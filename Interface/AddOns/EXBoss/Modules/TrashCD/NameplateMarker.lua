---@diagnostic disable: undefined-global, undefined-field

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.NameplateMarker or {}
ExBoss.TrashCD.NameplateMarker = Mod
ExBoss.Trash.NameplateMarker = Mod
local BorderUtil = ExBoss.BorderUtil

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end

local OFFSET_Y = 18
local FONT_PATH = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ICON_SIZE = 25
local ICON_GAP = 2
local ICON_CENTER_GAP = 8
local READY_BORDER_DEFAULT = { enabled = true, r = 0.20, g = 0.85, b = 0.20, a = 1 }
local framesByUnit = {}

local cachedAddonType = nil

local function GetNameplateAddonType()
    if cachedAddonType then return cachedAddonType end
    local function loaded(name)
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
            return C_AddOns.IsAddOnLoaded(name) == true
        end
        return IsAddOnLoaded and IsAddOnLoaded(name) == true
    end
    if loaded("Platynator") then
        cachedAddonType = "platynator"
    elseif loaded("EllesmereUINameplates") then
        cachedAddonType = "ellesmere"
    elseif loaded("PlateColor") then
        cachedAddonType = "platecolor"
    elseif loaded("Plater") then
        cachedAddonType = "plater"
    else
        cachedAddonType = "default"
    end
    return cachedAddonType
end

local function GetBorderTexturePath(name)
    local key = tostring(name or "")
    if key == "" or key == "None" then
        return nil
    end
    if LSM and type(LSM.Fetch) == "function" then
        local ok, path = pcall(LSM.Fetch, LSM, "border", key, true)
        if ok and path and path ~= "" then
            return path
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function ApplyIconBorder(icon, cfg, ready, readyCfg)
    local border = icon and icon.border
    if not border then
        return
    end
    local texture = cfg and cfg.show == true and GetBorderTexturePath(cfg.texture) or nil
    if not texture then
        border:Hide()
        return
    end
    local padding = tonumber(cfg.padding) or 0
    local size = math.max(1, tonumber(cfg.size) or 1)
    border:SetFrameLevel(icon:GetFrameLevel() + 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -padding, padding)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", padding, -padding)
    if issecretvalue and (issecretvalue(border:GetWidth()) or issecretvalue(border:GetHeight())) then
        if border.SetBackdrop then
            border:SetBackdrop(nil)
        end
        border:Hide()
        return
    end
    border:SetBackdrop({
        edgeFile = texture,
        edgeSize = size,
    })
    if ready == true and type(readyCfg) == "table" and readyCfg.enabled == true then
        border:SetBackdropBorderColor(readyCfg.r or 0, readyCfg.g or 0, readyCfg.b or 0, readyCfg.a or 1)
    else
        border:SetBackdropBorderColor(cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
    end
    border:Show()
end

local function GetMediaFont(fontKey)
    local key = tostring(fontKey or "")
    if key ~= "" and LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok and lsm and type(lsm.Fetch) == "function" then
            local font = lsm:Fetch("font", key, true)
            if font and font ~= "" then
                return font
            end
        end
    end
    return FONT_PATH
end

local function GetStore()
    return ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
end

local function GetIconLayout()
    local Store = GetStore()
    local enabled = true
    local reverse = false
    local width = ICON_SIZE
    local height = ICON_SIZE
    local offsetX, offsetY = 6, 0
    if Store and type(Store.GetNameplateIconLayout) == "function" then
        enabled, width, height, offsetX, offsetY, reverse = Store.GetNameplateIconLayout()
    else
        if Store and type(Store.GetNameplateIconSize) == "function" then
            width = tonumber(Store.GetNameplateIconSize()) or width
            height = width
        end
        if Store and type(Store.GetNameplateOffset) == "function" then
            offsetX, offsetY = Store.GetNameplateOffset()
        end
    end
    width = math.max(10, math.min(300, tonumber(width) or ICON_SIZE))
    height = math.max(10, math.min(300, tonumber(height) or width))
    offsetX = math.max(-1000, math.min(1000, tonumber(offsetX) or 6))
    offsetY = math.max(-1000, math.min(1000, tonumber(offsetY) or 0))
    return enabled ~= false, width, height, offsetX, offsetY, reverse == true
end

local function GetIconSpacing()
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconSpacing) == "function" then
        return Store.GetNameplateIconSpacing()
    end
    return ICON_GAP
end

local function GetBorderConfig()
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconBorder) == "function" then
        return Store.GetNameplateIconBorder()
    end
    return {
        show = true,
        texture = "Square Full White",
        size = 1,
        padding = 0,
        r = 0, g = 0, b = 0, a = 1,
    }
end

