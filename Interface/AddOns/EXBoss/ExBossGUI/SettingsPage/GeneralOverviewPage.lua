---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GeneralOverviewPage = ExBoss.UI.Panel.GeneralOverviewPage or {}
local Page = ExBoss.UI.Panel.GeneralOverviewPage

local MODULE_KEY = "ExBoss.GeneralOverview"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}
local ACTIVE_CONTENT_FRAME

local CHANNEL_OPTIONS = {
    { "Master",   "Master" },
    { "SFX",      "SFX" },
    { "Dialog",   "Dialog" },
    { "Music",    "Music" },
    { "Ambience", "Ambience" },
}

local BAR_MODE_OPTIONS = {
    { L["仅束状条"], "bun" },
    { L["两者都启用"], "both" },
    { L["仅计时条"], "timer" },
    { L["两者都隐藏"], "none" },
}

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
    if s == "" then
        return nil
    end
    return s
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

local function IsEncounterWarningsEnabled()
    local value = ReadCVarValue("encounterWarningsEnabled")
    if value == nil then
        WriteCVarValue("encounterWarningsEnabled", "1")
        return true
    end
    return value ~= "0"
end

local function IsEncounterTimelineEnabled()
    local value = ReadCVarValue("encounterTimelineEnabled")
    if value == nil then
        WriteCVarValue("encounterTimelineEnabled", "1")
        return true
    end
    return value ~= "0"
end

local function IsEncounterWarningSoundsEnabled()
    local value = ReadCVarValue("Sound_EnableEncounterWarningsSounds")
    if value == nil then
        return true
    end
    return value ~= "2"
end

local LAYOUT = {
    { key = "header_8111", type = "header", x = 1, y = 2, w = 63, h = 2, label = L["通用设置"], labelSize = 20 },
    { key = "barDisplayMode", type = "dropdown", x = 1, y = 6, w = 20, h = 2, label = L["时间轴样式选择"], items = BAR_MODE_OPTIONS, parentKey = "ui.general" },
    { key = "bossAlertsEnabledRaid", type = "checkbox", x = 1, y = 8, w = 24, h = 2, label = L["启用团本首领提示"], parentKey = "ui.general" },
    { key = "disableBlizzardEncounterTimeline", type = "checkbox", x = 1, y = 10, w = 24, h = 2, label = L["关闭暴雪原生计时条"], parentKey = "ui.general" },
    { key = "autoDisableCAAInBoss", type = "checkbox", x = 1, y = 12, w = 24, h = 2, label = L["首领战时自动关闭战斗音频预警"], parentKey = "ui.general" },
    { key = "hideTankBossAlertsForDps", type = "checkbox", x = 1, y = 14, w = 24, h = 2, label = L["DPS职责下不提示坦克技能"], parentKey = "ui.general" },
    { key = "hideTankBossAlertsForHeal", type = "checkbox", x = 1, y = 16, w = 24, h = 2, label = L["治疗职责下不提示坦克技能"], parentKey = "ui.general" },
    { key = "showSpellOccurrenceCount", type = "checkbox", x = 1, y = 18, w = 23, h = 2, label = L["法术名称显示次数"], parentKey = "ui.general" },
    { key = "encounterWarningsEnabled", type = "checkbox", x = 1, y = 20, w = 27, h = 2, label = L["开启暴雪中央文字预警（注意：如果关闭会导致语音不工作）"], parentKey = "ui.general" },
    { key = "encounterWarningSoundsEnabled", type = "checkbox", x = 1, y = 22, w = 40, h = 2, label = L["开启中央文字预警提示音（预设叮一声）"], parentKey = "ui.general" },
    { key = "enableBlizzardHintCountdown", type = "checkbox", x = 1, y = 24, w = 14, h = 2, label = L["暴雪时间轴模式启用5秒倒数"], parentKey = "ui.general" },
    { key = "enableBlizzardHintCountdown_desc", type = "description", x = 1, y = 27, w = 17, h = 2, label = L["(该设置只在团本生效,只能整体启用或是禁用,无法过滤)"], parentKey = "ui.general" },
    { key = "header_5292", type = "header", x = 1, y = 30, w = 62, h = 3, label = L["音频输出选项"], labelSize = 20 },
    { key = "channel", type = "dropdown", x = 1, y = 34, w = 15, h = 2, label = L["输出通道"], items = CHANNEL_OPTIONS, parentKey = "voice.global" },
    { key = "volume", type = "slider", x = 18, y = 34, w = 14, h = 2, label = L["全局音量"], min = 0, max = 1, step = 0.01, parentKey = "voice.global" },
    { key = "label_5567", type = "label", x = 1, y = 38, w = 30, h = 2, label = L["注意:声音大小请勿在此修改,若要调整声音大小请在ESC的设置面板修改"] },
    { key = "header_auto_gossip", type = "header", x = 1, y = 40, w = 62, h = 3, label = L["自动对话"], labelSize = 20 },
    { key = "autoGossipEnabled", type = "checkbox", x = 1, y = 42, w = 24, h = 2, label = L["启用自动对话"], parentKey = "autoGossip", subKey = "enabled" },
    { key = "autoGossipAcademyBuff", type = "checkbox", x = 1, y = 44, w = 32, h = 2, label = L["[大秘境] 自动对话学院(AA)BUFF"], parentKey = "autoGossip", subKey = "academyBuff" },
    { key = "autoGossipCaveCauldron", type = "checkbox", x = 1, y = 46, w = 32, h = 2, label = L["[大秘境] 自动对话洞窟(MC)大锅BUFF"], parentKey = "autoGossip", subKey = "caveCauldron" },
    { key = "autoGossipPosRescue", type = "checkbox", x = 1, y = 48, w = 32, h = 2, label = L["[大秘境] 自动对话萨隆矿坑救人(POS)"], parentKey = "autoGossip", subKey = "posRescue" },
    { key = "autoGossipNpxBuff", type = "checkbox", x = 1, y = 50, w = 32, h = 2, label = L["[大秘境] 自动对话节点(NPX)BUFF"], parentKey = "autoGossip", subKey = "npxBuff" },
}

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
end

