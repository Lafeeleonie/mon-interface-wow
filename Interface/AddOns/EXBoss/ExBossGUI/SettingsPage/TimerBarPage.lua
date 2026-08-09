---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/TimerBarPage.lua
-- 计时条设置页（ExwindGrid 渲染）
--
-- 正确接入方式（参考 ExwindToolsUI.lua）：
--   1. RegisterModuleLayout(key, layout) — 注册布局
--   2. GetModuleDB(key, defaults)        — 管理 DB（存入 ExwindToolsDB.ModuleDB）
--   3. Grid 渲染到固定宽度的 ScrollChild
--   4. WatchState(key..".DatabaseChanged") 监听控件变化 → 刷新 HUD
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.TimerBarPage = ExBoss.UI.Panel.TimerBarPage or {}
local Page = ExBoss.UI.Panel.TimerBarPage

local MODULE_KEY = "ExBoss.TimerBar"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

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

-- =============================================================
-- 默认值
-- =============================================================
local DEFAULTS = {
    enabled      = true,
    spacing      = 1,
    maxBars      = 6,
    growDir      = "UP",
    fillMode     = "LTR_FILL",
    showName     = true,
    showTimer    = true,
    hideLongTimersEnabled = false,
    hideLongTimersSeconds = 30,
    anchorX      = -237,
    anchorY      = 245,
    attachToCustom = false,
    customAttachTarget = "",
    font_name = {
        font = "默认",
        size = 15,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 2, y = 0,
    },
    font_time = {
        font = "默认",
        size = 15,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 0, y = 0,
    },
    timerBarGroup = {
        width = 200,
        height = 25,
        texture = "Melli",
        barColorR = 1.0,
        barColorG = 0.7,
        barColorB = 0.0,
        barColorA = 1.0,
        barBgColorR = 0.0,
        barBgColorG = 0.0,
        barBgColorB = 0.0,
        barBgColorA = 0.5,
        showBorder = true,
        borderTexture = "Square Full White",
        borderColorR = 0.0,
        borderColorG = 0.0,
        borderColorB = 0.0,
        borderColorA = 1.0,
        borderSize = 1,
        borderPadding = 0,
        showIcon = true,
        iconSide = "LEFT",
        iconSize = 24,
        iconOffsetX = -1,
        iconOffsetY = 0,
        showIconBorder = true,
        iconBorderTexture = "Square Full White",
        iconBorderColorR = 0.0,
        iconBorderColorG = 0.0,
        iconBorderColorB = 0.0,
        iconBorderColorA = 1.0,
        iconBorderSize = 1,
        iconBorderPadding = 0,
        alertIcons = {
            showIcon = true,
            anchor = "OUTSIDE_LEFT",
            layout = "HORIZONTAL",
            size = 26,
            x = -28,
            y = 0,
        },
    },
}

