---@diagnostic disable: undefined-global

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local BossConfig = ExBoss.Modules.Boss
ExBoss.BossConfig = BossConfig

local DB_VERSION = 4

local SLOT_ORDER = {
    "raid_tank",
    "raid_dps",
    "raid_heal",
    "mplus_tank",
    "mplus_dps",
    "mplus_heal",
}

local SLOT_META = {
    raid_tank =  { scene = "raid",  role = "tank", label = "团本坦克", short = "RaidTank" },
    raid_dps =   { scene = "raid",  role = "dps",  label = "团本DPS",  short = "RaidDps" },
    raid_heal =  { scene = "raid",  role = "heal", label = "团本治疗", short = "RaidHealer" },
    mplus_tank = { scene = "mplus", role = "tank", label = "大米坦克", short = "MplusTank" },
    mplus_dps =  { scene = "mplus", role = "dps",  label = "大米DPS",  short = "MplusDps" },
    mplus_heal = { scene = "mplus", role = "heal", label = "大米治疗", short = "MplusHealer" },
}

local IMPORT_ROLE_SUFFIX = {
    tank = "坦克",
    dps = "DPS",
    heal = "治疗",
}

local HIDDEN_AUTHOR_KEYS = {
    A = true,
}

local _sceneIndexCache = nil
local _sceneIndexSource = nil

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

local PRIVATE_AURA_ENTRY_DEFAULTS = {
    enabled = true,
    sourceType = "pack",
    label = "",
    customLSM = "",
    customPath = "",
}

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

local function NormalizeRoleKey(role)
    local v = tostring(role or ""):lower()
    if v == "tank" then return "tank" end
    if v == "heal" or v == "healer" then return "heal" end
    if v == "dps" or v == "damage" or v == "damager" then return "dps" end
    return "dps"
end

