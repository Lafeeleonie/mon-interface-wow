local _, Addon = ...

local FEATURE_ID = "character_gear"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local SLOT_NAMES = {
    "HeadSlot",
    "NeckSlot",
    "ShoulderSlot",
    "BackSlot",
    "ChestSlot",
    "WristSlot",
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
    "Finger0Slot",
    "Finger1Slot",
    "Trinket0Slot",
    "Trinket1Slot",
    "MainHandSlot",
    "SecondaryHandSlot",
}

local LEFT_SLOT_NAMES = {
    HeadSlot = true,
    NeckSlot = true,
    ShoulderSlot = true,
    BackSlot = true,
    ChestSlot = true,
    WristSlot = true,
    SecondaryHandSlot = true,
}

local ENCHANTABLE_SLOT_IDS = {
    [1] = true,
    [3] = true,
    [5] = true,
    [7] = true,
    [8] = true,
    [11] = true,
    [12] = true,
    [16] = true,
    [17] = true,
}

local MARKER_OFFSET_X = 9
local MARKER_TOP_OFFSET_Y = -1
local MARKER_GAP_Y = -2

local Runtime = {
    enabled = false,
    paperDollHooked = false,
    characterFrameHooked = false,
    refreshGeneration = 0,
}

Addon.CharacterGear = Runtime

local function getSlotButton(slotName)
    return type(slotName) == "string" and _G["Character" .. slotName] or nil
end

local function isCharacterFrameShown()
    return CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
end

local function getSettings()
    return {
        itemLevel = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "item_level") == true,
        itemLevelStyle = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "item_level_style") or "white",
        enchants = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "enchants") == true,
        missingEnchantsOnly = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "missing_enchants_only") == true,
        emptySockets = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "sockets") == true,
        gems = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "gems") == true,
    }
end

local function ensureItemLevelFont()
    local font = _G.VaultloomCharacterItemLevelFont
    if font then
        return font
    end

    font = CreateFont("VaultloomCharacterItemLevelFont")
    font:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    font:SetShadowOffset(1, -1)
    font:SetShadowColor(0, 0, 0, 0.95)
    return font
end

local function ensureItemLevelText(slotButton)
    local text = slotButton and slotButton.VaultloomCharacterItemLevelText or nil
    if text then
        return text
    end
    if not slotButton or type(slotButton.CreateFontString) ~= "function" then
        return nil
    end

    text = slotButton:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(ensureItemLevelFont())
    text:SetJustifyH("CENTER")
    text:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 3)
    text:SetText("")
    text:Hide()
    slotButton.VaultloomCharacterItemLevelText = text
    return text
end

local function hideItemLevel(slotButton)
    local text = slotButton and slotButton.VaultloomCharacterItemLevelText or nil
    if text then
        text:Hide()
    end
end

local function getInventoryLink(slotID)
    if type(GetInventoryItemLink) ~= "function" then
        return nil
    end
    local ok, itemLink = pcall(GetInventoryItemLink, "player", slotID)
    return ok and itemLink or nil
end

local function getItemDescriptor(itemLink)
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, equipLocation, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemLink)
        if ok then
            return equipLocation, classID, subclassID
        end
    end
    if type(GetItemInfo) == "function" then
        local ok, _, _, _, _, _, _, _, _, equipLocation, _, _, classID, subclassID = pcall(GetItemInfo, itemLink)
        if ok then
            return equipLocation, classID, subclassID
        end
    end
    return nil, nil, nil
end

