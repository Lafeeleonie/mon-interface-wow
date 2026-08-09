local _, Addon = ...

local FEATURE_ID = "prey_hunt_icons"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PIN_TEMPLATES = {
    "AdventureMap_QuestOfferPinTemplate",
    "AdventureMap_QuestChoicePinTemplate",
}
local DIFFICULTY_KEYS = {
    [1] = "PVE_PREY_NORMAL",
    [2] = "PVE_PREY_HARD",
    [3] = "PVE_PREY_NIGHTMARE",
}

local Runtime = {
    enabled = false,
    map = nil,
    preview = nil,
    refreshGeneration = 0,
    initializeGeneration = 0,
    hookedMaps = setmetatable({}, { __mode = "k" }),
    hookedProviders = setmetatable({}, { __mode = "k" }),
    modifiedPins = setmetatable({}, { __mode = "k" }),
}

Addon.PreyHuntIcons = Runtime

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function getHuntMap()
    local missionFrame = _G.CovenantMissionFrame
    local map = missionFrame and missionFrame.MapTab or nil
    if map and type(map.EnumeratePinsByTemplate) == "function" then return map end
    return nil
end

local function safeCall(object, methodName, ...)
    local callback = object and object[methodName] or nil
    if type(callback) ~= "function" then return false end
    return pcall(callback, object, ...)
end

local function captureTextureState(texture)
    if not texture then return nil end
    local state = {
        left = 0,
        right = 1,
        top = 0,
        bottom = 1,
        alpha = 1,
    }
    if type(texture.GetTexture) == "function" then
        local ok, value = pcall(texture.GetTexture, texture)
        if ok then state.texture = value end
    end
    if type(texture.GetTexCoord) == "function" then
        local ok, left, right, top, bottom = pcall(texture.GetTexCoord, texture)
        if ok then
            state.left = tonumber(left) or 0
            state.right = tonumber(right) or 1
            state.top = tonumber(top) or 0
            state.bottom = tonumber(bottom) or 1
        end
    end
    if type(texture.GetWidth) == "function" then
        local ok, value = pcall(texture.GetWidth, texture)
        if ok then state.width = tonumber(value) end
    end
    if type(texture.GetHeight) == "function" then
        local ok, value = pcall(texture.GetHeight, texture)
        if ok then state.height = tonumber(value) end
    end
    if type(texture.GetAlpha) == "function" then
        local ok, value = pcall(texture.GetAlpha, texture)
        if ok then state.alpha = tonumber(value) or 1 end
    end
    if type(texture.IsShown) == "function" then
        local ok, value = pcall(texture.IsShown, texture)
        if ok then state.shown = value == true end
    end
    return state
end

local function restoreTextureState(texture, state)
    if not texture or type(state) ~= "table" then return end
    safeCall(texture, "SetTexture", state.texture)
    safeCall(
        texture,
        "SetTexCoord",
        state.left or 0,
        state.right or 1,
        state.top or 0,
        state.bottom or 1
    )
    if state.width and state.height then
        safeCall(texture, "SetSize", state.width, state.height)
    end
    safeCall(texture, "SetAlpha", state.alpha == nil and 1 or state.alpha)
    if state.shown == true then
        safeCall(texture, "Show")
    elseif state.shown == false then
        safeCall(texture, "Hide")
    end
end

local function getPinQuestID(pin)
    if pin == nil then return nil end
    local ok, questID = pcall(function()
        return pin.questID
            or pin.questId
            or (type(pin.questInfo) == "table" and (pin.questInfo.questID or pin.questInfo.questId))
            or (type(pin.pinData) == "table" and (pin.pinData.questID or pin.pinData.questId))
    end)
    questID = ok and tonumber(questID) or nil
    return questID and questID > 0 and math.floor(questID) or nil
end

local function isCriteriaCompleted(achievementID, criteriaID)
    if type(GetAchievementCriteriaInfoByID) ~= "function" then return nil end
    local ok, _, _, completed = pcall(
        GetAchievementCriteriaInfoByID,
        achievementID,
        criteriaID
    )
    if ok and type(completed) == "boolean" then return completed end
    return nil
end

