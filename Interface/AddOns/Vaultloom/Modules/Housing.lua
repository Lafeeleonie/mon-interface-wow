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
        viewsByNeighborhood = {},
        requestAt = {},
        scanQueue = {},
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

local RESCAN_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    HOUSE_LEVEL_CHANGED = true,
    INITIATIVE_TASK_COMPLETED = true,
    INITIATIVE_COMPLETED = true,
    QUEST_TURNED_IN = true,
    CURRENCY_DISPLAY_UPDATE = true,
}

local function safeCall(api, method, ...)
    if type(api) ~= "table" or type(api[method]) ~= "function" then return false end
    return pcall(api[method], ...)
end

local function loadAddon(addonName)
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        return pcall(C_AddOns.LoadAddOn, addonName)
    end
    if type(LoadAddOn) == "function" then return pcall(LoadAddOn, addonName) end
    return false
end

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

local function containsHouse(houses, neighborhoodGUID)
    for _, house in ipairs(type(houses) == "table" and houses or {}) do
        if house.neighborhoodGUID == neighborhoodGUID then return true end
    end
    return false
end

local function getActiveNeighborhood()
    local ok, neighborhoodGUID = safeCall(C_NeighborhoodInitiative, "GetActiveNeighborhood")
    return ok and neighborhoodGUID or nil
end

local function housingSettings()
    local ui = Addon.Database:GetUI()
    ui.housing = type(ui.housing) == "table" and ui.housing or {}
    local mode = ui.housing.switchMode
    if mode ~= "off" and mode ~= "ask" and mode ~= "automatic" then mode = "ask" end
    ui.housing.switchMode = mode
    ui.housing.ignoredSwitches = type(ui.housing.ignoredSwitches) == "table"
        and ui.housing.ignoredSwitches or {}
    return ui.housing
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshots = record and type(record.snapshots) == "table" and record.snapshots or nil
    return snapshots and type(snapshots.housing) == "table" and snapshots.housing or nil
end

function Service:GetView(characterKey, preferredNeighborhoodGUID)
    local snapshot = self:GetSnapshot(characterKey)
    local identity = currentIdentity()
    if not preferredNeighborhoodGUID and identity and identity.key == characterKey then
        preferredNeighborhoodGUID = self.runtime.selectedNeighborhoodGUID
    end
    return Addon.HousingLogic:SelectPortfolioView(snapshot, preferredNeighborhoodGUID)
end

function Service:IsOpen()
    return self.opened == true
end

function Service:GetSwitchMode()
    return housingSettings().switchMode
end

function Service:SetSwitchMode(mode)
    if mode ~= "off" and mode ~= "ask" and mode ~= "automatic" then return false end
    local settings = housingSettings()
    if settings.switchMode == mode then return false end
    settings.switchMode = mode
    self.runtime.promptedSwitchKey = nil
    if self.opened then self:Refresh(0) end
    return true
end

