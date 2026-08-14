local _, Addon = ...

local Logic = {}
Addon.UtilityLogic = Logic

local UNKNOWN_ICON = "Interface\\ICONS\\INV_Misc_QuestionMark"
local MAX_CURRENCY_LIST_ENTRIES = 2000

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end
    local ok, result = pcall(callback, ...)
    return ok and result or nil
end

function Logic:GetEntryKey(entry)
    if type(entry) ~= "table" then
        return nil
    elseif tonumber(entry.currencyID) then
        return "currency:" .. tostring(math.floor(tonumber(entry.currencyID)))
    elseif tonumber(entry.itemID) then
        return "item:" .. tostring(math.floor(tonumber(entry.itemID)))
    end
    return nil
end

function Logic:BuildCurrencyRecord(currencyID)
    currencyID = math.floor(tonumber(currencyID) or 0)
    if currencyID <= 0 then
        return nil
    end

    local info = C_CurrencyInfo and safeCall(C_CurrencyInfo.GetCurrencyInfo, currencyID) or nil
    if type(info) ~= "table" then
        return nil
    end

    return {
        currencyID = currencyID,
        name = info.name or ("Currency " .. tostring(currencyID)),
        icon = info.iconFileID or info.icon,
        quantity = math.max(0, math.floor(tonumber(info.quantity) or 0)),
        quality = tonumber(info.quality),
    }
end

function Logic:BuildItemRecord(itemID)
    itemID = math.floor(tonumber(itemID) or 0)
    if itemID <= 0 then
        return nil
    end

    local name = C_Item and safeCall(C_Item.GetItemNameByID, itemID) or nil
    local icon = C_Item and safeCall(C_Item.GetItemIconByID, itemID) or nil
    local quality = C_Item and safeCall(C_Item.GetItemQualityByID, itemID) or nil
    local quantity = C_Item and safeCall(C_Item.GetItemCount, itemID, true, false, true, true) or 0
    return {
        itemID = itemID,
        name = name or ("Item " .. tostring(itemID)),
        icon = icon,
        quality = tonumber(quality),
        quantity = math.max(0, math.floor(tonumber(quantity) or 0)),
    }
end

