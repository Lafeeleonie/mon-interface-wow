local _, Addon = ...

local Logic = {}
Addon.InventoryTrackerLogic = Logic

local SOURCE_KEYS = {
    "bags",
    "bank",
    "reagents",
    "equipped",
}

local function normalizeItemID(value)
    value = tonumber(value)
    if not value or value <= 0 then
        return nil
    end
    return math.floor(value)
end

local function normalizeCount(value)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, value)
end

local function mergeItemMetadata(entry, item)
    if type(entry) ~= "table" or type(item) ~= "table" then
        return
    end

    local itemLink = item.itemLink or item.hyperlink or item.link
    local linkedName = type(itemLink) == "string" and itemLink:match("%[(.-)%]") or nil
    local itemName = linkedName or item.itemName or item.name
    if type(itemName) == "string" and itemName ~= "" then
        entry.itemName = itemName
    end
    if type(itemLink) == "string" and itemLink ~= "" then
        entry.itemLink = itemLink
    end
    if item.icon ~= nil or item.iconFileID ~= nil then
        entry.icon = item.icon or item.iconFileID
    end
    if tonumber(item.quality) then
        entry.quality = tonumber(item.quality)
    end
end

local function ensureItem(index, itemID, metadata)
    local entry = index.items[itemID]
    if not entry then
        entry = {
            itemID = itemID,
            characters = {},
            warband = 0,
        }
        index.items[itemID] = entry
    end
    mergeItemMetadata(entry, metadata)
    return entry
end

local function ensureCharacter(entry, characterKey, metadata)
    local character = entry.characters[characterKey]
    if not character then
        character = {
            key = characterKey,
            name = metadata.name,
            realm = metadata.realm,
            classFile = metadata.classFile,
            lastSeen = metadata.lastSeen,
            isCurrent = metadata.isCurrent,
            isMain = metadata.isMain,
            sources = {
                bags = 0,
                bank = 0,
                reagents = 0,
                equipped = 0,
            },
        }
        entry.characters[characterKey] = character
    end
    return character
end

local function addCharacterCount(index, characterKey, metadata, item, sourceKey, count)
    local itemID = normalizeItemID(type(item) == "table" and item.itemID or item)
    count = normalizeCount(count)
    if not itemID or count == 0 then
        return
    end

    local entry = ensureItem(index, itemID, item)
    local character = ensureCharacter(entry, characterKey, metadata)
    character.sources[sourceKey] = normalizeCount(character.sources[sourceKey]) + count
end

local function addContainerSnapshot(index, characterKey, metadata, snapshot, fallbackSource)
    for _, container in ipairs(type(snapshot and snapshot.containers) == "table" and snapshot.containers or {}) do
        local sourceKey = fallbackSource
        if fallbackSource == "bank" and container.kind == "reagents" then
            sourceKey = "reagents"
        end
        for _, item in pairs(type(container and container.items) == "table" and container.items or {}) do
            if type(item) == "table" then
                addCharacterCount(
                    index,
                    characterKey,
                    metadata,
                    item,
                    sourceKey,
                    item.count or 1
                )
            end
        end
    end
end

local function addEquipment(index, characterKey, metadata, equipment)
    for _, item in pairs(type(equipment) == "table" and equipment or {}) do
        if type(item) == "table" and item.empty ~= true then
            addCharacterCount(index, characterKey, metadata, item, "equipped", 1)
        end
    end
end

local function addWarbandSnapshot(index, snapshot)
    for _, container in ipairs(type(snapshot and snapshot.containers) == "table" and snapshot.containers or {}) do
        for _, item in pairs(type(container and container.items) == "table" and container.items or {}) do
            if type(item) == "table" then
                local itemID = normalizeItemID(item.itemID)
                local count = normalizeCount(item.count or 1)
                if itemID and count > 0 then
                    local entry = ensureItem(index, itemID, item)
                    entry.warband = normalizeCount(entry.warband) + count
                end
            end
        end
    end
end

function Logic:BuildIndex(database, currentCharacterKey)
    database = type(database) == "table" and database or {}
    local index = {
        items = {},
        characterCount = 0,
        coverage = {
            characters = 0,
            bagsKnown = 0,
            banksKnown = 0,
            equipmentKnown = 0,
            warbandKnown = false,
        },
    }

    for characterKey, record in pairs(type(database.characters) == "table" and database.characters or {}) do
        local identity = type(record) == "table" and record.identity or nil
        local arsenal = type(record) == "table" and record.arsenal or nil
        if type(characterKey) == "string"
            and characterKey ~= ""
            and type(identity) == "table"
            and type(arsenal) == "table"
        then
            local metadata = {
                name = tostring(identity.name or characterKey),
                realm = tostring(identity.realm or ""),
                classFile = identity.classFile,
                lastSeen = tonumber(identity.lastSeen) or 0,
                isCurrent = characterKey == currentCharacterKey,
                isMain = characterKey == database.mainCharacterKey,
            }
            index.characterCount = index.characterCount + 1
            index.coverage.characters = index.coverage.characters + 1
            if type(arsenal.equipment) == "table" then
                index.coverage.equipmentKnown = index.coverage.equipmentKnown + 1
            end
            if type(arsenal.bags) == "table" then
                index.coverage.bagsKnown = index.coverage.bagsKnown + 1
            end
            if type(arsenal.bank) == "table" then
                index.coverage.banksKnown = index.coverage.banksKnown + 1
            end
            addEquipment(index, characterKey, metadata, arsenal.equipment)
            addContainerSnapshot(index, characterKey, metadata, arsenal.bags, "bags")
            addContainerSnapshot(index, characterKey, metadata, arsenal.bank, "bank")
        end
    end

    local warband = type(database.arsenal) == "table" and database.arsenal.warband or nil
    index.coverage.warbandKnown = type(warband) == "table"
        and (tonumber(warband.updatedAt) or 0) > 0
    addWarbandSnapshot(index, warband)
    return index
