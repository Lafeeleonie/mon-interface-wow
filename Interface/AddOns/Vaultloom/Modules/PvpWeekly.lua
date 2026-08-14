local _, Addon = ...

local Module = {
    id = "pvp.weekly",
    defaultEnabled = true,
}
local Service = {}
Addon.PvpWeekly = Service

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_DATA_LOAD_RESULT",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pvpWeekly or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    if Addon.WoWApi:IsResetExpired(snapshot.resetAt) then
        Addon.Database:ClearCharacterSnapshot(characterKey, "pvpWeekly", "expired")
        return nil
    end
    return snapshot
end

local function collectWeekly()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end
    local existing = Service:GetSnapshot(identity.key)
    local snapshot = Addon.PvpWeeklyLogic:BuildSnapshot(existing)
    if snapshot then
        local stored = Addon.Database:CommitCharacterSnapshot(
            identity.key,
            "pvpWeekly",
            snapshot,
            "refresh"
        )
        if not stored then snapshot = existing end
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
    Addon.RefreshScheduler:Register(self.id, self, collectWeekly)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" or Addon:IsScreenActive("pvp") then
                Addon.RefreshScheduler:Invalidate(Module.id, event == "PLAYER_ENTERING_WORLD" and 0.90 or 0.15)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pvp") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.55)
end

Addon.ModuleRegistry:Register(Module)
