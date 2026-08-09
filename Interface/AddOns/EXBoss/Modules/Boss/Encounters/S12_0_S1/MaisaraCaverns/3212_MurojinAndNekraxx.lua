---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3212,
    dungeon = { key = "maisara_caverns", name = "Maisara Caverns", zhCN = "迈萨拉洞窟" },
    boss = { key = "murojin_and_nekraxx", name = "Muro'jin and Nekraxx", zhCN = "姆罗金和内克拉克斯" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

