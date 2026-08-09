---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/PrivateAuraMonitorPage.lua
-- 私人光环监控设置页（ExwindGrid 渲染）
-- 监控玩家自身3个私人光环槽位的显示配置
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local function T(key)
    if type(L) == "table" and L[key] then
        return L[key]
    end
    return key
end

ExBoss.UI.Panel.PrivateAuraMonitorPage = ExBoss.UI.Panel.PrivateAuraMonitorPage or {}
local Page = ExBoss.UI.Panel.PrivateAuraMonitorPage

local MODULE_KEY  = "ExBoss.PrivateAuraMonitor"
local BASE_COLS   = 63
local TARGET_CELL = 18

-- =============================================================
-- 默认值
-- =============================================================
local DEFAULTS = {
    enabled          = false,
    iconSize         = 56,
    iconSpacing      = 8,
    growDir          = "RIGHT",
    showBorder       = true,
    borderScale      = 1.0,
    showCountdown    = true,
    showNumbers      = true,
    durationOffsetX  = 0,
    durationOffsetY  = 0,
    anchorX          = 0,
    anchorY          = -200,
    anchorPoint      = "CENTER",
}

-- =============================================================
-- Grid 布局定义
-- =============================================================
local LAYOUT = {
    { key = "header",       type = "header",   x = 1,  y = 2,  w = 63, h = 2, label = T("私人光环监控"), labelSize = 23 },
    { key = "enabled",      type = "checkbox", x = 1,  y = 5,  w = 14, h = 2, label = T("启用") },
    { key = "btn_preview",  type = "button",   x = 50, y = 5,  w = 10, h = 2, label = T("进入编辑模式") },
    { key = "anchorX",      type = "slider",   x = 1,  y = 9,  w = 15, h = 2, label = T("水平位置 (X)"), min = -1500, max = 1500 },
    { key = "anchorY",      type = "slider",   x = 18, y = 9,  w = 15, h = 2, label = T("垂直位置 (Y)"), min = -800, max = 800 },
    { key = "anchorPoint",  type = "dropdown", x = 34, y = 9,  w = 14, h = 2, label = T("锚点"), items = {
        { T("屏幕中央"), "CENTER" }, { T("左上角"), "TOPLEFT" }, { T("上方中央"), "TOP" }, { T("右上角"), "TOPRIGHT" },
        { T("左侧中央"), "LEFT" }, { T("右侧中央"), "RIGHT" }, { T("左下角"), "BOTTOMLEFT" }, { T("下方中央"), "BOTTOM" },
        { T("右下角"), "BOTTOMRIGHT" },
    }, labelPos = "top" },
    { key = "btn_reset_pos", type = "button",  x = 50, y = 9,  w = 10, h = 2, label = T("重置位置"), labelSize = 18 },
    { key = "header_9545",  type = "header",   x = 1,  y = 13, w = 63, h = 2, label = T("外观设置"), labelSize = 20 },
    { key = "iconSize",     type = "slider",   x = 1,  y = 17, w = 15, h = 2, label = T("图标大小"), min = 20, max = 128 },
    { key = "iconSpacing",  type = "slider",   x = 18, y = 17, w = 15, h = 2, label = T("图标间距"), min = 0, max = 60 },
    { key = "growDir",      type = "dropdown", x = 34, y = 17, w = 14, h = 2, label = T("排列方向"), items = {
        { T("向右"), "RIGHT" }, { T("向左"), "LEFT" }, { T("向上"), "UP" }, { T("向下"), "DOWN" },
    } },
    { key = "showBorder",   type = "checkbox", x = 1,  y = 20, w = 8,  h = 2, label = T("显示边框") },
    { key = "borderScale",  type = "slider",   x = 18, y = 20, w = 15, h = 2, label = T("边框缩放"), min = 0.1, max = 3 },
    { key = "header_4495",  type = "header",   x = 1,  y = 24, w = 63, h = 2, label = T("冷却设置"), labelSize = 20 },
    { key = "showCountdown",   type = "checkbox", x = 1,  y = 27, w = 14, h = 2, label = T("显示冷却圈") },
    { key = "showNumbers",     type = "checkbox", x = 18, y = 27, w = 15, h = 2, label = T("显示数字倒计时") },
    -- durationAnchor 偏移：把冷却圈/数字锚定到图标中心之外的位置
    { key = "durationOffsetX", type = "slider", x = 1,  y = 30, w = 15, h = 2, label = T("倒计时水平偏移"), min = -150, max = 150 },
    { key = "durationOffsetY", type = "slider", x = 18, y = 30, w = 15, h = 2, label = T("倒计时垂直偏移"), min = -150, max = 150 },
}

