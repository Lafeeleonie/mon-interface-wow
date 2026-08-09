---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.Panel.GlobalSettingsPage = ExBoss.UI.Panel.GlobalSettingsPage or {}
local Page = ExBoss.UI.Panel.GlobalSettingsPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local leftRoot
local embeddedHostFrame
local rightScrollFrame
local rightRoot
local listScroll
local listChild
local titleText
local titleSep
local descText
local overviewSection
local barModeDropdown
local bossAlertsEnabledMplusCheck
local bossAlertsEnabledRaidCheck
local autoDisableCAAInBossCheck
local encounterWarningsEnabledCheck
local encounterTimelineDisabledCheck
local voiceSection
local voiceRegisterSection
local voiceChannelDrop
local voiceVolumeSlider
local voiceRegisterSummary
local voiceRegisterTime
local voiceRegisterListScroll
local voiceRegisterListChild
local voiceRegisterListText
local colorSection
local trashCDSection
local trashHideLongCheck
local trashHideLongInput
local trashKeepReadyCheck
local trashKeepReadyInput
local trashNameplateSideDropdown
local trashNameplateStrataDropdown
local trashNameplateIconGroup
local trashNameplateTextFontGroup
local trashNameplatePreview
local trashNameplatePreviewIcons = {}
local partyFrameGlow = {}
local dungeonExtra = {}
local dungeonExtraTrashMaxBarsSlider
local dungeonExtraTrashGapSlider
local embedPlaceholder
local activeButtons = {}
local buttonPool = {}
local headerPool = {}
local selectedIndex = 1
local categoryExpanded = {
    general = true,
    display = true,
    trash = true,
    tools = true,
    other = true,
}
local searchBox
local searchText = ""
local sidebarDivider

local fixedColorButtons = {}
local fixedColorLabels = {}
local customNameInput
local customColorButton
local extraCustomEnableChecks = {}
local extraCustomNameInputs = {}
local extraCustomColorButtons = {}
local resetSection

local TRASH248690_STYLE_DEFAULTS = {
    timerBarGroup = {
        width = 260,
        height = 28,
        texture = "Melli",
        barColorR = 0.1,
        barColorG = 0.8,
        barColorB = 1.0,
        barColorA = 1,
        barBgColorR = 0,
        barBgColorG = 0,
        barBgColorB = 0,
        barBgColorA = 0.5,
        showBorder = true,
        borderTexture = "Square Full White",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 1,
        borderPadding = 0,
        showIcon = true,
        iconSide = "LEFT",
        iconSize = 28,
        iconOffsetX = -1,
        iconOffsetY = 0,
        showIconBorder = true,
        iconBorderTexture = "Square Full White",
        iconBorderColorR = 0,
        iconBorderColorG = 0,
        iconBorderColorB = 0,
        iconBorderColorA = 1,
        iconBorderSize = 1,
        iconBorderPadding = 0,
    },
    font_percent = {
        font = "Friz Quadrata TT",
        size = 14,
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        x = -4,
        y = 0,
        enabled = true,
    },
}

local ResetDisplayStylesOnly
local ResetTrashCDSettingsOnly
local ResetAllConfigExceptAppearance
local ResetAllConfigIncludingAppearance

local function DeepApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            DeepApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function DeepCopyInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            DeepCopyInto(dst[k], v)
        else
            dst[k] = v
        end
    end
end

-- titleKey/descKey are locale keys resolved at render time via GetTitle/GetDesc,
-- avoiding the load-time capture bug where L["..."] would always return zhCN
-- because ExBossDB (and the saved locale mode) is not yet available at file load.
local ITEMS = {
    { key = "overview",           category = "general", titleKey = "通用设置",         descKey = "全局显示模式与语音输出。",                                                                                                          mode = "embedded", moduleKey = "ExBoss.GeneralOverview" },
    { key = "countdownvoice",     category = "general", titleKey = "倒数语音",          descKey = "技能数字倒数语音、名称提前秒数与单数字试听。",                                                                                         mode = "embedded", moduleKey = "ExBoss.CountdownVoiceSettings" },
    { key = "batchedit",          category = "general", titleKey = "批量修改",          descKey = "批量启用/禁用事件功能，并真实写入 override。",                                                                                        mode = "embedded", moduleKey = "ExBoss.BatchEdit" },
    { key = "color",              category = "general", titleKey = "通用颜色方案",      descKey = "4个固定颜色方案 + 1个自定义方案 + 最多3个额外方案。Boss技能页可直接选择方案或自定义颜色。",                                             mode = "builtin",  moduleKey = "ExBoss.GeneralColor" },
    { key = "conditions",         category = "general", titleKey = "条件系统",          descKey = "固定轴/AI轴 IF/THEN 条件触发规则。",                                                                                                 mode = "embedded", moduleKey = "ExBoss.Conditions.RuleEditor" },
    { key = "privateauramonitor", category = "general", titleKey = "私人光环监控",      descKey = "监控玩家自身的3个私人光环槽位，支持图标大小、位置、倒计时、音效等配置。",                                                             mode = "embedded", moduleKey = "ExBoss.PrivateAuraMonitor" },
    { key = "timerbar",           category = "display", titleKey = "计时条",            descKey = "计时条外观、文字、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.TimerBar" },
    { key = "bunbar",             category = "display", titleKey = "束状条",            descKey = "束状条外观、轨道、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.BunBar" },
    { key = "countdown",          category = "display", titleKey = "[文本]5秒倒数",     descKey = "中央倒数文字与字体、位置。",                                                                                                         mode = "embedded", moduleKey = "ExBoss.Countdown" },
    { key = "flashtext",          category = "display", titleKey = "[文本]文字公告(大)", descKey = "中央文字公告样式与位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.FlashText" },
    { key = "flashtextmedium",    category = "display", titleKey = "[文本]文字公告(中)", descKey = "中等尺寸中央提示，供血量转阶段、易伤、站位等功能模块复用。",                                                                         mode = "embedded", moduleKey = "ExBoss.FlashTextMedium" },
    { key = "ringprogress",       category = "display", titleKey = "中央圆环",          descKey = "屏幕中央圆环进度样式、大小、位置。",                                                                                                 mode = "embedded", moduleKey = "ExBoss.RingProgress" },
    { key = "iconalert",          category = "display", titleKey = "图标",              descKey = "通用图标容器，支持 API 推入、可选发光与多图标四向增长。",                                                                             mode = "embedded", moduleKey = "ExBoss.IconAlert" },
    { key = "castprogressbar",    category = "display", titleKey = "施法进度条",        descKey = "与中央圆环同源的施法/引导进度条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.CastProgressBar" },
    { key = "extrashieldbar",     category = "display", titleKey = "额外护盾条",        descKey = "供首领/副本额外功能复用的单体护盾监控条。",                                                                                           mode = "embedded", moduleKey = "ExBoss.ExtraShieldBar" },
    { key = "partyframeglow",     category = "display", titleKey = "团队框架发光",      descKey = "通用队伍/团队框架发光样式与预览。",                                                                                                   mode = "builtin"  },
    { key = "trashcd",            category = "trash",   titleKey = "小怪CD",            descKey = "小怪内置CD的全局计时条规则。",                                                                                                       mode = "embedded", moduleKey  = "ExBoss.TrashCD.Settings" },
    { key = "dungeonextra",       category = "trash",   titleKey = "副本额外功能",      descKey = "特定副本/首领的额外辅助模块。",                                                                                                       mode = "embedded", moduleKey = "ExBoss.DungeonExtra" },
    { key = "voiceregister",      category = "other",   titleKey = "语音注册监控",      descKey = "查看当前语音注册细节（默认仅显示非团本）：副本 > BOSS名称(数量) + eventID(trigger0/1/2)。",                                          mode = "builtin"  },
    { key = "reset",              category = "other",   titleKey = "重置设置",          descKey = "提供四种重置方式：\n1) 仅重置外观设置\n2) 仅重置小怪内置CD设置\n3) 重置所有配置（不包含外观）\n4) 清除全部设置（包含外观）",           mode = "builtin"  },
}

local CATEGORIES = {
    { key = "general", titleKey = "通用" },
    { key = "display", titleKey = "显示" },
    { key = "trash",   titleKey = "小怪" },
    { key = "other",   titleKey = "其他" },
}

function Page:GetExportModuleKeys()
    local out = {}
    local seen = {}
    local function add(key)
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    for _, item in ipairs(ITEMS) do
        add(item.moduleKey)
        if type(item.moduleKeys) == "table" then
            for _, key in ipairs(item.moduleKeys) do
                add(key)
            end
        end
    end
    return out
end

local function GetTitle(t) return L[t.titleKey or ""] end
local function GetDesc(t)  return L[t.descKey  or ""] end

local function FindItemIndexByKey(key)
    for i, item in ipairs(ITEMS) do
        if item.key == key then
            return i
        end
    end
    return nil
end

local function EnsureSelectedCategoryExpanded()
    local item = ITEMS[selectedIndex]
    if item and item.category then
        categoryExpanded[item.category] = true
    end
end

local CHANNEL_OPTIONS = {
    { "Master", "Master" },
    { "SFX", "SFX" },
    { "Dialog", "Dialog" },
    { "Music", "Music" },
    { "Ambience", "Ambience" },
}

local function GetBarModeOptions()
    return {
        { L["仅束状条"],   "bun"  },
        { L["两者都启用"], "both" },
        { L["仅计时条"],   "timer"},
        { L["两者都隐藏"], "none" },
    }
end

local function GetTrashNameplateSideOptions()
    return {
        { L["向右增长"], "right" },
        { L["向左增长"], "left"  },
    }
end

local function GetTrashNameplateStrataOptions()
    return {
        { L["背景"],     "BACKGROUND"       },
        { L["低"],       "LOW"              },
        { L["中"],       "MEDIUM"           },
        { L["高"],       "HIGH"             },
        { L["对话"],     "DIALOG"           },
        { L["全屏"],     "FULLSCREEN"       },
        { L["全屏对话"], "FULLSCREEN_DIALOG" },
        { L["提示"],     "TOOLTIP"          },
    }
end

local FALLBACK_SCHEME_ORDER = { "tank", "heal", "cooldown", "mechanic" }
local FALLBACK_SCHEME_KEYS = {
    tank     = "坦克方案",
    heal     = "治疗方案",
    cooldown = "减伤方案",
    mechanic = "机制方案",
}
local function GetFallbackSchemeName(key)
    local k = FALLBACK_SCHEME_KEYS[key]
    return k and L[k] or tostring(key or "")
end
local EXTRA_CUSTOM_COUNT_FALLBACK = 3
local EnsureColorDB
local GetSchemeOrder
local GetSchemeDisplayName
local GetExtraCustomCount
local ApplyVoiceOverrides
local RefreshColorControls

local function TrimOptionalText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetColorModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function EnsureVoiceDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.voice = ExBossDB.voice or {}
    ExBossDB.voice.global = ExBossDB.voice.global or {}

    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        CS.EnsureDB()
    end

    local g = ExBossDB.voice.global
    g.channel = g.channel or "Master"
    g.volume = tonumber(g.volume) or 1.0
    return g
end

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
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
        g.bossAlertsEnabledRaid = false
    else
        g.bossAlertsEnabledRaid = (g.bossAlertsEnabledRaid == true)
    end
    g.barDisplayMode = NormalizeBarDisplayMode(g.barDisplayMode)
    if g.autoDisableCAAInBoss == nil then
        g.autoDisableCAAInBoss = false
    else
        g.autoDisableCAAInBoss = (g.autoDisableCAAInBoss == true)
    end
    if g.hideTankBossAlertsForDps == nil then
        g.hideTankBossAlertsForDps = true
    else
        g.hideTankBossAlertsForDps = (g.hideTankBossAlertsForDps == true)
    end
    if g.hideTankBossAlertsForHeal == nil then
        g.hideTankBossAlertsForHeal = false
    else
        g.hideTankBossAlertsForHeal = (g.hideTankBossAlertsForHeal == true)
    end
    return g
end

local function GetTrashStore()
    return ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
end

local function EnsureTrashSettingsDB()
    local Store = GetTrashStore()
    if Store and type(Store.EnsureDB) == "function" then
        return Store.EnsureDB()
    end
    ExBossDB = ExBossDB or {}
    ExBossDB.trashCD = ExBossDB.trashCD or {}
    return ExBossDB.trashCD
end

