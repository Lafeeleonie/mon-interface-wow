---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Output or {}
ExBoss.TrashCD.Output = Mod
ExBoss.Trash.Output = Mod

local SCRIPT_EVENT_MIN_DELAY = 0.20
local CAST_START_VOICE_TARGET_DELAY = 0.12
local CAST_START_VOICE_TARGET_CLEAR_DELAY = 0.12
local CAST_START_VOICE_TARGET_SWITCH_DELAY = 0.12
local CAST_START_AURA_DELTA_DELAY = 0.10
local CAST_START_AURA_DELTA_PRE_WINDOW = 0.10
local CAST_START_AURA_DELTA_POST_WINDOW = 0.10
local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local RuntimeConfig = ExBoss.TrashCD and ExBoss.TrashCD.RuntimeConfig or nil
local AuraDelta = ExBoss.TrashCD and ExBoss.TrashCD.AuraDelta or nil

local function RequestRuntimeRefresh(runtime, reason)
    if type(runtime) ~= "table" then
        return
    end
    local unit = tostring(runtime._nameplateUnit or runtime._debugUnit or "")
    if unit == "" then
        return
    end
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    if test and type(test.RefreshUnit) == "function" then
        test:RefreshUnit(unit, reason or "aura-delta-refresh", true)
    end
end

local function IsDebug()
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    return test and type(test.IsDebug) == "function" and test.IsDebug() == true
end

local function DebugPrint(msg)
    if not IsDebug() then
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashCD|r " .. tostring(msg or ""))
    end
end

local function IsTrashVoiceDebug()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TrashVoice and ExBoss.Debug.TrashVoice.enabled == true
end

local function VoiceDebugPrint(msg)
    if not IsTrashVoiceDebug() then
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

local function GetScheduler()
    return ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
end

local function HasPositiveDurationValue(value)
    if type(value) == "table" then
        for _, item in pairs(value) do
            if HasPositiveDurationValue(item) then
                return true
            end
        end
        return false
    end
    if type(value) == "string" then
        for item in string.gmatch(value, "[^,;/|%s]+") do
            if (tonumber(item) or 0) > 0 then
                return true
            end
        end
        return false
    end
    local n = tonumber(value)
    return n ~= nil and n > 0
end

local function SpellMatchesStartKind(spellData, kind)
    if type(spellData) ~= "table" then
        return false
    end
    kind = tostring(kind or "")
    local hasCast = HasPositiveDurationValue(spellData.castTime)
        or HasPositiveDurationValue(spellData.castTimeExtra)
        or HasPositiveDurationValue(spellData.castTimeSet)
    local hasChannel = HasPositiveDurationValue(spellData.channelTime)
        or HasPositiveDurationValue(spellData.channelDuration)
        or HasPositiveDurationValue(spellData.channelTimeSet)
    if kind == "cast" then
        return hasCast == true
    end
    if kind == "channel" then
        return hasChannel == true and hasCast ~= true
    end
    return false
end

local function SpellHasAuraDeltaFingerprint(spellData)
    return type(spellData) == "table" and spellData.castStartAuraDelta == true
end

local function SpellHasTargetClearFingerprint(spellData)
    return type(spellData) == "table" and type(spellData.targetClearOnCastStart) == "boolean"
end

local function GetRuntimeMobData(runtime)
    if type(runtime) ~= "table" then
        return nil
    end
    local root = Data and type(Data.GetTrashCDDataRoot) == "function" and Data.GetTrashCDDataRoot() or nil
    local mapID = tonumber(runtime.matchedMapID)
    local npcID = tonumber(runtime.matchedNPCID)
    local mapData = mapID and type(root) == "table" and type(root[mapID]) == "table" and root[mapID] or nil
    local mobs = mapData and type(mapData.mobs) == "table" and mapData.mobs or nil
    return npcID and mobs and mobs[npcID] or nil
end

local function GetCurrentTrashResolveContext()
    if not (Data and type(Data.GetCurrentInstanceContext) == "function" and type(Data.NormalizeNameKey) == "function") then
        return nil, nil
    end
    local _instanceID, dungeonName = Data.GetCurrentInstanceContext()
    local dungeonKey = Data.NormalizeNameKey(dungeonName)
    if dungeonKey == "" then
        return nil, nil
    end
    local calibration = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Calibration or nil
    local mapID = calibration and type(calibration.GetCurrentTrashMapID) == "function"
        and tonumber(calibration.GetCurrentTrashMapID(dungeonKey))
        or nil
    if not mapID then
        return nil, nil
    end
    return dungeonKey, mapID
