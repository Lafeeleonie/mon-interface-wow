local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ScrollFrames = Addon.ScrollFrames

local STATUS_COLORS = {
    complete = { 0.34, 0.88, 0.48, 1 },
    turnin = { 0.98, 0.76, 0.22, 1 },
    open = Theme.colors.gold,
    missing = Theme.colors.muted,
}

local function syncScrollWidth(scroll, child)
    local width = tonumber(scroll and scroll.GetWidth and scroll:GetWidth()) or 0
    if width > 20 then
        child:SetWidth(math.max(10, width - 2))
    elseif (tonumber(child and child.GetWidth and child:GetWidth()) or 0) < 20 then
        child:SetWidth(scroll.fallbackChildWidth)
    end
end

local function createScroll(parent, topAnchor, fallbackChildWidth, bottom)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, bottom or 12)
    scroll:EnableMouseWheel(true)
    scroll.fallbackChildWidth = math.max(20, tonumber(fallbackChildWidth) or 220)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scroll.fallbackChildWidth, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, width)
        if (tonumber(width) or 0) > 20 then child:SetWidth(math.max(10, width - 2))
        else syncScrollWidth(self, child) end
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = tonumber(self:GetVerticalScroll()) or 0
        local maximum = tonumber(self:GetVerticalScrollRange()) or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - (delta * 32))))
    end)
    ScrollFrames:Style(scroll)
    return scroll, child
end

local function createHeader(parent, title, subtitle)
    parent.title = Widgets:CreateLabel(parent, "GameFontNormalLarge", "LEFT")
    parent.title:SetPoint("TOPLEFT", 16, -16)
    parent.title:SetPoint("TOPRIGHT", -16, -16)
    parent.title:SetText(title)
    parent.subtitle = Widgets:CreateLabel(parent, "GameFontHighlightSmall", "LEFT")
    parent.subtitle:SetPoint("TOPLEFT", parent.title, "BOTTOMLEFT", 0, -7)
    parent.subtitle:SetPoint("TOPRIGHT", -16, 0)
    parent.subtitle:SetWordWrap(true)
    parent.subtitle:SetText(subtitle)
end

local function createSectionHeader(parent, text)
    local label = Widgets:CreateLabel(parent, "GameFontNormal", "LEFT")
    label:SetText(text)
    label:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
    return label
end

local function createStatCard(parent)
    local card = Widgets:CreatePanel(parent, "cardInset")
    card:SetHeight(64)
    card.label = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.label:SetPoint("TOPLEFT", 10, -8)
    card.label:SetPoint("TOPRIGHT", -10, -8)
    card.value = Widgets:CreateLabel(card, "GameFontNormalLarge", "LEFT")
    card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
    card.value:SetPoint("TOPRIGHT", -10, 0)
    card.meta = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.meta:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -2)
    card.meta:SetPoint("TOPRIGHT", -10, 0)
    return card
end

local function applyStatCard(card, entry)
    entry = type(entry) == "table" and entry or {}
    card.label:SetText(entry.label or "")
    card.value:SetText(entry.value or "--")
    card.meta:SetText(entry.meta or "")
    card.value:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
end

