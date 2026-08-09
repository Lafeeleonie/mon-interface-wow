---@diagnostic disable: undefined-global

_G.EXBossData = _G.EXBossData or {}
_G.EXBOSS_AUTHOR_PRESETS = _G.EXBOSS_AUTHOR_PRESETS or { slots = {} }
_G.EXBOSS_PLUGIN_AUTHOR_PRESETS = _G.EXBOSS_PLUGIN_AUTHOR_PRESETS or { slots = {} }

local ROOT = _G.EXBOSS_AUTHOR_PRESETS
local PLUGIN_ROOT = _G.EXBOSS_PLUGIN_AUTHOR_PRESETS

local function BuildPresetEntry(row, pluginKey)
    local key = tostring(row.key or row.author or row.name or "")
    if key == "" then
        return nil, ""
    end
    return {
        key = key,
        name = tostring(row.name or key),
        author = tostring(row.author or row.name or key),
        builtIn = (row.builtIn == true),
        pluginKey = pluginKey and tostring(pluginKey) or nil,
        events = type(row.events) == "table" and row.events or {},
        privateAura = type(row.privateAura) == "table" and row.privateAura or nil,
    }, key
end

local function RegisterPreset(root, slotKey, row, pluginKey)
    slotKey = tostring(slotKey or "")
    if slotKey == "" or type(row) ~= "table" then
        return nil, ""
    end

    root.slots = type(root.slots) == "table" and root.slots or {}
    root.slots[slotKey] = type(root.slots[slotKey]) == "table" and root.slots[slotKey] or {}

    local entry, key = BuildPresetEntry(row, pluginKey)
    if not entry then
        return nil, ""
    end

    root.slots[slotKey][key] = entry
    return entry, key
end

function _G.EXBossData.RegisterBossPreset(slotKey, row)
    RegisterPreset(ROOT, slotKey, row)
end

function _G.EXBossData.RegisterBossPluginPreset(pluginKey, slotKey, row)
    pluginKey = tostring(pluginKey or "")
    if pluginKey == "" then
        return
    end
    local entry, key = RegisterPreset(PLUGIN_ROOT, slotKey, row, pluginKey)
    slotKey = tostring(slotKey or "")
    if not entry or slotKey == "" or key == "" then
        return
    end

    ROOT.slots = type(ROOT.slots) == "table" and ROOT.slots or {}
    ROOT.slots[slotKey] = type(ROOT.slots[slotKey]) == "table" and ROOT.slots[slotKey] or {}
    if ROOT.slots[slotKey][key] == nil then
        ROOT.slots[slotKey][key] = entry
    end
end
