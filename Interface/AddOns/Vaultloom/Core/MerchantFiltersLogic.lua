local _, Addon = ...

local Logic = {
    version = 1,
}

Addon.MerchantFiltersLogic = Logic

local VALID_CATEGORIES = {
    all = true,
    recipes = true,
    gear = true,
    collectibles = true,
    decor = true,
}

local GEAR_SLOT_ORDER = {
    "head",
    "neck",
    "shoulder",
    "back",
    "chest",
    "wrist",
    "hands",
    "waist",
    "legs",
    "feet",
    "finger",
    "trinket",
    "weapon",
    "offhand",
}

local GEAR_SLOT_SET = {}
for _, key in ipairs(GEAR_SLOT_ORDER) do
    GEAR_SLOT_SET[key] = true
end

Logic.gearSlotOrder = GEAR_SLOT_ORDER
Logic.gearSlotByEquipLocation = {
    INVTYPE_HEAD = "head",
    INVTYPE_NECK = "neck",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket",
    INVTYPE_WEAPON = "weapon",
    INVTYPE_2HWEAPON = "weapon",
    INVTYPE_WEAPONMAINHAND = "weapon",
    INVTYPE_RANGED = "weapon",
    INVTYPE_RANGEDRIGHT = "weapon",
    INVTYPE_THROWN = "weapon",
    INVTYPE_SHIELD = "offhand",
    INVTYPE_HOLDABLE = "offhand",
    INVTYPE_WEAPONOFFHAND = "offhand",
}