local function layoutStatCards(summaryPanel, cards, width)
    width = tonumber(width) or (summaryPanel.GetWidth and summaryPanel:GetWidth()) or 0
    local innerWidth = width > 200 and width - 28 or 748
    local gap = 12
    local cardWidth = math.max(112, math.floor((innerWidth - (gap * (#cards - 1))) / #cards))
    for index, card in ipairs(cards) do
        card:ClearAllPoints()
        card:SetWidth(cardWidth)
        if index == 1 then card:SetPoint("TOPLEFT", 14, -44)
        else card:SetPoint("TOPLEFT", cards[index - 1], "TOPRIGHT", gap, 0) end
    end
end

local function createTaskRow(parent, previous, service)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(48)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.88)
    row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -10)
    else
        row:SetPoint("TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", 0, 0)
    end
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    row.background:SetTexture(Addon.Assets.row)
    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -5)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 5)
    row.statusLine:SetWidth(3)
    row.label = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.label:SetPoint("TOPLEFT", 14, -7)
    row.label:SetPoint("BOTTOMRIGHT", -104, 7)
    row.label:SetJustifyV("TOP")
    row.label:SetWordWrap(true)
    row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.value:SetPoint("TOPRIGHT", -12, -9)
    row.value:SetWidth(84)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.90)
        if self.tooltipTitle and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(self.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            for _, line in ipairs(self.tooltipLines or {}) do
                if line and line ~= "" then GameTooltip:AddLine(line, 0.92, 0.92, 0.92, true) end
            end
            if service:CanToggleTasks() then
                GameTooltip:AddLine(self.tracked and L.HOUSING_TASK_UNTRACK_HINT or L.HOUSING_TASK_TRACK_HINT, 0.72, 0.72, 0.72, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.taskID ~= nil then service:ToggleTask(self.taskID, self.tracked) end
    end)
    row:Hide()
    return row
end

local function setTaskRow(row, entry)
    if not entry then row:Hide(); return end
    local color = STATUS_COLORS[entry.status] or STATUS_COLORS.missing
    local text = entry.title or ""
    if type(entry.meta) == "string" and entry.meta ~= "" then text = text .. "\n" .. entry.meta end
    row.label:SetText(text)
    row.value:SetText(entry.statusText or "")
    row.value:SetTextColor(color[1], color[2], color[3], 1)
    row.statusLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.taskID = entry.id
    row.tracked = entry.tracked == true
    row.tooltipTitle = entry.tooltipTitle
    row.tooltipLines = entry.tooltipLines
    row:Show()
end

local function createScreen(_, host)
    local shellFrame = Addon.UI.frame
    local service = Addon.Housing
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame:Hide()
    frame.layoutVersion = "housing-endeavors-1"

    frame.navigation = Widgets:CreateButton(frame, L.HOUSING_TAB_ENDEAVORS, 188, 24, "tab")
    frame.navigation:SetPoint("TOPLEFT", 0, 0)
    Widgets:SetButtonActive(frame.navigation, true)
    frame.subTabButtons = { endeavors = frame.navigation }

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation, "BOTTOMLEFT", 0, -10)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.summaryPanel = Widgets:CreatePanel(frame.contentHost, "card")
    frame.summaryPanel:SetPoint("TOPLEFT", 0, 0)
    frame.summaryPanel:SetPoint("TOPRIGHT", 0, 0)
    frame.summaryPanel:SetHeight(196)
    frame.summaryTitle = Widgets:CreateLabel(frame.summaryPanel, "GameFontNormalLarge", "LEFT")
    frame.summaryTitle:SetPoint("TOPLEFT", 14, -14)
    frame.summaryTitle:SetPoint("TOPRIGHT", -14, -14)
    frame.summaryTitle:SetText(L.HOUSING_TITLE)
    frame.summarySubtitle = Widgets:CreateLabel(frame.summaryPanel, "GameFontHighlightSmall", "LEFT")
    frame.summarySubtitle:SetPoint("TOPLEFT", frame.summaryTitle, "BOTTOMLEFT", 0, -6)
    frame.summarySubtitle:SetPoint("TOPRIGHT", -14, 0)
    frame.summarySubtitle:Hide()
    frame.statCards = {}
    for index = 1, 4 do frame.statCards[index] = createStatCard(frame.summaryPanel) end
    layoutStatCards(frame.summaryPanel, frame.statCards)
    frame.summaryPanel:SetScript("OnSizeChanged", function(_, width)
        layoutStatCards(frame.summaryPanel, frame.statCards, width)
    end)
    frame.progressLabel = Widgets:CreateLabel(frame.summaryPanel, "GameFontHighlightSmall", "LEFT")
    frame.progressLabel:SetPoint("TOPLEFT", frame.statCards[1], "BOTTOMLEFT", 0, -14)
    frame.progressValue = Widgets:CreateLabel(frame.summaryPanel, "GameFontHighlightSmall", "RIGHT")
    frame.progressValue:SetPoint("RIGHT", -14, 0)
    frame.progressValue:SetPoint("CENTER", frame.progressLabel, "CENTER", 0, 0)
    frame.progressBar = Widgets:CreateProgressBar(frame.summaryPanel)
    frame.progressBar:SetPoint("TOPLEFT", frame.progressLabel, "BOTTOMLEFT", 0, -7)
    frame.progressBar:SetPoint("TOPRIGHT", -14, 0)
    frame.progressBar:SetHeight(12)
    frame.progressNote = Widgets:CreateLabel(frame.summaryPanel, "GameFontDisableSmall", "LEFT")
    frame.progressNote:SetPoint("TOPLEFT", frame.progressBar, "BOTTOMLEFT", 0, -10)
    frame.progressNote:SetPoint("TOPRIGHT", -14, 0)
    frame.progressNote:SetWordWrap(true)

    frame.tasksPanel = Widgets:CreatePanel(frame.contentHost, "cardInset")
    frame.tasksPanel:SetPoint("TOPLEFT", frame.summaryPanel, "BOTTOMLEFT", 0, -14)
    frame.tasksPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.tasksTitle = Widgets:CreateLabel(frame.tasksPanel, "GameFontNormalLarge", "LEFT")
    frame.tasksTitle:SetPoint("TOPLEFT", 14, -14)
    frame.tasksTitle:SetText(L.HOUSING_SECTION_TASKS)
    frame.tasksSubtitle = Widgets:CreateLabel(frame.tasksPanel, "GameFontHighlightSmall", "LEFT")
    frame.tasksSubtitle:SetPoint("TOPLEFT", frame.tasksTitle, "BOTTOMLEFT", 0, -6)
    frame.tasksSubtitle:SetPoint("TOPRIGHT", -14, 0)
    frame.tasksSubtitle:SetWordWrap(true)
    frame.tasksSubtitle:SetText(L.HOUSING_SECTION_TASKS_SUBTITLE)
    frame.tasksScroll, frame.tasksScrollChild = createScroll(frame.tasksPanel, frame.tasksSubtitle, 690)
    frame.tasksEmpty = Widgets:CreateLabel(frame.tasksScrollChild, "GameFontDisable", "LEFT")
    frame.tasksEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.tasksEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.tasksEmpty:SetWordWrap(true)
    frame.taskRows = {}
    frame.contentEmpty = Widgets:CreateLabel(frame.contentHost, "GameFontDisableLarge", "LEFT")
    frame.contentEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.contentEmpty:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.contentEmpty:SetJustifyV("TOP")
    frame.contentEmpty:SetWordWrap(true)
    frame.contentEmpty:Hide()

    frame.sidebarPanel = Widgets:CreatePanel(shellFrame.sidebar, "sidebar")
    frame.sidebarPanel:SetAllPoints(shellFrame.sidebar)
    frame.sidebarPanel:SetFrameLevel(shellFrame.sidebar:GetFrameLevel() + 10)
    createHeader(frame.sidebarPanel, L.HOUSING_TITLE, L.HOUSING_SECTION_HOME_SUBTITLE)
    frame.homeHeader = createSectionHeader(frame.sidebarPanel, L.HOUSING_SECTION_HOME)
    frame.homeHeader:SetPoint("TOPLEFT", frame.sidebarPanel.subtitle, "BOTTOMLEFT", 0, -14)
    frame.homeHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.homePanel = Widgets:CreatePanel(frame.sidebarPanel, "cardInset")
    frame.homePanel:SetPoint("TOPLEFT", frame.homeHeader, "BOTTOMLEFT", 0, -8)
    frame.homePanel:SetPoint("TOPRIGHT", -16, 0)
    frame.homePanel:SetHeight(168)
    frame.homeName = Widgets:CreateLabel(frame.homePanel, "GameFontNormalLarge", "LEFT")
    frame.homeName:SetPoint("TOPLEFT", 14, -13)
    frame.homeName:SetPoint("TOPRIGHT", -14, -13)
    frame.homeSubtitle = Widgets:CreateLabel(frame.homePanel, "GameFontHighlightSmall", "LEFT")
    frame.homeSubtitle:SetPoint("TOPLEFT", frame.homeName, "BOTTOMLEFT", 0, -5)
    frame.homeSubtitle:SetPoint("TOPRIGHT", -14, 0)
    frame.homeMeta = Widgets:CreateLabel(frame.homePanel, "GameFontDisableSmall", "LEFT")
    frame.homeMeta:SetPoint("TOPLEFT", frame.homeSubtitle, "BOTTOMLEFT", 0, -6)
    frame.homeMeta:SetPoint("TOPRIGHT", -14, 0)
    frame.homeLevelLabel = Widgets:CreateLabel(frame.homePanel, "GameFontDisableSmall", "LEFT")
    frame.homeLevelLabel:SetPoint("TOPLEFT", frame.homeMeta, "BOTTOMLEFT", 0, -10)
    frame.homeLevelLabel:SetText(L.HOUSING_HOME_LEVEL)
    frame.homeLevelValue = Widgets:CreateLabel(frame.homePanel, "GameFontHighlightSmall", "RIGHT")
    frame.homeLevelValue:SetPoint("RIGHT", -14, 0)
    frame.homeLevelValue:SetPoint("CENTER", frame.homeLevelLabel, "CENTER", 0, 0)
    frame.homeFavorLabel = Widgets:CreateLabel(frame.homePanel, "GameFontDisableSmall", "LEFT")
    frame.homeFavorLabel:SetPoint("TOPLEFT", frame.homeLevelLabel, "BOTTOMLEFT", 0, -13)
    frame.homeFavorLabel:SetText(L.HOUSING_HOME_FAVOR)
    frame.homeFavorValue = Widgets:CreateLabel(frame.homePanel, "GameFontHighlightSmall", "RIGHT")
    frame.homeFavorValue:SetPoint("RIGHT", -14, 0)
    frame.homeFavorValue:SetPoint("CENTER", frame.homeFavorLabel, "CENTER", 0, 0)
    frame.homeFavorBar = Widgets:CreateProgressBar(frame.homePanel)
    frame.homeFavorBar:SetPoint("TOPLEFT", frame.homeFavorLabel, "BOTTOMLEFT", 0, -6)
    frame.homeFavorBar:SetPoint("TOPRIGHT", -14, 0)
    frame.homeFavorBar:SetHeight(10)
    frame.homeCouponLabel = Widgets:CreateLabel(frame.homePanel, "GameFontDisableSmall", "LEFT")
    frame.homeCouponLabel:SetPoint("TOPLEFT", frame.homeFavorBar, "BOTTOMLEFT", 0, -11)
    frame.homeCouponValue = Widgets:CreateLabel(frame.homePanel, "GameFontHighlightSmall", "RIGHT")
    frame.homeCouponValue:SetPoint("RIGHT", -14, 0)
    frame.homeCouponValue:SetPoint("CENTER", frame.homeCouponLabel, "CENTER", 0, 0)
    frame.weeklyHeader = createSectionHeader(frame.sidebarPanel, L.HOUSING_SECTION_WEEKLY)
    frame.weeklyHeader:SetPoint("TOPLEFT", frame.homePanel, "BOTTOMLEFT", 0, -14)
    frame.weeklyHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.weeklyPanel = Widgets:CreatePanel(frame.sidebarPanel, "cardInset")
    frame.weeklyPanel:SetPoint("TOPLEFT", frame.weeklyHeader, "BOTTOMLEFT", 0, -7)
    frame.weeklyPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.weeklyPanel:SetHeight(54)
    frame.weeklyRow = StatusRows:Create(frame.weeklyPanel, 1)
    frame.weeklyRow:ClearAllPoints()
    frame.weeklyRow:SetPoint("TOPLEFT", 10, -6)
    frame.weeklyRow:SetPoint("TOPRIGHT", -10, -6)
    frame.trackedHeader = createSectionHeader(frame.sidebarPanel, L.HOUSING_SECTION_TRACKED)
    frame.trackedHeader:SetPoint("TOPLEFT", frame.weeklyPanel, "BOTTOMLEFT", 0, -14)
    frame.trackedHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.trackedPanel = Widgets:CreatePanel(frame.sidebarPanel, "cardInset")
    frame.trackedPanel:SetPoint("TOPLEFT", frame.trackedHeader, "BOTTOMLEFT", 0, -7)
    frame.trackedPanel:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.trackedSubtitle = Widgets:CreateLabel(frame.trackedPanel, "GameFontHighlightSmall", "LEFT")
    frame.trackedSubtitle:SetPoint("TOPLEFT", 12, -12)
    frame.trackedSubtitle:SetPoint("TOPRIGHT", -12, -12)
    frame.trackedSubtitle:SetWordWrap(true)
    frame.trackedSubtitle:SetText(L.HOUSING_SECTION_TRACKED_SUBTITLE)
    frame.trackedScroll, frame.trackedScrollChild = createScroll(frame.trackedPanel, frame.trackedSubtitle, 214)
    frame.trackedEmpty = Widgets:CreateLabel(frame.trackedScrollChild, "GameFontDisableSmall", "LEFT")
    frame.trackedEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.trackedEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.trackedEmpty:SetWordWrap(true)
    frame.trackedEmpty:SetText(L.HOUSING_TRACKED_EMPTY)
    frame.trackedRows = {}
    frame.sidebarEmpty = Widgets:CreateLabel(frame.sidebarPanel, "GameFontDisable", "LEFT")
    frame.sidebarEmpty:SetPoint("TOPLEFT", frame.sidebarPanel.subtitle, "BOTTOMLEFT", 0, -14)
    frame.sidebarEmpty:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.sidebarEmpty:SetJustifyV("TOP")
    frame.sidebarEmpty:SetWordWrap(true)
    frame.sidebarEmpty:Hide()

    frame.utilityPanel = Widgets:CreatePanel(shellFrame.utility, "utility")
    frame.utilityPanel:SetAllPoints(shellFrame.utility)
    frame.utilityPanel:SetFrameLevel(shellFrame.utility:GetFrameLevel() + 10)
    createHeader(frame.utilityPanel, L.HOUSING_UTILITY_TITLE, L.HOUSING_UTILITY_SUBTITLE)
    frame.milestonesHeader = createSectionHeader(frame.utilityPanel, L.HOUSING_SECTION_MILESTONES)
    frame.milestonesHeader:SetPoint("TOPLEFT", frame.utilityPanel.subtitle, "BOTTOMLEFT", 0, -14)
    frame.milestonesHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.milestonesPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.milestonesPanel:SetPoint("TOPLEFT", frame.milestonesHeader, "BOTTOMLEFT", 0, -8)
    frame.milestonesPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.milestonesPanel:SetHeight(168)
    frame.milestonesSubtitle = Widgets:CreateLabel(frame.milestonesPanel, "GameFontHighlightSmall", "LEFT")
    frame.milestonesSubtitle:SetPoint("TOPLEFT", 12, -12)
    frame.milestonesSubtitle:SetPoint("TOPRIGHT", -12, -12)
    frame.milestonesSubtitle:SetWordWrap(true)
    frame.milestonesSubtitle:SetText(L.HOUSING_SECTION_MILESTONES_SUBTITLE)
    frame.milestonesScroll, frame.milestonesScrollChild = createScroll(frame.milestonesPanel, frame.milestonesSubtitle, 250)
    frame.milestonesEmpty = Widgets:CreateLabel(frame.milestonesScrollChild, "GameFontDisableSmall", "LEFT")
    frame.milestonesEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.milestonesEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.milestonesEmpty:SetWordWrap(true)
    frame.milestonesEmpty:SetText(L.HOUSING_MILESTONES_EMPTY)
    frame.milestoneRows = {}
    frame.activityHeader = createSectionHeader(frame.utilityPanel, L.HOUSING_SECTION_ACTIVITY)
    frame.activityHeader:SetPoint("TOPLEFT", frame.milestonesPanel, "BOTTOMLEFT", 0, -14)
    frame.activityHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.activityPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.activityPanel:SetPoint("TOPLEFT", frame.activityHeader, "BOTTOMLEFT", 0, -8)
    frame.activityPanel:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.activitySubtitle = Widgets:CreateLabel(frame.activityPanel, "GameFontHighlightSmall", "LEFT")
    frame.activitySubtitle:SetPoint("TOPLEFT", 12, -12)
    frame.activitySubtitle:SetPoint("TOPRIGHT", -12, -12)
    frame.activitySubtitle:SetWordWrap(true)
    frame.activitySubtitle:SetText(L.HOUSING_SECTION_ACTIVITY_SUBTITLE)
    frame.activityScroll, frame.activityScrollChild = createScroll(frame.activityPanel, frame.activitySubtitle, 250)
    frame.activityEmpty = Widgets:CreateLabel(frame.activityScrollChild, "GameFontDisableSmall", "LEFT")
    frame.activityEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.activityEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.activityEmpty:SetWordWrap(true)
    frame.activityEmpty:SetText(L.HOUSING_ACTIVITY_EMPTY)
    frame.activityRows = {}
    frame.utilityEmpty = Widgets:CreateLabel(frame.utilityPanel, "GameFontDisable", "LEFT")
    frame.utilityEmpty:SetPoint("TOPLEFT", frame.utilityPanel.subtitle, "BOTTOMLEFT", 0, -14)
    frame.utilityEmpty:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.utilityEmpty:SetJustifyV("TOP")
    frame.utilityEmpty:SetWordWrap(true)
    frame.utilityEmpty:Hide()

    local standardSidebar = {
        shellFrame.sidebarTitle, shellFrame.sidebarSubtitle, shellFrame.sidebarCurrent,
        shellFrame.sidebarSettingsButton, shellFrame.sidebarSortButton,
        shellFrame.sidebarVisibilityButton, shellFrame.sidebarScroll,
    }
    local standardUtility = { shellFrame.utilityStandard }

    function frame:SetChromeVisible(visible)
        visible = visible == true
        self.chromeVisible = visible
        for _, region in ipairs(standardSidebar) do region:SetShown(not visible) end
        for _, region in ipairs(standardUtility) do region:SetShown(not visible) end
        shellFrame.sidebarSortMenu:Hide()
        shellFrame.sidebarVisibilityMenu:Hide()
        shellFrame.sidebarSettingsMenu:Hide()
        self.sidebarPanel:SetShown(visible)
        self.utilityPanel:SetShown(visible)
        if visible then service:Open() else service:Close() end
    end

    local function ensureStatusRows(pool, parent, count, clickable)
        while #pool < count do
            local previous = pool[#pool]
            local row = StatusRows:Create(parent, #pool + 1, previous)
            row:ClearAllPoints()
            if previous then
                row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
                row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
            else
                row:SetPoint("TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", 0, 0)
            end
            if clickable then
                row.hitbox:SetScript("OnClick", function()
                    if row.taskID ~= nil then service:ToggleTask(row.taskID, row.taskTracked) end
                end)
            end
            pool[#pool + 1] = row
        end
    end

    local function ensureTaskRows(count)
        while #frame.taskRows < count do
            frame.taskRows[#frame.taskRows + 1] = createTaskRow(
                frame.tasksScrollChild,
                frame.taskRows[#frame.taskRows],
                service
            )
        end
    end

    local function showAvailable(available, message)
        frame.sidebarEmpty:SetShown(not available)
        frame.sidebarEmpty:SetText(message or "")
        frame.homeHeader:SetShown(available)
        frame.homePanel:SetShown(available)
        frame.weeklyHeader:SetShown(available)
        frame.weeklyPanel:SetShown(available)
        frame.trackedHeader:SetShown(available)
        frame.trackedPanel:SetShown(available)
        frame.contentEmpty:SetShown(not available)
        frame.contentEmpty:SetText(message or "")
        frame.summaryPanel:SetShown(available)
        frame.tasksPanel:SetShown(available)
        frame.utilityEmpty:SetShown(not available)
        frame.utilityEmpty:SetText(message or "")
        frame.milestonesHeader:SetShown(available)
        frame.milestonesPanel:SetShown(available)
        frame.activityHeader:SetShown(available)
        frame.activityPanel:SetShown(available)
    end

    function frame:Refresh()
        if self.chromeVisible ~= false then service:Open() end
        syncScrollWidth(self.tasksScroll, self.tasksScrollChild)
        syncScrollWidth(self.trackedScroll, self.trackedScrollChild)
        syncScrollWidth(self.milestonesScroll, self.milestonesScrollChild)
        syncScrollWidth(self.activityScroll, self.activityScrollChild)

        local character = Addon.WarbandRoster:GetSelected()
        local view = character and service:GetView(character.key) or Addon.HousingLogic:BuildView(nil)
        local state = Addon.StateStore:Get("housing.endeavors")
        local message = view.message
        if character and Addon.WarbandRoster:IsCurrent(character.key) and view.available ~= true then
            if state and state.loading then message = L.HOUSING_LOADING
            elseif state and state.unavailable then message = L.HOUSING_UNAVAILABLE end
        end
        local available = view.available == true
        showAvailable(available, message)
        if not available then return end

        local house = view.house or {}
        self.homeName:SetText(house.title or L.HOUSING_HOME_NONE)
        self.homeSubtitle:SetText(house.subtitle or "")
        self.homeSubtitle:SetShown(type(house.subtitle) == "string" and house.subtitle ~= "")
        self.homeMeta:SetText(house.meta or "")
        self.homeLevelValue:SetText(house.levelValue or "--")
        self.homeFavorValue:SetText(house.favorValue or "--")
        self.homeCouponLabel:SetText(house.couponLabel or L.HOUSING_HOME_COUPONS)
        self.homeCouponValue:SetText(house.couponValue or "--")
        Widgets:SetProgress(self.homeFavorBar, house.favorRatio or 0, 1)

        StatusRows:Set(self.weeklyRow, view.weekly or {
            label = L.PVE_WEEKLY_HOUSING_LABEL,
            text = L.STATUS_MISSING,
            status = "missing",
            tooltipTitle = L.PVE_WEEKLY_HOUSING_LABEL,
            tooltipLines = { L.PVE_WEEKLY_HOUSING_ACCEPT_HINT },
        })

        local tracked = type(view.trackedTasks) == "table" and view.trackedTasks or {}
        ensureStatusRows(self.trackedRows, self.trackedScrollChild, #tracked, true)
        for index, row in ipairs(self.trackedRows) do
            local entry = tracked[index]
            StatusRows:Set(row, entry)
            row.taskID = entry and entry.id or nil
            row.taskTracked = entry and entry.tracked == true or false
            if entry and service:CanToggleTasks() then
                row.tooltipLines = {}
                for _, line in ipairs(entry.tooltipLines or {}) do row.tooltipLines[#row.tooltipLines + 1] = line end
                row.tooltipLines[#row.tooltipLines + 1] = L.HOUSING_TASK_UNTRACK_HINT
            end
        end
        self.trackedScrollChild:SetHeight(math.max(10, (#tracked * 50) - 8))
        self.trackedEmpty:SetShown(#tracked == 0)

        self.summaryTitle:SetText(view.title or L.HOUSING_TITLE)
        self.summarySubtitle:SetText(view.subtitle or "")
        self.summarySubtitle:SetShown(type(view.subtitle) == "string" and view.subtitle ~= "")
        for index, card in ipairs(self.statCards) do applyStatCard(card, view.statCards and view.statCards[index]) end
        local progress = view.progress or {}
        self.progressLabel:SetText(progress.label or L.HOUSING_PROGRESS_LABEL)
        self.progressValue:SetText(progress.value or "--")
        self.progressNote:SetText(progress.note or "")
        Widgets:SetProgress(self.progressBar, progress.ratio or 0, 1)
        Widgets:SetProgressBreakpoints(self.progressBar, progress.thresholds, progress.maxThreshold)

        local tasks = type(view.tasks) == "table" and view.tasks or {}
        ensureTaskRows(#tasks)
        for index, row in ipairs(self.taskRows) do setTaskRow(row, tasks[index]) end
        self.tasksScrollChild:SetHeight(math.max(10, (#tasks * 58) - 10))
        self.tasksEmpty:SetText(view.loadingTasks and L.HOUSING_LOADING or L.HOUSING_TASKS_EMPTY)
        self.tasksEmpty:SetShown(#tasks == 0)

        local milestones = type(view.milestones) == "table" and view.milestones or {}
        ensureStatusRows(self.milestoneRows, self.milestonesScrollChild, #milestones, false)
        for index, row in ipairs(self.milestoneRows) do StatusRows:Set(row, milestones[index]) end
        self.milestonesScrollChild:SetHeight(math.max(10, (#milestones * 50) - 8))
        self.milestonesEmpty:SetShown(#milestones == 0)

        local activity = type(view.activity) == "table" and view.activity or {}
        ensureStatusRows(self.activityRows, self.activityScrollChild, #activity, false)
        for index, row in ipairs(self.activityRows) do StatusRows:Set(row, activity[index]) end
        self.activityScrollChild:SetHeight(math.max(10, (#activity * 50) - 8))
        self.activityEmpty:SetShown(#activity == 0)
    end

    frame.navigation:SetScript("OnClick", function()
        Addon.Database:GetUI().selectedSubTabs.housing = "endeavors"
    end)
    frame:SetScript("OnHide", function() frame:SetChromeVisible(false) end)
    frame:SetScript("OnShow", function()
        if not frame.chromeVisible then frame:SetChromeVisible(true) end
        frame:Refresh()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if frame:IsShown() then
                    syncScrollWidth(frame.tasksScroll, frame.tasksScrollChild)
                    syncScrollWidth(frame.trackedScroll, frame.trackedScrollChild)
                    syncScrollWidth(frame.milestonesScroll, frame.milestonesScrollChild)
                    syncScrollWidth(frame.activityScroll, frame.activityScrollChild)
                end
            end)
        end
    end)
    Addon.StateStore:Subscribe("housing.endeavors", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    return frame
end

Addon.ScreenRegistry:Register({
    id = "housing",
    order = 8,
    label = function() return L.SCREEN_HOUSING end,
    Create = createScreen,
})
