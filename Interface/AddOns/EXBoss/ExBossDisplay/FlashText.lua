---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/FlashText.lua
-- 屏幕中央文字公告（技能名淡入 → 停留 → 淡出）
--
-- 公开接口：
--   ExBoss.UI.FlashText:Show(timer, text, duration)
--   ExBoss.UI.FlashText:RefreshVisuals()
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.FlashText = ExBoss.UI.FlashText or {}
local FlashText     = ExBoss.UI.FlashText
local MODULE_KEY    = "ExBoss.FlashText"
local L             = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DebugFlash(text)
end

-- =============================================================
-- DB
-- =============================================================
local function DB()
    if ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY)
        if ok and type(mdb) == "table" then return mdb end
    end
    local db = _G.ExBossDB
    return db and db.timer and db.timer.flashText
end

local function SafeNum(v, def)
    return tonumber(v) or def
end

local function SafeTextWidth(fs)
    if not fs or not fs.GetStringWidth then
        return 0
    end
    return tonumber(fs:GetStringWidth()) or 0
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

local FALLBACK_DB       = {
    enabled       = true,
    anchorX_1205  = 0,
    anchorY_1205  = 200,
    flashDuration = 2.5,
    font_flash    = {
        font = "默认",
        size = 46,
        outline = "OUTLINE",
        r = 1.0,
        g = 1.0,
        b = 1.0,
        a = 1.0,
        shadow = true,
        shadowX = 2,
        shadowY = -2,
        x = 0,
        y = 0,
    },
}

-- =============================================================
-- 帧结构
-- =============================================================
local anchorFrame       = nil
local anchorController  = nil
local textFrame         = nil
local isPreviewing      = false
local EnsureAnchorController
local CreateFrames
local StopFlash

-- 淡入淡出状态
local _dir              = 0 -- 0=停止 1=淡入 -1=淡出
local _elapsed          = 0
local _holdTime         = 0
local _updateFrame      = nil
local _holdTimer        = nil
local _instantTimer     = nil

local FADE_IN_TIME      = 0.20
local FADE_OUT_TIME     = 0.45
local COUNTDOWN_GAP     = 8
local EDIT_FRAME_WIDTH  = 300
local EDIT_FRAME_HEIGHT = 80

-- =============================================================
-- ApplyFont（与 Countdown.lua 相同的兜底逻辑）
-- =============================================================
local function ApplyFont(fs, fontDB)
    if not fs or not fontDB then return end
    local StaticDB = ExwindTools.DB_Static
    if StaticDB and StaticDB.ApplyFont then
        StaticDB:ApplyFont(fs, fontDB)
        local fontFile = fs:GetFont()
        if fontFile then
            return
        end
    end
    local LSM     = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path    = (LSM and fontDB.font and fontDB.font ~= "默认")
        and LSM:Fetch("font", fontDB.font)
        or (ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT)
    local size    = SafeNum(fontDB.size, 46)
    local outline = fontDB.outline or "OUTLINE"
    fs:SetFont(path, size, outline)
    fs:SetTextColor(
        SafeNum(fontDB.r, 1),
        SafeNum(fontDB.g, 1),
        SafeNum(fontDB.b, 1),
        SafeNum(fontDB.a, 1)
    )
    if fontDB.shadow then
        fs:SetShadowOffset(SafeNum(fontDB.shadowX, 2), SafeNum(fontDB.shadowY, -2))
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- =============================================================
-- 帧创建
-- =============================================================
EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_FlashTextAnchor",
        title = L["文字公告"],
        getDB = function()
            return DB() or FALLBACK_DB
        end,
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
        widgetRanges = {
            anchorX_1205 = { min = -1000, max = 1000, step = 5 },
            anchorY_1205 = { min = -600, max = 600, step = 5 },
        },
        initialWidth = EDIT_FRAME_WIDTH,
        initialHeight = EDIT_FRAME_HEIGHT,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
        onEditModeChanged = function()
            if not anchorFrame then
                CreateFrames()
            end
            isPreviewing = anchorController.editActive == true and anchorController.editVisible == true
            if isPreviewing then
                anchorFrame:Show()
                if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
                if anchorFrame.EditLabel then anchorFrame.EditLabel:Show() end
                if anchorFrame.CenterMarker then anchorFrame.CenterMarker:Show() end
                StopFlash()
                if textFrame then
                    if textFrame.Text then
                        textFrame.Text:SetText(IsNonChineseLocale() and "Sample Spell Name" or "技能名称示例")
                    end
                    textFrame:SetAlpha(0.9)
                    textFrame:Show()
                end
            else
                if anchorFrame and anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
                if anchorFrame and anchorFrame.EditLabel then anchorFrame.EditLabel:Hide() end
                if anchorFrame and anchorFrame.CenterMarker then anchorFrame.CenterMarker:Hide() end
                StopFlash()
                if anchorFrame then
                    anchorFrame:Hide()
                end
            end
        end,
    })

    return anchorController
