local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Assets = Addon.Assets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SLOT_CARD_HEIGHT = 53
local SLOT_CARD_GAP = 4
local SAVED_PORTRAIT_SIZE = 130
local CLASS_FALLBACK_SIZE = 72
local SAVED_PORTRAIT_FRAME_SIZE = 146
local CLASS_FALLBACK_FRAME_SIZE = 88

local MODES = {
    { key = "equipment", label = function() return L.ARSENAL_TAB_EQUIPMENT end },
    { key = "bags", label = function() return L.ARSENAL_TAB_BAGS end },
    { key = "bank", label = function() return L.ARSENAL_TAB_BANK end },
    { key = "warband", label = function() return L.ARSENAL_TAB_WARBAND end },
}

local MODE_COPY = {
    bags = {
        title = function() return L.ARSENAL_INVENTORY_BAGS_TITLE end,
        subtitle = function() return L.ARSENAL_INVENTORY_BAGS_SUBTITLE end,
        empty = function() return L.ARSENAL_NO_BAGS end,
    },
    bank = {
        title = function() return L.ARSENAL_INVENTORY_BANK_TITLE end,
        subtitle = function() return L.ARSENAL_INVENTORY_BANK_SUBTITLE end,
        empty = function() return L.ARSENAL_NO_BANK end,
    },
    warband = {
        title = function() return L.ARSENAL_INVENTORY_WARBAND_TITLE end,
        subtitle = function() return L.ARSENAL_INVENTORY_WARBAND_SUBTITLE end,
        empty = function() return L.ARSENAL_NO_WARBAND_BANK end,
    },
}

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function hideTooltip()
    if GameTooltip and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
end

local function showItemTooltip(owner, itemLink)
    if not GameTooltip or type(itemLink) ~= "string" or itemLink == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(itemLink)
    end
    GameTooltip:Show()
end

local function formatTimestamp(timestamp, current)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 or type(date) ~= "function" then
        return L.ARSENAL_SNAPSHOT_UNKNOWN
    end
    local stamp = date("%x %H:%M", timestamp)
    return string.format(current and L.ARSENAL_SNAPSHOT_LIVE or L.ARSENAL_SNAPSHOT_SAVED, stamp)
end

local function setClassPortrait(texture, character, current)
    if not texture then return "class" end
    if current and type(SetPortraitTexture) == "function" then
        texture:SetTexCoord(0, 1, 0, 1)
        local ok = pcall(SetPortraitTexture, texture, "player")
        if ok then return "player" end
    end
    local displayID = tonumber(character and character.displayID)
    if displayID and displayID > 0 and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
        texture:SetTexCoord(0, 1, 0, 1)
        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, texture, displayID)
        if ok then return "display" end
    end
    local classFile = character and character.classFile
    local customIcon = Assets.classIcons and Assets.classIcons[classFile]
    if customIcon then
        texture:SetTexture(customIcon)
        texture:SetTexCoord(0, 1, 0, 1)
        return "class"
    end

    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile] or nil
    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
    return "class"
end

local function addCircularMask(owner, texture)
    if not owner or not texture
        or type(owner.CreateMaskTexture) ~= "function"
        or type(texture.AddMaskTexture) ~= "function"
    then
        return nil
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function setQualityBorder(frame, quality, alpha)
    if not frame or type(frame.SetBackdropBorderColor) ~= "function" then return end
    local color = Addon.ArsenalLogic:GetQualityColor(quality)
    frame:SetBackdropBorderColor(color[1], color[2], color[3], alpha or 0.92)
end

