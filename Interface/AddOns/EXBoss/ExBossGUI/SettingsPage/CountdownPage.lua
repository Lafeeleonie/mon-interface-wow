---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CountdownPage.lua
-- 倒计时设置页（ExwindGrid）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.CountdownPage = ExBoss.UI.Panel.CountdownPage or {}
local Page = ExBoss.UI.Panel.CountdownPage

local MODULE_KEY = "ExBoss.Countdown"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local ICON_GROUP_TOP = -1300

local function ApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local DEFAULTS = {
    enabled       = true,
    showIcon      = true,
    iconSize      = 24,
    countdownIcon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 24,
        height = 24,
        x = 0,
        y = 0,
        showBorder = true,
        borderTexture = "Square Full White",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 1,
        borderPadding = 0,
    },
    showDecimal   = true,
    stackMax_1205 = 2,
    stackGap      = 4,
    labelTemplate = " %s %t",
    preSecs       = 5,
    anchorX_1205  = 0,
    anchorY_1205  = 40,
    attachToCustom = false,
    customAttachTarget = "",
    font_label = {
        font="默认", size=22, outline="OUTLINE",
        r=1, g=1, b=1, a=1,
        shadow=true, shadowX=2, shadowY=-2, x=0, y=0,
    },
    font_cd = {
        font="默认", size=22, outline="OUTLINE",
        r=1, g=1, b=1, a=1,
        shadow=true, shadowX=2, shadowY=-2, x=0, y=0,
    },
}

-- =============================================================
-- 工具函数
-- =============================================================
local function SafeNum(v, def) return tonumber(v) or def end

local function EnsureCountdownIconDB(db)
    db = type(db) == "table" and db or DEFAULTS
    if type(db.countdownIcon) ~= "table" then
        db.countdownIcon = {}
    end
    local iconDB = db.countdownIcon
    local fallback = DEFAULTS.countdownIcon
    local legacySize = SafeNum(db.iconSize, fallback.width)
    if iconDB.showIcon == nil then iconDB.showIcon = (db.showIcon ~= false) end
    if iconDB.iconID == nil then iconDB.iconID = fallback.iconID end
    if iconDB.reverse == nil then iconDB.reverse = fallback.reverse end
    if tonumber(iconDB.width) == nil then iconDB.width = legacySize end
    if tonumber(iconDB.height) == nil then iconDB.height = legacySize end
    if tonumber(iconDB.x) == nil then iconDB.x = fallback.x end
    if tonumber(iconDB.y) == nil then iconDB.y = fallback.y end
    if iconDB.showBorder == nil then iconDB.showBorder = fallback.showBorder end
    if iconDB.borderTexture == nil then iconDB.borderTexture = fallback.borderTexture end
    if tonumber(iconDB.borderColorR) == nil then iconDB.borderColorR = fallback.borderColorR end
    if tonumber(iconDB.borderColorG) == nil then iconDB.borderColorG = fallback.borderColorG end
    if tonumber(iconDB.borderColorB) == nil then iconDB.borderColorB = fallback.borderColorB end
    if tonumber(iconDB.borderColorA) == nil then iconDB.borderColorA = fallback.borderColorA end
    if tonumber(iconDB.borderSize) == nil then iconDB.borderSize = fallback.borderSize end
    if tonumber(iconDB.borderPadding) == nil then iconDB.borderPadding = fallback.borderPadding end
    return iconDB
end

local function SyncVisualDB()
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb   = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.countdown
    if gridDB then
        ApplyDefaults(gridDB, DEFAULTS)
        EnsureCountdownIconDB(gridDB)
    end
    if exdb then
        ApplyDefaults(exdb, DEFAULTS)
        EnsureCountdownIconDB(exdb)
    end
    if gridDB and exdb then
        for k, v in pairs(gridDB) do exdb[k] = v end
    end
    if ExBoss.UI.Countdown and ExBoss.UI.Countdown.RefreshVisuals then
        ExBoss.UI.Countdown:RefreshVisuals()
    end
end

local function ToHex(r, g, b)
    local function c(v) return string.format("%02x", math.floor((tonumber(v) or 1) * 255 + 0.5)) end
    return "ff" .. c(r) .. c(g) .. c(b)
end

