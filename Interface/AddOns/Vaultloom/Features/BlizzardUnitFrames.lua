local _, Addon = ...

local FEATURE_ID = "blizzard_unit_frames"
local SHIELD_TEXTURE = "Interface\\RaidFrame\\Shield-Overlay"

local DEFAULTS = {
    color_mode = "class_reaction",
    health_text = "blizzard",
    shield_mode = "clear",
    dark_background = true,
}

local FRAME_SPECS = {
    { key = "player", unit = "player", frameName = "PlayerFrame", text = true, shield = true },
    { key = "target", unit = "target", frameName = "TargetFrame", text = true, shield = true },
    { key = "focus", unit = "focus", frameName = "FocusFrame", text = true, shield = true },
    { key = "pet", unit = "pet", frameName = "PetFrame" },
    { key = "targettarget", unit = "targettarget", frameName = "TargetFrameToT" },
    { key = "focustarget", unit = "focustarget", frameName = "FocusFrameToT" },
}

local Runtime = {
    enabled = false,
    hooksReady = false,
    suppressHooks = false,
    config = {
        color_mode = DEFAULTS.color_mode,
        health_text = DEFAULTS.health_text,
        shield_mode = DEFAULTS.shield_mode,
        dark_background = DEFAULTS.dark_background,
    },
    states = {},
    stateByBar = {},
    stateByFrame = {},
}

Addon.BlizzardUnitFrames = Runtime

local function setting(key)
    local state = Addon.FeatureRegistry:GetState(FEATURE_ID)
    local value = state.settings[key]
    return value == nil and DEFAULTS[key] or value
end

local function isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function canUseNumber(value)
    return type(value) == "number" and not isSecret(value)
end

local function safeMethod(object, methodName, ...)
    local method = object and object[methodName]
    if type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function unitExists(unit)
    if type(UnitExists) ~= "function" then return true end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or isSecret(exists) then return false end
    return exists == true
end

local function resolveHealthBar(frame)
    if not frame then return nil end
    if frame.healthbar then return frame.healthbar end
    if frame.HealthBar then return frame.HealthBar end
    if frame.healthBar then return frame.healthBar end

    local playerMain = frame.PlayerFrameContent
        and frame.PlayerFrameContent.PlayerFrameContentMain
    local targetMain = frame.TargetFrameContent
        and frame.TargetFrameContent.TargetFrameContentMain
    local main = playerMain or targetMain
    local container = main and main.HealthBarsContainer
    return container and (container.HealthBar or container.healthBar) or nil
end

