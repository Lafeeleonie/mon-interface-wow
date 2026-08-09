local _, Addon = ...

local Logic = {}
Addon.PreyHuntIconsLogic = Logic

local ICON_COORDS = {
    [1] = {
        ready = { 0.00, 0.25, 0.00, 0.25 },
        needed = { 0.00, 0.25, 0.25, 0.50 },
    },
    [2] = {
        ready = { 0.25, 0.50, 0.00, 0.25 },
        needed = { 0.25, 0.50, 0.25, 0.50 },
    },
    [3] = {
        ready = { 0.50, 0.75, 0.00, 0.25 },
        needed = { 0.50, 0.75, 0.25, 0.50 },
    },
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function positiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

function Logic:GetQuestData(questID)
    local data = Addon.Data
        and Addon.Data.PREY_HUNT_ICONS
        and Addon.Data.PREY_HUNT_ICONS.quests
        or nil
    questID = positiveInteger(questID)
    local entry = questID and data and data[questID] or nil
    if type(entry) ~= "table" then return nil end
    return {
        questID = questID,
        difficulty = positiveInteger(entry.difficulty),
        criteriaID = positiveInteger(entry.criteriaID),
    }
end

function Logic:GetIconCoords(difficulty, needsAchievement)
    local variants = ICON_COORDS[positiveInteger(difficulty)]
    local coords = variants and variants[needsAchievement == true and "needed" or "ready"] or nil
    if not coords then return 0, 1, 0, 1 end
    return coords[1], coords[2], coords[3], coords[4]
end

function Logic:BuildPinModel(questID, criteriaCompleted, showAchievementMarker, scalePercent)
    local quest = self:GetQuestData(questID)
    if not quest or not quest.difficulty or not quest.criteriaID then return nil end
    local data = Addon.Data.PREY_HUNT_ICONS
    local achievementID = data.achievementIDs[quest.difficulty]
    local completed
    if type(criteriaCompleted) == "function" and achievementID then
        local ok, value = pcall(criteriaCompleted, achievementID, quest.criteriaID)
        if ok and type(value) == "boolean" then completed = value end
    end
    local needsAchievement = showAchievementMarker ~= false and completed == false
    local left, right, top, bottom = self:GetIconCoords(quest.difficulty, needsAchievement)
    local scale = clamp(scalePercent, 80, 120) / 100
    local baseSize = tonumber(data.baseSize) or 38
    return {
        questID = quest.questID,
        difficulty = quest.difficulty,
        criteriaID = quest.criteriaID,
        achievementID = achievementID,
        achievementCompleted = completed,
        needsAchievement = needsAchievement,
        left = left,
        right = right,
        top = top,
        bottom = bottom,
        size = math.floor((baseSize * scale) + 0.5),
    }
end

function Logic:CountByDifficulty()
    local result = { [1] = 0, [2] = 0, [3] = 0, total = 0 }
    local quests = Addon.Data
        and Addon.Data.PREY_HUNT_ICONS
        and Addon.Data.PREY_HUNT_ICONS.quests
        or {}
    for _, entry in pairs(quests) do
        local difficulty = positiveInteger(entry and entry.difficulty)
        if result[difficulty] ~= nil then
            result[difficulty] = result[difficulty] + 1
            result.total = result.total + 1
        end
    end
    return result
end
