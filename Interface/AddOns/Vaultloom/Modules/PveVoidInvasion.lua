local _, Addon = ...

local Module = {
    id = "pve.void_invasion",
    defaultEnabled = true,
}

local Service = {}
Addon.PveVoidInvasion = Service

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "TASK_PROGRESS_UPDATE",
    "ZONE_CHANGED_NEW_AREA",
}

local VALID_DIFFICULTIES = {
    normal = true,
    heroic = true,
}

local function now()
    return type(time) == "function" and time() or 0
end

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveVoidInvasion or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    local expectedVersion = tonumber(Addon.PveVoidInvasionLogic
        and Addon.PveVoidInvasionLogic.snapshotVersion)
    if expectedVersion and tonumber(snapshot.version) ~= expectedVersion then
        record.snapshots.pveVoidInvasion = nil
        return nil
    end
    local resetAt = tonumber(snapshot.resetAt) or 0
    if resetAt > 0 and resetAt <= now() then
        record.snapshots.pveVoidInvasion = nil
        return nil
    end
    return snapshot
end

function Service:GetPreferredDifficulty(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local difficulty = record and record.pveVoidInvasionDifficulty or nil
    return VALID_DIFFICULTIES[difficulty] and difficulty or nil
end

function Service:SetPreferredDifficulty(characterKey, difficulty)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    if not record or not VALID_DIFFICULTIES[difficulty] then
        return false
    end
    record.pveVoidInvasionDifficulty = difficulty
    return true
end

local function collectVoidInvasion()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end
    local snapshot = Addon.PveVoidInvasionLogic:BuildSnapshot(Service:GetSnapshot(identity.key))
    if snapshot then
        record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
        record.snapshots.pveVoidInvasion = snapshot
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
    Addon.RefreshScheduler:Register(self.id, self, collectVoidInvasion)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if event == "PLAYER_ENTERING_WORLD"
                or event == "QUEST_TURNED_IN"
                or Addon:IsScreenActive("pve")
            then
                local delay = event == "PLAYER_ENTERING_WORLD" and 0.95
                    or event == "ZONE_CHANGED_NEW_AREA" and 0.35
                    or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.60)
end

Addon.ModuleRegistry:Register(Module)
