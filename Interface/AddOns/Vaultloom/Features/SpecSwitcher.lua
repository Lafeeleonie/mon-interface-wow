local _, Addon = ...

local FEATURE_ID = "spec_switcher"
local DOMAIN_ID = "feature.specSwitcher"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICON_TEXEL_INSET = 3 / 64
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SCALE_MIN = 0.70
local SCALE_MAX = 1.45
local SCALE_STEP = 0.05
local MAX_PENDING_ATTEMPTS = 6
local DEFAULT_POSITION = {
    point = "TOP",
    relativePoint = "TOP",
    x = 0,
    y = -220,
}
local RING_COLORS = {
    gold = { 0.92, 0.76, 0.24 },
    cyan = { 0.20, 0.82, 0.92 },
    green = { 0.30, 0.86, 0.42 },
    red = { 0.94, 0.24, 0.20 },
    purple = { 0.68, 0.38, 0.92 },
}
local INACTIVE_RING = { 0.48, 0.48, 0.50 }
local PENDING_RING = { 1.00, 0.55, 0.08 }

local Runtime = {
    enabled = false,
    frame = nil,
    menu = nil,
    buttons = {},
    menuRows = {},
    model = nil,
    pending = nil,
    requestSerial = 0,
}

Addon.SpecSwitcher = Runtime

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function positiveInteger(value)
    value = math.floor(tonumber(value) or 0)
    return value > 0 and value or nil
end

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function inCombat()
    return Addon.WoWApi:IsInCombatLockdown()
end

local function getActiveRingColor()
    local colorKey = setting("ring_color")
    if colorKey ~= "class" and RING_COLORS[colorKey] then
        return unpack(RING_COLORS[colorKey])
    end
    local classFile
    if type(UnitClass) == "function" then
        local ok, _, value = pcall(UnitClass, "player")
        if ok then classFile = value end
    end
    local colors = type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS
        or type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS
    local color = colors and colors[classFile] or nil
    if color then
        return tonumber(color.r) or 1, tonumber(color.g) or 0.82, tonumber(color.b) or 0.24
    end
    return unpack(RING_COLORS.gold)
end

local function getBarOpacity()
    return clamp(setting("bar_opacity_percent"), 30, 100) / 100
end

local function showMessage(message)
    if type(message) == "string" and message ~= "" then
        Addon:Print(message)
    end
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.specSwitcher = type(db.features.specSwitcher) == "table"
        and db.features.specSwitcher or {}
    local store = db.features.specSwitcher
    store.position = type(store.position) == "table" and store.position or {}
    store.scale = clamp(store.scale, SCALE_MIN, SCALE_MAX)
    return store
end

local function applyPosition(frame)
    if not frame then return end
    local position = getStore().position
    frame:ClearAllPoints()
    frame:SetPoint(
        type(position.point) == "string" and position.point or DEFAULT_POSITION.point,
        UIParent,
        type(position.relativePoint) == "string" and position.relativePoint or DEFAULT_POSITION.relativePoint,
        tonumber(position.x) or DEFAULT_POSITION.x,
        tonumber(position.y) or DEFAULT_POSITION.y
    )
end

local function savePosition(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local position = getStore().position
    position.point = type(point) == "string" and point or DEFAULT_POSITION.point
    position.relativePoint = type(relativePoint) == "string" and relativePoint or position.point
    position.x = tonumber(x) or 0
    position.y = tonumber(y) or 0

    if relativeTo and relativeTo ~= UIParent
        and type(frame.GetCenter) == "function"
        and type(UIParent.GetCenter) == "function"
    then
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if centerX and centerY and parentX and parentY then
            position.point, position.relativePoint = "CENTER", "CENTER"
            position.x, position.y = centerX - parentX, centerY - parentY
        end
    end
end

local function resetLayout()
    local store = getStore()
    store.position.point = DEFAULT_POSITION.point
    store.position.relativePoint = DEFAULT_POSITION.relativePoint
    store.position.x = DEFAULT_POSITION.x
    store.position.y = DEFAULT_POSITION.y
    store.scale = 1
    if Runtime.frame then
        Runtime.frame:SetScale(1)
        applyPosition(Runtime.frame)
    end
end

local function getCurrentSpecIndex()
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecialization) == "function" then
        local ok, value = pcall(C_SpecializationInfo.GetSpecialization)
        if ok and positiveInteger(value) then return positiveInteger(value) end
    end
    if type(GetSpecialization) == "function" then
        local ok, value = pcall(GetSpecialization)
        if ok then return positiveInteger(value) end
    end
    return nil
