local _, Addon = ...

local Logic = {}
Addon.ItemFinderLogic = Logic

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalizeText(value)
    value = trim(value)
    value = value:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
    return string.lower(value)
end

local function parseItemID(value)
    if type(value) == "number" and value > 0 then
        return math.floor(value)
    end
    value = trim(value)
    if value == "" then
        return nil
    end
    local itemID = tonumber(value:match("item:(%d+)")) or tonumber(value:match("^#?(%d+)$"))
    return itemID and itemID > 0 and math.floor(itemID) or nil
end

local function nameMatches(name, normalizedQuery)
    name = normalizeText(name)
    if name == "" or normalizedQuery == "" then
        return nil
    end
    if name == normalizedQuery then
        return 1
    end
    if name:find(normalizedQuery, 1, true) == 1 then
        return 2
    end

    for token in normalizedQuery:gmatch("%S+") do
        if not name:find(token, 1, true) then
            return nil
        end
    end
    return 3
end

local function resultSort(left, right)
    if left.matchScore ~= right.matchScore then
        return left.matchScore < right.matchScore
    end
    if left.total ~= right.total then
        return left.total > right.total
    end
    local leftName = normalizeText(left.itemName)
    local rightName = normalizeText(right.itemName)
    if leftName ~= rightName then
        return leftName < rightName
    end
    return left.itemID < right.itemID
end

function Logic:Search(index, query, options)
    index = type(index) == "table" and index or {}
    options = type(options) == "table" and options or {}
    local normalizedQuery = normalizeText(query)
    local exactItemID = parseItemID(query)
    local limit = math.max(1, math.floor(tonumber(options.limit) or 100))
    local results = {}

    if normalizedQuery == "" then
        return results, {
            query = "",
            totalMatches = 0,
            shown = 0,
            truncated = false,
        }
    end

    for itemID, indexed in pairs(type(index.items) == "table" and index.items or {}) do
        itemID = tonumber(itemID)
        local score
        if exactItemID then
            score = itemID == exactItemID and 0 or nil
        else
            score = nameMatches(indexed and indexed.itemName, normalizedQuery)
        end

        if score ~= nil then
            local view = Addon.InventoryTrackerLogic:GetItemView(index, itemID, {
                includeWarband = options.includeWarband ~= false,
                includeEquipped = options.includeEquipped ~= false,
            })
            if view then
                view.matchScore = score
                results[#results + 1] = view
            end
        end
    end

    table.sort(results, resultSort)
    local totalMatches = #results
    for indexToRemove = #results, limit + 1, -1 do
        table.remove(results, indexToRemove)
    end
    return results, {
        query = trim(query),
        totalMatches = totalMatches,
        shown = #results,
        truncated = totalMatches > #results,
    }
end

function Logic:BuildLocationText(result, labels, maxCharacters)
    result = type(result) == "table" and result or {}
    labels = type(labels) == "table" and labels or {}
    maxCharacters = math.max(1, math.floor(tonumber(maxCharacters) or 3))
    local parts = {}
    local shown = math.min(#(result.rows or {}), maxCharacters)

    for index = 1, shown do
        local row = result.rows[index]
        local sources = {}
        for _, sourceKey in ipairs({ "bags", "bank", "reagents", "equipped" }) do
            local count = math.max(0, math.floor(tonumber(row.sources and row.sources[sourceKey]) or 0))
            if count > 0 then
                sources[#sources + 1] = string.format("%s %d", labels[sourceKey] or sourceKey, count)
            end
        end
        local name = tostring(row.name or row.key or labels.unknown or "?")
        if row.showRealm and type(row.realm) == "string" and row.realm ~= "" then
            name = name .. "-" .. row.realm
        end
        parts[#parts + 1] = string.format("%s: %s", name, table.concat(sources, ", "))
    end

    local remaining = #(result.rows or {}) - shown
    if remaining > 0 then
        parts[#parts + 1] = string.format(labels.moreCharacters or "+ %d", remaining)
    end
    if (tonumber(result.warband) or 0) > 0 then
        parts[#parts + 1] = string.format(
            "%s: %d",
            labels.warband or "Warband",
            math.floor(tonumber(result.warband) or 0)
        )
    end
    return table.concat(parts, "  •  ")
end
