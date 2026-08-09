local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.accounting
if not module then return end

local unpack = unpack or table.unpack
local ITEM_CLASS_HOUSING = module.ITEM_CLASS_HOUSING
local ITEM_CLASS_LABELS = module.ITEM_CLASS_LABELS or {}
local ITEM_CLASS_FILTER_ORDER = module.ITEM_CLASS_FILTER_ORDER or {}
local CATEGORY_SETTING_KEYS = module.CATEGORY_SETTING_KEYS or {}
local CATEGORY_ORDER = module.CATEGORY_ORDER or {}
local GetItemInfoSafe = module.GetItemInfoSafe
local ExtractItemID = module.ExtractItemID
local NowEpoch = module.NowEpoch or function() return time and time() or 0 end

-- ============================================================================
-- Feature UI: Ledger viewer window
-- ============================================================================
--
-- A standalone, movable, themed window with tabs (Summary/All/Income/Expenses),
-- a time-bucket selector (24h/7d/14d/30d/all), a scrolling ledger list and a
-- footer with income/expense/net totals. Opened via /thyrax accounting show
-- or the Options Panel "Open Ledger Window" button.

module.WINDOW = {
    WIDTH       = 860,
    HEIGHT      = 592,
    MIN_WIDTH   = 760,
    MIN_HEIGHT  = 452,
    MAX_WIDTH   = 1400,
    MAX_HEIGHT  = 900,
    PADDING     = 12,
    HEADER_H    = 32,
    TAB_BAR_H   = 28,
    FILTER_BAR_H = 28,
    CATEGORY_BAR_H = 28,
    FOOTER_H    = 28,
    ROW_HEIGHT  = 18,
    COL_TIME    = 72,
    COL_KIND    = 112,
    COL_TYPE    = 100,
    COL_WHO     = 100,
    COL_AMOUNT  = 146,
    COL_DETAIL  = 178,
}

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DAILY_TREND_CHUNK_SIZE = 2000
local DAILY_TREND_CHUNK_DELAY = 0.01

-- Coercing clamp: window-size settings may be nil, so coerce to the minimum
-- before clamping via the shared Core helper. NormalizeColor / MixColor map to
-- their Core equivalents (all MixColor call sites pass an explicit alpha, so
-- ns.Color.Mix matches the old default-alpha behavior).
local function Clamp(value, minValue, maxValue)
    return ns.Color.Clamp(tonumber(value) or minValue, minValue, maxValue)
end
local NormalizeColor = ns.Color.Normalize
local MixColor = ns.Color.Mix

local function EnsureWindowSettings(settings)
    if type(settings) ~= "table" then return nil end
    if type(settings.window) ~= "table" then settings.window = {} end
    local window = settings.window
    if type(window.point) ~= "string" or window.point == "" then window.point = "CENTER" end
    if type(window.relativePoint) ~= "string" or window.relativePoint == "" then window.relativePoint = "CENTER" end
    window.x = tonumber(window.x) or 0
    window.y = tonumber(window.y) or 0
    window.width = Clamp(window.width or module.WINDOW.WIDTH, module.WINDOW.MIN_WIDTH, module.WINDOW.MAX_WIDTH)
    window.height = Clamp(window.height or module.WINDOW.HEIGHT, module.WINDOW.MIN_HEIGHT, module.WINDOW.MAX_HEIGHT)
    if window.tab == "summary" then window.tab = "groups" end
    if window.tab == "settings" then window.tab = "overview" end
    if type(window.tab) ~= "string" or window.tab == "" then window.tab = "overview" end
    if type(window.bucket) ~= "string" or window.bucket == "" then window.bucket = "7d" end
    if type(window.search) ~= "string" then window.search = "" end
    if type(window.groupBy) ~= "string" or window.groupBy == "" then window.groupBy = "source" end
    if type(window.chartView) ~= "string" or window.chartView == "" then window.chartView = "source" end
    -- Migrate legacy string itemFilter to hiddenItemTypes table
    if type(window.itemFilter) == "string" and window.itemFilter ~= "all" and window.itemFilter ~= "" then
        if type(window.hiddenItemTypes) ~= "table" then window.hiddenItemTypes = {} end
        -- Legacy single-select: we cannot perfectly migrate, just clear
    end
    window.itemFilter = nil -- remove legacy field
    if type(window.hiddenItemTypes) ~= "table" then window.hiddenItemTypes = {} end
    if window.characterFilter == "account" then window.characterFilter = "all" end
    if type(window.characterFilter) ~= "string" or window.characterFilter == "" then window.characterFilter = "current" end
    if type(window.columns) ~= "table" then window.columns = {} end
    if window.columns.time == nil then window.columns.time = true end
    if window.columns.source == nil then window.columns.source = true end
    if window.columns.itemType == nil then window.columns.itemType = true end
    if window.columns.who == nil then window.columns.who = true end
    if window.columns.amount == nil then window.columns.amount = true end
    if window.columns.detail == nil then window.columns.detail = true end
    return window
end
module.EnsureWindowSettings = EnsureWindowSettings

-- A small palette helper -- pulls from ns.UI:GetTheme rather than caching
-- so theme switches via Options Panel propagate live (RefreshWindow recolors).
local function WindowPalette()
    local theme = (ns.UI and ns.UI.GetTheme and ns.UI:GetTheme()) or "Modern"
    local palette
    if theme == "Classic" then
        palette = {
            windowBg    = { 0.10, 0.10, 0.10, 0.90 },
            windowBorder = { 0, 0, 0, 1 },
            tabOnBg     = { 0.20, 0.20, 0.22, 0.95 },
            tabOffBg    = { 0.08, 0.08, 0.09, 0.85 },
            tabHoverBg  = { 0.30, 0.30, 0.34, 0.95 },
            tabOnText   = { 1.00, 1.00, 1.00, 1 },
            tabOffText  = { 0.65, 0.65, 0.70, 1 },
            title       = { 0.85, 0.88, 0.95, 1 },
            rowAlt      = { 1, 1, 1, 0.04 },
            rowSep      = { 0.30, 0.30, 0.30, 0.30 },
            colHeader   = { 0.55, 0.65, 0.80, 1 },
            posAmount   = { 0.30, 0.95, 0.40, 1 },  -- green
            negAmount   = { 0.95, 0.35, 0.30, 1 },  -- red
            neutralText = { 0.92, 0.92, 0.92, 1 },
            dimText     = { 0.65, 0.65, 0.65, 1 },
        }
    else
        -- Modern (golden, default)
        palette = {
            windowBg    = { 0.12, 0.09, 0.05, 0.92 },
            windowBorder = { 0.68, 0.57, 0.26, 0.95 },
            tabOnBg     = { 0.42, 0.34, 0.16, 0.95 },
            tabOffBg    = { 0.18, 0.13, 0.07, 0.85 },
            tabHoverBg  = { 0.55, 0.46, 0.22, 0.95 },
            tabOnText   = { 1.00, 0.92, 0.66, 1 },
            tabOffText  = { 0.65, 0.58, 0.42, 1 },
            title       = { 1.00, 0.82, 0.22, 1 },
            rowAlt      = { 0.72, 0.62, 0.28, 0.06 },
            rowSep      = { 0.40, 0.32, 0.16, 0.35 },
            colHeader   = { 0.95, 0.78, 0.30, 1 },
            posAmount   = { 0.45, 0.95, 0.40, 1 },
            negAmount   = { 0.95, 0.40, 0.30, 1 },
            neutralText = { 0.95, 0.92, 0.80, 1 },
            dimText     = { 0.70, 0.62, 0.42, 1 },
        }
    end

    local settings = module.settings or module.defaults
    local userAlpha = settings and tonumber(settings.windowAlpha)
    if userAlpha then
        if userAlpha < 0.3 then userAlpha = 0.3 end
        if userAlpha > 1 then userAlpha = 1 end
        palette.windowBg[4] = userAlpha
        palette.tabOnBg[4] = math.min(1, userAlpha + 0.05)
        palette.tabOffBg[4] = math.max(0.2, userAlpha - 0.07)
        palette.tabHoverBg[4] = math.min(1, userAlpha + 0.05)
    end

    if settings and settings.customTheme == true then
        local accent = NormalizeColor(settings.accentColor, palette.colHeader)
        local surface = NormalizeColor(settings.surfaceColor, palette.tabOffBg)
        palette.windowBg = { surface[1], surface[2], surface[3], 0.92 }
        palette.windowBorder = { accent[1], accent[2], accent[3], 0.95 }
        palette.tabOffBg = { surface[1], surface[2], surface[3], 0.88 }
        palette.tabOnBg = MixColor(surface, accent, 0.48, 0.95)
        palette.tabHoverBg = MixColor(surface, accent, 0.68, 0.95)
        palette.title = { accent[1], accent[2], accent[3], 1 }
        palette.colHeader = { accent[1], accent[2], accent[3], 1 }
        palette.rowAlt = { accent[1], accent[2], accent[3], 0.07 }
        palette.rowSep = { accent[1], accent[2], accent[3], 0.30 }
    else
        -- Custom theme OFF: follow the global accent preset so a user who
        -- picked "Blue" in the General page gets a blue Accounting window
        -- too. When the preset is "Gold" we keep the hand-tuned Modern
        -- palette above (Gold is already its baseline look).
        local preset = (ns.UI and ns.UI.GetAccentPreset and ns.UI:GetAccentPreset()) or "Gold"
        local globalPalette = ns.UI and ns.UI.GetAccentPalette and ns.UI:GetAccentPalette() or nil
        if preset ~= "Gold" and globalPalette and globalPalette.accent and globalPalette.surface then
            local accent = globalPalette.accent
            local surface = globalPalette.surface
            palette.windowBg = { surface[1], surface[2], surface[3], palette.windowBg[4] }
            palette.windowBorder = { accent[1], accent[2], accent[3], 0.95 }
            palette.tabOffBg = { surface[1], surface[2], surface[3], palette.tabOffBg[4] }
            palette.tabOnBg = MixColor(surface, accent, 0.48, 0.95)
            palette.tabHoverBg = MixColor(surface, accent, 0.68, 0.95)
            palette.title = { accent[1], accent[2], accent[3], 1 }
            palette.colHeader = { accent[1], accent[2], accent[3], 1 }
            palette.rowAlt = { accent[1], accent[2], accent[3], 0.07 }
            palette.rowSep = { accent[1], accent[2], accent[3], 0.30 }
        end
    end

    -- Global font override wins over the accent-derived defaults: this is
    -- what lets a user keep a Green accent (window border / tab tint) while
    -- forcing pure-white column headers + light-grey dim text for legibility.
    if ns.Settings and ns.Settings.IsCustomFontEnabled and ns.Settings:IsCustomFontEnabled() then
        local primary = ns.Settings:GetCustomFontPrimary()
        local secondary = ns.Settings:GetCustomFontSecondary()
        palette.colHeader = { primary[1], primary[2], primary[3], primary[4] or 1 }
        palette.title     = { primary[1], primary[2], primary[3], primary[4] or 1 }
        palette.dimText   = { secondary[1], secondary[2], secondary[3], secondary[4] or 1 }
    end

    return palette
end

-- Filter spec for each tab. Each filter receives the entry and returns true
-- to include it. Summary tab is handled separately (per-kind aggregation).
local TAB_FILTERS = {
    all      = function(_) return true end,
    income   = function(e) return (e.amount or 0) > 0 end,
    expenses = function(e) return (e.amount or 0) < 0 end,
}

local TIME_BUCKETS = {
    { id = "24h", label = "Last 24h",  seconds = module.CONSTANTS.BUCKET_24H },
    { id = "7d",  label = "Last 7d",   seconds = module.CONSTANTS.BUCKET_7D  },
    { id = "14d", label = "Last 14d",  seconds = module.CONSTANTS.BUCKET_14D },
    { id = "30d", label = "Last 30d",  seconds = module.CONSTANTS.BUCKET_30D },
    { id = "90d", label = "Last 90d",  seconds = module.CONSTANTS.BUCKET_90D },
    { id = "all", label = "All time",  seconds = nil },
}

local TABS = {
    { id = "overview", label = "Overview" },
    { id = "all", label = "Ledger" },
    { id = "income", label = "Income" },
    { id = "expenses", label = "Expenses" },
    { id = "groups", label = "Groups" },
    { id = "charts", label = "Charts" },
}

local GROUP_MODES = {
    { id = "source", label = "Source" },
    { id = "category", label = "Category" },
    { id = "itemType", label = "Item Type" },
    { id = "housing", label = "Housing" },
    { id = "item", label = "Item" },
    { id = "who", label = "Who" },
    { id = "character", label = "Character" },
}

local CHART_MODES = {
    { id = "source", label = "Sources" },
    { id = "daily", label = "Daily Trend" },
}

local function GetGroupModeLabel(modeID)
    for _, mode in ipairs(GROUP_MODES) do
        if mode.id == modeID then return mode.label end
    end
    return "Source"
end

local function GetChartModeLabel(modeID)
    for _, mode in ipairs(CHART_MODES) do
        if mode.id == modeID then return mode.label end
    end
    return "Sources"
end

local function GetBucketLabel(bucketID)
    for _, bucket in ipairs(TIME_BUCKETS) do
        if bucket.id == bucketID then return bucket.label end
    end
    return "All time"
end

local COLUMN_ORDER = { "time", "source", "itemType", "who", "amount", "detail" }
local COLUMN_LABELS = {
    time = "Time",
    source = "Source",
    itemType = "Type",
    who = "Who",
    amount = "Amount",
    detail = "Details",
}
local WINDOW_EDGE_REGIONS = {
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
}
local TOOLBAR_THEME_BUTTON_KEYS = {
    "_bucketSelect", "_groupSelect", "_trendOptionsSelect", "_sortSelect",
    "_characterSelect", "_filterSelect", "_itemTypeSelect", "_columnSelect",
}

local MONEY_ICON_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local MONEY_ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local MONEY_ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local MAX_RENDER_ROWS = 500

local function SplitMoney(copper)
    local n = tonumber(copper) or 0
    local abs = math.abs(n)
    return n,
        math.floor(abs / 10000),
        math.floor((abs % 10000) / 100),
        abs % 100
end

local function GetMoneyThousandsSeparator()
    local value = module.settings and module.settings.moneyThousandsSeparator
    if value == "," then return "," end
    if value == "space" then return " " end
    if value == "none" then return "" end
    return "."
end

local function AddThousands(value)
    local sep = GetMoneyThousandsSeparator()
    local text = tostring(math.floor(math.abs(tonumber(value) or 0)))
    if sep == "" then return text end
    local result = text:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if result:sub(1, #sep) == sep then
        result = result:sub(#sep + 1)
    end
    return result
end

local function ShouldAlwaysCompactMoney()
    return module.settings and module.settings.moneyCompactAlways == true
end

local function TextWidth(fs, text)
    if not (fs and fs.SetText and fs.GetStringWidth) then return 0 end
    local old = fs:GetText()
    fs:SetText(text or "")
    local width = fs:GetStringWidth() or 0
    fs:SetText(old or "")
    return width
end

local function BuildMoneyTexts(copper)
    local n, g, s, c = SplitMoney(copper)
    local showSilver = g > 0 or s > 0
    local copperText = (g > 0 or s > 0) and string.format("%02d", c) or tostring(c)
    return {
        sign = n < 0 and "-" or "+",
        gold = g > 0 and (AddThousands(g) .. MONEY_ICON_GOLD) or "",
        silver = showSilver and (string.format("%02d", s) .. MONEY_ICON_SILVER) or "",
        copper = copperText .. MONEY_ICON_COPPER,
    }
end

-- Compact relative-time string. ~6 chars max so columns stay aligned.
local function AgoString(ts)
    local ago = NowEpoch() - (ts or 0)
    if ago < 60 then return ago .. "s" end
    if ago < 3600 then return math.floor(ago / 60) .. "m" end
    if ago < 86400 then return math.floor(ago / 3600) .. "h" end
    if ago < 86400 * 30 then return math.floor(ago / 86400) .. "d" end
    return math.floor(ago / 86400) .. "d"
end

-- Build a tab button consistent with the rest of the addon's themed style.
local function MakeTabButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, module.WINDOW.TAB_BAR_H - 4)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local p = WindowPalette()
    btn:SetBackdropColor(unpack(p.tabOffBg))
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText(label)
    btn._text = text
    btn._isOn = false
    btn:SetScript("OnEnter", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(p.tabHoverBg))
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(self._isOn and p.tabOnBg or p.tabOffBg))
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function MakeToolbarButton(parent, width, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, module.WINDOW.FILTER_BAR_H - 4)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local p = WindowPalette()
    btn:SetBackdropColor(unpack(p.tabOffBg))
    btn:SetBackdropBorderColor(p.colHeader[1], p.colHeader[2], p.colHeader[3], 0.75)
    btn._thyraxToolbarBtn = true

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", btn, "LEFT", 8, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label or "")
    btn._text = text
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(p.colHeader))
    btn._arrow = arrow
    btn:SetScript("OnEnter", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(p.tabHoverBg))
        self:SetBackdropBorderColor(unpack(p.title))
        if self._arrow then self._arrow:SetVertexColor(unpack(p.title)) end
    end)
    btn:SetScript("OnLeave", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(self._isOn and p.tabOnBg or p.tabOffBg))
        self:SetBackdropBorderColor(p.colHeader[1], p.colHeader[2], p.colHeader[3], 0.75)
        if self._arrow then self._arrow:SetVertexColor(unpack(p.colHeader)) end
    end)
    btn:SetScript("OnClick", onClick)
    btn.SetDisplayText = function(self, value)
        self._text:SetText(value or "")
    end
    return btn
end

local function MakeWindowIconButton(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(24, 24)
    btn:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText(label)
    btn._text = text
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(p.tabHoverBg))
        if tooltip and _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            _G.GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            _G.GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        local p = WindowPalette()
        self:SetBackdropColor(unpack(p.tabOffBg))
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    return btn
end

local function ApplyWindowIconButtonTheme(btn, palette)
    if not btn then return end
    btn:SetBackdropColor(unpack(palette.tabOffBg))
    btn:SetBackdropBorderColor(unpack(palette.colHeader))
    if btn._text then btn._text:SetTextColor(unpack(palette.title)) end
