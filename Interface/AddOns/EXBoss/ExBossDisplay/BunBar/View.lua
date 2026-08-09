---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/BunBar/View.lua
-- 束状条 HUD（图标沿时间轴向触发线滑动）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
--(无意义的注释 仅测试用)
local BunBar                = ExBoss.UI.BunBar
local BorderUtil            = ExBoss.BorderUtil
local L                     = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local LSM                   = LibStub and LibStub("LibSharedMedia-3.0", true)

local MODULE_KEY            = "ExBoss.BunBar"
local POOL_TYPE             = "ExBoss_BunBarNode"
local TEXT_UPDATE_INTERVAL  = 0.05
local POSITION_SMOOTH_TIME  = 0.10
local ACTIVE_WINDOW_SECS    = 20
local QUEUE_HIDE_SECS       = 60
local SUDDEN_INTRO_OFFSET_X = 28
local SUDDEN_INTRO_DURATION = 0.45
local QUEUE_INTRO_OFFSET_Y  = 22
local QUEUE_INTRO_DURATION  = 0.22
local OUTRO_DURATION        = 0.20
local OUTRO_FADE_DURATION   = 0.20
local OUTRO_SCALE_TO        = 1.35
local FIVE_SEC_MARK_REMAIN  = 5
local PREVIEW_PREFIX        = "__exboss_bun_preview_"
local TEST_PREFIX           = "__exboss_bun_test_"
local LEGACY_EVENT_KEY      = "encounter" .. "EventID"

local function EnsureBackdropBorderFrame(ownerFrame, key, parentFrame)
    if not ownerFrame or not key or not parentFrame then
        return nil
    end
    local borderFrame = ownerFrame[key]
    if borderFrame then
        return borderFrame
    end
    borderFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    borderFrame:Hide()
    ownerFrame[key] = borderFrame
    return borderFrame
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

local function Factory()
    return _G.ExwindFactory
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DB()
    if ExwindTools and ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY)
        if ok and type(mdb) == "table" then
            if mdb.layoutMode ~= "单条" then mdb.layoutMode = "单条" end
            if mdb.axis ~= "垂直" then mdb.axis = "垂直" end
            mdb.maxTracks = 1
            if mdb.moveDir ~= "向上" and mdb.moveDir ~= "向下" then
                mdb.moveDir = "向下"
            end
            return mdb
        end
    end
    local db = _G.ExBossDB
    local bdb = db and db.timer and db.timer.bunBar
    if type(bdb) == "table" then
        if bdb.layoutMode ~= "单条" then bdb.layoutMode = "单条" end
        if bdb.axis ~= "垂直" then bdb.axis = "垂直" end
        bdb.maxTracks = 1
        if bdb.moveDir ~= "向上" and bdb.moveDir ~= "向下" then
            bdb.moveDir = "向下"
        end
    end
    return bdb
end

local function IsSpellCountDisplayEnabled()
    local root = _G.ExBossDB
    return type(root) == "table"
        and type(root.ui) == "table"
        and type(root.ui.general) == "table"
        and root.ui.general.showSpellOccurrenceCount == true
end

local function FormatOccurrenceCountText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    if not IsSpellCountDisplayEnabled() then
        return ""
    end
    if timer.useOccurrenceCount ~= true then
        return ""
    end
    local count = tonumber(timer.occurrenceCount)
    if not count or count <= 0 then
        return ""
    end
    return string.format("(%d)", count)
end

local function ResolveBunBarDisplayName(timer, spellInfo)
    local usingRename = type(timer) == "table" and type(timer.timerBarName) == "string" and timer.timerBarName ~= ""
    local name = type(timer) == "table" and (timer.timerBarName or timer.displayName) or nil
    if not name and spellInfo then
        name = spellInfo.name
    end
    if not name then
        name = "???"
    end
    if usingRename then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
            return name, ""
        end
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "inline" then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
        end
        return name, ""
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "none" then
        return name, ""
    end
    return name, FormatOccurrenceCountText(timer)
end

local function SafeNum(v, def)
    local n = tonumber(v)
    if not n then return def end
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

local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then return nil end
    local eventID = tonumber(timer.eventID)
    if eventID then return eventID end
    return tonumber(rawget(timer, LEGACY_EVENT_KEY))
end

local function SafeExtractRGB(c)
    if type(c) ~= "table" then return nil end
    local r = tonumber(c.r)
    local g = tonumber(c.g)
    local b = tonumber(c.b)
    if r and g and b then
        return r, g, b
    end
    if type(c.GetRGB) == "function" then
        local ok, rr, gg, bb = pcall(c.GetRGB, c)
        if ok and tonumber(rr) and tonumber(gg) and tonumber(bb) then
            return tonumber(rr), tonumber(gg), tonumber(bb)
        end
    end
    return nil
end

local function Saturate(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function EaseOutCubic(t)
    t = Saturate(t)
    if EasingUtil and EasingUtil.OutCubic then
        return EasingUtil.OutCubic(t)
    end
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function EaseInCubic(t)
    t = Saturate(t)
    if EasingUtil and EasingUtil.InCubic then
        return EasingUtil.InCubic(t)
    end
    return t * t * t
end

local function FallbackDB()
    return {
        enabled           = true,
        anchorX           = -734,
        anchorY           = 141,
        width             = 420,
        iconSize          = 40,
        trackHeight       = 50,
        maxTracks         = 1,
        layoutMode        = "单条",
        axis              = "垂直",
        moveDir           = "向下",
        showIcon          = true,
        showName          = true,
        showTimer         = true,
        font_name         = {
            font = "默认",
            size = 16,
            r = 1,
            g = 1,
            b = 1,
            a = 1,
            outline = "OUTLINE",
            shadow = false,
            shadowX = 1,
            shadowY = -1,
            side = "RIGHT",
            x = 6,
            y = 0,
        },
        font_time         = {
            font = "默认",
            size = 20,
            r = 1,
            g = 1,
            b = 1,
            a = 1,
            outline = "THICKOUTLINE",
            shadow = false,
            shadowX = 1,
            shadowY = -1,
            x = 2,
            y = -2,
        },
        alertIcons        = {
            showIcon = true,
            anchor = "ICON_LEFT",
            layout = "VERTICAL",
            width = 35,
            height = 35,
            x = 0,
            y = 0,
        },
        axisLineWidth     = 1,
        axisLineColorR    = 0.35686275362968,
        axisLineColorG    = 0.35686275362968,
        axisLineColorB    = 0.35686275362968,
        axisLineColorA    = 0.6758024096489,
        fiveSecLineWidth  = 2,
        fiveSecLineColorR = 1.0,
        fiveSecLineColorG = 0.90,
        fiveSecLineColorB = 0.35,
        fiveSecLineColorA = 0.85,
        showBg            = true,
        showBorder        = true,
        bgSettings        = {
            texture       = "Solid",
            bgColorR      = 0.05098039656877518,
            bgColorG      = 0.05882353335618973,
            bgColorB      = 0.0784313753247261,
            bgColorA      = 0.6949490904808044,
            borderTexture = "Solid",
            borderColorR  = 0.9372549653053284,
            borderColorG  = 1.0,
            borderColorB  = 0.9137255549430847,
            borderColorA  = 1,
            edgeSize      = 1,
            inset         = 2,
        },
        colors            = {
            [1] = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },
            [2] = { r = 1.0, g = 0.8, b = 0.0, a = 1.0 },
            [3] = { r = 0.6, g = 0.6, b = 0.6, a = 0.6 },
        },
    }
