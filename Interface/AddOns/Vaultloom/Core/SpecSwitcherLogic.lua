local _, Addon = ...

local Logic = {}
Addon.SpecSwitcherLogic = Logic

local ICON_SIZES = {
    small = 32,
    normal = 38,
    large = 44,
}

local function positiveInteger(value)
    value = math.floor(tonumber(value) or 0)
    return value > 0 and value or nil
end

function Logic:GetIconSize(sizeKey)
    return ICON_SIZES[sizeKey] or ICON_SIZES.normal
end

function Logic:NormalizeLoadouts(loadouts)
    local result, seen = {}, {}
    for _, loadout in ipairs(type(loadouts) == "table" and loadouts or {}) do
        local configID = positiveInteger(type(loadout) == "table" and loadout.id or loadout)
        if configID and not seen[configID] then
            seen[configID] = true
            result[#result + 1] = {
                id = configID,
                name = type(loadout) == "table"
                    and tostring(loadout.name or ("Loadout " .. tostring(configID)))
                    or ("Loadout " .. tostring(configID)),
            }
        end
    end
    return result
end

local function containsConfig(loadouts, configID)
    configID = positiveInteger(configID)
    if not configID then return false end
    for _, loadout in ipairs(loadouts) do
        if loadout.id == configID then return true end
    end
    return false
end

function Logic:ResolveActiveLoadoutID(specID, currentSpecID, activeConfigID, lastSelectedID, loadouts)
    loadouts = self:NormalizeLoadouts(loadouts)
    if positiveInteger(specID) == positiveInteger(currentSpecID)
        and containsConfig(loadouts, activeConfigID)
    then
        return positiveInteger(activeConfigID)
    end
    if containsConfig(loadouts, lastSelectedID) then
        return positiveInteger(lastSelectedID)
    end
    return nil
end

function Logic:GetLoadoutName(loadouts, configID)
    configID = positiveInteger(configID)
    for _, loadout in ipairs(type(loadouts) == "table" and loadouts or {}) do
        if positiveInteger(loadout.id) == configID then
            return loadout.name
        end
    end
    return nil
end

function Logic:GetNextLoadout(loadouts, currentConfigID)
    loadouts = self:NormalizeLoadouts(loadouts)
    if #loadouts == 0 then return nil end
    currentConfigID = positiveInteger(currentConfigID)
    for index, loadout in ipairs(loadouts) do
        if loadout.id == currentConfigID then
            return loadouts[(index % #loadouts) + 1]
        end
    end
    return loadouts[1]
end

function Logic:BuildModel(specs, currentSpecIndex, activeConfigID)
    local model = {
        specs = {},
        currentSpecIndex = positiveInteger(currentSpecIndex),
        currentSpecID = nil,
        activeConfigID = positiveInteger(activeConfigID),
    }
    for _, spec in ipairs(type(specs) == "table" and specs or {}) do
        if type(spec) == "table" and positiveInteger(spec.id) and positiveInteger(spec.index) then
            local copy = {
                index = positiveInteger(spec.index),
                id = positiveInteger(spec.id),
                name = tostring(spec.name or ("Spec " .. tostring(spec.index))),
                description = spec.description,
                icon = spec.icon,
                role = spec.role,
                loadouts = self:NormalizeLoadouts(spec.loadouts),
                lastSelectedID = positiveInteger(spec.lastSelectedID),
            }
            copy.isActive = copy.index == model.currentSpecIndex
            if copy.isActive then model.currentSpecID = copy.id end
            model.specs[#model.specs + 1] = copy
        end
    end
    for _, spec in ipairs(model.specs) do
        spec.activeLoadoutID = self:ResolveActiveLoadoutID(
            spec.id,
            model.currentSpecID,
            model.activeConfigID,
            spec.lastSelectedID,
            spec.loadouts
        )
        spec.activeLoadoutName = self:GetLoadoutName(spec.loadouts, spec.activeLoadoutID)
    end
    return model
end

function Logic:GetLayout(specCount, orientation, frameStyle, sizeKey, showActiveLabel)
    specCount = math.max(1, positiveInteger(specCount) or 1)
    orientation = orientation == "vertical" and "vertical" or "horizontal"
    frameStyle = frameStyle == "clean" and "clean"
        or frameStyle == "compact" and "compact"
        or "warcraft"
    local iconSize = self:GetIconSize(sizeKey)
    local gap = 6
    local padding = frameStyle == "warcraft" and 8
        or frameStyle == "compact" and 5
        or 0
    local buttonWidth = orientation == "horizontal"
        and ((specCount * iconSize) + ((specCount - 1) * gap))
        or iconSize
    local buttonHeight = orientation == "vertical"
        and ((specCount * iconSize) + ((specCount - 1) * gap))
        or iconSize
    local labelWidth = showActiveLabel and orientation == "vertical" and 150 or 0
    local labelHeight = showActiveLabel and orientation == "horizontal" and 20 or 0
    return {
        orientation = orientation,
        frameStyle = frameStyle,
        iconSize = iconSize,
        gap = gap,
        padding = padding,
        buttonWidth = buttonWidth,
        buttonHeight = buttonHeight,
        labelWidth = labelWidth,
        labelHeight = labelHeight,
        width = buttonWidth + (padding * 2) + labelWidth,
        height = buttonHeight + (padding * 2) + labelHeight,
    }
end

