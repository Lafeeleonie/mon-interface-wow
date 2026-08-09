---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.TargetAlert = ExBoss.TargetAlert or {}

local Runtime = ExBoss.TargetAlert
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local PlaySoundFile = _G.PlaySoundFile
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local OWNER = "ExBoss.TargetAlert.Runtime"
local BOSS_CAST_START_EVENT = "EXBOSS_BOSS_OBSERVED_CAST_START"
local BOSS_CAST_STOP_EVENT = "EXBOSS_BOSS_OBSERVED_CAST_STOP"
local TRASH_CAST_START_EVENT = "EXBOSS_TRASH_OBSERVED_CAST_START"
local TRASH_VOICE_START_EVENT = "EXBOSS_TRASH_CAST_START_VOICE_TRIGGERED"
local TRASH_CAST_STOP_EVENT = "EXBOSS_TRASH_CASTBAR_STOP"
local FIXED_AI_EVENT_FINISHED_EVENT = "EXBOSS_FIXED_AI_EVENT_FINISHED"
local TARGET_ALERT_TRIGGERED_EVENT = "EXBOSS_TARGET_ALERT_TRIGGERED"
local TARGET_ALERT_A_DELAY = 0.10

Runtime._bossRules = Runtime._bossRules or {}
Runtime._trashRules = Runtime._trashRules or {}
Runtime._pending = Runtime._pending or {}
Runtime._pendingNextID = tonumber(Runtime._pendingNextID) or 1
Runtime._generation = tonumber(Runtime._generation) or 1
Runtime._fired = Runtime._fired or {}
Runtime._displayKeys = Runtime._displayKeys or {}
Runtime._encounterWarningRevision = tonumber(Runtime._encounterWarningRevision) or 0
Runtime._encounterWarningLastAt = tonumber(Runtime._encounterWarningLastAt) or 0

local function IsTargetAlertDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TargetAlert and ExBoss.Debug.TargetAlert.enabled == true
end

local function TargetAlertDebug(msg)
    if not IsTargetAlertDebugEnabled() then
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffExBoss TargetAlert|r " .. tostring(msg or ""))
    end
end

local function NormalizeMode(value)
    local mode = tostring(value or "A"):upper()
    if mode == "TARGET_TOKEN" then
        return "A"
    end
    if mode == "PLAYER_DEBUFF_DELTA" then
        return "B"
    end
    if mode == "ENCOUNTER_WARNING" or mode == "WARNING_DELTA" then
        return "C"
    end
    if mode == "EITHER" then
        return "A_OR_B"
    end
    if mode ~= "A" and mode ~= "B" and mode ~= "C" and mode ~= "A_OR_B" then
        mode = "A"
    end
    return mode
end

local function NormalizeAnchor(value)
    local anchor = tostring(value or "cast_start"):lower()
    if anchor ~= "cast_start" and anchor ~= "cast_end" then
        anchor = "cast_start"
    end
    return anchor
end

local function NormalizeWarningAnchor(value)
    local anchor = tostring(value or "cast_start"):lower()
    if anchor ~= "cast_start" and anchor ~= "cast_end" and anchor ~= "scheduler_finish" then
        anchor = "cast_start"
    end
    return anchor
end

local function NormalizeWindow(value)
    local window = tonumber(value)
    if not window then
        return 0.10
    end
    if window < 0.01 then
        return 0.01
    end
    if window > 1.00 then
        return 1.00
    end
    return window
end

local function NormalizeSeconds(value, defaultValue, maxValue)
    local seconds = tonumber(value)
    if not seconds then
        return tonumber(defaultValue) or 0
    end
    if seconds < 0 then
        return 0
    end
    local cap = tonumber(maxValue) or 10.0
    if seconds > cap then
        return cap
    end
    return seconds
end

local function ResolveDebuffTiming(rule)
    if type(rule) ~= "table" then
        return 0, 0.10
    end
    if rule.debuffDelay ~= nil then
        return 0, NormalizeSeconds(rule.debuffDelay, 0.10, 10.0)
    end
    local beforeWindow = NormalizeSeconds(rule.debuffWindowBefore, 0, 10.0)
    local afterWindow = rule.debuffWindowAfter
    if afterWindow == nil and rule.debuffWindow ~= nil then
        afterWindow = NormalizeWindow(rule.debuffWindow)
    end
    afterWindow = NormalizeSeconds(afterWindow, 0.10, 10.0)
    return beforeWindow, afterWindow
end

local function ResolveWarningTiming(rule)
    if type(rule) ~= "table" then
        return 0, 0.75
    end
    if rule.warningDelay ~= nil then
        return 0, NormalizeSeconds(rule.warningDelay, 0.75, 10.0)
    end
    local beforeWindow = rule.warningWindowBefore
    if beforeWindow == nil then
        beforeWindow = rule.debuffWindowBefore
    end
    beforeWindow = NormalizeSeconds(beforeWindow, 0, 10.0)
    local afterWindow = rule.warningWindowAfter
    if afterWindow == nil then
        afterWindow = rule.warningWindow
    end
    if afterWindow == nil then
        afterWindow = rule.debuffWindowAfter
    end
    if afterWindow == nil and rule.debuffWindow ~= nil then
        afterWindow = NormalizeWindow(rule.debuffWindow)
    end
    afterWindow = NormalizeSeconds(afterWindow, 0.75, 10.0)
    return beforeWindow, afterWindow
end

local function GetRuleBucket(encounterID, eventID, createIfMissing)
    local eventKey = tonumber(eventID)
    if not eventKey then
        return nil
    end
    local eid = tonumber(encounterID)
    local scopeKey = eid or "__any"
    if createIfMissing then
        Runtime._bossRules[scopeKey] = Runtime._bossRules[scopeKey] or {}
        Runtime._bossRules[scopeKey][eventKey] = Runtime._bossRules[scopeKey][eventKey] or {}
    end
    return Runtime._bossRules[scopeKey] and Runtime._bossRules[scopeKey][eventKey] or nil
end

