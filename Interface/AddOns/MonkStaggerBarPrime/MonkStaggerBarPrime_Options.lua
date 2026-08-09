local MSB_OptionsFrame
local MSB_Sections = {}
local MSB_MenuButtons = {}


local addonName = ...
local title = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Title") or GetAddOnMetadata(addonName, "Title")
local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or GetAddOnMetadata(addonName, "Version")

local UI = {
    SECTION_LEFT = 20,

    ROW_WIDTH = 560,
    ROW_HEIGHT = 24,
    EDIT_WIDTH = 70,
    EDIT_HEIGHT = 22,
    FIELD_X = 130,
    SLIDER_WIDTH = 260,
    SLIDER_OFFSET_X = 90,

    DISPLAY_DROPDOWN_WIDTH = 220,
    SOUND_DROPDOWN_WIDTH = 180,
    BUTTON_GAP = 12,
    SEPARATOR_INSET = 20,

    MENU_Y = {
        DISPLAY = -14,
        POSITION = -44,
        BEHAVIOUR = -74,
        ALERTS = -104,
    },

    DISPLAY_Y = {
        MODE = -60,
        TEXTURE = -94,
        TEXT_MODE = -128,
        WIDTH = -162,
        HEIGHT = -196,
        ICON = -230,
        FONT = -264,
    },

    POSITION_Y = {
        POS_X = -60,
        POS_Y = -94,
        LOCK = -140,
    },

    BEHAVIOUR_Y = {
        HIDE_OOC = -60,
        HIDE_ZERO = -94,
    },

    ALERTS_Y = {
        FLASH_ENABLE = -60,
        FLASH_THRESHOLD = -94,
        SEPARATOR = -130,
        SOUND_ENABLE = -148,
        SOUND_THRESHOLD = -182,
        SOUND_ROW = -221,
    },
}


local function MSB_BuildSoundDropdownItems()
    local items = {}
    local sounds = addonSounds or {}

    for i, soundData in ipairs(sounds) do
        local label

        if type(soundData) == "table" then
            label = soundData.name or soundData.label or ("Sound " .. i)
        else
            label = tostring(soundData)
        end

        items[#items + 1] = {
            value = i,
            label = label,
        }
    end

    return items
end

local function MSB_GetCurrentSoundLabel()
    local sounds = addonSounds or {}
    local idx = MonkStaggerBarPrimeDB and MonkStaggerBarPrimeDB.alertSoundIndex or 1
    local soundData = sounds[idx]

    if type(soundData) == "table" then
        return soundData.name or soundData.label or ("Sound " .. idx)
    elseif soundData ~= nil then
        return tostring(soundData)
    end

    return "Unknown"
end

function MSB_GetSelectedAddonSound(db)
    local idx = tonumber(db.alertSoundIndex) or 1
    idx = Clamp(idx, 1, math.max(#addonSounds, 1))
    db.alertSoundIndex = idx
    return addonSounds[idx], idx
end

function MSB_TryPlaySelectedSound()
    local db = MonkStaggerBarPrimeDB
    if not db or #addonSounds == 0 then return end

    local s = MSB_GetSelectedAddonSound(db)
    if s and s.path then
        PlaySoundFile(s.path, "Master")
    end
end



local function MSB_Color(tex, r, g, b, a)
    tex:SetColorTexture(r, g, b, a)
end

local function MSB_CreateLabel(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    fs:SetText(text or "")
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    else
        fs:SetTextColor(0.92, 0.95, 1.00, 1)
    end
    fs:SetJustifyH("LEFT")
    return fs
end

local function MSB_SelectAll(editBox)
    editBox:HighlightText()
    editBox:SetCursorPosition(0)
end

local function MSB_CreateEditBox(parent, width, height, initialValue, onEnterPressed)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width, height)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontNormal")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetJustifyH("LEFT")
    eb:SetText(tostring(initialValue or ""))

    eb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    eb:SetBackdropColor(0.05, 0.07, 0.11, 0.95)
    eb:SetBackdropBorderColor(0.20, 0.34, 0.52, 1)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.lastValue ~= nil then
            self:SetText(tostring(self.lastValue))
        end
    end)

    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnterPressed then
            onEnterPressed(self, self:GetText())
        end
    end)

    eb:SetScript("OnEditFocusGained", function(self)
        self.lastValue = self:GetText()
        self:HighlightText()
    end)

    eb:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MSB_SelectAll(self)
        end
    end)

    return eb
