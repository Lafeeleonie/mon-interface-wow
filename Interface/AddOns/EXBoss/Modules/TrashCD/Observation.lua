---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Observation or {}
ExBoss.TrashCD.Observation = Mod
ExBoss.Trash.Observation = Mod
local TRASH_CASTBAR_STOP_EVENT = "EXBOSS_TRASH_CASTBAR_STOP"

local SNAPSHOT_DELAY = 0.10
local CAST_TARGET_SAMPLE_DELAY = 0.10
local CAST_TARGET_CLEAR_WINDOW = 0.10
local CAST_TARGET_SWITCH_WINDOW = 0.10
local CAST_SUCCESS_TARGET_BUFFCOUNT_DELAY = 0.10
local MAX_NAMEPLATES = 40
local CHANNEL_REFRESH_INTERRUPTIBLE_WINDOW = 1.00


local function IsDebug()
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    return test and type(test.IsDebug) == "function" and test.IsDebug() == true
end

local function DebugPrint(runtime, msg)
    if not IsDebug() then
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashObs|r " .. tostring(msg or ""))
    end
end

local function IsTargetClearPrintEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TargetClear and ExBoss.Debug.TargetClear.enabled == true
end

local function TargetClearPrint(runtime, msg)
    if not IsTargetClearPrintEnabled() then
        return
    end
    local prefix = "|cffffaa33ExBoss TargetClear|r "
    if type(runtime) == "table" then
        prefix = string.format(
            "|cffffaa33ExBoss TargetClear|r map=%s npc=%s unit=%s ",
            tostring(runtime.matchedMapID or "nil"),
            tostring(runtime.matchedNPCID or "nil"),
            tostring(runtime._nameplateUnit or runtime._debugUnit or "?")
        )
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg or ""))
    end
end

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
        test:RefreshUnit(unit, reason or "fingerprint-refresh", true)
    end
    local seq = tonumber(runtime.activeCastSeq)
    if runtime.activeCastStartAt ~= nil
        and seq ~= nil
        and runtime._voicePlayedForSeq ~= seq then
        local output = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
        if output and type(output.PlayRuntimeCastStartVoice) == "function" then
            output.PlayRuntimeCastStartVoice(runtime, tostring(runtime.activeCastKind or ""))
        end
    end
end

local function RetryRuntimeCastStartVoice(runtime, kind, seq)
    if type(runtime) ~= "table" then
        return
    end
    if tonumber(runtime.activeCastSeq) ~= tonumber(seq) then
        return
    end
    if runtime.activeCastStartAt == nil then
        return
    end
    if runtime._voicePlayedForSeq == tonumber(seq) then
        return
    end
    local output = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
    if output and type(output.PlayRuntimeCastStartVoice) == "function" then
        output.PlayRuntimeCastStartVoice(runtime, tostring(kind or runtime.activeCastKind or ""))
    end
end


local function NormalizeNameplateUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = unit:match("^nameplate(%d+)$")
    if not index then
        return nil
    end
    return "nameplate" .. index
end

local function NormalizeCastBarID(castBarID)
    local id = tonumber(castBarID)
    if id and id >= 0 then
        return id
    end
    return nil
end

local function EmitTrashCastBarStop(runtime, castKind, castBarID)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local kind = tostring(castKind or "")
    if kind ~= "cast" and kind ~= "channel" then
        return
    end
    local normalizedCastBarID = NormalizeCastBarID(castBarID)
    if normalizedCastBarID == nil then
        return
    end
    ExwindTools:SendEvent(TRASH_CASTBAR_STOP_EVENT, {
        runtime = runtime,
        castKind = kind,
        castBarID = normalizedCastBarID,
    })
end

local function ActiveCastMatches(runtime, castBarID)
    if type(runtime) ~= "table" or not runtime.activeCastStartAt then
        return false
    end
    local activeID = NormalizeCastBarID(runtime.activeCastBarID)
    local eventID = NormalizeCastBarID(castBarID)
    if activeID ~= nil and eventID ~= nil then
        return activeID == eventID
    end
    return activeID == nil and eventID == nil
end

local function SafeUnitTargetTokenExists(unit)
    if type(unit) ~= "string" or type(UnitExists) ~= "function" then
        return nil
    end
    local ok, exists = pcall(UnitExists, unit .. "target")
    if not ok then
        return nil
    end
    return exists == true
end

local function SafeUnitShouldDisplaySpellTargetName(unit)
    if type(unit) ~= "string" or type(UnitShouldDisplaySpellTargetName) ~= "function" then
        return nil
    end
    local ok, shouldDisplay = pcall(UnitShouldDisplaySpellTargetName, unit)
    if not ok then
        return nil
    end
    return shouldDisplay == true
end

local function SafeUnitHasSpellTarget(unit)
    return SafeUnitTargetTokenExists(unit)
end

