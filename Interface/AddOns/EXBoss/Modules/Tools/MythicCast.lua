-- =============================================================
-- [[ EXBoss Tools: MythicCast ]]
-- =============================================================

local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
local BorderUtil = ExBoss.BorderUtil

local EXWIND_MODULE_KEY = "ExBoss.Tools.MythicCast"
local LSM = LibStub("LibSharedMedia-3.0") -- 假定 ExwindTools 环境中有 LSM
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end
local EXWIND_PLAYER_TARGET_ATLAS = "icons_64x64_deadly"
local EXWIND_PLAYER_TARGET_ATLAS_OPTIONS = {
    { label = "致命", atlas = "icons_64x64_deadly" },
    { label = "史诗难度", atlas = "GM-icon-difficulty-mythicSelected-hover" },
    { label = "PVP事件", atlas = "UI-EventPoi-pvp" },
    { label = "警告", atlas = "Ping_Wheel_Icon_Warning_Small" },
    { label = "进攻", atlas = "Ping_Marker_Icon_Attack" },
    { label = "非威胁", atlas = "Ping_Marker_Icon_NonThreat" },
    { label = "威胁", atlas = "Ping_Marker_Icon_Threat" },
    { label = "十字准星", atlas = "cursor_crosshairs_48" },
    { label = "疾病", atlas = "icons_64x64_disease" },
    { label = "伤害", atlas = "icons_64x64_damage" },
    { label = "激怒", atlas = "icons_64x64_enrage" },
}