end

local function TryResolveRuntimeStartCandidate(runtime)
    if type(runtime) ~= "table" then
        return nil
    end
    local unit = tostring(runtime._nameplateUnit or runtime._debugUnit or "")
    if unit == "" then
        return nil
    end

    local observation = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Observation or nil
    local inference = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Inference or nil
    if not (observation and type(observation.CollectObservedUnit) == "function" and inference and type(inference.ResolveCandidates) == "function") then
        return nil
    end

    local dungeonKey, mapID = GetCurrentTrashResolveContext()
    if not dungeonKey or not mapID then
        return nil
    end

    local traits = Data and type(Data.GetTrashMobTraitsRoot) == "function" and Data.GetTrashMobTraitsRoot() or nil
    local traitRows = type(traits) == "table" and type(traits.rows) == "table" and traits.rows or nil
    if type(traitRows) ~= "table" then
        return nil
    end

    local obs = observation.CollectObservedUnit(unit)
    if type(obs) ~= "table" then
        return nil
    end
    obs.unit = unit
    obs.inCombat = UnitAffectingCombat(unit) == true
    obs.sawCastStart = runtime.sawCastStart or false
    obs.sawChannelStart = runtime.sawChannelStart or false
    obs.sawInterrupted = runtime.sawInterrupted or false
    obs.firstCastAt = runtime.firstCastAt
    obs.firstChannelAt = runtime.firstChannelAt

    local result = inference.ResolveCandidates(obs, dungeonKey, traitRows, runtime, mapID, GetTime())
    local resolved = type(result) == "table" and type(result.resolved) == "table" and result.resolved or nil
    local npcID = tonumber(resolved and resolved.npcID)
    if not npcID then
        return nil
    end

    runtime.matchedMapID = mapID
    runtime.matchedNPCID = npcID
    runtime.lastResolvedName = tostring(resolved.name or runtime.lastResolvedName or "")
    return resolved
end

local function RuntimeNeedsTargetFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table" and type(spellData.targetExists) == "boolean" and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function RuntimeNeedsTargetAPIFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table" and type(spellData.targetAPIExists) == "boolean" and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function RuntimeNeedsTargetUnitFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table"
            and type(spellData.castStartTargetUnitExists) == "boolean"
            and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function RuntimeNeedsAuraDeltaFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if SpellHasAuraDeltaFingerprint(spellData) and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function RuntimeNeedsTargetClearFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if SpellHasTargetClearFingerprint(spellData) and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function RuntimeNeedsTargetSwitchFingerprint(runtime, kind)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table"
            and type(spellData.castStartChangeTarget) == "boolean"
            and SpellMatchesStartKind(spellData, kind or runtime.activeCastKind) then
            return true
        end
    end
    return false
end

local function SpellMatchesRuntimeFingerprints(spellData, runtime)
    if type(spellData) ~= "table" or type(runtime) ~= "table" then
        return true
    end
    if type(runtime.activeCastTargetExists) == "boolean"
        and type(spellData.targetExists) == "boolean"
        and spellData.targetExists ~= runtime.activeCastTargetExists then
        return false
    end
    if type(runtime.activeCastTargetAPIExists) == "boolean"
        and type(spellData.targetAPIExists) == "boolean"
        and spellData.targetAPIExists ~= runtime.activeCastTargetAPIExists then
        return false
    end
    if type(runtime.activeCastTargetUnitExists) == "boolean"
        and type(spellData.castStartTargetUnitExists) == "boolean"
        and spellData.castStartTargetUnitExists ~= runtime.activeCastTargetUnitExists then
        return false
    end
    if runtime.activeCastAuraDeltaResolved == true then
        local wantsAuraDelta = SpellHasAuraDeltaFingerprint(spellData)
        if runtime.activeCastAuraDeltaMatched == true then
            return wantsAuraDelta == true
        end
        if wantsAuraDelta then
            return false
        end
    end
    if runtime.activeCastTargetClearResolved == true
        and type(spellData.targetClearOnCastStart) == "boolean"
        and spellData.targetClearOnCastStart ~= (runtime.activeCastTargetClearedOnStart == true) then
        return false
    end
    if runtime.activeCastTargetSwitchResolved == true
        and type(spellData.castStartChangeTarget) == "boolean"
        and spellData.castStartChangeTarget ~= (runtime.activeCastTargetSwitched == true) then
        return false
    end
    return true