local function EnsureRootDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.general = ExBossDB.ui.general or {}
    ExBossDB.voice = ExBossDB.voice or {}
    ExBossDB.voice.global = ExBossDB.voice.global or {}
    ExBossDB.autoGossip = ExBossDB.autoGossip or {}

    local general = ExBossDB.ui.general
    general.barDisplayMode = NormalizeBarDisplayMode(general.barDisplayMode)
    if general.bossAlertsEnabledMplus == nil then
        general.bossAlertsEnabledMplus = true
    else
        general.bossAlertsEnabledMplus = (general.bossAlertsEnabledMplus == true)
    end
    if general.bossAlertsEnabledRaid == nil then
        general.bossAlertsEnabledRaid = false
    else
        general.bossAlertsEnabledRaid = (general.bossAlertsEnabledRaid == true)
    end
    if general.autoDisableCAAInBoss == nil then
        general.autoDisableCAAInBoss = false
    else
        general.autoDisableCAAInBoss = (general.autoDisableCAAInBoss == true)
    end
    if general.hideTankBossAlertsForDps == nil then
        general.hideTankBossAlertsForDps = true
    else
        general.hideTankBossAlertsForDps = (general.hideTankBossAlertsForDps == true)
    end
    if general.hideTankBossAlertsForHeal == nil then
        general.hideTankBossAlertsForHeal = false
    else
        general.hideTankBossAlertsForHeal = (general.hideTankBossAlertsForHeal == true)
    end
    if general.showSpellOccurrenceCount == nil then
        general.showSpellOccurrenceCount = true
    else
        general.showSpellOccurrenceCount = (general.showSpellOccurrenceCount == true)
    end
    if general.enableBlizzardHintCountdown == nil then
        general.enableBlizzardHintCountdown = true
    else
        general.enableBlizzardHintCountdown = (general.enableBlizzardHintCountdown == true)
    end
    general.encounterWarningsEnabled = IsEncounterWarningsEnabled()
    general.encounterWarningSoundsEnabled = IsEncounterWarningSoundsEnabled()
    general.disableBlizzardEncounterTimeline = not IsEncounterTimelineEnabled()

    local voice = ExBossDB.voice.global
    voice.channel = tostring(voice.channel or "Master")
    voice.volume = tonumber(voice.volume) or 1.0
    if voice.volume < 0 then voice.volume = 0 end
    if voice.volume > 1 then voice.volume = 1 end

    local autoGossip = ExBossDB.autoGossip
    if autoGossip.enabled == nil then
        autoGossip.enabled = true
    else
        autoGossip.enabled = (autoGossip.enabled == true)
    end
    if autoGossip.academyBuff == nil then
        autoGossip.academyBuff = true
    else
        autoGossip.academyBuff = (autoGossip.academyBuff == true)
    end
    if autoGossip.caveCauldron == nil then
        autoGossip.caveCauldron = true
    else
        autoGossip.caveCauldron = (autoGossip.caveCauldron == true)
    end
    if autoGossip.posRescue == nil then
        autoGossip.posRescue = true
    else
        autoGossip.posRescue = (autoGossip.posRescue == true)
    end
    if autoGossip.npxBuff == nil then
        autoGossip.npxBuff = true
    else
        autoGossip.npxBuff = (autoGossip.npxBuff == true)
    end

    return ExBossDB
