---@diagnostic disable: undefined-global, undefined-field, need-check-nil

ExBoss = ExBoss or {}
ExBoss.Condition = ExBoss.Condition or {}
ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local Runtime = ExBoss.Condition.Runtime or {}
ExBoss.Condition.Runtime = Runtime

local frame = CreateFrame("Frame")
Runtime._ringShown = false
Runtime._lastMatch = nil
Runtime._latchedMatch = nil
Runtime._debugState = nil
Runtime._shownCastKind = nil
Runtime._shownEventID = nil
Runtime._scanDebugSerial = 0

local CAST_MATCH_EVENT_BLACKLIST = {
    [293] = true,
}

local function IsCastBarDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true
end

local function DebugPrint(msg)
    if not IsCastBarDebugEnabled() then
        return
    end
    if ExBoss and ExBoss.Print and ExBoss.Print.Say then
        ExBoss.Print.Say("[CastBarDebug] " .. tostring(msg or ""))
    else
        print("|cff00ffff<EXBOSS>|r [CastBarDebug] " .. tostring(msg or ""))
    end
end

local function ClearDisplayLock(reason)
    Runtime._ringShown = false
    Runtime._shownCastKind = nil
    Runtime._shownEventID = nil
    Runtime._lastMatch = nil
    if reason then
        DebugPrint("ClearDisplayLock reason=" .. tostring(reason))
    end
end

local function GlobalDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.conditions = ExBossDB.conditions or {}
    if ExBossDB.conditions.enabled == nil then
        ExBossDB.conditions.enabled = true
    end
    return ExBossDB.conditions
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function GetEventConfigRoot(eventID, createIfMissing)
    local bossCfg = GetBossConfig()
    if bossCfg and type(bossCfg.GetOverrideRootForEvent) == "function" then
        local root = bossCfg:GetOverrideRootForEvent(eventID, createIfMissing == true)
        if type(root) == "table" then
            return root
        end
    end
    return nil
end

local function EnsureCastWindowRule(eventID)
    local root = GetEventConfigRoot(eventID, true)
    if type(root) ~= "table" then
        return nil
    end
    root[eventID] = root[eventID] or {}
    root[eventID].rules = root[eventID].rules or {}
    root[eventID].rules.castWindow = root[eventID].rules.castWindow or {
        enabled = false,
        windowBefore = 1,
        windowAfter = 2,
        ringEnabled = true,
        castCheckEnabled = false,
    }
    return root[eventID].rules.castWindow
end

local function GetCastWindowRule(timer, eventID)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true then
        return {
            enabled = false,
            ringEnabled = false,
            castBarEnabled = false,
            windowBefore = 1,
            windowAfter = 2,
        }
    end
    local ringEnabled = (timer.ringEnabled == true)
    local castBarEnabled = (timer.castProgressBarEnabled == true)
    return {
        enabled = (ringEnabled or castBarEnabled),
        ringEnabled = ringEnabled,
        castBarEnabled = castBarEnabled,
        castCheckEnabled = (timer.ringCastCheckEnabled == true),
        windowBefore = tonumber(timer.ringWindowBefore) or 1,
        windowAfter = tonumber(timer.ringWindowAfter) or 2,
    }
end

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function SetDebugState(_text)
    Runtime._debugState = _text
    if type(_text) == "string" and _text ~= "" then
        DebugPrint("Runtime " .. _text)
    end
end

local function IsDisplayModuleEnabled(moduleKey, fallbackEnabled)
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, moduleKey, { enabled = fallbackEnabled == true })
        if ok and type(mdb) == "table" then
            db = mdb
        end
    end
    if type(db) ~= "table" then
        if moduleKey == "ExBoss.RingProgress" then
            db = ExBossDB and ExBossDB.timer and ExBossDB.timer.ringProgress or nil
        elseif moduleKey == "ExBoss.CastProgressBar" then
            db = ExBossDB and ExBossDB.timer and ExBossDB.timer.castProgressBar or nil
        end
    end
    if type(db) ~= "table" or db.enabled == nil then
        return fallbackEnabled == true
    end
    return db.enabled == true
end

local function BuildRingPlan(timer, eventID, castKind)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true or (timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true) then
        return nil
    end

    if castKind == "channel" then
        local duration = tonumber(timer.ringChannelDuration)
        if duration and duration > 0 then
            return {
                {
                    duration = duration,
                    castKind = "channel",
                    displayName = timer.displayName or timer.baseDisplayName,
                    castBarRenameEnabled = timer.castProgressBarRenameEnabled == true,
                    castBarRenameText = tostring(timer.castProgressBarRenameText or ""),
                    spellID = timer.spellID or timer.spellIdentifier,
                    iconFileID = timer.iconFileID,
                },
            }
        end
        return nil
    end

    local plan = timer.ringPlan
    if type(plan) ~= "table" or #plan == 0 then
        return nil
    end

    local out = {}
    for i = 1, #plan do
        local phase = plan[i]
        local duration = tonumber(type(phase) == "table" and phase.duration or nil)
        local phaseKind = tostring(type(phase) == "table" and phase.castKind or "")
        if duration and duration > 0 and (phaseKind == "cast" or phaseKind == "channel") then
            out[#out + 1] = {
                duration = duration,
                castKind = phaseKind,
                displayName = timer.displayName or timer.baseDisplayName,
                castBarRenameEnabled = timer.castProgressBarRenameEnabled == true,
                castBarRenameText = tostring(timer.castProgressBarRenameText or ""),
                spellID = timer.spellID or timer.spellIdentifier,
                iconFileID = timer.iconFileID,
            }
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

