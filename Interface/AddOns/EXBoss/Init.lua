---@diagnostic disable: undefined-global
-- =============================================================
-- Init.lua — 启动序列（最后加载）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then
    --     print("|cffff4400ExBoss|r [Init] ExwindTools 不可用，插件停止")
    return
end

-- print("|cffff4400Ex|r|cff00ccffBoss|r [2/3] Init.lua 加载完成")
ExBoss._initLoaded = true

-- 全局输入框扁平化：GridInput 首次创建时读取此值
if ExwindTools.UI then
    ExwindTools.UI.TooltipBackdrop = {
        bgFile  = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets  = { left = 1, right = 1, top = 1, bottom = 1 },
    }
end

local _autoCAAWasForced = false
local _autoCAAPrevValue = nil
local _autoCAAVolumeMuted = false
local _autoCAAPrevVolumes = {}
local _autoCAACurrentEncounterID = nil
local CAA_DEBUG_LOG = false

local function CAADebug(msg)
    if not CAA_DEBUG_LOG then return end
    --     print("|cffff8800ExBoss CAA|r " .. tostring(msg or ""))
end

local function EnsureGeneralDB()
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
    if g.autoDisableCAAInBoss == nil then
        g.autoDisableCAAInBoss = false
    else
        g.autoDisableCAAInBoss = (g.autoDisableCAAInBoss == true)
    end
    return g
end

local function IsFixedTimelineEncounterForCAA(encounterID)
    local id = tonumber(encounterID)
    local fixed = _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS
    if type(fixed) ~= "table" then
        return false, "no fixed table"
    end
    if id and fixed[id] == true then
        return true, "fixed=true(id)"
    end
    if encounterID ~= nil and fixed[encounterID] == true then
        return true, "fixed=true(raw)"
    end
    return false, "fixed=false"
end

local function ReadCAAEnabled()
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, "CAAEnabled")
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, "CAAEnabled")
    end
    if not ok then return nil end
    if value == nil then return nil end
    local s = tostring(value)
    if s == "" then return nil end
    return s
end

local function WriteCAAEnabled(value)
    local s = tostring(value or "")
    if s == "" then return false end
    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, "CAAEnabled", s)
        if ok then
            CAADebug("fallback SetCVar CAAEnabled=" .. s .. " via C_CVar.SetCVar")
            return true
        end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, "CAAEnabled", s)
        if ok then
            CAADebug("fallback SetCVar CAAEnabled=" .. s .. " via SetCVar")
            return true
        end
    end
    CAADebug("fallback SetCVar CAAEnabled failed: " .. s)
    return false
end

local function ReadGenericCVar(name)
    local key = tostring(name or "")
    if key == "" then return nil end
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, key)
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, key)
    end
    if not ok or value == nil then return nil end
    local s = tostring(value)
    if s == "" then return nil end
    return s
end

local function WriteGenericCVar(name, value)
    local key = tostring(name or "")
    local s = tostring(value or "")
    if key == "" or s == "" then return false end
    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, key, s)
        if ok then return true end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, key, s)
        if ok then return true end
    end
    return false
end


-- 监听CVAR 强制开启或是关闭 encounterWarningsEnabled 和 encounterTimelineEnabled，防止 DBM 或其他插件修改它们导致计时引擎异常
local PROTECTED_ENCOUNTER_CVARS = {
    encounterWarningsEnabled = true,
    encounterTimelineEnabled = true,
}

local function ApplySoundNumChannels128()
    local current = ReadGenericCVar("Sound_NumChannels")
    if current ~= "128" then
        WriteGenericCVar("Sound_NumChannels", "128")
    end
end

local function GetDesiredEncounterCVarValue(name)
    local key = tostring(name or "")
    local g = EnsureGeneralDB()
    if key == "encounterWarningsEnabled" then
        return (g.encounterWarningsEnabled ~= false) and "1" or "0"
    end
    if key == "encounterTimelineEnabled" then
        return (g.disableBlizzardEncounterTimeline == true) and "0" or "1"
    end
    return nil
end

local function ApplyProtectedEncounterCVar(name)
    local key = tostring(name or "")
    if not PROTECTED_ENCOUNTER_CVARS[key] then
        return
    end
    local desired = GetDesiredEncounterCVarValue(key)
    if not desired then
        return
    end
    local current = ReadGenericCVar(key)
    if current ~= desired then
        WriteGenericCVar(key, desired)
    end
