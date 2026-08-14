local _, Addon = ...

local Logic = {}
Addon.ArsenalLogic = Logic

local SLOT_COLUMNS = {
    left = {
        { name = "HeadSlot", labelKey = "ARSENAL_SLOT_HEAD" },
        { name = "NeckSlot", labelKey = "ARSENAL_SLOT_NECK" },
        { name = "ShoulderSlot", labelKey = "ARSENAL_SLOT_SHOULDER" },
        { name = "BackSlot", labelKey = "ARSENAL_SLOT_BACK" },
        { name = "ChestSlot", labelKey = "ARSENAL_SLOT_CHEST" },
        { name = "WristSlot", labelKey = "ARSENAL_SLOT_WRIST" },
        { name = "HandsSlot", labelKey = "ARSENAL_SLOT_HANDS" },
        { name = "WaistSlot", labelKey = "ARSENAL_SLOT_WAIST" },
    },
    right = {
        { name = "LegsSlot", labelKey = "ARSENAL_SLOT_LEGS" },
        { name = "FeetSlot", labelKey = "ARSENAL_SLOT_FEET" },
        { name = "Finger0Slot", labelKey = "ARSENAL_SLOT_FINGER_1" },
        { name = "Finger1Slot", labelKey = "ARSENAL_SLOT_FINGER_2" },
        { name = "Trinket0Slot", labelKey = "ARSENAL_SLOT_TRINKET_1" },
        { name = "Trinket1Slot", labelKey = "ARSENAL_SLOT_TRINKET_2" },
        { name = "MainHandSlot", labelKey = "ARSENAL_SLOT_MAIN_HAND" },
        { name = "SecondaryHandSlot", labelKey = "ARSENAL_SLOT_OFF_HAND" },
    },
}

local TOTAL_EQUIPMENT_SLOTS = #SLOT_COLUMNS.left + #SLOT_COLUMNS.right
local QUALITY_BY_LINK_COLOR = {
    ["9d9d9d"] = 0,
    ["ffffff"] = 1,
    ["1eff00"] = 2,
    ["0070dd"] = 3,
    ["a335ee"] = 4,
    ["ff8000"] = 5,
    ["e6cc80"] = 6,
    ["00ccff"] = 7,
}

function Logic:GetSlotColumns()
    return SLOT_COLUMNS
end

function Logic:GetSlotLabel(definition)
    if type(definition) ~= "table" then
        return Addon.L.UNKNOWN
    end
    return Addon.L[definition.labelKey] or definition.name or Addon.L.UNKNOWN
end

function Logic:GetSlotID(definition)
    if type(definition) ~= "table" or type(GetInventorySlotInfo) ~= "function" then
        return nil, nil
    end
    local ok, slotID, emptyTexture = pcall(GetInventorySlotInfo, definition.name)
    if not ok then
        return nil, nil
    end
    return tonumber(slotID), emptyTexture
end

function Logic:ParseItemID(value)
    if type(value) == "number" and value > 0 then
        return math.floor(value)
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end

    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, value)
        if ok and tonumber(itemID) and tonumber(itemID) > 0 then
            return math.floor(tonumber(itemID))
        end
    end
    local itemID = tonumber(value:match("item:(%-?%d+)"))
    return itemID and itemID > 0 and math.floor(itemID) or nil
end

function Logic:GetItemName(itemLink, itemID)
    if type(itemLink) == "string" and itemLink ~= "" then
        local linkedName = itemLink:match("%[(.-)%]")
        if linkedName and linkedName ~= "" then
            return linkedName
        end
    end
    if itemID then
        local display = Addon.WoWApi:GetItemDisplayName(itemID)
        if type(display) == "string" and display ~= "" then
            return display:match("%[(.-)%]") or display
        end
    end
    return Addon.L.UNKNOWN
end

function Logic:ResolveQuality(quality, itemLink, itemID)
    quality = tonumber(quality)
    if quality ~= nil then
        return quality
    end

    if type(itemLink) == "string" then
        local linkColor = itemLink:match("^|c%x%x(%x%x%x%x%x%x)")
        quality = linkColor and QUALITY_BY_LINK_COLOR[linkColor:lower()] or nil
        if quality ~= nil then
            return quality
        end
    end

    local item = itemLink or itemID
    if item and C_Item and type(C_Item.GetItemQualityByID) == "function" then
        local ok, resolved = pcall(C_Item.GetItemQualityByID, item)
        if ok and tonumber(resolved) ~= nil then
            return tonumber(resolved)
        end
    end
    if item and type(GetItemInfo) == "function" then
        local ok, _, _, resolved = pcall(GetItemInfo, item)
        if ok and tonumber(resolved) ~= nil then
            return tonumber(resolved)
        end
    end
    return nil