end

local DEFAULT_FONT_NAME = {
    font = "默认",
    size = 16,
    r = 1,
    g = 1,
    b = 1,
    a = 1,
    outline = "OUTLINE",
    shadow = false,
    shadowX = 1,
    shadowY = -1,
    side = "RIGHT",
    x = 6,
    y = 0,
}

local DEFAULT_FONT_TIME = {
    font = "默认",
    size = 20,
    r = 1,
    g = 1,
    b = 1,
    a = 1,
    outline = "THICKOUTLINE",
    shadow = false,
    shadowX = 1,
    shadowY = -1,
    x = 2,
    y = -2,
}

local anchorFrame = nil
local anchorController = nil
local activeNodes = {}     -- [timerID] = frame
local nodeList = {}
local syntheticTimers = {} -- [timerID] = timer
local previewIDs = {}      -- [timerID] = true
local testIDs = {}         -- [timerID] = true
local isPreviewing = false
local _textElapsed = 0
local _sortDirty = false
local _testSeed = 0
local _updateFrame = nil
local _runtimeConfig = nil
local CreateAnchor
local EnsureAnchorController
local SetPreviewEnabled

local function InvalidateRuntimeConfig()
    _runtimeConfig = nil
end

local function GetRuntimeConfig()
    if _runtimeConfig then
        return _runtimeConfig
    end
    local db = DB() or FallbackDB()
    _runtimeConfig = {
        timelineLen = math.max(120, SafeNum(db.width, 420)),
        moveDir = db.moveDir or "向下",
        iconSize = math.max(10, SafeNum(db.iconSize, 39)),
        trackHeight = math.max(16, SafeNum(db.trackHeight, 49)),
        showName = (db.showName ~= false),
        showTimer = (db.showTimer ~= false),
    }
    return _runtimeConfig
end


local function ShouldShowAnchor()
    if isPreviewing then
        return true
    end
    if ExwindTools and ExwindTools.GlobalEditMode then
        return true
    end
    return next(activeNodes) ~= nil
end

local function RefreshAnchorVisibility()
    if not anchorFrame then return end
    local show = ShouldShowAnchor()
    if show then
        anchorFrame:Show()
        if _updateFrame then
            _updateFrame:Show()
        end
    else
        if _updateFrame then
            _updateFrame:Hide()
        end
        anchorFrame:Hide()
    end
end

local function FormatTime(secs)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    end
    return string.format("%d", math.max(0, math.ceil(secs)))
end

local function UpdateTimeTextBounds(node, text, iconSize, fontSize)
    if not (node and node.TimeText) then return end
    local baseWidth = math.max((iconSize or 0) - 4, 10)
    local size = tonumber(fontSize) or DEFAULT_FONT_TIME.size
    local charCount = math.max(2, tostring(text or ""):len())
    local width = math.max(baseWidth, math.ceil(charCount * size * 0.95 + math.max(10, size * 0.8)))
    local height = math.max(10, math.floor(math.max((iconSize or 0) * 0.42, size * 1.15)))
    node.TimeText:SetWidth(width)
    if node.TimeBG then
        node.TimeBG:SetSize(width, height)
    end
end

local function RecommendSpacingSeconds(db)
    local iconSize = math.max(10, SafeNum(db and db.iconSize, 39))
    local timelineLen = math.max(120, SafeNum(db and db.width, 420))
    local needPixels = iconSize + 2
    return math.max(0.5, (needPixels * ACTIVE_WINDOW_SECS) / timelineLen)
end

local function InitNodeStructure(node)
    node:SetSize(36, 36)
    SetClickThrough(node)

    local bg = node:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.45)
    node.IconBG = bg

    local icon = node:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    node.Icon = icon

    local nameText = node:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    node.NameText = nameText

    node.AlertIcons = {}

    local countText = node:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)
    node.CountText = countText

    local timeBG = node:CreateTexture(nil, "OVERLAY")
    timeBG:SetColorTexture(0, 0, 0, 0.55)
    node.TimeBG = timeBG

    local timeText = node:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetJustifyH("CENTER")
    timeText:SetWordWrap(false)
    if timeText.SetNonSpaceWrap then
        timeText:SetNonSpaceWrap(false)
    end
    node.TimeText = timeText
end

local function StartOutro(node)
    if not node or node._outroEnd then return end
    local now = GetTime()
    local startX = node._displayX
    local startY = node._displayY
    if (startX == nil or startY == nil) and node.GetPoint then
        local _p, _r, _rp, ox, oy = node:GetPoint(1)
        if ox and oy then
            startX = startX or ox
            startY = startY or (-oy)
        end
    end
    if not startX then startX = 0 end
    if not startY then startY = 0 end

    node._outroStart = now
    node._outroEnd = now + OUTRO_DURATION
    node._outroFromX = startX
    node._outroFromY = startY
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
end

local function UpdateOutro(node, now)
    if not node or not node._outroEnd then return false end
    if now >= node._outroEnd then
        return true
    end
    local elapsed = math.max(0, now - (node._outroStart or now))

    local alphaProgress = Saturate(elapsed / math.max(0.01, OUTRO_FADE_DURATION))
    local alphaValue = 1 - EaseInCubic(alphaProgress)
    node:SetAlpha(alphaValue)

    local scaleProgress = Saturate(elapsed / math.max(0.01, OUTRO_DURATION))
    local scaleValue = 1 + (OUTRO_SCALE_TO - 1) * EaseOutCubic(scaleProgress)
    local baseX = node._outroFromX or node._displayX or 0
    local baseY = node._outroFromY or node._displayY or 0
    local safeScale = (scaleValue > 0.001) and scaleValue or 0.001
    node._displayX = baseX
    node._displayY = baseY
    node:SetScale(scaleValue)
    if anchorFrame then
        -- WoW 对父坐标系缩放会引起锚点漂移；用反向补偿锁定视觉中心。
        node:ClearAllPoints()
        node:SetPoint("CENTER", anchorFrame, "TOPLEFT", baseX / safeScale, -(baseY / safeScale))
    end
    node:Show()
    return false
end

