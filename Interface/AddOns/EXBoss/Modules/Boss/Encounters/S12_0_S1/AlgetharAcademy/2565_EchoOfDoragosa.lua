---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2565,
    dungeon = { key = "algethar_academy", name = "Algeth'ar Academy", zhCN = "艾杰斯亚学院" },
    boss = { key = "echo_of_doragosa", name = "Echo of Doragosa", zhCN = "多拉苟萨的回响" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

