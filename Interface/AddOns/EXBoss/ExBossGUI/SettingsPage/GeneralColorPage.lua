---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GeneralColorPage = ExBoss.UI.Panel.GeneralColorPage or {}
local Page = ExBoss.UI.Panel.GeneralColorPage

local MODULE_KEY = "ExBoss.GeneralColor"
local BASE_GRID_COLS = 63
local MIN_GRID_COLS = 63
local MAX_GRID_COLS = 63
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

local function GetColorModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function EnsureColorDB()
    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        return CS.EnsureDB()
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.voice = ExBossDB.voice or {}
    ExBossDB.voice.colorSchemes = ExBossDB.voice.colorSchemes or {}
    ExBossDB.voice.customColors = ExBossDB.voice.customColors or {}
    ExBossDB.voice.extraCustomColors = ExBossDB.voice.extraCustomColors or {}
    ExBossDB.voice.customColors[1] = ExBossDB.voice.customColors[1] or { name = "自定义方案", r = 1, g = 0.82, b = 0.25 }
    for i = 1, 3 do
        ExBossDB.voice.extraCustomColors[i] = ExBossDB.voice.extraCustomColors[i] or {
            enabled = false,
            name = "额外方案" .. tostring(i),
            r = 1,
            g = 0.82,
            b = 0.25,
        }
    end
    return ExBossDB.voice
end

local function ApplyVoiceOverrides()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local function GetFixedOrder()
    local CS = GetColorModule()
    return (CS and CS.GetFixedOrder and CS.GetFixedOrder()) or { "tank", "heal", "cooldown", "mechanic" }
end

local function GetSchemeDisplayName(key)
    local CS = GetColorModule()
    return (CS and CS.GetSchemeDisplayName and CS.GetSchemeDisplayName(key)) or tostring(key or "")
end

local function GetExtraCustomCount()
    local CS = GetColorModule()
    return (CS and tonumber(CS.GetExtraCustomCount and CS.GetExtraCustomCount())) or 3
end

local function GetPath(config, path)
    if type(config) ~= "table" or type(path) ~= "string" or path == "" then
        return nil
    end
    local curr = config
    for part in string.gmatch(path, "([^%.]+)") do
        local k = tonumber(part) or part
        if type(curr) ~= "table" then
            return nil
        end
        curr = curr[k]
    end
    return curr
end

local function OpenColorPickerForPath(path)
    local db = EnsureColorDB()
    local row = GetPath(db, path)
    if type(row) ~= "table" then
        return
    end

    local currR = tonumber(row.r) or 1
    local currG = tonumber(row.g) or 1
    local currB = tonumber(row.b) or 1

    local function ApplyColor(r, g, b)
        row.r = math.max(0, math.min(1, tonumber(r) or currR))
        row.g = math.max(0, math.min(1, tonumber(g) or currG))
        row.b = math.max(0, math.min(1, tonumber(b) or currB))
        ApplyVoiceOverrides()
        ExwindTools:UpdateState(MODULE_KEY .. ".DatabaseChanged", {
            key = path,
            fullPath = path,
            value = { r = row.r, g = row.g, b = row.b },
            ts = GetTime(),
        })
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        hasOpacity = false,
        r = currR,
        g = currG,
        b = currB,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplyColor(r, g, b)
        end,
        cancelFunc = function(prev)
            ApplyColor(prev.r, prev.g, prev.b)
        end,
    })
end

local function BuildLayout()
    local layout = {
        { key = "header", type = "header", x = 1, y = 1, w = 63, h = 2, label = L["通用颜色方案"], labelSize = 25 },
        { key = "desc", type = "description", x = 1, y = 4, w = 63, h = 2, label = L["Boss 技能页会直接读取这里的配色方案。现在这页也走 Grid，可拖拽布局；颜色编辑走按钮打开取色器。"] },
        { key = "div_fixed", type = "divider", x = 1, y = 7, w = 63, h = 1, label = L["固定方案"] },
    }

    local rowY = 9
    for _, key in ipairs(GetFixedOrder()) do
        layout[#layout + 1] = {
            key = key .. "_label",
            type = "description",
            x = 1,
            y = rowY,
            w = 20,
            h = 1,
            label = GetSchemeDisplayName(key),
        }
        layout[#layout + 1] = {
            key = key .. "_color",
            type = "button",
            x = 23,
            y = rowY,
            w = 14,
            h = 2,
            label = L["编辑颜色"],
            func = function()
                OpenColorPickerForPath("colorSchemes." .. key)
            end,
        }
        rowY = rowY + 4
    end

    layout[#layout + 1] = { key = "div_custom", type = "divider", x = 1, y = rowY, w = 63, h = 1, label = L["自定义方案"] }
    rowY = rowY + 2
    layout[#layout + 1] = { key = "custom_name", parentKey = "customColors.1", subKey = "name", type = "input", x = 1, y = rowY, w = 20, h = 2, label = L["方案名称"] }
    layout[#layout + 1] = {
        key = "custom_color",
        type = "button",
        x = 23,
        y = rowY,
        w = 14,
        h = 2,
        label = L["编辑颜色"],
        func = function()
            OpenColorPickerForPath("customColors.1")
        end,
    }
    rowY = rowY + 4

    layout[#layout + 1] = { key = "div_extra", type = "divider", x = 1, y = rowY, w = 63, h = 1, label = L["额外方案"] }
    rowY = rowY + 2
    for i = 1, GetExtraCustomCount() do
        local parentKey = "extraCustomColors." .. tostring(i)
        layout[#layout + 1] = { key = "extra_enabled_" .. tostring(i), parentKey = parentKey, subKey = "enabled", type = "checkbox", x = 1, y = rowY, w = 10, h = 2, label = L["启用"] }
        layout[#layout + 1] = { key = "extra_name_" .. tostring(i), parentKey = parentKey, subKey = "name", type = "input", x = 13, y = rowY, w = 20, h = 2, label = L["名称"] }
        layout[#layout + 1] = {
            key = "extra_color_" .. tostring(i),
            type = "button",
            x = 35,
            y = rowY,
            w = 14,
            h = 2,
            label = L["编辑颜色"],
            func = function()
                OpenColorPickerForPath(parentKey)
            end,
        }
        rowY = rowY + 4
    end

    return layout
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
        return items
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

ExwindTools:RegisterModuleLayout(MODULE_KEY, BuildLayout())

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function()
    ApplyVoiceOverrides()
end)

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid or not contentFrame then
        return
    end

    local colorDB = EnsureColorDB()
    local layout = BuildLayout()

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_GeneralColorScroll", contentFrame, "ScrollFrameTemplate")
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
        Grid:Render(sc, ScaleLayout(layout, cols), colorDB, MODULE_KEY)
    end)
end
