---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/TimerBar/View.lua
-- BOSS 技能倒计时条 HUD
--
-- 结构：anchorFrame（拖动锚点）+ StatusBar 池
-- 进度：SetValue(remaining/duration)，左满右空
-- 编辑模式：RegisterEditModeCallback → 解锁拖动 + 预览
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local TimerBar      = ExBoss.UI.TimerBar
local BorderUtil    = ExBoss.BorderUtil
local L             = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local LSM           = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end
local function Factory()
    return _G.ExwindFactory
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local POOL_TYPE         = "ExBoss_TimerBar"
local TEXT_UPDATE_INTERVAL = 0.05
local MODULE_KEY        = "ExBoss.TimerBar"
local TEST_PREFIX       = "__exboss_test_"
local LEGACY_EVENT_KEY  = "encounter" .. "EventID"
local DEFAULT_ANCHOR_X  = -237
local DEFAULT_ANCHOR_Y  = 245

-- 运行时状态
local anchorFrame  = nil
local anchorController = nil
local activeBars   = {}      -- [timerID] = StatusBar frame
local barList      = {}      -- 有序列表，用于排列
local previewBars  = {}
local isPreviewing = false
local _textElapsed = 0
local _sortDirty   = false
local _testSeed    = 0
local testTimers   = {}      -- [timerID] = { castTime, duration }
local CreateAnchor = nil
local EnsureAnchorController = nil
local SetPreviewEnabled = nil
local _runtimeCache = nil
local UpdateAnchorFrameSize = nil

-- =============================================================
-- DB 快捷访问
-- =============================================================
local function DB()
    if ExwindTools and ExwindTools.GetModuleDB then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY)
        if ok and type(mdb) == "table" then
            return mdb
        end
    end
    local db = _G.ExBossDB
    return db and db.timer and db.timer.timerBar
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

local function ResolveTimerBarDisplayName(timer)
    local usingRename = type(timer) == "table" and type(timer.timerBarName) == "string" and timer.timerBarName ~= ""
    local name = type(timer) == "table" and (timer.timerBarName or timer.displayName) or nil
    if not name and type(timer) == "table" and timer.spellID then
        local info = C_Spell.GetSpellInfo(timer.spellID)
        name = info and info.name
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

local DEFAULT_PRIORITY_COLORS = {
    [1] = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },
    [2] = { r = 1.0, g = 0.8, b = 0.0, a = 1.0 },
    [3] = { r = 0.6, g = 0.6, b = 0.6, a = 0.6 },
}

local DEFAULT_STYLE = {
    width = 200,
    height = 25,
    texture = "Melli",
    barColorR = 1.0,
    barColorG = 0.7,
    barColorB = 0.0,
    barColorA = 1.0,
    barBgColorR = 0.0,
    barBgColorG = 0.0,
    barBgColorB = 0.0,
    barBgColorA = 0.5,
    showBorder = true,
    borderTexture = "Square Full White",
    borderColorR = 0.0,
    borderColorG = 0.0,
    borderColorB = 0.0,
    borderColorA = 1.0,
    borderSize = 1,
    borderPadding = 0,
    showIcon = true,
    iconSide = "LEFT",
    iconSize = 24,
    iconOffsetX = -1,
    iconOffsetY = 0,
    showIconBorder = true,
    iconBorderTexture = "Square Full White",
    iconBorderColorR = 0.0,
    iconBorderColorG = 0.0,
    iconBorderColorB = 0.0,
    iconBorderColorA = 1.0,
    iconBorderSize = 1,
    iconBorderPadding = 0,
    alertIcons = {
        showIcon = true,
        anchor = "OUTSIDE_LEFT",
        layout = "HORIZONTAL",
        size = 26,
        x = -28,
        y = 0,
    },
}

local DEFAULT_FONT_NAME = {
    font = "默认",
    size = 15,
    r = 1, g = 1, b = 1, a = 1,
    outline = "OUTLINE",
    shadow = false,
    shadowX = 1, shadowY = -1,
    x = 2, y = 0,
}

local DEFAULT_FONT_TIME = {
    font = "默认",
    size = 15,
    r = 1, g = 1, b = 1, a = 1,
    outline = "OUTLINE",
    shadow = false,
    shadowX = 1, shadowY = -1,
    x = 0, y = 0,
}

local function GetStyleDB(db)
    if type(db) == "table" and type(db.timerBarGroup) == "table" then
        return db.timerBarGroup
    end
    return db
end

local function ResolveStyle(db)
    local src = GetStyleDB(db)
    if type(src) ~= "table" then
        return DEFAULT_STYLE
    end

    local style = {}
    for k, v in pairs(DEFAULT_STYLE) do
        if src[k] ~= nil then
            style[k] = src[k]
        else
            style[k] = v
        end
    end
    return style
end

local function Clamp01(v)
    if v <= 0 then return 0 end
    if v >= 1 then return 1 end
    return v
