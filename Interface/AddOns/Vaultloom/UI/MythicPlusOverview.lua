local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Assets = Addon.Assets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Overview = {}
Addon.MythicPlusOverview = Overview

local WINDOW_WIDTH = 1180
local WINDOW_HEIGHT = 700
local INNER_WIDTH = 1114
local OVERVIEW_ROW_HEIGHT = 60
local MATRIX_ROW_HEIGHT = 54
local ROW_GAP = 6
local VIEW_MODES = { "overview", "matrix" }
local KEY_FILTERS = { "all", "with_key", "without_key" }
local VAULT_FILTERS = { "all", "open", "progress", "complete", "none" }
local DATA_FILTERS = { "all", "current", "stale", "missing" }
local SORT_MODES = { "attention", "name", "key", "score", "vault" }

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function numeric(value)
    return tonumber(value) or 0
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function cycleValue(values, current)
    for index, value in ipairs(values) do
        if value == current then return values[(index % #values) + 1] end
    end
    return values[1]
end

local function setClassIcon(texture, classFile)
    local customIcon = Assets.classIcons and Assets.classIcons[classFile]
    if customIcon then
        texture:SetTexture(customIcon)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile]
    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    if coords then texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else texture:SetTexCoord(0, 1, 0, 1) end
end

local function getClassColor(classFile)
    local color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile]
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return unpackColor(Theme.colors.gold)
end

local function createStatCard(parent, previous)
    local card = Widgets:CreatePanel(parent, "cardInset")
    card:SetSize(270, 52)
    if previous then card:SetPoint("TOPLEFT", previous, "TOPRIGHT", 10, 0)
    else card:SetPoint("TOPLEFT", 22, -72) end
    card.label = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.label:SetPoint("TOPLEFT", 11, -7)
    card.label:SetPoint("TOPRIGHT", -11, -7)
    card.value = Widgets:CreateLabel(card, "GameFontNormal", "LEFT")
    card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
    card.value:SetPoint("TOPRIGHT", -11, 0)
    card.value:SetTextColor(unpackColor(Theme.colors.gold))
    return card
end

local function createColumnLabel(parent, text, x, width, justify)
    local label = Widgets:CreateLabel(parent, "GameFontNormalSmall", justify or "LEFT")
    label:SetPoint("TOPLEFT", x, 0)
    label:SetSize(width, 32)
    label:SetText(text)
    label:SetTextColor(unpackColor(Theme.colors.gold))
    label:SetWordWrap(false)
    return label
end

local function createOverviewRow(parent, owner)
    local row = Widgets:CreateButton(parent, "", INNER_WIDTH, OVERVIEW_ROW_HEIGHT, "row")
    row.label:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(38, 38)
    row.icon:SetPoint("LEFT", 10, 0)
    row.name = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.name:SetPoint("TOPLEFT", 58, -10)
    row.name:SetSize(178, 18)
    row.name:SetWordWrap(false)
    row.meta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", 58, -32)
    row.meta:SetSize(178, 15)
    row.meta:SetWordWrap(false)

    row.itemLevel = Widgets:CreateLabel(row, "GameFontHighlightSmall", "CENTER")
    row.itemLevel:SetPoint("TOPLEFT", 244, 0)
    row.itemLevel:SetSize(70, OVERVIEW_ROW_HEIGHT)
    row.score = Widgets:CreateLabel(row, "GameFontNormal", "CENTER")
    row.score:SetPoint("TOPLEFT", 318, 0)
    row.score:SetSize(88, OVERVIEW_ROW_HEIGHT)

    row.key = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.key:SetPoint("TOPLEFT", 416, -10)
    row.key:SetSize(204, 18)
    row.keyMeta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.keyMeta:SetPoint("TOPLEFT", 416, -32)
    row.keyMeta:SetSize(204, 15)
    row.keyMeta:SetWordWrap(false)

    row.week = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.week:SetPoint("TOPLEFT", 632, -10)
    row.week:SetSize(134, 18)
    row.weekMeta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.weekMeta:SetPoint("TOPLEFT", 632, -32)
    row.weekMeta:SetSize(134, 15)

    row.vault = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.vault:SetPoint("TOPLEFT", 778, -10)
    row.vault:SetSize(154, 18)
    row.vaultMeta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.vaultMeta:SetPoint("TOPLEFT", 778, -32)
    row.vaultMeta:SetSize(154, 15)
    row.vaultMeta:SetWordWrap(false)

    row.freshness = Widgets:CreateLabel(row, "GameFontNormalSmall", "LEFT")
    row.freshness:SetPoint("TOPLEFT", 944, -10)
    row.freshness:SetSize(158, 18)
    row.freshnessMeta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.freshnessMeta:SetPoint("TOPLEFT", 944, -32)
    row.freshnessMeta:SetSize(158, 15)
    row.freshnessMeta:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if self.characterKey and type(owner.callbacks.select) == "function" then
            owner.callbacks.select(self.characterKey)
            owner:Refresh()
        end
    end)
    row:Hide()
    return row
