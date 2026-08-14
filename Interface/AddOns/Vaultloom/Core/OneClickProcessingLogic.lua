local _, Addon = ...

local Logic = {
    version = 1,
}

Addon.OneClickProcessingLogic = Logic

local ProcessingData = Addon.VaultloomProcessingData or {}
Logic.eligibleItems = ProcessingData.eligibleItems or {}

Logic.recipeDefinitions = {}
for _, group in ipairs(ProcessingData.actions or {}) do
    for _, recipeID in ipairs(group.recipeIDs or {}) do
        Logic.recipeDefinitions[#Logic.recipeDefinitions + 1] = {
            kind = group.kind,
            recipeID = recipeID,
            requiredCount = group.overrides and group.overrides[recipeID]
                or group.requiredCount,
        }
    end
end

Logic.lockboxes = {}
for _, tier in ipairs(ProcessingData.lockboxTiers or {}) do
    for _, itemID in ipairs(tier.itemIDs or {}) do
        Logic.lockboxes[itemID] = tier.requiredLevel
    end
end

Logic.lockSpells = ProcessingData.lockSpells or {}
Logic.professionKeys = {}
for _, tier in ipairs(ProcessingData.openerTiers or {}) do
    for _, itemID in ipairs(tier.itemIDs or {}) do
        Logic.professionKeys[#Logic.professionKeys + 1] = {
            itemID = itemID,
            maximumLockLevel = tier.maximumLockLevel,
            minimumPlayerLevel = tier.minimumPlayerLevel,
        }
    end
end

local function copyAction(action)
    local result = {}
    for key, value in pairs(action or {}) do
        result[key] = value
    end
    return result
end

local function addItemIDs(target, values, action)
    local added = 0
    local seen = 0
    if type(values) ~= "table" then
        return added, seen
    end

    for key, value in pairs(values) do
        local itemID = tonumber(value)
        if value == true then
            itemID = tonumber(key)
        end
        if itemID and itemID > 0 then
            seen = seen + 1
            if target[itemID] == nil then
                target[itemID] = action == true and true or copyAction(action)
                added = added + 1
            end
        end
    end
    return added, seen
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
    local catalogRecipeCount = 0
    local emptyRecipeCount = 0
    local unknownRecipeCount = 0

    for _, definition in ipairs(self.recipeDefinitions) do
        local recipeKnown = type(isRecipeKnown) ~= "function"
            or isRecipeKnown(definition.recipeID) == true
        if recipeKnown then
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
            local _, dynamicItemCount = addItemIDs(index, values, action)
            if dynamicItemCount > 0 then
                dynamicRecipeCount = dynamicRecipeCount + 1
            end

            local catalog = self.eligibleItems[definition.kind]
            local catalogItems = type(catalog) == "table"
                and catalog[definition.recipeID]
                or nil
            local _, catalogItemCount = addItemIDs(index, catalogItems, action)
            if catalogItemCount > 0 then
                catalogRecipeCount = catalogRecipeCount + 1
            elseif dynamicItemCount == 0 then
                emptyRecipeCount = emptyRecipeCount + 1
            end
        else
            unknownRecipeCount = unknownRecipeCount + 1
        end
    end

    return index, {
        dynamicRecipeCount = dynamicRecipeCount,
        catalogRecipeCount = catalogRecipeCount,
        emptyRecipeCount = emptyRecipeCount,
        unknownRecipeCount = unknownRecipeCount,
    }
end

