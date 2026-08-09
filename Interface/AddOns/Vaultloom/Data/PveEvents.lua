local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_EVENTS = {
    courtFavorQuestID = 89289,
    runestoneQuestPool = { 90573, 90574, 90575, 90576 },
    saltherilsFavorItemID = 238987,
    abundantOfferings = {
        questID = 89507,
        metaQuestID = 93890,
        continentMapID = 2537,
        poiMap = {
            [8672] = 2395,
            [8671] = 2437,
            [8676] = 2413,
            [8675] = 2405,
        },
    },
    lostLegends = {
        questID = 89268,
        relicQuestID = 92713,
        repeatableQuestPool = { 92716, 92719, 92720, 92721, 92722, 92724, 92725 },
        metaQuestID = 93891,
        mapIDs = { 2413 },
    },
    stormarionAssault = {
        questID = 90962,
        metaQuestID = 93892,
        mapIDs = { 2405 },
    },
    voidAssaultQuestPool = { 94386, 94385 },
}