end

CreateFrames = function()
    if anchorFrame then return end
    local db = DB() or FALLBACK_DB
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(EDIT_FRAME_WIDTH, EDIT_FRAME_HEIGHT)

    local editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0.8, 0, 0.20)
    editOverlay:Hide()
    anchorFrame.EditOverlay = editOverlay

    local editLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editLabel:SetPoint("TOP", anchorFrame, "TOP", 0, -4)
    editLabel:SetText("|cff00ff00[文字公告]|r")
    editLabel:Hide()
    anchorFrame.EditLabel = editLabel

    local centerMarker = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    centerMarker:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
    centerMarker:SetJustifyH("CENTER")
    centerMarker:SetJustifyV("MIDDLE")
    centerMarker:SetWordWrap(false)
    centerMarker:SetText("|cff00ff00◎|r")
    centerMarker:Hide()
    anchorFrame.CenterMarker = centerMarker

    -- 文字帧
    textFrame = CreateFrame("Frame", nil, anchorFrame)
    textFrame:SetAllPoints(anchorFrame)
    textFrame:SetFrameStrata("DIALOG")
    SetClickThrough(textFrame)

    local fs = textFrame:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    textFrame.Text = fs
    textFrame:SetAlpha(0)
    textFrame:Hide()

    ApplyFont(fs, db.font_flash or FALLBACK_DB.font_flash)

    local countdownGroup = CreateFrame("Frame", nil, textFrame)
    countdownGroup:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    countdownGroup:SetSize(1, 1)
    countdownGroup:Hide()
    SetClickThrough(countdownGroup)
    textFrame.CountdownGroup = countdownGroup

    local countdownLabel = countdownGroup:CreateFontString(nil, "OVERLAY")
    countdownLabel:SetJustifyH("CENTER")
    countdownLabel:SetJustifyV("MIDDLE")
    countdownLabel:SetPoint("CENTER", countdownGroup, "CENTER", 0, 0)
    countdownLabel:Hide()
    textFrame.CountdownLabel = countdownLabel
    ApplyFont(countdownLabel, db.font_flash or FALLBACK_DB.font_flash)
    countdownLabel:SetText("")

    local countdownTime = countdownGroup:CreateFontString(nil, "OVERLAY")
    countdownTime:SetJustifyH("LEFT")
    countdownTime:SetJustifyV("MIDDLE")
    countdownTime:SetPoint("LEFT", countdownLabel, "RIGHT", COUNTDOWN_GAP, 0)
    countdownTime:Hide()
    textFrame.CountdownTime = countdownTime
    ApplyFont(countdownTime, db.font_flash or FALLBACK_DB.font_flash)
    countdownTime:SetText("")

    -- OnUpdate 帧（淡入淡出驱动）
    _updateFrame = CreateFrame("Frame", nil, anchorFrame)
    _updateFrame:Hide()
    SetClickThrough(_updateFrame)
    _updateFrame:SetScript("OnUpdate", function(_, elapsed)
        if _dir == 0 then return end
        _elapsed = _elapsed + elapsed
        if _dir == 1 then
            local a = math.min(1, _elapsed / FADE_IN_TIME)
            textFrame:SetAlpha(a)
            if a >= 1 then
                _dir                  = 0
                _elapsed              = 0
                -- 安排淡出
                local db2             = DB() or FALLBACK_DB
                local dur             = SafeNum(db2._overrideDuration, SafeNum(db2.flashDuration, 2.5))
                db2._overrideDuration = nil
                local hold            = math.max(0.05, dur - FADE_IN_TIME - FADE_OUT_TIME)
                if _holdTimer then _holdTimer:Cancel() end
                _holdTimer = C_Timer.NewTimer(hold, function()
                    if textFrame:IsShown() and not isPreviewing then
                        _dir = -1
                        _elapsed = 0
                    end
                end)
            end
        elseif _dir == -1 then
            local a = math.max(0, 1 - _elapsed / FADE_OUT_TIME)
            textFrame:SetAlpha(a)
            if a <= 0 then
                _dir = 0
                textFrame:Hide()
                _updateFrame:Hide()
                if textFrame.Text then textFrame.Text:SetText("") end
            end
        end
    end)
