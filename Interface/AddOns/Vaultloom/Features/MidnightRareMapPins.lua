local _, Addon = ...

local FEATURE_ID = "midnight_rare_map_pins"
local PIN_TEMPLATE = "VaultloomMidnightRareWorldMapPinTemplate"
local PIN_ATLAS = "VignetteKill"
local PIN_FALLBACK = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare"
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local BASE_PIN_SIZE = 21

local DEFAULTS = {
    icon_scale_percent = 100,
    completed_mode = "hide",
}

local Runtime = {
    enabled = false,
    provider = nil,
    providerAdded = false,
    refreshGeneration = 0,
    preview = nil,
    lastPinCount = 0,
}

local function setting(key)
    local state = Addon.FeatureRegistry:GetState(FEATURE_ID)
    local value = state.settings[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

local function roundedPinSize()
    local percent = math.max(80, math.min(130, tonumber(setting("icon_scale_percent")) or 100))
    return math.max(16, math.floor((BASE_PIN_SIZE * percent / 100) + 0.5))
end

local function applyRareVisual(holder, completed, completedMode)
    if not holder then
        return
    end

    local size = roundedPinSize()
    if type(holder.SetSize) == "function" then
        holder:SetSize(size, size)
    end

    local icon = holder.Icon
    if icon then
        if type(icon.ClearAllPoints) == "function" then icon:ClearAllPoints() end
        if type(icon.SetAllPoints) == "function" then icon:SetAllPoints(holder) end
        local usedAtlas = false
        if type(icon.SetAtlas) == "function" then
            usedAtlas = pcall(icon.SetAtlas, icon, PIN_ATLAS, true) == true
        end
        if not usedAtlas and type(icon.SetTexture) == "function" then
            icon:SetTexture(PIN_FALLBACK)
            if type(icon.SetTexCoord) == "function" then icon:SetTexCoord(0, 1, 0, 1) end
        end
        if type(icon.SetDesaturated) == "function" then
            icon:SetDesaturated(completed == true)
        end
        if type(icon.SetAlpha) == "function" then
            icon:SetAlpha(completed and completedMode == "faded" and 0.42 or 1)
        end
        if type(icon.SetVertexColor) == "function" then
            icon:SetVertexColor(1, 1, 1, 1)
        end
    end

    local completedMark = holder.Completed
    if completedMark then
        if type(completedMark.SetTexture) == "function" then
            completedMark:SetTexture(CHECK_TEXTURE)
        end
        if type(completedMark.SetSize) == "function" then
            local markSize = math.max(9, math.floor((size * 0.52) + 0.5))
            completedMark:SetSize(markSize, markSize)
        end
        if type(completedMark.SetShown) == "function" then
            completedMark:SetShown(completed == true)
        elseif completed then
            completedMark:Show()
        else
            completedMark:Hide()
        end
    end
end

local function createMixin(...)
    if type(CreateFromMixins) == "function" then
        return CreateFromMixins(...)
    end
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if type(source) == "table" then
            for key, value in pairs(source) do result[key] = value end
        end
    end
    return result
end

local basePinMixin = type(MapCanvasPinMixin) == "table" and MapCanvasPinMixin or {}
local PinMixin = createMixin(basePinMixin)
_G.VaultloomMidnightRareWorldMapPinMixin = PinMixin

function PinMixin:SetPassThroughButtons()
end

function PinMixin:CheckMouseButtonPassthrough()
    return false
end

function PinMixin:OnLoad()
    self:SetSize(BASE_PIN_SIZE, BASE_PIN_SIZE)
    if type(self.RegisterForClicks) == "function" then
        self:RegisterForClicks("LeftButtonUp")
    end
    if type(self.UseFrameLevelType) == "function" then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    end
    if type(self.SetScalingLimits) == "function" then
        self:SetScalingLimits(1, 1, 1.35)
    end
end

function PinMixin:OnAcquired(rare)
    self.rare = rare
    applyRareVisual(self, rare and rare.completed == true, setting("completed_mode"))
    if type(self.SetScalingLimits) == "function" then
        self:SetScalingLimits(1, 1, 1.35)
    end
    if type(self.SetAlpha) == "function" then self:SetAlpha(1) end
    if type(self.SetPosition) == "function" then
        self:SetPosition(
            (tonumber(rare and rare.x) or 0) / 100,
            (tonumber(rare and rare.y) or 0) / 100
        )
    end
end

function PinMixin:OnReleased()
    self.rare = nil
end

function PinMixin:OnMouseEnter()
    local rare = self.rare
    if type(rare) ~= "table" or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end
    GameTooltip:AddLine(rare.name or rare.label or "", 1, 0.82, 0.12, true)
    if rare.zoneName and rare.zoneName ~= "" then
        GameTooltip:AddLine(rare.zoneName, 0.78, 0.78, 0.72, true)
    end
    GameTooltip:AddLine(
        string.format(
            Addon.L.PVE_RARES_COORDS_FORMAT or "Coordinates: %.1f, %.1f",
            tonumber(rare.x) or 0,
            tonumber(rare.y) or 0
        ),
        0.88,
        0.88,
        0.86,
        true
    )
    GameTooltip:AddLine(
        rare.completed and Addon.L.RARE_PINS_STATUS_DONE or Addon.L.RARE_PINS_STATUS_OPEN,
        rare.completed and 0.34 or 1,
        rare.completed and 0.86 or 0.82,
        rare.completed and 0.42 or 0.18,
        true
    )
    local resetSeconds = Addon.WoWApi:GetDailyResetInfo()
    GameTooltip:AddLine(
        string.format(
            Addon.L.RARE_PINS_TOOLTIP_RESET,
            Addon.WoWApi:FormatDurationShort(resetSeconds)
        ),
        0.72,
        0.72,
        0.68,
        true
    )
    GameTooltip:AddLine(Addon.L.RARE_PINS_TOOLTIP_HINT, 0.64, 0.74, 1, true)
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function PinMixin:OnMouseDown()
end

function PinMixin:OnMouseUp()
end

function PinMixin:OnClick(button)
    if button ~= "LeftButton" or type(self.rare) ~= "table" then
        return
    end
    Addon.PveRares:SetWaypoint(self.rare)
end

local function buildSnapshotLookup()
    local identity = Addon.StateStore:Get("character.identity")
    local snapshot = identity and identity.key and Addon.PveRares:GetSnapshot(identity.key) or nil
    local rares = {}
    for _, zone in ipairs(type(snapshot) == "table" and snapshot.zones or {}) do
        for _, rare in ipairs(type(zone) == "table" and zone.rares or {}) do
            local key = tonumber(rare.questID) or rare.key
            if key then rares[key] = rare end
        end
    end
    return rares
end

function Runtime:IsRareMap(mapID)
    mapID = tonumber(mapID)
    if not mapID then return false end
    for _, zone in ipairs(Addon.Data.PVE_RARES.zones or {}) do
        if tonumber(zone.mapID) == mapID then return true end
        for _, rare in ipairs(zone.rares or {}) do
            if tonumber(rare.mapID) == mapID then return true end
        end
    end
    return false
end

function Runtime:CollectPins(mapID)
    mapID = tonumber(mapID)
    if not mapID then return {} end

    local mode = setting("completed_mode")
    local snapshotRares = buildSnapshotLookup()
    local pins = {}
    for _, zone in ipairs(Addon.Data.PVE_RARES.zones or {}) do
        for _, definition in ipairs(zone.rares or {}) do
            local rareMapID = tonumber(definition.mapID) or tonumber(zone.mapID)
            if rareMapID == mapID then
                local questID = tonumber(definition.questID)
                local existing = snapshotRares[questID or definition.key]
                local completed = questID and Addon.QuestApi:IsCompleted(questID) or false
                if not completed and type(existing) == "table" and existing.completed == true then
                    completed = true
                end
                if not completed or mode ~= "hide" then
                    local fallbackName = type(existing) == "table" and existing.name or definition.name
                    pins[#pins + 1] = {
                        key = definition.key,
                        name = Addon.WoWApi:GetCreatureName(definition.npcID, fallbackName),
                        label = fallbackName,
                        npcID = tonumber(definition.npcID),
                        questID = questID,
                        mapID = rareMapID,
                        x = tonumber(definition.x) or 0,
                        y = tonumber(definition.y) or 0,
                        zoneName = Addon.WoWApi:GetMapName(rareMapID) or zone.label,
                        completed = completed == true,
                    }
                end
            end
        end
    end
    return pins
end

function Runtime:CreateProvider()
    if self.provider then return self.provider end
    if type(MapCanvasDataProviderMixin) ~= "table" then return nil end

    local provider = createMixin(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        local map = type(self.GetMap) == "function" and self:GetMap() or nil
        if map and type(map.RemoveAllPinsByTemplate) == "function" then
            map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
        end
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        Runtime.lastPinCount = 0
        if Runtime.enabled ~= true then return end

        local map = type(self.GetMap) == "function" and self:GetMap() or nil
        local mapID = map and type(map.GetMapID) == "function" and map:GetMapID() or nil
        if not mapID or not map or type(map.AcquirePin) ~= "function" then return end
        for _, rare in ipairs(Runtime:CollectPins(mapID)) do
            map:AcquirePin(PIN_TEMPLATE, rare)
            Runtime.lastPinCount = Runtime.lastPinCount + 1
        end
    end
    self.provider = provider
    return provider
end

function Runtime:EnsureProvider()
    if self.providerAdded then return true end
    local provider = self:CreateProvider()
    if not provider or not Addon.WorldMapPins:AddProvider(provider, self) then
        return false
    end
    self.providerAdded = true
    return true
end

function Runtime:RemoveProvider()
    if self.provider then Addon.WorldMapPins:RemoveProvider(self.provider) end
    self.providerAdded = false
    self.lastPinCount = 0
end

function Runtime:RequestRefresh(delay)
    if self.enabled ~= true or not Addon.WorldMapPins:IsShown() then
        return false
    end

    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local function refresh()
        if Runtime.enabled ~= true or Runtime.refreshGeneration ~= generation
            or not Addon.WorldMapPins:IsShown()
        then
            return
        end
        if Runtime:EnsureProvider() then
            Addon.WorldMapPins:RefreshProvider(Runtime.provider)
        end
    end
    delay = math.max(0, tonumber(delay) or 0)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, refresh)
    else
        refresh()
    end
    return true
end

function Runtime:OnWorldMapShown()
    self:RequestRefresh(0.05)
end

function Runtime:OnWorldMapHidden()
    self.refreshGeneration = self.refreshGeneration + 1
end

function Runtime:OnWorldMapChanged()
    self:RequestRefresh(0.05)
end

local function createPreviewSample(parent, x, y)
    local sample = CreateFrame("Frame", nil, parent)
    sample:SetPoint("CENTER", parent, "TOPLEFT", x, y)
    sample.Icon = sample:CreateTexture(nil, "ARTWORK")
    sample.Icon:SetAllPoints(sample)
    sample.Completed = sample:CreateTexture(nil, "OVERLAY")
    sample.Completed:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 3, -3)
    return sample
