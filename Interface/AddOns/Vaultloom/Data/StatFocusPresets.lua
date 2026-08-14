local _, Addon = ...

-- Stat Focus deliberately uses relative priority tiers, not simulated point
-- weights. Exact values change with gear, embellishments, tier sets, talents,
-- and diminishing returns. A tied tier records a meaningful guide/build
-- disagreement instead of pretending that one universal order is exact.

local CONTENT_KEYS = { "solo", "delve", "raid", "mythicplus" }
local CONTENT_KEY_SET = {
    solo = true,
    delve = true,
    raid = true,
    mythicplus = true,
}
local DEFAULT_CONTENT_KEY = "solo"
local DEFAULT_BUILD_KEY = "standard"

local function contentProfiles(overrides)
    overrides = type(overrides) == "table" and overrides or {}
    local profiles = {}
    for _, contentKey in ipairs(CONTENT_KEYS) do
        local profile = type(overrides[contentKey]) == "table" and overrides[contentKey] or {
            inherit = "default",
        }
        profile.defaultBuild = type(profile.defaultBuild) == "string" and profile.defaultBuild ~= ""
            and profile.defaultBuild or DEFAULT_BUILD_KEY
        profile.builds = type(profile.builds) == "table" and profile.builds or {}
        profiles[contentKey] = profile
    end
    return profiles
end

local function priority(...)
    local tiers = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        tiers[index] = type(value) == "table" and value or { value }
    end
    return tiers
end

local function contentPriorities(solo, delve, raid, mythicplus)
    delve = delve or solo
    raid = raid or solo
    mythicplus = mythicplus or delve
    return contentProfiles({
        solo = { tiers = solo },
        delve = { tiers = delve },
        raid = { tiers = raid },
        mythicplus = { tiers = mythicplus },
    })
end

local function specialization(classToken, specIndex, profiles, contextual)
    return {
        classToken = classToken,
        specIndex = specIndex,
        contextual = contextual == true,
        default = {
            tiers = profiles.solo.tiers,
        },
        profiles = profiles,
    }
end

