local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_PREY

local Logic = {}
Addon.PvePreyLogic = Logic

local function copyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = value
    end
    return copy
end

local function buildQuestRow(key, questID, target, label, memory, memoryKey)
    local completed = QuestApi:IsCompleted(questID)
        or (type(memory) == "table" and memory[memoryKey] == true)
    local active = QuestApi:IsActive(questID)
    local ready = active and QuestApi:IsTurnInReady(questID)
    local tooltipLines = {}

    if completed then
        if type(memory) == "table" then
            memory[memoryKey] = true
        end
        tooltipLines[1] = L.PVE_PREY_WEEKLY_DONE_HINT
        return {
            key = key,
            label = label,
            text = L.PVE_PREY_STATUS_DONE,
            status = "complete",
            seen = true,
            completed = true,
            count = target,
            maxCount = target,
            questID = questID,
            tooltipTitle = label,
            tooltipLines = tooltipLines,
        }
    end

    if ready then
        tooltipLines[1] = L.PVE_PREY_WEEKLY_TURNIN_HINT
        return {
            key = key,
            label = label,
            text = L.PVE_PREY_STATUS_TURNIN,
            status = "turnin",
            seen = true,
            completed = false,
            count = target,
            maxCount = target,
            questID = questID,
            turnInQuestID = questID,
            tooltipTitle = label,
            tooltipLines = tooltipLines,
        }
    end

    if active then
        local objectiveLines = QuestApi:GetObjectiveLines(questID)
        local count = 0
        for _, line in ipairs(objectiveLines) do
            tooltipLines[#tooltipLines + 1] = line
            local current, maximum = QuestApi:ParseObjectiveFraction(line)
            if current and maximum and maximum > 0 then
                count = math.max(count, math.min(target, current))
            end
        end
        if #tooltipLines == 0 then
            tooltipLines[1] = L.PVE_PREY_WEEKLY_ACTIVE_HINT
        end
        local objectiveComplete = count >= target
        return {
            key = key,
            label = label,
            text = objectiveComplete and L.PVE_PREY_STATUS_TURNIN or string.format("%d/%d", count, target),
            status = objectiveComplete and "turnin" or "open",
            seen = true,
            completed = false,
            count = count,
            maxCount = target,
            questID = questID,
            turnInQuestID = objectiveComplete and questID or nil,
            tooltipTitle = label,
            tooltipLines = tooltipLines,
        }
    end

    tooltipLines[1] = L.PVE_PREY_WEEKLY_ACCEPT_HINT
    return {
        key = key,
        label = label,
        text = L.PVE_PREY_STATUS_MISSING,
        status = "missing",
        seen = false,
        completed = false,
        count = 0,
        maxCount = target,
        questID = questID,
        tooltipTitle = label,
        tooltipLines = tooltipLines,
    }
end

local function mergeWithExisting(snapshot, existingSnapshot)
    if type(existingSnapshot) ~= "table" then
        return snapshot
    end

    local total = 0
    for _, key in ipairs(DATA.difficultyOrder) do
        local current = snapshot.difficulties[key]
        local old = type(existingSnapshot.difficulties) == "table" and existingSnapshot.difficulties[key] or nil
        if current.unlocked then
            local oldCount = math.max(0, tonumber(old and old.count) or 0)
            current.count = math.min(current.cap, math.max(current.count, oldCount))
            total = total + current.count
        end
    end
    snapshot.total = total

    for _, field in ipairs({ "weeklyQuest", "preferredQuest" }) do
        local current = snapshot[field]
        local old = existingSnapshot[field]
        if type(old) == "table" and old.completed == true and type(current) == "table" and current.completed ~= true then
            snapshot[field] = copyTable(old)
        end
    end
    return snapshot
end

function Logic:BuildSnapshot(memory, existingSnapshot)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end

    memory = type(memory) == "table" and memory or {}
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    local renownLevel = Addon.WoWApi:GetCurrentRenownLevel(DATA.renownFactionID)
    local activeMapName, activeQuestID = Addon.WoWApi:GetActivePreyMapName()
    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        renownLevel = renownLevel,
        activeMapName = activeMapName,
        activeQuestID = activeQuestID,
        total = 0,
        totalCap = DATA.difficultyCap,
        difficultyCap = DATA.difficultyCap,
        unlockedCount = 0,
        difficulties = {},
    }

    for _, key in ipairs(DATA.difficultyOrder) do
        local count = 0
        for _, questID in ipairs(DATA.targetQuests[key] or {}) do
            if QuestApi:IsCompleted(questID) then
                count = count + 1
            end
        end
        local unlocked = renownLevel >= (DATA.difficultyRenown[key] or 0)
        snapshot.difficulties[key] = {
            count = math.min(DATA.difficultyCap, count),
            cap = DATA.difficultyCap,
            unlocked = unlocked,
        }
        if unlocked then
            snapshot.unlockedCount = snapshot.unlockedCount + 1
            snapshot.total = snapshot.total + snapshot.difficulties[key].count
        end
    end

    snapshot.unlockedCount = math.max(1, snapshot.unlockedCount)
    snapshot.totalCap = math.max(DATA.difficultyCap, snapshot.unlockedCount * DATA.difficultyCap)
    snapshot.weeklyQuest = buildQuestRow(
        "prey_weekly",
        DATA.weeklyQuestID,
        DATA.weeklyQuestTarget,
        L.PVE_PREY_WEEKLY_NAME,
        memory,
        "weeklyCompleted"
    )
    snapshot.preferredQuest = buildQuestRow(
        "prey_preferred",
        DATA.preferredQuestID,
        DATA.preferredQuestTarget,
        L.PVE_PREY_PREFERRED_NAME,
        memory,
        "preferredCompleted"
    )
    snapshot.summary = {
        resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset),
    }
    return mergeWithExisting(snapshot, existingSnapshot)
end