end

function Runtime:CreatePreview()
    local frame = CreateFrame(
        "Frame",
        "VaultloomMidnightRarePinPreview",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(470, 250)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -20)
    frame.title:SetPoint("TOPRIGHT", -58, -20)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)
    frame.title:SetText(Addon.L.RARE_PINS_PREVIEW_TITLE)

    frame.subtitle = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", 22, -49)
    frame.subtitle:SetPoint("TOPRIGHT", -22, -49)
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(Addon.L.RARE_PINS_PREVIEW_SUBTITLE)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.samples = {}
    local rows = {
        { key = "open", label = Addon.L.RARE_PINS_PREVIEW_OPEN, completed = false, mode = "shown" },
        { key = "faded", label = Addon.L.RARE_PINS_PREVIEW_FADED, completed = true, mode = "faded" },
        { key = "shown", label = Addon.L.RARE_PINS_PREVIEW_SHOWN, completed = true, mode = "shown" },
    }
    for index, definition in ipairs(rows) do
        local y = -105 - ((index - 1) * 52)
        local sample = createPreviewSample(frame, 54, y)
        sample.key = definition.key
        sample.label = Addon.Widgets:CreateLabel(frame, "GameFontHighlight", "LEFT")
        sample.label:SetPoint("LEFT", frame, "TOPLEFT", 92, y)
        sample.label:SetText(definition.label)
        applyRareVisual(sample, definition.completed, definition.mode)
        frame.samples[index] = sample
    end

    self.preview = frame
    frame:Hide()
