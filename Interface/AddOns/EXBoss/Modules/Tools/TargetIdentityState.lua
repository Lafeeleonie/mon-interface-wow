-- =============================================================
-- [[ EXBoss Tools: TargetIdentityState ]]
-- 共享职责/职业身份缓存 + 施法目标快照
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss = ExBoss or {}
ExBoss.TargetIdentity = ExBoss.TargetIdentity or {}

local Mod = ExBoss.TargetIdentity

local MODULE_KEY = "ExBoss.TargetIdentity"
local STATE_ROSTER_REVISION = MODULE_KEY .. ".RosterRevision"
local STATE_PLAYER_IDENTITY = MODULE_KEY .. ".PlayerIdentity"
local STATE_PLAYER_USABLE = MODULE_KEY .. ".PlayerIdentityUsable"
local STATE_PLAYER_BLOCK_REASON = MODULE_KEY .. ".PlayerIdentityBlockReason"
local STATE_UNIT_CHANGED = MODULE_KEY .. ".UnitChanged"

local PARTY_UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }
local DEFAULT_SAMPLE_DELAYS = { 0.10 }

Mod._membersByUnit = Mod._membersByUnit or {}
Mod._membersByIdentity = Mod._membersByIdentity or {}
Mod._uniqueUnitByIdentity = Mod._uniqueUnitByIdentity or {}
Mod._duplicateIdentityFlags = Mod._duplicateIdentityFlags or {}
Mod._playerIdentityState = Mod._playerIdentityState or {}
Mod._observedByUnit = Mod._observedByUnit or {}
Mod._rosterRevision = tonumber(Mod._rosterRevision) or 0
Mod._unitRevision = tonumber(Mod._unitRevision) or 0
Mod.SlowRetargetRules = Mod.SlowRetargetRules or {}
Mod.SlowRetargetRules[240973] = Mod.SlowRetargetRules[240973] or { 0.40, 0.50, 0.60 }

local UnitClass = _G.UnitClass
local UnitExists = _G.UnitExists
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local GetTime = _G.GetTime
local UnitGUID = _G.UnitGUID
local C_Timer = _G.C_Timer
local ipairs = _G.ipairs
local pairs = _G.pairs
local tostring = _G.tostring
local tonumber = _G.tonumber
local type = _G.type
local table = _G.table
local math = _G.math

local function NormalizeObservedUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(castBarID)
    local id = tonumber(castBarID)
    if id and id >= 0 then
        return id
    end
    return nil
end

local function NormalizeRole(role)
    role = tostring(role or ""):upper()
    if role == "TANK" then
        return "tank"
    end
    if role == "HEALER" or role == "HEAL" then
        return "heal"
    end
    if role == "DAMAGER" or role == "DPS" then
        return "dps"
    end
    return nil
end

local function BuildIdentity(role, classFile)
    local normalizedRole = NormalizeRole(role)
    local normalizedClass = tostring(classFile or ""):upper()
    if normalizedRole == nil or normalizedClass == "" then
        return nil
    end
    return normalizedRole .. ":" .. normalizedClass
end

local function BuildMemberSnapshot(unitToken)
    if type(unitToken) ~= "string" or UnitExists(unitToken) ~= true then
        return nil
    end

    local localizedClass, classFile, classID = UnitClass(unitToken)
    classID = tonumber(classID)
    classFile = tostring(classFile or ""):upper()
    local role = NormalizeRole(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unitToken) or nil)
    local identity = BuildIdentity(role, classFile)

    return {
        unitToken = unitToken,
        role = role,
        classID = classID,
        classFile = classFile ~= "" and classFile or nil,
        localizedClass = localizedClass,
        identity = identity,
        isPlayer = unitToken == "player",
    }
end

