---@diagnostic disable: undefined-global

_G.EXBossData = _G.EXBossData or {}
_G.EXBOSS_BUILTIN_TRASH_PRESETS = _G.EXBOSS_BUILTIN_TRASH_PRESETS or { packs = {} }
_G.EXBOSS_BUILTIN_SETTINGS_PRESETS = _G.EXBOSS_BUILTIN_SETTINGS_PRESETS or { packs = {} }

local TRASH_ROOT = _G.EXBOSS_BUILTIN_TRASH_PRESETS
local SETTINGS_ROOT = _G.EXBOSS_BUILTIN_SETTINGS_PRESETS

local function Trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local function RegisterBuiltInPreset(root, row, payloadKey)
    if type(root) ~= "table" or type(row) ~= "table" then
        return nil
    end
    local payload = row[payloadKey]
    if type(payload) ~= "table" or next(payload) == nil then
        return nil
    end

    local pluginKey = Trim(row.pluginKey or row.authorKey or row.authorName or row.title)
    if pluginKey == "" then
        return nil
    end

    root.packs = type(root.packs) == "table" and root.packs or {}
    local stored = DeepCopy(row)
    stored.pluginKey = pluginKey
    stored.builtIn = true
    root.packs[pluginKey] = stored
    return stored
end

function _G.EXBossData.RegisterTrashPreset(row)
    return RegisterBuiltInPreset(TRASH_ROOT, row, "trashConfig")
end

function _G.EXBossData.RegisterSettingsPreset(row)
    return RegisterBuiltInPreset(SETTINGS_ROOT, row, "settingsPageConfig")
end
