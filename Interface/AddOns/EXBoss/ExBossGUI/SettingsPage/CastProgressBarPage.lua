---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CastProgressBarPage.lua
-- 施法进度条设置页
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.CastProgressBarPage = ExBoss.UI.Panel.CastProgressBarPage or {}
local Page = ExBoss.UI.Panel.CastProgressBarPage

local MODULE_KEY = "ExBoss.CastProgressBar"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

local DEFAULTS = {
    enabled = true,
    showName = true,
    showTimer = true,
    spacing = 1,
    maxBars = 3,
    growDir = "UP",
    castFillMode = "ltr_fill",
    channelFillModeV2 = "ltr_decay",
    anchorX = 0,
    anchorY = -170,
    attachToCustom = false,
    customAttachTarget = "",
    font_name = {
        font = "默认",
        size = 16,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 4, y = 0,
    },
    font_time = {
        font = "默认",
        size = 16,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = -4, y = 0,
    },
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
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["施法进度条设置"], labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 1, label = L["与中央圆环使用相同触发逻辑，额外显示一根施法/引导进度条。"] },
    { key = "subheader_general", type = "subheader", x = 1, y = 7, w = 63, h = 1, label = L["通用"], labelSize = 20 },
    { key = "divider_general", type = "divider", x = 1, y = 8, w = 63, h = 1, label = L["新组件"] },
    { key = "enabled", type = "checkbox", x = 1, y = 9, w = 10, h = 2, label = L["启用"] },
    { key = "showName", type = "checkbox", x = 12, y = 9, w = 10, h = 2, label = L["显示名称"] },
    { key = "showTimer", type = "checkbox", x = 24, y = 9, w = 10, h = 2, label = L["显示时间"] },
    { key = "attachToCustom", type = "checkbox", x = 1, y = 13, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 12, y = 13, w = 28, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 46, y = 13, w = 14, h = 2, label = L["鼠标选取"] },
    { key = "castFillMode", type = "dropdown", x = 1, y = 17, w = 14, h = 2, label = L["施法填充方式"], items = {
        { L["左到右填满"], "ltr_fill" },
        { L["右到左消退"], "rtl_decay" },
        { L["右到左填满"], "rtl_fill" },
        { L["左到右消退"], "ltr_decay" },
    }, labelPos = "top" },
    { key = "channelFillModeV2", type = "dropdown", x = 16, y = 17, w = 14, h = 2, label = L["引导填充方式"], items = {
        { L["左到右填满"], "ltr_fill" },
        { L["右到左消退"], "rtl_decay" },
        { L["右到左填满"], "rtl_fill" },
        { L["左到右消退"], "ltr_decay" },
    }, labelPos = "top" },
    { key = "growDir", type = "dropdown", x = 31, y = 17, w = 14, h = 2, label = L["增长方向"], items = {
        { L["向下"], "DOWN" },
        { L["向上"], "UP" },
    }, labelPos = "top" },
    { key = "anchorX", type = "slider", x = 46, y = 17, w = 14, h = 2, label = L["水平位置 (X)"], min = -1000, max = 1000 },
    { key = "anchorY", type = "slider", x = 1, y = 21, w = 14, h = 2, label = L["垂直位置 (Y)"], min = -600, max = 600 },
    { key = "spacing", type = "slider", x = 16, y = 21, w = 14, h = 2, label = L["上下间距"], min = -10, max = 40, step = 1 },
    { key = "btn_test_cast", type = "button", x = 31, y = 21, w = 14, h = 2, label = L["测试施法(3秒)"] },
    { key = "btn_reset_pos", type = "button", x = 46, y = 21, w = 14, h = 2, label = L["重置位置"] },
    { key = "btn_test_channel", type = "button", x = 1, y = 25, w = 14, h = 2, label = L["测试引导(3秒)"] },
    { key = "btn_test_cast_check", type = "button", x = 16, y = 25, w = 16, h = 2, label = L["测试施法检测"] },
    { key = "timerBarGroup", type = "timerBarGroupV2", x = 1, y = 30, w = 63, h = 40, label = L["计时条外观"], labelSize = 20 },
    { key = "font_name", type = "fontgroup", x = 1, y = 74, w = 63, h = 14, label = L["法术名称"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 90, w = 63, h = 14, label = L["时间文本"], labelSize = 20 },
}

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

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then return BASE_GRID_COLS end
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
    if cached then return cached end
    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then row[k] = v end
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
    ExBossDB.timer.castProgressBar = ExBossDB.timer.castProgressBar or {}
    ApplyDefaults(ExBossDB.timer.castProgressBar, DEFAULTS)
    return ExBossDB.timer.castProgressBar
