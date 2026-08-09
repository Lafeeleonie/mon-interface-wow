local _, Addon = ...

local Launcher = {
    initialized = false,
    button = nil,
    broker = nil,
}

Addon.MinimapLauncher = Launcher

local ICON = "Interface\\Icons\\Inv_10_gearupgrade_drakesshadowflameenhancedcrest"
local DEFAULT_ANGLE = 225
local RADIUS_OFFSET = 7

local MINIMAP_SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function settings()
    local ui = Addon.Database:GetUI()
    ui.minimap = type(ui.minimap) == "table" and ui.minimap or {
        hide = false,
        minimapPos = DEFAULT_ANGLE,
    }
    ui.minimap.hide = ui.minimap.hide == true
    ui.minimap.minimapPos = tonumber(ui.minimap.minimapPos) or DEFAULT_ANGLE
    return ui.minimap
end

local function showTooltip(owner)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end
    GameTooltip:AddLine(Addon.L.ADDON_TITLE or "Vaultloom", 0.39, 0.85, 1)
    GameTooltip:AddLine(Addon.L.MINIMAP_TOOLTIP_OPEN or "Left-click: open Vaultloom", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(Addon.L.MINIMAP_TOOLTIP_OPTIONS or "Right-click: open options", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(Addon.L.MINIMAP_TOOLTIP_DRAG or "Right-drag: move button", 0.68, 0.74, 0.84, true)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

function Launcher:ToggleWindow()
    if Addon.UI and type(Addon.UI.Toggle) == "function" then
        Addon.UI:Toggle()
        return true
    end
    return false
end

function Launcher:OpenOptions()
    if not Addon.UI or type(Addon.UI.CreateFrame) ~= "function" then return false end
    local frame = Addon.UI:CreateFrame()
    if not frame then return false end
    frame:Show()
    frame:Raise()
    return Addon.UI:OpenOptions("general")
end

function Launcher:UpdatePosition()
    local button = self.button
    if not button or not Minimap then return false end
    local angle = math.rad(tonumber(settings().minimapPos) or DEFAULT_ANGLE)
    local width = type(Minimap.GetWidth) == "function" and Minimap:GetWidth() or 140
    local height = type(Minimap.GetHeight) == "function" and Minimap:GetHeight() or 140
    local radiusX = math.max(54, (tonumber(width) or 140) * 0.5 + RADIUS_OFFSET)
    local radiusY = math.max(54, (tonumber(height) or 140) * 0.5 + RADIUS_OFFSET)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    local roundQuadrants = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
    if roundQuadrants[quadrant] then
        x, y = x * radiusX, y * radiusY
    else
        local diagonalX = math.sqrt(2 * radiusX * radiusX) - 10
        local diagonalY = math.sqrt(2 * radiusY * radiusY) - 10
        x = math.max(-radiusX, math.min(x * diagonalX, radiusX))
        y = math.max(-radiusY, math.min(y * diagonalY, radiusY))
    end
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    return true
end

function Launcher:Refresh()
    if not self.button then return false end
    if settings().hide then
        self.button:Hide()
    else
        self.button:Show()
        self:UpdatePosition()
    end
    return true
end

function Launcher:SetHidden(hidden)
    settings().hide = hidden == true
    self:Refresh()
    return settings().hide
end

function Launcher:IsHidden()
    return settings().hide == true
end

function Launcher:ResetPosition()
    settings().minimapPos = DEFAULT_ANGLE
    self:UpdatePosition()
    return DEFAULT_ANGLE
end

function Launcher:UpdateDrag(button)
    if not button or not Minimap or type(GetCursorPosition) ~= "function"
        or type(Minimap.GetCenter) ~= "function"
    then
        return
    end
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = type(Minimap.GetEffectiveScale) == "function"
        and Minimap:GetEffectiveScale()
        or (UIParent and type(UIParent.GetEffectiveScale) == "function"
            and UIParent:GetEffectiveScale() or 1)
    scale = tonumber(scale) or 1
    centerX = tonumber(centerX)
    centerY = tonumber(centerY)
    if not centerX or not centerY or not cursorX or not cursorY or scale == 0 then return end
    cursorX = cursorX / scale
    cursorY = cursorY / scale
    local deltaX, deltaY = cursorX - centerX, cursorY - centerY
    local angle
    if math.atan2 then
        angle = math.deg(math.atan2(deltaY, deltaX))
    elseif deltaX ~= 0 then
        angle = math.deg(math.atan(deltaY / deltaX))
        if deltaX < 0 then angle = angle + 180 end
    else
        angle = deltaY >= 0 and 90 or 270
    end
    if angle < 0 then angle = angle + 360 end
    settings().minimapPos = angle % 360
    self:UpdatePosition()
end

function Launcher:CreateButton()
    if self.button or not Minimap then return self.button end
    local button = CreateFrame("Button", "VaultloomMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((type(Minimap.GetFrameLevel) == "function" and Minimap:GetFrameLevel() or 1) + 8)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(ICON)
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if type(button.icon.AddMaskTexture) == "function" then
        button.mask = button:CreateMaskTexture(nil, "ARTWORK")
        button.mask:SetTexture(
            "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        button.mask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(button.mask)
    end

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetColorTexture(1.00, 0.82, 0.46, 0.16)
    button.highlight:SetBlendMode("ADD")
    button.highlight:SetSize(24, 24)
    button.highlight:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    if type(button.highlight.AddMaskTexture) == "function" then
        button.highlightMask = button:CreateMaskTexture(nil, "HIGHLIGHT")
        button.highlightMask:SetTexture(
            "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        button.highlightMask:SetAllPoints(button.highlight)
        button.highlight:AddMaskTexture(button.highlightMask)
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Launcher:OpenOptions()
        else
            Launcher:ToggleWindow()
        end
    end)
    button:SetScript("OnDragStart", function(selfButton)
        selfButton.dragging = true
        if type(selfButton.LockHighlight) == "function" then
            selfButton:LockHighlight()
        end
        hideTooltip()
        selfButton:SetScript("OnUpdate", function(activeButton)
            Launcher:UpdateDrag(activeButton)
        end)
    end)
    button:SetScript("OnDragStop", function(selfButton)
        selfButton.dragging = false
        selfButton:SetScript("OnUpdate", nil)
        if type(selfButton.UnlockHighlight) == "function" then
            selfButton:UnlockHighlight()
        end
        Launcher:UpdatePosition()
    end)
    button:SetScript("OnEnter", function(selfButton)
        if not selfButton.dragging then
            showTooltip(selfButton)
        end
    end)
    button:SetScript("OnLeave", hideTooltip)

    self.button = button
    self:Refresh()
    return button
end

function Launcher:CreateBroker()
    if self.broker or type(LibStub) ~= "table" then return self.broker end
    local ldb = LibStub("LibDataBroker-1.1", true)
    if not ldb then return nil end
    local broker = ldb:GetDataObjectByName("Vaultloom")
    if not broker then
        broker = ldb:NewDataObject("Vaultloom", {
            type = "launcher",
            label = "Vaultloom",
            text = "Vaultloom",
            icon = ICON,
            iconCoords = { 0.08, 0.92, 0.08, 0.92 },
        })
    end
    if not broker then return nil end
    broker.OnClick = function(_, mouseButton)
        if mouseButton == "RightButton" then
            Launcher:OpenOptions()
        else
            Launcher:ToggleWindow()
        end
    end
    broker.OnTooltipShow = function(tooltip)
        if not tooltip or type(tooltip.AddLine) ~= "function" then return end
        tooltip:AddLine(Addon.L.ADDON_TITLE or "Vaultloom", 0.39, 0.85, 1)
        tooltip:AddLine(Addon.L.MINIMAP_TOOLTIP_OPEN or "Left-click: open Vaultloom", 0.9, 0.9, 0.9, true)
        tooltip:AddLine(Addon.L.MINIMAP_TOOLTIP_OPTIONS or "Right-click: open options", 0.9, 0.9, 0.9, true)
    end
    self.broker = broker
    return broker
end

function Launcher:Initialize()
    if self.initialized then return true end
    self.initialized = true
    self:CreateBroker()
    self:CreateButton()
    return self.button ~= nil
end

function _G.Vaultloom_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        Launcher:OpenOptions()
    else
        Launcher:ToggleWindow()
    end
end

function _G.Vaultloom_OnAddonCompartmentEnter(_, buttonFrame)
    showTooltip(buttonFrame)
end

function _G.Vaultloom_OnAddonCompartmentLeave()
    hideTooltip()
end