local function ClearTable(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function NotifyUnitChanged(unit)
    Mod._unitRevision = (tonumber(Mod._unitRevision) or 0) + 1
    ExwindTools:UpdateState(STATE_UNIT_CHANGED, {
        unit = tostring(unit or ""),
        revision = Mod._unitRevision,
    })
end

local function GetPlayerIdentityState()
    return Mod._playerIdentityState or {}
end

local function BuildDelayKey(delay)
    return string.format("%.2f", tonumber(delay) or 0)
end

local function BuildSampleDelays(matchedNPCID, extraDelays)
    local merged = {}
    local seen = {}

    local function AddDelay(delay)
        delay = tonumber(delay)
        if not delay or delay < 0 then
            return
        end
        delay = math.max(0, delay)
        local key = BuildDelayKey(delay)
        if seen[key] then
            return
        end
        seen[key] = true
        merged[#merged + 1] = delay
    end

    for i = 1, #DEFAULT_SAMPLE_DELAYS do
        AddDelay(DEFAULT_SAMPLE_DELAYS[i])
    end

    local npcRules = tonumber(matchedNPCID) and Mod.SlowRetargetRules and Mod.SlowRetargetRules[tonumber(matchedNPCID)] or nil
    if type(npcRules) == "table" then
        for i = 1, #npcRules do
            AddDelay(npcRules[i])
        end
    end

    if type(extraDelays) == "table" then
        for i = 1, #extraDelays do
            AddDelay(extraDelays[i])
        end
    end

    table.sort(merged)
    return merged
end

local function CastTokenMatches(entry, castBarID)
    if type(entry) ~= "table" then
        return false
    end
    local wanted = NormalizeCastBarID(castBarID)
    local current = NormalizeCastBarID(entry.castBarID)
    if wanted ~= nil and current ~= nil then
        return wanted == current
    end
    return wanted == nil and current == nil
end

local function ResolveTargetSnapshot(unit)
    local targetUnit = tostring(unit or "") .. "target"
    if UnitExists(targetUnit) ~= true then
        return {
            targetExists = false,
            targetRole = nil,
            targetClassID = nil,
            targetClassFile = nil,
            targetIdentity = nil,
            targetPartyUnit = nil,
            targetIsPlayer = false,
            targetGUID = nil,
        }
    end

    local _, classFile, classID = UnitClass(targetUnit)
    classID = tonumber(classID)
    classFile = tostring(classFile or ""):upper()
    local role = NormalizeRole(UnitGroupRolesAssigned and UnitGroupRolesAssigned(targetUnit) or nil)
    local identity = BuildIdentity(role, classFile)
    local resolvedPartyUnit = type(identity) == "string" and Mod._uniqueUnitByIdentity and Mod._uniqueUnitByIdentity[identity] or nil
    if type(resolvedPartyUnit) ~= "string" then
        resolvedPartyUnit = nil
    end

    return {
        targetExists = true,
        targetRole = role,
        targetClassID = classID,
        targetClassFile = classFile ~= "" and classFile or nil,
        targetIdentity = identity,
        targetPartyUnit = resolvedPartyUnit,
        targetIsPlayer = resolvedPartyUnit == "player",
        targetGUID = UnitGUID(targetUnit),
    }
end

local function ApplyTargetSnapshot(unit, entry, forceResolved)
    if type(entry) ~= "table" then
        return
    end

    local snapshot = ResolveTargetSnapshot(unit)
    entry.targetExists = snapshot.targetExists
    entry.targetRole = snapshot.targetRole
    entry.targetClassID = snapshot.targetClassID
    entry.targetClassFile = snapshot.targetClassFile
    entry.targetIdentity = snapshot.targetIdentity
    entry.targetPartyUnit = snapshot.targetPartyUnit
    entry.targetIsPlayer = snapshot.targetIsPlayer
    entry.targetGUID = snapshot.targetGUID
    entry.lastCheckedAt = GetTime()
    if forceResolved == true then
        entry.resolved = true
    elseif tonumber(entry.resolveDeadlineAt) and entry.lastCheckedAt >= (tonumber(entry.resolveDeadlineAt) - 0.001) then
        entry.resolved = true
    else
        entry.resolved = false
    end
    NotifyUnitChanged(unit)
end

local function ScheduleObservedSample(unit, castSeq, delay)
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    C_Timer.After(math.max(0, tonumber(delay) or 0), function()
        local observedUnit = NormalizeObservedUnit(unit)
        local entry = observedUnit and Mod._observedByUnit and Mod._observedByUnit[observedUnit] or nil
        if type(entry) ~= "table" or entry.active ~= true then
            return
        end
        if tonumber(entry.castSeq) ~= tonumber(castSeq) then
            return
        end
        local resolveDelay = tonumber(entry.resolveDelay) or 0
        local shouldForceResolved = (tonumber(delay) or 0) >= (resolveDelay - 0.001)
        ApplyTargetSnapshot(observedUnit, entry, shouldForceResolved)
    end)
end

function Mod.RefreshRoster()
    ClearTable(Mod._membersByUnit)
    ClearTable(Mod._membersByIdentity)
    ClearTable(Mod._uniqueUnitByIdentity)
    ClearTable(Mod._duplicateIdentityFlags)

    for i = 1, #PARTY_UNIT_TOKENS do
        local snapshot = BuildMemberSnapshot(PARTY_UNIT_TOKENS[i])
        if type(snapshot) == "table" then
            local unitToken = snapshot.unitToken
            local identity = snapshot.identity
            Mod._membersByUnit[unitToken] = snapshot
            if type(identity) == "string" and identity ~= "" then
                local list = Mod._membersByIdentity[identity]
                if type(list) ~= "table" then
                    list = {}
                    Mod._membersByIdentity[identity] = list
                end
                list[#list + 1] = snapshot
                if #list == 1 then
                    Mod._uniqueUnitByIdentity[identity] = unitToken
                else
                    Mod._uniqueUnitByIdentity[identity] = nil
                    Mod._duplicateIdentityFlags[identity] = true
                end
            end
        end
    end

    local playerSnapshot = Mod._membersByUnit.player
    local playerRole = playerSnapshot and playerSnapshot.role or nil
    local playerIdentity = playerSnapshot and playerSnapshot.identity or nil
    local usable = false
    local blockReason = nil

    if playerSnapshot == nil then
        blockReason = "player_missing"
    elseif playerRole ~= "dps" and playerRole ~= "heal" then
        blockReason = "role_not_supported"
    elseif type(playerIdentity) ~= "string" or playerIdentity == "" then
        blockReason = "identity_missing"
    elseif Mod._duplicateIdentityFlags[playerIdentity] == true then
        blockReason = "duplicate_role_class"
    else
        usable = true
    end

    Mod._playerIdentityState = {
        usableForSelfAlert = usable == true,
        blockReason = blockReason,
        playerIdentity = playerIdentity,
        playerRole = playerRole,
        playerClassFile = playerSnapshot and playerSnapshot.classFile or nil,
    }

    Mod._rosterRevision = (tonumber(Mod._rosterRevision) or 0) + 1
    ExwindTools:UpdateState(STATE_PLAYER_IDENTITY, playerIdentity or "")
    ExwindTools:UpdateState(STATE_PLAYER_USABLE, usable == true)
    ExwindTools:UpdateState(STATE_PLAYER_BLOCK_REASON, blockReason or "")
    ExwindTools:UpdateState(STATE_ROSTER_REVISION, Mod._rosterRevision)
end

function Mod.GetRosterSnapshot()
    return {
        membersByUnit = Mod._membersByUnit,
        membersByIdentity = Mod._membersByIdentity,
        uniqueUnitByIdentity = Mod._uniqueUnitByIdentity,
        duplicateIdentityFlags = Mod._duplicateIdentityFlags,
        playerIdentityState = GetPlayerIdentityState(),
        revision = tonumber(Mod._rosterRevision) or 0,
    }
end

function Mod.GetPlayerIdentityState()
    return GetPlayerIdentityState()
end

function Mod.GetMemberByUnit(unitToken)
    return Mod._membersByUnit and Mod._membersByUnit[unitToken] or nil
end

function Mod.BeginObservedCast(unit, castBarID, opts)
    local observedUnit = NormalizeObservedUnit(unit)
    if not observedUnit then
        return nil
    end

    opts = type(opts) == "table" and opts or {}
    local normalizedCastBarID = NormalizeCastBarID(castBarID)
    local matchedNPCID = tonumber(opts.matchedNPCID)
    local now = GetTime()
    local existing = Mod._observedByUnit[observedUnit]
    local sampleDelays = BuildSampleDelays(matchedNPCID, opts.extraSampleDelays)
    local maxDelay = sampleDelays[#sampleDelays] or 0
    if type(existing) == "table" and existing.active == true and CastTokenMatches(existing, normalizedCastBarID) then
        if matchedNPCID then
            existing.matchedNPCID = matchedNPCID
        end
        if type(opts.source) == "string" and opts.source ~= "" then
            existing.source = opts.source
        end
        existing.resolveDelay = math.max(tonumber(existing.resolveDelay) or 0, maxDelay)
        existing.resolveDeadlineAt = (tonumber(existing.startedAt) or now) + (tonumber(existing.resolveDelay) or 0)
        if tonumber(existing.lastCheckedAt) and existing.lastCheckedAt >= ((tonumber(existing.resolveDeadlineAt) or 0) - 0.001) then
            existing.resolved = true
        else
            existing.resolved = false
        end
        existing._scheduledDelayKeys = type(existing._scheduledDelayKeys) == "table" and existing._scheduledDelayKeys or {}
        for i = 1, #sampleDelays do
            local delay = sampleDelays[i]
            local delayKey = BuildDelayKey(delay)
            if existing._scheduledDelayKeys[delayKey] ~= true then
                existing._scheduledDelayKeys[delayKey] = true
                ScheduleObservedSample(observedUnit, existing.castSeq, delay)
            end
        end
        return existing
    end

    local entry = {
        unit = observedUnit,
        active = true,
        castSeq = type(existing) == "table" and ((tonumber(existing.castSeq) or 0) + 1) or 1,
        castBarID = normalizedCastBarID,
        startedAt = now,
        resolveDelay = maxDelay,
        resolveDeadlineAt = now + maxDelay,
        matchedNPCID = matchedNPCID,
        source = tostring(opts.source or ""),
        targetExists = nil,
        targetRole = nil,
        targetClassID = nil,
        targetClassFile = nil,
        targetIdentity = nil,
        targetPartyUnit = nil,
        targetIsPlayer = false,
        targetGUID = nil,
        lastCheckedAt = nil,
        resolved = false,
        _scheduledDelayKeys = {},
    }
    Mod._observedByUnit[observedUnit] = entry

    for i = 1, #sampleDelays do
        local delay = sampleDelays[i]
        entry._scheduledDelayKeys[BuildDelayKey(delay)] = true
        ScheduleObservedSample(observedUnit, entry.castSeq, delay)
    end
    return entry
end

function Mod.EndObservedCast(unit, castBarID)
    local observedUnit = NormalizeObservedUnit(unit)
    if not observedUnit then
        return false
    end
    local entry = Mod._observedByUnit[observedUnit]
    if type(entry) ~= "table" then
        return false
    end
    if castBarID ~= nil and not CastTokenMatches(entry, castBarID) then
        return false
    end
    Mod._observedByUnit[observedUnit] = nil
    NotifyUnitChanged(observedUnit)
    return true
end

function Mod.ClearObservedUnit(unit)
    return Mod.EndObservedCast(unit, nil)
end

function Mod.GetObservedUnitState(unit)
    local observedUnit = NormalizeObservedUnit(unit)
    if not observedUnit then
        return nil
    end
    return Mod._observedByUnit and Mod._observedByUnit[observedUnit] or nil
end

function Mod.GetObservedTargetIdentity(unit)
    local entry = Mod.GetObservedUnitState(unit)
    return entry and entry.targetIdentity or nil
end

function Mod.IsObservedTargetMatchingPlayerIdentity(unit)
    local entry = Mod.GetObservedUnitState(unit)
    local playerState = GetPlayerIdentityState()
    local playerIdentity = type(playerState) == "table" and playerState.playerIdentity or nil
    if type(playerIdentity) ~= "string" or playerIdentity == "" then
        return false
    end
    return type(entry) == "table" and entry.targetIdentity == playerIdentity or false
end

function Mod.GetObservedTargetPartyUnit(unit)
    local entry = Mod.GetObservedUnitState(unit)
    return entry and entry.targetPartyUnit or nil
end

function Mod.IsObservedTargetPlayer(unit)
    local entry = Mod.GetObservedUnitState(unit)
    return entry and entry.targetIsPlayer == true or false
end

function Mod.GetObservedResolveDelay(unit)
    local entry = Mod.GetObservedUnitState(unit)
    if type(entry) == "table" then
        return tonumber(entry.resolveDelay) or 0
    end
    return DEFAULT_SAMPLE_DELAYS[#DEFAULT_SAMPLE_DELAYS] or 0
end

function Mod.GetObservedResolveDeadline(unit)
    local entry = Mod.GetObservedUnitState(unit)
    return type(entry) == "table" and tonumber(entry.resolveDeadlineAt) or nil
end

function Mod.RefreshObservedTargets()
    for unit, entry in pairs(Mod._observedByUnit or {}) do
        if type(entry) == "table" and entry.active == true then
            ApplyTargetSnapshot(unit, entry, entry.resolved == true)
        end
    end
end

local function OnRosterChanged()
    Mod.RefreshRoster()
    Mod.RefreshObservedTargets()
end

ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", MODULE_KEY, OnRosterChanged)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, OnRosterChanged)
ExwindTools:RegisterEvent("PLAYER_ROLES_ASSIGNED", MODULE_KEY, OnRosterChanged)
ExwindTools:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", MODULE_KEY, OnRosterChanged)
ExwindTools:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", MODULE_KEY, OnRosterChanged)

Mod.RefreshRoster()
