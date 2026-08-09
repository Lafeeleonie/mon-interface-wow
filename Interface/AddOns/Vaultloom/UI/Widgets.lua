local _, Addon = ...

local Theme = Addon.Theme
local Assets = Addon.Assets
local Widgets = {}
Addon.Widgets = Widgets

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BLIZZARD_INNER_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local TEXTURED_PANEL_STYLES = {
    card = true,
    content = true,
    hero = true,
    inset = true,
    sectionInset = true,
    sidebar = true,
    utility = true,
}
local BUTTON_CAP_WIDTH = 10
local BUTTON_MIN_MIDDLE_WIDTH = 8
local BUTTON_LONG_MIDDLE_THRESHOLD = 96
local BUTTON_VERTICAL_OVERDRAW = 6

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function getLegacyButtonTexture(style, state)
    if style == "row" then
        return Assets.row
    elseif style == "tab" then
        return state == "active" and Assets.tabActive or state == "hover" and Assets.tabHover or Assets.tabNormal
    end
    return state == "active" and Assets.buttonPressed or state == "hover" and Assets.buttonHover or Assets.buttonNormal
end

local function getButtonSlices(state)
    local slices = Assets.buttonSlices
    if type(slices) ~= "table" then
        return nil
    end
    return slices[state] or slices.normal
end

local function getButtonCapWidth(width)
    width = math.max(1, tonumber(width) or 100)
    return math.min(BUTTON_CAP_WIDTH, math.max(6, math.floor((width - BUTTON_MIN_MIDDLE_WIDTH) / 2)))
end

local function anchorButtonSkin(button, horizontalOverdraw, verticalOverdraw)
    if not button or not button.vaultloomSkinParts then
        return false
    end
    horizontalOverdraw = math.max(0, tonumber(horizontalOverdraw) or 0)
    verticalOverdraw = math.max(0, tonumber(verticalOverdraw) or 0)
    button.skinHorizontalOverdraw = horizontalOverdraw
    button.skinVerticalOverdraw = verticalOverdraw

    button.skinLeft:ClearAllPoints()
    button.skinLeft:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        -horizontalOverdraw,
        verticalOverdraw
    )
    button.skinLeft:SetPoint(
        "BOTTOMLEFT",
        button,
        "BOTTOMLEFT",
        -horizontalOverdraw,
        -verticalOverdraw
    )

    button.skinRight:ClearAllPoints()
    button.skinRight:SetPoint(
        "TOPRIGHT",
        button,
        "TOPRIGHT",
        horizontalOverdraw,
        verticalOverdraw
    )
    button.skinRight:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        horizontalOverdraw,
        -verticalOverdraw
    )

    button.skin:ClearAllPoints()
    button.skin:SetPoint("TOPLEFT", button.skinLeft, "TOPRIGHT", 0, 0)
    button.skin:SetPoint("BOTTOMRIGHT", button.skinRight, "BOTTOMLEFT", 0, 0)
    return true
end

local function applyButtonSkin(button, state)
    if not button or not button.skin then
        return
    end
    if button.skinStyle == "row" or not button.vaultloomSkinParts then
        button.skin:SetTexture(getLegacyButtonTexture(button.skinStyle, state))
        return
    end

    local slices = getButtonSlices(state)
    if not slices then
        button.skin:SetTexture(getLegacyButtonTexture(button.skinStyle, state))
        return
    end
    button.skinLeft:SetTexture(slices.left)
    button.skin:SetTexture(
        button.vaultloomUsesLongMiddle and slices.middleLong or slices.middle
    )
    button.skinRight:SetTexture(slices.right)
    button.vaultloomSkinState = state
end

local function setButtonLabelColor(button)
    if not button or not button.label then
        return
    end
    local enabled = type(button.IsEnabled) ~= "function" or button:IsEnabled()
    local color = not enabled and Theme.colors.muted
        or button.active and Theme.colors.gold
        or Theme.colors.parchment
    button.label:SetTextColor(unpackColor(color))
end

local function getRestingButtonState(button, hovered)
    if type(button.IsEnabled) == "function" and not button:IsEnabled() then
        return "disabled"
    elseif button.active then
        return "active"
    elseif hovered then
        return "hover"
    end
    return "normal"
end

