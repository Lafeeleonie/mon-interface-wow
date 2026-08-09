local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Assets = Addon.Assets
local Widgets = Addon.Widgets
local VerticalNavigation = Addon.VerticalNavigation
local ScrollFrames = Addon.ScrollFrames
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function isDarkmoonActive()
    local state = Addon.StateStore:Get("pve.darkmoon")
    if state == true then
        return true
    end
    return type(state) == "table" and (state.active == true
        or (type(state.snapshot) == "table" and state.snapshot.active == true))
end

local SUB_TABS = {
    { key = "weekly", label = function() return L.PVE_TAB_WEEKLY end },
    { key = "void_invasion", label = function() return L.PVE_TAB_VOID_INVASION end },
    { key = "daily", label = function() return L.PVE_TAB_DAILY end },
    { key = "events", label = function() return L.PVE_TAB_EVENTS end },
    { key = "delves", label = function() return L.PVE_TAB_DELVES end },
    { key = "prey", label = function() return L.PVE_TAB_PREY end },
    { key = "rares", label = function() return L.PVE_TAB_RARES end },
    { key = "world", label = function() return L.PVE_TAB_WORLD end },
    {
        key = "special-heading",
        heading = true,
        label = function() return L.PVE_TAB_SPECIAL end,
        visible = isDarkmoonActive,
    },
    {
        key = "darkmoon",
        label = function() return L.PVE_TAB_DARKMOON end,
        visible = isDarkmoonActive,
    },
}

local STATUS = {
    complete = { color = { 0.34, 0.88, 0.48, 1 }, texture = function() return Assets.statusBadgeComplete end },
    turnin = { color = { 0.98, 0.76, 0.22, 1 }, texture = function() return Assets.statusBadgeTurnIn end },
    open = { color = Theme.colors.gold, texture = function() return Assets.statusBadgeOpen end },
    daily = { color = Theme.colors.cyan, texture = function() return Assets.statusBadgeOpen end },
    missing = { color = { 0.62, 0.59, 0.54, 1 }, texture = function() return Assets.statusBadgeMissing end },
    locked = { color = { 0.42, 0.40, 0.38, 1 }, texture = function() return Assets.statusBadgeLocked end },
    failed = { color = { 0.92, 0.30, 0.24, 1 }, texture = function() return Assets.statusBadgeFailed end },
}

local function createStatusRow(parent, index, previous)
    local row = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(42)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.88)
    row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
    else
        row:SetPoint("TOPLEFT", parent.summary, "BOTTOMLEFT", 0, -16)
        row:SetPoint("TOPRIGHT", -16, 0)
    end

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    row.background:SetTexture(Assets.row)

    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -4)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 4)
    row.statusLine:SetWidth(3)

    row.label = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.label:SetPoint("LEFT", 16, 0)
    row.label:SetPoint("RIGHT", -132, 0)

    row.badgeFrame = row:CreateTexture(nil, "ARTWORK")
    row.badgeFrame:SetSize(26, 26)
    row.badgeFrame:SetPoint("RIGHT", -10, 0)
    row.badgeFrame:SetTexture(Assets.statusBadgeFrame)

    row.badge = row:CreateTexture(nil, "OVERLAY")
    row.badge:SetSize(24, 24)
    row.badge:SetPoint("CENTER", row.badgeFrame, "CENTER", 0, 0)

    row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.value:SetPoint("RIGHT", row.badgeFrame, "LEFT", -8, 0)
    row.value:SetWidth(90)

    row.hitbox = CreateFrame("Button", nil, row)
    row.hitbox:SetAllPoints(row)
    row.hitbox:RegisterForClicks("LeftButtonUp")
    row.hitbox:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" or not row.questID or not Addon.QuestApi then
            return
        end
        if Addon.QuestApi:OpenQuest(row.questID) and GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row.hitbox:SetScript("OnEnter", function()
        row:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.85)
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
        row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row.index = index
    return row
end

local function setStatusRow(row, entry, dailyOpen)
    if not entry then
        row.tooltipTitle = nil
        row.tooltipLines = nil
        row.questID = nil
        row:Hide()
        return
    end
    local visualKey = entry.status == "open" and (dailyOpen == true or entry.resetType == "daily")
        and "daily" or entry.status
    local visual = STATUS[visualKey] or STATUS.missing
    row.label:SetText(entry.label or "")
    row.value:SetText(entry.text or "")
    row.value:SetTextColor(visual.color[1], visual.color[2], visual.color[3], 1)
    row.statusLine:SetColorTexture(visual.color[1], visual.color[2], visual.color[3], 0.95)
    row.badge:ClearAllPoints()
    row.badge:SetPoint("CENTER", row.badgeFrame, "CENTER", 0, 0)
    if entry.key == "saltherils_favor" then
        row.badgeFrame:Hide()
        row.badge:SetSize(26, 26)
        row.badge:SetTexture(Assets.statusBadgeSaltherilFavor)
    else
        row.badgeFrame:Show()
        row.badge:SetSize(24, 24)
        row.badge:SetTexture(visual.texture())
    end
    row.tooltipTitle = entry.tooltipTitle or entry.label
    row.tooltipLines = entry.tooltipLines
    row.questID = tonumber(entry.questID)
    row:Show()
end