end

local function HideCountdownText()
    if not textFrame then return end
    if textFrame.CountdownGroup then
        textFrame.CountdownGroup:Hide()
    end
    if textFrame.CountdownLabel then
        textFrame.CountdownLabel:SetText("")
        textFrame.CountdownLabel:Hide()
    end
    if textFrame.CountdownTime then
        textFrame.CountdownTime:SetText("")
        textFrame.CountdownTime:Hide()
    end
end

-- =============================================================
-- 内部停止
-- =============================================================
StopFlash = function()
    _dir = 0
    if _holdTimer then
        _holdTimer:Cancel(); _holdTimer = nil
    end
    if _instantTimer then
        _instantTimer:Cancel(); _instantTimer = nil
    end
    if textFrame then
        textFrame:SetAlpha(0)
        textFrame:Hide()
        if textFrame.Text then textFrame.Text:SetText("") end
        HideCountdownText()
    end
    if _updateFrame then _updateFrame:Hide() end
end

-- =============================================================
-- 编辑模式
-- =============================================================
local function SetEditMode(enabled)
    if not anchorFrame then CreateFrames() end
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

-- =============================================================
-- 刷新外观
-- =============================================================
local function RefreshStyle()
    if not anchorFrame then return end
    local db = DB() or FALLBACK_DB
    anchorFrame:SetSize(EDIT_FRAME_WIDTH, EDIT_FRAME_HEIGHT)
    EnsureAnchorController():ApplyPosition()
    if textFrame and textFrame.Text then
        ApplyFont(textFrame.Text, db.font_flash or FALLBACK_DB.font_flash)
    end
    if textFrame and textFrame.CountdownLabel then
        ApplyFont(textFrame.CountdownLabel, db.font_flash or FALLBACK_DB.font_flash)
    end
    if textFrame and textFrame.CountdownTime then
        ApplyFont(textFrame.CountdownTime, db.font_flash or FALLBACK_DB.font_flash)
    end
end

-- =============================================================
-- 公开接口
-- =============================================================
function FlashText:Show(timer, text, duration)
    local db = DB() or FALLBACK_DB
    if db.enabled == false then
        return
    end
    if not anchorFrame then CreateFrames() end
    if isPreviewing then
        return
    end

    if type(timer) == "table" and (timer.noAnimation == true or timer.instant == true) then
        _dir = 0
        if _holdTimer then
            _holdTimer:Cancel(); _holdTimer = nil
        end
        if _instantTimer then
            _instantTimer:Cancel(); _instantTimer = nil
        end
        if textFrame and textFrame.Text then
            ApplyFont(textFrame.Text, db.font_flash or FALLBACK_DB.font_flash)
            if type(timer) == "table" and (type(timer.flashTextColor) == "table" or type(timer.color) == "table") then
                local c = timer.flashTextColor or timer.color
                local r = tonumber(c.r)
                local g = tonumber(c.g)
                local b = tonumber(c.b)
                if r and g and b then
                    textFrame.Text:SetTextColor(r, g, b, tonumber(c.a) or 1)
                end
            end
            textFrame.Text:SetText(text or "")
            if textFrame.Text.Show then textFrame.Text:Show() end
        end
        HideCountdownText()
        anchorFrame:Show()
        textFrame:SetAlpha(1)
        textFrame:Show()
        if _updateFrame then _updateFrame:Hide() end
        local dur = tonumber(duration) or SafeNum(db.flashDuration, 2.5)
        if _instantTimer then _instantTimer:Cancel() end
        _instantTimer = C_Timer.NewTimer(math.max(0.05, dur), function()
            _instantTimer = nil
            if textFrame then
                textFrame:SetAlpha(0)
                textFrame:Hide()
                if textFrame.Text then textFrame.Text:SetText("") end
            end
            if anchorFrame and not isPreviewing then
                anchorFrame:Hide()
            end
        end)
        return
    end

    StopFlash()

    -- 每次显示先恢复基础字体样式，再按事件覆盖颜色染色
    if textFrame and textFrame.Text then
        ApplyFont(textFrame.Text, db.font_flash or FALLBACK_DB.font_flash)
        if type(timer) == "table" and (type(timer.flashTextColor) == "table" or type(timer.color) == "table") then
            local c = timer.flashTextColor or timer.color
            local r = tonumber(c.r)
            local g = tonumber(c.g)
            local b = tonumber(c.b)
            if r and g and b then
                textFrame.Text:SetTextColor(r, g, b, tonumber(c.a) or 1)
            end
        end
    end

    if textFrame and textFrame.Text then
        textFrame.Text:SetText(text or "")
        if textFrame.Text.Show then textFrame.Text:Show() end
    end
    HideCountdownText()

    -- 临时覆盖持续时间
    if duration then
        local db2 = DB() or FALLBACK_DB
        db2._overrideDuration = duration
    end
    anchorFrame:Show()
    textFrame:SetAlpha(0)
    textFrame:Show()
    _dir     = 1
    _elapsed = 0
    if _updateFrame then _updateFrame:Show() end
