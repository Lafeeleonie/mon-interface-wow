local _, Addon = ...

local FEATURE_ID = "map_coordinates"
local MINIMAP_UPDATE_INTERVAL = 0.20
local MINIMAP_RETRY_INTERVAL = 1.00
local WORLD_MAP_UPDATE_INTERVAL = 0.10

local COORDINATE_FORMATS = {
    zero = "%.0f, %.0f",
    one = "%.1f, %.1f",
    two = "%.2f, %.2f",
}

local Runtime = {
    enabled = false,
    minimapDriver = nil,
    minimapText = nil,
    worldMap = nil,
    worldPanel = nil,
    worldText = nil,
}

Addon.MapCoordinates = Runtime

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function safeMapID(owner)
    if not owner or type(owner.GetMapID) ~= "function" then return nil end
    local ok, mapID = pcall(owner.GetMapID, owner)
    mapID = ok and tonumber(mapID) or nil
    return mapID and mapID > 0 and mapID or nil
end

local function playerMapID()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and tonumber(mapID) or nil
    return mapID and mapID > 0 and mapID or nil
end

local function normalizedPlayerPosition(mapID)
    if not mapID or not C_Map or type(C_Map.GetPlayerMapPosition) ~= "function" then
        return nil
    end

    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not position then return nil end

    local xyOK, x, y = pcall(function()
        if type(position.GetXY) == "function" then
            return position:GetXY()
        end
        return position.x, position.y
    end)
    x = xyOK and tonumber(x) or nil
    y = xyOK and tonumber(y) or nil
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function normalizedCursorPosition(map)
    if not map then return nil end
    local owner = type(map.GetNormalizedCursorPosition) == "function"
        and map
        or map.ScrollContainer
    if not owner or type(owner.GetNormalizedCursorPosition) ~= "function" then return nil end

    local ok, x, y = pcall(owner.GetNormalizedCursorPosition, owner)
    x = ok and tonumber(x) or nil
    y = ok and tonumber(y) or nil
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function coordinateText(x, y)
    if not x or not y then return "--" end
    local formatString = COORDINATE_FORMATS[setting("precision")]
        or COORDINATE_FORMATS.one
    return string.format(formatString, x * 100, y * 100)
end

local function setTextIfChanged(label, value)
    value = tostring(value or "")
    if label and label.vaultloomCoordinateText ~= value then
        label.vaultloomCoordinateText = value
        label:SetText(value)
    end
end

function Runtime:RefreshMinimap()
    local mapID = playerMapID()
    local x, y = normalizedPlayerPosition(mapID)
    local available = x ~= nil and y ~= nil
    if self.minimapText then
        if available then
            setTextIfChanged(self.minimapText, coordinateText(x, y))
            self.minimapText:Show()
        else
            self.minimapText:Hide()
        end
    end
    return available
end

function Runtime:RefreshWorldMap()
    local map = self.worldMap
    if not map or map ~= _G.WorldMapFrame then return false end

    local mapID = safeMapID(map)
    local playerX, playerY = normalizedPlayerPosition(mapID)
    local cursorX, cursorY = normalizedCursorPosition(map)
    local formatString = Addon.L.MAP_COORDINATES_WORLD_FORMAT
        or "Player: %s  |  Cursor: %s"
    setTextIfChanged(
        self.worldText,
        string.format(
            formatString,
            coordinateText(playerX, playerY),
            coordinateText(cursorX, cursorY)
        )
    )
    return true
end

local function minimapOnUpdate(frame, elapsed)
    frame.vaultloomElapsed = (tonumber(frame.vaultloomElapsed) or 0)
        + math.max(0, tonumber(elapsed) or 0)
    local interval = frame.vaultloomSlowRetry == true
        and MINIMAP_RETRY_INTERVAL
        or MINIMAP_UPDATE_INTERVAL
    if frame.vaultloomElapsed < interval then return end
    frame.vaultloomElapsed = 0

    local token = Addon.PerformanceDiagnostics:Begin(
        Runtime,
        "update",
        "map_coordinates.minimap"
    )
    frame.vaultloomSlowRetry = Runtime:RefreshMinimap() ~= true
    Addon.PerformanceDiagnostics:Finish(token)
end

local function worldMapOnUpdate(frame, elapsed)
    frame.vaultloomElapsed = (tonumber(frame.vaultloomElapsed) or 0)
        + math.max(0, tonumber(elapsed) or 0)
    if frame.vaultloomElapsed < WORLD_MAP_UPDATE_INTERVAL then return end
    frame.vaultloomElapsed = 0

    local token = Addon.PerformanceDiagnostics:Begin(
        Runtime,
        "update",
        "map_coordinates.world_map"
    )
    Runtime:RefreshWorldMap()
    Addon.PerformanceDiagnostics:Finish(token)
