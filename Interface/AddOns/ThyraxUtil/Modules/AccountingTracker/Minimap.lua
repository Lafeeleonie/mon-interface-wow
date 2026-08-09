local _, ns = ...

-- Minimap button for the Accounting ledger window. Lives in its own file so
-- the AccountingTracker.lua main file stays focused on data + window logic.
-- Loaded AFTER Modules/AccountingTracker.lua so the shared module table is
-- already present in ns._sharedModules.accounting.

local module = ns._sharedModules and ns._sharedModules.accounting
if not module then return end

local MINIMAP_BTN_DEFAULT_ANGLE  = 220
local MINIMAP_BTN_DEFAULT_RADIUS = 90

function module:UpdateMinimapButtonPosition()
    if not (self.minimapButton and _G.Minimap) then return end
    local x = self.settings and self.settings.minimapBtnX
    local y = self.settings and self.settings.minimapBtnY
    if not (x and y) then
        local r = math.rad(MINIMAP_BTN_DEFAULT_ANGLE)
        x = math.cos(r) * MINIMAP_BTN_DEFAULT_RADIUS
        y = math.sin(r) * MINIMAP_BTN_DEFAULT_RADIUS
    end
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

function module:SaveMinimapButtonPosition()
    if not (self.minimapButton and _G.Minimap) then return end
    local bx, by = self.minimapButton:GetCenter()
    local mx, my = _G.Minimap:GetCenter()
    if not (bx and by and mx and my) then return end
    if self.settings then
        self.settings.minimapBtnX = bx - mx
        self.settings.minimapBtnY = by - my
    end
end

function module:StopMinimapButtonDrag()
    if not self.minimapButton then return end
    self.minimapButton:StopMovingOrSizing()
    self:SaveMinimapButtonPosition()
end

function module:ResetMinimapButtonPosition()
    if self.settings then
        self.settings.minimapBtnX = nil
        self.settings.minimapBtnY = nil
    end
    self:UpdateMinimapButtonPosition()
end

function module:EnsureMinimapButton()
    if self.minimapButton or not _G.Minimap then return end

    local btn = CreateFrame("Button", "ThyraxUtilAccountingMinimapButton", _G.UIParent)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(btn)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 7)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnDragStart", function(self)
        self._wasDragged = false
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self._wasDragged = true
        module:StopMinimapButtonDrag()
    end)
    btn:SetScript("OnMouseUp", function()
        module:StopMinimapButtonDrag()
    end)
    btn:SetScript("OnClick", function(self, button)
        if self._wasDragged then
            self._wasDragged = false
            return
        end
        if button == "RightButton" then
            module:OpenAccountingOptions()
        else
            module:ToggleWindow()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        _G.GameTooltip:SetText("ThyraxUtil Accounting")
        _G.GameTooltip:AddLine("Left-click: Open ledger", 1, 1, 1)
        _G.GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
        _G.GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
        _G.GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    self.minimapButton = btn
    self:UpdateMinimapButtonPosition()
end

function module:UpdateMinimapButton()
    if self.settings and self.settings.showMinimapButton == true then
        self:EnsureMinimapButton()
        self:UpdateMinimapButtonPosition()
        if self.minimapButton then self.minimapButton:Show() end
    elseif self.minimapButton then
        self.minimapButton:Hide()
    end
end
