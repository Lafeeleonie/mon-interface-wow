---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/GlobalTrashCDPage.lua
-- 小怪CD 全局设置页（ExwindGrid 渲染）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GlobalTrashCDPage = ExBoss.UI.Panel.GlobalTrashCDPage or {}
local Page = ExBoss.UI.Panel.GlobalTrashCDPage

local MODULE_KEY     = "ExBoss.TrashCD.Settings"
local BASE_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE   = {}

-- =============================================================
-- 默认值
-- =============================================================
local DEFAULTS = {
    hideLongTimerBarEnabled      = false,
    hideLongTimerBarSeconds      = 0,
    keepTimerBarAfterReadyEnabled = true,
    keepTimerBarAfterReadySeconds = 10,
    nameplateGrowthSide          = "left",
    nameplateIcon = {
        borderColorA  = 1,
        borderColorB  = 0,
        borderColorG  = 0,
        borderColorR  = 0,
        borderPadding = 0,
        borderSize    = 1,
        borderTexture = "Square Full White",
        height        = 25,
        reverse       = false,
        showBorder    = true,
        showIcon      = true,
        spacing       = 2,
        readyBorderEnabled = true,
        readyBorderColorR  = 0.20,
        readyBorderColorG  = 0.85,
        readyBorderColorB  = 0.20,
        readyBorderColorA  = 1,
        width         = 25,
        x             = 6,
        y             = 0,
    },
    nameplateIconStrata          = "DIALOG",
    nameplateIconText = {
        a       = 1,
        b       = 1,
        font    = "",
        g       = 1,
        outline = "OUTLINE",
        r       = 1,
        shadow  = true,
        shadowX = 1,
        shadowY = -1,
        size    = 15,
        x       = 0,
        y       = 0,
    },
}

-- =============================================================
-- 布局
-- =============================================================
local LAYOUT = {
    { key = "header_main",      type = "header",   x = 1,  y = 1,  w = 63, h = 2,  label = L["小怪CD全局设置"], labelSize = 22 },

    -- 计时规则
    { key = "header_timer",     type = "header",   x = 1,  y = 4,  w = 63, h = 2,  label = L["计时规则"], labelSize = 18 },
    { key = "hideLongTimerBarEnabled",       type = "checkbox", x = 1,  y = 7,  w = 10, h = 2, label = L["隐藏"] },
    { key = "hideLongTimerBarSeconds",       type = "input",    x = 12, y = 7,  w = 5,  h = 2, label = L["秒以上的计时条"], labelPos = "right" },
    { key = "keepTimerBarAfterReadyEnabled", type = "checkbox", x = 1,  y = 10, w = 10, h = 2, label = L["技能冷却结束后"] },
    { key = "keepTimerBarAfterReadySeconds", type = "input",    x = 12, y = 10, w = 5,  h = 2, label = L["秒隐藏"], labelPos = "right" },
    { key = "readyBorderEnabled", parentKey = "nameplateIcon", type = "checkbox", x = 1,  y = 13, w = 10, h = 2, label = L["就绪边框"] },
    { key = "readyBorderColor",   parentKey = "nameplateIcon", type = "color",    x = 12, y = 13, w = 12, h = 2, label = L["就绪边框颜色"] },

    -- 姓名版设置
    { key = "header_nameplate", type = "header",   x = 1,  y = 16, w = 63, h = 2,  label = L["姓名版设置"], labelSize = 18 },
    {
        key      = "nameplateGrowthSide",
        type     = "dropdown",
        x = 1,  y = 19, w = 14, h = 2,
        label    = L["姓名版图标方向"],
        labelPos = "top",
        items    = {
            { L["向右增长"], "right" },
            { L["向左增长"], "left"  },
        },
    },
    {
        key      = "nameplateIconStrata",
        type     = "dropdown",
        x = 19, y = 19, w = 14, h = 2,
        label    = L["姓名版图标层级"],
        labelPos = "top",
        items    = {
            { L["背景"],     "BACKGROUND"        },
            { L["低"],       "LOW"               },
            { L["中"],       "MEDIUM"            },
            { L["高"],       "HIGH"              },
            { L["对话"],     "DIALOG"            },
            { L["全屏"],     "FULLSCREEN"        },
            { L["全屏对话"], "FULLSCREEN_DIALOG" },
            { L["提示"],     "TOOLTIP"           },
        },
    },

    -- 图标参数组（含间距滑块）
    {
      key = "nameplateIcon",
      type = "icongroup",
      x = 1,
      y = 23,
      w = 63,
      h = 23,
      label = L["姓名版图标参数"],
      opts = {
        enableSpacing = true,
        enableOffset = true
      }
    },

    -- 倒数字体参数组
    { key = "nameplateIconText", type = "fontgroup",  x = 1, y = 48, w = 63, h = 17, label = L["姓名版倒数字体参数"] },
}

