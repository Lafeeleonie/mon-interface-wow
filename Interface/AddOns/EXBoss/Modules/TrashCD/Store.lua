---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Store = ExBoss.TrashCD.Store or {}
ExBoss.TrashCD.Store = Store
ExBoss.Trash.Store = Store

local ExwindTools = _G.ExwindTools
local MODULE_KEY = "ExBoss.TrashCD.Settings"
local SPELL_EDITOR_MODULE_KEY = "ExBoss.TrashCD.SpellEditor"

local function GetDataModule()
    return ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
end

local DEFAULTS = {
    enabled = true,
    monitorEnabled = true,
    useTimelineScriptEvent = true,
    hideLongTimerBarEnabled = false,
    hideLongTimerBarSeconds = 0,
    keepTimerBarAfterReadyEnabled = true,
    keepTimerBarAfterReadySeconds = 10,
    nameplateGrowthSide = "left",
    hideNameplateNPCID = false,
    nameplateIconStrata = "DIALOG",
    nameplateIconSize = 25,
    nameplateOffsetX = 6,
    nameplateOffsetY = 0,
    nameplateIcon = {
        borderColorA = 1,
        borderColorB = 0,
        borderColorG = 0,
        borderColorR = 0,
        borderPadding = 0,
        borderSize = 1,
        borderTexture = "Square Full White",
        showIcon = true,
        height = 25,
        reverse = false,
        showBorder = true,
        width = 25,
        x = 6,
        y = 0,
        spacing = 2,
        showBorder = true,
        borderTexture = "Square Full White",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 1,
        borderPadding = 0,
        readyBorderEnabled = true,
        readyBorderColorR = 0.20,
        readyBorderColorG = 0.85,
        readyBorderColorB = 0.20,
        readyBorderColorA = 1,
    },
    nameplateIconText = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        size = 15,
        font = "",
        outline = "OUTLINE",
        x = 0,
        y = 0,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
    },
    spellEntries = {},
}

local SPELL_ENTRY_DEFAULTS = {
    enabled = true,
    tankEnabled = true,
    healerEnabled = true,
    dpsEnabled = true,
    showBunBar = false,
    showTimerBar = true,
    showNameplate = true,
    bossStages = "",
    customName = "",
    eventColorEnabled = false,
    eventColorMode = "none",
    eventColor = { r = 1, g = 1, b = 1, a = 1 },
    centralEnabled = false,
    centralLead = 0,
    centralText = "",
    countdownEnabled = false,
    countdownLead = 5,
    countdownVoiceEnabled = false,
    countdownPlayName = false,
    preAlertEnabled = false,
    countdownText = "",
    timerBarRenameEnabled = false,
    timerBarName = "",
    ringEnabled = false,
    ringRenameEnabled = false,
    ringRenameText = "",
    castProgressBarEnabled = false,
    castProgressBarRenameEnabled = false,
    castProgressBarRenameText = "",
    ringCastCheckEnabled = false,
    targetAlertStartEnabled = false,
    targetAlertStartLSM = "",
    targetAlertTankEnabled = false,
    targetAlertRingEnabled = false,
    targetAlertIconEnabled = false,
    targetAlertTextEnabledV2 = false,
    targetAlertStealthEnabledV2 = false,
    voice1Enabled = false,
    voice1Source = "pack",
    voice1Label = "",
    voice1LSM = "",
    voice1Path = "",
    voice1OffsetMode = "delay",
    voice1OffsetSeconds = 0,
    voice2Enabled = false,
    voice2Source = "pack",
    voice2Label = "",
    voice2LSM = "",
    voice2Path = "",
    voice2OffsetMode = "delay",
    voice2OffsetSeconds = 0,
}

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

local function ApplyDefaults(dst, defaults)
    dst = type(dst) == "table" and dst or {}
    if type(defaults) ~= "table" then
        return dst
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            dst[key] = ApplyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
    return dst
end

