---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2124,
    dungeon = { key = "temple_of_sethraliss", name = "Temple of Sethraliss", zhCN = "塞塔里斯神庙" },
    boss = { key = "adderis_and_aspix", name = "Adderis and Aspix", zhCN = "阿德里斯和阿斯匹克斯" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
