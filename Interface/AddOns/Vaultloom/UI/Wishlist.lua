local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local Assets = Addon.Assets
local ScrollFrames = Addon.ScrollFrames
local Tracker = Addon.JournalLootTracker
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Wishlist = {}
Addon.WishlistUI = Wishlist

local STATUS_FILTERS = {
    { key = "wish", label = function() return L.WISHLIST_STATUS_OPEN end },
    { key = "obtained", label = function() return L.WISHLIST_STATUS_OBTAINED end },
    { key = "all", label = function() return L.WISHLIST_FILTER_ALL end },
}

local SOURCE_FILTERS = {
    { key = "all", label = function() return L.WISHLIST_FILTER_ALL end },
    { key = "raids", label = function() return L.WISHLIST_SOURCE_RAIDS end },
    { key = "dungeons", label = function() return L.WISHLIST_SOURCE_DUNGEONS end },
}

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function difficultyLabel(key)
    if key == "lfr" then return L.WISHLIST_DIFFICULTY_LFR end
    if key == "heroic" then return L.WISHLIST_DIFFICULTY_HEROIC end
    if key == "mythic" then return L.WISHLIST_DIFFICULTY_MYTHIC end
    return L.WISHLIST_DIFFICULTY_NORMAL
end

local function trackerTexture(state)
    if state == "wish" then return Assets.raidTrackerWish end
    if state == "obtained" then return Assets.raidTrackerObtained end
    return Assets.raidTrackerNone
end

local function trackerColor(state)
    if state == "obtained" then return 0.34, 0.88, 0.48, 1 end
    return unpackColor(Theme.colors.gold)
end

local function sourceTypeLabel(source)
    return source and source.mainTabKey == "dungeons"
        and L.WISHLIST_SOURCE_DUNGEON
        or source and source.mainTabKey == "raids"
            and L.WISHLIST_SOURCE_RAID
            or L.WISHLIST_SOURCE_UNKNOWN
end

local function sourcePath(source)
    if type(source) ~= "table" then return L.WISHLIST_SOURCE_UNKNOWN end
    local instance = type(source.instanceName) == "string" and source.instanceName or ""
    local boss = type(source.bossName) == "string" and source.bossName or ""
    if instance ~= "" and boss ~= "" then return string.format("%s -> %s", instance, boss) end
    if instance ~= "" then return instance end
    if boss ~= "" then return boss end
    return L.WISHLIST_SOURCE_UNKNOWN
end

local function groupKey(entry)
    local source = entry and entry.primarySource
    if not source then return "unknown" end
    return string.format("%s:%s", source.mainTabKey or "unknown", source.instanceID or source.raidKey or source.instanceName or "")
end

local function groupLabel(entry)
    local source = entry and entry.primarySource
    if not source then return L.WISHLIST_GROUP_UNKNOWN end
    local instanceName = type(source.instanceName) == "string" and source.instanceName or ""
    if instanceName == "" then return sourceTypeLabel(source) end
    return string.format("%s  ·  %s", sourceTypeLabel(source), instanceName)
end

local function itemLevelLabel(item)
    if not item then return nil end
    local itemLevel
    if item.link and C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        itemLevel = C_Item.GetDetailedItemLevelInfo(item.link)
    end
    itemLevel = tonumber(itemLevel)
    return itemLevel and itemLevel > 0 and string.format(L.WISHLIST_ITEM_LEVEL, itemLevel) or nil
end

