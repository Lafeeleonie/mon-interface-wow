local _, ns = ...

ns.Onboarding = ns.Onboarding or {}
local Onboarding = ns.Onboarding

local hasEnteredWorld = false
local earlyEventFrame = CreateFrame("Frame")
earlyEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
earlyEventFrame:SetScript("OnEvent", function()
    hasEnteredWorld = true
end)

local FRAME_WIDTH     = 800
local FRAME_HEIGHT    = 500
local ROW_HEIGHT      = 64
local ROW_GAP         = 8
local PADDING         = 16
local CURRENT_VERSION = (ns.Compat and ns.Compat.GetAddOnVersion and ns.Compat.GetAddOnVersion(ns.addonName)) or "0.0.0"

local DEFAULT_ACCENT_PALETTE = {
    accent      = { 0.95, 0.78, 0.30, 1 },
    accentSoft  = { 0.72, 0.62, 0.28, 1 },
    accentEdge  = { 0.55, 0.45, 0.18, 0.90 },
    surface     = { 0.18, 0.13, 0.07, 0.95 },
    surfaceDark = { 0.14, 0.11, 0.05, 1 },
    header      = { 1.00, 0.82, 0.30, 1 },
}

local ACCENT_OPTIONS = {
    { value = "Gold",   label = "Gold" },
    { value = "Silver", label = "Silver" },
    { value = "Blue",   label = "Blue" },
    { value = "Green",  label = "Green" },
    { value = "Red",    label = "Red" },
    { value = "Purple", label = "Purple" },
    { value = "Teal",   label = "Teal" },
}

Onboarding.ACCENT_OPTIONS = ACCENT_OPTIONS

local function GetOnboardingData()
    if ns.Settings and ns.Settings.GetOnboardingData then
        return ns.Settings:GetOnboardingData()
    end
    return { seenModules = {} }
end

local function IsModernTheme()
    return ns.UI and ns.UI.GetTheme and ns.UI:GetTheme() == "Modern"
end

local function GetAccentPalette()
    if ns.UI and ns.UI.GetAccentPalette then
        return ns.UI:GetAccentPalette() or DEFAULT_ACCENT_PALETTE
    end
    return DEFAULT_ACCENT_PALETTE
end

local function GetAccentPreset()
    if ns.UI and ns.UI.GetAccentPreset then
        return ns.UI:GetAccentPreset() or "Gold"
    end
    if ns.Settings and ns.Settings.GetAccentPreset then
        return ns.Settings:GetAccentPreset() or "Gold"
    end
    return "Gold"
end

local function SetAccentPreset(value)
    if ns.UI and ns.UI.SetAccentPreset then
        ns.UI:SetAccentPreset(value)
    elseif ns.Settings and ns.Settings.SetAccentPreset then
        ns.Settings:SetAccentPreset(value)
    end
end

local function SetTextureColor(texture, color, alpha)
    if not texture or type(color) ~= "table" then return end
    texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, alpha or color[4] or 1)
end

local function GetPresetPalette(value)
    local presets = ns.UI and ns.UI.ACCENT_PRESETS
    return (presets and presets[value]) or DEFAULT_ACCENT_PALETTE
end

local function GetModuleSubtitle(module)
    if type(module.subtitle) == "string" and module.subtitle ~= "" then
        return module.subtitle
    end
    if type(module.onboardingDescription) == "string" and module.onboardingDescription ~= "" then
        return module.onboardingDescription
    end
    return "Enable this module to use its feature."
end

