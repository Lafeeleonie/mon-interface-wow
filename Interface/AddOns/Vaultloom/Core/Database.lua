local _, Addon = ...

local Database = {
    currentSchemaVersion = 41,
    migrations = {},
}

Addon.Database = Database

local DATABASE_IDENTITY = "vaultloom-1"
local RECOVERY_VERSION = 1
local MAX_PERSISTED_TABLE_DEPTH = 64
local MAX_PERSISTED_TABLE_NODES = 100000

local VALID_FRAME_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local STAT_FOCUS_CONTENT_KEYS = { "solo", "delve", "raid", "mythicplus" }
local STAT_FOCUS_CONTENT_KEY_SET = {
    solo = true,
    delve = true,
    raid = true,
    mythicplus = true,
}

local function copyStatFocusOrder(order)
    local result = {}
    for index, stat in ipairs(type(order) == "table" and order or {}) do
        result[index] = stat
    end
    return #result > 0 and result or nil
end

local function normalizeStatFocusProfileRecord(profile, fallbackMode, fallbackOrder, fallbackBuildKey)
    profile = type(profile) == "table" and profile or {}
    local mode = profile.mode
    if mode ~= "custom" and mode ~= "preset" then
        mode = fallbackMode == "custom" and "custom" or "preset"
    end
    profile.mode = mode
    profile.order = type(profile.order) == "table" and profile.order
        or (mode == "custom" and copyStatFocusOrder(fallbackOrder) or nil)
    if mode ~= "custom" then
        profile.order = nil
    end
    profile.buildKey = type(profile.buildKey) == "string" and profile.buildKey ~= ""
        and profile.buildKey
        or (type(fallbackBuildKey) == "string" and fallbackBuildKey ~= "" and fallbackBuildKey)
        or "standard"
    return profile
end

local function normalizeStatFocusSpecRecord(record)
    if type(record) ~= "table" then
        return nil
    end
    local legacy = record.version ~= 2
    local legacyMode = record.mode == "custom" and "custom" or "preset"
    local legacyOrder = type(record.order) == "table" and record.order or nil
    local legacyBuildKey = type(record.buildKey) == "string" and record.buildKey ~= ""
        and record.buildKey or "standard"
    record.version = 2
    record.contentKey = STAT_FOCUS_CONTENT_KEY_SET[record.contentKey] and record.contentKey or "solo"
    record.profiles = type(record.profiles) == "table" and record.profiles or {}
    for _, contentKey in ipairs(STAT_FOCUS_CONTENT_KEYS) do
        record.profiles[contentKey] = normalizeStatFocusProfileRecord(
            record.profiles[contentKey],
            legacy and legacyMode or "preset",
            legacy and legacyOrder or nil,
            legacyBuildKey
        )
    end
    record.mode = nil
    record.order = nil
    record.buildKey = nil
    return record
end

local DEFAULTS = {
    databaseIdentity = DATABASE_IDENTITY,
    schemaVersion = 41,
    performanceDiagnostics = {
        armOnReload = false,
    },
    ui = {
        language = "auto",
        chatMessagesEnabled = true,
        sounds = {
            enabled = true,
        },
        welcomeSeenRelease = "",
        selectedScreen = "vault",
        selectedCharacterKey = nil,
        features = {
            selectedCategory = "all",
            activeOnly = false,
            seenNewFeatureReleases = {},
        },
        newIndicators = {
            seenReleases = {},
        },
        options = {
            selectedPage = "general",
            hiddenMainTabs = {},
            lastReadRelease = "",
        },
        minimap = {
            hide = false,
            minimapPos = 225,
        },
        selectedSubTabs = {
            vault = "raids",
            arsenal = "equipment",
            pve = "weekly",
            systems = "professions",
            raids = "midnight",
            dungeons = "midnight",
            mythicplus = "season2",
            housing = "endeavors",
            focus = "questboard",
        },
        housing = {
            switchMode = "ask",
            ignoredSwitches = {},
        },
        vault = {},
        raidJournal = {
            selectedRaidKey = "",
            selectedBossKey = "",
            difficultyKey = "normal",
            classFilterKey = "player",
        },
        dungeonJournal = {
            selectedRaidKeys = {},
            selectedBossKeys = {},
            difficultyKey = "normal",
            classFilterKey = "player",
        },
        mythicPlus = {},
        mythicPlusOverview = {
            viewMode = "overview",
            realmFilter = "all",
            keyFilter = "all",
            vaultFilter = "all",
            dataFilter = "all",
            sortMode = "attention",
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            },
        },
        compendium = {
            category = "all",
            status = "missing",
            source = "all",
            profession = "all",
            search = "",
        },
        wishlist = {
            status = "wish",
            source = "all",
        },
        hiddenUtilityResources = {},
        utility = {
            showUpgradeSection = true,
            showPvpSection = true,
            fixedSectionVisibilityVersion = 0,
        },
        warband = {
            cardStyle = "expanded",
            realmFilter = "all",
            fields = {
                level = true,
                itemLevel = true,
                activityScore = true,
                gold = true,
                realm = true,
                professions = false,
                vault = true,
                specializationArt = true,
            },
        },
        warbandOverview = {
            layoutMode = "compact",
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            },
        },
        sidebarSortMode = nil,
        selectedRareZoneKey = "eversong",
        sidebarOrder = {},
        scale = 1,
        opacity = 1,
        window = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    },
    features = {
        states = {},
        statFocus = {
            characters = {},
        },
        shoppingList = {
            version = 1,
            entries = {},
            order = {},
            nextID = 1,
            selectedView = "projects",
            filter = "missing",
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            },
            miniButton = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 460,
                y = 0,
                scale = 1,
            },
            minimapButton = {
                angle = 315,
            },
        },
        specSwitcher = {
            position = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -220,
            },
            scale = 1,
        },
        travelBar = {
            position = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -272,
            },
            scale = 1,
            hidden = {},
            order = {},
        },
        preyBar = {
            position = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -160,
            },
            scale = 1,
        },
        gatheringNodes = {
            version = 1,
            data = {
                version = 1,
                maps = {},
            },
            hiddenByCharacter = {},
            displayEnabled = true,
            button = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 410,
                y = -92,
                scale = 1,
            },
            minimapButton = {
                angle = 135,
            },
        },
        quietLoot = {
            lootWindow = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 40,
            },
            toast = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -185,
            },
        },
        windowMover = {
            version = 2,
            positions = {},
            scales = {},
        },
        merchantFilters = {
            version = 1,
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            },
            globalFilters = {},
            merchantProfiles = {},
        },
        actionBars = {
            version = 1,
            slotOverrides = {},
            actionOverrides = {},
            groupColors = {},
        },
    },
    modules = {},
    characters = {},
    pveWeekly = {
        omniumFolioComplete = false,
    },
    arsenal = {
        version = 1,
        warband = {
            containers = {},
            updatedAt = 0,
        },
    },
    mailbox = {
        version = 2,
        snapshots = {},
        recentRecipients = {},
        send = {
            favorites = {},
            rules = {},
            templates = {},
            nextRuleID = 1,
            nextTemplateID = 1,
        },
    },
    hiddenCharacters = {},
    mainCharacterKey = nil,
    raidLootTracker = {},
    journalLootCatalog = {},
    focus = {
        global = {
            items = {},
            order = {},
        },
        characters = {},
        meta = {},
        tracker = {
            shown = false,
            locked = false,
            scalePercent = 100,
            opacityPercent = 90,
            background = true,
            styleKey = "frame",
            fontKey = "normal",
            point = nil,
        },
    },
    debug = {
        enabled = false,
    },
}

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, entry in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(entry, seen)
    end
    return copy
end

local function applyDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if target[key] == nil then
            target[key] = deepCopy(defaultValue)
        elseif type(defaultValue) == "table" and type(target[key]) == "table" then
            applyDefaults(target[key], defaultValue)
        elseif type(defaultValue) == "table" and type(target[key]) ~= "table" then
            target[key] = deepCopy(defaultValue)
        end
    end
end

