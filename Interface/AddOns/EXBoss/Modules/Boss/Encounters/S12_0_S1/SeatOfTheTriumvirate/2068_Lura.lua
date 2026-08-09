---@diagnostic disable: undefined-global

do
    local L = ExBoss and ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
    local ENCOUNTER_ID = 2068
    local EVENT_PREP = 253
    local EVENT_ACTIVE = 254
    local EVENT_ABYSSAL_LANCE = 100001
    local VULNERABILITY_KEY = "lura:vulnerability"
    local ABYSSAL_LANCE_KEY = "lura:abyssal-lance"
    local ABYSSAL_LANCE_INTERVAL = 16
    local AURA_SAMPLE_MIN_INDEX = 2
    local AURA_SAMPLE_MAX_INDEX = 5
    local AURA_SAMPLE_INTERVAL = 0.1
    local AURA_SAMPLE_DURATION = 7.5
    local AURA_SAMPLE_TOTAL_TICKS = math.floor((AURA_SAMPLE_DURATION / AURA_SAMPLE_INTERVAL) + 0.5)
    local ACTIVE_RESAMPLE_LEAD = 0.5
    local abyssalLanceToken = 0
    local abyssalLanceTimer = nil
    local auraSampleToken = 0
    local auraSampleTimer = nil
    local activeResampleTimer = nil
    local battleStartAt = nil

    local function CancelTimer(timer)
        if timer and type(timer.Cancel) == "function" then
            pcall(timer.Cancel, timer)
        end
    end

    local function ScheduleTimer(delay, fn)
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            return C_Timer.NewTimer(math.max(0.01, tonumber(delay) or 0.01), fn)
        end
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(math.max(0.01, tonumber(delay) or 0.01), fn)
        end
        return nil
    end

    local function IsLuraActive()
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.IsBossEncounter == true and tonumber(state.EncounterID) == ENCOUNTER_ID then
            return true
        end
        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
        return type(scheduler) == "table" and scheduler._running == true and
            tonumber(scheduler._encounterID) == ENCOUNTER_ID
    end

    local function StopVulnerabilityCountdowns()
        if ExBoss and type(ExBoss.StopVulnerability) == "function" then
            ExBoss:StopVulnerability(VULNERABILITY_KEY)
        end
    end

    local function StopAuraSampling()
        auraSampleToken = auraSampleToken + 1
        CancelTimer(auraSampleTimer)
        auraSampleTimer = nil
    end

    local function StopActiveResampleTrigger()
        CancelTimer(activeResampleTimer)
        activeResampleTimer = nil
    end

    local function SafeAuraInstanceID(aura)
        if type(aura) ~= "table" then
            return nil
        end
        local ok, value = pcall(function()
            return aura.auraInstanceID
        end)
        if ok then
            return tonumber(value)
        end
        return nil
    end

    local function CollectAuraSample(now, firstSeenOffsets)
        local currentIDs = {}
        local fn = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex or nil
        if not UnitExists("boss1") or type(fn) ~= "function" then
            return currentIDs
        end

        for index = AURA_SAMPLE_MIN_INDEX, AURA_SAMPLE_MAX_INDEX do
            local ok, aura = pcall(fn, "boss1", index)
            if ok and aura then
                local auraInstanceID = SafeAuraInstanceID(aura)
                if auraInstanceID then
                    currentIDs[auraInstanceID] = true
                    if firstSeenOffsets[auraInstanceID] == nil and battleStartAt then
                        firstSeenOffsets[auraInstanceID] = math.max(0, now - battleStartAt)
                    end
                end
            end
        end

        return currentIDs
    end

    local function StopAbyssalLanceCycle()
        abyssalLanceToken = abyssalLanceToken + 1
        CancelTimer(abyssalLanceTimer)
        abyssalLanceTimer = nil

        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
        if scheduler and type(scheduler.CancelFixedAIVirtualEvents) == "function" then
            scheduler:CancelFixedAIVirtualEvents(ABYSSAL_LANCE_KEY)
        end
    end

    local function ScheduleAbyssalLanceCallback(delay, fn)
        CancelTimer(abyssalLanceTimer)
        abyssalLanceTimer = ScheduleTimer(delay, fn)
    end

    local function StartAbyssalLanceCycle(startOffset)
        StopAbyssalLanceCycle()
        if not battleStartAt then
            return
        end

        local token = abyssalLanceToken
        local nextCastAt = battleStartAt + math.max(0, tonumber(startOffset) or 0) + ABYSSAL_LANCE_INTERVAL
        local now = GetTime()
        while nextCastAt <= now do
            nextCastAt = nextCastAt + ABYSSAL_LANCE_INTERVAL
        end

        local armNext
        armNext = function()
            if token ~= abyssalLanceToken or not IsLuraActive() then
                return
            end

            local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
            if not (scheduler and type(scheduler.ScheduleFixedAIVirtualEvent) == "function") then
                return
            end

            local delay = nextCastAt - GetTime()
            if delay <= 0 then
                while nextCastAt <= GetTime() do
                    nextCastAt = nextCastAt + ABYSSAL_LANCE_INTERVAL
                end
                delay = nextCastAt - GetTime()
            end

            local timerID = scheduler:ScheduleFixedAIVirtualEvent(EVENT_ABYSSAL_LANCE, delay, ABYSSAL_LANCE_KEY, {
                encounterID = ENCOUNTER_ID,
            })
            if not timerID then
                return
            end

            local currentCastAt = nextCastAt
            nextCastAt = nextCastAt + ABYSSAL_LANCE_INTERVAL
            ScheduleAbyssalLanceCallback(currentCastAt - GetTime(), armNext)
        end

        armNext()
    end

    local function FinalizeAuraSample(firstSeenOffsets, currentIDs)
        if not (battleStartAt and IsLuraActive()) then
            return
        end

        for auraInstanceID in pairs(firstSeenOffsets) do
            if currentIDs[auraInstanceID] ~= true then
                firstSeenOffsets[auraInstanceID] = nil
            end
        end

        local earliestOffset = nil
        local earliestAuraInstanceID = nil
        for auraInstanceID, offset in pairs(firstSeenOffsets) do
            if earliestOffset == nil
                or offset < earliestOffset
                or (offset == earliestOffset and (earliestAuraInstanceID == nil or auraInstanceID < earliestAuraInstanceID)) then
                earliestOffset = offset
                earliestAuraInstanceID = auraInstanceID
            end
        end

        if earliestOffset ~= nil then
            StartAbyssalLanceCycle(earliestOffset)
        end
    end

    local function StartAuraSampling(reason)
        if not battleStartAt then
            return
        end

        StopAuraSampling()

        local token = auraSampleToken
        local sampleStartedAt = GetTime()
        local tick = 0
        local firstSeenOffsets = {}

        local sampleTick
        sampleTick = function()
            if token ~= auraSampleToken or not IsLuraActive() then
                return
            end

            tick = tick + 1
            local now = GetTime()
            local currentIDs = CollectAuraSample(now, firstSeenOffsets)
            if tick >= AURA_SAMPLE_TOTAL_TICKS then
                auraSampleTimer = nil
                FinalizeAuraSample(firstSeenOffsets, currentIDs)
                return
            end

            local nextAt = sampleStartedAt + (tick + 1) * AURA_SAMPLE_INTERVAL
            auraSampleTimer = ScheduleTimer(nextAt - GetTime(), sampleTick)
        end

        auraSampleTimer = ScheduleTimer(AURA_SAMPLE_INTERVAL, sampleTick)
    end

    local function ScheduleActiveResample(payload)
        StopActiveResampleTrigger()
        if not battleStartAt then
            return
        end

        local castTime = tonumber(type(payload) == "table" and payload.castTime or nil)
        if not castTime then
            return
        end

        local function beginSample()
            activeResampleTimer = nil
            if not IsLuraActive() then
                return
            end
            StartAuraSampling("event_active")
        end

        local delay = castTime - GetTime() - ACTIVE_RESAMPLE_LEAD
        if delay <= 0.01 then
            beginSample()
            return
        end
        activeResampleTimer = ScheduleTimer(delay, beginSample)
    end

    local function OnFixedAIEventScheduled(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if not IsLuraActive() then
            return
        end

        local eventID = tonumber(payload.eventID)
        if eventID == EVENT_PREP then
            StopAuraSampling()
            StopActiveResampleTrigger()
            StopAbyssalLanceCycle()
            if ExBoss and type(ExBoss.ShowVulnerabilityPrepare) == "function" then
                ExBoss:ShowVulnerabilityPrepare(11.5, {
                    key = VULNERABILITY_KEY,
                })
            end
        elseif eventID == EVENT_ACTIVE then
            if ExBoss and type(ExBoss.ShowVulnerabilityActive) == "function" then
                ExBoss:ShowVulnerabilityActive(L["易伤阶段"], 19.5, {
                    key = VULNERABILITY_KEY,
                })
            end
            ScheduleActiveResample(payload)
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_SCHEDULED", "ExBoss_Lura_Vulnerability", OnFixedAIEventScheduled)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Lura_Vulnerability_Reset", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                battleStartAt = GetTime()
                StopAuraSampling()
                StopActiveResampleTrigger()
                StopAbyssalLanceCycle()
                StopVulnerabilityCountdowns()
                StartAuraSampling("encounter_start")
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Lura_Vulnerability_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID or IsLuraActive() then
                battleStartAt = nil
                StopAuraSampling()
                StopActiveResampleTrigger()
                StopAbyssalLanceCycle()
                StopVulnerabilityCountdowns()
            end
        end)
        ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_Lura_Vulnerability_PEW", function()
            battleStartAt = nil
            StopAuraSampling()
            StopActiveResampleTrigger()
            StopAbyssalLanceCycle()
            StopVulnerabilityCountdowns()
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2068,
    dungeon = { key = "seat_of_the_triumvirate", name = "Seat of the Triumvirate", zhCN = "执政团之座" },
    boss = { key = "lura", name = "L'ura", zhCN = "鲁拉" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
