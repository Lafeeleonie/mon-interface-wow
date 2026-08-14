local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local Logic = Addon.CompendiumLogic
local ScrollFrames = Addon.ScrollFrames
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local LINE_HEIGHT = 48
local POOL_SIZE = 18
local STATUS_COLORS = {
    collected = { 0.34, 0.88, 0.48, 1 },
    missing = Theme.colors.gold,
    unknown = Theme.colors.muted,
}

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function addCircularMask(owner, texture)
    if not owner or not texture
        or type(owner.CreateMaskTexture) ~= "function"
        or type(texture.AddMaskTexture) ~= "function"
    then
        return nil
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function addTooltip(frame, title, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(title or "", unpackColor(Theme.colors.gold))
    for _, line in ipairs(lines or {}) do
        if line.value and line.value ~= "" then
            GameTooltip:AddLine((line.label or "") .. ": " .. tostring(line.value), 0.92, 0.92, 0.92, true)
        end
    end
    GameTooltip:Show()
end

local function createItemRow(parent, service)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(42)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Addon.Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.90)
    row:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.background:SetTexture(Addon.Assets.row)

    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -6)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 6)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(31, 31)
    row.icon:SetPoint("LEFT", 11, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconMask = addCircularMask(row, row.icon)

    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetSize(38, 38)
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.iconBorder:SetTexture(Addon.Assets.compendiumIconBorder)

    row.name = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.name:SetPoint("RIGHT", -120, 0)
    row.name:SetHeight(18)

    row.source = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.source:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.source:SetPoint("RIGHT", -120, 0)
    row.source:SetHeight(15)

    row.status = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.status:SetWidth(74)

    row.waypoint = CreateFrame("Button", nil, row)
    row.waypoint:SetSize(24, 24)
    row.waypoint:SetPoint("RIGHT", -8, 0)
    row.status:SetPoint("RIGHT", row.waypoint, "LEFT", -8, 0)
    row.waypoint.icon = row.waypoint:CreateTexture(nil, "ARTWORK")
    row.waypoint.icon:SetAllPoints(row.waypoint)
    row.waypoint.icon:SetTexture(Addon.Assets.compendiumWaypointIcon)
    row.waypoint.iconBorder = row.waypoint:CreateTexture(nil, "OVERLAY")
    row.waypoint.iconBorder:SetSize(30, 30)
    row.waypoint.iconBorder:SetPoint("CENTER", row.waypoint.icon, "CENTER", 0, 0)
    row.waypoint.iconBorder:SetTexture(Addon.Assets.compendiumIconBorder)
    row.waypoint:SetScript("OnClick", function(self)
        if self.ownerRecord then service:SetWaypoint(self.ownerRecord) end
    end)
    row.waypoint:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(L.COMPENDIUM_TOOLTIP_SET_WAYPOINT, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(L.COMPENDIUM_TOOLTIP_CLICK_WAYPOINT, 0.92, 0.92, 0.92, true)
            GameTooltip:Show()
        end
    end)
    row.waypoint:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpackColor(Theme.colors.gold))
        if self.record then
            addTooltip(self, self.record.runtime.name, Logic:GetDetailLines(self.record.entry, self.record.runtime))
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.record and self.record.entry.achievementID then service:OpenAchievement(self.record) end
    end)
    row:Hide()
    return row
end

local function createPoolLine(parent, service)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(LINE_HEIGHT)
    line.group = Widgets:CreateLabel(line, "GameFontNormal", "LEFT")
    line.group:SetPoint("LEFT", 5, 0)
    line.group:SetPoint("RIGHT", -5, 0)
    line.group:SetTextColor(unpackColor(Theme.colors.gold))
    line.group:Hide()
    line.left = createItemRow(line, service)
    line.right = createItemRow(line, service)
    return line
end

local function layoutItemRowActions(row, hasWaypoint)
    local contentRight = hasWaypoint and -120 or -92
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.name:SetPoint("RIGHT", contentRight, 0)
    row.source:ClearAllPoints()
    row.source:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.source:SetPoint("RIGHT", contentRight, 0)
    row.status:ClearAllPoints()
    if hasWaypoint then
        row.status:SetPoint("RIGHT", row.waypoint, "LEFT", -8, 0)
    else
        row.status:SetPoint("RIGHT", -9, 0)
    end
