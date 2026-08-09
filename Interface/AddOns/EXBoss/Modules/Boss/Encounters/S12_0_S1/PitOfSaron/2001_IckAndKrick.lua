---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2001,
    dungeon = { key = "pit_of_saron", name = "Pit of Saron", zhCN = "萨隆矿坑" },
    boss = { key = "ick_and_krick", name = "Ick and Krick", zhCN = "伊克和科瑞克" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