end

local function ScheduleProtectedEncounterCVarRepair(name)
    local key = tostring(name or "")
    if not PROTECTED_ENCOUNTER_CVARS[key] then
        return
    end
    C_Timer.After(0.1, function()
        ApplyProtectedEncounterCVar(key)
    end)
    C_Timer.After(0.5, function()
        ApplyProtectedEncounterCVar(key)
    end)
end

local function ScheduleAllProtectedEncounterCVarRepairs()
    ScheduleProtectedEncounterCVarRepair("encounterWarningsEnabled")
    ScheduleProtectedEncounterCVarRepair("encounterTimelineEnabled")
end

local function GetCAACategoryRange()
    local minValue, maxValue = 0, 8
    local meta = Enum and Enum.CombatAudioAlertCategoryMeta
    if type(meta) == "table" then
        minValue = tonumber(meta.MinValue) or minValue
        maxValue = tonumber(meta.MaxValue) or maxValue
    end
    return minValue, maxValue
end

local function CanUseCAAApi()
    local ok = C_CombatAudioAlert
        and type(C_CombatAudioAlert.GetCategoryVolume) == "function"
        and type(C_CombatAudioAlert.SetCategoryVolume) == "function"
    if not ok then
        CAADebug("C_CombatAudioAlert API unavailable")
    end
    return ok
end

local function MuteCAAByCategoryVolumes()
    if _autoCAAVolumeMuted then
        return true
    end
    if not CanUseCAAApi() then
        return false
    end

    wipe(_autoCAAPrevVolumes)
    local minValue, maxValue = GetCAACategoryRange()
    CAADebug(string.format("Mute categories range: %d..%d", minValue, maxValue))
    local setOK = 0
    local setFail = 0
    for category = minValue, maxValue do
        local okGet, vol = pcall(C_CombatAudioAlert.GetCategoryVolume, category)
        if okGet and tonumber(vol) ~= nil then
            _autoCAAPrevVolumes[category] = tonumber(vol)
        else
            CAADebug(string.format("GetCategoryVolume failed c=%d ok=%s vol=%s", category, tostring(okGet), tostring(vol)))
        end
        local okSet, success = pcall(C_CombatAudioAlert.SetCategoryVolume, category, 0)
        if okSet and success ~= false then
            setOK = setOK + 1
        else
            setFail = setFail + 1
            CAADebug(string.format("SetCategoryVolume(0) failed c=%d ok=%s ret=%s", category, tostring(okSet),
                tostring(success)))
        end
    end
    _autoCAAVolumeMuted = true
    CAADebug(string.format("Mute done: success=%d fail=%d", setOK, setFail))
    return true
end

local function RestoreCAAByCategoryVolumes()
    if not _autoCAAVolumeMuted then
        return true
    end
    if not CanUseCAAApi() then
        return false
    end

    local minValue, maxValue = GetCAACategoryRange()
    CAADebug(string.format("Restore categories range: %d..%d", minValue, maxValue))
    local setOK = 0
    local setFail = 0
    for category = minValue, maxValue do
        local restoreVol = tonumber(_autoCAAPrevVolumes[category])
        if restoreVol == nil then
            local okGet, currentVol = pcall(C_CombatAudioAlert.GetCategoryVolume, category)
            if okGet and tonumber(currentVol) ~= nil then
                restoreVol = tonumber(currentVol)
            else
                restoreVol = 100
            end
        end
        local okSet, success = pcall(C_CombatAudioAlert.SetCategoryVolume, category, restoreVol)
        if okSet and success ~= false then
            setOK = setOK + 1
        else
            setFail = setFail + 1
            CAADebug(string.format("Restore volume failed c=%d v=%s ok=%s ret=%s", category, tostring(restoreVol),
                tostring(okSet), tostring(success)))
        end
    end
    wipe(_autoCAAPrevVolumes)
    _autoCAAVolumeMuted = false
    CAADebug(string.format("Restore done: success=%d fail=%d", setOK, setFail))
    return true
end

