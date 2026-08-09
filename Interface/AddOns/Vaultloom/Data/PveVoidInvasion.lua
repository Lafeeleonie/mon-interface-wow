local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_VOID_INVASION = {
    rowOrder = { "showdown", "disruption", "enemies", "world_boss" },
    zones = {
        {
            key = "val",
            name = "Val",
            mapID = 2599,
            rows = {
                showdown = { normal = 96713, heroic = 96714 },
                disruption = { normal = 97080, heroic = 97081 },
                enemies = { normal = 97082, heroic = 97083 },
                world_boss = { normal = 96295, heroic = 96941, task = true },
            },
        },
        {
            key = "naigtal",
            name = "Naigtal",
            mapID = 2600,
            rows = {
                showdown = { normal = 96717, heroic = 96718 },
                disruption = { normal = 97084, heroic = 97087 },
                enemies = { normal = 97085, heroic = 97086 },
                world_boss = { normal = 96522, heroic = 96942, task = true },
            },
        },
    },
}
