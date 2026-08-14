local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local ScrollFrames = Addon.ScrollFrames
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

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

local function createHeader(parent, title)
    parent.title = Widgets:CreateLabel(parent, "GameFontNormalLarge", "LEFT")
    parent.title:SetPoint("TOPLEFT", 16, -16)
    parent.title:SetPoint("TOPRIGHT", -16, -16)
    parent.title:SetText(title)
end

local function createSectionHeader(parent, text)
    local label = Widgets:CreateLabel(parent, "GameFontNormal", "LEFT")
    label:SetText(text)
    label:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
    return label
end

local function setTooltip(button, title, body)
    button.tooltipTitle = title
    button.tooltipBody = body
    local previousEnter = button:GetScript("OnEnter")
    local previousLeave = button:GetScript("OnLeave")
    button:SetScript("OnEnter", function(self)
        if previousEnter then previousEnter(self) end
        if not GameTooltip or not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(self.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
        if self.tooltipBody then GameTooltip:AddLine(self.tooltipBody, 0.92, 0.92, 0.92, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if previousLeave then previousLeave(self) end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function setProgressColor(bar, complete)
    if complete then bar:SetStatusBarColor(0.28, 0.76, 0.42, 0.96)
    else bar:SetStatusBarColor(0.74, 0.63, 0.28, 0.95) end
end

local function createNeighborhoodCard(parent, compact)
    local card = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    Widgets:ApplyPanelStyle(card, compact and "cardInset" or "card")
    card:SetHeight(compact and 72 or 148)
    card.name = Widgets:CreateLabel(card, compact and "GameFontNormal" or "GameFontNormalLarge", "LEFT")
    card.name:SetPoint("TOPLEFT", compact and 10 or 14, compact and -9 or -13)
    card.name:SetPoint("TOPRIGHT", compact and -66 or -100, compact and -9 or -13)
    card.status = Widgets:CreateLabel(card, "GameFontNormalSmall", "RIGHT")
    card.status:SetPoint("TOPRIGHT", compact and -9 or -13, compact and -10 or -15)
    card.status:SetWidth(compact and 58 or 90)
    card.endeavor = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.endeavor:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, compact and -4 or -8)
    card.endeavor:SetPoint("TOPRIGHT", compact and -10 or -14, 0)
    card.endeavor:SetMaxLines(1)
    card.progress = Widgets:CreateProgressBar(card)
    card.progress:SetPoint("TOPLEFT", card.endeavor, "BOTTOMLEFT", 0, compact and -6 or -10)
    card.progress:SetPoint("TOPRIGHT", compact and -10 or -14, 0)
    card.progress:SetHeight(compact and 8 or 12)
    card.progressValue = Widgets:CreateLabel(card, "GameFontDisableSmall", "RIGHT")
    card.progressValue:SetPoint("TOPRIGHT", card.progress, "BOTTOMRIGHT", 0, compact and -3 or -6)
    card.level = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.level:SetPoint("TOPLEFT", card.progress, "BOTTOMLEFT", 0, compact and -3 or -6)
    if not compact then
        card.house = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
        card.house:SetPoint("TOPLEFT", card.level, "BOTTOMLEFT", 0, -7)
        card.house:SetPoint("TOPRIGHT", -14, 0)
    end
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.95)
    end)
    card:SetScript("OnLeave", function(self)
        local color = self.selected and Theme.colors.gold or Theme.colors.goldDim
        self:SetBackdropBorderColor(color[1], color[2], color[3], self.selected and 0.95 or 0.65)
    end)
    card:Hide()
    return card
end

local function applyNeighborhoodCard(card, entry, selected)
    if type(entry) ~= "table" then card:Hide(); return end
    card.entry = entry
    card.neighborhoodGUID = entry.neighborhoodGUID
    card.selected = selected == true
    card.name:SetText(entry.title or L.HOUSING_HOME_NONE)
    card.endeavor:SetText(entry.endeavorTitle or L.HOUSING_LOADING_SHORT)
    card.progressValue:SetText(entry.progressValue or "--")
    card.level:SetText(string.format(L.HOUSING_CARD_LEVEL, entry.levelValue or "--"))
    if card.house then card.house:SetText(entry.houseName or "") end
    local statusText = entry.active and L.HOUSING_STATUS_ACTIVE
        or entry.complete and L.HOUSING_STATUS_COMPLETE
        or L.HOUSING_STATUS_VIEW
    card.status:SetText(statusText)
    local statusColor = entry.active and Theme.colors.gold
        or entry.complete and STATUS_COLORS.complete or Theme.colors.muted
    card.status:SetTextColor(statusColor[1], statusColor[2], statusColor[3], 1)
    Widgets:SetProgress(card.progress, entry.progressRatio or 0, 1)
    setProgressColor(card.progress, entry.complete == true)
    local border = selected and Theme.colors.gold or entry.active and Theme.colors.goldDim or Theme.colors.goldDim
    card:SetBackdropBorderColor(border[1], border[2], border[3], selected and 0.95 or 0.65)
    card:Show()
end