function ExBoss.GetMythicCastTargetIndicatorAtlasOptions()
    local items = {}
    for _, info in ipairs(EXWIND_PLAYER_TARGET_ATLAS_OPTIONS) do
        local displayText = CreateAtlasMarkup and CreateAtlasMarkup(info.atlas, 18, 18) or ""
        items[#items + 1] = { displayText, info.atlas }
    end
    return items
end

-- ------------------------------------------------------------
-- 常量定义
-- ------------------------------------------------------------
local EXWIND_COLOR_INTERRUPTIBLE = CreateColor(0, 1, 0)     -- 能打断 (绿)
local EXWIND_COLOR_NOT_INTERRUPTIBLE = CreateColor(1, 0, 0) -- 不能打断 (红)

local ExwindFactory = _G.ExwindFactory

-- ------------------------------------------------------------
-- 本地变量
-- ------------------------------------------------------------
local activeBars = {}
local usedBarsList = {}
local previewBars = {}
local anchorFrame = nil
local anchorController = nil
local editHandleFrame = nil
local isPreviewing = false
local isEditModeActive = false
local isEditModeVisible = true
local TogglePreview
local UpdateCast
local RefreshAll
local ReLayout
local CreateAnchor
local StartFramePicker

local function RefreshEditOverlay()
    return
end

-- 常用 API 引用
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local C_ClassColor = _G.C_ClassColor
local string = _G.string
local type = _G.type
local pairs = _G.pairs
local math = _G.math
local table = _G.table

local function ApplyBackdropBorder(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
    if not borderFrame or not targetFrame or not texturePath then
        return
    end
    local targetLevel = type(targetFrame.GetFrameLevel) == "function" and targetFrame:GetFrameLevel() or 0
    borderFrame:SetFrameLevel(frameLevel or (targetLevel + 2))
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)

    if issecretvalue and issecretvalue(borderFrame:GetWidth()) then
        if borderFrame.SetBackdrop then
            borderFrame:SetBackdrop(nil)
        end
        borderFrame:Hide()
        return
    end

    borderFrame:SetBackdrop({
        edgeFile = texturePath,
        edgeSize = edgeSize,
    })
    borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    borderFrame:Show()
end

local function HideBackdropBorder(borderFrame)
    if borderFrame then
        borderFrame:Hide()
    end
end

local function SyncIconAnchor(bar, group, isIconMode)
    if not bar.IconAnchor then
        bar.IconAnchor = CreateFrame("Frame", nil, bar)
    end
    local anchor = bar.IconAnchor
    anchor:ClearAllPoints()
    if isIconMode then
        anchor:SetAllPoints(bar)
    else
        anchor:SetSize(group.iconSize or 20, group.iconSize or 20)
        if (group.iconSide or "LEFT") == "LEFT" then
            anchor:SetPoint("RIGHT", bar, "LEFT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        else
            anchor:SetPoint("LEFT", bar, "RIGHT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        end
    end
    return anchor
end
local ipairs               = _G.ipairs
local print                = _G.print
local UnitExists           = _G.UnitExists
local UnitAffectingCombat  = _G.UnitAffectingCombat
local UnitCastingInfo      = _G.UnitCastingInfo
local UnitChannelInfo      = _G.UnitChannelInfo
local UnitCastingDuration  = _G.UnitCastingDuration
local UnitChannelDuration  = _G.UnitChannelDuration
local PlayerIsSpellTarget  = _G.PlayerIsSpellTarget
local UnitSpellTargetName  = _G.UnitSpellTargetName
local UnitSpellTargetClass = _G.UnitSpellTargetClass
local UnitLevel            = _G.UnitLevel
local CreateColor          = _G.CreateColor
local C_StringUtil         = _G.C_StringUtil
local C_Timer              = _G.C_Timer

local pendingCastUpdates   = {}
local castUpdateGeneration = 0

-- ------------------------------------------------------------
-- 1. Grid 布局定义
-- ------------------------------------------------------------
local EX_LAYOUT
local function EX_RegisterLayout()
    EX_LAYOUT = {
        { key = "header", type = "header", x = 1, y = 1, w = 53, h = 2, label = L["大米怪物施法 (MythicCast)"], labelSize = 25 },
        { key = "enabled", type = "checkbox", x = 1, y = 4, w = 6, h = 2, label = L["启用"] },
        { key = "locked", type = "checkbox", x = 9, y = 4, w = 8, h = 2, label = L["锁定位置"] },
        { key = "preview", type = "checkbox", x = 19, y = 4, w = 8, h = 2, label = L["预览模式"] },
        { key = "btn_reset_pos", type = "button", x = 40, y = 4, w = 14, h = 2, label = L["重置位置"] },
        { key = "custom_attach_header", type = "header", x = 1, y = 8, w = 53, h = 2, label = L["自由依附 (Beta)"], labelSize = 20 },
        { key = "custom_attach_desc", type = "description", x = 1, y = 10, w = 53, h = 1, label = L["开启后可将施法条组依附于任意 UI 元素。若目标框体不存在，将自动对齐到屏幕中心。"] },
        { key = "attachToCustom", type = "checkbox", x = 1, y = 12, w = 10, h = 2, label = L["启用自由依附"] },
        { key = "customAttachTarget", type = "input", x = 12, y = 12, w = 26, h = 2, label = L["当前目标路径"] },
        { key = "btn_pick_frame", type = "button", x = 40, y = 12, w = 10, h = 2, label = L["鼠标选取"] },
        { key = "posX", type = "slider", x = 1, y = 16, w = 12, h = 2, label = L["整体水平位置"], min = -1000, max = 1000 },
        { key = "posY", type = "slider", x = 15, y = 16, w = 12, h = 2, label = L["整体垂直位置"], min = -1000, max = 1000 },
        { key = "hideLevel91Casts", type = "checkbox", x = 15, y = 19, w = 12, h = 2, label = L["隐藏91级读条"] },
        { key = "hideLevel92Casts", type = "checkbox", x = 1, y = 19, w = 12, h = 2, label = L["隐藏92级读条"] },
        { key = "disabledBossEncounterIDs", type = "input", x = 1, y = 23, w = 53, h = 2, label = L["首领战禁用(输入首领战ID 用,分隔)"] },
        { key = "raid_header", type = "header", x = 1, y = 26, w = 53, h = 2, label = L["团队标记"], labelSize = 20 },
        { key = "showRaidIcon", type = "checkbox", x = 1, y = 29, w = 8, h = 2, label = L["显示团队标记"] },
        { key = "raidIconSize", type = "slider", x = 15, y = 29, w = 12, h = 2, label = L["标记大小"], min = 10, max = 64 },
        { key = "showPlayerTargetIndicator", type = "checkbox", x = 1, y = 34, w = 9, h = 2, label = L["玩家目标提示"] },
        { key = "playerTargetIndicatorAtlas", type = "dropdown", x = 15, y = 34, w = 12, h = 2, label = L["提示材质"], items = "func:ExBoss.GetMythicCastTargetIndicatorAtlasOptions()" },
        { key = "raidIconX", type = "slider", x = 29, y = 29, w = 12, h = 2, label = L["水平偏移"], min = -100, max = 100 },
        { key = "raidIconY", type = "slider", x = 42, y = 29, w = 12, h = 2, label = L["垂直偏移"], min = -100, max = 100 },
        { key = "playerTargetIndicatorSize", type = "slider", x = 29, y = 34, w = 12, h = 2, label = L["提示大小"], min = 8, max = 64 },
        { key = "playerTargetIndicatorX", type = "slider", x = 15, y = 38, w = 12, h = 2, label = L["提示X偏移"], min = -100, max = 100 },
        { key = "playerTargetIndicatorY", type = "slider", x = 29, y = 38, w = 12, h = 2, label = L["提示Y偏移"], min = -100, max = 100 },
        { key = "color_header", type = "header", x = 1, y = 41, w = 53, h = 2, label = L["计时条外观"], labelSize = 20 },
        {
            key = "displayMode",
            type = "dropdown",
            x = 1,
            y = 44,
            w = 12,
            h = 2,
            label = L["显示模式"],
            items = {
                { L["进度条模式"], "bar" },
                { L["图标模式"], "icon" },
            }
        },
        { key = "iconModeSize", type = "slider", x = 15, y = 44, w = 12, h = 2, label = L["图标尺寸"], min = 20, max = 80 },
        { key = "iconModeTimerSize", type = "slider", x = 29, y = 44, w = 12, h = 2, label = L["秒数字号"], min = 8, max = 32 },
        { key = "nonInterruptColor", type = "color", x = 42, y = 44, w = 12, h = 2, label = L["无法打断颜色"], labelPos = "top" },
        { key = "spacing", type = "slider", x = 1, y = 48, w = 12, h = 2, label = L["垂直间距"], min = 0, max = 50 },
        { key = "growDirection", type = "dropdown", x = 15, y = 48, w = 12, h = 2, label = L["增长方向"], items = "向下,向上" },
        { key = "maxBars", type = "slider", x = 29, y = 48, w = 12, h = 2, label = L["最大显示数量"], min = 1, max = 15 },
        { key = "timerGroup", type = "timerBarGroupV2", x = 1, y = 51, w = 53, h = 40, label = "", labelSize = 20 },
        { key = "font_spell_header", type = "header", x = 1, y = 98, w = 53, h = 2, label = L["法术名称"], labelSize = 20 },
        { key = "textAlign", type = "dropdown", x = 1, y = 101, w = 15, h = 2, label = L["对齐方式"], items = "LEFT,CENTER,RIGHT" },
        { key = "font_spell", type = "fontgroup", x = 1, y = 103, w = 53, h = 17, label = L["法术名称"], labelSize = 20 },
        { key = "font_target_header", type = "header", x = 1, y = 121, w = 53, h = 2, label = L["施法目标"], labelSize = 20 },
        { key = "showTarget", type = "checkbox", x = 1, y = 124, w = 12, h = 2, label = L["显示目标姓名"] },
        { key = "targetAlign", type = "dropdown", x = 16, y = 124, w = 12, h = 2, label = L["对齐方式"], items = "LEFT,CENTER,RIGHT" },
        { key = "mergeTargetIntoSpellName", type = "checkbox", x = 29, y = 124, w = 12, h = 2, label = L["并入法术名称"] },
        { key = "spellTargetInlineFormat", type = "input", x = 42, y = 124, w = 12, h = 2, label = L["中间分隔符"] },
        { key = "font_target", type = "fontgroup", x = 1, y = 128, w = 53, h = 18, label = L["施法目标"], labelSize = 20 },
        { key = "font_timer_header", type = "header", x = 1, y = 148, w = 53, h = 2, label = L["冷却时间"], labelSize = 20 },
        { key = "showTimer", type = "checkbox", x = 1, y = 151, w = 15, h = 2, label = L["显示时间文字"] },
        { key = "timerAlign", type = "dropdown", x = 17, y = 151, w = 15, h = 2, label = L["对齐方式"], items = "LEFT,CENTER,RIGHT" },
        { key = "font_timer", type = "fontgroup", x = 1, y = 154, w = 53, h = 18, label = L["冷却时间"], labelSize = 20 },
        { key = "divider_7758", type = "divider", x = 1, y = 32, w = 53, h = 1, label = L["新组件"] },
    }






    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)
end
EX_RegisterLayout()

local EX_DEFAULTS = {
    enabled = false,
    font_spell = {
        a = 1,
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1,
        size = 20,
        x = 2,
        y = 0,
    },
    font_target = {
        a = 1,
        b = 0.40392160415649,
        font = "默认",
        g = 0.80000007152557,
        outline = "OUTLINE",
        r = 0.27058824896812,
        shadow = false,
        shadowX = 1,
        size = 16,
        x = 38,
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
        shadowX = 9,
        size = 17,
        x = 0,
        y = 0,
    },
    displayMode = "bar",
    disabledBossEncounterIDs = "",
    iconModeSize = 36,
    iconModeTimerSize = 16,
    growDirection = "向上",
    hideLevel91Casts = false,
    hideLevel92Casts = false,
    locked = true,
    maxBars = 6,
    nonInterruptColorA = 1,
    nonInterruptColorB = 0.16862745583057,
    nonInterruptColorG = 0.1294117718935,
    nonInterruptColorR = 1,
    posX = -527,
    posY = -12,
    preview = false,
    playerTargetIndicatorAtlas = EXWIND_PLAYER_TARGET_ATLAS,
    playerTargetIndicatorSize = 20,
    playerTargetIndicatorX = 0,
    playerTargetIndicatorY = 0,
    raidIconSize = 27,
    raidIconX = -1,
    raidIconY = 0,
    -- scale removed
    showPlayerTargetIndicator = true,
    showRaidIcon = true,
    showTarget = true,
    showTimer = true,
    mergeTargetIntoSpellName = false,
    spellTargetInlineFormat = "-",
    spacing = 1,
    targetAlign = "CENTER",
    textAlign = "LEFT",
    timerAlign = "RIGHT",
    attachToCustom = false,  -- 是否启用自由依附
    customAttachTarget = "", -- 目标框架名称或路径
    timerGroup = {
        barBgColor = {
            a = 0.5,
            b = 0,
            g = 0,
            r = 0,
        },
        barBgColorA = 0.71539187431335,
        barBgColorB = 0.27843138575554,
        barBgColorG = 0.27843138575554,
        barBgColorR = 0.27843138575554,
        barColor = {
            a = 1,
            b = 0,
            g = 0.7,
            r = 1,
        },
        barColorA = 1,
        barColorB = 1,
        barColorG = 0.90980398654938,
        barColorR = 0.29019609093666,
        height = 28,
        iconOffsetX = 0,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconSize = 30,
        showIcon = true,
        showIconBorder = false,
        iconBorderTexture = "Square Full White",
        iconBorderColorR = 0,
        iconBorderColorG = 0,
        iconBorderColorB = 0,
        iconBorderColorA = 1,
        iconBorderSize = 1,
        iconBorderPadding = 0,
        texture = "Melli",
        width = 224,
    },
}

local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)
local disabledBossEncounterRaw = nil
local disabledBossEncounterSet = nil

local function GetAnchorPointForGrowDirection()
    if EX_DB.growDirection == "向上" then
        return "BOTTOM"
    end
    return "TOP"
end

local function EnsureAnchorController()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExBossMythicCastAnchor",
        title = L["大米怪物施法"],
        getDB = function()
            return EX_DB
        end,
        offsetXKey = "posX",
        offsetYKey = "posY",
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
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
        widgetRanges = {
            posX = { min = -1000, max = 1000, step = 1 },
            posY = { min = -1000, max = 1000, step = 1 },
        },
        initialWidth = 200,
        initialHeight = 20,
        clampedToScreen = true,
        getAnchorPoint = function()
            return GetAnchorPointForGrowDirection()
        end,
        relativePoint = "CENTER",
        onFramePicked = function()
            RefreshAll()
        end,
        onEditModeChanged = function(_, active, visible)
            isEditModeActive = active == true
            isEditModeVisible = visible == true

            if isEditModeActive then
                EX_DB.locked = not isEditModeVisible
                EX_DB.preview = isEditModeVisible
                CreateAnchor()
                TogglePreview(isEditModeVisible)
                RefreshAll()
                if anchorFrame and isEditModeVisible then
                    if anchorFrame.bg then anchorFrame.bg:Hide() end
                    if anchorFrame.label then anchorFrame.label:Hide() end
                end
                RefreshEditOverlay()
            else
                TogglePreview(EX_DB.preview)
                RefreshAll()
                RefreshEditOverlay()
            end
        end,
    })

    return anchorController
