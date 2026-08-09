---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Calibration or {}
ExBoss.TrashCD.Calibration = Mod
ExBoss.Trash.Calibration = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Output = ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
local RuntimeConfig = ExBoss.TrashCD and ExBoss.TrashCD.RuntimeConfig or nil
local TRASH_CASTBAR_STOP_EVENT = "EXBOSS_TRASH_CASTBAR_STOP"

local function IsDebug()
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    return test and type(test.IsDebug) == "function" and test.IsDebug() == true
end

local function DebugPrint(runtime, msg)
    if not IsDebug() then
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashCD|r " .. tostring(msg or ""))
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

local function GetScheduler()
    return ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
end

local SCRIPT_EVENT_HORIZON = 90.0
local SCRIPT_EVENT_MAX_OCCURRENCES = 12
local CAST_TIME_TOLERANCE = 0.20

function Mod.GetCurrentTrashMapID(dungeonKey)
    local state = ExwindTools and ExwindTools.State or nil
    local mapID = tonumber(state and state.MapID) or 0
    local root = Data and Data.GetTrashCDDataRoot and Data.GetTrashCDDataRoot() or {}
    if mapID > 0 and type(root[mapID]) == "table" then
        return mapID
    end
    local byNameKey = Data and Data.GetTrashMapIDByNameKey and Data.GetTrashMapIDByNameKey() or {}
    return tonumber(byNameKey[dungeonKey])
end

function Mod.GetMobCDData(mapID, npcID)
    local root = Data and Data.GetTrashCDDataRoot and Data.GetTrashCDDataRoot() or {}
    local mapData = type(root) == "table" and type(root[mapID]) == "table" and root[mapID] or nil
    local mobs = mapData and type(mapData.mobs) == "table" and mapData.mobs or nil
    return mobs and mobs[tonumber(npcID)] or nil
end

local function SafeNumericValue(value)
    local ok, n = pcall(function() return value + 0 end)
    if ok and type(n) == "number" then
        return n
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
    local normalizedCastBarID = SafeNumericValue(castBarID)
    if not normalizedCastBarID then
        return
    end
    ExwindTools:SendEvent(TRASH_CASTBAR_STOP_EVENT, {
        runtime = runtime,
        castKind = kind,
        castBarID = normalizedCastBarID,
    })
end

local function FindSpellDataByID(mobData, spellID)
    local sid = SafeNumericValue(spellID)
    if not sid or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil
    end
    local ok, direct = pcall(function()
        return mobData.spells[sid]
    end)
    if not ok then
        return nil
    end
    if type(direct) == "table" then
        return direct
    end
    for _, row in pairs(mobData.spells) do
        local matched = false
        ok, matched = pcall(function()
            return type(row) == "table" and SafeNumericValue(row.spellID) == sid
        end)
        if ok and matched then
            return row
        end
    end
    return nil
end

local function HasPositiveDurationValue(value)
    if type(value) == "table" then
        for _, item in pairs(value) do
            if (tonumber(item) or 0) > 0 then
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
    return (tonumber(value) or 0) > 0
end

