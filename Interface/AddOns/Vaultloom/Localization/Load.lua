local _, Addon = ...

local registry = Addon.LocaleRegistry
local clientLocale = type(GetLocale) == "function" and GetLocale() or "enUS"
local locale = registry:Resolve("auto", clientLocale)

Addon.clientLocale = clientLocale
Addon.localePreference = "auto"
Addon.locale = locale
Addon.L = registry:Build(locale)
Addon.localeFinalized = false

function Addon:FinalizeLocale()
    if self.localeFinalized then
        return self.locale
    end

    local preference = registry:GetBootPreference(
        _G[self.Identity.languageSavedVariable],
        _G[self.Identity.savedVariables]
    )
    local selectedLocale = registry:Resolve(preference, self.clientLocale)

    registry:Apply(selectedLocale, self.L)
    self.localePreference = preference
    self.locale = selectedLocale
    self.localeFinalized = true

    if type(self.RefreshReleaseNotesLocalization) == "function" then
        self:RefreshReleaseNotesLocalization()
    end

    -- SavedVariables are guaranteed to be available at ADDON_LOADED. Keep
    -- source tables only until then so every module retains the same mutable
    -- localization table while the duplicate source tables are released.
    registry:ReleaseSourceTables()
    return selectedLocale
end
