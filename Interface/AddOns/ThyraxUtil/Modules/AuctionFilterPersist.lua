local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "auction_filter_persist",
    name = "AH Filter Persist",
    version = ns.Versions.AUCTION_FILTER_PERSIST,
    source = "core",
    internal = true,
    subtitle = "Remembers your Browse-tab filters between sessions.",
    onboardingDescription =
    "The Auction House Browse tab resets level range, rarity, and other filters every time you open it. This module persists them across sessions and shows the active set in a small overlay above the AH window.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\ahfilter.tga",
    -- We listen for the LoD load via ADDON_LOADED, plus the open/close pair.
    events = {
        "ADDON_LOADED",
        "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED",
    },
    defaults = {
        enabled = false,
        -- User-facing toggles (configured via Options Panel).
        showOverlay     = true,
        autoSave        = true,
        -- (Removed: autoApplySearch. Opening the AH never auto-searches now.
        -- User actions on the overlay -- chip clicks, reset, level/category
        -- clears -- always trigger a fresh search to give immediate feedback.)
        -- Per-chip visibility (lets the user hide chip groups they never use).
        showLevelChip    = true,
        showCategoryChip = true,
        showToggleChips  = true,
        showRarityDots   = true,
        customTheme      = false,
        accentColor      = { 0.95, 0.85, 0.45, 1 },
        surfaceColor     = { 0.16, 0.13, 0.07, 0.85 },
        -- Persisted filter state (account-wide via ThyraxUtilDB).
        -- Empty defaults = "no preference" -> use Blizzard's defaults on first open.
        -- Once the user actually changes a filter, we capture and persist it here.
        minLevel = nil,
        maxLevel = nil,
        -- filters keyed by Enum.AuctionHouseFilter integer value.
        filters = {},
        -- itemClassFilters captures the left-side category sidebar selection
        -- (Weapons / Armor / Containers / etc). Stored as the same array shape
        -- the AH consumes: { { classID, subClassID, inventoryType }, ... }.
        itemClassFilters = {},
    },
}

-- Constants
module.CONSTANTS = {
    -- Enum.AuctionHouseFilter values are stable from 9.0+ and documented on Warcraft Wiki.
    -- We don't read Enum.AuctionHouseFilter directly in case the global isn't loaded yet.
    FILTER_UNCOLLECTED   = 1,
    FILTER_USABLE        = 2,
    FILTER_CURRENT_EXP   = 3,
    FILTER_UPGRADES      = 4,
    FILTER_POOR          = 6,
    FILTER_COMMON        = 7,
    FILTER_UNCOMMON      = 8,
    FILTER_RARE          = 9,
    FILTER_EPIC          = 10,
    FILTER_LEGENDARY     = 11,
    FILTER_ARTIFACT      = 12,

    AH_ADDON = "Blizzard_AuctionHouseUI",

    -- Overlay dimensions (Modern theme; Classic uses Blizzard backdrop and may be slightly taller).
    OVERLAY_HEIGHT     = 28,
    OVERLAY_PADDING    = 8,
    CHIP_PADDING_X     = 8,
    CHIP_HEIGHT        = 18,
    CHIP_GAP           = 4,
    DOT_SIZE           = 12,
    DOT_GAP            = 3,

    -- Visual feedback timing (seconds).
    SAVED_PULSE_DURATION = 0.4,

    -- Delay between AUCTION_HOUSE_SHOW and our restore push (seconds). Gives
    -- Blizzard's Browse panel a frame to finish its own initialization first.
    APPLY_DELAY = 0.05,

    -- Quality color fallback if ITEM_QUALITY_COLORS isn't populated yet.
    DEFAULT_QUALITY_COLORS = {
        [0] = { 0.62, 0.62, 0.62 },  -- Poor (grey)
        [1] = { 1.00, 1.00, 1.00 },  -- Common (white)
        [2] = { 0.12, 1.00, 0.00 },  -- Uncommon (green)
        [3] = { 0.00, 0.44, 0.87 },  -- Rare (blue)
        [4] = { 0.64, 0.21, 0.93 },  -- Epic (purple)
        [5] = { 1.00, 0.50, 0.00 },  -- Legendary (orange)
        [6] = { 0.90, 0.80, 0.50 },  -- Artifact (light tan)
    },
}

-- Mapping from rarity-filter enum to Blizzard quality index for color lookup.
module.CONSTANTS.RARITY_TO_QUALITY = {
    [module.CONSTANTS.FILTER_POOR]      = 0,
    [module.CONSTANTS.FILTER_COMMON]    = 1,
    [module.CONSTANTS.FILTER_UNCOMMON]  = 2,
    [module.CONSTANTS.FILTER_RARE]      = 3,
    [module.CONSTANTS.FILTER_EPIC]      = 4,
    [module.CONSTANTS.FILTER_LEGENDARY] = 5,
    [module.CONSTANTS.FILTER_ARTIFACT]  = 6,
}

-- Display order and labels for the toggle chips (non-rarity filters).
-- Rarity is rendered separately as colored dots.
module.CONSTANTS.TOGGLE_CHIPS = {
    { id = module.CONSTANTS.FILTER_UNCOLLECTED, label = "Uncollected" },
    { id = module.CONSTANTS.FILTER_USABLE,      label = "Usable" },
    { id = module.CONSTANTS.FILTER_CURRENT_EXP, label = "Current Exp" },
    { id = module.CONSTANTS.FILTER_UPGRADES,    label = "Upgrades" },
}

-- Stable rarity dot order (Poor -> Artifact, left to right).
module.CONSTANTS.RARITY_ORDER = {
    module.CONSTANTS.FILTER_POOR,
    module.CONSTANTS.FILTER_COMMON,
    module.CONSTANTS.FILTER_UNCOMMON,
    module.CONSTANTS.FILTER_RARE,
    module.CONSTANTS.FILTER_EPIC,
    module.CONSTANTS.FILTER_LEGENDARY,
    module.CONSTANTS.FILTER_ARTIFACT,
}

-- Tooltip text per filter id.
module.CONSTANTS.FILTER_TOOLTIPS = {
    [module.CONSTANTS.FILTER_UNCOLLECTED] = "Uncollected appearances/mounts/pets only",
    [module.CONSTANTS.FILTER_USABLE]      = "Items usable by your class/spec only",
    [module.CONSTANTS.FILTER_CURRENT_EXP] = "Current expansion items only",
    [module.CONSTANTS.FILTER_UPGRADES]    = "Items that are equipment upgrades only",
    [module.CONSTANTS.FILTER_POOR]        = "Poor quality (grey)",
    [module.CONSTANTS.FILTER_COMMON]      = "Common quality (white)",
    [module.CONSTANTS.FILTER_UNCOMMON]    = "Uncommon quality (green)",
    [module.CONSTANTS.FILTER_RARE]        = "Rare quality (blue)",
    [module.CONSTANTS.FILTER_EPIC]        = "Epic quality (purple)",
    [module.CONSTANTS.FILTER_LEGENDARY]   = "Legendary quality (orange)",
    [module.CONSTANTS.FILTER_ARTIFACT]    = "Artifact quality",
}

-- ============================================================================
-- State helpers
-- ============================================================================