local function AppendDurationValues(out, value)
    if type(out) ~= "table" then
        return
    end
    if type(value) == "table" then
        for _, item in pairs(value) do
            AppendDurationValues(out, item)
        end
        return
    end
    if type(value) == "string" then
        for item in string.gmatch(value, "[^,;/|%s]+") do
            AppendDurationValues(out, item)
        end
        return
    end
    local n = tonumber(value)
    if n and n > 0 then
        for i = 1, #out do
            if math.abs(out[i] - n) <= 0.001 then
                return
            end
        end
        out[#out + 1] = n
    end
end

local function GetCastTimeCandidates(spellData)
    local out = {}
    if type(spellData) ~= "table" then
        return out
    end
    AppendDurationValues(out, spellData.castTime)
    AppendDurationValues(out, spellData.castTimeExtra)
    return out
end

local function GetChannelTimeCandidates(spellData)
    local out = {}
    if type(spellData) ~= "table" then
        return out
    end
    AppendDurationValues(out, spellData.channelTime)
    AppendDurationValues(out, spellData.channelDuration)
    AppendDurationValues(out, spellData.channelTimeSet)
    return out
end

local function GetBestCastTimeDelta(spellData, observedDuration, compositeDuration)
    local bestCastTime = nil
    local bestDelta = math.huge
    local candidates = GetCastTimeCandidates(spellData)
    for i = 1, #candidates do
        local castTime = candidates[i]
        local delta = math.abs(observedDuration - castTime)
        if compositeDuration then
            delta = math.min(delta, math.abs(compositeDuration - castTime))
        end
        if delta < bestDelta then
            bestDelta = delta
            bestCastTime = castTime
        end
    end
    return bestDelta, bestCastTime
end

function Mod.IsSpellCastStartVoiceEligible(spellData)
    if type(spellData) ~= "table" then
        return false
    end
    return HasPositiveDurationValue(spellData.castTime)
        or HasPositiveDurationValue(spellData.castTimeExtra)
        or HasPositiveDurationValue(spellData.castTimeSet)
        or HasPositiveDurationValue(spellData.channelTime)
        or HasPositiveDurationValue(spellData.channelDuration)
        or HasPositiveDurationValue(spellData.channelTimeSet)
end

function Mod.GetSpellCastStartVoiceKind(spellData)
    if type(spellData) ~= "table" then
        return nil
    end
    local hasCast = HasPositiveDurationValue(spellData.castTime)
        or HasPositiveDurationValue(spellData.castTimeExtra)
        or HasPositiveDurationValue(spellData.castTimeSet)
    local hasChannel = HasPositiveDurationValue(spellData.channelTime)
        or HasPositiveDurationValue(spellData.channelDuration)
        or HasPositiveDurationValue(spellData.channelTimeSet)
    if hasCast then
        return "cast"
    end
    if hasChannel then
        return "channel"
    end
    return nil
end

function Mod.IsChannelRefreshOnInterruptible(spellData)
    return type(spellData) == "table" and spellData.channelRefreshOnInterruptible == true
end

local function SpellHasChannel(spellData)
    if type(spellData) ~= "table" then
        return false
    end
    return HasPositiveDurationValue(spellData.channelTime)
        or HasPositiveDurationValue(spellData.channelDuration)
        or HasPositiveDurationValue(spellData.channelTimeSet)
end

local function SpellDebugName(spellData)
    if type(spellData) ~= "table" then
        return "?"
    end
    return tostring(spellData.name or spellData.nameEN or spellData.spellID or "?")
end

local function HasTargetFingerprint(spellData)
    return type(spellData) == "table" and type(spellData.targetExists) == "boolean"
end

local function HasTargetAPIFingerprint(spellData)
    return type(spellData) == "table" and type(spellData.targetAPIExists) == "boolean"
end

local function HasTargetUnitExistsFingerprint(spellData)
    return type(spellData) == "table" and type(spellData.castStartTargetUnitExists) == "boolean"
end

local function HasAuraDeltaFingerprint(spellData)
    return type(spellData) == "table" and spellData.castStartAuraDelta == true
end

local function HasTargetClearFingerprint(spellData)
    return type(spellData) == "table" and type(spellData.targetClearOnCastStart) == "boolean"
end

local function HasSuccessTargetBuffCountDeltaFingerprint(spellData)
    return type(spellData) == "table" and tonumber(spellData.targetBuffCountDeltaOnSuccess) ~= nil
end

local function HasSuccessSelfBuffCountDeltaFingerprint(spellData)
    return type(spellData) == "table" and tonumber(spellData.selfBuffCountDeltaOnSuccess) ~= nil
end

local function SpellFingerprintsMatchRuntime(spellData, runtime)
    if not HasTargetFingerprint(spellData) then
        -- keep checking aura-delta below
    elseif type(runtime) == "table" and type(runtime.activeCastTargetExists) == "boolean" then
        if spellData.targetExists ~= runtime.activeCastTargetExists then
            return false
        end
    end

    if HasTargetAPIFingerprint(spellData)
        and type(runtime) == "table"
        and type(runtime.activeCastTargetAPIExists) == "boolean"
        and spellData.targetAPIExists ~= runtime.activeCastTargetAPIExists then
        return false
    end

    if HasTargetUnitExistsFingerprint(spellData)
        and type(runtime) == "table"
        and type(runtime.activeCastTargetUnitExists) == "boolean"
        and spellData.castStartTargetUnitExists ~= runtime.activeCastTargetUnitExists then
        return false
    end

    if type(runtime) == "table" and runtime.activeCastAuraDeltaResolved == true then
        local wantsAuraDelta = HasAuraDeltaFingerprint(spellData)
        if runtime.activeCastAuraDeltaMatched == true then
            return wantsAuraDelta == true
        end
        if wantsAuraDelta then
            return false
        end
    end

    if HasTargetClearFingerprint(spellData)
        and type(runtime) == "table"
        and runtime.activeCastTargetClearResolved == true
        and spellData.targetClearOnCastStart ~= (runtime.activeCastTargetClearedOnStart == true) then
        TargetClearPrint(runtime, string.format(
            "mismatch spell=%s expected=%s observed=%s activeSpell=%s observedSpell=%s baseline=%s current=%s eventAt=%s transition=%s transitionAt=%s",
            tostring(spellData.spellID or "?"),
            tostring(spellData.targetClearOnCastStart == true),
            tostring(runtime.activeCastTargetClearedOnStart == true),
            tostring(runtime.activeSpellID or "nil"),
            tostring(runtime.activeObservedSpellID or "nil"),
            tostring(runtime.activeCastTargetClearBaselineExists),
            tostring(runtime.activeCastTargetClearLastKnownExists),
            tostring(runtime.activeCastTargetClearEventAt or "nil"),
            tostring(runtime.activeCastTargetClearTransitionMatched == true),
            tostring(runtime.activeCastTargetClearTransitionAt or "nil")
        ))
        return false
    end

    if type(spellData) == "table"
        and type(spellData.castStartChangeTarget) == "boolean"
        and type(runtime) == "table"
        and runtime.activeCastTargetSwitchResolved == true
        and spellData.castStartChangeTarget ~= (runtime.activeCastTargetSwitched == true) then
        return false
    end

    return true
end

local function SpellSuccessFingerprintsMatchRuntime(spellData, runtime)
    if not SpellFingerprintsMatchRuntime(spellData, runtime) then
        return false
    end
    local expectedDelta = tonumber(type(spellData) == "table" and spellData.targetBuffCountDeltaOnSuccess or nil)
    if expectedDelta == nil then
        return true
    end
    if type(runtime) ~= "table" or runtime.activeCastSuccessTargetBuffCountResolved ~= true then
        return false
    end
    return tonumber(runtime.activeCastSuccessTargetBuffCountDelta) == expectedDelta
end

local function SpellSucceededFingerprintsMatchRuntime(spellData, runtime)
    if not SpellSuccessFingerprintsMatchRuntime(spellData, runtime) then
        return false
    end
    local expectedDelta = tonumber(type(spellData) == "table" and spellData.selfBuffCountDeltaOnSuccess or nil)
    if expectedDelta == nil then
        return true
    end
    if type(runtime) ~= "table" or runtime.activeCastSuccessSelfBuffCountResolved ~= true then
        return false
    end
    return tonumber(runtime.activeCastSuccessSelfBuffCountDelta) == expectedDelta
end

local function DescribeFingerprintMismatch(spellData, runtime)
    if type(spellData) ~= "table" or type(runtime) ~= "table" then
        return nil
    end
    if HasTargetFingerprint(spellData)
        and type(runtime.activeCastTargetExists) == "boolean"
        and spellData.targetExists ~= runtime.activeCastTargetExists then
        return string.format(
            "targetExists expected=%s observed=%s",
            tostring(spellData.targetExists),
            tostring(runtime.activeCastTargetExists)
        )
    end

    if HasTargetAPIFingerprint(spellData)
        and type(runtime.activeCastTargetAPIExists) == "boolean"
        and spellData.targetAPIExists ~= runtime.activeCastTargetAPIExists then
        return string.format(
            "targetAPIExists expected=%s observed=%s",
            tostring(spellData.targetAPIExists),
            tostring(runtime.activeCastTargetAPIExists)
        )
    end

    if HasTargetUnitExistsFingerprint(spellData)
        and type(runtime.activeCastTargetUnitExists) == "boolean"
        and spellData.castStartTargetUnitExists ~= runtime.activeCastTargetUnitExists then
        return string.format(
            "targetUnitExists expected=%s observed=%s",
            tostring(spellData.castStartTargetUnitExists),
            tostring(runtime.activeCastTargetUnitExists)
        )
    end

    if runtime.activeCastAuraDeltaResolved == true then
        local wantsAuraDelta = HasAuraDeltaFingerprint(spellData)
        if runtime.activeCastAuraDeltaMatched == true and wantsAuraDelta ~= true then
            return string.format(
                "auraDelta expected=true observedMatch=%s",
                tostring(runtime.activeCastAuraDeltaMatched)
            )
        end
        if runtime.activeCastAuraDeltaMatched ~= true and wantsAuraDelta == true then
            return string.format(
                "auraDelta expected=true observedMatch=%s",
                tostring(runtime.activeCastAuraDeltaMatched)
            )
        end
    end

    if HasTargetClearFingerprint(spellData)
        and runtime.activeCastTargetClearResolved == true
        and spellData.targetClearOnCastStart ~= (runtime.activeCastTargetClearedOnStart == true) then
        TargetClearPrint(runtime, string.format(
            "detail spell=%s expected=%s observed=%s activeSpell=%s observedSpell=%s baseline=%s current=%s eventAt=%s transition=%s transitionAt=%s",
            tostring(spellData.spellID or "?"),
            tostring(spellData.targetClearOnCastStart == true),
            tostring(runtime.activeCastTargetClearedOnStart == true),
            tostring(runtime.activeSpellID or "nil"),
            tostring(runtime.activeObservedSpellID or "nil"),
            tostring(runtime.activeCastTargetClearBaselineExists),
            tostring(runtime.activeCastTargetClearLastKnownExists),
            tostring(runtime.activeCastTargetClearEventAt or "nil"),
            tostring(runtime.activeCastTargetClearTransitionMatched == true),
            tostring(runtime.activeCastTargetClearTransitionAt or "nil")
        ))
        return string.format(
            "targetClear expected=%s observed=%s",
            tostring(spellData.targetClearOnCastStart == true),
            tostring(runtime.activeCastTargetClearedOnStart == true)
        )
    end

    if type(spellData.castStartChangeTarget) == "boolean"
        and runtime.activeCastTargetSwitchResolved == true
        and spellData.castStartChangeTarget ~= (runtime.activeCastTargetSwitched == true) then
        return string.format(
            "targetSwitch expected=%s observed=%s",
            tostring(spellData.castStartChangeTarget),
            tostring(runtime.activeCastTargetSwitched == true)
        )
    end

    local expectedTargetBuff = tonumber(spellData.targetBuffCountDeltaOnSuccess)
    if expectedTargetBuff ~= nil then
        if runtime.activeCastSuccessTargetBuffCountResolved ~= true then
            return "targetBuffDelta unresolved"
        end
        if tonumber(runtime.activeCastSuccessTargetBuffCountDelta) ~= expectedTargetBuff then
            return string.format(
                "targetBuffDelta expected=%s observed=%s",
                tostring(expectedTargetBuff),
                tostring(runtime.activeCastSuccessTargetBuffCountDelta)
            )
        end
    end

    local expectedSelfBuff = tonumber(spellData.selfBuffCountDeltaOnSuccess)
    if expectedSelfBuff ~= nil then
        if runtime.activeCastSuccessSelfBuffCountResolved ~= true then
            return "selfBuffDelta unresolved"
        end
        if tonumber(runtime.activeCastSuccessSelfBuffCountDelta) ~= expectedSelfBuff then
            return string.format(
                "selfBuffDelta expected=%s observed=%s",
                tostring(expectedSelfBuff),
                tostring(runtime.activeCastSuccessSelfBuffCountDelta)
            )
        end
    end

    return nil
end

local function IsCastStartCDMode(spellData)
    return type(spellData) == "table" and tostring(spellData.cdMode or "") == "CAST_START"
end

local SpellStartKindMatches

local function GetObservedCastStartSpell(runtime, mobData, kind)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil
    end
    local spellData = FindSpellDataByID(mobData, SafeNumericValue(runtime.activeObservedSpellID))
    if type(spellData) == "table"
        and IsCastStartCDMode(spellData)
        and SpellStartKindMatches(spellData, kind) then
        return spellData
    end
    return nil
end

local function StartsCDOnInterruptedChannel(spellData)
    return type(spellData) == "table"
        and (spellData.cdOnChannelInterrupt == true
            or spellData.cdOnInterruptedChannel == true
            or spellData.startCdOnInterruptedChannel == true)
end

local function GetPendingStartFingerprintNeeds(runtime, mobData, kind)
    local needsTarget = false
    local needsTargetAPI = false
    local needsTargetUnitExists = false
    local needsAuraDelta = false
    local needsTargetClear = false
    local needsTargetSwitch = false
    local needsTargetIsTank = false
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return needsTarget, needsTargetAPI, needsTargetUnitExists, needsAuraDelta, needsTargetClear, needsTargetSwitch, needsTargetIsTank
    end
    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table"
            and IsCastStartCDMode(spellData)
            and SpellStartKindMatches(spellData, kind) then
            if type(spellData.targetExists) == "boolean" then
                needsTarget = true
            end
            if type(spellData.targetAPIExists) == "boolean" then
                needsTargetAPI = true
            end
            if type(spellData.castStartTargetUnitExists) == "boolean" then
                needsTargetUnitExists = true
            end
            if spellData.castStartAuraDelta == true then
                needsAuraDelta = true
            end
            if type(spellData.targetClearOnCastStart) == "boolean" then
                needsTargetClear = true
            end
            if type(spellData.castStartChangeTarget) == "boolean" then
                needsTargetSwitch = true
            end
            if type(spellData.targetIsTank) == "boolean" then
                needsTargetIsTank = true
            end
        end
    end
    return needsTarget, needsTargetAPI, needsTargetUnitExists, needsAuraDelta, needsTargetClear, needsTargetSwitch, needsTargetIsTank
end

local function SpellFinishKindMatches(spellData, kind)
    if type(spellData) ~= "table" then
        return false
    end
    kind = tostring(kind or "")
    if kind == "cast" then
        return HasPositiveDurationValue(spellData.castTime)
            or HasPositiveDurationValue(spellData.castTimeExtra)
            or HasPositiveDurationValue(spellData.castTimeSet)
    end
    if kind == "channel" then
        return SpellHasChannel(spellData)
    end
    return false
end

local function GetPendingFinishFingerprintNeeds(runtime, mobData, kind)
    local needsTargetBuffCountDelta = false
    local needsSelfBuffCountDelta = false
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return needsTargetBuffCountDelta, needsSelfBuffCountDelta
    end
    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table" and SpellFinishKindMatches(spellData, kind) then
            if HasSuccessTargetBuffCountDeltaFingerprint(spellData) then
                needsTargetBuffCountDelta = true
            end
            if HasSuccessSelfBuffCountDeltaFingerprint(spellData) then
                needsSelfBuffCountDelta = true
            end
            if needsTargetBuffCountDelta and needsSelfBuffCountDelta then
                break
            end
        end
    end
    return needsTargetBuffCountDelta, needsSelfBuffCountDelta
end

local function ArePendingFinishFingerprintsResolved(runtime, mobData, kind)
    local needsTargetBuffCountDelta, needsSelfBuffCountDelta = GetPendingFinishFingerprintNeeds(runtime, mobData, kind)
    if needsTargetBuffCountDelta and runtime.activeCastSuccessTargetBuffCountResolved ~= true then
        return false, "target-buffcount-delta"
    end
    if needsSelfBuffCountDelta and runtime.activeCastSuccessSelfBuffCountResolved ~= true then
        return false, "self-buffcount-delta"
    end
    return true, nil
end

local function ArePendingStartFingerprintsResolved(runtime, mobData, kind)
    local needsTarget, needsTargetAPI, needsTargetUnitExists, needsAuraDelta, needsTargetClear, needsTargetSwitch, needsTargetIsTank = GetPendingStartFingerprintNeeds(runtime, mobData, kind)
    if needsTarget and type(runtime.activeCastTargetExists) ~= "boolean" then
        return false, "target"
    end
    if needsTargetAPI and type(runtime.activeCastTargetAPIExists) ~= "boolean" then
        return false, "target-api"
    end
    if needsTargetUnitExists and type(runtime.activeCastTargetUnitExists) ~= "boolean" then
        return false, "target-unit"
    end
    if needsAuraDelta and runtime.activeCastAuraDeltaResolved ~= true then
        return false, "aura-delta"
    end
    if needsTargetClear and runtime.activeCastTargetClearResolved ~= true then
        return false, "target-clear"
    end
    if needsTargetSwitch and runtime.activeCastTargetSwitchResolved ~= true then
        return false, "target-switch"
    end
    if needsTargetIsTank and type(runtime.activeCastTargetIsTank) ~= "boolean" then
        return false, "target-is-tank"
    end
    return true, nil
end

SpellStartKindMatches = function(spellData, kind)
    if type(spellData) ~= "table" then
        return false
    end
    kind = tostring(kind or "")
    local hasCast = HasPositiveDurationValue(spellData.castTime)
        or HasPositiveDurationValue(spellData.castTimeExtra)
        or HasPositiveDurationValue(spellData.castTimeSet)
    local hasChannel = SpellHasChannel(spellData)
    if kind == "cast" then
        return hasCast == true
    end
    if kind == "channel" then
        return hasChannel == true and hasCast ~= true
    end
    return false
end

function Mod.IsFixedCombatTimelineSpell(spellData)
    return type(spellData) == "table" and spellData.fixedCombatTimeline == true
end

local function FindNearestScheduledSpell(runtime, mobData, referenceAt)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil, nil
    end
    referenceAt = tonumber(referenceAt) or GetTime()
    local bestSpell = nil
    local bestDelta = math.huge
    local bestReason = nil

    if type(runtime.nextSpellStartAt) == "table" then
        for spellID, predictedAt in pairs(runtime.nextSpellStartAt) do
            local pn = tonumber(predictedAt)
            local spellData = FindSpellDataByID(mobData, spellID)
            if pn and type(spellData) == "table" then
                local delta = math.abs(referenceAt - pn)
                if delta < bestDelta then
                    bestDelta = delta
                    bestSpell = spellData
                    bestReason = string.format("nextSpellStartAt delta=%.2f", delta)
                end
            end
        end
    end

    local scheduler = GetScheduler()
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    if scheduler and type(scheduler._active) == "table" and type(bySpell) == "table" then
        for spellID, timerID in pairs(bySpell) do
            local timer = scheduler._active[tonumber(timerID)]
            local spellData = FindSpellDataByID(mobData, spellID)
            local castTime = type(timer) == "table" and tonumber(timer.castTime) or nil
            if castTime and type(spellData) == "table" then
                local delta = math.abs(referenceAt - castTime)
                if delta < bestDelta then
                    bestDelta = delta
                    bestSpell = spellData
                    bestReason = string.format("localTimer delta=%.2f", delta)
                end
            end
        end
    end

    return bestSpell, bestReason
end

function Mod.BuildSpellOccurrences(spellData, anchorAt, now, startSeqIndex)
    local out = {}
    if type(spellData) ~= "table" then
        return out
    end
    local first = tonumber(spellData.first)
    if not first then
        return out
    end
    local occurrenceAt = anchorAt + first
    local horizonAt = now + SCRIPT_EVENT_HORIZON
    local occurrences = 0
    local seq = type(spellData.cd) == "table" and spellData.cd or nil
    local seqIndex = 1
    if type(seq) == "table" and #seq > 0 then
        seqIndex = tonumber(startSeqIndex) or 1
        if seqIndex < 1 or seqIndex > #seq then
            seqIndex = 1
        end
    end

    while occurrenceAt <= horizonAt and occurrences < SCRIPT_EVENT_MAX_OCCURRENCES do
        if occurrenceAt > now + 0.20 then
            out[#out + 1] = {
                at = occurrenceAt,
                nextSeqIndex = (type(seq) == "table" and #seq > 0) and seqIndex or nil,
            }
            occurrences = occurrences + 1
        end
        if type(seq) ~= "table" or #seq == 0 then
            break
        end
        local step = tonumber(seq[seqIndex])
        if not step or step <= 0 then
            break
        end
        occurrenceAt = occurrenceAt + step
        seqIndex = seqIndex + 1
        if seqIndex > #seq then
            seqIndex = 1
        end
    end
    return out
end

function Mod.GetSpellAnchor(runtime, spellData, defaultAnchorAt)
    local spellID = tonumber(spellData and spellData.spellID)
    local spellAnchors = runtime and runtime.spellAnchors
    local spellAnchor = spellID and type(spellAnchors) == "table" and spellAnchors[spellID] or nil
    if type(spellAnchor) == "table" and tonumber(spellAnchor.anchorAt) then
        return tonumber(spellAnchor.anchorAt), tostring(spellAnchor.mode or "success"), tonumber(spellAnchor.nextSeqIndex) or 1
    end
    return tonumber(defaultAnchorAt) or GetTime(), "enter", 1
end

function Mod.BuildRuntimeScheduleSignature(runtime, candidateNPCID, defaultAnchorAt)
    local parts = {
        tostring(tonumber(candidateNPCID) or 0),
        string.format("base=%.1f", tonumber(defaultAnchorAt) or 0),
        runtime and runtime.activeCastStartAt and string.format("active=%s@%.1f", tostring(runtime.activeCastKind or "?"), tonumber(runtime.activeCastStartAt) or 0) or "active=0",
        string.format("cfg=%d", RuntimeConfig and type(RuntimeConfig.GetConfigRevision) == "function" and tonumber(RuntimeConfig.GetConfigRevision()) or 0),
    }
    local spellParts = {}
    local spellAnchors = runtime and runtime.spellAnchors
    if type(spellAnchors) == "table" then
        for spellID, row in pairs(spellAnchors) do
            if type(row) == "table" and tonumber(row.anchorAt) then
                spellParts[#spellParts + 1] = string.format("%d:%s:%.1f:%d",
                    tonumber(spellID) or 0,
                    tostring(row.mode or "?"),
                    tonumber(row.anchorAt) or 0,
                    tonumber(row.nextSeqIndex) or 1)
            end
        end
    end
    table.sort(spellParts)
    for i = 1, #spellParts do
        parts[#parts + 1] = spellParts[i]
    end
    return table.concat(parts, "|")
end

function Mod.InferSucceededSpell(runtime, mobData, defaultAnchorAt, successAtOverride)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil
    end
    local startAt = tonumber(runtime.activeCastStartAt)
    local successAt = tonumber(successAtOverride) or tonumber(runtime.pendingSucceededAt)
    if not startAt or not successAt or successAt < startAt then
        return nil
    end
    local activeKind = tostring(runtime.activeCastKind or "cast")
    local observedDuration = successAt - startAt
    local transitionStartAt = tonumber(runtime.transitionCastStartAt)
    local compositeDuration = nil
    if transitionStartAt and transitionStartAt <= startAt and successAt >= transitionStartAt then
        compositeDuration = successAt - transitionStartAt
    end
    local predictedSpellID = tonumber(runtime.activeSpellID)
    local predictedSpell = FindSpellDataByID(mobData, predictedSpellID)
    if activeKind == "cast" and SpellHasChannel(predictedSpell) then
        DebugPrint(runtime, string.format("infer ignore-predicted-channel activeSpell=%s name=%s observed=%.2f",
            tostring(predictedSpellID or "nil"),
            SpellDebugName(predictedSpell),
            tonumber(observedDuration) or 0))
    end
    if activeKind == "channel" then
        if type(predictedSpell) == "table" and SpellHasChannel(predictedSpell) then
            return predictedSpell
        end
        local nearestSpell, nearestReason = FindNearestScheduledSpell(runtime, mobData, startAt)
        if type(nearestSpell) == "table" and SpellHasChannel(nearestSpell) then
            return nearestSpell
        end
        return nil
    end
    local bestSpell = nil
    local bestScore = math.huge
    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table" then
            local spellID = tonumber(spellData.spellID)
            local first = tonumber(spellData.first)
            local durationDelta, castTime = GetBestCastTimeDelta(spellData, observedDuration, compositeDuration)
            if spellID and castTime and castTime > 0 and first ~= nil and not (activeKind == "cast" and SpellHasChannel(spellData)) then
                local fingerprintMismatch = DescribeFingerprintMismatch(spellData, runtime)
                if fingerprintMismatch then
                    DebugPrint(runtime, string.format(
                        "infer skip spell=%s name=%s reason=fingerprint-mismatch detail=%s observed=%.2f cast=%s activeStart=%.3f successAt=%.3f",
                        tostring(spellID),
                        SpellDebugName(spellData),
                        tostring(fingerprintMismatch),
                        tonumber(observedDuration) or 0,
                        tostring(castTime or "nil"),
                        tonumber(startAt) or 0,
                        tonumber(successAt) or 0
                    ))
                elseif SpellSucceededFingerprintsMatchRuntime(spellData, runtime) then
                    if durationDelta > CAST_TIME_TOLERANCE then
                        DebugPrint(runtime, string.format(
                            "infer skip spell=%s name=%s reason=duration-mismatch observed=%.2f cast=%.2f delta=%.2f tolerance=%.2f",
                            tostring(spellID),
                            SpellDebugName(spellData),
                            tonumber(observedDuration) or 0,
                            tonumber(castTime) or 0,
                            tonumber(durationDelta) or 0,
                            CAST_TIME_TOLERANCE
                        ))
                    else
                        local expectedStartAt = runtime.nextSpellStartAt and runtime.nextSpellStartAt[spellID] or nil
                        if not expectedStartAt then
                            local anchorAt = Mod.GetSpellAnchor(runtime, spellData, defaultAnchorAt)
                            expectedStartAt = tonumber(anchorAt) and (tonumber(anchorAt) + first) or nil
                        end
                        local expectedDelta = expectedStartAt and math.abs(startAt - expectedStartAt) or 9999
                        local score = durationDelta * 100 + expectedDelta
                        DebugPrint(runtime, string.format(
                            "infer candidate spell=%s name=%s kind=%s observed=%.2f cast=%.2f channel=%s durDelta=%.2f expectedDelta=%.2f score=%.2f",
                            tostring(spellID),
                            SpellDebugName(spellData),
                            tostring(activeKind),
                            tonumber(observedDuration) or 0,
                            tonumber(castTime) or 0,
                            tostring(spellData.channelTime or spellData.channelDuration or spellData.channelTimeSet or "nil"),
                            tonumber(durationDelta) or 0,
                            tonumber(expectedDelta) or 0,
                            tonumber(score) or 0
                        ))
                        if score < bestScore then
                            bestScore = score
                            bestSpell = spellData
                        end
                    end
                end
            end
        end
    end
    DebugPrint(runtime, string.format("infer result spell=%s name=%s score=%.2f",
        tostring(bestSpell and bestSpell.spellID or "nil"),
        SpellDebugName(bestSpell),
        tonumber(bestScore) or 0))
    return bestSpell
end

local function InterruptedChannelTimingMatches(spellData, runtime, interruptedAt)
    if not StartsCDOnInterruptedChannel(spellData) then
        return false
    end
    if tostring(runtime and runtime.activeCastKind or "") ~= "channel" then
        return false
    end
    if tostring(runtime and runtime.transitionCastKind or "") ~= "cast" then
        return false
    end
    local castStartAt = tonumber(runtime.transitionCastStartAt)
    local channelStartAt = tonumber(runtime.activeCastStartAt)
    interruptedAt = tonumber(interruptedAt)
    if not castStartAt or not channelStartAt or not interruptedAt or interruptedAt < channelStartAt then
        return false
    end
    local castTime = tonumber(spellData.castTime)
    if not castTime or castTime <= 0 then
        return false
    end
    local channelElapsed = interruptedAt - channelStartAt
    local compositeElapsed = interruptedAt - castStartAt
    local channelTimes = GetChannelTimeCandidates(spellData)
    if #channelTimes == 0 then
        return false
    end
    for i = 1, #channelTimes do
        local channelTime = channelTimes[i]
        -- 被打断时只要求已经进入该引导，不能要求完整引导时间结束。
        if channelElapsed >= -CAST_TIME_TOLERANCE
            and channelElapsed <= (channelTime + CAST_TIME_TOLERANCE)
            and math.abs((castTime + channelElapsed) - compositeElapsed) <= CAST_TIME_TOLERANCE then
            return true
        end
    end
    return false
end

local function InferInterruptedChannelSpell(runtime, mobData, interruptedAt)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil
    end
    local activeSpell = FindSpellDataByID(mobData, tonumber(runtime.activeSpellID))
    if type(activeSpell) == "table" and InterruptedChannelTimingMatches(activeSpell, runtime, interruptedAt) then
        return activeSpell
    end
    local bestSpell = nil
    local bestScore = math.huge
    local channelStartAt = tonumber(runtime.activeCastStartAt)
    interruptedAt = tonumber(interruptedAt)
    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table" and InterruptedChannelTimingMatches(spellData, runtime, interruptedAt) then
            local spellID = tonumber(spellData.spellID)
            local expectedAt = spellID and runtime.nextSpellStartAt and tonumber(runtime.nextSpellStartAt[spellID]) or nil
            local score = expectedAt and channelStartAt and math.abs(channelStartAt - expectedAt) or 9999
            if score < bestScore then
                bestScore = score
                bestSpell = spellData
            end
        end
    end
    return bestSpell
end

local function NormalizeSequenceIndex(seq, seqIndex)
    if type(seq) ~= "table" or #seq == 0 then
        return 1
    end
    local index = tonumber(seqIndex) or 1
    if index < 1 or index > #seq then
        return 1
    end
    return index
end

local function GetFollowingSequenceIndex(seq, seqIndex)
    if type(seq) ~= "table" or #seq == 0 then
        return 1
    end
    local index = NormalizeSequenceIndex(seq, seqIndex) + 1
    if index > #seq then
        index = 1
    end
    return index
end

function Mod.ApplyObservedCastAdvance(runtime, mobData, defaultAnchorAt, mode, successAtOverride)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return false
    end
    if mode == "success" then
        local succeededSpell = Mod.InferSucceededSpell(runtime, mobData, defaultAnchorAt, successAtOverride)
        if succeededSpell and tonumber(succeededSpell.spellID) and tonumber(succeededSpell.first) then
            if IsCastStartCDMode(succeededSpell) then
                return nil
            end
            local successAt = tonumber(successAtOverride) or tonumber(runtime.pendingSucceededAt) or GetTime()
            local observedStartAt = tonumber(runtime.transitionCastStartAt) or tonumber(runtime.activeCastStartAt)
            runtime.spellAnchors = runtime.spellAnchors or {}
            runtime.spellLastSucceededAt = runtime.spellLastSucceededAt or {}
            local seq = type(succeededSpell.cd) == "table" and succeededSpell.cd or nil
            runtime.spellAnchors[tonumber(succeededSpell.spellID)] = {
                mode = "success",
                anchorAt = observedStartAt - tonumber(succeededSpell.first),
                nextSeqIndex = NormalizeSequenceIndex(seq, runtime.activeSpellNextSeqIndex),
            }
            runtime.spellLastSucceededAt[tonumber(succeededSpell.spellID)] = successAt
            runtime.lastSucceededSpellID = tonumber(succeededSpell.spellID)
            runtime.lastSucceededSpellName = tostring(succeededSpell.name or "?")
            return tonumber(succeededSpell.spellID)
        end
        return nil
    end
    if mode == "interrupt" then
        local interruptedAt = tonumber(runtime.pendingInterruptedAt) or tonumber(successAtOverride) or GetTime()
        local interruptedSpell = InferInterruptedChannelSpell(runtime, mobData, interruptedAt)
        if interruptedSpell and tonumber(interruptedSpell.spellID) and tonumber(interruptedSpell.first) then
            local observedStartAt = tonumber(runtime.transitionCastStartAt) or tonumber(runtime.activeCastStartAt)
            runtime.spellAnchors = runtime.spellAnchors or {}
            runtime.spellLastSucceededAt = runtime.spellLastSucceededAt or {}
            local seq = type(interruptedSpell.cd) == "table" and interruptedSpell.cd or nil
            runtime.spellAnchors[tonumber(interruptedSpell.spellID)] = {
                mode = "channel_interrupt",
                anchorAt = observedStartAt - tonumber(interruptedSpell.first),
                nextSeqIndex = NormalizeSequenceIndex(seq, runtime.activeSpellNextSeqIndex),
            }
            runtime.spellLastSucceededAt[tonumber(interruptedSpell.spellID)] = interruptedAt
            runtime.lastSucceededSpellID = tonumber(interruptedSpell.spellID)
            runtime.lastSucceededSpellName = tostring(interruptedSpell.name or "?")
            return tonumber(interruptedSpell.spellID)
        end
        return nil
    end
    local spellID = tonumber(runtime.activeSpellID)
    local predictedAt = tonumber(runtime.activeSpellPredictedAt)
    local observedStartAt = tonumber(runtime.activeCastStartAt)
    local baseAnchorAt = tonumber(runtime.activeSpellAnchorAt) or tonumber(defaultAnchorAt)
    if spellID and predictedAt and observedStartAt and baseAnchorAt then
        local spellData = mobData.spells[spellID]
        local seq = type(spellData) == "table" and type(spellData.cd) == "table" and spellData.cd or nil
        runtime.spellAnchors = runtime.spellAnchors or {}
        runtime.spellAnchors[spellID] = {
            mode = tostring(mode or "observed"),
            anchorAt = baseAnchorAt + (observedStartAt - predictedAt),
            nextSeqIndex = NormalizeSequenceIndex(seq, runtime.activeSpellNextSeqIndex),
        }
        runtime.lastSucceededSpellID = spellID
        runtime.lastSucceededSpellName = type(spellData) == "table" and tostring(spellData.name or "?") or tostring(spellID)
        return spellID
    end
    return nil
end

local function BuildQueuedSnapshotRuntime(runtime, snapshot)
    if type(runtime) ~= "table" or type(snapshot) ~= "table" then
        return nil
    end
    local proxy = {}
    for key, value in pairs(snapshot) do
        proxy[key] = value
    end
    proxy._debugUnit = runtime._debugUnit
    proxy._nameplateUnit = runtime._nameplateUnit
    proxy.nextSpellStartAt = runtime.nextSpellStartAt
    proxy.nextSpellAnchorAt = runtime.nextSpellAnchorAt
    proxy.nextSpellSeqIndex = runtime.nextSpellSeqIndex
    proxy.spellAnchors = runtime.spellAnchors or {}
    proxy.spellLastSucceededAt = runtime.spellLastSucceededAt or {}
    return proxy
end

local function ApplySnapshotResultsToRuntime(runtime, snapshotRuntime, successAt, advancedSpellID, advancedSpellIDs)
    if type(runtime) ~= "table" or type(snapshotRuntime) ~= "table" then
        return
    end
    if (snapshotRuntime.pendingSucceeded or snapshotRuntime.pendingInterrupted) and snapshotRuntime.activeCastStartAt then
        EmitTrashCastBarStop(
            runtime,
            snapshotRuntime.activeCastKind,
            snapshotRuntime.activeCastBarID
        )
    end
    runtime.spellAnchors = snapshotRuntime.spellAnchors or runtime.spellAnchors
    runtime.spellLastSucceededAt = snapshotRuntime.spellLastSucceededAt or runtime.spellLastSucceededAt
    if successAt then
        runtime.lastSucceededAt = successAt
    end
    if advancedSpellID or (type(advancedSpellIDs) == "table" and #advancedSpellIDs > 0) then
        runtime.lastSucceededSpellID = snapshotRuntime.lastSucceededSpellID or runtime.lastSucceededSpellID
        runtime.lastSucceededSpellName = snapshotRuntime.lastSucceededSpellName or runtime.lastSucceededSpellName
    end
end

local function AppendAdvancedSpellID(out, spellID)
    local sid = tonumber(spellID)
    if not sid then
        return out
    end
    out = type(out) == "table" and out or {}
    for i = 1, #out do
        if tonumber(out[i]) == sid then
            return out
        end
    end
    out[#out + 1] = sid
    return out
end

local function MergeAdvancedSpellIDs(out, spellIDs)
    if type(spellIDs) ~= "table" then
        return out
    end
    for i = 1, #spellIDs do
        out = AppendAdvancedSpellID(out, spellIDs[i])
    end
    return out
end

local function ProcessQueuedPendingCast(runtime, snapshot, mobData, defaultAnchorAt)
    if type(runtime) ~= "table" or type(snapshot) ~= "table" or type(mobData) ~= "table" then
        return false, "bad-input", nil, nil
    end
    local snapshotRuntime = BuildQueuedSnapshotRuntime(runtime, snapshot)
    if not snapshotRuntime then
        return false, "no-snapshot", nil, nil
    end

    local advancedSpellIDs = nil
    if snapshotRuntime.pendingStartAdvance == true then
        local observedStartSpell = GetObservedCastStartSpell(
            snapshotRuntime,
            mobData,
            snapshotRuntime.pendingStartAdvanceKind or snapshotRuntime.activeCastKind
        )
        local fingerprintsReady, pendingReason = ArePendingStartFingerprintsResolved(
            snapshotRuntime,
            mobData,
            snapshotRuntime.pendingStartAdvanceKind or snapshotRuntime.activeCastKind
        )
        if not fingerprintsReady and not observedStartSpell then
            return false, pendingReason or "pending-start", nil, nil
        end
        advancedSpellIDs = Mod.ApplyObservedStartAdvance(snapshotRuntime, mobData, defaultAnchorAt)
    end

    local advancedSpellID = nil
    local successAt = nil
    if (snapshotRuntime.pendingSucceeded or snapshotRuntime.pendingInterrupted) and snapshotRuntime.activeCastStartAt then
        local resolveMode = snapshotRuntime.pendingInterrupted and "interrupt" or "success"
        successAt = tonumber(snapshotRuntime.pendingSucceededAt) or tonumber(snapshotRuntime.pendingInterruptedAt) or GetTime()
        if resolveMode == "success" then
            local fingerprintsReady, pendingReason = ArePendingFinishFingerprintsResolved(
                snapshotRuntime,
                mobData,
                snapshotRuntime.activeCastKind
            )
            if not fingerprintsReady then
                return false, pendingReason or "pending-finish", nil, nil
            end
        end
        if type(snapshotRuntime.pendingBehavior) == "string" and snapshotRuntime.pendingBehavior ~= "" then
            runtime.lastBehavior = snapshotRuntime.pendingBehavior
            runtime.lastBehaviorAt = successAt
            if snapshotRuntime.pendingBehavior == "cast_success" then
                runtime.sawCastSuccess = true
            elseif snapshotRuntime.pendingBehavior == "cast_interrupted" then
                runtime.sawCastInterrupted = true
            elseif snapshotRuntime.pendingBehavior == "channel_success" then
                runtime.sawChannelSuccess = true
            end
        end
        advancedSpellID = Mod.ApplyObservedCastAdvance(snapshotRuntime, mobData, defaultAnchorAt, resolveMode, successAt)
    end

    ApplySnapshotResultsToRuntime(runtime, snapshotRuntime, successAt, advancedSpellID, advancedSpellIDs)
    return true, nil, advancedSpellID, advancedSpellIDs
end

function Mod.ApplyObservedStartAdvance(runtime, mobData, defaultAnchorAt)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        return nil
    end
    local startAt = tonumber(runtime.pendingStartAdvanceAt) or tonumber(runtime.activeCastStartAt)
    local kind = tostring(runtime.pendingStartAdvanceKind or runtime.activeCastKind or "")
    if not startAt then
        return nil
    end

    local advancedSpellIDs = nil
    runtime.spellAnchors = runtime.spellAnchors or {}
    runtime.spellLastSucceededAt = runtime.spellLastSucceededAt or {}

    local observedSpell = GetObservedCastStartSpell(runtime, mobData, kind)
    if type(observedSpell) == "table" then
        local first = tonumber(observedSpell.first)
        local spellID = tonumber(observedSpell.spellID)
        if first and spellID then
            local seq = type(observedSpell.cd) == "table" and observedSpell.cd or nil
            runtime.spellAnchors[spellID] = {
                mode = "cast_start",
                anchorAt = startAt - first,
                nextSeqIndex = NormalizeSequenceIndex(seq, runtime.activeSpellNextSeqIndex),
            }
            runtime.spellLastSucceededAt[spellID] = startAt
            runtime.lastSucceededAt = startAt
            runtime.lastSucceededSpellID = spellID
            runtime.lastSucceededSpellName = tostring(observedSpell.name or "?")
            return { spellID }
        end
    end

    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table" and IsCastStartCDMode(spellData) and SpellStartKindMatches(spellData, kind) and SpellFingerprintsMatchRuntime(spellData, runtime) then
            local first = tonumber(spellData.first)
            local spellID = tonumber(spellData.spellID)
            if first and spellID then
                local seq = type(spellData.cd) == "table" and spellData.cd or nil
                runtime.spellAnchors[spellID] = {
                    mode = "cast_start",
                    anchorAt = startAt - first,
                    nextSeqIndex = NormalizeSequenceIndex(seq, runtime.activeSpellNextSeqIndex),
                }
                runtime.spellLastSucceededAt[spellID] = startAt
                runtime.lastSucceededAt = startAt
                runtime.lastSucceededSpellID = spellID
                runtime.lastSucceededSpellName = tostring(spellData.name or "?")
                advancedSpellIDs = advancedSpellIDs or {}
                advancedSpellIDs[#advancedSpellIDs + 1] = spellID
            end
        end
    end

    return advancedSpellIDs
end

local function RebuildSpellSchedule(runtime, mobData, spellData, defaultAnchorAt, now)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(spellData) ~= "table" then
        return
    end
    local spellID = tonumber(spellData.spellID)
    if not spellID then
        return
    end

    runtime.spellCastStartVoiceEligible = runtime.spellCastStartVoiceEligible or {}
    runtime.spellCastStartKindEligible = runtime.spellCastStartKindEligible or {}
    runtime.spellChannelRefreshOnInterruptible = runtime.spellChannelRefreshOnInterruptible or {}
    runtime.spellCastStartVoiceEligible[spellID] = Mod.IsSpellCastStartVoiceEligible(spellData)
    runtime.spellCastStartKindEligible[spellID] = Mod.GetSpellCastStartVoiceKind(spellData)
    runtime.spellChannelRefreshOnInterruptible[spellID] = Mod.IsChannelRefreshOnInterruptible(spellData) == true or nil

    if Output and type(Output.CancelRuntimeSpellScriptEvents) == "function" then
        Output.CancelRuntimeSpellScriptEvents(runtime, spellID)
    end

    runtime.nextSpellStartAt = runtime.nextSpellStartAt or {}
    runtime.nextSpellAnchorAt = runtime.nextSpellAnchorAt or {}
    runtime.nextSpellSeqIndex = runtime.nextSpellSeqIndex or {}
    runtime.nextSpellStartAt[spellID] = nil
    runtime.nextSpellAnchorAt[spellID] = nil
    runtime.nextSpellSeqIndex[spellID] = nil

    local fixedCombatTimeline = Mod.IsFixedCombatTimelineSpell(spellData)
    local succeededAt = (not fixedCombatTimeline) and type(runtime.spellLastSucceededAt) == "table" and tonumber(runtime.spellLastSucceededAt[spellID]) or nil
    local seq = type(spellData.cd) == "table" and spellData.cd or nil
    if succeededAt and type(seq) == "table" and #seq > 0 then
        local _, _, nextSeqIndex = Mod.GetSpellAnchor(runtime, spellData, defaultAnchorAt)
        nextSeqIndex = NormalizeSequenceIndex(seq, nextSeqIndex)
        local step = tonumber(seq[nextSeqIndex])
        if step and step > 0 then
            local nextAt = succeededAt + step
            if nextAt > now + 0.20 then
                runtime.nextSpellStartAt[spellID] = nextAt
                runtime.nextSpellAnchorAt[spellID] = succeededAt
                runtime.nextSpellSeqIndex[spellID] = GetFollowingSequenceIndex(seq, nextSeqIndex)
                DebugPrint(runtime, string.format("schedule spell=%s name=%s mode=success nextIn=%.2f step=%.2f seq=%d->%d",
                    tostring(spellID), SpellDebugName(spellData), nextAt - now, step, nextSeqIndex,
                    tonumber(runtime.nextSpellSeqIndex[spellID]) or 1))
                if Output and type(Output.AddRuntimeScriptEvent) == "function" then
                    Output.AddRuntimeScriptEvent(runtime, mobData, spellData, nextAt - now, 136243)
                end
                return "success"
            end
            DebugPrint(runtime, string.format("schedule skip spell=%s name=%s mode=success reason=past nextIn=%.2f step=%.2f seq=%d",
                tostring(spellID), SpellDebugName(spellData), nextAt - now, step, nextSeqIndex))
        end
    end

    local anchorAt, anchorMode, anchorSeqIndex = Mod.GetSpellAnchor(runtime, spellData, defaultAnchorAt)
    local times = Mod.BuildSpellOccurrences(spellData, anchorAt, now, anchorSeqIndex)
    if #times > 0 then
        local first = times[1]
        runtime.nextSpellStartAt[spellID] = tonumber(first and first.at)
        runtime.nextSpellAnchorAt[spellID] = tonumber(anchorAt)
        runtime.nextSpellSeqIndex[spellID] = tonumber(first and first.nextSeqIndex) or nil
        DebugPrint(runtime, string.format("schedule spell=%s name=%s mode=%s firstNextIn=%.2f count=%d anchor=%.3f seq=%s",
            tostring(spellID), SpellDebugName(spellData), tostring(anchorMode or "enter"),
            tonumber(first and first.at) and (tonumber(first.at) - now) or -1, #times, tonumber(anchorAt) or 0,
            tostring(runtime.nextSpellSeqIndex[spellID] or "nil")))
    else
        DebugPrint(runtime, string.format("schedule none spell=%s name=%s mode=%s first=%s cdCount=%s anchor=%.3f now=%.3f",
            tostring(spellID), SpellDebugName(spellData), tostring(anchorMode or "enter"),
            tostring(spellData.first or "nil"),
            tostring(type(spellData.cd) == "table" and #spellData.cd or 0),
            tonumber(anchorAt) or 0,
            tonumber(now) or 0))
    end

    local maxEvents = math.min(#times, 1)
    for i = 1, maxEvents do
        if Output and type(Output.AddRuntimeScriptEvent) == "function" then
            Output.AddRuntimeScriptEvent(runtime, mobData, spellData, tonumber(times[i] and times[i].at) - now, 136243)
        end
    end

    return tostring(anchorMode or "enter")
end

local function RebuildAllSpellSchedules(runtime, mobData, defaultAnchorAt, now)
    if Output and type(Output.CancelRuntimeScriptEvents) == "function" then
        Output.CancelRuntimeScriptEvents(runtime)
    end
    runtime.anchorAt = defaultAnchorAt
    runtime.scriptEventIDs = runtime.scriptEventIDs or {}
    runtime.scriptEventIDsBySpellID = runtime.scriptEventIDsBySpellID or {}
    runtime.nextSpellStartAt = {}
    runtime.nextSpellAnchorAt = {}
    runtime.nextSpellSeqIndex = {}
    runtime.spellCastStartVoiceEligible = {}
    runtime.spellCastStartKindEligible = {}
    runtime.spellChannelRefreshOnInterruptible = {}

    local sawSuccessAnchor = false
    for _, spellData in pairs(mobData.spells) do
        local anchorMode = RebuildSpellSchedule(runtime, mobData, spellData, defaultAnchorAt, now)
        if anchorMode == "success" then
            sawSuccessAnchor = true
        end
    end

    if sawSuccessAnchor then
        runtime.anchorMode = "success"
    else
        runtime.anchorMode = "enter"
    end
end

local function HasRuntimeSchedule(runtime)
    if type(runtime) ~= "table" then
        return false
    end
    if runtime.scheduleInitialized == true or runtime.matchedNPCID ~= nil or runtime.scheduleSignature ~= nil then
        return true
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    if bySpell and next(bySpell) ~= nil then
        return true
    end
    local scriptIDs = type(runtime.scriptEventIDs) == "table" and runtime.scriptEventIDs or nil
    if scriptIDs and #scriptIDs > 0 then
        return true
    end
    local nextSpells = type(runtime.nextSpellStartAt) == "table" and runtime.nextSpellStartAt or nil
    return nextSpells and next(nextSpells) ~= nil
end

local function ResetRuntimeSchedule(runtime)
    if type(runtime) ~= "table" then
        return
    end
    if HasRuntimeSchedule(runtime) and Output and type(Output.CancelRuntimeScriptEvents) == "function" then
        Output.CancelRuntimeScriptEvents(runtime)
    end
    runtime.scheduleSignature = nil
    runtime.scheduleInitialized = false
    runtime.anchorMode = nil
    runtime.matchedNPCID = nil
    runtime.matchedMapID = nil
    runtime.nextSpellStartAt = nil
    runtime.nextSpellAnchorAt = nil
    runtime.nextSpellSeqIndex = nil
    runtime.spellCastStartVoiceEligible = nil
    runtime.spellCastStartKindEligible = nil
    runtime.spellChannelRefreshOnInterruptible = nil
    runtime.activeObservedSpellID = nil
    runtime.activeSpellID = nil
    runtime.activeSpellAmbiguous = nil
    runtime.activeSpellPredictedAt = nil
    runtime.activeSpellAnchorAt = nil
    runtime.activeSpellNextSeqIndex = nil
    runtime.activeCastTargetExists = nil
    runtime.activeCastTargetCheckedAt = nil
    runtime.activeCastTargetAPIExists = nil
    runtime.activeCastTargetAPICheckedAt = nil
    runtime.activeCastTargetUnitExists = nil
    runtime.activeCastTargetUnitCheckedAt = nil
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
    runtime.channelRefreshOnInterruptibleAt = nil
    runtime.channelRefreshOnInterruptibleCastBarID = nil
    runtime.channelRefreshOnInterruptibleSeq = nil
    runtime.pendingStartAdvance = false
    runtime.pendingStartAdvanceAt = nil
    runtime.pendingStartAdvanceKind = nil
    runtime.pendingSucceeded = false
    runtime.pendingSucceededAt = nil
    runtime.pendingInterrupted = false
    runtime.pendingInterruptedAt = nil
    runtime.pendingBehavior = nil
    runtime.pendingResolvedCasts = nil
end

function Mod.SyncUnitCDTimers(runtime, obs, candidate, mapID)
    if not runtime then
        return
    end
    if not obs or not candidate or not mapID then
        if obs or candidate or mapID then
            DebugPrint(runtime, string.format("sync reset unit=%s reason=missing obs=%s candidate=%s map=%s",
                tostring(runtime._debugUnit or "?"), tostring(obs ~= nil), tostring(candidate ~= nil), tostring(mapID or "nil")))
        end
        ResetRuntimeSchedule(runtime)
        return
    end

    local candidateNPCID = tonumber(candidate.npcID)
    if not candidateNPCID or candidate.locked == true then
        DebugPrint(runtime, string.format("sync reset unit=%s reason=bad-candidate npc=%s locked=%s",
            tostring(runtime._debugUnit or "?"), tostring(candidate and candidate.npcID or "nil"), tostring(candidate and candidate.locked or false)))
        ResetRuntimeSchedule(runtime)
        return
    end
    if runtime.matchedNPCID and candidateNPCID and runtime.matchedNPCID ~= candidateNPCID then
        runtime.spellAnchors = nil
        runtime.nextSpellStartAt = nil
        runtime.nextSpellAnchorAt = nil
        runtime.nextSpellSeqIndex = nil
        runtime.activeCastKind = nil
        runtime.activeCastStartAt = nil
        runtime.activeObservedSpellID = nil
        runtime.activeCastTargetExists = nil
        runtime.activeCastTargetCheckedAt = nil
        runtime.activeCastTargetAPIExists = nil
        runtime.activeCastTargetAPICheckedAt = nil
        runtime.activeCastTargetUnitExists = nil
        runtime.activeCastTargetUnitCheckedAt = nil
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
        runtime.channelRefreshOnInterruptibleAt = nil
        runtime.channelRefreshOnInterruptibleCastBarID = nil
        runtime.channelRefreshOnInterruptibleSeq = nil
        runtime.activeSpellID = nil
        runtime.activeSpellAmbiguous = nil
        runtime.activeSpellPredictedAt = nil
        runtime.activeSpellAnchorAt = nil
        runtime.activeSpellNextSeqIndex = nil
        runtime.spellCastStartVoiceEligible = nil
        runtime.spellCastStartKindEligible = nil
        runtime.spellChannelRefreshOnInterruptible = nil
        runtime.pendingStartAdvance = false
        runtime.pendingStartAdvanceAt = nil
        runtime.pendingStartAdvanceKind = nil
        runtime.pendingSucceeded = false
        runtime.pendingSucceededAt = nil
        runtime.pendingInterrupted = false
        runtime.pendingInterruptedAt = nil
        runtime.pendingBehavior = nil
        runtime.pendingResolvedCasts = nil
        runtime.scheduleDirty = true
    end

    local mobData = Mod.GetMobCDData(mapID, candidate.npcID)
    if type(mobData) ~= "table" or type(mobData.spells) ~= "table" then
        DebugPrint(runtime, string.format("sync reset unit=%s reason=no-mobData map=%s npc=%s mobData=%s spells=%s",
            tostring(runtime._debugUnit or "?"), tostring(mapID or "nil"), tostring(candidate.npcID or "nil"), tostring(type(mobData)), tostring(type(mobData and mobData.spells))))
        ResetRuntimeSchedule(runtime)
        return
    end

    local defaultAnchorAt = tonumber(runtime.engagedAt) or tonumber(obs.firstSeenAt) or GetTime()
    runtime.defaultAnchorAt = defaultAnchorAt
    runtime.matchedMapID = tonumber(mapID)
    runtime.matchedNPCID = candidateNPCID
    local currentConfigRevision = RuntimeConfig and type(RuntimeConfig.GetConfigRevision) == "function" and tonumber(RuntimeConfig.GetConfigRevision()) or 0
    local candidateChanged = runtime._lastScheduleCandidateNPCID ~= candidateNPCID or runtime._lastScheduleMapID ~= tonumber(mapID)
    local configChanged = tonumber(runtime._lastScheduleConfigRevision) ~= currentConfigRevision

    local advancedSpellID = nil
    local advancedSpellIDs = nil
    if type(runtime.pendingResolvedCasts) == "table" and #runtime.pendingResolvedCasts > 0 then
        while #runtime.pendingResolvedCasts > 0 do
            local snapshot = runtime.pendingResolvedCasts[1]
            local processed, waitReason, queuedAdvancedSpellID, queuedAdvancedSpellIDs = ProcessQueuedPendingCast(
                runtime,
                snapshot,
                mobData,
                defaultAnchorAt
            )
            if not processed then
                DebugPrint(runtime, string.format("sync queued-cast-wait unit=%s reason=%s queue=%d",
                    tostring(runtime._debugUnit or runtime._nameplateUnit or "?"),
                    tostring(waitReason or "unknown"),
                    #runtime.pendingResolvedCasts))
                return
            end
            table.remove(runtime.pendingResolvedCasts, 1)
            DebugPrint(runtime, string.format("sync queued-cast unit=%s advancedSpell=%s startAdvanced=%s remaining=%d",
                tostring(runtime._debugUnit or runtime._nameplateUnit or "?"),
                tostring(queuedAdvancedSpellID or "nil"),
                tostring(type(queuedAdvancedSpellIDs) == "table" and #queuedAdvancedSpellIDs or 0),
                #runtime.pendingResolvedCasts))
            advancedSpellIDs = MergeAdvancedSpellIDs(advancedSpellIDs, queuedAdvancedSpellIDs)
            advancedSpellIDs = AppendAdvancedSpellID(advancedSpellIDs, queuedAdvancedSpellID)
            if queuedAdvancedSpellID or (type(queuedAdvancedSpellIDs) == "table" and #queuedAdvancedSpellIDs > 0) then
                runtime.scheduleDirty = true
            end
        end
    end
    if runtime.pendingStartAdvance == true then
        local observedStartSpell = GetObservedCastStartSpell(
            runtime,
            mobData,
            runtime.pendingStartAdvanceKind or runtime.activeCastKind
        )
        local fingerprintsReady, pendingReason = ArePendingStartFingerprintsResolved(
            runtime,
            mobData,
            runtime.pendingStartAdvanceKind or runtime.activeCastKind
        )
        if not fingerprintsReady and not observedStartSpell then
            DebugPrint(runtime, string.format("sync pending-start-wait unit=%s reason=%s kind=%s",
                tostring(runtime._debugUnit or runtime._nameplateUnit or "?"),
                tostring(pendingReason or "unknown"),
                tostring(runtime.pendingStartAdvanceKind or runtime.activeCastKind or "nil")))
            return
        end
        DebugPrint(runtime, string.format("sync pending-start unit=%s kind=%s at=%s",
            tostring(runtime._debugUnit or "?"),
            tostring(runtime.pendingStartAdvanceKind or runtime.activeCastKind or "nil"),
            tostring(runtime.pendingStartAdvanceAt or runtime.activeCastStartAt or "nil")))
        local currentStartAdvancedSpellIDs = Mod.ApplyObservedStartAdvance(runtime, mobData, defaultAnchorAt)
        DebugPrint(runtime, string.format("sync pending-start-result unit=%s count=%s",
            tostring(runtime._debugUnit or "?"),
            tostring(type(currentStartAdvancedSpellIDs) == "table" and #currentStartAdvancedSpellIDs or 0)))
        runtime.pendingStartAdvance = false
        runtime.pendingStartAdvanceAt = nil
        runtime.pendingStartAdvanceKind = nil
        advancedSpellIDs = MergeAdvancedSpellIDs(advancedSpellIDs, currentStartAdvancedSpellIDs)
        if type(currentStartAdvancedSpellIDs) == "table" and #currentStartAdvancedSpellIDs > 0 then
            runtime.scheduleDirty = true
        end
    end

    if (runtime.pendingSucceeded or runtime.pendingInterrupted) and runtime.activeCastStartAt then
        local resolveMode = runtime.pendingInterrupted and "interrupt" or "success"
        local successAt = tonumber(runtime.pendingSucceededAt) or tonumber(runtime.pendingInterruptedAt) or GetTime()
        if resolveMode == "success" then
            local fingerprintsReady, pendingReason = ArePendingFinishFingerprintsResolved(
                runtime,
                mobData,
                runtime.activeCastKind
            )
            if not fingerprintsReady then
                DebugPrint(runtime, string.format("sync pending-finish-wait unit=%s reason=%s kind=%s",
                    tostring(runtime._debugUnit or runtime._nameplateUnit or "?"),
                    tostring(pendingReason or "unknown"),
                    tostring(runtime.activeCastKind or "nil")))
                return
            end
        end
        DebugPrint(runtime, string.format("sync pending-finish unit=%s mode=%s activeKind=%s activeSpell=%s activeStart=%s successAt=%.3f behavior=%s",
            tostring(runtime._debugUnit or "?"),
            tostring(resolveMode),
            tostring(runtime.activeCastKind or "nil"),
            tostring(runtime.activeSpellID or "nil"),
            tostring(runtime.activeCastStartAt or "nil"),
            tonumber(successAt) or 0,
            tostring(runtime.pendingBehavior or "nil")))
        if type(runtime.pendingBehavior) == "string" and runtime.pendingBehavior ~= "" then
            runtime.lastBehavior = runtime.pendingBehavior
            runtime.lastBehaviorAt = successAt
            if runtime.pendingBehavior == "cast_success" then
                runtime.sawCastSuccess = true
            elseif runtime.pendingBehavior == "cast_interrupted" then
                runtime.sawCastInterrupted = true
            elseif runtime.pendingBehavior == "channel_success" then
                runtime.sawChannelSuccess = true
            end
        end
        if resolveMode == "success" or resolveMode == "interrupt" then
            advancedSpellID = Mod.ApplyObservedCastAdvance(runtime, mobData, defaultAnchorAt, resolveMode, successAt)
        end
        DebugPrint(runtime, string.format("sync pending-finish-result unit=%s advancedSpell=%s",
            tostring(runtime._debugUnit or "?"), tostring(advancedSpellID or "nil")))
        EmitTrashCastBarStop(runtime, runtime.activeCastKind, runtime.activeCastBarID)
        runtime.pendingSucceeded = false
        runtime.pendingSucceededAt = nil
        runtime.pendingInterrupted = false
        runtime.pendingInterruptedAt = nil
        runtime.pendingBehavior = nil
        runtime.lastSucceededAt = successAt
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
        runtime.pendingStartAdvance = false
        runtime.pendingStartAdvanceAt = nil
        runtime.pendingStartAdvanceKind = nil
        -- CAST_START 技能可能已经在 pending-start 阶段锚定 CD。
        -- 后续如果目标假死/失败导致 interrupt，不能把刚才的重排需求覆盖成 false。
        runtime.scheduleDirty = runtime.scheduleDirty == true or resolveMode == "success" or advancedSpellID ~= nil
    end

    local signature = Mod.BuildRuntimeScheduleSignature(runtime, candidate.npcID, defaultAnchorAt)
    local requireFullRebuild = runtime.scheduleSignature == nil or runtime.scheduleInitialized ~= true or candidateChanged or configChanged
    local hasStartAdvanced = type(advancedSpellIDs) == "table" and #advancedSpellIDs > 0
    if not requireFullRebuild and not advancedSpellID and not hasStartAdvanced and runtime.scheduleSignature == signature and not runtime.scheduleDirty then
        DebugPrint(runtime, string.format("sync skip unit=%s reason=clean-signature npc=%s",
            tostring(runtime._debugUnit or "?"), tostring(candidateNPCID or "nil")))
        return
    end

    runtime.scheduleSignature = signature
    runtime.scheduleDirty = false
    runtime._lastScheduleCandidateNPCID = candidateNPCID
    runtime._lastScheduleMapID = tonumber(mapID)
    runtime._lastScheduleConfigRevision = currentConfigRevision

    local now = GetTime()
    if requireFullRebuild then
        local spellCount = 0
        for _, spellData in pairs(mobData.spells or {}) do
            if type(spellData) == "table" then
                spellCount = spellCount + 1
            end
        end
        DebugPrint(runtime, string.format("sync rebuild unit=%s map=%s npc=%s spells=%s anchor=%.3f candidateChanged=%s configChanged=%s",
            tostring(runtime._debugUnit or "?"), tostring(mapID), tostring(candidateNPCID), tostring(spellCount),
            tonumber(defaultAnchorAt) or 0, tostring(candidateChanged), tostring(configChanged)))
        RebuildAllSpellSchedules(runtime, mobData, defaultAnchorAt, now)
        runtime.scheduleInitialized = true
        if not hasStartAdvanced and not advancedSpellID then
            DebugPrint(runtime, string.format("sync rebuild-only unit=%s reason=no-advance npc=%s",
                tostring(runtime._debugUnit or "?"), tostring(candidateNPCID or "nil")))
            return
        end
    end

    if hasStartAdvanced then
        DebugPrint(runtime, string.format("sync start-advance unit=%s map=%s npc=%s count=%d",
            tostring(runtime._debugUnit or "?"), tostring(mapID), tostring(candidateNPCID), #advancedSpellIDs))
        local scheduler = GetScheduler()
        for i = 1, #advancedSpellIDs do
            local spellID = advancedSpellIDs[i]
            if scheduler and type(scheduler.HandleTrashObservedCastSuccess) == "function" then
                scheduler:HandleTrashObservedCastSuccess(runtime, spellID)
            end
            local spellData = mobData.spells and mobData.spells[spellID] or nil
            if type(spellData) == "table" then
                local anchorMode = RebuildSpellSchedule(runtime, mobData, spellData, defaultAnchorAt, now)
                runtime.anchorMode = anchorMode == "success" and "success" or (runtime.anchorMode or "enter")
            end
        end
    end

    if advancedSpellID then
        DebugPrint(runtime, string.format("sync advance unit=%s map=%s npc=%s spell=%s",
            tostring(runtime._debugUnit or "?"), tostring(mapID), tostring(candidateNPCID), tostring(advancedSpellID)))
        local scheduler = GetScheduler()
        if scheduler and type(scheduler.HandleTrashObservedCastSuccess) == "function" then
            scheduler:HandleTrashObservedCastSuccess(runtime, advancedSpellID)
        end
        local spellData = mobData.spells and mobData.spells[advancedSpellID] or nil
        if type(spellData) ~= "table" then
            for _, row in pairs(mobData.spells or {}) do
                if type(row) == "table" and tonumber(row.spellID) == tonumber(advancedSpellID) then
                    spellData = row
                    break
                end
            end
        end
        if type(spellData) == "table" then
            local anchorMode = RebuildSpellSchedule(runtime, mobData, spellData, defaultAnchorAt, now)
            runtime.anchorMode = anchorMode == "success" and "success" or (runtime.anchorMode or "enter")
        end
    end
end