end

local function ResolveRuntimeSpellForStartVoice(runtime)
    local customResolver = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.ResolveObservedStartSpellID or nil
    if type(customResolver) == "function" and type(runtime) == "table" then
        local ok, forcedSpellID = pcall(customResolver, runtime, tostring(runtime.activeCastKind or ""))
        local forcedID = ok and tonumber(forcedSpellID) or nil
        if forcedID and forcedID > 0 then
            runtime.activeSpellID = forcedID
            runtime.activeSpellAmbiguous = false
            return forcedID
        end
    end

    TryResolveRuntimeStartCandidate(runtime)

    local fallbackID = tonumber(runtime and runtime.activeSpellID)
    local mobData = GetRuntimeMobData(runtime)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if not spells then
        if runtime and runtime.activeSpellAmbiguous == true then
            return nil
        end
        return fallbackID
    end

    local activeKind = tostring(runtime.activeCastKind or "")
    local startAt = tonumber(runtime.activeCastStartAt)
    local observedID = tonumber(runtime and runtime.activeObservedSpellID)
    if observedID then
        local observedSpell = spells[observedID]
        if type(observedSpell) == "table"
            and SpellMatchesStartKind(observedSpell, activeKind)
            and SpellMatchesRuntimeFingerprints(observedSpell, runtime) then
            runtime.activeSpellID = observedID
            runtime.activeSpellAmbiguous = false
            return observedID
        end
    end
    if fallbackID then
        local fallbackSpell = spells[fallbackID]
        if type(fallbackSpell) == "table"
            and SpellMatchesStartKind(fallbackSpell, activeKind)
            and SpellMatchesRuntimeFingerprints(fallbackSpell, runtime) then
            runtime.activeSpellAmbiguous = false
            return fallbackID
        end
    end
    local bestSpellID, bestScore, tieCount = nil, math.huge, 0
    for spellID, spellData in pairs(spells) do
        if type(spellData) == "table"
            and SpellMatchesRuntimeFingerprints(spellData, runtime)
            and SpellMatchesStartKind(spellData, activeKind) then
            local sid = tonumber(spellData.spellID) or tonumber(spellID)
            local predictedAt = sid and runtime.nextSpellStartAt and tonumber(runtime.nextSpellStartAt[sid]) or nil
            local score = predictedAt and startAt and math.abs(startAt - predictedAt) or 9999
            if fallbackID and sid == fallbackID then
                score = score - 0.01
            end
            if sid and score < (bestScore - 0.05) then
                bestSpellID, bestScore, tieCount = sid, score, 1
            elseif sid and math.abs(score - bestScore) <= 0.05 then
                tieCount = tieCount + 1
            end
        end
    end
    if bestSpellID and tieCount <= 1 then
        runtime.activeSpellID = bestSpellID
        runtime.activeSpellAmbiguous = false
        return bestSpellID
    end
    return nil
end

local function HasRuntimeTimerIDs(runtime)
    if type(runtime) ~= "table" then
        return false
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    if bySpell and next(bySpell) ~= nil then
        return true
    end
    local ids = type(runtime.scriptEventIDs) == "table" and runtime.scriptEventIDs or nil
    if ids and #ids > 0 then
        return true
    end
    local byScriptSpell = type(runtime.scriptEventIDsBySpellID) == "table" and runtime.scriptEventIDsBySpellID or nil
    return byScriptSpell and next(byScriptSpell) ~= nil
end

function Mod.CancelRuntimeScriptEvents(runtime)
    if not runtime or type(runtime) ~= "table" then
        return
    end
    if runtime._trashCachePendingRecovery == true then
        return
    end
    if not HasRuntimeTimerIDs(runtime) then
        return
    end
    local scheduler = GetScheduler()
    if scheduler and type(scheduler.CancelTrashLocalTimers) == "function" then
        scheduler:CancelTrashLocalTimers(runtime)
    end
    if not (C_EncounterTimeline and C_EncounterTimeline.CancelScriptEvent) then
        runtime.scriptEventIDs = {}
        return
    end
    local ids = runtime.scriptEventIDs
    if type(ids) ~= "table" then
        runtime.scriptEventIDs = {}
        return
    end
    for i = #ids, 1, -1 do
        local eventID = tonumber(ids[i])
        if eventID and eventID > 0 then
            if RuntimeConfig and type(RuntimeConfig.ClearEncounterEventSettings) == "function" then
                RuntimeConfig.ClearEncounterEventSettings(eventID)
            end
            if RuntimeConfig and type(RuntimeConfig.ClearTimelineEventMeta) == "function" then
                RuntimeConfig.ClearTimelineEventMeta(eventID)
            end
            pcall(C_EncounterTimeline.CancelScriptEvent, eventID)
        end
    end
    wipe(ids)
    if type(runtime.scriptEventIDsBySpellID) == "table" then
        wipe(runtime.scriptEventIDsBySpellID)
    end
