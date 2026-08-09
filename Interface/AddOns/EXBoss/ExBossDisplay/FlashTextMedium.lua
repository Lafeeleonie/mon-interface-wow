---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/FlashTextMedium.lua
-- 中央文字公告（中）
--
-- 显示层只负责呈现：位置、字体、淡入淡出、血量曲线文字透明度。
-- 机制判断与 Boss 规则归属模块层 / 声明层。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local UnitHealthPercent = _G.UnitHealthPercent
local C_CurveUtil = _G.C_CurveUtil
local CreateColor = _G.CreateColor

ExBoss.UI.FlashTextMedium = ExBoss.UI.FlashTextMedium or {}
local FlashText = ExBoss.UI.FlashTextMedium
local MODULE_KEY = "ExBoss.FlashTextMedium"

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DB()
    if ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY)
        if ok and type(mdb) == "table" then return mdb end
    end
    local db = _G.ExBossDB
    return db and db.timer and db.timer.flashTextMedium
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
    if frame.SetMouseClickEnabled then pcall(frame.SetMouseClickEnabled, frame, false) end
    if frame.SetMouseMotionEnabled then pcall(frame.SetMouseMotionEnabled, frame, false) end
end

local FALLBACK_DB = {
    enabled = true,
    anchorX_1205 = 0,
    anchorY_1205 = 110,
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

local anchorFrame
local anchorController
local textFrame
local healthFrame
local healthTexts = {}
local isPreviewing = false
local _dir = 0
local _elapsed = 0
local _updateFrame
local _holdTimer
local _instantTimer
local EnsureAnchorController
local EnsureFrames
local StopFlash

local FADE_IN_TIME = 0.16
local FADE_OUT_TIME = 0.35
local COUNTDOWN_GAP = 6
local EDIT_FRAME_WIDTH = 300
local EDIT_FRAME_HEIGHT = 50

local function ApplyFont(fs, fontDB)
    if not fs then return end
    fontDB = fontDB or FALLBACK_DB.font_flash
    local StaticDB = ExwindTools.DB_Static
    if StaticDB and StaticDB.ApplyFont then
        StaticDB:ApplyFont(fs, fontDB)
        local fontFile = fs:GetFont()
        if fontFile then
            return
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = (LSM and fontDB.font and fontDB.font ~= "默认")
        and LSM:Fetch("font", fontDB.font)
        or (ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT)
    fs:SetFont(path, SafeNum(fontDB.size, 32), fontDB.outline or "OUTLINE")
    fs:SetTextColor(SafeNum(fontDB.r, 1), SafeNum(fontDB.g, 1), SafeNum(fontDB.b, 1), SafeNum(fontDB.a, 1))
    if fontDB.shadow then
        fs:SetShadowOffset(SafeNum(fontDB.shadowX, 2), SafeNum(fontDB.shadowY, -2))
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function CreateAlphaColor(fontDB, alpha)
    if not CreateColor then return nil end
    return CreateColor(
        SafeNum(fontDB and fontDB.r, 1),
        SafeNum(fontDB and fontDB.g, 1),
        SafeNum(fontDB and fontDB.b, 1),
        SafeNum(fontDB and fontDB.a, 1) * SafeNum(alpha, 0)
    )
end

local function BuildRangeCurve(minPct, maxPct, fontDB)
    if not C_CurveUtil or not CreateColor then
        return nil
    end
    local low = math.max(0, SafeNum(minPct, 0) / 100)
    local high = math.min(1, SafeNum(maxPct, 0) / 100)
    if high <= low then
        return nil
    end

    local hidden = CreateAlphaColor(fontDB, 0)
    local shown = CreateAlphaColor(fontDB, 1)
    if not hidden or not shown then
        return nil
    end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetPoints({
        { x = 0,    y = hidden },
        { x = low,  y = hidden },
        { x = low,  y = shown },
        { x = high, y = shown },
        { x = high, y = hidden },
        { x = 1,    y = hidden },
    })
    return curve
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_FlashTextMediumAnchor",
        title = "文字公告(中)",
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
            if not EnsureFrames() then
                return
            end
            isPreviewing = anchorController.editActive == true and anchorController.editVisible == true
            if isPreviewing then
                anchorFrame:Show()
                if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
                if anchorFrame.EditLabel then anchorFrame.EditLabel:Show() end
                if anchorFrame.CenterMarker then anchorFrame.CenterMarker:Show() end
                StopFlash()
                FlashText:Show({ text = IsNonChineseLocale() and "Medium Alert Sample" or "中字提示示例", duration = 999 })
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

EnsureFrames = function()
    if anchorFrame then return true end

    local db = DB() or FALLBACK_DB
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(EDIT_FRAME_WIDTH, EDIT_FRAME_HEIGHT)

    local editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0.55, 1, 0.20)
    editOverlay:Hide()
    anchorFrame.EditOverlay = editOverlay

    local editLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editLabel:SetPoint("TOP", anchorFrame, "TOP", 0, -4)
    editLabel:SetText("|cff55bbff[文字公告(中)]|r")
    editLabel:Hide()
    anchorFrame.EditLabel = editLabel

    local centerMarker = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    centerMarker:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
    centerMarker:SetJustifyH("CENTER")
    centerMarker:SetJustifyV("MIDDLE")
    centerMarker:SetWordWrap(false)
    centerMarker:SetText("|cff55bbff◎|r")
    centerMarker:Hide()
    anchorFrame.CenterMarker = centerMarker

    textFrame = CreateFrame("Frame", nil, anchorFrame)
    textFrame:SetAllPoints(anchorFrame)
    textFrame:SetFrameStrata("DIALOG")
    textFrame:SetAlpha(0)
    textFrame:Hide()
    SetClickThrough(textFrame)

    local fs = textFrame:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    textFrame.Text = fs
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

    healthFrame = CreateFrame("Frame", nil, anchorFrame)
    healthFrame:SetAllPoints(anchorFrame)
    healthFrame:SetFrameStrata("DIALOG")
    healthFrame:Show()
    SetClickThrough(healthFrame)

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
                _dir = 0
                _elapsed = 0
                local db2 = DB() or FALLBACK_DB
                local dur = SafeNum(db2._overrideDuration, SafeNum(db2.flashDuration, 1.5))
                db2._overrideDuration = nil
                local hold = math.max(0.05, dur - FADE_IN_TIME - FADE_OUT_TIME)
                if _holdTimer then _holdTimer:Cancel() end
                _holdTimer = C_Timer.NewTimer(hold, function()
                    if textFrame:IsShown() and not isPreviewing then
                        _dir = -1
                        _elapsed = 0
                        if _updateFrame then _updateFrame:Show() end
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
    return true
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

local function HasVisibleHealthEntries()
    for i = 1, #healthTexts do
        local fs = healthTexts[i]
        if fs and fs.GetText and tostring(fs:GetText() or "") ~= "" then
            return true
        end
    end
    return false
end

local function HideAnchorIfIdle()
    if not anchorFrame or isPreviewing then
        return
    end
    if textFrame and textFrame.IsShown and textFrame:IsShown() then
        return
    end
    if HasVisibleHealthEntries() then
        return
    end
    anchorFrame:Hide()
end

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

local function EnsureHealthText(index)
    if not EnsureFrames() then return nil end
    local fs = healthTexts[index]
    if fs then return fs end
    fs = healthFrame:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    healthTexts[index] = fs
    return fs
end

local function HideHealthTexts(fromIndex)
    for i = fromIndex, #healthTexts do
        local fs = healthTexts[i]
        if fs then
            fs:SetText("")
            fs:SetTextColor(1, 1, 1, 0)
        end
    end
end

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
    for _, fs in ipairs(healthTexts) do
        ApplyFont(fs, db.font_flash or FALLBACK_DB.font_flash)
    end
end

local function SetEditMode(enabled)
    if not EnsureFrames() then return end
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

function FlashText:Show(payload, text, duration)
    local db = DB() or FALLBACK_DB
    if db.enabled == false then
        return
    end
    if not EnsureFrames() then return end
    if isPreviewing and not (type(payload) == "table" and payload.duration == 999) then
        return
    end

    local displayText = text
    local displayDuration = duration
    local color = nil
    if type(payload) == "table" and text == nil then
        displayText = payload.text
        displayDuration = payload.duration
        color = payload.color
    elseif type(payload) == "table" then
        color = payload.flashTextColor or payload.color
    end

    if type(payload) == "table" and (payload.noAnimation == true or payload.instant == true) then
        _dir = 0
        if _holdTimer then
            _holdTimer:Cancel(); _holdTimer = nil
        end
        if _instantTimer then
            _instantTimer:Cancel(); _instantTimer = nil
        end
        if textFrame and textFrame.Text then
            ApplyFont(textFrame.Text, db.font_flash or FALLBACK_DB.font_flash)
            if type(color) == "table" then
                local r, g, b = tonumber(color.r), tonumber(color.g), tonumber(color.b)
                if r and g and b then
                    textFrame.Text:SetTextColor(r, g, b, tonumber(color.a) or 1)
                end
            end
            textFrame.Text:SetText(tostring(displayText or ""))
            if textFrame.Text.Show then textFrame.Text:Show() end
        end
        HideCountdownText()
        anchorFrame:Show()
        textFrame:SetAlpha(1)
        textFrame:Show()
        if _updateFrame then _updateFrame:Hide() end
        local dur = tonumber(displayDuration) or SafeNum(db.flashDuration, 1.5)
        if _instantTimer then _instantTimer:Cancel() end
        _instantTimer = C_Timer.NewTimer(math.max(0.05, dur), function()
            _instantTimer = nil
            if textFrame then
                textFrame:SetAlpha(0)
                textFrame:Hide()
                if textFrame.Text then textFrame.Text:SetText("") end
            end
            HideAnchorIfIdle()
        end)
        return
    end

    StopFlash()

    if textFrame and textFrame.Text then
        ApplyFont(textFrame.Text, db.font_flash or FALLBACK_DB.font_flash)
        if type(color) == "table" then
            local r, g, b = tonumber(color.r), tonumber(color.g), tonumber(color.b)
            if r and g and b then
                textFrame.Text:SetTextColor(r, g, b, tonumber(color.a) or 1)
            end
        end
        textFrame.Text:SetText(tostring(displayText or ""))
        if textFrame.Text.Show then textFrame.Text:Show() end
    end
    HideCountdownText()

    if displayDuration then
        db._overrideDuration = displayDuration
    end
    anchorFrame:Show()
    textFrame:SetAlpha(0)
    textFrame:Show()
    _dir = 1
    _elapsed = 0
    if _updateFrame then _updateFrame:Show() end
end

function FlashText:ShowCountdown(payload)
    local db = DB() or FALLBACK_DB
    if db.enabled == false then
        return
    end
    if not EnsureFrames() then return end
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
    local height = SafeNum(fontDB.size, 32) * 1.4
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

    local dur = tonumber(type(payload) == "table" and payload.duration) or SafeNum(db.flashDuration, 1.5)
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
        HideAnchorIfIdle()
    end)
