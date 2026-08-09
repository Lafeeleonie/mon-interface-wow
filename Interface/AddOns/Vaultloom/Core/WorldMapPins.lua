local _, Addon = ...

local Service = {
    activeRuntimes = {},
    hookedMap = nil,
    providerProfiles = setmetatable({}, { __mode = "k" }),
}

Addon.WorldMapPins = Service

local function refreshFeatureButton(ensure)
    local button = Addon.WorldMapFeatureButton
    if type(button) ~= "table" then return end
    if ensure == true and type(button.Ensure) == "function" then
        Addon:SafeCall("worldmap.button.ensure", button.Ensure, button)
    end
    if type(button.Refresh) == "function" then
        Addon:SafeCall("worldmap.button.refresh", button.Refresh, button)
    end
end

local function notify(methodName, ...)
    local runtimes = {}
    for runtime in pairs(Service.activeRuntimes) do
        runtimes[#runtimes + 1] = runtime
    end
    for _, runtime in ipairs(runtimes) do
        local callback = runtime[methodName]
        if type(callback) == "function" then
            if Addon.PerformanceDiagnostics.active == true then
                Addon.PerformanceDiagnostics:Call(
                    runtime,
                    "world_map",
                    methodName,
                    "worldmap." .. methodName,
                    callback,
                    runtime,
                    ...
                )
            else
                Addon:SafeCall(
                    "worldmap." .. methodName,
                    callback,
                    runtime,
                    ...
                )
            end
        end
    end
end

local function restoreProviderProfile(provider)
    local profile = Service.providerProfiles[provider]
    if not profile then return end
    if provider.RefreshAllData == profile.wrapper then
        provider.RefreshAllData = profile.original
    end
    Service.providerProfiles[provider] = nil
end

local function installProviderProfile(provider, owner)
    if type(provider) ~= "table" or type(provider.RefreshAllData) ~= "function" then
        return false
    end
    local existing = Service.providerProfiles[provider]
    if existing then
        existing.owner = owner or existing.owner
        return true
    end

    local profile = {
        owner = owner,
        original = provider.RefreshAllData,
    }
    profile.wrapper = function(selfProvider, ...)
        if Addon.PerformanceDiagnostics.active ~= true then
            return profile.original(selfProvider, ...)
        end
        local ok, first, second, third, fourth = Addon.PerformanceDiagnostics:Call(
            profile.owner or Service,
            "world_map",
            "refresh_provider",
            "worldmap.refresh_provider",
            profile.original,
            selfProvider,
            ...
        )
        if ok then return first, second, third, fourth end
        return nil
    end
    Service.providerProfiles[provider] = profile
    provider.RefreshAllData = profile.wrapper
    return true
end

function Service:GetMap()
    return _G.WorldMapFrame
end

function Service:IsShown()
    local map = self:GetMap()
    return map ~= nil
        and (type(map.IsShown) ~= "function" or map:IsShown())
end

function Service:GetMapID()
    local map = self:GetMap()
    if not map or type(map.GetMapID) ~= "function" then
        return nil
    end
    local ok, mapID = pcall(map.GetMapID, map)
    return ok and tonumber(mapID) or nil
end

function Service:EnsureHooks()
    local map = self:GetMap()
    if not map then
        return false
    end
    if self.hookedMap == map then
        refreshFeatureButton(true)
        return true
    end

    self.hookedMap = map
    if type(map.HookScript) == "function" then
        map:HookScript("OnShow", function()
            notify("OnWorldMapShown")
            refreshFeatureButton(true)
        end)
        map:HookScript("OnHide", function()
            notify("OnWorldMapHidden")
            local button = Addon.WorldMapFeatureButton
            if type(button) == "table" and type(button.HideMenu) == "function" then
                Addon:SafeCall("worldmap.button.hide", button.HideMenu, button)
            end
        end)
    end
    if type(hooksecurefunc) == "function" and type(map.OnMapChanged) == "function" then
        pcall(hooksecurefunc, map, "OnMapChanged", function()
            notify("OnWorldMapChanged")
        end)
    end
    refreshFeatureButton(true)
    return true
end

function Service:Activate(runtime)
    if type(runtime) ~= "table" then
        return false
    end
    self.activeRuntimes[runtime] = true
    self:EnsureHooks()
    refreshFeatureButton(true)
    return true
end

function Service:Deactivate(runtime)
    self.activeRuntimes[runtime] = nil
    refreshFeatureButton(false)
end

function Service:AddProvider(provider, owner)
    local map = self:GetMap()
    if not map or type(provider) ~= "table" or type(map.AddDataProvider) ~= "function" then
        return false
    end

    installProviderProfile(provider, owner)
    if type(map.dataProviders) ~= "table" or not map.dataProviders[provider] then
        local ok = pcall(map.AddDataProvider, map, provider)
        if not ok then
            restoreProviderProfile(provider)
            return false
        end
    end
    return true
end

function Service:RemoveProvider(provider)
    if type(provider) ~= "table" then
        return
    end
    if type(provider.RemoveAllData) == "function" then
        pcall(provider.RemoveAllData, provider)
    end

    local map = self:GetMap()
    if not map or type(map.RemoveDataProvider) ~= "function" then
        restoreProviderProfile(provider)
        return
    end
    if type(map.dataProviders) ~= "table" or map.dataProviders[provider] then
        pcall(map.RemoveDataProvider, map, provider)
    end
    restoreProviderProfile(provider)
end

function Service:RefreshProvider(provider)
    if not self:IsShown() or type(provider) ~= "table"
        or type(provider.RefreshAllData) ~= "function"
    then
        return false
    end
    return pcall(provider.RefreshAllData, provider)
end