end

local function ApplyToolbarButtonTheme(btn, palette)
    if not (btn and btn._thyraxToolbarBtn) then return end
    btn:SetBackdropColor(unpack(btn._isOn and palette.tabOnBg or palette.tabOffBg))
    btn:SetBackdropBorderColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 0.75)
    if btn._text then btn._text:SetTextColor(unpack(palette.neutralText)) end
    if btn._arrow then btn._arrow:SetVertexColor(unpack(palette.colHeader)) end
end

local function ApplySearchTheme(search, palette, hasFilter)
    if not search then return end
    if search.SetBackdrop then
        if hasFilter then
            local activeBg = MixColor(palette.tabOffBg, palette.colHeader, 0.42, 0.94)
            search:SetBackdropColor(unpack(activeBg))
            search:SetBackdropBorderColor(unpack(palette.title))
        else
            search:SetBackdropColor(unpack(palette.tabOffBg))
            search:SetBackdropBorderColor(palette.rowSep[1], palette.rowSep[2], palette.rowSep[3], 0.6)
        end
    end
    search:SetTextColor(unpack(palette.neutralText))
end

local function ApplyScrollTheme(scroll, palette)
    local bar = scroll and (scroll.ScrollBar or scroll.scrollBar or scroll.Scrollbar)
    if not bar then return end
    if not bar._thyraxBg and bar.CreateTexture then
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -16)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 16)
        bar._thyraxBg = bg
    end
    if bar._thyraxBg then
        bar._thyraxBg:SetTexture(WHITE_TEXTURE)
        bar._thyraxBg:SetVertexColor(palette.tabOffBg[1], palette.tabOffBg[2], palette.tabOffBg[3], 0.38)
    end
    if bar.GetThumbTexture then
        local thumb = bar:GetThumbTexture()
        if thumb then
            thumb:SetTexture(WHITE_TEXTURE)
            thumb:SetVertexColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 0.48)
        end
    end
    local buttons = { bar.ScrollUpButton, bar.ScrollDownButton, bar.Back, bar.Forward }
    for _, button in ipairs(buttons) do
        if button and button.SetAlpha then
            button:SetAlpha(0.45)
        end
    end
end

function module:CloseWindowMenu()
    if self.window and self.window._menu then
        self.window._menu:Hide()
    end
end

function module:OpenWindowMenu(owner, width, entries, forceRefresh)
    local menuSource = entries
    if type(entries) == "function" then entries = entries() end
    if not (self.window and owner and type(entries) == "table") then return end
    local f = self.window
    local menu = f._menu
    if not menu then
        menu = CreateFrame("Frame", nil, f, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        menu.rows = {}
        menu:Hide()
        f._menu = menu
    elseif menu:IsShown() and menu.owner == owner and not forceRefresh then
        menu:Hide()
        return
    end

    local columnCount = #entries > 18 and 2 or 1
    local rowsPerColumn = math.ceil(math.max(1, #entries) / columnCount)
    local p = WindowPalette()
    menu.owner = owner
    if menu.SetFrameLevel and owner.GetFrameLevel then
        menu:SetFrameLevel(owner:GetFrameLevel() + 25)
    end
    menu:SetBackdropColor(unpack(p.tabOffBg))
    menu:SetBackdropBorderColor(unpack(p.colHeader))
    menu:SetWidth(width * columnCount)
    menu:SetHeight(rowsPerColumn * 22 + 4)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    for _, row in ipairs(menu.rows) do row:Hide() end

    for i, entry in ipairs(entries) do
        local currentEntry = entry
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(22)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(unpack(WindowPalette().tabHoverBg))
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(0, 0, 0, 0)
            end)
            menu.rows[i] = row
        end
        if row.SetFrameLevel and menu.GetFrameLevel then
            row:SetFrameLevel(menu:GetFrameLevel() + 1)
        end
        local column = math.floor((i - 1) / rowsPerColumn)
        local rowIndex = (i - 1) % rowsPerColumn
        row:SetWidth(width - 4)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2 + column * width, -2 - rowIndex * 22)
        local prefix = currentEntry.checked and "[x] " or (currentEntry.checkable and "[ ] " or "")
        row.text:SetText(prefix .. tostring(currentEntry.label or ""))
        row.text:SetTextColor(unpack(p.neutralText))
        row.bg:SetColorTexture(0, 0, 0, 0)
        row:SetScript("OnClick", function()
            if type(currentEntry.onClick) == "function" then currentEntry.onClick() end
            if currentEntry.keepOpen then
                module:OpenWindowMenu(owner, width, menuSource, true)
            else
                menu:Hide()
            end
        end)
        row:Show()
    end
    menu:Show()
end

-- Build a single row in the scroll content. Returns the row frame.
local function MakeLedgerRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(module.WINDOW.ROW_HEIGHT)
    if row.SetFrameLevel and parent.GetFrameLevel then
        row:SetFrameLevel(parent:GetFrameLevel() + 1)
    end
    row:EnableMouse(true)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    if index % 2 == 0 then
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row._stripe = stripe

    local function col(width, anchorOffset, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", anchorOffset, 0)
        fs:SetWidth(width - 6)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local w = module.WINDOW
    row._time   = col(w.COL_TIME,   0,                                                 "LEFT")
    row._kind   = col(w.COL_KIND,   w.COL_TIME,                                        "LEFT")
    row._type   = col(w.COL_TYPE,   w.COL_TIME + w.COL_KIND,                           "LEFT")
    row._who    = col(w.COL_WHO,    w.COL_TIME + w.COL_KIND + w.COL_TYPE,              "LEFT")
    row._amount = col(w.COL_AMOUNT, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO,  "RIGHT")
    row._amount:Hide()
    row._amountSign = col(12, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO, "RIGHT")
    row._amountGold = col(48, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO + 12, "RIGHT")
    row._amountSilver = col(38, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO + 60, "RIGHT")
    row._amountCopper = col(38, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO + 98, "RIGHT")
    row._detail = col(w.COL_DETAIL, w.COL_TIME + w.COL_KIND + w.COL_TYPE + w.COL_WHO + w.COL_AMOUNT + 8, "LEFT")

    row._bar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row._bar:SetColorTexture(0.45, 0.95, 0.40, 0.28)
    row._bar:Hide()

    row._sectionLine = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row._sectionLine:SetHeight(1)
    row._sectionLine:Hide()

    row._sectionTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row._sectionTitle:SetJustifyH("LEFT")
    row._sectionTitle:SetWordWrap(false)
    row._sectionTitle:Hide()

    local function ResolveRowItemLink(self)
        if self._itemLink then return self._itemLink end
        if not self._itemName then return nil end
        local resolvedName, resolvedLink = GetItemInfoSafe(self._itemName)
        if not resolvedLink then return nil end

        self._itemLink = resolvedLink
        self._itemName = resolvedName or self._itemName

        local entry = self._entryRef
        if type(entry) == "table" then
            entry.itemLink = resolvedLink
            entry.item = resolvedLink
            entry.itemName = self._itemName
            entry.itemID = entry.itemID or ExtractItemID(resolvedLink)
            module:NormalizeItemFields(entry)
            module:QueueWindowRefresh()
        end

        return resolvedLink
    end

    row:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        if not self._itemLink and not self._itemName and not self._questID then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._itemLink then
            _G.GameTooltip:SetHyperlink(self._itemLink)
        elseif self._itemName then
            local resolvedLink = ResolveRowItemLink(self)
            if resolvedLink then
                _G.GameTooltip:SetHyperlink(resolvedLink)
            else
                _G.GameTooltip:SetText(tostring(self._itemName), 1, 1, 1)
                _G.GameTooltip:AddLine("Item link is not cached by the client yet.", 0.7, 0.7, 0.7)
            end
        else
            _G.GameTooltip:SetText(tostring(self._questName or ("Quest #" .. tostring(self._questID))), 1, 0.82, 0.22)
            _G.GameTooltip:AddLine("Quest ID: " .. tostring(self._questID), 0.9, 0.9, 0.9)
        end
        _G.GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self)
        if self._settingKey then
            module.settings[self._settingKey] = not (module.settings[self._settingKey] == true)
            module:UpdateMinimapButton()
            module:RefreshWindow()
            return
        end
        if self._itemFilterToggle then
            -- Toggle housing filter shortcut from settings tab
            local windowSettings = EnsureWindowSettings(module.settings)
            local h = module.windowState.hiddenItemTypes or {}
            if h["Housing"] then
                h["Housing"] = nil
            else
                h["Housing"] = true
            end
            module.windowState.hiddenItemTypes = h
            if windowSettings then windowSettings.hiddenItemTypes = h end
            module:RefreshWindow()
            return
        end
        if self._drilldownSearch then
            local windowSettings = EnsureWindowSettings(module.settings)
            module.windowState.tab = self._drilldownTab or "all"
            module.windowState.search = self._drilldownSearch
            if windowSettings then
                windowSettings.tab = module.windowState.tab
                windowSettings.search = module.windowState.search
            end
            module:RefreshWindow()
            return
        end
        local itemLink = ResolveRowItemLink(self)
        if not itemLink then return end
        if type(_G.IsModifiedClick) == "function" and not _G.IsModifiedClick("CHATLINK") then
            return
        end
        if type(_G.HandleModifiedItemClick) == "function" then
            _G.HandleModifiedItemClick(itemLink)
        end
    end)

    return row
end

local FormatCompactMoney, FormatCompactGoldAmount

local function SetRowMoney(row, copper, noMoney, palette)
    if not row then return end
    row._noMoney = noMoney and true or false
    row._amountCopperValue = copper
    if row._amount then row._amount:SetText("") end
    local fields = { row._amountSign, row._amountGold, row._amountSilver, row._amountCopper }
    if noMoney then
        for _, fs in ipairs(fields) do if fs then fs:SetText(""); fs:Hide() end end
        return
    end

    local n = tonumber(copper) or 0
    local col = palette.neutralText
    if n > 0 then col = palette.posAmount
    elseif n < 0 then col = palette.negAmount end
    local texts = BuildMoneyTexts(copper)
    if row._amountSign then
        row._amountSign:SetText(texts.sign)
        row._amountSign:SetTextColor(unpack(col))
        row._amountSign:Show()
    end
    if row._amountCompact then
        if row._amountGold then
            row._amountGold:SetText(FormatCompactGoldAmount(copper))
            row._amountGold:SetTextColor(unpack(col))
            row._amountGold:Show()
        end
        if row._amountSilver then row._amountSilver:SetText(""); row._amountSilver:Hide() end
        if row._amountCopper then row._amountCopper:SetText(""); row._amountCopper:Hide() end
        return
    end
    if row._amountGold then
        row._amountGold:SetText(texts.gold)
        row._amountGold:SetTextColor(unpack(col))
        row._amountGold:Show()
    end
    if row._amountSilver then
        row._amountSilver:SetText(texts.silver)
        row._amountSilver:SetTextColor(unpack(col))
        row._amountSilver:Show()
    end
    if row._amountCopper then
        row._amountCopper:SetText(texts.copper)
        row._amountCopper:SetTextColor(unpack(col))
        row._amountCopper:Show()
    end
end

local function SetMoneyParts(parts, copper, palette)
    if type(parts) ~= "table" then return end
    parts._lastCopper = copper
    local n = tonumber(copper) or 0
    local col = palette.neutralText
    if n > 0 then col = palette.posAmount
    elseif n < 0 then col = palette.negAmount end
    local texts = BuildMoneyTexts(copper)
    if parts.sign then
        parts.sign:SetText(texts.sign)
        parts.sign:SetTextColor(unpack(col))
    end
    local compact = parts._compact == true
    if compact then
        if parts.gold then
            parts.gold:SetText(FormatCompactGoldAmount(copper))
            parts.gold:SetTextColor(unpack(col))
        end
        if parts.silver then parts.silver:SetText("") end
        if parts.copper then parts.copper:SetText("") end
        return
    end
    if parts.gold then
        parts.gold:SetText(texts.gold)
        parts.gold:SetTextColor(unpack(col))
    end
    if parts.silver then
        parts.silver:SetText(texts.silver)
        parts.silver:SetTextColor(unpack(col))
    end
    if parts.copper then
        parts.copper:SetText(texts.copper)
        parts.copper:SetTextColor(unpack(col))
    end
end

function FormatCompactMoney(copper)
    local gold = math.floor(math.abs(tonumber(copper) or 0) / 10000)
    if gold >= 1000000 then
        return string.format("%.1fM", gold / 1000000)
    end
    if gold >= 1000 then
        return tostring(math.floor(gold / 1000)) .. "K"
    end
    return tostring(gold) .. "g"
end

function FormatCompactGoldAmount(copper)
    local text = FormatCompactMoney(copper)
    if text:sub(-1) == "g" then
        text = text:sub(1, -2)
    end
    return text .. MONEY_ICON_GOLD
end

local function GetLocalDayStart(ts)
    ts = tonumber(ts) or NowEpoch()
    if type(date) == "function" and type(time) == "function" then
        local d = date("*t", ts)
        if type(d) == "table" then
            d.hour, d.min, d.sec = 0, 0, 0
            local ok, value = pcall(time, d)
            if ok and tonumber(value) then return value end
        end
    end
    return ts - (ts % 86400)
end

local function GetTrendDayCount(bucketID)
    if bucketID == "24h" then return 1 end
    if bucketID == "7d" then return 7 end
    if bucketID == "14d" then return 14 end
    if bucketID == "30d" then return 30 end
    if bucketID == "90d" or bucketID == "all" then return 90 end
    return 90
end

local function GetDailyTrendBucketLabel(bucketID)
    if bucketID == "all" then return "All time (chart: last 90 days)" end
    return GetBucketLabel(bucketID)
end

local function GetDayLabel(ts, todayStart)
    if ts == todayStart then return "Today" end
    if type(date) == "function" then
        return date("%m/%d", ts)
    end
    return tostring(math.floor((NowEpoch() - ts) / 86400)) .. "d"
end

local function CreateDailyTrendData(bucketID)
    local dayCount = GetTrendDayCount(bucketID)
    local todayStart = GetLocalDayStart(NowEpoch())
    local firstStart = todayStart - ((dayCount - 1) * 86400)
    local days = {}
    for i = 1, dayCount do
        days[i] = {
            t = firstStart + ((i - 1) * 86400),
            income = 0,
            expenses = 0,
            net = 0,
            count = 0,
        }
    end
    return {
        days = days,
        dayCount = dayCount,
        todayStart = todayStart,
        firstStart = firstStart,
        maxAbs = 1,
    }
end

local function AddDailyTrendEntry(data, entry)
    if not (data and entry) then return end
    local entryTime = tonumber(entry.t)
    if entryTime and entryTime >= data.firstStart then
        local index = math.floor((entryTime - data.firstStart) / 86400) + 1
        local day = data.days and data.days[index]
        if day then
            local amount = tonumber(entry.amount) or 0
            if amount > 0 then
                day.income = day.income + amount
            elseif amount < 0 then
                day.expenses = day.expenses + amount
            end
            day.net = day.net + amount
            day.count = day.count + 1
            data.maxAbs = math.max(data.maxAbs or 1, math.abs(day.income), math.abs(day.expenses), math.abs(day.net))
        end
    end
end

function module:BuildDailyTrendData(filtered, bucketID)
    local data = CreateDailyTrendData(bucketID)
    for _, row in ipairs(filtered or {}) do
        AddDailyTrendEntry(data, row.entry)
    end
    return data
end

local function HideObjectPool(pool)
    if type(pool) ~= "table" then return end
    for _, object in pairs(pool) do
        if object.Hide then object:Hide() end
    end
end

function module:EnsureDailyTrendChart()
    local f = self.window
    if not (f and f._content) then return nil end
    if f._trendChart then return f._trendChart end

    local chart = CreateFrame("Frame", nil, f._content, "BackdropTemplate")
    chart:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    chart._title = chart:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chart._title:SetPoint("TOPLEFT", chart, "TOPLEFT", 12, -10)
    chart._title:SetJustifyH("LEFT")
    chart._subtitle = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart._subtitle:SetPoint("TOPLEFT", chart._title, "BOTTOMLEFT", 0, -4)
    chart._subtitle:SetJustifyH("LEFT")
    chart._legend = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart._legend:SetPoint("TOPRIGHT", chart, "TOPRIGHT", -12, -10)
    chart._legend:SetJustifyH("RIGHT")
    chart._summary = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart._summary:SetPoint("TOPLEFT", chart._subtitle, "BOTTOMLEFT", 0, -6)
    chart._summary:SetJustifyH("LEFT")
    chart._gridPool = {}
    chart._barPool = {}
    chart._linePool = {}
    chart._glowPool = {}
    chart._pointPool = {}
    chart._labelPool = {}
    chart._hitPool = {}
    f._trendChart = chart
    return chart
end

function module:HideDailyTrendChart()
    local chart = self.window and self.window._trendChart
    if chart then chart:Hide() end
end

local function EnsureChartTexture(pool, index, parent, layer)
    local tex = pool[index]
    if not tex then
        tex = parent:CreateTexture(nil, layer or "ARTWORK")
        tex:SetTexture(WHITE_TEXTURE)
        pool[index] = tex
    end
    return tex
end

local function EnsureChartLabel(pool, index, parent)
    local fs = pool[index]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        pool[index] = fs
    end
    return fs
end

local function EnsureChartLine(pool, index, parent)
    if not parent.CreateLine then return nil end
    local line = pool[index]
    if not line then
        line = parent:CreateLine(nil, "ARTWORK")
        pool[index] = line
    end
    return line
end

