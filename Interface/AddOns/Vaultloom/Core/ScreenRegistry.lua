local _, Addon = ...

local ScreenRegistry = {
    definitions = {},
    order = {},
    instances = {},
}

Addon.ScreenRegistry = ScreenRegistry

local function installDiagnosticsRefresh(screenID, instance)
    if type(instance) ~= "table"
        or type(instance.Refresh) ~= "function"
        or instance.vaultloomDiagnosticsRefresh ~= nil
    then
        return
    end

    local original = instance.Refresh
    instance.vaultloomDiagnosticsRefresh = original
    instance.Refresh = function(self, ...)
        if Addon.PerformanceDiagnostics.active ~= true then
            return original(self, ...)
        end
        local ok, first, second, third, fourth = Addon.PerformanceDiagnostics:Call(
            self,
            "screen",
            "refresh." .. screenID,
            "screen.refresh." .. screenID,
            original,
            self,
            ...
        )
        if ok then return first, second, third, fourth end
        return nil
    end
end

function ScreenRegistry:Register(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or definition.id == "" then
        return false
    end
    if self.definitions[definition.id] then
        error("Duplicate Vaultloom screen: " .. definition.id)
    end

    self.definitions[definition.id] = definition
    self.order[#self.order + 1] = definition.id
    return true
end

function ScreenRegistry:GetDefinition(screenID)
    return self.definitions[screenID]
end

function ScreenRegistry:GetDefinitions()
    local result = {}
    for _, screenID in ipairs(self.order) do
        result[#result + 1] = self.definitions[screenID]
    end
    return result
end

function ScreenRegistry:GetOrCreate(screenID, host)
    local definition = self.definitions[screenID]
    if not definition then
        return nil
    end
    if self.instances[screenID] then
        return self.instances[screenID]
    end
    if type(definition.Create) ~= "function" then
        return nil
    end

    local ok, instance = Addon.PerformanceDiagnostics:Call(
        definition,
        "screen",
        "create." .. screenID,
        "screen.create." .. screenID,
        definition.Create,
        definition,
        host
    )
    if not ok or not instance then
        return nil
    end
    self.instances[screenID] = instance
    installDiagnosticsRefresh(screenID, instance)
    return instance
end

function ScreenRegistry:GetCreatedCount()
    local count = 0
    for _ in pairs(self.instances) do
        count = count + 1
    end
    return count
end
