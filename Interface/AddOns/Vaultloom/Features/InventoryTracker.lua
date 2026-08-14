local _, Addon = ...

local FEATURE_ID = "inventory_tracker"
local MAX_CHARACTER_ROWS = 8

local SOURCE_DEFINITIONS = {
    {
        key = "bags",
        labelKey = "FEATURE_INVENTORY_SOURCE_BAGS",
        texture = "Interface\\Icons\\INV_Misc_Bag_10_Black",
    },
    {
        key = "bank",
        labelKey = "FEATURE_INVENTORY_SOURCE_BANK",
        texture = "Interface\\Icons\\INV_Misc_Coin_02",
    },
    {
        key = "reagents",
        labelKey = "FEATURE_INVENTORY_SOURCE_REAGENTS",
        texture = "Interface\\Icons\\INV_Misc_Herb_11",
    },
    {
        key = "mail",
        labelKey = "FEATURE_INVENTORY_SOURCE_MAIL",
        texture = "Interface\\Icons\\INV_Letter_15",
    },
    {
        key = "equipped",
        labelKey = "FEATURE_INVENTORY_SOURCE_EQUIPPED",
        texture = "Interface\\Icons\\INV_Chest_Plate04",
    },
}

local Runtime = {
    enabled = false,
    hooksReady = false,
    dirty = true,
    index = nil,
    indexBuildCount = 0,
    trackedTooltips = setmetatable({}, { __mode = "k" }),
}

Addon.InventoryTracker = Runtime

local function normalizeItemID(value)
    local ok, resolved = pcall(function()
        if type(value) == "number" then
            return value
        end
        if type(value) ~= "string" or value == "" then
            return nil
        end
        if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
            local itemID = C_Item.GetItemInfoInstant(value)
            if tonumber(itemID) then
                return tonumber(itemID)
            end
        end
        return tonumber(value:match("item:(%d+)"))
    end)
    resolved = ok and tonumber(resolved) or nil
    return resolved and resolved > 0 and math.floor(resolved) or nil
end

local function getLiveWarbandCount(itemID)
    if not (C_Item and type(C_Item.GetItemCount) == "function") then
        return nil
    end

    local ok, count = pcall(function()
        -- GetItemCount always includes the current character's bags. Calling it
        -- once without and once with the account bank isolates the live Warband
        -- bank total even while the bank frame itself is closed.
        local bagCount = C_Item.GetItemCount(itemID, false, false, false, false)
        local accountCount = C_Item.GetItemCount(itemID, false, false, false, true)
        if type(bagCount) ~= "number" or type(accountCount) ~= "number" then
            return nil
        end
        return math.max(0, math.floor(accountCount - bagCount))
    end)
    return ok and count or nil
end

local function getTooltipItemID(tooltip, data)
    if type(data) == "table" then
        local ok, value = pcall(function()
            return data.itemID or data.id or data.hyperlink or data.itemLink or data.link
        end)
        local itemID = ok and normalizeItemID(value) or nil
        if itemID then
            return itemID
        end
    end

    if tooltip and type(tooltip.GetItem) == "function" then
        local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
        if ok then
            return normalizeItemID(itemLink)
        end
    end
    return nil
end

local function getClassColor(classFile)
    local color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return 1, 1, 1
end

local function formatCharacterName(row)
    local name = tostring(row and row.name or row and row.key or Addon.L.UNKNOWN)
    if row and row.showRealm and type(row.realm) == "string" and row.realm ~= "" then
        return name .. "-" .. row.realm
    end
    return name
end

local function sourceText(source)
    local icon = string.format("|T%s:12:12:0:0|t", source.texture)
    return string.format("%s %s %d", icon, Addon.L[source.labelKey] or source.labelKey, source.count)
end

local function formatSources(row)
    local parts = {}
    for _, definition in ipairs(SOURCE_DEFINITIONS) do
        local count = math.max(0, math.floor(tonumber(row.sources[definition.key]) or 0))
        if count > 0 then
            parts[#parts + 1] = sourceText({
                texture = definition.texture,
                labelKey = definition.labelKey,
                count = count,
            })
        end
    end
    return table.concat(parts, "   ")
end

local function clearTooltipState(tooltip)
    if not tooltip then
        return
    end
    tooltip.VaultloomInventoryRendered = nil
    tooltip.VaultloomInventoryItemID = nil
    Runtime.trackedTooltips[tooltip] = nil
end

local function ensureTooltipResetHook(tooltip)
    if not tooltip or tooltip.VaultloomInventoryClearHook then
        return
    end
    if type(tooltip.HookScript) == "function" then
        tooltip:HookScript("OnTooltipCleared", function(clearedTooltip)
            clearTooltipState(clearedTooltip)
        end)
        tooltip.VaultloomInventoryClearHook = true
    end
end

function Runtime:RestoreTooltip(tooltip, rebuild)
    if not tooltip then
        return
    end

    local hadInventory = tooltip.VaultloomInventoryRendered == true
    local itemLink
    local shown = type(tooltip.IsShown) ~= "function" or tooltip:IsShown()
    if rebuild and hadInventory and shown and type(tooltip.GetItem) == "function" then
        local ok, _, value = pcall(tooltip.GetItem, tooltip)
        if ok and type(value) == "string" and value ~= "" then
            itemLink = value
        end
    end
    clearTooltipState(tooltip)

    if itemLink and type(tooltip.ClearLines) == "function" and type(tooltip.SetHyperlink) == "function" then
        pcall(function()
            tooltip:ClearLines()
            tooltip:SetHyperlink(itemLink)
        end)
    end
