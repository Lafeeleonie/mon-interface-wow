---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3457,
    dungeon = { key = "altar_of_fangs", name = "Altar of Fangs", zhCN = "毒牙祭坛" },
    boss = { key = "the_writhing_coil", name = "The Writhing Coil", zhCN = "扭缠盘蛇" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
