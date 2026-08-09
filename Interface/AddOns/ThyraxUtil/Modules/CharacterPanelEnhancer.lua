local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "character_panel_enhancer",
    name = "Character Panel",
    version = ns.Versions.CHARACTER_PANEL_ENHANCER,
    source = "core",
    internal = true,
    subtitle = "ElvUI-style item levels on gear slots plus a detailed character stats panel.",
    onboardingDescription = "Stamps item level on every gear slot, flags missing enchants and empty sockets, and shows a detailed stats panel docked to the character sheet.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\characterpanel.tga",
    events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_EQUIPMENT_CHANGED",
        "ITEM_DATA_LOAD_RESULT",
        "ADDON_LOADED",
        "INSPECT_READY",
        "PLAYER_REGEN_ENABLED", -- recompute stats after combat ends (taint cleared)
    },
    defaults = {
        enabled = false,

        showCharacterGear = true,
        showInspectGear = true,
        showStatsPanel = true,

        showItemLevels = true,
        showEnchants = true,
        showGems = true,
        showQualityBorder = true,
        showWarnings = true,
        slotInfoBeside = false,

        fontSize = 12,
        ilvlFontSize = 14,
        panelAlpha = 1.0,
        gemIconSize = 14,
        enchantMarkerSize = 12,

        statsPanelCollapsed = false,

        minItemLevelForWarnings = 0,

        requireEnchantHead = false,
        requireEnchantShoulder = true,
        requireEnchantBack = false,
        requireEnchantChest = true,
        requireEnchantWaist = false,
        requireEnchantWrist = false,
        requireEnchantLegs = true,
        requireEnchantFeet = true,
        requireEnchantRings = true,
        requireEnchantMainHand = true,
        requireEnchantOffHand = true,

        showStatItemLevel = true,
        showStatEnchantReady = true,
        showStatSocketReady = true,
        showStatHealth = true,
        showStatArmor = true,
        showStatPrimary = true,
        showStatStamina = true,
        showStatCrit = true,
        showStatHaste = true,
        showStatMastery = true,
        showStatVersatility = true,
        showStatLeech = true,
        showStatAvoidance = true,
        showStatSpeed = true,
        showStatTank = false,
    },
}

-- Expose to sibling files in Modules/CharacterPanelEnhancer/ (StatsPanel.lua,
-- Inspect.lua). Each subfile reads ns._sharedModules.characterPanel to attach
-- its methods. Shared helpers used across the seam are promoted to module
-- fields further down (SetScaledFont, GetSafeItemLevel, ResolveAccentPalette).
ns._sharedModules = ns._sharedModules or {}
ns._sharedModules.characterPanel = module

module.CONSTANTS = {
    COLOR_READY = { 0.35, 0.95, 0.45, 1 },
    COLOR_WARN = { 1.00, 0.82, 0.25, 1 },
    COLOR_ERROR = { 1.00, 0.30, 0.22, 1 },
    COLOR_ILVL = { 0.82, 0.64, 1.00, 1 },
    COLOR_MUTED = { 0.74, 0.74, 0.74, 1 },
    COLOR_VALUE = { 1.00, 1.00, 1.00, 1 },
    COLOR_HEADER = { 1.00, 0.82, 0.30, 1 },
    MAX_GEMS = 4,
    BORDER_THICKNESS = 2,
    GEM_SIZE = 11,
    FONT_MIN = 8,
    FONT_MAX = 20,
}

local CONSTANTS = module.CONSTANTS
-- Deferred re-scan waves after INSPECT_READY. The Blizzard API trickles in
-- item data (ilvl, gems, sockets) over the first ~1.5s, so the immediate
-- refresh sometimes only sees half-populated slots. Each entry triggers
-- another full 16-slot scan with cache invalidation, so adding waves has a
-- direct cost in GC pressure. Two waves at 0.5s / 1.5s catch both the early
-- and late data arrivals; we used to fire three (0.25 / 0.75 / 1.50) but the
-- 0.25s pass almost always saw the same incomplete data as the immediate
-- refresh, generating ~16 wasted slot-info allocations per inspect.
local INSPECT_REFRESH_DELAYS = { 0.5, 1.5 }
module.INSPECT_REFRESH_DELAYS = INSPECT_REFRESH_DELAYS

function module:IsCombatLocked()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

function module:DeferFullRefreshUntilCombatEnds()
    self._refreshAfterCombat = true
end

function module:ShouldDeferInitialCharacterBuild()
    if not self:IsCombatLocked() then
        return false
    end
    if not self.characterHooksInstalled
        or not self.characterButtons
        or not self.statsPanel
        or not (self.slotWidgets and self.slotWidgets.character) then
        self:DeferFullRefreshUntilCombatEnds()
        return true
    end
    return false
end

-- column drives beside-icon placement: "left" slots get their info to the
-- right of the icon, "right" slots to the left, "bottom" (weapons) above it.
local SLOT_DEFS = {
    { id = 1,  key = "head",     label = "Head",      column = "left",   frame = "CharacterHeadSlot",      inspect = "InspectHeadSlot",     enchantKey = "requireEnchantHead" },
    { id = 2,  key = "neck",     label = "Neck",      column = "left",   frame = "CharacterNeckSlot",      inspect = "InspectNeckSlot" },
    { id = 3,  key = "shoulder", label = "Shoulder",  column = "left",   frame = "CharacterShoulderSlot",  inspect = "InspectShoulderSlot",  enchantKey = "requireEnchantShoulder" },
    { id = 5,  key = "chest",    label = "Chest",     column = "left",   frame = "CharacterChestSlot",     inspect = "InspectChestSlot",     enchantKey = "requireEnchantChest" },
    { id = 6,  key = "waist",    label = "Waist",     column = "right",  frame = "CharacterWaistSlot",     inspect = "InspectWaistSlot",     enchantKey = "requireEnchantWaist" },
    { id = 7,  key = "legs",     label = "Legs",      column = "right",  frame = "CharacterLegsSlot",      inspect = "InspectLegsSlot",      enchantKey = "requireEnchantLegs" },
    { id = 8,  key = "feet",     label = "Feet",      column = "right",  frame = "CharacterFeetSlot",      inspect = "InspectFeetSlot",      enchantKey = "requireEnchantFeet" },
    { id = 9,  key = "wrist",    label = "Wrist",     column = "left",   frame = "CharacterWristSlot",     inspect = "InspectWristSlot",     enchantKey = "requireEnchantWrist" },
    { id = 10, key = "hands",    label = "Hands",     column = "right",  frame = "CharacterHandsSlot",     inspect = "InspectHandsSlot" },
    { id = 11, key = "finger1",  label = "Ring 1",    column = "right",  frame = "CharacterFinger0Slot",   inspect = "InspectFinger0Slot",   enchantKey = "requireEnchantRings" },
    { id = 12, key = "finger2",  label = "Ring 2",    column = "right",  frame = "CharacterFinger1Slot",   inspect = "InspectFinger1Slot",   enchantKey = "requireEnchantRings" },
    { id = 13, key = "trinket1", label = "Trinket 1", column = "right",  frame = "CharacterTrinket0Slot",  inspect = "InspectTrinket0Slot" },
    { id = 14, key = "trinket2", label = "Trinket 2", column = "right",  frame = "CharacterTrinket1Slot",  inspect = "InspectTrinket1Slot" },
    { id = 15, key = "back",     label = "Back",      column = "left",   frame = "CharacterBackSlot",      inspect = "InspectBackSlot",      enchantKey = "requireEnchantBack" },
    { id = 16, key = "mainhand", label = "Main Hand", column = "bottom", frame = "CharacterMainHandSlot",  inspect = "InspectMainHandSlot",  enchantKey = "requireEnchantMainHand" },
    { id = 17, key = "offhand",  label = "Off Hand",  column = "bottom", frame = "CharacterSecondaryHandSlot", inspect = "InspectSecondaryHandSlot", enchantKey = "requireEnchantOffHand", optionalMissing = true },
}

