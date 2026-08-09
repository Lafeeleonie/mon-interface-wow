---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3058,
    dungeon = { key = "windrunner_spire", name = "Windrunner Spire", zhCN = "风行者之塔" },
    boss = { key = "commander_kroluk", name = "Commander Kroluk", zhCN = "指挥官克罗鲁科" },
    healthThresholds = {
        {
            unit = "boss1",
            threshold = 66,
            lead = 5,
            text = "转阶段 {lead}%",
            transitionText = "阶段转换",
            output = "central_medium",
        },
        {
            unit = "boss1",
            threshold = 33,
            lead = 5,
            text = "转阶段 {lead}%",
            transitionText = "阶段转换",
            output = "central_medium",
        },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