end

function Mod.CancelRuntimeSpellScriptEvents(runtime, spellID)
    if not runtime or type(runtime) ~= "table" then
        return
    end
    if runtime._trashCachePendingRecovery == true then
        return
    end
    local sid = tonumber(spellID)
    if not sid then
        return
    end
    local scheduler = GetScheduler()
    if scheduler and type(scheduler.CancelTrashLocalTimer) == "function" then
        scheduler:CancelTrashLocalTimer(runtime, sid)
    end
    local bySpell = type(runtime.scriptEventIDsBySpellID) == "table" and runtime.scriptEventIDsBySpellID or nil
    local ids = bySpell and bySpell[sid] or nil
    if type(ids) ~= "table" then
        return
    end
    local flat = type(runtime.scriptEventIDs) == "table" and runtime.scriptEventIDs or nil
    for i = #ids, 1, -1 do
        local eventID = tonumber(ids[i])
        if eventID and eventID > 0 then
            if RuntimeConfig and type(RuntimeConfig.ClearEncounterEventSettings) == "function" then
                RuntimeConfig.ClearEncounterEventSettings(eventID)
            end
            if RuntimeConfig and type(RuntimeConfig.ClearTimelineEventMeta) == "function" then
                RuntimeConfig.ClearTimelineEventMeta(eventID)
            end
            pcall(C_EncounterTimeline.CancelScriptEvent, eventID)
            if type(flat) == "table" then
                for j = #flat, 1, -1 do
                    if tonumber(flat[j]) == eventID then
                        table.remove(flat, j)
                    end
                end
            end
        end
    end
    bySpell[sid] = nil
end

function Mod.AddRuntimeScriptEvent(runtime, mobData, spellData, remaining, fallbackIcon)
    if not runtime or not mobData or not spellData then
        DebugPrint(string.format("output add=nil reason=missing runtime=%s mob=%s spellData=%s",
            tostring(runtime ~= nil), tostring(mobData ~= nil), tostring(spellData ~= nil)))
        return
    end
    if RuntimeConfig and type(RuntimeConfig.IsDisabledInCurrentEncounter) == "function"
        and RuntimeConfig.IsDisabledInCurrentEncounter() == true then
        DebugPrint(string.format("output add=nil reason=boss-disabled spell=%s",
            tostring(spellData and spellData.spellID or "nil")))
        return
    end
    local scheduler = GetScheduler()
    if not (scheduler and type(scheduler.RegisterTrashLocalTimer) == "function") then
        DebugPrint("output add=nil reason=no-scheduler")
        return
    end
    local delay = tonumber(remaining)
    if not delay or delay < SCRIPT_EVENT_MIN_DELAY then
        DebugPrint(string.format("output add=nil reason=bad-delay spell=%s delay=%s",
            tostring(spellData and spellData.spellID or "nil"), tostring(remaining or "nil")))
        return
    end

    local spellID = tonumber(spellData.spellID)
    if not spellID or spellID <= 0 then
        DebugPrint(string.format("output add=nil reason=bad-spell spell=%s", tostring(spellData and spellData.spellID or "nil")))
        return
    end
    local runtimeNPCID = tonumber(runtime.matchedNPCID)
    local mobNPCID = tonumber(mobData.npcID)
    if not runtimeNPCID or not mobNPCID or runtimeNPCID ~= mobNPCID then
        DebugPrint(string.format("output add=nil reason=npc-mismatch runtimeNPC=%s mobNPC=%s spell=%s",
            tostring(runtimeNPCID or "nil"), tostring(mobNPCID or "nil"), tostring(spellID)))
        return
    end

    local info = nil
    if C_Spell and C_Spell.GetSpellInfo then
        info = C_Spell.GetSpellInfo(spellID)
    end

    local meta = RuntimeConfig and type(RuntimeConfig.BuildResolvedMeta) == "function"
        and RuntimeConfig.BuildResolvedMeta(runtime, mobData, spellData, tonumber(spellData.iconFileID) or (info and tonumber(info.iconID)) or tonumber(fallbackIcon) or 136243)
        or nil
    if type(meta) ~= "table" then
        DebugPrint(string.format("output add=nil reason=meta-nil map=%s npc=%s spell=%s delay=%.2f",
            tostring(runtime.matchedMapID or mobData.mapID or "nil"), tostring(runtimeNPCID or "nil"), tostring(spellID), delay))
        return
    end

    local ok, result = pcall(scheduler.RegisterTrashLocalTimer, scheduler, runtime, mobData, spellData, delay, meta)
    local timerID = tonumber(result)
    if not (ok and timerID and timerID > 0) then
        DebugPrint(string.format("output add=nil reason=scheduler-failed spell=%s delay=%.2f ok=%s result=%s",
            tostring(spellID), delay, tostring(ok), tostring(result)))
        return
    end
    DebugPrint(string.format("output add=ok timer=%s map=%s npc=%s spell=%s delay=%.2f name=%s",
        tostring(timerID), tostring(runtime.matchedMapID or mobData.mapID or "nil"), tostring(runtimeNPCID or "nil"),
        tostring(spellID), delay, tostring(meta.displayName or spellData.name or "?")))
