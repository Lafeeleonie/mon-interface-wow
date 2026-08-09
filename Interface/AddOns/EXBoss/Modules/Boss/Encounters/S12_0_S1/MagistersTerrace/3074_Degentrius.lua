---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3074,
    dungeon = { key = "magisters_terrace", name = "Magister's Terrace", zhCN = "魔导师平台" },
    boss = { key = "degentrius", name = "Degentrius", zhCN = "迪詹崔乌斯" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