do
    local fac = Factory()
    if fac then
        fac:InitPool(POOL_TYPE, "Frame", nil, InitNodeStructure)
    end
end

local function GetRuntimeTimer(timerID)
    local sched = ExBoss.Timeline.Scheduler
    local active = sched and sched._active and sched._active[timerID]
    if active then return active end
    return syntheticTimers[timerID]
end

local function FetchLSM(mediaType, key, fallbackPath)
    if key == "None" or key == "" then
        return nil
    end
    if LSM and key then
        local path = LSM:Fetch(mediaType, key, true)
        if path then
            return path
        end
    end
    return fallbackPath
end

local function ApplyAnchorSkin()
    if not anchorFrame then return end
    local db = DB() or FallbackDB()
    local conf = db.bgSettings or {}
    local inset = math.max(0, SafeNum(conf.inset, 2))
    local bgTex = anchorFrame.BgTexture or anchorFrame:CreateTexture(nil, "BACKGROUND")
    local bgFile = (db.showBg ~= false) and FetchLSM("background", conf.texture, "Interface\\Buttons\\WHITE8X8") or nil
    local edgeFile = (db.showBorder ~= false) and
        FetchLSM("border", conf.borderTexture, "Interface\\Tooltips\\UI-Tooltip-Border") or nil
    local edgeSize = math.max(1, SafeNum(conf.edgeSize, 8))

    anchorFrame.BgTexture = bgTex
    bgTex:ClearAllPoints()
    bgTex:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", inset, -inset)
    bgTex:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -inset, inset)

    local r = SafeNum(conf.bgColorR, 0.05)
    local g = SafeNum(conf.bgColorG, 0.06)
    local b = SafeNum(conf.bgColorB, 0.08)
    local a = SafeNum(conf.bgColorA, 0.55)
    local br = SafeNum(conf.borderColorR, 1)
    local bg = SafeNum(conf.borderColorG, 1)
    local bb = SafeNum(conf.borderColorB, 1)
    local ba = SafeNum(conf.borderColorA, 0.35)

    if bgFile then
        bgTex:SetTexture(bgFile)
        bgTex:SetVertexColor(r, g, b, a)
        bgTex:Show()
    else
        bgTex:Hide()
    end

    anchorFrame.BorderFrame = anchorFrame.BorderFrame or EnsureBackdropBorderFrame(anchorFrame, "BorderFrame", anchorFrame)
    if edgeFile then
        ApplyBackdropBorder(anchorFrame.BorderFrame, anchorFrame, edgeFile, edgeSize, 0, br, bg, bb, ba, (anchorFrame:GetFrameLevel() or 1) + 1)
    else
        HideBackdropBorder(anchorFrame.BorderFrame)
    end
end

local function UpdateAnchorVisuals()
    if not anchorFrame then return end
    local db = DB() or FallbackDB()

    local timelineLen = math.max(120, SafeNum(db.width, 420))
    local trackHeight = math.max(16, SafeNum(db.trackHeight, 49))
    local trackCount = 1
    local crossLen = trackHeight * trackCount

    ApplyAnchorSkin()

    anchorFrame:SetSize(crossLen, timelineLen)
    if anchorFrame.AxisLine then
        local axisWidth = math.max(1, SafeNum(db.axisLineWidth, 1))
        local axisR = Clamp01(db.axisLineColorR, 1.0)
        local axisG = Clamp01(db.axisLineColorG, 1.0)
        local axisB = Clamp01(db.axisLineColorB, 1.0)
        local axisA = Clamp01(db.axisLineColorA, 0.20)
        anchorFrame.AxisLine:ClearAllPoints()
        anchorFrame.AxisLine:SetPoint("TOP", anchorFrame, "TOPLEFT", crossLen * 0.5, 0)
        anchorFrame.AxisLine:SetSize(axisWidth, timelineLen)
        anchorFrame.AxisLine:SetColorTexture(axisR, axisG, axisB, axisA)
    end

    if anchorFrame.FiveSecLine then
        local fiveWidth = math.max(1, SafeNum(db.fiveSecLineWidth, 2))
        local fiveR = Clamp01(db.fiveSecLineColorR, 1.0)
        local fiveG = Clamp01(db.fiveSecLineColorG, 0.90)
        local fiveB = Clamp01(db.fiveSecLineColorB, 0.35)
        local fiveA = Clamp01(db.fiveSecLineColorA, 0.85)
        local remain = math.max(0, math.min(ACTIVE_WINDOW_SECS, FIVE_SEC_MARK_REMAIN))
        local moveDir = db.moveDir or "向下"
        local y
        if moveDir == "向下" then
            y = timelineLen * (1 - (remain / ACTIVE_WINDOW_SECS))
        else
            y = timelineLen * (remain / ACTIVE_WINDOW_SECS)
        end
        anchorFrame.FiveSecLine:ClearAllPoints()
        anchorFrame.FiveSecLine:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -y)
        anchorFrame.FiveSecLine:SetSize(crossLen, fiveWidth)
        anchorFrame.FiveSecLine:SetColorTexture(fiveR, fiveG, fiveB, fiveA)
        anchorFrame.FiveSecLine:Show()
    end

    InvalidateRuntimeConfig()
end

local ALERT_FLAG_DEFS = {
    { name = "deadly",  bit = 1,   atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" },                                            texture = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "enrage",  bit = 2,   atlases = { "icons_64x64_enrage" },                                                                                                     texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "bleed",   bit = 4,   atlases = { "icons_64x64_bleed", "UI-Debuff-Border-Bleed-Icon", "RaidFrame-Icon-DebuffBleed" },                                         texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "magic",   bit = 8,   atlases = { "icons_64x64_magic", "RaidFrame-Icon-DebuffMagic", "UI-HUD-CoolDownManager-Debuff-Magic" } },
    { name = "disease", bit = 16,  atlases = { "icons_64x64_disease", "RaidFrame-Icon-DebuffDisease", "UI-HUD-CoolDownManager-Debuff-Disease" } },
    { name = "curse",   bit = 32,  atlases = { "icons_64x64_curse", "RaidFrame-Icon-DebuffCurse", "UI-HUD-CoolDownManager-Debuff-Curse" } },
    { name = "poison",  bit = 64,  atlases = { "icons_64x64_poison", "RaidFrame-Icon-DebuffPoison", "UI-HUD-CoolDownManager-Debuff-Poison" } },
    { name = "tank",    bit = 128, atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" },       texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 0, right = 19 / 64, top = 22 / 64, bottom = 41 / 64 } },
    { name = "heal",    bit = 256, atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 1 / 64, bottom = 20 / 64 } },
    { name = "damage",  bit = 512, atlases = { "icons_64x64_damage", "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" },        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 22 / 64, bottom = 41 / 64 } },
}

local _alertAtlasExistCache = {}