local function TrimString(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local _lsmSoundLookupCache = nil

local function StripLSMFormattingCodes(value)
    local text = TrimString(value)
    if text == "" then
        return ""
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    return TrimString(text)
end

local function StripLeadingVoicePackPrefix(value)
    local text = StripLSMFormattingCodes(value)
    if text == "" then
        return ""
    end
    text = text:gsub("^%[[^%]]+%]", "")
    return TrimString(text)
end

local function GetLSMSoundLookupCache()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        _lsmSoundLookupCache = nil
        return nil
    end

    local hash = LSM:HashTable("sound")
    if type(hash) ~= "table" then
        _lsmSoundLookupCache = nil
        return nil
    end

    if _lsmSoundLookupCache and _lsmSoundLookupCache.hash == hash then
        return _lsmSoundLookupCache
    end

    local byAlias = {}
    for actualKey in pairs(hash) do
        if type(actualKey) == "string" and actualKey ~= "" then
            local plain = StripLSMFormattingCodes(actualKey)
            if plain ~= "" and not byAlias[plain] then
                byAlias[plain] = actualKey
            end
            local noPack = StripLeadingVoicePackPrefix(plain)
            if noPack ~= "" and not byAlias[noPack] then
                byAlias[noPack] = actualKey
            end
        end
    end

    _lsmSoundLookupCache = {
        hash = hash,
        byAlias = byAlias,
    }
    return _lsmSoundLookupCache
end

local function ResolveCanonicalLSMSoundKey(value)
    local key = TrimString(value)
    if key == "" then
        return ""
    end

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return key
    end

    local path = LSM:Fetch("sound", key, true)
    if type(path) == "string" and path ~= "" then
        return key
    end

    local cache = GetLSMSoundLookupCache()
    local hash = cache and cache.hash or nil
    if type(hash) == "table" then
        local direct = hash[key]
        if type(direct) == "string" and direct ~= "" then
            return key
        end
        local plain = StripLSMFormattingCodes(key)
        local aliased = cache.byAlias[plain]
        if type(aliased) == "string" and aliased ~= "" then
            return aliased
        end
        local noPack = StripLeadingVoicePackPrefix(plain)
        aliased = cache.byAlias[noPack]
        if type(aliased) == "string" and aliased ~= "" then
            return aliased
        end
    end

    return key
end

local function NormalizeStandaloneTriggerLSMKey(trigger)
    if type(trigger) ~= "table" then
        return trigger
    end
    local sourceType = tostring(trigger.sourceType or "pack"):lower()
    if sourceType == "lsm" then
        trigger.customLSM = ResolveCanonicalLSMSoundKey(trigger.customLSM)
    end
    return trigger
end

local function NormalizeResolvedEventVoiceTriggers(row)
    if type(row) ~= "table" then
        return row
    end
    local triggers = type(row.triggers) == "table" and row.triggers or nil
    if type(triggers) ~= "table" then
        return row
    end
    for _, triggerCfg in pairs(triggers) do
        if type(triggerCfg) == "table" then
            NormalizeStandaloneTriggerLSMKey(triggerCfg)
        end
    end
    return row
end

local function StripImportRoleSuffix(authorKey)
    local text = TrimString(authorKey)
    if text == "" then
        return ""
    end
    for _, suffix in pairs(IMPORT_ROLE_SUFFIX) do
        for _, prefix in ipairs({ "-", "_", " " }) do
            local ending = prefix .. suffix
            if #text > #ending and text:sub(-#ending):lower() == ending:lower() then
                return TrimString(text:sub(1, #text - #ending))
            end
        end
        if #text > #suffix and text:sub(-#suffix):lower() == suffix:lower() then
            return TrimString(text:sub(1, #text - #suffix))
        end
    end
    return text
end

local function BuildImportedAuthorKey(authorKey, slotKey)
    local base = StripImportRoleSuffix(authorKey)
    local meta = SLOT_META[tostring(slotKey or ""):lower()]
    local suffix = meta and IMPORT_ROLE_SUFFIX[meta.role] or nil
    if base == "" or not suffix then
        return base
    end
    return string.format("%s-%s", base, suffix)
end

local function NormalizeSceneKey(scene)
    local v = tostring(scene or ""):lower()
    if v == "raid" then
        return "raid"
    end
    return "mplus"
end

local function NormalizeSlotKey(slotKey)
    local key = tostring(slotKey or ""):lower()
    if SLOT_META[key] then
        return key
    end
    local compact = key:gsub("[%s%-_]+", "")
    for candidate, meta in pairs(SLOT_META) do
        local cmp = candidate:gsub("[%s%-_]+", "")
        if compact == cmp or compact == tostring(meta.short or ""):lower() then
            return candidate
        end
    end
    return nil
end

local function EnsureBossSceneOptions()
    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.general = ExBossDB.ui.general or {}
    local g = ExBossDB.ui.general
    if g.bossAlertsEnabledMplus == nil then
        g.bossAlertsEnabledMplus = true
    else
        g.bossAlertsEnabledMplus = (g.bossAlertsEnabledMplus == true)
    end
    if g.bossAlertsEnabledRaid == nil then
        g.bossAlertsEnabledRaid = true
    else
        g.bossAlertsEnabledRaid = (g.bossAlertsEnabledRaid == true)
    end
    return g
end

local function GetPresetRoot()
    local root = _G.EXBOSS_AUTHOR_PRESETS
    if type(root) ~= "table" or type(root.slots) ~= "table" then
        return { slots = {} }
    end
    return root
end

local function HasPresetAuthorForSlot(slotKey, authorKey)
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    authorKey = tostring(authorKey or "")
    if authorKey == "" then
        return false
    end
    local slot = GetPresetRoot().slots[slotKey]
    return type(slot) == "table" and type(slot[authorKey]) == "table"
end

local function GetFirstAuthorKey(slotKey)
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    local slot = GetPresetRoot().slots[slotKey]
    if type(slot) ~= "table" then
        return nil
    end
    local keys = {}
    for key in pairs(slot) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys[1]
end

local function GetDefaultAuthorKey(slotKey)
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    local slot = GetPresetRoot().slots[slotKey]
    if type(slot) == "table" and type(slot.PresetConfig) == "table" then
        return "PresetConfig"
    end
    return GetFirstAuthorKey(slotKey)
end

local function GetEventScene(eventID)
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if _sceneIndexCache and _sceneIndexSource == data then
        return _sceneIndexCache[tonumber(eventID)]
    end
    local out = {}
    if type(data) == "table" and type(data.maps) == "table" then
        for _, mapRow in pairs(data.maps) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                local cat = tostring(mapRow.category or "")
                local itype = tonumber(mapRow.instanceType)
                local scene = ((itype == 2) or cat:find("团") ~= nil) and "raid" or "mplus"
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for rawEventID in pairs(bossRow.events) do
                            local eid = tonumber(rawEventID)
                            if eid then
                                out[eid] = scene
                            end
                        end
                    end
                end
            end
        end
    end
    _sceneIndexCache = out
    _sceneIndexSource = data
    return out[tonumber(eventID)]
end

local function GetCurrentRoleKey()
    local state = ExwindTools and ExwindTools.State
    return NormalizeRoleKey(state and state.RoleKey)
end

local function GetFactoryDefaultsRoot()
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetFactoryEventDefaults) == "function" then
        return api.GetFactoryEventDefaults()
    end
    return {}
end

local function GetFactoryEvent(eventID)
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetFactoryEventDefaults) == "function" then
        return api.GetFactoryEventDefaults(eventID)
    end
    local root = GetFactoryDefaultsRoot()
    return root[tonumber(eventID)]
end

local function TouchLegacyRoot(eventID)
    local api = _G.EXBossData
    if type(api) == "table" and type(api.TouchEventConfig) == "function" then
        api.TouchEventConfig(eventID)
    end
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

local function NormalizePrivateAuraSourceType(value)
    local sourceType = tostring(value or "pack"):lower()
    if sourceType ~= "lsm" and sourceType ~= "file" then
        sourceType = "pack"
    end
    return sourceType
end

local function NormalizePrivateAuraEntryRow(row)
    row = type(row) == "table" and row or {}
    if row.enabled == nil then
        row.enabled = PRIVATE_AURA_ENTRY_DEFAULTS.enabled
    else
        row.enabled = row.enabled == true
    end
    row.sourceType = NormalizePrivateAuraSourceType(row.sourceType or PRIVATE_AURA_ENTRY_DEFAULTS.sourceType)
    row.label = tostring(row.label or PRIVATE_AURA_ENTRY_DEFAULTS.label)
    row.customLSM = tostring(row.customLSM or PRIVATE_AURA_ENTRY_DEFAULTS.customLSM)
    row.customPath = tostring(row.customPath or PRIVATE_AURA_ENTRY_DEFAULTS.customPath)
    if row.sourceType == "pack" then
        row.customLSM = ""
        row.customPath = ""
    elseif row.sourceType == "lsm" then
        row.customLSM = ResolveCanonicalLSMSoundKey(row.customLSM)
        row.label = ""
        row.customPath = ""
    else
        row.label = ""
        row.customLSM = ""
    end
    return row
end

local function NormalizePrivateAuraCategoryRow(row)
    return NormalizePrivateAuraEntryRow(row)
end

local function BuildEmptyPrivateAuraRoot()
    return {
        categories = {},
        entries = {},
    }
end

local function NormalizePrivateAuraKey(value)
    local key = tostring(value or "")
    if key == "" then
        return nil
    end
    if key:match("^pa:raid:%d+:%d+$") then
        return key
    end
    if key:match("^pa:mplus:boss:.+:%d+$") then
        return key
    end
    return nil
end

local function GetPrivateAuraSceneKey(privateAuraKey)
    local normalized = NormalizePrivateAuraKey(privateAuraKey)
    if not normalized then
        return nil
    end
    if normalized:match("^pa:raid:") then
        return "raid"
    end
    if normalized:match("^pa:mplus:boss:") then
        return "mplus"
    end
    return nil
end

local function NormalizePrivateAuraRoot(row)
    if type(row) ~= "table" then
        return nil
    end
    local out = BuildEmptyPrivateAuraRoot()
    local categories = type(row.categories) == "table" and row.categories or {}
    for i = 1, 2 do
        local src = categories[i]
        if type(src) == "table" then
            out.categories[i] = NormalizePrivateAuraCategoryRow(DeepCopy(src))
        end
    end
    local entries = type(row.entries) == "table" and row.entries or {}
    for rawKey, src in pairs(entries) do
        local key = NormalizePrivateAuraKey(rawKey)
        if key and type(src) == "table" then
            out.entries[key] = NormalizePrivateAuraEntryRow(DeepCopy(src))
        end
    end
    if next(out.categories) == nil and next(out.entries) == nil then
        return nil
    end
    return out
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
    NormalizeStandaloneTriggerLSMKey(trigger)
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

local function NormalizeLinkedText(v)
    if type(v) ~= "string" then
        return ""
    end
    return v:gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsLegacyEmptyPackLabel(v)
    local t = NormalizeLinkedText(v)
    if t == "" then
        return true
    end
    return t == "无" or t:lower() == "none"
end

local function NormalizeLinkedTriggerPackLabel(triggerIndex, triggerCfg)
    if type(triggerCfg) ~= "table" then
        return ""
    end
    local sourceType = tostring(triggerCfg.sourceType or "pack")
    local label = triggerCfg.label
    if sourceType ~= "pack" then
        return NormalizeLinkedText(label)
    end
    if tonumber(triggerIndex) == 2 and IsLegacyEmptyPackLabel(label) then
        return "54321"
    end
    if IsLegacyEmptyPackLabel(label) then
        return ""
    end
    return NormalizeLinkedText(label)
end

local function ResolveLinkedTextFields(row)
    local resolved = {
        preAlertText = NormalizeLinkedText(type(row) == "table" and row.preAlertText or nil),
        timerBarRenameText = NormalizeLinkedText(type(row) == "table" and row.timerBarRenameText or nil),
    }
    local triggers = type(row) == "table" and row.triggers or nil
    if type(triggers) == "table" then
        if resolved.preAlertText == "" then
            local preset = NormalizeLinkedTriggerPackLabel(2, triggers[2])
            if preset == "54321" then
                preset = ""
            end
            if preset ~= "" then
                resolved.preAlertText = preset
            end
        end
        if resolved.timerBarRenameText == "" then
            local preset = NormalizeLinkedTriggerPackLabel(1, triggers[1])
            if preset ~= "" then
                resolved.timerBarRenameText = preset
            end
        end
    end
    return resolved
end

local function MigrateLegacyPrivateAuraOptionsIntoBossConfig(db)
    if type(db) ~= "table" or db.privateAuraOptionsMigrated == true then
        return
    end
    local legacyRoot = ExwindTools and ExwindTools.GetModuleDB and ExwindTools:GetModuleDB("ExBoss.PrivateAuraOptions", {
        entries = {},
    }) or nil
    local legacyEntries = type(legacyRoot) == "table" and type(legacyRoot.entries) == "table" and legacyRoot.entries or nil
    local migratedAny = false
    if type(legacyEntries) ~= "table" or next(legacyEntries) == nil then
        db.privateAuraOptionsMigrated = true
        return
    end

    local slotGroups = {
        raid = { "raid_tank", "raid_dps", "raid_heal" },
        mplus = { "mplus_tank", "mplus_dps", "mplus_heal" },
    }

    for rawKey, rawRow in pairs(legacyEntries) do
        local key = NormalizePrivateAuraKey(rawKey)
        local sceneKey = GetPrivateAuraSceneKey(key)
        local normalizedRow = type(rawRow) == "table" and NormalizePrivateAuraEntryRow(DeepCopy(rawRow)) or nil
        local slots = sceneKey and slotGroups[sceneKey] or nil
        if key and normalizedRow and type(slots) == "table" then
            for i = 1, #slots do
                local slotKey = slots[i]
                local authorKey = db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey)
                db.userOverrides[slotKey] = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or {}
                db.userOverrides[slotKey][authorKey] = type(db.userOverrides[slotKey][authorKey]) == "table"
                    and db.userOverrides[slotKey][authorKey] or {}
                db.userOverrides[slotKey][authorKey].events = type(db.userOverrides[slotKey][authorKey].events) == "table"
                    and db.userOverrides[slotKey][authorKey].events or {}
                local root = NormalizePrivateAuraRoot(db.userOverrides[slotKey][authorKey].privateAura) or BuildEmptyPrivateAuraRoot()
                db.userOverrides[slotKey][authorKey].privateAura = root
                root.entries[key] = DeepCopy(normalizedRow)
                migratedAny = true
            end
        end
    end

    if migratedAny and type(ExwindToolsDB) == "table" and type(ExwindToolsDB.ModuleDB) == "table" then
        ExwindToolsDB.ModuleDB["ExBoss.PrivateAuraOptions"] = nil
    end
    db.privateAuraOptionsMigrated = true
end

local StripLegacyRoleFields

local function NormalizeEventOverrideRowForStorage(row)
    if type(row) ~= "table" then
        return nil
    end
    -- Preserve explicit empty-string overrides for Boss text fields.
    -- Clearing these inputs must remain a real override instead of falling back to preset/default text.
    if type(row.preAlertText) == "string" and row.preAlertText == "" then
        row.preAlertTextManual = true
    else
        row.preAlertTextManual = nil
    end
    if type(row.timerBarRenameText) == "string" and row.timerBarRenameText == "" then
        row.timerBarRenameTextManual = true
    else
        row.timerBarRenameTextManual = nil
    end
    if type(row.color) == "table" then
        if type(row.color.scheme) == "string" and row.color.scheme == "" then
            row.color.scheme = nil
        end
        if next(row.color) == nil then
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
        row.triggers = next(normalized) and normalized or nil
    end
    if type(row.rules) == "table" then
        local cw = row.rules.castWindow
        if type(cw) == "table" and next(cw) == nil then
            row.rules.castWindow = nil
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

local function IsLegacyRoleSnapshotRow(row)
    if type(row) ~= "table" then
        return false
    end
    local hasLegacyRole = row.enabledRoles ~= nil
        or row.roleTankEnabled ~= nil
        or row.roleHealEnabled ~= nil
        or row.roleDpsEnabled ~= nil
    if not hasLegacyRole then
        return false
    end
    if type(row.centralText) == "string" and row.centralText ~= "" then
        return false
    end
    if type(row.preAlertText) == "string" and row.preAlertText ~= "" then
        return false
    end
    if type(row.timerBarRenameText) == "string" and row.timerBarRenameText ~= "" then
        return false
    end
    if type(row.color) == "table" and next(row.color) ~= nil then
        return false
    end
    if type(row.rules) == "table" and next(row.rules) ~= nil then
        return false
    end
    if type(row.triggers) == "table" then
        for _, triggerCfg in pairs(row.triggers) do
            if type(triggerCfg) == "table" then
                if type(triggerCfg.label) == "string" and triggerCfg.label ~= "" then
                    return false
                end
                if type(triggerCfg.customLSM) == "string" and triggerCfg.customLSM ~= "" then
                    return false
                end
                if type(triggerCfg.customPath) == "string" and triggerCfg.customPath ~= "" then
                    return false
                end
            end
        end
    end
    return true
end

local function BuildDefaultSelection()
    local out = {}
    for _, slotKey in ipairs(SLOT_ORDER) do
        out[slotKey] = GetDefaultAuthorKey(slotKey)
    end
    return out
end

local function ResolveDefaultEditSlot(scene)
    local role = GetCurrentRoleKey()
    return NormalizeSlotKey(string.format("%s_%s", NormalizeSceneKey(scene), role))
end

local GetPresetEvents
local ResolveSlotKeyForEvent
local BuildBaseResolvedForSlotAuthor
local CompactOverrideForSlotAuthor

local function EnsureDB()
    EXBossDataDB = EXBossDataDB or {}
    EXBossDataDB.bossConfig = EXBossDataDB.bossConfig or {}
    local db = EXBossDataDB.bossConfig
    db.slotSelection = type(db.slotSelection) == "table" and db.slotSelection or {}
    db.userOverrides = type(db.userOverrides) == "table" and db.userOverrides or {}
    local oldVersion = tonumber(db.version) or 0
    for _, slotKey in ipairs(SLOT_ORDER) do
        local defaultAuthor = GetDefaultAuthorKey(slotKey)
        local currentAuthor = db.slotSelection[slotKey]
        local userSlot = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or nil
        local hasUserAuthor = type(userSlot) == "table" and type(currentAuthor) == "string"
            and currentAuthor ~= "" and type(userSlot[currentAuthor]) == "table"
        if type(currentAuthor) ~= "string" or currentAuthor == "" then
            db.slotSelection[slotKey] = defaultAuthor
        elseif currentAuthor and not GetPresetEvents(slotKey, currentAuthor) and not hasUserAuthor and defaultAuthor then
            db.slotSelection[slotKey] = defaultAuthor
        end
        db.userOverrides[slotKey] = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or {}
    end
    if oldVersion < DB_VERSION then
        for _, slotKey in ipairs(SLOT_ORDER) do
            local slotRoot = db.userOverrides[slotKey]
            if type(slotRoot) == "table" then
                for authorKey, authorRow in pairs(slotRoot) do
                    local events = type(authorRow) == "table" and authorRow.events or nil
                    if type(events) == "table" then
                        local toCheck = {}
                        for rawEventID in pairs(events) do
                            toCheck[#toCheck + 1] = rawEventID
                        end
                        for i = 1, #toCheck do
                            local rawEventID = toCheck[i]
                            local eid = tonumber(rawEventID)
                            local compacted = CompactOverrideForSlotAuthor(eid, events[rawEventID], slotKey, authorKey)
                            if type(compacted) == "table" then
                                events[eid] = compacted
                            else
                                events[rawEventID] = nil
                            end
                        end
                    end
                    if type(authorRow) == "table" and authorRow.privateAura ~= nil then
                        authorRow.privateAura = NormalizePrivateAuraRoot(authorRow.privateAura)
                    end
                end
            end
        end
    end
    MigrateLegacyPrivateAuraOptionsIntoBossConfig(db)
    db.version = DB_VERSION
    db.editSlots = nil
    return db
end

local function EnsureAuthorSlotRoot(slotKey, authorKey)
    local db = EnsureDB()
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    authorKey = tostring(authorKey or db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey) or "")
    db.userOverrides[slotKey] = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or {}
    db.userOverrides[slotKey][authorKey] = type(db.userOverrides[slotKey][authorKey]) == "table" and db.userOverrides[slotKey][authorKey] or {}
    db.userOverrides[slotKey][authorKey].events = type(db.userOverrides[slotKey][authorKey].events) == "table" and db.userOverrides[slotKey][authorKey].events or {}
    return db.userOverrides[slotKey][authorKey]
end

local function EnsureAuthorOverrideRoot(slotKey, authorKey)
    return EnsureAuthorSlotRoot(slotKey, authorKey).events
end

local function GetAuthorOverrideRoot(slotKey, authorKey)
    local db = EnsureDB()
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    authorKey = tostring(authorKey or db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey) or "")
    local slot = db.userOverrides[slotKey]
    local author = type(slot) == "table" and slot[authorKey] or nil
    local events = type(author) == "table" and author.events or nil
    return type(events) == "table" and events or nil
end

local function EnsureAuthorPrivateAuraRoot(slotKey, authorKey)
    local author = EnsureAuthorSlotRoot(slotKey, authorKey)
    author.privateAura = NormalizePrivateAuraRoot(author.privateAura) or BuildEmptyPrivateAuraRoot()
    return author.privateAura
end

local function GetAuthorPrivateAuraRoot(slotKey, authorKey)
    local db = EnsureDB()
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    authorKey = tostring(authorKey or db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey) or "")
    local slot = db.userOverrides[slotKey]
    local author = type(slot) == "table" and slot[authorKey] or nil
    local privateAura = type(author) == "table" and author.privateAura or nil
    return NormalizePrivateAuraRoot(privateAura)