end

local function ResolveFillMode(db)
    local mode = tostring(db and db.fillMode or "LTR_FILL")
    if mode == "LTR_FILL" or mode == "LTR_FADE" or mode == "RTL_FILL" or mode == "RTL_FADE" then
        return mode
    end
    return "LTR_FILL"
end

local function InvalidateRuntimeCache()
    _runtimeCache = nil
end

local function GetRuntimeCache()
    if _runtimeCache then
        return _runtimeCache
    end
    local db = DB() or {}
    local style = ResolveStyle(db)
    local h = SafeNum(style.height, DEFAULT_STYLE.height)
    if h < 8 then h = 8 end
    local spacing = SafeNum(db and db.spacing, 1)
    if spacing < 0 then spacing = 0 end
    local maxBars = SafeNum(db and db.maxBars, 6)
    if maxBars < 1 then maxBars = 1 end
    _runtimeCache = {
        fillMode = ResolveFillMode(db),
        height = h,
        spacing = spacing,
        growDir = (db and db.growDir) or "UP",
        maxBars = maxBars,
    }
    return _runtimeCache
end


local function IsFillIncreasing(fillMode)
    return fillMode == "LTR_FILL" or fillMode == "RTL_FILL"
end

local function IsReverseFill(fillMode)
    return fillMode == "LTR_FADE" or fillMode == "RTL_FILL"
end

local function ApplyBarProgress(bar, remaining, duration, fillMode)
    if not bar then return end
    local d = math.max(1, tonumber(duration) or 1)
    local rem = math.max(0, tonumber(remaining) or 0)
    local ratio = rem / d
    if IsFillIncreasing(fillMode) then
        ratio = 1 - ratio
    end
    bar:SetValue(Clamp01(ratio))
end

local function ResolveColor(style, key, fallback)
    local def = fallback or { r = 1, g = 1, b = 1, a = 1 }
    if type(style) ~= "table" then
        return def.r, def.g, def.b, def.a
    end
    local r = tonumber(style[key .. "R"])
    local g = tonumber(style[key .. "G"])
    local b = tonumber(style[key .. "B"])
    local a = tonumber(style[key .. "A"])
    if r and g and b then
        return r, g, b, a or def.a
    end
    local t = style[key]
    if type(t) == "table" then
        r = tonumber(t.r)
        g = tonumber(t.g)
        b = tonumber(t.b)
        a = tonumber(t.a)
        if r and g and b then
            return r, g, b, a or def.a
        end
    end
    return def.r, def.g, def.b, def.a
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

-- =============================================================
-- 池初始化
-- =============================================================
local function InitBarStructure(bar)
    SetClickThrough(bar)
    bar:SetClampedToScreen(true)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetFillStyle(Enum.StatusBarFillStyle.Standard)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bar.BG = bg

    local icon = bar:CreateTexture(nil, "OVERLAY")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.Icon = icon

    local textOverlay = CreateFrame("Frame", nil, bar)
    textOverlay:SetAllPoints(bar)
    bar.TextOverlay = textOverlay

    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    bar.NameText = nameText

    bar.AlertIcons = {}

    local timeText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetJustifyH("RIGHT")
    bar.TimeText = timeText

    local countText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetJustifyH("RIGHT")
    countText:SetWordWrap(false)
    bar.CountText = countText
end

local function EnsureBackdropBorderFrame(key, ownerFrame, parentFrame)
    if not ownerFrame or not parentFrame then
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

local function IsBlizzardManagedTimer(timer)
    return type(timer) == "table" and (timer.timelineManaged == true or timer.source == "blizzard")
end

