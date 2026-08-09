local _, Addon = ...

local L = Addon.L
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local VerticalNavigation = Addon.VerticalNavigation
local ScrollFrames = Addon.ScrollFrames

local SUB_TABS = {
    { key = "weekly", label = function() return L.PVP_TAB_WEEKLY end },
}

local function getWeeklyRowPoolSize()
    local total = 0
    for _, pool in ipairs(Addon.Data.PVP_WEEKLY.pools or {}) do
        total = total + #(pool.quests or {})
    end
    return math.max(1, total)
end

local function createPvpScreen(_, host)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.layoutVersion = "vertical-pvp-1"
    frame.weeklyRows = {}

    function frame:SetChromeVisible(visible)
        visible = visible == true
        if self.domainVisible == visible then
            return
        end
        self.domainVisible = visible
        if visible then
            Addon.RefreshScheduler:Invalidate("pvp.weekly", 0)
        else
            Addon.RefreshScheduler:Cancel("pvp.weekly")
        end
    end

    frame.navigation = VerticalNavigation:Create(frame, 168)
    frame.navigation.frame:SetPoint("TOPLEFT", 0, 0)
    frame.navigation.frame:SetPoint("BOTTOMLEFT", 0, 0)
    frame.navigation:SetOnSelect(function(subTabKey)
        Addon.Database:GetUI().selectedSubTabs.pvp = subTabKey
        frame:Refresh()
    end)
    frame.navigation:SetDefinitions(SUB_TABS)
    frame.subTabButtons = frame.navigation.buttonsByKey

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation.frame, "TOPRIGHT", 14, 0)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.weeklyCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.weeklyCard:SetAllPoints(frame.contentHost)
    frame.weeklyCard.summary = Widgets:CreateLabel(frame.weeklyCard, "GameFontHighlightSmall", "LEFT")
    frame.weeklyCard.summary:SetPoint("TOPLEFT", 16, -16)
    frame.weeklyCard.reset = Widgets:CreateLabel(frame.weeklyCard, "GameFontHighlightSmall", "LEFT")
    frame.weeklyCard.reset:SetPoint("LEFT", frame.weeklyCard.summary, "RIGHT", 28, 0)
    frame.weeklyCard.giver = Widgets:CreateLabel(frame.weeklyCard, "GameFontHighlightSmall", "LEFT")
    frame.weeklyCard.giver:SetPoint("LEFT", frame.weeklyCard.reset, "RIGHT", 28, 0)
    frame.weeklyCard.subtitle = Widgets:CreateLabel(frame.weeklyCard, "GameFontDisableSmall", "LEFT")
    frame.weeklyCard.subtitle:SetPoint("TOPLEFT", frame.weeklyCard.summary, "BOTTOMLEFT", 0, -8)
    frame.weeklyCard.subtitle:SetPoint("TOPRIGHT", -34, -8)
    frame.weeklyCard.subtitle:SetText(L.PVP_WEEKLY_SUBTITLE)
    frame.weeklyCard.scroll = CreateFrame("ScrollFrame", nil, frame.weeklyCard, "UIPanelScrollFrameTemplate")
    frame.weeklyCard.scroll:SetPoint("TOPLEFT", frame.weeklyCard.subtitle, "BOTTOMLEFT", 0, -12)
    frame.weeklyCard.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.weeklyCard.scroll:EnableMouseWheel(true)
    frame.weeklyCard.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local nextValue = scroll:GetVerticalScroll() - (delta * 84)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), nextValue)))
    end)
    frame.weeklyCard.scrollChild = CreateFrame("Frame", nil, frame.weeklyCard.scroll)
    frame.weeklyCard.scrollChild:SetSize(10, 10)
    frame.weeklyCard.scrollChild.summary = frame.weeklyCard.subtitle
    frame.weeklyCard.scroll:SetScrollChild(frame.weeklyCard.scrollChild)
    ScrollFrames:Style(frame.weeklyCard.scroll, { autoHide = true })
    local previous
    for index = 1, getWeeklyRowPoolSize() do
        local row = StatusRows:Create(frame.weeklyCard.scrollChild, index, previous)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.weeklyCard.scrollChild, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", frame.weeklyCard.scrollChild, "TOPRIGHT", 0, 0)
        end
        frame.weeklyRows[index] = row
        previous = row
    end
    frame.weeklyCard.scroll:SetScript("OnSizeChanged", function(scroll, width)
        frame.weeklyCard.scrollChild:SetWidth(math.max(10, (tonumber(width) or scroll:GetWidth() or 10) - 2))
    end)

    function frame:Refresh()
        local selectedSubTab = Addon.Database:GetUI().selectedSubTabs.pvp or "weekly"
        self.navigation:Refresh()
        if not self.navigation:IsVisible(selectedSubTab) then
            selectedSubTab = "weekly"
            Addon.Database:GetUI().selectedSubTabs.pvp = selectedSubTab
        end
        self.navigation:SetSelected(selectedSubTab)
        self.weeklyCard:Show()
        self.weeklyCard.scrollChild:SetWidth(math.max(10, (self.weeklyCard.scroll:GetWidth() or 10) - 2))

        local character = Addon.WarbandRoster:GetSelected()
        local snapshot = character and Addon.PvpWeekly:GetSnapshot(character.key) or nil
        if not snapshot then
            self.weeklyCard.summary:SetText(L.PVP_WEEKLY_NO_SNAPSHOT)
            self.weeklyCard.reset:SetText("")
            self.weeklyCard.giver:SetText(L.PVP_WEEKLY_GIVER_SHORT)
            self.weeklyCard.scrollChild:SetHeight(10)
            for _, row in ipairs(self.weeklyRows) do
                StatusRows:Set(row, nil)
            end
            ScrollFrames:Refresh(self.weeklyCard.scroll, true)
            return
        end

        self.weeklyCard.summary:SetText(string.format(
            L.PVP_WEEKLY_PROGRESS,
            snapshot.summary.completed,
            snapshot.summary.total
        ))
        self.weeklyCard.reset:SetText(string.format(L.PVP_WEEKLY_RESET, snapshot.summary.resetText))
        self.weeklyCard.giver:SetText(L.PVP_WEEKLY_GIVER_SHORT)
        self.weeklyCard.scrollChild:SetHeight(math.max(10, (#snapshot.rows * 50) - 8))
        for index, row in ipairs(self.weeklyRows) do
            StatusRows:Set(row, snapshot.rows[index])
        end
        ScrollFrames:Refresh(self.weeklyCard.scroll)
    end

    Addon.StateStore:Subscribe("pvp.weekly", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "pvp",
    order = 3,
    label = function() return L.SCREEN_PVP end,
    Create = createPvpScreen,
})