function Widgets:ApplyStandardGoldFrame(frame, backgroundTexture, borderColor, texturedBorder)
    if not frame or type(frame.SetBackdrop) ~= "function" then
        return
    end

    local borderInset = texturedBorder and 2 or 0
    local backdrop = {
        edgeFile = texturedBorder and BLIZZARD_INNER_BORDER or WHITE_TEXTURE,
        edgeSize = texturedBorder and 8 or 1,
        insets = {
            left = borderInset,
            right = borderInset,
            top = borderInset,
            bottom = borderInset,
        },
    }
    if backgroundTexture then
        backdrop.bgFile = backgroundTexture
    end
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(1, 1, 1, backgroundTexture and 1 or 0)
    frame:SetBackdropBorderColor(unpackColor(borderColor or Theme.colors.goldDim))
end

function Widgets:ApplyPanelStyle(frame, style)
    if not frame or type(frame.SetBackdrop) ~= "function" then
        return
    end

    local inset = style == "inset" or style == "cardInset" or style == "sectionInset"
    local border = inset and Theme.colors.goldDim or Theme.colors.goldDim
    local backgroundTexture = Assets.panelBackground
    if style == "inset" then
        backgroundTexture = Assets.insetBackground
    elseif style == "card" or style == "row" then
        backgroundTexture = Assets.cardPlate
    elseif style == "cardInset" or style == "sectionInset" then
        backgroundTexture = Assets.cardInset
    elseif style == "sidebar" then
        backgroundTexture = Assets.sidebarPlate
    elseif style == "utility" then
        backgroundTexture = Assets.utilityPlate
    elseif style == "content" then
        backgroundTexture = Assets.contentPlate
    elseif style == "hero" then
        backgroundTexture = Assets.heroPlate
    end
    self:ApplyStandardGoldFrame(
        frame,
        backgroundTexture,
        border,
        TEXTURED_PANEL_STYLES[style] == true
    )
end

function Widgets:CreatePanel(parent, style)
    local frame = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    self:ApplyPanelStyle(frame, style)
    return frame
end

