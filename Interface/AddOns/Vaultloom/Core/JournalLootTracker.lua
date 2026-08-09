local _, Addon = ...

local Tracker = {}
Addon.JournalLootTracker = Tracker

local VALID_DIFFICULTIES = {
    lfr = true,
    normal = true,
    heroic = true,
    mythic = true,
}

local VALID_STATES = {
    wish = true,
    obtained = true,
}

local CONTENT_ORDER = {
    raids = 1,
    dungeons = 2,
}

local DIFFICULTY_ORDER = {
    lfr = 1,
    normal = 2,
    heroic = 3,
    mythic = 4,
}

local function normalizeText(value)
    return type(value) == "string" and value or nil
end

local function normalizePositiveNumber(value)
    value = tonumber(value)
    return value and value > 0 and value or nil
end

local function itemKey(itemID)
    itemID = normalizePositiveNumber(itemID)
    return itemID and tostring(math.floor(itemID)) or nil
end

local function getStateRoot()
    local db = Addon.Database:Get()
    db.raidLootTracker = type(db.raidLootTracker) == "table" and db.raidLootTracker or {}
    return db.raidLootTracker
end

local function getCatalogRoot()
    local db = Addon.Database:Get()
    db.journalLootCatalog = type(db.journalLootCatalog) == "table" and db.journalLootCatalog or {}
    return db.journalLootCatalog
end

local function sanitizeSource(source)
    if type(source) ~= "table" then return nil end
    local mainTabKey = source.mainTabKey == "dungeons" and "dungeons"
        or source.mainTabKey == "raids" and "raids" or nil
    if not mainTabKey then return nil end

    return {
        mainTabKey = mainTabKey,
        subTabKey = normalizeText(source.subTabKey),
        raidKey = normalizeText(source.raidKey),
        bossKey = normalizeText(source.bossKey),
        instanceID = normalizePositiveNumber(source.instanceID),
        encounterID = normalizePositiveNumber(source.encounterID),
        instanceName = normalizeText(source.instanceName),
        bossName = normalizeText(source.bossName),
    }
end

local function sourceKey(source)
    return table.concat({
        tostring(source.mainTabKey or ""),
        tostring(source.subTabKey or ""),
        tostring(source.instanceID or source.raidKey or ""),
        tostring(source.encounterID or source.bossKey or ""),
    }, ":")
end

local function copySource(source)
    return {
        mainTabKey = source.mainTabKey,
        subTabKey = source.subTabKey,
        raidKey = source.raidKey,
        bossKey = source.bossKey,
        instanceID = source.instanceID,
        encounterID = source.encounterID,
        instanceName = source.instanceName,
        bossName = source.bossName,
    }
end

local function copyItemMetadata(item)
    item = type(item) == "table" and item or {}
    return {
        itemID = normalizePositiveNumber(item.itemID),
        name = normalizeText(item.name),
        link = normalizeText(item.link),
        icon = item.icon,
        quality = tonumber(item.quality),
        slot = normalizeText(item.slot),
        armorType = normalizeText(item.armorType),
        veryRare = item.veryRare == true or item.isVeryRare == true,
        extremelyRare = item.extremelyRare == true or item.isExtremelyRare == true,
    }
end

local function mergeItemMetadata(target, item)
    local incoming = copyItemMetadata(item)
    target.itemID = target.itemID or incoming.itemID
    target.name = incoming.name or target.name
    target.link = incoming.link or target.link
    target.icon = incoming.icon or target.icon
    target.quality = incoming.quality or target.quality
    target.slot = incoming.slot or target.slot
    target.armorType = incoming.armorType or target.armorType
    target.veryRare = incoming.veryRare or target.veryRare == true
    target.extremelyRare = incoming.extremelyRare or target.extremelyRare == true
end

local function removeCatalogEntry(characterKey, difficultyKey, itemID)
    local root = getCatalogRoot()
    local character = root[characterKey]
    local difficulty = type(character) == "table" and character[difficultyKey] or nil
    local key = itemKey(itemID)
    if type(difficulty) ~= "table" or not key then return end

    difficulty[key] = nil
    if next(difficulty) == nil then character[difficultyKey] = nil end
    if next(character) == nil then root[characterKey] = nil end
end