local function HasFlag(v, b)
    v = tonumber(v) or 0
    b = tonumber(b) or 0
    if v <= 0 or b <= 0 then return false end
    if bit32 and bit32.band then return bit32.band(v, b) ~= 0 end
    if bit and bit.band then return bit.band(v, b) ~= 0 end
    return (v % (b * 2)) >= b
end

local function IsAlertAtlasValid(atlasName)
    if not atlasName or atlasName == "" then return false end
    local cached = _alertAtlasExistCache[atlasName]
    if cached ~= nil then return cached end
    local valid = true
    if C_Texture and C_Texture.GetAtlasInfo then
        valid = C_Texture.GetAtlasInfo(atlasName) ~= nil
    end
    _alertAtlasExistCache[atlasName] = valid and true or false
    return _alertAtlasExistCache[atlasName]
end

local function GetTimerIconFlags(timer)
    return tonumber(type(timer) == "table" and timer.iconFlags or nil) or 0
end

local function ApplyAlertTexture(tex, iconFlags)
    if not tex then return false end
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        tex:Hide()
        return false
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        tex:SetTexture(nil)
                        tex:SetTexCoord(0, 1, 0, 1)
                        tex:SetAtlas(atlas, true)
                        tex:Show()
                        return true
                    end
                end
            end
            if cfg.texture and cfg.texture.file then
                tex:SetTexture(cfg.texture.file)
                tex:SetTexCoord(cfg.texture.left or 0, cfg.texture.right or 1, cfg.texture.top or 0,
                    cfg.texture.bottom or 1)
                tex:Show()
                return true
            end
        end
    end
    tex:Hide()
    return false
end

