---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Layer2Filter or {}
ExBoss.TrashCD.Layer2Filter = Mod
ExBoss.Trash.Layer2Filter = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Rules = ExBoss.TrashCD and ExBoss.TrashCD.InferenceRules or nil
local LAST_DEBUG = nil

local CAST_TIME_TOLERANCE = 0.20
local FIRST_CAST_TOLERANCE = 2.0

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

local function GetMobData(mapID, npcID)
    local root = Data and Data.GetTrashCDDataRoot and Data.GetTrashCDDataRoot() or nil
    local mapRow = type(root) == "table" and type(root[tonumber(mapID)]) == "table" and root[tonumber(mapID)] or nil
    local mobs = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs or nil
    return mobs and mobs[tonumber(npcID)] or nil
end

local function GetCandidateLabel(candidate)
    if type(candidate) ~= "table" then
        return "?(?)"
    end
    return string.format("%s(%s)", tostring(candidate.name or "?"), tostring(candidate.npcID or "?"))
end

local function BuildObservedBehavior(obs, runtime, now)
    runtime = type(runtime) == "table" and runtime or {}
    obs = type(obs) == "table" and obs or {}
    now = tonumber(now) or GetTime()

    local startAt = tonumber(runtime.activeCastStartAt)
    local successAt = tonumber(runtime.pendingSucceededAt) or tonumber(runtime.pendingInterruptedAt)
    local duration = nil
    if startAt and successAt and successAt >= startAt then
        duration = successAt - startAt
    end
    local transitionStartAt = tonumber(runtime.transitionCastStartAt)
    local compositeDuration = nil
    if transitionStartAt and successAt and successAt >= transitionStartAt then
        compositeDuration = successAt - transitionStartAt
    end

    return {
        kind = tostring(runtime.activeCastKind or ""),
        sawCast = obs.sawCastStart == true,
        sawChannel = obs.sawChannelStart == true,
        sawInterrupted = obs.sawInterrupted == true,
        observedDuration = duration,
        compositeDuration = compositeDuration,
        interrupted = runtime.pendingInterrupted == true,
        elapsedSinceSeen = tonumber(obs.firstSeenAt) and math.max(0, now - tonumber(obs.firstSeenAt)) or nil,
        lastBehavior = tostring(runtime.lastBehavior or ""),
        sawCastSuccess = runtime.sawCastSuccess == true,
        sawCastInterrupted = runtime.sawCastInterrupted == true,
        sawChannelSuccess = runtime.sawChannelSuccess == true,
        sawCastIntoChannel = runtime.sawCastIntoChannel == true,
    }
end

local function MatchesBehaviorCapability(layer2Rule, behavior)
    if type(layer2Rule) ~= "table" or type(behavior) ~= "string" or behavior == "" then
        return nil
    end
    if behavior == "cast_success" then
        return layer2Rule.canCastSuccess == true
    elseif behavior == "cast_interrupted" then
        return layer2Rule.canCastInterrupt == true
    elseif behavior == "channel_success" then
        return layer2Rule.canChannelSuccess == true
    elseif behavior == "cast_into_channel" then
        return layer2Rule.canCastIntoChannel == true
    end
    return nil
end

local function MobSupportsBehavior(mobData, behavior)
    if type(behavior) ~= "string" or behavior == "" then
        return nil
    end
    local hasSpells = type(mobData) == "table" and type(mobData.spells) == "table"
    if behavior == "cast_success" or behavior == "cast_interrupted" then
        if not hasSpells then
            return nil
        end
        for _, spellData in pairs(mobData.spells) do
            local castTimes = GetCastTimeCandidates(spellData)
            if #castTimes > 0 then
                return true
            end
        end
        return false
    elseif behavior == "channel_success" then
        return nil
    elseif behavior == "cast_into_channel" then
        return nil
    end
    return nil
end

