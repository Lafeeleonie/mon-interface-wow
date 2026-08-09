---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/CastProgressBar.lua
-- 圆环同源施法进度条
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.CastProgressBar = ExBoss.UI.CastProgressBar or {}
local CastBar = ExBoss.UI.CastProgressBar
local BorderUtil = ExBoss.BorderUtil
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local MODULE_KEY = "ExBoss.CastProgressBar"
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end

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

local CAST_CHECK_MARGIN = 0.1
local CAST_CHECK_GOOD = { r = 0.10, g = 0.95, b = 0.20 }
local CAST_CHECK_BAD = { r = 1.00, g = 0.12, b = 0.08 }

local anchorFrame
local anchorController
local editOverlay
local editLabel
local isEditMode = false
local eventFrame
local rows = {}
local activeSlots = {}
local EnsureAnchorController
local Ensure
local ShowStaticEditPreview

local function IsDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DebugPrint(msg)
    if not IsDebugEnabled() then
        return
    end
    if ExBoss and ExBoss.Print and ExBoss.Print.Say then
        ExBoss.Print.Say("[CastBarDebug] " .. tostring(msg or ""))
    else
        print("|cff00ffff<EXBOSS>|r [CastBarDebug] " .. tostring(msg or ""))
    end
end

local function DebugDescribePoint(frameObj)
    if not frameObj then
        return "point=nil"
    end
    local point, _, relativePoint, x, y = frameObj:GetPoint(1)
    return string.format("point=%s rel=%s x=%s y=%s",
        tostring(point or "nil"),
        tostring(relativePoint or "nil"),
        tostring(x or "nil"),
        tostring(y or "nil"))
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[DeepCopy(k)] = DeepCopy(v)
    end
    return out
end

local function NormalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    unit = tostring(unit):lower()
    if unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return id
end

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then n = tonumber(def) end
    if n == nil then n = 1 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

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

local function SetClickThrough(obj)
    if not obj then return end
    obj:EnableMouse(false)
    if obj.SetMouseClickEnabled then pcall(obj.SetMouseClickEnabled, obj, false) end
    if obj.SetMouseMotionEnabled then pcall(obj.SetMouseMotionEnabled, obj, false) end
end

local function EnsurePersistentDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.castProgressBar = ExBossDB.timer.castProgressBar or {}
    ApplyDefaults(ExBossDB.timer.castProgressBar, DEFAULTS)
    return ExBossDB.timer.castProgressBar
end

local function DB()
    if ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY, DEFAULTS)
        if ok and type(mdb) == "table" then
            ApplyDefaults(mdb, DEFAULTS)
            local exdb = EnsurePersistentDB()
            ApplyDefaults(exdb, mdb)
            return mdb
        end
    end

    local exdb = EnsurePersistentDB()
    return exdb
end

local function SavePosition(anchorX, anchorY)
    anchorX = math.floor(tonumber(anchorX) or DEFAULTS.anchorX)
    anchorY = math.floor(tonumber(anchorY) or DEFAULTS.anchorY)

    local mdb = DB()
    if type(mdb) == "table" then
        mdb.anchorX = anchorX
        mdb.anchorY = anchorY
    end

    local exdb = EnsurePersistentDB()
    if type(exdb) == "table" then
        if type(mdb) == "table" then
            for key, value in pairs(mdb) do
                exdb[key] = DeepCopy(value)
            end
        end
        exdb.anchorX = anchorX
        exdb.anchorY = anchorY
    end

    DebugPrint(string.format("SavePosition anchorX=%d anchorY=%d", anchorX, anchorY))
end

local function FormatTime(secs)
    secs = math.max(0, tonumber(secs) or 0)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    end
    if secs >= 10 then
        return string.format("%.0f", secs)
    end
    return string.format("%.1f", secs)
end

local function GetPlayerCastEndAt()
    local now = GetTime()
    if UnitCastingInfo then
        local ok, _name, _text, _texture, _startTimeMS, endTimeMS = pcall(UnitCastingInfo, "player")
        local endAt = ok and tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then return endAt end
    end
    if UnitChannelInfo then
        local ok, _name, _text, _texture, _startTimeMS, endTimeMS = pcall(UnitChannelInfo, "player")
        local endAt = ok and tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then return endAt end
    end
    return nil
end

local function GetConfiguredMaxBars(db)
    local n = math.floor(SafeNum(type(db) == "table" and db.maxBars, DEFAULTS.maxBars) or DEFAULTS.maxBars)
    if n < 1 then n = 1 end
    if n > 3 then n = 3 end
    return n
end

local function GetConfiguredSpacing(db)
    local spacing = SafeNum(type(db) == "table" and db.spacing, DEFAULTS.spacing)
    if spacing < 0 then spacing = 0 end
    return spacing
end

