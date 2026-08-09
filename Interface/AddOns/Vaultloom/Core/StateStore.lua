local _, Addon = ...

local StateStore = {
    slices = {},
    versions = {},
    subscriptions = {},
    ownerSlices = {},
}

Addon.StateStore = StateStore

function StateStore:Get(sliceID)
    return self.slices[sliceID]
end

function StateStore:GetVersion(sliceID)
    return tonumber(self.versions[sliceID]) or 0
end

function StateStore:Set(sliceID, value)
    if type(sliceID) ~= "string" or sliceID == "" then
        return false
    end
    if self.slices[sliceID] == value then
        return false
    end

    self.slices[sliceID] = value
    self.versions[sliceID] = self:GetVersion(sliceID) + 1

    local handlers = self.subscriptions[sliceID]
    if type(handlers) == "table" then
        local snapshot = {}
        for index, handler in ipairs(handlers) do
            snapshot[index] = handler
        end
        for _, handler in ipairs(snapshot) do
            if Addon.PerformanceDiagnostics.active == true then
                Addon.PerformanceDiagnostics:Call(
                    handler.owner,
                    "state",
                    sliceID,
                    "state." .. sliceID,
                    handler.callback,
                    value,
                    self.versions[sliceID]
                )
            else
                Addon:SafeCall(
                    "state." .. sliceID,
                    handler.callback,
                    value,
                    self.versions[sliceID]
                )
            end
        end
    end
    return true
end

function StateStore:Subscribe(sliceID, owner, callback, notifyImmediately)
    if type(sliceID) ~= "string" or sliceID == "" or owner == nil or type(callback) ~= "function" then
        return false
    end

    self:Unsubscribe(owner, sliceID)
    self.subscriptions[sliceID] = self.subscriptions[sliceID] or {}
    self.subscriptions[sliceID][#self.subscriptions[sliceID] + 1] = {
        owner = owner,
        callback = callback,
    }
    self.ownerSlices[owner] = self.ownerSlices[owner] or {}
    self.ownerSlices[owner][sliceID] = true

    if notifyImmediately and self.slices[sliceID] ~= nil then
        if Addon.PerformanceDiagnostics.active == true then
            Addon.PerformanceDiagnostics:Call(
                owner,
                "state",
                sliceID,
                "state." .. sliceID,
                callback,
                self.slices[sliceID],
                self:GetVersion(sliceID)
            )
        else
            Addon:SafeCall(
                "state." .. sliceID,
                callback,
                self.slices[sliceID],
                self:GetVersion(sliceID)
            )
        end
    end
    return true
end

function StateStore:Unsubscribe(owner, sliceID)
    local handlers = self.subscriptions[sliceID]
    if type(handlers) == "table" then
        for index = #handlers, 1, -1 do
            if handlers[index].owner == owner then
                table.remove(handlers, index)
            end
        end
        if #handlers == 0 then
            self.subscriptions[sliceID] = nil
        end
    end

    local slices = self.ownerSlices[owner]
    if slices then
        slices[sliceID] = nil
        if next(slices) == nil then
            self.ownerSlices[owner] = nil
        end
    end
end

function StateStore:UnsubscribeOwner(owner)
    local slices = self.ownerSlices[owner]
    if type(slices) ~= "table" then
        return
    end

    local sliceIDs = {}
    for sliceID in pairs(slices) do
        sliceIDs[#sliceIDs + 1] = sliceID
    end
    for _, sliceID in ipairs(sliceIDs) do
        self:Unsubscribe(owner, sliceID)
    end
end

function StateStore:GetSliceCount()
    local count = 0
    for _ in pairs(self.slices) do
        count = count + 1
    end
    return count
end