local function CreateThemeCheckbox(parent)
    if not IsModernTheme() then
        -- Classic: use native WoW CheckButton so it matches the rest of the WoW UI
        local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        checkbox:SetSize(26, 26)
        local orig = checkbox.SetChecked
        function checkbox:SetChecked(checked)
            orig(self, checked and true or false)
        end

        function checkbox:RefreshVisual() end -- WoW handles native appearance

        checkbox:SetScript("OnClick", function(self) self:RefreshVisual() end)
        checkbox:SetChecked(false)
        return checkbox
    end

    -- Modern: custom accent toggle switch
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetSize(44, 24)

    local bg = checkbox:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(checkbox)
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)

    local knob = checkbox:CreateTexture(nil, "ARTWORK")
    knob:SetSize(20, 20)
    knob:SetPoint("LEFT", checkbox, "LEFT", 2, 0)
    knob:SetColorTexture(1, 1, 1, 1)

    local isChecked = false

    function checkbox:RefreshVisual()
        local palette = GetAccentPalette()
        if isChecked then
            SetTextureColor(bg, palette.accentSoft or palette.accent, 1)
            knob:ClearAllPoints()
            knob:SetPoint("RIGHT", checkbox, "RIGHT", -2, 0)
        else
            SetTextureColor(bg, palette.surface or palette.surfaceDark, 0.95)
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", checkbox, "LEFT", 2, 0)
        end
    end

    function checkbox:GetChecked()
        return isChecked
    end

    function checkbox:SetChecked(checked)
        isChecked = checked and true or false
        self:RefreshVisual()
    end

    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(not isChecked)
    end)

    checkbox:SetChecked(false)
    return checkbox
end