local function normalizeShortText(value, maximumLength)
    value = type(value) == "string" and value or ""
    value = value:gsub("[%c]", " "):gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:sub(1, math.max(1, tonumber(maximumLength) or 96))
end

local function compactUniqueStrings(values, maximumEntries)
    local result, seen = {}, {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        value = normalizeShortText(value, 96)
        local key = string.lower(value)
        if value ~= "" and not seen[key] and #result < maximumEntries then
            seen[key] = true
            result[#result + 1] = value
        end
    end
    return result
end

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function captureTime()
    return type(time) == "function" and math.max(0, tonumber(time()) or 0) or 0
end

local function isStorageKey(value)
    return type(value) == "string" and value ~= "" and #value <= 128
end

local function validatePersistedValue(value, active, state, depth)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" then
        return true
    end
    if valueType == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge, "non-finite-number"
    end
    if valueType ~= "table" then
        return false, "unsupported-" .. valueType
    end
    if depth > MAX_PERSISTED_TABLE_DEPTH then
        return false, "maximum-depth"
    end
    if active[value] then
        return false, "table-cycle"
    end

    active[value] = true
    for key, entry in pairs(value) do
        state.nodes = state.nodes + 1
        if state.nodes > MAX_PERSISTED_TABLE_NODES then
            active[value] = nil
            return false, "maximum-size"
        end
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            active[value] = nil
            return false, "unsupported-key-" .. keyType
        end
        local keyValid, keyReason = validatePersistedValue(key, active, state, depth + 1)
        if not keyValid then
            active[value] = nil
            return false, keyReason
        end
        local entryValid, entryReason = validatePersistedValue(entry, active, state, depth + 1)
        if not entryValid then
            active[value] = nil
            return false, entryReason
        end
    end
    active[value] = nil
    return true
end

local function ensureRecoveryRoot(db)
    db.recovery = type(db.recovery) == "table" and db.recovery or {}
    db.recovery.version = RECOVERY_VERSION
    return db.recovery
end

local function backupSnapshot(db, scope, ownerKey, snapshotKey, snapshot, reason)
    local recovery = ensureRecoveryRoot(db)
    recovery.snapshots = type(recovery.snapshots) == "table" and recovery.snapshots or {}
    recovery.snapshots[scope] = type(recovery.snapshots[scope]) == "table"
        and recovery.snapshots[scope] or {}
    local owners = recovery.snapshots[scope]
    owners[ownerKey] = type(owners[ownerKey]) == "table" and owners[ownerKey] or {}
    owners[ownerKey][snapshotKey] = {
        capturedAt = captureTime(),
        reason = normalizeShortText(reason or "replace", 64),
        snapshot = deepCopy(snapshot),
    }
end

Database.migrations[1] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.modules = type(db.modules) == "table" and db.modules or {}
    db.characters = type(db.characters) == "table" and db.characters or {}
    db.debug = type(db.debug) == "table" and db.debug or {}
end

Database.migrations[2] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.ui.sidebarOrder = type(db.ui.sidebarOrder) == "table" and db.ui.sidebarOrder or {}
    db.hiddenCharacters = type(db.hiddenCharacters) == "table" and db.hiddenCharacters or {}
end

Database.migrations[3] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    if type(db.ui.selectedSubTabs.pve) ~= "string" or db.ui.selectedSubTabs.pve == "" then
        db.ui.selectedSubTabs.pve = "weekly"
    end
end

Database.migrations[4] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    if type(db.ui.selectedRareZoneKey) ~= "string" or db.ui.selectedRareZoneKey == "" then
        db.ui.selectedRareZoneKey = "eversong"
    end
end

Database.migrations[5] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.ui.raidJournal = type(db.ui.raidJournal) == "table" and db.ui.raidJournal or {}
    db.raidLootTracker = type(db.raidLootTracker) == "table" and db.raidLootTracker or {}
end

Database.migrations[6] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.ui.dungeonJournal = type(db.ui.dungeonJournal) == "table" and db.ui.dungeonJournal or {}
end

Database.migrations[7] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.ui.mythicPlus = type(db.ui.mythicPlus) == "table" and db.ui.mythicPlus or {}
end

Database.migrations[8] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
end

Database.migrations[9] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.focus = type(db.focus) == "table" and db.focus or {}
end

Database.migrations[10] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.compendium = type(db.ui.compendium) == "table" and db.ui.compendium or {}
end

Database.migrations[11] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.hiddenUtilityResources = type(db.ui.hiddenUtilityResources) == "table"
        and db.ui.hiddenUtilityResources or {}
end

Database.migrations[12] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.warband = type(db.ui.warband) == "table" and db.ui.warband or {}
    db.ui.warband.fields = type(db.ui.warband.fields) == "table" and db.ui.warband.fields or {}
end

Database.migrations[13] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.selectedSubTabs = type(db.ui.selectedSubTabs) == "table" and db.ui.selectedSubTabs or {}
    db.arsenal = type(db.arsenal) == "table" and db.arsenal or {}
    db.arsenal.warband = type(db.arsenal.warband) == "table" and db.arsenal.warband or {}
end

Database.migrations[14] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.wishlist = type(db.ui.wishlist) == "table" and db.ui.wishlist or {}
    db.journalLootCatalog = type(db.journalLootCatalog) == "table" and db.journalLootCatalog or {}
end

Database.migrations[15] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.options = type(db.ui.options) == "table" and db.ui.options or {}
    db.ui.options.hiddenMainTabs = type(db.ui.options.hiddenMainTabs) == "table"
        and db.ui.options.hiddenMainTabs or {}
end

Database.migrations[16] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.features = type(db.ui.features) == "table" and db.ui.features or {}
    db.features = type(db.features) == "table" and db.features or {}
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
end

Database.migrations[17] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.statFocus = type(db.features.statFocus) == "table" and db.features.statFocus or {}
    db.features.statFocus.characters = type(db.features.statFocus.characters) == "table"
        and db.features.statFocus.characters or {}
end

Database.migrations[18] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.stat_focus) == "table" and states.stat_focus or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if settings and settings.tooltip_style == "compact" then
        settings.tooltip_style = "block"
    end
end

Database.migrations[19] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.stat_focus) == "table" and states.stat_focus or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if not settings or settings.tooltip_style == nil then
        return
    end

    local style = settings.tooltip_style
    if type(settings.tooltip_text) ~= "boolean" then
        settings.tooltip_text = style == "block" or style == "full" or style == "compact"
    end
    if type(settings.stat_colors) ~= "boolean" then
        settings.stat_colors = style == "lines" or style == "full"
    end
    if type(settings.stat_dots) ~= "boolean" then
        settings.stat_dots = style == "dots"
    end
    if settings.tooltip_text ~= true and settings.stat_colors ~= true and settings.stat_dots ~= true then
        settings.tooltip_text = true
    end
    settings.tooltip_style = nil
end

Database.migrations[20] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.shoppingList = type(db.features.shoppingList) == "table"
        and db.features.shoppingList or {}
end

Database.migrations[21] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.specSwitcher = type(db.features.specSwitcher) == "table"
        and db.features.specSwitcher or {}
end

Database.migrations[22] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
    db.features.specSwitcher = type(db.features.specSwitcher) == "table"
        and db.features.specSwitcher or {}
    local state = db.features.states.spec_switcher
    local settings = type(state) == "table" and type(state.settings) == "table"
        and state.settings or nil
    local oldSize = settings and settings.icon_size or nil
    if oldSize and tonumber(db.features.specSwitcher.scale or 1) == 1 then
        db.features.specSwitcher.scale = oldSize == "small" and 0.85
            or oldSize == "large" and 1.15
            or 1
    end
    if settings then settings.icon_size = nil end
end

Database.migrations[23] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.travelBar = type(db.features.travelBar) == "table"
        and db.features.travelBar or {}
end

Database.migrations[24] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.preyBar = type(db.features.preyBar) == "table"
        and db.features.preyBar or {}
end

