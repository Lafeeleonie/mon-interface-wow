---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3056,
    dungeon = { key = "windrunner_spire", name = "Windrunner Spire", zhCN = "风行者之塔" },
    boss = { key = "emberdawn", name = "Emberdawn", zhCN = "烬晓" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

