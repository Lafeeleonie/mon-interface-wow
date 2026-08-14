local _, Addon = ...

local L = Addon.L
local Logic = {}
Addon.CompendiumLogic = Logic

Logic.CATEGORY_ORDER = { "all", "mounts", "pets", "toys", "decorations", "recipes" }
Logic.SOURCE_ORDER = {
    "renown", "reputation", "drop", "achievement", "quest", "treasure", "delve", "prey",
    "promotion", "dungeon", "raid", "pvp", "worldevent", "event", "profession", "trainer",
    "vendor", "discovery", "specialization", "crafted", "tradingpost", "prepatch",
    "eversong", "zulaman", "harandar", "voidstorm", "coiled_isle", "wild",
}
Logic.CATEGORY_ICONS = {
    all = "Interface\\Icons\\INV_Misc_Book_09",
    mounts = "Interface\\Icons\\Ability_Mount_RidingHorse",
    pets = "Interface\\Icons\\INV_Box_PetCarrier_01",
    toys = "Interface\\Icons\\INV_Misc_Toy_10",
    decorations = "Interface\\Icons\\INV_Misc_Statue_02",
    recipes = "Interface\\Icons\\INV_Scroll_03",
}

local RECIPE_SOURCE_RANK = {
    trainer = 1, vendor = 2, discovery = 3, specialization = 4, profession = 5,
    drop = 6, crafted = 7, treasure = 8, quest = 9, dungeon = 10, raid = 11,
}
local SOURCE_LABEL_KEYS = {
    achievement = "COMPENDIUM_SOURCE_ACHIEVEMENT",
    crafted = "COMPENDIUM_SOURCE_CRAFTED",
    delve = "COMPENDIUM_SOURCE_DELVE",
    discovery = "COMPENDIUM_SOURCE_DISCOVERY",
    drop = "COMPENDIUM_SOURCE_DROP",
    dungeon = "COMPENDIUM_SOURCE_DUNGEON",
    event = "COMPENDIUM_SOURCE_EVENT",
    eversong = "COMPENDIUM_SOURCE_EVERSONG",
    harandar = "COMPENDIUM_SOURCE_HARANDAR",
    prepatch = "COMPENDIUM_SOURCE_PREPATCH",
    prey = "COMPENDIUM_SOURCE_PREY",
    profession = "COMPENDIUM_SOURCE_PROFESSION",
    promotion = "COMPENDIUM_SOURCE_PROMOTION",
    pvp = "COMPENDIUM_SOURCE_PVP",
    quest = "COMPENDIUM_SOURCE_QUEST",
    raid = "COMPENDIUM_SOURCE_RAID",
    renown = "COMPENDIUM_SOURCE_RENOWN",
    reputation = "COMPENDIUM_SOURCE_REPUTATION",
    specialization = "COMPENDIUM_SOURCE_SPECIALIZATION",
    trainer = "COMPENDIUM_SOURCE_TRAINER",
    tradingpost = "COMPENDIUM_SOURCE_TRADING_POST",
    treasure = "COMPENDIUM_SOURCE_TREASURE",
    vendor = "COMPENDIUM_SOURCE_VENDOR",
    voidstorm = "COMPENDIUM_SOURCE_VOIDSTORM",
    coiled_isle = "COMPENDIUM_SOURCE_COILED_ISLE",
    wild = "COMPENDIUM_SOURCE_WILD",
    worldevent = "COMPENDIUM_SOURCE_WORLD_EVENT",
    zulaman = "COMPENDIUM_SOURCE_ZULAMAN",
}
local PROFESSION_LABEL_KEYS = {
    alchemy = "COMPENDIUM_PROFESSION_ALCHEMY",
    blacksmithing = "COMPENDIUM_PROFESSION_BLACKSMITHING",
    cooking = "COMPENDIUM_PROFESSION_COOKING",
    enchanting = "COMPENDIUM_PROFESSION_ENCHANTING",
    engineering = "COMPENDIUM_PROFESSION_ENGINEERING",
    inscription = "COMPENDIUM_PROFESSION_INSCRIPTION",
    jewelcrafting = "COMPENDIUM_PROFESSION_JEWELCRAFTING",
    leatherworking = "COMPENDIUM_PROFESSION_LEATHERWORKING",
    tailoring = "COMPENDIUM_PROFESSION_TAILORING",
}
local CATEGORY_LABEL_KEYS = {
    all = "COMPENDIUM_CATEGORY_ALL",
    mounts = "COMPENDIUM_CATEGORY_MOUNTS",
    pets = "COMPENDIUM_CATEGORY_PETS",
    toys = "COMPENDIUM_CATEGORY_TOYS",
    decorations = "COMPENDIUM_CATEGORY_DECORATIONS",
    recipes = "COMPENDIUM_CATEGORY_RECIPES",
}
local ZONE_MAP_IDS = {
    ["Broken Throne Ritual Site"] = 2437,
    ["Coiled Isle"] = 2512,
    ["Daggerspine Point Ritual Site"] = 2395,
    ["Eversong Woods"] = 2395,
    ["Harandar"] = 2413,
    ["Isle of Quel'Danas"] = 2424,
    ["Silvermoon City"] = 2393,
    ["Schattenhochland"] = 241,
    ["Twilight Highlands"] = 241,
    ["Voidstorm"] = 2405,
    ["Zul'Aman"] = 2437,
}
local ITEM_ICON_FALLBACKS = {
    [268481] = "Interface\\Icons\\INV_Cooking_80_ChoralHoney3",
    [269828] = "Interface\\Icons\\INV_Weapon_Shortblade_28",
    [269829] = "Interface\\Icons\\INV_BabyAmaniEagle_Burgundy",
    [275436] = "Interface\\Icons\\INV_Misc_Noose_01",
}

