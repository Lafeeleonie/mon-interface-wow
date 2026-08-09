local _, Addon = ...

local FEATURE_ID = "one_click_processing"
local Logic = Addon.OneClickProcessingLogic
local ContainerItems = Addon.ContainerItems

local COLORS = {
    mill = { 0.18, 0.86, 0.42 },
    prospect = { 0.28, 0.74, 1.00 },
    disenchant = { 0.66, 0.48, 1.00 },
    open = { 1.00, 0.78, 0.26 },
}

local MACRO_SALVAGE = "/run C_TradeSkillUI.CraftSalvage(%d,1,ItemLocation:CreateFromBagAndSlot(%d,%d))"

local Runtime = {
    enabled = false,
    hooksReady = false,
    refreshGeneration = 0,
    salvageIndex = {},
    disenchantItems = {},
    disenchantAuthoritative = false,
    equipmentSetItems = {},
}

Addon.OneClickProcessing = Runtime

local function isCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function isSpellKnown(spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return false
    end

    local checker = C_SpellBook
        and (C_SpellBook.IsSpellKnownOrOverridesKnown or C_SpellBook.IsSpellKnown)
    if type(checker) == "function" then
        local ok, known = pcall(checker, spellID)
        if ok and known == true then
            return true
        end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, spellID)
        return ok and known == true
    end
    return false
end

local function isRecipeKnown(recipeID)
    if C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.learned == true then
            return true
        end
    end
    return isSpellKnown(recipeID)
end

local function getItemID(itemLink, fallback)
    local itemID = tonumber(fallback)
    if itemID then
        return itemID
    end
    if type(itemLink) == "string" then
        return tonumber(itemLink:match("item:(%d+)"))
    end
    return nil
end

local function createBagLocation(bagID, slotID)
    if not (ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function") then
        return nil
    end
    local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bagID, slotID)
    return ok and location or nil
end

local function getSalvagableItemIDs(recipeID)
    if not (C_TradeSkillUI and type(C_TradeSkillUI.GetSalvagableItemIDs) == "function") then
        return nil
    end
    local ok, values = pcall(C_TradeSkillUI.GetSalvagableItemIDs, recipeID)
    return ok and values or nil
end

local function getModifierState()
    local altDown = type(IsAltKeyDown) == "function" and IsAltKeyDown() == true
    local shiftDown = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    local controlDown = type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
    return altDown, shiftDown, controlDown
end

function Runtime:IsModifierActive()
    local altDown, shiftDown, controlDown = getModifierState()
    return Logic:ModifierMatches(
        Addon.FeatureRegistry:GetSetting(FEATURE_ID, "modifier"),
        altDown,
        shiftDown,
        controlDown
    )
end

function Runtime:GetModifierLabel()
    local value = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "modifier")
    if value == "alt_shift" then
        return Addon.L.FEATURE_VALUE_ALT_SHIFT or "Alt + Shift"
    end
    if value == "alt_ctrl" then
        return Addon.L.FEATURE_VALUE_ALT_CTRL or "Alt + Ctrl"
    end
    return Addon.L.FEATURE_VALUE_ALT or "Alt"
end

function Runtime:GetActionLabel(kind)
    local keys = {
        mill = "ONE_CLICK_ACTION_MILL",
        prospect = "ONE_CLICK_ACTION_PROSPECT",
        disenchant = "ONE_CLICK_ACTION_DISENCHANT",
        open = "ONE_CLICK_ACTION_OPEN",
    }
    return Addon.L[keys[kind]] or tostring(kind or "")
end