end

local function NormalizeExportEventRow(row)
    if type(row) ~= "table" then
        return nil
    end
    local normalized = NormalizeEventOverrideRowForStorage(DeepCopy(row))
    StripLegacyRoleFields(normalized)
    return normalized
end

GetPresetEvents = function(slotKey, authorKey)
    local presets = GetPresetRoot().slots
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    local slot = type(presets) == "table" and presets[slotKey] or nil
    local preset = type(slot) == "table" and slot[tostring(authorKey or "")] or nil
    local events = type(preset) == "table" and preset.events or nil
    return type(events) == "table" and events or nil
end

local function GetPresetPrivateAura(slotKey, authorKey)
    local presets = GetPresetRoot().slots
    slotKey = NormalizeSlotKey(slotKey) or slotKey
    local slot = type(presets) == "table" and presets[slotKey] or nil
    local preset = type(slot) == "table" and slot[tostring(authorKey or "")] or nil
    local privateAura = type(preset) == "table" and preset.privateAura or nil
    return NormalizePrivateAuraRoot(privateAura)
end

StripLegacyRoleFields = function(row)
    if type(row) ~= "table" then
        return row
    end
    row.enabledRoles = nil
    row.roleTankEnabled = nil
    row.roleHealEnabled = nil
    row.roleDpsEnabled = nil
    return row
