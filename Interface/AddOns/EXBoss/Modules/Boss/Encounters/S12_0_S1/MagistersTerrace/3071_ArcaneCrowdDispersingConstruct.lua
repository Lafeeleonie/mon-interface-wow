---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3071,
    dungeon = { key = "magisters_terrace", name = "Magister's Terrace", zhCN = "魔导师平台" },
    boss = { key = "arcane_crowd_dispersing_construct", name = "Arcane Crowd Dispersing Construct", zhCN = "奥术人群驱散构造体" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

