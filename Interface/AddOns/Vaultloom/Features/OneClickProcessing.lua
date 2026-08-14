local _, Addon = ...

local FEATURE_ID = "one_click_processing"
local Logic = Addon.OneClickProcessingLogic
local ContainerItems = Addon.ContainerItems

local COLORS = {
    mill = { 0.18, 0.86, 0.42 },
    prospect = { 0.28, 0.74, 1.00 },
    crush = { 1.00, 0.36, 0.24 },
    scrap = { 0.10, 0.92, 0.92 },
    shatter = { 0.78, 0.62, 1.00 },
    transmute = { 0.22, 0.56, 1.00 },
    disenchant = { 0.66, 0.48, 1.00 },
    open = { 1.00, 0.78, 0.26 },
}

local MACRO_SALVAGE = "/run C_TradeSkillUI.CraftSalvage(%d,1,ItemLocation:CreateFromBagAndSlot(%d,%d))"
local MACRO_TRADE_LOCK = "/cast %s\n/run ClickTargetTradeButton(7)"
local PROCESSING_GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local SECURE_MODIFIER_ATTRIBUTE = "vaultloom-modifier-state"
local SECURE_MODIFIER_ARMED = "armed"
local SECURE_MODIFIER_IDLE = "idle"
local ACTION_TYPE_ATTRIBUTES = {
    "type1",
    "alt-type1",
    "alt-shift-type1",
    "alt-ctrl-type1",
}

local Runtime = {
    enabled = false,
    hooksReady = false,
    refreshGeneration = 0,
    salvageIndex = {},
    candidateIndex = {},
    disenchantItems = {},
    disenchantAuthoritative = false,
    equipmentSetItems = {},
}

Addon.OneClickProcessing = Runtime

local function isCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function methodReturnsTrue(owner, methodName)
    local method = owner and owner[methodName]
    if type(method) ~= "function" then
        return false
    end
    local ok, value = pcall(method, owner)
    return ok and value == true
end

local function frameIsVisible(frame)
    return frame and methodReturnsTrue(frame, "IsVisible")
end

local function isUnsafeInteractionContext(tooltip, owner)
    if methodReturnsTrue(tooltip, "IsForbidden")
        or methodReturnsTrue(owner, "IsAnchoringRestricted")
        or methodReturnsTrue(owner, "IsAnchoringSecret")
    then
        return true
    end
    if type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") == true then
        return true
    end
    local equipmentFlyout = PaperDollFrameItemFlyoutButtons or EquipmentFlyoutFrame
    if frameIsVisible(equipmentFlyout) then
        return true
    end
    local auctionFrame = AuctionHouseFrame or AuctionFrame
    return frameIsVisible(auctionFrame)
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

local function getItemCount(itemID)
    if C_Item and type(C_Item.GetItemCount) == "function" then
        local ok, count = pcall(C_Item.GetItemCount, itemID)
        if ok then
            return tonumber(count) or 0
        end
    end
    return 0
end

local function isKeyUsable(itemID)
    if not (C_TooltipInfo and type(C_TooltipInfo.GetItemByID) == "function") then
        return true
    end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
        return true
    end
    local restrictedType = Enum
        and Enum.TooltipDataLineType
        and Enum.TooltipDataLineType.RestrictedSkill
    if restrictedType == nil then
        return true
    end
    for _, line in ipairs(data.lines) do
        if line.type == restrictedType then
            local color = line.leftColor
            if color and type(color.GetRGB) == "function" then
                local colorOK, red, green, blue = pcall(color.GetRGB, color)
                return colorOK and red >= 0.99 and green >= 0.99 and blue >= 0.99
            end
            return false
        end
    end
    return true
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

local function getModifierDriverCondition(modifier)
    if modifier == "alt_shift" then
        return "[mod:alt,mod:shift,nomod:ctrl] "
            .. SECURE_MODIFIER_ARMED .. "; " .. SECURE_MODIFIER_IDLE
    end
    if modifier == "alt_ctrl" then
        return "[mod:alt,mod:ctrl,nomod:shift] "
            .. SECURE_MODIFIER_ARMED .. "; " .. SECURE_MODIFIER_IDLE
    end
    return "[mod:alt,nomod:shift,nomod:ctrl] "
        .. SECURE_MODIFIER_ARMED .. "; " .. SECURE_MODIFIER_IDLE
end

local function getActionTypeAttribute(modifier)
    if modifier == "alt_shift" then
        return "alt-shift-type1"
    end
    if modifier == "alt_ctrl" then
        return "alt-ctrl-type1"
    end
    return "alt-type1"
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
        crush = "ONE_CLICK_ACTION_CRUSH",
        scrap = "ONE_CLICK_ACTION_SCRAP",
        shatter = "ONE_CLICK_ACTION_SHATTER",
        transmute = "ONE_CLICK_ACTION_TRANSMUTE",
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

