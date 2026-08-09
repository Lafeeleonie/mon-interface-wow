---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2000,
    dungeon = { key = "pit_of_saron", name = "Pit of Saron", zhCN = "萨隆矿坑" },
    boss = { key = "scourgelord_tyrannus", name = "Scourgelord Tyrannus", zhCN = "天灾领主泰兰努斯" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

