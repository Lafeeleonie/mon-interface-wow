---@diagnostic disable: undefined-global, undefined-field

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.Trash.Runtime = ExBoss.Trash.Runtime or {}

local Mod = ExBoss.Trash.Runtime.ObservationTest or {}
ExBoss.Trash.Runtime.ObservationTest = Mod

local ET = _G.ExwindTools
local TrashData = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local TrashCore = ExBoss.TrashCD and ExBoss.TrashCD.Core or nil
local Inference = ExBoss.TrashCD and ExBoss.TrashCD.Inference or nil
local Observation = ExBoss.TrashCD and ExBoss.TrashCD.Observation or nil
local Calibration = ExBoss.TrashCD and ExBoss.TrashCD.Calibration or nil
local Output = ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
local NameplateMarker = ExBoss.TrashCD and ExBoss.TrashCD.NameplateMarker or nil
local TrashCache = ExBoss.TrashCD and ExBoss.TrashCD.TrashCache or nil
local HealthThreshold = ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.HealthThreshold or nil

local MAX_NAMEPLATES = 40
local SNAPSHOT_RETRY_DELAY = 0.12
local MARKER_REFRESH_DELAY = 1.0
local THREAT_REFRESH_TICK = 0.05
local THREAT_REFRESH_BATCH = 5
local THREAT_FOLLOWUP_DELAY = 0.10

local _encounterMapNameByInstanceID
local _encounterMapNameByMapID
local _trashMapIDByNameKey

Mod._running = Mod._running == true
Mod._uiEnabled = Mod._uiEnabled == true
Mod._unitFirstSeenAt = Mod._unitFirstSeenAt or {}
Mod._observedByUnit = Mod._observedByUnit or {}
Mod._runtimeByUnit = Mod._runtimeByUnit or {}
Mod._pendingUnitRefresh = Mod._pendingUnitRefresh or {}
Mod._pendingMarkerRefresh = Mod._pendingMarkerRefresh or {}
Mod._pendingThreatRefreshByKey = Mod._pendingThreatRefreshByKey or {}
Mod._pendingThreatRefreshQueue = Mod._pendingThreatRefreshQueue or {}
Mod._pendingThreatRefreshElapsed = tonumber(Mod._pendingThreatRefreshElapsed) or 0
Mod._debug = Mod._debug == true
Mod._debugNextPrintAt = Mod._debugNextPrintAt or {}
Mod._debugBuffer = Mod._debugBuffer or {}
Mod._debugBufferMax = tonumber(Mod._debugBufferMax) or 400
Mod._debugCopyFrame = Mod._debugCopyFrame

local CancelRuntimeScriptEvents

local function WipeTable(t)
    if type(t) ~= "table" then
        return {}
    end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local function RemoveThreatRefreshesForUnit(unit)
    if type(unit) ~= "string" then
        return
    end
    local index = unit:match("^nameplate(%d+)$")
    if not index then
        return
    end
    unit = "nameplate" .. index
    local byKey = type(Mod._pendingThreatRefreshByKey) == "table" and Mod._pendingThreatRefreshByKey or nil
    if not byKey then
        return
    end
    for key, record in pairs(byKey) do
        if type(record) == "table" and record.unit == unit then
            byKey[key] = nil
        end
    end
end

local function NormalizeNameKey(name)
    if TrashData and type(TrashData.NormalizeNameKey) == "function" then
        return TrashData.NormalizeNameKey(name)
    end
    local s = tostring(name or "")
    s = s:lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
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