local function getCurrentItemLevel(slotID, itemLink)
    local itemLevel
    if ItemLocation and type(ItemLocation.CreateFromEquipmentSlot) == "function"
        and C_Item
        and type(C_Item.DoesItemExist) == "function"
        and type(C_Item.GetCurrentItemLevel) == "function"
    then
        local okLocation, itemLocation = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slotID)
        if okLocation and itemLocation then
            local okExists, exists = pcall(C_Item.DoesItemExist, itemLocation)
            if okExists and exists then
                local okLevel, currentLevel = pcall(C_Item.GetCurrentItemLevel, itemLocation)
                if okLevel then
                    itemLevel = tonumber(currentLevel)
                end
            end
        end
    end

    if not itemLevel and C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local ok, detailedLevel = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok then
            itemLevel = tonumber(detailedLevel)
        end
    end
    if not itemLevel and type(GetDetailedItemLevelInfo) == "function" then
        local ok, detailedLevel = pcall(GetDetailedItemLevelInfo, itemLink)
        if ok then
            itemLevel = tonumber(detailedLevel)
        end
    end

    return itemLevel and itemLevel > 0 and math.floor(itemLevel + 0.5) or nil
end

local function getItemLevelColor(slotID, style)
    if style ~= "quality" then
        return 1, 1, 1
    end

    local quality
    if type(GetInventoryItemQuality) == "function" then
        local ok, resolvedQuality = pcall(GetInventoryItemQuality, "player", slotID)
        if ok then
            quality = tonumber(resolvedQuality)
        end
    end
    local color = quality ~= nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or nil
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

local emptySocketLines
local function getEmptySocketLines()
    if emptySocketLines then
        return emptySocketLines
    end

    emptySocketLines = {}
    for globalName, value in pairs(_G) do
        if type(globalName) == "string"
            and globalName:find("EMPTY_SOCKET_", 1, true)
            and type(value) == "string"
            and value ~= ""
        then
            emptySocketLines[#emptySocketLines + 1] = value
        end
    end
    return emptySocketLines
end

local function getItemIcon(itemLink)
    if type(GetItemInfo) == "function" then
        local ok, _, _, _, _, _, _, _, _, _, icon = pcall(GetItemInfo, itemLink)
        if ok and icon then
            return icon
        end
    end
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, itemLink)
        if ok then
            return icon
        end
    end
    return nil
end

local function getGemLink(itemLink, gemIndex)
    if C_Item and type(C_Item.GetItemGem) == "function" then
        local ok, _, gemLink = pcall(C_Item.GetItemGem, itemLink, gemIndex)
        if ok and gemLink then
            return gemLink
        end
    end
    if type(GetItemGem) == "function" then
        local ok, _, gemLink = pcall(GetItemGem, itemLink, gemIndex)
        if ok then
            return gemLink
        end
    end
    return nil
end

local function getInventoryTooltipData(slotID)
    if not (C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem) == "function") then
        return nil
    end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
    return ok and data or nil
end

local function getSocketVisuals(slotID, itemLink, settings)
    local visuals = {}
    if settings.gems then
        for gemIndex = 1, 4 do
            local gemLink = getGemLink(itemLink, gemIndex)
            if gemLink then
                visuals[#visuals + 1] = {
                    texture = getItemIcon(gemLink),
                    gemLink = gemLink,
                    empty = false,
                }
            end
        end
    end

    if settings.emptySockets then
        local tooltipData = getInventoryTooltipData(slotID)
        local lines = tooltipData and tooltipData.lines or nil
        if type(lines) == "table" then
            local localizedEmptySockets = getEmptySocketLines()
            for _, line in ipairs(lines) do
                local text = line and line.leftText or nil
                if type(text) == "string" and text ~= "" then
                    for _, emptySocketText in ipairs(localizedEmptySockets) do
                        if text:find(emptySocketText, 1, true) then
                            visuals[#visuals + 1] = {
                                texture = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
                                empty = true,
                            }
                            break
                        end
                    end
                end
            end
        end
    end

    while #visuals > 4 do
        table.remove(visuals)
    end
    return visuals
end

