---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/Scheduler.lua
-- 战斗计时引擎（auto + fixed + blizzard）
-- 调度器，负责根据当前战斗和配置调度计时事件的创建、更新和销毁。
-- =============================================================

ExBoss.Timeline.Scheduler                          = ExBoss.Timeline.Scheduler or {}
local Scheduler                                    = ExBoss.Timeline.Scheduler
local TimelinePresentation                         = ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and
    ExBoss.Modules.Boss.TimelinePresentation
local TrashRuntimeConfig                           = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.RuntimeConfig or nil

local ONUPDATE_INTERVAL                            = 0.05
local MAX_ENCOUNTER_DURATION                       = 600
local BUNBAR_LEAD_TIME                             = 30
local TIMERBAR_LEAD_TIME                           = 30
local DEFAULT_PREALERT_SECS                        = 5
local VIRTUAL_HINT_REMAINING_SECS                  = 5
local FIXED_DRIVER_TIME                            = "time"
local FIXED_DRIVER_AI                              = "ai"
local FIXED_AI_MATCH_TOLERANCE                     = 0.75
local FIXED_AI_SYNC_WINDOW                         = 0.5
local FIXED_AI_CANCELED_RESUME_WINDOW              = 5
local FIXED_AI_CANCELED_RESUME_TOLERANCE           = 0.35
local FIXED_AI_FINISHED_TRIGGER_GRACE              = 0.5
local FIXED_AI_TIMELINE_FINISH_TIMEOUT             = 8
local FIXED_TIME_MATCH_TOLERANCE                   = 2.0
local FIXED_TIME_OFFSET_EPSILON                    = 0.02
local FIXED_TIME_OFFSET_CALIBRATION_ENABLED        = false
local TIMELINE_ADDED_CONFIRM_DELAY                 = 0.20
local TIMELINE_MAX_EVENT_DURATION                  = 120
local TIMELINE_DURATION_KEY_SCALE                  = 10
local FIXED_AI_EVENT_SCHEDULED_EVENT               = "EXBOSS_FIXED_AI_EVENT_SCHEDULED"
local FIXED_AI_EVENT_FINISHED_EVENT                = "EXBOSS_FIXED_AI_EVENT_FINISHED"
local TIMER_FIVE_SEC_REMAINING_EVENT               = "EXBOSS_TIMER_FIVE_SEC_REMAINING"
local TRASH_CASTBAR_STOP_EVENT                     = "EXBOSS_TRASH_CASTBAR_STOP"
local TRASH_OBSERVED_CAST_START_EVENT             = "EXBOSS_TRASH_OBSERVED_CAST_START"
local TRASH_CAST_START_VOICE_TRIGGERED_EVENT      = "EXBOSS_TRASH_CAST_START_VOICE_TRIGGERED"
local BOSS_OBSERVED_CAST_START_EVENT               = "EXBOSS_BOSS_OBSERVED_CAST_START"
local BOSS_OBSERVED_CAST_STOP_EVENT                = "EXBOSS_BOSS_OBSERVED_CAST_STOP"
local TIMER_FIVE_SEC_REMAINING_THRESHOLD           = 5
local BOSS_CAST_OBSERVE_LEAD                       = 0.10
local BOSS_CAST_OBSERVE_RECENT_KEEP                = 0.35
local BOSS_CAST_OBSERVE_MIN_WINDOW_AFTER           = 0.25
local BOSS_NAMEPLATE_LEVEL                         = 92
-- 施法条对应BOSS
local SPECIAL_BOSS_OBSERVE_UNIT_FILTERS            = {
    [3057] = {
        [29] = "boss2",
        [28] = "boss2",
        [25] = "boss2",
        [27] = "boss1",
        [26] = "boss1",
    },
    [2001] = {
        [204] = "boss1",
        [206] = "boss2",
        [205] = "boss2",
        [203] = "boss1",
        [560] = "boss2",
    },
}
local SPECIAL_BOSS_STOP_EVENT_BY_UNIT_KIND         = {
    [3057] = {
        boss1 = {
            cast = 27,
            channel = 27,
        },
        boss2 = {
            cast = 29,
            channel = 29,
        },
    },
}
local MECHANIC_PREALERT_SECS                       = 5
local DOG_JUMP_ENCOUNTER_ID                        = 2066
local DOG_JUMP_EVENT_ID                            = 237
local FIXED_AI_REMOVED_SYNC_ENCOUNTERS             = {
    [2564] = true,
    [3056] = true,
    [2068] = true,
    [3332] = true,
    [3333] = true,
}
local BuildBossObservedCastEventPayload
local DispatchBossObservedCastEvent
local FIXED_AI_KEEP_AFTER_PAUSE_REMOVED_ENCOUNTERS = {
    [3073] = true,
}
local FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS       = {
    [3073] = true,
}
local TRIGGER_TIME                                 = "TIME"
local TRIGGER_AI                                   = "AI"
local TRIGGER_BLZ                                  = "BLZ"

local STATE_ACTIVE                                 = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Active or
    0
local STATE_PAUSED                                 = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Paused or
    1
local STATE_FINISHED                               = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState
    .Finished or 2
local STATE_CANCELED                               = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState
    .Canceled or 3
local TIMELINE_SOURCE_ENCOUNTER                    = Enum and Enum.EncounterTimelineEventSource and
    Enum.EncounterTimelineEventSource.Encounter or 0

Scheduler._active                                  = {}
Scheduler._nextTimerID                             = 1
Scheduler._elapsed                                 = 0
Scheduler._running                                 = false
Scheduler._frame                                   = nil
Scheduler._encounterID                             = nil
Scheduler._mode                                    = "fixed"
Scheduler._timelineEventToTimer                    = {}
Scheduler._timelineCountdownSpecByEventID          = {}
Scheduler._lastFired                               = {} -- 最近触发的 timer 快照（供 SpellInference 比对）
Scheduler._fixedDriver                             = FIXED_DRIVER_TIME
Scheduler._fixedAIDurationRules                    = nil
Scheduler._fixedAISkillByEventID                   = {}
Scheduler._fixedAIEventToTimer                     = {}
Scheduler._fixedAIPendingEvents                    = {}
Scheduler._fixedAICanceledResumeSnapshot           = nil
Scheduler._fixedAISequenceCounters                 = {}
Scheduler._fixedAIPreEventLimitCounts              = {}
Scheduler._occurrenceCounts                        = {}
Scheduler._fixedTimeOffset                         = 0
Scheduler._fixedTimeEventToTimer                   = {}
Scheduler._lastEncounterStartAt                    = 0
Scheduler._lastEncounterStartID                    = nil
Scheduler._lastEncounterEndAt                      = 0
Scheduler._suppressBlizzardTimeline                = false
Scheduler._ignoreTimelineRecoveryUntil             = 0
Scheduler._acceptedTimelineEventIDs                = {}
Scheduler._timelineAddedPending                    = {}
Scheduler._eventActionsByEventID                   = {}
Scheduler._fixedAISyncCycleLimits                  = {}
Scheduler._fixedAISyncCycleCounts                  = {}
Scheduler._sessionToken                            = 0
Scheduler._blizzardHintSessionEnabled              = false
Scheduler._debugFixedAIPauseAll                    = false
Scheduler._bossCastObservePending                  = {}
Scheduler._bossCastObservePendingByTimerID         = {}
Scheduler._bossCastObserveNextID                   = 1
Scheduler._bossCastObserveRecentStarts             = {}
Scheduler._bossCastObserveNextStartID              = 1
Scheduler._bossObservedRuntimes                    = {}
Scheduler._bossObservedRuntimeNextID               = 1
local MAX_LAST_FIRED                               = 30
local _colorResolveErrorLogged                     = false

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local function SafeToNumber(v)
    local ok, n = pcall(tonumber, v)
    if ok then
        return n
    end
    return nil
end

local function NormalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    unit = tostring(unit):lower()
    if unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return id
end

local function IsBossUnitToken(unit)
    unit = NormalizeUnitToken(unit)
    return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
end

local function IsLevel92HostileNameplateUnit(unit)
    unit = NormalizeUnitToken(unit)
    if not unit or not unit:match("^nameplate%d+$") then
        return false
    end
    if type(UnitExists) == "function" and not UnitExists(unit) then
        return false
    end
    if type(UnitCanAttack) == "function" and not UnitCanAttack("player", unit) then
        return false
    end
    local level = type(UnitLevel) == "function" and tonumber(UnitLevel(unit)) or nil
    return level == BOSS_NAMEPLATE_LEVEL
end

local function IsBossCastObserveUnit(unit)
    return IsBossUnitToken(unit) or IsLevel92HostileNameplateUnit(unit)
end

local function GetBossCastObserveUnitPriority(unit)
    if IsBossUnitToken(unit) then
        return 2
    end
    if IsLevel92HostileNameplateUnit(unit) then
        return 1
    end
    return 0
end

