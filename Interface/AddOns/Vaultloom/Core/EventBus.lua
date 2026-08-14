local _, Addon = ...

local EventBus = {
    subscriptions = {},
    ownerEvents = {},
    activeCounts = {},
    compactionNeeded = {},
    mutationVersion = 0,
    dispatchDepth = 0,
}

Addon.EventBus = EventBus

local eventFrame = CreateFrame("Frame")
EventBus.frame = eventFrame

local function unregisterEvent(eventName)
    local ok, errorMessage = pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
    if not ok then
        Addon.Logger:Write(
            "WARN",
            "eventbus.unregister",
            "Could not unregister %s: %s",
            eventName,
            tostring(errorMessage)
        )
    end
end

local function compactEvent(self, eventName)
    local handlers = self.subscriptions[eventName]
    if type(handlers) ~= "table" then
        self.compactionNeeded[eventName] = nil
        return
    end

    -- Removals stay addressable until the outermost dispatch has finished.
    -- Compaction is cold-path work and never allocates a second list.
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

    self.compactionNeeded[eventName] = nil
    if (tonumber(self.activeCounts[eventName]) or 0) == 0 then
        self.subscriptions[eventName] = nil
        self.activeCounts[eventName] = nil
    end
end

local function compactPendingEvents(self)
    if self.dispatchDepth ~= 0 then
        return
    end
    for eventName in pairs(self.compactionNeeded) do
        compactEvent(self, eventName)
    end
end

local function removeOwnerFromEvent(self, eventName, owner)
    local handlers = self.subscriptions[eventName]
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

    local activeCount = math.max(0, (tonumber(self.activeCounts[eventName]) or 0) - removedCount)
    self.activeCounts[eventName] = activeCount
    self.compactionNeeded[eventName] = true
    if activeCount == 0 then
        unregisterEvent(eventName)
    end
    compactPendingEvents(self)
    return true
end

function EventBus:Subscribe(eventName, owner, callback)
    if type(eventName) ~= "string" or eventName == "" or owner == nil or type(callback) ~= "function" then
        return false
    end

    local events = self.ownerEvents[owner]
    if type(events) == "table" and events[eventName] then
        removeOwnerFromEvent(self, eventName, owner)
        events[eventName] = nil
    end

    local handlers = self.subscriptions[eventName]
    local activeCount = tonumber(self.activeCounts[eventName]) or 0
    if activeCount == 0 then
        local ok, registered = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
        if not ok or registered == false then
            if events and next(events) == nil then
                self.ownerEvents[owner] = nil
            end
            Addon.Logger:Write(
                "WARN",
                "eventbus.register",
                "Unsupported event %s was ignored%s",
                eventName,
                ok and "" or (": " .. tostring(registered))
            )
            return false
        end
    end

    if type(handlers) ~= "table" then
        handlers = {}
        self.subscriptions[eventName] = handlers
    end

    self.mutationVersion = self.mutationVersion + 1
    handlers[#handlers + 1] = {
        owner = owner,
        callback = callback,
        callsite = "event." .. eventName,
        addedAt = self.mutationVersion,
    }
    self.activeCounts[eventName] = activeCount + 1
    events = events or {}
    self.ownerEvents[owner] = events
    events[eventName] = true
    return true
end

function EventBus:Unsubscribe(owner, eventName)
    if owner == nil or type(eventName) ~= "string" then
        return
    end

    removeOwnerFromEvent(self, eventName, owner)
    local events = self.ownerEvents[owner]
    if events then
        events[eventName] = nil
        if next(events) == nil then
            self.ownerEvents[owner] = nil
        end
    end
end

function EventBus:UnsubscribeOwner(owner)
    local events = self.ownerEvents[owner]
    if type(events) ~= "table" then
        return
    end

    local eventNames = {}
    for eventName in pairs(events) do
        eventNames[#eventNames + 1] = eventName
    end
    for _, eventName in ipairs(eventNames) do
        self:Unsubscribe(owner, eventName)
    end
end

function EventBus:Dispatch(eventName, ...)
    if eventName == "ADDON_LOADED"
        and select(1, ...) == Addon.name
        and type(Addon.FinalizeLocale) == "function"
        and Addon.localeFinalized ~= true
    then
        local ok = Addon:SafeCall("localization.finalize", Addon.FinalizeLocale, Addon)
        if not ok then
            return
        end
    end

    local handlers = self.subscriptions[eventName]
    if type(handlers) ~= "table" or (tonumber(self.activeCounts[eventName]) or 0) == 0 then
        return
    end

    -- A fixed limit plus mutation generations reproduces snapshot membership
    -- without allocating and copying a handler table for every event.
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
                    "event",
                    eventName,
                    handler.callsite,
                    handler.callback,
                    eventName,
                    ...
                )
            else
                Addon:SafeCall(handler.callsite, handler.callback, eventName, ...)
            end
        end
    end
    self.dispatchDepth = self.dispatchDepth - 1
    compactPendingEvents(self)
end

function EventBus:GetSubscriptionCount()
    local count = 0
    for _, activeCount in pairs(self.activeCounts) do
        count = count + activeCount
    end
    return count
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    EventBus:Dispatch(eventName, ...)
end)
