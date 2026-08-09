---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2563,
    dungeon = { key = "algethar_academy", name = "Algeth'ar Academy", zhCN = "艾杰斯亚学院" },
    boss = { key = "overgrown_ancient", name = "Overgrown Ancient", zhCN = "茂林古树" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