Database.migrations[25] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.gatheringNodes = type(db.features.gatheringNodes) == "table"
        and db.features.gatheringNodes or {}
    local gatheringNodes = db.features.gatheringNodes
    if type(gatheringNodes.data) ~= "table" and type(gatheringNodes.maps) == "table" then
        gatheringNodes.data = {
            version = tonumber(gatheringNodes.version) or 1,
            maps = gatheringNodes.maps,
        }
        gatheringNodes.maps = nil
    end
end

Database.migrations[26] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.quietLoot = type(db.features.quietLoot) == "table"
        and db.features.quietLoot or {}
end

Database.migrations[27] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.quiet_loot) == "table" and states.quiet_loot or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if not settings then return end

    local oldLootMode = settings.loot_mode
    if settings.loot_window_mode == nil then
        settings.loot_window_mode = oldLootMode == "compact" and "compact" or "blizzard"
    end
    if settings.loot_alert_mode == nil then
        settings.loot_alert_mode = oldLootMode == "compact" and "compact"
            or oldLootMode == "hidden" and "hidden"
            or "blizzard"
    end
    if settings.boss_alert_mode == nil then
        settings.boss_alert_mode = settings.boss_mode == "compact" and "compact"
            or settings.boss_mode == "hidden" and "hidden"
            or settings.boss_mode == "blizzard" and "blizzard"
            or "compact"
    end
    settings.loot_mode = nil
    settings.boss_mode = nil
end

Database.migrations[28] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.windowMover = type(db.features.windowMover) == "table"
        and db.features.windowMover or {}
end

Database.migrations[29] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.merchantFilters = type(db.features.merchantFilters) == "table"
        and db.features.merchantFilters or {}
end

Database.migrations[30] = function(db)
    db.features = type(db.features) == "table" and db.features or {}
    db.features.actionBars = type(db.features.actionBars) == "table"
        and db.features.actionBars or {}
end

Database.migrations[31] = function(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.minimap = type(db.ui.minimap) == "table" and db.ui.minimap or {}
end

Database.migrations[32] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.shopping_list) == "table" and states.shopping_list or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if not settings or settings.mini_button == nil then return end
    if settings.launcher_mode == nil then
        settings.launcher_mode = settings.mini_button == false and "off" or "floating"
    end
    settings.mini_button = nil
end

Database.migrations[33] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.gathering_nodes) == "table" and states.gathering_nodes or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if not settings or settings.mini_button == nil then return end
    if settings.launcher_mode == nil then
        settings.launcher_mode = settings.mini_button == false and "off" or "floating"
    end
    settings.mini_button = nil
end

Database.migrations[34] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local mover = features and type(features.windowMover) == "table"
        and features.windowMover or nil
    if not mover then return end

    local protectedWindows = {
        "CinematicFrame",
        "GameMenuFrame",
        "MovieFrame",
    }
    for _, frameKey in ipairs(protectedWindows) do
        if type(mover.positions) == "table" then mover.positions[frameKey] = nil end
        if type(mover.scales) == "table" then mover.scales[frameKey] = nil end
    end
end

Database.migrations[35] = function(db)
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.snapshots = type(db.mailbox.snapshots) == "table"
        and db.mailbox.snapshots or {}
    db.mailbox.recentRecipients = type(db.mailbox.recentRecipients) == "table"
        and db.mailbox.recentRecipients or {}

    db.features = type(db.features) == "table" and db.features or {}
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
    local state = db.features.states.mailbox
    if type(state) ~= "table" then
        state = {
            enabled = true,
            settings = {},
        }
        db.features.states.mailbox = state
    elseif state.enabled == nil then
        state.enabled = true
    end
    state.settings = type(state.settings) == "table" and state.settings or {}
end

Database.migrations[36] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.mailbox) == "table" and states.mailbox or nil
    if state then
        state.enabled = false
        state.settings = type(state.settings) == "table" and state.settings or {}
        state.settings.show_panel = nil
    end
end

Database.migrations[37] = function(db)
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.recentRecipients = type(db.mailbox.recentRecipients) == "table"
        and db.mailbox.recentRecipients or {}
    db.mailbox.send = type(db.mailbox.send) == "table" and db.mailbox.send or {}
    local send = db.mailbox.send
    send.favorites = type(send.favorites) == "table" and send.favorites or {}
    send.rules = type(send.rules) == "table" and send.rules or {}
    send.templates = type(send.templates) == "table" and send.templates or {}
    send.nextRuleID = math.max(1, math.floor(tonumber(send.nextRuleID) or 1))
    send.nextTemplateID = math.max(1, math.floor(tonumber(send.nextTemplateID) or 1))
end

Database.migrations[38] = function(db)
    db.characters = type(db.characters) == "table" and db.characters or {}
    for _, record in pairs(db.characters) do
        if type(record) == "table" then
            record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
            local snapshots = record.snapshots
            snapshots.mythicPlusSeasons = type(snapshots.mythicPlusSeasons) == "table"
                and snapshots.mythicPlusSeasons or {}
            local legacy = snapshots.mythicPlus
            if type(legacy) == "table" then
                local seasonKey = type(legacy.seasonKey) == "string" and legacy.seasonKey or "season1"
                snapshots.mythicPlusSeasons[seasonKey] = snapshots.mythicPlusSeasons[seasonKey] or legacy
            end
        end
    end
end

Database.migrations[39] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.quiet_loot) == "table" and states.quiet_loot or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    local style = settings and settings.visual_style or nil
    if style == nil then return end

    if style == "clean" then
        settings.visual_style = "clean"
    elseif style == "round" or style == "rounded" then
        settings.visual_style = "round"
    else
        settings.visual_style = "standard"
    end
end

Database.migrations[40] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local statFocus = features and type(features.statFocus) == "table" and features.statFocus or nil
    local characters = statFocus and type(statFocus.characters) == "table" and statFocus.characters or nil
    for _, specifications in pairs(characters or {}) do
        if type(specifications) == "table" then
            for _, record in pairs(specifications) do
                normalizeStatFocusSpecRecord(record)
            end
        end
    end
end

Database.migrations[41] = function(db)
    local features = type(db.features) == "table" and db.features or nil
    local states = features and type(features.states) == "table" and features.states or nil
    local state = states and type(states.stat_focus) == "table" and states.stat_focus or nil
    local settings = state and type(state.settings) == "table" and state.settings or nil
    if not settings then
        return
    end
    settings.tooltip_text_style = settings.tooltip_text_style == "clean" and "clean" or "full"
    settings.tooltip_text = nil
end

function Database:RunMigrations(db)
    local savedVersion = math.max(0, math.floor(tonumber(db.schemaVersion) or 0))
    if savedVersion > self.currentSchemaVersion then
        Addon.Logger:Write(
            "WARN",
            "database",
            "Saved schema %d is newer than supported schema %d.",
            savedVersion,
            self.currentSchemaVersion
        )
        return false, "newer-schema"
    end

    for version = savedVersion + 1, self.currentSchemaVersion do
        local migration = self.migrations[version]
        if type(migration) == "function" then
            local ok = Addon:SafeCall("database.migration." .. version, migration, db)
            if not ok then
                error("Vaultloom database migration " .. version .. " failed")
            end
        end
        db.schemaVersion = version
    end
    return true
end