local function GetMatchingRules(payload)
    local encounterID = tonumber(type(payload) == "table" and payload.encounterID or nil)
    local eventID = tonumber(type(payload) == "table" and payload.eventID or nil)
    local bucket = GetRuleBucket(encounterID, eventID, false)
    local anyBucket = GetRuleBucket(nil, eventID, false)
    local specificCount = type(bucket) == "table" and #bucket or 0
    local anyCount = type(anyBucket) == "table" and #anyBucket or 0
    if specificCount == 0 and anyCount == 0 then
        return nil
    end
    if anyCount == 0 then
        return bucket
    end
    if specificCount == 0 then
        return anyBucket
    end
    local merged = {}
    for i = 1, specificCount do
        merged[#merged + 1] = bucket[i]
    end
    for i = 1, anyCount do
        merged[#merged + 1] = anyBucket[i]
    end
    return merged
end

local function BuildFireKey(rule, payload)
    return table.concat({
        tostring(rule and rule.key or "rule"),
        tostring(type(payload) == "table" and (payload.runtimeID or payload.runtimeKey) or 0),
        tostring(type(payload) == "table" and payload.castKind or ""),
        tostring(type(payload) == "table" and payload.castBarID or 0),
    }, ":")
end

local function BuildDisplayKey(rule, payload)
    return "targetalert:" .. BuildFireKey(rule, payload)
end

local function ResolveDisplayText(rule, payload)
    local custom = tostring(type(rule) == "table" and rule.placeholderText or "")
    if custom ~= "" then
        return custom
    end
    local displayName = tostring(type(payload) == "table" and payload.displayName or "")
    if displayName ~= "" then
        return displayName .. " " .. L["点你"]
    end
    return L["被点名"]
end

local function ResolveCountdownText(rule, payload)
    local custom = tostring(type(rule) == "table" and rule.placeholderText or "")
    if custom ~= "" then
        return custom
    end
    local displayName = tostring(type(payload) == "table" and payload.displayName or "")
    if displayName ~= "" then
        return displayName
    end
    return ResolveDisplayText(rule, payload)
end

local function ClonePayloadWithMatchAt(payload, matchAt)
    if type(payload) ~= "table" then
        return {
            _matchAt = tonumber(matchAt) or nil,
        }
    end
    local copy = {}
    for key, value in pairs(payload) do
        copy[key] = value
    end
    copy._matchAt = tonumber(matchAt) or nil
    return copy
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        out[DeepCopy(key)] = DeepCopy(item)
    end
    return out
end

local _encounterEventIndexCache = nil
local _encounterEventIndexSource = nil

local function BuildEncounterEventIndex()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if _encounterEventIndexCache and _encounterEventIndexSource == data then
        return _encounterEventIndexCache
    end
    local out = {}
    if type(data) == "table" and type(data.maps) == "table" then
        for _, mapRow in pairs(data.maps) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for rawEventID, eventRow in pairs(bossRow.events) do
                            local eid = tonumber(rawEventID) or
                                (type(eventRow) == "table" and tonumber(eventRow.eventID))
                            if eid and type(eventRow) == "table" then
                                out[eid] = eventRow
                            end
                        end
                    end
                end
            end
        end
    end
    _encounterEventIndexCache = out
    _encounterEventIndexSource = data
    return out
end

local function BuildEncounterEventPlanByID(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local row = BuildEncounterEventIndex()[eid]
    if type(row) ~= "table" then
        return nil
    end
    local castDuration = tonumber(row.castDuration)
    local channelDuration = tonumber(row.channelDuration)
    local plan = {}
    local totalDuration = 0
    if castDuration and castDuration > 0.05 then
        plan[#plan + 1] = {
            duration = castDuration,
            castKind = "cast",
        }
        totalDuration = totalDuration + castDuration
    end
    if channelDuration and channelDuration > 0.05 then
        plan[#plan + 1] = {
            duration = channelDuration,
            castKind = "channel",
        }
        totalDuration = totalDuration + channelDuration
    end
    if #plan == 0 then
        return nil
    end
    return {
        plan = plan,
        totalDuration = totalDuration,
    }
end

local function GetEncounterEventDurationByID(eventID)
    local timing = BuildEncounterEventPlanByID(eventID)
    if type(timing) ~= "table" then
        return nil
    end
    local totalDuration = tonumber(timing.totalDuration)
    if totalDuration and totalDuration > 0.05 then
        return totalDuration
    end
    return nil
end

local function GetEncounterEventPlanByID(eventID)
    local timing = BuildEncounterEventPlanByID(eventID)
    if type(timing) ~= "table" or type(timing.plan) ~= "table" or #timing.plan == 0 then
        return nil
    end
    return DeepCopy(timing.plan)
end

local function GetTrashSpellRow(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local mapID = tonumber(payload.mapID)
    local npcID = tonumber(payload.npcID)
    local spellID = tonumber(payload.spellID)
    if not (mapID and npcID and spellID) then
        return nil
    end
    local root = rawget(_G, "EXBOSS_TRASH_CD_DATA")
    local mapRow = type(root) == "table" and root[mapID] or nil
    local mobRow = type(mapRow) == "table" and type(mapRow.mobs) == "table" and mapRow.mobs[npcID] or nil
    local spellRow = type(mobRow) == "table" and type(mobRow.spells) == "table" and mobRow.spells[spellID] or nil
    if type(spellRow) ~= "table" then
        return nil
    end
    return spellRow
end

local function BuildTrashSpellPlan(payload)
    local row = GetTrashSpellRow(payload)
    if type(row) ~= "table" then
        return nil
    end
    local castDuration = tonumber(row.castTime) or tonumber(row.castDuration)
    local channelDuration = tonumber(row.channelTime) or tonumber(row.channelDuration)
    local plan = {}
    local totalDuration = 0
    if castDuration and castDuration > 0.05 then
        plan[#plan + 1] = {
            duration = castDuration,
            castKind = "cast",
        }
        totalDuration = totalDuration + castDuration
    end
    if channelDuration and channelDuration > 0.05 then
        plan[#plan + 1] = {
            duration = channelDuration,
            castKind = "channel",
        }
        totalDuration = totalDuration + channelDuration
    end
    if #plan == 0 then
        return nil
    end
    return {
        plan = plan,
        totalDuration = totalDuration,
    }
end

local function GetTrashSpellDuration(payload)
    local timing = BuildTrashSpellPlan(payload)
    if type(timing) ~= "table" then
        return nil
    end
    local totalDuration = tonumber(timing.totalDuration)
    if totalDuration and totalDuration > 0.05 then
        return totalDuration
    end
    return nil
end

local function GetTrashSpellPlan(payload)
    local timing = BuildTrashSpellPlan(payload)
    if type(timing) ~= "table" or type(timing.plan) ~= "table" or #timing.plan == 0 then
        return nil
    end
    return DeepCopy(timing.plan)
end

local function ResolveDisplayDuration(rule, payload)
    local configuredDuration = tonumber(type(rule) == "table" and rule.displayDuration or nil)
    if configuredDuration and configuredDuration > 0.05 then
        local matchAt = tonumber(type(payload) == "table" and payload._matchAt or nil)
        if matchAt and matchAt > 0 then
            return math.max(0, configuredDuration - math.max(0, (GetTime and GetTime() or 0) - matchAt))
        end
        return configuredDuration
    end
    local trashDuration = GetTrashSpellDuration(payload)
    if trashDuration and trashDuration > 0.05 then
        return trashDuration
    end
    local encounterDuration = GetEncounterEventDurationByID(type(payload) == "table" and payload.eventID or nil)
    if encounterDuration and encounterDuration > 0.05 then
        return encounterDuration
    end
    local totalDuration = tonumber(type(payload) == "table" and payload.totalDuration or nil)
    if totalDuration and totalDuration > 0.05 then
        return totalDuration
    end
    return nil
end

local function IsRingProgressGloballyEnabled()
    local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if not (Ring and type(Ring.ShowEntry) == "function") then
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

local function ShowRuleRing(rule, payload)
    if not (type(rule) == "table" and rule.ringEnabled == true and IsRingProgressGloballyEnabled()) then
        return false
    end
    local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if not (Ring and type(Ring.ShowEntry) == "function") then
        return false
    end
    local configuredDuration = tonumber(type(rule) == "table" and rule.displayDuration or nil)
    local matchAt = tonumber(type(payload) == "table" and payload._matchAt or nil)
    local phasePlan = GetTrashSpellPlan(payload) or
        GetEncounterEventPlanByID(type(payload) == "table" and payload.eventID or nil)
    if configuredDuration and configuredDuration > 0.05 then
        local remaining = ResolveDisplayDuration(rule, payload)
        if not remaining or remaining <= 0.05 then
            return false
        end
        local totalDuration = configuredDuration
        local endAt = matchAt and (matchAt + totalDuration) or ((GetTime and GetTime() or 0) + remaining)
        Ring:ShowEntry({
            duration = totalDuration,
            endTime = endAt,
            castKind = "cast",
            castCheckEnabled = false,
            displayName = ResolveCountdownText(rule, payload),
            progressDisplayName = ResolveCountdownText(rule, payload),
            spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
            owner = {
                source = "targetalert",
                earlyStopEnabled = true,
                eventID = tonumber(type(payload) == "table" and payload.eventID or nil),
                spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
                ruleKey = tostring(rule.key or ""),
            },
        })
        return true
    end
    if type(phasePlan) == "table" and #phasePlan > 0 then
        for i = 1, #phasePlan do
            local phase = phasePlan[i]
            if type(phase) == "table" then
                phase.displayName = ResolveCountdownText(rule, payload)
                phase.progressDisplayName = ResolveCountdownText(rule, payload)
                phase.spellID = tonumber(type(payload) == "table" and payload.spellID or nil)
                phase.castCheckEnabled = false
            end
        end
        if #phasePlan > 1 and type(Ring.ShowSequence) == "function" then
            Ring:ShowSequence(phasePlan, {
                castCheckEnabled = false,
                owner = {
                    source = "targetalert",
                    earlyStopEnabled = true,
                    eventID = tonumber(type(payload) == "table" and payload.eventID or nil),
                    spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
                    ruleKey = tostring(rule.key or ""),
                },
            })
            return true
        end
        local phase = phasePlan[1]
        Ring:ShowEntry({
            duration = tonumber(phase.duration) or 0,
            endTime = (GetTime and GetTime() or 0) + (tonumber(phase.duration) or 0),
            castKind = tostring(phase.castKind or "cast"),
            castCheckEnabled = false,
            displayName = ResolveCountdownText(rule, payload),
            progressDisplayName = ResolveCountdownText(rule, payload),
            spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
            owner = {
                source = "targetalert",
                earlyStopEnabled = true,
                eventID = tonumber(type(payload) == "table" and payload.eventID or nil),
                spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
                ruleKey = tostring(rule.key or ""),
            },
        })
        return true
    end
    local remaining = ResolveDisplayDuration(rule, payload)
    if (not remaining or remaining <= 0.05) and (not configuredDuration or configuredDuration <= 0.05) then
        return false
    end
    local totalDuration = configuredDuration and configuredDuration > 0.05 and configuredDuration or remaining
    local endAt = matchAt and totalDuration and (matchAt + totalDuration) or
        ((GetTime and GetTime() or 0) + (remaining or totalDuration))
    Ring:ShowEntry({
        duration = totalDuration,
        endTime = endAt,
        castKind = "cast",
        castCheckEnabled = false,
        displayName = ResolveCountdownText(rule, payload),
        progressDisplayName = ResolveCountdownText(rule, payload),
        spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
        owner = {
            source = "targetalert",
            earlyStopEnabled = true,
            eventID = tonumber(type(payload) == "table" and payload.eventID or nil),
            spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
            ruleKey = tostring(rule.key or ""),
        },
    })
    return true
end

local function IsIconAlertGloballyEnabled()
    local Icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
    if not (Icon and type(Icon.ShowEntry) == "function") then
        return false
    end
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, "ExBoss.IconAlert", { enabled = true })
        if ok and type(mdb) == "table" then
            db = mdb
        end
    end
    if type(db) ~= "table" then
        db = ExBossDB and ExBossDB.timer and ExBossDB.timer.iconAlert or nil
    end
    return type(db) == "table" and db.enabled == true
end

local function ShowRuleIcon(rule, payload)
    local ruleIconEnabled = type(rule) == "table" and rule.iconEnabled == true
    local globalIconEnabled = IsIconAlertGloballyEnabled()
    if not (ruleIconEnabled and globalIconEnabled) then
        TargetAlertDebug(string.format(
            "icon-skip key=%s ruleIcon=%s globalIcon=%s event=%s spell=%s unit=%s",
            tostring(type(rule) == "table" and rule.key or "?"),
            tostring(ruleIconEnabled),
            tostring(globalIconEnabled),
            tostring(type(payload) == "table" and payload.eventID or "nil"),
            tostring(type(payload) == "table" and payload.spellID or "nil"),
            tostring(type(payload) == "table" and payload.unit or "?")
        ))
        return false
    end
    local Icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
    if not (Icon and type(Icon.ShowEntry) == "function") then
        TargetAlertDebug(string.format(
            "icon-skip-api key=%s event=%s spell=%s unit=%s",
            tostring(type(rule) == "table" and rule.key or "?"),
            tostring(type(payload) == "table" and payload.eventID or "nil"),
            tostring(type(payload) == "table" and payload.spellID or "nil"),
            tostring(type(payload) == "table" and payload.unit or "?")
        ))
        return false
    end
    local remaining = ResolveDisplayDuration(rule, payload)
    local configuredDuration = tonumber(type(rule) == "table" and rule.displayDuration or nil)
    if (not remaining or remaining <= 0.05) and (not configuredDuration or configuredDuration <= 0.05) then
        TargetAlertDebug(string.format(
            "icon-skip-duration key=%s remaining=%s configured=%s event=%s spell=%s unit=%s",
            tostring(type(rule) == "table" and rule.key or "?"),
            tostring(remaining),
            tostring(configuredDuration),
            tostring(type(payload) == "table" and payload.eventID or "nil"),
            tostring(type(payload) == "table" and payload.spellID or "nil"),
            tostring(type(payload) == "table" and payload.unit or "?")
        ))
        return false
    end
    local totalDuration = configuredDuration and configuredDuration > 0.05 and configuredDuration or remaining
    local matchAt = tonumber(type(payload) == "table" and payload._matchAt or nil)
    local endAt = matchAt and totalDuration and (matchAt + totalDuration) or
        ((GetTime and GetTime() or 0) + (remaining or totalDuration))
    local state = ExwindTools and ExwindTools.State or nil
    local shadowmeldAvailable = type(state) == "table" and state.ShadowmeldAvailable == true
    local shadowmeldOnCooldown = type(state) == "table" and state.ShadowmeldCD == true
    local shadowmeldEnabled = type(rule) == "table" and rule.stealthEnabled == true
    if shadowmeldEnabled and shadowmeldAvailable and not shadowmeldOnCooldown then
        Icon:ShowEntry({
            duration = totalDuration,
            endTime = endAt,
            text = " ",
            icon = 132089,
            hideCooldown = true,
            hideCountdownNumbers = true,
            owner = {
                key = tostring(rule.key or "targetalert") .. ":stealth",
            },
        })
    end
    local key = Icon:ShowEntry({
        duration = totalDuration,
        endTime = endAt,
        displayName = ResolveCountdownText(rule, payload),
        spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
        owner = {
            source = "targetalert",
            eventID = tonumber(type(payload) == "table" and payload.eventID or nil),
            spellID = tonumber(type(payload) == "table" and payload.spellID or nil),
            ruleKey = tostring(rule.key or ""),
            castBarID = tonumber(type(payload) == "table" and payload.castBarID or nil),
        },
    })
    TargetAlertDebug(string.format(
        "icon-show key=%s result=%s duration=%s event=%s spell=%s unit=%s",
        tostring(type(rule) == "table" and rule.key or "?"),
        tostring(key or "nil"),
        tostring(totalDuration),
        tostring(type(payload) == "table" and payload.eventID or "nil"),
        tostring(type(payload) == "table" and payload.spellID or "nil"),
        tostring(type(payload) == "table" and payload.unit or "?")
    ))
    return true
end

local function StopDisplayKey(displayKey)
    if tostring(displayKey or "") == "" then
        return
    end
    if ExBoss and type(ExBoss.StopFlashCountdown) == "function" then
        ExBoss:StopFlashCountdown(displayKey)
    end
end

local function StopRuntimeDisplays(runtimeID)
    local rid = tostring(runtimeID or "")
    if rid == "" then
        return
    end
    local keys = Runtime._displayKeys[rid]
    if type(keys) ~= "table" then
        return
    end
    for i = 1, #keys do
        StopDisplayKey(keys[i])
    end
    Runtime._displayKeys[rid] = nil
end

local function ResolveRuntimeToken(payload)
    if type(payload) ~= "table" then
        return ""
    end
    local token = payload.runtimeID or payload.runtimeKey or payload.runtime
    return tostring(token or "")
end

local function CancelPendingForRuntime(runtimeToken)
    local rid = tostring(runtimeToken or "")
    if rid == "" then
        return
    end
    for pendingID, current in pairs(Runtime._pending or {}) do
        if type(current) == "table" and tostring(current.runtimeToken or "") == rid then
            Runtime._pending[pendingID] = nil
        end
    end
end

local function PlayRuleSound(rule)
    local soundKey = tostring(type(rule) == "table" and rule.soundKey or "")
    if soundKey == "" or not (LSM and type(LSM.Fetch) == "function" and PlaySoundFile) then
        return false
    end
    local soundPath = LSM:Fetch("sound", soundKey, true)
    if type(soundPath) ~= "string" or soundPath == "" then
        return false
    end
    pcall(PlaySoundFile, soundPath, "Master")
    return true
end

local function SendTriggeredEvent(rule, payload, reason)
    if ExwindTools and type(ExwindTools.SendEvent) == "function" then
        ExwindTools:SendEvent(TARGET_ALERT_TRIGGERED_EVENT, {
            ruleKey = tostring(rule and rule.key or ""),
            source = tostring(payload and payload.source or ""),
            encounterID = tonumber(payload and payload.encounterID or nil),
            eventID = tonumber(payload and payload.eventID or nil),
            runtimeID = tonumber(payload and payload.runtimeID or nil),
            runtimeKey = tostring(payload and payload.runtimeKey or ""),
            mapID = tonumber(payload and payload.mapID or nil),
            npcID = tonumber(payload and payload.npcID or nil),
            spellID = tonumber(payload and payload.spellID or nil),
            displayName = tostring(payload and payload.displayName or ""),
            unit = tostring(payload and payload.unit or ""),
            castKind = tostring(payload and payload.castKind or ""),
            castBarID = tonumber(payload and payload.castBarID or nil),
            totalDuration = tonumber(payload and payload.totalDuration or nil),
            reason = tostring(reason or ""),
        })
    end
end

local function ShowPlaceholder(rule, payload, reason, fireKey)
    if type(rule) == "table" and rule.textEnabled == false then
        SendTriggeredEvent(rule, payload, reason)
        PlayRuleSound(rule)
        return
    end
    local text = ResolveDisplayText(rule, payload)
    local countdownText = ResolveCountdownText(rule, payload)
    local displayKey = BuildDisplayKey(rule, payload)
    local displayDuration = ResolveDisplayDuration(rule, payload)
    local configuredDuration = tonumber(type(rule) == "table" and rule.displayDuration or nil)
    local payloadDuration = tonumber(type(payload) == "table" and payload.totalDuration or nil)
    local totalDisplayDuration = nil
    if configuredDuration and configuredDuration > 0.05 then
        totalDisplayDuration = configuredDuration
    elseif payloadDuration and payloadDuration > 0.05 then
        totalDisplayDuration = payloadDuration
    end
    local matchAt = tonumber(type(payload) == "table" and payload._matchAt or nil)
    local displayEndAt = matchAt and totalDisplayDuration and (matchAt + totalDisplayDuration) or nil
    SendTriggeredEvent(rule, payload, reason)
    PlayRuleSound(rule)
    if displayDuration and ExBoss and type(ExBoss.FlashCountdown) == "function" then
        local runtimeID = tostring(type(payload) == "table" and (payload.runtimeID or payload.runtimeKey) or "")
        if runtimeID ~= "" then
            Runtime._displayKeys[runtimeID] = Runtime._displayKeys[runtimeID] or {}
            Runtime._displayKeys[runtimeID][#Runtime._displayKeys[runtimeID] + 1] = displayKey
        end
        ExBoss:FlashCountdown(countdownText, displayDuration, {
            key = displayKey,
            template = "{text} > {time}",
            channel = "central_medium",
            endAt = displayEndAt,
            noAnimation = true,
            tickDuration = 0.10,
        })
        return
    end
    if ExBoss and type(ExBoss.FlashText) == "function" then
        ExBoss:FlashText(text, 1.5, {
            channel = "central_medium",
            noAnimation = true,
        })
    end
end

local IsCurrentPlayerTank
local IsRuleAllowedForCurrentRole

local function TryFireRule(rule, payload, reason, matchAt)
    local fireKey = BuildFireKey(rule, payload)
    if Runtime._fired[fireKey] == true then
        TargetAlertDebug(string.format(
            "skip-fired key=%s reason=%s event=%s spell=%s unit=%s",
            tostring(rule and rule.key or "?"),
            tostring(reason or "?"),
            tostring(type(payload) == "table" and payload.eventID or "nil"),
            tostring(type(payload) == "table" and payload.spellID or "nil"),
            tostring(type(payload) == "table" and payload.unit or "?")
        ))
        return false
    end
    if not IsRuleAllowedForCurrentRole(rule) then
        TargetAlertDebug(string.format(
            "skip-role key=%s reason=%s role=%s tankEnabled=%s",
            tostring(rule and rule.key or "?"),
            tostring(reason or "?"),
            tostring(ExwindTools and ExwindTools.State and ExwindTools.State.RoleKey or "unknown"),
            tostring(type(rule) == "table" and rule.tankEnabled == true)
        ))
        return false
    end
    local effectivePayload = ClonePayloadWithMatchAt(payload, matchAt)
    if tostring(reason or "") == "A" and type(effectivePayload) == "table" then
        local directDuration = GetTrashSpellDuration(effectivePayload) or
            GetEncounterEventDurationByID(effectivePayload.eventID)
        TargetAlertDebug(string.format(
            "table-duration map=%s npc=%s event=%s spell=%s duration=%s",
            tostring(effectivePayload.mapID or "nil"),
            tostring(effectivePayload.npcID or "nil"),
            tostring(effectivePayload.eventID or "nil"),
            tostring(effectivePayload.spellID or "nil"),
            tostring(directDuration or "nil")
        ))
        if directDuration and directDuration > 0.05 then
            effectivePayload.totalDuration = directDuration
        end
    end
    Runtime._fired[fireKey] = true
    local firedDuration = nil
    if type(rule) == "table" and tonumber(rule.displayDuration) and tonumber(rule.displayDuration) > 0.05 then
        firedDuration = tonumber(rule.displayDuration)
    elseif type(effectivePayload) == "table" then
        firedDuration = tonumber(effectivePayload.totalDuration)
    end
    TargetAlertDebug(string.format(
        "fire key=%s reason=%s event=%s spell=%s unit=%s duration=%s matchAt=%s",
        tostring(rule and rule.key or "?"),
        tostring(reason or "?"),
        tostring(type(effectivePayload) == "table" and effectivePayload.eventID or "nil"),
        tostring(type(effectivePayload) == "table" and effectivePayload.spellID or "nil"),
        tostring(type(effectivePayload) == "table" and effectivePayload.unit or "?"),
        tostring(firedDuration or "nil"),
        tostring(matchAt or "nil")
    ))
    ShowPlaceholder(rule, effectivePayload, reason, fireKey)
    ShowRuleRing(rule, effectivePayload)
    ShowRuleIcon(rule, effectivePayload)
    return true
end

local function EvaluatePendingDebuffMatch(current, state)
    state = state or (ExwindTools and ExwindTools.State or nil)
    local currentRevision = tonumber(state and state.PlayerDebuffRevision or 0) or 0
    local currentCount = tonumber(state and state.PlayerDebuffCount or 0) or 0
    local lastAddedAt = tonumber(state and state.PlayerDebuffLastAddedAt or 0) or 0
    local lastAddedRevision = tonumber(state and state.PlayerDebuffLastAddedRevision or 0) or 0
    local matched = current.preMatched == true
    local matchAt = current.preMatched == true and tonumber(current.preMatchedAt) or nil

    if not matched
        and lastAddedRevision > current.anchorLastAddedRevision
        and lastAddedAt >= ((current.anchorAt or 0) - (current.beforeWindow or 0) - 0.02)
        and lastAddedAt <= ((current.anchorAt or 0) + (current.afterWindow or 0) + 0.05) then
        matched = true
        matchAt = lastAddedAt
    end

    return matched, matchAt, currentRevision, currentCount, lastAddedAt, lastAddedRevision
end

local function EvaluatePendingEncounterWarningMatch(current)
    local currentRevision = tonumber(Runtime._encounterWarningRevision) or 0
    local lastWarningAt = tonumber(Runtime._encounterWarningLastAt) or 0
    local lastWarningRevision = currentRevision
    local matched = current.preMatched == true
    local matchAt = current.preMatched == true and tonumber(current.preMatchedAt) or nil

    if not matched
        and lastWarningRevision > current.anchorLastWarningRevision
        and lastWarningAt >= ((current.anchorAt or 0) - (current.beforeWindow or 0) - 0.02)
        and lastWarningAt <= ((current.anchorAt or 0) + (current.afterWindow or 0) + 0.10) then
        matched = true
        matchAt = lastWarningAt
    end

    return matched, matchAt, currentRevision, lastWarningAt, lastWarningRevision
end

local function ResolveTargetToken(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local targetGUID = UnitGUID(unit .. "target")
    if not targetGUID or type(UnitTokenFromGUID) ~= "function" then
        return nil
    end
    return UnitTokenFromGUID(targetGUID)
end

local function GetTargetIdentity()
    return ExBoss and ExBoss.TargetIdentity or nil
end

local function BeginObservedTargetForPayload(payload, sourceTag)
    local targetIdentity = GetTargetIdentity()
    if not (targetIdentity and type(targetIdentity.BeginObservedCast) == "function") then
        return nil
    end
    if type(payload) ~= "table" then
        return nil
    end
    local unit = type(payload.unit) == "string" and payload.unit or nil
    if not unit or unit == "" then
        return nil
    end
    return targetIdentity.BeginObservedCast(unit, payload.castBarID, {
        matchedNPCID = tonumber(payload.matchedNPCID or payload.npcID),
        source = tostring(sourceTag or "targetalert"),
    })
end

local function EndObservedTargetForPayload(payload)
    local targetIdentity = GetTargetIdentity()
    if not (targetIdentity and type(targetIdentity.EndObservedCast) == "function") then
        return false
    end
    if type(payload) ~= "table" then
        return false
    end
    local unit = type(payload.unit) == "string" and payload.unit or nil
    if not unit or unit == "" then
        return false
    end
    return targetIdentity.EndObservedCast(unit, payload.castBarID)
end

local function IsPlayerTargetedByUnit(unit)
    local targetIdentity = GetTargetIdentity()
    if targetIdentity and type(targetIdentity.GetPlayerIdentityState) == "function"
        and type(targetIdentity.IsObservedTargetPlayer) == "function" then
        local playerState = targetIdentity.GetPlayerIdentityState()
        if type(playerState) ~= "table" or playerState.usableForSelfAlert ~= true then
            return false
        end
        return targetIdentity.IsObservedTargetPlayer(unit) == true
    end
    local targetToken = ResolveTargetToken(unit)
    return targetToken ~= nil
end

local function GetTargetAlertCheckDelay(payload)
    local unit = type(payload) == "table" and payload.unit or nil
    local targetIdentity = GetTargetIdentity()
    if targetIdentity and type(targetIdentity.GetObservedResolveDelay) == "function" then
        local delay = tonumber(targetIdentity.GetObservedResolveDelay(unit))
        if delay and delay >= 0 then
            return math.max(0.01, delay)
        end
    end
    return TARGET_ALERT_A_DELAY
end

local function ShouldCheckTargetAlertByPayload(payload)
    local trashSpellRow = GetTrashSpellRow(payload)
    if type(trashSpellRow) == "table" and type(trashSpellRow.targetExists) == "boolean" then
        return trashSpellRow.targetExists == true
    end
    local unit = type(payload) == "table" and payload.unit or nil
    local targetIdentity = GetTargetIdentity()
    if targetIdentity and type(targetIdentity.GetObservedUnitState) == "function" then
        local observedState = targetIdentity.GetObservedUnitState(unit)
        if type(observedState) == "table" and observedState.targetExists ~= nil then
            return observedState.targetExists == true
        end
    end
    if type(unit) ~= "string" or unit == "" then
        return false
    end
    if type(UnitShouldDisplaySpellTargetName) ~= "function" then
        return false
    end
    return UnitShouldDisplaySpellTargetName(unit) == true
end

IsCurrentPlayerTank = function()
    local state = ExwindTools and ExwindTools.State or nil
    return tostring(state and state.RoleKey or ""):lower() == "tank"
end

IsRuleAllowedForCurrentRole = function(rule)
    if not IsCurrentPlayerTank() then
        return true
    end
    return type(rule) == "table" and rule.tankEnabled == true
end

local function QueueDebuffCheck(rule, payload)
    local pendingID = tonumber(Runtime._pendingNextID) or 1
    Runtime._pendingNextID = pendingID + 1
    local now = GetTime and GetTime() or 0
    local beforeWindow, afterWindow = ResolveDebuffTiming(rule)
    local state = ExwindTools and ExwindTools.State or nil
    local anchorRevision = tonumber(state and state.PlayerDebuffRevision or 0) or 0
    local anchorCount = tonumber(state and state.PlayerDebuffCount or 0) or 0
    local lastAddedAt = tonumber(state and state.PlayerDebuffLastAddedAt or 0) or 0
    local lastAddedRevision = tonumber(state and state.PlayerDebuffLastAddedRevision or 0) or 0
    local preMatched = lastAddedRevision > 0
        and lastAddedAt >= (now - beforeWindow)
        and lastAddedAt <= (now + 0.02)
    local item = {
        id = pendingID,
        kind = "B",
        generation = tonumber(Runtime._generation) or 0,
        rule = rule,
        payload = payload,
        runtimeToken = ResolveRuntimeToken(payload),
        anchorAt = now,
        anchorRevision = anchorRevision,
        anchorCount = anchorCount,
        anchorLastAddedRevision = lastAddedRevision,
        beforeWindow = beforeWindow,
        afterWindow = afterWindow,
        preMatched = preMatched == true,
        preMatchedAt = preMatched == true and lastAddedAt or nil,
        dueAt = now + afterWindow,
    }
    TargetAlertDebug(string.format(
        "B-state-anchor key=%s anchorRev=%s anchorCount=%s lastAddedAt=%s lastAddedRev=%s",
        tostring(rule and rule.key or "?"),
        tostring(anchorRevision),
        tostring(anchorCount),
        tostring(lastAddedAt),
        tostring(lastAddedRevision)
    ))
    Runtime._pending[pendingID] = item
    TargetAlertDebug(string.format(
        "queue-B key=%s anchor=%s before=%.2f after=%.2f anchorAt=%.3f preMatched=%s event=%s spell=%s unit=%s",
        tostring(rule and rule.key or "?"),
        tostring(type(rule) == "table" and rule.debuffAnchor or "?"),
        tonumber(beforeWindow) or 0,
        tonumber(afterWindow) or 0,
        tonumber(now) or 0,
        tostring(preMatched == true),
        tostring(type(payload) == "table" and payload.eventID or "nil"),
        tostring(type(payload) == "table" and payload.spellID or "nil"),
        tostring(type(payload) == "table" and payload.unit or "?")
    ))

    if item.preMatched == true then
        Runtime._pending[pendingID] = nil
        TargetAlertDebug(string.format(
            "fire-B-immediate key=%s anchorAt=%.3f matchAt=%s",
            tostring(rule and rule.key or "?"),
            tonumber(now) or 0,
            tostring(item.preMatchedAt or "nil")
        ))
        TryFireRule(item.rule, item.payload, "B", item.preMatchedAt)
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0.01, item.dueAt - now), function()
            local current = Runtime._pending[pendingID]
            if not current then
                return
            end
            Runtime._pending[pendingID] = nil
            if current.generation ~= (tonumber(Runtime._generation) or 0) then
                return
            end

            local state = ExwindTools and ExwindTools.State or nil
            local matched, matchAt, currentRevision, currentCount, lastAddedAt, lastAddedRevision =
                EvaluatePendingDebuffMatch(current, state)
            TargetAlertDebug(string.format(
                "B-state-final key=%s currentRev=%s currentCount=%s lastAddedAt=%s lastAddedRev=%s matched=%s matchAt=%s",
                tostring(current.rule and current.rule.key or "?"),
                tostring(currentRevision),
                tostring(currentCount),
                tostring(lastAddedAt),
                tostring(lastAddedRevision),
                tostring(matched == true),
                tostring(matchAt or "nil")
            ))

            TargetAlertDebug(string.format(
                "check-B key=%s matched=%s anchorAt=%.3f dueAt=%.3f lastAddedAt=%s lastAddedRev=%s anchorRev=%s currentRev=%s anchorCount=%s currentCount=%s matchAt=%s",
                tostring(current.rule and current.rule.key or "?"),
                tostring(matched == true),
                tonumber(current.anchorAt) or 0,
                tonumber(current.dueAt) or 0,
                tostring(lastAddedAt),
                tostring(lastAddedRevision),
                tostring(current.anchorRevision),
                tostring(currentRevision),
                tostring(current.anchorCount),
                tostring(currentCount),
                tostring(matchAt or "nil")
            ))

            if matched then
                TryFireRule(current.rule, current.payload, "B", matchAt)
            end
        end)
    end
end

local function QueueEncounterWarningCheck(rule, payload)
    local pendingID = tonumber(Runtime._pendingNextID) or 1
    Runtime._pendingNextID = pendingID + 1
    local now = GetTime and GetTime() or 0
    local beforeWindow, afterWindow = ResolveWarningTiming(rule)
    local anchorRevision = tonumber(Runtime._encounterWarningRevision) or 0
    local lastWarningAt = tonumber(Runtime._encounterWarningLastAt) or 0
    local lastWarningRevision = anchorRevision
    local preMatched = lastWarningRevision > 0
        and lastWarningAt >= (now - beforeWindow)
        and lastWarningAt <= (now + 0.02)
    local item = {
        id = pendingID,
        kind = "C",
        generation = tonumber(Runtime._generation) or 0,
        rule = rule,
        payload = payload,
        runtimeToken = ResolveRuntimeToken(payload),
        anchorAt = now,
        anchorRevision = anchorRevision,
        anchorLastWarningRevision = lastWarningRevision,
        beforeWindow = beforeWindow,
        afterWindow = afterWindow,
        preMatched = preMatched == true,
        preMatchedAt = preMatched == true and lastWarningAt or nil,
        dueAt = now + afterWindow,
    }
    TargetAlertDebug(string.format(
        "C-state-anchor key=%s anchorRev=%s lastWarningAt=%s",
        tostring(rule and rule.key or "?"),
        tostring(anchorRevision),
        tostring(lastWarningAt)
    ))
    Runtime._pending[pendingID] = item
    TargetAlertDebug(string.format(
        "queue-C key=%s anchor=%s before=%.2f after=%.2f anchorAt=%.3f preMatched=%s event=%s spell=%s unit=%s",
        tostring(rule and rule.key or "?"),
        tostring(type(rule) == "table" and (rule.warningAnchor or rule.debuffAnchor) or "?"),
        tonumber(beforeWindow) or 0,
        tonumber(afterWindow) or 0,
        tonumber(now) or 0,
        tostring(preMatched == true),
        tostring(type(payload) == "table" and payload.eventID or "nil"),
        tostring(type(payload) == "table" and payload.spellID or "nil"),
        tostring(type(payload) == "table" and payload.unit or "?")
    ))

    if item.preMatched == true then
        Runtime._pending[pendingID] = nil
        TargetAlertDebug(string.format(
            "fire-C-immediate key=%s anchorAt=%.3f matchAt=%s",
            tostring(rule and rule.key or "?"),
            tonumber(now) or 0,
            tostring(item.preMatchedAt or "nil")
        ))
        TryFireRule(item.rule, item.payload, "C", item.preMatchedAt)
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0.01, item.dueAt - now), function()
            local current = Runtime._pending[pendingID]
            if not current then
                return
            end
            Runtime._pending[pendingID] = nil
            if current.generation ~= (tonumber(Runtime._generation) or 0) then
                return
            end

            local matched, matchAt, currentRevision, currentLastWarningAt, currentLastWarningRevision =
                EvaluatePendingEncounterWarningMatch(current)
            TargetAlertDebug(string.format(
                "C-state-final key=%s currentRev=%s lastWarningAt=%s lastWarningRev=%s matched=%s matchAt=%s",
                tostring(current.rule and current.rule.key or "?"),
                tostring(currentRevision),
                tostring(currentLastWarningAt),
                tostring(currentLastWarningRevision),
                tostring(matched == true),
                tostring(matchAt or "nil")
            ))

            if matched then
                TryFireRule(current.rule, current.payload, "C", matchAt)
            end
        end)
    end
end

local function HandleBossSchedulerFinishPayload(payload)
    local rules = GetMatchingRules(payload)
    if type(rules) ~= "table" then
        return
    end
    local enrichedPayload = type(payload) == "table" and payload or {}
    if enrichedPayload.runtimeKey == nil then
        enrichedPayload.runtimeKey = table.concat({
            "fixedai_finish",
            tostring(type(payload) == "table" and payload.timerID or "0"),
            tostring(type(payload) == "table" and payload.eventID or "0"),
            tostring(type(payload) == "table" and payload.fireAt or "0"),
        }, ":")
    end
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table"
            and rule.enabled == true
            and NormalizeMode(rule.mode) == "C"
            and NormalizeWarningAnchor(rule.warningAnchor or rule.debuffAnchor) == "scheduler_finish" then
            QueueEncounterWarningCheck(rule, enrichedPayload)
        end
    end
end

local function QueueTargetCheck(rule, payload, sourceTag, checkFn, delaySeconds)
    if type(checkFn) ~= "function" then
        return
    end
    local pendingID = tonumber(Runtime._pendingNextID) or 1
    Runtime._pendingNextID = pendingID + 1
    local now = GetTime and GetTime() or 0
    local delay = tonumber(delaySeconds)
    if not delay or delay < 0.01 then
        delay = TARGET_ALERT_A_DELAY
    end
    local item = {
        id = pendingID,
        kind = "A",
        generation = tonumber(Runtime._generation) or 0,
        rule = rule,
        payload = payload,
        runtimeToken = ResolveRuntimeToken(payload),
        dueAt = now + delay,
        delay = delay,
        sourceTag = tostring(sourceTag or "A"),
    }
    Runtime._pending[pendingID] = item
    TargetAlertDebug(string.format(
        "queue-A key=%s source=%s dueAt=%.3f event=%s spell=%s unit=%s",
        tostring(rule and rule.key or "?"),
        tostring(item.sourceTag),
        tonumber(item.dueAt) or 0,
        tostring(type(payload) == "table" and payload.eventID or "nil"),
        tostring(type(payload) == "table" and payload.spellID or "nil"),
        tostring(type(payload) == "table" and payload.unit or "?")
    ))

    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            local current = Runtime._pending[pendingID]
            if not current then
                return
            end
            Runtime._pending[pendingID] = nil
            if current.generation ~= (tonumber(Runtime._generation) or 0) then
                return
            end
            local okCheck, shouldFire = pcall(checkFn, current.payload)
            TargetAlertDebug(string.format(
                "check-A key=%s source=%s shouldFire=%s event=%s spell=%s unit=%s",
                tostring(current.rule and current.rule.key or "?"),
                tostring(current.sourceTag),
                tostring(okCheck and shouldFire == true),
                tostring(type(current.payload) == "table" and current.payload.eventID or "nil"),
                tostring(type(current.payload) == "table" and current.payload.spellID or "nil"),
                tostring(type(current.payload) == "table" and current.payload.unit or "?")
            ))
            if okCheck and shouldFire == true then
                TryFireRule(current.rule, current.payload, "A")
            end
        end)
    end
