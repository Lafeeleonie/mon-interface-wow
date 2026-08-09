---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/RingProgress.lua
-- 屏幕中央圆环进度（透明背景）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.RingProgress = ExBoss.UI.RingProgress or {}
local Ring = ExBoss.UI.RingProgress

local MODULE_KEY = "ExBoss.RingProgress"

local DEFAULTS = {
    enabled = true,
    showName = false,
    showTimer = true,
    style = "thin1", -- thin1 | thin2 | classic
    size = 170,
    alpha = 0.95,
    castFillMode = "cw_fill",
    channelFillMode = "ccw_decay",
    ringColorR = 0.1,
    ringColorG = 0.8,
    ringColorB = 1.0,
    ringColorA = 1.0,
    bgEnabled = false,
    bgAlpha = 0.3,
    bgColorR = 0.3,
    bgColorG = 0.3,
    bgColorB = 0.3,
    bgColorA = 1.0,
    anchorX = 0,
    anchorY = 0,
    font_name = {
        font = "默认",
        size = 16,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 0, y = 30,
    },
    font_time = {
        font = "默认",
        size = 20,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        x = 0, y = 0,
    },
}

local STYLE_TEXTURES = {
    thin1 = "Interface\\AddOns\\EXBoss\\ExBossDisplay\\Textures\\RingWhiteThin1",
    thin2 = "Interface\\AddOns\\EXBoss\\ExBossDisplay\\Textures\\RingWhiteThin2",
    classic = "Interface\\AddOns\\EXBoss\\ExBossDisplay\\Textures\\RingWhite",
}

local frame
local anchorController
local cdForward
local cdReverse
local editRing
local bgRing
local textOverlay
local nameText
local timeText
local editOverlay
local editLabel
local isEditMode = false
local editTicker = nil
local activeAnim = nil
local eventFrame = nil
local GetActiveCooldown
local ApplyDefaults
local Ensure
local EnsureAnchorController
local ShowEditPreview
local StopEditPreview

local CAST_CHECK_MARGIN = 0.1
local CAST_CHECK_GOOD = { r = 0.10, g = 0.95, b = 0.20 }
local CAST_CHECK_BAD = { r = 1.00, g = 0.12, b = 0.08 }

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then
        n = tonumber(def)
    end
    if n == nil then
        n = 1
    end
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return n
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

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function SetClickThrough(obj)
    if not obj then return end
    obj:EnableMouse(false)
    if obj.SetMouseClickEnabled then
        pcall(obj.SetMouseClickEnabled, obj, false)
    end
    if obj.SetMouseMotionEnabled then
        pcall(obj.SetMouseMotionEnabled, obj, false)
    end
end

local function DB()
    if ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY, DEFAULTS)
        if ok and type(mdb) == "table" then
            ApplyDefaults(mdb, DEFAULTS)
            return mdb
        end
    end

    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.ringProgress = ExBossDB.timer.ringProgress or {}
    local db = ExBossDB.timer.ringProgress
    ApplyDefaults(db, DEFAULTS)
    return db
end

local function GetTexturePath(style)
    style = tostring(style or ""):lower()
    return STYLE_TEXTURES[style] or STYLE_TEXTURES.thin1
end

local function GetConfiguredColor(db)
    return Clamp01(db.ringColorR, DEFAULTS.ringColorR),
           Clamp01(db.ringColorG, DEFAULTS.ringColorG),
           Clamp01(db.ringColorB, DEFAULTS.ringColorB)
end

local function FormatTime(sec)
    local n = tonumber(sec) or 0
    if n < 0 then
        n = 0
    end
    if n >= 10 then
        return string.format("%.0f", n)
    end
    return string.format("%.1f", n)
end

local function ApplyFont(fs, fontDB)
    if not fs then
        return
    end
    local staticDB = ExwindTools.DB_Static
    if staticDB and staticDB.ApplyFont then
        staticDB:ApplyFont(fs, fontDB)
        return
    end
    fs:SetFontObject(GameFontNormal)
end

ApplyDefaults = function(dst, defaults)
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

local function GetPlayerCastEndAt()
    local now = GetTime()

    if UnitCastingInfo then
        local ok, _name, _text, _texture, _startTimeMS, endTimeMS = pcall(UnitCastingInfo, "player")
        local endAt = ok and tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then
            return endAt
        end
    end

    if UnitChannelInfo then
        local ok, _name, _text, _texture, _startTimeMS, endTimeMS = pcall(UnitChannelInfo, "player")
        local endAt = ok and tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then
            return endAt
        end
    end

    return nil