function Onboarding:CollectUnseenModules()
    local unseen = {}
    if not ns.ModuleRegistry or not ns.ModuleRegistry.GetModuleIDs then
        return unseen
    end

    if ns.Settings and ns.Settings.IsNeverShowOnboarding and ns.Settings:IsNeverShowOnboarding() then
        return unseen
    end

    local onboarding = GetOnboardingData()
    local seen = onboarding.seenModules or {}
    local moduleIDs = ns.ModuleRegistry:GetModuleIDs()

    -- Onboarding is strictly once-per-module-per-user. A module version bump
    -- must NOT re-open onboarding for an already-seen module. The NEW badge
    -- (see CreateRow) still uses module.version for the rare case a new
    -- module ships alongside an existing install and ends up in this list.
    for _, moduleID in ipairs(moduleIDs) do
        local status = ns.ModuleRegistry.GetModuleStatus and ns.ModuleRegistry:GetModuleStatus(moduleID)
        if not (status and status.available == false) then
            local module = ns.ModuleRegistry:GetModule(moduleID)
            if module and not seen[moduleID] then
                unseen[#unseen + 1] = module
            end
        end
    end

    return unseen
end

function Onboarding:CollectAllModules()
    local modules = {}
    if not ns.ModuleRegistry or not ns.ModuleRegistry.GetModuleIDs then
        return modules
    end

    for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
        local module = ns.ModuleRegistry:GetModule(moduleID)
        if module then
            modules[#modules + 1] = module
        end
    end

    return modules
end

function Onboarding:HideModuleTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

function Onboarding:ShowInlinePreview(module)
    if not self.previewTex or not self.previewPlaceholder then return end

    if module and module.previewTexture and module.previewTexture ~= "" then
        self.previewTex:SetTexture(module.previewTexture)
        self.previewTex:Show()
        self.previewPlaceholder:Hide()
    else
        self.previewTex:Hide()
        if module then
            self.previewPlaceholder:SetText("No preview available for\n" .. (module.name or module.id))
        else
            self.previewPlaceholder:SetText("Hover over a feature to see its preview")
        end
        self.previewPlaceholder:Show()
    end
end

function Onboarding:ShowModuleTooltip(anchor, module)
    if not GameTooltip or not anchor then return end

    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText(module.name or module.id or "Module", 1, 0.82, 0)
    GameTooltip:AddLine(GetModuleSubtitle(module), 0.92, 0.92, 0.92, true)
    GameTooltip:AddLine("\n" .. (module.onboardingDescription or ""), 1, 1, 1, true)
    GameTooltip:Show()
end

function Onboarding:CreateRow(parent, module, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, -((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING, -((index - 1) * (ROW_HEIGHT + ROW_GAP)))

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(row)
    end

    local onboarding = GetOnboardingData()
    local lastSeenVersion = onboarding.lastSeenVersion or "0.0.0"
    local isNew = module.version and module.version > lastSeenVersion

    if isNew then
        local palette = GetAccentPalette()
        local badgeColor = palette.header or palette.accent
        local borderColor = palette.accentSoft or palette.accent
        local newBadge = row:CreateTexture(nil, "OVERLAY")
        newBadge:SetSize(32, 16)
        newBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
        newBadge:SetTexture("Interface\\Buttons\\WHITE8x8")
        newBadge:SetVertexColor(badgeColor[1], badgeColor[2], badgeColor[3], 0.9)

        local newText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        newText:SetPoint("CENTER", newBadge, "CENTER", 0, 0)
        newText:SetText("NEW")
        newText:SetTextColor(0, 0, 0, 1)

        local border = row:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 0.3)
    end

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetTexture("Interface\\Buttons\\WHITE8x8")
    hover:SetVertexColor(0.35, 0.62, 1.0, 0)

    row:SetScript("OnEnter", function()
        if IsModernTheme() then
            local palette = GetAccentPalette()
            local color = palette.header or palette.accent
            hover:SetVertexColor(color[1], color[2], color[3], 0.12)
        else
            hover:SetVertexColor(0.35, 0.62, 1.0, 0.12)
        end
        self:ShowInlinePreview(module)
        self:ShowModuleTooltip(row, module)
    end)
    row:SetScript("OnLeave", function()
        hover:SetVertexColor(0.35, 0.62, 1.0, 0)
        self:HideModuleTooltip()
    end)

    local checkbox = CreateThemeCheckbox(row)
    checkbox:SetPoint("LEFT", row, "LEFT", 12, 0)
    checkbox:SetChecked(ns.Settings:IsModuleEnabled(module.id))

    local title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", row, "LEFT", 64, 1)
    title:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    title:SetJustifyH("LEFT")
    title:SetText(module.name or module.id)

    local subtitle = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", row, "LEFT", 64, -1)
    subtitle:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(GetModuleSubtitle(module))
    subtitle:SetTextColor(0.74, 0.74, 0.74, 1)

    row:SetScript("OnClick", function()
        checkbox:SetChecked(not checkbox:GetChecked())
    end)

    return { row = row, module = module, checkbox = checkbox }
end

function Onboarding:Populate(modules)
    self.currentModules = modules
    self.rows = self.rows or {}

    for _, rowData in ipairs(self.rows) do
        rowData.row:Hide()
        rowData.row:SetParent(nil)
    end
    for index = #self.rows, 1, -1 do
        self.rows[index] = nil
    end

    for index, module in ipairs(modules) do
        self.rows[index] = self:CreateRow(self.listContent, module, index)
    end

    local totalRows = #modules
    local height = math.max((totalRows * ROW_HEIGHT) + math.max(totalRows - 1, 0) * ROW_GAP, 10)
    self.listContent:SetHeight(height)
end

function Onboarding:RefreshAccentControls()
    local activePalette = GetAccentPalette()
    local selected = GetAccentPreset()

    if self.accentLabel then
        if IsModernTheme() then
            local header = activePalette.header or activePalette.accent
            self.accentLabel:SetTextColor(header[1], header[2], header[3], 1)
        else
            self.accentLabel:SetTextColor(1, 1, 1, 1)
        end
    end

    for _, button in ipairs(self.accentButtons or {}) do
        local presetPalette = GetPresetPalette(button._accentValue)
        local fill = presetPalette.accent or presetPalette.header or DEFAULT_ACCENT_PALETTE.accent
        SetTextureColor(button._swatch, fill, 1)

        if button.SetBackdropColor then
            local surface = activePalette.surfaceDark or activePalette.surface or DEFAULT_ACCENT_PALETTE.surfaceDark
            button:SetBackdropColor(surface[1], surface[2], surface[3], 0.45)
        end

        if button.SetBackdropBorderColor then
            if button._accentValue == selected then
                local edge = activePalette.header or activePalette.accent or fill
                button:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            else
                local edge = presetPalette.accentEdge or presetPalette.accentSoft or fill
                button:SetBackdropBorderColor(edge[1], edge[2], edge[3], 0.58)
            end
        end
    end

    if self.updateThemeToggle then
        self.updateThemeToggle()
    end
end

function Onboarding:RefreshTheme()
    local palette = GetAccentPalette()
    if self.titleText then
        if IsModernTheme() then
            local header = palette.header or palette.accent
            self.titleText:SetTextColor(header[1], header[2], header[3], 1)
        else
            self.titleText:SetTextColor(1, 1, 1, 1)
        end
    end
    if self.subtitleText then
        if IsModernTheme() then
            self.subtitleText:SetTextColor(0.80, 0.80, 0.80, 1)
        else
            self.subtitleText:SetTextColor(0.72, 0.72, 0.76, 1)
        end
    end
    if self.titleDivider then
        if IsModernTheme() then
            local edge = palette.accentSoft or palette.accent
            self.titleDivider:SetColorTexture(edge[1], edge[2], edge[3], 0.55)
        else
            self.titleDivider:SetColorTexture(0.45, 0.45, 0.50, 0.70)
        end
    end
    if self.neverShowCheckbox then
        local checked = self.neverShowCheckbox:GetChecked()
        -- Re-create or refresh the checkbox frame to match the theme
        local parent = self.neverShowCheckbox:GetParent()
        local point, rel, relPoint, x, y = self.neverShowCheckbox:GetPoint()

        self.neverShowCheckbox:Hide()
        self.neverShowCheckbox:SetParent(nil)

        local newCheckbox = CreateThemeCheckbox(parent)
        newCheckbox:SetPoint(point, rel, relPoint, x, y)
        newCheckbox:SetChecked(checked)
        self.neverShowCheckbox = newCheckbox

        if self.neverShowText then
            self.neverShowText:ClearAllPoints()
            self.neverShowText:SetPoint("LEFT", newCheckbox, "RIGHT", 6, 0)
        end
    end
    if self.previewPlaceholder then
        if IsModernTheme() then
            self.previewPlaceholder:SetTextColor(0.50, 0.50, 0.50, 1)
        else
            self.previewPlaceholder:SetTextColor(0.60, 0.60, 0.62, 1)
        end
    end
    if self.neverShowText then
        if IsModernTheme() then
            self.neverShowText:SetTextColor(0.80, 0.80, 0.80, 1)
        else
            self.neverShowText:SetTextColor(1, 1, 1, 1)
        end
    end
    self:RefreshAccentControls()
    -- Rebuild rows so checkboxes use the correct template for the active theme
    if self.currentModules then
        self:Populate(self.currentModules)
    end
end

function Onboarding:BuildFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ThyraxUtilOnboardingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(200)
    frame:Hide()
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then Onboarding:AcceptSelections() end
    end)

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(frame)
    end

    -- Title
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -PADDING)
    title:SetText("Welcome to ThyraxUtil")
    if IsModernTheme() then
        local palette = GetAccentPalette()
        local header = palette.header or palette.accent
        title:SetTextColor(header[1], header[2], header[3], 1)
    else
        title:SetTextColor(1, 1, 1, 1)
    end
    self.titleText = title

    -- Subtitle
    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetPoint("LEFT", frame, "LEFT", PADDING, 0)
    subtitle:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetText("Choose which modules should be active. You can change this later via /thyrax options.")
    if IsModernTheme() then
        subtitle:SetTextColor(0.80, 0.80, 0.80, 1)
    else
        subtitle:SetTextColor(0.72, 0.72, 0.76, 1)
    end
    self.subtitleText = subtitle

    -- Divider line under header
    local titleDivider = frame:CreateTexture(nil, "BORDER")
    titleDivider:SetHeight(1)
    titleDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -76)
    titleDivider:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    if IsModernTheme() then
        local palette = GetAccentPalette()
        local edge = palette.accentSoft or palette.accent
        titleDivider:SetColorTexture(edge[1], edge[2], edge[3], 0.55)
    else
        titleDivider:SetColorTexture(0.45, 0.45, 0.50, 0.70)
    end
    self.titleDivider = titleDivider

    -- Theme Toggle
    local themeBtn = CreateFrame("Button", nil, frame)
    themeBtn:SetSize(40, 20)

    local themeBg = themeBtn:CreateTexture(nil, "BACKGROUND")
    themeBg:SetAllPoints()
    themeBg:SetColorTexture(0.2, 0.2, 0.2, 1)

    local themeKnob = themeBtn:CreateTexture(nil, "ARTWORK")
    themeKnob:SetSize(16, 16)
    themeKnob:SetPoint("LEFT", themeBtn, "LEFT", 2, 0)
    themeKnob:SetColorTexture(1, 1, 1, 1)

    local themeLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    themeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -52)
    themeLabel:SetText("Modern UI:")

    themeBtn:SetPoint("LEFT", themeLabel, "RIGHT", 8, 0)

    local function UpdateThemeToggle()
        local palette = GetAccentPalette()
        if IsModernTheme() then
            SetTextureColor(themeBg, palette.accentSoft or palette.accent, 1)
            themeKnob:ClearAllPoints()
            themeKnob:SetPoint("RIGHT", themeBtn, "RIGHT", -2, 0)
        else
            SetTextureColor(themeBg, palette.surface or palette.surfaceDark, 0.95)
            themeKnob:ClearAllPoints()
            themeKnob:SetPoint("LEFT", themeBtn, "LEFT", 2, 0)
        end
    end

    self.updateThemeToggle = UpdateThemeToggle
    UpdateThemeToggle()

    -- Accent selection
    local accentLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    accentLabel:SetPoint("LEFT", themeBtn, "RIGHT", 24, 0)
    accentLabel:SetText("Accent:")
    self.accentLabel = accentLabel
    self.accentButtons = {}

    local previousAccentButton
    for _, option in ipairs(ACCENT_OPTIONS) do
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetSize(22, 22)
        button._accentValue = option.value
        button._accentLabel = option.label

        if previousAccentButton then
            button:SetPoint("LEFT", previousAccentButton, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", accentLabel, "RIGHT", 8, 0)
        end

        if button.SetBackdrop then
            button:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
        end

        local swatch = button:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        button._swatch = swatch

        button:SetScript("OnClick", function()
            SetAccentPreset(option.value)
            if ns.UI and ns.UI.ApplyTheme then
                ns.UI:ApplyTheme(frame)
                if Onboarding.previewPanel then
                    ns.UI:ApplyTheme(Onboarding.previewPanel)
                end
            end
            Onboarding:RefreshTheme()
        end)

        button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Accent: " .. option.label, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        self.accentButtons[#self.accentButtons + 1] = button
        previousAccentButton = button
    end

    themeBtn:SetScript("OnClick", function()
        local newTheme = IsModernTheme() and "Classic" or "Modern"
        if ns.UI and ns.UI.SetTheme then
            ns.UI:SetTheme(newTheme)
        end
        if ns.Settings and ns.Settings.SetTheme then
            ns.Settings:SetTheme(newTheme)
        end
        UpdateThemeToggle()

        -- Reapply backdrop/border to all registered frames
        if ns.UI and ns.UI.ApplyTheme then
            ns.UI:ApplyTheme(frame)
            if Onboarding.previewPanel then
                ns.UI:ApplyTheme(Onboarding.previewPanel)
            end
        end

        -- Refresh per-theme colors and rebuild rows with correct checkbox style
        Onboarding:RefreshTheme()
    end)

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        Onboarding:AcceptSelections()
    end)

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -86)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 400, 58)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetWidth(360)
    content:SetHeight(10)
    scroll:SetScrollChild(content)

    -- Preview panel
    local previewPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewPanel:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 24, 0)
    previewPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 58)

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(previewPanel)
    end

    local previewTex = previewPanel:CreateTexture(nil, "ARTWORK")
    previewTex:SetPoint("CENTER", previewPanel, "CENTER", 0, 0)
    previewTex:SetSize(320, 320)

    local previewPlaceholder = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewPlaceholder:SetPoint("CENTER", previewPanel, "CENTER", 0, 0)
    previewPlaceholder:SetText("Hover over a feature to see its preview")
    previewPlaceholder:SetTextColor(0.5, 0.5, 0.5, 1)

    self.previewTex = previewTex
    self.previewPlaceholder = previewPlaceholder
    self.previewPanel = previewPanel

    -- Never show again checkbox
    local neverShow = CreateThemeCheckbox(frame)
    neverShow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING + 4, 18)
    neverShow:SetChecked(ns.Settings:IsNeverShowOnboarding())

    local neverShowText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    neverShowText:SetPoint("LEFT", neverShow, "RIGHT", 6, 0)
    neverShowText:SetText("Never show again")
    self.neverShowCheckbox = neverShow
    self.neverShowText = neverShowText

    -- Okay button
    local okay = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okay:SetSize(120, 26)
    okay:SetPoint("BOTTOM", frame, "BOTTOM", 0, 18)
    okay:SetText(self.hasMigrated and "Reload" or "Okay")
    okay:SetScript("OnClick", function()
        Onboarding:AcceptSelections()
    end)

    self.frame = frame
    self.listScroll = scroll
    self.listContent = content