function Logic:BuildCatalogCandidateIndex()
    local index = {}
    for _, definition in ipairs(self.recipeDefinitions) do
        local catalog = self.eligibleItems[definition.kind]
        local values = type(catalog) == "table" and catalog[definition.recipeID] or nil
        local action = {
            kind = definition.kind,
            execution = "salvage",
            recipeID = definition.recipeID,
            requiredCount = definition.requiredCount,
        }
        for _, itemID in ipairs(values or {}) do
            itemID = tonumber(itemID)
            if itemID and itemID > 0 then
                index[itemID] = index[itemID] or {}
                index[itemID][#index[itemID] + 1] = copyAction(action)
            end
        end
    end
    return index
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

function Logic:GetSafetyReason(context)
    local bagID = tonumber(context and context.bagID)
    if type(context) ~= "table"
        or tonumber(context.itemID) == nil
        or bagID == nil
        or bagID < 0
        or bagID > 5
    then
        return "invalid"
    end
    if context.isLocked == true then
        return "locked"
    end
    if context.isRefundable == true then
        return "refundable"
    end
    if context.isCosmetic == true then
        return "cosmetic"
    end
    if context.inEquipmentSet == true then
        return "equipment_set"
    end
    return nil
end

function Logic:IsSafeContext(context)
    return self:GetSafetyReason(context) == nil
end

function Logic:ResolveLockboxSpell(itemID, playerLevel, isSpellKnown)
    local requiredLevel = self.lockboxes[tonumber(itemID)]
    if not requiredLevel or (tonumber(playerLevel) or 0) < requiredLevel then
        return nil
    end

    for _, definition in ipairs(self.lockSpells) do
        if (not definition.maximumLockLevel or requiredLevel <= definition.maximumLockLevel)
            and type(isSpellKnown) == "function"
            and isSpellKnown(definition.spellID) == true
        then
            return definition.spellID
        end
    end
    return nil
end

function Logic:ResolveLockboxKey(itemID, playerLevel, getItemCount, isKeyUsable)
    local requiredLevel = self.lockboxes[tonumber(itemID)]
    playerLevel = tonumber(playerLevel) or 0
    if not requiredLevel or playerLevel < requiredLevel or type(getItemCount) ~= "function" then
        return nil
    end

    local bestItemID
    local bestMaximum
    for _, definition in ipairs(self.professionKeys) do
        local keyItemID = tonumber(definition.itemID)
        local maximum = tonumber(definition.maximumLockLevel) or 0
        local minimumPlayerLevel = tonumber(definition.minimumPlayerLevel) or 0
        if keyItemID
            and maximum >= requiredLevel
            and minimumPlayerLevel <= playerLevel
            and (tonumber(getItemCount(keyItemID)) or 0) > 0
            and (type(isKeyUsable) ~= "function" or isKeyUsable(keyItemID) == true)
            and (not bestMaximum
                or maximum < bestMaximum
                or (maximum == bestMaximum and keyItemID < bestItemID))
        then
            bestItemID = keyItemID
            bestMaximum = maximum
        end
    end
    return bestItemID
end

function Logic:IsDisenchantCandidate(context, allowRareEpic, allowedItems, authoritative)
    local quality = tonumber(context and context.quality)
    if quality ~= 2 and not (allowRareEpic == true and (quality == 3 or quality == 4)) then
        return false
    end
    if authoritative == true then
        return type(allowedItems) == "table" and allowedItems[context.itemID] == true
    end

    -- Blizzard's salvage list is not always populated outside the profession UI.
    -- The local fallback deliberately admits only equippable weapons and armor;
    -- all destructive safety checks still run before an action can be armed.
    local classID = tonumber(context and context.classID)
    if classID ~= 2 and classID ~= 4 then
        return false
    end
    local equipLocation = tostring(context and context.equipLocation or "")
    if equipLocation == ""
        or equipLocation == "INVTYPE_BODY"
        or equipLocation == "INVTYPE_TABARD"
        or equipLocation == "INVTYPE_BAG"
    then
        return false
    end
    return context.isCosmetic ~= true
end

function Logic:DiagnoseFailure(context, options)
    options = type(options) == "table" and options or {}
    local bagID = tonumber(context and context.bagID)
    if type(context) ~= "table"
        or tonumber(context.itemID) == nil
        or bagID == nil
        or bagID < 0
        or bagID > 5
    then
        return nil
    end

    local candidates = {}
    local activeCandidate = type(options.salvageIndex) == "table"
        and options.salvageIndex[context.itemID]
        or nil
    if type(activeCandidate) == "table" then
        candidates[#candidates + 1] = activeCandidate
    end
    local catalogCandidates = type(options.candidateIndex) == "table"
        and options.candidateIndex[context.itemID]
        or nil
    for _, candidate in ipairs(catalogCandidates or {}) do
        if not activeCandidate or activeCandidate.recipeID ~= candidate.recipeID then
            candidates[#candidates + 1] = candidate
        end
    end
    local firstUnknown
    for _, candidate in ipairs(candidates) do
        if type(options.isRecipeKnown) ~= "function"
            or options.isRecipeKnown(candidate.recipeID) == true
        then
            local safetyReason = self:GetSafetyReason(context)
            if safetyReason then
                return {
                    reason = "protected",
                    safetyReason = safetyReason,
                    action = copyAction(candidate),
                }
            end
            if (tonumber(context.stackCount) or 0) < (tonumber(candidate.requiredCount) or 1) then
                return {
                    reason = "need_more",
                    action = copyAction(candidate),
                    requiredCount = tonumber(candidate.requiredCount) or 1,
                }
            end
            return nil
        elseif not firstUnknown then
            firstUnknown = candidate
        end
    end

    local allowedDisenchant = type(options.isSpellKnown) == "function"
        and options.isSpellKnown(13262) == true
        and self:IsDisenchantCandidate(
            context,
            true,
            options.disenchantItems,
            options.disenchantAuthoritative
        )
    if allowedDisenchant then
        local safetyReason = self:GetSafetyReason(context)
        if safetyReason then
            return {
                reason = "protected",
                safetyReason = safetyReason,
                action = { kind = "disenchant", execution = "spell", spellID = 13262 },
            }
        end
        local quality = tonumber(context.quality)
        if (quality == 3 or quality == 4) and options.allowRareEpic ~= true then
            return {
                reason = "rare_epic_disabled",
                action = { kind = "disenchant", execution = "spell", spellID = 13262 },
            }
        end
    end

    if firstUnknown then
        return {
            reason = "recipe_unknown",
            action = copyAction(firstUnknown),
        }
    end

    local lockSpellID = self:ResolveLockboxSpell(
        context.itemID,
        options.playerLevel,
        options.isSpellKnown
    )
    if not lockSpellID then
        local keyItemID = self:ResolveLockboxKey(
            context.itemID,
            options.playerLevel,
            options.getItemCount,
            options.isKeyUsable
        )
        if keyItemID then
            local keyAction = {
                kind = "open",
                execution = "item",
                itemID = keyItemID,
                requiredCount = 1,
            }
            local safetyReason = self:GetSafetyReason(context)
            if safetyReason then
                return {
                    reason = "protected",
                    safetyReason = safetyReason,
                    action = keyAction,
                }
            end
            if options.allowConsumableKeys ~= true then
                return {
                    reason = "keys_disabled",
                    action = keyAction,
                }
            end
        end
    end
    return nil
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


    if options.allowConsumableKeys == true then
        local keyItemID = self:ResolveLockboxKey(
            context.itemID,
            options.playerLevel,
            options.getItemCount,
            options.isKeyUsable
        )
        if keyItemID then
            return {
                kind = "open",
                execution = "item",
                itemID = keyItemID,
                requiredCount = 1,
            }
        end
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