end

local function ResolveCastCheckColor()
    local castEndAt = GetPlayerCastEndAt()
    local ringEndAt = activeAnim and tonumber(activeAnim.endAt) or nil
    if castEndAt and ringEndAt and castEndAt > (ringEndAt - CAST_CHECK_MARGIN) then
        return CAST_CHECK_BAD
    end
    return CAST_CHECK_GOOD
end

local function IsBadCheckColor(color)
    return type(color) == "table"
        and color.r == CAST_CHECK_BAD.r
        and color.g == CAST_CHECK_BAD.g
        and color.b == CAST_CHECK_BAD.b
end

local function ResolveActiveColor(db)
    if activeAnim then
        local hasCheck = false
        local c
        if activeAnim.castCheckEnabled == true then
            hasCheck = true
            c = ResolveCastCheckColor()
            if IsBadCheckColor(c) then
                return c.r, c.g, c.b
            end
        end
        if hasCheck then
            return CAST_CHECK_GOOD.r, CAST_CHECK_GOOD.g, CAST_CHECK_GOOD.b
        end
    end
    return GetConfiguredColor(db)
end

local function ApplyActiveColor()
    if not activeAnim then
        return
    end
    local db = DB()
    local r, g, b = ResolveActiveColor(db)
    local a = Clamp01(db.alpha, DEFAULTS.alpha)

    local function ApplyCooldownColor(cd)
        if not cd then return end
        if cd.SetSwipeColor then
            cd:SetSwipeColor(r, g, b, a)
        end

        -- 部分客户端/贴图组合不会把 SetSwipeColor 立即应用到自定义 swipe 贴图。
        -- 同步改可见 Texture 的 VertexColor，确保圆环颜色实时变化。
        local regionCount = cd.GetNumRegions and cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetVertexColor then
                region:SetVertexColor(r, g, b, a)
            end
        end
    end

    ApplyCooldownColor(cdForward)
    ApplyCooldownColor(cdReverse)
end

local function ResolveFillMode(entry, db)
    if type(entry) == "table" and entry.reverse ~= nil then
        return (entry.reverse == true) and "ccw_decay" or "cw_decay"
    end

    local castKind = type(entry) == "table" and tostring(entry.castKind or "") or ""
    local mode
    if castKind == "channel" then
        mode = tostring(db.channelFillMode or DEFAULTS.channelFillMode)
    else
        mode = tostring(db.castFillMode or DEFAULTS.castFillMode)
    end
    if mode ~= "cw_fill" and mode ~= "cw_decay" and mode ~= "ccw_fill" and mode ~= "ccw_decay" then
        mode = DEFAULTS.castFillMode
    end
    return mode
end

local function ResolveReverseFromMode(mode)
    if mode == "cw_fill" then
        return true
    elseif mode == "cw_decay" then
        return false
    elseif mode == "ccw_fill" then
        return false
    elseif mode == "ccw_decay" then
        return true
    end
    return false
end

local function ResolveDisplayRemaining(duration, remaining, mode)
    if mode == "ccw_fill" or mode == "ccw_decay" then
        local elapsed = math.max(0, duration - remaining)
        return math.max(0.01, elapsed)
    end
    return remaining
end

local function ResolveDisplayName(entry)
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    local rename = type(entry) == "table" and entry.ringRenameText or nil
    local progressName = type(entry) == "table" and entry.progressDisplayName or nil
    local name = type(entry) == "table" and entry.displayName or nil
    if type(entry) == "table" and entry.ringRenameEnabled == true and type(rename) == "string" and rename ~= "" then
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
    if type(progressName) == "string" and progressName ~= "" then
        return progressName
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return ""
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

local function StopAnimation()
    activeAnim = nil
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if bgRing then bgRing:Hide() end
end

local function EnsureEventFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then
            return
        end
        if not (activeAnim and activeAnim.castCheckEnabled == true) then
            return
        end
        ApplyActiveColor()
    end)
    return eventFrame
end

local function SetCastCheckEventsEnabled(enabled)
    local ef = EnsureEventFrame()
    ef:UnregisterAllEvents()
    if enabled ~= true then
        return
    end
    ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

