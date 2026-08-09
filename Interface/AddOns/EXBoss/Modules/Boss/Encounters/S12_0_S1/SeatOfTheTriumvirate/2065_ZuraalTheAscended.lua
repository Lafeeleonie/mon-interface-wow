---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2065,
    dungeon = { key = "seat_of_the_triumvirate", name = "Seat of the Triumvirate", zhCN = "执政团之座" },
    boss = { key = "zuraal_the_ascended", name = "Zuraal the Ascended", zhCN = "晋升者祖拉尔" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