local function GetGrowDir(db)
    local dir = tostring(type(db) == "table" and db.growDir or DEFAULTS.growDir)
    if dir ~= "UP" and dir ~= "DOWN" then
        dir = DEFAULTS.growDir
    end
    return dir
end

local function IsBadCheckColor(color)
    return type(color) == "table"
        and color.r == CAST_CHECK_BAD.r
        and color.g == CAST_CHECK_BAD.g
        and color.b == CAST_CHECK_BAD.b
end

local function ResolveCastCheckColor(slot)
    local castEndAt = GetPlayerCastEndAt()
    local state = type(slot) == "table" and slot.state or nil
    local barEndAt = state and tonumber(state.endAt) or nil
    if castEndAt and barEndAt and castEndAt > (barEndAt - CAST_CHECK_MARGIN) then
        return CAST_CHECK_BAD
    end
    return CAST_CHECK_GOOD
end

local function GetNormalBarColor(db)
    local group = type(db) == "table" and type(db.timerBarGroup) == "table" and db.timerBarGroup or DEFAULTS.timerBarGroup
    return Clamp01(group.barColorR, DEFAULTS.timerBarGroup.barColorR),
           Clamp01(group.barColorG, DEFAULTS.timerBarGroup.barColorG),
           Clamp01(group.barColorB, DEFAULTS.timerBarGroup.barColorB),
           Clamp01(group.barColorA, DEFAULTS.timerBarGroup.barColorA)
end

local function ResolveSlotActiveColor(slot, db)
    if type(slot) == "table" and type(slot.state) == "table" and slot.state.castCheckEnabled == true then
        local c = ResolveCastCheckColor(slot)
        if IsBadCheckColor(c) then
            return c.r, c.g, c.b, 1
        end
        return CAST_CHECK_GOOD.r, CAST_CHECK_GOOD.g, CAST_CHECK_GOOD.b, 1
    end
    return GetNormalBarColor(db)
end

local function ApplySlotActiveColor(slot)
    if not (slot and slot.bar) then return end
    local r, g, b, a = ResolveSlotActiveColor(slot, DB())
    if slot.bar.SetStatusBarColor then
        slot.bar:SetStatusBarColor(r, g, b, a)
    end
    local tex = slot.bar.GetStatusBarTexture and slot.bar:GetStatusBarTexture() or nil
    if tex and tex.SetVertexColor then
        tex:SetVertexColor(r, g, b, a)
    end
end

local function HasActiveCastCheckSlots()
    for i = 1, #activeSlots do
        local slot = activeSlots[i]
        if slot and type(slot.state) == "table" and slot.state.castCheckEnabled == true then
            return true
        end
    end
    return false
end

local function EnsureEventFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, _event, unit)
        if unit ~= "player" then return end
        for i = 1, #activeSlots do
            local slot = activeSlots[i]
            if slot and type(slot.state) == "table" and slot.state.castCheckEnabled == true then
                ApplySlotActiveColor(slot)
            end
        end
    end)
    return eventFrame
end

local function SetCastCheckEventsEnabled(enabled)
    local ef = EnsureEventFrame()
    ef:UnregisterAllEvents()
    if enabled ~= true then return end
    ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

local function RefreshCastCheckEventState()
    SetCastCheckEventsEnabled(HasActiveCastCheckSlots())
end

local function ResolveMode(phase, db)
    if type(phase) == "table" and type(phase.barMode) == "string" then
        return phase.barMode
    end
    local castKind = type(phase) == "table" and tostring(phase.castKind or "") or ""
    local defaultMode = castKind == "channel" and DEFAULTS.channelFillModeV2 or DEFAULTS.castFillMode
    local mode = castKind == "channel" and db.channelFillModeV2 or db.castFillMode
    mode = tostring(mode or defaultMode)
    if mode ~= "ltr_fill" and mode ~= "ltr_decay" and mode ~= "rtl_fill" and mode ~= "rtl_decay" then
        mode = defaultMode
    end
    return mode
end

local function IsReverseMode(mode)
    return mode == "rtl_fill" or mode == "rtl_decay"
end

local function ResolveValue(duration, elapsed, mode)
    if mode == "ltr_fill" or mode == "rtl_fill" then
        return math.max(0, math.min(duration, elapsed))
    end
    return math.max(0, math.min(duration, duration - elapsed))
end

local function ResolveDisplayName(entry)
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    local name = type(entry) == "table" and entry.displayName or nil
    local progressName = type(entry) == "table" and entry.progressDisplayName or nil
    local rename = type(entry) == "table" and entry.castBarRenameText or nil
    if type(entry) == "table" and entry.castBarRenameEnabled == true and type(rename) == "string" and rename ~= "" then
        return rename
    end
    if type(entry) == "table" and entry.preferSpellName == true then
        if type(progressName) == "string" and progressName ~= "" then
            return progressName
        end
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.name then
                return info.name
            end
        end
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo and IsNonChineseLocale() then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return ""
end