local function BeginPhase(phase)
    local db = DB()
    local mode = phase.mode or ResolveFillMode({ castKind = phase.castKind }, db)
    local reverse = ResolveReverseFromMode(mode)
    local cd, inactiveCd = GetActiveCooldown(reverse)
    if inactiveCd then
        inactiveCd:Hide()
    end

    local duration = math.max(0.1, SafeNum(phase.duration, 5))
    local now = GetTime()
    local initialRemaining = math.max(0.01, math.min(duration, SafeNum(phase.initialRemaining, duration)))
    local elapsed = math.max(0, duration - initialRemaining)
    local startTime = now - elapsed
    cd:SetCooldown(startTime, duration)
    cd:Show()
    frame:Show()
    if bgRing then
        if db.bgEnabled then bgRing:Show() else bgRing:Hide() end
    end
    if nameText then
        nameText:SetText(ResolveDisplayName(phase))
    end
    if timeText then
        timeText:SetText(FormatTime(initialRemaining))
    end

    activeAnim.cd = cd
    activeAnim.mode = mode
    activeAnim.duration = duration
    activeAnim.startedAt = startTime
    activeAnim.endAt = startTime + duration
    ApplyActiveColor()
end

local function StartAnimation(phases, opts)
    opts = type(opts) == "table" and opts or {}
    local totalDuration = 0
    for i = 1, #phases do
        totalDuration = totalDuration + math.max(0.1, SafeNum(phases[i] and phases[i].duration, 5))
    end
    local now = GetTime()
    activeAnim = {
        phases = phases,
        phaseIndex = 1,
        cd = nil,
        duration = nil,
        mode = nil,
        startedAt = 0,
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
    SetCastCheckEventsEnabled(activeAnim.castCheckEnabled == true)
    BeginPhase(phases[1])

    frame:SetScript("OnUpdate", function()
        if not activeAnim then
            frame:SetScript("OnUpdate", nil)
            return
        end

        local now = GetTime()
        local elapsed = now - activeAnim.startedAt
        if elapsed >= activeAnim.duration then
            local nextIndex = activeAnim.phaseIndex + 1
            if activeAnim.phases and activeAnim.phases[nextIndex] then
                activeAnim.phaseIndex = nextIndex
                BeginPhase(activeAnim.phases[nextIndex])
                return
            end
            StopAnimation()
            if not isEditMode then
                Ring:Hide()
            end
            return
        end

        ApplyActiveColor()

        local remaining
        if activeAnim.mode == "ccw_fill" or activeAnim.mode == "ccw_decay" then
            remaining = math.max(0.01, elapsed)
        else
            remaining = math.max(0.01, activeAnim.duration - elapsed)
        end
        local displayRemaining = math.max(0.01, activeAnim.duration - elapsed)

        local startTime = now + remaining - activeAnim.duration
        activeAnim.cd:SetCooldown(startTime, activeAnim.duration)
        if timeText and timeText:IsShown() then
            timeText:SetText(FormatTime(displayRemaining))
        end
    end)
end

local function ShowStaticEditPreview()
    Ensure()
    StopAnimation()
    local db = DB()
    if cdForward then cdForward:Hide() end
    if cdReverse then cdReverse:Hide() end
    if editRing then editRing:Show() end
    if bgRing then
        if db.bgEnabled then bgRing:Show() else bgRing:Hide() end
    end
    frame:Show()
    if nameText then
        nameText:SetText(IsNonChineseLocale() and "Sample Spell" or "技能名称示例")
        nameText:SetShown(db.showName ~= false)
    end
    if timeText then
        timeText:SetText("8.8")
        timeText:SetShown(db.showTimer ~= false)
    end
end

local function ApplyVisuals()
    if not frame then return end
    local db = DB()
    local size = SafeNum(db.size, DEFAULTS.size)
    if size < 20 then size = 20 end
    if size > 360 then size = 360 end

    frame:SetSize(size, size)
    EnsureAnchorController():ApplyPosition()

    if textOverlay and textOverlay.SetFrameLevel then
        textOverlay:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
        textOverlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    end
    if cdForward and cdForward.SetFrameLevel then
        cdForward:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    end
    if cdReverse and cdReverse.SetFrameLevel then
        cdReverse:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    end

    if nameText then
        ApplyFont(nameText, db.font_name)
        if nameText.SetDrawLayer then
            nameText:SetDrawLayer("OVERLAY", 7)
        end
        nameText:ClearAllPoints()
        nameText:SetPoint("CENTER", frame, "CENTER",
            SafeNum(db.font_name and db.font_name.x, DEFAULTS.font_name.x),
            SafeNum(db.font_name and db.font_name.y, DEFAULTS.font_name.y))
        nameText:SetWidth(math.max(80, size - 20))
        nameText:SetJustifyH("CENTER")
        nameText:SetShown(db.showName ~= false)
    end
    if timeText then
        ApplyFont(timeText, db.font_time)
        if timeText.SetDrawLayer then
            timeText:SetDrawLayer("OVERLAY", 7)
        end
        timeText:ClearAllPoints()
        timeText:SetPoint("CENTER", frame, "CENTER",
            SafeNum(db.font_time and db.font_time.x, DEFAULTS.font_time.x),
            SafeNum(db.font_time and db.font_time.y, DEFAULTS.font_time.y))
        timeText:SetWidth(math.max(54, math.floor(size * 0.5)))
        timeText:SetJustifyH("CENTER")
        timeText:SetShown(db.showTimer ~= false)
    end

    if bgRing then
        bgRing:SetTexture(GetTexturePath(db.style))
        bgRing:SetVertexColor(
            Clamp01(db.bgColorR, DEFAULTS.bgColorR),
            Clamp01(db.bgColorG, DEFAULTS.bgColorG),
            Clamp01(db.bgColorB, DEFAULTS.bgColorB),
            Clamp01(db.bgAlpha,  DEFAULTS.bgAlpha))
    end

    if editRing then
        editRing:SetTexture(GetTexturePath(db.style))
        local r, g, b = GetConfiguredColor(db)
        editRing:SetVertexColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
    end

    local function ApplyCooldownVisual(cd)
        if not cd then return end
        if cd.SetSwipeTexture then
            cd:SetSwipeTexture(GetTexturePath(db.style))
        end
        if cd.SetSwipeColor then
            local r, g, b = GetConfiguredColor(db)
            cd:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
        end
        local r, g, b = GetConfiguredColor(db)
        local a = Clamp01(db.alpha, DEFAULTS.alpha)
        local regionCount = cd.GetNumRegions and cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetVertexColor then
                region:SetVertexColor(r, g, b, a)
            end
        end
    end
    ApplyCooldownVisual(cdForward)
    ApplyCooldownVisual(cdReverse)
end

local function ClearCooldownBackgrounds()
    local function ClearOne(cd)
        if not cd then return end
        local regionCount = cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local layer = region.GetDrawLayer and region:GetDrawLayer() or nil
                if region.SetBlendMode then
                    region:SetBlendMode("ADD")
                end
                if layer == "BACKGROUND" and region.SetColorTexture then
                    region:SetColorTexture(0, 0, 0, 0)
                end
            end
        end
    end
    ClearOne(cdForward)
    ClearOne(cdReverse)
end

local function SetupCooldown(cd, reverse)
    cd:SetAllPoints()
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end
    if cd.SetDrawBling then
        cd:SetDrawBling(false)
    end
    if cd.SetDrawEdge then
        cd:SetDrawEdge(false)
    end
    if cd.SetDrawSwipe then
        cd:SetDrawSwipe(true)
    end
    if cd.SetReverse then
        cd:SetReverse(reverse)
    end
end

function GetActiveCooldown(reverse)
    if reverse then
        return cdReverse, cdForward
    end
    return cdForward, cdReverse
end

Ensure = function()
    if frame then
        return
    end

    local db = DB()
    frame = EnsureAnchorController():Ensure()

    bgRing = frame:CreateTexture(nil, "BACKGROUND")
    bgRing:SetAllPoints()
    bgRing:Hide()

    editRing = frame:CreateTexture(nil, "ARTWORK")
    editRing:SetAllPoints()
    editRing:Hide()
    frame.EditRing = editRing

    editOverlay = frame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0, 0, 0)
    editOverlay:Hide()
    frame.EditOverlay = editOverlay

    editLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editLabel:SetPoint("TOP", frame, "TOP", 0, -4)
    editLabel:SetText("")
    editLabel:Hide()
    frame.EditLabel = editLabel

    textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    textOverlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    SetClickThrough(textOverlay)

    nameText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)

    timeText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    timeText:SetJustifyH("CENTER")
    timeText:SetWordWrap(false)

    cdForward = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    SetupCooldown(cdForward, false)
    cdReverse = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    SetupCooldown(cdReverse, true)

    ApplyVisuals()
    ClearCooldownBackgrounds()

    -- 初始化颜色
    if cdForward and cdForward.SetSwipeColor then
        local r, g, b = GetConfiguredColor(db)
        cdForward:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
        cdReverse:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
    end
