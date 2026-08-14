local _, ns = ...
local unpack = unpack or table.unpack
-- Localize math hot-path functions used in OnUpdate (which ticks at frame
-- rate, ~60-300 Hz, while skyriding is active). Avoids two table lookups
-- per call under WoW's Lua 5.1 runtime. Matches the pattern already used
-- by MouseTracker.lua.
local math_min, math_max, math_abs, math_floor = math.min, math.max, math.abs, math.floor
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "dynamic_flight_tracker",
    name = "Dynamic Flight Tracker",
    version = ns.Versions.DYNAMIC_FLIGHT_TRACKER,
    source = "core",
    internal = true,
    events = {
        "PLAYER_MOUNT_DISPLAY_CHANGED",
        "UPDATE_SHAPESHIFT_FORM",
        "ZONE_CHANGED_NEW_AREA",
    },
    unitEvents = {
        { event = "UNIT_FLAGS", unit = "player" },
    },
    subtitle = "Skyriding & Momentum visualizer.",
    onboardingDescription = "Displays a momentum-based speed bar for Skyriding.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\flighttracker.tga",
    defaults = {
        enabled = false,
        xOffset = 0,
        yOffset = -300,
        scale = 1.0,
        arrowScale = 1.5,
        showSpeed = true,
        showAccel = true,
        textPosition = "above", -- Options: "above", "on", "below"
        barWidth = 200,
        barHeight = 12,
        colorMain = { 0.1, 0.8, 1, 1 }, -- Light Blue
        colorSustainable = { 0.1, 1, 0.1, 1 }, -- Green
        colorSlow = { 1, 0.1, 0.1, 1 }, -- Red

        -- Style options.
        fillTextureKey    = "solid",               -- "solid" | "uistatusbar" | "raidhp"
        showBackground    = true,
        backgroundColor   = { 0, 0, 0, 0.5 },
        showBorder        = false,
        borderColor       = { 1, 1, 1, 1 },        -- White so it's visible against the default dark bg.
        showMarker        = true,
        markerColor       = { 1, 1, 0, 1 },
        useGradientColor  = false,                 -- Hard-bucket color transitions by default; users can opt into smooth gradient.
        fontSize          = 11,
        fontOutline       = "NONE",                -- "NONE" | "OUTLINE" | "THICKOUTLINE"

        -- Speed threshold (percent) at or below which the bar is hidden.
        -- Bar shows when current displayed speed > hideUnderPct. Default 0
        -- means the feature is off and the bar shows whenever tracking is
        -- active; raise it (e.g. 200) to keep the bar out of sight at
        -- non-skyriding speeds and only reveal it once skyriding momentum
        -- starts contributing meaningful values.
        hideUnderPct      = 0,
    },
}

-- Constants
module.CONSTANTS = {
    BASE_YDS_SEC = 7.0,
    DRAGON_ISLES_SUSTAIN = 929,
    OLD_WORLD_SUSTAIN = 790, -- math.floor(929 * 0.85 + 0.5)
    OLD_WORLD_MODIFIER = 0.85,
    MAX_DISPLAY_MODERN = 1400,
    MAX_DISPLAY_LEGACY = 1200,
    SMOOTHING_WEIGHT = 0.7,
    TEXT_UPDATE_THROTTLE = 0.15,
    ACCEL_THRESHOLD = 5,
    VIGOR_REGEN_THRESHOLD = 510,
    BASE_ICON_SIZE = 16,
    DELAY_RETRY_TRACKING = 0.2,

    -- Druid Flight Form fires UPDATE_SHAPESHIFT_FORM well before IsFlying() and
    -- C_PlayerInfo.GetGlidingInfo().canGlide flip true: the player may shift on
    -- the ground and only start flying several seconds later. A single retry
    -- (as used for mount-up) misses this window, so shapeshift events schedule
    -- a chain of retries that aborts as soon as tracking turns on.
    -- Cumulative coverage ~7.2s, which spans the typical shift -> jump -> fly
    -- sequence with a generous safety margin. Each tick is an O(1) state read,
    -- so the chain is cheap even when the player never takes off.
    SHAPESHIFT_RETRY_DELAYS = { 0.2, 0.5, 1.0, 2.0, 3.5 },

    -- Frame-rate independent lerp rate for the displayed bar width / color.
    -- GetUnitSpeed() and C_PlayerInfo.GetGlidingInfo() only refresh at the
    -- engine tick (~10 Hz), so the raw speedPercentage jumps in steps. We
    -- exponentially interpolate the displayed percentage toward the raw
    -- value so the fill animates smoothly between engine ticks.
    -- Higher = snappier response, lower = smoother but more visual lag.
    -- 12 gives ~85% catch-up in 0.15s at 60 FPS.
    FILL_SMOOTH_RATE = 12,

    -- Fill texture presets (all ship with the game client, no external assets).
    FILL_TEXTURES = {
        solid       = "Interface\\Buttons\\WHITE8x8",
        uistatusbar = "Interface\\TargetingFrame\\UI-StatusBar",
        raidhp      = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    },

    BORDER_TEXTURE = "Interface\\Buttons\\WHITE8x8",

    -- Color bucket IDs used by OnUpdate to detect transitions without table compares.
    BUCKET_SLOW   = 1,
    BUCKET_MAIN   = 2,
    BUCKET_SUSTAIN = 3,

    -- Accel icon state IDs.
    ACCEL_NONE = 0,
    ACCEL_UP   = 1,
    ACCEL_DOWN = 2,
}

