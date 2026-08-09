---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3101,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "kystia_manaheart", name = "Kystia Manaheart", zhCN = "凯斯媞亚·魔力之心" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