local function NormalizeObserveUnitText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function NormalizeObserveUnitFilter(value)
    if type(value) == "table" then
        local out = {}
        for i = 1, #value do
            local item = NormalizeObserveUnitText(value[i])
            if item then
                out[#out + 1] = item
            end
        end
        return (#out > 0) and out or nil
    end
    local text = NormalizeObserveUnitText(value)
    if not text then
        return nil
    end
    if not text:find("[,|/;]") then
        return { text }
    end
    local out = {}
    for item in text:gmatch("[^,|/;]+") do
        item = NormalizeObserveUnitText(item)
        if item then
            out[#out + 1] = item
        end
    end
    return (#out > 0) and out or nil
end

local function BossObserveUnitFilterMatches(filterValue, entry)
    local filters = NormalizeObserveUnitFilter(filterValue)
    if not filters or type(entry) ~= "table" then
        return true
    end
    local unitToken = NormalizeUnitToken(entry.unit)
    for i = 1, #filters do
        local raw = filters[i]
        local token = NormalizeUnitToken(raw)
        local lowered = tostring(raw):lower()
        if token and unitToken == token then
            return true
        end
        if lowered == "boss" and IsBossUnitToken(unitToken) then
            return true
        end
        if lowered == "nameplate" and type(unitToken) == "string" and unitToken:match("^nameplate%d+$") then
            return true
        end
    end
    return false
end

local function GetSpecialBossObserveUnitFilter(encounterID, eventID)
    local encounterRow = SPECIAL_BOSS_OBSERVE_UNIT_FILTERS[tonumber(encounterID or 0)]
    if type(encounterRow) ~= "table" then
        return nil
    end
    local value = encounterRow[tonumber(eventID or 0)]
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        return DeepCopy(value)
    end
    return tostring(value)
end

local function GetSpecialBossStopEventID(encounterID, unit, castKind)
    local encounterRow = SPECIAL_BOSS_STOP_EVENT_BY_UNIT_KIND[tonumber(encounterID or 0)]
    if type(encounterRow) ~= "table" then
        return nil
    end
    local unitRow = encounterRow[NormalizeUnitToken(unit) or ""]
    if type(unitRow) ~= "table" then
        return nil
    end
    local eventID = unitRow[tostring(castKind or "")]
    return tonumber(eventID)
end

local function ComputeProgressPlanTotalDuration(plan)
    if type(plan) ~= "table" then
        return 0
    end
    local total = 0
    for i = 1, #plan do
        total = total + math.max(0.1, tonumber(type(plan[i]) == "table" and plan[i].duration or nil) or 0.1)
    end
    return total
end

local function IsAIVoiceDebugEnabled(scheduler, timer)
    local dbg = ExBoss and ExBoss.Debug and ExBoss.Debug.AIVoice
    if not (type(dbg) == "table" and dbg.enabled == true) then
        return false
    end
    local filter = SafeToNumber(dbg.encounterID)
    local encounterID = SafeToNumber(scheduler and scheduler._encounterID)
    if not encounterID and type(timer) == "table" then
        encounterID = SafeToNumber(timer.encounterID)
    end
    if filter and encounterID and filter ~= encounterID then
        return false
    end
    return true
end

local function AIVoiceDebugPrint(scheduler, timer, msg)
    if not IsAIVoiceDebugEnabled(scheduler, timer) then
        return
    end
    local dbg = ExBoss and ExBoss.Debug and ExBoss.Debug.AIVoice
    if type(dbg) == "table" then
        dbg.lines = (tonumber(dbg.lines) or 0) + 1
    end
    local prefix = "|cff33ff99ExBoss AIVoice|r "
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg or ""))
    else
        print(prefix .. tostring(msg or ""))
    end
end

local function IsCastBarDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true
end

local function CastBarDebugPrint(msg)
    if not IsCastBarDebugEnabled() then
        return
    end
    if ExBoss and ExBoss.Print and ExBoss.Print.Say then
        ExBoss.Print.Say("[CastBarDebug] " .. tostring(msg or ""))
    else
        print("|cff00ffff<EXBOSS>|r [CastBarDebug] " .. tostring(msg or ""))
    end
end

local function IsTrashVoiceDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TrashVoice and ExBoss.Debug.TrashVoice.enabled == true
end

local function TrashVoiceDebugPrint(msg)
    if not IsTrashVoiceDebugEnabled() then
        return
    end
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    if test and type(test.AppendExternalDebug) == "function" then
        test.AppendExternalDebug("TrashVoice", msg, true)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashVoice|r " .. tostring(msg or ""))
    end
end

local function IsTrackedCastBarEvent(timerOrEventID)
    local eventID = nil
    if type(timerOrEventID) == "table" then
        eventID = tonumber(timerOrEventID.eventID)
            or tonumber(timerOrEventID.timelineEventID)
            or tonumber(timerOrEventID.fixedAITimelineEventID)
    else
        eventID = tonumber(timerOrEventID)
    end
    return eventID == 145
end

local function CastBarEventDebugPrint(timerOrEventID, msg)
    if not IsTrackedCastBarEvent(timerOrEventID) then
        return
    end
    CastBarDebugPrint(msg)
end

local function AIVoiceTimerTimingText(timer)
    if type(timer) ~= "table" then
        return "now=0.00 cast=0.00 remain=0.00"
    end
    local now = GetTime and GetTime() or 0
    local castTime = SafeToNumber(timer.castTime) or 0
    return string.format("now=%.2f cast=%.2f remain=%.2f", now, castTime, castTime - now)
end

local function FixedAIMapDebugText(scheduler)
    if type(scheduler) ~= "table" then
        return "map=[] active=[]"
    end
    local mapParts = {}
    local map = type(scheduler._fixedAIEventToTimer) == "table" and scheduler._fixedAIEventToTimer or nil
    local active = type(scheduler._active) == "table" and scheduler._active or nil
    if map then
        local n = 0
        for timelineID, timerID in pairs(map) do
            n = n + 1
            if n <= 8 then
                local timer = active and active[timerID] or nil
                mapParts[#mapParts + 1] = string.format(
                    "%s->%s/e%s/r%.2f",
                    tostring(timelineID),
                    tostring(timerID),
                    tostring(timer and timer.eventID or ""),
                    (SafeToNumber(timer and timer.castTime) or 0) - (GetTime and GetTime() or 0)
                )
            end
        end
        if n > 8 then
            mapParts[#mapParts + 1] = "..."
        end
    end

    local activeParts = {}
    if active then
        local n = 0
        for timerID, timer in pairs(active) do
            if type(timer) == "table" and timer.source == "fixed_ai" then
                n = n + 1
                if n <= 8 then
                    activeParts[#activeParts + 1] = string.format(
                        "%s/e%s/tl%s/r%.2f",
                        tostring(timerID),
                        tostring(timer.eventID or ""),
                        tostring(timer.fixedAITimelineEventID or ""),
                        (SafeToNumber(timer.castTime) or 0) - (GetTime and GetTime() or 0)
                    )
                end
            end
        end
        if n > 8 then
            activeParts[#activeParts + 1] = "..."
        end
    end

    return string.format("map=[%s] active=[%s]", table.concat(mapParts, ","), table.concat(activeParts, ","))
end

local function IsEncounterTimelineSource(source)
    if source == nil then
        return true
    end
    local src = SafeToNumber(source)
    return src == nil or src == TIMELINE_SOURCE_ENCOUNTER
end

local function IsFixedTimeTestOverride(encounterID)
    local test = ExBoss and ExBoss.TestTimelineForceFixedTime
    if type(test) ~= "table" or test.active ~= true then
        return false
    end
    local expected = SafeToNumber(test.encounterID)
    local actual = SafeToNumber(encounterID)
    return expected ~= nil and actual ~= nil and expected == actual
end

local function IsTimelineDurationAllowed(duration)
    local d = SafeToNumber(duration)
    return d ~= nil and d >= 0 and d <= TIMELINE_MAX_EVENT_DURATION
end

local function BuildTimelineDurationKey(duration)
    local d = SafeToNumber(duration) or 0
    return tostring(math.floor((d * TIMELINE_DURATION_KEY_SCALE) + 0.5))
end

local function SafeNum(v, def)
    local n = SafeToNumber(v)
    if not n then return def end
    return n
end

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

local function IsDogJumpTimer(scheduler, timer)
    return tonumber(scheduler and scheduler._encounterID) == DOG_JUMP_ENCOUNTER_ID
        and tonumber(timer and (timer.eventID or timer.timelineEventID)) == DOG_JUMP_EVENT_ID
end

local function TryFireMechanicPreAlert(scheduler, timer, remaining)
    if type(timer) ~= "table" or timer.mechanicPreAlertFired == true then
        return
    end
    if not IsDogJumpTimer(scheduler, timer) then
        return
    end
    local r = tonumber(remaining)
    if not r or r > MECHANIC_PREALERT_SECS then
        return
    end
    timer.mechanicPreAlertFired = true
    local dispatcher = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Dispatcher
    if dispatcher and type(dispatcher.OnMechanicPreAlert) == "function" then
        dispatcher:OnMechanicPreAlert(timer, MECHANIC_PREALERT_SECS)
    end
end

local function PublishFixedAIEventScheduled(scheduler, timer, eventID, duration, observedAt, castTime, syncMode)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local now = GetTime()
    ExwindTools:SendEvent(FIXED_AI_EVENT_SCHEDULED_EVENT, {
        encounterID = scheduler and scheduler._encounterID or nil,
        eventID = SafeToNumber(eventID),
        timerID = SafeToNumber(timer and timer.id),
        duration = SafeToNumber(duration),
        observedAt = SafeToNumber(observedAt),
        castTime = SafeToNumber(castTime),
        remaining = math.max(0, (SafeToNumber(castTime) or now) - now),
        source = "fixed_ai",
        syncMode = syncMode == true,
        spellID = SafeToNumber(timer and timer.spellID),
        spellIdentifier = SafeToNumber(timer and timer.spellIdentifier),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
    })
    CastBarEventDebugPrint(eventID, string.format(
        "Scheduler scheduled event=%s timer=%s timeline=%s duration=%.2f observedAt=%.2f castTime=%.2f sync=%s name=%s",
        tostring(eventID),
        tostring(timer and timer.id or "nil"),
        tostring(timer and timer.fixedAITimelineEventID or "nil"),
        tonumber(duration) or 0,
        tonumber(observedAt) or 0,
        tonumber(castTime) or 0,
        tostring(syncMode == true),
        tostring(timer and (timer.displayName or timer.baseDisplayName) or "")
    ))
end

local function PublishFixedAIEventFinished(scheduler, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local now = GetTime()
    ExwindTools:SendEvent(FIXED_AI_EVENT_FINISHED_EVENT, {
        encounterID = scheduler and scheduler._encounterID or nil,
        eventID = SafeToNumber(timer and timer.eventID),
        timerID = SafeToNumber(timer and timer.id),
        timelineEventID = SafeToNumber(timer and timer.fixedAITimelineEventID),
        fireAt = now,
        source = "fixed_ai",
        finishSource = "blizzard_timeline",
        spellID = SafeToNumber(timer and timer.spellID),
        spellIdentifier = SafeToNumber(timer and timer.spellIdentifier),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
    })
end

local function AttachConditionTriggers(timer)
    local engine = ExBoss and ExBoss.Conditions and ExBoss.Conditions.Engine
    if engine and engine.AttachToTimer then
        pcall(engine.AttachToTimer, engine, timer)
    end
end

local function UpdateConditionTriggers(timer, now)
    local engine = ExBoss and ExBoss.Conditions and ExBoss.Conditions.Engine
    if engine and engine.UpdateTimer then
        pcall(engine.UpdateTimer, engine, timer, now)
    end
end

local function ExtractColorRGB(colorObj)
    if type(colorObj) ~= "table" then
        return nil
    end
    local r = tonumber(colorObj.r)
    local g = tonumber(colorObj.g)
    local b = tonumber(colorObj.b)
    local a = tonumber(colorObj.a) or 1
    if r and g and b then
        return { r = r, g = g, b = b, a = a }
    end
    if type(colorObj.GetRGB) == "function" then
        local ok, rr, gg, bb = pcall(colorObj.GetRGB, colorObj)
        if ok and tonumber(rr) and tonumber(gg) and tonumber(bb) then
            return { r = tonumber(rr), g = tonumber(gg), b = tonumber(bb), a = a }
        end
    end
    return nil
end

local function ResolveTimelineDisplayName(passthroughSpellName, eventID)
    if passthroughSpellName ~= nil then
        return passthroughSpellName
    end
    return "时间轴事件 " .. tostring(eventID)
end

local function BuildTimelineCountdownSpec(displayName, iconFileID, color)
    return {
        displayName = displayName,
        iconFileID = iconFileID,
        color = color,
        duration = 5,
        rawText = true,
        disableIconBorder = true,
    }
end

local function FixedAITimerDebugState(timer)
    if type(timer) ~= "table" then
        return "timer=nil"
    end
    return string.format(
        "timer=%s event=%s tl=%s fired=%s paused=%s wasPaused=%s keepAfterPauseRemoved=%s waitFinish=%s %s",
        tostring(timer.id),
        tostring(timer.eventID or ""),
        tostring(timer.fixedAITimelineEventID or ""),
        tostring(timer.castFired == true),
        tostring(timer.fixedAIPaused == true),
        tostring(timer.fixedAIWasPaused == true),
        tostring(timer.fixedAIKeepAfterPauseRemoved == true),
        tostring(timer.fixedAIWaitingTimelineFinish == true),
        AIVoiceTimerTimingText(timer)
    )
end

local function ApplyTrashTimelineMeta(timer, meta)
    if type(timer) ~= "table" or type(meta) ~= "table" then
        return
    end

    timer.trashMeta = meta
    timer.colorConfig = type(meta.colorConfig) == "table" and DeepCopy(meta.colorConfig) or timer.colorConfig
    timer.voicePlan = type(meta.voicePlan) == "table" and DeepCopy(meta.voicePlan) or timer.voicePlan
    local voiceLabel = type(meta.voiceLabel) == "string" and meta.voiceLabel or ""
    voiceLabel = voiceLabel:gsub("^%s+", ""):gsub("%s+$", "")
    if voiceLabel ~= "" then
        timer.voiceLabel = voiceLabel
    end

    local displayName = LocalizeDynamicText(meta.displayName or "")
    if displayName ~= "" then
        timer.baseDisplayName = displayName
        timer.displayName = displayName
        timer.timelineSpellName = displayName
    end

    local iconFileID = tonumber(meta.iconFileID)
    if iconFileID and iconFileID > 0 then
        timer.iconFileID = iconFileID
    end

    if type(meta.eventColor) == "table" then
        timer.eventColor = DeepCopy(meta.eventColor)
        timer.flashTextColor = DeepCopy(meta.eventColor)
    end

    local timerBarName = LocalizeDynamicText(meta.timerBarName or "")
    if timerBarName ~= "" then
        timer.timerBarName = timerBarName
    end

    timer.showBunBar = (meta.showBunBar ~= false)
    timer.showTimerBar = (meta.showTimerBar ~= false)
    timer.showNameplate = (meta.showNameplate == true)
    timer.nameplateSide = (tostring(meta.nameplateSide or "right") == "left") and "left" or "right"
    timer.progressDisplayName = LocalizeDynamicText(meta.progressDisplayName or "")
    timer.preferProgressSpellName = (meta.preferProgressSpellName == true)
    timer.ringEnabled = (meta.ringEnabled == true)
    timer.ringRenameEnabled = (meta.ringRenameEnabled == true)
    timer.ringRenameText = LocalizeDynamicText(meta.ringRenameText or "")
    timer.castProgressBarEnabled = (meta.castProgressBarEnabled == true)
    timer.castProgressBarRenameEnabled = (meta.castProgressBarRenameEnabled == true)
    timer.castProgressBarRenameText = LocalizeDynamicText(meta.castProgressBarRenameText or "")
    timer.ringCastCheckEnabled = (meta.ringCastCheckEnabled == true)
    timer.ringPlan = type(meta.ringPlan) == "table" and DeepCopy(meta.ringPlan) or nil

    timer.trashTimerBarHideAboveEnabled = meta.timerBarHideAboveEnabled == true
    timer.trashTimerBarHideAboveSeconds = math.max(0, tonumber(meta.timerBarHideAboveSeconds) or 0)
    if timer.trashTimerBarHideAboveEnabled == true then
        timer.timerBarDuration = timer.trashTimerBarHideAboveSeconds
    end
    timer.trashKeepTimerBarAfterReadyEnabled = meta.keepTimerBarAfterReadyEnabled == true
    timer.trashKeepTimerBarAfterReadySeconds = math.max(0, tonumber(meta.keepTimerBarAfterReadySeconds) or 0)
    timer.trashReadyAt = nil
    timer.countdownVoiceEnabled = (meta.countdownVoiceEnabled == true)
    timer.countdownPlayName = (meta.countdownPlayName == true)

    if meta.countdownEnabled == true then
        timer.countdownMode = "own"
        timer.useBlizzardHintCountdown = false
        timer.preAlertEnabled = true
        timer.preAlertFired = false
        timer.timelinePreAlertLead = tonumber(meta.countdownLead) or VIRTUAL_HINT_REMAINING_SECS
        timer.preAlertText = LocalizeDynamicText(meta.countdownText or displayName)
    else
        timer.useBlizzardHintCountdown = false
        timer.preAlertEnabled = false
        timer.preAlertText = nil
        timer.preAlertFired = true
        timer.timelinePreAlertLead = 0
        timer.countdownMode = "none"
    end

    if meta.centralEnabled == true then
        timer.centralMode = "own"
        timer.useBlizzardHintCentral = false
        timer.centralEnabled = true
        timer.centralFired = false
        timer.centralLead = tonumber(meta.centralLead) or 0
        timer.screenText = LocalizeDynamicText(meta.centralText or displayName)
    else
        timer.useBlizzardHintCentral = false
        timer.centralEnabled = false
        timer.centralFired = true
        timer.centralLead = 0
        timer.screenText = nil
        timer.centralMode = "none"
    end
end

local function IsRingProgressGloballyEnabled()
    local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if not (Ring and type(Ring.ShowSequence) == "function" and type(Ring.ShowEntry) == "function") then
        return false
    end
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, "ExBoss.RingProgress", { enabled = true })
        if ok and type(mdb) == "table" then
            db = mdb
        end
    end
    if type(db) ~= "table" then
        db = ExBossDB and ExBossDB.timer and ExBossDB.timer.ringProgress or nil
    end
    return type(db) == "table" and db.enabled == true
end

local function IsCastProgressBarGloballyEnabled()
    local CastBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
    if not (CastBar and type(CastBar.ShowSequence) == "function" and type(CastBar.ShowEntry) == "function") then
        return false
    end
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, "ExBoss.CastProgressBar", { enabled = true })
        if ok and type(mdb) == "table" then
            db = mdb
        end
    end
    if type(db) ~= "table" then
        db = ExBossDB and ExBossDB.timer and ExBossDB.timer.castProgressBar or nil
    end
    return type(db) == "table" and db.enabled == true
end

local function DoesTargetAlertWantObservedBossCast(timer)
    local runtime = ExBoss and ExBoss.TargetAlert or nil
    if runtime and type(runtime.ShouldObserveBossCast) == "function" then
        local ok, result = pcall(runtime.ShouldObserveBossCast, runtime, timer)
        return ok and result == true
    end
    return false
end

local function EnrichProgressPlan(plan, timer)
    if type(plan) ~= "table" or type(timer) ~= "table" then
        return plan
    end
    for i = 1, #plan do
        local phase = plan[i]
        if type(phase) == "table" then
            phase.displayName = phase.displayName or timer.displayName or timer.baseDisplayName
            phase.progressDisplayName = phase.progressDisplayName or timer.progressDisplayName
            phase.preferSpellName = timer.preferProgressSpellName == true
            phase.spellID = phase.spellID or timer.spellID or timer.spellIdentifier
            phase.iconFileID = phase.iconFileID or timer.iconFileID
            phase.ringRenameEnabled = timer.ringRenameEnabled == true
            phase.ringRenameText = tostring(timer.ringRenameText or "")
            phase.castBarRenameEnabled = timer.castProgressBarRenameEnabled == true
            phase.castBarRenameText = tostring(timer.castProgressBarRenameText or "")
        end
    end
    return plan
end

local function ShowProgressDisplays(plan, opts)
    opts = type(opts) == "table" and opts or {}
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end

    local shown = false
    if opts.ringEnabled ~= false and IsRingProgressGloballyEnabled() then
        local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        if #plan > 1 and Ring and type(Ring.ShowSequence) == "function" then
            Ring:ShowSequence(plan, {
                castCheckEnabled = opts.castCheckEnabled == true,
                owner = type(opts.owner) == "table" and opts.owner or nil,
            })
            shown = true
        elseif Ring and type(Ring.ShowEntry) == "function" then
            local row = DeepCopy(plan[1])
            row.owner = type(opts.owner) == "table" and opts.owner or nil
            Ring:ShowEntry(row)
            shown = true
        end
    end

    if opts.castProgressBarEnabled == true and IsCastProgressBarGloballyEnabled() then
        local CastBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        if #plan > 1 and CastBar and type(CastBar.ShowSequence) == "function" then
            CastBar:ShowSequence(plan, {
                castCheckEnabled = opts.castCheckEnabled == true,
                owner = type(opts.owner) == "table" and opts.owner or nil,
            })
            shown = true
        elseif CastBar and type(CastBar.ShowEntry) == "function" then
            local row = DeepCopy(plan[1])
            row.owner = type(opts.owner) == "table" and opts.owner or nil
            CastBar:ShowEntry(row)
            shown = true
        end
    end

    return shown
end

local function BuildTrashRingPlanForCurrentStart(timer, runtime)
    local rawPlan = type(timer) == "table" and type(timer.ringPlan) == "table" and timer.ringPlan or nil
    if not rawPlan or #rawPlan == 0 then
        return nil
    end
    local elapsed = 0
    if type(runtime) == "table" then
        local startAt = tonumber(runtime.activeCastStartAt)
        if startAt then
            elapsed = math.max(0, GetTime() - startAt)
        end
    end

    local out = {}
    for i = 1, #rawPlan do
        local phase = rawPlan[i]
        local duration = tonumber(phase and phase.duration) or 0
        if duration > 0 then
            if elapsed >= duration then
                elapsed = elapsed - duration
            else
                local row = DeepCopy(phase)
                row.duration = math.max(0.1, duration - elapsed)
                out[#out + 1] = row
                elapsed = 0
            end
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

local function BuildBossProgressPlanForCast(timer)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true then
        return nil
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return nil
    end

    local plan = {}
    local rawPlan = type(timer.ringPlan) == "table" and timer.ringPlan or nil
    if rawPlan and #rawPlan > 0 then
        for i = 1, #rawPlan do
            local phase = rawPlan[i]
            local duration = tonumber(type(phase) == "table" and phase.duration or nil)
            local castKind = tostring(type(phase) == "table" and phase.castKind or "")
            if duration and duration > 0 and (castKind == "cast" or castKind == "channel") then
                plan[#plan + 1] = DeepCopy(phase)
            end
        end
    end

    if #plan == 0 then
        local duration = tonumber(timer.ringChannelDuration)
        if duration and duration > 0 then
            plan[1] = {
                duration = duration,
                castKind = "channel",
            }
        end
    end

    if #plan == 0 then
        return nil
    end

    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = true
            end
        end
    end
    return plan, castCheckEnabled
end

local function BuildBossProgressPlanForSpecificKind(timer, wantedKind)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true then
        return nil
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return nil
    end

    local kind = tostring(wantedKind or "")
    local plan = {}
    local rawPlan = type(timer.ringPlan) == "table" and timer.ringPlan or nil
    if rawPlan and #rawPlan > 0 then
        for i = 1, #rawPlan do
            local phase = rawPlan[i]
            local duration = tonumber(type(phase) == "table" and phase.duration or nil)
            local phaseKind = tostring(type(phase) == "table" and phase.castKind or "")
            if duration and duration > 0 and phaseKind == kind then
                plan[#plan + 1] = DeepCopy(phase)
            end
        end
    end

    if #plan == 0 and kind == "channel" then
        local duration = tonumber(timer.ringChannelDuration)
        if duration and duration > 0 then
            plan[1] = {
                duration = duration,
                castKind = "channel",
            }
        end
    end

    if #plan == 0 then
        return nil
    end

    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = true
            end
        end
    end
    return plan, castCheckEnabled
end

local function BuildBossProgressPlanForObservedStart(timer, castKind)
    local kind = tostring(castKind or "")
    if kind == "channel" then
        return BuildBossProgressPlanForSpecificKind(timer, "channel")
    end

    local plan, castCheckEnabled = BuildBossProgressPlanForSpecificKind(timer, "cast")
    if type(plan) == "table" and #plan > 0 then
        return plan, castCheckEnabled
    end
    if kind == "cast" then
        local fullPlan, fullCastCheckEnabled = BuildBossProgressPlanForCast(timer)
        if type(fullPlan) == "table" and #fullPlan > 0 then
            return fullPlan, fullCastCheckEnabled
        end
    end
    return nil
end

local function PlayTrashObservedCastStartRing(runtime, timer, spellID)
    if type(runtime) ~= "table" or type(timer) ~= "table" then
        return false
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return false
    end
    if type(timer.ringPlan) ~= "table" or #timer.ringPlan == 0 then
        return false
    end
    if not IsRingProgressGloballyEnabled() and not IsCastProgressBarGloballyEnabled() then
        return false
    end

    runtime._trashCastStartRingKeys = runtime._trashCastStartRingKeys or {}
    local key = tostring(math.floor(tonumber(spellID) or 0)) ..
        ":" .. string.format("%.3f", tonumber(runtime.activeCastStartAt) or 0)
    if runtime._trashCastStartRingKeys[key] == true then
        return false
    end
    runtime._trashCastStartRingKeys[key] = true

    local plan = BuildTrashRingPlanForCurrentStart(timer, runtime)
    if not plan then
        return false
    end
    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = castCheckEnabled
            end
        end
    end
    return ShowProgressDisplays(plan, {
        castCheckEnabled = castCheckEnabled,
        ringEnabled = timer.ringEnabled == true,
        castProgressBarEnabled = timer.castProgressBarEnabled == true,
        owner = {
            source = "trash",
            runtime = runtime,
            castKind = tostring(runtime.activeCastKind or ""),
            castBarID = NormalizeCastBarID(runtime.activeCastBarID),
            earlyStopEnabled = true,
        },
    })
end

function Scheduler:ShowBossProgressFromTimer(timer)
    if type(timer) ~= "table" or timer.disabled then
        return false
    end
    if timer.trashMeta ~= nil or timer.trashRuntime ~= nil or timer.trashSpellData ~= nil then
        return false
    end
    local plan, castCheckEnabled = BuildBossProgressPlanForCast(timer)
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end
    CastBarDebugPrint(string.format(
        "Scheduler show-progress event=%s source=%s planCount=%d ringEnabled=%s castBarEnabled=%s",
        tostring(timer.eventID or timer.timelineEventID or "nil"),
        tostring(timer.source or "nil"),
        #plan,
        tostring(timer.ringEnabled == true),
        tostring(timer.castProgressBarEnabled == true)
    ))
    local useBossObserve = self:_ShouldUseBossCastObserve(timer)
    return ShowProgressDisplays(plan, {
        castCheckEnabled = castCheckEnabled == true,
        ringEnabled = timer.ringEnabled == true and not useBossObserve,
        castProgressBarEnabled = timer.castProgressBarEnabled == true and not useBossObserve,
    })
end

function Scheduler:ShowBossProgressFromObservedStart(timer, castKind, unit, _unitGUID, castBarID)
    if type(timer) ~= "table" or timer.disabled then
        return false
    end
    local targetAlertWanted = DoesTargetAlertWantObservedBossCast(timer)
    local ringEnabled = timer.ringEnabled == true and IsRingProgressGloballyEnabled()
    local castProgressBarEnabled = timer.castProgressBarEnabled == true and IsCastProgressBarGloballyEnabled()
    if ringEnabled ~= true and castProgressBarEnabled ~= true and targetAlertWanted ~= true then
        return false
    end

    local plan, castCheckEnabled = BuildBossProgressPlanForObservedStart(timer, castKind)
    if (type(plan) ~= "table" or #plan == 0) and targetAlertWanted ~= true then
        return false
    end

    if tostring(castKind or "") == "channel" then
        self:_HandleBossObservedChannelTransition(timer, unit, castBarID)
    end

    local observedDuration = (type(plan) == "table" and #plan > 0) and ComputeProgressPlanTotalDuration(plan) or 0
    if observedDuration <= 0.05 and type(timer) == "table" and tonumber(timer.castTime) then
        observedDuration = math.max(0, tonumber(timer.castTime) - GetTime())
    end

    local runtime = self:_CreateBossObservedRuntime(
        timer,
        castKind,
        unit,
        castBarID,
        observedDuration
    )

    local owner = {
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castKind = tostring(castKind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        encounterID = tonumber(timer.encounterID),
        eventID = tonumber(timer.eventID),
        runtime = runtime and runtime.id or nil,
        earlyStopEnabled = true,
    }

    CastBarDebugPrint(string.format(
        "Scheduler observed-progress event=%s source=%s kind=%s unit=%s castBarID=%s planCount=%d targetAlert=%s",
        tostring(timer.eventID or timer.timelineEventID or "nil"),
        tostring(timer.source or "nil"),
        tostring(castKind or "nil"),
        tostring(unit or "nil"),
        tostring(castBarID or "nil"),
        (type(plan) == "table" and #plan) or 0,
        tostring(targetAlertWanted == true)
    ))

    local shown = false
    if type(plan) == "table" and #plan > 0 then
        shown = ShowProgressDisplays(plan, {
            castCheckEnabled = castCheckEnabled == true,
            ringEnabled = ringEnabled == true,
            castProgressBarEnabled = castProgressBarEnabled == true,
            owner = owner,
        })
    end
    DispatchBossObservedCastEvent(BOSS_OBSERVED_CAST_START_EVENT, runtime)
    if shown ~= true and targetAlertWanted ~= true and runtime and runtime.id then
        self._bossObservedRuntimes[runtime.id] = nil
    end
    return shown == true or targetAlertWanted == true
end

function Scheduler:_ShouldUseBossCastObserve(timer)
    return type(timer) == "table"
        and timer.disabled ~= true
        and timer.source ~= "trash"
        and (
            (timer.useRingProgress == true and (timer.ringEnabled == true or timer.castProgressBarEnabled == true))
            or DoesTargetAlertWantObservedBossCast(timer)
        )
end

local function BuildBossCastObserveSnapshot(timer)
    if type(timer) ~= "table" then
        return nil
    end
    return DeepCopy(timer)
end

function Scheduler:_PruneBossObservedRuntimes(now)
    now = tonumber(now) or GetTime()
    for runtimeID, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) ~= "table" then
            self._bossObservedRuntimes[runtimeID] = nil
        else
            local expiresAt = tonumber(runtime.expiresAt) or 0
            if runtime.active ~= true or (expiresAt > 0 and now > expiresAt) then
                self._bossObservedRuntimes[runtimeID] = nil
            end
        end
    end
end

function Scheduler:_CreateBossObservedRuntime(timer, castKind, unit, castBarID, totalDuration)
    local runtimeID = tonumber(self._bossObservedRuntimeNextID) or 1
    self._bossObservedRuntimeNextID = runtimeID + 1

    local now = GetTime()
    local runtime = {
        id = runtimeID,
        encounterID = tonumber(timer and timer.encounterID) or tonumber(self._encounterID),
        eventID = tonumber(timer and timer.eventID),
        timerID = tonumber(timer and timer.id),
        castKind = tostring(castKind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        units = {},
        active = true,
        startedAt = now,
        totalDuration = math.max(0, tonumber(totalDuration) or 0),
        expiresAt = now + math.max(1.0, tonumber(totalDuration) or 0) + 2.0,
        timerSnapshot = BuildBossCastObserveSnapshot(timer),
    }

    local unitToken = NormalizeUnitToken(unit)
    if unitToken then
        runtime.units[unitToken] = true
        runtime.primaryUnit = unitToken
    end

    self._bossObservedRuntimes[runtimeID] = runtime
    return runtime
end

BuildBossObservedCastEventPayload = function(runtime)
    if type(runtime) ~= "table" then
        return nil
    end
    local timer = type(runtime.timerSnapshot) == "table" and runtime.timerSnapshot or nil
    local totalDuration = math.max(0, tonumber(runtime.totalDuration) or 0)
    if totalDuration <= 0.05 and type(timer) == "table" and tonumber(timer.castTime) and tonumber(runtime.startedAt) then
        totalDuration = math.max(0, tonumber(timer.castTime) - tonumber(runtime.startedAt))
    end
    return {
        runtimeID = tonumber(runtime.id),
        encounterID = tonumber(runtime.encounterID),
        eventID = tonumber(runtime.eventID),
        timerID = tonumber(runtime.timerID),
        spellID = tonumber(timer and (timer.spellID or timer.spellIdentifier) or nil),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
        progressDisplayName = tostring(timer and timer.progressDisplayName or ""),
        source = "boss",
        unit = NormalizeUnitToken(runtime.primaryUnit),
        castKind = tostring(runtime.castKind or ""),
        castBarID = NormalizeCastBarID(runtime.castBarID),
        startedAt = tonumber(runtime.startedAt) or 0,
        stoppedAt = tonumber(runtime.stoppedAt) or 0,
        totalDuration = totalDuration,
    }
end

DispatchBossObservedCastEvent = function(eventName, runtime)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local payload = BuildBossObservedCastEventPayload(runtime)
    if type(payload) ~= "table" then
        return
    end
    ExwindTools:SendEvent(eventName, payload)
end

local function ResolveTrashObservedCastDuration(runtime, timer)
    local castKind = tostring(type(runtime) == "table" and runtime.activeCastKind or "")
    if type(timer) == "table" and type(timer.ringPlan) == "table" then
        for i = 1, #timer.ringPlan do
            local item = timer.ringPlan[i]
            if type(item) == "table" and tonumber(item.duration) and tonumber(item.duration) > 0 then
                local itemKind = tostring(item.castKind or "")
                if itemKind == castKind then
                    return math.max(0, tonumber(item.duration) or 0)
                end
            end
        end
    end
    if type(timer) == "table" and tonumber(timer.castTime) and type(runtime) == "table" and tonumber(runtime.activeCastStartAt) then
        local remaining = tonumber(timer.castTime) - tonumber(runtime.activeCastStartAt)
        if remaining > 0.05 then
            return remaining
        end
    end
    return nil
end

local function DispatchTrashObservedCastStartEvent(runtime, spellID, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID) or tonumber(runtime.activeSpellID) or tonumber(runtime.activeObservedSpellID)
    if not sid then
        return
    end
    ExwindTools:SendEvent(TRASH_OBSERVED_CAST_START_EVENT, {
        source = "trash",
        runtime = runtime,
        runtimeKey = tostring(runtime),
        mapID = tonumber(runtime.matchedMapID),
        npcID = tonumber(runtime.matchedNPCID),
        spellID = sid,
        displayName = tostring(type(timer) == "table" and (timer.progressDisplayName or timer.displayName or timer.baseDisplayName) or sid),
        progressDisplayName = tostring(type(timer) == "table" and timer.progressDisplayName or ""),
        unit = tostring(runtime._nameplateUnit or runtime._debugUnit or ""),
        castKind = tostring(runtime.activeCastKind or ""),
        castBarID = NormalizeCastBarID(runtime.activeCastBarID),
        startedAt = tonumber(runtime.activeCastStartAt) or 0,
        totalDuration = ResolveTrashObservedCastDuration(runtime, timer),
    })
end

local function DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID) or tonumber(runtime.activeSpellID) or tonumber(runtime.activeObservedSpellID)
    if not sid then
        return
    end
    local seq = tonumber(runtime.activeCastSeq)
    local dedupeKey = tostring(seq or "nil") .. ":" .. tostring(sid)
    if runtime._targetAlertStartEventDedupeKey == dedupeKey then
        return
    end
    runtime._targetAlertStartEventDedupeKey = dedupeKey
    ExwindTools:SendEvent(TRASH_CAST_START_VOICE_TRIGGERED_EVENT, {
        source = "trash_voice_start",
        runtime = runtime,
        runtimeKey = tostring(runtime),
        mapID = tonumber(runtime.matchedMapID),
        npcID = tonumber(runtime.matchedNPCID),
        spellID = sid,
        displayName = tostring(type(timer) == "table" and (timer.progressDisplayName or timer.displayName or timer.baseDisplayName) or sid),
        progressDisplayName = tostring(type(timer) == "table" and timer.progressDisplayName or ""),
        unit = tostring(runtime._nameplateUnit or runtime._debugUnit or ""),
        castKind = tostring(runtime.activeCastKind or ""),
        castBarID = NormalizeCastBarID(runtime.activeCastBarID),
        startedAt = tonumber(runtime.activeCastStartAt) or 0,
        totalDuration = ResolveTrashObservedCastDuration(runtime, timer),
    })
end

function Scheduler:_FindBossObservedTransitionSource(timer, unit, nextCastBarID)
    local encounterID = tonumber(timer and timer.encounterID) or tonumber(self._encounterID)
    local eventID = tonumber(timer and timer.eventID)
    local unitToken = NormalizeUnitToken(unit)
    local normalizedNextCastBarID = NormalizeCastBarID(nextCastBarID)
    if not encounterID or not normalizedNextCastBarID then
        return nil
    end

    self:_PruneBossObservedRuntimes()

    local wantedPreviousCastBarID = normalizedNextCastBarID - 1
    local bestRuntime, bestScore = nil, nil
    for _, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) == "table"
            and runtime.active == true
            and tonumber(runtime.encounterID) == encounterID
            and tostring(runtime.castKind or "") == "cast"
            and NormalizeCastBarID(runtime.castBarID) == wantedPreviousCastBarID then
            local score = 0
            if eventID and tonumber(runtime.eventID) == eventID then
                score = score + 1000
            end
            if unitToken and type(runtime.units) == "table" and runtime.units[unitToken] == true then
                score = score + 100
            end
            if not bestScore or score > bestScore then
                bestScore = score
                bestRuntime = runtime
            end
        end
    end

    return bestRuntime
end

function Scheduler:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, specialEventID)
    local encounterID = tonumber(self._encounterID)
    if not encounterID then
        return nil
    end

    self:_PruneBossObservedRuntimes()

    local unitToken = NormalizeUnitToken(unit)
    local normalizedCastBarID = NormalizeCastBarID(castBarID)
    local wantedKind = tostring(castKind or "")
    local wantedEventID = tonumber(specialEventID)

    local bestRuntime, bestScore = nil, nil
    for _, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) == "table"
            and runtime.active == true
            and tonumber(runtime.encounterID) == encounterID
            and tostring(runtime.castKind or "") == wantedKind then
            local matches = true
            local score = 0
            if wantedEventID then
                if tonumber(runtime.eventID) ~= wantedEventID then
                    matches = false
                else
                    score = score + 1000
                end
            end

            if matches and normalizedCastBarID ~= nil then
                if NormalizeCastBarID(runtime.castBarID) == normalizedCastBarID then
                    score = score + 100
                elseif not wantedEventID then
                    matches = false
                end
            end

            if matches and unitToken and type(runtime.units) == "table" and runtime.units[unitToken] == true then
                score = score + 10
            end

            if matches and score > 0 and (not bestScore or score > bestScore) then
                bestScore = score
                bestRuntime = runtime
            end
        end
    end

    return bestRuntime
end

function Scheduler:_StopBossObservedRuntime(runtime)
    if type(runtime) ~= "table" or runtime.active ~= true then
        return false
    end
    runtime.active = false
    runtime.stoppedAt = GetTime()
    DispatchBossObservedCastEvent(BOSS_OBSERVED_CAST_STOP_EVENT, runtime)

    local owner = {
        source = "boss",
        runtime = runtime.id,
    }
    local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
    if castBar and type(castBar.StopByOwner) == "function" then
        castBar:StopByOwner(owner)
    end
    local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if ring and type(ring.StopByOwner) == "function" then
        ring:StopByOwner(owner)
    end
    self._bossObservedRuntimes[runtime.id] = nil
    return true
end

function Scheduler:_AttachBossObservedRuntimeUnitAlias(unit, castKind, castBarID)
    local unitToken = NormalizeUnitToken(unit)
    if not unitToken then
        return
    end
    local runtime = self:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, nil)
    if type(runtime) ~= "table" then
        return
    end
    runtime.units = type(runtime.units) == "table" and runtime.units or {}
    runtime.units[unitToken] = true
end

function Scheduler:_ResolveAndStopBossObservedRuntime(unit, castKind, castBarID, specialEventID)
    local runtime = self:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, specialEventID)
    if not runtime then
        return false
    end
    return self:_StopBossObservedRuntime(runtime)
end

function Scheduler:_HandleBossObservedChannelTransition(timer, unit, castBarID)
    local runtime = self:_FindBossObservedTransitionSource(timer, unit, castBarID)
    if not runtime then
        return false
    end
    return self:_StopBossObservedRuntime(runtime)
end

function Scheduler:_TryShowBossObservedChannelFromStart(unit, castBarID)
    local runtime = self:_FindBossObservedTransitionSource(nil, unit, castBarID)
    if type(runtime) ~= "table" then
        return false
    end
    local timer = (type(self._active) == "table" and self._active[tonumber(runtime.timerID)]) or runtime.timerSnapshot
    if type(timer) ~= "table" then
        return false
    end
    return self:ShowBossProgressFromObservedStart(timer, "channel", unit, nil, castBarID) == true
end

function Scheduler:_DropBossCastObservePending(pendingID)
    local id = tonumber(pendingID)
    if not id then
        return
    end
    local pending = self._bossCastObservePending and self._bossCastObservePending[id] or nil
    if not pending then
        return
    end
    self._bossCastObservePending[id] = nil
    local timerID = tonumber(pending.timerID)
    if timerID and self._bossCastObservePendingByTimerID[timerID] == id then
        self._bossCastObservePendingByTimerID[timerID] = nil
    end
end

function Scheduler:_DropBossCastObservePendingByTimerID(timerID)
    local id = tonumber(timerID)
    if not id then
        return
    end
    local pendingID = self._bossCastObservePendingByTimerID and self._bossCastObservePendingByTimerID[id] or nil
    if pendingID then
        self:_DropBossCastObservePending(pendingID)
    end
end

function Scheduler:_QueueBossCastObserveForTimer(timer, now)
    if not self:_ShouldUseBossCastObserve(timer) then
        return nil
    end
    local timerID = tonumber(timer and timer.id)
    local castTime = tonumber(timer and timer.castTime)
    if not timerID or not castTime then
        return nil
    end
    if self._bossCastObservePendingByTimerID[timerID] then
        return self._bossCastObservePendingByTimerID[timerID]
    end

    now = tonumber(now) or GetTime()
    local observeLead = math.max(0, tonumber(timer.castObserveLead) or BOSS_CAST_OBSERVE_LEAD)
    local windowAfter = math.max(BOSS_CAST_OBSERVE_MIN_WINDOW_AFTER, tonumber(timer.ringWindowAfter) or 2)
    local pendingID = tonumber(self._bossCastObserveNextID) or 1
    self._bossCastObserveNextID = pendingID + 1
    local pending = {
        id = pendingID,
        timerID = timerID,
        eventID = SafeToNumber(timer.eventID),
        expectedAt = castTime,
        observeStartAt = castTime - observeLead,
        observeEndAt = castTime + windowAfter,
        expectedKind = tostring(timer.castObserveExpectedKind or "any"),
        unitFilter = type(timer.castObserveUnitFilter) == "table" and DeepCopy(timer.castObserveUnitFilter)
            or tostring(timer.castObserveUnitFilter or ""),
        matchOrdinal = math.max(1, math.floor(tonumber(timer.castObserveOrdinal) or 1)),
        matchedCount = 0,
        sessionToken = tonumber(self._sessionToken) or 0,
        status = ((castTime - observeLead) <= now) and "active" or "queued",
        timerSnapshot = BuildBossCastObserveSnapshot(timer),
    }
    self._bossCastObservePending[pendingID] = pending
    self._bossCastObservePendingByTimerID[timerID] = pendingID
    CastBarDebugPrint(string.format(
        "Scheduler observe-queue timer=%s event=%s cast=%.2f start=%.2f end=%.2f ordinal=%d source=%s",
        tostring(timerID),
        tostring(timer.eventID or "nil"),
        tonumber(pending.expectedAt) or 0,
        tonumber(pending.observeStartAt) or 0,
        tonumber(pending.observeEndAt) or 0,
        tonumber(pending.matchOrdinal) or 1,
        tostring(timer.source or "nil")
    ))
    return pendingID
end

function Scheduler:_PruneBossCastObserveRecentStarts(now)
    now = tonumber(now) or GetTime()
    local keep = BOSS_CAST_OBSERVE_RECENT_KEEP
    for i = #self._bossCastObserveRecentStarts, 1, -1 do
        local entry = self._bossCastObserveRecentStarts[i]
        if type(entry) ~= "table" or (now - (tonumber(entry.at) or 0)) > keep then
            table.remove(self._bossCastObserveRecentStarts, i)
        end
    end
end

function Scheduler:_PendingAcceptsBossCastStart(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    if pending.status ~= "active" then
        return false
    end
    if (tonumber(pending.sessionToken) or 0) ~= (tonumber(self._sessionToken) or 0) then
        return false
    end
    local at = tonumber(entry.at) or 0
    if at < (tonumber(pending.observeStartAt) or 0) or at > (tonumber(pending.observeEndAt) or 0) then
        return false
    end
    local expectedKind = tostring(pending.expectedKind or "any")
    local actualKind = tostring(entry.kind or "")
    if expectedKind ~= "any" and expectedKind ~= "" and expectedKind ~= actualKind then
        return false
    end
    if not BossObserveUnitFilterMatches(pending.unitFilter, entry) then
        return false
    end
    return true
end

function Scheduler:_FindBestBossCastObservePending(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local bestPending = nil
    local bestDistance = math.huge
    for _, pending in pairs(self._bossCastObservePending or {}) do
        if self:_PendingAcceptsBossCastStart(pending, entry) then
            local distance = math.abs((tonumber(pending.expectedAt) or 0) - (tonumber(entry.at) or 0))
            if distance < bestDistance then
                bestDistance = distance
                bestPending = pending
            end
        end
    end
    return bestPending
end

function Scheduler:_MatchBossCastObservePending(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    local timer = (type(self._active) == "table" and self._active[tonumber(pending.timerID)]) or pending.timerSnapshot
    if type(timer) ~= "table" then
        self:_DropBossCastObservePending(pending.id)
        return false
    end

    pending.status = "matched"
    CastBarDebugPrint(string.format(
        "Scheduler observe-match timer=%s event=%s kind=%s unit=%s castBarID=%s count=%d/%d",
        tostring(pending.timerID),
        tostring(pending.eventID or "nil"),
        tostring(entry.kind or "nil"),
        tostring(entry.unit or "nil"),
        tostring(entry.castBarID or "nil"),
        tonumber(pending.matchedCount) or 0,
        tonumber(pending.matchOrdinal) or 1
    ))
    self:ShowBossProgressFromObservedStart(
        timer,
        entry.kind,
        entry.unit,
        nil,
        entry.castBarID
    )
    self:_DropBossCastObservePending(pending.id)
    return true
end

function Scheduler:_ConsumeBossCastObserveStart(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    if entry.assignedPendingID == pending.id then
        return false
    end
    if entry.assignedPendingID and entry.assignedPendingID ~= pending.id then
        return false
    end
    entry.assignedPendingID = pending.id
    pending.matchedCount = (tonumber(pending.matchedCount) or 0) + 1
    if pending.matchedCount >= (tonumber(pending.matchOrdinal) or 1) then
        return self:_MatchBossCastObservePending(pending, entry)
    end
    CastBarDebugPrint(string.format(
        "Scheduler observe-count timer=%s event=%s kind=%s unit=%s castBarID=%s count=%d/%d",
        tostring(pending.timerID),
        tostring(pending.eventID or "nil"),
        tostring(entry.kind or "nil"),
        tostring(entry.unit or "nil"),
        tostring(entry.castBarID or "nil"),
        tonumber(pending.matchedCount) or 0,
        tonumber(pending.matchOrdinal) or 1
    ))
    return true
end

function Scheduler:_ReplayBossCastObserveRecentStarts(pending, now)
    if type(pending) ~= "table" or pending.status ~= "active" then
        return
    end
    now = tonumber(now) or GetTime()
    for i = 1, #self._bossCastObserveRecentStarts do
        local entry = self._bossCastObserveRecentStarts[i]
        if type(entry) == "table"
            and not entry.assignedPendingID
            and (tonumber(entry.at) or 0) <= now
            and self:_PendingAcceptsBossCastStart(pending, entry) then
            if self:_ConsumeBossCastObserveStart(pending, entry) and pending.status == "matched" then
                return
            end
        end
    end
end

function Scheduler:_TickBossCastObserve(now)
    now = tonumber(now) or GetTime()
    self:_PruneBossCastObserveRecentStarts(now)
    self:_PruneBossObservedRuntimes(now)
    for pendingID, pending in pairs(self._bossCastObservePending or {}) do
        if type(pending) ~= "table" then
            self._bossCastObservePending[pendingID] = nil
        elseif (tonumber(pending.sessionToken) or 0) ~= (tonumber(self._sessionToken) or 0) then
            self:_DropBossCastObservePending(pendingID)
        elseif now > (tonumber(pending.observeEndAt) or 0) then
            CastBarDebugPrint(string.format(
                "Scheduler observe-expire timer=%s event=%s count=%d/%d",
                tostring(pending.timerID),
                tostring(pending.eventID or "nil"),
                tonumber(pending.matchedCount) or 0,
                tonumber(pending.matchOrdinal) or 1
            ))
            self:_DropBossCastObservePending(pendingID)
        elseif pending.status == "queued" and now >= (tonumber(pending.observeStartAt) or 0) then
            pending.status = "active"
            CastBarDebugPrint(string.format(
                "Scheduler observe-activate timer=%s event=%s start=%.2f end=%.2f",
                tostring(pending.timerID),
                tostring(pending.eventID or "nil"),
                tonumber(pending.observeStartAt) or 0,
                tonumber(pending.observeEndAt) or 0
            ))
            self:_ReplayBossCastObserveRecentStarts(pending, now)
        elseif pending.status == "active" then
            self:_ReplayBossCastObserveRecentStarts(pending, now)
        end
    end
end

function Scheduler:_RecordBossCastObserveStart(unit, kind, castBarID)
    if not (self._running and IsBossCastObserveUnit(unit)) then
        return
    end
    local unitToken = NormalizeUnitToken(unit)
    local now = GetTime()
    self:_PruneBossCastObserveRecentStarts(now)

    local entry = {
        id = tonumber(self._bossCastObserveNextStartID) or 1,
        unit = unitToken,
        kind = tostring(kind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        at = now,
        priority = GetBossCastObserveUnitPriority(unitToken),
        assignedPendingID = nil,
    }
    self._bossCastObserveNextStartID = entry.id + 1

    for i = #self._bossCastObserveRecentStarts, 1, -1 do
        local old = self._bossCastObserveRecentStarts[i]
        if type(old) == "table"
            and old.kind == entry.kind
            and old.castBarID ~= nil
            and entry.castBarID ~= nil
            and old.castBarID == entry.castBarID
            and math.abs((tonumber(old.at) or 0) - now) <= 0.05 then
            if entry.priority > (tonumber(old.priority) or 0) then
                old.unit = entry.unit
                old.priority = entry.priority
            end
            entry = old
            break
        end
    end

    if entry.id == (tonumber(self._bossCastObserveNextStartID) or 0) - 1 then
        self._bossCastObserveRecentStarts[#self._bossCastObserveRecentStarts + 1] = entry
    end

    local pending = self:_FindBestBossCastObservePending(entry)
    if pending then
        self:_ConsumeBossCastObserveStart(pending, entry)
    end
    if tostring(kind or "") == "channel" and not entry.assignedPendingID then
        self:_TryShowBossObservedChannelFromStart(unitToken, castBarID)
    end
    self:_AttachBossObservedRuntimeUnitAlias(unitToken, kind, castBarID)
end

local function ResolveTimerBarLeadTime(timer)
    if type(timer) == "table" and timer.trashTimerBarHideAboveEnabled == true then
        return math.max(0, tonumber(timer.trashTimerBarHideAboveSeconds) or 0)
    end
    local db = rawget(_G, "ExBossDB")
    local display = type(db) == "table" and type(db.timer) == "table" and type(db.timer.timerBar) == "table" and db.timer.timerBar
        or nil
    if type(display) == "table" and display.hideLongTimersEnabled == true then
        return math.max(0, tonumber(display.hideLongTimersSeconds) or 0)
    end
    return TIMERBAR_LEAD_TIME
end

local function ResolveTimerBarDisplayDuration(timer, now)
    local baseDuration = TIMERBAR_LEAD_TIME
    if type(timer) == "table" then
        baseDuration = math.max(1, tonumber(timer.timerBarDuration) or tonumber(timer.duration) or TIMERBAR_LEAD_TIME)
    end
    local leadTime = math.max(0, ResolveTimerBarLeadTime(timer))
    if leadTime <= 0 then
        return baseDuration
    end
    local remaining = math.max(1, tonumber(type(timer) == "table" and timer.castTime or 0) - tonumber(now or GetTime()))
    return math.max(1, math.min(baseDuration, leadTime, remaining))
end

local function ResolveBunBarLeadTime()
    local db = rawget(_G, "ExBossDB")
    local display = type(db) == "table" and type(db.timer) == "table" and type(db.timer.bunBar) == "table" and db.timer.bunBar
        or nil
    if type(display) == "table" and display.hideLongTimersEnabled == true then
        return math.max(0, tonumber(display.hideLongTimersSeconds) or 0)
    end
    return BUNBAR_LEAD_TIME
end

local function ResolveSpellIconFileID(spellIdentifier, fallbackSpellID, explicitIconFileID)
    local iconFileID = tonumber(explicitIconFileID)
    if iconFileID and iconFileID > 0 then
        return iconFileID
    end

    local sid = tonumber(spellIdentifier) or tonumber(fallbackSpellID)
    if not sid then
        return nil
    end

    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, icon = pcall(C_Spell.GetSpellTexture, sid)
        if ok and tonumber(icon) and tonumber(icon) > 0 then
            return tonumber(icon)
        end
    end

    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, sid)
        local icon = ok and type(info) == "table" and tonumber(info.iconID) or nil
        if icon and icon > 0 then
            return icon
        end
    end

    return nil
end

local function TimerDB()
    local tdb = nil
    if _G.EXBossData and _G.EXBossData.GetTimelineModeDB then
        tdb = _G.EXBossData.GetTimelineModeDB()
    else
        -- 兜底
        ExBossDB = ExBossDB or {}
        ExBossDB.timer = ExBossDB.timer or {}
        ExBossDB.timer.timelineMode = ExBossDB.timer.timelineMode or {}
        tdb = ExBossDB.timer.timelineMode
    end

    if type(tdb) ~= "table" then
        tdb = {}
    end
    if type(tdb.byEncounter) ~= "table" then tdb.byEncounter = {} end
    if type(tdb.default) ~= "string" or tdb.default == "" then tdb.default = "auto" end
    if type(tdb.fixedDriverByEncounter) ~= "table" then tdb.fixedDriverByEncounter = {} end
    if type(tdb.fixedDriverDefault) ~= "string" or tdb.fixedDriverDefault == "" then
        tdb.fixedDriverDefault = FIXED_DRIVER_TIME
    end
    return tdb
end

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
end

local function GetBarDisplayMode()
    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.general = ExBossDB.ui.general or {}
    local g = ExBossDB.ui.general
    g.barDisplayMode = NormalizeBarDisplayMode(g.barDisplayMode)
    return g.barDisplayMode
end

local function IsTimerBarEnabledByGlobal()
    local mode = GetBarDisplayMode()
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local mode = GetBarDisplayMode()
    return mode == "both" or mode == "bun"
end

local function IsBossSceneEnabledForCurrentInstance()
    local bossCfg = ExBoss and ExBoss.BossConfig
    if bossCfg and type(bossCfg.IsCurrentSceneEnabled) == "function" then
        local ok, enabled = pcall(bossCfg.IsCurrentSceneEnabled, bossCfg)
        if ok then
            return enabled ~= false
        end
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.general = ExBossDB.ui.general or {}
    local g = ExBossDB.ui.general
    if g.bossAlertsEnabledRaid == nil then g.bossAlertsEnabledRaid = true end
    if g.bossAlertsEnabledMplus == nil then g.bossAlertsEnabledMplus = true end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then
        return g.bossAlertsEnabledRaid ~= false
    end
    if instanceType == "party" then
        return g.bossAlertsEnabledMplus ~= false
    end
    return true
end

-- [DISABLED] ClearEncounterWarningsUI 已注释掉。
-- 原因：在 ENCOUNTER_START 等事件处理链路中调用此函数，会导致 Blizzard 受保护框架
-- (CriticalEncounterWarnings 等) 的 OnHide → ResetWarning → ScaleTextToFit 在
-- tainted 执行上下文中对秘密宽度值做算术运算，产生
-- "attempt to perform arithmetic on a secret number value (execution tainted by 'EXBoss')" 报错。
-- pcall 无法拦截此类 WoW 安全系统上报的 taint 违规。
-- 暴雪警告框有自己的生命周期，EXBoss 无需主动清除。
-- 如需恢复：将下方整块取消注释，并同步恢复两处 ClearEncounterWarningsUI() 调用。
--
-- local function ClearEncounterWarningsUI()
--     local frames = {
--         _G.CriticalEncounterWarnings,
--         _G.MediumEncounterWarnings,
--         _G.MinorEncounterWarnings,
--     }
--     for i = 1, #frames do
--         local frame = frames[i]
--         if type(frame) == "table" then
--             if type(frame.ClearWarning) == "function" then
--                 pcall(frame.ClearWarning, frame)
--             elseif type(frame.HideWarning) == "function" then
--                 pcall(frame.HideWarning, frame)
--             end
--         end
--     end
--     local tooltip = _G.GameTooltip
--     if tooltip and type(tooltip.Hide) == "function" then
--         pcall(tooltip.Hide, tooltip)
--     end
-- end

local function ResolveEncounterID(encounterID)
    local n = tonumber(encounterID)
    if n then
        return n
    end
    return encounterID
end

local function ResolveBossDef(encounterID)
    local bosses = ExBoss.Timeline and ExBoss.Timeline._bosses
    if type(bosses) ~= "table" then
        return nil, ResolveEncounterID(encounterID)
    end
    local id = ResolveEncounterID(encounterID)
    local def = bosses[id]
    if not def and type(id) == "number" then
        def = bosses[tostring(id)]
    end
    return def, id
end

local _encounterEventRowsCache = {}

local function GetEncounterEventRows(encounterID)
    local id = tonumber(encounterID)
    if not id then return nil end
    local cached = _encounterEventRowsCache[id]
    if cached ~= nil then
        return cached or nil
    end

    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" or type(data.maps) ~= "table" then
        _encounterEventRowsCache[id] = false
        return nil
    end

    for _, map in pairs(data.maps) do
        if type(map) == "table" and type(map.bosses) == "table" then
            for _, boss in pairs(map.bosses) do
                if type(boss) == "table" and tonumber(boss.encounterID) == id and type(boss.events) == "table" then
                    _encounterEventRowsCache[id] = boss.events
                    return boss.events
                end
            end
        end
    end

    _encounterEventRowsCache[id] = false
    return nil
end

local function BuildRuntimeSkillFromEvent(eventID, event)
    if type(event) ~= "table" then return nil end
    local evenSpellID = tonumber(event.evenSpellID)
    local spellID = tonumber(event.spellID) or evenSpellID
    local name = nil
    local spellIdentifier = evenSpellID or spellID
    if spellIdentifier and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, apiName = pcall(C_Spell.GetSpellName, spellIdentifier)
        if ok and type(apiName) == "string" and apiName ~= "" then
            name = apiName
        end
    end
    if not name then
        name = event.eventName or event.name
    end
    if type(name) ~= "string" or name == "" then
        name = spellID and ("技能 " .. tostring(spellID)) or ("事件 " .. tostring(eventID))
    end
    local rawName = tostring(name or "")
    name = LocalizeDynamicText(name)
    return {
        eventID = tonumber(event.eventID) or tonumber(eventID),
        spellID = spellID,
        evenSpellID = evenSpellID,
        spellIdentifier = evenSpellID or spellID,
        iconFileID = ResolveSpellIconFileID(evenSpellID or spellID, spellID, event.iconFileID),
        displayName = name,
        source = "duration_map",
        preAlert = 5,
        castDuration = 1.5,
        barPriority = 2,
        showBunBar = true,
        showTimerBar = true,
        screenAlert = false,
        preAlertText = "{name}",
        screenText = nil,
        voiceLabel = rawName,
    }
end

local function NormalizeMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "fixed" or m == "blizzard" or m == "auto" then
        return m
    end
    return "auto"
end

local function NormalizeFixedDriver(driver)
    local v = tostring(driver or ""):lower()
    if v == FIXED_DRIVER_AI then
        return FIXED_DRIVER_AI
    end
    return FIXED_DRIVER_TIME
end

local function NormalizeEncounterTrigger(trigger)
    local t = tostring(trigger or ""):upper()
    if t == TRIGGER_TIME or t == TRIGGER_AI or t == TRIGGER_BLZ then
        return t
    end
    return nil
end

local function GetEncounterTriggerPreset(encounterID)
    local id = tonumber(encounterID) or encounterID

    if _G.EXBossData and type(_G.EXBossData.GetEncounterTrigger) == "function" then
        local ok, trigger = pcall(_G.EXBossData.GetEncounterTrigger, id)
        if ok then
            local normalized = NormalizeEncounterTrigger(trigger)
            if normalized then
                return normalized
            end
        end
    end

    local all = _G.EXBOSS_ENCOUNTER_TRIGGERS
    if type(all) ~= "table" then
        return nil
    end
    local row = all[id]
    if row == nil then
        row = all[tostring(id)]
    end
    if type(row) == "table" then
        return NormalizeEncounterTrigger(row.trigger)
    end
    return NormalizeEncounterTrigger(row)
end

local function GetEncounterTriggerRow(encounterID)
    local id = tonumber(encounterID) or encounterID
    local all = _G.EXBOSS_ENCOUNTER_TRIGGERS
    if type(all) ~= "table" then
        return nil
    end
    local row = all[id]
    if row == nil then
        row = all[tostring(id)]
    end
    return type(row) == "table" and row or nil
end

local function BuildEncounterEventActions(encounterID)
    local function NormalizeCastStartUnit(unit)
        local u = tostring(unit or ""):lower()
        if u == "boss" then
            return "boss"
        end
        if u == "boss1" or u == "boss2" or u == "boss3" or u == "boss4" or u == "boss5" then
            return u
        end
        return nil
    end

    local function NormalizeCastStartEvent(eventName)
        local e = tostring(eventName or ""):lower()
        if e == "cast" or e == "start" or e == "spellcast_start" then
            return "cast"
        end
        if e == "channel" or e == "channel_start" or e == "spellcast_channel_start" then
            return "channel"
        end
        return nil
    end

    local out = {}
    local row = GetEncounterTriggerRow(encounterID)
    local src = row and row.eventActions
    if type(src) ~= "table" then
        return out
    end
    for rawEventID, actionRow in pairs(src) do
        local eventID = tonumber(rawEventID)
        if eventID and type(actionRow) == "table" then
            local clearDelay = tonumber(actionRow.clearActiveSnapshotAfter)
            local waitTimelineFinish = actionRow.waitTimelineFinish == true
            local timelineFinishTimeout = tonumber(actionRow.timelineFinishTimeout)
            local finishMode = tostring(actionRow.finishMode or ""):lower()
            local timerFinishIgnoreStateWindow = tonumber(actionRow.timerFinishIgnoreStateWindow)
            local castStartUnit = NormalizeCastStartUnit(actionRow.castStartUnit)
            -- Temporary probe: event 296 had a legacy boss-unit override that conflicts with
            -- the rebuilt cast-window matching path. Ignore that single override for now so
            -- we can verify whether it is the only blocker for playback.
            if eventID == 296 then
                castStartUnit = nil
            end
            local castStartWindow = tonumber(actionRow.castStartWindow)
            local castStartEvent = NormalizeCastStartEvent(actionRow.castStartEvent)
            local resumeFromCanceledSnapshot = actionRow.resumeFromCanceledSnapshot == true
            local resumeSnapshotTolerance = tonumber(actionRow.resumeSnapshotTolerance)
            local resumeSnapshotWindow = tonumber(actionRow.resumeSnapshotWindow)
            local canceledSnapshotEvents = nil
            if type(actionRow.canceledSnapshotEvents) == "table" then
                canceledSnapshotEvents = {}
                for key, value in pairs(actionRow.canceledSnapshotEvents) do
                    local eventValue = tonumber(value)
                    local eventKey = tonumber(key)
                    local eventID = eventValue or (value == true and eventKey or nil)
                    if eventID then
                        canceledSnapshotEvents[eventID] = true
                    end
                end
                if next(canceledSnapshotEvents) == nil then
                    canceledSnapshotEvents = nil
                end
            end
            local preEventLimits = nil
            if type(actionRow.preEventLimits) == "table" then
                preEventLimits = {}
                for rawLimitEventID, rawLimitCount in pairs(actionRow.preEventLimits) do
                    local limitEventID = tonumber(rawLimitEventID)
                    local limitCount = tonumber(rawLimitCount)
                    if limitEventID and limitCount and limitCount > 0 then
                        preEventLimits[limitEventID] = limitCount
                    end
                end
                if next(preEventLimits) == nil then
                    preEventLimits = nil
                end
            end
            if (clearDelay and clearDelay > 0)
                or preEventLimits
                or waitTimelineFinish
                or finishMode ~= ""
                or (timerFinishIgnoreStateWindow and timerFinishIgnoreStateWindow > 0)
                or castStartUnit ~= nil
                or (castStartWindow and castStartWindow > 0)
                or castStartEvent ~= nil
                or resumeFromCanceledSnapshot then
                out[eventID] = {}
                if clearDelay and clearDelay > 0 then
                    out[eventID].clearActiveSnapshotAfter = clearDelay
                end
                if waitTimelineFinish then
                    out[eventID].waitTimelineFinish = true
                    if timelineFinishTimeout and timelineFinishTimeout > 0 then
                        out[eventID].timelineFinishTimeout = timelineFinishTimeout
                    end
                end
                if preEventLimits then
                    out[eventID].preEventLimits = preEventLimits
                end
                if finishMode ~= "" then
                    out[eventID].finishMode = finishMode
                end
                if timerFinishIgnoreStateWindow and timerFinishIgnoreStateWindow > 0 then
                    out[eventID].timerFinishIgnoreStateWindow = timerFinishIgnoreStateWindow
                end
                if castStartUnit then
                    out[eventID].castStartUnit = castStartUnit
                end
                if castStartWindow and castStartWindow > 0 then
                    out[eventID].castStartWindow = castStartWindow
                end
                if castStartEvent then
                    out[eventID].castStartEvent = castStartEvent
                end
                if resumeFromCanceledSnapshot then
                    out[eventID].resumeFromCanceledSnapshot = true
                    out[eventID].resumeSnapshotTolerance = resumeSnapshotTolerance
                    out[eventID].resumeSnapshotWindow = resumeSnapshotWindow
                    out[eventID].canceledSnapshotEvents = canceledSnapshotEvents
                end
            end
        end
    end
    return out
end

local function BuildEncounterFixedAISyncCycleLimits(encounterID)
    local out = {}
    local row = GetEncounterTriggerRow(encounterID)
    local src = row and row.syncCycleLimits
    if type(src) ~= "table" then
        return out
    end
    for rawEventID, rawLimit in pairs(src) do
        local eventID = tonumber(rawEventID)
        local limit = tonumber(rawLimit)
        if eventID and limit and limit > 0 then
            out[eventID] = limit
        end
    end
    return out
end

local function GetDurationRulesForEncounter(encounterID)
    local id = tonumber(encounterID)
    if not id then return nil end
    local rows = nil
    if type(_G.EXBOSS_DURATION_EVENT_RULES) == "table" then
        rows = _G.EXBOSS_DURATION_EVENT_RULES[id]
        if rows == nil then
            rows = _G.EXBOSS_DURATION_EVENT_RULES[tostring(id)]
        end
    end
    if type(rows) ~= "table" or #rows == 0 then
        return nil
    end
    return rows
end

local function HasDurationRulesForEncounter(encounterID)
    return type(GetDurationRulesForEncounter(encounterID)) == "table"
end

local function GetFixedDriverOverride(encounterID)
    local tdb = TimerDB()
    local byID = tdb.fixedDriverByEncounter
    local v = byID[encounterID]
    if v == nil then
        v = byID[tostring(encounterID)]
    end
    if v == nil or v == "" then
        v = tdb.fixedDriverDefault or FIXED_DRIVER_TIME
    end
    return NormalizeFixedDriver(v)
end

local function ModeUsesFixed(mode)
    return mode == "fixed"
end

local function ModeUsesTimeline(mode)
    return mode == "blizzard"
end

local function CanUseFixedForEncounter(encounterID, bossDef)
    local id = tonumber(encounterID)
    if not id then return false end
    local set = _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS
    if type(set) ~= "table" or set[id] ~= true then
        return false
    end
    local def = bossDef
    if type(def) ~= "table" then
        def = ExBoss.Timeline and ExBoss.Timeline._bosses and ExBoss.Timeline._bosses[id]
    end
    return type(def) == "table" and type(def.skills) == "table" and #def.skills > 0
end

local function CanUseDurationMapForEncounter(encounterID)
    return HasDurationRulesForEncounter(encounterID)
end

local function CanUseTimelineAPI()
    if not C_EncounterTimeline then return false end
    if C_EncounterTimeline.IsFeatureAvailable then
        local ok, available = pcall(C_EncounterTimeline.IsFeatureAvailable)
        if ok and not available then
            return false
        end
    end
    return true
end

local function NormalizeText(v)
    if type(v) ~= "string" then return "" end
    local t = v:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

local function ResolveOccurrenceKey(skill, source)
    if type(skill) ~= "table" then
        return nil
    end
    local prefix = tostring(source or "timer")
    local eventID = tonumber(skill.eventID)
    if eventID then
        return prefix .. ":event:" .. tostring(eventID)
    end
    local spellID = tonumber(skill.evenSpellID) or tonumber(skill.spellIdentifier) or tonumber(skill.spellID)
    if spellID then
        return prefix .. ":spell:" .. tostring(spellID)
    end
    local name = NormalizeText(skill.displayName or skill.name)
    if name ~= "" then
        return prefix .. ":name:" .. name
    end
    return nil
end

local function ResolveDefaultCentralText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    local text = NormalizeText(timer.screenText)
    if text ~= "" then
        return text
    end
    text = NormalizeText(timer.displayName)
    if text ~= "" then
        return text
    end
    return ""
end

local function NormalizeLeadSeconds(v, fallback)
    local n = tonumber(v)
    if not n then
        n = tonumber(fallback) or 0
    end
    if n < 0 then n = 0 end
    if n > 30 then n = 30 end
    return n
end

local function NormalizeTriggerOffsetMode(v)
    local s = tostring(v or ""):lower()
    if s == "early" then
        return "early"
    end
    return "delay"
end

local function NormalizeTriggerOffsetSeconds(v)
    local n = tonumber(v)
    if not n then
        n = 0
    end
    if n < 0 then n = 0 end
    if n > 30 then n = 30 end
    return n
end

local function GetEventConfigRoot()
    if _G.EXBossData and _G.EXBossData.GetEventConfigRoot then
        return _G.EXBossData.GetEventConfigRoot()
    end
    EXBossDataDB = EXBossDataDB or {}
    EXBossDataDB.events = EXBossDataDB.events or {}
    return EXBossDataDB.events
end

local function TryPublishRuntimeSelection()
    local bossCfg = ExBoss and ExBoss.BossConfig
    if bossCfg and type(bossCfg.PublishRuntimeSelection) == "function" then
        pcall(bossCfg.PublishRuntimeSelection, bossCfg)
    end
end

local function ResolveTimerVoicePlan(timer)
    if type(timer) ~= "table" or type(timer.voicePlan) ~= "table" then
        return nil
    end
    return timer.voicePlan
end

local function ResolveVoiceEventConfig(timer)
    local voicePlan = ResolveTimerVoicePlan(timer)
    if type(voicePlan) == "table" and voicePlan.source == "own" and type(voicePlan.triggers) == "table" then
        return {
            enabled = (voicePlan.enabled ~= false),
            triggers = voicePlan.triggers,
        }
    end
    return nil
end

local function ResolveEventColorFromVoiceEvents(timer)
    if type(timer) == "table" and type(timer.colorConfig) == "table" then
        local cfg = timer.colorConfig
        local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
        if CS and CS.ResolveEventColor then
            local r, g, b = CS.ResolveEventColor(cfg)
            if r ~= nil and g ~= nil and b ~= nil then
                return { r = r, g = g, b = b, a = 1 }
            end
        end
        if cfg.r ~= nil and cfg.g ~= nil and cfg.b ~= nil then
            return {
                r = tonumber(cfg.r) or 1,
                g = tonumber(cfg.g) or 0.82,
                b = tonumber(cfg.b) or 0.25,
                a = tonumber(cfg.a) or 1,
            }
        end
    end
    return nil
end

local function ResolveBlizzardEventColor(timer)
    if type(timer) ~= "table" or not (C_EncounterEvents and C_EncounterEvents.GetEventColor) then
        return nil
    end
    local eventID = tonumber(timer.timelineEventID) or tonumber(timer.eventID)
    if not eventID then
        return nil
    end
    local ok, colorObj = pcall(C_EncounterEvents.GetEventColor, eventID)
    if not ok then
        return nil
    end
    return ExtractColorRGB(colorObj)
end

local function SafeResolveEventColorFromVoiceEvents(timer)
    local ok, color = pcall(ResolveEventColorFromVoiceEvents, timer)
    if ok and type(color) == "table" then
        return color
    end
    if not ok and not _colorResolveErrorLogged then
        _colorResolveErrorLogged = true
        --         print("|cffff4400Ex|r|cff00ccffBoss|r 颜色解析失败（已忽略，不影响计时条）: " .. tostring(color))
    end
    return nil
end

local function ResolveSkillEventID(skill, encounterID)
    if type(skill) ~= "table" then return nil end
    local eventID = tonumber(skill.eventID)
    if eventID then
        return eventID
    end

    local spellID = tonumber(skill.evenSpellID) or tonumber(skill.spellIdentifier) or tonumber(skill.spellID)
    if not spellID then
        return nil
    end

    local rows = GetEncounterEventRows(encounterID)
    if type(rows) ~= "table" then
        return nil
    end

    for rawEventID, row in pairs(rows) do
        if type(row) == "table" then
            local rowEventID = tonumber(row.eventID) or tonumber(rawEventID)
            local rowSpellID = tonumber(row.evenSpellID) or tonumber(row.spellID)
            if rowEventID and rowSpellID and rowSpellID == spellID then
                return rowEventID
            end
        end
    end

    return nil
end

local function ResetFixedVoiceTriggerState(timer, trigger)
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] = false
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"] = "delay"
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"] = 0
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Fired"] = false
end

local function ResolveTimerVoiceLabel(timer)
    if type(timer) ~= "table" then
        return ""
    end
    local voicePlan = ResolveTimerVoicePlan(timer)
    if type(voicePlan) == "table" then
        local label = NormalizeText(voicePlan.label)
        if label ~= "" then
            return label
        end
    end
    return NormalizeText(timer.voiceLabel)
end

local function ApplyFixedVoiceTriggerConfig(timer)
    ResetFixedVoiceTriggerState(timer, 1)
    ResetFixedVoiceTriggerState(timer, 2)

    if type(timer) ~= "table" then return end
    if timer.castVoiceSource ~= nil and timer.castVoiceSource ~= "own" then
        return
    end

    local cfg = ResolveVoiceEventConfig(timer)
    if type(cfg) ~= "table" then
        if ResolveTimerVoiceLabel(timer) ~= "" then
            timer.fixedVoiceTrigger1Enabled = true
        end
        return
    end
    if cfg.enabled == false then
        return
    end

    local triggers = cfg.triggers
    if type(triggers) ~= "table" then
        if ResolveTimerVoiceLabel(timer) ~= "" then
            timer.fixedVoiceTrigger1Enabled = true
        end
        return
    end

    local hasExplicitFixedVoice = false
    for trigger = 1, 2 do
        local triggerCfg = triggers[trigger]
        local allowTrigger = not (trigger == 2 and timer.source ~= "trash" and timer.countdownPlayName ~= true)
        if allowTrigger and type(triggerCfg) == "table" and triggerCfg.enabled == true then
            hasExplicitFixedVoice = true
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] = true
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"] = NormalizeTriggerOffsetMode(triggerCfg
                .fixedOffsetMode)
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"] = NormalizeTriggerOffsetSeconds(triggerCfg
                .fixedOffsetSeconds)
        end
    end

    if not hasExplicitFixedVoice and ResolveTimerVoiceLabel(timer) ~= "" then
        timer.fixedVoiceTrigger1Enabled = true
    end
end

local function CaptureLastFiredTimer(timer, now)
    if type(timer) ~= "table" then
        return
    end
    local firedAt = tonumber(now) or GetTime()
    timer.firedAt = firedAt

    -- _lastFired 供施法匹配层在 timer 被移出 _active 后继续读取。
    -- 这里必须保存快照，不能保留原表引用；否则后续 remove/复用/字段改写会污染最近触发池。
    local snapshot = DeepCopy(timer)
    snapshot.firedAt = firedAt
    table.insert(Scheduler._lastFired, 1, snapshot)
    while #Scheduler._lastFired > MAX_LAST_FIRED do
        table.remove(Scheduler._lastFired)
    end
end

local function GetFixedVoiceTriggerBaseTime(timer, trigger)
    if type(timer) ~= "table" then return nil end
    trigger = tonumber(trigger)
    if trigger == 1 then
        return tonumber(timer.castTime)
    end
    if trigger == 2 then
        if timer.preAlertEnabled == false then
            return nil
        end
        return tonumber(timer.preAlertTime)
    end
    return nil
end

local function GetFixedVoiceTriggerFireTime(timer, trigger)
    local baseTime = GetFixedVoiceTriggerBaseTime(timer, trigger)
    if not baseTime then
        return nil
    end

    if tonumber(trigger) == 2 and type(timer) == "table" and timer.countdownPlayName == true then
        return baseTime - 1
    end

    local mode = NormalizeTriggerOffsetMode(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"])
    local offset = NormalizeTriggerOffsetSeconds(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"])
    if mode == "early" then
        return baseTime - offset
    end
    return baseTime + offset
end

local function HasPendingFixedVoiceTriggers(timer)
    if type(timer) ~= "table" then return false end
    for trigger = 1, 2 do
        if timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] == true
            and timer["fixedVoiceTrigger" .. tostring(trigger) .. "Fired"] ~= true
            and GetFixedVoiceTriggerFireTime(timer, trigger) ~= nil then
            return true
        end
    end
    return false
end

local function HasAnyFixedVoiceTriggerEnabled(timer)
    if type(timer) ~= "table" then
        return false
    end
    return timer.fixedVoiceTrigger1Enabled == true or timer.fixedVoiceTrigger2Enabled == true
end

local function TryFireFixedVoiceTriggers(timer, now)
    if type(timer) ~= "table" then return end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "skip no-engine timer=%s event=%s name=%s",
            tostring(timer.id), tostring(timer.eventID), tostring(timer.displayName or timer.baseDisplayName or "")
        ))
        return
    end

    for trigger = 1, 2 do
        local allowTrigger = not (timer.source == "fixed_ai"
            and trigger == 1
            and timer.fixedAICompletingFromFinished ~= true)
        if allowTrigger then
            local enabled = (timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] == true)
            local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
            if enabled and timer[firedKey] ~= true then
                local fireAt = GetFixedVoiceTriggerFireTime(timer, trigger)
                if fireAt and now >= fireAt then
                    AIVoiceDebugPrint(Scheduler, timer, string.format(
                        "try trigger=%d timer=%s event=%s name=%s now=%.2f fireAt=%.2f cast=%.2f pre=%.2f label=%s",
                        trigger,
                        tostring(timer.id),
                        tostring(timer.eventID),
                        tostring(timer.displayName or timer.baseDisplayName or ""),
                        tonumber(now) or 0,
                        tonumber(fireAt) or 0,
                        tonumber(timer.castTime) or 0,
                        tonumber(timer.preAlertTime) or 0,
                        tostring(ResolveTimerVoiceLabel(timer))
                    ))
                    if timer.source == "trash" then
                        TrashVoiceDebugPrint(string.format(
                            "timer trigger=%d try timer=%s spell=%s event=%s now=%.2f fireAt=%.2f label=%s",
                            trigger,
                            tostring(timer.id),
                            tostring(timer.spellID or "nil"),
                            tostring(timer.eventID or "nil"),
                            tonumber(now) or 0,
                            tonumber(fireAt) or 0,
                            tostring(ResolveTimerVoiceLabel(timer))
                        ))
                    end
                    timer[firedKey] = true
                    local ok, err = Engine:TryPlayForTimer(timer, trigger)
                    AIVoiceDebugPrint(Scheduler, timer, string.format(
                        "result trigger=%d timer=%s event=%s ok=%s err=%s",
                        trigger, tostring(timer.id), tostring(timer.eventID), tostring(ok), tostring(err or "")
                    ))
                    if timer.source == "trash" then
                        TrashVoiceDebugPrint(string.format(
                            "timer trigger=%d result timer=%s spell=%s event=%s ok=%s err=%s",
                            trigger,
                            tostring(timer.id),
                            tostring(timer.spellID or "nil"),
                            tostring(timer.eventID or "nil"),
                            tostring(ok),
                            tostring(err or "")
                        ))
                    end
                end
            end
        end
    end
end

local function ScheduleFixedVoiceTriggerPlayback(timer, trigger, delay)
    if type(timer) ~= "table" then
        return false
    end
    local wait = tonumber(delay)
    if not wait or wait <= 0 then
        return false
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        return false
    end

    local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
    local scheduledKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Scheduled"
    if timer[scheduledKey] == true then
        return true
    end

    timer[scheduledKey] = true
    local snapshot = DeepCopy(timer)
    snapshot[firedKey] = true
    C_Timer.After(wait, function()
        timer[scheduledKey] = nil
        if timer[firedKey] == true then
            return
        end
        timer[firedKey] = true
        local ok, err = Engine:TryPlayForTimer(snapshot, trigger)
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "scheduled trigger=%d timer=%s event=%s delay=%.2f ok=%s err=%s",
            trigger,
            tostring(timer.id),
            tostring(timer.eventID),
            tonumber(wait) or 0,
            tostring(ok),
            tostring(err or "")
        ))
    end)
    return true
end

local function EnsureFixedVoiceAtCast(timer)
    if type(timer) ~= "table" then
        return
    end
    if timer.castVoiceSource ~= nil and timer.castVoiceSource ~= "own" then
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "cast-fallback skip source timer=%s event=%s castVoiceSource=%s",
            tostring(timer.id), tostring(timer.eventID), tostring(timer.castVoiceSource)
        ))
        return
    end
    if timer.fixedVoiceCastFallbackTried == true then
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "cast-fallback skip tried timer=%s event=%s",
            tostring(timer.id), tostring(timer.eventID)
        ))
        return
    end
    timer.fixedVoiceCastFallbackTried = true

    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "cast-fallback skip no-engine timer=%s event=%s",
            tostring(timer.id), tostring(timer.eventID)
        ))
        return
    end

    if not HasAnyFixedVoiceTriggerEnabled(timer) then
        local label = ResolveTimerVoiceLabel(timer)
        if label == "" then
            AIVoiceDebugPrint(Scheduler, timer, string.format(
                "cast-fallback skip no-label timer=%s event=%s",
                tostring(timer.id), tostring(timer.eventID)
            ))
            return
        end
    end

    if timer.fixedVoiceTrigger1Enabled == true and timer.fixedVoiceTrigger1Fired ~= true then
        local now = GetTime()
        local fireAt = GetFixedVoiceTriggerFireTime(timer, 1)
        if fireAt and fireAt > now then
            local delay = fireAt - now
            if ScheduleFixedVoiceTriggerPlayback(timer, 1, delay) then
                AIVoiceDebugPrint(Scheduler, timer, string.format(
                    "cast-fallback schedule timer=%s event=%s delay=%.2f",
                    tostring(timer.id),
                    tostring(timer.eventID),
                    tonumber(delay) or 0
                ))
                return
            end
        end
    end

    if timer.fixedVoiceTrigger1Fired == true then
        AIVoiceDebugPrint(Scheduler, timer, string.format(
            "cast-fallback skip already-fired timer=%s event=%s",
            tostring(timer.id), tostring(timer.eventID)
        ))
        return
    end

    AIVoiceDebugPrint(Scheduler, timer, string.format(
        "cast-fallback try timer=%s event=%s name=%s label=%s",
        tostring(timer.id),
        tostring(timer.eventID),
        tostring(timer.displayName or timer.baseDisplayName or ""),
        tostring(ResolveTimerVoiceLabel(timer))
    ))
    local ok, err = Engine:TryPlayForTimer(timer, 1)
    AIVoiceDebugPrint(Scheduler, timer, string.format(
        "cast-fallback result timer=%s event=%s ok=%s err=%s",
        tostring(timer.id), tostring(timer.eventID), tostring(ok), tostring(err or "")
    ))
