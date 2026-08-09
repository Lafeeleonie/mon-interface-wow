---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.RuntimeConfig or {}
ExBoss.TrashCD.RuntimeConfig = Mod
ExBoss.Trash.RuntimeConfig = Mod

local Store = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Core = ExBoss.TrashCD and ExBoss.TrashCD.Core or nil

local ACADEMY_DUNGEON_MAP_ID = 2526
local DISABLED_BOSS_ENCOUNTER_IDS = {
    [2001] = true,
}

local _timelineEventMeta = {}
local _configRevision = 0

local function GetVoiceEngine()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.Engine or nil
end

local function GetColorSchemes()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes or nil
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

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for key, value in pairs(v) do
        out[key] = DeepCopy(value)
    end
    return out
end

local function NormalizeText(v)
    if type(v) ~= "string" then
        return ""
    end
    local s = v:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function NormalizeRoleKey(role)
    local v = tostring(role or ""):lower()
    if v == "tank" then return "tank" end
    if v == "heal" or v == "healer" then return "heal" end
    if v == "dps" or v == "damage" or v == "damager" then return "dps" end
    return "dps"
end

local function GetCurrentRoleKey()
    local state = ExwindTools and ExwindTools.State or nil
    return NormalizeRoleKey(state and state.RoleKey)
end

local function GetCurrentBossProgressIndex()
    local state = ExwindTools and ExwindTools.State or nil
    local idx = tonumber(state and state.DungeonBossProgressIndex) or 0
    return idx > 0 and idx or nil
end

local function GetCurrentPlayerMapID()
    local state = ExwindTools and ExwindTools.State or nil
    local mapID = tonumber(state and state.MapID) or 0
    return mapID > 0 and mapID or nil
end

local function GetCurrentEncounterID()
    local state = ExwindTools and ExwindTools.State or nil
    local id = tonumber(state and state.EncounterID) or 0
    return id > 0 and id or nil
end

local function IsBossEncounterActive()
    local state = ExwindTools and ExwindTools.State or nil
    return state and state.IsBossEncounter == true
end

function Mod.IsDisabledInBossEncounter(encounterID)
    local id = tonumber(encounterID)
    return id ~= nil and DISABLED_BOSS_ENCOUNTER_IDS[id] == true
end

function Mod.IsDisabledInCurrentEncounter()
    if IsBossEncounterActive() and Mod.IsDisabledInBossEncounter(GetCurrentEncounterID()) then
        return true
    end
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
    if scheduler and scheduler._running == true then
        return Mod.IsDisabledInBossEncounter(scheduler._encounterID)
    end
    return false
end

local function IsRoleEnabled(cfg, roleKey)
    if type(cfg) ~= "table" then
        return false
    end
    if cfg.enabled ~= true then
        return false
    end
    local role = NormalizeRoleKey(roleKey)
    if role == "tank" then
        return cfg.tankEnabled == true
    end
    if role == "heal" then
        return cfg.healerEnabled == true
    end
    return cfg.dpsEnabled == true
end

function Mod.IsRoleEnabled(cfg, roleKey)
    local resolvedRoleKey = roleKey
    if resolvedRoleKey == nil then
        resolvedRoleKey = GetCurrentRoleKey()
    end
    return IsRoleEnabled(cfg, resolvedRoleKey)
end

local function ParsePlacementSet(text)
    local raw = NormalizeText(text)
    if raw == "" then
        return nil, nil
    end
    local stageSet = {}
    local mapSet = {}
    for token in raw:gmatch("[^,]+") do
        local n = tonumber((tostring(token):gsub("%s+", "")))
        if n and n > 0 then
            if n <= 20 then
                stageSet[n] = true
            else
                mapSet[n] = true
            end
        end
    end
    if next(stageSet) == nil then
        stageSet = nil
    end
    if next(mapSet) == nil then
        mapSet = nil
    end
    return stageSet, mapSet
end