function Database:Normalize(db)
    applyDefaults(db, DEFAULTS)
    db.databaseIdentity = DATABASE_IDENTITY
    db.ui.scale = clamp(db.ui.scale, 0.70, 1.25, 1)
    db.ui.opacity = clamp(db.ui.opacity, 0.65, 1, 1)
    db.ui.chatMessagesEnabled = db.ui.chatMessagesEnabled ~= false
    db.ui.welcomeSeenRelease = type(db.ui.welcomeSeenRelease) == "string"
        and db.ui.welcomeSeenRelease or ""
    local languageGlobal = Addon.Identity.languageSavedVariable
    local bootLanguage = languageGlobal and _G[languageGlobal] or nil
    if bootLanguage == "auto"
        or (Addon.LocaleRegistry and Addon.LocaleRegistry:IsSupported(bootLanguage))
    then
        db.ui.language = bootLanguage
    elseif db.ui.language ~= "auto"
        and (not Addon.LocaleRegistry or not Addon.LocaleRegistry:IsSupported(db.ui.language))
    then
        db.ui.language = "auto"
    end
    if languageGlobal then
        _G[languageGlobal] = db.ui.language
    end
    db.ui.options = type(db.ui.options) == "table" and db.ui.options or {}
    local optionPages = {
        general = true,
        language = true,
        navigation = true,
        diagnostics = true,
        patchnotes = true,
    }
    if not optionPages[db.ui.options.selectedPage] then
        db.ui.options.selectedPage = "general"
    end
    db.ui.options.hiddenMainTabs = type(db.ui.options.hiddenMainTabs) == "table"
        and db.ui.options.hiddenMainTabs or {}
    for screenID, hidden in pairs(db.ui.options.hiddenMainTabs) do
        if type(screenID) ~= "string" or screenID == "" or hidden ~= true then
            db.ui.options.hiddenMainTabs[screenID] = nil
        end
    end
    db.ui.options.lastReadRelease = type(db.ui.options.lastReadRelease) == "string"
        and db.ui.options.lastReadRelease or ""
    db.performanceDiagnostics = type(db.performanceDiagnostics) == "table"
        and db.performanceDiagnostics or {}
    db.performanceDiagnostics.armOnReload = db.performanceDiagnostics.armOnReload == true
    db.ui.minimap = type(db.ui.minimap) == "table" and db.ui.minimap or {}
    db.ui.minimap.hide = db.ui.minimap.hide == true
    db.ui.minimap.minimapPos = tonumber(db.ui.minimap.minimapPos) or 225
    while db.ui.minimap.minimapPos < 0 do
        db.ui.minimap.minimapPos = db.ui.minimap.minimapPos + 360
    end
    db.ui.minimap.minimapPos = db.ui.minimap.minimapPos % 360
    db.ui.features = type(db.ui.features) == "table" and db.ui.features or {}
    db.ui.features.selectedCategory = type(db.ui.features.selectedCategory) == "string"
        and db.ui.features.selectedCategory ~= ""
        and db.ui.features.selectedCategory or "all"
    db.ui.features.activeOnly = db.ui.features.activeOnly == true
    db.ui.features.seenNewFeatureReleases = type(db.ui.features.seenNewFeatureReleases) == "table"
        and db.ui.features.seenNewFeatureReleases or {}
    for featureID, version in pairs(db.ui.features.seenNewFeatureReleases) do
        if type(featureID) ~= "string" or featureID == "" or type(version) ~= "string" then
            db.ui.features.seenNewFeatureReleases[featureID] = nil
        end
    end
    db.ui.newIndicators = type(db.ui.newIndicators) == "table" and db.ui.newIndicators or {}
    db.ui.newIndicators.seenReleases = type(db.ui.newIndicators.seenReleases) == "table"
        and db.ui.newIndicators.seenReleases or {}
    for indicatorID, version in pairs(db.ui.newIndicators.seenReleases) do
        if type(indicatorID) ~= "string" or indicatorID == "" or type(version) ~= "string" then
            db.ui.newIndicators.seenReleases[indicatorID] = nil
        end
    end
    db.features = type(db.features) == "table" and db.features or {}
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
    db.features.statFocus = type(db.features.statFocus) == "table" and db.features.statFocus or {}
    db.features.statFocus.characters = type(db.features.statFocus.characters) == "table"
        and db.features.statFocus.characters or {}
    db.features.shoppingList = type(db.features.shoppingList) == "table"
        and db.features.shoppingList or {}
    local shoppingList = db.features.shoppingList
    shoppingList.version = 1
    shoppingList.entries = type(shoppingList.entries) == "table" and shoppingList.entries or {}
    shoppingList.order = type(shoppingList.order) == "table" and shoppingList.order or {}
    shoppingList.nextID = math.max(1, math.floor(tonumber(shoppingList.nextID) or 1))
    shoppingList.selectedView = shoppingList.selectedView == "shopping" and "shopping" or "projects"
    local shoppingFilters = { all = true, missing = true, complete = true }
    shoppingList.filter = shoppingFilters[shoppingList.filter] and shoppingList.filter or "missing"
    shoppingList.window = type(shoppingList.window) == "table" and shoppingList.window or {}
    shoppingList.window.point = type(shoppingList.window.point) == "string"
        and shoppingList.window.point or "CENTER"
    shoppingList.window.relativePoint = type(shoppingList.window.relativePoint) == "string"
        and shoppingList.window.relativePoint or "CENTER"
    shoppingList.window.x = tonumber(shoppingList.window.x) or 0
    shoppingList.window.y = tonumber(shoppingList.window.y) or 0
    shoppingList.miniButton = type(shoppingList.miniButton) == "table" and shoppingList.miniButton or {}
    shoppingList.miniButton.point = type(shoppingList.miniButton.point) == "string"
        and shoppingList.miniButton.point or "CENTER"
    shoppingList.miniButton.relativePoint = type(shoppingList.miniButton.relativePoint) == "string"
        and shoppingList.miniButton.relativePoint or "CENTER"
    shoppingList.miniButton.x = tonumber(shoppingList.miniButton.x) or 460
    shoppingList.miniButton.y = tonumber(shoppingList.miniButton.y) or 0
    shoppingList.miniButton.scale = clamp(shoppingList.miniButton.scale, 0.65, 1.75, 1)
    shoppingList.minimapButton = type(shoppingList.minimapButton) == "table"
        and shoppingList.minimapButton or {}
    shoppingList.minimapButton.angle = tonumber(shoppingList.minimapButton.angle) or 315
    while shoppingList.minimapButton.angle < 0 do
        shoppingList.minimapButton.angle = shoppingList.minimapButton.angle + 360
    end
    shoppingList.minimapButton.angle = shoppingList.minimapButton.angle % 360
    db.features.specSwitcher = type(db.features.specSwitcher) == "table"
        and db.features.specSwitcher or {}
    local specSwitcher = db.features.specSwitcher
    specSwitcher.position = type(specSwitcher.position) == "table" and specSwitcher.position or {}
    specSwitcher.position.point = type(specSwitcher.position.point) == "string"
        and specSwitcher.position.point or "TOP"
    specSwitcher.position.relativePoint = type(specSwitcher.position.relativePoint) == "string"
        and specSwitcher.position.relativePoint or "TOP"
    specSwitcher.position.x = tonumber(specSwitcher.position.x) or 0
    specSwitcher.position.y = tonumber(specSwitcher.position.y) or -220
    specSwitcher.scale = clamp(specSwitcher.scale, 0.70, 1.45, 1)
    db.features.travelBar = type(db.features.travelBar) == "table"
        and db.features.travelBar or {}
    local travelBar = db.features.travelBar
    travelBar.position = type(travelBar.position) == "table" and travelBar.position or {}
    travelBar.position.point = type(travelBar.position.point) == "string"
        and travelBar.position.point or "TOP"
    travelBar.position.relativePoint = type(travelBar.position.relativePoint) == "string"
        and travelBar.position.relativePoint or "TOP"
    travelBar.position.x = tonumber(travelBar.position.x) or 0
    travelBar.position.y = tonumber(travelBar.position.y) or -272
    travelBar.scale = clamp(travelBar.scale, 0.70, 1.45, 1)
    travelBar.hidden = type(travelBar.hidden) == "table" and travelBar.hidden or {}
    travelBar.order = type(travelBar.order) == "table" and travelBar.order or {}
    db.features.preyBar = type(db.features.preyBar) == "table"
        and db.features.preyBar or {}
    local preyBar = db.features.preyBar
    preyBar.position = type(preyBar.position) == "table" and preyBar.position or {}
    preyBar.position.point = type(preyBar.position.point) == "string"
        and preyBar.position.point or "TOP"
    preyBar.position.relativePoint = type(preyBar.position.relativePoint) == "string"
        and preyBar.position.relativePoint or "TOP"
    preyBar.position.x = tonumber(preyBar.position.x) or 0
    preyBar.position.y = tonumber(preyBar.position.y) or -160
    preyBar.scale = clamp(preyBar.scale, 0.70, 1.45, 1)
    db.features.gatheringNodes = type(db.features.gatheringNodes) == "table"
        and db.features.gatheringNodes or {}
    local gatheringNodes = db.features.gatheringNodes
    gatheringNodes.version = 1
    gatheringNodes.data = type(gatheringNodes.data) == "table"
        and gatheringNodes.data or { version = 1, maps = {} }
    gatheringNodes.data.version = 1
    gatheringNodes.data.maps = type(gatheringNodes.data.maps) == "table"
        and gatheringNodes.data.maps or {}
    gatheringNodes.hiddenByCharacter = type(gatheringNodes.hiddenByCharacter) == "table"
        and gatheringNodes.hiddenByCharacter or {}
    gatheringNodes.displayEnabled = gatheringNodes.displayEnabled ~= false
    gatheringNodes.button = type(gatheringNodes.button) == "table"
        and gatheringNodes.button or {}
    gatheringNodes.button.point = type(gatheringNodes.button.point) == "string"
        and gatheringNodes.button.point or "CENTER"
    gatheringNodes.button.relativePoint = type(gatheringNodes.button.relativePoint) == "string"
        and gatheringNodes.button.relativePoint or "CENTER"
    gatheringNodes.button.x = tonumber(gatheringNodes.button.x) or 410
    gatheringNodes.button.y = tonumber(gatheringNodes.button.y) or -92
    gatheringNodes.button.scale = clamp(gatheringNodes.button.scale, 0.70, 1.40, 1)
    gatheringNodes.minimapButton = type(gatheringNodes.minimapButton) == "table"
        and gatheringNodes.minimapButton or {}
    gatheringNodes.minimapButton.angle = tonumber(gatheringNodes.minimapButton.angle) or 135
    while gatheringNodes.minimapButton.angle < 0 do
        gatheringNodes.minimapButton.angle = gatheringNodes.minimapButton.angle + 360
    end
    gatheringNodes.minimapButton.angle = gatheringNodes.minimapButton.angle % 360
    db.features.quietLoot = type(db.features.quietLoot) == "table"
        and db.features.quietLoot or {}
    local quietLoot = db.features.quietLoot
    quietLoot.lootWindow = type(quietLoot.lootWindow) == "table"
        and quietLoot.lootWindow or {}
    quietLoot.lootWindow.point = type(quietLoot.lootWindow.point) == "string"
        and quietLoot.lootWindow.point or "CENTER"
    quietLoot.lootWindow.relativePoint = type(quietLoot.lootWindow.relativePoint) == "string"
        and quietLoot.lootWindow.relativePoint or "CENTER"
    quietLoot.lootWindow.x = tonumber(quietLoot.lootWindow.x) or 0
    quietLoot.lootWindow.y = tonumber(quietLoot.lootWindow.y) or 40
    quietLoot.toast = type(quietLoot.toast) == "table" and quietLoot.toast or {}
    quietLoot.toast.point = type(quietLoot.toast.point) == "string"
        and quietLoot.toast.point or "TOP"
    quietLoot.toast.relativePoint = type(quietLoot.toast.relativePoint) == "string"
        and quietLoot.toast.relativePoint or "TOP"
    quietLoot.toast.x = tonumber(quietLoot.toast.x) or 0
    quietLoot.toast.y = tonumber(quietLoot.toast.y) or -185
    db.features.windowMover = type(db.features.windowMover) == "table"
        and db.features.windowMover or {}
    local windowMover = db.features.windowMover
    local windowMoverVersion = tonumber(windowMover.version) or 1
    windowMover.positions = type(windowMover.positions) == "table"
        and windowMover.positions or {}
    windowMover.scales = type(windowMover.scales) == "table"
        and windowMover.scales or {}
    for frameKey, position in pairs(windowMover.positions) do
        if type(frameKey) ~= "string" or frameKey == "" or type(position) ~= "table" then
            windowMover.positions[frameKey] = nil
        else
            local point = string.upper(tostring(position.point or ""))
            local relativePoint = string.upper(tostring(position.relativePoint or ""))
            local x = tonumber(position.x)
            local y = tonumber(position.y)
            local corruptedLegacyAnchor = windowMoverVersion < 2
                and point == "CENTER"
                and relativePoint == "BOTTOMLEFT"
            if corruptedLegacyAnchor
                or not VALID_FRAME_POINTS[point]
                or not VALID_FRAME_POINTS[relativePoint]
                or x == nil
                or y == nil
            then
                windowMover.positions[frameKey] = nil
            else
                position.point = point
                position.relativePoint = relativePoint
                position.x = x
                position.y = y
            end
        end
    end
    windowMover.version = 2
    for frameKey, scale in pairs(windowMover.scales) do
        if type(frameKey) ~= "string" or frameKey == "" or tonumber(scale) == nil then
            windowMover.scales[frameKey] = nil
        else
            windowMover.scales[frameKey] = clamp(scale, 0.30, 2.50, 1)
        end
    end
    db.features.merchantFilters = type(db.features.merchantFilters) == "table"
        and db.features.merchantFilters or {}
    local merchantFilters = db.features.merchantFilters
    merchantFilters.version = 1
    merchantFilters.window = type(merchantFilters.window) == "table"
        and merchantFilters.window or {}
    merchantFilters.window.point = type(merchantFilters.window.point) == "string"
        and merchantFilters.window.point or "CENTER"
    merchantFilters.window.relativePoint = type(merchantFilters.window.relativePoint) == "string"
        and merchantFilters.window.relativePoint or "CENTER"
    merchantFilters.window.x = tonumber(merchantFilters.window.x) or 0
    merchantFilters.window.y = tonumber(merchantFilters.window.y) or 0
    merchantFilters.globalFilters = type(merchantFilters.globalFilters) == "table"
        and merchantFilters.globalFilters or {}
    merchantFilters.merchantProfiles = type(merchantFilters.merchantProfiles) == "table"
        and merchantFilters.merchantProfiles or {}
    for merchantKey, filters in pairs(merchantFilters.merchantProfiles) do
        if type(merchantKey) ~= "string" or merchantKey == "" or type(filters) ~= "table" then
            merchantFilters.merchantProfiles[merchantKey] = nil
        end
    end
    db.features.actionBars = type(db.features.actionBars) == "table"
        and db.features.actionBars or {}
    local actionBars = db.features.actionBars
    actionBars.version = 1
    actionBars.slotOverrides = type(actionBars.slotOverrides) == "table"
        and actionBars.slotOverrides or {}
    actionBars.actionOverrides = type(actionBars.actionOverrides) == "table"
        and actionBars.actionOverrides or {}
    actionBars.groupColors = type(actionBars.groupColors) == "table"
        and actionBars.groupColors or {}
    for characterKey, specifications in pairs(db.features.statFocus.characters) do
        if type(characterKey) ~= "string" or characterKey == "" or type(specifications) ~= "table" then
            db.features.statFocus.characters[characterKey] = nil
        else
            for specKey, record in pairs(specifications) do
                if type(specKey) ~= "string" or specKey == "" or type(record) ~= "table" then
                    specifications[specKey] = nil
                else
                    normalizeStatFocusSpecRecord(record)
                end
            end
        end
    end
    for featureID, state in pairs(db.features.states) do
        if type(featureID) ~= "string" or featureID == "" or type(state) ~= "table" then
            db.features.states[featureID] = nil
        else
            state.enabled = state.enabled == true
            state.settings = type(state.settings) == "table" and state.settings or {}
        end
    end
    db.ui.window.point = type(db.ui.window.point) == "string" and db.ui.window.point or "CENTER"
    db.ui.window.relativePoint = type(db.ui.window.relativePoint) == "string" and db.ui.window.relativePoint or "CENTER"
    db.ui.window.x = tonumber(db.ui.window.x) or 0
    db.ui.window.y = tonumber(db.ui.window.y) or 0
    db.ui.warbandOverview = type(db.ui.warbandOverview) == "table"
        and db.ui.warbandOverview or {}
    db.ui.warbandOverview.layoutMode = db.ui.warbandOverview.layoutMode == "cards"
        and "cards" or "compact"
    db.ui.warbandOverview.window = type(db.ui.warbandOverview.window) == "table"
        and db.ui.warbandOverview.window or {}
    local overviewWindow = db.ui.warbandOverview.window
    overviewWindow.point = string.upper(tostring(overviewWindow.point or "CENTER"))
    if not VALID_FRAME_POINTS[overviewWindow.point] then
        overviewWindow.point = "CENTER"
    end
    overviewWindow.relativePoint = string.upper(tostring(
        overviewWindow.relativePoint or overviewWindow.point
    ))
    if not VALID_FRAME_POINTS[overviewWindow.relativePoint] then
        overviewWindow.relativePoint = overviewWindow.point
    end
    overviewWindow.x = tonumber(overviewWindow.x) or 0
    overviewWindow.y = tonumber(overviewWindow.y) or 0
    db.ui.mythicPlusOverview = type(db.ui.mythicPlusOverview) == "table"
        and db.ui.mythicPlusOverview or {}
    local mythicOverview = db.ui.mythicPlusOverview
    mythicOverview.viewMode = mythicOverview.viewMode == "matrix" and "matrix" or "overview"
    local mythicRealmFilter = mythicOverview.realmFilter
    if mythicRealmFilter ~= "all"
        and mythicRealmFilter ~= "current"
        and (type(mythicRealmFilter) ~= "string" or not mythicRealmFilter:find("^realm:.+"))
    then
        mythicOverview.realmFilter = "all"
    end
    local validKeyFilters = { all = true, with_key = true, without_key = true }
    if not validKeyFilters[mythicOverview.keyFilter] then mythicOverview.keyFilter = "all" end
    local validVaultFilters = { all = true, open = true, progress = true, complete = true, none = true }
    if not validVaultFilters[mythicOverview.vaultFilter] then mythicOverview.vaultFilter = "all" end
    local validDataFilters = { all = true, current = true, stale = true, missing = true }
    if not validDataFilters[mythicOverview.dataFilter] then mythicOverview.dataFilter = "all" end
    local validMythicSortModes = { attention = true, name = true, key = true, score = true, vault = true }
    if not validMythicSortModes[mythicOverview.sortMode] then mythicOverview.sortMode = "attention" end
    mythicOverview.window = type(mythicOverview.window) == "table" and mythicOverview.window or {}
    local mythicWindow = mythicOverview.window
    mythicWindow.point = string.upper(tostring(mythicWindow.point or "CENTER"))
    if not VALID_FRAME_POINTS[mythicWindow.point] then mythicWindow.point = "CENTER" end
    mythicWindow.relativePoint = string.upper(tostring(mythicWindow.relativePoint or mythicWindow.point))
    if not VALID_FRAME_POINTS[mythicWindow.relativePoint] then
        mythicWindow.relativePoint = mythicWindow.point
    end
    mythicWindow.x = tonumber(mythicWindow.x) or 0
    mythicWindow.y = tonumber(mythicWindow.y) or 0
    local sortMode = db.ui.sidebarSortMode
    if sortMode ~= nil
        and sortMode ~= "name"
        and sortMode ~= "level"
        and sortMode ~= "itemLevel"
        and sortMode ~= "realm"
        and sortMode ~= "activityScore"
        and sortMode ~= "vault"
    then
        db.ui.sidebarSortMode = nil
    end
    db.ui.warband = type(db.ui.warband) == "table" and db.ui.warband or {}
    db.ui.warband.cardStyle = db.ui.warband.cardStyle == "compact" and "compact" or "expanded"
    local realmFilter = db.ui.warband.realmFilter
    if realmFilter ~= "all"
        and realmFilter ~= "current"
        and (type(realmFilter) ~= "string" or not realmFilter:find("^realm:.+"))
    then
        db.ui.warband.realmFilter = "all"
    end
    db.ui.warband.fields = type(db.ui.warband.fields) == "table" and db.ui.warband.fields or {}
    for fieldKey, defaultValue in pairs(DEFAULTS.ui.warband.fields) do
        if type(db.ui.warband.fields[fieldKey]) ~= "boolean" then
            db.ui.warband.fields[fieldKey] = defaultValue
        end
    end
    db.ui.vault = type(db.ui.vault) == "table" and db.ui.vault or {}
    db.ui.vault.viewMode = nil
    local vaultSubTab = db.ui.selectedSubTabs.vault
    if vaultSubTab ~= "raids" and vaultSubTab ~= "dungeons" and vaultSubTab ~= "world" then
        db.ui.selectedSubTabs.vault = "raids"
    end
    local arsenalSubTabs = {
        equipment = true,
        bags = true,
        bank = true,
        warband = true,
        mail = true,
    }
    if not arsenalSubTabs[db.ui.selectedSubTabs.arsenal] then
        db.ui.selectedSubTabs.arsenal = "equipment"
    end
    local pveSubTabs = {
        weekly = true,
        coiled_isle = true,
        void_invasion = true,
        daily = true,
        events = true,
        delves = true,
        prey = true,
        rares = true,
        world = true,
    }
    if not pveSubTabs[db.ui.selectedSubTabs.pve] then
        db.ui.selectedSubTabs.pve = "weekly"
    end
    if db.ui.selectedSubTabs.systems ~= "professions" and db.ui.selectedSubTabs.systems ~= "cooldowns" then
        db.ui.selectedSubTabs.systems = "professions"
    end
    if db.ui.selectedSubTabs.raids ~= "midnight" then
        db.ui.selectedSubTabs.raids = "midnight"
    end
    local seasons = Addon.Data and Addon.Data.SEASONS or nil
    local activeDungeonSeasonKey = seasons and seasons:GetActiveKey("dungeons") or "season1"
    local activeMythicSeasonKey = seasons and seasons:GetActiveKey("mythicPlus") or "season1"
    if db.ui.selectedSubTabs.dungeons ~= "midnight"
        and db.ui.selectedSubTabs.dungeons ~= activeDungeonSeasonKey
    then
        db.ui.selectedSubTabs.dungeons = "midnight"
    end
    db.ui.mythicPlus = type(db.ui.mythicPlus) == "table" and db.ui.mythicPlus or {}
    db.ui.selectedSubTabs.mythicplus = activeMythicSeasonKey
    db.ui.mythicPlus.activeSeasonKey = activeMythicSeasonKey
    local housingTabs = { endeavors = true, activity = true }
    if not housingTabs[db.ui.selectedSubTabs.housing] then
        db.ui.selectedSubTabs.housing = "endeavors"
    end
    db.ui.selectedSubTabs.focus = "questboard"
    db.ui.raidJournal = type(db.ui.raidJournal) == "table" and db.ui.raidJournal or {}
    db.ui.raidJournal.selectedRaidKey = type(db.ui.raidJournal.selectedRaidKey) == "string" and db.ui.raidJournal.selectedRaidKey or ""
    db.ui.raidJournal.selectedBossKey = type(db.ui.raidJournal.selectedBossKey) == "string" and db.ui.raidJournal.selectedBossKey or ""
    local raidDifficulties = { lfr = true, normal = true, heroic = true, mythic = true }
    if not raidDifficulties[db.ui.raidJournal.difficultyKey] then db.ui.raidJournal.difficultyKey = "normal" end
    db.ui.raidJournal.classFilterKey = db.ui.raidJournal.classFilterKey == "all" and "all" or "player"
    db.ui.dungeonJournal = type(db.ui.dungeonJournal) == "table" and db.ui.dungeonJournal or {}
    db.ui.dungeonJournal.selectedRaidKeys = type(db.ui.dungeonJournal.selectedRaidKeys) == "table" and db.ui.dungeonJournal.selectedRaidKeys or {}
    db.ui.dungeonJournal.selectedBossKeys = type(db.ui.dungeonJournal.selectedBossKeys) == "table" and db.ui.dungeonJournal.selectedBossKeys or {}
    local dungeonDifficulties = { normal = true, heroic = true, mythic = true }
    if not dungeonDifficulties[db.ui.dungeonJournal.difficultyKey] then db.ui.dungeonJournal.difficultyKey = "normal" end
    db.ui.dungeonJournal.classFilterKey = db.ui.dungeonJournal.classFilterKey == "all" and "all" or "player"
    db.ui.mythicPlus.centerMode = nil
    db.ui.compendium = type(db.ui.compendium) == "table" and db.ui.compendium or {}
    local compendiumCategories = {
        all = true,
        mounts = true,
        pets = true,
        toys = true,
        decorations = true,
        recipes = true,
    }
    local compendiumStatuses = {
        all = true,
        missing = true,
        collected = true,
        unknown = true,
    }
    if not compendiumCategories[db.ui.compendium.category] then db.ui.compendium.category = "all" end
    if not compendiumStatuses[db.ui.compendium.status] then db.ui.compendium.status = "missing" end
    db.ui.compendium.source = type(db.ui.compendium.source) == "string"
        and db.ui.compendium.source ~= "" and db.ui.compendium.source or "all"
    db.ui.compendium.profession = type(db.ui.compendium.profession) == "string"
        and db.ui.compendium.profession ~= "" and db.ui.compendium.profession or "all"
    db.ui.compendium.search = type(db.ui.compendium.search) == "string" and db.ui.compendium.search or ""
    if db.ui.compendium.category ~= "recipes" then db.ui.compendium.profession = "all" end
    db.ui.wishlist = type(db.ui.wishlist) == "table" and db.ui.wishlist or {}
    local wishlistStatuses = { wish = true, obtained = true, all = true }
    local wishlistSources = { all = true, raids = true, dungeons = true }
    if not wishlistStatuses[db.ui.wishlist.status] then db.ui.wishlist.status = "wish" end
    if not wishlistSources[db.ui.wishlist.source] then db.ui.wishlist.source = "all" end
    db.ui.hiddenUtilityResources = type(db.ui.hiddenUtilityResources) == "table"
        and db.ui.hiddenUtilityResources or {}
    db.ui.utility = type(db.ui.utility) == "table" and db.ui.utility or {}
    db.ui.utility.showUpgradeSection = db.ui.utility.showUpgradeSection ~= false
    db.ui.utility.showPvpSection = db.ui.utility.showPvpSection ~= false
    db.ui.utility.fixedSectionVisibilityVersion = math.max(
        0,
        math.floor(tonumber(db.ui.utility.fixedSectionVisibilityVersion) or 0)
    )
    db.arsenal = type(db.arsenal) == "table" and db.arsenal or {}
    db.arsenal.version = 1
    db.arsenal.warband = type(db.arsenal.warband) == "table" and db.arsenal.warband or {}
    db.arsenal.warband.containers = type(db.arsenal.warband.containers) == "table"
        and db.arsenal.warband.containers or {}
    db.arsenal.warband.updatedAt = math.max(0, tonumber(db.arsenal.warband.updatedAt) or 0)
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.version = 2
    db.mailbox.snapshots = type(db.mailbox.snapshots) == "table"
        and db.mailbox.snapshots or {}
    db.mailbox.recentRecipients = type(db.mailbox.recentRecipients) == "table"
        and db.mailbox.recentRecipients or {}
    db.mailbox.send = type(db.mailbox.send) == "table" and db.mailbox.send or {}
    local mailboxSend = db.mailbox.send
    mailboxSend.favorites = type(mailboxSend.favorites) == "table"
        and mailboxSend.favorites or {}
    mailboxSend.rules = type(mailboxSend.rules) == "table" and mailboxSend.rules or {}
    mailboxSend.templates = type(mailboxSend.templates) == "table"
        and mailboxSend.templates or {}
    mailboxSend.nextRuleID = math.max(1, math.floor(tonumber(mailboxSend.nextRuleID) or 1))
    mailboxSend.nextTemplateID = math.max(
        1,
        math.floor(tonumber(mailboxSend.nextTemplateID) or 1)
    )
    db.mailbox.recentRecipients = compactUniqueStrings(db.mailbox.recentRecipients, 20)
    mailboxSend.favorites = compactUniqueStrings(mailboxSend.favorites, 30)
    local normalizedRules, usedRuleIDs, highestRuleID = {}, {}, 0
    for _, rule in ipairs(mailboxSend.rules) do
        if type(rule) == "table" and #normalizedRules < 50 then
            local matchType = rule.matchType
            local recipient = normalizeShortText(rule.recipient, 96)
            local itemID = math.floor(tonumber(rule.itemID) or 0)
            local classID = tonumber(rule.classID)
            local subClassID = tonumber(rule.subClassID)
            local validMatch = matchType == "item" and itemID > 0
                or matchType == "class" and classID ~= nil
                or matchType == "subclass" and classID ~= nil and subClassID ~= nil
            if recipient ~= "" and validMatch then
                local ruleID = math.max(1, math.floor(tonumber(rule.id) or 0))
                while usedRuleIDs[ruleID] do ruleID = ruleID + 1 end
                usedRuleIDs[ruleID] = true
                highestRuleID = math.max(highestRuleID, ruleID)
                normalizedRules[#normalizedRules + 1] = {
                    id = ruleID,
                    enabled = rule.enabled ~= false,
                    name = normalizeShortText(rule.name, 96),
                    recipient = recipient,
                    matchType = matchType,
                    itemID = itemID > 0 and itemID or nil,
                    classID = classID and math.floor(classID) or nil,
                    subClassID = subClassID and math.floor(subClassID) or nil,
                    keepCount = math.max(0, math.floor(tonumber(rule.keepCount) or 0)),
                    subject = normalizeShortText(rule.subject, 128),
                    body = type(rule.body) == "string" and rule.body:sub(1, 4000) or "",
                }
            end
        end
    end
    mailboxSend.rules = normalizedRules
    mailboxSend.nextRuleID = math.max(mailboxSend.nextRuleID, highestRuleID + 1)
    local normalizedTemplates, usedTemplateIDs, highestTemplateID = {}, {}, 0
    for _, template in ipairs(mailboxSend.templates) do
        if type(template) == "table" and #normalizedTemplates < 20 then
            local recipients = compactUniqueStrings(template.recipients, 100)
            if #recipients > 0 then
                local templateID = math.max(1, math.floor(tonumber(template.id) or 0))
                while usedTemplateIDs[templateID] do templateID = templateID + 1 end
                usedTemplateIDs[templateID] = true
                highestTemplateID = math.max(highestTemplateID, templateID)
                normalizedTemplates[#normalizedTemplates + 1] = {
                    id = templateID,
                    name = normalizeShortText(template.name, 64),
                    recipients = recipients,
                    subject = normalizeShortText(template.subject, 128),
                    body = type(template.body) == "string" and template.body:sub(1, 4000) or "",
                }
            end
        end
    end
    mailboxSend.templates = normalizedTemplates
    mailboxSend.nextTemplateID = math.max(mailboxSend.nextTemplateID, highestTemplateID + 1)
    for characterKey, snapshot in pairs(db.mailbox.snapshots) do
        if type(characterKey) ~= "string" or characterKey == "" or type(snapshot) ~= "table" then
            db.mailbox.snapshots[characterKey] = nil
        else
            snapshot.version = 1
            snapshot.characterKey = characterKey
            snapshot.updatedAt = math.max(0, tonumber(snapshot.updatedAt) or 0)
            snapshot.totalMessages = math.max(0, math.floor(tonumber(snapshot.totalMessages) or 0))
            snapshot.messages = type(snapshot.messages) == "table" and snapshot.messages or {}
            snapshot.summary = type(snapshot.summary) == "table" and snapshot.summary or {}
        end
    end
    for entryKey, hidden in pairs(db.ui.hiddenUtilityResources) do
        if type(entryKey) ~= "string" or hidden ~= true then
            db.ui.hiddenUtilityResources[entryKey] = nil
        end
    end
    db.raidLootTracker = type(db.raidLootTracker) == "table" and db.raidLootTracker or {}
    db.journalLootCatalog = type(db.journalLootCatalog) == "table" and db.journalLootCatalog or {}
    db.pveWeekly = type(db.pveWeekly) == "table" and db.pveWeekly or {}
    db.pveWeekly.omniumFolioComplete = db.pveWeekly.omniumFolioComplete == true
    for _, record in pairs(db.characters) do
        if type(record) == "table" then
            record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
            local snapshots = record.snapshots
            snapshots.mythicPlusSeasons = type(snapshots.mythicPlusSeasons) == "table"
                and snapshots.mythicPlusSeasons or {}
            local legacy = snapshots.mythicPlus
            local legacySeasonKey = type(legacy) == "table" and legacy.seasonKey or nil
            if type(legacySeasonKey) == "string" and snapshots.mythicPlusSeasons[legacySeasonKey] == nil then
                snapshots.mythicPlusSeasons[legacySeasonKey] = legacy
            end
        end
    end
    local rareZones = {
        eversong = true,
        zulaman = true,
        harandar = true,
        voidstorm = true,
        coiled_isle = true,
    }
    if not rareZones[db.ui.selectedRareZoneKey] then
        db.ui.selectedRareZoneKey = "eversong"
    end
    db.debug.enabled = db.debug.enabled == true
