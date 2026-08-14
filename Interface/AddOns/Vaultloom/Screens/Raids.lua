local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local RaidRows = Addon.RaidRows
local ScrollFrames = Addon.ScrollFrames

local function navigationLabel(definition)
    if type(definition.label) == "function" then
        local ok, label = pcall(definition.label)
        return ok and tostring(label or "") or ""
    end
    return tostring(definition.label or "")
end

local function navigationEntryVisible(definition)
    if type(definition.visible) ~= "function" then return true end
    local ok, visible = pcall(definition.visible)
    return ok and visible == true
end

local function createHorizontalNavigation(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(24)

    local view = {
        frame = bar,
        orientation = "horizontal",
        definitions = {},
        entries = {},
        buttonsByKey = {},
        labelsByKey = {},
        visibleByKey = {},
    }

    function view:SetOnSelect(callback)
        self.onSelect = callback
    end

    function view:SetDefinitions(definitions)
        for _, button in ipairs(self.entries) do button:Hide() end
        self.definitions = definitions or {}
        self.entries = {}
        self.buttonsByKey = {}
        self.labelsByKey = {}

        for _, definition in ipairs(self.definitions) do
            local button = Widgets:CreateButton(self.frame, "", 188, 24, "tab")
            button.definition = definition
            button.subTabKey = definition.key
            button:SetScript("OnClick", function(selfButton)
                if self.onSelect then
                    if self.selectedKey ~= selfButton.subTabKey and Addon.Sound then
                        Addon.Sound:Play("tabSwitch")
                    end
                    self.onSelect(selfButton.subTabKey)
                end
            end)
            self.entries[#self.entries + 1] = button
            self.buttonsByKey[definition.key] = button
        end
        self:Refresh()
    end

    function view:Refresh()
        local previous
        self.visibleByKey = {}
        for _, button in ipairs(self.entries) do
            local definition = button.definition
            local visible = navigationEntryVisible(definition)
            button:SetShown(visible)
            if visible then
                local label = navigationLabel(definition)
                button.label:SetText(label)
                self.labelsByKey[definition.key] = label
                self.visibleByKey[definition.key] = true
                button:ClearAllPoints()
                if previous then
                    button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
                else
                    button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
                end
                previous = button
            end
        end
        self:SetSelected(self.selectedKey)
    end

    function view:SetSelected(key)
        self.selectedKey = key
        for buttonKey, button in pairs(self.buttonsByKey) do
            Widgets:SetButtonActive(button, buttonKey == key and self.visibleByKey[buttonKey] == true)
        end
    end

    function view:IsVisible(key)
        return self.visibleByKey[key] == true
    end

    function view:GetLabel(key)
        return self.labelsByKey[key]
    end

    return view
end

local function setScrollable(scroll, amount)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local nextValue = self:GetVerticalScroll() - (delta * amount)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), nextValue)))
    end)
end

local function createScroll(parent, topAnchor, rightInset)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -(rightInset or 26), 12)
    setScrollable(scroll, 58)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(10, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, width)
        child:SetWidth(math.max(10, (tonumber(width) or self:GetWidth() or 10) - 2))
    end)
    ScrollFrames:Style(scroll)
    return scroll, child
end

local function difficultyLabel(data, key)
    for _, definition in ipairs(data.difficultyOptions) do
        if definition.key == key then
            local localized = definition.labelKey and L[definition.labelKey] or nil
            local difficultyID = data.difficultyIDs and data.difficultyIDs[key]
            if type(GetDifficultyInfo) == "function" and difficultyID then
                local ok, name = pcall(GetDifficultyInfo, difficultyID)
                if ok and type(name) == "string" and name ~= "" then return name end
            end
            return localized or definition.label or tostring(key or L.UNKNOWN)
        end
    end
    return L.UNKNOWN
end