end

local IsFixedAICastStartFinishMode

local function ReleaseFixedAIVoiceAtCastTime(timer, now)
    if type(timer) ~= "table" then
        return
    end
    if timer.source ~= "fixed_ai" then
        return
    end
    if not IsFixedAICastStartFinishMode(timer) then
        return
    end
    if timer.fixedAIVoiceReleased == true then
        return
    end
    timer.fixedAIVoiceReleased = true
    timer.fixedAIVoicePendingByFinish = nil

    timer.fixedAICompletingFromFinished = true
    TryFireFixedVoiceTriggers(timer, tonumber(now) or GetTime())
    if timer.fixedVoiceTrigger1Fired == true then
        timer.fixedVoiceCastFallbackTried = true
    end
    EnsureFixedVoiceAtCast(timer)
    timer.fixedAICompletingFromFinished = false
end

function Scheduler:_ApplySkillOverride(timer)
    if type(timer) ~= "table" then return true end
    timer.disabled = false
    local runtimeMode = (timer.timelineManaged or timer.source == "blizzard") and "blizzard" or "fixed"
    local presentation = TimelinePresentation and TimelinePresentation.Resolve and
        TimelinePresentation:Resolve(timer, runtimeMode) or nil
    if type(presentation) ~= "table" then
        timer.disabled = true
        return false
    end
    local mode = tostring(presentation.mode or runtimeMode)
    timer._mode = mode
    timer.usePerEventEnabled = (presentation.usePerEventEnabled == true)
    timer.useEventColor = (presentation.useEventColor == true)
    timer.useCentralText = (presentation.useCentralText == true)
    timer.usePreAlertText = (presentation.usePreAlertText == true)
    timer.useTimerBarRename = (presentation.useTimerBarRename == true)
    timer.useRingProgress = (presentation.useRingProgress == true)
    timer.useOccurrenceCount = (presentation.useOccurrenceCount == true)
    timer.occurrenceDisplayMode = tostring(presentation.occurrenceDisplayMode or "inline")
    timer.useBlizzardHintCountdown = (presentation.useBlizzardHintCountdown == true)
    timer.useBlizzardHintCentral = (presentation.useBlizzardHintCentral == true)
    timer.blizzardHintCountdownLead = tonumber(presentation.blizzardHintCountdownLead) or VIRTUAL_HINT_REMAINING_SECS
    timer.blizzardHintCentralLead = tonumber(presentation.blizzardHintCentralLead) or 2
    timer.blizzardHintCentralDuration = tonumber(presentation.blizzardHintCentralDuration) or 2
    timer.eventColorSource = tostring(presentation.eventColorSource or "own")
    timer.countdownSource = tostring(presentation.countdownSource or "own")
    timer.centralSource = tostring(presentation.centralSource or "none")
    timer.castVoiceSource = tostring(presentation.castVoiceSource or "own")
    timer.preAlertVoiceSource = tostring(presentation.preAlertVoiceSource or "own")
    timer.countdownMode = tostring(presentation.countdownMode or "none")
    timer.centralMode = tostring(presentation.centralMode or "none")
    timer.voicePlan = type(presentation.voicePlan) == "table" and DeepCopy(presentation.voicePlan) or nil
    timer.voiceLabel = NormalizeText(type(timer.voicePlan) == "table" and timer.voicePlan.label or
        presentation.voiceLabel)
    if timer.voiceLabel == "" then
        timer.voiceLabel = nil
    end
    timer.colorConfig = type(presentation.colorConfig) == "table" and DeepCopy(presentation.colorConfig) or nil
    timer.iconFlags = tonumber(presentation.iconFlags) or 0
    timer.ringEnabled = (presentation.ringEnabled == true)
    timer.castProgressBarEnabled = (presentation.castProgressBarEnabled == true)
    timer.castProgressBarRenameEnabled = (presentation.castProgressBarRenameEnabled == true)
    timer.castProgressBarRenameText = NormalizeText(presentation.castProgressBarRenameText)
    timer.ringCastCheckEnabled = (presentation.ringCastCheckEnabled == true)
    timer.ringWindowBefore = tonumber(presentation.ringWindowBefore) or 1
    timer.ringWindowAfter = tonumber(presentation.ringWindowAfter) or 2
    timer.castObserveLead = tonumber(presentation.castObserveLead) or nil
    timer.castObserveOrdinal = tonumber(presentation.castObserveOrdinal) or nil
    timer.castObserveExpectedKind = NormalizeText(presentation.castObserveExpectedKind)
    timer.castObserveUnitFilter = type(presentation.castObserveUnitFilter) == "table" and
        DeepCopy(presentation.castObserveUnitFilter)
        or NormalizeText(presentation.castObserveUnitFilter)
    if timer.castObserveUnitFilter == nil then
        timer.castObserveUnitFilter = GetSpecialBossObserveUnitFilter(timer.encounterID, timer.eventID)
    end
    timer.ringCastDuration = tonumber(presentation.ringCastDuration) or nil
    timer.ringChannelDuration = tonumber(presentation.ringChannelDuration) or nil
    timer.ringPlan = type(presentation.ringPlan) == "table" and DeepCopy(presentation.ringPlan) or nil
    timer.countdownVoiceEnabled = (presentation.countdownVoiceEnabled == true)
    timer.countdownPlayName = (presentation.countdownPlayName == true)

    timer.preAlertEnabled = false
    timer.preAlertTime = nil
    timer.preAlertText = nil
    timer.preAlertFired = true
    timer.screenAlert = false
    if timer.timelineManaged then
        timer.timelinePreAlertLead = 0
    end

    timer.centralEnabled = false
    timer.centralLead = 0
    timer.centralFired = true
    timer.screenText = nil
    timer.timerBarName = nil

    -- 固定时间轴：事件颜色覆盖不依赖 skill override 是否存在。
    -- 这样可避免“中央文本有色、但部分计时条未染色”的不一致。
    if timer.eventColorSource == "own" then
        local eventColor = SafeResolveEventColorFromVoiceEvents(timer)
        if type(eventColor) == "table" then
            local resolved = {
                r = tonumber(eventColor.r) or 1,
                g = tonumber(eventColor.g) or 1,
                b = tonumber(eventColor.b) or 1,
                a = tonumber(eventColor.a) or 1,
            }
            timer.flashTextColor = resolved
            -- 条体与中央文本保持同色，避免依赖 C_EncounterEvents 命中。
            timer.eventColor = {
                r = resolved.r,
                g = resolved.g,
                b = resolved.b,
                a = resolved.a,
            }
        else
            timer.flashTextColor = nil
        end
    else
        timer.flashTextColor = nil
        local blizzardColor = ResolveBlizzardEventColor(timer)
        if type(blizzardColor) == "table" then
            timer.eventColor = blizzardColor
        end
    end

    if presentation.eventEnabled == false then
        timer.disabled = true
        return false
    end

    timer.showBunBar = (presentation.showBunBar ~= false)
    timer.showTimerBar = (presentation.showTimerBar ~= false)

    if presentation.countdownMode == "own" then
        timer.preAlertEnabled = true
        timer.screenAlert = true
        timer.preAlertText = presentation.preAlertText
        local lead = math.min(30, math.max(0, tonumber(presentation.preAlertLead) or 0))
        if lead > 0 then
            timer.preAlertTime = (timer.castTime or GetTime()) - lead
            timer.preAlertFired = false
            if timer.timelineManaged then
                timer.timelinePreAlertLead = lead
            end
        end
    end

    if presentation.centralMode == "own" then
        timer.centralEnabled = true
        timer.centralLead = NormalizeLeadSeconds(presentation.centralLead, 0)
        timer.centralFired = false
        timer.screenText = presentation.centralText
    end

    if presentation.timerBarRenameEnabled == true then
        local rename = NormalizeText(presentation.timerBarRenameText)
        if rename ~= "" then
            timer.timerBarName = rename
        end
    end

    local timerTextCfg = presentation.timerTextColor
    timer.timerTextColor = nil
    if type(timerTextCfg) == "table" then
        local r = tonumber(timerTextCfg.r)
        local g = tonumber(timerTextCfg.g)
        local b = tonumber(timerTextCfg.b)
        local a = tonumber(timerTextCfg.a) or 1
        if r and g and b then
            timer.timerTextColor = { r = r, g = g, b = b, a = a }
        end
    end

    ApplyFixedVoiceTriggerConfig(timer)

    return true
