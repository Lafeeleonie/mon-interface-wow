local _, Addon = ...

local FEATURE_ID = "stat_focus"

local MODE_PRESET = "preset"
local MODE_CUSTOM = "custom"

local DEFAULT_CONTENT_KEY = "solo"
local DEFAULT_BUILD_KEY = "standard"
local TOOLTIP_STYLE_CLEAN = "clean"
local TOOLTIP_STYLE_FULL = "full"
local CONTENT_KEYS = { "solo", "delve", "raid", "mythicplus" }
local VALID_CONTENT_KEYS = {
    solo = true,
    delve = true,
    raid = true,
    mythicplus = true,
}
local CONTENT_COMMANDS = {
    solo = "solo",
    delve = "delve",
    delves = "delve",
    raid = "raid",
    mythic = "mythicplus",
    mythics = "mythicplus",
    mythicplus = "mythicplus",
    mplus = "mythicplus",
    ["m+"] = "mythicplus",
}
local CONTENT_LABEL_KEYS = {
    solo = "FEATURE_VALUE_STAT_SOLO",
    delve = "FEATURE_VALUE_STAT_DELVE",
    raid = "FEATURE_VALUE_STAT_RAID",
    mythicplus = "FEATURE_VALUE_STAT_MYTHIC_PLUS",
}
local DEFAULT_STAT_ORDER = { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }
local DOT_TEXTURE_TOKEN = "stat_focus_dot_"
local DOT_TEXTURES = {
    [1] = "stat_focus_dot_orange",
    [2] = "stat_focus_dot_purple",
    [3] = "stat_focus_dot_blue",
    [4] = "stat_focus_dot_green",
}

local STAT_DEFINITIONS = {
    CRIT = {
        fallback = "Critical Strike",
        globals = { "ITEM_MOD_CRIT_RATING_SHORT", "STAT_CRITICAL_STRIKE", "ITEM_MOD_CRIT_RATING" },
    },
    HASTE = {
        fallback = "Haste",
        globals = { "ITEM_MOD_HASTE_RATING_SHORT", "STAT_HASTE", "ITEM_MOD_HASTE_RATING" },
    },
    MASTERY = {
        fallback = "Mastery",
        globals = { "ITEM_MOD_MASTERY_RATING_SHORT", "STAT_MASTERY", "ITEM_MOD_MASTERY_RATING" },
    },
    VERSATILITY = {
        fallback = "Versatility",
        globals = { "ITEM_MOD_VERSATILITY", "STAT_VERSATILITY", "ITEM_MOD_VERSATILITY_RATING" },
    },
}

local STAT_ALIASES = {
    crit = "CRIT",
    critical = "CRIT",
    ["critical strike"] = "CRIT",
    krit = "CRIT",
    kritisch = "CRIT",
    critique = "CRIT",
    critico = "CRIT",
    ["crítico"] = "CRIT",
    ["крит"] = "CRIT",
    ["критический"] = "CRIT",
    ["치명타"] = "CRIT",
    ["극대화"] = "CRIT",
    ["爆击"] = "CRIT",
    ["暴击"] = "CRIT",
    ["致命一擊"] = "CRIT",
    ["致命"] = "CRIT",
    haste = "HASTE",
    tempo = "HASTE",
    ["hâte"] = "HASTE",
    celeridad = "HASTE",
    celerita = "HASTE",
    ["celerità"] = "HASTE",
    aceleracao = "HASTE",
    ["aceleração"] = "HASTE",
    ["скорость"] = "HASTE",
    ["가속"] = "HASTE",
    ["急速"] = "HASTE",
    ["加速"] = "HASTE",
    mastery = "MASTERY",
    meisterschaft = "MASTERY",
    maitrise = "MASTERY",
    ["maîtrise"] = "MASTERY",
    maestria = "MASTERY",
    ["maestría"] = "MASTERY",
    ["искусность"] = "MASTERY",
    ["특화"] = "MASTERY",
    ["精通"] = "MASTERY",
    vers = "VERSATILITY",
    versa = "VERSATILITY",
    versatility = "VERSATILITY",
    vielseitigkeit = "VERSATILITY",
    polyvalence = "VERSATILITY",
    versatilidad = "VERSATILITY",
    versatilita = "VERSATILITY",
    ["versatilità"] = "VERSATILITY",
    versatilidade = "VERSATILITY",
    ["универсальность"] = "VERSATILITY",
    ["유연성"] = "VERSATILITY",
    ["全能"] = "VERSATILITY",
    ["臨機應變"] = "VERSATILITY",
}