end

BuildBaseResolvedForSlotAuthor = function(eventID, slotKey, authorKey)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    slotKey = ResolveSlotKeyForEvent(eid, slotKey)
    local defaults = GetFactoryEvent(eid)
    local presetEvents = GetPresetEvents(slotKey, authorKey)
    local preset = type(presetEvents) == "table" and presetEvents[eid] or nil
    StripLegacyRoleFields(preset)
    if type(defaults) ~= "table" and type(preset) ~= "table" then
        return nil
    end
    local base = DeepCopy(defaults or {})
    MergeOverride(base, preset)
    StripLegacyRoleFields(base)
    return base
end

CompactOverrideForSlotAuthor = function(eventID, row, slotKey, authorKey)
    local eid = tonumber(eventID)
    if not eid or type(row) ~= "table" then
        return nil
    end
    if IsLegacyRoleSnapshotRow(row) then
        return nil
    end
    local normalized = NormalizeEventOverrideRowForStorage(DeepCopy(row))
    StripLegacyRoleFields(normalized)
    if type(normalized) ~= "table" then
        return nil
    end
    local base = BuildBaseResolvedForSlotAuthor(eid, slotKey, authorKey)
    local compacted = BuildOverrideDelta(normalized, base or {})
    if type(compacted) == "table" then
        StripLegacyRoleFields(compacted)
        return compacted
    end
    return nil