local function findDataProviders(map)
    local providers = {}
    if not map or type(map.dataProviders) ~= "table" then return providers end
    for provider in pairs(map.dataProviders) do
        if provider and type(provider.RefreshAllData) == "function" then
            providers[#providers + 1] = provider
        end
    end
    return providers
end

function Runtime:StoreOriginalPinState(pin)
    if pin == nil or pin.VaultloomPreyPinState then return end
    pin.VaultloomPreyPinState = {
        icon = captureTextureState(pin.Icon),
        highlight = captureTextureState(pin.IconHighlight),
    }
end

function Runtime:RestorePin(pin)
    if pin == nil then return end
    local state = pin.VaultloomPreyPinState
    if type(state) == "table" then
        restoreTextureState(pin.Icon, state.icon)
        restoreTextureState(pin.IconHighlight, state.highlight)
        pin.VaultloomPreyPinState = nil
    end
    pin.VaultloomPreyPinModel = nil
    self.modifiedPins[pin] = nil
end

function Runtime:ApplyPin(pin, model)
    if pin == nil or not pin.Icon or type(model) ~= "table" then return end
    self:StoreOriginalPinState(pin)
    safeCall(pin.Icon, "SetTexture", Addon.Assets.preyHuntIcons)
    safeCall(pin.Icon, "SetTexCoord", model.left, model.right, model.top, model.bottom)
    safeCall(pin.Icon, "SetSize", model.size, model.size)

    if pin.IconHighlight then
        safeCall(pin.IconHighlight, "SetTexture", Addon.Assets.preyHuntIcons)
        safeCall(
            pin.IconHighlight,
            "SetTexCoord",
            model.left,
            model.right,
            model.top,
            model.bottom
        )
        safeCall(pin.IconHighlight, "SetSize", model.size, model.size)
        safeCall(pin.IconHighlight, "SetAlpha", 0.38)
    end
    pin.VaultloomPreyPinModel = model
    self.modifiedPins[pin] = true
end

function Runtime:RefreshPin(pin)
    local model
    if self.enabled == true then
        model = Addon.PreyHuntIconsLogic:BuildPinModel(
            getPinQuestID(pin),
            isCriteriaCompleted,
            setting("achievement_marker"),
            setting("icon_scale_percent")
        )
    end
    if model then
        self:ApplyPin(pin, model)
    else
        self:RestorePin(pin)
    end
end

function Runtime:ForEachMapPin(map, callback)
    if not map or type(callback) ~= "function" then return end
    for _, templateName in ipairs(PIN_TEMPLATES) do
        pcall(function()
            for pin in map:EnumeratePinsByTemplate(templateName) do
                callback(pin)
            end
        end)
    end
end

function Runtime:RefreshAllPins()
    local map = getHuntMap()
    if not map then
        if self.enabled ~= true then self:RestoreAllPins() end
        return false
    end
    self.map = map
    self:EnsureMapHooks()
    self:ForEachMapPin(map, function(pin)
        Runtime:RefreshPin(pin)
    end)
    return true
end

function Runtime:RestoreAllPins()
    local pins = {}
    for pin in pairs(self.modifiedPins) do pins[#pins + 1] = pin end
    for _, pin in ipairs(pins) do self:RestorePin(pin) end
end

function Runtime:RequestRefresh(delay)
    if self.enabled ~= true then return false end
    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local function refresh()
        if Runtime.enabled ~= true or Runtime.refreshGeneration ~= generation then return end
        local token = Addon.PerformanceDiagnostics:Begin(
            Runtime,
            "update",
            "prey_hunt_icons.refresh"
        )
        Runtime:RefreshAllPins()
        Addon.PerformanceDiagnostics:Finish(token)
    end
    delay = math.max(0, tonumber(delay) or 0)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, refresh)
    else
        refresh()
    end
    return true
end

function Runtime:EnsureMapHooks()
    local map = getHuntMap()
    if not map then return false end
    self.map = map

    if not self.hookedMaps[map] and type(map.HookScript) == "function" then
        self.hookedMaps[map] = true
        map:HookScript("OnShow", function()
            if Runtime.enabled then
                Runtime:EnsureMapHooks()
                Runtime:RequestRefresh(0)
            end
        end)
    end

    local providers = findDataProviders(map)
    if type(hooksecurefunc) == "function" then
        for _, provider in ipairs(providers) do
            if not self.hookedProviders[provider] then
                self.hookedProviders[provider] = true
                hooksecurefunc(provider, "RefreshAllData", function()
                    if Runtime.enabled then Runtime:RequestRefresh(0) end
                end)
            end
        end
    end
    return true, #providers
end

function Runtime:QueueInitialization()
    if self.enabled ~= true then return end
    self.initializeGeneration = self.initializeGeneration + 1
    local generation = self.initializeGeneration
    local delays = { 0, 0.10, 0.40, 1.00 }

    local function attempt(index)
        if Runtime.enabled ~= true or Runtime.initializeGeneration ~= generation then return end
        local mapReady, providerCount = Runtime:EnsureMapHooks()
        if mapReady then
            Runtime:RequestRefresh(0)
            if providerCount > 0 then return end
        end
        index = index + 1
        if index > #delays or not (C_Timer and type(C_Timer.After) == "function") then return end
        C_Timer.After(delays[index], function() attempt(index) end)
    end
    attempt(1)
end

function Runtime:IsMapShown()
    local map = getHuntMap()
    if not map then return false end
    if type(map.IsShown) ~= "function" then return true end
    local ok, shown = pcall(map.IsShown, map)
    return ok and shown == true
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= "Blizzard_GarrisonUI"
            and loadedName ~= "Blizzard_CovenantMissionUI"
        then
            return
        end
        self:QueueInitialization()
        return
    end
    if eventName == "PLAYER_ENTERING_WORLD" then
        self:QueueInitialization()
        return
    end
    if self:IsMapShown() then self:RequestRefresh(0) end
end

function Runtime:CreatePreviewIcon(parent)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Addon.Assets.preyHuntIcons)
    return icon