end

function Runtime:RefreshPreview()
    if not self.preview or not self.preview:IsShown() then return end
    applyRareVisual(self.preview.samples[1], false, "shown")
    applyRareVisual(self.preview.samples[2], true, "faded")
    applyRareVisual(self.preview.samples[3], true, "shown")
end

function Runtime:TogglePreview()
    if not self.preview then self:CreatePreview() end
    if self.preview:IsShown() then
        self.preview:Hide()
    else
        self.preview:Show()
        if type(self.preview.Raise) == "function" then self.preview:Raise() end
        self:RefreshPreview()
    end
end

function Runtime:GetSettingValue(settingKey)
    if DEFAULTS[settingKey] == nil then return nil end
    return setting(settingKey)
end

function Runtime:SetSettingValue(settingKey, value)
    if DEFAULTS[settingKey] == nil then return false end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value
    self:RefreshPreview()
    if self.enabled then self:RequestRefresh(0) end
    return true
end

function Runtime:ResetSettingValues()
    self:RefreshPreview()
    if self.enabled then self:RequestRefresh(0) end
end

function Runtime:OnSettingsReset()
    self:RefreshPreview()
    self:RequestRefresh(0)
end

function Runtime:OnSettingsClosed()
    if self.preview then self.preview:Hide() end