end

function Database:Validate(db)
    if type(db) ~= "table" then return false, "database-not-table" end
    if db.databaseIdentity ~= DATABASE_IDENTITY then return false, "database-identity" end
    if math.floor(tonumber(db.schemaVersion) or -1) ~= self.currentSchemaVersion then
        return false, "schema-version"
    end
    for _, key in ipairs({ "ui", "modules", "characters", "mailbox", "arsenal", "debug" }) do
        if type(db[key]) ~= "table" then return false, "missing-" .. key end
    end
    return true
end

function Database:Prepare(source)
    local candidate
    local quarantineReason
    if type(source) == "table" then
        local hasData = next(source) ~= nil
        local savedVersion = math.max(0, math.floor(tonumber(source.schemaVersion) or 0))
        if hasData and source.databaseIdentity ~= DATABASE_IDENTITY then
            quarantineReason = "incompatible-identity"
        elseif hasData and savedVersion > self.currentSchemaVersion then
            quarantineReason = "newer-schema"
        end

        if quarantineReason then
            candidate = {}
            local recovery = ensureRecoveryRoot(candidate)
            recovery.quarantinedDatabase = {
                capturedAt = captureTime(),
                reason = quarantineReason,
                sourceIdentity = type(source.databaseIdentity) == "string" and source.databaseIdentity or "",
                sourceSchemaVersion = savedVersion,
                database = deepCopy(source),
            }
        else
            candidate = deepCopy(source)
        end
    else
        candidate = {}
    end

    local migrated, migrationReason = self:RunMigrations(candidate)
    if migrated == false then
        error("Vaultloom database preparation failed: " .. tostring(migrationReason or "migration"))
    end
    self:Normalize(candidate)
    local valid, validationReason = self:Validate(candidate)
    if not valid then
        error("Vaultloom database validation failed: " .. tostring(validationReason or "unknown"))
    end
    return candidate