local RANK_COLORS = {
    [1] = { r = 1.00, g = 0.50, b = 0.00 },
    [2] = { r = 0.64, g = 0.21, b = 0.93 },
    [3] = { r = 0.00, g = 0.44, b = 0.87 },
    [4] = { r = 0.12, g = 1.00, b = 0.00 },
}

local DISPLAY_SETTING_KEYS = {
    stat_colors = true,
    stat_dots = true,
}

local DISPLAY_SETTING_DEFAULTS = {
    stat_colors = false,
    stat_dots = false,
}

-- WoW item class IDs are stable API values: 2 = Weapon, 4 = Armor.
-- Requiring an equipment location also excludes armor tokens and other
-- non-equippable items that happen to use one of these item classes.
local EQUIPMENT_ITEM_CLASSES = {
    [2] = true,
    [4] = true,
}

local function getTooltipItemReference(tooltip, data)
    if type(data) == "table" then
        local ok, value = pcall(function()
            return data.itemID or data.id or data.hyperlink or data.itemLink or data.link
        end)
        if ok and (type(value) == "number" or (type(value) == "string" and value ~= "")) then
            return value
        end
    end

    if tooltip and type(tooltip.GetItem) == "function" then
        local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
        if ok and type(itemLink) == "string" and itemLink ~= "" then
            return itemLink
        end
    end

    return nil
end

local function isSupportedEquipmentTooltip(tooltip, data)
    local itemReference = getTooltipItemReference(tooltip, data)
    if itemReference == nil or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then
        return false
    end

    local ok, itemID, _, _, equipLocation, _, classID = pcall(C_Item.GetItemInfoInstant, itemReference)
    if not ok or not tonumber(itemID) or not EQUIPMENT_ITEM_CLASSES[tonumber(classID)] then
        return false
    end

    return type(equipLocation) == "string"
        and equipLocation ~= ""
        and equipLocation ~= "INVTYPE_NON_EQUIP"
end

local function copyStatOrder(order)
    local result = {}
    for index, stat in ipairs(type(order) == "table" and order or {}) do
        result[index] = stat
    end
    return #result > 0 and result or nil
end

local function normalizeProfileRecord(profile, fallbackMode, fallbackOrder, fallbackBuildKey)
    profile = type(profile) == "table" and profile or {}
    local mode = profile.mode
    if mode ~= MODE_CUSTOM and mode ~= MODE_PRESET then
        mode = fallbackMode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
    end
    profile.mode = mode
    profile.order = type(profile.order) == "table" and profile.order
        or (mode == MODE_CUSTOM and copyStatOrder(fallbackOrder) or nil)
    if mode ~= MODE_CUSTOM then
        profile.order = nil
    end
    profile.buildKey = type(profile.buildKey) == "string" and profile.buildKey ~= ""
        and profile.buildKey
        or (type(fallbackBuildKey) == "string" and fallbackBuildKey ~= "" and fallbackBuildKey)
        or DEFAULT_BUILD_KEY
    return profile
end

local function normalizeSpecRecord(record)
    if type(record) ~= "table" then
        return nil
    end

    local legacy = record.version ~= 2
    local legacyMode = record.mode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
    local legacyOrder = type(record.order) == "table" and record.order or nil
    local legacyBuildKey = type(record.buildKey) == "string" and record.buildKey ~= ""
        and record.buildKey or DEFAULT_BUILD_KEY
    record.version = 2
    record.contentKey = VALID_CONTENT_KEYS[record.contentKey] and record.contentKey or DEFAULT_CONTENT_KEY
    record.profiles = type(record.profiles) == "table" and record.profiles or {}

    for _, contentKey in ipairs(CONTENT_KEYS) do
        local fallbackMode = legacy and legacyMode or MODE_PRESET
        local fallbackOrder = legacy and legacyOrder or nil
        record.profiles[contentKey] = normalizeProfileRecord(
            record.profiles[contentKey],
            fallbackMode,
            fallbackOrder,
            legacyBuildKey
        )
    end

    record.mode = nil
    record.order = nil
    record.buildKey = nil
    return record
