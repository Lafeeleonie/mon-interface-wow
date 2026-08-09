---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 1699,
    dungeon = { key = "skyreach", name = "Skyreach", zhCN = "通天峰" },
    boss = { key = "araknath", name = "Araknath", zhCN = "阿拉卡纳斯" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

