local _, Addon = ...

local Seasons = Addon.Data.SEASONS
local activeSeason = Seasons:GetDefinition(Seasons:GetActiveKey("dungeons"))

Addon.Data.DUNGEONS = {
    -- Encounter Journal dungeon buttons have their visible artwork biased toward
    -- the top-left. Keep their circular crop separate from Challenge Mode icons.
    midnightIconTexCoord = { 0.00, 0.78, 0.00, 0.78 },
    difficultyOptions = {
        { key = "normal", labelKey = "RAID_DIFFICULTY_NORMAL" },
        { key = "heroic", labelKey = "RAID_DIFFICULTY_HEROIC" },
        { key = "mythic", labelKey = "DUNGEON_DIFFICULTY_MYTHIC0" },
    },
    difficultyIDs = {
        normal = _G.DIFFICULTY_DUNGEON_NORMAL or 1,
        heroic = _G.DIFFICULTY_DUNGEON_HEROIC or 2,
        mythic = _G.DIFFICULTY_DUNGEON_MYTHIC or 23,
    },
    subTabs = {
        { key = "midnight", labelKey = "DUNGEONS_TAB_MIDNIGHT", subtitleKey = "DUNGEON_JOURNAL_MIDNIGHT_SUBTITLE" },
        {
            key = activeSeason.key,
            labelKey = activeSeason.dungeonLabelKey,
            subtitleKey = activeSeason.dungeonSubtitleKey,
            seasonal = true,
        },
    },
    seasonalKeyGroups = {
        ["altar-of-fangs"] = {
            "altar-of-fangs",
            "altar-der-reisszahne",
            "altar-der-reiszahne",
        },
        ["murder-row"] = {
            "murder-row",
            "murderrow",
            "mordergasse",
        },
        ["den-of-nalorakk"] = {
            "den-of-nalorakk",
            "nalorakks-den",
            "nalorakks-bau",
            "bau-des-nalorakk",
        },
        ["the-blinding-vale"] = {
            "the-blinding-vale",
            "blinding-vale",
            "das-blendende-tal",
        },
        ["voidscar-arena"] = {
            "voidscar-arena",
            "arena-der-leerennarbe",
        },
        ["kings-rest"] = {
            "kings-rest",
            "king-s-rest",
            "konigsruh",
            "die-konigsruh",
        },
        ["temple-of-sethraliss"] = {
            "temple-of-sethraliss",
            "tempel-von-sethraliss",
        },
        ["ruby-life-pools"] = {
            "ruby-life-pools",
            "rubinlebensbecken",
        },
        -- Retain previous-season aliases for historical snapshots and for
        -- Timewalking/rotation reuse by the live Challenge Mode API.
        ["seat-of-the-triumvirate"] = {
            "seat-of-the-triumvirate",
            "the-seat-of-the-triumvirate",
            "sitz-des-triumvirats",
            "der-sitz-des-triumvirats",
        },
        ["skyreach"] = {
            "skyreach",
            "himmelsnadel",
            "die-himmelsnadel",
        },
        ["pit-of-saron"] = {
            "pit-of-saron",
            "grube-von-saron",
            "die-grube-von-saron",
        },
        ["algethar-academy"] = {
            "algethar-academy",
            "algeth-ar-academy",
            "akademie-von-algeth-ar",
        },
    },
}