end

local Runtime = {
    enabled = false,
    hooksReady = false,
    statLookup = nil,
    trackedTooltips = setmetatable({}, { __mode = "k" }),
}

Addon.StatFocus = Runtime

local function getCurrentContext()
    local classToken
    if type(UnitClass) == "function" then
        local _
        _, classToken = UnitClass("player")
    end

    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
    specIndex = tonumber(specIndex)
    if type(classToken) ~= "string" or classToken == "" or not specIndex or specIndex < 1 then
        return nil
    end

    local specID, specName
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
        local ok, resolvedID, resolvedName = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        if ok then
            specID = tonumber(resolvedID)
            specName = resolvedName
        end
    elseif type(GetSpecializationInfo) == "function" then
        local ok, resolvedID, resolvedName = pcall(GetSpecializationInfo, specIndex)
        if ok then
            specID = tonumber(resolvedID)
            specName = resolvedName
        end
    end

    return {
        classToken = classToken,
        specIndex = specIndex,
        specID = specID,
        specName = type(specName) == "string" and specName or nil,
        specKey = specID and tostring(specID) or (classToken .. ":" .. tostring(specIndex)),
    }
end

local function getCurrentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
    if type(identity) == "table" and type(identity.key) == "string" and identity.key ~= "" then
        return identity.key
    end
    if Addon.WoWApi and type(Addon.WoWApi.GetCurrentCharacterIdentity) == "function" then
        local current = Addon.WoWApi:GetCurrentCharacterIdentity()
        if type(current) == "table" and type(current.key) == "string" and current.key ~= "" then
            return current.key
        end
    end
    return "player"
end

local function getStore(create)
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    if create then
        db.features.statFocus = type(db.features.statFocus) == "table" and db.features.statFocus or {}
        db.features.statFocus.characters = type(db.features.statFocus.characters) == "table"
            and db.features.statFocus.characters or {}
        return db.features.statFocus
    end
    return type(db.features.statFocus) == "table" and db.features.statFocus or nil
end

local function getSpecRecord(create)
    local context = getCurrentContext()
    if not context then
        return nil, nil
    end
    local store = getStore(create)
    if type(store) ~= "table" then
        return nil, context
    end

    local characterKey = getCurrentCharacterKey()
    if create then
        store.characters[characterKey] = type(store.characters[characterKey]) == "table"
            and store.characters[characterKey] or {}
        store.characters[characterKey][context.specKey] = type(store.characters[characterKey][context.specKey]) == "table"
            and store.characters[characterKey][context.specKey] or {}
        return normalizeSpecRecord(store.characters[characterKey][context.specKey]), context
    end

    local characterStore = type(store.characters) == "table" and store.characters[characterKey] or nil
    local record = type(characterStore) == "table" and characterStore[context.specKey] or nil
    return normalizeSpecRecord(record), context
end

local function getPreset(context, contentKey, buildKey)
    if not context or not Addon.StatFocusPresets then
        return nil
    end
    return Addon.StatFocusPresets:GetProfile(
        context.specID,
        context.classToken,
        context.specIndex,
        contentKey,
        buildKey
    )
end

local function getActiveProfileRecord(create)
    local record, context = getSpecRecord(create)
    if not record then
        return nil, context, nil
    end
    local contentKey = VALID_CONTENT_KEYS[record.contentKey] and record.contentKey or DEFAULT_CONTENT_KEY
    if create then
        record.profiles[contentKey] = normalizeProfileRecord(record.profiles[contentKey])
    end
    return record.profiles[contentKey], context, record
end