end

ShowEditPreview = function()
    ShowStaticEditPreview()
end

StopEditPreview = function()
    if editTicker then
        editTicker:Cancel()
        editTicker = nil
    end
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_RingProgress",
        title = "圆环进度",
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
            anchorX = { min = -1000, max = 1000, step = 5 },
            anchorY = { min = -600, max = 600, step = 5 },
        },
        initialWidth = DEFAULTS.size,
        initialHeight = DEFAULTS.size,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        fixedFrameStrata = true,
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
        onEditModeChanged = function()
            Ensure()
            isEditMode = anchorController.editActive == true and anchorController.editVisible == true
            ApplyVisuals()
            if isEditMode then
                if editOverlay then editOverlay:Show() end
                if editLabel then editLabel:Hide() end
                ShowEditPreview()
                StopEditPreview()
            else
                if editRing then editRing:Hide() end
                if bgRing then bgRing:Hide() end
                if editOverlay then editOverlay:Hide() end
                if editLabel then editLabel:Hide() end
                StopEditPreview()
                frame:Hide()
            end
        end,
    })

    return anchorController
end

EnsureAnchorController():RegisterEditModeHandler()

function Ring:ShowEntry(entry, forcedRemaining)
    Ensure()
    local db = DB()
    if type(entry) ~= "table" then
        frame:Hide()
        return
    end
    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    local mode = ResolveFillMode(entry, db)
    if remaining == nil then
        remaining = math.max(0, SafeNum(entry.endTime, GetTime() + duration) - GetTime())
    end
    if remaining <= 0 then
        if not isEditMode then
            frame:Hide()
        end
        return
    end
    StopAnimation()
    StartAnimation({
        {
            duration = duration,
            initialRemaining = remaining,
            castKind = entry.castKind or "cast",
            mode = mode,
            displayName = entry.displayName,
            progressDisplayName = entry.progressDisplayName,
            preferSpellName = entry.preferSpellName == true,
            spellID = entry.spellID,
            ringRenameEnabled = entry.ringRenameEnabled == true,
            ringRenameText = entry.ringRenameText,
        },
    }, {
        castCheckEnabled = entry.castCheckEnabled == true,
        owner = type(entry.owner) == "table" and entry.owner or nil,
    })
