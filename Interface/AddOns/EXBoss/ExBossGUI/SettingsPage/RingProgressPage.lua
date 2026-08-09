---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/RingProgressPage.lua
-- 圆环进度设置页（ExwindGrid）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = ExBoss and ExBoss.GetLocale and ExBoss:GetLocale() or {}

ExBoss.UI.Panel.RingProgressPage = ExBoss.UI.Panel.RingProgressPage or {}
local Page = ExBoss.UI.Panel.RingProgressPage

local MODULE_KEY = "ExBoss.RingProgress"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

local DEFAULTS = {
    enabled = true,
    showName = false,
    showTimer = true,
    style = "thin1",
    size = 170,
    alpha = 0.95,
    castFillMode = "cw_fill",
    channelFillMode = "ccw_decay",
    ringColorR = 0.1,
    ringColorG = 0.8,
    ringColorB = 1.0,
    ringColorA = 1.0,
    bgEnabled = false,
    bgAlpha = 0.3,
    bgColorR = 0.3,
    bgColorG = 0.3,
    bgColorB = 0.3,
    bgColorA = 1.0,
    anchorX = 0,
    anchorY = 0,
    attachToCustom = false,
    customAttachTarget = "",
    font_name = {
        font = "默认",
        size = 16,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 0, y = 30,
    },
    font_time = {
        font = "默认",
        size = 20,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 0, y = 0,
    },
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["圆环进度设置"] or "圆环进度设置", labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 1, label = L["屏幕中央显示圆环进度"] or "屏幕中央显示圆环进度", labelSize = 18 },
    { key = "div_func", type = "divider", x = 1, y = 6, w = 63, h = 1, label = L["功能"] or "功能" },
    { key = "enabled", type = "checkbox", x = 1, y = 7, w = 10, h = 2, label = L["启用"] or "启用" },
    { key = "showName", type = "checkbox", x = 12, y = 7, w = 10, h = 2, label = L["显示名称"] or "显示名称" },
    { key = "showTimer", type = "checkbox", x = 24, y = 7, w = 10, h = 2, label = L["显示时间"] or "显示时间" },
    { key = "attachToCustom", type = "checkbox", x = 1, y = 11, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 12, y = 11, w = 20, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 33, y = 11, w = 14, h = 2, label = L["鼠标选取"] },
    { key = "castFillMode", type = "dropdown", x = 2, y = 15, w = 14, h = 2, label = L["施法填充方式"] or "施法填充方式", items = {
        { L["顺时针填满"] or "顺时针填满", "cw_fill" },
        { L["顺时针消退"] or "顺时针消退", "cw_decay" },
        { L["逆时针填满"] or "逆时针填满", "ccw_fill" },
        { L["逆时针消退"] or "逆时针消退", "ccw_decay" },
    }, labelPos = "top" },
    { key = "channelFillMode", type = "dropdown", x = 17, y = 15, w = 14, h = 2, label = L["引导填充方式"] or "引导填充方式", items = {
        { L["顺时针填满"] or "顺时针填满", "cw_fill" },
        { L["顺时针消退"] or "顺时针消退", "cw_decay" },
        { L["逆时针填满"] or "逆时针填满", "ccw_fill" },
        { L["逆时针消退"] or "逆时针消退", "ccw_decay" },
    }, labelPos = "top" },
    { key = "style", type = "dropdown", x = 33, y = 15, w = 14, h = 2, label = L["圆环样式"] or "圆环样式", items = {
        { L["细环 1"] or "细环 1", "thin1" },
        { L["细环 2"] or "细环 2", "thin2" },
        { L["标准环"] or "标准环", "classic" },
    }, labelPos = "top" },
    { key = "size", type = "slider", x = 2, y = 19, w = 14, h = 2, label = L["圆环尺寸"] or "圆环尺寸", min = 20, max = 360, step = 2 },
    { key = "ringColor", type = "color", x = 17, y = 19, w = 14, h = 2, label = L["颜色"] or "颜色" },
    { key = "alpha", type = "slider", x = 33, y = 19, w = 14, h = 2, label = L["透明度"] or "透明度", min = 0.1, max = 1, step = 0.05 },
    { key = "btn_preview", type = "button", x = 48, y = 19, w = 13, h = 2, label = L["进入编辑模式"] or "进入编辑模式" },
    { key = "anchorX", type = "slider", x = 17, y = 23, w = 14, h = 2, label = L["水平位置 (X)"] or "水平位置 (X)", min = -1000, max = 1000, step = 5 },
    { key = "anchorY", type = "slider", x = 33, y = 23, w = 14, h = 2, label = L["垂直位置 (Y)"] or "垂直位置 (Y)", min = -600, max = 600, step = 5 },
    { key = "btn_test_cast", type = "button", x = 2, y = 23, w = 14, h = 2, label = L["测试施法(3秒)"] or "测试施法(3秒)" },
    { key = "btn_test_channel", type = "button", x = 2, y = 26, w = 14, h = 2, label = L["测试引导(3秒)"] or "测试引导(3秒)" },
    { key = "btn_test_cast_check", type = "button", x = 17, y = 26, w = 18, h = 2, label = L["测试施法检测"] or "测试施法检测" },
    { key = "div_bg", type = "divider", x = 1, y = 29, w = 63, h = 1, label = L["背景圆环"] or "背景圆环" },
    { key = "bgEnabled", type = "checkbox", x = 1, y = 30, w = 15, h = 2, label = L["启用背景圆环"] or "启用背景圆环" },
    { key = "bgColor", type = "color", x = 2, y = 33, w = 14, h = 2, label = L["背景颜色"] or "背景颜色" },
    { key = "bgAlpha", type = "slider", x = 17, y = 33, w = 14, h = 2, label = L["背景透明度"] or "背景透明度", min = 0.05, max = 1, step = 0.05 },
    { key = "font_name", type = "fontgroup", x = 1, y = 37, w = 63, h = 14, label = L["法术名称"] or "法术名称", labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 53, w = 63, h = 14, label = L["时间文本"] or "时间文本", labelSize = 20 },
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