local function isBuildAvailable(context, contentKey, buildKey)
    if buildKey == DEFAULT_BUILD_KEY then
        return true
    end
    if not context or not Addon.StatFocusPresets
        or type(Addon.StatFocusPresets.GetAvailableBuilds) ~= "function"
    then
        return false
    end
    for _, candidate in ipairs(Addon.StatFocusPresets:GetAvailableBuilds(
        context.specID,
        context.classToken,
        context.specIndex,
        contentKey
    )) do
        if candidate == buildKey then
            return true
        end
    end
    return false
end

local function flattenTiers(tiers)
    local result = {}
    local seen = {}
    for _, tier in ipairs(tiers or {}) do
        for _, stat in ipairs(tier or {}) do
            if STAT_DEFINITIONS[stat] and not seen[stat] then
                result[#result + 1] = stat
                seen[stat] = true
            end
        end
    end
    return result
end

local function copyFlatStatsToTiers(stats)
    if type(stats) ~= "table" then
        return nil
    end
    local tiers = {}
    for _, stat in ipairs(stats) do
        if STAT_DEFINITIONS[stat] then
            tiers[#tiers + 1] = { stat }
        end
    end
    return #tiers > 0 and tiers or nil
end

local function normalizeCustomOrder(stats, fallbackTiers)
    local order = {}
    local seen = {}
    for _, stat in ipairs(stats or {}) do
        if STAT_DEFINITIONS[stat] and not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    for _, stat in ipairs(flattenTiers(fallbackTiers)) do
        if not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    for _, stat in ipairs(DEFAULT_STAT_ORDER) do
        if not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    return #order == 4 and order or nil
end

local function buildRankMap(tiers)
    local rankMap = {}
    for rank, tier in ipairs(tiers or {}) do
        local color = RANK_COLORS[rank] or RANK_COLORS[#RANK_COLORS]
        for _, stat in ipairs(tier or {}) do
            if STAT_DEFINITIONS[stat] and not rankMap[stat] then
                rankMap[stat] = {
                    rank = rank,
                    color = color,
                }
            end
        end
    end
    return rankMap
end

local function clampColorChannel(value)
    value = tonumber(value) or 0
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
end

local function colorToHex(color)
    color = color or RANK_COLORS[4]
    return string.format(
        "|cff%02x%02x%02x",
        clampColorChannel(color.r),
        clampColorChannel(color.g),
        clampColorChannel(color.b)
    )
end

local function colorText(text, color)
    return colorToHex(color) .. tostring(text or "") .. "|r"
end

local function getStatLabel(stat)
    local definition = STAT_DEFINITIONS[stat]
    if not definition then
        return tostring(stat or "")
    end
    for _, globalName in ipairs(definition.globals or {}) do
        local value = _G[globalName]
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return definition.fallback
end

local function formatTierSummary(tiers)
    local tierParts = {}
    for rank, tier in ipairs(tiers or {}) do
        local statParts = {}
        local color = RANK_COLORS[rank] or RANK_COLORS[#RANK_COLORS]
        for _, stat in ipairs(tier or {}) do
            statParts[#statParts + 1] = colorText(getStatLabel(stat), color)
        end
        if #statParts > 0 then
            tierParts[#tierParts + 1] = table.concat(statParts, " = ")
        end
    end
    return table.concat(tierParts, " > ")
end

local function buildStatLookup()
    local lookup = {}
    for stat, definition in pairs(STAT_DEFINITIONS) do
        for _, globalName in ipairs(definition.globals or {}) do
            local value = _G[globalName]
            if type(value) == "string" and value ~= "" then
                lookup[value] = stat
            end
        end
        lookup[definition.fallback] = stat
    end
    return lookup
end

local function findStatInText(text, lookup)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    for localizedStat, stat in pairs(lookup or {}) do
        local ok, found = pcall(string.find, text, localizedStat, 1, true)
        if ok and found then
            return stat
        end
    end
    return nil
end

local function getDotTexture(rankInfo)
    local fileName = DOT_TEXTURES[rankInfo and rankInfo.rank or 4] or DOT_TEXTURES[4]
    local path = "Interface\\AddOns\\" .. tostring(Addon.name) .. "\\Assets\\" .. fileName
    return string.format("|T%s:9:9:0:0|t", path)
end

local function parseStatToken(raw)
    raw = tostring(raw or ""):lower()
    raw = raw:gsub("[,;>]+", "")
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    return STAT_ALIASES[raw]
end

local function splitWords(message)
    local words = {}
    for word in tostring(message or ""):gmatch("%S+") do
        words[#words + 1] = word
    end
    return words
end

local function getContentLabel(contentKey)
    local key = CONTENT_LABEL_KEYS[contentKey]
    return key and Addon.L[key] or tostring(contentKey or DEFAULT_CONTENT_KEY)
end

local function getBuildLabel(buildKey)
    if buildKey == DEFAULT_BUILD_KEY then
        return Addon.L.FEATURE_VALUE_STAT_STANDARD_BUILD
    end
    return tostring(buildKey or DEFAULT_BUILD_KEY)
end

function Runtime:GetCurrentContentProfile()
    local record = getSpecRecord(false)
    return record and record.contentKey or DEFAULT_CONTENT_KEY
end

function Runtime:SetCurrentContentProfile(contentKey)
    contentKey = VALID_CONTENT_KEYS[contentKey] and contentKey or DEFAULT_CONTENT_KEY
    local record, context = getSpecRecord(true)
    if not record then
        return DEFAULT_CONTENT_KEY
    end
    record.contentKey = contentKey
    local profile = record.profiles[contentKey]
    if not isBuildAvailable(context, contentKey, profile.buildKey) then
        profile.buildKey = DEFAULT_BUILD_KEY
    end
    self:RefreshTrackedTooltips()
    return contentKey
end

function Runtime:GetCurrentBuildProfile()
    local profile, context, record = getActiveProfileRecord(false)
    if not profile or not record then
        return DEFAULT_BUILD_KEY
    end
    if not isBuildAvailable(context, record.contentKey, profile.buildKey) then
        profile.buildKey = DEFAULT_BUILD_KEY
    end
    return profile.buildKey
end

function Runtime:SetCurrentBuildProfile(buildKey)
    buildKey = type(buildKey) == "string" and buildKey ~= "" and buildKey or DEFAULT_BUILD_KEY
    local profile, context, record = getActiveProfileRecord(true)
    if not profile or not record then
        return DEFAULT_BUILD_KEY
    end
    if not isBuildAvailable(context, record.contentKey, buildKey) then
        buildKey = DEFAULT_BUILD_KEY
    end
    profile.buildKey = buildKey
    self:RefreshTrackedTooltips()
    return buildKey
end

function Runtime:GetPreset(contentKey, buildKey)
    contentKey = contentKey or self:GetCurrentContentProfile()
    buildKey = buildKey or self:GetCurrentBuildProfile()
    return getPreset(getCurrentContext(), contentKey, buildKey)
end

function Runtime:GetCurrentMode()
    local profile = getActiveProfileRecord(false)
    return type(profile) == "table" and profile.mode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
end

function Runtime:SetCurrentMode(mode)
    mode = mode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
    local profile, context, record = getActiveProfileRecord(true)
    if not profile or not context or not record then
        return MODE_PRESET
    end
    profile.mode = mode
    if mode == MODE_CUSTOM then
        local preset = getPreset(context, record.contentKey, profile.buildKey)
        profile.order = normalizeCustomOrder(profile.order, preset and preset.tiers)
    else
        profile.order = nil
    end
    self:RefreshTrackedTooltips()
    return mode
end

function Runtime:GetCustomTiers()
    local profile, context, record = getActiveProfileRecord(false)
    if type(profile) ~= "table" or not context or not record then
        return nil
    end
    local preset = getPreset(context, record.contentKey, profile.buildKey)
    local order = normalizeCustomOrder(profile.order, preset and preset.tiers)
    if not order then
        return nil
    end
    profile.order = order
    return copyFlatStatsToTiers(order)
end

function Runtime:SetCustomOrder(stats)
    local profile, context, record = getActiveProfileRecord(true)
    if not profile or not context or not record then
        return nil
    end
    local preset = getPreset(context, record.contentKey, profile.buildKey)
    local order = normalizeCustomOrder(stats, preset and preset.tiers)
    if not order then
        return nil
    end
    profile.mode = MODE_CUSTOM
    profile.order = order
    self:RefreshTrackedTooltips()
    return order
end

function Runtime:ClearCustomOrder()
    local profile = getActiveProfileRecord(false)
    if type(profile) == "table" then
        profile.mode = MODE_PRESET
        profile.order = nil
    end
    self:RefreshTrackedTooltips()
end

function Runtime:ResetAllProfiles()
    local record = getSpecRecord(false)
    if type(record) == "table" then
        record.contentKey = DEFAULT_CONTENT_KEY
        for _, contentKey in ipairs(CONTENT_KEYS) do
            record.profiles[contentKey] = normalizeProfileRecord(record.profiles[contentKey])
            record.profiles[contentKey].mode = MODE_PRESET
            record.profiles[contentKey].order = nil
            record.profiles[contentKey].buildKey = DEFAULT_BUILD_KEY
        end
    end
    self:RefreshTrackedTooltips()
end

function Runtime:GetActiveTiers()
    local record, context = getSpecRecord(false)
    local contentKey = record and record.contentKey or DEFAULT_CONTENT_KEY
    local profile = record and record.profiles[contentKey] or nil
    local buildKey = profile and profile.buildKey or DEFAULT_BUILD_KEY
    if not isBuildAvailable(context, contentKey, buildKey) then
        buildKey = DEFAULT_BUILD_KEY
        if profile then
            profile.buildKey = buildKey
        end
    end
    local preset = getPreset(context, contentKey, buildKey)
    if type(profile) == "table" and profile.mode == MODE_CUSTOM then
        local order = normalizeCustomOrder(profile.order, preset and preset.tiers)
        if order then
            profile.order = order
            return copyFlatStatsToTiers(order), MODE_CUSTOM, preset, context, contentKey, buildKey
        end
    end
    return preset and preset.tiers or nil, MODE_PRESET, preset, context, contentKey, buildKey
end

function Runtime:GetSummaryText()
    local tiers, _, _, context, contentKey = self:GetActiveTiers()
    if not tiers then
        return Addon.L.FEATURE_STAT_FOCUS_NO_SPEC
    end
    local labels = { getContentLabel(contentKey) }
    if context and context.specName then
        table.insert(labels, 1, context.specName)
    end
    return table.concat(labels, " · ") .. ": " .. formatTierSummary(tiers)
end

function Runtime:GetSettingValue(settingKey)
    if settingKey == "tooltip_text_style" then
        local saved = Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
        return saved == TOOLTIP_STYLE_CLEAN and TOOLTIP_STYLE_CLEAN or TOOLTIP_STYLE_FULL
    end
    if settingKey == "content_profile" then
        return self:GetCurrentContentProfile()
    end
    if settingKey == "build_profile" then
        return self:GetCurrentBuildProfile()
    end
    if settingKey == "priority_mode" then
        return self:GetCurrentMode()
    end
    if DISPLAY_SETTING_KEYS[settingKey] then
        local saved = Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
        if saved == nil then
            return DISPLAY_SETTING_DEFAULTS[settingKey]
        end
        return saved == true
    end
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey == "tooltip_text_style" then
        Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] =
            value == TOOLTIP_STYLE_CLEAN and TOOLTIP_STYLE_CLEAN or TOOLTIP_STYLE_FULL
        if self.enabled == true then
            self:RefreshTrackedTooltips()
        end
        return true
    end
    if settingKey == "content_profile" then
        return self:SetCurrentContentProfile(value) == value
    end
    if settingKey == "build_profile" then
        return self:SetCurrentBuildProfile(value) == value
    end
    if settingKey == "priority_mode" then
        self:SetCurrentMode(value)
        return true
    end
    if DISPLAY_SETTING_KEYS[settingKey] then
        Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value == true
        if self.enabled == true then
            self:RefreshTrackedTooltips()
        end
        return true
    end
    return false
end

function Runtime:ResetSettingValues()
    self:ResetAllProfiles()
end

local function restoreLineHints(tooltip)
    local states = tooltip and tooltip.VaultloomStatFocusLineStates or nil
    for _, state in ipairs(states or {}) do
        if state.line then
            if state.text ~= nil and type(state.line.SetText) == "function" then
                state.line:SetText(state.text)
            end
            if state.color and type(state.line.SetTextColor) == "function" then
                state.line:SetTextColor(unpack(state.color))
            end
        end
    end
    if tooltip then
        tooltip.VaultloomStatFocusLineStates = nil
    end
end

function Runtime:RestoreTooltip(tooltip, rebuild)
    if not tooltip then
        return
    end
    restoreLineHints(tooltip)
    local hadSummary = tooltip.VaultloomStatFocusSummary == true
    tooltip.VaultloomStatFocusRendered = nil
    tooltip.VaultloomStatFocusSummary = nil

    if rebuild and hadSummary and type(tooltip.GetItem) == "function"
        and type(tooltip.ClearLines) == "function" and type(tooltip.SetHyperlink) == "function"
    then
        local okItem, _, itemLink = pcall(tooltip.GetItem, tooltip)
        local shown = type(tooltip.IsShown) ~= "function" or tooltip:IsShown()
        if okItem and type(itemLink) == "string" and itemLink ~= "" and shown then
            pcall(function()
                tooltip:ClearLines()
                tooltip:SetHyperlink(itemLink)
            end)
        end
    end
end

function Runtime:RefreshTrackedTooltips()
    for tooltip in pairs(self.trackedTooltips) do
        self:RestoreTooltip(tooltip, true)
    end
end

local function ensureTooltipResetHook(tooltip)
    if not tooltip or tooltip.VaultloomStatFocusClearHook then
        return
    end
    if type(tooltip.HookScript) == "function" then
        tooltip:HookScript("OnTooltipCleared", function(self)
            restoreLineHints(self)
            self.VaultloomStatFocusRendered = nil
            self.VaultloomStatFocusSummary = nil
        end)
        tooltip.VaultloomStatFocusClearHook = true
    end
end

function Runtime:ApplyLineHints(tooltip, rankMap, colorLines, addDots)
    local tooltipName = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if type(tooltipName) ~= "string" or tooltipName == "" then
        return
    end

    self.statLookup = self.statLookup or buildStatLookup()
    local states = {}
    local lineCount = type(tooltip.NumLines) == "function" and tonumber(tooltip:NumLines()) or 0
    for index = 2, lineCount do
        local line = _G[tooltipName .. "TextLeft" .. tostring(index)]
        if line and type(line.GetText) == "function" then
            local okText, text = pcall(line.GetText, line)
            local stat = okText and findStatInText(text, self.statLookup) or nil
            local rankInfo = stat and rankMap[stat] or nil
            if rankInfo and rankInfo.color then
                local originalColor
                if type(line.GetTextColor) == "function" then
                    local okColor, r, g, b, a = pcall(line.GetTextColor, line)
                    if okColor then
                        originalColor = { r, g, b, a }
                    end
                end
                states[#states + 1] = {
                    line = line,
                    text = text,
                    color = originalColor,
                }
                if colorLines and type(line.SetTextColor) == "function" then
                    line:SetTextColor(rankInfo.color.r, rankInfo.color.g, rankInfo.color.b, 1)
                end
                local hasDot = false
                if addDots then
                    local okDot, dotPosition = pcall(string.find, text, DOT_TEXTURE_TOKEN, 1, true)
                    hasDot = okDot and dotPosition ~= nil
                end
                if addDots and type(line.SetText) == "function" and not hasDot then
                    line:SetText(text .. "  " .. getDotTexture(rankInfo))
                end
            end
        end
    end
    tooltip.VaultloomStatFocusLineStates = #states > 0 and states or nil
end

function Runtime:AddSummary(tooltip, tiers, textStyle, contentKey)
    tooltip:AddLine(" ")
    if textStyle == TOOLTIP_STYLE_FULL then
        tooltip:AddLine(
            Addon.L.FEATURE_STAT_FOCUS_TOOLTIP_HEADER .. " · " .. getContentLabel(contentKey),
            1,
            0.82,
            0.24,
            true
        )
    end
    tooltip:AddLine(formatTierSummary(tiers), 1, 1, 1, true)
    tooltip.VaultloomStatFocusSummary = true
end

function Runtime:ApplyTooltip(tooltip, data)
    if self.enabled ~= true or not tooltip or tooltip.VaultloomStatFocusRendered then
        return
    end

    if not isSupportedEquipmentTooltip(tooltip, data) then
        return
    end

    local tiers, _, _, _, contentKey = self:GetActiveTiers()
    if not tiers then
        return
    end
    local rankMap = buildRankMap(tiers)
    local textStyle = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "tooltip_text_style")
    local colorLines = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_colors") == true
    local addDots = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_dots") == true

    ensureTooltipResetHook(tooltip)
    tooltip.VaultloomStatFocusRendered = true
    self.trackedTooltips[tooltip] = true

    if colorLines or addDots then
        self:ApplyLineHints(tooltip, rankMap, colorLines, addDots)
    end
    self:AddSummary(tooltip, tiers, textStyle, contentKey)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return
    end
    self.hooksReady = true

    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            Runtime:ApplyTooltip(tooltip, data)
        end)
        return
    end
    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            Runtime:ApplyTooltip(tooltip, nil)
        end)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:EnsureHooks()
end

function Runtime:OnDisable()
    self.enabled = false
    for tooltip in pairs(self.trackedTooltips) do
        self:RestoreTooltip(tooltip, true)
    end
end

function Runtime:OnSettingChanged()
    self:RefreshTrackedTooltips()
end

function Runtime:OnSettingsReset()
    self:RefreshTrackedTooltips()
end

function Runtime:HandleSlash(message)
    local words = splitWords(message)
    local first = words[1] and words[1]:lower() or ""

    if first == "" or first == "show" or first == "status" then
        Addon:Print(self:GetSummaryText())
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_SLASH_HELP)
        return true
    end
    local selectedContent = CONTENT_COMMANDS[first]
    if selectedContent then
        self:SetCurrentContentProfile(selectedContent)
        Addon:Print(string.format(
            Addon.L.FEATURE_STAT_FOCUS_PROFILE_SELECTED,
            getContentLabel(selectedContent)
        ))
        Addon:Print(self:GetSummaryText())
        return true
    end
    if first == "build" and words[2] then
        local buildKey = words[2]:lower()
        local selectedBuild = self:SetCurrentBuildProfile(buildKey)
        Addon:Print(string.format(
            Addon.L.FEATURE_STAT_FOCUS_BUILD_SELECTED,
            getBuildLabel(selectedBuild)
        ))
        Addon:Print(self:GetSummaryText())
        return true
    end
    if first == "preset" or first == "auto" or first == "预设" or first == "自动" or first == "預設" or first == "自動" then
        self:SetCurrentMode(MODE_PRESET)
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_PRESET_ENABLED)
        Addon:Print(self:GetSummaryText())
        return true
    end
    if first == "reset" or first == "clear" or first == "重置" or first == "重設" or first == "清除" then
        self:ClearCustomOrder()
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_CUSTOM_CLEARED)
        Addon:Print(self:GetSummaryText())
        return true
    end

    local parsed = {}
    local startIndex = (
        first == "custom"
        or first == "eigen"
        or first == "personnalise"
        or first == "personnalisé"
        or first == "personalizado"
        or first == "personalizada"
        or first == "свой"
        or first == "своя"
        or first == "사용자"
        or first == "사용자지정"
        or first == "自定义"
        or first == "自訂"
    ) and 2 or 1
    for index = startIndex, #words do
        local stat = parseStatToken(words[index])
        if stat then
            parsed[#parsed + 1] = stat
        end
    end
    if #parsed > 0 and self:SetCustomOrder(parsed) then
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_CUSTOM_SAVED)
        Addon:Print(self:GetSummaryText())
        return true
    end

    Addon:Print(Addon.L.FEATURE_STAT_FOCUS_SLASH_HELP)
    return true
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Stat Focus feature runtime.")
end