end

local function getClassID()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, _, classID = pcall(UnitClass, "player")
    return ok and positiveInteger(classID) or nil
end

local function getSpecInfo(classID, specIndex)
    local functions = {}
    if classID and C_SpecializationInfo
        and type(C_SpecializationInfo.GetSpecializationInfoForClassID) == "function"
    then
        functions[#functions + 1] = {
            callback = C_SpecializationInfo.GetSpecializationInfoForClassID,
            arguments = { classID, specIndex },
        }
    end
    if classID and type(GetSpecializationInfoForClassID) == "function" then
        functions[#functions + 1] = {
            callback = GetSpecializationInfoForClassID,
            arguments = { classID, specIndex },
        }
    end
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
        functions[#functions + 1] = {
            callback = C_SpecializationInfo.GetSpecializationInfo,
            arguments = { specIndex },
        }
    end
    if type(GetSpecializationInfo) == "function" then
        functions[#functions + 1] = {
            callback = GetSpecializationInfo,
            arguments = { specIndex },
        }
    end

    for _, candidate in ipairs(functions) do
        local ok, specID, name, description, icon, role = pcall(
            candidate.callback,
            unpack(candidate.arguments)
        )
        if ok and positiveInteger(specID) then
            return {
                index = specIndex,
                id = positiveInteger(specID),
                name = type(name) == "string" and name or ("Spec " .. tostring(specIndex)),
                description = description,
                icon = icon or UNKNOWN_ICON,
                role = role,
            }
        end
    end
    return nil
end