function module:GetSlotDefinitions()
    return SLOT_DEFS
end

-- STAT_CATEGORIES / STAT_SETTINGS moved to Modules/CharacterPanelEnhancer/StatsPanel.lua
-- (the only consumer, GetVisibleStatCategories, lives there now).

-- Coercing clamp: settings values may be nil / non-numeric, so coerce to the
-- minimum before clamping via the shared Core helper. (ns.Color.Clamp itself
-- does not coerce -- it assumes a number.)
local function Clamp(value, minValue, maxValue)
    return ns.Color.Clamp(tonumber(value) or minValue, minValue, maxValue)
end

-- Shared number/string/color helpers from Core. CopyColor maps to RGBA (both
-- return r, g, b, a as a multi-value for direct SetTextColor / SetColorTexture).
local FormatNumber = ns.Format.Number
local FormatPercent = ns.Format.Percent
local StripColorCodes = ns.Format.StripCodes
local CopyColor = ns.Color.RGBA

local QUALITY_FALLBACK = { 0.82, 0.82, 0.82, 1 }
local function GetQualityColor(quality)
    quality = tonumber(quality)
    if quality and type(_G.ITEM_QUALITY_COLORS) == "table" then
        local qc = _G.ITEM_QUALITY_COLORS[quality]
        if type(qc) == "table" and qc.r then
            return { qc.r, qc.g, qc.b, 1 }
        end
    end
    return QUALITY_FALLBACK
end

local function SetScaledFont(fontString, size, flags)
    if not fontString then return end
    local path = fontString:GetFont()
    if path then
        fontString:SetFont(path, size, flags)
    end
end
-- Shared with StatsPanel.lua (RefreshStats scales its row fonts).
module.SetScaledFont = SetScaledFont

local function SplitItemString(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then
        return nil
    end
    local fields = {}
    -- Split with "*" plus a trailing colon so EMPTY fields are kept. Modern item
    -- links have empty enchant/gem fields ("item:id::::"); the pattern "[^:]+"
    -- silently drops them and shifts every later field left -- which made the
    -- enchant slot read a wrong, non-zero value (the "always green E" bug).
    for value in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = value
    end
    return fields
end

local function GetTextLine(frameName, index)
    local line = _G[frameName .. "TextLeft" .. tostring(index)]
    if line and line.GetText then
        return line:GetText()
    end
    return nil
end

local function GetSafeItemInfo(itemLink)
    if type(itemLink) ~= "string" and type(itemLink) ~= "number" then
        return nil, nil, nil
    end
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfo) == "function" then
        local ok, name, link, quality = pcall(_G.C_Item.GetItemInfo, itemLink)
        if ok then
            return name, link, quality
        end
    end
    if type(_G.GetItemInfo) == "function" then
        local ok, name, link, quality = pcall(_G.GetItemInfo, itemLink)
        if ok then
            return name, link, quality
        end
    end
    return nil, nil, nil
end

