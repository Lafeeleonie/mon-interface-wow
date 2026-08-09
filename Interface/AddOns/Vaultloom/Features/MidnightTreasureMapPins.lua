local _, Addon = ...

local FEATURE_ID = "midnight_treasure_map_pins"
local PIN_TEMPLATE = "VaultloomMidnightTreasureWorldMapPinTemplate"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MASK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local BASE_PIN_SIZE = 21

local DATA = Addon.Data.MIDNIGHT_TREASURES or {
    nodes = {},
    byMapID = {},
    questIDs = {},
    mapIDs = {},
    counts = {},
    professionByKey = {},
    professionBySkillLineID = {},
}

local DEFAULTS = {
    icon_scale_percent = 100,
    completed_mode = "hide",
    show_treasures = true,
    show_professions = true,
    show_rituals = true,
    show_delves = true,
    only_current_professions = true,
}

local KIND_SETTING = {
    treasure = "show_treasures",
    profession = "show_professions",
    ritual = "show_rituals",
    delve = "show_delves",
}

local KIND_VISUALS = {
    treasure = {
        atlas = "VignetteLoot",
        fallback = "Interface\\Icons\\INV_Misc_TreasureChest01",
        ring = { 1.00, 0.76, 0.18, 1 },
    },
    profession = {
        fallback = "Interface\\Icons\\INV_Misc_Note_01",
        ring = { 0.96, 0.63, 0.16, 1 },
    },
    ritual = {
        fallback = "Interface\\Icons\\Spell_Shadow_Rune",
        ring = { 0.86, 0.53, 0.18, 1 },
    },
    delve = {
        fallback = "Interface\\Icons\\INV_Misc_TreasureChest05B",
        ring = { 0.72, 0.52, 0.25, 1 },
    },
}

local Runtime = {
    enabled = false,
    provider = nil,
    providerAdded = false,
    refreshGeneration = 0,
    preview = nil,
    lastPinCount = 0,
}

Addon.MidnightTreasureMapPins = Runtime

local requestedQuestTitles = {}

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

local function addCircularMask(owner, texture, storageKey)
    if not owner or not texture or owner[storageKey]
        or type(owner.CreateMaskTexture) ~= "function"
        or type(texture.AddMaskTexture) ~= "function"
    then
        return
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    owner[storageKey] = mask
end

local function getProfessionSpellIcon(professionKey)
    local definition = DATA.professionByKey[professionKey]
    local spellID = definition and tonumber(definition.spellID)
    if not spellID then return nil end

    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then return icon end
    end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and info.iconID then return info.iconID end
    end
    if type(GetSpellInfo) == "function" then
        local ok, _, _, icon = pcall(GetSpellInfo, spellID)
        if ok and icon then return icon end
    end
    return nil
end

local function getCurrentProfessions()
    local result = {}
    local professions = Addon.WoWApi:GetCurrentProfessions()
    if type(professions) ~= "table" then
        return result, false
    end
    for _, profession in ipairs(professions) do
        local key = DATA.professionBySkillLineID[tonumber(profession.skillLineID)]
        if key then
            result[key] = {
                key = key,
                name = profession.name,
                icon = profession.icon,
            }
        end
    end
    return result, true
end

local function getProfessionDetails(professionKey, currentProfessions)
    local current = type(currentProfessions) == "table" and currentProfessions[professionKey] or nil
    local definition = DATA.professionByKey[professionKey]
    local fallbackName = tostring(professionKey or "")
    if definition and definition.spellID then
        fallbackName = Addon.WoWApi:GetSpellName(definition.spellID, fallbackName) or fallbackName
    end
    return {
        name = type(current) == "table" and current.name or fallbackName,
        icon = type(current) == "table" and current.icon or getProfessionSpellIcon(professionKey),
    }
end

local function isCompleted(node)
    if type(node) ~= "table" then return false end
    local questID = tonumber(node.questID)
    if not questID then return false end
    if Addon.QuestApi:IsCompleted(questID) then return true end
    if node.kind ~= "profession" then
        return Addon.QuestApi:IsCompletedOnAccount(questID)
    end
    return false
end

local function isKindEnabled(kind)
    local settingKey = KIND_SETTING[kind]
    return settingKey ~= nil and setting(settingKey) == true
end

local function shouldIncludeProfession(node, currentProfessions, professionApiReady)
    if node.kind ~= "profession" or setting("only_current_professions") ~= true then
        return true
    end
    if professionApiReady ~= true then
        return true
    end
    return currentProfessions[node.professionKey] ~= nil