-- =============================================================
-- 生成面板内预览文字（读取当前 DB 颜色）
-- =============================================================
local function BuildPreviewText(db)
    db = db or DEFAULTS
    local iconDB = EnsureCountdownIconDB(db)
    local tmpl     = (type(db.labelTemplate)=="string" and db.labelTemplate~="") and db.labelTemplate or DEFAULTS.labelTemplate
    local fl       = db.font_label or DEFAULTS.font_label
    local fc       = db.font_cd    or DEFAULTS.font_cd
    local labelHex = ToHex(fl.r, fl.g, fl.b)
    local cdHex    = ToHex(fc.r, fc.g, fc.b)
    local showDec  = db.showDecimal

    -- 把模板按 %t 拆成 prefix + suffix
    -- 先替换 %s
    local s = tmpl:gsub("%%s", "|c" .. labelHex .. L["坦克尖刺"] .. "|r")
    local pre, suf = s:match("^(.-)%%t(.*)$")
    local numStr = showDec and "3.0" or "3"
    local colored
    if pre then
        colored = "|c" .. labelHex .. pre .. "|r"
                .. "|c" .. cdHex   .. numStr .. "|r"
                .. "|c" .. labelHex .. suf .. "|r"
    else
        colored = "|c" .. labelHex .. s .. "|r"
    end

    local previewIconSize = math.floor(math.max(12, SafeNum(iconDB.height, SafeNum(iconDB.width, 24))))
    local iconLine = iconDB.showIcon ~= false
                     and "|TInterface\\Icons\\Ability_Warrior_ShieldBlock:" .. tostring(previewIconSize) .. "|t  "
                     or ""

    return string.format(L["|cffaaaaff预览：|r\n%s"], iconLine .. colored)
end

-- =============================================================
-- 模块级 LAYOUT 表（Render 时直接引用）
-- =============================================================
local LAYOUT = {}

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

local function BuildBaseRows(previewText)
    return {
        { key="header", type="header", x=1, y=1, w=63, h=2,
          label=L["倒计时设置"], labelSize=22 },
        { key="desc", type="description", x=1, y=4, w=63, h=2,
          label=L["技能预警时在屏幕中央显示5秒倒数文字。\n|cff00ff00%s|r = 技能名称  |cffffd100%t|r = 倒计时数字"] },
        { key="div_func",    type="divider",  x=1, y=7,  w=63, h=1, label=L["功能"] },
        { key="enabled",     type="checkbox", x=1,  y=8,  w=10, h=2, label=L["启用"] },
        { key="showDecimal", type="checkbox", x=15, y=8,  w=13, h=2, label=L["显示小数点"] },
        { key="stackMax_1205", type="slider", x=30, y=8, w=14, h=2,
          label=L["最大条数"], min=1, max=10, step=1 },
        { key="stackGap",    type="slider",   x=46, y=8, w=17, h=2,
          label=L["上下间距"], min=0, max=20, step=1 },
        { key="attachToCustom", type="checkbox", x=1, y=12, w=10, h=2, label=L["自由依附"] },
        { key="customAttachTarget", type="input", x=13, y=12, w=28, h=2, label=L["目标路径"] },
        { key="btn_pick_frame", type="button", x=43, y=12, w=18, h=2, label=L["鼠标选取"] },
        { key="div_tmpl",      type="divider", x=1, y=15, w=63, h=1, label=L["提示文字模板"] },
        { key="labelTemplate", type="input",   x=1, y=16, w=60, h=2,
          label=L["模板（|cff00ff00%s|r=技能名  |cffffd100%t|r=倒计时数字）"] },
        { key="previewLabel", type="description", x=1, y=19, w=63, h=3,
          label=previewText, labelSize=20 },
        { key="hdr_label",  type="header",    x=1, y=23, w=63, h=2,
          label=L["提示文字字体（%s）"], labelSize=20 },
        { key="font_label", type="fontgroup", x=1, y=26, w=63, h=17,
          label=L["提示文字"], labelSize=18 },
        { key="hdr_cd",  type="header",    x=1, y=44, w=63, h=2,
          label=L["倒计时数字字体（%t）"], labelSize=20 },
        { key="font_cd", type="fontgroup", x=1, y=47, w=63, h=17,
          label=L["倒计时数字"], labelSize=18 },
        { key="div_pos",     type="divider", x=1,  y=65, w=63, h=1, label=L["位置"] },
        { key="anchorX_1205", type="slider", x=1,  y=66, w=23, h=2,
          label=L["水平位置 (X)"], min=-1000, max=1000, step=5 },
        { key="anchorY_1205", type="slider", x=26, y=66, w=23, h=2,
          label=L["垂直位置 (Y)"], min=-600,  max=600,  step=5 },
        { key="btn_reset_pos", type="button", x=51, y=66, w=11, h=2,
          label=L["重置位置"] },
        { key="div_preview", type="divider", x=1,  y=69, w=63, h=1, label=L["场景预览"] },
        { key="btn_preview", type="button",  x=1,  y=70, w=18, h=2, label=L["切换编辑模式预览"] },
        { key="btn_test",    type="button",  x=21, y=70, w=18, h=2, label=L["测试倒计时"] },
    }
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then
        return items
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
    return ScaleItems(items)
