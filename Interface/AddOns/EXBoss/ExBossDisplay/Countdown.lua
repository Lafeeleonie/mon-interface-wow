---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/Countdown.lua
-- 屏幕中央倒计时
--
-- 布局：[图标] [名称] [数字]
--   完全由 OnUpdate 驱动，帧率同步，无卡顿
--   使用 HorizontalLayoutFrame 自动布局，不在 Lua 层计算文本宽度。
--
-- 公开接口：
--   Countdown:Show(timer)       开始倒计时
--   Countdown:Stop()            提前终止
--   Countdown:RefreshVisuals()  设置变化后刷新
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end

ExBoss.UI.Countdown = ExBoss.UI.Countdown or {}
local Countdown     = ExBoss.UI.Countdown
local BorderUtil    = ExBoss.BorderUtil
local MODULE_KEY    = "ExBoss.Countdown"
local L             = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local anchorController = nil
local anchorFrame = nil
local updater = nil
local isPreviewing = false
local _entries = {}
local _entrySeq = 0
local ANCHOR_WIDTH = 200
local FALLBACK_DB = nil
local RenderStack = nil
local SplitTemplate = nil
local StopAll = nil

-- 显示层备注：
-- Countdown 只负责最终显示，不承担 fixed/blizzard 业务判断。
-- 无特殊情况禁止修改本模块的显示结构；若需变更，优先在调度层/分发层整理输入参数。

-- =============================================================
-- DB 访问
-- =============================================================
local function DB()
    if ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY)
        if ok and type(mdb) == "table" then return mdb end
    end
    local db = _G.ExBossDB
    return db and db.timer and db.timer.countdown
end

local function SafeNum(v, def) return tonumber(v) or def end

local function ApplyBackdropBorder(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
    if not borderFrame or not targetFrame or not texturePath then
        return
    end
    borderFrame:SetFrameLevel(frameLevel or (targetFrame:GetFrameLevel() + 2))
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)
    borderFrame:SetBackdrop({
        edgeFile = texturePath,
        edgeSize = edgeSize,
    })
    borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    borderFrame:Show()
end

local function HideBackdropBorder(borderFrame)
    if borderFrame then
        borderFrame:Hide()
    end
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function SetClickThrough(frame)
    if not frame then return end
    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        pcall(frame.SetMouseClickEnabled, frame, false)
    end
    if frame.SetMouseMotionEnabled then
        pcall(frame.SetMouseMotionEnabled, frame, false)
    end
end

local function EnsureAnchorController()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_CountdownAnchor",
        frameTemplate = "BackdropTemplate",
        title = L["倒计时"],
        getDB = DB,
        offsetXKey = "anchorX_1205",
        offsetYKey = "anchorY_1205",
        syncWidgets = {
            "anchorX_1205",
            "anchorY_1205",
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = ANCHOR_WIDTH,
        initialHeight = 80,
        clampedToScreen = false,
        frameStrata = "FULLSCREEN_DIALOG",
        fixedFrameStrata = true,
        frameLevel = 100,
        onCreateFrame = function(_, frame)
            frame:Hide()
        end,
        onEditModeChanged = function(_, active, visible)
            local db = DB() or FALLBACK_DB
            if active and visible then
                isPreviewing = true
                local tmpl = (type(db.labelTemplate) == "string" and db.labelTemplate ~= "") and db.labelTemplate or
                    FALLBACK_DB.labelTemplate
                local pre, suf = SplitTemplate(tmpl, L["坦克尖刺"])
                _entries[1] = {
                    id = 0,
                    startTime = GetTime(),
                    duration = 5,
                    endTime = GetTime() + 999,
                    pre = pre,
                    suf = suf,
                    iconID = 136197,
                    color = nil,
                }
                for i = #_entries, 2, -1 do
                    _entries[i] = nil
                end
                RenderStack(3)
                if updater then updater:Hide() end
            else
                isPreviewing = false
                StopAll()
            end
        end,
    })

    return anchorController
end