local function normalizeSearch(value)
    value = tostring(value or ""):lower()
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value
end

local function prettifyKey(value)
    value = tostring(value or ""):gsub("[_%-]+", " ")
    return value:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest:lower() end)
end

local function localized(value, key)
    if type(key) == "string" and type(L[key]) == "string" and L[key] ~= "" then return L[key] end
    return type(value) == "string" and value ~= "" and value or nil
end

function Logic:GetCategoryLabel(key)
    return L[CATEGORY_LABEL_KEYS[key] or ""] or prettifyKey(key)
end

function Logic:GetSourceLabel(key)
    return L[SOURCE_LABEL_KEYS[key] or ""] or prettifyKey(key)
end

function Logic:GetProfessionLabel(key, fallback)
    return L[PROFESSION_LABEL_KEYS[key] or ""] or fallback or prettifyKey(key)
end

function Logic:GetCategoryIcon(key)
    return self.CATEGORY_ICONS[key] or self.CATEGORY_ICONS.all
end

function Logic:PrepareCatalog(catalog)
    if type(catalog) ~= "table" or type(catalog.entries) ~= "table" then return nil end
    local prepared = {
        catalog = catalog,
        entries = catalog.entries,
        categoryRank = {},
        sourceRank = {},
        professionRank = {},
        professionBySkillLine = {},
        entryByKey = {},
        rawCounts = {},
    }
    for index, key in ipairs(self.CATEGORY_ORDER) do prepared.categoryRank[key] = index end
    for index, key in ipairs(self.SOURCE_ORDER) do prepared.sourceRank[key] = index end
    for index, profession in ipairs(type(catalog.professionOrder) == "table" and catalog.professionOrder or {}) do
        prepared.professionRank[profession.key] = index
        if tonumber(profession.skillLine) then
            prepared.professionBySkillLine[tonumber(profession.skillLine)] = profession.key
        end
    end
    for _, entry in ipairs(catalog.entries) do
        if type(entry) == "table" and type(entry.key) == "string" and entry.key ~= "" then
            prepared.entryByKey[entry.key] = entry
            prepared.rawCounts[entry.category] = (prepared.rawCounts[entry.category] or 0) + 1
        end
    end
    prepared.rawCounts.all = #catalog.entries
    return prepared