local function createRareRow(parent)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(34)
    row:RegisterForClicks("LeftButtonUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.88)
    row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    row.background:SetTexture(Assets.row)

    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -4)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 4)
    row.statusLine:SetWidth(2)

    row.badge = row:CreateTexture(nil, "ARTWORK")
    row.badge:SetSize(22, 22)
    row.badge:SetPoint("LEFT", 13, 0)

    row.name = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("LEFT", row.badge, "RIGHT", 10, 0)

    row.status = Widgets:CreateLabel(row, "GameFontDisableSmall", "RIGHT")
    row.status:SetPoint("RIGHT", -14, 0)
    row.status:SetWidth(82)
    row.name:SetPoint("RIGHT", row.status, "LEFT", -12, 0)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.85)
        if self.rare and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(self.rare.name or "", Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            for _, line in ipairs(self.rare.tooltipLines or {}) do
                GameTooltip:AddLine(line, 0.92, 0.92, 0.92, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", function(self)
        if self.rare then
            Addon.PveRares:SetWaypoint(self.rare)
        end
    end)
    return row
end

local function setRareRow(row, rare)
    if not rare then
        row.rare = nil
        row:Hide()
        return
    end
    local visual = STATUS[rare.status] or STATUS.open
    row.rare = rare
    row.name:SetText(rare.name or rare.label or "")
    row.status:SetText(rare.text or "")
    row.status:SetTextColor(visual.color[1], visual.color[2], visual.color[3], 1)
    row.statusLine:SetColorTexture(visual.color[1], visual.color[2], visual.color[3], 0.95)
    row.badge:SetTexture(visual.texture())
    row:Show()
end

local function createMountSlot(parent)
    local slot = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    slot:SetHeight(46)
    slot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    slot:SetBackdropColor(0.025, 0.022, 0.020, 0.82)
    slot:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.45)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(31, 31)
    slot.icon:SetPoint("LEFT", 10, 0)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.name = Widgets:CreateLabel(slot, "GameFontHighlightSmall", "LEFT")
    slot.name:SetPoint("LEFT", slot.icon, "RIGHT", 8, 7)
    slot.name:SetPoint("RIGHT", -12, 7)

    slot.status = Widgets:CreateLabel(slot, "GameFontDisableSmall", "LEFT")
    slot.status:SetPoint("LEFT", slot.icon, "RIGHT", 8, -10)
    slot.status:SetPoint("RIGHT", -12, -10)

    slot:SetScript("OnEnter", function(self)
        if not self.mount or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        if type(GameTooltip.SetItemByID) == "function" and self.mount.itemID then
            GameTooltip:SetItemByID(self.mount.itemID)
        else
            GameTooltip:AddLine(self.mount.name or "", Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            GameTooltip:AddLine(self.mount.text or "", 0.92, 0.92, 0.92, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return slot
end

local function setMountSlot(slot, mount)
    if not mount then
        slot.mount = nil
        slot:Hide()
        return
    end
    local visual = STATUS[mount.status] or STATUS.missing
    slot.mount = mount
    slot.icon:SetTexture(mount.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    slot.name:SetText(mount.name or "")
    slot.status:SetText(mount.text or "")
    slot.status:SetTextColor(visual.color[1], visual.color[2], visual.color[3], 1)
    slot:Show()
end

local function createPveScreen(_, host)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.weeklyRows = {}
    frame.voidInvasionRows = {}
    frame.dailyRows = {}
    frame.eventRows = {}
    frame.delveRows = {}
    frame.preyRows = {}
    frame.rareRows = {}
    frame.worldRows = {}
    frame.darkmoonRows = {}
    frame.layoutVersion = "vertical-pve-1"

    local domainIDs = {
        "pve.weekly",
        "pve.void_invasion",
        "pve.daily",
        "pve.events",
        "pve.delves",
        "pve.prey",
        "pve.rares",
        "pve.world",
        "pve.darkmoon",
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
    frame.navigation:SetOnSelect(function(subTabKey)
        Addon.Database:GetUI().selectedSubTabs.pve = subTabKey
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
    frame.weeklyCard.summary:SetPoint("TOPLEFT", 16, -18)

    frame.weeklyCard.reset = Widgets:CreateLabel(frame.weeklyCard, "GameFontHighlightSmall", "LEFT")
    frame.weeklyCard.reset:SetPoint("LEFT", frame.weeklyCard.summary, "RIGHT", 28, 0)

    local previous
    for index = 1, 5 do
        local row = createStatusRow(frame.weeklyCard, index, previous)
        frame.weeklyRows[index] = row
        previous = row
    end

    frame.voidInvasionCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.voidInvasionCard:SetAllPoints(frame.contentHost)

    frame.voidInvasionCard.summary = Widgets:CreateLabel(frame.voidInvasionCard, "GameFontHighlightSmall", "LEFT")
    frame.voidInvasionCard.summary:SetPoint("TOPLEFT", 16, -18)

    frame.voidInvasionCard.reset = Widgets:CreateLabel(frame.voidInvasionCard, "GameFontHighlightSmall", "RIGHT")
    frame.voidInvasionCard.reset:SetPoint("TOPRIGHT", -16, -18)
    frame.voidInvasionCard.summary:SetPoint("RIGHT", frame.voidInvasionCard.reset, "LEFT", -20, 0)

    frame.voidInvasionCard.normalButton = Widgets:CreateButton(
        frame.voidInvasionCard,
        L.PVE_VOID_INVASION_DIFFICULTY_NORMAL,
        144,
        30,
        "tab"
    )
    frame.voidInvasionCard.normalButton:SetPoint("TOPRIGHT", frame.voidInvasionCard, "TOP", -4, -47)
    frame.voidInvasionCard.normalButton:RegisterForClicks("LeftButtonDown")
    frame.voidInvasionCard.heroicButton = Widgets:CreateButton(
        frame.voidInvasionCard,
        L.PVE_VOID_INVASION_DIFFICULTY_HEROIC,
        144,
        30,
        "tab"
    )
    frame.voidInvasionCard.heroicButton:SetPoint("TOPLEFT", frame.voidInvasionCard, "TOP", 4, -47)
    frame.voidInvasionCard.heroicButton:RegisterForClicks("LeftButtonDown")

    local function selectVoidInvasionDifficulty(difficulty)
        local character = Addon.WarbandRoster:GetSelected()
        if character and Addon.PveVoidInvasion:SetPreferredDifficulty(character.key, difficulty) then
            frame:Refresh()
        end
    end
    frame.voidInvasionCard.normalButton:SetScript("OnClick", function()
        selectVoidInvasionDifficulty("normal")
    end)
    frame.voidInvasionCard.heroicButton:SetScript("OnClick", function()
        selectVoidInvasionDifficulty("heroic")
    end)

    previous = nil
    for index = 1, 4 do
        local row = createStatusRow(frame.voidInvasionCard, index, previous)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.voidInvasionCard, "TOPLEFT", 16, -92)
            row:SetPoint("TOPRIGHT", frame.voidInvasionCard, "TOPRIGHT", -16, -92)
        end
        frame.voidInvasionRows[index] = row
        previous = row
    end

    frame.dailyCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.dailyCard:SetAllPoints(frame.contentHost)

    frame.dailyCard.summary = Widgets:CreateLabel(frame.dailyCard, "GameFontHighlightSmall", "LEFT")
    frame.dailyCard.summary:SetPoint("TOPLEFT", 16, -18)

    frame.dailyCard.reset = Widgets:CreateLabel(frame.dailyCard, "GameFontHighlightSmall", "LEFT")
    frame.dailyCard.reset:SetPoint("LEFT", frame.dailyCard.summary, "RIGHT", 28, 0)

    previous = nil
    for index = 1, 3 do
        local row = createStatusRow(frame.dailyCard, index, previous)
        frame.dailyRows[index] = row
        previous = row
    end

    frame.eventsCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.eventsCard:SetAllPoints(frame.contentHost)

    frame.eventsCard.summary = Widgets:CreateLabel(frame.eventsCard, "GameFontHighlightSmall", "LEFT")
    frame.eventsCard.summary:SetPoint("TOPLEFT", 16, -18)

    frame.eventsCard.reset = Widgets:CreateLabel(frame.eventsCard, "GameFontHighlightSmall", "LEFT")
    frame.eventsCard.reset:SetPoint("LEFT", frame.eventsCard.summary, "RIGHT", 28, 0)

    previous = nil
    for index = 1, 7 do
        local row = createStatusRow(frame.eventsCard, index, previous)
        frame.eventRows[index] = row
        previous = row
    end

    frame.delvesCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.delvesCard:SetAllPoints(frame.contentHost)

    frame.delvesCard.summary = Widgets:CreateLabel(frame.delvesCard, "GameFontHighlightSmall", "LEFT")
    frame.delvesCard.summary:SetPoint("TOPLEFT", 16, -18)

    frame.delvesCard.reset = Widgets:CreateLabel(frame.delvesCard, "GameFontHighlightSmall", "LEFT")
    frame.delvesCard.reset:SetPoint("LEFT", frame.delvesCard.summary, "RIGHT", 28, 0)

    previous = nil
    for index = 1, 4 do
        local row = createStatusRow(frame.delvesCard, index, previous)
        frame.delveRows[index] = row
        previous = row
    end

    frame.preyCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.preyCard:SetAllPoints(frame.contentHost)

    frame.preyCard.totalLabel = Widgets:CreateLabel(frame.preyCard, "GameFontHighlightSmall", "LEFT")
    frame.preyCard.totalLabel:SetPoint("TOPLEFT", 16, -18)
    frame.preyCard.totalLabel:SetPoint("TOPRIGHT", -16, -18)

    frame.preyCard.totalValue = Widgets:CreateLabel(frame.preyCard, "GameFontHighlight", "RIGHT")
    frame.preyCard.totalValue:SetPoint("TOPRIGHT", -16, -18)

    frame.preyCard.totalBar = Widgets:CreateProgressBar(frame.preyCard)
    frame.preyCard.totalBar:SetPoint("TOPLEFT", frame.preyCard.totalLabel, "BOTTOMLEFT", 0, -8)
    frame.preyCard.totalBar:SetPoint("TOPRIGHT", frame.preyCard.totalLabel, "BOTTOMRIGHT", 0, -8)
    frame.preyCard.totalBar:SetHeight(14)

    local difficultyDefinitions = {
        { key = "normal", label = L.PVE_PREY_NORMAL, color = { 0.58, 0.82, 0.72, 1 } },
        { key = "hard", label = L.PVE_PREY_HARD, color = { 0.82, 0.66, 0.34, 1 } },
        { key = "nightmare", label = L.PVE_PREY_NIGHTMARE, color = { 0.82, 0.34, 0.38, 1 } },
    }
    local previousBar = frame.preyCard.totalBar
    frame.preyCard.difficulties = {}
    for _, definition in ipairs(difficultyDefinitions) do
        local difficulty = {
            key = definition.key,
            color = definition.color,
        }
        difficulty.label = Widgets:CreateLabel(frame.preyCard, "GameFontHighlightSmall", "LEFT")
        difficulty.label:SetPoint("TOPLEFT", previousBar, "BOTTOMLEFT", 0, -18)
        difficulty.label:SetPoint("TOPRIGHT", previousBar, "BOTTOMRIGHT", 0, -18)
        difficulty.label:SetText(definition.label)
        difficulty.value = Widgets:CreateLabel(frame.preyCard, "GameFontHighlight", "RIGHT")
        difficulty.value:SetPoint("RIGHT", -16, 0)
        difficulty.value:SetPoint("CENTER", difficulty.label, "CENTER", 0, 0)
        difficulty.bar = Widgets:CreateProgressBar(frame.preyCard)
        difficulty.bar:SetPoint("TOPLEFT", difficulty.label, "BOTTOMLEFT", 0, -8)
        difficulty.bar:SetPoint("TOPRIGHT", difficulty.label, "BOTTOMRIGHT", 0, -8)
        difficulty.bar:SetHeight(12)
        frame.preyCard.difficulties[definition.key] = difficulty
        previousBar = difficulty.bar
    end

    frame.preyCard.summary = previousBar
    local weeklyRow = createStatusRow(frame.preyCard, 1, nil)
    weeklyRow:ClearAllPoints()
    weeklyRow:SetPoint("TOPLEFT", previousBar, "BOTTOMLEFT", 0, -28)
    weeklyRow:SetPoint("TOPRIGHT", previousBar, "BOTTOMRIGHT", 0, -28)
    frame.preyRows[1] = weeklyRow
    local preferredRow = createStatusRow(frame.preyCard, 2, weeklyRow)
    frame.preyRows[2] = preferredRow

    frame.raresCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.raresCard:SetAllPoints(frame.contentHost)

    frame.raresCard.progress = Widgets:CreateLabel(frame.raresCard, "GameFontHighlightSmall", "LEFT")
    frame.raresCard.progress:SetPoint("TOPLEFT", 14, -14)
    frame.raresCard.mountSummary = Widgets:CreateLabel(frame.raresCard, "GameFontHighlightSmall", "LEFT")
    frame.raresCard.mountSummary:SetPoint("LEFT", frame.raresCard.progress, "RIGHT", 26, 0)
    frame.raresCard.reset = Widgets:CreateLabel(frame.raresCard, "GameFontHighlightSmall", "LEFT")
    frame.raresCard.reset:SetPoint("LEFT", frame.raresCard.mountSummary, "RIGHT", 26, 0)
    frame.raresCard.refresh = Widgets:CreateButton(frame.raresCard, L.PVE_RARES_REFRESH, 92, 28, "button")
    frame.raresCard.refresh:SetPoint("TOPRIGHT", -14, -8)

    frame.raresCard.zonePanel = Widgets:CreatePanel(frame.raresCard, "cardInset")
    frame.raresCard.zonePanel:SetPoint("TOPLEFT", 14, -48)
    frame.raresCard.zonePanel:SetPoint("BOTTOMLEFT", 14, 14)
    frame.raresCard.zonePanel:SetWidth(180)
    frame.raresCard.zoneTitle = Widgets:CreateLabel(frame.raresCard.zonePanel, "GameFontNormal", "LEFT")
    frame.raresCard.zoneTitle:SetPoint("TOPLEFT", 12, -12)
    frame.raresCard.zoneTitle:SetPoint("TOPRIGHT", -12, -12)
    frame.raresCard.zoneTitle:SetText(L.PVE_RARES_ZONES)
    frame.raresCard.zoneButtons = {}
    previous = nil
    for index = 1, 4 do
        local button = Widgets:CreateButton(frame.raresCard.zonePanel, "", 156, 30, "tab")
        if previous then
            button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
            button:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -6)
        else
            button:SetPoint("TOPLEFT", frame.raresCard.zoneTitle, "BOTTOMLEFT", 0, -12)
            button:SetPoint("TOPRIGHT", frame.raresCard.zoneTitle, "BOTTOMRIGHT", 0, -12)
        end
        frame.raresCard.zoneButtons[index] = button
        previous = button
    end

    frame.raresCard.detailPanel = Widgets:CreatePanel(frame.raresCard, "cardInset")
    frame.raresCard.detailPanel:SetPoint("TOPLEFT", frame.raresCard.zonePanel, "TOPRIGHT", 14, 0)
    frame.raresCard.detailPanel:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.raresCard.zoneHeader = Widgets:CreateLabel(frame.raresCard.detailPanel, "GameFontNormalLarge", "LEFT")
    frame.raresCard.zoneHeader:SetPoint("TOPLEFT", 14, -12)
    frame.raresCard.zoneHeader:SetPoint("TOPRIGHT", -14, -12)
    frame.raresCard.zoneMeta = Widgets:CreateLabel(frame.raresCard.detailPanel, "GameFontHighlightSmall", "LEFT")
    frame.raresCard.zoneMeta:SetPoint("TOPLEFT", frame.raresCard.zoneHeader, "BOTTOMLEFT", 0, -7)
    frame.raresCard.zoneMeta:SetPoint("TOPRIGHT", -14, 0)

    frame.raresCard.mountPanel = CreateFrame("Frame", nil, frame.raresCard.detailPanel)
    frame.raresCard.mountPanel:SetPoint("TOPLEFT", frame.raresCard.zoneMeta, "BOTTOMLEFT", 0, -12)
    frame.raresCard.mountPanel:SetPoint("TOPRIGHT", -14, 0)
    frame.raresCard.mountPanel:SetHeight(46)
    frame.raresCard.mountSlots = {}
    for index = 1, 2 do
        local slot = createMountSlot(frame.raresCard.mountPanel)
        if index == 1 then
            slot:SetPoint("TOPLEFT", 0, 0)
            slot:SetPoint("BOTTOMRIGHT", frame.raresCard.mountPanel, "BOTTOM", -6, 0)
        else
            slot:SetPoint("TOPLEFT", frame.raresCard.mountPanel, "TOP", 6, 0)
            slot:SetPoint("BOTTOMRIGHT", 0, 0)
        end
        frame.raresCard.mountSlots[index] = slot
    end

    frame.raresCard.scroll = CreateFrame("ScrollFrame", nil, frame.raresCard.detailPanel, "UIPanelScrollFrameTemplate")
    frame.raresCard.scroll:SetPoint("TOPLEFT", frame.raresCard.mountPanel, "BOTTOMLEFT", 0, -12)
    frame.raresCard.scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    frame.raresCard.scrollChild = CreateFrame("Frame", nil, frame.raresCard.scroll)
    frame.raresCard.scrollChild:SetSize(10, 10)
    frame.raresCard.scroll:SetScrollChild(frame.raresCard.scrollChild)
    ScrollFrames:Style(frame.raresCard.scroll, { autoHide = true })
    frame.raresCard.empty = Widgets:CreateLabel(frame.raresCard.detailPanel, "GameFontDisableLarge", "LEFT")
    frame.raresCard.empty:SetPoint("TOPLEFT", frame.raresCard.scroll, "TOPLEFT", 8, -8)
    frame.raresCard.empty:SetPoint("BOTTOMRIGHT", frame.raresCard.scroll, "BOTTOMRIGHT", -8, 8)
    frame.raresCard.empty:SetText(L.PVE_RARES_NO_DATA)
    frame.raresCard.empty:Hide()

    frame.worldCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.worldCard:SetAllPoints(frame.contentHost)
    frame.worldCard.summary = Widgets:CreateLabel(frame.worldCard, "GameFontHighlightSmall", "LEFT")
    frame.worldCard.summary:SetPoint("TOPLEFT", 16, -18)
    frame.worldCard.reset = Widgets:CreateLabel(frame.worldCard, "GameFontHighlightSmall", "LEFT")
    frame.worldCard.reset:SetPoint("LEFT", frame.worldCard.summary, "RIGHT", 28, 0)
    previous = nil
    for index = 1, 4 do
        local row = createStatusRow(frame.worldCard, index, previous)
        frame.worldRows[index] = row
        previous = row
    end

    frame.darkmoonCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.darkmoonCard:SetAllPoints(frame.contentHost)
    frame.darkmoonCard.summary = Widgets:CreateLabel(frame.darkmoonCard, "GameFontHighlightSmall", "LEFT")
    frame.darkmoonCard.summary:SetPoint("TOPLEFT", 16, -16)
    frame.darkmoonCard.reset = Widgets:CreateLabel(frame.darkmoonCard, "GameFontHighlightSmall", "LEFT")
    frame.darkmoonCard.reset:SetPoint("LEFT", frame.darkmoonCard.summary, "RIGHT", 28, 0)
    frame.darkmoonCard.scope = Widgets:CreateLabel(frame.darkmoonCard, "GameFontDisableSmall", "LEFT")
    frame.darkmoonCard.scope:SetPoint("TOPLEFT", frame.darkmoonCard.summary, "BOTTOMLEFT", 0, -7)
    frame.darkmoonCard.scope:SetPoint("TOPRIGHT", -34, -7)
    frame.darkmoonCard.scroll = CreateFrame("ScrollFrame", nil, frame.darkmoonCard, "UIPanelScrollFrameTemplate")
    frame.darkmoonCard.scroll:SetPoint("TOPLEFT", frame.darkmoonCard.scope, "BOTTOMLEFT", 0, -12)
    frame.darkmoonCard.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.darkmoonCard.scrollChild = CreateFrame("Frame", nil, frame.darkmoonCard.scroll)
    frame.darkmoonCard.scrollChild:SetSize(10, 1250)
    frame.darkmoonCard.scrollChild.summary = frame.darkmoonCard.scope
    frame.darkmoonCard.scroll:SetScrollChild(frame.darkmoonCard.scrollChild)
    ScrollFrames:Style(frame.darkmoonCard.scroll, { autoHide = true })
    previous = nil
    for index = 1, 25 do
        local row = createStatusRow(frame.darkmoonCard.scrollChild, index, previous)
        if index == 1 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.darkmoonCard.scrollChild, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", frame.darkmoonCard.scrollChild, "TOPRIGHT", 0, 0)
        end
        frame.darkmoonRows[index] = row
        previous = row
    end
    frame.darkmoonCard.scroll:SetScript("OnSizeChanged", function(scroll, width)
        frame.darkmoonCard.scrollChild:SetWidth(math.max(10, (tonumber(width) or scroll:GetWidth() or 10) - 2))
    end)

    frame.pendingCard = Widgets:CreatePanel(frame.contentHost, "card")
    frame.pendingCard:SetAllPoints(frame.contentHost)
    frame.pendingTitle = Widgets:CreateLabel(frame.pendingCard, "GameFontNormalLarge", "LEFT")
    frame.pendingTitle:SetPoint("TOPLEFT", 18, -18)
    frame.pendingText = Widgets:CreateLabel(frame.pendingCard, "GameFontHighlight", "LEFT")
    frame.pendingText:SetPoint("TOPLEFT", frame.pendingTitle, "BOTTOMLEFT", 0, -12)
    frame.pendingText:SetPoint("TOPRIGHT", -18, -12)
    frame.pendingText:SetText(L.PVE_PENDING_TEXT)

    function frame:Refresh()
        local selectedSubTab = Addon.Database:GetUI().selectedSubTabs.pve or "weekly"
        self.navigation:Refresh()
        if not self.navigation:IsVisible(selectedSubTab) then
            selectedSubTab = "weekly"
            Addon.Database:GetUI().selectedSubTabs.pve = selectedSubTab
        end
        self.navigation:SetSelected(selectedSubTab)
        self.weeklyCard:Hide()
        self.voidInvasionCard:Hide()
        self.dailyCard:Hide()
        self.eventsCard:Hide()
        self.delvesCard:Hide()
        self.preyCard:Hide()
        self.raresCard:Hide()
        self.worldCard:Hide()
        self.darkmoonCard:Hide()
        self.pendingCard:Hide()
        if selectedSubTab ~= "weekly" and selectedSubTab ~= "void_invasion" and selectedSubTab ~= "daily" and selectedSubTab ~= "events" and selectedSubTab ~= "delves" and selectedSubTab ~= "prey" and selectedSubTab ~= "rares" and selectedSubTab ~= "world" and selectedSubTab ~= "darkmoon" then
            self.pendingTitle:SetText(self.navigation:GetLabel(selectedSubTab) or L.PVE_TITLE)
            self.pendingCard:Show()
            return
        end

        local character = Addon.WarbandRoster:GetSelected()
        if selectedSubTab == "void_invasion" then
            self.voidInvasionCard:Show()
            local snapshot = character and Addon.PveVoidInvasion:GetSnapshot(character.key) or nil
            local preferredDifficulty = character
                and Addon.PveVoidInvasion:GetPreferredDifficulty(character.key) or nil
            local selectedDifficulty = preferredDifficulty
                or (snapshot and snapshot.difficulty) or "normal"
            Widgets:SetButtonActive(
                self.voidInvasionCard.normalButton,
                selectedDifficulty == "normal"
            )
            Widgets:SetButtonActive(
                self.voidInvasionCard.heroicButton,
                selectedDifficulty == "heroic"
            )
            if not snapshot then
                self.voidInvasionCard.summary:SetText(L.PVE_VOID_INVASION_NO_SNAPSHOT)
                self.voidInvasionCard.reset:SetText("")
                for _, row in ipairs(self.voidInvasionRows) do
                    row:Hide()
                end
                return
            end
            local view = type(snapshot.views) == "table" and snapshot.views[selectedDifficulty] or nil
            local rows = type(view) == "table" and view.rows or snapshot.rows
            local summary = type(view) == "table" and view.summary or snapshot.summary
            local zoneName = snapshot.zoneName or L.PVE_VOID_INVASION_ZONE_UNKNOWN
            local difficulty = selectedDifficulty == "heroic" and L.PVE_VOID_INVASION_DIFFICULTY_HEROIC
                or selectedDifficulty == "normal" and L.PVE_VOID_INVASION_DIFFICULTY_NORMAL
                or L.PVE_VOID_INVASION_DIFFICULTY_UNKNOWN
            self.voidInvasionCard.summary:SetText(string.format(
                L.PVE_VOID_INVASION_SUMMARY,
                zoneName,
                difficulty,
                summary.completed,
                summary.total
            ))
            self.voidInvasionCard.reset:SetText(string.format(
                L.PVE_VOID_INVASION_RESET,
                summary.resetText
            ))
            for index, row in ipairs(self.voidInvasionRows) do
                setStatusRow(row, rows[index])
            end
            return
        end

        if selectedSubTab == "darkmoon" then
            self.darkmoonCard:Show()
            self.darkmoonCard.scrollChild:SetWidth(math.max(10, (self.darkmoonCard.scroll:GetWidth() or 10) - 2))
            local snapshot = character and Addon.PveDarkmoon:GetSnapshot(character.key) or nil
            if not snapshot then
                self.darkmoonCard.summary:SetText(L.PVE_DARKMOON_NO_SNAPSHOT)
                self.darkmoonCard.reset:SetText("")
                self.darkmoonCard.scope:SetText("")
                for _, row in ipairs(self.darkmoonRows) do
                    row:Hide()
                end
                self.darkmoonCard.scrollChild:SetHeight(10)
                ScrollFrames:Refresh(self.darkmoonCard.scroll, true)
                return
            end
            self.darkmoonCard.summary:SetText(string.format(
                L.PVE_DARKMOON_PROGRESS,
                snapshot.summary.completed,
                snapshot.summary.total
            ))
            self.darkmoonCard.reset:SetText(string.format(
                L.PVE_DARKMOON_DAILY_RESET,
                snapshot.summary.dailyResetText
            ))
            self.darkmoonCard.scope:SetText(string.format(L.PVE_DARKMOON_SCOPE, snapshot.summary.open))
            self.darkmoonCard.scrollChild:SetHeight(math.max(10, (#(snapshot.rows or {}) * 50) - 8))
            for index, row in ipairs(self.darkmoonRows) do
                setStatusRow(row, snapshot.rows[index])
            end
            ScrollFrames:Refresh(self.darkmoonCard.scroll)
            return
        end

        if selectedSubTab == "world" then
            self.worldCard:Show()
            local snapshot = character and Addon.PveWorld:GetSnapshot(character.key) or nil
            if not snapshot then
                self.worldCard.summary:SetText(L.PVE_WORLD_NO_SNAPSHOT)
                self.worldCard.reset:SetText("")
                for _, row in ipairs(self.worldRows) do
                    row:Hide()
                end
                return
            end
            self.worldCard.summary:SetText(string.format(
                L.PVE_WORLD_PROGRESS,
                snapshot.summary.completed,
                snapshot.summary.total
            ))
            self.worldCard.reset:SetText(string.format(L.PVE_WORLD_RESET, snapshot.summary.resetText))
            for index, row in ipairs(self.worldRows) do
                setStatusRow(row, snapshot.rows[index])
            end
            return
        end

        if selectedSubTab == "rares" then
            self.raresCard:Show()
            local identity = Addon.StateStore:Get("character.identity")
            self.raresCard.refresh:SetShown(identity and character and identity.key == character.key)
            self.raresCard.refresh:SetScript("OnClick", function()
                Addon.PveRares:Refresh(0)
            end)
            local snapshot = character and Addon.PveRares:GetSnapshot(character.key) or nil
            if not snapshot then
                self.raresCard.progress:SetText(L.PVE_RARES_NO_SNAPSHOT)
                self.raresCard.mountSummary:SetText("")
                self.raresCard.reset:SetText("")
                self.raresCard.zoneHeader:SetText("")
                self.raresCard.zoneMeta:SetText("")
                for _, button in ipairs(self.raresCard.zoneButtons) do button:Hide() end
                for _, slot in ipairs(self.raresCard.mountSlots) do slot:Hide() end
                for _, row in ipairs(self.rareRows) do row:Hide() end
                self.raresCard.scrollChild:SetHeight(10)
                ScrollFrames:Refresh(self.raresCard.scroll, true)
                self.raresCard.empty:Show()
                return
            end

            self.raresCard.progress:SetText(string.format(L.PVE_RARES_PROGRESS, snapshot.text or "0/0"))
            self.raresCard.mountSummary:SetText(string.format(L.PVE_RARES_MOUNTS, snapshot.mountText or "0/0"))
            self.raresCard.reset:SetText(string.format(L.PVE_RARES_RESET, snapshot.summary and snapshot.summary.resetText or ""))
            local selectedZoneKey = Addon.PveRares:GetSelectedZoneKey()
            local selectedZone = snapshot.zones and snapshot.zones[1] or nil
            for index, zone in ipairs(snapshot.zones or {}) do
                local button = self.raresCard.zoneButtons[index]
                button.zoneKey = zone.key
                button.label:SetText(string.format("%s  %s", zone.label or zone.key, zone.text or "0/0"))
                Widgets:SetButtonActive(button, zone.key == selectedZoneKey)
                button:SetScript("OnClick", function(selfButton)
                    if Addon.PveRares:SetSelectedZoneKey(selfButton.zoneKey) then
                        frame:Refresh()
                    end
                end)
                button:Show()
                if zone.key == selectedZoneKey then
                    selectedZone = zone
                end
            end
            for index = #(snapshot.zones or {}) + 1, #self.raresCard.zoneButtons do
                self.raresCard.zoneButtons[index]:Hide()
            end

            selectedZone = selectedZone or {}
            self.raresCard.zoneHeader:SetText(selectedZone.label or "")
            self.raresCard.zoneMeta:SetText(string.format(
                L.PVE_RARES_ZONE_PROGRESS_FORMAT,
                tonumber(selectedZone.completed) or 0,
                tonumber(selectedZone.total) or 0
            ))
            for index, slot in ipairs(self.raresCard.mountSlots) do
                setMountSlot(slot, selectedZone.mounts and selectedZone.mounts[index])
            end
            local rareCount = #(selectedZone.rares or {})
            while #self.rareRows < rareCount do
                local row = createRareRow(self.raresCard.scrollChild)
                local index = #self.rareRows + 1
                if index == 1 then
                    row:SetPoint("TOPLEFT", self.raresCard.scrollChild, "TOPLEFT", 0, 0)
                    row:SetPoint("TOPRIGHT", self.raresCard.scrollChild, "TOPRIGHT", 0, 0)
                else
                    row:SetPoint("TOPLEFT", self.rareRows[index - 1], "BOTTOMLEFT", 0, -7)
                    row:SetPoint("TOPRIGHT", self.rareRows[index - 1], "BOTTOMRIGHT", 0, -7)
                end
                self.rareRows[index] = row
            end
            for index, row in ipairs(self.rareRows) do
                setRareRow(row, selectedZone.rares and selectedZone.rares[index])
            end
            self.raresCard.scrollChild:SetSize(math.max(10, self.raresCard.scroll:GetWidth() or 10), math.max(10, rareCount * 41))
            ScrollFrames:Refresh(self.raresCard.scroll)
            self.raresCard.empty:SetShown(rareCount == 0)
            return
        end

        if selectedSubTab == "prey" then
            self.preyCard:Show()
            local snapshot = character and Addon.PvePrey:GetSnapshot(character.key) or nil
            if not snapshot then
                self.preyCard.totalLabel:SetText(L.PVE_PREY_NO_SNAPSHOT)
                self.preyCard.totalValue:SetText("")
                Widgets:SetProgress(self.preyCard.totalBar, 0, 1)
                Widgets:SetProgressBreakpoints(self.preyCard.totalBar, {}, 1)
                for _, difficulty in pairs(self.preyCard.difficulties) do
                    difficulty.value:SetText("")
                    Widgets:SetProgress(difficulty.bar, 0, 1, difficulty.color)
                    Widgets:SetProgressBreakpoints(difficulty.bar, {}, 1)
                end
                for _, row in ipairs(self.preyRows) do
                    row:Hide()
                end
                return
            end

            self.preyCard.totalLabel:SetText(L.PVE_PREY_TOTAL)
            self.preyCard.totalValue:SetText(string.format("%d/%d", snapshot.total or 0, snapshot.totalCap or 4))
            Widgets:SetProgress(self.preyCard.totalBar, snapshot.total, snapshot.totalCap, Theme.colors.gold)
            local thresholds = {}
            for index = 1, math.max(1, tonumber(snapshot.unlockedCount) or 1) do
                thresholds[#thresholds + 1] = index * (tonumber(snapshot.difficultyCap) or 4)
            end
            Widgets:SetProgressBreakpoints(self.preyCard.totalBar, thresholds, snapshot.totalCap)

            for key, difficulty in pairs(self.preyCard.difficulties) do
                local entry = type(snapshot.difficulties) == "table" and snapshot.difficulties[key] or {}
                local cap = math.max(1, tonumber(entry.cap) or tonumber(snapshot.difficultyCap) or 4)
                local unlocked = entry.unlocked ~= false
                difficulty.value:SetText(unlocked and string.format("%d/%d", tonumber(entry.count) or 0, cap) or L.PVE_PREY_LOCKED)
                difficulty.value:SetTextColor(difficulty.color[1], difficulty.color[2], difficulty.color[3], unlocked and 1 or 0.48)
                Widgets:SetProgress(difficulty.bar, unlocked and entry.count or 0, cap, difficulty.color)
                Widgets:SetProgressBreakpoints(difficulty.bar, { cap }, cap)
            end
            setStatusRow(self.preyRows[1], snapshot.weeklyQuest)
            setStatusRow(self.preyRows[2], snapshot.preferredQuest)
            return
        end

        if selectedSubTab == "delves" then
            self.delvesCard:Show()
            local snapshot = character and Addon.PveDelves:GetSnapshot(character.key) or nil
            if not snapshot then
                self.delvesCard.summary:SetText(L.PVE_DELVES_NO_SNAPSHOT)
                self.delvesCard.reset:SetText("")
                for _, row in ipairs(self.delveRows) do
                    row:Hide()
                end
                return
            end
            self.delvesCard.summary:SetText(string.format(L.PVE_DELVES_PROGRESS, snapshot.summary.completed, snapshot.summary.total))
            self.delvesCard.reset:SetText(string.format(L.PVE_DELVES_RESET, snapshot.summary.resetText))
            for index, row in ipairs(self.delveRows) do
                setStatusRow(row, snapshot.rows[index])
            end
            return
        end

        if selectedSubTab == "events" then
            self.eventsCard:Show()
            local snapshot = character and Addon.PveEvents:GetSnapshot(character.key) or nil
            if not snapshot then
                self.eventsCard.summary:SetText(L.PVE_EVENTS_NO_SNAPSHOT)
                self.eventsCard.reset:SetText("")
                for _, row in ipairs(self.eventRows) do
                    row:Hide()
                end
                return
            end
            self.eventsCard.summary:SetText(string.format(L.PVE_EVENTS_PROGRESS, snapshot.summary.completed, snapshot.summary.total))
            self.eventsCard.reset:SetText(string.format(L.PVE_EVENTS_RESET, snapshot.summary.resetText))
            for index, row in ipairs(self.eventRows) do
                setStatusRow(row, snapshot.rows[index])
            end
            return
        end

        if selectedSubTab == "daily" then
            self.dailyCard:Show()
            local snapshot = character and Addon.PveDaily:GetSnapshot(character.key) or nil
            if not snapshot then
                self.dailyCard.summary:SetText(L.PVE_DAILY_NO_SNAPSHOT)
                self.dailyCard.reset:SetText("")
                for _, row in ipairs(self.dailyRows) do
                    row:Hide()
                end
                return
            end
            self.dailyCard.summary:SetText(string.format(L.PVE_DAILY_PROGRESS, snapshot.summary.completed, snapshot.summary.total))
            self.dailyCard.reset:SetText(string.format(L.PVE_DAILY_RESET, snapshot.summary.resetText))
            for index, row in ipairs(self.dailyRows) do
                setStatusRow(row, snapshot.rows[index], true)
            end
            return
        end

        self.weeklyCard:Show()
        local snapshot = character and Addon.PveWeekly:GetSnapshot(character.key) or nil
        if not snapshot then
            self.weeklyCard.summary:SetText(L.PVE_WEEKLY_NO_SNAPSHOT)
            self.weeklyCard.reset:SetText("")
            for _, row in ipairs(self.weeklyRows) do
                row:Hide()
            end
            return
        end
        self.weeklyCard.summary:SetText(string.format(L.PVE_WEEKLY_PROGRESS, snapshot.summary.completed, snapshot.summary.total))
        self.weeklyCard.reset:SetText(string.format(L.PVE_WEEKLY_RESET, snapshot.summary.resetText))
        for index, row in ipairs(self.weeklyRows) do
            setStatusRow(row, snapshot.rows[index])
        end
    end

    Addon.StateStore:Subscribe("pve.weekly", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.void_invasion", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.daily", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.events", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.delves", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.prey", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.rares", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.world", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("pve.darkmoon", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        else
            frame.navigation:Refresh()
        end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "pve",
    order = 2,
    label = function() return L.SCREEN_PVE end,
    Create = createPveScreen,
})
