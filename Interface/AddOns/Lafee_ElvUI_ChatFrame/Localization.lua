local _, addon = ...

local activeLocale = GetLocale()
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

function addon:RegisterLocale(locale, strings)
    if locale ~= "enUS" and locale ~= activeLocale then
        return
    end

    for key, value in pairs(strings) do
        L[key] = value
    end
end

addon.L = L
