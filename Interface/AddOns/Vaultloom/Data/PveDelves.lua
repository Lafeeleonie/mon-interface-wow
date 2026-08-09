local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_DELVES = {
    trovehuntersBountyItemID = 252415,
    trovehuntersBountyFlagQuestID = 86371,
    trovehuntersUnlockFactionID = 2722,
    trovehuntersUnlockRenown = 2,
    gildedStashSpellID = 1216211,
    gildedStashWidgetID = 7591,
    gildedStashFallbackMaximum = 4,
    weeklyDropQuestID = 93784,
    bonusRenownFlags = {
        { questID = 93821, factionID = 2710, fallbackName = "Silvermoon" },
        { questID = 93819, factionID = 2696, fallbackName = "Amani" },
        { questID = 93822, factionID = 2704, fallbackName = "Harandar" },
        { questID = 93820, factionID = 2699, fallbackName = "Singularity" },
    },
}