end

function FlashText:ShowCountdown(payload)
    local db = DB() or FALLBACK_DB
    if db.enabled == false then
        return
    end
    if not anchorFrame then CreateFrames() end
    if isPreviewing then
        return
    end

    _dir = 0
    if _holdTimer then
        _holdTimer:Cancel(); _holdTimer = nil
    end
    if _instantTimer then
        _instantTimer:Cancel(); _instantTimer = nil
    end

    local labelText = tostring(type(payload) == "table" and payload.label or "")
    local timeText = tostring(type(payload) == "table" and payload.time or "")
    local timeWidthText = tostring(type(payload) == "table" and payload.timeWidthText or "")
    local suffixText = tostring(type(payload) == "table" and payload.suffix or "")
    local color = type(payload) == "table" and payload.color or nil

    if textFrame.Text then
        textFrame.Text:SetText("")
        if textFrame.Text.Hide then textFrame.Text:Hide() end
    end

    local fontDB = db.font_flash or FALLBACK_DB.font_flash
    local group = textFrame.CountdownGroup
    local label = textFrame.CountdownLabel
    local time = textFrame.CountdownTime
    ApplyFont(label, fontDB)
    ApplyFont(time, fontDB)
    if type(color) == "table" then
        local r, g, b = tonumber(color.r), tonumber(color.g), tonumber(color.b)
        if r and g and b then
            label:SetTextColor(r, g, b, tonumber(color.a) or 1)
            time:SetTextColor(r, g, b, tonumber(color.a) or 1)
        end
    end
    label:ClearAllPoints()
    label:SetPoint("CENTER", group, "CENTER", 0, 0)
    time:ClearAllPoints()
    time:SetPoint("LEFT", label, "RIGHT", COUNTDOWN_GAP, 0)
    label:SetText(labelText)
    time:SetText(timeText .. suffixText)
    local timeWidthSample = timeWidthText ~= "" and (timeWidthText .. suffixText) or (timeText .. suffixText)
    local currentTimeWidth = SafeTextWidth(time)
    time:SetText(timeWidthSample)
    local fixedTimeWidth = math.max(currentTimeWidth, SafeTextWidth(time))
    time:SetText(timeText .. suffixText)
    time:SetWidth(fixedTimeWidth)
    local height = SafeNum(fontDB.size, 46) * 1.4
    group:ClearAllPoints()
    group:SetAllPoints(textFrame)
    group:SetHeight(math.max(1, height))
    group:Show()
    label:Show()
    time:Show()

    anchorFrame:Show()
    textFrame:SetAlpha(1)
    textFrame:Show()
    if _updateFrame then _updateFrame:Hide() end

    local dur = tonumber(type(payload) == "table" and payload.duration) or SafeNum(db.flashDuration, 2.5)
    _instantTimer = C_Timer.NewTimer(math.max(0.05, dur), function()
        _instantTimer = nil
        if textFrame then
            textFrame:SetAlpha(0)
            textFrame:Hide()
            if textFrame.Text then
                textFrame.Text:SetText("")
                if textFrame.Text.Show then textFrame.Text:Show() end
            end
            HideCountdownText()
        end
        if anchorFrame and not isPreviewing then
            anchorFrame:Hide()
        end
    end)
end

function FlashText:Stop()
    StopFlash()
end

function FlashText:StopCountdown()
    if _instantTimer then
        _instantTimer:Cancel(); _instantTimer = nil
    end
    if textFrame then
        HideCountdownText()
        if textFrame.Text then
            textFrame.Text:SetText("")
            if textFrame.Text.Show then textFrame.Text:Show() end
        end
        textFrame:SetAlpha(0)
        textFrame:Hide()
    end
    if anchorFrame and not isPreviewing then
        anchorFrame:Hide()
    end
end

function FlashText:RefreshVisuals()
    RefreshStyle()
    if isPreviewing and textFrame then
        anchorFrame:Show()
        textFrame:SetAlpha(0.9)
        textFrame:Show()
    end
end

function FlashText:StartFramePicker()
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