local function EnsureTrashNameplateIconDB()
    local db = EnsureTrashSettingsDB()
    db.nameplateIcon = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local icon = db.nameplateIcon
    if icon.showIcon == nil then
        icon.showIcon = true
    else
        icon.showIcon = icon.showIcon ~= false
    end
    icon.width = math.max(10, math.min(300, tonumber(icon.width) or tonumber(db.nameplateIconSize) or 25))
    icon.height = math.max(10, math.min(300, tonumber(icon.height) or tonumber(db.nameplateIconSize) or icon.width))
    icon.x = math.max(-1000, math.min(1000, tonumber(icon.x) or tonumber(db.nameplateOffsetX) or 6))
    icon.y = math.max(-1000, math.min(1000, tonumber(icon.y) or tonumber(db.nameplateOffsetY) or 0))
    if db.hideNameplateNPCID == nil then
        db.hideNameplateNPCID = true
    end

    -- 兼容旧字段，导出/导入和旧代码读取时仍能得到有效值。
    db.nameplateIconSize = math.max(icon.width, icon.height)
    db.nameplateOffsetX = icon.x
    db.nameplateOffsetY = icon.y
    db.nameplateIconStrata = tostring(db.nameplateIconStrata or "DIALOG"):upper()
    if db.nameplateIconStrata ~= "BACKGROUND"
        and db.nameplateIconStrata ~= "LOW"
        and db.nameplateIconStrata ~= "MEDIUM"
        and db.nameplateIconStrata ~= "HIGH"
        and db.nameplateIconStrata ~= "DIALOG"
        and db.nameplateIconStrata ~= "FULLSCREEN"
        and db.nameplateIconStrata ~= "FULLSCREEN_DIALOG"
        and db.nameplateIconStrata ~= "TOOLTIP" then
        db.nameplateIconStrata = "DIALOG"
    end
    return icon
end

local function GetTrashNameplateStrataText(value)
    local current = tostring(value or "DIALOG"):upper()
    for _, row in ipairs(GetTrashNameplateStrataOptions()) do
        if tostring(row[2] or ""):upper() == current then
            return row[1]
        end
    end
    return L["对话"]
end

local function EnsureTrashNameplateIconTextDB()
    local db = EnsureTrashSettingsDB()
    db.nameplateIconText = type(db.nameplateIconText) == "table" and db.nameplateIconText or {}
    local font = db.nameplateIconText
    font.r = tonumber(font.r) or 1
    font.g = tonumber(font.g) or 1
    font.b = tonumber(font.b) or 1
    font.a = tonumber(font.a) or 1
    font.size = math.max(4, math.min(100, tonumber(font.size) or 15))
    font.font = tostring(font.font or "")
    font.outline = tostring(font.outline or "OUTLINE")
    font.x = math.max(-200, math.min(200, tonumber(font.x) or 0))
    font.y = math.max(-200, math.min(200, tonumber(font.y) or 0))
    font.shadow = font.shadow ~= false
    font.shadowX = math.max(-20, math.min(20, tonumber(font.shadowX) or 1))
    font.shadowY = math.max(-20, math.min(20, tonumber(font.shadowY) or -1))
    return font
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
    if s == "" then
        return nil
    end
    return s
end

local function WriteCVarValue(name, value)
    local key = tostring(name or "")
    if key == "" then
        return false
    end
    local s = tostring(value or "")
    if s == "" then
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

local function SetEncounterWarningsEnabled(enabled)
    WriteCVarValue("encounterWarningsEnabled", enabled and "1" or "0")
end

local function SetEncounterTimelineEnabled(enabled)
    WriteCVarValue("encounterTimelineEnabled", enabled and "1" or "0")
end

local function SetEncounterWarningSoundsEnabled(enabled)
    WriteCVarValue("Sound_EnableEncounterWarningsSounds", enabled and "1" or "2")
end

local function IsTimerBarEnabledByGlobal()
    local g = EnsureGeneralDB()
    local mode = NormalizeBarDisplayMode(g.barDisplayMode)
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local g = EnsureGeneralDB()
    local mode = NormalizeBarDisplayMode(g.barDisplayMode)
    return mode == "both" or mode == "bun"
end

local function RefreshGeneralControls()
    local g = EnsureGeneralDB()
    if barModeDropdown then
        local mode = NormalizeBarDisplayMode(g.barDisplayMode)
        barModeDropdown._currentValue = mode
        local label = L["仅束状条"]
        for _, item in ipairs(GetBarModeOptions()) do
            if item[2] == mode then
                label = item[1]
                break
            end
        end
        barModeDropdown:SetText(label)
    end
    if bossAlertsEnabledMplusCheck and bossAlertsEnabledMplusCheck.SetChecked then
        bossAlertsEnabledMplusCheck:SetChecked(g.bossAlertsEnabledMplus == true)
    end
    if bossAlertsEnabledRaidCheck and bossAlertsEnabledRaidCheck.SetChecked then
        bossAlertsEnabledRaidCheck:SetChecked(g.bossAlertsEnabledRaid == true)
    end
    if Page.hideTankBossAlertsForDpsCheck and Page.hideTankBossAlertsForDpsCheck.SetChecked then
        Page.hideTankBossAlertsForDpsCheck:SetChecked(g.hideTankBossAlertsForDps == true)
    end
    if Page.hideTankBossAlertsForHealCheck and Page.hideTankBossAlertsForHealCheck.SetChecked then
        Page.hideTankBossAlertsForHealCheck:SetChecked(g.hideTankBossAlertsForHeal == true)
    end
    if autoDisableCAAInBossCheck and autoDisableCAAInBossCheck.SetChecked then
        autoDisableCAAInBossCheck:SetChecked(g.autoDisableCAAInBoss == true)
    end
    if encounterWarningsEnabledCheck and encounterWarningsEnabledCheck.SetChecked then
        encounterWarningsEnabledCheck:SetChecked(IsEncounterWarningsEnabled())
    end
    if Page.encounterWarningSoundsEnabledCheck and Page.encounterWarningSoundsEnabledCheck.SetChecked then
        Page.encounterWarningSoundsEnabledCheck:SetChecked(IsEncounterWarningSoundsEnabled())
    end
    if encounterTimelineDisabledCheck and encounterTimelineDisabledCheck.SetChecked then
        encounterTimelineDisabledCheck:SetChecked(not IsEncounterTimelineEnabled())
    end
end

local function CreateBossTankFilterChecks(parent, exui)
    if not (exui and exui.CreateCheckbox and parent) then
        return
    end

    Page.hideTankBossAlertsForDpsCheck = exui:CreateCheckbox(
        parent,
        L["DPS职责下不提示坦克技能"],
        EnsureGeneralDB().hideTankBossAlertsForDps == true,
        function(checked)
            local g = EnsureGeneralDB()
            g.hideTankBossAlertsForDps = (checked == true)
            RefreshGeneralControls()
        end
    )
    Page.hideTankBossAlertsForDpsCheck:SetPoint("TOPLEFT", 10, -174)

    Page.hideTankBossAlertsForHealCheck = exui:CreateCheckbox(
        parent,
        L["治疗职责下不提示坦克技能"],
        EnsureGeneralDB().hideTankBossAlertsForHeal == true,
        function(checked)
            local g = EnsureGeneralDB()
            g.hideTankBossAlertsForHeal = (checked == true)
            RefreshGeneralControls()
        end
    )
    Page.hideTankBossAlertsForHealCheck:SetPoint("TOPLEFT", 10, -208)
end

local function CreateOverviewSection(parent, anchor, exui)
    overviewSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overviewSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    overviewSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    overviewSection:SetHeight(408)
    overviewSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overviewSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    overviewSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local overviewTitle = overviewSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overviewTitle:SetPoint("TOPLEFT", 10, -8)
    overviewTitle:SetText(L["全局条显示模式"])
    overviewTitle:SetTextColor(1, 0.82, 0.45)

    if exui and exui.CreateDropdown then
        barModeDropdown = exui:CreateDropdown(
            overviewSection,
            220,
            L["显示模式"],
            GetBarModeOptions(),
            EnsureGeneralDB().barDisplayMode,
            function(val)
                local g = EnsureGeneralDB()
                g.barDisplayMode = NormalizeBarDisplayMode(val)
                RefreshGeneralControls()
                ApplyBarModeChange()
            end,
            true
        )
        barModeDropdown:SetPoint("TOPLEFT", 10, -36)
    end

    if exui and exui.CreateCheckbox then
        bossAlertsEnabledMplusCheck = exui:CreateCheckbox(
            overviewSection,
            L["启用大秘境首领提示"],
            EnsureGeneralDB().bossAlertsEnabledMplus == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.bossAlertsEnabledMplus = (checked == true)
                RefreshGeneralControls()
                ApplyBossSceneToggleChange()
            end
        )
        bossAlertsEnabledMplusCheck:SetPoint("TOPLEFT", 10, -72)
    end

    if exui and exui.CreateCheckbox then
        bossAlertsEnabledRaidCheck = exui:CreateCheckbox(
            overviewSection,
            L["启用团本首领提示"],
            EnsureGeneralDB().bossAlertsEnabledRaid == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.bossAlertsEnabledRaid = (checked == true)
                RefreshGeneralControls()
                ApplyBossSceneToggleChange()
            end
        )
        bossAlertsEnabledRaidCheck:SetPoint("TOPLEFT", 10, -106)
    end

    if exui and exui.CreateCheckbox then
        autoDisableCAAInBossCheck = exui:CreateCheckbox(
            overviewSection,
            L["首领战时自动关闭战斗音频预警"],
            EnsureGeneralDB().autoDisableCAAInBoss == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.autoDisableCAAInBoss = (checked == true)
                RefreshGeneralControls()
                if ExBoss and ExBoss.ApplyBossAutoCAASetting then
                    ExBoss.ApplyBossAutoCAASetting()
                end
            end
        )
        autoDisableCAAInBossCheck:SetPoint("TOPLEFT", 10, -140)
    end

    CreateBossTankFilterChecks(overviewSection, exui)

    if exui and exui.CreateCheckbox then
        encounterWarningsEnabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["开启中央文字预警（注意：如果关闭会导致语音不工作）"],
            IsEncounterWarningsEnabled(),
            function(checked)
                SetEncounterWarningsEnabled(checked == true)
                RefreshGeneralControls()
            end
        )
        encounterWarningsEnabledCheck:SetPoint("TOPLEFT", 10, -242)
    end

    if exui and exui.CreateCheckbox then
        Page.encounterWarningSoundsEnabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["开启中央文字预警提示音（预设叮一声）"],
            IsEncounterWarningSoundsEnabled(),
            function(checked)
                SetEncounterWarningSoundsEnabled(checked == true)
                RefreshGeneralControls()
            end
        )
        Page.encounterWarningSoundsEnabledCheck:SetPoint("TOPLEFT", 10, -276)
    end

    if exui and exui.CreateCheckbox then
        encounterTimelineDisabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["关闭暴雪原生计时条"],
            not IsEncounterTimelineEnabled(),
            function(checked)
                SetEncounterTimelineEnabled(not (checked == true))
                RefreshGeneralControls()
            end
        )
        encounterTimelineDisabledCheck:SetPoint("TOPLEFT", 10, -310)
    end

    local overviewDesc = overviewSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overviewDesc:SetPoint("TOPLEFT", 10, -346)
    overviewDesc:SetPoint("RIGHT", overviewSection, "RIGHT", -10, 0)
    overviewDesc:SetJustifyH("LEFT")
    overviewDesc:SetTextColor(0.85, 0.85, 0.9)
    overviewDesc:SetText(L["控制全局显示：仅计时条 / 仅束状条 / 两者都启用 / 两者都隐藏。\n可单独关闭大秘境或团本首领提示；关闭后将整体禁用该场景的 Boss 计时、中央文字、语音与颜色覆盖。\n可按当前职责过滤坦克类 Boss 技能提示。\n可选：首领战中自动将战斗音频预警分类音量静音（0），脱战恢复原值。"])
    overviewSection:Hide()
end

local function CreateVoiceSection(parent, anchor, exui)
    voiceSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    voiceSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    voiceSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    voiceSection:SetHeight(120)
    voiceSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    voiceSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    voiceSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local voiceTitle = voiceSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voiceTitle:SetPoint("TOPLEFT", 10, -8)
    voiceTitle:SetText(L["全局语音输出"])
    voiceTitle:SetTextColor(1, 0.82, 0.45)

    if exui and exui.CreateDropdown then
        voiceChannelDrop = exui:CreateDropdown(
            voiceSection,
            180,
            L["输出通道"],
            CHANNEL_OPTIONS,
            EnsureVoiceDB().channel,
            function(val)
                local g = EnsureVoiceDB()
                g.channel = tostring(val or "Master")
                ApplyVoiceOverrides()
            end,
            true
        )
        voiceChannelDrop:SetPoint("TOPLEFT", 10, -34)
    end

    if exui and exui.CreateSlider then
        voiceVolumeSlider = exui:CreateSlider(
            voiceSection,
            300,
            L["全局音量"],
            0,
            1,
            EnsureVoiceDB().volume,
            0.01,
            function(v) return string.format("%.2f", v) end,
            function(v)
                local g = EnsureVoiceDB()
                g.volume = tonumber(string.format("%.2f", v)) or 1.0
                ApplyVoiceOverrides()
            end
        )
        voiceVolumeSlider:SetPoint("TOPLEFT", 10, -78)
    end
    voiceSection:Hide()
end