local function CopyValues(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = CopyValues(type(dst[key]) == "table" and dst[key] or {}, value)
        else
            dst[key] = value
        end
    end
    return dst
end

local NormalizeSpellEntry
local LEGACY_SPELL_KEY_PATTERN = "^(%d+):(%d+):(%d+)$"

local function NormalizeText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function ParseSpellEntryKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local mapID, npcID, spellID = key:match(LEGACY_SPELL_KEY_PATTERN)
    if not mapID or not npcID or not spellID then
        return nil
    end
    return tonumber(mapID), tonumber(npcID), tonumber(spellID)
end

local function IsKnownTopLevelKey(key)
    if type(key) ~= "string" then
        return false
    end
    if DEFAULTS[key] ~= nil then
        return true
    end
    return key == "_nameplateGrowthSideDefaultMigrated"
        or key == "_nameplateDefaultsV2"
end

local function IsTrashVoiceDebug()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TrashVoice and ExBoss.Debug.TrashVoice.enabled == true
end

local function VoiceDebugPrint(msg)
    if not IsTrashVoiceDebug() then
        return
    end
    local test = ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    if test and type(test.AppendExternalDebug) == "function" then
        test.AppendExternalDebug("TrashVoice", msg, true)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss TrashVoice|r " .. tostring(msg or ""))
    end
end

local function ApplyPresetValues(out, preset)
    if type(out) ~= "table" or type(preset) ~= "table" then
        return out
    end
    local presetCustomName = tostring(preset.customName or "")
    local presetTimerBarName = tostring(preset.timerBarName or "")
    if NormalizeText(presetTimerBarName) == "" and NormalizeText(presetCustomName) ~= "" then
        presetTimerBarName = presetCustomName
    end
    out.enabled = preset.enabled == true
    out.tankEnabled = preset.tankEnabled == true
    out.healerEnabled = preset.healerEnabled == true
    out.dpsEnabled = preset.dpsEnabled == true
    if preset.showBunBar ~= nil then
        out.showBunBar = preset.showBunBar == true
    end
    if preset.showTimerBar ~= nil then
        out.showTimerBar = preset.showTimerBar == true
    end
    if preset.showNameplate ~= nil then
        out.showNameplate = preset.showNameplate == true
    end
    out.bossStages = tostring(preset.bossStages or preset.bossStage or preset.bossProgressStages or "")
    out.customName = presetCustomName
    out.eventColorEnabled = preset.eventColorEnabled == true
    out.eventColorMode = tostring(preset.eventColorMode or out.eventColorMode)
    if type(preset.eventColor) == "table" then
        out.eventColor = {
            r = tonumber(preset.eventColor.r) or out.eventColor.r,
            g = tonumber(preset.eventColor.g) or out.eventColor.g,
            b = tonumber(preset.eventColor.b) or out.eventColor.b,
            a = tonumber(preset.eventColor.a) or out.eventColor.a,
        }
    end
    out.centralEnabled = preset.centralEnabled == true
    out.centralLead = tonumber(preset.centralLead) or out.centralLead
    out.centralText = tostring(preset.centralText or "")
    if preset.countdownEnabled ~= nil then
        out.countdownEnabled = preset.countdownEnabled == true
    elseif preset.preAlertEnabled ~= nil then
        out.countdownEnabled = preset.preAlertEnabled == true
    end
    out.countdownLead = tonumber(preset.countdownLead) or out.countdownLead
    if preset.countdownVoiceEnabled ~= nil then
        out.countdownVoiceEnabled = preset.countdownVoiceEnabled == true
    elseif preset.voice2Enabled ~= nil or preset.voiceEnabled ~= nil then
        out.countdownVoiceEnabled = (preset.voice2Enabled == true) or (preset.voiceEnabled == true)
    end
    if preset.countdownPlayName ~= nil then
        out.countdownPlayName = preset.countdownPlayName == true
    elseif preset.voice2Enabled ~= nil or preset.voiceEnabled ~= nil then
        out.countdownPlayName = (preset.voice2Enabled == true) or (preset.voiceEnabled == true)
    end
    out.preAlertEnabled = preset.preAlertEnabled == true
    out.countdownText = tostring(preset.countdownText or "")
    out.timerBarRenameEnabled = preset.timerBarRenameEnabled == true or NormalizeText(presetTimerBarName) ~= ""
    out.timerBarName = presetTimerBarName
    out.ringEnabled = preset.ringEnabled == true or preset.showRing == true
    out.ringRenameEnabled = preset.ringRenameEnabled == true
    out.ringRenameText = NormalizeText(preset.ringRenameText or preset.ringName)
    out.castProgressBarEnabled = preset.castProgressBarEnabled == true
        or preset.castBarEnabled == true
        or preset.showCastBar == true
    out.castProgressBarRenameEnabled = preset.castProgressBarRenameEnabled == true or preset.castBarRenameEnabled == true
    out.castProgressBarRenameText = NormalizeText(preset.castProgressBarRenameText or preset.castBarRenameText)
    out.ringCastCheckEnabled = preset.ringCastCheckEnabled == true or preset.ringCastCheck == true
    out.targetAlertStartEnabled = preset.targetAlertStartEnabled == true
    out.targetAlertStartLSM = tostring(preset.targetAlertStartLSM or "")
    out.targetAlertTankEnabled = preset.targetAlertTankEnabled == true
    out.targetAlertRingEnabled = preset.targetAlertRingEnabled == true
    out.targetAlertIconEnabled = preset.targetAlertIconEnabled == true
    out.targetAlertTextEnabledV2 = preset.targetAlertTextEnabledV2 == true
    out.targetAlertStealthEnabledV2 = preset.targetAlertStealthEnabledV2 == true
    out.voice1Enabled = preset.voice1Enabled == true
    out.voice1Source = tostring(preset.voice1Source or preset.castVoiceSource or out.voice1Source)
    out.voice1Label = tostring(preset.voice1Label or preset.castVoiceLabel or "")
    out.voice1LSM = tostring(preset.voice1LSM or "")
    out.voice1Path = tostring(preset.voice1Path or "")
    out.voice1OffsetMode = tostring(preset.voice1OffsetMode or out.voice1OffsetMode)
    out.voice1OffsetSeconds = tonumber(preset.voice1OffsetSeconds) or out.voice1OffsetSeconds
    out.voice2Enabled = preset.voice2Enabled == true
    out.voice2Source = tostring(preset.voice2Source or preset.pre5VoiceSource or out.voice2Source)
    out.voice2Label = tostring(preset.voice2Label or preset.pre5VoiceLabel or "")
    out.voice2LSM = tostring(preset.voice2LSM or "")
    out.voice2Path = tostring(preset.voice2Path or "")
    out.voice2OffsetMode = tostring(preset.voice2OffsetMode or out.voice2OffsetMode)
    out.voice2OffsetSeconds = tonumber(preset.voice2OffsetSeconds) or out.voice2OffsetSeconds
    if preset.voice2Enabled == nil and preset.voiceEnabled ~= nil then
        out.voice2Enabled = preset.voiceEnabled == true
    end
    if (out.voice2Label == "" or preset.voice2Label == nil) and type(preset.voiceLabel) == "string" then
        out.voice2Label = tostring(preset.voiceLabel or "")
    end
    return out
end

local function RestorePresetTextFallbacks(out, presetDefaults)
    if type(out) ~= "table" or type(presetDefaults) ~= "table" then
        return out
    end
    if NormalizeText(out.customName) == "" and NormalizeText(presetDefaults.customName) ~= "" then
        out.customName = tostring(presetDefaults.customName or "")
    end
    if NormalizeText(out.timerBarName) == "" and NormalizeText(presetDefaults.timerBarName) ~= "" then
        out.timerBarName = tostring(presetDefaults.timerBarName or "")
    end
    if NormalizeText(out.ringRenameText) == "" and NormalizeText(presetDefaults.ringRenameText) ~= "" then
        out.ringRenameText = tostring(presetDefaults.ringRenameText or "")
    end
    if out.ringRenameEnabled ~= true and NormalizeText(out.ringRenameText) ~= "" and presetDefaults.ringRenameEnabled == true then
        out.ringRenameEnabled = true
    end
    if NormalizeText(out.voice1Label) == "" and NormalizeText(presetDefaults.voice1Label) ~= "" then
        out.voice1Label = tostring(presetDefaults.voice1Label or "")
    end
    if NormalizeText(out.voice2Label) == "" and NormalizeText(presetDefaults.voice2Label) ~= "" then
        out.voice2Label = tostring(presetDefaults.voice2Label or "")
    end
    return out
end

local function BuildSpellEntryDefaultsForSpell(mapID, npcID, spellID)
    local out = DeepCopy(SPELL_ENTRY_DEFAULTS)
    local Data = GetDataModule()
    local preset = Data and Data.GetTrashSpellPreset and Data.GetTrashSpellPreset(mapID, npcID, spellID) or nil
    if type(preset) == "table" then
        ApplyPresetValues(out, preset)
    end
    local customEvents = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.CustomEvents or nil
    local customPreset = customEvents and type(customEvents.GetPreset) == "function"
        and customEvents.GetPreset(mapID, npcID, spellID)
        or nil
    if type(customPreset) == "table" then
        ApplyPresetValues(out, customPreset)
    end
    return NormalizeSpellEntry(out)
end

function Store.GetModuleKey()
    return MODULE_KEY
end

function Store.GetPluginPresetItems()
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetTrashPluginPresetList) ~= "function" then
        return {}
    end
    local ok, items = pcall(api.GetTrashPluginPresetList)
    if not ok or type(items) ~= "table" then
        return {}
    end
    return items