end

ResolveSlotKeyForEvent = function(eventID, slotKey)
    local normalized = NormalizeSlotKey(slotKey)
    if normalized then
        return normalized
    end
    local scene = GetEventScene(eventID)
    scene = NormalizeSceneKey(scene)
    return ResolveDefaultEditSlot(scene)
end

local function MigrateLegacyOnce()
    local db = EnsureDB()
    if db.legacyMigrated == true then
        return
    end
    EXBossDataDB = EXBossDataDB or {}
    local legacyRoot = type(EXBossDataDB.events) == "table" and EXBossDataDB.events or nil
    if type(legacyRoot) ~= "table" or next(legacyRoot) == nil then
        db.legacyMigrated = true
        return
    end
    local role = GetCurrentRoleKey()
    for rawEventID, row in pairs(legacyRoot) do
        local eventID = tonumber(rawEventID)
        local scene = eventID and GetEventScene(eventID) or nil
        if eventID and scene and type(row) == "table" then
            local slotKey = NormalizeSlotKey(string.format("%s_%s", scene, role))
            if slotKey then
                local authorKey = db.slotSelection[slotKey] or GetFirstAuthorKey(slotKey)
                local root = EnsureAuthorOverrideRoot(slotKey, authorKey)
                root[eventID] = CompactOverrideForSlotAuthor(eventID, row, slotKey, authorKey)
            end
        end
    end
    db.legacyMigrated = true
end

local function BuildResolvedForSlot(eventID, slotKey)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    slotKey = ResolveSlotKeyForEvent(eid, slotKey)
    local defaults = GetFactoryEvent(eid)
    local db = EnsureDB()
    local authorKey = db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey)
    local presetEvents = GetPresetEvents(slotKey, authorKey)
    local userEvents = GetAuthorOverrideRoot(slotKey, authorKey)
    local preset = type(presetEvents) == "table" and presetEvents[eid] or nil
    local user = type(userEvents) == "table" and userEvents[eid] or nil
    StripLegacyRoleFields(preset)
    StripLegacyRoleFields(user)
    if type(defaults) ~= "table" and type(preset) ~= "table" and type(user) ~= "table" then
        return nil
    end
    local resolved = DeepCopy(defaults or {})
    MergeOverride(resolved, preset)
    MergeOverride(resolved, user)
    StripLegacyRoleFields(resolved)
    NormalizeResolvedEventVoiceTriggers(resolved)
    return resolved
end

local function BuildResolvedPrivateAuraForSlotAuthor(slotKey, authorKey)
    slotKey = NormalizeSlotKey(slotKey)
    if not slotKey then
        return nil
    end
    local preset = GetPresetPrivateAura(slotKey, authorKey)
    local user = GetAuthorPrivateAuraRoot(slotKey, authorKey)
    if type(preset) ~= "table" and type(user) ~= "table" then
        return nil
    end
    local resolved = { categories = {} }
    if type(preset) == "table" then
        MergeOverride(resolved, preset)
    end
    if type(user) == "table" then
        MergeOverride(resolved, user)
    end
    return NormalizePrivateAuraRoot(resolved)
end

local function BuildPublishedRootForRole(roleKey)
    local root = {}
    local db = EnsureDB()
    local role = NormalizeRoleKey(roleKey)
    local factory = GetFactoryDefaultsRoot()
    for _, scene in ipairs({ "raid", "mplus" }) do
        local seen = {}
        local slotKey = NormalizeSlotKey(string.format("%s_%s", scene, role))
        local authorKey = db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey)
        local presetEvents = GetPresetEvents(slotKey, authorKey)
        local userEvents = GetAuthorOverrideRoot(slotKey, authorKey)
        for rawEventID in pairs(factory) do
            local eid = tonumber(rawEventID)
            if eid and GetEventScene(eid) == scene then
                seen[eid] = true
            end
        end
        if type(presetEvents) == "table" then
            for rawEventID in pairs(presetEvents) do
                local eid = tonumber(rawEventID)
                if eid and GetEventScene(eid) == scene then
                    seen[eid] = true
                end
            end
        end
        if type(userEvents) == "table" then
            for rawEventID in pairs(userEvents) do
                local eid = tonumber(rawEventID)
                if eid and GetEventScene(eid) == scene then
                    seen[eid] = true
                end
            end
        end
        for eid in pairs(seen) do
            if GetEventScene(eid) == scene then
                local resolved = BuildResolvedForSlot(eid, slotKey)
                if type(resolved) == "table" then
                    root[eid] = DeepCopy(resolved)
                end
            end
        end
    end
    return root
end

function BossConfig:Ensure()
    EnsureDB()
    MigrateLegacyOnce()
    return EXBossDataDB.bossConfig
end

function BossConfig:ResolveLinkedTextFields(row)
    return ResolveLinkedTextFields(row)
end