end

function Runtime:CreatePreview()
    local frame = CreateFrame(
        "Frame",
        "VaultloomPreyHuntIconPreview",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(590, 282)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 22, -20)
    frame.title:SetPoint("TOPRIGHT", -58, -20)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetText(Addon.L.PREY_ICONS_PREVIEW_TITLE)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", 22, -48)
    frame.subtitle:SetPoint("TOPRIGHT", -22, -48)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(Addon.L.PREY_ICONS_PREVIEW_SUBTITLE)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.readyHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.readyHeader:SetPoint("TOP", frame, "TOPLEFT", 338, -82)
    frame.readyHeader:SetText(Addon.L.PREY_ICONS_PREVIEW_READY)
    frame.readyHeader:SetTextColor(1, 0.82, 0.24, 1)
    frame.neededHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.neededHeader:SetPoint("TOP", frame, "TOPLEFT", 490, -82)
    frame.neededHeader:SetText(Addon.L.PREY_ICONS_PREVIEW_NEEDED)
    frame.neededHeader:SetTextColor(1, 0.82, 0.24, 1)

    frame.rows = {}
    for difficulty = 1, 3 do
        local row = {}
        local y = -128 - ((difficulty - 1) * 52)
        row.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", frame, "TOPLEFT", 28, y)
        row.label:SetWidth(176)
        row.label:SetJustifyH("LEFT")
        row.ready = self:CreatePreviewIcon(frame)
        row.ready:SetPoint("CENTER", frame, "TOPLEFT", 338, y)
        row.needed = self:CreatePreviewIcon(frame)
        row.needed:SetPoint("CENTER", frame, "TOPLEFT", 490, y)
        frame.rows[difficulty] = row
    end

    self.preview = frame
    frame:Hide()
end

function Runtime:RefreshPreview()
    if not self.preview or not self.preview:IsShown() then return end
    local showAchievement = setting("achievement_marker")
    local scale = setting("icon_scale_percent")
    for difficulty, row in ipairs(self.preview.rows) do
        row.label:SetText(Addon.L[DIFFICULTY_KEYS[difficulty]] or tostring(difficulty))
        local readyLeft, readyRight, readyTop, readyBottom =
            Addon.PreyHuntIconsLogic:GetIconCoords(difficulty, false)
        local neededLeft, neededRight, neededTop, neededBottom =
            Addon.PreyHuntIconsLogic:GetIconCoords(difficulty, showAchievement ~= false)
        local size = math.floor((38 * (tonumber(scale) or 100) / 100) + 0.5)
        row.ready:SetTexCoord(readyLeft, readyRight, readyTop, readyBottom)
        row.ready:SetSize(size, size)
        row.needed:SetTexCoord(neededLeft, neededRight, neededTop, neededBottom)
        row.needed:SetSize(size, size)
    end
end

function Runtime:TogglePreview()
    if not self.preview then self:CreatePreview() end
    if self.preview:IsShown() then
        self.preview:Hide()
    else
        self.preview:Show()
        if type(self.preview.Raise) == "function" then self.preview:Raise() end
        self:RefreshPreview()
    end
end

function Runtime:GetSettingValue(settingKey)
    if settingKey ~= "icon_scale_percent" and settingKey ~= "achievement_marker" then
        return nil
    end
    return Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey ~= "icon_scale_percent" and settingKey ~= "achievement_marker" then
        return false
    end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value
    self:RefreshPreview()
    if self.enabled then self:RequestRefresh(0) end
    return true
end

function Runtime:ResetSettingValues()
    self:RefreshPreview()
    if self.enabled then self:RequestRefresh(0) end
end

function Runtime:OnSettingsReset()
    self:RefreshPreview()
    self:RequestRefresh(0)
end

function Runtime:OnSettingsClosed()
    if self.preview then self.preview:Hide() end
end

function Runtime:OnAction(actionKey)
    if actionKey ~= "preview" then return false end
    self:TogglePreview()
    return true
end

function Runtime:OnEnable()
    self.enabled = true
    for _, eventName in ipairs({
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "CRITERIA_UPDATE",
        "ACHIEVEMENT_EARNED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:QueueInitialization()
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self.initializeGeneration = self.initializeGeneration + 1
    self:RestoreAllPins()
    if self.preview then self.preview:Hide() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Prey Hunt Icons runtime.")
end