local function ResolveIcon(entry)
    local iconFileID = tonumber(type(entry) == "table" and entry.iconFileID or nil)
    if iconFileID and iconFileID > 0 then
        return iconFileID
    end
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    return 136197
end

local function ApplyFont(fs, fontDB)
    if not fs then return end
    local staticDB = ExwindTools.DB_Static
    if staticDB and staticDB.ApplyFont then
        staticDB:ApplyFont(fs, fontDB)
        return
    end
    fs:SetFontObject(GameFontNormal)
end

local function RemoveActiveSlot(slot)
    for i = #activeSlots, 1, -1 do
        if activeSlots[i] == slot then
            table.remove(activeSlots, i)
            return
        end
    end
end

local function EnsureRow(index)
    if rows[index] then
        return rows[index]
    end
    local frame = CreateFrame("Frame", nil, anchorFrame, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    local bar = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")
    bar:SetFrameStrata("DIALOG")
    bar:SetAllPoints(frame)

    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetFrameStrata("DIALOG")
    textOverlay:SetAllPoints(frame)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()

    local icon = bar:CreateTexture(nil, "OVERLAY")
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local timeText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    local slot = {
        index = index,
        frame = frame,
        bar = bar,
        textOverlay = textOverlay,
        bg = bg,
        icon = icon,
        nameText = nameText,
        timeText = timeText,
        state = nil,
        previewShown = false,
    }
    rows[index] = slot
    return slot
end

local function GetVisibleSlots()
    local visible = {}
    for i = 1, #rows do
        local slot = rows[i]
        if slot and (type(slot.state) == "table" or slot.previewShown == true) then
            visible[#visible + 1] = slot
        end
    end
    table.sort(visible, function(a, b)
        local aState = type(a.state) == "table"
        local bState = type(b.state) == "table"
        if aState and bState then
            local aEnd = tonumber(a.state.endAt) or math.huge
            local bEnd = tonumber(b.state.endAt) or math.huge
            if aEnd == bEnd then
                return (a.index or 0) < (b.index or 0)
            end
            return aEnd < bEnd
        end
        if aState ~= bState then
            return aState
        end
        return (a.index or 0) < (b.index or 0)
    end)
    return visible
end

local function GetVisibleSlotCount()
    local visible = GetVisibleSlots()
    local count = #visible
    local maxBars = GetConfiguredMaxBars(DB())
    if count < 1 then
        count = 1
    end
    if count > maxBars then
        count = maxBars
    end
    return count
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_CastProgressBarAnchor",
        title = L["施法进度条"],
        getDB = DB,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        syncWidgets = {
            "anchorX",
            "anchorY",
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        widgetRanges = {
            anchorX = { min = -1000, max = 1000, step = 1 },
            anchorY = { min = -600, max = 600, step = 1 },
        },
        initialWidth = DEFAULTS.timerBarGroup.width,
        initialHeight = DEFAULTS.timerBarGroup.height,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        getAnchorPoint = function()
            if GetGrowDir(DB()) == "UP" then
                return "BOTTOM"
            end
            return "TOP"
        end,
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
        onPositionSaved = function(_, offsetX, offsetY)
            SavePosition(offsetX, offsetY)
            if ExwindTools.UI and ExwindTools.UI.MainFrame and ExwindTools.UI.MainFrame:IsShown() then
                ExwindTools.UI:RefreshContent()
            end
        end,
        onEditModeChanged = function(_, activeMode, visible)
            Ensure()
            isEditMode = activeMode == true and visible == true
            if isEditMode then
                if editOverlay then editOverlay:Show() end
                if editLabel then editLabel:Show() end
                ShowStaticEditPreview()
            else
                if editOverlay then editOverlay:Hide() end
                if editLabel then editLabel:Hide() end
                for i = 1, #rows do
                    rows[i].previewShown = false
                end
                CastBar:Hide()
            end
        end,
    })

    return anchorController
end

local function ApplyAnchorPosition(count)
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
end

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

local function UpdateAnchorFrameSize()
    if not anchorFrame then return end
    local db = DB()
    local group = type(db.timerBarGroup) == "table" and db.timerBarGroup or DEFAULTS.timerBarGroup
    local width = math.max(20, SafeNum(group.width, DEFAULTS.timerBarGroup.width))
    local baseHeight = math.max(4, SafeNum(group.height, DEFAULTS.timerBarGroup.height))
    local count = GetVisibleSlotCount()
    local height = baseHeight * count + GetConfiguredSpacing(db) * math.max(0, count - 1)
    anchorFrame:SetSize(width, height)
end

local function LayoutRows()
    if not anchorFrame then return end
    local db = DB()
    local visible = GetVisibleSlots()
    local maxBars = GetConfiguredMaxBars(db)
    local group = type(db.timerBarGroup) == "table" and db.timerBarGroup or DEFAULTS.timerBarGroup
    local height = math.max(4, SafeNum(group.height, DEFAULTS.timerBarGroup.height))
    local spacing = GetConfiguredSpacing(db)
    local growDir = GetGrowDir(db)

    UpdateAnchorFrameSize()

    for i = 1, #rows do
        rows[i].frame:Hide()
    end

    for i = 1, #visible do
        local slot = visible[i]
        slot.frame:ClearAllPoints()
        if i > maxBars then
            slot.frame:Hide()
        else
            local offset = (i - 1) * (height + spacing)
            if growDir == "UP" then
                slot.frame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, offset)
            else
                slot.frame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -offset)
            end
            slot.frame:Show()
        end
    end