end

local function GetColor(dbKey)
    local r, g, b, a = EX_DB[dbKey .. "R"], EX_DB[dbKey .. "G"], EX_DB[dbKey .. "B"], EX_DB[dbKey .. "A"]
    if r == nil and EX_DB[dbKey] and type(EX_DB[dbKey]) == "table" then
        return EX_DB[dbKey].r, EX_DB[dbKey].g, EX_DB[dbKey].b, EX_DB[dbKey].a
    end
    return r or 1, g or 1, b or 1, a or 1
end

local function GetDisabledBossEncounterSet()
    local raw = EX_DB.disabledBossEncounterIDs
    if raw == disabledBossEncounterRaw then
        return disabledBossEncounterSet
    end

    disabledBossEncounterRaw = raw
    disabledBossEncounterSet = nil
    if type(raw) ~= "string" or raw == "" then
        return nil
    end

    local set = {}
    for token in string.gmatch(raw, "[^,;/|%s]+") do
        local encounterID = tonumber(token)
        if encounterID and encounterID > 0 then
            set[encounterID] = true
        end
    end

    if next(set) ~= nil then
        disabledBossEncounterSet = set
    end
    return disabledBossEncounterSet
end

local function IsDisabledInBossEncounter()
    if ExwindTools.State.IsBossEncounter ~= true then
        return false
    end

    local encounterID = tonumber(ExwindTools.State.EncounterID) or 0
    if encounterID <= 0 then
        return false
    end

    local disabledSet = GetDisabledBossEncounterSet()
    return type(disabledSet) == "table" and disabledSet[encounterID] == true
end

local function BuildInlineTargetText(targetName, targetClass)
    if not targetName then
        return targetName
    end

    local coloredTarget = targetName
    if targetClass then
        local classColor = C_ClassColor.GetClassColor(targetClass)
        if classColor and classColor.GenerateHexColor and WrapTextInColorCode then
            coloredTarget = WrapTextInColorCode(targetName, classColor:GenerateHexColor())
        end
    end

    local separator = EX_DB.spellTargetInlineFormat
    if type(separator) ~= "string" or separator == "" then
        separator = "-"
    end

    -- 兼容旧配置：如果用户之前填的是 "%s - %s" 这种格式串，自动提取中间分隔符
    local extracted = separator:match("^%%s(.-)%%s$")
    if extracted ~= nil then
        separator = extracted
    end

    local wrappedTarget = coloredTarget
    if C_StringUtil and C_StringUtil.WrapString then
        wrappedTarget = C_StringUtil.WrapString(coloredTarget, separator)
    else
        wrappedTarget = string.concat(separator, coloredTarget)
    end
    return wrappedTarget
end

local function BuildMergedSpellText(spellName, targetName, targetClass)
    if not spellName or not targetName then
        return spellName
    end

    local inlineTarget = BuildInlineTargetText(targetName, targetClass)
    if string.concat then
        return string.concat(spellName, inlineTarget)
    end
    return spellName
end