local function DebugPrint(msg)
    if not Mod._debug then
        return
    end
    local stamp = date and date("%H:%M:%S") or "??:??:??"
    local line = string.format("[%s] ExBoss TrashMatch %s", tostring(stamp), tostring(msg or ""))
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or {}
    Mod._debugBuffer = buffer
    buffer[#buffer + 1] = line
    local maxLines = tonumber(Mod._debugBufferMax) or 400
    while #buffer > maxLines do
        table.remove(buffer, 1)
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashMatch|r " .. tostring(msg or ""))
    end
end

local function AppendBufferLine(tag, msg, echoToChat)
    local stamp = date and date("%H:%M:%S") or "??:??:??"
    local safeTag = tostring(tag or "External")
    local line = string.format("[%s] ExBoss %s %s", tostring(stamp), safeTag, tostring(msg or ""))
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or {}
    Mod._debugBuffer = buffer
    buffer[#buffer + 1] = line
    local maxLines = tonumber(Mod._debugBufferMax) or 400
    while #buffer > maxLines do
        table.remove(buffer, 1)
    end
    if echoToChat == true and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss " .. safeTag .. "|r " .. tostring(msg or ""))
    end
end

local function CacheDebug(msg)
    if not (ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true) then
        return
    end
    local stamp = date and date("%H:%M:%S") or "??:??:??"
    local line = string.format("[%s] ExBoss TrashCache %s", tostring(stamp), tostring(msg or ""))
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or {}
    Mod._debugBuffer = buffer
    buffer[#buffer + 1] = line
    local maxLines = tonumber(Mod._debugBufferMax) or 400
    while #buffer > maxLines do
        table.remove(buffer, 1)
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashCache|r " .. tostring(msg or ""))
    end
end

local function ShouldLogScheduleDecision(resolvedNPCID, canSchedule, keepLockedRuntime, runtime)
    if resolvedNPCID then
        return true
    end
    if canSchedule == true or keepLockedRuntime == true then
        return true
    end
    if type(runtime) ~= "table" then
        return false
    end
    if runtime.activeCastStartAt ~= nil or runtime.pendingSucceeded == true or runtime.pendingInterrupted == true then
        return true
    end
    return false
end

function Mod.ClearDebugBuffer()
    Mod._debugBuffer = {}
end

function Mod.GetDebugBufferText()
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or nil
    if not buffer or #buffer == 0 then
        return ""
    end
    return table.concat(buffer, "\n")
end

local function EnsureDebugCopyFrame()
    if type(Mod._debugCopyFrame) == "table" then
        return Mod._debugCopyFrame
    end

    local frame = CreateFrame("Frame", "EXBossTrashDebugCopyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(900, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("ExBoss Trash Debug Copy")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -46)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 18)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 24, self:GetVerticalScrollRange())))
    end)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(820)
    editBox:SetHeight(560)
    editBox:SetPoint("TOPLEFT", 0, 0)
    editBox:SetTextInsets(8, 8, 8, 8)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local textRegion = self.GetFontString and self:GetFontString() or nil
        local textHeight = textRegion and textRegion.GetStringHeight and textRegion:GetStringHeight() or 0
        self:SetHeight(math.max(560, textHeight + 24))
    end)
    scrollFrame:SetScrollChild(editBox)

    frame.editBox = editBox
    Mod._debugCopyFrame = frame
    return frame
end

function Mod.ShowDebugCopy()
    local frame = EnsureDebugCopyFrame()
    local text = Mod.GetDebugBufferText()
    if text == "" then
        text = "No trash debug logs captured."
    end
    frame:Show()
    frame.editBox:SetText(text)
    frame.editBox:SetCursorPosition(0)
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
end

function Mod.AppendExternalDebug(tag, msg, echoToChat)
    AppendBufferLine(tag, msg, echoToChat == true)
end

function Mod.SetDebug(...)
    local enabled = select(1, ...)
    if type(enabled) == "table" then
        enabled = select(2, ...)
    end
    Mod._debug = enabled == true
    if Mod._debug then
        DebugPrint("debug=on")
        if Mod.RefreshTargetDebug then
            Mod:RefreshTargetDebug("debug-on")
        end
    else
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashMatch|r debug=off")
        end
    end
end

function Mod.IsDebug()
    return Mod._debug == true
end

local function FormatBool(value)
    return value == true and "true" or "false"
end

local function GetStateValue(key)
    local state = ET and ET.State or nil
    return type(state) == "table" and state[key] or nil
end

local function BuildCandidateSummary(candidates, maxCount)
    if type(candidates) ~= "table" or #candidates == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, math.min(maxCount or 5, #candidates) do
        local c = candidates[i]
        parts[#parts + 1] = string.format("%s(%s)", tostring(c and c.name or "?"), tostring(c and c.npcID or "?"))
    end
    return table.concat(parts, ", ")
end

local function BuildLayer2DecisionSummary(debug, maxCount)
    if type(debug) ~= "table" or type(debug.decisions) ~= "table" or #debug.decisions == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, math.min(maxCount or 6, #debug.decisions) do
        local row = debug.decisions[i]
        parts[#parts + 1] = string.format(
            "%s(%s)=%s[%s]",
            tostring(row and row.name or "?"),
            tostring(row and row.npcID or "?"),
            row and row.keep == true and "keep" or "drop",
            tostring(row and row.reason or "?")
        )
    end
    return table.concat(parts, ", ")
end

local function PrintMatchDebug(unit, context)
    if not Mod._debug or type(context) ~= "table" then
        return
    end
    if unit ~= "target" then
        return
    end
    local now = GetTime()
    local nextAt = tonumber(Mod._debugNextPrintAt[unit]) or 0
    if now < nextAt then
        return
    end
    Mod._debugNextPrintAt[unit] = now + 0.8

    local obs = type(context.obs) == "table" and context.obs or {}
    local result = type(context.result) == "table" and context.result or {}
    local debug = context.layer1Debug or {}
    local layer2Debug = context.layer2Debug or {}
    local resolved = type(result.resolved) == "table" and result.resolved or nil
    local layer1 = type(result.layer1Candidates) == "table" and #result.layer1Candidates or 0
    local layer2 = type(result.candidates) == "table" and #result.candidates or 0
    local finalText = resolved and
    string.format("%s(%s)", tostring(resolved.name or "?"), tostring(resolved.npcID or "?")) or "???"

    DebugPrint(string.format(
        "unit=%s reason=%s inst=%s map=%s playerMap=%s zone=%s dungeon=%s stage=%s mplus=%s final=%s",
        tostring(unit or "?"),
        tostring(context.reason or "?"),
        tostring(context.instanceID or "nil"),
        tostring(context.trashMapID or "nil"),
        tostring(GetStateValue("MapID") or "nil"),
        tostring(GetStateValue("ZoneText") or "nil"),
        tostring(context.dungeonKey or ""),
        tostring(GetStateValue("DungeonBossProgressIndex") or "nil"),
        FormatBool(GetStateValue("InMythicPlus") == true),
        finalText
    ))
    DebugPrint(string.format(
        "obs level=%s sex=%s power=%s class=%s buff=%s rawBuff=%s mplusBuff-1=%s cast=%s channel=%s interrupt=%s combat=%s",
        tostring(obs.level or "nil"),
        tostring(obs.sex or "nil"),
        tostring(obs.power or "nil"),
        tostring(obs.classID or "nil"),
        tostring(obs.buffCount or "nil"),
        tostring(obs.rawBuffCount or "nil"),
        FormatBool(obs.mythicPlusBuffAdjusted == true),
        FormatBool(obs.sawCastStart == true),
        FormatBool(obs.sawChannelStart == true),
        FormatBool(obs.sawInterrupted == true),
        FormatBool(obs.inCombat == true)
    ))
    DebugPrint(string.format(
        "rows total=%s dungeon=%s tested=%s matched=%s L1=%s L2=%s normalizedDungeon=%s layerZone=%s",
        tostring(debug.totalRows or "nil"),
        tostring(debug.dungeonRows or "nil"),
        tostring(debug.testedRows or "nil"),
        tostring(debug.matchedRows or "nil"),
        tostring(layer1),
        tostring(layer2),
        tostring(debug.normalizedDungeonKey or ""),
        tostring(debug.zoneText or "nil")
    ))
    if debug.academyZoneExpectedNPCID ~= nil or tostring(context.trashMapID or "") == "2526" then
        DebugPrint(string.format(
            "academy-forces eligible=%s expectedNPC=%s reason=%s mplusForces=%s matchedAfterForces=%s rules=%s",
            tostring(debug.academyZoneRouteEligible or false),
            tostring(debug.academyZoneExpectedNPCID or "nil"),
            tostring(debug.academyZoneReason or "nil"),
            tostring(debug.mythicPlusForcesPercent or GetStateValue("MythicPlusForcesPercent") or "nil"),
            tostring(debug.matchedRows or "nil"),
            tostring(debug.academyZoneRules or "nil")
        ))
    end

    if type(result.layer1Candidates) == "table" and #result.layer1Candidates > 0 then
        DebugPrint("L1候选: " .. BuildCandidateSummary(result.layer1Candidates, 5))
    end

    if type(result.candidates) == "table" and #result.candidates > 0 then
        DebugPrint("L2候选: " .. BuildCandidateSummary(result.candidates, 5))
    end

    if type(layer2Debug) == "table" and type(layer2Debug.decisions) == "table" and #layer2Debug.decisions > 0 then
        DebugPrint(string.format(
            "L2过滤 kind=%s dur=%s narrowed=%s returnedOriginal=%s final=%s kept=%s",
            tostring(layer2Debug.behavior and layer2Debug.behavior.kind or "nil"),
            tostring(layer2Debug.behavior and layer2Debug.behavior.observedDuration or "nil"),
            FormatBool(layer2Debug.fingerprintNarrowed == true),
            FormatBool(layer2Debug.returnedOriginal == true),
            tostring(layer2Debug.finalCount or "nil"),
            BuildCandidateSummary(layer2Debug.kept, 5)
        ))
        DebugPrint("L2细节: " .. BuildLayer2DecisionSummary(layer2Debug, 6))
    end

    local samples = type(debug.samples) == "table" and debug.samples or {}
    for i = 1, math.min(5, #samples) do
        local s = samples[i]
        DebugPrint(string.format(
            "fail %s(%s) %s db=[%s/%s/%s/%s/%s]",
            tostring(s.name or "?"),
            tostring(s.npcID or "?"),
            tostring(s.reason or "?"),
            tostring(s.level or "nil"),
            tostring(s.sex or "nil"),
            tostring(s.power or "nil"),
            tostring(s.classID or "nil"),
            tostring(s.buffCount or "nil")
        ))
    end
end

local function GetMobTraits()
    if TrashData and type(TrashData.GetTrashMobTraitsRoot) == "function" then
        return TrashData.GetTrashMobTraitsRoot()
    end
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashMobTraitsRoot) == "function" then
        local ok, data = pcall(api.GetTrashMobTraitsRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_MOB_TRAITS")
    return type(raw) == "table" and raw or { rows = {} }
end

local function GetTrashCDDataRoot()
    if TrashData and type(TrashData.GetTrashCDDataRoot) == "function" then
        return TrashData.GetTrashCDDataRoot()
    end
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashCDDataRoot) == "function" then
        local ok, data = pcall(api.GetTrashCDDataRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_CD_DATA")
    return type(raw) == "table" and raw or {}
end

local function BuildTrashMapIDByNameKey()
    local out = {}
    local root = GetTrashCDDataRoot()
    for key, row in pairs(root) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or "")
            local nameKey = NormalizeNameKey(mapName)
            if mapID and mapID > 0 and nameKey ~= "" then
                out[nameKey] = mapID
            end
        end
    end
    return out
end

local function GetTrashMapIDByNameKey()
    if not _trashMapIDByNameKey then
        _trashMapIDByNameKey = BuildTrashMapIDByNameKey()
    end
    return _trashMapIDByNameKey
end

local function BuildEncounterMapNameByInstanceID()
    local out = {}
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetEncounterDataRoot) ~= "function" then
        return out
    end

    local ok, data = pcall(api.GetEncounterDataRoot)
    if not ok or type(data) ~= "table" then
        return out
    end

    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end

    for key, row in pairs(maps) do
        if type(row) == "table" then
            local instanceID = tonumber(row.instanceID) or tonumber(row.instanceId) or tonumber(row.mapID) or
            tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if instanceID and instanceID > 0 and mapName ~= "" then
                out[instanceID] = mapName
            end
        end
    end

    return out
end

local function BuildEncounterMapNameByMapID()
    local out = {}
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetEncounterDataRoot) ~= "function" then
        return out
    end

    local ok, data = pcall(api.GetEncounterDataRoot)
    if not ok or type(data) ~= "table" then
        return out
    end

    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end

    for key, row in pairs(maps) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if mapID and mapID > 0 and mapName ~= "" then
                out[mapID] = mapName
            end
        end
    end

    return out
end

local function GetEncounterMapNameByInstanceID()
    if not _encounterMapNameByInstanceID then
        _encounterMapNameByInstanceID = BuildEncounterMapNameByInstanceID()
    end
    return _encounterMapNameByInstanceID
end

local function GetEncounterMapNameByMapID()
    if not _encounterMapNameByMapID then
        _encounterMapNameByMapID = BuildEncounterMapNameByMapID()
    end
    return _encounterMapNameByMapID
end

local function GetCurrentInstanceContext()
    if TrashData and type(TrashData.GetCurrentInstanceContext) == "function" then
        return TrashData.GetCurrentInstanceContext()
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance ~= true then
        return nil, nil, instanceType
    end

    local state = ET and ET.State or nil
    local instanceID = tonumber(state and state.InstanceID) or tonumber((select(8, GetInstanceInfo()))) or 0
    local mapID = tonumber(state and state.MapID) or 0
    local instanceName = tostring((select(1, GetInstanceInfo())) or "")
    local mapName = ""

    if mapID > 0 then
        mapName = tostring(GetEncounterMapNameByMapID()[mapID] or "")
    end
    if instanceID > 0 and mapName == "" then
        mapName = tostring(GetEncounterMapNameByInstanceID()[instanceID] or "")
    end
    if mapName == "" then
        mapName = instanceName
    end

    return instanceID > 0 and instanceID or nil, mapName, instanceType
end

local function IsHostileNameplate(unit)
    return UnitExists(unit)
        and UnitCanAttack("player", unit)
        and not UnitIsDead(unit)
end

local function IsInInstanceForTest()
    local inInstance = IsInInstance()
    return inInstance == true
end

local function ShouldRunObservationTest()
    if TrashCore and type(TrashCore.ShouldRunMonitor) == "function" then
        return TrashCore.ShouldRunMonitor()
    end
    return Mod._uiEnabled == true and IsInInstanceForTest()
end

local function GetCurrentTrashMapID(dungeonKey)
    if Calibration and type(Calibration.GetCurrentTrashMapID) == "function" then
        return Calibration.GetCurrentTrashMapID(dungeonKey)
    end
    local byNameKey = GetTrashMapIDByNameKey()
    return tonumber(byNameKey[dungeonKey])
end

local function GetCurrentTrashContext()
    local instanceID, dungeonName = GetCurrentInstanceContext()
    local dungeonKey = NormalizeNameKey(dungeonName)
    return instanceID, dungeonName, dungeonKey, GetCurrentTrashMapID(dungeonKey)
end

local function BuildNameplateMarkerText(unit, resolved, runtime)
    local npcText = "???"
    if type(resolved) == "table" and resolved.npcID then
        npcText = tostring(resolved.npcID)
    end
    local unitText = tostring(unit or "?")
    local inCombat = false
    if type(runtime) == "table" then
        inCombat = runtime.engagedAt ~= nil
            or runtime.activeCastStartAt ~= nil
            or runtime.sawCastStart == true
            or runtime.sawChannelStart == true
            or runtime.pendingSucceeded == true
            or runtime.pendingInterrupted == true
    end
    if not inCombat and type(unit) == "string" then
        inCombat = UnitAffectingCombat(unit) == true
    end
    local combatText = inCombat and "|cff00ff00是|r" or "|cffff3030否|r"
    return string.format("%s\n%s 战斗:%s", npcText, unitText, combatText)
end

local function GetScheduler()
    return ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
end

local function BuildNameplateTimerRows(runtime)
    local scheduler = GetScheduler()
    if not (scheduler and type(scheduler.GetTrashNameplateTimers) == "function") then
        return {}
    end
    local rows = scheduler:GetTrashNameplateTimers(runtime, GetTime())
    if ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true then
        CacheDebug(string.format(
            "marker-rows runtime=%s matchedNPC=%s rows=%d",
            tostring(runtime),
            tostring(runtime and runtime.matchedNPCID or "nil"),
            #rows
        ))
    end
    return rows
end

local function GetRuntimeObs(unit)
    return Observation and Observation.GetRuntimeObs and Observation.GetRuntimeObs(Mod, unit) or nil
end

function Mod.NormalizeNameplateUnit(unit)
    return NormalizeNameplateUnit(unit)
end

function Mod.GetRuntimeByUnit(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    return GetRuntimeObs(unit)
end

local function TrackNameplate(unit)
    if TrashCache and type(TrashCache.OnNameplateAdded) == "function" then
        TrashCache.OnNameplateAdded(unit)
    end
    if Observation and type(Observation.TrackNameplate) == "function" then
        return Observation.TrackNameplate(Mod, unit, IsHostileNameplate)
    end
end

local function SyncUnitCDTimers(unit, obs, candidate, mapID)
    local runtime = GetRuntimeObs(unit)
    local candidateNPCID = tonumber(type(candidate) == "table" and candidate.npcID or nil)
    if HealthThreshold then
        if obs and candidateNPCID and mapID and type(HealthThreshold.ActivateTrashUnit) == "function" then
            HealthThreshold:ActivateTrashUnit(unit, mapID, candidateNPCID)
        elseif type(HealthThreshold.DeactivateTrashUnit) == "function" then
            HealthThreshold:DeactivateTrashUnit(unit)
        end
    end
    if Calibration and type(Calibration.SyncUnitCDTimers) == "function" then
        return Calibration.SyncUnitCDTimers(runtime, obs, candidate, mapID)
    end
end

local function UpdateUnitNameplate(unit, resolved, runtime)
    if not NameplateMarker then
        return
    end
    if type(NameplateMarker.SetUnitText) == "function" then
        NameplateMarker.SetUnitText(unit, BuildNameplateMarkerText(unit, resolved, runtime),
            type(resolved) == "table" and resolved.npcID ~= nil)
    end
    if type(NameplateMarker.SetUnitTimers) == "function" then
        local markerRows = {}
        local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
        if resolvedNPCID and type(runtime) == "table" and tonumber(runtime.matchedNPCID) == resolvedNPCID then
            markerRows = BuildNameplateTimerRows(runtime)
        end
        NameplateMarker.SetUnitTimers(unit, markerRows)
        if #markerRows > 0 then
            Mod:ScheduleMarkerRefresh(unit)
        end
    end
end

local function UntrackNameplate(unit)
    RemoveThreatRefreshesForUnit(unit)
    local runtime = GetRuntimeObs(unit)
    local keepPending = false
    if TrashCache and type(TrashCache.OnNameplateRemoved) == "function" then
        keepPending = TrashCache.OnNameplateRemoved(unit, runtime, CancelRuntimeScriptEvents) == true
    end
    if NameplateMarker and type(NameplateMarker.HideUnit) == "function" then
        NameplateMarker.HideUnit(unit)
    end
    if HealthThreshold and type(HealthThreshold.DeactivateTrashUnit) == "function" then
        HealthThreshold:DeactivateTrashUnit(unit)
    end
    if Observation and type(Observation.UntrackNameplate) == "function" then
        return Observation.UntrackNameplate(Mod, unit, keepPending and nil or CancelRuntimeScriptEvents)
    end
end

CancelRuntimeScriptEvents = function(runtime)
    if Output and type(Output.CancelRuntimeScriptEvents) == "function" then
        return Output.CancelRuntimeScriptEvents(runtime)
    end
end

function Mod:ScheduleUnitRefresh(unit, delay, reason, forceSnapshot)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    delay = math.max(0.01, tonumber(delay) or SNAPSHOT_RETRY_DELAY)
    local key = unit .. ":" .. tostring(reason or "refresh")
    if self._pendingUnitRefresh[key] then
        return
    end
    self._pendingUnitRefresh[key] = true
    C_Timer.After(delay, function()
        self._pendingUnitRefresh[key] = nil
        if self._running == true then
            self:RefreshUnit(unit, reason or "delayed", forceSnapshot == true)
        end
    end)
end

function Mod:QueueThreatRefresh(unit, reason, delay, forceSnapshot)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return false
    end

    local key = tostring(unit) .. ":" .. tostring(reason or "threat")
    local dueAt = GetTime() + math.max(0, tonumber(delay) or 0)
    local byKey = self._pendingThreatRefreshByKey
    local queue = self._pendingThreatRefreshQueue
    local existing = byKey[key]

    if type(existing) == "table" then
        if dueAt < (tonumber(existing.dueAt) or dueAt) then
            existing.dueAt = dueAt
        end
        if forceSnapshot == true then
            existing.forceSnapshot = true
        end
        return false
    end

    local record = {
        key = key,
        unit = unit,
        reason = tostring(reason or "threat"),
        dueAt = dueAt,
        forceSnapshot = forceSnapshot == true,
    }
    byKey[key] = record
    queue[#queue + 1] = record
    return true
end

function Mod:ProcessThreatRefreshQueue(now)
    local queue = self._pendingThreatRefreshQueue
    local byKey = self._pendingThreatRefreshByKey
    if type(queue) ~= "table" or #queue == 0 then
        return 0
    end

    now = tonumber(now) or GetTime()
    local processed = 0
    local remaining = {}

    for i = 1, #queue do
        local record = queue[i]
        if type(record) == "table" and byKey[record.key] == record then
            if processed < THREAT_REFRESH_BATCH and now >= (tonumber(record.dueAt) or now) then
                byKey[record.key] = nil
                processed = processed + 1
                if self._running == true then
                    self:RefreshUnit(record.unit, record.reason, record.forceSnapshot == true)
                end
            else
                remaining[#remaining + 1] = record
            end
        end
    end

    self._pendingThreatRefreshQueue = remaining
    return processed
end

function Mod:EnsureThreatRefreshDriver()
    self._threatRefreshFrame = self._threatRefreshFrame or CreateFrame("Frame")
    if self._threatRefreshFrame:GetScript("OnUpdate") then
        return
    end
    self._pendingThreatRefreshElapsed = 0
    self._threatRefreshFrame:SetScript("OnUpdate", function(_, elapsed)
        Mod._pendingThreatRefreshElapsed = (tonumber(Mod._pendingThreatRefreshElapsed) or 0) + (tonumber(elapsed) or 0)
        if Mod._pendingThreatRefreshElapsed < THREAT_REFRESH_TICK then
            return
        end
        Mod._pendingThreatRefreshElapsed = 0

        if Mod._running ~= true then
            if type(Mod._pendingThreatRefreshQueue) == "table" then
                Mod._pendingThreatRefreshQueue = {}
            end
            if type(Mod._pendingThreatRefreshByKey) == "table" then
                wipe(Mod._pendingThreatRefreshByKey)
            end
            Mod._threatRefreshFrame:SetScript("OnUpdate", nil)
            return
        end

        Mod:ProcessThreatRefreshQueue(GetTime())
        if type(Mod._pendingThreatRefreshQueue) ~= "table" or #Mod._pendingThreatRefreshQueue == 0 then
            Mod._threatRefreshFrame:SetScript("OnUpdate", nil)
        end
    end)
end

function Mod:ScheduleMarkerRefresh(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    if self._pendingMarkerRefresh[unit] then
        return
    end
    self._pendingMarkerRefresh[unit] = true
    C_Timer.After(MARKER_REFRESH_DELAY, function()
        self._pendingMarkerRefresh[unit] = nil
        if self._running == true then
            self:RefreshUnitMarker(unit)
        end
    end)
end

function Mod:RefreshUnitMarker(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not IsHostileNameplate(unit) then
        UntrackNameplate(unit)
        return
    end
    local runtime = GetRuntimeObs(unit)
    if not runtime or not runtime.matchedNPCID then
        if NameplateMarker and type(NameplateMarker.SetUnitTimers) == "function" then
            NameplateMarker.SetUnitTimers(unit, {})
        end
        return
    end
    local resolved = {
        npcID = tonumber(runtime.matchedNPCID),
        name = runtime.lastResolvedName,
    }
    UpdateUnitNameplate(unit, resolved, runtime)
end

function Mod:RefreshUnit(unit, reason, forceSnapshot)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    if not ShouldRunObservationTest() then
        self:Stop()
        return
    end
    if not IsHostileNameplate(unit) then
        UntrackNameplate(unit)
        return
    end
    if not (Observation and type(Observation.CollectTrackedNameplate) == "function" and Inference and type(Inference.ResolveCandidates) == "function") then
        return
    end

    local instanceID, _dungeonName, dungeonKey, trashMapID = GetCurrentTrashContext()
    if not instanceID or dungeonKey == "" then
        PrintMatchDebug(unit, {
            reason = "no-trash-context",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
        })
        UntrackNameplate(unit)
        return
    end

    local obs = Observation.CollectTrackedNameplate(Mod, unit, IsHostileNameplate, CancelRuntimeScriptEvents,
        forceSnapshot == true)
    if not obs then
        UntrackNameplate(unit)
        return
    end
    if obs.pending == true then
        PrintMatchDebug(unit, {
            reason = "snapshot-pending",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
            obs = obs,
        })
        if NameplateMarker and type(NameplateMarker.SetUnitText) == "function" then
            NameplateMarker.SetUnitText(unit, BuildNameplateMarkerText(unit, nil, GetRuntimeObs(unit)), false)
        end
        if NameplateMarker and type(NameplateMarker.SetUnitTimers) == "function" then
            NameplateMarker.SetUnitTimers(unit, {})
        end
        self:ScheduleUnitRefresh(unit, tonumber(obs.retryAfter) or SNAPSHOT_RETRY_DELAY, "snapshot", true)
        return
    end

    local traits = GetMobTraits()
    local traitRows = type(traits.rows) == "table" and traits.rows or {}
    local runtime = GetRuntimeObs(unit)
    local result = Inference.ResolveCandidates(obs, dungeonKey, traitRows, runtime, trashMapID, GetTime())
    local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
    local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil
    local layer1Debug = Layer1 and type(Layer1.GetLastDebug) == "function" and Layer1.GetLastDebug() or nil
    local layer2Debug = Layer2 and type(Layer2.GetLastDebug) == "function" and Layer2.GetLastDebug() or nil
    PrintMatchDebug(unit, {
        reason = reason,
        instanceID = instanceID,
        dungeonKey = dungeonKey,
        trashMapID = trashMapID,
        obs = obs,
        result = result,
        layer1Debug = layer1Debug,
        layer2Debug = layer2Debug,
    })
    local resolved = type(result) == "table" and result.resolved or nil
    local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
    local restored = false
    if resolvedNPCID and runtime and TrashCache and type(TrashCache.TryRestoreRuntime) == "function" then
        restored = TrashCache.TryRestoreRuntime(unit, runtime, resolved) == true
        CacheDebug(string.format(
            "refresh unit=%s reason=%s resolvedNPC=%s restored=%s combat=%s matchedNPC=%s",
            tostring(unit),
            tostring(reason or "?"),
            tostring(resolvedNPCID),
            tostring(restored),
            tostring(obs and obs.inCombat == true),
            tostring(runtime and runtime.matchedNPCID or "nil")
        ))
    end
    local canSchedule = (obs.inCombat == true)
    local keepLockedRuntime = resolvedNPCID == nil
        and canSchedule == true
        and type(runtime) == "table"
        and tonumber(runtime.matchedNPCID) ~= nil
    if type(runtime) == "table" then
        runtime._debugUnit = unit
    end
    if Mod._debug == true and ShouldLogScheduleDecision(resolvedNPCID, canSchedule, keepLockedRuntime, runtime) then
        local threat = nil
        local detailedThreatStatus = nil
        local detailedThreatPct = nil
        local detailedThreatRawPct = nil
        local detailedThreatValue = nil
        if type(UnitThreatSituation) == "function" then
            local okThreat, value = pcall(UnitThreatSituation, "player", unit)
            if okThreat then
                threat = value
            end
        end
        if type(UnitDetailedThreatSituation) == "function" then
            local okDetailed, _, status, pct, rawPct, threatValue = pcall(UnitDetailedThreatSituation, "player", unit)
            if okDetailed then
                detailedThreatStatus = status
                detailedThreatPct = pct
                detailedThreatRawPct = rawPct
                detailedThreatValue = threatValue
            end
        end
        DebugPrint(string.format(
            "schedule-check unit=%s resolved=%s canSchedule=%s unitCombat=%s playerCombat=%s threat=%s detailedStatus=%s pct=%s rawPct=%s value=%s activeCast=%s pendingSuccess=%s pendingInterrupt=%s action=%s",
            tostring(unit or "?"),
            tostring(resolvedNPCID or "nil"),
            FormatBool(canSchedule == true),
            FormatBool(obs.inCombat == true),
            FormatBool(UnitAffectingCombat("player") == true),
            tostring(threat or "nil"),
            tostring(detailedThreatStatus or "nil"),
            tostring(detailedThreatPct or "nil"),
            tostring(detailedThreatRawPct or "nil"),
            tostring(detailedThreatValue or "nil"),
            FormatBool(type(runtime) == "table" and runtime.activeCastStartAt ~= nil),
            FormatBool(type(runtime) == "table" and runtime.pendingSucceeded == true),
            FormatBool(type(runtime) == "table" and runtime.pendingInterrupted == true),
            (resolvedNPCID and canSchedule) and "sync" or (keepLockedRuntime and "keep-locked" or "reset")
        ))
        if resolvedNPCID == nil then
            DebugPrint(string.format(
                "schedule-candidates unit=%s L1=%s L2=%s matchedNPC=%s kept=%s",
                tostring(unit or "?"),
                BuildCandidateSummary(type(result.layer1Candidates) == "table" and result.layer1Candidates or nil, 5),
                BuildCandidateSummary(type(result.candidates) == "table" and result.candidates or nil, 5),
                tostring(type(runtime) == "table" and runtime.matchedNPCID or "nil"),
                BuildCandidateSummary(type(layer2Debug) == "table" and layer2Debug.kept or nil, 5)
            ))
            if type(layer2Debug) == "table" and type(layer2Debug.decisions) == "table" and #layer2Debug.decisions > 0 then
                DebugPrint("schedule-layer2 unit=" .. tostring(unit or "?") .. " " .. BuildLayer2DecisionSummary(layer2Debug, 6))
            end
        end
    end

    if resolvedNPCID and canSchedule then
        if runtime and resolved.name then
            runtime.lastResolvedName = resolved.name
        end
        SyncUnitCDTimers(unit, obs, resolved, trashMapID)
    elseif keepLockedRuntime then
        -- 单帧快照可能因为施法/引导状态变化而无法重新推理 NPC。
        -- 已锁定且仍在战斗中时保留 runtime，避免正在处理的技能和本地 CD 被清空。
    else
        SyncUnitCDTimers(unit, nil, nil, nil)
    end

    local displayResolved = resolved
    if keepLockedRuntime and type(runtime) == "table" then
        displayResolved = {
            npcID = tonumber(runtime.matchedNPCID),
            name = runtime.lastResolvedName,
        }
    end
    UpdateUnitNameplate(unit, displayResolved, runtime)
end

function Mod:RefreshTargetDebug(reason)
    if not Mod._debug then
        return
    end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        PrintMatchDebug("target", { reason = "no-hostile-target" })
        return
    end
    if not (Observation and type(Observation.CollectObservedUnit) == "function" and Inference and type(Inference.ResolveCandidates) == "function") then
        PrintMatchDebug("target", { reason = "missing-runtime-modules" })
        return
    end

    local instanceID, _dungeonName, dungeonKey, trashMapID = GetCurrentTrashContext()
    if not instanceID or dungeonKey == "" then
        PrintMatchDebug("target", {
            reason = "no-trash-context",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
        })
        return
    end

    local obs = Observation.CollectObservedUnit("target")
    if type(obs) ~= "table" then
        PrintMatchDebug("target", {
            reason = "collect-target-failed",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
        })
        return
    end

    obs.unit = "target"
    obs.inCombat = UnitAffectingCombat("target") == true

    local traits = GetMobTraits()
    local traitRows = type(traits.rows) == "table" and traits.rows or {}
    local runtime = Mod._targetDebugRuntime or {}
    Mod._targetDebugRuntime = runtime
    local result = Inference.ResolveCandidates(obs, dungeonKey, traitRows, runtime, trashMapID, GetTime())
    local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
    local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil
    local layer1Debug = Layer1 and type(Layer1.GetLastDebug) == "function" and Layer1.GetLastDebug() or nil
    local layer2Debug = Layer2 and type(Layer2.GetLastDebug) == "function" and Layer2.GetLastDebug() or nil

    PrintMatchDebug("target", {
        reason = reason or "target",
        instanceID = instanceID,
        dungeonKey = dungeonKey,
        trashMapID = trashMapID,
        obs = obs,
        result = result,
        layer1Debug = layer1Debug,
        layer2Debug = layer2Debug,
    })
end

function Mod:RefreshAllActiveNameplates(reason, forceSnapshot)
    if not ShouldRunObservationTest() then
        self:Stop()
        return
    end
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if IsHostileNameplate(unit) then
            TrackNameplate(unit)
            self:RefreshUnit(unit, reason or "full", forceSnapshot == true)
            if forceSnapshot ~= true then
                self:ScheduleUnitRefresh(unit, SNAPSHOT_RETRY_DELAY, "snapshot", true)
            end
        else
            UntrackNameplate(unit)
        end
    end
end

function Mod:Start()
    self._running = true
    local AuraDelta = ExBoss.TrashCD and ExBoss.TrashCD.AuraDelta or nil
    if AuraDelta and type(AuraDelta.SetEnabled) == "function" then
        AuraDelta.SetEnabled(true)
    end
    self:RefreshAllActiveNameplates("start", false)
end

function Mod:Stop()
    for _, runtime in pairs(self._runtimeByUnit or {}) do
        CancelRuntimeScriptEvents(runtime)
    end
    if NameplateMarker and type(NameplateMarker.HideAll) == "function" then
        NameplateMarker.HideAll()
    end
    if HealthThreshold and type(HealthThreshold.DeactivateAllTrashUnits) == "function" then
        HealthThreshold:DeactivateAllTrashUnits()
    end
    self._running = false
    WipeTable(self._unitFirstSeenAt)
    WipeTable(self._observedByUnit)
    WipeTable(self._runtimeByUnit)
    WipeTable(self._pendingUnitRefresh)
    WipeTable(self._pendingMarkerRefresh)
    WipeTable(self._pendingThreatRefreshByKey)
    self._pendingThreatRefreshQueue = {}
    self._pendingThreatRefreshElapsed = 0
    if self._threatRefreshFrame then
        self._threatRefreshFrame:SetScript("OnUpdate", nil)
    end
    if TrashCache and type(TrashCache.Reset) == "function" then
        TrashCache.Reset()
    end
    local AuraDelta = ExBoss.TrashCD and ExBoss.TrashCD.AuraDelta or nil
    if AuraDelta and type(AuraDelta.SetEnabled) == "function" then
        AuraDelta.SetEnabled(false)
    end
end

function Mod:EnsureRunning()
    if not ShouldRunObservationTest() then
        self:Stop()
        return false
    end
    if self._running ~= true then
        self:Start()
    end
    return self._running == true
end

local function MarkRuntimeObservation(unit, key)
    if Observation and type(Observation.MarkRuntimeObservation) == "function" then
        return Observation.MarkRuntimeObservation(Mod, unit, key)
    end
end

local function BeginRuntimeCast(unit, kind, castBarID)
    if Observation and type(Observation.BeginRuntimeCast) == "function" then
        return Observation.BeginRuntimeCast(Mod, unit, kind, castBarID)
    end
end

local function MarkRuntimeInterruptible(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeInterruptible) == "function" then
        return Observation.MarkRuntimeInterruptible(Mod, unit, castBarID)
    end
end

local function MarkRuntimeCastStop(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeCastStop) == "function" then
        return Observation.MarkRuntimeCastStop(Mod, unit, castBarID)
    end
end

local function MarkRuntimeInterrupted(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeInterrupted) == "function" then
        return Observation.MarkRuntimeInterrupted(Mod, unit, castBarID)
    end
end

local function MarkRuntimeChannelStop(unit, castBarID, interruptedBy)
    if Observation and type(Observation.MarkRuntimeChannelStop) == "function" then
        return Observation.MarkRuntimeChannelStop(Mod, unit, castBarID, interruptedBy)
    end
end

local function MarkRuntimeUnitTarget(unit)
    if Observation and type(Observation.MarkRuntimeUnitTarget) == "function" then
        return Observation.MarkRuntimeUnitTarget(Mod, unit)
    end
end

local function Register(event, owner, func)
    if ET and ET.RegisterEvent then
        ET:RegisterEvent(event, owner, func)
    end
end

local function OnThreatListUpdate(_, event, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod:EnsureRunning() then
        Mod:QueueThreatRefresh(unit, "threat-list-update", 0, true)
        Mod:QueueThreatRefresh(unit, "threat-followup", THREAT_FOLLOWUP_DELAY, true)
        Mod:EnsureThreatRefreshDriver()
        if Mod._debug == true then
            local unitName = UnitExists(unit) and UnitName(unit) or "nil"
            local unitCombat = UnitAffectingCombat(unit) == true
            local threat = nil
            local detailedThreatStatus = nil
            if type(UnitThreatSituation) == "function" then
                local okThreat, value = pcall(UnitThreatSituation, "player", unit)
                if okThreat then
                    threat = value
                end
            end
            if type(UnitDetailedThreatSituation) == "function" then
                local okDetailed, _, status = pcall(UnitDetailedThreatSituation, "player", unit)
                if okDetailed then
                    detailedThreatStatus = status
                end
            end
            DebugPrint(string.format(
                "threat-event unit=%s name=%s unitCombat=%s threat=%s detailedStatus=%s",
                tostring(unit),
                tostring(unitName or "nil"),
                FormatBool(unitCombat),
                tostring(threat or "nil"),
                tostring(detailedThreatStatus or "nil")
            ))
        end
    end
end

Register("PLAYER_ENTERING_WORLD", "ExBoss_Trash_Observation_PEW", function()
    if ShouldRunObservationTest() then
        Mod:Start()
    else
        Mod:Stop()
    end
end)

Register("PLAYER_REGEN_DISABLED", "ExBoss_Trash_Observation_CombatStart", function()
    if not ShouldRunObservationTest() then
        Mod:Stop()
    elseif Mod._running ~= true then
        Mod:Start()
    else
        Mod:RefreshAllActiveNameplates("combat-start", true)
    end
end)

Register("PLAYER_REGEN_ENABLED", "ExBoss_Trash_Observation_CombatEnd", function()
    if ShouldRunObservationTest() then
        Mod:RefreshAllActiveNameplates("combat-end", true)
    else
        Mod:Stop()
    end
end)

Register("PLAYER_TARGET_CHANGED", "ExBoss_Trash_Observation_TargetDebug", function()
    if Mod._debug == true then
        Mod:RefreshTargetDebug("target-changed")
    end
end)

Register("NAME_PLATE_UNIT_ADDED", "ExBoss_Trash_Observation_NPA", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod:EnsureRunning() then
        if Mod._debug == true then
            DebugPrint(string.format(
                "nameplate-added unit=%s name=%s unitCombat=%s",
                tostring(unit),
                tostring(UnitExists(unit) and UnitName(unit) or "nil"),
                FormatBool(UnitExists(unit) and UnitAffectingCombat(unit) == true)
            ))
        end
        TrackNameplate(unit)
        Mod:RefreshUnit(unit, "nameplate-added", false)
        Mod:ScheduleUnitRefresh(unit, SNAPSHOT_RETRY_DELAY, "snapshot", true)
    end
end)

Register("NAME_PLATE_UNIT_REMOVED", "ExBoss_Trash_Observation_NPR", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._debug == true then
        local runtime = GetRuntimeObs(unit)
        DebugPrint(string.format(
            "nameplate-removed unit=%s name=%s resolvedNPC=%s activeCast=%s engagedAt=%s",
            tostring(unit),
            tostring(UnitExists(unit) and UnitName(unit) or "nil"),
            tostring(type(runtime) == "table" and runtime.matchedNPCID or "nil"),
            FormatBool(type(runtime) == "table" and runtime.activeCastStartAt ~= nil),
            tostring(type(runtime) == "table" and runtime.engagedAt or "nil")
        ))
    end
    UntrackNameplate(unit)
end)

Mod._threatEventFrame = Mod._threatEventFrame or CreateFrame("Frame")
Mod._threatEventFrame:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
Mod._threatEventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
Mod._threatEventFrame:SetScript("OnEvent", OnThreatListUpdate)

Register("UNIT_DISPLAYPOWER", "ExBoss_Trash_Observation_DisplayPower", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        Mod:RefreshUnit(unit, "display-power", true)
    end
end)

Register("UNIT_HEALTH", "ExBoss_Trash_Observation_UnitHealth", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or Mod._running ~= true then
        return
    end
    if UnitIsDead(unit) then
        if TrashCache and type(TrashCache.OnUnitDead) == "function" then
            TrashCache.OnUnitDead(unit)
        end
        UntrackNameplate(unit)
    end
end)

Register("UNIT_DIED", "ExBoss_Trash_Observation_UnitDied", function(_, unitGUID)
    if Mod._running ~= true then
        return
    end
    if TrashCache and type(TrashCache.OnCombatLogUnitDied) == "function" then
        TrashCache.OnCombatLogUnitDied(unitGUID)
    end
end)

Register("UNIT_TARGET", "ExBoss_Trash_Observation_UnitTarget", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeUnitTarget(unit)
    end
end)

Register("UNIT_SPELLCAST_START", "ExBoss_Trash_Observation_CastStart", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod:EnsureRunning() then
        MarkRuntimeObservation(unit, "sawCastStart")
        local started = BeginRuntimeCast(unit, "cast", castBarID)
        Mod:RefreshUnit(unit, "cast-start", true)
        if started ~= false and Output and type(Output.PlayRuntimeCastStartVoice) == "function" then
            Output.PlayRuntimeCastStartVoice(GetRuntimeObs(unit), "cast")
        end
    end
end)

Register("UNIT_SPELLCAST_CHANNEL_START", "ExBoss_Trash_Observation_ChannelStart",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod:EnsureRunning() then
            MarkRuntimeObservation(unit, "sawChannelStart")
            local started = BeginRuntimeCast(unit, "channel", castBarID)
            Mod:RefreshUnit(unit, "channel-start", true)
            if started ~= false and Output and type(Output.PlayRuntimeCastStartVoice) == "function" then
                Output.PlayRuntimeCastStartVoice(GetRuntimeObs(unit), "channel")
            end
        end
    end)

Register("UNIT_SPELLCAST_INTERRUPTIBLE", "ExBoss_Trash_Observation_Interruptible",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeInterruptible(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-interruptible", true)
        end
    end)

Register("UNIT_SPELLCAST_INTERRUPTED", "ExBoss_Trash_Observation_Interrupted",
    function(_, unit, _castGUID, _spellID, _interruptedBy, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeObservation(unit, "sawInterrupted")
            MarkRuntimeInterrupted(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-interrupted", true)
        end
    end)

Register("UNIT_SPELLCAST_FAILED", "ExBoss_Trash_Observation_Failed", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeObservation(unit, "sawInterrupted")
        MarkRuntimeInterrupted(unit, castBarID)
        Mod:RefreshUnit(unit, "cast-failed", true)
    end
end)

Register("UNIT_SPELLCAST_FAILED_QUIET", "ExBoss_Trash_Observation_FailedQuiet",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeObservation(unit, "sawInterrupted")
            MarkRuntimeInterrupted(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-failed-quiet", true)
        end
    end)

Register("UNIT_SPELLCAST_STOP", "ExBoss_Trash_Observation_CastStop", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeCastStop(unit, castBarID)
        Mod:RefreshUnit(unit, "cast-stop", true)
    end
end)

Register("UNIT_SPELLCAST_CHANNEL_STOP", "ExBoss_Trash_Observation_ChannelStop",
    function(_, unit, _castGUID, _spellID, interruptedBy, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeChannelStop(unit, castBarID, interruptedBy)
            Mod:RefreshUnit(unit, "channel-stop", true)
        end
    end)

function Mod:SetUIEnabled(enabled)
    self._uiEnabled = (enabled == true)
    if TrashCore and type(TrashCore.SetMonitorUIEnabled) == "function" then
        TrashCore.SetMonitorUIEnabled(enabled == true)
    end
    if ShouldRunObservationTest() then
        self:Start()
    else
        self:Stop()
    end
end