end

local function ApplyRowStyle(slot, db)
    if not slot then return end
    local group = type(db.timerBarGroup) == "table" and db.timerBarGroup or DEFAULTS.timerBarGroup
    local width = math.max(20, SafeNum(group.width, DEFAULTS.timerBarGroup.width))
    local height = math.max(4, SafeNum(group.height, DEFAULTS.timerBarGroup.height))
    local iconSize = math.max(4, SafeNum(group.iconSize, DEFAULTS.timerBarGroup.iconSize))
    local frameLevel = math.max(1, (slot.frame:GetParent() and slot.frame:GetParent():GetFrameLevel() or 0) + 1)
    local barLevel = frameLevel + 1
    local borderLevel = barLevel + 1
    local textLevel = borderLevel + 1

    slot.frame:SetFrameLevel(frameLevel)
    slot.bar:SetFrameLevel(barLevel)
    if slot.textOverlay then
        slot.textOverlay:SetFrameLevel(textLevel)
    end
    slot.frame:SetSize(width, height)
    slot.bar:SetSize(width, height)
    slot.bar:ClearAllPoints()
    slot.bar:SetPoint("CENTER", slot.frame, "CENTER")

    local texName = group.texture or DEFAULTS.timerBarGroup.texture
    local tex = LSM and LSM:Fetch("statusbar", texName) or nil
    if not tex then tex = "Interface\\Buttons\\WHITE8X8" end
    slot.bar:SetStatusBarTexture(tex)
    if slot.bg then
        slot.bg:SetTexture(tex)
        slot.bg:SetVertexColor(
            Clamp01(group.barBgColorR, DEFAULTS.timerBarGroup.barBgColorR),
            Clamp01(group.barBgColorG, DEFAULTS.timerBarGroup.barBgColorG),
            Clamp01(group.barBgColorB, DEFAULTS.timerBarGroup.barBgColorB),
            Clamp01(group.barBgColorA, DEFAULTS.timerBarGroup.barBgColorA)
        )
    end

    local edgeTex = group.showBorder and group.borderTexture and group.borderTexture ~= "None"
        and LSM and LSM:Fetch("border", group.borderTexture) or nil
    if edgeTex then
        if not slot.bar.BorderFrame then
            slot.bar.BorderFrame = CreateFrame("Frame", nil, slot.bar, "BackdropTemplate")
        end
        local pad = SafeNum(group.borderPadding, DEFAULTS.timerBarGroup.borderPadding)
        ApplyBackdropBorder(
            slot.bar.BorderFrame,
            slot.bar,
            edgeTex,
            SafeNum(group.borderSize, DEFAULTS.timerBarGroup.borderSize),
            pad,
            Clamp01(group.borderColorR, DEFAULTS.timerBarGroup.borderColorR),
            Clamp01(group.borderColorG, DEFAULTS.timerBarGroup.borderColorG),
            Clamp01(group.borderColorB, DEFAULTS.timerBarGroup.borderColorB),
            Clamp01(group.borderColorA, DEFAULTS.timerBarGroup.borderColorA),
            borderLevel
        )
    elseif slot.bar.BorderFrame then
        HideBackdropBorder(slot.bar.BorderFrame)
    end

    if slot.icon then
        slot.icon:SetSize(iconSize, iconSize)
        slot.icon:ClearAllPoints()
        if tostring(group.iconSide or "LEFT"):upper() == "RIGHT" then
            slot.icon:SetPoint("LEFT", slot.bar, "RIGHT", SafeNum(group.iconOffsetX, DEFAULTS.timerBarGroup.iconOffsetX), SafeNum(group.iconOffsetY, DEFAULTS.timerBarGroup.iconOffsetY))
        else
            slot.icon:SetPoint("RIGHT", slot.bar, "LEFT", SafeNum(group.iconOffsetX, DEFAULTS.timerBarGroup.iconOffsetX), SafeNum(group.iconOffsetY, DEFAULTS.timerBarGroup.iconOffsetY))
        end
        slot.icon:SetShown(group.showIcon ~= false)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local iconEdgeTex = group.showIconBorder and group.iconBorderTexture and group.iconBorderTexture ~= "None"
        and LSM and LSM:Fetch("border", group.iconBorderTexture) or nil
    if iconEdgeTex and slot.icon and group.showIcon ~= false then
        if not slot.bar.IconBorderFrame then
            slot.bar.IconBorderFrame = CreateFrame("Frame", nil, slot.bar, "BackdropTemplate")
        end
        local iconPad = SafeNum(group.iconBorderPadding, DEFAULTS.timerBarGroup.iconBorderPadding)
        ApplyBackdropBorder(
            slot.bar.IconBorderFrame,
            slot.icon,
            iconEdgeTex,
            SafeNum(group.iconBorderSize, DEFAULTS.timerBarGroup.iconBorderSize),
            iconPad,
            Clamp01(group.iconBorderColorR, DEFAULTS.timerBarGroup.iconBorderColorR),
            Clamp01(group.iconBorderColorG, DEFAULTS.timerBarGroup.iconBorderColorG),
            Clamp01(group.iconBorderColorB, DEFAULTS.timerBarGroup.iconBorderColorB),
            Clamp01(group.iconBorderColorA, DEFAULTS.timerBarGroup.iconBorderColorA),
            borderLevel
        )
    elseif slot.bar.IconBorderFrame then
        HideBackdropBorder(slot.bar.IconBorderFrame)
    end

    if slot.nameText then
        ApplyFont(slot.nameText, db.font_name)
        if slot.nameText.SetDrawLayer then
            slot.nameText:SetDrawLayer("OVERLAY", 7)
        end
        slot.nameText:ClearAllPoints()
        slot.nameText:SetPoint("LEFT", slot.bar, "LEFT", SafeNum(db.font_name and db.font_name.x, DEFAULTS.font_name.x), SafeNum(db.font_name and db.font_name.y, DEFAULTS.font_name.y))
        slot.nameText:SetPoint("RIGHT", slot.timeText or slot.bar, "LEFT", -8, 0)
        slot.nameText:SetJustifyH("LEFT")
        slot.nameText:SetShown(db.showName ~= false)
    end
    if slot.timeText then
        ApplyFont(slot.timeText, db.font_time)
        if slot.timeText.SetDrawLayer then
            slot.timeText:SetDrawLayer("OVERLAY", 7)
        end
        slot.timeText:ClearAllPoints()
        slot.timeText:SetPoint("RIGHT", slot.bar, "RIGHT", SafeNum(db.font_time and db.font_time.x, DEFAULTS.font_time.x), SafeNum(db.font_time and db.font_time.y, DEFAULTS.font_time.y))
        slot.timeText:SetWidth(54)
        slot.timeText:SetJustifyH("RIGHT")
        slot.timeText:SetShown(db.showTimer ~= false)
    end

    ApplySlotActiveColor(slot)
