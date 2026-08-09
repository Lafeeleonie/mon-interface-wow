local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "crosshair",
    name = "Crosshair",
    version = ns.Versions.CROSSHAIR,
    source = "core",
    internal = true,
    subtitle = "Display a centered crosshair during combat.",
    onboardingDescription = "Helps with orientation using a tactical crosshair.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\crosshair.tga",
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    defaults = {
        enabled = false,
        xOffset = 0,
        yOffset = -26,
        alphaInCombat = 0.4,
        combatColor = { 1, 0, 0.1176, 1 },
        accentColor = { 0.4352, 0, 0.1450, 1 },
        combatSoftColor = { 1, 0.0078, 0, 1 },
        scale = 0.8,
        combatOnly = true,
        alphaOutCombat = 0.2,
        frameStrata = "HIGH",
    },
}

-- Constants & Design System
module.CONSTANTS = {
    TEXTURE_WHITE = "Interface\\Buttons\\WHITE8x8",
    DEFAULT_SIZE = 104,
    MIN_SCALE = 0.25,
    MAX_SCALE = 4.0,
    FALLBACK_ALPHA = 1.0,
    STRATA_DEFAULT = "HIGH",
    
    -- Specific line dimensions for the tactical layout
    LAYOUT = {
        { width = 104, height = 7,   x = 0, y = 0, color = { 1, 1, 1, 0.85 }, alpha = 0 },
        { width = 7,   height = 104, x = 0, y = 0, color = { 0.97, 1, 0.97, 0.85 }, alpha = 0 },
        { width = 100, height = 4,   x = 0, y = 0, color = { 1, 0, 0.086, 1 }, alpha = 1 },
        { width = 4,   height = 100, x = 0, y = 0, color = { 1, 0, 0.086, 0.85 }, alpha = 1 },
    }
}

-- Utility helpers: shared color helpers from Core/Color.lua (NormalizeRGBA
-- clamps + defaults the alpha to fallback[4] or 1, matching the old local's
-- FALLBACK_ALPHA = 1.0 behavior).
local NormalizeColor = ns.Color.NormalizeRGBA
local Clamp = ns.Color.Clamp

function module:EnsureFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ThyraxCrosshairFrame", UIParent)
    frame:SetSize(self.CONSTANTS.DEFAULT_SIZE, self.CONSTANTS.DEFAULT_SIZE)
    frame:Hide()

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(frame, { transparent = true, border = false })
    end

    self.lines = {}
    for i, config in ipairs(self.CONSTANTS.LAYOUT) do
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(self.CONSTANTS.TEXTURE_WHITE)
        tex:SetSize(config.width, config.height)
        tex:SetPoint("CENTER", frame, "CENTER", config.x, config.y)
        tex:SetVertexColor(config.color[1], config.color[2], config.color[3], config.alpha or config.color[4] or 1)
        self.lines[i] = tex
    end

    self.frame = frame
end

function module:SetupEditMode()
    if self.editModeSetup then return end
    self.editModeSetup = true

    self:EnsureFrame()
    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")

    local bg = self.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0, 0.2)
    bg:Hide()
    self.editModeBg = bg

    self.frame:SetScript("OnDragStart", function(f)
        if self.inEditMode then f:StartMoving() end
    end)

    self.frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local uiScale = UIParent:GetEffectiveScale()
        local frameScale = f:GetEffectiveScale()
        local cx, cy = f:GetCenter()
        local px, py = UIParent:GetCenter()

        if cx and cy and px and py then
            local newX = math.floor(((cx * frameScale) - (px * uiScale)) / frameScale + 0.5)
            local newY = math.floor(((cy * frameScale) - (py * uiScale)) / frameScale + 0.5)

            if ns.Settings and ns.Settings.SetModuleValue then
                ns.Settings:SetModuleValue(self.id, "xOffset", newX)
                ns.Settings:SetModuleValue(self.id, "yOffset", newY)
            end

            self.settings.xOffset = newX
            self.settings.yOffset = newY
            self:ApplyVisualSettings()
        end
    end)

    local function ToggleEditMode(enabled)
        -- hooksecurefunc cannot be uninstalled, so the EditMode hooks fire
        -- forever after the first OnEnable. Guard against the case where the
        -- module was disabled in between: without this check, opening Edit
        -- Mode on a disabled module would force the crosshair back on screen.
        if not self.isActive then return end
        self.inEditMode = enabled
        if enabled then
            self.frame:EnableMouse(true)
            self.editModeBg:Show()
            self.frame:SetAlpha(1)
            self.frame:Show()
        else
            self.frame:EnableMouse(false)
            self.editModeBg:Hide()
            self:UpdateVisibility()
        end
    end

    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "Show", function() ToggleEditMode(true) end)
        hooksecurefunc(EditModeManagerFrame, "Hide", function() ToggleEditMode(false) end)
        if EditModeManagerFrame:IsShown() then ToggleEditMode(true) end
    end
