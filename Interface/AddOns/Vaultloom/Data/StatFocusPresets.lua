local _, Addon = ...

-- These are deliberately relative priority tiers, not simulated point weights.
-- Exact stat values change with a character's gear, embellishments, and diminishing
-- returns. Tied tiers mark a meaningful guide/build disagreement instead of
-- pretending that one universal order is exact.
local Presets = {
    metadata = {
        schemaVersion = 1,
        patch = "12.0.7",
        season = "Midnight Season 1",
        reviewedAt = "2026-07-27",
        methodology = "Icy Veins + Wowhead consensus; Pawn/Ask Mr. Robot cross-check",
        sources = {
            {
                key = "icy_veins",
                label = "Icy Veins",
                url = "https://www.icy-veins.com/wow/class-guides",
            },
            {
                key = "wowhead",
                label = "Wowhead",
                url = "https://www.wowhead.com/guides/classes",
            },
            {
                key = "pawn_askmrrobot",
                label = "Pawn / Ask Mr. Robot",
                version = "Pawn 2.13.13",
                url = "https://www.curseforge.com/wow/addons/pawn",
            },
        },
    },
    bySpecID = {
        -- Death Knight
        [250] = { classToken = "DEATHKNIGHT", specIndex = 1, contextual = true, tiers = { { "HASTE", "CRIT" }, { "VERSATILITY", "MASTERY" } } },
        [251] = { classToken = "DEATHKNIGHT", specIndex = 2, tiers = { { "CRIT", "MASTERY" }, { "HASTE" }, { "VERSATILITY" } } },
        [252] = { classToken = "DEATHKNIGHT", specIndex = 3, tiers = { { "MASTERY" }, { "CRIT" }, { "HASTE" }, { "VERSATILITY" } } },

        -- Demon Hunter
        [577] = { classToken = "DEMONHUNTER", specIndex = 1, tiers = { { "CRIT" }, { "MASTERY" }, { "HASTE" }, { "VERSATILITY" } } },
        [581] = { classToken = "DEMONHUNTER", specIndex = 2, tiers = { { "HASTE" }, { "CRIT", "VERSATILITY" }, { "MASTERY" } } },
        [1480] = { classToken = "DEMONHUNTER", specIndex = 3, contextual = true, tiers = { { "HASTE", "MASTERY" }, { "CRIT" }, { "VERSATILITY" } } },

        -- Druid
        [102] = { classToken = "DRUID", specIndex = 1, contextual = true, tiers = { { "MASTERY", "CRIT" }, { "HASTE" }, { "VERSATILITY" } } },
        [103] = { classToken = "DRUID", specIndex = 2, tiers = { { "MASTERY" }, { "HASTE", "CRIT" }, { "VERSATILITY" } } },
        [104] = { classToken = "DRUID", specIndex = 3, tiers = { { "HASTE" }, { "VERSATILITY" }, { "CRIT", "MASTERY" } } },
        [105] = { classToken = "DRUID", specIndex = 4, contextual = true, tiers = { { "HASTE" }, { "MASTERY" }, { "VERSATILITY" }, { "CRIT" } } },

        -- Evoker
        [1467] = { classToken = "EVOKER", specIndex = 1, tiers = { { "CRIT", "HASTE" }, { "MASTERY" }, { "VERSATILITY" } } },
        [1468] = { classToken = "EVOKER", specIndex = 2, tiers = { { "MASTERY" }, { "CRIT" }, { "HASTE" }, { "VERSATILITY" } } },
        [1473] = { classToken = "EVOKER", specIndex = 3, tiers = { { "CRIT" }, { "HASTE" }, { "MASTERY" }, { "VERSATILITY" } } },

        -- Hunter
        [253] = { classToken = "HUNTER", specIndex = 1, contextual = true, tiers = { { "MASTERY" }, { "CRIT", "HASTE" }, { "VERSATILITY" } } },
        [254] = { classToken = "HUNTER", specIndex = 2, tiers = { { "CRIT" }, { "MASTERY" }, { "VERSATILITY" }, { "HASTE" } } },
        [255] = { classToken = "HUNTER", specIndex = 3, tiers = { { "MASTERY" }, { "CRIT", "HASTE" }, { "VERSATILITY" } } },

        -- Mage
        [62] = { classToken = "MAGE", specIndex = 1, contextual = true, tiers = { { "MASTERY" }, { "HASTE", "VERSATILITY" }, { "CRIT" } } },
        [63] = { classToken = "MAGE", specIndex = 2, tiers = { { "HASTE" }, { "MASTERY" }, { "VERSATILITY" }, { "CRIT" } } },
        [64] = { classToken = "MAGE", specIndex = 3, tiers = { { "MASTERY" }, { "CRIT" }, { "HASTE" }, { "VERSATILITY" } } },

        -- Monk
        [268] = { classToken = "MONK", specIndex = 1, contextual = true, tiers = { { "CRIT", "VERSATILITY", "MASTERY" }, { "HASTE" } } },
        [270] = { classToken = "MONK", specIndex = 2, tiers = { { "HASTE" }, { "CRIT" }, { "VERSATILITY" }, { "MASTERY" } } },
        [269] = { classToken = "MONK", specIndex = 3, tiers = { { "HASTE" }, { "CRIT", "MASTERY" }, { "VERSATILITY" } } },

        -- Paladin
        [65] = { classToken = "PALADIN", specIndex = 1, contextual = true, tiers = { { "MASTERY" }, { "HASTE", "CRIT" }, { "VERSATILITY" } } },
        [66] = { classToken = "PALADIN", specIndex = 2, tiers = { { "HASTE" }, { "VERSATILITY" }, { "MASTERY", "CRIT" } } },
        [70] = { classToken = "PALADIN", specIndex = 3, tiers = { { "MASTERY" }, { "CRIT" }, { "HASTE" }, { "VERSATILITY" } } },

        -- Priest
        [256] = { classToken = "PRIEST", specIndex = 1, contextual = true, tiers = { { "HASTE" }, { "CRIT", "MASTERY" }, { "VERSATILITY" } } },
        [257] = { classToken = "PRIEST", specIndex = 2, contextual = true, tiers = { { "CRIT", "VERSATILITY" }, { "MASTERY", "HASTE" } } },
        [258] = { classToken = "PRIEST", specIndex = 3, tiers = { { "HASTE" }, { "MASTERY" }, { "CRIT" }, { "VERSATILITY" } } },

        -- Rogue
        [259] = { classToken = "ROGUE", specIndex = 1, tiers = { { "CRIT" }, { "HASTE" }, { "MASTERY" }, { "VERSATILITY" } } },
        [260] = { classToken = "ROGUE", specIndex = 2, tiers = { { "CRIT", "HASTE" }, { "VERSATILITY" }, { "MASTERY" } } },
        [261] = { classToken = "ROGUE", specIndex = 3, contextual = true, tiers = { { "HASTE", "MASTERY" }, { "CRIT" }, { "VERSATILITY" } } },

        -- Shaman
        [262] = { classToken = "SHAMAN", specIndex = 1, tiers = { { "MASTERY" }, { "HASTE", "CRIT" }, { "VERSATILITY" } } },
        [263] = { classToken = "SHAMAN", specIndex = 2, contextual = true, tiers = { { "MASTERY", "HASTE" }, { "CRIT" }, { "VERSATILITY" } } },
        [264] = { classToken = "SHAMAN", specIndex = 3, contextual = true, tiers = { { "CRIT" }, { "VERSATILITY", "HASTE", "MASTERY" } } },

        -- Warlock
        [265] = { classToken = "WARLOCK", specIndex = 1, tiers = { { "HASTE" }, { "CRIT" }, { "MASTERY", "VERSATILITY" } } },
        [266] = { classToken = "WARLOCK", specIndex = 2, tiers = { { "CRIT", "HASTE" }, { "MASTERY" }, { "VERSATILITY" } } },
        [267] = { classToken = "WARLOCK", specIndex = 3, contextual = true, tiers = { { "HASTE", "CRIT" }, { "MASTERY" }, { "VERSATILITY" } } },

        -- Warrior
        [71] = { classToken = "WARRIOR", specIndex = 1, tiers = { { "CRIT" }, { "HASTE" }, { "MASTERY" }, { "VERSATILITY" } } },
        [72] = { classToken = "WARRIOR", specIndex = 2, contextual = true, tiers = { { "MASTERY", "HASTE" }, { "VERSATILITY", "CRIT" } } },
        [73] = { classToken = "WARRIOR", specIndex = 3, tiers = { { "HASTE" }, { "VERSATILITY", "CRIT" }, { "MASTERY" } } },
    },
}