-- =============================================================
-- Grid 布局定义
-- =============================================================
local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["计时条设置"], labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 1, label = L["计时条所有外观的设置"] },
    { key = "enabled", type = "checkbox", x = 1, y = 9, w = 10, h = 2, label = L["启用"] },
    { key = "attachToCustom", type = "checkbox", x = 1, y = 13, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 12, y = 13, w = 28, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 46, y = 13, w = 14, h = 2, label = L["鼠标选取"] },
    { key = "showName", type = "checkbox", x = 1, y = 17, w = 10, h = 2, label = L["显示名称"] },
    { key = "showTimer", type = "checkbox", x = 16, y = 17, w = 10, h = 2, label = L["显示时间"] },
    { key = "hideLongTimersEnabled", type = "checkbox", x = 31, y = 17, w = 12, h = 2, label = L["隐藏长技能"] },
    { key = "hideLongTimersSeconds", type = "slider", x = 46, y = 17, w = 14, h = 2, label = L["只显示最后几秒"], min = 1, max = 60 },
    { key = "fillMode", type = "dropdown", x = 46, y = 21, w = 14, h = 2, label = L["条增长方式"], items = {
        { L["左到右填充"], "LTR_FILL" },
        { L["左到右消退"], "LTR_FADE" },
        { L["右到左填充"], "RTL_FILL" },
        { L["右到左消退"], "RTL_FADE" },
    } },
    { key = "spacing", type = "slider", x = 1, y = 21, w = 14, h = 2, label = L["间距"], min = 0, max = 20 },
    { key = "maxBars", type = "slider", x = 16, y = 21, w = 14, h = 2, label = L["最大显示数量"], min = 1, max = 20 },
    { key = "growDir", type = "dropdown", x = 31, y = 21, w = 14, h = 2, label = L["增长方向"], items = {
        { L["向下"], "DOWN" },
        { L["向上"], "UP" },
    } },
    { key = "anchorX", type = "slider", x = 1, y = 25, w = 14, h = 2, label = L["水平位置 (X)"], min = -1000, max = 1000 },
    { key = "anchorY", type = "slider", x = 16, y = 25, w = 14, h = 2, label = L["垂直位置 (Y)"], min = -600, max = 600 },
    { key = "btn_reset_pos", type = "button", x = 31, y = 25, w = 14, h = 2, label = L["重置位置"] },
    { key = "alertIconHeader", type = "header", x = 1, y = 29, w = 63, h = 1, label = L["提示图标"], labelSize = 20 },
    { key = "alertIconGroup", type = "TableGroup", x = 1, y = 1, w = 1, h = 1, label = "--[[ Function ]]", parentKey = "timerBarGroup.alertIcons", children = {
        { key = "alertShowIcon", subKey = "showIcon", type = "checkbox", x = 1, y = 32, w = 12, h = 2, label = L["显示提示图标"] },
        { key = "alertAnchor", subKey = "anchor", type = "dropdown", x = 16, y = 32, w = 14, h = 2, label = L["提示图标锚点"], items = {
            { L["外部(左侧)"], "OUTSIDE_LEFT" },
            { L["文字前"], "TEXT_BEFORE" },
            { L["文字后"], "TEXT_AFTER" },
        } },
        { key = "alertLayout", subKey = "layout", type = "dropdown", x = 31, y = 32, w = 14, h = 2, label = L["排列"], items = {
            { L["左右排列"], "HORIZONTAL" },
            { L["上下排列"], "VERTICAL" },
        } },
        { key = "alertSize", subKey = "size", type = "slider", x = 46, y = 32, w = 14, h = 2, label = L["大小"], min = 6, max = 80 },
        { key = "alertX", subKey = "x", type = "slider", x = 1, y = 36, w = 14, h = 2, label = L["X偏移"], min = -100, max = 100 },
        { key = "alertY", subKey = "y", type = "slider", x = 16, y = 36, w = 14, h = 2, label = L["Y偏移"], min = -100, max = 100 },
    } },
    { key = "timerBarGroup", type = "timerBarGroupV2", x = 1, y = 39, w = 62, h = 32, label = L["计时条外观"], labelSize = 20 },
    { key = "font_name", type = "fontgroup", x = 1, y = 73, w = 63, h = 14, label = L["法术名称"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 89, w = 63, h = 14, label = L["时间文本"], labelSize = 20 },
    { key = "subheader_8209", type = "subheader", x = 1, y = 7, w = 63, h = 1, label = L["通用"], labelSize = 20 },
    { key = "divider_5953", type = "divider", x = 1, y = 8, w = 63, h = 1, label = L["新组件"] },
}

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

-- 注册布局（加载时执行一次）
ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

-- =============================================================
-- 监听 Grid 控件事件
-- =============================================================
ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    -- 同步到 ExBossDB（Grid 管理的 DB 存在 ExwindToolsDB，需同步到 ExBossDB）
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
    local exdb   = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.timerBar
    if gridDB and exdb then
        ApplyDefaults(gridDB, DEFAULTS)
        ApplyDefaults(exdb, DEFAULTS)
        for k, v in pairs(gridDB) do
            exdb[k] = v
        end
    end
    -- 刷新 HUD
    if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
        ExBoss.UI.TimerBar:RefreshVisuals()
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    if info.key == "btn_reset_pos" then
        local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
        if gridDB then
            gridDB.anchorX = -237
            gridDB.anchorY = 245
        end
        local exdb = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.timerBar
        if exdb then
            exdb.anchorX = -237
            exdb.anchorY = 245
        end
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
            ExBoss.UI.TimerBar:RefreshVisuals()
        end
    elseif info.key == "btn_preview" then
        if ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    elseif info.key == "btn_create_test" then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.CreateTestBars then
            ExBoss.UI.TimerBar:CreateTestBars(5)
        end
    elseif info.key == "btn_clear_test" then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.ClearTestBars then
            ExBoss.UI.TimerBar:ClearTestBars()
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.StartFramePicker then
            ExBoss.UI.TimerBar:StartFramePicker()
        end
    end
end)

-- =============================================================
-- 渲染接口（由 PanelFrame 调用）
-- contentFrame：面板右侧内容区
-- =============================================================
function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
--         print("|cffff4400ExBoss|r TimerBarPage: ExwindGrid 不可用")
        return
    end

    -- 确保 Grid DB 和 ExBossDB 同步（初次打开时把 ExBossDB 的值写入 Grid DB）
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb   = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.timerBar
    if exdb and gridDB then
        ApplyDefaults(exdb, DEFAULTS)
        ApplyDefaults(gridDB, DEFAULTS)
        for k, v in pairs(exdb) do
            gridDB[k] = v
        end
    end

    -- 首次创建 ScrollFrame + ScrollChild
    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_TimerBarSettingsScroll",
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

    -- 延迟一帧让 contentFrame 宽度就绪后再渲染 Grid
    C_Timer.After(0, function()
        if not sf:IsShown() then return end  -- 如果已切换 Tab 就放弃
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end          -- 兜底（面板宽度 1100 - 左侧240 - 边距）
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
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), gridDB, MODULE_KEY)
    end)
end