function Runtime:GetItemIcon(itemID)
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then
            return icon
        end
    end
    if type(GetItemIcon) == "function" then
        local ok, icon = pcall(GetItemIcon, itemID)
        if ok and icon then
            return icon
        end
    end
    return 134400
end

function Runtime:RebuildProcessingData()
    self.candidateIndex = Logic:BuildCatalogCandidateIndex()
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
    local ownerName = owner and type(owner.GetName) == "function" and owner:GetName() or nil
    if ownerName == "TradeRecipientItem7ItemButton" then
        local itemLink
        if type(GetTradeTargetItemLink) == "function" then
            local ok, value = pcall(GetTradeTargetItemLink, 7)
            itemLink = ok and value or nil
        end
        if (type(itemLink) ~= "string" or itemLink == "")
            and tooltip
            and type(tooltip.GetItem) == "function"
        then
            local ok, _, value = pcall(tooltip.GetItem, tooltip)
            itemLink = ok and value or nil
        end
        return owner, nil, nil, itemLink, "trade"
    end

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

    return owner, tonumber(bagID), tonumber(slotID), itemLink, "bag"
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

function Runtime:DecorateAction(action)
    if action then
        action.label = self:GetActionLabel(action.kind)
        action.color = COLORS[action.kind] or COLORS.open
        action.icon = action.itemID
            and self:GetItemIcon(action.itemID)
            or self:GetSpellIcon(action.recipeID or action.spellID)
    end
    return action
end

function Runtime:GetResolveOptions()
    return {
        salvageIndex = self.salvageIndex,
        candidateIndex = self.candidateIndex,
        disenchantItems = self.disenchantItems,
        disenchantAuthoritative = self.disenchantAuthoritative,
        allowRareEpic = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "disenchant_rare_epic") == true,
        allowConsumableKeys = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "consumable_keys") == true,
        playerLevel = type(UnitLevel) == "function" and UnitLevel("player") or 0,
        isSpellKnown = isSpellKnown,
        isRecipeKnown = isRecipeKnown,
        getItemCount = getItemCount,
        isKeyUsable = isKeyUsable,
    }
end

function Runtime:ResolveAction(context)
    return self:DecorateAction(Logic:ResolveAction(context, self:GetResolveOptions()))
end

function Runtime:ResolveFailure(context)
    local failure = Logic:DiagnoseFailure(context, self:GetResolveOptions())
    if failure and failure.action then
        failure.action = self:DecorateAction(failure.action)
    end
    return failure
end

function Runtime:ResolveTradeAction(itemLink)
    local itemID = getItemID(itemLink)
    local spellID = itemID and Logic:ResolveLockboxSpell(
        itemID,
        type(UnitLevel) == "function" and UnitLevel("player") or 0,
        isSpellKnown
    ) or nil
    if not spellID then
        return nil
    end
    return self:DecorateAction({
        kind = "open",
        execution = "trade_spell",
        spellID = spellID,
        requiredCount = 1,
    })
end

local function createBorder(button, pointA, relativePointA, pointB, relativePointB)
    local texture = button:CreateTexture(nil, "OVERLAY", nil, 4)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetPoint(pointA, button, relativePointA, 0, 0)
    texture:SetPoint(pointB, button, relativePointB, 0, 0)
    return texture
end

local function setButtonActionType(button, actionType, modifier)
    for _, attributeName in ipairs(ACTION_TYPE_ATTRIBUTES) do
        button:SetAttribute(attributeName, nil)
    end
    button:SetAttribute(getActionTypeAttribute(modifier), actionType)
end

