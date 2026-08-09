local _, Addon = ...

local Module = {
    id = "housing.endeavors",
    defaultEnabled = true,
}

local Service = {
    opened = false,
    runtime = {
        houseList = {},
        houseLevelFavorByGUID = {},
        requestAt = {},
    },
}
Addon.Housing = Service

local DATA_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "HOUSE_LEVEL_CHANGED",
    "NEIGHBORHOOD_INITIATIVE_UPDATED",
    "INITIATIVE_TASKS_TRACKED_UPDATED",
    "INITIATIVE_TASKS_TRACKED_LIST_CHANGED",
    "INITIATIVE_TASK_COMPLETED",
    "INITIATIVE_COMPLETED",
    "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN",
    "QUEST_ACCEPTED",
    "CURRENCY_DISPLAY_UPDATE",
}

local function requestNow()
    if type(GetTimePreciseSec) == "function" then
        local ok, value = pcall(GetTimePreciseSec)
        if ok and type(value) == "number" then return value end
    end
    return type(time) == "function" and time() or 0
end

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

local function currentIdentity()
    return Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
end

local function currentSnapshot()
    local identity = currentIdentity()
    return identity and Service:GetSnapshot(identity.key) or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshots = record and type(record.snapshots) == "table" and record.snapshots or nil
    return snapshots and type(snapshots.housing) == "table" and snapshots.housing or nil
end

function Service:GetView(characterKey)
    return Addon.HousingLogic:BuildView(self:GetSnapshot(characterKey))
end

function Service:IsOpen()
    return self.opened == true
end

function Service:CanToggleTasks()
    return type(C_NeighborhoodInitiative) == "table"
        and type(C_NeighborhoodInitiative.AddTrackedInitiativeTask) == "function"
        and type(C_NeighborhoodInitiative.RemoveTrackedInitiativeTask) == "function"
end

function Service:ToggleTask(taskID, tracked)
    if taskID == nil or not self:CanToggleTasks() then return false end
    local method = tracked and "RemoveTrackedInitiativeTask" or "AddTrackedInitiativeTask"
    local ok = pcall(C_NeighborhoodInitiative[method], taskID)
    if ok and self.opened then self:Refresh(0) end
    return ok
end

function Service:QueueFollowUp(delaySeconds)
    if self.runtime.followUpPending or not self.opened then return false end
    if not (C_Timer and type(C_Timer.After) == "function") then return false end
    self.runtime.followUpPending = true
    C_Timer.After(delaySeconds or 1.0, function()
        Service.runtime.followUpPending = false
        if Service.opened then Service:Refresh(0) end
    end)
    return true
end

local function canRequest(key)
    local previous = tonumber(Service.runtime.requestAt[key]) or -1000
    local current = requestNow()
    if current - previous < Addon.Data.HOUSING.requestCooldown then return false end
    Service.runtime.requestAt[key] = current
    return true
end

local function requestMissing(needs)
    if not Service.opened or type(needs) ~= "table" then return end
    local neighborhoodGUID = needs.neighborhoodGUID
    local requested = false
    if neighborhoodGUID and Service.runtime.viewingNeighborhoodGUID ~= neighborhoodGUID
        and type(C_NeighborhoodInitiative) == "table"
        and type(C_NeighborhoodInitiative.SetViewingNeighborhood) == "function"
    then
        Service.runtime.viewingNeighborhoodGUID = neighborhoodGUID
        pcall(C_NeighborhoodInitiative.SetViewingNeighborhood, neighborhoodGUID)
    end
    if needs.houseList and canRequest("house-list")
        and type(C_Housing) == "table"
        and type(C_Housing.GetPlayerOwnedHouses) == "function"
    then
        local ok, houses = pcall(C_Housing.GetPlayerOwnedHouses)
        if ok and type(houses) == "table" then Service.runtime.houseList = houses end
        requested = true
    end
    if needs.initiative and canRequest("initiative")
        and type(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo) == "function"
    then
        pcall(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo)
        requested = true
    end
    if needs.activity and canRequest("activity")
        and type(C_NeighborhoodInitiative.RequestInitiativeActivityLog) == "function"
    then
        pcall(C_NeighborhoodInitiative.RequestInitiativeActivityLog)
        requested = true
    end
    if needs.favor and needs.houseGUID and canRequest("favor:" .. tostring(needs.houseGUID))
        and type(C_Housing) == "table"
        and type(C_Housing.GetCurrentHouseLevelFavor) == "function"
    then
        local ok, favor = pcall(C_Housing.GetCurrentHouseLevelFavor, needs.houseGUID)
        if ok and type(favor) == "table" then
            Service.runtime.lastHouseLevelFavor = favor
            Service.runtime.houseLevelFavorByGUID[needs.houseGUID] = favor
        end
        requested = true
    end
    if requested then Service:QueueFollowUp(1.0) end
