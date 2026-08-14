local _, Addon = ...

local Module = {
    id = "vault.progress",
    defaultEnabled = true,
}

local Service = {}
Addon.VaultProgress = Service

local REWARD_REMINDER_KEY = "vaultRewardReminder"
local MAX_REWARD_SLOTS = 9
local TEST_REWARD_REMINDER = {
    expected = true,
    confirmed = false,
    unlockedSlots = 3,
    sourceResetAt = 0,
    detectedAt = 0,
    test = true,
}

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "WEEKLY_REWARDS_ITEM_CHANGED",
    "WEEKLY_REWARDS_UPDATE",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_MAPS_UPDATE",
}

local function now()
    return type(time) == "function" and time() or 0
end

local function getSnapshotContainer(characterKey, create)
    local characters = Addon.Database:Get().characters
    local record = type(characters) == "table" and characters[characterKey] or nil
    if type(record) ~= "table" then
        return nil
    end
    if create and type(record.snapshots) ~= "table" then
        record.snapshots = {}
    end
    return record.snapshots
end

local function normalizeRewardReminder(container)
    local reminder = type(container) == "table" and container[REWARD_REMINDER_KEY] or nil
    if type(reminder) ~= "table" or reminder.expected ~= true then
        if type(container) == "table" then container[REWARD_REMINDER_KEY] = nil end
        return nil
    end

    reminder.confirmed = reminder.confirmed == true
    reminder.unlockedSlots = math.max(
        0,
        math.min(MAX_REWARD_SLOTS, math.floor(tonumber(reminder.unlockedSlots) or 0))
    )
    reminder.sourceResetAt = math.max(0, math.floor(tonumber(reminder.sourceResetAt) or 0))
    reminder.detectedAt = math.max(0, math.floor(tonumber(reminder.detectedAt) or 0))
    return reminder
end

local function countUnlockedSlots(snapshot)
    local count = 0
    for _, row in pairs(type(snapshot) == "table" and snapshot.rows or {}) do
        if type(row) == "table" then
            local completed = math.max(0, tonumber(row.completedCount) or 0)
            local slots = type(row.slots) == "table" and row.slots or nil
            if slots and #slots > 0 then
                for _, slot in ipairs(slots) do
                    local threshold = math.max(0, tonumber(slot and slot.threshold) or 0)
                    local progress = math.max(completed, tonumber(slot and slot.progress) or 0)
                    if threshold > 0 and progress >= threshold then count = count + 1 end
                end
            else
                for _, thresholdValue in ipairs(type(row.thresholds) == "table" and row.thresholds or {}) do
                    local threshold = math.max(0, tonumber(thresholdValue) or 0)
                    if threshold > 0 and completed >= threshold then count = count + 1 end
                end
            end
        end
    end
    return math.min(MAX_REWARD_SLOTS, count)
end

local function archiveExpiredSnapshot(characterKey, container, snapshot)
    if type(characterKey) ~= "string" or type(container) ~= "table" or type(snapshot) ~= "table" then
        return false
    end

    local unlockedSlots = countUnlockedSlots(snapshot)
    if unlockedSlots > 0 then
        local existing = normalizeRewardReminder(container)
        local sourceResetAt = math.max(0, math.floor(tonumber(snapshot.resetAt) or 0))
        if not existing or sourceResetAt >= existing.sourceResetAt then
            container[REWARD_REMINDER_KEY] = {
                expected = true,
                confirmed = existing and existing.confirmed == true or false,
                unlockedSlots = unlockedSlots,
                sourceResetAt = sourceResetAt,
                detectedAt = now(),
            }
        end
    end

    -- Archive the small reward marker first, then remove only the expired Vault
    -- snapshot. Every unrelated snapshot in this container remains untouched.
    return Addon.Database:ClearCharacterSnapshot(characterKey, "vault", "expired") == true
end

local function trackNextExpiry(resetAt)
    resetAt = tonumber(resetAt) or 0
    if Addon.WoWApi:GetResetState(resetAt) ~= Addon.WoWApi.RESET_ACTIVE then return end
    if not Service.nextExpiryAt or resetAt < Service.nextExpiryAt then
        Service.nextExpiryAt = resetAt
    end
end

function Service:ProcessExpiredSnapshots(force)
    local timestamp = now()
    if force ~= true and self.nextExpiryAt and timestamp < self.nextExpiryAt then
        return false
    end

    local changed = false
    local nextExpiryAt
    for characterKey, record in pairs(Addon.Database:Get().characters or {}) do
        local container = type(record) == "table" and record.snapshots or nil
        local snapshot = type(container) == "table" and container.vault or nil
        local resetAt = type(snapshot) == "table" and tonumber(snapshot.resetAt) or 0
        local resetState = Addon.WoWApi:GetResetState(resetAt, timestamp)
        if resetState == Addon.WoWApi.RESET_EXPIRED then
            changed = archiveExpiredSnapshot(characterKey, container, snapshot) or changed
        elseif resetState == Addon.WoWApi.RESET_ACTIVE and (not nextExpiryAt or resetAt < nextExpiryAt) then
            nextExpiryAt = resetAt
        end
    end
    self.nextExpiryAt = nextExpiryAt
    return changed
end