local Presets = {
    metadata = {
        schemaVersion = 2,
        dataVersion = "2026.08.12-12.1.0",
        status = "verified",
        sourcePatch = "12.1.0",
        sourceSeason = "Midnight Season 2",
        targetPatch = "12.1.0",
        targetSeason = "Midnight Season 2",
        reviewedAt = "2026-08-12",
        preparedAt = "2026-08-12",
        methodology = "Icy Veins 12.1 primary; Wowhead 12.1 and current Archon Raid/Mythic+ data cross-check",
        note = "Generalized secondary-stat presets; personal gear, hero talents, caps, and diminishing returns can change exact values",
        coverage = {
            specializations = 40,
            contentProfiles = 160,
            explicitProfiles = 160,
            contextSpecificSpecializations = 10,
        },
        contentModel = {
            solo = "single-target or general 12.1 guide priority",
            delve = "multi-target/dungeon priority when published; otherwise the closest current general priority",
            raid = "raid or single-target priority when published",
            mythicplus = "Mythic+/dungeon/AoE priority when published",
        },
        sources = {
            {
                key = "icy_veins",
                label = "Icy Veins",
                patch = "12.1",
                checkedAt = "2026-08-12",
                url = "https://www.icy-veins.com/wow/class-guides",
            },
            {
                key = "wowhead",
                label = "Wowhead",
                patch = "12.1.0",
                checkedAt = "2026-08-12",
                url = "https://www.wowhead.com/guides/classes",
            },
            {
                key = "archon",
                label = "Archon",
                dataWindow = "last 14 days",
                note = "Season 1 log cross-check until Season 2 has a stable sample",
                checkedAt = "2026-08-12",
                url = "https://www.archon.gg/wow/builds",
            },
        },
    },
    bySpecID = {
        -- Death Knight
        [250] = specialization("DEATHKNIGHT", 1, contentPriorities(
            priority({ "HASTE", "CRIT" }, "MASTERY", "VERSATILITY")
        ), true),
        [251] = specialization("DEATHKNIGHT", 2, contentPriorities(
            priority("CRIT", "HASTE", "MASTERY", "VERSATILITY")
        )),
        [252] = specialization("DEATHKNIGHT", 3, contentPriorities(
            priority("CRIT", "MASTERY", "HASTE", "VERSATILITY")
        ), true),

        -- Demon Hunter
        [577] = specialization("DEMONHUNTER", 1, contentPriorities(
            priority("CRIT", "MASTERY", "HASTE", "VERSATILITY")
        )),
        [581] = specialization("DEMONHUNTER", 2, contentPriorities(
            priority("HASTE", "VERSATILITY", "CRIT", "MASTERY")
        )),
        [1480] = specialization("DEMONHUNTER", 3, contentPriorities(
            priority("HASTE", { "MASTERY", "CRIT" }, "VERSATILITY")
        ), true),

        -- Druid
        [102] = specialization("DRUID", 1, contentPriorities(
            priority("CRIT", "MASTERY", "HASTE", "VERSATILITY")
        ), true),
        [103] = specialization("DRUID", 2, contentPriorities(
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY"),
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY"),
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY"),
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY")
        ), true),
        [104] = specialization("DRUID", 3, contentPriorities(
            priority("HASTE", "VERSATILITY", "CRIT", "MASTERY"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT")
        ), true),
        [105] = specialization("DRUID", 4, contentPriorities(
            priority("HASTE", "MASTERY", "VERSATILITY", "CRIT"),
            priority("MASTERY", "HASTE", "VERSATILITY", "CRIT"),
            priority("HASTE", "MASTERY", "VERSATILITY", "CRIT"),
            priority("MASTERY", "HASTE", "VERSATILITY", "CRIT")
        ), true),

        -- Evoker
        [1467] = specialization("EVOKER", 1, contentPriorities(
            priority("CRIT", "HASTE", "MASTERY", "VERSATILITY")
        )),
        [1468] = specialization("EVOKER", 2, contentPriorities(
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY"),
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY"),
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY"),
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY")
        ), true),
        [1473] = specialization("EVOKER", 3, contentPriorities(
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY")
        ), true),

        -- Hunter
        [253] = specialization("HUNTER", 1, contentPriorities(
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY"),
            priority("MASTERY", "CRIT", "VERSATILITY", "HASTE"),
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY"),
            priority("MASTERY", "CRIT", "VERSATILITY", "HASTE")
        ), true),
        [254] = specialization("HUNTER", 2, contentPriorities(
            priority("CRIT", "MASTERY", "VERSATILITY", "HASTE")
        )),
        [255] = specialization("HUNTER", 3, contentPriorities(
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY")
        )),

        -- Mage
        [62] = specialization("MAGE", 1, contentPriorities(
            priority("HASTE", "CRIT", "MASTERY", "VERSATILITY")
        ), true),
        [63] = specialization("MAGE", 2, contentPriorities(
            priority("HASTE", "MASTERY", "VERSATILITY", "CRIT")
        )),
        [64] = specialization("MAGE", 3, contentPriorities(
            priority("MASTERY", "CRIT", "HASTE", "VERSATILITY")
        )),

        -- Monk
        [268] = specialization("MONK", 1, contentPriorities(
            priority("CRIT", "MASTERY", "VERSATILITY", "HASTE"),
            priority("CRIT", "VERSATILITY", "MASTERY", "HASTE"),
            priority("CRIT", "VERSATILITY", "MASTERY", "HASTE"),
            priority("CRIT", "VERSATILITY", "MASTERY", "HASTE")
        ), true),
        [270] = specialization("MONK", 2, contentPriorities(
            priority("HASTE", "CRIT", "VERSATILITY", "MASTERY"),
            priority("HASTE", "MASTERY", "CRIT", "VERSATILITY"),
            priority("HASTE", "CRIT", "VERSATILITY", "MASTERY"),
            priority("HASTE", "MASTERY", "CRIT", "VERSATILITY")
        ), true),
        [269] = specialization("MONK", 3, contentPriorities(
            priority("HASTE", "CRIT", "MASTERY", "VERSATILITY")
        ), true),

        -- Paladin
        [65] = specialization("PALADIN", 1, contentPriorities(
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY")
        ), true),
        [66] = specialization("PALADIN", 2, contentPriorities(
            priority("HASTE", "CRIT", "VERSATILITY", "MASTERY"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT"),
            priority("HASTE", "VERSATILITY", "MASTERY", "CRIT")
        ), true),
        [70] = specialization("PALADIN", 3, contentPriorities(
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY")
        )),

        -- Priest
        [256] = specialization("PRIEST", 1, contentPriorities(
            priority("HASTE", "MASTERY", "CRIT", "VERSATILITY")
        ), true),
        [257] = specialization("PRIEST", 2, contentPriorities(
            priority("CRIT", { "MASTERY", "VERSATILITY" }, "HASTE"),
            priority({ "CRIT", "VERSATILITY" }, "HASTE", "MASTERY"),
            priority("CRIT", { "MASTERY", "VERSATILITY" }, "HASTE"),
            priority({ "CRIT", "VERSATILITY" }, "HASTE", "MASTERY")
        ), true),
        [258] = specialization("PRIEST", 3, contentPriorities(
            priority("HASTE", "MASTERY", "CRIT", "VERSATILITY")
        ), true),

        -- Rogue
        [259] = specialization("ROGUE", 1, contentPriorities(
            priority("CRIT", "HASTE", "MASTERY", "VERSATILITY")
        )),
        [260] = specialization("ROGUE", 2, contentPriorities(
            priority("CRIT", "HASTE", "VERSATILITY", "MASTERY")
        ), true),
        [261] = specialization("ROGUE", 3, contentPriorities(
            priority({ "HASTE", "MASTERY" }, "CRIT", "VERSATILITY")
        ), true),

        -- Shaman
        [262] = specialization("SHAMAN", 1, contentPriorities(
            priority("MASTERY", { "HASTE", "CRIT" }, "VERSATILITY")
        ), true),
        [263] = specialization("SHAMAN", 2, contentPriorities(
            priority("MASTERY", "HASTE", "CRIT", "VERSATILITY")
        ), true),
        [264] = specialization("SHAMAN", 3, contentPriorities(
            priority("CRIT", "HASTE", "VERSATILITY", "MASTERY"),
            priority("CRIT", "HASTE", "VERSATILITY", "MASTERY"),
            priority("CRIT", "VERSATILITY", "HASTE", "MASTERY"),
            priority("CRIT", "HASTE", "VERSATILITY", "MASTERY")
        ), true),

        -- Warlock
        [265] = specialization("WARLOCK", 1, contentPriorities(
            priority("HASTE", "CRIT", "MASTERY", "VERSATILITY")
        ), true),
        [266] = specialization("WARLOCK", 2, contentPriorities(
            priority("HASTE", "CRIT", "MASTERY", "VERSATILITY")
        ), true),
        [267] = specialization("WARLOCK", 3, contentPriorities(
            priority("HASTE", "CRIT", "MASTERY", "VERSATILITY")
        ), true),

        -- Warrior
        [71] = specialization("WARRIOR", 1, contentPriorities(
            priority("CRIT", "HASTE", "MASTERY", "VERSATILITY")
        )),
        [72] = specialization("WARRIOR", 2, contentPriorities(
            priority("MASTERY", "HASTE", { "VERSATILITY", "CRIT" })
        ), true),
        [73] = specialization("WARRIOR", 3, contentPriorities(
            priority("HASTE", "CRIT", "VERSATILITY", "MASTERY")
        )),
    },
}

local VALID_STATS = {
    CRIT = true,
    HASTE = true,
    MASTERY = true,
    VERSATILITY = true,
}

local function validateTiers(tiers, message)
    local seen = {}
    local statCount = 0
    for _, tier in ipairs(tiers or {}) do
        assert(type(tier) == "table" and #tier > 0, "Empty Stat Focus priority tier: " .. message)
        for _, stat in ipairs(tier) do
            assert(VALID_STATS[stat] and not seen[stat], "Invalid or duplicate Stat Focus stat: " .. message)
            seen[stat] = true
            statCount = statCount + 1
        end
    end
    assert(statCount == 4, "Incomplete Stat Focus priority: " .. message)
end

local function validate()
    local count = 0
    local fallbackKeys = {}
    for specID, preset in pairs(Presets.bySpecID) do
        count = count + 1
        assert(type(specID) == "number" and specID > 0, "Invalid Stat Focus specialization ID")
        assert(type(preset.classToken) == "string" and preset.classToken ~= "", "Invalid Stat Focus class")
        assert(type(preset.specIndex) == "number" and preset.specIndex > 0, "Invalid Stat Focus specialization index")
        assert(type(preset.default) == "table", "Missing Stat Focus default profile")
        validateTiers(preset.default.tiers, tostring(specID) .. ":default")

        for _, contentKey in ipairs(CONTENT_KEYS) do
            local profile = preset.profiles and preset.profiles[contentKey] or nil
            assert(type(profile) == "table", "Missing Stat Focus content profile: " .. tostring(specID) .. ":" .. contentKey)
            if profile.tiers then
                validateTiers(profile.tiers, tostring(specID) .. ":" .. contentKey)
            else
                assert(profile.inherit == "default", "Invalid Stat Focus profile inheritance")
            end
            assert(type(profile.defaultBuild) == "string" and profile.defaultBuild ~= "", "Invalid default build key")
            assert(
                profile.defaultBuild == DEFAULT_BUILD_KEY or type(profile.builds[profile.defaultBuild]) == "table",
                "Missing Stat Focus default build"
            )
            for buildKey, build in pairs(profile.builds or {}) do
                assert(type(buildKey) == "string" and buildKey ~= "" and type(build) == "table", "Invalid Stat Focus build")
                if build.tiers then
                    validateTiers(build.tiers, tostring(specID) .. ":" .. contentKey .. ":" .. buildKey)
                else
                    assert(build.inherit == "profile" or build.inherit == "default", "Invalid Stat Focus build inheritance")
                end
            end
        end

        local fallbackKey = preset.classToken .. ":" .. tostring(preset.specIndex)
        assert(not fallbackKeys[fallbackKey], "Duplicate Stat Focus class/index fallback")
        fallbackKeys[fallbackKey] = specID
    end
    assert(count == 40, "Stat Focus must contain all 40 Retail specializations")
    Presets.count = count
    Presets.fallbackSpecIDs = fallbackKeys
end

local function resolvePreset(self, specID, classToken, specIndex)
    local preset = self.bySpecID[tonumber(specID)]
    if preset then
        return preset
    end
    local fallbackID = self.fallbackSpecIDs[tostring(classToken or "") .. ":" .. tostring(specIndex or "")]
    return fallbackID and self.bySpecID[fallbackID] or nil
end

local function resolveFields(source, fallback, metadata)
    source = type(source) == "table" and source or {}
    fallback = type(fallback) == "table" and fallback or {}
    return {
        tiers = source.tiers or fallback.tiers,
        status = source.status or fallback.status or metadata.status,
        sourcePatch = source.sourcePatch or fallback.sourcePatch or metadata.sourcePatch,
        sourceSeason = source.sourceSeason or fallback.sourceSeason or metadata.sourceSeason,
        targetPatch = source.targetPatch or fallback.targetPatch or metadata.targetPatch,
        targetSeason = source.targetSeason or fallback.targetSeason or metadata.targetSeason,
        reviewedAt = source.reviewedAt or fallback.reviewedAt or metadata.reviewedAt,
        note = source.note or fallback.note or metadata.note,
        sources = source.sources or fallback.sources or metadata.sources,
    }
end

validate()

function Presets:Get(specID, classToken, specIndex)
    return resolvePreset(self, specID, classToken, specIndex)
end

function Presets:GetProfile(specID, classToken, specIndex, contentKey, buildKey)
    local preset = resolvePreset(self, specID, classToken, specIndex)
    if not preset then
        return nil
    end

    contentKey = CONTENT_KEY_SET[contentKey] and contentKey or DEFAULT_CONTENT_KEY
    local contentProfile = preset.profiles[contentKey]
    local defaultFields = resolveFields(preset.default, nil, self.metadata)
    local contentFields = resolveFields(contentProfile, defaultFields, self.metadata)
    local requestedBuildKey = type(buildKey) == "string" and buildKey ~= "" and buildKey
        or contentProfile.defaultBuild or DEFAULT_BUILD_KEY
    local resolvedBuildKey = requestedBuildKey
    local fields = contentFields

    if requestedBuildKey ~= DEFAULT_BUILD_KEY then
        local build = contentProfile.builds and contentProfile.builds[requestedBuildKey] or nil
        if build then
            local fallback = build.inherit == "default" and defaultFields or contentFields
            fields = resolveFields(build, fallback, self.metadata)
        else
            resolvedBuildKey = contentProfile.defaultBuild or DEFAULT_BUILD_KEY
            local fallbackBuild = contentProfile.builds and contentProfile.builds[resolvedBuildKey] or nil
            if fallbackBuild then
                local fallback = fallbackBuild.inherit == "default" and defaultFields or contentFields
                fields = resolveFields(fallbackBuild, fallback, self.metadata)
            end
        end
    end

    fields.spec = preset
    fields.contentKey = contentKey
    fields.requestedBuildKey = requestedBuildKey
    fields.buildKey = resolvedBuildKey
    fields.usedBuildFallback = requestedBuildKey ~= resolvedBuildKey
    return fields
end

function Presets:GetAvailableBuilds(specID, classToken, specIndex, contentKey)
    local preset = resolvePreset(self, specID, classToken, specIndex)
    contentKey = CONTENT_KEY_SET[contentKey] and contentKey or DEFAULT_CONTENT_KEY
    local profile = preset and preset.profiles[contentKey] or nil
    local result = { DEFAULT_BUILD_KEY }
    local additional = {}
    for buildKey in pairs(profile and profile.builds or {}) do
        if buildKey ~= DEFAULT_BUILD_KEY then
            additional[#additional + 1] = buildKey
        end
    end
    table.sort(additional)
    for _, buildKey in ipairs(additional) do
        result[#result + 1] = buildKey
    end
    return result
end

function Presets:IsContentKey(contentKey)
    return CONTENT_KEY_SET[contentKey] == true
end

function Presets:GetContentKeys()
    local result = {}
    for index, contentKey in ipairs(CONTENT_KEYS) do
        result[index] = contentKey
    end
    return result
end

function Presets:GetCount()
    return self.count
end

function Presets:GetMetadata()
    return self.metadata
end

Addon.StatFocusPresets = Presets
