local _, Addon = ...

local FEATURE_ID = "stat_focus"

local MODE_PRESET = "preset"
local MODE_CUSTOM = "custom"

local DEFAULT_STAT_ORDER = { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }
local DOT_TEXTURE_TOKEN = "stat_focus_dot_"
local DOT_TEXTURES = {
    [1] = "stat_focus_dot_orange",
    [2] = "stat_focus_dot_purple",
    [3] = "stat_focus_dot_blue",
    [4] = "stat_focus_dot_green",
}

local STAT_DEFINITIONS = {
    CRIT = {
        fallback = "Critical Strike",
        globals = { "ITEM_MOD_CRIT_RATING_SHORT", "STAT_CRITICAL_STRIKE", "ITEM_MOD_CRIT_RATING" },
    },
    HASTE = {
        fallback = "Haste",
        globals = { "ITEM_MOD_HASTE_RATING_SHORT", "STAT_HASTE", "ITEM_MOD_HASTE_RATING" },
    },
    MASTERY = {
        fallback = "Mastery",
        globals = { "ITEM_MOD_MASTERY_RATING_SHORT", "STAT_MASTERY", "ITEM_MOD_MASTERY_RATING" },
    },
    VERSATILITY = {
        fallback = "Versatility",
        globals = { "ITEM_MOD_VERSATILITY", "STAT_VERSATILITY", "ITEM_MOD_VERSATILITY_RATING" },
    },
}

local STAT_ALIASES = {
    crit = "CRIT",
    critical = "CRIT",
    ["critical strike"] = "CRIT",
    krit = "CRIT",
    kritisch = "CRIT",
    critique = "CRIT",
    critico = "CRIT",
    ["crítico"] = "CRIT",
    ["крит"] = "CRIT",
    ["критический"] = "CRIT",
    ["치명타"] = "CRIT",
    ["극대화"] = "CRIT",
    ["爆击"] = "CRIT",
    ["暴击"] = "CRIT",
    ["致命一擊"] = "CRIT",
    ["致命"] = "CRIT",
    haste = "HASTE",
    tempo = "HASTE",
    ["hâte"] = "HASTE",
    celeridad = "HASTE",
    celerita = "HASTE",
    ["celerità"] = "HASTE",
    aceleracao = "HASTE",
    ["aceleração"] = "HASTE",
    ["скорость"] = "HASTE",
    ["가속"] = "HASTE",
    ["急速"] = "HASTE",
    ["加速"] = "HASTE",
    mastery = "MASTERY",
    meisterschaft = "MASTERY",
    maitrise = "MASTERY",
    ["maîtrise"] = "MASTERY",
    maestria = "MASTERY",
    ["maestría"] = "MASTERY",
    ["искусность"] = "MASTERY",
    ["특화"] = "MASTERY",
    ["精通"] = "MASTERY",
    vers = "VERSATILITY",
    versa = "VERSATILITY",
    versatility = "VERSATILITY",
    vielseitigkeit = "VERSATILITY",
    polyvalence = "VERSATILITY",
    versatilidad = "VERSATILITY",
    versatilita = "VERSATILITY",
    ["versatilità"] = "VERSATILITY",
    versatilidade = "VERSATILITY",
    ["универсальность"] = "VERSATILITY",
    ["유연성"] = "VERSATILITY",
    ["全能"] = "VERSATILITY",
    ["臨機應變"] = "VERSATILITY",
}

local RANK_COLORS = {
    [1] = { r = 1.00, g = 0.50, b = 0.00 },
    [2] = { r = 0.64, g = 0.21, b = 0.93 },
    [3] = { r = 0.00, g = 0.44, b = 0.87 },
    [4] = { r = 0.12, g = 1.00, b = 0.00 },
}

local DISPLAY_SETTING_KEYS = {
    tooltip_text = true,
    stat_colors = true,
    stat_dots = true,
}

local DISPLAY_SETTING_DEFAULTS = {
    tooltip_text = true,
    stat_colors = false,
    stat_dots = false,
}

local Runtime = {
    enabled = false,
    hooksReady = false,
    statLookup = nil,
    trackedTooltips = setmetatable({}, { __mode = "k" }),
}

Addon.StatFocus = Runtime

