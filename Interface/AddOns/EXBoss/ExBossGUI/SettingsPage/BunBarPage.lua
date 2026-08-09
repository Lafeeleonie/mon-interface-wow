---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/BunBarPage.lua
-- 束状条设置页（ExwindGrid）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.BunBarPage = ExBoss.UI.Panel.BunBarPage or {}
local Page = ExBoss.UI.Panel.BunBarPage

local MODULE_KEY = "ExBoss.BunBar"
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

local DEFAULTS = {
    enabled           = true,
    locked            = false,
    anchorX           = -734,
    anchorY           = 141,
    attachToCustom    = false,
    customAttachTarget = "",
    width             = 420,
    iconSize          = 40,
    trackHeight       = 50,
    preAlertSecs      = 5,
    maxTracks         = 1,
    layoutMode        = "单条",
    axis              = "垂直",
    moveDir           = "向下",
    showIcon          = true,
    showName          = true,
    showTimer         = true,
    hideLongTimersEnabled = false,
    hideLongTimersSeconds = 30,
    font_name         = {
        font = "默认",
        size = 16,
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        side = "RIGHT",
        x = 6,
        y = 0,
    },
    font_time         = {
        font = "默认",
        size = 20,
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        outline = "THICKOUTLINE",
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        x = 2,
        y = -2,
    },
    alertIcons        = {
        showIcon = true,
        anchor = "ICON_LEFT",
        layout = "VERTICAL",
        width = 35,
        height = 35,
        x = 0,
        y = 0,
    },
    axisLineWidth     = 1,
    axisLineColorR    = 0.35686275362968,
    axisLineColorG    = 0.35686275362968,
    axisLineColorB    = 0.35686275362968,
    axisLineColorA    = 0.6758024096489,
    fiveSecLineWidth  = 2,
    fiveSecLineColorR = 1.0,
    fiveSecLineColorG = 0.90,
    fiveSecLineColorB = 0.35,
    fiveSecLineColorA = 0.85,
    showBg            = true,
    showBorder        = true,
    bgSettings        = {
        texture       = "Solid",
        bgColorR      = 0.05098039656877518,
        bgColorG      = 0.05882353335618973,
        bgColorB      = 0.0784313753247261,
        bgColorA      = 0.6949490904808044,
        borderTexture = "Solid",
        borderColorR  = 0.9372549653053284,
        borderColorG  = 1.0,
        borderColorB  = 0.9137255549430847,
        borderColorA  = 1,
        edgeSize      = 1,
        inset         = 2,
    },
    colors            = {
        [1] = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },
        [2] = { r = 1.0, g = 0.8, b = 0.0, a = 1.0 },
        [3] = { r = 0.6, g = 0.6, b = 0.6, a = 0.6 },
    },
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["束状条设置"], labelSize = 25 },
    { key = "enabled", type = "checkbox", x = 1, y = 7, w = 10, h = 2, label = L["启用"] },
    { key = "attachToCustom", type = "checkbox", x = 1, y = 11, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 13, y = 11, w = 28, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 46, y = 11, w = 14, h = 2, label = L["鼠标选取"] },
    { key = "showIcon", type = "checkbox", x = 1, y = 15, w = 10, h = 2, label = L["显示图标"] },
    { key = "showName", type = "checkbox", x = 16, y = 15, w = 10, h = 2, label = L["显示名称"] },
    { key = "showTimer", type = "checkbox", x = 32, y = 15, w = 10, h = 2, label = L["显示时间"] },
    { key = "hideLongTimersEnabled", type = "checkbox", x = 48, y = 15, w = 12, h = 2, label = L["隐藏长技能"] },
    { key = "width", type = "slider", x = 1, y = 19, w = 14, h = 2, label = L["轨道宽度"], min = 200, max = 1400 },
    { key = "iconSize", type = "slider", x = 16, y = 19, w = 14, h = 2, label = L["图标大小"], min = 12, max = 64 },
    { key = "trackHeight", type = "slider", x = 31, y = 19, w = 14, h = 2, label = L["轨道高度"], min = 16, max = 90 },
    { key = "moveDir", type = "dropdown", x = 1, y = 23, w = 14, h = 2, label = L["移动方向"], items = L["向上"] .. "," .. L["向下"] },
    { key = "hideLongTimersSeconds", type = "slider", x = 16, y = 23, w = 14, h = 2, label = L["只显示最后几秒"], min = 1, max = 60 },
    { key = "anchorY", type = "slider", x = 31, y = 23, w = 14, h = 2, label = L["垂直位置 (Y)"], min = -1000, max = 1000 },
    { key = "anchorX", type = "slider", x = 46, y = 23, w = 14, h = 2, label = L["水平位置 (X)"], min = -1500, max = 1500 },
    { key = "showBg", type = "checkbox", x = 1, y = 42, w = 10, h = 2, label = L["显示背景"] },
    { key = "showBorder", type = "checkbox", x = 1, y = 46, w = 10, h = 2, label = L["显示边框"] },
    { key = "font_name", type = "fontgroup", x = 1, y = 53, w = 63, h = 14, label = L["法术名称"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 73, w = 63, h = 14, label = L["图案倒数时间"], labelSize = 20 },
    { key = "axisLineWidth", type = "slider", x = 1, y = 89, w = 14, h = 2, label = L["背景线粗细"], min = 1, max = 8 },
    { key = "axisLineColor", type = "color", x = 16, y = 89, w = 14, h = 2, label = L["背景线颜色"] },
    { key = "fiveSecLineWidth", type = "slider", x = 31, y = 89, w = 14, h = 2, label = L["5秒线粗细"], min = 1, max = 8 },
    { key = "fiveSecLineColor", type = "color", x = 46, y = 89, w = 14, h = 2, label = L["5秒线颜色"] },
    {
        key = "fontNameGroup",
        type = "TableGroup",
        x = 1,
        y = 1,
        w = 1,
        h = 1,
        label = "--[[ Function ]]",
        parentKey = "font_name",
        children = {
            {
                key = "side",
                type = "dropdown",
                x = 1,
                y = 69,
                w = 14,
                h = 2,
                label = L["名称位置"],
                items = {
                    { L["图标左边"], "LEFT" },
                    { L["图标右边"], "RIGHT" },
                }
            },
        }
    },
    {
        key = "bgGroup",
        type = "TableGroup",
        x = 1,
        y = 1,
        w = 1,
        h = 1,
        label = "--[[ Function ]]",
        parentKey = "bgSettings",
        children = {
            { key = "texture", type = "lsm_background", x = 16, y = 42, w = 14, h = 2, label = L["背景材质"], labelPos = "left" },
            { key = "bgColor", type = "color", x = 32, y = 42, w = 14, h = 2, label = L["背景颜色"] },
            { key = "borderTexture", type = "lsm_border", x = 16, y = 46, w = 14, h = 2, label = L["边框材质"], labelPos = "left" },
            { key = "borderColor", type = "color", x = 32, y = 46, w = 14, h = 2, label = L["边框颜色"] },
            { key = "edgeSize", type = "slider", x = 16, y = 50, w = 14, h = 2, label = L["边框粗细"], min = 1, max = 32 },
            { key = "inset", type = "slider", x = 32, y = 50, w = 14, h = 2, label = L["边框内距"], min = 0, max = 16 },
        }
    },
    { key = "header_alert_icons", type = "header", x = 1, y = 27, w = 63, h = 2, label = L["提示图标"], labelSize = 20 },
    {
        key = "alertIconGroup",
        type = "TableGroup",
        x = 1,
        y = 1,
        w = 1,
        h = 1,
        label = "--[[ Function ]]",
        parentKey = "alertIcons",
        children = {
            { key = "alertShowIcon", subKey = "showIcon", type = "checkbox", x = 1, y = 30, w = 12, h = 2, label = L["显示提示图标"] },
            {
                key = "alertAnchor",
                subKey = "anchor",
                type = "dropdown",
                x = 16,
                y = 30,
                w = 14,
                h = 2,
                label = L["提示图标锚点"],
                items = {
                    { L["图标左"], "ICON_LEFT" },
                    { L["图标右"], "ICON_RIGHT" },
                    { L["文字左"], "NAME_LEFT" },
                    { L["文字右"], "NAME_RIGHT" },
                }
            },
            {
                key = "alertLayout",
                subKey = "layout",
                type = "dropdown",
                x = 31,
                y = 30,
                w = 14,
                h = 2,
                label = L["排列"],
                items = {
                    { L["左右排列"], "HORIZONTAL" },
                    { L["上下排列"], "VERTICAL" },
                }
            },
            { key = "alertWidth", subKey = "width", type = "slider", x = 46, y = 30, w = 14, h = 2, label = L["宽度"], min = 6, max = 80 },
            { key = "alertHeight", subKey = "height", type = "slider", x = 1, y = 34, w = 14, h = 2, label = L["高度"], min = 6, max = 80 },
            { key = "alertX", subKey = "x", type = "slider", x = 16, y = 34, w = 14, h = 2, label = L["X偏移"], min = -100, max = 100 },
            { key = "alertY", subKey = "y", type = "slider", x = 31, y = 34, w = 14, h = 2, label = L["Y偏移"], min = -100, max = 100 },
        }
    },
    { key = "header_7996", type = "header", x = 1, y = 39, w = 63, h = 2, label = L["背景设置"], labelSize = 20 },
    { key = "header_5885", type = "header", x = 1, y = 5, w = 63, h = 1, label = L["通用设置"], labelSize = 20 },
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

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
    local exdb = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.bunBar
    if gridDB and exdb then
        ApplyDefaults(gridDB, DEFAULTS)
        ApplyDefaults(exdb, DEFAULTS)
        for k, v in pairs(gridDB) do
            exdb[k] = v
        end
    end
    if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
        ExBoss.UI.BunBar:RefreshVisuals()
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end

    if info.key == "btn_reset_pos" then
        local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
        if gridDB then
            gridDB.anchorX = -734
            gridDB.anchorY = 141
        end
        local exdb = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.bunBar
        if exdb then
            exdb.anchorX = -734
            exdb.anchorY = 141
        end
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
            ExBoss.UI.BunBar:RefreshVisuals()
        end
    elseif info.key == "btn_preview" then
        if ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    elseif info.key == "btn_create_test" then
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.CreateTestBars then
            ExBoss.UI.BunBar:CreateTestBars(5)
        end
    elseif info.key == "btn_clear_test" then
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.ClearTestBars then
            ExBoss.UI.BunBar:ClearTestBars()
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.StartFramePicker then
            ExBoss.UI.BunBar:StartFramePicker()
        end
    end
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        --         print("|cffff4400ExBoss|r BunBarPage: ExwindGrid 不可用")
        return
    end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb = _G.ExBossDB and _G.ExBossDB.timer and _G.ExBossDB.timer.bunBar
    if gridDB then
        ApplyDefaults(gridDB, DEFAULTS)
    end
    if exdb and gridDB then
        ApplyDefaults(exdb, DEFAULTS)
        for k, v in pairs(exdb) do
            gridDB[k] = v
        end
        ApplyDefaults(gridDB, DEFAULTS)
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_BunBarSettingsScroll",
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