local function requestItemData(itemID)
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function resolveItemMetadata(itemID, stored)
    local result = copyItemMetadata(stored)
    result.itemID = itemID

    if (not result.name or result.name == "") and C_Item and type(C_Item.GetItemNameByID) == "function" then
        result.name = C_Item.GetItemNameByID(itemID)
    end
    if not result.icon and C_Item and type(C_Item.GetItemIconByID) == "function" then
        result.icon = C_Item.GetItemIconByID(itemID)
    end

    if type(GetItemInfo) == "function" and (not result.name or not result.link or not result.icon or result.quality == nil) then
        local name, link, quality, _, _, _, _, _, slot, icon = GetItemInfo(itemID)
        result.name = result.name or name
        result.link = result.link or link
        result.quality = result.quality or quality
        result.slot = result.slot or slot
        result.icon = result.icon or icon
    end

    if not result.name or result.name == "" then
        result.name = string.format((Addon.L and Addon.L.RAID_JOURNAL_ITEM_FALLBACK) or "Item %d", itemID)
        requestItemData(itemID)
    end
    result.icon = result.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    return result
end

local function sourceMatchesFilter(sources, sourceFilter)
    if sourceFilter == nil or sourceFilter == "all" then return true end
    for _, source in ipairs(sources or {}) do
        if source.mainTabKey == sourceFilter then return true end
    end
    return false
end

local function primarySourceForFilter(sources, sourceFilter)
    if sourceFilter and sourceFilter ~= "all" then
        for _, source in ipairs(sources or {}) do
            if source.mainTabKey == sourceFilter then return source end
        end
    end
    return sources and sources[1] or nil
end

local function normalizedSortText(value)
    return string.lower(tostring(value or ""))
end

function Tracker:IsDifficultyKey(difficultyKey)
    return VALID_DIFFICULTIES[difficultyKey] == true
end

function Tracker:GetState(characterKey, difficultyKey, itemID)
    local key = itemKey(itemID)
    local root = getStateRoot()
    local character = type(characterKey) == "string" and root[characterKey] or nil
    local difficulty = type(character) == "table" and character[difficultyKey] or nil
    local state = type(difficulty) == "table" and key and difficulty[key] or nil
    return state == "wish" and "wish" or (state == "obtained" and "obtained" or nil)
end

