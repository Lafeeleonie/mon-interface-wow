local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

-- Localize hot-path globals (OnUpdate ticks at ~250 Hz, so table lookups add up).
local math_min, math_max = math.min, math.max
local tonumber = tonumber
local NormalizeRGBA = ns.Color.NormalizeRGBA

local module = {
    id = "mouse_tracker",
    name = "Mouse Tracker",
    version = ns.Versions.MOUSE_TRACKER,
    source = "core",
    internal = true,
    subtitle = "Dynamic mouse ring with combat styles.",
    onboardingDescription = "Displays a mouse tracker that adapts to combat states.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\mousetracker.tga",
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    defaults = {
        enabled            = false,
        sizeOutCombat      = 45,
        updateRate         = 0.004,
        sizeCombat         = 50,
        smoothFollow       = false,
        combatOnly         = false,
        texturePath        = "",
        combatOutlineColor = { 0.47, 0.50, 0.47, 1 },
        shape              = "ring",
        outOfCombatColor   = { 0.38, 0.42, 0.38, 1 },
        combatFillColor    = { 0.95, 0, 0.08, 1 },
        thickness          = 1,
        thicknessInCombat  = 1,
        useCombatColor     = true,
        opacity            = 1,
    },
}

-- Constants & Performance Tuning
module.CONSTANTS = {
    RING_TEXTURE = "Interface\\Cooldown\\ping4",
    STAR_TEXTURE = "Interface\\Cooldown\\star4",
    BACKUP_TEXTURE = "Interface\\Buttons\\WHITE8x8",
    DEFAULT_UPDATE_RATE = 0.004, -- 250 FPS cap
    MIN_UPDATE_RATE = 0.001,
    SMOOTH_FACTOR_BASE = 45,
    MIN_COMBAT_THICKNESS = 2,
    DEFAULT_SIZE = 68,
}

-- Resolved State (Cached to avoid per-frame logic)
module.state = {
    texturePath = "",
    inCombat = false,
    currentX = 0,
    currentY = 0,
    lockX = 0,
    lockY = 0,
}

function module:EnsureFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(20)
    frame:SetSize(self.CONSTANTS.DEFAULT_SIZE, self.CONSTANTS.DEFAULT_SIZE)
    frame:SetClampedToScreen(true)
    frame:Hide()

    self.frame = frame
    self.textures = {
        outlineList = {},
        fillList = {},
        outOfCombatList = {},
    }
end

local function UpdateThickRing(frame, list, count, layer, path, r, g, b, a, baseSize, isVisible)
    for i = 1, #list do list[i]:Hide() end
    if not isVisible or count <= 0 then return end

    for i = 1, count do
        local t = list[i]
        if not t then
            t = frame:CreateTexture(nil, layer)
            t:SetBlendMode("ADD")
            t:SetPoint("CENTER", frame, "CENTER", 0, 0)
            list[i] = t
        end
        t:SetTexture(path)
        t:SetVertexColor(r, g, b, a)
        local offset = (i - 1 - (count - 1) / 2) * 2
        t:SetSize(math.max(1, baseSize + offset), math.max(1, baseSize + offset))
        t:Show()
    end
end

function module:UpdateTexturePath()
    local s = self.settings or self.defaults
    local shape = string.lower(s.shape or "ring")
    
    if s.texturePath and s.texturePath ~= "" then
        self.state.texturePath = s.texturePath
        return
    end

    if shape == "star" or shape == "soft_ring" then
        self.state.texturePath = self.CONSTANTS.STAR_TEXTURE
    else
        self.state.texturePath = self.CONSTANTS.RING_TEXTURE
    end
end

-- Cold-path: resolve all settings-derived values once per settings change.
-- ApplyVisualState (called on combat transitions) reads self.resolvedStyle
-- directly and does zero NormalizeColor / tonumber / string.lower work.
function module:RebuildResolvedStyle()
    local s = self.settings or self.defaults
    self:UpdateTexturePath()

    local rF, gF, bF, aF = NormalizeRGBA(s.combatFillColor, self.defaults.combatFillColor)
    local rO, gO, bO, aO = NormalizeRGBA(s.combatOutlineColor, self.defaults.combatOutlineColor)
    local rNC, gNC, bNC, aNC = NormalizeRGBA(s.outOfCombatColor, self.defaults.outOfCombatColor)

    local thickness        = tonumber(s.thickness) or self.defaults.thickness
    local thicknessCombat  = tonumber(s.thicknessInCombat) or self.defaults.thicknessInCombat
    local sizeCombat       = tonumber(s.sizeCombat) or self.defaults.sizeCombat
    local sizeOut          = tonumber(s.sizeOutCombat) or self.defaults.sizeOutCombat
    local useCombatColor   = s.useCombatColor ~= false
    local opacity          = math_max(0, math_min(1, tonumber(s.opacity) or self.defaults.opacity))

    -- Combat thickness floor: if both thickness values are thin (<2), force the
    -- minimum combat thickness so the bar is visible; otherwise honor the user's
    -- configured combat thickness.
    local effectiveThickness = math_max(
        thicknessCombat,
        (thickness < 2 and thicknessCombat < 2) and self.CONSTANTS.MIN_COMBAT_THICKNESS or thicknessCombat
    )
    local outlineCount = math_max(1, math.floor(effectiveThickness * 0.4))

    self.resolvedStyle = {
        texturePath = self.state.texturePath,
        opacity     = opacity,
        combatOnly  = s.combatOnly and true or false,
        combat = {
            fillR     = useCombatColor and rF or rNC,
            fillG     = useCombatColor and gF or gNC,
            fillB     = useCombatColor and bF or bNC,
            fillA     = useCombatColor and aF or aNC,
            outlineR  = useCombatColor and rO or rNC,
            outlineG  = useCombatColor and gO or gNC,
            outlineB  = useCombatColor and bO or bNC,
            outlineA  = useCombatColor and aO or aNC,
            size      = sizeCombat,
            thickness = effectiveThickness,
            outlineCount = outlineCount,
        },
        outCombat = {
            r = rNC, g = gNC, b = bNC, a = aNC,
            size      = sizeOut,
            thickness = thickness,
        },
    }

    if self.frame then
        self.frame:SetAlpha(opacity)
    end
