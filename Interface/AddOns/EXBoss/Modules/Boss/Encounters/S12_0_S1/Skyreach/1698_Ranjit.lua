---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 1698,
    dungeon = { key = "skyreach", name = "Skyreach", zhCN = "通天峰" },
    boss = { key = "ranjit", name = "Ranjit", zhCN = "兰吉特" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