local function isSecretValue(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret == true
end

function Logic:IsSecretValue(value)
    return isSecretValue(value)
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function trim(value)
    if isSecretValue(value) then return "" end
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function Logic:NormalizeText(value)
    value = trim(value)
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("|T.-|t", " ")
    value = value:gsub("%s+", " ")
    return string.lower(value)
end

function Logic:DefaultFilters()
    return {
        category = "all",
        hideKnown = false,
        hideOtherProfessions = false,
        affordableOnly = false,
        usableOnly = false,
        hideAllGear = false,
        hiddenGearSlots = {},
    }
end

function Logic:NormalizeFilters(filters)
    filters = type(filters) == "table" and filters or {}
    local result = self:DefaultFilters()
    if VALID_CATEGORIES[filters.category] then
        result.category = filters.category
    end
    result.hideKnown = filters.hideKnown == true
    result.hideOtherProfessions = filters.hideOtherProfessions == true
    result.affordableOnly = filters.affordableOnly == true
    result.usableOnly = filters.usableOnly == true
    result.hideAllGear = filters.hideAllGear == true
    for key, hidden in pairs(type(filters.hiddenGearSlots) == "table" and filters.hiddenGearSlots or {}) do
        if GEAR_SLOT_SET[key] and hidden == true then
            result.hiddenGearSlots[key] = true
        end
    end
    return result
end

function Logic:CopyFilters(filters)
    return copyTable(self:NormalizeFilters(filters))
end

function Logic:HasActiveFilters(filters)
    filters = self:NormalizeFilters(filters)
    if filters.category ~= "all"
        or filters.hideKnown
        or filters.hideOtherProfessions
        or filters.affordableOnly
        or filters.usableOnly
        or filters.hideAllGear
    then
        return true
    end
    return next(filters.hiddenGearSlots) ~= nil
end

function Logic:GetItemIDFromLink(link)
    return not isSecretValue(link)
        and type(link) == "string"
        and tonumber(link:match("item:(%d+)")) or nil
end

function Logic:GetCurrencyIDFromLink(link)
    return not isSecretValue(link)
        and type(link) == "string"
        and tonumber(link:match("currency:(%d+)")) or nil
end

function Logic:GetNPCIDFromGUID(guid)
    if isSecretValue(guid) or type(guid) ~= "string" or guid == "" then
        return nil
    end
    local unitType, npcID = guid:match("^([^-]+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    if (unitType == "Creature" or unitType == "Vehicle") and tonumber(npcID) then
        return tonumber(npcID)
    end
    return nil
end

function Logic:GetMerchantKey(guid, name)
    local npcID = self:GetNPCIDFromGUID(guid)
    if npcID then
        return "npc:" .. tostring(npcID)
    end
    local normalizedName = self:NormalizeText(name):gsub("%s+", "_")
    if normalizedName == "" then
        normalizedName = "unknown"
    end
    return "name:" .. normalizedName
end

function Logic:ResolveCost(cost, getCurrencyInfo, getItemInfo, getOwnedAmount)
    cost = type(cost) == "table" and cost or {}
    local result = {
        amount = math.max(0, tonumber(cost.amount) or 0),
        texture = cost.texture,
        link = cost.link,
        name = cost.name,
        currencyID = tonumber(cost.currencyID) or self:GetCurrencyIDFromLink(cost.link),
        itemID = tonumber(cost.itemID) or self:GetItemIDFromLink(cost.link),
        owned = tonumber(cost.owned),
        quality = tonumber(cost.quality),
    }

    if result.currencyID and type(getCurrencyInfo) == "function" then
        local info = getCurrencyInfo(result.currencyID)
        if type(info) == "table" then
            result.name = type(info.name) == "string" and info.name ~= "" and info.name or result.name
            result.texture = info.iconFileID or info.icon or result.texture
            result.owned = tonumber(info.quantity) or result.owned
            result.quality = tonumber(info.quality) or result.quality
        end
    elseif result.itemID and type(getItemInfo) == "function" then
        local info = getItemInfo(result.itemID)
        if type(info) == "table" then
            result.name = type(info.name) == "string" and info.name ~= "" and info.name or result.name
            result.texture = info.icon or info.texture or result.texture
            result.quality = tonumber(info.quality) or result.quality
        end
    end

    if type(getOwnedAmount) == "function" then
        local owned = getOwnedAmount(result)
        if tonumber(owned) ~= nil then
            result.owned = tonumber(owned)
        end
    end

    if result.currencyID then
        result.key = "currency:" .. tostring(result.currencyID)
    elseif result.itemID then
        result.key = "item:" .. tostring(result.itemID)
    else
        result.key = "cost:" .. self:NormalizeText(result.name) .. ":" .. tostring(result.texture or "")
    end
    return result
end

function Logic:NormalizeApiAffordability(value)
    local ok, normalized = pcall(function()
        if value == false then
            return "false"
        elseif value == true then
            return "true"
        end
        return "unknown"
    end)
    if not ok then
        return nil
    elseif normalized == "false" then
        return false
    elseif normalized == "true" then
        return true
    end
    return nil
end

function Logic:IsAffordable(price, costs, money, apiAffordable)
    apiAffordable = self:NormalizeApiAffordability(apiAffordable)
    if apiAffordable == false then
        return false
    end
    price = math.max(0, tonumber(price) or 0)
    if tonumber(money) and price > tonumber(money) then
        return false
    end
    for _, cost in ipairs(type(costs) == "table" and costs or {}) do
        local required = math.max(0, tonumber(cost.amount) or 0)
        if cost.owned ~= nil and tonumber(cost.owned) < required then
            return false
        end
    end
    return true
end

local function categoryMatches(entry, category)
    if category == "recipes" then
        return entry.isRecipe == true
    elseif category == "gear" then
        return entry.isGear == true
    elseif category == "collectibles" then
        return entry.isMount == true
            or entry.isPet == true
            or entry.isToy == true
            or entry.isCosmetic == true
    elseif category == "decor" then
        return entry.isDecor == true
    end
    return true
end

function Logic:MatchesSearch(entry, query)
    query = self:NormalizeText(query)
    if query == "" then
        return true
    end
    local haystack = self:NormalizeText(table.concat({
        tostring(entry.name or ""),
        tostring(entry.tagText or ""),
        tostring(entry.requiredProfession or ""),
        tostring(entry.itemType or ""),
        tostring(entry.itemSubType or ""),
    }, " "))
    return haystack:find(query, 1, true) ~= nil
end

function Logic:PassesFilters(entry, filters, query)
    if type(entry) ~= "table" then
        return false
    end
    filters = self:NormalizeFilters(filters)
    if not categoryMatches(entry, filters.category) then
        return false
    end
    if filters.hideKnown and entry.isKnown == true then
        return false
    end
    if filters.hideOtherProfessions and entry.isOtherProfessionRecipe == true then
        return false
    end
    if filters.affordableOnly and entry.isAffordable ~= true then
        return false
    end
    if filters.usableOnly and entry.isUsable == false then
        return false
    end
    if filters.hideAllGear and entry.isGear == true then
        return false
    end
    if entry.gearSlot and filters.hiddenGearSlots[entry.gearSlot] == true then
        return false
    end
    return self:MatchesSearch(entry, query)
end

function Logic:FilterItems(items, filters, query)
    local result = {}
    local summary = {
        total = 0,
        visible = 0,
        hidden = 0,
    }
    for _, entry in ipairs(type(items) == "table" and items or {}) do
        summary.total = summary.total + 1
        if self:PassesFilters(entry, filters, query) then
            result[#result + 1] = entry
            summary.visible = summary.visible + 1
        else
            summary.hidden = summary.hidden + 1
        end
    end
    return result, summary
end