function module:RenderDailyTrendChart(filtered, bucketID, incomeTotal, expenseTotal, palette)
    local f = self.window
    local chart = self:EnsureDailyTrendChart()
    if not (f and f._content and chart) then return end

    local data = type(filtered) == "table" and filtered.days and filtered
        or self:BuildDailyTrendData(filtered, bucketID)
    local days = data.days or {}
    local scrollH = (f._scroll and f._scroll:GetHeight()) or 260
    local chartH = math.max(200, scrollH - 8)
    local chartW = math.max(360, f._content:GetWidth() or 360)
    chart:ClearAllPoints()
    chart:SetPoint("TOPLEFT", f._content, "TOPLEFT", 0, 0)
    chart:SetSize(chartW, chartH)
    chart:SetBackdropColor(palette.tabOffBg[1], palette.tabOffBg[2], palette.tabOffBg[3], 0.42)
    chart:SetBackdropBorderColor(unpack(palette.rowSep))
    chart:Show()
    chart._title:SetWidth(chartW - 24)
    chart._subtitle:SetWidth(chartW - 24)
    chart._legend:SetWidth(math.min(360, math.floor(chartW * 0.50)))

    HideObjectPool(chart._gridPool)
    HideObjectPool(chart._barPool)
    HideObjectPool(chart._linePool)
    HideObjectPool(chart._glowPool)
    HideObjectPool(chart._pointPool)
    HideObjectPool(chart._labelPool)
    for _, hit in ipairs(chart._hitPool) do if hit.Hide then hit:Hide() end end

    chart._title:SetText("Daily Trend")
    chart._title:SetTextColor(unpack(palette.colHeader))
    chart._subtitle:SetText(GetDailyTrendBucketLabel(bucketID) .. "  -  " .. self:GetWindowShardFilterTitle())
    chart._subtitle:SetTextColor(unpack(palette.dimText))
    local function ChartColorHex(c)
        return string.format("|cFF%02x%02x%02x", math.floor((c[1] or 0) * 255), math.floor((c[2] or 0) * 255), math.floor((c[3] or 0) * 255))
    end
    local showCumSetting = self.settings and self.settings.chartCumulativeLine == true
    local showAvgSetting = self.settings and self.settings.chartShowAvgLine == true
    local legendParts = ChartColorHex(palette.posAmount) .. "Income|r  " .. ChartColorHex(palette.negAmount) .. "Expenses|r  " .. ChartColorHex(palette.colHeader) .. "Net|r"
    if showCumSetting then
        legendParts = legendParts .. "  |cFF4DD9FFP&L|r"
    end
    if showAvgSetting then
        legendParts = legendParts .. "  |cFFccccccAvg|r"
    end
    chart._legend:SetText(legendParts)
    chart._legend:SetTextColor(1, 1, 1, 1)
    if chart._summary then
        if data.loadingText then
            chart._summary:SetText(data.loadingText)
            chart._summary:SetTextColor(unpack(palette.dimText))
            chart._summary:Show()
        else
            chart._summary:SetText("")
            chart._summary:Hide()
        end
    end

    local left = 64
    local right = 16
    local bottom = 48
    local top = 66
    local plotW = math.max(160, chartW - left - right)
    local plotH = math.max(96, chartH - top - bottom)
    local zeroY = bottom + math.floor(plotH / 2)
    local scaleH = math.max(24, math.floor(plotH / 2) - 18)
    local maxAbs = math.max(1, data.maxAbs or 1)

    local showCumulative = self.settings and self.settings.chartCumulativeLine == true
    local showAvgLine = self.settings and self.settings.chartShowAvgLine == true
    local avgWindow = math.min(3, #days)
    local cumValues, avgValues = {}, {}
    local cumSum = 0
    for ci, day in ipairs(days) do
        cumSum = cumSum + (day.net or 0)
        cumValues[ci] = cumSum
        local avgStart = math.max(1, ci - avgWindow + 1)
        local avgSum = 0
        for cj = avgStart, ci do avgSum = avgSum + (days[cj].net or 0) end
        avgValues[ci] = avgSum / (ci - avgStart + 1)
    end
    if showCumulative then
        for ci = 1, #cumValues do
            maxAbs = math.max(maxAbs, math.abs(cumValues[ci]))
        end
    end
    if showAvgLine then
        for ci = 1, #avgValues do
            maxAbs = math.max(maxAbs, math.abs(avgValues[ci]))
        end
    end

    local gridYs = { zeroY + scaleH, zeroY, zeroY - scaleH }
    for i, y in ipairs(gridYs) do
        local grid = EnsureChartTexture(chart._gridPool, i, chart, "BACKGROUND")
        grid:ClearAllPoints()
        grid:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", left, y)
        grid:SetSize(plotW, i == 2 and 2 or 1)
        if i == 2 then
            grid:SetVertexColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 0.35)
        else
            grid:SetVertexColor(palette.rowSep[1], palette.rowSep[2], palette.rowSep[3], 0.28)
        end
        grid:Show()
    end

    local axisLabels = {
        { text = FormatCompactMoney(maxAbs), y = zeroY + scaleH - 6 },
        { text = "0", y = zeroY - 6 },
        { text = "-" .. FormatCompactMoney(maxAbs), y = zeroY - scaleH - 6 },
    }
    local labelIndex = 1
    for _, labelInfo in ipairs(axisLabels) do
        local label = EnsureChartLabel(chart._labelPool, labelIndex, chart)
        labelIndex = labelIndex + 1
        label:ClearAllPoints()
        label:SetPoint("LEFT", chart, "BOTTOMLEFT", 6, labelInfo.y)
        label:SetSize(52, 12)
        label:SetJustifyH("RIGHT")
        label:SetText(labelInfo.text)
        label:SetTextColor(unpack(palette.dimText))
        label:Show()
    end

    local dayCount = math.max(1, #days)
    local slotW = plotW / dayCount
    local barW = math.max(4, math.min(16, math.floor(slotW * 0.25)))
    local labelEvery = math.max(1, math.ceil(dayCount / 7))
    local showBarLabels = self.settings and self.settings.chartBarLabels ~= false
    local prevNetX, prevNetY
    local prevCumX, prevCumY
    local prevAvgX, prevAvgY
    local barIndex, pointIndex, lineIndex, glowIndex = 1, 1, 1, 1
    for i, day in ipairs(days) do
        local x = left + ((i - 0.5) * slotW)
        local incomeH = math.floor(math.abs(day.income or 0) / maxAbs * scaleH)
        local expenseH = math.floor(math.abs(day.expenses or 0) / maxAbs * scaleH)
        local netY = zeroY + math.floor(((day.net or 0) / maxAbs) * scaleH)
        local topLabelY = bottom + plotH - 16
        local bottomLabelY = bottom + 16

        if incomeH > 0 then
            local bar = EnsureChartTexture(chart._barPool, barIndex, chart, "ARTWORK")
            barIndex = barIndex + 1
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", math.floor(x - barW - 1), zeroY)
            bar:SetSize(barW, math.max(2, incomeH))
            bar:SetVertexColor(palette.posAmount[1], palette.posAmount[2], palette.posAmount[3], 0.80)
            bar:Show()
            if showBarLabels then
                local lbl = EnsureChartLabel(chart._labelPool, labelIndex, chart)
                labelIndex = labelIndex + 1
                lbl:ClearAllPoints()
                lbl:SetPoint("BOTTOM", chart, "BOTTOMLEFT", math.floor(x - barW / 2 - 1), math.min(zeroY + incomeH + 2, topLabelY))
                lbl:SetSize(math.max(36, slotW), 10)
                lbl:SetJustifyH("CENTER")
                lbl:SetText(FormatCompactMoney(math.abs(day.income or 0)))
                lbl:SetTextColor(palette.posAmount[1], palette.posAmount[2], palette.posAmount[3], 1)
                lbl:Show()
            end
        end

        if expenseH > 0 then
            local bar = EnsureChartTexture(chart._barPool, barIndex, chart, "ARTWORK")
            barIndex = barIndex + 1
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", math.floor(x + 1), zeroY)
            bar:SetSize(barW, math.max(2, expenseH))
            bar:SetVertexColor(palette.negAmount[1], palette.negAmount[2], palette.negAmount[3], 0.78)
            bar:Show()
            if showBarLabels then
                local lbl = EnsureChartLabel(chart._labelPool, labelIndex, chart)
                labelIndex = labelIndex + 1
                lbl:ClearAllPoints()
                lbl:SetPoint("TOP", chart, "BOTTOMLEFT", math.floor(x + barW / 2 + 1), math.max(zeroY - expenseH - 2, bottomLabelY))
                lbl:SetSize(math.max(36, slotW), 10)
                lbl:SetJustifyH("CENTER")
                lbl:SetText(FormatCompactMoney(math.abs(day.expenses or 0)))
                lbl:SetTextColor(palette.negAmount[1], palette.negAmount[2], palette.negAmount[3], 1)
                lbl:Show()
            end
        end

        -- Daily net line (yellow, always shown)
        local netValue = day.net or 0
        local netY = zeroY + math.floor((netValue / maxAbs) * scaleH)
        local point = EnsureChartTexture(chart._pointPool, pointIndex, chart, "OVERLAY")
        pointIndex = pointIndex + 1
        point:ClearAllPoints()
        point:SetPoint("CENTER", chart, "BOTTOMLEFT", math.floor(x), netY)
        point:SetSize(5, 5)
        point:SetVertexColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 1)
        point:Show()
        if showBarLabels and netValue ~= 0 then
            local lbl = EnsureChartLabel(chart._labelPool, labelIndex, chart)
            labelIndex = labelIndex + 1
            lbl:ClearAllPoints()
            local netAbove = netValue >= 0
            local incomeTop = zeroY + incomeH + 14
            local expenseBot = zeroY - expenseH - 14
            if netAbove then
                local labelY = netY + 4
                if incomeH > 0 and math.abs(labelY - incomeTop) < 14 then
                    labelY = incomeTop + 2
                end
                labelY = math.min(labelY, topLabelY)
                lbl:SetPoint("BOTTOM", chart, "BOTTOMLEFT", math.floor(x), labelY)
            else
                local labelY = netY - 4
                if expenseH > 0 and math.abs(labelY - expenseBot) < 14 then
                    labelY = expenseBot - 2
                end
                labelY = math.max(labelY, bottomLabelY)
                lbl:SetPoint("TOP", chart, "BOTTOMLEFT", math.floor(x), labelY)
            end
            lbl:SetSize(math.max(36, slotW), 10)
            lbl:SetJustifyH("CENTER")
            lbl:SetText(FormatCompactMoney(math.abs(netValue)))
            lbl:SetTextColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 1)
            lbl:Show()
        end

        if prevNetX and prevNetY then
            -- Glow/shadow line: 4px, transparent, beneath the main line
            local glow = EnsureChartLine(chart._glowPool, glowIndex, chart)
            glowIndex = glowIndex + 1
            if glow then
                if glow.ClearAllPoints then glow:ClearAllPoints() end
                glow:SetStartPoint("BOTTOMLEFT", chart, prevNetX, prevNetY)
                glow:SetEndPoint("BOTTOMLEFT", chart, math.floor(x), netY)
                glow:SetThickness(4)
                if glow.SetDrawLayer then glow:SetDrawLayer("ARTWORK", 1) end
                if glow.SetColorTexture then
                    glow:SetColorTexture(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 0.25)
                elseif glow.SetVertexColor then
                    glow:SetVertexColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 0.25)
                end
                glow:Show()
            end
            -- Main line: 2px, full alpha, on top of the glow
            local line = EnsureChartLine(chart._linePool, lineIndex, chart)
            lineIndex = lineIndex + 1
            if line then
                if line.ClearAllPoints then line:ClearAllPoints() end
                line:SetStartPoint("BOTTOMLEFT", chart, prevNetX, prevNetY)
                line:SetEndPoint("BOTTOMLEFT", chart, math.floor(x), netY)
                line:SetThickness(2)
                if line.SetDrawLayer then line:SetDrawLayer("ARTWORK", 2) end
                if line.SetColorTexture then
                    line:SetColorTexture(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 1)
                elseif line.SetVertexColor then
                    line:SetVertexColor(palette.colHeader[1], palette.colHeader[2], palette.colHeader[3], 1)
                end
                line:Show()
            end
        end
        prevNetX, prevNetY = math.floor(x), netY

        -- Cumulative P&L line (cyan, separate overlay)
        if showCumulative then
            local cumY = zeroY + math.floor((cumValues[i] / maxAbs) * scaleH)
            local cumPt = EnsureChartTexture(chart._pointPool, pointIndex, chart, "OVERLAY")
            pointIndex = pointIndex + 1
            cumPt:ClearAllPoints()
            cumPt:SetPoint("CENTER", chart, "BOTTOMLEFT", math.floor(x), cumY)
            cumPt:SetSize(5, 5)
            cumPt:SetVertexColor(0.3, 0.85, 1, 1)
            cumPt:Show()
            if prevCumX and prevCumY then
                local cumLine = EnsureChartLine(chart._linePool, lineIndex, chart)
                lineIndex = lineIndex + 1
                if cumLine then
                    if cumLine.ClearAllPoints then cumLine:ClearAllPoints() end
                    cumLine:SetStartPoint("BOTTOMLEFT", chart, prevCumX, prevCumY)
                    cumLine:SetEndPoint("BOTTOMLEFT", chart, math.floor(x), cumY)
                    cumLine:SetThickness(2)
                    if cumLine.SetColorTexture then
                        cumLine:SetColorTexture(0.3, 0.85, 1, 0.85)
                    elseif cumLine.SetVertexColor then
                        cumLine:SetVertexColor(0.3, 0.85, 1, 0.85)
                    end
                    cumLine:Show()
                end
            end
            prevCumX, prevCumY = math.floor(x), cumY
        end

        -- Moving average line (white, dashed appearance via thinner line)
        if showAvgLine then
            local avgY = zeroY + math.floor((avgValues[i] / maxAbs) * scaleH)
            local avgPt = EnsureChartTexture(chart._pointPool, pointIndex, chart, "OVERLAY")
            pointIndex = pointIndex + 1
            avgPt:ClearAllPoints()
            avgPt:SetPoint("CENTER", chart, "BOTTOMLEFT", math.floor(x), avgY)
            avgPt:SetSize(3, 3)
            avgPt:SetVertexColor(1, 1, 1, 0.7)
            avgPt:Show()
            if prevAvgX and prevAvgY then
                local avgLine = EnsureChartLine(chart._linePool, lineIndex, chart)
                lineIndex = lineIndex + 1
                if avgLine then
                    if avgLine.ClearAllPoints then avgLine:ClearAllPoints() end
                    avgLine:SetStartPoint("BOTTOMLEFT", chart, prevAvgX, prevAvgY)
                    avgLine:SetEndPoint("BOTTOMLEFT", chart, math.floor(x), avgY)
                    avgLine:SetThickness(1)
                    if avgLine.SetColorTexture then
                        avgLine:SetColorTexture(1, 1, 1, 0.45)
                    elseif avgLine.SetVertexColor then
                        avgLine:SetVertexColor(1, 1, 1, 0.45)
                    end
                    avgLine:Show()
                end
            end
            prevAvgX, prevAvgY = math.floor(x), avgY
        end

        if i == 1 or i == dayCount or ((i - 1) % labelEvery == 0) then
            local label = EnsureChartLabel(chart._labelPool, labelIndex, chart)
            labelIndex = labelIndex + 1
            label:ClearAllPoints()
            label:SetPoint("TOP", chart, "BOTTOMLEFT", math.floor(x), bottom - 8)
            label:SetSize(math.max(36, slotW), 12)
            label:SetJustifyH("CENTER")
            label:SetText(GetDayLabel(day.t, data.todayStart))
            label:SetTextColor(unpack(palette.dimText))
            label:Show()
        end
    end

    -- Per-day hover hit zones for tooltips
    local hitIndex = 0
    for i, day in ipairs(days) do
        hitIndex = hitIndex + 1
        local hit = chart._hitPool[hitIndex]
        if not hit then
            hit = CreateFrame("Button", nil, chart)
            hit:SetFrameLevel((chart:GetFrameLevel() or 0) + 10)
            hit._highlight = hit:CreateTexture(nil, "HIGHLIGHT")
            hit._highlight:SetAllPoints()
            hit._highlight:SetColorTexture(1, 1, 1, 0.07)
            chart._hitPool[hitIndex] = hit
        end
        local hitX = left + ((i - 1) * slotW)
        hit:ClearAllPoints()
        hit:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", math.floor(hitX), bottom)
        hit:SetSize(math.max(4, math.floor(slotW)), plotH)
        hit._dayData = day
        hit._dayLabel = GetDayLabel(day.t, data.todayStart)
        hit._palette = palette
        -- Stamp cumulative P&L + moving-average for this day so the tooltip
        -- can show them in step with the visible overlay lines. The two
        -- _show flags mirror the legend: if the overlay line is hidden, the
        -- corresponding tooltip line is hidden too.
        hit._cumValue = cumValues[i]
        hit._avgValue = avgValues[i]
        hit._showCum = showCumulative
        hit._showAvg = showAvgLine
        hit._avgWindow = avgWindow
        hit:SetScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            _G.GameTooltip:ClearLines()
            _G.GameTooltip:AddLine(self._dayLabel, 1, 1, 1)
            local p = self._palette
            local d = self._dayData
            _G.GameTooltip:AddDoubleLine(
                "Income",
                FormatCompactMoney(d.income or 0),
                p.posAmount[1], p.posAmount[2], p.posAmount[3],
                p.posAmount[1], p.posAmount[2], p.posAmount[3])
            _G.GameTooltip:AddDoubleLine(
                "Expenses",
                FormatCompactMoney(math.abs(d.expenses or 0)),
                p.negAmount[1], p.negAmount[2], p.negAmount[3],
                p.negAmount[1], p.negAmount[2], p.negAmount[3])
            _G.GameTooltip:AddDoubleLine(
                "Net",
                ((d.net or 0) >= 0 and "+" or "-") .. FormatCompactMoney(math.abs(d.net or 0)),
                p.colHeader[1], p.colHeader[2], p.colHeader[3],
                p.colHeader[1], p.colHeader[2], p.colHeader[3])
            if self._showCum then
                local cum = self._cumValue or 0
                _G.GameTooltip:AddDoubleLine(
                    "P&L",
                    (cum >= 0 and "+" or "-") .. FormatCompactMoney(math.abs(cum)),
                    0.30, 0.85, 1.00,
                    0.30, 0.85, 1.00)
            end
            if self._showAvg then
                local avg = self._avgValue or 0
                local label = (self._avgWindow and self._avgWindow > 1)
                    and ("Avg (" .. tostring(self._avgWindow) .. "d)")
                    or "Avg"
                _G.GameTooltip:AddDoubleLine(
                    label,
                    (avg >= 0 and "+" or "-") .. FormatCompactMoney(math.abs(avg)),
                    0.80, 0.80, 0.80,
                    0.80, 0.80, 0.80)
            end
            _G.GameTooltip:AddDoubleLine(
                "Transactions",
                tostring(d.count or 0),
                0.75, 0.75, 0.75,
                1, 1, 1)
            _G.GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        hit:Show()
    end
    -- Hide unused hit zones from a previous render with more days
    for hi = hitIndex + 1, #chart._hitPool do
        if chart._hitPool[hi] then chart._hitPool[hi]:Hide() end
    end

    f._content:SetHeight(chartH + 8)