end

local function requestQuestTitle(questID)
    questID = tonumber(questID)
    if not questID or requestedQuestTitles[questID] then return end
    requestedQuestTitles[questID] = true
    if C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(C_QuestLog.RequestLoadQuestByID, questID)
    end
end

local function applyTreasureVisual(holder, treasure, completedMode)
    if not holder or type(treasure) ~= "table" then return end

    local size = roundedPinSize()
    local visual = KIND_VISUALS[treasure.kind] or KIND_VISUALS.treasure
    if type(holder.SetSize) == "function" then holder:SetSize(size, size) end

    local ring = holder.Ring
    if ring then
        ring:ClearAllPoints()
        ring:SetAllPoints(holder)
        ring:SetTexture(WHITE_TEXTURE)
        ring:SetVertexColor(visual.ring[1], visual.ring[2], visual.ring[3], visual.ring[4])
        ring:SetAlpha(treasure.completed and completedMode == "faded" and 0.55 or 1)
        addCircularMask(holder, ring, "treasureRingMask")
    end

    local icon = holder.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
        local iconSize = math.max(12, size - 4)
        icon:SetSize(iconSize, iconSize)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetVertexColor(1, 1, 1, 1)
        local usedAtlas = false
        if treasure.professionIcon then
            icon:SetTexture(treasure.professionIcon)
        elseif visual.atlas and type(icon.SetAtlas) == "function" then
            usedAtlas = pcall(icon.SetAtlas, icon, visual.atlas, false) == true
        end
        if not treasure.professionIcon and not usedAtlas then
            icon:SetTexture(visual.fallback)
        end
        icon:SetDesaturated(treasure.completed == true)
        icon:SetAlpha(treasure.completed and completedMode == "faded" and 0.42 or 1)
        addCircularMask(holder, icon, "treasureIconMask")
    end

    local completedMark = holder.Completed
    if completedMark then
        completedMark:SetTexture(CHECK_TEXTURE)
        local markSize = math.max(9, math.floor((size * 0.52) + 0.5))
        completedMark:SetSize(markSize, markSize)
        completedMark:SetShown(treasure.completed == true)
    end
end

local basePinMixin = type(MapCanvasPinMixin) == "table" and MapCanvasPinMixin or {}
local PinMixin = createMixin(basePinMixin)
_G.VaultloomMidnightTreasureWorldMapPinMixin = PinMixin

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

function PinMixin:OnAcquired(treasure)
    self.treasure = treasure
    applyTreasureVisual(self, treasure, setting("completed_mode"))
    if type(self.SetAlpha) == "function" then self:SetAlpha(1) end
    if type(self.SetPosition) == "function" then
        self:SetPosition(
            (tonumber(treasure and treasure.x) or 0) / 100,
            (tonumber(treasure and treasure.y) or 0) / 100
        )
    end
end

function PinMixin:OnReleased()
    self.treasure = nil
end

function PinMixin:OnMouseEnter()
    local treasure = self.treasure
    if type(treasure) ~= "table" or not GameTooltip then return end

    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end
    GameTooltip:AddLine(treasure.name or treasure.fallbackName or "", 1, 0.82, 0.12, true)
    local kindLabel = Addon.L["TREASURE_PINS_KIND_" .. string.upper(treasure.kind or "treasure")]
        or treasure.kind
    if treasure.professionName and treasure.professionName ~= "" then
        kindLabel = string.format("%s: %s", kindLabel, treasure.professionName)
    end
    GameTooltip:AddLine(kindLabel, 0.88, 0.72, 0.36, true)
    if treasure.zoneName and treasure.zoneName ~= "" then
        GameTooltip:AddLine(treasure.zoneName, 0.78, 0.78, 0.72, true)
    end
    GameTooltip:AddLine(
        string.format(
            Addon.L.PVE_RARES_COORDS_FORMAT or "Coordinates: %.1f, %.1f",
            tonumber(treasure.x) or 0,
            tonumber(treasure.y) or 0
        ),
        0.88,
        0.88,
        0.86,
        true
    )
    GameTooltip:AddLine(
        treasure.completed and Addon.L.TREASURE_PINS_STATUS_DONE or Addon.L.TREASURE_PINS_STATUS_OPEN,
        treasure.completed and 0.34 or 1,
        treasure.completed and 0.86 or 0.82,
        treasure.completed and 0.42 or 0.18,
        true
    )
    GameTooltip:AddLine(Addon.L.TREASURE_PINS_TOOLTIP_HINT, 0.64, 0.74, 1, true)
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function PinMixin:OnMouseDown()
end

