local _, Addon = ...

local Module = {
    id = "pve.weekly",
    defaultEnabled = true,
}

local Service = {}
Addon.PveWeekly = Service

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function getAccountState()
    local db = Addon.Database:Get()
    db.pveWeekly = type(db.pveWeekly) == "table" and db.pveWeekly or {}
    db.pveWeekly.omniumFolioComplete = db.pveWeekly.omniumFolioComplete == true
    return db.pveWeekly
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveWeekly or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    Addon.PveWeeklyLogic:ApplyAccountHides(snapshot, getAccountState())
    if Addon.WoWApi:IsResetExpired(snapshot.resetAt) then
        Addon.Database:ClearCharacterSnapshot(characterKey, "pveWeekly", "expired")
        return nil
    end
    return snapshot
end

local function getMemory(record, resetAt)
    local memory = type(record.weeklyQuestMemory) == "table" and record.weeklyQuestMemory or nil
    local savedResetAt = memory and tonumber(memory.resetAt) or 0
    if not memory or Addon.WoWApi:IsResetExpired(savedResetAt) then
        memory = {
            resetAt = resetAt,
            buckets = {},
        }
        record.weeklyQuestMemory = memory
    end
    memory.buckets = type(memory.buckets) == "table" and memory.buckets or {}
    if resetAt > 0 then
        memory.resetAt = resetAt
    end
    return memory.buckets
end

local function collectWeekly()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end

    local existing = Service:GetSnapshot(identity.key)
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    local snapshot = Addon.PveWeeklyLogic:BuildSnapshot(
        getMemory(record, resetAt),
        existing,
        getAccountState()
    )
    if snapshot then
        local stored = Addon.Database:CommitCharacterSnapshot(
            identity.key,
            "pveWeekly",
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
            if event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" or Addon:IsScreenActive("pve") then
                local delay = event == "PLAYER_ENTERING_WORLD" and 0.60 or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.25)
end

Addon.ModuleRegistry:Register(Module)