end

local function MSB_CreateSlider(parent, width, minValue, maxValue, step, initialValue, onValueChanged)
    local slider = CreateFrame("Frame", nil, parent)
    slider:SetSize(width, 16)
    slider:EnableMouse(true)

    slider.minValue = minValue
    slider.maxValue = maxValue
    slider.step = step or 1
    slider.value = initialValue or minValue
    slider.onValueChanged = onValueChanged
    slider.dragging = false

    slider.bg = slider:CreateTexture(nil, "BACKGROUND")
    slider.bg:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -4)
    slider.bg:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 4)
    MSB_Color(slider.bg, 0.07, 0.09, 0.13, 0.95)

    slider.border = slider:CreateTexture(nil, "BORDER")
    slider.border:SetPoint("TOPLEFT", slider.bg, "TOPLEFT", -1, 1)
    slider.border:SetPoint("BOTTOMRIGHT", slider.bg, "BOTTOMRIGHT", 1, -1)
    MSB_Color(slider.border, 0.20, 0.34, 0.52, 1)

    slider.fill = slider:CreateTexture(nil, "ARTWORK")
    slider.fill:SetPoint("TOPLEFT", slider.bg, "TOPLEFT", 1, -1)
    slider.fill:SetPoint("BOTTOMLEFT", slider.bg, "BOTTOMLEFT", 1, 1)
    slider.fill:SetWidth(0)
    MSB_Color(slider.fill, 0.16, 0.46, 0.90, 1)

    slider.thumb = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    slider.thumb:SetSize(14, 20)
    slider.thumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    slider.thumb:SetBackdropColor(0.22, 0.52, 0.98, 1)
    slider.thumb:SetBackdropBorderColor(0.05, 0.08, 0.12, 1)

    function slider:GetValue()
        return self.value
    end

    function slider:SetValue(value)
        local minV, maxV = self.minValue, self.maxValue
        value = math.max(minV, math.min(maxV, value))

        if self.step and self.step > 0 then
            value = minV + math.floor(((value - minV) / self.step) + 0.5) * self.step
            value = math.max(minV, math.min(maxV, value))
        end

        self.value = value

        local pct = 0
        if maxV > minV then
            pct = (value - minV) / (maxV - minV)
        end
        pct = math.max(0, math.min(1, pct))

        local usableWidth = self:GetWidth() - 2
        self.fill:SetWidth(usableWidth * pct)

        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", self:GetWidth() * pct, 0)

        if self.onValueChanged then
            self.onValueChanged(self, value)
        end
    end

    local function setValueFromMouse(self)
        local x = GetCursorPosition()
        local left = self:GetLeft()
        local scale = self:GetEffectiveScale()

        if not left or not scale then
            return
        end

        x = x / scale
        local rel = x - left
        rel = math.max(0, math.min(self:GetWidth(), rel))

        local pct = rel / self:GetWidth()
        local value = self.minValue + (self.maxValue - self.minValue) * pct
        self:SetValue(value)
    end

    slider:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragging = true
            setValueFromMouse(self)
        end
    end)

    slider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.dragging = false
        end
    end)

    slider:SetScript("OnUpdate", function(self)
        if self.dragging then
            setValueFromMouse(self)
        end
    end)

    slider:SetValue(slider.value)
    return slider
end

