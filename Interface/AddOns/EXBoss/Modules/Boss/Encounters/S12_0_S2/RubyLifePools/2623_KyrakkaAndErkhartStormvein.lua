---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2623,
    dungeon = { key = "ruby_life_pools", name = "Ruby Life Pools", zhCN = "红玉新生法池" },
    boss = { key = "kyrakka_and_erkhart_stormvein", name = "Kyrakka and Erkhart Stormvein", zhCN = "基拉卡与厄克哈特·风脉" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