end

function module:ApplyVisualState()
    if not self.frame then return end

    -- ApplyVisualState is called on combat transitions and tests sometimes
    -- call it after mutating module.settings directly. Rebuild here so alpha
    -- and colors always reflect the current settings table.
    self:RebuildResolvedStyle()
    local style = self.resolvedStyle
    if not style then return end

    local isCombat = self.state.inCombat
    local showOut  = not isCombat and not style.combatOnly

    if isCombat then
        local c = style.combat
        UpdateThickRing(self.frame, self.textures.outlineList, c.outlineCount, "BACKGROUND", style.texturePath, c.outlineR, c.outlineG, c.outlineB, c.outlineA, c.size, true)
        UpdateThickRing(self.frame, self.textures.fillList,    c.thickness,    "ARTWORK",    style.texturePath, c.fillR,    c.fillG,    c.fillB,    c.fillA,    c.size, true)
        UpdateThickRing(self.frame, self.textures.outOfCombatList, 0, nil, nil, 0, 0, 0, 0, 0, false)
    else
        local o = style.outCombat
        UpdateThickRing(self.frame, self.textures.outlineList, 0, nil, nil, 0, 0, 0, 0, 0, false)
        UpdateThickRing(self.frame, self.textures.fillList,    0, nil, nil, 0, 0, 0, 0, 0, false)
        UpdateThickRing(self.frame, self.textures.outOfCombatList, o.thickness, "ARTWORK", style.texturePath, o.r, o.g, o.b, o.a, o.size, showOut)
    end

    self:UpdateFrameVisibility()
    self.frame:SetAlpha(style.opacity or 1)
end

function module:UpdateFrameVisibility()
    if not self.frame then return end

    if self.testModeUntil and ns.Compat.GetTime() < self.testModeUntil then
        self.frame:Show()
        return
    end

    if self.settings.combatOnly and not self.state.inCombat then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function module:OnUpdate(elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed

    -- Rate is resolved once per ApplySettings (see self.resolvedRate).
    if self.elapsed < (self.resolvedRate or self.CONSTANTS.DEFAULT_UPDATE_RATE) then return end
    self.elapsed = 0

    if self.testModeUntil and ns.Compat.GetTime() < self.testModeUntil then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self.frame:Show()
        return
    end

    if self.settings.combatOnly and not self.state.inCombat then
        if self.frame:IsShown() then self.frame:Hide() end
        return
    end

    local x, y = ns.Compat.GetCursorPositionScaled()
    if not x or x < 0 then x, y = self.state.lockX, self.state.lockY end
    self.state.lockX, self.state.lockY = x, y

    if self.settings.smoothFollow then
        local factor = math_min(elapsed * self.CONSTANTS.SMOOTH_FACTOR_BASE, 1)
        self.state.currentX = self.state.currentX + (x - self.state.currentX) * factor
        self.state.currentY = self.state.currentY + (y - self.state.currentY) * factor
    else
        self.state.currentX, self.state.currentY = x, y
    end

    if not self.frame:IsShown() then self.frame:Show() end

    -- Only update anchor when position actually changed (avoids ClearAllPoints/SetPoint GC churn)
    local cx, cy = self.state.currentX, self.state.currentY
    if cx ~= self.state.lastSetX or cy ~= self.state.lastSetY then
        self.state.lastSetX, self.state.lastSetY = cx, cy
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    -- Cache the clamped update rate so OnUpdate doesn't have to tonumber/clamp
    -- it every single tick. Recomputed only when settings change.
    local rate = tonumber(self.settings.updateRate) or self.CONSTANTS.DEFAULT_UPDATE_RATE
    self.resolvedRate = math_max(rate, self.CONSTANTS.MIN_UPDATE_RATE)
    -- ApplyVisualState rebuilds the cached visual style from the current
    -- settings table and repaints the frame.
    self:ApplyVisualState()
end

function module:OnEnable(settings)
    self:EnsureFrame()
    self.state.inCombat = ns.Compat.IsInCombat()
    self.state.currentX, self.state.currentY = ns.Compat.GetCursorPositionScaled()
    
    if not self.updateFrame then
        self.updateFrame = CreateFrame("Frame")
        self.onUpdateHandler = function(_, elapsed) self:OnUpdate(elapsed) end
    end
    self.updateFrame:SetScript("OnUpdate", self.onUpdateHandler)
    
    self:ApplySettings(settings)
end

function module:OnDisable()
    if self.updateFrame then self.updateFrame:SetScript("OnUpdate", nil) end
    if self.frame then self.frame:Hide() end
    self.testModeUntil = nil
end

function module:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.state.inCombat = false
    end
    self:ApplyVisualState()
end

function module:RunTest(durationSeconds)
    self:EnsureFrame()
    self.testModeUntil = ns.Compat.GetTime() + (tonumber(durationSeconds) or 5)
    self:ApplyVisualState()
end

function module:GetDebugState()
    return {
        inCombat = self.state.inCombat,
        visible = self.frame and self.frame:IsShown() or false,
        x = self.state.currentX,
        y = self.state.currentY,
    }
end

function module:GetTargetPosition()
    return self.state.currentX, self.state.currentY
end

ns.ModuleRegistry:Register(module)
