local _, Addon = ...

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local MASK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BUTTON_SIZE = 32
local MENU_WIDTH = 270
local ROW_HEIGHT = 34
local FALLBACK_X_OFFSET = -4
local FALLBACK_FIRST_Y_OFFSET = -66
local FALLBACK_STACK_GAP = 4
local FALLBACK_SCAN_MAX_Y = 320
local MAP_FEATURES = {
    "midnight_rare_map_pins",
    "midnight_treasure_map_pins",
    "gathering_nodes",
}

local Runtime = {
    button = nil,
    retiredFallbackButton = nil,
    menu = nil,
    rows = {},
    hookedMap = nil,
    usingKrowiWorldMapButtons = false,
    krowiWorldMapButtons = nil,
}

Addon.WorldMapFeatureButton = Runtime

local function resolveText(value)
    if type(value) == "function" then
        local ok, result = pcall(value)
        return ok and tostring(result or "") or ""
    end
    return tostring(value or "")
end

local function getMapParent()
    local map = _G.WorldMapFrame
    if not map then return nil end
    if type(map.GetCanvasContainer) == "function" then
        local ok, canvas = pcall(map.GetCanvasContainer, map)
        if ok and canvas then return canvas end
    end
    return map.ScrollContainer or map
end

local function getKrowiWorldMapButtons()
    local libStub = _G.LibStub
    if type(libStub) ~= "table" or type(libStub.GetLibrary) ~= "function" then
        return nil
    end
    local ok, library = pcall(
        libStub.GetLibrary,
        libStub,
        "Krowi_WorldMapButtons-1.4",
        true
    )
    if ok and type(library) == "table" and type(library.Add) == "function" then
        return library
    end
    return nil
end

local function collectChildren(parent, callback)
    if not parent or type(parent.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { parent:GetChildren() } end)
    if not ok then return end
    for _, child in ipairs(children) do callback(child) end
end

local function getFallbackButtonYOffset(button, anchor)
    if not button or not anchor
        or type(anchor.GetTop) ~= "function"
        or type(anchor.GetRight) ~= "function"
    then
        return FALLBACK_FIRST_Y_OFFSET
    end

    local okTop, anchorTop = pcall(anchor.GetTop, anchor)
    local okRight, anchorRight = pcall(anchor.GetRight, anchor)
    if not okTop or not okRight or not anchorTop or not anchorRight then
        return FALLBACK_FIRST_Y_OFFSET
    end

    local deepestBottom = math.abs(FALLBACK_FIRST_Y_OFFSET)
    local seen = {}
    local function scanCandidate(frame)
        if not frame or frame == button or frame == Runtime.menu or seen[frame] then return end
        seen[frame] = true

        if type(frame.IsShown) == "function" then
            local okShown, shown = pcall(frame.IsShown, frame)
            if okShown and shown ~= true then return end
        end
        if type(frame.GetTop) ~= "function" or type(frame.GetRight) ~= "function" then
            return
        end

        local width = type(frame.GetWidth) == "function" and tonumber(frame:GetWidth()) or 0
        local height = type(frame.GetHeight) == "function" and tonumber(frame:GetHeight()) or 0
        if width < 18 or width > 64 or height < 18 or height > 64 then return end

        local okCandidateTop, top = pcall(frame.GetTop, frame)
        local okCandidateRight, right = pcall(frame.GetRight, frame)
        if not okCandidateTop or not okCandidateRight or not top or not right then return end

        local yOffset = anchorTop - top
        local xOffset = anchorRight - right
        if yOffset >= -8 and yOffset <= FALLBACK_SCAN_MAX_Y
            and xOffset >= -40 and xOffset <= 90
        then
            deepestBottom = math.max(deepestBottom, yOffset + height)
        end
    end

    local map = _G.WorldMapFrame
    if map and type(map.overlayFrames) == "table" then
        for _, frame in pairs(map.overlayFrames) do scanCandidate(frame) end
    end
    collectChildren(map, scanCandidate)
    if anchor ~= map then collectChildren(anchor, scanCandidate) end

    return -math.floor(deepestBottom + FALLBACK_STACK_GAP + 0.5)
end