end

local function createMatrixRow(parent, owner)
    local row = Widgets:CreateButton(parent, "", INNER_WIDTH, MATRIX_ROW_HEIGHT, "row")
    row.label:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", 9, 0)
    row.name = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.name:SetPoint("TOPLEFT", 52, -8)
    row.name:SetSize(158, 18)
    row.meta = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", 52, -29)
    row.meta:SetSize(158, 14)
    row.cells = {}
    row:SetScript("OnClick", function(self)
        if self.characterKey and type(owner.callbacks.select) == "function" then
            owner.callbacks.select(self.characterKey)
            owner:Refresh()
        end
    end)
    row:Hide()
    return row
end

local function ensureMatrixCell(row, index)
    local cell = row.cells[index]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    cell:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cell.value = Widgets:CreateLabel(cell, "GameFontNormal", "CENTER")
    cell.value:SetPoint("TOPLEFT", 3, -5)
    cell.value:SetPoint("TOPRIGHT", -3, -5)
    cell.meta = Widgets:CreateLabel(cell, "GameFontDisableSmall", "CENTER")
    cell.meta:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -2)
    cell.meta:SetPoint("TOPRIGHT", cell.value, "BOTTOMRIGHT", 0, -2)
    row.cells[index] = cell
    return cell
end

local function getBestLevel(dungeon)
    local level = numeric(dungeon and dungeon.best and dungeon.best.level)
    if level <= 0 and type(dungeon and dungeon.bestText) == "string" then
        level = numeric(dungeon.bestText:match("%+(%d+)"))
    end
    return level
end

