-- =============================================================
-- [[ EXBoss Tools: InterruptTracker ]]
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L                        = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY        = "ExBoss.Tools.InterruptTracker"
local DISPLAY_STYLE_BAR        = "bar"
local DISPLAY_STYLE_LIST       = "list"
local GROW_DIRECTION_DOWN      = "DOWN"
local GROW_DIRECTION_UP        = "UP"
local PartySpec                = ExwindTools.PartySpec
local EXDB                     = _G.EXDB
local C_Spell                  = _G.C_Spell
local LSM                      = LibStub("LibSharedMedia-3.0")

-- 常用全局函数引用
local UnitGUID                 = _G.UnitGUID
local UnitName                 = _G.UnitName
local UnitClass                = _G.UnitClass
local UnitNameFromGUID         = _G.UnitNameFromGUID
local UnitClassFromGUID        = _G.UnitClassFromGUID
local UnitTokenFromGUID        = _G.UnitTokenFromGUID
local UnitExists               = _G.UnitExists
local GetTime                  = _G.GetTime
local CreateFrame              = _G.CreateFrame
local UIParent                 = _G.UIParent
local C_Timer                  = _G.C_Timer
local wipe                     = _G.wipe
local GetSpecialization        = _G.GetSpecialization
local GetSpecializationInfo    = _G.GetSpecializationInfo
local C_ClassColor             = _G.C_ClassColor
local GetInstanceInfo          = _G.GetInstanceInfo
local C_ChallengeMode          = _G.C_ChallengeMode
local IsInRaid                 = _G.IsInRaid
local GetNumGroupMembers       = _G.GetNumGroupMembers
local GetRaidTargetIndex       = _G.GetRaidTargetIndex
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local anchorFrame              = nil
local anchorController         = nil
local isEditModeActive         = false
local isEditModeVisible        = true
local editHandleFrame          = nil
local EX_DB                    = nil

local playerSelfBar            = nil   -- 玩家自己的永久打断计时条
local playerSelfBarOnCD        = false -- 是否处于CD中
local playerSelfBarStartTime   = 0     -- CD开始时间
local playerSelfBarDuration    = 0     -- CD总时长
local RefreshPlayerSelfBar, ReleasePlayerSelfBar, SetupPlayerSelfBarOnUpdate

local function RefreshEditOverlay() end

local function IsGrowUp()
    return EX_DB and EX_DB.growDirection == GROW_DIRECTION_UP
end

local function GetStandaloneAnchorPoint()
    return IsGrowUp() and "BOTTOM" or "TOP"
end

local function ApplyStandaloneAnchorPosition()
    if not anchorFrame then return end
    if anchorController then
        anchorController:ApplyPosition()
        return
    end
    local db = EX_DB or EX_DEFAULTS
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(GetStandaloneAnchorPoint(), UIParent, "CENTER", db.posX or 0, db.posY or 0)
end

local function SaveStandaloneAnchorPosition()
    if not anchorFrame or not EX_DB then return end
    if anchorController then
        anchorController:SavePosition()
        return
    end

    local left = anchorFrame.GetLeft and anchorFrame:GetLeft() or nil
    local right = anchorFrame.GetRight and anchorFrame:GetRight() or nil
    local top = anchorFrame.GetTop and anchorFrame:GetTop() or nil
    local bottom = anchorFrame.GetBottom and anchorFrame:GetBottom() or nil
    local sx = (left and right) and ((left + right) / 2) or nil
    local sy = IsGrowUp() and bottom or top
    local cx, cy = UIParent:GetCenter()

    if sx and sy and cx and cy then
        EX_DB.posX = math.floor(sx - cx)
        EX_DB.posY = math.floor(sy - cy)
    end
end

-- 使用 EXDB.InterruptData
local SPEC_INTERRUPT_DB = EXDB.InterruptData


-- =============================================================
-- Grid 布局
-- =============================================================




local EX_LAYOUT

local function EX_RegisterLayout()
    EX_LAYOUT = {
        { key = "header", type = "header", x = 1, y = 1, w = 55, h = 2, label = L["打断监控"], labelSize = 25 },
        { key = "enabled", type = "checkbox", x = 1, y = 4, w = 6, h = 2, label = L["启用"] },
        { key = "locked", type = "checkbox", x = 12, y = 4, w = 8, h = 2, label = L["锁定位置"] },
        { key = "preview", type = "checkbox", x = 24, y = 4, w = 8, h = 2, label = L["预览模式"] },
        { key = "btn_reset_pos", type = "button", x = 42, y = 4, w = 14, h = 2, label = L["重置位置"] },
        { key = "attachToCustom", type = "checkbox", x = 1, y = 8, w = 10, h = 2, label = L["自由依附"] },
        { key = "customAttachTarget", type = "input", x = 12, y = 8, w = 24, h = 2, label = L["目标路径"] },
        { key = "btn_pick_frame", type = "button", x = 42, y = 8, w = 14, h = 2, label = L["鼠标选取"] },
        { key = "posX", type = "slider", x = 1, y = 12, w = 15, h = 2, label = L["整体水平位置"], min = -1000, max = 1000 },
        { key = "posY", type = "slider", x = 17, y = 12, w = 15, h = 2, label = L["整体垂直位置"], min = -1000, max = 1000 },
        { key = "color_header", type = "header", x = 1, y = 16, w = 55, h = 2, label = L["计时条"], labelSize = 22 },
        { key = "spacing", type = "slider", x = 1, y = 20, w = 17, h = 2, label = L["垂直间距"], min = 0, max = 50 },
        {
            key = "growDirection",
            type = "dropdown",
            x = 20,
            y = 20,
            w = 15,
            h = 2,
            label = L["增长方向"],
            items = {
                { L["向下"], GROW_DIRECTION_DOWN },
                { L["向上"], GROW_DIRECTION_UP },
            }
        },
        { key = "useClassColorBar", type = "checkbox", x = 39, y = 20, w = 15, h = 2, label = L["使用职业颜色"] },
        { key = "timerGroup", type = "timerBarGroup", x = 1, y = 23, w = 55, h = 22, label = L["计时条外观"], labelSize = 20 },
        { key = "font_name_header", type = "header", x = 1, y = 47, w = 54, h = 3, label = L["玩家名称"], labelSize = 22 },
        { key = "showPlayerName", type = "checkbox", x = 1, y = 51, w = 15, h = 2, label = L["显示玩家名字"], labelSize = 18 },
        {
            key = "nameAlign",
            type = "dropdown",
            x = 16,
            y = 51,
            w = 13,
            h = 2,
            label = L["名字对齐方式"],
            items = {
                { L["左对齐"], "LEFT" },
                { L["居中"], "CENTER" },
                { L["右对齐"], "RIGHT" },
            }
        },
        { key = "useClassColorName", type = "checkbox", x = 34, y = 51, w = 15, h = 2, label = L["使用职业颜色"] },
        { key = "font_name", type = "fontgroup", x = 1, y = 54, w = 55, h = 15, label = L["玩家名字文字设置"], labelSize = 20 },
        { key = "font_timer_header", type = "header", x = 1, y = 71, w = 55, h = 2, label = L["冷却时间设置"], labelSize = 22 },
        { key = "showTimer", type = "checkbox", x = 1, y = 74, w = 15, h = 2, label = L["显示剩余时间"] },
        { key = "font_timer", type = "fontgroup", x = 1, y = 77, w = 55, h = 15, label = L["时间文字设置"], labelSize = 20 },
        { key = "raid_icon_header", type = "header", x = 1, y = 129, w = 53, h = 2, label = L["团队标记图标"], labelSize = 20 },
        { key = "raidIconSize", type = "slider", x = 1, y = 132, w = 15, h = 2, label = L["图标大小"], min = 8, max = 40 },
        { key = "raidIconX", type = "slider", x = 19, y = 132, w = 15, h = 2, label = L["水平偏移"], min = -50, max = 50 },
        { key = "raidIconY", type = "slider", x = 36, y = 132, w = 15, h = 2, label = L["垂直偏移"], min = -50, max = 50 },
    }




    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)
end
EX_RegisterLayout()

local EX_DEFAULTS = {
    attachToCustom = false,
    customAttachTarget = "",
    enabled = false,
    font_name = {
        a = 1,
        align = "LEFT",
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = -200,
        y = 0,
    },
    font_timer = {
        a = 1,
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = true,
        shadowX = 0.5,
        shadowY = -0.5,
        size = 16,
        x = -3,
        y = 0,
    },
    growDirection = "DOWN",
    locked = true,
    nameAlign = "LEFT",
    pos = {
        "CENTER",
        "UIParent",
        "CENTER",
        0,
        -200,
    },
    posX = 495,
    posY = 138,
    preview = false,
    raidIconSize = 18,
    raidIconX = -2,
    raidIconY = 0,
    showPlayerName = true,
    showTimer = true,
    spacing = 1,
    timerGroup = {
        barBgColor = {
            a = 0.6,
            b = 0.1,
            g = 0.1,
            r = 0.1,
        },
        barBgColorA = 0.90653932094574,
        barBgColorB = 0.30196079611778,
        barBgColorG = 0.30196079611778,
        barBgColorR = 0.30196079611778,
        barColor = {
            a = 1,
            b = 0.5,
            g = 0.5,
            r = 0.5,
        },
        barColorA = 1,
        barColorB = 0.2,
        barColorG = 0.8,
        barColorR = 0.2,
        borderColorA = 1,
        borderColorB = 0.10196079313755,
        borderColorG = 0.10196079313755,
        borderColorR = 0.10196079313755,
        borderPadding = 1,
        borderSize = 1,
        borderTexture = "Square Full White",
        height = 25,
        iconOffsetX = -2,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconSize = 25,
        showBorder = true,
        showIcon = true,
        texture = "Melli",
        width = 184,
    },
    useClassColorBar = true,
    useClassColorName = false,
}