local function GetSafeItemLevel(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetDetailedItemLevelInfo) == "function" then
        local ok, itemLevel = pcall(_G.C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok then
            return tonumber(tostring(itemLevel))
        end
    end
    return nil
end
-- Shared with Inspect.lua (ComputeAverageItemLevel falls back to slot scan).
module.GetSafeItemLevel = GetSafeItemLevel

local function GetSafeIcon(itemLink)
    if type(itemLink) ~= "string" and type(itemLink) ~= "number" then
        return nil
    end
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, icon = pcall(_G.C_Item.GetItemInfoInstant, itemLink)
        if ok and icon then
            return icon
        end
    end
    if type(_G.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, icon = pcall(_G.GetItemInfoInstant, itemLink)
        if ok and icon then
            return icon
        end
    end
    return nil
end

function module:ParseItemLink(itemLink)
    local fields = SplitItemString(itemLink)
    if not fields then
        return nil
    end
    local gems = {}
    for index = 4, 7 do
        local gemID = tonumber(fields[index]) or 0
        if gemID > 0 then
            gems[#gems + 1] = gemID
        end
    end
    return {
        itemID = tonumber(fields[2]) or 0,
        enchantID = tonumber(fields[3]) or 0,
        gems = gems,
    }
end

function module:IsEnchantRequired(slotDef, itemLevel)
    if not slotDef or not slotDef.enchantKey then
        return false
    end
    if self.settings and self.settings[slotDef.enchantKey] ~= true then
        return false
    end
    local threshold = tonumber(self.settings and self.settings.minItemLevelForWarnings) or 0
    if threshold > 0 and tonumber(itemLevel or 0) > 0 and tonumber(itemLevel or 0) < threshold then
        return false
    end
    return true
end

function module:EnsureTooltip()
    if self.scanTooltip then
        return self.scanTooltip
    end
    local tooltip = CreateFrame("GameTooltip", "ThyraxCharacterPanelScanTooltip", UIParent, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    self.scanTooltip = tooltip
    return tooltip
end

-- Counts empty gem sockets via C_Item.GetItemStats / GetItemStats. The stats
-- table contains keys like EMPTY_SOCKET_PRISMATIC = 1, EMPTY_SOCKET_RED = 1,
-- etc., so we just sum every EMPTY_SOCKET_*. This avoids the per-call tooltip
-- scan that locked the UI for 0.3-0.6s every equipment change, AND it picks
-- up new socket types automatically (no Blizzard tooltip-text parsing involved).
-- Tooltip scan kept as a final fallback for very old clients where GetItemStats
-- is missing.
function module:CountEmptySockets(unit, slotID, itemLink)
    if not itemLink and unit and slotID and type(_G.GetInventoryItemLink) == "function" then
        local ok, link = pcall(_G.GetInventoryItemLink, unit, slotID)
        if ok then itemLink = link end
    end
    if not itemLink then return 0 end

    local stats
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemStats) == "function" then
        local ok, s = pcall(_G.C_Item.GetItemStats, itemLink)
        if ok then stats = s end
    end
    if not stats and type(_G.GetItemStats) == "function" then
        local ok, s = pcall(_G.GetItemStats, itemLink)
        if ok then stats = s end
    end
    if type(stats) == "table" then
        -- Counter-intuitive but verified: the EMPTY_SOCKET_* values report the
        -- TOTAL count of that socket type on the item definition (filled +
        -- empty), not the empty count. Subtract the gems that are actually
        -- socketed to get the actually-empty number.
        local total = 0
        for k, v in pairs(stats) do
            if type(k) == "string" and k:sub(1, 13) == "EMPTY_SOCKET_" then
                total = total + (tonumber(v) or 0)
            end
        end
        local filled = 0
        if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemGem) == "function" then
            for i = 1, CONSTANTS.MAX_GEMS do
                local ok, gemName, gemLink = pcall(_G.C_Item.GetItemGem, itemLink, i)
                if ok and ((gemLink and gemLink ~= "") or (gemName and gemName ~= "")) then
                    filled = filled + 1
                end
            end
        end
        local empty = total - filled
        if empty < 0 then empty = 0 end
        return empty
    end

    -- Last-resort tooltip fallback for clients without GetItemStats.
    local tooltip = self:EnsureTooltip()
    if not tooltip then return 0 end
    tooltip:ClearLines()
    if unit and slotID then
        pcall(tooltip.SetInventoryItem, tooltip, unit, slotID)
    else
        pcall(tooltip.SetHyperlink, tooltip, itemLink)
    end
    local tokens = {}
    for key, value in pairs(_G) do
        if type(key) == "string"
            and key:sub(1, 13) == "EMPTY_SOCKET_"
            and type(value) == "string"
            and value ~= "" then
            tokens[value] = true
        end
    end
    local name = tooltip:GetName()
    local count = 0
    for index = 2, tooltip:NumLines() do
        local text = GetTextLine(name, index)
        if type(text) == "string" and text ~= "" then
            local stripped = (StripColorCodes(text) or text):match("^%s*(.-)%s*$") or text
            if tokens[stripped] or stripped:match("Socket$") and not stripped:match("Socket Bonus") then
                count = count + 1
            end
        end
    end
    tooltip:Hide()
    return count
end

-- Returns only real socketed gems that resolve to an icon, so the slot overlay
-- never renders placeholder squares for unresolved data.
function module:GetGemLinks(itemLink)
    local gems = {}
    if type(itemLink) ~= "string" then
        return gems
    end
    if type(_G.C_Item) ~= "table" or type(_G.C_Item.GetItemGem) ~= "function" then
        return gems
    end

    for index = 1, CONSTANTS.MAX_GEMS do
        local ok, gemName, gemLink = pcall(_G.C_Item.GetItemGem, itemLink, index)
        if ok then
            local value = gemLink or gemName
            if type(value) == "string" and value ~= "" then
                local icon = GetSafeIcon(value)
                if icon then
                    gems[#gems + 1] = { icon = icon }
                end
            end
        end
    end

    return gems
end

function module:GetDurability(unit, slotID)
    if unit ~= "player" or type(_G.GetInventoryItemDurability) ~= "function" then
        return nil
    end
    local ok, current, maximum = pcall(_G.GetInventoryItemDurability, slotID)
    if not ok or not current or not maximum or maximum <= 0 then
        return nil
    end
    return {
        current = current,
        maximum = maximum,
        pct = (current / maximum) * 100,
    }
end

-- Cached slot-info accessor. Without this, RefreshGear AND ComputeReadiness
-- each iterate all 17 slots independently and call GetSlotInfo per slot,
-- which used to mean 34 tooltip scans per refresh. Now we share the computed
-- table for the duration of the cache window (invalidated on equipment /
-- item-data events in OnEvent).
function module:GetCachedSlotInfo(unit, slotDef)
    self._slotInfoCache = self._slotInfoCache or {}
    local bucket = self._slotInfoCache[unit]
    if not bucket then
        bucket = {}
        self._slotInfoCache[unit] = bucket
    end
    local info = bucket[slotDef.key]
    if not info then
        info = self:GetSlotInfo(unit, slotDef)
        bucket[slotDef.key] = info
    end
    return info
end

function module:InvalidateSlotInfoCache()
    self._slotInfoCache = nil
end

function module:GetSlotInfo(unit, slotDef)
    local itemLink
    if type(_G.GetInventoryItemLink) == "function" then
        local ok, link = pcall(_G.GetInventoryItemLink, unit, slotDef.id)
        if ok then itemLink = link end
    end

    local info = {
        slot = slotDef,
        itemLink = itemLink,
        itemName = nil,
        itemLevel = nil,
        quality = nil,
        enchantID = 0,
        gems = {},
        emptySockets = 0,
        warnings = {},
        severity = "ready",
    }

    if not itemLink then
        if not slotDef.optionalMissing then
            info.warnings[#info.warnings + 1] = "Missing item"
            info.severity = "error"
        end
        return info
    end

    local parsed = self:ParseItemLink(itemLink)
    if parsed then
        info.enchantID = parsed.enchantID or 0
    end

    local itemName, _, quality = GetSafeItemInfo(itemLink)
    info.itemName = itemName or slotDef.label
    info.quality = quality
    info.itemLevel = GetSafeItemLevel(itemLink)
    info.gems = self:GetGemLinks(itemLink)
    info.emptySockets = self:CountEmptySockets(unit, slotDef.id, itemLink)

    if self.settings and self.settings.showWarnings ~= false then
        if self:IsEnchantRequired(slotDef, info.itemLevel) and info.enchantID <= 0 then
            info.warnings[#info.warnings + 1] = "Missing enchant"
            info.severity = "error"
        end
        if info.emptySockets > 0 then
            info.warnings[#info.warnings + 1] = tostring(info.emptySockets) .. " empty socket(s)"
            info.severity = "error"
        end
    end

    return info
end

-- Gear slot widgets (ElvUI-style: drawn directly on the slot button) ----------

function module:CreateSlotWidget(slotButton)
    local widget = { border = {}, gems = {} }

    for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
        local tex = slotButton:CreateTexture(nil, "OVERLAY")
        tex:SetDrawLayer("OVERLAY", 4)
        tex:Hide()
        widget.border[edge] = tex
    end

    local thick = CONSTANTS.BORDER_THICKNESS
    widget.border.top:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
    widget.border.top:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", 0, 0)
    widget.border.top:SetHeight(thick)
    widget.border.bottom:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMLEFT", 0, 0)
    widget.border.bottom:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
    widget.border.bottom:SetHeight(thick)
    widget.border.left:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
    widget.border.left:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMLEFT", 0, 0)
    widget.border.left:SetWidth(thick)
    widget.border.right:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", 0, 0)
    widget.border.right:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
    widget.border.right:SetWidth(thick)

    local ilvlShadow = slotButton:CreateTexture(nil, "OVERLAY")
    ilvlShadow:SetDrawLayer("OVERLAY", 6)
    ilvlShadow:SetColorTexture(0, 0, 0, 0.55)
    ilvlShadow:Hide()
    widget.ilvlShadow = ilvlShadow

    local ilvl = slotButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ilvl:SetDrawLayer("OVERLAY", 7)
    ilvl:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 2)
    ilvl:SetJustifyH("CENTER")
    ilvl:Hide()
    widget.ilvl = ilvl

    ilvlShadow:SetPoint("TOPLEFT", ilvl, "TOPLEFT", -2, 1)
    ilvlShadow:SetPoint("BOTTOMRIGHT", ilvl, "BOTTOMRIGHT", 2, -1)

    -- Dark backing behind the enchant marker so both the green "E" and the
    -- red "!" stay legible against bright item icons.
    local enchantShadow = slotButton:CreateTexture(nil, "OVERLAY")
    enchantShadow:SetDrawLayer("OVERLAY", 6)
    enchantShadow:SetColorTexture(0, 0, 0, 0.65)
    enchantShadow:Hide()
    widget.enchantShadow = enchantShadow

    local enchant = slotButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    enchant:SetDrawLayer("OVERLAY", 7)
    enchant:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", -1, -1)
    enchant:Hide()
    widget.enchant = enchant

    enchantShadow:SetPoint("TOPLEFT", enchant, "TOPLEFT", -2, 1)
    enchantShadow:SetPoint("BOTTOMRIGHT", enchant, "BOTTOMRIGHT", 2, -1)

    local size = CONSTANTS.GEM_SIZE
    for index = 1, CONSTANTS.MAX_GEMS do
        local back = slotButton:CreateTexture(nil, "OVERLAY")
        back:SetDrawLayer("OVERLAY", 5)
        back:SetColorTexture(0, 0, 0, 0.85)
        back:Hide()

        local icon = slotButton:CreateTexture(nil, "OVERLAY")
        icon:SetDrawLayer("OVERLAY", 6)
        icon:SetSize(size, size)
        if index == 1 then
            icon:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 2, -2)
        else
            icon:SetPoint("LEFT", widget.gems[index - 1].icon, "RIGHT", 2, 0)
        end
        icon:Hide()

        back:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        back:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

        -- Warning glyph painted on top of an empty-socket gem slot. Real
        -- gems display the actual gem icon; empty sockets get a red square
        -- (from icon:SetColorTexture below) plus this "!" so the missing
        -- socket reads the same warning language as the enchant marker.
        local marker = slotButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        marker:SetDrawLayer("OVERLAY", 7)
        marker:SetPoint("CENTER", icon, "CENTER", 0, 0)
        marker:Hide()

        widget.gems[index] = { icon = icon, back = back, marker = marker }
    end

    return widget
end

function module:HideSlotWidget(widget)
    if not widget then return end
    widget.ilvl:Hide()
    widget.ilvlShadow:Hide()
    widget.enchant:Hide()
    if widget.enchantShadow then widget.enchantShadow:Hide() end
    for _, tex in pairs(widget.border) do tex:Hide() end
    for _, gem in ipairs(widget.gems) do
        gem.icon:Hide()
        gem.back:Hide()
        if gem.marker then gem.marker:Hide() end
    end
end

-- Re-anchors the item level, enchant marker and gem row for the current
-- placement mode. On-icon mode draws everything over the slot; beside mode
-- stacks the info next to (or, for weapons, above) the slot icon. Each
-- element anchors to the previous visible one so hidden parts leave no gap.
function module:LayoutSlotWidget(widget, slotDef, showIlvl, showEnchant)
    local s = self.settings or self.defaults
    local btn = widget.ilvl:GetParent()
    local MAX = CONSTANTS.MAX_GEMS
    local gems = widget.gems

    local function chainGems(point, relRegion, relPoint, ox, oy, dir)
        gems[1].icon:ClearAllPoints()
        gems[1].icon:SetPoint(point, relRegion, relPoint, ox, oy)
        for i = 2, MAX do
            gems[i].icon:ClearAllPoints()
            if dir == "left" then
                gems[i].icon:SetPoint("RIGHT", gems[i - 1].icon, "LEFT", -2, 0)
            else
                gems[i].icon:SetPoint("LEFT", gems[i - 1].icon, "RIGHT", 2, 0)
            end
        end
    end

    if s.slotInfoBeside ~= true then
        -- On-icon overlay (ElvUI-style): everything drawn on top of the slot.
        widget.ilvl:ClearAllPoints()
        widget.ilvl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
        widget.ilvl:SetJustifyH("CENTER")

        widget.enchant:ClearAllPoints()
        widget.enchant:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        widget.enchant:SetJustifyH("RIGHT")

        -- Gems chain from the outer top-left corner using the same edge inset
        -- as the enchant marker (-1, -1) so a single gem visually aligns with
        -- the "E" / "!" on the opposite corner. Multi-gem rows then extend
        -- inward across the icon, leaving room for up to four gems.
        chainGems("TOPLEFT", btn, "TOPLEFT", 1, -1, "right")
        return
    end

    local column = (slotDef and slotDef.column) or "left"

    if column == "bottom" then
        -- Weapons: stack upward, centered above the slot icon.
        widget.ilvl:ClearAllPoints()
        widget.ilvl:SetPoint("BOTTOM", btn, "TOP", 0, 3)
        widget.ilvl:SetJustifyH("CENTER")

        widget.enchant:ClearAllPoints()
        widget.enchant:SetJustifyH("CENTER")
        if showIlvl then
            widget.enchant:SetPoint("BOTTOM", widget.ilvl, "TOP", 0, 2)
        else
            widget.enchant:SetPoint("BOTTOM", btn, "TOP", 0, 3)
        end

        if showEnchant then
            chainGems("BOTTOM", widget.enchant, "TOP", 0, 2, "right")
        elseif showIlvl then
            chainGems("BOTTOM", widget.ilvl, "TOP", 0, 2, "right")
        else
            chainGems("BOTTOM", btn, "TOP", 0, 3, "right")
        end
        return
    end

    -- Left / right columns: stack downward beside the slot icon.
    local cornerH = (column == "right") and "RIGHT" or "LEFT"
    local btnCorner = (column == "right") and "TOPLEFT" or "TOPRIGHT"
    local bx = (column == "right") and -4 or 4
    local gemDir = (column == "right") and "left" or "right"

    widget.ilvl:ClearAllPoints()
    widget.ilvl:SetPoint("TOP" .. cornerH, btn, btnCorner, bx, -2)
    widget.ilvl:SetJustifyH(cornerH)

    widget.enchant:ClearAllPoints()
    widget.enchant:SetJustifyH(cornerH)
    if showIlvl then
        widget.enchant:SetPoint("TOP" .. cornerH, widget.ilvl, "BOTTOM" .. cornerH, 0, -2)
    else
        widget.enchant:SetPoint("TOP" .. cornerH, btn, btnCorner, bx, -2)
    end

    if showEnchant then
        -- Gem goes BESIDE the enchant marker (not below), so ilvl + enchant
        -- + gems together stay within the icon's vertical span instead of
        -- pushing the row past the bottom edge of the slot icon.
        local gemSide  = (column == "right") and "RIGHT" or "LEFT"
        local enchSide = (column == "right") and "LEFT"  or "RIGHT"
        local gx       = (column == "right") and -4 or 4
        chainGems(gemSide, widget.enchant, enchSide, gx, 0, gemDir)
    elseif showIlvl then
        chainGems("TOP" .. cornerH, widget.ilvl, "BOTTOM" .. cornerH, 0, -2, gemDir)
    else
        chainGems("TOP" .. cornerH, btn, btnCorner, bx, -2, gemDir)
    end
end

function module:ApplySlotWidget(widget, info)
    if not widget or not info then return end
    local s = self.settings or self.defaults
    local ilvlFontSize = Clamp(s.ilvlFontSize, 8, 24)
    local gemSize = Clamp(s.gemIconSize, 6, 24)
    local enchantSize = Clamp(s.enchantMarkerSize, 8, 24)
    local hasItem = info.itemLink ~= nil
    local slotDef = info.slot

    -- Item level ---------------------------------------------------------
    local showIlvl = s.showItemLevels ~= false and hasItem and info.itemLevel ~= nil
    if showIlvl then
        widget.ilvl:SetText(FormatNumber(info.itemLevel))
        local qc = GetQualityColor(info.quality)
        widget.ilvl:SetTextColor(qc[1], qc[2], qc[3], 1)
        SetScaledFont(widget.ilvl, ilvlFontSize, "OUTLINE")
    end

    -- Enchant marker -----------------------------------------------------
    local showEnchant = false
    if s.showEnchants ~= false and hasItem and slotDef and slotDef.enchantKey then
        if info.enchantID and info.enchantID > 0 then
            widget.enchant:SetText("E")
            widget.enchant:SetTextColor(CopyColor(CONSTANTS.COLOR_READY))
            SetScaledFont(widget.enchant, enchantSize, "OUTLINE")
            showEnchant = true
        elseif s.showWarnings ~= false and self:IsEnchantRequired(slotDef, info.itemLevel) then
            widget.enchant:SetText("!")
            widget.enchant:SetTextColor(CopyColor(CONSTANTS.COLOR_ERROR))
            SetScaledFont(widget.enchant, enchantSize, "OUTLINE")
            showEnchant = true
        end
    end

    -- Gems ---------------------------------------------------------------
    local showGems = s.showGems ~= false
    local showWarnings = s.showWarnings ~= false
    local gemList = info.gems or {}
    local filled = #gemList
    local emptySockets = tonumber(info.emptySockets) or 0
    local markerSize = math.max(8, gemSize)
    for index, gem in ipairs(widget.gems) do
        local source = gemList[index]
        gem.icon:SetSize(gemSize, gemSize)
        if showGems and source and source.icon then
            gem.icon:SetTexture(source.icon)
            gem.icon:SetVertexColor(1, 1, 1, 1)
            gem.shown = true
            gem.markerShown = false
        elseif showWarnings and index > filled and index <= filled + emptySockets then
            gem.icon:SetColorTexture(0.92, 0.22, 0.16, 1)
            gem.shown = true
            gem.markerShown = true
            gem.marker:SetText("!")
            gem.marker:SetTextColor(CopyColor(CONSTANTS.COLOR_VALUE))
            SetScaledFont(gem.marker, markerSize, "OUTLINE")
        else
            gem.shown = false
            gem.markerShown = false
        end
    end

    -- Position everything for the current placement mode -----------------
    self:LayoutSlotWidget(widget, slotDef, showIlvl, showEnchant)

    -- Apply visibility ---------------------------------------------------
    if showIlvl then
        widget.ilvl:Show()
        widget.ilvlShadow:Show()
    else
        widget.ilvl:Hide()
        widget.ilvlShadow:Hide()
    end
    if showEnchant then
        widget.enchant:Show()
        widget.enchantShadow:Show()
    else
        widget.enchant:Hide()
        widget.enchantShadow:Hide()
    end
    for _, gem in ipairs(widget.gems) do
        if gem.shown then
            gem.icon:Show()
            gem.back:Show()
            if gem.markerShown then
                gem.marker:Show()
            else
                gem.marker:Hide()
            end
        else
            gem.icon:Hide()
            gem.back:Hide()
            gem.marker:Hide()
        end
    end

    -- Quality / error border ---------------------------------------------
    local borderColor
    if hasItem then
        if s.showQualityBorder ~= false then
            borderColor = GetQualityColor(info.quality)
        end
    elseif info.severity == "error" and showWarnings then
        borderColor = CONSTANTS.COLOR_ERROR
    end
    for _, tex in pairs(widget.border) do
        if borderColor then
            tex:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 0.95)
            tex:Show()
        else
            tex:Hide()
        end
    end
end

function module:EnsureSlotStore(kind)
    self.slotWidgets = self.slotWidgets or {}
    self.slotWidgets[kind] = self.slotWidgets[kind] or {}
    return self.slotWidgets[kind]
end

function module:RefreshGear(kind, unit, container, useInspect)
    if not container or not container.IsShown or not container:IsShown() then
        self:HideGear(kind)
        return
    end

    local settingKey = (kind == "inspect") and "showInspectGear" or "showCharacterGear"
    if self.settings[settingKey] ~= true then
        self:HideGear(kind)
        return
    end

    local store = self:EnsureSlotStore(kind)
    for _, slotDef in ipairs(SLOT_DEFS) do
        local frameName = useInspect and slotDef.inspect or slotDef.frame
        local slotButton = _G[frameName]
        if slotButton then
            local widget = store[slotDef.key]
            if not widget then
                widget = self:CreateSlotWidget(slotButton)
                store[slotDef.key] = widget
            end
            if slotButton.IsShown and slotButton:IsShown() then
                self:ApplySlotWidget(widget, self:GetCachedSlotInfo(unit, slotDef))
            else
                self:HideSlotWidget(widget)
            end
        end
    end
end

function module:HideGear(kind)
    local store = self.slotWidgets and self.slotWidgets[kind]
    if not store then return end
    for _, widget in pairs(store) do
        self:HideSlotWidget(widget)
    end
end

-- Stats ----------------------------------------------------------------------

function module:GetAverageDurability()
    local totalCurrent = 0
    local totalMax = 0
    for _, slotDef in ipairs(SLOT_DEFS) do
        local durability = self:GetDurability("player", slotDef.id)
        if durability then
            totalCurrent = totalCurrent + durability.current
            totalMax = totalMax + durability.maximum
        end
    end
    if totalMax <= 0 then
        return nil
    end
    return (totalCurrent / totalMax) * 100
end

local function GetCombatRatingPair(ratingKey)
    local ratingIndex = _G[ratingKey]
    if not ratingIndex then
        return nil
    end
    local rating, bonus
    if type(_G.GetCombatRating) == "function" then
        local ok, value = pcall(_G.GetCombatRating, ratingIndex)
        if ok then rating = tonumber(tostring(value)) end
    end
    if type(_G.GetCombatRatingBonus) == "function" then
        local ok, value = pcall(_G.GetCombatRatingBonus, ratingIndex)
        if ok then bonus = tonumber(tostring(value)) end
    end
    return rating, bonus
end

-- Counts enchant + socket completeness across every equipped slot so the
-- stats panel (and inspect overlay) can show "X / Y" readiness summaries.
-- Works for any unit; for inspect, pass the inspect-target unit token.
--
-- enchantPresent  = number of enchant-capable slots that ARE enchanted
-- enchantTotal    = number of enchant-capable slots (equipped + has enchantKey)
-- enchantRequired = number of slots where the user demands an enchant
-- requiredMissing = number of required slots where the enchant is missing
function module:ComputeReadiness(unit)
    local enchantPresent, enchantTotal, enchantRequired, requiredMissing = 0, 0, 0, 0
    local socketsFilled, socketsTotal = 0, 0
    for _, slotDef in ipairs(SLOT_DEFS) do
        local info = self:GetCachedSlotInfo(unit, slotDef)
        if info and info.itemLink then
            -- Count every enchant-capable slot, not only required ones.
            if slotDef.enchantKey then
                enchantTotal = enchantTotal + 1
                if (info.enchantID or 0) > 0 then
                    enchantPresent = enchantPresent + 1
                end
                if self:IsEnchantRequired(slotDef, info.itemLevel) then
                    enchantRequired = enchantRequired + 1
                    if (info.enchantID or 0) <= 0 then
                        requiredMissing = requiredMissing + 1
                    end
                end
            end
            local filled = info.gems and #info.gems or 0
            local empty = tonumber(info.emptySockets) or 0
            socketsFilled = socketsFilled + filled
            socketsTotal = socketsTotal + filled + empty
        end
    end
    return {
        enchantPresent = enchantPresent,
        enchantTotal = enchantTotal,
        enchantRequired = enchantRequired,
        requiredMissing = requiredMissing,
        socketsFilled = socketsFilled,
        socketsTotal = socketsTotal,
    }
end

-- Cached readiness for the local player. The full slot-tooltip scan is
-- expensive (17 slots, each with a tooltip rescan); recomputing it on every
-- RefreshStats call multiplied CPU 3-4x once the readiness rows were added.
-- The cache is invalidated on PLAYER_EQUIPMENT_CHANGED / ITEM_DATA_LOAD_RESULT,
-- so it always reflects the current loadout but only does the work once per
-- gear change.
function module:GetCachedPlayerReadiness()
    if self._readinessDirty or not self._playerReadiness then
        self._playerReadiness = self:ComputeReadiness("player")
        self._readinessDirty = false
    end
    return self._playerReadiness
end

-- Coalesces stats-panel refreshes that fire in the same frame (typical when
-- Blizzard swaps sidebar panes -- multiple OnShow / OnHide hooks fire back
-- to back) into a single deferred refresh on the next frame. The defer also
-- lets Blizzard finish ALL its show / hide calls before we evaluate the
-- sidebar state, which avoids the race that re-showed CharacterStatsPane
-- between Blizzard hiding it and Blizzard showing the next sidebar pane.
function module:ScheduleStatsRefresh()
    if self._statsRefreshPending then return end
    self._statsRefreshPending = true
    C_Timer.After(0, function()
        self._statsRefreshPending = false
        if module.isActive then module:RefreshStats() end
    end)
end

function module:ScheduleFullRefresh()
    if self._fullRefreshPending then return end
    self._fullRefreshPending = true
    C_Timer.After(0, function()
        self._fullRefreshPending = false
        if module.isActive then module:RefreshAll() end
    end)
end

-- Combat-safe wrapper around the real ComputeStats. Some Blizzard APIs
-- (GetUnitSpeed, GetCritChance, ...) flag their return values as "secret
-- numbers" when our execution is tainted (typical when the character frame
-- is opened during combat via the Blizzard panel manager). Comparing /
-- arithmetic on a secret number raises a Lua error, which used to surface
-- as the "Interface action failed because of an AddOn" toast. We now run
-- the heavy computation under pcall and fall back to the last cached
-- result; PLAYER_REGEN_ENABLED triggers a fresh recompute once combat ends.
function module:GetStats()
    local ok, result = pcall(module.ComputeStats, self)
    if ok and type(result) == "table" then
        self._cachedStats = result
        return result
    end
    return self._cachedStats or {}
end

function module:ComputeStats()
    local stats = {}

    local readiness = self:GetCachedPlayerReadiness()
    if readiness.enchantTotal > 0 then
        -- Denominator follows what the user actually demands (enchantRequired),
        -- expanded upward so we never display X > Y. Previous behaviour showed
        -- "8 / 12" because the total counted every enchant-capable slot even
        -- when the user only required 8 of them.
        local denom = math.max(readiness.enchantPresent, readiness.enchantRequired)
        if denom > 0 then
            stats.enchantReady = {
                label = "Enchants",
                value = readiness.enchantPresent .. " / " .. denom,
                ready = readiness.requiredMissing <= 0,
            }
        end
    end
    if readiness.socketsTotal > 0 then
        stats.socketReady = {
            label = "Sockets",
            value = readiness.socketsFilled .. " / " .. readiness.socketsTotal,
            ready = readiness.socketsFilled >= readiness.socketsTotal,
        }
    end

    if type(_G.GetAverageItemLevel) == "function" then
        local ok, average, equipped = pcall(_G.GetAverageItemLevel)
        if ok then
            local safeAverage = tonumber(tostring(average))
            local safeEquipped = tonumber(tostring(equipped))
            stats.itemLevel = {
                label = "Item Level",
                value = FormatNumber(safeEquipped or safeAverage, 1),
                detail = safeAverage and FormatNumber(safeAverage, 1) or nil,
            }
        end
    end

    if type(_G.UnitHealthMax) == "function" then
        local ok, health = pcall(_G.UnitHealthMax, "player")
        local safeHealth = ok and tonumber(tostring(health)) or nil
        if safeHealth then
            stats.health = { label = "Health", value = FormatNumber(safeHealth) }
        end
    end

    if type(_G.UnitArmor) == "function" then
        local ok, baseArmor, effectiveArmor = pcall(_G.UnitArmor, "player")
        if ok then
            local armor = tonumber(tostring(effectiveArmor)) or tonumber(tostring(baseArmor))
            if armor and armor > 0 then
                stats.armor = { label = "Armor", value = FormatNumber(armor) }
            end
        end
    end

    local statLabels = {
        [1] = "Strength",
        [2] = "Agility",
        [3] = "Stamina",
        [4] = "Intellect",
    }
    local bestPrimary = { label = "Primary", value = 0 }
    if type(_G.UnitStat) == "function" then
        for statIndex = 1, 4 do
            local ok, base, effective = pcall(_G.UnitStat, "player", statIndex)
            local value = tonumber(tostring(effective or base))
            if ok and value then
                if statIndex == 3 then
                    stats.stamina = { label = "Stamina", value = FormatNumber(value) }
                elseif value > bestPrimary.value then
                    bestPrimary = { label = statLabels[statIndex] or "Primary", value = value }
                end
            end
        end
    end
    if bestPrimary.value > 0 then
        stats.primary = { label = bestPrimary.label, value = FormatNumber(bestPrimary.value) }
    end

    -- Percentage stats: use the dedicated total-percent APIs (which include
    -- base + spec passives + buffs + gear) rather than
    -- GetCombatRatingBonus alone (which only reports the rating's gear
    -- contribution). The user-visible character sheet uses the same total
    -- APIs, so this keeps our numbers in lockstep with Blizzard's.
    local function SafeNumber(value)
        return tonumber(tostring(value))
    end
    local function SafeCall(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if not ok then return nil end
        return SafeNumber(value)
    end

    -- Crit: take the higher of melee / ranged / spell so casters and
    -- physical specs both see the value their character sheet shows.
    local critM = SafeCall(_G.GetCritChance)
    local critR = SafeCall(_G.GetRangedCritChance)
    local critS = SafeCall(_G.GetSpellCritChance, 2)
    local critTotal = math.max(critM or 0, critR or 0, critS or 0)
    if critTotal > 0 then
        local rating = GetCombatRatingPair("CR_CRIT_MELEE")
        stats.crit = {
            label = "Crit",
            value = FormatPercent(critTotal),
            detail = rating and tostring(rating) or nil,
        }
    end

    -- Haste: unified % including spec, buffs, gear.
    local hasteTotal = SafeCall(_G.GetHaste) or SafeCall(_G.UnitSpellHaste, "player")
    if hasteTotal then
        local rating = GetCombatRatingPair("CR_HASTE_MELEE")
        stats.haste = {
            label = "Haste",
            value = FormatPercent(hasteTotal),
            detail = rating and tostring(rating) or nil,
        }
    end

    -- Versatility: rating contribution + buff contribution = total damage-done %.
    local versCR = _G.CR_VERSATILITY_DAMAGE_DONE
    local versRating = versCR and SafeCall(_G.GetCombatRatingBonus, versCR) or 0
    local versBuff = versCR and SafeCall(_G.GetVersatilityBonus, versCR) or 0
    local versTotal = (versRating or 0) + (versBuff or 0)
    if versTotal > 0 then
        local rating = GetCombatRatingPair("CR_VERSATILITY_DAMAGE_DONE")
        stats.versatility = {
            label = "Versatility",
            value = FormatPercent(versTotal),
            detail = rating and tostring(rating) or nil,
        }
    end

    -- Leech / Avoidance: GetLifesteal / GetAvoidance return the total %
    -- including buffs; fall back to the rating-bonus value if the helper
    -- is missing on the client.
    local leechTotal = SafeCall(_G.GetLifesteal)
    if not leechTotal then
        local cr = _G.CR_LIFESTEAL
        leechTotal = cr and SafeCall(_G.GetCombatRatingBonus, cr) or nil
    end
    if leechTotal and leechTotal > 0 then
        local rating = GetCombatRatingPair("CR_LIFESTEAL")
        stats.leech = {
            label = "Leech",
            value = FormatPercent(leechTotal),
            detail = rating and tostring(rating) or nil,
        }
    end

    local avoidTotal = SafeCall(_G.GetAvoidance)
    if not avoidTotal then
        local cr = _G.CR_AVOIDANCE
        avoidTotal = cr and SafeCall(_G.GetCombatRatingBonus, cr) or nil
    end
    if avoidTotal and avoidTotal > 0 then
        local rating = GetCombatRatingPair("CR_AVOIDANCE")
        stats.avoidance = {
            label = "Avoidance",
            value = FormatPercent(avoidTotal),
            detail = rating and tostring(rating) or nil,
        }
    end

    -- Speed: actual run speed, not the (usually zero) Speed combat rating.
    -- WoW 12.0 (Midnight) returns "secret numbers" from GetUnitSpeed when our
    -- execution is tainted (e.g. character frame opened while in combat via
    -- the Blizzard panel manager). Comparing or doing arithmetic on a secret
    -- number raises a Lua error, so we validate with Compat.IsNonSecretNumber
    -- before touching either return value.
    if type(_G.GetUnitSpeed) == "function" then
        local ok, current, run = pcall(_G.GetUnitSpeed, "player")
        if ok then
            local isSafe = ns.Compat and ns.Compat.IsNonSecretNumber
            local moveSpeed
            if isSafe and isSafe(run) and run > 0 then
                moveSpeed = run
            elseif isSafe and isSafe(current) and current > 0 then
                moveSpeed = current
            end
            if moveSpeed then
                -- 7 yards/sec is the base run speed (= 100%).
                stats.speed = { label = "Speed", value = FormatPercent((moveSpeed / 7) * 100) }
            end
        end
    end

    if type(_G.GetMasteryEffect) == "function" then
        local ok, mastery = pcall(_G.GetMasteryEffect)
        mastery = ok and tonumber(tostring(mastery)) or nil
        if mastery then
            local rating = GetCombatRatingPair("CR_MASTERY")
            stats.mastery = {
                label = "Mastery",
                value = FormatPercent(mastery),
                detail = rating and tostring(rating) or nil,
            }
        end
    end

    if type(_G.GetDodgeChance) == "function" then
        local ok, value = pcall(_G.GetDodgeChance)
        value = ok and tonumber(tostring(value)) or nil
        if ok and value then stats.dodge = { label = "Dodge", value = FormatPercent(value) } end
    end
    if type(_G.GetParryChance) == "function" then
        local ok, value = pcall(_G.GetParryChance)
        value = ok and tonumber(tostring(value)) or nil
        if ok and value then stats.parry = { label = "Parry", value = FormatPercent(value) } end
    end
    if type(_G.GetBlockChance) == "function" then
        local ok, value = pcall(_G.GetBlockChance)
        value = ok and tonumber(tostring(value)) or nil
        if ok and value then stats.block = { label = "Block", value = FormatPercent(value) } end
    end

    return stats
end

-- GetVisibleStatCategories moved to Modules/CharacterPanelEnhancer/StatsPanel.lua.

-- Stats panel chrome shared with the character-frame buttons below ------------

-- Resolves the global accent palette; falls back to gold when ns.UI is not
-- yet available (early init). Promoted to a module field so StatsPanel.lua and
-- Inspect.lua can re-tint to the same palette.
local function ResolveAccentPalette()
    if ns.UI and ns.UI.GetAccentPalette then
        return ns.UI:GetAccentPalette()
    end
    return {
        accent      = { 0.95, 0.78, 0.30, 1 },
        accentSoft  = { 0.72, 0.62, 0.28, 1 },
        accentEdge  = { 0.55, 0.45, 0.18, 0.90 },
        surface     = { 0.18, 0.13, 0.07, 0.95 },
        surfaceDark = { 0.14, 0.11, 0.05, 1 },
        header      = { 1.00, 0.82, 0.30, 1 },
    }
end
module.ResolveAccentPalette = ResolveAccentPalette

local function CreateHeaderButton(parent, size)
    -- Matches the boxed look of the Accounting window's icon buttons: dark
    -- fill with an accent edge and hover highlight. Colors come from the
    -- global accent palette so the buttons re-tint when the user switches
    -- the accent preset.
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    local palette = ResolveAccentPalette()
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(palette.surface[1], palette.surface[2], palette.surface[3], 0.85)
        btn:SetBackdropBorderColor(palette.header[1], palette.header[2], palette.header[3], 0.55)
    else
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(palette.surface[1], palette.surface[2], palette.surface[3], 0.85)
    end
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.18)
    btn._thyraxIsHeaderButton = true
    return btn
end

local function AttachButtonTooltip(btn, text)
    btn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

-- EnsureStatsPanel / AcquireStatHeader / AcquireStatRow / ToggleStatsPanelCollapsed
-- / UpdateScrollThumb / RefreshStats moved to
-- Modules/CharacterPanelEnhancer/StatsPanel.lua.

-- Character frame buttons ----------------------------------------------------

function module:EnsureCharacterButtons()
    if self.characterButtons then
        return self.characterButtons
    end
    if not CharacterFrame then
        return nil
    end

    local closeButton = CharacterFrame.CloseButton or _G.CharacterFrameCloseButton
    local size = 22
    -- Some re-skin / Classic-style UIs place decorative frames at high levels
    -- relative to CharacterFrame; anchor anchors at +50 (or close button + 5)
    -- so our buttons stay on top in both Modern and reskinned UIs.
    local baseLevel = (CharacterFrame:GetFrameLevel() or 1) + 50
    if closeButton and closeButton.GetFrameLevel then
        local cl = closeButton:GetFrameLevel() or 0
        if cl + 5 > baseLevel then baseLevel = cl + 5 end
    end
    local topLevel = baseLevel

    local optionsBtn = CreateHeaderButton(CharacterFrame, size)
    optionsBtn:SetFrameLevel(topLevel)
    if closeButton then
        optionsBtn:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    else
        optionsBtn:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -30, -8)
    end
    -- Single-letter "S" badge mirrors the Accounting window header button so
    -- both ThyraxUtil entry points read the same at a glance.
    local optText = optionsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optText:SetPoint("CENTER", optionsBtn, "CENTER", 0, 0)
    optText:SetText("S")
    optText:SetTextColor(CopyColor(CONSTANTS.COLOR_HEADER))
    optionsBtn.text = optText
    optionsBtn:SetScript("OnClick", function()
        if ns.SlashCommands and ns.SlashCommands.RequestOptionsOpen then
            ns.SlashCommands:RequestOptionsOpen("character_panel_enhancer")
        elseif ns.OptionsPanel and ns.OptionsPanel.Open then
            ns.OptionsPanel:Open("character_panel_enhancer")
        end
    end)
    AttachButtonTooltip(optionsBtn, "ThyraxUtil character panel options")

    local collapseBtn = CreateHeaderButton(CharacterFrame, size)
    collapseBtn:SetFrameLevel(topLevel)
    collapseBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -2, 0)
    local collapseText = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    collapseText:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
    collapseText:SetText("-")
    collapseText:SetTextColor(CopyColor(CONSTANTS.COLOR_HEADER))
    collapseBtn.text = collapseText
    collapseBtn:SetScript("OnClick", function()
        module:ToggleStatsPanelCollapsed()
    end)
    AttachButtonTooltip(collapseBtn, "Collapse / expand the stats panel")

    self.characterButtons = { options = optionsBtn, collapse = collapseBtn }
    return self.characterButtons