end

function Scheduler:RefreshActiveEventConfig(eventID)
    local eid = tonumber(eventID)
    if not eid or type(self._active) ~= "table" then
        return 0
    end

    local refreshed = 0
    for _, timer in pairs(self._active) do
        if type(timer) == "table" and tonumber(timer.eventID) == nil and type(timer.skillDef) == "table" then
            timer.eventID = ResolveSkillEventID(timer.skillDef, self._encounterID)
        end
        if type(timer) == "table"
            and timer.timelineManaged ~= true
            and tonumber(timer.eventID) == eid then
            self:_ApplyTimerDisplayName(timer)
            if self:_ApplySkillOverride(timer) then
                refreshed = refreshed + 1
                if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshTimer then
                    ExBoss.UI.TimerBar:RefreshTimer(timer)
                end
                if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshTimer then
                    ExBoss.UI.BunBar:RefreshTimer(timer)
                end
            end
        end
    end

    return refreshed
end

function Scheduler:_GetModeOverride(encounterID)
    local tdb = TimerDB()
    local byID = tdb.byEncounter
    local v = byID[encounterID]
    if v == nil then
        v = byID[tostring(encounterID)]
    end
    if v == nil or v == "" then
        v = tdb.default or "auto"
    end
    return NormalizeMode(v)
end

function Scheduler:GetResolvedMode(encounterID)
    local bossDef, resolvedID = ResolveBossDef(encounterID)
    if IsFixedTimeTestOverride(resolvedID)
        and type(bossDef) == "table"
        and type(bossDef.skills) == "table"
        and #bossDef.skills > 0 then
        return "fixed"
    end
    local canFixedTime = CanUseFixedForEncounter(resolvedID, bossDef)
    local canDurationMap = CanUseDurationMapForEncounter(resolvedID)
    local canFixed = canFixedTime or canDurationMap
    local triggerPreset = GetEncounterTriggerPreset(resolvedID)
    local override = self:_GetModeOverride(resolvedID)

    if not bossDef and not canDurationMap then
        return "blizzard"
    end

    if override ~= "auto" then
        if override == "fixed" then
            if not canFixed then
                return "blizzard"
            end
            return "fixed"
        end
        if override == "blizzard" and not CanUseTimelineAPI() and canFixed then
            return "fixed"
        end
        return "blizzard"
    end

    if triggerPreset == TRIGGER_BLZ then
        return "blizzard"
    end
    if triggerPreset == TRIGGER_TIME then
        if canFixedTime then
            return "fixed"
        end
        if canDurationMap then
            return "fixed"
        end
        return "blizzard"
    end
    if triggerPreset == TRIGGER_AI then
        if canDurationMap then
            return "fixed"
        end
        if canFixedTime then
            return "fixed"
        end
        return "blizzard"
    end

    if canFixed then
        return "fixed"
    end
    return "blizzard"
end

-- ── 生命周期 ────────────────────────────────────────────────

function Scheduler:StartBoss(encounterID)
    if not IsBossSceneEnabledForCurrentInstance() then
        self:EndBoss()
        return false
    end
    self:EndBoss()

    local bossDef, resolvedID = ResolveBossDef(encounterID)
    if not bossDef then
        local count = 0
        if ExBoss.Timeline and ExBoss.Timeline._bosses then
            for _ in pairs(ExBoss.Timeline._bosses) do
                count = count + 1
            end
        end
        --         print("|cffff4400Ex|r|cff00ccffBoss|r StartBoss miss id=" .. tostring(encounterID)
        --             .. " type=" .. tostring(type(encounterID))
        --             .. " bosses=" .. tostring(count))
        -- 无本地固定轴定义时，仍允许暴雪原生轴工作。
        bossDef = { axisType = "blizzard", skills = {} }
        resolvedID = ResolveEncounterID(encounterID)
    end

    self._encounterID = resolvedID
    self._mode = self:GetResolvedMode(resolvedID)
    self._running = true
    self._blizzardHintSessionEnabled = true
    self._sessionToken = (tonumber(self._sessionToken) or 0) + 1
    self._acceptedTimelineEventIDs = {}
    self._timelineAddedPending = {}
    self._timelineCountdownSpecByEventID = {}
    self._eventActionsByEventID = BuildEncounterEventActions(resolvedID)
    self._fixedAISyncCycleLimits = BuildEncounterFixedAISyncCycleLimits(resolvedID)
    self._fixedAISyncCycleCounts = {}
    self._debugFixedAIPauseAll = false
    self._bossCastObservePending = {}
    self._bossCastObservePendingByTimerID = {}
    self._bossCastObserveNextID = 1
    self._bossCastObserveRecentStarts = {}
    self._bossCastObserveNextStartID = 1
    self._bossObservedRuntimes = {}
    self._bossObservedRuntimeNextID = 1

    local now = GetTime()
    if ModeUsesFixed(self._mode) then
        self:_SetupFixedDriver(resolvedID, bossDef)
        if self._fixedDriver == FIXED_DRIVER_TIME then
            for _, skill in ipairs(bossDef.skills or {}) do
                local src = tostring(skill.source or bossDef.axisType or "fixed"):lower()
                if src == "fixed" and skill.first then
                    self:_ExpandAndSchedule(skill, now)
                end
            end
        end
    else
        self._fixedDriver = FIXED_DRIVER_TIME
        self._fixedAIDurationRules = nil
        self._fixedAISkillByEventID = {}
        self._fixedAIEventToTimer = {}
        self._fixedAIPendingEvents = {}
        self._fixedAICanceledResumeSnapshot = nil
        self._fixedAISequenceCounters = {}
        self._fixedAIPreEventLimitCounts = {}
        self._fixedAISyncCycleLimits = {}
        self._fixedAISyncCycleCounts = {}
    end

    if self._mode == "blizzard" then
        self._ignoreTimelineRecoveryUntil = now + 2.0
    else
        self._ignoreTimelineRecoveryUntil = 0
    end

    if ModeUsesTimeline(self._mode) and CanUseTimelineAPI() and self._ignoreTimelineRecoveryUntil <= now then
        self:_RecoverTimelineEvents()
    end

    self._frame:Show()
    return true
end

function Scheduler:HandleEncounterStart(encounterID, source)
    local now = GetTime and GetTime() or 0
    local resolvedID = ResolveEncounterID(encounterID)
    if self._running and self._encounterID == resolvedID and (now - (tonumber(self._lastEncounterStartAt) or 0)) <= 1.0 then
        return
    end
    if self._lastEncounterStartID == resolvedID and (now - (tonumber(self._lastEncounterStartAt) or 0)) <= 1.0 then
        return
    end
    self._lastEncounterStartAt = now
    self._lastEncounterStartID = resolvedID
    self._suppressBlizzardTimeline = false
    -- ClearEncounterWarningsUI() -- [DISABLED] 见函数定义处注释
    self:StartBoss(encounterID)
end

function Scheduler:EndBoss()
    if ExBoss.UI.BunBar and ExBoss.UI.BunBar.ReleaseAll then
        ExBoss.UI.BunBar:ReleaseAll()
    end
    if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.ReleaseAll then
        ExBoss.UI.TimerBar:ReleaseAll()
    end
    if ExBoss.UI.Countdown and ExBoss.UI.Countdown.Stop then
        ExBoss.UI.Countdown:Stop()
    end
    if ExBoss.UI.FlashText and ExBoss.UI.FlashText.Stop then
        ExBoss.UI.FlashText:Stop()
    end
    if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Stop then
        ExBoss.UI.FlashTextMedium:Stop()
    end
    if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.Hide then
        ExBoss.UI.CastProgressBar:Hide()
    end
    self._active                          = {}
    self._nextTimerID                     = 1
    self._running                         = false
    self._blizzardHintSessionEnabled      = false
    self._encounterID                     = nil
    self._mode                            = "fixed"
    self._timelineEventToTimer            = {}
    self._timelineCountdownSpecByEventID  = {}
    self._lastFired                       = {}
    self._fixedDriver                     = FIXED_DRIVER_TIME
    self._fixedAIDurationRules            = nil
    self._fixedAISkillByEventID           = {}
    self._fixedAIEventToTimer             = {}
    self._fixedAIPendingEvents            = {}
    self._fixedAICanceledResumeSnapshot   = nil
    self._fixedAISequenceCounters         = {}
    self._fixedAIPreEventLimitCounts      = {}
    self._occurrenceCounts                = {}
    self._fixedTimeOffset                 = 0
    self._fixedTimeEventToTimer           = {}
    self._acceptedTimelineEventIDs        = {}
    self._timelineAddedPending            = {}
    self._eventActionsByEventID           = {}
    self._fixedAISyncCycleLimits          = {}
    self._fixedAISyncCycleCounts          = {}
    self._debugFixedAIPauseAll            = false
    self._bossCastObservePending          = {}
    self._bossCastObservePendingByTimerID = {}
    self._bossCastObserveNextID           = 1
    self._bossCastObserveRecentStarts     = {}
    self._bossCastObserveNextStartID      = 1
    self._bossObservedRuntimes            = {}
    self._bossObservedRuntimeNextID       = 1
    self._sessionToken                    = (tonumber(self._sessionToken) or 0) + 1
    self._ignoreTimelineRecoveryUntil     = 0
    -- ClearEncounterWarningsUI() -- [DISABLED] 见函数定义处注释
    if self._frame then self._frame:Hide() end
end

function Scheduler:HandleEncounterEnd(source)
    local now = GetTime and GetTime() or 0
    if (now - (tonumber(self._lastEncounterEndAt) or 0)) <= 1.0 then
        return
    end
    self._lastEncounterEndAt = now
    self._suppressBlizzardTimeline = true
    self:EndBoss()
end

function Scheduler:StartBlizzardFallback()
    if self._suppressBlizzardTimeline == true then
        return false
    end
    local now = GetTime and GetTime() or 0
    if (now - (tonumber(self._lastEncounterEndAt) or 0)) <= 6.0 then
        return false
    end
    if not IsBossSceneEnabledForCurrentInstance() then
        self:EndBoss()
        return false
    end
    if self._running then
        return false
    end
    if not CanUseTimelineAPI() then
        return false
    end
    self._active                         = {}
    self._nextTimerID                    = 1
    self._encounterID                    = nil
    self._mode                           = "blizzard"
    self._running                        = true
    self._blizzardHintSessionEnabled     = false
    self._timelineEventToTimer           = {}
    self._timelineCountdownSpecByEventID = {}
    self._lastFired                      = {}
    self._fixedDriver                    = FIXED_DRIVER_TIME
    self._fixedAIDurationRules           = nil
    self._fixedAISkillByEventID          = {}
    self._fixedAIEventToTimer            = {}
    self._fixedAIPendingEvents           = {}
    self._fixedAICanceledResumeSnapshot  = nil
    self._fixedAISequenceCounters        = {}
    self._fixedAIPreEventLimitCounts     = {}
    self._occurrenceCounts               = {}
    self._fixedTimeOffset                = 0
    self._fixedTimeEventToTimer          = {}
    self._acceptedTimelineEventIDs       = {}
    self._timelineAddedPending           = {}
    self._eventActionsByEventID          = {}
    self._fixedAISyncCycleLimits         = {}
    self._fixedAISyncCycleCounts         = {}
    self._debugFixedAIPauseAll           = false
    self._bossObservedRuntimes           = {}
    self._bossObservedRuntimeNextID      = 1
    self._sessionToken                   = (tonumber(self._sessionToken) or 0) + 1
    self._ignoreTimelineRecoveryUntil    = 0
    if self._frame then
        self._frame:Show()
    end
    self:_RecoverTimelineEvents()
    return true
end

-- ── fixed 轴展开 ─────────────────────────────────────────────

function Scheduler:_SetupFixedDriver(encounterID, bossDef)
    self._fixedDriver = FIXED_DRIVER_TIME
    self._fixedAIDurationRules = nil
    self._fixedAISkillByEventID = {}
    self._fixedAIEventToTimer = {}
    self._fixedAIPendingEvents = {}
    self._fixedAICanceledResumeSnapshot = nil
    self._fixedAISequenceCounters = {}
    self._fixedAIPreEventLimitCounts = {}
    self._fixedAISyncCycleCounts = {}
    self._occurrenceCounts = {}
    self._fixedTimeOffset = 0
    self._fixedTimeEventToTimer = {}
    self._timelineAddedPending = {}

    local testFixedTime = IsFixedTimeTestOverride(encounterID)
        and type(bossDef) == "table"
        and type(bossDef.skills) == "table"
        and #bossDef.skills > 0
    local canFixedTime = CanUseFixedForEncounter(encounterID, bossDef) or testFixedTime
    local durationRules = GetDurationRulesForEncounter(encounterID)
    local hasDurationRules = type(durationRules) == "table" and #durationRules > 0
    local triggerPreset = GetEncounterTriggerPreset(encounterID)
    local requestedDriver = GetFixedDriverOverride(encounterID)
    if testFixedTime then
        requestedDriver = FIXED_DRIVER_TIME
    elseif triggerPreset == TRIGGER_AI then
        requestedDriver = FIXED_DRIVER_AI
    elseif triggerPreset == TRIGGER_TIME then
        requestedDriver = FIXED_DRIVER_TIME
    end

    local resolvedDriver = requestedDriver
    if resolvedDriver == FIXED_DRIVER_AI and not hasDurationRules then
        resolvedDriver = canFixedTime and FIXED_DRIVER_TIME or FIXED_DRIVER_TIME
    elseif resolvedDriver == FIXED_DRIVER_TIME and not canFixedTime and hasDurationRules then
        resolvedDriver = FIXED_DRIVER_AI
    elseif not canFixedTime and hasDurationRules then
        resolvedDriver = FIXED_DRIVER_AI
    elseif canFixedTime then
        resolvedDriver = FIXED_DRIVER_TIME
    end

    self._fixedDriver = resolvedDriver
    if resolvedDriver == FIXED_DRIVER_AI then
        self._fixedAIDurationRules = durationRules
    end

    if type(bossDef) == "table" and type(bossDef.skills) == "table" then
        for _, skill in ipairs(bossDef.skills) do
            local eventID = tonumber(skill and skill.eventID)
            if eventID then
                self._fixedAISkillByEventID[eventID] = skill
            end
        end
    end

    local eventRows = GetEncounterEventRows(encounterID)
    if type(eventRows) == "table" then
        for eventID, event in pairs(eventRows) do
            local eid = tonumber(eventID)
            if eid and not self._fixedAISkillByEventID[eid] then
                local skill = BuildRuntimeSkillFromEvent(eid, event)
                if skill then
                    self._fixedAISkillByEventID[eid] = skill
                end
            end
        end
    end
