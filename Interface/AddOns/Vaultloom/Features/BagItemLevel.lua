local _, Addon = ...

local FEATURE_ID = "bag_item_level"
local ContainerItems = Addon.ContainerItems

local Runtime = {
    enabled = false,
    hooksReady = false,
    refreshGeneration = 0,
    trackedButtons = setmetatable({}, { __mode = "k" }),
}

Addon.BagItemLevel = Runtime

local function isFrameObject(value)
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

local function ensureFont()
    local font = _G.VaultloomBagItemLevelFont
    if font then
        return font
    end

    font = CreateFont("VaultloomBagItemLevelFont")
    font:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    font:SetShadowOffset(1, -1)
    font:SetShadowColor(0, 0, 0, 0.95)
    return font
end

local function ensureOverlay(button)
    local text = button and button.VaultloomBagItemLevelText or nil
    if text then
        return text
    end
    if not button or type(button.CreateFontString) ~= "function" then
        return nil
    end

    text = button:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(ensureFont())
    text:SetJustifyH("CENTER")
    text:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
    text:SetText("")
    text:Hide()
    button.VaultloomBagItemLevelText = text
    return text
end

local function hideOverlay(button)
    local text = isFrameObject(button) and button.VaultloomBagItemLevelText or nil
    if text then
        text:Hide()
    end
end

local function isExcludedItemContext(button)
    local frame = button
    local guard = 0
    while isFrameObject(frame) and guard < 8 do
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" and (name:find("^Quest") or name:find("^GossipFrame")) then
            return true
        end
        if type(name) == "string"
            and (
                name == "CharacterFrame"
                or name == "PaperDollFrame"
                or name:find("^Character.*Slot")
                or name:find("^Inspect")
            )
        then
            return true
        end
        frame = frame.GetParent and frame:GetParent() or nil
        guard = guard + 1
    end
    return false
end

local function getItemDescriptor(itemLink)
    local equipLocation
    local classID

    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, resolvedEquipLocation, _, resolvedClassID = pcall(C_Item.GetItemInfoInstant, itemLink)
        if ok then
            equipLocation = resolvedEquipLocation
            classID = resolvedClassID
        end
    end

    if (type(equipLocation) ~= "string" or equipLocation == "") and type(GetItemInfo) == "function" then
        local ok, _, _, _, _, _, _, _, _, resolvedEquipLocation, _, _, resolvedClassID = pcall(GetItemInfo, itemLink)
        if ok then
            equipLocation = resolvedEquipLocation
            classID = classID or resolvedClassID
        end
    end

    return equipLocation, classID
end

local function getDetailedItemLevel(itemLink)
    if C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local ok, itemLevel = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(itemLevel) then
            return tonumber(itemLevel)
        end
    end
    if type(GetDetailedItemLevelInfo) == "function" then
        local ok, itemLevel = pcall(GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(itemLevel) then
            return tonumber(itemLevel)
        end
    end
    return nil
end

local function resolveItemLevel(itemLink, itemLocation)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    if type(IsEquippableItem) ~= "function" then
        return nil
    end
    local okEquippable, isEquippable = pcall(IsEquippableItem, itemLink)
    if not okEquippable or not isEquippable then
        return nil
    end

    local equipLocation, classID = getItemDescriptor(itemLink)
    local weaponClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    local armorClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
    if type(equipLocation) ~= "string" or equipLocation == "" or equipLocation == "INVTYPE_BAG" then
        return nil
    end
    if classID ~= weaponClassID and classID ~= armorClassID then
        return nil
    end

    local itemLevel
    if itemLocation and C_Item
        and type(C_Item.DoesItemExist) == "function"
        and type(C_Item.GetCurrentItemLevel) == "function"
    then
        local okExists, exists = pcall(C_Item.DoesItemExist, itemLocation)
        if okExists and exists then
            local okLevel, currentLevel = pcall(C_Item.GetCurrentItemLevel, itemLocation)
            if okLevel then
                itemLevel = tonumber(currentLevel)
            end
        end
    end

    itemLevel = itemLevel or getDetailedItemLevel(itemLink)
    if not itemLevel or itemLevel <= 0 then
        return nil
    end
    return math.floor(itemLevel + 0.5)
end

local function getButtonItemLevel(button)
    local bagID, slotID = ContainerItems:GetButtonBagAndSlot(button)
    local itemLink = ContainerItems:GetButtonItemLink(button, bagID, slotID)
    if not itemLink then
        return nil, nil, bagID, slotID
    end

    local itemLocation
    if bagID ~= nil and slotID ~= nil
        and ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function"
    then
        local ok, resolvedLocation = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bagID, slotID)
        if ok then
            itemLocation = resolvedLocation
        end
    elseif type(button.GetItemLocation) == "function" then
        local ok, resolvedLocation = pcall(button.GetItemLocation, button)
        if ok then
            itemLocation = resolvedLocation
        end
    else
        itemLocation = button.itemLocation or button.ItemLocation
    end

    return resolveItemLevel(itemLink, itemLocation), itemLink, bagID, slotID