end

function Runtime:EnsureMinimapDisplay()
    local minimap = _G.Minimap
    if not minimap then return false end

    if not self.minimapDriver or self.minimapDriver:GetParent() ~= minimap then
        local driver = CreateFrame("Frame", nil, minimap)
        driver:Hide()
        self.minimapDriver = driver

        local label = minimap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", minimap, "BOTTOM", 0, 7)
        label:SetJustifyH("CENTER")
        label:SetTextColor(0.92, 0.76, 0.24, 1)
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(1, -1)
        label:Hide()
        self.minimapText = label
    end
    return true
end

function Runtime:EnsureWorldMapDisplay()
    local map = _G.WorldMapFrame
    if not map then return false end
    if self.worldPanel and self.worldMap == map then return true end

    if self.worldPanel then
        self.worldPanel:SetScript("OnUpdate", nil)
        self.worldPanel:Hide()
    end

    local panel = Addon.Widgets:CreatePanel(map, "cardInset")
    panel:SetSize(340, 24)
    local anchor = map.ScrollContainer or map
    panel:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 10, 10)
    panel:SetFrameLevel((tonumber(anchor:GetFrameLevel()) or 1) + 20)
    panel:EnableMouse(false)

    local label = Addon.Widgets:CreateLabel(panel, "GameFontHighlightSmall", "CENTER")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, 0)
    label:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 0)
    label:SetTextColor(0.93, 0.89, 0.77, 1)

    self.worldMap = map
    self.worldPanel = panel
    self.worldText = label
    return true
end

function Runtime:ApplyWorldMapStyle()
    local panel = self.worldPanel
    if not panel or type(panel.SetBackdrop) ~= "function" then return end
    if setting("world_map_frame") == true then
        Addon.Widgets:ApplyPanelStyle(panel, "cardInset")
    else
        panel:SetBackdrop(nil)
    end
end

function Runtime:StopWatchingForWorldMap()
    Addon.EventBus:Unsubscribe(self, "ADDON_LOADED")
end

function Runtime:WatchForWorldMap()
    if self.worldPanel or setting("world_map") ~= true then return end
    Addon.EventBus:Subscribe("ADDON_LOADED", self, function(_, addonName)
        if addonName ~= "Blizzard_WorldMap" and not _G.WorldMapFrame then return end
        if Runtime:EnsureWorldMapDisplay() then
            Runtime:StopWatchingForWorldMap()
            Runtime:ApplySettings()
        end
    end)
end

function Runtime:ApplySettings()
    if self.enabled ~= true then return end

    if setting("minimap") == true and self:EnsureMinimapDisplay() then
        self.minimapDriver.vaultloomElapsed = 0
        self.minimapDriver.vaultloomSlowRetry = self:RefreshMinimap() ~= true
        self.minimapDriver:SetScript("OnUpdate", minimapOnUpdate)
        self.minimapDriver:Show()
    elseif self.minimapDriver then
        self.minimapDriver:SetScript("OnUpdate", nil)
        self.minimapDriver:Hide()
        if self.minimapText then self.minimapText:Hide() end
    end

    if setting("world_map") == true then
        if self:EnsureWorldMapDisplay() then
            self:StopWatchingForWorldMap()
            self:ApplyWorldMapStyle()
            self.worldPanel.vaultloomElapsed = 0
            self.worldPanel:SetScript("OnUpdate", worldMapOnUpdate)
            self.worldPanel:Show()
            self:RefreshWorldMap()
        else
            self:WatchForWorldMap()
        end
    else
        self:StopWatchingForWorldMap()
        if self.worldPanel then
            self.worldPanel:SetScript("OnUpdate", nil)
            self.worldPanel:Hide()
        end
    end
end

function Runtime:OnSettingChanged()
    if self.minimapText then self.minimapText.vaultloomCoordinateText = nil end
    if self.worldText then self.worldText.vaultloomCoordinateText = nil end
    self:ApplySettings()
end

function Runtime:OnSettingsReset()
    self:OnSettingChanged()
end

function Runtime:OnEnable()
    self.enabled = true
    self:ApplySettings()
end

function Runtime:OnDisable()
    self.enabled = false
    if self.minimapDriver then
        self.minimapDriver:SetScript("OnUpdate", nil)
        self.minimapDriver:Hide()
    end
    if self.minimapText then self.minimapText:Hide() end
    if self.worldPanel then
        self.worldPanel:SetScript("OnUpdate", nil)
        self.worldPanel:Hide()
    end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Map Coordinates runtime.")
end
