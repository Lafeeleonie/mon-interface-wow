---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.CustomEvents or {}
ExBoss.TrashCD.CustomEvents = Mod
ExBoss.Trash.CustomEvents = Mod

local Store = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil

Mod._defsByKey = Mod._defsByKey or {}
Mod._rowsByMap = Mod._rowsByMap or {}
Mod._mapsByID = Mod._mapsByID or {}

local function NormalizeText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for key, value in pairs(src) do
        out[key] = DeepCopy(value)
    end
    return out
end

local function BuildKey(mapID, npcID, spellID)
    if Store and type(Store.GetSpellEntryKey) == "function" then
        return Store.GetSpellEntryKey(mapID, npcID, spellID)
    end
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    local sid = tonumber(spellID)
    if not (mid and nid and sid) then
        return nil
    end
    return string.format("%d:%d:%d", mid, nid, sid)
end

local function NormalizeTrigger(trigger)
    local t = tostring(trigger or "cast_start")
    if t == "cast_start" or t == "channel_start" or t == "custom" then
        return t
    end
    return "custom"
end

local function BuildTriggerLabel(def)
    local trigger = NormalizeTrigger(def and def.trigger)
    if trigger == "cast_start" then
        if def and def.firstOnly == true then
            return "首次施法开始"
        end
        return "施法开始"
    end
    if trigger == "channel_start" then
        if def and def.firstOnly == true then
            return "首次引导开始"
        end
        return "引导开始"
    end
    return NormalizeText(def and def.triggerLabel) ~= "" and tostring(def.triggerLabel) or "自定义事件"
end

function Mod.Register(def)
    if type(def) ~= "table" then
        return nil, "invalid def"
    end
    local mapID = tonumber(def.mapID)
    local npcID = tonumber(def.npcID)
    local spellID = tonumber(def.spellID)
    if not (mapID and npcID and spellID and spellID > 0) then
        return nil, "invalid ids"
    end

    local key = BuildKey(mapID, npcID, spellID)
    if not key then
        return nil, "bad key"
    end

    local normalized = {
        mapID = mapID,
        npcID = npcID,
        spellID = spellID,
        mapName = NormalizeText(def.mapName),
        mobName = NormalizeText(def.mobName),
        spellName = NormalizeText(def.spellName),
        description = NormalizeText(def.description),
        iconFileID = tonumber(def.iconFileID) or 134400,
        trigger = NormalizeTrigger(def.trigger),
        triggerLabel = BuildTriggerLabel(def),
        firstOnly = def.firstOnly == true,
        eventCategory = NormalizeText(def.eventCategory),
        preset = type(def.preset) == "table" and DeepCopy(def.preset) or nil,
    }

    if normalized.spellName == "" then
        normalized.spellName = normalized.triggerLabel
    end
    if normalized.description == "" then
        normalized.description = string.format("识别到该NPC后，在%s时触发。", normalized.triggerLabel)
    end
    if normalized.eventCategory == "" then
        normalized.eventCategory = "custom"
    end

    Mod._defsByKey[key] = normalized
    Mod._rowsByMap[mapID] = Mod._rowsByMap[mapID] or {}
    Mod._mapsByID[mapID] = {
        mapID = mapID,
        mapName = normalized.mapName,
    }

    local rows = Mod._rowsByMap[mapID]
    local replaced = false
    for i = 1, #rows do
        if tonumber(rows[i].npcID) == npcID and tonumber(rows[i].spellID) == spellID then
            rows[i] = {
                mapID = mapID,
                npcID = npcID,
                mobName = normalized.mobName,
                spellID = spellID,
                spellName = normalized.spellName,
                first = nil,
                castTime = nil,
                cd = nil,
                isCustomEvent = true,
                customTrigger = normalized.trigger,
                customTriggerLabel = normalized.triggerLabel,
                description = normalized.description,
                iconFileID = normalized.iconFileID,
            }
            replaced = true
            break
        end
    end
    if not replaced then
        rows[#rows + 1] = {
            mapID = mapID,
            npcID = npcID,
            mobName = normalized.mobName,
            spellID = spellID,
            spellName = normalized.spellName,
            first = nil,
            castTime = nil,
            cd = nil,
            isCustomEvent = true,
            customTrigger = normalized.trigger,
            customTriggerLabel = normalized.triggerLabel,
            description = normalized.description,
            iconFileID = normalized.iconFileID,
        }
    end
    return key