function ExBoss.ApplyBossAutoCAASetting(forceIsBossEncounter)
    local g = EnsureGeneralDB()
    local enabled = (g.autoDisableCAAInBoss == true)
    local isBoss = (forceIsBossEncounter == true)
    if forceIsBossEncounter == nil and ExwindTools and ExwindTools.State then
        isBoss = (ExwindTools.State.IsBossEncounter == true)
    end
    local shouldMuteBecauseFixed = false
    local muteReason = "n/a"
    if isBoss then
        shouldMuteBecauseFixed, muteReason = IsFixedTimelineEncounterForCAA(_autoCAACurrentEncounterID)
    end
    CAADebug(string.format(
        "Apply: enabled=%s isBoss=%s encounter=%s shouldMute=%s reason=%s muted=%s forced=%s prevCAA=%s",
        tostring(enabled), tostring(isBoss), tostring(_autoCAACurrentEncounterID), tostring(shouldMuteBecauseFixed),
        tostring(muteReason),
        tostring(_autoCAAVolumeMuted), tostring(_autoCAAWasForced), tostring(_autoCAAPrevValue)
    ))

    if not enabled then
        if _autoCAAVolumeMuted then
            CAADebug("Apply -> disabled path: restoring muted categories")
            RestoreCAAByCategoryVolumes()
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        elseif _autoCAAWasForced then
            CAADebug("Apply -> disabled path: restoring CAAEnabled fallback")
            WriteCAAEnabled(_autoCAAPrevValue or "1")
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        end
        return
    end

    if isBoss and not shouldMuteBecauseFixed then
        CAADebug("Apply -> boss path: current encounter is not fixed-timeline, skip CAA mute")
        if _autoCAAVolumeMuted then
            RestoreCAAByCategoryVolumes()
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        elseif _autoCAAWasForced then
            WriteCAAEnabled(_autoCAAPrevValue or "1")
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        end
        return
    end

    if isBoss then
        CAADebug("Apply -> boss path: try mute categories")
        local muted = MuteCAAByCategoryVolumes()
        if muted then
            _autoCAAWasForced = true
            CAADebug("Apply -> boss path: category mute success")
            return
        end
        if not _autoCAAWasForced then
            _autoCAAPrevValue = ReadCAAEnabled()
            CAADebug("Apply -> boss path: fallback remember CAAEnabled=" .. tostring(_autoCAAPrevValue))
        end
        WriteCAAEnabled("0")
        _autoCAAWasForced = true
    else
        if _autoCAAVolumeMuted then
            CAADebug("Apply -> leave boss path: restore categories")
            RestoreCAAByCategoryVolumes()
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        elseif _autoCAAWasForced then
            CAADebug("Apply -> leave boss path: restore CAAEnabled fallback")
            WriteCAAEnabled(_autoCAAPrevValue or "1")
            _autoCAAWasForced = false
            _autoCAAPrevValue = nil
        end
    end
end

if ExwindTools and ExwindTools.WatchState then
    ExwindTools:WatchState("IsBossEncounter", "ExBoss_AutoCAA_Toggle", function(newValue)
        CAADebug("WatchState IsBossEncounter -> " .. tostring(newValue))
        if ExBoss and ExBoss.ApplyBossAutoCAASetting then
            ExBoss.ApplyBossAutoCAASetting(newValue == true)
        end
    end)
    C_Timer.After(0.2, function()
        if ExBoss and ExBoss.ApplyBossAutoCAASetting then
            ExBoss.ApplyBossAutoCAASetting()
        end
    end)
end

