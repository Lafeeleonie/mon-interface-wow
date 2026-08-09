local _, Addon = ...

local FEATURE_ID = "item_id_tooltip"

local Runtime = {
    enabled = false,
    hooksReady = false,
    trackedTooltips = setmetatable({}, { __mode = "k" }),
}

Addon.ItemIDTooltip = Runtime

local function applySmallerFont(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function" then
        return nil
    end

    local fontFile, fontHeight, fontFlags = fontString:GetFont()
    fontHeight = tonumber(fontHeight)
    if not fontFile or not fontHeight then
        return nil
    end

    fontString:SetFont(fontFile, math.max(8, fontHeight - 2), fontFlags)
    return {
        fontFile = fontFile,
        fontHeight = fontHeight,
        fontFlags = fontFlags,
    }
end

local function restoreFont(fontString, fontInfo)
    if not fontString or type(fontString.SetFont) ~= "function" or type(fontInfo) ~= "table" then
        return
    end

    if fontInfo.fontFile and fontInfo.fontHeight then
        fontString:SetFont(fontInfo.fontFile, fontInfo.fontHeight, fontInfo.fontFlags)
    end
end

local function parseItemID(value)
    local ok, itemID = pcall(function()
        if type(value) == "number" then
            return value
        end
        if type(value) ~= "string" or value == "" then
            return nil
        end

        if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
            local resolvedID = C_Item.GetItemInfoInstant(value)
            if tonumber(resolvedID) then
                return tonumber(resolvedID)
            end
        end

        return tonumber(value:match("item:(%d+)"))
    end)

    local normalized, resolvedID = pcall(function()
        itemID = ok and tonumber(itemID) or nil
        if itemID and itemID > 0 then
            return math.floor(itemID)
        end
    end)
    return normalized and resolvedID or nil
end

local function getTooltipItemID(tooltip, data)
    if type(data) == "table" then
        local ok, value = pcall(function()
            return data.itemID or data.id or data.hyperlink or data.itemLink or data.link
        end)
        local itemID = ok and parseItemID(value) or nil
        if itemID then
            return itemID
        end
    end

    if tooltip and type(tooltip.GetItem) == "function" then
        local okItem, _, itemLink = pcall(tooltip.GetItem, tooltip)
        if okItem then
            return parseItemID(itemLink)
        end
    end

    return nil
end

local function getTooltipRightLineOne(tooltip)
    if not tooltip or type(tooltip.GetName) ~= "function" then
        return nil
    end

    local ok, name = pcall(tooltip.GetName, tooltip)
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end

    return _G[name .. "TextRight1"]
end

local function clearTooltipState(tooltip)
    if not tooltip then
        return
    end
    restoreFont(getTooltipRightLineOne(tooltip), tooltip.VaultloomItemIDOriginalRight1Font)
    tooltip.VaultloomItemID = nil
    tooltip.VaultloomItemIDOriginalRight1 = nil
    tooltip.VaultloomItemIDOriginalRight1Font = nil
    Runtime.trackedTooltips[tooltip] = nil
end

local function ensureTooltipResetHook(tooltip)
    if not tooltip or tooltip.VaultloomItemIDClearHook then
        return
    end

    if type(tooltip.HookScript) == "function" then
        tooltip:HookScript("OnTooltipCleared", function(clearedTooltip)
            clearTooltipState(clearedTooltip)
        end)
        tooltip.VaultloomItemIDClearHook = true
    end
end

function Runtime:ClearTooltip(tooltip)
    local rightLine = getTooltipRightLineOne(tooltip)
    if not rightLine or not tooltip or not tooltip.VaultloomItemID then
        return
    end

    local originalText = tooltip.VaultloomItemIDOriginalRight1
    rightLine:SetText(type(originalText) == "string" and originalText or "")
    clearTooltipState(tooltip)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

function Runtime:ApplyTooltip(tooltip, data)
    if self.enabled ~= true or not tooltip then
        return
    end

    local itemID = getTooltipItemID(tooltip, data)
    if not itemID then
        return
    end

    local rightLine = getTooltipRightLineOne(tooltip)
    if not rightLine then
        return
    end

    if tooltip.VaultloomItemID == itemID then
        return
    end

    ensureTooltipResetHook(tooltip)

    local originalText = rightLine:GetText()
    tooltip.VaultloomItemIDOriginalRight1 = type(originalText) == "string" and originalText or ""
    tooltip.VaultloomItemIDOriginalRight1Font = applySmallerFont(rightLine)
    tooltip.VaultloomItemID = itemID
    self.trackedTooltips[tooltip] = true

    local idText = string.format("|cffdbb85cID %d|r", itemID)
    if tooltip.VaultloomItemIDOriginalRight1 ~= "" then
        rightLine:SetText(tooltip.VaultloomItemIDOriginalRight1 .. "  " .. idText)
    else
        rightLine:SetText(idText)
    end
    rightLine:Show()

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

    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            Runtime:ApplyTooltip(tooltip, nil)
        end)
        self.hooksReady = true
        return true
    end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    if not self:EnsureHooks() then
        self.enabled = false
        error("No supported item-tooltip API is available.")
    end
end

function Runtime:OnDisable()
    self.enabled = false
    local tracked = {}
    for tooltip in pairs(self.trackedTooltips) do
        tracked[#tracked + 1] = tooltip
    end
    for _, tooltip in ipairs(tracked) do
        self:ClearTooltip(tooltip)
    end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Item-ID feature runtime.")
end