end

function module:RefreshCharacterButtons()
    local buttons = self:EnsureCharacterButtons()
    if not buttons then
        return
    end
    -- Re-tint to the current accent on every refresh so the buttons follow
    -- the global accent preset when the user switches it at runtime.
    local palette = ResolveAccentPalette()
    for _, btn in ipairs({ buttons.options, buttons.collapse }) do
        if btn and btn.SetBackdropColor then
            btn:SetBackdropColor(palette.surface[1], palette.surface[2], palette.surface[3], 0.85)
            btn:SetBackdropBorderColor(palette.header[1], palette.header[2], palette.header[3], 0.55)
        end
        if btn and btn.text then
            btn.text:SetTextColor(palette.header[1], palette.header[2], palette.header[3], palette.header[4] or 1)
        end
    end

    if self.isActive then
        buttons.options:Show()
        -- Collapse button only meaningful while the Stats sidebar is active.
        -- Use host:IsShown() as truth -- Blizzard manages host's visibility
        -- and we no longer touch it.
        local host = _G.CharacterStatsPane
        local statsSidebarActive = host and host:IsShown()
        local statsAvailable = self.settings and self.settings.showStatsPanel ~= false
        if statsAvailable and statsSidebarActive then
            buttons.collapse:Show()
        else
            buttons.collapse:Hide()
        end
        local collapsed = self.settings and self.settings.statsPanelCollapsed == true
        buttons.collapse.text:SetText(collapsed and "+" or "-")
    else
        buttons.options:Hide()
        buttons.collapse:Hide()
    end