local function createTaskRow(parent, previous, service)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(48)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Addon.Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
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
    row.background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.background:SetTexture(Addon.Assets.row)
    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -6)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 6)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)
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
            if self.allowToggle and service:CanToggleTasks() then
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
        if self.allowToggle and self.taskID ~= nil then service:ToggleTask(self.taskID, self.tracked) end
    end)
    row:Hide()
    return row
end

local function setTaskRow(row, entry, allowToggle)
    if type(entry) ~= "table" then
        row.taskID, row.tooltipTitle, row.tooltipLines = nil, nil, nil
        row:Hide()
        return
    end
    local color = STATUS_COLORS[entry.status] or Theme.colors.muted
    local text = entry.title or L.UNKNOWN
    if entry.meta and entry.meta ~= "" then text = text .. "\n|cff9b978f" .. entry.meta .. "|r" end
    row.label:SetText(text)
    row.value:SetText(entry.statusText or "")
    row.value:SetTextColor(color[1], color[2], color[3], 1)
    row.statusLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.taskID = entry.id
    row.tracked = entry.tracked == true
    row.allowToggle = allowToggle == true
    row.tooltipTitle = entry.tooltipTitle
    row.tooltipLines = entry.tooltipLines
    row:Show()
end

local function createSummaryPanel(parent)
    local panel = Widgets:CreatePanel(parent, "card")
    panel:SetHeight(142)
    panel.title = Widgets:CreateLabel(panel, "GameFontNormalLarge", "LEFT")
    panel.title:SetPoint("TOPLEFT", 14, -13)
    panel.title:SetPoint("TOPRIGHT", -110, -13)
    panel.status = Widgets:CreateLabel(panel, "GameFontNormalSmall", "RIGHT")
    panel.status:SetPoint("TOPRIGHT", -14, -15)
    panel.status:SetWidth(92)
    panel.meta = Widgets:CreateLabel(panel, "GameFontDisableSmall", "LEFT")
    panel.meta:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.meta:SetPoint("TOPRIGHT", -14, 0)
    panel.progressLabel = Widgets:CreateLabel(panel, "GameFontHighlightSmall", "LEFT")
    panel.progressLabel:SetPoint("TOPLEFT", panel.meta, "BOTTOMLEFT", 0, -12)
    panel.progressValue = Widgets:CreateLabel(panel, "GameFontHighlightSmall", "RIGHT")
    panel.progressValue:SetPoint("RIGHT", -14, 0)
    panel.progressValue:SetPoint("CENTER", panel.progressLabel, "CENTER", 0, 0)
    panel.progress = Widgets:CreateProgressBar(panel)
    panel.progress:SetPoint("TOPLEFT", panel.progressLabel, "BOTTOMLEFT", 0, -7)
    panel.progress:SetPoint("TOPRIGHT", -14, 0)
    panel.progress:SetHeight(12)
    panel.note = Widgets:CreateLabel(panel, "GameFontDisableSmall", "LEFT")
    panel.note:SetPoint("TOPLEFT", panel.progress, "BOTTOMLEFT", 0, -9)
    panel.note:SetPoint("TOPRIGHT", -14, 0)
    return panel
end

local function applySummaryPanel(panel, view)
    local progress = type(view.progress) == "table" and view.progress or {}
    local house = type(view.house) == "table" and view.house or {}
    panel.title:SetText(view.title or L.HOUSING_TITLE)
    panel.meta:SetText(house.neighborhoodName or house.subtitle or house.title or "")
    panel.progressLabel:SetText(progress.label or L.HOUSING_PROGRESS_LABEL)
    panel.progressValue:SetText(progress.value or "--")
    panel.note:SetText(progress.note or "")
    panel.status:SetText(view.isActive and L.HOUSING_STATUS_ACTIVE
        or view.isComplete and L.HOUSING_STATUS_COMPLETE or L.HOUSING_STATUS_VIEW)
    local color = view.isActive and Theme.colors.gold
        or view.isComplete and STATUS_COLORS.complete or Theme.colors.muted
    panel.status:SetTextColor(color[1], color[2], color[3], 1)
    Widgets:SetProgress(panel.progress, progress.ratio or 0, 1)
    Widgets:SetProgressBreakpoints(panel.progress, progress.thresholds, progress.maxThreshold)
    setProgressColor(panel.progress, view.isComplete == true)
end

local function createStatStrip(parent)
    local panel = Widgets:CreatePanel(parent, "cardInset")
    panel:SetHeight(66)
    panel.cells = {}
    local previous
    for index = 1, 4 do
        local cell = CreateFrame("Frame", nil, panel)
        cell:SetHeight(48)
        if previous then cell:SetPoint("TOPLEFT", previous, "TOPRIGHT", 8, 0)
        else cell:SetPoint("TOPLEFT", 14, -9) end
        cell:SetWidth(176)
        cell.label = Widgets:CreateLabel(cell, "GameFontDisableSmall", "LEFT")
        cell.label:SetPoint("TOPLEFT", 0, 0)
        cell.label:SetPoint("TOPRIGHT", 0, 0)
        cell.value = Widgets:CreateLabel(cell, "GameFontNormal", "LEFT")
        cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
        cell.value:SetPoint("TOPRIGHT", 0, 0)
        cell.meta = Widgets:CreateLabel(cell, "GameFontDisableSmall", "LEFT")
        cell.meta:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -1)
        cell.meta:SetPoint("TOPRIGHT", 0, 0)
        panel.cells[index] = cell
        previous = cell
    end
    return panel
