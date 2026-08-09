local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_WORLD = {
    worldBossQuestIDs = {
        92034,
        92123,
        92560,
        92636,
    },
    worldBossNamePatterns = {
        "thorm",
        "crag",
        "lu'ashal",
        "predax",
    },
    specialAssignments = {
        { questID = 92145, unlockQuestID = 92848 },
        { questID = 92063, unlockQuestID = 94390 },
        { questID = 93013, unlockQuestID = 94391 },
        { questID = 93438, unlockQuestID = 94743 },
        { questID = 93244, unlockQuestID = 94795 },
        { questID = 91390, unlockQuestID = 94865 },
        { questID = 91796, unlockQuestID = 94866 },
        { questID = 92139, unlockQuestID = 95435 },
    },
    keyShardCurrencyIDs = { 3310 },
    keyShardCap = 600,
    dundunCurrencyIDs = { 3376 },
    dundunCap = 8,
}