end

local function ApplyVisuals()
    if not anchorFrame then return end
    local db = DB()
    local maxBars = GetConfiguredMaxBars(db)

    for i = 1, maxBars do
        ApplyRowStyle(EnsureRow(i), db)
    end
    LayoutRows()
    ApplyAnchorPosition(GetVisibleSlotCount())

    DebugPrint(string.format(
        "ApplyVisuals enabled=%s anchor=(%s,%s) shown=%s %s bars=%d grow=%s",
        tostring(db.enabled ~= false),
        tostring(db.anchorX),
        tostring(db.anchorY),
        tostring(anchorFrame and anchorFrame:IsShown() == true),
        DebugDescribePoint(anchorFrame),
        tonumber(maxBars) or 0,
        tostring(GetGrowDir(db))
    ))
end

local function HideAllRows()
    for i = 1, #rows do
        local slot = rows[i]
        if slot and slot.frame then
            slot.frame:Hide()
        end
    end
end

local function StopSlot(slot)
    if not slot then return end
    RemoveActiveSlot(slot)
    slot.state = nil
    slot.previewShown = false
    if slot.frame then
        slot.frame:Hide()
    end
end

local function DoesOwnerMatch(state, owner)
    if type(state) ~= "table" or type(owner) ~= "table" then
        return false
    end
    if owner.source and tostring(state.ownerSource or "") ~= tostring(owner.source or "") then
        return false
    end
    if owner.castKind and tostring(state.ownerCastKind or "") ~= tostring(owner.castKind or "") then
        return false
    end
    local ownerCastBarID = NormalizeCastBarID(owner.castBarID)
    local stateCastBarID = NormalizeCastBarID(state.ownerCastBarID)
    if ownerCastBarID ~= nil and stateCastBarID ~= ownerCastBarID then
        return false
    end
    if owner.runtime ~= nil and state.ownerRuntime ~= owner.runtime then
        return false
    end
    if owner.encounterID ~= nil and tonumber(state.ownerEncounterID) ~= tonumber(owner.encounterID) then
        return false
    end
    if owner.eventID ~= nil and tonumber(state.ownerEventID) ~= tonumber(owner.eventID) then
        return false
    end
    if (owner.encounterID ~= nil or owner.eventID ~= nil)
        and tostring(state.ownerSource or "") == "boss"
        and tostring(owner.source or "") == "boss"
    then
        return true
    end

    local ownerUnit = NormalizeUnitToken(owner.unit)
    local stateUnit = NormalizeUnitToken(state.ownerUnit)
    if ownerUnit ~= nil then
        if stateUnit == ownerUnit then
            return true
        end
        if tostring(state.ownerSource or "") == "boss"
            and tostring(owner.source or "") == "boss"
            and ownerCastBarID ~= nil
            and stateCastBarID == ownerCastBarID
        then
            return true
        end
        return false
    end

    return true
