---@diagnostic disable: undefined-global
-- =============================================================
-- EXBossData/Store.lua
-- 单一数据入口：
--   1. EXBOSS_ENCOUNTER_DATA  静态 Boss 数据（含 eventType / voiceLabel）
--   2. EXBossDataDB.events    玩家 override 真源
-- 运行时读取始终走：EncounterData 推导默认 + Override
-- =============================================================

local DATA_WTF_VERSION = 3

local _resolvedEventCache = {}
local _resolvedRootCache = nil
local GetFactoryDefaultEvent
local _encounterEventIndexCache = nil
local _encounterEventIndexSource = nil
_G.EXBOSS_PLUGIN_TRASH_PRESETS = _G.EXBOSS_PLUGIN_TRASH_PRESETS or { packs = {} }
local TRASH_PLUGIN_ROOT = _G.EXBOSS_PLUGIN_TRASH_PRESETS
_G.EXBOSS_PLUGIN_SETTINGS_PRESETS = _G.EXBOSS_PLUGIN_SETTINGS_PRESETS or { packs = {} }
local SETTINGS_PLUGIN_ROOT = _G.EXBOSS_PLUGIN_SETTINGS_PRESETS
_G.EXBOSS_BUILTIN_TRASH_PRESETS = _G.EXBOSS_BUILTIN_TRASH_PRESETS or { packs = {} }
local TRASH_BUILTIN_ROOT = _G.EXBOSS_BUILTIN_TRASH_PRESETS
_G.EXBOSS_BUILTIN_SETTINGS_PRESETS = _G.EXBOSS_BUILTIN_SETTINGS_PRESETS or { packs = {} }
local SETTINGS_BUILTIN_ROOT = _G.EXBOSS_BUILTIN_SETTINGS_PRESETS
local EVENT_BLACKLIST = {
    [513] = true,
}

local EVENT_TYPE_SCHEME_MAP = {
    ["坦克"] = "tank",
    ["治疗"] = "heal",
    ["机制"] = "mechanic",
    ["其他"] = "cooldown",
}

local PACK_LABELS = {
    ["准备AOE"] = true, ["准备引线"] = true, ["准备打断"] = true, ["准备拉人"] = true, ["准备挡线"] = true, ["准备接圈"] = true, ["准备消层"] = true,
    ["准备点名"] = true, ["准备踩箭"] = true, ["准备进圈"] = true, ["准备连线"] = true, ["准备送球"] = true, ["准备钩人"] = true, ["准备集合"] = true,
    ["准备驱散"] = true, ["去撞分身"] = true, ["坦克尖刺"] = true, ["快卡视角"] = true, ["快去消水"] = true, ["快找光柱"] = true, ["快踩陷阱"] = true,
    ["无"] = true, ["注意击退"] = true, ["注意头前"] = true, ["注意挡球"] = true, ["注意消球"] = true, ["注意躲避"] = true, ["点名头前"] = true,
    ["点名放水"] = true, ["点名消线"] = true, ["躲开头前"] = true, ["转火小怪"] = true, ["转阶段"] = true, ["远离BOSS"] = true, ["靠近分散"] = true, ["风筝小怪"] = true,
    ["Boss狂暴"] = true, ["Boss易伤"] = true, ["你是白色"] = true, ["你是黑色"] = true, ["准备AOE(断条)"] = true, ["准备吸球"] = true, ["出去放水"] = true,
    ["去接小怪"] = true, ["射线点你"] = true, ["小心冲击波"] = true, ["小心击飞"] = true, ["强化奶骑"] = true, ["强化惩戒骑"] = true, ["强化防骑"] = true,
    ["快分散"] = true, ["快打断"] = true, ["快救人"] = true, ["快破盾"] = true, ["快进罩子"] = true, ["拉断连线"] = true, ["易伤爆发"] = true, ["注意减伤"] = true,
    ["注意治疗"] = true, ["特殊技能"] = true, ["转火大怪"] = true, ["远离大怪"] = true, ["集合分摊"] = true,
    ["倒数5"] = true, ["倒数4"] = true, ["倒数3"] = true, ["倒数2"] = true, ["倒数1"] = true,
}