function Runtime:GetSpellIcon(spellID)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    if type(GetSpellTexture) == "function" then
        local ok, icon = pcall(GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return 134400
end

function Runtime:RebuildProcessingData()
    self.salvageIndex, self.salvageStats = Logic:BuildSalvageIndex(
        getSalvagableItemIDs,
        isRecipeKnown
    )
    self.disenchantItems, self.disenchantAuthoritative = Logic:BuildDisenchantSet(
        getSalvagableItemIDs,
        isSpellKnown
    )
end

function Runtime:RebuildEquipmentSetItems()
    local result = {}
    if C_EquipmentSet
        and type(C_EquipmentSet.GetEquipmentSetIDs) == "function"
        and type(C_EquipmentSet.GetItemIDs) == "function"
    then
        local okSets, setIDs = pcall(C_EquipmentSet.GetEquipmentSetIDs)
        if okSets and type(setIDs) == "table" then
            for _, setID in pairs(setIDs) do
                local okItems, itemIDs = pcall(C_EquipmentSet.GetItemIDs, setID)
                if okItems and type(itemIDs) == "table" then
                    for _, itemID in pairs(itemIDs) do
                        itemID = tonumber(itemID)
                        if itemID and itemID > 0 then
                            result[itemID] = true
                        end
                    end
                end
            end
        end
    end
    self.equipmentSetItems = result
end

function Runtime:RebuildDisenchantData()
    self.disenchantItems, self.disenchantAuthoritative = Logic:BuildDisenchantSet(
        getSalvagableItemIDs,
        isSpellKnown
    )
end

function Runtime:GetTooltipContext(tooltip, data)
    local owner = tooltip and type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
    local bagID, slotID = ContainerItems:GetButtonBagAndSlot(owner)
    local itemLink = bagID ~= nil and slotID ~= nil
        and ContainerItems:GetItemLink(bagID, slotID)
        or nil

    if (bagID == nil or slotID == nil)
        and type(data) == "table"
        and data.guid
        and C_Item
        and type(C_Item.GetItemLocation) == "function"
    then
        local okLocation, itemLocation = pcall(C_Item.GetItemLocation, data.guid)
        if okLocation and itemLocation
            and type(itemLocation.IsBagAndSlot) == "function"
            and itemLocation:IsBagAndSlot()
            and type(itemLocation.GetBagAndSlot) == "function"
        then
            bagID, slotID = itemLocation:GetBagAndSlot()
            itemLink = ContainerItems:GetItemLink(bagID, slotID)
        end
    end

    if type(itemLink) ~= "string" or itemLink == "" then
        itemLink = ContainerItems:GetButtonItemLink(owner, bagID, slotID)
    end

    return owner, tonumber(bagID), tonumber(slotID), itemLink
end

function Runtime:BuildItemContext(bagID, slotID)
    bagID = tonumber(bagID)
    slotID = tonumber(slotID)
    if not bagID or not slotID or bagID < 0 or bagID > 5 then
        return nil
    end

    local info
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, value = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(value) == "table" then
            info = value
        end
    end
    info = info or {}

    local itemLink = info.hyperlink or ContainerItems:GetItemLink(bagID, slotID)
    local itemID = getItemID(itemLink, info.itemID)
    if not itemID then
        return nil
    end

    local location = createBagLocation(bagID, slotID)
    local equipLocation
    local classID
    local subClassID
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, resolvedEquipLocation, _, resolvedClassID, resolvedSubClassID =
            pcall(C_Item.GetItemInfoInstant, itemLink or itemID)
        if ok then
            equipLocation = resolvedEquipLocation
            classID = tonumber(resolvedClassID)
            subClassID = tonumber(resolvedSubClassID)
        end
    end

    local isRefundable = false
    if location and C_Item and type(C_Item.CanBeRefunded) == "function" then
        local ok, value = pcall(C_Item.CanBeRefunded, location)
        isRefundable = ok and value == true
    end

    local isLocked = info.isLocked == true
    if location and C_Item and type(C_Item.IsLocked) == "function" then
        local ok, value = pcall(C_Item.IsLocked, location)
        if ok then
            isLocked = value == true
        end
    end

    local isCosmetic = false
    if C_Item and type(C_Item.IsCosmeticItem) == "function" then
        local ok, value = pcall(C_Item.IsCosmeticItem, itemID)
        isCosmetic = ok and value == true
    end

    return {
        bagID = bagID,
        slotID = slotID,
        itemID = itemID,
        itemLink = itemLink,
        itemLocation = location,
        stackCount = tonumber(info.stackCount or info.quantity) or 1,
        quality = tonumber(info.quality or info.qualityID)
            or ContainerItems:GetQuality(bagID, slotID, itemLink),
        equipLocation = equipLocation,
        classID = classID,
        subClassID = subClassID,
        isLocked = isLocked,
        isRefundable = isRefundable,
        isCosmetic = isCosmetic,
        inEquipmentSet = self.equipmentSetItems[itemID] == true,
    }
end

function Runtime:ResolveAction(context)
    local action = Logic:ResolveAction(context, {
        salvageIndex = self.salvageIndex,
        disenchantItems = self.disenchantItems,
        disenchantAuthoritative = self.disenchantAuthoritative,
        allowRareEpic = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "disenchant_rare_epic") == true,
        playerLevel = type(UnitLevel) == "function" and UnitLevel("player") or 0,
        isSpellKnown = isSpellKnown,
    })
    if action then
        action.label = self:GetActionLabel(action.kind)
        action.color = COLORS[action.kind] or COLORS.open
        action.icon = self:GetSpellIcon(action.recipeID or action.spellID)
    end
    return action
end