local function MSB_CreateCheckbox(parent, labelText, initialValue, onClick)
    local btn = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    btn:SetSize(18, 18)

    btn.box = btn:CreateTexture(nil, "BACKGROUND")
    btn.box:SetAllPoints()
    MSB_Color(btn.box, 0.05, 0.07, 0.11, 0.95)

    btn.border = btn:CreateTexture(nil, "BORDER")
    btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    MSB_Color(btn.border, 0.20, 0.34, 0.52, 1)

    btn.check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.check:SetPoint("CENTER", btn, "CENTER", 1, 0)
    btn.check:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    btn.check:SetText("✓")
    btn.check:SetTextColor(0.30, 0.65, 1.0, 1)

    btn.text = MSB_CreateLabel(parent, labelText, 12)
    btn.text:SetPoint("LEFT", btn, "RIGHT", 8, 0)

    btn:SetChecked(initialValue and true or false)
    btn.check:SetShown(btn:GetChecked())

    btn:SetScript("OnClick", function(self)
        self.check:SetShown(self:GetChecked())
        if onClick then
            onClick(self, self:GetChecked())
        end
    end)

    return btn
end

local function MSB_CreateDropdown(parent, width, currentLabel, items, onSelect)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetSize(width, 22)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.07, 0.11, 0.95)
    f:SetBackdropBorderColor(0.20, 0.34, 0.52, 1)

    f.items = items or {}
    f.onSelect = onSelect

    f.text = MSB_CreateLabel(f, currentLabel or "", 12)
    f.text:SetPoint("LEFT", f, "LEFT", 8, 0)

    f.arrow = f:CreateTexture(nil, "OVERLAY")
    f.arrow:SetSize(10, 8)
    f.arrow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.arrow:SetTexture("Interface\\AddOns\\MonkStaggerBarPrime\\Media\\triangle_down")
    f.arrow:SetVertexColor(0.72, 0.82, 1.0, 1)

    f.menu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f.menu:SetBackdropColor(0.05, 0.07, 0.11, 0.98)
    f.menu:SetBackdropBorderColor(0.20, 0.34, 0.52, 1)
    f.menu:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    f.menu:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
    f.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    f.menu:SetFrameLevel(f:GetFrameLevel() + 20)
    f.menu:SetBackdropColor(0.05, 0.07, 0.11, 1)
    f.menu:Hide()
    f.menu:Hide()

    f.menuButtons = {}

    local function hideMenu()
        f.menu:Hide()
    end

    local function rebuildMenu()
        for _, b in ipairs(f.menuButtons) do
            b:Hide()
            b:SetParent(nil)
        end
        wipe(f.menuButtons)

        local itemHeight = 22
        local totalHeight = #f.items * itemHeight
        f.menu:SetHeight(totalHeight)

        for i, item in ipairs(f.items) do
            local value, label

            if type(item) == "table" then
                value = item.value
                label = item.label or tostring(item.value)
            else
                value = item
                label = tostring(item)
            end

            local b = CreateFrame("Button", nil, f.menu)
            b:SetFrameStrata("FULLSCREEN_DIALOG")
            b:SetFrameLevel(f.menu:GetFrameLevel() + i)
            b:SetHeight(itemHeight)
            b:SetPoint("TOPLEFT", f.menu, "TOPLEFT", 0, -((i - 1) * itemHeight))
            b:SetPoint("TOPRIGHT", f.menu, "TOPRIGHT", 0, -((i - 1) * itemHeight))

            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            MSB_Color(b.bg, 0.08, 0.10, 0.14, 0)

            b.text = MSB_CreateLabel(b, label, 12)
            b.text:SetPoint("LEFT", b, "LEFT", 8, 0)

            b:SetScript("OnEnter", function(self)
                MSB_Color(self.bg, 0.14, 0.18, 0.25, 0.7)
            end)

            b:SetScript("OnLeave", function(self)
                MSB_Color(self.bg, 0.08, 0.10, 0.14, 0)
            end)

            b:SetScript("OnClick", function()
                f.text:SetText(label)
                hideMenu()
                if f.onSelect then
                    f.onSelect(value, label)
                end
            end)

            table.insert(f.menuButtons, b)
        end
    end

    rebuildMenu()

    f:SetScript("OnClick", function(self)
        if self.menu:IsShown() then
            hideMenu()
        else
            self.menu:Show()
        end
    end)

    f:SetScript("OnHide", function(self)
        hideMenu()
    end)

    return f