-- =============================================================
-- 工具函数
-- =============================================================
local function ApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function GetTrashExDB()
    if type(_G.ExBossDB) ~= "table" then return nil end
    if type(_G.ExBossDB.trashCD) ~= "table" then _G.ExBossDB.trashCD = {} end
    return _G.ExBossDB.trashCD
end

local function PublishChanges(reason)
    local Store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store
    if Store and type(Store.SyncSavedToModuleDB) == "function" then
        Store.SyncSavedToModuleDB()
    end
    if Store and type(Store.PublishConfigChanged) == "function" then
        Store.PublishConfigChanged(reason or "trashGlobal")
    end
end

local function SyncGridToExDB()
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY)
    local exdb   = GetTrashExDB()
    if not (gridDB and exdb) then return end
    ApplyDefaults(gridDB, DEFAULTS)
    -- 写回 ExBossDB.trashCD（只同步本页管理的字段）
    local SYNC_KEYS = {
        "hideLongTimerBarEnabled", "hideLongTimerBarSeconds",
        "keepTimerBarAfterReadyEnabled", "keepTimerBarAfterReadySeconds",
        "nameplateGrowthSide", "nameplateIconStrata",
    }
    for _, k in ipairs(SYNC_KEYS) do
        exdb[k] = gridDB[k]
    end
    -- 同步嵌套表
    if type(gridDB.nameplateIcon) == "table" then
        exdb.nameplateIcon = exdb.nameplateIcon or {}
        for k, v in pairs(gridDB.nameplateIcon) do
            exdb.nameplateIcon[k] = v
        end
    end
    if type(gridDB.nameplateIconText) == "table" then
        exdb.nameplateIconText = exdb.nameplateIconText or {}
        for k, v in pairs(gridDB.nameplateIconText) do
            exdb.nameplateIconText[k] = v
        end
    end
end

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then return BASE_GRID_COLS end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < BASE_GRID_COLS then cols = BASE_GRID_COLS end
    if cols > BASE_GRID_COLS then cols = BASE_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then return LAYOUT end
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
                if nx + nw - 1 > toCols then nw = math.max(1, toCols - nx + 1) end
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

-- =============================================================
-- DB 变更监听 → 写回 ExBossDB + 刷新显示
-- =============================================================
ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function(info)
    if not info then return end
    SyncGridToExDB()
    local reason = (type(info) == "table" and info.key) or "trashGlobal"
    PublishChanges(reason)
end)

-- =============================================================
-- Render
-- =============================================================
function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end

    -- 把 ExBossDB.trashCD 的现有值同步进 gridDB
    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local exdb   = GetTrashExDB()
    if gridDB and exdb then
        ApplyDefaults(gridDB, DEFAULTS)
        -- 从 ExBossDB 载入最新值（保证面板打开时显示正确）
        local SYNC_KEYS = {
            "hideLongTimerBarEnabled", "hideLongTimerBarSeconds",
            "keepTimerBarAfterReadyEnabled", "keepTimerBarAfterReadySeconds",
            "nameplateGrowthSide", "nameplateIconStrata",
        }
        for _, k in ipairs(SYNC_KEYS) do
            if exdb[k] ~= nil then gridDB[k] = exdb[k] end
        end
        if type(exdb.nameplateIcon) == "table" then
            gridDB.nameplateIcon = gridDB.nameplateIcon or {}
            ApplyDefaults(gridDB.nameplateIcon, DEFAULTS.nameplateIcon)
            for k, v in pairs(exdb.nameplateIcon) do
                gridDB.nameplateIcon[k] = v
            end
        end
        if type(exdb.nameplateIconText) == "table" then
            gridDB.nameplateIconText = gridDB.nameplateIconText or {}
            ApplyDefaults(gridDB.nameplateIconText, DEFAULTS.nameplateIconText)
            for k, v in pairs(exdb.nameplateIconText) do
                gridDB.nameplateIconText[k] = v
            end
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_GlobalTrashCDScroll",
            contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        Page._scrollFrame = sf
        Page._scrollChild  = sc
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild
    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT",     contentFrame, "TOPLEFT",     4,   -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24,  4)
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
            ExwindTools.UI.ActivePageFrame  = sc
            ExwindTools.UI.CurrentModule    = MODULE_KEY
        end
        local cols = ResolveGridCols(sc:GetWidth())
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), gridDB, MODULE_KEY)
    end)
end