function Widgets:CreateLabel(parent, fontObject, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    label:SetJustifyH(justify or "LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetTextColor(unpackColor(Theme.colors.parchment))
    return label
end

function Widgets:SetButtonSkinOverdraw(button, horizontalOverdraw, verticalOverdraw)
    return anchorButtonSkin(button, horizontalOverdraw, verticalOverdraw)
end

function Widgets:RefreshSimpleGoldButton(button)
    if not button or not button.vaultloomSimpleGoldButton then
        return
    end
    local background = button.vaultloomPressed and Theme.colors.selected
        or button.active and Theme.colors.selected
        or button.vaultloomHovered and Theme.colors.panelHover
        or Theme.colors.panelInset
    local border = (button.active or button.vaultloomHovered)
        and Theme.colors.gold or Theme.colors.goldDim
    button:SetBackdropColor(unpackColor(background))
    button:SetBackdropBorderColor(unpackColor(border))
end

function Widgets:CreateSimpleGoldButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    button:SetSize(width or 24, height or 24)
    button:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    button.vaultloomSimpleGoldButton = true
    if type(text) == "string" and text ~= "" then
        button.label = self:CreateLabel(button, "GameFontHighlightSmall", "CENTER")
        button.label:SetAllPoints(button)
        button.label:SetText(text)
    end
    self:RefreshSimpleGoldButton(button)
    button:SetScript("OnEnter", function(selfButton)
        selfButton.vaultloomHovered = true
        Widgets:RefreshSimpleGoldButton(selfButton)
    end)
    button:SetScript("OnLeave", function(selfButton)
        selfButton.vaultloomHovered = false
        selfButton.vaultloomPressed = false
        Widgets:RefreshSimpleGoldButton(selfButton)
    end)
    button:SetScript("OnMouseDown", function(selfButton)
        if type(selfButton.IsEnabled) ~= "function" or selfButton:IsEnabled() then
            selfButton.vaultloomPressed = true
            Widgets:RefreshSimpleGoldButton(selfButton)
        end
    end)
    button:SetScript("OnMouseUp", function(selfButton)
        selfButton.vaultloomPressed = false
        Widgets:RefreshSimpleGoldButton(selfButton)
    end)
    return button
end

function Widgets:CreateButton(parent, text, width, height, style)
    local button = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    button.skinStyle = style or "button"
    local buttonWidth = width or 100
    local buttonHeight = height or 28
    button.vaultloomUsesLongMiddle = button.skinStyle ~= "row"
        and buttonWidth >= BUTTON_LONG_MIDDLE_THRESHOLD
    button:SetSize(buttonWidth, buttonHeight)
    if button.skinStyle == "row" then
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button:SetBackdropColor(0, 0, 0, 0)
        button:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    else
        button:SetBackdrop(nil)
    end

    button.skin = button:CreateTexture(nil, "BACKGROUND")
    if button.skinStyle == "row" then
        button.skin:SetAllPoints(button)
    else
        button.skinCapWidth = getButtonCapWidth(buttonWidth)
        button.skinLeft = button:CreateTexture(nil, "BACKGROUND")
        button.skinRight = button:CreateTexture(nil, "BACKGROUND")
        button.skinLeft:SetWidth(button.skinCapWidth)
        button.skinRight:SetWidth(button.skinCapWidth)
        button.vaultloomSkinParts = {
            left = button.skinLeft,
            middle = button.skin,
            right = button.skinRight,
        }
        self:SetButtonSkinOverdraw(button, 0, BUTTON_VERTICAL_OVERDRAW)
    end
    applyButtonSkin(button, "normal")

    button.label = self:CreateLabel(button, "GameFontHighlightSmall", "CENTER")
    local labelInset = button.skinStyle == "row" and 6
        or math.min((button.skinCapWidth or BUTTON_CAP_WIDTH) + 2, math.max(4, math.floor((buttonWidth - 10) / 2)))
    button.label:SetPoint("TOPLEFT", labelInset, 0)
    button.label:SetPoint("BOTTOMRIGHT", -labelInset, 0)
    button.label:SetText(text or "")

    button:SetScript("OnEnter", function(self)
        self.vaultloomHovered = true
        applyButtonSkin(self, getRestingButtonState(self, true))
        if self.skinStyle == "row" then
            self:SetBackdropBorderColor(unpackColor(Theme.colors.gold))
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.vaultloomHovered = false
        applyButtonSkin(self, getRestingButtonState(self, false))
        if self.skinStyle == "row" then
            self:SetBackdropBorderColor(unpackColor(self.active and Theme.colors.gold or Theme.colors.goldDim))
        end
    end)
    button:SetScript("OnMouseDown", function(self)
        if type(self.IsEnabled) ~= "function" or self:IsEnabled() then
            applyButtonSkin(self, "pressed")
        end
    end)
    button:SetScript("OnMouseUp", function(self)
        applyButtonSkin(self, getRestingButtonState(self, self.vaultloomHovered ~= false))
    end)
    button:SetScript("OnDisable", function(self)
        applyButtonSkin(self, "disabled")
        setButtonLabelColor(self)
    end)
    button:SetScript("OnEnable", function(self)
        applyButtonSkin(self, getRestingButtonState(self, self.vaultloomHovered == true))
        setButtonLabelColor(self)
    end)
    return button
end

function Widgets:SetButtonActive(button, active)
    if not button then
        return
    end
    button.active = active == true
    if button.vaultloomSimpleGoldButton then
        self:RefreshSimpleGoldButton(button)
        return
    end
    applyButtonSkin(button, getRestingButtonState(button, button.vaultloomHovered == true))
    if button.skinStyle == "row" then
        button:SetBackdropBorderColor(unpackColor(button.active and Theme.colors.gold or Theme.colors.goldDim))
    end
    setButtonLabelColor(button)
end

function Widgets:CreateProgressBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(Assets.barFill)
    bar:SetStatusBarColor(0.74, 0.63, 0.28, 0.95)

    bar.backdrop = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bar.backdrop:SetPoint("TOPLEFT", -1, 1)
    bar.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.backdrop:SetTexture(Assets.barBackground)
    bar.backdrop:SetVertexColor(0.08, 0.07, 0.06, 0.22)

    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints(bar)
    bar.background:SetTexture(Assets.barBackground)
    bar.background:SetVertexColor(1, 1, 1, 0.94)

    bar.fill = bar:GetStatusBarTexture()
    if bar.fill then
        bar.fill:SetHorizTile(false)
        bar.fill:SetVertTile(false)
    end

    bar.fillOverlay = bar:CreateTexture(nil, "ARTWORK")
    if bar.fill then
        bar.fillOverlay:SetPoint("TOPLEFT", bar.fill, "TOPLEFT", 0, 0)
        bar.fillOverlay:SetPoint("BOTTOMRIGHT", bar.fill, "BOTTOMRIGHT", 0, 0)
    else
        bar.fillOverlay:SetAllPoints(bar)
    end
    bar.fillOverlay:SetTexture(Assets.barOverlay)
    bar.fillOverlay:SetBlendMode("ADD")
    bar.fillOverlay:SetVertexColor(1, 1, 1, 0.22)

    bar.glow = bar:CreateTexture(nil, "ARTWORK")
    bar.glow:SetTexture(Assets.barOverlay)
    bar.glow:SetBlendMode("ADD")
    bar.glow:SetAlpha(0.06)
    bar.glow:Hide()

    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetSize(16, 20)
    bar.spark:SetTexture(Assets.barSpark)
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetAlpha(0.18)

    bar.topEdge = bar:CreateTexture(nil, "BORDER")
    bar.topEdge:SetPoint("TOPLEFT", 7, 0)
    bar.topEdge:SetPoint("TOPRIGHT", -7, 0)
    bar.topEdge:SetHeight(1)
    bar.topEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.topEdge:SetVertexColor(Theme.colors.parchment[1], Theme.colors.parchment[2], Theme.colors.parchment[3], 0.10)

    bar.bottomEdge = bar:CreateTexture(nil, "BORDER")
    bar.bottomEdge:SetPoint("BOTTOMLEFT", 7, 0)
    bar.bottomEdge:SetPoint("BOTTOMRIGHT", -7, 0)
    bar.bottomEdge:SetHeight(1)
    bar.bottomEdge:SetColorTexture(0.01, 0.01, 0.01, 0.16)

    bar.markers = {}
    return bar
end

function Widgets:SetProgress(bar, value, maximum, color)
    if not bar then
        return
    end
    maximum = math.max(1, tonumber(maximum) or 1)
    value = math.max(0, math.min(maximum, tonumber(value) or 0))
    local ratio = maximum > 0 and math.min(1, value / maximum) or 0
    local visualValue = ratio >= 0.015 and ratio or 0
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(visualValue)
    color = color or Theme.colors.gold
    bar:SetStatusBarColor(unpackColor(color))

    local width = bar.GetWidth and math.max(1, tonumber(bar:GetWidth()) or 1) or 1
    local fillWidth = math.floor(width * visualValue)
    if bar.glow then
        bar.glow:ClearAllPoints()
        if fillWidth > 1 then
            bar.glow:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, 0)
            bar.glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", fillWidth, 0)
            bar.glow:SetVertexColor(color[1], color[2], color[3], 0.05)
            bar.glow:Show()
        else
            bar.glow:Hide()
        end
    end
    if bar.fillOverlay then
        bar.fillOverlay:SetShown(visualValue > 0)
        bar.fillOverlay:SetVertexColor(1, 1, 1, visualValue > 0 and 0.035 or 0)
    end
    if bar.spark then
        local sparkOffset = math.max(0, math.min(width - 1, fillWidth))
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", sparkOffset, 0)
        bar.spark:SetVertexColor(color[1], color[2], color[3], 0.16)
        bar.spark:SetShown(visualValue > 0.04 and visualValue < 0.992)
    end
end

function Widgets:SetProgressBreakpoints(bar, thresholds, maximum)
    if not bar then
        return
    end

    thresholds = type(thresholds) == "table" and thresholds or {}
    maximum = math.max(0, tonumber(maximum) or 0)
    bar.markers = bar.markers or {}

    for index, threshold in ipairs(thresholds) do
        local marker = bar.markers[index]
        if not marker then
            marker = bar:CreateTexture(nil, "OVERLAY")
            marker:SetSize(16, 16)
            marker:SetTexture(Assets.barMarker)
            marker:SetBlendMode("BLEND")
            marker:SetVertexColor(0.96, 0.82, 0.48, 0.54)
            bar.markers[index] = marker
        end

        threshold = tonumber(threshold)
        if maximum > 0 and threshold and threshold < maximum then
            local width = bar.GetWidth and math.max(1, tonumber(bar:GetWidth()) or 1) or 1
            marker:ClearAllPoints()
            marker:SetPoint("CENTER", bar, "LEFT", math.floor((width * (threshold / maximum)) + 0.5), 0)
            marker:Show()
        else
            marker:Hide()
        end
    end

    for index = #thresholds + 1, #bar.markers do
        bar.markers[index]:Hide()
    end
end

function Widgets:CreateSectionTitle(parent, text, anchor)
    local title = self:CreateLabel(parent, "GameFontNormalLarge", "LEFT")
    title:SetText(text or "")
    title:SetTextColor(unpackColor(Theme.colors.gold))
    if anchor then
        title:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
    return title
end

function Widgets:CreateDivider(parent)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpackColor(Theme.colors.goldDim))
    divider:SetHeight(1)
    return divider
end
