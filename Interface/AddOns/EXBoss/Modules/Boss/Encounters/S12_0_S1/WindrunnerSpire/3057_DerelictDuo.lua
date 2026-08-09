---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3057,
    dungeon = { key = "windrunner_spire", name = "Windrunner Spire", zhCN = "风行者之塔" },
    boss = { key = "derelict_duo", name = "Derelict Duo", zhCN = "被遗弃的二人组" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