end

function Store.GetPluginPreset(pluginKey)
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetTrashPluginPreset) ~= "function" then
        return nil
    end
    local ok, row = pcall(api.GetTrashPluginPreset, pluginKey)
    if not ok or type(row) ~= "table" then
        return nil
    end
    return row
end

function Store.ImportPluginPreset(pluginKey)
    local preset = Store.GetPluginPreset(pluginKey)
    if type(preset) ~= "table" or type(preset.trashConfig) ~= "table" then
        return false, "trash preset not found"
    end
    return Store.ImportFullConfig(preset.trashConfig)
end

function Store.GetDefaults()
    return DeepCopy(DEFAULTS)
end

function Store.ExportFullConfig()
    local db = Store.EnsureDB()
    return DeepCopy(db)
end

function Store.GetSpellEntryDefaults()
    return DeepCopy(SPELL_ENTRY_DEFAULTS)
end

function Store.EnsureDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.trashCD = ApplyDefaults(ExBossDB.trashCD, DeepCopy(DEFAULTS))
    ExBossDB.trashCD.spellEntries = type(ExBossDB.trashCD.spellEntries) == "table" and ExBossDB.trashCD.spellEntries or {}
    if ExBossDB.trashCD._nameplateGrowthSideDefaultMigrated ~= true then
        ExBossDB.trashCD.nameplateGrowthSide = "left"
        ExBossDB.trashCD._nameplateGrowthSideDefaultMigrated = true
    end
    if ExBossDB.trashCD._nameplateDefaultsV2 ~= true then
        local icon = type(ExBossDB.trashCD.nameplateIcon) == "table" and ExBossDB.trashCD.nameplateIcon or {}
        ExBossDB.trashCD.nameplateIcon = icon
        if tonumber(icon.width) == nil or tonumber(icon.width) == 18 then icon.width = 25 end
        if tonumber(icon.height) == nil or tonumber(icon.height) == 18 then icon.height = 25 end
        if tonumber(icon.x) == nil or tonumber(icon.x) == 0 then icon.x = 6 end
        if icon.reverse == nil then icon.reverse = false end
        if icon.showBorder == nil then icon.showBorder = true end
        if icon.borderTexture == nil or icon.borderTexture == "None" then icon.borderTexture = "Square Full White" end
        if tonumber(icon.borderColorR) == nil then icon.borderColorR = 0 end
        if tonumber(icon.borderColorG) == nil then icon.borderColorG = 0 end
        if tonumber(icon.borderColorB) == nil then icon.borderColorB = 0 end
        if tonumber(icon.borderColorA) == nil then icon.borderColorA = 1 end
        if tonumber(icon.borderSize) == nil then icon.borderSize = 1 end
        if tonumber(icon.borderPadding) == nil then icon.borderPadding = 0 end
        if tonumber(ExBossDB.trashCD.nameplateIconSize) == nil or tonumber(ExBossDB.trashCD.nameplateIconSize) == 18 then ExBossDB.trashCD.nameplateIconSize = 25 end
        if tonumber(ExBossDB.trashCD.nameplateOffsetX) == nil or tonumber(ExBossDB.trashCD.nameplateOffsetX) == 0 then ExBossDB.trashCD.nameplateOffsetX = 6 end

        local font = type(ExBossDB.trashCD.nameplateIconText) == "table" and ExBossDB.trashCD.nameplateIconText or {}
        ExBossDB.trashCD.nameplateIconText = font
        if tonumber(font.size) == nil or tonumber(font.size) == 11 then font.size = 15 end
        ExBossDB.trashCD.hideNameplateNPCID = false
        ExBossDB.trashCD._nameplateDefaultsV2 = true
    end
    return ExBossDB.trashCD