local function UpdateBarVisuals(bar)
    local db = EX_DB
    local group = db.timerGroup or {}
    local barWidth = group.width or 200
    local spellTextWidth
    if db.mergeTargetIntoSpellName then
        spellTextWidth = math.max(40, math.floor(barWidth * 0.85))
    else
        local timerReserve = db.showTimer and 48 or 0
        spellTextWidth = math.max(40, barWidth - timerReserve - 8)
    end
    -- 1. 基础视觉
    bar:SetSize(barWidth, group.height or 20)
    local texName = group.texture or "Melli"
    local tex = LSM:Fetch("statusbar", texName)
    if not tex then tex = "Interface\\Buttons\\WHITE8X8" end

    if bar.bg then
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(
            group.barBgColorR or 0,
            group.barBgColorG or 0,
            group.barBgColorB or 0,
            group.barBgColorA or 0.5
        )
        bar.bg:SetAlpha(group.barBgColorA or 0.5)
    end
    bar:SetStatusBarTexture(tex)

    -- [Feature] 应用边框相关样式 (确保边框渲染于状态条前台)
    local edgeTex = group.showBorder and group.borderTexture and group.borderTexture ~= "None" and
        LSM:Fetch("border", group.borderTexture) or nil
    local textFrameLevel = bar:GetFrameLevel() + 3
    if edgeTex then
        if not bar.BorderFrame then
            bar.BorderFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        end
        local edgeSize = group.borderSize or 12
        local pad = group.borderPadding or 0
        local br, bg, bb, ba = group.borderColorR or 1, group.borderColorG or 1, group.borderColorB or 1,
            group.borderColorA or 1
        ApplyBackdropBorder(bar.BorderFrame, bar, edgeTex, edgeSize, pad, br, bg, bb, ba, bar:GetFrameLevel() + 2)
    else
        if bar.BorderFrame then
            HideBackdropBorder(bar.BorderFrame)
        end
    end

    if bar.TextFrame then
        bar.TextFrame:SetFrameLevel(textFrameLevel)
    end

    -- 2. 应用标准字体组 (EXDB:ApplyFont 会处理字体/大小/颜色/描边/阴影)
    local StaticDB = ExwindTools.DB_Static

    if bar.Text then
        StaticDB:ApplyFont(bar.Text, db.font_spell)
        bar.Text:ClearAllPoints()
        if db.mergeTargetIntoSpellName then
            bar.Text:SetPoint("LEFT", bar, "LEFT", db.font_spell.x, db.font_spell.y)
            bar.Text:SetJustifyH("LEFT")
        else
            bar.Text:SetPoint(db.textAlign, bar, db.textAlign, db.font_spell.x, db.font_spell.y)
            bar.Text:SetJustifyH(db.textAlign)
        end
        bar.Text:SetWidth(spellTextWidth)
        bar.Text:SetMaxLines(1)
        bar.Text:SetWordWrap(false)
        if bar.Text.SetNonSpaceWrap then
            bar.Text:SetNonSpaceWrap(false)
        end
    end

    if bar.TargetNameText then
        StaticDB:ApplyFont(bar.TargetNameText, db.font_target)
        bar.TargetNameText:ClearAllPoints()
        if db.mergeTargetIntoSpellName then
            -- 并排模式下不沿用独立目标名的大偏移量，否则会在中间制造大量空白
            bar.TargetNameText:SetPoint("LEFT", bar.Text, "RIGHT", 2, db.font_target.y)
            bar.TargetNameText:SetJustifyH("LEFT")
        else
            bar.TargetNameText:SetPoint(db.targetAlign, bar, db.targetAlign, db.font_target.x, db.font_target.y)
            bar.TargetNameText:SetJustifyH(db.targetAlign)
        end
        bar.TargetNameText:SetShown(db.showTarget and not db.mergeTargetIntoSpellName)
        bar.TargetNameText:SetWidth(math.max(30, barWidth - 16))
        bar.TargetNameText:SetMaxLines(1)
        bar.TargetNameText:SetWordWrap(false)
        if bar.TargetNameText.SetNonSpaceWrap then
            bar.TargetNameText:SetNonSpaceWrap(false)
        end


        if bar._isPreview then
            local _, class = UnitClass("player")
            local colorObj = C_ClassColor.GetClassColor(class)
            if colorObj then
                bar.TargetNameText:SetTextColor(colorObj.r, colorObj.g, colorObj.b, 1)
            end
        end
    end

    if bar.TimerText then
        StaticDB:ApplyFont(bar.TimerText, db.font_timer)
        bar.TimerText:ClearAllPoints()
        bar.TimerText:SetPoint(db.timerAlign, bar, db.timerAlign, db.font_timer.x, db.font_timer.y)
        bar.TimerText:SetJustifyH(db.timerAlign)
        bar.TimerText:SetShown((db.showTimer and bar._isPreview) or false)
    end

    if bar.Cooldown then
        bar.Cooldown:SetFrameLevel(textFrameLevel)
        bar.Cooldown:ClearAllPoints()
        bar.Cooldown:SetAllPoints(bar)
        bar.Cooldown:SetReverse(true)
        bar.Cooldown:SetDrawSwipe(false)
        bar.Cooldown:SetDrawEdge(false)
        bar.Cooldown:SetDrawBling(false)
        if bar.Cooldown.SetMinimumCountdownDuration then
            bar.Cooldown:SetMinimumCountdownDuration(0)
        end
        if bar.Cooldown.SetCountdownMillisecondsThreshold then
            bar.Cooldown:SetCountdownMillisecondsThreshold(10)
        end
        if bar.Cooldown.SetCountdownAbbrevThreshold then
            bar.Cooldown:SetCountdownAbbrevThreshold(60)
        end
        bar.Cooldown:SetHideCountdownNumbers(not db.showTimer or bar._isPreview)

        local countdown = bar.Cooldown.GetCountdownFontString and bar.Cooldown:GetCountdownFontString() or nil
        if countdown then
            StaticDB:ApplyFont(countdown, db.font_timer)
            countdown:ClearAllPoints()
            countdown:SetPoint(db.timerAlign, bar, db.timerAlign, db.font_timer.x, db.font_timer.y)
            countdown:SetJustifyH(db.timerAlign)
        end
    end
    if bar.Icon then
        bar.Icon:SetSize(group.iconSize or 20, group.iconSize or 20)
        bar.Icon:ClearAllPoints()
        local side = group.iconSide or "LEFT"
        if side == "LEFT" then
            bar.Icon:SetPoint("RIGHT", bar, "LEFT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        else
            bar.Icon:SetPoint("LEFT", bar, "RIGHT", group.iconOffsetX or 0, group.iconOffsetY or 0)
        end
        bar.Icon:SetShown(group.showIcon)
        -- 为所有图标应用 8% 裁剪 (Zoom)，去除暴雪原生的黑边
        bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if bar.PlayerTargetIndicator then
        local atlasName = db.playerTargetIndicatorAtlas or EXWIND_PLAYER_TARGET_ATLAS
        local indicatorSize = math.max(8, db.playerTargetIndicatorSize or math.max(16, math.min(group.height or 20, 24)))
        if bar.PlayerTargetIndicatorFrame then
            local topFrameLevel = bar:GetFrameLevel() + 20
            if bar.Cooldown and bar.Cooldown.GetFrameLevel then
                topFrameLevel = math.max(topFrameLevel, bar.Cooldown:GetFrameLevel() + 10)
            end
            bar.PlayerTargetIndicatorFrame:SetFrameLevel(topFrameLevel)
            bar.PlayerTargetIndicatorFrame:Show()
        end
        bar.PlayerTargetIndicator:SetDrawLayer("OVERLAY", 7)
        bar.PlayerTargetIndicator:SetAtlas(atlasName)
        bar.PlayerTargetIndicator:SetSize(indicatorSize, indicatorSize)
        bar.PlayerTargetIndicator:ClearAllPoints()
        bar.PlayerTargetIndicator:SetPoint("CENTER", bar.PlayerTargetIndicatorFrame or bar, "CENTER",
            db.playerTargetIndicatorX or 0, db.playerTargetIndicatorY or 0)
        bar.PlayerTargetIndicator:SetShown(db.showPlayerTargetIndicator ~= false)
        if db.showPlayerTargetIndicator ~= false and bar._isPreview then
            bar.PlayerTargetIndicator:SetAlpha(1)
        else
            bar.PlayerTargetIndicator:SetAlpha(0)
        end
    end

    if bar.RaidIcon then
        -- 实时视觉预览：应用设置中的大小和位置
        bar.RaidIcon:SetSize(db.raidIconSize or 24, db.raidIconSize or 24)
        bar.RaidIcon:ClearAllPoints()
        bar.RaidIcon:SetPoint("RIGHT", bar.Icon, "LEFT", db.raidIconX or -2, db.raidIconY or 0)

        -- 在预览模式下，为了让用户看清位置，如果没有真实标记且开启了显示，展示一个模拟标记(大饼)
        -- 预览模式的特殊处理
        if bar._isPreview then
            if bar.RaidIcon and EX_DB.showRaidIcon then
                bar.RaidIcon:Show()
                -- [Fix] 支持显示不通的图标（1-8 循环）
                local idx = bar._previewRaidIndex or 1
                bar.RaidIcon:SetSpriteSheetCell(idx, 4, 4)
            else
                if bar.RaidIcon then
                    bar.RaidIcon:Hide()
                end
            end
        end
    end

    -- 3. 增强：预览模式实时颜色预览
    local sbTex = bar:GetStatusBarTexture()
    if sbTex and bar._isPreview then
        local nrR, nrG, nrB, nrA = GetColor("nonInterruptColor")
        local intColor = CreateColor(nrR, nrG, nrB, nrA)
        local normColor = CreateColor(
            group.barColorR or 1,
            group.barColorG or 0.7,
            group.barColorB or 0,
            group.barColorA or 1
        )
        -- 使用存储的 _isNotInt 状态，确保修改颜色后实时刷新
        sbTex:SetVertexColorFromBoolean(bar._isNotInt, intColor, normColor)
    end

    -- 4. 图标模式：隐藏进度条本体，仅显示图标 + 秒数
    local isIconMode = (db.displayMode == "icon")
    local iconSz = math.max(20, db.iconModeSize or 36)
    local timerFontSz = math.max(8, db.iconModeTimerSize or 16)
    if isIconMode then
        -- 隐藏进度条填充和背景
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(0, 0, 0, 0)
        if bar.bg then bar.bg:SetAlpha(0) end

        -- 调整整体尺寸为正方形图标
        bar:SetSize(iconSz, iconSz)

        -- 图标铺满整个 bar
        if bar.Icon then
            bar.Icon:ClearAllPoints()
            bar.Icon:SetAllPoints(bar)
            bar.Icon:SetSize(iconSz, iconSz)
            bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar.Icon:Show()
        end

        -- 秒数文字显示在图标右侧
        if bar.TimerText then
            bar.TimerText:ClearAllPoints()
            bar.TimerText:SetPoint("LEFT", bar, "RIGHT", 4, 0)
            bar.TimerText:SetJustifyH("LEFT")
            local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            bar.TimerText:SetFont(font, timerFontSz, "OUTLINE")
            bar.TimerText:SetTextColor(1, 1, 1, 1)
            bar.TimerText:Show()
        end

        -- 隐藏法术名、目标名（图标模式不显示文字）
        if bar.Text then bar.Text:Hide() end
        if bar.TargetNameText then bar.TargetNameText:Hide() end
        if bar.Cooldown then
            bar.Cooldown:SetHideCountdownNumbers(true); bar.Cooldown:Clear()
        end

        -- 不可打断：照抄原有 SetVertexColorFromBoolean 方式，避免触碰 Secret Boolean
        if bar.Icon and bar._isNotInt ~= nil then
            local nrR, nrG, nrB, nrA = GetColor("nonInterruptColor")
            local intColor = CreateColor(nrR, nrG, nrB, nrA)
            local normColor = CreateColor(
                group.barColorR or 1, group.barColorG or 0.7,
                group.barColorB or 0, group.barColorA or 1)
            bar.Icon:SetVertexColorFromBoolean(bar._isNotInt, intColor, normColor)
        end
    else
        -- 进度条模式：还原图标着色
        if bar.bg then bar.bg:SetAlpha(group.barBgColorA or 0.5) end
        if bar.Icon then
            bar.Icon:SetVertexColor(1, 1, 1, 1)
        end
    end

    local iconEdgeTex = group.showIconBorder and group.iconBorderTexture and group.iconBorderTexture ~= "None" and
        LSM:Fetch("border", group.iconBorderTexture) or nil
    if iconEdgeTex and bar.Icon and bar.Icon:IsShown() then
        local iconAnchor = SyncIconAnchor(bar, group, isIconMode)
        if not bar.IconBorderFrame then
            bar.IconBorderFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        end
        local iconEdgeSize = group.iconBorderSize or 1
        local iconPad = group.iconBorderPadding or 0
        local ibr, ibg, ibb, iba = group.iconBorderColorR or 0, group.iconBorderColorG or 0,
            group.iconBorderColorB or 0, group.iconBorderColorA or 1
        ApplyBackdropBorder(bar.IconBorderFrame, iconAnchor, iconEdgeTex, iconEdgeSize, iconPad, ibr, ibg, ibb, iba,
            bar:GetFrameLevel() + 2)
    else
        if bar.IconBorderFrame then
            HideBackdropBorder(bar.IconBorderFrame)
        end
    end
end

local function InvalidatePlayerTargetIndicator(bar, shouldHide)
    if not bar then return end
    if shouldHide and bar.PlayerTargetIndicator then
        bar.PlayerTargetIndicator:SetAlpha(0)
        if bar.PlayerTargetIndicatorFrame then
            bar.PlayerTargetIndicatorFrame:Hide()
        end
    end
end

local function UpdatePlayerTargetIndicator(bar, unit)
    if not bar or not bar.PlayerTargetIndicator then return end

    if EX_DB.showPlayerTargetIndicator == false then
        bar.PlayerTargetIndicator:SetAlpha(0)
        bar.PlayerTargetIndicator:Hide()
        if bar.PlayerTargetIndicatorFrame then
            bar.PlayerTargetIndicatorFrame:Hide()
        end
        return
    end

    if bar.PlayerTargetIndicatorFrame then
        bar.PlayerTargetIndicatorFrame:Show()
    end
    bar.PlayerTargetIndicator:Show()

    if bar._isPreview then
        bar.PlayerTargetIndicator:SetAlpha(1)
        return
    end

    if not unit or not PlayerIsSpellTarget or not bar.PlayerTargetIndicator.SetAlphaFromBoolean then
        bar.PlayerTargetIndicator:SetAlpha(0)
        return
    end

    bar.PlayerTargetIndicator:SetAlphaFromBoolean(PlayerIsSpellTarget(unit), 255, 0)
end

-- ------------------------------------------------------------
-- 锚点位移保存：支持自由依附模式下的相对坐标计算
-- ------------------------------------------------------------
local function SaveAnchorPosition()
    EnsureAnchorController():SavePosition()
end

ReLayout = function()
    if not anchorFrame then return end
    local group = EX_DB.timerGroup or {}
    local isIconMode = (EX_DB.displayMode == "icon")
    local height = isIconMode and math.max(20, EX_DB.iconModeSize or 36) or (group.height or 20)
    local spacing = EX_DB.spacing or 0
    local list = isPreviewing and previewBars or usedBarsList
    local growUp = (EX_DB.growDirection == "向上")
    local maxLimit = EX_DB.maxBars or 5

    local visibleCount = 0
    for i, bar in ipairs(list) do
        if i <= maxLimit then
            visibleCount = visibleCount + 1
            bar:Show()
            bar:EnableMouse(false) -- [v4.7 Fix] 禁止条条感应鼠标，防止遮挡锚点拖动
        else
            bar:Hide()
        end
    end

    local totalHeight = math.max(20, visibleCount * height + math.max(0, visibleCount - 1) * spacing)
    anchorFrame:SetSize(group.width or 220, totalHeight)

    if anchorFrame.bg then
        anchorFrame.bg:ClearAllPoints()
        anchorFrame.bg:SetAllPoints(anchorFrame)
        anchorFrame.label:ClearAllPoints()
        anchorFrame.label:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)

        -- 为背景手柄注入拖动逻辑 (转发给父级)
        anchorFrame.bg:EnableMouse(not EX_DB.locked)
        anchorFrame.bg:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and not EX_DB.locked then
                local onDragStart = anchorFrame:GetScript("OnDragStart")
                if type(onDragStart) == "function" then
                    onDragStart(anchorFrame)
                end
            elseif button == "RightButton" and ExwindTools.GlobalEditMode then
                -- [v4.7.2 Fix] 转发右键点击，解决背景层遮挡 HUD 注册钩子的问题
                ExwindTools:OpenConfig(EXWIND_MODULE_KEY)
            end
        end)
        anchorFrame.bg:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and anchorFrame.isMoving then
                local onDragStop = anchorFrame:GetScript("OnDragStop")
                if type(onDragStop) == "function" then
                    onDragStop(anchorFrame)
                end
            end
        end)

        -- 所有的条相对于固定的 anchorFrame 进行堆叠
        for i, bar in ipairs(list) do
            if i <= maxLimit then
                bar:ClearAllPoints()
                local yOffset = (i - 1) * (height + spacing)
                if growUp then
                    bar:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, yOffset)
                else
                    bar:SetPoint("TOP", anchorFrame, "TOP", 0, -yOffset)
                end
            end
        end

        if editHandleFrame then
            editHandleFrame:ClearAllPoints()
            editHandleFrame:SetAllPoints(anchorFrame)
        end
    end

    EnsureAnchorController():ApplyPosition()