end

local function IsTimerBarEnabledByGlobal()
    local root = EnsureRootDB()
    local mode = NormalizeBarDisplayMode(root.ui.general.barDisplayMode)
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local root = EnsureRootDB()
    local mode = NormalizeBarDisplayMode(root.ui.general.barDisplayMode)
    return mode == "both" or mode == "bun"
end

local function ApplyBarModeChange()
    if not IsBunBarEnabledByGlobal() and ExBoss and ExBoss.UI and ExBoss.UI.BunBar and ExBoss.UI.BunBar.ReleaseAll then
        ExBoss.UI.BunBar:ReleaseAll()
    end
    if not IsTimerBarEnabledByGlobal() and ExBoss and ExBoss.UI and ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.ReleaseAll then
        ExBoss.UI.TimerBar:ReleaseAll()
    end

    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyVoiceOverrides()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local function ApplySpellCountDisplayChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyBlizzardHintCountdownChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyBossSceneToggleChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    local bossCfg = ExBoss and ExBoss.BossConfig
    local sceneEnabled = true
    if bossCfg and type(bossCfg.IsCurrentSceneEnabled) == "function" then
        local ok, enabled = pcall(bossCfg.IsCurrentSceneEnabled, bossCfg)
        if ok then
            sceneEnabled = (enabled ~= false)
        end
    end

    if sceneEnabled == false then
        if sched and sched.EndBoss then
            sched:EndBoss()
        end
        if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ClearEventOverridesInMemory then
            ExBoss.Voice.Engine:ClearEventOverridesInMemory("boss scene disabled")
        end
    elseif sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end

    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local function HasFlag(flags, bit)
    flags = tonumber(flags) or 0
    bit = tonumber(bit) or 0
    if flags <= 0 or bit <= 0 then
        return false
    end
    return math.floor(flags / bit) % 2 >= 1
end

local function GetEncounterDataSource()
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetEncounterDataRoot) == "function" then
        local ok, root = pcall(api.GetEncounterDataRoot)
        if ok and type(root) == "table" then
            return root
        end
    end
    local raw = _G.EXBOSS_ENCOUNTER_DATA
    if type(raw) == "table" and type(raw.maps) == "table" then
        return raw.maps
    end
    return raw
end

local _tankBossEventIDsByScene
local _tankBossEventIDsSource

local function GetSceneByMap(mapRow)
    local instanceType = tonumber(type(mapRow) == "table" and mapRow.instanceType or nil)
    if instanceType == 2 then
        return "raid"
    end
    local category = tostring(type(mapRow) == "table" and mapRow.category or "")
    if category:find("团") then
        return "raid"
    end
    return "mplus"
end

local _bossEventIDsByScene