local function SafeGetTargetIsTank(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local targetUnit = unit .. "target"
    if type(UnitExists) ~= "function" or not UnitExists(targetUnit) then
        return nil
    end
    if type(UnitGroupRolesAssigned) ~= "function" then
        return nil
    end
    local ok, role = pcall(UnitGroupRolesAssigned, targetUnit)
    if not ok or type(role) ~= "string" then
        return nil
    end
    return role == "TANK"
end

local function SafeUnitTargetPresence(unit)
    return SafeUnitTargetTokenExists(unit)
end

local function ResetRuntimeTargetState(runtime)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateInCombat = false
    runtime.targetStateTracking = false
    runtime.targetStateStartedAt = nil
    runtime.targetStateExists = nil
    runtime.targetStateLastChangedAt = nil
    runtime.targetStateTransitions = nil
    runtime.targetSwitchEvents = nil
end

local function StartRuntimeTargetStateTracking(runtime, unit, now)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateTracking = true
    runtime.targetStateStartedAt = tonumber(now) or GetTime()
    runtime.targetStateExists = SafeUnitTargetPresence(unit)
    runtime.targetStateLastChangedAt = nil
    runtime.targetStateTransitions = {}
    runtime.targetSwitchEvents = {}
end

local function AppendRuntimeTargetTransition(runtime, at, fromExists, toExists)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateTransitions = type(runtime.targetStateTransitions) == "table" and runtime.targetStateTransitions or
    {}
    runtime.targetStateTransitions[#runtime.targetStateTransitions + 1] = {
        at = tonumber(at) or GetTime(),
        fromExists = fromExists,
        toExists = toExists,
    }
    local cutoff = (tonumber(at) or GetTime()) - 1.0
    while #runtime.targetStateTransitions > 0 do
        local first = runtime.targetStateTransitions[1]
        if type(first) == "table" and tonumber(first.at) and tonumber(first.at) < cutoff then
            table.remove(runtime.targetStateTransitions, 1)
        else
            break
        end
    end
end

local function AppendRuntimeTargetSwitchEvent(runtime, at)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetSwitchEvents = type(runtime.targetSwitchEvents) == "table" and runtime.targetSwitchEvents or {}
    runtime.targetSwitchEvents[#runtime.targetSwitchEvents + 1] = tonumber(at) or GetTime()
    local cutoff = (tonumber(at) or GetTime()) - 1.0
    while #runtime.targetSwitchEvents > 0 do
        if (runtime.targetSwitchEvents[1] or 0) < cutoff then
            table.remove(runtime.targetSwitchEvents, 1)
        else
            break
        end
    end
end

local function HasTargetSwitchEventInWindow(runtime, windowStartAt, windowEndAt)
    local events = type(runtime) == "table" and runtime.targetSwitchEvents or nil
    if type(events) ~= "table" then
        return false, nil
    end
    for i = 1, #events do
        local at = events[i]
        if type(at) == "number" and at >= windowStartAt and at <= windowEndAt then
            return true, at
        end
    end
    return false, nil
end

local function UpdateRuntimeTargetState(runtime, unit, now)
    if type(runtime) ~= "table" or type(unit) ~= "string" then
        return
    end
    if runtime.targetStateTracking ~= true then
        return
    end
    now = tonumber(now) or GetTime()
    local previousExists = runtime.targetStateExists
    local currentExists = SafeUnitTargetPresence(unit)
    if type(previousExists) == "boolean"
        and type(currentExists) == "boolean"
        and previousExists ~= currentExists then
        if previousExists == true and currentExists == false then
            AppendRuntimeTargetTransition(runtime, now, previousExists, currentExists)
            runtime.targetStateLastChangedAt = now
        end
    end
    if type(currentExists) == "boolean" then
        runtime.targetStateExists = currentExists
    end
end

local function HasTargetClearTransitionInWindow(runtime, windowStartAt, windowEndAt)
    local transitions = type(runtime) == "table" and runtime.targetStateTransitions or nil
    if type(transitions) ~= "table" then
        return false, nil
    end
    for i = 1, #transitions do
        local row = transitions[i]
        local at = type(row) == "table" and tonumber(row.at) or nil
        if at
            and at >= windowStartAt
            and at <= windowEndAt
            and row.fromExists == true
            and row.toExists == false then
            return true, at
        end
    end
    return false, nil
end

local function SafeUnitBuffCount(unit)
    if type(unit) ~= "string" then
        return nil
    end
    ---@diagnostic disable-next-line: undefined-field
    local fn = _G.EXDB and _G.EXDB._s
    if type(fn) ~= "function" then
        return nil
    end
    local ok, _, _, _, _, _, _, buffCount = pcall(fn, unit)
    if not ok then
        return nil
    end
    return type(buffCount) == "number" and buffCount or nil
end

local function ScheduleCastTargetSnapshot(runtime, unit, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        return
    end
    C_Timer.After(CAST_TARGET_SAMPLE_DELAY, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local hasTarget = SafeUnitHasSpellTarget(unit)
        local hasTargetAPI = SafeUnitShouldDisplaySpellTargetName(unit)
        local hasTargetUnitExists = SafeUnitTargetTokenExists(unit)
        if hasTarget == nil and hasTargetAPI == nil and hasTargetUnitExists == nil then
            DebugPrint(runtime, string.format(
                "target-snapshot unit=%s seq=%s kind=%s castBarID=%s result=nil api=nil strict=nil",
                tostring(unit or "?"),
                tostring(seq or "nil"),
                tostring(kind or "nil"),
                tostring(castBarID or "nil")
            ))
            return
        end
        local checkedAt = GetTime and GetTime() or nil
        runtime.activeCastTargetExists = hasTarget
        runtime.activeCastTargetCheckedAt = checkedAt
        runtime.activeCastTargetAPIExists = hasTargetAPI
        runtime.activeCastTargetAPICheckedAt = checkedAt
        runtime.activeCastTargetUnitExists = hasTargetUnitExists
        runtime.activeCastTargetUnitCheckedAt = checkedAt
        runtime.activeCastTargetIsTank = SafeGetTargetIsTank(unit)
        DebugPrint(runtime, string.format(
            "target-snapshot unit=%s seq=%s kind=%s castBarID=%s result=%s api=%s strict=%s at=%.3f",
            tostring(unit or "?"),
            tostring(seq or "nil"),
            tostring(kind or "nil"),
            tostring(castBarID or "nil"),
            tostring(hasTarget),
            tostring(hasTargetAPI),
            tostring(hasTargetUnitExists),
            tonumber(checkedAt) or 0
        ))
        if runtime.pendingStartAdvance == true then
            RequestRuntimeRefresh(runtime, "cast-target-snapshot")
        end
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ScheduleCastTargetClearSnapshot(runtime, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastTargetClearResolved = true
        runtime.activeCastTargetClearedOnStart = false
        return
    end
    C_Timer.After(CAST_TARGET_CLEAR_WINDOW, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local startAt = tonumber(runtime.activeCastStartAt)
        local windowStartAt = startAt and (startAt - CAST_TARGET_CLEAR_WINDOW) or nil
        local windowEndAt = startAt and (startAt + CAST_TARGET_CLEAR_WINDOW) or nil
        local matched, transitionAt = false, nil
        if windowStartAt and windowEndAt then
            matched, transitionAt = HasTargetClearTransitionInWindow(runtime, windowStartAt, windowEndAt)
        end
        runtime.activeCastTargetClearResolved = true
        runtime.activeCastTargetClearedOnStart = matched == true
        runtime.activeCastTargetClearCheckedAt = GetTime and GetTime() or nil
        runtime.activeCastTargetClearTransitionMatched = matched == true
        runtime.activeCastTargetClearTransitionAt = transitionAt
        TargetClearPrint(runtime, string.format(
            "snapshot seq=%s castBarID=%s activeSpell=%s observedSpell=%s state=%s window=[%.3f,%.3f] transition=%s transitionAt=%s cleared=%s",
            tostring(seq or "nil"),
            tostring(castBarID or "nil"),
            tostring(runtime.activeSpellID or "nil"),
            tostring(runtime.activeObservedSpellID or "nil"),
            tostring(runtime.targetStateExists),
            tonumber(windowStartAt) or 0,
            tonumber(windowEndAt) or 0,
            tostring(runtime.activeCastTargetClearTransitionMatched == true),
            tostring(runtime.activeCastTargetClearTransitionAt or "nil"),
            tostring(runtime.activeCastTargetClearedOnStart == true)
        ))
        DebugPrint(runtime, string.format(
            "target-clear-snapshot unit=%s seq=%s kind=%s castBarID=%s state=%s window=[%.3f,%.3f] cleared=%s transition=%s transitionAt=%s at=%.3f",
            tostring(runtime._nameplateUnit or "?"),
            tostring(seq or "nil"),
            tostring(kind or "nil"),
            tostring(castBarID or "nil"),
            tostring(runtime.targetStateExists),
            tonumber(windowStartAt) or 0,
            tonumber(windowEndAt) or 0,
            tostring(runtime.activeCastTargetClearedOnStart == true),
            tostring(runtime.activeCastTargetClearTransitionMatched == true),
            tostring(runtime.activeCastTargetClearTransitionAt or "nil"),
            tonumber(runtime.activeCastTargetClearCheckedAt) or 0
        ))
        if runtime.pendingStartAdvance == true then
            RequestRuntimeRefresh(runtime, "cast-target-clear-snapshot")
        end
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ScheduleCastTargetSwitchSnapshot(runtime, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastTargetSwitchResolved = true
        runtime.activeCastTargetSwitched = false
        return
    end
    C_Timer.After(CAST_TARGET_SWITCH_WINDOW, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local startAt = tonumber(runtime.activeCastStartAt)
        local windowStartAt = startAt and (startAt - CAST_TARGET_SWITCH_WINDOW) or nil
        local windowEndAt = startAt and (startAt + CAST_TARGET_SWITCH_WINDOW) or nil
        local matched, switchAt = false, nil
        if windowStartAt and windowEndAt then
            matched, switchAt = HasTargetSwitchEventInWindow(runtime, windowStartAt, windowEndAt)
        end
        runtime.activeCastTargetSwitchResolved = true
        runtime.activeCastTargetSwitched = matched == true
        runtime.activeCastTargetSwitchCheckedAt = GetTime and GetTime() or nil
        DebugPrint(runtime, string.format(
            "target-switch-snapshot unit=%s seq=%s kind=%s castBarID=%s window=[%.3f,%.3f] switched=%s switchAt=%s at=%.3f",
            tostring(runtime._nameplateUnit or "?"),
            tostring(seq or "nil"),
            tostring(kind or "nil"),
            tostring(castBarID or "nil"),
            tonumber(windowStartAt) or 0,
            tonumber(windowEndAt) or 0,
            tostring(matched == true),
            tostring(switchAt or "nil"),
            tonumber(runtime.activeCastTargetSwitchCheckedAt) or 0
        ))
        if runtime.pendingStartAdvance == true then
            RequestRuntimeRefresh(runtime, "cast-target-switch-snapshot")
        end
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ScheduleCastSuccessTargetBuffCountSnapshot(runtime, unit, kind, castBarID, seq)
    local targetUnit = type(unit) == "string" and (unit .. "target") or nil
    runtime.activeCastSuccessTargetBuffCountBefore = targetUnit and SafeUnitBuffCount(targetUnit) or nil
    runtime.activeCastSuccessTargetBuffCountAfter = nil
    runtime.activeCastSuccessTargetBuffCountDelta = nil
    runtime.activeCastSuccessTargetBuffCountResolved = false
    runtime.activeCastSuccessTargetBuffCountCheckedAt = nil
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastSuccessTargetBuffCountResolved = true
        return
    end
    C_Timer.After(CAST_SUCCESS_TARGET_BUFFCOUNT_DELAY, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local afterCount = targetUnit and SafeUnitBuffCount(targetUnit) or nil
        runtime.activeCastSuccessTargetBuffCountAfter = afterCount
        runtime.activeCastSuccessTargetBuffCountCheckedAt = GetTime and GetTime() or nil
        runtime.activeCastSuccessTargetBuffCountResolved = true
        local beforeCount = tonumber(runtime.activeCastSuccessTargetBuffCountBefore)
        if beforeCount ~= nil and type(afterCount) == "number" then
            runtime.activeCastSuccessTargetBuffCountDelta = afterCount - beforeCount
        else
            runtime.activeCastSuccessTargetBuffCountDelta = nil
        end
        if runtime.pendingSucceeded == true then
            RequestRuntimeRefresh(runtime, "cast-success-target-buffcount")
        end
    end)
end

local function ScheduleCastSuccessSelfBuffCountSnapshot(runtime, unit, kind, castBarID, seq)
    runtime.activeCastSuccessSelfBuffCountBefore = SafeUnitBuffCount(unit)
    runtime.activeCastSuccessSelfBuffCountAfter = nil
    runtime.activeCastSuccessSelfBuffCountDelta = nil
    runtime.activeCastSuccessSelfBuffCountResolved = false
    runtime.activeCastSuccessSelfBuffCountCheckedAt = nil
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastSuccessSelfBuffCountResolved = true
        return
    end
    C_Timer.After(CAST_SUCCESS_TARGET_BUFFCOUNT_DELAY, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local afterCount = SafeUnitBuffCount(unit)
        runtime.activeCastSuccessSelfBuffCountAfter = afterCount
        runtime.activeCastSuccessSelfBuffCountCheckedAt = GetTime and GetTime() or nil
        runtime.activeCastSuccessSelfBuffCountResolved = true
        local beforeCount = tonumber(runtime.activeCastSuccessSelfBuffCountBefore)
        if beforeCount ~= nil and type(afterCount) == "number" then
            runtime.activeCastSuccessSelfBuffCountDelta = afterCount - beforeCount
        else
            runtime.activeCastSuccessSelfBuffCountDelta = nil
        end
        if runtime.pendingSucceeded == true then
            RequestRuntimeRefresh(runtime, "cast-success-self-buffcount")
        end
    end)
end

local function ResolveResultKind(kind, wasSuccess)
    kind = tostring(kind or "")
    if kind == "channel" then
        return wasSuccess and "channel_success" or nil
    end
    return wasSuccess and "cast_success" or "cast_interrupted"
end

local function MarkBehavior(runtime, behavior, now)
    if type(runtime) ~= "table" then
        return
    end
    behavior = tostring(behavior or "")
    now = tonumber(now) or GetTime()
    runtime.lastBehavior = behavior
    runtime.lastBehaviorAt = now
    runtime.engagedAt = runtime.engagedAt or now
    if behavior == "cast_success" then
        runtime.sawCastSuccess = true
    elseif behavior == "cast_interrupted" then
        runtime.sawCastInterrupted = true
    elseif behavior == "channel_success" then
        runtime.sawChannelSuccess = true
    elseif behavior == "cast_into_channel" then
        runtime.sawCastIntoChannel = true
    end
end

local function ActiveSpellAllowsInterruptibleChannelRefresh(runtime)
    if type(runtime) ~= "table" then
        return false
    end
    local spellID = tonumber(runtime.activeSpellID)
    local bySpell = type(runtime.spellChannelRefreshOnInterruptible) == "table" and
    runtime.spellChannelRefreshOnInterruptible or nil
    return spellID ~= nil and bySpell and bySpell[spellID] == true
end

local function EnsureState(state)
    state = type(state) == "table" and state or {}
    state._unitFirstSeenAt = state._unitFirstSeenAt or {}
    state._observedByUnit = state._observedByUnit or {}
    state._runtimeByUnit = state._runtimeByUnit or {}
    return state
end

local function CapturePendingCastSnapshot(runtime)
    if type(runtime) ~= "table" or runtime.activeCastStartAt == nil then
        return nil
    end
    return {
        activeCastKind = runtime.activeCastKind,
        activeCastBarID = runtime.activeCastBarID,
        activeCastStartAt = runtime.activeCastStartAt,
        activeObservedSpellID = runtime.activeObservedSpellID,
        activeCastSeq = runtime.activeCastSeq,
        activeCastTargetExists = runtime.activeCastTargetExists,
        activeCastTargetCheckedAt = runtime.activeCastTargetCheckedAt,
        activeCastTargetAPIExists = runtime.activeCastTargetAPIExists,
        activeCastTargetAPICheckedAt = runtime.activeCastTargetAPICheckedAt,
        activeCastTargetUnitExists = runtime.activeCastTargetUnitExists,
        activeCastTargetUnitCheckedAt = runtime.activeCastTargetUnitCheckedAt,
        activeCastTargetIsTank = runtime.activeCastTargetIsTank,
        activeCastTargetClearResolved = runtime.activeCastTargetClearResolved,
        activeCastTargetClearedOnStart = runtime.activeCastTargetClearedOnStart,
        activeCastTargetClearSeen = runtime.activeCastTargetClearSeen,
        activeCastTargetClearCheckedAt = runtime.activeCastTargetClearCheckedAt,
        activeCastTargetClearEventAt = runtime.activeCastTargetClearEventAt,
        activeCastTargetClearTransitionMatched = runtime.activeCastTargetClearTransitionMatched,
        activeCastTargetClearBaselineExists = runtime.activeCastTargetClearBaselineExists,
        activeCastTargetClearLastKnownExists = runtime.activeCastTargetClearLastKnownExists,
        activeCastTargetClearTransitionAt = runtime.activeCastTargetClearTransitionAt,
        activeCastTargetClearTransitionFromExists = runtime.activeCastTargetClearTransitionFromExists,
        activeCastTargetClearTransitionToExists = runtime.activeCastTargetClearTransitionToExists,
        activeCastAuraDeltaResolved = runtime.activeCastAuraDeltaResolved,
        activeCastAuraDeltaMatched = runtime.activeCastAuraDeltaMatched,
        activeCastAuraDeltaUnit = runtime.activeCastAuraDeltaUnit,
        activeCastAuraDeltaAt = runtime.activeCastAuraDeltaAt,
        activeCastSuccessTargetBuffCountBefore = runtime.activeCastSuccessTargetBuffCountBefore,
        activeCastSuccessTargetBuffCountAfter = runtime.activeCastSuccessTargetBuffCountAfter,
        activeCastSuccessTargetBuffCountDelta = runtime.activeCastSuccessTargetBuffCountDelta,
        activeCastSuccessTargetBuffCountResolved = runtime.activeCastSuccessTargetBuffCountResolved,
        activeCastSuccessTargetBuffCountCheckedAt = runtime.activeCastSuccessTargetBuffCountCheckedAt,
        activeCastSuccessSelfBuffCountBefore = runtime.activeCastSuccessSelfBuffCountBefore,
        activeCastSuccessSelfBuffCountAfter = runtime.activeCastSuccessSelfBuffCountAfter,
        activeCastSuccessSelfBuffCountDelta = runtime.activeCastSuccessSelfBuffCountDelta,
        activeCastSuccessSelfBuffCountResolved = runtime.activeCastSuccessSelfBuffCountResolved,
        activeCastSuccessSelfBuffCountCheckedAt = runtime.activeCastSuccessSelfBuffCountCheckedAt,
        activeSpellID = runtime.activeSpellID,
        activeSpellAmbiguous = runtime.activeSpellAmbiguous,
        activeSpellPredictedAt = runtime.activeSpellPredictedAt,
        activeSpellAnchorAt = runtime.activeSpellAnchorAt,
        activeSpellNextSeqIndex = runtime.activeSpellNextSeqIndex,
        transitionCastStartAt = runtime.transitionCastStartAt,
        transitionCastBarID = runtime.transitionCastBarID,
        transitionCastKind = runtime.transitionCastKind,
        transitionIntoKind = runtime.transitionIntoKind,
        pendingStartAdvance = runtime.pendingStartAdvance,
        pendingStartAdvanceAt = runtime.pendingStartAdvanceAt,
        pendingStartAdvanceKind = runtime.pendingStartAdvanceKind,
        pendingSucceeded = runtime.pendingSucceeded,
        pendingSucceededAt = runtime.pendingSucceededAt,
        pendingInterrupted = runtime.pendingInterrupted,
        pendingInterruptedAt = runtime.pendingInterruptedAt,
        pendingBehavior = runtime.pendingBehavior,
        queuedAt = GetTime(),
    }
end

local function QueuePendingCastSnapshot(runtime, reason)
    local snapshot = CapturePendingCastSnapshot(runtime)
    if not snapshot then
        return false
    end
    runtime.pendingResolvedCasts = runtime.pendingResolvedCasts or {}
    runtime.pendingResolvedCasts[#runtime.pendingResolvedCasts + 1] = snapshot
    DebugPrint(runtime, string.format(
        "queue-pending-cast reason=%s kind=%s startAt=%.3f spell=%s pendingSuccess=%s pendingInterrupt=%s queue=%d",
        tostring(reason or "?"),
        tostring(snapshot.activeCastKind or "nil"),
        tonumber(snapshot.activeCastStartAt) or 0,
        tostring(snapshot.activeObservedSpellID or snapshot.activeSpellID or "nil"),
        tostring(snapshot.pendingSucceeded == true),
        tostring(snapshot.pendingInterrupted == true),
        #runtime.pendingResolvedCasts
    ))
    return true
end

function Mod.CollectObservedUnit(unit)
    ---@diagnostic disable-next-line: undefined-field
    local _fn = _G.EXDB and _G.EXDB._s
    local lv, sx, pw, cl, slot5, slot6, bc, rbc, adj, uc
    if type(_fn) == "function" then
        lv, sx, pw, cl, slot5, slot6, bc, rbc, adj, uc = _fn(unit)
    end
    if type(lv) ~= "number" or lv <= 0 then lv = nil end
    return {
        unit = unit,
        level = lv,
        sex = sx,
        power = pw,
        classID = cl,
        buffCount = bc,
        rawBuffCount = rbc,
        mythicPlusBuffAdjusted = adj,
        unitClassification = uc,
    }
end

function Mod.TrackNameplate(state, unit, isHostileFn)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    if type(isHostileFn) == "function" and not isHostileFn(unit) then
        return
    end
    if not state._unitFirstSeenAt[unit] then
        state._unitFirstSeenAt[unit] = GetTime()
    end
    state._runtimeByUnit[unit] = state._runtimeByUnit[unit] or {}
    state._runtimeByUnit[unit]._nameplateUnit = unit
end

function Mod.UntrackNameplate(state, unit, cancelFn)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    local runtime = state._runtimeByUnit[unit]
    if runtime and type(cancelFn) == "function" then
        cancelFn(runtime)
    end
    state._unitFirstSeenAt[unit] = nil
    state._observedByUnit[unit] = nil
    state._runtimeByUnit[unit] = nil
end

function Mod.GetRuntimeObs(state, unit)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    state._runtimeByUnit[unit] = state._runtimeByUnit[unit] or {}
    return state._runtimeByUnit[unit]
end

function Mod.CollectTrackedNameplate(state, unit, isHostileFn, cancelFn, forceSnapshot)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    if type(isHostileFn) == "function" and not isHostileFn(unit) then
        Mod.UntrackNameplate(state, unit, cancelFn)
        return nil
    end

    Mod.TrackNameplate(state, unit)

    local now = GetTime()
    local runtime = state._runtimeByUnit[unit]
    if runtime then
        local unitInCombat = UnitAffectingCombat(unit) == true
        local wasInCombat = runtime.targetStateInCombat == true
        runtime.targetStateInCombat = unitInCombat
        if unitInCombat == true and wasInCombat ~= true then
            StartRuntimeTargetStateTracking(runtime, unit, now)
            TargetClearPrint(runtime, string.format(
                "start now=%.3f state=%s",
                tonumber(now) or 0,
                tostring(runtime.targetStateExists)
            ))
        elseif unitInCombat ~= true and wasInCombat == true then
            ResetRuntimeTargetState(runtime)
        end
        if unitInCombat == true then
            runtime.engagedAt = runtime.engagedAt or now
        end
    end

    local firstSeenAt = state._unitFirstSeenAt[unit]
    local cached = state._observedByUnit[unit]
    if not cached then
        if forceSnapshot == true or (firstSeenAt and (now - firstSeenAt) >= SNAPSHOT_DELAY) then
            cached = Mod.CollectObservedUnit(unit)
            state._observedByUnit[unit] = cached
        end
    end

    if not cached then
        return {
            unit = unit,
            pending = true,
            firstSeenAt = firstSeenAt,
            retryAfter = firstSeenAt and math.max(0.02, SNAPSHOT_DELAY - (now - firstSeenAt)) or SNAPSHOT_DELAY,
        }
    end

    cached.unit = unit
    cached.firstSeenAt = firstSeenAt
    cached.inCombat = UnitAffectingCombat(unit) == true
    cached.sawCastStart = runtime and runtime.sawCastStart or false
    cached.sawChannelStart = runtime and runtime.sawChannelStart or false
    cached.sawInterrupted = runtime and runtime.sawInterrupted or false
    cached.firstCastAt = runtime and runtime.firstCastAt or nil
    cached.firstChannelAt = runtime and runtime.firstChannelAt or nil
    return cached
end

function Mod.MarkRuntimeObservation(state, unit, key)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime or type(key) ~= "string" or key == "" then
        return
    end
    runtime[key] = true
    local now = GetTime()
    if key == "sawCastStart" and not runtime.firstCastAt then
        runtime.firstCastAt = now
        runtime.engagedAt = runtime.engagedAt or now
    elseif key == "sawChannelStart" and not runtime.firstChannelAt then
        runtime.firstChannelAt = now
        runtime.engagedAt = runtime.engagedAt or now
    elseif key == "sawInterrupted" and not runtime.firstInterruptedAt then
        runtime.firstInterruptedAt = now
        runtime.engagedAt = runtime.engagedAt or now
    end
end

function Mod.BeginRuntimeCast(state, unit, kind, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    local now = GetTime()
    runtime.engagedAt = runtime.engagedAt or now
    runtime._nameplateUnit = unit
    local nextKind = tostring(kind or "cast")

    local nextCastBarID = NormalizeCastBarID(castBarID)
    local activeCastBarID = NormalizeCastBarID(runtime.activeCastBarID)
    local activeKind = tostring(runtime.activeCastKind or "")
    if runtime.activeCastStartAt
        and activeKind == nextKind
        and ActiveCastMatches(runtime, nextCastBarID) then
        return false
    end

    local interruptibleAt = tonumber(runtime.channelRefreshOnInterruptibleAt)
    local isInterruptibleChannelRefresh = nextKind == "channel"
        and activeKind == "channel"
        and runtime.activeCastStartAt ~= nil
        and runtime.pendingSucceeded ~= true
        and runtime.pendingInterrupted ~= true
        and ActiveSpellAllowsInterruptibleChannelRefresh(runtime)
        and interruptibleAt ~= nil
        and (now - interruptibleAt) <= CHANNEL_REFRESH_INTERRUPTIBLE_WINDOW
        and tonumber(runtime.channelRefreshOnInterruptibleSeq) == tonumber(runtime.activeCastSeq)
        and nextCastBarID ~= nil
        and not ActiveCastMatches(runtime, nextCastBarID)
    if isInterruptibleChannelRefresh then
        runtime.activeCastBarID = nextCastBarID
        runtime.channelRefreshOnInterruptibleAt = nil
        runtime.channelRefreshOnInterruptibleCastBarID = nil
        runtime.channelRefreshOnInterruptibleSeq = nil
        DebugPrint(runtime, string.format(
            "begin-cast refresh unit=%s kind=%s castBarID=%s now=%.3f",
            tostring(unit or "?"),
            tostring(nextKind),
            tostring(nextCastBarID or "nil"),
            tonumber(now) or 0
        ))
        return false
    end

    local isCastIntoChannel = nextKind == "channel"
        and activeCastBarID ~= nil
        and nextCastBarID ~= nil
        and nextCastBarID == (activeCastBarID + 1)
    if not isCastIntoChannel
        and runtime.activeCastStartAt ~= nil
        and (runtime.pendingSucceeded == true or runtime.pendingInterrupted == true) then
        QueuePendingCastSnapshot(runtime, "begin-overwrite")
    end
    local carriedSpellID = isCastIntoChannel and runtime.activeSpellID or nil
    local carriedSpellAmbiguous = isCastIntoChannel and runtime.activeSpellAmbiguous or nil
    local carriedSpellPredictedAt = isCastIntoChannel and runtime.activeSpellPredictedAt or nil
    local carriedSpellAnchorAt = isCastIntoChannel and runtime.activeSpellAnchorAt or nil
    local carriedSpellNextSeqIndex = isCastIntoChannel and runtime.activeSpellNextSeqIndex or nil

    if isCastIntoChannel
        and runtime.activeCastStartAt
        and tostring(runtime.activeCastKind or "") == "cast"
        and not runtime.pendingInterrupted then
        runtime.transitionCastStartAt = tonumber(runtime.activeCastStartAt)
        runtime.transitionCastBarID = activeCastBarID
        runtime.transitionCastKind = "cast"
        runtime.transitionIntoKind = nextKind
        MarkBehavior(runtime, "cast_into_channel", now)
    end

    local bestSpellID = nil
    local bestPredictedAt = nil
    local bestDelta = math.huge
    local bestTieCount = 0
    local nextSpellStartAt = runtime.nextSpellStartAt
    local castStartEligible = type(runtime.spellCastStartVoiceEligible) == "table" and
    runtime.spellCastStartVoiceEligible or nil
    local castStartKindEligible = type(runtime.spellCastStartKindEligible) == "table" and
    runtime.spellCastStartKindEligible or nil
    if type(nextSpellStartAt) == "table" then
        for spellID, predictedAt in pairs(nextSpellStartAt) do
            local sid = tonumber(spellID)
            local pn = tonumber(predictedAt)
            local expectedKind = sid and castStartKindEligible and castStartKindEligible[sid] or nil
            if sid and pn and castStartEligible and castStartEligible[sid] == true and expectedKind == nextKind then
                local delta = math.abs(now - pn)
                if delta < (bestDelta - 0.05) then
                    bestDelta = delta
                    bestSpellID = sid
                    bestPredictedAt = pn
                    bestTieCount = 1
                elseif math.abs(delta - bestDelta) <= 0.05 then
                    bestTieCount = bestTieCount + 1
                end
            end
        end
    end
    if carriedSpellID then
        bestSpellID = carriedSpellID
        bestTieCount = carriedSpellAmbiguous and 2 or 1
        bestPredictedAt = carriedSpellPredictedAt
    end
    runtime.activeCastKind = nextKind
    runtime.activeCastBarID = nextCastBarID
    runtime.activeCastStartAt = now
    runtime.activeObservedSpellID = nil
    runtime.activeCastSeq = (tonumber(runtime.activeCastSeq) or 0) + 1
    local syncTargetAPI = SafeUnitShouldDisplaySpellTargetName(unit)
    local syncTargetExists = SafeUnitTargetTokenExists(unit)
    runtime.activeCastTargetExists = syncTargetExists
    runtime.activeCastTargetCheckedAt = syncTargetExists ~= nil and now or nil
    runtime.activeCastTargetAPIExists = syncTargetAPI
    runtime.activeCastTargetAPICheckedAt = syncTargetAPI ~= nil and now or nil
    runtime.activeCastTargetUnitExists = syncTargetExists
    runtime.activeCastTargetUnitCheckedAt = syncTargetExists ~= nil and now or nil
    runtime.activeCastTargetIsTank = nil
    runtime.activeCastTargetClearResolved = false
    runtime.activeCastTargetClearedOnStart = nil
    runtime.activeCastTargetClearSeen = false
    runtime.activeCastTargetClearCheckedAt = nil
    runtime.activeCastTargetClearEventAt = nil
    runtime.activeCastTargetClearTransitionMatched = false
    runtime.activeCastTargetClearBaselineExists = runtime.targetStateExists
    runtime.activeCastTargetClearLastKnownExists = runtime.targetStateExists
    runtime.activeCastTargetClearTransitionAt = nil
    runtime.activeCastTargetClearTransitionFromExists = nil
    runtime.activeCastTargetClearTransitionToExists = nil
    runtime.activeCastTargetSwitchResolved = false
    runtime.activeCastTargetSwitched = nil
    runtime.activeCastTargetSwitchCheckedAt = nil
    runtime._voicePlayedForSeq = nil
    runtime.activeCastAuraDeltaResolved = false
    runtime.activeCastAuraDeltaMatched = false
    runtime.activeCastAuraDeltaUnit = nil
    runtime.activeCastAuraDeltaAt = nil
    runtime.activeCastSuccessTargetBuffCountBefore = nil
    runtime.activeCastSuccessTargetBuffCountAfter = nil
    runtime.activeCastSuccessTargetBuffCountDelta = nil
    runtime.activeCastSuccessTargetBuffCountResolved = false
    runtime.activeCastSuccessTargetBuffCountCheckedAt = nil
    runtime.activeCastSuccessSelfBuffCountBefore = nil
    runtime.activeCastSuccessSelfBuffCountAfter = nil
    runtime.activeCastSuccessSelfBuffCountDelta = nil
    runtime.activeCastSuccessSelfBuffCountResolved = false
    runtime.activeCastSuccessSelfBuffCountCheckedAt = nil
    runtime.channelRefreshOnInterruptibleAt = nil
    runtime.channelRefreshOnInterruptibleCastBarID = nil
    runtime.channelRefreshOnInterruptibleSeq = nil
    runtime.activeSpellID = bestSpellID
    runtime.activeSpellAmbiguous = bestTieCount > 1
    runtime.activeSpellPredictedAt = bestPredictedAt
    runtime.activeSpellAnchorAt = carriedSpellAnchorAt or
    (bestSpellID and runtime.nextSpellAnchorAt and runtime.nextSpellAnchorAt[bestSpellID] or nil)
    runtime.activeSpellNextSeqIndex = carriedSpellNextSeqIndex or
    (bestSpellID and runtime.nextSpellSeqIndex and runtime.nextSpellSeqIndex[bestSpellID] or nil)
    if not isCastIntoChannel then
        runtime.pendingStartAdvance = true
        runtime.pendingStartAdvanceAt = now
        runtime.pendingStartAdvanceKind = nextKind
    else
        runtime.pendingStartAdvance = false
        runtime.pendingStartAdvanceAt = nil
        runtime.pendingStartAdvanceKind = nil
    end
    runtime.pendingSucceeded = false
    runtime.pendingSucceededAt = nil
    runtime.pendingInterrupted = false
    runtime.pendingInterruptedAt = nil
    runtime.pendingBehavior = nil
    runtime.scheduleDirty = true
    DebugPrint(runtime, string.format(
        "begin-cast unit=%s kind=%s castBarID=%s spell=%s activeStart=%.3f predictedSpell=%s predictedAt=%s tieCount=%s carry=%s",
        tostring(unit or "?"),
        tostring(nextKind),
        tostring(nextCastBarID or "nil"),
        "nil",
        tonumber(runtime.activeCastStartAt) or 0,
        tostring(bestSpellID or "nil"),
        tostring(bestPredictedAt or "nil"),
        tostring(bestTieCount or 0),
        tostring(carriedSpellID or "nil")
    ))
    ScheduleCastTargetSnapshot(runtime, unit, nextKind, nextCastBarID, runtime.activeCastSeq)
    ScheduleCastTargetClearSnapshot(runtime, nextKind, nextCastBarID, runtime.activeCastSeq)
    ScheduleCastTargetSwitchSnapshot(runtime, nextKind, nextCastBarID, runtime.activeCastSeq)
    return true
end

function Mod.MarkRuntimeUnitTarget(state, unit)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if UnitAffectingCombat(unit) ~= true then
        return
    end
    local now = GetTime()
    AppendRuntimeTargetSwitchEvent(runtime, now)
    local previousExists = runtime.targetStateExists
    UpdateRuntimeTargetState(runtime, unit, now)
    if runtime.activeCastStartAt and runtime.activeCastTargetClearResolved ~= true then
        runtime.activeCastTargetClearSeen = true
        runtime.activeCastTargetClearEventAt = now
        local transitionAt = nil
        if previousExists == true and runtime.targetStateExists == false then
            transitionAt = runtime.targetStateLastChangedAt
        end
        TargetClearPrint(runtime, string.format(
            "event castBarID=%s now=%.3f prev=%s current=%s transitionAt=%s",
            tostring(runtime.activeCastBarID or "nil"),
            tonumber(now) or 0,
            tostring(previousExists),
            tostring(runtime.targetStateExists),
            tostring(transitionAt or "nil")
        ))
    end
end

function Mod.MarkRuntimeCastStop(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if tostring(runtime.activeCastKind or "") ~= "cast" then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        runtime.pendingSucceeded = true
        runtime.pendingSucceededAt = GetTime()
        runtime.pendingBehavior = "cast_success"
        runtime.scheduleDirty = true
        EmitTrashCastBarStop(runtime, "cast", castBarID)
        DebugPrint(runtime, string.format(
            "cast-stop unit=%s castBarID=%s startAt=%.3f stopAt=%.3f observed=%.3f spell=%s",
            tostring(unit or "?"),
            tostring(castBarID or "nil"),
            tonumber(runtime.activeCastStartAt) or 0,
            tonumber(runtime.pendingSucceededAt) or 0,
            math.max(0, (tonumber(runtime.pendingSucceededAt) or 0) - (tonumber(runtime.activeCastStartAt) or 0)),
            tostring(runtime.activeSpellID or runtime.activeObservedSpellID or "nil")
        ))
        ScheduleCastSuccessTargetBuffCountSnapshot(runtime, unit, runtime.activeCastKind, castBarID,
            runtime.activeCastSeq)
        ScheduleCastSuccessSelfBuffCountSnapshot(runtime, unit, runtime.activeCastKind, castBarID, runtime.activeCastSeq)
    end
end

function Mod.MarkRuntimeInterrupted(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        local activeKind = tostring(runtime.activeCastKind or "")
        runtime.pendingInterrupted = true
        runtime.pendingInterruptedAt = GetTime()
        runtime.pendingBehavior = ResolveResultKind(activeKind, false)
        if activeKind == "cast" then
            EmitTrashCastBarStop(runtime, activeKind, castBarID)
        end
    else
        MarkBehavior(runtime, "cast_interrupted", GetTime())
    end
    runtime.scheduleDirty = true
end

function Mod.MarkRuntimeInterruptible(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if tostring(runtime.activeCastKind or "") ~= "channel" or not runtime.activeCastStartAt then
        return
    end
    if castBarID ~= nil and not ActiveCastMatches(runtime, castBarID) then
        return
    end
    if not ActiveSpellAllowsInterruptibleChannelRefresh(runtime) then
        return
    end
    runtime.channelRefreshOnInterruptibleAt = GetTime()
    runtime.channelRefreshOnInterruptibleCastBarID = NormalizeCastBarID(runtime.activeCastBarID)
    runtime.channelRefreshOnInterruptibleSeq = runtime.activeCastSeq
end

function Mod.MarkRuntimeChannelStop(state, unit, castBarID, interruptedBy)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        if interruptedBy ~= nil then
            runtime.pendingInterrupted = true
            runtime.pendingInterruptedAt = GetTime()
            runtime.pendingBehavior = ResolveResultKind(runtime.activeCastKind, false)
            runtime.scheduleDirty = true
            return
        end
        runtime.pendingSucceeded = true
        runtime.pendingSucceededAt = GetTime()
        runtime.pendingBehavior = ResolveResultKind(runtime.activeCastKind, true)
        ScheduleCastSuccessTargetBuffCountSnapshot(runtime, unit, runtime.activeCastKind, castBarID,
            runtime.activeCastSeq)
        ScheduleCastSuccessSelfBuffCountSnapshot(runtime, unit, runtime.activeCastKind, castBarID, runtime.activeCastSeq)
    end
    runtime.scheduleDirty = true
end

function Mod.ClearRuntimeActiveCast(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if castBarID ~= nil and not ActiveCastMatches(runtime, castBarID) then
        return
    end
    runtime.activeCastKind = nil
    runtime.activeCastBarID = nil
    runtime.activeCastStartAt = nil
    runtime.activeObservedSpellID = nil
    runtime.activeCastTargetExists = nil
    runtime.activeCastTargetCheckedAt = nil
    runtime.activeCastTargetAPIExists = nil
    runtime.activeCastTargetAPICheckedAt = nil
    runtime.activeCastTargetUnitExists = nil
    runtime.activeCastTargetUnitCheckedAt = nil
    runtime.activeCastTargetIsTank = nil
    runtime.activeCastTargetClearResolved = false
    runtime.activeCastTargetClearedOnStart = nil
    runtime.activeCastTargetClearSeen = false
    runtime.activeCastTargetClearCheckedAt = nil
    runtime.activeCastTargetClearEventAt = nil
    runtime.activeCastTargetClearTransitionMatched = false
    runtime.activeCastTargetClearBaselineExists = nil
    runtime.activeCastTargetClearLastKnownExists = nil
    runtime.activeCastTargetClearTransitionAt = nil
    runtime.activeCastTargetClearTransitionFromExists = nil
    runtime.activeCastTargetClearTransitionToExists = nil
    runtime.activeCastAuraDeltaResolved = false
    runtime.activeCastAuraDeltaMatched = false
    runtime.activeCastAuraDeltaUnit = nil
    runtime.activeCastAuraDeltaAt = nil
    runtime.activeCastSuccessTargetBuffCountBefore = nil
    runtime.activeCastSuccessTargetBuffCountAfter = nil
    runtime.activeCastSuccessTargetBuffCountDelta = nil
    runtime.activeCastSuccessTargetBuffCountResolved = false
    runtime.activeCastSuccessTargetBuffCountCheckedAt = nil
    runtime.activeCastSuccessSelfBuffCountBefore = nil
    runtime.activeCastSuccessSelfBuffCountAfter = nil
    runtime.activeCastSuccessSelfBuffCountDelta = nil
    runtime.activeCastSuccessSelfBuffCountResolved = false
    runtime.activeCastSuccessSelfBuffCountCheckedAt = nil
    runtime.channelRefreshOnInterruptibleAt = nil
    runtime.channelRefreshOnInterruptibleCastBarID = nil
    runtime.channelRefreshOnInterruptibleSeq = nil
    runtime.activeSpellID = nil
    runtime.activeSpellAmbiguous = nil
    runtime.activeSpellPredictedAt = nil
    runtime.activeSpellAnchorAt = nil
    runtime.activeSpellNextSeqIndex = nil
    runtime.transitionCastStartAt = nil
    runtime.transitionCastBarID = nil
    runtime.transitionCastKind = nil
    runtime.transitionIntoKind = nil
    runtime.pendingSucceeded = false
    runtime.pendingSucceededAt = nil
    runtime.pendingInterrupted = false
    runtime.pendingInterruptedAt = nil
    runtime.pendingBehavior = nil
    runtime.pendingStartAdvance = false
    runtime.pendingStartAdvanceAt = nil
    runtime.pendingStartAdvanceKind = nil
    runtime.scheduleDirty = true
end

function Mod.CollectActiveNameplates(state, isHostileFn, cancelFn)
    state = EnsureState(state)
    local out = {}
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if type(isHostileFn) == "function" and isHostileFn(unit) then
            local cached = Mod.CollectTrackedNameplate(state, unit, isHostileFn, cancelFn, false)
            if cached then
                out[#out + 1] = cached
            end
        else
            Mod.UntrackNameplate(state, unit, cancelFn)
        end
    end
    return out
end
