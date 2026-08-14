local _, Addon = ...

Addon.Data.RAIDS = {
    -- Midnight raid buttons use the same top-left-biased Encounter Journal art
    -- and corrected circular crop as the dungeon catalog.
    midnightIconTexCoord = { 0.00, 0.78, 0.00, 0.78 },
    contentTypes = {
        raid = { key = "raid", labelKey = "RAID_JOURNAL_TYPE_RAID" },
        lair = { key = "lair", labelKey = "RAID_JOURNAL_TYPE_LAIR" },
    },
    instanceContentTypes = {
        byInstanceID = {
            [1317] = "lair", -- Tidebound Grotto
            [1320] = "raid", -- The Venomous Abyss
        },
        byKey = {
            ["tidebound-grotto"] = "lair",
            ["tidebound-grotto-lair"] = "lair",
        },
    },
    -- Blizzard can omit instances from EJ_GetInstanceByIndex when the
    -- selected difficulty is not supported. Keep the Midnight catalog
    -- independent from that filter so Season 1 raids remain visible.
    journalInstanceIDs = {
        1317, -- The Tidebound Grotto
        1320, -- The Venomous Abyss
        1305, -- Sporefall
        1314, -- The Dreamrift
        1307, -- The Voidspire
        1308, -- March on Quel'Danas
    },
    difficultyOptions = {
        { key = "lfr", labelKey = "RAID_DIFFICULTY_LFR" },
        { key = "normal", labelKey = "RAID_DIFFICULTY_NORMAL" },
        { key = "heroic", labelKey = "RAID_DIFFICULTY_HEROIC" },
        { key = "mythic", labelKey = "RAID_DIFFICULTY_MYTHIC" },
    },
    difficultyIDs = {
        lfr = 17,
        normal = 14,
        heroic = 15,
        mythic = 16,
    },
    fallbackRaids = {
        { key = "the-venomous-abyss", icon = "Interface\\Icons\\Spell_Nature_Acid_01", contentType = "raid" },
        { key = "tidebound-grotto", icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2", contentType = "lair" },
        { key = "dreamrift", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
        { key = "voidspire", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
        { key = "march-on-quel-danas", icon = "Interface\\Icons\\INV_Misc_Map_01" },
        { key = "sporefall", icon = "Interface\\Icons\\INV_Mushroom_11" },
    },
}
