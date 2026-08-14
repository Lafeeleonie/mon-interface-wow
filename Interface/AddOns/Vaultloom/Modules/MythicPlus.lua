local _, Addon = ...

local Data = Addon.Data.MYTHIC_PLUS
local Module = {
    id = Data.stateID,
    defaultEnabled = true,
}
local Service = {}
Addon.MythicPlus = Service
local openOwners = {}

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "WEEKLY_REWARDS_UPDATE",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
    "CHALLENGE_MODE_COMPLETED",
    "BAG_UPDATE_DELAYED",
}

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey, seasonKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshots = record and type(record.snapshots) == "table" and record.snapshots or nil
    seasonKey = type(seasonKey) == "string" and seasonKey or Data.seasonKey
    local archive = snapshots and type(snapshots.mythicPlusSeasons) == "table"
        and snapshots.mythicPlusSeasons or nil
    local snapshot = archive and archive[seasonKey] or nil
    if type(snapshot) ~= "table" and seasonKey == Data.seasonKey then
        local legacy = snapshots and snapshots.mythicPlus or nil
        if type(legacy) == "table"
            and (legacy.seasonKey == seasonKey or (legacy.seasonKey == nil and seasonKey == "season1"))
        then
            snapshot = legacy
        end
    end
    return type(snapshot) == "table" and snapshot or nil
end

function Service:GetView(characterKey, seasonKey)
    seasonKey = Data.seasonKeys[seasonKey] and seasonKey or Data.seasonKey
    return Addon.MythicPlusLogic:BuildView(self:GetSnapshot(characterKey, seasonKey), seasonKey)
end

function Service:GetWarbandOverview()
    return Addon.MythicPlusLogic:BuildWarbandOverview(
        Addon.WarbandRoster:GetAll(),
        function(characterKey) return Service:GetSnapshot(characterKey) end,
        function(characterKey)
            return Addon.VaultProgress and Addon.VaultProgress:GetSnapshot(characterKey) or nil
        end,
        function(characterKey) return Addon.WarbandRoster:IsHidden(characterKey) end
    )
end

local function collect()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then return nil end
    local existing = Service:GetSnapshot(identity.key)
    local snapshot = Addon.MythicPlusLogic:Scan(existing)
    if snapshot then
        local previousSnapshots = type(record.snapshots) == "table" and record.snapshots or {}
        local previousSeasons = type(previousSnapshots.mythicPlusSeasons) == "table"
            and previousSnapshots.mythicPlusSeasons or {}
        local seasons = {}
        for seasonKey, seasonSnapshot in pairs(previousSeasons) do
            seasons[seasonKey] = seasonSnapshot
        end
        seasons[Data.seasonKey] = snapshot
        local seasonsStored = Addon.Database:CommitCharacterSnapshot(
            identity.key,
            "mythicPlusSeasons",
            seasons,
            "refresh"
        )
        -- Keep the legacy field as an active-season alias for older consumers
        -- and SavedVariables written by pre-season-migration builds.
        local legacyStored = Addon.Database:CommitCharacterSnapshot(
            identity.key,
            "mythicPlus",
            snapshot,
            "refresh"
        )
        if not seasonsStored or not legacyStored then snapshot = Service:GetSnapshot(identity.key) end
    else
        snapshot = Service:GetSnapshot(identity.key)
    end
    return {
        characterKey = identity.key,
        snapshot = snapshot,
    }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

local function isOpened()
    return next(openOwners) ~= nil
end

function Service:Open(owner)
    owner = owner or self
    if openOwners[owner] then return false end
    local wasOpened = isOpened()
    openOwners[owner] = true
    if not wasOpened then self:Refresh(0) end
    return true
end

function Service:Close(owner)
    owner = owner or self
    if not openOwners[owner] then return false end
    openOwners[owner] = nil
    if not isOpened() then Addon.RefreshScheduler:Cancel(Module.id) end
    return true
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collect)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if isOpened() then
                Addon.RefreshScheduler:Invalidate(Module.id, event == "PLAYER_ENTERING_WORLD" and 0.90 or 0.20)
            end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if isOpened() then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.20)
        end
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0.65)
end

Addon.ModuleRegistry:Register(Module)
