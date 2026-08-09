local _, Addon = ...

local Logic = {
    version = 1,
}

Addon.OneClickProcessingLogic = Logic

Logic.recipeDefinitions = {
    { kind = "mill", recipeID = 1269575, requiredCount = 10 },
    { kind = "mill", recipeID = 444181, requiredCount = 10 },
    { kind = "prospect", recipeID = 1231127, requiredCount = 5 },
    { kind = "prospect", recipeID = 434018, requiredCount = 5 },
}

Logic.fallbackSalvageItems = {
    [444181] = {
        210796, 210797, 210798, 210799, 210800, 210801, 210802, 210803,
        210804, 210805, 210806, 210807, 220141, 240216, 249218,
    },
    [1269575] = {
        236761, 236767, 236770, 236771, 236776, 236777, 236778, 236779,
    },
    [434018] = {
        210930, 210931, 210932, 210933, 210934, 210935, 210936, 210937,
        210938, 210939, 213398, 240216, 249218,
    },
    [1231127] = {
        237359, 237361, 237362, 237363, 237364, 237365, 237366,
    },
}

Logic.lockboxes = {
    [4632] = 15, [4633] = 15, [4634] = 15, [4636] = 15, [4637] = 15,
    [4638] = 15, [5758] = 15, [5759] = 15, [5760] = 15, [6354] = 15,
    [6355] = 15, [7209] = 1, [12033] = 15, [13875] = 15, [13918] = 15,
    [16882] = 15, [16883] = 15, [16884] = 15, [16885] = 15, [29569] = 30,
    [31952] = 30, [43575] = 30, [43622] = 30, [43624] = 30, [45986] = 30,
    [63349] = 30, [68729] = 30, [88165] = 35, [88567] = 35, [106895] = 40,
    [116920] = 40, [121331] = 45, [169475] = 50, [179311] = 60,
    [180522] = 60, [180532] = 60, [180533] = 60, [186160] = 60,
    [186161] = 60, [188787] = 60, [190954] = 65, [198657] = 65,
    [203743] = 15, [204307] = 15, [220376] = 75, [264475] = 85,
}

local function copyAction(action)
    local result = {}
    for key, value in pairs(action or {}) do
        result[key] = value
    end
    return result
end

local function addItemIDs(target, values, action)
    local added = 0
    if type(values) ~= "table" then
        return added
    end

    for key, value in pairs(values) do
        local itemID = tonumber(value)
        if value == true then
            itemID = tonumber(key)
        end
        if itemID and itemID > 0 then
            target[itemID] = action == true and true or copyAction(action)
            added = added + 1
        end
    end
    return added
end

function Logic:ModifierMatches(modifier, altDown, shiftDown, controlDown)
    altDown = altDown == true
    shiftDown = shiftDown == true
    controlDown = controlDown == true

    if modifier == "alt_shift" then
        return altDown and shiftDown and not controlDown
    end
    if modifier == "alt_ctrl" then
        return altDown and controlDown and not shiftDown
    end
    return altDown and not shiftDown and not controlDown
end

function Logic:BuildSalvageIndex(getSalvagableItemIDs, isRecipeKnown)
    local index = {}
    local dynamicRecipeCount = 0
    local fallbackRecipeCount = 0

    for _, definition in ipairs(self.recipeDefinitions) do
        local values
        if type(getSalvagableItemIDs) == "function" then
            values = getSalvagableItemIDs(definition.recipeID)
        end

        local action = {
            kind = definition.kind,
            execution = "salvage",
            recipeID = definition.recipeID,
            requiredCount = definition.requiredCount,
        }
        if addItemIDs(index, values, action) > 0 then
            dynamicRecipeCount = dynamicRecipeCount + 1
        elseif type(isRecipeKnown) ~= "function" or isRecipeKnown(definition.recipeID) == true then
            addItemIDs(index, self.fallbackSalvageItems[definition.recipeID], action)
            fallbackRecipeCount = fallbackRecipeCount + 1
        end
    end

    return index, {
        dynamicRecipeCount = dynamicRecipeCount,
        fallbackRecipeCount = fallbackRecipeCount,
    }
end

function Logic:BuildDisenchantSet(getSalvagableItemIDs, isSpellKnown)
    if type(isSpellKnown) == "function" and isSpellKnown(13262) ~= true then
        return {}, false
    end
    if type(getSalvagableItemIDs) ~= "function" then
        return {}, false
    end

    local values = getSalvagableItemIDs(13262)
    local result = {}
    return result, addItemIDs(result, values, true) > 0
end

function Logic:IsSafeContext(context)
    local bagID = tonumber(context and context.bagID)
    return type(context) == "table"
        and tonumber(context.itemID) ~= nil
        and bagID ~= nil
        and bagID >= 0
        and bagID <= 5
        and context.isLocked ~= true
        and context.isRefundable ~= true
        and context.isCosmetic ~= true
        and context.inEquipmentSet ~= true
end

function Logic:ResolveLockboxSpell(itemID, playerLevel, isSpellKnown)
    local requiredLevel = self.lockboxes[tonumber(itemID)]
    if not requiredLevel or (tonumber(playerLevel) or 0) < requiredLevel then
        return nil
    end

    for _, spellID in ipairs({ 1804, 312890, 323427 }) do
        if type(isSpellKnown) == "function" and isSpellKnown(spellID) == true then
            return spellID
        end
    end
    return nil
end

function Logic:IsDisenchantCandidate(context, allowRareEpic, allowedItems, authoritative)
    local quality = tonumber(context and context.quality)
    if quality ~= 2 and not (allowRareEpic == true and (quality == 3 or quality == 4)) then
        return false
    end
    if authoritative == true and not (type(allowedItems) == "table" and allowedItems[context.itemID]) then
        return false
    end

    local itemClass = Enum and Enum.ItemClass or {}
    local weaponClassID = tonumber(itemClass.Weapon) or 2
    local armorClassID = tonumber(itemClass.Armor) or 4
    local professionClassID = tonumber(itemClass.Profession) or 19
    local gemClassID = tonumber(itemClass.Gem) or 3
    local artifactRelicSubclassID = tonumber(Enum and Enum.ItemGemSubclass and Enum.ItemGemSubclass.Artifactrelic) or 11
    local classID = tonumber(context.classID)
    local subClassID = tonumber(context.subClassID)

    if context.equipLocation == "INVTYPE_BODY" then
        return false
    end
    return classID == weaponClassID
        or classID == armorClassID
        or classID == professionClassID
        or (classID == gemClassID and subClassID == artifactRelicSubclassID)
end

function Logic:ResolveAction(context, options)
    options = type(options) == "table" and options or {}
    if not self:IsSafeContext(context) then
        return nil
    end

    local salvage = type(options.salvageIndex) == "table"
        and options.salvageIndex[context.itemID]
        or nil
    if salvage and (tonumber(context.stackCount) or 0) >= (tonumber(salvage.requiredCount) or 1) then
        return copyAction(salvage)
    end

    local lockSpellID = self:ResolveLockboxSpell(
        context.itemID,
        options.playerLevel,
        options.isSpellKnown
    )
    if lockSpellID then
        return {
            kind = "open",
            execution = "spell",
            spellID = lockSpellID,
            requiredCount = 1,
        }
    end

    if type(options.isSpellKnown) == "function"
        and options.isSpellKnown(13262) == true
        and self:IsDisenchantCandidate(
            context,
            options.allowRareEpic,
            options.disenchantItems,
            options.disenchantAuthoritative
        )
    then
        return {
            kind = "disenchant",
            execution = "spell",
            spellID = 13262,
            requiredCount = 1,
        }
    end
    return nil
end
