---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

do
    local active = false
    local f = CreateFrame("Frame")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            local encounterID = ...
            active = tonumber(encounterID) == 3073
            return
        end
        if event == "ENCOUNTER_END" then
            local encounterID = ...
            if tonumber(encounterID) == 3073 then
                active = false
            end
            return
        end
        if event ~= "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" or not active then
            return
        end
    end)
end

R:Register({
    encounterID = 3073,
    dungeon = { key = "magisters_terrace", name = "Magister's Terrace", zhCN = "魔导师平台" },
    boss = { key = "gemellus", name = "Gemellus", zhCN = "吉美尔鲁斯" },
    healthThresholds = {
        {
            unit = "boss1",
            threshold = 50,
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