end

function Runtime:RefreshTrackedTooltips()
    local tracked = {}
    for tooltip in pairs(self.trackedTooltips) do
        tracked[#tracked + 1] = tooltip
    end
    for _, tooltip in ipairs(tracked) do
        self:RestoreTooltip(tooltip, true)
    end
end

function Runtime:InvalidateIndex(refreshTooltips)
    self.dirty = true
    Addon.InventoryIndex:Invalidate()
    if refreshTooltips and self.enabled then
        self:RefreshTrackedTooltips()
    end
end

function Runtime:GetIndex()
    self.index = Addon.InventoryIndex:GetIndex()
    self.dirty = false
    self.indexBuildCount = Addon.InventoryIndex.buildCount
    return self.index
end

function Runtime:GetItemView(itemID)
    self:GetIndex()
    local includeWarband = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "warband_bank") == true
    local view = Addon.InventoryIndex:GetItemView(itemID, {
        includeWarband = includeWarband,
        includeEquipped = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "equipped_items") == true,
    })

    if not includeWarband then
        return view
    end

    local liveWarband = getLiveWarbandCount(itemID)
    if liveWarband == nil then
        return view
    end
    if not view then
        if liveWarband == 0 then
            return nil
        end
        return {
            itemID = itemID,
            rows = {},
            warband = liveWarband,
            total = liveWarband,
        }
    end

    local storedWarband = math.max(0, math.floor(tonumber(view.warband) or 0))
    view.warband = liveWarband
    view.total = math.max(0, math.floor(tonumber(view.total) or 0) - storedWarband + liveWarband)
    return view.total > 0 and view or nil
end

function Runtime:AddHeader(tooltip, total)
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(
        Addon.L.FEATURE_INVENTORY_TOOLTIP_HEADER,
        tostring(total),
        1, 0.82, 0.24,
        1, 0.82, 0.24
    )
end

function Runtime:AddCharacterRow(tooltip, row, detailed)
    local r, g, b = getClassColor(row.classFile)
    tooltip:AddDoubleLine(
        formatCharacterName(row),
        tostring(row.total),
        r, g, b,
        1, 1, 1
    )
    if detailed then
        local sources = formatSources(row)
        if sources ~= "" then
            tooltip:AddLine("  " .. sources, 0.72, 0.68, 0.58, true)
        end
    end
end

function Runtime:ApplyTooltip(tooltip, data)
    if self.enabled ~= true or not tooltip or tooltip.VaultloomInventoryRendered then
        return
    end

    local itemID = getTooltipItemID(tooltip, data)
    if not itemID then
        return
    end
    local view = self:GetItemView(itemID)
    if not view then
        return
    end

    ensureTooltipResetHook(tooltip)
    tooltip.VaultloomInventoryRendered = true
    tooltip.VaultloomInventoryItemID = itemID
    self.trackedTooltips[tooltip] = true

    local mode = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "tooltip_mode")
    self:AddHeader(tooltip, view.total)
    if mode ~= "total" then
        local detailed = mode == "detail"
        local shown = math.min(#view.rows, MAX_CHARACTER_ROWS)
        for index = 1, shown do
            self:AddCharacterRow(tooltip, view.rows[index], detailed)
        end
        if #view.rows > shown then
            tooltip:AddLine(
                string.format(Addon.L.FEATURE_INVENTORY_MORE_CHARACTERS, #view.rows - shown),
                0.72, 0.68, 0.58,
                true
            )
        end
        if view.warband > 0 then
            tooltip:AddDoubleLine(
                Addon.L.FEATURE_INVENTORY_WARBAND_BANK,
                tostring(view.warband),
                1, 0.82, 0.24,
                1, 0.82, 0.24
            )
        end
    end

    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return true
    end

    if TooltipDataProcessor
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum
        and Enum.TooltipDataType
        and Enum.TooltipDataType.Item
    then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            Runtime:ApplyTooltip(tooltip, data)
        end)
        self.hooksReady = true
        return true
    end

    local hooked = false
    for _, tooltip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and type(tooltip.HookScript) == "function" then
            tooltip:HookScript("OnTooltipSetItem", function(currentTooltip)
                Runtime:ApplyTooltip(currentTooltip, nil)
            end)
            hooked = true
        end
    end
    self.hooksReady = hooked
    return hooked
end

function Runtime:OnEnable()
    self.enabled = true
    self.dirty = true
    if not self:EnsureHooks() then
        self.enabled = false
        error("No supported item-tooltip API is available.")
    end

    Addon.StateStore:Subscribe("arsenal.snapshots", self, function()
        Runtime:InvalidateIndex(true)
    end)
    Addon.StateStore:Subscribe("warband.roster", self, function()
        Runtime:InvalidateIndex(true)
    end)
    Addon.StateStore:Subscribe("mailbox.snapshots", self, function()
        Runtime:InvalidateIndex(true)
    end)
end

function Runtime:OnDisable()
    self.enabled = false
    self:RefreshTrackedTooltips()
    self.index = nil
    self.dirty = true
end

function Runtime:OnSettingChanged()
    self:RefreshTrackedTooltips()
end

function Runtime:OnSettingsReset()
    self:RefreshTrackedTooltips()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Item Inventory feature runtime.")
end