end

local function TextContains(haystack, needle)
    if needle == "" then return true end
    if type(haystack) ~= "string" then return false end
    return string.find(string.lower(haystack), needle, 1, true) ~= nil
end

local function EntryMatchesSearch(entry, rawSearch)
    local search = string.lower(rawSearch or "")
    if search == "" then return true end
    if TextContains(entry.kind, search) then return true end
    if TextContains(module:GetKindLabel(entry.kind), search) then return true end
    if TextContains(entry.item, search) then return true end
    if TextContains(entry.itemName, search) then return true end
    if TextContains(entry.who, search) then return true end
    if TextContains(entry.workOrderType, search) then return true end
    if TextContains(entry.questName, search) then return true end
    if TextContains(entry.subject, search) then return true end
    if TextContains(module:GetCategoryLabel(module:GetEntryCategory(entry)), search) then return true end
    if TextContains(entry.itemClassName, search) then return true end
    if TextContains(entry.itemSubClassName, search) then return true end
    if tonumber(entry.itemClassID) == ITEM_CLASS_HOUSING and TextContains("housing", search) then return true end
    if TextContains(tostring(entry.itemID or ""), search) then return true end
    return false
end

local function EntryDetailText(entry)
    local detail = ""
    if entry.kind == module.CONSTANTS.KIND_QUEST then
        return entry.questName or (entry.questID and ("Quest #" .. tostring(entry.questID))) or tostring(entry.who or "")
    end
    if entry.item then
        detail = tostring(entry.item)
    elseif entry.itemName then
        detail = tostring(entry.itemName)
    elseif entry.itemID then
        detail = "itemID:" .. tostring(entry.itemID)
    end
    if entry.qty and entry.qty > 1 then detail = detail .. " x" .. tostring(entry.qty) end
    if entry.kind == module.CONSTANTS.KIND_WORK_ORDER then
        if entry.workOrderType and entry.workOrderType ~= "" then
            if detail ~= "" then detail = detail .. "  " end
            detail = detail .. "[" .. tostring(entry.workOrderType) .. "]"
        end
        if entry.consortiumCut and tonumber(entry.consortiumCut) and tonumber(entry.consortiumCut) > 0 then
            if detail ~= "" then detail = detail .. "  " end
            detail = detail .. "Cut " .. module:FormatMoney(0 - tonumber(entry.consortiumCut))
        end
    end
    if tonumber(entry.itemClassID) == ITEM_CLASS_HOUSING then
        if detail ~= "" then detail = detail .. "  " end
        detail = detail .. "[Housing]"
    end
    return detail
end

function module:GetEntryTypeLabel(entry)
    if type(entry) ~= "table" then return "" end
    if entry.itemID or entry.itemLink or entry.item or entry.itemClassID or entry.itemClassName then
        return self:GetItemTypeLabel(entry)
    end
    return self:GetCategoryLabel(self:GetEntryCategory(entry))
end

function module:GetGroupKey(entry, mode, shardKey)
    if mode == "category" then
        local category = self:GetEntryCategory(entry)
        return category, self:GetCategoryLabel(category), nil
    end
    if mode == "itemType" then
        local label = self:GetItemTypeLabel(entry)
        return tostring(label), tostring(label), nil
    end
    if mode == "housing" then
        if self:IsHousingEntry(entry) then
            return "housing", "Housing", entry.itemLink
        end
        if entry.itemID or entry.itemLink or entry.item or entry.itemName or entry.itemClassID or entry.itemClassName then
            return "other_items", "Other Items", entry.itemLink
        end
        return "no_item", "No Item", nil
    end
    if mode == "item" then
        local label = entry.itemName or entry.item or "No item"
        return tostring(entry.itemID or label), tostring(label), entry.itemLink
    end
    if mode == "who" then
        local label = entry.who or "No character"
        return tostring(label), tostring(label), nil
    end
    if mode == "character" then
        local key = shardKey or ""
        return tostring(key), self:GetShardLabel(key), nil
    end
    local kind = entry.kind or module.CONSTANTS.KIND_UNKNOWN
    return kind, self:GetKindLabel(kind), entry.itemLink
end

function module:GetWindowColumns()
    local windowSettings = EnsureWindowSettings(self.settings)
    return windowSettings and windowSettings.columns or {}
end

function module:IsWindowColumnVisible(column)
    local columns = self:GetWindowColumns()
    return columns[column] ~= false
end

function module:ToggleWindowColumn(column)
    local windowSettings = EnsureWindowSettings(self.settings)
    if not (windowSettings and type(windowSettings.columns) == "table") then return end
    windowSettings.columns[column] = not (windowSettings.columns[column] ~= false)
    local anyVisible = false
    for _, key in ipairs(COLUMN_ORDER) do
        if windowSettings.columns[key] ~= false then anyVisible = true; break end
    end
    if not anyVisible then
        windowSettings.columns.detail = true
    end
    self:RefreshWindow()
end

function module:GetActiveSourceFilterLabel()
    local hidden = 0
    for _, category in ipairs(CATEGORY_ORDER) do
        if not self:IsCategoryVisible(category) then hidden = hidden + 1 end
    end
    if hidden == 0 then return "Sources: All" end
    return ("Sources: %d hidden"):format(hidden)
end

