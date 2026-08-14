local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local Data = Addon.Data.MYTHIC_PLUS
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ScrollFrames = Addon.ScrollFrames

local function addCircularMask(owner, texture)
    if type(owner.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then return nil end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function syncScrollWidth(scroll, child)
    local width = tonumber(scroll and scroll.GetWidth and scroll:GetWidth()) or 0
    if width > 20 then
        child:SetWidth(math.max(10, width - 2))
    elseif (tonumber(child and child.GetWidth and child:GetWidth()) or 0) < 20 then
        child:SetWidth(scroll.fallbackChildWidth)
    end
end

local function createScroll(parent, topAnchor, fallbackChildWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, 12)
    scroll:EnableMouseWheel(true)
    scroll.fallbackChildWidth = math.max(20, tonumber(fallbackChildWidth) or 220)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scroll.fallbackChildWidth, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, width)
        if (tonumber(width) or 0) > 20 then
            child:SetWidth(math.max(10, width - 2))
        else
            syncScrollWidth(self, child)
        end
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

local function createKeyPanel(parent)
    local panel = Widgets:CreatePanel(parent, "cardInset")
    panel:SetPoint("TOPLEFT", parent.title, "BOTTOMLEFT", 0, -14)
    panel:SetPoint("TOPRIGHT", -16, 0)
    panel:SetHeight(118)
    panel.iconBackplate = panel:CreateTexture(nil, "ARTWORK")
    panel.iconBackplate:SetSize(58, 58)
    panel.iconBackplate:SetPoint("LEFT", 14, 0)
    panel.iconBackplate:SetColorTexture(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )
    panel.iconBackplateMask = addCircularMask(panel, panel.iconBackplate)
    panel.icon = panel:CreateTexture(nil, "OVERLAY", nil, 1)
    panel.icon:SetSize(51, 51)
    panel.icon:SetPoint("CENTER", panel.iconBackplate, "CENTER", 0, 0)
    panel.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    panel.iconMask = addCircularMask(panel, panel.icon)
    panel.label = Widgets:CreateLabel(panel, "GameFontDisableSmall", "LEFT")
    panel.label:SetPoint("TOPLEFT", panel.iconBackplate, "TOPRIGHT", 12, -3)
    panel.label:SetPoint("TOPRIGHT", -12, -3)
    panel.value = Widgets:CreateLabel(panel, "GameFontNormalLarge", "LEFT")
    panel.value:SetPoint("TOPLEFT", panel.label, "BOTTOMLEFT", 0, -5)
    panel.value:SetPoint("TOPRIGHT", -12, 0)
    panel.meta = Widgets:CreateLabel(panel, "GameFontHighlightSmall", "LEFT")
    panel.meta:SetPoint("TOPLEFT", panel.value, "BOTTOMLEFT", 0, -5)
    panel.meta:SetPoint("TOPRIGHT", -12, 0)
    return panel
end

local function createStatCard(parent, previous)
    local card = Widgets:CreatePanel(parent, "cardInset")
    card:SetHeight(72)
    if previous then
        card:SetPoint("TOPLEFT", previous, "TOPRIGHT", 10, 0)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -48)
    end
    card.label = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.label:SetPoint("TOPLEFT", 12, -10)
    card.label:SetPoint("TOPRIGHT", -12, -10)
    card.value = Widgets:CreateLabel(card, "GameFontNormalLarge", "LEFT")
    card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
    card.value:SetPoint("TOPRIGHT", -12, 0)
    card.meta = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.meta:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -3)
    card.meta:SetPoint("TOPRIGHT", -12, 0)
    return card
end

local function applyStatCard(card, entry, color)
    entry = type(entry) == "table" and entry or {}
    card.label:SetText(entry.label or "")
    card.value:SetText(entry.value or "--")
    card.meta:SetText(entry.meta or "")
    color = color or Theme.colors.gold
    card.value:SetTextColor(color[1], color[2], color[3], 1)
end

