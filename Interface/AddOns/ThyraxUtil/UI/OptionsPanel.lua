local addonName, ns = ...
local unpack = unpack or table.unpack

ns.OptionsPanel = ns.OptionsPanel or {}
local OptionsPanel = ns.OptionsPanel

-- [[ START_WIDGETS ]]
local currentYOffset = -16
local layoutPendingHalfY = nil
local classicSliderCounter = 0
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Settings search index. Populated automatically by CreateRow / CreateHeader
-- as each page builder runs during OptionsPanel:Build(). Cleared in :Rebuild().
-- Each entry: { label, tooltip, pageIndex, pageLabel, headerLabel }.
-- Build() sets currentSearchContext before invoking a page builder so rows
-- registered during that builder know which tab they belong to; the header
-- field tracks the most recent CreateHeader call within the same builder.
local searchIndex = {}
local currentSearchContext = nil

-- Themed-widget repaint registry. Every Create* in this file that bakes an
-- accent / header / surface color into a widget at creation time also pushes
-- a closure here that re-tints that widget from the current palette. Calling
-- OptionsPanel:RepaintThemedWidgets() walks the list and refreshes them all
-- WITHOUT recreating frames - that's what lets accent / custom-font changes
-- avoid Rebuild (which orphans ~1 MB of frames per call since WoW can't
-- destroy them). Cleared in :Rebuild() so closures don't keep dead widgets
-- alive across rebuilds.
local themedRepaintFns = {}

-- Shared color helper from Core/Color.lua (identical clamp semantics).
local Clamp = ns.Color.Clamp

-- Resolves the current global accent palette (RGB tuples). Widget creators
-- call this so toggle / slider / window-border colors follow the user's
-- chosen accent preset instead of being hard-coded gold. Fallback to the
-- Gold palette when UI module isn't loaded yet (e.g. very early init).
local DEFAULT_ACCENT_PALETTE = {
    accent      = { 0.95, 0.78, 0.30, 1 },
    accentSoft  = { 0.72, 0.62, 0.28, 1 },
    accentEdge  = { 0.55, 0.45, 0.18, 0.90 },
    surface     = { 0.18, 0.13, 0.07, 0.95 },
    surfaceDark = { 0.14, 0.11, 0.05, 1 },
    header      = { 1.00, 0.82, 0.30, 1 },
}
local function GetAccentPalette()
    if ns.UI and ns.UI.GetAccentPalette then
        return ns.UI:GetAccentPalette() or DEFAULT_ACCENT_PALETTE
    end
    return DEFAULT_ACCENT_PALETTE
end

-- Compact helper for hardcoded-color call sites: returns the 4 RGBA
-- components of the named palette entry with an optional alpha override.
-- Use as: tex:SetColorTexture(PaletteRGBA("surface", 0.95))
local function PaletteRGBA(key, alpha)
    local p = GetAccentPalette()
    local c = p[key] or p.surface
    return c[1], c[2], c[3], alpha or c[4] or 1
end

-- Coalesces rapid slider updates into a single trailing call so the
-- expensive onChange / RefreshAll path runs at most once per `delay`
-- seconds while the user is dragging.
local function CreateDebouncedCall(fn, delay)
    delay = delay or 0.08
    local pending
    local scheduled = false
    return function(value)
        pending = value
        if scheduled then return end
        scheduled = true
        C_Timer.After(delay, function()
            scheduled = false
            local v = pending
            pending = nil
            if fn then fn(v) end
        end)
    end
end

local function IsModernTheme()
    return ns.Settings and ns.Settings.GetTheme and ns.Settings:GetTheme() == "Modern"
end

local function IsClassicTheme()
    return ns.Settings and ns.Settings.GetTheme and ns.Settings:GetTheme() == "Classic"
end

-- Shared color helper from Core/Color.lua. Note: ns.Color.Normalize returns a
-- sanitised fallback COPY for malformed input (the old local returned the
-- fallback table by reference); callers here only read the result, so the copy
-- is safe and avoids accidental shared-table mutation.
local NormalizeColor = ns.Color.Normalize

local function GetModuleDefaultColor(moduleID, key, fallback)
    local mod = ns.ModuleRegistry and ns.ModuleRegistry.GetModule and ns.ModuleRegistry:GetModule(moduleID)
    local value = mod and type(mod.defaults) == "table" and mod.defaults[key]
    if type(value) == "table" then
        return value
    end
    return fallback
end

local function SetTextureColor(texture, color)
    if not texture then return end
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function CreateTextureBorder(frame, thickness)
    thickness = thickness or 1
    local border = {
        top = frame:CreateTexture(nil, "BORDER"),
        right = frame:CreateTexture(nil, "BORDER"),
        bottom = frame:CreateTexture(nil, "BORDER"),
        left = frame:CreateTexture(nil, "BORDER"),
    }
    border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.top:SetHeight(thickness)
    border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(thickness)
    border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(thickness)
    border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(thickness)
    return border
end

local function SetTextureBorderColor(border, r, g, b, a)
    if type(border) ~= "table" then return end
    for _, tex in pairs(border) do
        tex:SetTexture(WHITE_TEXTURE)
        tex:SetVertexColor(r, g, b, a or 1)
    end
end

-- Wire a frame to show / hide a GameTooltip on hover. Reusable across all
-- input widgets so we have a single place to evolve the tooltip style.
-- Safe to call with a nil or empty tooltip (no-op), so callers can forward
-- the parameter unconditionally.
local function AttachTooltip(frame, tooltipText)
    if not frame or type(tooltipText) ~= "string" or tooltipText == "" then return end
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local COLUMN_GAP = 10

local function CreateRow(parent, labelText, tooltip, half)
    local rowHeight = 36
    local row = CreateFrame("Frame", nil, parent)

    -- Two-column flow: a half-width row pairs with the next half-width row on
    -- the same line; a full-width row (or header) closes any pending half.
    -- Rows anchor to the content frame so they stretch when the window resizes.
    local rowY, mode
    -- Row gap matches COLUMN_GAP so vertical and horizontal spacing read
    -- consistent in the 2-column grid.
    local rowGap = COLUMN_GAP
    if half then
        if layoutPendingHalfY then
            rowY, mode = layoutPendingHalfY, "right"
            layoutPendingHalfY = nil
        else
            rowY, mode = currentYOffset, "left"
            layoutPendingHalfY = currentYOffset
            currentYOffset = currentYOffset - rowHeight - rowGap
        end
    else
        layoutPendingHalfY = nil
        rowY, mode = currentYOffset, "full"
        currentYOffset = currentYOffset - rowHeight - rowGap
    end

    row:SetHeight(rowHeight)
    if mode == "left" then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, rowY)
        row:SetPoint("TOPRIGHT", parent, "TOP", -(COLUMN_GAP / 2), rowY)
    elseif mode == "right" then
        row:SetPoint("TOPLEFT", parent, "TOP", COLUMN_GAP / 2, rowY)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, rowY)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, rowY)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, rowY)
    end

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.03)

    local rowLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rowLabel:SetPoint("LEFT", row, "LEFT", 16, 0)
    -- Default-left so every widget reads consistently; some font objects
    -- default to CENTER which produced the "label sometimes centered,
    -- sometimes left" inconsistency in the old layout.
    rowLabel:SetJustifyH("LEFT")
    rowLabel:SetText(labelText)

    -- Tooltip on the row so hovering anywhere on the row shows the explanation.
    AttachTooltip(row, tooltip)

    -- Register this row in the global settings-search index when we are
    -- inside a page builder. Empty-label rows (action button rows produced
    -- by CreateActionBtn) are skipped: they have no searchable text.
    if currentSearchContext and type(labelText) == "string" and labelText ~= "" then
        searchIndex[#searchIndex + 1] = {
            label = labelText,
            tooltip = type(tooltip) == "string" and tooltip or "",
            pageIndex = currentSearchContext.pageIndex,
            pageLabel = currentSearchContext.pageLabel or "",
            headerLabel = currentSearchContext.header or "",
            row = row,
        }
    end

    return row, rowLabel
end