local function createSlotCard(parent)
    local card = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    card:SetHeight(SLOT_CARD_HEIGHT)
    card:RegisterForClicks("LeftButtonUp")
    Widgets:ApplyPanelStyle(card, "cardInset")

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(35, 35)
    card.icon:SetPoint("LEFT", 6, 0)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.slot = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.slot:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 7, -1)
    card.slot:SetPoint("TOPRIGHT", -42, -1)
    card.slot:SetHeight(12)

    card.name = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.name:SetPoint("TOPLEFT", card.slot, "BOTTOMLEFT", 0, -1)
    card.name:SetPoint("TOPRIGHT", -42, -13)
    card.name:SetHeight(13)
    card.name:SetWordWrap(false)
    card.name:SetMaxLines(1)

    card.detail = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.detail:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -1)
    card.detail:SetPoint("RIGHT", -76, 0)
    card.detail:SetHeight(11)
    card.detail:SetWordWrap(false)
    card.detail:SetMaxLines(1)

    card.level = Widgets:CreateLabel(card, "GameFontNormalSmall", "RIGHT")
    card.level:SetPoint("TOPRIGHT", -6, -7)
    card.level:SetSize(36, 14)
    card.level:SetTextColor(unpackColor(Theme.colors.gold))

    card.enchant = card:CreateTexture(nil, "OVERLAY")
    card.enchant:SetSize(14, 14)
    card.enchant:SetPoint("BOTTOMRIGHT", -6, 5)
    card.enchant:Hide()

    card.sockets = {}
    for index = 1, 4 do
        local socket = card:CreateTexture(nil, "OVERLAY")
        socket:SetSize(13, 13)
        socket:SetPoint("RIGHT", card.enchant, "LEFT", -3 - ((index - 1) * 14), 0)
        socket:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        socket:Hide()
        card.sockets[index] = socket
    end

    card:SetScript("OnEnter", function(self)
        showItemTooltip(self, self.itemLink)
    end)
    card:SetScript("OnLeave", hideTooltip)
    card:SetScript("OnClick", function(self)
        if self.itemLink and type(HandleModifiedItemClick) == "function" then
            HandleModifiedItemClick(self.itemLink)
        end
    end)
    return card
end

