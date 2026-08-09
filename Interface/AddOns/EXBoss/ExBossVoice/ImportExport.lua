---@diagnostic disable: undefined-global

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.ImportExport = ExBoss.Voice.ImportExport or {}
local IE = ExBoss.Voice.ImportExport

local PREFIX          = "EXBXC:"
local RAW_SENTINEL    = "RAW:"
local PAYLOAD_TYPE    = "exboss_bundle"
local PAYLOAD_VERSION = 5
local PRESET_PACK_SLOT_ORDER = {
    "raid_tank",
    "raid_dps",
    "raid_heal",
    "mplus_tank",
    "mplus_dps",
    "mplus_heal",
}

local STYLE_MODULE_KEYS = {
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashText",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
}

local STATIC_SETTINGS_EXTRA_MODULE_KEYS = {
    "ExBoss.BossSpellOptions",
    "ExBoss.MDT.Settings",
}

local STATIC_PLUGIN_SETTINGS_EXTRA_MODULE_KEYS = {
    "ExBoss.MDT.Settings",
}

-- ─── 工具 ─────────────────────────────────────────────────────

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

local function Trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function CountEntries(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function AppendUniqueKey(out, seen, key)
    if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        out[#out + 1] = key
    end
end

local function AppendKeyList(out, seen, keys)
    if type(keys) ~= "table" then
        return
    end
    for _, key in ipairs(keys) do
        AppendUniqueKey(out, seen, key)
    end
end

local function CollectPageExportModuleKeys(page)
    if type(page) ~= "table" or type(page.GetExportModuleKeys) ~= "function" then
        return nil
    end
    local ok, keys = pcall(page.GetExportModuleKeys, page)
    if ok and type(keys) == "table" then
        return keys
    end
    return nil
end

local function GetPageDrivenSettingsModuleKeys()
    local out = {}
    local seen = {}
    local panel = ExBoss and ExBoss.UI and ExBoss.UI.Panel
    if not panel then
        return out
    end
    AppendKeyList(out, seen, CollectPageExportModuleKeys(panel.GlobalSettingsPage))
    AppendKeyList(out, seen, CollectPageExportModuleKeys(panel.ToolsPage))
    return out
end

local function GetSettingsModuleKeys()
    local out = {}
    local seen = {}
    AppendKeyList(out, seen, GetPageDrivenSettingsModuleKeys())
    AppendKeyList(out, seen, STATIC_SETTINGS_EXTRA_MODULE_KEYS)
    return out
end

local function GetPluginSettingsModuleKeys()
    local out = {}
    local seen = {}
    AppendKeyList(out, seen, GetPageDrivenSettingsModuleKeys())
    AppendKeyList(out, seen, STATIC_PLUGIN_SETTINGS_EXTRA_MODULE_KEYS)
    return out
end

local function ReadCVarValue(name)
    local key = tostring(name or "")
    if key == "" then
        return nil
    end
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, key)
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, key)
    end
    if not ok or value == nil then
        return nil
    end
    local s = tostring(value)
    return s ~= "" and s or nil
end

local function WriteCVarValue(name, value)
    local key = tostring(name or "")
    local s = tostring(value or "")
    if key == "" or s == "" then
        return false
    end
    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, key, s)
        if ok then
            return true
        end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, key, s)
        if ok then
            return true
        end
    end
    return false
end

local function CopyModuleDB(keys)
    local out = {}
    if type(keys) ~= "table" or type(ExwindToolsDB) ~= "table" or type(ExwindToolsDB.ModuleDB) ~= "table" then
        return out
    end
    for _, key in ipairs(keys) do
        if ExwindToolsDB.ModuleDB[key] ~= nil then
            out[key] = DeepCopy(ExwindToolsDB.ModuleDB[key])
        end
    end
    return out
end

local function ApplyModuleDBSnapshot(snapshot, clearKeys)
    ExwindToolsDB = ExwindToolsDB or {}
    ExwindToolsDB.ModuleDB = ExwindToolsDB.ModuleDB or {}
    local allowSet = nil
    if type(clearKeys) == "table" then
        allowSet = {}
        for _, key in ipairs(clearKeys) do
            allowSet[key] = true
            ExwindToolsDB.ModuleDB[key] = nil
        end
    end
    if type(snapshot) == "table" then
        for key, value in pairs(snapshot) do
            if clearKeys == STYLE_MODULE_KEYS or (allowSet and allowSet[key]) then
                ExwindToolsDB.ModuleDB[key] = DeepCopy(value)
            end
        end
    end
end

local function SyncGeneralCVarsIntoDB(general)
    if type(general) ~= "table" then
        return general
    end
    local warnings = ReadCVarValue("encounterWarningsEnabled")
    if warnings ~= nil then
        general.encounterWarningsEnabled = warnings ~= "0"
    end
    local timeline = ReadCVarValue("encounterTimelineEnabled")
    if timeline ~= nil then
        general.disableBlizzardEncounterTimeline = timeline == "0"
    end
    return general
end

local function ApplyGeneralCVarsFromDB(general)
    if type(general) ~= "table" then
        return
    end
    if general.encounterWarningsEnabled ~= nil then
        WriteCVarValue("encounterWarningsEnabled", general.encounterWarningsEnabled ~= false and "1" or "0")
    end
    if general.disableBlizzardEncounterTimeline ~= nil then
        WriteCVarValue("encounterTimelineEnabled", general.disableBlizzardEncounterTimeline == true and "0" or "1")
    end
end

-- ─── 序列化（无 LibSerialize 时的 fallback） ──────────────────