end

local function getItemNameAndIcon(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil end
    local name, icon
    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, result = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(result) == "string" and result ~= "" then name = result end
    end
    if type(GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, result = pcall(GetItemInfoInstant, itemID)
        if ok and result and result ~= 0 and result ~= "" then icon = result end
    elseif C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, result = pcall(C_Item.GetItemIconByID, itemID)
        if ok and result and result ~= 0 then icon = result end
    end
    return name, icon or ITEM_ICON_FALLBACKS[itemID]
end

local function getSpellNameAndIcon(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil, nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID end
    end
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local okName, name = pcall(C_Spell.GetSpellName, spellID)
        local okIcon, icon = false, nil
        if type(C_Spell.GetSpellTexture) == "function" then okIcon, icon = pcall(C_Spell.GetSpellTexture, spellID) end
        return okName and name or nil, okIcon and icon or nil
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok then return name, icon end
    end
end

local function resolveMountID(entry)
    local mountID = tonumber(entry.mountID)
    if mountID then return mountID end
    local itemID = tonumber(entry.itemID)
    if itemID and C_MountJournal and type(C_MountJournal.GetMountFromItem) == "function" then
        local ok, value = pcall(C_MountJournal.GetMountFromItem, itemID)
        if ok and tonumber(value) then return tonumber(value) end
    end
    local spellID = tonumber(entry.spellID or entry.id)
    if spellID and C_MountJournal and type(C_MountJournal.GetMountFromSpell) == "function" then
        local ok, value = pcall(C_MountJournal.GetMountFromSpell, spellID)
        if ok and tonumber(value) then return tonumber(value) end
    end
end

local function decorationOwnedCount(info)
    if type(info) ~= "table" then return nil end
    if info.numPlaced == nil and info.quantity == nil and info.remainingRedeemable == nil then return nil end
    return (tonumber(info.numPlaced) or 0)
        + (tonumber(info.quantity) or 0)
        + (tonumber(info.remainingRedeemable) or 0)
end

local function decorationInfo(entry, context)
    local name, icon, ownedCount
    local decorID, itemID = tonumber(entry.decorID), tonumber(entry.itemID)
    if decorID and C_HousingDecor and type(C_HousingDecor.GetDecorName) == "function" then
        local ok, value = pcall(C_HousingDecor.GetDecorName, decorID)
        if ok and type(value) == "string" and value ~= "" then name = value end
    end
    if decorID and C_HousingDecor and type(C_HousingDecor.GetDecorIcon) == "function" then
        local ok, value = pcall(C_HousingDecor.GetDecorIcon, decorID)
        if ok and value and value ~= 0 then icon = value end
    end

    local function apply(info)
        if type(info) ~= "table" then return end
        if type(info.name) == "string" and info.name ~= "" then name = info.name end
        if info.iconTexture and info.iconTexture ~= 0 then icon = icon or info.iconTexture end
        local apiCount = decorationOwnedCount(info)
        local stored = context.getDecorationCount and context.getDecorationCount(entry) or nil
        if apiCount ~= nil then
            if apiCount > 0 then context.housingCatalogObserved = true end
            if apiCount <= 0 and stored and stored > 0 and not context.housingCatalogObserved then
                ownedCount = stored
            elseif apiCount <= 0 and not context.housingCatalogObserved then
                ownedCount = stored
            else
                ownedCount = apiCount
                if context.rememberDecorationCount then context.rememberDecorationCount(entry, apiCount) end
            end
        elseif stored ~= nil then
            ownedCount = stored
        end
    end

    if decorID and C_HousingCatalog and type(C_HousingCatalog.GetCatalogEntryInfoByRecordID) == "function" then
        local entryType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or 1
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, entryType, decorID, true)
        if ok then apply(info) end
    end
    if ownedCount == nil and itemID and C_HousingCatalog and type(C_HousingCatalog.GetCatalogEntryInfoByItem) == "function" then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID, true)
        if ok then apply(info) end
    end
    if ownedCount == nil and context.getDecorationCount then ownedCount = context.getDecorationCount(entry) end
    if not name or not icon then
        local itemName, itemIcon = getItemNameAndIcon(itemID)
        name, icon = name or itemName, icon or itemIcon
    end
    return name, icon, ownedCount
end

function Logic:GetActiveProfessions(prepared, identity)
    local active, apiAvailable = {}, type(identity and identity.professions) == "table"
    for _, profession in ipairs(apiAvailable and identity.professions or {}) do
        local key = prepared.professionBySkillLine[tonumber(profession.skillLineID)]
        if not key then
            local name = normalizeSearch(profession.name)
            for _, definition in ipairs(prepared.catalog.professionOrder or {}) do
                if name == normalizeSearch(definition.label)
                    or name == normalizeSearch(self:GetProfessionLabel(definition.key, definition.label))
                then
                    key = definition.key
                    break
                end
            end
        end
        if key then active[key] = true end
    end
    return active, apiAvailable
end

local function isOppositeFaction(entry, runtime)
    if type(entry.faction) ~= "string" or entry.faction == "" or runtime.statusKey == "collected" then return false end
    if type(UnitFactionGroup) ~= "function" then return false end
    local ok, faction = pcall(UnitFactionGroup, "player")
    return ok and type(faction) == "string" and faction ~= "" and faction ~= entry.faction
end

function Logic:ResolveRuntime(entry, context)
    local name = entry.name or L.UNKNOWN
    local icon = self:GetCategoryIcon(entry.category)
    local collected, ownedCount
    if entry.category == "mounts" then
        local mountID = resolveMountID(entry)
        if mountID and C_MountJournal and type(C_MountJournal.GetMountInfoByID) == "function" then
            local ok, mountName, _, mountIcon, _, _, _, _, _, _, _, isCollected =
                pcall(C_MountJournal.GetMountInfoByID, mountID)
            if ok then
                if type(mountName) == "string" and mountName ~= "" then name = mountName end
                if mountIcon and mountIcon ~= 0 then icon = mountIcon end
                collected = isCollected == true
            end
        end
        if tonumber(entry.itemID) and icon == self:GetCategoryIcon(entry.category) then
            local itemName, itemIcon = getItemNameAndIcon(entry.itemID)
            name, icon = itemName or name, itemIcon or icon
        end
    elseif entry.category == "pets" then
        if tonumber(entry.speciesID) and C_PetJournal and type(C_PetJournal.GetPetInfoBySpeciesID) == "function" then
            local ok, petName, petIcon = pcall(C_PetJournal.GetPetInfoBySpeciesID, tonumber(entry.speciesID))
            if ok then
                if type(petName) == "string" and petName ~= "" then name = petName end
                if petIcon and petIcon ~= 0 then icon = petIcon end
            end
        end
        if tonumber(entry.speciesID) and C_PetJournal and type(C_PetJournal.GetNumCollectedInfo) == "function" then
            local ok, count = pcall(C_PetJournal.GetNumCollectedInfo, tonumber(entry.speciesID))
            if ok then collected = (tonumber(count) or 0) > 0 end
        end
    elseif entry.category == "toys" then
        local itemName, itemIcon = getItemNameAndIcon(entry.itemID)
        name, icon = itemName or name, itemIcon or icon
        if tonumber(entry.itemID) and C_ToyBox and type(C_ToyBox.GetToyInfo) == "function" then
            local ok, _, toyName, toyIcon = pcall(C_ToyBox.GetToyInfo, tonumber(entry.itemID))
            if ok then
                if type(toyName) == "string" and toyName ~= "" then name = toyName end
                if toyIcon and toyIcon ~= 0 then icon = toyIcon end
            end
        end
        if tonumber(entry.itemID) and type(PlayerHasToy) == "function" then
            local ok, value = pcall(PlayerHasToy, tonumber(entry.itemID))
            if ok then collected = value == true end
        end
    elseif entry.category == "decorations" then
        local decorName, decorIcon
        decorName, decorIcon, ownedCount = decorationInfo(entry, context)
        name, icon = decorName or name, decorIcon or icon
        if ownedCount ~= nil then collected = ownedCount > 0 end
    elseif entry.category == "recipes" then
        local spellName, spellIcon = getSpellNameAndIcon(entry.spellID or entry.id)
        name, icon = spellName or name, spellIcon or icon
        if type(IsPlayerSpell) == "function" and tonumber(entry.spellID or entry.id) then
            local ok, value = pcall(IsPlayerSpell, tonumber(entry.spellID or entry.id))
            if ok then collected = value == true end
        end
    end

    local statusKey = collected == true and "collected" or collected == false and "missing" or "unknown"
    local statusLabel
    if entry.category == "decorations" and ownedCount ~= nil then
        statusLabel = tostring(math.floor(ownedCount))
    elseif statusKey == "collected" and entry.category == "recipes" then
        statusLabel = L.COMPENDIUM_STATUS_LEARNED
    elseif statusKey == "collected" then
        statusLabel = L.COMPENDIUM_STATUS_COLLECTED
    elseif statusKey == "missing" then
        statusLabel = L.COMPENDIUM_STATUS_MISSING
    else
        statusLabel = L.COMPENDIUM_STATUS_UNKNOWN
    end

    local sourceLabel = self:GetSourceLabel(entry.source)
    local categoryLabel = self:GetCategoryLabel(entry.category)
    local professionLabel = entry.professionKey and self:GetProfessionLabel(entry.professionKey, entry.profession) or nil
    local searchText = normalizeSearch(table.concat({
        name or "", entry.name or "", entry.itemID or "", entry.spellID or "", entry.mountID or "",
        categoryLabel or "", sourceLabel or "", entry.zone or "",
        localized(entry.vendor, entry.vendorKey) or "",
        localized(entry.quest, entry.questKey) or "",
        localized(entry.sourceDetail, entry.sourceDetailKey) or "",
        entry.cost and (localized(entry.cost.text, entry.cost.textKey) or "") or "",
        professionLabel or "", entry.subcategory or "",
    }, " "))
    return {
        name = name,
        icon = icon,
        statusKey = statusKey,
        statusLabel = statusLabel,
        ownedCount = ownedCount,
        sourceLabel = sourceLabel,
        categoryLabel = categoryLabel,
        professionLabel = professionLabel,
        searchText = searchText,
    }
end

local function addStats(stats, statusKey)
    stats.total = (stats.total or 0) + 1
    stats[statusKey] = (stats[statusKey] or 0) + 1
end

function Logic:BuildRuntime(prepared, context)
    context = type(context) == "table" and context or {}
    local activeProfessions, professionApiAvailable = self:GetActiveProfessions(prepared, context.identity)
    local runtime = {
        prepared = prepared,
        records = {},
        categoryStats = { all = {} },
        waypointCount = 0,
        activeProfessions = activeProfessions,
        professionApiAvailable = professionApiAvailable,
        generatedAt = type(time) == "function" and time() or 0,
    }
    for _, categoryKey in ipairs(self.CATEGORY_ORDER) do runtime.categoryStats[categoryKey] = {} end
    for _, entry in ipairs(prepared.entries) do
        local include = type(entry) == "table"
            and not (entry.category == "recipes" and professionApiAvailable and not activeProfessions[entry.professionKey])
        if include then
            local info = self:ResolveRuntime(entry, context)
            include = (entry.unavailable ~= true or entry.showUnavailable == true or info.statusKey == "collected")
                and not isOppositeFaction(entry, info)
            if include then
                local record = { entry = entry, runtime = info }
                runtime.records[#runtime.records + 1] = record
                runtime.categoryStats[entry.category] = runtime.categoryStats[entry.category] or {}
                addStats(runtime.categoryStats[entry.category], info.statusKey)
                addStats(runtime.categoryStats.all, info.statusKey)
                if self:GetWaypoint(entry) then runtime.waypointCount = runtime.waypointCount + 1 end
            end
        end
    end
    return runtime
end

local function normalizeState(state)
    state = type(state) == "table" and state or {}
    local categories = { all = true, mounts = true, pets = true, toys = true, decorations = true, recipes = true }
    local statuses = { all = true, missing = true, collected = true, unknown = true }
    if not categories[state.category] then state.category = "all" end
    if not statuses[state.status] then state.status = "missing" end
    state.source = type(state.source) == "string" and state.source ~= "" and state.source or "all"
    state.profession = type(state.profession) == "string" and state.profession ~= "" and state.profession or "all"
    state.search = type(state.search) == "string" and state.search or ""
    if state.category ~= "recipes" then state.profession = "all" end
    return state
end

local function statusRank(key)
    return key == "missing" and 1 or key == "unknown" and 2 or 3
end

local function matchesStatus(status, selected)
    return selected == "all" or status == selected
end

function Logic:BuildView(runtimeState, uiState)
    uiState = normalizeState(uiState)
    if type(runtimeState) ~= "table" then
        return {
            state = uiState, entries = {}, categoryStats = {}, sourceOptions = {},
            professionOptions = {}, waypointCount = 0,
        }
    end
    local prepared = runtimeState.prepared
    local search = normalizeSearch(uiState.search)
    local base, visible, sourceCounts, professionCounts = {}, {}, {}, {}
    for _, record in ipairs(runtimeState.records) do
        local entry, info = record.entry, record.runtime
        local matches = (uiState.category == "all" or entry.category == uiState.category)
            and (uiState.profession == "all" or entry.professionKey == uiState.profession)
            and (search == "" or info.searchText:find(search, 1, true))
        if matches then
            base[#base + 1] = record
            sourceCounts[entry.source] = (sourceCounts[entry.source] or 0) + 1
            if entry.category == "recipes" and entry.professionKey then
                professionCounts[entry.professionKey] = (professionCounts[entry.professionKey] or 0) + 1
            end
            if (uiState.source == "all" or entry.source == uiState.source)
                and matchesStatus(info.statusKey, uiState.status)
            then
                visible[#visible + 1] = record
            end
        end
    end

    local sourceOptions = { { key = "all", label = L.COMPENDIUM_FILTER_SOURCE_ALL, count = #base } }
    for source, count in pairs(sourceCounts) do
        sourceOptions[#sourceOptions + 1] = { key = source, label = self:GetSourceLabel(source), count = count }
    end
    table.sort(sourceOptions, function(a, b)
        if a.key == "all" then return true end
        if b.key == "all" then return false end
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.label) < tostring(b.label)
    end)
    local validSource = false
    for _, option in ipairs(sourceOptions) do if option.key == uiState.source then validSource = true; break end end
    if not validSource then
        uiState.source = "all"
        visible = {}
        for _, record in ipairs(base) do
            if matchesStatus(record.runtime.statusKey, uiState.status) then visible[#visible + 1] = record end
        end
    end

    local professionOptions = { { key = "all", label = L.COMPENDIUM_FILTER_PROFESSION_ALL, count = 0 } }
    for _, profession in ipairs(prepared.catalog.professionOrder or {}) do
        if not runtimeState.professionApiAvailable or runtimeState.activeProfessions[profession.key] then
            local count = professionCounts[profession.key] or 0
            professionOptions[#professionOptions + 1] = {
                key = profession.key,
                label = self:GetProfessionLabel(profession.key, profession.label),
                count = count,
            }
            professionOptions[1].count = professionOptions[1].count + count
        end
    end

    table.sort(visible, function(a, b)
        local ae, be, ar, br = a.entry, b.entry, a.runtime, b.runtime
        local ac, bc = prepared.categoryRank[ae.category] or 99, prepared.categoryRank[be.category] or 99
        if ac ~= bc then return ac < bc end
        local ap, bp = prepared.professionRank[ae.professionKey] or 99, prepared.professionRank[be.professionKey] or 99
        if ap ~= bp then return ap < bp end
        local as = ae.category == "recipes" and RECIPE_SOURCE_RANK[ae.source] or prepared.sourceRank[ae.source]
        local bs = be.category == "recipes" and RECIPE_SOURCE_RANK[be.source] or prepared.sourceRank[be.source]
        as, bs = as or 99, bs or 99
        if as ~= bs then return as < bs end
        local ast, bst = statusRank(ar.statusKey), statusRank(br.statusKey)
        if ast ~= bst then return ast < bst end
        return tostring(ar.name or ae.name) < tostring(br.name or be.name)
    end)

    local grouped, counts, labels = {}, {}, {}
    local function groupKey(record)
        local entry, parts = record.entry, {}
        if uiState.category == "all" then parts[#parts + 1] = entry.category end
        if entry.category == "recipes" and uiState.profession == "all" then parts[#parts + 1] = entry.professionKey or "unknown" end
        if uiState.source == "all" then parts[#parts + 1] = entry.source or "unknown" end
        return #parts > 0 and table.concat(parts, "\31") or "all"
    end
    local function groupLabel(record)
        local entry, parts = record.entry, {}
        if uiState.category == "all" then parts[#parts + 1] = self:GetCategoryLabel(entry.category) end
        if entry.category == "recipes" and uiState.profession == "all" then
            parts[#parts + 1] = self:GetProfessionLabel(entry.professionKey, entry.profession)
        end
        if uiState.source == "all" then parts[#parts + 1] = self:GetSourceLabel(entry.source) end
        if #parts == 0 then parts[1] = self:GetSourceLabel(entry.source) end
        return table.concat(parts, " / ")
    end
    for _, record in ipairs(visible) do
        local key = groupKey(record)
        counts[key] = (counts[key] or 0) + 1
        labels[key] = labels[key] or groupLabel(record)
    end
    local previous
    for _, record in ipairs(visible) do
        local key = groupKey(record)
        if key ~= previous then
            grouped[#grouped + 1] = { kind = "group", key = key, label = labels[key], count = counts[key] }
            previous = key
        end
        grouped[#grouped + 1] = record
    end

    return {
        state = uiState,
        entries = grouped,
        categoryStats = runtimeState.categoryStats,
        sourceOptions = sourceOptions,
        professionOptions = professionOptions,
        waypointCount = runtimeState.waypointCount,
        visibleCount = #visible,
        totalRuntimeCount = #runtimeState.records,
    }
end

function Logic:GetWaypoint(entry)
    if type(entry) ~= "table" then return nil end
    local waypoint = entry.waypoint
    if entry.overworldWaypoint then
        waypoint = entry.overworldWaypoint
        if entry.waypoint and C_Map and type(C_Map.GetBestMapForUnit) == "function" then
            local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
            if ok and tonumber(mapID) == tonumber(entry.waypoint[1]) then waypoint = entry.waypoint end
        end
    end
    if type(waypoint) == "table" and tonumber(waypoint[1]) and tonumber(waypoint[2]) and tonumber(waypoint[3]) then
        return waypoint
    end
end

function Logic:SetWaypoint(entry)
    local waypoint = self:GetWaypoint(entry)
    if not waypoint or not C_Map or type(C_Map.SetUserWaypoint) ~= "function"
        or not UiMapPoint or type(UiMapPoint.CreateFromCoordinates) ~= "function"
    then
        return false, L.COMPENDIUM_WAYPOINT_UNAVAILABLE
    end
    local okPoint, point = pcall(
        UiMapPoint.CreateFromCoordinates,
        tonumber(waypoint[1]),
        tonumber(waypoint[2]),
        tonumber(waypoint[3])
    )
    if not okPoint or not point then return false, L.COMPENDIUM_WAYPOINT_UNAVAILABLE end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok == true
end

function Logic:OpenAchievement(entry)
    local achievementID = tonumber(entry and entry.achievementID)
    if not achievementID then return false end
    if type(OpenAchievementFrame) == "function" and pcall(OpenAchievementFrame, achievementID) then return true end
    if type(AchievementFrame_LoadUI) == "function" then pcall(AchievementFrame_LoadUI) end
    if type(ToggleAchievementFrame) == "function" and (not AchievementFrame or not AchievementFrame:IsShown()) then
        pcall(ToggleAchievementFrame)
    end
    return type(AchievementFrame_SelectAchievement) == "function"
        and pcall(AchievementFrame_SelectAchievement, achievementID)
end

local function mapName(mapID)
    if not tonumber(mapID) or not C_Map or type(C_Map.GetMapInfo) ~= "function" then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, tonumber(mapID))
    return ok and type(info) == "table" and info.name or nil
end

local function formatCurrency(info)
    if type(info) ~= "table" then return nil end
    local currencyID, amount = tonumber(info[1]), tonumber(info[2]) or 0
    local name, icon = tostring(currencyID or ""), nil
    if currencyID and C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
        local ok, currency = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and type(currency) == "table" then
            name, icon = currency.name or name, currency.iconFileID or currency.icon
        end
    end
    return icon and string.format("%s |T%s:14:14:0:0|t %s", amount, icon, name)
        or string.format("%s %s", amount, name)
end

function Logic:FormatCost(cost)
    if type(cost) ~= "table" then return nil end
    local parts = {}
    local text = localized(cost.text, cost.textKey)
    if text then parts[#parts + 1] = text end
    for _, key in ipairs({ "currency", "currency2", "currency3" }) do
        local value = formatCurrency(cost[key])
        if value then parts[#parts + 1] = value end
    end
    for _, key in ipairs({ "item", "item2", "item3" }) do
        local info = cost[key]
        local itemID = type(info) == "table" and tonumber(info.itemID or info[1]) or nil
        if itemID then
            local amount = tonumber(info.amount or info[2]) or 1
            local name, icon = getItemNameAndIcon(itemID)
            parts[#parts + 1] = icon and string.format("%s |T%s:14:14:0:0|t %s", amount, icon, name or itemID)
                or string.format("%s %s", amount, name or itemID)
        end
    end
    if tonumber(cost.gold) then parts[#parts + 1] = string.format(L.COMPENDIUM_COST_GOLD_FORMAT, cost.gold) end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function Logic:GetDetailLines(entry, runtime)
    local waypoint = self:GetWaypoint(entry)
    local zone = waypoint and mapName(waypoint[1]) or mapName(ZONE_MAP_IDS[entry.zone]) or entry.zone
    local source = runtime.sourceLabel or self:GetSourceLabel(entry.source)
    local detail = localized(entry.sourceDetail, entry.sourceDetailKey) or localized(entry.quest, entry.questKey)
    local vendor = localized(entry.vendor, entry.vendorKey)
    local cost = self:FormatCost(entry.cost)
    local lines = {
        { label = L.COMPENDIUM_TOOLTIP_CATEGORY, value = runtime.categoryLabel },
        { label = L.COMPENDIUM_TOOLTIP_STATUS, value = runtime.statusLabel },
        { label = L.COMPENDIUM_TOOLTIP_SOURCE, value = detail and (source .. " - " .. detail) or source },
    }
    if runtime.professionLabel then lines[#lines + 1] = { label = L.COMPENDIUM_TOOLTIP_PROFESSION, value = runtime.professionLabel } end
    if zone then lines[#lines + 1] = { label = L.COMPENDIUM_TOOLTIP_ZONE, value = zone } end
    if vendor then lines[#lines + 1] = { label = L.COMPENDIUM_TOOLTIP_VENDOR, value = vendor } end
    if cost then lines[#lines + 1] = { label = L.COMPENDIUM_TOOLTIP_COST, value = cost } end
    if waypoint then
        lines[#lines + 1] = {
            label = L.COMPENDIUM_TOOLTIP_WAYPOINT,
            value = string.format("%.1f, %.1f", waypoint[2] * 100, waypoint[3] * 100),
        }
    end
    return lines
end