local function CreateVoiceRegisterSection(parent, anchor)
    voiceRegisterSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    voiceRegisterSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    voiceRegisterSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    voiceRegisterSection:SetHeight(520)
    voiceRegisterSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    voiceRegisterSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    voiceRegisterSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local monitorTitle = voiceRegisterSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorTitle:SetPoint("TOPLEFT", 10, -8)
    monitorTitle:SetText(L["当前语音注册状态"])
    monitorTitle:SetTextColor(1, 0.82, 0.45)

    voiceRegisterSummary = voiceRegisterSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    voiceRegisterSummary:SetPoint("TOPLEFT", 10, -32)
    voiceRegisterSummary:SetPoint("RIGHT", voiceRegisterSection, "RIGHT", -120, 0)
    voiceRegisterSummary:SetJustifyH("LEFT")
    voiceRegisterSummary:SetTextColor(0.9, 0.95, 1)
    voiceRegisterSummary:SetText(L["已注册BOSS: 0  |  已注册事件: 0"])

    voiceRegisterTime = voiceRegisterSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    voiceRegisterTime:SetPoint("TOPLEFT", 10, -52)
    voiceRegisterTime:SetPoint("RIGHT", voiceRegisterSection, "RIGHT", -120, 0)
    voiceRegisterTime:SetJustifyH("LEFT")
    voiceRegisterTime:SetTextColor(0.75, 0.8, 0.9)
    voiceRegisterTime:SetText(L["最近刷新: -"])

    local refreshBtn = CreateFrame("Button", nil, voiceRegisterSection, "UIPanelButtonTemplate")
    refreshBtn:SetSize(96, 24)
    refreshBtn:SetPoint("TOPRIGHT", -10, -24)
    refreshBtn:SetText(L["刷新"])
    refreshBtn:SetScript("OnClick", function()
        RefreshVoiceRegisterMonitor()
    end)

    local listBg = CreateFrame("Frame", nil, voiceRegisterSection, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 10, -76)
    listBg:SetPoint("BOTTOMRIGHT", voiceRegisterSection, "BOTTOMRIGHT", -10, 10)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    listBg:SetBackdropColor(0.02, 0.02, 0.03, 0.92)
    listBg:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.95)

    voiceRegisterListScroll = CreateFrame("ScrollFrame", nil, listBg, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(voiceRegisterListScroll)
    end
    voiceRegisterListScroll:SetPoint("TOPLEFT", 4, -4)
    voiceRegisterListScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    voiceRegisterListChild = CreateFrame("Frame", nil, voiceRegisterListScroll)
    voiceRegisterListChild:SetSize(560, 24)
    voiceRegisterListScroll:SetScrollChild(voiceRegisterListChild)

    voiceRegisterListText = voiceRegisterListChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    voiceRegisterListText:SetPoint("TOPLEFT", 3, -2)
    voiceRegisterListText:SetJustifyH("LEFT")
    voiceRegisterListText:SetJustifyV("TOP")
    voiceRegisterListText:SetWordWrap(true)
    voiceRegisterListText:SetTextColor(0.92, 0.92, 0.92)
    voiceRegisterListText:SetText(L["暂无已注册BOSS"])

    voiceRegisterSection:Hide()
end

local function CreateColorSection(parent, anchor, exui)
    colorSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colorSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    colorSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    colorSection:SetHeight(430)
    colorSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    colorSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    colorSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local colorTitle = colorSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorTitle:SetPoint("TOPLEFT", 10, -8)
    colorTitle:SetText(L["通用颜色方案"])
    colorTitle:SetTextColor(1, 0.82, 0.45)

    local colorDesc = colorSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorDesc:SetPoint("TOPLEFT", 10, -28)
    colorDesc:SetPoint("RIGHT", colorSection, "RIGHT", -10, 0)
    colorDesc:SetText(L["Boss技能页面可选择下列方案；选择“自定义颜色”时使用“自定义方案”。勾选启用的额外方案会出现在技能页下拉。"])
    colorDesc:SetTextColor(0.85, 0.85, 0.9)
    colorDesc:SetJustifyH("LEFT")

    local _, schemes, custom, extraSlots = EnsureColorDB()
    local rowY = -52
    for _, key in ipairs(GetSchemeOrder()) do
        local row = schemes and schemes[key]

        local nameFS = colorSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameFS:SetPoint("TOPLEFT", 12, rowY)
        nameFS:SetText(GetSchemeDisplayName(key))
        nameFS:SetTextColor(0.95, 0.95, 0.95)
        fixedColorLabels[key] = nameFS

        if exui and exui.CreateColorButton then
            local btn = exui:CreateColorButton(colorSection, L["颜色"], row or { r = 1, g = 1, b = 1 }, "", false, function()
                ApplyVoiceOverrides()
            end)
            btn:SetPoint("TOPLEFT", 180, rowY + 8)
            btn:SetSize(220, 30)
            fixedColorButtons[key] = btn
        end
        rowY = rowY - 38
    end

    if exui and exui.CreateEditBox then
        customNameInput = exui:CreateEditBox(
            colorSection,
            (custom and custom.name) or L["自定义方案"],
            160,
            28,
            L["自定义方案名"],
            {
                onEditFocusLost = function(text)
                    local _, _, c = EnsureColorDB()
                    c.name = TrimOptionalText(text)
                    RefreshColorControls()
                end,
                onEnter = function(text)
                    local _, _, c = EnsureColorDB()
                    c.name = TrimOptionalText(text)
                    RefreshColorControls()
                end,
            }
        )
        customNameInput:SetPoint("TOPLEFT", 12, rowY - 2)
    end

    if exui and exui.CreateColorButton then
        customColorButton = exui:CreateColorButton(colorSection, L["自定义方案颜色"], custom or { r = 1, g = 0.82, b = 0.25 }, "", false,
            function()
                ApplyVoiceOverrides()
            end
        )
        customColorButton:SetPoint("TOPLEFT", 180, rowY + 6)
        customColorButton:SetSize(220, 30)
    end

    rowY = rowY - 42
    local extraTitle = colorSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    extraTitle:SetPoint("TOPLEFT", 12, rowY)
    extraTitle:SetText(L["额外方案（最多3个）"])
    extraTitle:SetTextColor(0.95, 0.95, 0.95)

    rowY = rowY - 24
    for i = 1, GetExtraCustomCount() do
        local slot = type(extraSlots) == "table" and extraSlots[i] or nil
        if type(slot) ~= "table" then
            slot = { enabled = false, name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25 }
        end

        if exui and exui.CreateCheckbox then
            local cb = exui:CreateCheckbox(colorSection, L["启用"], slot.enabled == true, function(checked)
                local _, _, _, slots = EnsureColorDB()
                if type(slots) ~= "table" then return end
                local row = slots and slots[i]
                if type(row) ~= "table" then
                    row = { name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25, enabled = false }
                    slots[i] = row
                end
                row.enabled = (checked == true)
                RefreshColorControls()
                ApplyVoiceOverrides()
            end)
            cb:SetPoint("TOPLEFT", 12, rowY + 4)
            extraCustomEnableChecks[i] = cb
        end

        if exui and exui.CreateEditBox then
            local nameInput = exui:CreateEditBox(
                colorSection,
                slot.name or (L["额外方案"] .. tostring(i)),
                190,
                28,
                "",
                {
                    onEditFocusLost = function(text)
                        local _, _, _, slots = EnsureColorDB()
                        if type(slots) ~= "table" then return end
                        local row = slots and slots[i]
                        if type(row) ~= "table" then
                            row = { enabled = false, r = 1, g = 0.82, b = 0.25 }
                            slots[i] = row
                        end
                        row.name = TrimOptionalText(text)
                        RefreshColorControls()
                    end,
                    onEnter = function(text)
                        local _, _, _, slots = EnsureColorDB()
                        if type(slots) ~= "table" then return end
                        local row = slots and slots[i]
                        if type(row) ~= "table" then
                            row = { enabled = false, r = 1, g = 0.82, b = 0.25 }
                            slots[i] = row
                        end
                        row.name = TrimOptionalText(text)
                        RefreshColorControls()
                    end,
                }
            )
            nameInput:SetPoint("TOPLEFT", 88, rowY + 2)
            extraCustomNameInputs[i] = nameInput
        end

        if exui and exui.CreateColorButton then
            local colorBtn = exui:CreateColorButton(colorSection, L["颜色"], slot, "", false, function()
                ApplyVoiceOverrides()
            end)
            colorBtn:SetPoint("TOPLEFT", 290, rowY + 6)
            colorBtn:SetSize(220, 30)
            extraCustomColorButtons[i] = colorBtn
        end

        rowY = rowY - 38
    end
    colorSection:Hide()
end

local function CreateResetSection(parent, anchor)
    resetSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    resetSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    resetSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    resetSection:SetHeight(204)
    resetSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    resetSection:SetBackdropColor(0.12, 0.03, 0.03, 0.85)
    resetSection:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.95)

    local resetTitle = resetSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetTitle:SetPoint("TOPLEFT", 10, -10)
    resetTitle:SetText("|cffff4444" .. L["重置设置"] .. "|r")

    local resetDesc = resetSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetDesc:SetPoint("TOPLEFT", 10, -30)
    resetDesc:SetPoint("RIGHT", resetSection, "RIGHT", -10, 0)
    resetDesc:SetJustifyH("LEFT")
    resetDesc:SetText(L["推荐先使用针对性重置：外观问题用“仅重置外观设置”，小怪CD异常用“重置小怪内置CD设置”。\n“重置所有配置（不包含外观）”会清空通用设置、语音配置、技能配置与时间轴设置，但保留外观。\n“清除全部设置”会把 EXBoss 的全部配置都恢复到初始状态。"])
    resetDesc:SetTextColor(0.9, 0.7, 0.7)

    local resetStyleBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetStyleBtn:SetSize(220, 28)
    resetStyleBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 118)
    resetStyleBtn:SetText(L["仅重置外观设置"])
    resetStyleBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_STYLE_ONLY_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["仅重置计时条/束状条/倒计时/文字公告的外观样式，不删除法术配置。是否继续？"],
                button1 = L["确定"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetDisplayStylesOnly()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)

    local resetTrashCDBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetTrashCDBtn:SetSize(220, 28)
    resetTrashCDBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 82)
    resetTrashCDBtn:SetText(L["重置小怪内置CD设置"])
    resetTrashCDBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_TRASH_CD_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["|cffffcc00将清空小怪内置CD的全局设置、姓名版设置和所有法术覆盖。|r\n会重新使用 Lua 预设默认值。是否继续？"],
                button1 = L["确定重置"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetTrashCDSettingsOnly()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)

    local resetConfigBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetConfigBtn:SetSize(220, 28)
    resetConfigBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 46)
    resetConfigBtn:SetText(L["重置所有配置（不包含外观）"])
    resetConfigBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_CONFIG_ONLY_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["|cffffcc00将清空 EXBoss 的通用设置、语音配置、技能配置与时间轴设置，但保留外观样式。|r\n确认继续？"],
                button1 = L["确定重置"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetAllConfigExceptAppearance()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)

    local resetAllBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetAllBtn:SetSize(220, 28)
    resetAllBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 10)
    resetAllBtn:SetText(L["清除全部设置（包含外观）"])
    resetAllBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_ALL_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["|cffff4444危险：将清空 EXBoss 的全部设置（包含外观）并重载。此操作不可撤销。|r\n确认继续？"],
                button1 = L["确定清空"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetAllConfigIncludingAppearance()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)
    resetSection:Hide()
end

local function PublishTrashCDSettingsChanged(changedKey)
    local Store = GetTrashStore()
    if Store and type(Store.SyncSavedToModuleDB) == "function" then
        Store.SyncSavedToModuleDB()
    end
    if Store and type(Store.PublishConfigChanged) == "function" then
        Store.PublishConfigChanged(changedKey or "trashGlobal")
    end
end

local function PublishTrashNameplateIconChanged()
    EnsureTrashNameplateIconDB()
    if trashNameplatePreview and trashNameplatePreview.Refresh then
        trashNameplatePreview:Refresh()
    end
    PublishTrashCDSettingsChanged("nameplateIcon")
end

local function PublishTrashNameplateIconTextChanged()
    EnsureTrashNameplateIconTextDB()
    if trashNameplatePreview and trashNameplatePreview.Refresh then
        trashNameplatePreview:Refresh()
    end
    PublishTrashCDSettingsChanged("nameplateIconText")
end

local function RefreshTrashCDControls()
    local db = EnsureTrashSettingsDB()
    EnsureTrashNameplateIconDB()
    EnsureTrashNameplateIconTextDB()
    if trashHideLongCheck and trashHideLongCheck.SetChecked then
        trashHideLongCheck:SetChecked(db.hideLongTimerBarEnabled == true)
    end
    if trashKeepReadyCheck and trashKeepReadyCheck.SetChecked then
        trashKeepReadyCheck:SetChecked(db.keepTimerBarAfterReadyEnabled == true)
    end
    if trashHideLongInput and trashHideLongInput.SetText then
        trashHideLongInput:SetText(tostring(math.max(0, tonumber(db.hideLongTimerBarSeconds) or 0)))
    end
    if trashKeepReadyInput and trashKeepReadyInput.SetText then
        trashKeepReadyInput:SetText(tostring(math.max(0, tonumber(db.keepTimerBarAfterReadySeconds) or 0)))
    end
    if trashNameplateSideDropdown then
        local side = tostring(db.nameplateGrowthSide or "left")
        if side ~= "left" and side ~= "right" then
            side = "left"
        end
        trashNameplateSideDropdown._currentValue = side
        trashNameplateSideDropdown:SetText(side == "left" and L["向左增长"] or L["向右增长"])
    end
    if trashNameplateStrataDropdown then
        local strata = tostring(db.nameplateIconStrata or "DIALOG"):upper()
        trashNameplateStrataDropdown._currentValue = strata
        trashNameplateStrataDropdown:SetText(GetTrashNameplateStrataText(strata))
    end
    if trashNameplatePreview and trashNameplatePreview.Refresh then
        trashNameplatePreview:Refresh()
    end