local function CollectAlertVisuals(iconFlags)
    local out = {}
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return out
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            local added = false
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        out[#out + 1] = { atlas = atlas }
                        added = true
                        break
                    end
                end
            end
            if (not added) and cfg.texture and cfg.texture.file then
                out[#out + 1] = {
                    file = cfg.texture.file,
                    left = cfg.texture.left or 0,
                    right = cfg.texture.right or 1,
                    top = cfg.texture.top or 0,
                    bottom = cfg.texture.bottom or 1,
                }
            end
        end
    end
    return out
end

local function BuildAlertIconMarkup(iconFlags, iconSize, iconYOffset)
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return ""
    end
    local renderSize = tonumber(iconSize) or 14
    local renderYOffset = tonumber(iconYOffset) or 0
    local marks = {}
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        local bitMask = tonumber(cfg.bit) or 0
        if bitMask > 0 and HasFlag(flags, bitMask) then
            local atlasList = cfg.atlases
            local added = false
            if type(atlasList) ~= "table" or #atlasList == 0 then
                atlasList = { "icons_64x64_" .. tostring(cfg.name or "") }
            end
            for _, atlas in ipairs(atlasList) do
                if IsAlertAtlasValid(atlas) then
                    if CreateAtlasMarkup then
                        marks[#marks + 1] = CreateAtlasMarkup(atlas, renderSize, renderSize, 0, renderYOffset)
                    else
                        marks[#marks + 1] = string.format("|A:%s:%d:%d:0:%d|a", atlas, renderSize, renderSize,
                            renderYOffset)
                    end
                    added = true
                    break
                end
            end
            if (not added) and cfg.texture and cfg.texture.file and cfg.texture.file ~= "" then
                local tex = cfg.texture
                local width = tonumber(tex.width) or 64
                local height = tonumber(tex.height) or 64
                if CreateTextureMarkup then
                    marks[#marks + 1] = CreateTextureMarkup(
                        tex.file,
                        width,
                        height,
                        renderSize,
                        renderSize,
                        tonumber(tex.left) or 0,
                        tonumber(tex.right) or 1,
                        tonumber(tex.top) or 0,
                        tonumber(tex.bottom) or 1,
                        0,
                        renderYOffset
                    )
                else
                    marks[#marks + 1] = string.format(
                        "|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d:%d|t",
                        tex.file,
                        renderSize,
                        renderSize,
                        renderYOffset,
                        width,
                        height,
                        math.floor((tonumber(tex.left) or 0) * width),
                        math.floor((tonumber(tex.right) or 1) * width),
                        math.floor((tonumber(tex.top) or 0) * height),
                        math.floor((tonumber(tex.bottom) or 1) * height)
                    )
                end
            end
        end
    end
    return table.concat(marks, " ")
end

local function EnsureAlertIcons(owner, count)
    owner.AlertIcons = owner.AlertIcons or {}
    while #owner.AlertIcons < count do
        local tex = owner:CreateTexture(nil, "OVERLAY")
        tex:Hide()
        owner.AlertIcons[#owner.AlertIcons + 1] = tex
    end
    return owner.AlertIcons
end

local function ResolveAlertIconDB(db)
    local cfg = type(db) == "table" and type(db.alertIcons) == "table" and db.alertIcons or nil
    local fallback = FallbackDB().alertIcons
    return cfg or fallback
end

local function UpdateAlertIcons(owner, iconFlags, cfg)
    local defs = CollectAlertVisuals(iconFlags)
    local icons = EnsureAlertIcons(owner, #defs)
    local enabled = type(cfg) ~= "table" or cfg.showIcon ~= false
    local baseWidth = math.max(6, tonumber(type(cfg) == "table" and cfg.width) or 16)
    local baseHeight = math.max(6, tonumber(type(cfg) == "table" and cfg.height) or baseWidth)
    local layout = tostring(type(cfg) == "table" and cfg.layout or "HORIZONTAL"):upper()
    local vertical = layout == "VERTICAL"
    local shouldShrink = vertical and #defs > 1
    local width = shouldShrink and math.max(4, math.floor(baseWidth / 2)) or baseWidth
    local height = shouldShrink and math.max(4, math.floor(baseHeight / 2)) or baseHeight
    local ox = tonumber(type(cfg) == "table" and cfg.x) or 0
    local oy = tonumber(type(cfg) == "table" and cfg.y) or 0
    local anchorMode = tostring(type(cfg) == "table" and cfg.anchor or "ICON_LEFT"):upper()
    local last = nil
    local function PlaceIcon(tex, index, baseFrame, point, relPoint, horizontalDir)
        local zeroIndex = index - 1
        if vertical and #defs > 1 then
            local column = math.floor(zeroIndex / 2)
            local row = zeroIndex % 2
            local columnOffset = column * (width + 2) * horizontalDir
            local rowOffset = row == 0 and math.floor(height / 2) or -math.floor(height / 2)
            tex:SetPoint(point, baseFrame, relPoint, ox + columnOffset, oy + rowOffset)
            return
        end
        if index == 1 then
            tex:SetPoint(point, baseFrame, relPoint, ox, oy)
        elseif horizontalDir < 0 then
            tex:SetPoint("RIGHT", icons[index - 1], "LEFT", -2, 0)
        else
            tex:SetPoint("LEFT", icons[index - 1], "RIGHT", 2, 0)
        end
    end
    for i, tex in ipairs(icons) do
        local def = defs[i]
        if def and enabled then
            tex:ClearAllPoints()
            tex:SetSize(width, height)
            if anchorMode == "ICON_RIGHT" then
                PlaceIcon(tex, i, owner.Icon or owner, "LEFT", "RIGHT", 1)
            elseif anchorMode == "NAME_LEFT" then
                PlaceIcon(tex, i, owner.NameText or owner.Icon or owner, "RIGHT", "LEFT", -1)
            elseif anchorMode == "NAME_RIGHT" then
                PlaceIcon(tex, i, owner.NameText or owner.Icon or owner, "LEFT", "RIGHT", 1)
            else
                PlaceIcon(tex, i, owner.Icon or owner, "RIGHT", "LEFT", -1)
            end
            if def.atlas then
                tex:SetTexture(nil)
                tex:SetTexCoord(0, 1, 0, 1)
                tex:SetAtlas(def.atlas, false)
            else
                tex:SetAtlas(nil)
                tex:SetTexture(def.file)
                tex:SetTexCoord(def.left, def.right, def.top, def.bottom)
            end
            tex:Show()
            last = tex
        else
            tex:Hide()
        end
    end
    owner._lastAlertIcon = last
    return last
end

local function UpdateNodeVisuals(node, priority)
    local db = DB() or FallbackDB()
    local axis = db.axis or "垂直"
    local iconSize = math.max(10, SafeNum(db.iconSize, 39))
    local col = db.colors and db.colors[priority or 2] or nil
    local staticDB = ExwindTools and ExwindTools.DB_Static
    if not col then col = { r = 1, g = 0.8, b = 0, a = 1 } end

    local overrideColor = nil
    if node and type(node._eventColor) == "table"
        and tonumber(node._eventColor.r) and tonumber(node._eventColor.g) and tonumber(node._eventColor.b) then
        overrideColor = { r = node._eventColor.r, g = node._eventColor.g, b = node._eventColor.b }
    end

    local colorR = overrideColor and overrideColor.r or (col.r or 1)
    local colorG = overrideColor and overrideColor.g or (col.g or 1)
    local colorB = overrideColor and overrideColor.b or (col.b or 1)
    local textColorR = colorR
    local textColorG = colorG
    local textColorB = colorB
    local textColorA = 1
    if type(node._timerTextColor) == "table"
        and tonumber(node._timerTextColor.r)
        and tonumber(node._timerTextColor.g)
        and tonumber(node._timerTextColor.b) then
        textColorR = node._timerTextColor.r
        textColorG = node._timerTextColor.g
        textColorB = node._timerTextColor.b
        textColorA = tonumber(node._timerTextColor.a) or 1
    end

    node:SetSize(iconSize + 4, iconSize + 4)

    if node.IconBG then
        node.IconBG:ClearAllPoints()
        node.IconBG:SetPoint("CENTER", node, "CENTER", 0, 0)
        node.IconBG:SetSize(iconSize, iconSize)
        node.IconBG:SetVertexColor(colorR, colorG, colorB, (col.a or 1) * 0.85)
    end

    if node.Icon then
        node.Icon:ClearAllPoints()
        node.Icon:SetPoint("CENTER", node, "CENTER", 0, 0)
        node.Icon:SetSize(iconSize - 2, iconSize - 2)
        node.Icon:SetShown(db.showIcon ~= false)
    end

    if node.TimeBG then
        node.TimeBG:ClearAllPoints()
        node.TimeBG:SetPoint("BOTTOM", node.Icon, "BOTTOM", 0, 1)
        node.TimeBG:SetSize(iconSize - 4, math.max(10, math.floor(iconSize * 0.42)))
        node.TimeBG:SetShown(false)
    end

    if node.NameText then
        local nameFont = (type(db.font_name) == "table") and db.font_name or DEFAULT_FONT_NAME
        local side = tostring(nameFont.side or DEFAULT_FONT_NAME.side or "RIGHT"):upper()
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.NameText, nameFont)
        end
        node.NameText:ClearAllPoints()
        local nx = SafeNum(nameFont.x, DEFAULT_FONT_NAME.x)
        local ny = SafeNum(nameFont.y, DEFAULT_FONT_NAME.y)
        if side == "LEFT" then
            node.NameText:SetJustifyH("RIGHT")
            node.NameText:SetPoint("RIGHT", node.Icon, "LEFT", nx, ny)
            node.NameText:SetPoint("LEFT", node.Icon, "LEFT", -200 + nx, ny)
        else
            node.NameText:SetJustifyH("LEFT")
            node.NameText:SetPoint("LEFT", node.Icon, "RIGHT", nx, ny)
            node.NameText:SetPoint("RIGHT", node.Icon, "RIGHT", 200 + nx, ny)
        end
        node.NameText:SetShown((db.showName ~= false) and axis == "垂直")
        node.NameText:SetTextColor(textColorR, textColorG, textColorB, textColorA)
    end

    if node.CountText then
        local nameFont = (type(db.font_name) == "table") and db.font_name or DEFAULT_FONT_NAME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.CountText, nameFont)
        end
        node.CountText:ClearAllPoints()
        node.CountText:SetJustifyH("LEFT")
        node.CountText:SetPoint("LEFT", node.NameText or node.Icon, "RIGHT", 4, 0)
        node.CountText:SetShown((db.showName ~= false) and axis == "垂直" and type(node._occurrenceCountText) == "string" and
        node._occurrenceCountText ~= "")
        node.CountText:SetTextColor(textColorR, textColorG, textColorB, textColorA)
    end

    if node.TimeText then
        local timeFont = (type(db.font_time) == "table") and db.font_time or DEFAULT_FONT_TIME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.TimeText, timeFont)
        end
        node.TimeText:ClearAllPoints()
        local tx = SafeNum(timeFont.x, DEFAULT_FONT_TIME.x)
        local ty = SafeNum(timeFont.y, DEFAULT_FONT_TIME.y)
        node.TimeText:SetPoint("CENTER", node.Icon, "CENTER", tx, ty)
        UpdateTimeTextBounds(node, node.TimeText:GetText(), iconSize, SafeNum(timeFont.size, DEFAULT_FONT_TIME.size))
        node.TimeText:SetShown(db.showTimer ~= false)
    end

    UpdateAlertIcons(node, node._iconFlags, ResolveAlertIconDB(db))
end

local function AcquireNode(timerID, priority)
    local fac = Factory()
    if not fac or not anchorFrame then return nil end
    local node = fac:Acquire(POOL_TYPE, anchorFrame)
    node._timerID = timerID
    node._priority = priority or 2
    node._trackIndex = nil
    node._castTime = 0
    node._duration = 30
    node._eventColor = nil
    node._timerTextColor = nil
    node._occurrenceCountText = nil
    node._iconFlags = 0
    node._mode = nil
    node._isMovingNow = false
    node._wasMoving = false
    node._isQueuedNow = false
    node._wasQueued = false
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
    node._outroStart = nil
    node._outroEnd = nil
    node._outroFromX = nil
    node._outroFromY = nil
    node._displayX = nil
    node._displayY = nil
    node._waitingTimelineFinish = nil
    node:SetAlpha(1)
    node:SetScale(1)
    SetClickThrough(node)
    UpdateNodeVisuals(node, node._priority)
    activeNodes[timerID] = node
    table.insert(nodeList, node)
    _sortDirty = true
    return node
end

local function ReleaseNode(timerID)
    local node = activeNodes[timerID]
    if not node then return end

    activeNodes[timerID] = nil
    syntheticTimers[timerID] = nil
    previewIDs[timerID] = nil
    testIDs[timerID] = nil

    for i, n in ipairs(nodeList) do
        if n == node then
            table.remove(nodeList, i)
            break
        end
    end

    node:Hide()
    node._mode = nil
    node._timerTextColor = nil
    node._trackIndex = nil
    node._isMovingNow = nil
    node._wasMoving = nil
    node._isQueuedNow = nil
    node._wasQueued = nil
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
    node._outroStart = nil
    node._outroEnd = nil
    node._outroFromX = nil
    node._outroFromY = nil
    node._displayX = nil
    node._displayY = nil
    node._waitingTimelineFinish = nil
    node:SetAlpha(1)
    node:SetScale(1)
    if node.NameText then node.NameText:SetText("") end
    if node.CountText then node.CountText:SetText("") end
    if node.TimeText then node.TimeText:SetText("") end
    if node.Icon then node.Icon:SetTexture(nil) end
    node._iconFlags = 0
    if node.AlertIcons then
        for _, tex in ipairs(node.AlertIcons) do
            tex:Hide()
        end
    end
    node._lastAlertIcon = nil
    node._occurrenceCountText = nil

    local fac = Factory()
    if fac then
        fac:Release(POOL_TYPE, node)
    end
    _sortDirty = true
    RefreshAnchorVisibility()
end

local _sortBuf = {}
local function RebuildTrackOrder()
    local now = GetTime()

    wipe(_sortBuf)
    for _, node in ipairs(nodeList) do
        table.insert(_sortBuf, node)
    end
    table.sort(_sortBuf, function(a, b)
        return (a._castTime - now) < (b._castTime - now)
    end)

    for _, node in ipairs(_sortBuf) do
        node._trackIndex = 1
    end
    _sortDirty = false
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_BunBarAnchor",
        title = L["束状条"],
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
        initialWidth = 420,
        initialHeight = 50,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
        onEditModeChanged = function(_, active, visible)
            if not anchorFrame then
                CreateAnchor()
            end
            if active == true and visible == true then
                if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
                if anchorFrame.label then anchorFrame.label:Show() end
                SetPreviewEnabled(true)
            else
                if anchorFrame and anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
                if anchorFrame and anchorFrame.label then anchorFrame.label:Hide() end
                SetPreviewEnabled(false)
            end
            RefreshAnchorVisibility()
        end,
    })

    return anchorController