function Overview:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    frame.callbacks = callbacks
    frame.overviewRows = {}
    frame.matrixRows = {}
    frame.matrixHeaders = {}
    frame.searchQuery = ""
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    local settings = type(callbacks.getSettings) == "function" and callbacks.getSettings() or {}
    frame.viewMode = settings.viewMode == "matrix" and "matrix" or "overview"
    local savedPosition = type(callbacks.getPosition) == "function" and callbacks.getPosition() or nil
    if type(savedPosition) == "table" then
        frame:SetPoint(
            savedPosition.point or "CENTER",
            UIParent,
            savedPosition.relativePoint or savedPosition.point or "CENTER",
            numeric(savedPosition.x),
            numeric(savedPosition.y)
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + 90)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Widgets:ApplyStandardGoldFrame(frame, Assets.windowBackground)

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", 14, -10)
    frame.dragBar:SetPoint("TOPRIGHT", -58, -10)
    frame.dragBar:SetHeight(50)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if type(callbacks.storePosition) == "function" then callbacks.storePosition(frame) end
    end)

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalHuge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -17)
    frame.title:SetPoint("TOPRIGHT", -64, -17)
    frame.title:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))
    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetPoint("TOPRIGHT", -300, 0)
    frame.subtitle:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUBTITLE)
    frame.dataSummary = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "RIGHT")
    frame.dataSummary:SetPoint("TOPRIGHT", -66, -47)
    frame.dataSummary:SetWidth(270)
    frame.dataSummary:SetTextColor(unpackColor(Theme.colors.gold))
    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -18, -16)
    frame.closeButton:SetScript("OnClick", function()
        if type(callbacks.close) == "function" then callbacks.close() else frame:Hide() end
    end)

    frame.statCards = {}
    local previousCard
    for index = 1, 4 do
        local card = createStatCard(frame, previousCard)
        frame.statCards[index] = card
        previousCard = card
    end

    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetSize(200, 28)
    frame.search:SetPoint("TOPLEFT", 22, -139)
    frame.search:SetAutoFocus(false)
    if _G.GameFontHighlightSmall and type(frame.search.SetFontObject) == "function" then
        frame.search:SetFontObject(_G.GameFontHighlightSmall)
    end
    frame.searchHint = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.searchHint:SetPoint("RIGHT", -8, 0)
    frame.searchHint:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_SEARCH)
    frame.search:SetScript("OnTextChanged", function(self)
        frame.searchQuery = lower(self:GetText())
        frame.searchHint:SetShown(frame.searchQuery == "")
        frame:Refresh()
    end)
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function createFilterButton(previous, width)
        local button = Widgets:CreateButton(frame, "", width, 28)
        button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        return button
    end
    frame.realm = createFilterButton(frame.search, 160)
    frame.keyFilter = createFilterButton(frame.realm, 150)
    frame.vaultFilter = createFilterButton(frame.keyFilter, 165)
    frame.dataFilter = createFilterButton(frame.vaultFilter, 150)
    frame.sort = createFilterButton(frame.dataFilter, 210)

    frame.overviewButton = Widgets:CreateButton(frame, L.MYTHIC_PLUS_WARBAND_OVERVIEW_VIEW_OVERVIEW, 180, 28, "tab")
    frame.overviewButton:SetPoint("TOPLEFT", 22, -179)
    frame.matrixButton = Widgets:CreateButton(frame, L.MYTHIC_PLUS_WARBAND_OVERVIEW_VIEW_MATRIX, 180, 28, "tab")
    frame.matrixButton:SetPoint("LEFT", frame.overviewButton, "RIGHT", 6, 0)
    frame.resultSummary = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "RIGHT")
    frame.resultSummary:SetPoint("TOPRIGHT", -44, -181)
    frame.resultSummary:SetSize(260, 24)

    frame.header = Widgets:CreatePanel(frame, "cardInset")
    frame.header:SetPoint("TOPLEFT", 22, -217)
    frame.header:SetSize(INNER_WIDTH, 32)
    frame.overviewHeaders = {
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_CHARACTER, 10, 224),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_ITEM_LEVEL, 244, 70, "CENTER"),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_SCORE, 318, 88, "CENTER"),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_KEY, 416, 204),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_WEEK, 632, 134),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_VAULT, 778, 154),
        createColumnLabel(frame.header, L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_DATA, 944, 158),
    }

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -257)
    frame.scroll:SetPoint("BOTTOMRIGHT", -42, 22)
    frame.scroll:EnableMouseWheel(true)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(INNER_WIDTH, 10)
    frame.scroll:SetScrollChild(frame.child)
    frame.scroll:SetScript("OnMouseWheel", function(self, delta)
        local rowHeight = frame.viewMode == "matrix" and MATRIX_ROW_HEIGHT or OVERVIEW_ROW_HEIGHT
        local nextValue = self:GetVerticalScroll() - (delta * (rowHeight + ROW_GAP))
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), nextValue)))
    end)
    ScrollFrames:Style(frame.scroll, { autoHide = true })
    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisableLarge", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 20, -50)
    frame.empty:SetPoint("TOPRIGHT", -20, -50)
    frame.empty:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_EMPTY)
    frame.empty:Hide()

    function frame:GetSettings()
        local value = type(self.callbacks.getSettings) == "function" and self.callbacks.getSettings() or {}
        return type(value) == "table" and value or {}
    end

    function frame:SetSetting(key, value)
        if type(self.callbacks.setSetting) == "function" then
            self.callbacks.setSetting(key, value)
        else
            self:GetSettings()[key] = value
        end
    end

    function frame:GetOverview()
        local value = type(self.callbacks.getOverview) == "function" and self.callbacks.getOverview() or {}
        return type(value) == "table" and value or {}
    end

    function frame:GetRealmOptions(overview)
        local realms = {}
        for _, entry in ipairs(overview.entries or {}) do
            if tostring(entry.realm or "") ~= "" then realms[entry.realm] = true end
        end
        local names = {}
        for name in pairs(realms) do names[#names + 1] = name end
        table.sort(names, function(a, b) return lower(a) < lower(b) end)
        local options = {
            { key = "all", label = L.SIDEBAR_REALM_ALL },
            { key = "current", label = L.SIDEBAR_REALM_CURRENT },
        }
        for _, name in ipairs(names) do
            options[#options + 1] = { key = "realm:" .. name, label = name }
        end
        return options
    end

    function frame:CycleRealm()
        local overview = self:GetOverview()
        local options, values = self:GetRealmOptions(overview), {}
        for _, option in ipairs(options) do values[#values + 1] = option.key end
        local settingsValue = self:GetSettings()
        self:SetSetting("realmFilter", cycleValue(values, settingsValue.realmFilter))
        self:Refresh()
    end

    frame.realm:SetScript("OnClick", function() frame:CycleRealm() end)
    frame.keyFilter:SetScript("OnClick", function()
        frame:SetSetting("keyFilter", cycleValue(KEY_FILTERS, frame:GetSettings().keyFilter))
        frame:Refresh()
    end)
    frame.vaultFilter:SetScript("OnClick", function()
        frame:SetSetting("vaultFilter", cycleValue(VAULT_FILTERS, frame:GetSettings().vaultFilter))
        frame:Refresh()
    end)
    frame.dataFilter:SetScript("OnClick", function()
        frame:SetSetting("dataFilter", cycleValue(DATA_FILTERS, frame:GetSettings().dataFilter))
        frame:Refresh()
    end)
    frame.sort:SetScript("OnClick", function()
        frame:SetSetting("sortMode", cycleValue(SORT_MODES, frame:GetSettings().sortMode))
        frame:Refresh()
    end)

    function frame:SetViewMode(viewMode)
        viewMode = viewMode == "matrix" and "matrix" or "overview"
        if self.viewMode == viewMode then return false end
        self.viewMode = viewMode
        self:SetSetting("viewMode", viewMode)
        self.scroll:SetVerticalScroll(0)
        self:Refresh()
        return true
    end

    frame.overviewButton:SetScript("OnClick", function() frame:SetViewMode("overview") end)
    frame.matrixButton:SetScript("OnClick", function() frame:SetViewMode("matrix") end)

    function frame:RefreshFilterLabels(overview)
        local settingsValue = self:GetSettings()
        local realmLabel = L.SIDEBAR_REALM_ALL
        for _, option in ipairs(self:GetRealmOptions(overview)) do
            if option.key == settingsValue.realmFilter then realmLabel = option.label; break end
        end
        local keyLabels = {
            all = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_ALL,
            with_key = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_WITH_KEY,
            without_key = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_WITHOUT_KEY,
        }
        local vaultLabels = {
            all = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_ALL,
            open = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_VAULT_OPEN,
            progress = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_VAULT_PROGRESS,
            complete = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_VAULT_COMPLETE,
            none = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_VAULT_NONE,
        }
        local dataLabels = {
            all = L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_ALL,
            current = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_CURRENT,
            stale = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_STALE,
            missing = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_MISSING,
        }
        local sortLabels = {
            attention = L.MYTHIC_PLUS_WARBAND_OVERVIEW_SORT_ATTENTION,
            name = L.SIDEBAR_SORT_NAME,
            key = L.MYTHIC_PLUS_WARBAND_OVERVIEW_SORT_KEY,
            score = L.MYTHIC_PLUS_WARBAND_OVERVIEW_SORT_SCORE,
            vault = L.MYTHIC_PLUS_WARBAND_OVERVIEW_SORT_VAULT,
        }
        self.realm.label:SetText(string.format(L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_REALM, realmLabel))
        self.keyFilter.label:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_KEY,
            keyLabels[settingsValue.keyFilter] or keyLabels.all
        ))
        self.vaultFilter.label:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_VAULT,
            vaultLabels[settingsValue.vaultFilter] or vaultLabels.all
        ))
        self.dataFilter.label:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_DATA,
            dataLabels[settingsValue.dataFilter] or dataLabels.all
        ))
        self.sort.label:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_FILTER_SORT,
            sortLabels[settingsValue.sortMode] or sortLabels.attention
        ))
    end

    function frame:ApplyOverviewRow(row, entry)
        local r, g, b = getClassColor(entry.classFile)
        setClassIcon(row.icon, entry.classFile)
        row.name:SetText(entry.name or L.UNKNOWN)
        row.name:SetTextColor(r, g, b, 1)
        local tags = {}
        if entry.isCurrent then tags[#tags + 1] = L.WARBAND_OVERVIEW_CURRENT_TAG end
        if entry.isMain then tags[#tags + 1] = L.MYTHIC_PLUS_MAIN_TAG end
        if entry.isHidden then tags[#tags + 1] = L.WARBAND_OVERVIEW_HIDDEN_TAG end
        local identity = tostring(entry.realm or L.UNKNOWN)
        if #tags > 0 then identity = identity .. "  |  " .. table.concat(tags, " | ") end
        row.meta:SetText(identity)
        row.itemLevel:SetText(entry.itemLevel and string.format("%.1f", entry.itemLevel) or "--")
        row.score:SetText(entry.score > 0 and tostring(math.floor(entry.score + 0.5)) or "--")
        local scoreColor = Addon.MythicPlusLogic:GetScoreColor(entry.score)
        row.score:SetTextColor(unpackColor(scoreColor))
        row.key:SetText(entry.keyLevel > 0 and string.format("+%d", entry.keyLevel) or L.MYTHIC_PLUS_KEY_NONE)
        row.keyMeta:SetText(entry.keyName or "")
        if entry.weeklyBestLevel > 0 then
            row.week:SetText(string.format("+%d", entry.weeklyBestLevel))
            row.weekMeta:SetText(entry.weeklyRewardLevel > 0
                and string.format(L.MYTHIC_PLUS_WARBAND_OVERVIEW_REWARD_LEVEL, entry.weeklyRewardLevel) or "")
        else
            row.week:SetText("--")
            row.weekMeta:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_WEEK_NONE)
        end
        if entry.vault.total > 0 then
            row.vault:SetText(string.format(
                L.MYTHIC_PLUS_WARBAND_OVERVIEW_VAULT_VALUE,
                entry.vault.unlocked,
                entry.vault.total
            ))
            row.vaultMeta:SetText(entry.vault.note or "")
        else
            row.vault:SetText("--")
            row.vaultMeta:SetText(L.MYTHIC_PLUS_WARBAND_OVERVIEW_VAULT_NO_DATA)
        end
        local freshnessLabels = {
            current = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_CURRENT,
            stale = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_STALE,
            missing = L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_MISSING,
        }
        local freshnessColors = {
            current = { 0.34, 0.88, 0.48, 1 },
            stale = Theme.colors.gold,
            missing = Theme.colors.muted,
        }
        row.freshness:SetText(freshnessLabels[entry.freshness] or L.UNKNOWN)
        row.freshness:SetTextColor(unpackColor(freshnessColors[entry.freshness] or Theme.colors.gold))
        row.freshnessMeta:SetText(entry.updatedAt > 0 and string.format(
            L.MYTHIC_PLUS_WARBAND_KEYS_CAPTURED,
            Addon.MythicPlusLogic:FormatRelative(entry.updatedAt)
        ) or L.MYTHIC_PLUS_WARBAND_KEYS_NO_SNAPSHOT)
        row.characterKey = entry.characterKey
        row:SetAlpha(entry.isHidden and 0.58 or 1)
        row:Show()
    end

    function frame:RefreshOverviewHeaders()
        for _, header in ipairs(self.matrixHeaders) do header:Hide() end
        for _, header in ipairs(self.overviewHeaders) do header:Show() end
    end

    function frame:RefreshMatrixHeaders(dungeons)
        for _, header in ipairs(self.overviewHeaders) do header:Hide() end
        local characterHeader = self.matrixHeaders[1]
        if not characterHeader then
            characterHeader = createColumnLabel(
                self.header,
                L.MYTHIC_PLUS_WARBAND_OVERVIEW_COLUMN_CHARACTER,
                10,
                204
            )
            self.matrixHeaders[1] = characterHeader
        end
        characterHeader:Show()
        local cellWidth = math.max(72, math.floor((INNER_WIDTH - 222) / math.max(1, #dungeons)))
        self.matrixCellWidth = cellWidth
        for index, dungeon in ipairs(dungeons) do
            local header = self.matrixHeaders[index + 1]
            if not header then
                header = createColumnLabel(self.header, "", 0, cellWidth, "CENTER")
                header:SetWordWrap(true)
                header:SetMaxLines(2)
                self.matrixHeaders[index + 1] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 218 + ((index - 1) * cellWidth), 0)
            header:SetSize(cellWidth, 32)
            header:SetText(dungeon.name or L.UNKNOWN)
            header:Show()
        end
        for index = #dungeons + 2, #self.matrixHeaders do self.matrixHeaders[index]:Hide() end
    end

    function frame:ApplyMatrixRow(row, entry, dungeons)
        local r, g, b = getClassColor(entry.classFile)
        setClassIcon(row.icon, entry.classFile)
        row.name:SetText(entry.name or L.UNKNOWN)
        row.name:SetTextColor(r, g, b, 1)
        row.meta:SetText(string.format(
            "%s  |  %s",
            entry.realm or L.UNKNOWN,
            entry.score > 0 and string.format(L.MYTHIC_PLUS_SCORE_SHORT, entry.score) or "--"
        ))
        local cellWidth = self.matrixCellWidth or 72
        for index, descriptor in ipairs(dungeons) do
            local cell = ensureMatrixCell(row, index)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", 218 + ((index - 1) * cellWidth), -5)
            cell:SetSize(cellWidth - 4, MATRIX_ROW_HEIGHT - 10)
            local dungeon = entry.dungeonsByKey and entry.dungeonsByKey[descriptor.key]
            local level = getBestLevel(dungeon)
            local status = dungeon and dungeon.bestStatus or nil
            local color = status == "timed" and { 0.34, 0.88, 0.48, 1 }
                or status == "overtime" and Theme.colors.gold
                or Theme.colors.muted
            cell:SetBackdropColor(color[1], color[2], color[3], level > 0 and 0.12 or 0.04)
            cell:SetBackdropBorderColor(color[1], color[2], color[3], level > 0 and 0.72 or 0.20)
            cell.value:SetText(level > 0 and string.format("+%d", level) or "--")
            cell.value:SetTextColor(unpackColor(color))
            cell.meta:SetText(level > 0 and (status == "timed" and L.MYTHIC_PLUS_TIMED
                or status == "overtime" and L.MYTHIC_PLUS_OVERTIME
                or ((numeric(dungeon and dungeon.score) > 0) and tostring(math.floor(numeric(dungeon.score) + 0.5)) or "")) or "")
            cell:Show()
        end
        for index = #dungeons + 1, #row.cells do row.cells[index]:Hide() end
        row.characterKey = entry.characterKey
        row:SetAlpha(entry.isHidden and 0.58 or 1)
        row:Show()
    end

    function frame:Refresh()
        if not self:IsShown() then return end
        local overview = self:GetOverview()
        local settingsValue = self:GetSettings()
        self.viewMode = settingsValue.viewMode == "matrix" and "matrix" or "overview"
        local entries = Addon.MythicPlusLogic:FilterWarbandOverview(overview, {
            search = self.searchQuery,
            realmFilter = settingsValue.realmFilter,
            keyFilter = settingsValue.keyFilter,
            vaultFilter = settingsValue.vaultFilter,
            dataFilter = settingsValue.dataFilter,
            sortMode = settingsValue.sortMode,
        })

        local summary = overview.summary or {}
        local statValues = {
            { L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUMMARY_CHARACTERS, tostring(numeric(summary.characters)) },
            { L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUMMARY_KEYS, tostring(numeric(summary.keys)) },
            { L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUMMARY_VAULT,
                string.format(L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUMMARY_VAULT_VALUE, numeric(summary.vaultComplete)) },
            { L.MYTHIC_PLUS_WARBAND_OVERVIEW_SUMMARY_RESET,
                Addon.WoWApi:FormatDurationShort(numeric(overview.resetSeconds)) },
        }
        for index, value in ipairs(statValues) do
            self.statCards[index].label:SetText(value[1])
            self.statCards[index].value:SetText(value[2])
        end
        self.dataSummary:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_DATA_SUMMARY,
            numeric(summary.stale),
            numeric(summary.missing)
        ))
        self.resultSummary:SetText(string.format(
            L.MYTHIC_PLUS_WARBAND_OVERVIEW_RESULT_SUMMARY,
            #entries,
            numeric(summary.characters)
        ))
        self:RefreshFilterLabels(overview)
        Widgets:SetButtonActive(self.overviewButton, self.viewMode == "overview")
        Widgets:SetButtonActive(self.matrixButton, self.viewMode == "matrix")

        if self.viewMode == "matrix" then
            self:RefreshMatrixHeaders(overview.dungeons or {})
            for _, row in ipairs(self.overviewRows) do row:Hide() end
            for index, entry in ipairs(entries) do
                local row = self.matrixRows[index]
                if not row then row = createMatrixRow(self.child, self); self.matrixRows[index] = row end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -((index - 1) * (MATRIX_ROW_HEIGHT + ROW_GAP)))
                self:ApplyMatrixRow(row, entry, overview.dungeons or {})
            end
            for index = #entries + 1, #self.matrixRows do self.matrixRows[index]:Hide() end
            self.child:SetHeight(math.max(10, (#entries * (MATRIX_ROW_HEIGHT + ROW_GAP)) - ROW_GAP))
        else
            self:RefreshOverviewHeaders()
            for _, row in ipairs(self.matrixRows) do row:Hide() end
            for index, entry in ipairs(entries) do
                local row = self.overviewRows[index]
                if not row then row = createOverviewRow(self.child, self); self.overviewRows[index] = row end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -((index - 1) * (OVERVIEW_ROW_HEIGHT + ROW_GAP)))
                self:ApplyOverviewRow(row, entry)
            end
            for index = #entries + 1, #self.overviewRows do self.overviewRows[index]:Hide() end
            self.child:SetHeight(math.max(10, (#entries * (OVERVIEW_ROW_HEIGHT + ROW_GAP)) - ROW_GAP))
        end
        self.empty:SetShown(#entries == 0)
        ScrollFrames:Refresh(self.scroll)
    end

    frame:SetScript("OnShow", function() frame:Refresh() end)
    frame:SetScript("OnHide", function()
        if type(frame.search.ClearFocus) == "function" then frame.search:ClearFocus() end
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:Hide()
    return frame
end
