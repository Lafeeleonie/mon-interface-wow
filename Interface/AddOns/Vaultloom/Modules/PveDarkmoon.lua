local _, Addon = ...

local Module = {
    id = "pve.darkmoon",
    defaultEnabled = true,
}
local Service = {}
Addon.PveDarkmoon = Service

local ACTIVE_REFRESH_EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_DATA_LOAD_RESULT",
    "BAG_UPDATE_DELAYED",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function clearSnapshot(characterKey)
    Addon.Database:ClearCharacterSnapshot(characterKey, "pveDarkmoon", "expired")
end

function Service:GetSnapshot(characterKey)
    local detectorState = Addon.DarkmoonDetector:GetState()
    if detectorState.active ~= true then
        return nil
    end
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveDarkmoon or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    if Addon.WoWApi:IsResetExpired(snapshot.dailyResetAt)
        or Addon.WoWApi:IsResetExpired(snapshot.faireEndAt)
        or (snapshot.faireResetKey and detectorState.resetKey and snapshot.faireResetKey ~= detectorState.resetKey)
    then
        clearSnapshot(characterKey)
        return nil
    end
    return snapshot
end

local function collectDarkmoon()
    local detectorState = Addon.DarkmoonDetector:GetState()
    if detectorState.active ~= true then
        return {
            active = false,
            source = detectorState.source,
            resetKey = detectorState.resetKey,
        }
    end

    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return {
            active = true,
            source = detectorState.source,
            resetKey = detectorState.resetKey,
        }
    end
    local existing = Service:GetSnapshot(identity.key)
    local snapshot = Addon.PveDarkmoonLogic:BuildSnapshot(detectorState, existing)
    if snapshot then
        local stored = Addon.Database:CommitCharacterSnapshot(identity.key, "pveDarkmoon", snapshot, "refresh")
        if not stored then snapshot = existing end
    end
    return {
        active = true,
        characterKey = identity.key,
        snapshot = snapshot,
        source = detectorState.source,
        resetKey = detectorState.resetKey,
        endAt = detectorState.endAt,
    }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectDarkmoon)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        Addon.DarkmoonDetector:RequestCalendar()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.90)
    end)
    Addon.EventBus:Subscribe("CALENDAR_UPDATE_EVENT_LIST", self, function()
        Addon.DarkmoonDetector:ClearCache()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.10)
    end)
    for _, eventName in ipairs(ACTIVE_REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            local state = Addon.StateStore:Get(Module.id)
            if type(state) == "table"
                and state.active == true
                and (event == "QUEST_TURNED_IN" or Addon:IsScreenActive("pve"))
            then
                local delay = event == "BAG_UPDATE_DELAYED" and 0.25 or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.50)
end

Addon.ModuleRegistry:Register(Module)
