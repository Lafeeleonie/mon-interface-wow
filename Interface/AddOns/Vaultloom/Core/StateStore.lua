local _, Addon = ...

local StateStore = {
    slices = {},
    versions = {},
    subscriptions = {},
    ownerSlices = {},
    activeCounts = {},
    compactionNeeded = {},
    mutationVersion = 0,
    dispatchDepth = 0,
}

Addon.StateStore = StateStore

local function compactSlice(self, sliceID)
    local handlers = self.subscriptions[sliceID]
    if type(handlers) ~= "table" then
        self.compactionNeeded[sliceID] = nil
        return
    end

    -- Tombstones are compacted in place once the outermost notification ends.
    local writeIndex = 1
    for readIndex = 1, #handlers do
        local handler = handlers[readIndex]
        if handler.removedAt == nil then
            if writeIndex ~= readIndex then
                handlers[writeIndex] = handler
            end
            writeIndex = writeIndex + 1
        end
    end
    for index = #handlers, writeIndex, -1 do
        handlers[index] = nil
    end

    self.compactionNeeded[sliceID] = nil
    if (tonumber(self.activeCounts[sliceID]) or 0) == 0 then
        self.subscriptions[sliceID] = nil
        self.activeCounts[sliceID] = nil
    end
end

local function compactPendingSlices(self)
    if self.dispatchDepth ~= 0 then
        return
    end
    for sliceID in pairs(self.compactionNeeded) do
        compactSlice(self, sliceID)
    end
end

local function removeOwnerFromSlice(self, sliceID, owner)
    local handlers = self.subscriptions[sliceID]
    if type(handlers) ~= "table" then
        return false
    end

    local removedAt
    local removedCount = 0
    for index = 1, #handlers do
        local handler = handlers[index]
        if handler.owner == owner and handler.removedAt == nil then
            if removedAt == nil then
                self.mutationVersion = self.mutationVersion + 1
                removedAt = self.mutationVersion
            end
            handler.removedAt = removedAt
            removedCount = removedCount + 1
        end
    end

    if removedCount == 0 then
        return false
    end

    self.activeCounts[sliceID] = math.max(
        0,
        (tonumber(self.activeCounts[sliceID]) or 0) - removedCount
    )
    self.compactionNeeded[sliceID] = true
    compactPendingSlices(self)
    return true
end

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
    if type(handlers) == "table" and (tonumber(self.activeCounts[sliceID]) or 0) > 0 then
        -- Preserve the old snapshot semantics without a per-Set handler copy.
        local dispatchVersion = self.mutationVersion
        local handlerLimit = #handlers
        self.dispatchDepth = self.dispatchDepth + 1
        for index = 1, handlerLimit do
            local handler = handlers[index]
            if handler.addedAt <= dispatchVersion
                and (handler.removedAt == nil or handler.removedAt > dispatchVersion)
            then
                if Addon.PerformanceDiagnostics.active == true then
                    Addon.PerformanceDiagnostics:Call(
                        handler.owner,
                        "state",
                        sliceID,
                        handler.callsite,
                        handler.callback,
                        value,
                        self.versions[sliceID]
                    )
                else
                    Addon:SafeCall(
                        handler.callsite,
                        handler.callback,
                        value,
                        self.versions[sliceID]
                    )
                end
            end
        end
        self.dispatchDepth = self.dispatchDepth - 1
        compactPendingSlices(self)
    end
    return true
end

function StateStore:Subscribe(sliceID, owner, callback, notifyImmediately)
    if type(sliceID) ~= "string" or sliceID == "" or owner == nil or type(callback) ~= "function" then
        return false
    end

    self:Unsubscribe(owner, sliceID)
    self.subscriptions[sliceID] = self.subscriptions[sliceID] or {}
    self.mutationVersion = self.mutationVersion + 1
    local callsite = "state." .. sliceID
    self.subscriptions[sliceID][#self.subscriptions[sliceID] + 1] = {
        owner = owner,
        callback = callback,
        callsite = callsite,
        addedAt = self.mutationVersion,
    }
    self.activeCounts[sliceID] = (tonumber(self.activeCounts[sliceID]) or 0) + 1
    self.ownerSlices[owner] = self.ownerSlices[owner] or {}
    self.ownerSlices[owner][sliceID] = true

    if notifyImmediately and self.slices[sliceID] ~= nil then
        if Addon.PerformanceDiagnostics.active == true then
            Addon.PerformanceDiagnostics:Call(
                owner,
                "state",
                sliceID,
                callsite,
                callback,
                self.slices[sliceID],
                self:GetVersion(sliceID)
            )
        else
            Addon:SafeCall(
                callsite,
                callback,
                self.slices[sliceID],
                self:GetVersion(sliceID)
            )
        end
    end
    return true
end

function StateStore:Unsubscribe(owner, sliceID)
    removeOwnerFromSlice(self, sliceID, owner)

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
