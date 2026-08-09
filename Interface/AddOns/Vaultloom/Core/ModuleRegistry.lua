local _, Addon = ...

local ModuleRegistry = {
    definitions = {},
    order = {},
    enabled = {},
}

Addon.ModuleRegistry = ModuleRegistry

local function cleanupDefinition(definition)
    Addon.EventBus:UnsubscribeOwner(definition)
    Addon.StateStore:UnsubscribeOwner(definition)
    Addon.RefreshScheduler:UnregisterOwner(definition)
end

function ModuleRegistry:Register(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or definition.id == "" then
        return false
    end
    if self.definitions[definition.id] then
        error("Duplicate Vaultloom module: " .. definition.id)
    end

    self.definitions[definition.id] = definition
    self.order[#self.order + 1] = definition.id
    return true
end

function ModuleRegistry:IsEnabled(moduleID)
    return self.enabled[moduleID] == true
end

function ModuleRegistry:Enable(moduleID)
    local definition = self.definitions[moduleID]
    if not definition or self.enabled[moduleID] then
        return definition ~= nil
    end

    local ok = true
    if type(definition.OnEnable) == "function" then
        ok = Addon.PerformanceDiagnostics:Call(
            definition,
            "lifecycle",
            "enable",
            "module.enable." .. moduleID,
            definition.OnEnable,
            definition
        )
    end
    if ok then
        self.enabled[moduleID] = true
    else
        cleanupDefinition(definition)
    end
    return ok
end

function ModuleRegistry:Disable(moduleID)
    local definition = self.definitions[moduleID]
    if not definition or not self.enabled[moduleID] then
        return definition ~= nil
    end

    if type(definition.OnDisable) == "function" then
        Addon.PerformanceDiagnostics:Call(
            definition,
            "lifecycle",
            "disable",
            "module.disable." .. moduleID,
            definition.OnDisable,
            definition
        )
    end
    cleanupDefinition(definition)
    self.enabled[moduleID] = nil
    return true
end

function ModuleRegistry:SetEnabled(moduleID, enabled)
    local result
    if enabled == true then
        result = self:Enable(moduleID)
    else
        result = self:Disable(moduleID)
    end
    if result then
        Addon.Database:SetModuleEnabled(moduleID, enabled == true)
    end
    return result
end

function ModuleRegistry:ApplySavedStates()
    for _, moduleID in ipairs(self.order) do
        local definition = self.definitions[moduleID]
        local enabled = Addon.Database:GetModuleEnabled(moduleID, definition.defaultEnabled == true)
        if enabled then
            self:Enable(moduleID)
        end
    end
end

function ModuleRegistry:GetStats()
    local total = #self.order
    local enabled = 0
    for _, moduleID in ipairs(self.order) do
        if self.enabled[moduleID] then
            enabled = enabled + 1
        end
    end
    return enabled, total
end