end

function Mod.GetDefinition(mapID, npcID, spellID)
    local key = BuildKey(mapID, npcID, spellID)
    local row = key and Mod._defsByKey[key] or nil
    return type(row) == "table" and row or nil
end

function Mod.GetPreset(mapID, npcID, spellID)
    local row = Mod.GetDefinition(mapID, npcID, spellID)
    local preset = row and row.preset or nil
    return type(preset) == "table" and DeepCopy(preset) or nil
end

function Mod.GetRowsForMap(mapID)
    local mid = tonumber(mapID)
    if not mid then
        return {}
    end
    local rows = Mod._rowsByMap[mid]
    if type(rows) ~= "table" then
        return {}
    end
    return rows
end

function Mod.GetRegisteredMaps()
    local out = {}
    for mapID, row in pairs(Mod._mapsByID) do
        out[#out + 1] = {
            mapID = tonumber(mapID),
            mapName = tostring(type(row) == "table" and row.mapName or ""),
        }
    end
    return out
end

local function GetObservationTest()
    return ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
end

function Mod.NormalizeNameplateUnit(unit)
    local test = GetObservationTest()
    if test and type(test.NormalizeNameplateUnit) == "function" then
        return test.NormalizeNameplateUnit(unit)
    end
    if type(unit) ~= "string" then
        return nil
    end
    local index = unit:match("^nameplate(%d+)$")
    if not index then
        return nil
    end
    return "nameplate" .. index
end

function Mod.GetRuntimeByUnit(unit)
    local test = GetObservationTest()
    if test and type(test.GetRuntimeByUnit) == "function" then
        return test.GetRuntimeByUnit(unit)
    end
    return nil
end

ExBoss.Trash.GetRuntimeByUnit = Mod.GetRuntimeByUnit
ExBoss.Trash.NormalizeNameplateUnit = Mod.NormalizeNameplateUnit

local function BuildStandaloneTrigger(enabled, source, label, lsm, path)
    return {
        enabled = enabled == true,
        sourceType = tostring(source or "pack"),
        label = tostring(label or ""),
        customLSM = tostring(lsm or ""),
        customPath = tostring(path or ""),
        fixedOffsetMode = "delay",
        fixedOffsetSeconds = 0,
    }
end

local function ResolveTriggerDelay(mode, seconds)
    local delay = math.max(0, tonumber(seconds) or 0)
    if tostring(mode or "delay") == "delay" then
        return delay
    end
    return 0
end

local function ResolveEventColor(cfg)
    if type(cfg) ~= "table" or cfg.eventColorEnabled ~= true then
        return nil
    end
    if type(cfg.eventColor) ~= "table" then
        return nil
    end
    return {
        r = tonumber(cfg.eventColor.r) or 1,
        g = tonumber(cfg.eventColor.g) or 1,
        b = tonumber(cfg.eventColor.b) or 1,
        a = tonumber(cfg.eventColor.a) or 1,
    }
end

local function ResolveCentralText(cfg, def, spec)
    local custom = NormalizeText(type(cfg) == "table" and cfg.centralText or "")
    if custom ~= "" then
        return custom
    end
    local defName = NormalizeText(type(def) == "table" and def.spellName or "")
    if defName ~= "" then
        return defName
    end
    local specName = NormalizeText(type(spec) == "table" and spec.displayName or "")
    if specName ~= "" then
        return specName
    end
    return "小怪提示"
end