end

function Database:ValidateSnapshot(snapshot)
    if type(snapshot) ~= "table" then return false, "snapshot-not-table" end
    return validatePersistedValue(snapshot, {}, { nodes = 0 }, 1)
end

function Database:CommitCharacterSnapshot(characterKey, snapshotKey, snapshot, reason)
    if not isStorageKey(characterKey) or not isStorageKey(snapshotKey) then
        return false, "invalid-key"
    end
    local valid, validationReason = self:ValidateSnapshot(snapshot)
    if not valid then
        Addon.Logger:Write(
            "WARN",
            "database.snapshot",
            "Rejected snapshot %s/%s: %s.",
            characterKey,
            snapshotKey,
            tostring(validationReason or "invalid")
        )
        return false, validationReason
    end

    local db = self:Get()
    local record = type(db.characters) == "table" and db.characters[characterKey] or nil
    if type(record) ~= "table" then return false, "missing-character" end
    record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
    local previous = record.snapshots[snapshotKey]
    if previous ~= nil and previous ~= snapshot then
        backupSnapshot(db, "characters", characterKey, snapshotKey, previous, reason or "replace")
    end
    record.snapshots[snapshotKey] = snapshot
    return true
end

function Database:ClearCharacterSnapshot(characterKey, snapshotKey, reason)
    if not isStorageKey(characterKey) or not isStorageKey(snapshotKey) then
        return false, "invalid-key"
    end
    local db = self:Get()
    local record = type(db.characters) == "table" and db.characters[characterKey] or nil
    local snapshots = type(record) == "table" and type(record.snapshots) == "table"
        and record.snapshots or nil
    local previous = snapshots and snapshots[snapshotKey] or nil
    if previous == nil then return false, "missing-snapshot" end
    backupSnapshot(db, "characters", characterKey, snapshotKey, previous, reason or "clear")
    snapshots[snapshotKey] = nil
    return true