--[[ 使用新版本预设 如果有问题回退此版本!

local EX_DEFAULTS = {
    enabled = true,
    font_name = {
        a = 1,
        align = "LEFT",
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = true,
        shadowX = 1.6000003814697,
        shadowY = -0.69999885559082,
        size = 16,
        x = 2,
        y = 0,
    },
    font_timer = {
        a = 1,
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 14,
        x = 0,
        y = 0,
    },
    displayStyle = "计时条",
    growDirection = "向下",
    locked = true,
    listMarkerSize = 18,
    listMaxRows = 5,
    listRowHeight = 22,
    listWidth = 180,
    maxBars = 5,
    nameAlign = "LEFT",
    pos = {
        "CENTER",
        "UIParent",
        "CENTER",
        0,
        -200,
    },
    posX = -592,
    posY = -52,
    preview = false,
    raidIconSize = 18,
    raidIconX = -2,
    raidIconY = 0,
    readyText = L["准备"],
    showPlayerName = true,
    showReadyText = false,
    showTimer = true,
    spacing = 1,
    timerGroup = {
        barBgColor = {
            a = 0.6,
            b = 0.1,
            g = 0.1,
            r = 0.1,
        },
        barBgColorA = 0.5,
        barBgColorB = 0,
        barBgColorG = 0,
        barBgColorR = 0,
        barColor = {
            a = 1,
            b = 0.5,
            g = 0.5,
            r = 0.5,
        },
        barColorA = 1,
        barColorB = 0.2,
        barColorG = 0.8,
        barColorR = 0.2,
        height = 24,
        iconOffsetX = -1,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconSize = 23,
        showIcon = true,
        texture = "Melli",
        width = 150,
    },
    useClassColorBar = true,
    useClassColorName = false,
    sortPriorityTank = 1, -- 坦克优先级最高
    sortPriorityHealer = 2, -- 治疗次之
    sortPriorityDPS = 3, -- DPS最低
    sortMeleeDPSFirst = false, -- 近战DPS不优先
}
]]

EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)

local function IsListStyle()
    return EX_DB and EX_DB.displayStyle == DISPLAY_STYLE_LIST
end

-- =============================================================
-- 自动检测已加载的小队框体插件（仅在用户未手动设置时生效）
-- =============================================================
--- 延迟自动检测：在模块首次需要时调用（插件框架可能还未创建）
-- =============================================================
-- UI 框架系统
-- =============================================================
local activeBars = {}   -- [recordID] = { bar, guid, startTime, expireTime, duration, classFilename }
local usedBarsList = {} -- 有序列表，用于布局
local previewBars = {}  -- 预览模式条
local isPreviewing = false
local ExwindFactory = _G.ExwindFactory
local nextInterruptRecordID = 0
local INTERRUPT_RECORD_DURATION = 15
local INTERRUPT_RECORD_ICON = 132357
local interruptDebugEnabled = false
local isValidEnvironment = nil
-- 前置声明局部函数，防止时序导致的 nil 错误
local UpdateLayout, ReLayout, RefreshAll, TogglePreview, CreateAnchor, CleanupExpiredRecords, EnsureAnchorController
local RemoveInterruptRecord
local UpdateBarVisuals, UpdateRecordTimerText, ReleaseVisual

local function IsSecretValue(value)
    return type(_G.issecretvalue) == "function" and _G.issecretvalue(value)
end

local function NormalizeSafeText(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end
    local text = tostring(value)
    if text == "" then
        return nil
    end
    return text
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExBossInterruptTrackerAnchor",
        title = L["打断监控"],
        getDB = function()
            return EX_DB or EX_DEFAULTS
        end,
        offsetXKey = "posX",
        offsetYKey = "posY",
        restoreKeys = {
            "locked",
            "preview",
        },
        syncWidgets = {
            "posX",
            "posY",
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        widgetRanges = {
            posX = { min = -1000, max = 1000, step = 1 },
            posY = { min = -1000, max = 1000, step = 1 },
        },
        initialWidth = 200,
        initialHeight = 20,
        clampedToScreen = true,
        getAnchorPoint = function()
            return GetStandaloneAnchorPoint()
        end,
        relativePoint = "CENTER",
        onCreateFrame = function(_, frame)
            frame:Hide()
        end,
        onFramePicked = function()
            RefreshAll()
        end,
        onFramePickCancelled = function()
            RefreshAll()
        end,
        onEditModeChanged = function(_, active, visible)
            isEditModeActive = active == true
            isEditModeVisible = visible == true

            if isEditModeActive then
                EX_DB.locked = not isEditModeVisible
                EX_DB.preview = isEditModeVisible
                CreateAnchor()

                if isEditModeVisible then
                    TogglePreview(true)
                    RefreshAll()
                    if anchorFrame then
                        anchorFrame:Show()
                        if anchorFrame.bg then anchorFrame.bg:Hide() end
                        if anchorFrame.label then anchorFrame.label:Hide() end
                    end
                    RefreshEditOverlay()
                else
                    HideAllVisualsForEditMode()
                end
            else
                CreateAnchor()
                TogglePreview(EX_DB.preview == true)
                RefreshAll()
                RefreshEditOverlay()
            end
        end,
    })

    return anchorController
end

local function ClearRuntimeBars()
    for recordID, data in pairs(activeBars) do
        if data.bar then
            data.bar:SetScript("OnUpdate", nil)
            ReleaseVisual(data.bar)
        end
        activeBars[recordID] = nil
    end
    wipe(usedBarsList)
end

local function IsTrackedNameplateUnit(unit)
    if type(unit) ~= "string" then
        return false
    end

    local index = string.match(unit, "^nameplate(%d+)$")
    if not index then
        return false
    end

    index = tonumber(index)
    return index ~= nil and index >= 1 and index <= 40
end

local function DebugPrint(fmt, ...)
    if not interruptDebugEnabled then return end

    local msg = fmt
    if select("#", ...) > 0 then
        msg = string.format(fmt, ...)
    end

    print(string.format("|cff33ff99[ExInterruptDebug]|r %s", msg))
end

local function HideAllVisualsForEditMode()
    if anchorFrame then
        anchorFrame:Hide()
        anchorFrame:EnableMouse(false)
        if anchorFrame.bg then anchorFrame.bg:Hide() end
        if anchorFrame.label then anchorFrame.label:Hide() end
        ExwindTools:HideExwindToolsEditOverlay(anchorFrame)
    end

    for _, data in pairs(activeBars) do
        if data.bar then
            data.bar:Hide()
            data.bar:SetScript("OnUpdate", nil)
        end
    end

    for _, bar in ipairs(previewBars) do
        bar:Hide()
        bar:SetScript("OnUpdate", nil)
        ReleaseVisual(bar)
    end
    wipe(previewBars)

    for _, bar in ipairs(usedBarsList) do
        if bar then
            bar:Hide()
            bar:SetScript("OnUpdate", nil)
        end
    end

    if playerSelfBar then
        playerSelfBar:Hide()
        playerSelfBar:SetScript("OnUpdate", nil)
    end

    isPreviewing = false
end

local function GetDesiredPreviewCount()
    local count = IsListStyle() and (EX_DB.listMaxRows or 5) or (EX_DB.maxBars or 5)
    count = tonumber(count) or 5
    if count < 1 then
        count = 1
    end
    return math.floor(count)
end

local function ReleasePreviewBars()
    for _, bar in ipairs(previewBars) do
        bar:Hide()
        bar:SetScript("OnUpdate", nil)
        ReleaseVisual(bar)
    end
    wipe(previewBars)
end

local function PrintDebugSnapshot()
    local state = ExwindTools.State or {}
    local enemyNameplates = (_G.GetCVarBool and _G.GetCVarBool("nameplateShowEnemies")) and "开" or "关"
    DebugPrint("enabled=%s, preview=%s, env=%s, IsInParty=%s, InstanceType=%s, InMythicPlus=%s, 敌方姓名板=%s",
        tostring(EX_DB and EX_DB.enabled),
        tostring(isPreviewing),
        tostring(isValidEnvironment),
        tostring(state.IsInParty),
        tostring(state.InstanceType),
        tostring(state.InMythicPlus),
        enemyNameplates
    )
end