local VALID_STATS = {
    CRIT = true,
    HASTE = true,
    MASTERY = true,
    VERSATILITY = true,
}

local function validate()
    local count = 0
    local fallbackKeys = {}
    for specID, preset in pairs(Presets.bySpecID) do
        count = count + 1
        assert(type(specID) == "number" and specID > 0, "Invalid Stat Focus specialization ID")
        assert(type(preset.classToken) == "string" and preset.classToken ~= "", "Invalid Stat Focus class")
        assert(type(preset.specIndex) == "number" and preset.specIndex > 0, "Invalid Stat Focus specialization index")

        local seen = {}
        local statCount = 0
        for _, tier in ipairs(preset.tiers or {}) do
            assert(type(tier) == "table" and #tier > 0, "Empty Stat Focus priority tier")
            for _, stat in ipairs(tier) do
                assert(VALID_STATS[stat] and not seen[stat], "Invalid or duplicate Stat Focus stat")
                seen[stat] = true
                statCount = statCount + 1
            end
        end
        assert(statCount == 4, "Incomplete Stat Focus priority")

        local fallbackKey = preset.classToken .. ":" .. tostring(preset.specIndex)
        assert(not fallbackKeys[fallbackKey], "Duplicate Stat Focus class/index fallback")
        fallbackKeys[fallbackKey] = specID
    end
    assert(count == 40, "Stat Focus must contain all 40 Retail specializations")
    Presets.count = count
    Presets.fallbackSpecIDs = fallbackKeys
end

validate()

function Presets:Get(specID, classToken, specIndex)
    local preset = self.bySpecID[tonumber(specID)]
    if preset then
        return preset
    end
    local fallbackID = self.fallbackSpecIDs[tostring(classToken or "") .. ":" .. tostring(specIndex or "")]
    return fallbackID and self.bySpecID[fallbackID] or nil
end

function Presets:GetCount()
    return self.count
end

function Presets:GetMetadata()
    return self.metadata
end

Addon.StatFocusPresets = Presets
