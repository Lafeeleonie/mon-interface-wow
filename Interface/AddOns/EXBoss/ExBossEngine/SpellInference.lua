---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/SpellInference.lua
-- 施法时长反推 SpellID（仅 START -> SUCCEEDED）
-- =============================================================

ExBoss.Timeline.SpellInference = ExBoss.Timeline.SpellInference or {}
local Infer = ExBoss.Timeline.SpellInference

local MAX_KEEP_SECONDS = 8
local MAX_HISTORY = 200
local MAX_PULLS_PER_BOSS = 3
local MAX_RECORDS_PER_PULL = 500

Infer._frame = Infer._frame or nil
Infer._active = false
Infer._encounterID = nil
Infer._pendingByUnit = Infer._pendingByUnit or {}
Infer._history = Infer._history or {}
Infer._currentPull = nil  -- 当前这场战斗的记录缓冲

local function DB()
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.spellInference = ExBossDB.timer.spellInference or {}
    local db = ExBossDB.timer.spellInference

    if db.enabled == nil then db.enabled = true end
    if type(db.tolerance) ~= "number" then db.tolerance = 0.18 end
    if db.debug == nil then db.debug = false end
    if type(db.mappings) ~= "table" then db.mappings = {} end

    return db
end

local function IsBossUnit(unit)
    if type(unit) ~= "string" then return false end
    return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
end

local function Now()
    return GetTime()
end

local function Clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function PushHistory(payload)
    table.insert(Infer._history, 1, payload)
    while #Infer._history > MAX_HISTORY do
        table.remove(Infer._history)
    end
end

local function DebugPrint(msg)
    local db = DB()
    if db.debug then
--         print("|cffff4400Ex|r|cff00ccffBoss|r [Infer] " .. tostring(msg))
    end
end

local function CleanupExpired(now)
    for unit, list in pairs(Infer._pendingByUnit) do
        if type(list) == "table" then
            for i = #list, 1, -1 do
                local rec = list[i]
                if type(rec) ~= "table" or (now - (rec.startTime or now)) > MAX_KEEP_SECONDS then
                    table.remove(list, i)
                end
            end
            if #list == 0 then
                Infer._pendingByUnit[unit] = nil
            end
        else
            Infer._pendingByUnit[unit] = nil
        end
    end
end

local function AddPending(unit, _castGUID, spellID)
    local now = Now()
    CleanupExpired(now)

    local rec = {
        unit = unit,
        startTime = now,
        startSpellID = tonumber(spellID),
        encounterID = Infer._encounterID,
    }

    Infer._pendingByUnit[unit] = Infer._pendingByUnit[unit] or {}
    table.insert(Infer._pendingByUnit[unit], rec)
end

local function ConsumePending(unit, _castGUID)
    local now = Now()
    CleanupExpired(now)

    local rec = nil
    local list = Infer._pendingByUnit[unit]
    if type(list) == "table" then
        rec = list[1]
        if rec then
            table.remove(list, 1)
        end
        if #list == 0 then
            Infer._pendingByUnit[unit] = nil
        end
    end

    return rec
end

local function FindBestMapping(encounterID, unit, castDuration)
    local db = DB()
    local list = db.mappings and db.mappings[encounterID]
    if type(list) ~= "table" then return nil end

    local best = nil
    local bestDelta = math.huge

    for _, item in ipairs(list) do
        if type(item) == "table" then
            local mappedSpellID = tonumber(item.spellID)
            local mappedTime = tonumber(item.castTime)
            if mappedSpellID and mappedTime then
                local mappedUnit = item.bossUnit
                if not mappedUnit or mappedUnit == unit then
                    local tol = tonumber(item.tolerance) or tonumber(db.tolerance) or 0.18
                    tol = math.max(0.01, tol)
                    local delta = math.abs(castDuration - mappedTime)
                    if delta <= tol and delta < bestDelta then
                        bestDelta = delta
                        best = {
                            spellID = mappedSpellID,
                            expected = mappedTime,
                            delta = delta,
                            tolerance = tol,
                            entry = item,
                        }
                    end
                end
            end
        end
    end

    return best
end

local function CalibDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.calibration = ExBossDB.calibration or {}
    return ExBossDB.calibration
end

local function FindPredictedTimer(spellID, actualTime)
    local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if not sched then return nil end
    local best, bestDelta
    for _, timer in pairs(sched._active) do
        if timer.spellID == spellID and timer.firedAt then
            local d = math.abs(timer.firedAt - actualTime)
            if not bestDelta or d < bestDelta then
                bestDelta = d
                best = timer
            end
        end
    end
    if not best and sched._lastFired then
        for _, timer in ipairs(sched._lastFired) do
            if timer.spellID == spellID then
                local d = math.abs(timer.firedAt - actualTime)
                if not bestDelta or d < bestDelta then
                    bestDelta = d
                    best = timer
                end
            end
        end
    end
    return best
end

local function SaveCalibRecord(payload)
    if not Infer._currentPull then return end
    if #Infer._currentPull.records >= MAX_RECORDS_PER_PULL then return end

    local predicted, delta
    if payload.spellID then
        local timer = FindPredictedTimer(payload.spellID, payload.timestamp)
        if timer and timer.castTime then
            predicted = timer.castTime
            delta = payload.timestamp - timer.castTime
        end
    end

    table.insert(Infer._currentPull.records, {
        sp  = payload.spellID,
        pre = predicted,
        act = payload.timestamp,
        dlt = delta,
        cf  = payload.confidence,
        ut  = payload.unit,
    })
