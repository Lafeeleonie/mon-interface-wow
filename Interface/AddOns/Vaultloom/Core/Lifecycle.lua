local addonName, Addon = ...

local Lifecycle = {}
Addon.Lifecycle = Lifecycle

local function initialize()
    if Addon.Runtime.initialized then
        return
    end

    Addon.Database:Ensure()
    if Addon.PerformanceDiagnostics:ConsumeReloadArm() then
        Addon.PerformanceDiagnostics:Start("reload")
    end
    Addon.CombatQueue:Start()
    Addon.ModuleRegistry:ApplySavedStates()
    Addon.FeatureRegistry:ApplySavedStates()
    if Addon.PerformanceDiagnostics:IsActive() then
        Addon.PerformanceDiagnostics:SeedOwners()
    end
    Addon:RegisterSlashCommands()
    Addon:RegisterReloadSlashCommand()
    if Addon.MinimapLauncher then
        Addon.MinimapLauncher:Initialize()
    end
    Addon.Runtime.initialized = true
    Addon.Logger:Write("INFO", "lifecycle", "Initialized %s", Addon.version)
end

Addon.EventBus:Subscribe("ADDON_LOADED", Lifecycle, function(_, loadedAddonName)
    if loadedAddonName == addonName then
        initialize()
    end
end)

Addon.EventBus:Subscribe("PLAYER_LOGIN", Lifecycle, function()
    Addon.Runtime.loggedIn = true
    if Addon.ModuleRegistry:IsEnabled("character.identity") then
        Addon.RefreshScheduler:Invalidate("character.identity", 0.10)
    end
    if Addon.Welcome then
        Addon.Welcome:OnLogin()
    end
end)

Addon.EventBus:Subscribe("PLAYER_LOGOUT", Lifecycle, function()
    Addon.Runtime.loggedIn = false
end)