function module:LayoutWindowToolbar()
    local f = self.window
    if not (f and f._timeBar and f._search and f._bucketSelect) then return end
    local timeBar = f._timeBar
    local controlH = module.WINDOW.FILTER_BAR_H - 4
    local gap = 8
    local edge = 2
    local labelW = 62
    local bucketW = 140

    -- Tab bar: distribute buttons evenly
    if f._tabBar then
        local tabGap = 4
        local tabBarW = f._tabBar:GetWidth()
        if not tabBarW or tabBarW < 1 then
            tabBarW = module.WINDOW.WIDTH - module.WINDOW.PADDING * 2
        end
        local tabW = math.max(60, math.floor((tabBarW - edge * 2 - tabGap * (#TABS - 1)) / #TABS))
        local tabH = module.WINDOW.TAB_BAR_H - 4
        local tx = edge
        for _, tab in ipairs(TABS) do
            local btn = f._tabs[tab.id]
            if btn then
                btn:ClearAllPoints()
                btn:SetSize(tabW, tabH)
                btn:SetPoint("TOPLEFT", f._tabBar, "TOPLEFT", tx, -2)
                tx = tx + tabW + tabGap
            end
        end
    end

    -- BucketSelect anchored from right of timeBar
    f._bucketSelect:SetSize(bucketW, controlH)
    f._bucketSelect:ClearAllPoints()
    f._bucketSelect:SetPoint("RIGHT", timeBar, "RIGHT", -edge, 0)

    -- Search fills remaining space (left edge to bucket)
    f._search:ClearAllPoints()
    if f._searchLabel then
        f._searchLabel:ClearAllPoints()
        f._searchLabel:SetWidth(labelW)
        f._searchLabel:SetJustifyH("LEFT")
        f._searchLabel:SetPoint("LEFT", timeBar, "LEFT", edge + 2, 0)
        f._search:SetPoint("LEFT", timeBar, "LEFT", edge + labelW, 0)
    else
        f._search:SetPoint("LEFT", timeBar, "LEFT", edge, 0)
    end
    f._search:SetPoint("RIGHT", f._bucketSelect, "LEFT", -gap, 0)
    f._search:SetHeight(controlH)

    -- CategoryBar: always below timeBar
    if not (f._categoryBar and f._characterSelect and f._filterSelect and f._itemTypeSelect and f._columnSelect) then return end
    local categoryBar = f._categoryBar
    categoryBar:ClearAllPoints()
    categoryBar:SetPoint("TOPLEFT", timeBar, "BOTTOMLEFT", 0, -4)
    categoryBar:SetPoint("TOPRIGHT", timeBar, "BOTTOMRIGHT", 0, -4)

    local categoryWidth = categoryBar:GetWidth()
    if not categoryWidth or categoryWidth < 1 then
        categoryWidth = module.WINDOW.WIDTH - module.WINDOW.PADDING * 2
    end
    local columnShown = f._columnSelect:IsShown()
    local slots = columnShown and 4 or 3
    local slotW = math.max(96, math.floor((categoryWidth - edge * 2 - gap * (slots - 1)) / slots))
    local x = edge

    local function placeToolbarControl(control)
        control:ClearAllPoints()
        control:SetSize(slotW, controlH)
        control:SetPoint("LEFT", categoryBar, "LEFT", x, 0)
        x = x + slotW + gap
    end

    placeToolbarControl(f._characterSelect)
    placeToolbarControl(f._filterSelect)
    placeToolbarControl(f._itemTypeSelect)
    if columnShown then
        placeToolbarControl(f._columnSelect)
    end

    -- GroupBar: anchored below categoryBar, same slot width as categoryBar
    if f._groupSelect and f._groupBar then
        f._groupBar:ClearAllPoints()
        f._groupBar:SetPoint("TOPLEFT", categoryBar, "BOTTOMLEFT", 0, -4)
        f._groupBar:SetPoint("TOPRIGHT", categoryBar, "BOTTOMRIGHT", 0, -4)
        f._groupSelect:ClearAllPoints()
        f._groupSelect:SetSize(slotW, controlH)
        f._groupSelect:SetPoint("LEFT", f._groupBar, "LEFT", edge, 0)
        if f._trendOptionsSelect then
            f._trendOptionsSelect:ClearAllPoints()
            f._trendOptionsSelect:SetSize(slotW, controlH)
            f._trendOptionsSelect:SetPoint("LEFT", f._groupSelect, "RIGHT", gap, 0)
        end
    end

    -- ColHeader: below groupBar when visible, else below categoryBar
    if f._colHeader then
        f._colHeader:ClearAllPoints()
        if f._groupBar and f._groupBar:IsShown() then
            f._colHeader:SetPoint("TOPLEFT", f._groupBar, "BOTTOMLEFT", 0, -8)
            f._colHeader:SetPoint("TOPRIGHT", f._groupBar, "BOTTOMRIGHT", 0, -8)
        else
            f._colHeader:SetPoint("TOPLEFT", categoryBar, "BOTTOMLEFT", 0, -8)
            f._colHeader:SetPoint("TOPRIGHT", categoryBar, "BOTTOMRIGHT", 0, -8)
        end
    end
end

function module:ApplyLedgerColumnLayout()
    if not self.window then return end
    local f = self.window
    local W = module.WINDOW
    local columns = self:GetWindowColumns()
    local visible = {}
    for _, key in ipairs(COLUMN_ORDER) do
        visible[key] = columns[key] ~= false
    end
    if not (visible.time or visible.source or visible.itemType or visible.who or visible.amount or visible.detail) then
        visible.detail = true
    end

    local inner = (f._content and f._content:GetWidth()) or (f:GetWidth() - 2 * W.PADDING - 24)
    local widths = {
        time = visible.time and W.COL_TIME or 0,
        source = visible.source and W.COL_KIND or 0,
        itemType = visible.itemType and W.COL_TYPE or 0,
        who = visible.who and W.COL_WHO or 0,
        amount = visible.amount and W.COL_AMOUNT or 0,
        detail = 0,
    }
    local fixed = widths.time + widths.source + widths.itemType + widths.who + widths.amount
    widths.detail = visible.detail and math.max(120, inner - fixed - 8) or 0
    local layoutPalette = WindowPalette()

    local offset = 0
    local function place(fs, key, justify)
        if not fs then return end
        if not visible[key] then
            fs:Hide()
            return
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", fs:GetParent(), "LEFT", offset, 0)
        fs:SetWidth(widths[key] - 6)
        fs:SetJustifyH(justify or "LEFT")
        fs:Show()
        offset = offset + widths[key]
    end

    local function hideMoney(row)
        if row._amount then row._amount:Hide() end
        if row._amountSign then row._amountSign:Hide() end
        if row._amountGold then row._amountGold:Hide() end
        if row._amountSilver then row._amountSilver:Hide() end
        if row._amountCopper then row._amountCopper:Hide() end
    end

    local function placeMoney(row)
        if not row then return end
        if not visible.amount or row._noMoney then
            row._amountCompact = false
            hideMoney(row)
            return
        end
        local parent = row._amountSign and row._amountSign:GetParent()
        if not parent then return end
        local start = offset
        local texts = BuildMoneyTexts(row._amountCopperValue or 0)
        local signW = 14
        local goldNeed = texts.gold ~= "" and math.ceil(TextWidth(row._amountGold, texts.gold) + 4) or 0
        local silverNeed = texts.silver ~= "" and math.ceil(TextWidth(row._amountSilver, texts.silver) + 4) or 0
        local copperNeed = math.ceil(TextWidth(row._amountCopper, texts.copper) + 4)
        local fullNeed = signW + goldNeed + silverNeed + copperNeed
        row._amountCompact = ShouldAlwaysCompactMoney() or fullNeed > math.max(0, widths.amount - 4)
        local parts
        if row._amountCompact then
            local goldW = math.max(0, widths.amount - signW - 2)
            parts = {
                { fs = row._amountSign, width = signW, show = true },
                { fs = row._amountGold, width = goldW, show = true },
                { fs = row._amountSilver, width = 0, show = false },
                { fs = row._amountCopper, width = 0, show = false },
            }
        else
            local remainingGoldW = math.max(goldNeed, widths.amount - signW - silverNeed - copperNeed)
            parts = {
                { fs = row._amountSign, width = signW, show = true },
                { fs = row._amountGold, width = remainingGoldW, show = true },
                { fs = row._amountSilver, width = silverNeed, show = true },
                { fs = row._amountCopper, width = copperNeed, show = true },
            }
        end
        local partOffset = start
        if row._amount then row._amount:Hide() end
        for _, part in ipairs(parts) do
            if part.fs then
                if part.show then
                    part.fs:ClearAllPoints()
                    part.fs:SetPoint("LEFT", parent, "LEFT", partOffset, 0)
                    part.fs:SetWidth(math.max(0, part.width - 2))
                    part.fs:SetJustifyH("RIGHT")
                    part.fs:Show()
                else
                    part.fs:SetText("")
                    part.fs:Hide()
                end
            end
            partOffset = partOffset + part.width
        end
        SetRowMoney(row, row._amountCopperValue or 0, row._noMoney, layoutPalette)
        offset = offset + widths.amount
    end

    offset = 0
    place(f._hTime, "time", "LEFT")
    place(f._hKind, "source", "LEFT")
    place(f._hType, "itemType", "LEFT")
    place(f._hWho, "who", "LEFT")
    place(f._hAmount, "amount", "RIGHT")
    place(f._hDetail, "detail", "LEFT")

    local function hideRegularRowFields(row)
        if row._time then row._time:Hide() end
        if row._kind then row._kind:Hide() end
        if row._type then row._type:Hide() end
        if row._who then row._who:Hide() end
        if row._detail then row._detail:Hide() end
        hideMoney(row)
    end

    for _, row in ipairs(f._rows or {}) do
        -- Skip pooled rows that aren't currently visible. RefreshWindow hides
        -- leftover rows beyond the filtered set, and laying out hidden rows
        -- (especially the ~500 cap when switching from a wide bucket to 24h)
        -- is wasted SetPoint/Show churn.
        if not row:IsShown() then
            -- nothing to do
        elseif row._sectionHeader then
            hideRegularRowFields(row)
            if row._sectionTitle then
                row._sectionTitle:ClearAllPoints()
                row._sectionTitle:SetPoint("LEFT", row, "LEFT", 0, 0)
                row._sectionTitle:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row._sectionTitle:Show()
            end
            if row._sectionLine then
                row._sectionLine:ClearAllPoints()
                row._sectionLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row._sectionLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 0)
                row._sectionLine:Show()
            end
            if row._bar then row._bar:Hide() end
        else
            if row._sectionTitle then row._sectionTitle:Hide() end
            if row._sectionLine then row._sectionLine:Hide() end
            offset = 0
            place(row._time, "time", "LEFT")
            place(row._kind, "source", "LEFT")
            place(row._type, "itemType", "LEFT")
            place(row._who, "who", "LEFT")
            placeMoney(row)
            place(row._detail, "detail", "LEFT")
            if row._bar then
                if row._barFraction and visible.detail and row._detail:IsShown() then
                    row._bar:ClearAllPoints()
                    row._bar:SetPoint("LEFT", row._detail, "LEFT", 0, 0)
                    row._bar:SetHeight(module.WINDOW.ROW_HEIGHT - 4)
                    row._bar:SetWidth(math.max(2, row._detail:GetWidth() * row._barFraction))
                    row._bar:Show()
                else
                    row._bar:Hide()
                end
            end
        end
    end
end

function module:ApplyWindowPosition()
    if not self.window then return end
    local windowSettings = EnsureWindowSettings(self.settings)
    self.window:ClearAllPoints()
    if windowSettings then
        self.window:SetPoint(
            windowSettings.point,
            UIParent,
            windowSettings.relativePoint,
            windowSettings.x,
            windowSettings.y
        )
    else
        self.window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function module:SaveWindowPosition()
    if not (self.window and self.settings) then return end
    local point, _, relativePoint, x, y = self.window:GetPoint(1)
    local windowSettings = EnsureWindowSettings(self.settings)
    if not windowSettings then return end
    windowSettings.point = point or "CENTER"
    windowSettings.relativePoint = relativePoint or "CENTER"
    windowSettings.x = tonumber(x) or 0
    windowSettings.y = tonumber(y) or 0
end

function module:ApplyWindowSize()
    if not self.window then return end
    local windowSettings = EnsureWindowSettings(self.settings)
    local width = windowSettings and windowSettings.width or module.WINDOW.WIDTH
    local height = windowSettings and windowSettings.height or module.WINDOW.HEIGHT
    self.window:SetSize(width, height)
end

function module:SaveWindowSize()
    if not (self.window and self.settings) then return end
    local windowSettings = EnsureWindowSettings(self.settings)
    if not windowSettings then return end
    local width, height = self.window:GetSize()
    windowSettings.width = Clamp(width or module.WINDOW.WIDTH, module.WINDOW.MIN_WIDTH, module.WINDOW.MAX_WIDTH)
    windowSettings.height = Clamp(height or module.WINDOW.HEIGHT, module.WINDOW.MIN_HEIGHT, module.WINDOW.MAX_HEIGHT)
end

function module:LayoutWindowFooter()
    local f = self.window
    if not (f and f._footerBar and f._footerCount and f._footerIncome and f._footerExpenses and f._footerNet) then return end
    local width = f._footerBar:GetWidth()
    local countWidth = 124
    local gap = 8
    local available = math.max(module.WINDOW.MIN_WIDTH - 2 * module.WINDOW.PADDING, width)
    local groupWidth = math.floor((available - countWidth - gap * 3) / 3)
    local incomeX = countWidth + gap
    local expensesX = incomeX + groupWidth + gap
    local netX = expensesX + groupWidth + gap

    if not f._footerSections then
        f._footerSections = {}
        for i = 1, 4 do
            local tex = f._footerBar:CreateTexture(nil, "BACKGROUND")
            tex:SetTexture(WHITE_TEXTURE)
            f._footerSections[i] = tex
        end
    end

    local p = WindowPalette()
    local sectionXs = { 0, incomeX, expensesX, netX }
    local sectionWs = { countWidth, groupWidth, groupWidth, groupWidth }
    for i, tex in ipairs(f._footerSections) do
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", f._footerBar, "LEFT", sectionXs[i], 0)
        tex:SetWidth(sectionWs[i])
        tex:SetHeight(module.WINDOW.FOOTER_H - 4)
        -- Slightly stronger fill than the rest of the window so the all-time
        -- totals band stands out as a distinct footer.
        tex:SetVertexColor(p.tabOffBg[1], p.tabOffBg[2], p.tabOffBg[3], 0.30)
    end
    if f._footerTopLine then
        local hc = p.colHeader or p.neutralText
        f._footerTopLine:SetColorTexture(hc[1], hc[2], hc[3], 0.55)
    end

    local function place(fs, x, w)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", f._footerBar, "LEFT", x, 0)
        fs:SetWidth(w)
    end
    local function placeMoneyGroup(group, x)
        local innerX = x + 6
        local innerW = math.max(0, groupWidth - 12)
        local labelW = math.min(64, math.max(48, math.floor(innerW * 0.32)))
        local signW = 12
        local moneyW = math.max(0, innerW - labelW - signW - 8)
        local texts = BuildMoneyTexts(group._lastCopper or 0)
        local goldNeed = texts.gold ~= "" and math.ceil(TextWidth(group.gold, texts.gold) + 4) or 0
        local silverNeed = texts.silver ~= "" and math.ceil(TextWidth(group.silver, texts.silver) + 4) or 0
        local copperNeed = math.ceil(TextWidth(group.copper, texts.copper) + 4)
        local compact = ShouldAlwaysCompactMoney() or (goldNeed + silverNeed + copperNeed) > moneyW
        group._compact = compact
        local goldW = compact and moneyW or math.max(goldNeed, moneyW - silverNeed - copperNeed)
        local silverW = compact and 0 or silverNeed
        local copperW = compact and 0 or copperNeed
        place(group.label, innerX, labelW)
        place(group.sign, innerX + labelW + 2, signW)
        place(group.gold, innerX + labelW + signW + 2, goldW)
        place(group.silver, innerX + labelW + signW + goldW + 2, silverW)
        place(group.copper, innerX + labelW + signW + goldW + silverW + 2, copperW)
        if group._lastCopper ~= nil then
            SetMoneyParts(group, group._lastCopper, p)
        end
    end

    place(f._footerCount, 6, countWidth - 12)
    placeMoneyGroup(f._footerIncome, incomeX)
    placeMoneyGroup(f._footerExpenses, expensesX)
    placeMoneyGroup(f._footerNet, netX)
end

-- Minimap button lives in Modules/AccountingTracker/Minimap.lua (loaded
-- after this file via the TOC), which attaches:
--   module:UpdateMinimapButtonPosition / SaveMinimapButtonPosition /
--   StopMinimapButtonDrag / ResetMinimapButtonPosition / EnsureMinimapButton /
--   UpdateMinimapButton

function module:OpenAccountingOptions()
    if ns.SlashCommands and ns.SlashCommands.RequestOptionsOpen then
        ns.SlashCommands:RequestOptionsOpen("accounting_tracker")
    elseif ns.OptionsPanel and ns.OptionsPanel.Open then
        ns.OptionsPanel:Open("accounting_tracker")
    end
end

function module:EnsureWindow()
    if self.window then return end

    local W = module.WINDOW
    local f = CreateFrame("Frame", "ThyraxUtilAccountingWindow", UIParent, "BackdropTemplate")
    local windowSettings = EnsureWindowSettings(self.settings)
    f:SetSize(windowSettings and windowSettings.width or W.WIDTH, windowSettings and windowSettings.height or W.HEIGHT)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then
        f:SetResizeBounds(W.MIN_WIDTH, W.MIN_HEIGHT, W.MAX_WIDTH, W.MAX_HEIGHT)
    elseif f.SetMinResize and f.SetMaxResize then
        f:SetMinResize(W.MIN_WIDTH, W.MIN_HEIGHT)
        f:SetMaxResize(W.MAX_WIDTH, W.MAX_HEIGHT)
    end
    f:SetClampedToScreen(true)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(false)
            end
            module:HideWindow()
        else
            if self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(true)
            end
        end
    end)
    if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme(f) end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
        })
    end

    -- Header (title + shard label + window actions)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", W.PADDING, -W.PADDING)
    title:SetText("ThyraxUtil Accounting")
    f._title = title

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 12, 0)
    sub:SetText("")
    f._subtitle = sub

    local close = MakeWindowIconButton(f, "X", "Close", function() module:HideWindow() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f._closeBtn = close

    local settingsBtn = MakeWindowIconButton(f, "S", "Accounting settings", function()
        module:OpenAccountingOptions()
    end)
    settingsBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    f._settingsBtn = settingsBtn

    local resetBtn = MakeWindowIconButton(f, "R", "Reset all filters", function()
        module.windowState.search = ""
        module.windowState.bucket = "7d"
        module.windowState.characterFilter = "current"
        module.windowState.hiddenItemTypes = {}
        for _, category in ipairs(CATEGORY_ORDER) do
            local key = CATEGORY_SETTING_KEYS[category]
            if key then module.settings[key] = true end
        end
        local windowSettings = EnsureWindowSettings(module.settings)
        if windowSettings then
            windowSettings.search = ""
            windowSettings.bucket = "7d"
            windowSettings.characterFilter = "current"
            windowSettings.hiddenItemTypes = {}
        end
        module:RefreshWindow()
    end)
    resetBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    f._resetBtn = resetBtn

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    drag:SetHeight(W.HEADER_H + W.PADDING)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        module:SaveWindowPosition()
    end)
    f._drag = drag
    if close.SetFrameLevel and drag.GetFrameLevel then
        close:SetFrameLevel(drag:GetFrameLevel() + 1)
        settingsBtn:SetFrameLevel(drag:GetFrameLevel() + 1)
        resetBtn:SetFrameLevel(drag:GetFrameLevel() + 1)
    end

    local resize = CreateFrame("Button", nil, f)
    resize:SetSize(20, 20)
    resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    resize:EnableMouse(true)
    -- Keep the grip above the (now mouse-enabled) footer bar so the bottom-right
    -- corner still grabs the resize handle instead of the footer tooltip area.
    resize:SetFrameLevel(f:GetFrameLevel() + 30)
    resize:RegisterForDrag("LeftButton")
    resize._parts = {}
    local bottom = resize:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture(WHITE_TEXTURE)
    bottom:SetSize(16, 3)
    bottom:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -1, 1)
    resize._parts[#resize._parts + 1] = bottom
    local right = resize:CreateTexture(nil, "OVERLAY")
    right:SetTexture(WHITE_TEXTURE)
    right:SetSize(3, 16)
    right:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -1, 1)
    resize._parts[#resize._parts + 1] = right
    local corner = resize:CreateTexture(nil, "OVERLAY")
    corner:SetTexture(WHITE_TEXTURE)
    corner:SetSize(7, 7)
    corner:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -1, 1)
    resize._parts[#resize._parts + 1] = corner
    local function StartResize()
        f._isResizing = true
        if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
    end
    local function StopResize()
        f._isResizing = false
        f:StopMovingOrSizing()
        module:SaveWindowSize()
        module:RefreshWindow()
    end
    resize:SetScript("OnMouseDown", StartResize)
    resize:SetScript("OnMouseUp", StopResize)
    resize:SetScript("OnDragStart", StartResize)
    resize:SetScript("OnDragStop", StopResize)
    f._resizeGrip = resize

    f._tabs = {}
    f._timeBtns = {}

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetFrameLevel(f:GetFrameLevel() + 10)
    tabBar:SetPoint("TOPLEFT", f, "TOPLEFT", W.PADDING, -W.PADDING - W.HEADER_H - 4)
    tabBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -W.PADDING, -W.PADDING - W.HEADER_H - 4)
    tabBar:SetHeight(W.TAB_BAR_H)
    tabBar:Show()
    f._tabBar = tabBar

    for _, tab in ipairs(TABS) do
        local tabID = tab.id
        local btn = MakeTabButton(tabBar, tab.label, function()
            module.windowState.tab = tabID
            local windowSettings = EnsureWindowSettings(module.settings)
            if windowSettings then windowSettings.tab = tabID end
            module:RefreshWindow()
        end)
        f._tabs[tabID] = btn
    end

    -- Time-filter bar (below tab bar)
    local timeBar = CreateFrame("Frame", nil, f)
    timeBar:SetFrameLevel(f:GetFrameLevel() + 10)
    timeBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    timeBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -4)
    timeBar:SetHeight(W.FILTER_BAR_H)
    timeBar:Show()
    f._timeBar = timeBar

    local searchLabel = timeBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    searchLabel:SetPoint("LEFT", timeBar, "LEFT", 4, 0)
    searchLabel:SetText("Search:")
    f._searchLabel = searchLabel

    local search = CreateFrame("EditBox", nil, timeBar, "BackdropTemplate")
    search:SetAutoFocus(false)
    search:SetSize(230, W.FILTER_BAR_H - 4)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    search:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        module.windowState.search = text
        local windowSettings = EnsureWindowSettings(module.settings)
        if windowSettings then windowSettings.search = text end
        -- Debounce: wait 250ms before refreshing to reduce garbage pressure
        if module._searchTimer then
            module._searchTimer:Cancel()
            module._searchTimer = nil
        end
        if type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTimer) == "function" then
            module._searchTimer = _G.C_Timer.NewTimer(0.25, function()
                module._searchTimer = nil
                if module.window and module.window:IsShown() then
                    module:RefreshWindow()
                end
            end)
        else
            module:RefreshWindow()
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    f._search = search

    local clearBtn = CreateFrame("Button", nil, search)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearText:SetText("x")
    clearBtn._text = clearText
    clearBtn:SetScript("OnClick", function()
        search:SetText("")
        module.windowState.search = ""
        local windowSettings = EnsureWindowSettings(module.settings)
        if windowSettings then windowSettings.search = "" end
        module:RefreshWindow()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        self._text:SetTextColor(1, 1, 1, 1)
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self._text:SetTextColor(0.7, 0.6, 0.4, 0.8)
    end)
    clearBtn:Hide()
    f._searchClear = clearBtn

    f._bucketSelect = MakeToolbarButton(timeBar, 112, "Range", function(self)
        local entries = {}
        for _, bucket in ipairs(TIME_BUCKETS) do
            local bucketID = bucket.id
            local bucketLabel = bucket.label
            entries[#entries + 1] = {
                label = bucketLabel,
                checked = module.windowState.bucket == bucketID,
                checkable = true,
                onClick = function()
                    module.windowState.bucket = bucketID
                    local windowSettings = EnsureWindowSettings(module.settings)
                    if windowSettings then windowSettings.bucket = bucketID end
                    module:RefreshWindow()
                end,
            }
        end
        module:OpenWindowMenu(self, 150, entries)
    end)
    f._bucketSelect:SetPoint("RIGHT", timeBar, "RIGHT", -2, 0)

    -- Group/Chart bar (dynamic row, only visible for Groups/Charts tabs)
    local groupBar = CreateFrame("Frame", nil, f)
    groupBar:SetFrameLevel(f:GetFrameLevel() + 10)
    groupBar:SetPoint("TOPLEFT", timeBar, "BOTTOMLEFT", 0, -4)
    groupBar:SetPoint("TOPRIGHT", timeBar, "BOTTOMRIGHT", 0, -4)
    groupBar:SetHeight(W.FILTER_BAR_H)
    groupBar:Hide()
    f._groupBar = groupBar

    f._groupSelect = MakeToolbarButton(groupBar, 200, "Group", function(self)
        local entries = {}
        if module.windowState.tab == "charts" then
            for _, mode in ipairs(CHART_MODES) do
                local modeID = mode.id
                local modeLabel = mode.label
                entries[#entries + 1] = {
                    label = modeLabel,
                    checked = module.windowState.chartView == modeID,
                    checkable = true,
                    onClick = function()
                        module.windowState.chartView = modeID
                        local windowSettings = EnsureWindowSettings(module.settings)
                        if windowSettings then windowSettings.chartView = modeID end
                        module:RefreshWindow()
                    end,
                }
            end
        else
            for _, mode in ipairs(GROUP_MODES) do
                local modeID = mode.id
                local modeLabel = mode.label
                entries[#entries + 1] = {
                    label = modeLabel,
                    checked = module.windowState.groupBy == modeID,
                    checkable = true,
                    onClick = function()
                        module.windowState.groupBy = modeID
                        module.windowState.tab = "groups"
                        local windowSettings = EnsureWindowSettings(module.settings)
                        if windowSettings then
                            windowSettings.groupBy = modeID
                            windowSettings.tab = "groups"
                        end
                        module:RefreshWindow()
                    end,
                }
            end
        end
        module:OpenWindowMenu(self, 150, entries)
    end)
    f._groupSelect:SetPoint("LEFT", groupBar, "LEFT", 2, 0)

    f._trendOptionsSelect = MakeToolbarButton(groupBar, 160, "Display", function(self)
        local s = module.settings or {}
        local entries = {
            {
                label = "Show bar values",
                checked = s.chartBarLabels ~= false,
                checkable = true,
                onClick = function()
                    local newVal = not (s.chartBarLabels ~= false)
                    ns.Settings:SetModuleValue("accounting_tracker", "chartBarLabels", newVal)
                    if module.settings then module.settings.chartBarLabels = newVal end
                    module:RefreshWindow()
                end,
            },
            {
                label = "Cumulative P&L line",
                checked = s.chartCumulativeLine == true,
                checkable = true,
                onClick = function()
                    local newVal = not (s.chartCumulativeLine == true)
                    ns.Settings:SetModuleValue("accounting_tracker", "chartCumulativeLine", newVal)
                    if module.settings then module.settings.chartCumulativeLine = newVal end
                    module:RefreshWindow()
                end,
            },
            {
                label = "Moving average line",
                checked = s.chartShowAvgLine == true,
                checkable = true,
                onClick = function()
                    local newVal = not (s.chartShowAvgLine == true)
                    ns.Settings:SetModuleValue("accounting_tracker", "chartShowAvgLine", newVal)
                    if module.settings then module.settings.chartShowAvgLine = newVal end
                    module:RefreshWindow()
                end,
            },
        }
        module:OpenWindowMenu(self, 200, entries)
    end)
    f._trendOptionsSelect:SetPoint("LEFT", f._groupSelect, "RIGHT", 8, 0)
    f._trendOptionsSelect:Hide()

    local categoryBar = CreateFrame("Frame", nil, f)
    categoryBar:SetFrameLevel(f:GetFrameLevel() + 10)
    categoryBar:SetPoint("TOPLEFT", timeBar, "BOTTOMLEFT", 0, -4)
    categoryBar:SetPoint("TOPRIGHT", timeBar, "BOTTOMRIGHT", 0, -4)
    categoryBar:SetHeight(W.CATEGORY_BAR_H)
    categoryBar:Show()
    f._categoryBar = categoryBar
    f._categoryBtns = {}
    f._itemFilterBtns = {}

    f._characterSelect = MakeToolbarButton(categoryBar, 176, "Character", function(self)
        local entries = {}
        local _, currentKey = module:GetShard()
        entries[#entries + 1] = {
            label = "Current: " .. module:GetShardLabel(currentKey),
            checked = module:GetWindowShardFilter() == "current",
            checkable = true,
            onClick = function()
                module:SetWindowShardFilter("current")
                module:RefreshWindow()
            end,
        }
        entries[#entries + 1] = {
            label = "All account characters",
            checked = module:GetWindowShardFilter() == "all",
            checkable = true,
            onClick = function()
                module:SetWindowShardFilter("all")
                module:RefreshWindow()
            end,
        }
        for _, key in ipairs(module:GetKnownShardKeys()) do
            if key ~= currentKey then
                local shardKey = key
                local shard = module.settings and module.settings.shards and module.settings.shards[shardKey]
                -- Works whether the shard is live or at rest (blobbed).
                local entryCount = module:GetShardEntryCount(shard)
                entries[#entries + 1] = {
                    label = module:GetShardLabel(shardKey) .. " (" .. tostring(entryCount) .. ")",
                    checked = module:GetWindowShardFilter() == shardKey,
                    checkable = true,
                    onClick = function()
                        module:SetWindowShardFilter(shardKey)
                        module:RefreshWindow()
                    end,
                }
            end
        end
        module:OpenWindowMenu(self, 260, entries)
    end)
    f._characterSelect:SetPoint("LEFT", categoryBar, "LEFT", 2, 0)

    f._filterSelect = MakeToolbarButton(categoryBar, 170, "Sources", function(self)
        local owner = self
        module:OpenWindowMenu(owner, 190, function()
            local entries = {}
            entries[#entries + 1] = {
                label = "All sources",
                checked = module:GetActiveSourceFilterLabel() == "Sources: All",
                checkable = true,
                keepOpen = true,
                onClick = function()
                    for _, category in ipairs(CATEGORY_ORDER) do
                        local key = CATEGORY_SETTING_KEYS[category]
                        if key then module.settings[key] = true end
                    end
                    module:RefreshWindow()
                end,
            }
            entries[#entries + 1] = {
                label = "Auction House only",
                checked = module.settings.showCategoryAH ~= false
                    and module.settings.showCategoryVendor == false
                    and module.settings.showCategoryQuest == false
                    and module.settings.showCategoryLoot == false
                    and module.settings.showCategoryMail == false
                    and module.settings.showCategoryTrade == false
                    and module.settings.showCategoryWorkOrders == false
                    and module.settings.showCategoryOther == false,
                checkable = true,
                keepOpen = true,
                onClick = function()
                    for _, category in ipairs(CATEGORY_ORDER) do
                        local key = CATEGORY_SETTING_KEYS[category]
                        if key then module.settings[key] = (category == "ah") end
                    end
                    module:RefreshWindow()
                end,
            }
            for _, category in ipairs(CATEGORY_ORDER) do
                local key = CATEGORY_SETTING_KEYS[category]
                local label = module:GetCategoryLabel(category)
                entries[#entries + 1] = {
                    label = label,
                    checked = key and module.settings[key] ~= false,
                    checkable = true,
                    keepOpen = true,
                    onClick = function()
                        if key then
                            module.settings[key] = module.settings[key] == false
                            module:RefreshWindow()
                        end
                    end,
                }
            end
            return entries
        end)
    end)
    f._filterSelect:SetPoint("LEFT", categoryBar, "LEFT", 2, 0)

    f._itemTypeSelect = MakeToolbarButton(categoryBar, 190, "Item Types", function(self)
        local owner = self
        module:OpenWindowMenu(owner, 210, function()
            local entries = {}
            local hidden = module.windowState.hiddenItemTypes or {}
            local hiddenCount = 0
            for _ in pairs(hidden) do hiddenCount = hiddenCount + 1 end
            local types = {}
            local seen = {}
            local function addType(label)
                if type(label) == "string" and label ~= "" and label ~= "No item type" and not seen[label] then
                    seen[label] = true
                    table.insert(types, label)
                end
            end
            for _, shardInfo in ipairs(module:GetWindowShardList()) do
                local shard = shardInfo.shard
                module:MaterializeShard(shard)
                if shard and shard.entries then
                    for _, entry in ipairs(shard.entries) do
                        module:EnsureEntryItemMetadata(entry)
                        addType(module:GetItemTypeLabel(entry))
                    end
                end
            end
            for _, classID in ipairs(ITEM_CLASS_FILTER_ORDER) do
                addType(ITEM_CLASS_LABELS[classID])
            end
            table.sort(types)
            entries[#entries + 1] = {
                label = "Show all",
                checked = hiddenCount == 0,
                checkable = true,
                keepOpen = true,
                onClick = function()
                    module.windowState.hiddenItemTypes = {}
                    local windowSettings = EnsureWindowSettings(module.settings)
                    if windowSettings then windowSettings.hiddenItemTypes = {} end
                    module:RefreshWindow()
                end,
            }
            entries[#entries + 1] = {
                label = "Hide all",
                checked = false,
                checkable = false,
                keepOpen = true,
                onClick = function()
                    local allHidden = {}
                    for _, itemType in ipairs(types) do allHidden[itemType] = true end
                    module.windowState.hiddenItemTypes = allHidden
                    local windowSettings = EnsureWindowSettings(module.settings)
                    if windowSettings then windowSettings.hiddenItemTypes = allHidden end
                    module:RefreshWindow()
                end,
            }
            for _, t in ipairs(types) do
                local itemType = t
                entries[#entries + 1] = {
                    label = itemType,
                    checked = not hidden[itemType],
                    checkable = true,
                    keepOpen = true,
                    onClick = function()
                        local h = module.windowState.hiddenItemTypes or {}
                        if h[itemType] then
                            h[itemType] = nil
                        else
                            h[itemType] = true
                        end
                        module.windowState.hiddenItemTypes = h
                        local windowSettings = EnsureWindowSettings(module.settings)
                        if windowSettings then windowSettings.hiddenItemTypes = h end
                        module:RefreshWindow()
                    end,
                }
            end
            return entries
        end)
    end)
    f._itemTypeSelect:SetPoint("LEFT", f._filterSelect, "RIGHT", 8, 0)

    f._columnSelect = MakeToolbarButton(categoryBar, 132, "Columns", function(self)
        local owner = self
        module:OpenWindowMenu(owner, 150, function()
            local entries = {}
            local windowSettings = EnsureWindowSettings(module.settings)
            for _, key in ipairs(COLUMN_ORDER) do
                local columnKey = key
                entries[#entries + 1] = {
                    label = COLUMN_LABELS and COLUMN_LABELS[columnKey] or columnKey,
                    checked = windowSettings.columns[columnKey] ~= false,
                    checkable = true,
                    keepOpen = true,
                    onClick = function()
                        module:ToggleWindowColumn(columnKey)
                    end,
                }
            end
            return entries
        end)
    end)
    f._columnSelect:SetPoint("LEFT", f._itemTypeSelect, "RIGHT", 8, 0)

    f._groupBtns = {}

    -- Column header row
    local colHeader = CreateFrame("Frame", nil, f)
    colHeader:SetFrameLevel(f:GetFrameLevel() + 10)
    colHeader:SetPoint("TOPLEFT", categoryBar, "BOTTOMLEFT", 0, -8)
    colHeader:SetPoint("TOPRIGHT", categoryBar, "BOTTOMRIGHT", 0, -8)
    colHeader:SetHeight(16)
    colHeader:Show()
    f._colHeader = colHeader

    local function headerCol(label, width, anchorOffset, justify)
        local fs = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", colHeader, "LEFT", anchorOffset, 0)
        fs:SetWidth(width - 6)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(label)
        return fs
    end
    f._hTime   = headerCol("Time",        W.COL_TIME,                                           0,                                                "LEFT")
    f._hKind   = headerCol("Source",      W.COL_KIND,                                           W.COL_TIME,                                       "LEFT")
    f._hType   = headerCol("Type",        W.COL_TYPE,                                           W.COL_TIME + W.COL_KIND,                          "LEFT")
    f._hWho    = headerCol("Who",         W.COL_WHO,                                            W.COL_TIME + W.COL_KIND + W.COL_TYPE,             "LEFT")
    f._hAmount = headerCol("Amount",      W.COL_AMOUNT,                                         W.COL_TIME + W.COL_KIND + W.COL_TYPE + W.COL_WHO, "RIGHT")
    f._hDetail = headerCol("Details",     W.COL_DETAIL,                                         W.COL_TIME + W.COL_KIND + W.COL_TYPE + W.COL_WHO + W.COL_AMOUNT + 8, "LEFT")

    -- Scroll area for rows
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetFrameLevel(f:GetFrameLevel() + 10)
    scroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.PADDING - 18, W.PADDING + W.FOOTER_H + 4)
    scroll:Show()
    f._scroll = scroll

    -- Virtualized ledger scrolling: a tall scroll child gives an accurate
    -- scrollbar over the whole dataset, and every scroll event re-fills the
    -- on-screen row window. HookScript keeps any template handler intact.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local bar = self.ScrollBar or self.scrollBar or self.Scrollbar
        if not (bar and bar.SetValue and bar.GetValue) then return end
        bar:SetValue(bar:GetValue() - delta * module.WINDOW.ROW_HEIGHT * 3)
    end)
    scroll:HookScript("OnVerticalScroll", function()
        if module.window and module.window._isVirtualList then
            module:UpdateLedgerWindow()
        end
    end)

    local content = CreateFrame("Frame", nil, scroll)
    if content.SetFrameLevel and scroll.GetFrameLevel then
        content:SetFrameLevel(scroll:GetFrameLevel() + 1)
    end
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(W.WIDTH - 2 * W.PADDING - 24, 10)
    content:Show()
    scroll:SetScrollChild(content)
    f._content = content
    f._rows = {}

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
    empty:SetText("No accounting entries")
    empty:Hide()
    f._empty = empty

    -- Footer
    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", W.PADDING, W.PADDING)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.PADDING, W.PADDING)
    footer:SetJustifyH("LEFT")
    footer:SetText("")
    f._footer = footer

    local footerBar = CreateFrame("Frame", nil, f)
    footerBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", W.PADDING, W.PADDING)
    footerBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.PADDING, W.PADDING)
    footerBar:SetHeight(W.FOOTER_H)
    -- Sits below the resize grip (raised above) so its corner stays grabbable.
    footerBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f._footerBar = footerBar

    -- Thin accent line across the top edge so the totals bar reads as its own
    -- band, set apart from the list above. Colored in LayoutWindowFooter so it
    -- tracks the active theme.
    local footerTopLine = footerBar:CreateTexture(nil, "ARTWORK")
    footerTopLine:SetHeight(2)
    footerTopLine:SetPoint("TOPLEFT", footerBar, "TOPLEFT", 0, 1)
    footerTopLine:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT", 0, 1)
    f._footerTopLine = footerTopLine

    -- Hover explanation for the all-time footer. The child money FontStrings are
    -- not mouse-enabled, so the cursor stays "inside" footerBar across the whole
    -- row and the tooltip does not flicker.
    footerBar:EnableMouse(true)
    footerBar:SetScript("OnEnter", function(selfBar)
        local gt = _G.GameTooltip
        if not gt then return end
        gt:SetOwner(selfBar, "ANCHOR_TOP")
        gt:ClearLines()
        gt:AddLine("All-time totals")
        gt:AddLine("Income, Expenses and Net below are lifetime totals for the selected character(s), counted since you installed ThyraxUtil.", 0.9, 0.9, 0.9, true)
        gt:AddLine("They ignore the time range (top right), which only filters the list and charts above (up to the last 90 days).", 0.9, 0.9, 0.9, true)
        gt:AddLine("Open the Overview tab for totals limited to a time range.", 0.9, 0.9, 0.9, true)
        gt:AddLine("All-time totals are kept even when old entries are trimmed to save space.", 0.7, 0.7, 0.7, true)
        local shown = (module.window and module.window._footerShownCount) or 0
        gt:AddLine(" ")
        gt:AddLine(("Currently showing %d entries in the selected range."):format(shown), 0.7, 0.7, 0.7, true)
        gt:Show()
    end)
    footerBar:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    local function footerLabel(text, x, width)
        local fs = footerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", footerBar, "LEFT", x, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text or "")
        return fs
    end
    local function footerMoneyGroup(label, x)
        local group = { label = footerLabel(label, x, 58) }
        group.sign = footerLabel("", x + 58, 12)
        group.sign:SetJustifyH("RIGHT")
        group.gold = footerLabel("", x + 70, 58)
        group.gold:SetJustifyH("RIGHT")
        group.silver = footerLabel("", x + 128, 42)
        group.silver:SetJustifyH("RIGHT")
        group.copper = footerLabel("", x + 170, 42)
        group.copper:SetJustifyH("RIGHT")
        return group
    end
    f._footerCount = footerLabel("", 0, 110)
    f._footerIncome = footerMoneyGroup("Income", 122)
    f._footerExpenses = footerMoneyGroup("Expenses", 350)
    f._footerNet = footerMoneyGroup("Net", 604)

    self.window = f
    f:SetScript("OnSizeChanged", function(_, width)
        if f._content then
            local contentWidth = (f._scroll and f._scroll:GetWidth()) or (width - 2 * W.PADDING - 24)
            f._content:SetWidth(math.max(10, contentWidth))
        end
        if f._isResizing then
            module:LayoutWindowFooter()
            return
        end
        module:LayoutWindowToolbar()
        module:LayoutWindowFooter()
        module:ApplyLedgerColumnLayout()
        if f._isVirtualList then module:UpdateLedgerWindow() end
    end)

    self.windowState = self.windowState or {
        tab = windowSettings and windowSettings.tab or "overview",
        bucket = windowSettings and windowSettings.bucket or "7d",
        search = windowSettings and windowSettings.search or "",
        groupBy = windowSettings and windowSettings.groupBy or "source",
        chartView = windowSettings and windowSettings.chartView or "daily",
        hiddenItemTypes = windowSettings and windowSettings.hiddenItemTypes or {},
        characterFilter = windowSettings and windowSettings.characterFilter or "current",
    }
    self:LayoutWindowFooter()
    self:ApplyWindowPosition()
