local _, Addon = ...

local Registry = {
    tables = {},
    locales = {},
    order = {},
}

Addon.LocaleRegistry = Registry

function Registry:Register(localeKey, values, displayName)
    if type(localeKey) ~= "string" or localeKey == "" or type(values) ~= "table" then
        return false
    end

    if not self.locales[localeKey] then
        self.order[#self.order + 1] = localeKey
    end
    self.locales[localeKey] = {
        key = localeKey,
        name = type(displayName) == "string" and displayName ~= "" and displayName or localeKey,
    }
    self.tables[localeKey] = values
    return true
end

function Registry:IsSupported(localeKey)
    return type(localeKey) == "string" and self.locales[localeKey] ~= nil
end

function Registry:Resolve(preference, clientLocale)
    local requested = preference == "auto" and clientLocale or preference
    if requested == "enGB" then requested = "enUS" end
    if self:IsSupported(requested) then
        return requested
    end
    return self:IsSupported("enUS") and "enUS" or self.order[1]
end

function Registry:GetSavedPreference(database)
    if type(database) ~= "table"
        or database.databaseIdentity ~= "vaultloom-1"
        or type(database.ui) ~= "table"
    then
        return "auto"
    end
    local preference = database.ui.language
    if preference == "auto" or self:IsSupported(preference) then
        return preference
    end
    return "auto"
end

function Registry:GetBootPreference(savedPreference, database)
    if savedPreference == "auto" or self:IsSupported(savedPreference) then
        return savedPreference
    end
    return self:GetSavedPreference(database)
end

function Registry:GetAvailable()
    local result = {}
    for _, localeKey in ipairs(self.order) do
        local locale = self.locales[localeKey]
        result[#result + 1] = {
            key = locale.key,
            name = locale.name,
        }
    end
    return result
end

function Registry:GetDisplayName(localeKey)
    local locale = self.locales[localeKey]
    return locale and locale.name or tostring(localeKey or "")
end

function Registry:Apply(localeKey, target)
    target = type(target) == "table" and target or {}
    for key in pairs(target) do
        target[key] = nil
    end

    local tables = self.tables or {}
    local base = tables.enUS or {}
    local localized = tables[localeKey]

    for key, value in pairs(base) do
        target[key] = value
    end
    if localized and localized ~= base then
        for key, value in pairs(localized) do
            target[key] = value
        end
    end

    return target
end

function Registry:Build(localeKey)
    return self:Apply(localeKey, {})
end

function Registry:ReleaseSourceTables()
    self.tables = nil
end
