local panel = CreateFrame("Frame")
local initialized = false

local scroll
local content
local widgets = {}
local sections = {}
local RefreshPreview
local testStatusToken = 0

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local PANEL_BANNER = "Interface\\AddOns\\PetAlert\\media\\petalert_panel_banner"
local PANEL_EMBLEM = "Interface\\AddOns\\PetAlert\\media\\petalert_console_emblem"

local THEME = {
    bg = { 0.035, 0.042, 0.055, 0.96 },
    card = { 0.060, 0.072, 0.092, 0.94 },
    cardSoft = { 0.085, 0.102, 0.128, 0.92 },
    cardLift = { 0.110, 0.130, 0.160, 0.96 },
    text = { 0.960, 0.975, 1.000, 1 },
    muted = { 0.660, 0.730, 0.810, 1 },
    dim = { 0.430, 0.500, 0.580, 1 },
    cyan = { 0.180, 0.690, 1.000, 1 },
    red = { 1.000, 0.180, 0.160, 1 },
    gold = { 1.000, 0.720, 0.180, 1 },
    mint = { 0.290, 0.900, 0.700, 1 },
    steel = { 0.420, 0.520, 0.640, 1 },
    success = { 0.320, 0.860, 0.420, 1 },
    warning = { 1.000, 0.560, 0.160, 1 },
}

local function L(key)
    if PetAlert and PetAlert.L then
        return PetAlert:L(key)
    end
    return key
end

local function GetDB()
    if PetAlert and PetAlert.GetDB then
        return PetAlert:GetDB()
    end
end

local function SafeRefresh()
    if PetAlert and PetAlert.RefreshAll then
        PetAlert:RefreshAll()
    end
end

local function ClampWidth(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function SetFontColor(fs, color)
    if fs and color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function ApplyBackdrop(frame, bg, border, edgeSize)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = edgeSize or 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function CreateLine(parent, color, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE_TEXTURE)
    line:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
    return line
end

local function CreateFont(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(text or "")
    SetFontColor(fs, color or THEME.text)
    return fs
end

local function CreateBadge(parent, text, color, width)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetSize(width or 62, 22)
    ApplyBackdrop(badge, { color[1] * 0.10, color[2] * 0.13, color[3] * 0.16, 0.94 }, { color[1], color[2], color[3], 0.78 }, 8)

    local glow = badge:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(WHITE_TEXTURE)
    glow:SetPoint("TOPLEFT", 3, -3)
    glow:SetPoint("BOTTOMRIGHT", -3, 3)
    glow:SetVertexColor(color[1], color[2], color[3], 0.12)

    badge.text = CreateFont(badge, text, "GameFontHighlightSmall", color)
    badge.text:SetPoint("CENTER", 0, 0)
    return badge
end

local function StyleButtonState(btn, hovered)
    local color = btn._color or THEME.cyan
    if btn.IsEnabled and not btn:IsEnabled() then
        btn:SetAlpha(0.42)
        return
    end

    btn:SetAlpha(1)
    local selected = btn._selected == true
    local bgBoost = (hovered or selected) and 0.24 or 0.16
    local fillAlpha = selected and 0.42 or (hovered and 0.34 or 0.22)
    local borderAlpha = selected and 1.00 or (hovered and 0.95 or 0.72)

    btn:SetBackdropColor(color[1] * bgBoost, color[2] * bgBoost, color[3] * bgBoost, 0.96)
    btn:SetBackdropBorderColor(color[1], color[2], color[3], borderAlpha)
    if btn.fill then
        btn.fill:SetVertexColor(color[1], color[2], color[3], fillAlpha)
    end
end

local function CreateButton(parent, text, width, height, onClick, color)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 92, height or 28)
    btn._color = color or THEME.cyan
    ApplyBackdrop(btn, THEME.cardLift, { btn._color[1], btn._color[2], btn._color[3], 0.72 }, 8)

    btn.fill = btn:CreateTexture(nil, "ARTWORK")
    btn.fill:SetTexture(WHITE_TEXTURE)
    btn.fill:SetPoint("TOPLEFT", 3, -3)
    btn.fill:SetPoint("BOTTOMRIGHT", -3, 3)

    btn.gloss = btn:CreateTexture(nil, "OVERLAY")
    btn.gloss:SetTexture(WHITE_TEXTURE)
    btn.gloss:SetPoint("TOPLEFT", 4, -4)
    btn.gloss:SetPoint("TOPRIGHT", -4, -4)
    btn.gloss:SetHeight(7)
    btn.gloss:SetVertexColor(1, 1, 1, 0.14)

    btn.label = CreateFont(btn, text, "GameFontHighlightSmall", THEME.text)
    btn.label:SetPoint("CENTER", 0, 0)

    local baseSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled)
        if baseSetEnabled then
            baseSetEnabled(self, enabled)
        end
        StyleButtonState(self, false)
    end

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self) StyleButtonState(self, true) end)
    btn:SetScript("OnLeave", function(self) StyleButtonState(self, false) end)

    StyleButtonState(btn, false)
    return btn
end

local function CreateCheckButton(parent, text, onClick)
    local btn = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    local label = btn.Text or _G[(btn:GetName() or "") .. "Text"]
    if label then
        label:SetText(text)
        label:SetWidth(250)
        label:SetJustifyH("LEFT")
        SetFontColor(label, THEME.text)
    end
    btn:SetScript("OnClick", function(self)
        onClick(self:GetChecked() == true)
    end)
    return btn
end

local function CreateSlider(parent, globalName, label, minVal, maxVal, onChanged)
    local slider = CreateFrame("Slider", globalName, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local lowLabel = _G[globalName .. "Low"]
    local highLabel = _G[globalName .. "High"]
    local titleLabel = _G[globalName .. "Text"]

    if lowLabel then lowLabel:SetText(tostring(minVal)) end
    if highLabel then highLabel:SetText(tostring(maxVal)) end
    if titleLabel then titleLabel:SetText(label) end

    SetFontColor(lowLabel, THEME.dim)
    SetFontColor(highLabel, THEME.dim)
    SetFontColor(titleLabel, THEME.text)

    slider.valueBadge = CreateBadge(parent, "0", THEME.cyan, 44)

    slider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor((value or 0) + 0.5)
        self.valueBadge.text:SetText(tostring(rounded))
        onChanged(rounded)
    end)

    return slider
end

local function RefreshSoundLabel()
    if widgets.soundLabel and PetAlert and PetAlert.GetSelectedSoundLabel then
        widgets.soundLabel:SetText(PetAlert:GetSelectedSoundLabel())
    end
end

local function RefreshCustomIconSelector()
    local db = GetDB()
    local icon
    local label = L("automaticClassIcon")

    if not db then
        icon = 136164
        label = L("automaticClassIcon")
    elseif db.customIconEnabled and db.customIcon ~= "" then
        icon = db.customIcon
        label = string.format(L("customIconPrefix"), tostring(db.customIcon))
    elseif PetAlert and PetAlert.GetDefaultAlertIcon then
        icon = PetAlert:GetDefaultAlertIcon()
    end

    if widgets.iconPreview then
        widgets.iconPreview:SetTexture(icon or 136164)
    end
    if widgets.iconValueLabel then
        widgets.iconValueLabel:SetText(label)
    end
end

local function RefreshMinimapControls()
    local db = GetDB()

    if widgets.minimapCheck then
        widgets.minimapCheck:SetChecked(db and db.minimapButtonEnabled == true)
    end

    if widgets.minimapLockCheck then
        widgets.minimapLockCheck:SetChecked(db and db.minimapButtonLocked == true)
    end

    if widgets.minimapStatus then
        if not db then
            widgets.minimapStatus:SetText(L("minimapWait"))
            SetFontColor(widgets.minimapStatus, THEME.dim)
        elseif db.minimapButtonEnabled ~= true then
            widgets.minimapStatus:SetText(L("minimapHidden"))
            SetFontColor(widgets.minimapStatus, THEME.dim)
        elseif db.minimapButtonLocked == true then
            widgets.minimapStatus:SetText(L("minimapVisibleLocked"))
            SetFontColor(widgets.minimapStatus, THEME.gold)
        else
            widgets.minimapStatus:SetText(L("minimapVisibleUnlocked"))
            SetFontColor(widgets.minimapStatus, THEME.mint)
        end
    end

    if widgets.minimapReset and widgets.minimapReset.SetEnabled then
        widgets.minimapReset:SetEnabled(db ~= nil)
    end