-- =============================================================
-- 运行时状态
-- =============================================================
local anchorIDs  = {}    -- [1..3] anchorID
local rootFrame  = nil   -- 根 Frame（真实锚点，不可见）
local slotFrames = {}    -- [1..3] 每个槽位真实 Frame
local previewFrames = {} -- [1..3] 编辑模式假图标
local pendingApply = false
local UpdateRootSize

-- =============================================================
-- 工具函数
-- =============================================================
local function GetDB()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local function SetClickThrough(frame)
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
end

local function GetSlotOffset(db, idx)
    local totalW, totalH
    local step = (db.iconSize or 56) + (db.iconSpacing or 8)
    local sz = db.iconSize or 56
    local dir = db.growDir or "RIGHT"
    if dir == "RIGHT" or dir == "LEFT" then
        totalW = step * 3 - (db.iconSpacing or 8)
        totalH = sz
    else
        totalW = sz
        totalH = step * 3 - (db.iconSpacing or 8)
    end
    local dx = (totalW - sz) * 0.5
    local dy = (totalH - sz) * 0.5
    local i = idx - 1
    if dir == "RIGHT" then return -dx + i * step, 0 end
    if dir == "LEFT"  then return  dx - i * step, 0 end
    if dir == "UP"    then return 0, -dy + i * step end
    return 0, dy - i * step
end

local function GetRootSize(db)
    local step = (db.iconSize or 56) + (db.iconSpacing or 8)
    local dir  = db.growDir or "RIGHT"
    local sz = db.iconSize or 56
    if dir == "RIGHT" or dir == "LEFT" then
        return step * 3 - (db.iconSpacing or 8), sz
    end
    return sz, step * 3 - (db.iconSpacing or 8)
end

local function GetAnchorAdjustment(db)
    local w, h = GetRootSize(db)
    local sz = db.iconSize or 56
    local dir = db.growDir or "RIGHT"
    if dir == "RIGHT" then return  (w - sz) * 0.5, 0 end
    if dir == "LEFT"  then return -(w - sz) * 0.5, 0 end
    if dir == "UP"    then return 0,  (h - sz) * 0.5 end
    if dir == "DOWN"  then return 0, -(h - sz) * 0.5 end
    return 0, 0
end

-- =============================================================
-- 真实锚点管理
-- =============================================================
local function RemoveAllAnchors()
    for i = 1, 3 do
        if anchorIDs[i] then
            C_UnitAuras.RemovePrivateAuraAnchor(anchorIDs[i])
            anchorIDs[i] = nil
        end
    end
end

local function EnsureFrames()
    if not rootFrame then
        rootFrame = CreateFrame("Frame", "ExBoss_PAMonitor_Root", UIParent)
        rootFrame:SetSize(1, 1)
        SetClickThrough(rootFrame)
        rootFrame:SetMovable(true)
        rootFrame:SetClampedToScreen(false)
        rootFrame:SetFrameStrata("MEDIUM")

        rootFrame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and ExwindTools.GlobalEditMode then
                self.isMoving = true
                self:StartMoving()
            elseif button == "RightButton" and ExwindTools.GlobalEditMode then
                ExwindTools:OpenConfig(MODULE_KEY)
            end
        end)
        rootFrame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                self.isMoving = false
                self:StopMovingOrSizing()
                local cx, cy = UIParent:GetCenter()
                local sx, sy = self:GetCenter()
                if sx and cx then
                    local db = GetDB()
                    local ax, ay = GetAnchorAdjustment(db)
                    db.anchorY     = math.floor((sy - cy) - ay)
                    db.anchorX     = math.floor((sx - cx) - ax)
                    db.anchorPoint = "CENTER"
                    ExwindTools:UpdateState(MODULE_KEY .. ".DatabaseChanged", { key = "anchorX" })
                end
            end
        end)

        ExwindTools:RegisterHUD(MODULE_KEY, rootFrame)
        SetClickThrough(rootFrame)
    end

    for i = 1, 3 do
        if not slotFrames[i] then
            slotFrames[i] = CreateFrame("Frame", nil, UIParent)
            SetClickThrough(slotFrames[i])
        end
        if not previewFrames[i] then
            local pf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            pf:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            pf:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            pf:SetBackdropBorderColor(0.2, 0.8, 1, 0.9)
            local tex = pf:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            tex:SetAlpha(0.5)
            pf.tex = tex
            local num = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            num:SetPoint("CENTER")
            num:SetTextColor(1, 1, 0)
            num:SetText(tostring(i))
            pf:Hide()
            previewFrames[i] = pf
        end
    end
