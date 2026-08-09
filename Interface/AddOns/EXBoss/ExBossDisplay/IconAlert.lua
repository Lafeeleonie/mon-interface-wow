---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/IconAlert.lua
-- 通用图标容器：由其他模块通过 API 推入条目，统一负责图标/扫光/发光/堆叠布局。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.IconAlert = ExBoss.UI.IconAlert or {}
local IconAlert = ExBoss.UI.IconAlert
local BorderUtil = ExBoss.BorderUtil

local MODULE_KEY = "ExBoss.IconAlert"

local DEFAULTS = {
    enabled = true,
    anchorX = 0,
    anchorY = -40,
    attachToCustom = false,
    customAttachTarget = "",
    growDir = "RIGHT",
    spacing = 8,
    maxVisible = 5,
    showText = true,
    font_text = {
        font = "默认",
        size = 13,
        outline = "OUTLINE",
        r = 1,
        g = 0.82,
        b = 0.2,
        a = 1,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
        x = 0,
        y = -4,
    },
    icon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 64,
        height = 64,
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
    glowEnabled = false,
    glowStyle = "Pixel Glow",
    glowColorR = 1,
    glowColorG = 0.82,
    glowColorB = 0,
    glowColorA = 1,
    glowFrequency = 0.25,
    glowLines = 8,
    glowScale = 1,
    glowOffset = 0,
}

