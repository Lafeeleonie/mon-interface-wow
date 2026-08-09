---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 1700,
    dungeon = { key = "skyreach", name = "Skyreach", zhCN = "通天峰" },
    boss = { key = "rukhran", name = "Rukhran", zhCN = "鲁克兰" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