-- ── ADDON_LOADED：初始化 DB ───────────────────────────────────
ExwindTools:RegisterEvent("ADDON_LOADED", "ExBoss_Init_Loaded", function(event, addonName)
    local name = tostring(addonName or ""):lower()
    if name ~= "exboss" then return end

    if ExBoss.DB and ExBoss.DB.Init then
        ExBoss.DB:Init()
    end

    -- ExBossDB is now loaded; re-apply the saved locale mode so _currentLocale
    -- reflects the user's choice instead of the load-time default.
    if type(ExBossDB) == "table" and type(ExBossDB.locale) == "table" then
        ExBoss:SetLocaleMode(ExBossDB.locale.mode)
    end

    if ReadGenericCVar("encounterWarningsEnabled") == nil then
        WriteGenericCVar("encounterWarningsEnabled", "1")
    end
    if ReadGenericCVar("encounterTimelineEnabled") == nil then
        WriteGenericCVar("encounterTimelineEnabled", "1")
    end
    ApplySoundNumChannels128()
    ScheduleAllProtectedEncounterCVarRepairs()
    C_Timer.After(0.1, ApplySoundNumChannels128)
    C_Timer.After(1.0, ApplySoundNumChannels128)

    -- ── 清理旧字段（一次性，无兼容意义）────────────────────────
    if type(EXBossDataDB) == "table" then
        EXBossDataDB.events = EXBossDataDB.events or {}
        EXBossDataDB.voice = nil
        EXBossDataDB.timer = EXBossDataDB.timer or {}
        EXBossDataDB.timer.skillOverrides = nil
    end

    if type(ExBossDB) == "table" and type(ExBossDB.voice) == "table" then
        local v                      = ExBossDB.voice
        v.events                     = nil
        v.profileBindings            = nil
        v.profileDefaults            = nil
        v.profileDefaultsByScene     = nil
        v.specProfileBindingsByScene = nil
        v._liveEvents                = nil
        -- 清理 profile 对象内残留的旧 global 字段
        if type(v.profiles) == "table" then
            for _, p in pairs(v.profiles) do
                if type(p) == "table" then
                    p.global = nil
                end
            end
        end
    end

    -- 把 S12_MechanicMap 的 castTime 填入 SpellInference.mappings
    local mecMap = _G.EXBOSS_S12_MECHANIC_MAP
    local infer = ExBossDB and ExBossDB.timer and ExBossDB.timer.spellInference
    if type(mecMap) == "table" and type(infer) == "table" then
        infer.mappings = infer.mappings or {}
        for encounterID, boss in pairs(mecMap) do
            if type(boss.mechanics) == "table" then
                infer.mappings[encounterID] = infer.mappings[encounterID] or {}
                local existing = {}
                for _, m in ipairs(infer.mappings[encounterID]) do
                    if m.spellID then existing[m.spellID] = true end
                end
                for _, mech in ipairs(boss.mechanics) do
                    local castTime = tonumber(mech.castTime)
                    if castTime and castTime > 0 then
                        for _, spellID in ipairs(mech.fixedSpellIDs or {}) do
                            if not existing[spellID] then
                                table.insert(infer.mappings[encounterID], {
                                    spellID  = spellID,
                                    castTime = castTime,
                                })
                                existing[spellID] = true
                            end
                        end
                    end
                end
            end
        end
        --         print("|cffff4400Ex|r|cff00ccffBoss|r MechanicMap → SpellInference.mappings 已填入")
    end
end)

ExwindTools:RegisterEvent("CVAR_UPDATE", "ExBoss_EncounterCVarGuard", function(event, cvarName)
    local key = tostring(cvarName or "")
    if PROTECTED_ENCOUNTER_CVARS[key] then
        ScheduleProtectedEncounterCVarRepair(key)
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_EncounterCVarGuardPEW", function()
    ScheduleAllProtectedEncounterCVarRepairs()
    ApplySoundNumChannels128()
    C_Timer.After(0.5, ApplySoundNumChannels128)
end)

ExwindTools:RegisterEvent("ADDON_LOADED", "ExBoss_EncounterCVarGuardDBM", function(event, addonName)
    local name = tostring(addonName or ""):lower()
    if name == "dbm-core" or name == "dbm-gui" then
        ScheduleAllProtectedEncounterCVarRepairs()
    end
end)

-- ── ENCOUNTER_START：启动计时引擎 ────────────────────────────
ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Init_EncStart", function(_, encounterID)
    _autoCAACurrentEncounterID = tonumber(encounterID) or encounterID
    if ExBoss and ExBoss.ApplyBossAutoCAASetting then
        ExBoss.ApplyBossAutoCAASetting(true)
    end
    if ExBoss.Timeline and ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.HandleEncounterStart then
        ExBoss.Timeline.Scheduler:HandleEncounterStart(encounterID, "exwind")
        return
    end
    if ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.StartBoss then
        ExBoss.Timeline.Scheduler:StartBoss(encounterID)
    end
end)

-- ── ENCOUNTER_END：停止计时引擎 ──────────────────────────────
ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Init_EncEnd", function()
    _autoCAACurrentEncounterID = nil
    if ExBoss and ExBoss.ApplyBossAutoCAASetting then
        ExBoss.ApplyBossAutoCAASetting(false)
    end
    if ExBoss.Timeline and ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.HandleEncounterEnd then
        ExBoss.Timeline.Scheduler:HandleEncounterEnd("exwind")
        return
    end
    if ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.EndBoss then
        ExBoss.Timeline.Scheduler:EndBoss()
    end
end)
