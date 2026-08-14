local _, Addon = ...

local Module = {
    id = "pve.daily",
    defaultEnabled = true,
}

local Service = {}
Addon.PveDaily = Service

local BOUNTIFUL_MEMORY_VERSION = 2

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "AREA_POIS_UPDATED",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveDaily or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    if Addon.WoWApi:IsResetExpired(snapshot.resetAt) then
        Addon.Database:ClearCharacterSnapshot(characterKey, "pveDaily", "expired")
        record.dailyQuestMemory = nil
        return nil
    end
    return snapshot
end

local function getMemory(record, resetAt)
    local memory = type(record.dailyQuestMemory) == "table" and record.dailyQuestMemory or nil
    local savedResetAt = memory and tonumber(memory.resetAt) or 0
    local expired = Addon.WoWApi:IsResetExpired(savedResetAt)
    if not memory or expired then
        memory = {
            resetAt = resetAt,
            bountiful = {},
            wanted = { discoveredIDs = {} },
        }
        record.dailyQuestMemory = memory
    end
    memory.bountiful = type(memory.bountiful) == "table" and memory.bountiful or {}
    memory.wanted = type(memory.wanted) == "table" and memory.wanted or {}
    memory.wanted.discoveredIDs = type(memory.wanted.discoveredIDs) == "table" and memory.wanted.discoveredIDs or {}
    if tonumber(memory.bountiful.version) ~= BOUNTIFUL_MEMORY_VERSION then
        -- Older builds interpreted "no Bountiful POI visible" as 4/4 and
        -- persisted that false completion for the rest of the day. That old
        -- value has no reliable provenance, so discard it once on upgrade.
        memory.bountiful.completed = 0
        memory.bountiful.version = BOUNTIFUL_MEMORY_VERSION
    end
    if resetAt > 0 then
        memory.resetAt = resetAt
    end
    return memory
end

local function getCurrentContext()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    return identity, record
end

function Service:RememberWantedQuests(questIDs)
    if type(questIDs) ~= "table" or #questIDs == 0 then
        return false
    end
    local _, record = getCurrentContext()
    if not record then
        return false
    end
    local _, resetAt = Addon.WoWApi:GetDailyResetInfo()
    local memory = getMemory(record, resetAt)
    local changed = false
    for _, questID in ipairs(questIDs) do
        questID = tonumber(questID)
        if questID and questID > 0 and not memory.wanted.discoveredIDs[questID] then
            memory.wanted.discoveredIDs[questID] = true
            changed = true
        end
    end
    local count = 0
    for _, known in pairs(memory.wanted.discoveredIDs) do
        if known then
            count = count + 1
        end
    end
    if count > (tonumber(memory.wanted.lastKnownTotal) or 0) then
        memory.wanted.lastKnownTotal = count
        changed = true
    end
    return changed
end

local function collectDaily()
    local identity, record = getCurrentContext()
    if not identity or not record then
        return nil
    end
    local existing = Service:GetSnapshot(identity.key)
    local _, resetAt = Addon.WoWApi:GetDailyResetInfo()
    local snapshot = Addon.PveDailyLogic:BuildSnapshot(getMemory(record, resetAt), existing, identity)
    if snapshot then
        local stored = Addon.Database:CommitCharacterSnapshot(
            identity.key,
            "pveDaily",
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
    Addon.RefreshScheduler:Register(self.id, self, collectDaily)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" or Addon:IsScreenActive("pve") then
                local delay = event == "PLAYER_ENTERING_WORLD" and 0.65
                    or event == "AREA_POIS_UPDATED" and 0.35
                    or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.EventBus:Subscribe("GOSSIP_SHOW", self, function()
        Service:RememberWantedQuests(Addon.PveDailyLogic:GetWantedGossipQuestIDs())
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.10)
        end
    end)
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.30)
end

Addon.ModuleRegistry:Register(Module)
