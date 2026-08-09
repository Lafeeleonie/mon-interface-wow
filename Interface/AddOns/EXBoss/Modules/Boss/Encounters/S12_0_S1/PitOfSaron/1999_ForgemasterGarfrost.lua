---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 1999,
    dungeon = { key = "pit_of_saron", name = "Pit of Saron", zhCN = "萨隆矿坑" },
    boss = { key = "forgemaster_garfrost", name = "Forgemaster Garfrost", zhCN = "熔炉之主加弗斯特" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