-- Module State
module.isActive = false
module.lastSpeedPercentage = 0
module.smoothAcceleration = 0
module.isOldWorld = true
module.lastWidth = 0
module.cachedSustainPct = 0
module.cachedMaxDisplayPct = 0

-- Static string cache for speeds to avoid string.format churn
local speedLabelCache = {}
for i = 0, 1500 do
    speedLabelCache[i] = i .. "%"
end

-- Cache the shared secret-value guard from Compat for the OnUpdate hot path.
-- See Core/Compat.lua for full rationale on WoW 12.0 secret values.
local IsNonSecretNumber = ns.Compat.IsNonSecretNumber

-- UI Elements
function module:EnsureFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ThyraxFlightTracker", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", self.defaults.xOffset, self.defaults.yOffset)
    frame:SetSize(self.defaults.barWidth, 40)
    frame:Hide()

    -- Speed Bar Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    self.bg = bg

    -- Speed Bar Fill
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", frame, "LEFT", 0, 0)
    fill:SetHeight(self.defaults.barHeight)
    fill:SetTexture(self.CONSTANTS.FILL_TEXTURES.solid)
    fill:SetVertexColor(1, 1, 1, 1)
    self.fill = fill

    -- Optional 1px Border (4 WHITE8x8 edges, hidden by default; toggled by ApplyStyle).
    -- Draw layer is ARTWORK sublevel 1 so edges render ABOVE the fill (which is
    -- ARTWORK sublevel 0). Using the "BORDER" layer would let the fill paint
    -- over the edges, so enabling the border would appear to do nothing once
    -- the bar fills up. The marker on OVERLAY still sits on top of both.
    local function MakeEdge()
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture(self.CONSTANTS.BORDER_TEXTURE)
        t:Hide()
        return t
    end
    local borderTop, borderBottom, borderLeft, borderRight =
        MakeEdge(), MakeEdge(), MakeEdge(), MakeEdge()
    borderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)
    borderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)
    borderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)
    borderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)
    self.borderEdges = { borderTop, borderBottom, borderLeft, borderRight }

    -- Sustainable Marker
    local marker = frame:CreateTexture(nil, "OVERLAY")
    marker:SetSize(2, self.defaults.barHeight + 4)
    marker:SetColorTexture(1, 1, 0, 1)
    marker:SetPoint("CENTER", frame, "LEFT", 0, 0)
    self.marker = marker

    -- Speed Text
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    self.text = text

    -- Accel Icon
    local accelIcon = frame:CreateTexture(nil, "OVERLAY")
    accelIcon:SetSize(16, 16)
    accelIcon:SetPoint("LEFT", text, "RIGHT", 2, 0)
    self.accelIcon = accelIcon

    self.frame = frame

    -- The flight tracker has its own fully-configurable background and border
    -- (showBackground/backgroundColor + showBorder/borderColor, see ApplyStyle),
    -- so we intentionally disable the theme's border and keep the theme bg
    -- transparent. Otherwise the Modern theme's gold 1px edge would always be
    -- drawn on top of the user's border choice with no way to disable it.
    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(frame, { transparent = true, border = false })
    end
end

-- Math functions
function module:CalculateSpeedPercentage(rawSpeed)
    return (rawSpeed / self.CONSTANTS.BASE_YDS_SEC) * 100
end