local function GetBossEventIDsByScene(scene)
    local sceneKey = tostring(scene or ""):lower() == "raid" and "raid" or "mplus"
    local source = GetEncounterDataSource()
    if _bossEventIDsByScene and _tankBossEventIDsSource == source then
        return _bossEventIDsByScene[sceneKey] or {}
    end

    local out = {
        raid = {},
        mplus = {},
    }
    local seen = {
        raid = {},
        mplus = {},
    }

    for _, mapRow in pairs(source or {}) do
        if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
            local mapScene = GetSceneByMap(mapRow)
            for _, bossRow in pairs(mapRow.bosses) do
                if type(bossRow) == "table" and type(bossRow.events) == "table" then
                    for rawEventID, eventRow in pairs(bossRow.events) do
                        local eventID = tonumber(type(eventRow) == "table" and eventRow.eventID or nil) or
                            tonumber(rawEventID)
                        if eventID and not seen[mapScene][eventID] then
                            seen[mapScene][eventID] = true
                            out[mapScene][#out[mapScene] + 1] = eventID
                        end
                    end
                end
            end
        end
    end

    table.sort(out.raid)
    table.sort(out.mplus)
    _bossEventIDsByScene = out
    _tankBossEventIDsSource = source
    return out[sceneKey] or {}
end

local function IsTankSchemeColor(colorCfg)
    if type(colorCfg) ~= "table" then
        return false
    end
    local scheme = nil
    if colorCfg.useCustom == true then
        scheme = "__custom"
    else
        scheme = tostring(colorCfg.scheme or "")
    end
    local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes or nil
    if CS and type(CS.NormalizeSchemeKey) == "function" then
        scheme = CS.NormalizeSchemeKey(scheme)
    end
    return scheme == "tank"
end

local function IsTankBossEventForSlot(cfg, eventID, slotKey)
    local source = GetEncounterDataSource()
    local rawFlags = 0
    for _, mapRow in pairs(source or {}) do
        if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
            for _, bossRow in pairs(mapRow.bosses) do
                if type(bossRow) == "table" and type(bossRow.events) == "table" then
                    local eventRow = bossRow.events[eventID]
                    if type(eventRow) == "table" then
                        rawFlags = tonumber(eventRow.iconFlags or eventRow.icons) or 0
                        break
                    end
                end
            end
        end
        if rawFlags > 0 then
            break
        end
    end
    if HasFlag(rawFlags, 128) then
        return true, "iconFlags"
    end

    local resolved = cfg:GetResolvedEventConfig(eventID, slotKey)
    if type(resolved) == "table" and IsTankSchemeColor(resolved.color) then
        return true, "colorScheme"
    end
    return false, "none"
end

local function ApplyTankBossSkillToggleForRole(roleKey, suppress)
    local normalizedRole = tostring(roleKey or ""):lower()
    if normalizedRole ~= "dps" and normalizedRole ~= "heal" then
        return 0
    end

    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.GetResolvedEventConfig) == "function" and type(cfg.GetOverrideRootForSlot) == "function" and type(cfg.CompactEventOverride) == "function") then
        return 0
    end

    local changed = 0
    for _, scene in ipairs({ "raid", "mplus" }) do
        local slotKey = string.format("%s_%s", scene, normalizedRole)
        local root, _, authorKey = cfg:GetOverrideRootForSlot(slotKey, true)
        local eventIDs = GetBossEventIDsByScene(scene)
        if type(root) == "table" then
            for _, eventID in ipairs(eventIDs) do
                local resolved = cfg:GetResolvedEventConfig(eventID, slotKey)
                local isTank, reason = IsTankBossEventForSlot(cfg, eventID, slotKey)
                if isTank then
                    local row = type(root[eventID]) == "table" and root[eventID] or {}
                    row.enabled = (suppress ~= true)
                    root[eventID] = row
                    cfg:CompactEventOverride(eventID, slotKey)
                    changed = changed + 1
                end
            end
        end
    end

    if changed > 0 then
        cfg:PublishRuntimeSelection()
        ApplyVoiceOverrides()
        local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
        if sched and sched._running and sched.StartBoss and sched._encounterID then
            sched:StartBoss(sched._encounterID)
        end
    end

    return changed
end

ExBoss.ApplyTankBossSkillToggleForRole = ApplyTankBossSkillToggleForRole