end

local function CommitPull(encounterID)
    if not Infer._currentPull or #Infer._currentPull.records == 0 then return end
    local db = CalibDB()
    local key = tostring(encounterID)
    db[key] = db[key] or {}
    local pulls = db[key]
    table.insert(pulls, 1, Infer._currentPull)
    while #pulls > MAX_PULLS_PER_BOSS do
        table.remove(pulls)
    end
    Infer._currentPull = nil
end

local function EmitResolved(payload)
    PushHistory(payload)
    SaveCalibRecord(payload)
    if ExwindTools and ExwindTools.SendEvent then
        ExwindTools:SendEvent("EXBOSS_SPELL_INFERRED", payload)
    end

    if payload.inferred then
        DebugPrint(string.format(
            "inferred spellID=%s encounter=%s unit=%s cast=%.3fs confidence=%.2f",
            tostring(payload.spellID), tostring(payload.encounterID), tostring(payload.unit),
            tonumber(payload.castDuration) or 0, tonumber(payload.confidence) or 0
        ))
    else
        DebugPrint(string.format(
            "resolved spellID=%s encounter=%s unit=%s cast=%.3fs",
            tostring(payload.spellID), tostring(payload.encounterID), tostring(payload.unit),
            tonumber(payload.castDuration) or 0
        ))
    end
end

function Infer:ResetEncounterState()
    self._pendingByUnit = {}
end

function Infer:OnEncounterStart(encounterID)
    self._active = true
    self._encounterID = tonumber(encounterID)
    self:ResetEncounterState()
    -- 新建本场 pull 缓冲
    local dateStr = date and date("%Y-%m-%d %H:%M") or "unknown"
    self._currentPull = { date = dateStr, encounterID = self._encounterID, records = {} }
end

function Infer:OnEncounterEnd()
    CommitPull(self._encounterID)
    self._active = false
    self._encounterID = nil
    self:ResetEncounterState()
end

function Infer:OnSpellcastStart(unit, _castGUID, _spellID)
    local db = DB()
    if db.enabled == false then return end
    if not self._active then return end
    if not IsBossUnit(unit) then return end

    AddPending(unit, nil, _spellID)
end

function Infer:OnSpellcastSucceeded(unit, _castGUID, _spellID)
    local db = DB()
    if db.enabled == false then return end
    if not self._active then return end
    if not IsBossUnit(unit) then return end

    local rec = ConsumePending(unit, nil)
    if not rec then
        DebugPrint("succeeded without start, unit=" .. tostring(unit))
        return
    end

    local now = Now()
    local castDuration = math.max(0, now - (rec.startTime or now))
    local resolvedSpellID = nil
    local inferred = true
    local confidence = 1.0
    local mapping = nil

    mapping = FindBestMapping(self._encounterID, unit, castDuration)
    if mapping and mapping.spellID then
        resolvedSpellID = mapping.spellID
        confidence = 1.0 - Clamp(mapping.delta / math.max(0.01, mapping.tolerance), 0, 1)
    else
        inferred = false
        confidence = 0.0
    end

    local payload = {
        encounterID = self._encounterID,
        unit = unit,
        castDuration = castDuration,
        startSpellID = rec.startSpellID,
        succeededSpellID = nil, -- 12.0 场景不依赖事件 spellID
        spellID = resolvedSpellID,
        inferred = inferred,
        confidence = confidence,
        mapping = mapping and mapping.entry or nil,
        timestamp = now,
    }

    EmitResolved(payload)
end

function Infer:OnSpellcastStop(unit, _castGUID, _spellID)
    local db = DB()
    if db.enabled == false then return end
    if not self._active then return end
    if not IsBossUnit(unit) then return end
    local rec = ConsumePending(unit, nil)
    if rec and db.debug then
        DebugPrint("cast stop cleanup, unit=" .. tostring(unit))
    end
end

function Infer:GetRecentHistory()
    return self._history
end

function Infer:AddMapping(encounterID, mapping)
    encounterID = tonumber(encounterID)
    if not encounterID or type(mapping) ~= "table" then
        return false
    end
    local spellID = tonumber(mapping.spellID)
    local castTime = tonumber(mapping.castTime)
    if not spellID or not castTime then
        return false
    end

    local db = DB()
    db.mappings[encounterID] = db.mappings[encounterID] or {}
    table.insert(db.mappings[encounterID], {
        spellID = spellID,
        castTime = castTime,
        tolerance = tonumber(mapping.tolerance) or db.tolerance,
        bossUnit = mapping.bossUnit,
        note = mapping.note,
    })
    return true
end

if not Infer._frame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "boss1", "boss2", "boss3", "boss4", "boss5")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "boss1", "boss2", "boss3", "boss4", "boss5")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "boss2", "boss3", "boss4", "boss5")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "boss1", "boss2", "boss3", "boss4", "boss5")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            local encounterID = ...
            Infer:OnEncounterStart(encounterID)
        elseif event == "ENCOUNTER_END" then
            Infer:OnEncounterEnd()
        elseif event == "UNIT_SPELLCAST_START" then
            local unit, _castGUID, spellID = ...
            Infer:OnSpellcastStart(unit, _castGUID, spellID)
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local unit, _castGUID, spellID = ...
            Infer:OnSpellcastStop(unit, _castGUID, spellID)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _castGUID, spellID = ...
            Infer:OnSpellcastSucceeded(unit, _castGUID, spellID)
        end
    end)
    Infer._frame = frame
end