-- Walks the map's parent chain up to its continent entry. This replaces a
-- former C_Map.GetFallbackWorldMapID(mapID) call: that API does not resolve
-- the continent of the passed map (it returns the generic fallback world
-- map), so the Dragon Isles / Khaz Algar check below never matched and the
-- sustain marker always used old-world values. The parent walk via
-- C_Map.GetMapInfo(...).parentMapID is the documented way to resolve a
-- zone's continent. The loop is bounded defensively against parent cycles.
local function GetContinentMapID(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local continentType = (_G.Enum and _G.Enum.UIMapType and _G.Enum.UIMapType.Continent) or 2
    local info = C_Map.GetMapInfo(mapID)
    for _ = 1, 10 do
        if not info then return nil end
        if info.mapType == continentType then return info.mapID end
        local parentMapID = info.parentMapID
        if not parentMapID or parentMapID == 0 then return nil end
        info = C_Map.GetMapInfo(parentMapID)
    end
    return nil
end

function module:UpdateZoneMultiplier(forcedOldWorld)
    local isOldWorld = forcedOldWorld
    if isOldWorld == nil then
        local mapID = C_Map.GetBestMapForUnit("player")
        local continentID = mapID and GetContinentMapID(mapID)
        if continentID then
            -- 1978: Dragon Isles, 2248: Khaz Algar
            isOldWorld = not (continentID == 1978 or continentID == 2248)
        else
            isOldWorld = self.isOldWorld
        end
    end

    self.isOldWorld = isOldWorld
    if isOldWorld then
        self.cachedSustainPct = self.CONSTANTS.OLD_WORLD_SUSTAIN
        self.cachedMaxDisplayPct = self.CONSTANTS.MAX_DISPLAY_LEGACY
    else
        self.cachedSustainPct = self.CONSTANTS.DRAGON_ISLES_SUSTAIN
        self.cachedMaxDisplayPct = self.CONSTANTS.MAX_DISPLAY_MODERN
    end

    -- Marker position depends on cachedSustainPct / cachedMaxDisplayPct / barWidth.
    -- All are stable between zone/settings changes, so cache anchor here.
    self:UpdateMarkerPosition()
end

-- Sets the sustainable-speed marker anchor. Called only on setting/zone changes,
-- never from OnUpdate.
function module:UpdateMarkerPosition()
    if not self.marker or not self.frame then return end
    local s = self.settings or self.defaults
    local barWidth = tonumber(s.barWidth) or self.defaults.barWidth
    if self.cachedSustainPct <= 0 or self.cachedMaxDisplayPct <= 0 then return end
    local markerPos = (self.cachedSustainPct / self.cachedMaxDisplayPct) * barWidth
    self.marker:ClearAllPoints()
    self.marker:SetPoint("CENTER", self.frame, "LEFT", markerPos, 0)
end

-- Applies all user-selected visual style settings. Called from ApplySettings,
-- never from OnUpdate.
function module:ApplyStyle()
    if not self.frame then return end
    local s = self.settings or self.defaults
    local C = self.CONSTANTS

    -- Fill texture preset (falls back to solid if the key is unrecognised).
    local texKey = tostring(s.fillTextureKey or "solid"):lower()
    local texPath = C.FILL_TEXTURES[texKey] or C.FILL_TEXTURES.solid
    if self.fill then
        self.fill:SetTexture(texPath)
    end

    -- Background visibility + color (with alpha).
    if self.bg then
        local bc = s.backgroundColor or self.defaults.backgroundColor
        local r = tonumber(bc[1]) or 0
        local g = tonumber(bc[2]) or 0
        local b = tonumber(bc[3]) or 0
        local a = tonumber(bc[4]) or 0.5
        if s.showBackground == false then
            a = 0
        end
        self.bg:SetColorTexture(r, g, b, a)
    end

    -- Optional 1px border.
    if self.borderEdges then
        local showBorder = s.showBorder == true
        local bc = s.borderColor or self.defaults.borderColor
        local r = tonumber(bc[1]) or 0
        local g = tonumber(bc[2]) or 0
        local b = tonumber(bc[3]) or 0
        local a = tonumber(bc[4]) or 1
        for _, edge in ipairs(self.borderEdges) do
            if showBorder then
                edge:SetVertexColor(r, g, b, a)
                edge:Show()
            else
                edge:Hide()
            end
        end
    end

    -- Marker visibility + color.
    if self.marker then
        if s.showMarker == false then
            self.marker:Hide()
        else
            local mc = s.markerColor or self.defaults.markerColor
            local r = tonumber(mc[1]) or 1
            local g = tonumber(mc[2]) or 1
            local b = tonumber(mc[3]) or 0
            local a = tonumber(mc[4]) or 1
            self.marker:SetColorTexture(r, g, b, a)
            self.marker:Show()
        end
    end

    -- Font size + outline flag on speed text.
    if self.text then
        local fontPath = self.text:GetFont()
        if fontPath then
            local size = tonumber(s.fontSize) or self.defaults.fontSize
            local outlineKey = tostring(s.fontOutline or "NONE"):upper()
            local outlineFlag = ""
            if outlineKey == "OUTLINE" then
                outlineFlag = "OUTLINE"
            elseif outlineKey == "THICKOUTLINE" then
                outlineFlag = "THICKOUTLINE"
            end
            self.text:SetFont(fontPath, size, outlineFlag)
        end
    end

    -- Accel icon size is setting-driven, not per-frame. Cache it here.
    if self.accelIcon then
        local arrowScale = tonumber(s.arrowScale) or self.defaults.arrowScale
        local size = C.BASE_ICON_SIZE * arrowScale
        self.accelIcon:SetSize(size, size)
    end

    -- Invalidate OnUpdate caches so the next tick re-pushes color + accel state.
    self.lastColorBucket = nil
    self.lastAccelState = nil
end

-- Returns r, g, b, a for the given speed percentage, respecting the user's
-- gradient/hard-bucket preference. Called from OnUpdate only when the bucket
-- transitions (hard mode) or every updated tick (gradient mode).
function module:ResolveFillColor(speedPercentage)
    local s = self.settings or self.defaults
    local slow = s.colorSlow or self.defaults.colorSlow
    local main = s.colorMain or self.defaults.colorMain
    local sustain = s.colorSustainable or self.defaults.colorSustainable

    if s.useGradientColor == true then
        local vigor = self.CONSTANTS.VIGOR_REGEN_THRESHOLD
        local sustPct = self.cachedSustainPct
        if speedPercentage <= vigor then
            return slow[1], slow[2], slow[3], slow[4] or 1
        elseif speedPercentage < sustPct then
            local t = (speedPercentage - vigor) / math_max(sustPct - vigor, 1)
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            local r = slow[1] + (main[1] - slow[1]) * t
            local g = slow[2] + (main[2] - slow[2]) * t
            local b = slow[3] + (main[3] - slow[3]) * t
            local a = (slow[4] or 1) + ((main[4] or 1) - (slow[4] or 1)) * t
            return r, g, b, a
        else
            local top = sustPct * 1.1
            local t = (speedPercentage - sustPct) / math_max(top - sustPct, 1)
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            local r = main[1] + (sustain[1] - main[1]) * t
            local g = main[2] + (sustain[2] - main[2]) * t
            local b = main[3] + (sustain[3] - main[3]) * t
            local a = (main[4] or 1) + ((sustain[4] or 1) - (main[4] or 1)) * t
            return r, g, b, a
        end
    end

    -- Hard-bucket mode (default, matches original behaviour exactly).
    if speedPercentage >= self.cachedSustainPct then
        return sustain[1], sustain[2], sustain[3], sustain[4] or 1
    elseif speedPercentage > self.CONSTANTS.VIGOR_REGEN_THRESHOLD then
        return main[1], main[2], main[3], main[4] or 1
    else
        return slow[1], slow[2], slow[3], slow[4] or 1
    end
end

function module:ResolveBucket(speedPercentage)
    if speedPercentage >= self.cachedSustainPct then
        return self.CONSTANTS.BUCKET_SUSTAIN
    elseif speedPercentage > self.CONSTANTS.VIGOR_REGEN_THRESHOLD then
        return self.CONSTANTS.BUCKET_MAIN
    else
        return self.CONSTANTS.BUCKET_SLOW
    end
end

function module:GetSustainableMarker()
    return self.cachedSustainPct
end

function module:ApplySmoothing(historicalValue, newValue, weight)
    return (historicalValue * weight) + (newValue * (1 - weight))
end

function module:GetUnitSpeed(unit)
    local rawSpeed = GetUnitSpeed(unit or "player")
    if not IsNonSecretNumber(rawSpeed) then
        -- Secret value (12.0 taint) or nil; preserve last known percentage.
        return self.lastSpeedPercentage or 0
    end
    return self:CalculateSpeedPercentage(rawSpeed)
end

function module:IsSkyridingActive()
    if not C_PlayerInfo or not C_PlayerInfo.GetGlidingInfo then return false end
    local isGliding, canGlide = C_PlayerInfo.GetGlidingInfo()

    -- Active gliding/skyriding right now.
    if isGliding then return true end

    -- Skyride-capable state: a skyride mount (airborne or grounded) OR Druid
    -- Flight Form. canGlide reports the *capability*, not the current motion,
    -- so it stays true through landings. Treating it as a sufficient trigger
    -- on its own (instead of AND-ing with IsMounted/IsFlying) means we don't
    -- need a polling watcher to catch the land-then-take-off-again case:
    -- OnUpdate keeps running between flight bursts and picks the speed back
    -- up the instant the player leaves the ground. Side effect by design:
    -- the bar shows at 0% while in Flight Form on the ground, mirroring the
    -- existing behaviour while parked on a skyride mount.
    if canGlide then return true end

    return false
end

-- Returns true if the bar should be hidden because the current speed is
-- below the user-configured threshold. Edit mode and test mode always force
-- the bar visible so the user can position / preview it regardless of speed.
-- Extracted from OnUpdate so it can be unit-tested without mocking the WoW
-- frame APIs.
--
-- Reads from `self.cachedHideUnderPct`, refreshed in ApplySettings whenever
-- the user changes the slider. Falls back to a re-read when the cache has
-- not been primed yet or the settings table was replaced by tests.
function module:ShouldSuppressBar(displayPct)
    if self.inEditMode then return false end
    if self.testModeUntil and GetTime() < self.testModeUntil then return false end
    local hideUnder = self.cachedHideUnderPct
    local settings = self.settings or self.defaults
    if hideUnder == nil or self.cachedHideUnderSource ~= settings then
        hideUnder = tonumber(settings.hideUnderPct) or 0
        self.cachedHideUnderPct = hideUnder
        self.cachedHideUnderSource = settings
    end
    if hideUnder <= 0 then return false end
    return (tonumber(displayPct) or 0) <= hideUnder
end

function module:UpdateModuleState()
    if not self.isActive then return end

    local shouldTrack = self:IsSkyridingActive() or self.inEditMode or
        (self.testModeUntil and GetTime() < self.testModeUntil)

    if shouldTrack then
        self:EnableTracking()
    else
        self:DisableTracking()
    end
end

function module:EnableTracking()
    self:EnsureFrame()
    if self.isTracking then return end
    self.isTracking = true

    -- Reset smoothing + transition state so the first OnUpdate tick pushes a
    -- color / accel icon state instead of assuming stale caches.
    local initialPct = self:GetUnitSpeed("player")
    self.lastSpeedPercentage = initialPct
    -- Seed the displayed percentage to the current real value so the bar
    -- doesn't animate up from 0 when tracking starts mid-flight.
    self.displayPercentage = initialPct
    self.smoothAcceleration = 0
    self.textUpdateTimer = 0
    self.lastWidth = 0
    self.lastColorBucket = nil
    self.lastAccelState = nil

    self.updateFrame:SetScript("OnUpdate", self.onUpdateHandler)

    if self.frame and not self.frame:IsShown() then
        self.frame:Show()
    end
end

function module:DisableTracking()
    if not self.isTracking then return end
    self.isTracking = false

    if self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
    end
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    end
end

function module:OnUpdate(elapsed)
    -- Cap the heavy per-frame work at ~60 Hz. On high-refresh monitors
    -- (144 / 240 Hz) the engine fires OnUpdate at the display rate, which
    -- doubles or quadruples CPU cost for no visible benefit. Pass the
    -- accumulated elapsed through so the lerp / acceleration math stays
    -- frame-rate independent.
    self._updateAccum = (self._updateAccum or 0) + elapsed
    if self._updateAccum < 0.016 then return end
    elapsed = self._updateAccum
    self._updateAccum = 0

    -- Single authoritative GetGlidingInfo call per frame, used for both the
    -- skyriding-active check and the skyriding speed value below.
    local isGliding, canGlide, skySpeed = false, false, 0
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        isGliding, canGlide, skySpeed = C_PlayerInfo.GetGlidingInfo()
    end

    -- Periodic safety check: If we are not in Edit Mode or Test Mode,
    -- check if we should still be tracking. Handles dismounting mid-air and
    -- other edge cases where events might lag behind game state.
    local isTestMode = self.testModeUntil and GetTime() < self.testModeUntil
    if not self.inEditMode and not isTestMode then
        -- Mirrors IsSkyridingActive: canGlide alone keeps the bar alive
        -- across landings while still in a flight-capable state (Flight
        -- Form, parked skyride mount). Without this, after every landing
        -- the OnUpdate would tear itself down and there would be no event
        -- to re-enable on the next take-off.
        local stillActive = isGliding or canGlide
        if not stillActive then
            self:DisableTracking()
            return
        end
    end

    -- GetUnitSpeed("player") may return a "secret number" under WoW 12.0
    -- when execution is tainted by an addon. Comparing or doing arithmetic
    -- on a secret value raises a Lua error, so we have to bail out for this
    -- frame and let the displayPercentage lerp coast on the last known value.
    -- skySpeed (from C_PlayerInfo.GetGlidingInfo) is not currently restricted.
    local rawSpeed = GetUnitSpeed("player")
    if not IsNonSecretNumber(rawSpeed) then
        return
    end

    -- Use the higher of the two speeds for maximum responsiveness
    local effectiveSpeed = rawSpeed
    if isGliding and skySpeed and skySpeed > rawSpeed then
        effectiveSpeed = skySpeed
    end

    local speedPercentage = self:CalculateSpeedPercentage(effectiveSpeed)

    -- Acceleration Math (runs on raw engine values so the arrow reflects
    -- true acceleration, not the visually smoothed bar state).
    if elapsed > 0 then
        local currentDelta = (speedPercentage - self.lastSpeedPercentage) / elapsed
        self.smoothAcceleration = self:ApplySmoothing(self.smoothAcceleration, currentDelta,
            self.CONSTANTS.SMOOTHING_WEIGHT)
        self.lastSpeedPercentage = speedPercentage
    end

    -- Frame-rate independent smoothing for the displayed bar percentage.
    -- GetUnitSpeed() / GetGlidingInfo() only refresh at the engine tick,
    -- so the raw speedPercentage jumps in ~10 Hz steps. Lerp the displayed
    -- value toward the raw value so the fill animates smoothly between
    -- engine ticks instead of stair-stepping (especially visible in the
    -- 250-700% skyriding ramp).
    local displayPct = self.displayPercentage or speedPercentage
    local lerpFactor = math_min(elapsed * self.CONSTANTS.FILL_SMOOTH_RATE, 1)
    displayPct = displayPct + (speedPercentage - displayPct) * lerpFactor
    self.displayPercentage = displayPct

    -- Update UI
    if self.frame then
        local s = self.settings
        local C = self.CONSTANTS

        -- Apply the user's speed-visibility threshold. We toggle frame
        -- visibility (cheap, only on transition) rather than skipping the
        -- per-frame work below, so the bar paints accurately the instant it
        -- becomes visible instead of revealing a stale fill width.
        local shouldSuppress = self:ShouldSuppressBar(displayPct)
        local isShown = self.frame:IsShown()
        if shouldSuppress and isShown then
            self.frame:Hide()
        elseif not shouldSuppress and not isShown then
            self.frame:Show()
        end

        -- Bar Fill width (only push on > 0.5px delta; unchanged from before).
        local widthRatio = math_min(displayPct / self.cachedMaxDisplayPct, 1)
        local targetWidth = math_max(1, s.barWidth * widthRatio)
        if math_abs(targetWidth - self.lastWidth) > 0.5 then
            self.fill:SetWidth(targetWidth)
            self.lastWidth = targetWidth
        end

        -- Color: gradient mode updates every tick; hard-bucket mode only on
        -- bucket transition (saves a SetVertexColor call per frame most of the time).
        -- Uses displayPct (not raw) so the color transition animates in lock-step
        -- with the bar fill.
        if s.useGradientColor == true then
            local r, g, b, a = self:ResolveFillColor(displayPct)
            self.fill:SetVertexColor(r, g, b, a)
            self.lastColorBucket = -1 -- force repaint on mode switch back to hard
        else
            local bucket = self:ResolveBucket(displayPct)
            if bucket ~= self.lastColorBucket then
                local r, g, b, a = self:ResolveFillColor(displayPct)
                self.fill:SetVertexColor(r, g, b, a)
                self.lastColorBucket = bucket
            end
        end

        -- Text + accel icon throttled to TEXT_UPDATE_THROTTLE.
        self.textUpdateTimer = (self.textUpdateTimer or 0) + elapsed
        if self.textUpdateTimer >= C.TEXT_UPDATE_THROTTLE then
            local textStr = ""
            if s.showSpeed then
                local rounded = math_floor(speedPercentage + 0.5)
                textStr = speedLabelCache[rounded] or (rounded .. "%")
            end

            if s.showAccel then
                local accelThreshold = C.ACCEL_THRESHOLD
                local newState
                if self.smoothAcceleration > accelThreshold then
                    newState = C.ACCEL_UP
                elseif self.smoothAcceleration < -accelThreshold then
                    newState = C.ACCEL_DOWN
                else
                    newState = C.ACCEL_NONE
                end

                if newState ~= self.lastAccelState then
                    if newState == C.ACCEL_UP then
                        self.accelIcon:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
                        self.accelIcon:Show()
                    elseif newState == C.ACCEL_DOWN then
                        self.accelIcon:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                        self.accelIcon:Show()
                    else
                        self.accelIcon:Hide()
                    end
                    self.lastAccelState = newState
                end
            elseif self.lastAccelState ~= C.ACCEL_NONE then
                self.accelIcon:Hide()
                self.lastAccelState = C.ACCEL_NONE
            end

            if self.text then
                self.text:SetText(textStr)
            end
            self.textUpdateTimer = 0
        end
    end

    -- Update debug panel throttled to 0.2s only in developer mode to prevent memory pressure
    self.debugUpdateTimer = (self.debugUpdateTimer or 0) + elapsed
    if self.isActive and ns.Settings and ns.Settings:IsDeveloperModeEnabled() and self.debugPanel then
        if self.debugUpdateTimer >= 0.2 then
            local st = self:GetDebugState()
            self.debugPanel:SetText(self:FormatDebugState(st))
            self.debugUpdateTimer = 0
        end
    end
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    self:EnsureFrame()

    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", self.settings.xOffset, self.settings.yOffset)
        self.frame:SetScale(self.settings.scale)
        self.frame:SetSize(self.settings.barWidth, self.settings.barHeight)
        self.bg:SetSize(self.settings.barWidth, self.settings.barHeight)
        self.fill:SetHeight(self.settings.barHeight)
        self.marker:SetHeight(self.settings.barHeight + 4)

        -- Position Text & Accel Icon
        if self.text then
            self.text:ClearAllPoints()
            local pos = self.settings.textPosition or "on"
            if pos == "above" then
                self.text:SetPoint("BOTTOM", self.frame, "TOP", 0, 4)
            elseif pos == "below" then
                self.text:SetPoint("TOP", self.frame, "BOTTOM", 0, -4)
            else -- "on"
                self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
            end
        end
    end

    -- Apply all user-chosen visual style options (texture, bg, border, marker,
    -- font, accel icon size) and refresh the marker anchor. These routines
    -- only run on setting changes, never from OnUpdate.
    self:ApplyStyle()
    self:UpdateMarkerPosition()

    -- Cache the speed-visibility threshold so ShouldSuppressBar doesn't have
    -- to tonumber() the setting on every OnUpdate tick. Invalidated whenever
    -- the user moves the slider (ApplySettings reruns).
    self.cachedHideUnderPct = tonumber(self.settings.hideUnderPct) or 0
    self.cachedHideUnderSource = self.settings

    -- The bar width may have shrunk, so reset fill width tracking so OnUpdate
    -- doesn't skip the first paint after a settings change.
    self.lastWidth = 0
end

function module:SetupEditMode()
    if self.editModeSetup then return end
    self.editModeSetup = true

    self:EnsureFrame()
    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")

    local bg = self.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0, 0.2)
    bg:Hide()
    self.editModeBg = bg

    self.frame:SetScript("OnDragStart", function(f)
        if self.inEditMode then
            f:StartMoving()
        end
    end)

    self.frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local uiScale = UIParent:GetEffectiveScale()
        local frameScale = f:GetEffectiveScale()
        local cx, cy = f:GetCenter()
        local px, py = UIParent:GetCenter()

        if cx and cy and px and py then
            local dxPhysical = (cx * frameScale) - (px * uiScale)
            local dyPhysical = (cy * frameScale) - (py * uiScale)

            local newX = math_floor(dxPhysical / frameScale + 0.5)
            local newY = math_floor(dyPhysical / frameScale + 0.5)

            if ns.Settings and ns.Settings.SetModuleValue then
                ns.Settings:SetModuleValue(self.id, "xOffset", newX)
                ns.Settings:SetModuleValue(self.id, "yOffset", newY)
            end

            self.settings.xOffset = newX
            self.settings.yOffset = newY

            self:ApplySettings()
        end
    end)

    local function ToggleEditMode(enabled)
        -- hooksecurefunc cannot be uninstalled, so the EditMode hooks fire
        -- forever after the first OnEnable. Guard against the case where the
        -- module was disabled in between: without this check, opening Edit
        -- Mode would call EnableTracking() on a disabled module and start
        -- OnUpdate on the cached updateFrame.
        if not self.isActive then return end
        self.inEditMode = enabled
        if enabled then
            self.frame:EnableMouse(true)
            self.editModeBg:Show()
            self:EnableTracking()
            self.testModeUntil = GetTime() + 7200 -- 2 hours test mode
        else
            self.frame:EnableMouse(false)
            self.editModeBg:Hide()
            self.testModeUntil = nil
            self:UpdateModuleState()
        end
    end

    local function HookEditMode()
        hooksecurefunc(EditModeManagerFrame, "Show", function() ToggleEditMode(true) end)
        hooksecurefunc(EditModeManagerFrame, "Hide", function() ToggleEditMode(false) end)
        if EditModeManagerFrame:IsShown() then
            ToggleEditMode(true)
        end
    end

    if EditModeManagerFrame then
        HookEditMode()
    else
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_EditMode" or EditModeManagerFrame then
                f:UnregisterEvent("ADDON_LOADED")
                HookEditMode()
            end
        end)
    end
