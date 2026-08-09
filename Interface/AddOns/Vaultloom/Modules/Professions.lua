local _, Addon = ...

local Module = {
    id = "systems.professions",
    defaultEnabled = true,
}
local Service = {}
Addon.Professions = Service
local knowledgeDirty = true

local QUEST_EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_DATA_LOAD_RESULT",
    "BAG_UPDATE_DELAYED",
}
local PROFESSION_EVENTS = {
    "SKILL_LINES_CHANGED",
    "TRADE_SKILL_LIST_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_TREE_CURRENCY_INFO_UPDATED",
}

local function now()
    return type(time) == "function" and time() or 0
end

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function getRawSnapshot(characterKey)
    local record = getRecord(characterKey)
    return record and type(record.snapshots) == "table" and record.snapshots.professions or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and getRawSnapshot(characterKey) or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    if (tonumber(snapshot.resetAt) or 0) <= now() then
        record.snapshots.professions = nil
        return nil
    end
    local runtimeState = Addon.StateStore:Get(Module.id)
    local detectorState = type(runtimeState) == "table" and {
        active = runtimeState.darkmoonActive == true,
        resetKey = runtimeState.darkmoonResetKey,
    } or Addon.DarkmoonDetector:GetState()
    return Addon.ProfessionWeeklyLogic:FilterDarkmoon(snapshot, detectorState)
end

function Service:GetKnowledge(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local state = record and type(record.snapshots) == "table" and record.snapshots.professionKnowledge or nil
    return type(state) == "table" and state or nil
end

function Service:Open(entry, characterKey)
    if not Addon.WarbandRoster:IsCurrent(characterKey) then
        return false
    end
    return Addon.WoWApi:OpenProfession(entry)
end

local function collectProfessions()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then
        return nil
    end
    local detectorState = Addon.DarkmoonDetector:GetState()
    local existing = getRawSnapshot(identity.key)
    if type(existing) == "table" and (tonumber(existing.resetAt) or 0) <= now() then
        existing = nil
    end
    local snapshot = Addon.ProfessionWeeklyLogic:BuildSnapshot(identity, existing, detectorState)
    local knowledge = Addon.ProfessionKnowledgeLogic:BuildState(knowledgeDirty)
    record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
    if snapshot then
        record.snapshots.professions = snapshot
    end
    if knowledge then
        record.snapshots.professionKnowledge = knowledge
        knowledgeDirty = false
    else
        knowledge = record.snapshots.professionKnowledge
    end
    return {
        characterKey = identity.key,
        snapshot = snapshot,
        knowledge = knowledge,
        darkmoonActive = detectorState.active == true,
        darkmoonResetKey = detectorState.resetKey,
    }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectProfessions)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        knowledgeDirty = true
        Addon.DarkmoonDetector:RequestCalendar()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.95)
    end)
    Addon.EventBus:Subscribe("CALENDAR_UPDATE_EVENT_LIST", self, function()
        Addon.DarkmoonDetector:ClearCache()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.10)
    end)
    for _, eventName in ipairs(QUEST_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if event == "QUEST_TURNED_IN" or Addon:IsScreenActive("systems") then
                Addon.RefreshScheduler:Invalidate(Module.id, event == "BAG_UPDATE_DELAYED" and 0.25 or 0.15)
            end
        end)
    end
    for _, eventName in ipairs(PROFESSION_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function()
            knowledgeDirty = true
            Addon.RefreshScheduler:Invalidate("character.identity", 0.05)
            Addon.RefreshScheduler:Invalidate(Module.id, 0.20)
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.65)
end

Addon.ModuleRegistry:Register(Module)
