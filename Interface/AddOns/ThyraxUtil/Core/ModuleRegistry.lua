local _, ns = ...

ns.ModuleRegistry = ns.ModuleRegistry or {}
local ModuleRegistry = ns.ModuleRegistry

local modulesByID = {}
local moduleOrder = {}
local enabledModules = {}
local unavailableReasons = {}
local CORE_SOURCE = "core"
local EXTERNAL_SOURCE = "external"

local function CopyArray(source)
    local result = {}
    for index, value in ipairs(source) do
        result[index] = value
    end
    return result
end

local function RegisterModuleEvents(module)
    if not ns.EventBus or not ns.EventBus.RegisterEvents then
        return
    end

    ns.EventBus:RegisterEvents(module.events or {})

    -- Register unit-filtered events (reduces GC pressure from high-frequency
    -- events like UNIT_AURA that would otherwise fire for every unit in the raid).
    if ns.EventBus.RegisterUnitEvent and type(module.unitEvents) == "table" then
        for _, entry in ipairs(module.unitEvents) do
            ns.EventBus:RegisterUnitEvent(entry.event, entry.unit, entry.unit2)
            -- Also mark the event in the module's _eventSet so dispatch works
            if module._eventSet then
                module._eventSet[entry.event] = true
            end
        end
    end
end

local function ResolveModuleSource(module)
    if type(module) ~= "table" then
        return EXTERNAL_SOURCE
    end

    if module.internal == true then
        return CORE_SOURCE
    end

    if type(module.source) == "string" and module.source ~= "" then
        return string.lower(module.source)
    end

    return EXTERNAL_SOURCE
end

local function InitializeModule(module)
    if type(module.OnInitialize) == "function" then
        ns.Diagnostics:SafeCall(
            module.id .. ":OnInitialize",
            module.OnInitialize,
            module,
            ns.Settings:GetModuleSettings(module.id)
        )
    end
end

function ModuleRegistry:Register(module)
    if type(module) ~= "table" then
        return
    end

    if type(module.id) ~= "string" or module.id == "" then
        if ns.Diagnostics then
            ns.Diagnostics:Warn("Attempted to register a module without a valid id.")
        end
        return
    end

    local incomingSource = ResolveModuleSource(module)
    module._source = incomingSource

    local existingModule = modulesByID[module.id]
    local isReplacingExternal = false
    if existingModule then
        local existingSource = ResolveModuleSource(existingModule)

        if existingSource == CORE_SOURCE and incomingSource ~= CORE_SOURCE then
            if ns.Diagnostics then
                ns.Diagnostics:Warn(
                    ("Blocked external duplicate '%s' (core module already loaded)."):format(module.id)
                )
            end
            return false, "duplicate_blocked_core_priority"
        end

        if existingSource ~= CORE_SOURCE and incomingSource == CORE_SOURCE then
            isReplacingExternal = true
            if ns.Diagnostics then
                ns.Diagnostics:Warn(
                    ("Replacing external module '%s' with integrated core module."):format(module.id)
                )
            end
            self:DisableModule(module.id)
        else
            if ns.Diagnostics then
                ns.Diagnostics:Warn(
                    ("Duplicate module id '%s' from source '%s'."):format(module.id, incomingSource)
                )
            end
            return false, "duplicate_blocked"
        end
    end

    module.events = module.events or {}
    module._eventSet = {}
    for _, eventName in ipairs(module.events) do
        module._eventSet[eventName] = true
    end

    -- Register module defaults into Settings (also works if Settings is not
    -- yet initialized - RegisterModuleDefaults merges into DEFAULTS and, if
    -- already loaded, also into self.db).
    if type(module.defaults) == "table" and ns.Settings and ns.Settings.RegisterModuleDefaults then
        ns.Settings:RegisterModuleDefaults(module.id, module.defaults)
    end

    modulesByID[module.id] = module
    if not isReplacingExternal then
        table.insert(moduleOrder, module.id)
    end

    if self.initialized then
        RegisterModuleEvents(module)
        InitializeModule(module)

        if ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled(module.id) then
            local ok, reason = self:EnableModule(module.id)
                if ok then
                    ns.Diagnostics:Debug(("Module enabled: %s"):format(module.id))
                else
                    ns.Diagnostics:Debug(("Module blocked: %s (%s)"):format(module.id, tostring(reason)))
                end
        end
    end

    return true
