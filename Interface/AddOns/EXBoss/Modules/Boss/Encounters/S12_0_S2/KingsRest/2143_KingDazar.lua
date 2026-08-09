---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2143,
    dungeon = { key = "kings_rest", name = "Kings' Rest", zhCN = "诸王之眠" },
    boss = { key = "king_dazar", name = "King Dazar", zhCN = "达萨大王" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