function BossConfig:GetSlotKeys(scene)
    local out = {}
    local sceneKey = scene and NormalizeSceneKey(scene) or nil
    for _, slotKey in ipairs(SLOT_ORDER) do
        if not sceneKey or SLOT_META[slotKey].scene == sceneKey then
            out[#out + 1] = slotKey
        end
    end
    return out
end

function BossConfig:GetSlotLabel(slotKey)
    local meta = SLOT_META[NormalizeSlotKey(slotKey) or ""]
    return meta and meta.label or tostring(slotKey or "")
end

function BossConfig:GetSlotItems(scene)
    local out = {}
    for _, slotKey in ipairs(self:GetSlotKeys(scene)) do
        out[#out + 1] = { self:GetSlotLabel(slotKey), slotKey }
    end
    return out
end

function BossConfig:GetAuthorItems(slotKey)
    local db = self:Ensure()
    local normalized = NormalizeSlotKey(slotKey)
    local slot = GetPresetRoot().slots[normalized] or {}
    local seen = {}
    local items = {}
    for key, preset in pairs(slot) do
        if not HIDDEN_AUTHOR_KEYS[tostring(key or "")] then
            seen[key] = true
            local displayName = tostring((type(preset) == "table" and (preset.name or preset.author)) or key)
            local L = ExBoss and ExBoss.L
            if L then displayName = L[displayName] or displayName end
            items[#items + 1] = { displayName, key }
        end
    end
    local userSlot = type(db.userOverrides) == "table" and db.userOverrides[normalized] or nil
    if type(userSlot) == "table" then
        for key, authorRow in pairs(userSlot) do
            local skey = tostring(key or "")
            if skey ~= "" and not seen[skey] and not HIDDEN_AUTHOR_KEYS[skey] then
                local hasEvents = type(authorRow) == "table" and type(authorRow.events) == "table" and next(authorRow.events) ~= nil
                local hasPrivateAura = NormalizePrivateAuraRoot(type(authorRow) == "table" and authorRow.privateAura or nil) ~= nil
                if hasEvents or hasPrivateAura then
                    seen[skey] = true
                    items[#items + 1] = { skey, skey }
                end
            end
        end
    end
    local selected = db.slotSelection[normalized]
    if selected and not seen[selected] and not HIDDEN_AUTHOR_KEYS[tostring(selected or "")] then
        items[#items + 1] = { tostring(selected), selected }
    end
    table.sort(items, function(a, b)
        return tostring(a[1]) < tostring(b[1])
    end)
    return items
end

function BossConfig:GetSelectedAuthor(slotKey)
    local db = self:Ensure()
    slotKey = NormalizeSlotKey(slotKey)
    return slotKey and (db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey)) or nil
end

function BossConfig:SetSelectedAuthor(slotKey, authorKey)
    local db = self:Ensure()
    slotKey = NormalizeSlotKey(slotKey)
    if not slotKey then
        return false, "invalid slot"
    end
    authorKey = tostring(authorKey or "")
    if authorKey == "" then
        return false, "invalid author"
    end
    db.slotSelection[slotKey] = authorKey
    EnsureAuthorOverrideRoot(slotKey, authorKey)
    self:PublishRuntimeSelection()
    do
        ExBossDB = ExBossDB or {}
        ExBossDB.ui = ExBossDB.ui or {}
        ExBossDB.ui.general = ExBossDB.ui.general or {}
        local g = ExBossDB.ui.general
        local meta = SLOT_META[slotKey]
        if meta and meta.role == "dps" and g.hideTankBossAlertsForDps == true and type(ExBoss.ApplyTankBossSkillToggleForRole) == "function" then
            ExBoss.ApplyTankBossSkillToggleForRole("dps", true)
        elseif meta and meta.role == "heal" and g.hideTankBossAlertsForHeal == true and type(ExBoss.ApplyTankBossSkillToggleForRole) == "function" then
            ExBoss.ApplyTankBossSkillToggleForRole("heal", true)
        end
    end
    return true
end

function BossConfig:GetOverrideRootForEvent(eventID, createIfMissing)
    local slotKey = ResolveSlotKeyForEvent(eventID)
    local authorKey = self:GetSelectedAuthor(slotKey)
    if createIfMissing == true then
        return EnsureAuthorOverrideRoot(slotKey, authorKey), slotKey, authorKey
    end
    return GetAuthorOverrideRoot(slotKey, authorKey), slotKey, authorKey
end

function BossConfig:GetOverrideRootForSlot(slotKey, createIfMissing)
    self:Ensure()
    slotKey = NormalizeSlotKey(slotKey)
    if not slotKey then
        return nil, nil, nil
    end
    local authorKey = self:GetSelectedAuthor(slotKey)
    if createIfMissing == true then
        return EnsureAuthorOverrideRoot(slotKey, authorKey), slotKey, authorKey
    end
    return GetAuthorOverrideRoot(slotKey, authorKey), slotKey, authorKey
end

function BossConfig:GetPrivateAuraOverrideRootForSlot(slotKey, createIfMissing)
    self:Ensure()
    slotKey = NormalizeSlotKey(slotKey)
    if not slotKey then
        return nil, nil, nil
    end
    local authorKey = self:GetSelectedAuthor(slotKey)
    if createIfMissing == true then
        return EnsureAuthorPrivateAuraRoot(slotKey, authorKey), slotKey, authorKey
    end
    return GetAuthorPrivateAuraRoot(slotKey, authorKey), slotKey, authorKey
end

function BossConfig:GetPrivateAuraSlotForKey(privateAuraKey)
    local sceneKey = GetPrivateAuraSceneKey(privateAuraKey)
    if not sceneKey then
        return nil
    end
    return self:GetRuntimeSlotForScene(sceneKey)
end

function BossConfig:GetResolvedPrivateAuraEntry(privateAuraKey, slotKey)
    self:Ensure()
    local key = NormalizePrivateAuraKey(privateAuraKey)
    if not key then
        return nil
    end
    slotKey = NormalizeSlotKey(slotKey) or self:GetPrivateAuraSlotForKey(key)
    if not slotKey then
        return nil
    end
    local root = self:GetResolvedPrivateAuraConfig(slotKey)
    local entries = type(root) == "table" and type(root.entries) == "table" and root.entries or nil
    local row = entries and entries[key] or nil
    return type(row) == "table" and NormalizePrivateAuraEntryRow(DeepCopy(row)) or nil
end

function BossConfig:GetResolvedPrivateAuraConfig(slotKey)
    self:Ensure()
    slotKey = NormalizeSlotKey(slotKey)
    if not slotKey then
        return nil
    end
    local authorKey = self:GetSelectedAuthor(slotKey)
    return BuildResolvedPrivateAuraForSlotAuthor(slotKey, authorKey)
end

function BossConfig:GetResolvedEventConfig(eventID, slotKey)
    self:Ensure()
    return BuildResolvedForSlot(eventID, slotKey)
end

function BossConfig:CompactEventOverride(eventID, slotKey)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local resolvedSlotKey = ResolveSlotKeyForEvent(eid, slotKey)
    local root, _, authorKey
    if slotKey ~= nil then
        root, _, authorKey = self:GetOverrideRootForSlot(resolvedSlotKey, true)
    else
        root, resolvedSlotKey, authorKey = self:GetOverrideRootForEvent(eid, true)
    end
    if type(root) ~= "table" then
        return nil
    end
    local row = root[eid]
    if type(row) ~= "table" then
        root[eid] = nil
        return nil
    end
    StripLegacyRoleFields(row)
    local compacted = CompactOverrideForSlotAuthor(eid, row, resolvedSlotKey or slotKey, authorKey)
    if type(compacted) == "table" then
        StripLegacyRoleFields(compacted)
        root[eid] = compacted
    else
        root[eid] = nil
    end
    return root[eid]
end

function BossConfig:GetRuntimeSlotForScene(scene)
    local role = GetCurrentRoleKey()
    return NormalizeSlotKey(string.format("%s_%s", NormalizeSceneKey(scene), role))
end

function BossConfig:IsSceneEnabled(scene)
    local g = EnsureBossSceneOptions()
    local sceneKey = NormalizeSceneKey(scene)
    if sceneKey == "raid" then
        return g.bossAlertsEnabledRaid ~= false
    end
    return g.bossAlertsEnabledMplus ~= false
end

function BossConfig:IsCurrentSceneEnabled()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then
        return self:IsSceneEnabled("raid"), "raid"
    end
    if instanceType == "party" then
        return self:IsSceneEnabled("mplus"), "mplus"
    end
    return true, nil
end

function BossConfig:PublishRuntimeSelection(roleKey)
    self:Ensure()
    EXBossDataDB = EXBossDataDB or {}
    EXBossDataDB.events = EXBossDataDB.events or {}
    local legacyRoot = EXBossDataDB.events
    WipeTable(legacyRoot)
    local published = BuildPublishedRootForRole(roleKey or GetCurrentRoleKey())
    for eventID, row in pairs(published) do
        legacyRoot[eventID] = row
    end
    TouchLegacyRoot()
    do
        local privateAura = ExBoss and ExBoss.PrivateAura
        if privateAura and type(privateAura.RefreshActiveRegistrations) == "function" then
            privateAura:RefreshActiveRegistrations()
        end
    end
    do
        local targetAlert = ExBoss and ExBoss.TargetAlert
        if targetAlert and type(targetAlert.RefreshActiveRegistrations) == "function" then
            targetAlert:RefreshActiveRegistrations()
        end
    end
    if ExwindTools and type(ExwindTools.UpdateState) == "function" then
        ExwindTools:UpdateState("ExBoss.PrivateAuraOptions.DatabaseChanged", { key = "slotSelection" })
    end
    return true
end

function BossConfig:ApplyPersistedChange(eventID)
    self:PublishRuntimeSelection()
    local encounterID = tonumber(eventID) and nil
    if eventID ~= nil and ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
    if eventID ~= nil and ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
        and type(ExBoss.Timeline.Scheduler.RefreshActiveEventConfig) == "function" then
        pcall(ExBoss.Timeline.Scheduler.RefreshActiveEventConfig, ExBoss.Timeline.Scheduler, eventID)
    end
    return encounterID
end

function BossConfig:ExportScene(scene, includeSlots)
    local sceneKey = NormalizeSceneKey(scene)
    local db = self:Ensure()
    local out = {
        selections = {},
        slots = {},
    }
    local include = type(includeSlots) == "table" and includeSlots or nil
    for _, slotKey in ipairs(self:GetSlotKeys(sceneKey)) do
        if not include or include[slotKey] == true then
            local authorKey = db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey)
            local events = {}
            local seen = {}
            local defaultsRoot = GetFactoryDefaultsRoot()
            local presetEvents = GetPresetEvents(slotKey, authorKey)
            local userEvents = GetAuthorOverrideRoot(slotKey, authorKey)
            for rawEventID in pairs(defaultsRoot) do
                local eid = tonumber(rawEventID)
                if eid and GetEventScene(eid) == sceneKey then
                    seen[eid] = true
                end
            end
            if type(presetEvents) == "table" then
                for rawEventID in pairs(presetEvents) do
                    local eid = tonumber(rawEventID)
                    if eid and GetEventScene(eid) == sceneKey then
                        seen[eid] = true
                    end
                end
            end
            if type(userEvents) == "table" then
                for rawEventID in pairs(userEvents) do
                    local eid = tonumber(rawEventID)
                    if eid and GetEventScene(eid) == sceneKey then
                        seen[eid] = true
                    end
                end
            end
            for eid in pairs(seen) do
                local resolved = NormalizeExportEventRow(BuildResolvedForSlot(eid, slotKey))
                local defaults = GetFactoryEvent(eid)
                local delta = BuildOverrideDelta(resolved, defaults or {})
                if delta ~= nil then
                    events[eid] = delta
                end
            end
            out.selections[slotKey] = authorKey
            out.slots[slotKey] = {
                author = authorKey,
                events = events,
                privateAura = BuildResolvedPrivateAuraForSlotAuthor(slotKey, authorKey),
            }
        end
    end
    return out
end

function BossConfig:ImportScene(scene, sceneData, options)
    if type(sceneData) ~= "table" then
        return false, "invalid scene data"
    end
    options = type(options) == "table" and options or {}
    local sceneKey = NormalizeSceneKey(scene)
    local db = self:Ensure()
    local selections = type(sceneData.selections) == "table" and sceneData.selections or {}
    local slots = type(sceneData.slots) == "table" and sceneData.slots or {}
    local importedAuthorKey = TrimString(options.authorKey or options.authorName or "")
    local targetSlots = {}
    local sceneSlots = self:GetSlotKeys(sceneKey)
    for _, slotKey in ipairs(self:GetSlotKeys(sceneKey)) do
        if selections[slotKey] ~= nil or slots[slotKey] ~= nil then
            targetSlots[#targetSlots + 1] = slotKey
        end
    end
    if #targetSlots == 0 then
        return false, "no slot data"
    end
    local importedProfiles = {}
    for _, slotKey in ipairs(targetSlots) do
        local sourceAuthorKey = importedAuthorKey ~= "" and importedAuthorKey
            or tostring(selections[slotKey] or (type(slots[slotKey]) == "table" and slots[slotKey].author) or db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey) or "")
        local authorKey = BuildImportedAuthorKey(sourceAuthorKey, slotKey)
        if authorKey == "" then
            authorKey = TrimString(sourceAuthorKey)
        end
        importedProfiles[#importedProfiles + 1] = {
            sourceSlotKey = slotKey,
            authorKey = authorKey,
            sourceEvents = type(slots[slotKey]) == "table" and type(slots[slotKey].events) == "table" and slots[slotKey].events or {},
            sourcePrivateAura = type(slots[slotKey]) == "table" and NormalizePrivateAuraRoot(slots[slotKey].privateAura) or nil,
        }
    end
    for _, profile in ipairs(importedProfiles) do
        for _, slotKey in ipairs(sceneSlots) do
            local authorRoot = EnsureAuthorSlotRoot(slotKey, profile.authorKey)
            local root = authorRoot.events
            WipeTable(root)
            for eventID, row in pairs(profile.sourceEvents) do
                local eid = tonumber(eventID)
                if eid and GetEventScene(eid) == sceneKey then
                    local compacted = CompactOverrideForSlotAuthor(eid, row, slotKey, profile.authorKey)
                    if type(compacted) == "table" then
                        root[eid] = compacted
                    end
                end
            end
            authorRoot.privateAura = NormalizePrivateAuraRoot(profile.sourcePrivateAura)
        end
    end
    for _, profile in ipairs(importedProfiles) do
        db.slotSelection[profile.sourceSlotKey] = profile.authorKey
    end
    self:PublishRuntimeSelection()
    return true
end

function BossConfig:GetSelectionSummary()
    local db = self:Ensure()
    local out = {}
    for _, slotKey in ipairs(SLOT_ORDER) do
        out[#out + 1] = {
            slotKey = slotKey,
            label = self:GetSlotLabel(slotKey),
            author = db.slotSelection[slotKey] or GetDefaultAuthorKey(slotKey),
        }
    end
    return out
end

function BossConfig:GetManagedAuthorProfiles()
    local db = self:Ensure()
    local profiles = {}
    local byKey = {}

    for _, slotKey in ipairs(SLOT_ORDER) do
        local slotRoot = type(db.userOverrides) == "table" and db.userOverrides[slotKey] or nil
        if type(slotRoot) == "table" then
            for authorKey, authorRow in pairs(slotRoot) do
                local key = tostring(authorKey or "")
                if key ~= "" and not HIDDEN_AUTHOR_KEYS[key] and not HasPresetAuthorForSlot(slotKey, key) then
                    local hasEvents = type(authorRow) == "table"
                        and type(authorRow.events) == "table"
                        and next(authorRow.events) ~= nil
                    if hasEvents then
                        local row = byKey[key]
                        if not row then
                            row = {
                                authorKey = key,
                                displayName = key,
                                slots = {},
                                selectedSlots = {},
                            }
                            byKey[key] = row
                            profiles[#profiles + 1] = row
                        end
                        row.slots[#row.slots + 1] = slotKey
                        if db.slotSelection and db.slotSelection[slotKey] == key then
                            row.selectedSlots[#row.selectedSlots + 1] = slotKey
                        end
                    end
                end
            end
        end
    end

    table.sort(profiles, function(a, b)
        return tostring(a.displayName or a.authorKey or "") < tostring(b.displayName or b.authorKey or "")
    end)

    return profiles
end

function BossConfig:RenameManagedAuthorProfile(oldAuthorKey, newAuthorKey)
    local db = self:Ensure()
    local oldKey = tostring(oldAuthorKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local newKey = tostring(newAuthorKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if oldKey == "" or newKey == "" then
        return false, "invalid author key"
    end
    if oldKey == newKey then
        return true
    end
    if HIDDEN_AUTHOR_KEYS[oldKey] or HIDDEN_AUTHOR_KEYS[newKey] then
        return false, "reserved author key"
    end

    local found = false
    db.userOverrides = type(db.userOverrides) == "table" and db.userOverrides or {}
    db.slotSelection = type(db.slotSelection) == "table" and db.slotSelection or {}

    for _, slotKey in ipairs(SLOT_ORDER) do
        if HasPresetAuthorForSlot(slotKey, oldKey) or HasPresetAuthorForSlot(slotKey, newKey) then
            return false, "preset author cannot be renamed"
        end
        local slotRoot = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or nil
        if slotRoot and slotRoot[oldKey] ~= nil then
            found = true
            local existing = slotRoot[newKey]
            local oldRow = slotRoot[oldKey]
            if type(existing) ~= "table" then
                slotRoot[newKey] = oldRow
            else
                existing.events = type(existing.events) == "table" and existing.events or {}
                local oldEvents = type(oldRow) == "table" and type(oldRow.events) == "table" and oldRow.events or nil
                if oldEvents then
                    for eventID, row in pairs(oldEvents) do
                        existing.events[eventID] = row
                    end
                end
            end
            slotRoot[oldKey] = nil
        end
        if db.slotSelection[slotKey] == oldKey then
            db.slotSelection[slotKey] = newKey
        end
    end

    if not found then
        return false, "author not found"
    end

    self:PublishRuntimeSelection()
    return true
end

function BossConfig:DeleteManagedAuthorProfile(authorKey)
    local db = self:Ensure()
    local key = tostring(authorKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        return false, "invalid author key"
    end
    if HIDDEN_AUTHOR_KEYS[key] then
        return false, "reserved author key"
    end

    local removed = false
    db.userOverrides = type(db.userOverrides) == "table" and db.userOverrides or {}
    db.slotSelection = type(db.slotSelection) == "table" and db.slotSelection or {}

    for _, slotKey in ipairs(SLOT_ORDER) do
        if HasPresetAuthorForSlot(slotKey, key) then
            return false, "preset author cannot be deleted"
        end
        local slotRoot = type(db.userOverrides[slotKey]) == "table" and db.userOverrides[slotKey] or nil
        if slotRoot and slotRoot[key] ~= nil then
            slotRoot[key] = nil
            removed = true
        end
        if db.slotSelection[slotKey] == key then
            db.slotSelection[slotKey] = GetDefaultAuthorKey(slotKey)
        end
    end

    if not removed then
        return false, "author not found"
    end

    self:PublishRuntimeSelection()
    return true
end

if ExwindTools and ExwindTools.WatchState then
    ExwindTools:WatchState("RoleKey", "ExBoss.BossConfig.RolePublish", function()
        BossConfig:PublishRuntimeSelection()
    end)
end

if ExwindTools and ExwindTools.RegisterEvent then
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss.BossConfig.Publish", function()
        BossConfig:PublishRuntimeSelection()
    end)
    ExwindTools:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ExBoss.BossConfig.PublishZone", function()
        BossConfig:PublishRuntimeSelection()
    end)
    ExwindTools:RegisterEvent("ADDON_LOADED", "ExBoss.BossConfig.Init", function(_, addonName)
        if tostring(addonName or ""):lower() ~= "exboss" then
            return
        end
        BossConfig:Ensure()
        BossConfig:PublishRuntimeSelection()
    end)
end