local function GetQualityColor(qualityIndex)
    if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[qualityIndex] then
        local c = _G.ITEM_QUALITY_COLORS[qualityIndex]
        return c.r or 1, c.g or 1, c.b or 1
    end
    local fallback = module.CONSTANTS.DEFAULT_QUALITY_COLORS[qualityIndex]
    if fallback then
        return fallback[1], fallback[2], fallback[3]
    end
    return 1, 1, 1
end

-- Whether the saved state has any actual content.
function module:HasAnyFilters()
    local s = self.settings
    if not s then return false end
    if s.minLevel or s.maxLevel then return true end
    if type(s.filters) == "table" then
        for _ in pairs(s.filters) do return true end
    end
    if type(s.itemClassFilters) == "table" and #s.itemClassFilters > 0 then
        return true
    end
    return false
end

-- Deep-equal helper for short flat tables. Used to short-circuit polling so
-- we don't fire RefreshOverlay/FlashSavedPulse every 0.5s while idle.
local function FiltersEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k in pairs(a) do if a[k] ~= b[k] then return false end end
    for k in pairs(b) do if a[k] ~= b[k] then return false end end
    return true
end

local function ItemClassListsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if type(x) ~= "table" or type(y) ~= "table" then return false end
        if x.classID ~= y.classID or x.subClassID ~= y.subClassID
            or x.inventoryType ~= y.inventoryType then
            return false
        end
    end
    return true
end

-- AH frame accessors. Declared here, BEFORE every consumer: ResetAllFilters
-- (further down) compiles a reference to whatever `GetFilterButton` is in
-- scope at that point, so defining these below it made that reference resolve
-- to the global (nil) and the Options Panel "Clear AH Filters" button raised
-- "attempt to call a nil value".
--
-- The dropdown filter state in WoW 12.0 lives on AuctionHouseFrame.SearchBar
-- .FilterButton. This holds .filters (keyed table), .minLevel, .maxLevel and
-- a :GetFilters() method. The dump diagnostic (/thyrax ahdump) confirmed this
-- layout in 12.0.5.
local function GetFilterButton()
    local af = _G.AuctionHouseFrame
    if af and af.SearchBar and af.SearchBar.FilterButton then
        return af.SearchBar.FilterButton
    end
    return nil
end

-- Browse results panel -- owns the searchContext (only after a Search runs)
-- and the SetSearchContext / GetSearchContext methods we use to trigger a
-- refresh after writing our saved filters back into FilterButton.
local function GetBrowseResultsFrame()
    local af = _G.AuctionHouseFrame
    if af and af.BrowseResultsFrame then
        return af.BrowseResultsFrame
    end
    return nil
end

-- Legacy alias kept for back-compat with older code paths inside this module
-- that still expect (owner, ctx). New code should use GetFilterButton +
-- GetBrowseResultsFrame directly.
local function GetBrowseContext()
    local brf = GetBrowseResultsFrame()
    if brf and brf.searchContext then
        return brf, brf.searchContext
    end
    return nil
end

-- Snapshot a Blizzard-built browse query (or live searchContext) into our
-- persisted form. We only keep filters, level range, and itemClassFilters;
-- searchString and sorts intentionally don't persist (per user preference --
-- those are per-search, not preferences).
-- Returns true if the snapshot actually changed our saved state. The caller
-- uses that signal to decide whether to flash the "saved" pulse.
--
-- Important: 0 in minLevel/maxLevel means "the input box is empty", NOT
-- "level 0 only". Treat it as nil so the overlay doesn't render "Lv 0-0".
-- And nil/empty `filters` from the AH means "the dropdown isn't initialized
-- yet" (transient during AH open) -- DO NOT clear our saved state in that
-- case, that's how state gets randomly wiped.
function module:SnapshotFromQuery(query)
    if type(query) ~= "table" or not self.settings then return false end

    local s = self.settings
    local changed = false

    local function asLevel(v)
        if type(v) ~= "number" then return nil end
        if v <= 0 then return nil end
        return v
    end

    local newMin = asLevel(query.minLevel)
    local newMax = asLevel(query.maxLevel)
    if s.minLevel ~= newMin or s.maxLevel ~= newMax then
        s.minLevel = newMin
        s.maxLevel = newMax
        changed = true
    end

    -- Filters: Blizzard's FilterButton.filters is a KEYED table
    -- ({[enumValue]=bool, ...}) per AuctionHouseFilterButtonMixin source.
    -- C_AuctionHouse.SendBrowseQuery, however, takes the array form. We
    -- accept either shape and normalize to keyed for our saved state.
    -- We still skip nil/empty so we don't wipe saved state during the brief
    -- post-reset / pre-fully-initialized window.
    if type(query.filters) == "table" then
        local newFilters = {}
        local sawAny = false
        -- Detect array vs keyed: arrays have at least one numeric value at
        -- index 1; keyed tables have boolean values keyed by enum number.
        local v1 = rawget(query.filters, 1)
        if type(v1) == "number" then
            -- Array form: { 1, 3, 6, 7, ... }
            for _, enumValue in ipairs(query.filters) do
                if type(enumValue) == "number" then
                    newFilters[enumValue] = true
                    sawAny = true
                end
            end
        else
            -- Keyed form: { [1]=true, [3]=true, [6]=true, ... }
            for enumValue, isOn in pairs(query.filters) do
                if type(enumValue) == "number" and isOn then
                    newFilters[enumValue] = true
                    sawAny = true
                end
            end
        end
        if sawAny and not FiltersEqual(s.filters or {}, newFilters) then
            s.filters = newFilters
            changed = true
        end
    end

    -- itemClassFilters: same defensive logic. Only overwrite if the source
    -- actually returned a table (treat nil as "AH didn't tell us", not as
    -- "no categories"). Empty array is a legitimate user state, so allow
    -- that path.
    if type(query.itemClassFilters) == "table" then
        local newClasses = {}
        for i, entry in ipairs(query.itemClassFilters) do
            if type(entry) == "table" then
                newClasses[i] = {
                    classID       = entry.classID,
                    subClassID    = entry.subClassID,
                    inventoryType = entry.inventoryType,
                }
            end
        end
        if not ItemClassListsEqual(s.itemClassFilters or {}, newClasses) then
            s.itemClassFilters = newClasses
            changed = true
        end
    end

    if changed then
        self:RefreshOverlay()
    end
    return changed
end

-- Toggle a single filter id and refresh overlay. Used by chip / dot click handlers.
function module:ToggleFilter(enumValue)
    self.toggleCount = (self.toggleCount or 0) + 1
    self.lastToggleId = enumValue
    self.lastToggleTime = (GetTimePreciseSec and GetTimePreciseSec()) or 0
    if not self.settings then return end
    self.settings.filters = self.settings.filters or {}
    if self.settings.filters[enumValue] then
        self.settings.filters[enumValue] = nil
    else
        self.settings.filters[enumValue] = true
    end
    self:RefreshOverlay()
    self:FlashSavedPulse()
    -- If the AH is currently open, push the change live AND trigger a fresh
    -- browse query so the results panel updates immediately. RestoreAndSearch
    -- is the canonical "user did something, react now" path.
    if self.ahOpen then
        self:RestoreAndSearch()
    end
end