function Runtime:EnsureButton()
    if self.button then
        return self.button
    end

    local button = CreateFrame(
        "Button",
        "VaultloomOneClickProcessingButton",
        UIParent,
        "SecureActionButtonTemplate,SecureHandlerAttributeTemplate,SecureHandlerEnterLeaveTemplate"
    )
    button:SetFrameStrata("TOOLTIP")
    button:SetSize(38, 38)
    button:RegisterForClicks("LeftButtonUp")
    button:EnableMouse(true)
    if type(button.SetPropagateMouseClicks) == "function" then
        button:SetPropagateMouseClicks(false)
    end
    button:Hide()

    button.tint = button:CreateTexture(nil, "BACKGROUND")
    button.tint:SetAllPoints(button)

    button.glow = button:CreateTexture(nil, "ARTWORK", nil, 3)
    button.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.glow:SetBlendMode("ADD")
    button.glow:SetDesaturated(true)
    button.glowAtlasReady = pcall(button.glow.SetAtlas, button.glow, PROCESSING_GLOW_ATLAS)
    button.glow:Hide()

    if button.glowAtlasReady and type(button.CreateAnimationGroup) == "function" then
        button.glowAnimation = button:CreateAnimationGroup()
        button.glowAnimation:SetLooping("REPEAT")
        local flipBook = button.glowAnimation:CreateAnimation("FlipBook")
        flipBook:SetTarget(button.glow)
        flipBook:SetDuration(1)
        flipBook:SetFlipBookColumns(5)
        flipBook:SetFlipBookRows(6)
        flipBook:SetFlipBookFrames(30)
        button.glowFlipBook = flipBook
    end

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

    button:HookScript("OnShow", function()
        Runtime:AnchorButton()
        if not isCombatLocked() then
            button:SetAttribute("_entered", true)
        end
        if button.glowEnabled and button.glowAnimation then
            button.glowAnimation:Play()
        end
    end)
    button:HookScript("OnHide", function()
        if button.glowAnimation then
            button.glowAnimation:Stop()
        end
    end)
    button:HookScript("OnEnter", function(enteredButton)
        Runtime:ShowButtonTooltip(enteredButton)
    end)
    button:HookScript("OnLeave", function()
        if GameTooltip and type(GameTooltip.Hide) == "function" then
            GameTooltip:Hide()
        end
        Runtime:HideButton()
    end)
    button:SetAttribute("_onleave", "self:Hide()")
    button:SetAttribute("_onattributechanged", [[
        if name == "vaultloom-modifier-state" and value ~= "armed" then
            self:Hide()
        end
    ]])

    self.button = button
    return button
end

function Runtime:UpdateModifierDriver()
    if isCombatLocked() then
        self.modifierDriverPending = true
        return false
    end
    if type(RegisterAttributeDriver) ~= "function" then
        self.modifierDriverPending = false
        return false
    end

    local button = self:EnsureButton()
    local modifier = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "modifier")
    RegisterAttributeDriver(
        button,
        SECURE_MODIFIER_ATTRIBUTE,
        getModifierDriverCondition(modifier)
    )
    self.modifierDriverPending = false
    return true
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
    local modifier = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "modifier")
    if action.itemID then
        button:SetAttribute("item", "item:" .. tostring(action.itemID))
        setButtonActionType(button, "item", modifier)
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
            setButtonActionType(button, "macro", modifier)
        else
            button:SetAttribute("spell", spellID)
            setButtonActionType(button, "spell", modifier)
        end
    else
        return false
    end

    return true
end

function Runtime:ApplyTradeAttributes(action)
    local button = self:EnsureButton()
    if isCombatLocked() then
        return false
    end

    local spellID = tonumber(action and action.spellID)
    local spellName
    if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, value = pcall(C_Spell.GetSpellName, spellID)
        spellName = ok and value or nil
    end
    if not spellID or type(spellName) ~= "string" or spellName == "" then
        return false
    end

    button:SetAttribute("target-bag", nil)
    button:SetAttribute("target-slot", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", string.format(MACRO_TRADE_LOCK, spellName))
    setButtonActionType(
        button,
        "macro",
        Addon.FeatureRegistry:GetSetting(FEATURE_ID, "modifier")
    )
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
    for _, attributeName in ipairs(ACTION_TYPE_ATTRIBUTES) do
        button:SetAttribute(attributeName, nil)
    end
end

function Runtime:StyleButton(action)
    local button = self.button
    local color = action.color
    button.tint:SetColorTexture(color[1], color[2], color[3], 0.10)
    button.badge:SetTexture(action.icon)
    button.badge:SetVertexColor(1, 1, 1, 1)
    button.glowEnabled = button.glowAtlasReady == true
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "animated_glow") == true
    if button.glowEnabled then
        button.glow:SetVertexColor(color[1], color[2], color[3], 1)
        button.glow:Show()
    else
        button.glow:Hide()
        if button.glowAnimation then
            button.glowAnimation:Stop()
        end
    end
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
    if button.glow then
        button.glow:SetSize(width * scaleMultiplier * 1.4, height * scaleMultiplier * 1.4)
    end
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
    if self:TooltipContainsText(tooltip, text) then
        return
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(text, action.color[1], action.color[2], action.color[3], true)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:TooltipContainsText(tooltip, text)
    if not tooltip or type(text) ~= "string" or text == "" then
        return false
    end
    local name = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    local count = type(tooltip.NumLines) == "function" and tooltip:NumLines() or 0
    if type(name) ~= "string" or name == "" then
        return false
    end
    for index = 1, count do
        for _, side in ipairs({ "Left", "Right" }) do
            local region = _G[name .. "Text" .. side .. tostring(index)]
            local value = region and type(region.GetText) == "function" and region:GetText() or nil
            if value == text then
                return true
            end
        end
    end
    return false