local function getSpecCount(classID)
    if classID then
        local callbacks = {}
        if C_SpecializationInfo
            and type(C_SpecializationInfo.GetNumSpecializationsForClassID) == "function"
        then
            callbacks[#callbacks + 1] = C_SpecializationInfo.GetNumSpecializationsForClassID
        end
        if type(GetNumSpecializationsForClassID) == "function" then
            callbacks[#callbacks + 1] = GetNumSpecializationsForClassID
        end
        for _, callback in ipairs(callbacks) do
            local ok, count = pcall(callback, classID)
            count = ok and positiveInteger(count) or nil
            if count then return count end
        end
    end

    local count = 0
    for specIndex = 1, 6 do
        if getSpecInfo(classID, specIndex) then
            count = specIndex
        elseif count > 0 then
            break
        end
    end
    return count
end

local function getConfigInfo(configID)
    if not (C_Traits and type(C_Traits.GetConfigInfo) == "function") then
        return nil
    end
    local ok, info = pcall(C_Traits.GetConfigInfo, configID)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function getLoadouts(specID)
    if not (C_ClassTalents and type(C_ClassTalents.GetConfigIDsBySpecID) == "function") then
        return {}
    end
    local ok, configIDs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(configIDs) ~= "table" then return {} end

    local result = {}
    for _, rawConfigID in ipairs(configIDs) do
        local configID = positiveInteger(rawConfigID)
        if configID then
            local info = getConfigInfo(configID)
            result[#result + 1] = {
                id = configID,
                name = info and type(info.name) == "string" and info.name
                    or string.format(Addon.L.SPEC_BAR_LOADOUT_FALLBACK, configID),
            }
        end
    end
    return result
end

local function getLastSelectedConfigID(specID)
    if not (C_ClassTalents and type(C_ClassTalents.GetLastSelectedSavedConfigID) == "function") then
        return nil
    end
    local ok, configID = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    return ok and positiveInteger(configID) or nil
end

local function getActiveConfigID()
    if not (C_ClassTalents and type(C_ClassTalents.GetActiveConfigID) == "function") then
        return nil
    end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    return ok and positiveInteger(configID) or nil
end

function Runtime:CollectModel()
    local classID = getClassID()
    local specs = {}
    for specIndex = 1, getSpecCount(classID) do
        local spec = getSpecInfo(classID, specIndex)
        if spec then
            spec.loadouts = getLoadouts(spec.id)
            spec.lastSelectedID = getLastSelectedConfigID(spec.id)
            specs[#specs + 1] = spec
        end
    end
    return Addon.SpecSwitcherLogic:BuildModel(
        specs,
        getCurrentSpecIndex(),
        getActiveConfigID()
    )
end

function Runtime:ScheduleRefresh(delay)
    if self.enabled then
        Addon.RefreshScheduler:Invalidate(DOMAIN_ID, delay or 0)
    end
end

local function requestSpecialization(specIndex)
    local callback
    if C_SpecializationInfo and type(C_SpecializationInfo.SetSpecialization) == "function" then
        callback = C_SpecializationInfo.SetSpecialization
    elseif type(SetSpecialization) == "function" then
        callback = SetSpecialization
    end
    if not callback then return false end
    local ok, result = pcall(callback, specIndex)
    return ok and result ~= false
end

local function requestLoadout(configID)
    if not (C_ClassTalents and type(C_ClassTalents.LoadConfig) == "function") then
        return false
    end
    local ok, result = pcall(C_ClassTalents.LoadConfig, configID, true)
    return ok and result ~= false
end

function Runtime:FailPending(message)
    self.pending = nil
    showMessage(message or Addon.L.SPEC_BAR_ERROR_FAILED)
    self:Render()
end

function Runtime:AdvancePending()
    local pending = self.pending
    if not pending or not self.model then return end
    if inCombat() then
        self:FailPending(Addon.L.SPEC_BAR_ERROR_COMBAT)
        return
    end

    pending.attempts = (pending.attempts or 0) + 1
    if pending.attempts > MAX_PENDING_ATTEMPTS then
        self:FailPending(Addon.L.SPEC_BAR_ERROR_TIMEOUT)
        return
    end

    local currentSpecID = self.model.currentSpecID
    if currentSpecID ~= pending.specID then
        if pending.specializationRequested ~= true then
            if not requestSpecialization(pending.specIndex) then
                self:FailPending(Addon.L.SPEC_BAR_ERROR_SPECIALIZATION)
                return
            end
            pending.specializationRequested = true
        end
        self:ScheduleRefresh(0.18)
        return
    end

    if not pending.configID then
        self.pending = nil
        self:Render()
        return
    end
    if self.model.activeConfigID == pending.configID then
        self.pending = nil
        self:Render()
        return
    end

    if pending.loadoutRequested ~= true or pending.attempts >= 4 then
        if not requestLoadout(pending.configID) then
            self:FailPending(Addon.L.SPEC_BAR_ERROR_LOADOUT)
            return
        end
        pending.loadoutRequested = true
    end
    self:ScheduleRefresh(0.18)
end

function Runtime:RequestSelection(spec, loadout)
    if self.enabled ~= true or type(spec) ~= "table" then return false end
    if inCombat() then
        showMessage(Addon.L.SPEC_BAR_ERROR_COMBAT)
        return false
    end

    self.requestSerial = self.requestSerial + 1
    self.pending = {
        serial = self.requestSerial,
        specIndex = positiveInteger(spec.index),
        specID = positiveInteger(spec.id),
        configID = positiveInteger(loadout and loadout.id),
        configName = loadout and loadout.name,
        attempts = 0,
    }
    self:HideMenu()
    self:Render()
    self:AdvancePending()
    return true
end

local function activeSpec(model)
    for _, spec in ipairs(type(model and model.specs) == "table" and model.specs or {}) do
        if spec.isActive then return spec end
    end
    return nil
end

function Runtime:HandlePrimaryClick(spec, button)
    if button == "RightButton" then
        self:ToggleMenu(spec)
        return
    end
    if button ~= "LeftButton" then return end

    if not spec.isActive then
        self:RequestSelection(spec)
        return
    end
    if setting("active_click") == "menu" then
        self:ToggleMenu(spec)
        return
    end

    local nextLoadout = Addon.SpecSwitcherLogic:GetNextLoadout(
        spec.loadouts,
        spec.activeLoadoutID
    )
    if #spec.loadouts == 1 and nextLoadout
        and nextLoadout.id == spec.activeLoadoutID
    then
        self:ToggleMenu(spec)
    elseif nextLoadout then
        self:RequestSelection(spec, nextLoadout)
    else
        self:ToggleMenu(spec)
    end
end

local function setTooltip(button, spec)
    if not GameTooltip or not spec then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    GameTooltip:AddLine(spec.name, 1, 0.82, 0.24)
    if spec.activeLoadoutName then
        GameTooltip:AddLine(
            string.format(Addon.L.SPEC_BAR_ACTIVE_LOADOUT, spec.activeLoadoutName),
            0.93, 0.89, 0.77
        )
    end
    GameTooltip:AddLine(string.format(Addon.L.SPEC_BAR_LOADOUT_COUNT, #spec.loadouts), 0.64, 0.61, 0.56)
    GameTooltip:AddLine(" ")
    if spec.isActive then
        GameTooltip:AddLine(
            setting("active_click") == "menu"
                and Addon.L.SPEC_BAR_HINT_ACTIVE_MENU
                or Addon.L.SPEC_BAR_HINT_ACTIVE_CYCLE,
            0.72, 0.68, 0.58,
            true
        )
    else
        GameTooltip:AddLine(Addon.L.SPEC_BAR_HINT_SPECIALIZATION, 0.72, 0.68, 0.58, true)
    end
    GameTooltip:AddLine(Addon.L.SPEC_BAR_HINT_RIGHT_CLICK, 0.72, 0.68, 0.58, true)
    if setting("locked") ~= true then
        GameTooltip:AddLine(Addon.L.SPEC_BAR_HINT_MOVE_SCALE, 0.72, 0.68, 0.58, true)
    end
    GameTooltip:Show()
end

function Runtime:CreateSpecButton()
    local button = CreateFrame("Button", nil, self.frame, BACKDROP_TEMPLATE)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:EnableMouse(true)

    button.roundBack = button:CreateTexture(nil, "BACKGROUND")
    button.roundBack:SetColorTexture(1, 1, 1, 1)
    button.roundBack:SetAllPoints(button)
    button.roundBackMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.roundBackMask:SetTexture(ROUND_MASK)
    button.roundBackMask:SetAllPoints(button.roundBack)
    button.roundBack:AddMaskTexture(button.roundBackMask)

    button.roundIcon = button:CreateTexture(nil, "ARTWORK")
    button.roundIcon:SetPoint("TOPLEFT", 2, -2)
    button.roundIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.roundMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.roundMask:SetTexture(ROUND_MASK)
    button.roundMask:SetAllPoints(button.roundIcon)
    button.roundIcon:AddMaskTexture(button.roundMask)

    button.squareIcon = button:CreateTexture(nil, "ARTWORK")
    button.squareIcon:SetPoint("TOPLEFT", 2, -2)
    button.squareIcon:SetPoint("BOTTOMRIGHT", -2, 2)

    button.squareBorders = {}
    local function createSquareBorder()
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetColorTexture(1, 1, 1, 1)
        button.squareBorders[#button.squareBorders + 1] = border
        return border
    end
    button.squareBorderTop = createSquareBorder()
    button.squareBorderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.squareBorderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.squareBorderTop:SetHeight(2)
    button.squareBorderBottom = createSquareBorder()
    button.squareBorderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.squareBorderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.squareBorderBottom:SetHeight(2)
    button.squareBorderLeft = createSquareBorder()
    button.squareBorderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.squareBorderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.squareBorderLeft:SetWidth(2)
    button.squareBorderRight = createSquareBorder()
    button.squareBorderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.squareBorderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.squareBorderRight:SetWidth(2)

    button.loadoutMarker = button:CreateTexture(nil, "OVERLAY")
    button.loadoutMarker:SetTexture(WHITE_TEXTURE)
    button.loadoutMarker:SetSize(14, 2)
    button.loadoutMarker:SetPoint("BOTTOM", 0, 1)
    button.loadoutMarker:SetVertexColor(0.92, 0.76, 0.24, 0.94)

    button:SetScript("OnEnter", function(self)
        setTooltip(self, self.spec)
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        Runtime:HandlePrimaryClick(self.spec, mouseButton)
    end)
    button:SetScript("OnDragStart", function()
        Runtime:StartMoving()
    end)
    button:SetScript("OnDragStop", function()
        Runtime:StopMoving()
    end)
    return button
end

function Runtime:GetButton(index)
    if not self.buttons[index] then
        self.buttons[index] = self:CreateSpecButton()
    end
    return self.buttons[index]
end

function Runtime:StartMoving()
    if not self.frame or setting("locked") == true or inCombat() then return end
    self:HideMenu()
    self.frame:StartMoving()
end

function Runtime:StopMoving()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    savePosition(self.frame)
end

function Runtime:GetSettingValue(settingKey)
    if settingKey == "scale_percent" then
        return math.floor((getStore().scale * 100) + 0.5)
    end
    return nil
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey ~= "scale_percent" then return false end
    local store = getStore()
    store.scale = clamp((tonumber(value) or 100) / 100, SCALE_MIN, SCALE_MAX)
    if self.frame then self.frame:SetScale(store.scale) end
    return true
end

function Runtime:ChangeScale(delta)
    if not self.frame or setting("locked") == true or not IsShiftKeyDown or not IsShiftKeyDown() then
        return
    end
    local current = self:GetSettingValue("scale_percent") or 100
    Addon.FeatureRegistry:SetSetting(
        FEATURE_ID,
        "scale_percent",
        current + (delta > 0 and (SCALE_STEP * 100) or -(SCALE_STEP * 100))
    )
end

function Runtime:CreateFrame()
    local frame = CreateFrame("Frame", "VaultloomSpecBar", UIParent, BACKDROP_TEMPLATE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() Runtime:StartMoving() end)
    frame:SetScript("OnDragStop", function() Runtime:StopMoving() end)
    frame:SetScript("OnMouseWheel", function(_, delta) Runtime:ChangeScale(delta) end)

    frame.activeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.activeLabel:SetJustifyH("LEFT")
    frame.activeLabel:SetJustifyV("MIDDLE")
    frame.activeLabel:SetMaxLines(1)
    frame.activeLabel:SetTextColor(0.93, 0.89, 0.77, 1)

    self.frame = frame
    frame:SetScale(getStore().scale)
    applyPosition(frame)
end

function Runtime:ApplyFrameStyle(frameStyle)
    if not self.frame then return end
    if frameStyle == "clean" then
        self.frame:SetBackdrop(nil)
        return
    end
    if frameStyle == "compact" then
        self.frame:SetBackdrop({
            bgFile = Addon.Assets.cardInset,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        self.frame:SetBackdropColor(1, 1, 1, 0.96)
        self.frame:SetBackdropBorderColor(
            0.40,
            0.31,
            0.10,
            setting("outer_border") == false and 0 or 1
        )
        return
    end
    self.frame:SetBackdrop({
        bgFile = Addon.Assets.menuPlate,
        edgeFile = TOOLTIP_BORDER,
        tile = false,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    self.frame:SetBackdropColor(1, 1, 1, 1)
    self.frame:SetBackdropBorderColor(
        0.82,
        0.64,
        0.20,
        setting("outer_border") == false and 0 or 1
    )
end

local function applyButtonAppearance(button, round, showIconBorder)
    local inset = showIconBorder and 2 or 0
    button.roundIcon:ClearAllPoints()
    button.roundIcon:SetPoint("TOPLEFT", inset, -inset)
    button.roundIcon:SetPoint("BOTTOMRIGHT", -inset, inset)
    button.squareIcon:ClearAllPoints()
    button.squareIcon:SetPoint("TOPLEFT", inset, -inset)
    button.squareIcon:SetPoint("BOTTOMRIGHT", -inset, inset)

    button.roundBack:SetShown(round and showIconBorder)
    button.roundBackMask:SetShown(round and showIconBorder)
    button.roundIcon:SetShown(round)
    button.roundMask:SetShown(round)
    button.squareIcon:SetShown(not round)
    for _, border in ipairs(button.squareBorders) do
        border:SetShown(not round and showIconBorder)
    end
end

function Runtime:Render()
    if self.enabled ~= true then return end
    if not self.frame then self:CreateFrame() end

    local model = self.model or { specs = {} }
    local frameStyle = setting("frame_style")
    local iconShape = setting("icon_shape")
    local showActiveLabel = setting("loadout_label") == "active"
    local layout = Addon.SpecSwitcherLogic:GetLayout(
        #model.specs,
        setting("orientation"),
        frameStyle,
        "normal",
        showActiveLabel
    )
    self.layout = layout
    self:ApplyFrameStyle(layout.frameStyle)
    self.frame:SetSize(layout.width, layout.height)
    self.frame:SetAlpha(getBarOpacity() * (inCombat() and 0.55 or 1))
    local showIconBorder = setting("icon_border") ~= false

    for index, spec in ipairs(model.specs) do
        local button = self:GetButton(index)
        button.spec = spec
        button:SetSize(layout.iconSize, layout.iconSize)
        button:ClearAllPoints()
        if layout.orientation == "vertical" then
            button:SetPoint("TOPLEFT", layout.padding, -(layout.padding + ((index - 1) * (layout.iconSize + layout.gap))))
        else
            button:SetPoint("TOPLEFT", layout.padding + ((index - 1) * (layout.iconSize + layout.gap)), -layout.padding)
        end
        button.roundIcon:SetTexture(spec.icon or UNKNOWN_ICON)
        button.squareIcon:SetTexture(spec.icon or UNKNOWN_ICON)
        button.roundIcon:SetTexCoord(
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET,
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET
        )
        button.squareIcon:SetTexCoord(
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET,
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET
        )

        local round = iconShape ~= "square"
        applyButtonAppearance(button, round, showIconBorder)

        local pending = self.pending and self.pending.specID == spec.id
        button.loadoutMarker:SetShown(#spec.loadouts > 0)
        local r, g, b, alpha = INACTIVE_RING[1], INACTIVE_RING[2], INACTIVE_RING[3], 0.92
        if pending then
            r, g, b, alpha = PENDING_RING[1], PENDING_RING[2], PENDING_RING[3], 1
        elseif spec.isActive then
            r, g, b = getActiveRingColor()
            alpha = 1
        end
        button.roundBack:SetVertexColor(r, g, b, alpha)
        for _, border in ipairs(button.squareBorders) do
            border:SetVertexColor(r, g, b, alpha)
        end
        button:SetAlpha((spec.isActive or pending) and 1 or 0.78)
        button:Show()
    end
    for index = #model.specs + 1, #self.buttons do
        self.buttons[index]:Hide()
    end

    local current = activeSpec(model)
    self.frame.activeLabel:ClearAllPoints()
    if showActiveLabel and current then
        local label = current.activeLoadoutName or Addon.L.SPEC_BAR_NO_ACTIVE_LOADOUT
        self.frame.activeLabel:SetText(label)
        if layout.orientation == "vertical" then
            self.frame.activeLabel:SetPoint("TOPLEFT", layout.padding + layout.iconSize + 9, -layout.padding)
            self.frame.activeLabel:SetPoint("BOTTOMRIGHT", -layout.padding, layout.padding)
        else
            self.frame.activeLabel:SetPoint("BOTTOMLEFT", layout.padding, layout.padding)
            self.frame.activeLabel:SetPoint("BOTTOMRIGHT", -layout.padding, layout.padding)
        end
        self.frame.activeLabel:Show()
    else
        self.frame.activeLabel:Hide()
    end
    self.frame:Show()
end

function Runtime:CreateMenuRow()
    local row = Addon.Widgets:CreateButton(self.menu.content, "", 236, 30, "row")
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 34, 0)
    row.label:SetPoint("RIGHT", -12, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture(CHECK_TEXTURE)
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 6, 0)
    row.check:SetVertexColor(1, 0.82, 0.24, 1)
    row:SetScript("OnClick", function(self)
        if self.spec and self.loadout then
            Runtime:RequestSelection(self.spec, self.loadout)
        end
    end)
    return row
end

function Runtime:CreateMenu()
    local menu = CreateFrame("Frame", "VaultloomSpecMenu", UIParent, BACKDROP_TEMPLATE)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetSize(272, 160)
    Addon.Widgets:ApplyStandardGoldFrame(menu, Addon.Assets.menuPlate)

    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.title:SetPoint("TOPLEFT", 16, -14)
    menu.title:SetPoint("TOPRIGHT", -16, -14)
    menu.title:SetJustifyH("LEFT")
    menu.title:SetTextColor(1, 0.82, 0.24, 1)
    menu.subtitle = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.subtitle:SetPoint("TOPLEFT", 16, -36)
    menu.subtitle:SetPoint("TOPRIGHT", -16, -36)
    menu.subtitle:SetJustifyH("LEFT")

    menu.scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    menu.scroll:SetPoint("TOPLEFT", 16, -56)
    menu.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    menu.content = CreateFrame("Frame", nil, menu.scroll)
    menu.content:SetWidth(236)
    menu.content:SetHeight(1)
    menu.scroll:SetScrollChild(menu.content)
    Addon.ScrollFrames:Style(menu.scroll, { autoHide = true })
    menu:SetScript("OnHide", function()
        Runtime.menuSpecID = nil
    end)

    self.menu = menu
    menu:Hide()
end

function Runtime:PositionMenu(button)
    if not self.menu or not button then return end
    self.menu:ClearAllPoints()
    if self.layout and self.layout.orientation == "vertical" then
        self.menu:SetPoint("TOPLEFT", button, "TOPRIGHT", 8, 0)
    else
        self.menu:SetPoint("TOP", button, "BOTTOM", 0, -8)
    end
end

function Runtime:ShowMenu(spec)
    if type(spec) ~= "table" then return end
    if inCombat() then
        showMessage(Addon.L.SPEC_BAR_ERROR_COMBAT)
        return
    end
    if not self.menu then self:CreateMenu() end

    self.menuSpecID = spec.id
    self.menu.title:SetText(spec.name)
    self.menu.subtitle:SetText(Addon.L.SPEC_BAR_MENU_SUBTITLE)
    local loadouts = type(spec.loadouts) == "table" and spec.loadouts or {}
    local rowCount = math.max(1, #loadouts)
    for index = 1, rowCount do
        local row = self.menuRows[index]
        if not row then
            row = self:CreateMenuRow()
            self.menuRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 34))
        row:SetPoint("TOPRIGHT", 0, -((index - 1) * 34))
        local loadout = loadouts[index]
        row.spec = loadout and spec or nil
        row.loadout = loadout
        row.label:SetText(loadout and loadout.name or Addon.L.SPEC_BAR_NO_LOADOUTS)
        row.check:SetShown(loadout and spec.activeLoadoutID == loadout.id or false)
        if loadout then
            row:Enable()
            row:SetAlpha(1)
        else
            row:Disable()
            row:SetAlpha(0.62)
        end
        row:Show()
    end
    for index = rowCount + 1, #self.menuRows do
        self.menuRows[index]:Hide()
    end

    local visibleRows = math.min(rowCount, 8)
    self.menu.content:SetHeight(math.max(1, rowCount * 34))
    self.menu:SetHeight(70 + (visibleRows * 34))
    local button
    for _, candidate in ipairs(self.buttons) do
        if candidate.spec and candidate.spec.id == spec.id then
            button = candidate
            break
        end
    end
    self:PositionMenu(button or self.frame)
    self.menu:Show()
    Addon.ScrollFrames:Refresh(self.menu.scroll, true)
end

function Runtime:HideMenu()
    if self.menu then self.menu:Hide() end
end

function Runtime:ToggleMenu(spec)
    if self.menu and self.menu:IsShown() and self.menuSpecID == spec.id then
        self:HideMenu()
    else
        self:ShowMenu(spec)
    end
end

function Runtime:OnModelChanged(model)
    self.model = type(model) == "table" and model or { specs = {} }
    self:Render()
    self:AdvancePending()
end

function Runtime:OnEvent(eventName, unit)
    if eventName == "PLAYER_REGEN_DISABLED" then
        self:HideMenu()
        if self.pending then
            self:FailPending(Addon.L.SPEC_BAR_ERROR_COMBAT)
        else
            self:Render()
        end
        return
    end
    if eventName == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end
    local delayed = eventName == "PLAYER_ENTERING_WORLD"
        or eventName == "PLAYER_SPECIALIZATION_CHANGED"
    self:ScheduleRefresh(delayed and 0.15 or 0)
end

function Runtime:OnSettingChanged()
    self:HideMenu()
    self:Render()
end

function Runtime:ResetSettingValues()
    resetLayout()
end

function Runtime:OnSettingsReset()
    self:HideMenu()
    self:Render()
end

function Runtime:OnAction(actionKey)
    if actionKey ~= "reset_layout" then return false end
    resetLayout()
    self:HideMenu()
    self:Render()
    showMessage(Addon.L.SPEC_BAR_LAYOUT_RESET)
    return true
end

function Runtime:OnEnable()
    self.enabled = true
    self.pending = nil
    Addon.RefreshScheduler:Register(DOMAIN_ID, self, function()
        return Runtime:CollectModel()
    end)
    Addon.StateStore:Subscribe(DOMAIN_ID, self, function(model)
        Runtime:OnModelChanged(model)
    end, true)
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "TRAIT_CONFIG_LIST_UPDATED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:ScheduleRefresh(0)
end

function Runtime:OnDisable()
    self.enabled = false
    self.pending = nil
    self:HideMenu()
    if self.frame then self.frame:Hide() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Spec Bar feature runtime.")
end