local function IsPlacementAllowed(cfg, mapID)
    if type(cfg) ~= "table" then
        return true
    end
    if tonumber(mapID) == ACADEMY_DUNGEON_MAP_ID then
        return true
    end
    local stageSet, mapSet = ParsePlacementSet(cfg.bossStages)
    if not stageSet and not mapSet then
        return true
    end
    if mapSet then
        if Data and type(Data.IsCurrentPlacementSetAllowed) == "function"
            and Data.IsCurrentPlacementSetAllowed(mapSet) ~= true then
            return false
        end
    end
    if stageSet then
        local currentStage = GetCurrentBossProgressIndex()
        if currentStage and stageSet[currentStage] ~= true then
            return false
        end
    end
    return true
end

local function GetHideLongTimerBarConfig()
    if not (Store and type(Store.GetHideLongTimerBarConfig) == "function") then
        return { enabled = false, seconds = 0 }
    end
    local cfg = Store.GetHideLongTimerBarConfig()
    return {
        enabled = type(cfg) == "table" and cfg.enabled == true or false,
        seconds = math.max(0, tonumber(type(cfg) == "table" and cfg.seconds or 0) or 0),
    }
end

local function GetKeepTimerBarAfterReadyConfig()
    if not (Store and type(Store.GetKeepTimerBarAfterReadyConfig) == "function") then
        return { enabled = false, seconds = 0 }
    end
    local cfg = Store.GetKeepTimerBarAfterReadyConfig()
    return {
        enabled = type(cfg) == "table" and cfg.enabled == true or false,
        seconds = math.max(0, tonumber(type(cfg) == "table" and cfg.seconds or 0) or 0),
    }
end

local function BuildFallbackDisplayName(mobData, spellData)
    local locale = type(GetLocale) == "function" and tostring(GetLocale() or "") or ""
    local spellID = tonumber(type(spellData) == "table" and spellData.spellID or nil)
    if locale ~= "zhCN" and spellID and Data and type(Data.GetSpellNameSafe) == "function" then
        local apiName = NormalizeText(Data.GetSpellNameSafe(spellID))
        if apiName ~= "" then
            return apiName
        end
    end
    local spellName = NormalizeText(type(spellData) == "table" and tostring(spellData.name or "") or "")
    if spellName ~= "" then
        return spellName
    end
    if spellID then
        return "技能 " .. tostring(spellID)
    end
    return "小怪技能"
end

local function BuildDefaultSpellName(spellData)
    return BuildFallbackDisplayName(nil, spellData)
end

local function BuildColorConfig(cfg)
    if type(cfg) ~= "table" or cfg.eventColorEnabled ~= true then
        return nil
    end
    local mode = tostring(cfg.eventColorMode or "none")
    if mode == "" or mode == "none" then
        return nil
    end

    local out = {
        enabled = true,
        scheme = mode,
        useCustom = false,
    }

    if mode == "__custom" or mode == "custom" then
        local colorSchemes = GetColorSchemes()
        out.useCustom = true
        out.scheme = colorSchemes and colorSchemes.GetCustomKey and colorSchemes.GetCustomKey() or "__custom"
        out.r = tonumber(cfg.eventColor and cfg.eventColor.r) or 1
        out.g = tonumber(cfg.eventColor and cfg.eventColor.g) or 0.82
        out.b = tonumber(cfg.eventColor and cfg.eventColor.b) or 0.25
        out.a = tonumber(cfg.eventColor and cfg.eventColor.a) or 1
    end

    return out
end

local function BuildResolvedEventColor(colorConfig)
    local colorSchemes = GetColorSchemes()
    if type(colorConfig) ~= "table" or type(colorSchemes) ~= "table" or type(colorSchemes.ResolveEventColor) ~= "function" then
        return nil
    end
    local r, g, b = colorSchemes.ResolveEventColor(colorConfig)
    if r == nil or g == nil or b == nil then
        return nil
    end
    return {
        r = tonumber(r) or 1,
        g = tonumber(g) or 1,
        b = tonumber(b) or 1,
        a = tonumber(colorConfig.a) or 1,
    }