end

CreateAnchor = function()
    if anchorFrame then return end

    local db = DB() or FallbackDB()
    anchorFrame = EnsureAnchorController():Ensure()

    local editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0.8, 0, 0.20)
    editOverlay:Hide()
    anchorFrame.EditOverlay = editOverlay

    local label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 4, -4)
    label:SetText(string.format("|cff00ff00[%s]|r", L["束状条"]))
    label:Hide()
    anchorFrame.label = label
    anchorFrame.EditLabel = label

    local axisLine = anchorFrame:CreateTexture(nil, "ARTWORK")
    axisLine:SetColorTexture(1, 1, 1, 0.20)
    anchorFrame.AxisLine = axisLine

    local fiveSecLine = anchorFrame:CreateTexture(nil, "OVERLAY")
    fiveSecLine:SetColorTexture(1.0, 0.90, 0.35, 0.85)
    anchorFrame.FiveSecLine = fiveSecLine
    UpdateAnchorVisuals()
    _updateFrame:SetParent(anchorFrame)
    RefreshAnchorVisibility()
end

local function CreatePreviewTimers()
    local db = DB() or FallbackDB()
    local count = 8
    local spacingSec = RecommendSpacingSeconds(db)
    local now = GetTime()

    for id in pairs(previewIDs) do
        ReleaseNode(id)
    end

    for i = 1, count do
        local id = PREVIEW_PREFIX .. tostring(i)
        local dur = 7 + i * 2
        local timer = {
            id = id,
            barPriority = ((i - 1) % 3) + 1,
            castTime = now + i * spacingSec,
            duration = dur,
            displayName = IsNonChineseLocale() and ("Preview Spell " .. i) or ("预览技能 " .. i),
            spellID = 136197,
            iconFlags = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1,
            _mode = "preview",
        }
        syntheticTimers[id] = timer
        previewIDs[id] = true
        BunBar:AddTimer(timer)
    end
end

SetPreviewEnabled = function(enabled)
    if not anchorFrame then CreateAnchor() end
    enabled = not not enabled

    if enabled == isPreviewing then
        if enabled then
            CreatePreviewTimers()
        end
        return
    end

    isPreviewing = enabled
    if enabled then
        local canMove = ExwindTools and ExwindTools.GlobalEditMode
        if canMove then
            anchorFrame:EnableMouse(true)
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
            if anchorFrame.label then anchorFrame.label:Show() end
        else
            SetClickThrough(anchorFrame)
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
            if anchorFrame.label then anchorFrame.label:Hide() end
        end
        CreatePreviewTimers()
    else
        for id in pairs(previewIDs) do
            ReleaseNode(id)
        end
        SetClickThrough(anchorFrame)
        if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
        if anchorFrame.label then anchorFrame.label:Hide() end
    end
    RefreshAnchorVisibility()
end

local function CreateTestBars(count)
    if not anchorFrame then CreateAnchor() end
    if isPreviewing then SetPreviewEnabled(false) end
    count = math.max(1, math.min(tonumber(count) or 5, 5))

    local now = GetTime()
    local preset = { 5, 10, 15, 20, 25 }
    for i = 1, count do
        _testSeed = _testSeed + 1
        local id = TEST_PREFIX .. tostring(_testSeed)
        local rem = preset[i] or (i * 5)
        local dur = math.max(rem + 6, 10)
        local timer = {
            id = id,
            barPriority = ((i - 1) % 3) + 1,
            castTime = now + rem,
            duration = dur,
            displayName = IsNonChineseLocale() and ("Test Spell " .. i) or ("测试技能 " .. i),
            spellID = 136197,
            iconFlags = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1,
            _mode = "test",
        }
        syntheticTimers[id] = timer
        testIDs[id] = true
        BunBar:AddTimer(timer)
    end