-- Reset all filters by directly emulating what Blizzard's X-button OnClick
-- handler does internally:
--    self.ClearFiltersButton:SetScript("OnClick", function() self:Reset() end)
-- We just call fb:Reset() ourselves -- no Click() simulation, no reliance on
-- the HookScript firing. The previous Click()-based version did not fire
-- HookScript handlers (verified via dev report: blizzard-clear was never
-- in firstFires after R press), so we just do everything inline.
function module:ResetAllFilters()
    self.resetClickCount = (self.resetClickCount or 0) + 1
    self.lastResetTime = (GetTimePreciseSec and GetTimePreciseSec()) or 0

    -- 1. Reset Blizzard's FilterButton state (same as X-click does).
    local fb = GetFilterButton()
    if fb and type(fb.Reset) == "function" then
        self.suppressCapture = true
        pcall(fb.Reset, fb)
        self.suppressCapture = false
    end

    -- 2. Sync the dropdown's "X" visibility (Reset hides it but we ensure).
    local af = _G.AuctionHouseFrame
    local sb = af and af.SearchBar
    if sb and type(sb.UpdateClearFiltersButton) == "function" then
        self.suppressCapture = true
        pcall(sb.UpdateClearFiltersButton, sb)
        self.suppressCapture = false
    end

    -- 3. Force the dropdown menu to rebuild from the now-default state.
    if fb and type(fb.GenerateMenu) == "function" then
        self.suppressCapture = true
        pcall(fb.GenerateMenu, fb)
        self.suppressCapture = false
    end

    -- 4. Sync our saved filters to AUCTION_HOUSE_DEFAULT_FILTERS so the
    --    overlay rarity dots stay LIT after reset (matching the dropdown,
    --    which has all 7 rarities checked at game default). Setting saved
    --    to {} would leave the overlay all-dim while the dropdown shows
    --    rarities checked -- visually inconsistent.
    if self.settings then
        self.settings.minLevel = nil
        self.settings.maxLevel = nil
        self.settings.itemClassFilters = {}
        local defaults = _G.AUCTION_HOUSE_DEFAULT_FILTERS
        if type(defaults) == "table" then
            local copy = {}
            for k, v in pairs(defaults) do copy[k] = v and true or false end
            self.settings.filters = copy
        else
            self.settings.filters = {}
        end
    end

    -- 5. Refresh overlay + pulse to reflect cleared state.
    self:RefreshOverlay()
    self:FlashSavedPulse()

    -- 6. Trigger a fresh search so the results panel updates.
    if self.ahOpen then
        self:TriggerSearch()
    end
end

-- ============================================================================
-- AH integration
-- ============================================================================

-- Build the keyed-table form Blizzard's FilterButton expects.
-- Per AuctionHouseFilterButtonMixin source, self.filters is { [enum]=bool }.
function module:BuildFiltersKeyed()
    local s = self.settings
    if not s or type(s.filters) ~= "table" then return {} end
    local out = {}
    for enumValue, isOn in pairs(s.filters) do
        out[enumValue] = isOn and true or false
    end
    return out
end

-- Write saved filters into the live FilterButton + sync the dropdown's
-- clear button. This is the SILENT path -- it never triggers an actual
-- browse query, so opening the AH never causes a surprise search.
function module:RestoreFilterButtonState()
    if not self.ahLoaded then return end
    if not self:HasAnyFilters() then return end

    local af = _G.AuctionHouseFrame
    local fb = GetFilterButton()
    if not fb then return end

    -- Write KEYED filter state to FilterButton (Blizzard's actual format).
    -- Only overwrite if we have saved filters; an empty merge would clear
    -- the rarity checkboxes and break the next search.
    local savedKeyed = self:BuildFiltersKeyed()
    if next(savedKeyed) ~= nil then
        -- Mutate fb.filters in place so we don't break Blizzard's own
        -- references to that table. We write explicit FALSE for unsaved
        -- filter slots that are in AUCTION_HOUSE_DEFAULT_FILTERS so the
        -- table shape matches what Blizzard's tCompare expects.
        fb.filters = fb.filters or {}
        local defaults = _G.AUCTION_HOUSE_DEFAULT_FILTERS
        if type(defaults) == "table" then
            -- Wipe then write every known slot (true if saved, false otherwise).
            for k in pairs(fb.filters) do fb.filters[k] = nil end
            for k in pairs(defaults) do fb.filters[k] = savedKeyed[k] and true or false end
            -- Also include any saved keys not in the defaults table (defensive
            -- against future filter enums).
            for k, v in pairs(savedKeyed) do fb.filters[k] = v end
        else
            -- Fallback if the defaults global isn't loaded (shouldn't happen).
            for k in pairs(fb.filters) do fb.filters[k] = nil end
            for k, v in pairs(savedKeyed) do fb.filters[k] = v end
        end
    end

    -- Level range: 0/0 is Blizzard's "unset" sentinel. Write 0 instead of
    -- nil so the dropdown's LevelRangeFrameTemplate stays happy.
    fb.minLevel = self.settings.minLevel or 0
    fb.maxLevel = self.settings.maxLevel or 0

    -- Resync the dropdown's "X" clear button visibility.
    local sb = af and af.SearchBar
    if sb and type(sb.UpdateClearFiltersButton) == "function" then
        self.suppressCapture = true
        pcall(sb.UpdateClearFiltersButton, sb)
        self.suppressCapture = false
    end

    -- CRITICAL: Force the dropdown to rebuild its menu from the NOW-current
    -- FilterButton state. Per Blizzard's MenuImplementationGuide:
    --   "if code external to the dropdown causes the logical state to
    --    change, the dropdown needs to be notified to update. This is
    --    most easily done by calling GenerateMenu() on the dropdown to
    --    cause a new root description to be created."
    -- Without this call, dropdown checkboxes show stale state until the
    -- user closes + reopens the dropdown -- which was the persistent
    -- "addon changes WoW UI only after AH window reopen" complaint.
    if type(fb.GenerateMenu) == "function" then
        self.suppressCapture = true
        pcall(fb.GenerateMenu, fb)
        self.suppressCapture = false
    end
end

-- Trigger a fresh browse query via Blizzard's StartSearch pipeline.
-- Returns true if a search was actually issued. Heavily instrumented because
-- this path has been the source of multiple silent failures during dev.
function module:TriggerSearch()
    local af = _G.AuctionHouseFrame
    local sb = af and af.SearchBar
    local fb = sb and sb.FilterButton

    self.searchAttempts = (self.searchAttempts or 0) + 1
    self.lastSearchAttemptTime = (GetTimePreciseSec and GetTimePreciseSec()) or 0

    if not sb or type(sb.StartSearch) ~= "function" then
        self.lastSearchError = "sb or StartSearch missing"
        if ns.Diagnostics then
            ns.Diagnostics:Warn("AH Filter Persist: TriggerSearch -> SearchBar or StartSearch missing.")
        end
        return false
    end

    -- Pre-flight: snapshot what StartSearch will see when it runs. If this
    -- doesn't match expectations the bug is upstream of StartSearch.
    local fbCount = 0
    if fb and type(fb.filters) == "table" then
        for _, v in pairs(fb.filters) do if v then fbCount = fbCount + 1 end end
    end
    self.lastSearchPreflight = string.format(
        "fb.filters#=%d minLevel=%s maxLevel=%s",
        fbCount,
        tostring(fb and fb.minLevel or "?"),
        tostring(fb and fb.maxLevel or "?")
    )

    -- Track whether the actual SendBrowseQuery fired during StartSearch.
    -- We use searchHookFireCount (bumped unconditionally inside the hook,
    -- BEFORE the suppressCapture check) so this works even though we set
    -- suppressCapture=true around the call to avoid the snapshot-echo loop.
    -- Previously this used captureCount, which was suppressed during our
    -- own call -- so the delta was always 0 and the "silent early-return"
    -- diagnosis fired even when the search worked.
    local fireBefore = self.searchHookFireCount or 0

    self.suppressCapture = true
    local ok, err = pcall(sb.StartSearch, sb)
    self.suppressCapture = false

    local fireAfter = self.searchHookFireCount or 0
    self.lastSearchSendDelta = fireAfter - fireBefore   -- expected: 1 if SendBrowseQuery actually ran

    if not ok then
        self.lastSearchError = tostring(err)
        if ns.Diagnostics then
            ns.Diagnostics:Warn(("AH Filter Persist: StartSearch raised: %s"):format(tostring(err)))
        end
        return false
    end

    -- If the search hook didn't fire, the call returned cleanly but never
    -- actually issued a SendBrowseQuery (most likely AreSortTypesLoaded() was
    -- false at call time, or some other internal early-return). Surface this
    -- so the user can see the silent-failure case in the dev report.
    if self.lastSearchSendDelta == 0 then
        self.lastSearchError = "StartSearch returned cleanly but SendBrowseQuery never fired (silent early-return)"
        if ns.Diagnostics then
            ns.Diagnostics:Warn("AH Filter Persist: StartSearch returned without issuing SendBrowseQuery.")
        end
        return false
    end

    self.lastSearchError = nil
    return true
