local _, Addon = ...

local Module = {
    id = "pve.delves",
    defaultEnabled = true,
}

local Service = {}
Addon.PveDelves = Service

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "BAG_UPDATE_DELAYED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.pveDelves or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    if Addon.WoWApi:IsResetExpired(snapshot.resetAt) then
        Addon.Database:ClearCharacterSnapshot(characterKey, "pveDelves", "expired")
        return nil
    end
    return snapshot
end

local function scanStoredWeeklyDrop(db, resetAt)
    for _, record in pairs(db.characters or {}) do
        local snapshot = type(record) == "table" and type(record.snapshots) == "table" and record.snapshots.pveDelves or nil
        local snapshotResetAt = type(snapshot) == "table" and tonumber(snapshot.resetAt) or 0
        local resetState = Addon.WoWApi:GetResetState(resetAt)
        if Addon.WoWApi:GetResetState(snapshotResetAt) == Addon.WoWApi.RESET_ACTIVE
            and (resetState ~= Addon.WoWApi.RESET_ACTIVE or math.abs(snapshotResetAt - resetAt) <= 120)
        then
            for _, row in ipairs(snapshot.rows or {}) do
                if row.key == "delve_weekly_drop" and (row.completed == true or row.status == "complete") then
                    return true
                end
            end
        end
    end
    return false
end

local function getMemory(resetAt)
    local db = Addon.Database:Get()
    local memory = type(db.pveDelvesMemory) == "table" and db.pveDelvesMemory or nil
    local savedResetAt = memory and tonumber(memory.resetAt) or 0
    local expired = Addon.WoWApi:IsResetExpired(savedResetAt)
    if not memory or expired then
        memory = { resetAt = resetAt }
        db.pveDelvesMemory = memory
    end
    if not memory.weeklyDropCompleted and scanStoredWeeklyDrop(db, resetAt) then
        memory.weeklyDropCompleted = true
        memory.weeklyDropQuestID = Addon.Data.PVE_DELVES.weeklyDropQuestID
    end
    if resetAt > 0 then
        memory.resetAt = resetAt
    end
    return memory
end

local function collectDelves()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end
    local existing = Service:GetSnapshot(identity.key)
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    local snapshot = Addon.PveDelvesLogic:BuildSnapshot(getMemory(resetAt), existing)
    if snapshot then
        local stored = Addon.Database:CommitCharacterSnapshot(identity.key, "pveDelves", snapshot, "refresh")
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
    Addon.RefreshScheduler:Register(self.id, self, collectDelves)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if event == "PLAYER_ENTERING_WORLD" or Addon:IsScreenActive("pve") then
                local delay = event == "PLAYER_ENTERING_WORLD" and 0.85
                    or event == "BAG_UPDATE_DELAYED" and 0.25
                    or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" and 0.30
                    or 0.15
                Addon.RefreshScheduler:Invalidate(Module.id, delay)
            end
        end)
    end
    Addon.EventBus:Subscribe("QUEST_TURNED_IN", self, function(_, questID)
        if tonumber(questID) == Addon.Data.PVE_DELVES.weeklyDropQuestID then
            local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
            local memory = getMemory(resetAt)
            memory.weeklyDropCompleted = true
            memory.weeklyDropQuestID = tonumber(questID)
        end
        Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
    end)
    Addon.EventBus:Subscribe("UPDATE_UI_WIDGET", self, function(_, widgetInfo)
        local widgetID = type(widgetInfo) == "table" and tonumber(widgetInfo.widgetID or widgetInfo.widgetId)
            or tonumber(widgetInfo)
        if widgetID == Addon.Data.PVE_DELVES.gildedStashWidgetID
            or (widgetID == nil and Addon:IsScreenActive("pve"))
        then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.20)
        end
    end)
    Addon.EventBus:Subscribe("UPDATE_ALL_UI_WIDGETS", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.25)
        end
    end)
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Addon:IsScreenActive("pve") then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.40)
end

Addon.ModuleRegistry:Register(Module)
