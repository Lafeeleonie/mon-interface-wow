---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3059,
    dungeon = { key = "windrunner_spire", name = "Windrunner Spire", zhCN = "风行者之塔" },
    boss = { key = "restless_heart", name = "Restless Heart", zhCN = "无眠之心" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