end

local function getTextColor(bagID, slotID, itemLink)
    if Addon.FeatureRegistry:GetSetting(FEATURE_ID, "text_style") ~= "quality" then
        return 1, 1, 1
    end

    local quality = ContainerItems:GetQuality(bagID, slotID, itemLink)
    local color = quality ~= nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or nil
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

function Runtime:TrackButton(button)
    if self.enabled ~= true
        or not isFrameObject(button)
        or (button.IsForbidden and button:IsForbidden())
        or isExcludedItemContext(button)
    then
        hideOverlay(button)
        return false
    end

    local name = button.GetName and button:GetName() or nil
    local hasItemContext = type(button.GetSlotAndBagID) == "function"
        or type(button.GetBagID) == "function"
        or type(button.GetItem) == "function"
        or type(button.GetItemLocation) == "function"
        or button.itemLocation ~= nil
        or button.itemLink ~= nil
        or button.hyperlink ~= nil
        or (type(name) == "string" and name:find("Item", 1, true) and ContainerItems:GetButtonIcon(button))
    if not hasItemContext then
        return false
    end

    local bagID, slotID = ContainerItems:GetButtonBagAndSlot(button)
    if (bagID == nil or slotID == nil) and not ContainerItems:GetButtonItemLink(button, bagID, slotID) then
        return false
    end

    self.trackedButtons[button] = true
    if button.VaultloomBagItemLevelHooked ~= true and type(button.HookScript) == "function" then
        button.VaultloomBagItemLevelHooked = true
        button:HookScript("OnShow", function(shownButton)
            if Runtime.enabled == true then
                Runtime:RefreshButton(shownButton)
            end
        end)
        button:HookScript("OnHide", hideOverlay)
    end
    return true
end

function Runtime:RefreshButton(button)
    if not isFrameObject(button) then
        return
    end
    if self.enabled ~= true or (button.IsShown and not button:IsShown()) or isExcludedItemContext(button) then
        hideOverlay(button)
        return
    end
    if not self:TrackButton(button) then
        hideOverlay(button)
        return
    end

    local itemLevel, itemLink, bagID, slotID = getButtonItemLevel(button)
    if not itemLevel then
        hideOverlay(button)
        return
    end

    local text = ensureOverlay(button)
    if not text then
        return
    end
    local red, green, blue = getTextColor(bagID, slotID, itemLink)
    text:SetText(itemLevel)
    text:SetTextColor(red, green, blue, 1)
    text:Show()
end

function Runtime:RefreshContainer(frame)
    if self.enabled ~= true
        or not isFrameObject(frame)
        or (frame.IsShown and not frame:IsShown())
        or type(frame.EnumerateValidItems) ~= "function"
    then
        return
    end

    for firstValue, secondValue in frame:EnumerateValidItems() do
        -- Blizzard containers may expose valid items as either index -> button
        -- or button -> true. Prefer whichever iterator value is the frame.
        local button = isFrameObject(secondValue) and secondValue
            or (isFrameObject(firstValue) and firstValue or nil)
        if button then
            self:RefreshButton(button)
        end
    end
end