FALLBACK_DB = {
    enabled       = true,
    showIcon      = true,
    iconSize      = 25,
    countdownIcon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 25,
        height = 25,
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
    font_label    = {
        font = "默认",
        size = 25,
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
    font_cd       = {
        font = "默认",
        size = 25,
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

local function NormalizeColorTable(c)
    if type(c) ~= "table" then return nil end
    local r, g, b, a
    if type(c.GetRGB) == "function" then
        local ok, rr, gg, bb = pcall(c.GetRGB, c)
        if ok then
            r, g, b = rr, gg, bb
        end
        a = c.a
    else
        r, g, b, a = c.r, c.g, c.b, c.a
    end
    if tonumber(r) and tonumber(g) and tonumber(b) then
        return {
            r = tonumber(r),
            g = tonumber(g),
            b = tonumber(b),
            a = tonumber(a) or 1,
        }
    end
    return nil
end

local function ResolveCountdownTextColor(spec)
    if type(spec) ~= "table" then return nil end
    return spec.color
end

local function EnsureCountdownIconDB(db)
    db = type(db) == "table" and db or FALLBACK_DB
    if type(db.countdownIcon) ~= "table" then
        db.countdownIcon = {}
    end
    local iconDB = db.countdownIcon
    local fallback = FALLBACK_DB.countdownIcon
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

local function ResolveCountdownIconTexture(spec, db)
    if type(spec) == "table" then
        return spec.iconFileID
    end
    local okSpell, spellID = pcall(function()
        local numeric = tonumber(type(spec) == "table" and spec.spellID or nil)
        if numeric and numeric > 0 then
            return numeric
        end
        return nil
    end)
    spellID = okSpell and spellID or nil
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    local iconDB = EnsureCountdownIconDB(db)
    local fallbackID = tonumber(iconDB.iconID)
    if fallbackID and fallbackID > 0 then
        return fallbackID
    end
    return nil
end

-- =============================================================
-- ApplyFont（优先 StaticDB:ApplyFont，兜底手动）
-- =============================================================
local function ApplyFont(fs, fontDB, defSize)
    if not fs or not fontDB then return end
    local StaticDB = ExwindTools.DB_Static
    if StaticDB and StaticDB.ApplyFont then
        StaticDB:ApplyFont(fs, fontDB)
        return
    end
    local LSM  = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = (LSM and fontDB.font and fontDB.font ~= "默认")
        and LSM:Fetch("font", fontDB.font)
        or (ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT)
    fs:SetFont(path, SafeNum(fontDB.size, defSize or 46), fontDB.outline or "OUTLINE")
    fs:SetTextColor(SafeNum(fontDB.r, 1), SafeNum(fontDB.g, 1), SafeNum(fontDB.b, 1), SafeNum(fontDB.a, 1))
    if fontDB.shadow then
        fs:SetShadowOffset(SafeNum(fontDB.shadowX, 2), SafeNum(fontDB.shadowY, -2))
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- =============================================================
-- 帧变量
-- =============================================================
local rows            = {} -- 可复用行：每行 icon + label + cd
local _cdGap          = 6
local _updateElapsed  = 0
local UPDATE_INTERVAL = 0.1

local function GetStackGap(db)
    return math.max(0, math.floor(SafeNum(db and db.stackGap, 4)))
end

local function GetStackMax(db)
    return math.max(1, math.floor(SafeNum(db and db.stackMax_1205, 2)))
end

local function ApplyVerticalOffset(region, offset)
    offset = SafeNum(offset, 0)
    region._yOffset = offset
end

local function ApplyHorizontalOffset(region, offset)
    offset = SafeNum(offset, 0)
    region._xOffset = offset
end

local function GetRowHeight(db)
    local iconDB = EnsureCountdownIconDB(db)
    local showIco = iconDB.showIcon ~= false
    local icoHeight = showIco and math.max(8, SafeNum(iconDB.height, SafeNum(iconDB.width, 25))) or 0
    local labelSize = SafeNum((db.font_label or FALLBACK_DB.font_label).size, 46)
    local cdSize = SafeNum((db.font_cd or FALLBACK_DB.font_cd).size, 60)
    local textH = math.max(labelSize, cdSize) + 6
    return math.max(36, icoHeight, textH)
end

local function EnsureRow(index)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, anchorFrame)
    row:SetSize(ANCHOR_WIDTH, 80)
    SetClickThrough(row)

    row.contentFrame = CreateFrame("Frame", nil, row)
    row.contentFrame:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.contentFrame:SetSize(520, 80)
    SetClickThrough(row.contentFrame)

    row.iconTex = row.contentFrame:CreateTexture(nil, "ARTWORK")
    row.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorderFrame = CreateFrame("Frame", nil, row.contentFrame, "BackdropTemplate")
    row.iconBorderFrame:Hide()

    row.labelFS = row.contentFrame:CreateFontString(nil, "OVERLAY")
    row.labelFS:SetFontObject(GameFontNormal)
    row.labelFS:SetJustifyH("CENTER")
    row.labelFS:SetJustifyV("MIDDLE")
    row.labelFS:SetWordWrap(false)
    if row.labelFS.SetNonSpaceWrap then
        row.labelFS:SetNonSpaceWrap(false)
    end

    row.cdFS = row.contentFrame:CreateFontString(nil, "OVERLAY")
    row.cdFS:SetFontObject(GameFontNormal)
    row.cdFS:SetJustifyH("LEFT")
    row.cdFS:SetJustifyV("MIDDLE")
    row.cdFS:SetWordWrap(false)
    if row.cdFS.SetNonSpaceWrap then
        row.cdFS:SetNonSpaceWrap(false)
    end

    row._showIcon = true
    row._numCache = nil
    row._sufCache = nil
    row._direct = false

    rows[index] = row
    return row
end

local function ApplyRowStyle(row, db, disableIconBorder)
    if not row then return end
    ApplyFont(row.labelFS, db.font_label or FALLBACK_DB.font_label, 46)
    ApplyFont(row.cdFS, db.font_cd or FALLBACK_DB.font_cd, 60)

    local lf = db.font_label or FALLBACK_DB.font_label
    local cf = db.font_cd or FALLBACK_DB.font_cd

    local iconDB = EnsureCountdownIconDB(db)
    local showIco = iconDB.showIcon ~= false
    local icoW = math.max(8, SafeNum(iconDB.width, SafeNum(db.iconSize, 25)))
    local icoH = math.max(8, SafeNum(iconDB.height, SafeNum(db.iconSize, 25)))
    row.iconTex:SetSize(icoW, icoH)
    row.iconTex:SetShown(false)
    row._showIcon = showIco
    row._iconReverse = iconDB.reverse == true
    row._showBorder = false
    ApplyHorizontalOffset(row.labelFS, SafeNum(lf.x, 0))
    ApplyHorizontalOffset(row.cdFS, SafeNum(cf.x, 0))
    ApplyVerticalOffset(row.labelFS, SafeNum(lf.y, 0))
    ApplyVerticalOffset(row.cdFS, SafeNum(cf.y, 0))

    row.iconTex:ClearAllPoints()
    row.labelFS:ClearAllPoints()
    row.cdFS:ClearAllPoints()
    row.iconBorderFrame:ClearAllPoints()
    row.contentFrame:SetSize(520, row:GetHeight())
    local sideGap = 2
    row.labelFS:SetPoint("CENTER", row.contentFrame, "CENTER", SafeNum(row.labelFS._xOffset, 0),
        SafeNum(row.labelFS._yOffset, 0))
    row.labelFS:SetWidth(0)
    row.cdFS:SetPoint("LEFT", row.labelFS, "RIGHT", sideGap + SafeNum(row.cdFS._xOffset, 0),
        SafeNum(row.cdFS._yOffset, 0))
    row.cdFS:SetWidth(0)
    if showIco then
        if row._iconReverse then
            row.iconTex:SetPoint("LEFT", row.cdFS, "RIGHT", sideGap + SafeNum(iconDB.x, 0), SafeNum(iconDB.y, 0))
        else
            row.iconTex:SetPoint("RIGHT", row.labelFS, "LEFT", -sideGap + SafeNum(iconDB.x, 0), SafeNum(iconDB.y, 0))
        end
    end
    local edgeTex = (disableIconBorder ~= true) and showIco and iconDB.showBorder ~= false and iconDB.borderTexture and
        iconDB.borderTexture ~= "None"
        and LSM and LSM:Fetch("border", iconDB.borderTexture) or nil
    if edgeTex then
        local pad = SafeNum(iconDB.borderPadding, 0)
        ApplyBackdropBorder(
            row.iconBorderFrame,
            row.iconTex,
            edgeTex,
            SafeNum(iconDB.borderSize, 1),
            pad,
            SafeNum(iconDB.borderColorR, 0),
            SafeNum(iconDB.borderColorG, 0),
            SafeNum(iconDB.borderColorB, 0),
            SafeNum(iconDB.borderColorA, 1),
            row:GetFrameLevel() + 3
        )
        row._showBorder = true
    else
        HideBackdropBorder(row.iconBorderFrame)
        row._showBorder = false
    end
    row.cdFS:Show()
end

local function ApplyRowColor(row, db, entryColor)
    if not row then return end
    if entryColor then
        if type(entryColor.GetRGBA) == "function" then
            row.labelFS:SetTextColor(entryColor:GetRGBA())
            row.cdFS:SetTextColor(entryColor:GetRGBA())
            return
        end
        if type(entryColor.GetRGB) == "function" then
            row.labelFS:SetTextColor(entryColor:GetRGB())
            row.cdFS:SetTextColor(entryColor:GetRGB())
            return
        end
        row.labelFS:SetTextColor(entryColor.r, entryColor.g, entryColor.b, entryColor.a or 1)
        row.cdFS:SetTextColor(entryColor.r, entryColor.g, entryColor.b, entryColor.a or 1)
        return
    end
    local lf = db.font_label or FALLBACK_DB.font_label
    local cf = db.font_cd or FALLBACK_DB.font_cd
    row.labelFS:SetTextColor(SafeNum(lf.r, 1), SafeNum(lf.g, 1), SafeNum(lf.b, 1), SafeNum(lf.a, 1))
    row.cdFS:SetTextColor(SafeNum(cf.r, 1), SafeNum(cf.g, 1), SafeNum(cf.b, 1), SafeNum(cf.a, 1))
end

local function HideUnusedRows(startIndex)
    for i = startIndex, #rows do
        local row = rows[i]
        if row then row:Hide() end
    end
end

RenderStack = function(forcedRemaining)
    if not anchorFrame then return end
    local db = DB() or FALLBACK_DB
    local count = #_entries
    if count <= 0 then
        HideUnusedRows(1)
        if not isPreviewing then
            anchorFrame:Hide()
            if updater then updater:Hide() end
        end
        return
    end

    local rowH = GetRowHeight(db)
    local stackGap = GetStackGap(db)
    local totalH = rowH * count + stackGap * math.max(0, count - 1)
    anchorFrame:SetHeight(totalH)

    local now = GetTime()
    for i = 1, count do
        local entry = _entries[i]
        local row = EnsureRow(i)
        row:SetSize(ANCHOR_WIDTH, rowH)
        local remaining = forcedRemaining or math.max(0, (entry.endTime or now) - now)
        local numStr = db.showDecimal and string.format("%.1f", remaining) or tostring(math.ceil(remaining))
        local rightText
        if entry.suf == nil then
            rightText = numStr
        else
            rightText = numStr .. entry.suf
        end
        ApplyRowStyle(row, db, entry.disableIconBorder == true)
        row.labelFS:SetText(entry.pre or "")
        row.cdFS:SetText(rightText or "")
        row.iconTex:SetTexture(entry.iconID)
        ApplyRowColor(row, db, entry.color)
        if entry.disableIconBorder == true then
            HideBackdropBorder(row.iconBorderFrame)
            row._showBorder = false
        end
        row.iconTex:SetShown(row._showIcon)
        row.iconBorderFrame:SetShown(row._showBorder and row._showIcon)

        row:ClearAllPoints()
        -- 最新一条放在最上方，后续项向下堆叠。
        row:SetPoint("CENTER", anchorFrame, "CENTER", 0, (count - i) * (rowH + stackGap))
        row:Show()
    end

    HideUnusedRows(count + 1)
    anchorFrame:Show()
end

-- =============================================================
-- 帧创建
-- =============================================================
local function CreateFrames()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()

    -- 唯一驱动帧
    updater = CreateFrame("Frame", nil, UIParent)
    updater:Hide()
    SetClickThrough(updater)
    updater:SetScript("OnUpdate", function(_, elapsed)
        if isPreviewing then return end
        _updateElapsed = _updateElapsed + (tonumber(elapsed) or 0)
        if _updateElapsed < UPDATE_INTERVAL then
            return
        end
        _updateElapsed = 0

        local now = GetTime()
        for i = #_entries, 1, -1 do
            if (_entries[i].endTime or 0) <= now then
                table.remove(_entries, i)
            end
        end
        RenderStack(nil)
        if #_entries <= 0 then
            updater:Hide()
        end
    end)
end

-- =============================================================
-- 模板拆分
-- =============================================================
SplitTemplate = function(template, spellName)
    if not template or template == "" then
        if type(spellName) == "string" then
            return spellName, ""
        end
        return "", ""
    end
    if type(spellName) == "string" then
        local s = template:gsub("%%s", spellName)
        local pre, suf = s:match("^(.-)%%t(.*)$")
        if pre then return pre, suf end
        return s, ""
    end
    local s = template:gsub("%%s", "")
    local pre, suf = s:match("^(.-)%%t(.*)$")
    if pre then return pre, suf end
    return s, ""
end

-- =============================================================
-- 停止
-- =============================================================
StopAll = function()
    if updater then updater:Hide() end
    for i = #_entries, 1, -1 do
        _entries[i] = nil
    end
    HideUnusedRows(1)
    if anchorFrame then anchorFrame:Hide() end
end

-- =============================================================
-- 刷新外观
-- =============================================================
local function RefreshStyle()
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
    if isPreviewing then
        RenderStack(3)
    else
        RenderStack(nil)
    end
end

-- =============================================================
-- 公开接口
-- =============================================================
function Countdown:Show(spec)
    local db = DB() or FALLBACK_DB
    if db.enabled == false then return end
    if not anchorFrame then CreateFrames() end
    if isPreviewing then return end
    local iconID = ResolveCountdownIconTexture(spec, db)

    local tmpl = (type(db.labelTemplate) == "string" and db.labelTemplate ~= "") and db.labelTemplate or
        FALLBACK_DB.labelTemplate
    local pre, suf
    if spec and spec.rawText == true then
        pre, suf = spec.displayName, ""
    elseif type(spec and spec.displayName) == "string" then
        pre, suf = SplitTemplate(tmpl, spec.displayName)
    else
        pre, suf = SplitTemplate(tmpl, nil)
    end
    local mechanicColor = ResolveCountdownTextColor(spec)

    _entrySeq = _entrySeq + 1
    local duration = math.max(0.1, SafeNum(spec and spec.duration, 5.0))
    local now = GetTime()
    local stackMax = GetStackMax(db)
    table.insert(_entries, 1, {
        id = _entrySeq,
        startTime = now,
        duration = duration,
        endTime = now + duration,
        pre = pre or "",
        suf = suf or "",
        iconID = iconID,
        color = mechanicColor,
        disableIconBorder = (spec and spec.disableIconBorder == true) or false,
    })
    while #_entries > stackMax do
        table.remove(_entries, #_entries)
    end

    RenderStack(nil)
    _updateElapsed = 0
    if updater then updater:Show() end
end

function Countdown:Stop()
    StopAll()
end

function Countdown:RefreshVisuals()
    if not anchorFrame then return end
    RefreshStyle()
    if isPreviewing then
        if updater then updater:Hide() end
    elseif #_entries > 0 then
        if updater then updater:Show() end
    end
end

function Countdown:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

-- =============================================================
-- 初始化
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateFrames()
        RefreshStyle()
    end)
end)
