local _, ns = ...

ns.EventBus = ns.EventBus or {}
local EventBus = ns.EventBus

local registeredEvents = {}

-- The actual WoW event frame -- owned by ThyraxUtil (core addon, NOT tainted).
-- Dependent addons (like ThyraxUtil_InterruptTracker) cannot create their own
-- frames and call RegisterEvent on them in WoW 12.0 -- they are permanently
-- tainted. ALL event registration must go through this core-owned frame.
local eventFrame = CreateFrame("Frame")

local function ClearTable(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function EventBus:Initialize(dispatcher)
    self.dispatcher = dispatcher

    -- Wire up the OnEvent handler to dispatch all registered events.
    eventFrame:SetScript("OnEvent", function(_, eventName, ...)
        if self.dispatcher then
            self.dispatcher(eventName, ...)
        end
    end)
end

function EventBus:RegisterEvent(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        if ns and ns.Diagnostics then
            ns.Diagnostics:Warn("Tried to register non-string event! Type: " ..
                type(eventName) .. ", Value: " .. tostring(eventName))
        end
        return
    end

    if registeredEvents[eventName] then
        return
    end

    registeredEvents[eventName] = true

    -- Actually register with WoW so events are dispatched.
    local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
    if not ok then
        if ns and ns.Diagnostics then
            ns.Diagnostics:Warn("Failed to register event '" .. tostring(eventName) .. "': " .. tostring(err))
        end
    end
end

--- Register a unit-filtered event (e.g. UNIT_AURA for "player" only).
--- Falls back to RegisterEvent if RegisterUnitEvent is unavailable.
function EventBus:RegisterUnitEvent(eventName, unit1, unit2)
    if type(eventName) ~= "string" or eventName == "" then
        return
    end

    -- Build a composite key so the same event can be registered both as
    -- unit-filtered and global without conflict.
    local key = eventName .. ":" .. tostring(unit1) .. ":" .. tostring(unit2 or "")
    if registeredEvents[key] then
        return
    end

    registeredEvents[key] = true

    if eventFrame.RegisterUnitEvent then
        local ok, err = pcall(eventFrame.RegisterUnitEvent, eventFrame, eventName, unit1, unit2)
        if ok then return end
        -- Fallback on failure
        if ns and ns.Diagnostics then
            ns.Diagnostics:Warn("RegisterUnitEvent failed for '" .. eventName .. "': " .. tostring(err))
        end
    end

    -- Fallback: register unfiltered if RegisterUnitEvent is not available
    if not registeredEvents[eventName] then
        registeredEvents[eventName] = true
        pcall(eventFrame.RegisterEvent, eventFrame, eventName)
    end
end

function EventBus:RegisterEvents(eventNames)
    if type(eventNames) ~= "table" then
        return
    end

    for _, eventName in ipairs(eventNames) do
        self:RegisterEvent(eventName)
    end
end

function EventBus:UnregisterEvent(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return
    end

    if not registeredEvents[eventName] then
        return
    end

    registeredEvents[eventName] = nil
    eventFrame:UnregisterEvent(eventName)
end

function EventBus:Reset()
    eventFrame:UnregisterAllEvents()
    ClearTable(registeredEvents)
end

-- Diagnostic: returns the number of unique event registrations currently
-- active on the shared event frame (global + unit-filtered). Used by the
-- developer mode overlay. Cheap: just iterates the keys of a small table.
function EventBus:GetRegisteredEventCount()
    local count = 0
    for _ in pairs(registeredEvents) do
        count = count + 1
    end
    return count
end
