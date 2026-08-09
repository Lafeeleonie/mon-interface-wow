local _, Addon = ...

local FEATURE_ID = "auto_sell_junk"
local START_DELAY_SECONDS = 0.15
local RETRY_DELAY_SECONDS = 0.15
local SETTLE_DELAY_SECONDS = 0.12
local MAX_START_ATTEMPTS = 3
local MAX_SETTLE_ATTEMPTS = 5

local NO_SELL_MERCHANT_NPC_IDS = {
    [207283] = true, -- Delvers' Supplies / Vorräte der Tiefenforscher
}

local NO_SELL_MERCHANT_NAMES = {
    ["delver's supplies"] = true,
    ["delvers' supplies"] = true,
    ["explorers' league supplies"] = true,
    ["vorräte der forscherliga"] = true,
    ["vorräte der tiefenforscher"] = true,
}

local Runtime = {
    enabled = false,
    sessionActive = false,
    sessionSuppressed = false,
    sellAttempted = false,
    pendingSale = false,
    generation = 0,
    startToken = 0,
    settleToken = 0,
    startAttempts = 0,
    settleAttempts = 0,
    moneyBefore = nil,
    junkBefore = 0,
    sessionEarned = 0,
    lastObservedMoney = nil,
    lastObservedJunk = nil,
    stableObservations = 0,
}

Addon.AutoSellJunk = Runtime

local function getSetting(settingKey)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, settingKey)
end

local function getMoneyAmount()
    if type(GetMoney) ~= "function" then
        return nil
    end
    local ok, amount = pcall(GetMoney)
    if ok and tonumber(amount) then
        return math.max(0, math.floor(tonumber(amount)))
    end
    return nil
end

local function formatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))

    if C_CurrencyInfo and type(C_CurrencyInfo.GetCoinTextureString) == "function" then
        local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper, 12)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end

    if type(GetCoinTextureString) == "function" then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end

    if type(GetMoneyString) == "function" then
        local ok, text = pcall(GetMoneyString, copper)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end

    return tostring(copper) .. "c"
end

local function getNativeJunkCount()
    if not C_MerchantFrame or type(C_MerchantFrame.GetNumJunkItems) ~= "function" then
        return nil
    end
    local ok, count = pcall(C_MerchantFrame.GetNumJunkItems)
    if ok and tonumber(count) then
        return math.max(0, math.floor(tonumber(count)))
    end
    return nil
end

local function nativeSellAllEnabled()
    if not C_MerchantFrame or type(C_MerchantFrame.IsSellAllJunkEnabled) ~= "function" then
        return false, "missing"
    end
    local ok, enabled = pcall(C_MerchantFrame.IsSellAllJunkEnabled)
    if not ok then
        return false, tostring(enabled)
    end
    return enabled == true
end

local function merchantFrameOpen()
    if not MerchantFrame or type(MerchantFrame.IsShown) ~= "function" then
        return false
    end
    if type(MerchantFrame.IsForbidden) == "function" and MerchantFrame:IsForbidden() then
        return false
    end
    return MerchantFrame:IsShown() == true
end

