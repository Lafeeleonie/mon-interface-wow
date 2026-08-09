local _, Addon = ...

local Logic = {
    schemaVersion = 1,
    coordinateScale = 10000,
    cellSize = 32,
    mergeRadius = {
        mining = 25,
        herbalism = 25,
        leather = 65,
        wood = 65,
        fish = 65,
        cooking = 65,
    },
}

Addon.GatheringNodesLogic = Logic

local VALID_KINDS = {
    mining = true,
    herbalism = true,
    leather = true,
    wood = true,
    fish = true,
    cooking = true,
}

local KIND_ORDER = {
    mining = 1,
    herbalism = 2,
    leather = 3,
    wood = 4,
    fish = 5,
    cooking = 6,
}

local WORDS = {
    mining = {
        "ore", "mineral", "metal", "stone", "deposit", "vein",
        "erz", "mineral", "metall", "stein", "vorkommen", "ader",
        "aqirite", "bismuth", "ironclaw", "umbraltin", "karesh",
    },
    herbalism = {
        "herb", "flower", "blossom", "bloom", "root", "pollen", "moss", "leaf",
        "lotus", "thistle", "vine", "lichen",
        "kraut", "kräut", "blume", "blüte", "wurzel", "pollen", "moos", "blatt",
        "lotus", "distel", "ranke", "flechte",
        "argentleaf", "arathorsspear", "arathorsspeer", "azeroot", "luredrop",
        "manalily", "sanguithorn",
    },
    leather = {
        "leather", "hide", "pelt", "scale", "chitin", "carapace", "fur", "skin",
        "leder", "haut", "häute", "balg", "fell", "pelz", "schuppe", "schuppen",
    },
    wood = {
        "wood", "timber", "lumber", "log", "plank", "branch",
        "woodcutting", "lumbering",
        "holz", "bauholz", "stamm", "ast", "planke", "holzfällen",
    },
    fish = {
        "fish", "fillet", "salmon", "trout", "herring", "eel", "tuna", "mackerel",
        "clam", "crab", "shrimp", "bass", "carp", "cod", "minnow", "snapper",
        "catfish", "sturgeon", "sole", "shark", "octopus", "squid",
        "fisch", "filet", "lachs", "forelle", "hering", "aal", "thunfisch",
        "makrele", "muschel", "krabbe", "garnele", "karpfen", "kabeljau",
        "elritze", "schnapper", "wels", "stör", "hai", "oktopus", "kalmar",
    },
    cooking = {
        "meat", "steak", "rib", "breast", "flank", "bacon", "ham", "sausage",
        "egg", "flour", "spice", "pepper", "salt", "sugar", "honey", "milk",
        "cheese", "oil", "cooking",
        "fleisch", "rippe", "rippen", "brust", "flanke", "speck", "schinken",
        "wurst", "ei", "eier", "mehl", "gewürz", "pfeffer", "salz", "zucker",
        "honig", "milch", "käse", "öl", "kochreagenz",
    },
}

local function rounded(value)
    value = tonumber(value) or 0
    return math.floor(value + 0.5)
end

local function copyNode(node)
    local copy = {}
    for key, value in pairs(node or {}) do copy[key] = value end
    return copy
end

function Logic:IsValidKind(kind)
    return VALID_KINDS[kind] == true
end

function Logic:GetKindOrder(kind)
    return KIND_ORDER[kind] or 99
end

function Logic:NormalizeText(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("|A:[^|]+|a", " ")
    text = text:gsub("|T[^|]+|t", " ")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h%[([^%]]+)%]|h", "%1")
    text = text:gsub("%b()", " ")
    text = text:gsub("[%-_/]", " ")
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("%s+", " ")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

function Logic:QuantizeCoordinate(value)
    value = tonumber(value)
    if not value or value <= 0 or value > 1 then return nil end
    return math.max(1, math.min(self.coordinateScale, rounded(value * self.coordinateScale)))
end

function Logic:ExpandCoordinate(value)
    value = tonumber(value)
    if not value then return nil end
    return value / self.coordinateScale
end