function Logic:GetListedCurrencyRecords()
    local api = C_CurrencyInfo
    if type(api) ~= "table"
        or type(api.GetCurrencyListSize) ~= "function"
        or type(api.GetCurrencyListInfo) ~= "function"
    then
        return {}
    end

    local records = {}
    local seen = {}
    local collapsedHeaders = {}
    local listSize = math.min(
        MAX_CURRENCY_LIST_ENTRIES,
        math.max(0, math.floor(tonumber(safeCall(api.GetCurrencyListSize)) or 0))
    )
    local index = 1
    while index <= listSize and index <= MAX_CURRENCY_LIST_ENTRIES do
        local info = safeCall(api.GetCurrencyListInfo, index)
        if type(info) == "table" and info.isHeader == true then
            if info.isHeaderExpanded == false and type(api.ExpandCurrencyList) == "function" then
                collapsedHeaders[#collapsedHeaders + 1] = index
                pcall(api.ExpandCurrencyList, index, true)
                listSize = math.min(
                    MAX_CURRENCY_LIST_ENTRIES,
                    math.max(0, math.floor(tonumber(safeCall(api.GetCurrencyListSize)) or listSize))
                )
            end
        elseif type(info) == "table" then
            local currencyID = math.floor(tonumber(
                info.currencyID or info.currencyType or info.currencyTypesID
            ) or 0)
            if currencyID > 0 and not seen[currencyID] then
                local record = self:BuildCurrencyRecord(currencyID)
                if record and (tonumber(record.quantity) or 0) > 0 then
                    records[#records + 1] = record
                    seen[currencyID] = true
                end
            end
        end
        index = index + 1
    end

    if type(api.ExpandCurrencyList) == "function" then
        for headerIndex = #collapsedHeaders, 1, -1 do
            pcall(api.ExpandCurrencyList, collapsedHeaders[headerIndex], false)
        end
    end
    return records
end

function Logic:Scan()
    local snapshot = {
        updatedAt = type(time) == "function" and time() or 0,
        upgrades = {},
        resources = {},
    }

    for _, currencyID in ipairs(Addon.Data.MID_UTILITY_UPGRADE_CRESTS or {}) do
        snapshot.upgrades[tostring(currencyID)] = self:BuildCurrencyRecord(currencyID)
    end
    local knownResourceKeys = {}
    local upgradeCurrencies = {}
    for _, currencyID in ipairs(Addon.Data.MID_UTILITY_UPGRADE_CRESTS or {}) do
        upgradeCurrencies[math.floor(tonumber(currencyID) or 0)] = true
    end
    for _, currencyID in ipairs(Addon.Data.MID_UTILITY_RETIRED_UPGRADE_CRESTS or {}) do
        upgradeCurrencies[math.floor(tonumber(currencyID) or 0)] = true
    end
    for _, entry in ipairs(Addon.Data.MID_UTILITY_RESOURCE_ENTRIES or {}) do
        local entryKey = self:GetEntryKey(entry)
        if entryKey then
            knownResourceKeys[entryKey] = true
            snapshot.resources[entryKey] = entry.currencyID
                and self:BuildCurrencyRecord(entry.currencyID)
                or self:BuildItemRecord(entry.itemID)
        end
    end
    for _, record in ipairs(self:GetListedCurrencyRecords()) do
        local entryKey = self:GetEntryKey(record)
        if entryKey
            and not knownResourceKeys[entryKey]
            and not upgradeCurrencies[tonumber(record.currencyID) or 0]
        then
            knownResourceKeys[entryKey] = true
            snapshot.resources[entryKey] = record
        end
    end
    return snapshot
end

local function copyDisplayRecord(record, fallback, definition)
    local source = type(record) == "table" and record or nil
    local preview = source or (type(fallback) == "table" and fallback or nil)
    return {
        currencyID = definition.currencyID,
        itemID = definition.itemID,
        name = preview and preview.name or "...",
        icon = preview and preview.icon or UNKNOWN_ICON,
        quality = preview and tonumber(preview.quality) or nil,
        quantity = source and math.max(0, math.floor(tonumber(source.quantity) or 0)) or nil,
        available = source ~= nil,
    }
end

function Logic:BuildView(snapshot, fallbackSnapshot, hiddenResources, settings)
    snapshot = type(snapshot) == "table" and snapshot or nil
    fallbackSnapshot = type(fallbackSnapshot) == "table" and fallbackSnapshot or nil
    hiddenResources = type(hiddenResources) == "table" and hiddenResources or {}
    settings = type(settings) == "table" and settings or {}
    local showUpgradeSection = settings.showUpgradeSection ~= false
    local showPvpSection = settings.showPvpSection ~= false

    local view = {
        available = snapshot ~= nil,
        updatedAt = snapshot and tonumber(snapshot.updatedAt) or 0,
        showUpgradeSection = showUpgradeSection,
        showPvpSection = showPvpSection,
        upgrades = {},
        pvp = {},
        resources = {},
        hiddenCount = 0,
    }

    local upgradeDefinitions = {}
    local upgradeKeys = {}
    for _, currencyID in ipairs(Addon.Data.MID_UTILITY_UPGRADE_CRESTS or {}) do
        local key = tostring(currencyID)
        local entryKey = "currency:" .. key
        local record = snapshot and snapshot.upgrades and snapshot.upgrades[key] or nil
        local fallback = fallbackSnapshot and fallbackSnapshot.upgrades and fallbackSnapshot.upgrades[key] or nil
        local definition = { currencyID = currencyID }
        upgradeDefinitions[#upgradeDefinitions + 1] = definition
        upgradeKeys[entryKey] = true
        if showUpgradeSection then
            local display = copyDisplayRecord(record, fallback, definition)
            display.entryKey = entryKey
            view.upgrades[#view.upgrades + 1] = display
        end
    end

    local pvpKeys = {}
    for _, currencyID in ipairs(Addon.Data.MID_UTILITY_PVP_CURRENCIES or {}) do
        local entryKey = "currency:" .. tostring(currencyID)
        pvpKeys[entryKey] = true
        if showPvpSection then
            local record = snapshot and snapshot.resources and snapshot.resources[entryKey] or nil
            local fallback = fallbackSnapshot and fallbackSnapshot.resources
                and fallbackSnapshot.resources[entryKey] or nil
            local display = copyDisplayRecord(record, fallback, { currencyID = currencyID })
            display.entryKey = entryKey
            view.pvp[#view.pvp + 1] = display
        end
    end

    local definitions = {}
    local knownDefinitions = {}
    local function appendDefinition(definition)
        local entryKey = self:GetEntryKey(definition)
        if entryKey and not knownDefinitions[entryKey] then
            knownDefinitions[entryKey] = true
            definitions[#definitions + 1] = definition
        end
    end
    for _, definition in ipairs(Addon.Data.MID_UTILITY_RESOURCE_ENTRIES or {}) do
        appendDefinition(definition)
    end

    local dynamicSource = snapshot and snapshot.resources
        or (fallbackSnapshot and fallbackSnapshot.resources)
        or {}
    local dynamicDefinitions = {}
    for entryKey, record in pairs(type(dynamicSource) == "table" and dynamicSource or {}) do
        if not knownDefinitions[entryKey] and type(record) == "table" then
            dynamicDefinitions[#dynamicDefinitions + 1] = {
                currencyID = record.currencyID,
                itemID = record.itemID,
                name = record.name,
            }
        end
    end
    table.sort(dynamicDefinitions, function(left, right)
        local leftName = string.lower(tostring(left.name or ""))
        local rightName = string.lower(tostring(right.name or ""))
        if leftName ~= rightName then
            return leftName < rightName
        end
        return (tonumber(left.currencyID or left.itemID) or 0)
            < (tonumber(right.currencyID or right.itemID) or 0)
    end)
    for _, definition in ipairs(dynamicDefinitions) do
        appendDefinition(definition)
    end
    if not showUpgradeSection then
        for _, definition in ipairs(upgradeDefinitions) do appendDefinition(definition) end
    end

    for _, definition in ipairs(definitions) do
        local entryKey = self:GetEntryKey(definition)
        if entryKey and showPvpSection and pvpKeys[entryKey] then
            -- Rendered in the compact PvP section above.
        elseif entryKey and hiddenResources[entryKey] == true then
            view.hiddenCount = view.hiddenCount + 1
        elseif entryKey then
            local isUpgrade = upgradeKeys[entryKey] == true
            local upgradeKey = tostring(definition.currencyID or "")
            local record = isUpgrade
                and snapshot and snapshot.upgrades and snapshot.upgrades[upgradeKey]
                or snapshot and snapshot.resources and snapshot.resources[entryKey] or nil
            local fallback = isUpgrade
                and fallbackSnapshot and fallbackSnapshot.upgrades and fallbackSnapshot.upgrades[upgradeKey]
                or fallbackSnapshot and fallbackSnapshot.resources and fallbackSnapshot.resources[entryKey] or nil
            local display = copyDisplayRecord(record, fallback, definition)
            display.entryKey = entryKey
            view.resources[#view.resources + 1] = display
        end
    end
    return view
end
