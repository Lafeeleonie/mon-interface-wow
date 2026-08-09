local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_DAILY = {
    wantedHarandar = {
        questPool = { 92012, 92013, 91980, 91970, 91982, 92010, 91998 },
        npc = "Shul'ka Li'tya",
        area = "Harandar",
        waypoint = {
            mapIDs = { 2413 },
            x = 52,
            y = 74,
        },
    },
    decorDuelQuestID = 93870,
    bountiful = {
        minimumLevel = 90,
        cap = 4,
        knownPois = {
            { mapID = 2424, poiID = 8428 },
            { mapID = 2395, poiID = 8438 },
            { mapID = 2437, poiID = 8444 },
            { mapID = 2437, poiID = 8442 },
            { mapID = 2405, poiID = 8432 },
            { mapID = 2405, poiID = 8430 },
            { mapID = 2413, poiID = 8436 },
            { mapID = 2413, poiID = 8434 },
            { mapID = 2393, poiID = 8426 },
            { mapID = 2393, poiID = 8440 },
        },
        knownDelveMapIDs = {
            2535, 2502, 2545, 2547, 2525, 2504, 2510, 2505, 2528, 2571, 2506,
        },
        safetyMapIDs = {
            2274, 2339, 2535, 2502, 2545, 2547, 2525, 2504, 2510, 2505,
            2528, 2571, 2506, 2248, 2214, 2215, 2216, 2213, 2255,
        },
    },
}