function PinMixin:OnMouseUp()
end

function Runtime:SetWaypoint(treasure)
    if type(treasure) ~= "table" or not C_Map
        or type(C_Map.SetUserWaypoint) ~= "function"
        or not UiMapPoint
        or type(UiMapPoint.CreateFromCoordinates) ~= "function"
    then
        return false
    end
    local mapID = tonumber(treasure.mapID)
    local x, y = tonumber(treasure.x), tonumber(treasure.y)
    if not mapID or not x or not y then return false end

    local okPoint, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x / 100, y / 100)
    if not okPoint or not point then return false end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok == true
end

function PinMixin:OnClick(button)
    if button == "LeftButton" and type(self.treasure) == "table" then
        Runtime:SetWaypoint(self.treasure)
    end
end

function Runtime:IsTreasureMap(mapID)
    return DATA.mapIDs[tonumber(mapID)] == true
end

function Runtime:CollectPins(mapID)
    mapID = tonumber(mapID)
    local definitions = mapID and DATA.byMapID[mapID] or nil
    if type(definitions) ~= "table" then return {} end

    local mode = setting("completed_mode")
    local currentProfessions, professionApiReady = getCurrentProfessions()
    local pins = {}
    for _, definition in ipairs(definitions) do
        if isKindEnabled(definition.kind)
            and shouldIncludeProfession(definition, currentProfessions, professionApiReady)
        then
            local completed = isCompleted(definition)
            if not completed or mode ~= "hide" then
                requestQuestTitle(definition.questID)
                local profession = definition.professionKey
                    and getProfessionDetails(definition.professionKey, currentProfessions)
                    or nil
                pins[#pins + 1] = {
                    key = definition.key,
                    questID = definition.questID,
                    kind = definition.kind,
                    professionKey = definition.professionKey,
                    professionName = profession and profession.name or nil,
                    professionIcon = profession and profession.icon or nil,
                    fallbackName = definition.fallbackName,
                    name = Addon.QuestApi:GetTitle(definition.questID, definition.fallbackName),
                    mapID = definition.mapID,
                    zoneName = Addon.WoWApi:GetMapName(definition.mapID) or "",
                    x = definition.x,
                    y = definition.y,
                    completed = completed == true,
                }
            end
        end
    end
    return pins
end

function Runtime:GetProgress()
    local currentProfessions, professionApiReady = getCurrentProfessions()
    local progress = {
        treasure = { completed = 0, total = 0 },
        profession = { completed = 0, total = 0 },
        ritual = { completed = 0, total = 0 },
        delve = { completed = 0, total = 0 },
    }
    for _, node in ipairs(DATA.nodes or {}) do
        if shouldIncludeProfession(node, currentProfessions, professionApiReady) then
            local bucket = progress[node.kind]
            if bucket then
                bucket.total = bucket.total + 1
                if isCompleted(node) then bucket.completed = bucket.completed + 1 end
            end
        end
    end
    return progress
end

function Runtime:GetProgressSummary()
    local progress = self:GetProgress()
    local parts = {}
    for _, kind in ipairs({ "treasure", "profession", "ritual", "delve" }) do
        local bucket = progress[kind]
        if bucket and bucket.total > 0 then
            local label = Addon.L["TREASURE_PINS_PROGRESS_" .. string.upper(kind)] or kind
            parts[#parts + 1] = string.format("%s %d/%d", label, bucket.completed, bucket.total)
        end
    end
    return table.concat(parts, "  |  ")
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
        for _, treasure in ipairs(Runtime:CollectPins(mapID)) do
            map:AcquirePin(PIN_TEMPLATE, treasure)
            Runtime.lastPinCount = Runtime.lastPinCount + 1
        end
    end
    self.provider = provider
    return provider
end

function Runtime:EnsureProvider()
    if self.providerAdded then return true end
    local provider = self:CreateProvider()
    if not provider or not Addon.WorldMapPins:AddProvider(provider, self) then return false end
    self.providerAdded = true
    return true
end

function Runtime:RemoveProvider()
    if self.provider then Addon.WorldMapPins:RemoveProvider(self.provider) end
    self.providerAdded = false
    self.lastPinCount = 0
end

function Runtime:RequestRefresh(delay)
    if self.enabled ~= true or not Addon.WorldMapPins:IsShown() then return false end
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
    sample.Ring = sample:CreateTexture(nil, "BACKGROUND")
    sample.Ring:SetAllPoints(sample)
    sample.Icon = sample:CreateTexture(nil, "ARTWORK")
    sample.Icon:SetPoint("CENTER")
    sample.Completed = sample:CreateTexture(nil, "OVERLAY")
    sample.Completed:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 3, -3)
    return sample