end

function Scheduler:_ApplyFixedTimeOffset(newOffset)
    local offset = tonumber(newOffset)
    if not offset then return end
    if math.abs(offset - (self._fixedTimeOffset or 0)) < FIXED_TIME_OFFSET_EPSILON then
        return
    end
    self._fixedTimeOffset = offset

    for _, timer in pairs(self._active) do
        if timer and timer.source == "fixed" and not timer.castFired then
            local base = tonumber(timer.baseCastTime) or tonumber(timer.castTime)
            if base then
                local oldCast = tonumber(timer.castTime) or base
                local newCast = base + offset
                local shift = newCast - oldCast
                timer.castTime = newCast
                if timer.preAlertTime then
                    timer.preAlertTime = timer.preAlertTime + shift
                end
            end
        end
    end
end

function Scheduler:_FindBestFixedTimeTimer(observedCastAt)
    local bestTimerID = nil
    local bestDelta = nil
    local target = tonumber(observedCastAt)
    if not target then return nil end

    for timerID, timer in pairs(self._active) do
        if timer and timer.source == "fixed" and not timer.castFired and timer.fixedTimelineMatched ~= true then
            local castTime = tonumber(timer.castTime)
            if castTime then
                local delta = math.abs(target - castTime)
                if (not bestDelta or delta < bestDelta) then
                    bestDelta = delta
                    bestTimerID = timerID
                end
            end
        end
    end

    if bestDelta and bestDelta <= FIXED_TIME_MATCH_TOLERANCE then
        return bestTimerID
    end
    return nil
end

function Scheduler:_ResolveFixedAIEventID(duration)
    local d = tonumber(duration)
    if not d then return nil end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then return nil end

    local bestEventID, bestDelta = nil, nil
    for _, row in ipairs(rules) do
        local t = tonumber(row and row.time)
        local eventID = tonumber(row and row.eventID)
        if t and eventID then
            local delta = math.abs(d - t)
            if not bestDelta or delta < bestDelta then
                bestDelta = delta
                bestEventID = eventID
            end
        end
    end

    if bestDelta and bestDelta <= FIXED_AI_MATCH_TOLERANCE then
        return bestEventID
    end
    return nil
end

function Scheduler:_ResolveFixedAIEventIDForMode(duration, timelineEventID, syncMode)
    local d = tonumber(duration)
    if not d then return nil end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then return nil end

    local candidates = {}
    local bestDelta = nil
    local timelineID = tonumber(timelineEventID)

    for _, row in ipairs(rules) do
        if type(row) == "table" then
            local rowSync = (row.sync == true)
            if rowSync == syncMode then
                local t = tonumber(row.time)
                local eventID = tonumber(row.eventID)
                if t and eventID then
                    if (not syncMode) or (timelineID and eventID == timelineID) then
                        local delta = math.abs(d - t)
                        if not bestDelta or delta < bestDelta then
                            bestDelta = delta
                            candidates = { row }
                        elseif delta == bestDelta then
                            candidates[#candidates + 1] = row
                        end
                    end
                end
            end
        end
    end

    if not (bestDelta and bestDelta <= FIXED_AI_MATCH_TOLERANCE) then
        return nil
    end

    if #candidates <= 1 or syncMode == true then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    local firstGroup = NormalizeText(candidates[1] and candidates[1].sequenceGroup)
    if firstGroup == "" then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    local grouped = {}
    for _, row in ipairs(candidates) do
        if NormalizeText(row and row.sequenceGroup) == firstGroup then
            grouped[#grouped + 1] = row
        end
    end
    if #grouped == 0 then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    table.sort(grouped, function(a, b)
        return (tonumber(a and a.sequenceOrder) or 0) < (tonumber(b and b.sequenceOrder) or 0)
    end)

    self._fixedAISequenceCounters = type(self._fixedAISequenceCounters) == "table" and self._fixedAISequenceCounters or
        {}
    local current = tonumber(self._fixedAISequenceCounters[firstGroup]) or 0
    local nextIndex = (current % #grouped) + 1
    self._fixedAISequenceCounters[firstGroup] = current + 1
    local chosen = grouped[nextIndex]
    if chosen then
        return tonumber(chosen.eventID)
    end
    return nil
end

function Scheduler:_CountFixedAISyncRuleMatches(batch)
    if type(batch) ~= "table" then
        return 0
    end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then
        return 0
    end
    local count = 0
    for _, queued in ipairs(batch) do
        local d = SafeToNumber(queued and queued.duration)
        if d then
            local matched = false
            for _, row in ipairs(rules) do
                if type(row) == "table" and row.sync == true then
                    local t = SafeToNumber(row.time)
                    if t and math.abs(d - t) <= FIXED_AI_MATCH_TOLERANCE then
                        matched = true
                        break
                    end
                end
            end
            if matched then
                count = count + 1
            end
        end
    end
    return count
end

function Scheduler:_HasFixedAIPausedSyncAccepted(batch)
    if type(batch) ~= "table" then
        return false
    end
    for _, queued in ipairs(batch) do
        if type(queued) == "table" and queued.pausedSyncAccepted == true then
            return true
        end
    end
    return false
end

function Scheduler:_IsFixedAISyncDuration(duration)
    local d = SafeToNumber(duration)
    if not d then
        return false
    end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then
        return false
    end
    for _, row in ipairs(rules) do
        if type(row) == "table" and row.sync == true then
            local t = SafeToNumber(row.time)
            if t and math.abs(d - t) <= FIXED_AI_MATCH_TOLERANCE then
                return true
            end
        end
    end
    return false
end

function Scheduler:_HasFixedAICanceledResumeSnapshotReady(batch)
    if type(batch) ~= "table" or #batch < 2 then
        return false
    end
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or type(snapshot.entries) ~= "table" or #snapshot.entries == 0 then
        return false
    end
    local now = GetTime()
    local expiresAt = SafeToNumber(snapshot.expiresAt)
    if expiresAt and now > expiresAt then
        self._fixedAICanceledResumeSnapshot = nil
        return false
    end
    return true
end

function Scheduler:_FindFixedAIPreEventLimit(eventID)
    local id = tonumber(eventID)
    if not id then
        return nil, nil
    end
    local actions = self._eventActionsByEventID
    if type(actions) ~= "table" then
        return nil, nil
    end
    for resetEventID, action in pairs(actions) do
        local limits = type(action) == "table" and action.preEventLimits or nil
        local limit = type(limits) == "table" and tonumber(limits[id]) or nil
        if limit and limit > 0 then
            return tonumber(resetEventID), limit
        end
    end
    return nil, nil
end

function Scheduler:_AcceptFixedAIPreEventLimit(eventID)
    local resetEventID, limit = self:_FindFixedAIPreEventLimit(eventID)
    if not resetEventID then
        return true
    end
    self._fixedAIPreEventLimitCounts = type(self._fixedAIPreEventLimitCounts) == "table" and
        self._fixedAIPreEventLimitCounts or {}
    local byReset = self._fixedAIPreEventLimitCounts[resetEventID]
    if type(byReset) ~= "table" then
        byReset = {}
        self._fixedAIPreEventLimitCounts[resetEventID] = byReset
    end
    local id = tonumber(eventID)
    local current = tonumber(byReset[id]) or 0
    if current >= limit then
        return false
    end
    byReset[id] = current + 1
    return true
end

function Scheduler:_ResetFixedAIPreEventLimits(resetEventID)
    local id = tonumber(resetEventID)
    if not id or type(self._fixedAIPreEventLimitCounts) ~= "table" then
        return
    end
    self._fixedAIPreEventLimitCounts[id] = nil
end

function Scheduler:_ResetAllFixedAIPreEventLimits()
    self._fixedAIPreEventLimitCounts = {}
end

function Scheduler:_ResetFixedAISyncCycleLimits()
    self._fixedAISyncCycleCounts = {}
end

function Scheduler:_AcceptFixedAISyncCycleLimit(eventID)
    local id = tonumber(eventID)
    if not id then
        return true
    end
    local limits = self._fixedAISyncCycleLimits
    local limit = type(limits) == "table" and tonumber(limits[id]) or nil
    if not (limit and limit > 0) then
        return true
    end
    self._fixedAISyncCycleCounts = type(self._fixedAISyncCycleCounts) == "table" and self._fixedAISyncCycleCounts or {}
    local current = tonumber(self._fixedAISyncCycleCounts[id]) or 0
    if current >= limit then
        return false
    end
    self._fixedAISyncCycleCounts[id] = current + 1
    return true
end

function Scheduler:_FindFixedAICanceledResumeAction(eventID)
    local id = SafeToNumber(eventID)
    if not id or type(self._eventActionsByEventID) ~= "table" then
        return nil
    end
    for _, action in pairs(self._eventActionsByEventID) do
        if type(action) == "table" and action.resumeFromCanceledSnapshot == true then
            local events = type(action.canceledSnapshotEvents) == "table" and action.canceledSnapshotEvents or nil
            if events and events[id] == true then
                return action
            end
        end
    end
    return nil
end

function Scheduler:_CaptureFixedAICanceledResumeSnapshot(timer, timelineEventID, remaining, now)
    if type(timer) ~= "table" then
        return
    end
    local eventID = SafeToNumber(timer.eventID) or SafeToNumber(timer.timelineEventID)
    local action = self:_FindFixedAICanceledResumeAction(eventID)
    if not action then
        return
    end

    now = SafeToNumber(now) or GetTime()
    local remain = SafeToNumber(remaining)
    if not remain then
        local castTime = SafeToNumber(timer.castTime)
        remain = castTime and (castTime - now) or nil
    end
    if not remain or remain <= 0 then
        return
    end

    local window = math.max(1, SafeToNumber(action.resumeSnapshotWindow) or FIXED_AI_CANCELED_RESUME_WINDOW)
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or (SafeToNumber(snapshot.expiresAt) or 0) < now then
        snapshot = {
            entries = {},
        }
        self._fixedAICanceledResumeSnapshot = snapshot
    end

    snapshot.tolerance = math.max(0.01,
        SafeToNumber(action.resumeSnapshotTolerance) or FIXED_AI_CANCELED_RESUME_TOLERANCE)
    snapshot.expiresAt = now + window

    local entries = snapshot.entries
    local replaced = false
    for _, entry in ipairs(entries) do
        if SafeToNumber(entry.eventID) == eventID then
            entry.remaining = remain
            entry.timelineEventID = SafeToNumber(timelineEventID)
            entry.timerID = SafeToNumber(timer.id)
            replaced = true
            break
        end
    end
    if not replaced then
        entries[#entries + 1] = {
            eventID = eventID,
            remaining = remain,
            timelineEventID = SafeToNumber(timelineEventID),
            timerID = SafeToNumber(timer.id),
        }
    end
end

function Scheduler:_BuildFixedAICanceledResumeSnapshotMap(batch, syncMode)
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or type(batch) ~= "table" then
        return nil
    end

    if syncMode ~= true then
        return nil
    end

    local now = GetTime()
    local expiresAt = SafeToNumber(snapshot.expiresAt)
    if expiresAt and now > expiresAt then
        self._fixedAICanceledResumeSnapshot = nil
        return nil
    end

    local entries = type(snapshot.entries) == "table" and snapshot.entries or nil
    if not entries or #entries == 0 then
        return nil
    end

    local tolerance = SafeToNumber(snapshot.tolerance) or FIXED_AI_CANCELED_RESUME_TOLERANCE
    local usedEntries = {}
    local map = {}
    local matched = false
    for _, queued in ipairs(batch) do
        local duration = SafeToNumber(queued and queued.duration)
        if duration then
            local bestIndex, bestDelta = nil, nil
            for index, entry in ipairs(entries) do
                if not usedEntries[index] then
                    local remaining = SafeToNumber(entry.remaining)
                    local eventID = SafeToNumber(entry.eventID)
                    if remaining and eventID then
                        local delta = math.abs(duration - remaining)
                        if delta <= tolerance and (not bestDelta or delta < bestDelta) then
                            bestIndex = index
                            bestDelta = delta
                        end
                    end
                end
            end
            if bestIndex then
                usedEntries[bestIndex] = true
                map[queued] = SafeToNumber(entries[bestIndex].eventID)
                matched = true
            end
        end
    end

    return matched and map or nil
end

function Scheduler:_ProcessFixedAIPendingBatch(batch, syncMode)
    if type(batch) ~= "table" or #batch == 0 then return end
    if syncMode == true then
        self._fixedAISequenceCounters = {}
        self:_ResetAllFixedAIPreEventLimits()
        self:_ResetFixedAISyncCycleLimits()
    end

    local canceledResumeSnapshotMap = self:_BuildFixedAICanceledResumeSnapshotMap(batch, syncMode)
    local usedCanceledResumeSnapshot = false
    for _, queued in ipairs(batch) do
        local timelineEventID = SafeToNumber(queued.timelineEventID)
        local duration = SafeToNumber(queued.duration)
        local observedAt = SafeToNumber(queued.receivedAt) or GetTime()
        if timelineEventID and duration then
            local inferredEventID = canceledResumeSnapshotMap and canceledResumeSnapshotMap[queued] or nil
            if inferredEventID then
                usedCanceledResumeSnapshot = true
            end
            if not inferredEventID then
                inferredEventID = self:_ResolveFixedAIEventIDForMode(duration, timelineEventID, syncMode)
            end
            if not inferredEventID and syncMode then
                inferredEventID = self:_ResolveFixedAIEventID(duration)
            end
            CastBarEventDebugPrint(inferredEventID, string.format(
                "Scheduler pending resolve event=%s timeline=%s duration=%.2f sync=%s observedAt=%.2f",
                tostring(inferredEventID),
                tostring(timelineEventID),
                tonumber(duration) or 0,
                tostring(syncMode == true),
                tonumber(observedAt) or 0
            ))
            if inferredEventID then
                local skill = self._fixedAISkillByEventID[inferredEventID]
                local hasSkill = type(skill) == "table"
                local acceptedSync = hasSkill and self:_AcceptFixedAISyncCycleLimit(inferredEventID) or false
                local acceptedPre = acceptedSync and self:_AcceptFixedAIPreEventLimit(inferredEventID) or false
                CastBarEventDebugPrint(inferredEventID, string.format(
                    "Scheduler accept-check event=%s timeline=%s hasSkill=%s syncLimit=%s preLimit=%s",
                    tostring(inferredEventID),
                    tostring(timelineEventID),
                    tostring(hasSkill),
                    tostring(acceptedSync),
                    tostring(acceptedPre)
                ))
                if hasSkill and acceptedSync and acceptedPre then
                    local oldTimerID = self._fixedAIEventToTimer[timelineEventID]
                    if oldTimerID then
                        local oldTimer = self._active[oldTimerID]
                        AIVoiceDebugPrint(self, oldTimer, string.format(
                            "remove-source=replace-old timer=%s timeline=%s newEvent=%s %s",
                            tostring(oldTimerID),
                            tostring(timelineEventID),
                            tostring(inferredEventID),
                            AIVoiceTimerTimingText(oldTimer)
                        ))
                        if type(oldTimer) == "table" then
                            oldTimer._debugRemoveReason = "replace-old:" .. tostring(inferredEventID)
                        end
                        CastBarEventDebugPrint(oldTimer, string.format(
                            "Scheduler replace-old remove oldTimer=%s oldEvent=%s timeline=%s newEvent=%s castTime=%.2f",
                            tostring(oldTimerID),
                            tostring(oldTimer and oldTimer.eventID or "nil"),
                            tostring(timelineEventID),
                            tostring(inferredEventID),
                            tonumber(oldTimer and oldTimer.castTime) or 0
                        ))
                        self:_RemoveActiveTimerByID(oldTimerID)
                        self._fixedAIEventToTimer[timelineEventID] = nil
                    end

                    local castTime = observedAt + math.max(0, duration)
                    local timerID = self:_AddTimer(skill, castTime, "fixed_ai")
                    if timerID then
                        local timer = self._active[timerID]
                        if timer then
                            timer.fixedAITimelineEventID = timelineEventID
                        end
                        self._fixedAIEventToTimer[timelineEventID] = timerID
                        CastBarEventDebugPrint(timer, string.format(
                            "Scheduler add event=%s timer=%s timeline=%s duration=%.2f observedAt=%.2f castTime=%.2f",
                            tostring(inferredEventID),
                            tostring(timerID),
                            tostring(timelineEventID),
                            tonumber(duration) or 0,
                            tonumber(observedAt) or 0,
                            tonumber(castTime) or 0
                        ))
                        AIVoiceDebugPrint(self, timer, string.format(
                            "add timer=%s event=%s timeline=%s duration=%.2f name=%s %s preEnabled=%s preAt=%.2f tr1=%s tr2=%s label=%s",
                            tostring(timerID),
                            tostring(inferredEventID),
                            tostring(timelineEventID),
                            tonumber(duration) or 0,
                            tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
                            AIVoiceTimerTimingText(timer),
                            tostring(timer and timer.preAlertEnabled),
                            tonumber(timer and timer.preAlertTime) or 0,
                            tostring(timer and timer.fixedVoiceTrigger1Enabled),
                            tostring(timer and timer.fixedVoiceTrigger2Enabled),
                            tostring(ResolveTimerVoiceLabel(timer))
                        ))
                        AIVoiceDebugPrint(self, timer, string.format(
                            "map-set timeline=%s timer=%s event=%s %s",
                            tostring(timelineEventID),
                            tostring(timerID),
                            tostring(inferredEventID),
                            FixedAIMapDebugText(self)
                        ))
                        PublishFixedAIEventScheduled(self, timer, inferredEventID, duration, observedAt, castTime,
                            syncMode)
                    else
                        AIVoiceDebugPrint(self, nil, string.format(
                            "add failed event=%s timeline=%s duration=%.2f",
                            tostring(inferredEventID), tostring(timelineEventID), tonumber(duration) or 0
                        ))
                    end
                else
                    CastBarEventDebugPrint(inferredEventID, string.format(
                        "Scheduler add skipped event=%s timeline=%s duration=%.2f hasSkill=%s syncLimit=%s preLimit=%s",
                        tostring(inferredEventID),
                        tostring(timelineEventID),
                        tonumber(duration) or 0,
                        tostring(hasSkill),
                        tostring(acceptedSync),
                        tostring(acceptedPre)
                    ))
                    AIVoiceDebugPrint(self, nil, string.format(
                        "add skipped event=%s timeline=%s duration=%.2f skill=%s syncLimit=%s preLimit=%s",
                        tostring(inferredEventID),
                        tostring(timelineEventID),
                        tonumber(duration) or 0,
                        tostring(hasSkill),
                        tostring(acceptedSync),
                        tostring(acceptedPre)
                    ))
                end
            else
                AIVoiceDebugPrint(self, nil, string.format(
                    "resolve failed timeline=%s duration=%.2f sync=%s",
                    tostring(timelineEventID), tonumber(duration) or 0, tostring(syncMode == true)
                ))
            end
        end
    end
    if usedCanceledResumeSnapshot then
        self._fixedAICanceledResumeSnapshot = nil
    end
end

function Scheduler:_ApplyEncounterEventActions(timer)
    if type(timer) ~= "table" then
        return
    end
    local actions = self._eventActionsByEventID
    if type(actions) ~= "table" then
        timer.clearActiveSnapshotAfter = nil
        return
    end
    local eventID = tonumber(timer.eventID) or tonumber(timer.timelineEventID)
    local row = eventID and actions[eventID] or nil
    timer.clearActiveSnapshotAfter = tonumber(row and row.clearActiveSnapshotAfter)
    if row and row.waitTimelineFinish ~= nil then
        timer.waitTimelineFinish = row.waitTimelineFinish == true
    end
    if row and row.timelineFinishTimeout ~= nil then
        timer.timelineFinishTimeout = tonumber(row.timelineFinishTimeout)
    end
    if row and row.finishMode ~= nil then
        timer.finishMode = tostring(row.finishMode or ""):lower()
    end
    timer.timerFinishIgnoreStateWindow = tonumber(row and row.timerFinishIgnoreStateWindow)
    timer.castStartUnit = type(row) == "table" and tostring(row.castStartUnit or ""):lower() or nil
    if timer.castStartUnit == "" then
        timer.castStartUnit = nil
    end
    timer.castStartWindow = tonumber(row and row.castStartWindow)
    timer.castStartEvent = type(row) == "table" and tostring(row.castStartEvent or ""):lower() or nil
    if timer.castStartEvent == "" then
        timer.castStartEvent = nil
    end
    if row and row.resumeFromCanceledSnapshot == true then
        timer.resumeFromCanceledSnapshot = true
        timer.resumeSnapshotTolerance = tonumber(row.resumeSnapshotTolerance)
        timer.resumeSnapshotWindow = tonumber(row.resumeSnapshotWindow)
        timer.canceledSnapshotEvents = row.canceledSnapshotEvents
    else
        timer.resumeFromCanceledSnapshot = nil
        timer.canceledSnapshotEvents = nil
    end
end

function Scheduler:_RemoveActiveTimerByID(timerID)
    local id = tonumber(timerID)
    if not id then
        return
    end
    local timer = self._active[id]
    if not timer then
        return
    end
    if timer.timelineEventID then
        self._timelineEventToTimer[timer.timelineEventID] = nil
    end
    if timer.fixedAITimelineEventID then
        self._fixedAIEventToTimer[timer.fixedAITimelineEventID] = nil
    end
    if timer.fixedTimeTimelineEventID then
        self._fixedTimeEventToTimer[timer.fixedTimeTimelineEventID] = nil
    end
    local countdownRuntime = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
    if countdownRuntime and type(countdownRuntime.Cancel) == "function" then
        countdownRuntime:Cancel("prealert:" .. tostring(id))
    end
    AIVoiceDebugPrint(self, timer, string.format(
        "remove-source=%s timer=%s event=%s timeline=%s %s castFired=%s tr1=%s/%s tr2=%s/%s name=%s",
        tostring(timer._debugRemoveReason or "direct"),
        tostring(timer.id),
        tostring(timer.eventID),
        tostring(timer.fixedAITimelineEventID or timer.timelineEventID or timer.fixedTimeTimelineEventID or ""),
        AIVoiceTimerTimingText(timer),
        tostring(timer.castFired),
        tostring(timer.fixedVoiceTrigger1Fired),
        tostring(timer.fixedVoiceTrigger1Enabled),
        tostring(timer.fixedVoiceTrigger2Fired),
        tostring(timer.fixedVoiceTrigger2Enabled),
        tostring(timer.displayName or timer.baseDisplayName or "")
    ))
    CastBarEventDebugPrint(timer, string.format(
        "Scheduler remove reason=%s timer=%s event=%s timeline=%s castFired=%s now=%.2f cast=%.2f remain=%.2f name=%s",
        tostring(timer._debugRemoveReason or "direct"),
        tostring(timer.id),
        tostring(timer.eventID),
        tostring(timer.fixedAITimelineEventID or timer.timelineEventID or timer.fixedTimeTimelineEventID or ""),
        tostring(timer.castFired),
        tonumber(GetTime()) or 0,
        tonumber(timer.castTime) or 0,
        (tonumber(timer.castTime) or 0) - (tonumber(GetTime()) or 0),
        tostring(timer.displayName or timer.baseDisplayName or "")
    ))
    if timer.source == "trash" and type(timer.trashRuntime) == "table" and tonumber(timer.spellID) then
        TrashVoiceDebugPrint(string.format(
            "local-timer remove runtime=%s timer=%s spell=%s reason=%s castFired=%s ready=%s remaining=%.2f",
            tostring(timer.trashRuntime),
            tostring(timer.id),
            tostring(timer.spellID or "nil"),
            tostring(timer._debugRemoveReason or "direct"),
            tostring(timer.castFired == true),
            tostring(timer.trashReadyAt ~= nil),
            math.max(0, (tonumber(timer.castTime) or 0) - (GetTime() or 0))
        ))
        if IsCastBarDebugEnabled() then
            CastBarDebugPrint(string.format(
                "Scheduler trash-remove timer=%s spell=%s runtime=%s reason=%s castFired=%s ready=%s remaining=%.2f name=%s",
                tostring(timer.id),
                tostring(timer.spellID or "nil"),
                tostring(timer.trashRuntime),
                tostring(timer._debugRemoveReason or "direct"),
                tostring(timer.castFired == true),
                tostring(timer.trashReadyAt ~= nil),
                math.max(0, (tonumber(timer.castTime) or 0) - (GetTime() or 0)),
                tostring(timer.displayName or timer.baseDisplayName or "")
            ))
        end
        local bySpell = type(timer.trashRuntime.localTimerIDsBySpellID) == "table" and
            timer.trashRuntime.localTimerIDsBySpellID or nil
        if bySpell then
            bySpell[tonumber(timer.spellID)] = nil
        end
    end
    self._active[id] = nil
end

function Scheduler:CancelTrashLocalTimer(runtime, spellID)
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID)
    if not sid then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    if timerID then
        self:_RemoveActiveTimerByID(timerID)
    end
end

function Scheduler:CancelTrashLocalTimers(runtime)
    if type(runtime) ~= "table" then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    if type(bySpell) ~= "table" then
        return
    end
    local ids = {}
    for _, timerID in pairs(bySpell) do
        if tonumber(timerID) then
            ids[#ids + 1] = tonumber(timerID)
        end
    end
    for i = 1, #ids do
        self:_RemoveActiveTimerByID(ids[i])
    end
    wipe(bySpell)
end

function Scheduler:HandleTrashObservedCastSuccess(runtime, spellID)
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID)
    if not sid then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    local timer = timerID and self._active and self._active[timerID] or nil
    if type(timer) ~= "table" then
        return
    end
    timer.castFired = true
    CaptureLastFiredTimer(timer, GetTime())
    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:GetTrashLocalTimer(runtime, spellID)
    if type(runtime) ~= "table" then
        return nil
    end
    if type(spellID) ~= "number" then
        return nil
    end
    local sid = math.floor(spellID)
    if not sid then
        return nil
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    return timerID and self._active and self._active[timerID] or nil
end

local function BuildTrashObservedCastStartTrigger(runtime, spellID)
    local store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
    if not (store and type(store.GetResolvedSpellEntry) == "function") then
        return nil, "no store"
    end
    local mapID = tonumber(runtime and runtime.matchedMapID)
    local npcID = tonumber(runtime and runtime.matchedNPCID)
    local sid = tonumber(spellID)
    if not (mapID and npcID and sid) then
        return nil, "bad ids"
    end

    local cfg = store.GetResolvedSpellEntry(mapID, npcID, sid, false)
    if type(cfg) ~= "table" then
        return nil, "no cfg"
    end
    if cfg.enabled ~= true then
        return nil, "cfg disabled"
    end
    if TrashRuntimeConfig and type(TrashRuntimeConfig.IsRoleEnabled) == "function"
        and TrashRuntimeConfig.IsRoleEnabled(cfg) ~= true then
        return nil, "role disabled"
    end
    if cfg.voice1Enabled ~= true then
        return nil, "trigger1 disabled"
    end

    return {
        enabled = true,
        sourceType = tostring(cfg.voice1Source or "pack"),
        label = tostring(cfg.voice1Label or ""),
        customLSM = tostring(cfg.voice1LSM or ""),
        customPath = tostring(cfg.voice1Path or ""),
        fixedOffsetMode = tostring(cfg.voice1OffsetMode or "delay"),
        fixedOffsetSeconds = tonumber(cfg.voice1OffsetSeconds) or 0,
    }, nil
end

local function BuildTrashObservedCastStartDisplayTimer(runtime, spellID)
    local data = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
    if not (data and type(data.GetTrashCDDataRoot) == "function") then
        return nil, "no data"
    end
    if not (TrashRuntimeConfig and type(TrashRuntimeConfig.BuildResolvedMeta) == "function") then
        return nil, "no runtime-config"
    end

    local mapID = tonumber(runtime and runtime.matchedMapID)
    local npcID = tonumber(runtime and runtime.matchedNPCID)
    local sid = tonumber(spellID)
    if not (mapID and npcID and sid) then
        return nil, "bad ids"
    end

    local root = data.GetTrashCDDataRoot()
    local mapRow = type(root) == "table" and type(root[mapID]) == "table" and root[mapID] or nil
    local mobData = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs[npcID] or nil
    local spellData = mobData and type(mobData.spells) == "table" and mobData.spells[sid] or nil
    if type(mobData) ~= "table" or type(spellData) ~= "table" then
        return nil, "no spell-data"
    end

    local fallbackIcon = tonumber(spellData.iconFileID)
        or (type(data.GetSpellIconSafe) == "function" and tonumber(data.GetSpellIconSafe(sid)))
        or 136243
    local meta = TrashRuntimeConfig.BuildResolvedMeta(runtime, mobData, spellData, fallbackIcon)
    if type(meta) ~= "table" then
        return nil, "no meta"
    end

    local timer = {
        spellID = sid,
        spellIdentifier = sid,
        trashRuntime = runtime,
        trashNPCID = npcID,
        trashSpellData = spellData,
        baseDisplayName = tostring(meta.displayName or spellData.name or sid),
        displayName = tostring(meta.displayName or spellData.name or sid),
        iconFileID = tonumber(meta.iconFileID) or tonumber(spellData.iconFileID) or fallbackIcon,
    }
    ApplyTrashTimelineMeta(timer, meta)
    return timer, nil
end

local function NormalizeTrashCastStartVoiceCooldownMuteWindow(value)
    if value == nil or value == false then
        return nil
    end
    if value == true then
        return 0
    end
    if type(value) == "number" then
        if value <= 0 then
            return nil
        end
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local text = value:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end

    local lowered = string.lower(text)
    if lowered == "true" or text == "是" then
        return 0
    end
    if lowered == "false" or text == "否" then
        return nil
    end

    local suffixSeconds = text:match("^([%d%.]+)%s*[sS]$")
    if suffixSeconds then
        local numeric = tonumber(suffixSeconds)
        return (numeric and numeric > 0) and numeric or nil
    end

    local chineseSeconds = text:match("^([%d%.]+)%s*秒$")
    if chineseSeconds then
        local numeric = tonumber(chineseSeconds)
        return (numeric and numeric > 0) and numeric or nil
    end

    local numeric = tonumber(text)
    if not numeric or numeric <= 0 then
        return nil
    end
    return numeric
end

local function ShouldSuppressTrashCastStartVoiceByCooldown(timer)
    if type(timer) ~= "table" then
        return false, nil, nil
    end
    local spellData = type(timer.trashSpellData) == "table" and timer.trashSpellData or nil
    local muteWindow = NormalizeTrashCastStartVoiceCooldownMuteWindow(
        spellData and spellData.muteCastStartVoiceDuringCooldown
    )
    if muteWindow == nil then
        return false, nil, nil
    end

    local now = GetTime()
    local remaining = math.max(0, tonumber(timer.castTime or now) - now)
    if remaining > muteWindow then
        return true, remaining, muteWindow
    end
    return false, remaining, muteWindow
end

function Scheduler:PlayTrashObservedCastStartVoice(runtime, spellID)
    if type(runtime) == "table" and runtime.activeSpellAmbiguous == true then
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=ambiguous runtime=%s spell=%s kind=%s activeSpell=%s",
            tostring(runtime),
            tostring(spellID or "nil"),
            tostring(runtime and runtime.activeCastKind or ""),
            tostring(runtime and runtime.activeSpellID or "nil")
        ))
        return false
    end

    if type(runtime) ~= "table" then
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=bad-runtime spell=%s",
            tostring(spellID or "nil")
        ))
        return false
    end
    runtime._trashCastStartVoiceKeys = runtime._trashCastStartVoiceKeys or {}
    local dedupeKey = tostring(math.floor(tonumber(spellID) or 0)) ..
        ":" .. string.format("%.3f", tonumber(runtime.activeCastStartAt) or 0)
    if runtime._trashCastStartVoiceKeys[dedupeKey] == true then
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=duplicate runtime=%s spell=%s key=%s",
            tostring(runtime),
            tostring(spellID or "nil"),
            tostring(dedupeKey)
        ))
        return false
    end

    local timer = self:GetTrashLocalTimer(runtime, spellID)
    if type(timer) ~= "table" then
        local fallbackTimer, fallbackErr = BuildTrashObservedCastStartDisplayTimer(runtime, spellID)
        DispatchTrashObservedCastStartEvent(runtime, spellID, fallbackTimer)
        local progressShown = false
        if type(fallbackTimer) == "table" then
            progressShown = PlayTrashObservedCastStartRing(runtime, fallbackTimer, spellID) == true
            TrashVoiceDebugPrint(string.format(
                "cast-start ring-fallback runtime=%s spell=%s shown=%s err=%s",
                tostring(runtime),
                tostring(spellID or "nil"),
                tostring(progressShown),
                tostring(fallbackErr or "")
            ))
        else
            TrashVoiceDebugPrint(string.format(
                "cast-start ring-fallback-skip runtime=%s spell=%s err=%s",
                tostring(runtime),
                tostring(spellID or "nil"),
                tostring(fallbackErr or "")
            ))
        end

        local bySpell = type(runtime) == "table" and type(runtime.localTimerIDsBySpellID) == "table" and
            runtime.localTimerIDsBySpellID or nil
        local sid = tonumber(spellID)
        local mappedTimerID = sid and bySpell and tonumber(bySpell[sid]) or nil
        local mappedTimer = mappedTimerID and self._active and self._active[mappedTimerID] or nil
        local keys = {}
        if type(bySpell) == "table" then
            for k in pairs(bySpell) do
                keys[#keys + 1] = tostring(k)
            end
            table.sort(keys)
        end
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=no-timer runtime=%s spell=%s mapped=%s timerID=%s activePresent=%s keys=%s",
            tostring(runtime),
            tostring(spellID or "nil"),
            tostring(type(bySpell) == "table"),
            tostring(mappedTimerID or "nil"),
            tostring(type(mappedTimer) == "table"),
            (#keys > 0) and table.concat(keys, ",") or "-"
        ))
        local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
        if not (Engine and Engine.TryPlayStandaloneSound) then
            TrashVoiceDebugPrint(string.format(
                "cast-start skip reason=no-engine-standalone runtime=%s spell=%s",
                tostring(runtime),
                tostring(spellID or "nil")
            ))
            return false
        end
        local triggerCfg, triggerErr = BuildTrashObservedCastStartTrigger(runtime, spellID)
        if type(triggerCfg) ~= "table" then
            TrashVoiceDebugPrint(string.format(
                "cast-start skip reason=no-standalone-trigger runtime=%s spell=%s err=%s",
                tostring(runtime),
                tostring(spellID or "nil"),
                tostring(triggerErr or "")
            ))
            return false
        end
        TrashVoiceDebugPrint(string.format(
            "cast-start try-standalone runtime=%s spell=%s label=%s startAt=%.3f",
            tostring(runtime),
            tostring(spellID or "nil"),
            tostring(triggerCfg.label or ""),
            tonumber(runtime.activeCastStartAt) or 0
        ))
        local ok, err = Engine:TryPlayStandaloneSound(triggerCfg,
            "trash-cast:" .. tostring(runtime) .. ":" .. tostring(dedupeKey), {
                triggerIndex = 1,
                throttle = false,
            })
        TrashVoiceDebugPrint(string.format(
            "cast-start result-standalone runtime=%s spell=%s ok=%s err=%s",
            tostring(runtime),
            tostring(spellID or "nil"),
            tostring(ok),
            tostring(err or "")
        ))
        if ok == true then
            runtime._trashCastStartVoiceKeys[dedupeKey] = true
            DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, fallbackTimer)
        end
        return (ok == true), err
    end
    DispatchTrashObservedCastStartEvent(runtime, spellID, timer)
    PlayTrashObservedCastStartRing(runtime, timer, spellID)

    local voicePlan = type(timer.voicePlan) == "table" and timer.voicePlan or nil
    local triggerCfg = voicePlan and type(voicePlan.triggers) == "table" and voicePlan.triggers[1] or nil
    if not (type(triggerCfg) == "table" and triggerCfg.enabled == true) then
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=trigger1-disabled timer=%s spell=%s label=%s",
            tostring(timer.id),
            tostring(spellID or "nil"),
            tostring(timer.voiceLabel or "")
        ))
        return false
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=no-engine timer=%s spell=%s",
            tostring(timer.id),
            tostring(spellID or "nil")
        ))
        return false
    end

    local suppressByCooldown, cooldownRemaining, muteWindow = ShouldSuppressTrashCastStartVoiceByCooldown(timer)
    if suppressByCooldown == true then
        runtime._trashCastStartVoiceKeys[dedupeKey] = true
        timer.fixedVoiceTrigger1Fired = true
        timer.fixedVoiceTrigger1Enabled = false
        TrashVoiceDebugPrint(string.format(
            "cast-start skip reason=cooldown-mute timer=%s spell=%s remaining=%.2f window=%.2f",
            tostring(timer.id),
            tostring(spellID or "nil"),
            tonumber(cooldownRemaining) or 0,
            tonumber(muteWindow) or 0
        ))
        return false
    end

    TrashVoiceDebugPrint(string.format(
        "cast-start try timer=%s spell=%s event=%s label=%s startAt=%.3f",
        tostring(timer.id),
        tostring(spellID or "nil"),
        tostring(timer.eventID or "nil"),
        tostring(timer.voiceLabel or ""),
        tonumber(runtime.activeCastStartAt) or 0
    ))
    local ok, err = Engine:TryPlayForTimer(timer, 1)
    TrashVoiceDebugPrint(string.format(
        "cast-start result timer=%s spell=%s event=%s ok=%s err=%s",
        tostring(timer.id),
        tostring(spellID or "nil"),
        tostring(timer.eventID or "nil"),
        tostring(ok),
        tostring(err or "")
    ))
    if ok == true then
        runtime._trashCastStartVoiceKeys[dedupeKey] = true
        timer.fixedVoiceTrigger1Fired = true
        timer.fixedVoiceTrigger1Enabled = false
        DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, timer)
    end
    return ok, err
