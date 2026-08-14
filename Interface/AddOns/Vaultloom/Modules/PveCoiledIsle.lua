local _, Addon = ...

local Module = {
    id = "pve.coiled_isle",
    defaultEnabled = true,
}

local Service = {}
Addon.PveCoiledIsle = Service

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "AREA_POIS_UPDATED",
    "UPDATE_INSTANCE_INFO",
    "BOSS_KILL",
}

local function requestRaidProgress(loadJournal)
    if loadJournal and type(EJ_GetNumTiers) ~= "function" and C_AddOns
        and type(C_AddOns.LoadAddOn) == "function"
    then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
    if type(RequestRaidInfo) == "function" then pcall(RequestRaidInfo) end
end

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function getMemory(record, resetAt)
    local memory = type(record.pveCoiledIsleMemory) == "table" and record.pveCoiledIsleMemory or nil
    local savedResetAt = memory and tonumber(memory.resetAt) or 0
    if not memory or Addon.WoWApi:IsResetExpired(savedResetAt) then
        memory = { resetAt = resetAt }
        record.pveCoiledIsleMemory = memory
    end
    if memory.worldBossCompleted ~= true then
        local snapshot = type(record.snapshots) == "table" and record.snapshots.pveCoiledIsle or nil
        if type(snapshot) == "table" and not Addon.WoWApi:IsResetExpired(snapshot.weeklyResetAt) then
            for _, row in ipairs(snapshot.rows or {}) do
                if row.key == Addon.Data.PVE_COILED_ISLE.worldBoss.key
                    and (row.completed == true or row.status == "complete")
                then
                    memory.worldBossCompleted = true
                    break
                end
            end
        end
    end
    if resetAt > 0 then memory.resetAt = resetAt end
    return memory
end

local function getCurrentContext()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    return identity, record
end

local function isTrackedWorldBoss(encounterID, encounterName)
    local definition = Addon.Data.PVE_COILED_ISLE.worldBoss
    encounterID = tonumber(encounterID)
    for _, trackedID in ipairs(definition.bossKillEncounterIDs or {}) do
        if encounterID and encounterID == tonumber(trackedID) then return true end
    end
    return Addon.RaidJournalLogic:NormalizeKey(encounterName)
        == Addon.RaidJournalLogic:NormalizeKey(definition.fallbackName)
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveCoiledIsle or nil
    if type(snapshot) ~= "table" then return nil end
    if Addon.WoWApi:IsResetExpired(snapshot.resetAt) then
        Addon.Database:ClearCharacterSnapshot(characterKey, "pveCoiledIsle", "expired")
        return nil
    end
    return snapshot
end

local function collectCoiledIsle()
    local identity, record = getCurrentContext()
    if not identity or not record then return nil end
    local existing = Service:GetSnapshot(identity.key)
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    local snapshot = Addon.PveCoiledIsleLogic:BuildSnapshot(existing, getMemory(record, resetAt))
    if snapshot then
        if not Addon.Database:CommitCharacterSnapshot(identity.key, "pveCoiledIsle", snapshot, "refresh") then
            snapshot = existing
        end
    end
    return { characterKey = identity.key, snapshot = snapshot }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    requestRaidProgress(true)
    Addon.RefreshScheduler:Register(self.id, self, collectCoiledIsle)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            if event == "PLAYER_ENTERING_WORLD" then requestRaidProgress(false) end
            local trackedBossKill = event == "BOSS_KILL" and isTrackedWorldBoss(...)
            if trackedBossKill then
                local _, record = getCurrentContext()
                if record then
                    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
                    getMemory(record, resetAt).worldBossCompleted = true
                end
            end
            if trackedBossKill or event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN"
                or Addon:IsScreenActive("pve")
            then
                local delay = event == "PLAYER_ENTERING_WORLD" and 0.70
                    or event == "AREA_POIS_UPDATED" and 0.35
                    or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then Addon.RefreshScheduler:Invalidate(Module.id, 0.15) end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.35)
end

Addon.ModuleRegistry:Register(Module)