end

function module:OnEnable(settings)
    self.isActive = true
    self:EnsureFrame()

    if not self.updateFrame then
        self.updateFrame = CreateFrame("Frame")
        self.onUpdateHandler = function(_, elapsed) self:OnUpdate(elapsed) end
    end

    self:ApplySettings(settings)
    self:UpdateZoneMultiplier()
    self:SetupEditMode()
    self:UpdateModuleState()
end

function module:OnDisable()
    self:DisableTracking()
    self.isActive = false
    -- Any in-flight retry chain will short-circuit on its next tick via the
    -- isActive guard. Clearing the flag here lets a subsequent OnEnable
    -- schedule a fresh chain immediately instead of waiting for the stale
    -- chain to exhaust its delays.
    self.retryPending = false
end

function module:RunTest(durationSeconds)
    self:EnsureFrame()
    self.testModeUntil = GetTime() + (tonumber(durationSeconds) or 5)
    self:EnableTracking()
end

-- Schedules a chain of delayed UpdateModuleState() calls. Used to work around
-- the Glide API lagging behind the triggering event (mount-up, shapeshift,
-- unit-flag transition). The chain self-aborts:
--   * once tracking turns on (the lag resolved, we're done);
--   * if the module gets disabled mid-chain (avoids leaking timers across
--     enable/disable cycles, which would otherwise hold a reference to self
--     for the chain's full duration);
--   * when the schedule is exhausted.
-- retryPending prevents stacking chains when events fire in quick succession.
function module:ScheduleRetries(delays)
    if not self.isActive then return end
    if self.retryPending then return end
    if type(delays) ~= "table" or #delays == 0 then return end
    self.retryPending = true
    local idx = 1
    local function step()
        local delay = delays[idx]
        if not delay then
            self.retryPending = false
            return
        end
        idx = idx + 1
        C_Timer.After(delay, function()
            -- Mid-chain disable: drop the chain so we don't keep the module
            -- table reachable via the closure for the rest of the schedule.
            if not self.isActive then
                self.retryPending = false
                return
            end
            self:UpdateModuleState()
            if self.isTracking then
                self.retryPending = false
                return
            end
            step()
        end)
    end
    step()
end

function module:OnEvent(event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" then
        self:UpdateZoneMultiplier()
        return
    end

    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_FLAGS" then
        self:UpdateModuleState()
        -- Mount + UNIT_FLAGS settle within a tick, so a single retry suffices
        -- and we gate UNIT_FLAGS on IsMounted() to avoid storms from non-flight
        -- flag transitions. Shapeshift is the druid case: the player is not
        -- mounted, so the old IsMounted() gate dropped the retry entirely, and
        -- Flight Form may need over a second before IsFlying() / canGlide flip.
        if event == "UPDATE_SHAPESHIFT_FORM" then
            self:ScheduleRetries(self.CONSTANTS.SHAPESHIFT_RETRY_DELAYS)
        elseif IsMounted() then
            self:ScheduleRetries({ self.CONSTANTS.DELAY_RETRY_TRACKING })
        end
    end
end

-- Reusable table to avoid per-call allocation (called from OnUpdate in dev mode).
-- WARNING: Shared mutable state - callers must consume the result immediately.
-- Do not hold a reference across frames; contents will be overwritten on next call.
module._debugState = {}

function module:GetDebugState()
    local isGliding, canGlide, glidingSpeed = false, false, 0
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        isGliding, canGlide, glidingSpeed = C_PlayerInfo.GetGlidingInfo()
    end

    local st = self._debugState
    st.active = self.isActive
    st.visible = self.frame and self.frame:IsShown() or false
    st.gliding = isGliding
    st.canGlide = canGlide
    st.isFlying = IsFlying()
    st.isFalling = IsFalling()
    st.speed = self.lastSpeedPercentage
    st.accel = self.smoothAcceleration
    return st
end

function module:FormatDebugState(state)
    local function B(v) return v and "Y" or "N" end

    return ("vis=%s glide=%s can=%s fly=%s fall=%s spd=%d%% acc=%.1f"):format(
        B(state.visible), B(state.gliding), B(state.canGlide),
        B(state.isFlying), B(state.isFalling), state.speed, state.accel
    )
end

ns.ModuleRegistry:Register(module)
