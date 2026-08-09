local _, Addon = ...

local CombatQueue = {
    queued = {},
    order = {},
    started = false,
}

Addon.CombatQueue = CombatQueue

function CombatQueue:Start()
    if self.started then
        return
    end
    self.started = true
    Addon.EventBus:Subscribe("PLAYER_REGEN_ENABLED", self, function()
        self:Flush()
    end)
end

function CombatQueue:Stop()
    Addon.EventBus:UnsubscribeOwner(self)
    self.started = false
end

function CombatQueue:RunOrQueue(operationID, callback)
    if type(operationID) ~= "string" or operationID == "" or type(callback) ~= "function" then
        return false
    end

    if not Addon.WoWApi:IsInCombatLockdown() then
        return Addon:SafeCall("combat." .. operationID, callback)
    end

    if not self.queued[operationID] then
        self.order[#self.order + 1] = operationID
    end
    self.queued[operationID] = callback
    return true, "queued"
end

function CombatQueue:Flush()
    if Addon.WoWApi:IsInCombatLockdown() then
        return false
    end

    local order = self.order
    self.order = {}
    for _, operationID in ipairs(order) do
        local callback = self.queued[operationID]
        self.queued[operationID] = nil
        if callback then
            Addon:SafeCall("combat." .. operationID, callback)
        end
    end
    return true
end