local function createJournalScreen(config, host)
    local data = config.data
    local service = config.getService()
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame:Hide()
    frame.layoutVersion = config.layoutVersion
    frame.raidRows = {}
    frame.bossRows = {}
    frame.lootRows = {}

    frame.navigation = createHorizontalNavigation(frame)
    frame.navigation.frame:SetPoint("TOPLEFT", 0, 0)
    frame.navigation.frame:SetPoint("TOPRIGHT", 0, 0)

    frame.contentHost = CreateFrame("Frame", nil, frame)
    frame.contentHost:SetPoint("TOPLEFT", frame.navigation.frame, "BOTTOMLEFT", 0, -10)
    frame.contentHost:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.raidPanel = Widgets:CreatePanel(frame.contentHost, "cardInset")
    frame.raidPanel:SetPoint("TOPLEFT", 0, 0)
    frame.raidPanel:SetPoint("BOTTOMLEFT", 0, 0)
    frame.raidPanel:SetWidth(252)
    frame.raidPanel.title = Widgets:CreateLabel(frame.raidPanel, "GameFontNormalLarge", "LEFT")
    frame.raidPanel.title:SetPoint("TOPLEFT", 14, -14)
    frame.raidPanel.title:SetText(config.primaryPlural())
    frame.raidPanel.subtitle = Widgets:CreateLabel(frame.raidPanel, "GameFontHighlightSmall", "LEFT")
    frame.raidPanel.subtitle:SetPoint("TOPLEFT", frame.raidPanel.title, "BOTTOMLEFT", 0, -7)
    frame.raidPanel.subtitle:SetPoint("TOPRIGHT", -14, 0)
    frame.raidPanel.subtitle:SetText(config.defaultListSubtitle())
    frame.raidPanel.scroll, frame.raidPanel.scrollChild = createScroll(frame.raidPanel, frame.raidPanel.subtitle)
    frame.raidPanel.empty = Widgets:CreateLabel(frame.raidPanel.scrollChild, "GameFontDisable", "LEFT")
    frame.raidPanel.empty:SetPoint("TOPLEFT", 4, -4)
    frame.raidPanel.empty:SetPoint("TOPRIGHT", -4, -4)
    frame.raidPanel.empty:SetText(config.unavailable())

    frame.bossPanel = Widgets:CreatePanel(frame.contentHost, "cardInset")
    frame.bossPanel:SetPoint("TOPLEFT", frame.raidPanel, "TOPRIGHT", 12, 0)
    frame.bossPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.bossPanel.title = Widgets:CreateLabel(frame.bossPanel, "GameFontNormalLarge", "LEFT")
    frame.bossPanel.title:SetPoint("TOPLEFT", 14, -14)
    frame.bossPanel.title:SetText(L.RAID_JOURNAL_BOSSES)
    frame.bossPanel.subtitle = Widgets:CreateLabel(frame.bossPanel, "GameFontHighlightSmall", "LEFT")
    frame.bossPanel.subtitle:SetPoint("TOPLEFT", frame.bossPanel.title, "BOTTOMLEFT", 0, -7)
    frame.bossPanel.subtitle:SetPoint("TOPRIGHT", -14, 0)
    frame.bossPanel.subtitle:SetText(L.RAID_JOURNAL_BOSSLIST_SUBTITLE)
    frame.bossPanel.scroll, frame.bossPanel.scrollChild = createScroll(frame.bossPanel, frame.bossPanel.subtitle)
    frame.bossPanel.empty = Widgets:CreateLabel(frame.bossPanel.scrollChild, "GameFontDisable", "LEFT")
    frame.bossPanel.empty:SetPoint("TOPLEFT", 4, -4)
    frame.bossPanel.empty:SetPoint("TOPRIGHT", -4, -4)

    local shellFrame = Addon.UI.frame
    frame.lootPanel = Widgets:CreatePanel(shellFrame.sidebar, "sidebar")
    frame.lootPanel:SetAllPoints(shellFrame.sidebar)
    frame.lootPanel:SetFrameLevel(shellFrame.sidebar:GetFrameLevel() + 10)
    frame.lootPanel:Hide()
    frame.lootPanel.title = Widgets:CreateLabel(frame.lootPanel, "GameFontNormalLarge", "LEFT")
    frame.lootPanel.title:SetPoint("TOPLEFT", 16, -16)
    frame.lootPanel.title:SetText(L.RAID_JOURNAL_LOOT)
    frame.lootPanel.difficultyButton = Widgets:CreateButton(frame.lootPanel, "", 236, 28)
    frame.lootPanel.difficultyButton:SetPoint("TOPLEFT", frame.lootPanel.title, "BOTTOMLEFT", 0, -14)
    frame.lootPanel.difficultyButton:SetPoint("TOPRIGHT", -16, -14)
    frame.lootPanel.classButton = Widgets:CreateButton(frame.lootPanel, "", 236, 28)
    frame.lootPanel.classButton:SetPoint("TOPLEFT", frame.lootPanel.difficultyButton, "BOTTOMLEFT", 0, -7)
    frame.lootPanel.classButton:SetPoint("TOPRIGHT", frame.lootPanel.difficultyButton, "BOTTOMRIGHT", 0, -7)

    local function hideMenus()
        frame.lootPanel.difficultyMenu:Hide()
        frame.lootPanel.classMenu:Hide()
    end

    frame.lootPanel.difficultyMenu = Widgets:CreatePanel(frame.lootPanel, "cardInset")
    frame.lootPanel.difficultyMenu:SetPoint("TOPLEFT", frame.lootPanel.difficultyButton, "BOTTOMLEFT", 0, -3)
    frame.lootPanel.difficultyMenu:SetPoint("TOPRIGHT", frame.lootPanel.difficultyButton, "BOTTOMRIGHT", 0, -3)
    frame.lootPanel.difficultyMenu:SetHeight(12 + (#data.difficultyOptions * 25))
    frame.lootPanel.difficultyMenu:SetFrameLevel(frame.lootPanel:GetFrameLevel() + 20)
    frame.lootPanel.difficultyMenu:Hide()
    frame.lootPanel.difficultyRows = {}
    for index, definition in ipairs(data.difficultyOptions) do
        local button = Widgets:CreateButton(frame.lootPanel.difficultyMenu, difficultyLabel(data, definition.key), 224, 23)
        button:SetPoint("TOPLEFT", 6, -6 - ((index - 1) * 25))
        button:SetPoint("TOPRIGHT", -6, -6 - ((index - 1) * 25))
        button.difficultyKey = definition.key
        button:SetScript("OnClick", function(self)
            service:SetDifficulty(self.difficultyKey)
            hideMenus()
        end)
        frame.lootPanel.difficultyRows[index] = button
    end

    frame.lootPanel.classMenu = Widgets:CreatePanel(frame.lootPanel, "cardInset")
    frame.lootPanel.classMenu:SetPoint("TOPLEFT", frame.lootPanel.classButton, "BOTTOMLEFT", 0, -3)
    frame.lootPanel.classMenu:SetPoint("TOPRIGHT", frame.lootPanel.classButton, "BOTTOMRIGHT", 0, -3)
    frame.lootPanel.classMenu:SetHeight(62)
    frame.lootPanel.classMenu:SetFrameLevel(frame.lootPanel:GetFrameLevel() + 21)
    frame.lootPanel.classMenu:Hide()
    frame.lootPanel.classRows = {}
    for index = 1, 2 do
        local button = Widgets:CreateButton(frame.lootPanel.classMenu, "", 224, 23)
        button:SetPoint("TOPLEFT", 6, -6 - ((index - 1) * 25))
        button:SetPoint("TOPRIGHT", -6, -6 - ((index - 1) * 25))
        button:SetScript("OnClick", function(self)
            service:SetClassFilter(self.classFilterKey)
            hideMenus()
        end)
        frame.lootPanel.classRows[index] = button
    end
    frame.lootPanel.difficultyButton:SetScript("OnClick", function()
        local show = not frame.lootPanel.difficultyMenu:IsShown()
        hideMenus()
        frame.lootPanel.difficultyMenu:SetShown(show)
    end)
    frame.lootPanel.classButton:SetScript("OnClick", function()
        local show = not frame.lootPanel.classMenu:IsShown()
        hideMenus()
        frame.lootPanel.classMenu:SetShown(show)
    end)

    frame.lootPanel.subtitle = Widgets:CreateLabel(frame.lootPanel, "GameFontHighlightSmall", "LEFT")
    frame.lootPanel.subtitle:SetPoint("TOPLEFT", frame.lootPanel.classButton, "BOTTOMLEFT", 0, -12)
    frame.lootPanel.subtitle:SetPoint("TOPRIGHT", -16, 0)
    frame.lootPanel.subtitle:SetWordWrap(true)
    frame.lootPanel.context = Widgets:CreateLabel(frame.lootPanel, "GameFontDisableSmall", "LEFT")
    frame.lootPanel.context:SetPoint("TOPLEFT", frame.lootPanel.subtitle, "BOTTOMLEFT", 0, -10)
    frame.lootPanel.context:SetPoint("TOPRIGHT", -16, 0)
    frame.lootPanel.scroll, frame.lootPanel.scrollChild = createScroll(frame.lootPanel, frame.lootPanel.context)
    frame.lootPanel.empty = Widgets:CreateLabel(frame.lootPanel.scrollChild, "GameFontDisable", "LEFT")
    frame.lootPanel.empty:SetPoint("TOPLEFT", 4, -4)
    frame.lootPanel.empty:SetPoint("TOPRIGHT", -4, -4)
    frame.lootPanel.empty:SetText(L.RAID_JOURNAL_NO_LOOT)

    frame.detailPanel = Widgets:CreatePanel(shellFrame.utility, "utility")
    frame.detailPanel:SetAllPoints(shellFrame.utility)
    frame.detailPanel:SetFrameLevel(shellFrame.utility:GetFrameLevel() + 10)
    frame.detailPanel:Hide()
    frame.detailPanel.title = Widgets:CreateLabel(frame.detailPanel, "GameFontNormalLarge", "LEFT")
    frame.detailPanel.title:SetPoint("TOPLEFT", 16, -16)
    frame.detailPanel.title:SetText(L.RAID_JOURNAL_DETAILS)
    frame.detailPanel.subtitle = Widgets:CreateLabel(frame.detailPanel, "GameFontHighlightSmall", "LEFT")
    frame.detailPanel.subtitle:SetPoint("TOPLEFT", frame.detailPanel.title, "BOTTOMLEFT", 0, -8)
    frame.detailPanel.subtitle:SetPoint("TOPRIGHT", -16, 0)
    frame.detailPanel.subtitle:SetText(config.detailSubtitle())
    frame.detailPanel.summary = Widgets:CreatePanel(frame.detailPanel, "cardInset")
    frame.detailPanel.summary:SetPoint("TOPLEFT", frame.detailPanel.subtitle, "BOTTOMLEFT", 0, -14)
    frame.detailPanel.summary:SetPoint("TOPRIGHT", -16, -14)
    frame.detailPanel.summary:SetHeight(150)
    local summaryDefinitions = {
        { key = "raid", label = config.primarySingular() },
        { key = "progress", label = L.RAID_JOURNAL_PROGRESS },
        { key = "status", label = L.RAID_JOURNAL_STATUS_LABEL },
        { key = "filter", label = L.RAID_JOURNAL_FILTERS },
        { key = "character", label = L.RAID_JOURNAL_CHARACTER },
    }
    frame.detailPanel.summaryRows = {}
    for index, definition in ipairs(summaryDefinitions) do
        local label = Widgets:CreateLabel(frame.detailPanel.summary, "GameFontDisableSmall", "LEFT")
        label:SetPoint("TOPLEFT", 14, -12 - ((index - 1) * 26))
        label:SetText(definition.label)
        local value = Widgets:CreateLabel(frame.detailPanel.summary, "GameFontHighlightSmall", "RIGHT")
        value:SetPoint("TOPLEFT", 102, -12 - ((index - 1) * 26))
        value:SetPoint("TOPRIGHT", -14, -12 - ((index - 1) * 26))
        frame.detailPanel.summaryRows[definition.key] = value
    end
    frame.detailPanel.detail = Widgets:CreatePanel(frame.detailPanel, "cardInset")
    frame.detailPanel.detail:SetPoint("TOPLEFT", frame.detailPanel.summary, "BOTTOMLEFT", 0, -14)
    frame.detailPanel.detail:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.detailPanel.detailTitle = Widgets:CreateLabel(frame.detailPanel.detail, "GameFontHighlight", "LEFT")
    frame.detailPanel.detailTitle:SetPoint("TOPLEFT", 14, -13)
    frame.detailPanel.detailTitle:SetPoint("TOPRIGHT", -14, -13)
    frame.detailPanel.detailStatus = Widgets:CreateLabel(frame.detailPanel.detail, "GameFontDisableSmall", "LEFT")
    frame.detailPanel.detailStatus:SetPoint("TOPLEFT", frame.detailPanel.detailTitle, "BOTTOMLEFT", 0, -8)
    frame.detailPanel.detailStatus:SetPoint("TOPRIGHT", -14, 0)
    frame.detailPanel.detailText = Widgets:CreateLabel(frame.detailPanel.detail, "GameFontHighlightSmall", "LEFT")
    frame.detailPanel.detailText:SetPoint("TOPLEFT", frame.detailPanel.detailStatus, "BOTTOMLEFT", 0, -12)
    frame.detailPanel.detailText:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.detailPanel.detailText:SetJustifyV("TOP")
    frame.detailPanel.detailText:SetWordWrap(true)

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
        self.lootPanel:SetShown(visible)
        self.detailPanel:SetShown(visible)
        if not visible then
            hideMenus()
            service:Close()
        end
    end

    local function ensureSelectionRows(pool, parent, count, onClick)
        while #pool < count do
            local previous = pool[#pool]
            local row = RaidRows:CreateSelectionRow(parent, previous)
            row:SetScript("OnClick", function(self) onClick(self) end)
            pool[#pool + 1] = row
        end
    end

    local function ensureLootRows(count)
        while #frame.lootRows < count do
            frame.lootRows[#frame.lootRows + 1] = RaidRows:CreateLootRow(frame.lootPanel.scrollChild, frame.lootRows[#frame.lootRows])
        end
    end

    function frame:Refresh()
        if self.chromeVisible ~= false then service:Open() end
        self.navigation:Refresh()
        local character = Addon.WarbandRoster:GetSelected()
        local view = character and service:GetView(character.key) or {}
        self.navigation:SetSelected(view.subTabKey or config.defaultSubTab)
        self.raidPanel.subtitle:SetText(view.listSubtitle or config.defaultListSubtitle())
        local raids = view.raids or {}
        local bosses = view.selectedRaid and view.selectedRaid.bosses or {}
        local loot = view.loot or {}

        self.lootPanel.difficultyButton.label:SetText(string.format(L.RAID_JOURNAL_DIFFICULTY_FILTER, difficultyLabel(data, view.difficultyKey)))
        self.lootPanel.classButton.label:SetText(string.format(L.RAID_JOURNAL_CLASS_FILTER, view.classFilterName or L.UNKNOWN))
        for _, button in ipairs(self.lootPanel.difficultyRows) do
            Widgets:SetButtonActive(button, button.difficultyKey == view.difficultyKey)
        end
        self.lootPanel.classRows[1].classFilterKey = "player"
        self.lootPanel.classRows[1].label:SetText(character and character.className or L.UNKNOWN)
        self.lootPanel.classRows[2].classFilterKey = "all"
        self.lootPanel.classRows[2].label:SetText(L.RAID_JOURNAL_ALL_CLASSES)
        Widgets:SetButtonActive(self.lootPanel.classRows[1], view.classFilterKey == "player")
        Widgets:SetButtonActive(self.lootPanel.classRows[2], view.classFilterKey == "all")
        self.lootPanel.subtitle:SetText(view.selectedBoss
            and string.format(L.RAID_JOURNAL_LOOT_PANEL_SUBTITLE, view.selectedBoss.name, difficultyLabel(data, view.difficultyKey))
            or L.RAID_JOURNAL_LOOT_INFO_PLAYER)
        self.lootPanel.context:SetText(string.format(
            L.RAID_JOURNAL_LOOT_CONTEXT, #loot, view.selectedRaid and view.selectedRaid.name or config.primaryPlural()
        ))

        ensureLootRows(#loot)
        local lootSource = {
            mainTabKey = config.screenID,
            subTabKey = view.subTabKey or config.defaultSubTab,
            raidKey = view.selectedRaid and view.selectedRaid.key or nil,
            bossKey = view.selectedBoss and view.selectedBoss.key or nil,
            instanceID = view.selectedRaid and view.selectedRaid.instanceID or nil,
            encounterID = view.selectedBoss and view.selectedBoss.encounterID or nil,
            instanceName = view.selectedRaid and view.selectedRaid.name or nil,
            bossName = view.selectedBoss and view.selectedBoss.name or nil,
        }
        for index, row in ipairs(self.lootRows) do
            RaidRows:SetLootRow(row, loot[index], character, view.difficultyKey, service, lootSource)
        end
        self.lootPanel.scrollChild:SetHeight(math.max(10, (#loot * 66) - 6))
        self.lootPanel.empty:SetShown(#loot == 0)

        ensureSelectionRows(self.raidRows, self.raidPanel.scrollChild, #raids, function(row)
            service:SetSelection(row.raidKey, row.defaultBossKey or "")
        end)
        for index, row in ipairs(self.raidRows) do
            local raid = raids[index]
            if raid then
                row.raidKey = raid.key
                row.defaultBossKey = raid.bosses and raid.bosses[1] and raid.bosses[1].key or ""
                local repeatable = raid.counterMode == "repeatable"
                local status = repeatable and "repeatable"
                    or raid.totalCount > 0 and raid.killedCount >= raid.totalCount and "complete"
                    or raid.killedCount > 0 and "partial" or "open"
                local typeLabel = not config.isDungeon and raid.contentType == "lair"
                    and L.RAID_JOURNAL_TYPE_LAIR or nil
                RaidRows:SetSelectionRow(row, {
                    title = raid.name,
                    meta = typeLabel or (raid.totalCount == 0 and L.RAID_JOURNAL_SOURCE_EJ or ""),
                    value = repeatable and L.DUNGEON_JOURNAL_REPEATABLE or raid.progressText,
                    valuePlacement = "stacked",
                    status = status,
                    colorKey = config.isDungeon and not repeatable and status == "open" and "dailyOpen" or status,
                    icon = raid.icon,
                    iconTexCoord = (view.subTabKey or config.defaultSubTab) == "midnight"
                        and data.midnightIconTexCoord or nil,
                    selected = raid.key == view.selectedRaidKey,
                })
            else
                RaidRows:SetSelectionRow(row, nil)
            end
        end
        self.raidPanel.scrollChild:SetHeight(RaidRows:GetSelectionListHeight(self.raidRows))
        self.raidPanel.empty:SetShown(#raids == 0)

        ensureSelectionRows(self.bossRows, self.bossPanel.scrollChild, #bosses, function(row)
            service:SetSelection(row.raidKey, row.bossKey)
        end)
        for index, row in ipairs(self.bossRows) do
            local boss = bosses[index]
            if boss then
                row.raidKey = view.selectedRaidKey
                row.bossKey = boss.key
                local repeatable = boss.status == "repeatable"
                local bossValue = repeatable and L.DUNGEON_JOURNAL_REPEATABLE
                    or config.isDungeon and boss.killed and L.DUNGEON_JOURNAL_CARD_STATUS_KILLED
                    or config.isDungeon and L.DUNGEON_JOURNAL_CARD_STATUS_OPEN
                    or boss.killed and L.RAID_JOURNAL_CARD_STATUS_KILLED
                    or L.RAID_JOURNAL_CARD_STATUS_OPEN
                local status = repeatable and "repeatable" or boss.status
                RaidRows:SetSelectionRow(row, {
                    title = boss.name,
                    meta = boss.description ~= "" and boss.description or L.RAID_JOURNAL_SOURCE_EJ,
                    value = bossValue,
                    valuePlacement = "top",
                    status = status,
                    colorKey = config.isDungeon and not repeatable and status == "open" and "dailyOpen" or status,
                    icon = boss.icon,
                    selected = boss.key == view.selectedBossKey,
                })
            else
                RaidRows:SetSelectionRow(row, nil)
            end
        end
        self.bossPanel.scrollChild:SetHeight(RaidRows:GetSelectionListHeight(self.bossRows))
        self.bossPanel.empty:SetShown(#bosses == 0)
        self.bossPanel.empty:SetText(view.source == "fallback" and config.unavailable() or L.RAID_JOURNAL_BOSSLIST_SUBTITLE)
        local repeatable = view.counterMode == "repeatable"
        self.bossPanel.subtitle:SetText(repeatable and L.DUNGEON_JOURNAL_REPEATABLE_SUBTITLE
            or view.selectedRaid and view.selectedRaid.totalCount > 0
                and string.format(config.isDungeon and L.DUNGEON_JOURNAL_BOSS_PROGRESS or L.RAID_JOURNAL_BOSS_PROGRESS, view.selectedRaid.progressText)
            or L.RAID_JOURNAL_BOSSLIST_SUBTITLE)

        local statusText = repeatable and L.DUNGEON_JOURNAL_REPEATABLE
            or view.selectedBoss and config.isDungeon and (view.selectedBoss.killed and L.DUNGEON_JOURNAL_STATUS_KILLED or L.DUNGEON_JOURNAL_STATUS_OPEN)
            or view.selectedBoss and (view.selectedBoss.killed and L.RAID_JOURNAL_STATUS_KILLED or L.RAID_JOURNAL_STATUS_OPEN)
            or L.RAID_JOURNAL_STATUS_PENDING
        self.detailPanel.summaryRows.raid:SetText(view.selectedRaid and view.selectedRaid.name or config.primaryPlural())
        self.detailPanel.summaryRows.progress:SetText(repeatable and L.DUNGEON_JOURNAL_REPEATABLE or (view.selectedRaid and view.selectedRaid.progressText or "--"))
        self.detailPanel.summaryRows.status:SetText(statusText)
        self.detailPanel.summaryRows.filter:SetText(string.format("%s | %s", difficultyLabel(data, view.difficultyKey), view.classFilterName or L.UNKNOWN))
        self.detailPanel.summaryRows.character:SetText(character and character.name or L.UNKNOWN)
        self.detailPanel.detailTitle:SetText(view.selectedBoss and view.selectedBoss.name or L.RAID_JOURNAL_DETAILS)
        self.detailPanel.detailStatus:SetText(repeatable and L.DUNGEON_JOURNAL_REPEATABLE_SUBTITLE
            or string.format(config.isDungeon and L.DUNGEON_JOURNAL_RESET or L.RAID_JOURNAL_RESET, view.resetText or "--"))
        self.detailPanel.detailText:SetText(view.selectedBoss and view.selectedBoss.description ~= ""
            and view.selectedBoss.description
            or (view.selectedRaid and view.selectedRaid.description ~= "" and view.selectedRaid.description)
            or L.RAID_JOURNAL_UNAVAILABLE)
    end

    frame.navigation:SetOnSelect(function(subTabKey)
        service:SetSubTab(subTabKey)
    end)
    frame.navigation:SetDefinitions(config.subTabs)
    frame.subTabButtons = frame.navigation.buttonsByKey
    frame:SetScript("OnHide", function()
        frame:SetChromeVisible(false)
    end)
    frame:SetScript("OnShow", function()
        if not frame.chromeVisible then
            frame:SetChromeVisible(true)
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe(config.stateID, frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    return frame
end

Addon.JournalScreen = {
    Create = createJournalScreen,
}

Addon.ScreenRegistry:Register({
    id = "raids",
    order = 5,
    label = function() return L.SCREEN_RAIDS end,
    Create = function(_, host)
        return createJournalScreen({
            screenID = "raids",
            stateID = "raids.journal",
            layoutVersion = "journal-raids-6",
            data = Addon.Data.RAIDS,
            defaultSubTab = "midnight",
            subTabs = {
                { key = "midnight", label = function() return L.RAIDS_TAB_MIDNIGHT end },
            },
            getService = function() return Addon.RaidJournal end,
            primarySingular = function() return L.RAID_JOURNAL_PRIMARY_LABEL end,
            primaryPlural = function() return L.SCREEN_RAIDS end,
            defaultListSubtitle = function() return L.RAID_JOURNAL_MIDNIGHT_SUBTITLE end,
            detailSubtitle = function() return L.RAID_JOURNAL_DETAILS_SUBTITLE end,
            unavailable = function() return L.RAID_JOURNAL_UNAVAILABLE end,
            isDungeon = false,
        }, host)
    end,
})