end

local function applyStatStrip(panel, entries)
    entries = type(entries) == "table" and entries or {}
    for index, cell in ipairs(panel.cells) do
        local entry = entries[index]
        cell.label:SetText(entry and entry.label or "")
        cell.value:SetText(entry and entry.value or "--")
        cell.meta:SetText(entry and entry.meta or "")
    end
end

local function createRewardSummary(parent)
    local panel = Widgets:CreatePanel(parent, "card")
    panel:SetHeight(66)
    panel.title = Widgets:CreateLabel(panel, "GameFontNormalLarge", "LEFT")
    panel.title:SetPoint("TOPLEFT", 14, -12)
    panel.title:SetPoint("TOPRIGHT", -130, -12)
    panel.status = Widgets:CreateLabel(panel, "GameFontNormalSmall", "RIGHT")
    panel.status:SetPoint("TOPRIGHT", -14, -14)
    panel.status:SetWidth(116)
    panel.text = Widgets:CreateLabel(panel, "GameFontDisableSmall", "LEFT")
    panel.text:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.text:SetPoint("TOPRIGHT", -14, 0)
    return panel
end

local function applyRewardSummary(panel, summary)
    summary = type(summary) == "table" and summary or {}
    panel.title:SetText(summary.title or L.HOUSING_REWARD_SUMMARY_TITLE)
    panel.status:SetText(summary.status or "")
    panel.text:SetText(summary.text or "")
    local color = summary.complete and STATUS_COLORS.complete or STATUS_COLORS.turnin
    panel.status:SetTextColor(color[1], color[2], color[3], 1)
end

local function modeLabel(mode)
    if mode == "automatic" then return L.HOUSING_SWITCH_MODE_AUTOMATIC end
    if mode == "off" then return L.HOUSING_SWITCH_MODE_OFF end
    return L.HOUSING_SWITCH_MODE_ASK
end

local function modeDescription(mode)
    if mode == "automatic" then return L.HOUSING_SWITCH_MODE_AUTOMATIC_DESC end
    if mode == "off" then return L.HOUSING_SWITCH_MODE_OFF_DESC end
    return L.HOUSING_SWITCH_MODE_ASK_DESC
end