end

RefreshAll = function()
    if isPreviewing then
        -- 如果在预览模式，重新生成指定数量的预览条
        TogglePreview(false)
        TogglePreview(true)
    else
        for unit, bar in pairs(activeBars) do
            UpdateBarVisuals(bar)
            UpdateCast(unit)
        end
    end
    ReLayout()
    if anchorFrame then
        -- 整体缩放功能已移除

        if EX_DB.locked then
            anchorFrame:EnableMouse(false)
            anchorFrame.bg:Hide()
            anchorFrame.label:Hide()
        else
            anchorFrame:EnableMouse(true)
            anchorFrame.bg:Show()
            anchorFrame.label:Show()
        end
    end
end

-- ------------------------------------------------------------
-- 框架拾取器 — 由 ExwindCore/Core/ExwindFramePicker.lua 提供
-- ------------------------------------------------------------
StartFramePicker = function()
    EnsureAnchorController():StartFramePicker()
end


local function InitCastBarStructure(bar)
    bar:SetClampedToScreen(true)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bar.bg = bg
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    -- 文字层单独抬高，确保始终压在边框之上
    bar.Text = bar.TextFrame:CreateFontString(nil, "OVERLAY")
    bar.TargetNameText = bar.TextFrame:CreateFontString(nil, "OVERLAY")
    bar.TimerText = bar.TextFrame:CreateFontString(nil, "OVERLAY")
    bar.Cooldown = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    bar.Icon = bar:CreateTexture(nil, "OVERLAY")
    bar.PlayerTargetIndicatorFrame = CreateFrame("Frame", nil, bar)
    bar.PlayerTargetIndicatorFrame:SetAllPoints(bar)
    bar.PlayerTargetIndicator = bar.PlayerTargetIndicatorFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    bar.PlayerTargetIndicator:SetAtlas(EXWIND_PLAYER_TARGET_ATLAS)
    bar.PlayerTargetIndicator:SetAlpha(0)

    -- 团队标记图标 (Raid Icon)
    local ri = bar:CreateTexture(nil, "OVERLAY")
    ri:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    ri:Hide()
    bar.RaidIcon = ri