local function itemMeta(entry)
    local parts = {}
    local item = entry and entry.item or nil
    local itemType = item and (item.slot or item.armorType) or nil
    if type(itemType) == "string" and itemType ~= "" then parts[#parts + 1] = itemType end
    parts[#parts + 1] = difficultyLabel(entry and entry.difficultyKey)
    local level = itemLevelLabel(item)
    if level then parts[#parts + 1] = level end
    if item and item.veryRare then
        parts[#parts + 1] = L.RAID_LOOT_VERY_RARE
    elseif item and item.extremelyRare then
        parts[#parts + 1] = L.RAID_LOOT_EXTREMELY_RARE
    end
    return table.concat(parts, "  |  ")
end

local function showItemTooltip(row)
    if not GameTooltip or not row or not row.entry then return end
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT")
    if entry.item and entry.item.link and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(entry.item.link)
    elseif type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(entry.itemID)
    else
        GameTooltip:AddLine(entry.item and entry.item.name or L.UNKNOWN, 0.92, 0.92, 0.92, true)
    end

    if #entry.sources > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.WISHLIST_TOOLTIP_SOURCES, unpackColor(Theme.colors.gold))
        for _, source in ipairs(entry.sources) do
            GameTooltip:AddLine(
                string.format("%s  |  %s  |  %s", sourceTypeLabel(source), sourcePath(source), difficultyLabel(entry.difficultyKey)),
                0.86,
                0.86,
                0.82,
                true
            )
        end
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
end

local function addButtonTooltip(button, callback)
    local enter = button:GetScript("OnEnter")
    local leave = button:GetScript("OnLeave")
    button:SetScript("OnEnter", function(self)
        if enter then enter(self) end
        callback(self)
    end)
    button:SetScript("OnLeave", function(self)
        if leave then leave(self) end
        hideTooltip()
    end)
end

local function createFilterButtons(parent, definitions, xOffset)
    local buttons = {}
    local previous
    for _, definition in ipairs(definitions) do
        local button = Widgets:CreateButton(parent, definition.label(), 98, 26, "tab")
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", xOffset, 0)
        end
        button.filterKey = definition.key
        buttons[#buttons + 1] = button
        previous = button
    end
    return buttons
end

local function createGroupHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(25)
    header.label = Widgets:CreateLabel(header, "GameFontNormal", "LEFT")
    header.label:SetPoint("LEFT", 2, 0)
    header.label:SetPoint("RIGHT", -2, 0)
    header.label:SetTextColor(unpackColor(Theme.colors.gold))
    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetPoint("BOTTOMLEFT", 0, 0)
    header.divider:SetPoint("BOTTOMRIGHT", 0, 0)
    header.divider:SetHeight(1)
    header.divider:SetColorTexture(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.62)
    header:Hide()
    return header
end

local function createWishlistRow(parent, callbacks)
    local row = Widgets:CreatePanel(parent, "cardInset")
    row:SetHeight(64)
    row:EnableMouse(true)

    row.statusLine = row:CreateTexture(nil, "OVERLAY")
    row.statusLine:SetPoint("TOPLEFT", 4, -7)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 7)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)

    row.iconBorder = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    row.iconBorder:SetPoint("LEFT", 14, 0)
    row.iconBorder:SetSize(42, 42)
    row.iconBorder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row.iconBorder:SetBackdropColor(0, 0, 0, 0.78)
    row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(39, 39)
    row.icon:SetPoint("CENTER", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.removeButton = Widgets:CreateButton(row, "X", 30, 30)
    row.removeButton:SetPoint("RIGHT", -9, 0)
    row.removeButton:SetScript("OnClick", function()
        if row.entry and Tracker:RemoveEntry(
            row.entry.characterKey,
            row.entry.difficultyKey,
            row.entry.itemID
        ) then
            if callbacks.changed then callbacks.changed() end
            callbacks.refresh()
        end
    end)
    addButtonTooltip(row.removeButton, function(button)
        if not row.entry or not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(L.WISHLIST_REMOVE, unpackColor(Theme.colors.gold))
        GameTooltip:Show()
    end)

    row.trackButton = Widgets:CreateButton(row, "", 30, 30)
    row.trackButton:SetPoint("RIGHT", row.removeButton, "LEFT", -4, 0)
    row.trackButton.label:Hide()
    row.trackButton.icon = row.trackButton:CreateTexture(nil, "OVERLAY")
    row.trackButton.icon:SetSize(18, 18)
    row.trackButton.icon:SetPoint("CENTER", 0, 0)
    row.trackButton:SetScript("OnClick", function()
        if row.entry then
            Tracker:CycleEntry(row.entry.characterKey, row.entry.difficultyKey, row.entry.itemID)
            if callbacks.changed then callbacks.changed() end
            callbacks.refresh()
        end
    end)
    addButtonTooltip(row.trackButton, function(button)
        if not row.entry or not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(
            row.entry.state == "obtained" and L.RAID_LOOT_TRACKER_OBTAINED or L.RAID_LOOT_TRACKER_WISH,
            trackerColor(row.entry.state)
        )
        GameTooltip:AddLine(L.RAID_LOOT_TRACKER_CLICK, 0.72, 0.78, 0.88, true)
        GameTooltip:Show()
    end)

    row.sourceButton = Widgets:CreateButton(row, L.WISHLIST_SOURCE_OPEN, 96, 24)
    row.sourceButton:SetPoint("RIGHT", row.trackButton, "LEFT", -6, 0)
    row.sourceButton:SetScript("OnClick", function()
        if row.entry and row.entry.primarySource then
            callbacks.openSource(row.entry.primarySource, row.entry.difficultyKey)
        end
    end)

    row.name = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 10, -2)
    row.name:SetPoint("TOPRIGHT", row.sourceButton, "TOPLEFT", -10, -2)
    row.name:SetWordWrap(false)
    row.name:SetMaxLines(1)

    row.meta = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.meta:SetPoint("TOPRIGHT", row.sourceButton, "TOPLEFT", -10, 0)
    row.meta:SetWordWrap(false)
    row.meta:SetMaxLines(1)

    row.source = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.source:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -3)
    row.source:SetPoint("TOPRIGHT", row.sourceButton, "TOPLEFT", -10, 0)
    row.source:SetWordWrap(false)
    row.source:SetMaxLines(1)

    row:SetScript("OnEnter", showItemTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:Hide()
    return row
end

local function setWishlistRow(row, entry)
    if not entry then
        row.entry = nil
        row:Hide()
        return
    end

    row.entry = entry
    local item = entry.item or {}
    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(item.name or L.UNKNOWN)
    row.meta:SetText(itemMeta(entry))

    local sourceText = sourcePath(entry.primarySource)
    if #entry.sources > 1 then
        sourceText = string.format("%s  |  %s", sourceText, string.format(L.WISHLIST_SOURCE_MORE, #entry.sources - 1))
    end
    row.source:SetText(sourceText)
    row.sourceButton:SetShown(entry.primarySource ~= nil)
    row.trackButton.icon:SetTexture(trackerTexture(entry.state))
    Widgets:SetButtonActive(row.trackButton, entry.state ~= nil)
    row.statusLine:SetColorTexture(trackerColor(entry.state))

    local quality = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] or nil
    if quality then
        row.name:SetTextColor(quality.r, quality.g, quality.b, 1)
        row.iconBorder:SetBackdropBorderColor(quality.r, quality.g, quality.b, 0.96)
    else
        row.name:SetTextColor(unpackColor(Theme.colors.parchment))
        row.iconBorder:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.78)
    end
    row:Show()
end

function Wishlist:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = Widgets:CreatePanel(parent, "content")
    frame.layoutVersion = "wishlist-overlay-3"
    frame:Hide()
    frame.rows = {}
    frame.groupHeaders = {}

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 18, -16)
    frame.title:SetText(L.WISHLIST_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -14, -13)
    frame.closeButton:SetScript("OnClick", function() callbacks.close() end)

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -7)
    frame.subtitle:SetPoint("TOPRIGHT", frame.closeButton, "BOTTOMLEFT", -12, 0)
    frame.subtitle:SetText(L.WISHLIST_SUBTITLE)

    frame.summary = Widgets:CreateLabel(frame, "GameFontNormalSmall", "LEFT")
    frame.summary:SetPoint("TOPLEFT", frame.subtitle, "BOTTOMLEFT", 0, -7)
    frame.summary:SetPoint("TOPRIGHT", -18, 0)

    frame.filters = Widgets:CreatePanel(frame, "cardInset")
    frame.filters:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -12)
    frame.filters:SetPoint("TOPRIGHT", -18, 0)
    frame.filters:SetHeight(46)

    frame.statusLabel = Widgets:CreateLabel(frame.filters, "GameFontNormalSmall", "LEFT")
    frame.statusLabel:SetPoint("LEFT", 14, 0)
    frame.statusLabel:SetWidth(48)
    frame.statusLabel:SetText(L.WISHLIST_FILTER_STATUS)
    frame.statusButtons = createFilterButtons(frame.filters, STATUS_FILTERS, 66)

    frame.sourceLabel = Widgets:CreateLabel(frame.filters, "GameFontNormalSmall", "LEFT")
    frame.sourceLabel:SetPoint("LEFT", 404, 0)
    frame.sourceLabel:SetWidth(48)
    frame.sourceLabel:SetText(L.WISHLIST_FILTER_SOURCE)
    frame.sourceButtons = createFilterButtons(frame.filters, SOURCE_FILTERS, 458)

    frame.listPanel = Widgets:CreatePanel(frame, "inset")
    frame.listPanel:SetPoint("TOPLEFT", frame.filters, "BOTTOMLEFT", 0, -12)
    frame.listPanel:SetPoint("BOTTOMRIGHT", -18, 18)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame.listPanel, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 14, -14)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(self, delta)
        local nextValue = self:GetVerticalScroll() - (delta * 52)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), nextValue)))
    end)
    frame.scrollChild = CreateFrame("Frame", nil, frame.scroll)
    frame.scrollChild:SetSize(760, 10)
    frame.scroll:SetScrollChild(frame.scrollChild)
    frame.scroll:SetScript("OnSizeChanged", function(self, width)
        frame.scrollChild:SetWidth(math.max(320, (tonumber(width) or self:GetWidth() or 320) - 2))
    end)
    ScrollFrames:Style(frame.scroll)

    frame.empty = Widgets:CreateLabel(frame.scrollChild, "GameFontDisableLarge", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 30, -80)
    frame.empty:SetPoint("TOPRIGHT", -30, -80)
    frame.empty:SetText(L.WISHLIST_EMPTY)
    frame.emptyHint = Widgets:CreateLabel(frame.scrollChild, "GameFontDisableSmall", "CENTER")
    frame.emptyHint:SetPoint("TOPLEFT", frame.empty, "BOTTOMLEFT", 0, -10)
    frame.emptyHint:SetPoint("TOPRIGHT", frame.empty, "BOTTOMRIGHT", 0, -10)
    frame.emptyHint:SetText(L.WISHLIST_EMPTY_HINT)

    local function setFilter(kind, value)
        local settings = Addon.Database:GetUI().wishlist
        settings[kind] = value
        frame:Refresh()
    end

    for _, button in ipairs(frame.statusButtons) do
        button:SetScript("OnClick", function(self) setFilter("status", self.filterKey) end)
    end
    for _, button in ipairs(frame.sourceButtons) do
        button:SetScript("OnClick", function(self) setFilter("source", self.filterKey) end)
    end

    function frame:EnsureRows(count)
        while #self.rows < count do
            self.rows[#self.rows + 1] = createWishlistRow(self.scrollChild, {
                refresh = function() self:Refresh() end,
                openSource = callbacks.openSource,
                changed = callbacks.changed,
            })
        end
    end

    function frame:EnsureGroupHeaders(count)
        while #self.groupHeaders < count do
            self.groupHeaders[#self.groupHeaders + 1] = createGroupHeader(self.scrollChild)
        end
    end

    function frame:Refresh()
        local character = Addon.WarbandRoster:GetSelected() or Addon.StateStore:Get("character.identity")
        local characterKey = character and character.key or nil
        local settings = Addon.Database:GetUI().wishlist
        local counts = Tracker:GetCounts(characterKey)
        local entries = Tracker:GetEntries(characterKey, settings.status, settings.source)

        self.summary:SetText(string.format(
            L.WISHLIST_CHARACTER_SUMMARY,
            character and character.name or L.UNKNOWN,
            character and character.realm or L.UNKNOWN,
            counts.wish,
            counts.obtained
        ))
        for _, button in ipairs(self.statusButtons) do
            Widgets:SetButtonActive(button, button.filterKey == settings.status)
        end
        for _, button in ipairs(self.sourceButtons) do
            Widgets:SetButtonActive(button, button.filterKey == settings.source)
        end

        self:EnsureRows(#entries)
        local neededGroups = 0
        local previousGroup
        for _, entry in ipairs(entries) do
            local current = groupKey(entry)
            if current ~= previousGroup then
                neededGroups = neededGroups + 1
                previousGroup = current
            end
        end
        self:EnsureGroupHeaders(neededGroups)

        local yOffset = 0
        local rowIndex = 0
        local groupIndex = 0
        previousGroup = nil
        for _, entry in ipairs(entries) do
            local current = groupKey(entry)
            if current ~= previousGroup then
                groupIndex = groupIndex + 1
                local header = self.groupHeaders[groupIndex]
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", 2, -yOffset)
                header:SetPoint("TOPRIGHT", -2, -yOffset)
                header.label:SetText(groupLabel(entry))
                header:Show()
                yOffset = yOffset + 31
                previousGroup = current
            end

            rowIndex = rowIndex + 1
            local row = self.rows[rowIndex]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, -yOffset)
            row:SetPoint("TOPRIGHT", -2, -yOffset)
            setWishlistRow(row, entry)
            yOffset = yOffset + 70
        end

        for index = rowIndex + 1, #self.rows do setWishlistRow(self.rows[index], nil) end
        for index = groupIndex + 1, #self.groupHeaders do self.groupHeaders[index]:Hide() end
        self.empty:SetShown(#entries == 0)
        self.emptyHint:SetShown(#entries == 0)
        self.scrollChild:SetHeight(math.max(10, yOffset))
        ScrollFrames:Refresh(self.scroll, true)
    end

    return frame
end