function Service:CycleSwitchMode()
    local modes = Addon.Data.HOUSING.switchModes or { "off", "ask", "automatic" }
    local current = self:GetSwitchMode()
    for index, mode in ipairs(modes) do
        if mode == current then
            local nextMode = modes[(index % #modes) + 1]
            self:SetSwitchMode(nextMode)
            return nextMode
        end
    end
    self:SetSwitchMode("ask")
    return "ask"
end

function Service:GetSwitchKey(characterKey, suggestion)
    if type(characterKey) ~= "string" or type(suggestion) ~= "table" then return nil end
    return table.concat({
        characterKey,
        tostring(suggestion.cycleID or 0),
        tostring(suggestion.sourceNeighborhoodGUID or ""),
        tostring(suggestion.targetNeighborhoodGUID or ""),
    }, ":")
end

function Service:IsSwitchIgnored(characterKey, suggestion)
    local key = self:GetSwitchKey(characterKey, suggestion)
    return key and housingSettings().ignoredSwitches[key] == true or false
end

function Service:IgnoreSwitch(characterKey, suggestion)
    local key = self:GetSwitchKey(characterKey, suggestion)
    if not key then return false end
    housingSettings().ignoredSwitches[key] = true
    self.runtime.promptedSwitchKey = key
    if self.opened then self:Refresh(0) end
    return true
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

function Service:CanSwitchNeighborhood()
    return type(C_NeighborhoodInitiative) == "table"
        and type(C_NeighborhoodInitiative.SetActiveNeighborhood) == "function"
end

function Service:OpenDashboard()
    for _, addonName in ipairs({ "Blizzard_HousingDashboard", "Blizzard_Housing" }) do
        loadAddon(addonName)
    end
    for _, globalName in ipairs({ "ToggleHousingDashboard", "HousingDashboard_Toggle" }) do
        local toggle = _G[globalName]
        if type(toggle) == "function" then
            local ok = pcall(toggle)
            if ok then return true end
        end
    end
    local dashboard = _G.HousingDashboardFrame
    if not dashboard then return false end
    if type(ShowUIPanel) == "function" then
        local ok = pcall(ShowUIPanel, dashboard)
        if ok then return true end
    end
    if type(dashboard.Show) == "function" then
        local ok = pcall(dashboard.Show, dashboard)
        if ok then return true end
    end
    return false
end

function Service:SwitchNeighborhood(neighborhoodGUID)
    if not neighborhoodGUID
        or not self:CanSwitchNeighborhood()
        or not containsHouse(self.runtime.houseList, neighborhoodGUID)
        or self.runtime.switchPendingGUID
    then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end

    local ok = pcall(C_NeighborhoodInitiative.SetActiveNeighborhood, neighborhoodGUID)
    if not ok then return false end
    self.runtime.switchPendingGUID = neighborhoodGUID
    self.runtime.selectedNeighborhoodGUID = neighborhoodGUID
    self.runtime.promptedSwitchKey = nil
    self:StartScan(neighborhoodGUID)
    if self.opened then self:Refresh(0.10) end
    return true
end

function Service:SelectNeighborhood(neighborhoodGUID)
    if not neighborhoodGUID or not containsHouse(self.runtime.houseList, neighborhoodGUID) then return false end
    self.runtime.selectedNeighborhoodGUID = neighborhoodGUID
    self:StartScan(neighborhoodGUID)
    if self.opened then self:Refresh(0) end
    return true
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

function Service:ApplyHouseList(houses)
    if type(houses) ~= "table" then return false end
    self.runtime.houseList = houses
    self.runtime.houseListLoaded = true
    self.runtime.requestAt["house-list"] = nil
    self:StartScan(self.runtime.selectedNeighborhoodGUID or getActiveNeighborhood())
    if self.opened then self:Refresh(0) end
    return true
end

local function requestHouseList()
    if Service.runtime.houseListLoaded == true then
        return false
    end
    if not canRequest("house-list")
        or type(C_Housing) ~= "table"
        or type(C_Housing.GetPlayerOwnedHouses) ~= "function"
    then
        return false
    end
    local ok, houses = pcall(C_Housing.GetPlayerOwnedHouses)
    if ok and type(houses) == "table" then Service:ApplyHouseList(houses) end
    return ok
end

local function setViewingNeighborhood(neighborhoodGUID)
    if not neighborhoodGUID
        or Service.runtime.viewingNeighborhoodGUID == neighborhoodGUID
        or type(C_NeighborhoodInitiative) ~= "table"
        or type(C_NeighborhoodInitiative.SetViewingNeighborhood) ~= "function"
    then
        return false
    end
    local ok = pcall(C_NeighborhoodInitiative.SetViewingNeighborhood, neighborhoodGUID)
    if ok then Service.runtime.viewingNeighborhoodGUID = neighborhoodGUID end
    return ok
end

local function requestMissing(needs)
    if not Service.opened or type(needs) ~= "table" then return false end
    local neighborhoodGUID = needs.neighborhoodGUID
    local requested = setViewingNeighborhood(neighborhoodGUID)
    if needs.houseList and requestHouseList() then requested = true end
    if needs.initiative and canRequest("initiative:" .. tostring(neighborhoodGUID))
        and type(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo) == "function"
    then
        pcall(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo)
        requested = true
    end
    if needs.activity and canRequest("activity:" .. tostring(neighborhoodGUID))
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
            Service.runtime.houseLevelFavorByGUID[favor.houseGUID or needs.houseGUID] = favor
        end
        requested = true
    end
    if requested then Service:QueueFollowUp(0.60) end
    return requested
end

local function housingWeekly(identity)
    local snapshot = identity and Addon.PveWeekly and Addon.PveWeekly:GetSnapshot(identity.key)
    for _, row in ipairs(snapshot and type(snapshot.rows) == "table" and snapshot.rows or {}) do
        if row.key == "housing" or row.key == "housing_weekly" then return row end
    end
    return snapshot and snapshot.rows and snapshot.rows[5] or nil
end

local function addUnique(target, seen, neighborhoodGUID)
    if neighborhoodGUID and not seen[neighborhoodGUID] then
        seen[neighborhoodGUID] = true
        target[#target + 1] = neighborhoodGUID
    end
end

function Service:StartScan(preferredNeighborhoodGUID)
    self.runtime.scanPreferredGUID = preferredNeighborhoodGUID
    self.runtime.rebuildScanQueue = true
    return true
end

local function rebuildScanQueue(activeNeighborhoodGUID)
    local runtime = Service.runtime
    local queue, seen = {}, {}
    addUnique(queue, seen, runtime.scanPreferredGUID)
    addUnique(queue, seen, runtime.selectedNeighborhoodGUID)
    addUnique(queue, seen, activeNeighborhoodGUID)
    for _, house in ipairs(runtime.houseList or {}) do
        addUnique(queue, seen, house.neighborhoodGUID)
    end
    runtime.scanQueue = queue
    runtime.scanTargetGUID = table.remove(runtime.scanQueue, 1)
    runtime.scanPreferredGUID = nil
    runtime.rebuildScanQueue = false
end

local function seedRuntimeFromSnapshot(snapshot)
    local runtime = Service.runtime
    if next(runtime.viewsByNeighborhood or {}) ~= nil or type(snapshot) ~= "table" then return end
    if type(snapshot.viewsByNeighborhood) == "table" then
        for neighborhoodGUID, view in pairs(snapshot.viewsByNeighborhood) do
            if type(view) == "table" then runtime.viewsByNeighborhood[neighborhoodGUID] = view end
        end
    elseif snapshot.neighborhoodGUID then
        runtime.viewsByNeighborhood[snapshot.neighborhoodGUID] = snapshot
    end
end

local function collect()
    local identity = currentIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not identity or not record then return nil end
    if not Service.opened then
        return { opened = false, characterKey = identity.key, snapshot = Service:GetSnapshot(identity.key) }
    end

    local previousSnapshot = Service:GetSnapshot(identity.key)
    seedRuntimeFromSnapshot(previousSnapshot)

    if type(Service.runtime.houseList) ~= "table" or #Service.runtime.houseList == 0 then
        requestHouseList()
    end
    local activeNeighborhoodGUID = getActiveNeighborhood()
    if Service.runtime.switchPendingGUID == activeNeighborhoodGUID then
        Service.runtime.switchPendingGUID = nil
    end
    if not Service.runtime.selectedNeighborhoodGUID
        or not containsHouse(Service.runtime.houseList, Service.runtime.selectedNeighborhoodGUID)
    then
        Service.runtime.selectedNeighborhoodGUID = activeNeighborhoodGUID
            or Service.runtime.houseList[1] and Service.runtime.houseList[1].neighborhoodGUID
    end
    if Service.runtime.rebuildScanQueue then rebuildScanQueue(activeNeighborhoodGUID) end

    local targetNeighborhoodGUID = Service.runtime.scanTargetGUID
        or Service.runtime.selectedNeighborhoodGUID
        or activeNeighborhoodGUID
    local snapshot, needs = Addon.HousingLogic:Scan(
        Service.runtime,
        housingWeekly(identity),
        targetNeighborhoodGUID
    )
    if snapshot and snapshot.neighborhoodGUID then
        Service.runtime.viewsByNeighborhood[snapshot.neighborhoodGUID] = snapshot
    end

    local targetReady = snapshot ~= nil and not (needs and needs.initiative) and not (needs and needs.favor)
    requestMissing(needs)
    if Service.runtime.scanTargetGUID and targetReady then
        Service.runtime.scanTargetGUID = table.remove(Service.runtime.scanQueue, 1)
        if Service.runtime.scanTargetGUID then
            Service:QueueFollowUp(0.05)
        else
            setViewingNeighborhood(Service.runtime.selectedNeighborhoodGUID or activeNeighborhoodGUID)
        end
    end

    local portfolio = Addon.HousingLogic:BuildPortfolio(
        Service.runtime.viewsByNeighborhood,
        Service.runtime.houseList,
        activeNeighborhoodGUID,
        Service.runtime.selectedNeighborhoodGUID,
        housingWeekly(identity)
    )
    if portfolio and (#(portfolio.neighborhoods or {}) > 0 or portfolio.available == true) then
        if not Addon.Database:CommitCharacterSnapshot(identity.key, "housing", portfolio, "refresh") then
            portfolio = previousSnapshot
        end
    else
        portfolio = previousSnapshot
    end

    return {
        opened = true,
        characterKey = identity.key,
        snapshot = portfolio,
        loading = portfolio == nil and not (needs and needs.unavailable),
        scanning = Service.runtime.scanTargetGUID ~= nil,
        unavailable = needs and needs.unavailable == true,
    }
end

local function subscribeLiveEvents()
    if Service.liveEventsSubscribed == true then return end
    Service.liveEventsSubscribed = true
    Addon.EventBus:Subscribe("PLAYER_HOUSE_LIST_UPDATED", Module, function(_, houses)
        if Service.opened then Service:ApplyHouseList(houses) end
    end)
    Addon.EventBus:Subscribe("HOUSE_LEVEL_FAVOR_UPDATED", Module, function(_, favor)
        if type(favor) == "table" then
            Service.runtime.lastHouseLevelFavor = favor
            if favor.houseGUID then Service.runtime.houseLevelFavorByGUID[favor.houseGUID] = favor end
            if Service.opened then Service:StartScan(Service.runtime.selectedNeighborhoodGUID); Service:Refresh(0.10) end
        end
    end)
    for _, eventName in ipairs(DATA_EVENTS) do
        Addon.EventBus:Subscribe(eventName, Module, function(event)
            if not Service.opened then return end
            if RESCAN_EVENTS[event] and not Service.runtime.scanTargetGUID then
                Service:StartScan(Service.runtime.selectedNeighborhoodGUID)
            end
            Service:Refresh(event == "PLAYER_ENTERING_WORLD" and 0.80 or 0.15)
        end)
    end
    Addon.StateStore:Subscribe("character.identity", Module, function()
        if Service.opened then
            Service.runtime.viewsByNeighborhood = {}
            Service.runtime.selectedNeighborhoodGUID = nil
            Service:StartScan()
            Service:Refresh(0.15)
        end
    end)
end

local function unsubscribeLiveEvents()
    if Service.liveEventsSubscribed ~= true then return end
    Service.liveEventsSubscribed = false
    Addon.EventBus:Unsubscribe(Module, "PLAYER_HOUSE_LIST_UPDATED")
    Addon.EventBus:Unsubscribe(Module, "HOUSE_LEVEL_FAVOR_UPDATED")
    for _, eventName in ipairs(DATA_EVENTS) do Addon.EventBus:Unsubscribe(Module, eventName) end
    Addon.StateStore:Unsubscribe(Module, "character.identity")
end

function Service:Refresh(delaySeconds)
    if not self.opened then return false end
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Service:Open()
    if self.opened then return false end
    self.opened = true
    self.runtime.viewsByNeighborhood = {}
    self.runtime.houseList = {}
    self.runtime.houseListLoaded = false
    self.runtime.houseLevelFavorByGUID = {}
    self.runtime.requestAt = {}
    self.runtime.selectedNeighborhoodGUID = nil
    self.runtime.switchPendingGUID = nil
    self:StartScan()
    subscribeLiveEvents()
    return self:Refresh(0)
end

function Service:Close()
    if not self.opened then return false end
    self.opened = false
    unsubscribeLiveEvents()
    Addon.RefreshScheduler:Cancel(Module.id)
    self.runtime.scanQueue = {}
    self.runtime.scanTargetGUID = nil
    self.runtime.followUpPending = false
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
