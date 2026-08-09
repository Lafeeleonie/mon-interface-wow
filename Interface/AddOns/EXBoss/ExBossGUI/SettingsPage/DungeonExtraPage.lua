---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.DungeonExtraPage = ExBoss.UI.Panel.DungeonExtraPage or {}
local Page = ExBoss.UI.Panel.DungeonExtraPage

local MODULE_KEY = "ExBoss.DungeonExtra"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

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

local DEFAULTS = {
    dogJumpEnabled = true,
    dogJumpPreview = false,
    trash248690Enabled = true,
    maxVisibleBars = 6,
    stackGap = 4,
    timerBarGroup = {},
    font_percent = {},
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["副本额外功能"], labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 1, label = L["特定副本/首领的额外辅助模块。"] },

    { key = "subheader_dog", type = "subheader", x = 1, y = 7, w = 63, h = 1, label = L["执政团之座 2号 - 狗跳点名"], labelSize = 20 },
    { key = "dog_desc", type = "description", x = 1, y = 10, w = 63, h = 2, label = L["实战只在 encounterID=2066 且事件237附近扫描队友有害光环实例ID，用最近两次目标排除下次候选。预览会显示样例面板并让候选队友框架发光，不写入实战记录。"] },
    { key = "dogJumpEnabled", type = "checkbox", x = 1, y = 13, w = 20, h = 2, label = L["启用狗跳点名模块"] },
    { key = "dogJumpPreview", type = "checkbox", x = 1, y = 16, w = 20, h = 2, label = L["预览狗跳点名面板"] },
    { key = "trash248690Enabled", type = "checkbox", x = 1, y = 19, w = 20, h = 2, label = L["启用小怪护盾条模块"] },
    { key = "btn_toggle_absorb_edit", type = "button", x = 1, y = 22, w = 14, h = 2, label = L["进入编辑模式"] },
    { key = "maxVisibleBars", type = "slider", x = 16, y = 22, w = 14, h = 2, label = L["最多显示几个"], min = 1, max = 8, step = 1 },
    { key = "stackGap", type = "slider", x = 31, y = 22, w = 14, h = 2, label = L["上下间距"], min = 0, max = 30, step = 1 },

    { key = "timerBarGroup", type = "timerBarGroupV2", x = 1, y = 27, w = 63, h = 40, label = L["计时条外观"], labelSize = 20 },
    { key = "font_percent", type = "fontgroup", x = 1, y = 71, w = 63, h = 14, label = L["百分比文本"], labelSize = 20 },

    { key = "subheader_vordaza", type = "subheader", x = 1, y = 88, w = 63, h = 1, label = L["迈萨拉洞窟 3号 - 沃达扎护盾"], labelSize = 20 },
    { key = "vordaza_desc", type = "description", x = 1, y = 91, w = 63, h = 1, label = L["进入编辑模式后可直接调整额外护盾条位置。"] },
    { key = "btn_toggle_vordaza_edit", type = "button", x = 1, y = 94, w = 14, h = 2, label = L["进入编辑模式"] },
}

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
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    local db = ExBossDB.timer.trash248690AbsorbPanel
    if type(db) ~= "table" then
        db = {}
        ExBossDB.timer.trash248690AbsorbPanel = db
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
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    local exdb = ExBossDB.timer.trash248690AbsorbStyle
    if type(exdb) ~= "table" then
        local legacy = ExBossDB.timer.extraShieldBar
        local migrated = {}
        if type(legacy) == "table" then
            DeepCopyInto(migrated, legacy)
            exdb = migrated
        else
            exdb = {}
        end
        ExBossDB.timer.trash248690AbsorbStyle = exdb
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

local function EnsurePageDB()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    DeepApplyDefaults(db, DEFAULTS)
    return db
end

local function SyncSourceToGridDB(gridDB)
    gridDB = gridDB or EnsurePageDB()
    local dogJump = GetDogJumpTracker()
    local panelDB = EnsureTrash248690PanelDB()
    local styleDB = EnsureTrash248690StyleDB()

    gridDB.dogJumpEnabled = (not dogJump or not dogJump.IsEnabled) or dogJump:IsEnabled()
    gridDB.dogJumpPreview = dogJump and dogJump.IsPreviewing and dogJump:IsPreviewing() == true or false
    local absorbMod = GetTrash248690AbsorbModule()
    gridDB.trash248690Enabled = (not absorbMod or not absorbMod.IsEnabled) or absorbMod:IsEnabled()
    gridDB.maxVisibleBars = tonumber(panelDB.maxVisibleBars) or 6
    gridDB.stackGap = tonumber(panelDB.stackGap) or 4
    if type(styleDB.timerBarGroup) == "table" then
        gridDB.timerBarGroup = gridDB.timerBarGroup or {}
        DeepCopyInto(gridDB.timerBarGroup, styleDB.timerBarGroup)
    end
    if type(styleDB.font_percent) == "table" then
        gridDB.font_percent = gridDB.font_percent or {}
        DeepCopyInto(gridDB.font_percent, styleDB.font_percent)
    end
