local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_RARES

local Logic = {}
Addon.PveRaresLogic = Logic

local function buildExistingLookups(existingSnapshot)
    local rares, mounts = {}, {}
    for _, zone in ipairs(type(existingSnapshot) == "table" and existingSnapshot.zones or {}) do
        for _, rare in ipairs(type(zone) == "table" and zone.rares or {}) do
            if type(rare) == "table" then
                rares[tonumber(rare.questID) or rare.key] = rare
            end
        end
        for _, mount in ipairs(type(zone) == "table" and zone.mounts or {}) do
            if type(mount) == "table" then
                mounts[tonumber(mount.itemID) or mount.name] = mount
            end
        end
    end
    return rares, mounts
end

local function buildMount(definition, existingMounts)
    local itemID = tonumber(definition.itemID)
    local icon, collected = Addon.WoWApi:GetMountItemState(itemID)
    local existing = existingMounts[itemID or definition.name]
    if not collected and type(existing) == "table" and existing.collected == true then
        collected = true
        icon = icon or existing.icon
    end
    return {
        itemID = itemID,
        name = definition.name,
        icon = icon,
        collected = collected == true,
        status = collected and "complete" or "missing",
        text = collected and L.PVE_RARES_MOUNT_COLLECTED or L.PVE_RARES_MOUNT_MISSING,
    }
end

local function buildRare(zone, definition, existingRares)
    local questID = tonumber(definition.questID)
    local completed = questID and QuestApi:IsCompleted(questID) or false
    local existing = existingRares[questID or definition.key]
    if not completed and type(existing) == "table" and existing.completed == true then
        completed = true
    end
    local mapID = tonumber(definition.mapID) or tonumber(zone.mapID)
    local x = tonumber(definition.x) or 0
    local y = tonumber(definition.y) or 0
    local name = Addon.WoWApi:GetCreatureName(definition.npcID, definition.name)
    return {
        key = definition.key,
        name = name,
        label = name,
        npcID = tonumber(definition.npcID),
        questID = questID,
        mapID = mapID,
        x = x,
        y = y,
        status = completed and "complete" or "open",
        text = completed and L.PVE_RARES_DONE or L.PVE_RARES_OPEN,
        completed = completed == true,
        seen = true,
        tooltipTitle = name,
        tooltipLines = {
            string.format(L.PVE_RARES_COORDS_FORMAT, x, y),
            L.PVE_RARES_WAYPOINT_HINT,
        },
    }
end

function Logic:BuildSnapshot(existingSnapshot)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end

    local existingRares, existingMounts = buildExistingLookups(existingSnapshot)
    local secondsUntilReset, resetAt = Addon.WoWApi:GetDailyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.resetAt or nil
    )
    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        zones = {},
        completed = 0,
        total = 0,
        mountCollected = 0,
        mountTotal = 0,
    }

    for _, zone in ipairs(DATA.zones) do
        local zoneState = {
            key = zone.key,
            label = Addon.WoWApi:GetMapName(zone.mapID) or zone.label,
            mapID = zone.mapID,
            rares = {},
            mounts = {},
            completed = 0,
            total = 0,
        }
        for _, mount in ipairs(zone.mounts or {}) do
            local mountState = buildMount(mount, existingMounts)
            zoneState.mounts[#zoneState.mounts + 1] = mountState
            snapshot.mountTotal = snapshot.mountTotal + 1
            if mountState.collected then
                snapshot.mountCollected = snapshot.mountCollected + 1
            end
        end
        for _, rare in ipairs(zone.rares or {}) do
            local rareState = buildRare(zone, rare, existingRares)
            zoneState.rares[#zoneState.rares + 1] = rareState
            zoneState.total = zoneState.total + 1
            if rareState.completed then
                zoneState.completed = zoneState.completed + 1
            end
        end
        zoneState.text = string.format("%d/%d", zoneState.completed, zoneState.total)
        snapshot.completed = snapshot.completed + zoneState.completed
        snapshot.total = snapshot.total + zoneState.total
        snapshot.zones[#snapshot.zones + 1] = zoneState
    end

    snapshot.text = string.format("%d/%d", snapshot.completed, snapshot.total)
    snapshot.mountText = string.format("%d/%d", snapshot.mountCollected, snapshot.mountTotal)
    snapshot.summary = {
        resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset),
    }
    return snapshot
end