end

local function MSB_CreateButton(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.08, 0.10, 0.15, 0.95)
    b:SetBackdropBorderColor(0.24, 0.38, 0.60, 1)

    b.text = MSB_CreateLabel(b, text, 12)
    b.text:SetPoint("CENTER")

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.11, 0.14, 0.20, 0.95)
    end)

    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.10, 0.15, 0.95)
    end)

    b:SetScript("OnClick", onClick)
    return b
end

local function MSB_CreateSectionButton(parent, text, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(155, 28)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    MSB_Color(btn.bg, 0.08, 0.10, 0.14, 0)

    btn.indicator = btn:CreateTexture(nil, "ARTWORK")
    btn.indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -3)
    btn.indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 3)
    btn.indicator:SetWidth(3)
    MSB_Color(btn.indicator, 0.24, 0.60, 1.0, 1)
    btn.indicator:Hide()

    btn.text = MSB_CreateLabel(btn, text, 13)
    btn.text:SetPoint("LEFT", btn, "LEFT", 12, 0)
    btn.text:SetTextColor(0.92, 0.95, 1.0, 1)

    btn:SetScript("OnEnter", function(self)
        if not self.selected then
            MSB_Color(self.bg, 0.14, 0.18, 0.25, 0.55)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if not self.selected then
            MSB_Color(self.bg, 0.08, 0.10, 0.14, 0)
        end
    end)

    btn:SetScript("OnClick", function()
        for _, b in ipairs(MSB_MenuButtons) do
            b.selected = false
            b.indicator:Hide()
            MSB_Color(b.bg, 0.08, 0.10, 0.14, 0)
            b.text:SetTextColor(0.92, 0.95, 1.0, 1)
        end

        for _, frame in pairs(MSB_Sections) do
            frame:Hide()
        end

        btn.selected = true
        btn.indicator:Show()
        btn.text:SetTextColor(0.35, 0.72, 1.0, 1)
        MSB_Color(btn.bg, 0.08, 0.10, 0.14, 0)

        if MSB_Sections[text] then
            MSB_Sections[text]:Show()
        end
    end)

    table.insert(MSB_MenuButtons, btn)
    return btn
end