local function Serialize(v)
    local tv = type(v)
    if tv == "nil"     then return "nil" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number"  then return tostring(v) end
    if tv == "string"  then return string.format("%q", v) end
    if tv == "table" then
        local parts = {}
        local i = 1
        while rawget(v, i) ~= nil do
            parts[#parts + 1] = Serialize(v[i])
            i = i + 1
        end
        for k, x in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k < i and math.floor(k) == k) then
                local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k
                            or ("[" .. Serialize(k) .. "]")
                parts[#parts + 1] = key .. "=" .. Serialize(x)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local function CompareStableKeys(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb then
        if ta == "number" then
            return a < b
        end
        if ta == "string" then
            return a < b
        end
    end
    if ta == "number" then
        return true
    end
    if tb == "number" then
        return false
    end
    if ta == "string" then
        return true
    end
    if tb == "string" then
        return false
    end
    return tostring(a) < tostring(b)
end

local function BuildStableKeyList(t)
    local keys = {}
    for key in pairs(t) do
        keys[#keys + 1] = key
    end
    table.sort(keys, CompareStableKeys)
    return keys
end

local function FormatStableKey(key)
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        return key
    end
    return "[" .. Serialize(key) .. "]"
end

local function SplitLines(text)
    local lines = {}
    text = tostring(text or "")
    if text == "" then
        return { "" }
    end
    for line in text:gmatch("([^\n]*)\n?") do
        if line == "" and #lines > 0 and text:sub(-1) ~= "\n" then
            break
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        lines[1] = ""
    end
    return lines
end

local function SerializeStable(v, indentLevel)
    if type(v) ~= "table" then
        return Serialize(v)
    end

    indentLevel = tonumber(indentLevel) or 0
    local keys = BuildStableKeyList(v)
    if #keys == 0 then
        return "{}"
    end

    local baseIndent = string.rep("    ", indentLevel)
    local childIndent = string.rep("    ", indentLevel + 1)
    local lines = { "{" }

    for _, key in ipairs(keys) do
        local value = v[key]
        local valueText = SerializeStable(value, indentLevel + 1)
        local valueLines = SplitLines(valueText)
        lines[#lines + 1] = childIndent .. FormatStableKey(key) .. " = " .. valueLines[1]
        for i = 2, #valueLines do
            lines[#lines + 1] = valueLines[i]
        end
        lines[#lines] = lines[#lines] .. ","
    end

    lines[#lines + 1] = baseIndent .. "}"
    return table.concat(lines, "\n")
end

local function Deserialize(s)
    if type(s) ~= "string" or s == "" then return nil, "empty" end
    local loader = loadstring("return " .. s)
    if not loader then return nil, "invalid lua" end
    local ok, data = pcall(loader)
    if not ok then return nil, tostring(data) end
    if type(data) ~= "table" then return nil, "not a table" end
    return data
end

-- ─── 编码/解码 ────────────────────────────────────────────────

local function GetLibs()
    local ls = LibStub and LibStub("LibSerialize", true)
    local ld = LibStub and LibStub("LibDeflate", true)
    return ls, ld
end

local function EncodePayload(payload)
    local ls, ld = GetLibs()
    if ls and ld then
        local ok, serialized = pcall(function() return ls:Serialize(payload) end)
        if ok and serialized then
            local compressed = ld:CompressDeflate(serialized)
            local encoded = compressed and ld:EncodeForPrint(compressed)
            if encoded then return PREFIX .. encoded, nil end
        end
    end
    return PREFIX .. RAW_SENTINEL .. Serialize(payload), nil
end

local function DecodePayload(rawText)
    local str = Trim(rawText)
    if str == "" then return nil, "empty string" end
    if str:sub(1, #PREFIX) ~= PREFIX then
        return nil, "unsupported prefix (expected EXBXC:)"
    end
    local body = str:sub(#PREFIX + 1)
    if body:sub(1, #RAW_SENTINEL) == RAW_SENTINEL then
        return Deserialize(body:sub(#RAW_SENTINEL + 1))
    end
    local ls, ld = GetLibs()
    if not ls or not ld then return nil, "missing LibSerialize/LibDeflate" end
    local decoded = ld:DecodeForPrint(body)
    if not decoded then return nil, "decode failed" end
    local decompressed = ld:DecompressDeflate(decoded)
    if not decompressed then return nil, "decompress failed" end
    local ok, payload = ls:Deserialize(decompressed)
    if not ok or type(payload) ~= "table" then return nil, "deserialize failed" end
    return payload
end

-- ─── 设置页配置数据（payload 字段名沿用 appearance 以兼容旧字符串） ───

local GetTrashStore

local function CaptureAppearance()
    local out = {
        timer = {},
        moduleDB = {},
        voiceGlobal = nil,
        colorSchemes = nil,
        customColors = nil,
        extraCustomColors = nil,
        settingsPage = {
            ui = {},
            voice = {},
            timer = {},
            conditions = nil,
            trashCD = nil,
            bossModules = nil,
            locale = nil,
            mdt = nil,
            moduleDB = {},
        },
    }
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    local timer = ExBossDB.timer
    if timer.timerBar    ~= nil then out.timer.timerBar    = DeepCopy(timer.timerBar)    end
    if timer.bunBar      ~= nil then out.timer.bunBar      = DeepCopy(timer.bunBar)      end
    if timer.countdown   ~= nil then out.timer.countdown   = DeepCopy(timer.countdown)   end
    if timer.flashText   ~= nil then out.timer.flashText   = DeepCopy(timer.flashText)   end
    if timer.flashTextMedium ~= nil then out.timer.flashTextMedium = DeepCopy(timer.flashTextMedium) end
    if timer.ringProgress ~= nil then out.timer.ringProgress = DeepCopy(timer.ringProgress) end
    if timer.iconAlert ~= nil then out.timer.iconAlert = DeepCopy(timer.iconAlert) end
    if timer.castProgressBar ~= nil then out.timer.castProgressBar = DeepCopy(timer.castProgressBar) end
    out.moduleDB = CopyModuleDB(STYLE_MODULE_KEYS)
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.global) == "table" then
        out.voiceGlobal = DeepCopy(ExBossDB.voice.global)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.colorSchemes) == "table" then
        out.colorSchemes = DeepCopy(ExBossDB.voice.colorSchemes)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.customColors) == "table" then
        out.customColors = DeepCopy(ExBossDB.voice.customColors)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.extraCustomColors) == "table" then
        out.extraCustomColors = DeepCopy(ExBossDB.voice.extraCustomColors)
    end
    if type(ExBossDB.ui) == "table" then
        if type(ExBossDB.ui.general) == "table" then
            out.settingsPage.ui.general = SyncGeneralCVarsIntoDB(DeepCopy(ExBossDB.ui.general))
        end
        if type(ExBossDB.ui.partyFrameGlow) == "table" then
            out.settingsPage.ui.partyFrameGlow = DeepCopy(ExBossDB.ui.partyFrameGlow)
        end
    end
    out.settingsPage.timer = DeepCopy(out.timer)
    if type(ExBossDB.voice) == "table" then
        out.settingsPage.voice.global = DeepCopy(ExBossDB.voice.global)
        out.settingsPage.voice.colorSchemes = DeepCopy(ExBossDB.voice.colorSchemes)
        out.settingsPage.voice.customColors = DeepCopy(ExBossDB.voice.customColors)
        out.settingsPage.voice.extraCustomColors = DeepCopy(ExBossDB.voice.extraCustomColors)
    end
    if type(ExBossDB.conditions) == "table" then
        out.settingsPage.conditions = DeepCopy(ExBossDB.conditions)
    end
    local trashStore = GetTrashStore()
    if trashStore and type(trashStore.ExportFullConfig) == "function" then
        out.settingsPage.trashCD = trashStore.ExportFullConfig()
    elseif type(ExBossDB.trashCD) == "table" then
        out.settingsPage.trashCD = DeepCopy(ExBossDB.trashCD)
    end
    if type(ExBossDB.bossModules) == "table" then
        out.settingsPage.bossModules = DeepCopy(ExBossDB.bossModules)
    end
    if type(ExBossDB.locale) == "table" then
        out.settingsPage.locale = DeepCopy(ExBossDB.locale)
    end
    if type(ExBossDB.mdt) == "table" then
        out.settingsPage.mdt = DeepCopy(ExBossDB.mdt)
    end
    out.settingsPage.moduleDB = CopyModuleDB(GetSettingsModuleKeys())
    return out
end

local function CapturePluginSettingsPageAppearance()
    local out = {
        timer = {},
        moduleDB = {},
        voiceGlobal = nil,
        colorSchemes = nil,
        customColors = nil,
        extraCustomColors = nil,
        settingsPage = {
            ui = {},
            voice = {},
            timer = {},
            conditions = nil,
            locale = nil,
            mdt = nil,
            moduleDB = {},
        },
    }

    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    local timer = ExBossDB.timer
    if timer.timerBar ~= nil then out.timer.timerBar = DeepCopy(timer.timerBar) end
    if timer.bunBar ~= nil then out.timer.bunBar = DeepCopy(timer.bunBar) end
    if timer.countdown ~= nil then out.timer.countdown = DeepCopy(timer.countdown) end
    if timer.flashText ~= nil then out.timer.flashText = DeepCopy(timer.flashText) end
    if timer.flashTextMedium ~= nil then out.timer.flashTextMedium = DeepCopy(timer.flashTextMedium) end
    if timer.ringProgress ~= nil then out.timer.ringProgress = DeepCopy(timer.ringProgress) end
    if timer.iconAlert ~= nil then out.timer.iconAlert = DeepCopy(timer.iconAlert) end
    if timer.castProgressBar ~= nil then out.timer.castProgressBar = DeepCopy(timer.castProgressBar) end
    out.moduleDB = CopyModuleDB(STYLE_MODULE_KEYS)

    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.global) == "table" then
        out.voiceGlobal = DeepCopy(ExBossDB.voice.global)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.colorSchemes) == "table" then
        out.colorSchemes = DeepCopy(ExBossDB.voice.colorSchemes)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.customColors) == "table" then
        out.customColors = DeepCopy(ExBossDB.voice.customColors)
    end
    if type(ExBossDB.voice) == "table" and type(ExBossDB.voice.extraCustomColors) == "table" then
        out.extraCustomColors = DeepCopy(ExBossDB.voice.extraCustomColors)
    end
    if type(ExBossDB.ui) == "table" then
        if type(ExBossDB.ui.general) == "table" then
            out.settingsPage.ui.general = SyncGeneralCVarsIntoDB(DeepCopy(ExBossDB.ui.general))
        end
        if type(ExBossDB.ui.partyFrameGlow) == "table" then
            out.settingsPage.ui.partyFrameGlow = DeepCopy(ExBossDB.ui.partyFrameGlow)
        end
    end
    out.settingsPage.timer = DeepCopy(out.timer)
    if type(ExBossDB.voice) == "table" then
        out.settingsPage.voice.global = DeepCopy(ExBossDB.voice.global)
        out.settingsPage.voice.colorSchemes = DeepCopy(ExBossDB.voice.colorSchemes)
        out.settingsPage.voice.customColors = DeepCopy(ExBossDB.voice.customColors)
        out.settingsPage.voice.extraCustomColors = DeepCopy(ExBossDB.voice.extraCustomColors)
    end
    if type(ExBossDB.conditions) == "table" then
        out.settingsPage.conditions = DeepCopy(ExBossDB.conditions)
    end
    if type(ExBossDB.locale) == "table" then
        out.settingsPage.locale = DeepCopy(ExBossDB.locale)
    end
    if type(ExBossDB.mdt) == "table" then
        out.settingsPage.mdt = DeepCopy(ExBossDB.mdt)
    end
    out.settingsPage.moduleDB = CopyModuleDB(GetPluginSettingsModuleKeys())
    return out
end

local SLOT_SCENE = {
    raid_tank = "raid",
    raid_dps = "raid",
    raid_heal = "raid",
    mplus_tank = "mplus",
    mplus_dps = "mplus",
    mplus_heal = "mplus",
}

local SLOT_PRESET_DIR = {
    raid_tank = "RaidTank",
    raid_dps = "RaidDps",
    raid_heal = "RaidHealer",
    mplus_tank = "MplusTank",
    mplus_dps = "MplusDps",
    mplus_heal = "MplusHealer",
}

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

GetTrashStore = function()
    local store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store
    if type(store) == "table" then
        return store
    end
    return nil
end

local function ApplyAppearance(appearance)
    if type(appearance) ~= "table" then return false, "invalid settings config" end
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.voice = ExBossDB.voice or {}
    local settings = type(appearance.settingsPage) == "table" and appearance.settingsPage or nil
    local timer = settings and type(settings.timer) == "table" and settings.timer
        or type(appearance.timer) == "table" and appearance.timer
        or {}
    ExBossDB.timer.timerBar     = DeepCopy(timer.timerBar)
    ExBossDB.timer.bunBar       = DeepCopy(timer.bunBar)
    ExBossDB.timer.countdown    = DeepCopy(timer.countdown)
    ExBossDB.timer.flashText    = DeepCopy(timer.flashText)
    ExBossDB.timer.flashTextMedium = DeepCopy(timer.flashTextMedium)
    ExBossDB.timer.ringProgress = DeepCopy(timer.ringProgress)
    ExBossDB.timer.iconAlert = DeepCopy(timer.iconAlert)
    ExBossDB.timer.castProgressBar = DeepCopy(timer.castProgressBar)
    local voice = settings and type(settings.voice) == "table" and settings.voice or nil
    ExBossDB.voice.global       = DeepCopy((voice and voice.global) or appearance.voiceGlobal) or ExBossDB.voice.global or {}
    ExBossDB.voice.colorSchemes = DeepCopy((voice and voice.colorSchemes) or appearance.colorSchemes) or ExBossDB.voice.colorSchemes or {}
    ExBossDB.voice.customColors = DeepCopy((voice and voice.customColors) or appearance.customColors) or ExBossDB.voice.customColors or {}
    ExBossDB.voice.extraCustomColors = DeepCopy((voice and voice.extraCustomColors) or appearance.extraCustomColors) or ExBossDB.voice.extraCustomColors or {}
    if settings then
        if type(settings.ui) == "table" then
            ExBossDB.ui = ExBossDB.ui or {}
            if type(settings.ui.general) == "table" then
                ExBossDB.ui.general = DeepCopy(settings.ui.general)
                ApplyGeneralCVarsFromDB(ExBossDB.ui.general)
            end
            if type(settings.ui.partyFrameGlow) == "table" then
                ExBossDB.ui.partyFrameGlow = DeepCopy(settings.ui.partyFrameGlow)
            end
        end
        if type(settings.conditions) == "table" then
            ExBossDB.conditions = DeepCopy(settings.conditions)
        end
        if type(settings.trashCD) == "table" then
            local trashStore = GetTrashStore()
            if trashStore and type(trashStore.ImportFullConfig) == "function" then
                local ok, err = trashStore.ImportFullConfig(settings.trashCD)
                if not ok then
                    return false, err
                end
            else
                ExBossDB.trashCD = DeepCopy(settings.trashCD)
            end
        end
        if type(settings.bossModules) == "table" then
            ExBossDB.bossModules = DeepCopy(settings.bossModules)
        end
        if type(settings.locale) == "table" then
            ExBossDB.locale = DeepCopy(settings.locale)
            if ExBoss and type(ExBoss.SetLocaleMode) == "function" and ExBossDB.locale.mode ~= nil then
                ExBoss:SetLocaleMode(ExBossDB.locale.mode)
            end
        end
        if type(settings.mdt) == "table" then
            ExBossDB.mdt = DeepCopy(settings.mdt)
        end
        ApplyModuleDBSnapshot(settings.moduleDB, GetSettingsModuleKeys())
        local trashStore = GetTrashStore()
        if trashStore and type(trashStore.SyncSavedToModuleDB) == "function" then
            trashStore.SyncSavedToModuleDB()
        end
        if trashStore and type(trashStore.PublishConfigChanged) == "function" then
            trashStore.PublishConfigChanged("settings-import")
        end
    else
        ApplyModuleDBSnapshot(appearance.moduleDB, STYLE_MODULE_KEYS)
    end
    if ExBoss and ExBoss.UI then
        for _, name in ipairs({ "TimerBar", "BunBar", "Countdown", "FlashText", "FlashTextMedium", "RingProgress", "IconAlert", "CastProgressBar" }) do
            local m = ExBoss.UI[name]
            if m and m.RefreshVisuals then m:RefreshVisuals() end
        end
    end
    local conditionsStore = ExBoss and ExBoss.Conditions and ExBoss.Conditions.Store
    if settings and conditionsStore and type(conditionsStore.BumpRevision) == "function" then
        conditionsStore:BumpRevision()
    end
    if settings and ExwindTools and type(ExwindTools.UpdateState) == "function" then
        ExwindTools:UpdateState("ExBoss.PrivateAuraMonitor.DatabaseChanged", { key = "import" })
        ExwindTools:UpdateState("ExBoss.PrivateAuraOptions.DatabaseChanged", { key = "import" })
        ExwindTools:UpdateState("ExBoss.Boss.DogJumpTracker.SettingsChanged", GetTime and GetTime() or 0)
        ExwindTools:UpdateState("ExBoss.MDT.Settings.DatabaseChanged", { key = "import" })
    end
    local privateAura = ExBoss and ExBoss.PrivateAura
    if settings and privateAura and type(privateAura.RefreshActiveRegistrations) == "function" then
        privateAura:RefreshActiveRegistrations()
    end
    if settings and ExBoss and ExBoss.ApplyBossAutoCAASetting then
        ExBoss.ApplyBossAutoCAASetting()
    end
    if settings and ExBoss and type(ExBoss.ApplyTankBossSkillToggleForRole) == "function" then
        local general = ExBossDB.ui and ExBossDB.ui.general or nil
        if type(general) == "table" then
            ExBoss.ApplyTankBossSkillToggleForRole("dps", general.hideTankBossAlertsForDps == true)
            ExBoss.ApplyTankBossSkillToggleForRole("heal", general.hideTankBossAlertsForHeal == true)
        end
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if Engine and Engine.ApplyEventOverridesToAPI then
        Engine:ApplyEventOverridesToAPI()
    end
    local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
    if CS and type(CS.EnsureDB) == "function" then
        CS.EnsureDB()
    end
    return true
end

-- ─── 公开 API ─────────────────────────────────────────────────

function IE:GetPlayerIdentifier()
    local name  = UnitName   and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName()    or "Realm"
    return tostring(name) .. "-" .. tostring(realm)
end

-- 解码并校验版本，返回 payload 或 nil+err
function IE:DecodePayload(rawText)
    local payload, err = DecodePayload(rawText)
    if not payload then return nil, err end
    if type(payload.meta) ~= "table"
        or payload.meta.payloadType ~= PAYLOAD_TYPE
        or tonumber(payload.version) ~= PAYLOAD_VERSION then
        return nil, "unsupported payload (version=" .. tostring(payload.version)
                    .. ", expected=" .. PAYLOAD_VERSION .. ")"
    end
    return payload
end

-- 导出
-- options = {
--   includeAppearance = bool,
--   includeSlots      = { [slotKey] = true, ... },
--   configName        = string,
--   note              = string,
--   exporterName      = string,
-- }
local function BuildExportPayload(self, options)
    options = type(options) == "table" and options or {}
    local inclAppearance = (options.includeAppearance == true)
    local inclTrashCD = (options.includeTrashCD == true)
    local includeSlots = type(options.includeSlots) == "table" and options.includeSlots or {}
    local hasBossSlots = false
    for slotKey, enabled in pairs(includeSlots) do
        if enabled == true and SLOT_SCENE[slotKey] then
            hasBossSlots = true
            break
        end
    end
    if not inclAppearance and not hasBossSlots and not inclTrashCD then
        return nil, "nothing selected"
    end

    local payload = {
        version = PAYLOAD_VERSION,
        meta = {
            payloadType  = PAYLOAD_TYPE,
            configName   = options.configName  or "未命名配置",
            exporter     = options.exporterName or self:GetPlayerIdentifier(),
            note         = options.note        or "",
            exportedAt   = date and date("%Y-%m-%d %H:%M:%S") or "",
            addonVersion = ExBoss and ExBoss.VERSION or "unknown",
        },
    }

    if inclAppearance then
        payload.appearance = CaptureAppearance()
    end

    if inclTrashCD then
        local trashStore = GetTrashStore()
        if not (trashStore and type(trashStore.ExportFullConfig) == "function") then
            return nil, "trash cd config unavailable"
        end
        payload.trashCDConfig = trashStore:ExportFullConfig()
    end

    if hasBossSlots then
        local bossCfg = GetBossConfig()
        if not bossCfg then return nil, "boss config unavailable" end
        payload.bossConfig = {}
        local mplusSlots, raidSlots = {}, {}
        for slotKey, enabled in pairs(includeSlots) do
            if enabled == true then
                local scene = SLOT_SCENE[slotKey]
                if scene == "mplus" then
                    mplusSlots[slotKey] = true
                elseif scene == "raid" then
                    raidSlots[slotKey] = true
                end
            end
        end
        if next(mplusSlots) then
            payload.bossConfig.mplus = bossCfg:ExportScene("mplus", mplusSlots)
        end
        if next(raidSlots) then
            payload.bossConfig.raid = bossCfg:ExportScene("raid", raidSlots)
        end
    end

    return payload, nil
end

local function GetSingleSelectedSlot(includeSlots)
    local selected = nil
    local count = 0
    for _, slotKey in ipairs(PRESET_PACK_SLOT_ORDER) do
        if type(includeSlots) == "table" and includeSlots[slotKey] == true then
            selected = slotKey
            count = count + 1
        end
    end
    if count == 1 then
        return selected, nil
    end
    if count == 0 then
        return nil, "no slot selected"
    end
    return nil, "multiple slots selected"
end

local function BuildBuiltInAuthorSlotSnippet(slotKey, authorKey, authorName, slotRow)
    slotRow = type(slotRow) == "table" and slotRow or {}
    local eventText = SerializeStable(type(slotRow.events) == "table" and slotRow.events or {}, 1)
    local eventLines = SplitLines(eventText)
    local privateAuraLines = nil
    if type(slotRow.privateAura) == "table" then
        privateAuraLines = SplitLines(SerializeStable(slotRow.privateAura, 1))
    end
    local lines = {
        "_G.EXBossData.RegisterBossPreset(" .. string.format("%q", tostring(slotKey or "")) .. ", {",
        "    key = " .. string.format("%q", tostring(authorKey or "")) .. ",",
        "    name = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    author = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    builtIn = true,",
        "    events = " .. eventLines[1],
    }
    for i = 2, #eventLines do
        lines[#lines + 1] = eventLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    if privateAuraLines then
        lines[#lines + 1] = "    privateAura = " .. privateAuraLines[1]
        for i = 2, #privateAuraLines do
            lines[#lines + 1] = privateAuraLines[i]
        end
        lines[#lines] = lines[#lines] .. ","
    end
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:Export(options)
    local payload, err = BuildExportPayload(self, options)
    if not payload then
        return nil, err
    end
    return EncodePayload(payload)
end

local function ResolveBuiltInAuthorIdentity(options)
    options = type(options) == "table" and options or {}
    local authorKey = Trim(options.builtInAuthorKey or options.authorKey or "")
    if authorKey == "" then
        authorKey = "RURU"
    end
    local authorName = Trim(options.builtInAuthorName or options.authorName or authorKey)
    if authorName == "" then
        authorName = authorKey
    end
    return authorKey, authorName
end

function IE:ExportBuiltInAuthorSlotSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance == true or options.includeTrashCD == true then
        return nil, "built-in author lua export only supports boss slot data"
    end

    local slotKey, slotErr = GetSingleSelectedSlot(options.includeSlots)
    if not slotKey then
        if slotErr == "no slot selected" then
            return nil, "please select one boss slot"
        end
        return nil, "built-in author lua export requires exactly one slot"
    end

    local scene = SLOT_SCENE[slotKey]
    if not scene then
        return nil, "invalid slot"
    end

    local bossCfg = GetBossConfig()
    if not bossCfg then
        return nil, "boss config unavailable"
    end

    local sceneData = bossCfg:ExportScene(scene, { [slotKey] = true })
    local slotRow = type(sceneData) == "table" and type(sceneData.slots) == "table" and sceneData.slots[slotKey] or nil
    if type(slotRow) ~= "table" then
        return nil, "slot export unavailable"
    end

    local authorKey, authorName = ResolveBuiltInAuthorIdentity(options)

    local snippet = BuildBuiltInAuthorSlotSnippet(slotKey, authorKey, authorName, slotRow)
    local presetDir = SLOT_PRESET_DIR[slotKey] or slotKey
    local targetPath = string.format("EXBossData/Modules/Boss/Presets/%s/%s.lua", presetDir, authorKey)
    return snippet, nil, {
        slotKey = slotKey,
        authorKey = authorKey,
        authorName = authorName,
        targetPath = targetPath,
    }
end

local function BuildBuiltInTrashConfigSnippet(authorKey, authorName, payload)
    local metaText = SerializeStable(type(payload.meta) == "table" and payload.meta or {}, 1)
    local metaLines = SplitLines(metaText)
    local configText = SerializeStable(type(payload.trashCDConfig) == "table" and payload.trashCDConfig or {}, 1)
    local configLines = SplitLines(configText)
    local lines = {
        "_G.EXBossData.RegisterTrashPreset({",
        "    pluginKey = " .. string.format("%q", "builtin:" .. tostring(authorKey or "")) .. ",",
        "    authorKey = " .. string.format("%q", tostring(authorKey or "")) .. ",",
        "    authorName = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    title = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    builtIn = true,",
        "    exportMeta = " .. metaLines[1],
    }
    for i = 2, #metaLines do
        lines[#lines + 1] = metaLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "    trashConfig = " .. configLines[1]
    for i = 2, #configLines do
        lines[#lines + 1] = configLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:ExportBuiltInTrashConfigSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance == true then
        return nil, "built-in author lua export only supports trash cd data"
    end
    if options.includeTrashCD ~= true then
        return nil, "please select trash cd config"
    end
    local includeSlots = type(options.includeSlots) == "table" and options.includeSlots or nil
    if type(includeSlots) == "table" then
        for _, enabled in pairs(includeSlots) do
            if enabled == true then
                return nil, "built-in trash lua export only supports trash cd data"
            end
        end
    end

    local payload, err = BuildExportPayload(self, options)
    if not payload then
        return nil, err
    end
    if type(payload.trashCDConfig) ~= "table" then
        return nil, "trash cd config unavailable"
    end

    local authorKey, authorName = ResolveBuiltInAuthorIdentity(options)
    return BuildBuiltInTrashConfigSnippet(authorKey, authorName, payload), nil, {
        authorKey = authorKey,
        authorName = authorName,
        targetPath = string.format("EXBossData/Modules/Presets/Trash/%s.lua", authorKey),
    }
end

local function BuildBuiltInSettingsPageSnippet(authorKey, authorName, payload)
    local metaText = SerializeStable(type(payload.meta) == "table" and payload.meta or {}, 1)
    local metaLines = SplitLines(metaText)
    local settingsText = SerializeStable(type(payload.appearance) == "table" and payload.appearance or {}, 1)
    local settingsLines = SplitLines(settingsText)
    local lines = {
        "_G.EXBossData.RegisterSettingsPreset({",
        "    pluginKey = " .. string.format("%q", "builtin:" .. tostring(authorKey or "")) .. ",",
        "    authorKey = " .. string.format("%q", tostring(authorKey or "")) .. ",",
        "    authorName = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    title = " .. string.format("%q", tostring(authorName or authorKey or "")) .. ",",
        "    builtIn = true,",
        "    exportMeta = " .. metaLines[1],
    }
    for i = 2, #metaLines do
        lines[#lines + 1] = metaLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "    settingsPageConfig = " .. settingsLines[1]
    for i = 2, #settingsLines do
        lines[#lines + 1] = settingsLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:ExportBuiltInSettingsPageSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance ~= true then
        return nil, "please select settings page config"
    end
    if options.includeTrashCD == true then
        return nil, "built-in settings lua export only supports settings page config"
    end
    local includeSlots = type(options.includeSlots) == "table" and options.includeSlots or nil
    if type(includeSlots) == "table" then
        for _, enabled in pairs(includeSlots) do
            if enabled == true then
                return nil, "built-in settings lua export only supports settings page config"
            end
        end
    end

    local payload = {
        version = PAYLOAD_VERSION,
        meta = {
            payloadType = PAYLOAD_TYPE,
            configName = options.configName or "未命名配置",
            exporter = options.exporterName or self:GetPlayerIdentifier(),
            note = options.note or "",
            exportedAt = date and date("%Y-%m-%d %H:%M:%S") or "",
            addonVersion = ExBoss and ExBoss.VERSION or "unknown",
        },
        appearance = CapturePluginSettingsPageAppearance(),
    }

    local authorKey, authorName = ResolveBuiltInAuthorIdentity(options)
    return BuildBuiltInSettingsPageSnippet(authorKey, authorName, payload), nil, {
        authorKey = authorKey,
        authorName = authorName,
        targetPath = string.format("EXBossData/Modules/Presets/SettingsPage/%s.lua", authorKey),
    }
end

local function BuildPluginAuthorSlotSnippet(slotKey, slotRow)
    slotRow = type(slotRow) == "table" and slotRow or {}
    local eventText = SerializeStable(type(slotRow.events) == "table" and slotRow.events or {}, 1)
    local eventLines = SplitLines(eventText)
    local privateAuraLines = nil
    if type(slotRow.privateAura) == "table" then
        privateAuraLines = SplitLines(SerializeStable(slotRow.privateAura, 1))
    end
    local lines = {
        "local _, NS = ...",
        "NS.Plugin.RegisterSlot(" .. string.format("%q", tostring(slotKey or "")) .. ", {",
        "    events = " .. eventLines[1],
    }
    for i = 2, #eventLines do
        lines[#lines + 1] = eventLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    if privateAuraLines then
        lines[#lines + 1] = "    privateAura = " .. privateAuraLines[1]
        for i = 2, #privateAuraLines do
            lines[#lines + 1] = privateAuraLines[i]
        end
        lines[#lines] = lines[#lines] .. ","
    end
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:ExportPluginAuthorSlotSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance == true or options.includeTrashCD == true then
        return nil, "plugin author lua export only supports boss slot data"
    end

    local slotKey, slotErr = GetSingleSelectedSlot(options.includeSlots)
    if not slotKey then
        if slotErr == "no slot selected" then
            return nil, "please select one boss slot"
        end
        return nil, "plugin author lua export requires exactly one slot"
    end

    local scene = SLOT_SCENE[slotKey]
    if not scene then return nil, "invalid slot" end

    local bossCfg = GetBossConfig()
    if not bossCfg then return nil, "boss config unavailable" end

    local sceneData = bossCfg:ExportScene(scene, { [slotKey] = true })
    local slotRow = type(sceneData) == "table" and type(sceneData.slots) == "table" and sceneData.slots[slotKey] or nil
    if type(slotRow) ~= "table" then return nil, "slot export unavailable" end

    local presetDir = SLOT_PRESET_DIR[slotKey] or slotKey
    local targetPath = string.format("EXBOSS-TEMPLATE/Presets/%s.lua", presetDir)
    return BuildPluginAuthorSlotSnippet(slotKey, slotRow), nil, {
        slotKey = slotKey,
        targetPath = targetPath,
    }
end

local function BuildPluginTrashConfigSnippet(payload)
    local metaText = SerializeStable(type(payload.meta) == "table" and payload.meta or {}, 1)
    local metaLines = SplitLines(metaText)
    local configText = SerializeStable(type(payload.trashCDConfig) == "table" and payload.trashCDConfig or {}, 1)
    local configLines = SplitLines(configText)
    local lines = {
        "local _, NS = ...",
        "NS.Plugin.RegisterTrashConfig({",
        "    exportMeta = " .. metaLines[1],
    }
    for i = 2, #metaLines do
        lines[#lines + 1] = metaLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "    trashConfig = " .. configLines[1]
    for i = 2, #configLines do
        lines[#lines + 1] = configLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:ExportPluginTrashConfigSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance == true then
        return nil, "plugin trash lua export only supports trash cd data"
    end
    if options.includeTrashCD ~= true then
        return nil, "please select trash cd config"
    end
    local includeSlots = type(options.includeSlots) == "table" and options.includeSlots or nil
    if type(includeSlots) == "table" then
        for _, enabled in pairs(includeSlots) do
            if enabled == true then
                return nil, "plugin trash lua export only supports trash cd data"
            end
        end
    end

    local payload, err = BuildExportPayload(self, options)
    if not payload then
        return nil, err
    end
    if type(payload.trashCDConfig) ~= "table" then
        return nil, "trash cd config unavailable"
    end

    return BuildPluginTrashConfigSnippet(payload), nil, {
        targetPath = "EXBOSS-TEMPLATE/Presets/TrashConfig.lua",
    }
end

local function BuildPluginSettingsPageSnippet(payload)
    local metaText = SerializeStable(type(payload.meta) == "table" and payload.meta or {}, 1)
    local metaLines = SplitLines(metaText)
    local settingsText = SerializeStable(type(payload.appearance) == "table" and payload.appearance or {}, 1)
    local settingsLines = SplitLines(settingsText)
    local lines = {
        "local _, NS = ...",
        "NS.Plugin.RegisterSettingsPageConfig({",
        "    exportMeta = " .. metaLines[1],
    }
    for i = 2, #metaLines do
        lines[#lines + 1] = metaLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "    settingsPageConfig = " .. settingsLines[1]
    for i = 2, #settingsLines do
        lines[#lines + 1] = settingsLines[i]
    end
    lines[#lines] = lines[#lines] .. ","
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

function IE:ExportPluginSettingsPageSnippet(options)
    options = type(options) == "table" and options or {}
    if options.includeAppearance ~= true then
        return nil, "please select settings page config"
    end
    if options.includeTrashCD == true then
        return nil, "settings page lua export only supports settings page config"
    end
    local includeSlots = type(options.includeSlots) == "table" and options.includeSlots or nil
    if type(includeSlots) == "table" then
        for _, enabled in pairs(includeSlots) do
            if enabled == true then
                return nil, "settings page lua export only supports settings page config"
            end
        end
    end

    local payload = {
        version = PAYLOAD_VERSION,
        meta = {
            payloadType = PAYLOAD_TYPE,
            configName = options.configName or "未命名配置",
            exporter = options.exporterName or self:GetPlayerIdentifier(),
            note = options.note or "",
            exportedAt = date and date("%Y-%m-%d %H:%M:%S") or "",
            addonVersion = ExBoss and ExBoss.VERSION or "unknown",
        },
        appearance = CapturePluginSettingsPageAppearance(),
    }

    return BuildPluginSettingsPageSnippet(payload), nil, {
        targetPath = "EXBOSS-TEMPLATE/Presets/SettingsPage.lua",
    }
end

function IE:ApplySettingsPageConfig(appearance)
    return ApplyAppearance(appearance)
end

-- 获取导入预览摘要（不实际导入）
function IE:GetImportSummary(payload)
    if type(payload) ~= "table" then return nil, "invalid payload" end
    local meta = type(payload.meta) == "table" and payload.meta or {}
    if meta.payloadType ~= PAYLOAD_TYPE then return nil, "unsupported payload" end

    local summary = {
        version         = payload.version,
        configName      = meta.configName  or "未命名配置",
        exporter        = meta.exporter    or "未知",
        note            = meta.note        or "",
        exportedAt      = meta.exportedAt  or "",
        hasAppearance   = (type(payload.appearance) == "table"),
        hasTrashCD      = (type(payload.trashCDConfig) == "table"),
        hasMplus        = false,
        hasRaid         = false,
        mplusEventCount = 0,
        raidEventCount  = 0,
        slotAvailability = {},
        slotEventCount   = {},
    }

    local scenes = payload.bossConfig
    if type(scenes) == "table" then
        if type(scenes.mplus) == "table" then
            summary.hasMplus        = true
            local slotCount = 0
            for slotKey, slotRow in pairs((scenes.mplus.slots or {})) do
                local count = CountEntries(type(slotRow) == "table" and slotRow.events or nil)
                slotCount = slotCount + count
                summary.slotAvailability[slotKey] = true
                summary.slotEventCount[slotKey] = count
            end
            summary.mplusEventCount = slotCount
        end
        if type(scenes.raid) == "table" then
            summary.hasRaid        = true
            local slotCount = 0
            for slotKey, slotRow in pairs((scenes.raid.slots or {})) do
                local count = CountEntries(type(slotRow) == "table" and slotRow.events or nil)
                slotCount = slotCount + count
                summary.slotAvailability[slotKey] = true
                summary.slotEventCount[slotKey] = count
            end
            summary.raidEventCount = slotCount
        end
    end
    return summary
end

-- 导入（payload 必须已通过 DecodePayload 解码）
-- options = {
--   importAppearance = bool,
--   importSlots      = { [slotKey] = true, ... },
--   namePrefix       = string,
-- }
function IE:Import(payload, options)
    if type(payload) ~= "table" then return false, "invalid payload" end
    local summary, err = self:GetImportSummary(payload)
    if not summary then return false, err or "unsupported payload" end

    options = type(options) == "table" and options or {}
    local doAppearance = (options.importAppearance == true)
    local doTrashCD = (options.importTrashCD == true)
    local importSlots = type(options.importSlots) == "table" and options.importSlots or {}
    local importAuthorName = Trim(options.authorName or options.namePrefix or "")
    local wantMplus, wantRaid = false, false
    for slotKey, enabled in pairs(importSlots) do
        if enabled == true then
            local scene = SLOT_SCENE[slotKey]
            if scene == "mplus" then
                wantMplus = true
            elseif scene == "raid" then
                wantRaid = true
            end
        end
    end
    if not doAppearance and not doTrashCD and not wantMplus and not wantRaid then
        return false, "nothing selected"
    end

    local parts = {}

    if doAppearance then
        if type(payload.appearance) ~= "table" then
            return false, "payload has no settings section"
        end
        local ok2, applyErr = ApplyAppearance(payload.appearance)
        if not ok2 then return false, applyErr end
        parts[#parts + 1] = "设置页配置已应用"
    end

    if doTrashCD then
        local trashStore = GetTrashStore()
        if not (trashStore and type(trashStore.ImportFullConfig) == "function") then
            return false, "trash cd config unavailable"
        end
        if type(payload.trashCDConfig) ~= "table" then
            return false, "payload has no trashCDConfig section"
        end
        local ok2, importErr = trashStore.ImportFullConfig(payload.trashCDConfig)
        if not ok2 then
            return false, importErr
        end
        parts[#parts + 1] = "小怪CD设置已导入"
    end

    if wantMplus or wantRaid then
        local bossCfg = GetBossConfig()
        if not bossCfg then return false, "boss config unavailable" end
        local scenes = payload.bossConfig
        if type(scenes) ~= "table" then
            return false, "payload has no bossConfig section"
        end

        if wantMplus then
            local src = scenes.mplus
            if type(src) ~= "table" then
                return false, "payload has no mplus config"
            end
            local slotData = { selections = {}, slots = {} }
            for slotKey, enabled in pairs(importSlots) do
                if enabled == true and SLOT_SCENE[slotKey] == "mplus" then
                    if type(src.selections) == "table" and src.selections[slotKey] ~= nil then
                        slotData.selections[slotKey] = src.selections[slotKey]
                    end
                    if type(src.slots) == "table" and src.slots[slotKey] ~= nil then
                        slotData.slots[slotKey] = src.slots[slotKey]
                    end
                end
            end
            local ok2, err2 = bossCfg:ImportScene("mplus", slotData, {
                authorName = importAuthorName ~= "" and importAuthorName or (payload.meta and payload.meta.configName) or nil,
            })
            if not ok2 then return false, err2 end
            parts[#parts + 1] = "大米槽位已导入"
        end
        if wantRaid then
            local src = scenes.raid
            if type(src) ~= "table" then
                return false, "payload has no raid config"
            end
            local slotData = { selections = {}, slots = {} }
            for slotKey, enabled in pairs(importSlots) do
                if enabled == true and SLOT_SCENE[slotKey] == "raid" then
                    if type(src.selections) == "table" and src.selections[slotKey] ~= nil then
                        slotData.selections[slotKey] = src.selections[slotKey]
                    end
                    if type(src.slots) == "table" and src.slots[slotKey] ~= nil then
                        slotData.slots[slotKey] = src.slots[slotKey]
                    end
                end
            end
            local ok2, err2 = bossCfg:ImportScene("raid", slotData, {
                authorName = importAuthorName ~= "" and importAuthorName or (payload.meta and payload.meta.configName) or nil,
            })
            if not ok2 then return false, err2 end
            parts[#parts + 1] = "团本槽位已导入"
        end
    end

    return true, table.concat(parts, "，")
end

-- 一步完成：解码字符串 + 导入
-- options 同 Import；传 nil 时自动导入包里存在的所有块
function IE:ImportString(rawText, options)
    local payload, decErr = DecodePayload(rawText)
    if not payload then return false, "decode failed: " .. tostring(decErr) end
    if type(payload.meta) ~= "table"
        or payload.meta.payloadType ~= PAYLOAD_TYPE
        or tonumber(payload.version) ~= PAYLOAD_VERSION then
        return false, "unsupported payload version " .. tostring(payload.version)
    end
    if type(options) ~= "table" then
        local scenes = payload.bossConfig
        local autoSlots = {}
        local function Collect(sceneName)
            local sceneRow = type(scenes) == "table" and scenes[sceneName] or nil
            if type(sceneRow) == "table" and type(sceneRow.slots) == "table" then
                for slotKey in pairs(sceneRow.slots) do
                    autoSlots[slotKey] = true
                end
            end
        end
        Collect("mplus")
        Collect("raid")
        options = {
            importAppearance = (type(payload.appearance) == "table"),
            importTrashCD    = (type(payload.trashCDConfig) == "table"),
            importSlots      = autoSlots,
        }
    end
    return self:Import(payload, options)
end