local function GetUnitSpecID(unit)
    local specID = 0
    if PartySpec then
        specID = PartySpec:GetSpec(unit)
    end

    if specID == 0 and unit == "player" then
        specID = GetSpecializationInfo(GetSpecialization() or 1)
    end

    return specID or 0
end

local function GetUnitInterruptSpellData(unit)
    local specID = GetUnitSpecID(unit)
    if specID == 0 then return nil, 0 end
    return SPEC_INTERRUPT_DB[specID], specID
end

local function GetPlayerInterruptData()
    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    local specID = GetSpecializationInfo(specIndex)
    if not specID or specID <= 0 then return nil end
    local data = SPEC_INTERRUPT_DB[specID]
    if not data or data.id == 0 then return nil end
    return data
end

-- =============================================================
-- 环境检测：只在队伍且5人副本内生效
-- =============================================================
--- 检测当前环境是否有效（队伍 + 5人副本）
local function CheckEnvironment()
    local state = ExwindTools.State
    local inParty = state.IsInParty or false
    local instanceType = state.InstanceType or "none"

    -- 必须在队伍中，且副本类型为 party (5人本)
    local shouldEnable = inParty and instanceType == "party"

    if shouldEnable ~= isValidEnvironment then
        isValidEnvironment = shouldEnable
        DebugPrint("环境切换: shouldEnable=%s, inParty=%s, instanceType=%s",
            tostring(shouldEnable), tostring(inParty), tostring(instanceType))

        if not shouldEnable then
            -- 环境无效，隐藏所有UI
            if anchorFrame then
                anchorFrame:Hide()
                anchorFrame:EnableMouse(false)
                if anchorFrame.bg then anchorFrame.bg:Hide() end
                if anchorFrame.label then anchorFrame.label:Hide() end
            end
            ClearRuntimeBars()
            ReleasePlayerSelfBar()
        else
            -- 环境有效，恢复显示
            if EX_DB.enabled then
                UpdateLayout()
            end
        end
    end

    return shouldEnable
end

-- 创建锚点
CreateAnchor = function()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(200, 20)
    ApplyStandaloneAnchorPosition()

    anchorFrame.bg = anchorFrame:CreateTexture(nil, "BACKGROUND")
    anchorFrame.bg:SetAllPoints()
    anchorFrame.bg:SetColorTexture(0, 0.5, 0, 0.5)

    anchorFrame.label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorFrame.label:SetPoint("CENTER")
    anchorFrame.label:SetText(L["打断监控 锚点"])
    anchorFrame.bg:Hide()
    anchorFrame.label:Hide()

    editHandleFrame = CreateFrame("Frame", nil, anchorFrame)
    editHandleFrame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    editHandleFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    editHandleFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
    editHandleFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
end

-- 初始化计时条结构
local function InitCastBarStructure(bar)
    bar:SetClampedToScreen(true)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bar.bg = bg

    bar.Text = bar:CreateFontString(nil, "OVERLAY")
    bar.TargetNameText = bar:CreateFontString(nil, "OVERLAY")
    bar.TimerText = bar:CreateFontString(nil, "OVERLAY")
    bar.Icon = bar:CreateTexture(nil, "OVERLAY")
    bar.RaidIcon = bar:CreateTexture(nil, "OVERLAY")
    bar.RaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    bar.RaidIcon:Hide()
end

local function InitInterruptListRowStructure(row)
    row:SetClampedToScreen(true)
    row.Icon = row:CreateTexture(nil, "OVERLAY")
    row.Icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.Icon:Hide()
    row.SeparatorText = row:CreateFontString(nil, "OVERLAY")
    row.Text = row:CreateFontString(nil, "OVERLAY")
end

-- 初始化框架池
if ExwindFactory then
    ExwindFactory:InitPool("ExBossInterruptBar", "StatusBar", "BackdropTemplate", InitCastBarStructure)
    ExwindFactory:InitPool("ExBossInterruptListRow", "Frame", nil, InitInterruptListRowStructure)
end

-- 获取计时条
local function AcquireBar()
    if not ExwindFactory then return end
    local bar = ExwindFactory:Acquire("ExBossInterruptBar", anchorFrame)
    bar._isPreview = nil
    bar._visualStyle = "bar"
    return bar
end

local function AcquireListRow()
    if not ExwindFactory then return end
    local row = ExwindFactory:Acquire("ExBossInterruptListRow", anchorFrame)
    row._isPreview = nil
    row._visualStyle = "list"
    return row
end

-- 释放计时条
local function ReleaseBar(bar)
    if not ExwindFactory or not bar then return end
    bar:SetScript("OnUpdate", nil)
    ExwindFactory:Release("ExBossInterruptBar", bar)
end

local function ReleaseListRow(row)
    if not ExwindFactory or not row then return end
    row:SetScript("OnUpdate", nil)
    ExwindFactory:Release("ExBossInterruptListRow", row)
end

ReleaseVisual = function(widget)
    if not widget then return end
    if widget._visualStyle == "list" then
        ReleaseListRow(widget)
    else
        ReleaseBar(widget)
    end
end

-- =============================================================
-- 玩家自身打断计时条管理
-- =============================================================
SetupPlayerSelfBarOnUpdate = function()
    if not playerSelfBar then return end
    playerSelfBar:SetScript("OnUpdate", function(self)
        if not playerSelfBarOnCD then
            self:SetScript("OnUpdate", nil)
            return
        end
        local remaining = playerSelfBarStartTime + playerSelfBarDuration - GetTime()
        if remaining > 0 then
            self:SetValue(remaining)
            UpdateRecordTimerText(self, remaining)
        else
            playerSelfBarOnCD = false
            self:SetScript("OnUpdate", nil)
            self:SetValue(playerSelfBarDuration)
            if self.TimerText then
                if EX_DB.showReadyText then
                    self.TimerText:SetText(EX_DB.readyText or "准备")
                    self.TimerText:SetShown(EX_DB.showTimer)
                else
                    self.TimerText:SetText("")
                end
            end
        end
    end)
end

ReleasePlayerSelfBar = function()
    if not playerSelfBar then return end
    playerSelfBar:SetScript("OnUpdate", nil)
    ReleaseBar(playerSelfBar)
    playerSelfBar = nil
    playerSelfBarOnCD = false
end

RefreshPlayerSelfBar = function()
    if IsListStyle() then
        ReleasePlayerSelfBar()
        return
    end
    if not anchorFrame then return end

    local interruptData = GetPlayerInterruptData()
    if not interruptData then
        ReleasePlayerSelfBar()
        return
    end

    if not playerSelfBar then
        playerSelfBar = AcquireBar()
        if not playerSelfBar then return end
        playerSelfBar._visualStyle = "bar"
    end

    local _, classToken = UnitClass("player")
    playerSelfBar._classFilename = classToken
    playerSelfBar._isPreview = nil
    playerSelfBar.unit = "player"
    playerSelfBar._raidTargetIndex = GetRaidTargetIndex and GetRaidTargetIndex("player") or nil

    if playerSelfBar.Icon then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(interruptData.id)
        if spellInfo then
            playerSelfBar.Icon:SetTexture(spellInfo.iconID)
        end
    end

    if playerSelfBar.Text then
        local displayName = UnitName("player") or ""
        pcall(playerSelfBar.Text.SetText, playerSelfBar.Text, displayName)
        playerSelfBar.Text:SetShown(EX_DB.showPlayerName)
    end

    playerSelfBarDuration = interruptData.cd
    playerSelfBar:SetMinMaxValues(0, playerSelfBarDuration)
    UpdateBarVisuals(playerSelfBar)

    if playerSelfBarOnCD then
        local remaining = playerSelfBarStartTime + playerSelfBarDuration - GetTime()
        if remaining > 0 then
            playerSelfBar:SetValue(remaining)
            UpdateRecordTimerText(playerSelfBar, remaining)
            SetupPlayerSelfBarOnUpdate()
        else
            playerSelfBarOnCD = false
            playerSelfBar:SetValue(playerSelfBarDuration)
            if playerSelfBar.TimerText and EX_DB.showReadyText then
                playerSelfBar.TimerText:SetText(EX_DB.readyText or "准备")
                playerSelfBar.TimerText:SetShown(EX_DB.showTimer)
            end
        end
    else
        playerSelfBar:SetValue(playerSelfBarDuration)
        if playerSelfBar.TimerText then
            if EX_DB.showReadyText then
                playerSelfBar.TimerText:SetText(EX_DB.readyText or "准备")
                playerSelfBar.TimerText:SetShown(EX_DB.showTimer)
            else
                playerSelfBar.TimerText:SetText("")
            end
        end
    end
end

local function ApplyClassColorToText(fontString, classToken)
    if not fontString then return end

    fontString:SetTextColor(1, 1, 1, 1)
    local okColor, color = pcall(C_ClassColor.GetClassColor, classToken)
    if okColor and color then
        fontString:SetTextColor(color.r, color.g, color.b, 1)
    end
end