local function getSafeMerchantName()
    local logic = Addon.MerchantFiltersLogic
    if not logic then return nil end

    if type(UnitName) == "function" then
        for _, unit in ipairs({ "npc", "target", "mouseover" }) do
            local ok, name = pcall(UnitName, unit)
            if ok
                and not logic:IsSecretValue(name)
                and type(name) == "string"
                and name ~= ""
            then
                return name
            end
        end
    end

    local titleRegions = {}
    local function addTitleRegion(region)
        if region then titleRegions[#titleRegions + 1] = region end
    end
    addTitleRegion(_G.MerchantFrameTitleText)
    addTitleRegion(MerchantFrame and MerchantFrame.TitleText)
    addTitleRegion(MerchantFrame and MerchantFrame.TitleContainer
        and MerchantFrame.TitleContainer.TitleText)
    for _, region in ipairs(titleRegions) do
        if region and type(region.GetText) == "function" then
            local ok, title = pcall(region.GetText, region)
            if ok
                and not logic:IsSecretValue(title)
                and type(title) == "string"
                and title ~= ""
            then
                return title
            end
        end
    end
    return nil
end

function Runtime:IsNoSellMerchant()
    local logic = Addon.MerchantFiltersLogic
    if not logic then return false end

    if type(UnitGUID) == "function" then
        for _, unit in ipairs({ "npc", "target", "mouseover" }) do
            local ok, guid = pcall(UnitGUID, unit)
            local npcID = ok and logic:GetNPCIDFromGUID(guid) or nil
            if npcID and NO_SELL_MERCHANT_NPC_IDS[npcID] then return true end
        end
    end

    local name = getSafeMerchantName()
    if not name then return false end
    return NO_SELL_MERCHANT_NAMES[logic:NormalizeText(name)] == true
end

function Runtime:InvalidateTimers()
    self.startToken = self.startToken + 1
    self.settleToken = self.settleToken + 1
end

function Runtime:ResetSession()
    self:InvalidateTimers()
    self.sessionActive = false
    self.sessionSuppressed = false
    self.sellAttempted = false
    self.pendingSale = false
    self.startAttempts = 0
    self.settleAttempts = 0
    self.moneyBefore = nil
    self.junkBefore = 0
    self.sessionEarned = 0
    self.lastObservedMoney = nil
    self.lastObservedJunk = nil
    self.stableObservations = 0
end

function Runtime:FinishSale(earned)
    earned = math.max(0, math.floor(tonumber(earned) or 0))
    self.pendingSale = false
    self.settleToken = self.settleToken + 1
    self.moneyBefore = nil
    self.sessionEarned = earned

    if earned > 0 and getSetting("show_summary") ~= false then
        Addon:Print(string.format(
            Addon.L.FEATURE_AUTO_SELL_JUNK_SOLD or "Automatically sold junk for %s.",
            formatMoney(earned)
        ))
    end
end

function Runtime:ObserveSaleResult(generation)
    if not self.enabled
        or not self.sessionActive
        or generation ~= self.generation
        or not self.pendingSale
    then
        return
    end

    self.settleAttempts = self.settleAttempts + 1
    local moneyNow = getMoneyAmount()
    local junkNow = getNativeJunkCount()
    local earned = 0
    if moneyNow ~= nil and self.moneyBefore ~= nil then
        earned = math.max(0, moneyNow - self.moneyBefore)
    end
    if earned > self.sessionEarned then
        self.sessionEarned = earned
    end

    if moneyNow == self.lastObservedMoney and junkNow == self.lastObservedJunk then
        self.stableObservations = self.stableObservations + 1
    else
        self.stableObservations = 0
        self.lastObservedMoney = moneyNow
        self.lastObservedJunk = junkNow
    end

    local junkSaleFinished = junkNow == nil or junkNow <= 0
    if self.sessionEarned > 0
        and junkSaleFinished
        and self.stableObservations >= 2
    then
        self:FinishSale(self.sessionEarned)
        return
    end

    if self.settleAttempts >= MAX_SETTLE_ATTEMPTS then
        if self.sessionEarned > 0 then
            self:FinishSale(self.sessionEarned)
        else
            self.pendingSale = false
            self.moneyBefore = nil
        end
        return
    end

    self:ScheduleSettlement(SETTLE_DELAY_SECONDS, generation)
end

function Runtime:ScheduleSettlement(delay, generation)
    if not self.enabled or not self.pendingSale then
        return false
    end

    self.settleToken = self.settleToken + 1
    local token = self.settleToken
    local function settle()
        if token == Runtime.settleToken then
            Runtime:ObserveSaleResult(generation)
        end
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or SETTLE_DELAY_SECONDS, settle)
    else
        settle()
    end
    return true
end