end

function Database:CommitMailboxSnapshot(characterKey, snapshot, reason)
    if not isStorageKey(characterKey) then return false, "invalid-key" end
    local valid, validationReason = self:ValidateSnapshot(snapshot)
    if not valid then return false, validationReason end
    local db = self:Get()
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.snapshots = type(db.mailbox.snapshots) == "table" and db.mailbox.snapshots or {}
    local previous = db.mailbox.snapshots[characterKey]
    if previous ~= nil and previous ~= snapshot then
        backupSnapshot(db, "mailbox", characterKey, "inbox", previous, reason or "replace")
    end
    db.mailbox.snapshots[characterKey] = snapshot
    return true
end

function Database:GetRecoverySnapshot(scope, ownerKey, snapshotKey)
    if not isStorageKey(scope) or not isStorageKey(ownerKey) or not isStorageKey(snapshotKey) then
        return nil
    end
    local db = self:Get()
    local recovery = type(db.recovery) == "table" and db.recovery or nil
    local snapshots = recovery and type(recovery.snapshots) == "table" and recovery.snapshots or nil
    local owners = snapshots and type(snapshots[scope]) == "table" and snapshots[scope] or nil
    local owner = owners and type(owners[ownerKey]) == "table" and owners[ownerKey] or nil
    local entry = owner and type(owner[snapshotKey]) == "table" and owner[snapshotKey] or nil
    return entry and type(entry.snapshot) == "table" and entry.snapshot or nil, entry