local function forEachVisibleDescendantButton(rootFrame, callback)
    if not isFrameObject(rootFrame)
        or (rootFrame.IsShown and not rootFrame:IsShown())
        or type(callback) ~= "function"
    then
        return
    end

    local stack = { rootFrame }
    local visited = {}
    while #stack > 0 do
        local frame = table.remove(stack)
        if not visited[frame] then
            visited[frame] = true
            if frame ~= rootFrame and frame.IsObjectType and frame:IsObjectType("Button") then
                callback(frame)
            end
            if frame.GetChildren then
                for _, child in ipairs({ frame:GetChildren() }) do
                    if isFrameObject(child) then
                        stack[#stack + 1] = child
                    end
                end
            end
        end
    end
end

local function isVisible(frame)
    return isFrameObject(frame) and (not frame.IsShown or frame:IsShown())
end

function Runtime:RefreshBankButtons()
    for _, rootFrame in pairs({
        _G.PlayerBankPanel,
        _G.BankFrame,
        _G.BankPanel,
        _G.ReagentBankFrame,
        _G.AccountBankPanel,
        _G.AccountBankFrame,
        _G.WarbandBankFrame,
    }) do
        if isVisible(rootFrame) then
            self:RefreshContainer(rootFrame)
            forEachVisibleDescendantButton(rootFrame, function(button)
                self:RefreshButton(button)
            end)
        end
    end

    for _, entry in ipairs({
        { prefix = "BankFrameItem", maxCount = tonumber(NUM_BANKGENERIC_SLOTS) or 28 },
        { prefix = "BankPanelItem", maxCount = tonumber(NUM_BANKGENERIC_SLOTS) or 28 },
        { prefix = "ReagentBankFrameItem", maxCount = tonumber(NUM_REAGENTBANKGENERIC_SLOTS) or 98 },
    }) do
        for index = 1, entry.maxCount do
            local button = _G[entry.prefix .. index]
            if isVisible(button) and isVisible(button.GetParent and button:GetParent() or nil) then
                self:RefreshButton(button)
            end
        end
    end
end

function Runtime:RefreshVisible()
    if self.enabled ~= true then
        return
    end

    local combinedBags = _G.ContainerFrameCombinedBags
    if isVisible(combinedBags) then
        self:RefreshContainer(combinedBags)
    end

    local containerCount = tonumber(NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES) or 0
    for index = 1, containerCount do
        local frame = _G["ContainerFrame" .. index]
        if frame ~= combinedBags and isVisible(frame) then
            self:RefreshContainer(frame)
        end
    end

    self:RefreshBankButtons()
    for button in pairs(self.trackedButtons) do
        if isVisible(button) then
            self:RefreshButton(button)
        else
            hideOverlay(button)
        end
    end
end

function Runtime:HideAll()
    for button in pairs(self.trackedButtons) do
        hideOverlay(button)
    end
end

function Runtime:ScheduleRefresh(delaySeconds)
    if self.enabled ~= true then
        return
    end

    local generation = self.refreshGeneration
    local callback = function()
        if Runtime.enabled == true and Runtime.refreshGeneration == generation then
            Runtime:RefreshVisible()
        end
    end

    delaySeconds = tonumber(delaySeconds) or 0
    if delaySeconds > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(
            delaySeconds,
            Addon.PerformanceDiagnostics:Wrap(Runtime, "timer", "bag_item_level.refresh", callback)
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Runtime,
            "timer",
            "bag_item_level.refresh",
            callback
        )
        wrapped()
    end
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return
    end
    self.hooksReady = true

    if type(hooksecurefunc) ~= "function" then
        return
    end

    local function refreshContainer(frame)
        if Runtime.enabled == true then
            Runtime:RefreshContainer(frame)
        end
    end
    local function refreshButton(button)
        if Runtime.enabled == true then
            Runtime:RefreshButton(button)
        end
    end

    if type(ContainerFrameMixin) == "table" and type(ContainerFrameMixin.UpdateItems) == "function" then
        hooksecurefunc(ContainerFrameMixin, "UpdateItems", refreshContainer)
    end
    if type(ContainerFrameItemButtonMixin) == "table" and type(ContainerFrameItemButtonMixin.OnLoad) == "function" then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnLoad", refreshButton)
    end
    if type(SetItemButtonQuality) == "function" then
        hooksecurefunc("SetItemButtonQuality", refreshButton)
    end

    local combinedBags = _G.ContainerFrameCombinedBags
    if combinedBags and type(combinedBags.UpdateItems) == "function" then
        hooksecurefunc(combinedBags, "UpdateItems", refreshContainer)
    end
    local containerCount = tonumber(NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES) or 0
    for index = 1, containerCount do
        local frame = _G["ContainerFrame" .. index]
        if frame and frame ~= combinedBags and type(frame.UpdateItems) == "function" then
            hooksecurefunc(frame, "UpdateItems", refreshContainer)
        end
    end

    for _, frame in pairs({
        _G.PlayerBankPanel,
        _G.BankFrame,
        _G.BankPanel,
        _G.ReagentBankFrame,
        _G.AccountBankPanel,
        _G.AccountBankFrame,
        _G.WarbandBankFrame,
    }) do
        if frame and type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function()
                if Runtime.enabled == true then
                    Runtime:ScheduleRefresh(0)
                    Runtime:ScheduleRefresh(0.1)
                    Runtime:ScheduleRefresh(0.25)
                end
            end)
        end
    end
end

local delayedRefreshEvents = {
    BANKFRAME_OPENED = true,
    PLAYERBANKSLOTS_CHANGED = true,
    PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
    PLAYER_ENTERING_WORLD = true,
}

function Runtime:HandleEvent(eventName)
    if self.enabled ~= true then
        return
    end
    self:RefreshVisible()
    if delayedRefreshEvents[eventName] then
        self:ScheduleRefresh(0.1)
        self:ScheduleRefresh(0.25)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshGeneration = self.refreshGeneration + 1
    self:EnsureHooks()

    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED",
        "BANKFRAME_OPENED",
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(dispatchedEvent)
            Runtime:HandleEvent(dispatchedEvent)
        end)
    end

    self:RefreshVisible()
    self:ScheduleRefresh(0.1)
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self:HideAll()
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "text_style" then
        self:RefreshVisible()
    end
end

function Runtime:OnSettingsReset()
    self:RefreshVisible()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Bag Item Level feature runtime.")
end
