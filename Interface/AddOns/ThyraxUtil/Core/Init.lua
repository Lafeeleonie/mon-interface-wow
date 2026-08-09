local _, ns = ...

ns.context = ns.context or {}
ns.initialized = false

local function RefreshContext()
    ns.context.classToken = ns.Compat.GetPlayerClassToken()
    ns.context.specID = ns.Compat.GetSpecializationID()
end

local function InitializeAddon()
    if ns.initialized then return end

    RefreshContext()
    ns.Settings:Initialize()
    
    local hasMigrated = false
    if ns.LegacyAddonGuard and ns.LegacyAddonGuard.DisableLegacyAddons then
        local disabledTypes = ns.LegacyAddonGuard:DisableLegacyAddons()
        if type(disabledTypes) == "table" then
            for addonType, _ in pairs(disabledTypes) do
                ns.Settings:MigrateFromLegacy(addonType)
                hasMigrated = true
            end
        end
    end

    ns.EventBus:Initialize(function(eventName, ...)
        ns.ModuleRegistry:DispatchEvent(eventName, ...)
    end)
    ns.ModuleRegistry:Initialize(ns.context)
    ns.SlashCommands:Initialize()
    ns.OptionsPanel:Initialize()
    ns.DeveloperMode:Initialize()

    local function EnableConfiguredModules()
        ns.ModuleRegistry:EnableConfiguredModules()
        if ns.OptionsPanel and ns.OptionsPanel.Refresh then
            ns.OptionsPanel:Refresh()
        end
    end

    if ns.Onboarding and ns.Onboarding.Initialize then
        ns.Onboarding:Initialize(EnableConfiguredModules, hasMigrated)
    else
        EnableConfiguredModules()
    end

    ns.Diagnostics:RunStartupChecks()
    local version = (ns.Compat and ns.Compat.GetAddOnVersion and ns.Compat.GetAddOnVersion(ns.addonName)) or "0.0.0"
    ns.Diagnostics:Info(("Loaded build %s (all-in-one)."):format(version))

    ns.initialized = true
end

-- Compatibility wrapper for IsAddOnLoaded
local function IsAddOnLoadedSafe(name)
    if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name)
    end
    return false
end

-- Use a frame to catch ADDON_LOADED and specialization changes
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ns.addonName then
        InitializeAddon()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not ns.initialized then return end
        local previousSpecID = ns.context.specID
        RefreshContext()
        if ns.context.specID ~= previousSpecID then
            ns.ModuleRegistry:ReevaluateAvailability()
        end
    end
end)

-- Safety trigger: If addon is already loaded (e.g. on /reload)
if IsAddOnLoadedSafe(ns.addonName) then
    -- Small delay to ensure all modules had a chance to register
    C_Timer.After(0.1, InitializeAddon)
end