function Tracker:RegisterItem(characterKey, difficultyKey, item, source)
    local itemID = type(item) == "table" and item.itemID or item
    local key = itemKey(itemID)
    if type(characterKey) ~= "string" or characterKey == ""
        or not self:IsDifficultyKey(difficultyKey)
        or not key
        or not self:GetState(characterKey, difficultyKey, itemID)
    then
        return false
    end

    local root = getCatalogRoot()
    root[characterKey] = type(root[characterKey]) == "table" and root[characterKey] or {}
    local character = root[characterKey]
    character[difficultyKey] = type(character[difficultyKey]) == "table" and character[difficultyKey] or {}
    local difficulty = character[difficultyKey]
    local record = type(difficulty[key]) == "table" and difficulty[key] or {
        itemID = tonumber(itemID),
        sources = {},
    }
    difficulty[key] = record
    record.sources = type(record.sources) == "table" and record.sources or {}
    mergeItemMetadata(record, type(item) == "table" and item or { itemID = itemID })

    local cleanSource = sanitizeSource(source)
    if cleanSource then
        local keyToMerge = sourceKey(cleanSource)
        local replaced = false
        for index, existing in ipairs(record.sources) do
            if sourceKey(existing) == keyToMerge then
                record.sources[index] = cleanSource
                replaced = true
                break
            end
        end
        if not replaced then record.sources[#record.sources + 1] = cleanSource end
    end
    return true
end

function Tracker:CycleState(characterKey, difficultyKey, itemID, isDifficultyKey, item, source)
    itemID = tonumber(itemID)
    if type(characterKey) ~= "string" or characterKey == ""
        or type(difficultyKey) ~= "string" or difficultyKey == ""
        or type(isDifficultyKey) ~= "function" or not isDifficultyKey(difficultyKey)
        or not itemID or itemID <= 0
    then
        return nil
    end

    local db = Addon.Database:Get()
    db.raidLootTracker = type(db.raidLootTracker) == "table" and db.raidLootTracker or {}
    db.raidLootTracker[characterKey] = type(db.raidLootTracker[characterKey]) == "table" and db.raidLootTracker[characterKey] or {}
    local character = db.raidLootTracker[characterKey]
    character[difficultyKey] = type(character[difficultyKey]) == "table" and character[difficultyKey] or {}
    local difficulty = character[difficultyKey]
    local key = itemKey(itemID)
    local current = difficulty[key]
    local nextState = current == "wish" and "obtained" or (current == "obtained" and nil or "wish")
    difficulty[key] = nextState

    if next(difficulty) == nil then character[difficultyKey] = nil end
    if next(character) == nil then db.raidLootTracker[characterKey] = nil end

    if nextState then
        self:RegisterItem(characterKey, difficultyKey, type(item) == "table" and item or { itemID = itemID }, source)
    else
        removeCatalogEntry(characterKey, difficultyKey, itemID)
    end
    return nextState
end

function Tracker:CycleEntry(characterKey, difficultyKey, itemID)
    return self:CycleState(characterKey, difficultyKey, itemID, function(key)
        return VALID_DIFFICULTIES[key] == true
    end)
end

function Tracker:RemoveEntry(characterKey, difficultyKey, itemID)
    local key = itemKey(itemID)
    if type(characterKey) ~= "string" or characterKey == ""
        or not VALID_DIFFICULTIES[difficultyKey]
        or not key
    then
        return false
    end

    local root = getStateRoot()
    local character = root[characterKey]
    local difficulty = type(character) == "table" and character[difficultyKey] or nil
    if type(difficulty) ~= "table" or not VALID_STATES[difficulty[key]] then
        return false
    end

    difficulty[key] = nil
    if next(difficulty) == nil then character[difficultyKey] = nil end
    if next(character) == nil then root[characterKey] = nil end
    removeCatalogEntry(characterKey, difficultyKey, itemID)
    return true
end

function Tracker:GetCounts(characterKey)
    local counts = {
        wish = 0,
        obtained = 0,
    }
    local root = getStateRoot()
    local character = type(characterKey) == "string" and root[characterKey] or nil
    if type(character) ~= "table" then return counts end

    for difficultyKey, difficulty in pairs(character) do
        if VALID_DIFFICULTIES[difficultyKey] and type(difficulty) == "table" then
            for _, state in pairs(difficulty) do
                if state == "wish" then
                    counts.wish = counts.wish + 1
                elseif state == "obtained" then
                    counts.obtained = counts.obtained + 1
                end
            end
        end
    end
    return counts
end

function Tracker:GetEntries(characterKey, statusFilter, sourceFilter)
    statusFilter = VALID_STATES[statusFilter] and statusFilter or "all"
    sourceFilter = CONTENT_ORDER[sourceFilter] and sourceFilter or "all"

    local stateRoot = getStateRoot()
    local catalogRoot = getCatalogRoot()
    local stateCharacter = type(characterKey) == "string" and stateRoot[characterKey] or nil
    local catalogCharacter = type(characterKey) == "string" and catalogRoot[characterKey] or nil
    if type(stateCharacter) ~= "table" then return {} end

    local entries = {}
    for difficultyKey, difficulty in pairs(stateCharacter) do
        if VALID_DIFFICULTIES[difficultyKey] and type(difficulty) == "table" then
            for storedItemID, state in pairs(difficulty) do
                local itemID = tonumber(storedItemID)
                if itemID and VALID_STATES[state] and (statusFilter == "all" or statusFilter == state) then
                    local catalogDifficulty = type(catalogCharacter) == "table" and catalogCharacter[difficultyKey] or nil
                    local catalog = type(catalogDifficulty) == "table" and catalogDifficulty[tostring(storedItemID)] or nil
                    local sources = {}
                    for _, source in ipairs(type(catalog) == "table" and catalog.sources or {}) do
                        local clean = sanitizeSource(source)
                        if clean then sources[#sources + 1] = copySource(clean) end
                    end
                    if sourceMatchesFilter(sources, sourceFilter) then
                        entries[#entries + 1] = {
                            key = string.format("%s:%d", difficultyKey, itemID),
                            characterKey = characterKey,
                            difficultyKey = difficultyKey,
                            itemID = itemID,
                            state = state,
                            item = resolveItemMetadata(itemID, catalog),
                            sources = sources,
                            primarySource = primarySourceForFilter(sources, sourceFilter),
                        }
                    end
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        local aSource = a.primarySource
        local bSource = b.primarySource
        local aContent = CONTENT_ORDER[aSource and aSource.mainTabKey] or 99
        local bContent = CONTENT_ORDER[bSource and bSource.mainTabKey] or 99
        if aContent ~= bContent then return aContent < bContent end

        local aInstance = normalizedSortText(aSource and aSource.instanceName)
        local bInstance = normalizedSortText(bSource and bSource.instanceName)
        if aInstance ~= bInstance then return aInstance < bInstance end

        local aBoss = normalizedSortText(aSource and aSource.bossName)
        local bBoss = normalizedSortText(bSource and bSource.bossName)
        if aBoss ~= bBoss then return aBoss < bBoss end

        local aDifficulty = DIFFICULTY_ORDER[a.difficultyKey] or 99
        local bDifficulty = DIFFICULTY_ORDER[b.difficultyKey] or 99
        if aDifficulty ~= bDifficulty then return aDifficulty < bDifficulty end

        local aName = normalizedSortText(a.item and a.item.name)
        local bName = normalizedSortText(b.item and b.item.name)
        if aName ~= bName then return aName < bName end
        return a.itemID < b.itemID
    end)
    return entries
end