end

local function GetDogJumpTracker()
    return ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.DogJumpTracker or nil
end

local function GetTrash248690AbsorbModule()
    return ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.MaisaraTrash248690Absorb or nil
end

local function GetVordazaShieldModule()
    return ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.VordazaShieldBar or nil
end

local function EnsureTrash248690PanelDB()
    _G.ExBossDB = _G.ExBossDB or {}
    _G.ExBossDB.timer = _G.ExBossDB.timer or {}
    local db = _G.ExBossDB.timer.trash248690AbsorbPanel
    if type(db) ~= "table" then
        db = {}
        _G.ExBossDB.timer.trash248690AbsorbPanel = db
    end
    if db.maxVisibleBars == nil then
        db.maxVisibleBars = 6
    end
    if db.stackGap == nil then
        db.stackGap = 4
    end
    return db
end

local function EnsureTrash248690StyleDB()
    _G.ExBossDB = _G.ExBossDB or {}
    _G.ExBossDB.timer = _G.ExBossDB.timer or {}
    local exdb = _G.ExBossDB.timer.trash248690AbsorbStyle
    if type(exdb) ~= "table" then
        local legacy = _G.ExBossDB.timer.castProgressBar
        if type(legacy) == "table" then
            local migrated = {}
            DeepCopyInto(migrated, legacy)
            exdb = migrated
        else
            exdb = {}
        end
        _G.ExBossDB.timer.trash248690AbsorbStyle = exdb
    end
    DeepApplyDefaults(exdb, TRASH248690_STYLE_DEFAULTS)
    if type(exdb.font_percent) ~= "table" then
        exdb.font_percent = {}
    end
    if next(exdb.font_percent) == nil and type(exdb.font_time) == "table" then
        DeepCopyInto(exdb.font_percent, exdb.font_time)
    end
    DeepApplyDefaults(exdb.font_percent, TRASH248690_STYLE_DEFAULTS.font_percent)
    return exdb
end

local function RefreshTrash248690StyleEditor()
    local host = dungeonExtra.trash248690StyleHost
    local EXUI = ExwindTools and ExwindTools.UI or nil
    if not host or not EXUI or type(EXUI.CreateTimerBarGroupV2) ~= "function" then
        return
    end

    local db = EnsureTrash248690StyleDB()
    if type(db) ~= "table" or type(db.timerBarGroup) ~= "table" then
        return
    end

    local width = math.max(720, math.floor((dungeonExtra.section:GetWidth() or 760) - 24))
    host:SetWidth(width)
    host:SetHeight(920)

    if not dungeonExtra.trash248690StyleWidget then
        dungeonExtra.trash248690StyleWidget = EXUI:CreateTimerBarGroupV2(
            host,
            width,
            L["计时条外观"],
            db.timerBarGroup,
            nil,
            function()
                local exdb = EnsureTrash248690StyleDB()
                local panelDB = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.trash248690AbsorbPanel
                if type(exdb) == "table" and type(exdb.timerBarGroup) == "table" and type(panelDB) == "table" then
                    panelDB.width = math.max(80, tonumber(exdb.timerBarGroup.width) or tonumber(panelDB.width) or 220)
                    panelDB.height = math.max(8, tonumber(exdb.timerBarGroup.height) or tonumber(panelDB.height) or 18)
                end
                local TrashAbsorb = GetTrash248690AbsorbModule()
                if TrashAbsorb and TrashAbsorb.RefreshVisuals then
                    TrashAbsorb:RefreshVisuals()
                end
            end
        )
        dungeonExtra.trash248690StyleWidget:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    end

    dungeonExtra.trash248690StyleWidget:ClearAllPoints()
    dungeonExtra.trash248690StyleWidget:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    dungeonExtra.trash248690StyleWidget:SetWidth(width)
    dungeonExtra.trash248690StyleWidget:Show()

    if not dungeonExtra.trash248690PercentFontWidget and EXUI.CreateFontGroup then
        dungeonExtra.trash248690PercentFontWidget = EXUI:CreateFontGroup(
            host,
            width,
            L["百分比文本"],
            db.font_percent,
            function()
                local exdb = EnsureTrash248690StyleDB()
                local TrashAbsorb = GetTrash248690AbsorbModule()
                if TrashAbsorb and TrashAbsorb.RefreshVisuals then
                    TrashAbsorb:RefreshVisuals()
                end
            end
        )
    end

    if dungeonExtra.trash248690PercentFontWidget then
        dungeonExtra.trash248690PercentFontWidget:ClearAllPoints()
        dungeonExtra.trash248690PercentFontWidget:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -620)
        dungeonExtra.trash248690PercentFontWidget:SetWidth(width)
        dungeonExtra.trash248690PercentFontWidget:Show()
    end
end

local function RefreshDungeonExtraControls()
    local DogJump = GetDogJumpTracker()
    if dungeonExtra.dogJumpEnabledCheck and dungeonExtra.dogJumpEnabledCheck.SetChecked then
        dungeonExtra.dogJumpEnabledCheck:SetChecked((not DogJump or not DogJump.IsEnabled) or DogJump:IsEnabled())
    end
    if dungeonExtra.dogJumpPreviewCheck and dungeonExtra.dogJumpPreviewCheck.SetChecked then
        dungeonExtra.dogJumpPreviewCheck:SetChecked(DogJump and DogJump.IsPreviewing and DogJump:IsPreviewing() == true)
    end

    local TrashAbsorb = GetTrash248690AbsorbModule()
    if dungeonExtra.trash248690EditButton and dungeonExtra.trash248690EditButton.SetText then
        local inEditMode = TrashAbsorb and TrashAbsorb.IsEditMode and TrashAbsorb:IsEditMode() == true
        dungeonExtra.trash248690EditButton:SetText(inEditMode and L["关闭编辑模式"] or L["进入编辑模式"])
    end
    local VordazaShield = GetVordazaShieldModule()
    if dungeonExtra.vordazaShieldEditButton and dungeonExtra.vordazaShieldEditButton.SetText then
        local inEditMode = VordazaShield and VordazaShield.IsEditMode and VordazaShield:IsEditMode() == true
        dungeonExtra.vordazaShieldEditButton:SetText(inEditMode and L["关闭编辑模式"] or L["进入编辑模式"])
    end
    local panelDB = EnsureTrash248690PanelDB()
    if dungeonExtraTrashMaxBarsSlider and dungeonExtraTrashMaxBarsSlider.SetValue then
        dungeonExtraTrashMaxBarsSlider:SetValue(math.max(1, math.min(8, tonumber(panelDB.maxVisibleBars) or 6)))
    end
    if dungeonExtraTrashGapSlider and dungeonExtraTrashGapSlider.SetValue then
        dungeonExtraTrashGapSlider:SetValue(math.max(0, math.min(30, tonumber(panelDB.stackGap) or 4)))
    end
    RefreshTrash248690StyleEditor()
end

local function GetPartyFrameGlow()
    return ExBoss and ExBoss.Display and ExBoss.Display.PartyFrameGlow or nil
end

local function EnsurePartyFrameGlowDB()
    local Glow = GetPartyFrameGlow()
    if Glow and type(Glow.GetDB) == "function" then
        return Glow.GetDB()
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.partyFrameGlow = ExBossDB.ui.partyFrameGlow or {}
    local db = ExBossDB.ui.partyFrameGlow
    if db.glowEnabled == nil then db.glowEnabled = true end
    db.glowStyle = db.glowStyle or "Pixel Glow"
    db.glowColorR = tonumber(db.glowColorR) or 1
    db.glowColorG = tonumber(db.glowColorG) or 0.86
    db.glowColorB = tonumber(db.glowColorB) or 0.1
    db.glowColorA = tonumber(db.glowColorA) or 1
    db.glowFrequency = tonumber(db.glowFrequency) or 0.35
    db.glowLines = tonumber(db.glowLines) or 10
    db.glowScale = tonumber(db.glowScale) or 2
    db.glowOffset = tonumber(db.glowOffset) or 0
    db.duration = tonumber(db.duration) or 5
    return db
end

