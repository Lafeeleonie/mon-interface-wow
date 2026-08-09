local _, Addon = ...

local Module = {
    id = "mythicplus.season1",
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

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.mythicPlus or nil
    return type(snapshot) == "table" and snapshot or nil
end

function Service:GetView(characterKey)
    return Addon.MythicPlusLogic:BuildView(self:GetSnapshot(characterKey))
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
    local snapshot = Addon.MythicPlusLogic:Scan()
    if snapshot then
        record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
        record.snapshots.mythicPlus = snapshot
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