end

local function HandleBossCastPayload(payload, phase)
    if phase == "cast_end" then
        EndObservedTargetForPayload(payload)
        StopRuntimeDisplays(type(payload) == "table" and (payload.runtimeID or payload.runtimeKey) or nil)
        CancelPendingForRuntime(ResolveRuntimeToken(payload))
    end
    local rules = GetMatchingRules(payload)
    if type(rules) ~= "table" then
        return
    end
    local suppressA = false
    for i = 1, #rules do
        local rule = rules[i]
        local mode = type(rule) == "table" and NormalizeMode(rule.mode) or nil
        if mode == "B" or mode == "C" or mode == "A_OR_B" then
            suppressA = true
            break
        end
    end

    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and rule.enabled == true then
            local mode = NormalizeMode(rule.mode)
            if phase == "cast_start" and suppressA == true and mode == "A" then
                TargetAlertDebug(string.format(
                    "skip-A-by-B key=%s event=%s spell=%s unit=%s",
                    tostring(rule.key or "?"),
                    tostring(type(payload) == "table" and payload.eventID or "nil"),
                    tostring(type(payload) == "table" and payload.spellID or "nil"),
                    tostring(type(payload) == "table" and payload.unit or "?")
                ))
            end
            if phase == "cast_start" and suppressA ~= true and (mode == "A" or mode == "A_OR_B") then
                BeginObservedTargetForPayload(payload, "targetalert_filtered")
                local shouldDisplayTarget = true
                local isPlayerTargeted = IsPlayerTargetedByUnit(payload.unit)
                local targetCheckDelay = GetTargetAlertCheckDelay(payload)
                TargetAlertDebug(string.format(
                    "A-check key=%s unit=%s shouldDisplay=%s targeted=%s delay=%.2f event=%s spell=%s",
                    tostring(rule.key or "?"),
                    tostring(type(payload) == "table" and payload.unit or "?"),
                    tostring(shouldDisplayTarget),
                    tostring(isPlayerTargeted),
                    tonumber(targetCheckDelay) or 0,
                    tostring(type(payload) == "table" and payload.eventID or "nil"),
                    tostring(type(payload) == "table" and payload.spellID or "nil")
                ))
                if shouldDisplayTarget then
                    QueueTargetCheck(rule, payload, "boss", function(currentPayload)
                        return IsPlayerTargetedByUnit(type(currentPayload) == "table" and currentPayload.unit or nil)
                    end, targetCheckDelay)
                end
            end
            if (mode == "B" or mode == "A_OR_B") and NormalizeAnchor(rule.debuffAnchor) == phase then
                QueueDebuffCheck(rule, payload)
            end
            if mode == "C" and NormalizeWarningAnchor(rule.warningAnchor or rule.debuffAnchor) == phase then
                QueueEncounterWarningCheck(rule, payload)
            end
        end
    end
