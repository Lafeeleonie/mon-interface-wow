local _, Addon = ...

Addon.Data.PVP_WEEKLY = {
    pools = {
        {
            key = "rotating",
            labelKey = "PVP_WEEKLY_ROTATING",
            quests = {
                { id = 93502, titleKey = "PVP_WEEKLY_ROTATING_SOLO", fallbackTitle = "Veiled Solo" },
                { id = 93505, titleKey = "PVP_WEEKLY_ROTATING_WAR", fallbackTitle = "Veiled War" },
                { id = 93503, titleKey = "PVP_WEEKLY_ROTATING_TEAMWORK", fallbackTitle = "Veiled Cooperation" },
                { id = 93499, titleKey = "PVP_WEEKLY_ROTATING_ARENAS", fallbackTitle = "Veiled Arenas" },
                { id = 93506, titleKey = "PVP_WEEKLY_BATTLEGROUND_QUEST", fallbackTitle = "Veiled Battle" },
                { id = 93504, titleKey = "PVP_WEEKLY_BATTLEGROUND_SKIRMISH_QUEST", fallbackTitle = "Veiled Skirmish" },
            },
        },
        {
            key = "warmode",
            labelKey = "PVP_WEEKLY_WARMODE",
            quests = {
                { id = 93425, fallbackTitle = "Sparks of War: Harandar" },
                { id = 93423, fallbackTitle = "Sparks of War: Eversong Woods" },
                { id = 93426, fallbackTitle = "Sparks of War: Voidstorm" },
                { id = 93424, fallbackTitle = "Sparks of War: Zul'Aman" },
                { id = 96725, fallbackTitle = "Sparks of War: Val" },
                { id = 96726, fallbackTitle = "Sparks of War: Naigtal" },
            },
        },
        {
            key = "brawl",
            labelKey = "PVP_WEEKLY_BRAWL",
            quests = {
                { id = 47148, titleKey = "PVP_WEEKLY_BRAWL_QUEST", fallbackTitle = "Something Different" },
            },
        },
    },
}