function Service:GetRewardReminder(characterKey)
    if type(characterKey) ~= "string" then return nil end
    if self.testRewardCharacterKey == characterKey then return TEST_REWARD_REMINDER end
    return normalizeRewardReminder(getSnapshotContainer(characterKey, false))
end

function Service:ToggleTestReward(characterKey)
    if type(characterKey) ~= "string" or characterKey == "" then return false, false end
    local enabled = self.testRewardCharacterKey ~= characterKey
    self.testRewardCharacterKey = enabled and characterKey or nil
    Addon.RefreshScheduler:Invalidate(Module.id, 0)
    return true, enabled
end

function Service:GetPendingRewardCount()
    local count = 0
    for characterKey in pairs(Addon.Database:Get().characters or {}) do
        if self:GetRewardReminder(characterKey) then count = count + 1 end
    end
    return count
end

function Service:RefreshCurrentRewardAvailability(authoritative)
    local identity = Addon.StateStore:Get("character.identity")
        or Addon.WoWApi:GetCurrentCharacterIdentity()
    local characterKey = identity and identity.key
    local hasAvailableRewards = C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards
    if not characterKey or type(hasAvailableRewards) ~= "function" then return false end

    local ok, available = pcall(hasAvailableRewards)
    if not ok or type(available) ~= "boolean" then return false end

    local container = getSnapshotContainer(characterKey, available == true)
    if not container then return false end
    local existing = normalizeRewardReminder(container)
    if available then
        if not existing then
            container[REWARD_REMINDER_KEY] = {
                expected = true,
                confirmed = true,
                unlockedSlots = 0,
                sourceResetAt = 0,
                detectedAt = now(),
            }
            return true
        end
        if not existing.confirmed then
            existing.confirmed = true
            return true
        end
    elseif authoritative == true and existing then
        container[REWARD_REMINDER_KEY] = nil
        return true
    end
    return false
end

function Service:GetSnapshot(characterKey)
    if type(characterKey) ~= "string" then
        return nil
    end
    local container = getSnapshotContainer(characterKey, false)
    local snapshot = type(container) == "table" and container.vault or nil
    if type(snapshot) ~= "table" then
        return nil
    end
    local resetAt = tonumber(snapshot.resetAt) or 0
    if Addon.WoWApi:IsResetExpired(resetAt) then
        archiveExpiredSnapshot(characterKey, container, snapshot)
        return nil
    end
    trackNextExpiry(resetAt)
    return snapshot
end

local function collectVault()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    if not identity or not identity.key then
        return nil
    end

    -- The reward API is already authoritative when it reports true at login.
    -- Query it as part of every collection so the character-list badge does
    -- not have to wait for a later WEEKLY_REWARDS_UPDATE event.
    if Service.skipNextAvailabilityCheck then
        Service.skipNextAvailabilityCheck = nil
    else
        Service:RefreshCurrentRewardAvailability(false)
    end

    local existing = Service:GetSnapshot(identity.key)
    local snapshot = Addon.VaultLogic:BuildSnapshot(existing)
    if snapshot then
        if Addon.Database:CommitCharacterSnapshot(identity.key, "vault", snapshot, "refresh") then
            trackNextExpiry(snapshot.resetAt)
        else
            snapshot = existing
        end
    else
        snapshot = existing
    end
    return {
        characterKey = identity.key,
        snapshot = snapshot,
        reward = Service:GetRewardReminder(identity.key),
        pendingRewardCount = Service:GetPendingRewardCount(),
    }
end

function Service:Refresh(delaySeconds)
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectVault)
    Service:ProcessExpiredSnapshots(true)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            Service:ProcessExpiredSnapshots(false)
            if event == "CHALLENGE_MODE_COMPLETED" and C_MythicPlus
                and type(C_MythicPlus.RequestMapInfo) == "function"
            then
                pcall(C_MythicPlus.RequestMapInfo)
            end
            if event == "WEEKLY_REWARDS_UPDATE" or event == "WEEKLY_REWARDS_ITEM_CHANGED" then
                Service:RefreshCurrentRewardAvailability(true)
                Service.skipNextAvailabilityCheck = true
            end
            local delay = event == "PLAYER_ENTERING_WORLD" and 0.50
                or event == "CHALLENGE_MODE_COMPLETED" and 0.60
                or 0.10
            Addon.RefreshScheduler:Invalidate(Module.id, delay)
        end)
    end
    Addon.EventBus:Subscribe("UPDATE_UI_WIDGET", self, function(_, widgetInfo)
        local widgetID = type(widgetInfo) == "table" and tonumber(widgetInfo.widgetID or widgetInfo.widgetId)
            or tonumber(widgetInfo)
        if widgetID == Addon.Data.PVE_PREY.widgetID
            or (widgetID == nil and Addon:IsMainWindowShown())
        then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.15)
        end
    end)
    Addon.EventBus:Subscribe("UPDATE_ALL_UI_WIDGETS", self, function()
        if Addon:IsMainWindowShown() then
            Addon.RefreshScheduler:Invalidate(Module.id, 0.20)
        end
    end)
    Addon.StateStore:Subscribe("character.identity", self, function()
        Addon.RefreshScheduler:Invalidate(Module.id, 0.10)
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0)
end

Addon.ModuleRegistry:Register(Module)
