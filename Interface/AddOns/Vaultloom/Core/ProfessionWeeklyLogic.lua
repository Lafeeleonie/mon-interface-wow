local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PROFESSIONS
local Logic = {}
Addon.ProfessionWeeklyLogic = Logic

local STATUS_RANK = {
    missing = 1,
    open = 2,
    turnin = 3,
    complete = 4,
}

local function requestQuest(questID)
    if C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(C_QuestLog.RequestLoadQuestByID, questID)
    end
end

local function getProfessionList(character)
    local result = {}
    for _, entry in ipairs(type(character) == "table" and character.professions or {}) do
        local skillLineID = tonumber(type(entry) == "table" and entry.skillLineID or nil)
        local professionKey = skillLineID and DATA.skillLineToKey[skillLineID] or nil
        if professionKey then
            result[#result + 1] = {
                key = professionKey,
                skillLineID = skillLineID,
                slotIndex = tonumber(entry.slotIndex),
                spellOffset = tonumber(entry.spellOffset),
                name = entry.name or professionKey,
                icon = entry.icon,
            }
        end
    end
    table.sort(result, function(left, right)
        return tostring(left.name or "") < tostring(right.name or "")
    end)
    return result
end

local function questState(questIDs)
    local completedID, activeID
    for _, questID in ipairs(questIDs or {}) do
        requestQuest(questID)
        if QuestApi:IsCompleted(questID) then
            completedID = completedID or questID
        elseif QuestApi:IsActive(questID) then
            activeID = activeID or questID
        end
    end

    local questID = completedID or activeID or (questIDs and questIDs[1])
    if completedID then
        return completedID, "complete", true, true
    end
    if activeID then
        if QuestApi:IsTurnInReady(activeID) then
            return activeID, "turnin", false, true
        end
        return activeID, "open", false, true
    end
    return questID, "missing", false, false
end

local function statusText(status, questID)
    if status == "complete" then
        return L.PROFESSIONS_STATUS_DONE
    elseif status == "turnin" then
        return L.PROFESSIONS_STATUS_TURNIN
    elseif status == "open" then
        return QuestApi:GetObjectiveProgressText(questID) or L.PROFESSIONS_STATUS_OPEN
    end
    return L.PROFESSIONS_STATUS_MISSING
end

local function statusHint(status, missingHint, openHint, questID)
    if status == "complete" then
        return { L.PROFESSIONS_TOOLTIP_DONE }
    elseif status == "turnin" then
        return { L.PROFESSIONS_TOOLTIP_TURNIN }
    elseif status == "open" then
        local lines = QuestApi:GetObjectiveLines(questID)
        return #lines > 0 and lines or { openHint }
    end
    return { missingHint }
end