local function createScreen(_, host)
    local shellFrame = Addon.UI.frame
    local service = Addon.Housing
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame:Hide()
    frame.layoutVersion = "housing-neighborhoods-4"
    frame.selectedNeighborhoodGUID = nil

    frame.subTabButtons = {}
    local previousTab
    for _, definition in ipairs(Addon.Data.HOUSING.subTabs or {}) do
        local button = Widgets:CreateButton(frame, L[definition.labelKey], 230, 24, "tab")
        if previousTab then button:SetPoint("LEFT", previousTab, "RIGHT", 8, 0)
        else button:SetPoint("TOPLEFT", 0, 0) end
        frame.subTabButtons[definition.key] = button
        previousTab = button
    end
    frame.navigation = frame.subTabButtons.endeavors

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation, "BOTTOMLEFT", 0, -10)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.pages = {}
    for _, key in ipairs({ "endeavors", "activity" }) do
        local page = CreateFrame("Frame", nil, frame.contentHost)
        page:SetAllPoints(frame.contentHost)
        page:Hide()
        frame.pages[key] = page
    end

    local endeavors = frame.pages.endeavors
    endeavors.summary = createSummaryPanel(endeavors)
    endeavors.summary:SetPoint("TOPLEFT", 0, 0)
    endeavors.summary:SetPoint("TOPRIGHT", 0, 0)
    endeavors.stats = createStatStrip(endeavors)
    endeavors.stats:SetPoint("TOPLEFT", endeavors.summary, "BOTTOMLEFT", 0, -10)
    endeavors.stats:SetPoint("TOPRIGHT", endeavors.summary, "BOTTOMRIGHT", 0, -10)
    endeavors.tasksPanel = Widgets:CreatePanel(endeavors, "cardInset")
    endeavors.tasksPanel:SetPoint("TOPLEFT", endeavors.stats, "BOTTOMLEFT", 0, -12)
    endeavors.tasksPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    endeavors.tasksTitle = Widgets:CreateLabel(endeavors.tasksPanel, "GameFontNormalLarge", "LEFT")
    endeavors.tasksTitle:SetPoint("TOPLEFT", 14, -14)
    endeavors.tasksTitle:SetPoint("TOPRIGHT", -250, -14)
    endeavors.tasksTitle:SetText(L.HOUSING_SECTION_TASKS)
    endeavors.tasksCap = Widgets:CreateLabel(endeavors.tasksPanel, "GameFontDisableSmall", "RIGHT")
    endeavors.tasksCap:SetPoint("TOPRIGHT", -14, -17)
    endeavors.tasksCap:SetWidth(226)
    endeavors.tasksCap:SetText(string.format(L.HOUSING_TASK_HOUSE_XP_CAP_SHORT, Addon.Data.HOUSING.houseXPPerEndeavor))
    endeavors.tasksScroll, endeavors.tasksScrollChild = createScroll(endeavors.tasksPanel, endeavors.tasksTitle, 690)
    endeavors.tasksEmpty = Widgets:CreateLabel(endeavors.tasksScrollChild, "GameFontDisable", "LEFT")
    endeavors.tasksEmpty:SetPoint("TOPLEFT", 4, -4)
    endeavors.tasksEmpty:SetPoint("TOPRIGHT", -4, -4)
    endeavors.tasksEmpty:SetWordWrap(true)
    endeavors.taskRows = {}
    frame.tasksScroll = endeavors.tasksScroll
    frame.tasksScrollChild = endeavors.tasksScrollChild
    frame.taskRows = endeavors.taskRows
    frame.summaryTitle = endeavors.summary.title
    frame.statCells = endeavors.stats.cells

    local activity = frame.pages.activity
    activity.rewardSummary = createRewardSummary(activity)
    activity.rewardSummary:SetPoint("TOPLEFT", 0, 0)
    activity.rewardSummary:SetPoint("TOPRIGHT", 0, 0)
    activity.milestonesPanel = Widgets:CreatePanel(activity, "cardInset")
    activity.milestonesPanel:SetPoint("TOPLEFT", activity.rewardSummary, "BOTTOMLEFT", 0, -12)
    activity.milestonesPanel:SetPoint("BOTTOMLEFT", 0, 0)
    activity.milestonesPanel:SetWidth(374)
    activity.milestonesTitle = Widgets:CreateLabel(activity.milestonesPanel, "GameFontNormalLarge", "LEFT")
    activity.milestonesTitle:SetPoint("TOPLEFT", 14, -14)
    activity.milestonesTitle:SetText(L.HOUSING_SECTION_MILESTONES)
    activity.milestonesScroll, activity.milestonesScrollChild = createScroll(activity.milestonesPanel, activity.milestonesTitle, 338)
    activity.milestonesEmpty = Widgets:CreateLabel(activity.milestonesScrollChild, "GameFontDisable", "LEFT")
    activity.milestonesEmpty:SetPoint("TOPLEFT", 4, -4)
    activity.milestonesEmpty:SetPoint("TOPRIGHT", -4, -4)
    activity.milestonesEmpty:SetText(L.HOUSING_MILESTONES_EMPTY)
    activity.milestoneRows = {}
    activity.logPanel = Widgets:CreatePanel(activity, "cardInset")
    activity.logPanel:SetPoint("TOPLEFT", activity.milestonesPanel, "TOPRIGHT", 14, 0)
    activity.logPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    activity.logTitle = Widgets:CreateLabel(activity.logPanel, "GameFontNormalLarge", "LEFT")
    activity.logTitle:SetPoint("TOPLEFT", 14, -14)
    activity.logTitle:SetText(L.HOUSING_SECTION_ACTIVITY)
    activity.logScroll, activity.logScrollChild = createScroll(activity.logPanel, activity.logTitle, 338)
    activity.logEmpty = Widgets:CreateLabel(activity.logScrollChild, "GameFontDisable", "LEFT")
    activity.logEmpty:SetPoint("TOPLEFT", 4, -4)
    activity.logEmpty:SetPoint("TOPRIGHT", -4, -4)
    activity.logEmpty:SetText(L.HOUSING_ACTIVITY_EMPTY)
    activity.activityRows = {}
    frame.milestonesScroll = activity.milestonesScroll
    frame.milestonesScrollChild = activity.milestonesScrollChild
    frame.activityScroll = activity.logScroll
    frame.activityScrollChild = activity.logScrollChild
    frame.rewardSummary = activity.rewardSummary

    frame.sidebarPanel = Widgets:CreatePanel(shellFrame.sidebar, "sidebar")
    frame.sidebarPanel:SetAllPoints(shellFrame.sidebar)
    frame.sidebarPanel:SetFrameLevel(shellFrame.sidebar:GetFrameLevel() + 10)
    createHeader(frame.sidebarPanel, L.HOUSING_TITLE)
    frame.neighborhoodsHeader = createSectionHeader(frame.sidebarPanel, L.HOUSING_SECTION_NEIGHBORHOODS)
    frame.neighborhoodsHeader:SetPoint("TOPLEFT", frame.sidebarPanel.title, "BOTTOMLEFT", 0, -14)
    frame.neighborhoodsHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.neighborhoodsPanel = Widgets:CreatePanel(frame.sidebarPanel, "cardInset")
    frame.neighborhoodsPanel:SetPoint("TOPLEFT", frame.neighborhoodsHeader, "BOTTOMLEFT", 0, -8)
    frame.neighborhoodsPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.neighborhoodsPanel:SetHeight(166)
    frame.sidebarNeighborhoodCards = {}
    frame.weeklyHeader = createSectionHeader(frame.sidebarPanel, L.HOUSING_SECTION_WEEKLY)
    frame.weeklyHeader:SetPoint("TOPLEFT", frame.neighborhoodsPanel, "BOTTOMLEFT", 0, -14)
    frame.weeklyHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.weeklyPanel = Widgets:CreatePanel(frame.sidebarPanel, "cardInset")
    frame.weeklyPanel:SetPoint("TOPLEFT", frame.weeklyHeader, "BOTTOMLEFT", 0, -7)
    frame.weeklyPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.weeklyPanel:SetHeight(54)
    frame.weeklyRow = StatusRows:Create(frame.weeklyPanel, 1)
    frame.weeklyRow:ClearAllPoints()
    frame.weeklyRow:SetPoint("TOPLEFT", 10, -6)
    frame.weeklyRow:SetPoint("TOPRIGHT", -10, -6)
    frame.sidebarHint = Widgets:CreateLabel(frame.sidebarPanel, "GameFontDisableSmall", "LEFT")
    frame.sidebarHint:SetPoint("TOPLEFT", frame.weeklyPanel, "BOTTOMLEFT", 2, -16)
    frame.sidebarHint:SetPoint("BOTTOMRIGHT", -18, 18)
    frame.sidebarHint:SetJustifyV("TOP")
    frame.sidebarHint:SetWordWrap(true)
    frame.sidebarHint:SetText(L.HOUSING_NEIGHBORHOOD_HINT)

    frame.utilityPanel = Widgets:CreatePanel(shellFrame.utility, "utility")
    frame.utilityPanel:SetAllPoints(shellFrame.utility)
    frame.utilityPanel:SetFrameLevel(shellFrame.utility:GetFrameLevel() + 10)
    createHeader(frame.utilityPanel, L.HOUSING_CONTROL_TITLE)
    frame.controlPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.controlPanel:SetPoint("TOPLEFT", frame.utilityPanel.title, "BOTTOMLEFT", 0, -12)
    frame.controlPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.controlPanel:SetHeight(106)
    frame.activeLabel = Widgets:CreateLabel(frame.controlPanel, "GameFontDisableSmall", "LEFT")
    frame.activeLabel:SetPoint("TOPLEFT", 12, -12)
    frame.activeLabel:SetText(L.HOUSING_ACTIVE_DESTINATION)
    frame.activeName = Widgets:CreateLabel(frame.controlPanel, "GameFontNormalLarge", "LEFT")
    frame.activeName:SetPoint("TOPLEFT", frame.activeLabel, "BOTTOMLEFT", 0, -5)
    frame.activeName:SetPoint("TOPRIGHT", -12, 0)
    frame.controlMessage = Widgets:CreateLabel(frame.controlPanel, "GameFontHighlightSmall", "LEFT")
    frame.controlMessage:SetPoint("TOPLEFT", frame.activeName, "BOTTOMLEFT", 0, -9)
    frame.controlMessage:SetPoint("TOPRIGHT", -12, 0)
    frame.controlMessage:SetWordWrap(true)
    frame.controlAction = Widgets:CreateButton(frame.controlPanel, L.HOUSING_SET_ACTIVE, 224, 28)
    frame.controlAction:SetPoint("BOTTOMLEFT", 12, 13)
    frame.modePanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.modePanel:SetPoint("TOPLEFT", frame.controlPanel, "BOTTOMLEFT", 0, -12)
    frame.modePanel:SetPoint("TOPRIGHT", -16, 0)
    frame.modePanel:SetHeight(122)
    frame.modeLabel = Widgets:CreateLabel(frame.modePanel, "GameFontNormal", "LEFT")
    frame.modeLabel:SetPoint("TOPLEFT", 12, -11)
    frame.modeLabel:SetPoint("TOPRIGHT", -12, -11)
    frame.modeLabel:SetText(L.HOUSING_SWITCH_MODE)
    frame.modeDescription = Widgets:CreateLabel(frame.modePanel, "GameFontDisableSmall", "LEFT")
    frame.modeDescription:SetPoint("TOPLEFT", frame.modeLabel, "BOTTOMLEFT", 0, -6)
    frame.modeDescription:SetPoint("TOPRIGHT", -12, 0)
    frame.modeDescription:SetWordWrap(true)
    frame.modeButtons = {}
    local previousModeButton
    for _, definition in ipairs({
        { key = "off", width = 64 },
        { key = "ask", width = 84 },
        { key = "automatic", width = 84 },
    }) do
        local button = Widgets:CreateButton(frame.modePanel, modeLabel(definition.key), definition.width, 25, "tab")
        button.label:ClearAllPoints()
        button.label:SetPoint("TOPLEFT", 4, 0)
        button.label:SetPoint("BOTTOMRIGHT", -4, 0)
        if previousModeButton then button:SetPoint("LEFT", previousModeButton, "RIGHT", 5, 0)
        else button:SetPoint("BOTTOMLEFT", 12, 11) end
        button.mode = definition.key
        setTooltip(button, modeLabel(definition.key), modeDescription(definition.key))
        frame.modeButtons[definition.key] = button
        previousModeButton = button
    end
    frame.quickPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.quickPanel:SetPoint("TOPLEFT", frame.modePanel, "BOTTOMLEFT", 0, -12)
    frame.quickPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.quickPanel:SetHeight(48)
    frame.decorationsButton = Widgets:CreateButton(frame.quickPanel, L.HOUSING_OPEN_DECORATIONS, 118, 25)
    frame.decorationsButton:SetPoint("LEFT", 12, 0)
    setTooltip(frame.decorationsButton, L.HOUSING_OPEN_DECORATIONS, L.HOUSING_OPEN_DECORATIONS_DESC)
    frame.dashboardButton = Widgets:CreateButton(frame.quickPanel, L.HOUSING_OPEN_DASHBOARD, 118, 25)
    frame.dashboardButton:SetPoint("LEFT", frame.decorationsButton, "RIGHT", 6, 0)
    setTooltip(frame.dashboardButton, L.HOUSING_OPEN_DASHBOARD, L.HOUSING_OPEN_DASHBOARD_DESC)
    frame.trackedHeader = createSectionHeader(frame.utilityPanel, L.HOUSING_SECTION_TRACKED)
    frame.trackedHeader:SetPoint("TOPLEFT", frame.quickPanel, "BOTTOMLEFT", 0, -14)
    frame.trackedHeader:SetPoint("TOPRIGHT", -16, 0)
    frame.trackedPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.trackedPanel:SetPoint("TOPLEFT", frame.trackedHeader, "BOTTOMLEFT", 0, -8)
    frame.trackedPanel:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.trackedScroll, frame.trackedScrollChild = createScroll(frame.trackedPanel, frame.trackedHeader, 250)
    frame.trackedScroll:ClearAllPoints()
    frame.trackedScroll:SetPoint("TOPLEFT", frame.trackedPanel, "TOPLEFT", 12, -10)
    frame.trackedScroll:SetPoint("BOTTOMRIGHT", -26, 12)
    frame.trackedEmpty = Widgets:CreateLabel(frame.trackedScrollChild, "GameFontDisableSmall", "LEFT")
    frame.trackedEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.trackedEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.trackedEmpty:SetWordWrap(true)
    frame.trackedEmpty:SetText(L.HOUSING_TRACKED_EMPTY)
    frame.trackedRows = {}

    frame.contentEmpty = Widgets:CreateLabel(frame.contentHost, "GameFontDisableLarge", "LEFT")
    frame.contentEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.contentEmpty:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.contentEmpty:SetJustifyV("TOP")
    frame.contentEmpty:SetWordWrap(true)
    frame.contentEmpty:Hide()

    frame.confirm = Widgets:CreatePanel(frame.contentHost, "content")
    frame.confirm:SetSize(430, 174)
    frame.confirm:SetPoint("CENTER")
    frame.confirm:SetFrameLevel(frame.contentHost:GetFrameLevel() + 40)
    frame.confirm.title = Widgets:CreateLabel(frame.confirm, "GameFontNormalLarge", "CENTER")
    frame.confirm.title:SetPoint("TOPLEFT", 18, -20)
    frame.confirm.title:SetPoint("TOPRIGHT", -18, -20)
    frame.confirm.title:SetText(L.HOUSING_SWITCH_PROMPT_TITLE)
    frame.confirm.message = Widgets:CreateLabel(frame.confirm, "GameFontHighlightSmall", "CENTER")
    frame.confirm.message:SetPoint("TOPLEFT", 24, -56)
    frame.confirm.message:SetPoint("TOPRIGHT", -24, -56)
    frame.confirm.message:SetWordWrap(true)
    frame.confirm.cancel = Widgets:CreateButton(frame.confirm, L.HOUSING_IGNORE_CYCLE, 164, 30)
    frame.confirm.cancel:SetPoint("BOTTOMLEFT", 36, 22)
    frame.confirm.accept = Widgets:CreateButton(frame.confirm, L.HOUSING_SWITCH_NOW, 164, 30)
    frame.confirm.accept:SetPoint("BOTTOMRIGHT", -36, 22)
    frame.confirm:Hide()

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
                    if row.allowToggle and row.taskID ~= nil then service:ToggleTask(row.taskID, row.taskTracked) end
                end)
            end
            pool[#pool + 1] = row
        end
    end

    local function ensureTaskRows(count)
        while #endeavors.taskRows < count do
            endeavors.taskRows[#endeavors.taskRows + 1] = createTaskRow(
                endeavors.tasksScrollChild,
                endeavors.taskRows[#endeavors.taskRows],
                service
            )
        end
    end

    local function ensureNeighborhoodCards(pool, parent, count, compact)
        while #pool < count do
            local card = createNeighborhoodCard(parent, compact)
            if compact then
                if #pool == 0 then card:SetPoint("TOPLEFT", 8, -8); card:SetPoint("TOPRIGHT", -8, -8)
                else card:SetPoint("TOPLEFT", pool[#pool], "BOTTOMLEFT", 0, -6); card:SetPoint("TOPRIGHT", pool[#pool], "BOTTOMRIGHT", 0, -6) end
            end
            card:SetScript("OnClick", function(self)
                if self.neighborhoodGUID then frame:SelectNeighborhood(self.neighborhoodGUID) end
            end)
            pool[#pool + 1] = card
        end
    end

    function frame:SetTab(key)
        if not self.pages[key] then key = "endeavors" end
        self.selectedTab = key
        Addon.Database:GetUI().selectedSubTabs.housing = key
        for tabKey, page in pairs(self.pages) do page:SetShown(tabKey == key) end
        for tabKey, button in pairs(self.subTabButtons) do Widgets:SetButtonActive(button, tabKey == key) end
        self:Refresh()
    end

    function frame:SelectNeighborhood(neighborhoodGUID)
        self.selectedNeighborhoodGUID = neighborhoodGUID
        local character = Addon.WarbandRoster:GetSelected()
        if character and Addon.WarbandRoster:IsCurrent(character.key) then
            service:SelectNeighborhood(neighborhoodGUID)
        else
            self:Refresh()
        end
    end

    function frame:SwitchTo(neighborhoodGUID)
        if service:SwitchNeighborhood(neighborhoodGUID) then self.confirm:Hide() end
    end

    function frame:MaybeOfferSwitch(character, view)
        local suggestion = view.switchSuggestion
        if not character or not Addon.WarbandRoster:IsCurrent(character.key) or type(suggestion) ~= "table" then
            self.confirm:Hide()
            return
        end
        local mode = service:GetSwitchMode()
        local key = service:GetSwitchKey(character.key, suggestion)
        if service:IsSwitchIgnored(character.key, suggestion) then self.confirm:Hide(); return end
        if mode == "automatic" then
            if not service.runtime.switchPendingGUID then self:SwitchTo(suggestion.targetNeighborhoodGUID) end
            return
        end
        if mode == "ask" and service.runtime.promptedSwitchKey ~= key then
            service.runtime.promptedSwitchKey = key
            self.confirm.suggestion = suggestion
            self.confirm.characterKey = character.key
            self.confirm.message:SetText(string.format(
                L.HOUSING_SWITCH_PROMPT,
                suggestion.sourceTitle or L.HOUSING_HOME_ACTIVE,
                suggestion.targetTitle or L.HOUSING_HOME_VIEWING,
                suggestion.targetProgressValue or "--"
            ))
            self.confirm:Show()
            if type(self.confirm.Raise) == "function" then self.confirm:Raise() end
        end
    end

    function frame:Refresh()
        if self.chromeVisible ~= false then service:Open() end
        for _, pair in ipairs({
            { endeavors.tasksScroll, endeavors.tasksScrollChild },
            { activity.milestonesScroll, activity.milestonesScrollChild },
            { activity.logScroll, activity.logScrollChild },
            { self.trackedScroll, self.trackedScrollChild },
        }) do syncScrollWidth(pair[1], pair[2]) end

        local character = Addon.WarbandRoster:GetSelected()
        local preferred = self.selectedNeighborhoodGUID
        local view = character and service:GetView(character.key, preferred) or Addon.HousingLogic:BuildView(nil)
        local state = Addon.StateStore:Get("housing.endeavors")
        local message = view.message
        if character and Addon.WarbandRoster:IsCurrent(character.key) and view.available ~= true then
            if state and state.loading then message = L.HOUSING_LOADING
            elseif state and state.unavailable then message = L.HOUSING_UNAVAILABLE end
        end
        local neighborhoods = type(view.neighborhoods) == "table" and view.neighborhoods or {}
        local available = view.available == true or #neighborhoods > 0
        self.contentEmpty:SetShown(not available)
        self.contentEmpty:SetText(message or "")
        for _, page in pairs(self.pages) do page:SetShown(available and self.selectedTab == page.key) end
        if not available then
            for _, page in pairs(self.pages) do page:Hide() end
            return
        end

        if not self.selectedNeighborhoodGUID then
            self.selectedNeighborhoodGUID = view.selectedNeighborhoodGUID or view.activeNeighborhoodGUID
        end
        if view.selectedNeighborhoodGUID ~= self.selectedNeighborhoodGUID then
            view = service:GetView(character.key, self.selectedNeighborhoodGUID)
            neighborhoods = type(view.neighborhoods) == "table" and view.neighborhoods or neighborhoods
        end

        ensureNeighborhoodCards(self.sidebarNeighborhoodCards, self.neighborhoodsPanel, #neighborhoods, true)
        self.neighborhoodsPanel:SetHeight(math.max(88, math.min(244, (#neighborhoods * 78) + 10)))
        for index, card in ipairs(self.sidebarNeighborhoodCards) do
            applyNeighborhoodCard(card, neighborhoods[index], neighborhoods[index]
                and neighborhoods[index].neighborhoodGUID == self.selectedNeighborhoodGUID)
        end

        local isCurrent = character and Addon.WarbandRoster:IsCurrent(character.key)
        applySummaryPanel(endeavors.summary, view)
        applyStatStrip(endeavors.stats, view.statCards)
        applyRewardSummary(activity.rewardSummary, view.rewardSummary)

        local tasks = type(view.tasks) == "table" and view.tasks or {}
        ensureTaskRows(#tasks)
        for index, row in ipairs(endeavors.taskRows) do setTaskRow(row, tasks[index], isCurrent) end
        endeavors.tasksScrollChild:SetHeight(math.max(10, (#tasks * 58) - 10))
        endeavors.tasksEmpty:SetText(view.loadingTasks and L.HOUSING_LOADING or L.HOUSING_TASKS_EMPTY)
        endeavors.tasksEmpty:SetShown(#tasks == 0)

        local milestones = type(view.milestones) == "table" and view.milestones or {}
        ensureStatusRows(activity.milestoneRows, activity.milestonesScrollChild, #milestones, false)
        for index, row in ipairs(activity.milestoneRows) do StatusRows:Set(row, milestones[index]) end
        activity.milestonesScrollChild:SetHeight(math.max(10, (#milestones * 50) - 8))
        activity.milestonesEmpty:SetShown(#milestones == 0)

        local activityRows = type(view.activity) == "table" and view.activity or {}
        ensureStatusRows(activity.activityRows, activity.logScrollChild, #activityRows, false)
        for index, row in ipairs(activity.activityRows) do StatusRows:Set(row, activityRows[index]) end
        activity.logScrollChild:SetHeight(math.max(10, (#activityRows * 50) - 8))
        activity.logEmpty:SetShown(#activityRows == 0)

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
            row.allowToggle = isCurrent
        end
        self.trackedScrollChild:SetHeight(math.max(10, (#tracked * 50) - 8))
        self.trackedEmpty:SetShown(#tracked == 0)

        local activeCard
        for _, card in ipairs(neighborhoods) do if card.active then activeCard = card break end end
        self.activeName:SetText(activeCard and activeCard.title or L.HOUSING_HOME_NONE)
        local switchMode = service:GetSwitchMode()
        local hasAlternateNeighborhood = #neighborhoods > 1
        self.modeDescription:SetText(hasAlternateNeighborhood and modeDescription(switchMode)
            or L.HOUSING_SWITCH_SINGLE_NEIGHBORHOOD)
        for mode, button in pairs(self.modeButtons) do
            if hasAlternateNeighborhood then button:Enable() else button:Disable() end
            button.tooltipBody = hasAlternateNeighborhood and modeDescription(mode)
                or L.HOUSING_SWITCH_SINGLE_NEIGHBORHOOD
            Widgets:SetButtonActive(button, hasAlternateNeighborhood and mode == switchMode)
        end
        local suggestion = view.switchSuggestion
        local actionTarget
        if type(suggestion) == "table" then
            self.controlMessage:SetText(string.format(
                L.HOUSING_SWITCH_SUGGESTION,
                suggestion.targetTitle or L.HOUSING_HOME_VIEWING,
                suggestion.targetProgressValue or "--"
            ))
            self.controlAction.label:SetText(L.HOUSING_SWITCH_NOW)
            actionTarget = suggestion.targetNeighborhoodGUID
        elseif not view.isActive then
            self.controlMessage:SetText(L.HOUSING_ROUTE_VIEWING_DESC)
            self.controlAction.label:SetText(L.HOUSING_SET_ACTIVE)
            actionTarget = view.neighborhoodGUID
        else
            self.controlMessage:SetText(view.isComplete and L.HOUSING_ACTIVE_COMPLETE or L.HOUSING_ACTIVE_OPEN)
        end
        self.controlAction.targetNeighborhoodGUID = actionTarget
        local showAction = isCurrent and actionTarget ~= nil and service:CanSwitchNeighborhood()
        self.controlAction:SetShown(showAction)
        self.controlPanel:SetHeight(showAction and 152 or 106)
        self:MaybeOfferSwitch(character, view)
    end

    for key, button in pairs(frame.subTabButtons) do
        button:SetScript("OnClick", function() frame:SetTab(key) end)
    end
    frame.controlAction:SetScript("OnClick", function(self)
        if self.targetNeighborhoodGUID then frame:SwitchTo(self.targetNeighborhoodGUID) end
    end)
    for mode, button in pairs(frame.modeButtons) do
        local selectedMode = mode
        button:SetScript("OnClick", function()
            service:SetSwitchMode(selectedMode)
            frame:Refresh()
        end)
    end
    frame.decorationsButton:SetScript("OnClick", function()
        if Addon.Compendium then Addon.Compendium:SetCategory("decorations") end
        Addon.UI:ShowScreen("compendium")
    end)
    frame.dashboardButton:SetScript("OnClick", function() service:OpenDashboard() end)
    frame.confirm.cancel:SetScript("OnClick", function()
        if frame.confirm.characterKey and frame.confirm.suggestion then
            service:IgnoreSwitch(frame.confirm.characterKey, frame.confirm.suggestion)
        end
        frame.confirm:Hide()
    end)
    frame.confirm.accept:SetScript("OnClick", function()
        local suggestion = frame.confirm.suggestion
        if suggestion then frame:SwitchTo(suggestion.targetNeighborhoodGUID) end
    end)
    frame:SetScript("OnHide", function() frame.confirm:Hide(); frame:SetChromeVisible(false) end)
    frame:SetScript("OnShow", function()
        if not frame.chromeVisible then frame:SetChromeVisible(true) end
        local selected = Addon.Database:GetUI().selectedSubTabs.housing
        frame:SetTab(frame.pages[selected] and selected or "endeavors")
    end)
    Addon.StateStore:Subscribe("housing.endeavors", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        frame.selectedNeighborhoodGUID = nil
        if frame:IsShown() then frame:Refresh() end
    end)
    for key, page in pairs(frame.pages) do page.key = key end
    frame.selectedTab = "endeavors"
    return frame
end

Addon.ScreenRegistry:Register({
    id = "housing",
    order = 8,
    label = function() return L.SCREEN_HOUSING end,
    Create = createScreen,
})