local function CreateHeader(parent, labelText)
    layoutPendingHalfY = nil
    -- Same gap before / after as between rows so headers integrate with the
    -- grid rhythm (no random extra padding).
    currentYOffset = currentYOffset - COLUMN_GAP
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, currentYOffset)
    header:SetText(labelText)
    header:SetTextColor(PaletteRGBA("header"))
    currentYOffset = currentYOffset - 14 - COLUMN_GAP
    -- Track the active section header so subsequent CreateRow registrations
    -- can stamp the section name into their search-index entry.
    if currentSearchContext then
        currentSearchContext.header = labelText or ""
    end
    themedRepaintFns[#themedRepaintFns + 1] = function()
        header:SetTextColor(PaletteRGBA("header"))
    end
    return header
end

local function ResetLayout()
    currentYOffset = -16
    layoutPendingHalfY = nil
end

-- Modern toggle (custom switch, golden/ElvUI style)
local function CreateToggleSwitch(parent, labelText, onChange, tooltip)
    -- Every toggle is half-width so the 2-column grid stays regular regardless
    -- of label length; long labels clip at the switch instead of pushing the
    -- whole row to full width.
    local half = true
    local row, label = CreateRow(parent, labelText, tooltip, half)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(44, 24)
    btn:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)
    local knob = btn:CreateTexture(nil, "ARTWORK")
    knob:SetSize(20, 20)
    knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
    knob:SetColorTexture(1, 1, 1, 1)
    local isChecked = false
    local function UpdateVisuals()
        local palette = GetAccentPalette()
        if isChecked then
            bg:SetColorTexture(unpack(palette.accentSoft))
            knob:ClearAllPoints()
            knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            bg:SetColorTexture(unpack(palette.surface))
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
        end
    end

    btn:SetScript("OnClick", function()
        if ns.OptionsPanel.refreshing then return end
        isChecked = not isChecked
        UpdateVisuals()
        onChange(isChecked)
    end)
    -- Toggle bg / knob colors come from palette.accentSoft / palette.surface;
    -- UpdateVisuals already pulls fresh palette on each call, so we just hook
    -- it into the repaint pass.
    themedRepaintFns[#themedRepaintFns + 1] = UpdateVisuals
    return {
        row = row, btn = btn, label = label,
        SetChecked = function(self, val) isChecked = val and true or false; UpdateVisuals() end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Classic toggle (WoW native CheckButton)
local function CreateToggleClassic(parent, labelText, onChange, tooltip)
    -- Every toggle is half-width so the 2-column grid stays regular regardless
    -- of label length; long labels clip at the switch instead of pushing the
    -- whole row to full width.
    local half = true
    local row, label = CreateRow(parent, labelText, tooltip, half)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetPoint("RIGHT", cb, "LEFT", -6, 0)
    local isChecked = false
    cb:SetScript("OnClick", function(self)
        if ns.OptionsPanel.refreshing then return end
        isChecked = self:GetChecked() and true or false
        onChange(isChecked)
    end)
    return {
        row = row, btn = cb, label = label,
        SetChecked = function(self, val)
            isChecked = val and true or false
            cb:SetChecked(isChecked)
        end,
        SetEnabled = function(self, enabled)
            cb:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Modern keybind button (custom, golden style)
local function CreateKeybindButton(parent, labelText, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(100, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PaletteRGBA("surface", 0.95))
    local btnText = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local isListening = false
    local currentValue = "NONE"
    local function StopListening()
        isListening = false
        btnText:SetText(currentValue or "NONE")
        btn:EnableKeyboard(false)
        btn:SetScript("OnKeyDown", nil)
        btn:SetScript("OnMouseWheel", nil)
        bg:SetColorTexture(PaletteRGBA("surface", 0.95))
    end
    themedRepaintFns[#themedRepaintFns + 1] = function()
        if not isListening then
            bg:SetColorTexture(PaletteRGBA("surface", 0.95))
        end
    end

    local function HandleInput(self, key)
        if key == "UNKNOWN" then return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
        if key == "ESCAPE" then StopListening(); return end
        local prefix = ""
        if IsAltKeyDown() then prefix = prefix .. "ALT-" end
        if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
        if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
        currentValue = prefix .. key
        StopListening()
        onChange(currentValue)
    end

    btn:SetScript("OnClick", function()
        if ns.OptionsPanel.refreshing then return end
        if isListening then
            StopListening()
        else
            isListening = true
            btnText:SetText("Press a key...")
            btn:EnableKeyboard(true)
            bg:SetColorTexture(0.30, 0.22, 0.10, 0.95)
            btn:SetScript("OnKeyDown", HandleInput)
            btn:SetScript("OnMouseWheel",
                function(self, delta) HandleInput(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        end
    end)
    return {
        row = row,
        SetValue = function(self, val) currentValue = val; if not isListening then btnText:SetText(val or "NONE") end end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Classic keybind button (WoW native UIPanelButtonTemplate)
local function CreateKeybindClassic(parent, labelText, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(100, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    btn:SetText("NONE")
    local isListening = false
    local currentValue = "NONE"
    local function StopListening()
        isListening = false
        btn:SetText(currentValue or "NONE")
        btn:EnableKeyboard(false)
        btn:SetScript("OnKeyDown", nil)
        btn:SetScript("OnMouseWheel", nil)
    end

    local function HandleInput(self, key)
        if key == "UNKNOWN" then return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
        if key == "ESCAPE" then StopListening(); return end
        local prefix = ""
        if IsAltKeyDown() then prefix = prefix .. "ALT-" end
        if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
        if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
        currentValue = prefix .. key
        StopListening()
        onChange(currentValue)
    end

    btn:SetScript("OnClick", function()
        if ns.OptionsPanel.refreshing then return end
        if isListening then
            StopListening()
        else
            isListening = true
            btn:SetText("Press a key...")
            btn:EnableKeyboard(true)
            btn:SetScript("OnKeyDown", HandleInput)
            btn:SetScript("OnMouseWheel",
                function(self, delta) HandleInput(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        end
    end)
    return {
        row = row,
        SetValue = function(self, val) currentValue = val; if not isListening then btn:SetText(val or "NONE") end end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Modern slider (custom, golden style)
local function CreateSliderM(parent, labelText, minValue, maxValue, step, decimals, onChange, tooltip)
    -- Half-width row so sliders share the same 2-column grid as toggles.
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    local editBox = CreateFrame("EditBox", nil, row)
    editBox:SetAutoFocus(false)
    editBox:SetSize(58, 18)
    editBox:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetJustifyH("CENTER")
    local editBg = editBox:CreateTexture(nil, "BACKGROUND")
    editBg:SetAllPoints()
    -- Same accent-tinted fill as the slider track so the numeric input reads
    -- as part of the same control. No border (the fill alone differentiates
    -- the field from the row background).
    editBg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("RIGHT", editBox, "LEFT", -6, 0)
    slider:SetSize(90, 12)
    label:SetPoint("RIGHT", slider, "LEFT", -6, 0)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local sbg = slider:CreateTexture(nil, "BACKGROUND")
    sbg:SetPoint("LEFT", 0, 0)
    sbg:SetPoint("RIGHT", 0, 0)
    sbg:SetHeight(4)
    -- Accent-tinted track instead of the near-invisible dark surface tone, so
    -- the slider reads as a real bar against the dim row background.
    sbg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    themedRepaintFns[#themedRepaintFns + 1] = function()
        sbg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
        editBg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    end
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(0.8, 0.8, 0.8, 1)
    slider:SetThumbTexture(thumb)
    local formatPattern = "%." .. tostring(decimals or 0) .. "f"
    local function UpdateEditBox(v) editBox:SetText(format(formatPattern, v)) end
    -- Coalesce drag-induced OnValueChanged storms so live-resizing slot
    -- markers / icons does not stutter the game while flying or in combat.
    local debouncedChange = CreateDebouncedCall(onChange, 0.08)

    slider:SetScript("OnValueChanged",
        function(_, value) UpdateEditBox(value); if ns.OptionsPanel.refreshing then return end debouncedChange(value) end)
    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            num = Clamp(num, minValue, maxValue)
            if step and step > 0 then num = math.floor(num / step + 0.5) * step end
            slider:SetValue(num)
            UpdateEditBox(num)
            if not ns.OptionsPanel.refreshing then onChange(num) end
        else UpdateEditBox(slider:GetValue()) end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self) UpdateEditBox(slider:GetValue()); self:ClearFocus() end)
    return {
        row = row, slider = slider, editBox = editBox, label = label,
        SetValue = function(self, value)
            local n = tonumber(value) or minValue
            n = Clamp(n, minValue, maxValue)
            slider:SetValue(n)
            UpdateEditBox(n)
        end,
        SetEnabled = function(self, enabled)
            if enabled then
                slider:Enable();
                slider:EnableMouse(true)
                editBox:EnableMouse(true);
                editBox:SetTextColor(1, 1, 1, 1)
                row:SetAlpha(1);
                label:SetTextColor(1, 1, 1, 1)
            else
                slider:Disable();
                slider:EnableMouse(false)
                editBox:EnableMouse(false);
                editBox:SetTextColor(0.55, 0.55, 0.55, 1)
                row:SetAlpha(0.5);
                label:SetTextColor(0.55, 0.55, 0.55, 1)
            end
        end,
    }
end

-- Classic slider (standard WoW look + InputBoxTemplate editbox)
local function CreateSliderClassic(parent, labelText, minValue, maxValue, step, decimals, onChange, tooltip)
    -- Half-width row so sliders share the same 2-column grid as toggles.
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(58, 18)
    editBox:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetJustifyH("CENTER")
    editBox:SetNumeric(false)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("RIGHT", editBox, "LEFT", -6, 0)
    slider:SetSize(90, 12)
    label:SetPoint("RIGHT", slider, "LEFT", -6, 0)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local sbg = slider:CreateTexture(nil, "BACKGROUND")
    sbg:SetPoint("LEFT", 0, 0)
    sbg:SetPoint("RIGHT", 0, 0)
    sbg:SetHeight(4)
    sbg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    sbg:SetTexCoord(0, 1, 0.25, 0.75)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 14)
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetThumbTexture(thumb)
    local formatPattern = "%." .. tostring(decimals or 0) .. "f"
    local function UpdateEditBox(v) editBox:SetText(format(formatPattern, v)) end
    local debouncedChange = CreateDebouncedCall(onChange, 0.08)

    slider:SetScript("OnValueChanged",
        function(_, value) UpdateEditBox(value); if ns.OptionsPanel.refreshing then return end debouncedChange(value) end)
    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            num = Clamp(num, minValue, maxValue)
            if step and step > 0 then num = math.floor(num / step + 0.5) * step end
            slider:SetValue(num)
            UpdateEditBox(num)
            if not ns.OptionsPanel.refreshing then onChange(num) end
        else UpdateEditBox(slider:GetValue()) end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self) UpdateEditBox(slider:GetValue()); self:ClearFocus() end)
    return {
        row = row, slider = slider, editBox = editBox, label = label,
        SetValue = function(self, value)
            local n = tonumber(value) or minValue
            n = Clamp(n, minValue, maxValue)
            slider:SetValue(n)
            UpdateEditBox(n)
        end,
        SetEnabled = function(self, enabled)
            if enabled then
                slider:Enable();
                slider:EnableMouse(true)
                editBox:EnableMouse(true);
                editBox:SetTextColor(1, 1, 1, 1)
                row:SetAlpha(1);
                label:SetTextColor(1, 1, 1, 1)
            else
                slider:Disable();
                slider:EnableMouse(false)
                editBox:EnableMouse(false);
                editBox:SetTextColor(0.55, 0.55, 0.55, 1)
                row:SetAlpha(0.5);
                label:SetTextColor(0.55, 0.55, 0.55, 1)
            end
        end,
    }
end

local dropdownMenuFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
dropdownMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
if dropdownMenuFrame.SetBackdrop then
    dropdownMenuFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
end
local menuEntries = {}
-- Re-tint the popup to the current accent every time it shows, so the user's
-- theme choice propagates without an addon reload.
local function ApplyDropdownPopupTheme()
    if not dropdownMenuFrame.SetBackdropColor then return end
    local p = GetAccentPalette()
    dropdownMenuFrame:SetBackdropColor(p.surfaceDark[1], p.surfaceDark[2], p.surfaceDark[3], 0.95)
    dropdownMenuFrame:SetBackdropBorderColor(p.accentEdge[1], p.accentEdge[2], p.accentEdge[3], 1)
    for _, entry in ipairs(menuEntries) do
        if entry._bg then
            entry._bg:SetColorTexture(0.3, 0.55, 1, 0)
        end
        if entry.text then
            entry.text:SetTextColor(p.header[1], p.header[2], p.header[3], 1)
        end
    end
end
ApplyDropdownPopupTheme()
dropdownMenuFrame:HookScript("OnShow", ApplyDropdownPopupTheme)
dropdownMenuFrame:Hide()
local closeFrame = CreateFrame("Frame", nil, UIParent)
closeFrame:SetAllPoints(UIParent)
closeFrame:SetFrameStrata("FULLSCREEN")
closeFrame:Hide()
closeFrame:SetScript("OnMouseDown", function() dropdownMenuFrame:Hide(); closeFrame:Hide() end)
local function GetMenuEntry(i)
    if not menuEntries[i] then
        local entry = CreateFrame("Button", nil, dropdownMenuFrame)
        entry:SetHeight(22)
        local entryBg = entry:CreateTexture(nil, "BACKGROUND")
        entryBg:SetAllPoints()
        entryBg:SetColorTexture(0.3, 0.55, 1, 0)
        entry._bg = entryBg
        local entryText = entry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        entryText:SetPoint("LEFT", entry, "LEFT", 8, 0)
        entry:SetScript("OnEnter", function()
            if IsModernTheme() then
                entryBg:SetColorTexture(PaletteRGBA("accentSoft", 0.25))
            else
                entryBg:SetColorTexture(0.3, 0.55, 1, 0.25)
            end
        end)
        entry:SetScript("OnLeave", function() entryBg:SetColorTexture(0.3, 0.55, 1, 0) end)
        entry.text = entryText
        menuEntries[i] = entry
    end
    return menuEntries[i]
end

local function CreateDropdownM(parent, labelText, width, options, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    -- Cap dropdown width so it always fits the half-row; long option text
    -- truncates when displayed in the closed state but the open menu shows
    -- the full text.
    width = math.min(width or 130, 130)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(width, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- Accent-tinted fill, matches the slider track look. No border: the fill
    -- alone is enough to read the field, and a border on top of it competes
    -- visually with neighbouring native widgets.
    if IsModernTheme() then
        bg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    else
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    end
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(PaletteRGBA("header"))
    local valueLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("LEFT", btn, "LEFT", 8, 0)
    valueLabel:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    valueLabel:SetJustifyH("LEFT")
    local currentValue = options[1] and options[1].value or ""
    btn:SetScript("OnClick", function()
        if dropdownMenuFrame:IsShown() and dropdownMenuFrame.activeBtn == btn then
            dropdownMenuFrame:Hide()
            closeFrame:Hide()
            return
        end
        dropdownMenuFrame.activeBtn = btn
        for i, entry in ipairs(menuEntries) do entry:Hide() end
        dropdownMenuFrame:SetWidth(width)
        dropdownMenuFrame:SetHeight(#options * 22)
        dropdownMenuFrame:ClearAllPoints()
        dropdownMenuFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0)
        for i, opt in ipairs(options) do
            local entry = GetMenuEntry(i)
            entry:SetWidth(width)
            entry:SetPoint("TOPLEFT", dropdownMenuFrame, "TOPLEFT", 0, -(i - 1) * 22)
            entry.text:SetText(opt.display or opt.value)
            if entry._bg then entry._bg:SetColorTexture(0.3, 0.55, 1, 0) end
            entry:SetScript("OnClick", function()
                currentValue = opt.value
                valueLabel:SetText(opt.display or opt.value)
                dropdownMenuFrame:Hide()
                closeFrame:Hide()
                if not ns.OptionsPanel.refreshing then onChange(currentValue) end
            end)
            entry:Show()
        end
        ApplyDropdownPopupTheme()
        dropdownMenuFrame:Show()
        closeFrame:Show()
    end)
    themedRepaintFns[#themedRepaintFns + 1] = function()
        if IsModernTheme() then
            bg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
        end
        arrow:SetVertexColor(PaletteRGBA("header"))
    end
    return {
        row = row, btn = btn, bg = bg, arrow = arrow, valueLabel = valueLabel,
        SetWidth = function(self, newWidth)
            width = math.min(newWidth or width or 130, 130)
            btn:SetWidth(width)
        end,
        SetValue = function(self, value)
            currentValue = value
            local d = value
            for _, opt in ipairs(options) do if opt.value == value then d = opt.display or opt.value; break end end
            valueLabel:SetText(d)
            if IsModernTheme() then
                bg:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
                arrow:SetVertexColor(PaletteRGBA("header"))
            end
        end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            valueLabel:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            if IsModernTheme() then
                bg:SetColorTexture(PaletteRGBA("accentSoft", enabled and 0.55 or 0.25))
                arrow:SetVertexColor(PaletteRGBA("header"))
            end
        end,
    }
end

-- Classic drop down (WoW native UIPanelButtonTemplate but with custom flyout)
local function CreateDropdownClassic(parent, labelText, width, options, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    width = math.min(width or 130, 130)
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    -- UIPanelButtonTemplate ships its own border; an extra custom border on
    -- top doubles up and makes Classic dropdowns indistinguishable from
    -- Classic action buttons. Drop the custom border entirely.

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(PaletteRGBA("header"))

    local valueLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("LEFT", btn, "LEFT", 8, 0)
    valueLabel:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    valueLabel:SetJustifyH("LEFT")

    local currentValue = options[1] and options[1].value or ""
    btn:SetScript("OnClick", function()
        if dropdownMenuFrame:IsShown() and dropdownMenuFrame.activeBtn == btn then
            dropdownMenuFrame:Hide()
            closeFrame:Hide()
            return
        end
        dropdownMenuFrame.activeBtn = btn
        for i, entry in ipairs(menuEntries) do entry:Hide() end
        dropdownMenuFrame:SetWidth(width)
        dropdownMenuFrame:SetHeight(#options * 22)
        dropdownMenuFrame:ClearAllPoints()
        dropdownMenuFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0)
        for i, opt in ipairs(options) do
            local entry = GetMenuEntry(i)
            entry:SetWidth(width)
            entry:SetPoint("TOPLEFT", dropdownMenuFrame, "TOPLEFT", 0, -(i - 1) * 22)
            entry.text:SetText(opt.display or opt.value)
            if entry._bg then entry._bg:SetColorTexture(0.3, 0.55, 1, 0) end
            entry:SetScript("OnClick", function()
                currentValue = opt.value
                valueLabel:SetText(opt.display or opt.value)
                dropdownMenuFrame:Hide()
                closeFrame:Hide()
                if not ns.OptionsPanel.refreshing then onChange(currentValue) end
            end)
            entry:Show()
        end
        ApplyDropdownPopupTheme()
        dropdownMenuFrame:Show()
        closeFrame:Show()
    end)
    themedRepaintFns[#themedRepaintFns + 1] = function()
        arrow:SetVertexColor(PaletteRGBA("header"))
    end
    return {
        row = row, btn = btn, arrow = arrow, valueLabel = valueLabel,
        SetWidth = function(self, newWidth)
            width = math.min(newWidth or width or 130, 130)
            btn:SetWidth(width)
        end,
        SetValue = function(self, value)
            currentValue = value
            local d = value
            for _, opt in ipairs(options) do if opt.value == value then d = opt.display or opt.value; break end end
            valueLabel:SetText(d)
            arrow:SetVertexColor(PaletteRGBA("header"))
        end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            valueLabel:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            arrow:SetVertexColor(PaletteRGBA("header"))
        end,
    }
end

local function OpenColorPicker(initialColor, onChanged)
    if not ColorPickerFrame then return end
    local base = NormalizeColor(initialColor, { 1, 1, 1, 1 })
    local function ApplyFromFrame()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local alpha = 1
        if OpacitySliderFrame and OpacitySliderFrame.GetValue then alpha = 1 - OpacitySliderFrame:GetValue() end
        onChanged({ r, g, b, alpha })
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = base[1], g = base[2], b = base[3], opacity = 1 - base[4],
            hasOpacity = true, swatchFunc = ApplyFromFrame, opacityFunc = ApplyFromFrame,
            cancelFunc = function() onChanged(base) end })
        return
    end
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = 1 - base[4]
    ColorPickerFrame.previousValues = { r = base[1], g = base[2], b = base[3], opacity = 1 - base[4] }
    ColorPickerFrame.func = ApplyFromFrame
    ColorPickerFrame.opacityFunc = ApplyFromFrame
    ColorPickerFrame.cancelFunc = function(p)
        if type(p) == "table" then
            onChanged({ tonumber(p.r) or base[1], tonumber(p.g) or base[2], tonumber(p.b) or base[3],
                1 - (tonumber(p.opacity) or (1 - base[4])) })
        else onChanged(base) end
    end
    ColorPickerFrame:SetColorRGB(base[1], base[2], base[3])
    ColorPickerFrame:Show()
end

-- Modern color picker (custom button, golden style)
local function CreateColorPickerM(parent, labelText, onChange)
    local row, label = CreateRow(parent, labelText, nil, true)
    label:SetWordWrap(false)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(40, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PaletteRGBA("surface", 0.95))
    local swatch = btn:CreateTexture(nil, "OVERLAY")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
    local currentColor = { 1, 1, 1, 1 }
    local function UpdateSwatch()
        swatch:SetVertexColor(currentColor[1], currentColor[2], currentColor[3], currentColor[4] or 1)
    end

    btn:SetScript("OnClick", function()
        OpenColorPicker(currentColor, function(color)
            currentColor = NormalizeColor(color, currentColor)
            UpdateSwatch()
            if not ns.OptionsPanel.refreshing then onChange(currentColor) end
        end)
    end)
    return {
        row = row,
        SetValue = function(self, color) currentColor = NormalizeColor(color, { 1, 1, 1, 1 }); UpdateSwatch() end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Classic color picker (WoW native UIPanelButtonTemplate)
local function CreateColorPickerClassic(parent, labelText, onChange)
    local row, label = CreateRow(parent, labelText, nil, true)
    label:SetWordWrap(false)
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(40, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    local swatch = btn:CreateTexture(nil, "OVERLAY")
    swatch:SetPoint("TOPLEFT", 4, -4)
    swatch:SetPoint("BOTTOMRIGHT", -4, 4)
    swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
    local currentColor = { 1, 1, 1, 1 }
    local function UpdateSwatch()
        swatch:SetVertexColor(currentColor[1], currentColor[2], currentColor[3], currentColor[4] or 1)
    end

    btn:SetScript("OnClick", function()
        OpenColorPicker(currentColor, function(color)
            currentColor = NormalizeColor(color, currentColor)
            UpdateSwatch()
            if not ns.OptionsPanel.refreshing then onChange(currentColor) end
        end)
    end)
    return {
        row = row,
        SetValue = function(self, color) currentColor = NormalizeColor(color, { 1, 1, 1, 1 }); UpdateSwatch() end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Modern edit box (custom, golden style)
local function CreateEditBoxM(parent, labelText, width, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    width = math.min(width or 110, 130)
    local editBg = CreateFrame("Frame", nil, row)
    editBg:SetSize(width, 22)
    editBg:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetPoint("RIGHT", editBg, "LEFT", -6, 0)
    local bgTex = editBg:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    -- Accent-tinted fill (same as slider track / dropdown) instead of a
    -- surface tone with a header-coloured border on top. One visual style
    -- across all three input widgets.
    bgTex:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    themedRepaintFns[#themedRepaintFns + 1] = function()
        bgTex:SetColorTexture(PaletteRGBA("accentSoft", 0.55))
    end
    local editBox = CreateFrame("EditBox", nil, editBg)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", -6, 2)
    editBox:SetFontObject("GameFontHighlightSmall")
    local function Commit() if ns.OptionsPanel.refreshing then return end onChange(editBox:GetText() or "") end

    editBox:SetScript("OnEnterPressed", function() Commit(); editBox:ClearFocus() end)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus(); ns.OptionsPanel:Refresh() end)
    editBox:SetScript("OnEditFocusLost", Commit)
    return {
        row = row, editBox = editBox,
        SetValue = function(self, value) editBox:SetText(value or "") end,
        SetEnabled = function(self, enabled)
            editBox:EnableMouse(enabled)
            editBox:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

-- Classic edit box (WoW native InputBoxTemplate)
local function CreateEditBoxClassic(parent, labelText, width, onChange, tooltip)
    local row, label = CreateRow(parent, labelText, tooltip, true)
    label:SetWordWrap(false)
    width = math.min(width or 110, 130)
    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(width, 20)
    editBox:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    editBox:SetFontObject("GameFontHighlightSmall")
    label:SetPoint("RIGHT", editBox, "LEFT", -6, 0)
    local function Commit() if ns.OptionsPanel.refreshing then return end onChange(editBox:GetText() or "") end

    editBox:SetScript("OnEnterPressed", function() Commit(); editBox:ClearFocus() end)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus(); ns.OptionsPanel:Refresh() end)
    editBox:SetScript("OnEditFocusLost", Commit)
    return {
        row = row, editBox = editBox,
        SetValue = function(self, value) editBox:SetText(value or "") end,
        SetEnabled = function(self, enabled)
            editBox:EnableMouse(enabled)
            editBox:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

local function StyleModernButton(btn, bg, label, variant)
    if variant == "danger" then
        bg:SetColorTexture(0.34, 0.07, 0.05, 0.95)
        if label then label:SetTextColor(1.00, 0.68, 0.62, 1) end
        return
    end
    bg:SetColorTexture(PaletteRGBA("surfaceDark", 0.95))
    if label then label:SetTextColor(PaletteRGBA("header")) end
end

local function CreateModernButton(parent, width, height, text, callback, variant)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if variant == "danger" then
        hl:SetColorTexture(0.95, 0.18, 0.12, 0.24)
    else
        hl:SetColorTexture(PaletteRGBA("accentSoft", 0.20))
    end
    local t = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("LEFT", btn, "LEFT", 8, 0)
    t:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    t:SetJustifyH("CENTER")
    t:SetWordWrap(false)
    t:SetText(text)
    btn.label = t
    StyleModernButton(btn, bg, t, variant)
    btn:SetScript("OnClick", function()
        if not ns.OptionsPanel.refreshing then callback() end
    end)
    themedRepaintFns[#themedRepaintFns + 1] = function()
        StyleModernButton(btn, bg, t, variant)
        if variant ~= "danger" then
            hl:SetColorTexture(PaletteRGBA("accentSoft", 0.20))
        end
    end
    return btn
end

local function CreateActionBtn(parent, text, callback, width, variant)
    -- Action buttons live in the same 2-column grid as toggles / sliders so
    -- the overall page reads as one consistent grid rather than a mix of
    -- floating buttons and rows.
    local row = CreateRow(parent, "", nil, true)
    width = width or 200
    local btn
    if IsClassicTheme() then
        btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(width, 24)
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            if not ns.OptionsPanel.refreshing then callback() end
        end)
    else
        btn = CreateModernButton(row, width, 24, text, callback, variant)
    end
    btn:SetPoint("CENTER", row, "CENTER", 0, 0)
    return btn
end

local function CreateActionButtonRow(parent, specs, columns, buttonWidth)
    columns = columns or #specs
    buttonWidth = buttonWidth or 132
    -- Match the grid's row gap on entry so multi-button rows align with the
    -- surrounding half-width rows above them.
    layoutPendingHalfY = nil
    currentYOffset = currentYOffset - COLUMN_GAP
    local row = CreateFrame("Frame", nil, parent)
    local buttonHeight = 24
    local gap = 8
    local rows = math.ceil(#specs / columns)
    row:SetSize(460, rows * buttonHeight + math.max(0, rows - 1) * gap)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, currentYOffset)
    local result = { row = row }
    for i, spec in ipairs(specs) do
        local col = (i - 1) % columns
        local line = math.floor((i - 1) / columns)
        local btn
        if IsClassicTheme() then
            btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            btn:SetSize(buttonWidth, buttonHeight)
            btn:SetText(spec.text)
            btn:SetScript("OnClick", function()
                if not ns.OptionsPanel.refreshing then spec.callback() end
            end)
        else
            btn = CreateModernButton(row, buttonWidth, buttonHeight, spec.text, spec.callback, spec.variant)
        end
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", col * (buttonWidth + gap), -line * (buttonHeight + gap))
        if spec.tooltip then
            btn:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(spec.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        end
        result[spec.key or i] = btn
    end
    currentYOffset = currentYOffset - row:GetHeight() - COLUMN_GAP
    return result
end

local function CreateThemeColorRow(parent, moduleID, onApply)
    local row, label = CreateRow(parent, "Theme colors", nil, true)
    label:SetWordWrap(false)
    -- Fall back to the global accent palette so a module without its own
    -- accentColor still defaults to the same color the rest of the UI uses.
    local globalPalette = GetAccentPalette()
    local accentFallback = GetModuleDefaultColor(moduleID, "accentColor", globalPalette.accent)
    local surfaceFallback = GetModuleDefaultColor(moduleID, "surfaceColor", globalPalette.surface)
    local currentAccent = accentFallback
    local currentSurface = surfaceFallback
    local customEnabled = false

    local function Apply()
        ns.ModuleRegistry:ApplyModuleSettings(moduleID)
        if type(onApply) == "function" then
            onApply()
        else
            ns.OptionsPanel:Refresh()
        end
    end

    local toggle = CreateFrame("Button", nil, row)
    toggle:SetSize(70, 24)
    toggle:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    local toggleBg = toggle:CreateTexture(nil, "BACKGROUND")
    toggleBg:SetAllPoints()
    local toggleText = toggle:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    toggleText:SetPoint("CENTER", toggle, "CENTER", 0, 0)
    local function UpdateToggle()
        if customEnabled then
            toggleBg:SetColorTexture(PaletteRGBA("accentSoft", 0.95))
            toggleText:SetText("Custom")
            toggleText:SetTextColor(PaletteRGBA("header"))
        else
            toggleBg:SetColorTexture(PaletteRGBA("surface", 0.85))
            toggleText:SetText("Default")
            local p = GetAccentPalette()
            toggleText:SetTextColor(p.header[1] * 0.7, p.header[2] * 0.7, p.header[3] * 0.7, 1)
        end
    end

    local function MakeSwatch(key, tooltip, anchor, xOffset)
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(30, 24)
        btn:SetPoint("RIGHT", anchor, "LEFT", xOffset, 0)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.07, 0.06, 0.04, 0.95)
        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
        swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
        swatch:SetTexture(WHITE_TEXTURE)
        btn._swatch = swatch
        btn:SetScript("OnClick", function()
            local seed = key == "accentColor" and currentAccent or currentSurface
            OpenColorPicker(seed, function(color)
                local fallback = key == "accentColor" and accentFallback or surfaceFallback
                local normalized = NormalizeColor(color, fallback)
                customEnabled = true
                ns.Settings:SetModuleValue(moduleID, "customTheme", true)
                ns.Settings:SetModuleValue(moduleID, key, normalized)
                if key == "accentColor" then currentAccent = normalized else currentSurface = normalized end
                swatch:SetVertexColor(normalized[1], normalized[2], normalized[3], normalized[4] or 1)
                UpdateToggle()
                Apply()
            end)
        end)
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return btn
    end

    local surfaceBtn = MakeSwatch("surfaceColor", "Panel color", toggle, -8)
    local accentBtn = MakeSwatch("accentColor", "Accent color", surfaceBtn, -6)

    toggle:SetScript("OnClick", function()
        if ns.OptionsPanel.refreshing then return end
        customEnabled = not customEnabled
        ns.Settings:SetModuleValue(moduleID, "customTheme", customEnabled)
        UpdateToggle()
        Apply()
    end)

    return {
        row = row,
        SetValues = function(self, accent, surface, custom)
            currentAccent = NormalizeColor(accent, accentFallback)
            currentSurface = NormalizeColor(surface, surfaceFallback)
            customEnabled = custom == true
            accentBtn._swatch:SetVertexColor(currentAccent[1], currentAccent[2], currentAccent[3], currentAccent[4] or 1)
            surfaceBtn._swatch:SetVertexColor(currentSurface[1], currentSurface[2], currentSurface[3], currentSurface[4] or 1)
            UpdateToggle()
        end,
        SetEnabled = function(self, enabled)
            toggle:SetEnabled(enabled)
            accentBtn:SetEnabled(enabled)
            surfaceBtn:SetEnabled(enabled)
            row:SetAlpha(enabled and 1 or 0.5)
            label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
        end,
    }
end

local function CreateColorGroupRow(parent, labelText, specs)
    -- Each color spec is its own half-width row so multi-color groups join
    -- the same 2-column grid as toggles / sliders. The optional labelText
    -- (e.g. "Crosshair colors") is ignored visually -- callers already place
    -- a CreateHeader above the group, and per-row labels carry the names.
    local controls = {}

    for _, spec in ipairs(specs) do
        local rowLabelText = spec.label or spec.key or "Color"
        local row, label = CreateRow(parent, rowLabelText, spec.tooltip, true)
        label:SetWordWrap(false)

        local btn
        if IsClassicTheme() then
            btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        else
            btn = CreateFrame("Button", nil, row)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.07, 0.06, 0.04, 0.95)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(PaletteRGBA("accentSoft", 0.20))
        end
        btn:SetSize(40, 22)
        btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        label:SetPoint("RIGHT", btn, "LEFT", -6, 0)

        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
        swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
        swatch:SetTexture(WHITE_TEXTURE)

        local currentColor = { 1, 1, 1, 1 }
        local function UpdateSwatch()
            swatch:SetVertexColor(currentColor[1], currentColor[2], currentColor[3], currentColor[4] or 1)
        end

        btn:SetScript("OnClick", function()
            OpenColorPicker(currentColor, function(color)
                currentColor = NormalizeColor(color, currentColor)
                UpdateSwatch()
                if not ns.OptionsPanel.refreshing and type(spec.onChange) == "function" then
                    spec.onChange(currentColor)
                end
            end)
        end)
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spec.tooltip or spec.label or "Color", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        controls[spec.key] = {
            row = row,
            SetValue = function(self, color)
                currentColor = NormalizeColor(color, { 1, 1, 1, 1 })
                UpdateSwatch()
            end,
            SetEnabled = function(self, enabled)
                btn:SetEnabled(enabled)
                row:SetAlpha(enabled and 1 or 0.5)
                label:SetTextColor(enabled and 1 or 0.55, enabled and 1 or 0.55, enabled and 1 or 0.55, 1)
            end,
        }
        UpdateSwatch()
    end

    controls.SetEnabled = function(self, enabled)
        for _, spec in ipairs(specs) do
            local control = controls[spec.key]
            if control and control.SetEnabled then control:SetEnabled(enabled) end
        end
    end

    return controls
end

local function MakeHelpers(moduleID)
    local classic = IsClassicTheme()
    return {
        Toggle       = classic and CreateToggleClassic or CreateToggleSwitch,
        Slider       = classic and CreateSliderClassic or CreateSliderM,
        EditBox      = classic and CreateEditBoxClassic or CreateEditBoxM,
        Dropdown     = classic and CreateDropdownClassic or CreateDropdownM,
        ColorPicker  = classic and CreateColorPickerClassic or CreateColorPickerM,
        Keybind      = classic and CreateKeybindClassic or CreateKeybindButton,
        Header       = CreateHeader,
        Button       = CreateActionBtn,
        Reset        = ResetLayout,
        ApplySetting = function(_, key, value)
            ns.Settings:SetModuleValue(moduleID, key, value)
            ns.ModuleRegistry:ApplyModuleSettings(moduleID)
            ns.OptionsPanel:Refresh()
        end,
    }
end

-- Single StaticPopup definition shared across every "Restore Defaults" button.
-- The actual reset callback is passed in via the StaticPopup_Show data arg so
-- we don't have to maintain a unique popup key per module.
local RESTORE_DEFAULTS_POPUP_KEY = "THYRAXUTIL_RESTORE_DEFAULTS"
local restoreDefaultsPopupRegistered = false

local function EnsureRestoreDefaultsPopup()
    if restoreDefaultsPopupRegistered then return end
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs[RESTORE_DEFAULTS_POPUP_KEY] = {
        text = "Restore this module's settings to defaults?\n\nThis cannot be undone.",
        button1 = "Yes",
        button2 = "Cancel",
        OnAccept = function(self, data)
            if type(data) == "function" then
                data()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    restoreDefaultsPopupRegistered = true
end

local function CreateRestoreDefaultsBtn(parent, callback)
    -- Wrap the reset in a confirm dialog so an accidental click can't wipe
    -- the user's customisation (colors, positions, sizes). Matches the
    -- existing pattern used by Accounting's "Clear Character / Account"
    -- buttons. Falls back to direct execution only if StaticPopup is
    -- somehow unavailable (e.g. very stripped-down test environments).
    return CreateActionBtn(parent, "Restore Defaults", function()
        EnsureRestoreDefaultsPopup()
        if restoreDefaultsPopupRegistered then
            StaticPopup_Show(RESTORE_DEFAULTS_POPUP_KEY, nil, nil, callback)
        else
            callback()
        end
    end)
end

-- [[ END_WIDGETS ]]

-- [[ START_TAB_SYSTEM ]]
local TAB_HEIGHT    = 28
local TAB_MIN_WIDTH = 90

local function GetTabPalette()
    local accent = GetAccentPalette()
    if IsModernTheme() then
        local s = accent.surface
        local sd = accent.surfaceDark
        local h = accent.header
        local a = accent.accent
        return {
            active        = { s[1], s[2], s[3], 0.95 },
            inactive      = { sd[1], sd[2], sd[3], 0.85 },
            underline     = { h[1], h[2], h[3], 1 },
            labelActive   = { h[1], h[2], h[3], 1 },
            labelInactive = { h[1] * 0.78, h[2] * 0.78, h[3] * 0.78, 1 },
            divider       = { a[1] * 0.65, a[2] * 0.65, a[3] * 0.65, 0.95 },
        }
    end
    -- Classic: neutral grey base, accent for the active-tab underline only.
    local h = accent.header
    return {
        active        = { 0.08, 0.08, 0.10, 0.95 },
        inactive      = { 0.02, 0.02, 0.03, 0.80 },
        underline     = { h[1], h[2], h[3], 1 },
        labelActive   = { 1, 1, 1, 1 },
        labelInactive = { 0.75, 0.75, 0.75, 1 },
        divider       = { 0.28, 0.28, 0.28, 0.9 },
    }
end

local function CreateTabButton(parent, label, index, totalTabs, onSelect)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(TAB_HEIGHT)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    local p = GetTabPalette()
    bg:SetColorTexture(p.inactive[1], p.inactive[2], p.inactive[3], p.inactive[4])
    btn.bg = bg
    local underline = btn:CreateTexture(nil, "BORDER")
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    underline:SetHeight(2)
    underline:SetColorTexture(p.underline[1], p.underline[2], p.underline[3], 0)
    btn.underline = underline
    local text = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText(label)
    btn.label = text
    btn:SetScript("OnClick", function() onSelect(index) end)
    function btn:SetActive(active)
        local cp = GetTabPalette()
        if active then
            self.bg:SetColorTexture(unpack(cp.active))
            self.underline:SetColorTexture(cp.underline[1], cp.underline[2], cp.underline[3], 1)
            self.label:SetTextColor(unpack(cp.labelActive))
        else
            self.bg:SetColorTexture(unpack(cp.inactive))
            self.underline:SetColorTexture(cp.underline[1], cp.underline[2], cp.underline[3], 0)
            self.label:SetTextColor(unpack(cp.labelInactive))
        end
    end

    return btn
end

local function LayoutTabs(tabs, containerWidth)
    local visible = {}
    for _, t in ipairs(tabs) do if t:IsShown() then table.insert(visible, t) end end
    if #visible == 0 then return end
    containerWidth = math.max(1, tonumber(containerWidth) or 1)
    local perRow = math.max(1, math.floor(containerWidth / TAB_MIN_WIDTH))
    local rowCount = math.ceil(#visible / perRow)
    local parent = visible[1]:GetParent()
    if parent then parent:SetHeight(rowCount * TAB_HEIGHT) end

    for rowIndex = 0, rowCount - 1 do
        local startIndex = rowIndex * perRow + 1
        local endIndex = math.min(#visible, startIndex + perRow - 1)
        local count = endIndex - startIndex + 1
        local tabW = math.max(math.floor(containerWidth / count), TAB_MIN_WIDTH)
        local previous
        for i = startIndex, endIndex do
            local t = visible[i]
            t:ClearAllPoints()
            t:SetWidth(tabW)
            if previous then
                t:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            else
                t:SetPoint("TOPLEFT", t:GetParent(), "TOPLEFT", 0, -rowIndex * TAB_HEIGHT)
            end
            previous = t
        end
    end
end

-- [[ END_TAB_SYSTEM ]]

-- [[ START_PAGE_BUILDERS ]]
-- Themes a UIPanelScrollFrameTemplate scrollbar to match the Accounting window:
-- dark track, gold thumb, dimmed arrow buttons.
local function StyleScrollBar(bar)
    if not bar then return end
    if not bar._thyraxBg and bar.CreateTexture then
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -16)
        barBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 16)
        bar._thyraxBg = barBg
    end
    local palette = GetAccentPalette()
    if bar._thyraxBg then
        bar._thyraxBg:SetTexture(WHITE_TEXTURE)
        bar._thyraxBg:SetVertexColor(palette.surface[1] * 1.1, palette.surface[2] * 1.1, palette.surface[3] * 1.1, 0.55)
    end
    if bar.GetThumbTexture then
        local thumb = bar:GetThumbTexture()
        if thumb then
            thumb:SetTexture(WHITE_TEXTURE)
            thumb:SetVertexColor(palette.accentSoft[1], palette.accentSoft[2], palette.accentSoft[3], 0.85)
        end
    end
    for _, button in ipairs({ bar.ScrollUpButton, bar.ScrollDownButton, bar.Back, bar.Forward }) do
        if button and button.SetAlpha then
            button:SetAlpha(0.45)
        end
    end
end

local function CreateScrollPage(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 2)
    scroll:Hide()
    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetSize(400, 100)
    scroll:SetScrollChild(content)

    -- Anchor the scrollbar cleanly at the page's right edge and theme it.
    local bar = scroll.ScrollBar or scroll.scrollBar or scroll.Scrollbar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -18)
        bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 18)
        StyleScrollBar(bar)
    end
    return scroll, content
end

local THEME_OPTIONS = { { value = "Modern", display = "Modern" }, { value = "Classic", display = "Classic" } }
local THEME_ACCENT_OPTIONS = {
    { value = "Gold",   display = "Gold" },
    { value = "Silver", display = "Silver" },
    { value = "Blue",   display = "Blue" },
    { value = "Green",  display = "Green" },
    { value = "Red",    display = "Red" },
    { value = "Purple", display = "Purple" },
    { value = "Teal",   display = "Teal" },
    { value = "Custom", display = "Custom" },
}

local function CreateInlineCustomAccentToggle(row, dropdownControl, onChange)
    if not row or not dropdownControl or not dropdownControl.btn then
        return nil
    end
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(70, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -10, 0)

    dropdownControl.btn:ClearAllPoints()
    dropdownControl.btn:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    if dropdownControl.SetWidth then
        dropdownControl:SetWidth(96)
    else
        dropdownControl.btn:SetWidth(96)
    end

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local checked = false

    local function Update()
        if checked then
            bg:SetColorTexture(PaletteRGBA("accentSoft", 0.95))
            text:SetTextColor(PaletteRGBA("header"))
        else
            bg:SetColorTexture(PaletteRGBA("surface", 0.85))
            local p = GetAccentPalette()
            text:SetTextColor(p.header[1] * 0.7, p.header[2] * 0.7, p.header[3] * 0.7, 1)
        end
        text:SetText("Custom")
    end

    btn:SetScript("OnClick", function()
        if ns.OptionsPanel.refreshing then return end
        checked = not checked
        Update()
        onChange(checked)
    end)
    Update()

    return {
        btn = btn,
        SetChecked = function(self, value)
            checked = value and true or false
            Update()
        end,
        SetEnabled = function(self, enabled)
            btn:SetEnabled(enabled)
            btn:SetAlpha(enabled and 1 or 0.5)
        end,
    }
end

local function BuildGeneralPage(content)
    local c = {}
    local h = MakeHelpers(nil)
    local function ApplyGlobalAccentPreset(value)
        if ns.UI and ns.UI.SetAccentPreset then
            ns.UI:SetAccentPreset(value)
        end
        -- Accent change only re-tints existing widgets; no need to recreate
        -- pages. RepaintThemedWidgets walks the per-Create registry and
        -- ApplyWindowTheme handles the panel chrome / tabs / scrollbars.
        OptionsPanel:RepaintThemedWidgets()
    end
    h.Reset()
    h.Header(content, "Global Settings")
    c.globalEnabled = h.Toggle(content, "Enable ThyraxUtil",
        function(v) ns.ModuleRegistry:SetGlobalEnabled(v); OptionsPanel:Refresh() end,
        "Master switch. When off, every module is suspended regardless of its individual toggle.")
    c.theme = h.Dropdown(content, "UI Design Theme", 160, THEME_OPTIONS,
        function(v)
            ns.UI:SetTheme(v)
            OptionsPanel:RequestRebuild()
        end,
        "Visual style of the options widgets and module overlays. Modern uses custom styling, Classic mirrors Blizzard's native look.")
    c.accentPreset = h.Dropdown(content, "Accent Color", 160, THEME_ACCENT_OPTIONS,
        function(v)
            ApplyGlobalAccentPreset(v)
        end,
        "Highlight color applied across toggles, sliders, borders and header buttons. Independent of the theme style above. Choose 'Custom' to pick your own accent + surface colors below.")
    c.customAccentToggle = CreateInlineCustomAccentToggle(c.accentPreset.row, c.accentPreset, function(customEnabled)
        ApplyGlobalAccentPreset(customEnabled and "Custom" or "Gold")
    end)
    -- Custom accent / surface pickers. Enabled only when the dropdown above
    -- is set to "Custom"; otherwise greyed-out so the user knows the presets
    -- override these values.
    c.customAccentColor = CreateColorPickerM and h.ColorPicker(content, "Custom Accent",
        function(color)
            if ns.Settings and ns.Settings.SetCustomAccentColor then
                ns.Settings:SetCustomAccentColor(color)
            end
            if ns.UI and ns.UI.ReapplyAll then ns.UI:ReapplyAll() end
            -- Trigger module repaints same as SetAccentPreset does.
            if ns.ModuleRegistry and ns.ModuleRegistry.GetModuleIDs and ns.ModuleRegistry.ApplyModuleSettings then
                for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
                    ns.ModuleRegistry:ApplyModuleSettings(moduleID)
                end
            end
            OptionsPanel:RepaintThemedWidgets()
        end) or nil
    c.customSurfaceColor = CreateColorPickerM and h.ColorPicker(content, "Custom Surface",
        function(color)
            if ns.Settings and ns.Settings.SetCustomSurfaceColor then
                ns.Settings:SetCustomSurfaceColor(color)
            end
            if ns.UI and ns.UI.ReapplyAll then ns.UI:ReapplyAll() end
            if ns.ModuleRegistry and ns.ModuleRegistry.GetModuleIDs and ns.ModuleRegistry.ApplyModuleSettings then
                for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
                    ns.ModuleRegistry:ApplyModuleSettings(moduleID)
                end
            end
            OptionsPanel:RepaintThemedWidgets()
        end) or nil

    -- Custom font colors: optional override that recolors heading + dim text
    -- everywhere (Options labels, Accounting column headers, axis ticks). Use
    -- when the accent preset's gold-derived text tones do not read well on a
    -- non-gold accent (e.g. green accent with white-tinted body text).
    local function RefreshAllPaletteConsumers()
        if ns.UI and ns.UI.ReapplyAll then ns.UI:ReapplyAll() end
        if ns.ModuleRegistry and ns.ModuleRegistry.GetModuleIDs and ns.ModuleRegistry.ApplyModuleSettings then
            for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
                ns.ModuleRegistry:ApplyModuleSettings(moduleID)
            end
        end
        -- Re-tint without rebuild: ColorPicker fires this on every drag tick
        -- but RepaintThemedWidgets allocates ZERO new frames, so the memory
        -- floor stops climbing per colour session.
        OptionsPanel:RepaintThemedWidgets()
    end
    c.customFontEnabled = h.Toggle(content, "Custom Font Colors",
        function(v)
            if ns.Settings and ns.Settings.SetCustomFontEnabled then
                ns.Settings:SetCustomFontEnabled(v)
            end
            RefreshAllPaletteConsumers()
        end,
        "Override the addon-wide font color. When on, headings and dim text follow the two color pickers below instead of the accent-derived gold tones.")
    c.customFontPrimary = CreateColorPickerM and h.ColorPicker(content, "Font Primary",
        function(color)
            if ns.Settings and ns.Settings.SetCustomFontPrimary then
                ns.Settings:SetCustomFontPrimary(color)
            end
            RefreshAllPaletteConsumers()
        end) or nil
    c.customFontSecondary = CreateColorPickerM and h.ColorPicker(content, "Font Secondary",
        function(color)
            if ns.Settings and ns.Settings.SetCustomFontSecondary then
                ns.Settings:SetCustomFontSecondary(color)
            end
            RefreshAllPaletteConsumers()
        end) or nil

    h.Header(content, "Modules")
    local moduleTooltip = "Enable or disable this module. The master switch above must also be on."
    c.crosshairEnabled = h.Toggle(content, "Crosshair",
        function(v) ns.ModuleRegistry:SetModuleEnabled("crosshair", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.mouseTrackerEnabled = h.Toggle(content, "Mouse Tracker",
        function(v) ns.ModuleRegistry:SetModuleEnabled("mouse_tracker", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.darknessEnabled = h.Toggle(content, "Darkness",
        function(v) ns.ModuleRegistry:SetModuleEnabled("darkness_announcer", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.questAcceptHotkeyEnabled = h.Toggle(content, "Quest Accept",
        function(v) ns.ModuleRegistry:SetModuleEnabled("quest_accept_hotkey", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.flightTrackerEnabled = h.Toggle(content, "Dynamic Flight",
        function(v) ns.ModuleRegistry:SetModuleEnabled("dynamic_flight_tracker", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.auctionFilterPersistEnabled = h.Toggle(content, "AH Filter Persist",
        function(v) ns.ModuleRegistry:SetModuleEnabled("auction_filter_persist", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.accountingTrackerEnabled = h.Toggle(content, "Accounting Tracker",
        function(v) ns.ModuleRegistry:SetModuleEnabled("accounting_tracker", v); OptionsPanel:Refresh() end,
        moduleTooltip)
    c.characterPanelEnabled = h.Toggle(content, "Character Panel",
        function(v) ns.ModuleRegistry:SetModuleEnabled("character_panel_enhancer", v); OptionsPanel:Refresh() end,
        moduleTooltip)

    h.Header(content, "Debug")
    c.developerMode = h.Toggle(content, "Developer Mode",
        function(v)
            ns.Settings:SetDeveloperModeEnabled(v)
            if ns.DeveloperMode and ns.DeveloperMode.SetEnabled then
                ns.DeveloperMode:SetEnabled(v)
            end
        end,
        "Enable the in-game debug overlay and verbose diagnostic logging. Off in normal use.")

    CreateRestoreDefaultsBtn(content, function()
        ns.Settings:SetGlobalEnabled(true)
        for _, modID in ipairs({ "crosshair", "mouse_tracker", "darkness_announcer", "quest_accept_hotkey", "dynamic_flight_tracker", "auction_filter_persist", "accounting_tracker", "character_panel_enhancer" }) do
            local mod = ns.ModuleRegistry:GetModule(modID)
            if mod and mod.defaults then
                ns.Settings:SetModuleEnabled(modID, mod.defaults.enabled ~= false)
            end
        end
        OptionsPanel:Refresh()
    end)

    local function Refresh()
        local g = ns.Settings:IsGlobalEnabled()
        c.globalEnabled:SetChecked(g)
        c.theme:SetValue(ns.Settings:GetTheme())
        local accentPresetName = "Gold"
        if c.accentPreset and ns.Settings.GetAccentPreset then
            accentPresetName = ns.Settings:GetAccentPreset()
            c.accentPreset:SetValue(accentPresetName)
        end
        -- Custom pickers: load current saved values and grey-out / enable
        -- based on whether the Custom preset is active.
        local customActive = accentPresetName == "Custom"
        if c.customAccentToggle then
            c.customAccentToggle:SetChecked(customActive)
            c.customAccentToggle:SetEnabled(g)
        end
        if c.customAccentColor then
            if ns.Settings.GetCustomAccentColor then
                c.customAccentColor:SetValue(ns.Settings:GetCustomAccentColor())
            end
            if c.customAccentColor.SetEnabled then
                c.customAccentColor:SetEnabled(customActive)
            end
        end
        if c.customSurfaceColor then
            if ns.Settings.GetCustomSurfaceColor then
                c.customSurfaceColor:SetValue(ns.Settings:GetCustomSurfaceColor())
            end
            if c.customSurfaceColor.SetEnabled then
                c.customSurfaceColor:SetEnabled(customActive)
            end
        end
        local fontEnabled = ns.Settings.IsCustomFontEnabled and ns.Settings:IsCustomFontEnabled() or false
        if c.customFontEnabled then
            c.customFontEnabled:SetChecked(fontEnabled)
            c.customFontEnabled:SetEnabled(g)
        end
        if c.customFontPrimary then
            if ns.Settings.GetCustomFontPrimary then
                c.customFontPrimary:SetValue(ns.Settings:GetCustomFontPrimary())
            end
            if c.customFontPrimary.SetEnabled then
                c.customFontPrimary:SetEnabled(g and fontEnabled)
            end
        end
        if c.customFontSecondary then
            if ns.Settings.GetCustomFontSecondary then
                c.customFontSecondary:SetValue(ns.Settings:GetCustomFontSecondary())
            end
            if c.customFontSecondary.SetEnabled then
                c.customFontSecondary:SetEnabled(g and fontEnabled)
            end
        end
        c.crosshairEnabled:SetChecked(ns.Settings:IsModuleEnabled("crosshair"))
        c.crosshairEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("crosshair"))
        c.mouseTrackerEnabled:SetChecked(ns.Settings:IsModuleEnabled("mouse_tracker"))
        c.mouseTrackerEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("mouse_tracker"))

        local darkStatus = ns.ModuleRegistry.GetModuleStatus and ns.ModuleRegistry:GetModuleStatus("darkness_announcer")
        if darkStatus and darkStatus.available == false then
            c.darknessEnabled:SetChecked(false)
            c.darknessEnabled:SetEnabled(false)
            c.darknessEnabled.label:SetText("Darkness (Disabled: Demon Hunter Only)")
        else
            c.darknessEnabled:SetChecked(ns.Settings:IsModuleEnabled("darkness_announcer"))
            c.darknessEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("darkness_announcer"))
            c.darknessEnabled.label:SetText("Darkness")
        end

        c.questAcceptHotkeyEnabled:SetChecked(ns.Settings:IsModuleEnabled("quest_accept_hotkey"))
        c.questAcceptHotkeyEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("quest_accept_hotkey"))
        
        c.flightTrackerEnabled:SetChecked(ns.Settings:IsModuleEnabled("dynamic_flight_tracker"))
        c.flightTrackerEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("dynamic_flight_tracker"))

        c.auctionFilterPersistEnabled:SetChecked(ns.Settings:IsModuleEnabled("auction_filter_persist"))
        c.auctionFilterPersistEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("auction_filter_persist"))

        c.accountingTrackerEnabled:SetChecked(ns.Settings:IsModuleEnabled("accounting_tracker"))
        c.accountingTrackerEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("accounting_tracker"))

        c.characterPanelEnabled:SetChecked(ns.Settings:IsModuleEnabled("character_panel_enhancer"))
        c.characterPanelEnabled:SetEnabled(g and ns.ModuleRegistry:GetModule("character_panel_enhancer"))

        c.developerMode:SetChecked(ns.Settings:IsDeveloperModeEnabled())
        c.developerMode:SetEnabled(g)
    end

    return c, Refresh
end

local LAYER_OPTIONS = {
    { value = "BACKGROUND", display = "Background" }, { value = "LOW", display = "Low" },
    { value = "MEDIUM", display = "Medium" }, { value = "HIGH", display = "High" },
    { value = "DIALOG", display = "Dialog" },
    { value = "FULLSCREEN", display = "Fullscreen" }, { value = "TOOLTIP", display = "Tooltip" },
}

local MOUSE_SHAPE_OPTIONS = {
    { value = "ring", display = "Ring" },
    { value = "star", display = "Star" },
}

local CHANNEL_OPTIONS = {
    { value = "AUTO", display = "Auto" },
    { value = "PARTY", display = "Party" },
    { value = "INSTANCE_CHAT", display = "Instance Chat" },
}

local TEXT_POSITION_OPTIONS = {
    { value = "above", display = "Above" },
    { value = "on", display = "On Bar" },
    { value = "below", display = "Below" },
}

local FILL_TEXTURE_OPTIONS = {
    { value = "solid",       display = "Solid (flat)" },
    { value = "uistatusbar", display = "Blizzard UI StatusBar" },
    { value = "raidhp",      display = "Raid HP" },
}

local FONT_OUTLINE_OPTIONS = {
    { value = "NONE",         display = "None" },
    { value = "OUTLINE",      display = "Outline" },
    { value = "THICKOUTLINE", display = "Thick Outline" },
}

local function BuildCrosshairPage(content)
    local c = {}
    local h = MakeHelpers("crosshair")
    h.Reset()
    h.Header(content, "Crosshair Options")

    c.editModeBtn = h.Button(content, "Enter Edit Mode", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            SettingsPanel:Hide()
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            InterfaceOptionsFrame:Hide()
        end
        if EditModeManagerFrame then
            ShowUIPanel(EditModeManagerFrame)
        end
    end)

    -- Ordering pairs Combat Only with Alpha (Out of Combat) on the last row
    -- since one gates the other.
    c.xOffset        = h.Slider(content, "X Offset", -300, 300, 1, 0,
        function(v) h:ApplySetting("xOffset", v) end,
        "Horizontal offset from screen center, in pixels. Negative shifts left.")
    c.yOffset        = h.Slider(content, "Y Offset", -300, 300, 1, 0,
        function(v) h:ApplySetting("yOffset", v) end,
        "Vertical offset from screen center, in pixels. Negative shifts down.")
    c.scale          = h.Slider(content, "Scale", 0.25, 4, 0.01, 2,
        function(v) h:ApplySetting("scale", v) end,
        "Size multiplier for the entire crosshair.")
    c.alphaInCombat  = h.Slider(content, "Alpha (In Combat)", 0, 1, 0.01, 2,
        function(v) h:ApplySetting("alphaInCombat", v) end,
        "Opacity while in combat. 1 = fully visible, 0 = invisible.")
    c.combatOnly     = h.Toggle(content, "Combat Only",
        function(v) h:ApplySetting("combatOnly", v) end,
        "Show the crosshair only while in combat. Disables the out-of-combat alpha slider.")
    c.alphaOutCombat = h.Slider(content, "Alpha (Out of Combat)", 0, 1, 0.01, 2,
        function(v) h:ApplySetting("alphaOutCombat", v) end,
        "Opacity while out of combat. Ignored when Combat Only is on.")
    h.Header(content, "Colors")
    local crosshairColors = CreateColorGroupRow(content, "Crosshair colors", {
        { key = "accentColor", label = "Accent",
            tooltip = "Color of the outer accent lines.",
            onChange = function(color) h:ApplySetting("accentColor", color) end },
        { key = "combatColor", label = "Combat",
            tooltip = "Main color of the inner combat crosshair.",
            onChange = function(color) h:ApplySetting("combatColor", color) end },
        { key = "combatSoftColor", label = "Soft",
            tooltip = "Color of the softer secondary crosshair line.",
            onChange = function(color) h:ApplySetting("combatSoftColor", color) end },
    })
    c.accentColor = crosshairColors.accentColor
    c.combatColor = crosshairColors.combatColor
    c.combatSoftColor = crosshairColors.combatSoftColor
    h.Header(content, "Display")
    c.frameStrata = h.Dropdown(content, "Layer", 160, LAYER_OPTIONS,
        function(v) h:ApplySetting("frameStrata", v) end,
        "Frame strata the crosshair draws on. HIGH keeps it above most UI elements.")

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("crosshair")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("crosshair", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("crosshair")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("crosshair")
        for _, widget in pairs(c) do if widget.SetEnabled then widget:SetEnabled(a) end end
        c.combatOnly:SetChecked(ns.Settings:GetModuleValue("crosshair", "combatOnly") and true or false)
        c.xOffset:SetValue(ns.Settings:GetModuleValue("crosshair", "xOffset") or 0)
        c.yOffset:SetValue(ns.Settings:GetModuleValue("crosshair", "yOffset") or -26)
        c.scale:SetValue(ns.Settings:GetModuleValue("crosshair", "scale") or 0.8)
        c.alphaInCombat:SetValue(ns.Settings:GetModuleValue("crosshair", "alphaInCombat") or 0.4)
        c.alphaOutCombat:SetValue(ns.Settings:GetModuleValue("crosshair", "alphaOutCombat") or 0.2)
        c.accentColor:SetValue(ns.Settings:GetModuleValue("crosshair", "accentColor"))
        c.combatColor:SetValue(ns.Settings:GetModuleValue("crosshair", "combatColor"))
        c.combatSoftColor:SetValue(ns.Settings:GetModuleValue("crosshair", "combatSoftColor"))
        c.frameStrata:SetValue(ns.Settings:GetModuleValue("crosshair", "frameStrata") or "HIGH")

        -- Sub-control gating: "Alpha (Out of Combat)" is never used when the
        -- crosshair is set to only render in combat.
        if a then
            local combatOnly = ns.Settings:GetModuleValue("crosshair", "combatOnly") == true
            c.alphaOutCombat:SetEnabled(not combatOnly)
        end
    end

    return c, Refresh
end

local function BuildMousePage(content)
    local c = {}
    local h = MakeHelpers("mouse_tracker")
    h.Reset()
    h.Header(content, "Shape")
    c.shape       = h.Dropdown(content, "Shape", 160, MOUSE_SHAPE_OPTIONS,
        function(v) h:ApplySetting("shape", v) end,
        "Visual shape of the cursor tracker: Ring (circle) or Star.")
    c.texturePath = h.EditBox(content, "Custom Texture", 200,
        function(v) h:ApplySetting("texturePath", v) end,
        "Optional WoW asset path overriding the built-in shape texture. Leave empty for default.")
    h.Header(content, "Size")
    c.combatOnly    = h.Toggle(content, "Combat Only",
        function(v) h:ApplySetting("combatOnly", v) end,
        "Show the tracker only while in combat. Disables the out-of-combat size and thickness sliders.")
    c.sizeCombat    = h.Slider(content, "Size (In Combat)", 16, 180, 1, 0,
        function(v) h:ApplySetting("sizeCombat", v) end,
        "Diameter of the tracker while in combat, in pixels.")
    c.sizeOutCombat = h.Slider(content, "Size (Out of Combat)", 16, 180, 1, 0,
        function(v) h:ApplySetting("sizeOutCombat", v) end,
        "Diameter of the tracker while out of combat, in pixels.")
    h.Header(content, "Thickness")
    c.thickness         = h.Slider(content, "Thickness (Out of Combat)", 1, 12, 1, 0,
        function(v) h:ApplySetting("thickness", v) end,
        "Line thickness of the tracker outline while out of combat.")
    c.thicknessInCombat = h.Slider(content, "Thickness (In Combat)", 1, 12, 1, 0,
        function(v) h:ApplySetting("thicknessInCombat", v) end,
        "Line thickness of the tracker outline while in combat.")
    h.Header(content, "Movement")
    c.updateRate = h.Slider(content, "Update Rate", 0.002, 0.02, 0.001, 3,
        function(v) h:ApplySetting("updateRate", v) end,
        "How often the tracker re-positions to the cursor, in seconds. Smaller = smoother, slightly more CPU.")
    c.smoothFollow = h.Toggle(content, "Smooth Follow",
        function(v) h:ApplySetting("smoothFollow", v) end,
        "Interpolate cursor movement instead of snapping to the cursor each frame.")
    h.Header(content, "Colors")
    c.opacity            = h.Slider(content, "Opacity", 0, 1, 0.05, 2,
        function(v) h:ApplySetting("opacity", v) end,
        "Overall transparency of the tracker. 1 = fully visible.")
    c.useCombatColor     = h.Toggle(content, "Use Combat Colors",
        function(v) h:ApplySetting("useCombatColor", v) end,
        "Switch to the combat fill / outline colors when entering combat for higher visibility.")
    local mouseColors = CreateColorGroupRow(content, "Mouse colors", {
        { key = "combatFillColor", label = "Fill",
            tooltip = "Fill color used in combat.",
            onChange = function(color) h:ApplySetting("combatFillColor", color) end },
        { key = "combatOutlineColor", label = "Outline",
            tooltip = "Outline color used in combat.",
            onChange = function(color) h:ApplySetting("combatOutlineColor", color) end },
        { key = "outOfCombatColor", label = "Out",
            tooltip = "Color used while out of combat.",
            onChange = function(color) h:ApplySetting("outOfCombatColor", color) end },
    })
    c.combatFillColor = mouseColors.combatFillColor
    c.combatOutlineColor = mouseColors.combatOutlineColor
    c.outOfCombatColor = mouseColors.outOfCombatColor
    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("mouse_tracker")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("mouse_tracker", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("mouse_tracker")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("mouse_tracker")
        for _, w in pairs(c) do if w.SetEnabled then w:SetEnabled(a) end end
        c.shape:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "shape") or "ring")
        c.texturePath:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "texturePath") or "")
        c.combatOnly:SetChecked(ns.Settings:GetModuleValue("mouse_tracker", "combatOnly") and true or false)
        c.sizeCombat:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "sizeCombat") or 50)
        c.sizeOutCombat:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "sizeOutCombat") or 45)
        c.thickness:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "thickness") or 1)
        c.thicknessInCombat:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "thicknessInCombat") or 1)
        c.updateRate:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "updateRate") or 0.004)
        c.smoothFollow:SetChecked(ns.Settings:GetModuleValue("mouse_tracker", "smoothFollow") and true or false)
        c.useCombatColor:SetChecked(ns.Settings:GetModuleValue("mouse_tracker", "useCombatColor") ~= false)
        c.combatFillColor:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "combatFillColor"))
        c.combatOutlineColor:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "combatOutlineColor"))
        c.outOfCombatColor:SetValue(ns.Settings:GetModuleValue("mouse_tracker", "outOfCombatColor"))
        local opacityVal = ns.Settings:GetModuleValue("mouse_tracker", "opacity")
        if opacityVal == nil then opacityVal = 1 end
        c.opacity:SetValue(opacityVal)

        -- Sub-control gating: reflect which settings actually paint anything
        -- given the current toggle states. The underlying value is preserved.
        if a then
            local useCombat = ns.Settings:GetModuleValue("mouse_tracker", "useCombatColor") ~= false
            local combatOnly = ns.Settings:GetModuleValue("mouse_tracker", "combatOnly") == true

            -- Combat fill/outline only apply while useCombatColor is on; when
            -- off the ring uses outOfCombatColor for both states.
            c.combatFillColor:SetEnabled(useCombat)
            c.combatOutlineColor:SetEnabled(useCombat)

            -- Out-of-combat SIZE and THICKNESS only paint when the ring is
            -- allowed to show out of combat (i.e. combatOnly is off).
            c.sizeOutCombat:SetEnabled(not combatOnly)
            c.thickness:SetEnabled(not combatOnly)

            -- outOfCombatColor is used either when the ring is visible OOC
            -- OR when useCombatColor is off (then it's the single ring colour).
            c.outOfCombatColor:SetEnabled((not combatOnly) or (not useCombat))
        end
    end

    return c, Refresh
end

local function BuildDarknessPage(content)
    local c = {}
    local h = MakeHelpers("darkness_announcer")
    h.Reset()
    h.Header(content, "Start Announcement")
    c.channelStart = h.Dropdown(content, "Channel", 160, CHANNEL_OPTIONS,
        function(v) h:ApplySetting("channelStart", v) end,
        "Chat channel for the Darkness start announcement. Auto picks Instance Chat in raids and Party otherwise.")
    c.startMessage = h.EditBox(content, "Message", 260,
        function(v) h:ApplySetting("startMessage", v) end,
        "Text broadcast when Darkness begins.")
    h.Header(content, "End Announcement")
    c.channelEnd = h.Dropdown(content, "Channel", 160, CHANNEL_OPTIONS,
        function(v) h:ApplySetting("channelEnd", v) end,
        "Chat channel for the Darkness end announcement.")
    c.endMessage = h.EditBox(content, "Message", 260,
        function(v) h:ApplySetting("endMessage", v) end,
        "Text broadcast when Darkness ends.")
    h.Header(content, "Timing & Conditions")
    c.durationSeconds = h.Slider(content, "Fallback Duration (s)", 1, 30, 1, 0,
        function(v) h:ApplySetting("durationSeconds", v) end,
        "Used to schedule the end announcement when the live aura duration is not reported by the game.")
    c.instancesOnly   = h.Toggle(content, "Instances Only",
        function(v) h:ApplySetting("instancesOnly", v) end,
        "Only announce while inside a dungeon, raid or scenario.")
    c.onlyInGroup     = h.Toggle(content, "Only In Group",
        function(v) h:ApplySetting("onlyInGroup", v) end,
        "Suppress announcements while solo so the chat stays quiet outside of groups.")
    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("darkness_announcer")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("darkness_announcer", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("darkness_announcer")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("darkness_announcer")
        for _, w in pairs(c) do if w.SetEnabled then w:SetEnabled(a) end end
        c.channelStart:SetValue(ns.Settings:GetModuleValue("darkness_announcer", "channelStart") or "AUTO")
        c.startMessage:SetValue(ns.Settings:GetModuleValue("darkness_announcer", "startMessage") or ">>> DARKNESS <<<")
        c.channelEnd:SetValue(ns.Settings:GetModuleValue("darkness_announcer", "channelEnd") or "AUTO")
        c.endMessage:SetValue(ns.Settings:GetModuleValue("darkness_announcer", "endMessage") or ">>> Darkness Over <<<")
        c.durationSeconds:SetValue(ns.Settings:GetModuleValue("darkness_announcer", "durationSeconds") or 8)
        c.instancesOnly:SetChecked(ns.Settings:GetModuleValue("darkness_announcer", "instancesOnly") ~= false)
        c.onlyInGroup:SetChecked(ns.Settings:GetModuleValue("darkness_announcer", "onlyInGroup") and true or false)
    end

    return c, Refresh
end

local function BuildQuestAcceptHotkeyPage(content)
    local c = {}
    local h = MakeHelpers("quest_accept_hotkey")
    h.Reset()
    h.Header(content, "Quest Accept Options")
    c.acceptKey = h.Keybind(content, "Accept Key",
        function(v) h:ApplySetting("acceptKey", v or "SPACE") end,
        "Key that auto-accepts gossip, quest start and quest turn-in dialogues.")
    c.disableInInstance = h.Toggle(content, "Disable in Instances",
        function(v) h:ApplySetting("disableInInstance", v) end,
        "Skip the hotkey inside dungeons and raids to avoid accidental accepts during pulls.")

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("quest_accept_hotkey")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("quest_accept_hotkey", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("quest_accept_hotkey")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("quest_accept_hotkey")
        c.acceptKey:SetEnabled(a)
        c.acceptKey:SetValue(tostring(ns.Settings:GetModuleValue("quest_accept_hotkey", "acceptKey") or "SPACE"))
        c.disableInInstance:SetEnabled(a)
        c.disableInInstance:SetChecked(ns.Settings:GetModuleValue("quest_accept_hotkey", "disableInInstance") ~= false)
    end

    return c, Refresh
end

local function BuildFlightTrackerPage(content)
    local c = {}
    local h = MakeHelpers("dynamic_flight_tracker")
    h.Reset()
    h.Header(content, "Dynamic Flight Options")

    c.editModeBtn = h.Button(content, "Enter Edit Mode", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            SettingsPanel:Hide()
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            InterfaceOptionsFrame:Hide()
        end
        if EditModeManagerFrame then
            ShowUIPanel(EditModeManagerFrame)
        end
    end)

    h.Header(content, "Display")
    c.barWidth = h.Slider(content, "Bar Width", 50, 600, 1, 0,
        function(v) h:ApplySetting("barWidth", v) end,
        "Width of the speed bar in pixels.")
    c.barHeight = h.Slider(content, "Bar Height", 2, 40, 1, 0,
        function(v) h:ApplySetting("barHeight", v) end,
        "Height of the speed bar in pixels.")
    c.scale = h.Slider(content, "Scale", 0.5, 3.0, 0.01, 2,
        function(v) h:ApplySetting("scale", v) end,
        "Overall size multiplier applied on top of width / height.")
    c.xOffset = h.Slider(content, "X Offset", -800, 800, 1, 0,
        function(v) h:ApplySetting("xOffset", v) end,
        "Horizontal offset from screen center in pixels.")
    c.yOffset = h.Slider(content, "Y Offset", -800, 800, 1, 0,
        function(v) h:ApplySetting("yOffset", v) end,
        "Vertical offset from screen center in pixels.")
    c.arrowScale = h.Slider(content, "Accel Icon Scale", 0.5, 5.0, 0.1, 1,
        function(v) h:ApplySetting("arrowScale", v) end,
        "Size multiplier for the acceleration / deceleration arrow.")

    h.Header(content, "Visibility")
    c.showSpeed = h.Toggle(content, "Show Speed Value",
        function(v) h:ApplySetting("showSpeed", v) end,
        "Display the current speed as a percentage on or near the bar.")
    c.showAccel = h.Toggle(content, "Show Acceleration",
        function(v) h:ApplySetting("showAccel", v) end,
        "Show an up / down arrow when speed is rising or falling.")
    c.textPosition = h.Dropdown(content, "Text & Icon Position", 160, TEXT_POSITION_OPTIONS,
        function(v) h:ApplySetting("textPosition", v) end,
        "Where the speed text and acceleration arrow are placed relative to the bar.")
    c.hideUnderPct = h.Slider(content, "Hide Bar Below Speed (%)", 0, 1500, 10, 0,
        function(v) h:ApplySetting("hideUnderPct", v) end,
        "Hide the bar while your current speed is at or below this value. "
        .. "0 = always visible. 200 hides at foot / basic mount speeds and only appears once skyriding kicks in.")

    h.Header(content, "Colors")
    local barColors = CreateColorGroupRow(content, "Bar colors", {
        { key = "colorMain", label = "Main",
            tooltip = "Color of the bar fill at high / accelerating speeds.",
            onChange = function(v) h:ApplySetting("colorMain", v) end },
        { key = "colorSustainable", label = "Sustain",
            tooltip = "Color at sustained cruising speed (steady glide / vigor).",
            onChange = function(v) h:ApplySetting("colorSustainable", v) end },
        { key = "colorSlow", label = "Slow",
            tooltip = "Color at low / decelerating speeds.",
            onChange = function(v) h:ApplySetting("colorSlow", v) end },
    })
    c.colorMain = barColors.colorMain
    c.colorSustainable = barColors.colorSustainable
    c.colorSlow = barColors.colorSlow
    c.useGradientColor = h.Toggle(content, "Smooth Color Gradient",
        function(v) h:ApplySetting("useGradientColor", v) end,
        "Smoothly interpolate the bar color across the three speed bands instead of using hard color buckets.")

    h.Header(content, "Style")
    c.fillTextureKey = h.Dropdown(content, "Fill Texture", 200, FILL_TEXTURE_OPTIONS,
        function(v) h:ApplySetting("fillTextureKey", v) end,
        "Texture used for the bar fill. Solid = flat color, others borrow Blizzard's status-bar textures.")
    c.showBackground = h.Toggle(content, "Show Background",
        function(v) h:ApplySetting("showBackground", v) end,
        "Draw a dark backplate behind the speed bar.")
    c.showBorder = h.Toggle(content, "Show 1px Border",
        function(v) h:ApplySetting("showBorder", v) end,
        "Draw a thin border around the speed bar.")
    c.showMarker = h.Toggle(content, "Show Sustain Marker",
        function(v) h:ApplySetting("showMarker", v) end,
        "Draw a vertical line at the sustainable-speed mark so you can see when you cross it.")
    local styleColors = CreateColorGroupRow(content, "Style colors", {
        { key = "backgroundColor", label = "BG",
            tooltip = "Color of the dark backplate behind the bar.",
            onChange = function(v) h:ApplySetting("backgroundColor", v) end },
        { key = "borderColor", label = "Border",
            tooltip = "Color of the 1px bar border.",
            onChange = function(v) h:ApplySetting("borderColor", v) end },
        { key = "markerColor", label = "Marker",
            tooltip = "Color of the sustain-speed marker line.",
            onChange = function(v) h:ApplySetting("markerColor", v) end },
    })
    c.backgroundColor = styleColors.backgroundColor
    c.borderColor = styleColors.borderColor
    c.markerColor = styleColors.markerColor

    h.Header(content, "Font")
    c.fontSize = h.Slider(content, "Font Size", 8, 20, 1, 0,
        function(v) h:ApplySetting("fontSize", v) end,
        "Font size for the speed text.")
    c.fontOutline = h.Dropdown(content, "Font Outline", 160, FONT_OUTLINE_OPTIONS,
        function(v) h:ApplySetting("fontOutline", v) end,
        "Outline thickness around the speed text for legibility against bright backgrounds.")

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("dynamic_flight_tracker")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("dynamic_flight_tracker", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("dynamic_flight_tracker")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("dynamic_flight_tracker")
        for _, w in pairs(c) do if type(w) == "table" and w.SetEnabled then w:SetEnabled(a) end end

        local mod = ns.ModuleRegistry:GetModule("dynamic_flight_tracker")
        local d = (mod and mod.defaults) or {}

        c.barWidth:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "barWidth") or 200)
        c.barHeight:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "barHeight") or 12)
        c.scale:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "scale") or 1.0)
        c.xOffset:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "xOffset") or 0)
        c.yOffset:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "yOffset") or d.yOffset or -300)
        c.arrowScale:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "arrowScale") or 1.5)
        c.showSpeed:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "showSpeed") ~= false)
        c.showAccel:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "showAccel") ~= false)
        c.textPosition:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "textPosition") or "above")
        c.hideUnderPct:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "hideUnderPct") or d.hideUnderPct or 0)
        c.colorMain:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "colorMain"))
        c.colorSustainable:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "colorSustainable"))
        c.colorSlow:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "colorSlow"))
        c.useGradientColor:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "useGradientColor") == true)

        c.fillTextureKey:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "fillTextureKey") or d.fillTextureKey or "solid")
        c.showBackground:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "showBackground") ~= false)
        c.backgroundColor:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "backgroundColor") or d.backgroundColor)
        c.showBorder:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "showBorder") == true)
        c.borderColor:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "borderColor") or d.borderColor)
        c.showMarker:SetChecked(ns.Settings:GetModuleValue("dynamic_flight_tracker", "showMarker") ~= false)
        c.markerColor:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "markerColor") or d.markerColor)
        c.fontSize:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "fontSize") or d.fontSize or 11)
        c.fontOutline:SetValue(ns.Settings:GetModuleValue("dynamic_flight_tracker", "fontOutline") or d.fontOutline or "NONE")

        -- Sub-control gating: colour pickers are meaningless if their parent
        -- toggle is off. Grey them out so the panel reads clearly at a glance.
        -- The underlying setting value is preserved either way.
        if a then
            local showBg = ns.Settings:GetModuleValue("dynamic_flight_tracker", "showBackground") ~= false
            local showBrd = ns.Settings:GetModuleValue("dynamic_flight_tracker", "showBorder") == true
            local showMrk = ns.Settings:GetModuleValue("dynamic_flight_tracker", "showMarker") ~= false
            c.backgroundColor:SetEnabled(showBg)
            c.borderColor:SetEnabled(showBrd)
            c.markerColor:SetEnabled(showMrk)

            -- Accel icon scale only matters when the acceleration indicator is shown.
            local showAcc = ns.Settings:GetModuleValue("dynamic_flight_tracker", "showAccel") ~= false
            c.arrowScale:SetEnabled(showAcc)

            -- Text position only matters when at least one text element is shown.
            local showSpd = ns.Settings:GetModuleValue("dynamic_flight_tracker", "showSpeed") ~= false
            c.textPosition:SetEnabled(showSpd or showAcc)
            c.fontSize:SetEnabled(showSpd)
            c.fontOutline:SetEnabled(showSpd)
        end
    end

    return c, Refresh