end

local function StopAllAnimations()
    for i = #activeSlots, 1, -1 do
        local slot = activeSlots[i]
        if slot then
            slot.state = nil
        end
        table.remove(activeSlots, i)
    end
    RefreshCastCheckEventState()
end

local function EnsureAnchorVisible()
    if not anchorFrame then return end
    if isEditMode then
        anchorFrame:Show()
        return
    end
    if DB().enabled == false then
        anchorFrame:Hide()
        return
    end
    if #GetVisibleSlots() > 0 then
        anchorFrame:Show()
    else
        anchorFrame:Hide()
    end
end

local function ConfigurePreviewRow(slot, index, duration, remaining)
    local db = DB()
    local phase = {
        duration = duration,
        castKind = "cast",
        displayName = "施法" .. tostring(index),
        iconFileID = 136197,
    }
    local mode = ResolveMode(phase, db)
    local reverse = IsReverseMode(mode)

    slot.previewShown = true
    slot.state = nil

    slot.bar:SetMinMaxValues(0, duration)
    if slot.bar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
        slot.bar:SetFillStyle(reverse and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
    end
    slot.bar:SetValue(ResolveValue(duration, duration - remaining, mode))
    slot.nameText:SetText(phase.displayName)
    slot.icon:SetTexture(phase.iconFileID)
    slot.timeText:SetText(FormatTime(remaining))
    ApplySlotActiveColor(slot)
end

ShowStaticEditPreview = function()
    local db = DB()
    local maxBars = GetConfiguredMaxBars(db)
    StopAllAnimations()
    for i = 1, maxBars do
        local slot = EnsureRow(i)
        ConfigurePreviewRow(slot, i, 3 + (i * 0.4), math.max(0.5, 2.8 - ((i - 1) * 0.8)))
    end
    for i = maxBars + 1, #rows do
        StopSlot(rows[i])
    end
    ApplyVisuals()
    LayoutRows()
    EnsureAnchorVisible()
    DebugPrint("ShowStaticEditPreview rows=3")
end

local function BeginSlotPhase(slot, phase)
    local state = slot and slot.state or nil
    if not state then
        return
    end
    local db = DB()
    local duration = math.max(0.1, SafeNum(phase and phase.duration, 5))
    local mode = ResolveMode(phase, db)
    local reverse = IsReverseMode(mode)
    local now = GetTime()

    state.duration = duration
    state.mode = mode
    state.startedAt = now
    state.phase = phase

    slot.bar:SetMinMaxValues(0, duration)
    if slot.bar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
        slot.bar:SetFillStyle(reverse and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
    end
    slot.bar:SetValue(ResolveValue(duration, 0, mode))
    slot.nameText:SetText(ResolveDisplayName(phase))
    slot.icon:SetTexture(ResolveIcon(phase))
    slot.timeText:SetText(FormatTime(duration))
    ApplySlotActiveColor(slot)
    slot.frame:Show()

    DebugPrint(string.format(
        "BeginPhase slot=%s kind=%s duration=%.2f display=%s",
        tostring(slot.index),
        tostring(phase and phase.castKind or "nil"),
        tonumber(duration) or 0,
        tostring(ResolveDisplayName(phase))
    ))
end

local function StartSlotAnimation(slot, phases, opts)
    opts = type(opts) == "table" and opts or {}
    if not slot or type(phases) ~= "table" or #phases == 0 then
        return
    end
    StopSlot(slot)

    local totalDuration = 0
    for i = 1, #phases do
        totalDuration = totalDuration + math.max(0.1, SafeNum(phases[i] and phases[i].duration, 5))
    end
    local now = GetTime()
    slot.previewShown = false
    slot.state = {
        phases = phases,
        phaseIndex = 1,
        startedAt = 0,
        duration = 0,
        mode = nil,
        endAt = now + totalDuration,
        castCheckEnabled = opts.castCheckEnabled == true,
        ownerSource = type(opts.owner) == "table" and tostring(opts.owner.source or "") or nil,
        ownerUnit = type(opts.owner) == "table" and NormalizeUnitToken(opts.owner.unit) or nil,
        ownerCastKind = type(opts.owner) == "table" and tostring(opts.owner.castKind or "") or nil,
        ownerCastBarID = type(opts.owner) == "table" and NormalizeCastBarID(opts.owner.castBarID) or nil,
        ownerEncounterID = type(opts.owner) == "table" and tonumber(opts.owner.encounterID) or nil,
        ownerEventID = type(opts.owner) == "table" and tonumber(opts.owner.eventID) or nil,
        ownerRuntime = type(opts.owner) == "table" and opts.owner.runtime or nil,
        earlyStopEnabled = type(opts.owner) == "table" and opts.owner.earlyStopEnabled == true or false,
    }
    activeSlots[#activeSlots + 1] = slot
    BeginSlotPhase(slot, phases[1])
    RefreshCastCheckEventState()
    LayoutRows()
    EnsureAnchorVisible()

    DebugPrint(string.format(
        "StartAnimation slot=%s phases=%d totalDuration=%.2f castCheck=%s",
        tostring(slot.index),
        #phases,
        tonumber(totalDuration) or 0,
        tostring(slot.state.castCheckEnabled == true)
    ))
end

local function TickActiveSlots()
    if #activeSlots == 0 then
        if not isEditMode then
            EnsureAnchorVisible()
        end
        return
    end

    local changedLayout = false
    local nowTick = GetTime()
    for i = #activeSlots, 1, -1 do
        local slot = activeSlots[i]
        local state = slot and slot.state or nil
        if type(state) ~= "table" then
            table.remove(activeSlots, i)
            changedLayout = true
        else
            local elapsed = nowTick - state.startedAt
            if elapsed >= state.duration then
                local nextIndex = state.phaseIndex + 1
                if state.phases and state.phases[nextIndex] then
                    state.phaseIndex = nextIndex
                    BeginSlotPhase(slot, state.phases[nextIndex])
                else
                    slot.state = nil
                    slot.frame:Hide()
                    table.remove(activeSlots, i)
                    changedLayout = true
                end
            else
                ApplySlotActiveColor(slot)
                slot.bar:SetValue(ResolveValue(state.duration, elapsed, state.mode))
                if slot.timeText and slot.timeText:IsShown() then
                    local remaining = math.max(0, state.duration - elapsed)
                    slot.timeText:SetText(FormatTime(remaining))
                end
            end
        end
    end

    if changedLayout then
        RefreshCastCheckEventState()
        LayoutRows()
        if not isEditMode then
            EnsureAnchorVisible()
        end
    end
end

local function NormalizePhases(sequence, opts)
    opts = type(opts) == "table" and opts or {}
    local out = {}
    for i = 1, #sequence do
        local phase = sequence[i]
        if type(phase) == "table" then
            local row = DeepCopy(phase)
            row.displayName = row.displayName or opts.displayName
            row.spellID = row.spellID or opts.spellID
            row.iconFileID = row.iconFileID or opts.iconFileID
            if opts.castCheckEnabled == true then
                row.castCheckEnabled = true
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function AcquireSlot()
    local maxBars = GetConfiguredMaxBars(DB())
    for i = 1, maxBars do
        local slot = EnsureRow(i)
        if type(slot.state) ~= "table" then
            return slot
        end
    end

    local replacement = EnsureRow(1)
    for i = 2, maxBars do
        local slot = EnsureRow(i)
        local slotEnd = slot and slot.state and tonumber(slot.state.endAt) or math.huge
        local replaceEnd = replacement and replacement.state and tonumber(replacement.state.endAt) or math.huge
        if slotEnd < replaceEnd then
            replacement = slot
        end
    end
    return replacement
end

Ensure = function()
    if anchorFrame then return end

    local db = DB()
    local group = type(db.timerBarGroup) == "table" and db.timerBarGroup or DEFAULTS.timerBarGroup
    local initW = math.max(20, SafeNum(group.width, DEFAULTS.timerBarGroup.width))
    local initH = math.max(4, SafeNum(group.height, DEFAULTS.timerBarGroup.height))
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(initW, initH)
    anchorFrame:SetScript("OnUpdate", TickActiveSlots)

    editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0.8, 0, 0.18)
    editOverlay:Hide()
    anchorFrame.EditOverlay = editOverlay

    editLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editLabel:SetPoint("CENTER", anchorFrame, "CENTER")
    editLabel:SetText("|cff00ff00[施法进度条]|r")
    editLabel:Hide()
    anchorFrame.EditLabel = editLabel
    for i = 1, GetConfiguredMaxBars(db) do
        EnsureRow(i)
    end
    ApplyVisuals()
    if db.enabled == false and not isEditMode then
        anchorFrame:Hide()
    end
end

local function SetEditMode(enabled)
    Ensure()
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

function CastBar:ShowEntry(entry, forcedRemaining)
    Ensure()
    local db = DB()
    if db.enabled == false and not isEditMode and type(entry) == "table" and entry._preview ~= true then
        DebugPrint("ShowEntry skipped: disabled")
        return
    end
    if type(entry) ~= "table" then
        DebugPrint("ShowEntry skipped: entry=nil")
        self:Hide()
        return
    end

    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    if remaining == nil then
        remaining = math.max(0, SafeNum(entry.endTime, GetTime() + duration) - GetTime())
    end
    if remaining <= 0 then
        DebugPrint(string.format("ShowEntry skipped: remaining=%.2f", tonumber(remaining) or 0))
        if not isEditMode then
            self:Hide()
        end
        return
    end

    local row = DeepCopy(entry)
    row.duration = math.max(0.1, math.min(duration, remaining))
    local slot = AcquireSlot()

    DebugPrint(string.format(
        "ShowEntry slot=%s duration=%.2f remaining=%.2f kind=%s name=%s",
        tostring(slot and slot.index or "nil"),
        tonumber(duration) or 0,
        tonumber(remaining) or 0,
        tostring(entry.castKind or "nil"),
        tostring(entry.displayName or "nil")
    ))

    StartSlotAnimation(slot, { row }, {
        castCheckEnabled = entry.castCheckEnabled == true,
        owner = type(entry.owner) == "table" and entry.owner or nil,
    })
end

function CastBar:ShowSequence(sequence, opts)
    Ensure()
    local db = DB()
    if db.enabled == false and not isEditMode then
        DebugPrint("ShowSequence skipped: disabled")
        return
    end
    if type(sequence) ~= "table" or #sequence == 0 then
        DebugPrint("ShowSequence skipped: empty")
        return
    end
    opts = type(opts) == "table" and opts or {}
    local phases = NormalizePhases(sequence, opts)
    if #phases == 0 then
        return
    end
    if opts.castCheckEnabled ~= true then
        for i = 1, #phases do
            if phases[i].castCheckEnabled == true then
                opts.castCheckEnabled = true
                break
            end
        end
    end
    local slot = AcquireSlot()
    StartSlotAnimation(slot, phases, opts)
end

function CastBar:Preview(seconds, castKind, opts)
    opts = type(opts) == "table" and opts or {}
    local sec = SafeNum(seconds, 3)
    if sec < 0.2 then sec = 0.2 end
    self:ShowEntry({
        duration = sec,
        endTime = GetTime() + sec,
        castKind = castKind or "cast",
        displayName = castKind == "channel"
            and (IsNonChineseLocale() and "Test Channel" or "测试引导")
            or (IsNonChineseLocale() and "Test Cast" or "测试施法"),
        iconFileID = 136197,
        castCheckEnabled = opts.castCheckEnabled == true,
        _preview = true,
    })
end

function CastBar:PreviewCastCheck(seconds)
    self:Preview(seconds or 3, "cast", {
        castCheckEnabled = true,
    })
end

function CastBar:Hide()
    if anchorFrame and not isEditMode then
        StopAllAnimations()
        HideAllRows()
        anchorFrame:Hide()
        DebugPrint("Hide")
    end
end

function CastBar:StopByOwner(owner)
    if type(owner) ~= "table" then
        return 0
    end
    local removed = 0
    for i = #activeSlots, 1, -1 do
        local slot = activeSlots[i]
        local state = slot and slot.state or nil
        if type(state) == "table" and state.earlyStopEnabled == true and DoesOwnerMatch(state, owner) then
            StopSlot(slot)
            removed = removed + 1
        end
    end
    if removed > 0 then
        RefreshCastCheckEventState()
        LayoutRows()
        EnsureAnchorVisible()
        DebugPrint(string.format(
            "StopByOwner removed=%d unit=%s castBarID=%s kind=%s source=%s",
            tonumber(removed) or 0,
            tostring(owner.unit or "nil"),
            tostring(owner.castBarID or "nil"),
            tostring(owner.castKind or "nil"),
            tostring(owner.source or "nil")
        ))
    end
    return removed
end

function CastBar:StopByUnitCastBar(unit, castBarID, castKind)
    return self:StopByOwner({
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castBarID = NormalizeCastBarID(castBarID),
        castKind = tostring(castKind or ""),
    })
end

function CastBar:IsPlaying()
    return #activeSlots > 0
end

function CastBar:RefreshVisuals()
    if not anchorFrame then
        DebugPrint("RefreshVisuals skipped: anchorFrame=nil")
        return
    end
    DebugPrint("RefreshVisuals begin")
    ApplyVisuals()
    if isEditMode then
        ShowStaticEditPreview()
        return
    end
    if DB().enabled == false then
        self:Hide()
        return
    end
    EnsureAnchorVisible()
end

function CastBar:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        Ensure()
        CastBar:RefreshVisuals()
    end)
end)