local function GetEffectiveBarDimensions(bar, group)
    local configuredWidth = (bar and bar._layoutWidth) or (group and group.width) or 200
    local configuredHeight = (bar and bar._layoutHeight) or (group and group.height) or 20
    local width = math.max(20, tonumber(configuredWidth) or 200)
    local height = math.max(12, tonumber(configuredHeight) or 20)
    return width, height
end

local function GetConfiguredIconSize(requestedSize, fallbackSize)
    local size = tonumber(requestedSize) or tonumber(fallbackSize) or 20
    if size < 1 then
        size = 1
    end
    return size
end

-- 应用计时条视觉
UpdateBarVisuals = function(bar)
    local db = EX_DB
    local group = db.timerGroup or {}
    local barWidth, barHeight = GetEffectiveBarDimensions(bar, group)
    local iconSide = group.iconSide or "LEFT"
    local iconSize = GetConfiguredIconSize(group.iconSize or 20, 20)
    local raidSize = GetConfiguredIconSize(EX_DB.raidIconSize or 18, 18)
    local timerFontSize = (db.font_timer and tonumber(db.font_timer.size)) or 14
    local timerWidth = db.showTimer and math.max(40, math.floor(timerFontSize * 3.5)) or 0
    local textInsetLeft = math.max(2, 4 + ((db.font_name and tonumber(db.font_name.x)) or 0))
    local textInsetRight = db.showTimer and (timerWidth + 6) or 4
    -- 设置尺寸
    bar:SetSize(barWidth, barHeight)

    -- 设置材质 (fallback: LSM 找不到时用 Solid)
    local tex = LSM:Fetch("statusbar", group.texture or "Melli")
    if not tex then tex = LSM:Fetch("statusbar", "Solid") or "Interface\\Buttons\\WHITE8X8" end
    if bar.bg then
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(
            group.barBgColorR or 0,
            group.barBgColorG or 0,
            group.barBgColorB or 0,
            group.barBgColorA or 0.5
        )
    end
    bar:SetStatusBarTexture(tex)

    -- 如果不使用职业颜色，使用默认颜色
    if not db.useClassColorBar then
        bar:SetStatusBarColor(
            group.barColorR or 0.2,
            group.barColorG or 0.8,
            group.barColorB or 0.2,
            group.barColorA or 1
        )
    else
        -- 使用职业颜色 (StatusBar)
        local classToken = bar._classFilename
        if bar._isPreview then
            classToken = bar._previewClass
        elseif bar.unit then
            local _, unitClass = UnitClass(bar.unit)
            classToken = unitClass
        end

        bar:SetStatusBarColor(
            group.barColorR or 0.2,
            group.barColorG or 0.8,
            group.barColorB or 0.2,
            group.barColorA or 1
        )

        local okColor, color = pcall(C_ClassColor.GetClassColor, classToken)
        if okColor and color then
            bar:SetStatusBarColor(color.r, color.g, color.b, 1)
        end
    end

    -- [Feature] 应用边框相关样式 (确保边框渲染于状态条前台)
    local edgeTex = group.showBorder and group.borderTexture and group.borderTexture ~= "None" and
        LSM:Fetch("border", group.borderTexture) or nil
    if edgeTex then
        if not bar.BorderFrame then
            bar.BorderFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
            bar.BorderFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
        end
        local edgeSize = group.borderSize or 12
        local pad = group.borderPadding or 0
        bar.BorderFrame:ClearAllPoints()
        bar.BorderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -pad, pad)
        bar.BorderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad, -pad)
        bar.BorderFrame:SetBackdrop({
            edgeFile = edgeTex,
            edgeSize = edgeSize,
        })
        local br, bg, bb, ba = group.borderColorR or 1, group.borderColorG or 1, group.borderColorB or 1,
            group.borderColorA or 1
        bar.BorderFrame:SetBackdropBorderColor(br, bg, bb, ba)
        bar.BorderFrame:Show()
    else
        if bar.BorderFrame then
            bar.BorderFrame:Hide()
        end
    end

    -- 应用字体组
    local StaticDB = ExwindTools.DB_Static

    -- 玩家名称 (原来的 Text)
    if bar.Text then
        StaticDB:ApplyFont(bar.Text, db.font_name)
        bar.Text:ClearAllPoints()
        bar.Text:SetPoint("LEFT", bar, "LEFT", textInsetLeft, db.font_name.y)
        bar.Text:SetJustifyH(db.nameAlign)
        bar.Text:SetShown(db.showPlayerName)

        -- 职业颜色 (Text)
        if db.useClassColorName then
            local classToken = bar._classFilename
            if bar._isPreview then
                classToken = bar._previewClass
            elseif bar.unit then
                local _, unitClass = UnitClass(bar.unit)
                classToken = unitClass
            end
            ApplyClassColorToText(bar.Text, classToken)
        else
            bar.Text:SetTextColor(1, 1, 1, 1)
        end
    end

    -- 冷却时间 (固定在最右边)
    if bar.TimerText then
        StaticDB:ApplyFont(bar.TimerText, db.font_timer)
        bar.TimerText:ClearAllPoints()
        bar.TimerText:SetPoint("RIGHT", bar, "RIGHT", db.font_timer.x, db.font_timer.y)
        bar.TimerText:SetWidth(timerWidth)
        bar.TimerText:SetJustifyH("RIGHT")
        bar.TimerText:SetMaxLines(1)
        bar.TimerText:SetWordWrap(false)
        if bar.TimerText.SetNonSpaceWrap then
            bar.TimerText:SetNonSpaceWrap(false)
        end
        bar.TimerText:SetShown(db.showTimer)
    end

    -- 隐藏原来的目标名字（不再使用）
    if bar.TargetNameText then
        bar.TargetNameText:Hide()
    end

    -- 图标
    if bar.Icon then
        bar.Icon:SetSize(iconSize, iconSize)
        bar.Icon:ClearAllPoints()
        if iconSide == "LEFT" then
            bar.Icon:SetPoint("RIGHT", bar, "LEFT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        else
            bar.Icon:SetPoint("LEFT", bar, "RIGHT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        end
        bar.Icon:SetShown(group.showIcon)
        bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if bar.RaidIcon then
        local raidIndex = bar._raidTargetIndex
        local hasRaidIcon = (raidIndex ~= nil)
        if hasRaidIcon then
            local raidX = EX_DB.raidIconX or 0
            local raidY = EX_DB.raidIconY or 0

            bar.RaidIcon:ClearAllPoints()
            bar.RaidIcon:SetSize(raidSize, raidSize)
            if group.showIcon and bar.Icon and iconSide == "LEFT" then
                bar.RaidIcon:SetPoint("RIGHT", bar.Icon, "LEFT", raidX, raidY)
            else
                bar.RaidIcon:SetPoint("RIGHT", bar, "LEFT", raidX, raidY)
            end
            bar.RaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            bar.RaidIcon:SetSpriteSheetCell(raidIndex, 4, 4)
            bar.RaidIcon:Show()
        else
            bar.RaidIcon:Hide()
        end
    end
end

local function UpdateListRowVisuals(row)
    if not row then return end

    local StaticDB = ExwindTools.DB_Static
    local rowHeight = math.max(12, tonumber(row._layoutHeight or EX_DB.listRowHeight) or 22)
    local rowWidth = math.max(30, tonumber(row._layoutWidth or EX_DB.listWidth) or 180)
    local markerSize = GetConfiguredIconSize(EX_DB.listMarkerSize or 18, 18)

    row:SetSize(rowWidth, rowHeight)

    if row.Icon then
        row.Icon:ClearAllPoints()
        row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.Icon:SetSize(markerSize, markerSize)
    end

    if row.SeparatorText then
        StaticDB:ApplyFont(row.SeparatorText, EX_DB.font_name)
        row.SeparatorText:SetText("-")
        row.SeparatorText:SetTextColor(1, 1, 1, 1)
        row.SeparatorText:ClearAllPoints()
    end

    if row.Text then
        StaticDB:ApplyFont(row.Text, EX_DB.font_name)
        row.Text:SetJustifyH("LEFT")
        row.Text:ClearAllPoints()
        ApplyClassColorToText(row.Text, row._classFilename)
    end

    local markerIndex = row._raidTargetIndex
    local hasMarker = (markerIndex ~= nil)
    local textLeft = 0
    if hasMarker then
        if row.Icon and row.Icon.SetSpriteSheetCell then
            row.Icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            row.Icon:SetSpriteSheetCell(markerIndex, 4, 4)
            row.Icon:Show()
        end
        if row.SeparatorText then
            row.SeparatorText:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
            row.SeparatorText:Show()
        end
        if row.Text then
            row.Text:SetPoint("LEFT", row.SeparatorText, "RIGHT", 6, 0)
            textLeft = markerSize + 4 + row.SeparatorText:GetStringWidth() + 6
        end
    else
        if row.Icon then
            row.Icon:Hide()
        end
        if row.SeparatorText then
            row.SeparatorText:Hide()
        end
        if row.Text then
            row.Text:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
    end
end

local function UpdateVisuals(widget)
    if not widget then return end
    if widget._visualStyle == "list" then
        UpdateListRowVisuals(widget)
    else
        UpdateBarVisuals(widget)
    end
end

-- 获取专精的角色优先级
local function GetSpecPriority(unit)
    if not unit or not UnitExists(unit) then return 999 end

    local specID = GetUnitSpecID(unit)
    if not specID or specID == 0 then return 999 end

    local specData = SPEC_INTERRUPT_DB[specID]
    if not specData then return 999 end

    local role = specData.role or "DAMAGER"
    local db = EX_DB

    -- 基础优先级（根据角色）
    local basePriority =
        role == "TANK" and (db.sortPriorityTank or 1) or
        role == "HEALER" and (db.sortPriorityHealer or 2) or
        (db.sortPriorityDPS or 3)

    -- 近战DPS微调（如果开启）
    if role == "DAMAGER" and db.sortMeleeDPSFirst then
        -- 判断是否近战专精（根据EXDB.InterruptData中的专精ID）
        local meleeSpecs = {
            -- 战士: 71武器, 72狂暴
            [71] = true,
            [72] = true,
            -- 圣骑士: 70神圣, 66防护, 70惩戒
            [70] = true,
            -- 猎人: 无近战
            -- 盗贼: 全近战
            [259] = true,
            [260] = true,
            [261] = true,
            -- 牧师: 无近战
            -- 萨满: 263增强
            [263] = true,
            -- 法师: 无近战
            -- 术士: 无近战
            -- 武僧: 268酿酒, 269踏风
            [268] = true,
            [269] = true,
            -- 德鲁伊: 103野性
            [103] = true,
            -- 恶魔猎手: 全近战
            [577] = true,
            [581] = true,
            -- 死亡骑士: 全近战
            [250] = true,
            [251] = true,
            [252] = true,
        }

        if meleeSpecs[specID] then
            basePriority = basePriority - 0.5 -- 近战优先级提升0.5
        end
    end

    return basePriority
end

-- 排序函数：最新打断记录优先，剩余显示时间越长越靠前
local function BuildSortedRecordList()
    local sortList = {}
    for recordID, data in pairs(activeBars) do
        table.insert(sortList, { recordID = recordID, data = data })
    end

    table.sort(sortList, function(a, b)
        if a.data.startTime ~= b.data.startTime then
            return a.data.startTime > b.data.startTime
        end

        if a.data.expireTime ~= b.data.expireTime then
            return (a.data.expireTime or 0) > (b.data.expireTime or 0)
        end

        return a.recordID > b.recordID
    end)

    return sortList
end

local function SortBars()
    if isPreviewing then return end

    local sortList = BuildSortedRecordList()

    wipe(usedBarsList)
    -- 玩家自己的打断条始终排在最前
    if playerSelfBar then
        table.insert(usedBarsList, playerSelfBar)
    end
    for _, item in ipairs(sortList) do
        table.insert(usedBarsList, item.data.bar)
    end
end

local function TrimListRecords()
    if not IsListStyle() then return end

    local sortList = BuildSortedRecordList()
    local maxRows = EX_DB.listMaxRows or 5
    local removed = false

    for index = maxRows + 1, #sortList do
        RemoveInterruptRecord(sortList[index].recordID, true)
        removed = true
    end

    if removed then
        ReLayout()
    end
end

-- 重新布局所有条
ReLayout = function()
    if not anchorFrame then return end

    if not isPreviewing and not isEditModeActive then
        if not EX_DB.enabled or not isValidEnvironment then
            anchorFrame:Hide()
            anchorFrame:EnableMouse(false)
            if anchorFrame.bg then anchorFrame.bg:Hide() end
            if anchorFrame.label then anchorFrame.label:Hide() end
            for _, bar in ipairs(usedBarsList) do
                if bar then
                    bar:Hide()
                end
            end
            if playerSelfBar then
                playerSelfBar:Hide()
                playerSelfBar:SetScript("OnUpdate", nil)
            end
            return
        end
    end

    -- 先排序
    if not isPreviewing then
        SortBars()
    end

    local group = EX_DB.timerGroup or {}
    local listStyle = IsListStyle()
    local height = listStyle and (EX_DB.listRowHeight or 22) or (group.height or 20)
    local spacing = EX_DB.spacing or 2
    local list = isPreviewing and previewBars or usedBarsList
    local growUp = (EX_DB.growDirection == GROW_DIRECTION_UP)
    local maxLimit = listStyle and (EX_DB.listMaxRows or 5) or (EX_DB.maxBars or 5)
    local barWidth = listStyle and (EX_DB.listWidth or 180) or (group.width or 200)
    local totalHeight = height

    -- ====== 统一条堆叠逻辑 ======
    local visibleCount = 0
    for i, bar in ipairs(list) do
        if i <= maxLimit then
            visibleCount = visibleCount + 1
            bar:SetParent(anchorFrame)
            bar:Show()
            bar:EnableMouse(false)
            bar:ClearAllPoints()
            bar._layoutWidth = barWidth
            bar._layoutHeight = height
            UpdateVisuals(bar)

            if growUp then
                -- 向上增长：第1条在锚点 BOTTOM，后续依次向上叠加
                bar:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, (i - 1) * (height + spacing))
            else
                -- 向下增长：第1条在锚点 TOP，后续依次向下叠加
                bar:SetPoint("TOP", anchorFrame, "TOP", 0, -(i - 1) * (height + spacing))
            end
        else
            bar:Hide()
        end
    end

    totalHeight = math.max(height, visibleCount > 0 and (visibleCount * height + (visibleCount - 1) * spacing) or height)
    local anchorHeight = isEditModeActive and totalHeight or height

    -- 编辑模式下让主 frame 包住整个条组，便于 ExBoss 标准外框正确覆盖全部内容。
    anchorFrame:SetSize(barWidth, anchorHeight)
    ApplyStandaloneAnchorPosition()

    if anchorFrame.bg then
        anchorFrame.bg:ClearAllPoints()
        if isEditModeActive then
            anchorFrame.bg:SetAllPoints(anchorFrame)
        else
            anchorFrame.bg:SetSize(barWidth, totalHeight)
        end
        if anchorFrame.label then
            anchorFrame.label:ClearAllPoints()
            anchorFrame.label:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
        end

        if isEditModeActive then
            anchorFrame:SetHitRectInsets(0, 0, 0, 0)
        elseif growUp then
            anchorFrame.bg:SetPoint("BOTTOM", anchorFrame, "BOTTOM")
            anchorFrame:SetHitRectInsets(0, 0, -(totalHeight - height), 0)
        else
            anchorFrame.bg:SetPoint("TOP", anchorFrame, "TOP")
            anchorFrame:SetHitRectInsets(0, 0, 0, -(totalHeight - height))
        end
    end

    if editHandleFrame then
        editHandleFrame:ClearAllPoints()
        if isEditModeActive then
            editHandleFrame:SetAllPoints(anchorFrame)
        else
            editHandleFrame:SetSize(barWidth, totalHeight)
            if growUp then
                editHandleFrame:SetPoint("BOTTOM", anchorFrame, "BOTTOM")
            else
                editHandleFrame:SetPoint("TOP", anchorFrame, "TOP")
            end
        end
    end
end

-- 刷新所有条
RefreshAll = function()
    if not isPreviewing and not isEditModeActive and (not EX_DB.enabled or not isValidEnvironment) then
        if anchorFrame then
            anchorFrame:Hide()
            anchorFrame:EnableMouse(false)
            if anchorFrame.bg then anchorFrame.bg:Hide() end
            if anchorFrame.label then anchorFrame.label:Hide() end
        end
        return
    end

    if isPreviewing then
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        local previewClasses = {
            { name = "战士", class = "WARRIOR" },
            { name = "法师", class = "MAGE" },
            { name = "猎人", class = "HUNTER" },
            { name = "圣骑士", class = "PALADIN" },
        }

        if #previewBars ~= GetDesiredPreviewCount() then
            ReleasePreviewBars()
            TogglePreview(true)
        else
            for i, bar in ipairs(previewBars) do
                if IsListStyle() then
                    bar._previewClass = (i == 1) and playerClass or previewClasses[((i - 2) % #previewClasses) + 1]
                        .class
                    bar._classFilename = bar._previewClass
                    bar._raidTargetIndex = i
                    UpdateVisuals(bar)
                    if bar.Text then
                        local previewInfo = previewClasses[((i - 2) % #previewClasses) + 1]
                        local displayName = (i == 1) and playerName or (previewInfo and previewInfo.name) or playerName
                        bar.Text:SetText(displayName)
                    end
                else
                    local previewSpells = { 1766, 2139, 106839, 183752, 187707 }
                    local previewInfo = previewClasses[((i - 2) % #previewClasses) + 1]
                    bar._previewClass = (i == 1) and playerClass or (previewInfo and previewInfo.class) or playerClass
                    bar._classFilename = bar._previewClass
                    UpdateVisuals(bar)
                    if bar.Icon then
                        local spellInfo = C_Spell.GetSpellInfo(previewSpells[((i - 1) % #previewSpells) + 1] or 1766)
                        bar.Icon:SetTexture((spellInfo and spellInfo.iconID) or 136197)
                    end
                    if bar.Text then
                        local displayName = (i == 1) and playerName or (previewInfo and previewInfo.name) or playerName
                        bar.Text:SetText(displayName)
                        bar.Text:SetShown(EX_DB.showPlayerName)
                    end
                    local remaining = math.max(1, INTERRUPT_RECORD_DURATION - (i - 1) * 3)
                    bar:SetMinMaxValues(0, INTERRUPT_RECORD_DURATION)
                    bar:SetValue(remaining)
                    if bar.TimerText then
                        if EX_DB.showTimer then
                            bar.TimerText:SetText(string.format("%d", remaining))
                        else
                            bar.TimerText:SetText("")
                        end
                    end
                end
            end
        end
    else
        for guid, data in pairs(activeBars) do
            if data.bar then
                UpdateVisuals(data.bar)
            end
        end
        -- 同步刷新玩家条视觉
        if playerSelfBar then
            UpdateBarVisuals(playerSelfBar)
        end
    end
    ReLayout()

    if anchorFrame then
        ApplyStandaloneAnchorPosition()

        if isEditModeActive and isEditModeVisible then
            anchorFrame:Show()
            anchorFrame:EnableMouse(true)
            anchorFrame.bg:Hide()
            anchorFrame.label:Hide()
        elseif EX_DB.locked then
            anchorFrame.bg:Hide()
            anchorFrame.label:Hide()
            anchorFrame:EnableMouse(false)
        else
            anchorFrame:EnableMouse(true)
            anchorFrame.bg:Show()
            anchorFrame.label:Show()
        end
    end
end

-- 预览模式（5个最近打断记录）
TogglePreview = function(enable)
    isPreviewing = enable

    if enable then
        -- [v5.0 新增] 预览模式下创建锚点（不受环境限制）
        if not anchorFrame then
            CreateAnchor()
        end

        if anchorFrame then
            anchorFrame:Show()
            anchorFrame:EnableMouse(true)
            if isEditModeActive and isEditModeVisible then
                anchorFrame.bg:Hide()
                anchorFrame.label:Hide()
            else
                anchorFrame.bg:Show()
                anchorFrame.label:Show()
            end
        end

        -- 清理真实条
        for guid, data in pairs(activeBars) do
            if data.bar then
                data.bar:Hide()
            end
        end
        wipe(activeBars)
        wipe(usedBarsList)
        ReleasePreviewBars()

        -- 获取玩家职业
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")

        -- 预设4个不同职业（用于其他4个条）
        local previewClasses = {
            { name = "战士", class = "WARRIOR" },
            { name = "法师", class = "MAGE" },
            { name = "猎人", class = "HUNTER" },
            { name = "圣骑士", class = "PALADIN" },
        }

        -- 创建预览条，数量跟随当前显示上限
        for i = 1, GetDesiredPreviewCount() do
            local bar = IsListStyle() and AcquireListRow() or AcquireBar()
            bar._isPreview = true

            if IsListStyle() then
                local previewInfo = previewClasses[((i - 2) % #previewClasses) + 1]
                bar._previewClass = (i == 1) and playerClass or (previewInfo and previewInfo.class) or playerClass
                bar._classFilename = bar._previewClass
                bar._raidTargetIndex = i
                UpdateVisuals(bar)
                if bar.Text then
                    local displayName = (i == 1) and playerName or (previewInfo and previewInfo.name) or playerName
                    bar.Text:SetText(displayName)
                end
            else
                -- 设置模拟法术图标
                local previewSpells = { 1766, 2139, 106839, 183752, 187707 }
                local previewInfo = previewClasses[((i - 2) % #previewClasses) + 1]
                local spellInfo = C_Spell.GetSpellInfo(previewSpells[((i - 1) % #previewSpells) + 1] or 1766)
                if spellInfo then
                    bar.Icon:SetTexture(spellInfo.iconID)
                else
                    bar.Icon:SetTexture(136197)
                end

                if bar.Text and EX_DB.showPlayerName then
                    local displayName
                    if i == 1 then
                        displayName = playerName
                    else
                        displayName = (previewInfo and previewInfo.name) or playerName
                    end

                    bar._previewClass = (i == 1) and playerClass or (previewInfo and previewInfo.class) or playerClass
                    bar._classFilename = bar._previewClass
                    UpdateVisuals(bar)
                    bar.Text:SetText(displayName)
                    bar.Text:Show()
                end

                -- 预览为最近 15 秒内的打断记录
                bar:SetMinMaxValues(0, INTERRUPT_RECORD_DURATION)
                do
                    local remaining = math.max(1, INTERRUPT_RECORD_DURATION - (i - 1) * 3)
                    bar:SetValue(remaining)
                    if bar.TimerText and EX_DB.showTimer then
                        bar.TimerText:SetText(string.format("%d", remaining))
                    end
                end
            end

            table.insert(previewBars, bar)
        end
    else
        -- 退出预览
        ReleasePreviewBars()

        -- [v3.1 Fix] 退出预览时恢复锁定状态
        if anchorFrame then
            if EX_DB.locked then
                anchorFrame:EnableMouse(false)
                anchorFrame.bg:Hide()
                anchorFrame.label:Hide()
            else
                anchorFrame:EnableMouse(true)
                anchorFrame.bg:Show()
            end
        end
        -- [v5.1 Fix] 退出预览后立即执行一次 UpdateLayout 以恢复真实数据，解决关闭编辑模式后条条不显示的问题
        UpdateLayout()
    end

    ReLayout()
end

-- 更新打断条布局 (增量更新,保留冷却状态)
UpdateLayout = function()
    -- [v5.0 新增] 环境检测：只在队伍且5人副本内生效
    if not CheckEnvironment() then
        return
    end

    if not EX_DB.enabled then
        if anchorFrame then
            anchorFrame:Hide()
        end
        return
    end

    if not anchorFrame then
        CreateAnchor()
    end

    anchorFrame:Show()

    -- [Fix] 预览时不该直接退出，而是应该继续执行
    if isPreviewing then
        ReLayout()
        return
    end

    if not IsListStyle() then
        CleanupExpiredRecords()
    end
    RefreshPlayerSelfBar()
    ReLayout()
    RefreshAll()
end

-- =============================================================
-- 核心逻辑：打断检测
-- =============================================================

UpdateRecordTimerText = function(bar, remaining)
    if not bar or not bar.TimerText or not EX_DB.showTimer then return end

    local displayVal
    if remaining > 6 then
        displayVal = math.floor(remaining)
        if displayVal ~= bar._lastDisplayed then
            bar._lastDisplayed = displayVal
            bar.TimerText:SetText(string.format("%d", displayVal))
        end
    else
        displayVal = math.floor(remaining * 10)
        if displayVal ~= bar._lastDisplayed then
            bar._lastDisplayed = displayVal
            bar.TimerText:SetText(string.format("%.1f", remaining))
        end
    end
end

RemoveInterruptRecord = function(recordID, skipReLayout)
    local data = activeBars[recordID]
    if not data then return end

    if data.bar then
        data.bar._lastDisplayed = nil
        data.bar:SetScript("OnUpdate", nil)
        ReleaseVisual(data.bar)
    end

    activeBars[recordID] = nil

    if not skipReLayout then
        ReLayout()
    end
end

CleanupExpiredRecords = function()
    local now = GetTime()
    local hasExpired = false

    for recordID, data in pairs(activeBars) do
        if data.expireTime and data.expireTime <= now then
            RemoveInterruptRecord(recordID, true)
            hasExpired = true
        end
    end

    if hasExpired then
        ReLayout()
    end
end

local function AddInterruptRecord(interruptedBy, interruptedSpellID, interruptedUnit, resolvedUnit)
    if interruptedBy == nil then
        DebugPrint("AddInterruptRecord 失败: interruptedBy 为空")
        return false, "missing_interruptedBy"
    end

    local displayName, classFilename

    if resolvedUnit and UnitExists(resolvedUnit) then
        -- L1/L2 已通过时间戳识别出 unit token，直接从 unit 取名字和职业，不碰 GUID
        local okName, name = pcall(UnitName, resolvedUnit)
        displayName = (okName and name) or nil
        if not displayName then
            DebugPrint("AddInterruptRecord 失败: UnitName 无法解析, resolvedUnit=%s", tostring(resolvedUnit))
            return false, "name_unresolved"
        end
        local okClass, _, classFile = pcall(UnitClass, resolvedUnit)
        classFilename = okClass and classFile or nil
    else
        -- L3 兜底：用原始 interruptedBy GUID
        local okName, unitName = pcall(UnitNameFromGUID, interruptedBy)
        if not okName or unitName == nil then
            DebugPrint("AddInterruptRecord 失败: UnitNameFromGUID 无法解析, ok=%s, secret=%s",
                tostring(okName), tostring(IsSecretValue(interruptedBy)))
            return false, "name_unresolved"
        end
        displayName = unitName
        if UnitClassFromGUID then
            local okClass, _, classFile = pcall(UnitClassFromGUID, interruptedBy)
            if okClass then
                classFilename = classFile
            else
                DebugPrint("UnitClassFromGUID 未提供可用职业 token, ok=%s", tostring(okClass))
            end
        end
    end

    local raidTargetIndex = nil
    if interruptedUnit and GetRaidTargetIndex then
        local okMarker, markerIndex = pcall(GetRaidTargetIndex, interruptedUnit)
        if okMarker then
            raidTargetIndex = markerIndex
        end
    end

    local iconTexture = INTERRUPT_RECORD_ICON
    if C_Spell and C_Spell.GetSpellTexture and interruptedSpellID then
        local okIcon, spellIcon = pcall(C_Spell.GetSpellTexture, interruptedSpellID)
        if okIcon and spellIcon then
            iconTexture = spellIcon
        else
            DebugPrint("GetSpellTexture 失败或无返回: spellID=%s, ok=%s", tostring(interruptedSpellID), tostring(okIcon))
        end
    end

    local bar = IsListStyle() and AcquireListRow() or AcquireBar()
    if not bar then return end

    nextInterruptRecordID = nextInterruptRecordID + 1
    local recordID = nextInterruptRecordID
    local startTime = GetTime()
    local expireTime = IsListStyle() and nil or (startTime + INTERRUPT_RECORD_DURATION)

    bar.unit = nil
    bar._classFilename = classFilename
    bar._isPreview = nil
    bar._lastDisplayed = nil
    bar._raidTargetIndex = raidTargetIndex

    if bar.Icon and not IsListStyle() then
        bar.Icon:SetTexture(iconTexture)
    end

    -- 先应用字体和控件样式，再写入文本，避免池化 FontString 尚未设置字体时报错。
    UpdateVisuals(bar)

    if bar.Text then
        local okText, errText = pcall(bar.Text.SetText, bar.Text, displayName)
        if not okText then
            DebugPrint("bar.Text:SetText 失败: %s", tostring(errText))
            return false, "text_set_failed"
        end
        bar.Text:SetShown(EX_DB.showPlayerName)
    end

    if not IsListStyle() then
        local okColor, color = pcall(C_ClassColor.GetClassColor, classFilename)
        if okColor and color then
            bar:SetStatusBarColor(color.r, color.g, color.b, 1)
        end

        bar:SetMinMaxValues(0, INTERRUPT_RECORD_DURATION)
        bar:SetValue(INTERRUPT_RECORD_DURATION)
        UpdateRecordTimerText(bar, INTERRUPT_RECORD_DURATION)
    end

    activeBars[recordID] = {
        bar = bar,
        guid = interruptedBy,
        unit = nil,
        startTime = startTime,
        expireTime = expireTime,
        duration = INTERRUPT_RECORD_DURATION,
        classFilename = classFilename,
        raidTargetIndex = raidTargetIndex,
    }

    if not IsListStyle() then
        bar:SetScript("OnUpdate", function(self)
            local data = activeBars[recordID]
            if not data or data.bar ~= self then
                self:SetScript("OnUpdate", nil)
                return
            end

            local remaining = data.expireTime - GetTime()
            if remaining > 0 then
                self:SetValue(remaining)
                UpdateRecordTimerText(self, remaining)
            else
                RemoveInterruptRecord(recordID)
            end
        end)
    end

    TrimListRecords()
    ReLayout()
    DebugPrint("AddInterruptRecord 成功: style=%s, nameSecret=%s, classSecret=%s, spellID=%s, activeRecords=%d",
        IsListStyle() and "list" or "bar",
        tostring(IsSecretValue(displayName)),
        tostring(IsSecretValue(classFilename)),
        tostring(interruptedSpellID),
        nextInterruptRecordID)
    return true, "ok"
end

-- =============================================================
-- 大秘境打断统计系统
-- =============================================================
local interruptStats = {} -- { [guid] = count }
local isInMythicPlus = false
local C_DamageMeter = _G.C_DamageMeter
local IsInGroup = _G.IsInGroup
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers

-- 重置打断统计表
local function ResetInterruptStats()
    wipe(interruptStats)
end

-- 记录一次打断
local function RecordInterrupt(guid)
    if not isInMythicPlus then return end
    if guid == nil then return end
    if IsSecretValue(guid) then
        DebugPrint("自定义统计跳过: interruptedBy 是 secret GUID，不能作为 table key")
        return
    end

    interruptStats[guid] = (interruptStats[guid] or 0) + 1
end

-- 打印自定义统计（模块内部记录）
local function PrintCustomInterruptStats()
    if not next(interruptStats) then
        return
    end

    -- 按次数排序
    local sortedStats = {}
    for guid, count in pairs(interruptStats) do
        table.insert(sortedStats, { guid = guid, count = count })
    end

    table.sort(sortedStats, function(a, b) return a.count > b.count end)

    -- 打印结果
    for _, data in ipairs(sortedStats) do
        local nameEX, serverEX = UnitNameFromGUID(data.guid)
        local safeNameEX = NormalizeSafeText(nameEX)
        local safeServerEX = NormalizeSafeText(serverEX)
        if safeNameEX then
            if safeServerEX then
                print(string.format("|cffffffff%s-%s|r: |cff00ff00%d|r 次", safeNameEX, safeServerEX, data.count))
            else
                print(string.format("|cffffffff%s|r: |cff00ff00%d|r 次", safeNameEX, data.count))
            end
        else
            print(string.format("|cffaaaaaa%s|r: |cff00ff00%d|r 次", data.guid, data.count))
        end
    end
end

-- 打印内建伤害统计的打断次数
local function PrintBlizzardInterruptStats()
    local sessionTypeEX = 0 -- Overall
    local meterTypeEX = 5   -- Interrupts

    if not C_DamageMeter then
        print("|cffff0000[内建统计]|r C_DamageMeter 不可用")
        return
    end

    local totalBySourceEX = {}

    local unitsEX = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            table.insert(unitsEX, "raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            table.insert(unitsEX, "party" .. i)
        end
    end

    for _, unitEX in ipairs(unitsEX) do
        local guidEX = UnitGUID(unitEX)
        if guidEX then
            local sessionSourceEX = C_DamageMeter.GetCombatSessionSourceFromType(sessionTypeEX, meterTypeEX, guidEX)

            if sessionSourceEX and sessionSourceEX.combatSpells then
                local totalEX = 0

                for _, spellEX in ipairs(sessionSourceEX.combatSpells) do
                    totalEX = totalEX + (spellEX.totalAmount or 0)
                end

                totalBySourceEX[guidEX] = totalEX
            end
        end
    end

    print("|cff00ffff===== 内建统计：打断次数 =====|r")

    if not next(totalBySourceEX) then
        print("|cffaaaaaa(暂无数据)|r")
        return
    end

    -- 按次数排序
    local sortedStats = {}
    for guid, count in pairs(totalBySourceEX) do
        table.insert(sortedStats, { guid = guid, count = count })
    end

    table.sort(sortedStats, function(a, b) return a.count > b.count end)

    for _, data in ipairs(sortedStats) do
        local nameEX, serverEX = UnitNameFromGUID(data.guid)
        local safeNameEX = NormalizeSafeText(nameEX)
        local safeServerEX = NormalizeSafeText(serverEX)
        if safeNameEX then
            if safeServerEX then
                print(string.format("|cffffffff%s-%s|r: |cff00ff00%d|r 次", safeNameEX, safeServerEX, data.count))
            else
                print(string.format("|cffffffff%s|r: |cff00ff00%d|r 次", safeNameEX, data.count))
            end
        else
            print(string.format("|cffaaaaaa%s|r: |cff00ff00%d|r 次", data.guid, data.count))
        end
    end
end

-- 打印完整统计报告
local function PrintInterruptReport()
    print(" ")
    print("|cffff00ff================================================|r")
    print("|cffff00ff          打断统计报告                         |r")
    print("|cffff00ff================================================|r")
    print(" ")

    -- 打印模块统计
    PrintCustomInterruptStats()
    print(" ")

    -- 打印内建统计
    PrintBlizzardInterruptStats()
    print(" ")
    print("|cffff00ff================================================|r")
end

local function HandleInterruptEvent(eventName, unit, spellID, interruptedBy, castBarID)
    local interruptedByIsNil = (interruptedBy == nil)
    DebugPrint(
        "收到 %s: unit=%s, spellID=%s, castBarID=%s, interruptedByIsNil=%s, secretInterruptedBy=%s",
        tostring(eventName), tostring(unit), tostring(spellID), tostring(castBarID), tostring(interruptedByIsNil),
        tostring(IsSecretValue(interruptedBy)))

    if not EX_DB.enabled then
        DebugPrint("事件忽略: 模块未启用")
        return
    end
    if isPreviewing then
        DebugPrint("事件忽略: 当前处于预览模式")
        return
    end
    if not isValidEnvironment then
        DebugPrint("事件忽略: isValidEnvironment=false")
        PrintDebugSnapshot()
        return
    end
    if not IsTrackedNameplateUnit(unit) then
        DebugPrint("事件忽略: unit 不是 nameplate1-40, unit=%s", tostring(unit))
        return
    end
    if interruptedBy == nil then
        DebugPrint("事件忽略: interruptedBy 为空")
        return
    end

    RecordInterrupt(interruptedBy)

    -- UnitTokenFromGUID 为 nil = 队友打断，不为 nil = 玩家本人（CD 由 UNIT_SPELLCAST_SUCCEEDED 处理）
    local interrupterToken = UnitTokenFromGUID(interruptedBy)
    if interrupterToken == nil then
        local okAdd, reason = AddInterruptRecord(interruptedBy, spellID, unit, nil)
        DebugPrint("事件处理结束: AddInterruptRecord=%s, reason=%s",
            tostring(okAdd), tostring(reason))
    else
        DebugPrint("玩家本人打断（统计已记录，CD 由 SPELLCAST_SUCCEEDED 触发）: token=%s", tostring(interrupterToken))
    end
end

ExwindTools:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", EXWIND_MODULE_KEY,
    function(_, unit, castGUID, spellID, interruptedBy, castBarID)
        HandleInterruptEvent("UNIT_SPELLCAST_INTERRUPTED", unit, spellID, interruptedBy, castBarID)
    end)

ExwindTools:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", EXWIND_MODULE_KEY .. "_ChannelStop",
    function(_, unit, castGUID, spellID, interruptedBy, castBarID)
        HandleInterruptEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit, spellID, interruptedBy, castBarID)
    end)

-- =============================================================
-- 玩家打断施法成功 → 触发玩家条进入 CD
-- =============================================================
ExwindTools:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", EXWIND_MODULE_KEY .. "_PlayerInterrupt",
    function(_, unit, _, spellID)
        if unit ~= "player" then return end
        if not EX_DB.enabled then return end
        if isPreviewing then return end
        local interruptData = GetPlayerInterruptData()
        if not interruptData or interruptData.cd <= 0 then return end
        if spellID ~= interruptData.id then return end
        -- 玩家打断技能施法成功 → 计时条进入 CD
        playerSelfBarOnCD = true
        playerSelfBarStartTime = GetTime()
        playerSelfBarDuration = interruptData.cd
        if playerSelfBar then
            playerSelfBar:SetMinMaxValues(0, playerSelfBarDuration)
            playerSelfBar:SetValue(playerSelfBarDuration)
            SetupPlayerSelfBarOnUpdate()
        end
    end)

-- =============================================================
-- 事件处理
-- =============================================================
ExwindTools:RegisterEvent("EX_PARTY_SPEC_UPDATED", EXWIND_MODULE_KEY, function()
    if not isPreviewing then
        UpdateLayout()
    end
end)

ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY, function()
    if not isPreviewing then
        UpdateLayout()
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    EX_DB.preview = false
    C_Timer.After(1, function()
        CreateAnchor()
        UpdateLayout()
    end)
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".DatabaseChanged", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    if isEditModeActive and (info.key == "preview" or info.key == "locked") then
        return
    end

    if info.key == "preview" then
        TogglePreview(EX_DB.preview)
    elseif info.key == "attachToCustom" or info.key == "customAttachTarget" then
        if anchorFrame then
            ApplyStandaloneAnchorPosition()
        end
        RefreshAll()
    elseif info.key == "displayStyle" then
        for _, data in pairs(activeBars) do
            if data.bar then
                data.bar:SetParent(anchorFrame or UIParent)
                ReleaseVisual(data.bar)
            end
        end
        wipe(activeBars)
        wipe(usedBarsList)
        ReleasePreviewBars()
        if isPreviewing then
            TogglePreview(true)
        else
            UpdateLayout()
        end
    elseif info.key == "enabled" then
        if EX_DB.enabled then
            CreateAnchor()
            UpdateLayout()
        else
            if anchorFrame then
                anchorFrame:Hide()
                anchorFrame:EnableMouse(false)
                if anchorFrame.bg then anchorFrame.bg:Hide() end
                if anchorFrame.label then anchorFrame.label:Hide() end
            end
            ClearRuntimeBars()
            ReleasePlayerSelfBar()
        end
    else
        RefreshAll()
    end
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if info.key == "btn_reset_pos" then
        EX_DB.posX = 0
        EX_DB.posY = -200
        EnsureAnchorController():SyncWidgets()
        if anchorFrame then
            ApplyStandaloneAnchorPosition()
        end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        EnsureAnchorController():StartFramePicker()
    end
end)

-- 专精切换时重置玩家条（换专精可能打断技能变化）
ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY .. "_PlayerSpec", function()
    if not isPreviewing then
        playerSelfBarOnCD = false
        RefreshPlayerSelfBar()
        UpdateLayout()
    end
end)

EnsureAnchorController():RegisterEditModeHandler()

-- =============================================================
-- 大秘境事件监听
-- =============================================================

-- 监听大秘境开始事件
ExwindTools:RegisterEvent("CHALLENGE_MODE_START", EXWIND_MODULE_KEY, function()
    isInMythicPlus = true
    ResetInterruptStats()
end)

-- 监听大秘境完成事件
ExwindTools:RegisterEvent("CHALLENGE_MODE_COMPLETED", EXWIND_MODULE_KEY, function()
    if isInMythicPlus then
        -- print("|cff00ff00[打断统计]|r 大秘境已完成，数据已保存")
    end
end)

-- 监听大秘境重置事件
ExwindTools:RegisterEvent("CHALLENGE_MODE_RESET", EXWIND_MODULE_KEY, function()
    if isInMythicPlus then
        -- print("|cffff8800[打断统计]|r 大秘境已重置")
    end
    isInMythicPlus = false
end)

-- 监听进入世界（重载也会触发）
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY .. "_EnterWorld", function()
    -- 检测是否在大秘境中
    local _, instanceType = GetInstanceInfo()
    local isMythicPlusInstance = (instanceType == "party" and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo())

    -- 只做统计用的标志位更新
    if isMythicPlusInstance then
        isInMythicPlus = true
    else
        isInMythicPlus = false
    end

    -- 检测环境并更新UI
    CheckEnvironment()
end)

-- =============================================================
-- State 监听：环境变化时自动启用/禁用
-- =============================================================
-- 监听队伍状态变化
ExwindTools:WatchState("IsInParty", EXWIND_MODULE_KEY .. "_PartyWatch", function()
    CheckEnvironment()
end)

-- 监听副本类型变化
ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY .. "_InstanceWatch", function()
    CheckEnvironment()
end)

-- =============================================================
-- 斜杠命令注册
-- =============================================================

-- 注册 /extest 命令
_G.SLASH_EXTEST1 = "/extest"
_G.SlashCmdList["EXTEST"] = function()
    PrintInterruptReport()
end

_G.SLASH_EXINTDEBUG1 = "/exintdebug"
_G.SlashCmdList["EXINTDEBUG"] = function(msg)
    local cmd = string.lower(tostring(msg or ""))
    if cmd == "on" then
        interruptDebugEnabled = true
    elseif cmd == "off" then
        interruptDebugEnabled = false
    else
        interruptDebugEnabled = not interruptDebugEnabled
    end

    print(string.format("|cff33ff99[ExInterruptDebug]|r 调试已%s", interruptDebugEnabled and "开启" or "关闭"))
    if interruptDebugEnabled then
        PrintDebugSnapshot()
    end
end

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

-- 重置注册（供 ToolsPage 重置按钮调用）
ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    local moduleDB = _G.ExwindToolsDB and _G.ExwindToolsDB.ModuleDB
    if not moduleDB or not moduleDB[EXWIND_MODULE_KEY] then return end
    wipe(moduleDB[EXWIND_MODULE_KEY])
    ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)
    ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".DatabaseChanged", { key = "*" })
end

-- =============================================================
-- GUI 渲染接口（由 ToolsPage embed 调用）
-- =============================================================
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.InterruptTrackerPage = ExBoss.UI.Panel.InterruptTrackerPage or {}
local GUIPage = ExBoss.UI.Panel.InterruptTrackerPage

local BASE_COLS = 53
local TARGET_CELL = 18

function GUIPage:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end

    if not GUIPage._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_InterruptTrackerSettingsScroll", contentFrame,
            "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        GUIPage._scrollFrame = sf
        GUIPage._scrollChild = sc
    end

    local sf = GUIPage._scrollFrame
    local sc = GUIPage._scrollChild

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if not sf:IsShown() then return end
        local width = contentFrame:GetWidth()
        if width < 100 then width = 820 end
        sc:SetWidth(width - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()

        local cols = math.max(BASE_COLS, math.floor((((sc:GetWidth() or width) - 20) / TARGET_CELL) + 0.5))
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end

        ExwindTools.UI.ActivePageFrame = sc
        ExwindTools.UI.CurrentModule = EXWIND_MODULE_KEY
        Grid:Render(sc, EX_LAYOUT, EX_DB, EXWIND_MODULE_KEY)
    end)
end

function GUIPage:Hide()
    if GUIPage._scrollFrame then
        GUIPage._scrollFrame:Hide()
        if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == GUIPage._scrollChild then
            ExwindTools.UI.ActivePageFrame = nil
            ExwindTools.UI.CurrentModule = nil
        end
    end
end