end

local function characterTotal(character, includeEquipped)
    local total = 0
    for _, sourceKey in ipairs(SOURCE_KEYS) do
        if sourceKey ~= "equipped" or includeEquipped then
            total = total + normalizeCount(character.sources[sourceKey])
        end
    end
    return total
end

local function sortRows(left, right)
    if left.isCurrent ~= right.isCurrent then
        return left.isCurrent
    end
    if left.isMain ~= right.isMain then
        return left.isMain
    end
    if left.total ~= right.total then
        return left.total > right.total
    end
    if left.lastSeen ~= right.lastSeen then
        return left.lastSeen > right.lastSeen
    end
    local leftName = string.lower(tostring(left.name or left.key or ""))
    local rightName = string.lower(tostring(right.name or right.key or ""))
    if leftName ~= rightName then
        return leftName < rightName
    end
    return string.lower(tostring(left.realm or "")) < string.lower(tostring(right.realm or ""))
end

function Logic:GetItemView(index, itemID, options)
    index = type(index) == "table" and index or {}
    itemID = normalizeItemID(itemID)
    options = type(options) == "table" and options or {}
    if not itemID then
        return nil
    end

    local indexed = type(index.items) == "table" and index.items[itemID] or nil
    if type(indexed) ~= "table" then
        return nil
    end

    local includeEquipped = options.includeEquipped ~= false
    local includeWarband = options.includeWarband ~= false
    local rows = {}
    local duplicateNames = {}
    local total = 0

    for _, character in pairs(type(indexed.characters) == "table" and indexed.characters or {}) do
        local rowTotal = characterTotal(character, includeEquipped)
        if rowTotal > 0 then
            local nameKey = string.lower(tostring(character.name or ""))
            duplicateNames[nameKey] = (duplicateNames[nameKey] or 0) + 1
            rows[#rows + 1] = {
                key = character.key,
                name = character.name,
                realm = character.realm,
                classFile = character.classFile,
                lastSeen = character.lastSeen,
                isCurrent = character.isCurrent == true,
                isMain = character.isMain == true,
                sources = {
                    bags = normalizeCount(character.sources.bags),
                    bank = normalizeCount(character.sources.bank),
                    reagents = normalizeCount(character.sources.reagents),
                    equipped = includeEquipped and normalizeCount(character.sources.equipped) or 0,
                },
                total = rowTotal,
            }
            total = total + rowTotal
        end
    end

    table.sort(rows, sortRows)
    for _, row in ipairs(rows) do
        row.showRealm = duplicateNames[string.lower(tostring(row.name or ""))] > 1
    end

    local warband = includeWarband and normalizeCount(indexed.warband) or 0
    total = total + warband
    if total == 0 then
        return nil
    end

    return {
        itemID = itemID,
        itemName = indexed.itemName,
        itemLink = indexed.itemLink,
        icon = indexed.icon,
        quality = indexed.quality,
        rows = rows,
        warband = warband,
        total = total,
    }
end

local SharedIndex = {
    index = nil,
    arsenalVersion = -1,
    rosterVersion = -1,
    currentCharacterKey = nil,
    mainCharacterKey = nil,
    buildCount = 0,
}

Addon.InventoryIndex = SharedIndex

local function getCurrentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
    if type(identity) == "table" and type(identity.key) == "string" and identity.key ~= "" then
        return identity.key
    end
    return nil
end

function SharedIndex:Invalidate()
    self.index = nil
    self.arsenalVersion = -1
    self.rosterVersion = -1
end

function SharedIndex:GetIndex()
    local arsenalVersion = Addon.StateStore:GetVersion("arsenal.snapshots")
    local rosterVersion = Addon.StateStore:GetVersion("warband.roster")
    local database = Addon.Database:Get()
    local currentCharacterKey = getCurrentCharacterKey()
    local mainCharacterKey = database.mainCharacterKey

    if type(self.index) ~= "table"
        or self.arsenalVersion ~= arsenalVersion
        or self.rosterVersion ~= rosterVersion
        or self.currentCharacterKey ~= currentCharacterKey
        or self.mainCharacterKey ~= mainCharacterKey
    then
        self.index = Logic:BuildIndex(database, currentCharacterKey)
        self.arsenalVersion = arsenalVersion
        self.rosterVersion = rosterVersion
        self.currentCharacterKey = currentCharacterKey
        self.mainCharacterKey = mainCharacterKey
        self.buildCount = self.buildCount + 1
    end
    return self.index
end

function SharedIndex:GetItemView(itemID, options)
    return Logic:GetItemView(self:GetIndex(), itemID, options)
end

function SharedIndex:GetStoredCount(itemID, options)
    local view = self:GetItemView(itemID, options)
    return view and view.total or 0
end

function SharedIndex:GetCoverage()
    local index = self:GetIndex()
    local coverage = type(index.coverage) == "table" and index.coverage or {}
    return {
        characters = math.max(0, tonumber(coverage.characters) or 0),
        bagsKnown = math.max(0, tonumber(coverage.bagsKnown) or 0),
        banksKnown = math.max(0, tonumber(coverage.banksKnown) or 0),
        equipmentKnown = math.max(0, tonumber(coverage.equipmentKnown) or 0),
        warbandKnown = coverage.warbandKnown == true,
    }
end