end

function Onboarding:AcceptSelections()
    local onboarding = GetOnboardingData()

    for _, rowData in ipairs(self.rows or {}) do
        local enabled = rowData.checkbox:GetChecked()
        if ns.ModuleRegistry and ns.ModuleRegistry.SetModuleEnabled then
            ns.ModuleRegistry:SetModuleEnabled(rowData.module.id, enabled)
        else
            ns.Settings:SetModuleEnabled(rowData.module.id, enabled)
            if ns.ModuleRegistry then
                ns.ModuleRegistry:ApplyModuleSettings(rowData.module.id)
            end
        end
        onboarding.seenModules[rowData.module.id] = true
    end

    if self.neverShowCheckbox then
        ns.Settings:SetNeverShowOnboarding(self.neverShowCheckbox:GetChecked())
    end
    local maxVersion = CURRENT_VERSION
    for _, rowData in ipairs(self.rows or {}) do
        if rowData.module.version and rowData.module.version > maxVersion then
            maxVersion = rowData.module.version
        end
    end
    ns.Settings:SetLastSeenVersion(maxVersion)

    self:HideModuleTooltip()

    if self.frame then
        self.frame:EnableKeyboard(false)
        self.frame:Hide()
    end

    self:Finish()

    if self.hasMigrated then
        ReloadUI()
    end