end

local function BuildAuctionFilterPersistPage(content)
    local c = {}
    local h = MakeHelpers("auction_filter_persist")
    h.Reset()
    h.Header(content, "Auction House Filter Persist")

    c.themeColors = CreateThemeColorRow(content, "auction_filter_persist", function()
        OptionsPanel:Refresh()
    end)

    c.showOverlay = h.Toggle(content, "Show overlay above the AH",
        function(v) h:ApplySetting("showOverlay", v) end,
        "Display a small status bar above the auction Browse window that shows the active filters.")
    c.autoSave = h.Toggle(content, "Auto-save on every change",
        function(v) h:ApplySetting("autoSave", v) end,
        "Remember filter changes immediately so they restore next time you open the AH.")

    h.Header(content, "Visible Chips")
    c.showLevelChip = h.Toggle(content, "Show level range chip",
        function(v) h:ApplySetting("showLevelChip", v) end,
        "Display the min-max item-level range as a chip in the overlay.")
    c.showCategoryChip = h.Toggle(content, "Show category chip",
        function(v) h:ApplySetting("showCategoryChip", v) end,
        "Display the active item-category filter (Weapons / Armor / etc.) as a chip.")
    c.showToggleChips = h.Toggle(content, "Show filter toggles",
        function(v) h:ApplySetting("showToggleChips", v) end,
        "Display the boolean filter chips (Usable, Current Expansion, Upgrades, etc.).")
    c.showRarityDots = h.Toggle(content, "Show rarity dots",
        function(v) h:ApplySetting("showRarityDots", v) end,
        "Display the rarity filters as small colored dots in the overlay.")

    h.Header(content, "Saved State")
    c.clearAllBtn = h.Button(content, "Clear AH Filters", function()
        local mod = ns.ModuleRegistry:GetModule("auction_filter_persist")
        if mod and mod.ResetAllFilters then mod:ResetAllFilters() end
        OptionsPanel:Refresh()
    end)

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("auction_filter_persist")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("auction_filter_persist", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("auction_filter_persist")
            OptionsPanel:Refresh()
        end
    end)

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("auction_filter_persist")
        c.showOverlay:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "showOverlay") ~= false)
        c.showOverlay:SetEnabled(a)
        c.themeColors:SetValues(
            ns.Settings:GetModuleValue("auction_filter_persist", "accentColor"),
            ns.Settings:GetModuleValue("auction_filter_persist", "surfaceColor"),
            ns.Settings:GetModuleValue("auction_filter_persist", "customTheme") == true
        )
        c.themeColors:SetEnabled(a)
        c.autoSave:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "autoSave") ~= false)
        c.autoSave:SetEnabled(a)
        c.showLevelChip:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "showLevelChip") ~= false)
        c.showLevelChip:SetEnabled(a)
        c.showCategoryChip:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "showCategoryChip") ~= false)
        c.showCategoryChip:SetEnabled(a)
        c.showToggleChips:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "showToggleChips") ~= false)
        c.showToggleChips:SetEnabled(a)
        c.showRarityDots:SetChecked(ns.Settings:GetModuleValue("auction_filter_persist", "showRarityDots") ~= false)
        c.showRarityDots:SetEnabled(a)
        c.clearAllBtn:SetEnabled(a)
    end

    return c, Refresh
