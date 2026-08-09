local _, Addon = ...

local EventBus = {
    subscriptions = {},
    ownerEvents = {},
}

Addon.EventBus = EventBus

local eventFrame = CreateFrame("Frame")
EventBus.frame = eventFrame

local function removeOwnerFromEvent(self, eventName, owner)
    local handlers = self.subscriptions[eventName]
    if type(handlers) ~= "table" then
        return
    end

    for index = #handlers, 1, -1 do
        if handlers[index].owner == owner then
            table.remove(handlers, index)
        end
    end

    if #handlers == 0 then
        self.subscriptions[eventName] = nil
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
end

function EventBus:Subscribe(eventName, owner, callback)
    if type(eventName) ~= "string" or eventName == "" or owner == nil or type(callback) ~= "function" then
        return false
    end

    self.ownerEvents[owner] = self.ownerEvents[owner] or {}
    if self.ownerEvents[owner][eventName] then
        removeOwnerFromEvent(self, eventName, owner)
    end

    local handlers = self.subscriptions[eventName]
    if not handlers then
        local ok, registered = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
        if not ok or registered == false then
            local events = self.ownerEvents[owner]
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

        handlers = {}
        self.subscriptions[eventName] = handlers
    end

    handlers[#handlers + 1] = {
        owner = owner,
        callback = callback,
    }
    self.ownerEvents[owner][eventName] = true
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
    if type(handlers) ~= "table" or #handlers == 0 then
        return
    end

    local snapshot = {}
    for index, handler in ipairs(handlers) do
        snapshot[index] = handler
    end

    for _, handler in ipairs(snapshot) do
        if Addon.PerformanceDiagnostics.active == true then
            Addon.PerformanceDiagnostics:Call(
                handler.owner,
                "event",
                eventName,
                "event." .. eventName,
                handler.callback,
                eventName,
                ...
            )
        else
            Addon:SafeCall("event." .. eventName, handler.callback, eventName, ...)
        end
    end
end

function EventBus:GetSubscriptionCount()
    local count = 0
    for _, handlers in pairs(self.subscriptions) do
        count = count + #handlers
    end
    return count
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    EventBus:Dispatch(eventName, ...)
end)
