local _, ns = ...

ns.Settings = ns.Settings or {}
local Settings = ns.Settings

local SCHEMA_VERSION = 13
local DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    global = {
        enabled = true,
    },
    -- Modules register their own defaults via RegisterModuleDefaults().
    -- This table is populated at runtime; it stays empty here so that
    -- MergeDefaults() works correctly even when no module is loaded.
    modules = {},
    theme = "Modern",
    accentPreset = "Gold",
    customAccentColor = { 0.95, 0.78, 0.30, 1 },
    customSurfaceColor = { 0.18, 0.13, 0.07, 0.95 },
    -- Optional override for the addon-wide font color. When customFontEnabled
    -- is true, headings and dim text follow these two tones instead of the
    -- accent-derived header tone. Primary = brighter (titles, column headers,
    -- toggle labels). Secondary = dimmer (sub-labels, axis ticks).
    customFontEnabled = false,
    customFontPrimary = { 1.00, 0.82, 0.30, 1 },
    customFontSecondary = { 0.70, 0.62, 0.42, 1 },
    onboarding = {
        seenModules = {},
        lastSeenVersion = "0.0.0",
        neverShowAgain = false,
    },
    debug = {
        verbose = false,
        developerMode = false,
    },
}

local function NormalizeTheme(value)
    if type(value) ~= "string" then
        return "Modern"
    end

    local normalized = string.lower(value)
    if normalized == "classic" then
        return "Classic"
    end

    return "Modern"
end