end

local ACCOUNTING_CLEAR_CHARACTER_POPUP_KEY = "THYRAXUTIL_CLEAR_ACCOUNTING_LEDGER_CHARACTER"
local ACCOUNTING_CLEAR_ACCOUNT_POPUP_KEY = "THYRAXUTIL_CLEAR_ACCOUNTING_LEDGER_ACCOUNT"

local function ConfirmClearAccountingLedger(scope)
    if StaticPopupDialogs and StaticPopup_Show then
        local accountWide = scope == "account"
        local popupKey = accountWide and ACCOUNTING_CLEAR_ACCOUNT_POPUP_KEY or ACCOUNTING_CLEAR_CHARACTER_POPUP_KEY
        StaticPopupDialogs[popupKey] = {
            text = accountWide
                and "Clear the accounting ledger for every account character?\n\nThis cannot be undone."
                or "Clear the accounting ledger for this character?\n\nThis cannot be undone.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if accountWide then
                    if mod and mod.ClearAllShards then mod:ClearAllShards() end
                else
                    if mod and mod.ClearShard then mod:ClearShard() end
                end
                OptionsPanel:Refresh()
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
        StaticPopup_Show(popupKey)
    elseif ns.Diagnostics and ns.Diagnostics.Warn then
        ns.Diagnostics:Warn("Accounting ledger was not cleared: confirmation dialog is unavailable.")
    end
end

local ACCOUNTING_RESET_LIFETIME_CHARACTER_POPUP_KEY = "THYRAXUTIL_RESET_ACCOUNTING_LIFETIME_CHARACTER"
local ACCOUNTING_RESET_LIFETIME_ACCOUNT_POPUP_KEY = "THYRAXUTIL_RESET_ACCOUNTING_LIFETIME_ACCOUNT"

-- The all-time footer totals survive a normal ledger clear and entry pruning,
-- so resetting them is a separate, explicit action. Entries are kept; only the
-- running income/expense counters are zeroed.
local function ConfirmResetAccountingLifetime(scope)
    if StaticPopupDialogs and StaticPopup_Show then
        local accountWide = scope == "account"
        local popupKey = accountWide and ACCOUNTING_RESET_LIFETIME_ACCOUNT_POPUP_KEY or ACCOUNTING_RESET_LIFETIME_CHARACTER_POPUP_KEY
        StaticPopupDialogs[popupKey] = {
            text = accountWide
                and "Reset the all-time totals for every account character?\n\nThe ledger entries are kept; only the lifetime footer totals are zeroed. This cannot be undone."
                or "Reset the all-time totals for this character?\n\nThe ledger entries are kept; only the lifetime footer totals are zeroed. This cannot be undone.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if accountWide then
                    if mod and mod.ClearAllShardLifetime then mod:ClearAllShardLifetime() end
                else
                    if mod and mod.ClearShardLifetime then mod:ClearShardLifetime() end
                end
                OptionsPanel:Refresh()
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
        StaticPopup_Show(popupKey)
    elseif ns.Diagnostics and ns.Diagnostics.Warn then
        ns.Diagnostics:Warn("Accounting all-time totals were not reset: confirmation dialog is unavailable.")
    end
end

local function BuildAccountingTrackerPage(content)
    local c = {}
    local h = MakeHelpers("accounting_tracker")
    h.Reset()
    h.Header(content, "Accounting Tracker")
    -- (Enable / disable lives on the General page. This tab is only visible
    --  when the module is enabled, matching the convention for other modules.)
    c.openWindowBtn = h.Button(content, "Open Ledger Window", function()
        local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
        if mod and mod.ShowWindow then mod:ShowWindow() end
    end, 200)

    c.themeColors = CreateThemeColorRow(content, "accounting_tracker", function()
        OptionsPanel:Refresh()
    end)

    h.Header(content, "Window")
    c.showMinimapButton = h.Toggle(content, "Show minimap button",
        function(v) h:ApplySetting("showMinimapButton", v) end,
        "Display a button on the minimap that opens the ledger window.")
    c.minimapBtnResetPos = h.Button(content, "Reset button position", function()
        local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
        if mod and mod.ResetMinimapButtonPosition then
            mod:ResetMinimapButtonPosition()
        end
    end)
    c.windowAlpha = h.Slider(content, "Window transparency", 0.3, 1.0, 0.05, 2,
        function(v) h:ApplySetting("windowAlpha", v) end,
        "Background opacity of the ledger window. 1 = fully opaque.")
    c.defaultTab = h.Dropdown(content, "Default window tab", 170, {
        { value = "last", label = "Last used" },
        { value = "overview", label = "Overview" },
        { value = "all", label = "Ledger" },
        { value = "income", label = "Income" },
        { value = "expenses", label = "Expenses" },
        { value = "groups", label = "Groups" },
        { value = "charts", label = "Charts" },
    },
        function(v) h:ApplySetting("defaultTab", v) end,
        "Which tab the ledger window opens on. 'Last used' remembers your last choice between sessions.")

    h.Header(content, "Visible Sources")
    c.showCategoryAH = h.Toggle(content, "Auction House",
        function(v) h:ApplySetting("showCategoryAH", v) end,
        "Include auction sales, buyouts and deposits in ledger summaries and totals.")
    c.showCategoryVendor = h.Toggle(content, "Vendor and repairs",
        function(v) h:ApplySetting("showCategoryVendor", v) end,
        "Include vendor purchases, junk sales and repair bills.")
    c.showCategoryQuest = h.Toggle(content, "Quest rewards",
        function(v) h:ApplySetting("showCategoryQuest", v) end,
        "Include gold rewards from completed quests.")
    c.showCategoryLoot = h.Toggle(content, "Loot",
        function(v) h:ApplySetting("showCategoryLoot", v) end,
        "Include coin loot picked up from creatures and containers.")
    c.showCategoryMail = h.Toggle(content, "Mail and COD",
        function(v) h:ApplySetting("showCategoryMail", v) end,
        "Include money received via mail and cash-on-delivery transactions.")
    c.showCategoryTrade = h.Toggle(content, "Trade",
        function(v) h:ApplySetting("showCategoryTrade", v) end,
        "Include gold exchanged via the player-to-player trade window.")
    c.showCategoryWorkOrders = h.Toggle(content, "Work Orders",
        function(v) h:ApplySetting("showCategoryWorkOrders", v) end,
        "Include payouts and fees from crafting work orders.")
    c.showCategoryOther = h.Toggle(content, "Other / unattributed",
        function(v) h:ApplySetting("showCategoryOther", v) end,
        "Include money changes the addon could not attribute to a specific source.")

    h.Header(content, "Money Text")
    c.moneyCompactAlways = h.Toggle(content, "Always abbreviate money",
        function(v) h:ApplySetting("moneyCompactAlways", v) end,
        "Show compact K/M gold amounts even when the full amount would fit.")
    c.moneyThousandsSeparator = h.Dropdown(content, "Thousands separator", 130, {
        { value = ".", display = "Period (.)" },
        { value = ",", display = "Comma (,)" },
        { value = "space", display = "Space" },
        { value = "none", display = "None" },
    },
        function(v) h:ApplySetting("moneyThousandsSeparator", v) end,
        "Separator inserted every three digits in full gold amounts.")

    h.Header(content, "Ledger Data")
    c.maxEntries = h.Slider(content, "Max entries per character", 5000, 100000, 5000, 0,
        function(v) h:ApplySetting("maxEntries", v) end,
        "Maximum number of ledger entries kept per character. The oldest 10% gets trimmed when the cap is exceeded.")
    c.clearCharacterBtn = h.Button(content, "Clear Character", function()
        ConfirmClearAccountingLedger("character")
    end)
    c.clearAccountBtn = h.Button(content, "Clear Account", function()
        ConfirmClearAccountingLedger("account")
    end, nil, "danger")

    h.Header(content, "All-time Totals")
    c.resetLifetimeCharacterBtn = h.Button(content, "Reset All-time (Char)", function()
        ConfirmResetAccountingLifetime("character")
    end)
    c.resetLifetimeAccountBtn = h.Button(content, "Reset All-time (Account)", function()
        ConfirmResetAccountingLifetime("account")
    end, nil, "danger")

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                -- Never touch `shards` from a defaults reset -- that would
                -- wipe the user's actual ledger data. Same guard for `enabled`
                -- so the user has to flip the toggle themselves.
                if k ~= "enabled" and k ~= "shards" then
                    ns.Settings:SetModuleValue("accounting_tracker", k, v)
                end
            end
            ns.ModuleRegistry:ApplyModuleSettings("accounting_tracker")
            OptionsPanel:Refresh()
        end
    end)

    -- ===================== Dev / Diagnostics (collapsible) =====================
    -- All debug-only toggles (chat report buttons, verbose logging, dev tools,
    -- cache list) live behind this header so the normal options pane stays
    -- focused on user-visible settings. Toggle persists across reloads.
    -- Compact layout: clickable header toggles a fixed-size content block
    -- (4 buttons in one row + stats + scrollable cache list). Toggle persists
    -- across reloads. Auto-refresh ticker updates the cache view every 2s so
    -- background changes (GET_ITEM_INFO_RECEIVED auto-caching, posting hooks)
    -- show without having to click Refresh.
    local devExpanded = ns.Settings:GetModuleValue("accounting_tracker", "devPanelExpanded") == true
    currentYOffset = currentYOffset - 12
    c.devHeaderBtn = CreateFrame("Button", nil, content)
    c.devHeaderBtn:SetSize(460, 20)
    c.devHeaderBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, currentYOffset)
    local devLabel = c.devHeaderBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    devLabel:SetPoint("LEFT", c.devHeaderBtn, "LEFT", 0, 0)
    devLabel:SetText((devExpanded and "[-] " or "[+] ") .. "Dev / Diagnostics")
    local devHl = c.devHeaderBtn:CreateTexture(nil, "HIGHLIGHT")
    devHl:SetAllPoints()
    devHl:SetColorTexture(1, 1, 1, 0.06)
    c.devHeaderBtn:SetScript("OnClick", function()
        local newExpanded = not (ns.Settings:GetModuleValue("accounting_tracker", "devPanelExpanded") == true)
        ns.Settings:SetModuleValue("accounting_tracker", "devPanelExpanded", newExpanded)
        OptionsPanel:Rebuild()
    end)
    currentYOffset = currentYOffset - 22

    if devExpanded then
        -- Debug-only toggles (moved here so the main pane is not cluttered).
        c.showDebugActions = h.Toggle(content, "Show report buttons",
            function(v) h:ApplySetting("showDebugActions", v) end,
            "Expose the Summary / Last / Status buttons below so you can print ledger snapshots to chat.")
        c.verboseLogging = h.Toggle(content, "Verbose chat logging",
            function(v) h:ApplySetting("verboseLogging", v) end,
            "Print every recorded ledger entry to chat as it happens. Useful for debugging, very noisy.")
        c.logUnattributed = h.Toggle(content, "Log unattributed deltas",
            function(v) h:ApplySetting("logUnattributed", v) end,
            "Also record money changes the addon could not attribute to a known source.")
        local reportButtons = CreateActionButtonRow(content, {
            { key = "summary24h", text = "Summary 24h", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintSummary then mod:PrintSummary("24h") end
            end },
            { key = "summary7d", text = "Summary 7d", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintSummary then mod:PrintSummary("7d") end
            end },
            { key = "summary30d", text = "Summary 30d", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintSummary then mod:PrintSummary("30d") end
            end },
            { key = "summaryAll", text = "Summary All", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintSummary then mod:PrintSummary("all") end
            end },
            { key = "recent", text = "Last 10", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintRecent then mod:PrintRecent(10) end
            end },
            { key = "status", text = "Status", callback = function()
                local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
                if mod and mod.PrintStatus then mod:PrintStatus() end
            end },
        }, 3, 132)
        c.chatReportRow = reportButtons.row
        c.summary24h = reportButtons.summary24h
        c.summary7d = reportButtons.summary7d
        c.summary30d = reportButtons.summary30d
        c.summaryAll = reportButtons.summaryAll
        c.recentBtn = reportButtons.recent
        c.statusBtn = reportButtons.status

        currentYOffset = currentYOffset - 4

        -- Stat label (single line) above the button row.
        c.devStat = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        c.devStat:SetPoint("TOPLEFT", content, "TOPLEFT", 16, currentYOffset)
        c.devStat:SetText("Cache: 0 entries")
        currentYOffset = currentYOffset - 18

        -- Compact button helper (manual positioning to keep 4 in one row).
        local function MakeCompactBtn(parent, x, y, w, text, callback)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(w, 22)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.20, 0.12, 0.06, 0.95)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(PaletteRGBA("accentSoft", 0.20))
            local t = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            t:SetPoint("CENTER", btn, "CENTER", 0, 0)
            t:SetText(text)
            t:SetTextColor(PaletteRGBA("header"))
            btn.label = t
            btn:SetScript("OnClick", function()
                if not ns.OptionsPanel.refreshing then callback() end
            end)
            return btn
        end

        local btnW = 86
        local btnGap = 4
        local btnY = currentYOffset
        c.devRefreshBtn  = MakeCompactBtn(content, 16,                        btnY, btnW, "Refresh",  function() ns.OptionsPanel:Refresh() end)
        c.devScanAHBtn   = MakeCompactBtn(content, 16 + (btnW + btnGap) * 1,  btnY, btnW, "Scan AH",  function()
            local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
            if not mod then return end
            if mod.RequestOwnedAuctionsScan then mod:RequestOwnedAuctionsScan() end
            local added = mod.ScanOwnedAuctions and mod:ScanOwnedAuctions() or 0
            if ns.Diagnostics then
                ns.Diagnostics:Info(string.format("Accounting: scanned owned auctions, added %d cache entries (more may follow in 2s).", added))
            end
            ns.OptionsPanel:Refresh()
        end)
        c.devBackfillBtn = MakeCompactBtn(content, 16 + (btnW + btnGap) * 2,  btnY, btnW, "Backfill", function()
            local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
            if not mod then return end
            local added = mod.BackfillItemNameCacheFromLedger and mod:BackfillItemNameCacheFromLedger() or 0
            if ns.Diagnostics then
                ns.Diagnostics:Info(string.format("Accounting: backfilled %d name->ID cache entries from ledger.", added))
            end
            ns.OptionsPanel:Refresh()
        end)
        c.devResolveBtn  = MakeCompactBtn(content, 16 + (btnW + btnGap) * 3,  btnY, btnW, "Resolve",  function()
            local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
            if not mod then return end
            local n = mod.ResolveUnresolvedLedgerEntries and mod:ResolveUnresolvedLedgerEntries() or 0
            if ns.Diagnostics then
                ns.Diagnostics:Info(string.format("Accounting: resolved %d ledger entries from client item cache.", n))
            end
            ns.OptionsPanel:Refresh()
        end)
        c.devClearBtn    = MakeCompactBtn(content, 16 + (btnW + btnGap) * 4,  btnY, btnW, "Clear",    function()
            local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
            if not mod then return end
            local removed = mod.ClearItemNameCache and mod:ClearItemNameCache() or 0
            if ns.Diagnostics then
                ns.Diagnostics:Info(string.format("Accounting: cleared %d name->ID cache entries.", removed))
            end
            ns.OptionsPanel:Refresh()
        end)
        currentYOffset = currentYOffset - 26

        -- Cache list. ScrollFrame + child Frame + FontString. Auto-refreshed
        -- by a ticker (see below) so newly cached items appear without clicks.
        currentYOffset = currentYOffset - 4
        local listFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
        listFrame:SetSize(460, 200)
        listFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 16, currentYOffset)
        if listFrame.SetBackdrop then
            listFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            listFrame:SetBackdropColor(0.05, 0.04, 0.02, 0.85)
            listFrame:SetBackdropBorderColor(0.30, 0.22, 0.10, 0.95)
        else
            local bg = listFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.05, 0.04, 0.02, 0.85)
        end
        c.devListFrame = listFrame

        local scroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, 6)
        local scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetSize(420, 1)
        scroll:SetScrollChild(scrollChild)
        local body = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -4)
        body:SetWidth(412)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(2)
        body:SetText("")
        c.devListScroll = scroll
        c.devListChild = scrollChild
        c.devListBody = body

        currentYOffset = currentYOffset - 204

        -- Local helper: rebuild only the cache list (no full OptionsPanel refresh)
        -- so the ticker stays cheap. Touches three widgets: stat label, body text,
        -- and child height. No global side effects, no other-page work.
        local function UpdateDevList()
            local mod = ns.ModuleRegistry:GetModule("accounting_tracker")
            local snapshot = (mod and mod.GetItemNameCacheSnapshot) and mod:GetItemNameCacheSnapshot() or {}
            c.devStat:SetText(string.format("Cache: %d entries  (auto-refreshes every 5s)", #snapshot))
            local lines = {}
            for _, e in ipairs(snapshot) do
                local label = e.link or e.name
                lines[#lines + 1] = string.format("%-6d  %s", e.itemID or 0, tostring(label))
            end
            if #lines == 0 then
                c.devListBody:SetText("(cache is empty -- post an item, browse the AH, or click Backfill)")
                c.devListChild:SetHeight(20)
            else
                c.devListBody:SetText(table.concat(lines, "\n"))
                c.devListChild:SetHeight(math.max(20, #lines * 12 + 8))
            end
        end
        c.UpdateDevList = UpdateDevList

    end
    -- ===========================================================================

    local function Refresh()
        local a = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("accounting_tracker")
        c.openWindowBtn:SetEnabled(a)
        c.themeColors:SetValues(
            ns.Settings:GetModuleValue("accounting_tracker", "accentColor"),
            ns.Settings:GetModuleValue("accounting_tracker", "surfaceColor"),
            ns.Settings:GetModuleValue("accounting_tracker", "customTheme") == true
        )
        c.themeColors:SetEnabled(a)
        c.showMinimapButton:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showMinimapButton") == true)
        c.showMinimapButton:SetEnabled(a)
        c.minimapBtnResetPos:SetEnabled(a)
        c.windowAlpha:SetValue(ns.Settings:GetModuleValue("accounting_tracker", "windowAlpha") or 0.92)
        c.windowAlpha:SetEnabled(a)
        c.defaultTab:SetValue(ns.Settings:GetModuleValue("accounting_tracker", "defaultTab") or "last")
        c.defaultTab:SetEnabled(a)
        c.showCategoryAH:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryAH") ~= false)
        c.showCategoryAH:SetEnabled(a)
        c.showCategoryVendor:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryVendor") ~= false)
        c.showCategoryVendor:SetEnabled(a)
        c.showCategoryQuest:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryQuest") ~= false)
        c.showCategoryQuest:SetEnabled(a)
        c.showCategoryLoot:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryLoot") ~= false)
        c.showCategoryLoot:SetEnabled(a)
        c.showCategoryMail:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryMail") ~= false)
        c.showCategoryMail:SetEnabled(a)
        c.showCategoryTrade:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryTrade") ~= false)
        c.showCategoryTrade:SetEnabled(a)
        c.showCategoryWorkOrders:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryWorkOrders") ~= false)
        c.showCategoryWorkOrders:SetEnabled(a)
        c.showCategoryOther:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showCategoryOther") ~= false)
        c.showCategoryOther:SetEnabled(a)
        c.moneyCompactAlways:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "moneyCompactAlways") == true)
        c.moneyCompactAlways:SetEnabled(a)
        c.moneyThousandsSeparator:SetValue(ns.Settings:GetModuleValue("accounting_tracker", "moneyThousandsSeparator") or ".")
        c.moneyThousandsSeparator:SetEnabled(a)
        c.maxEntries:SetValue(tonumber(ns.Settings:GetModuleValue("accounting_tracker", "maxEntries")) or 20000)
        c.maxEntries:SetEnabled(a)
        c.clearCharacterBtn:SetEnabled(a)
        c.clearAccountBtn:SetEnabled(a)
        c.resetLifetimeCharacterBtn:SetEnabled(a)
        c.resetLifetimeAccountBtn:SetEnabled(a)

        -- Dev / Diagnostics widgets only exist when the section is expanded.
        if c.verboseLogging then
            c.verboseLogging:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "verboseLogging") == true)
            c.verboseLogging:SetEnabled(a)
        end
        if c.logUnattributed then
            c.logUnattributed:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "logUnattributed") == true)
            c.logUnattributed:SetEnabled(a)
        end
        if c.showDebugActions then
            c.showDebugActions:SetChecked(ns.Settings:GetModuleValue("accounting_tracker", "showDebugActions") == true)
            c.showDebugActions:SetEnabled(a)
            local showDebug = a and ns.Settings:GetModuleValue("accounting_tracker", "showDebugActions") == true
            if c.chatReportRow then c.chatReportRow:SetShown(showDebug) end
            for _, key in ipairs({ "summary24h", "summary7d", "summary30d", "summaryAll", "recentBtn", "statusBtn" }) do
                local widget = c[key]
                if widget then
                    widget:SetShown(showDebug)
                    widget:SetEnabled(showDebug)
                end
            end
        end

        if c.devListBody then
            if c.UpdateDevList then c.UpdateDevList() end
            c.devRefreshBtn:SetEnabled(a)
            c.devScanAHBtn:SetEnabled(a)
            c.devBackfillBtn:SetEnabled(a)
            c.devResolveBtn:SetEnabled(a)
            c.devClearBtn:SetEnabled(a)
        end
    end

    return c, Refresh