end

-- Hooks and lifecycle --------------------------------------------------------

function module:InstallCharacterHooks()
    if self.characterHooksInstalled or not CharacterFrame then
        return
    end
    self.characterHooksInstalled = true
    CharacterFrame:HookScript("OnShow", function()
        if module.isActive then
            module:RefreshAll()
        end
    end)
    CharacterFrame:HookScript("OnHide", function()
        module:HideGear("character")
        if module.statsPanel then
            module.statsPanel:Hide()
        end
    end)
end

-- InstallInspectHooks / GetInspectUnit / ComputeAverageItemLevel /
-- EnsureInspectReadiness / RefreshInspectReadiness / RefreshInspect /
-- IsInspectDataComplete / RefreshInspectWithFreshData / ScheduleInspectRefresh
-- moved to Modules/CharacterPanelEnhancer/Inspect.lua.

function module:RefreshAll()
    if not self.isActive then
        return
    end
    if self:ShouldDeferInitialCharacterBuild() then
        return
    end
    self:InstallCharacterHooks()
    self:InstallInspectHooks()
    self:RefreshCharacterButtons()
    if CharacterFrame and CharacterFrame:IsShown() then
        self:RefreshGear("character", "player", CharacterFrame, false)
        self:RefreshStats()
    else
        self:HideGear("character")
        if self.statsPanel then
            self.statsPanel:Hide()
        end
    end
    self:RefreshInspect()
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    -- Settings changes can flip an enchant requirement (requireEnchant*),
    -- which changes the readiness totals. Without invalidating the readiness
    -- cache, the stats panel keeps showing the previous "X / Y" until the
    -- next equipment / combat event. Mark dirty so the next RefreshAll
    -- recomputes against the new settings.
    self._readinessDirty = true
    self:RefreshAll()