end

function module:CancelDailyTrendBuild()
    self._dailyTrendBuildToken = (self._dailyTrendBuildToken or 0) + 1
end

function module:ApplyWindowFooterTotals(displayShards, shownCount, palette, countLabel)
    local f = self.window
    if not f then return end
    local p = palette or WindowPalette()
    local lifeIncome, lifeExpense = 0, 0
    for _, shardInfo in ipairs(displayShards or {}) do
        local inc, exp = self:GetShardLifetime(shardInfo.shard)
        lifeIncome = lifeIncome + (inc or 0)
        lifeExpense = lifeExpense + (exp or 0)
    end
    local lifeNet = lifeIncome + lifeExpense
    f._footerShownCount = tonumber(shownCount) or 0
    if f._footer then f._footer:SetText("") end
    if f._footerBar then f._footerBar:Show() end
    if f._footerCount then
        f._footerCount:SetText(countLabel or "All-time Total:")
        f._footerCount:SetTextColor(unpack(p.colHeader or p.neutralText))
    end
    if f._footerIncome then
        f._footerIncome.label:SetTextColor(unpack(p.neutralText))
        f._footerIncome._lastCopper = lifeIncome
    end
    if f._footerExpenses then
        f._footerExpenses.label:SetTextColor(unpack(p.neutralText))
        f._footerExpenses._lastCopper = lifeExpense
    end
    if f._footerNet then
        f._footerNet.label:SetTextColor(unpack(p.neutralText))
        f._footerNet._lastCopper = lifeNet
    end
    self:LayoutWindowFooter()
end