end

if ExwindFactory then
    ExwindFactory:InitPool("ExBossMythicCastBar", "StatusBar", "BackdropTemplate", InitCastBarStructure)
end

local function AcquireBar()
    if not ExwindFactory then return end
    local bar = ExwindFactory:Acquire("ExBossMythicCastBar", anchorFrame)
    -- 关键：由于框架池复用机制，必须手动清除预览标记，否则战斗中条会卡在预览状态(如2.5s)
    bar._isPreview = nil
    bar._isNotInt = nil
    bar.unit = nil
    InvalidatePlayerTargetIndicator(bar, true)
    if bar.RaidIcon then bar.RaidIcon:Hide() end
    UpdateBarVisuals(bar)
    return bar
end

local function ReleaseBar(bar)
    if not ExwindFactory or not bar then return end
    bar:SetScript("OnUpdate", nil)
    InvalidatePlayerTargetIndicator(bar, true)
    if bar.Cooldown then
        bar.Cooldown:Clear()
    end
    ExwindFactory:Release("ExBossMythicCastBar", bar)
end

local function ReleaseActiveBarForUnit(unit)
    local bar = activeBars[unit]
    if not bar then
        return false
    end

    activeBars[unit] = nil
    for i, usedBar in ipairs(usedBarsList) do
        if usedBar == bar then
            table.remove(usedBarsList, i)
            break
        end
    end
    ReleaseBar(bar)
    ReLayout()
    return true
end

local function ScheduleCastUpdate(unit)
    if not C_Timer or pendingCastUpdates[unit] then return end
    local generation = castUpdateGeneration
    pendingCastUpdates[unit] = true
    C_Timer.After(0.1, function()
        if generation ~= castUpdateGeneration then return end
        pendingCastUpdates[unit] = nil
        if not EX_DB.enabled or isPreviewing or IsDisabledInBossEncounter() or not UnitExists(unit) then return end
        if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
            return
        end
        UpdateCast(unit)
    end)
end