end

local function RegisterLayout()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local rows = BuildBaseRows(BuildPreviewText(db))
    for i = #LAYOUT, 1, -1 do LAYOUT[i] = nil end
    for _, row in ipairs(rows) do LAYOUT[#LAYOUT + 1] = row end
    ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)
end

-- 立即注册
RegisterLayout()

-- =============================================================
-- WatchState：DB 变化 → 同步 ExBossDB + 刷新显示 + 刷新预览
-- =============================================================
ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
    SyncVisualDB()
    RegisterLayout()

    -- 嵌入页模式下避免调用 ExwindTools.UI:RefreshContent()，否则会和 ExBoss 面板刷新流冲突导致空白。
    local Grid = _G.ExwindGrid
    if Grid and type(Grid.Widgets) == "table" and ExwindTools.UI and ExwindTools.UI.CurrentModule == MODULE_KEY then
        local preview = Grid.Widgets["previewLabel"]
        if preview and preview.text and preview.text.SetText then
            preview.text:SetText(BuildPreviewText(gridDB))
        end
    end
end)

-- =============================================================
-- WatchState：按钮
-- =============================================================
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    if info.key == "btn_reset_pos" then
        local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
        if gridDB then gridDB.anchorX_1205 = 0; gridDB.anchorY_1205 = 40; gridDB.stackMax_1205 = 2 end
        local exdb = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.countdown
        if exdb then exdb.anchorX_1205 = 0; exdb.anchorY_1205 = 40; exdb.stackMax_1205 = 2 end
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.RefreshVisuals then
            ExBoss.UI.Countdown:RefreshVisuals()
        end
    elseif info.key == "btn_preview" then
        if ExwindTools.ToggleGlobalEditMode then ExwindTools:ToggleGlobalEditMode() end
    elseif info.key == "btn_test" then
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.Show then
            ExBoss.UI.Countdown:Show({ displayName = L["坦克尖刺"], spellID = 46968 })
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.StartFramePicker then
            ExBoss.UI.Countdown:StartFramePicker()
        end
    end
end)

-- =============================================================
-- Render
-- =============================================================
function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
--         print("|cffff4400ExBoss|r CountdownPage: ExwindGrid 不可用")
        return
    end

    -- 把 ExBossDB 的值同步到 ExwindTools 的 moduleDB（初次打开）
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb   = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.countdown
    if gridDB then
        ApplyDefaults(gridDB, DEFAULTS)
        EnsureCountdownIconDB(gridDB)
    end
    if exdb then
        ApplyDefaults(exdb, DEFAULTS)
        EnsureCountdownIconDB(exdb)
    end
    if exdb and gridDB then
        for k, v in pairs(exdb) do
            if gridDB[k] == nil then gridDB[k] = v end
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_CountdownSettingsScroll",
            contentFrame, "ScrollFrameTemplate")
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
    sf:SetPoint("TOPLEFT",     contentFrame, "TOPLEFT",     4,  -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if not sf:IsShown() then return end
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end
        sc:SetWidth(w - 16)
        sc:SetHeight(1620)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = sc
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        local currentDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
        local cols = ResolveGridCols(sc:GetWidth())
        local renderLayout = BuildBaseRows(BuildPreviewText(currentDB))
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end
        Grid:Render(sc, ScaleLayout(renderLayout, cols), currentDB, MODULE_KEY)

        if ExBoss.UI and ExBoss.UI.CreateIconGroupV2 then
            if Page._iconGroup then
                Page._iconGroup:Hide()
            end
            Page._iconGroup = ExBoss.UI.CreateIconGroupV2(
                sc,
                math.max(720, sc:GetWidth() - 24),
                L["图标设置"],
                currentDB,
                "countdownIcon",
                SyncVisualDB
            )
            Page._iconGroup:SetPoint("TOPLEFT", 10, ICON_GROUP_TOP)
            Page._iconGroup:Show()
        end
    end)
end