local function GetReadyBorderConfig()
    local Store = GetStore()
    if Store and type(Store.GetNameplateReadyBorder) == "function" then
        return Store.GetNameplateReadyBorder()
    end
    return READY_BORDER_DEFAULT
end

local function GetTextLayout()
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconTextLayout) == "function" then
        return Store.GetNameplateIconTextLayout()
    end
    return {
        r = 1, g = 1, b = 1, a = 1,
        size = 15,
        font = "",
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
    }
end

local function GetIconStrata()
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconStrata) == "function" then
        return Store.GetNameplateIconStrata()
    end
    return "DIALOG"
end

local function ApplyFrameStrata(frame, strata)
    if not frame then
        return
    end
    local value = tostring(strata or "DIALOG"):upper()
    frame:SetFrameStrata(value)
    if frame.SetFixedFrameStrata then
        frame:SetFixedFrameStrata(true)
    end
end

local function GetNameplate(unit)
    local api = _G.C_NamePlate
    if type(api) == "table" and type(api.GetNamePlateForUnit) == "function" then
        local plate = api.GetNamePlateForUnit(unit)
        if plate then
            return plate
        end
    end
    local driver = _G.NamePlateDriverFrame
    if driver and type(driver.GetNamePlateForUnit) == "function" then
        local plate = driver:GetNamePlateForUnit(unit)
        if plate then
            return plate
        end
    end
    return nil
end

local function IsUsableAnchorCandidate(obj, plate)
    if not obj or type(obj.GetObjectType) ~= "function" then
        return false
    end
    if obj.IsForbidden and obj:IsForbidden() then
        return false
    end
    if obj.IsVisible and not obj:IsVisible() then
        return false
    end

    local current = obj
    for _ = 1, 8 do
        if not current or type(current.GetParent) ~= "function" then
            break
        end
        current = current:GetParent()
        if not current then
            break
        end
        if current == plate or current == UIParent or current == WorldFrame then
            return true
        end
        if current.IsForbidden and current:IsForbidden() then
            return false
        end
        if current.IsShown and not current:IsShown() then
            return false
        end
    end

    return true
end

local function ResolvePlateAnchorTarget(plate)
    if type(plate) ~= "table" then
        return nil
    end

    local addonType = GetNameplateAddonType()

    if addonType == "platynator" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if IsUsableAnchorCandidate(child, plate) and child.widgets and child.AurasManager then
                    if type(child.GetChildren) == "function" then
                        local widgets = { child:GetChildren() }
                        for j = 1, #widgets do
                            local widget = widgets[j]
                            local details = widget and widget.details
                            if IsUsableAnchorCandidate(widget, plate) and type(details) == "table" and details.kind == "health" and widget.statusBar then
                                return widget
                            end
                        end
                    end
                    return child
                end
            end
        end

    elseif addonType == "ellesmere" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child.health and child.unit and IsUsableAnchorCandidate(child.health, plate) then
                    return child.health
                end
            end
        end

    elseif addonType == "platecolor" or addonType == "default" then
        local unitFrame = plate.UnitFrame or plate.unitFrame
        if unitFrame and unitFrame.HealthBarsContainer and IsUsableAnchorCandidate(unitFrame, plate) then
            return unitFrame
        end
    end

    local candidates = {
        plate.unitFrame and plate.unitFrame.healthBar,
        plate.UnitFrame and plate.UnitFrame.healthBar,
        plate.unitFrame and plate.unitFrame.HealthBar,
        plate.UnitFrame and plate.UnitFrame.HealthBar,
        plate.unitFrame,
        plate.UnitFrame,
    }

    for i = 1, #candidates do
        local obj = candidates[i]
        if IsUsableAnchorCandidate(obj, plate) then
            return obj
        end
    end

    return plate
end

local function AnchorUnitFrameToPlate(frame, plate)
    if not (frame and plate) then
        return
    end
    local anchorTarget
    if frame._anchorPlate == plate then
        anchorTarget = frame._anchorTarget
    else
        anchorTarget = ResolvePlateAnchorTarget(plate) or plate
        frame._anchorPlate = plate
        frame._anchorTarget = anchorTarget
    end
    frame:ClearAllPoints()
    if type(frame.SetAllPoints) == "function" then
        frame:SetAllPoints(anchorTarget)
    else
        local width = type(anchorTarget.GetWidth) == "function" and anchorTarget:GetWidth() or nil
        local height = type(anchorTarget.GetHeight) == "function" and anchorTarget:GetHeight() or nil
        if issecretvalue and issecretvalue(width) then
            width = nil
        else
            width = tonumber(width)
        end
        if issecretvalue and issecretvalue(height) then
            height = nil
        else
            height = tonumber(height)
        end
        frame:SetSize(width and width > 0 and width or 120, height and height > 0 and height or 28)
        frame:SetPoint("CENTER", anchorTarget, "CENTER", 0, 0)
    end
