---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3105,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "lithiel_cinderfury", name = "Lithiel Cinderfury", zhCN = "利希尔·烬怒" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
