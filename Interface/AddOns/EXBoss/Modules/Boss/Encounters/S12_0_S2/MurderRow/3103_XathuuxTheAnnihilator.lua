---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3103,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "xathuux_the_annihilator", name = "Xathuux the Annihilator", zhCN = "歼灭者萨祖克斯" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
