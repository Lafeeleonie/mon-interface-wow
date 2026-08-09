local _, Addon = ...

local L = Addon.L

local Module = {
    id = "pve.rares",
    defaultEnabled = true,
}

local Service = {}
Addon.PveRares = Service

local questLookup, mapLookup = {}, {}
local completionCache = {}
local completionCacheReady = false
local questProbePending = false

for _, zone in ipairs(Addon.Data.PVE_RARES.zones) do
    mapLookup[tonumber(zone.mapID)] = true
    for _, rare in ipairs(zone.rares or {}) do
        questLookup[tonumber(rare.questID)] = true
        if rare.mapID then
            mapLookup[tonumber(rare.mapID)] = true
        end
    end
end

local function now()
    return type(time) == "function" and time() or 0
end

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function isRareMap(mapID)
    mapID = tonumber(mapID)
    local depth = 0
    while mapID and depth < 8 do
        if mapLookup[mapID] then
            return true
        end
        if not (C_Map and type(C_Map.GetMapInfo) == "function") then
            break
        end
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        mapID = ok and type(info) == "table" and tonumber(info.parentMapID) or nil
        depth = depth + 1
    end
    return false
end

local function isPlayerOnRareMap()
    if not (C_Map and type(C_Map.GetBestMapForUnit) == "function") then
        return false
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and isRareMap(mapID) or false
end

local function scanCompletionChanges()
    local changed = false
    for questID in pairs(questLookup) do
        local completed = Addon.QuestApi:IsCompleted(questID)
        if completionCacheReady and completed and completionCache[questID] == false then
            changed = true
        end
        completionCache[questID] = completed == true
    end
    completionCacheReady = true
    return changed
end

local function queueQuestProbe()
    if questProbePending or not isPlayerOnRareMap() then
        return
    end
    questProbePending = true
    local function run()
        questProbePending = false
        if isPlayerOnRareMap() and scanCompletionChanges() then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.05)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(
            0.55,
            Addon.PerformanceDiagnostics:Wrap(
                Module,
                "timer",
                "pve_rares.quest_probe",
                run
            )
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Module,
            "timer",
            "pve_rares.quest_probe",
            run
        )
        wrapped()
    end
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveRares or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    local resetAt = tonumber(snapshot.resetAt) or 0
    if resetAt > 0 and resetAt <= now() then
        record.snapshots.pveRares = nil
        return nil
    end
    return snapshot
end

function Service:GetSelectedZoneKey()
    local selected = Addon.Database:GetUI().selectedRareZoneKey
    for _, zone in ipairs(Addon.Data.PVE_RARES.zones) do
        if zone.key == selected then
            return selected
        end
    end
    return Addon.Data.PVE_RARES.zones[1] and Addon.Data.PVE_RARES.zones[1].key or nil
end

function Service:SetSelectedZoneKey(zoneKey)
    for _, zone in ipairs(Addon.Data.PVE_RARES.zones) do
        if zone.key == zoneKey then
            Addon.Database:GetUI().selectedRareZoneKey = zoneKey
            return true
        end
    end
    return false
end

function Service:SetWaypoint(rare)
    if type(rare) ~= "table" then
        return false
    end
    local ok = Addon.WoWApi:SetUserWaypoint(rare.mapID, rare.x, rare.y)
    if ok then
        Addon:Print(L.PVE_RARES_WAYPOINT_SET, rare.name or rare.label or L.PVE_RARES_WAYPOINT)
    else
        Addon:Print(L.PVE_RARES_WAYPOINT_UNAVAILABLE)
    end
    return ok
end

function Service:IsQuestID(questID)
    return questLookup[tonumber(questID)] == true
end

local function collectRares()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end
    local existing = Service:GetSnapshot(identity.key)
    local snapshot = Addon.PveRaresLogic:BuildSnapshot(existing)
    if snapshot then
        record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
        record.snapshots.pveRares = snapshot
    end
    return {
        characterKey = identity.key,
        snapshot = snapshot,
    }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectRares)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        scanCompletionChanges()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.90)
    end)
    Addon.EventBus:Subscribe("QUEST_LOG_UPDATE", self, function()
        if Addon:IsScreenActive("pve") then
            queueQuestProbe()
        end
    end)
    Addon.EventBus:Subscribe("QUEST_TURNED_IN", self, function(_, questID)
        questID = tonumber(questID)
        if questLookup[questID] then
            completionCache[questID] = true
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    scanCompletionChanges()
    Addon.RefreshScheduler:Invalidate(self.id, 0.45)
end

Addon.ModuleRegistry:Register(Module)