local function getAvailableFeatures()
    local result = {}
    for _, featureID in ipairs(MAP_FEATURES) do
        if Addon.FeatureRegistry:IsAvailable(featureID) then
            result[#result + 1] = featureID
        end
    end
    return result
end

local function addCircularMask(owner, texture)
    if owner.iconMask or type(owner.CreateMaskTexture) ~= "function"
        or type(texture.AddMaskTexture) ~= "function"
    then
        return
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    owner.iconMask = mask
end

function Runtime:HideMenu()
    if self.menu then self.menu:Hide() end
end

function Runtime:Position()
    if not self.button then return end
    local parent = getMapParent()
    if not parent then return end

    if self.usingKrowiWorldMapButtons then
        if self.krowiWorldMapButtons
            and type(self.krowiWorldMapButtons.SetPoints) == "function"
        then
            pcall(self.krowiWorldMapButtons.SetPoints)
        end
    else
        self.button:ClearAllPoints()
        self.button:SetPoint(
            "TOPRIGHT",
            parent,
            "TOPRIGHT",
            FALLBACK_X_OFFSET,
            getFallbackButtonYOffset(self.button, parent)
        )
    end
    if self.menu then
        self.menu:ClearAllPoints()
        self.menu:SetPoint("TOPRIGHT", self.button, "BOTTOMRIGHT", 0, -7)
    end
end

function Runtime:QueuePosition()
    if not (C_Timer and type(C_Timer.After) == "function") then
        self:Position()
        return
    end
    C_Timer.After(0, function() Runtime:Position() end)
    C_Timer.After(0.25, function() Runtime:Position() end)
end

function Runtime:EnsureMapHooks()
    local map = _G.WorldMapFrame
    if not map or self.hookedMap == map then return end
    self.hookedMap = map

    if type(map.HookScript) == "function" then
        map:HookScript("OnShow", function()
            Runtime:Refresh()
            Runtime:QueuePosition()
        end)
        map:HookScript("OnHide", function() Runtime:HideMenu() end)
    end

    if type(hooksecurefunc) ~= "function" then return end
    for _, methodName in ipairs({
        "RefreshOverlayFrames",
        "OnMapChanged",
        "OnFrameSizeChanged",
    }) do
        if type(map[methodName]) == "function" then
            pcall(hooksecurefunc, map, methodName, function()
                Runtime:QueuePosition()
            end)
        end
    end
end

function Runtime:CreateRow(index)
    local row = CreateFrame("Button", nil, self.menu, BACKDROP_TEMPLATE)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 12, -38 - ((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -12, 0)
    row:EnableMouse(true)
    row:SetBackdrop({
        bgFile = Addon.Assets.row,
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    row:SetBackdropColor(0.18, 0.15, 0.11, 0.94)
    row:SetBackdropBorderColor(0.60, 0.45, 0.16, 0.68)

    row.box = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    row.box:SetSize(18, 18)
    row.box:SetPoint("LEFT", 7, 0)
    row.box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row.box:SetBackdropColor(0.04, 0.035, 0.03, 1)
    row.box:SetBackdropBorderColor(0.84, 0.65, 0.22, 0.86)

    row.check = row.box:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:SetSize(24, 24)
    row.check:SetPoint("CENTER")

    row.label = Addon.Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.label:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", -50, 0)

    row.status = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "RIGHT")
    row.status:SetPoint("RIGHT", -8, 0)
    row.status:SetWidth(42)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.80, 0.22, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.60, 0.45, 0.16, 0.68)
    end)
    row:SetScript("OnClick", function(self)
        if not self.featureID then return end
        Addon.FeatureRegistry:SetEnabled(
            self.featureID,
            not Addon.FeatureRegistry:IsEnabled(self.featureID),
            "world-map-button"
        )
        Runtime:Refresh()
    end)
    return row
end

function Runtime:CreateMenu(parent)
    if self.menu then return self.menu end
    local menu = CreateFrame(
        "Frame",
        "VaultloomWorldMapFeatureMenu",
        parent,
        BACKDROP_TEMPLATE
    )
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel((parent:GetFrameLevel() or 0) + 30)
    menu:EnableMouse(true)
    Addon.Widgets:ApplyStandardGoldFrame(menu, Addon.Assets.menuPlate)

    menu.title = Addon.Widgets:CreateLabel(menu, "GameFontNormal", "LEFT")
    menu.title:SetPoint("TOPLEFT", 12, -12)
    menu.title:SetPoint("TOPRIGHT", -12, -12)
    menu.title:SetTextColor(1, 0.82, 0.24, 1)
    menu.title:SetText(Addon.L.WORLD_MAP_FEATURE_MENU_TITLE)
    menu:Hide()
    self.menu = menu
    return menu
end

function Runtime:CreateButton(parent)
    if self.button then
        local manager = not self.usingKrowiWorldMapButtons
            and getKrowiWorldMapButtons() or nil
        if not manager then return self.button end

        self.button:Hide()
        self.button:ClearAllPoints()
        self.retiredFallbackButton = self.button
        self.button = nil
    end

    local manager = getKrowiWorldMapButtons()
    local button
    if manager then
        local ok, managedButton = pcall(manager.Add, manager, nil, "BUTTON")
        if ok and managedButton then
            button = managedButton
            self.usingKrowiWorldMapButtons = true
            self.krowiWorldMapButtons = manager
            button.Refresh = function() Runtime:Refresh() end
        end
    end

    if not button then
        button = CreateFrame(
            "Button",
            "VaultloomWorldMapFeatureButton",
            parent
        )
        self.usingKrowiWorldMapButtons = false
        self.krowiWorldMapButtons = nil
    end

    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((parent:GetFrameLevel() or 0) + 40)
    button:RegisterForClicks("LeftButtonUp")
    button:EnableMouse(true)

    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.background:SetSize(25, 25)
    button.background:SetPoint("TOPLEFT", 2, -4)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(BUTTON_ICON)
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("TOPLEFT", 6, -6)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addCircularMask(button, button.icon)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT")

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetColorTexture(1.00, 0.82, 0.46, 0.16)
    button.highlight:SetBlendMode("ADD")
    button.highlight:SetSize(24, 24)
    button.highlight:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    if type(button.highlight.AddMaskTexture) == "function" then
        button.highlightMask = button:CreateMaskTexture(nil, "HIGHLIGHT")
        button.highlightMask:SetTexture(
            MASK_TEXTURE,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        button.highlightMask:SetAllPoints(button.highlight)
        button.highlight:AddMaskTexture(button.highlightMask)
    end

    button:SetScript("OnClick", function()
        if Runtime.menu:IsShown() then
            Runtime.menu:Hide()
        else
            Runtime:Refresh()
            Runtime.menu:Show()
            if type(Runtime.menu.Raise) == "function" then Runtime.menu:Raise() end
        end
    end)
    button:SetScript("OnMouseDown", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("TOPLEFT", 7, -7)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("TOPLEFT", 6, -6)
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(Addon.L.WORLD_MAP_FEATURE_BUTTON_TITLE, 1, 0.82, 0.18, true)
            GameTooltip:AddLine(Addon.L.WORLD_MAP_FEATURE_BUTTON_TOOLTIP, 0.88, 0.86, 0.82, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.button = button
    self:CreateMenu(parent)
    self:QueuePosition()
    return button
end

function Runtime:Ensure()
    local parent = getMapParent()
    if not parent then return false end
    self:CreateButton(parent)
    self:EnsureMapHooks()
    self:Refresh()
    self:QueuePosition()
    return true
end

function Runtime:Refresh()
    if not self.button or not self.menu then return end
    local features = getAvailableFeatures()
    self.button:SetShown(#features > 0)
    if #features == 0 then
        self.menu:Hide()
        self:Position()
        return
    end

    local enabledCount = 0
    for index, featureID in ipairs(features) do
        local row = self.rows[index]
        if not row then
            row = self:CreateRow(index)
            self.rows[index] = row
        end
        local definition = Addon.FeatureRegistry:GetDefinition(featureID)
        local enabled = Addon.FeatureRegistry:IsEnabled(featureID)
        if enabled then enabledCount = enabledCount + 1 end
        row.featureID = featureID
        row.label:SetText(definition and resolveText(definition.title) or featureID)
        row.status:SetText(
            enabled and Addon.L.WORLD_MAP_FEATURE_ENABLED or Addon.L.WORLD_MAP_FEATURE_DISABLED
        )
        row.status:SetTextColor(enabled and 0.50 or 0.72, enabled and 1 or 0.72, enabled and 0.56 or 0.68, 1)
        row.check:SetShown(enabled)
        row:Show()
    end
    for index = #features + 1, #self.rows do
        self.rows[index]:Hide()
        self.rows[index].featureID = nil
    end
    self.menu:SetSize(MENU_WIDTH, 50 + (#features * ROW_HEIGHT))
    self.button.icon:SetDesaturated(enabledCount == 0)
    self.button.icon:SetAlpha(enabledCount == 0 and 0.48 or 1)
    self:Position()
end

Addon.EventBus:Subscribe("ADDON_LOADED", Runtime, function(_, addonName)
    if addonName == Addon.name or addonName == "Blizzard_WorldMap" then
        Runtime:Ensure()
    elseif Runtime.button
        and Runtime.usingKrowiWorldMapButtons ~= true
        and getKrowiWorldMapButtons()
    then
        Runtime:Ensure()
    end
end)

Addon.EventBus:Subscribe("PLAYER_LOGIN", Runtime, function()
    Runtime:Ensure()
end)

Addon.StateStore:Subscribe("features.registry", Runtime, function()
    Runtime:Refresh()
end)