end

local function BuildCharacterPanelPage(content)
    local c = {}
    local h = MakeHelpers("character_panel_enhancer")
    h.Reset()
    h.Header(content, "Character Panel")

    c.showCharacterGear = h.Toggle(content, "Show gear overlay (your character)",
        function(v) h:ApplySetting("showCharacterGear", v) end,
        "Stamps item level, enchant and gem markers onto your own equipped slots.")
    c.showInspectGear = h.Toggle(content, "Show gear overlay (inspect)",
        function(v) h:ApplySetting("showInspectGear", v) end,
        "Applies the same slot overlays when you inspect another player.")
    c.showStatsPanel = h.Toggle(content, "Show stats panel",
        function(v) h:ApplySetting("showStatsPanel", v) end,
        "Docks a detailed, categorized stats panel next to the character window.")

    h.Header(content, "Gear Slot Display")
    c.showItemLevels = h.Toggle(content, "Show item levels",
        function(v) h:ApplySetting("showItemLevels", v) end,
        "Shows the item level number on each gear slot.")
    c.showEnchants = h.Toggle(content, "Show enchant marker",
        function(v) h:ApplySetting("showEnchants", v) end,
        "Green E when a slot is enchanted, red ! when a required enchant is missing.")
    c.showGems = h.Toggle(content, "Show gem icons",
        function(v) h:ApplySetting("showGems", v) end,
        "Shows socketed gem icons on the slot, and red markers for empty sockets.")
    c.showQualityBorder = h.Toggle(content, "Show quality border",
        function(v) h:ApplySetting("showQualityBorder", v) end,
        "Frames each equipped slot with a border colored by item quality.")
    c.showWarnings = h.Toggle(content, "Show gear warnings",
        function(v) h:ApplySetting("showWarnings", v) end,
        "Highlights missing enchants, empty sockets and missing items with red markers.")
    c.slotInfoBeside = h.Toggle(content, "Beside-icon layout",
        function(v) h:ApplySetting("slotInfoBeside", v) end,
        "Draws item level, enchant and gems next to each slot instead of on top of the icon.")

    h.Header(content, "Warning Rules")
    c.minItemLevelForWarnings = h.Slider(content, "Min ilvl for enchant warnings", 0, 900, 1, 0,
        function(v) h:ApplySetting("minItemLevelForWarnings", v) end,
        "Suppresses missing-enchant warnings on items below this item level. 0 = always warn.")

    h.Header(content, "Required Enchants")
    local enchTooltip = "Treat this slot as requiring an enchant. Missing enchants on required slots show a red warning marker."
    c.requireEnchantHead = h.Toggle(content, "Head",
        function(v) h:ApplySetting("requireEnchantHead", v) end, enchTooltip)
    c.requireEnchantShoulder = h.Toggle(content, "Shoulders",
        function(v) h:ApplySetting("requireEnchantShoulder", v) end, enchTooltip)
    c.requireEnchantBack = h.Toggle(content, "Back",
        function(v) h:ApplySetting("requireEnchantBack", v) end, enchTooltip)
    c.requireEnchantChest = h.Toggle(content, "Chest",
        function(v) h:ApplySetting("requireEnchantChest", v) end, enchTooltip)
    c.requireEnchantWaist = h.Toggle(content, "Waist",
        function(v) h:ApplySetting("requireEnchantWaist", v) end, enchTooltip)
    c.requireEnchantWrist = h.Toggle(content, "Wrist",
        function(v) h:ApplySetting("requireEnchantWrist", v) end, enchTooltip)
    c.requireEnchantLegs = h.Toggle(content, "Legs",
        function(v) h:ApplySetting("requireEnchantLegs", v) end, enchTooltip)
    c.requireEnchantFeet = h.Toggle(content, "Feet",
        function(v) h:ApplySetting("requireEnchantFeet", v) end, enchTooltip)
    c.requireEnchantRings = h.Toggle(content, "Rings",
        function(v) h:ApplySetting("requireEnchantRings", v) end, enchTooltip)
    c.requireEnchantMainHand = h.Toggle(content, "Main hand",
        function(v) h:ApplySetting("requireEnchantMainHand", v) end, enchTooltip)
    c.requireEnchantOffHand = h.Toggle(content, "Off hand",
        function(v) h:ApplySetting("requireEnchantOffHand", v) end, enchTooltip)

    h.Header(content, "Stats Panel")
    local statTooltip = "Include this row in the stats panel docked to the character window."
    c.showStatItemLevel = h.Toggle(content, "Item level",
        function(v) h:ApplySetting("showStatItemLevel", v) end, statTooltip)
    c.showStatEnchantReady = h.Toggle(content, "Enchants",
        function(v) h:ApplySetting("showStatEnchantReady", v) end,
        "Show how many required enchants are present. Green when complete, red when one is missing.")
    c.showStatSocketReady = h.Toggle(content, "Sockets",
        function(v) h:ApplySetting("showStatSocketReady", v) end,
        "Show how many gem sockets are filled. Green when complete, red when sockets are empty.")
    c.showStatHealth = h.Toggle(content, "Health",
        function(v) h:ApplySetting("showStatHealth", v) end, statTooltip)
    c.showStatArmor = h.Toggle(content, "Armor",
        function(v) h:ApplySetting("showStatArmor", v) end, statTooltip)
    c.showStatPrimary = h.Toggle(content, "Primary stat",
        function(v) h:ApplySetting("showStatPrimary", v) end,
        "Show your spec's primary stat (Strength / Agility / Intellect).")
    c.showStatStamina = h.Toggle(content, "Stamina",
        function(v) h:ApplySetting("showStatStamina", v) end, statTooltip)
    c.showStatCrit = h.Toggle(content, "Critical strike",
        function(v) h:ApplySetting("showStatCrit", v) end, statTooltip)
    c.showStatHaste = h.Toggle(content, "Haste",
        function(v) h:ApplySetting("showStatHaste", v) end, statTooltip)
    c.showStatMastery = h.Toggle(content, "Mastery",
        function(v) h:ApplySetting("showStatMastery", v) end, statTooltip)
    c.showStatVersatility = h.Toggle(content, "Versatility",
        function(v) h:ApplySetting("showStatVersatility", v) end, statTooltip)
    c.showStatLeech = h.Toggle(content, "Leech",
        function(v) h:ApplySetting("showStatLeech", v) end, statTooltip)
    c.showStatAvoidance = h.Toggle(content, "Avoidance",
        function(v) h:ApplySetting("showStatAvoidance", v) end, statTooltip)
    c.showStatSpeed = h.Toggle(content, "Speed",
        function(v) h:ApplySetting("showStatSpeed", v) end,
        "Show your movement speed as a percentage of base run speed (7 yd/s = 100%).")
    c.showStatTank = h.Toggle(content, "Tank stats",
        function(v) h:ApplySetting("showStatTank", v) end,
        "Show Dodge, Parry and Block percentages (relevant for tank specs).")

    h.Header(content, "Appearance")
    c.fontSize = h.Slider(content, "Stats panel font size", 8, 20, 1, 0,
        function(v) h:ApplySetting("fontSize", v) end,
        "Font size for the stat rows in the integrated stats panel.")
    c.ilvlFontSize = h.Slider(content, "Item level font size", 8, 24, 1, 0,
        function(v) h:ApplySetting("ilvlFontSize", v) end,
        "Font size of the item level number stamped on each gear slot.")
    c.gemIconSize = h.Slider(content, "Gem icon size", 6, 24, 1, 0,
        function(v) h:ApplySetting("gemIconSize", v) end,
        "Size of the gem icons and empty-socket markers shown on each slot.")
    c.enchantMarkerSize = h.Slider(content, "Enchant marker size", 8, 24, 1, 0,
        function(v) h:ApplySetting("enchantMarkerSize", v) end,
        "Size of the E / ! enchant indicator on each slot.")

    h.Header(content, "Actions")
    c.refreshBtn = h.Button(content, "Refresh Panel", function()
        local mod = ns.ModuleRegistry:GetModule("character_panel_enhancer")
        if mod and mod.RefreshAll then mod:RefreshAll() end
    end, 180)

    CreateRestoreDefaultsBtn(content, function()
        local mod = ns.ModuleRegistry:GetModule("character_panel_enhancer")
        if mod and mod.defaults then
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" then ns.Settings:SetModuleValue("character_panel_enhancer", k, v) end
            end
            ns.ModuleRegistry:ApplyModuleSettings("character_panel_enhancer")
        end
        OptionsPanel:Refresh()
    end)

    local function SetToggle(key, value)
        if c[key] then c[key]:SetChecked(value == true) end
    end

    local function Refresh()
        local active = ns.Settings:IsGlobalEnabled() and ns.Settings:IsModuleEnabled("character_panel_enhancer")
        local mod = ns.ModuleRegistry:GetModule("character_panel_enhancer")
        local d = mod and mod.defaults or {}

        for _, key in ipairs({
            "showCharacterGear", "showInspectGear", "showStatsPanel",
            "showItemLevels", "showEnchants", "showGems", "showQualityBorder", "showWarnings",
            "slotInfoBeside",
            "requireEnchantHead", "requireEnchantShoulder", "requireEnchantBack", "requireEnchantChest",
            "requireEnchantWaist", "requireEnchantWrist", "requireEnchantLegs",
            "requireEnchantFeet", "requireEnchantRings", "requireEnchantMainHand", "requireEnchantOffHand",
            "showStatItemLevel", "showStatEnchantReady", "showStatSocketReady",
            "showStatHealth", "showStatArmor", "showStatPrimary",
            "showStatStamina", "showStatCrit", "showStatHaste", "showStatMastery",
            "showStatVersatility", "showStatLeech", "showStatAvoidance", "showStatSpeed", "showStatTank",
        }) do
            SetToggle(key, ns.Settings:GetModuleValue("character_panel_enhancer", key) == true)
            if c[key] and c[key].SetEnabled then c[key]:SetEnabled(active) end
        end

        c.minItemLevelForWarnings:SetValue(ns.Settings:GetModuleValue("character_panel_enhancer", "minItemLevelForWarnings") or d.minItemLevelForWarnings or 0)
        c.fontSize:SetValue(ns.Settings:GetModuleValue("character_panel_enhancer", "fontSize") or d.fontSize or 12)
        c.ilvlFontSize:SetValue(ns.Settings:GetModuleValue("character_panel_enhancer", "ilvlFontSize") or d.ilvlFontSize or 14)
        c.gemIconSize:SetValue(ns.Settings:GetModuleValue("character_panel_enhancer", "gemIconSize") or d.gemIconSize or 14)
        c.enchantMarkerSize:SetValue(ns.Settings:GetModuleValue("character_panel_enhancer", "enchantMarkerSize") or d.enchantMarkerSize or 12)

        for _, key in ipairs({ "minItemLevelForWarnings", "fontSize", "ilvlFontSize", "gemIconSize", "enchantMarkerSize", "refreshBtn" }) do
            if c[key] and c[key].SetEnabled then c[key]:SetEnabled(active) end
        end
    end

    return c, Refresh