end

local function SyncGridToSource(gridDB)
    gridDB = gridDB or EnsurePageDB()
    local dogJump = GetDogJumpTracker()
    if dogJump and dogJump.SetEnabled then
        dogJump:SetEnabled(gridDB.dogJumpEnabled == true)
    end
    if dogJump and dogJump.SetPreview then
        dogJump:SetPreview(gridDB.dogJumpPreview == true)
    end
    local absorbMod = GetTrash248690AbsorbModule()
    if absorbMod and absorbMod.SetEnabled then
        absorbMod:SetEnabled(gridDB.trash248690Enabled == true)
    end

    local panelDB = EnsureTrash248690PanelDB()
    panelDB.maxVisibleBars = math.max(1, math.min(8, math.floor(tonumber(gridDB.maxVisibleBars) or 6)))
    panelDB.stackGap = math.max(0, math.min(30, math.floor(tonumber(gridDB.stackGap) or 4)))

    local styleDB = EnsureTrash248690StyleDB()
    styleDB.timerBarGroup = styleDB.timerBarGroup or {}
    styleDB.font_percent = styleDB.font_percent or {}
    if type(gridDB.timerBarGroup) == "table" then
        styleDB.timerBarGroup = gridDB.timerBarGroup
        panelDB.width = math.max(80, tonumber(gridDB.timerBarGroup.width) or tonumber(panelDB.width) or 220)
        panelDB.height = math.max(8, tonumber(gridDB.timerBarGroup.height) or tonumber(panelDB.height) or 18)
    end
    if type(gridDB.font_percent) == "table" then
        styleDB.font_percent = gridDB.font_percent
    end

    local trashAbsorb = GetTrash248690AbsorbModule()
    if trashAbsorb and trashAbsorb.RefreshVisuals then
        trashAbsorb:RefreshVisuals()
    end
    local vordaza = GetVordazaShieldModule()
    if vordaza and vordaza.RefreshVisuals then
        vordaza:RefreshVisuals()
    end
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function()
    local gridDB = EnsurePageDB()
    SyncGridToSource(gridDB)
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then
        return
    end
    if info.key == "btn_toggle_absorb_edit" then
        local mod = GetTrash248690AbsorbModule()
        if mod and mod.ToggleEditMode then
            mod:ToggleEditMode()
        elseif ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    elseif info.key == "btn_toggle_vordaza_edit" then
        local mod = GetVordazaShieldModule()
        if mod and mod.ToggleEditMode then
            mod:ToggleEditMode()
        elseif ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    end
end)

local function RefreshDynamicButtonLabels()
    local Grid = _G.ExwindGrid
    local widgets = Grid and Grid.Widgets
    if type(widgets) ~= "table" then
        return
    end
    local absorbEdit = GetTrash248690AbsorbModule()
    local absorbBtn = widgets[MODULE_KEY .. "::btn_toggle_absorb_edit"]
    if absorbBtn and absorbBtn.SetText then
        local inEditMode = absorbEdit and absorbEdit.IsEditMode and absorbEdit:IsEditMode() == true
        absorbBtn:SetText(inEditMode and L["关闭编辑模式"] or L["进入编辑模式"])
    end
    local vordaza = GetVordazaShieldModule()
    local vordazaBtn = widgets[MODULE_KEY .. "::btn_toggle_vordaza_edit"]
    if vordazaBtn and vordazaBtn.SetText then
        local inEditMode = vordaza and vordaza.IsEditMode and vordaza:IsEditMode() == true
        vordazaBtn:SetText(inEditMode and L["关闭编辑模式"] or L["进入编辑模式"])
    end
end

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    local gridDB = EnsurePageDB()
    SyncSourceToGridDB(gridDB)

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_DungeonExtraSettingsScroll", contentFrame, "ScrollFrameTemplate")
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
        RefreshDynamicButtonLabels()
    end)
end

function Page:Hide()
    if Page._scrollFrame then
        Page._scrollFrame:Hide()
    end
end

if ExwindTools.RegisterEditModeHandler then
    ExwindTools:RegisterEditModeHandler(MODULE_KEY, {
        RefreshEditMode = function()
            RefreshDynamicButtonLabels()
        end,
    })
end