end

function Onboarding:Finish()
    if self.completed then return end
    self.completed = true

    local callback = self.onReady
    self.onReady = nil
    if type(callback) == "function" then
        callback()
    end
end

function Onboarding:Show(modules)
    self:BuildFrame()
    self:Populate(modules)
    self:RefreshTheme()

    if self.listScroll then
        self.listScroll:SetVerticalScroll(0)
    end

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(self.frame)
        if self.previewPanel then
            ns.UI:ApplyTheme(self.previewPanel)
        end
    end

    self.frame:SetAlpha(1)
    self.frame:Show()
end

function Onboarding:ShowForTesting()
    local modules = self:CollectAllModules()
    if #modules == 0 then
        return false, "no_modules"
    end
    self:Show(modules)
    return true
end

function Onboarding:TryStart()
    if self.started then return end
    self.started = true

    -- Respect the "never show again" preference set by the user
    if ns.Settings and ns.Settings.IsNeverShowOnboarding and ns.Settings:IsNeverShowOnboarding() then
        self:Finish()
        return
    end

    local unseenModules = self:CollectUnseenModules()
    if #unseenModules == 0 then
        self:Finish()
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            self:Show(unseenModules)
        end)
    else
        self:Show(unseenModules)
    end
end

function Onboarding:Initialize(onReady, hasMigrated)
    self.onReady = onReady
    self.hasMigrated = hasMigrated

    if self.initialized then return end
    self.initialized = true

    if hasEnteredWorld then
        self:TryStart()
    else
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:SetScript("OnEvent", function()
            self:TryStart()
        end)
    end
end