end

-- [[ END_PAGE_BUILDERS ]]

-- [[ START_MAIN ]]
function OptionsPanel:ApplyModuleSetting(moduleID, key, value)
    ns.Settings:SetModuleValue(moduleID, key, value)
    ns.ModuleRegistry:ApplyModuleSettings(moduleID)
    self:Refresh()
end

local TAB_MODULE_MAP = {
    [1] = nil,
    [2] = "crosshair",
    [3] = "mouse_tracker",
    [4] = "darkness_announcer",
    [5] = "quest_accept_hotkey",
    [6] = "dynamic_flight_tracker",
    [7] = "auction_filter_persist",
    [8] = "accounting_tracker",
    [9] = "character_panel_enhancer",
}

local function GetTabIndexForModule(moduleID)
    if type(moduleID) == "number" then
        return moduleID
    end
    if type(moduleID) ~= "string" then
        return nil
    end
    for index, mappedID in pairs(TAB_MODULE_MAP) do
        if mappedID == moduleID then
            return index
        end
    end
    return nil
end

local OPTIONS_WINDOW_MIN_W, OPTIONS_WINDOW_MIN_H = 460, 380
local OPTIONS_WINDOW_MAX_W, OPTIONS_WINDOW_MAX_H = 1100, 900

function OptionsPanel:SaveWindowState()
    local win = self.window
    if not win then return end
    local db = ns.Settings and ns.Settings.GetDB and ns.Settings:GetDB()
    if type(db) ~= "table" then return end
    local centerX, centerY = win:GetCenter()
    if not centerX or not centerY then return end
    local scale = win:GetEffectiveScale() or 1
    db.optionsWindow = {
        x = centerX * scale,
        y = centerY * scale,
        width = win:GetWidth(),
        height = win:GetHeight(),
    }