end

function ModuleRegistry:GetModule(moduleID)
    return modulesByID[moduleID]
end

function ModuleRegistry:GetModuleIDs()
    return CopyArray(moduleOrder)
end

function ModuleRegistry:IsModuleEnabled(moduleID)
    return enabledModules[moduleID] == true
end

function ModuleRegistry:GetModuleStatus(moduleID)
    local module = modulesByID[moduleID]
    if not module then
        return nil
    end

    local available, reason = self:_EvaluateAvailability(module)
    return {
        id = moduleID,
        name = module.name or moduleID,
        configured = ns.Settings:IsModuleEnabled(moduleID),
        enabled = enabledModules[moduleID] == true,
        available = available,
        reason = reason,
    }
end

function ModuleRegistry:GetAllStatuses()
    local statuses = {}
    for _, moduleID in ipairs(moduleOrder) do
        statuses[#statuses + 1] = self:GetModuleStatus(moduleID)
    end
    return statuses
end

function ModuleRegistry:_EvaluateAvailability(module)
    if type(module.IsAvailable) ~= "function" then
        unavailableReasons[module.id] = nil
        return true, nil
    end

    local ok, available, reason = ns.Diagnostics:SafeCall(
        module.id .. ":IsAvailable",
        module.IsAvailable,
        module,
        self.context
    )

    if not ok then
        unavailableReasons[module.id] = "availability check failed"
        return false, unavailableReasons[module.id]
    end

    if available == false then
        unavailableReasons[module.id] = reason or "unavailable"
        return false, unavailableReasons[module.id]
    end

    unavailableReasons[module.id] = nil
    return true, nil
end

function ModuleRegistry:Initialize(context)
    self.context = context or {}
    self.initialized = true

    -- Note: PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED are dispatched through
    -- the EventBus channel. Every module that reacts to combat transitions
    -- declares the event(s) in its own events{} table, so RegisterAllModuleEvents
    -- below wires them up through EventBus. A separate registry-owned frame used
    -- to register these globally here, which caused every combat transition to
    -- dispatch twice (once per frame). Removed to eliminate the double-dispatch.

    self:RegisterAllModuleEvents()

    for _, moduleID in ipairs(moduleOrder) do
        local module = modulesByID[moduleID]
        InitializeModule(module)
    end
end

function ModuleRegistry:RegisterAllModuleEvents()
    if not ns.EventBus or not ns.EventBus.RegisterEvents then
        return
    end

    for _, moduleID in ipairs(moduleOrder) do
        local module = modulesByID[moduleID]
        RegisterModuleEvents(module)
    end
end

function ModuleRegistry:EnableModule(moduleID)
    local module = modulesByID[moduleID]
    if not module then
        return false, "module not found"
    end

    if enabledModules[moduleID] then
        return true
    end

    if not ns.Settings:IsGlobalEnabled() then
        return false, "global disabled"
    end

    if not ns.Settings:IsModuleEnabled(moduleID) then
        return false, "module disabled in settings"
    end

    local available, reason = self:_EvaluateAvailability(module)
    if not available then
        return false, reason
    end

    local moduleSettings = ns.Settings:GetModuleSettings(moduleID)

    -- OnEnable must run first so the module can create its frame/state
    -- before ApplySettings tries to use it.
    if type(module.OnEnable) == "function" then
        local ok = ns.Diagnostics:SafeCall(module.id .. ":OnEnable", module.OnEnable, module, moduleSettings)
        if not ok then
            return false, "module failed to enable"
        end
    end

    -- ApplySettings after OnEnable so frame/state is guaranteed to exist.
    if type(module.ApplySettings) == "function" then
        ns.Diagnostics:SafeCall(module.id .. ":ApplySettings", module.ApplySettings, module, moduleSettings)
    end

    enabledModules[moduleID] = true
    return true
end

function ModuleRegistry:DisableModule(moduleID)
    local module = modulesByID[moduleID]
    if not module then
        return false, "module not found"
    end

    if not enabledModules[moduleID] then
        return true
    end

    if type(module.OnDisable) == "function" then
        ns.Diagnostics:SafeCall(module.id .. ":OnDisable", module.OnDisable, module)
    end

    enabledModules[moduleID] = nil
    return true
end

function ModuleRegistry:ApplyModuleSettings(moduleID)
    local module = modulesByID[moduleID]
    if not module then
        return false, "module not found"
    end

    local moduleSettings = ns.Settings:GetModuleSettings(moduleID)
    if type(module.ApplySettings) == "function" then
        ns.Diagnostics:SafeCall(module.id .. ":ApplySettings", module.ApplySettings, module, moduleSettings)
    end

    return true
end

function ModuleRegistry:EnableConfiguredModules()
    if not ns.Settings:IsGlobalEnabled() then
        self:DisableAllModules()
        if ns.Diagnostics then
            ns.Diagnostics:Warn("Suite is globally disabled. Use /thyrax global on")
        end
        return
    end

    for _, moduleID in ipairs(moduleOrder) do
        if ns.Settings:IsModuleEnabled(moduleID) then
            local ok, reason = self:EnableModule(moduleID)
            if ns.Diagnostics then
                if ok then
                    ns.Diagnostics:Debug(("Module enabled: %s"):format(moduleID))
                else
                    ns.Diagnostics:Debug(("Module blocked: %s (%s)"):format(moduleID, tostring(reason)))
                end
            end
        else
            self:DisableModule(moduleID)
            if ns.Diagnostics then
                ns.Diagnostics:Debug(("Module disabled in settings: %s"):format(moduleID))
            end
        end
    end
end

function ModuleRegistry:DisableAllModules()
    for _, moduleID in ipairs(moduleOrder) do
        self:DisableModule(moduleID)
    end
end

function ModuleRegistry:ReloadAll()
    self:DisableAllModules()
    self:EnableConfiguredModules()
end

function ModuleRegistry:ReevaluateAvailability()
    for _, moduleID in ipairs(moduleOrder) do
        local module = modulesByID[moduleID]
        local available = self:_EvaluateAvailability(module)
        local shouldBeEnabled =
        ns.Settings:IsGlobalEnabled() and
            ns.Settings:IsModuleEnabled(moduleID) and
            available

        if shouldBeEnabled and not enabledModules[moduleID] then
            self:EnableModule(moduleID)
        elseif (not shouldBeEnabled) and enabledModules[moduleID] then
            self:DisableModule(moduleID)
        end
    end
end

local dispatchLabelCache = {}

function ModuleRegistry:DispatchEvent(eventName, ...)
    for _, moduleID in ipairs(moduleOrder) do
        if enabledModules[moduleID] then
            local module = modulesByID[moduleID]
            if module._eventSet[eventName] and type(module.OnEvent) == "function" then
                -- Cache the SafeCall label to avoid string concatenation churn
                local cache = dispatchLabelCache[moduleID]
                if not cache then
                    cache = {}
                    dispatchLabelCache[moduleID] = cache
                end
                
                local label = cache[eventName]
                if not label then
                    label = moduleID .. ":OnEvent(" .. eventName .. ")"
                    cache[eventName] = label
                end

                ns.Diagnostics:SafeCall(label, module.OnEvent, module, eventName, ...)
            end
        end
    end
end

function ModuleRegistry:SetModuleEnabled(moduleID, enabled)
    ns.Settings:SetModuleEnabled(moduleID, enabled)

    if enabled then
        return self:EnableModule(moduleID)
    end

    return self:DisableModule(moduleID)
end

function ModuleRegistry:SetGlobalEnabled(enabled)
    ns.Settings:SetGlobalEnabled(enabled)
    if enabled then
        self:EnableConfiguredModules()
    else
        self:DisableAllModules()
    end
end