function Logic:GetCellKey(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil end
    return string.format("%d:%d", math.floor(x / self.cellSize), math.floor(y / self.cellSize))
end

function Logic:GetResourceKey(kind, itemID, name, nodeName)
    if not self:IsValidKind(kind) then return nil end
    local normalizedNodeName = self:NormalizeText(nodeName)
    if (kind == "mining" or kind == "herbalism") and normalizedNodeName ~= "" then
        return string.format("%s:node:%s", kind, normalizedNodeName)
    end
    itemID = tonumber(itemID)
    if itemID and itemID > 0 then
        return string.format("%s:item:%d", kind, itemID)
    end
    local normalized = self:NormalizeText(name)
    if normalized == "" then return nil end
    return string.format("%s:name:%s", kind, normalized)
end

function Logic:GetNodeKey(node)
    if type(node) ~= "table" then return nil end
    local resourceKey = self:GetResourceKey(node.kind, node.itemID, node.name, node.nodeName)
    local x, y = tonumber(node.x), tonumber(node.y)
    if not resourceKey or not x or not y then return nil end
    return string.format("%s:%d:%d", resourceKey, x, y)
end

function Logic:NormalizeNode(node, mapID)
    if type(node) ~= "table" then return nil end
    local kind = self:IsValidKind(node.kind) and node.kind or nil
    if not kind then return nil end

    local x = tonumber(node.x)
    local y = tonumber(node.y)
    if x and x > 0 and x <= 1 then x = self:QuantizeCoordinate(x) end
    if y and y > 0 and y <= 1 then y = self:QuantizeCoordinate(y) end
    x, y = rounded(x), rounded(y)
    if x <= 0 or y <= 0 or x > self.coordinateScale or y > self.coordinateScale then
        return nil
    end

    local itemID = tonumber(node.itemID)
    if itemID and itemID <= 0 then itemID = nil end
    local nodeName = tostring(node.nodeName or "")
    nodeName = nodeName:gsub("^%s+", ""):gsub("%s+$", "")
    local name = tostring(node.name or node.itemName or nodeName or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" and not itemID then return nil end

    local normalized = {
        kind = kind,
        itemID = itemID,
        name = name ~= "" and name or nil,
        nodeName = nodeName ~= "" and nodeName or nil,
        icon = node.icon or node.itemIcon,
        x = x,
        y = y,
    }
    if tonumber(mapID or node.mapID) then normalized.mapID = tonumber(mapID or node.mapID) end
    normalized.resourceKey = self:GetResourceKey(kind, itemID, name, nodeName)
    normalized.key = self:GetNodeKey(normalized)
    return normalized.resourceKey and normalized.key and normalized or nil
end

function Logic:CreateStore(source)
    source = type(source) == "table" and source or {}
    local result = {
        version = self.schemaVersion,
        maps = {},
    }
    local sourceMaps = type(source.maps) == "table" and source.maps or {}
    for rawMapID, bucket in pairs(sourceMaps) do
        local mapID = tonumber(rawMapID)
        if mapID and type(bucket) == "table" then
            local cleanBucket = {}
            local nodes = type(bucket.nodes) == "table" and bucket.nodes or bucket
            for _, rawNode in pairs(nodes) do
                local node = self:NormalizeNode(rawNode, mapID)
                if node then
                    node.mapID = nil
                    cleanBucket[node.key] = node
                    node.key = nil
                    node.resourceKey = nil
                end
            end
            if next(cleanBucket) then result.maps[tostring(mapID)] = cleanBucket end
        end
    end
    return result
end

function Logic:BuildIndex(store)
    local index = {
        maps = {},
        total = 0,
    }
    for rawMapID, bucket in pairs(type(store) == "table" and store.maps or {}) do
        local mapID = tonumber(rawMapID)
        if mapID and type(bucket) == "table" then
            local mapIndex = {
                cells = {},
                count = 0,
            }
            index.maps[mapID] = mapIndex
            for key, rawNode in pairs(bucket) do
                local node = self:NormalizeNode(rawNode, mapID)
                if node then
                    local cellKey = self:GetCellKey(node.x, node.y)
                    local cell = mapIndex.cells[cellKey]
                    if not cell then
                        cell = {}
                        mapIndex.cells[cellKey] = cell
                    end
                    cell[key] = true
                    mapIndex.count = mapIndex.count + 1
                    index.total = index.total + 1
                end
            end
        end
    end
    return index
end

function Logic:FindNearby(store, index, mapID, candidate, radius)
    mapID = tonumber(mapID)
    candidate = self:NormalizeNode(candidate, mapID)
    if not mapID or not candidate then return nil end
    local bucket = store and store.maps and store.maps[tostring(mapID)]
    local mapIndex = index and index.maps and index.maps[mapID]
    if type(bucket) ~= "table" or type(mapIndex) ~= "table" then return nil end

    radius = tonumber(radius) or self.mergeRadius[candidate.kind] or 25
    local radiusSquared = radius * radius
    local cellX = math.floor(candidate.x / self.cellSize)
    local cellY = math.floor(candidate.y / self.cellSize)
    local cellRange = math.max(1, math.ceil(radius / self.cellSize))
    local bestKey, bestDistance
    for offsetX = -cellRange, cellRange do
        for offsetY = -cellRange, cellRange do
            local cell = mapIndex.cells[string.format("%d:%d", cellX + offsetX, cellY + offsetY)]
            for key in pairs(cell or {}) do
                local node = self:NormalizeNode(bucket[key], mapID)
                if node and node.resourceKey == candidate.resourceKey then
                    local dx, dy = node.x - candidate.x, node.y - candidate.y
                    local distance = (dx * dx) + (dy * dy)
                    if distance <= radiusSquared and (not bestDistance or distance < bestDistance) then
                        bestKey, bestDistance = key, distance
                    end
                end
            end
        end
    end
    return bestKey, bestDistance
end

function Logic:AddNode(store, index, mapID, rawNode)
    mapID = tonumber(mapID)
    local node = self:NormalizeNode(rawNode, mapID)
    if not mapID or not node then return nil, false end

    store.maps = type(store.maps) == "table" and store.maps or {}
    local mapKey = tostring(mapID)
    local bucket = store.maps[mapKey]
    if type(bucket) ~= "table" then
        bucket = {}
        store.maps[mapKey] = bucket
    end
    index.maps = type(index.maps) == "table" and index.maps or {}
    local mapIndex = index.maps[mapID]
    if type(mapIndex) ~= "table" then
        mapIndex = { cells = {}, count = 0 }
        index.maps[mapID] = mapIndex
    end

    local nearbyKey = self:FindNearby(store, index, mapID, node)
    if nearbyKey then
        local existing = bucket[nearbyKey]
        if type(existing) == "table" then
            existing.itemID = node.itemID or existing.itemID
            existing.name = node.name or existing.name
            existing.nodeName = node.nodeName or existing.nodeName
            existing.icon = node.icon or existing.icon
        end
        return nearbyKey, false
    end

    local baseKey = node.key
    local key = baseKey
    local suffix = 1
    while bucket[key] ~= nil do
        suffix = suffix + 1
        key = baseKey .. ":" .. suffix
    end

    local stored = copyNode(node)
    stored.mapID = nil
    stored.key = nil
    stored.resourceKey = nil
    bucket[key] = stored

    local cellKey = self:GetCellKey(node.x, node.y)
    mapIndex.cells[cellKey] = mapIndex.cells[cellKey] or {}
    mapIndex.cells[cellKey][key] = true
    mapIndex.count = (tonumber(mapIndex.count) or 0) + 1
    index.total = (tonumber(index.total) or 0) + 1
    return key, true
end

function Logic:RemoveNode(store, index, mapID, key)
    mapID = tonumber(mapID)
    local bucket = mapID and store and store.maps and store.maps[tostring(mapID)] or nil
    local rawNode = type(bucket) == "table" and bucket[key] or nil
    local node = self:NormalizeNode(rawNode, mapID)
    if not node then return false end

    bucket[key] = nil
    if not next(bucket) then store.maps[tostring(mapID)] = nil end
    local mapIndex = index and index.maps and index.maps[mapID]
    if mapIndex then
        local cell = mapIndex.cells[self:GetCellKey(node.x, node.y)]
        if cell then
            cell[key] = nil
            if not next(cell) then mapIndex.cells[self:GetCellKey(node.x, node.y)] = nil end
        end
        mapIndex.count = math.max(0, (tonumber(mapIndex.count) or 1) - 1)
        if mapIndex.count == 0 then index.maps[mapID] = nil end
    end
    index.total = math.max(0, (tonumber(index.total) or 1) - 1)
    return true
end

function Logic:ClearMap(store, index, mapID)
    mapID = tonumber(mapID)
    local bucket = mapID and store and store.maps and store.maps[tostring(mapID)] or nil
    if type(bucket) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(bucket) do count = count + 1 end
    store.maps[tostring(mapID)] = nil
    if index and index.maps then index.maps[mapID] = nil end
    if index then index.total = math.max(0, (tonumber(index.total) or 0) - count) end
    return count
end

function Logic:ClearAll(store, index)
    local count = tonumber(index and index.total) or 0
    store.maps = {}
    if index then
        index.maps = {}
        index.total = 0
    end
    return count
end

function Logic:GetNodesForMap(store, mapID)
    mapID = tonumber(mapID)
    local bucket = mapID and store and store.maps and store.maps[tostring(mapID)] or nil
    local result = {}
    for key, rawNode in pairs(type(bucket) == "table" and bucket or {}) do
        local node = self:NormalizeNode(rawNode, mapID)
        if node then
            node.key = key
            result[#result + 1] = node
        end
    end
    table.sort(result, function(first, second)
        local firstOrder, secondOrder = self:GetKindOrder(first.kind), self:GetKindOrder(second.kind)
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        local firstName = self:NormalizeText(first.name)
        local secondName = self:NormalizeText(second.name)
        if firstName ~= secondName then return firstName < secondName end
        if first.y ~= second.y then return first.y < second.y end
        return first.x < second.x
    end)
    return result
end

function Logic:GetNodesNear(store, index, mapID, x, y, xRadius, yRadius)
    mapID = tonumber(mapID)
    x, y = tonumber(x), tonumber(y)
    xRadius = math.min(self.coordinateScale, math.max(1, tonumber(xRadius) or self.cellSize))
    yRadius = math.min(self.coordinateScale, math.max(1, tonumber(yRadius) or self.cellSize))
    local bucket = mapID and store and store.maps and store.maps[tostring(mapID)] or nil
    local mapIndex = mapID and index and index.maps and index.maps[mapID] or nil
    if not x or not y or type(bucket) ~= "table" or type(mapIndex) ~= "table" then return {} end

    local maximumCell = math.floor(self.coordinateScale / self.cellSize)
    local minimumCellX = math.max(0, math.floor((x - xRadius) / self.cellSize))
    local maximumCellX = math.min(maximumCell, math.floor((x + xRadius) / self.cellSize))
    local minimumCellY = math.max(0, math.floor((y - yRadius) / self.cellSize))
    local maximumCellY = math.min(maximumCell, math.floor((y + yRadius) / self.cellSize))
    local result, seen = {}, {}
    local queriedCellCount = (maximumCellX - minimumCellX + 1) * (maximumCellY - minimumCellY + 1)
    local indexedNodeCount = math.max(1, tonumber(mapIndex.count) or 0)

    -- Tiny or malformed map dimensions can turn a short minimap range into tens of
    -- thousands of empty grid lookups. Scanning the map bucket is cheaper whenever
    -- it contains fewer entries than the requested grid contains cells.
    if queriedCellCount > indexedNodeCount then
        for key, rawNode in pairs(bucket) do
            local node = self:NormalizeNode(rawNode, mapID)
            if node and math.abs(node.x - x) <= xRadius and math.abs(node.y - y) <= yRadius then
                node.key = key
                result[#result + 1] = node
            end
        end
        return result
    end

    for cellX = minimumCellX, maximumCellX do
        for cellY = minimumCellY, maximumCellY do
            local cell = mapIndex.cells[string.format("%d:%d", cellX, cellY)]
            for key in pairs(cell or {}) do
                if not seen[key] then
                    seen[key] = true
                    local node = self:NormalizeNode(bucket[key], mapID)
                    if node and math.abs(node.x - x) <= xRadius and math.abs(node.y - y) <= yRadius then
                        node.key = key
                        result[#result + 1] = node
                    end
                end
            end
        end
    end
    return result
end

function Logic:BuildCatalog(store)
    local entriesByKey = {}
    for rawMapID, bucket in pairs(type(store) == "table" and store.maps or {}) do
        local mapID = tonumber(rawMapID)
        for _, rawNode in pairs(type(bucket) == "table" and bucket or {}) do
            local node = self:NormalizeNode(rawNode, mapID)
            if node then
                local entry = entriesByKey[node.resourceKey]
                if not entry then
                    entry = {
                        key = node.resourceKey,
                        kind = node.kind,
                        itemID = node.itemID,
                        name = node.name,
                        icon = node.icon,
                        count = 0,
                    }
                    entriesByKey[node.resourceKey] = entry
                end
                entry.name = entry.name or node.name
                entry.icon = entry.icon or node.icon
                entry.count = entry.count + 1
            end
        end
    end

    local result = {}
    for _, entry in pairs(entriesByKey) do result[#result + 1] = entry end
    table.sort(result, function(first, second)
        local firstOrder, secondOrder = self:GetKindOrder(first.kind), self:GetKindOrder(second.kind)
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        return self:NormalizeText(first.name) < self:NormalizeText(second.name)
    end)
    return result
end

function Logic:Cluster(nodes, radius)
    radius = math.max(1, tonumber(radius) or 90)
    local cellSize = radius
    local radiusSquared = radius * radius
    local cells, clusters = {}, {}

    for _, node in ipairs(nodes or {}) do
        local cellX, cellY = math.floor(node.x / cellSize), math.floor(node.y / cellSize)
        local matched
        for offsetX = -1, 1 do
            for offsetY = -1, 1 do
                local cell = cells[string.format("%d:%d", cellX + offsetX, cellY + offsetY)]
                for _, cluster in ipairs(cell or {}) do
                    local dx, dy = cluster.x - node.x, cluster.y - node.y
                    if (dx * dx) + (dy * dy) <= radiusSquared then
                        matched = cluster
                        break
                    end
                end
                if matched then break end
            end
            if matched then break end
        end

        if matched then
            matched.members[#matched.members + 1] = node
            matched.count = #matched.members
            matched.x = rounded(((matched.x * (matched.count - 1)) + node.x) / matched.count)
            matched.y = rounded(((matched.y * (matched.count - 1)) + node.y) / matched.count)
        else
            matched = {
                kind = node.kind,
                itemID = node.itemID,
                name = node.name,
                icon = node.icon,
                mapID = node.mapID,
                x = node.x,
                y = node.y,
                count = 1,
                members = { node },
            }
            clusters[#clusters + 1] = matched
            local cellKey = string.format("%d:%d", cellX, cellY)
            cells[cellKey] = cells[cellKey] or {}
            cells[cellKey][#cells[cellKey] + 1] = matched
        end
    end
    local result = {}
    for _, cluster in ipairs(clusters) do
        result[#result + 1] = cluster.count == 1 and cluster.members[1] or cluster
    end
    return result
end

function Logic:ContainsWord(value, words)
    local text = self:NormalizeText(value)
    local tokens = {}
    for token in text:gmatch("%S+") do tokens[token] = true end
    for _, word in ipairs(words or {}) do
        if tokens[word] then return true end
        if #word >= 4 then
            for token in pairs(tokens) do
                if #token > #word
                    and (token:sub(1, #word) == word or token:sub(-#word) == word)
                then
                    return true
                end
            end
        end
    end
    return false
end

function Logic:ClassifyLoot(itemInfo, context)
    if type(itemInfo) ~= "table" then return nil end
    context = type(context) == "table" and context or {}
    if context.kind == "mining" or context.kind == "herbalism" then
        return context.kind
    end
    if context.recentFishing == true then return "fish" end

    local text = tostring(itemInfo.name or "") .. " " .. tostring(itemInfo.subType or "")
    if self:ContainsWord(text, WORDS.fish) then return "fish" end
    if context.subclassKind and VALID_KINDS[context.subclassKind] then
        return context.subclassKind
    end
    if self:ContainsWord(text, WORDS.leather) then return "leather" end
    if self:ContainsWord(text, WORDS.mining) then return "mining" end
    if self:ContainsWord(text, WORDS.herbalism) then return "herbalism" end
    if self:ContainsWord(text, WORDS.wood) then return "wood" end
    if self:ContainsWord(text, WORDS.cooking) then return "cooking" end
    return nil
end