end

function Runtime:OnAction(actionKey)
    if actionKey ~= "preview" then return false end
    self:TogglePreview()
    return true
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshGeneration = self.refreshGeneration + 1
    Addon.WorldMapPins:Activate(self)

    Addon.EventBus:Subscribe("ADDON_LOADED", self, function(_, addonName)
        if addonName == "Blizzard_WorldMap" then
            Addon.WorldMapPins:EnsureHooks()
            Runtime:RequestRefresh(0.05)
        end
    end)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        Runtime:RequestRefresh(0.15)
    end)
    Addon.EventBus:Subscribe("QUEST_LOG_UPDATE", self, function()
        if Runtime:IsRareMap(Addon.WorldMapPins:GetMapID()) then
            Runtime:RequestRefresh(0.20)
        end
    end)
    Addon.EventBus:Subscribe("QUEST_TURNED_IN", self, function(_, questID)
        if Addon.PveRares:IsQuestID(questID) then
            Runtime:RequestRefresh(0.05)
        end
    end)
    Addon.StateStore:Subscribe("pve.rares", self, function()
        Runtime:RequestRefresh(0.05)
    end)

    if Addon.WorldMapPins:IsShown() then self:OnWorldMapShown() end
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    Addon.WorldMapPins:Deactivate(self)
    self:RemoveProvider()
    if self.preview then self.preview:Hide() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Midnight Rare Map Pins runtime.")
end