local function GetPartyFrameGlowPreviewUnits(groupMode)
    local units = {}
    if groupMode and IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then
                units[#units + 1] = unit
                if #units >= 5 then
                    break
                end
            end
        end
    elseif groupMode then
        units[#units + 1] = "player"
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                units[#units + 1] = unit
            end
        end
    else
        units[#units + 1] = "player"
    end
    return units
end

local function StopPartyFrameGlowPreview()
    local Glow = GetPartyFrameGlow()
    if Glow and type(Glow.Hide) == "function" then
        Glow.Hide("settings.partyFrameGlow")
    end
    partyFrameGlow.previewToken = (tonumber(partyFrameGlow.previewToken) or 0) + 1
    partyFrameGlow.previewUnits = nil
end

local function PreviewPartyFrameGlow(units)
    local Glow = GetPartyFrameGlow()
    if not (Glow and type(Glow.ShowUnits) == "function") then
        if partyFrameGlow.statusText then
            partyFrameGlow.statusText:SetText("|cffff5555" .. L["PartyFrameGlow 模块未加载。"] .. "|r")
        end
        return
    end

    units = type(units) == "table" and units or GetPartyFrameGlowPreviewUnits(false)
    partyFrameGlow.previewUnits = units
    local previewOpts = {
        useGlobalSettings = true,
        preferGroupedPlayerFrame = true,
    }
    local ok = Glow.ShowUnits("settings.partyFrameGlow", units, {
        useGlobalSettings = previewOpts.useGlobalSettings,
        preferGroupedPlayerFrame = previewOpts.preferGroupedPlayerFrame,
    })

    if partyFrameGlow.statusText then
        if ok then
            local names = {}
            for i = 1, #units do
                local name = UnitName(units[i]) or units[i]
                names[#names + 1] = tostring(name)
            end
            partyFrameGlow.statusText:SetText("|cff55ff88" .. L["预览中："] .. "|r" .. table.concat(names, " / "))
            partyFrameGlow.previewToken = (tonumber(partyFrameGlow.previewToken) or 0) + 1
            local token = partyFrameGlow.previewToken
            local duration = tonumber(EnsurePartyFrameGlowDB().duration) or 5
            if C_Timer and C_Timer.After then
                C_Timer.After(duration, function()
                    if partyFrameGlow.previewToken == token then
                        partyFrameGlow.previewUnits = nil
                        if partyFrameGlow.statusText then
                            partyFrameGlow.statusText:SetText(L["预览已结束。"])
                        end
                    end
                end)
            end
        elseif EnsurePartyFrameGlowDB().glowEnabled == false then
            partyFrameGlow.statusText:SetText("|cffffcc00" .. L["发光已关闭，启用后再预览。"] .. "|r")
        else
            partyFrameGlow.statusText:SetText("|cffffcc00" .. L["没有找到可发光的队伍/团队框架。请确认框架已显示。"] .. "|r")
        end
    end
end

local function RefreshPartyFrameGlowControls()
    EnsurePartyFrameGlowDB()
    if partyFrameGlow.previewUnits then
        PreviewPartyFrameGlow(partyFrameGlow.previewUnits)
    elseif partyFrameGlow.statusText then
        partyFrameGlow.statusText:SetText(L["可用上方按钮测试当前样式。"])
    end
end

local function BuildTrashNameplatePreview(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(430, 76)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(L["姓名版图标预览"])
    label:SetTextColor(0.85, 0.85, 0.9)

    local plate = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    plate:SetSize(190, 26)
    plate:SetPoint("LEFT", holder, "LEFT", 150, -30)
    plate:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    plate:SetBackdropColor(0.02, 0.025, 0.03, 0.92)
    plate:SetBackdropBorderColor(0.20, 0.62, 0.32, 0.9)

    local name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("CENTER")
    name:SetText(L["姓名版锚点"])
    name:SetTextColor(0.82, 0.92, 0.82)
    plate.name = name

    local samples = {
        { icon = 136243, text = "8" },
        { icon = 132343, text = "21" },
        { icon = 135826, text = "" },
    }

    local function ResolvePreviewFont(fontKey)
        local key = tostring(fontKey or "")
        if key ~= "" and LibStub then
            local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
            if ok and lsm and type(lsm.Fetch) == "function" then
                local font = lsm:Fetch("font", key, true)
                if font and font ~= "" then
                    return font
                end
            end
        end
        return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    end

    local function ApplyPreviewTextStyle(icon, fontDb)
        if not (icon and icon.count and type(fontDb) == "table") then
            return
        end
        icon.count:ClearAllPoints()
        local anchor = icon.textOverlay or icon
        icon.count:SetPoint("CENTER", anchor, "CENTER", tonumber(fontDb.x) or 0, tonumber(fontDb.y) or 0)
        if icon.count.SetFont then
            icon.count:SetFont(ResolvePreviewFont(fontDb.font), tonumber(fontDb.size) or 11, tostring(fontDb.outline or "OUTLINE"))
        end
        icon.count:SetTextColor(tonumber(fontDb.r) or 1, tonumber(fontDb.g) or 1, tonumber(fontDb.b) or 1, tonumber(fontDb.a) or 1)
        if fontDb.shadow == false then
            icon.count:SetShadowOffset(0, 0)
        else
            icon.count:SetShadowOffset(tonumber(fontDb.shadowX) or 1, tonumber(fontDb.shadowY) or -1)
            icon.count:SetShadowColor(0, 0, 0, 0.9)
        end
    end

    local function EnsurePreviewIcon(index)
        local icon = trashNameplatePreviewIcons[index]
        if icon then
            return icon
        end
        icon = CreateFrame("Frame", nil, holder, "BackdropTemplate")
        icon:SetSize(22, 22)
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true,
            tileSize = 8,
            edgeSize = 1,
        })
        icon:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
        icon:SetBackdropBorderColor(0.26, 0.26, 0.30, 1)
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.tex = tex
        local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cooldown:SetAllPoints(icon)
        cooldown:SetFrameLevel(icon:GetFrameLevel() + 1)
        if cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(true)
        end
        if cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(true)
        end
        if cooldown.SetReverse then
            cooldown:SetReverse(false)
        end
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(true)
        end
        cooldown.noCooldownCount = true
        cooldown.noOCC = true
        icon.cooldown = cooldown
        local textOverlay = CreateFrame("Frame", nil, icon)
        textOverlay:SetAllPoints(icon)
        textOverlay:SetFrameLevel(icon:GetFrameLevel() + 2)
        icon.textOverlay = textOverlay
        local count = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("CENTER")
        count:SetTextColor(1, 1, 1)
        icon.count = count
        trashNameplatePreviewIcons[index] = icon
        return icon
    end

    function holder:Refresh()
        local db = EnsureTrashSettingsDB()
        local iconDb = EnsureTrashNameplateIconDB()
        local fontDb = EnsureTrashNameplateIconTextDB()
        local side = tostring(db.nameplateGrowthSide or "left")
        if side ~= "left" and side ~= "right" then
            side = "left"
        end
        local iconWidth = math.max(10, math.min(300, tonumber(iconDb.width) or 25))
        local iconHeight = math.max(10, math.min(300, tonumber(iconDb.height) or iconWidth))
        local offsetX = math.max(-1000, math.min(1000, tonumber(iconDb.x) or 6))
        local offsetY = math.max(-1000, math.min(1000, tonumber(iconDb.y) or 0))
        for i = 1, #samples do
            local icon = EnsurePreviewIcon(i)
            icon:SetSize(iconWidth, iconHeight)
            icon:ClearAllPoints()
            if side == "left" then
                if i == 1 then
                    icon:SetPoint("RIGHT", plate, "LEFT", -8 + offsetX, offsetY)
                else
                    icon:SetPoint("RIGHT", trashNameplatePreviewIcons[i - 1], "LEFT", -3, 0)
                end
            else
                if i == 1 then
                    icon:SetPoint("LEFT", plate, "RIGHT", 8 + offsetX, offsetY)
                else
                    icon:SetPoint("LEFT", trashNameplatePreviewIcons[i - 1], "RIGHT", 3, 0)
                end
            end
            icon.tex:SetTexture(samples[i].icon)
            if icon.cooldown.SetReverse then
                icon.cooldown:SetReverse(iconDb.reverse == true)
            end
            icon.cooldown:SetCooldown(GetTime() - (20 - (i * 5)), 20)
            icon.cooldown:Show()
            ApplyPreviewTextStyle(icon, fontDb)
            icon.count:SetText(samples[i].text)
            if iconDb.showIcon == false then
                icon:Hide()
            else
                icon:Show()
            end
        end
    end

    holder:Refresh()
    return holder
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

EnsureColorDB = function()
    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        local db = CS.EnsureDB()
        local custom = (db.customColors and db.customColors[1]) or {}
        return db, db.colorSchemes or {}, custom, db.extraCustomColors or {}
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.voice = ExBossDB.voice or {}
    ExBossDB.voice.colorSchemes = ExBossDB.voice.colorSchemes or {}
    ExBossDB.voice.customColors = ExBossDB.voice.customColors or {}
    ExBossDB.voice.extraCustomColors = ExBossDB.voice.extraCustomColors or {}
    ExBossDB.voice.customColors[1] = ExBossDB.voice.customColors[1] or { name = L["自定义方案"], r = 1, g = 0.82, b = 0.25 }

    for i = 1, EXTRA_CUSTOM_COUNT_FALLBACK do
        local row = ExBossDB.voice.extraCustomColors[i]
        if type(row) ~= "table" then
            ExBossDB.voice.extraCustomColors[i] = {
                enabled = false,
                name = L["额外方案"] .. tostring(i),
                r = 1,
                g = 0.82,
                b = 0.25,
            }
        else
            if row.enabled == nil then row.enabled = false end
            if type(row.name) ~= "string" then
                row.name = L["额外方案"] .. tostring(i)
            end
            row.r = tonumber(row.r) or 1
            row.g = tonumber(row.g) or 0.82
            row.b = tonumber(row.b) or 0.25
        end
    end

    for _, key in ipairs(FALLBACK_SCHEME_ORDER) do
        local row = ExBossDB.voice.colorSchemes[key]
        if type(row) ~= "table" then
            ExBossDB.voice.colorSchemes[key] = {
                name = GetFallbackSchemeName(key),
                r = 1,
                g = 1,
                b = 1,
            }
        end
    end

    return ExBossDB.voice, ExBossDB.voice.colorSchemes, ExBossDB.voice.customColors[1], ExBossDB.voice.extraCustomColors
end

GetSchemeOrder = function()
    local CS = GetColorModule()
    if CS and CS.GetFixedOrder then
        return CS.GetFixedOrder()
    end
    return FALLBACK_SCHEME_ORDER
end

GetSchemeDisplayName = function(key)
    local CS = GetColorModule()
    if CS and CS.GetSchemeDisplayName then
        return CS.GetSchemeDisplayName(key)
    end
    return GetFallbackSchemeName(key)
end

GetExtraCustomCount = function()
    local CS = GetColorModule()
    if CS and CS.GetExtraCustomCount then
        return tonumber(CS.GetExtraCustomCount()) or EXTRA_CUSTOM_COUNT_FALLBACK
    end
    return EXTRA_CUSTOM_COUNT_FALLBACK
end

ApplyVoiceOverrides = function()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

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

local EXBOSS_MODULE_KEYS = {
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashText",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
    "ExBoss.BossSpellOptions",
    "ExBoss.PrivateAuraOptions",
    "ExBoss.TrashCD.Settings",
}

local STYLE_MODULE_KEY_SET = {
    ["ExBoss.TimerBar"] = true,
    ["ExBoss.BunBar"] = true,
    ["ExBoss.Countdown"] = true,
    ["ExBoss.FlashText"] = true,
    ["ExBoss.FlashTextMedium"] = true,
    ["ExBoss.RingProgress"] = true,
    ["ExBoss.IconAlert"] = true,
    ["ExBoss.CastProgressBar"] = true,
}

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[DeepCopy(k)] = DeepCopy(v)
    end
    return out
end

local function CaptureAppearanceSnapshot()
    local snap = {
        timer = {},
        voice = {},
        moduleDB = {},
    }

    if type(ExBossDB) == "table" then
        local timer = type(ExBossDB.timer) == "table" and ExBossDB.timer or nil
        if timer then
            if timer.timerBar ~= nil then snap.timer.timerBar = DeepCopy(timer.timerBar) end
            if timer.bunBar ~= nil then snap.timer.bunBar = DeepCopy(timer.bunBar) end
            if timer.countdown ~= nil then snap.timer.countdown = DeepCopy(timer.countdown) end
            if timer.flashText ~= nil then snap.timer.flashText = DeepCopy(timer.flashText) end
            if timer.flashTextMedium ~= nil then snap.timer.flashTextMedium = DeepCopy(timer.flashTextMedium) end
            if timer.ringProgress ~= nil then snap.timer.ringProgress = DeepCopy(timer.ringProgress) end
            if timer.iconAlert ~= nil then snap.timer.iconAlert = DeepCopy(timer.iconAlert) end
            if timer.castProgressBar ~= nil then snap.timer.castProgressBar = DeepCopy(timer.castProgressBar) end
            if timer.trash248690AbsorbStyle ~= nil then snap.timer.trash248690AbsorbStyle = DeepCopy(timer.trash248690AbsorbStyle) end
        end

        local voice = type(ExBossDB.voice) == "table" and ExBossDB.voice or nil
        if voice then
            if voice.colorSchemes ~= nil then snap.voice.colorSchemes = DeepCopy(voice.colorSchemes) end
            if voice.customColors ~= nil then snap.voice.customColors = DeepCopy(voice.customColors) end
            if voice.extraCustomColors ~= nil then snap.voice.extraCustomColors = DeepCopy(voice.extraCustomColors) end
        end
    end

    if type(ExwindToolsDB) == "table" and type(ExwindToolsDB.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            if ExwindToolsDB.ModuleDB[key] ~= nil then
                snap.moduleDB[key] = DeepCopy(ExwindToolsDB.ModuleDB[key])
            end
        end
    end

    return snap
end

local function RestoreAppearanceSnapshot(snap)
    if type(snap) ~= "table" then
        return
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.voice = ExBossDB.voice or {}

    ExBossDB.timer.timerBar = DeepCopy(snap.timer and snap.timer.timerBar)
    ExBossDB.timer.bunBar = DeepCopy(snap.timer and snap.timer.bunBar)
    ExBossDB.timer.countdown = DeepCopy(snap.timer and snap.timer.countdown)
    ExBossDB.timer.flashText = DeepCopy(snap.timer and snap.timer.flashText)
    ExBossDB.timer.flashTextMedium = DeepCopy(snap.timer and snap.timer.flashTextMedium)
    ExBossDB.timer.ringProgress = DeepCopy(snap.timer and snap.timer.ringProgress)
    ExBossDB.timer.iconAlert = DeepCopy(snap.timer and snap.timer.iconAlert)
    ExBossDB.timer.castProgressBar = DeepCopy(snap.timer and snap.timer.castProgressBar)
    ExBossDB.timer.trash248690AbsorbStyle = DeepCopy(snap.timer and snap.timer.trash248690AbsorbStyle)
    ExBossDB.voice.colorSchemes = DeepCopy(snap.voice and snap.voice.colorSchemes)
    ExBossDB.voice.customColors = DeepCopy(snap.voice and snap.voice.customColors)
    ExBossDB.voice.extraCustomColors = DeepCopy(snap.voice and snap.voice.extraCustomColors)

    ExwindToolsDB = ExwindToolsDB or {}
    ExwindToolsDB.ModuleDB = ExwindToolsDB.ModuleDB or {}
    for _, key in ipairs(STYLE_MODULE_KEYS) do
        ExwindToolsDB.ModuleDB[key] = nil
    end
    if type(snap.moduleDB) == "table" then
        for key, value in pairs(snap.moduleDB) do
            ExwindToolsDB.ModuleDB[key] = DeepCopy(value)
        end
    end
end

local function ClearExBossModuleDB(preserveAppearanceModules)
    if type(ExwindToolsDB) ~= "table" or type(ExwindToolsDB.ModuleDB) ~= "table" then
        return
    end
    for _, key in ipairs(EXBOSS_MODULE_KEYS) do
        if not (preserveAppearanceModules and STYLE_MODULE_KEY_SET[key]) then
            ExwindToolsDB.ModuleDB[key] = nil
        end
    end
end

ResetDisplayStylesOnly = function()
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.timerBar = nil
    ExBossDB.timer.bunBar = nil
    ExBossDB.timer.countdown = nil
    ExBossDB.timer.flashText = nil
    ExBossDB.timer.flashTextMedium = nil
    ExBossDB.timer.ringProgress = nil
    ExBossDB.timer.iconAlert = nil
    ExBossDB.timer.castProgressBar = nil
    ExBossDB.timer.trash248690AbsorbStyle = nil

    if ExwindToolsDB and type(ExwindToolsDB.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            ExwindToolsDB.ModuleDB[key] = nil
        end
    end

    if ExBoss and ExBoss.UI then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
            ExBoss.UI.TimerBar:RefreshVisuals()
        end
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
            ExBoss.UI.BunBar:RefreshVisuals()
        end
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.RefreshVisuals then
            ExBoss.UI.Countdown:RefreshVisuals()
        end
        if ExBoss.UI.FlashText and ExBoss.UI.FlashText.RefreshVisuals then
            ExBoss.UI.FlashText:RefreshVisuals()
        end
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.RefreshVisuals then
            ExBoss.UI.FlashTextMedium:RefreshVisuals()
        end
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.RefreshVisuals then
            ExBoss.UI.RingProgress:RefreshVisuals()
        end
        if ExBoss.UI.IconAlert and ExBoss.UI.IconAlert.RefreshVisuals then
            ExBoss.UI.IconAlert:RefreshVisuals()
        end
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.RefreshVisuals then
            ExBoss.UI.CastProgressBar:RefreshVisuals()
        end
        local TrashAbsorb = GetTrash248690AbsorbModule()
        if TrashAbsorb and TrashAbsorb.RefreshVisuals then
            TrashAbsorb:RefreshVisuals()
        end
    end
end

ResetTrashCDSettingsOnly = function()
    local Store = GetTrashStore()
    if Store and type(Store.ResetSettings) == "function" then
        Store.ResetSettings()
        return
    end
    ExBossDB = ExBossDB or {}
    ExBossDB.trashCD = nil
    if type(ExwindToolsDB) == "table" and type(ExwindToolsDB.ModuleDB) == "table" then
        ExwindToolsDB.ModuleDB["ExBoss.TrashCD.Settings"] = nil
    end
end

ResetAllConfigExceptAppearance = function()
    local appearance = CaptureAppearanceSnapshot()

    ExBossDB = {}
    EXBossDataDB = nil
    ClearExBossModuleDB(false)

    RestoreAppearanceSnapshot(appearance)
end

ResetAllConfigIncludingAppearance = function()
    ExBossDB = nil
    EXBossDataDB = nil
    ClearExBossModuleDB(false)
end

local function RefreshVoiceControls()
    local g = EnsureVoiceDB()
    if voiceChannelDrop then
        voiceChannelDrop._currentValue = g.channel
        local label = g.channel
        for _, item in ipairs(CHANNEL_OPTIONS) do
            if item[2] == g.channel then
                label = item[1]
                break
            end
        end
        voiceChannelDrop:SetText(label or "Master")
    end
    if voiceVolumeSlider then
        if voiceVolumeSlider.Init then
            voiceVolumeSlider:Init(g.volume, 0, 1, 100)
        else
            voiceVolumeSlider:SetValue(g.volume)
        end
    end
end

local function RefreshVoiceRegisterMonitor()
    if not (voiceRegisterSummary and voiceRegisterTime and voiceRegisterListText and voiceRegisterListChild and voiceRegisterListScroll) then
        return
    end

    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.GetRegistrationSnapshot) then
        voiceRegisterSummary:SetText(L["语音引擎未就绪，无法读取注册状态。"])
            voiceRegisterTime:SetText("")
        voiceRegisterListText:SetText(L["无数据"])
        voiceRegisterListChild:SetHeight(24)
        return
    end

    local snap = Engine:GetRegistrationSnapshot({ includeRaid = false })
    if type(snap) ~= "table" then
        voiceRegisterSummary:SetText(L["注册快照为空。"])
        voiceRegisterTime:SetText("")
        voiceRegisterListText:SetText(L["无数据"])
        voiceRegisterListChild:SetHeight(24)
        return
    end

    local bossCount = tonumber(snap.bossCount) or 0
    local eventCount = tonumber(snap.eventCount) or 0
    local rawEventCount = tonumber(snap.rawEventCount) or eventCount
    local trigger0Events = tonumber(snap.trigger0Events) or 0
    local trigger1Events = tonumber(snap.trigger1Events) or 0
    local trigger2Events = tonumber(snap.trigger2Events) or 0
    local orphanCount = tonumber(snap.orphanEventCount) or 0
    local filteredByRaid = tonumber(snap.filteredOutByRaid) or 0
    local extra = ""
    if orphanCount > 0 then
        extra = string.format(L["  |  未匹配BOSS事件: %d"], orphanCount)
    end
    if filteredByRaid > 0 then
        extra = extra .. string.format(L["  |  团本已过滤: %d"], filteredByRaid)
    end
    voiceRegisterSummary:SetText(string.format(L["非团本已注册BOSS: %d  |  非团本事件: %d / 全量: %d  |  触发器事件(0/1/2): %d/%d/%d%s"],
        bossCount, eventCount, rawEventCount, trigger0Events, trigger1Events, trigger2Events, extra))

    local stamp = tostring(snap.updatedAt or "")
    if stamp == "" then
        stamp = L["未知"]
    end
    local modeSuffix = (snap.isPreview == true) and L["（预估）"] or L["（实测）"]
    local errSuffix = ""
    if type(snap.error) == "string" and snap.error ~= "" then
        errSuffix = L["  |  最近错误: "] .. snap.error
    end
    local scopeText = ""
    local scopeMapName = tostring(snap.scopeMapName or "")
    local scopeInstanceID = tonumber(snap.scopeInstanceID)
    local scopeEncounterID = tonumber(snap.scopeEncounterID)
    if scopeInstanceID and scopeInstanceID > 0 then
        scopeText = string.format(L["  |  作用域: %s[InstanceID:%d]"], (scopeMapName ~= "" and scopeMapName or L["未知副本"]), scopeInstanceID)
        if scopeEncounterID and scopeEncounterID > 0 then
            scopeText = scopeText .. string.format(" > encounter:%d", scopeEncounterID)
        end
    end
    voiceRegisterTime:SetText(L["最近刷新: "] .. stamp .. modeSuffix .. scopeText .. errSuffix)

    local lines = {}
    local rows = snap.rows
    if type(rows) == "table" and #rows > 0 then
        for i = 1, #rows do
            local row = rows[i]
            local bossName = tostring(row and row.bossName or (L["未知首领 "] .. tostring(row and row.encounterID or i)))
            local n = tonumber(row and row.count) or 0
            local mapName = tostring(row and row.mapName or L["未知副本"])
            local eventIDs = row and row.eventIDs
            local eventDetails = row and row.eventDetails
            local detail = ""
            if type(eventDetails) == "table" and #eventDetails > 0 then
                local chunks = {}
                for j = 1, #eventDetails do
                    local d = eventDetails[j]
                    local eid = tonumber(d and d.eventID) or (d and d.eventID) or "?"
                    local triggerText = tostring(d and d.triggerText or "-")
                    chunks[#chunks + 1] = string.format("%s(%s)", tostring(eid), triggerText)
                end
                detail = "  [eventID(trigger): " .. table.concat(chunks, ",") .. "]"
            elseif type(eventIDs) == "table" and #eventIDs > 0 then
                local ids = {}
                for j = 1, #eventIDs do
                    ids[#ids + 1] = tostring(eventIDs[j]) .. "(-)"
                end
                detail = "  [eventID(trigger): " .. table.concat(ids, ",") .. "]"
            end
            lines[#lines + 1] = string.format("%s > %s (%d)%s", mapName, bossName, n, detail)
        end
    else
        lines[1] = L["暂无非团本已注册BOSS"]
    end

    local text = table.concat(lines, "\n")
    voiceRegisterListText:SetText(text)

    local w = (voiceRegisterListScroll:GetWidth() or 540) - 26
    if w < 120 then w = 120 end
    voiceRegisterListChild:SetWidth(w)
    voiceRegisterListText:SetWidth(w - 6)
    voiceRegisterListChild:SetHeight(math.max(24, (#lines * 20) + 8))
end

RefreshColorControls = function()
    local _, schemes, custom, extraSlots = EnsureColorDB()
    for _, key in ipairs(GetSchemeOrder()) do
        local btn = fixedColorButtons[key]
        local nameFS = fixedColorLabels[key]
        local row = schemes and schemes[key]
        if btn and type(row) == "table" then
            btn._currentDb = row
            if btn.UpdateColor then
                btn:UpdateColor(row.r, row.g, row.b, 1)
            end
        end
        if nameFS then
            nameFS:SetText(GetSchemeDisplayName(key))
        end
    end

    if customNameInput and type(custom) == "table" then
        if not customNameInput:HasFocus() then
            customNameInput:SetText(custom.name or L["自定义方案"])
        end
    end
    if customColorButton and type(custom) == "table" then
        customColorButton._currentDb = custom
        if customColorButton.UpdateColor then
            customColorButton:UpdateColor(custom.r, custom.g, custom.b, 1)
        end
    end

    for i = 1, GetExtraCustomCount() do
        local row = type(extraSlots) == "table" and extraSlots[i] or nil
        local cb = extraCustomEnableChecks[i]
        local nameInput = extraCustomNameInputs[i]
        local colorBtn = extraCustomColorButtons[i]
        if cb and cb.SetChecked then
            cb:SetChecked(row and row.enabled == true)
        end
        if nameInput and type(row) == "table" then
            if not nameInput:HasFocus() then
                nameInput:SetText(row.name or (L["额外方案"] .. tostring(i)))
            end
        end
        if colorBtn and type(row) == "table" then
            colorBtn._currentDb = row
            if colorBtn.UpdateColor then
                colorBtn:UpdateColor(row.r, row.g, row.b, 1)
            end
        end
    end
end

local function ClearButtons()
    for _, b in ipairs(activeButtons) do
        b:Hide()
        b:ClearAllPoints()
        b:SetScript("OnClick", nil)
        if b._sidebarKind == "header" then
            headerPool[#headerPool + 1] = b
        else
            buttonPool[#buttonPool + 1] = b
        end
    end
    wipe(activeButtons)
end

local function AcquireListButton()
    local b = table.remove(buttonPool)
    if b then
        b:SetParent(listChild)
        return b
    end

    if ExBoss.UI and ExBoss.UI.CreateSidebarModuleButton then
        b = ExBoss.UI.CreateSidebarModuleButton(listChild)
    else
        b = CreateFrame("Button", nil, listChild)
        b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.fs:SetPoint("LEFT", 14, 0)
        b.fs:SetPoint("RIGHT", -8, 0)
        b.fs:SetJustifyH("LEFT")
        b.label = b.fs
    end
    b._sidebarKind = "item"
    return b
end

local function AcquireHeaderButton()
    local b = table.remove(headerPool)
    if b then
        b:SetParent(listChild)
        return b
    end
    if ExBoss.UI and ExBoss.UI.CreateSidebarCategoryHeader then
        b = ExBoss.UI.CreateSidebarCategoryHeader(listChild)
    else
        b = CreateFrame("Button", nil, listChild)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.label:SetAllPoints()
        b.label:SetJustifyH("LEFT")
    end
    b._sidebarKind = "header"
    return b
end

local function SetupListButton(button, height, leftInset)
    button:SetHeight(height)
    local label = button.label or button.fs
    label:ClearAllPoints()
    label:SetPoint("LEFT", leftInset or 14, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    button:Enable()
end

local function ItemMatchesSearch(item)
    if searchText == "" then
        return true
    end
    if not ExBoss.UI or not ExBoss.UI.SidebarTextContains then
        return true
    end
    return ExBoss.UI.SidebarTextContains(GetTitle(item), searchText)
        or ExBoss.UI.SidebarTextContains(GetDesc(item), searchText)
        or ExBoss.UI.SidebarTextContains(item.key, searchText)
        or ExBoss.UI.SidebarTextContains(item.moduleKey, searchText)
end

local function HideEmbeddedPages()
    local pages = {
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtraPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ConditionsPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ImportExportPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.PrivateAuraMonitorPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TargetAlertPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.MythicCastPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
    }
    for _, page in ipairs(pages) do
        if page and page._scrollFrame then
            page._scrollFrame:Hide()
            if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == page._scrollChild then
                ExwindTools.UI.ActivePageFrame = nil
                ExwindTools.UI.CurrentModule = nil
            end
        end
    end
end

local function ShowBuiltinLayout(show)
    if titleText then
        if show then titleText:Show() else titleText:Hide() end
    end
    if titleSep then
        if show then titleSep:Show() else titleSep:Hide() end
    end
    if descText then
        if show then descText:Show() else descText:Hide() end
    end
end

local function RefreshRight()
    local item = ITEMS[selectedIndex] or ITEMS[1]
    local key = item and item.key or "overview"

    HideEmbeddedPages()
    if overviewSection then overviewSection:Hide() end
    if voiceSection then voiceSection:Hide() end
    if voiceRegisterSection then voiceRegisterSection:Hide() end
    if colorSection then colorSection:Hide() end
    if trashCDSection then trashCDSection:Hide() end
    if partyFrameGlow.section then partyFrameGlow.section:Hide() end
    if dungeonExtra.section then dungeonExtra.section:Hide() end
    if resetSection then resetSection:Hide() end
    if embedPlaceholder then embedPlaceholder:Hide() end

    if item and item.mode == "embedded" then
        if rightScrollFrame then
            rightScrollFrame:Hide()
        end
        if rightRoot then
            rightRoot:Hide()
        end
        ShowBuiltinLayout(false)

        local pageMap = {
            overview = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
            countdownvoice = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
            batchedit = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
            timerbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
            bunbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
            countdown = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
            flashtext = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextPage,
            flashtextmedium = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
            ringprogress         = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
            iconalert            = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
            castprogressbar      = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
            extrashieldbar       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
            dungeonextra         = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtraPage,
            conditions           = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ConditionsPage,
            privateauramonitor   = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.PrivateAuraMonitorPage,
            targetalert          = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TargetAlertPage,
            mythiccast           = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.MythicCastPage,
            trashcd              = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
        }
        local page = pageMap[key]
        if page and page.Render then
            page:Render(embeddedHostFrame)
        elseif embedPlaceholder then
            embedPlaceholder:SetText((GetTitle(item) or L["设置页"]) .. L[" 未就绪"])
            embedPlaceholder:Show()
        end
        return
    end

    if rightScrollFrame then
        rightScrollFrame:SetVerticalScroll(0)
        rightScrollFrame:Show()
    end
    if rightRoot then
        rightRoot:Show()
    end
    ShowBuiltinLayout(true)
    if titleText then
        titleText:SetText(item and GetTitle(item) or L["通用设置"])
    end
    if descText then
        descText:SetText(item and GetDesc(item) or "")
    end

    if key == "overview" then
        if overviewSection then overviewSection:Show() end
    elseif key == "voice" then
        if voiceSection then voiceSection:Show() end
    elseif key == "voiceregister" then
        if voiceRegisterSection then
            voiceRegisterSection:Show()
            RefreshVoiceRegisterMonitor()
        end
    elseif key == "color" then
        if colorSection then colorSection:Show() end
    elseif key == "trashcd" then
        if trashCDSection then
            trashCDSection:Show()
            RefreshTrashCDControls()
        end
    elseif key == "partyframeglow" then
        if partyFrameGlow.section then
            partyFrameGlow.section:Show()
            RefreshPartyFrameGlowControls()
        end
    elseif key == "reset" then
        if resetSection then resetSection:Show() end
    end
end

local function RefreshList()
    if not listChild then return end
    ClearButtons()

    local y = -6
    local shown = 0
    for _, category in ipairs(CATEGORIES) do
        local matchedItems = {}
        for i, item in ipairs(ITEMS) do
            if item.category == category.key and ItemMatchesSearch(item) then
                matchedItems[#matchedItems + 1] = { index = i, item = item }
            end
        end

        if #matchedItems > 0 then
            local header = AcquireHeaderButton()
            SetupListButton(header, 26, 0)
            header:SetPoint("TOPLEFT", 10, y)
            header:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
            header.label:SetText(GetTitle(category))
            header:SetScript("OnClick", nil)
            activeButtons[#activeButtons + 1] = header
            header:Show()
            y = y - 30
            shown = shown + 1

            for _, row in ipairs(matchedItems) do
                local i = row.index
                local item = row.item
                local b = AcquireListButton()
                SetupListButton(b, 30, 34)
                b:SetPoint("TOPLEFT", 10, y)
                b:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)

                local label = b.label or b.fs
                label:SetText(GetTitle(item) or (L["条目 "] .. tostring(i)))
                if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and b.label then
                    ExBoss.UI.ApplySidebarModuleButtonState(b, selectedIndex == i, true)
                end

                b:SetScript("OnClick", function()
                    selectedIndex = i
                    EnsureSelectedCategoryExpanded()
                    RefreshList()
                    RefreshRight()
                end)

                activeButtons[#activeButtons + 1] = b
                b:Show()
                y = y - 34
                shown = shown + 1
            end
            y = y - 6
        end
    end

    if shown == 0 then
        local empty = AcquireListButton()
        SetupListButton(empty, 30, 34)
        empty:SetPoint("TOPLEFT", 10, y)
        empty:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
        local label = empty.label or empty.fs
        label:SetText(L["没有匹配项"])
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and empty.label then
            ExBoss.UI.ApplySidebarModuleButtonState(empty, false, false)
        else
            label:SetTextColor(0.45, 0.48, 0.55, 1)
        end
        empty:Show()
        activeButtons[#activeButtons + 1] = empty
        y = y - 32
    end

    listChild:SetHeight(math.max(1, -y + 8))
end

local function BuildTrashCDSection(parent, anchor, EXUI)
    trashCDSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    trashCDSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    trashCDSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    trashCDSection:SetHeight(1260)
    trashCDSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    trashCDSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    trashCDSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local trashTitle = trashCDSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trashTitle:SetPoint("TOPLEFT", 10, -8)
    trashTitle:SetText(L["小怪CD全局设置"])
    trashTitle:SetTextColor(1, 0.82, 0.45)

    local function CreateSectionHeader(parentFrame, text, topY)
        local header = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 10, topY)
        header:SetText(text)
        header:SetTextColor(1, 0.82, 0.45)

        local line = parentFrame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 0.82, 0.45, 0.30)
        line:SetPoint("TOPLEFT", 10, topY - 22)
        line:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -10, topY - 22)
        line:SetHeight(1)

        return header, line
    end

    CreateSectionHeader(trashCDSection, L["计时规则"], -34)

    if EXUI and EXUI.CreateCheckbox then
        trashHideLongCheck = EXUI:CreateCheckbox(
            trashCDSection,
            L["隐藏"],
            EnsureTrashSettingsDB().hideLongTimerBarEnabled == true,
            function(checked)
                local db = EnsureTrashSettingsDB()
                db.hideLongTimerBarEnabled = (checked == true)
                RefreshTrashCDControls()
                PublishTrashCDSettingsChanged("hideLongTimerBarEnabled")
            end
        )
        trashHideLongCheck:SetPoint("TOPLEFT", 10, -64)
    end

    if EXUI and EXUI.CreateEditBox then
        trashHideLongInput = EXUI:CreateEditBox(
            trashCDSection,
            tostring(math.max(0, tonumber(EnsureTrashSettingsDB().hideLongTimerBarSeconds) or 0)),
            180,
            32,
            L["秒以上的计时条"],
            {
                onEditFocusLost = function(text)
                    local db = EnsureTrashSettingsDB()
                    db.hideLongTimerBarSeconds = math.max(0, tonumber(text) or 0)
                    RefreshTrashCDControls()
                    PublishTrashCDSettingsChanged("hideLongTimerBarSeconds")
                end,
                onEnter = function(text)
                    local db = EnsureTrashSettingsDB()
                    db.hideLongTimerBarSeconds = math.max(0, tonumber(text) or 0)
                    RefreshTrashCDControls()
                    PublishTrashCDSettingsChanged("hideLongTimerBarSeconds")
                end,
            }
        )
        trashHideLongInput:SetPoint("TOPLEFT", 136, -58)
    end

    if EXUI and EXUI.CreateCheckbox then
        trashKeepReadyCheck = EXUI:CreateCheckbox(
            trashCDSection,
            L["技能冷却结束后"],
            EnsureTrashSettingsDB().keepTimerBarAfterReadyEnabled == true,
            function(checked)
                local db = EnsureTrashSettingsDB()
                db.keepTimerBarAfterReadyEnabled = (checked == true)
                RefreshTrashCDControls()
                PublishTrashCDSettingsChanged("keepTimerBarAfterReadyEnabled")
            end
        )
        trashKeepReadyCheck:SetPoint("TOPLEFT", 10, -118)
    end

    if EXUI and EXUI.CreateEditBox then
        trashKeepReadyInput = EXUI:CreateEditBox(
            trashCDSection,
            tostring(math.max(0, tonumber(EnsureTrashSettingsDB().keepTimerBarAfterReadySeconds) or 0)),
            180,
            32,
            L["秒隐藏"],
            {
                onEditFocusLost = function(text)
                    local db = EnsureTrashSettingsDB()
                    db.keepTimerBarAfterReadySeconds = math.max(0, tonumber(text) or 0)
                    RefreshTrashCDControls()
                    PublishTrashCDSettingsChanged("keepTimerBarAfterReadySeconds")
                end,
                onEnter = function(text)
                    local db = EnsureTrashSettingsDB()
                    db.keepTimerBarAfterReadySeconds = math.max(0, tonumber(text) or 0)
                    RefreshTrashCDControls()
                    PublishTrashCDSettingsChanged("keepTimerBarAfterReadySeconds")
                end,
            }
        )
        trashKeepReadyInput:SetPoint("TOPLEFT", 236, -112)
    end

    CreateSectionHeader(trashCDSection, L["姓名版设置"], -154)

    if EXUI and EXUI.CreateDropdown then
        trashNameplateSideDropdown = EXUI:CreateDropdown(
            trashCDSection,
            160,
            L["姓名版图标方向"],
            GetTrashNameplateSideOptions(),
            tostring(EnsureTrashSettingsDB().nameplateGrowthSide or "left"),
            function(val)
                local db = EnsureTrashSettingsDB()
                db.nameplateGrowthSide = (tostring(val or "left") == "right") and "right" or "left"
                RefreshTrashCDControls()
                PublishTrashCDSettingsChanged("nameplateGrowthSide")
            end,
            true
        )
        trashNameplateSideDropdown:SetPoint("TOPLEFT", 10, -224)

        trashNameplateStrataDropdown = EXUI:CreateDropdown(
            trashCDSection,
            160,
            L["姓名版图标层级"],
            GetTrashNameplateStrataOptions(),
            tostring(EnsureTrashSettingsDB().nameplateIconStrata or "DIALOG"),
            function(val)
                local db = EnsureTrashSettingsDB()
                EnsureTrashNameplateIconDB()
                db.nameplateIconStrata = tostring(val or "DIALOG"):upper()
                RefreshTrashCDControls()
                PublishTrashCDSettingsChanged("nameplateIconStrata")
            end,
            true
        )
        trashNameplateStrataDropdown:SetPoint("TOPLEFT", 10, -274)
    end

    if ExBoss.UI and ExBoss.UI.CreateIconGroupV2 then
        EnsureTrashNameplateIconDB()
        trashNameplateIconGroup = ExBoss.UI.CreateIconGroupV2(
            trashCDSection,
            740,
            L["姓名版图标参数"],
            EnsureTrashSettingsDB(),
            "nameplateIcon",
            PublishTrashNameplateIconChanged
        )
        trashNameplateIconGroup:SetPoint("TOPLEFT", 10, -310)
    end

    if EXUI and EXUI.CreateFontGroup then
        trashNameplateTextFontGroup = EXUI:CreateFontGroup(
            trashCDSection,
            740,
            L["姓名版倒数字体参数"],
            EnsureTrashNameplateIconTextDB(),
            PublishTrashNameplateIconTextChanged
        )
        trashNameplateTextFontGroup:SetPoint("TOPLEFT", 10, -600)
    end

    trashNameplatePreview = BuildTrashNameplatePreview(trashCDSection)
    trashNameplatePreview:SetPoint("TOPLEFT", 250, -196)

    CreateSectionHeader(trashCDSection, L["说明"], -844)

    local trashDesc = trashCDSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trashDesc:SetPoint("TOPLEFT", 10, -874)
    trashDesc:SetPoint("RIGHT", trashCDSection, "RIGHT", -10, 0)
    trashDesc:SetJustifyH("LEFT")
    trashDesc:SetTextColor(0.85, 0.85, 0.9)
    trashDesc:SetText(L["隐藏 X 秒以上的计时条：只在最后 X 秒显示小怪计时条。\n技能冷却结束后 X 秒隐藏：条子到点后若怪物尚未成功施法，会停在 0 继续保留；成功施法后才进入下一轮 CD，或超过额外 X 秒后隐藏。\n隐藏NPCID只隐藏姓名版上方的识别文字，不影响内置CD图标。\n姓名版图标参数控制图标本体；姓名版倒数字体参数控制图标上的数字大小、颜色、字体、描边和偏移。"])
    trashCDSection:Hide()
end

local function BuildPartyFrameGlowSection(parent, anchor, EXUI)
    partyFrameGlow.section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    partyFrameGlow.section:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    partyFrameGlow.section:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    partyFrameGlow.section:SetHeight(520)
    partyFrameGlow.section:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    partyFrameGlow.section:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    partyFrameGlow.section:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local title = partyFrameGlow.section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["团队框架发光"])
    title:SetTextColor(1, 0.82, 0.45)

    local desc = partyFrameGlow.section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 10, -30)
    desc:SetPoint("RIGHT", partyFrameGlow.section, "RIGHT", -10, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.82, 0.84, 0.9)
    desc:SetText(L["这里配置通用队伍/团队框架发光样式。它只负责框架发光本身，具体机制模块是否使用这套默认样式由模块调用时决定。"])

    local db = EnsurePartyFrameGlowDB()
    if EXUI and EXUI.CreateGlowSettings then
        partyFrameGlow.glowSettings = EXUI:CreateGlowSettings(
            partyFrameGlow.section,
            780,
            L["默认发光样式"],
            db,
            "glow",
            RefreshPartyFrameGlowControls
        )
        partyFrameGlow.glowSettings:SetPoint("TOPLEFT", 10, -74)
    else
        local missing = partyFrameGlow.section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        missing:SetPoint("TOPLEFT", 10, -74)
        missing:SetTextColor(1, 0.35, 0.35)
        missing:SetText(L["EXUI:CreateGlowSettings 不可用，无法渲染发光参数。"])
    end

    if EXUI and EXUI.CreateSlider then
        partyFrameGlow.durationSlider = EXUI:CreateSlider(
            partyFrameGlow.section,
            225,
            L["默认持续时间"],
            0.5,
            15,
            db.duration or 5,
            0.5,
            function(v)
                return string.format(L["%.1f 秒"], tonumber(v) or 0)
            end,
            function(v)
                local settings = EnsurePartyFrameGlowDB()
                settings.duration = math.max(0.5, math.min(15, tonumber(v) or 5))
                RefreshPartyFrameGlowControls()
            end
        )
        partyFrameGlow.durationSlider:SetPoint("TOPLEFT", 10, -368)
    end

    if EXUI and EXUI.CreateButton then
        local previewSelf = EXUI:CreateButton(partyFrameGlow.section, 130, 28, L["预览自己"], function()
            PreviewPartyFrameGlow(GetPartyFrameGlowPreviewUnits(false))
        end)
        previewSelf:SetPoint("TOPLEFT", 270, -370)

        local previewGroup = EXUI:CreateButton(partyFrameGlow.section, 150, 28, L["预览当前队伍"], function()
            PreviewPartyFrameGlow(GetPartyFrameGlowPreviewUnits(true))
        end)
        previewGroup:SetPoint("TOPLEFT", 410, -370)

        local stopPreview = EXUI:CreateButton(partyFrameGlow.section, 120, 28, L["停止预览"], function()
            StopPartyFrameGlowPreview()
            if partyFrameGlow.statusText then
                partyFrameGlow.statusText:SetText(L["预览已停止。"])
            end
        end)
        stopPreview:SetPoint("TOPLEFT", 570, -370)
    end

    partyFrameGlow.statusText = partyFrameGlow.section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    partyFrameGlow.statusText:SetPoint("TOPLEFT", 10, -420)
    partyFrameGlow.statusText:SetPoint("RIGHT", partyFrameGlow.section, "RIGHT", -10, 0)
    partyFrameGlow.statusText:SetJustifyH("LEFT")
    partyFrameGlow.statusText:SetTextColor(0.85, 0.9, 1)
    partyFrameGlow.statusText:SetText(L["可用上方按钮测试当前样式。"])

    local note = partyFrameGlow.section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 10, -452)
    note:SetPoint("RIGHT", partyFrameGlow.section, "RIGHT", -10, 0)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.72, 0.76, 0.84)
    note:SetText(L["查找顺序：PlayerFrame、PartyFrame、CompactPartyFrame、CompactRaidFrame，再递归扫描 UIParent。第三方队伍框架如果没有标准 unit 属性，可能需要单独适配。"])

    partyFrameGlow.section:Hide()
end

function Page.BuildDungeonExtraSection(parent, anchor, EXUI)
    dungeonExtra.section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dungeonExtra.section:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    dungeonExtra.section:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    dungeonExtra.section:SetHeight(1160)
    dungeonExtra.section:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dungeonExtra.section:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    dungeonExtra.section:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local title = dungeonExtra.section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["副本额外功能"])
    title:SetTextColor(1, 0.82, 0.45)

    local dogTitle = dungeonExtra.section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dogTitle:SetPoint("TOPLEFT", 10, -38)
    dogTitle:SetText(L["执政团之座 2号 - 狗跳点名"])
    dogTitle:SetTextColor(0.35, 0.95, 1)

    local desc = dungeonExtra.section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 10, -64)
    desc:SetPoint("RIGHT", dungeonExtra.section, "RIGHT", -10, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.82, 0.84, 0.9)
    desc:SetText(L["实战只在 encounterID=2066 且事件237附近扫描队友有害光环实例ID，用最近两次目标排除下次候选。预览会显示样例面板并让候选队友框架发光，不写入实战记录。"])

    if EXUI and EXUI.CreateCheckbox then
        dungeonExtra.dogJumpEnabledCheck = EXUI:CreateCheckbox(
            dungeonExtra.section,
            L["启用狗跳点名模块"],
            true,
            function(checked)
                local DogJump = GetDogJumpTracker()
                if DogJump and DogJump.SetEnabled then
                    DogJump:SetEnabled(checked == true)
                end
                RefreshDungeonExtraControls()
            end
        )
        dungeonExtra.dogJumpEnabledCheck:SetPoint("TOPLEFT", 10, -108)

        dungeonExtra.dogJumpPreviewCheck = EXUI:CreateCheckbox(
            dungeonExtra.section,
            L["预览狗跳点名面板"],
            false,
            function(checked)
                local DogJump = GetDogJumpTracker()
                if DogJump and DogJump.SetPreview then
                    DogJump:SetPreview(checked == true)
                end
                RefreshDungeonExtraControls()
            end
        )
        dungeonExtra.dogJumpPreviewCheck:SetPoint("TOPLEFT", 10, -148)
    end

    local editBtn = CreateFrame("Button", nil, dungeonExtra.section, "UIPanelButtonTemplate")
    editBtn:SetSize(120, 24)
    editBtn:SetPoint("TOPLEFT", 10, -188)
    editBtn:SetText(L["进入编辑模式"])
    editBtn:SetScript("OnClick", function()
        local TrashAbsorb = GetTrash248690AbsorbModule()
        if TrashAbsorb and TrashAbsorb.ToggleEditMode then
            TrashAbsorb:ToggleEditMode()
        elseif ExwindTools and ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
        RefreshDungeonExtraControls()
    end)
    dungeonExtra.trash248690EditButton = editBtn

    local panelDB = EnsureTrash248690PanelDB()
    if EXUI and EXUI.CreateSlider then
        dungeonExtraTrashMaxBarsSlider = EXUI:CreateSlider(
            dungeonExtra.section,
            225,
            L["最多显示几个"],
            1,
            8,
            tonumber(panelDB.maxVisibleBars) or 6,
            1,
            function(v)
                return string.format("%d", math.floor(tonumber(v) or 0))
            end,
            function(v)
                local db = EnsureTrash248690PanelDB()
                db.maxVisibleBars = math.max(1, math.min(8, math.floor(tonumber(v) or 6)))
                local TrashAbsorb = GetTrash248690AbsorbModule()
                if TrashAbsorb and TrashAbsorb.RefreshVisuals then
                    TrashAbsorb:RefreshVisuals()
                end
            end
        )
        dungeonExtraTrashMaxBarsSlider:SetPoint("TOPLEFT", 150, -182)

        dungeonExtraTrashGapSlider = EXUI:CreateSlider(
            dungeonExtra.section,
            225,
            L["上下间距"],
            0,
            30,
            tonumber(panelDB.stackGap) or 4,
            1,
            function(v)
                return string.format("%d", math.floor(tonumber(v) or 0))
            end,
            function(v)
                local db = EnsureTrash248690PanelDB()
                db.stackGap = math.max(0, math.min(30, math.floor(tonumber(v) or 4)))
                local TrashAbsorb = GetTrash248690AbsorbModule()
                if TrashAbsorb and TrashAbsorb.RefreshVisuals then
                    TrashAbsorb:RefreshVisuals()
                end
            end
        )
        dungeonExtraTrashGapSlider:SetPoint("TOPLEFT", 390, -182)
    end

    local styleHost = CreateFrame("Frame", nil, dungeonExtra.section)
    styleHost:SetPoint("TOPLEFT", 10, -236)
    styleHost:SetPoint("TOPRIGHT", dungeonExtra.section, "TOPRIGHT", -10, -236)
    styleHost:SetHeight(920)
    dungeonExtra.trash248690StyleHost = styleHost

    local vordazaEditBtn = CreateFrame("Button", nil, dungeonExtra.section, "UIPanelButtonTemplate")
    vordazaEditBtn:SetSize(120, 24)
    vordazaEditBtn:SetPoint("TOPLEFT", 10, -1170)
    vordazaEditBtn:SetText(L["进入编辑模式"])
    vordazaEditBtn:SetScript("OnClick", function()
        local VordazaShield = GetVordazaShieldModule()
        if VordazaShield and VordazaShield.ToggleEditMode then
            VordazaShield:ToggleEditMode()
        elseif ExwindTools and ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
        RefreshDungeonExtraControls()
    end)
    dungeonExtra.vordazaShieldEditButton = vordazaEditBtn

    dungeonExtra.section:Hide()
end

local function EnsureUI(leftFrame, contentFrame)
    if leftRoot and rightRoot then return end

    leftRoot = CreateFrame("Frame", nil, leftFrame)
    leftRoot:SetAllPoints(leftFrame)

    sidebarDivider = leftRoot:CreateTexture(nil, "ARTWORK")
    sidebarDivider:SetWidth(1)
    sidebarDivider:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -2, -2)
    sidebarDivider:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -2, 2)
    sidebarDivider:SetColorTexture(0.12, 0.15, 0.20, 0.9)

    if ExBoss.UI and ExBoss.UI.CreateSidebarSearchBox then
        searchBox = ExBoss.UI.CreateSidebarSearchBox(leftRoot, searchText, {
            placeholder = L["搜索设置..."],
            onChanged = function(text)
                local normalized = ExBoss.UI.NormalizeSidebarSearchText and ExBoss.UI.NormalizeSidebarSearchText(text) or tostring(text or "")
                if normalized == searchText then
                    return
                end
                searchText = normalized
                if listScroll and listScroll.SetVerticalScroll then
                    listScroll:SetVerticalScroll(0)
                end
                RefreshList()
            end,
        })
        searchBox:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -5)
        searchBox:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -22, -5)
    end

    listScroll = CreateFrame("ScrollFrame", nil, leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -40)
    listScroll:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -22, 5)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(340, 1)
    listScroll:SetScrollChild(listChild)

    rightScrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(rightScrollFrame)
    end
    rightRoot = CreateFrame("Frame", nil, rightScrollFrame)
    rightRoot:SetPoint("TOPLEFT", 0, 0)
    rightRoot:SetSize(math.max((contentFrame:GetWidth() or 0) - 28, 760), 1600)
    rightScrollFrame:SetScrollChild(rightRoot)

    titleText = rightRoot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 14, -14)
    titleText:SetTextColor(1, 0.82, 0.45)

    local sep = rightRoot:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
    sep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
    sep:SetHeight(1)
    sep:SetColorTexture(1, 1, 1, 0.18)
    titleSep = sep

    descText = rightRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    descText:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
    descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetWordWrap(true)
    descText:SetTextColor(0.88, 0.88, 0.9)

    embedPlaceholder = rightRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    embedPlaceholder:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -14)
    embedPlaceholder:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    embedPlaceholder:SetJustifyH("LEFT")
    embedPlaceholder:SetTextColor(0.75, 0.75, 0.8, 1)
    embedPlaceholder:Hide()

    local EXUI = ExwindTools.UI

    CreateOverviewSection(rightRoot, descText, EXUI)
    CreateVoiceSection(rightRoot, descText, EXUI)
    CreateVoiceRegisterSection(rightRoot, descText)
    CreateColorSection(rightRoot, descText, EXUI)

    BuildTrashCDSection(rightRoot, descText, EXUI)
    BuildPartyFrameGlowSection(rightRoot, descText, EXUI)
    ExBoss.UI.Panel.GlobalSettingsPage.BuildDungeonExtraSection(rightRoot, descText, EXUI)

    CreateResetSection(rightRoot, descText)
end

function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then return end
    embeddedHostFrame = contentFrame
    EnsureUI(leftFrame, contentFrame)
    if selectedIndex < 1 or selectedIndex > #ITEMS then
        selectedIndex = 1
    end
    EnsureSelectedCategoryExpanded()

    leftRoot:SetParent(leftFrame)
    leftRoot:ClearAllPoints()
    leftRoot:SetAllPoints(leftFrame)
    leftRoot:Show()

    rightScrollFrame:SetParent(contentFrame)
    rightScrollFrame:ClearAllPoints()
    rightScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    rightScrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 0)
    rightRoot:SetWidth(math.max((contentFrame:GetWidth() or 0) - 28, 760))

    RefreshList()
    RefreshGeneralControls()
    RefreshVoiceControls()
    RefreshVoiceRegisterMonitor()
    RefreshColorControls()
    RefreshTrashCDControls()
    RefreshPartyFrameGlowControls()
    RefreshDungeonExtraControls()
    RefreshRight()