local function PlayStandaloneVoice(runtime, cfg, def, index, uniqueKey)
    if type(cfg) ~= "table" then
        return false
    end
    local enabledKey = (index == 1) and "voice1Enabled" or "voice2Enabled"
    if cfg[enabledKey] ~= true then
        return false
    end

    local triggerCfg = BuildStandaloneTrigger(
        cfg[enabledKey],
        cfg[(index == 1) and "voice1Source" or "voice2Source"],
        cfg[(index == 1) and "voice1Label" or "voice2Label"],
        cfg[(index == 1) and "voice1LSM" or "voice2LSM"],
        cfg[(index == 1) and "voice1Path" or "voice2Path"]
    )
    local delay = ResolveTriggerDelay(
        cfg[(index == 1) and "voice1OffsetMode" or "voice2OffsetMode"],
        cfg[(index == 1) and "voice1OffsetSeconds" or "voice2OffsetSeconds"]
    )
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine or nil
    if not (Engine and type(Engine.TryPlayStandaloneSound) == "function") then
        return false
    end

    local function Fire()
        Engine:TryPlayStandaloneSound(triggerCfg, uniqueKey .. ":voice" .. tostring(index), {
            triggerIndex = index,
            throttle = false,
        })
    end

    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, Fire)
    else
        Fire()
    end
    return true
end

local function BuildUniqueKey(spec)
    return table.concat({
        tostring(tonumber(spec.mapID) or 0),
        tostring(tonumber(spec.npcID) or 0),
        tostring(tonumber(spec.spellID) or 0),
        tostring(spec.trigger or "custom"),
        string.format("%.3f", GetTime()),
    }, ":")
end

function Mod.TriggerEvent(spec)
    if type(spec) ~= "table" then
        return false, "invalid spec"
    end
    local mapID = tonumber(spec.mapID)
    local npcID = tonumber(spec.npcID)
    local spellID = tonumber(spec.spellID)
    if not (mapID and npcID and spellID) then
        return false, "bad ids"
    end

    local cfg = Store and type(Store.GetResolvedSpellEntry) == "function"
        and Store.GetResolvedSpellEntry(mapID, npcID, spellID, false)
        or nil
    if type(cfg) ~= "table" then
        return false, "no cfg"
    end
    if cfg.enabled ~= true then
        return false, "cfg disabled"
    end

    local def = Mod.GetDefinition(mapID, npcID, spellID)
    local uniqueKey = BuildUniqueKey(spec)
    local fired = false

    if cfg.centralEnabled == true and ExBoss.UI and ExBoss.UI.FlashText and type(ExBoss.UI.FlashText.Show) == "function" then
        ExBoss.UI.FlashText:Show({
            instant = true,
            color = ResolveEventColor(cfg),
            source = "trash_custom",
        }, ResolveCentralText(cfg, def, spec), 1.5)
        fired = true
    end

    if PlayStandaloneVoice(spec.runtime, cfg, def, 1, uniqueKey) == true then
        fired = true
    end
    if PlayStandaloneVoice(spec.runtime, cfg, def, 2, uniqueKey) == true then
        fired = true
    end

    return fired, fired and nil or "no output"
end

local function BuildSpecFromArgs(mapID, npcID, spellID, trigger, unit, runtime, displayName)
    return {
        mapID = tonumber(mapID),
        npcID = tonumber(npcID),
        spellID = tonumber(spellID),
        trigger = trigger,
        unit = unit,
        runtime = runtime,
        displayName = displayName,
    }
end

function ExBoss.TriggerTrashEvent(selfOrSpec, maybeSpec, ...)
    local spec
    if selfOrSpec == ExBoss then
        if type(maybeSpec) == "table" then
            spec = maybeSpec
        else
            spec = BuildSpecFromArgs(maybeSpec, ...)
        end
    else
        if type(selfOrSpec) == "table" then
            spec = selfOrSpec
        else
            spec = BuildSpecFromArgs(selfOrSpec, maybeSpec, ...)
        end
    end
    return Mod.TriggerEvent(spec)
end

ExBoss.TrashTrigger = ExBoss.TriggerTrashEvent
ExBoss.TRASHTRIGGER = ExBoss.TriggerTrashEvent