end

function Store.SyncSavedToModuleDB()
    if not ExwindTools or type(ExwindTools.GetModuleDB) ~= "function" then
        return nil
    end
    local saved = Store.EnsureDB()
    local moduleDB = ExwindTools:GetModuleDB(MODULE_KEY, DeepCopy(DEFAULTS))
    ApplyDefaults(moduleDB, DeepCopy(DEFAULTS))
    CopyValues(moduleDB, saved)
    return moduleDB
end

function Store.GetModuleDB()
    if not ExwindTools or type(ExwindTools.GetModuleDB) ~= "function" then
        return nil
    end
    local moduleDB = ExwindTools:GetModuleDB(MODULE_KEY, DeepCopy(DEFAULTS))
    ApplyDefaults(moduleDB, DeepCopy(DEFAULTS))
    return moduleDB
end

function Store.GetSpellEntryKey(mapID, npcID, spellID)
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    local sid = tonumber(spellID)
    if not mid or not nid or not sid then
        return nil
    end
    return string.format("%d:%d:%d", mid, nid, sid)
end

local function BuildImportedSpellEntry(key, value)
    local mapID, npcID, spellID = ParseSpellEntryKey(key)
    if not mapID then
        return nil, "invalid spell entry key"
    end

    local row = BuildSpellEntryDefaultsForSpell(mapID, npcID, spellID)
    local valueType = type(value)

    if valueType == "table" then
        ApplyPresetValues(row, value)
        CopyValues(row, value)
    elseif valueType == "boolean" then
        row.enabled = value
    elseif valueType == "number" then
        row.enabled = (value ~= 0)
    elseif valueType == "string" then
        local text = NormalizeText(value)
        row.enabled = text ~= "" and text ~= "0"
    elseif value == nil then
        row.enabled = false
    else
        return nil, "unsupported value type: " .. valueType
    end

    return NormalizeSpellEntry(row)
end

