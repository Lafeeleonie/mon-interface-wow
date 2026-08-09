---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2066,
    dungeon = { key = "seat_of_the_triumvirate", name = "Seat of the Triumvirate", zhCN = "执政团之座" },
    boss = { key = "saprish", name = "Saprish", zhCN = "萨普瑞什" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {
        dogJump = {
            enabled = true,
        },
    },
})