end

local function applyRecord(row, record)
    if not record then row.record = nil; row:Hide(); return end
    local info = record.runtime
    local color = STATUS_COLORS[info.statusKey] or STATUS_COLORS.unknown
    row.record = record
    row.name:SetText(info.name or record.entry.name or L.UNKNOWN)
    row.source:SetText(info.professionLabel or info.sourceLabel or "")
    row.status:SetText(info.statusLabel or "")
    row.status:SetTextColor(unpackColor(color))
    row.statusLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.icon:SetTexture(info.icon or Logic:GetCategoryIcon(record.entry.category))
    local hasWaypoint = Logic:GetWaypoint(record.entry) ~= nil
    layoutItemRowActions(row, hasWaypoint)
    row.waypoint.ownerRecord = record
    row.waypoint:SetShown(hasWaypoint)
    row:Show()
end

local function buildLayout(entries)
    local lines = {}
    local current
    for _, entry in ipairs(entries or {}) do
        if entry.kind == "group" then
            current = nil
            lines[#lines + 1] = { kind = "group", label = entry.label, count = entry.count }
        elseif current and not current.right then
            current.right = entry
            current = nil
        else
            current = { kind = "items", left = entry }
            lines[#lines + 1] = current
        end
    end
    return lines
end

local function createScreen(_, host)
    local service = Addon.Compendium
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.layoutVersion = "compendium-midnight-1"
    frame.categoryButtons = {}
    frame.statusButtons = {}
    frame.pool = {}
    frame.layoutLines = {}

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalHuge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 2, -2)
    frame.title:SetText(L.COMPENDIUM_TAB_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("LEFT", frame.title, "RIGHT", 14, 0)
    frame.subtitle:SetPoint("RIGHT", -2, 0)
    frame.subtitle:SetText(L.COMPENDIUM_TAB_SUBTITLE)

    frame.sidebar = Widgets:CreatePanel(frame, "sidebar")
    frame.sidebar:SetPoint("TOPLEFT", 0, -42)
    frame.sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    frame.sidebar:SetWidth(194)

    frame.categoryTitle = Widgets:CreateLabel(frame.sidebar, "GameFontNormalLarge", "LEFT")
    frame.categoryTitle:SetPoint("TOPLEFT", 14, -14)
    frame.categoryTitle:SetPoint("TOPRIGHT", -14, -14)
    frame.categoryTitle:SetText(L.COMPENDIUM_FILTER_CATEGORIES)
    frame.categoryTitle:SetTextColor(unpackColor(Theme.colors.gold))

    for index, categoryKey in ipairs(Logic.CATEGORY_ORDER) do
        local button = Widgets:CreateButton(frame.sidebar, "", 166, 42, "row")
        button.categoryKey = categoryKey
        button:SetPoint("TOPLEFT", 14, -48 - ((index - 1) * 48))
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(28, 28)
        button.icon:SetPoint("LEFT", 8, 0)
        button.icon:SetTexture(Logic:GetCategoryIcon(categoryKey))
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.iconMask = addCircularMask(button, button.icon)
        button.iconBorder = Widgets:CreateRoundedIconBorder(button, button.icon, 1, Theme.colors.goldDim)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", 43, 0)
        button.label:SetPoint("RIGHT", -46, 0)
        button.label:SetJustifyH("LEFT")
        button.progress = Widgets:CreateLabel(button, "GameFontNormalSmall", "RIGHT")
        button.progress:SetPoint("RIGHT", -8, 0)
        button.progress:SetWidth(42)
        button:SetScript("OnClick", function(self) service:SetCategory(self.categoryKey) end)
        frame.categoryButtons[categoryKey] = button
    end

    frame.sidebarHint = Widgets:CreateLabel(frame.sidebar, "GameFontDisableSmall", "LEFT")
    frame.sidebarHint:SetPoint("BOTTOMLEFT", 14, 14)
    frame.sidebarHint:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.sidebarHint:SetWordWrap(true)
    frame.sidebarHint:SetText(L.COMPENDIUM_SIDEBAR_HINT)

    frame.content = Widgets:CreatePanel(frame, "content")
    frame.content:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 12, 0)
    frame.content:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.summary = Widgets:CreatePanel(frame.content, "cardInset")
    frame.summary:SetPoint("TOPLEFT", 14, -14)
    frame.summary:SetPoint("TOPRIGHT", -14, -14)
    frame.summary:SetHeight(48)
    frame.summaryLabels = {}
    for index = 1, 4 do
        local label = Widgets:CreateLabel(frame.summary, index == 1 and "GameFontNormal" or "GameFontHighlightSmall", "CENTER")
        label:SetWidth(250)
        label:SetPoint("TOPLEFT", (index - 1) * 250, 0)
        label:SetPoint("BOTTOM", 0, 0)
        frame.summaryLabels[index] = label
    end
    frame.summary:SetScript("OnSizeChanged", function(_, width)
        width = tonumber(width) or 0
        if width < 200 then width = 1080 end
        local labelWidth = math.floor(width / 4)
        for index, label in ipairs(frame.summaryLabels) do
            label:ClearAllPoints()
            label:SetWidth(labelWidth)
            label:SetPoint("TOPLEFT", (index - 1) * labelWidth, 0)
            label:SetPoint("BOTTOM", 0, 0)
        end
    end)

    frame.toolbar = CreateFrame("Frame", nil, frame.content)
    frame.toolbar:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -9)
    frame.toolbar:SetPoint("TOPRIGHT", frame.summary, "BOTTOMRIGHT", 0, -9)
    frame.toolbar:SetHeight(30)

    local statusDefinitions = {
        { key = "missing", text = L.COMPENDIUM_FILTER_STATUS_MISSING },
        { key = "all", text = L.COMPENDIUM_FILTER_STATUS_ALL },
        { key = "collected", text = L.COMPENDIUM_FILTER_STATUS_COLLECTED },
        { key = "unknown", text = L.COMPENDIUM_FILTER_STATUS_UNKNOWN },
    }
    for index, definition in ipairs(statusDefinitions) do
        local button = Widgets:CreateButton(frame.toolbar, definition.text, 78, 28)
        button.statusKey = definition.key
        if index == 1 then button:SetPoint("LEFT", 0, 0)
        else button:SetPoint("LEFT", frame.statusButtons[statusDefinitions[index - 1].key], "RIGHT", 3, 0) end
        button:SetScript("OnClick", function(self) service:SetStatus(self.statusKey) end)
        frame.statusButtons[definition.key] = button
    end

    frame.search = CreateFrame("EditBox", nil, frame.toolbar, BACKDROP_TEMPLATE)
    frame.search:SetSize(220, 28)
    frame.search:SetPoint("LEFT", frame.statusButtons.unknown, "RIGHT", 6, 0)
    frame.search:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Addon.Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame.search:SetBackdropColor(0.025, 0.022, 0.020, 0.94)
    frame.search:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    if frame.search.SetAutoFocus then frame.search:SetAutoFocus(false) end
    if frame.search.SetTextInsets then frame.search:SetTextInsets(9, 9, 0, 0) end
    if frame.search.SetFontObject then frame.search:SetFontObject("GameFontHighlightSmall") end
    frame.searchPlaceholder = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchPlaceholder:SetPoint("LEFT", 9, 0)
    frame.searchPlaceholder:SetPoint("RIGHT", -9, 0)
    frame.searchPlaceholder:SetText(L.COMPENDIUM_SEARCH_PLACEHOLDER)
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        frame.searchPlaceholder:SetShown(text == "")
        if not frame.syncingSearch then service:SetSearch(text) end
    end)

    frame.refresh = Widgets:CreateButton(frame.toolbar, L.COMPENDIUM_REFRESH, 90, 28)
    frame.refresh:SetPoint("RIGHT", 0, 0)
    frame.refresh:SetScript("OnClick", function() service:Refresh() end)

    frame.source = Widgets:CreateButton(frame.toolbar, "", 178, 28)
    frame.source:SetPoint("RIGHT", frame.refresh, "LEFT", -4, 0)
    if frame.source.RegisterForClicks then frame.source:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    frame.source:SetScript("OnClick", function(_, mouseButton)
        service:CycleSource(mouseButton == "RightButton" and -1 or 1)
    end)

    frame.profession = Widgets:CreateButton(frame.toolbar, "", 178, 28)
    frame.profession:SetPoint("RIGHT", frame.source, "LEFT", -4, 0)
    if frame.profession.RegisterForClicks then frame.profession:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    frame.profession:SetScript("OnClick", function(_, mouseButton)
        service:CycleProfession(mouseButton == "RightButton" and -1 or 1)
    end)

    frame.listPanel = Widgets:CreatePanel(frame.content, "card")
    frame.listPanel:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -9)
    frame.listPanel:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", -14, 38)

    frame.empty = Widgets:CreateLabel(frame.listPanel, "GameFontHighlight", "CENTER")
    frame.empty:SetPoint("CENTER", 0, 0)
    frame.empty:SetWidth(620)
    frame.empty:SetWordWrap(true)

    frame.listScroll = CreateFrame("ScrollFrame", nil, frame.listPanel, "UIPanelScrollFrameTemplate")
    frame.listScroll:SetPoint("TOPLEFT", 10, -10)
    frame.listScroll:SetPoint("BOTTOMRIGHT", -28, 10)
    frame.listScroll:EnableMouseWheel(true)
    frame.listChild = CreateFrame("Frame", nil, frame.listScroll)
    frame.listChild:SetSize(1030, 10)
    frame.listScroll:SetScrollChild(frame.listChild)
    ScrollFrames:Style(frame.listScroll)
    for index = 1, POOL_SIZE do frame.pool[index] = createPoolLine(frame.listChild, service) end

    frame.footer = Widgets:CreateLabel(frame.content, "GameFontDisableSmall", "LEFT")
    frame.footer:SetPoint("BOTTOMLEFT", frame.listPanel, "BOTTOMLEFT", 2, -25)
    frame.footer:SetPoint("BOTTOMRIGHT", frame.listPanel, "BOTTOMRIGHT", -2, -25)
    frame.footer:SetHeight(18)

    function frame:LayoutPool()
        local width = tonumber(self.listScroll.GetWidth and self.listScroll:GetWidth()) or 0
        if width <= 60 then width = 1060 end
        self.listChild:SetWidth(math.max(100, width - 2))
        local columnWidth = math.max(180, math.floor((width - 12) / 2))
        for _, line in ipairs(self.pool) do
            line:SetWidth(math.max(100, width - 2))
            line.left:ClearAllPoints()
            line.left:SetPoint("TOPLEFT", 0, -3)
            line.left:SetWidth(columnWidth)
            line.right:ClearAllPoints()
            line.right:SetPoint("TOPLEFT", line.left, "TOPRIGHT", 8, 0)
            line.right:SetWidth(columnWidth)
        end
    end

    function frame:RenderVisible()
        local offset = tonumber(self.listScroll.GetVerticalScroll and self.listScroll:GetVerticalScroll()) or 0
        local first = math.max(1, math.floor(offset / LINE_HEIGHT) + 1)
        for poolIndex, line in ipairs(self.pool) do
            local lineIndex = first + poolIndex - 1
            local data = self.layoutLines[lineIndex]
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 0, -((lineIndex - 1) * LINE_HEIGHT))
            if data then
                if data.kind == "group" then
                    line.group:SetText(string.format("%s  |cff9a9185(%d)|r", data.label or "", data.count or 0))
                    line.group:Show()
                    applyRecord(line.left, nil)
                    applyRecord(line.right, nil)
                else
                    line.group:Hide()
                    applyRecord(line.left, data.left)
                    applyRecord(line.right, data.right)
                end
                line:Show()
            else
                line.group:Hide()
                applyRecord(line.left, nil)
                applyRecord(line.right, nil)
                line:Hide()
            end
        end
    end

    function frame:Refresh()
        local state = service:GetState()
        local view = state and state.view
        if not view then
            self.layoutLines = {}
            self.listChild:SetHeight(10)
            self.listScroll:Hide()
            self.empty:SetText(state and state.loadError and L.COMPENDIUM_LOAD_ERROR or L.COMPENDIUM_LOADING)
            self.empty:Show()
            return
        end

        local selected = view.state
        local allStats = view.categoryStats.all or {}
        self.summaryLabels[1]:SetText(string.format(L.COMPENDIUM_STAT_TOTAL, allStats.total or 0))
        self.summaryLabels[2]:SetText(string.format(L.COMPENDIUM_STAT_MISSING, allStats.missing or 0))
        self.summaryLabels[3]:SetText(string.format(L.COMPENDIUM_STAT_OWNED, allStats.collected or 0))
        self.summaryLabels[4]:SetText(string.format(L.COMPENDIUM_STAT_WAYPOINTS, view.waypointCount or 0))

        for _, categoryKey in ipairs(Logic.CATEGORY_ORDER) do
            local button = self.categoryButtons[categoryKey]
            local stats = view.categoryStats[categoryKey] or {}
            local active = categoryKey == selected.category
            button.label:SetText(Logic:GetCategoryLabel(categoryKey))
            button.progress:SetText(string.format(L.COMPENDIUM_PROGRESS_FORMAT, stats.collected or 0, stats.total or 0))
            Widgets:SetButtonActive(button, active)
            local borderColor = active and Theme.colors.gold or Theme.colors.goldDim
            button.iconBorder:SetBackdropBorderColor(
                borderColor[1], borderColor[2], borderColor[3], active and 0.96 or 0.78
            )
        end
        for statusKey, button in pairs(self.statusButtons) do
            Widgets:SetButtonActive(button, statusKey == selected.status)
        end

        local sourceLabel = L.COMPENDIUM_FILTER_SOURCE_ALL
        for _, option in ipairs(view.sourceOptions or {}) do
            if option.key == selected.source then sourceLabel = option.label; break end
        end
        self.source.label:SetText(string.format(L.COMPENDIUM_FILTER_SOURCE_FORMAT, sourceLabel))

        local professionLabel = L.COMPENDIUM_FILTER_PROFESSION_ALL
        for _, option in ipairs(view.professionOptions or {}) do
            if option.key == selected.profession then professionLabel = option.label; break end
        end
        self.profession.label:SetText(string.format(L.COMPENDIUM_FILTER_PROFESSION_FORMAT, professionLabel))
        self.profession:SetShown(selected.category == "recipes")

        local searchText = selected.search or ""
        if self.search:GetText() ~= searchText then
            self.syncingSearch = true
            self.search:SetText(searchText)
            self.syncingSearch = false
        end
        self.searchPlaceholder:SetShown(searchText == "")

        self.layoutLines = buildLayout(view.entries)
        self.listChild:SetHeight(math.max(10, #self.layoutLines * LINE_HEIGHT))
        self.listScroll:SetShown(#self.layoutLines > 0)
        self.empty:SetShown(#self.layoutLines == 0)
        self.empty:SetText(L.COMPENDIUM_EMPTY)
        self.footer:SetText(selected.category == "decorations"
            and L.COMPENDIUM_DECORATION_CATALOG_HINT
            or string.format("%d / %d", view.visibleCount or 0, view.totalRuntimeCount or 0))
        self:LayoutPool()
        self:RenderVisible()
    end

    frame.listScroll:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        frame:RenderVisible()
    end)
    frame.listScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = tonumber(self:GetVerticalScroll()) or 0
        local maximum = tonumber(self:GetVerticalScrollRange()) or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - (delta * LINE_HEIGHT * 2))))
        frame:RenderVisible()
    end)
    frame.listScroll:SetScript("OnSizeChanged", function()
        frame:LayoutPool()
        frame:RenderVisible()
    end)

    function frame:SetChromeVisible(visible)
        visible = visible == true
        if self.chromeVisible == visible then return end
        self.chromeVisible = visible
        if visible then service:Open() else service:Close() end
    end
    frame:SetScript("OnShow", function()
        if not frame.chromeVisible then frame:SetChromeVisible(true) end
        frame:Refresh()
    end)
    frame:SetScript("OnHide", function() frame:SetChromeVisible(false) end)
    Addon.StateStore:Subscribe("compendium.catalog", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "compendium",
    order = 10,
    label = function() return L.SCREEN_COMPENDIUM end,
    Create = createScreen,
})