local function buildWeeklyRow(profession, kind, questIDs)
    local suffix = kind == "service" and L.PROFESSIONS_ROW_SERVICE or L.PROFESSIONS_ROW_TREATISE
    local questID, status, completed, seen = questState(questIDs)
    local label = string.format("%s - %s", profession.name, suffix)
    local tooltipLines
    if kind == "service" then
        tooltipLines = statusHint(
            status,
            L.PROFESSIONS_TOOLTIP_SERVICE_MISSING,
            L.PROFESSIONS_TOOLTIP_SERVICE_PROGRESS,
            questID
        )
    else
        tooltipLines = { L.PROFESSIONS_TOOLTIP_TREATISE_ITEM_HINT }
        for _, line in ipairs(statusHint(
            status,
            L.PROFESSIONS_TOOLTIP_TREATISE_MISSING,
            L.PROFESSIONS_TOOLTIP_TREATISE_PROGRESS,
            questID
        )) do
            tooltipLines[#tooltipLines + 1] = line
        end
    end
    return {
        key = string.format("profession_%s_%s", kind, profession.key),
        professionKey = profession.key,
        professionName = profession.name,
        skillLineID = profession.skillLineID,
        slotIndex = profession.slotIndex,
        spellOffset = profession.spellOffset,
        label = label,
        text = statusText(status, questID),
        status = status,
        completed = completed,
        seen = seen,
        questID = questID,
        turnInQuestID = status == "turnin" and questID or nil,
        tooltipTitle = label,
        tooltipLines = tooltipLines,
    }
end

local function appendDarkmoonItems(lines, definition)
    if type(definition.items) ~= "table" or #definition.items == 0 then
        return
    end
    lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_REQUIRES
    for _, item in ipairs(definition.items) do
        lines[#lines + 1] = string.format(
            "%dx %s",
            math.max(1, tonumber(item.count) or 1),
            Addon.WoWApi:GetItemDisplayName(item.id)
        )
    end
end

local function buildDarkmoonRow(profession)
    local definition = DATA.darkmoonQuests[profession.key]
    if type(definition) ~= "table" then
        return nil
    end
    local questID, status, completed, seen = questState({ definition.id })
    local label = string.format("%s - %s", profession.name, L.PROFESSIONS_ROW_DARKMOON)
    local lines = {}
    appendDarkmoonItems(lines, definition)
    lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_REWARD
    lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_MONTHLY
    if status == "complete" then
        lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_DONE
    elseif status == "turnin" then
        lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_TURNIN
    elseif status == "open" then
        local objectiveLines = QuestApi:GetObjectiveLines(questID)
        if #objectiveLines > 0 then
            for _, line in ipairs(objectiveLines) do
                lines[#lines + 1] = line
            end
        else
            lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_PROGRESS
        end
    else
        lines[#lines + 1] = L.PROFESSIONS_TOOLTIP_DARKMOON_MISSING
    end
    return {
        key = "profession_darkmoon_" .. profession.key,
        professionKey = profession.key,
        professionName = profession.name,
        skillLineID = profession.skillLineID,
        slotIndex = profession.slotIndex,
        spellOffset = profession.spellOffset,
        resetType = "darkmoon",
        label = label,
        text = statusText(status, questID),
        status = status,
        completed = completed,
        seen = seen,
        questID = questID,
        turnInQuestID = status == "turnin" and questID or nil,
        tooltipTitle = label,
        tooltipLines = lines,
    }
end

local function rebuildSummary(snapshot)
    local completed, open = 0, 0
    for _, row in ipairs(snapshot.rows or {}) do
        if row.completed then
            completed = completed + 1
        elseif row.seen then
            open = open + 1
        end
    end
    local isEmpty = #snapshot.rows == 1 and snapshot.rows[1].key == "profession_none"
    local total = isEmpty and 0 or #snapshot.rows
    snapshot.summary = {
        completed = completed,
        open = open,
        total = total,
        progressText = string.format("%d/%d", completed, total),
        resetText = snapshot.summary and snapshot.summary.resetText or "",
    }
end

local function preserveProgress(existing, current, darkmoonResetKey)
    if type(existing) ~= "table" or type(existing.rows) ~= "table" then
        return current
    end
    local existingDarkmoonKey = existing.darkmoonResetKey
    local byKey = {}
    for _, row in ipairs(existing.rows) do
        if row.resetType ~= "darkmoon" or (darkmoonResetKey and existingDarkmoonKey == darkmoonResetKey) then
            byKey[row.key or tostring(row.questID)] = row
        end
    end
    for index, row in ipairs(current.rows) do
        local previous = byKey[row.key or tostring(row.questID)]
        local previousRank = previous and STATUS_RANK[previous.status] or 0
        local currentRank = STATUS_RANK[row.status] or 0
        if previous and (previous.completed == true and row.completed ~= true
            or previousRank > currentRank
            or previous.seen == true and row.seen ~= true and row.status == "missing")
        then
            current.rows[index] = previous
        end
    end
    rebuildSummary(current)
    return current
end

function Logic:FilterDarkmoon(snapshot, detectorState)
    if type(snapshot) ~= "table" or type(snapshot.rows) ~= "table" then
        return snapshot
    end
    local active = type(detectorState) == "table" and detectorState.active == true
    local matchingReset = active and (not snapshot.darkmoonResetKey
        or not detectorState.resetKey
        or snapshot.darkmoonResetKey == detectorState.resetKey)
    if matchingReset then
        return snapshot
    end
    local hasDarkmoonRows = false
    for _, row in ipairs(snapshot.rows) do
        if row.resetType == "darkmoon" then
            hasDarkmoonRows = true
            break
        end
    end
    if not hasDarkmoonRows then
        return snapshot
    end
    local filtered = {}
    for key, value in pairs(snapshot) do
        if key ~= "rows" and key ~= "summary" then
            filtered[key] = value
        end
    end
    filtered.rows = {}
    for _, row in ipairs(snapshot.rows) do
        if row.resetType ~= "darkmoon" then
            filtered.rows[#filtered.rows + 1] = row
        end
    end
    filtered.summary = { resetText = snapshot.summary and snapshot.summary.resetText or "" }
    rebuildSummary(filtered)
    return filtered
end

function Logic:BuildSnapshot(character, existing, detectorState)
    if not QuestApi:IsAvailable() then
        return existing
    end
    local professions = getProfessionList(character)
    local rows = {}
    for _, profession in ipairs(professions) do
        local quests = DATA.serviceQuests[profession.key]
        if type(quests) == "table" and #quests > 0 then
            rows[#rows + 1] = buildWeeklyRow(profession, "service", quests)
        end
    end
    for _, profession in ipairs(professions) do
        local questID = tonumber(DATA.treatiseQuests[profession.key])
        if questID then
            rows[#rows + 1] = buildWeeklyRow(profession, "treatise", { questID })
        end
    end
    local darkmoonActive = type(detectorState) == "table" and detectorState.active == true
    if darkmoonActive then
        for _, profession in ipairs(professions) do
            local row = buildDarkmoonRow(profession)
            if row then
                rows[#rows + 1] = row
            end
        end
    end
    if #rows == 0 then
        rows[1] = {
            key = "profession_none",
            label = L.PROFESSIONS_EMPTY_LABEL,
            text = L.PROFESSIONS_EMPTY_VALUE,
            status = "missing",
            completed = false,
            seen = false,
            tooltipTitle = L.PROFESSIONS_EMPTY_LABEL,
            tooltipLines = { L.PROFESSIONS_EMPTY_HINT },
        }
    end
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo(
        type(existing) == "table" and existing.resetAt or nil
    )
    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        darkmoonResetKey = darkmoonActive and detectorState.resetKey or nil,
        rows = rows,
        summary = { resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset) },
    }
    rebuildSummary(snapshot)
    return preserveProgress(existing, snapshot, snapshot.darkmoonResetKey)
end