end

local function EnsureUnitFrame(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local frame = framesByUnit[unit]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetPoint("CENTER")
    ApplyFrameStrata(frame, GetIconStrata())
    frame:SetFrameLevel(6200)
    frame:SetFixedFrameLevel(true)
    frame:SetSize(220, 40)
    frame:EnableMouse(false)
    frame:Hide()

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOM", frame, "TOP", 0, OFFSET_Y)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetDrawLayer("OVERLAY", 7)
    if fs.SetFont then
        fs:SetFont(FONT_PATH, 14, "OUTLINE")
    end
    fs:SetText("")
    frame.text = fs
    frame.leftIcons = {}
    frame.rightIcons = {}
    framesByUnit[unit] = frame
    return frame
end

local function EnsureIconFrame(owner, side, index)
    local pool = side == "left" and owner.leftIcons or owner.rightIcons
    local icon = pool[index]
    if icon then
        return icon
    end

    icon = CreateFrame("Frame", nil, owner)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    ApplyFrameStrata(icon, GetIconStrata())
    icon:SetFrameLevel(owner:GetFrameLevel() + 1)

    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(icon)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.04, 0.04, 0.05, 0.92)
    icon.bg = bg

    local border = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    border:SetFrameLevel(icon:GetFrameLevel() + 1)
    icon.border = border

    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 1, -1)
    texture:SetPoint("BOTTOMRIGHT", -1, 1)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.texture = texture

    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetFrameLevel(icon:GetFrameLevel() + 1)
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(true)
    end
    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(true)
    end
    if cooldown.SetReverse then
        cooldown:SetReverse(false)
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(true)
    end
    cooldown.noCooldownCount = true
    cooldown.noOCC = true
    cooldown:Hide()
    icon.cooldown = cooldown

    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(icon)
    textOverlay:SetFrameLevel(icon:GetFrameLevel() + 2)
    icon.textOverlay = textOverlay

    local count = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("CENTER", 0, 0)
    if count.SetFont then
        count:SetFont(FONT_PATH, 11, "OUTLINE")
    end
    count:SetJustifyH("CENTER")
    count:SetText("")
    icon.count = count

    pool[index] = icon
    return icon
end

local function HideUnusedIcons(pool, startIndex)
    for i = startIndex, #pool do
        local icon = pool[i]
        if icon then
            icon:Hide()
        end
    end
end

local function FormatRemainingText(remaining, ready)
    if ready == true or (tonumber(remaining) or 0) <= 0.05 then
        return ""
    end
    local seconds = math.ceil(math.max(0, tonumber(remaining) or 0))
    return seconds > 0 and tostring(seconds) or ""
end

local function ApplyCooldown(icon, row, reverse)
    if not (icon and icon.cooldown) then
        return
    end
    if row.ready == true then
        icon.cooldown:Hide()
        return
    end
    local duration = tonumber(row.duration) or 0
    local remaining = tonumber(row.remaining) or 0
    if duration <= 0 or remaining <= 0 then
        icon.cooldown:Hide()
        return
    end
    if icon.cooldown.SetReverse then
        icon.cooldown:SetReverse(reverse == true)
    end
    local now = GetTime()
    local startTime = tonumber(row.startTime) or (now + remaining - duration)
    icon.cooldown:SetCooldown(startTime, duration)
    icon.cooldown:Show()
end

local function ApplyTextStyle(icon, layout)
    if not (icon and icon.count) then
        return
    end
    layout = type(layout) == "table" and layout or GetTextLayout()
    icon.count:ClearAllPoints()
    local anchor = icon.textOverlay or icon
    icon.count:SetPoint("CENTER", anchor, "CENTER", tonumber(layout.x) or 0, tonumber(layout.y) or 0)
    if icon.count.SetFont then
        icon.count:SetFont(GetMediaFont(layout.font), tonumber(layout.size) or 11, tostring(layout.outline or "OUTLINE"))
    end
    icon.count:SetTextColor(tonumber(layout.r) or 1, tonumber(layout.g) or 1, tonumber(layout.b) or 1, tonumber(layout.a) or 1)
    if layout.shadow == false then
        icon.count:SetShadowOffset(0, 0)
    else
        icon.count:SetShadowOffset(tonumber(layout.shadowX) or 1, tonumber(layout.shadowY) or -1)
        icon.count:SetShadowColor(0, 0, 0, 0.9)
    end
end

function Mod.HideAll()
    for _, frame in pairs(framesByUnit) do
        if frame and frame.text then
            frame.text:SetText("")
            frame:Hide()
            HideUnusedIcons(frame.leftIcons or {}, 1)
            HideUnusedIcons(frame.rightIcons or {}, 1)
        end
    end