local function createBorder(button, pointA, relativePointA, pointB, relativePointB)
    local texture = button:CreateTexture(nil, "OVERLAY", nil, 4)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetPoint(pointA, button, relativePointA, 0, 0)
    texture:SetPoint(pointB, button, relativePointB, 0, 0)
    return texture
end

local function setButtonActionType(button, actionType)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("alt-type1", actionType)
    button:SetAttribute("alt-shift-type1", actionType)
    button:SetAttribute("alt-ctrl-type1", actionType)
end

function Runtime:EnsureButton()
    if self.button then
        return self.button
    end

    local button = CreateFrame(
        "Button",
        "VaultloomOneClickProcessingButton",
        UIParent,
        "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate"
    )
    button:SetFrameStrata("TOOLTIP")
    button:SetSize(38, 38)
    button:RegisterForClicks("LeftButtonUp")
    button:EnableMouse(true)
    button:Hide()

    button.tint = button:CreateTexture(nil, "BACKGROUND")
    button.tint:SetAllPoints(button)

    button.borderTop = createBorder(button, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT")
    button.borderTop:SetHeight(1)
    button.borderBottom = createBorder(button, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT")
    button.borderBottom:SetHeight(1)
    button.borderLeft = createBorder(button, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT")
    button.borderLeft:SetWidth(1)
    button.borderRight = createBorder(button, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT")
    button.borderRight:SetWidth(1)

    button.badge = button:CreateTexture(nil, "OVERLAY", nil, 5)
    button.badge:SetSize(15, 15)
    button.badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetScript("OnShow", function()
        Runtime:AnchorButton()
    end)
    button:SetScript("OnEnter", function(enteredButton)
        Runtime:ShowButtonTooltip(enteredButton)
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip and type(GameTooltip.Hide) == "function" then
            GameTooltip:Hide()
        end
        Runtime:HideButton()
    end)
    button:SetAttribute("_onleave", "self:Hide()")

    self.button = button
    return button
end

function Runtime:ApplyAttributes(action, bagID, slotID)
    local button = self:EnsureButton()
    if isCombatLocked() then
        return false
    end

    button:SetAttribute("target-bag", bagID)
    button:SetAttribute("target-slot", slotID)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", nil)

    local spellID = tonumber(action.recipeID or action.spellID)
    if action.itemID then
        button:SetAttribute("item", "item:" .. tostring(action.itemID))
        setButtonActionType(button, "item")
    elseif spellID then
        local useSalvageMacro = C_TradeSkillUI
            and type(C_TradeSkillUI.CraftSalvage) == "function"
            and ItemLocation
            and type(ItemLocation.CreateFromBagAndSlot) == "function"
            and (type(FindSpellBookSlotBySpellID) ~= "function"
                or not FindSpellBookSlotBySpellID(spellID))
        if useSalvageMacro then
            button:SetAttribute(
                "macrotext",
                string.format(MACRO_SALVAGE, spellID, bagID, slotID)
            )
            setButtonActionType(button, "macro")
        else
            button:SetAttribute("spell", spellID)
            setButtonActionType(button, "spell")
        end
    else
        return false
    end

    return true
end

function Runtime:HideButton()
    local button = self.button
    self.owner = nil
    self.action = nil
    self.itemLink = nil
    self.bagID = nil
    self.slotID = nil
    self.current = nil

    if not button then
        return
    end
    if isCombatLocked() then
        self.hidePending = true
        return
    end

    self.hidePending = false
    button:Hide()
    button:SetAttribute("target-bag", nil)
    button:SetAttribute("target-slot", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", nil)
end

function Runtime:StyleButton(action)
    local button = self.button
    local color = action.color
    button.tint:SetColorTexture(color[1], color[2], color[3], 0.10)
    button.badge:SetTexture(action.icon)
    button.badge:SetVertexColor(1, 1, 1, 1)
    for _, edge in ipairs({
        button.borderTop, button.borderBottom, button.borderLeft, button.borderRight,
    }) do
        edge:SetColorTexture(color[1], color[2], color[3], 0.95)
    end
end

function Runtime:AnchorButton()
    local button = self.button
    local owner = self.owner
        or (GameTooltip and type(GameTooltip.GetOwner) == "function" and GameTooltip:GetOwner())
        or nil
    if not button or not owner or type(owner.GetScaledRect) ~= "function" then
        return
    end

    local ok, left, bottom, width, height = pcall(owner.GetScaledRect, owner)
    if not ok or not left or not bottom or not width or not height then
        return
    end

    local scaleMultiplier = 1 / UIParent:GetScale()
    button:ClearAllPoints()
    button:SetPoint(
        "BOTTOMLEFT",
        UIParent,
        "BOTTOMLEFT",
        left * scaleMultiplier,
        bottom * scaleMultiplier
    )
    button:SetSize(width * scaleMultiplier, height * scaleMultiplier)
end

function Runtime:AddTooltipHint(tooltip, action)
    if not tooltip or type(tooltip.AddLine) ~= "function" then
        return
    end

    local text = string.format(
        Addon.L.ONE_CLICK_TOOLTIP_USE or "%s + left-click: %s",
        self:GetModifierLabel(),
        action.label
    )
    tooltip:AddLine(" ")
    tooltip:AddLine(text, action.color[1], action.color[2], action.color[3], true)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:ShowButtonTooltip(button)
    if not button or button ~= self.button or not GameTooltip then
        return false
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if self.bagID and self.slotID then
        GameTooltip:SetBagItem(self.bagID, self.slotID)
    elseif self.itemLink then
        GameTooltip:SetHyperlink(self.itemLink)
    end

    if self.action then
        self:AddTooltipHint(GameTooltip, self.action)
    end
    GameTooltip:Show()
    return true
end

function Runtime:TryShowForTooltip(tooltip, data)
    if self.enabled ~= true then
        self:HideButton()
        return false
    end
    if tooltip ~= GameTooltip
        or (type(tooltip.GetOwner) == "function" and tooltip:GetOwner() == self.button)
    then
        return false
    end
    if isCombatLocked() then
        self:HideButton()
        return false
    end

    local owner, bagID, slotID, itemLink = self:GetTooltipContext(tooltip, data)
    if not self:IsModifierActive()
        or not owner
        or not bagID
        or bagID < 0
        or bagID > 5
        or not slotID
        or type(itemLink) ~= "string"
    then
        self:HideButton()
        return false
    end

    local context = self:BuildItemContext(bagID, slotID)
    local action = context and self:ResolveAction(context) or nil
    if not action or not self:ApplyAttributes(action, bagID, slotID) then
        self:HideButton()
        return false
    end

    self.owner = owner
    self.bagID = bagID
    self.slotID = slotID
    self.itemLink = itemLink
    self.action = action
    self.current = {
        owner = owner,
        bagID = bagID,
        slotID = slotID,
        itemID = context.itemID,
        itemLink = itemLink,
        action = action,
    }
    self:StyleButton(action)
    self.button:Show()
    self:AnchorButton()
    self:AddTooltipHint(tooltip, action)
    return true
end

function Runtime:RefreshFromTooltip()
    if GameTooltip
        and type(GameTooltip.IsShown) == "function"
        and GameTooltip:IsShown()
        and type(GameTooltip.GetOwner) == "function"
        and GameTooltip:GetOwner()
    then
        return self:TryShowForTooltip(GameTooltip, nil)
    end
    self:HideButton()
    return false
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return
    end
    self.hooksReady = true

    if TooltipDataProcessor
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum
        and Enum.TooltipDataType
    then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            Runtime:TryShowForTooltip(tooltip, data)
        end)
    elseif type(hooksecurefunc) == "function" and GameTooltip then
        hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bagID, slotID)
            Runtime:TryShowForTooltip(tooltip, { bagID = bagID, slotID = slotID })
        end)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:EnsureHooks()
    self:RebuildProcessingData()
    self:RebuildEquipmentSetItems()

    for _, eventName in ipairs({
        "MODIFIER_STATE_CHANGED",
        "BAG_UPDATE_DELAYED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED",
        "EQUIPMENT_SETS_CHANGED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(dispatchedEvent)
            Runtime:OnEvent(dispatchedEvent)
        end)
    end
    self:RefreshFromTooltip()
end

function Runtime:OnDisable()
    self.enabled = false
    Addon.EventBus:UnsubscribeOwner(self)
    self:HideButton()
end

function Runtime:OnSettingChanged()
    self:HideButton()
    self:RefreshFromTooltip()
end

function Runtime:OnEvent(eventName)
    if eventName == "PLAYER_REGEN_ENABLED" then
        if self.hidePending then
            self:HideButton()
        else
            self:RefreshFromTooltip()
        end
        return
    end
    if eventName == "MODIFIER_STATE_CHANGED" then
        self:RefreshFromTooltip()
        return
    end
    if eventName == "SPELLS_CHANGED" then
        self:RebuildProcessingData()
    elseif eventName == "BAG_UPDATE_DELAYED" then
        self:RebuildDisenchantData()
    elseif eventName == "EQUIPMENT_SETS_CHANGED" then
        self:RebuildEquipmentSetItems()
    end
    self:HideButton()
end

assert(
    Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime),
    "One-Click Processing runtime registration failed"
)