end

function OptionsPanel:RestoreWindowState()
    local win = self.window
    if not win then return end
    local db = ns.Settings and ns.Settings.GetDB and ns.Settings:GetDB()
    local state = type(db) == "table" and db.optionsWindow
    if type(state) ~= "table" then return end
    local w = tonumber(state.width)
    local hgt = tonumber(state.height)
    if w and hgt then
        win:SetSize(
            Clamp(w, OPTIONS_WINDOW_MIN_W, OPTIONS_WINDOW_MAX_W),
            Clamp(hgt, OPTIONS_WINDOW_MIN_H, OPTIONS_WINDOW_MAX_H)
        )
    end
    local x = tonumber(state.x)
    local y = tonumber(state.y)
    if x and y then
        local scale = win:GetEffectiveScale() or 1
        if scale == 0 then scale = 1 end
        win:ClearAllPoints()
        win:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
end

function OptionsPanel:ApplyWindowTheme()
    local win = self.window
    if not win then return end
    local palette = GetAccentPalette()
    if win._themeBg then
        win._themeBg:SetColorTexture(palette.surfaceDark[1], palette.surfaceDark[2], palette.surfaceDark[3], 0.97)
    end
    if win._themeEdges then
        for _, edge in ipairs(win._themeEdges) do
            edge:SetColorTexture(palette.accentEdge[1], palette.accentEdge[2], palette.accentEdge[3], palette.accentEdge[4] or 0.95)
        end
    end
    if win._themeTitleBarBg then
        win._themeTitleBarBg:SetColorTexture(unpack(palette.surfaceDark))
    end
    if win._themeTitle then
        win._themeTitle:SetTextColor(unpack(palette.header))
    end
    local closeBtn = win._themeCloseBtn
    if closeBtn then
        local bg = closeBtn._themeHover
            and { palette.accentSoft[1] * 0.55, palette.accentSoft[2] * 0.55, palette.accentSoft[3] * 0.55, 1 }
            or { palette.surfaceDark[1], palette.surfaceDark[2], palette.surfaceDark[3], 0.95 }
        if closeBtn.SetBackdropColor then
            closeBtn:SetBackdropColor(unpack(bg))
            closeBtn:SetBackdropBorderColor(palette.accentSoft[1], palette.accentSoft[2], palette.accentSoft[3], 0.55)
        end
        if closeBtn._themeText then
            closeBtn._themeText:SetTextColor(unpack(palette.header))
        end
    end
    if win._themeGrip and win._themeGrip._themeParts then
        for _, part in ipairs(win._themeGrip._themeParts) do
            part:SetVertexColor(palette.accentEdge[1], palette.accentEdge[2], palette.accentEdge[3], 0.85)
        end
    end
    if self.tabDivider then
        local tp = GetTabPalette()
        self.tabDivider:SetColorTexture(unpack(tp.divider))
    end
    -- Search bar follows the accent palette so theme / font-color switches
    -- propagate to the bar tint and the "Search" / "X" labels.
    if win._themeSearchBg then
        win._themeSearchBg:SetColorTexture(palette.surface[1], palette.surface[2], palette.surface[3], 0.85)
    end
    if win._themeSearchBorder then
        SetTextureBorderColor(win._themeSearchBorder,
            palette.accentEdge[1], palette.accentEdge[2], palette.accentEdge[3], palette.accentEdge[4] or 0.85)
    end
    if win._themeSearchIcon then
        win._themeSearchIcon:SetTextColor(palette.header[1], palette.header[2], palette.header[3], palette.header[4] or 1)
    end
    if win._themeSearchClearText then
        win._themeSearchClearText:SetTextColor(palette.header[1], palette.header[2], palette.header[3], palette.header[4] or 1)
    end
    if self.tabs then
        for index, tab in ipairs(self.tabs) do
            if tab.SetActive then
                tab:SetActive(index == self.activeIndex)
            end
        end
    end
    if self.pages then
        for _, page in ipairs(self.pages) do
            local bar = page.ScrollBar or page.scrollBar or page.Scrollbar
            StyleScrollBar(bar)
        end
    end
    ApplyDropdownPopupTheme()
end

function OptionsPanel:EnsureWindow()
    if self.window then
        return self.window
    end

    local win = CreateFrame("Frame", "ThyraxUtilOptionsWindow", UIParent)
    win:SetSize(520, 640)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:SetResizable(true)
    win:EnableMouse(true)
    win:Hide()

    if win.SetResizeBounds then
        win:SetResizeBounds(OPTIONS_WINDOW_MIN_W, OPTIONS_WINDOW_MIN_H, OPTIONS_WINDOW_MAX_W, OPTIONS_WINDOW_MAX_H)
    else
        if win.SetMinResize then win:SetMinResize(OPTIONS_WINDOW_MIN_W, OPTIONS_WINDOW_MIN_H) end
        if win.SetMaxResize then win:SetMaxResize(OPTIONS_WINDOW_MAX_W, OPTIONS_WINDOW_MAX_H) end
    end

    local palette = GetAccentPalette()

    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    win._themeBg = bg

    win._themeEdges = {}
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local b = win:CreateTexture(nil, "BORDER")
        b:SetColorTexture(unpack(palette.accentEdge))
        win._themeEdges[#win._themeEdges + 1] = b
        if edge == "TOP" then
            b:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
            b:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
            b:SetHeight(1)
        elseif edge == "BOTTOM" then
            b:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
            b:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
            b:SetHeight(1)
        elseif edge == "LEFT" then
            b:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
            b:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
            b:SetWidth(1)
        else
            b:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
            b:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
            b:SetWidth(1)
        end
    end

    local titleBar = CreateFrame("Frame", nil, win)
    titleBar:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() win:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        OptionsPanel:SaveWindowState()
    end)
    local tbBg = titleBar:CreateTexture(nil, "ARTWORK")
    tbBg:SetAllPoints()
    tbBg:SetColorTexture(unpack(palette.surfaceDark))
    win._themeTitleBarBg = tbBg
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText((ns.displayName or addonName) .. " Options")
    title:SetTextColor(unpack(palette.header))
    win._themeTitle = title

    -- Boxed "X" close button matching the Accounting window header style.
    -- Frame level is bumped above the title bar -- otherwise the title bar
    -- (created earlier, same level, EnableMouse=true) swallows the clicks
    -- in its rectangle, including the close-button area.
    local closeBtn = CreateFrame("Button", nil, win, "BackdropTemplate")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -6, -6)
    closeBtn:SetFrameLevel((titleBar:GetFrameLevel() or win:GetFrameLevel()) + 5)
    closeBtn:Raise()
    local closeIdleBg = { palette.surfaceDark[1], palette.surfaceDark[2], palette.surfaceDark[3], 0.95 }
    if closeBtn.SetBackdrop then
        closeBtn:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
        })
        closeBtn:SetBackdropColor(unpack(closeIdleBg))
        closeBtn:SetBackdropBorderColor(palette.accentSoft[1], palette.accentSoft[2], palette.accentSoft[3], 0.55)
    end
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("X")
    closeText:SetTextColor(unpack(palette.header))
    closeBtn._themeText = closeText
    win._themeCloseBtn = closeBtn
    closeBtn:SetScript("OnClick", function() win:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        self._themeHover = true
        if OptionsPanel.ApplyWindowTheme then OptionsPanel:ApplyWindowTheme() end
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self._themeHover = false
        if OptionsPanel.ApplyWindowTheme then OptionsPanel:ApplyWindowTheme() end
    end)

    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
    -- L-shaped resize handle, same graphic style as the Accounting window.
    for _, dims in ipairs({ { 16, 3 }, { 3, 16 }, { 7, 7 } }) do
        local part = grip:CreateTexture(nil, "OVERLAY")
        part:SetTexture(WHITE_TEXTURE)
        part:SetSize(dims[1], dims[2])
        part:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
        part:SetVertexColor(palette.accentEdge[1], palette.accentEdge[2], palette.accentEdge[3], 0.85)
        grip._themeParts = grip._themeParts or {}
        grip._themeParts[#grip._themeParts + 1] = part
    end
    win._themeGrip = grip
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        OptionsPanel:SaveWindowState()
        if OptionsPanel.tabs and win.body then
            LayoutTabs(OptionsPanel.tabs, win.body:GetWidth())
        end
    end)

    -- Settings search bar lives between the title bar and the tab area.
    -- Typing filters every settings row across every page; hitting Esc /
    -- clearing the box restores the previously active tab. See
    -- OptionsPanel:SetSearch and the searchPage block in :Build.
    local searchBar = CreateFrame("Frame", nil, win)
    searchBar:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -32)
    searchBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -32)
    searchBar:SetHeight(24)
    local searchBg = searchBar:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(PaletteRGBA("surface", 0.85))
    win._themeSearchBg = searchBg
    local searchBorder = CreateTextureBorder(searchBar, 1)
    SetTextureBorderColor(searchBorder, PaletteRGBA("accentEdge", 0.85))
    win._themeSearchBorder = searchBorder

    local searchIcon = searchBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchIcon:SetPoint("LEFT", searchBar, "LEFT", 8, 0)
    searchIcon:SetText("Search")
    searchIcon:SetTextColor(PaletteRGBA("header"))
    win._themeSearchIcon = searchIcon

    local searchEdit = CreateFrame("EditBox", nil, searchBar)
    searchEdit:SetAutoFocus(false)
    searchEdit:SetFontObject("GameFontHighlightSmall")
    searchEdit:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    searchEdit:SetPoint("RIGHT", searchBar, "RIGHT", -28, 0)
    searchEdit:SetHeight(20)
    win._themeSearchEdit = searchEdit

    local clearBtn = CreateFrame("Button", nil, searchBar)
    clearBtn:SetSize(18, 18)
    clearBtn:SetPoint("RIGHT", searchBar, "RIGHT", -6, 0)
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearText:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearText:SetText("X")
    clearText:SetTextColor(PaletteRGBA("header"))
    clearBtn:Hide()
    win._themeSearchClear = clearBtn
    win._themeSearchClearText = clearText
    clearBtn:SetScript("OnClick", function()
        searchEdit:SetText("")
        searchEdit:ClearFocus()
        OptionsPanel:SetSearch("")
    end)

    -- 150ms debounce so each keystroke doesn't repopulate the result list.
    local pendingTimer
    searchEdit:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        if text ~= "" then
            clearBtn:Show()
        else
            clearBtn:Hide()
        end
        if pendingTimer then pendingTimer = nil end
        local token = {}
        pendingTimer = token
        C_Timer.After(0.15, function()
            if pendingTimer ~= token then return end
            pendingTimer = nil
            OptionsPanel:SetSearch(searchEdit:GetText() or "")
        end)
    end)
    searchEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        OptionsPanel:SetSearch("")
    end)
    searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win._themeSearchBar = searchBar

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -62)
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 8)
    win.body = body

    win:SetScript("OnSizeChanged", function()
        if OptionsPanel.tabs and win.body then
            LayoutTabs(OptionsPanel.tabs, win.body:GetWidth())
        end
        -- Resize hot path: only sync the CURRENTLY VISIBLE page's content
        -- width. Iterating all 9 pages here used to mark ~110 row anchors
        -- dirty per resize tick (60-144 Hz during drag), which is what made
        -- the Options window stutter while the Accounting window stayed
        -- smooth (it only has one active content frame).
        -- Hidden pages are re-synced when they become visible via the Show
        -- function inside :Build.
        local idx = OptionsPanel.activeIndex
        if idx and OptionsPanel.pages and OptionsPanel.pages[idx] and OptionsPanel.pages[idx].content then
            local scr = OptionsPanel.pages[idx]
            scr.content:SetWidth(math.max(120, scr:GetWidth()))
        end
        if OptionsPanel.searchPage and OptionsPanel.searchPage:IsShown()
            and OptionsPanel.searchPage.content then
            OptionsPanel.searchPage.content:SetWidth(math.max(120, OptionsPanel.searchPage:GetWidth()))
        end
    end)

    win:SetScript("OnShow", function()
        if not OptionsPanel.built then
            OptionsPanel:Build()
        end
        local active = type(OptionsPanel._currentSearch) == "string"
            and OptionsPanel._currentSearch ~= ""
        if active then
            -- Re-apply the previous search so the results page comes back
            -- exactly as the user left it (matches the EditBox content too).
            OptionsPanel:SetSearch(OptionsPanel._currentSearch)
        else
            local idx = OptionsPanel.activeIndex or 1
            if OptionsPanel.showTabFn then
                OptionsPanel.showTabFn(idx)
            end
        end
        OptionsPanel:Refresh()
        C_Timer.After(0, function()
            if OptionsPanel.tabs and OptionsPanel.window and OptionsPanel.window.body then
                LayoutTabs(OptionsPanel.tabs, OptionsPanel.window.body:GetWidth())
            end
        end)
    end)

    self.window = win
    self:RestoreWindowState()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ThyraxUtilOptionsWindow")
    end
    return win