local ALERT_FLAG_DEFS = {
    { name = "deadly", bit = 1, atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" }, texture = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "enrage", bit = 2, atlases = { "icons_64x64_enrage" }, texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "bleed", bit = 4, atlases = { "icons_64x64_bleed", "UI-Debuff-Border-Bleed-Icon", "RaidFrame-Icon-DebuffBleed" }, texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "magic", bit = 8, atlases = { "icons_64x64_magic", "RaidFrame-Icon-DebuffMagic", "UI-HUD-CoolDownManager-Debuff-Magic" } },
    { name = "disease", bit = 16, atlases = { "icons_64x64_disease", "RaidFrame-Icon-DebuffDisease", "UI-HUD-CoolDownManager-Debuff-Disease" } },
    { name = "curse", bit = 32, atlases = { "icons_64x64_curse", "RaidFrame-Icon-DebuffCurse", "UI-HUD-CoolDownManager-Debuff-Curse" } },
    { name = "poison", bit = 64, atlases = { "icons_64x64_poison", "RaidFrame-Icon-DebuffPoison", "UI-HUD-CoolDownManager-Debuff-Poison" } },
    { name = "tank", bit = 128, atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 0, right = 19 / 64, top = 22 / 64, bottom = 41 / 64 } },
    { name = "heal", bit = 256, atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 1 / 64, bottom = 20 / 64 } },
    { name = "damage", bit = 512, atlases = { "icons_64x64_damage", "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 22 / 64, bottom = 41 / 64 } },
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
    if flags <= 0 then tex:Hide() return false end
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
                tex:SetTexCoord(cfg.texture.left or 0, cfg.texture.right or 1, cfg.texture.top or 0, cfg.texture.bottom or 1)
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
    local renderSize = tonumber(iconSize) or 16
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
                        marks[#marks + 1] = string.format("|A:%s:%d:%d:0:%d|a", atlas, renderSize, renderSize, renderYOffset)
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

local function ResolveAlertIconDB(style)
    local cfg = type(style) == "table" and type(style.alertIcons) == "table" and style.alertIcons or nil
    return cfg or DEFAULT_STYLE.alertIcons
end

local function UpdateAlertIcons(owner, iconFlags, cfg)
    local defs = CollectAlertVisuals(iconFlags)
    local icons = EnsureAlertIcons(owner, #defs)
    local enabled = type(cfg) ~= "table" or cfg.showIcon ~= false
    local baseSize = math.max(6, tonumber(type(cfg) == "table" and cfg.size) or DEFAULT_STYLE.alertIcons.size or 16)
    local layout = tostring(type(cfg) == "table" and cfg.layout or "HORIZONTAL"):upper()
    local vertical = layout == "VERTICAL"
    local size = (vertical and #defs > 1) and math.max(4, math.floor(baseSize / 2)) or baseSize
    local ox = tonumber(type(cfg) == "table" and cfg.x) or 0
    local oy = tonumber(type(cfg) == "table" and cfg.y) or 0
    local anchorMode = tostring(type(cfg) == "table" and cfg.anchor or "OUTSIDE_LEFT"):upper()
    local last = nil
    local function PlaceIcon(tex, index, baseFrame, point, relPoint, horizontalDir)
        local zeroIndex = index - 1
        if vertical and #defs > 1 then
            local column = math.floor(zeroIndex / 2)
            local row = zeroIndex % 2
            local columnOffset = column * (size + 2) * horizontalDir
            local rowOffset = row == 0 and math.floor(size / 2) or -math.floor(size / 2)
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
            tex:SetSize(size, size)
            if anchorMode == "TEXT_BEFORE" then
                PlaceIcon(tex, i, owner.NameText or owner, "RIGHT", "LEFT", -1)
            elseif anchorMode == "TEXT_AFTER" then
                PlaceIcon(tex, i, owner.NameText or owner, "LEFT", "RIGHT", 1)
            else
                PlaceIcon(tex, i, owner, "RIGHT", "LEFT", -1)
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

do
    local fac = Factory()
    if fac then
        fac:InitPool(POOL_TYPE, "StatusBar", nil, InitBarStructure)
    end
end

-- =============================================================
-- 视觉更新（从 DB 读取外观）
-- =============================================================
local function UpdateBarVisuals(bar, priority)
    local db = DB() or {}
    local style = ResolveStyle(db)
    local fillMode = ResolveFillMode(db)
    local staticDB = ExwindTools and ExwindTools.DB_Static
    local allowBackdropBorder = (bar and bar._suppressBackdropBorder ~= true)

    local w = SafeNum(style.width, DEFAULT_STYLE.width)
    local h = SafeNum(style.height, DEFAULT_STYLE.height)
    if w < 80 then w = 80 end
    if h < 8 then h = 8 end
    bar:SetSize(w, h)

    local texName = style.texture or DEFAULT_STYLE.texture
    local tex = (LSM and LSM:Fetch("statusbar", texName))
                or "Interface\\Buttons\\WHITE8X8"
    bar:SetStatusBarTexture(tex)
    if bar.SetReverseFill then
        bar:SetReverseFill(IsReverseFill(fillMode))
    end

    if bar.BG then
        bar.BG:SetTexture(tex)
        local bgr, bgg, bgb, bga = ResolveColor(style, "barBgColor", {
            r = DEFAULT_STYLE.barBgColorR,
            g = DEFAULT_STYLE.barBgColorG,
            b = DEFAULT_STYLE.barBgColorB,
            a = DEFAULT_STYLE.barBgColorA,
        })
        bar.BG:SetVertexColor(bgr, bgg, bgb, bga)
    end

    local fallbackCol = DEFAULT_PRIORITY_COLORS[priority or 2] or DEFAULT_PRIORITY_COLORS[2]
    local r, g, b, a = ResolveColor(style, "barColor", fallbackCol)

    local overrideColor = nil
    if bar and type(bar._eventColor) == "table"
        and tonumber(bar._eventColor.r) and tonumber(bar._eventColor.g) and tonumber(bar._eventColor.b) then
        overrideColor = { r = bar._eventColor.r, g = bar._eventColor.g, b = bar._eventColor.b }
    end

    if overrideColor then
        bar:SetStatusBarColor(overrideColor.r, overrideColor.g, overrideColor.b, a)
    else
        bar:SetStatusBarColor(r, g, b, a)
    end

    local edgeTex = nil
    if style.showBorder and style.borderTexture and style.borderTexture ~= "None" then
        edgeTex = LSM and LSM:Fetch("border", style.borderTexture) or nil
    end
    if edgeTex and allowBackdropBorder then
        local edgeSize = SafeNum(style.borderSize, DEFAULT_STYLE.borderSize)
        local pad = SafeNum(style.borderPadding, DEFAULT_STYLE.borderPadding)
        bar.BorderFrame = EnsureBackdropBorderFrame("BorderFrame", bar, bar)
        local br, bg, bb, ba = ResolveColor(style, "borderColor", {
            r = DEFAULT_STYLE.borderColorR,
            g = DEFAULT_STYLE.borderColorG,
            b = DEFAULT_STYLE.borderColorB,
            a = DEFAULT_STYLE.borderColorA,
        })
        ApplyBackdropBorder(bar.BorderFrame, bar, edgeTex, edgeSize, pad, br, bg, bb, ba, bar:GetFrameLevel() + 2)
    elseif bar.BorderFrame then
        HideBackdropBorder(bar.BorderFrame)
    end

    if bar.TextOverlay then
        local overlayLevel = bar:GetFrameLevel() + 3
        if bar.BorderFrame and bar.BorderFrame:IsShown() then
            overlayLevel = math.max(overlayLevel, (bar.BorderFrame:GetFrameLevel() or 0) + 1)
        end
        bar.TextOverlay:SetFrameLevel(overlayLevel)
    end

    if bar.Icon then
        local iconSize = SafeNum(style.iconSize, h)
        if iconSize < 8 then iconSize = 8 end
        bar.Icon:SetSize(iconSize, iconSize)
        bar.Icon:ClearAllPoints()
        local side = tostring(style.iconSide or DEFAULT_STYLE.iconSide):upper()
        local ox = SafeNum(style.iconOffsetX, DEFAULT_STYLE.iconOffsetX)
        local oy = SafeNum(style.iconOffsetY, DEFAULT_STYLE.iconOffsetY)
        if side == "RIGHT" then
            bar.Icon:SetPoint("LEFT", bar, "RIGHT", ox, oy)
        else
            bar.Icon:SetPoint("RIGHT", bar, "LEFT", ox, oy)
        end
        bar.Icon:SetShown(style.showIcon ~= false)
    end

    local iconBorderTex = nil
    if style.showIconBorder and style.iconBorderTexture and style.iconBorderTexture ~= "None" then
        iconBorderTex = LSM and LSM:Fetch("border", style.iconBorderTexture) or nil
    end
    if iconBorderTex and allowBackdropBorder and bar.Icon and style.showIcon ~= false then
        local iconPad = SafeNum(style.iconBorderPadding, DEFAULT_STYLE.iconBorderPadding)
        bar.IconBorderFrame = EnsureBackdropBorderFrame("IconBorderFrame", bar, bar)
        ApplyBackdropBorder(
            bar.IconBorderFrame,
            bar.Icon,
            iconBorderTex,
            SafeNum(style.iconBorderSize, DEFAULT_STYLE.iconBorderSize),
            iconPad,
            Clamp01(style.iconBorderColorR, DEFAULT_STYLE.iconBorderColorR),
            Clamp01(style.iconBorderColorG, DEFAULT_STYLE.iconBorderColorG),
            Clamp01(style.iconBorderColorB, DEFAULT_STYLE.iconBorderColorB),
            Clamp01(style.iconBorderColorA, DEFAULT_STYLE.iconBorderColorA),
            bar:GetFrameLevel() + 2
        )
    elseif bar.IconBorderFrame then
        HideBackdropBorder(bar.IconBorderFrame)
    end

    if bar.NameText then
        local nameFont = (type(db.font_name) == "table") and db.font_name or DEFAULT_FONT_NAME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(bar.NameText, nameFont)
        end
        bar.NameText:ClearAllPoints()
        local nx = SafeNum(nameFont.x, DEFAULT_FONT_NAME.x)
        local ny = SafeNum(nameFont.y, DEFAULT_FONT_NAME.y)
        bar.NameText:SetPoint("LEFT",  bar, "LEFT", 4 + nx, ny)
        bar.NameText:SetShown(db.showName ~= false)
        if type(bar._timerTextColor) == "table" and tonumber(bar._timerTextColor.r) and tonumber(bar._timerTextColor.g) and tonumber(bar._timerTextColor.b) then
            bar.NameText:SetTextColor(bar._timerTextColor.r, bar._timerTextColor.g, bar._timerTextColor.b, tonumber(bar._timerTextColor.a) or 1)
        end
    end

    if bar.CountText then
        local nameFont = (type(db.font_name) == "table") and db.font_name or DEFAULT_FONT_NAME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(bar.CountText, nameFont)
        end
        bar.CountText:ClearAllPoints()
        local nx = SafeNum(nameFont.x, DEFAULT_FONT_NAME.x)
        local ny = SafeNum(nameFont.y, DEFAULT_FONT_NAME.y)
        bar.CountText:SetPoint("RIGHT", bar.TimeText or bar, "LEFT", -6 + nx, ny)
        bar.CountText:SetShown(type(bar._occurrenceCountText) == "string" and bar._occurrenceCountText ~= "")
        if type(bar._timerTextColor) == "table" and tonumber(bar._timerTextColor.r) and tonumber(bar._timerTextColor.g) and tonumber(bar._timerTextColor.b) then
            bar.CountText:SetTextColor(bar._timerTextColor.r, bar._timerTextColor.g, bar._timerTextColor.b, tonumber(bar._timerTextColor.a) or 1)
        end
    end

    if bar.TimeText then
        local timeFont = (type(db.font_time) == "table") and db.font_time or DEFAULT_FONT_TIME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(bar.TimeText, timeFont)
        end
        bar.TimeText:ClearAllPoints()
        local tx = SafeNum(timeFont.x, DEFAULT_FONT_TIME.x)
        local ty = SafeNum(timeFont.y, DEFAULT_FONT_TIME.y)
        bar.TimeText:SetPoint("RIGHT", bar, "RIGHT", -4 + tx, ty)
        bar.TimeText:SetShown(db.showTimer ~= false)
        if type(bar._timerTextColor) == "table" and tonumber(bar._timerTextColor.r) and tonumber(bar._timerTextColor.g) and tonumber(bar._timerTextColor.b) then
            bar.TimeText:SetTextColor(bar._timerTextColor.r, bar._timerTextColor.g, bar._timerTextColor.b, tonumber(bar._timerTextColor.a) or 1)
        end
    end

    UpdateAlertIcons(bar, bar._iconFlags, ResolveAlertIconDB(style))

end

-- =============================================================
-- Acquire / Release
-- =============================================================
local function AcquireBar(timerID, priority)
    local fac = Factory()
    if not fac or not anchorFrame then return nil end
    local bar = fac:Acquire(POOL_TYPE, anchorFrame)
    bar._timerID   = timerID
    bar._priority  = priority or 2
    bar._castTime  = 0
    bar._duration  = 30
    bar._eventColor = nil
    bar._timerTextColor = nil
    bar._occurrenceCountText = nil
    bar._iconFlags = 0
    bar._suppressBackdropBorder = nil
    bar._isPreview = nil
    bar._isTest    = nil
    bar:SetAlpha(1)
    SetClickThrough(bar)
    UpdateBarVisuals(bar, priority)
    activeBars[timerID] = bar
    table.insert(barList, bar)
    _sortDirty = true
    return bar
end

local function ReleaseBar(timerID)
    local bar = activeBars[timerID]
    if not bar then return end
    testTimers[timerID] = nil
    activeBars[timerID] = nil
    for i, b in ipairs(barList) do
        if b == bar then table.remove(barList, i); break end
    end
    bar:Hide()
    bar:SetAlpha(1)
    bar._isPreview = nil
    bar._isTest = nil
    if bar.NameText then bar.NameText:SetText("") end
    if bar.CountText then bar.CountText:SetText("") end
    if bar.TimeText then bar.TimeText:SetText("") end
    if bar.Icon then bar.Icon:SetTexture(nil) end
    bar._iconFlags = 0
    if bar.AlertIcons then
        for _, tex in ipairs(bar.AlertIcons) do
            tex:Hide()
        end
    end
    bar._lastAlertIcon = nil
    bar:SetScript("OnUpdate", nil)
    local fac = Factory()
    if fac then fac:Release(POOL_TYPE, bar) end
    _sortDirty = true
end

-- =============================================================
-- 排列
-- =============================================================
local _sortBuf = {}
local function GetVisibleBarCount()
    local cache = GetRuntimeCache()
    local list = isPreviewing and previewBars or barList
    local count = 0
    for _, bar in ipairs(list) do
        if bar and (bar:IsShown() or isPreviewing) then
            count = count + 1
        end
    end
    if count < 1 then
        count = 1
    end
    if count > cache.maxBars then
        count = cache.maxBars
    end
    return count
end

local function GetAnchorVerticalAdjustment(count)
    local cache = GetRuntimeCache()
    local baseHeight = math.max(20, cache.height)
    local visibleCount = math.max(1, math.min(tonumber(count) or 1, cache.maxBars))
    local totalHeight = baseHeight * visibleCount + cache.spacing * math.max(0, visibleCount - 1)
    local delta = (totalHeight - baseHeight) * 0.5
    if cache.growDir == "DOWN" then
        return -delta
    end
    return delta
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_TimerBarAnchor",
        title = L["计时条"],
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
        initialWidth = DEFAULT_STYLE.width,
        initialHeight = 20,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        getAppliedOffsets = function(_, _, offsetX, offsetY)
            return offsetX, offsetY + GetAnchorVerticalAdjustment(GetVisibleBarCount())
        end,
        normalizeSavedOffsets = function(_, _, offsetX, offsetY)
            return offsetX, offsetY - GetAnchorVerticalAdjustment(GetVisibleBarCount())
        end,
        onCreateFrame = function(_, owner)
            owner:Show()
        end,
        onEditModeChanged = function(_, active, visible)
            if not anchorFrame then
                CreateAnchor()
            end
            if active == true and visible == true then
                if anchorFrame.bg then anchorFrame.bg:Show() end
                if anchorFrame.label then anchorFrame.label:Show() end
                SetPreviewEnabled(true)
            else
                if anchorFrame.bg then anchorFrame.bg:Hide() end
                if anchorFrame.label then anchorFrame.label:Hide() end
                SetPreviewEnabled(false)
            end
        end,
    })

    return anchorController
end

local function ApplyAnchorPosition(count)
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
end

UpdateAnchorFrameSize = function(_)
    if not anchorFrame then return end
    local db = DB() or {}
    local style = ResolveStyle(db)
    local cache = GetRuntimeCache()
    local width = SafeNum(style.width, DEFAULT_STYLE.width)
    if width < 80 then width = 80 end

    local count = math.max(1, math.min(tonumber(_) or 1, cache.maxBars))
    local baseHeight = math.max(20, cache.height)
    local height = baseHeight * count + cache.spacing * math.max(0, count - 1)
    anchorFrame:SetSize(width, height)
end

local function ReLayout(nowOverride)
    if not anchorFrame then return end
    local cache   = GetRuntimeCache()
    local h       = cache.height
    local spacing = cache.spacing
    local growDir = cache.growDir
    local maxBars = cache.maxBars
    local now     = nowOverride or GetTime()

    wipe(_sortBuf)
    local list = isPreviewing and previewBars or barList
    for _, bar in ipairs(list) do table.insert(_sortBuf, bar) end

    table.sort(_sortBuf, function(a, b)
        return (a._castTime - now) < (b._castTime - now)
    end)

    for i, bar in ipairs(_sortBuf) do
        bar:ClearAllPoints()
        if i > maxBars then
            bar:Hide()
        else
            bar:Show()
            local offset = (i - 1) * (h + spacing)
            if growDir == "DOWN" then
                bar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -offset)
            else
                bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, offset)
            end
        end
    end
    local visibleCount = math.max(1, math.min(#_sortBuf, maxBars))
    UpdateAnchorFrameSize(visibleCount)
    ApplyAnchorPosition(visibleCount)
    _sortDirty = false
end

-- =============================================================
-- 倒计时文字
-- =============================================================
local function FormatTime(secs)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    elseif secs >= 10 then
        return string.format("%.0f", secs)
    else
        return string.format("%.1f", secs)
    end
end

-- =============================================================
-- OnUpdate 驱动
-- =============================================================
local function RuntimeTick(elapsed, nowOverride)
    local now = nowOverride or GetTime()
    if _sortDirty then ReLayout(now) end
    if isPreviewing then return end

    _textElapsed = _textElapsed + elapsed
    local updateText = false
    if _textElapsed >= TEXT_UPDATE_INTERVAL then
        _textElapsed = 0
        updateText = true
    end

    local fillMode = GetRuntimeCache().fillMode
    local toRelease = nil

    for timerID, bar in pairs(activeBars) do
        local active = ExBoss.Timeline.Scheduler
                       and ExBoss.Timeline.Scheduler._active
                       and ExBoss.Timeline.Scheduler._active[timerID]
        if not active then
            active = testTimers[timerID]
        end
        if active then
            local remaining = math.max(0, active.castTime - now)
            local duration  = math.max(1, active.timerBarDuration or active.duration or 30)
            if active.fixedAIWaitingTimelineFinish == true then
                bar:SetAlpha(0.62 + 0.38 * math.abs(math.sin(now * 5.5)))
            else
                bar:SetAlpha(1)
            end
            ApplyBarProgress(bar, remaining, duration, fillMode)
            if updateText and bar.TimeText and bar.TimeText:IsShown() then
                bar.TimeText:SetText(FormatTime(remaining))
            end
            if remaining <= 0 and testTimers[timerID] then
                if not toRelease then toRelease = {} end
                table.insert(toRelease, timerID)
            end
        else
            if not toRelease then toRelease = {} end
            table.insert(toRelease, timerID)
        end
    end

    if toRelease then
        for _, id in ipairs(toRelease) do ReleaseBar(id) end
    end
end

local _updateFrame = CreateFrame("Frame")
_updateFrame:Hide()
_updateFrame:SetScript("OnUpdate", function(_, elapsed)
    RuntimeTick(elapsed)
end)
TimerBar._updateFrame = _updateFrame

-- =============================================================
-- 预览模式
-- =============================================================
local function ClearPreviewBars()
    local fac = Factory()
    for i = #previewBars, 1, -1 do
        local bar = previewBars[i]
        bar:Hide()
        bar._isPreview = nil
        if fac then fac:Release(POOL_TYPE, bar) end
        table.remove(previewBars, i)
    end
end

local function ShowPreview()
    ClearPreviewBars()
    local db    = DB()
    local fac   = Factory()
    if not fac then
--         print("|cffff4400ExBoss|r TimerBar: ExwindFactory 不可用，无法创建预览条")
        return
    end
    local count = SafeNum(db and db.maxBars, 5)
    local fillMode = ResolveFillMode(db)
    if count < 1 then count = 1 end
    if count > 8 then count = 8 end
    local now   = GetTime()
    for i = 1, count do
        if not fac or not anchorFrame then break end
        local bar = fac:Acquire(POOL_TYPE, anchorFrame)
        SetClickThrough(bar)
        bar._isPreview = true
        bar._priority  = ((i - 1) % 3) + 1
        bar._castTime  = now + i * 5
        bar._duration  = count * 5
        bar._iconFlags = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1
        if bar.NameText then
            bar.NameText:SetText(IsNonChineseLocale() and ("Sample Spell " .. i) or ("技能示例 " .. i))
        end
        if bar.TimeText  then bar.TimeText:SetText(string.format("%ds", i * 5)) end
        if bar.Icon      then bar.Icon:SetTexture(136197) end
        UpdateBarVisuals(bar, bar._priority)
        local remain = (count - i + 1) * 5
        ApplyBarProgress(bar, remain, count * 5, fillMode)
        table.insert(previewBars, bar)
    end
    ReLayout()
end

SetPreviewEnabled = function(enabled)
    if not anchorFrame then CreateAnchor() end
    enabled = not not enabled
    if enabled == isPreviewing then
        if enabled then
            ShowPreview()
        end
        return
    end

    isPreviewing = enabled
    if enabled then
        for _, bar in pairs(activeBars) do
            bar:Hide()
        end
        ShowPreview()
    else
        ClearPreviewBars()
        for _, bar in pairs(activeBars) do
            bar:Show()
        end
        ReLayout()
    end
end

local function CreateTestBars(count)
    if not anchorFrame then CreateAnchor() end
    if isPreviewing then
        SetPreviewEnabled(false)
    end
    if not Factory() then
--         print("|cffff4400ExBoss|r TimerBar: ExwindFactory 不可用，无法创建测试条")
        return
    end

    count = math.max(1, math.min(tonumber(count) or 5, 12))
    local now = GetTime()
    for i = 1, count do
        _testSeed = _testSeed + 1
        local timerID   = TEST_PREFIX .. tostring(_testSeed)
        local remaining = 3 + i * 3
        local duration  = math.max(remaining + 6, 12)
        local prio      = ((i - 1) % 3) + 1

        testTimers[timerID] = {
            castTime = now + remaining,
            duration = duration,
        }

        TimerBar:AddTimer({
            id          = timerID,
            barPriority = prio,
            castTime    = now + remaining,
            duration    = duration,
            displayName = IsNonChineseLocale() and ("Test Spell " .. i) or ("测试技能 " .. i),
            spellID     = 136197,
            iconFlags   = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1,
        })

        local bar = activeBars[timerID]
        if bar then
            bar._isTest = true
        end
    end
    _sortDirty = true
end

local function ClearTestBars()
    local toRelease = {}
    for timerID in pairs(testTimers) do
        table.insert(toRelease, timerID)
    end
    for _, timerID in ipairs(toRelease) do
        testTimers[timerID] = nil
        ReleaseBar(timerID)
    end
end

-- =============================================================
-- 锚点创建
-- =============================================================
CreateAnchor = function()
    if anchorFrame then return end
    local db = DB()
    local style = ResolveStyle(db)
    local w  = SafeNum(style.width, DEFAULT_STYLE.width)
    if w < 80 then w = 80 end

    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(w, 20)
    anchorFrame:Show()

    -- 编辑模式手柄
    local bg = anchorFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.8, 0, 0.4)
    bg:Hide()
    anchorFrame.bg = bg

    local label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(string.format("|cff00ff00[%s]|r", L["计时条"]))
    label:Hide()
    anchorFrame.label = label
    UpdateAnchorFrameSize(1)
    ApplyAnchorPosition(1)

    _updateFrame:SetParent(anchorFrame)
    SetClickThrough(_updateFrame)
    _updateFrame:Show()
end

-- =============================================================
-- 编辑模式回调
-- =============================================================
local function SetEditMode(enabled)
    if not anchorFrame then CreateAnchor() end
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

-- =============================================================
-- Dispatcher 回调接口
-- =============================================================
function TimerBar:AddTimer(timer)
    if not anchorFrame then CreateAnchor() end
    if activeBars[timer.id] then return end

    local bar = AcquireBar(timer.id, timer.barPriority)
    if not bar then return end

    bar._castTime = timer.castTime
    bar._duration = math.max(1, timer.duration or 30)
    bar._eventColor = timer.eventColor
    bar._timerTextColor = timer.timerTextColor
    bar._iconFlags = GetTimerIconFlags(timer)
    bar._suppressBackdropBorder = IsBlizzardManagedTimer(timer)
    local name, countText = ResolveTimerBarDisplayName(timer)
    bar._occurrenceCountText = countText
    if bar.NameText then bar.NameText:SetText(name or "???") end
    if bar.CountText then bar.CountText:SetText(bar._occurrenceCountText or "") end
    UpdateBarVisuals(bar, timer.barPriority)

    if bar.Icon and timer.spellID then
        local info = C_Spell.GetSpellInfo(timer.spellID)
        if info and info.iconID then
            bar.Icon:SetTexture(info.iconID)
        elseif timer.iconFileID then
            bar.Icon:SetTexture(timer.iconFileID)
        end
    elseif bar.Icon and timer.iconFileID then
        bar.Icon:SetTexture(timer.iconFileID)
    end
    if bar.AlertIcons then
        for _, tex in ipairs(bar.AlertIcons) do
            tex:Hide()
        end
    end
    bar._lastAlertIcon = nil
    UpdateBarVisuals(bar, timer.barPriority)

    if bar.NameText then bar.NameText:SetText(name or "???") end
    if bar.CountText then bar.CountText:SetText(bar._occurrenceCountText or "") end
    ApplyBarProgress(
        bar,
        math.max(0, timer.castTime - GetTime()),
        math.max(1, timer.duration or 30),
        GetRuntimeCache().fillMode
    )

    bar:Show()
    _sortDirty = true
end

function TimerBar:RefreshTimer(timer)
    if type(timer) ~= "table" then
        return
    end
    local bar = activeBars[timer.id]
    if not bar then
        return
    end

    bar._castTime = timer.castTime
    bar._duration = math.max(1, timer.duration or 30)
    bar._eventColor = timer.eventColor
    bar._timerTextColor = timer.timerTextColor
    bar._iconFlags = GetTimerIconFlags(timer)
    bar._suppressBackdropBorder = IsBlizzardManagedTimer(timer)

    local name, countText = ResolveTimerBarDisplayName(timer)
    bar._occurrenceCountText = countText
    if bar.NameText then bar.NameText:SetText(name or "???") end
    if bar.CountText then bar.CountText:SetText(bar._occurrenceCountText or "") end

    if bar.Icon and timer.spellID then
        local info = C_Spell.GetSpellInfo(timer.spellID)
        if info and info.iconID then
            bar.Icon:SetTexture(info.iconID)
        elseif timer.iconFileID then
            bar.Icon:SetTexture(timer.iconFileID)
        end
    elseif bar.Icon and timer.iconFileID then
        bar.Icon:SetTexture(timer.iconFileID)
    end

    UpdateBarVisuals(bar, timer.barPriority)

    if bar.NameText then bar.NameText:SetText(name or "???") end
    if bar.CountText then bar.CountText:SetText(bar._occurrenceCountText or "") end
    ApplyBarProgress(
        bar,
        math.max(0, timer.castTime - GetTime()),
        math.max(1, timer.duration or 30),
        GetRuntimeCache().fillMode
    )
end

function TimerBar:OnPreAlert(timer)
    -- TODO: 进度条脉冲动画
end

function TimerBar:OnCast(timer)
    ReleaseBar(timer.id)
end

function TimerBar:ReleaseAll()
    ClearTestBars()
    for timerID in pairs(activeBars) do
        ReleaseBar(timerID)
    end
end

function TimerBar:RefreshVisuals()
    local db = DB() or {}
    InvalidateRuntimeCache()
    for _, bar in pairs(activeBars) do
        UpdateBarVisuals(bar, bar._priority)
    end
    if isPreviewing then
        ShowPreview()
    else
        ReLayout()
    end
    local visibleCount = GetVisibleBarCount()
    UpdateAnchorFrameSize(visibleCount)
    ApplyAnchorPosition(visibleCount)
end

function TimerBar:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

function TimerBar:SetPreviewEnabled(enabled)
    SetPreviewEnabled(enabled)
end

function TimerBar:TogglePreview()
    SetPreviewEnabled(not isPreviewing)
end

function TimerBar:CreateTestBars(count)
    CreateTestBars(count)
end

function TimerBar:ClearTestBars()
    ClearTestBars()
end

-- =============================================================
-- 初始化
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateAnchor()
    end)
end)

function TimerBar:OnRuntimeTick(elapsed, now)
    RuntimeTick(elapsed, now)
end

TimerBar._active = activeBars