local function createDungeonRow(parent, previous)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(76)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Addon.Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.86)
    row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.58)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -10)
    else
        row:SetPoint("TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", 0, 0)
    end
    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -7)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 7)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)
    row.iconBackplate = row:CreateTexture(nil, "ARTWORK")
    row.iconBackplate:SetPoint("LEFT", 13, 0)
    row.iconBackplate:SetSize(50, 50)
    row.iconBackplate:SetTexture(Addon.Assets.classBackplate)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetPoint("CENTER", row.iconBackplate, "CENTER", 0, 0)
    row.icon:SetSize(44, 44)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconMask = addCircularMask(row, row.icon)
    row.iconRing = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.iconRing:SetPoint("CENTER", row.iconBackplate, "CENTER", 0, 0)
    row.iconRing:SetSize(50, 50)
    row.iconRing:SetTexture(Addon.Assets.classRing)
    row.title = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.title:SetPoint("TOPLEFT", row.iconBackplate, "TOPRIGHT", 12, -4)
    row.title:SetPoint("TOPRIGHT", -96, -4)
    row.best = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.best:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.best:SetPoint("TOPRIGHT", -96, 0)
    row.meta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", row.best, "BOTTOMLEFT", 0, -4)
    row.meta:SetPoint("TOPRIGHT", -14, 0)
    row.value = Widgets:CreateLabel(row, "GameFontNormalLarge", "RIGHT")
    row.value:SetPoint("TOPRIGHT", -13, -10)
    row.status = Widgets:CreateLabel(row, "GameFontDisableSmall", "RIGHT")
    row.status:SetPoint("TOPRIGHT", row.value, "BOTTOMRIGHT", 0, -6)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.92)
        if self.tooltipTitle and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(self.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            for _, line in ipairs(self.tooltipLines or {}) do
                if line then GameTooltip:AddLine(line, 0.92, 0.92, 0.92, true) end
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.58)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:Hide()
    return row
end

local function setDungeonRow(row, entry)
    if not entry then row:Hide(); return end
    local timed = entry.bestStatus == "timed"
    local color = timed and { 0.34, 0.88, 0.48, 1 } or Theme.colors.gold
    row.icon:SetTexture(entry.texture or Data.fallbackIcon)
    row.title:SetText(entry.name or L.UNKNOWN)
    row.best:SetText(entry.bestText or L.MYTHIC_PLUS_DUNGEON_BEST_NONE)
    row.meta:SetText(entry.weeklyText or L.MYTHIC_PLUS_DUNGEON_WEEKLY_NONE)
    row.value:SetText((tonumber(entry.score) or 0) > 0 and tostring(math.floor((tonumber(entry.score) or 0) + 0.5)) or "--")
    row.value:SetTextColor(color[1], color[2], color[3], 1)
    row.status:SetText(entry.bestStatus == "timed" and L.MYTHIC_PLUS_TIMED
        or entry.bestStatus == "overtime" and L.MYTHIC_PLUS_OVERTIME or "")
    row.statusLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.tooltipTitle = entry.tooltipTitle
    row.tooltipLines = entry.tooltipLines
    row:Show()
end

