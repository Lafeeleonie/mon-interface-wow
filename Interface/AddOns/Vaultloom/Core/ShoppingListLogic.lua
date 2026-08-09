local _, Addon = ...

local Logic = {}
Addon.ShoppingListLogic = Logic

function Logic:ClampQuantity(value)
    value = math.floor((tonumber(value) or 1) + 0.5)
    return math.max(1, math.min(9999, value))
end

local function normalizeItemID(value)
    value = tonumber(value)
    if not value or value <= 0 then
        return nil
    end
    return math.floor(value)
end

local function getReagentItemIDs(reagent)
    local result, seen = {}, {}
    local selectedItemID = normalizeItemID(reagent and reagent.selectedItemID)
    if selectedItemID then
        return { selectedItemID }
    end

    for _, value in ipairs(type(reagent and reagent.itemIDs) == "table" and reagent.itemIDs or {}) do
        local itemID = normalizeItemID(value)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            result[#result + 1] = itemID
        end
    end
    local primaryItemID = normalizeItemID(reagent and reagent.itemID)
    if primaryItemID and not seen[primaryItemID] then
        result[#result + 1] = primaryItemID
    end
    table.sort(result)
    return result
end

function Logic:GetMaterialKey(reagent)
    local itemIDs = getReagentItemIDs(reagent)
    if #itemIDs == 0 then
        return nil
    end
    if #itemIDs == 1 then
        return "item:" .. tostring(itemIDs[1])
    end
    local parts = {}
    for _, itemID in ipairs(itemIDs) do
        parts[#parts + 1] = tostring(itemID)
    end
    return "group:" .. table.concat(parts, ",")
end

local function makeCountResolver(countProvider)
    local cache = {}
    return function(itemID)
        itemID = normalizeItemID(itemID)
        if not itemID then
            return 0
        end
        if cache[itemID] == nil then
            local count = 0
            if type(countProvider) == "function" then
                local ok, resolved = pcall(countProvider, itemID)
                if ok then
                    count = resolved
                end
            end
            cache[itemID] = math.max(0, math.floor(tonumber(count) or 0))
        end
        return cache[itemID]
    end
end

local function resolveOwned(reagent, resolveCount)
    local total = 0
    for _, itemID in ipairs(getReagentItemIDs(reagent)) do
        total = total + resolveCount(itemID)
    end
    return total
end

local function addMaterial(materials, order, reagent, required)
    local key = Logic:GetMaterialKey(reagent)
    required = math.max(0, math.floor(tonumber(required) or 0))
    if not key or required == 0 then
        return
    end

    local material = materials[key]
    if not material then
        local itemIDs = getReagentItemIDs(reagent)
        material = {
            key = key,
            itemID = normalizeItemID(reagent.selectedItemID) or normalizeItemID(reagent.itemID),
            itemIDs = itemIDs,
            itemLink = reagent.itemLink,
            name = reagent.name,
            icon = reagent.icon,
            quality = reagent.quality,
            grouped = #itemIDs > 1,
            required = 0,
        }
        materials[key] = material
        order[#order + 1] = key
    end
    material.required = material.required + required
end

function Logic:BuildPlan(entries, countProvider)
    entries = type(entries) == "table" and entries or {}
    local resolveCount = makeCountResolver(countProvider)
    local projects = {}
    local materials, materialOrder = {}, {}

    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local quantity = self:ClampQuantity(entry.quantity)
            local project = {
                id = entry.id,
                kind = entry.kind == "recipe" and "recipe" or "item",
                entry = entry,
                quantity = quantity,
                outputQuantity = math.max(1, math.floor(tonumber(entry.outputQuantity) or 1)),
                reagents = {},
                missing = 0,
                complete = false,
            }

            if project.kind == "recipe" then
                for _, reagent in ipairs(type(entry.reagents) == "table" and entry.reagents or {}) do
                    local requiredPerCraft = math.max(0, tonumber(reagent.quantity) or 0)
                    local required = math.floor((requiredPerCraft * quantity) + 0.5)
                    if required > 0 then
                        local owned = resolveOwned(reagent, resolveCount)
                        local missing = math.max(0, required - owned)
                        project.reagents[#project.reagents + 1] = {
                            reagent = reagent,
                            required = required,
                            owned = owned,
                            missing = missing,
                            complete = missing == 0,
                        }
                        project.missing = project.missing + missing
                        addMaterial(materials, materialOrder, reagent, required)
                    end
                end
                project.complete = #project.reagents > 0 and project.missing == 0
            else
                local reagent = {
                    itemID = entry.itemID,
                    selectedItemID = entry.itemID,
                    itemLink = entry.itemLink,
                    name = entry.name,
                    icon = entry.icon,
                    quality = entry.quality,
                }
                project.owned = resolveOwned(reagent, resolveCount)
                project.missing = math.max(0, quantity - project.owned)
                project.complete = project.missing == 0
                addMaterial(materials, materialOrder, reagent, quantity)
            end
            projects[#projects + 1] = project
        end
    end

    local purchases = {}
    local missingUnits, missingTypes, completeTypes = 0, 0, 0
    for _, key in ipairs(materialOrder) do
        local material = materials[key]
        material.owned = resolveOwned(material, resolveCount)
        material.missing = math.max(0, material.required - material.owned)
        material.complete = material.missing == 0
        if material.complete then
            completeTypes = completeTypes + 1
        else
            missingTypes = missingTypes + 1
            missingUnits = missingUnits + material.missing
        end
        purchases[#purchases + 1] = material
    end

    table.sort(purchases, function(left, right)
        if left.complete ~= right.complete then
            return not left.complete
        end
        if left.missing ~= right.missing then
            return left.missing > right.missing
        end
        return string.lower(tostring(left.name or left.key)) < string.lower(tostring(right.name or right.key))
    end)

    return {
        projects = projects,
        purchases = purchases,
        summary = {
            projects = #projects,
            materials = #purchases,
            missingTypes = missingTypes,
            missingUnits = missingUnits,
            completeTypes = completeTypes,
        },
    }
end

function Logic:FilterPurchases(purchases, filterKey)
    local result = {}
    filterKey = filterKey == "complete" and "complete"
        or filterKey == "all" and "all"
        or "missing"
    for _, material in ipairs(type(purchases) == "table" and purchases or {}) do
        if filterKey == "all"
            or (filterKey == "missing" and material.missing > 0)
            or (filterKey == "complete" and material.complete)
        then
            result[#result + 1] = material
        end
    end
    return result
end