end

local function BuildStandaloneTrigger(enabled, source, label, lsm, path, offsetMode, offsetSeconds)
    return {
        enabled = (enabled == true),
        sourceType = tostring(source or "pack"),
        label = tostring(label or ""),
        customLSM = tostring(lsm or ""),
        customPath = tostring(path or ""),
        fixedOffsetMode = tostring(offsetMode or "delay"),
        fixedOffsetSeconds = tonumber(offsetSeconds) or 0,
    }
end

local function ResolveStandaloneSoundInfo(triggerCfg, triggerIndex)
    local voiceEngine = GetVoiceEngine()
    if not (voiceEngine and type(voiceEngine.ResolveStandaloneSound) == "function") then
        return nil
    end
    local ok, soundInfo = pcall(voiceEngine.ResolveStandaloneSound, voiceEngine, triggerCfg, {
        ignoreState = true,
        triggerIndex = tonumber(triggerIndex) or 0,
    })
    if ok and type(soundInfo) == "table" then
        return soundInfo
    end
    return nil
end

local function BuildVoicePlan(cfg, displayName)
    if type(cfg) ~= "table" then
        return nil
    end

    local trigger2Enabled = (cfg.countdownPlayName == true) or (cfg.voice2Enabled == true)

    local triggers = {
        [1] = BuildStandaloneTrigger(cfg.voice1Enabled, cfg.voice1Source, cfg.voice1Label, cfg.voice1LSM, cfg.voice1Path, cfg.voice1OffsetMode, cfg.voice1OffsetSeconds),
        [2] = BuildStandaloneTrigger(trigger2Enabled, cfg.voice2Source, cfg.voice2Label, cfg.voice2LSM, cfg.voice2Path, cfg.voice2OffsetMode, cfg.voice2OffsetSeconds),
    }

    local hasAny = false
    for trigger = 1, 2 do
        if triggers[trigger].enabled == true then
            hasAny = true
            break
        end
    end
    if not hasAny then
        return nil
    end

    return {
        enabled = true,
        source = "own",
        label = NormalizeText(cfg.voice1Label) ~= "" and tostring(cfg.voice1Label) or tostring(displayName or ""),
        triggers = triggers,
    }
end