end

function Logic:GetQualityColor(quality, itemLink, itemID)
    quality = self:ResolveQuality(quality, itemLink, itemID)
    local color = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality] or nil
    if color then
        return { color.r or 1, color.g or 1, color.b or 1, 1 }
    end
    return Addon.Theme.colors.goldDim
end

function Logic:IsUpgradeIncomplete(upgradeTrack)
    if type(upgradeTrack) ~= "string" or upgradeTrack == "" then
        return false
    end
    local current, maximum = upgradeTrack:match("(%d+)%s*/%s*(%d+)")
    current, maximum = tonumber(current), tonumber(maximum)
    return current ~= nil and maximum ~= nil and maximum > 0 and current < maximum
end

function Logic:GetSlotIssue(entry)
    entry = type(entry) == "table" and entry or {}
    local empty = entry.empty == true or type(entry.itemLink) ~= "string" or entry.itemLink == ""
    local missingEnchant = not empty and entry.enchantable == true and entry.enchanted ~= true
    local emptySockets = not empty and math.max(0, tonumber(entry.emptySockets) or 0) or 0
    local upgradeable = not empty and self:IsUpgradeIncomplete(entry.upgradeTrack)
    return {
        empty = empty,
        missingEnchant = missingEnchant,
        emptySockets = emptySockets,
        upgradeable = upgradeable,
        hasIssue = empty or missingEnchant or emptySockets > 0 or upgradeable,
    }
end

function Logic:BuildEquipmentSummary(equipment)
    equipment = type(equipment) == "table" and equipment or {}
    local summary = {
        totalSlots = TOTAL_EQUIPMENT_SLOTS,
        equipped = 0,
        emptySlots = 0,
        missingEnchants = 0,
        emptySockets = 0,
        upgradeable = 0,
        issueSlots = 0,
        durabilityCurrent = 0,
        durabilityMaximum = 0,
    }

    for _, column in pairs(SLOT_COLUMNS) do
        for _, definition in ipairs(column) do
            local slotID = self:GetSlotID(definition)
            local entry = slotID and equipment[slotID] or nil
            local issue = self:GetSlotIssue(entry)
            if issue.empty then
                summary.emptySlots = summary.emptySlots + 1
            else
                summary.equipped = summary.equipped + 1
            end
            if issue.hasIssue then summary.issueSlots = summary.issueSlots + 1 end
            if issue.missingEnchant then summary.missingEnchants = summary.missingEnchants + 1 end
            summary.emptySockets = summary.emptySockets + issue.emptySockets
            if issue.upgradeable then summary.upgradeable = summary.upgradeable + 1 end
            if entry then
                summary.durabilityCurrent = summary.durabilityCurrent
                    + math.max(0, tonumber(entry.durabilityCurrent) or 0)
                summary.durabilityMaximum = summary.durabilityMaximum
                    + math.max(0, tonumber(entry.durabilityMaximum) or 0)
            end
        end
    end

    summary.durabilityPercent = summary.durabilityMaximum > 0
        and math.floor(((summary.durabilityCurrent / summary.durabilityMaximum) * 100) + 0.5) or nil
    return summary
end

function Logic:CountContainer(container)
    local totalSlots = math.max(0, tonumber(container and container.totalSlots) or 0)
    local occupied = 0
    for _, item in pairs(type(container and container.items) == "table" and container.items or {}) do
        if type(item) == "table" and tonumber(item.itemID) then
            occupied = occupied + 1
        end
    end
    return occupied, totalSlots, math.max(0, totalSlots - occupied)
end

function Logic:GetContainer(snapshot, selectedIndex)
    local containers = type(snapshot and snapshot.containers) == "table" and snapshot.containers or {}
    selectedIndex = math.max(1, math.min(#containers, math.floor(tonumber(selectedIndex) or 1)))
    return containers[selectedIndex], selectedIndex, containers
end