end

function module:ApplyVisualSettings()
    if not self.frame or not self.lines then return end

    local s = self.settings
    local x = tonumber(s.xOffset) or self.defaults.xOffset
    local y = tonumber(s.yOffset) or self.defaults.yOffset
    local scale = Clamp(tonumber(s.scale) or self.defaults.scale, self.CONSTANTS.MIN_SCALE, self.CONSTANTS.MAX_SCALE)

    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    self.frame:SetScale(scale)
    self.frame:SetFrameStrata(s.frameStrata or self.CONSTANTS.STRATA_DEFAULT)

    -- Resolve tactical colors
    local rA, gA, bA, aA = NormalizeColor(s.accentColor, self.defaults.accentColor)
    local rC, gC, bC, aC = NormalizeColor(s.combatColor, self.defaults.combatColor)
    local rS, gS, bS, aS = NormalizeColor(s.combatSoftColor, { rC, gC, bC, aC * 0.85 })

    self.lines[1]:SetVertexColor(rA, gA, bA, aA)
    self.lines[2]:SetVertexColor(rA, gA, bA, aA)
    self.lines[3]:SetVertexColor(rC, gC, bC, aC)
    self.lines[4]:SetVertexColor(rS, gS, bS, aS)
end

function module:UpdateVisibility()
    if not self.frame then return end

    if self.testModeUntil and ns.Compat.GetTime() < self.testModeUntil then
        self.frame:SetAlpha(1)
        self.frame:Show()
        return
    end

    local inCombat = self.inCombat
    local settings = self.settings
    if settings.combatOnly and not inCombat then
        self.frame:Hide()
        return
    end

    local alpha = inCombat and (tonumber(settings.alphaInCombat) or 1) or (tonumber(settings.alphaOutCombat) or 0.2)
    if alpha <= 0 then
        self.frame:Hide()
    else
        self.frame:SetAlpha(alpha)
        self.frame:Show()
    end
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    self:ApplyVisualSettings()
    self:UpdateVisibility()
end

function module:OnEnable(settings)
    -- Track the enabled state so EditMode hooks (which cannot be uninstalled
    -- in WoW) can short-circuit when the module gets disabled later.
    self.isActive = true
    self:EnsureFrame()
    self.inCombat = ns.Compat.IsInCombat()
    self:ApplySettings(settings)
    self:SetupEditMode()
end

function module:OnDisable()
    self.isActive = false
    if self.frame then self.frame:Hide() end
    self.testModeUntil = nil
end

function module:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
    end
    self:UpdateVisibility()
end

function module:RunTest(durationSeconds)
    self:EnsureFrame()
    self.testModeUntil = ns.Compat.GetTime() + (tonumber(durationSeconds) or 5)
    self:UpdateVisibility()
end

function module:GetDebugState()
    return {
        inCombat = self.inCombat,
        visible = self.frame and self.frame:IsShown() or false,
        alpha = self.frame and self.frame:GetAlpha() or 0,
        x = self.settings.xOffset,
        y = self.settings.yOffset,
    }
end

ns.ModuleRegistry:Register(module)