end

function Scheduler:EnsureTrashLocalRuntime()
    if self._running ~= true then
        self._running = true
        self._mode = "fixed"
        self._elapsed = ONUPDATE_INTERVAL
    end
    if self._frame then
        self._frame:Show()
    end
end

local function IsTrashFixedCombatTimelineSpell(spellData)
    return type(spellData) == "table" and spellData.fixedCombatTimeline == true
end

local function GetTrashFixedCombatTimelineStep(spellData)
    local seq = type(spellData) == "table" and type(spellData.cd) == "table" and spellData.cd or nil
    local step = seq and tonumber(seq[1]) or nil
    if step and step > 0 then
        return step
    end
    return nil
end

local function ResetTrashTimerForNextFixedCombatTimeline(timer, nextAt, now)
    local delay = math.max(0.1, nextAt - now)
    timer.baseCastTime = nextAt
    timer.castTime = nextAt
    timer.duration = math.max(delay, 30)
    timer.trashIconStartTime = now
    timer.trashIconDuration = delay
    timer.timerBarDuration = TIMERBAR_LEAD_TIME
    timer.preAlertFired = false
    timer.mechanicPreAlertFired = false
    timer.hintCountdownFired = false
    timer.hintCentralFired = false
    timer.castFired = false
    timer.centralFired = false
    timer.trashReadyAt = nil
    timer.bunBarShown = false
    timer.timerBarShown = false
    timer.fiveSecBroadcastFired = false
    if timer.countdownMode == "own" and timer.preAlertEnabled == true then
        timer.preAlertTime = nextAt - SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    else
        timer.preAlertTime = nil
    end
    ApplyFixedVoiceTriggerConfig(timer)
    timer.fixedVoiceTrigger1Enabled = false
    timer.fixedVoiceTrigger1Fired = true
end

function Scheduler:_AdvanceTrashFixedCombatTimeline(timer, now)
    if type(timer) ~= "table" or timer.trashFixedCombatTimeline ~= true then
        return false
    end
    local spellData = timer.trashSpellData
    local step = GetTrashFixedCombatTimelineStep(spellData)
    if not step then
        return false
    end
    local spellID = tonumber(timer.spellID)
    local scheduledAt = tonumber(timer.castTime) or now
    local nextAt = scheduledAt + step
    while nextAt <= now + 0.20 do
        nextAt = nextAt + step
    end

    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    ResetTrashTimerForNextFixedCombatTimeline(timer, nextAt, now)

    local runtime = type(timer.trashRuntime) == "table" and timer.trashRuntime or nil
    if runtime and spellID then
        runtime.nextSpellStartAt = runtime.nextSpellStartAt or {}
        runtime.nextSpellAnchorAt = runtime.nextSpellAnchorAt or {}
        runtime.nextSpellStartAt[spellID] = nextAt
        runtime.nextSpellAnchorAt[spellID] = tonumber(runtime.defaultAnchorAt) or tonumber(runtime.engagedAt) or now
    end
    return true
end

function Scheduler:RegisterTrashLocalTimer(runtime, mobData, spellData, remaining, meta)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(spellData) ~= "table" or type(meta) ~= "table" then
        return nil
    end
    if TrashRuntimeConfig then
        if type(TrashRuntimeConfig.IsDisabledInCurrentEncounter) == "function"
            and TrashRuntimeConfig.IsDisabledInCurrentEncounter() == true then
            return nil
        end
        if type(TrashRuntimeConfig.IsDisabledInBossEncounter) == "function"
            and TrashRuntimeConfig.IsDisabledInBossEncounter(self._encounterID) == true then
            return nil
        end
    end
    local delay = tonumber(remaining)
    local spellID = tonumber(spellData.spellID)
    if not delay or delay <= 0 or not spellID then
        return nil
    end

    self:EnsureTrashLocalRuntime()

    runtime.localTimerIDsBySpellID = runtime.localTimerIDsBySpellID or {}
    local now = GetTime()
    local timerID = tonumber(runtime.localTimerIDsBySpellID[spellID])
    local timer = timerID and self._active and self._active[timerID] or nil
    local isNewTimer = type(timer) ~= "table"

    if isNewTimer then
        timerID = self._nextTimerID
        self._nextTimerID = timerID + 1
        timer = {
            id = timerID,
            spellID = spellID,
            spellIdentifier = spellID,
            baseDisplayName = tostring(meta.displayName or spellData.name or spellID),
            displayName = tostring(meta.displayName or spellData.name or spellID),
            occurrenceCount = nil,
            baseCastTime = now + delay,
            castTime = now + delay,
            duration = math.max(delay, 30),
            trashIconDuration = delay,
            trashIconStartTime = now,
            timerBarDuration = TIMERBAR_LEAD_TIME,
            preAlertTime = nil,
            barPriority = 2,
            showBunBar = true,
            showTimerBar = true,
            showNameplate = false,
            nameplateSide = "right",
            headAlert = false,
            screenAlert = false,
            preAlertText = nil,
            screenText = nil,
            centralLead = 0,
            voiceLabel = nil,
            source = "trash",
            eventID = nil,
            eventColor = nil,
            preAlertFired = false,
            mechanicPreAlertFired = false,
            hintCountdownFired = false,
            hintCentralFired = false,
            castFired = false,
            bunBarShown = false,
            timerBarShown = false,
            fiveSecBroadcastFired = false,
            timelineManaged = false,
            timelineEventID = nil,
            timelinePreAlertLead = DEFAULT_PREALERT_SECS,
            centralFired = false,
            trashRuntime = runtime,
            trashNPCID = tonumber(mobData.npcID),
            trashSpellData = spellData,
            trashFixedCombatTimeline = IsTrashFixedCombatTimelineSpell(spellData),
        }
        self._active[timerID] = timer
        runtime.localTimerIDsBySpellID[spellID] = timerID
    end

    timer.spellID = spellID
    timer.spellIdentifier = spellID
    timer.iconFileID = tonumber(meta.iconFileID) or tonumber(spellData.iconFileID)
    timer.baseDisplayName = tostring(meta.displayName or spellData.name or spellID)
    timer.displayName = timer.baseDisplayName
    local newCastTime = now + delay
    local oldCastTime = tonumber(timer.castTime)
    local oldIconStartTime = tonumber(timer.trashIconStartTime)
    local resetIconCooldown = isNewTimer
        or oldIconStartTime == nil
        or timer.castFired == true
        or timer.trashReadyAt ~= nil
        or oldCastTime == nil
        or math.abs(newCastTime - oldCastTime) > 0.75

    timer.baseCastTime = newCastTime
    timer.castTime = newCastTime
    timer.duration = math.max(delay, 30)
    if resetIconCooldown then
        timer.trashIconStartTime = now
        timer.trashIconDuration = delay
    else
        timer.trashIconDuration = math.max(0.1, newCastTime - oldIconStartTime)
    end
    timer.timerBarDuration = TIMERBAR_LEAD_TIME
    timer.preAlertTime = nil
    timer.preAlertFired = false
    timer.mechanicPreAlertFired = false
    timer.hintCountdownFired = false
    timer.hintCentralFired = false
    timer.castFired = false
    timer.centralFired = false
    timer.trashReadyAt = nil
    timer.trashRuntime = runtime
    timer.trashNPCID = tonumber(mobData.npcID)
    timer.trashSpellData = spellData
    timer.trashFixedCombatTimeline = IsTrashFixedCombatTimelineSpell(spellData)

    ApplyTrashTimelineMeta(timer, meta)
    if timer.countdownMode == "own" and timer.preAlertEnabled == true then
        timer.preAlertTime = (now + delay) - SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    end
    ApplyFixedVoiceTriggerConfig(timer)
    -- 小怪“施法开始”语音必须由真实 UNIT_SPELLCAST_START / CHANNEL_START 触发；
    -- 本地 CD 计时到点只表示技能可用，不代表怪物已经开始施法。
    timer.fixedVoiceTrigger1Enabled = false
    timer.fixedVoiceTrigger1Fired = true

    TrashVoiceDebugPrint(string.format(
        "local-timer bind runtime=%s timer=%s spell=%s isNew=%s delay=%.2f cast=%.3f name=%s",
        tostring(runtime),
        tostring(timerID),
        tostring(spellID),
        tostring(isNewTimer),
        tonumber(delay) or 0,
        tonumber(timer.castTime) or 0,
        tostring(timer.displayName or timer.baseDisplayName or "")
    ))

    return timerID
end

function Scheduler:GetTrashNameplateTimers(runtime, now)
    if type(runtime) ~= "table" then
        return {}
    end
    now = tonumber(now) or GetTime()
    local out = {}
    local debugMatches = nil
    if IsCastBarDebugEnabled() then
        debugMatches = {}
    end
    for _, timer in pairs(self._active or {}) do
        if debugMatches and type(timer) == "table" and timer.source == "trash" and timer.trashRuntime == runtime then
            debugMatches[#debugMatches + 1] = string.format(
                "timer=%s spell=%s show=%s castFired=%s ready=%s remain=%.2f",
                tostring(timer.id),
                tostring(timer.spellID or "nil"),
                tostring(timer.showNameplate == true),
                tostring(timer.castFired == true),
                tostring(timer.trashReadyAt ~= nil),
                math.max(0, tonumber(timer.castTime or now) - now)
            )
        end
        if type(timer) == "table"
            and timer.source == "trash"
            and timer.trashRuntime == runtime
            and timer.showNameplate == true
            and (timer.castFired ~= true or timer.trashReadyAt ~= nil) then
            out[#out + 1] = {
                spellID = tonumber(timer.spellID),
                iconFileID = tonumber(timer.iconFileID),
                displayName = tostring(timer.displayName or timer.baseDisplayName or ""),
                remaining = math.max(0, tonumber(timer.castTime or now) - now),
                duration = math.max(0, tonumber(timer.trashIconDuration) or tonumber(timer.duration) or 0),
                startTime = tonumber(timer.trashIconStartTime),
                ready = (timer.trashReadyAt ~= nil),
                side = (tostring(timer.nameplateSide or "right") == "left") and "left" or "right",
            }
        end
    end
    if debugMatches then
        if #debugMatches > 0 then
            CastBarDebugPrint("Scheduler trash-nameplate-scan runtime=" ..
                tostring(runtime) .. " " .. table.concat(debugMatches, " | "))
        else
            CastBarDebugPrint("Scheduler trash-nameplate-scan runtime=" .. tostring(runtime) .. " no-bound-trash-timers")
        end
    end
    table.sort(out, function(a, b)
        local ar = tonumber(a and a.remaining) or 0
        local br = tonumber(b and b.remaining) or 0
        if ar == br then
            return (tonumber(a and a.spellID) or 0) < (tonumber(b and b.spellID) or 0)
        end
        return ar < br
    end)
    return out
end

local function ShouldIgnoreFixedAIStateChangeNearDeadline(timer, now)
    if type(timer) ~= "table" or timer.source ~= "fixed_ai" then
        return false
    end
    if tostring(timer.finishMode or ""):lower() ~= "timer" then
        return false
    end
    local window = tonumber(timer.timerFinishIgnoreStateWindow)
    if not window or window <= 0 then
        return false
    end
    now = tonumber(now) or GetTime()
    local castTime = SafeToNumber(timer.castTime)
    if not castTime then
        return false
    end
    return (castTime - now) <= window
end

local function ShouldPauseFixedAITimer(timer)
    if type(timer) ~= "table" or timer.source ~= "fixed_ai" then
        return false
    end
    return FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS[SafeToNumber(Scheduler._encounterID) or 0] == true
end

local function ShiftFixedAITimerForPause(timer, delta)
    if type(timer) ~= "table" then
        return
    end
    delta = tonumber(delta)
    if not delta or delta <= 0 then
        return
    end

    if timer.castTime then
        timer.castTime = tonumber(timer.castTime) + delta
    end
    if timer.preAlertTime then
        timer.preAlertTime = tonumber(timer.preAlertTime) + delta
    end
    if timer.fixedAICastStartListenAt then
        timer.fixedAICastStartListenAt = tonumber(timer.fixedAICastStartListenAt) + delta
    end
    if timer.fixedAICastStartDeadline then
        timer.fixedAICastStartDeadline = tonumber(timer.fixedAICastStartDeadline) + delta
    end
end

local function ApplyFixedAIPausedState(timer, now)
    if not ShouldPauseFixedAITimer(timer) or timer.castFired == true then
        return false
    end
    if timer.fixedAIPausedAt then
        timer.fixedAIPausedTick = tonumber(now) or GetTime()
        return true
    end
    timer.fixedAIPausedAt = tonumber(now) or GetTime()
    timer.fixedAIPausedTick = timer.fixedAIPausedAt
    timer.fixedAIPaused = true
    timer.fixedAIWasPaused = true
    return true
end

local function ResumeFixedAIPausedState(timer, now)
    if type(timer) ~= "table" or timer.fixedAIPausedAt == nil then
        return false
    end
    timer.fixedAIPausedAt = nil
    timer.fixedAIPausedTick = nil
    timer.fixedAIPaused = nil
    return true
end

local function ShouldKeepFixedAIAfterPauseRemoved(encounterID, timer)
    return type(timer) == "table"
        and timer.source == "fixed_ai"
        and FIXED_AI_KEEP_AFTER_PAUSE_REMOVED_ENCOUNTERS[SafeToNumber(encounterID) or 0] == true
        and (timer.fixedAIWasPaused == true or timer.fixedAIPaused == true)
end

local function DetachFixedAITimelineKeepLocal(scheduler, timer, timelineEventID, reason)
    if type(timer) ~= "table" then
        return false
    end
    ResumeFixedAIPausedState(timer, GetTime())
    timer.fixedAITimelineEventID = nil
    timer.fixedAIKeepAfterPauseRemoved = true
    if type(scheduler) == "table" and type(scheduler._fixedAIEventToTimer) == "table" then
        scheduler._fixedAIEventToTimer[timelineEventID] = nil
    end
    AIVoiceDebugPrint(scheduler, timer, string.format(
        "%s timeline=%s %s %s",
        tostring(reason or "timeline keep-local"),
        tostring(timelineEventID),
        FixedAITimerDebugState(timer),
        FixedAIMapDebugText(scheduler)
    ))
    return true
end

IsFixedAICastStartFinishMode = function(timer)
    return type(timer) == "table"
        and timer.source == "fixed_ai"
        and tostring(timer.finishMode or ""):lower() == "cast_start"
end

local function GetFixedAICastStartListenLead(_timer)
    return 0.1
end

local function GetFixedAICastStartDeadlineOffset(_timer)
    return 2.0
end

local function TryEnterFixedAICastStartWait(timer, now)
    if not IsFixedAICastStartFinishMode(timer) or timer.castFired == true then
        return false
    end
    now = tonumber(now) or GetTime()
    local castTime = SafeToNumber(timer.castTime)
    if not castTime then
        return false
    end
    local listenLead = GetFixedAICastStartListenLead(timer)
    local deadlineOffset = GetFixedAICastStartDeadlineOffset(timer)
    local listenAt = castTime - listenLead
    local deadline = castTime + deadlineOffset
    if now < listenAt or now > deadline then
        return false
    end
    timer.fixedAIWaitingCastStart = true
    timer.fixedAICastStartListenAt = listenAt
    timer.fixedAICastStartDeadline = deadline
    return true
end

local function UnitAllowedForFixedAICastStart(timer, unit)
    local allowedUnit = tostring(type(timer) == "table" and timer.castStartUnit or "")
    if allowedUnit == "" or allowedUnit == "boss" then
        return IsBossCastObserveUnit(unit)
    end
    return allowedUnit == tostring(NormalizeUnitToken(unit) or "")
end

function Scheduler:RebindTrashRuntime(oldRuntime, newRuntime)
    if type(oldRuntime) ~= "table" or type(newRuntime) ~= "table" or oldRuntime == newRuntime then
        return 0
    end
    local rebound = 0
    for _, timer in pairs(self._active or {}) do
        if type(timer) == "table" and timer.source == "trash" and timer.trashRuntime == oldRuntime then
            timer.trashRuntime = newRuntime
            rebound = rebound + 1
        end
    end
    if rebound > 0 and IsCastBarDebugEnabled() then
        CastBarDebugPrint(string.format(
            "Scheduler rebind-trash-runtime count=%d old=%s new=%s",
            rebound,
            tostring(oldRuntime),
            tostring(newRuntime)
        ))
    end
    return rebound
end

function Scheduler:_ScheduleClearActiveSnapshot(triggerTimer)
    local delay = tonumber(triggerTimer and triggerTimer.clearActiveSnapshotAfter)
    if not delay or delay <= 0 then
        return
    end

    local triggerID = tonumber(triggerTimer and triggerTimer.id)
    self:_ResetFixedAIPreEventLimits(tonumber(triggerTimer and triggerTimer.eventID) or
        tonumber(triggerTimer and triggerTimer.timelineEventID))
    local snapshot = {}
    for timerID, timer in pairs(self._active) do
        if timerID ~= triggerID and type(timer) == "table" and timer.castFired ~= true then
            snapshot[#snapshot + 1] = timerID
        end
    end
    if #snapshot == 0 then
        return
    end

    local sessionToken = tonumber(self._sessionToken) or 0
    local encounterID = self._encounterID
    C_Timer.After(delay, function()
        if sessionToken ~= (tonumber(Scheduler._sessionToken) or 0) then
            return
        end
        if Scheduler._running ~= true or Scheduler._encounterID ~= encounterID then
            return
        end
        for i = 1, #snapshot do
            Scheduler:_RemoveActiveTimerByID(snapshot[i])
        end
    end)
end

function Scheduler:_FlushFixedAIPendingEvents(now)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then return end
    local pending = self._fixedAIPendingEvents
    if type(pending) ~= "table" or #pending == 0 then return end
    now = tonumber(now) or GetTime()

    while #pending > 0 do
        local first = pending[1]
        local firstAt = tonumber(first and first.receivedAt)
        if not firstAt then
            table.remove(pending, 1)
        elseif (now - firstAt) < FIXED_AI_SYNC_WINDOW then
            break
        else
            local batch = {}
            local windowEnd = firstAt + FIXED_AI_SYNC_WINDOW
            while #pending > 0 do
                local row = pending[1]
                local rowAt = tonumber(row and row.receivedAt)
                if not rowAt or rowAt <= windowEnd then
                    table.insert(batch, row)
                    table.remove(pending, 1)
                else
                    break
                end
            end
            local filtered = self:_FilterTimelineAddedBatch(batch, now)
            if filtered and #filtered > 0 then
                local syncMode = self:_CountFixedAISyncRuleMatches(filtered) >= 2
                    or self:_HasFixedAIPausedSyncAccepted(filtered)
                    or self:_HasFixedAICanceledResumeSnapshotReady(filtered)
                self:_ProcessFixedAIPendingBatch(filtered, syncMode)
            end
        end
    end
end

function Scheduler:_OnFixedTimeTimelineEventAdded(eventInfo)
    if not FIXED_TIME_OFFSET_CALIBRATION_ENABLED then return end
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_TIME) then return end
    if type(eventInfo) ~= "table" then return end

    local timelineEventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not timelineEventID or not duration then return end
    if not IsEncounterTimelineSource(eventInfo.source) or not IsTimelineDurationAllowed(duration) then return end

    local oldTimerID = self._fixedTimeEventToTimer[timelineEventID]
    if oldTimerID then
        self._active[oldTimerID] = nil
        self._fixedTimeEventToTimer[timelineEventID] = nil
    end

    local observedCastAt = GetTime() + math.max(0, duration)
    local timerID = self:_FindBestFixedTimeTimer(observedCastAt)
    if not timerID then
        return
    end

    local timer = self._active[timerID]
    if not timer then
        return
    end

    local baseCast = tonumber(timer.baseCastTime) or tonumber(timer.castTime)
    if baseCast then
        self:_ApplyFixedTimeOffset(observedCastAt - baseCast)
        timer = self._active[timerID] or timer
    end

    timer.fixedTimelineMatched = true
    timer.fixedTimeTimelineEventID = timelineEventID
    self._fixedTimeEventToTimer[timelineEventID] = timerID
