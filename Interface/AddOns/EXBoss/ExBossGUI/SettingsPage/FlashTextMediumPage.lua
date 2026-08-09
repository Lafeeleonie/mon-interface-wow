---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/FlashTextMediumPage.lua
-- 中央文字公告（中）设置页
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.FlashTextMediumPage = ExBoss.UI.Panel.FlashTextMediumPage or {}
local Page = ExBoss.UI.Panel.FlashTextMediumPage

local MODULE_KEY = "ExBoss.FlashTextMedium"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

local DEFAULTS = {
    enabled = true,
    anchorX_1205 = 0,
    anchorY_1205 = 110,
    attachToCustom = false,
    customAttachTarget = "",
    flashDuration = 1.5,
    font_flash = {
        font = "默认",
        size = 32,
        outline = "OUTLINE",
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        shadow = true,
        shadowX = 2,
        shadowY = -2,
        x = 0,
        y = 0,
    },
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["中央文字公告(中)"], labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 1, label = "", labelSize = 18 },
    { key = "div_func", type = "divider", x = 1, y = 6, w = 63, h = 1, label = L["功能"] },
    { key = "enabled", type = "checkbox", x = 1, y = 8, w = 10, h = 2, label = L["启用"] },
    { key = "flashDuration", type = "slider", x = 13, y = 8, w = 14, h = 2, label = L["持续时间(秒)"], min = 0.5, max = 6, step = 0.5 },
    { key = "anchorX_1205", type = "slider", x = 28, y = 8, w = 14, h = 2, label = L["水平位置 (X)"], min = -1000, max = 1000, step = 5 },
    { key = "anchorY_1205", type = "slider", x = 43, y = 8, w = 14, h = 2, label = L["垂直位置 (Y)"], min = -600, max = 600, step = 5 },
    { key = "attachToCustom", type = "checkbox", x = 1, y = 12, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 13, y = 12, w = 28, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 43, y = 12, w = 14, h = 2, label = L["鼠标选取"] },
    { key = "font_flash", type = "fontgroup", x = 1, y = 16, w = 63, h = 17, label = L["中央文字公告(中)"], labelSize = 20 },
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
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.flashTextMedium = ExBossDB.timer.flashTextMedium or {}
    local exdb = ExBossDB.timer.flashTextMedium
    if gridDB and exdb then
        for k, v in pairs(gridDB) do exdb[k] = v end
    end
    if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.RefreshVisuals then
        ExBoss.UI.FlashTextMedium:RefreshVisuals()
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    if info.key == "btn_reset_pos" then
        local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
        if gridDB then
            gridDB.anchorX_1205 = 0; gridDB.anchorY_1205 = 110
        end
        ExBossDB = ExBossDB or {}
        ExBossDB.timer = ExBossDB.timer or {}
        ExBossDB.timer.flashTextMedium = ExBossDB.timer.flashTextMedium or {}
        ExBossDB.timer.flashTextMedium.anchorX_1205 = 0
        ExBossDB.timer.flashTextMedium.anchorY_1205 = 110
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.RefreshVisuals then
            ExBoss.UI.FlashTextMedium:RefreshVisuals()
        end
    elseif info.key == "btn_preview" then
        if ExwindTools.ToggleGlobalEditMode then ExwindTools:ToggleGlobalEditMode() end
    elseif info.key == "btn_test" then
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Show then
            local db = ExwindTools:GetModuleDB(MODULE_KEY)
            ExBoss.UI.FlashTextMedium:Show({ text = L["中字提示测试文字"], duration = db and db.flashDuration or 1.5 })
        end
    elseif info.key == "btn_pick_frame" then
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.StartFramePicker then
            ExBoss.UI.FlashTextMedium:StartFramePicker()
        end
    end
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.flashTextMedium = ExBossDB.timer.flashTextMedium or {}
    local exdb = ExBossDB.timer.flashTextMedium
    if exdb and gridDB then
        for k, v in pairs(exdb) do
            if gridDB[k] == nil then gridDB[k] = v end
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_FlashTextMediumSettingsScroll", contentFrame, "ScrollFrameTemplate")
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