end

local function housingWeekly(identity)
    local snapshot = identity and Addon.PveWeekly and Addon.PveWeekly:GetSnapshot(identity.key)
    for _, row in ipairs(snapshot and type(snapshot.rows) == "table" and snapshot.rows or {}) do
        if row.key == "housing" or row.key == "housing_weekly" then return row end
    end
    return snapshot and snapshot.rows and snapshot.rows[5] or nil
end

local function collect()
    local identity = currentIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not identity or not record then return nil end
    if not Service.opened then
        return { opened = false, characterKey = identity.key, snapshot = Service:GetSnapshot(identity.key) }
    end

    local snapshot, needs = Addon.HousingLogic:Scan(Service.runtime, housingWeekly(identity))
    if snapshot then
        record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
        record.snapshots.housing = snapshot
    else
        snapshot = Service:GetSnapshot(identity.key)
    end
    requestMissing(needs)
    return {
        opened = true,
        characterKey = identity.key,
        snapshot = snapshot,
        loading = snapshot == nil and not (needs and needs.unavailable),
        unavailable = needs and needs.unavailable == true,
    }
end

local function subscribeLiveEvents()
    if Service.liveEventsSubscribed == true then return end
    Service.liveEventsSubscribed = true
    Addon.EventBus:Subscribe("HOUSE_LEVEL_FAVOR_UPDATED", Module, function(_, favor)
        if type(favor) == "table" then
            local previous = favor.houseGUID
                and Service.runtime.houseLevelFavorByGUID[favor.houseGUID]
                or Service.runtime.lastHouseLevelFavor
            local changed = type(previous) ~= "table"
                or previous.houseGUID ~= favor.houseGUID
                or previous.houseLevel ~= favor.houseLevel
                or previous.houseFavor ~= favor.houseFavor
            Service.runtime.lastHouseLevelFavor = favor
            if favor.houseGUID then
                Service.runtime.houseLevelFavorByGUID[favor.houseGUID] = favor
            end
            if changed and Service.opened then Service:Refresh(0.10) end
        end
    end)
    for _, eventName in ipairs(DATA_EVENTS) do
        Addon.EventBus:Subscribe(eventName, Module, function(event)
            if Service.opened then
                Service:Refresh(event == "PLAYER_ENTERING_WORLD" and 0.80 or 0.15)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", Module, function()
        if Service.opened then Service:Refresh(0.15) end
    end)
end

local function unsubscribeLiveEvents()
    if Service.liveEventsSubscribed ~= true then return end
    Service.liveEventsSubscribed = false
    Addon.EventBus:Unsubscribe(Module, "HOUSE_LEVEL_FAVOR_UPDATED")
    for _, eventName in ipairs(DATA_EVENTS) do
        Addon.EventBus:Unsubscribe(Module, eventName)
    end
    Addon.StateStore:Unsubscribe(Module, "character.identity")
end

function Service:Refresh(delaySeconds)
    if not self.opened then return false end
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Service:Open()
    if self.opened then return false end
    self.opened = true
    subscribeLiveEvents()
    return self:Refresh(0)
end

function Service:Close()
    if not self.opened then return false end
    self.opened = false
    unsubscribeLiveEvents()
    Addon.RefreshScheduler:Cancel(Module.id)
    local identity = currentIdentity()
    Addon.StateStore:Set(Module.id, {
        opened = false,
        characterKey = identity and identity.key,
        snapshot = currentSnapshot(),
    })
    return true
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collect)
    Addon.StateStore:Set(self.id, {
        opened = false,
        characterKey = currentIdentity() and currentIdentity().key,
        snapshot = currentSnapshot(),
    })
end

function Module:OnDisable()
    Service.opened = false
    unsubscribeLiveEvents()
end

Addon.ModuleRegistry:Register(Module)