end

function PetAlert:RefreshMinimapConfigControls()
    RefreshMinimapControls()
end

local function RefreshPetHealthBarControls()
    local db = GetDB()

    if widgets.petHealthBarCheck then
        widgets.petHealthBarCheck:SetChecked(db and db.petHealthBarEnabled == true)
    end

    if widgets.petHealthBarPreview then
        if PetAlert and PetAlert.IsPetHealthBarPreviewing and PetAlert:IsPetHealthBarPreviewing() then
            widgets.petHealthBarPreview.label:SetText(L("petHealthBarPreviewHide"))
        else
            widgets.petHealthBarPreview.label:SetText(L("petHealthBarPreview"))
        end
    end

    if db and widgets.petHealthBarSliders then
        if widgets.petHealthBarSliders.width then
            widgets.petHealthBarSliders.width:SetValue(db.petHealthBarWidth or 168)
        end
        if widgets.petHealthBarSliders.height then
            widgets.petHealthBarSliders.height:SetValue(db.petHealthBarHeight or 16)
        end
        if widgets.petHealthBarSliders.red then
            widgets.petHealthBarSliders.red:SetValue(math.floor(((db.petHealthBarR or 0.29) * 100) + 0.5))
        end
        if widgets.petHealthBarSliders.green then
            widgets.petHealthBarSliders.green:SetValue(math.floor(((db.petHealthBarG or 0.90) * 100) + 0.5))
        end
        if widgets.petHealthBarSliders.blue then
            widgets.petHealthBarSliders.blue:SetValue(math.floor(((db.petHealthBarB or 0.42) * 100) + 0.5))
        end
        if widgets.petHealthBarSliders.bgAlpha then
            widgets.petHealthBarSliders.bgAlpha:SetValue(db.petHealthBarBgAlpha or 88)
        end
        if widgets.petHealthBarSliders.borderAlpha then
            widgets.petHealthBarSliders.borderAlpha:SetValue(db.petHealthBarBorderAlpha or 85)
        end
    end

    if db and widgets.petHealthBarStyleButtons then
        for key, button in pairs(widgets.petHealthBarStyleButtons) do
            button._selected = db.petHealthBarFrameStyle == key
            StyleButtonState(button, false)
        end
    end

    if db and widgets.petHealthBarThemeButtons then
        for key, button in pairs(widgets.petHealthBarThemeButtons) do
            button._selected = db.petHealthBarTheme == key
            StyleButtonState(button, false)
        end
    end

    if db and widgets.petHealthBarTextureButtons then
        for key, button in pairs(widgets.petHealthBarTextureButtons) do
            button._selected = db.petHealthBarTexture == key
            StyleButtonState(button, false)
        end
    end

    if db then
        if widgets.petHealthBarIconCheck then widgets.petHealthBarIconCheck:SetChecked(db.petHealthBarShowIcon ~= false) end
        if widgets.petHealthBarPercentCheck then widgets.petHealthBarPercentCheck:SetChecked(db.petHealthBarShowPercent ~= false) end
        if widgets.petHealthBarShineCheck then widgets.petHealthBarShineCheck:SetChecked(db.petHealthBarShowShine ~= false) end
    end
end

local function RefreshAllPreviews()
    if sections.main and sections.main.frame then
        RefreshPreview(sections.main.frame.preview)
    end
    if sections.hp and sections.hp.frame then
        RefreshPreview(sections.hp.frame.preview)
    end
    if sections.passive and sections.passive.frame then
        RefreshPreview(sections.passive.frame.preview)
    end
end

local function RefreshControlValues()
    local db = GetDB()
    if not db then return end

    if widgets.globalCheck then widgets.globalCheck:SetChecked(db.alertsOutOfCombat) end
    if widgets.audioCheck then widgets.audioCheck:SetChecked(db.audioAlertEnabled) end
    if widgets.minimalCheck then widgets.minimalCheck:SetChecked(db.minimalMode) end

    RefreshMinimapControls()
    RefreshPetHealthBarControls()
    RefreshSoundLabel()
    RefreshCustomIconSelector()

    if sections.main and sections.main.controls then
        sections.main.controls.enable:SetChecked(db.missingAlertEnabled)
        sections.main.controls.sliders[1]:SetValue(db.mainSize or 140)
    end

    if sections.hp and sections.hp.controls then
        sections.hp.controls.enable:SetChecked(db.lowHPAlertEnabled)
        sections.hp.controls.sliders[1]:SetValue(db.lowHPThreshold or 25)
        sections.hp.controls.sliders[2]:SetValue(db.hpSize or 140)
    end

    if sections.passive and sections.passive.controls then
        sections.passive.controls.enable:SetChecked(db.passiveAlertEnabled)
        sections.passive.controls.sliders[1]:SetValue(db.passiveSize or 140)
    end

    RefreshAllPreviews()
end

local function SetTestStatus(key, color)
    if not widgets.testStatus then return end

    testStatusToken = testStatusToken + 1
    local token = testStatusToken
    widgets.testStatus:SetText(L(key))
    SetFontColor(widgets.testStatus, color or THEME.mint)

    if C_Timer and C_Timer.After and key ~= "testReady" then
        C_Timer.After(3.0, function()
            if token == testStatusToken and widgets.testStatus then
                widgets.testStatus:SetText(L("testReady"))
                SetFontColor(widgets.testStatus, THEME.mint)
            end
        end)
    end
end

local function GetColorByType(alertType)
    if alertType == "hp" then
        return THEME.gold
    elseif alertType == "passive" then
        return THEME.mint
    end
    return THEME.red
end

local iconPicker
local iconPickerButtons = {}
local iconPickerIcons
local iconPickerPage = 1
local ICONS_PER_PAGE = 48