end

-- 更新预览框的 Backdrop edgeSize，使 borderScale 可即时预览
local function RefreshPreviewFrameBackdrop(pf, db)
    local sz = db.iconSize or 56
    local edgeSz = db.showBorder and math.max(2, math.floor(sz / 16 * (db.borderScale or 1.0) + 0.5)) or 0
    pf:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = edgeSz > 0 and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
        tile = true, tileSize = 16, edgeSize = edgeSz,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    pf:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
    pf:SetBackdropBorderColor(0.2, 0.8, 1, 0.9)
end

function Page:ApplyAnchors()
    if InCombatLockdown and InCombatLockdown() then
        pendingApply = true
        return
    end

    pendingApply = false
    RemoveAllAnchors()
    EnsureFrames()

    local db = GetDB()
    local sz     = db.iconSize or 56
    local bScale = db.showBorder and (db.borderScale or 1.0) or -100
    local borderPx = sz / 16 * bScale

    -- 始终更新 rootFrame 位置（编辑模式拖动需要）
    local rootW, rootH = GetRootSize(db)
    local adjX, adjY   = GetAnchorAdjustment(db)
    rootFrame:SetSize(math.max(rootW, 1), math.max(rootH, 1))
    rootFrame:ClearAllPoints()
    rootFrame:SetPoint(db.anchorPoint or "CENTER", UIParent, db.anchorPoint or "CENTER",
        (db.anchorX or 0) + adjX, (db.anchorY or 0) + adjY)

    -- 始终更新 slot/preview frame 位置和大小（缩放在禁用状态下也能预览）
    for i = 1, 3 do
        local ox, oy = GetSlotOffset(db, i)
        local f = slotFrames[i]
        f:SetSize(sz, sz)
        f:ClearAllPoints()
        f:SetPoint("CENTER", rootFrame, "CENTER", ox, oy)

        local pf = previewFrames[i]
        pf:SetSize(sz, sz)
        pf:ClearAllPoints()
        pf:SetPoint("CENTER", f, "CENTER", 0, 0)
        RefreshPreviewFrameBackdrop(pf, db)
    end

    if not db.enabled then
        -- 禁用状态：编辑模式保留 rootFrame 可见（用于拖拽定位）
        if not ExwindTools.GlobalEditMode then
            rootFrame:Hide()
        end
        for i = 1, 3 do
            slotFrames[i]:Hide()
        end
        return
    end

    rootFrame:Show()

    -- durationAnchor：当偏移非零时把冷却圈锚定到图标中心偏移处
    local dox = db.durationOffsetX or 0
    local doy = db.durationOffsetY or 0
    local hasDurationOffset = db.showCountdown and (dox ~= 0 or doy ~= 0)

    for i = 1, 3 do
        local f = slotFrames[i]
        f:Show()

        local durationAnchor = nil
        if hasDurationOffset then
            durationAnchor = {
                point         = "CENTER",
                relativeTo    = f,
                relativePoint = "CENTER",
                offsetX       = dox,
                offsetY       = doy,
            }
        end

        anchorIDs[i] = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken            = "player",
            auraIndex            = i,
            parent               = f,
            showCountdownFrame   = db.showCountdown == true,
            showCountdownNumbers = db.showNumbers == true,
            isContainer          = false,
            iconInfo = {
                iconAnchor = {
                    point         = "CENTER",
                    relativeTo    = f,
                    relativePoint = "CENTER",
                    offsetX       = 0,
                    offsetY       = 0,
                },
                iconWidth   = sz,
                iconHeight  = sz,
                borderScale = borderPx,
            },
            durationAnchor = durationAnchor,
        })
    end
