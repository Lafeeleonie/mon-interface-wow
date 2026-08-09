local _, Addon = ...

Addon.Data.RAIDS = {
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
        { key = "dreamrift", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
        { key = "voidsreach-spire", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
        { key = "march-on-quel-danas", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    },
}