local function MigrateImportedConfig(payload)
    if type(payload) ~= "table" then
        return nil, "invalid trash config"
    end

    if payload.spellEntries ~= nil and type(payload.spellEntries) ~= "table" then
        return nil, "invalid trash config: spellEntries must be table"
    end

    local out = DeepCopy(DEFAULTS)
    local recognizedTopLevel = 0
    local legacySpellKeyCount = 0
    local migratedSpellCount = 0

    for key, value in pairs(payload) do
        if key ~= "spellEntries" and IsKnownTopLevelKey(key) then
            out[key] = DeepCopy(value)
            recognizedTopLevel = recognizedTopLevel + 1
        end
    end

    out.spellEntries = {}

    if type(payload.spellEntries) == "table" then
        recognizedTopLevel = recognizedTopLevel + 1
        for key, value in pairs(payload.spellEntries) do
            if type(key) ~= "string" then
                return nil, "invalid trash config: spellEntries key must be string"
            end
            if not ParseSpellEntryKey(key) then
                return nil, "invalid trash config: unsupported spellEntries key " .. key
            end
            local row, err = BuildImportedSpellEntry(key, value)
            if not row then
                return nil, "invalid trash spell entry " .. key .. ": " .. tostring(err)
            end
            out.spellEntries[key] = row
            migratedSpellCount = migratedSpellCount + 1
        end
    end

    for key, value in pairs(payload) do
        if ParseSpellEntryKey(key) then
            legacySpellKeyCount = legacySpellKeyCount + 1
            if out.spellEntries[key] == nil then
                local row, err = BuildImportedSpellEntry(key, value)
                if not row then
                    return nil, "legacy trash spell entry " .. key .. " cannot be migrated: " .. tostring(err)
                end
                out.spellEntries[key] = row
                migratedSpellCount = migratedSpellCount + 1
            end
        end
    end

    if legacySpellKeyCount > 0 and migratedSpellCount == 0 then
        return nil, "legacy trash config migration failed"
    end

    if recognizedTopLevel == 0 and migratedSpellCount == 0 then
        return nil, "unsupported trash config schema"
    end

    return out
end