end

local function TryPlayRuntimeSpellStartVoice(runtime)
    local scheduler = GetScheduler()
    if not (scheduler and type(scheduler.PlayTrashObservedCastStartVoice) == "function") then
        VoiceDebugPrint("cast-start skip reason=no-scheduler-playback")
        return false
    end
    if type(runtime) ~= "table" then
        VoiceDebugPrint("cast-start skip reason=bad-runtime")
        return false
    end
    local sid = ResolveRuntimeSpellForStartVoice(runtime)
    if not sid then
        VoiceDebugPrint(string.format(
            "cast-start skip reason=no-resolved-spell runtime=%s kind=%s activeSpell=%s ambiguous=%s",
            tostring(runtime),
            tostring(runtime.activeCastKind or ""),
            tostring(runtime.activeSpellID or "nil"),
            tostring(runtime.activeSpellAmbiguous == true)
        ))
        return false
    end
    VoiceDebugPrint(string.format(
        "cast-start resolved runtime=%s spell=%s kind=%s startAt=%.3f",
        tostring(runtime),
        tostring(sid),
        tostring(runtime.activeCastKind or ""),
        tonumber(runtime.activeCastStartAt) or 0
    ))
    local ok, err = scheduler:PlayTrashObservedCastStartVoice(runtime, sid)
    if ok then
        runtime._voicePlayedForSeq = tonumber(runtime.activeCastSeq)
    end
    VoiceDebugPrint(string.format(
        "cast-start scheduler-result runtime=%s spell=%s ok=%s err=%s",
        tostring(runtime),
        tostring(sid),
        tostring(ok),
        tostring(err or "")
    ))
    return ok, err
end

local function DelayRuntimeCastStartVoice(runtime, kind)
    if not (C_Timer and C_Timer.After) then
        return false
    end
    local seq = tonumber(runtime and runtime.activeCastSeq)
    if not seq then
        return false
    end
    if runtime._castStartVoiceDelaySeq == seq then
        return false
    end
    runtime._castStartVoiceDelaySeq = seq
    C_Timer.After(CAST_START_VOICE_TARGET_DELAY, function()
        if type(runtime) ~= "table" or tonumber(runtime.activeCastSeq) ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        TryPlayRuntimeSpellStartVoice(runtime)
    end)
    return true
end

local function DelayRuntimeTargetSwitchCastStartVoice(runtime, kind)
    if not (C_Timer and C_Timer.After) then
        return false
    end
    local seq = tonumber(runtime and runtime.activeCastSeq)
    if not seq then
        return false
    end
    if runtime._castStartTargetSwitchDelaySeq == seq then
        return false
    end
    runtime._castStartTargetSwitchDelaySeq = seq
    C_Timer.After(CAST_START_VOICE_TARGET_SWITCH_DELAY, function()
        if type(runtime) ~= "table" or tonumber(runtime.activeCastSeq) ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        Mod.PlayRuntimeCastStartVoice(runtime, kind)
    end)
    return true
end

