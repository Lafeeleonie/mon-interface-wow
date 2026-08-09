---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3072,
    dungeon = { key = "magisters_terrace", name = "Magister's Terrace", zhCN = "魔导师平台" },
    boss = { key = "selanar_sunlash", name = "Selanar Sunlash", zhCN = "瑟拉奈尔·日鞭" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