local GLOW_DEFAULT_COLOR = { 1, 0.82, 0, 1 }
local frame
local anchorController
local contentFrame
local editOverlay
local editLabel
local updateFrame
local editMode = false
local pool = {}
local active = {}
local activeOrder = {}
local serial = 0
local EnsureAnchorController
local ShowEditPreview

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

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function ClampInt(v, minValue, maxValue, def)
    local n = math.floor((tonumber(v) or tonumber(def) or minValue) + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
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
    ExBossDB.timer.iconAlert = ExBossDB.timer.iconAlert or {}
    local db = ExBossDB.timer.iconAlert
    ApplyDefaults(db, DEFAULTS)
    return db
end

local function IsTargetAlertDebugEnabled()
    return ExBoss and ExBoss.Debug and ExBoss.Debug.TargetAlert and ExBoss.Debug.TargetAlert.enabled == true
end

local function IconAlertDebug(msg)
    if not IsTargetAlertDebugEnabled() then
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9f7bffExBoss IconAlert|r " .. tostring(msg or ""))
    end
end

local function GetLSMTexture(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(LSM.Fetch) == "function" and type(name) == "string" and name ~= "" then
        local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name, true)
        if ok and path then
            return path
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function GetGlowLib()
    if LibStub then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibCustomGlow-1.0", true)
        if ok then
            return lib
        end
    end
    return nil
end

local function BuildGlowOptions(db)
    return {
        enabled = db.glowEnabled == true,
        style = tostring(db.glowStyle or DEFAULTS.glowStyle),
        color = {
            Clamp01(db.glowColorR, DEFAULTS.glowColorR),
            Clamp01(db.glowColorG, DEFAULTS.glowColorG),
            Clamp01(db.glowColorB, DEFAULTS.glowColorB),
            Clamp01(db.glowColorA, DEFAULTS.glowColorA),
        },
        frequency = tonumber(db.glowFrequency) or DEFAULTS.glowFrequency,
        lines = ClampInt(db.glowLines, 1, 30, DEFAULTS.glowLines),
        scale = tonumber(db.glowScale) or DEFAULTS.glowScale,
        offset = tonumber(db.glowOffset) or DEFAULTS.glowOffset,
    }
end

local function StartWidgetGlow(target, key, opts)
    if not target or type(opts) ~= "table" or opts.enabled == false then
        return nil
    end
    local lib = GetGlowLib()
    local style = tostring(opts.style or "Pixel Glow")
    local color = opts.color or GLOW_DEFAULT_COLOR
    local lines = math.max(1, math.floor(tonumber(opts.lines) or 8))
    local frequency = tonumber(opts.frequency) or 0.25
    local scale = tonumber(opts.scale) or 1
    local offset = tonumber(opts.offset) or 0
    if lib then
        if style == "Action Button Glow" and type(lib.ButtonGlow_Start) == "function" then
            lib.ButtonGlow_Start(target, color, frequency, 20)
            return "lib_action"
        elseif style == "Autocast Shine" and type(lib.AutoCastGlow_Start) == "function" then
            lib.AutoCastGlow_Start(target, color, lines, frequency, scale, offset, offset, key, 20)
            return "lib_autocast"
        elseif style == "Proc Glow" and type(lib.ProcGlow_Start) == "function" then
            lib.ProcGlow_Start(target, {
                key = key,
                color = color,
                frameLevel = 20,
                xOffset = offset,
                yOffset = offset,
                duration = 1,
            })
            return "lib_proc"
        elseif type(lib.PixelGlow_Start) == "function" then
            lib.PixelGlow_Start(target, color, lines, frequency, nil, scale, offset, offset, false, key, 20)
            return "lib_pixel"
        end
    end

    target.__ExBossIconAlertFallbackGlow = target.__ExBossIconAlertFallbackGlow or CreateFrame("Frame", nil, target, "BackdropTemplate")
    local glow = target.__ExBossIconAlertFallbackGlow
    glow:SetFrameStrata(target:GetFrameStrata())
    glow:SetFrameLevel((target:GetFrameLevel() or 1) + 20)
    ApplyBackdropBorder(
        glow,
        target,
        "Interface\\Buttons\\WHITE8X8",
        math.max(1, scale),
        3 + offset,
        color[1] or 1,
        color[2] or 0.82,
        color[3] or 0,
        color[4] or 1,
        (target:GetFrameLevel() or 1) + 20
    )
    glow:Show()
    return "fallback"
end

local function StopWidgetGlow(target, key, mode)
    if not target then
        return
    end
    local lib = GetGlowLib()
    if mode == "lib_pixel" and lib and type(lib.PixelGlow_Stop) == "function" then
        lib.PixelGlow_Stop(target, key)
    elseif mode == "lib_autocast" and lib and type(lib.AutoCastGlow_Stop) == "function" then
        lib.AutoCastGlow_Stop(target, key)
    elseif mode == "lib_proc" and lib and type(lib.ProcGlow_Stop) == "function" then
        lib.ProcGlow_Stop(target, key)
    elseif mode == "lib_action" and lib and type(lib.ButtonGlow_Stop) == "function" then
        lib.ButtonGlow_Stop(target)
    elseif target.__ExBossIconAlertFallbackGlow then
        HideBackdropBorder(target.__ExBossIconAlertFallbackGlow)
    end
end

local function NormalizeOwner(owner)
    local t = type(owner)
    if t == "table" or t == "string" or t == "number" or t == "boolean" then
        return owner
    end
    return nil
end

local function StableOwnerKey(owner)
    local t = type(owner)
    if t == "string" or t == "number" or t == "boolean" then
        return tostring(owner)
    end
    if t ~= "table" then
        return nil
    end
    if type(owner.key) == "string" and owner.key ~= "" then
        return owner.key
    end
    if type(owner.id) == "string" or type(owner.id) == "number" then
        return tostring(owner.id)
    end
    local parts = {}
    for _, k in ipairs({ "source", "kind", "eventID", "spellID", "mapID", "npcID", "unit", "castBarID", "castKind" }) do
        local v = owner[k]
        if v ~= nil then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    if #parts > 0 then
        return table.concat(parts, "|")
    end
    return tostring(owner)
end

local function DoesOwnerMatch(lhs, rhs)
    if lhs == rhs then
        return true
    end
    local lt, rt = type(lhs), type(rhs)
    if lt ~= rt then
        return false
    end
    if lt == "string" or lt == "number" or lt == "boolean" then
        return tostring(lhs) == tostring(rhs)
    end
    if lt ~= "table" then
        return false
    end
    return StableOwnerKey(lhs) == StableOwnerKey(rhs)
end

local function ResolveTexture(entry, db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    local forced = tonumber(iconDB.iconID)
    if forced then
        if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, tex = pcall(C_Spell.GetSpellTexture, forced)
            if ok and tex then
                return tex
            end
        end
        if type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, forced)
            if ok and tex then
                return tex
            end
        end
        return forced
    end
    if entry and entry.icon then
        return entry.icon
    end
    local spellID = tonumber(entry and entry.spellID)
    if spellID and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    if spellID and type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function CellWidth(db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    return math.max(1, SafeNum(iconDB.width, DEFAULTS.icon.width))
end

local function CellHeight(db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    local height = math.max(1, SafeNum(iconDB.height, DEFAULTS.icon.height))
    if db.showText ~= false then
        height = height + 24
    end
    return height
end

local function ResolveDisplayName(entry)
    local text = tostring(type(entry) == "table" and entry.text or "")
    if text ~= "" then
        return text
    end
    local displayName = tostring(type(entry) == "table" and entry.displayName or "")
    if displayName ~= "" then
        return displayName
    end
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if spellID and type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return ""
end

local function ApplyFont(fs, fontDB, defSize)
    if not fs or not fontDB then
        return
    end
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
    fs:SetFont(path, SafeNum(fontDB.size, defSize or 13), fontDB.outline or "OUTLINE")
    fs:SetTextColor(
        SafeNum(fontDB.r, 1),
        SafeNum(fontDB.g, 1),
        SafeNum(fontDB.b, 1),
        SafeNum(fontDB.a, 1)
    )
    if fontDB.shadow then
        fs:SetShadowOffset(SafeNum(fontDB.shadowX, 1), SafeNum(fontDB.shadowY, -1))
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end
end

local function StopRecordGlow(record)
    if type(record) ~= "table" then
        return
    end
    if record.glowMode then
        StopWidgetGlow(record.iconFrame, record.glowKey, record.glowMode)
        record.glowMode = nil
    end
end

local function ApplyRecordVisual(record, db)
    if type(record) ~= "table" or not record.frame then
        return
    end
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    local iconW = math.max(1, SafeNum(iconDB.width, DEFAULTS.icon.width))
    local iconH = math.max(1, SafeNum(iconDB.height, DEFAULTS.icon.height))
    local offsetX = 0
    local offsetY = 0
    local cellW = CellWidth(db)
    local cellH = CellHeight(db)
    local fontDB = type(db.font_text) == "table" and db.font_text or DEFAULTS.font_text

    record.frame:SetSize(cellW, cellH)
    record.iconFrame:SetSize(iconW, iconH)
    record.iconFrame:ClearAllPoints()
    record.iconFrame:SetPoint("TOP", record.frame, "TOP", offsetX, -math.max(0, offsetY))

    record.texture:SetTexture(ResolveTexture(record.entry, db))
    record.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    record.texture:SetAllPoints(record.iconFrame)

    record.cooldown:ClearAllPoints()
    record.cooldown:SetAllPoints(record.iconFrame)
    if record.cooldown.SetReverse then
        record.cooldown:SetReverse(iconDB.reverse == true)
    end
    if record.cooldown.SetHideCountdownNumbers then
        record.cooldown:SetHideCountdownNumbers(type(record.entry) == "table" and record.entry.hideCountdownNumbers == true)
    end

    if iconDB.showBorder == true then
        ApplyBackdropBorder(
            record.border,
            record.iconFrame,
            GetLSMTexture(iconDB.borderTexture or DEFAULTS.icon.borderTexture),
            math.max(1, SafeNum(iconDB.borderSize, DEFAULTS.icon.borderSize)),
            SafeNum(iconDB.borderPadding, 0),
            Clamp01(iconDB.borderColorR, DEFAULTS.icon.borderColorR),
            Clamp01(iconDB.borderColorG, DEFAULTS.icon.borderColorG),
            Clamp01(iconDB.borderColorB, DEFAULTS.icon.borderColorB),
            Clamp01(iconDB.borderColorA, DEFAULTS.icon.borderColorA),
            (record.iconFrame:GetFrameLevel() or 1) + 3
        )
    else
        HideBackdropBorder(record.border)
    end

    if record.nameText then
        ApplyFont(record.nameText, fontDB, 13)
        record.nameText:ClearAllPoints()
        record.nameText:SetPoint("TOP", record.iconFrame, "BOTTOM", SafeNum(fontDB.x, 0), SafeNum(fontDB.y, -4))
        record.nameText:SetPoint("LEFT", record.frame, "LEFT", -20 + SafeNum(fontDB.x, 0), 0)
        record.nameText:SetPoint("RIGHT", record.frame, "RIGHT", 20 + SafeNum(fontDB.x, 0), 0)
        if db.showText ~= false then
            record.nameText:SetText(ResolveDisplayName(record.entry))
            record.nameText:Show()
        else
            record.nameText:SetText("")
            record.nameText:Hide()
        end
    end

    if type(record.entry) == "table" and record.entry.hideCooldown == true then
        if record.cooldown and record.cooldown.Clear then
            record.cooldown:Clear()
        elseif record.cooldown and record.cooldown.SetCooldown then
            record.cooldown:SetCooldown(0, 0)
        end
        record.cooldown:Hide()
    elseif record.entry and record.entry.previewStatic == true and editMode then
        if record.cooldown and record.cooldown.Clear then
            record.cooldown:Clear()
        elseif record.cooldown and record.cooldown.SetCooldown then
            record.cooldown:SetCooldown(0, 0)
        end
        record.cooldown:Hide()
    else
        record.cooldown:Show()
    end

    StopRecordGlow(record)
    if db.glowEnabled == true then
        record.glowKey = "iconalert:" .. tostring(record.key)
        record.glowMode = StartWidgetGlow(record.iconFrame, record.glowKey, BuildGlowOptions(db))
    end
end

local function NewRecordFrame()
    local holder = CreateFrame("Frame", nil, contentFrame or frame)
    holder:SetFrameStrata("DIALOG")
    holder:SetFrameLevel(((contentFrame or frame):GetFrameLevel() or 1) + 5)
    SetClickThrough(holder)

    local iconFrame = CreateFrame("Frame", nil, holder)
    iconFrame:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    SetClickThrough(iconFrame)

    local tex = iconFrame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(iconFrame)

    local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(iconFrame)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(true)
    cooldown:SetHideCountdownNumbers(false)
    if cooldown.SetSwipeTexture then
        cooldown:SetSwipeTexture("Interface\\Cooldown\\star4")
    end

    local border = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    border:SetFrameLevel((iconFrame:GetFrameLevel() or 1) + 3)
    SetClickThrough(border)

    local nameText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("TOP", iconFrame, "BOTTOM", 0, -2)
    nameText:SetJustifyH("CENTER")
    nameText:SetJustifyV("TOP")
    nameText:SetWordWrap(false)
    if nameText.SetNonSpaceWrap then
        nameText:SetNonSpaceWrap(false)
    end
    if nameText.SetMaxLines then
        nameText:SetMaxLines(1)
    end
    nameText:Hide()

    record = {
        frame = holder,
        iconFrame = iconFrame,
        texture = tex,
        cooldown = cooldown,
        border = border,
        nameText = nameText,
    }
    return record
end

local function AcquireRecordFrame()
    local record = table.remove(pool)
    if record then
        record.frame:SetParent(contentFrame or frame)
        return record
    end
    return NewRecordFrame()
end

local function ReleaseRecord(record)
    if type(record) ~= "table" then
        return
    end
    StopRecordGlow(record)
    record.key = nil
    record.owner = nil
    record.entry = nil
    record.expiresAt = nil
    record.duration = nil
    record.startsAt = nil
    if record.nameText then
        record.nameText:SetText("")
        record.nameText:Hide()
    end
    if record.cooldown and record.cooldown.Clear then
        record.cooldown:Clear()
    elseif record.cooldown and record.cooldown.SetCooldown then
        record.cooldown:SetCooldown(0, 0)
    end
    if record.frame then
        record.frame:Hide()
        record.frame:ClearAllPoints()
        record.frame:SetParent(UIParent)
    end
    pool[#pool + 1] = record
end

local function RemoveRecordByKey(key)
    local record = active[key]
    if not record then
        return
    end
    active[key] = nil
    for i = #activeOrder, 1, -1 do
        if activeOrder[i] == key then
            table.remove(activeOrder, i)
            break
        end
    end
    ReleaseRecord(record)
end

local function LayoutRecords()
    if not frame or not contentFrame then
        return
    end
    local db = DB()
    local cellW = CellWidth(db)
    local cellH = CellHeight(db)
    local spacing = SafeNum(db.spacing, DEFAULTS.spacing)
    local growDir = tostring(db.growDir or DEFAULTS.growDir)
    local maxVisible = ClampInt(db.maxVisible, 1, 12, DEFAULTS.maxVisible)
    local visibleCount = math.min(maxVisible, #activeOrder)
    local totalW = cellW
    local totalH = cellH
    if growDir == "RIGHT" or growDir == "LEFT" then
        totalW = math.max(cellW, (visibleCount * cellW) + math.max(0, visibleCount - 1) * spacing)
        totalH = cellH
    else
        totalW = cellW
        totalH = math.max(cellH, (visibleCount * cellH) + math.max(0, visibleCount - 1) * spacing)
    end
    frame:SetSize(totalW, totalH)
    contentFrame:SetAllPoints(frame)

    for i = 1, #activeOrder do
        local record = active[activeOrder[i]]
        if record and record.frame then
            local isEditPreview = (record.entry and record.entry.previewStatic == true and editMode == true)
            if i <= maxVisible and ((db.enabled == true and db.icon.showIcon == true) or isEditPreview) then
                record.frame:Show()
                record.frame:ClearAllPoints()
                local offset = i - 1
                if growDir == "RIGHT" then
                    record.frame:SetPoint("LEFT", contentFrame, "LEFT", offset * (cellW + spacing), 0)
                elseif growDir == "LEFT" then
                    record.frame:SetPoint("RIGHT", contentFrame, "RIGHT", -(offset * (cellW + spacing)), 0)
                elseif growDir == "UP" then
                    record.frame:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, offset * (cellH + spacing))
                else
                    record.frame:SetPoint("TOP", contentFrame, "TOP", 0, -(offset * (cellH + spacing)))
                end
            else
                record.frame:Hide()
            end
        end
    end

    if visibleCount > 0 or editMode then
        frame:Show()
    else
        frame:Hide()
    end
end

local function RefreshAllActiveVisuals()
    local db = DB()
    for i = 1, #activeOrder do
        local record = active[activeOrder[i]]
        if record then
            ApplyRecordVisual(record, db)
        end
    end
    LayoutRecords()
end

local function StopAllActive()
    for i = #activeOrder, 1, -1 do
        RemoveRecordByKey(activeOrder[i])
    end
    if frame and not editMode then
        frame:Hide()
    end
end

local function UpdateTick()
    local now = GetTime()
    local changed = false
    for i = #activeOrder, 1, -1 do
        local key = activeOrder[i]
        local record = active[key]
        if record and record.entry and record.entry.previewStatic == true and editMode then
            -- 编辑模式下固定展示静态样本，不参与倒计时。
        elseif not record or SafeNum(record.expiresAt, 0) <= now then
            RemoveRecordByKey(key)
            changed = true
        end
    end
    if changed then
        LayoutRecords()
    elseif #activeOrder == 0 and not editMode and frame then
        frame:Hide()
    end
end

local function EnsurePoolSize()
    local count = ClampInt(DB().maxVisible, 1, 12, DEFAULTS.maxVisible)
    while (#pool + #activeOrder) < count do
        pool[#pool + 1] = NewRecordFrame()
    end
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_IconAlertAnchor",
        title = "图标提示",
        getDB = DB,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        syncWidgets = {
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = math.max(20, SafeNum(DEFAULTS.icon.width, 64)),
        initialHeight = math.max(20, SafeNum(DEFAULTS.icon.height, 64)),
        clampedToScreen = false,
        frameStrata = "DIALOG",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
        onEditModeChanged = function(_, activeMode, visible)
            editMode = activeMode == true and visible == true
            if editOverlay then
                editOverlay:Hide()
            end
            if editLabel then
                editLabel:Hide()
            end
            if editMode then
                ShowEditPreview()
            else
                StopAllActive()
            end
        end,
    })

    return anchorController
end

local function ApplyAnchorPosition()
    if not frame then
        return
    end
    EnsureAnchorController():ApplyPosition()
end

ShowEditPreview = function()
    if not editMode then
        return
    end
    StopAllActive()
    local samples = {
        118,
        642,
        853,
        6940,
    }
    for i = 1, #samples do
        IconAlert:ShowEntry({
            owner = { key = "edit-preview:" .. tostring(i) },
            spellID = samples[i],
            duration = 5,
            endTime = GetTime() + 5,
            previewStatic = true,
        })
    end
end

local function Ensure()
    if frame then
        return true
    end

    frame = EnsureAnchorController():Ensure()

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetAllPoints(frame)
    SetClickThrough(contentFrame)

    editOverlay = frame:CreateTexture(nil, "ARTWORK")
    editOverlay:SetAllPoints()
    editOverlay:SetColorTexture(0, 0.55, 1, 0.20)
    editOverlay:Hide()

    editLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editLabel:SetPoint("TOP", frame, "TOP", 0, -4)
    editLabel:SetText("|cff55bbff[图标]|r")
    editLabel:Hide()

    updateFrame = CreateFrame("Frame", nil, frame)
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        updateFrame._elapsed = SafeNum(updateFrame._elapsed, 0) + elapsed
        if updateFrame._elapsed < 0.05 then
            return
        end
        updateFrame._elapsed = 0
        UpdateTick()
    end)

    ApplyAnchorPosition()
    EnsurePoolSize()
    return true
end

local function SetEditMode(enabled)
    if not Ensure() then
        return
    end
    EnsureAnchorController():RefreshEditMode(enabled == true, enabled == true)
end

EnsureAnchorController():RegisterEditModeHandler()

function IconAlert:ShowEntry(entry, forcedRemaining)
    if not Ensure() then
        IconAlertDebug("show-skip reason=ensure-failed")
        return nil
    end
    local db = DB()
    local isEditPreview = (type(entry) == "table" and entry.previewStatic == true and editMode == true)
    if (not isEditPreview) and (db.enabled ~= true or db.icon.showIcon ~= true or type(entry) ~= "table") then
        IconAlertDebug(string.format(
            "show-skip reason=gated enabled=%s showIcon=%s entryType=%s spell=%s",
            tostring(db.enabled == true),
            tostring(type(db.icon) == "table" and db.icon.showIcon == true),
            tostring(type(entry)),
            tostring(type(entry) == "table" and entry.spellID or "nil")
        ))
        return nil
    end

    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    local now = GetTime()
    local expiresAt
    if remaining ~= nil then
        expiresAt = now + math.max(0, remaining)
    else
        expiresAt = SafeNum(entry.endTime, now + duration)
        remaining = math.max(0, expiresAt - now)
    end
    if remaining <= 0 then
        IconAlertDebug(string.format(
            "show-skip reason=expired remaining=%s duration=%s spell=%s",
            tostring(remaining),
            tostring(duration),
            tostring(entry.spellID or "nil")
        ))
        return nil
    end

    local owner = NormalizeOwner(entry.owner or entry.key)
    local key = StableOwnerKey(owner)
    if not key or key == "" then
        serial = serial + 1
        key = "anon:" .. tostring(serial)
    end

    local record = active[key]
    if not record then
        record = AcquireRecordFrame()
        active[key] = record
        activeOrder[#activeOrder + 1] = key
    end

    record.key = key
    record.owner = owner
    record.entry = entry
    record.duration = duration
    record.expiresAt = expiresAt
    record.startsAt = expiresAt - duration
    ApplyRecordVisual(record, db)
    if type(record.entry) == "table" and record.entry.hideCooldown == true then
        if record.cooldown and record.cooldown.Clear then
            record.cooldown:Clear()
        elseif record.cooldown and record.cooldown.SetCooldown then
            record.cooldown:SetCooldown(0, 0)
        end
    elseif record.entry and record.entry.previewStatic == true and editMode then
        if record.cooldown and record.cooldown.Clear then
            record.cooldown:Clear()
        elseif record.cooldown and record.cooldown.SetCooldown then
            record.cooldown:SetCooldown(0, 0)
        end
    elseif record.cooldown and record.cooldown.SetCooldown then
        record.cooldown:SetCooldown(record.startsAt, duration)
    end
    LayoutRecords()
    IconAlertDebug(string.format(
        "show-ok key=%s spell=%s duration=%s remaining=%s text=%s",
        tostring(key),
        tostring(entry.spellID or "nil"),
        tostring(duration),
        tostring(remaining),
        tostring(ResolveDisplayName(entry) or "")
    ))
    return key
end

function IconAlert:ShowSequence(sequence, opts)
    if type(sequence) ~= "table" then
        return 0
    end
    local count = 0
    opts = type(opts) == "table" and opts or {}
    for i = 1, #sequence do
        local row = type(sequence[i]) == "table" and sequence[i] or nil
        if row then
            if row.owner == nil and opts.ownerPrefix then
                row.owner = tostring(opts.ownerPrefix) .. ":" .. tostring(i)
            end
            if self:ShowEntry(row, row.forcedRemaining) then
                count = count + 1
            end
        end
    end
    return count
end

function IconAlert:StopByOwner(owner)
    local removed = 0
    for i = #activeOrder, 1, -1 do
        local key = activeOrder[i]
        local record = active[key]
        if record and DoesOwnerMatch(record.owner, owner) then
            RemoveRecordByKey(key)
            removed = removed + 1
        end
    end
    LayoutRecords()
    return removed
end

function IconAlert:Hide()
    StopAllActive()
end

function IconAlert:IsPlaying()
    return #activeOrder > 0
end

function IconAlert:Preview(count, seconds)
    if not Ensure() then
        return
    end
    StopAllActive()
    local now = GetTime()
    local duration = math.max(0.2, SafeNum(seconds, 6))
    local total = ClampInt(count, 1, 8, 4)
    local sample = { 118, 642, 853, 6940, 20484, 1953, 527, 116849 }
    for i = 1, total do
        self:ShowEntry({
            owner = { key = "preview:" .. tostring(i) },
            duration = duration,
            endTime = now + duration - ((i - 1) * 0.35),
            spellID = sample[i] or sample[1],
        })
    end
end

function IconAlert:RefreshVisuals()
    if not frame then
        if not Ensure() then
            return
        end
    end
    if ExwindTools.GlobalEditMode == true and editMode ~= true then
        SetEditMode(true)
    elseif ExwindTools.GlobalEditMode ~= true and editMode == true then
        SetEditMode(false)
    end
    ApplyAnchorPosition()
    EnsurePoolSize()
    RefreshAllActiveVisuals()
    if editMode and #activeOrder == 0 then
        ShowEditPreview()
    end
end

function IconAlert:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        if Ensure() then
            IconAlert:RefreshVisuals()
        end
    end)
end)

ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_KEY .. "_combat_init", function()
    if frame then
        return
    end
    if Ensure() then
        IconAlert:RefreshVisuals()
    end
end)

C_Timer.After(0, function()
    if frame then
        return
    end
    if Ensure() then
        IconAlert:RefreshVisuals()
    end
end)