local function ConfirmEnableRaidBossAlerts()
    local popupID = "EXBOSS_ENABLE_RAID_BOSS_ALERTS_CONFIRM"
    if not StaticPopupDialogs[popupID] then
        StaticPopupDialogs[popupID] = {
            text = L["团本配置尚未完工，确认启用？"],
            button1 = L["确定"],
            button2 = L["取消"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                EnsureRootDB().ui.general.bossAlertsEnabledRaid = true
                ApplyBossSceneToggleChange()
                if Page and ACTIVE_CONTENT_FRAME and ACTIVE_CONTENT_FRAME:IsShown() then
                    Page:Render(ACTIVE_CONTENT_FRAME)
                end
            end,
            OnCancel = function()
                EnsureRootDB().ui.general.bossAlertsEnabledRaid = false
                if Page and ACTIVE_CONTENT_FRAME and ACTIVE_CONTENT_FRAME:IsShown() then
                    Page:Render(ACTIVE_CONTENT_FRAME)
                end
            end,
        }
    end
    StaticPopup_Show(popupID)
end

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then
        return BASE_GRID_COLS
    end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < MIN_GRID_COLS then cols = MIN_GRID_COLS end
    if cols > MAX_GRID_COLS then cols = MAX_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then
        return LAYOUT
    end
    local cached = LAYOUT_CACHE[toCols]
    if cached then
        return cached
    end

    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then
                    row[k] = v
                end
            end
            if type(item.x) == "number" and type(item.w) == "number" then
                local nx = math.floor(((item.x - 1) * scale) + 1 + 0.5)
                local nw = math.max(1, math.floor(item.w * scale + 0.5))
                if nx < 1 then nx = 1 end
                if nx > toCols then nx = toCols end
                if nx + nw - 1 > toCols then
                    nw = math.max(1, toCols - nx + 1)
                end
                row.x = nx
                row.w = nw
            end
            if type(item.children) == "table" then
                row.children = ScaleItems(item.children)
            end
            out[#out + 1] = row
        end
        return out
    end

    cached = ScaleItems(items)
    LAYOUT_CACHE[toCols] = cached
    return cached
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    local fullPath = tostring(info.fullPath or "")
    if fullPath:find("^ui%.general%.") then
        if fullPath == "ui.general.bossAlertsEnabledRaid" and info.value == true then
            local g = EnsureRootDB().ui.general
            if g._raidBossAlertsConfirming ~= true then
                g._raidBossAlertsConfirming = true
                g.bossAlertsEnabledRaid = false
                C_Timer.After(0, function()
                    local current = EnsureRootDB().ui.general
                    current._raidBossAlertsConfirming = nil
                    ConfirmEnableRaidBossAlerts()
                end)
                return
            end
        end
        if fullPath == "ui.general.encounterWarningsEnabled" then
            WriteCVarValue("encounterWarningsEnabled", (info.value == true) and "1" or "0")
        elseif fullPath == "ui.general.encounterWarningSoundsEnabled" then
            WriteCVarValue("Sound_EnableEncounterWarningsSounds", (info.value == true) and "1" or "2")
        elseif fullPath == "ui.general.disableBlizzardEncounterTimeline" then
            WriteCVarValue("encounterTimelineEnabled", (info.value == true) and "0" or "1")
        elseif fullPath == "ui.general.showSpellOccurrenceCount" then
            ApplySpellCountDisplayChange()
        elseif fullPath == "ui.general.enableBlizzardHintCountdown" then
            ApplyBlizzardHintCountdownChange()
        elseif fullPath == "ui.general.hideTankBossAlertsForDps" then
            ApplyTankBossSkillToggleForRole("dps", info.value == true)
        elseif fullPath == "ui.general.hideTankBossAlertsForHeal" then
            ApplyTankBossSkillToggleForRole("heal", info.value == true)
        end
        ApplyBarModeChange()
        if fullPath == "ui.general.bossAlertsEnabledMplus" or fullPath == "ui.general.bossAlertsEnabledRaid" then
            ApplyBossSceneToggleChange()
        end
        if fullPath == "ui.general.autoDisableCAAInBoss" and ExBoss and ExBoss.ApplyBossAutoCAASetting then
            ExBoss.ApplyBossAutoCAASetting()
        end
    elseif fullPath:find("^autoGossip%.") then
        local mod = ExBoss and ExBoss.AutoGossip
        if mod and type(mod.NotifySettingsChanged) == "function" then
            mod.NotifySettingsChanged()
        end
    elseif fullPath:find("^voice%.global%.") then
        ApplyVoiceOverrides()
    end
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid or not contentFrame then
        return
    end

    ACTIVE_CONTENT_FRAME = contentFrame

    local rootDB = EnsureRootDB()
    local general = rootDB.ui and rootDB.ui.general or nil
    if type(general) == "table" and general._bossTankSkillToggleInitApplied ~= true then
        general._bossTankSkillToggleInitApplied = true
        ApplyTankBossSkillToggleForRole("dps", general.hideTankBossAlertsForDps == true)
        ApplyTankBossSkillToggleForRole("heal", general.hideTankBossAlertsForHeal == true)
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_GeneralOverviewScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end

        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)

        Page._scrollFrame = sf
        Page._scrollChild = sc
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if not sf:IsShown() then return end
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end
        sc:SetWidth(w - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = sc
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        local cols = ResolveGridCols(sc:GetWidth())
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), rootDB, MODULE_KEY)
    end)
end