end

-- Convenience: write saved state AND immediately refresh results. Used
-- by every "user actively changed something on the overlay" code path
-- (chip clicks, dot toggles, level/category clears, reset).
function module:RestoreAndSearch()
    self:RestoreFilterButtonState()
    self:TriggerSearch()
end

-- Schedule a search after a short debounce window so rapid dropdown
-- checkbox toggles don't spam one search per click. The latest scheduled
-- search wins; earlier scheduled ones become no-ops via a generation token.
function module:ScheduleDebouncedSearch()
    self.searchGen = (self.searchGen or 0) + 1
    local myGen = self.searchGen
    if not (_G.C_Timer and _G.C_Timer.After) then
        self:TriggerSearch()
        return
    end
    _G.C_Timer.After(0.25, function()
        if not module.isActive or not module.ahOpen then return end
        if module.searchGen ~= myGen then return end  -- a newer toggle won
        module:TriggerSearch()
    end)
end

-- Hook installation: runs once after Blizzard_AuctionHouseUI loads.
--
-- IMPORTANT: We hook the FRAME INSTANCES, not the mixin tables. WoW's
-- Mixin() helper copies methods directly into the frame at construction
-- time (it doesn't use metatable inheritance), so hooking the mixin table
-- AFTER the frame is created has no effect on the live instance. Every
-- previous version of this file made that mistake -- which is why "nothing
-- worked at all" on the user's machine.
--
-- Three frame-level hooks (verified against the live FrameXML):
--   1. AuctionHouseFrame.SearchBar.FilterButton:Reset        - fires inside
--      SearchBar:OnShow on every AH open; we re-apply saved state after.
--   2. AuctionHouseFrame.SearchBar:UpdateClearFiltersButton  - fires on
--      every dropdown checkbox toggle and every level-range edit.
--   3. AuctionHouseFrame:SendBrowseQuery                     - fires on
--      Search-button clicks (Blizzard's wrapper, distinct from C_AuctionHouse.*).
function module:InstallAHHooks()
    if self.hooksInstalled then return end

    local af = _G.AuctionHouseFrame
    local sb = af and af.SearchBar
    local fb = sb and sb.FilterButton
    if not af or not sb or not fb then
        if ns.Diagnostics then
            ns.Diagnostics:Warn("AH Filter Persist: AuctionHouseFrame.SearchBar.FilterButton not present; cannot install hooks yet.")
        end
        return
    end

    -- Per-hook "first fire" tracker. The counter is always populated so the
    -- dev report (/devreport) can verify hook health, but the chat output
    -- only fires under verbose mode (Settings.debug.verbose) so normal play
    -- stays quiet.
    module.firstFires = module.firstFires or {}
    local function logFirstFire(reason)
        if module.firstFires[reason] then return end
        module.firstFires[reason] = true
        if ns.Diagnostics and ns.Diagnostics.Debug then
            ns.Diagnostics:Debug(("AH Filter Persist: hook fired (%s) for the first time."):format(reason))
        end
    end

    local function captureFromFilterButton(reason)
        if module.suppressCapture or not module.isActive then return end
        logFirstFire(reason)
        local query = {
            minLevel         = fb.minLevel,
            maxLevel         = fb.maxLevel,
            filters          = fb.filters,            -- keyed table; SnapshotFromQuery handles both shapes
            itemClassFilters = nil,                   -- not on FilterButton; from BrowseResultsFrame.searchContext
        }
        local _, ctx = GetBrowseContext()
        if ctx and type(ctx.itemClassFilters) == "table" then
            query.itemClassFilters = ctx.itemClassFilters
        end
        module.captureCount = (module.captureCount or 0) + 1
        module.lastCaptureReason = reason
        local changed = module:SnapshotFromQuery(query)
        if changed and module.settings and module.settings.autoSave ~= false then
            module:FlashSavedPulse()
        end

        -- Auto-search after a dropdown toggle so the user sees the change
        -- reflected in results immediately. Without this, dropdown checkbox
        -- clicks "save" silently but don't refresh results until the user
        -- manually clicks Search -- the persistent "only applies after
        -- reopen" complaint. We debounce via C_Timer so rapid toggles in
        -- one dropdown session don't fire one search per checkbox.
        if reason == "dropdown-change" and changed then
            module:ScheduleDebouncedSearch()
        end
    end

    -- 1. Restore saved state on every SearchBar OnShow.
    --    HookScript (NOT hooksecurefunc) is critical here: WoW's XML
    --    mixin script handlers capture a direct function reference at
    --    frame creation time, so `hooksecurefunc(sb, "OnShow", ...)`
    --    never fires (verified via dev report -- onshow was missing
    --    from firstFires). HookScript adds a post-handler at the
    --    script-system level that always runs after Blizzard's OnShow.
    if type(sb.HookScript) == "function" then
        sb:HookScript("OnShow", function()
            logFirstFire("onshow")
            if not module.isActive then return end
            if module.suppressCapture then return end
            if not module:HasAnyFilters() then return end
            -- Defer one frame so SearchBar:OnShow finishes its own work
            -- (calling SearchBox:Reset and FilterButton:Reset) before our
            -- restore writes the saved state on top.
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if module.isActive and module.ahOpen then
                        module:RestoreFilterButtonState()
                    end
                end)
            else
                module:RestoreFilterButtonState()
            end
        end)
        self.resetHooked = true
    end

    -- When the user clicks Blizzard's "X" ClearFiltersButton in the dropdown,
    -- they intend to clear filters. We piggyback to also wipe our saved
    -- state -- otherwise the next AH open would silently restore the saved
    -- filters and the X click would feel ineffective ("doesn't work").
    if fb.ClearFiltersButton and type(fb.ClearFiltersButton.HookScript) == "function" then
        fb.ClearFiltersButton:HookScript("OnClick", function()
            if not module.isActive then return end
            logFirstFire("blizzard-clear")
            module.settings.minLevel        = nil
            module.settings.maxLevel        = nil
            module.settings.itemClassFilters = {}
            -- Mirror AUCTION_HOUSE_DEFAULT_FILTERS into saved so overlay
            -- rarities stay LIT after the X-click reset (matches dropdown).
            local defaults = _G.AUCTION_HOUSE_DEFAULT_FILTERS
            if type(defaults) == "table" then
                local copy = {}
                for k, v in pairs(defaults) do copy[k] = v and true or false end
                module.settings.filters = copy
            else
                module.settings.filters = {}
            end
            module:RefreshOverlay()
            module:FlashSavedPulse()
        end)
        self.clearButtonHooked = true
    end

    -- 2. Capture filter changes from the dropdown (toggle + level edits).
    if type(sb.UpdateClearFiltersButton) == "function" then
        hooksecurefunc(sb, "UpdateClearFiltersButton", function()
            captureFromFilterButton("dropdown-change")
        end)
        self.captureHooked = true
    end

    -- 3. Catch Search-button clicks. AuctionHouseFrame:SendBrowseQuery is
    --    the wrapper Blizzard's SearchBar:StartSearch calls into. Fall back
    --    to C_AuctionHouse.SendBrowseQuery for clients/forks where the
    --    method isn't on the AuctionHouseFrame instance.
    --
    -- IMPORTANT: searchHookFireCount is bumped BEFORE the suppressCapture
    -- check so TriggerSearch can verify whether SendBrowseQuery actually
    -- ran during its own pcall(StartSearch) -- even when capture is
    -- suppressed to avoid echo loops. Without this, lastSearchSendDelta
    -- always read 0 and falsely reported "silent early-return".
    if type(af.SendBrowseQuery) == "function" then
        hooksecurefunc(af, "SendBrowseQuery", function()
            module.searchHookFireCount = (module.searchHookFireCount or 0) + 1
            captureFromFilterButton("search")
        end)
        self.searchHooked = true
    elseif type(_G.C_AuctionHouse) == "table" and type(_G.C_AuctionHouse.SendBrowseQuery) == "function" then
        hooksecurefunc(_G.C_AuctionHouse, "SendBrowseQuery", function()
            module.searchHookFireCount = (module.searchHookFireCount or 0) + 1
            captureFromFilterButton("search-c-api")
        end)
        self.searchHooked = true
    end

    self.hooksInstalled = true

    -- Hook-install summary -- verbose-only. Visible in /devreport unconditionally.
    if ns.Diagnostics and ns.Diagnostics.Debug then
        ns.Diagnostics:Debug(("AH Filter Persist hooks: reset=%s capture=%s search=%s"):format(
            tostring(self.resetHooked or false),
            tostring(self.captureHooked or false),
            tostring(self.searchHooked or false)
        ))
    end
end

-- Walk the AH frame tree and dump filter-related fields to /print so we can
-- find where the dropdown's checkbox state actually lives in this WoW build.
-- Triggered by the slash command registered in OnAuctionHouseLoaded.
function module:DumpAHStructure()
    local af = _G.AuctionHouseFrame
    if not af then
        print("|cffff8888ThyraxAH:|r AuctionHouseFrame not loaded -- open the AH first.")
        return
    end
    print("|cff95d955ThyraxAH dump:|r AuctionHouseFrame children + filter-shaped tables:")
    local function describe(t, path, depth)
        if depth > 3 then return end
        if type(t) ~= "table" then return end
        for k, v in pairs(t) do
            local key = tostring(k)
            local sub = path .. "." .. key
            if type(v) == "table" then
                -- Heuristic: any table with both "filters" and ("minLevel" or "maxLevel")
                -- is a strong candidate for the searchContext we need.
                if rawget(v, "filters") ~= nil
                    and (rawget(v, "minLevel") ~= nil or rawget(v, "maxLevel") ~= nil) then
                    print("  " .. sub .. "  |cffffd070<-- candidate (has filters + level)|r")
                end
                if key == "searchContext" or key == "filters"
                    or key == "FilterButton" or key == "BrowseResultsFrame"
                    or key == "SearchBar" or key == "filterDropDown" then
                    print("  " .. sub .. " (" .. type(v) .. ")")
                end
                describe(v, sub, depth + 1)
            elseif type(v) == "function" and (
                key == "GetFilters" or key == "SetFilters" or key == "GetSearchContext"
                or key == "SetSearchContext" or key == "GetCurrentFilters"
            ) then
                print("  " .. sub .. " (function)")
            end
        end
    end
    describe(af, "AuctionHouseFrame", 1)
    print("|cff95d955ThyraxAH dump complete.|r Look for 'candidate' lines.")
end

-- ============================================================================
-- Overlay UI
-- ============================================================================

-- Theme-aware palette. Modern uses Blizzard's golden style; Classic uses
-- a neutral grey. The overlay picks colors at every refresh so theme
-- changes via Options Panel propagate immediately.
-- Shared color helpers from Core/Color.lua. Call sites always pass an explicit
-- weight (0.48 / 0.68) and alpha (0.95), so ns.Color.Mix matches the old
-- MixThemeColor exactly; ns.Color.Normalize matches NormalizeThemeColor.
local NormalizeThemeColor = ns.Color.Normalize
local MixThemeColor = ns.Color.Mix

local function GetChipPalette()
    local theme = (ns.UI and ns.UI.GetTheme and ns.UI:GetTheme()) or "Modern"
    local palette
    if theme == "Classic" then
        palette = {
            overlayBg = { 0.10, 0.10, 0.10, 0.90 },
            overlayBorder = { 0, 0, 0, 1 },
            onBg      = { 0.20, 0.20, 0.22, 0.95 },
            offBg     = { 0.06, 0.06, 0.07, 0.85 },
            hoverBg   = { 0.34, 0.34, 0.38, 0.95 },
            onText    = { 1.00, 1.00, 1.00, 1 },
            offText   = { 0.55, 0.55, 0.55, 0.85 },
            titleText = { 0.85, 0.88, 0.95, 1 },
            pulse     = { 0.65, 0.75, 1.00 },
        }
    else
        -- Modern (golden, default)
        palette = {
            overlayBg = { 0.12, 0.09, 0.05, 0.92 },
            overlayBorder = { 0.68, 0.57, 0.26, 0.95 },
            onBg      = { 0.42, 0.34, 0.16, 0.95 },
            offBg     = { 0.16, 0.13, 0.07, 0.85 },
            hoverBg   = { 0.55, 0.46, 0.22, 0.95 },
            onText    = { 1.00, 0.92, 0.66, 1 },
            offText   = { 0.55, 0.50, 0.42, 0.85 },
            titleText = { 0.95, 0.85, 0.45, 1 },
            pulse     = { 0.95, 0.85, 0.45 },
        }
    end

    local settings = module.settings or module.defaults
    if settings and settings.customTheme == true then
        local accent = NormalizeThemeColor(settings.accentColor, palette.titleText)
        local surface = NormalizeThemeColor(settings.surfaceColor, palette.offBg)
        palette.overlayBg = { surface[1], surface[2], surface[3], 0.92 }
        palette.overlayBorder = { accent[1], accent[2], accent[3], 0.95 }
        palette.offBg = { surface[1], surface[2], surface[3], 0.85 }
        palette.onBg = MixThemeColor(surface, accent, 0.48, 0.95)
        palette.hoverBg = MixThemeColor(surface, accent, 0.68, 0.95)
        palette.titleText = { accent[1], accent[2], accent[3], 1 }
        palette.pulse = { accent[1], accent[2], accent[3] }
    else
        -- Custom theme OFF: inherit the global accent preset (so picking a
        -- non-Gold preset in the General page tints the AH overlay too).
        -- Gold preset = baseline Modern look, no override needed.
        local preset = (ns.UI and ns.UI.GetAccentPreset and ns.UI:GetAccentPreset()) or "Gold"
        local globalPalette = ns.UI and ns.UI.GetAccentPalette and ns.UI:GetAccentPalette() or nil
        if preset ~= "Gold" and globalPalette and globalPalette.accent and globalPalette.surface then
            local accent = globalPalette.accent
            local surface = globalPalette.surface
            palette.overlayBg = { surface[1], surface[2], surface[3], palette.overlayBg[4] }
            palette.overlayBorder = { accent[1], accent[2], accent[3], 0.95 }
            palette.offBg = { surface[1], surface[2], surface[3], palette.offBg[4] }
            palette.onBg = MixThemeColor(surface, accent, 0.48, 0.95)
            palette.hoverBg = MixThemeColor(surface, accent, 0.68, 0.95)
            palette.titleText = { accent[1], accent[2], accent[3], 1 }
            palette.pulse = { accent[1], accent[2], accent[3] }
        end
    end

    return palette
end

local function ApplyChipBaseColor(chip)
    -- RefreshOverlay sets _isOn; restore the matching base color after hover.
    local p = GetChipPalette()
    local color = chip._isOn and p.onBg or p.offBg
    chip._bg:SetColorTexture(unpack(color))
end

local function MakeChip(parent, label)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(module.CONSTANTS.CHIP_HEIGHT)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.16, 0.13, 0.07, 0.85)  -- starts in OFF style
    f._bg = bg
    f._isOn = false

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetText(label)
    f._text = text

    -- Width auto-fits the text.
    f:SetWidth(text:GetStringWidth() + module.CONSTANTS.CHIP_PADDING_X * 2)

    -- Hover state. We brighten on hover but restore the on/off base color
    -- on leave so off-state chips don't end up looking on after a hover.
    f:SetScript("OnEnter", function(self)
        local p = GetChipPalette()
        bg:SetColorTexture(unpack(p.hoverBg))
        if self._tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self._tooltip, 1, 1, 1, 1, true)
            local hint = self._isOn and "Click to disable this filter." or "Click to enable this filter."
            GameTooltip:AddLine(hint, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        ApplyChipBaseColor(self)
        GameTooltip:Hide()
    end)

    return f