UpdateCast = function(unit)
    if isPreviewing then return end
    if IsDisabledInBossEncounter() then
        ReleaseActiveBarForUnit(unit)
        return
    end

    local unitLevel = UnitLevel(unit)
    if (EX_DB.hideLevel91Casts and unitLevel == 91) or (EX_DB.hideLevel92Casts and unitLevel == 92) then
        ReleaseActiveBarForUnit(unit)
        return
    end


    -- 统一在施法开始后延迟 0.1 秒进入这里，战斗状态和目标信息应已同步完成。
    if not UnitAffectingCombat(unit) and unit ~= "player" then
        ReleaseActiveBarForUnit(unit)
        return
    end

    local objCast = UnitCastingDuration(unit)
    local objChannel = UnitChannelDuration(unit)
    local activeObj = objCast or objChannel
    local isChanneling = (objChannel ~= nil)

    if not activeObj then
        ReleaseActiveBarForUnit(unit)
        return
    end

    local bar = activeBars[unit]
    if not bar then
        bar = AcquireBar()
        activeBars[unit] = bar
        table.insert(usedBarsList, bar)
        ReLayout()
    end
    bar.unit = unit
    InvalidatePlayerTargetIndicator(bar, false)

    local name, texture, notInterruptible;
    if isChanneling then
        name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
    else
        name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    end

    if not name then return end

    local finalTargetName = UnitSpellTargetName and UnitSpellTargetName(unit)
    local targetClass = UnitSpellTargetClass and UnitSpellTargetClass(unit)

    if EX_DB.mergeTargetIntoSpellName then
        bar.Text:SetText(BuildMergedSpellText(name, finalTargetName, targetClass))
    else
        bar.Text:SetText(name)
    end

    if bar.TargetNameText then
        if EX_DB.mergeTargetIntoSpellName or not EX_DB.showTarget then
            bar.TargetNameText:SetText("")
            bar.TargetNameText:Hide()
        else
            local shouldShow = false
            if UnitShouldDisplaySpellTargetName then
                shouldShow = UnitShouldDisplaySpellTargetName(unit)
            else
                shouldShow = finalTargetName ~= nil
            end

            bar.TargetNameText:SetText(finalTargetName)

            local color = nil
            local targetClassIsSecret = issecretvalue and issecretvalue(targetClass)
            if targetClassIsSecret or targetClass then
                color = C_ClassColor.GetClassColor(targetClass)
            end
            if color then
                bar.TargetNameText:SetTextColor(color.r, color.g, color.b, 1)
            else
                local font = EX_DB.font_target or {}
                bar.TargetNameText:SetTextColor(font.r or 1, font.g or 1, font.b or 1, font.a or 1)
            end
            bar.TargetNameText:SetShown(shouldShow)
        end
    end
    bar.Icon:SetTexture(texture)
    UpdatePlayerTargetIndicator(bar, unit)

    -- 12.0 适配：显示团队标记 (Raid Icon)
    -- GetRaidTargetIndex 在 12.0 返回的是 Secret Number
    local raidIndex = GetRaidTargetIndex(unit)
    if raidIndex and bar.RaidIcon and EX_DB.showRaidIcon then
        bar.RaidIcon:Show()
        -- 利用 12.0 专用 API 安全地根据秘机索引设置精灵图单元格 (4x4 布局)
        bar.RaidIcon:SetSpriteSheetCell(raidIndex, 4, 4)
    else
        if bar.RaidIcon then bar.RaidIcon:Hide() end
    end

    if notInterruptible == nil then notInterruptible = false end

    local sbTex = bar:GetStatusBarTexture()
    if sbTex then
        -- 为 12.0 Secret Boolean 适配：严禁在 Lua 中对 notInterruptible 进行布尔测试
        local nrR, nrG, nrB, nrA = GetColor("nonInterruptColor")
        local intColor = CreateColor(nrR, nrG, nrB, nrA)

        local group = EX_DB.timerGroup
        local normColor = CreateColor(
            group.barColorR or 1,
            group.barColorG or 0.7,
            group.barColorB or 0,
            group.barColorA or 1
        )

        -- 使用 12.0 安全 API，其内部处理 Secret Boolean 逻辑
        sbTex:SetVertexColorFromBoolean(notInterruptible, intColor, normColor)
        -- 图标模式：同步给图标上色（照抄 sbTex 的方式）
        if EX_DB.displayMode == "icon" and bar.Icon and bar.Icon.SetVertexColorFromBoolean then
            bar.Icon:SetVertexColorFromBoolean(notInterruptible, intColor, normColor)
        end
    end

    if bar.SetTimerDuration then
        bar:SetTimerDuration(activeObj, Enum.StatusBarInterpolation.None, (isChanneling and 1 or 0))
    end
    if bar.Cooldown then
        bar.Cooldown:SetHideCountdownNumbers(not EX_DB.showTimer or bar._isPreview)
        if bar.Cooldown.SetCooldownFromDurationObject then
            bar.Cooldown:SetCooldownFromDurationObject(activeObj, true)
        end
    end

    if bar.TimerText and not bar._isPreview then
        bar.TimerText:SetText("")
    end
    if bar.Cooldown and (not EX_DB.showTimer or bar._isPreview) then
        bar.Cooldown:SetHideCountdownNumbers(true)
        bar.Cooldown:Clear()
    end
    -- 图标模式：启动 OnUpdate 实时更新剩余秒数
    if EX_DB.displayMode == "icon" and bar.TimerText then
        local function ReadEndTime(u)
            local _, _, _, _, endTimeMS = UnitCastingInfo(u)
            if endTimeMS then return endTimeMS / 1000 end
            _, _, _, _, endTimeMS = UnitChannelInfo(u)
            if endTimeMS then return endTimeMS / 1000 end
            return nil
        end
        bar:SetScript("OnUpdate", function(self)
            if not self.unit then
                self:SetScript("OnUpdate", nil); return
            end
            local endTime = ReadEndTime(self.unit)
            if not endTime then
                self:SetScript("OnUpdate", nil); return
            end
            local remaining = endTime - GetTime()
            if remaining < 0 then remaining = 0 end
            if remaining >= 10 then
                self.TimerText:SetText(string.format("%.0fs", remaining))
            else
                self.TimerText:SetText(string.format("%.1fs", remaining))
            end
        end)
    else
        bar:SetScript("OnUpdate", nil)
    end

    if bar.TargetNameText and not (EX_DB.showTarget or EX_DB.mergeTargetIntoSpellName) then
        bar.TargetNameText:Hide()
    end
end

CreateAnchor = function()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame.bg = anchorFrame:CreateTexture(nil, "BACKGROUND")
    -- [Fix] 移除 SetAllPoints，改由 ReLayout 动态控制背景伸展方向
    anchorFrame.bg:SetColorTexture(0, 1, 0, 0.5)
    anchorFrame.label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorFrame.label:SetPoint("CENTER")
    anchorFrame.label:SetText(L["大米怪物施法"])

    editHandleFrame = CreateFrame("Frame", nil, anchorFrame)
    editHandleFrame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    editHandleFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    editHandleFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
    editHandleFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    RefreshAll()
end