local function addUnique(result, seen, region)
    if region and type(region.SetAlpha) == "function" and not seen[region] then
        result[#result + 1] = region
        seen[region] = true
    end
end

local function resolveTextRegions(frame, healthBar)
    local result, seen = {}, {}
    addUnique(result, seen, healthBar and healthBar.TextString)
    addUnique(result, seen, healthBar and healthBar.LeftText)
    addUnique(result, seen, healthBar and healthBar.RightText)

    local playerMain = frame and frame.PlayerFrameContent
        and frame.PlayerFrameContent.PlayerFrameContentMain
    local targetMain = frame and frame.TargetFrameContent
        and frame.TargetFrameContent.TargetFrameContentMain
    local main = playerMain or targetMain
    local container = main and main.HealthBarsContainer
    addUnique(result, seen, container and container.HealthBarText)
    addUnique(result, seen, container and container.LeftText)
    addUnique(result, seen, container and container.RightText)
    return result
end

local function getStatusBarColor(bar)
    if not bar or type(bar.GetStatusBarColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
    if not ok or isSecret(r) or isSecret(g) or isSecret(b) or isSecret(a) then
        return nil
    end
    return { r = r, g = g, b = b, a = a }
end

local function getStatusBarDesaturated(bar)
    if not bar or type(bar.GetStatusBarDesaturated) ~= "function" then return false end
    local ok, value = pcall(bar.GetStatusBarDesaturated, bar)
    if not ok or isSecret(value) then return false end
    return value == true
end

local function colorsMatch(left, right)
    if not left or not right then return false end
    return math.abs((tonumber(left.r) or 0) - (tonumber(right.r) or 0)) < 0.0001
        and math.abs((tonumber(left.g) or 0) - (tonumber(right.g) or 0)) < 0.0001
        and math.abs((tonumber(left.b) or 0) - (tonumber(right.b) or 0)) < 0.0001
        and math.abs((tonumber(left.a) or 1) - (tonumber(right.a) or 1)) < 0.0001
end

local function getClassColor(unit)
    local classToken
    if type(UnitClassBase) == "function" then
        local ok, value = pcall(UnitClassBase, unit)
        if ok then classToken = value end
    end
    if not classToken and type(UnitClass) == "function" then
        local ok, _, value = pcall(UnitClass, unit)
        if ok then classToken = value end
    end
    if isSecret(classToken) then return nil end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = colors and classToken and colors[classToken]
    if not color then return nil end
    return {
        r = tonumber(color.r) or 1,
        g = tonumber(color.g) or 1,
        b = tonumber(color.b) or 1,
        a = tonumber(color.a) or 1,
    }
end

local function callUnitPredicate(predicate, unit, otherUnit)
    if type(predicate) ~= "function" then return false end
    local ok, value = pcall(predicate, unit, otherUnit)
    if not ok or isSecret(value) then return false end
    return value == true
end

local function getUnitColor(unit)
    local mode = Runtime.config.color_mode
    if mode == "blizzard" or not unitExists(unit) then return nil end

    if unit == "pet" then
        return getClassColor("player")
    end
    if callUnitPredicate(UnitIsPlayer, unit) then
        return getClassColor(unit)
    end
    if mode == "class_only" then return nil end

    if callUnitPredicate(UnitIsTapDenied, unit) then
        return { r = 0.55, g = 0.55, b = 0.55, a = 1 }
    end
    if callUnitPredicate(UnitIsEnemy, unit, "player") then
        return { r = 0.90, g = 0.12, b = 0.12, a = 1 }
    end
    if callUnitPredicate(UnitIsFriend, unit, "player") then
        return { r = 0.20, g = 0.82, b = 0.24, a = 1 }
    end
    return { r = 0.95, g = 0.80, b = 0.10, a = 1 }
end

local function abbreviate(value)
    value = tonumber(value) or 0
    if type(AbbreviateNumbers) == "function" then
        local ok, result = pcall(AbbreviateNumbers, value)
        if ok and result ~= nil then return tostring(result) end
    end
    if value >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    end
    if value >= 1000 then
        return string.format("%dk", math.floor(value / 1000))
    end
    return tostring(math.floor(value + 0.5))
end

local function captureTextureStyle(texture)
    if not texture then return nil end
    local style = {}
    if type(texture.GetAtlas) == "function" then
        local ok, value = pcall(texture.GetAtlas, texture)
        if ok then style.atlas = value end
    end
    if type(texture.GetTexture) == "function" then
        local ok, value = pcall(texture.GetTexture, texture)
        if ok then style.texture = value end
    end
    if type(texture.GetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
        if ok then style.vertex = { r, g, b, a } end
    end
    if type(texture.GetAlpha) == "function" then
        local ok, value = pcall(texture.GetAlpha, texture)
        if ok then style.alpha = value end
    end
    if type(texture.IsHorizTile) == "function" then
        local ok, value = pcall(texture.IsHorizTile, texture)
        if ok then style.horizTile = value == true end
    end
    if type(texture.IsVertTile) == "function" then
        local ok, value = pcall(texture.IsVertTile, texture)
        if ok then style.vertTile = value == true end
    end
    return style
end

local function restoreTextureStyle(texture, style)
    if not texture or not style then return end
    if style.atlas and type(texture.SetAtlas) == "function" then
        safeMethod(texture, "SetAtlas", style.atlas)
    elseif style.texture ~= nil then
        safeMethod(texture, "SetTexture", style.texture)
    end
    if style.vertex then
        safeMethod(texture, "SetVertexColor", unpack(style.vertex))
    end
    if style.alpha ~= nil then safeMethod(texture, "SetAlpha", style.alpha) end
    if style.horizTile ~= nil then safeMethod(texture, "SetHorizTile", style.horizTile) end
    if style.vertTile ~= nil then safeMethod(texture, "SetVertTile", style.vertTile) end
end

local function resolveAbsorbOverlay(frame)
    local absorbBar = frame and frame.totalAbsorbBar
    return absorbBar and (
        absorbBar.TiledFillOverlay
        or absorbBar.tiledFillOverlay
        or absorbBar.Fill
    ) or nil
end

function Runtime:AcquireState(spec)
    local frame = _G[spec.frameName]
    local healthBar = resolveHealthBar(frame)
    if not frame or not healthBar then return nil end

    local state = self.states[spec.key]
    if state and state.healthBar ~= healthBar then
        self:RestoreState(state, false)
        self.stateByBar[state.healthBar] = nil
        self.stateByFrame[state.frame] = nil
        state = nil
    end
    if not state then
        local originalColor = getStatusBarColor(healthBar)
        state = {
            spec = spec,
            frame = frame,
            healthBar = healthBar,
            originalColor = originalColor,
            originalDesaturated = getStatusBarDesaturated(healthBar),
            nativeColor = originalColor,
            nativeDesaturated = getStatusBarDesaturated(healthBar),
            originalTextAlpha = {},
        }
        self.states[spec.key] = state
        self.stateByBar[healthBar] = state
    else
        if state.frame ~= frame then self.stateByFrame[state.frame] = nil end
        state.frame = frame
    end
    self.stateByFrame[frame] = state

    if not state.background and type(healthBar.CreateTexture) == "function" then
        state.background = healthBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        state.background:SetAllPoints(healthBar)
        state.background:SetColorTexture(0.015, 0.015, 0.018, 0.72)
        state.background:Hide()
    end

    if spec.text then
        for _, region in ipairs(resolveTextRegions(frame, healthBar)) do
            if state.originalTextAlpha[region] == nil then
                local alpha = 1
                if type(region.GetAlpha) == "function" then
                    local ok, value = pcall(region.GetAlpha, region)
                    if ok and tonumber(value) then alpha = tonumber(value) end
                end
                state.originalTextAlpha[region] = alpha
            end
        end
        if not state.healthText and type(healthBar.CreateFontString) == "function" then
            state.healthText = healthBar:CreateFontString(nil, "OVERLAY")
            state.healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
            state.healthText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            state.healthText:SetTextColor(1, 1, 1, 1)
            state.healthText:SetShadowOffset(1, -1)
            state.healthText:SetShadowColor(0, 0, 0, 1)
            state.healthText:Hide()
        end
    end

    if spec.shield then
        local nativeOverlay = resolveAbsorbOverlay(frame)
        if nativeOverlay and state.nativeAbsorbOverlay ~= nativeOverlay then
            state.nativeAbsorbOverlay = nativeOverlay
            state.nativeAbsorbStyle = captureTextureStyle(nativeOverlay)
        end
    end
    return state
end

function Runtime:SetOriginalTextVisible(state, visible)
    for region, alpha in pairs(state.originalTextAlpha or {}) do
        safeMethod(region, "SetAlpha", visible and alpha or 0)
    end
end

function Runtime:ApplyColor(state)
    local color = getUnitColor(state.spec.unit)
    if not color then
        state.lastAppliedColor = nil
        return
    end
    safeMethod(state.healthBar, "SetStatusBarDesaturated", true)
    safeMethod(
        state.healthBar,
        "SetStatusBarColor",
        color.r,
        color.g,
        color.b,
        color.a or 1
    )
    state.lastAppliedColor = {
        r = color.r,
        g = color.g,
        b = color.b,
        a = color.a or 1,
    }
end

function Runtime:ApplyBackground(state)
    if not state.background then return end
    state.background:SetShown(self.config.dark_background == true)
end

function Runtime:UpdateHealthText(state)
    if not state.spec.text or not state.healthText then return end
    local mode = self.config.health_text
    if mode == "blizzard" or not unitExists(state.spec.unit) then
        state.healthText:Hide()
        self:SetOriginalTextVisible(state, true)
        return
    end

    local okCurrent, current = pcall(UnitHealth, state.spec.unit)
    local okMaximum, maximum = pcall(UnitHealthMax, state.spec.unit)
    if not okCurrent
        or not okMaximum
        or not canUseNumber(current)
        or not canUseNumber(maximum)
        or maximum <= 0
    then
        state.healthText:Hide()
        self:SetOriginalTextVisible(state, true)
        return
    end

    local percent = math.max(0, math.min(100, math.floor((current / maximum * 100) + 0.5)))
    if mode == "value_percent" then
        state.healthText:SetText(string.format("%s · %d%%", abbreviate(current), percent))
    else
        state.healthText:SetText(string.format("%d%%", percent))
    end
    self:SetOriginalTextVisible(state, false)
    state.healthText:Show()
end

function Runtime:EnsureShieldObjects(state)
    if not state.spec.shield or state.overshield then return end
    local healthBar = state.healthBar
    state.overshield = CreateFrame("StatusBar", nil, healthBar)
    state.overshield:SetAllPoints(healthBar)
    safeMethod(state.overshield, "SetReverseFill", true)
    state.overshield:SetStatusBarTexture(SHIELD_TEXTURE)
    state.overshield:SetStatusBarColor(0.86, 0.95, 1, 0.92)
    state.overshield:SetFrameLevel(
        (type(healthBar.GetFrameLevel) == "function" and healthBar:GetFrameLevel() or 1) + 1
    )
    local texture = state.overshield:GetStatusBarTexture()
    texture:SetTexture(SHIELD_TEXTURE, "REPEAT", "REPEAT")
    texture:SetHorizTile(true)
    texture:SetVertTile(true)
    safeMethod(texture, "SetDrawLayer", "ARTWORK", 2)
    state.overshield:Hide()

    state.absorbText = healthBar:CreateFontString(nil, "OVERLAY")
    state.absorbText:SetPoint("RIGHT", healthBar, "RIGHT", -2, 0)
    state.absorbText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    state.absorbText:SetTextColor(0.72, 0.92, 1, 1)
    state.absorbText:SetShadowOffset(1, -1)
    state.absorbText:SetShadowColor(0, 0, 0, 1)
    state.absorbText:Hide()

    if type(CreateUnitHealPredictionCalculator) == "function" then
        local ok, calculator = pcall(CreateUnitHealPredictionCalculator)
        if ok and calculator then
            state.healPredictionCalculator = calculator
            local clampMode = Enum
                and Enum.UnitDamageAbsorbClampMode
                and Enum.UnitDamageAbsorbClampMode.MissingHealth
            if clampMode ~= nil then
                safeMethod(calculator, "SetDamageAbsorbClampMode", clampMode)
            end
        end
    end
end

function Runtime:IsAbsorbClamped(state, totalAbsorbs)
    local calculator = state.healPredictionCalculator
    if calculator
        and type(UnitGetDetailedHealPrediction) == "function"
        and type(calculator.GetDamageAbsorbs) == "function"
    then
        local predicted = pcall(
            UnitGetDetailedHealPrediction,
            state.spec.unit,
            nil,
            calculator
        )
        if predicted then
            local ok, _, clamped = pcall(calculator.GetDamageAbsorbs, calculator)
            if ok and not isSecret(clamped) then return clamped == true end
        end
    end

    if not canUseNumber(totalAbsorbs) then return false end
    local okCurrent, current = pcall(UnitHealth, state.spec.unit)
    local okMaximum, maximum = pcall(UnitHealthMax, state.spec.unit)
    return okCurrent
        and okMaximum
        and canUseNumber(current)
        and canUseNumber(maximum)
        and totalAbsorbs > math.max(0, maximum - current)
end

function Runtime:ApplyNativeShieldStyle(state)
    local texture = state.nativeAbsorbOverlay
    if not texture then return end
    safeMethod(texture, "SetTexture", SHIELD_TEXTURE, "REPEAT", "REPEAT")
    safeMethod(texture, "SetHorizTile", true)
    safeMethod(texture, "SetVertTile", true)
    safeMethod(texture, "SetVertexColor", 0.84, 0.94, 1, 0.92)
end

function Runtime:UpdateShield(state)
    if not state.spec.shield then return end
    local mode = self.config.shield_mode
    if mode == "blizzard" or not unitExists(state.spec.unit) then
        if state.overshield then state.overshield:Hide() end
        if state.absorbText then state.absorbText:Hide() end
        return
    end

    self:EnsureShieldObjects(state)
    self:ApplyNativeShieldStyle(state)
    if not state.overshield then return end

    local okAbsorb, totalAbsorbs = pcall(UnitGetTotalAbsorbs, state.spec.unit)
    if not okAbsorb or not canUseNumber(totalAbsorbs) then
        state.overshield:Hide()
        state.absorbText:Hide()
        return
    end

    local okRange, minimum, maximum = pcall(
        state.healthBar.GetMinMaxValues,
        state.healthBar
    )
    if okRange and canUseNumber(minimum) and canUseNumber(maximum) and maximum > minimum then
        safeMethod(state.overshield, "SetMinMaxValues", minimum, maximum)
        safeMethod(state.overshield, "SetValue", totalAbsorbs)
    else
        state.overshield:Hide()
    end

    if okRange
        and canUseNumber(maximum)
        and self:IsAbsorbClamped(state, totalAbsorbs)
    then
        state.overshield:Show()
    else
        state.overshield:Hide()
    end

    if mode == "clear_value"
        and canUseNumber(totalAbsorbs)
        and totalAbsorbs > 0
    then
        state.absorbText:SetText("+" .. abbreviate(totalAbsorbs))
        state.absorbText:Show()
    else
        state.absorbText:Hide()
    end
end

function Runtime:ApplyState(state)
    if not self.enabled or not state then return end
    self:ApplyColor(state)
    self:ApplyBackground(state)
    self:UpdateHealthText(state)
    self:UpdateShield(state)
end

function Runtime:RestoreNativeHealth(state)
    local color = state.nativeColor or state.originalColor
    if color then
        local desaturated = state.nativeDesaturated
        if desaturated == nil then desaturated = state.originalDesaturated end
        safeMethod(state.healthBar, "SetStatusBarDesaturated", desaturated == true)
        safeMethod(
            state.healthBar,
            "SetStatusBarColor",
            color.r,
            color.g,
            color.b,
            color.a or 1
        )
    end
    state.lastAppliedColor = nil
end

function Runtime:RestoreState(state, refreshNative)
    if not state then return end
    if state.background then state.background:Hide() end
    if state.healthText then state.healthText:Hide() end
    self:SetOriginalTextVisible(state, true)
    if state.overshield then state.overshield:Hide() end
    if state.absorbText then state.absorbText:Hide() end
    restoreTextureStyle(state.nativeAbsorbOverlay, state.nativeAbsorbStyle)
    if refreshNative then self:RestoreNativeHealth(state) end
end

function Runtime:RefreshAll(resetNative)
    self.suppressHooks = true
    for _, spec in ipairs(FRAME_SPECS) do
        local state = self:AcquireState(spec)
        if state and resetNative then self:RestoreState(state, true) end
    end
    self.suppressHooks = false

    if not self.enabled then return end
    for _, spec in ipairs(FRAME_SPECS) do
        self:ApplyState(self:AcquireState(spec))
    end
end

function Runtime:RefreshUnit(unit, resetNative)
    self.suppressHooks = true
    for _, spec in ipairs(FRAME_SPECS) do
        if spec.unit == unit then
            local state = self:AcquireState(spec)
            if state and resetNative then self:RestoreState(state, true) end
        end
    end
    self.suppressHooks = false
    if not self.enabled then return end
    for _, spec in ipairs(FRAME_SPECS) do
        if spec.unit == unit then self:ApplyState(self:AcquireState(spec)) end
    end
end

function Runtime:OnHealthBarUpdated(bar, unit)
    if not self.enabled or self.suppressHooks then return end
    local state = self.stateByBar[bar]
    if not state and type(unit) == "string" then
        for _, spec in ipairs(FRAME_SPECS) do
            if spec.unit == unit then
                local candidate = self:AcquireState(spec)
                if candidate and candidate.healthBar == bar then
                    state = candidate
                    break
                end
            end
        end
    end
    if state then
        local nativeColor = getStatusBarColor(bar)
        if nativeColor and not colorsMatch(nativeColor, state.lastAppliedColor) then
            state.nativeColor = nativeColor
            state.nativeDesaturated = getStatusBarDesaturated(bar)
        end
        self:ApplyColor(state)
        self:ApplyBackground(state)
        self:UpdateHealthText(state)
    end
end

function Runtime:OnHealPredictionUpdated(frame)
    if not self.enabled or self.suppressHooks then return end
    local state = self.stateByFrame[frame]
    if state and state.spec.shield then self:UpdateShield(state) end
end

local function callProfiledHook(detail, callback, ...)
    if not Runtime.enabled or Runtime.suppressHooks then return end
    if Addon.PerformanceDiagnostics.active == true then
        Addon.PerformanceDiagnostics:Call(
            Runtime,
            "hook",
            detail,
            "feature." .. FEATURE_ID .. "." .. detail,
            callback,
            Runtime,
            ...
        )
    else
        callback(Runtime, ...)
    end
end

function Runtime:InstallHooks()
    if self.hooksReady or type(hooksecurefunc) ~= "function" then return end

    if type(UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit)
            callProfiledHook("healthbar", Runtime.OnHealthBarUpdated, bar, unit)
        end)
    end
    if type(UnitFrameHealPredictionBars_Update) == "function" then
        hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
            callProfiledHook("shield", Runtime.OnHealPredictionUpdated, frame)
        end)
    end
    self.hooksReady = true
end

function Runtime:OnEvent(eventName, unit)
    if eventName == "PLAYER_TARGET_CHANGED" then
        self:RefreshUnit("target", true)
        self:RefreshUnit("targettarget", true)
    elseif eventName == "PLAYER_FOCUS_CHANGED" then
        self:RefreshUnit("focus", true)
        self:RefreshUnit("focustarget", true)
    elseif eventName == "UNIT_PET" then
        if unit == nil or unit == "player" then self:RefreshUnit("pet", true) end
    elseif eventName == "UNIT_TARGET" then
        if unit == "target" then
            self:RefreshUnit("targettarget", true)
        elseif unit == "focus" then
            self:RefreshUnit("focustarget", true)
        end
    elseif eventName == "UNIT_FACTION" or eventName == "UNIT_CONNECTION" then
        if type(unit) == "string" then self:RefreshUnit(unit, true) end
    else
        self:RefreshAll(true)
    end
end

function Runtime.EventHandler(eventName, ...)
    Runtime:OnEvent(eventName, ...)
end

function Runtime:QueueRefresh()
    local callback = function()
        if Runtime.enabled then Runtime:RefreshAll(true) end
    end
    if Addon.WoWApi:IsInCombatLockdown() then
        Addon.CombatQueue:RunOrQueue("feature." .. FEATURE_ID .. ".settings", callback)
    else
        callback()
    end
end

function Runtime:ReloadConfig()
    self.config.color_mode = setting("color_mode")
    self.config.health_text = setting("health_text")
    self.config.shield_mode = setting("shield_mode")
    self.config.dark_background = setting("dark_background") == true
end

function Runtime:OnSettingChanged()
    self:ReloadConfig()
    if self.enabled then self:QueueRefresh() end
end

function Runtime:OnSettingsReset()
    self:ReloadConfig()
    if self.enabled then self:QueueRefresh() end
end

function Runtime:OnEnable()
    self:ReloadConfig()
    self.enabled = true
    self:InstallHooks()
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED",
        "UNIT_PET",
        "UNIT_TARGET",
        "UNIT_FACTION",
        "UNIT_CONNECTION",
    }) do
        Addon.EventBus:Subscribe(eventName, self, Runtime.EventHandler)
    end
    self:RefreshAll(true)
end

function Runtime:OnDisable()
    self.enabled = false
    self.suppressHooks = true
    for _, state in pairs(self.states) do
        self:RestoreState(state, true)
    end
    self.suppressHooks = false
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    Addon.Logger:Write("ERROR", FEATURE_ID, "Feature runtime registration failed.")
end