local function BuildBehaviorEvidence(behavior)
    local out = {}
    if type(behavior) ~= "table" then
        return out
    end
    if behavior.sawCastSuccess == true then
        out[#out + 1] = "cast_success"
    end
    if behavior.sawCastInterrupted == true then
        out[#out + 1] = "cast_interrupted"
    end
    if behavior.sawChannelSuccess == true then
        out[#out + 1] = "channel_success"
    end
    if behavior.sawCastIntoChannel == true then
        out[#out + 1] = "cast_into_channel"
    end
    if #out == 0 and type(behavior.lastBehavior) == "string" and behavior.lastBehavior ~= "" then
        out[#out + 1] = behavior.lastBehavior
    end
    return out
end

local function HasMatchingCastTime(mobData, observedDuration)
    if type(mobData) ~= "table" or type(mobData.spells) ~= "table" or type(observedDuration) ~= "number" then
        return nil
    end
    local foundTimedSpell = false
    for _, spellData in pairs(mobData.spells) do
        local castTimes = GetCastTimeCandidates(spellData)
        for i = 1, #castTimes do
            local castTime = castTimes[i]
            foundTimedSpell = true
            if math.abs(castTime - observedDuration) <= CAST_TIME_TOLERANCE then
                return true
            end
        end
    end
    if foundTimedSpell then
        return false
    end
    return nil
end

local function HasMatchingRuleDuration(rules, observedDuration, kind)
    if type(rules) ~= "table" or type(observedDuration) ~= "number" then
        return nil
    end
    local foundRule = false
    for i = 1, #rules do
        local row = rules[i]
        if type(row) == "table" and (row.kind == nil or tostring(row.kind) == tostring(kind or "")) then
            local duration = tonumber(row.duration)
            local tolerance = tonumber(row.tolerance) or CAST_TIME_TOLERANCE
            if duration and duration > 0 then
                foundRule = true
                if math.abs(duration - observedDuration) <= tolerance then
                    return true
                end
            end
        end
    end
    if foundRule then
        return false
    end
    return nil
end

local function HasMatchingChannelTime(spellData, observedDuration)
    if type(spellData) ~= "table" or type(observedDuration) ~= "number" then
        return nil
    end
    local channelTimes = GetChannelTimeCandidates(spellData)
    if #channelTimes == 0 then
        return nil
    end
    for i = 1, #channelTimes do
        if math.abs(channelTimes[i] - observedDuration) <= CAST_TIME_TOLERANCE then
            return true
        end
    end
    return false
end

local function ExceedsFirstObservedWindow(mobData, elapsedSinceSeen)
    if type(mobData) ~= "table" or type(mobData.spells) ~= "table" or type(elapsedSinceSeen) ~= "number" then
        return false
    end
    local earliest = nil
    for _, spellData in pairs(mobData.spells) do
        if type(spellData) == "table" then
            local first = tonumber(spellData.first)
            if first and #GetCastTimeCandidates(spellData) > 0 then
                earliest = earliest and math.min(earliest, first) or first
            end
        end
    end
    if not earliest then
        return false
    end
    return elapsedSinceSeen > (earliest + FIRST_CAST_TOLERANCE)
end

local function ExceedsFirstObservedRuleWindow(rules, elapsedSinceSeen, kind)
    if type(rules) ~= "table" or type(elapsedSinceSeen) ~= "number" then
        return false
    end
    local earliest = nil
    for i = 1, #rules do
        local row = rules[i]
        if type(row) == "table" and (row.kind == nil or tostring(row.kind) == tostring(kind or "cast")) then
            local first = tonumber(row.first)
            local tolerance = tonumber(row.tolerance) or FIRST_CAST_TOLERANCE
            if first then
                earliest = earliest and math.min(earliest, first + tolerance) or (first + tolerance)
            end
        end
    end
    if not earliest then
        return false
    end
    return elapsedSinceSeen > earliest
end

local function SpellHasCastIntoChannelFingerprint(spellRow)
    if type(spellRow) ~= "table" then
        return false
    end
    local castTime = tonumber(spellRow.castTime)
    local channelTime = tonumber(spellRow.channelTime)
    if not castTime or castTime <= 0 then
        return false
    end
    if not channelTime or channelTime <= 0 then
        return false
    end
    return true
end

local function SpellMatchesCastIntoChannelTiming(spellRow, behavior)
    if type(spellRow) ~= "table" or type(behavior) ~= "table" then
        return false
    end
    local castTime = tonumber(spellRow.castTime)
    local channelTimes = GetChannelTimeCandidates(spellRow)
    if not castTime or castTime <= 0 or #channelTimes == 0 then
        return false
    end
    local observedChannel = tonumber(behavior.observedDuration)
    local observedComposite = tonumber(behavior.compositeDuration)
    local hasObservedTiming = observedChannel ~= nil or observedComposite ~= nil
    if not hasObservedTiming then
        return true
    end
    for i = 1, #channelTimes do
        local channelTime = channelTimes[i]
        local channelOK = true
        local compositeOK = true
        if observedChannel then
            if behavior.interrupted == true then
                channelOK = observedChannel <= (channelTime + CAST_TIME_TOLERANCE)
            else
                channelOK = math.abs(channelTime - observedChannel) <= CAST_TIME_TOLERANCE
            end
        end
        if observedComposite then
            if behavior.interrupted == true and observedChannel then
                compositeOK = math.abs((castTime + observedChannel) - observedComposite) <= CAST_TIME_TOLERANCE
            else
                compositeOK = math.abs((castTime + channelTime) - observedComposite) <= CAST_TIME_TOLERANCE
            end
        end
        if channelOK and compositeOK then
            return true
        end
    end
    return false
end

local function MatchByCastIntoChannelFingerprint(candidates, behavior, mapID)
    if type(behavior) ~= "table" or behavior.sawCastIntoChannel ~= true then
        return nil
    end
    if type(candidates) ~= "table" or #candidates <= 1 then
        return nil
    end

    local matched = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local mobData = GetMobData(mapID, candidate and candidate.npcID)
        local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
        if type(spells) == "table" then
            for _, spellRow in pairs(spells) do
                if SpellHasCastIntoChannelFingerprint(spellRow)
                    and SpellMatchesCastIntoChannelTiming(spellRow, behavior) then
                    matched[#matched + 1] = candidate
                    break
                end
            end
        end
    end

    if #matched > 0 and #matched < #candidates then
        return matched
    end
    return nil
end

local function SpellMatchesCurrentFingerprint(spellData, behavior, runtime)
    if type(spellData) ~= "table" or type(behavior) ~= "table" or type(runtime) ~= "table" then
        return false, "invalid"
    end

    local kind = tostring(behavior.kind or "")
    if kind == "cast" then
        local castTimes = GetCastTimeCandidates(spellData)
        if #castTimes == 0 then
            return false, "kind"
        end
        if type(behavior.observedDuration) == "number" then
            local matched = false
            for i = 1, #castTimes do
                if math.abs(castTimes[i] - behavior.observedDuration) <= CAST_TIME_TOLERANCE then
                    matched = true
                    break
                end
            end
            if not matched then
                return false, "cast-duration"
            end
        end
    elseif kind == "channel" then
        local channelTimes = GetChannelTimeCandidates(spellData)
        if #channelTimes == 0 then
            return false, "kind"
        end
        if behavior.sawCastIntoChannel == true and not SpellHasCastIntoChannelFingerprint(spellData) then
            return false, "cast-into-channel"
        end
        if behavior.sawCastIntoChannel == false and SpellHasCastIntoChannelFingerprint(spellData) then
            return false, "pure-channel-no-cast"
        end
        if type(behavior.observedDuration) == "number" then
            local matched = HasMatchingChannelTime(spellData, behavior.observedDuration)
            if matched == false then
                return false, "channel-duration"
            end
        end
    else
        return false, "kind"
    end

    if type(spellData.targetExists) == "boolean"
        and type(runtime.activeCastTargetExists) == "boolean"
        and spellData.targetExists ~= runtime.activeCastTargetExists then
        return false, "targetExists"
    end

    if type(spellData.targetAPIExists) == "boolean"
        and type(runtime.activeCastTargetAPIExists) == "boolean"
        and spellData.targetAPIExists ~= runtime.activeCastTargetAPIExists then
        return false, "targetAPIExists"
    end

    if type(spellData.targetIsTank) == "boolean"
        and type(runtime.activeCastTargetIsTank) == "boolean"
        and spellData.targetIsTank ~= runtime.activeCastTargetIsTank then
        return false, "targetIsTank"
    end

    if type(spellData.castStartTargetUnitExists) == "boolean"
        and type(runtime.activeCastTargetUnitExists) == "boolean"
        and spellData.castStartTargetUnitExists ~= runtime.activeCastTargetUnitExists then
        return false, "targetUnitExists"
    end

    if type(spellData.targetClearOnCastStart) == "boolean"
        and runtime.activeCastTargetClearResolved == true
        and spellData.targetClearOnCastStart ~= (runtime.activeCastTargetClearedOnStart == true) then
        return false, "targetClear"
    end

    if type(spellData.castStartChangeTarget) == "boolean"
        and runtime.activeCastTargetSwitchResolved == true
        and spellData.castStartChangeTarget ~= (runtime.activeCastTargetSwitched == true) then
        return false, "targetSwitch"
    end

    if runtime.activeCastAuraDeltaResolved == true then
        local wantsAuraDelta = spellData.castStartAuraDelta == true
        if runtime.activeCastAuraDeltaMatched == true and wantsAuraDelta ~= true then
            return false, "auraDelta"
        end
        if runtime.activeCastAuraDeltaMatched ~= true and wantsAuraDelta == true then
            return false, "auraDelta"
        end
    end

    local expectedTargetBuff = tonumber(spellData.targetBuffCountDeltaOnSuccess)
    if expectedTargetBuff ~= nil
        and runtime.activeCastSuccessTargetBuffCountResolved == true
        and tonumber(runtime.activeCastSuccessTargetBuffCountDelta) ~= expectedTargetBuff then
        return false, "targetBuffDelta"
    end

    local expectedSelfBuff = tonumber(spellData.selfBuffCountDeltaOnSuccess)
    if expectedSelfBuff ~= nil
        and runtime.activeCastSuccessSelfBuffCountResolved == true
        and tonumber(runtime.activeCastSuccessSelfBuffCountDelta) ~= expectedSelfBuff then
        return false, "selfBuffDelta"
    end

    return true, "match"
end

local function CandidateMatchesCurrentFingerprint(candidate, behavior, runtime, mapID)
    local mobData = GetMobData(mapID, candidate and candidate.npcID)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if type(spells) ~= "table" then
        return false, "no-spells"
    end
    local sawRelevantSpell = false
    local lastReason = "no-match"
    for _, spellData in pairs(spells) do
        if type(spellData) == "table" then
            local matched, reason = SpellMatchesCurrentFingerprint(spellData, behavior, runtime)
            if matched == true then
                return true, "match"
            end
            if reason ~= "kind" then
                sawRelevantSpell = true
            end
            lastReason = reason or lastReason
        end
    end
    return false, sawRelevantSpell and lastReason or "kind"
end

local function NarrowByCurrentFingerprint(candidates, behavior, runtime, mapID)
    if type(candidates) ~= "table" or #candidates <= 1 or type(runtime) ~= "table" then
        return nil, nil
    end
    if runtime.activeCastStartAt == nil then
        return nil, nil
    end
    if tostring(behavior.kind or "") ~= "cast" and tostring(behavior.kind or "") ~= "channel" then
        return nil, nil
    end

    local matched = {}
    local reasons = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local ok, reason = CandidateMatchesCurrentFingerprint(candidate, behavior, runtime, mapID)
        reasons[tonumber(candidate and candidate.npcID) or i] = reason or "?"
        if ok == true then
            matched[#matched + 1] = candidate
        end
    end
    if #matched > 0 and #matched < #candidates then
        return matched, reasons
    end
    return nil, reasons
end

function Mod.FilterCandidates(candidates, obs, runtime, mapID, now)
    if type(candidates) ~= "table" or #candidates <= 1 then
        LAST_DEBUG = {
            initialCount = type(candidates) == "table" and #candidates or 0,
            finalCount = type(candidates) == "table" and #candidates or 0,
            returnedOriginal = true,
            behavior = BuildObservedBehavior(obs, runtime, now),
            kept = type(candidates) == "table" and candidates or {},
            decisions = {},
        }
        return candidates
    end

    local behavior = BuildObservedBehavior(obs, runtime, now)
    local debug = {
        initialCount = #candidates,
        behavior = behavior,
        fingerprintNarrowed = false,
        fingerprintBefore = {},
        fingerprintAfter = {},
        decisions = {},
        kept = {},
        finalCount = 0,
        returnedOriginal = false,
    }
    for i = 1, #candidates do
        debug.fingerprintBefore[#debug.fingerprintBefore + 1] = GetCandidateLabel(candidates[i])
    end

    local currentFingerprintNarrowed, currentFingerprintReasons = NarrowByCurrentFingerprint(candidates, behavior, runtime, mapID)
    if currentFingerprintNarrowed then
        candidates = currentFingerprintNarrowed
    end

    local fingerprintNarrowed = MatchByCastIntoChannelFingerprint(candidates, behavior, mapID)
    if fingerprintNarrowed then
        debug.fingerprintNarrowed = true
        candidates = fingerprintNarrowed
        for i = 1, #candidates do
            debug.fingerprintAfter[#debug.fingerprintAfter + 1] = GetCandidateLabel(candidates[i])
        end
        if #candidates <= 1 then
            debug.finalCount = #candidates
            debug.kept = candidates
            LAST_DEBUG = debug
            return candidates
        end
    end

    local evidenceList = BuildBehaviorEvidence(behavior)
    local filtered = {}

    for i = 1, #candidates do
        local candidate = candidates[i]
        local keep = true
        local rejectReason = nil
        local mobData = GetMobData(mapID, candidate and candidate.npcID)
        local layer2Rule = Rules and type(Rules.GetLayer2Rule) == "function" and Rules.GetLayer2Rule(mapID, candidate and candidate.npcID) or nil
        local candidateNPCID = tonumber(candidate and candidate.npcID)
        local narrowedReason = type(currentFingerprintReasons) == "table" and currentFingerprintReasons[candidateNPCID] or nil
        if currentFingerprintNarrowed and narrowedReason and narrowedReason ~= "match" then
            keep = false
            rejectReason = "current:" .. tostring(narrowedReason)
        end
        if keep then
            for evidenceIndex = 1, #evidenceList do
                local evidence = evidenceList[evidenceIndex]
                local behaviorSupport = MatchesBehaviorCapability(layer2Rule, evidence)
                if behaviorSupport == nil then
                    behaviorSupport = MobSupportsBehavior(mobData, evidence)
                end
                if behaviorSupport == false then
                    keep = false
                    rejectReason = "behavior:" .. tostring(evidence)
                    break
                end
            end
        end

        if keep and behavior.observedDuration and behavior.kind == "cast" then
            local matched = HasMatchingRuleDuration(layer2Rule and layer2Rule.castRules, behavior.observedDuration, "cast")
            if matched == nil then
                matched = HasMatchingCastTime(mobData, behavior.observedDuration)
            end
            if matched == false then
                keep = false
                rejectReason = string.format("cast-duration:%.3f", tonumber(behavior.observedDuration) or 0)
            end
        elseif keep and behavior.observedDuration and behavior.kind == "channel" then
            local matched = HasMatchingRuleDuration(layer2Rule and layer2Rule.channelRules, behavior.observedDuration, "channel")
            if matched == false then
                keep = false
                rejectReason = string.format("channel-duration:%.3f", tonumber(behavior.observedDuration) or 0)
            end
        end

        debug.decisions[#debug.decisions + 1] = {
            npcID = tonumber(candidate and candidate.npcID),
            name = tostring(candidate and candidate.name or "?"),
            keep = keep == true,
            reason = rejectReason or "keep",
        }
        if keep then
            filtered[#filtered + 1] = candidate
        end
    end

    if #filtered > 0 then
        debug.finalCount = #filtered
        debug.kept = filtered
        LAST_DEBUG = debug
        return filtered
    end
    debug.finalCount = #candidates
    debug.kept = candidates
    debug.returnedOriginal = true
    LAST_DEBUG = debug
    return candidates
end

function Mod.GetLastDebug()
    return LAST_DEBUG
end