end

function Runtime:CreatePreview()
    local frame = CreateFrame(
        "Frame",
        "VaultloomMidnightTreasurePinPreview",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(590, 350)
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
    frame.title:SetText(Addon.L.TREASURE_PINS_PREVIEW_TITLE)

    frame.subtitle = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", 22, -49)
    frame.subtitle:SetPoint("TOPRIGHT", -22, -49)
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(Addon.L.TREASURE_PINS_PREVIEW_SUBTITLE)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.openHeader = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "LEFT")
    frame.openHeader:SetPoint("TOPLEFT", 44, -89)
    frame.openHeader:SetText(Addon.L.TREASURE_PINS_PREVIEW_OPEN)
    frame.doneHeader = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "LEFT")
    frame.doneHeader:SetPoint("TOPLEFT", 340, -89)
    frame.doneHeader:SetText(Addon.L.TREASURE_PINS_PREVIEW_DONE)

    frame.samples = {}
    local rows = {
        { kind = "treasure" },
        { kind = "profession", professionKey = "alchemy" },
        { kind = "ritual" },
        { kind = "delve" },
    }
    for index, definition in ipairs(rows) do
        local y = -137 - ((index - 1) * 56)
        local profession = definition.professionKey
            and getProfessionDetails(definition.professionKey, {})
            or nil
        local sampleData = {
            kind = definition.kind,
            professionKey = definition.professionKey,
            professionIcon = profession and profession.icon or nil,
            completed = false,
        }
        local open = createPreviewSample(frame, 58, y)
        open.label = Addon.Widgets:CreateLabel(frame, "GameFontHighlight", "LEFT")
        open.label:SetPoint("LEFT", frame, "TOPLEFT", 92, y)
        open.label:SetText(Addon.L["TREASURE_PINS_KIND_" .. string.upper(definition.kind)])
        applyTreasureVisual(open, sampleData, "shown")

        local doneData = {
            kind = definition.kind,
            professionKey = definition.professionKey,
            professionIcon = profession and profession.icon or nil,
            completed = true,
        }
        local done = createPreviewSample(frame, 356, y)
        done.label = Addon.Widgets:CreateLabel(frame, "GameFontHighlight", "LEFT")
        done.label:SetPoint("LEFT", frame, "TOPLEFT", 390, y)
        applyTreasureVisual(done, doneData, setting("completed_mode"))
        frame.samples[#frame.samples + 1] = {
            open = open,
            done = done,
            doneData = doneData,
        }
    end

    self.preview = frame
    frame:Hide()
end

function Runtime:RefreshPreview()
    if not self.preview or not self.preview:IsShown() then return end
    local mode = setting("completed_mode")
    for _, samples in ipairs(self.preview.samples) do
        applyTreasureVisual(samples.open, {
            kind = samples.doneData.kind,
            professionKey = samples.doneData.professionKey,
            professionIcon = samples.doneData.professionIcon,
            completed = false,
        }, "shown")
        applyTreasureVisual(samples.done, samples.doneData, mode)
        local hidden = mode == "hide"
        samples.done:SetShown(not hidden)
        samples.done.label:SetText(
            hidden and Addon.L.TREASURE_PINS_PREVIEW_HIDDEN
                or (mode == "faded" and Addon.L.TREASURE_PINS_PREVIEW_FADED
                    or Addon.L.TREASURE_PINS_PREVIEW_SHOWN)
        )
    end
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
        if Runtime:IsTreasureMap(Addon.WorldMapPins:GetMapID()) then
            Runtime:RequestRefresh(0.20)
        end
    end)
    Addon.EventBus:Subscribe("QUEST_TURNED_IN", self, function(_, questID)
        if DATA.questIDs[tonumber(questID)] then Runtime:RequestRefresh(0.05) end
    end)
    Addon.EventBus:Subscribe("QUEST_DATA_LOAD_RESULT", self, function(_, questID)
        if DATA.questIDs[tonumber(questID)] then Runtime:RequestRefresh(0.05) end
    end)
    Addon.EventBus:Subscribe("SKILL_LINES_CHANGED", self, function()
        Runtime:RequestRefresh(0.10)
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
    error("Vaultloom could not register the Midnight Treasure Map Pins runtime.")
end