end

function Page:Hide()
    StopPartyFrameGlowPreview()
    HideEmbeddedPages()
    if leftRoot then leftRoot:Hide() end
    if rightRoot then rightRoot:Hide() end
    if rightScrollFrame then rightScrollFrame:Hide() end
end

function Page:SetSelectedKey(key)
    if type(key) ~= "string" or key == "" then return end
    local index = FindItemIndexByKey(key)
    if index then
        selectedIndex = index
        EnsureSelectedCategoryExpanded()
    end

    if leftRoot and rightRoot and leftRoot:IsShown() and rightRoot:IsShown() then
        RefreshList()
        RefreshGeneralControls()
        RefreshVoiceControls()
        RefreshColorControls()
        RefreshTrashCDControls()
        RefreshPartyFrameGlowControls()
        RefreshDungeonExtraControls()
        RefreshRight()
    end
end

if ExwindTools.WatchState and not dungeonExtra.watchRegistered then
    dungeonExtra.watchRegistered = true
    ExwindTools:WatchState("ExBoss.Boss.DogJumpTracker.SettingsChanged", "ExBoss.GlobalSettings.DungeonExtra", function()
        RefreshDungeonExtraControls()
    end)
    if ExwindTools.RegisterEditModeHandler then
        ExwindTools:RegisterEditModeHandler("ExBoss.GlobalSettings.DungeonExtra", {
            RefreshEditMode = function()
                RefreshDungeonExtraControls()
            end,
        })
    end
end