end

function Ring:ShowSequence(sequence, opts)
    Ensure()
    if type(sequence) ~= "table" or #sequence == 0 then
        return
    end
    opts = type(opts) == "table" and opts or {}
    if opts.castCheckEnabled ~= true then
        for i = 1, #sequence do
            if type(sequence[i]) == "table" and sequence[i].castCheckEnabled == true then
                opts.castCheckEnabled = true
                break
            end
        end
    end
    StopAnimation()
    StartAnimation(sequence, opts)
end

function Ring:Preview(seconds, castKind, opts)
    opts = type(opts) == "table" and opts or {}
    local sec = SafeNum(seconds, 3)
    if sec < 0.2 then sec = 0.2 end
    self:ShowEntry({
        duration = sec,
        endTime = GetTime() + sec,
        castKind = castKind or "cast",
        castCheckEnabled = opts.castCheckEnabled == true,
        displayName = IsNonChineseLocale() and "Test Cast" or "测试施法",
        progressDisplayName = IsNonChineseLocale() and "Test Cast" or "测试施法",
    })
end

function Ring:PreviewCastCheck(seconds)
    self:Preview(seconds or 3, "cast", {
        castCheckEnabled = true,
    })
end

function Ring:Hide()
    if frame and not isEditMode then
        StopAnimation()
        if cdForward then cdForward:Hide() end
        if cdReverse then cdReverse:Hide() end
        if editRing then editRing:Hide() end
        if bgRing then bgRing:Hide() end
        frame:Hide()
    end
end

function Ring:StopByOwner(owner)
    if type(owner) ~= "table" then
        return 0
    end
    if type(activeAnim) ~= "table" or activeAnim.earlyStopEnabled ~= true or not DoesOwnerMatch(activeAnim, owner) then
        return 0
    end
    StopAnimation()
    if not isEditMode then
        self:Hide()
    end
    return 1
end

function Ring:StopByUnitCastBar(unit, castBarID, castKind)
    return self:StopByOwner({
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castBarID = NormalizeCastBarID(castBarID),
        castKind = tostring(castKind or ""),
    })
end

function Ring:IsPlaying()
    return activeAnim ~= nil
end

function Ring:RefreshVisuals()
    if not frame then
        return
    end
    ApplyVisuals()
    if isEditMode then
        ShowStaticEditPreview()
    end
end

function Ring:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        Ensure()
        Ring:RefreshVisuals()
    end)
end)
