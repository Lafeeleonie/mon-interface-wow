local addonName, Addon = ...

Addon.name = addonName
Addon.version = "1.0.6-beta"

Addon.Identity = {
    displayName = "Vaultloom",
    addonName = addonName,
    savedVariables = "VaultloomDB",
    languageSavedVariable = "VaultloomLanguage",
    globalPrefix = "Vaultloom",
    slashCommands = { "/vl", "/vaultloom" },
}

Addon.Runtime = {
    initialized = false,
    loggedIn = false,
}

function Addon:GetIdentity()
    return self.Identity
end

function Addon:IsMainWindowShown()
    local ui = self.UI
    local frame = ui and ui.frame
    return frame ~= nil
        and type(frame.IsShown) == "function"
        and frame:IsShown() == true
end

function Addon:IsScreenActive(screenID)
    local ui = self.UI
    local screen = ui and ui.activeScreen
    return type(screenID) == "string"
        and self:IsMainWindowShown()
        and ui.activeScreenID == screenID
        and screen ~= nil
        and type(screen.IsShown) == "function"
        and screen:IsShown() == true
end