local function FindBestMatch(now, bossCast)
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if type(scheduler) ~= "table" then
        return nil, { "scheduler=nil" }
    end

    local best = nil
    local debugLines = {}
    local function ConsiderTimer(timer)
        local eventID = tonumber(timer and timer.eventID)
            or tonumber(timer and timer.timelineEventID)
            or tonumber(timer and timer.skillDef and timer.skillDef.eventID)
        if not eventID then
            debugLines[#debugLines + 1] = "candidate event=nil"
            return
        end
        if CAST_MATCH_EVENT_BLACKLIST[eventID] == true then
            debugLines[#debugLines + 1] = string.format("candidate event=%s blacklisted-from-cast-match", tostring(eventID))
            return
        end
        local rule = GetCastWindowRule(timer, eventID)
        if type(rule) ~= "table" then
            debugLines[#debugLines + 1] = string.format("candidate event=%s no-rule", tostring(eventID))
            return
        end
        if rule.enabled ~= true or (rule.ringEnabled ~= true and rule.castBarEnabled ~= true) then
            debugLines[#debugLines + 1] = string.format(
                "candidate event=%s disabled enabled=%s ringEnabled=%s castBarEnabled=%s",
                tostring(eventID),
                tostring(rule.enabled),
                tostring(rule.ringEnabled),
                tostring(rule.castBarEnabled)
            )
            return
        end
        local requiredUnit = type(timer.castStartUnit) == "string" and timer.castStartUnit or nil
        if requiredUnit and requiredUnit ~= "" and requiredUnit ~= tostring(bossCast and bossCast.unit or ""):lower() then
            debugLines[#debugLines + 1] = string.format(
                "candidate event=%s unit-filter required=%s actual=%s status=skip",
                tostring(eventID),
                tostring(requiredUnit),
                tostring(bossCast and bossCast.unit or "")
            )
            return
        end
        local before = math.max(0, SafeNum(rule.windowBefore, 1))
        local after = math.max(0, SafeNum(rule.windowAfter, 2))
        local castTime = SafeNum(timer.firedAt, nil) or SafeNum(timer.castTime, nil)
        if not castTime then
            debugLines[#debugLines + 1] = string.format("candidate event=%s no-castTime", tostring(eventID))
            return
        end
        local delta = now - castTime
        local status = "inside"
        if delta < -before then
            status = "too_early"
        elseif delta > after then
            status = "too_late"
        end
        debugLines[#debugLines + 1] = string.format(
            "candidate event=%s kind=%s castTime=%.2f delta=%.2f window=[-%.2f,+%.2f] status=%s",
            tostring(eventID),
            tostring(bossCast and bossCast.castKind or "?"),
            tonumber(castTime) or 0,
            tonumber(delta) or 0,
            tonumber(before) or 0,
            tonumber(after) or 0,
            status
        )
        if delta >= -before and delta <= after then
            local dist = math.abs(delta)
            if not best or dist < best.distance then
                best = {
                    eventID = eventID,
                    timer = timer,
                    rule = rule,
                    bossCast = bossCast,
                    distance = dist,
                    delta = delta,
                }
            end
        end
    end

    local timers = scheduler.GetActiveTimers and scheduler:GetActiveTimers() or scheduler._active
    if type(timers) == "table" then
        for _, timer in pairs(timers) do
            ConsiderTimer(timer)
        end
    end

    local lastFired = scheduler._lastFired
    if type(lastFired) == "table" then
        for i = 1, #lastFired do
            ConsiderTimer(lastFired[i])
        end
    end
    if best then
        debugLines[#debugLines + 1] = string.format(
            "selected event=%s delta=%.2f dist=%.2f verdict=inside-window",
            tostring(best.eventID),
            tonumber(best.delta) or 0,
            tonumber(best.distance) or 0
        )
    else
        debugLines[#debugLines + 1] = "selected event=nil verdict=no-candidate-inside-window"
    end
    return best, debugLines
end

local function LatchMatch(match)
    Runtime._latchedMatch = nil
end

local function IsBossUnit(unit)
    if type(unit) ~= "string" then
        return false
    end
    return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
end

local function ShowRingForMatch(match)
    DebugPrint(string.format(
        "ShowMatch event=%s ringEnabled=%s castBarEnabled=%s timer.useRingProgress=%s",
        tostring(match and match.eventID or "nil"),
        tostring(match and match.timer and match.timer.ringEnabled == true),
        tostring(match and match.timer and match.timer.castProgressBarEnabled == true),
        tostring(match and match.timer and match.timer.useRingProgress == true)
    ))
    local ring = match.timer and match.timer.ringEnabled == true and IsDisplayModuleEnabled("ExBoss.RingProgress", true) and
    ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    local cast = match.bossCast
    local plan = BuildRingPlan(match.timer, match.eventID, cast.castKind)
    if type(plan) ~= "table" or #plan == 0 then
        SetDebugState(string.format("match-no-duration event=%s kind=%s", tostring(match.eventID or "?"),
            tostring(cast.castKind or "?")))
        return
    end

    DebugPrint(string.format(
        "ShowMatch planCount=%d ringObj=%s castBarObj=%s",
        #plan,
        tostring(ring ~= nil),
        "false"
    ))

    local shown = false
    if #plan > 1 and ring and ring.ShowSequence then
        ring:ShowSequence(plan, {
            castCheckEnabled = match.rule and match.rule.castCheckEnabled == true,
        })
        shown = true
    elseif #plan == 1 and ring and ring.ShowEntry then
        local firstPhase = plan[1]
        ring:ShowEntry({
            duration = tonumber(firstPhase and firstPhase.duration),
            endTime = GetTime() + (tonumber(firstPhase and firstPhase.duration) or 0),
            castKind = tostring(firstPhase and firstPhase.castKind or cast.castKind),
            castCheckEnabled = match.rule and match.rule.castCheckEnabled == true,
        })
        shown = true
    end

    if shown then
        Runtime._ringShown = true
        Runtime._shownCastKind = #plan > 1 and "sequence" or tostring(plan[1] and plan[1].castKind or cast.castKind)
        Runtime._shownEventID = match.eventID
        Runtime._lastMatch = {
            eventID = match.eventID,
            eventName = match.timer and match.timer.displayName,
            castName = nil,
            castRemaining = nil,
            delta = match.delta,
        }
        return
    end
end

local function HideRingIfOwned()
    if Runtime._ringShown then
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress
        if ring and ring.Hide then
            ring:Hide()
        end
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar
        if castBar and castBar.Hide then
            castBar:Hide()
        end
        Runtime._ringShown = false
    end
    ClearDisplayLock("hide-owned")
end

local function ClearLatchedMatch()
    Runtime._latchedMatch = nil
end

local function HandleSpellEvent(unit, castKind)
    local gdb = GlobalDB()
    if gdb.enabled == false then
        ClearLatchedMatch()
        HideRingIfOwned()
        return
    end

    if not IsBossUnit(unit) then
        DebugPrint(string.format("HandleSpellEvent ignored non-boss unit=%s kind=%s", tostring(unit), tostring(castKind)))
        return
    end

    DebugPrint(string.format("HandleSpellEvent unit=%s kind=%s", tostring(unit), tostring(castKind)))

    local bossCast = {
        unit = unit,
        castKind = castKind,
    }
    local now = GetTime()
    local match = FindBestMatch(now, bossCast)
    if IsCastBarDebugEnabled() then
        local _, debugLines = FindBestMatch(now, bossCast)
        if type(debugLines) == "table" then
            for i = 1, #debugLines do
                DebugPrint(debugLines[i])
            end
        end
    end
    if match then
        if Runtime._ringShown and Runtime._shownEventID == match.eventID and Runtime._shownCastKind == castKind then
            SetDebugState(string.format("duplicate-ignore event=%s kind=%s", tostring(match.eventID or "?"),
                tostring(castKind or "?")))
            return
        end
        SetDebugState(string.format("match event=%s kind=%s delta=%.2f", tostring(match.eventID or "?"),
            tostring(castKind or "?"), tonumber(match.delta) or 0))
        LatchMatch(match)
        Runtime._latchedMatch = {
            eventID = match.eventID,
            eventName = match.timer and match.timer.displayName,
            delta = match.delta,
        }
        ShowRingForMatch(match)
        return
    end

    SetDebugState(string.format("cast-no-match kind=%s", tostring(castKind or "?")))
end

function Runtime:GetLastMatch()
    return self._lastMatch
end

function Runtime:GetOrCreateRule(eventID)
    eventID = tonumber(eventID)
    if not eventID then
        return nil
    end
    return EnsureCastWindowRule(eventID)
end

frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "boss1", "boss2", "boss3", "boss4", "boss5")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_SPELLCAST_START" then
        HandleSpellEvent(unit, "cast")
        return
    end
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        HandleSpellEvent(unit, "channel")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ENCOUNTER_END" then
        ClearLatchedMatch()
        HideRingIfOwned()
        SetDebugState("")
    end
end)