local function AddUniqueIcon(list, seen, icon)
    if icon == nil or icon == "" then return end
    if type(icon) ~= "number" and type(icon) ~= "string" then return end

    local key = tostring(icon)
    if seen[key] then return end

    seen[key] = true
    list[#list + 1] = icon
end

local function GetMacroIconPool()
    if iconPickerIcons then
        return iconPickerIcons
    end

    local icons = {}
    local seen = {}

    if GetMacroIcons then
        local macroIcons = {}
        local ok = pcall(GetMacroIcons, macroIcons)
        if ok then
            for _, icon in ipairs(macroIcons) do
                AddUniqueIcon(icons, seen, icon)
            end
        end
    end

    if GetMacroItemIcons then
        local itemIcons = {}
        local ok = pcall(GetMacroItemIcons, itemIcons)
        if ok then
            for _, icon in ipairs(itemIcons) do
                AddUniqueIcon(icons, seen, icon)
            end
        end
    end

    if #icons == 0 and GetMacroIconInfo then
        for i = 1, 2500 do
            local icon = GetMacroIconInfo(i)
            if not icon then break end
            AddUniqueIcon(icons, seen, icon)
        end
    end

    AddUniqueIcon(icons, seen, 136164)
    AddUniqueIcon(icons, seen, 132203)
    AddUniqueIcon(icons, seen, 136243)
    AddUniqueIcon(icons, seen, 136184)
    AddUniqueIcon(icons, seen, 135805)
    AddUniqueIcon(icons, seen, 136048)
    AddUniqueIcon(icons, seen, "Interface\\Icons\\INV_Misc_QuestionMark")

    iconPickerIcons = icons
    return iconPickerIcons
end

local function RefreshIconPickerPage()
    if not iconPicker then return end

    local icons = GetMacroIconPool()
    local maxPage = math.max(1, math.ceil(#icons / ICONS_PER_PAGE))
    if iconPickerPage < 1 then iconPickerPage = 1 end
    if iconPickerPage > maxPage then iconPickerPage = maxPage end

    local startIndex = ((iconPickerPage - 1) * ICONS_PER_PAGE) + 1
    for i, button in ipairs(iconPickerButtons) do
        local icon = icons[startIndex + i - 1]
        button.iconValue = icon

        if icon then
            button.icon:SetTexture(icon)
            button:Enable()
            button:Show()
        else
            button.icon:SetTexture(nil)
            button:Disable()
            button:Hide()
        end
    end

    if iconPicker.pageText then
        iconPicker.pageText:SetText(string.format(L("pageFormat"), iconPickerPage, maxPage))
    end
    if iconPicker.prev then iconPicker.prev:SetEnabled(iconPickerPage > 1) end
    if iconPicker.next then iconPicker.next:SetEnabled(iconPickerPage < maxPage) end
end

local function CreateIconPicker()
    if iconPicker then
        return iconPicker
    end

    iconPicker = CreateFrame("Frame", "PetAlertIconPickerFrame", UIParent, "BackdropTemplate")
    iconPicker:SetSize(456, 430)
    iconPicker:SetPoint("CENTER")
    iconPicker:SetFrameStrata("DIALOG")
    iconPicker:SetClampedToScreen(true)
    iconPicker:EnableMouse(true)
    iconPicker:SetMovable(true)
    iconPicker:RegisterForDrag("LeftButton")
    iconPicker:SetScript("OnDragStart", iconPicker.StartMoving)
    iconPicker:SetScript("OnDragStop", iconPicker.StopMovingOrSizing)
    ApplyBackdrop(iconPicker, { 0.035, 0.042, 0.055, 0.98 }, { THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.78 }, 12)
    iconPicker:Hide()

    local art = iconPicker:CreateTexture(nil, "BACKGROUND")
    art:SetTexture(PANEL_BANNER)
    art:SetPoint("TOPLEFT", 6, -6)
    art:SetPoint("TOPRIGHT", -6, -6)
    art:SetHeight(72)
    art:SetAlpha(0.82)

    local shade = iconPicker:CreateTexture(nil, "ARTWORK")
    shade:SetTexture(WHITE_TEXTURE)
    shade:SetPoint("TOPLEFT", 6, -6)
    shade:SetPoint("TOPRIGHT", -6, -6)
    shade:SetHeight(72)
    shade:SetVertexColor(0, 0, 0, 0.40)

    local title = CreateFont(iconPicker, L("iconPickerTitle"), "GameFontNormalLarge", THEME.text)
    title:SetPoint("TOPLEFT", 18, -16)

    local subtitle = CreateFont(iconPicker, L("iconPickerSubtitle"), "GameFontHighlightSmall", THEME.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local close = CreateButton(iconPicker, L("close"), 66, 26, function()
        iconPicker:Hide()
    end, THEME.steel)
    close:SetPoint("TOPRIGHT", -18, -16)

    local grid = CreateFrame("Frame", nil, iconPicker)
    grid:SetPoint("TOPLEFT", 20, -92)
    grid:SetSize(384, 288)

    for i = 1, ICONS_PER_PAGE do
        local button = CreateFrame("Button", nil, grid, "BackdropTemplate")
        button:SetSize(42, 42)
        ApplyBackdrop(button, THEME.cardSoft, { THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.24 }, 7)

        local col = (i - 1) % 8
        local row = math.floor((i - 1) / 8)
        button:SetPoint("TOPLEFT", col * 48, -(row * 48))

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("CENTER")
        button.icon:SetSize(34, 34)

        button:SetScript("OnClick", function(self)
            if PetAlert and PetAlert.SetCustomIcon and self.iconValue then
                PetAlert:SetCustomIcon(self.iconValue)
                RefreshCustomIconSelector()
                RefreshAllPreviews()
            end
            iconPicker:Hide()
        end)
        button:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 1)
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.24)
        end)

        iconPickerButtons[i] = button
    end

    iconPicker.prev = CreateButton(iconPicker, L("previous"), 86, 26, function()
        iconPickerPage = iconPickerPage - 1
        RefreshIconPickerPage()
    end, THEME.cyan)
    iconPicker.prev:SetPoint("BOTTOMLEFT", 20, 18)

    iconPicker.next = CreateButton(iconPicker, L("next"), 66, 26, function()
        iconPickerPage = iconPickerPage + 1
        RefreshIconPickerPage()
    end, THEME.cyan)
    iconPicker.next:SetPoint("LEFT", iconPicker.prev, "RIGHT", 10, 0)

    iconPicker.pageText = CreateFont(iconPicker, "", "GameFontHighlight", THEME.text)
    iconPicker.pageText:SetPoint("CENTER", 0, -184)

    iconPicker.default = CreateButton(iconPicker, L("useAutomaticIcon"), 146, 26, function()
        if PetAlert and PetAlert.ResetCustomIcon then
            PetAlert:ResetCustomIcon()
            RefreshCustomIconSelector()
            RefreshAllPreviews()
        end
        iconPicker:Hide()
    end, THEME.gold)
    iconPicker.default:SetPoint("BOTTOMRIGHT", -20, 18)

    return iconPicker
end

local function OpenIconPicker()
    local picker = CreateIconPicker()
    iconPickerPage = 1
    RefreshIconPickerPage()
    picker:Show()
end

local function CreatePreview(parent, alertType)
    local color = GetColorByType(alertType)

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame.alertType = alertType
    frame.color = color
    ApplyBackdrop(frame, THEME.cardLift, { color[1], color[2], color[3], 0.74 }, 10)

    frame.glow = frame:CreateTexture(nil, "BACKGROUND")
    frame.glow:SetTexture(WHITE_TEXTURE)
    frame.glow:SetPoint("TOPLEFT", 4, -4)
    frame.glow:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.glow:SetVertexColor(color[1], color[2], color[3], 0.08)

    frame.topLine = CreateLine(frame, color, 0.95)
    frame.topLine:SetPoint("TOPLEFT", 2, -2)
    frame.topLine:SetPoint("TOPRIGHT", -2, -2)
    frame.topLine:SetHeight(2)

    frame.title = CreateFont(frame, L("livePreview"), "GameFontNormalSmall", color)
    frame.title:SetPoint("TOPLEFT", 10, -9)

    frame.iconRing = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    ApplyBackdrop(frame.iconRing, { 0.030, 0.036, 0.046, 0.96 }, { color[1], color[2], color[3], 0.84 }, 10)

    frame.iconGlow = frame.iconRing:CreateTexture(nil, "BACKGROUND")
    frame.iconGlow:SetTexture(WHITE_TEXTURE)
    frame.iconGlow:SetPoint("TOPLEFT", 4, -4)
    frame.iconGlow:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.iconGlow:SetVertexColor(color[1], color[2], color[3], 0.10)

    frame.icon = frame.iconRing:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("CENTER")
    frame.icon:SetSize(64, 64)

    frame.text = CreateFont(frame, "ALERT !", "GameFontNormal", color)
    frame.text:SetPoint("TOP", frame.iconRing, "BOTTOM", 0, -7)

    return frame
end

RefreshPreview = function(frame)
    if not frame then
        return
    end

    if not GetDB() or not PetAlert or not PetAlert.GetPreviewData then
        frame.icon:SetTexture(136164)
        frame.icon:SetSize(64, 64)
        frame.text:SetText("")
        return
    end

    local data = PetAlert:GetPreviewData(frame.alertType)
    if not data then
        return
    end

    frame.icon:SetTexture(data.icon or 136164)
    frame.icon:SetSize(data.size or 64, data.size or 64)
    frame.text:SetText(data.text or "")
    frame.text:SetTextColor(data.r or 1, data.g or 1, data.b or 1, 1)
end

local function CreateSection(parent, cfg)
    local color = GetColorByType(cfg.alertType)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame.alertType = cfg.alertType
    frame.color = color
    ApplyBackdrop(frame, THEME.card, { color[1], color[2], color[3], 0.58 }, 10)

    frame.topLine = CreateLine(frame, color, 0.92)
    frame.leftLine = CreateLine(frame, color, 0.62)

    frame.kicker = CreateFont(frame, cfg.kicker, "GameFontHighlightSmall", THEME.muted)
    frame.title = CreateFont(frame, cfg.title, "GameFontNormalLarge", color)
    frame.description = CreateFont(frame, cfg.description, "GameFontHighlightSmall", THEME.muted)
    frame.description:SetJustifyH("LEFT")

    frame.badge = CreateBadge(frame, cfg.badge, color, cfg.badgeWidth or 86)
    frame.preview = CreatePreview(frame, cfg.alertType)

    return frame
end

local function CreateSectionControls(section, cfg)
    local color = section.color

    local enable = CreateCheckButton(section, cfg.enableText, function(checked)
        local db = GetDB()
        if not db then return end
        db[cfg.enableKey] = checked
        SafeRefresh()
        RefreshPreview(section.preview)
    end)

    local sliders = {}
    for _, sliderConfig in ipairs(cfg.sliders) do
        local slider = CreateSlider(section, sliderConfig.name, sliderConfig.label, sliderConfig.min, sliderConfig.max, function(value)
            local db = GetDB()
            if not db then return end
            db[sliderConfig.key] = value
            SafeRefresh()
            RefreshPreview(section.preview)
        end)
        slider.valueBadge._color = color
        slider.valueBadge:SetBackdropBorderColor(color[1], color[2], color[3], 0.78)
        SetFontColor(slider.valueBadge.text, color)
        sliders[#sliders + 1] = slider
    end

    local positionLabel = CreateFont(section, L("position"), "GameFontHighlightSmall", THEME.muted)

    local move = CreateButton(section, L("move"), 82, 28, function()
        if PetAlert and cfg.moveMethod and PetAlert[cfg.moveMethod] then
            PetAlert[cfg.moveMethod](PetAlert)
        end
    end, color)

    local lock = CreateButton(section, L("lock"), 82, 28, function()
        if PetAlert and cfg.lockMethod and PetAlert[cfg.lockMethod] then
            PetAlert[cfg.lockMethod](PetAlert)
        end
    end, THEME.steel)

    local reset = CreateButton(section, L("reset"), 82, 28, function()
        if PetAlert and cfg.resetMethod and PetAlert[cfg.resetMethod] then
            PetAlert[cfg.resetMethod](PetAlert)
        end
        SafeRefresh()
        RefreshPreview(section.preview)
    end, THEME.warning)

    return {
        enable = enable,
        sliders = sliders,
        positionLabel = positionLabel,
        move = move,
        lock = lock,
        reset = reset,
    }
end

local function LayoutSection(section, controls, topY, availableWidth)
    local sectionWidth = math.max(584, availableWidth)
    local left = 20
    local right = 18
    local previewWidth = 170
    local previewHeight = 136
    local previewX = sectionWidth - right - previewWidth
    local contentWidth = previewX - left - 22

    section:ClearAllPoints()
    section:SetPoint("TOPLEFT", 18, topY)
    section:SetSize(sectionWidth, 210)

    section.topLine:ClearAllPoints()
    section.topLine:SetPoint("TOPLEFT", 2, -2)
    section.topLine:SetPoint("TOPRIGHT", -2, -2)
    section.topLine:SetHeight(3)

    section.leftLine:ClearAllPoints()
    section.leftLine:SetPoint("TOPLEFT", 2, -8)
    section.leftLine:SetPoint("BOTTOMLEFT", 2, 8)
    section.leftLine:SetWidth(3)

    section.kicker:ClearAllPoints()
    section.kicker:SetPoint("TOPLEFT", left, -14)

    section.title:ClearAllPoints()
    section.title:SetPoint("TOPLEFT", left, -34)

    section.badge:ClearAllPoints()
    section.badge:SetPoint("LEFT", section.title, "RIGHT", 12, 0)

    section.description:ClearAllPoints()
    section.description:SetPoint("TOPLEFT", left, -62)
    section.description:SetWidth(contentWidth)

    controls.enable:ClearAllPoints()
    controls.enable:SetPoint("TOPLEFT", left - 4, -94)

    local sliderY = -132
    for _, slider in ipairs(controls.sliders) do
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", left + 8, sliderY)
        slider:SetWidth(ClampWidth(contentWidth - 76, 220, 330))

        slider.valueBadge:ClearAllPoints()
        slider.valueBadge:SetPoint("LEFT", slider, "RIGHT", 16, 0)

        sliderY = sliderY - 48
    end

    local buttonY = sliderY - 8
    controls.positionLabel:ClearAllPoints()
    controls.positionLabel:SetPoint("TOPLEFT", left, buttonY + 5)

    controls.move:ClearAllPoints()
    controls.move:SetPoint("TOPLEFT", left + 78, buttonY)

    controls.lock:ClearAllPoints()
    controls.lock:SetPoint("LEFT", controls.move, "RIGHT", 10, 0)

    controls.reset:ClearAllPoints()
    controls.reset:SetPoint("LEFT", controls.lock, "RIGHT", 10, 0)

    section.preview:ClearAllPoints()
    section.preview:SetPoint("TOPLEFT", previewX, -48)
    section.preview:SetSize(previewWidth, previewHeight)
    section.preview.iconRing:ClearAllPoints()
    section.preview.iconRing:SetSize(82, 82)
    section.preview.iconRing:SetPoint("CENTER", 0, 5)

    local previewBottom = 48 + previewHeight + 18
    local controlBottom = math.abs(buttonY) + 34 + 18
    local finalHeight = math.max(previewBottom, controlBottom, 204)
    section:SetHeight(finalHeight)

    RefreshPreview(section.preview)
    return finalHeight
end

local function UpdateLayout()
    if not panel or not content or not initialized then
        return
    end

    local panelWidth = panel:GetWidth()
    if not panelWidth or panelWidth <= 0 then
        panelWidth = 900
    end

    local availableWidth = math.max(620, panelWidth - 70)
    local cardWidth = availableWidth - 36
    local left = 18

    content:SetWidth(availableWidth)

    widgets.hero:ClearAllPoints()
    widgets.hero:SetPoint("TOPLEFT", left, -16)
    widgets.hero:SetSize(cardWidth, 128)

    widgets.heroArt:ClearAllPoints()
    widgets.heroArt:SetPoint("TOPLEFT", 2, -2)
    widgets.heroArt:SetPoint("BOTTOMRIGHT", -2, 2)

    widgets.heroShade:ClearAllPoints()
    widgets.heroShade:SetPoint("TOPLEFT", 2, -2)
    widgets.heroShade:SetPoint("BOTTOMRIGHT", -2, 2)

    widgets.headerTitle:ClearAllPoints()
    widgets.headerTitle:SetPoint("LEFT", widgets.hero, "LEFT", 24, 20)

    widgets.headerVersion:ClearAllPoints()
    widgets.headerVersion:SetPoint("LEFT", widgets.headerTitle, "RIGHT", 14, 0)

    widgets.headerSubtitle:ClearAllPoints()
    widgets.headerSubtitle:SetPoint("TOPLEFT", widgets.headerTitle, "BOTTOMLEFT", 0, -8)

    widgets.heroEmblem:ClearAllPoints()
    widgets.heroEmblem:SetPoint("RIGHT", widgets.hero, "RIGHT", -26, 0)
    widgets.heroEmblem:SetSize(92, 92)

    widgets.heroBadges.main:ClearAllPoints()
    widgets.heroBadges.hp:ClearAllPoints()
    widgets.heroBadges.passive:ClearAllPoints()
    widgets.heroBadges.main:SetPoint("BOTTOMLEFT", widgets.hero, "BOTTOMLEFT", 24, 18)
    widgets.heroBadges.hp:SetPoint("LEFT", widgets.heroBadges.main, "RIGHT", 10, 0)
    widgets.heroBadges.passive:SetPoint("LEFT", widgets.heroBadges.hp, "RIGHT", 10, 0)

    widgets.globalBox:ClearAllPoints()
    widgets.globalBox:SetPoint("TOPLEFT", left, -162)
    widgets.globalBox:SetSize(cardWidth, 860)

    widgets.globalTopLine:ClearAllPoints()
    widgets.globalTopLine:SetPoint("TOPLEFT", 2, -2)
    widgets.globalTopLine:SetPoint("TOPRIGHT", -2, -2)
    widgets.globalTopLine:SetHeight(3)

    widgets.globalTitle:ClearAllPoints()
    widgets.globalTitle:SetPoint("TOPLEFT", 18, -16)

    widgets.globalSubtitle:ClearAllPoints()
    widgets.globalSubtitle:SetPoint("TOPLEFT", widgets.globalTitle, "BOTTOMLEFT", 0, -4)

    local rightX = math.max(350, cardWidth - 286)

    widgets.behaviorTitle:ClearAllPoints()
    widgets.behaviorTitle:SetPoint("TOPLEFT", 18, -56)

    widgets.globalCheck:ClearAllPoints()
    widgets.globalCheck:SetPoint("TOPLEFT", 12, -80)

    widgets.minimalCheck:ClearAllPoints()
    widgets.minimalCheck:SetPoint("TOPLEFT", 12, -114)

    widgets.petHealthBarTitle:ClearAllPoints()
    widgets.petHealthBarTitle:SetPoint("TOPLEFT", 18, -152)

    widgets.petHealthBarCheck:ClearAllPoints()
    widgets.petHealthBarCheck:SetPoint("TOPLEFT", 12, -176)

    widgets.petHealthBarPreview:ClearAllPoints()
    widgets.petHealthBarPreview:SetPoint("TOPLEFT", 18, -210)

    widgets.petHealthBarStylesTitle:ClearAllPoints()
    widgets.petHealthBarStylesTitle:SetPoint("TOPLEFT", 18, -252)

    local styleX = 18
    local styleY = -276
    if widgets.petHealthBarStyleButtons then
        local styleOrder = { "glass", "tactical", "minimal", "neon" }
        for _, key in ipairs(styleOrder) do
            local button = widgets.petHealthBarStyleButtons[key]
            if button then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", styleX, styleY)
                styleX = styleX + 84
            end
        end
    end

    widgets.petHealthBarThemesTitle:ClearAllPoints()
    widgets.petHealthBarThemesTitle:SetPoint("TOPLEFT", 18, -318)

    local themeX = 18
    local themeY = -342
    if widgets.petHealthBarThemeButtons then
        local themeOrder = { "emerald", "arcane", "inferno", "frost" }
        for _, key in ipairs(themeOrder) do
            local button = widgets.petHealthBarThemeButtons[key]
            if button then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", themeX, themeY)
                themeX = themeX + 84
            end
        end
    end

    widgets.petHealthBarTexturesTitle:ClearAllPoints()
    widgets.petHealthBarTexturesTitle:SetPoint("TOPLEFT", 18, -384)

    local textureX = 18
    local textureY = -408
    if widgets.petHealthBarTextureButtons then
        local textureOrder = { "raid", "status", "flat" }
        for _, key in ipairs(textureOrder) do
            local button = widgets.petHealthBarTextureButtons[key]
            if button then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", textureX, textureY)
                textureX = textureX + 76
            end
        end
    end

    widgets.petHealthBarDisplayTitle:ClearAllPoints()
    widgets.petHealthBarDisplayTitle:SetPoint("TOPLEFT", 18, -450)

    widgets.petHealthBarIconCheck:ClearAllPoints()
    widgets.petHealthBarIconCheck:SetPoint("TOPLEFT", 12, -474)

    widgets.petHealthBarPercentCheck:ClearAllPoints()
    widgets.petHealthBarPercentCheck:SetPoint("TOPLEFT", 12, -502)

    widgets.petHealthBarShineCheck:ClearAllPoints()
    widgets.petHealthBarShineCheck:SetPoint("TOPLEFT", 12, -530)

    if widgets.petHealthBarSliders then
        local hbSliderY = -586
        local hbSliderOrder = {
            widgets.petHealthBarSliders.width,
            widgets.petHealthBarSliders.height,
            widgets.petHealthBarSliders.red,
            widgets.petHealthBarSliders.green,
            widgets.petHealthBarSliders.blue,
            widgets.petHealthBarSliders.bgAlpha,
            widgets.petHealthBarSliders.borderAlpha,
        }

        for _, slider in ipairs(hbSliderOrder) do
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", 26, hbSliderY)
            slider:SetWidth(230)
            slider.valueBadge:ClearAllPoints()
            slider.valueBadge:SetPoint("LEFT", slider, "RIGHT", 16, 0)
            hbSliderY = hbSliderY - 42
        end
    end

    widgets.audioTitle:ClearAllPoints()
    widgets.audioTitle:SetPoint("TOPLEFT", rightX, -56)

    widgets.audioCheck:ClearAllPoints()
    widgets.audioCheck:SetPoint("TOPLEFT", rightX - 6, -80)

    widgets.soundLabel:ClearAllPoints()
    widgets.soundLabel:SetPoint("TOPLEFT", rightX, -116)
    widgets.soundLabel:SetWidth(250)

    widgets.soundPrev:ClearAllPoints()
    widgets.soundPrev:SetPoint("TOPLEFT", rightX, -146)

    widgets.soundNext:ClearAllPoints()
    widgets.soundNext:SetPoint("LEFT", widgets.soundPrev, "RIGHT", 8, 0)

    widgets.soundTest:ClearAllPoints()
    widgets.soundTest:SetPoint("LEFT", widgets.soundNext, "RIGHT", 8, 0)

    widgets.identityTitle:ClearAllPoints()
    widgets.identityTitle:SetPoint("TOPLEFT", 18, -786)

    widgets.iconPreviewButton:ClearAllPoints()
    widgets.iconPreviewButton:SetPoint("TOPLEFT", 18, -812)

    widgets.iconSelect:ClearAllPoints()
    widgets.iconSelect:SetPoint("LEFT", widgets.iconPreviewButton, "RIGHT", 12, 0)

    widgets.iconReset:ClearAllPoints()
    widgets.iconReset:SetPoint("LEFT", widgets.iconSelect, "RIGHT", 10, 0)

    widgets.iconValueLabel:ClearAllPoints()
    widgets.iconValueLabel:SetPoint("TOPLEFT", widgets.iconSelect, "BOTTOMLEFT", 0, -8)
    widgets.iconValueLabel:SetWidth(math.max(180, rightX - 92))

    widgets.minimapTitle:ClearAllPoints()
    widgets.minimapTitle:SetPoint("TOPLEFT", rightX, -188)

    widgets.minimapBadge:ClearAllPoints()
    widgets.minimapBadge:SetPoint("LEFT", widgets.minimapTitle, "RIGHT", 10, 0)

    widgets.minimapStatus:ClearAllPoints()
    widgets.minimapStatus:SetPoint("TOPLEFT", rightX, -212)
    widgets.minimapStatus:SetWidth(260)

    widgets.minimapCheck:ClearAllPoints()
    widgets.minimapCheck:SetPoint("TOPLEFT", rightX - 6, -240)

    widgets.minimapLockCheck:ClearAllPoints()
    widgets.minimapLockCheck:SetPoint("TOPLEFT", rightX - 6, -272)

    widgets.minimapReset:ClearAllPoints()
    widgets.minimapReset:SetPoint("TOPLEFT", rightX, -306)

    widgets.toolsBox:ClearAllPoints()
    widgets.toolsBox:SetPoint("TOPLEFT", left, -1040)
    widgets.toolsBox:SetSize(cardWidth, 178)

    widgets.toolsTopLine:ClearAllPoints()
    widgets.toolsTopLine:SetPoint("TOPLEFT", 2, -2)
    widgets.toolsTopLine:SetPoint("TOPRIGHT", -2, -2)
    widgets.toolsTopLine:SetHeight(3)

    local presetX = math.max(350, cardWidth - 300)
    local dividerX = presetX - 22

    widgets.toolsDivider:ClearAllPoints()
    widgets.toolsDivider:SetPoint("TOPLEFT", dividerX, -18)
    widgets.toolsDivider:SetPoint("BOTTOMLEFT", dividerX, 18)
    widgets.toolsDivider:SetWidth(2)

    widgets.testTitle:ClearAllPoints()
    widgets.testTitle:SetPoint("TOPLEFT", 18, -16)

    widgets.testSubtitle:ClearAllPoints()
    widgets.testSubtitle:SetPoint("TOPLEFT", widgets.testTitle, "BOTTOMLEFT", 0, -4)
    widgets.testSubtitle:SetWidth(math.max(240, presetX - 58))

    widgets.testMain:ClearAllPoints()
    widgets.testMain:SetPoint("TOPLEFT", 18, -72)

    widgets.testHP:ClearAllPoints()
    widgets.testHP:SetPoint("LEFT", widgets.testMain, "RIGHT", 8, 0)

    widgets.testPassive:ClearAllPoints()
    widgets.testPassive:SetPoint("LEFT", widgets.testHP, "RIGHT", 8, 0)

    widgets.testSequence:ClearAllPoints()
    widgets.testSequence:SetPoint("TOPLEFT", 18, -110)

    widgets.testStop:ClearAllPoints()
    widgets.testStop:SetPoint("LEFT", widgets.testSequence, "RIGHT", 8, 0)

    widgets.testStatus:ClearAllPoints()
    widgets.testStatus:SetPoint("LEFT", widgets.testStop, "RIGHT", 12, 0)
    widgets.testStatus:SetWidth(math.max(110, presetX - 210))

    widgets.presetsTitle:ClearAllPoints()
    widgets.presetsTitle:SetPoint("TOPLEFT", presetX, -16)

    widgets.presetsSubtitle:ClearAllPoints()
    widgets.presetsSubtitle:SetPoint("TOPLEFT", widgets.presetsTitle, "BOTTOMLEFT", 0, -4)
    widgets.presetsSubtitle:SetWidth(math.max(220, cardWidth - presetX - 18))

    widgets.presetCompact:ClearAllPoints()
    widgets.presetCompact:SetPoint("TOPLEFT", presetX, -72)

    widgets.presetReadable:ClearAllPoints()
    widgets.presetReadable:SetPoint("LEFT", widgets.presetCompact, "RIGHT", 8, 0)

    widgets.presetStreamer:ClearAllPoints()
    widgets.presetStreamer:SetPoint("TOPLEFT", presetX, -110)

    widgets.presetMinimal:ClearAllPoints()
    widgets.presetMinimal:SetPoint("LEFT", widgets.presetStreamer, "RIGHT", 8, 0)

    widgets.presetsStatus:ClearAllPoints()
    widgets.presetsStatus:SetPoint("TOPLEFT", presetX, -146)
    widgets.presetsStatus:SetWidth(math.max(220, cardWidth - presetX - 18))

    local y = -1238
    local sectionWidth = cardWidth

    local h1 = LayoutSection(sections.main.frame, sections.main.controls, y, sectionWidth)
    y = y - h1 - 18

    local h2 = LayoutSection(sections.hp.frame, sections.hp.controls, y, sectionWidth)
    y = y - h2 - 18

    local h3 = LayoutSection(sections.passive.frame, sections.passive.controls, y, sectionWidth)
    y = y - h3 - 18

    content:SetHeight(math.max(math.abs(y) + 24, 720))
end

local function BuildPanel(container)
    if initialized then return end
    initialized = true

    container.name = "PetAlert"

    scroll = CreateFrame("ScrollFrame", "PetAlertConfigScrollFrame", container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    content = CreateFrame("Frame", "PetAlertConfigScrollChild", scroll)
    content:SetSize(700, 200)
    scroll:SetScrollChild(content)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        local nextValue = current - (delta * 42)
        if nextValue < 0 then nextValue = 0 end
        if nextValue > maxScroll then nextValue = maxScroll end
        self:SetVerticalScroll(nextValue)
    end)

    widgets.hero = CreateFrame("Frame", nil, content, "BackdropTemplate")
    ApplyBackdrop(widgets.hero, THEME.bg, { THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.58 }, 12)

    widgets.heroArt = widgets.hero:CreateTexture(nil, "BACKGROUND")
    widgets.heroArt:SetTexture(PANEL_BANNER)
    widgets.heroArt:SetAlpha(0.92)

    widgets.heroShade = widgets.hero:CreateTexture(nil, "ARTWORK")
    widgets.heroShade:SetTexture(WHITE_TEXTURE)
    widgets.heroShade:SetVertexColor(0, 0, 0, 0.22)

    widgets.heroEmblem = widgets.hero:CreateTexture(nil, "OVERLAY")
    widgets.heroEmblem:SetTexture(PANEL_EMBLEM)
    widgets.heroEmblem:SetAlpha(0.96)

    widgets.headerTitle = CreateFont(widgets.hero, "PetAlert", "GameFontNormalHuge", THEME.text)
    widgets.headerVersion = CreateBadge(widgets.hero, "3.1.1", THEME.cyan, 64)
    widgets.headerSubtitle = CreateFont(widgets.hero, L("heroSubtitle"), "GameFontHighlight", THEME.muted)

    widgets.heroBadges = {
        main = CreateBadge(widgets.hero, L("badgeMissing"), THEME.red, 96),
        hp = CreateBadge(widgets.hero, L("badgeLowHP"), THEME.gold, 98),
        passive = CreateBadge(widgets.hero, L("badgePassive"), THEME.mint, 92),
    }

    widgets.globalBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    ApplyBackdrop(widgets.globalBox, THEME.card, { THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.48 }, 10)
    widgets.globalTopLine = CreateLine(widgets.globalBox, THEME.cyan, 0.90)
    widgets.globalTitle = CreateFont(widgets.globalBox, L("globalTitle"), "GameFontNormalLarge", THEME.cyan)
    widgets.globalSubtitle = CreateFont(widgets.globalBox, L("globalSubtitle"), "GameFontHighlightSmall", THEME.muted)

    widgets.behaviorTitle = CreateFont(widgets.globalBox, L("behaviorTitle"), "GameFontNormalSmall", THEME.text)
    widgets.globalCheck = CreateCheckButton(widgets.globalBox, L("alertsOutOfCombat"), function(checked)
        local db = GetDB()
        if not db then return end
        db.alertsOutOfCombat = checked
        SafeRefresh()
    end)

    widgets.minimalCheck = CreateCheckButton(widgets.globalBox, L("minimalMode"), function(checked)
        local db = GetDB()
        if not db then return end
        db.minimalMode = checked
        SafeRefresh()
        RefreshAllPreviews()
    end)

    widgets.petHealthBarTitle = CreateFont(widgets.globalBox, L("petHealthBarTitle"), "GameFontNormalSmall", THEME.text)
    widgets.petHealthBarCheck = CreateCheckButton(widgets.globalBox, L("petHealthBarEnable"), function(checked)
        if PetAlert and PetAlert.SetPetHealthBarEnabled then
            PetAlert:SetPetHealthBarEnabled(checked)
        else
            local db = GetDB()
            if db then db.petHealthBarEnabled = checked end
            SafeRefresh()
        end
        RefreshPetHealthBarControls()
    end)
    widgets.petHealthBarPreview = CreateButton(widgets.globalBox, L("petHealthBarPreview"), 112, 28, function()
        if PetAlert and PetAlert.TogglePetHealthBarPreview then
            PetAlert:TogglePetHealthBarPreview()
        end
        RefreshPetHealthBarControls()
    end, THEME.mint)

    local function CreatePetHealthBarSlider(name, label, minValue, maxValue, dbKey, scale)
        local slider = CreateSlider(widgets.globalBox, name, label, minValue, maxValue, function(value)
            local db = GetDB()
            if not db then return end
            db[dbKey] = scale and (value / scale) or value
            SafeRefresh()
        end)
        slider.valueBadge._color = THEME.mint
        slider.valueBadge:SetBackdropBorderColor(THEME.mint[1], THEME.mint[2], THEME.mint[3], 0.78)
        SetFontColor(slider.valueBadge.text, THEME.mint)
        return slider
    end

    widgets.petHealthBarSliders = {
        width = CreatePetHealthBarSlider("PetAlertPetHealthBarWidthSlider", L("petHealthBarWidth"), 96, 260, "petHealthBarWidth"),
        height = CreatePetHealthBarSlider("PetAlertPetHealthBarHeightSlider", L("petHealthBarHeight"), 10, 28, "petHealthBarHeight"),
        red = CreatePetHealthBarSlider("PetAlertPetHealthBarRedSlider", L("petHealthBarRed"), 0, 100, "petHealthBarR", 100),
        green = CreatePetHealthBarSlider("PetAlertPetHealthBarGreenSlider", L("petHealthBarGreen"), 0, 100, "petHealthBarG", 100),
        blue = CreatePetHealthBarSlider("PetAlertPetHealthBarBlueSlider", L("petHealthBarBlue"), 0, 100, "petHealthBarB", 100),
        bgAlpha = CreatePetHealthBarSlider("PetAlertPetHealthBarBgAlphaSlider", L("petHealthBarBgAlpha"), 0, 100, "petHealthBarBgAlpha"),
        borderAlpha = CreatePetHealthBarSlider("PetAlertPetHealthBarBorderAlphaSlider", L("petHealthBarBorderAlpha"), 0, 100, "petHealthBarBorderAlpha"),
    }

    widgets.petHealthBarStylesTitle = CreateFont(widgets.globalBox, L("petHealthBarStyles"), "GameFontNormalSmall", THEME.text)
    widgets.petHealthBarStyleButtons = {}
    if PetAlert and PetAlert.GetPetHealthBarFrameStyles then
        for _, style in ipairs(PetAlert:GetPetHealthBarFrameStyles()) do
            widgets.petHealthBarStyleButtons[style.key] = CreateButton(widgets.globalBox, style.label, 78, 26, function()
                if PetAlert and PetAlert.ApplyPetHealthBarFrameStyle then
                    PetAlert:ApplyPetHealthBarFrameStyle(style.key)
                    RefreshPetHealthBarControls()
                end
            end, THEME.cyan)
        end
    end

    widgets.petHealthBarThemesTitle = CreateFont(widgets.globalBox, L("petHealthBarThemes"), "GameFontNormalSmall", THEME.text)
    widgets.petHealthBarThemeButtons = {}
    if PetAlert and PetAlert.GetPetHealthBarThemes then
        for _, theme in ipairs(PetAlert:GetPetHealthBarThemes()) do
            widgets.petHealthBarThemeButtons[theme.key] = CreateButton(widgets.globalBox, theme.label, 78, 26, function()
                if PetAlert and PetAlert.ApplyPetHealthBarTheme then
                    PetAlert:ApplyPetHealthBarTheme(theme.key)
                    RefreshPetHealthBarControls()
                end
            end, { theme.r, theme.g, theme.b, 1 })
        end
    end

    widgets.petHealthBarTexturesTitle = CreateFont(widgets.globalBox, L("petHealthBarTextures"), "GameFontNormalSmall", THEME.text)
    widgets.petHealthBarTextureButtons = {}
    if PetAlert and PetAlert.GetPetHealthBarTextures then
        for _, texture in ipairs(PetAlert:GetPetHealthBarTextures()) do
            widgets.petHealthBarTextureButtons[texture.key] = CreateButton(widgets.globalBox, texture.label, 70, 26, function()
                if PetAlert and PetAlert.SetPetHealthBarTexture then
                    PetAlert:SetPetHealthBarTexture(texture.key)
                    RefreshPetHealthBarControls()
                end
            end, THEME.steel)
        end
    end

    widgets.petHealthBarDisplayTitle = CreateFont(widgets.globalBox, L("petHealthBarDisplay"), "GameFontNormalSmall", THEME.text)
    widgets.petHealthBarIconCheck = CreateCheckButton(widgets.globalBox, L("petHealthBarShowIcon"), function(checked)
        if PetAlert and PetAlert.SetPetHealthBarDisplayOption then
            PetAlert:SetPetHealthBarDisplayOption("icon", checked)
        end
        RefreshPetHealthBarControls()
    end)
    widgets.petHealthBarPercentCheck = CreateCheckButton(widgets.globalBox, L("petHealthBarShowPercent"), function(checked)
        if PetAlert and PetAlert.SetPetHealthBarDisplayOption then
            PetAlert:SetPetHealthBarDisplayOption("percent", checked)
        end
        RefreshPetHealthBarControls()
    end)
    widgets.petHealthBarShineCheck = CreateCheckButton(widgets.globalBox, L("petHealthBarShowShine"), function(checked)
        if PetAlert and PetAlert.SetPetHealthBarDisplayOption then
            PetAlert:SetPetHealthBarDisplayOption("shine", checked)
        end
        RefreshPetHealthBarControls()
    end)

    widgets.audioTitle = CreateFont(widgets.globalBox, L("audioTitle"), "GameFontNormalSmall", THEME.text)
    widgets.audioCheck = CreateCheckButton(widgets.globalBox, L("enableAudio"), function(checked)
        local db = GetDB()
        if not db then return end
        db.audioAlertEnabled = checked
        SafeRefresh()
    end)

    widgets.soundLabel = CreateFont(widgets.globalBox, "", "GameFontNormal", THEME.text)
    widgets.soundLabel:SetJustifyH("LEFT")

    widgets.soundPrev = CreateButton(widgets.globalBox, L("previous"), 78, 28, function()
        if PetAlert and PetAlert.SelectPreviousSound then
            PetAlert:SelectPreviousSound()
            RefreshSoundLabel()
        end
    end, THEME.steel)

    widgets.soundNext = CreateButton(widgets.globalBox, L("next"), 64, 28, function()
        if PetAlert and PetAlert.SelectNextSound then
            PetAlert:SelectNextSound()
            RefreshSoundLabel()
        end
    end, THEME.steel)

    widgets.soundTest = CreateButton(widgets.globalBox, L("testSound"), 56, 28, function()
        if PetAlert and PetAlert.PreviewAlertSound then
            PetAlert:PreviewAlertSound()
        end
    end, THEME.success)

    widgets.identityTitle = CreateFont(widgets.globalBox, L("identityTitle"), "GameFontNormalSmall", THEME.text)
    widgets.iconPreviewButton = CreateFrame("Button", nil, widgets.globalBox, "BackdropTemplate")
    widgets.iconPreviewButton:SetSize(42, 42)
    ApplyBackdrop(widgets.iconPreviewButton, THEME.cardLift, { THEME.cyan[1], THEME.cyan[2], THEME.cyan[3], 0.58 }, 8)
    widgets.iconPreviewButton:SetScript("OnClick", OpenIconPicker)

    widgets.iconPreview = widgets.iconPreviewButton:CreateTexture(nil, "ARTWORK")
    widgets.iconPreview:SetPoint("CENTER")
    widgets.iconPreview:SetSize(34, 34)

    widgets.iconSelect = CreateButton(widgets.globalBox, L("chooseIcon"), 104, 28, OpenIconPicker, THEME.cyan)
    widgets.iconReset = CreateButton(widgets.globalBox, L("automaticIcon"), 100, 28, function()
        if PetAlert and PetAlert.ResetCustomIcon then
            PetAlert:ResetCustomIcon()
            RefreshCustomIconSelector()
            RefreshAllPreviews()
        end
    end, THEME.gold)

    widgets.iconValueLabel = CreateFont(widgets.globalBox, "", "GameFontHighlightSmall", THEME.muted)
    widgets.iconValueLabel:SetJustifyH("LEFT")

    widgets.minimapTitle = CreateFont(widgets.globalBox, L("minimapTitle"), "GameFontNormalSmall", THEME.text)
    widgets.minimapBadge = CreateBadge(widgets.globalBox, L("minimapBadge"), THEME.mint, 78)
    widgets.minimapStatus = CreateFont(widgets.globalBox, "", "GameFontHighlightSmall", THEME.muted)
    widgets.minimapStatus:SetJustifyH("LEFT")

    widgets.minimapCheck = CreateCheckButton(widgets.globalBox, L("showMinimap"), function(checked)
        local db = GetDB()
        if not db then return end

        if PetAlert and PetAlert.SetMinimapButtonEnabled then
            PetAlert:SetMinimapButtonEnabled(checked)
        else
            db.minimapButtonEnabled = checked
        end

        RefreshMinimapControls()
    end)

    widgets.minimapLockCheck = CreateCheckButton(widgets.globalBox, L("lockMinimap"), function(checked)
        local db = GetDB()
        if not db then return end

        if PetAlert and PetAlert.SetMinimapButtonLocked then
            PetAlert:SetMinimapButtonLocked(checked)
        else
            db.minimapButtonLocked = checked
        end

        RefreshMinimapControls()
    end)

    widgets.minimapReset = CreateButton(widgets.globalBox, L("resetPosition"), 112, 28, function()
        if PetAlert and PetAlert.ResetMinimapButton then
            PetAlert:ResetMinimapButton()
        end

        RefreshMinimapControls()
    end, THEME.mint)

    widgets.toolsBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    ApplyBackdrop(widgets.toolsBox, THEME.card, { THEME.mint[1], THEME.mint[2], THEME.mint[3], 0.42 }, 10)
    widgets.toolsTopLine = CreateLine(widgets.toolsBox, THEME.mint, 0.90)
    widgets.toolsDivider = CreateLine(widgets.toolsBox, THEME.steel, 0.42)

    widgets.testTitle = CreateFont(widgets.toolsBox, L("testCenterTitle"), "GameFontNormalLarge", THEME.mint)
    widgets.testSubtitle = CreateFont(widgets.toolsBox, L("testCenterSubtitle"), "GameFontHighlightSmall", THEME.muted)
    widgets.testStatus = CreateFont(widgets.toolsBox, L("testReady"), "GameFontHighlightSmall", THEME.mint)
    widgets.testStatus:SetJustifyH("LEFT")

    widgets.testMain = CreateButton(widgets.toolsBox, L("testMissing"), 92, 28, function()
        if PetAlert and PetAlert.PreviewAlert then
            PetAlert:PreviewAlert("main")
            SetTestStatus("testShowingMissing", THEME.red)
        end
    end, THEME.red)

    widgets.testHP = CreateButton(widgets.toolsBox, L("testLowHP"), 84, 28, function()
        if PetAlert and PetAlert.PreviewAlert then
            PetAlert:PreviewAlert("hp")
            SetTestStatus("testShowingHP", THEME.gold)
        end
    end, THEME.gold)

    widgets.testPassive = CreateButton(widgets.toolsBox, L("testPassive"), 84, 28, function()
        if PetAlert and PetAlert.PreviewAlert then
            PetAlert:PreviewAlert("passive")
            SetTestStatus("testShowingPassive", THEME.mint)
        end
    end, THEME.mint)

    widgets.testSequence = CreateButton(widgets.toolsBox, L("testSequence"), 92, 28, function()
        if PetAlert and PetAlert.PreviewAlert then
            PetAlert:PreviewAlert("all")
            SetTestStatus("testShowingSequence", THEME.cyan)
        end
    end, THEME.cyan)

    widgets.testStop = CreateButton(widgets.toolsBox, L("testStop"), 70, 28, function()
        if PetAlert and PetAlert.StopAlertPreview then
            PetAlert:StopAlertPreview()
            SetTestStatus("testStopped", THEME.steel)
        end
    end, THEME.steel)

    widgets.presetsTitle = CreateFont(widgets.toolsBox, L("presetsTitle"), "GameFontNormalLarge", THEME.cyan)
    widgets.presetsSubtitle = CreateFont(widgets.toolsBox, L("presetsSubtitle"), "GameFontHighlightSmall", THEME.muted)
    widgets.presetsStatus = CreateFont(widgets.toolsBox, "", "GameFontHighlightSmall", THEME.cyan)
    widgets.presetsStatus:SetJustifyH("LEFT")

    local function CreatePresetButton(name, color)
        local label = L("preset" .. name:sub(1, 1):upper() .. name:sub(2))
        return CreateButton(widgets.toolsBox, label, 92, 28, function()
            if PetAlert and PetAlert.ApplyPreset then
                local ok, appliedLabel = PetAlert:ApplyPreset(name)
                if ok then
                    RefreshControlValues()
                    widgets.presetsStatus:SetText(string.format(L("presetAppliedStatus"), appliedLabel or label))
                end
            end
        end, color)
    end

    widgets.presetCompact = CreatePresetButton("compact", THEME.steel)
    widgets.presetReadable = CreatePresetButton("readable", THEME.cyan)
    widgets.presetStreamer = CreatePresetButton("streamer", THEME.red)
    widgets.presetMinimal = CreatePresetButton("minimal", THEME.mint)

    sections.main = {
        frame = CreateSection(content, {
            alertType = "main",
            kicker = L("mainKicker"),
            title = L("mainTitle"),
            description = L("mainDesc"),
            badge = L("mainBadge"),
            badgeWidth = 86,
        }),
    }
    sections.main.controls = CreateSectionControls(sections.main.frame, {
        enableText = L("mainEnable"),
        enableKey = "missingAlertEnabled",
        sliders = {
            {
                name = "PetAlertConfigMainSizeSlider",
                label = L("iconSize"),
                min = 40,
                max = 300,
                key = "mainSize",
            },
        },
        moveMethod = "MoveMain",
        lockMethod = "LockMain",
        resetMethod = "ResetMain",
    })

    sections.hp = {
        frame = CreateSection(content, {
            alertType = "hp",
            kicker = L("hpKicker"),
            title = L("hpTitle"),
            description = L("hpDesc"),
            badge = L("hpBadge"),
            badgeWidth = 96,
        }),
    }
    sections.hp.controls = CreateSectionControls(sections.hp.frame, {
        enableText = L("hpEnable"),
        enableKey = "lowHPAlertEnabled",
        sliders = {
            {
                name = "PetAlertConfigHPThresholdSlider",
                label = L("hpThreshold"),
                min = 1,
                max = 99,
                key = "lowHPThreshold",
            },
            {
                name = "PetAlertConfigHPSizeSlider",
                label = L("iconSize"),
                min = 40,
                max = 300,
                key = "hpSize",
            },
        },
        moveMethod = "MoveHP",
        lockMethod = "LockHP",
        resetMethod = "ResetHP",
    })

    sections.passive = {
        frame = CreateSection(content, {
            alertType = "passive",
            kicker = L("passiveKicker"),
            title = L("passiveTitle"),
            description = L("passiveDesc"),
            badge = L("passiveBadge"),
            badgeWidth = 92,
        }),
    }
    sections.passive.controls = CreateSectionControls(sections.passive.frame, {
        enableText = L("passiveEnable"),
        enableKey = "passiveAlertEnabled",
        sliders = {
            {
                name = "PetAlertConfigPassiveSizeSlider",
                label = L("iconSize"),
                min = 40,
                max = 300,
                key = "passiveSize",
            },
        },
        moveMethod = "MovePassive",
        lockMethod = "LockPassive",
        resetMethod = "ResetPassive",
    })

    container:SetScript("OnSizeChanged", UpdateLayout)

    container:SetScript("OnShow", function()
        local db = GetDB()
        if not db then return end

        if db.alertsOutOfCombat == nil then db.alertsOutOfCombat = false end
        if db.audioAlertEnabled == nil then db.audioAlertEnabled = false end
        if db.minimalMode == nil then db.minimalMode = false end
        if db.customIconEnabled == nil then db.customIconEnabled = false end
        if db.customIcon == nil then db.customIcon = "" end
        if db.minimapButtonEnabled == nil then db.minimapButtonEnabled = true end
        if db.minimapButtonLocked == nil then db.minimapButtonLocked = false end
        if db.petHealthBarEnabled == nil then db.petHealthBarEnabled = false end
        if db.petHealthBarWidth == nil then db.petHealthBarWidth = 168 end
        if db.petHealthBarHeight == nil then db.petHealthBarHeight = 16 end
        if db.petHealthBarR == nil then db.petHealthBarR = 0.29 end
        if db.petHealthBarG == nil then db.petHealthBarG = 0.90 end
        if db.petHealthBarB == nil then db.petHealthBarB = 0.42 end
        if db.petHealthBarTheme == nil then db.petHealthBarTheme = "emerald" end
        if db.petHealthBarTexture == nil then db.petHealthBarTexture = "raid" end
        if db.petHealthBarFrameStyle == nil then db.petHealthBarFrameStyle = "glass" end
        if db.petHealthBarShowIcon == nil then db.petHealthBarShowIcon = true end
        if db.petHealthBarShowPercent == nil then db.petHealthBarShowPercent = true end
        if db.petHealthBarShowShine == nil then db.petHealthBarShowShine = true end
        if db.petHealthBarBgAlpha == nil then db.petHealthBarBgAlpha = 88 end
        if db.petHealthBarBorderAlpha == nil then db.petHealthBarBorderAlpha = 85 end

        RefreshControlValues()
        SetTestStatus("testReady", THEME.mint)
        UpdateLayout()
    end)

    RefreshControlValues()
    UpdateLayout()
end

local registeredCategory

if Settings and Settings.RegisterCanvasLayoutCategory then
    registeredCategory = Settings.RegisterCanvasLayoutCategory(panel, "PetAlert")
    Settings.RegisterAddOnCategory(registeredCategory)
    BuildPanel(panel)
else
    panel.name = "PetAlert"
    panel:Hide()
    panel:SetScript("OnShow", function(self)
        self:SetScript("OnShow", nil)
        BuildPanel(self)
    end)
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function PetAlert:OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        print("|cffff4040PetAlert|r Options indisponibles en combat.")
        return
    end

    if Settings and Settings.OpenToCategory then
        local id = registeredCategory and (registeredCategory.ID or (registeredCategory.GetID and registeredCategory:GetID()))
        local ok = false

        if id then
            ok = pcall(Settings.OpenToCategory, id)
        end
        if ok then return end

        ok = pcall(Settings.OpenToCategory, "PetAlert")
        if ok then return end
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
