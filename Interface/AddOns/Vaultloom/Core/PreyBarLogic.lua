local _, Addon = ...

local Logic = {}
Addon.PreyBarLogic = Logic

local FINAL_STAGE = 3
local STAGE_PERCENT = {
    [0] = 0,
    [1] = 33,
    [2] = 66,
    [3] = 100,
}
local MAP_EQUIVALENTS = {
    [2395] = 2395,
    [2405] = 2405,
    [2413] = 2413,
    [2437] = 2437,
    [2444] = 2405,
    [2536] = 2437,
    [2576] = 2413,
}
local HUNT_ZONE_MAPS = {
    [2395] = true,
    [2405] = true,
    [2413] = true,
    [2437] = true,
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = value
    end
    return copy
end

local function readField(object, key)
    if type(object) ~= "table" then return nil end
    local okDirect, direct = pcall(function() return object[key] end)
    if okDirect and direct ~= nil then return direct end

    local getterName = "Get" .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
    local okGetter, getter = pcall(function() return object[getterName] end)
    if okGetter and type(getter) == "function" then
        local okValue, value = pcall(getter, object)
        if okValue then return value end
    end
    return nil
end

function Logic:CoerceNumber(value)
    local okText, text = pcall(tostring, value)
    if not okText or type(text) ~= "string" then return nil end
    local token = text:match("^%s*([%+%-]?%d+%.?%d*)%s*$")
        or text:match("^%s*([%+%-]?%d*%.%d+)%s*$")
    if not token then return nil end
    local okNumber, number = pcall(tonumber, token)
    return okNumber and type(number) == "number" and number or nil
end

function Logic:CanonicalizeMapID(mapID)
    mapID = self:CoerceNumber(mapID)
    if not mapID or mapID <= 0 then return nil end
    mapID = math.floor(mapID)
    return MAP_EQUIVALENTS[mapID] or mapID
end

function Logic:SelectQuestMapID(candidates)
    for _, candidate in ipairs(type(candidates) == "table" and candidates or {}) do
        local mapID = self:CanonicalizeMapID(candidate)
        if mapID and HUNT_ZONE_MAPS[mapID] then return mapID end
    end
    return nil
end

function Logic:IsPlayerInQuestZone(playerMapID, questMapID, getParentMapID)
    playerMapID = self:CoerceNumber(playerMapID)
    questMapID = self:CanonicalizeMapID(questMapID)
    if not playerMapID or not questMapID then return false end

    local seen = {}
    while playerMapID and playerMapID > 0 and not seen[playerMapID] do
        seen[playerMapID] = true
        if self:CanonicalizeMapID(playerMapID) == questMapID then return true end
        if type(getParentMapID) ~= "function" then return false end
        local okParent, parentMapID = pcall(getParentMapID, playerMapID)
        playerMapID = okParent and self:CoerceNumber(parentMapID) or nil
    end
    return false
end

function Logic:ExtractTargetName(questTitle)
    if type(questTitle) ~= "string" or questTitle == "" then return nil end
    local target = questTitle:match("^%s*[^:]+:%s*(.-)%s*%([^)]*%)%s*$")
        or questTitle:match("^%s*[^:]+:%s*(.-)%s*$")
    if type(target) == "string" and target ~= "" then return target end
    return questTitle
end

local function normalizePercent(value)
    value = Logic:CoerceNumber(value)
    if value == nil then return nil end
    if value >= 0 and value <= 1 then value = value * 100 end
    return clamp(value, 0, 100)
end

function Logic:StageFromPercent(percent)
    percent = normalizePercent(percent)
    if percent == nil then return nil end
    if percent >= 100 then return 3 end
    if percent >= 66 then return 2 end
    if percent >= 33 then return 1 end
    return 0
end

function Logic:ProgressFromWidgetState(progressState)
    progressState = self:CoerceNumber(progressState)
    if progressState == nil then return nil, nil end
    progressState = clamp(math.floor(progressState + 0.5), 0, FINAL_STAGE)

    -- Blizzard exposes the hunt as Cold, Warm, Hot and Final. The widget API
    -- does not expose a continuous percentage, so its state is authoritative.
    -- Quest objectives use unrelated counters and can still report 50% when
    -- the hunt widget has already reached Final.
    return progressState, STAGE_PERCENT[progressState] or 0
end

function Logic:ExtractWidgetInfo(info)
    if type(info) ~= "table" then return nil end

    local shownState = self:CoerceNumber(readField(info, "shownState"))
    local shownValue = (Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown) or 1
    local result = {
        shownState = shownState,
        hidden = shownState ~= nil and shownState ~= shownValue,
        progressState = self:CoerceNumber(readField(info, "progressState")),
        tooltip = type(readField(info, "tooltip")) == "string" and readField(info, "tooltip") or nil,
    }

    for _, key in ipairs({
        "questID",
        "questId",
        "associatedQuestID",
        "associatedQuestId",
    }) do
        local questID = self:CoerceNumber(readField(info, key))
        if questID and questID > 0 then
            result.questID = math.floor(questID)
            break
        end
    end

    for _, key in ipairs({
        "progressPercentage",
        "progressPercent",
        "fillPercentage",
        "percentage",
        "percent",
        "progress",
        "progressValue",
    }) do
        local percent = normalizePercent(readField(info, key))
        if percent ~= nil then
            result.percent = percent
            break
        end
    end

    if result.percent == nil then
        local current
        for _, key in ipairs({ "barValue", "value", "currentValue" }) do
            current = self:CoerceNumber(readField(info, key))
            if current ~= nil then break end
        end
        local maximum
        for _, key in ipairs({ "barMax", "maxValue", "totalValue", "total", "max" }) do
            maximum = self:CoerceNumber(readField(info, key))
            if maximum ~= nil then break end
        end
        if current and maximum and maximum > 0 then
            result.percent = clamp((current / maximum) * 100, 0, 100)
        end
    end

    if result.percent == nil and result.tooltip then
        result.percent = normalizePercent(result.tooltip:match("(%d+)%s*%%"))
    end
    if result.progressState ~= nil then
        result.progressState = clamp(math.floor(result.progressState + 0.5), 0, FINAL_STAGE)
    end
    return result
end

local function objectiveDone(objective)
    if type(objective) ~= "table" then return false end
    if objective.finished == true then return true end
    local current = Logic:CoerceNumber(objective.numFulfilled or objective.fulfilled)
    local maximum = Logic:CoerceNumber(objective.numRequired or objective.required)
    return current ~= nil and maximum ~= nil and maximum > 0 and current >= maximum
end

function Logic:ExtractObjectiveInfo(objectives)
    objectives = type(objectives) == "table" and objectives or {}
    if #objectives == 0 then return nil end

    local fulfilled, required = 0, 0
    local hasNumeric = false
    local activeText
    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local current = self:CoerceNumber(objective.numFulfilled or objective.fulfilled)
            local maximum = self:CoerceNumber(objective.numRequired or objective.required)
            if current and maximum and maximum > 0 then
                fulfilled = fulfilled + math.max(0, current)
                required = required + math.max(0, maximum)
                hasNumeric = true
            end
            if not activeText and objective.finished ~= true
                and type(objective.text) == "string" and objective.text ~= ""
            then
                activeText = objective.text
            end
        end
    end

    local completedObjectives = 0
    for _, objective in ipairs(objectives) do
        if objectiveDone(objective) then
            completedObjectives = completedObjectives + 1
        end
    end
    local stage = clamp(completedObjectives, 0, FINAL_STAGE)

    return {
        stage = stage,
        percent = hasNumeric and required > 0 and clamp((fulfilled / required) * 100, 0, 100) or nil,
        activeText = activeText,
    }
end

function Logic:BuildProgress(questID, widgetInfo, objectives, previous)
    questID = self:CoerceNumber(questID)
    if not questID or questID <= 0 then return nil end

    local widget = self:ExtractWidgetInfo(widgetInfo)
    if widget and widget.questID and widget.questID ~= math.floor(questID) then
        widget = nil
    end
    if widget and widget.hidden then
        return {
            questID = math.floor(questID),
            hidden = true,
            source = "widget",
        }
    end

    local objective = self:ExtractObjectiveInfo(objectives)
    local widgetState = widget and widget.progressState or nil
    local stage, percent = self:ProgressFromWidgetState(widgetState)
    if percent == nil and objective then percent = objective.percent end
    if stage == nil then stage = self:StageFromPercent(percent) end
    if stage == nil and objective then stage = objective.stage end
    if percent == nil and stage ~= nil then
        percent = STAGE_PERCENT[stage] or 0
    end

    local samePrevious = type(previous) == "table"
        and tonumber(previous.questID) == math.floor(questID)
        and previous.hidden ~= true
    if stage == nil and percent == nil and samePrevious then
        local held = copyTable(previous)
        held.stale = true
        return held
    end

    stage = clamp(math.floor((tonumber(stage) or 0) + 0.5), 0, FINAL_STAGE)
    percent = clamp(percent or STAGE_PERCENT[stage] or 0, 0, 100)

    if samePrevious then
        local oldPercent = clamp(previous.percent or 0, 0, 100)
        percent = math.max(percent, oldPercent)
        stage = self:StageFromPercent(percent) or stage
    end

    return {
        questID = math.floor(questID),
        hidden = false,
        stage = stage,
        percent = percent,
        progressState = widgetState,
        activeText = objective and objective.activeText or nil,
        source = widget and "widget" or objective and "quest" or "fallback",
    }
end

function Logic:BuildModel(input, previousProgress)
    input = type(input) == "table" and input or {}
    local questID = self:CoerceNumber(input.questID)
    if not questID or questID <= 0 then
        return {
            active = false,
            inZone = false,
            visible = false,
        }
    end

    questID = math.floor(questID)
    local inZone = input.inZone == true
    local progress = self:BuildProgress(
        questID,
        input.widgetInfo,
        input.objectives,
        previousProgress
    )
    return {
        active = true,
        inZone = inZone,
        visible = inZone and type(progress) == "table" and progress.hidden ~= true,
        questID = questID,
        questMapID = self:CanonicalizeMapID(input.questMapID),
        playerMapID = self:CanonicalizeMapID(input.playerMapID),
        mapName = input.mapName,
        questTitle = input.questTitle,
        targetName = self:ExtractTargetName(input.questTitle),
        progress = progress,
    }
end