end

function Mod.HideUnit(unit)
    if type(unit) ~= "string" then
        return
    end
    local frame = framesByUnit[unit]
    if not frame then
        return
    end
    if frame.text then
        frame.text:SetText("")
    end
    HideUnusedIcons(frame.leftIcons or {}, 1)
    HideUnusedIcons(frame.rightIcons or {}, 1)
    frame:Hide()
end

function Mod.SetUnitText(unit, textValue, recognized)
    if type(unit) ~= "string" then
        return
    end
    local plate = GetNameplate(unit)
    if not plate then
        Mod.HideUnit(unit)
        return
    end

    local frame = EnsureUnitFrame(unit)
    if not frame or not frame.text then
        return
    end

    ApplyFrameStrata(frame, GetIconStrata())
    AnchorUnitFrameToPlate(frame, plate)
    local Store = GetStore()
    if Store and type(Store.IsNameplateNPCIDHidden) == "function" and Store.IsNameplateNPCIDHidden() == true then
        frame.text:SetText("")
        frame:Show()
        return
    end
    local text = tostring(textValue or "???")
    frame.text:SetText(text)
    if string.find(text, "|c", 1, true) then
        frame.text:SetTextColor(1.00, 1.00, 1.00)
    elseif recognized == true then
        frame.text:SetTextColor(0.20, 1.00, 0.35)
    else
        frame.text:SetTextColor(1.00, 0.25, 0.25)
    end
    frame:Show()
end

function Mod.SetUnitTimers(unit, timers)
    if type(unit) ~= "string" then
        return
    end
    local plate = GetNameplate(unit)
    local frame = plate and EnsureUnitFrame(unit) or nil
    if not frame then
        Mod.HideUnit(unit)
        return
    end

    local strata = GetIconStrata()
    ApplyFrameStrata(frame, strata)
    AnchorUnitFrameToPlate(frame, plate)

    local iconsEnabled, iconWidth, iconHeight, offsetX, offsetY, reverseCooldown = GetIconLayout()
    local textLayout = GetTextLayout()
    local borderConfig = GetBorderConfig()
    local readyBorderConfig = GetReadyBorderConfig()
    local iconGap = GetIconSpacing()
    if iconsEnabled ~= true then
        HideUnusedIcons(frame.leftIcons or {}, 1)
        HideUnusedIcons(frame.rightIcons or {}, 1)
        frame:Show()
        return
    end

    local left, right = {}, {}
    for i = 1, #(timers or {}) do
        local row = timers[i]
        if type(row) == "table" and tonumber(row.spellID) then
            if tostring(row.side or "right") == "left" then
                left[#left + 1] = row
            else
                right[#right + 1] = row
            end
        end
    end

    for i = 1, #left do
        local row = left[i]
        local icon = EnsureIconFrame(frame, "left", i)
        ApplyFrameStrata(icon, strata)
        icon:SetSize(iconWidth, iconHeight)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("RIGHT", frame, "LEFT", -ICON_CENTER_GAP + offsetX, offsetY)
        else
            icon:SetPoint("RIGHT", frame.leftIcons[i - 1], "LEFT", -iconGap, 0)
        end
        icon.texture:SetTexture(tonumber(row.iconFileID) or 136243)
        icon.texture:SetDesaturated(false)
        ApplyCooldown(icon, row, reverseCooldown)
        ApplyTextStyle(icon, textLayout)
        icon.count:SetText(FormatRemainingText(row.remaining, row.ready))
        ApplyIconBorder(icon, borderConfig, row.ready, readyBorderConfig)
        icon:Show()
    end
    HideUnusedIcons(frame.leftIcons, #left + 1)

    for i = 1, #right do
        local row = right[i]
        local icon = EnsureIconFrame(frame, "right", i)
        ApplyFrameStrata(icon, strata)
        icon:SetSize(iconWidth, iconHeight)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("LEFT", frame, "RIGHT", ICON_CENTER_GAP + offsetX, offsetY)
        else
            icon:SetPoint("LEFT", frame.rightIcons[i - 1], "RIGHT", iconGap, 0)
        end
        icon.texture:SetTexture(tonumber(row.iconFileID) or 136243)
        icon.texture:SetDesaturated(false)
        ApplyCooldown(icon, row, reverseCooldown)
        ApplyTextStyle(icon, textLayout)
        icon.count:SetText(FormatRemainingText(row.remaining, row.ready))
        ApplyIconBorder(icon, borderConfig, row.ready, readyBorderConfig)
        icon:Show()
    end
    HideUnusedIcons(frame.rightIcons, #right + 1)
end