function Runtime:TrySell(generation)
    if not self.enabled
        or not self.sessionActive
        or self.sessionSuppressed
        or self.sellAttempted
        or generation ~= self.generation
    then
        return
    end

    self.startAttempts = self.startAttempts + 1

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self.sellAttempted = true
        return
    end

    local canSell, apiError = nativeSellAllEnabled()
    local junkCount = getNativeJunkCount()
    if not canSell or junkCount == nil or junkCount <= 0 then
        if self.startAttempts < MAX_START_ATTEMPTS then
            self:ScheduleStart(RETRY_DELAY_SECONDS, generation)
        elseif apiError == "missing" or junkCount == nil then
            Addon.Logger:Write(
                "WARN",
                "auto_sell_junk.api",
                "Blizzard's native sell-all-junk API is unavailable; no items were sold."
            )
        end
        return
    end

    if not C_MerchantFrame or type(C_MerchantFrame.SellAllJunkItems) ~= "function" then
        self.sellAttempted = true
        Addon.Logger:Write(
            "WARN",
            "auto_sell_junk.api",
            "Blizzard's native sell-all-junk action is unavailable; no items were sold."
        )
        return
    end

    self.sellAttempted = true
    self.pendingSale = true
    self.settleAttempts = 0
    self.moneyBefore = getMoneyAmount()
    self.junkBefore = junkCount
    self.sessionEarned = 0
    self.lastObservedMoney = nil
    self.lastObservedJunk = nil
    self.stableObservations = 0

    local ok, errorMessage = pcall(C_MerchantFrame.SellAllJunkItems)
    if not ok then
        self.pendingSale = false
        self.moneyBefore = nil
        Addon.Logger:Write(
            "ERROR",
            "auto_sell_junk.sell",
            "Blizzard rejected the automatic junk sale: %s",
            tostring(errorMessage)
        )
        return
    end

    self:ScheduleSettlement(SETTLE_DELAY_SECONDS, generation)
end

function Runtime:ScheduleStart(delay, generation)
    if not self.enabled or not self.sessionActive then
        return false
    end

    self.startToken = self.startToken + 1
    local token = self.startToken
    local function start()
        if token == Runtime.startToken then
            Runtime:TrySell(generation)
        end
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or START_DELAY_SECONDS, start)
    else
        start()
    end
    return true
end

function Runtime:BeginSession()
    self:ResetSession()
    self.generation = self.generation + 1
    self.sessionActive = true

    if self:IsNoSellMerchant() then
        self.sessionSuppressed = true
        return
    end

    if getSetting("pause_with_shift") ~= false
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown()
    then
        self.sessionSuppressed = true
        return
    end

    self:ScheduleStart(START_DELAY_SECONDS, self.generation)
end

function Runtime:OnEvent(eventName)
    if eventName == "MERCHANT_SHOW" then
        self:BeginSession()
        return
    end

    if eventName == "MERCHANT_CLOSED" then
        self.generation = self.generation + 1
        self:ResetSession()
        return
    end

    if not self.sessionActive then
        return
    end

    if self.pendingSale then
        self:ScheduleSettlement(SETTLE_DELAY_SECONDS, self.generation)
    elseif not self.sellAttempted
        and not self.sessionSuppressed
        and self.startAttempts < MAX_START_ATTEMPTS
        and eventName == "MERCHANT_UPDATE"
    then
        self:ScheduleStart(0.05, self.generation)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:ResetSession()

    local function onEvent(eventName)
        Runtime:OnEvent(eventName)
    end
    Addon.EventBus:Subscribe("MERCHANT_SHOW", self, onEvent)
    Addon.EventBus:Subscribe("MERCHANT_CLOSED", self, onEvent)
    Addon.EventBus:Subscribe("MERCHANT_UPDATE", self, onEvent)
    Addon.EventBus:Subscribe("BAG_UPDATE_DELAYED", self, onEvent)
    Addon.EventBus:Subscribe("PLAYER_MONEY", self, onEvent)

    if merchantFrameOpen() then
        self:BeginSession()
    end
end

function Runtime:OnDisable()
    self.enabled = false
    self.generation = self.generation + 1
    self:ResetSession()
end

Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime)
