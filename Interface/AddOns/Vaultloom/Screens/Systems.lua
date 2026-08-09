local _, Addon = ...

local L = Addon.L
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local VerticalNavigation = Addon.VerticalNavigation
local Theme = Addon.Theme
local ScrollFrames = Addon.ScrollFrames

local SUB_TABS = {
    { key = "professions", label = function() return L.SYSTEMS_TAB_PROFESSIONS end },
    { key = "cooldowns", label = function() return L.SYSTEMS_TAB_COOLDOWNS end },
}

local function currentSelection()
    return Addon.WarbandRoster:GetSelected()
end

local function isCurrentCharacter(character)
    return type(character) == "table" and Addon.WarbandRoster:IsCurrent(character.key)
end

local function createSystemsScreen(_, host)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame:Hide()
    frame.layoutVersion = "vertical-systems-2"
    frame.professionRows = {}
    frame.knowledgeRows = {}
    frame.concentrationRows = {}
    frame.cooldownRows = {}

    local domainIDs = {
        "systems.professions",
        "systems.cooldowns",
    }

    function frame:SetChromeVisible(visible)
        visible = visible == true
        if self.domainVisible == visible then
            return
        end
        self.domainVisible = visible
        for _, domainID in ipairs(domainIDs) do
            if visible then
                Addon.RefreshScheduler:Invalidate(domainID, 0)
            else
                Addon.RefreshScheduler:Cancel(domainID)
            end
        end
    end

    frame.navigation = VerticalNavigation:Create(frame, 168)
    frame.navigation.frame:SetPoint("TOPLEFT", 0, 0)
    frame.navigation.frame:SetPoint("BOTTOMLEFT", 0, 0)

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation.frame, "TOPRIGHT", 14, 0)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.professionsCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.professionsCard:SetAllPoints(frame.contentHost)
    frame.professionsCard.summary = Widgets:CreateLabel(frame.professionsCard, "GameFontHighlightSmall", "LEFT")
    frame.professionsCard.summary:SetPoint("TOPLEFT", 16, -16)
    frame.professionsCard.reset = Widgets:CreateLabel(frame.professionsCard, "GameFontHighlightSmall", "LEFT")
    frame.professionsCard.reset:SetPoint("LEFT", frame.professionsCard.summary, "RIGHT", 28, 0)
    frame.professionsCard.darkmoon = Widgets:CreateLabel(frame.professionsCard, "GameFontHighlightSmall", "LEFT")
    frame.professionsCard.darkmoon:SetPoint("LEFT", frame.professionsCard.reset, "RIGHT", 28, 0)
    frame.professionsCard.subtitle = Widgets:CreateLabel(frame.professionsCard, "GameFontDisableSmall", "LEFT")
    frame.professionsCard.subtitle:SetPoint("TOPLEFT", frame.professionsCard.summary, "BOTTOMLEFT", 0, -8)
    frame.professionsCard.subtitle:SetPoint("TOPRIGHT", -30, -8)

    frame.professionsCard.knowledgeHeader = Widgets:CreateLabel(frame.professionsCard, "GameFontNormalSmall", "LEFT")
    frame.professionsCard.knowledgeHeader:SetPoint("TOPLEFT", frame.professionsCard.subtitle, "BOTTOMLEFT", 0, -16)
    frame.professionsCard.knowledgeHeader:SetText(L.PROFESSIONS_KNOWLEDGE_LABEL)
    local previous
    for index = 1, 2 do
        local row = StatusRows:Create(frame.professionsCard, index, previous)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.professionsCard.knowledgeHeader, "BOTTOMLEFT", 0, -8)
            row:SetPoint("TOPRIGHT", frame.professionsCard, "TOPRIGHT", -30, 0)
        end
        frame.knowledgeRows[index] = row
        previous = row
    end

    frame.professionsCard.weeklyHeader = Widgets:CreateLabel(frame.professionsCard, "GameFontNormalSmall", "LEFT")
    frame.professionsCard.weeklyHeader:SetText(L.PROFESSIONS_WEEKLY_LABEL)
    frame.professionsCard.scroll = CreateFrame("ScrollFrame", nil, frame.professionsCard, "UIPanelScrollFrameTemplate")
    frame.professionsCard.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.professionsCard.scroll:EnableMouseWheel(true)
    frame.professionsCard.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local nextValue = scroll:GetVerticalScroll() - (delta * 84)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), nextValue)))
    end)
    frame.professionsCard.scrollChild = CreateFrame("Frame", nil, frame.professionsCard.scroll)
    frame.professionsCard.scrollChild:SetSize(10, 10)
    frame.professionsCard.scrollChild.summary = frame.professionsCard.weeklyHeader
    frame.professionsCard.scroll:SetScrollChild(frame.professionsCard.scrollChild)
    ScrollFrames:Style(frame.professionsCard.scroll, { autoHide = true })
    previous = nil
    for index = 1, 8 do
        local row = StatusRows:Create(frame.professionsCard.scrollChild, index, previous)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.professionsCard.scrollChild, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", frame.professionsCard.scrollChild, "TOPRIGHT", 0, 0)
        end
        frame.professionRows[index] = row
        previous = row
    end
    frame.professionsCard.scroll:SetScript("OnSizeChanged", function(scroll, width)
        frame.professionsCard.scrollChild:SetWidth(math.max(10, (tonumber(width) or scroll:GetWidth() or 10) - 2))
    end)

    frame.cooldownsCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.cooldownsCard:SetAllPoints(frame.contentHost)
    frame.cooldownsCard.summary1 = Widgets:CreateLabel(frame.cooldownsCard, "GameFontHighlightSmall", "LEFT")
    frame.cooldownsCard.summary1:SetPoint("TOPLEFT", 16, -16)
    frame.cooldownsCard.summary2 = Widgets:CreateLabel(frame.cooldownsCard, "GameFontHighlightSmall", "LEFT")
    frame.cooldownsCard.summary2:SetPoint("LEFT", frame.cooldownsCard.summary1, "RIGHT", 28, 0)
    frame.cooldownsCard.summary3 = Widgets:CreateLabel(frame.cooldownsCard, "GameFontHighlightSmall", "LEFT")
    frame.cooldownsCard.summary3:SetPoint("LEFT", frame.cooldownsCard.summary2, "RIGHT", 28, 0)
    frame.cooldownsCard.subtitle = Widgets:CreateLabel(frame.cooldownsCard, "GameFontDisableSmall", "LEFT")
    frame.cooldownsCard.subtitle:SetPoint("TOPLEFT", frame.cooldownsCard.summary1, "BOTTOMLEFT", 0, -8)
    frame.cooldownsCard.subtitle:SetPoint("TOPRIGHT", -30, -8)
    frame.cooldownsCard.subtitle:SetText(L.PROFESSION_COOLDOWNS_SUBTITLE)

    frame.cooldownsCard.concentrationHeader = Widgets:CreateLabel(frame.cooldownsCard, "GameFontNormalSmall", "LEFT")
    frame.cooldownsCard.concentrationHeader:SetPoint("TOPLEFT", frame.cooldownsCard.subtitle, "BOTTOMLEFT", 0, -16)
    frame.cooldownsCard.concentrationHeader:SetText(L.PROFESSION_COOLDOWNS_CONCENTRATION)

    local previousConcentration
    for index = 1, 2 do
        local row = CreateFrame("Frame", nil, frame.cooldownsCard)
        row:SetHeight(42)
        if previousConcentration then
            row:SetPoint("TOPLEFT", previousConcentration, "BOTTOMLEFT", 0, -10)
            row:SetPoint("TOPRIGHT", previousConcentration, "BOTTOMRIGHT", 0, -10)
        else
            row:SetPoint("TOPLEFT", frame.cooldownsCard.concentrationHeader, "BOTTOMLEFT", 0, -10)
            row:SetPoint("TOPRIGHT", frame.cooldownsCard, "TOPRIGHT", -30, 0)
        end
        row.label = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.label:SetPoint("TOPRIGHT", -104, 0)
        row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
        row.value:SetPoint("RIGHT", 0, 0)
        row.value:SetPoint("CENTER", row.label, "CENTER", 0, 0)
        row.value:SetWidth(100)
        row.bar = Widgets:CreateProgressBar(row)
        row.bar:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -6)
        row.bar:SetPoint("TOPRIGHT", 0, 0)
        row.bar:SetHeight(12)
        row.hitbox = CreateFrame("Button", nil, row)
        row.hitbox:SetAllPoints(row)
        row.hitbox:SetScript("OnEnter", function()
            if row.tooltipTitle and GameTooltip then
                GameTooltip:SetOwner(row.hitbox, "ANCHOR_CURSOR_RIGHT")
                GameTooltip:AddLine(row.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
                for _, line in ipairs(row.tooltipLines or {}) do
                    GameTooltip:AddLine(line, 0.92, 0.92, 0.92, true)
                end
                GameTooltip:Show()
            end
        end)
        row.hitbox:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        frame.concentrationRows[index] = row
        previousConcentration = row
    end

    frame.cooldownsCard.cooldownHeader = Widgets:CreateLabel(frame.cooldownsCard, "GameFontNormalSmall", "LEFT")
    frame.cooldownsCard.cooldownHeader:SetPoint("TOPLEFT", frame.concentrationRows[2], "BOTTOMLEFT", 0, -16)
    frame.cooldownsCard.cooldownHeader:SetText(L.PROFESSION_COOLDOWNS_COOLDOWNS)
    frame.cooldownsCard.summary = frame.cooldownsCard.cooldownHeader
    local previousCooldown
    for index = 1, 6 do
        local row = StatusRows:Create(frame.cooldownsCard, index, previousCooldown)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.cooldownsCard.cooldownHeader, "BOTTOMLEFT", 0, -8)
            row:SetPoint("TOPRIGHT", frame.cooldownsCard, "TOPRIGHT", -30, 0)
        end
        frame.cooldownRows[index] = row
        previousCooldown = row
    end

    local function refreshKnowledge(character, knowledge)
        local entries = type(knowledge) == "table" and knowledge.professions or {}
        local hasKnowledge = #entries > 0
        frame.professionsCard.knowledgeHeader:SetShown(hasKnowledge)
        for index, row in ipairs(frame.knowledgeRows) do
            local entry = entries[index]
            if entry then
                local points = math.max(0, tonumber(entry.points) or 0)
                local clickEntry = entry
                local clickCharacterKey = character and character.key or nil
                local tooltip = points > 0
                    and string.format(L.PROFESSIONS_KNOWLEDGE_TOOLTIP_AVAILABLE, entry.name, points)
                    or string.format(L.PROFESSIONS_KNOWLEDGE_TOOLTIP_EMPTY, entry.name)
                StatusRows:Set(row, {
                    label = entry.name,
                    text = points > 99 and "99+" or tostring(points),
                    status = points > 0 and "open" or "missing",
                    badgeFullTexture = Addon.Assets.professionBadges
                        and Addon.Assets.professionBadges[entry.professionKey],
                    badgeTexture = entry.icon,
                    tooltipTitle = entry.name,
                    tooltipLines = {
                        tooltip,
                        isCurrentCharacter(character) and L.PROFESSIONS_KNOWLEDGE_TOOLTIP_OPEN
                            or L.PROFESSIONS_KNOWLEDGE_TOOLTIP_ALT,
                    },
                })
                row.hitbox:SetScript("OnClick", isCurrentCharacter(character) and function()
                    Addon.Professions:Open(clickEntry, clickCharacterKey)
                end or nil)
            else
                StatusRows:Set(row, nil)
            end
        end

        frame.professionsCard.weeklyHeader:ClearAllPoints()
        if hasKnowledge then
            local lastRow = frame.knowledgeRows[math.min(2, #entries)]
            frame.professionsCard.weeklyHeader:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -16)
        else
            frame.professionsCard.weeklyHeader:SetPoint("TOPLEFT", frame.professionsCard.subtitle, "BOTTOMLEFT", 0, -16)
        end
        frame.professionsCard.scroll:ClearAllPoints()
        frame.professionsCard.scroll:SetPoint("TOPLEFT", frame.professionsCard.weeklyHeader, "BOTTOMLEFT", 0, -10)
        frame.professionsCard.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    end

    local function setConcentrationRow(row, entry)
        if not entry then
            row.tooltipTitle = nil
            row.tooltipLines = nil
            row:Hide()
            return
        end
        row.label:SetText(entry.label or "")
        row.value:SetText(entry.text or "--")
        row.tooltipTitle = entry.tooltipTitle or entry.label
        row.tooltipLines = entry.tooltipLines
        local color = entry.status == "complete" and { 0.34, 0.88, 0.48, 1 }
            or entry.status == "open" and Theme.colors.gold
            or Theme.colors.muted
        row.value:SetTextColor(color[1], color[2], color[3], 1)
        Widgets:SetProgress(row.bar, entry.ratio or 0, 1, color)
        row:Show()
    end

    local function refreshCooldowns(character)
        local view = character and Addon.ProfessionCooldowns:GetView(character.key) or {}
        local summary = view.summary or {}
        local concentrationRows = view.concentrationRows or {}
        local cooldownRows = view.cooldownRows or {}
        frame.cooldownsCard.summary1:SetText(string.format(
            "%s  %d/%d",
            L.PROFESSION_COOLDOWNS_CONCENTRATION,
            tonumber(summary.concentrationKnown) or 0,
            tonumber(summary.concentrationTotal) or 0
        ))
        frame.cooldownsCard.summary2:SetText(string.format(
            "%s  %d/%d",
            L.PROFESSION_COOLDOWNS_PROGRESS,
            tonumber(summary.cooldownReady) or 0,
            tonumber(summary.cooldownTotal) or 0
        ))
        frame.cooldownsCard.summary3:SetText(
            (tonumber(summary.updatedAt) or 0) > 0
                and string.format(L.PROFESSION_COOLDOWNS_LAST_SYNC, summary.lastSyncText or "")
                or ""
        )

        if #concentrationRows == 0 then
            concentrationRows = {
                {
                    label = L.PROFESSION_COOLDOWNS_CONCENTRATION,
                    text = "--",
                    ratio = 0,
                    status = "missing",
                    tooltipTitle = L.PROFESSION_COOLDOWNS_CONCENTRATION,
                    tooltipLines = { isCurrentCharacter(character) and L.PROFESSION_COOLDOWNS_OPEN_HINT or L.PROFESSION_COOLDOWNS_ALT_HINT },
                },
            }
        end
        for index, row in ipairs(frame.concentrationRows) do
            setConcentrationRow(row, concentrationRows[index])
        end

        if #cooldownRows == 0 then
            cooldownRows = {
                {
                    label = L.PROFESSION_COOLDOWNS_NO_COOLDOWNS,
                    text = "--",
                    status = "missing",
                    tooltipTitle = L.PROFESSION_COOLDOWNS_NO_COOLDOWNS,
                    tooltipLines = { isCurrentCharacter(character) and L.PROFESSION_COOLDOWNS_OPEN_HINT or L.PROFESSION_COOLDOWNS_ALT_HINT },
                },
            }
        elseif #cooldownRows > #frame.cooldownRows then
            local hiddenCount = #cooldownRows - #frame.cooldownRows + 1
            cooldownRows[#frame.cooldownRows] = {
                label = "+" .. tostring(hiddenCount),
                text = L.PROFESSION_COOLDOWNS_PROGRESS,
                status = "missing",
                hideStatusBadge = true,
                tooltipTitle = L.PROFESSION_COOLDOWNS_COOLDOWNS,
                tooltipLines = { string.format(L.PROFESSION_COOLDOWNS_MORE_ROWS, hiddenCount) },
            }
        end
        for index, row in ipairs(frame.cooldownRows) do
            StatusRows:Set(row, cooldownRows[index])
        end
    end

    function frame:Refresh()
        local selected = Addon.Database:GetUI().selectedSubTabs.systems or "professions"
        self.navigation:Refresh()
        if not self.navigation:IsVisible(selected) then
            selected = "professions"
            Addon.Database:GetUI().selectedSubTabs.systems = selected
        end
        self.navigation:SetSelected(selected)
        self.professionsCard:SetShown(selected == "professions")
        self.cooldownsCard:SetShown(selected == "cooldowns")
        local character = currentSelection()
        if selected == "cooldowns" then
            refreshCooldowns(character)
            return
        end

        local snapshot = character and Addon.Professions:GetSnapshot(character.key) or nil
        local knowledge = character and Addon.Professions:GetKnowledge(character.key) or nil
        refreshKnowledge(character, knowledge)
        self.professionsCard.scrollChild:SetWidth(math.max(10, (self.professionsCard.scroll:GetWidth() or 10) - 2))
        if not snapshot then
            self.professionsCard.summary:SetText(L.PROFESSIONS_NO_SNAPSHOT)
            self.professionsCard.reset:SetText("")
            self.professionsCard.darkmoon:SetText("")
            self.professionsCard.subtitle:SetText(L.PROFESSIONS_SUBTITLE)
            self.professionsCard.scrollChild:SetHeight(10)
            for _, row in ipairs(self.professionRows) do
                StatusRows:Set(row, nil)
            end
            ScrollFrames:Refresh(self.professionsCard.scroll, true)
            return
        end

        local runtimeState = Addon.StateStore:Get("systems.professions")
        local darkmoonActive = type(runtimeState) == "table" and runtimeState.darkmoonActive == true
        self.professionsCard.summary:SetText(string.format(
            L.PROFESSIONS_PROGRESS,
            snapshot.summary.completed,
            snapshot.summary.total
        ))
        self.professionsCard.reset:SetText(string.format(L.PROFESSIONS_RESET, snapshot.summary.resetText))
        self.professionsCard.darkmoon:SetText(darkmoonActive and L.PROFESSIONS_DARKMOON_HINT or "")
        self.professionsCard.subtitle:SetText(darkmoonActive
            and L.PROFESSIONS_SUBTITLE_WITH_DARKMOON
            or L.PROFESSIONS_SUBTITLE)
        self.professionsCard.scrollChild:SetHeight(math.max(10, (#snapshot.rows * 50) - 8))
        for index, row in ipairs(self.professionRows) do
            local entry = snapshot.rows[index]
            StatusRows:Set(row, entry)
            if entry and entry.skillLineID then
                local clickEntry = entry
                local clickCharacterKey = character and character.key or nil
                row.hitbox:SetScript("OnClick", isCurrentCharacter(character) and function()
                    Addon.Professions:Open(clickEntry, clickCharacterKey)
                end or nil)
            end
        end
        ScrollFrames:Refresh(self.professionsCard.scroll)
    end

    -- Activate navigation only after the complete screen and Refresh method exist.
    -- This prevents a failed/early selection from leaving an orphaned visible frame.
    frame.navigation:SetOnSelect(function(subTabKey)
        Addon.Database:GetUI().selectedSubTabs.systems = subTabKey
        frame:Refresh()
    end)
    frame.navigation:SetDefinitions(SUB_TABS)
    frame.subTabButtons = frame.navigation.buttonsByKey

    Addon.StateStore:Subscribe("systems.professions", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("systems.cooldowns", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "systems",
    order = 4,
    label = function() return L.SCREEN_SYSTEMS end,
    Create = createSystemsScreen,
})