function NormalizeSpellEntry(row)
    row = type(row) == "table" and row or {}
    row.enabled = row.enabled == true
    row.tankEnabled = row.tankEnabled == true
    row.healerEnabled = row.healerEnabled == true
    row.dpsEnabled = row.dpsEnabled == true
    row.showBunBar = row.showBunBar ~= false
    row.showTimerBar = row.showTimerBar ~= false
    row.showNameplate = row.showNameplate == true
    if type(row.bossStages) ~= "string" then
        row.bossStages = SPELL_ENTRY_DEFAULTS.bossStages
    end
    if type(row.customName) ~= "string" then
        row.customName = SPELL_ENTRY_DEFAULTS.customName
    end
    row.eventColorEnabled = row.eventColorEnabled == true
    if type(row.eventColorMode) ~= "string" then
        row.eventColorMode = SPELL_ENTRY_DEFAULTS.eventColorMode
    end
    if type(row.eventColor) ~= "table" then
        row.eventColor = DeepCopy(SPELL_ENTRY_DEFAULTS.eventColor)
    end
    row.eventColor.r = tonumber(row.eventColor.r) or SPELL_ENTRY_DEFAULTS.eventColor.r
    row.eventColor.g = tonumber(row.eventColor.g) or SPELL_ENTRY_DEFAULTS.eventColor.g
    row.eventColor.b = tonumber(row.eventColor.b) or SPELL_ENTRY_DEFAULTS.eventColor.b
    row.eventColor.a = tonumber(row.eventColor.a) or SPELL_ENTRY_DEFAULTS.eventColor.a
    row.centralEnabled = row.centralEnabled == true
    local centralLead = tonumber(row.centralLead)
    row.centralLead = centralLead and centralLead or SPELL_ENTRY_DEFAULTS.centralLead
    if type(row.centralText) ~= "string" then
        row.centralText = SPELL_ENTRY_DEFAULTS.centralText
    end
    row.countdownEnabled = row.countdownEnabled == true
    local countdownLead = tonumber(row.countdownLead)
    row.countdownLead = countdownLead and countdownLead or SPELL_ENTRY_DEFAULTS.countdownLead
    row.countdownVoiceEnabled = row.countdownVoiceEnabled == true
    row.countdownPlayName = row.countdownPlayName == true
    row.preAlertEnabled = row.preAlertEnabled == true
    if type(row.countdownText) ~= "string" then
        row.countdownText = SPELL_ENTRY_DEFAULTS.countdownText
    end
    row.timerBarRenameEnabled = row.timerBarRenameEnabled == true
    if type(row.timerBarName) ~= "string" then
        row.timerBarName = SPELL_ENTRY_DEFAULTS.timerBarName
    end
    row.ringEnabled = row.ringEnabled == true
    row.ringRenameEnabled = row.ringRenameEnabled == true
    if type(row.ringRenameText) ~= "string" then
        row.ringRenameText = SPELL_ENTRY_DEFAULTS.ringRenameText
    end
    row.castProgressBarEnabled = row.castProgressBarEnabled == true
        or row.castBarEnabled == true
        or row.showCastBar == true
    row.castProgressBarRenameEnabled = row.castProgressBarRenameEnabled == true
    if type(row.castProgressBarRenameText) ~= "string" then
        row.castProgressBarRenameText = SPELL_ENTRY_DEFAULTS.castProgressBarRenameText
    end
    row.ringCastCheckEnabled = row.ringCastCheckEnabled == true
    row.targetAlertStartEnabled = row.targetAlertStartEnabled == true
    if type(row.targetAlertStartLSM) ~= "string" then
        row.targetAlertStartLSM = SPELL_ENTRY_DEFAULTS.targetAlertStartLSM
    end
    row.targetAlertTankEnabled = row.targetAlertTankEnabled == true
    row.targetAlertRingEnabled = row.targetAlertRingEnabled == true
    row.targetAlertIconEnabled = row.targetAlertIconEnabled == true
    row.targetAlertTextEnabledV2 = row.targetAlertTextEnabledV2 == true
    row.targetAlertStealthEnabledV2 = row.targetAlertStealthEnabledV2 == true
    if type(row.voice1Source) ~= "string" then row.voice1Source = SPELL_ENTRY_DEFAULTS.voice1Source end
    if type(row.voice1Label) ~= "string" then row.voice1Label = SPELL_ENTRY_DEFAULTS.voice1Label end
    if type(row.voice1LSM) ~= "string" then row.voice1LSM = SPELL_ENTRY_DEFAULTS.voice1LSM end
    if type(row.voice1Path) ~= "string" then row.voice1Path = SPELL_ENTRY_DEFAULTS.voice1Path end
    if type(row.voice1OffsetMode) ~= "string" then row.voice1OffsetMode = SPELL_ENTRY_DEFAULTS.voice1OffsetMode end
    row.voice1OffsetSeconds = tonumber(row.voice1OffsetSeconds) or SPELL_ENTRY_DEFAULTS.voice1OffsetSeconds
    if type(row.voice2Source) ~= "string" then row.voice2Source = SPELL_ENTRY_DEFAULTS.voice2Source end
    if type(row.voice2Label) ~= "string" then row.voice2Label = SPELL_ENTRY_DEFAULTS.voice2Label end
    if type(row.voice2LSM) ~= "string" then row.voice2LSM = SPELL_ENTRY_DEFAULTS.voice2LSM end
    if type(row.voice2Path) ~= "string" then row.voice2Path = SPELL_ENTRY_DEFAULTS.voice2Path end
    if type(row.voice2OffsetMode) ~= "string" then row.voice2OffsetMode = SPELL_ENTRY_DEFAULTS.voice2OffsetMode end
    row.voice2OffsetSeconds = tonumber(row.voice2OffsetSeconds) or SPELL_ENTRY_DEFAULTS.voice2OffsetSeconds
    row.voice1Enabled = row.voice1Enabled == true
    row.voice2Enabled = row.voice2Enabled == true
    return row
end

function Store.GetSpellEntry(mapID, npcID, spellID, createIfMissing)
    local key = Store.GetSpellEntryKey(mapID, npcID, spellID)
    if not key then
        return nil
    end
    local db = Store.EnsureDB()
    db.spellEntries = type(db.spellEntries) == "table" and db.spellEntries or {}
    local row = db.spellEntries[key]
    if row == nil and createIfMissing then
        row = BuildSpellEntryDefaultsForSpell(mapID, npcID, spellID)
        db.spellEntries[key] = row
    end
    if row then
        return NormalizeSpellEntry(row)
    end
    return nil
end

function Store.GetResolvedSpellEntry(mapID, npcID, spellID, createIfMissing)
    local out = DeepCopy(SPELL_ENTRY_DEFAULTS)
    local Data = GetDataModule()
    local preset = Data and Data.GetTrashSpellPreset and Data.GetTrashSpellPreset(mapID, npcID, spellID) or nil
    local presetDefaults = nil
    if type(preset) == "table" then
        ApplyPresetValues(out, preset)
        presetDefaults = DeepCopy(out)
    end
    local customEvents = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.CustomEvents or nil
    local customPreset = customEvents and type(customEvents.GetPreset) == "function"
        and customEvents.GetPreset(mapID, npcID, spellID)
        or nil
    if type(customPreset) == "table" then
        ApplyPresetValues(out, customPreset)
        presetDefaults = DeepCopy(out)
    end
    local saved = Store.GetSpellEntry(mapID, npcID, spellID, createIfMissing)
    if type(saved) == "table" then
        CopyValues(out, saved)
        RestorePresetTextFallbacks(out, presetDefaults)
    end
    local voiceBlacklist = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.VoiceBlacklist or nil
    local voiceBlock = voiceBlacklist and type(voiceBlacklist.GetEntry) == "function"
        and voiceBlacklist.GetEntry(mapID, npcID, spellID)
        or nil
    if type(voiceBlock) == "table" then
        out.authorVoiceDisabled = true
        out.authorVoiceDisableReasonKey = tostring(voiceBlock.reasonKey or "")
        out.authorVoiceDisableReason = tostring(voiceBlock.reason or "")
    else
        out.authorVoiceDisabled = nil
        out.authorVoiceDisableReasonKey = nil
        out.authorVoiceDisableReason = nil
    end
    return NormalizeSpellEntry(out)
