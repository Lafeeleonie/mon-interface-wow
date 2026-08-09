---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2562,
    dungeon = { key = "algethar_academy", name = "Algeth'ar Academy", zhCN = "艾杰斯亚学院" },
    boss = { key = "vexamus", name = "Vexamus", zhCN = "维克萨姆斯" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