end

function Scheduler:_TryHoldFixedAIForTimelineFinish(timer, now)
    if type(timer) ~= "table"
        or timer.source ~= "fixed_ai"
        or timer.finishMode == "timer"
        or timer.castFired == true then
        return false
    end

    local timelineEventID = SafeToNumber(timer.fixedAITimelineEventID)
    if not timelineEventID then
        return false
    end

    local state = self:_GetTimelineState(timelineEventID)
    if state ~= STATE_ACTIVE and state ~= STATE_PAUSED then
        return false
    end

    now = tonumber(now) or GetTime()
    local startedAt = tonumber(timer.fixedAITimelineFinishWaitStartedAt)
    if not startedAt then
        startedAt = now
        timer.fixedAITimelineFinishWaitStartedAt = startedAt
    end

    local timeout = tonumber(timer.timelineFinishTimeout)
    if not timeout and timer.waitTimelineFinish == true then
        timeout = FIXED_AI_TIMELINE_FINISH_TIMEOUT
    end
    if timeout and timeout > 0 and (now - startedAt) >= timeout then
        timer.fixedAIWaitingTimelineFinish = false
        timer.fixedAITimelineFinishTimedOut = true
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline wait timeout timer=%s event=%s timeline=%s waited=%.2f state=%s %s",
            tostring(timer.id),
            tostring(timer.eventID),
            tostring(timelineEventID),
            now - startedAt,
            tostring(state),
            AIVoiceTimerTimingText(timer)
        ))
        return false
    end

    if timer.fixedAIWaitingTimelineFinish ~= true then
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline wait start timer=%s event=%s timeline=%s timeout=%.2f state=%s %s",
            tostring(timer.id),
            tostring(timer.eventID),
            tostring(timelineEventID),
            tonumber(timeout) or 0,
            tostring(state),
            AIVoiceTimerTimingText(timer)
        ))
    end
    timer.fixedAIWaitingTimelineFinish = true
    if timer.fixedVoiceTrigger1Fired == true or timer.fixedVoiceTrigger2Fired == true then
        timer.fixedVoiceCastFallbackTried = true
    end
    timer.castTime = now
    return true
end

function Scheduler:_OnFixedAITimelineEventAdded(eventInfo)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then return end
    if type(eventInfo) ~= "table" then return end

    local timelineEventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not timelineEventID or not duration then return end
    if not IsEncounterTimelineSource(eventInfo.source) or not IsTimelineDurationAllowed(duration) then return end
    AIVoiceDebugPrint(self, nil, string.format(
        "timeline added timeline=%s duration=%.2f source=%s",
        tostring(timelineEventID), tonumber(duration) or 0, tostring(eventInfo.source)
    ))
    table.insert(self._fixedAIPendingEvents, {
        timelineEventID = timelineEventID,
        duration = duration,
        receivedAt = GetTime(),
    })
end

function Scheduler:_ShouldUseFixedAIRemovedSync()
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return false
    end
    return FIXED_AI_REMOVED_SYNC_ENCOUNTERS[SafeToNumber(self._encounterID) or 0] == true
end

function Scheduler:_RemoveFixedAIPendingTimelineEvent(timelineEventID)
    local id = SafeToNumber(timelineEventID)
    local pending = self._fixedAIPendingEvents
    if not id or type(pending) ~= "table" then
        return false
    end
    local removed = false
    for i = #pending, 1, -1 do
        local row = pending[i]
        if SafeToNumber(row and row.timelineEventID) == id then
            table.remove(pending, i)
            removed = true
        end
    end
    return removed
end

function Scheduler:_TriggerFixedAITimerCast(timer, now, debugReason, suppressVoice)
    if type(timer) ~= "table" or timer.castFired == true then
        return false
    end
    now = tonumber(now) or GetTime()

    timer.fixedAIPausedAt = nil
    timer.fixedAIPausedTick = nil
    timer.fixedAIPaused = nil
    timer.fixedAIWaitingTimelineFinish = false
    timer.fixedAIWaitingCastStart = false
    timer.fixedAICastStartListenAt = nil
    timer.fixedAICastStartDeadline = nil
    timer.fixedAICastStartNextPollAt = nil
    timer.castTime = now
    timer.fixedAICompletingFromFinished = true

    if suppressVoice ~= true then
        TryFireFixedVoiceTriggers(timer, now)
        if timer.fixedVoiceTrigger1Fired == true then
            timer.fixedVoiceCastFallbackTried = true
        end
    end
    timer.castFired = true
    CaptureLastFiredTimer(timer, now)
    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    PublishFixedAIEventFinished(self, timer)
    if timer.clearActiveSnapshotAfter then
        self:_ScheduleClearActiveSnapshot(timer)
    end
    if suppressVoice ~= true then
        EnsureFixedVoiceAtCast(timer)
    end
    timer.fixedAICompletingFromFinished = false
    timer._debugRemoveReason = tostring(debugReason or "fixed-ai-cast")
    return true
end

function Scheduler:_CompleteFixedAITimerFromFinished(timerID)
    local id = SafeToNumber(timerID)
    local timer = id and self._active and self._active[id] or nil
    if type(timer) ~= "table" then
        return
    end

    local now = GetTime()
    local castTime = SafeToNumber(timer.castTime) or now
    local remaining = castTime - now
    if timer.castFired ~= true and (timer.source == "fixed_ai"
            or timer.waitTimelineFinish == true
            or timer.fixedAIWaitingTimelineFinish == true
            or remaining <= FIXED_AI_FINISHED_TRIGGER_GRACE) then
        AIVoiceDebugPrint(self, timer, string.format(
            "finish-complete timer=%s event=%s %s name=%s",
            tostring(timer.id),
            tostring(timer.eventID),
            AIVoiceTimerTimingText(timer),
            tostring(timer.displayName or timer.baseDisplayName or "")
        ))
        self:_TriggerFixedAITimerCast(timer, now, "state-finished-complete")
    elseif timer.castFired ~= true then
        AIVoiceDebugPrint(self, timer, string.format(
            "finish-skip-far timer=%s event=%s %s grace=%.2f name=%s",
            tostring(timer.id),
            tostring(timer.eventID),
            AIVoiceTimerTimingText(timer),
            FIXED_AI_FINISHED_TRIGGER_GRACE,
            tostring(timer.displayName or timer.baseDisplayName or "")
        ))
        timer._debugRemoveReason = "state-finished-far"
    else
        timer._debugRemoveReason = "state-finished-fired"
    end

    self:_RemoveActiveTimerByID(id)
end

function Scheduler:_FindFixedAICastStartTimer(unit, _eventKind, now)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return nil
    end
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    now = tonumber(now) or GetTime()
    local bestTimer = nil
    local bestDelta = math.huge
    for _, timer in pairs(self._active or {}) do
        if TryEnterFixedAICastStartWait(timer, now) then
            if UnitAllowedForFixedAICastStart(timer, unit) then
                local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                if now <= deadline then
                    local delta = math.abs((tonumber(timer.castTime) or now) - now)
                    if delta < bestDelta then
                        bestDelta = delta
                        bestTimer = timer
                    end
                end
            end
        end
    end
    return bestTimer
end

function Scheduler:_OnBossSpellcastBoundary(unit, eventKind)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return
    end
    local now = GetTime()
    local timer = self:_FindFixedAICastStartTimer(unit, eventKind, now)
    if not timer then
        return
    end
    local suppressVoice = (timer.source == "fixed_ai" and IsFixedAICastStartFinishMode(timer))
    if suppressVoice then
        timer.fixedAIVoicePendingByFinish = true
    end
    if self:_TriggerFixedAITimerCast(timer, now, "boss-" .. tostring(eventKind) .. "-start", suppressVoice) then
        if suppressVoice ~= true then
            self:_RemoveActiveTimerByID(timer.id)
        end
    end
end

function Scheduler:_OnFixedTimeTimelineEventRemoved(eventID)
    if not FIXED_TIME_OFFSET_CALIBRATION_ENABLED then return end
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_TIME) then return end
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedTimeEventToTimer[timelineEventID]
    if not timerID then return end

    self._fixedTimeEventToTimer[timelineEventID] = nil
    self._active[timerID] = nil
end

function Scheduler:_OnFixedAITimelineEventRemoved(eventID)
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedAIEventToTimer[timelineEventID]
    local timer = timerID and self._active[timerID] or nil
    if ShouldIgnoreFixedAIStateChangeNearDeadline(timer, GetTime()) then
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline removed ignored near-deadline timer=%s event=%s timeline=%s %s",
            tostring(timer and timer.id),
            tostring(timer and timer.eventID),
            tostring(timelineEventID),
            AIVoiceTimerTimingText(timer)
        ))
        return
    end
    if type(timer) == "table" and timer.finishMode == "timer" then
        return
    end
    if type(timer) == "table" and timer.fixedAIVoicePendingByFinish == true and timer.fixedAIVoiceReleased ~= true then
        ReleaseFixedAIVoiceAtCastTime(timer, GetTime())
    end
    if TryEnterFixedAICastStartWait(timer, GetTime()) then
        ReleaseFixedAIVoiceAtCastTime(timer, GetTime())
        return
    end
    local syncEnabled = self:_ShouldUseFixedAIRemovedSync()
        or (type(timer) == "table" and timer.source == "fixed_ai")
        or (type(timer) == "table" and timer.waitTimelineFinish == true)
    if not syncEnabled then
        AIVoiceDebugPrint(self, nil, string.format(
            "timeline removed ignored sync-disabled encounter=%s timeline=%s %s",
            tostring(self._encounterID),
            tostring(timelineEventID),
            FixedAIMapDebugText(self)
        ))
        return
    end

    local pendingRemoved = self:_RemoveFixedAIPendingTimelineEvent(timelineEventID)

    if not timerID then
        AIVoiceDebugPrint(self, nil, string.format(
            "timeline removed no-map timeline=%s pendingRemoved=%s %s",
            tostring(timelineEventID),
            tostring(pendingRemoved),
            FixedAIMapDebugText(self)
        ))
        return
    end

    if ShouldKeepFixedAIAfterPauseRemoved(self._encounterID, timer) then
        DetachFixedAITimelineKeepLocal(self, timer, timelineEventID, "timeline removed keep-after-pause")
        return
    end

    if timer then
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline removed will-remove timeline=%s reason=no-keep-after-pause %s %s",
            tostring(timelineEventID),
            FixedAITimerDebugState(timer),
            FixedAIMapDebugText(self)
        ))
        timer._debugRemoveReason = "timeline-removed"
    end
    AIVoiceDebugPrint(self, timer, string.format(
        "timeline removed matched timeline=%s timer=%s %s",
        tostring(timelineEventID),
        tostring(timerID),
        FixedAIMapDebugText(self)
    ))
    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:_OnFixedAITimelineEventStateChanged(eventID)
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedAIEventToTimer[timelineEventID]
    local timer = timerID and self._active[timerID] or nil
    local state = self:_GetTimelineState(timelineEventID)
    local now = GetTime()
    if state == STATE_CANCELED then
        local remainBefore = timer and ((SafeToNumber(timer.castTime) or now) - now) or nil
        self:_CaptureFixedAICanceledResumeSnapshot(timer, timelineEventID, remainBefore, now)
    end
    local syncEnabled = self:_ShouldUseFixedAIRemovedSync()
        or (type(timer) == "table" and timer.source == "fixed_ai")
    if not syncEnabled then
        AIVoiceDebugPrint(self, nil, string.format(
            "timeline state ignored sync-disabled encounter=%s timeline=%s %s",
            tostring(self._encounterID),
            tostring(timelineEventID),
            FixedAIMapDebugText(self)
        ))
        return
    end

    AIVoiceDebugPrint(self, nil, string.format(
        "timeline state timeline=%s state=%s %s",
        tostring(timelineEventID), tostring(state), FixedAIMapDebugText(self)
    ))
    if ShouldIgnoreFixedAIStateChangeNearDeadline(timer, now) then
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline state ignored near-deadline timer=%s event=%s timeline=%s state=%s %s",
            tostring(timer and timer.id),
            tostring(timer and timer.eventID),
            tostring(timelineEventID),
            tostring(state),
            AIVoiceTimerTimingText(timer)
        ))
        return
    end
    if state == STATE_PAUSED then
        ApplyFixedAIPausedState(timer, now)
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline paused accepted timeline=%s %s %s",
            tostring(timelineEventID),
            FixedAITimerDebugState(timer),
            FixedAIMapDebugText(self)
        ))
        return
    end
    if state == STATE_ACTIVE then
        ResumeFixedAIPausedState(timer, now)
        AIVoiceDebugPrint(self, timer, string.format(
            "timeline active resume timeline=%s %s %s",
            tostring(timelineEventID),
            FixedAITimerDebugState(timer),
            FixedAIMapDebugText(self)
        ))
        return
    end
    if type(timer) == "table" and timer.fixedAIVoicePendingByFinish == true and timer.fixedAIVoiceReleased ~= true then
        ReleaseFixedAIVoiceAtCastTime(timer, now)
    end
    if TryEnterFixedAICastStartWait(timer, now) then
        ReleaseFixedAIVoiceAtCastTime(timer, now)
        return
    end

    local pendingRemoved = self:_RemoveFixedAIPendingTimelineEvent(timelineEventID)

    if not timerID then
        AIVoiceDebugPrint(self, nil, string.format(
            "timeline state no-map timeline=%s state=%s pendingRemoved=%s %s",
            tostring(timelineEventID),
            tostring(state),
            tostring(pendingRemoved),
            FixedAIMapDebugText(self)
        ))
        return
    end

    if state == STATE_CANCELED and ShouldKeepFixedAIAfterPauseRemoved(self._encounterID, timer) then
        DetachFixedAITimelineKeepLocal(self, timer, timelineEventID, "timeline canceled keep-after-pause")
        return
    end

    if state == STATE_FINISHED then
        self:_CompleteFixedAITimerFromFinished(timerID)
        return
    end

    if timer then
        timer.fixedAIPausedAt = nil
        timer.fixedAIPausedTick = nil
        timer.fixedAIPaused = nil
        timer._debugRemoveReason = "state-changed:" .. tostring(state)
    end
    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:ScheduleFixedAIVirtualEvent(eventID, duration, key, options)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return nil
    end

    local eid = SafeToNumber(eventID)
    local dur = SafeToNumber(duration)
    if not eid or not dur then
        return nil
    end

    if type(options) == "table" then
        local expectedEncounterID = SafeToNumber(options.encounterID)
        if expectedEncounterID and expectedEncounterID ~= SafeToNumber(self._encounterID) then
            return nil
        end
    end

    local skill = type(self._fixedAISkillByEventID) == "table" and self._fixedAISkillByEventID[eid] or nil
    if type(skill) ~= "table" then
        local rows = GetEncounterEventRows(self._encounterID)
        local row = type(rows) == "table" and rows[eid] or nil
        skill = BuildRuntimeSkillFromEvent(eid, row)
        if type(skill) == "table" then
            self._fixedAISkillByEventID = type(self._fixedAISkillByEventID) == "table" and self._fixedAISkillByEventID or
                {}
            self._fixedAISkillByEventID[eid] = skill
        end
    end
    if type(skill) ~= "table" then
        return nil
    end

    local observedAt = type(options) == "table" and SafeToNumber(options.observedAt) or nil
    observedAt = observedAt or GetTime()
    local castTime = observedAt + math.max(0, dur)
    local timerID = self:_AddTimer(skill, castTime, "fixed_ai")
    local timer = timerID and self._active[timerID] or nil
    if not timer then
        return nil
    end

    timer.fixedAIVirtual = true
    timer.fixedAIVirtualKey = tostring(key or eid)
    timer.fixedAIVirtualEventID = eid

    PublishFixedAIEventScheduled(self, timer, eid, dur, observedAt, castTime, false)
    return timerID
end

function Scheduler:CancelFixedAIVirtualEvents(key)
    local expectedKey = key ~= nil and tostring(key) or nil
    local removed = 0
    if type(self._active) ~= "table" then
        return removed
    end

    for timerID, timer in pairs(self._active) do
        if type(timer) == "table"
            and timer.fixedAIVirtual == true
            and (not expectedKey or timer.fixedAIVirtualKey == expectedKey) then
            self:_RemoveActiveTimerByID(timerID)
            removed = removed + 1
        end
    end

    return removed
end

function Scheduler:_ExpandAndSchedule(skill, battleStart)
    local first = tonumber(skill and skill.first)
    if not first then
        return nil
    end
    local castTime = battleStart + first
    local limit = battleStart + MAX_ENCOUNTER_DURATION
    if castTime > limit then
        return nil
    end

    local timerID = self:_AddTimer(skill, castTime, "fixed")
    local timer = timerID and self._active[timerID] or nil
    if timer then
        timer.fixedBattleStart = battleStart
        timer.fixedIntervalIndex = 1
    end
    return timerID
end