local function DelayRuntimeTargetClearCastStartVoice(runtime, kind)
    if not (C_Timer and C_Timer.After) then
        return false
    end
    local seq = tonumber(runtime and runtime.activeCastSeq)
    if not seq then
        return false
    end
    if runtime._castStartTargetClearDelaySeq == seq then
        return false
    end
    runtime._castStartTargetClearDelaySeq = seq
    C_Timer.After(CAST_START_VOICE_TARGET_CLEAR_DELAY, function()
        if type(runtime) ~= "table" or tonumber(runtime.activeCastSeq) ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        Mod.PlayRuntimeCastStartVoice(runtime, kind)
    end)
    return true
end

local function DelayRuntimeAuraDeltaCastStartVoice(runtime, kind)
    if not (AuraDelta and type(AuraDelta.ScheduleRuntimeCheck) == "function") then
        return false
    end
    local seq = tonumber(runtime and runtime.activeCastSeq)
    if not seq then
        return false
    end
    if runtime._castStartAuraDeltaDelaySeq == seq then
        return false
    end
    runtime._castStartAuraDeltaDelaySeq = seq
    return AuraDelta.ScheduleRuntimeCheck(
        runtime,
        kind,
        CAST_START_AURA_DELTA_DELAY,
        CAST_START_AURA_DELTA_PRE_WINDOW,
        CAST_START_AURA_DELTA_POST_WINDOW,
        function(matched, row)
            if type(runtime) ~= "table" or tonumber(runtime.activeCastSeq) ~= seq then
                return
            end
            if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
                return
            end
            runtime.activeCastAuraDeltaResolved = true
            runtime.activeCastAuraDeltaMatched = matched == true
            runtime.activeCastAuraDeltaUnit = matched and row and row.unit or nil
            runtime.activeCastAuraDeltaAt = matched and tonumber(row and row.at) or GetTime()
            if runtime.pendingStartAdvance == true then
                RequestRuntimeRefresh(runtime, "cast-aura-delta")
            end
            Mod.PlayRuntimeCastStartVoice(runtime, kind)
        end
    )
end

function Mod.PlayRuntimeCastStartVoice(runtime, kind)
    if type(runtime) ~= "table" then
        return false
    end
    local castKind = tostring(kind or runtime.activeCastKind or "")
    if castKind == "channel"
        and runtime.transitionCastKind == "cast"
        and runtime.transitionIntoKind == castKind then
        VoiceDebugPrint(string.format(
            "cast-start skip reason=transition-channel runtime=%s kind=%s",
            tostring(runtime),
            tostring(castKind)
        ))
        return false
    end

    if RuntimeNeedsAuraDeltaFingerprint(runtime, castKind) and runtime.activeCastAuraDeltaResolved ~= true then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=aura-delta runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeAuraDeltaCastStartVoice(runtime, castKind)
    end

    if RuntimeNeedsTargetFingerprint(runtime, castKind) and type(runtime.activeCastTargetExists) ~= "boolean" then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=target-exists runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeCastStartVoice(runtime, castKind)
    end

    if RuntimeNeedsTargetAPIFingerprint(runtime, castKind) and type(runtime.activeCastTargetAPIExists) ~= "boolean" then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=target-api runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeCastStartVoice(runtime, castKind)
    end

    if RuntimeNeedsTargetUnitFingerprint(runtime, castKind) and type(runtime.activeCastTargetUnitExists) ~= "boolean" then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=target-unit-exists runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeCastStartVoice(runtime, castKind)
    end

    if RuntimeNeedsTargetClearFingerprint(runtime, castKind) and runtime.activeCastTargetClearResolved ~= true then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=target-clear runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeTargetClearCastStartVoice(runtime, castKind)
    end

    if RuntimeNeedsTargetSwitchFingerprint(runtime, castKind) and runtime.activeCastTargetSwitchResolved ~= true then
        VoiceDebugPrint(string.format(
            "cast-start wait reason=target-switch runtime=%s kind=%s seq=%s",
            tostring(runtime),
            tostring(castKind),
            tostring(runtime.activeCastSeq or "nil")
        ))
        return DelayRuntimeTargetSwitchCastStartVoice(runtime, castKind)
    end

    VoiceDebugPrint(string.format(
        "cast-start direct-try runtime=%s kind=%s spell=%s",
        tostring(runtime),
        tostring(castKind),
        tostring(runtime.activeSpellID or "nil")
    ))
    return TryPlayRuntimeSpellStartVoice(runtime)
end