end

local function ClearTestBars()
    for id in pairs(testIDs) do
        ReleaseNode(id)
    end
end

local _movingBuf = {}
local _queueBuf = {}
local _releaseBuf = {}

local function ApplyPlacement(node, targetX, targetY, remaining, introKind, isQueue, now, elapsed, cfg, updateText,
                              timelineLen, iconSize)
    if not node then return end

    if introKind == "sudden" then
        node._displayX = targetX + SUDDEN_INTRO_OFFSET_X
        node._displayY = targetY
        node._introKind = "sudden"
        node._introFromX = node._displayX
        node._introFromY = node._displayY
        node._introStart = now
        node._introEnd = now + SUDDEN_INTRO_DURATION
    elseif introKind == "queue" then
        node._displayX = targetX
        node._displayY = targetY - QUEUE_INTRO_OFFSET_Y
        node._introKind = "queue"
        node._introFromX = node._displayX
        node._introFromY = node._displayY
        node._introStart = now
        node._introEnd = now + QUEUE_INTRO_DURATION
    elseif node._displayX == nil or node._displayY == nil then
        node._displayX = targetX
        node._displayY = targetY
    elseif node._introEnd and now < node._introEnd then
        local span = math.max(0.01, node._introEnd - (node._introStart or (node._introEnd - 0.01)))
        local t = (now - (node._introStart or (node._introEnd - span))) / span
        local ease = EaseOutCubic(t)
        local fromX = node._introFromX or targetX
        local fromY = node._introFromY or targetY
        if node._introKind == "sudden" then
            node._displayX = fromX + (targetX - fromX) * ease
            node._displayY = targetY
        elseif node._introKind == "queue" then
            node._displayX = targetX
            node._displayY = fromY + (targetY - fromY) * ease
        else
            node._displayX = fromX + (targetX - fromX) * ease
            node._displayY = fromY + (targetY - fromY) * ease
        end
    else
        if node._introEnd and now >= node._introEnd then
            node._introKind = nil
            node._introStart = nil
            node._introEnd = nil
            node._introFromX = nil
            node._introFromY = nil
        end
        local lerpAlpha = 1
        if POSITION_SMOOTH_TIME > 0 then
            lerpAlpha = 1 - math.exp(-elapsed / POSITION_SMOOTH_TIME)
            if lerpAlpha < 0 then lerpAlpha = 0 end
            if lerpAlpha > 1 then lerpAlpha = 1 end
        end
        node._displayX = node._displayX + (targetX - node._displayX) * lerpAlpha
        node._displayY = node._displayY + (targetY - node._displayY) * lerpAlpha
    end

    node:ClearAllPoints()
    node:SetPoint("CENTER", anchorFrame, "TOPLEFT", node._displayX, -node._displayY)

    if node.NameText then
        node.NameText:SetShown(cfg.showName)
    end
    if node.TimeText then
        node.TimeText:SetShown(cfg.showTimer)
    end
    if node.TimeBG then
        node.TimeBG:SetShown(false)
    end

    local iconHalf = iconSize * 0.5
    local dy = node._displayY or targetY
    local outOfRange = (not isQueue) and (dy > timelineLen + iconHalf + 2 or dy < -iconHalf - 2)
    if outOfRange then
        node:Hide()
    else
        if node._waitingTimelineFinish == true then
            node:SetAlpha(0.62 + 0.38 * math.abs(math.sin((now or GetTime()) * 5.5)))
        else
            node:SetAlpha(1)
        end
        node:SetScale(1)
        node:Show()
    end
    if updateText and node.TimeText and node.TimeText:IsShown() then
        local txt = FormatTime(remaining)
        local db = DB() or FallbackDB()
        local timeFont = (type(db.font_time) == "table") and db.font_time or DEFAULT_FONT_TIME
        node.TimeText:SetText(txt)
        UpdateTimeTextBounds(node, txt, iconSize, SafeNum(timeFont.size, DEFAULT_FONT_TIME.size))
    end
end

local function RuntimeTick(elapsed, nowOverride)
    if not anchorFrame then return end

    _textElapsed = _textElapsed + elapsed
    local updateText = false
    if _textElapsed >= TEXT_UPDATE_INTERVAL then
        _textElapsed = 0
        updateText = true
    end

    if _sortDirty then
        RebuildTrackOrder()
    end

    local cfg = GetRuntimeConfig()
    local timelineLen = cfg.timelineLen
    local moveDir = cfg.moveDir
    local iconSize = cfg.iconSize
    local trackHeight = cfg.trackHeight
    local now = nowOverride or GetTime()
    local minIconGap = iconSize + 2
    wipe(_movingBuf)
    wipe(_queueBuf)
    wipe(_releaseBuf)

    for _, node in pairs(activeNodes) do
        node._wasMoving = node._isMovingNow
        node._isMovingNow = false
        node._wasQueued = node._isQueuedNow
        node._isQueuedNow = false
    end

    for timerID, node in pairs(activeNodes) do
        if node._outroEnd then
            if UpdateOutro(node, now) then
                table.insert(_releaseBuf, timerID)
            end
        else
            local timer = GetRuntimeTimer(timerID)
            if not timer then
                StartOutro(node)
                if UpdateOutro(node, now) then
                    table.insert(_releaseBuf, timerID)
                end
            else
                local remaining = timer.castTime - now
                node._waitingTimelineFinish = timer.fixedAIWaitingTimelineFinish == true
                if remaining <= 0 then
                    if timer._mode == "preview" then
                        timer.castTime = now + math.max(5, timer.duration or 8)
                        remaining = timer.castTime - now
                    elseif timer._mode == "test" then
                        StartOutro(node)
                        if UpdateOutro(node, now) then
                            table.insert(_releaseBuf, timerID)
                        end
                        remaining = 0
                    else
                        -- 实战条不在这里提前删，保持在触发线直到 OnCast / 调度清理。
                        remaining = 0
                    end
                end

                if node._outroEnd then
                    -- 已进入退场动画，跳过轨道计算
                elseif remaining > QUEUE_HIDE_SECS then
                    node:Hide()
                    node._displayX = nil
                    node._displayY = nil
                    node._introKind = nil
                    node._introStart = nil
                    node._introEnd = nil
                    node._introFromX = nil
                    node._introFromY = nil
                elseif remaining > ACTIVE_WINDOW_SECS then
                    node._isQueuedNow = true
                    node._introKind = nil
                    node._introStart = nil
                    node._introEnd = nil
                    node._introFromX = nil
                    node._introFromY = nil
                    node._rtRemaining = remaining
                    table.insert(_queueBuf, node)
                elseif node._trackIndex then
                    node._isMovingNow = true
                    local y = 0
                    local progress = remaining / ACTIVE_WINDOW_SECS
                    if moveDir == "向下" then
                        y = timelineLen * (1 - progress)
                    else
                        y = timelineLen * progress
                    end
                    node._rtRemaining = remaining
                    node._rtTargetY = y
                    node._rtIntroKind = (node._wasQueued and "queue") or ((not node._wasMoving) and "sudden") or nil
                    table.insert(_movingBuf, node)
                else
                    node:Hide()
                end
            end
        end
    end

    if #_movingBuf > 1 then
        table.sort(_movingBuf, function(a, b)
            return (a._rtTargetY or 0) < (b._rtTargetY or 0)
        end)
    end

    if #_movingBuf > 1 then
        for i = #_movingBuf - 1, 1, -1 do
            local nextNode = _movingBuf[i + 1]
            local cur = _movingBuf[i]
            local nextY = nextNode and nextNode._rtTargetY or 0
            local curY = cur and cur._rtTargetY or 0
            if nextY - curY < minIconGap then
                cur._rtTargetY = nextY - minIconGap
            end
        end
    end

    if #_queueBuf > 1 then
        table.sort(_queueBuf, function(a, b)
            return (a._rtRemaining or 0) < (b._rtRemaining or 0)
        end)
    end

    if #_queueBuf > 0 then
        local queueEdge = (moveDir == "向下") and 0 or timelineLen
        local queueSign = (moveDir == "向下") and -1 or 1
        for i, node in ipairs(_queueBuf) do
            ApplyPlacement(
                node,
                trackHeight * 0.5,
                queueEdge + queueSign * (i * minIconGap),
                node._rtRemaining or 0,
                nil,
                true,
                now,
                elapsed,
                cfg,
                updateText,
                timelineLen,
                iconSize
            )
        end
    end

    for _, node in ipairs(_movingBuf) do
        ApplyPlacement(
            node,
            trackHeight * 0.5,
            node._rtTargetY or 0,
            node._rtRemaining or 0,
            node._rtIntroKind,
            false,
            now,
            elapsed,
            cfg,
            updateText,
            timelineLen,
            iconSize
        )
    end

    if #_releaseBuf > 0 then
        for _, id in ipairs(_releaseBuf) do
            ReleaseNode(id)
        end
    end