local function getCurrentContext()
    local classToken
    if type(UnitClass) == "function" then
        local _
        _, classToken = UnitClass("player")
    end

    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
    specIndex = tonumber(specIndex)
    if type(classToken) ~= "string" or classToken == "" or not specIndex or specIndex < 1 then
        return nil
    end

    local specID, specName
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
        local ok, resolvedID, resolvedName = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        if ok then
            specID = tonumber(resolvedID)
            specName = resolvedName
        end
    elseif type(GetSpecializationInfo) == "function" then
        local ok, resolvedID, resolvedName = pcall(GetSpecializationInfo, specIndex)
        if ok then
            specID = tonumber(resolvedID)
            specName = resolvedName
        end
    end

    return {
        classToken = classToken,
        specIndex = specIndex,
        specID = specID,
        specName = type(specName) == "string" and specName or nil,
        specKey = specID and tostring(specID) or (classToken .. ":" .. tostring(specIndex)),
    }
end

local function getCurrentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
    if type(identity) == "table" and type(identity.key) == "string" and identity.key ~= "" then
        return identity.key
    end
    if Addon.WoWApi and type(Addon.WoWApi.GetCurrentCharacterIdentity) == "function" then
        local current = Addon.WoWApi:GetCurrentCharacterIdentity()
        if type(current) == "table" and type(current.key) == "string" and current.key ~= "" then
            return current.key
        end
    end
    return "player"
end

local function getStore(create)
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    if create then
        db.features.statFocus = type(db.features.statFocus) == "table" and db.features.statFocus or {}
        db.features.statFocus.characters = type(db.features.statFocus.characters) == "table"
            and db.features.statFocus.characters or {}
        return db.features.statFocus
    end
    return type(db.features.statFocus) == "table" and db.features.statFocus or nil
end

local function getSpecRecord(create)
    local context = getCurrentContext()
    if not context then
        return nil, nil
    end
    local store = getStore(create)
    if type(store) ~= "table" then
        return nil, context
    end

    local characterKey = getCurrentCharacterKey()
    if create then
        store.characters[characterKey] = type(store.characters[characterKey]) == "table"
            and store.characters[characterKey] or {}
        store.characters[characterKey][context.specKey] = type(store.characters[characterKey][context.specKey]) == "table"
            and store.characters[characterKey][context.specKey] or {}
        return store.characters[characterKey][context.specKey], context
    end

    local characterStore = type(store.characters) == "table" and store.characters[characterKey] or nil
    return type(characterStore) == "table" and characterStore[context.specKey] or nil, context
end

local function getPreset(context)
    if not context or not Addon.StatFocusPresets then
        return nil
    end
    return Addon.StatFocusPresets:Get(context.specID, context.classToken, context.specIndex)
end