end

function Database:RestoreCharacterSnapshot(characterKey, snapshotKey)
    local snapshot = self:GetRecoverySnapshot("characters", characterKey, snapshotKey)
    if type(snapshot) ~= "table" then return false, "missing-recovery" end
    return self:CommitCharacterSnapshot(characterKey, snapshotKey, deepCopy(snapshot), "restore")
end

function Database:RestoreMailboxSnapshot(characterKey)
    local snapshot = self:GetRecoverySnapshot("mailbox", characterKey, "inbox")
    if type(snapshot) ~= "table" then return false, "missing-recovery" end
    return self:CommitMailboxSnapshot(characterKey, deepCopy(snapshot), "restore")
end

function Database:Ensure()
    local globalName = Addon.Identity.savedVariables
    local source = _G[globalName]
    local db = self:Prepare(source)
    _G[globalName] = db
    Addon.db = db
    Addon.Logger:SetDebugEnabled(db.debug.enabled)
    return db
end

function Database:Get()
    return Addon.db or self:Ensure()
end

function Database:GetUI()
    return self:Get().ui
end

function Database:ResetDisplaySettings()
    local ui = self:GetUI()
    ui.scale = DEFAULTS.ui.scale
    ui.opacity = DEFAULTS.ui.opacity
    return ui
end

function Database:ResetWindowPosition()
    local ui = self:GetUI()
    ui.window = deepCopy(DEFAULTS.ui.window)
    return ui
end

function Database:ResetWindowSettings()
    self:ResetDisplaySettings()
    return self:ResetWindowPosition()
end

function Database:GetModuleEnabled(moduleID, defaultEnabled)
    local modules = self:Get().modules
    local saved = modules[moduleID]
    if saved == nil then
        return defaultEnabled == true
    end
    return saved == true
end

function Database:SetModuleEnabled(moduleID, enabled)
    self:Get().modules[moduleID] = enabled == true
end
