---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 1701,
    dungeon = { key = "skyreach", name = "Skyreach", zhCN = "通天峰" },
    boss = { key = "high_sage_viryx", name = "High Sage Viryx", zhCN = "高阶贤者维里克斯" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