local function flattenTiers(tiers)
    local result = {}
    local seen = {}
    for _, tier in ipairs(tiers or {}) do
        for _, stat in ipairs(tier or {}) do
            if STAT_DEFINITIONS[stat] and not seen[stat] then
                result[#result + 1] = stat
                seen[stat] = true
            end
        end
    end
    return result
end

local function copyFlatStatsToTiers(stats)
    if type(stats) ~= "table" then
        return nil
    end
    local tiers = {}
    for _, stat in ipairs(stats) do
        if STAT_DEFINITIONS[stat] then
            tiers[#tiers + 1] = { stat }
        end
    end
    return #tiers > 0 and tiers or nil
end

local function normalizeCustomOrder(stats, fallbackTiers)
    local order = {}
    local seen = {}
    for _, stat in ipairs(stats or {}) do
        if STAT_DEFINITIONS[stat] and not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    for _, stat in ipairs(flattenTiers(fallbackTiers)) do
        if not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    for _, stat in ipairs(DEFAULT_STAT_ORDER) do
        if not seen[stat] then
            order[#order + 1] = stat
            seen[stat] = true
        end
    end
    return #order == 4 and order or nil
end

local function buildRankMap(tiers)
    local rankMap = {}
    for rank, tier in ipairs(tiers or {}) do
        local color = RANK_COLORS[rank] or RANK_COLORS[#RANK_COLORS]
        for _, stat in ipairs(tier or {}) do
            if STAT_DEFINITIONS[stat] and not rankMap[stat] then
                rankMap[stat] = {
                    rank = rank,
                    color = color,
                }
            end
        end
    end
    return rankMap
end

local function clampColorChannel(value)
    value = tonumber(value) or 0
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
end

local function colorToHex(color)
    color = color or RANK_COLORS[4]
    return string.format(
        "|cff%02x%02x%02x",
        clampColorChannel(color.r),
        clampColorChannel(color.g),
        clampColorChannel(color.b)
    )
end

local function colorText(text, color)
    return colorToHex(color) .. tostring(text or "") .. "|r"
end

local function getStatLabel(stat)
    local definition = STAT_DEFINITIONS[stat]
    if not definition then
        return tostring(stat or "")
    end
    for _, globalName in ipairs(definition.globals or {}) do
        local value = _G[globalName]
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return definition.fallback
end

local function formatTierSummary(tiers)
    local tierParts = {}
    for rank, tier in ipairs(tiers or {}) do
        local statParts = {}
        local color = RANK_COLORS[rank] or RANK_COLORS[#RANK_COLORS]
        for _, stat in ipairs(tier or {}) do
            statParts[#statParts + 1] = colorText(getStatLabel(stat), color)
        end
        if #statParts > 0 then
            tierParts[#tierParts + 1] = table.concat(statParts, " = ")
        end
    end
    return table.concat(tierParts, " > ")
end

local function buildStatLookup()
    local lookup = {}
    for stat, definition in pairs(STAT_DEFINITIONS) do
        for _, globalName in ipairs(definition.globals or {}) do
            local value = _G[globalName]
            if type(value) == "string" and value ~= "" then
                lookup[value] = stat
            end
        end
        lookup[definition.fallback] = stat
    end
    return lookup
end

local function findStatInText(text, lookup)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    for localizedStat, stat in pairs(lookup or {}) do
        local ok, found = pcall(string.find, text, localizedStat, 1, true)
        if ok and found then
            return stat
        end
    end
    return nil
end

local function getDotTexture(rankInfo)
    local fileName = DOT_TEXTURES[rankInfo and rankInfo.rank or 4] or DOT_TEXTURES[4]
    local path = "Interface\\AddOns\\" .. tostring(Addon.name) .. "\\Assets\\" .. fileName
    return string.format("|T%s:9:9:0:0|t", path)
end

local function parseStatToken(raw)
    raw = tostring(raw or ""):lower()
    raw = raw:gsub("[,;>]+", "")
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    return STAT_ALIASES[raw]
end

local function splitWords(message)
    local words = {}
    for word in tostring(message or ""):gmatch("%S+") do
        words[#words + 1] = word
    end
    return words
end

function Runtime:GetPreset()
    return getPreset(getCurrentContext())
end

function Runtime:GetCurrentMode()
    local record = getSpecRecord(false)
    return type(record) == "table" and record.mode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
end

function Runtime:SetCurrentMode(mode)
    mode = mode == MODE_CUSTOM and MODE_CUSTOM or MODE_PRESET
    local record, context = getSpecRecord(true)
    if not record or not context then
        return MODE_PRESET
    end
    record.mode = mode
    if mode == MODE_CUSTOM then
        local preset = getPreset(context)
        record.order = normalizeCustomOrder(record.order, preset and preset.tiers)
    end
    self:RefreshTrackedTooltips()
    return mode
end

function Runtime:GetCustomTiers()
    local record, context = getSpecRecord(false)
    if type(record) ~= "table" then
        return nil
    end
    local preset = getPreset(context)
    local order = normalizeCustomOrder(record.order, preset and preset.tiers)
    if not order then
        return nil
    end
    record.order = order
    return copyFlatStatsToTiers(order)
end

function Runtime:SetCustomOrder(stats)
    local record, context = getSpecRecord(true)
    if not record or not context then
        return nil
    end
    local preset = getPreset(context)
    local order = normalizeCustomOrder(stats, preset and preset.tiers)
    if not order then
        return nil
    end
    record.mode = MODE_CUSTOM
    record.order = order
    self:RefreshTrackedTooltips()
    return order
end

function Runtime:ClearCustomOrder()
    local record = getSpecRecord(false)
    if type(record) == "table" then
        record.mode = MODE_PRESET
        record.order = nil
    end
    self:RefreshTrackedTooltips()
end

function Runtime:GetActiveTiers()
    local context = getCurrentContext()
    local preset = getPreset(context)
    if self:GetCurrentMode() == MODE_CUSTOM then
        local custom = self:GetCustomTiers()
        if custom then
            return custom, MODE_CUSTOM, preset, context
        end
    end
    return preset and preset.tiers or nil, MODE_PRESET, preset, context
end

function Runtime:GetSummaryText()
    local tiers, mode, _, context = self:GetActiveTiers()
    if not tiers then
        return Addon.L.FEATURE_STAT_FOCUS_NO_SPEC
    end
    local modeLabel = mode == MODE_CUSTOM
        and Addon.L.FEATURE_VALUE_CUSTOM
        or Addon.L.FEATURE_VALUE_PRESET
    local contextLabel = context and context.specName
    local prefix = contextLabel and (modeLabel .. " - " .. contextLabel) or modeLabel
    return prefix .. ": " .. formatTierSummary(tiers)
end

function Runtime:GetSettingValue(settingKey)
    if settingKey == "priority_mode" then
        return self:GetCurrentMode()
    end
    if DISPLAY_SETTING_KEYS[settingKey] then
        local saved = Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
        if saved == nil then
            return DISPLAY_SETTING_DEFAULTS[settingKey]
        end
        return saved == true
    end
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey == "priority_mode" then
        self:SetCurrentMode(value)
        return true
    end
    if DISPLAY_SETTING_KEYS[settingKey] then
        Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value == true
        self:EnsureVisibleDisplay(settingKey)
        if self.enabled == true then
            self:RefreshTrackedTooltips()
        end
        return true
    end
    return false
end

function Runtime:ResetSettingValues()
    self:ClearCustomOrder()
end

local function restoreLineHints(tooltip)
    local states = tooltip and tooltip.VaultloomStatFocusLineStates or nil
    for _, state in ipairs(states or {}) do
        if state.line then
            if state.text ~= nil and type(state.line.SetText) == "function" then
                state.line:SetText(state.text)
            end
            if state.color and type(state.line.SetTextColor) == "function" then
                state.line:SetTextColor(unpack(state.color))
            end
        end
    end
    if tooltip then
        tooltip.VaultloomStatFocusLineStates = nil
    end
end

function Runtime:RestoreTooltip(tooltip, rebuild)
    if not tooltip then
        return
    end
    restoreLineHints(tooltip)
    local hadSummary = tooltip.VaultloomStatFocusSummary == true
    tooltip.VaultloomStatFocusRendered = nil
    tooltip.VaultloomStatFocusSummary = nil

    if rebuild and hadSummary and type(tooltip.GetItem) == "function"
        and type(tooltip.ClearLines) == "function" and type(tooltip.SetHyperlink) == "function"
    then
        local okItem, _, itemLink = pcall(tooltip.GetItem, tooltip)
        local shown = type(tooltip.IsShown) ~= "function" or tooltip:IsShown()
        if okItem and type(itemLink) == "string" and itemLink ~= "" and shown then
            pcall(function()
                tooltip:ClearLines()
                tooltip:SetHyperlink(itemLink)
            end)
        end
    end
end

function Runtime:RefreshTrackedTooltips()
    for tooltip in pairs(self.trackedTooltips) do
        self:RestoreTooltip(tooltip, true)
    end
end

local function ensureTooltipResetHook(tooltip)
    if not tooltip or tooltip.VaultloomStatFocusClearHook then
        return
    end
    if type(tooltip.HookScript) == "function" then
        tooltip:HookScript("OnTooltipCleared", function(self)
            restoreLineHints(self)
            self.VaultloomStatFocusRendered = nil
            self.VaultloomStatFocusSummary = nil
        end)
        tooltip.VaultloomStatFocusClearHook = true
    end
end

function Runtime:ApplyLineHints(tooltip, rankMap, colorLines, addDots)
    local tooltipName = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if type(tooltipName) ~= "string" or tooltipName == "" then
        return
    end

    self.statLookup = self.statLookup or buildStatLookup()
    local states = {}
    local lineCount = type(tooltip.NumLines) == "function" and tonumber(tooltip:NumLines()) or 0
    for index = 2, lineCount do
        local line = _G[tooltipName .. "TextLeft" .. tostring(index)]
        if line and type(line.GetText) == "function" then
            local okText, text = pcall(line.GetText, line)
            local stat = okText and findStatInText(text, self.statLookup) or nil
            local rankInfo = stat and rankMap[stat] or nil
            if rankInfo and rankInfo.color then
                local originalColor
                if type(line.GetTextColor) == "function" then
                    local okColor, r, g, b, a = pcall(line.GetTextColor, line)
                    if okColor then
                        originalColor = { r, g, b, a }
                    end
                end
                states[#states + 1] = {
                    line = line,
                    text = text,
                    color = originalColor,
                }
                if colorLines and type(line.SetTextColor) == "function" then
                    line:SetTextColor(rankInfo.color.r, rankInfo.color.g, rankInfo.color.b, 1)
                end
                local hasDot = false
                if addDots then
                    local okDot, dotPosition = pcall(string.find, text, DOT_TEXTURE_TOKEN, 1, true)
                    hasDot = okDot and dotPosition ~= nil
                end
                if addDots and type(line.SetText) == "function" and not hasDot then
                    line:SetText(text .. "  " .. getDotTexture(rankInfo))
                end
            end
        end
    end
    tooltip.VaultloomStatFocusLineStates = #states > 0 and states or nil
end

function Runtime:AddSummary(tooltip, tiers, contextual)
    local header = Addon.L.FEATURE_STAT_FOCUS_TOOLTIP_HEADER
    tooltip:AddLine(" ")
    tooltip:AddLine(header, 1, 0.82, 0.24, true)
    tooltip:AddLine(formatTierSummary(tiers), 1, 1, 1, true)
    if contextual then
        tooltip:AddLine(Addon.L.FEATURE_STAT_FOCUS_CONTEXT_NOTE, 0.72, 0.68, 0.58, true)
    end
    tooltip.VaultloomStatFocusSummary = true
end

function Runtime:ApplyTooltip(tooltip)
    if self.enabled ~= true or not tooltip or tooltip.VaultloomStatFocusRendered then
        return
    end

    local tiers, _, preset = self:GetActiveTiers()
    if not tiers then
        return
    end
    local rankMap = buildRankMap(tiers)
    local showText = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "tooltip_text") == true
    local colorLines = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_colors") == true
    local addDots = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_dots") == true
    if not showText and not colorLines and not addDots then
        return
    end

    ensureTooltipResetHook(tooltip)
    tooltip.VaultloomStatFocusRendered = true
    self.trackedTooltips[tooltip] = true

    if colorLines or addDots then
        self:ApplyLineHints(tooltip, rankMap, colorLines, addDots)
    end
    if showText then
        self:AddSummary(tooltip, tiers, preset and preset.contextual == true)
    end
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return
    end
    self.hooksReady = true

    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            Runtime:ApplyTooltip(tooltip)
        end)
        return
    end
    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            Runtime:ApplyTooltip(tooltip)
        end)
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:EnsureVisibleDisplay("tooltip_text")
    self:EnsureHooks()
end

function Runtime:OnDisable()
    self.enabled = false
    for tooltip in pairs(self.trackedTooltips) do
        self:RestoreTooltip(tooltip, true)
    end
end

function Runtime:EnsureVisibleDisplay(preferredSetting)
    local showText = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "tooltip_text") == true
    local colorLines = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_colors") == true
    local addDots = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "stat_dots") == true
    if showText or colorLines or addDots then
        return true
    end

    local settingKey = DISPLAY_SETTING_KEYS[preferredSetting] and preferredSetting or "tooltip_text"
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = true
    return false
end

function Runtime:OnSettingChanged(settingKey)
    if DISPLAY_SETTING_KEYS[settingKey] then
        self:EnsureVisibleDisplay(settingKey)
    end
    self:RefreshTrackedTooltips()
end

function Runtime:OnSettingsReset()
    self:RefreshTrackedTooltips()
end

function Runtime:HandleSlash(message)
    local words = splitWords(message)
    local first = words[1] and words[1]:lower() or ""

    if first == "" or first == "show" or first == "status" then
        Addon:Print(self:GetSummaryText())
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_SLASH_HELP)
        return true
    end
    if first == "preset" or first == "auto" or first == "预设" or first == "自动" or first == "預設" or first == "自動" then
        self:SetCurrentMode(MODE_PRESET)
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_PRESET_ENABLED)
        Addon:Print(self:GetSummaryText())
        return true
    end
    if first == "reset" or first == "clear" or first == "重置" or first == "重設" or first == "清除" then
        self:ClearCustomOrder()
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_CUSTOM_CLEARED)
        Addon:Print(self:GetSummaryText())
        return true
    end

    local parsed = {}
    local startIndex = (
        first == "custom"
        or first == "eigen"
        or first == "personnalise"
        or first == "personnalisé"
        or first == "personalizado"
        or first == "personalizada"
        or first == "свой"
        or first == "своя"
        or first == "사용자"
        or first == "사용자지정"
        or first == "自定义"
        or first == "自訂"
    ) and 2 or 1
    for index = startIndex, #words do
        local stat = parseStatToken(words[index])
        if stat then
            parsed[#parsed + 1] = stat
        end
    end
    if #parsed > 0 and self:SetCustomOrder(parsed) then
        Addon:Print(Addon.L.FEATURE_STAT_FOCUS_CUSTOM_SAVED)
        Addon:Print(self:GetSummaryText())
        return true
    end

    Addon:Print(Addon.L.FEATURE_STAT_FOCUS_SLASH_HELP)
    return true
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Stat Focus feature runtime.")
end
