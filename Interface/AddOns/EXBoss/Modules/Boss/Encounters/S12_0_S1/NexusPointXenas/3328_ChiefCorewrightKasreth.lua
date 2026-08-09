---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3328,
    dungeon = { key = "nexus_point_xenas", name = "Nexus-Point Xenas", zhCN = "节点希纳斯" },
    boss = { key = "chief_corewright_kasreth", name = "Chief Corewright Kasreth", zhCN = "核技工程长卡斯雷瑟" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})