end

local function DebugPrint(msg)
    if not (ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true) then
        return
    end
    if ExBoss.Print and ExBoss.Print.Say then
        ExBoss.Print.Say("[CastBarDebug] " .. tostring(msg or ""))
    else
        print("|cff00ffff<EXBOSS>|r [CastBarDebug] " .. tostring(msg or ""))
    end
end

local function SavePosition(anchorX, anchorY)
    anchorX = math.floor(tonumber(anchorX) or DEFAULTS.anchorX)
    anchorY = math.floor(tonumber(anchorY) or DEFAULTS.anchorY)

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    if type(gridDB) == "table" then
        gridDB.anchorX = anchorX
        gridDB.anchorY = anchorY
    end

    local exdb = EnsureExBossDB()
    if type(exdb) == "table" then
        exdb.anchorX = anchorX
        exdb.anchorY = anchorY
    end
    DebugPrint(string.format("Page.SavePosition anchorX=%d anchorY=%d", anchorX, anchorY))
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb = EnsureExBossDB()
    if gridDB and exdb then
        ApplyDefaults(gridDB, DEFAULTS)
        for k, v in pairs(gridDB) do
            exdb[k] = v
        end
    end
    local group = gridDB and gridDB.timerBarGroup or nil
    DebugPrint(string.format(
        "DatabaseChanged key=%s fullPath=%s anchor=(%s,%s) texture=%s width=%s height=%s",
        tostring(info.key or "nil"),
        tostring(info.fullPath or "nil"),
        tostring(gridDB and gridDB.anchorX or "nil"),
        tostring(gridDB and gridDB.anchorY or "nil"),
        tostring(group and group.texture or "nil"),
        tostring(group and group.width or "nil"),
        tostring(group and group.height or "nil")
    ))
    if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.RefreshVisuals then
        ExBoss.UI.CastProgressBar:RefreshVisuals()
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb = EnsureExBossDB()
    if info.key == "btn_reset_pos" then
        SavePosition(DEFAULTS.anchorX, DEFAULTS.anchorY)
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.RefreshVisuals then
            ExBoss.UI.CastProgressBar:RefreshVisuals()
        end
    elseif info.key == "btn_test_cast" then
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.Preview then
            ExBoss.UI.CastProgressBar:Preview(3, "cast")
        end
    elseif info.key == "btn_test_channel" then
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.Preview then
            ExBoss.UI.CastProgressBar:Preview(3, "channel")
        end
    elseif info.key == "btn_test_cast_check" then
        if ExBoss.UI.CastProgressBar then
            if ExBoss.UI.CastProgressBar.PreviewCastCheck then
                ExBoss.UI.CastProgressBar:PreviewCastCheck(3)
            elseif ExBoss.UI.CastProgressBar.Preview then
                ExBoss.UI.CastProgressBar:Preview(3, "cast", { castCheckEnabled = true })
            end
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.StartFramePicker then
            ExBoss.UI.CastProgressBar:StartFramePicker()
        end
    end
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb = EnsureExBossDB()
    if exdb and gridDB then
        ApplyDefaults(gridDB, DEFAULTS)
        for k, v in pairs(exdb) do
            gridDB[k] = v
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_CastProgressBarSettingsScroll", contentFrame, "ScrollFrameTemplate")
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