local function CloneTable(source)
    local result = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = CloneTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function Settings:Migrate(fromVersion)
    if fromVersion < 1 then
        fromVersion = 1
    end

    if fromVersion < 4 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local crosshair = self.db.modules.crosshair
        if type(crosshair) == "table" then
            if crosshair.combatOnly == nil then
                crosshair.combatOnly = true
            end
            if crosshair.alphaOutCombat == nil then
                crosshair.alphaOutCombat = 0
            end
        end

        local mouse = self.db.modules.mouse_tracker
        if type(mouse) == "table" then
            if mouse.combatOnly == nil then
                mouse.combatOnly = false
            end
            if mouse.smoothFollow == nil then
                mouse.smoothFollow = false
            end
            if mouse.updateRate == nil then
                mouse.updateRate = 0
            end
            if type(mouse.shape) ~= "string" or mouse.shape == "" then
                mouse.shape = "ring"
            end
        end
    end

    if fromVersion < 5 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local crosshair = self.db.modules.crosshair
        if type(crosshair) == "table" then
            local alphaOutCombat = tonumber(crosshair.alphaOutCombat) or 0
            if crosshair.combatOnly == true and alphaOutCombat <= 0 then
                -- Old "combat only" users had combatOnly=true + alphaOutCombat=0.
                -- Switch to always-visible with a sane out-of-combat alpha.
                crosshair.combatOnly = false
                crosshair.alphaOutCombat = 0.75
            end
            if crosshair.alphaOutCombat == nil then
                crosshair.alphaOutCombat = 0.75
            end
        end

        local darkness = self.db.modules.darkness_announcer
        if type(darkness) == "table" then
            local startChannel = type(darkness.channelStart) == "string" and string.upper(darkness.channelStart) or ""
            local endChannel = type(darkness.channelEnd) == "string" and string.upper(darkness.channelEnd) or ""
            if startChannel == "" or startChannel == "YELL" then
                darkness.channelStart = "AUTO"
            end
            if endChannel == "" or endChannel == "YELL" then
                darkness.channelEnd = "AUTO"
            end
        end
    end

    if fromVersion < 6 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local crosshair = self.db.modules.crosshair
        if type(crosshair) == "table" then
            -- Fix the leftover from the buggy v5 migration: combatOnly was set
            -- to false but alphaOutCombat was left at 0, making the crosshair
            -- invisible outside combat. Restore a visible default.
            local alphaOutCombat = tonumber(crosshair.alphaOutCombat)
            if alphaOutCombat ~= nil and alphaOutCombat <= 0 and crosshair.combatOnly ~= true then
                crosshair.alphaOutCombat = 0.75
            end
        end
    end

    if fromVersion < 7 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local darkness = self.db.modules.darkness_announcer
        if type(darkness) == "table" then
            -- New option: onlyInGroup -- default is false (existing users should not see a behaviour change).
            if darkness.onlyInGroup == nil then
                darkness.onlyInGroup = false
            end
        end
    end

    if fromVersion < 8 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local darkness = self.db.modules.darkness_announcer
        if type(darkness) == "table" then
            -- Migrate AUTO channels: use YELL for start (in instances), PARTY for end.
            -- Users who already customised a specific channel (not AUTO) keep their value.
            local startChannel = type(darkness.channelStart) == "string" and string.upper(darkness.channelStart) or ""
            local endChannel   = type(darkness.channelEnd) == "string" and string.upper(darkness.channelEnd) or ""
            if startChannel == "" or startChannel == "AUTO" or startChannel == "GUILD" then
                darkness.channelStart = "AUTO"
            end
            if endChannel == "" or endChannel == "AUTO" or endChannel == "GUILD" then
                darkness.channelEnd = "AUTO"
            end
        end
    end

    if fromVersion > 0 and fromVersion < 11 then
        -- Theme names swapped: old "Classic" (golden) -> new "Modern"; old "Modern" (dark) -> new "Classic"
        if self.db.theme == "Classic" then
            self.db.theme = "Modern"
        elseif self.db.theme == "Modern" then
            self.db.theme = "Classic"
        end
    end

    if fromVersion > 0 and fromVersion < 12 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local activeModules = { "crosshair", "mouse_tracker", "darkness_announcer", "quest_accept_hotkey" }
        for _, modID in ipairs(activeModules) do
            -- Only ensure table exists. DO NOT force enabled = true here,
            -- as it bypasses onboarding and forces everything on for existing users.
            if type(self.db.modules[modID]) ~= "table" then
                self.db.modules[modID] = {}
            end
        end

        -- Clean up dead data from removed modules to keep the DB lean
        local deprecated = { "qol", "nameplates", "nameplate_lite", "interrupt_tracker", "interrupt_tracker_fallback" }
        for _, modID in ipairs(deprecated) do
            self.db.modules[modID] = nil
        end
    end

    if fromVersion > 0 and fromVersion < 13 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        local accounting = self.db.modules.accounting_tracker
        if type(accounting) == "table" then
            local currentMax = tonumber(accounting.maxEntries)
            if currentMax == nil or currentMax == 5000 then
                accounting.maxEntries = 20000
            end
        end
    end

    if fromVersion < 10 then
        if type(self.db.modules) ~= "table" then
            self.db.modules = {}
        end

        self.db.theme = NormalizeTheme(self.db.theme)
        if type(self.db.onboarding) ~= "table" then
            self.db.onboarding = {}
        end
        if type(self.db.onboarding.seenModules) ~= "table" then
            self.db.onboarding.seenModules = {}
        end

        if (not self.isFreshDB) and self.db.onboarding.seededFromExisting ~= true then
            for moduleID, moduleData in pairs(self.db.modules) do
                -- Only seed if the user actually had some configuration or enabled status
                -- Not just because the module registered its defaults.
                if moduleData and (moduleData.enabled ~= nil or next(moduleData)) then
                    self.db.onboarding.seenModules[moduleID] = true
                end
            end
            -- For existing users, we also set the lastSeenVersion to the current one
            -- so they don't get "new" highlights for things they already have.
            if self.db.onboarding.lastSeenVersion == "0.0.0" then
                self.db.onboarding.lastSeenVersion = "0.4.0"
            end
            self.db.onboarding.seededFromExisting = true
        end
    end
end

function Settings:Initialize()
    -- Robust detection of a fresh installation:
    -- Either ThyraxUtilDB doesn't exist at all, or it's an empty table without a schema version.
    local hadExistingDB = type(ThyraxUtilDB) == "table" and ThyraxUtilDB.schemaVersion ~= nil
    if type(ThyraxUtilDB) ~= "table" then
        ThyraxUtilDB = {}
    end

    self.isFreshDB = not hadExistingDB
    self.db = ThyraxUtilDB

    if type(self.db.schemaVersion) ~= "number" then
        self.db.schemaVersion = 0
    end

    self:Migrate(self.db.schemaVersion)
    MergeDefaults(self.db, DEFAULTS)
    self.db.schemaVersion = SCHEMA_VERSION
end