local function createScreen(_, host)
    local shellFrame = Addon.UI.frame
    local service = Addon.MythicPlus
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame:Hide()
    frame.layoutVersion = "mythicplus-active-season-3"

    frame.subTabButtons = {}
    local previousSubTab
    for index, definition in ipairs(Data.subTabs) do
        local button = Widgets:CreateButton(frame, L[definition.labelKey], 188, 24, "tab")
        if previousSubTab then
            button:SetPoint("LEFT", previousSubTab, "RIGHT", 8, 0)
        else
            button:SetPoint("TOPLEFT", 0, 0)
            frame.navigation = button
        end
        button.seasonKey = definition.key
        button:SetScript("OnClick", function(selfButton)
            Addon.Database:GetUI().selectedSubTabs.mythicplus = selfButton.seasonKey
            frame:Refresh()
        end)
        frame.subTabButtons[definition.key] = button
        previousSubTab = button
    end

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation, "BOTTOMLEFT", 0, -10)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.summaryPanel = Widgets:CreatePanel(frame.contentHost, "card")
    frame.summaryPanel:SetPoint("TOPLEFT", 0, 0)
    frame.summaryPanel:SetPoint("TOPRIGHT", 0, 0)
    frame.summaryPanel:SetHeight(136)
    frame.summaryTitle = Widgets:CreateLabel(frame.summaryPanel, "GameFontNormalLarge", "LEFT")
    frame.summaryTitle:SetPoint("TOPLEFT", 16, -16)
    frame.summaryTitle:SetText(L.MYTHIC_PLUS_TITLE)
    frame.statCards = {}
    local previousStat
    for index = 1, 3 do
        local card = createStatCard(frame.summaryPanel, previousStat)
        card:SetWidth(230)
        frame.statCards[index] = card
        previousStat = card
    end

    frame.listPanel = Widgets:CreatePanel(frame.contentHost, "cardInset")
    frame.listPanel:SetPoint("TOPLEFT", frame.summaryPanel, "BOTTOMLEFT", 0, -12)
    frame.listPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.listTitle = Widgets:CreateLabel(frame.listPanel, "GameFontNormalLarge", "LEFT")
    frame.listTitle:SetPoint("TOPLEFT", 16, -15)
    frame.listSubtitle = Widgets:CreateLabel(frame.listPanel, "GameFontHighlightSmall", "LEFT")
    frame.listSubtitle:SetPoint("TOPLEFT", frame.listTitle, "BOTTOMLEFT", 0, -6)
    frame.listSubtitle:SetPoint("TOPRIGHT", -16, 0)
    frame.listScroll, frame.listScrollChild = createScroll(frame.listPanel, frame.listSubtitle, 690)
    frame.listEmpty = Widgets:CreateLabel(frame.listScrollChild, "GameFontDisable", "LEFT")
    frame.listEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.listEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.dungeonRows = {}

    frame.sidebarPanel = Widgets:CreatePanel(shellFrame.sidebar, "sidebar")
    frame.sidebarPanel:SetAllPoints(shellFrame.sidebar)
    frame.sidebarPanel:SetFrameLevel(shellFrame.sidebar:GetFrameLevel() + 10)
    createHeader(frame.sidebarPanel, L.MYTHIC_PLUS_SUMMARY_KEY)
    frame.keyPanel = createKeyPanel(frame.sidebarPanel)
    frame.weekMeta = Widgets:CreateLabel(frame.sidebarPanel, "GameFontHighlightSmall", "LEFT")
    frame.weekMeta:SetPoint("TOPLEFT", frame.keyPanel, "BOTTOMLEFT", 0, -10)
    frame.weekMeta:SetPoint("TOPRIGHT", -16, 0)
    frame.overviewButton = Widgets:CreateButton(frame.sidebarPanel, L.MYTHIC_PLUS_WARBAND_OVERVIEW_BUTTON, 220, 28)
    frame.overviewButton:SetPoint("TOPLEFT", frame.weekMeta, "BOTTOMLEFT", 0, -12)
    frame.overviewButton:SetPoint("TOPRIGHT", -16, 0)
    frame.overviewButton:SetScript("OnClick", function()
        Addon.UI:ToggleMythicPlusOverview()
    end)
    frame.affixTitle = Widgets:CreateLabel(frame.sidebarPanel, "GameFontNormalLarge", "LEFT")
    frame.affixTitle:SetPoint("TOPLEFT", frame.overviewButton, "BOTTOMLEFT", 0, -18)
    frame.affixTitle:SetText(L.MYTHIC_PLUS_SECTION_AFFIXES)
    frame.affixRows = {}
    local previousAffix
    for index = 1, 4 do
        local row = StatusRows:Create(frame.sidebarPanel, index, previousAffix)
        row:ClearAllPoints()
        if previousAffix then row:SetPoint("TOPLEFT", previousAffix, "BOTTOMLEFT", 0, -7)
        else row:SetPoint("TOPLEFT", frame.affixTitle, "BOTTOMLEFT", 0, -12) end
        row:SetPoint("TOPRIGHT", -16, 0)
        frame.affixRows[index] = row
        previousAffix = row
    end

    frame.utilityPanel = Widgets:CreatePanel(shellFrame.utility, "utility")
    frame.utilityPanel:SetAllPoints(shellFrame.utility)
    frame.utilityPanel:SetFrameLevel(shellFrame.utility:GetFrameLevel() + 10)
    createHeader(frame.utilityPanel, L.MYTHIC_PLUS_UTILITY_TITLE)
    frame.recentPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.recentPanel:SetPoint("TOPLEFT", frame.utilityPanel.title, "BOTTOMLEFT", 0, -14)
    frame.recentPanel:SetPoint("TOPRIGHT", -16, 0)
    frame.recentPanel:SetHeight(255)
    frame.recentTitle = Widgets:CreateLabel(frame.recentPanel, "GameFontNormal", "LEFT")
    frame.recentTitle:SetPoint("TOPLEFT", 12, -12)
    frame.recentTitle:SetText(L.MYTHIC_PLUS_SECTION_RECENT)
    frame.recentScroll, frame.recentScrollChild = createScroll(frame.recentPanel, frame.recentTitle, 230)
    frame.recentEmpty = Widgets:CreateLabel(frame.recentScrollChild, "GameFontDisableSmall", "LEFT")
    frame.recentEmpty:SetPoint("TOPLEFT", 4, -4)
    frame.recentEmpty:SetPoint("TOPRIGHT", -4, -4)
    frame.recentEmpty:SetWordWrap(true)
    frame.recentEmpty:SetText(L.MYTHIC_PLUS_RECENT_EMPTY)
    frame.recentRows = {}
    frame.goalsPanel = Widgets:CreatePanel(frame.utilityPanel, "cardInset")
    frame.goalsPanel:SetPoint("TOPLEFT", frame.recentPanel, "BOTTOMLEFT", 0, -12)
    frame.goalsPanel:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.goalsTitle = Widgets:CreateLabel(frame.goalsPanel, "GameFontNormal", "LEFT")
    frame.goalsTitle:SetPoint("TOPLEFT", 12, -12)
    frame.goalsTitle:SetText(L.MYTHIC_PLUS_SECTION_REWARDS)
    frame.goalsScroll, frame.goalsScrollChild = createScroll(frame.goalsPanel, frame.goalsTitle, 230)
    frame.goalRows = {}

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
        if visible then service:Open(self) else service:Close(self) end
    end

    local function ensureRows(pool, parent, count)
        while #pool < count do
            pool[#pool + 1] = createDungeonRow(parent, pool[#pool])
        end
    end

    local function ensureStatusRows(pool, parent, count)
        while #pool < count do
            local previous = pool[#pool]
            local row = StatusRows:Create(parent, #pool + 1, previous)
            row:ClearAllPoints()
            if previous then row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -7)
            else row:SetPoint("TOPLEFT", 0, 0) end
            row:SetPoint("TOPRIGHT", 0, 0)
            pool[#pool + 1] = row
        end
    end

    function frame:Refresh()
        if self.chromeVisible ~= false then service:Open(self) end
        syncScrollWidth(self.listScroll, self.listScrollChild)
        syncScrollWidth(self.recentScroll, self.recentScrollChild)
        syncScrollWidth(self.goalsScroll, self.goalsScrollChild)
        local selectedSeasonKey = Addon.Database:GetUI().selectedSubTabs.mythicplus
        if not Data.seasonKeys[selectedSeasonKey] then
            selectedSeasonKey = Data.seasonKey
            Addon.Database:GetUI().selectedSubTabs.mythicplus = selectedSeasonKey
        end
        for seasonKey, button in pairs(self.subTabButtons) do
            Widgets:SetButtonActive(button, seasonKey == selectedSeasonKey)
        end
        local character = Addon.WarbandRoster:GetSelected()
        local view = character and service:GetView(character.key, selectedSeasonKey)
            or Addon.MythicPlusLogic:BuildView(nil, selectedSeasonKey)
        local available = view.available == true
        local key = available and view.currentKey or {}
        self.keyPanel.icon:SetTexture(key.texture or Data.fallbackIcon)
        self.keyPanel.label:SetText(L.MYTHIC_PLUS_SUMMARY_KEY)
        self.keyPanel.value:SetText((tonumber(key.level) or 0) > 0 and string.format("+%d", key.level) or L.MYTHIC_PLUS_KEY_NONE)
        self.keyPanel.meta:SetText(key.name or "")
        self.weekMeta:SetText(available and (tonumber(view.currentWeekBestLevel) or 0) > 0
            and string.format(L.MYTHIC_PLUS_KEY_META, view.currentWeekBestLevel or 0, view.weeklyRewardLevel or 0)
            or L.MYTHIC_PLUS_KEY_META_EMPTY)
        Widgets:SetButtonActive(self.overviewButton, Addon.UI.mythicPlusOverviewOpen == true)

        local summary = available and view.summary or {}
        local scoreColor = Addon.MythicPlusLogic:GetScoreColor(
            summary.score and summary.score.score or 0
        )
        applyStatCard(self.statCards[1], summary.score, scoreColor)
        applyStatCard(self.statCards[2], summary.vault)
        applyStatCard(self.statCards[3], summary.portals)

        for index, row in ipairs(self.affixRows) do
            StatusRows:Set(row, available and view.affixes[index] or nil)
        end

        local entries = available and view.dungeons or {}
        self.listTitle:SetText(L.MYTHIC_PLUS_SECTION_DUNGEONS)
        self.listSubtitle:SetText(L.MYTHIC_PLUS_SECTION_DUNGEONS_SUBTITLE)
        self.listEmpty:SetText(available and L.MYTHIC_PLUS_DUNGEONS_EMPTY or view.message)
        ensureRows(self.dungeonRows, self.listScrollChild, #entries)
        for index, row in ipairs(self.dungeonRows) do setDungeonRow(row, entries[index]) end
        self.listScrollChild:SetHeight(math.max(10, (#entries * 86) - 10))
        self.listEmpty:SetShown(#entries == 0)

        local recent = available and view.recentRuns or {}
        ensureStatusRows(self.recentRows, self.recentScrollChild, #recent)
        for index, row in ipairs(self.recentRows) do StatusRows:Set(row, recent[index]) end
        self.recentScrollChild:SetHeight(math.max(10, (#recent * 49) - 7))
        self.recentEmpty:SetShown(#recent == 0)

        local rewards = available and view.rewards or {}
        ensureStatusRows(self.goalRows, self.goalsScrollChild, #rewards)
        for index, row in ipairs(self.goalRows) do StatusRows:Set(row, rewards[index]) end
        self.goalsScrollChild:SetHeight(math.max(10, (#rewards * 49) - 7))
    end

    frame:SetScript("OnHide", function() frame:SetChromeVisible(false) end)
    frame:SetScript("OnShow", function()
        if not frame.chromeVisible then frame:SetChromeVisible(true) end
        frame:Refresh()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if frame:IsShown() then
                    syncScrollWidth(frame.listScroll, frame.listScrollChild)
                    syncScrollWidth(frame.recentScroll, frame.recentScrollChild)
                    syncScrollWidth(frame.goalsScroll, frame.goalsScrollChild)
                end
            end)
        end
    end)
    Addon.StateStore:Subscribe(Data.stateID, frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    return frame
end

Addon.ScreenRegistry:Register({
    id = "mythicplus",
    order = 7,
    label = function() return L.SCREEN_MYTHICPLUS end,
    Create = createScreen,
})
