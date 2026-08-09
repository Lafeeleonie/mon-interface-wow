---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3333,
    dungeon = { key = "nexus_point_xenas", name = "Nexus-Point Xenas", zhCN = "节点希纳斯" },
    boss = { key = "lothraxion", name = "Lothraxion", zhCN = "洛萨克森" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

