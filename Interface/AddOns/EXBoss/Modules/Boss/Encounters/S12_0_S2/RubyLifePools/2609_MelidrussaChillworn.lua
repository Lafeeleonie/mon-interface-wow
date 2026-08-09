---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2609,
    dungeon = { key = "ruby_life_pools", name = "Ruby Life Pools", zhCN = "红玉新生法池" },
    boss = { key = "melidrussa_chillworn", name = "Melidrussa Chillworn", zhCN = "梅莉杜莎·寒妆" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