local function SafeNum(v)
    local n = tonumber(v)
    return n
end

local function IsEventBlacklisted(eventID)
    local eid = tonumber(eventID)
    return eid and EVENT_BLACKLIST[eid] and true or false
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

local function TrimString(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function WipeTable(t)
    if type(t) ~= "table" then
        return
    end
    if wipe then
        wipe(t)
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function MarkEventConfigDirty(eventID)
    _resolvedRootCache = nil
    if eventID ~= nil then
        _resolvedEventCache[tonumber(eventID) or eventID] = nil
        return
    end
    WipeTable(_resolvedEventCache)
end

local function MergeOverride(dst, src)
    if type(src) ~= "table" then
        return dst
    end
    if type(dst) ~= "table" then
        dst = {}
    end
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            MergeOverride(dst[k], v)
        else
            dst[k] = DeepCopy(v)
        end
    end
    return dst
end

local function BuildOverrideDelta(current, defaults)
    local currentType = type(current)
    local defaultType = type(defaults)

    if currentType ~= "table" then
        if defaults == nil or current ~= defaults then
            return current
        end
        return nil
    end

    local out = {}
    local hasAny = false
    for k, v in pairs(current) do
        local baseline = nil
        if defaultType == "table" then
            baseline = defaults[k]
        end
        local delta = BuildOverrideDelta(v, baseline)
        if delta ~= nil then
            out[k] = delta
            hasAny = true
        end
    end

    if hasAny then
        return out
    end
    return nil
end

local function NormalizeStandaloneTriggerStorage(trigger)
    if type(trigger) ~= "table" then
        return nil
    end
    if type(trigger.label) == "string" and trigger.label == "" then
        trigger.label = nil
    end
    if type(trigger.customLSM) == "string" and trigger.customLSM == "" then
        trigger.customLSM = nil
    end
    if type(trigger.customPath) == "string" and trigger.customPath == "" then
        trigger.customPath = nil
    end

    if next(trigger) == nil then
        return nil
    end
    return trigger
end

local function NormalizeEventOverrideRowForStorage(row)
    if type(row) ~= "table" then
        return nil
    end
    if type(row.centralText) == "string" and row.centralText == "" then
        row.centralText = nil
    end

    if type(row.preAlertText) == "string" and row.preAlertText == "" then
        row.preAlertText = nil
    end

    if type(row.timerBarRenameText) == "string" and row.timerBarRenameText == "" then
        row.timerBarRenameText = nil
    end

    if type(row.color) == "table" then
        if type(row.color.scheme) == "string" and row.color.scheme == "" then
            row.color.scheme = nil
        end
        if row.color.r == nil and row.color.g == nil and row.color.b == nil and next(row.color) == nil then
            row.color = nil
        elseif next(row.color) == nil then
            row.color = nil
        end
    end

    if type(row.triggers) == "table" then
        local normalized = {}
        for triggerKey, triggerCfg in pairs(row.triggers) do
            local kept = NormalizeStandaloneTriggerStorage(type(triggerCfg) == "table" and DeepCopy(triggerCfg) or nil)
            if kept then
                normalized[triggerKey] = kept
            end
        end
        if next(normalized) == nil then
            row.triggers = nil
        else
            row.triggers = normalized
        end
    end

    if type(row.rules) == "table" then
        local cw = row.rules.castWindow
        if type(cw) == "table" then
            if next(cw) == nil then
                row.rules.castWindow = nil
            end
        end
        if next(row.rules) == nil then
            row.rules = nil
        end
    end

    if next(row) == nil then
        return nil
    end
    return row
end

local function BuildCompactedEventOverride(eventID, row)
    local eid = tonumber(eventID)
    if not eid or type(row) ~= "table" then
        return nil
    end
    local normalized = NormalizeEventOverrideRowForStorage(DeepCopy(row))
    if type(normalized) ~= "table" then
        return nil
    end
    return BuildOverrideDelta(normalized, GetFactoryDefaultEvent(eid))
end

local function BuildEncounterEventIndex()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if _encounterEventIndexCache and _encounterEventIndexSource == data then
        return _encounterEventIndexCache
    end
    local out = {}
    if type(data) == "table" and type(data.maps) == "table" then
        for _, mapRow in pairs(data.maps) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for rawEventID, eventRow in pairs(bossRow.events) do
                            local eid = tonumber(rawEventID) or (type(eventRow) == "table" and tonumber(eventRow.eventID))
                            if eid and type(eventRow) == "table" and not IsEventBlacklisted(eid) then
                                out[eid] = eventRow
                            end
                        end
                    end
                end
            end
        end
    end
    _encounterEventIndexCache = out
    _encounterEventIndexSource = data
    return out
end

local function GetEncounterEventRow(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    if IsEventBlacklisted(eid) then
        return nil
    end
    local index = BuildEncounterEventIndex()
    return type(index) == "table" and index[eid] or nil
end

local function BuildFactoryRowFromEncounterEvent(eventID, eventRow)
    local eid = tonumber(eventID)
    if not eid or type(eventRow) ~= "table" then
        return nil
    end
    if IsEventBlacklisted(eid) then
        return nil
    end
    local label = tostring(eventRow.voiceLabel or "")
    local eventType = tostring(eventRow.eventType or "其他")
    local scheme = EVENT_TYPE_SCHEME_MAP[eventType] or "cooldown"
    local sourceType = PACK_LABELS[label] and "pack" or "none"
    return {
        enabled = true,
        centralEnabled = false,
        eventID = eid,
        color = {
            enabled = true,
            scheme = scheme,
            useCustom = false,
        },
        triggers = {
            [0] = { enabled = false, label = label, sourceType = sourceType },
            [1] = { enabled = true,  label = label, sourceType = sourceType },
            [2] = { enabled = false, label = label, sourceType = sourceType },
        },
    }
end

local function GetFactoryDefaultsRoot()
    local out = {}
    local index = BuildEncounterEventIndex()
    for eid, eventRow in pairs(index) do
        local row = BuildFactoryRowFromEncounterEvent(eid, eventRow)
        if type(row) == "table" then
            out[eid] = row
        end
    end
    return out
end

GetFactoryDefaultEvent = function(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    if IsEventBlacklisted(eid) then
        return nil
    end
    return BuildFactoryRowFromEncounterEvent(eid, GetEncounterEventRow(eid))
end

local function ResetLegacySavedData()
    EXBossDataDB = {
        wtfVersion = DATA_WTF_VERSION,
        events = {},
        timer = {
            timelineMode = {},
        },
    }

    if type(ExBossDB) == "table" then
        ExBossDB.voice = type(ExBossDB.voice) == "table" and ExBossDB.voice or {}
        ExBossDB.voice.profiles = nil
        ExBossDB.voice.activeProfileMplus = nil
        ExBossDB.voice.activeProfileRaid = nil
    end

    MarkEventConfigDirty()
end

local function InitEXBossDataDB()
    if type(EXBossDataDB) ~= "table" or tonumber(EXBossDataDB.wtfVersion) ~= DATA_WTF_VERSION then
        ResetLegacySavedData()
        return
    end

    EXBossDataDB.events = type(EXBossDataDB.events) == "table" and EXBossDataDB.events or {}
    EXBossDataDB.timer = type(EXBossDataDB.timer) == "table" and EXBossDataDB.timer or {}
    EXBossDataDB.timer.timelineMode = type(EXBossDataDB.timer.timelineMode) == "table" and EXBossDataDB.timer.timelineMode or {}
end

local function GetOverrideRoot()
    InitEXBossDataDB()
    return EXBossDataDB.events
end

local function BuildResolvedEvent(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end

    local cached = _resolvedEventCache[eid]
    if type(cached) == "table" then
        return cached
    end

    local defaults = GetFactoryDefaultEvent(eid)
    local override = GetOverrideRoot()[eid]

    if type(defaults) ~= "table" and type(override) ~= "table" then
        return nil
    end

    local resolved = DeepCopy(defaults or {})
    MergeOverride(resolved, override)
    _resolvedEventCache[eid] = resolved
    return resolved
end

local function BuildResolvedRoot()
    if type(_resolvedRootCache) == "table" then
        return _resolvedRootCache
    end

    local out = {}
    local seen = {}
    local defaultsRoot = GetFactoryDefaultsRoot()
    local overrideRoot = GetOverrideRoot()

    for rawKey in pairs(defaultsRoot) do
        local eid = tonumber(rawKey)
        if eid then
            seen[eid] = true
            local resolved = BuildResolvedEvent(eid)
            if type(resolved) == "table" then
                out[eid] = resolved
            end
        end
    end

    for rawKey in pairs(overrideRoot) do
        local eid = tonumber(rawKey)
        if eid and not seen[eid] then
            local resolved = BuildResolvedEvent(eid)
            if type(resolved) == "table" then
                out[eid] = resolved
            end
        end
    end

    _resolvedRootCache = out
    return out
end

local function CompactEventOverride(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    if IsEventBlacklisted(eid) then
        return nil
    end

    local root = GetOverrideRoot()
    local row = root[eid]
    if type(row) ~= "table" then
        root[eid] = nil
        MarkEventConfigDirty(eid)
        return nil
    end

    local compacted = BuildCompactedEventOverride(eid, row)
    if type(compacted) == "table" then
        root[eid] = compacted
    else
        root[eid] = nil
    end
    MarkEventConfigDirty(eid)
    return root[eid]
end

local function CompactAllEventOverrides()
    local root = GetOverrideRoot()
    local toCheck = {}
    for rawKey in pairs(root) do
        toCheck[#toCheck + 1] = rawKey
    end
    for i = 1, #toCheck do
        CompactEventOverride(toCheck[i])
    end
    MarkEventConfigDirty()
end

local function BuildInterval(cdSeriesSec)
    if type(cdSeriesSec) ~= "table" then
        return nil
    end
    local out = {}
    for _, v in ipairs(cdSeriesSec) do
        local n = SafeNum(v)
        if n and n > 0 then
            out[#out + 1] = n
        end
    end
    if #out == 0 then return nil end
    if #out == 1 then return out[1] end
    return out
end

local function BuildTimelineSkill(eventID, event)
    if type(event) ~= "table" then return nil end
    if IsEventBlacklisted(eventID) then return nil end
    local first = SafeNum(event.firstSeenSec)
    if not first then
        return nil
    end

    local evenSpellID = SafeNum(event.evenSpellID)
    local spellID = SafeNum(event.spellID) or evenSpellID
    local name = nil
    local spellIdentifier = evenSpellID or spellID
    if spellIdentifier and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, apiName = pcall(C_Spell.GetSpellName, spellIdentifier)
        if ok and type(apiName) == "string" and apiName ~= "" then
            name = apiName
        end
    end
    if not name then
        name = event.eventName or event.name
            or (spellID and ("技能 " .. tostring(spellID)))
            or ("事件 " .. tostring(eventID))
    end
    local voiceLabel = tostring(event.voiceLabel or name or "")

    return {
        eventID = SafeNum(event.eventID) or SafeNum(eventID),
        spellID = spellID,
        evenSpellID = evenSpellID,
        spellIdentifier = evenSpellID or spellID,
        displayName = name,
        source = "fixed",
        first = first,
        interval = BuildInterval(event.cdSeriesSec),
        preAlert = 5,
        castDuration = 1.5,
        barPriority = 2,
        showBunBar = true,
        showTimerBar = true,
        screenAlert = false,
        preAlertText = "{name}",
        screenText = nil,
        voiceLabel = voiceLabel,
    }
end

local function BuildTimelineBossRow(mapID, bossID, boss)
    if type(boss) ~= "table" then return nil, nil end
    local encounterID = SafeNum(boss.encounterID) or SafeNum(bossID)
    if not encounterID then return nil, nil end

    local skills = {}
    if type(boss.events) == "table" then
        for eventID, event in pairs(boss.events) do
            local skill = BuildTimelineSkill(eventID, event)
            if skill then
                skills[#skills + 1] = skill
            end
        end
    end

    table.sort(skills, function(a, b)
        if a.first ~= b.first then
            return a.first < b.first
        end
        return (SafeNum(a.eventID) or 0) < (SafeNum(b.eventID) or 0)
    end)

    local fixedSet = _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS or {}
    local canFixed = (fixedSet[encounterID] == true) and (#skills > 0)

    return encounterID, {
        encounterID = encounterID,
        name = boss.bossName or boss.name or tostring(encounterID),
        mapID = SafeNum(mapID),
        axisType = canFixed and "fixed" or "blizzard",
        skills = skills,
    }
end

local function GetEncounterMaps()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" then
        return nil
    end
    if type(data.maps) == "table" then
        return data.maps
    end
    return data
end

local function RebuildTimelineBosses()
    local maps = GetEncounterMaps()
    if type(maps) ~= "table" then
        print("|cffff4400ExBoss|r Store: 缺少 EncounterData（请启用 EXBossData 插件）")
        return
    end

    ExBoss = ExBoss or {}
    ExBoss.Timeline = ExBoss.Timeline or {}
    ExBoss.Timeline._bosses = {}

    for mapID, map in pairs(maps) do
        if type(map) == "table" and type(map.bosses) == "table" then
            for bossID, boss in pairs(map.bosses) do
                local encounterID, bossDef = BuildTimelineBossRow(mapID, bossID, boss)
                if encounterID and bossDef then
                    ExBoss.Timeline._bosses[encounterID] = bossDef
                end
            end
        end
    end
end

_G.EXBossData = _G.EXBossData or {}

local function NormalizeTrashPluginPresetRow(pluginKey, row)
    pluginKey = TrimString(pluginKey)
    if pluginKey == "" or type(row) ~= "table" then
        return nil, "invalid trash preset"
    end
    if type(row.trashConfig) ~= "table" then
        return nil, "missing trashConfig"
    end
    return {
        pluginKey = pluginKey,
        authorKey = TrimString(row.authorKey or row.authorName or pluginKey),
        authorName = TrimString(row.authorName or row.authorKey or pluginKey),
        title = TrimString(row.title or row.authorName or row.authorKey or pluginKey),
        builtIn = (row.builtIn == true),
        note = tostring(row.note or ""),
        exportMeta = type(row.exportMeta) == "table" and DeepCopy(row.exportMeta) or nil,
        trashConfig = DeepCopy(row.trashConfig),
    }, nil
end

local function NormalizeSettingsPluginPresetRow(pluginKey, row)
    pluginKey = TrimString(pluginKey)
    if pluginKey == "" or type(row) ~= "table" then
        return nil, "invalid settings preset"
    end
    if type(row.settingsPageConfig) ~= "table" then
        return nil, "missing settingsPageConfig"
    end
    return {
        pluginKey = pluginKey,
        authorKey = TrimString(row.authorKey or row.authorName or pluginKey),
        authorName = TrimString(row.authorName or row.authorKey or pluginKey),
        title = TrimString(row.title or row.authorName or row.authorKey or pluginKey),
        builtIn = (row.builtIn == true),
        note = tostring(row.note or ""),
        exportMeta = type(row.exportMeta) == "table" and DeepCopy(row.exportMeta) or nil,
        settingsPageConfig = DeepCopy(row.settingsPageConfig),
    }, nil
end

function _G.EXBossData.RegisterTrashPluginPreset(pluginKey, row)
    local normalized, err = NormalizeTrashPluginPresetRow(pluginKey, row)
    if not normalized then
        return false, err
    end
    TRASH_PLUGIN_ROOT.packs = type(TRASH_PLUGIN_ROOT.packs) == "table" and TRASH_PLUGIN_ROOT.packs or {}
    TRASH_PLUGIN_ROOT.packs[normalized.pluginKey] = normalized
    return true
end

function _G.EXBossData.GetTrashPluginPreset(pluginKey)
    local key = TrimString(pluginKey)
    if key == "" then
        return nil
    end
    local pluginPacks = type(TRASH_PLUGIN_ROOT) == "table" and type(TRASH_PLUGIN_ROOT.packs) == "table" and TRASH_PLUGIN_ROOT.packs or nil
    local row = pluginPacks and pluginPacks[key] or nil
    if type(row) == "table" then
        return DeepCopy(row)
    end
    local builtInPacks = type(TRASH_BUILTIN_ROOT) == "table" and type(TRASH_BUILTIN_ROOT.packs) == "table" and TRASH_BUILTIN_ROOT.packs or nil
    row = builtInPacks and builtInPacks[key] or nil
    return type(row) == "table" and DeepCopy(row) or nil
end

function _G.EXBossData.GetTrashPluginPresetList()
    local out = {}
    local seen = {}
    local pluginPacks = type(TRASH_PLUGIN_ROOT) == "table" and type(TRASH_PLUGIN_ROOT.packs) == "table" and TRASH_PLUGIN_ROOT.packs or {}
    for _, row in pairs(pluginPacks) do
        if type(row) == "table" and type(row.trashConfig) == "table" then
            out[#out + 1] = DeepCopy(row)
            seen[TrimString(row.pluginKey)] = true
        end
    end
    local builtInPacks = type(TRASH_BUILTIN_ROOT) == "table" and type(TRASH_BUILTIN_ROOT.packs) == "table" and TRASH_BUILTIN_ROOT.packs or {}
    for _, row in pairs(builtInPacks) do
        local key = TrimString(type(row) == "table" and row.pluginKey or "")
        if type(row) == "table" and type(row.trashConfig) == "table" and not seen[key] then
            out[#out + 1] = DeepCopy(row)
            seen[key] = true
        end
    end
    table.sort(out, function(a, b)
        local an = TrimString(a.authorName or a.title or a.pluginKey)
        local bn = TrimString(b.authorName or b.title or b.pluginKey)
        if an ~= bn then
            return an < bn
        end
        return TrimString(a.pluginKey) < TrimString(b.pluginKey)
    end)
    return out
end

function _G.EXBossData.RegisterSettingsPluginPreset(pluginKey, row)
    local normalized, err = NormalizeSettingsPluginPresetRow(pluginKey, row)
    if not normalized then
        return false, err
    end
    SETTINGS_PLUGIN_ROOT.packs = type(SETTINGS_PLUGIN_ROOT.packs) == "table" and SETTINGS_PLUGIN_ROOT.packs or {}
    SETTINGS_PLUGIN_ROOT.packs[normalized.pluginKey] = normalized
    return true
end

function _G.EXBossData.GetSettingsPluginPreset(pluginKey)
    local key = TrimString(pluginKey)
    if key == "" then
        return nil
    end
    local pluginPacks = type(SETTINGS_PLUGIN_ROOT) == "table" and type(SETTINGS_PLUGIN_ROOT.packs) == "table" and SETTINGS_PLUGIN_ROOT.packs or nil
    local row = pluginPacks and pluginPacks[key] or nil
    if type(row) == "table" then
        return DeepCopy(row)
    end
    local builtInPacks = type(SETTINGS_BUILTIN_ROOT) == "table" and type(SETTINGS_BUILTIN_ROOT.packs) == "table" and SETTINGS_BUILTIN_ROOT.packs or nil
    row = builtInPacks and builtInPacks[key] or nil
    return type(row) == "table" and DeepCopy(row) or nil
end

function _G.EXBossData.GetSettingsPluginPresetList()
    local out = {}
    local seen = {}
    local pluginPacks = type(SETTINGS_PLUGIN_ROOT) == "table" and type(SETTINGS_PLUGIN_ROOT.packs) == "table" and SETTINGS_PLUGIN_ROOT.packs or {}
    for _, row in pairs(pluginPacks) do
        if type(row) == "table" and type(row.settingsPageConfig) == "table" then
            out[#out + 1] = DeepCopy(row)
            seen[TrimString(row.pluginKey)] = true
        end
    end
    local builtInPacks = type(SETTINGS_BUILTIN_ROOT) == "table" and type(SETTINGS_BUILTIN_ROOT.packs) == "table" and SETTINGS_BUILTIN_ROOT.packs or {}
    for _, row in pairs(builtInPacks) do
        local key = TrimString(type(row) == "table" and row.pluginKey or "")
        if type(row) == "table" and type(row.settingsPageConfig) == "table" and not seen[key] then
            out[#out + 1] = DeepCopy(row)
            seen[key] = true
        end
    end
    table.sort(out, function(a, b)
        local an = TrimString(a.authorName or a.title or a.pluginKey)
        local bn = TrimString(b.authorName or b.title or b.pluginKey)
        if an ~= bn then
            return an < bn
        end
        return TrimString(a.pluginKey) < TrimString(b.pluginKey)
    end)
    return out
end

function _G.EXBossData.GetEncounterDataRoot()
    return GetEncounterMaps() or {}
end

function _G.EXBossData.GetFactoryEventDefaults(eventID)
    local eid = tonumber(eventID)
    if eid then
        if IsEventBlacklisted(eid) then
            return nil
        end
        return GetFactoryDefaultEvent(eid)
    end
    return GetFactoryDefaultsRoot()
end

function _G.EXBossData.GetEventOverrideRoot()
    return GetOverrideRoot()
end

function _G.EXBossData.GetResolvedEventConfig(eventID)
    if IsEventBlacklisted(eventID) then
        return nil
    end
    return BuildResolvedEvent(eventID)
end

function _G.EXBossData.GetEventConfigRoot()
    return BuildResolvedRoot()
end

function _G.EXBossData.TouchEventConfig(eventID)
    MarkEventConfigDirty(eventID)
end

function _G.EXBossData.CompactEventOverride(eventID)
    if IsEventBlacklisted(eventID) then
        return nil
    end
    return CompactEventOverride(eventID)
end

function _G.EXBossData.CompactExternalEventOverride(eventID, row)
    if IsEventBlacklisted(eventID) then
        return nil
    end
    return BuildCompactedEventOverride(eventID, row)
end

function _G.EXBossData.IsEventBlacklisted(eventID)
    return IsEventBlacklisted(eventID)
end

function _G.EXBossData.CompactAllEventOverrides()
    CompactAllEventOverrides()
end

function _G.EXBossData.GetTimelineModeDB()
    InitEXBossDataDB()
    local tdb = EXBossDataDB.timer.timelineMode
    if type(tdb.byEncounter) ~= "table" then tdb.byEncounter = {} end
    if type(tdb.default) ~= "string" or tdb.default == "" then tdb.default = "auto" end
    return tdb
end

function _G.EXBossData.RebuildTimelineBosses()
    RebuildTimelineBosses()
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addonName)
        if tostring(addonName or ""):lower() == "exbossdata" then
            InitEXBossDataDB()
            CompactAllEventOverrides()
            RebuildTimelineBosses()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

RebuildTimelineBosses()