local function MSB_CreateOptionRow(parent, y, labelText, value, minV, maxV, step, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(UI.ROW_WIDTH, UI.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.SECTION_LEFT, y)

    row.label = MSB_CreateLabel(row, labelText, 12)
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.edit = MSB_CreateEditBox(row, UI.EDIT_WIDTH, UI.EDIT_HEIGHT, value, function(self, text)
        local n = tonumber(text)
        if not n then
            self:SetText(tostring(self.lastValue or value))
            return
        end

        if step >= 1 then
            n = math.floor(n + 0.5)
        end

        n = math.max(minV, math.min(maxV, n))
        row.slider:SetValue(n)

        if step >= 1 then
            self:SetText(tostring(n))
        else
            self:SetText(string.format("%.2f", n))
        end

        if setter then
            setter(n)
        end
    end)
    row.edit:ClearAllPoints()
    row.edit:SetPoint("LEFT", row.label, "LEFT", UI.FIELD_X, 0)

    row.slider = MSB_CreateSlider(row, UI.SLIDER_WIDTH, minV, maxV, step, value, function(self, newValue)
        local v = step >= 1 and math.floor(newValue + 0.5) or newValue
        if step >= 1 then
            row.edit:SetText(tostring(v))
        else
            row.edit:SetText(string.format("%.2f", v))
        end

        if setter then
            setter(v)
        end
    end)
    row.slider:ClearAllPoints()
    row.slider:SetPoint("LEFT", row.edit, "LEFT", UI.SLIDER_OFFSET_X, 0)

    return row
end

local function MSB_CreateSection(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()

    f.title = MSB_CreateLabel(f, title, 18, {0.35, 0.72, 1.0, 1})
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -20)

    return f
end

function CreateMonkStaggerOptionsWindow()
    if MSB_OptionsFrame then
        MSB_OptionsFrame:Show()
        return MSB_OptionsFrame
    end

    local db = MonkStaggerBarPrimeDB

    local f = CreateFrame("Frame", "MonkStaggerBarPrimeOptions", UIParent, "BackdropTemplate")
    MSB_OptionsFrame = f

    f:SetSize(860, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.03, 0.05, 0.08, 0.78)
    f:SetBackdropBorderColor(0.24, 0.38, 0.60, 1)

    f.titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.titleBar:SetHeight(36)
    f.titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f.titleBar:SetBackdropColor(0.05, 0.07, 0.11, 0.92)
    f.titleBar:SetBackdropBorderColor(0.24, 0.38, 0.60, 1)

    f.title = MSB_CreateLabel(f.titleBar, title .. " Options", 16)
    f.title:SetPoint("CENTER")

    f.close = MSB_CreateButton(f.titleBar, "×", 24, 24, function()
        f:Hide()
    end)
    f.close:SetPoint("RIGHT", f.titleBar, "RIGHT", -6, 0)

    f.leftPane = CreateFrame("Frame", nil, f)
    f.leftPane:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
    f.leftPane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.leftPane:SetWidth(180)

    f.separator = f:CreateTexture(nil, "ARTWORK")
    f.separator:SetPoint("TOPLEFT", f, "TOPLEFT", 180, -36)
    f.separator:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 180, 0)
    f.separator:SetWidth(1)
    MSB_Color(f.separator, 0.24, 0.38, 0.60, 1)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 181, -36)
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    f.footerLine = f:CreateTexture(nil, "ARTWORK")
    f.footerLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 58)
    f.footerLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 58)
    f.footerLine:SetHeight(1)
    MSB_Color(f.footerLine, 0.24, 0.38, 0.60, 1)

    f.version = MSB_CreateLabel(
        f.leftPane,
        string.format("%s\n%s", title or addonName or "Monk Stagger Bar", version or ""),
        11,
        {0.78, 0.84, 0.96, 1}
    )
    f.version:SetPoint("BOTTOMLEFT", f.leftPane, "BOTTOMLEFT", 10, 10)

    MSB_Sections["Display"] = MSB_CreateSection(f.content, "Display")
    MSB_Sections["Position"] = MSB_CreateSection(f.content, "Position")
    MSB_Sections["Behaviour"] = MSB_CreateSection(f.content, "Behaviour")
    MSB_Sections["Alerts"] = MSB_CreateSection(f.content, "Alerts")

    local b1 = MSB_CreateSectionButton(f.leftPane, "Display", UI.MENU_Y.DISPLAY)
    local b2 = MSB_CreateSectionButton(f.leftPane, "Position", UI.MENU_Y.POSITION)
    local b3 = MSB_CreateSectionButton(f.leftPane, "Behaviour", UI.MENU_Y.BEHAVIOUR)
    local b4 = MSB_CreateSectionButton(f.leftPane, "Alerts", UI.MENU_Y.ALERTS)

    do
        local s = MSB_Sections["Display"]

        local l1 = MSB_CreateLabel(s, "Display Mode", 12)
        l1:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.DISPLAY_Y.MODE)
        local dd1 = MSB_CreateDropdown(
            s,
            UI.DISPLAY_DROPDOWN_WIDTH,
            (db.displayMode == 1 and "Bar Only") or "Bar + Icon",
            {
                { value = 1, label = "Bar Only" },
                { value = 2, label = "Icon Only" },
                { value = 3, label = "Bar + Icon" },
            },
            function(value, label)
                db.displayMode = value
                ApplySettings()
            end
        )
        dd1.text:SetText((db.displayMode == 1 and "Bar Only")
            or (db.displayMode == 2 and "Icon Only")
            or "Bar + Icon")
        dd1:SetPoint("LEFT", l1, "LEFT", UI.FIELD_X, 0)

        local l2 = MSB_CreateLabel(s, "Texture", 12)
        l2:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.DISPLAY_Y.TEXTURE)
        local textureItems = {
            { value = 1, label = "Default" },
            { value = 2, label = "Smooth" },
            { value = 3, label = "Striped" },
        }

        local currentTextureLabel = "Default"
        for _, item in ipairs(textureItems) do
            if item.value == db.texture then
                currentTextureLabel = item.label
                break
            end
        end

        local dd2 = MSB_CreateDropdown(
            s,
            UI.DISPLAY_DROPDOWN_WIDTH,
            "Default",
            {
                { value = 1, label = "Default" },
                { value = 2, label = "Smooth" },
                { value = 3, label = "Striped" },
            },
            function(value, label)
                db.texture = value
                ApplySettings()
            end
        )
        dd2.text:SetText(currentTextureLabel)
        dd2:SetPoint("LEFT", l2, "LEFT", UI.FIELD_X, 0)

        local lTextMode = MSB_CreateLabel(s, "Text Display", 12)
        lTextMode:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.DISPLAY_Y.TEXT_MODE)

        local textModeItems = {
            { value = 1, label = "HP Value + Percentage" },
            { value = 2, label = "Percentage Only" },
        }

        local currentTextModeLabel = "HP Value + Percentage"

        for _, item in ipairs(textModeItems) do
            if item.value == db.textMode then
                currentTextModeLabel = item.label
                break
            end
        end

        local ddTextMode = MSB_CreateDropdown(
            s,
            UI.DISPLAY_DROPDOWN_WIDTH,
            currentTextModeLabel,
            textModeItems,
            function(value)
                db.textMode = value
                ApplySettings()
            end
        )

        ddTextMode:SetPoint("LEFT", lTextMode, "LEFT", UI.FIELD_X, 0)

        MSB_CreateOptionRow(s, UI.DISPLAY_Y.WIDTH, "Bar Width", db.width or 420, 200, 1200, 1, function(v)
            db.width = v
            ApplySettings()
        end)

        MSB_CreateOptionRow(s, UI.DISPLAY_Y.HEIGHT, "Bar Height", db.height or 30, 10, 60, 1, function(v)
            db.height = v
            ApplySettings()
        end)

        MSB_CreateOptionRow(s, UI.DISPLAY_Y.ICON, "Icon Size", db.iconSize or 32, 8, 96, 1, function(v)
            db.iconSize = v
            ApplySettings()
        end)

        MSB_CreateOptionRow(s, UI.DISPLAY_Y.FONT, "Font Size", db.fontSize or 12, 8, 32, 1, function(v)
            db.fontSize = v
            ApplySettings()
        end)


    end

    do
        local s = MSB_Sections["Position"]

        MSB_CreateOptionRow(s, UI.POSITION_Y.POS_X, "Pos X", db.posX or 0, -1000, 1000, 1, function(v)
            db.posX = v
            ApplySettings()
        end)

        MSB_CreateOptionRow(s, UI.POSITION_Y.POS_Y, "Pos Y", db.posY or -216, -1000, 1000, 1, function(v)
            db.posY = v
            ApplySettings()
        end)

        local cb = MSB_CreateCheckbox(s, "Lock Bar Position", db.locked, function(_, checked)
            db.locked = checked
        end)
        cb:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.POSITION_Y.LOCK)
    end

    do
        local s = MSB_Sections["Behaviour"]

        local cb1 = MSB_CreateCheckbox(s, "Hide Out of Combat", db.hideOOC, function(_, checked)
            db.hideOOC = checked
            ApplySettings()
        end)
        cb1:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.BEHAVIOUR_Y.HIDE_OOC)

        local cb2 = MSB_CreateCheckbox(s, "Hide at 0 Stagger", db.hideZeroStagger, function(_, checked)
            db.hideZeroStagger = checked
            ApplySettings()
        end)
        cb2:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.BEHAVIOUR_Y.HIDE_ZERO)
    end

    do
        local s = MSB_Sections["Alerts"]

        local cbFlashBorder = MSB_CreateCheckbox(s, "Enable Flashing Border", db.flashEnabled, function(_, checked)
            db.flashEnabled = checked
            UpdateBar()
        end)
        cbFlashBorder:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.ALERTS_Y.FLASH_ENABLE)

        MSB_CreateOptionRow(s, UI.ALERTS_Y.FLASH_THRESHOLD, "Flash Threshold %", db.flashThreshold or 100, 0, 200, 1, function(v)
            db.flashThreshold = v
            UpdateBar()
        end)

        local flashSep = s:CreateTexture(nil, "ARTWORK")
        flashSep:SetColorTexture(0.35, 0.55, 0.85, 0.8)
        flashSep:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SEPARATOR_INSET, UI.ALERTS_Y.SEPARATOR)
        flashSep:SetPoint("TOPRIGHT", s, "TOPRIGHT", -UI.SEPARATOR_INSET, UI.ALERTS_Y.SEPARATOR)
        flashSep:SetHeight(1)

        local cbAlertSound = MSB_CreateCheckbox(s, "Enable Alert Sound", db.alertEnabled, function(_, checked)
            db.alertEnabled = checked
        end)
        cbAlertSound:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.ALERTS_Y.SOUND_ENABLE)

        MSB_CreateOptionRow(s, UI.ALERTS_Y.SOUND_THRESHOLD, "Sound Threshold %", db.alertThreshold or 50, 0, MSBP_SOUND_THRESHOLD_MAX, 1, function(v)
            db.alertThreshold = v
        end)

        local soundLabel = MSB_CreateLabel(s, "Sound", 12)
        soundLabel:SetPoint("TOPLEFT", s, "TOPLEFT", UI.SECTION_LEFT, UI.ALERTS_Y.SOUND_ROW)

        local soundDD = MSB_CreateDropdown(
            s,
            UI.SOUND_DROPDOWN_WIDTH,
            MSB_GetCurrentSoundLabel(),
            MSB_BuildSoundDropdownItems(),
            function(value, label)
                db.alertSoundIndex = value
            end
        )
        soundDD:SetPoint("LEFT", soundLabel, "LEFT", UI.FIELD_X, 0)

        local testBtn = MSB_CreateButton(s, "Test Sound", 80, 22, function()
            MSB_TryPlaySelectedSound()
        end)
        testBtn:SetPoint("LEFT", soundDD, "RIGHT", UI.BUTTON_GAP, 0)
    end

    f.reset = MSB_CreateButton(f, "Reset", 110, 28, function()
        db.width = 420
        db.height = 30
        db.iconSize = 32
        db.fontSize = 12
        db.posX = 0
        db.posY = -216
        db.locked = true
        db.hideOOC = false
        db.hideZeroStagger = false
        db.alertEnabled = true
        db.alertThreshold = 50
        db.flashEnabled = true
        db.flashThreshold = 100
        ApplySettings()

        if MSB_OptionsFrame then
            MSB_OptionsFrame:Hide()
            MSB_OptionsFrame = nil
        end

        CreateMonkStaggerOptionsWindow()
    end)
    f.reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -120, 14)

    f.test = MSB_CreateButton(f, "Test", 110, 28, function()
        ToggleStaggerBarTest()
    end)
    f.test:SetPoint("RIGHT", f.reset, "LEFT", -12, 0)

    b1:Click()
    return f
end