end

local function ClearRuntimeState()
    for runtimeID in pairs(Runtime._displayKeys or {}) do
        StopRuntimeDisplays(runtimeID)
    end
    Runtime._generation = (tonumber(Runtime._generation) or 0) + 1
    Runtime._pending = {}
    Runtime._fired = {}
    Runtime._displayKeys = {}
    Runtime._encounterWarningRevision = 0
    Runtime._encounterWarningLastAt = 0
end

local function GetTrashRuleBucket(mapID, npcID, spellID, createIfMissing)
    local sid = tonumber(spellID)
    if not sid then
        return nil
    end
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    local bucketKey = table.concat({
        tostring(mid or "__any"),
        tostring(nid or "__any"),
        tostring(sid),
    }, ":")
    if createIfMissing then
        Runtime._trashRules[bucketKey] = Runtime._trashRules[bucketKey] or {}
    end
    return Runtime._trashRules[bucketKey]
end

local function GetMatchingTrashRules(payload)
    local exactBucket = GetTrashRuleBucket(
        type(payload) == "table" and payload.mapID or nil,
        type(payload) == "table" and payload.npcID or nil,
        type(payload) == "table" and payload.spellID or nil,
        false
    )
    local anyBucket = GetTrashRuleBucket(
        nil,
        nil,
        type(payload) == "table" and payload.spellID or nil,
        false
    )
    local exactCount = type(exactBucket) == "table" and #exactBucket or 0
    local anyCount = type(anyBucket) == "table" and #anyBucket or 0
    if exactCount == 0 and anyCount == 0 then
        return nil
    end
    if anyCount == 0 then
        return exactBucket
    end
    if exactCount == 0 then
        return anyBucket
    end
    local merged = {}
    for i = 1, exactCount do
        merged[#merged + 1] = exactBucket[i]
    end
    for i = 1, anyCount do
        merged[#merged + 1] = anyBucket[i]
    end
    return merged
end

local function HandleTrashCastPayload(payload, phase, allowA)
    if phase == "cast_end" then
        EndObservedTargetForPayload(payload)
        StopRuntimeDisplays(type(payload) == "table" and (payload.runtimeKey or payload.runtime) or nil)
        CancelPendingForRuntime(ResolveRuntimeToken(payload))
    end
    local rules = GetMatchingTrashRules(payload)
    if type(rules) ~= "table" then
        return
    end
    local suppressA = false
    for i = 1, #rules do
        local rule = rules[i]
        local mode = type(rule) == "table" and NormalizeMode(rule.mode) or nil
        if mode == "B" or mode == "C" or mode == "A_OR_B" then
            suppressA = true
            break
        end
    end
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and rule.enabled == true then
            local mode = NormalizeMode(rule.mode)
            if phase == "cast_start" and suppressA == true and mode == "A" then
                TargetAlertDebug(string.format(
                    "skip-A-by-B key=%s event=%s spell=%s unit=%s",
                    tostring(rule.key or "?"),
                    tostring(type(payload) == "table" and payload.eventID or "nil"),
                    tostring(type(payload) == "table" and payload.spellID or "nil"),
                    tostring(type(payload) == "table" and payload.unit or "?")
                ))
            end
            if phase == "cast_start"
                and allowA ~= false
                and suppressA ~= true
                and (mode == "A" or mode == "A_OR_B") then
                BeginObservedTargetForPayload(payload, "targetalert_filtered")
                local shouldDisplayTarget = ShouldCheckTargetAlertByPayload(payload)
                local isPlayerTargeted = shouldDisplayTarget and IsPlayerTargetedByUnit(payload.unit) or false
                local targetCheckDelay = GetTargetAlertCheckDelay(payload)
                TargetAlertDebug(string.format(
                    "A-check key=%s unit=%s shouldDisplay=%s targeted=%s delay=%.2f map=%s npc=%s spell=%s",
                    tostring(rule.key or "?"),
                    tostring(type(payload) == "table" and payload.unit or "?"),
                    tostring(shouldDisplayTarget),
                    tostring(isPlayerTargeted),
                    tonumber(targetCheckDelay) or 0,
                    tostring(type(payload) == "table" and payload.mapID or "nil"),
                    tostring(type(payload) == "table" and payload.npcID or "nil"),
                    tostring(type(payload) == "table" and payload.spellID or "nil")
                ))
                if shouldDisplayTarget then
                    QueueTargetCheck(rule, payload, "trash", function(currentPayload)
                        local shouldDisplay = ShouldCheckTargetAlertByPayload(currentPayload)
                        return shouldDisplay and
                            IsPlayerTargetedByUnit(type(currentPayload) == "table" and currentPayload.unit or nil)
                    end, targetCheckDelay)
                end
            end
            if (mode == "B" or mode == "A_OR_B") and NormalizeAnchor(rule.debuffAnchor) == phase then
                QueueDebuffCheck(rule, payload)
            end
            if mode == "C" and NormalizeWarningAnchor(rule.warningAnchor or rule.debuffAnchor) == phase then
                QueueEncounterWarningCheck(rule, payload)
            end
        end
    end
end

function Runtime:RegisterBossRule(def)
    if type(def) ~= "table" then
        return nil
    end
    local encounterID = tonumber(def.encounterID)
    local eventID = tonumber(def.eventID)
    if not eventID then
        return nil
    end
    local bucket = GetRuleBucket(encounterID, eventID, true)
    local rule = {
        key = tostring(def.key or
            ("boss:" .. tostring(encounterID or "any") .. ":" .. tostring(eventID) .. ":" .. tostring(#bucket + 1))),
        enabled = def.enabled ~= false,
        encounterID = encounterID,
        eventID = eventID,
        mode = NormalizeMode(def.mode),
        debuffAnchor = NormalizeAnchor(def.debuffAnchor),
        debuffWindow = NormalizeWindow(def.debuffWindow),
        debuffWindowBefore = NormalizeSeconds(def.debuffWindowBefore, 0, 10.0),
        debuffWindowAfter = def.debuffWindowAfter ~= nil and
            NormalizeSeconds(def.debuffWindowAfter, def.debuffWindow, 10.0) or nil,
        debuffDelay = def.debuffDelay ~= nil and NormalizeSeconds(def.debuffDelay, 0.10, 10.0) or nil,
        warningAnchor = NormalizeWarningAnchor(def.warningAnchor or def.debuffAnchor),
        warningWindow = def.warningWindow ~= nil and NormalizeWindow(def.warningWindow) or nil,
        warningWindowBefore = def.warningWindowBefore ~= nil and NormalizeSeconds(def.warningWindowBefore, 0, 10.0) or
            nil,
        warningWindowAfter = def.warningWindowAfter ~= nil and
            NormalizeSeconds(def.warningWindowAfter, def.warningWindow, 10.0) or nil,
        warningDelay = def.warningDelay ~= nil and NormalizeSeconds(def.warningDelay, 0.75, 10.0) or nil,
        displayDuration = NormalizeSeconds(def.displayDuration, nil, 60.0),
        ringEnabled = def.ringEnabled == true,
        iconEnabled = def.iconEnabled == true,
        tankEnabled = def.tankEnabled == true,
        textEnabled = def.textEnabled ~= false,
        stealthEnabled = def.stealthEnabled == true,
        placeholderText = tostring(def.placeholderText or ""),
        soundKey = tostring(def.soundKey or ""),
    }

    for i = 1, #bucket do
        if type(bucket[i]) == "table" and bucket[i].key == rule.key then
            bucket[i] = rule
            return rule.key
        end
    end
    bucket[#bucket + 1] = rule
    return rule.key
end

function Runtime:RegisterTrashRule(def)
    if type(def) ~= "table" then
        return nil
    end
    local mapID = tonumber(def.mapID)
    local npcID = tonumber(def.npcID)
    local spellID = tonumber(def.spellID)
    if not spellID then
        return nil
    end
    local bucket = GetTrashRuleBucket(mapID, npcID, spellID, true)
    local rule = {
        key = tostring(def.key or
            ("trash:" .. tostring(mapID or "any") .. ":" .. tostring(npcID or "any") .. ":" .. tostring(spellID) .. ":" .. tostring(#bucket + 1))),
        enabled = def.enabled ~= false,
        mapID = mapID,
        npcID = npcID,
        spellID = spellID,
        mode = NormalizeMode(def.mode),
        debuffAnchor = NormalizeAnchor(def.debuffAnchor),
        debuffWindow = NormalizeWindow(def.debuffWindow),
        debuffWindowBefore = NormalizeSeconds(def.debuffWindowBefore, 0, 10.0),
        debuffWindowAfter = def.debuffWindowAfter ~= nil and
            NormalizeSeconds(def.debuffWindowAfter, def.debuffWindow, 10.0) or nil,
        debuffDelay = def.debuffDelay ~= nil and NormalizeSeconds(def.debuffDelay, 0.10, 10.0) or nil,
        warningAnchor = NormalizeWarningAnchor(def.warningAnchor or def.debuffAnchor),
        warningWindow = def.warningWindow ~= nil and NormalizeWindow(def.warningWindow) or nil,
        warningWindowBefore = def.warningWindowBefore ~= nil and NormalizeSeconds(def.warningWindowBefore, 0, 10.0) or
            nil,
        warningWindowAfter = def.warningWindowAfter ~= nil and
            NormalizeSeconds(def.warningWindowAfter, def.warningWindow, 10.0) or nil,
        warningDelay = def.warningDelay ~= nil and NormalizeSeconds(def.warningDelay, 0.75, 10.0) or nil,
        displayDuration = NormalizeSeconds(def.displayDuration, nil, 60.0),
        ringEnabled = def.ringEnabled == true,
        iconEnabled = def.iconEnabled == true,
        tankEnabled = def.tankEnabled == true,
        textEnabled = def.textEnabled ~= false,
        stealthEnabled = def.stealthEnabled == true,
        placeholderText = tostring(def.placeholderText or ""),
        soundKey = tostring(def.soundKey or ""),
    }
    for i = 1, #bucket do
        if type(bucket[i]) == "table" and bucket[i].key == rule.key then
            bucket[i] = rule
            return rule.key
        end
    end
    bucket[#bucket + 1] = rule
    return rule.key
end

function Runtime:UnregisterBossRule(ruleKey)
    local wanted = tostring(ruleKey or "")
    if wanted == "" then
        return false
    end
    for encounterID, byEvent in pairs(self._bossRules) do
        if type(byEvent) == "table" then
            for eventID, bucket in pairs(byEvent) do
                if type(bucket) == "table" then
                    for i = #bucket, 1, -1 do
                        if type(bucket[i]) == "table" and bucket[i].key == wanted then
                            table.remove(bucket, i)
                            if #bucket == 0 then
                                byEvent[eventID] = nil
                            end
                            if next(byEvent) == nil then
                                self._bossRules[encounterID] = nil
                            end
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function Runtime:ClearBossRules()
    self._bossRules = {}
end

function Runtime:ClearTrashRules()
    self._trashRules = {}
end

function Runtime:RegisterBossDebuffWindowRule(eventID, def)
    def = type(def) == "table" and def or {}
    return self:RegisterBossRule({
        key = def.key,
        enabled = def.enabled,
        encounterID = def.encounterID,
        eventID = tonumber(eventID),
        mode = def.mode or "B",
        debuffAnchor = def.anchor or def.debuffAnchor or "cast_start",
        debuffWindowBefore = def.windowBefore,
        debuffWindowAfter = def.windowAfter,
        debuffDelay = def.delay,
        displayDuration = def.displayDuration,
        ringEnabled = def.ringEnabled,
        iconEnabled = def.iconEnabled,
        tankEnabled = def.tankEnabled,
        placeholderText = def.placeholderText,
        soundKey = def.soundKey,
    })
end

function Runtime:RegisterTrashDebuffWindowRule(arg1, arg2, arg3, arg4)
    local mapID, npcID, spellID, def
    if arg3 == nil and type(arg2) == "table" then
        mapID = nil
        npcID = nil
        spellID = tonumber(arg1)
        def = arg2
    else
        mapID = tonumber(arg1)
        npcID = tonumber(arg2)
        spellID = tonumber(arg3)
        def = type(arg4) == "table" and arg4 or {}
    end
    return self:RegisterTrashRule({
        key = def.key,
        enabled = def.enabled,
        mapID = mapID,
        npcID = npcID,
        spellID = spellID,
        mode = def.mode or "B",
        debuffAnchor = def.anchor or def.debuffAnchor or "cast_start",
        debuffWindowBefore = def.windowBefore,
        debuffWindowAfter = def.windowAfter,
        debuffDelay = def.delay,
        displayDuration = def.displayDuration,
        ringEnabled = def.ringEnabled,
        iconEnabled = def.iconEnabled,
        tankEnabled = def.tankEnabled,
        placeholderText = def.placeholderText,
        soundKey = def.soundKey,
    })
end

function Runtime:RegisterBossEncounterWarningRule(eventID, def)
    def = type(def) == "table" and def or {}
    return self:RegisterBossRule({
        key = def.key,
        enabled = def.enabled,
        encounterID = def.encounterID,
        eventID = tonumber(eventID),
        mode = def.mode or "C",
        warningAnchor = def.anchor or def.warningAnchor or "cast_start",
        warningWindowBefore = def.windowBefore,
        warningWindowAfter = def.windowAfter,
        warningDelay = def.delay,
        displayDuration = def.displayDuration,
        ringEnabled = def.ringEnabled,
        iconEnabled = def.iconEnabled,
        tankEnabled = def.tankEnabled,
        textEnabled = def.textEnabled,
        stealthEnabled = def.stealthEnabled,
        placeholderText = def.placeholderText,
        soundKey = def.soundKey,
    })
end

function Runtime:RegisterTrashEncounterWarningRule(arg1, arg2, arg3, arg4)
    local mapID, npcID, spellID, def
    if arg3 == nil and type(arg2) == "table" then
        mapID = nil
        npcID = nil
        spellID = tonumber(arg1)
        def = arg2
    else
        mapID = tonumber(arg1)
        npcID = tonumber(arg2)
        spellID = tonumber(arg3)
        def = type(arg4) == "table" and arg4 or {}
    end
    return self:RegisterTrashRule({
        key = def.key,
        enabled = def.enabled,
        mapID = mapID,
        npcID = npcID,
        spellID = spellID,
        mode = def.mode or "C",
        warningAnchor = def.anchor or def.warningAnchor or "cast_start",
        warningWindowBefore = def.windowBefore,
        warningWindowAfter = def.windowAfter,
        warningDelay = def.delay,
        displayDuration = def.displayDuration,
        ringEnabled = def.ringEnabled,
        iconEnabled = def.iconEnabled,
        tankEnabled = def.tankEnabled,
        textEnabled = def.textEnabled,
        stealthEnabled = def.stealthEnabled,
        placeholderText = def.placeholderText,
        soundKey = def.soundKey,
    })
end

function Runtime:ShouldObserveBossCast(timer)
    if type(timer) ~= "table" or timer.disabled == true then
        return false
    end
    local eventID = tonumber(timer.eventID)
    if not eventID then
        return false
    end
    local bucket = GetRuleBucket(tonumber(timer.encounterID), eventID, false)
    if type(bucket) == "table" and #bucket > 0 then
        return true
    end
    local anyBucket = GetRuleBucket(nil, eventID, false)
    return type(anyBucket) == "table" and #anyBucket > 0
end

function Runtime:RefreshActiveRegistrations()
    ClearRuntimeState()
    self:ClearBossRules()
    self:ClearTrashRules()
    local root = type(_G.EXBossDataDB) == "table" and type(_G.EXBossDataDB.events) == "table" and _G.EXBossDataDB.events or
        nil
    local count = 0
    if type(root) == "table" then
        for rawEventID, row in pairs(root) do
            local eventID = tonumber(rawEventID)
            if eventID and type(row) == "table" and row.targetAlertStartEnabled == true then
                self:RegisterBossRule({
                    key = "boss:start:" .. tostring(eventID),
                    eventID = eventID,
                    mode = "A",
                    enabled = true,
                    tankEnabled = row.targetAlertTankEnabled == true,
                    ringEnabled = row.targetAlertRingEnabled == true,
                    iconEnabled = row.targetAlertIconEnabled == true,
                    textEnabled = row.targetAlertTextEnabledV2 == true,
                    stealthEnabled = row.targetAlertStealthEnabledV2 == true,
                    soundKey = tostring(row.targetAlertStartLSM or ""),
                })
                count = count + 1
            end
        end
    end

    do
        local row241 = type(root) == "table" and root[241] or nil
        self:RegisterBossDebuffWindowRule(241, {
            key = "boss:b:241",
            anchor = "cast_end",
            windowBefore = 0.10,
            windowAfter = 0.60,
            displayDuration = 6,
            tankEnabled = type(row241) == "table" and row241.targetAlertTankEnabled == true,
            ringEnabled = type(row241) == "table" and row241.targetAlertRingEnabled == true,
            iconEnabled = type(row241) == "table" and row241.targetAlertIconEnabled == true,
            textEnabled = type(row241) == "table" and row241.targetAlertTextEnabledV2 == true,
            stealthEnabled = type(row241) == "table" and row241.targetAlertStealthEnabledV2 == true,
            soundKey = type(row241) == "table" and tostring(row241.targetAlertStartLSM or "") or "",
        })
        count = count + 1
    end

    do
        local row275 = type(root) == "table" and root[275] or nil
        if type(row275) == "table" and row275.targetAlertStartEnabled == true then
            self:RegisterBossDebuffWindowRule(275, {
                key = "boss:b:275",
                anchor = "cast_end",
                windowBefore = 0.10,
                windowAfter = 0.30,
                displayDuration = 4.00,
                tankEnabled = row275.targetAlertTankEnabled == true,
                ringEnabled = row275.targetAlertRingEnabled == true,
                iconEnabled = row275.targetAlertIconEnabled == true,
                textEnabled = row275.targetAlertTextEnabledV2 == true,
                stealthEnabled = row275.targetAlertStealthEnabledV2 == true,
                soundKey = tostring(row275.targetAlertStartLSM or ""),
            })
            count = count + 1
        end
    end

    do
        local row153 = type(root) == "table" and root[153] or nil
        if type(row153) == "table" and row153.targetAlertStartEnabled == true then
            self:RegisterBossEncounterWarningRule(153, {
                key = "boss:c:153",
                anchor = "cast_start",
                windowBefore = 0.10,
                windowAfter = 3.00,
                tankEnabled = row153.targetAlertTankEnabled == true,
                ringEnabled = row153.targetAlertRingEnabled == true,
                iconEnabled = row153.targetAlertIconEnabled == true,
                textEnabled = row153.targetAlertTextEnabledV2 == true,
                stealthEnabled = row153.targetAlertStealthEnabledV2 == true,
                soundKey = tostring(row153.targetAlertStartLSM or ""),
            })
            count = count + 1
        end
    end

    do
        local row157 = type(root) == "table" and root[157] or nil
        if type(row157) == "table" and row157.targetAlertStartEnabled == true then
            self:RegisterBossEncounterWarningRule(157, {
                key = "boss:c:157",
                anchor = "cast_start",
                windowBefore = 0.10,
                windowAfter = 5.00,
                displayDuration = 4.50,
                tankEnabled = row157.targetAlertTankEnabled == true,
                ringEnabled = row157.targetAlertRingEnabled == true,
                iconEnabled = row157.targetAlertIconEnabled == true,
                textEnabled = row157.targetAlertTextEnabledV2 == true,
                stealthEnabled = row157.targetAlertStealthEnabledV2 == true,
                soundKey = tostring(row157.targetAlertStartLSM or ""),
            })
            count = count + 1
        end
    end

    do
        local row166 = type(root) == "table" and root[166] or nil
        if type(row166) == "table" and row166.targetAlertStartEnabled == true then
            self:RegisterBossEncounterWarningRule(166, {
                key = "boss:c:166",
                anchor = "scheduler_finish",
                windowBefore = 0.10,
                windowAfter = 4.00,
                displayDuration = 6.60,
                tankEnabled = row166.targetAlertTankEnabled == true,
                ringEnabled = row166.targetAlertRingEnabled == true,
                iconEnabled = row166.targetAlertIconEnabled == true,
                textEnabled = row166.targetAlertTextEnabledV2 == true,
                stealthEnabled = row166.targetAlertStealthEnabledV2 == true,
                soundKey = tostring(row166.targetAlertStartLSM or ""),
            })
            count = count + 1
        end
    end

    local trashStore = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
    local trashRuntimeConfig = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.RuntimeConfig or nil
    local db = trashStore and type(trashStore.EnsureDB) == "function" and trashStore.EnsureDB() or nil
    local entries = type(db) == "table" and type(db.spellEntries) == "table" and db.spellEntries or nil
    if type(entries) == "table" then
        for rawKey in pairs(entries) do
            local mapID, npcID, spellID = tostring(rawKey or ""):match("^(%d+):(%d+):(%d+)$")
            mapID = tonumber(mapID)
            npcID = tonumber(npcID)
            spellID = tonumber(spellID)
            if mapID and npcID and spellID and trashStore and type(trashStore.GetResolvedSpellEntry) == "function" then
                local cfg = trashStore.GetResolvedSpellEntry(mapID, npcID, spellID, false)
                local roleAllowed = not (trashRuntimeConfig and type(trashRuntimeConfig.IsRoleEnabled) == "function")
                    or trashRuntimeConfig.IsRoleEnabled(cfg) == true
                if type(cfg) == "table" and cfg.targetAlertStartEnabled == true and cfg.enabled == true and roleAllowed then
                    self:RegisterTrashRule({
                        key = "trash:start:" .. tostring(mapID) .. ":" .. tostring(npcID) .. ":" .. tostring(spellID),
                        mapID = mapID,
                        npcID = npcID,
                        spellID = spellID,
                        mode = "A",
                        enabled = true,
                        tankEnabled = cfg.targetAlertTankEnabled == true,
                        ringEnabled = cfg.targetAlertRingEnabled == true,
                        iconEnabled = cfg.targetAlertIconEnabled == true,
                        textEnabled = cfg.targetAlertTextEnabledV2 == true,
                        stealthEnabled = cfg.targetAlertStealthEnabledV2 == true,
                        soundKey = tostring(cfg.targetAlertStartLSM or ""),
                    })
                    count = count + 1
                end
            end
        end
    end
    return count
end

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent(BOSS_CAST_START_EVENT, OWNER .. ".Start", function(_, payload)
        HandleBossCastPayload(payload, "cast_start")
    end)
    ExwindTools:RegisterEvent(BOSS_CAST_STOP_EVENT, OWNER .. ".Stop", function(_, payload)
        HandleBossCastPayload(payload, "cast_end")
    end)
    ExwindTools:RegisterEvent(TRASH_CAST_START_EVENT, OWNER .. ".TrashStart", function(_, payload)
        HandleTrashCastPayload(payload, "cast_start", true)
    end)
    ExwindTools:RegisterEvent(TRASH_VOICE_START_EVENT, OWNER .. ".TrashVoiceStart", function(_, payload)
        HandleTrashCastPayload(payload, "cast_start", true)
    end)
    ExwindTools:RegisterEvent(TRASH_CAST_STOP_EVENT, OWNER .. ".TrashStop", function(_, payload)
        HandleTrashCastPayload(payload, "cast_end")
    end)
    ExwindTools:RegisterEvent(FIXED_AI_EVENT_FINISHED_EVENT, OWNER .. ".FixedAIFinished", function(_, payload)
        HandleBossSchedulerFinishPayload(payload)
    end)
    ExwindTools:RegisterEvent("ENCOUNTER_END", OWNER .. ".EncounterEnd", function()
        ClearRuntimeState()
    end)
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", OWNER .. ".PEW", function()
        ClearRuntimeState()
        Runtime:RefreshActiveRegistrations()
    end)
    ExwindTools:RegisterEvent("PLAYER_STEALTH_CHANGED", OWNER .. ".StealthChanged", function()
        if not (IsStealthed and IsStealthed()) then return end
        ClearRuntimeState()
        local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress
        if Ring and type(Ring.StopByOwner) == "function" then
            Ring:StopByOwner({ source = "targetalert" })
        end
        local Icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert
        if Icon and type(Icon.StopByOwner) == "function" then
            Icon:StopByOwner({ source = "targetalert" })
        end
    end)
    ExwindTools:RegisterEvent("ENCOUNTER_WARNING", OWNER .. ".EncounterWarning", function(_, encounterWarningInfo)
        Runtime._encounterWarningRevision = (tonumber(Runtime._encounterWarningRevision) or 0) + 1
        Runtime._encounterWarningLastAt = GetTime and GetTime() or 0
        TargetAlertDebug(string.format(
            "encounter-warning rev=%s at=%.3f hasInfo=%s text=%s",
            tostring(Runtime._encounterWarningRevision),
            tonumber(Runtime._encounterWarningLastAt) or 0,
            tostring(type(encounterWarningInfo) == "table"),
            tostring(type(encounterWarningInfo) == "table" and encounterWarningInfo.text or "")
        ))
        for pendingID, current in pairs(Runtime._pending or {}) do
            if type(current) == "table"
                and current.kind == "C"
                and current.generation == (tonumber(Runtime._generation) or 0) then
                local matched, matchAt = EvaluatePendingEncounterWarningMatch(current)
                if matched then
                    Runtime._pending[pendingID] = nil
                    TargetAlertDebug(string.format(
                        "fire-C-early key=%s matchAt=%s anchorAt=%.3f dueAt=%.3f",
                        tostring(current.rule and current.rule.key or "?"),
                        tostring(matchAt or "nil"),
                        tonumber(current.anchorAt) or 0,
                        tonumber(current.dueAt) or 0
                    ))
                    TryFireRule(current.rule, current.payload, "C", matchAt)
                end
            end
        end
    end)
end

if ExwindTools and type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState("RoleKey", OWNER .. ".RoleChanged", function()
        Runtime:RefreshActiveRegistrations()
    end)
    ExwindTools:WatchState("PlayerDebuffRevision", OWNER .. ".PendingDebuffCheck", function(newValue)
        local state = ExwindTools and ExwindTools.State or nil
        for pendingID, current in pairs(Runtime._pending or {}) do
            if type(current) == "table"
                and current.kind == "B"
                and current.generation == (tonumber(Runtime._generation) or 0) then
                local matched, matchAt = EvaluatePendingDebuffMatch(current, state)
                if matched then
                    Runtime._pending[pendingID] = nil
                    TargetAlertDebug(string.format(
                        "fire-B-early key=%s rev=%s matchAt=%s anchorAt=%.3f dueAt=%.3f",
                        tostring(current.rule and current.rule.key or "?"),
                        tostring(newValue or "nil"),
                        tostring(matchAt or "nil"),
                        tonumber(current.anchorAt) or 0,
                        tonumber(current.dueAt) or 0
                    ))
                    TryFireRule(current.rule, current.payload, "B", matchAt)
                end
            end
        end
    end)
end

if type(Runtime.RefreshActiveRegistrations) == "function" then
    Runtime:RefreshActiveRegistrations()
end
