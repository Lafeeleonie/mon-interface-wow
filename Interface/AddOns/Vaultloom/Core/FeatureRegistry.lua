local _, Addon = ...

local FeatureRegistry = {
    categories = {},
    categoryOrder = {},
    definitions = {},
    order = {},
    runtimes = {},
    enabled = {},
    errors = {},
    pending = {},
    revision = 0,
}

Addon.FeatureRegistry = FeatureRegistry

local function resolveText(value)
    if type(value) == "function" then
        local ok, result = pcall(value)
        if ok then
            return tostring(result or "")
        end
        return ""
    end
    return tostring(value or "")
end

local function normalizeSearch(value)
    value = tostring(value or "")
    value = value:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
    return string.lower(value)
end

local function cleanupRuntime(runtime)
    if type(runtime) ~= "table" then
        return
    end
    Addon.EventBus:UnsubscribeOwner(runtime)
    Addon.StateStore:UnsubscribeOwner(runtime)
    Addon.RefreshScheduler:UnregisterOwner(runtime)
end

function FeatureRegistry:Notify()
    self.revision = self.revision + 1
    Addon.StateStore:Set("features.registry", self.revision)
end

function FeatureRegistry:RegisterCategory(definition)
    if type(definition) ~= "table"
        or type(definition.id) ~= "string"
        or definition.id == ""
    then
        return false
    end
    if self.categories[definition.id] then
        error("Duplicate Vaultloom feature category: " .. definition.id)
    end

    self.categories[definition.id] = definition
    self.categoryOrder[#self.categoryOrder + 1] = definition.id
    return true
end

function FeatureRegistry:RegisterDefinition(definition)
    if type(definition) ~= "table"
        or type(definition.id) ~= "string"
        or definition.id == ""
        or type(definition.category) ~= "string"
        or not self.categories[definition.category]
    then
        return false
    end
    if self.definitions[definition.id] then
        error("Duplicate Vaultloom feature: " .. definition.id)
    end

    definition.status = definition.status == "available" and "available" or "planned"
    definition.defaultEnabled = definition.defaultEnabled == true
    definition.settings = type(definition.settings) == "table" and definition.settings or {}
    self.definitions[definition.id] = definition
    self.order[#self.order + 1] = definition.id
    return true
end

function FeatureRegistry:RegisterRuntime(featureID, runtime)
    local definition = self.definitions[featureID]
    if not definition or type(runtime) ~= "table" then
        return false
    end
    if self.runtimes[featureID] then
        error("Duplicate Vaultloom feature runtime: " .. featureID)
    end

    self.runtimes[featureID] = runtime
    if definition.status == "available" then
        self:Notify()
    end
    return true
end

function FeatureRegistry:GetDefinition(featureID)
    return self.definitions[featureID]
end

function FeatureRegistry:GetRuntime(featureID)
    return self.runtimes[featureID]
end

function FeatureRegistry:GetCategories()
    local result = {}
    for _, categoryID in ipairs(self.categoryOrder) do
        result[#result + 1] = self.categories[categoryID]
    end
    return result
end

function FeatureRegistry:GetDefinitions(categoryID, search, activeOnly)
    local result = {}
    local query = normalizeSearch(search)
    for _, featureID in ipairs(self.order) do
        local definition = self.definitions[featureID]
        local categoryMatches = categoryID == nil
            or categoryID == ""
            or categoryID == "all"
            or definition.category == categoryID
        local activeMatches = activeOnly ~= true or self:IsEnabled(featureID)
        local searchMatches = true
        if query ~= "" then
            local haystack = normalizeSearch(
                resolveText(definition.title)
                    .. " "
                    .. resolveText(definition.description)
                    .. " "
                    .. resolveText(self.categories[definition.category].label)
            )
            searchMatches = haystack:find(query, 1, true) ~= nil
        end
        if categoryMatches and activeMatches and searchMatches then
            result[#result + 1] = definition
        end
    end
    return result
end

function FeatureRegistry:GetCategoryCount(categoryID)
    local count = 0
    for _, featureID in ipairs(self.order) do
        local definition = self.definitions[featureID]
        if categoryID == "all" or definition.category == categoryID then
            count = count + 1
        end
    end
    return count
end

function FeatureRegistry:GetStats()
    local enabled = 0
    for _, featureID in ipairs(self.order) do
        if self:IsEnabled(featureID) then
            enabled = enabled + 1
        end
    end
    return enabled, #self.order
end

function FeatureRegistry:GetState(featureID)
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or { states = {} }
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
    local state = db.features.states[featureID]
    if type(state) ~= "table" then
        state = {
            enabled = false,
            settings = {},
        }
        db.features.states[featureID] = state
    end
    state.settings = type(state.settings) == "table" and state.settings or {}
    return state
end

function FeatureRegistry:IsEnabled(featureID)
    return self.enabled[featureID] == true
end

function FeatureRegistry:IsAvailable(featureID)
    local definition = self.definitions[featureID]
    return definition ~= nil
        and definition.status == "available"
        and self.runtimes[featureID] ~= nil
end

function FeatureRegistry:GetStatus(featureID)
    if self.errors[featureID] then
        return "error"
    end
    if self.pending[featureID] ~= nil then
        return "pending"
    end
    if self:IsEnabled(featureID) then
        return "enabled"
    end
    if self:IsAvailable(featureID) then
        return "disabled"
    end
    return "planned"
end

function FeatureRegistry:GetError(featureID)
    return self.errors[featureID]
end

function FeatureRegistry:CanToggle(featureID)
    return self:IsAvailable(featureID) and self.pending[featureID] == nil
end

function FeatureRegistry:GetSetting(featureID, settingKey)
    local definition = self.definitions[featureID]
    if not definition or type(settingKey) ~= "string" or settingKey == "" then
        return nil
    end

    local descriptor
    for _, setting in ipairs(definition.settings) do
        if setting.key == settingKey then
            descriptor = setting
            break
        end
    end
    if not descriptor then
        return nil
    end

    local runtime = self.runtimes[featureID]
    if descriptor.runtime == true and runtime and type(runtime.GetSettingValue) == "function" then
        local ok, runtimeValue = Addon:SafeCall(
            "feature.setting.get." .. featureID .. "." .. settingKey,
            runtime.GetSettingValue,
            runtime,
            settingKey
        )
        if ok and runtimeValue ~= nil then
            return runtimeValue
        end
    end

    local saved = self:GetState(featureID).settings[settingKey]
    if saved == nil then
        return descriptor.default
    end
    if descriptor.type == "select" then
        local valid = false
        for _, option in ipairs(descriptor.options or {}) do
            if option.value == saved then
                valid = true
                break
            end
        end
        if not valid then
            return descriptor.default
        end
    elseif descriptor.type == "range" then
        local minimum = tonumber(descriptor.minimum) or 0
        local maximum = tonumber(descriptor.maximum) or minimum
        local step = math.max(0.0001, tonumber(descriptor.step) or 1)
        saved = tonumber(saved) or tonumber(descriptor.default) or minimum
        saved = math.max(minimum, math.min(maximum, saved))
        saved = minimum + (math.floor(((saved - minimum) / step) + 0.5) * step)
    end
    return saved
end

function FeatureRegistry:SetSetting(featureID, settingKey, value)
    local definition = self.definitions[featureID]
    local runtime = self.runtimes[featureID]
    if not definition or type(settingKey) ~= "string" or settingKey == "" then
        return false
    end

    local descriptor
    for _, setting in ipairs(definition.settings) do
        if setting.key == settingKey then
            descriptor = setting
            break
        end
    end
    if not descriptor then
        return false
    end

    if descriptor.type == "boolean" then
        value = value == true
    elseif descriptor.type == "select" then
        local valid = false
        for _, option in ipairs(descriptor.options or {}) do
            if option.value == value then
                valid = true
                break
            end
        end
        if not valid then
            value = descriptor.default
        end
    elseif descriptor.type == "range" then
        local minimum = tonumber(descriptor.minimum) or 0
        local maximum = tonumber(descriptor.maximum) or minimum
        local step = math.max(0.0001, tonumber(descriptor.step) or 1)
        value = tonumber(value) or tonumber(descriptor.default) or minimum
        value = math.max(minimum, math.min(maximum, value))
        value = minimum + (math.floor(((value - minimum) / step) + 0.5) * step)
    end

    local handled = false
    if descriptor.runtime == true and runtime and type(runtime.SetSettingValue) == "function" then
        local ok, runtimeHandled = Addon:SafeCall(
            "feature.setting.set." .. featureID .. "." .. settingKey,
            runtime.SetSettingValue,
            runtime,
            settingKey,
            value
        )
        if not ok then
            self.errors[featureID] = tostring(runtimeHandled or "setting update failed")
            self:Notify()
            return false
        end
        handled = runtimeHandled == true
    end

    if not handled then
        self:GetState(featureID).settings[settingKey] = value
    end
    if not handled and self:IsEnabled(featureID) and runtime and type(runtime.OnSettingChanged) == "function" then
        local ok, errorMessage = Addon:SafeCall(
            "feature.setting." .. featureID .. "." .. settingKey,
            runtime.OnSettingChanged,
            runtime,
            settingKey,
            value
        )
        if not ok then
            self.errors[featureID] = tostring(errorMessage or "setting update failed")
        end
    end
    self:Notify()
    return true
end

function FeatureRegistry:InvokeAction(featureID, actionKey)
    local definition = self.definitions[featureID]
    local runtime = self.runtimes[featureID]
    if not definition or not runtime or type(actionKey) ~= "string" or actionKey == "" then
        return false
    end

    local descriptor
    for _, setting in ipairs(definition.settings) do
        if setting.key == actionKey and setting.type == "action" then
            descriptor = setting
            break
        end
    end
    if not descriptor or type(runtime.OnAction) ~= "function" then
        return false
    end

    local ok, handled = Addon:SafeCall(
        "feature.action." .. featureID .. "." .. actionKey,
        runtime.OnAction,
        runtime,
        actionKey
    )
    if not ok then
        self.errors[featureID] = tostring(handled or "feature action failed")
        self:Notify()
        return false
    end
    self:Notify()
    return handled ~= false
end

function FeatureRegistry:ResetSettings(featureID)
    local definition = self.definitions[featureID]
    if not definition then
        return false
    end
    local state = self:GetState(featureID)
    state.settings = {}
    local runtime = self.runtimes[featureID]
    if runtime and type(runtime.ResetSettingValues) == "function" then
        Addon:SafeCall("feature.settings.values.reset." .. featureID, runtime.ResetSettingValues, runtime)
    end
    if self:IsEnabled(featureID) and runtime and type(runtime.OnSettingsReset) == "function" then
        Addon:SafeCall("feature.settings.reset." .. featureID, runtime.OnSettingsReset, runtime)
    end
    self:Notify()
    return true
end

function FeatureRegistry:ApplyEnabled(featureID, enabled, reason)
    local definition = self.definitions[featureID]
    local runtime = self.runtimes[featureID]
    if not definition or not runtime or definition.status ~= "available" then
        return false
    end
    if enabled == self:IsEnabled(featureID) then
        self:GetState(featureID).enabled = enabled
        return true
    end

    self.errors[featureID] = nil
    if enabled then
        local ok, errorMessage = true, nil
        if type(runtime.OnEnable) == "function" then
            ok, errorMessage = Addon.PerformanceDiagnostics:Call(
                runtime,
                "lifecycle",
                "enable",
                "feature.enable." .. featureID,
                runtime.OnEnable,
                runtime,
                reason or "user"
            )
        end
        if not ok then
            cleanupRuntime(runtime)
            self.enabled[featureID] = nil
            self:GetState(featureID).enabled = false
            self.errors[featureID] = tostring(errorMessage or "enable failed")
            self:Notify()
            return false
        end
        self.enabled[featureID] = true
        self:GetState(featureID).enabled = true
    else
        if type(runtime.OnDisable) == "function" then
            local ok, errorMessage = Addon.PerformanceDiagnostics:Call(
                runtime,
                "lifecycle",
                "disable",
                "feature.disable." .. featureID,
                runtime.OnDisable,
                runtime,
                reason or "user"
            )
            if not ok then
                self.errors[featureID] = tostring(errorMessage or "disable failed")
            end
        end
        cleanupRuntime(runtime)
        self.enabled[featureID] = nil
        self:GetState(featureID).enabled = false
    end
    self:Notify()
    return self.errors[featureID] == nil
end

function FeatureRegistry:SetEnabled(featureID, enabled, reason)
    if not self:IsAvailable(featureID) then
        return false
    end
    enabled = enabled == true
    local definition = self.definitions[featureID]
    if definition.combatProtected == true and Addon.WoWApi:IsInCombatLockdown() then
        self.pending[featureID] = enabled
        self:Notify()
        local queued = Addon.CombatQueue:RunOrQueue("feature." .. featureID, function()
            local desired = FeatureRegistry.pending[featureID]
            FeatureRegistry.pending[featureID] = nil
            if desired ~= nil then
                FeatureRegistry:ApplyEnabled(featureID, desired, "combat-ended")
            end
        end)
        return queued == true
    end
    return self:ApplyEnabled(featureID, enabled, reason)
end

function FeatureRegistry:ApplySavedStates()
    for _, featureID in ipairs(self.order) do
        local definition = self.definitions[featureID]
        local state = self:GetState(featureID)
        if definition and definition.status == "available" and state.enabled == true then
            self:ApplyEnabled(featureID, true, "load")
        else
            state.enabled = false
        end
    end
end

function FeatureRegistry:ResolveText(value)
    return resolveText(value)
end