end

function Runtime:AddFailureHint(tooltip, context, failure)
    local action = failure and failure.action
    if not tooltip or not action then
        return false
    end

    local text
    if failure.reason == "need_more" then
        local itemName
        if C_Item and type(C_Item.GetItemNameByID) == "function" then
            local ok, value = pcall(C_Item.GetItemNameByID, context.itemID)
            itemName = ok and value or nil
        end
        itemName = itemName or context.itemLink or action.label
        text = string.format(
            Addon.L.ONE_CLICK_TOOLTIP_NEED_MORE or "Requires %d x %s.",
            failure.requiredCount or action.requiredCount or 1,
            itemName
        )
    elseif failure.reason == "recipe_unknown" then
        local recipeName
        if C_Spell and type(C_Spell.GetSpellName) == "function" then
            local ok, value = pcall(C_Spell.GetSpellName, action.recipeID)
            recipeName = ok and value or nil
        end
        recipeName = recipeName or action.label
        text = string.format(
            Addon.L.ONE_CLICK_TOOLTIP_RECIPE_UNKNOWN or "Required recipe not learned: %s.",
            recipeName
        )
    elseif failure.reason == "rare_epic_disabled" then
        text = Addon.L.ONE_CLICK_TOOLTIP_RARE_EPIC_DISABLED
            or "Rare and epic disenchanting is disabled."
    elseif failure.reason == "keys_disabled" then
        text = Addon.L.ONE_CLICK_TOOLTIP_KEYS_DISABLED
            or "A suitable consumable opener is available, but its use is disabled."
    elseif failure.reason == "protected" then
        text = Addon.L.ONE_CLICK_TOOLTIP_PROTECTED
            or "Vaultloom protects this item from one-click processing."
    end
    if not text or self:TooltipContainsText(tooltip, text) then
        return false
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(text, 1.00, 0.25, 0.20, true)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
    return true
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

    local owner, bagID, slotID, itemLink, targetType = self:GetTooltipContext(tooltip, data)
    if isUnsafeInteractionContext(tooltip, owner)
        or not self:IsModifierActive()
        or not owner
        or type(itemLink) ~= "string"
        or (targetType ~= "trade" and (
            not bagID
            or bagID < 0
            or bagID > 5
            or not slotID
        ))
    then
        self:HideButton()
        return false
    end

    if targetType == "trade" then
        local action = self:ResolveTradeAction(itemLink)
        if not action or not self:ApplyTradeAttributes(action) then
            self:HideButton()
            return false
        end
        self.owner = owner
        self.itemLink = itemLink
        self.action = action
        self.current = {
            owner = owner,
            itemID = getItemID(itemLink),
            itemLink = itemLink,
            targetType = "trade",
            action = action,
        }
        self:StyleButton(action)
        self.button:Show()
        self:AnchorButton()
        self:AddTooltipHint(tooltip, action)
        return true
    end

    local context = self:BuildItemContext(bagID, slotID)
    local action = context and self:ResolveAction(context) or nil
    if not action then
        local failure = context and self:ResolveFailure(context) or nil
        self:HideButton()
        if failure then
            self:AddFailureHint(tooltip, context, failure)
        end
        return false
    end
    if not self:ApplyAttributes(action, bagID, slotID) then
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
        targetType = "bag",
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
        hooksecurefunc(GameTooltip, "SetTradeTargetItem", function(tooltip)
            Runtime:TryShowForTooltip(tooltip, { targetType = "trade" })
        end)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:EnsureHooks()
    self:RebuildProcessingData()
    self:RebuildEquipmentSetItems()
    self:UpdateModifierDriver()

    for _, eventName in ipairs({
        "MODIFIER_STATE_CHANGED",
        "BAG_UPDATE_DELAYED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED",
        "TRADE_SKILL_LIST_UPDATE",
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
    self:UpdateModifierDriver()
    self:HideButton()
    self:RefreshFromTooltip()
end

function Runtime:OnEvent(eventName)
    if eventName == "PLAYER_REGEN_ENABLED" then
        if self.modifierDriverPending then
            self:UpdateModifierDriver()
        end
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
    if eventName == "SPELLS_CHANGED" or eventName == "TRADE_SKILL_LIST_UPDATE" then
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
