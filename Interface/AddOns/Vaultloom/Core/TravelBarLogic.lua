local _, Addon = ...

local Logic = {}
Addon.TravelBarLogic = Logic

local DIRECT_ORDER = {
    dalaran = 10,
    garrison = 20,
    housing = 30,
    class_travel = 40,
}

local function validAction(action)
    return type(action) == "table"
        and type(action.key) == "string"
        and action.key ~= ""
        and type(action.kind) == "string"
        and action.kind ~= ""
end

local function copyAction(action)
    if not validAction(action) then return nil end
    local copy = {}
    for key, value in pairs(action) do copy[key] = value end
    copy.label = tostring(copy.label or copy.key)
    copy.direct = copy.direct == true or DIRECT_ORDER[copy.key] ~= nil
    return copy
end

function Logic:NormalizeActions(actions)
    local result, seen = {}, {}
    for _, action in ipairs(type(actions) == "table" and actions or {}) do
        local copy = copyAction(action)
        if copy and not seen[copy.key] then
            seen[copy.key] = true
            result[#result + 1] = copy
        end
    end
    return result
end

local function orderIndex(order)
    local result = {}
    for index, key in ipairs(type(order) == "table" and order or {}) do
        if type(key) == "string" and key ~= "" and result[key] == nil then
            result[key] = index
        end
    end
    return result
end

function Logic:SortActions(actions, order)
    actions = self:NormalizeActions(actions)
    local indexes = orderIndex(order)
    table.sort(actions, function(left, right)
        local leftIndex = indexes[left.key]
        local rightIndex = indexes[right.key]
        if leftIndex ~= nil or rightIndex ~= nil then
            leftIndex = leftIndex or 100000
            rightIndex = rightIndex or 100000
            if leftIndex ~= rightIndex then return leftIndex < rightIndex end
        end
        local leftDirect = DIRECT_ORDER[left.key] or 1000
        local rightDirect = DIRECT_ORDER[right.key] or 1000
        if leftDirect ~= rightDirect then return leftDirect < rightDirect end
        if left.label ~= right.label then return left.label < right.label end
        return left.key < right.key
    end)
    return actions
end

function Logic:PickRandom(actions, avoidKey, randomCallback)
    actions = self:NormalizeActions(actions)
    if #actions == 0 then return nil end
    local candidates = {}
    for _, action in ipairs(actions) do
        if #actions == 1 or action.key ~= avoidKey then
            candidates[#candidates + 1] = action
        end
    end
    if #candidates == 0 then candidates = actions end
    local index
    if type(randomCallback) == "function" then
        index = tonumber(randomCallback(#candidates))
    end
    index = math.max(1, math.min(#candidates, math.floor(index or math.random(1, #candidates))))
    return candidates[index]
end

local function findByKey(actions, key)
    if type(key) ~= "string" then return nil end
    for _, action in ipairs(actions) do
        if action.key == key then return action end
    end
    return nil
end

function Logic:BuildModel(input)
    input = type(input) == "table" and input or {}
    local hidden = type(input.hidden) == "table" and input.hidden or {}
    local hearthsAll = self:SortActions(input.hearths, input.order)
    local travelAll = self:SortActions(input.travels, input.order)
    local hearths, direct, extras = {}, {}, {}

    for _, action in ipairs(hearthsAll) do
        if hidden[action.key] ~= true then hearths[#hearths + 1] = action end
    end
    for _, action in ipairs(travelAll) do
        if hidden[action.key] ~= true then
            if action.direct then
                direct[#direct + 1] = action
            else
                extras[#extras + 1] = action
            end
        end
    end

    local main
    if input.hearthMode == "fixed" then
        main = findByKey(hearths, input.fixedHearthKey) or hearths[1]
    else
        main = findByKey(hearths, input.currentHearthKey)
            or self:PickRandom(hearths, nil, input.randomCallback)
    end
    local more = findByKey(extras, input.selectedExtraKey) or extras[1]
    local buttons = {}
    if main then
        buttons[#buttons + 1] = { role = "main", action = main }
    end
    for _, action in ipairs(direct) do
        buttons[#buttons + 1] = { role = "direct", action = action }
    end
    for _, action in ipairs(extras) do
        buttons[#buttons + 1] = { role = "destination", action = action }
    end

    return {
        hearthsAll = hearthsAll,
        travelAll = travelAll,
        hearths = hearths,
        direct = direct,
        extras = extras,
        main = main,
        more = more,
        buttons = buttons,
    }
end

function Logic:GetLayout(buttonCount, orientation, frameStyle, iconShape)
    buttonCount = math.max(1, math.floor(tonumber(buttonCount) or 1))
    orientation = orientation == "vertical" and "vertical"
        or orientation == "two_rows" and "two_rows"
        or orientation == "honeycomb" and "honeycomb"
        or "horizontal"
    frameStyle = frameStyle == "clean" and "clean"
        or frameStyle == "compact" and "compact"
        or "warcraft"
    local iconSize = 38
    local gap = 6
    local padding = frameStyle == "warcraft" and 8
        or frameStyle == "compact" and 5
        or 0
    local twoRows = orientation == "two_rows" or orientation == "honeycomb"
    local staggered = orientation == "honeycomb" and iconShape ~= "square"
    local firstRowCount = twoRows and math.ceil(buttonCount / 2) or buttonCount
    local secondRowCount = twoRows and (buttonCount - firstRowCount) or 0
    local secondRowOffset = staggered and math.floor((iconSize + gap) / 2) or 0
    local rowStride = iconSize + gap
    local function rowWidth(count)
        return count > 0 and ((count * iconSize) + ((count - 1) * gap)) or 0
    end
    local width
    local height
    if orientation == "vertical" then
        width = iconSize
        height = rowWidth(buttonCount)
    elseif twoRows then
        width = math.max(rowWidth(firstRowCount), secondRowOffset + rowWidth(secondRowCount))
        height = iconSize + (secondRowCount > 0 and rowStride or 0)
    else
        width = rowWidth(buttonCount)
        height = iconSize
    end
    return {
        orientation = orientation,
        frameStyle = frameStyle,
        iconSize = iconSize,
        gap = gap,
        padding = padding,
        firstRowCount = firstRowCount,
        secondRowCount = secondRowCount,
        secondRowOffset = secondRowOffset,
        rowStride = rowStride,
        staggered = staggered,
        width = width + (padding * 2),
        height = height + (padding * 2),
    }
end

function Logic:GetButtonOffset(layout, index)
    layout = type(layout) == "table" and layout or self:GetLayout(1)
    index = math.max(1, math.floor(tonumber(index) or 1))
    local padding = tonumber(layout.padding) or 0
    local stride = (tonumber(layout.iconSize) or 38) + (tonumber(layout.gap) or 6)
    if layout.orientation == "vertical" then
        return padding, padding + ((index - 1) * stride)
    end
    if layout.orientation == "two_rows" or layout.orientation == "honeycomb" then
        local firstRowCount = math.max(1, tonumber(layout.firstRowCount) or 1)
        if index > firstRowCount then
            return padding + (tonumber(layout.secondRowOffset) or 0)
                    + ((index - firstRowCount - 1) * stride),
                padding + (tonumber(layout.rowStride) or stride)
        end
    end
    return padding + ((index - 1) * stride), padding
end

function Logic:MoveKey(order, availableKeys, key, delta)
    local available, seen = {}, {}
    for _, candidate in ipairs(type(availableKeys) == "table" and availableKeys or {}) do
        if type(candidate) == "string" and candidate ~= "" and not seen[candidate] then
            seen[candidate] = true
            available[#available + 1] = candidate
        end
    end
    local ordered, included = {}, {}
    for _, candidate in ipairs(type(order) == "table" and order or {}) do
        if seen[candidate] and not included[candidate] then
            included[candidate] = true
            ordered[#ordered + 1] = candidate
        end
    end
    for _, candidate in ipairs(available) do
        if not included[candidate] then ordered[#ordered + 1] = candidate end
    end
    local index
    for candidateIndex, candidate in ipairs(ordered) do
        if candidate == key then index = candidateIndex break end
    end
    if not index then return ordered, false end
    local target = math.max(1, math.min(#ordered, index + (delta < 0 and -1 or 1)))
    if target == index then return ordered, false end
    ordered[index], ordered[target] = ordered[target], ordered[index]
    return ordered, true
end