function module:StartDailyTrendBuild(displayShards, bucketID, filterEntry, palette)
    if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.After) ~= "function" then return false end
    if type(self.DeserializeEntriesChunk) ~= "function" then return false end
    local f = self.window
    if not f then return false end

    local token = (self._dailyTrendBuildToken or 0) + 1
    self._dailyTrendBuildToken = token
    local data = CreateDailyTrendData(bucketID)
    data.loadingText = "Loading chart..."
    local incomeTotal, expenseTotal, count = 0, 0, 0
    local scanned = 0
    self:RenderDailyTrendChart(data, bucketID, 0, 0, palette)
    self:ApplyWindowFooterTotals(displayShards, 0, palette, "Loading chart...")

    local sources = {}
    for _, shardInfo in ipairs(displayShards or {}) do
        local shard = shardInfo.shard
        if type(shard) == "table" then
            if type(shard.entries) == "table" then
                sources[#sources + 1] = { kind = "live", entries = shard.entries }
            elseif type(shard.blob) == "string" and shard.blob ~= "" then
                sources[#sources + 1] = { kind = "blob", blob = shard.blob }
            end
        end
    end

    local sourceIndex, liveIndex, blobCursor = 1, 1, nil
    local function isCancelled()
        if self._dailyTrendBuildToken ~= token then return true end
        if not self.window then return true end
        if self.window.IsShown and not self.window:IsShown() then return true end
        local state = self.windowState
        return not (state and state.tab == "charts" and state.chartView == "daily" and state.bucket == bucketID)
    end
    local function addEntry(entry)
        scanned = scanned + 1
        if type(entry) == "table" and filterEntry(entry) then
            local amt = entry.amount or 0
            if amt > 0 then incomeTotal = incomeTotal + amt
            elseif amt < 0 then expenseTotal = expenseTotal + amt end
            count = count + 1
            AddDailyTrendEntry(data, entry)
        end
    end
    local function finish()
        if isCancelled() then return end
        data.loadingText = nil
        self:RenderDailyTrendChart(data, bucketID, incomeTotal, expenseTotal, palette)
        self:ApplyWindowFooterTotals(displayShards, count, palette)
        if self.window and self.window._empty then self.window._empty:Hide() end
    end
    local step
    local function scheduleNext()
        _G.C_Timer.After(DAILY_TREND_CHUNK_DELAY, function()
            step()
        end)
    end
    step = function()
        if isCancelled() then return end
        local processed = 0
        while processed < DAILY_TREND_CHUNK_SIZE do
            local source = sources[sourceIndex]
            if not source then
                finish()
                return
            end
            if source.kind == "live" then
                local entries = source.entries
                while liveIndex <= #entries and processed < DAILY_TREND_CHUNK_SIZE do
                    addEntry(entries[liveIndex])
                    liveIndex = liveIndex + 1
                    processed = processed + 1
                end
                if liveIndex > #entries then
                    sourceIndex = sourceIndex + 1
                    liveIndex = 1
                end
            elseif source.kind == "blob" then
                local remaining = DAILY_TREND_CHUNK_SIZE - processed
                local out, cursor, done, err = self:DeserializeEntriesChunk(source.blob, blobCursor, remaining, {})
                if not out then
                    if ns.Diagnostics and ns.Diagnostics.Warn then
                        ns.Diagnostics:Warn(("Accounting: skipped unreadable history while building chart (%s)."):format(tostring(err)))
                    end
                    sourceIndex = sourceIndex + 1
                    blobCursor = nil
                else
                    for i = 1, #out do addEntry(out[i]) end
                    processed = processed + #out
                    if done then
                        sourceIndex = sourceIndex + 1
                        blobCursor = nil
                    else
                        blobCursor = cursor
                    end
                end
            else
                sourceIndex = sourceIndex + 1
                liveIndex = 1
                blobCursor = nil
            end
        end
        if f._trendChart and f._trendChart._summary then
            f._trendChart._summary:SetText("Loading chart... " .. tostring(scanned) .. " entries")
        end
        scheduleNext()
    end

    scheduleNext()
    return true
end

-- Build/refresh row content for the currently selected tab + bucket.
function module:RefreshWindow()
    if not self.window then return end
    local f = self.window
    local p = WindowPalette()
    local state = self.windowState
    if state.tab == "settings" then state.tab = "overview" end
    if type(state.hiddenItemTypes) ~= "table" then state.hiddenItemTypes = {} end
    if state.chartView ~= "daily" then state.chartView = "source" end
    if state.characterFilter == "account" then state.characterFilter = "all" end
    if type(state.characterFilter) ~= "string" or state.characterFilter == "" then state.characterFilter = self:GetWindowShardFilter() end

    -- Title + theme repaint -- always use solid texture so alpha slider works
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(unpack(p.windowBg))
        f:SetBackdropBorderColor(unpack(p.windowBorder))
    end
    -- Override NineSlice textures with solid color so alpha slider works in Classic
    if f.Center and f.Center.SetTexture then
        f.Center:SetTexture("Interface\\Buttons\\WHITE8x8")
        f.Center:SetVertexColor(p.windowBg[1], p.windowBg[2], p.windowBg[3], p.windowBg[4])
    end
    for _, region in ipairs(WINDOW_EDGE_REGIONS) do
        if f[region] and f[region].SetTexture then
            f[region]:SetTexture("Interface\\Buttons\\WHITE8x8")
            f[region]:SetVertexColor(p.windowBorder[1], p.windowBorder[2], p.windowBorder[3], p.windowBorder[4])
        end
    end
    f._title:SetTextColor(unpack(p.title))
    f._subtitle:SetTextColor(unpack(p.dimText))
    -- Suffix the subtitle with the active search filter (if any). The gold
    -- search-bar highlight already signals an active filter, but a quick
    -- glance at the window title makes it impossible to miss across long
    -- sessions, and it survives scrolling away from the search bar.
    local subtitleText = self:GetWindowShardFilterTitle()
    local activeSearch = self.windowState and self.windowState.search or ""
    if activeSearch ~= "" then
        subtitleText = subtitleText .. '  -  filter: "' .. activeSearch .. '"'
    end
    f._subtitle:SetText(subtitleText)
    ApplyWindowIconButtonTheme(f._closeBtn, p)
    ApplyWindowIconButtonTheme(f._settingsBtn, p)
    ApplyWindowIconButtonTheme(f._resetBtn, p)
    ApplySearchTheme(f._search, p, (state.search or "") ~= "")
    ApplyScrollTheme(f._scroll, p)
    self:LayoutWindowFooter()
    if f._resizeGrip and f._resizeGrip._parts then
        for _, part in ipairs(f._resizeGrip._parts) do
            part:SetVertexColor(p.colHeader[1], p.colHeader[2], p.colHeader[3], 0.85)
        end
    end
    if f._content and f._scroll then
        f._content:SetWidth(math.max(10, f._scroll:GetWidth()))
    end

    -- Tab visuals (active vs inactive)
    for _, t in ipairs(TABS) do
        local btn = f._tabs[t.id]
        if btn then
            btn._isOn = (state.tab == t.id)
            btn:SetBackdropColor(unpack(btn._isOn and p.tabOnBg or p.tabOffBg))
            btn:SetBackdropBorderColor(0, 0, 0, 1)
            btn._text:SetTextColor(unpack(btn._isOn and p.tabOnText or p.tabOffText))
        end
    end

    -- Toolbar dropdown-style buttons (bucketSelect / groupSelect / etc).
    -- These re-pull WindowPalette on hover via OnEnter / OnLeave, but their
    -- idle backdrop is set once at creation. Re-applying it on every refresh
    -- means a theme change repaints immediately instead of waiting for a
    -- mouseover.
    for _, key in ipairs(TOOLBAR_THEME_BUTTON_KEYS) do
        ApplyToolbarButtonTheme(f[key], p)
    end
    for _, bucket in ipairs(TIME_BUCKETS) do
        local btn = f._timeBtns[bucket.id]
        if btn then
            btn._isOn = (state.bucket == bucket.id)
            btn:SetBackdropColor(unpack(btn._isOn and p.tabOnBg or p.tabOffBg))
            btn:SetBackdropBorderColor(0, 0, 0, 1)
            btn._text:SetTextColor(unpack(btn._isOn and p.tabOnText or p.tabOffText))
        end
    end
    if f._bucketSelect then
        local label = "Range"
        for _, bucket in ipairs(TIME_BUCKETS) do
            if bucket.id == state.bucket then label = bucket.label; break end
        end
        f._bucketSelect:SetDisplayText(label)
    end
    if f._groupSelect and f._groupBar then
        if state.tab == "groups" then
            local label = "Group"
            for _, mode in ipairs(GROUP_MODES) do
                if mode.id == state.groupBy then label = "Group: " .. mode.label; break end
            end
            f._groupSelect:SetDisplayText(label)
            f._groupBar:Show()
            if f._trendOptionsSelect then f._trendOptionsSelect:Hide() end
        elseif state.tab == "charts" then
            if state.chartView ~= "daily" then state.chartView = "source" end
            f._groupSelect:SetDisplayText("Chart: " .. GetChartModeLabel(state.chartView))
            f._groupBar:Show()
            if f._trendOptionsSelect then
                if state.chartView == "daily" then
                    f._trendOptionsSelect:SetDisplayText("Display")
                    f._trendOptionsSelect:Show()
                else
                    f._trendOptionsSelect:Hide()
                end
            end
        else
            f._groupBar:Hide()
            if f._trendOptionsSelect then f._trendOptionsSelect:Hide() end
        end
    end
    if f._filterSelect then
        f._filterSelect:SetDisplayText(self:GetActiveSourceFilterLabel())
    end
    if f._characterSelect then
        f._characterSelect:SetDisplayText(self:GetWindowShardFilterButtonLabel())
    end
    if f._itemTypeSelect then
        local hidden = state.hiddenItemTypes or {}
        local hiddenCount = 0
        for _ in pairs(hidden) do hiddenCount = hiddenCount + 1 end
        local itemTypeLabel = hiddenCount == 0 and "Item Types: All" or ("Item Types: " .. hiddenCount .. " hidden")
        f._itemTypeSelect:SetDisplayText(itemTypeLabel)
        f._itemTypeSelect:Show()
    end
    if f._columnSelect then
        f._columnSelect:SetDisplayText("Columns")
        if state.tab == "all" or state.tab == "income" or state.tab == "expenses" then
            f._columnSelect:Show()
        else
            f._columnSelect:Hide()
        end
    end
    self:LayoutWindowToolbar()
    if f._timeLabel then f._timeLabel:SetTextColor(unpack(p.dimText)) end
    if f._categoryLabel then f._categoryLabel:SetTextColor(unpack(p.dimText)) end
    for _, category in ipairs(CATEGORY_ORDER) do
        local btn = f._categoryBtns and f._categoryBtns[category]
        if btn then
            btn._isOn = self:IsCategoryVisible(category)
            btn:SetBackdropColor(unpack(btn._isOn and p.tabOnBg or p.tabOffBg))
            btn:SetBackdropBorderColor(0, 0, 0, 1)
            btn._text:SetTextColor(unpack(btn._isOn and p.tabOnText or p.tabOffText))
        end
    end

    if f._groupLabel then f._groupLabel:SetTextColor(unpack(p.dimText)) end
    for _, mode in ipairs(GROUP_MODES) do
        local btn = f._groupBtns and f._groupBtns[mode.id]
        if btn then
            btn._isOn = (state.groupBy == mode.id)
            btn:SetBackdropColor(unpack(btn._isOn and p.tabOnBg or p.tabOffBg))
            btn:SetBackdropBorderColor(0, 0, 0, 1)
            btn._text:SetTextColor(unpack(btn._isOn and p.tabOnText or p.tabOffText))
        end
    end
    f._colHeader:Show()
    if f._scroll then
        f._scroll:ClearAllPoints()
        f._scroll:SetPoint("TOPLEFT", f._colHeader, "BOTTOMLEFT", 0, -2)
        f._scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -module.WINDOW.PADDING - 18, module.WINDOW.PADDING + module.WINDOW.FOOTER_H + 4)
    end
    f._hTime:SetTextColor(unpack(p.colHeader))
    f._hKind:SetTextColor(unpack(p.colHeader))
    f._hType:SetTextColor(unpack(p.colHeader))
    f._hWho:SetTextColor(unpack(p.colHeader))
    f._hAmount:SetTextColor(unpack(p.colHeader))
    f._hDetail:SetTextColor(unpack(p.colHeader))
    if state.tab == "overview" then
        f._hTime:SetText("Period")
        f._hKind:SetText("Metric")
        f._hType:SetText("Section")
        f._hWho:SetText("")
        f._hAmount:SetText("Amount")
        f._hDetail:SetText("Notes")
    elseif state.tab == "groups" then
        f._hTime:SetText("Count")
        f._hKind:SetText("Group")
        f._hType:SetText("Grouped By")
        f._hWho:SetText("")
        f._hAmount:SetText("Net")
        f._hDetail:SetText("Notes")
    elseif state.tab == "charts" then
        if state.chartView == "daily" then
            f._colHeader:Hide()
            if f._scroll then
                f._scroll:ClearAllPoints()
                if f._groupBar and f._groupBar:IsShown() then
                    f._scroll:SetPoint("TOPLEFT", f._groupBar, "BOTTOMLEFT", 0, -4)
                elseif f._categoryBar then
                    f._scroll:SetPoint("TOPLEFT", f._categoryBar, "BOTTOMLEFT", 0, -4)
                end
                f._scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -module.WINDOW.PADDING - 18, module.WINDOW.PADDING + module.WINDOW.FOOTER_H + 4)
            end
        else
            f._hTime:SetText("Source")
            f._hKind:SetText("View")
            f._hType:SetText("Type")
            f._hWho:SetText("")
            f._hAmount:SetText("Net")
            f._hDetail:SetText("Relative")
        end
    elseif state.tab == "settings" then
        f._hTime:SetText("Area")
        f._hKind:SetText("Setting")
        f._hType:SetText("")
        f._hWho:SetText("")
        f._hAmount:SetText("")
        f._hDetail:SetText("State")
    else
        f._hTime:SetText("Time")
        f._hKind:SetText("Source")
        f._hType:SetText("Type")
        f._hWho:SetText("Who")
        f._hAmount:SetText("Amount")
        f._hDetail:SetText("Details")
    end
    if f._searchLabel then
        if (state.search or "") ~= "" then
            f._searchLabel:SetTextColor(unpack(p.title))
        else
            f._searchLabel:SetTextColor(unpack(p.dimText))
        end
    end
    if f._search and f._search:GetText() ~= (state.search or "") then
        f._search:SetText(state.search or "")
    end
    if f._searchClear then
        local hasText = (state.search or "") ~= ""
        if hasText then
            f._searchClear:Show()
            f._searchClear._text:SetTextColor(p.title[1], p.title[2], p.title[3], 0.85)
        else
            f._searchClear:Hide()
        end
        f._search:SetTextInsets(6, hasText and 20 or 6, 0, 0)
    end
    if f._empty then
        f._empty:SetTextColor(unpack(p.dimText))
        f._empty:Hide()
    end

    -- Hide all existing rows so leftover frames don't bleed through.
    for _, row in ipairs(f._rows) do row:Hide() end
    self:CancelDailyTrendBuild()
    self:HideDailyTrendChart()

    local isDailyTrendRequested = state.tab == "charts" and state.chartView == "daily"

    -- Resolve bucket
    local bucketDef
    for _, b in ipairs(TIME_BUCKETS) do
        if b.id == state.bucket then bucketDef = b; break end
    end
    local sinceEpoch = (bucketDef and bucketDef.seconds) and (NowEpoch() - bucketDef.seconds) or 0

    -- Build display rows depending on tab.
    local rows = {}
    local renderDailyTrend = false
    local incomeTotal, expenseTotal, count = 0, 0, 0

    local displayShards = self:GetWindowShardList()
    if #displayShards == 0 then
        f._content:SetHeight(10)
        f._footer:SetText("(no accounting shard yet)")
        f._footer:SetTextColor(unpack(p.dimText))
        if f._footerBar then f._footerBar:Hide() end
        if f._empty then
            f._empty:SetText("No accounting shard")
            f._empty:Show()
        end
        return
    end

    local ledgerRows = {}
    local ledgerFilter = TAB_FILTERS[state.tab]
    local isLedgerTab = ledgerFilter ~= nil
    local isOverviewTab = state.tab == "overview"
    local isGroupsTab = state.tab == "groups"
    local isSourceChartTab = state.tab == "charts" and state.chartView ~= "daily"
    local isSettingsTab = state.tab == "settings"
    local needsEntryScan = not isSettingsTab
    local searchText = state.search or ""
    local hasSearch = searchText ~= ""
    local hiddenItemTypes = state.hiddenItemTypes or {}
    local hasHiddenItemTypes = next(hiddenItemTypes) ~= nil
    local categoryIncome = isOverviewTab and {} or nil
    local categoryExpenses = isOverviewTab and {} or nil
    local categoryCounts = isOverviewTab and {} or nil
    local housingTotal, housingCount = 0, 0
    local groups = isGroupsTab and {} or nil
    local order = isGroupsTab and {} or nil
    local groupModeLabel = isGroupsTab and GetGroupModeLabel(state.groupBy) or nil
    local categoryTotals = isSourceChartTab and {} or nil
    local maxAbs = 0
    local dailyTrendData = isDailyTrendRequested and CreateDailyTrendData(state.bucket) or nil
    -- Ledger tabs use a virtualized list: keep every matching entry (no row
    -- cap) and render only the on-screen slice via UpdateLedgerWindow. shardKey
    -- is never read on ledger rows, so entries are stored flat to avoid
    -- allocating one wrapper table per entry on large datasets.
    local function sortLedgerRows()
        table.sort(ledgerRows, function(a, b)
            return (a.t or 0) > (b.t or 0)
        end)
    end
    local function keepLedgerRow(entry)
        if not ledgerFilter(entry) then return end
        ledgerRows[#ledgerRows + 1] = entry
    end
    local function addGroupEntry(entry, shardKey)
        local key, label, itemLink = self:GetGroupKey(entry, state.groupBy, shardKey)
        if not groups[key] then
            groups[key] = { label = label, amount = 0, count = 0, itemLink = itemLink }
            order[#order + 1] = key
        end
        groups[key].amount = groups[key].amount + (entry.amount or 0)
        groups[key].count = groups[key].count + 1
        groups[key].itemLink = groups[key].itemLink or itemLink
    end
    local function addOverviewEntry(entry)
        local category = self:GetEntryCategory(entry)
        local amount = entry.amount or 0
        categoryCounts[category] = (categoryCounts[category] or 0) + 1
        if amount > 0 then
            categoryIncome[category] = (categoryIncome[category] or 0) + amount
        elseif amount < 0 then
            categoryExpenses[category] = (categoryExpenses[category] or 0) + amount
        end
        if self:IsHousingEntry(entry) then
            housingTotal = housingTotal + amount
            housingCount = housingCount + 1
        end
    end
    local function addSourceChartEntry(entry)
        local category = self:GetEntryCategory(entry)
        categoryTotals[category] = (categoryTotals[category] or 0) + (entry.amount or 0)
        maxAbs = math.max(maxAbs, math.abs(categoryTotals[category]))
    end
    local function includeEntry(entry)
        -- Cheap filters first: skip entries outside the time bucket before
        -- doing any metadata work. Avoids walking the whole shard history
        -- through GetItemInfo / NormalizeItemFields on every bucket switch.
        if (entry.t or 0) < sinceEpoch then return false end
        if not self:IsCategoryVisible(self:GetEntryCategory(entry)) then return false end
        if hasHiddenItemTypes or hasSearch then
            self:EnsureEntryItemMetadata(entry)
            self:EnsureEntryQuestMetadata(entry)
        end
        if hasHiddenItemTypes then
            local entryType = self:GetItemTypeLabel(entry)
            if entryType and hiddenItemTypes[entryType] then return false end
        end
        if hasSearch and not EntryMatchesSearch(entry, searchText) then return false end
        return true
    end
    if isDailyTrendRequested and self:StartDailyTrendBuild(displayShards, state.bucket, includeEntry, p) then
        f._isVirtualList = false
        f._listSource = nil
        if f._content and f._scroll then
            f._content:SetHeight(math.max(10, f._scroll:GetHeight()))
        end
        if f._empty then f._empty:Hide() end
        return
    end
    if needsEntryScan then
        -- Lazy storage: other characters' shards may be at rest (history in a
        -- serialized blob, shard.entries dropped). Materialize the in-scope
        -- shards so the scan sees their entries. They are dematerialized again
        -- when the window closes (see HideWindow -> CompactInactiveShards).
        for _, shardInfo in ipairs(displayShards) do
            self:MaterializeShard(shardInfo.shard)
        end
        for _, shardInfo in ipairs(displayShards) do
            local shard = shardInfo.shard
            if shard and type(shard.entries) == "table" then
                for _, entry in ipairs(shard.entries) do
                    if includeEntry(entry) then
                        local amt = entry.amount or 0
                        if amt > 0 then incomeTotal = incomeTotal + amt
                        elseif amt < 0 then expenseTotal = expenseTotal + amt end
                        count = count + 1
                        if isLedgerTab then
                            keepLedgerRow(entry)
                        elseif isOverviewTab then
                            addOverviewEntry(entry)
                        elseif isGroupsTab then
                            addGroupEntry(entry, shardInfo.key)
                        elseif isDailyTrendRequested then
                            AddDailyTrendEntry(dailyTrendData, entry)
                        elseif isSourceChartTab then
                            addSourceChartEntry(entry)
                        end
                    end
                end
            end
        end
    end

    if state.tab == "overview" then
        local bucketLabel = GetBucketLabel(state.bucket)
        local scopeLabel = self:GetWindowShardFilterTitle()
        local function addSection(title, detail)
            rows[#rows + 1] = {
                sectionHeader = true,
                kind = title,
                detail = detail,
                noMoney = true,
            }
        end
        local function addMetric(metric, section, amount, detail)
            rows[#rows + 1] = {
                time = bucketLabel,
                kind = metric,
                type = section,
                amount = amount,
                detail = detail,
            }
        end
        local function addNoData(section, detail)
            rows[#rows + 1] = {
                time = bucketLabel,
                kind = "No matching entries",
                type = section,
                amount = 0,
                detail = detail,
                noMoney = true,
            }
        end

        addSection("Key totals", scopeLabel)
        addMetric("Gross Income", "Summary", incomeTotal, "All positive ledger entries")
        addMetric("Gross Expenses", "Summary", expenseTotal, "All negative ledger entries")
        addMetric("Net Change", "Summary", incomeTotal + expenseTotal, tostring(count) .. " filtered entries")

        addSection("Income by source", "Positive money flow")
        local hasIncomeBreakdown = false
        for _, category in ipairs(CATEGORY_ORDER) do
            local amt = categoryIncome[category] or 0
            if amt > 0 then
                hasIncomeBreakdown = true
                rows[#rows + 1] = {
                    time = bucketLabel,
                    kind = self:GetCategoryLabel(category),
                    type = "Income",
                    amount = amt,
                    detail = tostring(categoryCounts[category] or 0) .. " entries",
                }
            end
        end
        if not hasIncomeBreakdown then
            addNoData("Income", "No positive entries in this view")
        end

        addSection("Expenses by source", "Negative money flow")
        local hasExpenseBreakdown = false
        for _, category in ipairs(CATEGORY_ORDER) do
            local amt = categoryExpenses[category] or 0
            if amt < 0 then
                hasExpenseBreakdown = true
                rows[#rows + 1] = {
                    time = bucketLabel,
                    kind = self:GetCategoryLabel(category),
                    type = "Expense",
                    amount = amt,
                    detail = tostring(categoryCounts[category] or 0) .. " entries",
                }
            end
        end
        if not hasExpenseBreakdown then
            addNoData("Expense", "No negative entries in this view")
        end

        if housingCount > 0 then
            addSection("Item focus", "Selected item classifications")
            addMetric("Housing Items", "Item Type", housingTotal, tostring(housingCount) .. " entries")
        end
    elseif state.tab == "groups" then
        table.sort(order, function(a, b)
            return math.abs(groups[a].amount or 0) > math.abs(groups[b].amount or 0)
        end)
        rows[#rows + 1] = {
            sectionHeader = true,
            kind = "Grouped by " .. groupModeLabel,
            detail = self:GetWindowShardFilterTitle(),
            noMoney = true,
        }
        for _, key in ipairs(order) do
            local group = groups[key]
            rows[#rows + 1] = {
                time = tostring(group.count) .. " entries",
                kind = group.label,
                type = groupModeLabel,
                amount = group.amount,
                detail = "Net total",
                itemLink = group.itemLink,
                itemName = state.groupBy == "item" and group.label or nil,
                drilldownSearch = state.groupBy ~= "character" and group.label or nil,
                drilldownTab = "all",
            }
        end
        if #order == 0 then
            rows[#rows + 1] = {
                time = GetBucketLabel(state.bucket),
                kind = "No matching entries",
                type = groupModeLabel,
                amount = 0,
                detail = "Nothing to group in this view",
                noMoney = true,
            }
        end
    elseif state.tab == "charts" and state.chartView == "daily" then
        renderDailyTrend = true
    elseif state.tab == "charts" then
        if maxAbs <= 0 then maxAbs = 1 end
        rows[#rows + 1] = {
            sectionHeader = true,
            kind = "Net by source",
            detail = self:GetWindowShardFilterTitle(),
            noMoney = true,
        }
        local hasChartRows = false
        for _, category in ipairs(CATEGORY_ORDER) do
            local amt = categoryTotals[category] or 0
            if amt ~= 0 then
                hasChartRows = true
                local catLabel = self:GetCategoryLabel(category)
                rows[#rows + 1] = {
                    time = catLabel,
                    kind = "Chart",
                    type = catLabel,
                    amount = amt,
                    detail = "",
                    barFraction = math.min(1, math.max(0.04, math.abs(amt) / maxAbs)),
                    drilldownSearch = catLabel,
                    drilldownTab = "all",
                }
            end
        end
        if not hasChartRows then
            rows[#rows + 1] = {
                time = GetBucketLabel(state.bucket),
                kind = "No matching entries",
                type = "Chart",
                amount = 0,
                detail = "No chartable money flow",
                noMoney = true,
            }
        end
    elseif state.tab == "settings" then
        rows[#rows + 1] = {
            time = "Window",
            kind = "Minimap Button",
            type = "",
            amount = 0,
            detail = self.settings.showMinimapButton and "On" or "Off",
            settingKey = "showMinimapButton",
            noMoney = true,
        }
        rows[#rows + 1] = {
            time = "Window",
            kind = "Housing Filter",
            type = "",
            amount = 0,
            detail = (state.hiddenItemTypes or {})["Housing"] and "Housing hidden" or "Housing visible",
            itemFilterToggle = true,
            noMoney = true,
        }
        for _, category in ipairs(CATEGORY_ORDER) do
            local key = CATEGORY_SETTING_KEYS[category]
            rows[#rows + 1] = {
                time = "Source",
                kind = self:GetCategoryLabel(category),
                type = "",
                amount = 0,
                detail = self.settings[key] ~= false and "Visible" or "Hidden",
                settingKey = key,
                noMoney = true,
            }
        end
    else
        -- Ledger tabs (all/income/expenses) render virtualized: keep the full
        -- sorted entry list and let UpdateLedgerWindow fill only the visible
        -- rows. No display tables are built here, so a 100k ledger does not
        -- allocate 100k row tables on every refresh.
        sortLedgerRows()
    end

    local totalDisplayRows = #rows
    if totalDisplayRows > MAX_RENDER_ROWS then
        for i = totalDisplayRows, MAX_RENDER_ROWS + 1, -1 do
            rows[i] = nil
        end
    end

    if renderDailyTrend then
        f._isVirtualList = false
        f._listSource = nil
        -- Cap the scroll content so the chart cannot be scrolled off-screen
        -- after viewing a tall ledger list.
        if f._content and f._scroll then
            f._content:SetHeight(math.max(10, f._scroll:GetHeight()))
        end
        self:RenderDailyTrendChart(dailyTrendData, state.bucket, incomeTotal, expenseTotal, p)
        if f._empty then f._empty:Hide() end
    elseif isLedgerTab then
        -- Virtualized ledger list: size the scroll content to the full row
        -- count so the scrollbar spans every entry, then render only the
        -- visible window. Reset scroll to the top when the active filter set
        -- changes; otherwise preserve position across refreshes (item-link
        -- resolution, theme repaints).
        f._isVirtualList = true
        f._listSource = ledgerRows
        f._listPalette = p
        f._content:SetHeight(math.max(#ledgerRows * module.WINDOW.ROW_HEIGHT, 10))
        local hiddenKeys = {}
        for hk in pairs(hiddenItemTypes) do hiddenKeys[#hiddenKeys + 1] = tostring(hk) end
        table.sort(hiddenKeys)
        local sig = table.concat({
            state.tab, state.bucket, state.search or "",
            tostring(state.characterFilter or ""),
            tostring(self:GetActiveSourceFilterLabel()),
            table.concat(hiddenKeys, ","),
        }, "|")
        if f._listSignature ~= sig then
            f._listSignature = sig
            if f._scroll then
                f._scroll:SetVerticalScroll(0)
                local bar = f._scroll.ScrollBar or f._scroll.scrollBar or f._scroll.Scrollbar
                if bar and bar.SetValue then bar:SetValue(0) end
            end
        end
        self:UpdateLedgerWindow()
        if f._empty then
            if #ledgerRows == 0 then
                f._empty:SetText((state.search and state.search ~= "") and "No matching entries" or "No accounting entries")
                f._empty:Show()
            else
                f._empty:Hide()
            end
        end
    else
        f._isVirtualList = false
        f._listSource = nil
        -- Populate row frames, reusing existing pool entries.
        for i, data in ipairs(rows) do
            local row = f._rows[i]
            if not row then
                row = MakeLedgerRow(f._content, i)
                row:SetWidth(f._content:GetWidth())
                f._rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f._content, "TOPLEFT", 0, -(i - 1) * module.WINDOW.ROW_HEIGHT)
            row:SetPoint("RIGHT", f._content, "RIGHT", 0, 0)
            row._time:SetText(data.time)
            row._time:SetTextColor(unpack(p.dimText))
            row._kind:SetText(data.kind)
            row._kind:SetTextColor(unpack(p.neutralText))
            row._type:SetText(data.type or "")
            row._type:SetTextColor(unpack(p.dimText))
            row._who:SetText(data.who or "")
            row._who:SetTextColor(unpack(p.dimText))
            SetRowMoney(row, data.amount or 0, data.noMoney, p)
            local col = p.neutralText
            if (data.amount or 0) > 0 then col = p.posAmount
            elseif (data.amount or 0) < 0 then col = p.negAmount end
            row._detail:SetText(data.detail or "")
            row._detail:SetTextColor(unpack(p.neutralText))
            row._itemLink = data.itemLink
            row._itemName = data.itemName
            row._questID = data.questID
            row._questName = data.questName
            row._entryRef = data.entry
            row._settingKey = data.settingKey
            row._itemFilterToggle = data.itemFilterToggle
            row._drilldownSearch = data.drilldownSearch
            row._drilldownTab = data.drilldownTab
            row._barFraction = data.barFraction
            row._sectionHeader = data.sectionHeader == true
            if row._sectionTitle then
                local sectionText = tostring(data.kind or "")
                if data.detail and data.detail ~= "" then
                    sectionText = sectionText .. "  -  " .. tostring(data.detail)
                end
                row._sectionTitle:SetText(sectionText)
                row._sectionTitle:SetTextColor(unpack(p.colHeader))
            end
            if row._sectionLine then
                row._sectionLine:SetColorTexture(unpack(p.rowSep))
            end
            if row._bar then
                row._bar:SetColorTexture(unpack(col))
                row._bar:SetAlpha(0.28)
                row._bar:Hide()
            end
            if row._stripe then
                if row._sectionHeader then
                    row._stripe:SetColorTexture(unpack(p.rowAlt))
                elseif i % 2 == 0 then
                    row._stripe:SetColorTexture(unpack(p.rowAlt))
                else
                    row._stripe:SetColorTexture(0, 0, 0, 0)
                end
            end
            row:Show()
        end

        self:ApplyLedgerColumnLayout()

        f._content:SetHeight(math.max(#rows * module.WINDOW.ROW_HEIGHT, 10))
        if f._empty then
            if #rows == 0 then
                f._empty:SetText((state.search and state.search ~= "") and "No matching entries" or "No accounting entries")
                f._empty:Show()
            else
                f._empty:Hide()
            end
        end
    end

    -- Footer totals. Income / Expenses / Net are ALL-TIME (lifetime) totals for
    -- the selected character scope, independent of the time range (top right),
    -- which only filters the list and charts above (capped at 90 days). Lifetime
    -- is summed from the persisted per-shard running totals so it stays correct
    -- even after old entries are pruned. The left column is a fixed "All-time"
    -- caption; the hover tooltip on the footer bar explains the rest and shows
    -- how many entries the current range/filter is displaying.
    self:ApplyWindowFooterTotals(displayShards, count, p)
end

-- Virtualized fill for ledger tabs. Renders only the on-screen slice of
-- f._listSource into the shared row pool, repositioning the ~visible frames to
-- the true content coordinates for the current scroll offset. Frame count stays
-- constant (rows on screen) regardless of dataset size, so a 100k ledger costs
-- the same handful of frames as a 50-row one.
function module:UpdateLedgerWindow()
    local f = self.window
    if not (f and f._isVirtualList and f._content and f._scroll) then return end
    local data = f._listSource
    local total = data and #data or 0
    local p = f._listPalette or WindowPalette()
    local rowH = module.WINDOW.ROW_HEIGHT
    local scrollOffset = f._scroll:GetVerticalScroll() or 0
    local viewH = f._scroll:GetHeight() or 0
    local first = math.floor(scrollOffset / rowH)
    if first < 0 then first = 0 end
    local visible = math.ceil(viewH / rowH) + 1
    local used = 0
    for k = 0, visible - 1 do
        local dataIndex = first + k + 1
        if dataIndex > total then break end
        local e = data[dataIndex]
        if e then
            used = used + 1
            local row = f._rows[used]
            if not row then
                row = MakeLedgerRow(f._content, used)
                f._rows[used] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f._content, "TOPLEFT", 0, -(first + k) * rowH)
            row:SetPoint("RIGHT", f._content, "RIGHT", 0, 0)
            row._time:SetText(AgoString(e.t) .. " ago")
            row._time:SetTextColor(unpack(p.dimText))
            row._kind:SetText(self:GetKindLabel(e.kind))
            row._kind:SetTextColor(unpack(p.neutralText))
            row._type:SetText(self:GetEntryTypeLabel(e) or "")
            row._type:SetTextColor(unpack(p.dimText))
            row._who:SetText(e.who or "")
            row._who:SetTextColor(unpack(p.dimText))
            SetRowMoney(row, e.amount or 0, false, p)
            row._detail:SetText(EntryDetailText(e) or "")
            row._detail:SetTextColor(unpack(p.neutralText))
            row._itemLink = e.itemLink
            row._itemName = e.itemName or e.item
            row._questID = e.questID
            row._questName = e.questName
            row._entryRef = e
            row._settingKey = nil
            row._itemFilterToggle = nil
            row._drilldownSearch = nil
            row._drilldownTab = nil
            row._barFraction = nil
            row._sectionHeader = false
            if row._sectionTitle then row._sectionTitle:SetText(""); row._sectionTitle:Hide() end
            if row._sectionLine then row._sectionLine:Hide() end
            if row._bar then row._bar:Hide() end
            if row._stripe then
                if dataIndex % 2 == 0 then
                    row._stripe:SetColorTexture(unpack(p.rowAlt))
                else
                    row._stripe:SetColorTexture(0, 0, 0, 0)
                end
            end
            row:Show()
        end
    end
    for i = used + 1, #f._rows do
        local row = f._rows[i]
        if row then row:Hide() end
    end
    self:ApplyLedgerColumnLayout()
end

function module:ShowWindow()
    self:EnsureWindow()
    if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme(self.window) end
    self:ApplyWindowSize()
    self:ApplyWindowPosition()
    local dt = self.settings and self.settings.defaultTab
    if dt and dt ~= "last" and self.windowState then
        self.windowState.tab = dt
    end
    self.window:Show()
    self:RefreshWindow()
end

function module:ClearWindowDisplay()
    local f = self.window
    if not f then return end
    self:CancelDailyTrendBuild()
    for _, row in ipairs(f._rows or {}) do
        if row._time then row._time:SetText("") end
        if row._kind then row._kind:SetText("") end
        if row._type then row._type:SetText("") end
        if row._who then row._who:SetText("") end
        if row._amount then row._amount:SetText("") end
        if row._amountSign then row._amountSign:SetText("") end
        if row._amountGold then row._amountGold:SetText("") end
        if row._amountSilver then row._amountSilver:SetText("") end
        if row._amountCopper then row._amountCopper:SetText("") end
        if row._detail then row._detail:SetText("") end
        if row._sectionTitle then row._sectionTitle:SetText("") end
        if row._bar then row._bar:Hide() end
        if row._sectionLine then row._sectionLine:Hide() end
        row._itemLink = nil
        row._itemName = nil
        row._questID = nil
        row._questName = nil
        row._entryRef = nil
        row._settingKey = nil
        row._itemFilterToggle = nil
        row._drilldownSearch = nil
        row._drilldownTab = nil
        row._barFraction = nil
        row._sectionHeader = nil
        row._amountCopperValue = nil
        row:Hide()
    end
    local chart = f._trendChart
    if chart then
        HideObjectPool(chart._gridPool)
        HideObjectPool(chart._barPool)
        HideObjectPool(chart._linePool)
        HideObjectPool(chart._glowPool)
        HideObjectPool(chart._pointPool)
        HideObjectPool(chart._labelPool)
        for _, hit in ipairs(chart._hitPool or {}) do
            hit._dayData = nil
            hit._dayLabel = nil
            hit._palette = nil
            hit._cumValue = nil
            hit._avgValue = nil
            hit._showCum = nil
            hit._showAvg = nil
            hit._avgWindow = nil
            hit:Hide()
        end
        chart:Hide()
    end
    if f._content then f._content:SetHeight(10) end
    f._listSource = nil
    f._listPalette = nil
    f._isVirtualList = false
    f._listSignature = nil
end

function module:HideWindow()
    if self.window then
        self:ClearWindowDisplay()
        self.window:Hide()
        -- Drop other characters' history back to blobs now the window is gone,
        -- so viewing "all characters" does not leave their entries resident.
        -- With a valid blob this is just nil-ing the live tables (no re-serialize),
        -- so it stays cheap even for a 100k-entry view.
        if self.CompactInactiveShards then self:CompactInactiveShards() end
        -- NO forced collectgarbage("collect") here. A full collect on a heap with
        -- ~100k just-dropped tables is a multi-second stop-the-world freeze on
        -- close. The dropped tables are unreachable now, so WoW's incremental GC
        -- reclaims them over the next frames with no pause -- memory settles back
        -- down within a second or two. (/accstress compact still does an explicit
        -- collect for an immediate measurement when asked.)
    end
end

function module:ToggleWindow()
    if self.window and self.window:IsShown() then
        self:HideWindow()
    else
        self:ShowWindow()
    end
end

function module:InstallUIHooks()
    if self.uiHooksInstalled then return end
    if type(_G.hooksecurefunc) == "function" and ns.UI and type(ns.UI.ReapplyAll) == "function" then
        hooksecurefunc(ns.UI, "ReapplyAll", function()
            if module.window and module.window:IsShown() then
                module:RefreshWindow()
            end
        end)
        self.uiHooksInstalled = true
    end
end