local function EnsureExBossDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.ringProgress = ExBossDB.timer.ringProgress or {}
    local db = ExBossDB.timer.ringProgress
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end
    return db
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
    local exdb = EnsureExBossDB()
    if gridDB and exdb then
        for k, v in pairs(gridDB) do
            exdb[k] = v
        end
    end
    if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.RefreshVisuals then
        ExBoss.UI.RingProgress:RefreshVisuals()
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    if info.key == "btn_reset_pos" then
        local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
        if gridDB then
            gridDB.anchorX = 0
            gridDB.anchorY = 0
        end
        local exdb = EnsureExBossDB()
        exdb.anchorX = 0
        exdb.anchorY = 0
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.RefreshVisuals then
            ExBoss.UI.RingProgress:RefreshVisuals()
        end
    elseif info.key == "btn_preview" then
        if ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    elseif info.key == "btn_test_cast" then
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.Preview then
            ExBoss.UI.RingProgress:Preview(3, "cast")
        end
    elseif info.key == "btn_test_channel" then
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.Preview then
            ExBoss.UI.RingProgress:Preview(3, "channel")
        end
    elseif info.key == "btn_test_cast_check" then
        if ExBoss.UI.RingProgress then
            if ExBoss.UI.RingProgress.PreviewCastCheck then
                ExBoss.UI.RingProgress:PreviewCastCheck(3)
            elseif ExBoss.UI.RingProgress.Preview then
                ExBoss.UI.RingProgress:Preview(3, "cast", { castCheckEnabled = true })
            end
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.StartFramePicker then
            ExBoss.UI.RingProgress:StartFramePicker()
        end
    end
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb = EnsureExBossDB()
    if exdb and gridDB then
        for k, v in pairs(exdb) do
            gridDB[k] = v
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_RingProgressSettingsScroll", contentFrame, "ScrollFrameTemplate")
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
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), gridDB, MODULE_KEY)
    end)
end