end

function Store.SyncModuleDBToSaved()
    local saved = Store.EnsureDB()
    local moduleDB = Store.GetModuleDB()
    if moduleDB then
        CopyValues(saved, moduleDB)
    end
    return saved
end

function Store.ImportFullConfig(payload)
    local migrated, migrateErr = MigrateImportedConfig(payload)
    if type(migrated) ~= "table" then
        VoiceDebugPrint("import reject reason=" .. tostring(migrateErr or "invalid trash config"))
        return false, migrateErr or "invalid trash config"
    end
    ExBossDB = ExBossDB or {}
    ExBossDB.trashCD = DeepCopy(migrated)
    local db = Store.EnsureDB()
    db.spellEntries = type(db.spellEntries) == "table" and db.spellEntries or {}
    for key, row in pairs(db.spellEntries) do
        if type(key) == "string" and ParseSpellEntryKey(key) then
            db.spellEntries[key] = NormalizeSpellEntry(type(row) == "table" and row or {})
        else
            db.spellEntries[key] = nil
        end
    end
    local spellCount = 0
    for _ in pairs(db.spellEntries) do
        spellCount = spellCount + 1
    end
    VoiceDebugPrint(string.format(
        "import ok enabled=%s monitorEnabled=%s useTimelineScriptEvent=%s spellEntries=%d",
        tostring(db.enabled ~= false),
        tostring(db.monitorEnabled ~= false),
        tostring(db.useTimelineScriptEvent ~= false),
        spellCount
    ))
    Store.SyncSavedToModuleDB()
    Store.PublishConfigChanged("import")
    return true
end

function Store.ResetSettings()
    ExBossDB = ExBossDB or {}
    ExBossDB.trashCD = DeepCopy(DEFAULTS)
    if type(ExwindToolsDB) == "table" and type(ExwindToolsDB.ModuleDB) == "table" then
        ExwindToolsDB.ModuleDB[MODULE_KEY] = nil
        ExwindToolsDB.ModuleDB[SPELL_EDITOR_MODULE_KEY] = nil
    end
    Store.EnsureDB()
    Store.SyncSavedToModuleDB()
    Store.PublishConfigChanged("reset")
    return ExBossDB.trashCD
end

function Store.PublishConfigChanged(changedKey)
    if ExwindTools and type(ExwindTools.UpdateState) == "function" then
        ExwindTools:UpdateState(MODULE_KEY .. ".ConfigChanged", { key = changedKey })
    end
    local targetAlert = ExBoss and ExBoss.TargetAlert
    if targetAlert and type(targetAlert.RefreshActiveRegistrations) == "function" then
        targetAlert:RefreshActiveRegistrations()
    end
end

function Store.IsEnabled()
    local db = Store.EnsureDB()
    return db.enabled ~= false
end

function Store.IsMonitorEnabled()
    local db = Store.EnsureDB()
    return db.enabled ~= false and db.monitorEnabled ~= false
end

function Store.IsOutputEnabled()
    local db = Store.EnsureDB()
    return db.enabled ~= false
end

function Store.GetHideLongTimerBarConfig()
    local db = Store.EnsureDB()
    return {
        enabled = db.hideLongTimerBarEnabled == true,
        seconds = math.max(0, tonumber(db.hideLongTimerBarSeconds) or 0),
    }
end

function Store.GetKeepTimerBarAfterReadyConfig()
    local db = Store.EnsureDB()
    return {
        enabled = db.keepTimerBarAfterReadyEnabled == true,
        seconds = math.max(0, tonumber(db.keepTimerBarAfterReadySeconds) or 0),
    }
end

function Store.GetNameplateGrowthSide()
    local db = Store.EnsureDB()
    local side = tostring(db.nameplateGrowthSide or "left")
    if side ~= "left" and side ~= "right" then
        side = "left"
    end
    return side
end