local function cleanEnchantName(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local clean = text:gsub("|A:[^|]+|a", ""):gsub("%s+", " ")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    clean = clean:gsub("^Enchanted:%s*", ""):gsub("^Verzaubert:%s*", "")
    return clean ~= "" and clean or nil
end

local function getEnchantScanTooltip()
    local tooltip = _G.VaultloomCharacterGearScanTooltip
    if tooltip then
        return tooltip
    end
    if type(CreateFrame) ~= "function" then
        return nil
    end

    local ok, createdTooltip = pcall(
        CreateFrame,
        "GameTooltip",
        "VaultloomCharacterGearScanTooltip",
        nil,
        "GameTooltipTemplate"
    )
    if not ok or not createdTooltip then
        return nil
    end
    if type(createdTooltip.SetOwner) == "function" then
        createdTooltip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    end
    return createdTooltip
end

local function getEnchantName(itemLink)
    if C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" then
        local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and type(tooltipData) == "table" and type(tooltipData.lines) == "table" then
            for _, line in ipairs(tooltipData.lines) do
                local text = line and line.leftText or nil
                if type(text) == "string"
                    and (
                        text:find("Professions%-ChatIcon%-Quality%-Tier")
                        or text:find("|A:Professions")
                    )
                    and not text:lower():find("socket", 1, true)
                then
                    local name = cleanEnchantName(text)
                    if name then
                        return name
                    end
                end
            end
        end
    end

    local tooltip = getEnchantScanTooltip()
    if not tooltip
        or type(tooltip.ClearLines) ~= "function"
        or type(tooltip.SetHyperlink) ~= "function"
        or type(tooltip.NumLines) ~= "function"
    then
        return nil
    end

    local ok = pcall(function()
        tooltip:ClearLines()
        tooltip:SetHyperlink(itemLink)
    end)
    if not ok then
        return nil
    end

    for index = 1, tooltip:NumLines() do
        local line = _G["VaultloomCharacterGearScanTooltipTextLeft" .. index]
        if line and type(line.GetText) == "function" then
            local text = line:GetText()
            local red, green, blue
            if type(line.GetTextColor) == "function" then
                red, green, blue = line:GetTextColor()
            end
            if type(text) == "string"
                and (
                    text:find("Professions%-ChatIcon%-Quality%-Tier")
                    or ((green or 0) > 0.90 and (red or 1) < 0.20 and (blue or 1) < 0.20)
                )
                and not text:lower():find("socket", 1, true)
            then
                local name = cleanEnchantName(text)
                if name then
                    return name
                end
            end
        end
    end
    return nil
end

local function canBeEnchanted(slotID, itemLink, equipLocation, classID, subclassID)
    if not ENCHANTABLE_SLOT_IDS[slotID] or not itemLink then
        return false
    end
    if slotID ~= 17 then
        return true
    end

    local weaponClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    local armorClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
    if classID == weaponClassID then
        return true
    end
    if classID == armorClassID
        and (subclassID == 6 or subclassID == 0 or equipLocation == "INVTYPE_HOLDABLE")
    then
        return false
    end
    return equipLocation == "INVTYPE_WEAPON" or equipLocation == "INVTYPE_WEAPONOFFHAND"
end

local function resolveSlot(slotID, settings)
    local itemLink = getInventoryLink(slotID)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local equipLocation, classID, subclassID = getItemDescriptor(itemLink)
    local enchantID = tonumber(itemLink:match("item:%-?%d+:(%-?%d+)")) or 0
    local enchanted = enchantID > 0

    return {
        itemLink = itemLink,
        itemLevel = settings.itemLevel and getCurrentItemLevel(slotID, itemLink) or nil,
        socketVisuals = (settings.emptySockets or settings.gems)
            and getSocketVisuals(slotID, itemLink, settings)
            or {},
        enchantable = settings.enchants
            and canBeEnchanted(slotID, itemLink, equipLocation, classID, subclassID)
            or false,
        enchanted = enchanted,
        enchantName = settings.enchants and enchanted and getEnchantName(itemLink) or nil,
    }
end

local function ensureMarkerOverlay(slotButton)
    local overlay = slotButton and slotButton.VaultloomCharacterGearOverlay or nil
    if overlay then
        return overlay
    end
    if not slotButton then
        return nil
    end

    overlay = CreateFrame("Frame", nil, slotButton)
    overlay:SetAllPoints(slotButton)
    overlay:SetFrameLevel(slotButton:GetFrameLevel() + 10)
    overlay:EnableMouse(false)
    overlay.socketHolders = {}

    for index = 1, 4 do
        local holder = CreateFrame("Button", nil, overlay, BACKDROP_TEMPLATE)
        holder:SetSize(14, 14)
        holder:EnableMouse(true)
        if holder.SetBackdrop then
            holder:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            holder:SetBackdropColor(0.03, 0.03, 0.04, 0.88)
            holder:SetBackdropBorderColor(0.22, 0.22, 0.24, 0.90)
        end
        holder.icon = holder:CreateTexture(nil, "OVERLAY")
        holder.icon:SetSize(13, 13)
        holder.icon:SetPoint("CENTER", 0, 0)
        holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        holder:SetScript("OnEnter", function(marker)
            GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
            if marker.vaultloomGemLink then
                GameTooltip:SetHyperlink(marker.vaultloomGemLink)
            else
                GameTooltip:AddLine(Addon.L.FEATURE_GEAR_EMPTY_SOCKET or "Empty socket", 1, 0.32, 0.32, true)
                GameTooltip:AddLine(
                    Addon.L.FEATURE_GEAR_EMPTY_SOCKET_NOTE or "No gem is inserted.",
                    0.88,
                    0.86,
                    0.82,
                    true
                )
            end
            GameTooltip:Show()
        end)
        holder:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        holder:Hide()
        overlay.socketHolders[index] = holder
    end

    overlay.enchantStatus = CreateFrame("Button", nil, overlay, BACKDROP_TEMPLATE)
    overlay.enchantStatus:SetSize(14, 14)
    overlay.enchantStatus:EnableMouse(true)
    if overlay.enchantStatus.SetBackdrop then
        overlay.enchantStatus:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        overlay.enchantStatus:SetBackdropColor(0.03, 0.03, 0.04, 0.88)
        overlay.enchantStatus:SetBackdropBorderColor(0.22, 0.22, 0.24, 0.90)
    end
    overlay.enchantStatus.icon = overlay.enchantStatus:CreateTexture(nil, "OVERLAY")
    overlay.enchantStatus.icon:SetSize(13, 13)
    overlay.enchantStatus.icon:SetPoint("CENTER", 0, 0)
    overlay.enchantStatus.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    overlay.enchantStatus:SetScript("OnEnter", function(marker)
        GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
        if marker.vaultloomMissing then
            GameTooltip:AddLine(Addon.L.FEATURE_GEAR_MISSING_ENCHANT or "Missing enchant", 1, 0.20, 0.20, true)
            GameTooltip:AddLine(
                Addon.L.FEATURE_GEAR_MISSING_ENCHANT_NOTE or "This item can be enchanted.",
                0.88,
                0.86,
                0.82,
                true
            )
        else
            GameTooltip:AddLine(
                marker.vaultloomEnchantName or Addon.L.FEATURE_GEAR_ENCHANTED or "Enchanted",
                0.20,
                1,
                0.45,
                true
            )
        end
        GameTooltip:Show()
    end)
    overlay.enchantStatus:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    overlay.enchantStatus:Hide()

    slotButton.VaultloomCharacterGearOverlay = overlay
    return overlay
end

local function hideMarkers(slotButton)
    local overlay = slotButton and slotButton.VaultloomCharacterGearOverlay or nil
    if not overlay then
        return
    end
    overlay:Hide()
    for _, holder in ipairs(overlay.socketHolders or {}) do
        holder:Hide()
    end
    if overlay.enchantStatus then
        overlay.enchantStatus:Hide()
    end
end

local function renderItemLevel(slotButton, slotID, slotData, settings)
    if not settings.itemLevel or not slotData or not slotData.itemLevel then
        hideItemLevel(slotButton)
        return
    end

    local text = ensureItemLevelText(slotButton)
    if not text then
        return
    end
    local red, green, blue = getItemLevelColor(slotID, settings.itemLevelStyle)
    text:SetText(slotData.itemLevel)
    text:SetTextColor(red, green, blue, 1)
    text:Show()
end

local function renderMarkers(slotButton, slotName, slotData, settings)
    if not slotData
        or (not settings.enchants and not settings.emptySockets and not settings.gems)
    then
        hideMarkers(slotButton)
        return
    end

    local overlay = ensureMarkerOverlay(slotButton)
    if not overlay then
        return
    end

    local placeLeft = LEFT_SLOT_NAMES[slotName] == true
    local enchantShown = settings.enchants
        and slotData.enchantable
        and (not settings.missingEnchantsOnly or not slotData.enchanted)

    overlay.enchantStatus:ClearAllPoints()
    if placeLeft then
        overlay.enchantStatus:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", MARKER_OFFSET_X, MARKER_TOP_OFFSET_Y)
    else
        overlay.enchantStatus:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", -MARKER_OFFSET_X, MARKER_TOP_OFFSET_Y)
    end

    if enchantShown then
        overlay.enchantStatus.vaultloomMissing = not slotData.enchanted
        overlay.enchantStatus.vaultloomEnchantName = slotData.enchantName
        overlay.enchantStatus.icon:SetTexture(
            slotData.enchanted
                and "Interface\\RaidFrame\\ReadyCheck-Ready"
                or "Interface\\RaidFrame\\ReadyCheck-NotReady"
        )
        if overlay.enchantStatus.SetBackdropBorderColor then
            overlay.enchantStatus:SetBackdropColor(0, 0, 0, 0)
            overlay.enchantStatus:SetBackdropBorderColor(0, 0, 0, 0)
        end
        overlay.enchantStatus:Show()
    else
        overlay.enchantStatus.vaultloomMissing = nil
        overlay.enchantStatus.vaultloomEnchantName = nil
        overlay.enchantStatus:Hide()
    end

    local visibleSocketCount = 0
    for index, holder in ipairs(overlay.socketHolders) do
        local visual = slotData.socketVisuals[index]
        holder:ClearAllPoints()
        if visual and visual.texture then
            holder.icon:SetTexture(visual.texture)
            holder.icon:SetVertexColor(1, 1, 1, 1)
            holder.vaultloomGemLink = visual.gemLink
            if holder.SetBackdropBorderColor then
                if visual.empty then
                    holder:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
                    holder:SetBackdropBorderColor(0.58, 0.62, 0.76, 0.95)
                else
                    holder:SetBackdropColor(0.03, 0.03, 0.04, 0.88)
                    holder:SetBackdropBorderColor(0.22, 0.22, 0.24, 0.90)
                end
            end
            holder:Show()
            visibleSocketCount = visibleSocketCount + 1
        else
            holder.vaultloomGemLink = nil
            holder:Hide()
        end
    end

    for index = 1, visibleSocketCount do
        local holder = overlay.socketHolders[index]
        if index == 1 then
            local anchor = enchantShown and overlay.enchantStatus or slotButton
            if placeLeft then
                holder:SetPoint(
                    "TOPLEFT",
                    anchor,
                    enchantShown and "BOTTOMLEFT" or "TOPRIGHT",
                    enchantShown and 0 or MARKER_OFFSET_X,
                    enchantShown and MARKER_GAP_Y or MARKER_TOP_OFFSET_Y
                )
            else
                holder:SetPoint(
                    "TOPRIGHT",
                    anchor,
                    enchantShown and "BOTTOMRIGHT" or "TOPLEFT",
                    enchantShown and 0 or -MARKER_OFFSET_X,
                    enchantShown and MARKER_GAP_Y or MARKER_TOP_OFFSET_Y
                )
            end
        else
            local previous = overlay.socketHolders[index - 1]
            holder:SetPoint(
                placeLeft and "TOPLEFT" or "TOPRIGHT",
                previous,
                placeLeft and "BOTTOMLEFT" or "BOTTOMRIGHT",
                0,
                MARKER_GAP_Y
            )
        end
    end

    if enchantShown or visibleSocketCount > 0 then
        overlay:Show()
    else
        overlay:Hide()
    end
end

function Runtime:HideSlot(slotButton)
    hideItemLevel(slotButton)
    hideMarkers(slotButton)
end

function Runtime:RefreshSlot(slotButton, slotName, settings)
    if not slotButton then
        return
    end
    if self.enabled ~= true or not isCharacterFrameShown() then
        self:HideSlot(slotButton)
        return
    end

    slotName = slotName
        or (slotButton.GetName and tostring(slotButton:GetName() or ""):gsub("^Character", ""))
    local ok, slotID = pcall(slotButton.GetID, slotButton)
    slotID = ok and tonumber(slotID) or nil
    if not slotID then
        self:HideSlot(slotButton)
        return
    end

    settings = settings or getSettings()
    local slotData = resolveSlot(slotID, settings)
    renderItemLevel(slotButton, slotID, slotData, settings)
    renderMarkers(slotButton, slotName, slotData, settings)
end

function Runtime:RefreshAll()
    if self.enabled ~= true or not isCharacterFrameShown() then
        return
    end

    local settings = getSettings()
    for _, slotName in ipairs(SLOT_NAMES) do
        self:RefreshSlot(getSlotButton(slotName), slotName, settings)
    end
end

function Runtime:HideAll()
    for _, slotName in ipairs(SLOT_NAMES) do
        self:HideSlot(getSlotButton(slotName))
    end
end

function Runtime:ScheduleRefresh(delaySeconds)
    if self.enabled ~= true then
        return
    end
    local generation = self.refreshGeneration
    local callback = function()
        if Runtime.enabled == true and Runtime.refreshGeneration == generation then
            Runtime:EnsureHooks()
            Runtime:RefreshAll()
        end
    end

    delaySeconds = tonumber(delaySeconds) or 0
    if delaySeconds > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(
            delaySeconds,
            Addon.PerformanceDiagnostics:Wrap(Runtime, "timer", "character_gear.refresh", callback)
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Runtime,
            "timer",
            "character_gear.refresh",
            callback
        )
        wrapped()
    end
end

function Runtime:EnsureHooks()
    if type(hooksecurefunc) == "function"
        and not self.paperDollHooked
        and type(PaperDollItemSlotButton_Update) == "function"
    then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(slotButton)
            if Runtime.enabled == true
                and slotButton
                and slotButton.GetName
                and tostring(slotButton:GetName() or ""):find("^Character")
            then
                Runtime:RefreshSlot(slotButton)
            end
        end)
        self.paperDollHooked = true
    end

    if CharacterFrame and type(CharacterFrame.HookScript) == "function" and not self.characterFrameHooked then
        CharacterFrame:HookScript("OnShow", function()
            if Runtime.enabled == true then
                Runtime:ScheduleRefresh(0)
                Runtime:ScheduleRefresh(0.1)
                Runtime:ScheduleRefresh(0.4)
            end
        end)
        CharacterFrame:HookScript("OnHide", function()
            Runtime:HideAll()
        end)
        self.characterFrameHooked = true
    end
end

function Runtime:HandleEvent(eventName, ...)
    if self.enabled ~= true then
        return
    end
    if eventName == "ADDON_LOADED" then
        if (...) == "Blizzard_CharacterUI" then
            self:EnsureHooks()
            self:ScheduleRefresh(0)
            self:ScheduleRefresh(0.1)
        end
        return
    end
    if eventName == "UNIT_INVENTORY_CHANGED" and (...) ~= "player" then
        return
    end

    self:ScheduleRefresh(0)
    self:ScheduleRefresh(0.1)
    self:ScheduleRefresh(0.4)
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshGeneration = self.refreshGeneration + 1
    self:EnsureHooks()

    for _, eventName in ipairs({
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(dispatchedEvent, ...)
            Runtime:HandleEvent(dispatchedEvent, ...)
        end)
    end

    self:ScheduleRefresh(0)
    self:ScheduleRefresh(0.1)
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self:HideAll()
end

function Runtime:OnSettingChanged()
    self:RefreshAll()
end

function Runtime:OnSettingsReset()
    self:RefreshAll()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Character Equipment feature runtime.")
end