function TogglePreview(enable)
    isPreviewing = enable
    if enable then
        -- [v3.1 Fix] 预览模式自动启用拖动
        if anchorFrame then
            anchorFrame:EnableMouse(true)
            anchorFrame.bg:Show()
            anchorFrame.label:Show()
        end
        RefreshEditOverlay()

        for _, bar in pairs(activeBars) do bar:Hide() end
        -- 始终清理并从池中归还旧预览条，确保数量和设置对齐
        for i = #previewBars, 1, -1 do
            local bar = previewBars[i]
            bar:Hide()
            ReleaseBar(bar)
            table.remove(previewBars, i)
        end

        local nrR, nrG, nrB, nrA = GetColor("nonInterruptColor")
        local intColor = CreateColor(nrR, nrG, nrB, nrA)
        local group = EX_DB.timerGroup
        local normColor = CreateColor(
            group.barColorR or 1,
            group.barColorG or 0.7,
            group.barColorB or 0,
            group.barColorA or 1
        )

        -- 根据当前“最大显示数量”生成预览
        local maxLimit = EX_DB.maxBars or 5
        for i = 1, maxLimit do
            local bar = AcquireBar()
            bar._isPreview = true
            -- [v4.3.17] 模拟标记在 1-8 之间循环显示
            bar._previewRaidIndex = (i - 1) % 8 + 1
            bar._isNotInt = (i % 2 == 1) -- 奇数行显示“不可打断”样式演示
            local previewSpellName = L["测试施法 "] .. i
            local previewTargetName = UnitName("player") or L["玩家"]
            local _, previewClass = UnitClass("player")
            if EX_DB.mergeTargetIntoSpellName then
                bar.Text:SetText(BuildMergedSpellText(previewSpellName, previewTargetName, previewClass))
            else
                bar.Text:SetText(previewSpellName)
            end
            bar.Icon:SetTexture(136197) -- 演示图标
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.5)

            -- [Fix] 在设置预览标记后立即刷新视觉，确保模拟团队标记可见
            UpdateBarVisuals(bar)

            -- 安全应用 12.0 预览颜色
            local sbTex = bar:GetStatusBarTexture()
            if sbTex then
                sbTex:SetVertexColorFromBoolean(bar._isNotInt, intColor, normColor)
            end

            -- 演示目标和时间
            if bar.TargetNameText then
                if EX_DB.mergeTargetIntoSpellName then
                    bar.TargetNameText:SetText("")
                    bar.TargetNameText:Hide()
                else
                    bar.TargetNameText:SetText(UnitName("player"))
                    bar.TargetNameText:Show()
                end
            end
            UpdatePlayerTargetIndicator(bar)
            if bar.TimerText then
                bar.TimerText:SetText(L["2.5s"])
                bar.TimerText:Show()
            end

            table.insert(previewBars, bar)
        end
    else
        -- 退出预览，清空模拟数据
        for i = #previewBars, 1, -1 do
            local bar = previewBars[i]
            bar:Hide()
            ReleaseBar(bar)
            table.remove(previewBars, i)
        end
        for _, bar in pairs(activeBars) do UpdateCast(bar.unit) end

        -- [v3.1 Fix] 退出预览时恢复锁定状态
        if anchorFrame then
            if EX_DB.locked then
                anchorFrame:EnableMouse(false)
                anchorFrame.bg:Hide()
                anchorFrame.label:Hide()
            else
                anchorFrame:EnableMouse(true)
                anchorFrame.bg:Show()
                anchorFrame.label:Show()
            end
        end
        RefreshEditOverlay()
    end
    ReLayout()
end

-- =============================================================
-- 事件处理与状态管理
-- =============================================================

local function OnEvent(event, unit)
    -- [Fix] 严格过滤：仅监控敌对单位血条(nameplate)，排除玩家以及友方/队友单位
    if not EX_DB.enabled or IsDisabledInBossEncounter() or not unit then return end
    if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        ScheduleCastUpdate(unit)
        return
    end
    UpdateCast(unit)
end

local function OnUnitRemoved(event, unit)
    pendingCastUpdates[unit] = nil
    ReleaseActiveBarForUnit(unit)
end

local areEventsEnabled = false

local function EnableEnvEvents()
    if areEventsEnabled then return end
    areEventsEnabled = true

    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY, OnEvent)
    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY, OnUnitRemoved)

    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, e in ipairs(events) do
        ExwindTools:RegisterEvent(e, EXWIND_MODULE_KEY, OnEvent)
    end

    if ExwindTools.DebugMode then
        print("|cff00ff00[ExBoss.Tools.MythicCast]|r " .. L["进入5人副本，施法监控已启用。"])
    end
end

local function DisableEnvEvents()
    if not areEventsEnabled then return end
    areEventsEnabled = false

    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY)

    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, e in ipairs(events) do
        ExwindTools:UnregisterEvent(e, EXWIND_MODULE_KEY)
    end

    -- 彻底清理
    for unit, bar in pairs(activeBars) do
        ReleaseBar(bar)
    end
    activeBars = {}
    usedBarsList = {}
    castUpdateGeneration = castUpdateGeneration + 1
    pendingCastUpdates = {}
    ReLayout()
end

local function CheckEnvStatus()
    -- 核心优化: 仅在 5人副本 (party) 且模块开启时注册事件
    -- 注: State.InstanceType 由 ExwindState 维护
    local isParty = (ExwindTools.State.InstanceType == "party")
    local disabledInEncounter = IsDisabledInBossEncounter()

    if isParty and EX_DB.enabled and not disabledInEncounter then
        EnableEnvEvents()
    else
        DisableEnvEvents()
    end
end

-- 监听 InstanceType 变化 (进入/离开副本)
ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY, function(newType)
    CheckEnvStatus()
end)

ExwindTools:WatchState("IsBossEncounter", EXWIND_MODULE_KEY, function()
    CheckEnvStatus()
end)

ExwindTools:WatchState("EncounterID", EXWIND_MODULE_KEY, function()
    CheckEnvStatus()
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".DatabaseChanged", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    if isEditModeActive and (info.key == "preview" or info.key == "locked") then
        return
    end
    if info.key == "preview" then
        TogglePreview(EX_DB.preview)
    elseif info.key == "enabled" then
        if EX_DB.enabled then
            CreateAnchor()
            if anchorFrame then
                anchorFrame:Show()
            end
            RefreshAll()
        else
            if anchorFrame then anchorFrame:Hide() end
        end
        CheckEnvStatus() -- 开关变化时也要检查
    else
        if info.key == "disabledBossEncounterIDs" then
            CheckEnvStatus()
        end
        RefreshAll()
    end
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if info.key == "btn_reset_pos" then
        EX_DB.posX, EX_DB.posY = 0, 100
        EX_DB.attachToCustom = false
        EX_DB.customAttachTarget = ""
        EnsureAnchorController():SyncWidgets()
        if anchorFrame then
            EnsureAnchorController():ApplyPosition()
        end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        StartFramePicker()
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    -- [v4.3.18 Fix] 解决持久化问题：强制在加载时关闭预览模式
    -- 因为框架会在脚本加载后同步 DB 值，所以必须在进入世界事件中强制将其重置为 false
    EX_DB.preview = false
    EX_DB.locked = true

    C_Timer.After(1, function()
        CreateAnchor(); TogglePreview(false)
        RefreshAll()
        CheckEnvStatus() -- 初始检查
    end)
end)

EnsureAnchorController():RegisterEditModeHandler()

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

-- 重置注册（供 ToolsPage 重置按钮调用）
ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    ---@diagnostic disable-next-line: undefined-field
    local wipe = _G.wipe
    local moduleDB = _G.ExwindToolsDB and _G.ExwindToolsDB.ModuleDB
    if not moduleDB or not moduleDB[EXWIND_MODULE_KEY] then return end
    wipe(moduleDB[EXWIND_MODULE_KEY])
    ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)
    ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".DatabaseChanged", { key = "*" })
end

-- =============================================================
-- GUI 渲染接口（由 GlobalSettingsPage embed 调用）
-- =============================================================
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.MythicCastPage = ExBoss.UI.Panel.MythicCastPage or {}
local GUIPage = ExBoss.UI.Panel.MythicCastPage

local BASE_COLS = 53
local TARGET_CELL = 18

function GUIPage:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    if not GUIPage._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_MythicCastSettingsScroll", contentFrame, "ScrollFrameTemplate")
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
        if not sf:IsShown() then
            return
        end

        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 820
        end
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