function Store.GetNameplateIconLayout()
    local db = Store.EnsureDB()
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local enabled = cfg.showIcon ~= false
    local reverse = cfg.reverse == true
    local width = tonumber(cfg.width) or tonumber(db.nameplateIconSize) or 25
    local height = tonumber(cfg.height) or tonumber(db.nameplateIconSize) or width
    local x = tonumber(cfg.x) or tonumber(db.nameplateOffsetX) or 6
    local y = tonumber(cfg.y) or tonumber(db.nameplateOffsetY) or 0
    if width < 10 then width = 10 elseif width > 300 then width = 300 end
    if height < 10 then height = 10 elseif height > 300 then height = 300 end
    if x < -1000 then x = -1000 elseif x > 1000 then x = 1000 end
    if y < -1000 then y = -1000 elseif y > 1000 then y = 1000 end
    return enabled, width, height, x, y, reverse
end

function Store.GetNameplateIconSpacing()
    local db = Store.EnsureDB()
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local spacing = tonumber(cfg.spacing)
    if spacing == nil then
        spacing = 2
    end
    if spacing < 0 then spacing = 0 elseif spacing > 20 then spacing = 20 end
    return spacing
end

function Store.GetNameplateIconBorder()
    local db = Store.EnsureDB()
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local size = tonumber(cfg.borderSize) or 1
    local padding = tonumber(cfg.borderPadding) or 0
    if size < 1 then size = 1 elseif size > 20 then size = 20 end
    if padding < -20 then padding = -20 elseif padding > 20 then padding = 20 end
    return {
        show = cfg.showBorder ~= false,
        texture = tostring(cfg.borderTexture or "Square Full White"),
        size = size,
        padding = padding,
        r = tonumber(cfg.borderColorR) or 0,
        g = tonumber(cfg.borderColorG) or 0,
        b = tonumber(cfg.borderColorB) or 0,
        a = tonumber(cfg.borderColorA) or 1,
    }
end

function Store.GetNameplateReadyBorder()
    local db = Store.EnsureDB()
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    return {
        enabled = cfg.readyBorderEnabled ~= false,
        r = tonumber(cfg.readyBorderColorR) or 0.20,
        g = tonumber(cfg.readyBorderColorG) or 0.85,
        b = tonumber(cfg.readyBorderColorB) or 0.20,
        a = tonumber(cfg.readyBorderColorA) or 1,
    }
end

function Store.GetNameplateIconStrata()
    local db = Store.EnsureDB()
    local strata = tostring(db.nameplateIconStrata or "DIALOG"):upper()
    if strata == "BACKGROUND"
        or strata == "LOW"
        or strata == "MEDIUM"
        or strata == "HIGH"
        or strata == "DIALOG"
        or strata == "FULLSCREEN"
        or strata == "FULLSCREEN_DIALOG"
        or strata == "TOOLTIP" then
        return strata
    end
    return "DIALOG"
end

function Store.GetNameplateIconSize()
    local _, width, height = Store.GetNameplateIconLayout()
    return math.max(tonumber(width) or 25, tonumber(height) or 25)
end

function Store.GetNameplateOffset()
    local _, _, _, x, y = Store.GetNameplateIconLayout()
    return x, y
end

function Store.GetNameplateIconTextLayout()
    local db = Store.EnsureDB()
    local cfg = type(db.nameplateIconText) == "table" and db.nameplateIconText or {}
    local size = tonumber(cfg.size) or 15
    local x = tonumber(cfg.x) or 0
    local y = tonumber(cfg.y) or 0
    local shadowX = tonumber(cfg.shadowX) or 1
    local shadowY = tonumber(cfg.shadowY) or -1
    if size < 4 then size = 4 elseif size > 100 then size = 100 end
    if x < -200 then x = -200 elseif x > 200 then x = 200 end
    if y < -200 then y = -200 elseif y > 200 then y = 200 end
    if shadowX < -20 then shadowX = -20 elseif shadowX > 20 then shadowX = 20 end
    if shadowY < -20 then shadowY = -20 elseif shadowY > 20 then shadowY = 20 end
    return {
        r = tonumber(cfg.r) or 1,
        g = tonumber(cfg.g) or 1,
        b = tonumber(cfg.b) or 1,
        a = tonumber(cfg.a) or 1,
        size = size,
        font = tostring(cfg.font or ""),
        outline = tostring(cfg.outline or "OUTLINE"),
        x = x,
        y = y,
        shadow = cfg.shadow ~= false,
        shadowX = shadowX,
        shadowY = shadowY,
    }
end

function Store.IsNameplateNPCIDHidden()
    -- 强制隐藏，仅调试命令 /exb shownpcid on 可临时打开显示
    if ExBoss and ExBoss.Debug and ExBoss.Debug.ShowNameplateNPCID == true then
        return false
    end
    return true
end

function Store.UseTimelineScriptEvent()
    local db = Store.EnsureDB()
    return db.enabled ~= false and db.useTimelineScriptEvent ~= false
end
