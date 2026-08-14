local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_COILED_ISLE = {
    enabled = true,
    factionID = 2772,
    mapIDs = { 2512, 2509 },
    worldBoss = {
        key = "nymrissa_world",
        journalInstanceID = 1317,
        journalEncounterID = 2849,
        achievementID = 63683,
        bossKillEncounterIDs = { 3379, 2849 },
        fallbackName = "Nymrissa Wavecaller",
        -- Blizzard exposes Nymrissa's open-world tier through the primary
        -- Raid Finder difficulty. Difficulty 172 is not valid for this lair.
        difficultyIDs = { 17, 14, 15, 16 }, -- World/Raid Finder or higher
        resetType = "weekly",
    },
    activities = {
        { key = "turn_back_the_surge", questID = 96995, mapID = 2512, resetType = "weekly", fallbackName = "Turn Back the Surge" },
        { key = "purging_the_vaults", questID = 95520, mapID = 2509, resetType = "weekly", fallbackName = "Purging the Vaults" },
        { key = "patrolling_the_temple", questID = 96639, mapID = 2509, resetType = "daily", fallbackName = "Patrolling the Temple" },
        { key = "bounty_of_the_cursed", questID = 96640, mapID = 2509, resetType = "daily", fallbackName = "Bounty of the Cursed" },
        { key = "relentless_strikes", questID = 96641, mapID = 2509, resetType = "daily", fallbackName = "Relentless Strikes" },
        { key = "decisive_incursions", questID = 96642, mapID = 2509, resetType = "daily", fallbackName = "Decisive Incursions" },
        { key = "from_whence_it_came", questID = 96643, mapID = 2509, resetType = "daily", fallbackName = "From Whence it Came" },
        { key = "essence_of_malice", questID = 96644, mapID = 2509, resetType = "daily", fallbackName = "Essence of Malice" },
        { key = "whats_out_there", questID = 98420, mapID = 2509, resetType = "daily", fallbackName = "What's Out There?" },
    },
}
