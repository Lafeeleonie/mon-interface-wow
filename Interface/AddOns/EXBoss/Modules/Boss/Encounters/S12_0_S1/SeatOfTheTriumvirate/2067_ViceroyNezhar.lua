---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2067,
    dungeon = { key = "seat_of_the_triumvirate", name = "Seat of the Triumvirate", zhCN = "执政团之座" },
    boss = { key = "viceroy_nezhar", name = "Viceroy Nezhar", zhCN = "总督奈扎尔" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