-- Called by ModuleRegistry:Register() as soon as a module registers its
-- defaults. Works both before and after Initialize().
function Settings:RegisterModuleDefaults(moduleID, defaults)
    if type(moduleID) ~= "string" or moduleID == "" then
        return
    end
    if type(defaults) ~= "table" then
        return
    end

    -- Merge into the static DEFAULTS table (for new characters / reset).
    if not DEFAULTS.modules[moduleID] then
        DEFAULTS.modules[moduleID] = {}
    end
    MergeDefaults(DEFAULTS.modules[moduleID], defaults)

    -- Also merge live into the already-loaded DB in case Initialize() has
    -- already run (sub-module loading after core).
    if self.db and type(self.db.modules) == "table" then
        if not self.db.modules[moduleID] then
            self.db.modules[moduleID] = {}
        end
        MergeDefaults(self.db.modules[moduleID], defaults)
    end
end

function Settings:GetDB()
    return self.db
end

function Settings:GetDefaults()
    return DEFAULTS
end

function Settings:IsGlobalEnabled()
    return self.db and self.db.global and self.db.global.enabled ~= false
end

function Settings:SetGlobalEnabled(enabled)
    self.db.global.enabled = enabled and true or false
end

function Settings:GetModuleSettings(moduleID)
    if type(self.db.modules[moduleID]) ~= "table" then
        self.db.modules[moduleID] = {}
    end

    if DEFAULTS.modules[moduleID] then
        MergeDefaults(self.db.modules[moduleID], DEFAULTS.modules[moduleID])
    end

    return self.db.modules[moduleID]
end

function Settings:IsModuleEnabled(moduleID)
    local moduleSettings = self:GetModuleSettings(moduleID)
    return moduleSettings.enabled == true
end

function Settings:SetModuleEnabled(moduleID, enabled)
    local moduleSettings = self:GetModuleSettings(moduleID)
    moduleSettings.enabled = enabled and true or false
end

function Settings:SetModuleValue(moduleID, key, value)
    local moduleSettings = self:GetModuleSettings(moduleID)
    moduleSettings[key] = value
end

function Settings:GetModuleValue(moduleID, key)
    local moduleSettings = self:GetModuleSettings(moduleID)
    return moduleSettings[key]
end

function Settings:GetDebugSettings()
    return self.db.debug
end

function Settings:GetTheme()
    return NormalizeTheme(self.db and self.db.theme or DEFAULTS.theme)
end

function Settings:SetTheme(theme)
    self.db.theme = NormalizeTheme(theme)
end

function Settings:GetAccentPreset()
    if self.db and type(self.db.accentPreset) == "string" and self.db.accentPreset ~= "" then
        return self.db.accentPreset
    end
    return DEFAULTS.accentPreset or "Gold"
end

function Settings:SetAccentPreset(name)
    if type(name) ~= "string" or name == "" then
        name = DEFAULTS.accentPreset or "Gold"
    end
    self.db.accentPreset = name
end

-- Custom accent / surface colors are only honored when accentPreset == "Custom".
-- Stored as {r,g,b,a}; ns.Color.Normalize sanitises on read so corrupted
-- SavedVariables don't propagate bad values to the palette.
function Settings:GetCustomAccentColor()
    local fallback = DEFAULTS.customAccentColor or { 0.95, 0.78, 0.30, 1 }
    if ns.Color and ns.Color.Normalize then
        return ns.Color.Normalize(self.db and self.db.customAccentColor, fallback)
    end
    return self.db and self.db.customAccentColor or fallback
end

function Settings:SetCustomAccentColor(color)
    if ns.Color and ns.Color.Normalize then
        self.db.customAccentColor = ns.Color.Normalize(color, DEFAULTS.customAccentColor)
    else
        self.db.customAccentColor = color
    end
end

function Settings:GetCustomSurfaceColor()
    local fallback = DEFAULTS.customSurfaceColor or { 0.18, 0.13, 0.07, 0.95 }
    if ns.Color and ns.Color.Normalize then
        return ns.Color.Normalize(self.db and self.db.customSurfaceColor, fallback)
    end
    return self.db and self.db.customSurfaceColor or fallback
end

