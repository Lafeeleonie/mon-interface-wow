---@diagnostic disable: undefined-global

do
    local L = ExBoss and ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
    local ENCOUNTER_ID = 3332
    local EVENT_LIGHTFLARE = 34
    local VULNERABILITY_KEY = "nysarra:vulnerability"
    local PREPARE_SECONDS = 7.5
    local WATCH_LEAD_SECONDS = 2
    local WATCH_WINDOW_SECONDS = 4
    local TARGET_CHECK_DELAYS = { 0.1, 0.2, 0.3 }
    local ACTIVE_SECONDS = 17.9
    local watchFrame = nil
    local watchToken = 0
    local watchEndsAt = 0

    local function IsNysarraActive()
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.IsBossEncounter == true and tonumber(state.EncounterID) == ENCOUNTER_ID then
            return true
        end
        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
        return type(scheduler) == "table" and scheduler._running == true and
            tonumber(scheduler._encounterID) == ENCOUNTER_ID
    end

    local function SafeUnitHasSpellTarget(unit)
        if type(unit) ~= "string" then
            return nil, "bad-unit"
        end
        if type(UnitExists) == "function" then
            local ok, exists = pcall(UnitExists, unit .. "target")
            if ok then
                return exists == true, "unit-target"
            end
        end
        return nil, "unknown"
    end

    local function IsNysarraTrackedUnit(unit)
        if type(unit) ~= "string" or (unit ~= "target" and not unit:match("^nameplate%d+$")) then
            return false
        end
        if type(UnitLevel) ~= "function" then
            return false
        end
        local ok, level = pcall(UnitLevel, unit)
        return ok and tonumber(level) == 92
    end

    local function StopVulnerabilityWatch()
        watchToken = watchToken + 1
        watchEndsAt = 0
        if watchFrame then
            watchFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        end
    end

    local function StopVulnerabilityCountdowns()
        StopVulnerabilityWatch()
        if ExBoss and type(ExBoss.StopVulnerability) == "function" then
            ExBoss:StopVulnerability(VULNERABILITY_KEY)
        end
    end

    local function ShowVulnerabilityActiveFromChannel(token, unit)
        if token ~= watchToken then
            return
        end
        if not IsNysarraActive() then
            return
        end
        if watchEndsAt > 0 and (GetTime and GetTime() or 0) > watchEndsAt then
            StopVulnerabilityWatch()
            return
        end
        if not IsNysarraTrackedUnit(unit) then
            return
        end
        local hasTarget = SafeUnitHasSpellTarget(unit)
        if hasTarget ~= false then
            return
        end
        StopVulnerabilityWatch()
        if ExBoss and type(ExBoss.ShowVulnerabilityActive) == "function" then
            ExBoss:ShowVulnerabilityActive(L["易伤阶段"], ACTIVE_SECONDS, {
                key = VULNERABILITY_KEY,
            })
        end
    end

    local function EnsureWatchFrame()
        if watchFrame then
            return watchFrame
        end
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", function(_, _, unit)
            if not IsNysarraTrackedUnit(unit) then
                return
            end
            if watchEndsAt <= 0 or (GetTime and GetTime() or 0) > watchEndsAt then
                StopVulnerabilityWatch()
                return
            end
            local token = watchToken
            for i = 1, #TARGET_CHECK_DELAYS do
                local delay = TARGET_CHECK_DELAYS[i]
                C_Timer.After(delay, function()
                    ShowVulnerabilityActiveFromChannel(token, unit)
                end)
            end
        end)
        return watchFrame
    end

    local function StartVulnerabilityWatch()
        StopVulnerabilityWatch()
        watchEndsAt = (GetTime and GetTime() or 0) + WATCH_WINDOW_SECONDS
        local token = watchToken
        EnsureWatchFrame():RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        C_Timer.After(WATCH_WINDOW_SECONDS, function()
            if token == watchToken then
                StopVulnerabilityWatch()
            end
        end)
    end

    local function ScheduleVulnerabilityWatch()
        local token = watchToken
        local delay = math.max(0, PREPARE_SECONDS - WATCH_LEAD_SECONDS)
        C_Timer.After(delay, function()
            if token ~= watchToken or not IsNysarraActive() then
                return
            end
            StartVulnerabilityWatch()
        end)
    end

    local function OnFixedAIEventFinished(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(payload.eventID) ~= EVENT_LIGHTFLARE then
            return
        end
        if not IsNysarraActive() then
            return
        end
        if ExBoss and type(ExBoss.ShowVulnerabilityPrepare) == "function" then
            StopVulnerabilityCountdowns()
            ExBoss:ShowVulnerabilityPrepare(PREPARE_SECONDS, {
                key = VULNERABILITY_KEY,
            })
            ScheduleVulnerabilityWatch()
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_FINISHED", "ExBoss_Nysarra_Vulnerability",
            OnFixedAIEventFinished)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Nysarra_Vulnerability_Reset", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                StopVulnerabilityCountdowns()
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Nysarra_Vulnerability_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID or IsNysarraActive() then
                StopVulnerabilityCountdowns()
            end
        end)
        ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_Nysarra_Vulnerability_PEW", function()
            StopVulnerabilityCountdowns()
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3332,
    dungeon = { key = "nexus_point_xenas", name = "Nexus-Point Xenas", zhCN = "节点希纳斯" },
    boss = { key = "corewarden_nysarra", name = "Corewarden Nysarra", zhCN = "核心守卫奈萨拉" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