end

_updateFrame = CreateFrame("Frame")
_updateFrame:Hide()
SetClickThrough(_updateFrame)
_updateFrame:SetScript("OnUpdate", function(_, elapsed)
    RuntimeTick(elapsed)
end)

local function SetEditMode(enabled)
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

function BunBar:AddTimer(timer)
    local db = DB()
    if db and db.enabled == false then return end
    if not anchorFrame then CreateAnchor() end
    RefreshAnchorVisibility()
    if activeNodes[timer.id] then return end

    local node = AcquireNode(timer.id, timer.barPriority)
    if not node then return end

    node._castTime = timer.castTime
    node._duration = math.max(1, timer.duration or 30)
    node._eventColor = timer.eventColor
    node._timerTextColor = timer.timerTextColor
    node._iconFlags = GetTimerIconFlags(timer)
    node._mode = timer._mode

    local spellInfo = timer.spellID and C_Spell.GetSpellInfo(timer.spellID) or nil
    local name, countText = ResolveBunBarDisplayName(timer, spellInfo)
    node._occurrenceCountText = countText
    if node.NameText then node.NameText:SetText(name) end
    if node.CountText then node.CountText:SetText(node._occurrenceCountText or "") end
    if node.Icon then
        node.Icon:SetTexture((spellInfo and spellInfo.iconID) or timer.iconFileID or 136197)
    end
    if node.AlertIcons then
        for _, tex in ipairs(node.AlertIcons) do
            tex:Hide()
        end
    end
    node._lastAlertIcon = nil
    UpdateNodeVisuals(node, timer.barPriority)

    _sortDirty = true
    RefreshAnchorVisibility()
end

function BunBar:RefreshTimer(timer)
    if type(timer) ~= "table" then
        return
    end
    local node = activeNodes[timer.id]
    if not node then
        return
    end

    node._castTime = timer.castTime
    node._duration = math.max(1, timer.duration or 30)
    node._eventColor = timer.eventColor
    node._timerTextColor = timer.timerTextColor
    node._iconFlags = GetTimerIconFlags(timer)
    node._mode = timer._mode

    local spellInfo = timer.spellID and C_Spell.GetSpellInfo(timer.spellID) or nil
    local name, countText = ResolveBunBarDisplayName(timer, spellInfo)
    node._occurrenceCountText = countText
    if node.NameText then node.NameText:SetText(name) end
    if node.CountText then node.CountText:SetText(node._occurrenceCountText or "") end

    if node.Icon then
        node.Icon:SetTexture((spellInfo and spellInfo.iconID) or timer.iconFileID or 136197)
    end

    UpdateNodeVisuals(node, timer.barPriority)

    _sortDirty = true
    RefreshAnchorVisibility()
end

function BunBar:OnCast(timer)
    local node = activeNodes[timer.id]
    if node then
        StartOutro(node)
    else
        ReleaseNode(timer.id)
    end
end

function BunBar:OnPreAlert(timer)
    -- 束状条不需要额外预警动画
end

function BunBar:ReleaseAll()
    isPreviewing = false
    local ids = {}
    for id in pairs(activeNodes) do
        table.insert(ids, id)
    end
    for _, id in ipairs(ids) do
        ReleaseNode(id)
    end
    syntheticTimers = {}
    previewIDs = {}
    testIDs = {}
    RefreshAnchorVisibility()
end

function BunBar:RefreshVisuals()
    local db = DB() or FallbackDB()
    if anchorFrame then
        EnsureAnchorController():ApplyPosition()
    end
    UpdateAnchorVisuals()
    for _, node in pairs(activeNodes) do
        UpdateNodeVisuals(node, node._priority)
    end
    _sortDirty = true
    if isPreviewing then
        CreatePreviewTimers()
    end
    InvalidateRuntimeConfig()
    RefreshAnchorVisibility()
end

function BunBar:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

function BunBar:SetPreviewEnabled(enabled)
    SetPreviewEnabled(enabled)
end

function BunBar:TogglePreview()
    SetPreviewEnabled(not isPreviewing)
end

function BunBar:CreateTestBars(count)
    CreateTestBars(count)
end

function BunBar:ClearTestBars()
    ClearTestBars()
end

function BunBar:OnRuntimeTick(elapsed, now)
    RuntimeTick(elapsed, now)
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateAnchor()
        UpdateAnchorVisuals()
    end)
end)

BunBar._active = activeNodes