end

-- =============================================================
-- 编辑模式回调
-- =============================================================
local function SetEditMode(enabled)
    EnsureFrames()
    local db = GetDB()
    if enabled then
        -- 编辑模式开启：始终显示预览框（不要求模块已启用）
        UpdateRootSize()
        rootFrame:Show()
        rootFrame:EnableMouse(true)
        for i = 1, 3 do
            -- 确保 previewFrame 位置/大小是最新的
            local ox, oy = GetSlotOffset(db, i)
            local sz = db.iconSize or 56
            slotFrames[i]:SetSize(sz, sz)
            slotFrames[i]:ClearAllPoints()
            slotFrames[i]:SetPoint("CENTER", rootFrame, "CENTER", ox, oy)
            previewFrames[i]:SetSize(sz, sz)
            previewFrames[i]:ClearAllPoints()
            previewFrames[i]:SetPoint("CENTER", slotFrames[i], "CENTER", 0, 0)
            RefreshPreviewFrameBackdrop(previewFrames[i], db)
            previewFrames[i]:Show()
            previewFrames[i]:SetFrameStrata("DIALOG")
        end
    else
        -- 编辑模式关闭
        if not db.enabled then
            rootFrame:Hide()
        end
        SetClickThrough(rootFrame)
        for i = 1, 3 do
            previewFrames[i]:Hide()
        end
    end
end

UpdateRootSize = function()
    if not rootFrame then return end
    local db = GetDB()
    local w, h = GetRootSize(db)
    rootFrame:SetSize(math.max(w, 1), math.max(h, 1))
    -- 编辑模式下始终保持 rootFrame 可见
    if ExwindTools.GlobalEditMode then
        rootFrame:Show()
    end
end

ExwindTools:RegisterEditModeCallback(MODULE_KEY, SetEditMode)

-- =============================================================
-- Grid 注册 & 控件事件
-- =============================================================
ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_cfg", function()
    Page:ApplyAnchors()
    UpdateRootSize()
    if ExwindTools.GlobalEditMode then
        SetEditMode(true)
    end
end)

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info then return end
    if info.key == "btn_preview" then
        ExwindTools:ToggleGlobalEditMode()
    elseif info.key == "btn_reset_pos" then
        local db = GetDB()
        db.anchorX     = DEFAULTS.anchorX
        db.anchorY     = DEFAULTS.anchorY
        db.anchorPoint = DEFAULTS.anchorPoint
        Page:ApplyAnchors()
        ExwindTools:UpdateState(MODULE_KEY .. ".DatabaseChanged", { key = "anchorX" })
    end
end)

-- =============================================================
-- 登录初始化
-- =============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer.After(0.5, function()
            Page:ApplyAnchors()
            UpdateRootSize()
        end)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and pendingApply then
        Page:ApplyAnchors()
        UpdateRootSize()
        if ExwindTools.GlobalEditMode then
            SetEditMode(true)
        end
    end
end)

-- =============================================================
-- 渲染接口（由 GlobalSettingsPage embed 调用）
-- =============================================================
function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_PAMonitorSettingsScroll",
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
    sf:SetAllPoints(contentFrame)
    sc:SetWidth(contentFrame:GetWidth() - 24)

    local cols = math.max(BASE_COLS, math.floor(((contentFrame:GetWidth() - 24 - 20) / TARGET_CELL) + 0.5))
    Grid:SetContainerCols(sc, cols)

    ExwindTools.UI.ActivePageFrame = sc
    ExwindTools.UI.CurrentModule   = MODULE_KEY

    Grid:Render(sc, LAYOUT, GetDB(), MODULE_KEY)

    sf:Show()
end

function Page:Hide()
    if Page._scrollFrame then
        Page._scrollFrame:Hide()
        if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == Page._scrollChild then
            ExwindTools.UI.ActivePageFrame = nil
            ExwindTools.UI.CurrentModule   = nil
        end
    end
end