local function BuildRingPlan(spellData)
    if type(spellData) ~= "table" then
        return nil
    end
    local castDuration = tonumber(spellData.castTime) or tonumber(spellData.castDuration) or tonumber(spellData.castTimeSet) or 0
    local channelDuration = tonumber(spellData.channelTime) or tonumber(spellData.channelDuration) or tonumber(spellData.channelTimeSet) or 0
    local out = {}
    if castDuration > 0 then
        out[#out + 1] = { duration = castDuration, castKind = "cast" }
    end
    if channelDuration > 0 then
        out[#out + 1] = { duration = channelDuration, castKind = "channel" }
    end
    if #out == 0 then
        return nil
    end
    return out
end

function Mod.RegisterTimelineEventMeta(eventID, meta)
    local eid = tonumber(eventID)
    if not eid or type(meta) ~= "table" then
        return
    end
    _timelineEventMeta[eid] = DeepCopy(meta)
end

function Mod.GetTimelineEventMeta(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local row = _timelineEventMeta[eid]
    return type(row) == "table" and row or nil
end

function Mod.ClearTimelineEventMeta(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return
    end
    _timelineEventMeta[eid] = nil
end

function Mod.ClearAllTimelineEventMeta()
    if wipe then
        wipe(_timelineEventMeta)
        return
    end
    for key in pairs(_timelineEventMeta) do
        _timelineEventMeta[key] = nil
    end
end

function Mod.BumpConfigRevision()
    _configRevision = (tonumber(_configRevision) or 0) + 1
    return _configRevision
end

function Mod.GetConfigRevision()
    return tonumber(_configRevision) or 0
end

function Mod.BuildResolvedMeta(runtime, mobData, spellData, fallbackIconFileID)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(spellData) ~= "table" then
        VoiceDebugPrint("meta skip reason=bad-input")
        return nil
    end
    if Mod.IsDisabledInCurrentEncounter() then
        VoiceDebugPrint("meta skip reason=boss-disabled")
        return nil
    end
    if not (Core and Core.IsEnabled and Core.IsEnabled() == true) then
        VoiceDebugPrint("meta skip reason=core-disabled")
        return nil
    end
    if not (Store and Store.UseTimelineScriptEvent and Store.UseTimelineScriptEvent() == true) then
        VoiceDebugPrint("meta skip reason=timeline-script-disabled")
        return nil
    end
    if not (Store and type(Store.GetResolvedSpellEntry) == "function") then
        VoiceDebugPrint("meta skip reason=no-store")
        return nil
    end

    local mapID = tonumber(runtime.matchedMapID) or tonumber(mobData.mapID)
    local npcID = tonumber(runtime.matchedNPCID) or tonumber(mobData.npcID)
    local spellID = tonumber(spellData.spellID)
    if not (mapID and npcID and spellID) then
        VoiceDebugPrint(string.format(
            "meta skip reason=bad-ids map=%s npc=%s spell=%s",
            tostring(mapID or runtime.matchedMapID or mobData.mapID or "nil"),
            tostring(npcID or runtime.matchedNPCID or mobData.npcID or "nil"),
            tostring(spellID or spellData.spellID or "nil")
        ))
        return nil
    end

    local cfg = Store.GetResolvedSpellEntry(mapID, npcID, spellID, false)
    if type(cfg) ~= "table" then
        VoiceDebugPrint(string.format("meta skip reason=no-cfg map=%s npc=%s spell=%s", tostring(mapID), tostring(npcID), tostring(spellID)))
        return nil
    end
    local roleKey = GetCurrentRoleKey()
    if not IsRoleEnabled(cfg, roleKey) then
        VoiceDebugPrint(string.format(
            "meta skip reason=role-disabled map=%s npc=%s spell=%s role=%s enabled=%s tank=%s heal=%s dps=%s voice1=%s voice2=%s",
            tostring(mapID),
            tostring(npcID),
            tostring(spellID),
            tostring(roleKey),
            tostring(cfg.enabled == true),
            tostring(cfg.tankEnabled == true),
            tostring(cfg.healerEnabled == true),
            tostring(cfg.dpsEnabled == true),
            tostring(cfg.voice1Enabled == true),
            tostring(cfg.voice2Enabled == true)
        ))
        return nil
    end
    if not IsPlacementAllowed(cfg, mapID) then
        VoiceDebugPrint(string.format(
            "meta skip reason=placement map=%s npc=%s spell=%s bossStages=%s",
            tostring(mapID),
            tostring(npcID),
            tostring(spellID),
            tostring(cfg.bossStages or "")
        ))
        return nil
    end

    local voiceBlacklist = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.VoiceBlacklist or nil
    local voiceBlock = voiceBlacklist and type(voiceBlacklist.GetEntry) == "function"
        and voiceBlacklist.GetEntry(mapID, npcID, spellID)
        or nil

    VoiceDebugPrint(string.format(
        "meta cfg-ok runtime=%s map=%s npc=%s spell=%s enabled=%s role=%s voice1=%s label1=%s voice2=%s label2=%s preAlert=%s countdownText=%s voiceBlocked=%s",
        tostring(runtime),
        tostring(mapID),
        tostring(npcID),
        tostring(spellID),
        tostring(cfg.enabled == true),
        tostring(roleKey),
        tostring(cfg.voice1Enabled == true),
        tostring(cfg.voice1Label or ""),
        tostring(cfg.voice2Enabled == true),
        tostring(cfg.voice2Label or ""),
        tostring(cfg.preAlertEnabled == true),
        tostring(cfg.countdownText or ""),
        tostring(type(voiceBlock) == "table")
    ))

    local defaultSpellName = BuildDefaultSpellName(spellData)
    local displayName = NormalizeText(cfg.customName)
    if displayName == "" then
        displayName = defaultSpellName
    end

    local timerBarName = displayName
    if cfg.timerBarRenameEnabled == true and NormalizeText(cfg.timerBarName) ~= "" then
        timerBarName = tostring(cfg.timerBarName)
    end

    local colorConfig = BuildColorConfig(cfg)
    local eventColor = BuildResolvedEventColor(colorConfig)

    local voicePlan = (type(voiceBlock) ~= "table") and BuildVoicePlan(cfg, displayName) or nil
    local progressEnabled = (cfg.ringEnabled == true or cfg.castProgressBarEnabled == true)
    local ringPlan = progressEnabled and BuildRingPlan(spellData) or nil
    local hideLongTimerBar = GetHideLongTimerBarConfig()
    local keepTimerBarAfterReady = GetKeepTimerBarAfterReadyConfig()
    local nameplateGrowthSide = (Store and type(Store.GetNameplateGrowthSide) == "function") and Store.GetNameplateGrowthSide() or "right"
    local triggerSounds = {}
    if type(voicePlan) == "table" and type(voicePlan.triggers) == "table" then
        if voicePlan.triggers[1] and voicePlan.triggers[1].enabled == true then
            triggerSounds[1] = ResolveStandaloneSoundInfo(voicePlan.triggers[1], 1)
        end
        if voicePlan.triggers[2] and voicePlan.triggers[2].enabled == true then
            triggerSounds[2] = ResolveStandaloneSoundInfo(voicePlan.triggers[2], 2)
        end
    end

    local countdownEnabled = (cfg.countdownEnabled == true) or (cfg.preAlertEnabled == true)
    local countdownLead = tonumber(cfg.countdownLead)
    if countdownLead == nil then
        countdownLead = 5
    end
    local countdownVoiceEnabled = (cfg.countdownVoiceEnabled == true) or (cfg.voice2Enabled == true)
    local countdownPlayName = (cfg.countdownPlayName == true) or (cfg.voice2Enabled == true)
    if type(voiceBlock) == "table" then
        countdownVoiceEnabled = false
        countdownPlayName = false
    end

    local meta = {
        mapID = mapID,
        npcID = npcID,
        spellID = spellID,
        roleKey = roleKey,
        bossStages = tostring(cfg.bossStages or ""),
        displayName = displayName,
        progressDisplayName = defaultSpellName,
        preferProgressSpellName = true,
        timerBarName = timerBarName,
        showBunBar = (cfg.showBunBar ~= false),
        showTimerBar = (cfg.showTimerBar ~= false),
        showNameplate = (cfg.showNameplate == true),
        nameplateSide = (tostring(nameplateGrowthSide or "right") == "left") and "left" or "right",
        iconFileID = tonumber(spellData.iconFileID) or tonumber(fallbackIconFileID) or (Data and Data.GetSpellIconSafe and Data.GetSpellIconSafe(spellID)) or 136243,
        countdownEnabled = (countdownEnabled == true),
        countdownLead = countdownLead,
        countdownVoiceEnabled = (countdownVoiceEnabled == true),
        countdownPlayName = (countdownPlayName == true),
        countdownText = NormalizeText(cfg.countdownText) ~= "" and tostring(cfg.countdownText) or nil,
        authorVoiceDisabled = type(voiceBlock) == "table",
        authorVoiceDisableReasonKey = type(voiceBlock) == "table" and tostring(voiceBlock.reasonKey or "") or nil,
        authorVoiceDisableReason = type(voiceBlock) == "table" and tostring(voiceBlock.reason or "") or nil,
        centralEnabled = (cfg.centralEnabled == true),
        centralLead = tonumber(cfg.centralLead) or 0,
        centralText = NormalizeText(cfg.centralText) ~= "" and tostring(cfg.centralText) or nil,
        colorConfig = colorConfig and DeepCopy(colorConfig) or nil,
        eventColor = eventColor and DeepCopy(eventColor) or nil,
        voicePlan = voicePlan and DeepCopy(voicePlan) or nil,
        voiceLabel = type(voicePlan) == "table" and NormalizeText(voicePlan.label) or "",
        triggerSounds = triggerSounds,
        ringEnabled = (cfg.ringEnabled == true and type(ringPlan) == "table"),
        ringRenameEnabled = (cfg.ringRenameEnabled == true),
        ringRenameText = NormalizeText(cfg.ringRenameText) ~= "" and tostring(cfg.ringRenameText) or nil,
        castProgressBarEnabled = (cfg.castProgressBarEnabled == true and type(ringPlan) == "table"),
        castProgressBarRenameEnabled = (cfg.castProgressBarRenameEnabled == true),
        castProgressBarRenameText = NormalizeText(cfg.castProgressBarRenameText) ~= "" and tostring(cfg.castProgressBarRenameText) or nil,
        ringCastCheckEnabled = (cfg.ringCastCheckEnabled == true),
        ringPlan = ringPlan and DeepCopy(ringPlan) or nil,
        timerBarHideAboveEnabled = hideLongTimerBar.enabled == true,
        timerBarHideAboveSeconds = hideLongTimerBar.seconds,
        keepTimerBarAfterReadyEnabled = keepTimerBarAfterReady.enabled == true,
        keepTimerBarAfterReadySeconds = keepTimerBarAfterReady.seconds,
    }
    return meta
end

function Mod.ApplyEncounterEventSettings(eventID, meta)
    local eid = tonumber(eventID)
    if not eid or type(meta) ~= "table" or not C_EncounterEvents then
        return
    end

    if C_EncounterEvents.SetEventColor then
        if type(meta.eventColor) == "table" then
            local color = CreateColor and CreateColor(meta.eventColor.r or 1, meta.eventColor.g or 1, meta.eventColor.b or 1) or {
                r = meta.eventColor.r or 1,
                g = meta.eventColor.g or 1,
                b = meta.eventColor.b or 1,
            }
            pcall(C_EncounterEvents.SetEventColor, eid, color)
        else
            pcall(C_EncounterEvents.SetEventColor, eid, nil)
        end
    end

    if C_EncounterEvents.SetEventSound then
        local triggerSounds = type(meta.triggerSounds) == "table" and meta.triggerSounds or nil
        pcall(C_EncounterEvents.SetEventSound, eid, 0, nil)
        pcall(C_EncounterEvents.SetEventSound, eid, 1, triggerSounds and triggerSounds[1] or nil)
        pcall(C_EncounterEvents.SetEventSound, eid, 2, triggerSounds and triggerSounds[2] or nil)
    end
end

function Mod.ClearEncounterEventSettings(eventID)
    local eid = tonumber(eventID)
    if not eid or not C_EncounterEvents then
        return
    end
    if C_EncounterEvents.SetEventSound then
        for trigger = 0, 2 do
            pcall(C_EncounterEvents.SetEventSound, eid, trigger, nil)
        end
    end
    if C_EncounterEvents.SetEventColor then
        pcall(C_EncounterEvents.SetEventColor, eid, nil)
    end
end

if ExwindTools and not Mod._stateWatchRegistered then
    local moduleKey = Store and type(Store.GetModuleKey) == "function" and Store.GetModuleKey() or "ExBoss.TrashCD.Settings"
    ExwindTools:WatchState(moduleKey .. ".ConfigChanged", "ExBoss.TrashCD.RuntimeConfig.ConfigChanged", function()
        Mod.BumpConfigRevision()
    end)
    ExwindTools:WatchState("RoleKey", "ExBoss.TrashCD.RuntimeConfig.RoleChanged", function()
        Mod.BumpConfigRevision()
    end)
    Mod._stateWatchRegistered = true
end