end

function FlashText:ShowHealthEntries(entries)
    if not EnsureFrames() then return end
    local db = DB() or FALLBACK_DB
    if db.enabled == false or type(entries) ~= "table" then
        HideHealthTexts(1)
        HideAnchorIfIdle()
        return
    end

    anchorFrame:Show()

    local fontDB = db.font_flash or FALLBACK_DB.font_flash
    for i = 1, #entries do
        local entry = entries[i]
        local fs = EnsureHealthText(i)
        if fs then
            ApplyFont(fs, fontDB)
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", healthFrame, "CENTER", 0, 0)
            fs:SetText(tostring(entry.text or ""))
            fs:SetTextColor(1, 1, 1, 0)
        end

        local curve = BuildRangeCurve(entry.min, entry.max, fontDB)
        if fs and curve and UnitHealthPercent and UnitExists(entry.unit) then
            local color = UnitHealthPercent(entry.unit, true, curve)
            if color and color.GetRGBA then
                fs:SetTextColor(color:GetRGBA())
            end
        end
    end

    HideHealthTexts(#entries + 1)
end

function FlashText:ClearHealthEntries()
    HideHealthTexts(1)
    HideAnchorIfIdle()
end

function FlashText:Stop()
    StopFlash()
    self:ClearHealthEntries()
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
    HideAnchorIfIdle()
end

function FlashText:RefreshVisuals()
    if not EnsureFrames() then return end
    RefreshStyle()
    if isPreviewing then
        anchorFrame:Show()
    end
end

function FlashText:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        if EnsureFrames() then
            RefreshStyle()
        end
    end)
end)
