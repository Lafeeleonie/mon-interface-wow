local _, Addon = ...

Addon.Data.DUNGEONS = {
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
        { key = "season1", labelKey = "DUNGEONS_TAB_SEASON1", subtitleKey = "DUNGEON_JOURNAL_SEASON1_SUBTITLE" },
    },
    seasonalKeyGroups = {
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