function Scheduler:_ScheduleNextFixedOccurrence(timer)
    if type(timer) ~= "table" or timer.source ~= "fixed" then
        return nil
    end

    local skill = timer.skillDef
    if type(skill) ~= "table" or skill.interval == nil then
        return nil
    end

    local interval = skill.interval
    local index = tonumber(timer.fixedIntervalIndex) or 1
    local delay = type(interval) == "table" and tonumber(interval[index]) or tonumber(interval)
    if not delay or delay <= 0 then
        return nil
    end

    local currentCast = tonumber(timer.castTime)
    local battleStart = tonumber(timer.fixedBattleStart)
    if not currentCast or not battleStart then
        return nil
    end

    local nextCast = currentCast + delay
    if nextCast > (battleStart + MAX_ENCOUNTER_DURATION) then
        return nil
    end

    local nextTimerID = self:_AddTimer(skill, nextCast, "fixed")
    local nextTimer = nextTimerID and self._active[nextTimerID] or nil
    if nextTimer then
        nextTimer.fixedBattleStart = battleStart
        nextTimer.fixedIntervalIndex = type(interval) == "table" and ((index % #interval) + 1) or 1
    end
    return nextTimerID
end

function Scheduler:_NextOccurrenceCount(skill, source)
    local key = ResolveOccurrenceKey(skill, source)
    if not key then
        return nil
    end
    self._occurrenceCounts = type(self._occurrenceCounts) == "table" and self._occurrenceCounts or {}
    local nextCount = (tonumber(self._occurrenceCounts[key]) or 0) + 1
    self._occurrenceCounts[key] = nextCount
    return nextCount
end

function Scheduler:_ApplyTimerDisplayName(timer)
    if type(timer) ~= "table" then
        return
    end
    local baseName = timer.baseDisplayName or timer.displayName
    timer.baseDisplayName = baseName
    timer.displayName = baseName
end

function Scheduler:_AddTimer(skill, castTime, source)
    local id = self._nextTimerID
    self._nextTimerID = id + 1
    local occurrenceCount = self:_NextOccurrenceCount(skill, source)

    local timer = {
        id                    = id,
        spellID               = skill.spellID,
        spellIdentifier       = skill.evenSpellID or skill.spellIdentifier or skill.spellID,
        iconFileID            = ResolveSpellIconFileID(skill.evenSpellID or skill.spellIdentifier or skill.spellID,
            skill.spellID, skill.iconFileID),
        baseDisplayName       = skill.displayName,
        displayName           = skill.displayName,
        occurrenceCount       = occurrenceCount,
        baseCastTime          = castTime,
        castTime              = castTime,
        duration              = skill.preAlert and (skill.preAlert + (skill.castDuration or 0)) or 30,
        timerBarDuration      = TIMERBAR_LEAD_TIME,
        preAlertTime          = skill.preAlert and (castTime - skill.preAlert) or nil,
        barPriority           = skill.barPriority or 2,
        showBunBar            = skill.showBunBar ~= false,
        showTimerBar          = skill.showTimerBar ~= false,
        headAlert             = skill.headAlert or false,
        screenAlert           = skill.screenAlert or false,
        preAlertText          = skill.preAlertText,
        screenText            = skill.screenText,
        centralLead           = NormalizeLeadSeconds(skill.centralLead, 0),
        voiceLabel            = skill.voiceLabel,
        source                = source,
        eventID               = ResolveSkillEventID(skill, self._encounterID),
        eventColor            = skill.eventColor,
        preAlertFired         = false,
        mechanicPreAlertFired = false,
        hintCountdownFired    = false,
        hintCentralFired      = false,
        castFired             = false,
        bunBarShown           = false,
        fiveSecBroadcastFired = false,
        timerBarShown         = false,
        timelineManaged       = false,
        timelineEventID       = nil,
        timelinePreAlertLead  = DEFAULT_PREALERT_SECS,
        fixedTimelineMatched  = false,
        waitTimelineFinish    = skill.waitTimelineFinish == true,
        timelineFinishTimeout = tonumber(skill.timelineFinishTimeout),
        centralFired          = false,
        skillDef              = skill,
    }

    self:_ApplyTimerDisplayName(timer)
    self:_ApplyEncounterEventActions(timer)

    if not self:_ApplySkillOverride(timer) then
        return nil
    end

    AttachConditionTriggers(timer)
    if source == "fixed_ai" and self._debugFixedAIPauseAll == true and timer.castFired ~= true then
        local now = GetTime and GetTime() or 0
        timer.fixedAIPausedAt = now
        timer.fixedAIPausedTick = now
        timer.fixedAIPaused = true
        timer.fixedAIWasPaused = true
    end
    self._active[id] = timer

    return id
end

-- ── blizzard 原生轴桥接 ──────────────────────────────────────

function Scheduler:_GetTimelineRemaining(eventID, fallback)
    if C_EncounterTimeline and C_EncounterTimeline.GetEventTimeRemaining then
        local ok, r = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
        if ok and type(r) == "number" then
            return r
        end
    end
    return fallback
end

function Scheduler:_GetTimelineState(eventID)
    if C_EncounterTimeline and C_EncounterTimeline.GetEventState then
        local ok, s = pcall(C_EncounterTimeline.GetEventState, eventID)
        if ok then return s end
    end
    return nil
end

function Scheduler:_ClearTimelineAddedPending(eventID)
    local pending = self._timelineAddedPending
    local timelineEventID = SafeToNumber(eventID)
    if type(pending) == "table" and timelineEventID then
        pending[timelineEventID] = nil
    end
end

function Scheduler:_QueueTimelineEventAdded(eventInfo)
    if type(eventInfo) ~= "table" then return end
    local eventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not eventID or not IsTimelineDurationAllowed(duration) then
        return
    end
    if not IsEncounterTimelineSource(eventInfo.source) then
        return
    end

    local now = GetTime()
    self._timelineAddedPending = type(self._timelineAddedPending) == "table" and self._timelineAddedPending or {}
    self._timelineAddedPending[eventID] = {
        timelineEventID = eventID,
        duration = duration,
        receivedAt = now,
        readyAt = now + TIMELINE_ADDED_CONFIRM_DELAY,
        spellIdentifier = eventInfo.spellID,
        spellName = eventInfo.spellName,
        iconFileID = SafeToNumber(eventInfo.iconFileID),
        eventColor = ExtractColorRGB(eventInfo.color),
        source = SafeToNumber(eventInfo.source),
    }
    self._acceptedTimelineEventIDs[eventID] = true
end

function Scheduler:_FilterTimelineAddedBatch(batch, now)
    if type(batch) ~= "table" or #batch == 0 then
        return nil
    end
    local chosenByDuration = {}
    local orderByDuration = {}
    local acceptPausedSync = self._mode == "fixed"
        and self._fixedDriver == FIXED_DRIVER_AI
        and FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS[SafeToNumber(self._encounterID) or 0] == true

    for _, queued in ipairs(batch) do
        local eventID = SafeToNumber(queued and queued.timelineEventID)
        local duration = SafeToNumber(queued and queued.duration)
        if eventID and IsTimelineDurationAllowed(duration) then
            local state = self:_GetTimelineState(eventID)
            local pausedSyncAccepted = acceptPausedSync and state == STATE_PAUSED and
                self:_IsFixedAISyncDuration(duration)
            if state == STATE_ACTIVE or pausedSyncAccepted then
                queued.pausedSyncAccepted = pausedSyncAccepted or nil
                local key = BuildTimelineDurationKey(duration)
                if chosenByDuration[key] == nil then
                    orderByDuration[#orderByDuration + 1] = key
                else
                    local oldEventID = SafeToNumber(chosenByDuration[key] and chosenByDuration[key].timelineEventID)
                    if oldEventID and oldEventID ~= eventID then
                        self._acceptedTimelineEventIDs[oldEventID] = nil
                        self._timelineCountdownSpecByEventID[oldEventID] = nil
                    end
                end
                chosenByDuration[key] = queued
            else
                self._acceptedTimelineEventIDs[eventID] = nil
                self._timelineCountdownSpecByEventID[eventID] = nil
            end
        end
    end

    if #orderByDuration == 0 then
        return nil
    end

    table.sort(orderByDuration, function(a, b)
        local left = chosenByDuration[a]
        local right = chosenByDuration[b]
        return (SafeToNumber(left and left.receivedAt) or now or 0) <
            (SafeToNumber(right and right.receivedAt) or now or 0)
    end)

    local filtered = {}
    for _, key in ipairs(orderByDuration) do
        filtered[#filtered + 1] = chosenByDuration[key]
    end
    return filtered
end

function Scheduler:_FlushTimelineAddedPending(now)
    if not (self._running and self._mode == "blizzard" and ModeUsesTimeline(self._mode)) then
        return
    end
    local pending = self._timelineAddedPending
    if type(pending) ~= "table" then
        return
    end

    now = SafeToNumber(now) or GetTime()
    local batch = nil
    for eventID, queued in pairs(pending) do
        if type(queued) ~= "table" or now >= (SafeToNumber(queued.readyAt) or 0) then
            pending[eventID] = nil
            batch = batch or {}
            batch[#batch + 1] = queued
        end
    end

    local filtered = self:_FilterTimelineAddedBatch(batch, now)
    if not filtered then
        return
    end

    for _, queued in ipairs(filtered) do
        local eventID = SafeToNumber(queued.timelineEventID)
        if eventID then
            self._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                queued.spellName,
                queued.iconFileID,
                queued.eventColor
            )
            self:_AttachTimelineEventByID(
                eventID,
                self:_GetTimelineRemaining(eventID, queued.duration),
                queued.spellIdentifier,
                queued.spellName,
                queued.iconFileID,
                queued.eventColor,
                queued.source
            )
        end
    end
end

function Scheduler:_BuildTimelineTimer(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                                       passthroughIconFileID, passthroughEventColor, passthroughSource)
    eventID = SafeToNumber(eventID)
    if not eventID then return nil end

    local now = GetTime()
    remaining = SafeNum(remaining, self:_GetTimelineRemaining(eventID, 0))
    if remaining < 0 then remaining = 0 end

    -- 12.0 secret 规则：显示名只透传事件载荷 spellName，不调用外部法术名 API。
    local name = ResolveTimelineDisplayName(passthroughSpellName, eventID)
    local priority = 2
    local screenAlert = false
    local occurrenceCount = self:_NextOccurrenceCount({
        eventID = eventID,
        spellIdentifier = passthroughSpellIdentifier,
        displayName = name,
    }, "blizzard")

    local timer = {
        -- secret 值只做透传，不在本模块做比较/运算。
        spellID                    = nil,
        spellIdentifier            = passthroughSpellIdentifier,
        timelineSpellName          = passthroughSpellName,
        iconFileID                 = passthroughIconFileID,
        baseDisplayName            = name,
        displayName                = name,
        occurrenceCount            = occurrenceCount,
        castTime                   = now + remaining,
        duration                   = math.max(5, remaining),
        timerBarDuration           = TIMERBAR_LEAD_TIME,
        preAlertTime               = nil,
        barPriority                = priority,
        showBunBar                 = true,
        showTimerBar               = true,
        headAlert                  = false,
        screenAlert                = screenAlert,
        preAlertText               = nil,
        screenText                 = nil,
        centralLead                = 0,
        voiceLabel                 = nil,
        source                     = "blizzard",
        eventID                    = nil,
        eventColor                 = passthroughEventColor,
        preAlertFired              = false,
        mechanicPreAlertFired      = false,
        hintCountdownFired         = false,
        hintCentralFired           = false,
        castFired                  = false,
        bunBarShown                = false,
        fiveSecBroadcastFired      = false,
        timerBarShown              = false,
        timelineManaged            = true,
        timelineEventID            = eventID,
        timelineSourceType         = tonumber(passthroughSource),
        blizzardHintSessionEnabled = (self._blizzardHintSessionEnabled == true),
        timelinePreAlertLead       = 0,
        centralFired               = false,
    }
    self:_ApplyTimerDisplayName(timer)
    self:_ApplyEncounterEventActions(timer)
    if not self:_ApplySkillOverride(timer) then
        return nil
    end
    local trashMeta = TrashRuntimeConfig and type(TrashRuntimeConfig.GetTimelineEventMeta) == "function"
        and TrashRuntimeConfig.GetTimelineEventMeta(eventID) or nil
    if type(trashMeta) == "table" then
        ApplyTrashTimelineMeta(timer, trashMeta)
    end
    return timer
end

function Scheduler:_AttachTimelineEventByID(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                                            passthroughIconFileID, passthroughEventColor, passthroughSource)
    eventID = SafeToNumber(eventID)
    if not eventID then return end

    local exists = self._timelineEventToTimer[eventID]
    if exists and self._active[exists] then
        local timer = self._active[exists]
        if timer then
            if passthroughSpellIdentifier ~= nil then
                timer.spellIdentifier = passthroughSpellIdentifier
            end
            if passthroughSpellName ~= nil then
                timer.timelineSpellName = passthroughSpellName
            end
            if passthroughIconFileID ~= nil then
                timer.iconFileID = passthroughIconFileID
            end
            if type(passthroughEventColor) == "table" then
                timer.eventColor = passthroughEventColor
            end
            timer.timelineSourceType = tonumber(passthroughSource) or timer.timelineSourceType
            timer.blizzardHintSessionEnabled = (self._blizzardHintSessionEnabled == true)
            timer.spellID = nil
            timer.baseDisplayName = ResolveTimelineDisplayName(timer.timelineSpellName, eventID)
            self:_ApplyTimerDisplayName(timer)
        end
        local now = GetTime()
        remaining = SafeNum(remaining, self:_GetTimelineRemaining(eventID, timer.castTime - now))
        if remaining and remaining >= 0 then
            timer.castTime = now + remaining
            if timer.countdownMode == "own" then
                timer.timelinePreAlertLead = math.min(DEFAULT_PREALERT_SECS, math.max(0, remaining))
            else
                timer.timelinePreAlertLead = 0
            end
        end
        if not self:_ApplySkillOverride(timer) then
            self:_DetachTimelineEvent(eventID)
        end
        local trashMeta = TrashRuntimeConfig and type(TrashRuntimeConfig.GetTimelineEventMeta) == "function"
            and TrashRuntimeConfig.GetTimelineEventMeta(eventID) or nil
        if type(trashMeta) == "table" then
            ApplyTrashTimelineMeta(timer, trashMeta)
        end
        self:_ApplyEncounterEventActions(timer)
        return
    end

    local timer = self:_BuildTimelineTimer(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
        passthroughIconFileID, passthroughEventColor, passthroughSource)
    if not timer then return end

    local id = self._nextTimerID
    self._nextTimerID = id + 1
    timer.id = id
    self._active[id] = timer
    self._timelineEventToTimer[eventID] = id
end

function Scheduler:_DetachTimelineEvent(eventID)
    local timerID = self._timelineEventToTimer[eventID]
    if not timerID then return end
    self._timelineEventToTimer[eventID] = nil
    self._active[timerID] = nil
end

function Scheduler:_RecoverTimelineEvents()
    if not (self._running and ModeUsesTimeline(self._mode) and CanUseTimelineAPI()) then
        return
    end
    local now = GetTime and GetTime() or 0
    if self._mode == "blizzard" and now < (tonumber(self._ignoreTimelineRecoveryUntil) or 0) then
        return
    end
    if self._mode == "blizzard" and self._encounterID ~= nil then
        return
    end
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then
        return
    end
    local ok, events = pcall(C_EncounterTimeline.GetEventList)
    if not ok or type(events) ~= "table" then return end

    for _, eventID in ipairs(events) do
        if self:_GetTimelineState(eventID) ~= STATE_ACTIVE then
            self._acceptedTimelineEventIDs[SafeToNumber(eventID) or 0] = nil
            self._timelineCountdownSpecByEventID[SafeToNumber(eventID) or 0] = nil
        else
            local remaining = self:_GetTimelineRemaining(eventID, 0)
            if IsTimelineDurationAllowed(remaining) then
                local passthroughSpellIdentifier = nil
                local passthroughSpellName = nil
                local passthroughIconFileID = nil
                local passthroughEventColor = nil
                if C_EncounterTimeline and C_EncounterTimeline.GetEventInfo then
                    local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
                    if okInfo and info then
                        passthroughSpellIdentifier = info.spellID
                        passthroughSpellName = info.spellName
                        passthroughIconFileID = SafeToNumber(info.iconFileID)
                        passthroughEventColor = ExtractColorRGB(info.color)
                        self._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                            info.spellName,
                            info.iconFileID,
                            passthroughEventColor
                        )
                    end
                end
                self._acceptedTimelineEventIDs[SafeToNumber(eventID) or 0] = true
                self:_AttachTimelineEventByID(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                    passthroughIconFileID, passthroughEventColor)
            end
        end
    end
end

function Scheduler:_OnTimelineEventAdded(eventInfo)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    -- 优先使用 ADDED 事件透传的信息（与原生时间轴同源）。
    if type(eventInfo) == "table" and SafeToNumber(eventInfo.id) then
        self:_QueueTimelineEventAdded(eventInfo)
        return
    end
    if self._mode ~= "blizzard" then
        self:_RecoverTimelineEvents()
    end
end

function Scheduler:_OnTimelineEventStateChanged(eventID)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    local timelineEventID = SafeToNumber(eventID)
    local timerID = self._timelineEventToTimer[timelineEventID or eventID]
    local timer = timerID and self._active[timerID] or nil
    local state = self:_GetTimelineState(eventID)
    if self._mode == "blizzard" and self._acceptedTimelineEventIDs[timelineEventID or 0] ~= true then
        return
    end
    if self._mode == "blizzard"
        and timelineEventID
        and type(self._timelineAddedPending) == "table"
        and self._timelineAddedPending[timelineEventID] then
        if state ~= STATE_ACTIVE then
            self:_ClearTimelineAddedPending(timelineEventID)
            self._acceptedTimelineEventIDs[timelineEventID] = nil
            self._timelineCountdownSpecByEventID[timelineEventID] = nil
        end
        return
    end

    if not timerID then
        if self._mode == "blizzard" then
            return
        end
        local passthroughSpellIdentifier = nil
        local passthroughSpellName = nil
        local passthroughIconFileID = nil
        local passthroughEventColor = nil
        if C_EncounterTimeline and C_EncounterTimeline.GetEventInfo then
            local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
            if okInfo and info then
                passthroughSpellIdentifier = info.spellID
                passthroughSpellName = info.spellName
                passthroughIconFileID = SafeToNumber(info.iconFileID)
                passthroughEventColor = ExtractColorRGB(info.color)
                self._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                    info.spellName,
                    info.iconFileID,
                    passthroughEventColor
                )
            end
        end
        self:_AttachTimelineEventByID(eventID, self:_GetTimelineRemaining(eventID, 0), passthroughSpellIdentifier,
            passthroughSpellName, passthroughIconFileID, passthroughEventColor, nil)
        return
    end

    timer = self._active[timerID]
    if not timer then
        self._timelineEventToTimer[eventID] = nil
        return
    end

    if state == STATE_FINISHED then
        if timer.trashKeepTimerBarAfterReadyEnabled == true then
            timer.trashReadyAt = tonumber(timer.trashReadyAt) or GetTime()
            timer.castTime = GetTime()
            timer.timelineManaged = false
            timer.timelineEventID = nil
            self._timelineEventToTimer[eventID] = nil
            return
        end
        timer.castFired = true
        CaptureLastFiredTimer(timer, GetTime())
        if ExBoss.Timeline.Dispatcher then
            ExBoss.Timeline.Dispatcher:OnCast(timer)
        end
        self:_DetachTimelineEvent(eventID)
    elseif state == STATE_CANCELED then
        self:_DetachTimelineEvent(eventID)
    end
end

function Scheduler:_OnTimelineEventRemoved(eventID)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    local timelineEventID = SafeToNumber(eventID) or 0
    self:_ClearTimelineAddedPending(timelineEventID)
    self._acceptedTimelineEventIDs[timelineEventID] = nil
    self._timelineCountdownSpecByEventID[timelineEventID] = nil
    self:_DetachTimelineEvent(eventID)
end

function Scheduler:_UpdateTimelineManagedTimer(timer, now)
    local eventID = timer.timelineEventID
    if not eventID then
        if timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil then
            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
            if hideAfter > 0 and (now - tonumber(timer.trashReadyAt)) >= hideAfter then
                return "remove"
            end
            timer.castTime = now
            return "keep"
        end
        return "remove"
    end

    local state = self:_GetTimelineState(eventID)
    if state == nil then
        return "remove"
    end

    local remaining = self:_GetTimelineRemaining(eventID, timer.castTime - now)
    if type(remaining) == "number" and remaining >= 0 then
        timer.castTime = now + remaining
    else
        remaining = math.max(0, timer.castTime - now)
    end

    TryFireMechanicPreAlert(self, timer, remaining)

    local blizzardCentralLead = tonumber(timer.blizzardHintCentralLead) or 2
    if timer.useBlizzardHintCentral == true and timer.centralMode == "blizzard_hint" and timer.hintCentralFired ~= true and remaining <= blizzardCentralLead then
        timer.hintCentralFired = true
        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCentralLead)
        end
    end

    local lead = SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and remaining <= lead then
        timer.preAlertFired = true
        if ExBoss.Timeline.Dispatcher then
            ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
        end
    end

    local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
    if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and remaining <= centralLead then
        timer.centralFired = true
        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
            ExBoss.Timeline.Dispatcher:OnCentral(timer)
        end
    end

    if state == STATE_FINISHED or remaining <= 0 then
        if timer.trashKeepTimerBarAfterReadyEnabled == true then
            timer.trashReadyAt = tonumber(timer.trashReadyAt) or now
            timer.castTime = now
            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
            if hideAfter > 0 and (now - timer.trashReadyAt) >= hideAfter then
                return "remove"
            end
            return "keep"
        end
        if not timer.castFired then
            timer.castFired = true
            CaptureLastFiredTimer(timer, now)
            if ExBoss.Timeline.Dispatcher then
                ExBoss.Timeline.Dispatcher:OnCast(timer)
            end
            if timer.clearActiveSnapshotAfter then
                self:_ScheduleClearActiveSnapshot(timer)
            end
        end
        return "remove"
    end
    if state == STATE_CANCELED then
        return "remove"
    end
    return "keep"
end

-- ── HIGHLIGHT 校准 ───────────────────────────────────────────
-- ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT 在某个技能剩余约5秒时触发（无参数）。
-- 对所有固定模式（非 timelineManaged）且尚未触发的 timer，找到 castTime
-- 最接近 GetTime()+5 的那个，将其 castTime 吸附到精确值，并同步 preAlertTime。

local HIGHLIGHT_TARGET_SECS = 5    -- Blizzard 触发时提前量（秒）
local HIGHLIGHT_SNAP_TOLERANCE = 4 -- 搜索窗口：±N 秒内才算候选

function Scheduler:_OnTimelineHighlight(eventID)
    if not self._running then return end

    local timelineEventID = SafeToNumber(eventID)
    if timelineEventID then
        if self._mode == "blizzard" and self._acceptedTimelineEventIDs[timelineEventID] ~= true then
            return
        end
        local timerID = self._timelineEventToTimer and self._timelineEventToTimer[timelineEventID] or nil
        local timer = timerID and self._active and self._active[timerID] or nil
        local isBlizzardManaged = type(timer) == "table"
            and (timer.timelineManaged == true
                or timer.countdownMode == "blizzard_hint"
                or timer.centralMode == "blizzard_hint")
        if isBlizzardManaged then
            local blizzardCountdownLead = tonumber(timer.blizzardHintCountdownLead) or HIGHLIGHT_TARGET_SECS
            if timer.useBlizzardHintCountdown == true and timer.countdownMode == "blizzard_hint" and blizzardCountdownLead == HIGHLIGHT_TARGET_SECS and timer.hintCountdownFired ~= true then
                timer.blizzardHighlightCountdownFired = true
                timer.hintCountdownFired = true
                timer.blizzardCountdownShown = true
                local spec = self._timelineCountdownSpecByEventID[timelineEventID]
                if spec and ExBoss.UI.Countdown and ExBoss.UI.Countdown.Show then
                    ExBoss.UI.Countdown:Show(spec)
                end
            end
            return
        end
    end

    local targetTime = GetTime() + HIGHLIGHT_TARGET_SECS
    local bestID, bestDelta = nil, math.huge
    for id, timer in pairs(self._active) do
        if not timer.timelineManaged and not timer.castFired then
            local delta = math.abs(timer.castTime - targetTime)
            if delta < bestDelta then
                bestDelta = delta
                bestID = id
            end
        end
    end
    if bestID and bestDelta <= HIGHLIGHT_SNAP_TOLERANCE then
        local timer = self._active[bestID]
        local oldCast = timer.castTime
        timer.castTime = targetTime
        -- 同步 preAlertTime（保持提前量不变）
        if timer.preAlertTime and not timer.preAlertFired then
            timer.preAlertTime = timer.preAlertTime + (targetTime - oldCast)
        end
    end
end

-- ── OnUpdate 驱动 ────────────────────────────────────────────

function Scheduler:_OnUpdate(elapsed)
    if not self._running then return end
    self._elapsed = self._elapsed + elapsed
    if self._elapsed < ONUPDATE_INTERVAL then return end
    self._elapsed  = 0

    local now      = GetTime()
    local toRemove = nil

    self:_FlushTimelineAddedPending(now)
    self:_FlushFixedAIPendingEvents(now)
    self:_TickBossCastObserve(now)

    for id, timer in pairs(self._active) do
        local action = nil
        if timer.timelineManaged then
            action = self:_UpdateTimelineManagedTimer(timer, now)
        end

        if action ~= "remove" then
            if not timer.bunBarShown and timer.showBunBar and IsBunBarEnabledByGlobal() and now >= (timer.castTime - ResolveBunBarLeadTime()) then
                timer.bunBarShown = true
                if ExBoss.UI.BunBar and ExBoss.UI.BunBar.AddTimer then
                    ExBoss.UI.BunBar:AddTimer(timer)
                end
            end

            if not timer.timerBarShown and timer.showTimerBar and IsTimerBarEnabledByGlobal() and now >= (timer.castTime - ResolveTimerBarLeadTime(timer)) then
                timer.timerBarShown = true
                timer.timerBarDuration = ResolveTimerBarDisplayDuration(timer, now)
                if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.AddTimer then
                    ExBoss.UI.TimerBar:AddTimer(timer)
                end
            end

            if not timer.fiveSecBroadcastFired and not timer.castFired then
                local remaining = timer.castTime - now
                if remaining <= TIMER_FIVE_SEC_REMAINING_THRESHOLD and remaining > 0 then
                    timer.fiveSecBroadcastFired = true
                    ExwindTools:SendEvent(TIMER_FIVE_SEC_REMAINING_EVENT, {
                        timerID     = timer.id,
                        eventID     = SafeToNumber(timer.eventID),
                        encounterID = self._encounterID,
                        remaining   = remaining,
                        castTime    = timer.castTime,
                        source      = timer.source,
                        spellID     = SafeToNumber(timer.spellID),
                        displayName = timer.displayName,
                    })
                    self:_QueueBossCastObserveForTimer(timer, now)
                end
            end

            if not timer.timelineManaged then
                if timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil then
                    local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
                    if hideAfter > 0 and (now - tonumber(timer.trashReadyAt)) >= hideAfter then
                        action = "remove"
                    else
                        timer.castTime = now
                        action = "keep"
                    end
                end
            end

            if not timer.timelineManaged and action ~= "remove" and timer.source == "trash" then
                local remaining = math.max(0, timer.castTime - now)
                if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and timer.preAlertTime and now >= timer.preAlertTime then
                    timer.preAlertFired = true
                    local lead = math.max(0, tonumber(timer.castTime or now) - tonumber(timer.preAlertTime or now))
                    timer.preAlertCountdownDuration = math.max(0.1,
                        math.min(lead > 0 and lead or DEFAULT_PREALERT_SECS, remaining))
                    if timer.preAlertCountdownDuration > 0.15 and ExBoss.Timeline.Dispatcher then
                        ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
                    end
                end
                local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
                if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and remaining <= centralLead then
                    timer.centralFired = true
                    if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
                        ExBoss.Timeline.Dispatcher:OnCentral(timer)
                    end
                end
                TryFireFixedVoiceTriggers(timer, now)
                if now >= timer.castTime then
                    if not timer.castFired then
                        timer.castFired = true
                        CaptureLastFiredTimer(timer, now)
                    end
                    if self:_AdvanceTrashFixedCombatTimeline(timer, now) then
                        action = "keep"
                    else
                        timer.trashReadyAt = tonumber(timer.trashReadyAt) or now
                        timer.castTime = now
                        if timer.trashKeepTimerBarAfterReadyEnabled == true then
                            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
                            if hideAfter > 0 and (now - timer.trashReadyAt) >= hideAfter then
                                action = "remove"
                            else
                                action = "keep"
                            end
                        else
                            action = "remove"
                        end
                    end
                end
            end

            if not timer.timelineManaged and action ~= "remove" and timer.source ~= "trash" and not (timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil) then
                if timer.source == "fixed_ai" and timer.fixedAIPaused == true then
                    local lastTick = tonumber(timer.fixedAIPausedTick) or tonumber(timer.fixedAIPausedAt) or now
                    local pauseDelta = math.max(0, now - lastTick)
                    if pauseDelta > 0 then
                        ShiftFixedAITimerForPause(timer, pauseDelta)
                    end
                    timer.fixedAIPausedTick = now
                    action = "keep"
                else
                    UpdateConditionTriggers(timer, now)
                    local mechanicRemaining = math.max(0, tonumber(timer.castTime or now) - now)
                    TryFireMechanicPreAlert(self, timer, mechanicRemaining)
                    local blizzardCountdownLead = tonumber(timer.blizzardHintCountdownLead) or
                        VIRTUAL_HINT_REMAINING_SECS
                    if timer.useBlizzardHintCountdown == true and timer.countdownMode == "blizzard_hint" and timer.hintCountdownFired ~= true and now >= (timer.castTime - blizzardCountdownLead) then
                        timer.hintCountdownFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
                            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCountdownLead)
                        end
                    end
                    local blizzardCentralLead = tonumber(timer.blizzardHintCentralLead) or 2
                    if timer.useBlizzardHintCentral == true and timer.centralMode == "blizzard_hint" and timer.hintCentralFired ~= true and now >= (timer.castTime - blizzardCentralLead) then
                        timer.hintCentralFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
                            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCentralLead)
                        end
                    end
                    if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and timer.preAlertTime and now >= timer.preAlertTime then
                        timer.preAlertFired = true
                        local remaining = math.max(0, tonumber(timer.castTime or now) - now)
                        local lead = math.max(0, tonumber(timer.castTime or now) - tonumber(timer.preAlertTime or now))
                        timer.preAlertCountdownDuration = math.max(0.1,
                            math.min(lead > 0 and lead or DEFAULT_PREALERT_SECS, remaining))
                        if timer.preAlertCountdownDuration > 0.15 and ExBoss.Timeline.Dispatcher then
                            ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
                        end
                    end
                    local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
                    if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and now >= (timer.castTime - centralLead) then
                        timer.centralFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
                            ExBoss.Timeline.Dispatcher:OnCentral(timer)
                        end
                    end
                    local castNow = false
                    if not timer.castFired and now >= timer.castTime and timer.source == "fixed_ai" then
                        if TryEnterFixedAICastStartWait(timer, now) then
                            local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                            if now >= deadline then
                                castNow = true
                            else
                                action = "keep"
                            end
                        elseif self:_TryHoldFixedAIForTimelineFinish(timer, now) then
                            action = "keep"
                        else
                            castNow = true
                        end
                    elseif not timer.castFired and timer.source == "fixed_ai" and IsFixedAICastStartFinishMode(timer) and TryEnterFixedAICastStartWait(timer, now) then
                        local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                        if now >= deadline then
                            castNow = true
                        else
                            action = "keep"
                        end
                    else
                        TryFireFixedVoiceTriggers(timer, now)
                        castNow = not timer.castFired and now >= timer.castTime
                    end
                    if castNow then
                        CastBarEventDebugPrint(timer, string.format(
                            "Scheduler castNow event=%s timer=%s timeline=%s now=%.2f cast=%.2f remain=%.2f",
                            tostring(timer.eventID),
                            tostring(timer.id),
                            tostring(timer.fixedAITimelineEventID or ""),
                            tonumber(now) or 0,
                            tonumber(timer.castTime) or 0,
                            (tonumber(timer.castTime) or 0) - (tonumber(now) or 0)
                        ))
                        AIVoiceDebugPrint(self, timer, string.format(
                            "cast-branch timer=%s event=%s %s name=%s",
                            tostring(timer.id),
                            tostring(timer.eventID),
                            AIVoiceTimerTimingText(timer),
                            tostring(timer.displayName or timer.baseDisplayName or "")
                        ))
                        if timer.source == "fixed_ai" then
                            self:_TriggerFixedAITimerCast(timer, now, "cast-timeout-fallback")
                            for trigger = 1, 2 do
                                local enabledKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"
                                local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
                                local fireAt = GetFixedVoiceTriggerFireTime(timer, trigger)
                                local keepPending = (timer[enabledKey] == true)
                                    and (timer[firedKey] ~= true)
                                    and fireAt
                                    and fireAt > now
                                if not keepPending then
                                    timer[firedKey] = true
                                end
                            end
                        else
                            timer.fixedAIWaitingTimelineFinish = false
                            timer.castFired = true
                            CaptureLastFiredTimer(timer, now)
                            if ExBoss.Timeline.Dispatcher then
                                ExBoss.Timeline.Dispatcher:OnCast(timer)
                            end
                            if timer.clearActiveSnapshotAfter then
                                self:_ScheduleClearActiveSnapshot(timer)
                            end
                            EnsureFixedVoiceAtCast(timer)
                        end
                        if timer.source == "fixed" then
                            self:_ScheduleNextFixedOccurrence(timer)
                        end
                    end
                end
                if timer.castFired and not HasPendingFixedVoiceTriggers(timer) then
                    action = "remove"
                end
            end
        end

        if action == "remove" then
            if not toRemove then toRemove = {} end
            toRemove[id] = true
        end
    end

    if toRemove then
        for id in pairs(toRemove) do
            local timer = self._active[id]
            if timer then
                if not timer._debugRemoveReason then
                    timer._debugRemoveReason = "auto"
                end
                AIVoiceDebugPrint(self, timer, string.format(
                    "remove-source=auto timer=%s event=%s %s castFired=%s tr1=%s/%s tr2=%s/%s name=%s",
                    tostring(timer.id),
                    tostring(timer.eventID),
                    AIVoiceTimerTimingText(timer),
                    tostring(timer.castFired),
                    tostring(timer.fixedVoiceTrigger1Fired),
                    tostring(timer.fixedVoiceTrigger1Enabled),
                    tostring(timer.fixedVoiceTrigger2Fired),
                    tostring(timer.fixedVoiceTrigger2Enabled),
                    tostring(timer.displayName or timer.baseDisplayName or "")
                ))
            end
            self:_RemoveActiveTimerByID(id)
        end
    end
end

function Scheduler:GetActiveTimers()
    return self._active
end

function Scheduler:GetCurrentEncounterID()
    return self._encounterID
end

function Scheduler:SetDebugFixedAIPaused(enabled)
    local nextState = (enabled == true)
    self._debugFixedAIPauseAll = nextState

    local now = GetTime and GetTime() or 0
    local affected = 0
    for _, timer in pairs(self._active or {}) do
        if type(timer) == "table" and timer.source == "fixed_ai" and timer.castFired ~= true then
            if nextState then
                if not timer.fixedAIPausedAt then
                    timer.fixedAIPausedAt = now
                    timer.fixedAIPausedTick = now
                    timer.fixedAIPaused = true
                    timer.fixedAIWasPaused = true
                end
            else
                timer.fixedAIPausedAt = nil
                timer.fixedAIPausedTick = nil
                timer.fixedAIPaused = nil
            end
            affected = affected + 1
        end
    end
    return affected
end

function Scheduler:ToggleDebugFixedAIPaused()
    local enabled = not (self._debugFixedAIPauseAll == true)
    local affected = self:SetDebugFixedAIPaused(enabled)
    return enabled, affected
end

function Scheduler:IsDebugFixedAIPaused()
    return self._debugFixedAIPauseAll == true
end

function Scheduler:DebugPrintFixedAIState()
    local prefix = "|cff33ff99ExBoss AIDump|r "
    local function Emit(text)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(text or ""))
        else
            print(prefix .. tostring(text or ""))
        end
    end

    Emit(string.format(
        "encounter=%s mode=%s driver=%s running=%s debugPause=%s",
        tostring(self._encounterID),
        tostring(self._mode),
        tostring(self._fixedDriver),
        tostring(self._running == true),
        tostring(self._debugFixedAIPauseAll == true)
    ))
    Emit(FixedAIMapDebugText(self))

    local lines = {}
    for _, timer in pairs(self._active or {}) do
        if type(timer) == "table" and timer.source == "fixed_ai" then
            lines[#lines + 1] = FixedAITimerDebugState(timer)
        end
    end
    table.sort(lines)
    if #lines == 0 then
        Emit("active fixed_ai timers = 0")
        return
    end
    for i = 1, #lines do
        Emit(lines[i])
    end
end

-- ── 帧初始化 ─────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:Hide()
frame:SetScript("OnUpdate", function(_, elapsed)
    Scheduler:_OnUpdate(elapsed)
end)
frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT")
frame:RegisterEvent("ENCOUNTER_TIMELINE_STATE_UPDATED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
Scheduler._handlesEncounterEvents = false
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_START" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        Scheduler:_RecordBossCastObserveStart(unit, "cast", castBarID)
        Scheduler:_OnBossSpellcastBoundary(unit, "cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        Scheduler:_RecordBossCastObserveStart(unit, "channel", castBarID)
        Scheduler:_OnBossSpellcastBoundary(unit, "channel")
    elseif event == "UNIT_SPELLCAST_STOP" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "cast")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "cast", castBarID, specialEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "cast")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "cast")
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "channel")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "channel", castBarID, specialEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "channel")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "channel")
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialCastEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "cast")
        local specialChannelEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "channel")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "cast", castBarID, specialCastEventID)
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "channel", castBarID, specialChannelEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialCastEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialCastEventID,
                })
            end
            if specialChannelEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialChannelEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "cast")
            castBar:StopByUnitCastBar(unit, castBarID, "channel")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialCastEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialCastEventID,
                })
            end
            if specialChannelEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialChannelEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "cast")
            ring:StopByUnitCastBar(unit, castBarID, "channel")
        end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventAdded(arg1)
                return
            end
            if Scheduler._fixedDriver == FIXED_DRIVER_TIME then
                Scheduler:_OnFixedTimeTimelineEventAdded(arg1)
                return
            end
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventAdded(arg1)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventStateChanged(arg1)
            end
            return
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventStateChanged(arg1)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventRemoved(arg1)
                return
            end
            if Scheduler._fixedDriver == FIXED_DRIVER_TIME then
                Scheduler:_OnFixedTimeTimelineEventRemoved(arg1)
                return
            end
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventRemoved(arg1)
    elseif event == "ENCOUNTER_TIMELINE_STATE_UPDATED" then
        if Scheduler._suppressBlizzardTimeline == true then
            return
        end
        local now = GetTime and GetTime() or 0
        if Scheduler._mode == "blizzard" and now < (tonumber(Scheduler._ignoreTimelineRecoveryUntil) or 0) then
            return
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_RecoverTimelineEvents()
    elseif event == "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        Scheduler:_OnTimelineHighlight(arg1)
    end
end)
Scheduler._frame   = frame
Scheduler._elapsed = 0

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent(TRASH_CASTBAR_STOP_EVENT, "ExBoss.Scheduler.TrashCastBarStop", function(_, payload)
        if type(payload) ~= "table" then
            return
        end
        local owner = {
            source = "trash",
            runtime = payload.runtime,
            castKind = tostring(payload.castKind or ""),
            castBarID = NormalizeCastBarID(payload.castBarID),
        }
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        if castBar and type(castBar.StopByOwner) == "function" then
            castBar:StopByOwner(owner)
        end
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        if ring and type(ring.StopByOwner) == "function" then
            ring:StopByOwner(owner)
        end
    end)
end

-- BOSS 注册表（由 ExBossDB/Bosses/*.lua 填入）
ExBoss.Timeline._bosses = ExBoss.Timeline._bosses or {}

function ExBoss.Timeline:RegisterBoss(encounterID, def)
    self._bosses[encounterID] = def
end