end

function OptionsPanel:Build()
    if self.built then return end

    self:EnsureWindow()
    if self.contentRoot then self.contentRoot:Hide() end

    local body = self.window.body
    local root = CreateFrame("Frame", nil, body)
    root:SetAllPoints(body)
    self.contentRoot = root

    local tabBar = CreateFrame("Frame", nil, root)
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(TAB_HEIGHT)
    local div = tabBar:CreateTexture(nil, "BORDER")
    div:SetPoint("BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", 0, 0)
    div:SetHeight(1)
    local p = GetTabPalette()
    div:SetColorTexture(unpack(p.divider))
    self.tabDivider = div

    local pageHost = CreateFrame("Frame", nil, root)
    pageHost:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    pageHost:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)

    local DEFS = {
        { label = "General", builder = BuildGeneralPage },
        { label = "Crosshair", builder = BuildCrosshairPage },
        { label = "Mouse", builder = BuildMousePage },
        { label = "Darkness", builder = BuildDarknessPage },
        { label = "Quest Hotkey", builder = BuildQuestAcceptHotkeyPage },
        { label = "Flight", builder = BuildFlightTrackerPage },
        { label = "AH Filters", builder = BuildAuctionFilterPersistPage },
        { label = "Accounting", builder = BuildAccountingTrackerPage },
        { label = "Character", builder = BuildCharacterPanelPage },
    }
    self.tabs = {}
    self.pages = {}
    self.refreshFns = {}
    local function Show(idx)
        for i, s in ipairs(self.pages) do
            if i == idx then
                s:Show()
                -- Catch up on any window-width changes that happened while
                -- this page was hidden. The OnSizeChanged hot path only
                -- updates the visible page; the rest sync here on show.
                if s.content then
                    s.content:SetWidth(math.max(120, s:GetWidth()))
                end
            else
                s:Hide()
            end
        end
        for i, t in ipairs(self.tabs) do t:SetActive(i == idx) end
        self.activeIndex = idx
        -- Lazy refresh: while this page was hidden, settings changes only
        -- ran the previously-active page's refresh fn. Catch up now so the
        -- widgets reflect current values.
        if self._dirtyPages and self._dirtyPages[idx] and self.refreshFns and self.refreshFns[idx] then
            self.refreshing = true
            pcall(self.refreshFns[idx])
            self.refreshing = false
            self._dirtyPages[idx] = nil
        end
    end

    for i, d in ipairs(DEFS) do
        local scr, cont = CreateScrollPage(pageHost)
        scr:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, 0)
        scr:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", -22, 0)
        cont:SetWidth(math.max(120, scr:GetWidth()))
        -- Open a search context so every CreateRow / CreateHeader invoked by
        -- the builder is stamped with this page's index + label. Closed below
        -- so action buttons or post-loop helpers don't pollute the index.
        currentSearchContext = { pageIndex = i, pageLabel = d.label, header = "" }
        local _, r = d.builder(cont)
        currentSearchContext = nil
        -- Dynamic page height from the layout cursor -- no wasted scroll space.
        cont:SetHeight(math.max(60, -currentYOffset + 20))
        scr.content = cont
        self.pages[i] = scr
        self.refreshFns[i] = r
        self.tabs[i] = CreateTabButton(tabBar, d.label, i, #DEFS, Show)
    end

    -- Search results page: a sibling scroll page that displays the filtered
    -- entries from searchIndex. Stays hidden until OptionsPanel:SetSearch
    -- receives a non-empty needle.
    local searchScr, searchCont = CreateScrollPage(pageHost)
    searchScr:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, 0)
    searchScr:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", -22, 0)
    searchCont:SetWidth(math.max(120, searchScr:GetWidth()))
    searchScr.content = searchCont
    searchScr._resultRows = {}
    self.searchPage = searchScr

    self.tabBar = tabBar
    self.bodyFrame = pageHost
    self.showTabFn = Show
    self.built = true
    self:Refresh()
    self:ApplyWindowTheme()
end

function OptionsPanel:Rebuild()
    self.built = false
    self.tabs = nil
    self.pages = nil
    self.refreshFns = nil
    self.searchPage = nil
    -- Drop the dirty-page bitmap too: refresh fns are about to be replaced
    -- with new ones, so flagged indices on the old set are meaningless.
    self._dirtyPages = nil
    -- Wipe the search index so the next Build() starts with fresh entries
    -- (avoids duplicated entries from previously built pages).
    for k in pairs(searchIndex) do searchIndex[k] = nil end
    -- Same for the themed-widget repaint registry: the closures we registered
    -- last time reference the now-orphaned widgets. Drop them so the new
    -- Build() can populate from scratch.
    for k in pairs(themedRepaintFns) do themedRepaintFns[k] = nil end
    local activeIndex = self.activeIndex or 1
    self:Build()
    if self.showTabFn then self.showTabFn(activeIndex) end
    self:Refresh()
    self:ApplyWindowTheme()
end

-- Re-tint every widget that baked an accent / header / surface color into
-- itself at creation time. Use this on accent / custom-font changes instead
-- of Rebuild: zero new frames allocated, so the memory floor doesn't climb
-- per colour-picking session. ApplyWindowTheme handles the window chrome +
-- tabs + scrollbars separately; RepaintThemedWidgets covers the widgets
-- inside the pages.
function OptionsPanel:RepaintThemedWidgets()
    for _, fn in ipairs(themedRepaintFns) do pcall(fn) end
    self:ApplyWindowTheme()
    -- Some widgets (the per-module CreateThemeColorRow "Default / Custom"
    -- badge in particular) only re-pull the palette via SetValue paths.
    -- Calling Refresh re-runs those without rebuilding anything. Cheap now
    -- that Refresh only touches the active page.
    if self.refreshFns then self:Refresh() end
end

-- WoW frames cannot be destroyed once created, so every Rebuild leaves the
-- old page frames orphaned in memory (~1 MB per rebuild for this panel).
-- The Blizzard ColorPicker fires its swatch callback on EVERY cursor move
-- while the user drags the hue / saturation sliders, which used to trigger
-- dozens of Rebuilds in a single colour-picking session.
-- RequestRebuild debounces: the most recent request wins, and only one
-- Rebuild runs after the user stops interacting for `delay` seconds.
-- Used for genuine rebuilds (theme switch); accent / font colour changes
-- should call RepaintThemedWidgets instead.
function OptionsPanel:RequestRebuild(delay)
    delay = tonumber(delay) or 0.20
    self._rebuildToken = (self._rebuildToken or 0) + 1
    local token = self._rebuildToken
    C_Timer.After(delay, function()
        if OptionsPanel._rebuildToken == token then
            OptionsPanel:Rebuild()
        end
    end)
end

function OptionsPanel:Refresh()
    if not self.refreshFns then return end
    self.refreshing = true
    -- Only refresh the VISIBLE page. The other 8 page refresh functions
    -- would otherwise pump ~110 SetValue() calls into hidden widgets on
    -- every single settings change (the slider debounce alone fires this
    -- ~12x per second while a slider is being dragged). Hidden pages are
    -- marked dirty so the next showTabFn() catches them up.
    self._dirtyPages = self._dirtyPages or {}
    local activeIdx = self.activeIndex
    if type(activeIdx) ~= "number" then activeIdx = 1 end
    for i, fn in ipairs(self.refreshFns) do
        if i == activeIdx then
            pcall(fn)
            self._dirtyPages[i] = nil
        else
            self._dirtyPages[i] = true
        end
    end
    self.refreshing = false
    local g = ns.Settings:IsGlobalEnabled()
    local searchActive = type(self._currentSearch) == "string" and self._currentSearch ~= ""
    for i, t in ipairs(self.tabs) do
        local m = TAB_MODULE_MAP[i]
        if searchActive then
            -- While a search is being shown, no tab is the active tab.
            t:Hide()
        elseif m == nil then
            t:Show()
        else
            local status = ns.ModuleRegistry.GetModuleStatus and ns.ModuleRegistry:GetModuleStatus(m)
            if status and status.available == false then
                t:Hide()
            elseif ns.ModuleRegistry:GetModule(m) and g and ns.Settings:IsModuleEnabled(m) then
                t:Show()
            else
                t:Hide()
            end
        end
    end
    LayoutTabs(self.tabs, (self.window and self.window.body and self.window.body:GetWidth()) or 1)
    -- Keep the search results page visible across Refresh calls (Refresh can
    -- fire from OnShow / value-change paths and would otherwise re-show the
    -- last active tab via :Open's caller).
    if searchActive and self.searchPage then
        for _, scr in ipairs(self.pages or {}) do scr:Hide() end
        self.searchPage:Show()
    elseif self.searchPage then
        self.searchPage:Hide()
    end
    self:ApplyWindowTheme()
end

-- Reusable container for one search result row. Built lazily and stored in
-- searchPage._resultRows so successive searches reuse frames instead of
-- allocating new ones every keystroke.
local function EnsureSearchResultRow(searchPage, index)
    local rows = searchPage._resultRows
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, searchPage.content)
    row:SetHeight(24)
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(1, 1, 1, 0.03)
    row._bg = rowBg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(PaletteRGBA("accentSoft", 0.20))

    local badge = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", row, "LEFT", 10, 0)
    badge:SetJustifyH("LEFT")
    badge:SetWidth(140)
    badge:SetWordWrap(false)
    row.badge = badge

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", badge, "RIGHT", 12, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local section = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    section:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    section:SetJustifyH("RIGHT")
    section:SetWordWrap(false)
    row.section = section

    -- Right-edge cap for the label so a long label doesn't overlap the
    -- section column on the right.
    label:SetPoint("RIGHT", section, "LEFT", -10, 0)

    rows[index] = row
    return row
end

function OptionsPanel:RenderSearchResults(needle)
    local page = self.searchPage
    if not page or type(needle) ~= "string" or needle == "" then return end
    local content = page.content
    local matches = {}
    for _, entry in ipairs(searchIndex) do
        local labelLower = string.lower(entry.label or "")
        local tipLower = string.lower(entry.tooltip or "")
        local headerLower = string.lower(entry.headerLabel or "")
        if labelLower:find(needle, 1, true)
            or tipLower:find(needle, 1, true)
            or headerLower:find(needle, 1, true) then
            matches[#matches + 1] = entry
        end
    end

    local y = -8
    for i, entry in ipairs(matches) do
        local row = EnsureSearchResultRow(page, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, y)
        row.badge:SetText("[" .. (entry.pageLabel or "") .. "]")
        row.badge:SetTextColor(PaletteRGBA("header"))
        row.label:SetText(entry.label or "")
        row.label:SetTextColor(1, 1, 1, 1)
        row.section:SetText(entry.headerLabel or "")
        -- Respect the custom font secondary if the user enabled it; otherwise
        -- fall back to a dim accent tone so the section tag stays subtle.
        local p = GetAccentPalette()
        local soft = p.headerSoft or p.accentSoft
        row.section:SetTextColor(soft[1], soft[2], soft[3], soft[4] or 1)
        row:SetScript("OnClick", function()
            local win = OptionsPanel.window
            if win and win._themeSearchEdit then
                win._themeSearchEdit:SetText("")
                win._themeSearchEdit:ClearFocus()
                if win._themeSearchClear then win._themeSearchClear:Hide() end
            end
            OptionsPanel:SetSearch("")
            if entry.pageIndex and OptionsPanel.showTabFn then
                OptionsPanel.activeIndex = entry.pageIndex
                OptionsPanel.showTabFn(entry.pageIndex)
                -- Defer scroll + highlight by one frame so the page has time
                -- to lay itself out after Show; otherwise GetTop() returns
                -- pre-show coordinates and the scroll math goes wrong.
                if entry.row then
                    C_Timer.After(0, function()
                        OptionsPanel:ScrollToSearchResult(entry.pageIndex, entry.row)
                    end)
                end
            end
        end)
        row:Show()
        y = y - 26
    end

    for i = #matches + 1, #page._resultRows do
        if page._resultRows[i] then page._resultRows[i]:Hide() end
    end

    if not page._emptyMsg then
        local m = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        m:SetPoint("TOP", content, "TOP", 0, -20)
        page._emptyMsg = m
    end
    if #matches == 0 then
        page._emptyMsg:SetText("No settings match \"" .. (self._currentSearch or "") .. "\"")
        page._emptyMsg:Show()
        content:SetHeight(60)
    else
        page._emptyMsg:Hide()
        content:SetHeight(math.max(60, -y + 8))
    end
end

-- Scrolls the destination page so the search-target row is in view, and
-- flashes the row background with the accent color so the eye lands on it
-- immediately. Safe to call with stale references: every step is guarded.
function OptionsPanel:ScrollToSearchResult(pageIndex, row)
    if not (self.pages and self.pages[pageIndex] and row) then return end
    local scroll = self.pages[pageIndex]
    local content = scroll.content
    if not content or not row.GetTop then return end

    -- Compute pixel offset of the row's top edge inside the content frame.
    local contentTop = content:GetTop()
    local rowTop = row:GetTop()
    if contentTop and rowTop then
        local offset = contentTop - rowTop - 20
        if offset < 0 then offset = 0 end
        local range = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
        if offset > range then offset = range end
        if scroll.SetVerticalScroll then scroll:SetVerticalScroll(offset) end
    end

    -- Flash highlight: lay a transparent accent overlay over the row, then
    -- fade it out after ~1.6 s. Re-uses a single texture per row.
    if not row._searchFlash and row.CreateTexture then
        row._searchFlash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row._searchFlash:SetAllPoints()
    end
    if row._searchFlash then
        local palette = GetAccentPalette()
        row._searchFlash:SetColorTexture(palette.accent[1], palette.accent[2], palette.accent[3], 0.35)
        row._searchFlash:Show()
        -- Token guards against successive searches resetting the same row:
        -- only the most recent fade callback actually hides the overlay.
        row._searchFlashToken = (row._searchFlashToken or 0) + 1
        local token = row._searchFlashToken
        C_Timer.After(1.6, function()
            if row._searchFlash and row._searchFlashToken == token then
                row._searchFlash:Hide()
            end
        end)
    end
end

function OptionsPanel:SetSearch(needle)
    if type(needle) ~= "string" then needle = "" end
    needle = string.lower(needle)
    needle = needle:gsub("^%s+", ""):gsub("%s+$", "")
    self._currentSearch = needle
    if not self.built then return end

    if needle == "" then
        -- Restore: hide search page, run Refresh to re-evaluate which tabs /
        -- pages should be visible, then re-show the last active page.
        if self.searchPage then self.searchPage:Hide() end
        self:Refresh()
        local idx = self.activeIndex or 1
        if self.showTabFn then self.showTabFn(idx) end
        return
    end

    -- Hide every regular page + deactivate every tab indicator while the
    -- search results are shown.
    if self.pages then
        for _, s in ipairs(self.pages) do s:Hide() end
    end
    if self.tabs then
        for _, t in ipairs(self.tabs) do
            if t.SetActive then t:SetActive(false) end
            t:Hide()
        end
    end
    self:RenderSearchResults(needle)
    if self.searchPage then self.searchPage:Show() end
end

function OptionsPanel:SelectModuleTab(moduleID)
    local index = GetTabIndexForModule(moduleID)
    if not index then return false end
    self.activeIndex = index
    if self.showTabFn then
        self.showTabFn(index)
    end
    return true
end

function OptionsPanel:Initialize()
    if self.initialized then return end
    local p = CreateFrame("Frame")
    p.name = ns.displayName or addonName

    -- Blizzard's AddOn-settings entry is only a redirect ("Weiche"): the real
    -- options live in a standalone, movable window (OptionsPanel:EnsureWindow).
    local redirectDesc = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    redirectDesc:SetPoint("TOPLEFT", 24, -40)
    redirectDesc:SetWidth(520)
    redirectDesc:SetJustifyH("LEFT")
    redirectDesc:SetText("ThyraxUtil options open in their own movable, resizable window so they can stay open next to other frames.")
    local redirectBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    redirectBtn:SetSize(240, 28)
    redirectBtn:SetPoint("TOPLEFT", redirectDesc, "BOTTOMLEFT", 0, -16)
    redirectBtn:SetText("Open ThyraxUtil Options")
    redirectBtn:SetScript("OnClick", function() OptionsPanel:Open() end)
    
    -- Ensure we build when shown
    p:SetScript("OnShow", function()
        if not self.built then
            self:Build()
        end
        
        local targetIndex = self.pendingOpenIndex or self.activeIndex or 1
        self.pendingOpenIndex = nil

        if self.showTabFn then 
            self.showTabFn(targetIndex)
        end
        
        self:Refresh()

        -- WoW's Settings canvas may not have applied final panel dimensions
        -- yet when OnShow fires, causing LayoutTabs to size tabs to zero.
        -- Re-layout on the next few frames once the panel is fully sized.
        C_Timer.After(0, function()
            if self.tabs and self.panel then
                LayoutTabs(self.tabs, self.panel:GetWidth())
            end
        end)
        C_Timer.After(0.1, function()
            if self.tabs and self.panel then
                LayoutTabs(self.tabs, self.panel:GetWidth())
            end
        end)
    end)
    
    self.panel = p
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local c = Settings.RegisterCanvasLayoutCategory(p, p.name)
        Settings.RegisterAddOnCategory(c)
        self.category = c
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
    self.initialized = true
end

function OptionsPanel:Open(moduleID)
    self:EnsureWindow()
    if not self.built then
        self:Build()
    end
    local targetIndex = GetTabIndexForModule(moduleID)
    if targetIndex then
        -- Caller explicitly asked for a module tab; clear any active search
        -- so they actually land on the requested tab.
        if self.window and self.window._themeSearchEdit then
            self.window._themeSearchEdit:SetText("")
            self.window._themeSearchEdit:ClearFocus()
            if self.window._themeSearchClear then self.window._themeSearchClear:Hide() end
        end
        self:SetSearch("")
        self.activeIndex = targetIndex
        if self.showTabFn then
            self.showTabFn(targetIndex)
        end
    end
    self.window:Show()
    self.window:Raise()
    return true
end

-- [[ END_MAIN ]]