function Settings:SetCustomSurfaceColor(color)
    if ns.Color and ns.Color.Normalize then
        self.db.customSurfaceColor = ns.Color.Normalize(color, DEFAULTS.customSurfaceColor)
    else
        self.db.customSurfaceColor = color
    end
end

function Settings:IsCustomFontEnabled()
    return self.db and self.db.customFontEnabled == true
end

function Settings:SetCustomFontEnabled(enabled)
    self.db.customFontEnabled = enabled and true or false
end

function Settings:GetCustomFontPrimary()
    local fallback = DEFAULTS.customFontPrimary or { 1.00, 0.82, 0.30, 1 }
    if ns.Color and ns.Color.Normalize then
        return ns.Color.Normalize(self.db and self.db.customFontPrimary, fallback)
    end
    return self.db and self.db.customFontPrimary or fallback
end

function Settings:SetCustomFontPrimary(color)
    if ns.Color and ns.Color.Normalize then
        self.db.customFontPrimary = ns.Color.Normalize(color, DEFAULTS.customFontPrimary)
    else
        self.db.customFontPrimary = color
    end
end

function Settings:GetCustomFontSecondary()
    local fallback = DEFAULTS.customFontSecondary or { 0.70, 0.62, 0.42, 1 }
    if ns.Color and ns.Color.Normalize then
        return ns.Color.Normalize(self.db and self.db.customFontSecondary, fallback)
    end
    return self.db and self.db.customFontSecondary or fallback
end

function Settings:SetCustomFontSecondary(color)
    if ns.Color and ns.Color.Normalize then
        self.db.customFontSecondary = ns.Color.Normalize(color, DEFAULTS.customFontSecondary)
    else
        self.db.customFontSecondary = color
    end
end

function Settings:GetOnboardingData()
    if type(self.db.onboarding) ~= "table" then
        self.db.onboarding = {
            seenModules = {},
            lastSeenVersion = "0.0.0",
            neverShowAgain = false,
        }
    end
    if type(self.db.onboarding.seenModules) ~= "table" then
        self.db.onboarding.seenModules = {}
    end
    return self.db.onboarding
end

function Settings:SetNeverShowOnboarding(value)
    local data = self:GetOnboardingData()
    data.neverShowAgain = value and true or false
end

function Settings:IsNeverShowOnboarding()
    local data = self:GetOnboardingData()
    return data.neverShowAgain == true
end

function Settings:GetLastSeenVersion()
    local data = self:GetOnboardingData()
    return data.lastSeenVersion or "0.0.0"
end

function Settings:SetLastSeenVersion(version)
    local data = self:GetOnboardingData()
    data.lastSeenVersion = version
end

-- Migration from standalone addons
function Settings:MigrateFromLegacy(addonType)
    local map = {
        crosshair = "ThyraxUtil_CrosshairDB",
        mouse_tracker = "ThyraxUtil_MouseTrackerDB",
        darkness_announcer = "ThyraxUtil_DarknessAnnouncerDB",
        quest_accept_hotkey = "ThyraxUtil_QoLDB"
    }

    local dbName = map[addonType]
    if not dbName then return end

    local legacyDB = _G[dbName]
    if type(legacyDB) ~= "table" then return end

    -- Mark as seen so we don't bother them with onboarding for something they already use
    local onboarding = self:GetOnboardingData()
    onboarding.seenModules[addonType] = true

    if type(self.db.modules[addonType]) ~= "table" then
        self.db.modules[addonType] = {}
    end

    -- Copy all settings from legacy DB over
    for k, v in pairs(legacyDB) do
        if self.db.modules[addonType][k] == nil then
            if type(v) == "table" then
                self.db.modules[addonType][k] = CloneTable(v)
            else
                self.db.modules[addonType][k] = v
            end
        end
    end

    -- Try to preserve enabled state
    if self.db.modules[addonType].enabled == nil then
        -- Standalones were enabled by default if their DB existed, or if explicitly true
        self.db.modules[addonType].enabled = (legacyDB.enabled ~= false)
    end
end

function Settings:IsDeveloperModeEnabled()
    local debugSettings = self:GetDebugSettings()
    return debugSettings and debugSettings.developerMode == true
end

function Settings:SetDeveloperModeEnabled(enabled)
    local debugSettings = self:GetDebugSettings()
    debugSettings.developerMode = enabled and true or false
end