end

function module:OnEnable(settings)
    self.isActive = true
    self.settings = settings or self.settings or self.defaults
    self._readinessDirty = true
    if self:ShouldDeferInitialCharacterBuild() then
        return
    end
    self:InstallCharacterHooks()
    self:InstallInspectHooks()
    self:RefreshAll()
end

function module:OnDisable()
    self.isActive = false
    self:HideGear("character")
    self:HideGear("inspect")
    if self.statsPanel then
        self.statsPanel:Hide()
    end
    if self.inspectReadiness then
        self.inspectReadiness.container:Hide()
    end
    if self.characterButtons then
        self.characterButtons.options:Hide()
        self.characterButtons.collapse:Hide()
    end
    -- No host:Show() needed: we never hide CharacterStatsPane any more, so
    -- there is nothing to restore. Blizzard owns its visibility entirely.
end

function module:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
        self:InstallInspectHooks()
        if self.isActive then
            self:RefreshInspectWithFreshData()
            self:ScheduleInspectRefresh()
        end
        return
    end
    if not self.isActive then
        return
    end
    if event == "INSPECT_READY" then
        self:RefreshInspectWithFreshData()
        self:ScheduleInspectRefresh()
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Equipment really changed -- drop caches and refresh ASAP.
        self:InvalidateSlotInfoCache()
        self._readinessDirty = true
        self:ScheduleFullRefresh()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended -- taint on player-info APIs is cleared, recompute
        -- the (until-now possibly cached / partial) stats panel.
        self._cachedStats = nil
        self:InvalidateSlotInfoCache()
        self._readinessDirty = true
        self._refreshAfterCombat = nil
        self:ScheduleFullRefresh()
        return
    end
    if event == "ITEM_DATA_LOAD_RESULT" then
        -- ITEM_DATA_LOAD_RESULT fires in bursts (often dozens per second when
        -- the character frame first opens). Coalesce all of them into one
        -- delayed refresh so we don't tooltip-scan / iterate slots per fire.
        self:InvalidateSlotInfoCache()
        self._readinessDirty = true
        if not self._itemDataDebouncePending then
            self._itemDataDebouncePending = true
            C_Timer.After(0.25, function()
                self._itemDataDebouncePending = false
                if module.isActive then module:ScheduleFullRefresh() end
            end)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- On login / reload the server trickles item data (gems, sockets)
        -- over the first ~1.5s, identical to the inspect-ready situation.
        -- Without explicit cache invalidation here the very first refresh
        -- caches incomplete socket counts (0) and nothing corrects them
        -- because ITEM_DATA_LOAD_RESULT may arrive before GetItemStats is
        -- fully populated. Invalidate + immediate refresh + delayed waves.
        self:InvalidateSlotInfoCache()
        self._readinessDirty = true
        self:ScheduleFullRefresh()
        for _, delay in ipairs(INSPECT_REFRESH_DELAYS) do
            C_Timer.After(delay, function()
                if module.isActive then
                    module:InvalidateSlotInfoCache()
                    module._readinessDirty = true
                    module:ScheduleFullRefresh()
                end
            end)
        end
        return
    end
    self:ScheduleFullRefresh()
end

function module:RunTest()
    self:RefreshAll()
end

function module:GetDebugState()
    return {
        characterVisible = CharacterFrame and CharacterFrame:IsShown() or false,
        inspectVisible = _G.InspectFrame and _G.InspectFrame:IsShown() or false,
        statsPanelShown = self.statsPanel and self.statsPanel:IsShown() or false,
        statsPanelCollapsed = self.settings and self.settings.statsPanelCollapsed == true or false,
    }
end

ns.ModuleRegistry:Register(module)