local function applySlotCard(card, definition, entry)
    entry = type(entry) == "table" and entry or {
        empty = true,
    }
    local issue = Addon.ArsenalLogic:GetSlotIssue(entry)
    card.issue = issue
    card.itemLink = entry.itemLink
    card.slot:SetText(Addon.ArsenalLogic:GetSlotLabel(definition))
    card.icon:SetTexture(entry.icon or entry.emptyTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

    if issue.empty then
        card.name:SetText(L.ARSENAL_EMPTY_SLOT)
        card.name:SetTextColor(unpackColor(Theme.colors.muted))
        card.detail:SetText(L.ARSENAL_NO_ITEM)
        card.level:SetText("--")
        if type(card.icon.SetDesaturated) == "function" then card.icon:SetDesaturated(true) end
        card:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
        card.enchant:Hide()
        for _, socket in ipairs(card.sockets) do socket:Hide() end
        return
    end

    if type(card.icon.SetDesaturated) == "function" then card.icon:SetDesaturated(false) end
    card.name:SetText(entry.itemName or Addon.ArsenalLogic:GetItemName(entry.itemLink, entry.itemID))
    local qualityColor = Addon.ArsenalLogic:GetQualityColor(entry.quality)
    card.name:SetTextColor(unpackColor(qualityColor))
    card.level:SetText(entry.itemLevel and tostring(entry.itemLevel) or "?")
    card.detail:SetText(entry.upgradeTrack or "")
    card.detail:SetTextColor(unpackColor(issue.upgradeable and Theme.colors.gold or Theme.colors.muted))

    if entry.enchantable then
        card.enchant:SetTexture(entry.enchanted
            and "Interface\\RaidFrame\\ReadyCheck-Ready"
            or "Interface\\RaidFrame\\ReadyCheck-NotReady")
        card.enchant:Show()
    else
        card.enchant:Hide()
    end

    for index, socket in ipairs(card.sockets) do
        local socketData = entry.sockets and entry.sockets[index]
        if socketData then
            socket:SetTexture(socketData.icon or "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
            socket:Show()
        else
            socket:Hide()
        end
    end

    if issue.missingEnchant then
        card:SetBackdropBorderColor(0.72, 0.18, 0.14, 0.92)
    elseif issue.emptySockets > 0 or issue.upgradeable then
        card:SetBackdropBorderColor(0.80, 0.58, 0.16, 0.88)
    else
        setQualityBorder(card, entry.quality, 0.58)
    end
end

local function createStatRow(parent, previous)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:SetPoint("LEFT", 12, 0)
    row:SetPoint("RIGHT", -12, 0)
    if previous then
        row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
    end
    row.label = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.label:SetPoint("LEFT", 0, 0)
    row.value = Widgets:CreateLabel(row, "GameFontHighlightSmall", "RIGHT")
    row.value:SetPoint("RIGHT", 0, 0)
    return row
end

local function setStatRow(row, label, value, warning)
    row.label:SetText(label or "")
    row.value:SetText(value or "--")
    row.value:SetTextColor(unpackColor(warning and Theme.colors.gold or Theme.colors.parchment))
end

local function createInventorySlot(parent)
    local slot = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    slot:SetSize(42, 42)
    slot:RegisterForClicks("LeftButtonUp")
    Widgets:ApplyPanelStyle(slot, "cardInset")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(37, 37)
    slot.icon:SetPoint("CENTER", 0, 0)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.count = Widgets:CreateLabel(slot, "GameFontHighlightSmall", "RIGHT")
    slot.count:SetPoint("BOTTOMRIGHT", -4, 3)
    slot.count:SetTextColor(1, 1, 1, 1)
    slot:SetScript("OnEnter", function(self)
        showItemTooltip(self, self.itemLink)
    end)
    slot:SetScript("OnLeave", hideTooltip)
    slot:SetScript("OnClick", function(self)
        if self.itemLink and type(HandleModifiedItemClick) == "function" then
            HandleModifiedItemClick(self.itemLink)
        end
    end)
    return slot
end

local function getContainerLabel(container, listIndex)
    if type(container and container.name) == "string" and container.name ~= "" then
        return container.name
    end
    local kind = container and container.kind
    if kind == "backpack" then return L.ARSENAL_CONTAINER_BACKPACK end
    if kind == "bag" then return string.format(L.ARSENAL_CONTAINER_BAG, container.index or listIndex) end
    if kind == "bank" then return L.ARSENAL_CONTAINER_BANK end
    if kind == "bankTab" then return string.format(L.ARSENAL_CONTAINER_BANK_TAB, container.index or listIndex) end
    if kind == "reagents" then return L.ARSENAL_CONTAINER_REAGENTS end
    if kind == "warband" then return string.format(L.ARSENAL_CONTAINER_WARBAND_TAB, container.index or listIndex) end
    return tostring(listIndex)
end

local function createScreen(_, host)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.layoutVersion = "arsenal-snapshots-2"
    frame.modeButtons = {}
    frame.slotCards = { left = {}, right = {} }
    frame.inventorySlots = {}
    frame.containerButtons = {}
    frame.selectedContainerByMode = {
        bags = 1,
        bank = 1,
        warband = 1,
    }
    frame.issuesOnly = false

    frame.navigation = CreateFrame("Frame", nil, frame)
    frame.navigation:SetPoint("TOPLEFT", 0, 0)
    frame.navigation:SetPoint("TOPRIGHT", 0, 0)
    frame.navigation:SetHeight(32)

    local previousModeButton
    for _, mode in ipairs(MODES) do
        local button = Widgets:CreateButton(frame.navigation, mode.label(), 174, 30, "tab")
        if previousModeButton then
            button:SetPoint("LEFT", previousModeButton, "RIGHT", 5, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end
        button.modeKey = mode.key
        button:SetScript("OnClick", function(self)
            Addon.Database:GetUI().selectedSubTabs.arsenal = self.modeKey
            frame:Refresh()
        end)
        frame.modeButtons[mode.key] = button
        previousModeButton = button
    end

    frame.content = Widgets:CreatePanel(frame, "inset")
    frame.content:SetPoint("TOPLEFT", frame.navigation, "BOTTOMLEFT", 0, -10)
    frame.content:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.equipmentPanel = CreateFrame("Frame", nil, frame.content)
    frame.equipmentPanel:SetAllPoints(frame.content)

    frame.equipmentTitle = Widgets:CreateLabel(frame.equipmentPanel, "GameFontNormalLarge", "LEFT")
    frame.equipmentTitle:SetPoint("TOPLEFT", 14, -12)
    frame.equipmentTitle:SetText(L.ARSENAL_EQUIPMENT_TITLE)
    frame.equipmentSubtitle = Widgets:CreateLabel(frame.equipmentPanel, "GameFontDisableSmall", "LEFT")
    frame.equipmentSubtitle:SetPoint("TOPLEFT", frame.equipmentTitle, "BOTTOMLEFT", 0, -3)
    frame.equipmentSubtitle:SetPoint("RIGHT", -240, 0)
    frame.equipmentSubtitle:SetText(L.ARSENAL_EQUIPMENT_SUBTITLE)
    frame.equipmentTimestamp = Widgets:CreateLabel(frame.equipmentPanel, "GameFontDisableSmall", "RIGHT")
    frame.equipmentTimestamp:SetPoint("TOPRIGHT", -14, -14)
    frame.equipmentTimestamp:SetWidth(210)

    frame.issueFilter = Widgets:CreateButton(frame.equipmentPanel, L.ARSENAL_FILTER_ISSUES, 118, 23)
    frame.issueFilter:SetPoint("TOPRIGHT", -14, -34)
    frame.issueFilter:SetScript("OnClick", function()
        frame.issuesOnly = not frame.issuesOnly
        frame:RefreshEquipment()
    end)

    frame.leftSlots = CreateFrame("Frame", nil, frame.equipmentPanel)
    frame.leftSlots:SetPoint("TOPLEFT", 12, -68)
    frame.leftSlots:SetPoint("BOTTOMLEFT", 12, 12)
    frame.leftSlots:SetWidth(236)

    frame.rightSlots = CreateFrame("Frame", nil, frame.equipmentPanel)
    frame.rightSlots:SetPoint("TOPRIGHT", -12, -68)
    frame.rightSlots:SetPoint("BOTTOMRIGHT", -12, 12)
    frame.rightSlots:SetWidth(236)

    frame.centerEquipment = CreateFrame("Frame", nil, frame.equipmentPanel)
    frame.centerEquipment:SetPoint("TOPLEFT", frame.leftSlots, "TOPRIGHT", 10, 0)
    frame.centerEquipment:SetPoint("BOTTOMRIGHT", frame.rightSlots, "BOTTOMLEFT", -10, 0)

    frame.modelPanel = Widgets:CreatePanel(frame.centerEquipment, "hero")
    frame.modelPanel:SetPoint("TOPLEFT", 0, 0)
    frame.modelPanel:SetPoint("TOPRIGHT", 0, 0)
    frame.modelPanel:SetHeight(250)
    frame.model = CreateFrame("PlayerModel", nil, frame.modelPanel)
    frame.model:SetPoint("TOPLEFT", 4, -4)
    frame.model:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.modelPortrait = frame.modelPanel:CreateTexture(nil, "ARTWORK")
    frame.modelPortrait:SetSize(130, 130)
    frame.modelPortrait:SetPoint("CENTER", 0, 8)
    frame.modelPortraitMask = addCircularMask(frame.modelPanel, frame.modelPortrait)
    frame.modelPortraitBackplate = frame.modelPanel:CreateTexture(nil, "BACKGROUND")
    frame.modelPortraitBackplate:SetSize(146, 146)
    frame.modelPortraitBackplate:SetPoint("CENTER", frame.modelPortrait, "CENTER", 0, 0)
    frame.modelPortraitBackplate:SetTexture(Assets.classBackplate)
    frame.modelPortraitRing = frame.modelPanel:CreateTexture(nil, "OVERLAY")
    frame.modelPortraitRing:SetSize(146, 146)
    frame.modelPortraitRing:SetPoint("CENTER", frame.modelPortrait, "CENTER", 0, 0)
    frame.modelPortraitRing:SetTexture(Assets.classRing)
    frame.modelCaption = Widgets:CreateLabel(frame.modelPanel, "GameFontDisableSmall", "CENTER")
    frame.modelCaption:SetPoint("BOTTOMLEFT", 8, 9)
    frame.modelCaption:SetPoint("BOTTOMRIGHT", -8, 9)

    frame.statsPanel = Widgets:CreatePanel(frame.centerEquipment, "cardInset")
    frame.statsPanel:SetPoint("TOPLEFT", frame.modelPanel, "BOTTOMLEFT", 0, -9)
    frame.statsPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.statsTitle = Widgets:CreateLabel(frame.statsPanel, "GameFontNormal", "LEFT")
    frame.statsTitle:SetPoint("TOPLEFT", 12, -10)
    frame.statsTitle:SetText(L.ARSENAL_EQUIPMENT_TITLE)
    frame.statsRows = {}
    local previousStat
    for index = 1, 5 do
        local row = createStatRow(frame.statsPanel, previousStat)
        if not previousStat then row:SetPoint("TOP", frame.statsTitle, "BOTTOM", 0, -8) end
        frame.statsRows[index] = row
        previousStat = row
    end

    local slotColumns = Addon.ArsenalLogic:GetSlotColumns()
    for side, definitions in pairs(slotColumns) do
        local parent = side == "left" and frame.leftSlots or frame.rightSlots
        local previous
        for index, definition in ipairs(definitions) do
            local card = createSlotCard(parent)
            card.definition = definition
            card:SetPoint("LEFT", 7, 0)
            card:SetPoint("RIGHT", -7, 0)
            if previous then
                card:SetPoint("TOP", previous, "BOTTOM", 0, -SLOT_CARD_GAP)
            else
                card:SetPoint("TOP", parent, "TOP", 0, 0)
            end
            frame.slotCards[side][index] = card
            previous = card
        end
    end

    frame.equipmentEmpty = Widgets:CreateLabel(frame.equipmentPanel, "GameFontDisable", "CENTER")
    frame.equipmentEmpty:SetPoint("TOPLEFT", 20, -90)
    frame.equipmentEmpty:SetPoint("BOTTOMRIGHT", -20, 20)
    frame.equipmentEmpty:SetWordWrap(true)
    frame.equipmentEmpty:SetText(L.ARSENAL_NO_EQUIPMENT)
    frame.equipmentEmpty:Hide()

    frame.inventoryPanel = CreateFrame("Frame", nil, frame.content)
    frame.inventoryPanel:SetAllPoints(frame.content)
    frame.inventoryTitle = Widgets:CreateLabel(frame.inventoryPanel, "GameFontNormalLarge", "LEFT")
    frame.inventoryTitle:SetPoint("TOPLEFT", 14, -12)
    frame.inventorySubtitle = Widgets:CreateLabel(frame.inventoryPanel, "GameFontDisableSmall", "LEFT")
    frame.inventorySubtitle:SetPoint("TOPLEFT", frame.inventoryTitle, "BOTTOMLEFT", 0, -3)
    frame.inventorySubtitle:SetPoint("TOPRIGHT", -220, 0)
    frame.inventoryTimestamp = Widgets:CreateLabel(frame.inventoryPanel, "GameFontDisableSmall", "RIGHT")
    frame.inventoryTimestamp:SetPoint("TOPRIGHT", -14, -14)
    frame.inventoryTimestamp:SetWidth(205)

    frame.containerSelector = CreateFrame("Frame", nil, frame.inventoryPanel)
    frame.containerSelector:SetPoint("TOPLEFT", 14, -57)
    frame.containerSelector:SetPoint("TOPRIGHT", -14, -57)
    frame.containerSelector:SetHeight(28)

    frame.containerUsage = Widgets:CreateLabel(frame.inventoryPanel, "GameFontHighlightSmall", "LEFT")
    frame.containerUsage:SetPoint("TOPLEFT", frame.containerSelector, "BOTTOMLEFT", 0, -10)
    frame.containerFree = Widgets:CreateLabel(frame.inventoryPanel, "GameFontDisableSmall", "RIGHT")
    frame.containerFree:SetPoint("TOPRIGHT", frame.containerSelector, "BOTTOMRIGHT", 0, -10)

    frame.inventoryScroll = CreateFrame("ScrollFrame", nil, frame.inventoryPanel, "UIPanelScrollFrameTemplate")
    frame.inventoryScroll:SetPoint("TOPLEFT", frame.containerUsage, "BOTTOMLEFT", 0, -10)
    frame.inventoryScroll:SetPoint("BOTTOMRIGHT", -31, 14)
    frame.inventoryChild = CreateFrame("Frame", nil, frame.inventoryScroll)
    frame.inventoryChild:SetSize(700, 10)
    frame.inventoryScroll:SetScrollChild(frame.inventoryChild)
    ScrollFrames:Style(frame.inventoryScroll, { autoHide = true })

    frame.inventoryEmpty = Widgets:CreateLabel(frame.inventoryPanel, "GameFontDisable", "CENTER")
    frame.inventoryEmpty:SetPoint("TOPLEFT", 24, -100)
    frame.inventoryEmpty:SetPoint("BOTTOMRIGHT", -24, 24)
    frame.inventoryEmpty:SetWordWrap(true)
    frame.inventoryEmpty:Hide()

    function frame:EnsureContainerButtons(count)
        while #self.containerButtons < count do
            local button = Widgets:CreateButton(self.containerSelector, "", 100, 24)
            button:SetScript("OnClick", function(selfButton)
                local mode = Addon.Database:GetUI().selectedSubTabs.arsenal
                frame.selectedContainerByMode[mode] = selfButton.containerIndex
                frame:RefreshInventory()
            end)
            self.containerButtons[#self.containerButtons + 1] = button
        end
    end

    function frame:EnsureInventorySlots(count)
        while #self.inventorySlots < count do
            self.inventorySlots[#self.inventorySlots + 1] = createInventorySlot(self.inventoryChild)
        end
    end

    function frame:RefreshEquipment()
        local character = Addon.WarbandRoster:GetSelected()
        local view = character and Addon.Arsenal:GetView("equipment", character.key) or nil
        local snapshot = view and view.snapshot
        local equipment = snapshot and snapshot.equipment
        local available = type(equipment) == "table" and next(equipment) ~= nil

        self.equipmentTimestamp:SetText(formatTimestamp(snapshot and snapshot.updatedAt, view and view.current))
        if not available then self.equipmentSubtitle:SetText(L.ARSENAL_EQUIPMENT_SUBTITLE) end
        self.equipmentEmpty:SetText(L.ARSENAL_NO_EQUIPMENT)
        self.equipmentEmpty:SetShown(not available)
        self.issueFilter:SetShown(available)
        self.leftSlots:SetShown(available)
        self.rightSlots:SetShown(available)
        self.centerEquipment:SetShown(available)
        if not available then return end

        local summary = snapshot.summary or Addon.ArsenalLogic:BuildEquipmentSummary(equipment)
        self.equipmentSubtitle:SetText(string.format(
            L.ARSENAL_SUMMARY_FORMAT,
            summary.equipped or 0,
            summary.totalSlots or 16,
            summary.missingEnchants or 0,
            summary.emptySockets or 0,
            summary.upgradeable or 0
        ))
        self.issueFilter.label:SetText(self.issuesOnly and L.ARSENAL_FILTER_ALL or L.ARSENAL_FILTER_ISSUES)
        Widgets:SetButtonActive(self.issueFilter, self.issuesOnly)

        local characterInfo = view.character or character
        local modelShown = false
        if view.current and self.model and type(self.model.SetUnit) == "function" then
            local ok = pcall(self.model.SetUnit, self.model, "player")
            if ok then
                if type(self.model.SetCamDistanceScale) == "function" then pcall(self.model.SetCamDistanceScale, self.model, 1.15) end
                if type(self.model.SetPortraitZoom) == "function" then pcall(self.model.SetPortraitZoom, self.model, 0) end
                modelShown = true
            end
        end
        self.model:SetShown(modelShown)
        self.modelPortrait:SetShown(not modelShown)
        self.modelPortraitBackplate:SetShown(not modelShown)
        self.modelPortraitRing:SetShown(not modelShown)
        if not modelShown then
            local portraitMode = setClassPortrait(self.modelPortrait, characterInfo, view.current)
            local classFallback = portraitMode == "class"
            local portraitSize = classFallback and CLASS_FALLBACK_SIZE or SAVED_PORTRAIT_SIZE
            local frameSize = classFallback and CLASS_FALLBACK_FRAME_SIZE or SAVED_PORTRAIT_FRAME_SIZE
            self.modelPortrait:SetSize(portraitSize, portraitSize)
            self.modelPortraitBackplate:SetSize(frameSize, frameSize)
            self.modelPortraitRing:SetSize(frameSize, frameSize)
        end
        self.modelCaption:SetText(view.current and L.ARSENAL_CURRENT_MODEL or L.ARSENAL_SAVED_PORTRAIT)

        setStatRow(self.statsRows[1], L.ARSENAL_EQUIPPED,
            string.format("%d/%d", summary.equipped or 0, summary.totalSlots or 16),
            (summary.emptySlots or 0) > 0)
        setStatRow(self.statsRows[2], L.ARSENAL_ENCHANTS,
            tostring(summary.missingEnchants or 0),
            (summary.missingEnchants or 0) > 0)
        setStatRow(self.statsRows[3], L.ARSENAL_SOCKETS,
            tostring(summary.emptySockets or 0),
            (summary.emptySockets or 0) > 0)
        setStatRow(self.statsRows[4], L.ARSENAL_UPGRADES,
            tostring(summary.upgradeable or 0),
            (summary.upgradeable or 0) > 0)
        setStatRow(self.statsRows[5], L.ARSENAL_DURABILITY,
            summary.durabilityPercent and (tostring(summary.durabilityPercent) .. "%") or "--",
            summary.durabilityPercent and summary.durabilityPercent < 40)

        local visibleIssues = 0
        for side, definitions in pairs(Addon.ArsenalLogic:GetSlotColumns()) do
            local previous
            local parent = side == "left" and self.leftSlots or self.rightSlots
            for index, definition in ipairs(definitions) do
                local card = self.slotCards[side][index]
                local slotID = Addon.ArsenalLogic:GetSlotID(definition)
                local entry = slotID and equipment[slotID] or nil
                applySlotCard(card, definition, entry)
                local shown = not self.issuesOnly or (card.issue and card.issue.hasIssue)
                card:SetShown(shown)
                card:ClearAllPoints()
                card:SetPoint("LEFT", 7, 0)
                card:SetPoint("RIGHT", -7, 0)
                if shown then
                    if previous then
                        card:SetPoint("TOP", previous, "BOTTOM", 0, -SLOT_CARD_GAP)
                    else
                        card:SetPoint("TOP", parent, "TOP", 0, 0)
                    end
                    previous = card
                    if card.issue and card.issue.hasIssue then visibleIssues = visibleIssues + 1 end
                end
            end
        end
        if self.issuesOnly and visibleIssues == 0 then
            self.equipmentEmpty:SetText(L.ARSENAL_NO_ISSUES)
            self.equipmentEmpty:Show()
            self.leftSlots:Hide()
            self.rightSlots:Hide()
            self.centerEquipment:Hide()
        else
            self.equipmentEmpty:SetText(L.ARSENAL_NO_EQUIPMENT)
        end
    end

    function frame:RefreshInventory()
        local mode = Addon.Database:GetUI().selectedSubTabs.arsenal
        local copy = MODE_COPY[mode] or MODE_COPY.bags
        local character = Addon.WarbandRoster:GetSelected()
        local view = character and Addon.Arsenal:GetView(mode, character.key) or nil
        local snapshot = view and view.snapshot
        local containers = type(snapshot and snapshot.containers) == "table" and snapshot.containers or {}
        local available = #containers > 0

        self.inventoryTitle:SetText(copy.title())
        self.inventorySubtitle:SetText(copy.subtitle())
        self.inventoryTimestamp:SetText(formatTimestamp(snapshot and snapshot.updatedAt, view and view.current and mode == "bags"))
        self.inventoryEmpty:SetText(copy.empty())
        self.inventoryEmpty:SetShown(not available)
        self.containerSelector:SetShown(available)
        self.containerUsage:SetShown(available)
        self.containerFree:SetShown(available)
        self.inventoryScroll:SetShown(available)
        if not available then return end

        local selected = math.max(1, math.min(#containers, tonumber(self.selectedContainerByMode[mode]) or 1))
        self.selectedContainerByMode[mode] = selected
        self:EnsureContainerButtons(#containers)
        local width = math.max(76, math.min(112, math.floor((720 - ((#containers - 1) * 5)) / #containers)))
        local previous
        for index, button in ipairs(self.containerButtons) do
            local container = containers[index]
            button:SetShown(container ~= nil)
            if container then
                button.containerIndex = index
                button:SetWidth(width)
                button:ClearAllPoints()
                if previous then
                    button:SetPoint("LEFT", previous, "RIGHT", 5, 0)
                else
                    button:SetPoint("LEFT", 0, 0)
                end
                button.label:SetText(getContainerLabel(container, index))
                Widgets:SetButtonActive(button, index == selected)
                previous = button
            end
        end

        local container = containers[selected]
        local occupied, totalSlots, free = Addon.ArsenalLogic:CountContainer(container)
        self.containerUsage:SetText(string.format(
            "%s  |  %s",
            getContainerLabel(container, selected),
            string.format(L.ARSENAL_CONTAINER_USAGE, occupied, totalSlots)
        ))
        self.containerFree:SetText(string.format(L.ARSENAL_CONTAINER_FREE, free))

        self:EnsureInventorySlots(totalSlots)
        local columns, size, gap = 13, 42, 8
        for slotIndex, slot in ipairs(self.inventorySlots) do
            local shown = slotIndex <= totalSlots
            slot:SetShown(shown)
            if shown then
                local column = (slotIndex - 1) % columns
                local row = math.floor((slotIndex - 1) / columns)
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", column * (size + gap), -(row * (size + gap)))
                local item = container.items and container.items[slotIndex]
                slot.itemLink = item and item.itemLink or nil
                if item then
                    slot.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    slot.icon:Show()
                    slot.count:SetText((tonumber(item.count) or 1) > 1 and tostring(item.count) or "")
                    slot.count:Show()
                    setQualityBorder(slot, item.quality, 0.95)
                else
                    slot.icon:Hide()
                    slot.count:Hide()
                    slot:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.42)
                end
            end
        end
        local rows = totalSlots > 0 and math.ceil(totalSlots / columns) or 1
        self.inventoryChild:SetHeight(math.max(10, (rows * (size + gap)) - gap))
        ScrollFrames:Refresh(self.inventoryScroll, true)
    end

    function frame:Refresh()
        local mode = Addon.Database:GetUI().selectedSubTabs.arsenal
        if not self.modeButtons[mode] then
            mode = "equipment"
            Addon.Database:GetUI().selectedSubTabs.arsenal = mode
        end
        for key, button in pairs(self.modeButtons) do
            Widgets:SetButtonActive(button, key == mode)
        end
        self.equipmentPanel:SetShown(mode == "equipment")
        self.inventoryPanel:SetShown(mode ~= "equipment")
        if mode == "equipment" then
            self:RefreshEquipment()
        else
            self:RefreshInventory()
        end
    end

    frame:SetScript("OnShow", function()
        Addon.Arsenal:RefreshCurrent()
        frame:Refresh()
    end)
    frame:SetScript("OnHide", hideTooltip)
    Addon.StateStore:Subscribe("arsenal.snapshots", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "arsenal",
    order = 2,
    label = function() return L.SCREEN_ARSENAL end,
    Create = createScreen,
})