end

local function MakeRarityDot(parent, qualityIndex)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(module.CONSTANTS.DOT_SIZE, module.CONSTANTS.DOT_SIZE)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    f._tex = tex
    f._quality = qualityIndex

    f:SetScript("OnEnter", function(self)
        if self._tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self._tooltip, 1, 1, 1, 1, true)
            local hint = self._isOn and "Click to disable this rarity." or "Click to enable this rarity."
            GameTooltip:AddLine(hint, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end


function module:EnsureOverlay()
    if self.overlay then return end
    local af = _G.AuctionHouseFrame
    if not af then return end

    local overlay = CreateFrame("Frame", "ThyraxAHFilterOverlay", af)
    overlay:SetHeight(self.CONSTANTS.OVERLAY_HEIGHT)
    -- Anchor flush to the top edge of the AH (no gap) so the strip reads as
    -- an integrated header extension rather than a detached floating panel.
    overlay:SetPoint("BOTTOMLEFT", af, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", af, "TOPRIGHT", 0, 0)
    overlay:Hide()

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(overlay, { border = true })
    end

    -- Title label (left edge).
    local title = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", overlay, "LEFT", self.CONSTANTS.OVERLAY_PADDING, 0)
    title:SetText("AH Filters:")
    title:SetTextColor(0.95, 0.85, 0.45, 1)
    overlay._title = title

    -- Category chip (item class sidebar selection: Weapons / Armor / etc.).
    local categoryChip = MakeChip(overlay, "Category")
    categoryChip:SetScript("OnClick", function() module:ResetItemClassFilters() end)
    categoryChip._tooltip = "Saved item class category (click to clear)"
    overlay._categoryChip = categoryChip

    -- Level-range chip (always present in the layout, hidden when unset).
    local levelChip = MakeChip(overlay, "Lv -")
    levelChip:SetScript("OnClick", function() module:ResetLevelRange() end)
    levelChip._tooltip = "Saved level range (click to clear)"
    overlay._levelChip = levelChip

    -- Toggle chips (Uncollected, Usable, Current Exp, Upgrades).
    overlay._toggleChips = {}
    for _, def in ipairs(self.CONSTANTS.TOGGLE_CHIPS) do
        local chip = MakeChip(overlay, def.label)
        chip._filterId = def.id
        chip._tooltip  = self.CONSTANTS.FILTER_TOOLTIPS[def.id] or def.label
        chip:SetScript("OnClick", function(self)
            module:ToggleFilter(self._filterId)
        end)
        overlay._toggleChips[def.id] = chip
    end

    -- Rarity dots (always 7, color/dim based on state).
    overlay._rarityDots = {}
    for _, enumValue in ipairs(self.CONSTANTS.RARITY_ORDER) do
        local q = self.CONSTANTS.RARITY_TO_QUALITY[enumValue]
        local dot = MakeRarityDot(overlay, q)
        dot._filterId = enumValue
        dot._tooltip  = self.CONSTANTS.FILTER_TOOLTIPS[enumValue] or "Rarity"
        dot:SetScript("OnClick", function(self)
            module:ToggleFilter(self._filterId)
        end)
        overlay._rarityDots[enumValue] = dot
    end

    -- (Removed: overlay's "R" reset button. Blizzard's built-in "X"
    -- ClearFiltersButton inside the dropdown is the single reset path now.
    -- The "Clear all saved AH filters" button in the Options Panel still
    -- calls ResetAllFilters for users who want to wipe state via settings.)

    -- "Saved" feedback flash texture (full-overlay overlay layer).
    local pulse = overlay:CreateTexture(nil, "OVERLAY")
    pulse:SetAllPoints(overlay)
    pulse:SetColorTexture(0.95, 0.85, 0.45, 0)
    overlay._pulse = pulse

    self.overlay = overlay
end

-- Recompute chip visibility, dot colors, level chip text based on current
-- saved state. Called any time filters change.
function module:RefreshOverlay()
    if not self.overlay then return end
    local s = self.settings
    if not s then return end

    local hasContent = self:HasAnyFilters()

    local palette = GetChipPalette()

    -- Apply theme-aware colors to the title and empty hint each refresh so
    -- theme changes (Modern <-> Classic) propagate without a /reload.
    if self.overlay.SetBackdrop and palette.overlayBg then
        self.overlay:SetBackdropColor(unpack(palette.overlayBg))
        self.overlay:SetBackdropBorderColor(unpack(palette.overlayBorder))
    end
    self.overlay._title:SetTextColor(unpack(palette.titleText))

    -- Level chip: shown when (showLevelChip is enabled) AND a level range
    -- is saved. Always rendered as ON visually because clicking clears it.
    local levelChip = self.overlay._levelChip
    local showLevel = (s.showLevelChip ~= false) and (s.minLevel or s.maxLevel)
    if showLevel then
        local lo = s.minLevel or 1
        local hi = s.maxLevel or "max"
        levelChip._text:SetText("Lv " .. tostring(lo) .. "-" .. tostring(hi))
        levelChip:SetWidth(levelChip._text:GetStringWidth() + self.CONSTANTS.CHIP_PADDING_X * 2)
        levelChip._isOn = true
        levelChip._bg:SetColorTexture(unpack(palette.onBg))
        levelChip._text:SetTextColor(unpack(palette.onText))
        levelChip:Show()
    else
        levelChip._isOn = false
        levelChip:Hide()
    end

    -- Category chip.
    local categoryChip = self.overlay._categoryChip
    local classCount = (type(s.itemClassFilters) == "table") and #s.itemClassFilters or 0
    local showCategory = (s.showCategoryChip ~= false) and classCount > 0
    if showCategory then
        local label
        if classCount == 1 and type(s.itemClassFilters[1]) == "table" then
            local entry = s.itemClassFilters[1]
            local className
            if type(_G.GetItemClassInfo) == "function" then
                local ok, name = pcall(_G.GetItemClassInfo, entry.classID)
                if ok and type(name) == "string" and name ~= "" then className = name end
            end
            label = "Cat: " .. (className or ("#" .. tostring(entry.classID)))
        else
            label = classCount .. " categories"
        end
        categoryChip._text:SetText(label)
        categoryChip:SetWidth(categoryChip._text:GetStringWidth() + self.CONSTANTS.CHIP_PADDING_X * 2)
        categoryChip._isOn = true
        categoryChip._bg:SetColorTexture(unpack(palette.onBg))
        categoryChip._text:SetTextColor(unpack(palette.onText))
        categoryChip:Show()
    else
        categoryChip._isOn = false
        categoryChip:Hide()
    end

    -- Toggle chips: ALWAYS visible when their group setting is enabled,
    -- regardless of saved-state content. Dim for OFF, lit for ON. The user
    -- can click a dim chip to enable that filter directly from the overlay
    -- without needing to first set up state via the Blizzard dropdown.
    local showToggles = (s.showToggleChips ~= false)
    for _, def in ipairs(self.CONSTANTS.TOGGLE_CHIPS) do
        local chip = self.overlay._toggleChips[def.id]
        if chip then
            local isOn = s.filters and s.filters[def.id] == true
            chip._isOn = isOn
            if isOn then
                chip._bg:SetColorTexture(unpack(palette.onBg))
                chip._text:SetTextColor(unpack(palette.onText))
            else
                chip._bg:SetColorTexture(unpack(palette.offBg))
                chip._text:SetTextColor(unpack(palette.offText))
            end
            chip:SetShown(showToggles)
        end
    end

    -- Rarity dots: ALWAYS visible when their group setting is enabled.
    -- Lit when ON, dim when OFF. Clicking a dim dot enables that rarity.
    local showRarities = (s.showRarityDots ~= false)
    for _, enumValue in ipairs(self.CONSTANTS.RARITY_ORDER) do
        local dot = self.overlay._rarityDots[enumValue]
        if dot then
            if not showRarities then
                dot:Hide()
            else
                local isOn = s.filters and s.filters[enumValue] == true
                dot._isOn = isOn
                local q = self.CONSTANTS.RARITY_TO_QUALITY[enumValue]
                local r, g, b = GetQualityColor(q)
                if isOn then
                    dot._tex:SetVertexColor(r, g, b, 1)
                else
                    dot._tex:SetVertexColor(r * 0.4, g * 0.4, b * 0.4, 0.35)
                end
                dot:Show()
            end
        end
    end

    -- Re-flow chips left to right after the title.
    self:LayoutChips()
end

function module:LayoutChips()
    if not self.overlay then return end
    local cursor = self.overlay._title
    local cursorEdge = "RIGHT"
    local function place(child)
        if not child or not child:IsShown() then return end
        child:ClearAllPoints()
        child:SetPoint("LEFT", cursor, cursorEdge, self.CONSTANTS.CHIP_GAP, 0)
        cursor = child
        cursorEdge = "RIGHT"
    end

    place(self.overlay._categoryChip)
    place(self.overlay._levelChip)
    for _, def in ipairs(self.CONSTANTS.TOGGLE_CHIPS) do
        place(self.overlay._toggleChips[def.id])
    end
    -- Rarity dots: a small group with their own internal spacing.
    local prev, prevEdge = cursor, cursorEdge
    for i, enumValue in ipairs(self.CONSTANTS.RARITY_ORDER) do
        local dot = self.overlay._rarityDots[enumValue]
        if dot then
            dot:ClearAllPoints()
            local gap = (i == 1) and self.CONSTANTS.CHIP_GAP * 2 or self.CONSTANTS.DOT_GAP
            dot:SetPoint("LEFT", prev, prevEdge, gap, 0)
            prev, prevEdge = dot, "RIGHT"
        end
    end
end

-- Brief themed flash on the overlay to confirm a save happened.
function module:FlashSavedPulse()
    if not self.overlay or not self.overlay._pulse then return end
    local pulse = self.overlay._pulse
    local p = GetChipPalette()
    pulse:SetColorTexture(p.pulse[1], p.pulse[2], p.pulse[3], 0)
    pulse:SetAlpha(0.35)
    -- AnimationGroup would be more idiomatic, but a single OnUpdate fade keeps
    -- the module dependency-free and works on every theme. The fade itself
    -- runs on a separate _pulseFader Frame (Textures don't have SetScript).
    local elapsed = 0
    local duration = self.CONSTANTS.SAVED_PULSE_DURATION
    -- (Removed: bogus `pulse:SetScript("OnUpdate", nil)` -- Texture has no
    -- SetScript method, so that line raised "attempt to call a nil value"
    -- and aborted ToggleFilter / ResetAllFilters / capture hooks before
    -- they could call RestoreAndSearch. That single line was the root
    -- cause of the persistent "addon changes only after reopen" bug.)
    local fader = self.overlay._pulseFader
    if not fader then
        fader = CreateFrame("Frame", nil, self.overlay)
        self.overlay._pulseFader = fader
    end
    fader:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        pulse:SetAlpha(0.35 * (1 - t))
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Inline level-range editor (very small footprint -- click the chip to clear).
-- Writes nil through to FilterButton too so the poll loop won't immediately
-- re-read the previous level value and resurrect the chip.
function module:ResetLevelRange()
    if not self.settings then return end
    self.settings.minLevel = nil
    self.settings.maxLevel = nil
    local fb = GetFilterButton()
    if fb then
        fb.minLevel = nil
        fb.maxLevel = nil
    end
    self:RefreshOverlay()
    self:FlashSavedPulse()
    if self.ahOpen then self:RestoreAndSearch() end
end

function module:ResetItemClassFilters()
    if not self.settings then return end
    self.settings.itemClassFilters = {}
    local _, ctx = GetBrowseContext()
    if ctx then ctx.itemClassFilters = {} end
    self:RefreshOverlay()
    self:FlashSavedPulse()
    if self.ahOpen then self:RestoreAndSearch() end
end

-- Settings -> overlay visibility. Called from the Options Panel.
function module:ApplyOverlayVisibility()
    if not self.overlay then return end
    if self.ahOpen and self.settings and self.settings.showOverlay ~= false then
        self.overlay:Show()
    else
        self.overlay:Hide()
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function module:OnAuctionHouseLoaded()
    self.ahLoaded = true
    -- InstallAHHooks may fail if AuctionHouseFrame.SearchBar.FilterButton
    -- isn't fully constructed yet at ADDON_LOADED time. We'll retry on
    -- AUCTION_HOUSE_SHOW (by which point all the XML frames definitely exist).
    self:InstallAHHooks()
    self:EnsureOverlay()

    -- First-run seeding: if saved.filters is still empty (fresh install or
    -- never interacted with the AH), populate it with Blizzard's defaults
    -- so the overlay rarity dots show LIT from the very first AH open --
    -- matching the dropdown which always shows rarities checked at game
    -- default. AUCTION_HOUSE_DEFAULT_FILTERS becomes available exactly
    -- here, after Blizzard_AuctionHouseUI has loaded.
    if self.settings and
        (type(self.settings.filters) ~= "table" or next(self.settings.filters) == nil) then
        local defaults = _G.AUCTION_HOUSE_DEFAULT_FILTERS
        if type(defaults) == "table" then
            local copy = {}
            for k, v in pairs(defaults) do copy[k] = v and true or false end
            self.settings.filters = copy
        end
    end

    self:RefreshOverlay()

    -- Re-paint the overlay whenever the user switches Modern <-> Classic
    -- theme via Options Panel. ns.UI:SetTheme is called by the theme
    -- dropdown's OnChange; piggybacking gives us live theme switching.
    if not self.themeHookInstalled and ns.UI and type(ns.UI.SetTheme) == "function" then
        hooksecurefunc(ns.UI, "SetTheme", function()
            if module.isActive and module.overlay then
                module:RefreshOverlay()
            end
        end)
        self.themeHookInstalled = true
    end
end

function module:OnAuctionHouseShow()
    self.ahOpen = true
    if not self.ahLoaded then
        local isLoaded = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded)
            or _G.IsAddOnLoaded
        if isLoaded and isLoaded(self.CONSTANTS.AH_ADDON) then
            self:OnAuctionHouseLoaded()
        end
    end
    -- Retry the hook install if the first attempt failed (frames not yet built).
    if not self.hooksInstalled then
        self:InstallAHHooks()
    end
    self:ApplyOverlayVisibility()
    self:RefreshOverlay()
    -- The OnShow hook re-applies our state automatically every time
    -- SearchBar:OnShow runs FilterButton:Reset. This explicit restore is
    -- just insurance for cold-paths (module enabled mid-session, hook
    -- install retried mid-session). Defer one frame to avoid racing the
    -- SearchBar:OnShow that fired alongside AUCTION_HOUSE_SHOW.
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(self.CONSTANTS.APPLY_DELAY, function()
            if self.isActive and self.ahOpen then
                self:RestoreFilterButtonState()
            end
        end)
    else
        self:RestoreFilterButtonState()
    end
end

function module:OnAuctionHouseClose()
    self.ahOpen = false
    if self.overlay then self.overlay:Hide() end
end

function module:OnEnable(settings)
    self.isActive = true
    self.settings = settings or self.defaults

    -- One-shot migration: nuke leftover `autoApplySearch` field from saves
    -- written by older versions of this module. The setting was removed
    -- entirely (auto-search is now scoped to user actions, never to AH-open),
    -- but stale values in saved DB confuse the dev report.
    if self.settings.autoApplySearch ~= nil then
        self.settings.autoApplySearch = nil
    end

    -- If the AH is already loaded (rare -- enabled mid-session via options),
    -- run the loaded hook immediately.
    local isLoaded = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded)
        or _G.IsAddOnLoaded
    if isLoaded and isLoaded(self.CONSTANTS.AH_ADDON) then
        self:OnAuctionHouseLoaded()
    end
end

function module:OnDisable()
    self.isActive = false
    self.ahOpen = false
    if self.overlay then self.overlay:Hide() end
end

-- Called when settings change via the Options Panel.
function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    self:ApplyOverlayVisibility()
    self:RefreshOverlay()
end

function module:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == self.CONSTANTS.AH_ADDON then
            self:OnAuctionHouseLoaded()
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        self:OnAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        self:OnAuctionHouseClose()
    end
end

-- Pretty-print the current module state to chat. Wired up to /thyrax ahstatus.
function module:PrintStatus()
    local s = self.settings or self.defaults
    local filterCount = 0
    local activeFilters = {}
    if type(s.filters) == "table" then
        for k, v in pairs(s.filters) do
            if v then
                filterCount = filterCount + 1
                activeFilters[#activeFilters + 1] = tostring(k)
            end
        end
    end
    table.sort(activeFilters)

    local lines = {
        "|cff95d955=== AH Filter Persist Status ===|r",
        ("isActive       : %s"):format(tostring(self.isActive or false)),
        ("ahLoaded       : %s"):format(tostring(self.ahLoaded or false)),
        ("ahOpen         : %s"):format(tostring(self.ahOpen or false)),
        ("hooksInstalled : %s"):format(tostring(self.hooksInstalled or false)),
        ("  resetHooked  : %s"):format(tostring(self.resetHooked or false)),
        ("  captureHooked: %s"):format(tostring(self.captureHooked or false)),
        ("  searchHooked : %s"):format(tostring(self.searchHooked or false)),
        ("captureCount   : %d (last: %s)"):format(self.captureCount or 0, tostring(self.lastCaptureReason or "-")),
        ("saved filters  : [%s]"):format(table.concat(activeFilters, ", ")),
        ("saved level    : min=%s max=%s"):format(tostring(s.minLevel or "-"), tostring(s.maxLevel or "-")),
        ("itemClass count: %d"):format(type(s.itemClassFilters) == "table" and #s.itemClassFilters or 0),
        ("settings: showOverlay=%s autoSave=%s"):format(
            tostring(s.showOverlay ~= false),
            tostring(s.autoSave ~= false)
        ),
        ("visibility: level=%s category=%s toggles=%s rarities=%s"):format(
            tostring(s.showLevelChip ~= false),
            tostring(s.showCategoryChip ~= false),
            tostring(s.showToggleChips ~= false),
            tostring(s.showRarityDots ~= false)
        ),
    }
    for _, line in ipairs(lines) do
        if ns.Diagnostics then ns.Diagnostics:Info(line) else print(line) end
    end

    -- Live FilterButton state for comparison.
    local fb = GetFilterButton()
    if fb then
        local liveCount = 0
        if type(fb.filters) == "table" then
            for _, v in pairs(fb.filters) do if v then liveCount = liveCount + 1 end end
        end
        if ns.Diagnostics then
            ns.Diagnostics:Info(("LIVE FilterButton: filters=%d minLevel=%s maxLevel=%s"):format(
                liveCount, tostring(fb.minLevel), tostring(fb.maxLevel)
            ))
        end
    else
        if ns.Diagnostics then ns.Diagnostics:Info("LIVE FilterButton: not present (open the AH first)") end
    end
end

function module:GetDebugState()
    local s = self.settings or self.defaults
    local filterCount = 0
    if type(s.filters) == "table" then
        for _ in pairs(s.filters) do filterCount = filterCount + 1 end
    end
    return {
        ahLoaded     = self.ahLoaded or false,
        ahOpen       = self.ahOpen or false,
        hooked       = self.hooksInstalled or false,
        captures     = self.captureCount or 0,
        filterCount  = filterCount,
        levelRange   = (s.minLevel or "-") .. "/" .. (s.maxLevel or "-"),
    }
end

ns.ModuleRegistry:Register(module)
