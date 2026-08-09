local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVP_WEEKLY
local Logic = {}
Addon.PvpWeeklyLogic = Logic

local function poolLabel(pool)
    return L[pool.labelKey] or pool.key or ""
end

local function questTitle(definition)
    local fallback = definition.titleKey and L[definition.titleKey] or definition.fallbackTitle
    return QuestApi:GetTitle(definition.id, fallback or string.format(L.PVP_WEEKLY_QUEST_FALLBACK, definition.id))
end

local function requestQuest(definition)
    if C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(C_QuestLog.RequestLoadQuestByID, definition.id)
    end
end

local function buildQuestRow(pool, definition, status, key, showVariant, variantIndex)
    local title = questTitle(definition)
    local label = poolLabel(pool)
    if showVariant and title and title ~= "" and title ~= label then
        if pool.key == "warmode" and variantIndex then
            label = string.format("%s %d - %s", label, variantIndex, title)
        else
            label = string.format("%s - %s", label, title)
        end
    end
    if status == "complete" then
        return {
            key = key,
            poolKey = pool.key,
            label = label,
            text = L.PVP_WEEKLY_STATUS_DONE,
            status = "complete",
            seen = true,
            completed = true,
            questID = definition.id,
            tooltipTitle = title,
            tooltipLines = { L.PVP_WEEKLY_DONE_TOOLTIP },
        }
    end

    local ready = QuestApi:IsTurnInReady(definition.id)
    local lines = QuestApi:GetObjectiveLines(definition.id)
    if #lines == 0 then
        lines[1] = ready and L.PVP_WEEKLY_TURNIN_TOOLTIP or L.PVP_WEEKLY_ACTIVE_TOOLTIP
    end
    return {
        key = key,
        poolKey = pool.key,
        label = label,
        text = ready and L.PVP_WEEKLY_STATUS_TURNIN
            or QuestApi:GetObjectiveProgressText(definition.id)
            or L.PVP_WEEKLY_STATUS_OPEN,
        status = ready and "turnin" or "open",
        seen = true,
        completed = false,
        questID = definition.id,
        turnInQuestID = ready and definition.id or nil,
        tooltipTitle = title,
        tooltipLines = lines,
    }
end

local function buildPoolRows(pool, knownCompleted)
    local found = {}
    local firstCompleted, firstActive
    for _, definition in ipairs(pool.quests or {}) do
        requestQuest(definition)
        if QuestApi:IsCompleted(definition.id) or knownCompleted[definition.id] then
            firstCompleted = firstCompleted or definition.id
            found[#found + 1] = { definition = definition, status = "complete" }
        elseif QuestApi:IsActive(definition.id) then
            firstActive = firstActive or definition.id
            found[#found + 1] = { definition = definition, status = "active" }
        end
    end

    if #found == 0 then
        local definition = pool.quests and pool.quests[1] or nil
        return definition and {
            {
                key = pool.key,
                poolKey = pool.key,
                label = poolLabel(pool),
                text = L.PVP_WEEKLY_STATUS_MISSING,
                status = "missing",
                seen = false,
                completed = false,
                questID = definition.id,
                tooltipTitle = questTitle(definition),
                tooltipLines = { L.PVP_WEEKLY_GIVER_TOOLTIP },
            },
        } or {}
    end

    local primaryQuestID = firstCompleted or firstActive
    local rows = {}
    for variantIndex, entry in ipairs(found) do
        local questID = entry.definition.id
        rows[#rows + 1] = buildQuestRow(
            pool,
            entry.definition,
            entry.status,
            questID == primaryQuestID and pool.key or string.format("%s:%d", pool.key, questID),
            #found > 1,
            variantIndex
        )
    end
    return rows
end

local function completedQuestLookup(existing)
    local result = {}
    for _, row in ipairs(type(existing) == "table" and existing.rows or {}) do
        local questID = tonumber(type(row) == "table" and row.questID or nil)
        if questID and row.completed == true then
            result[questID] = true
        end
    end
    return result
end

function Logic:BuildSnapshot(existing)
    if not QuestApi:IsAvailable() then
        return existing
    end
    local rows = {}
    local knownCompleted = completedQuestLookup(existing)
    for _, pool in ipairs(DATA.pools) do
        for _, row in ipairs(buildPoolRows(pool, knownCompleted)) do
            rows[#rows + 1] = row
        end
    end

    local completed = 0
    for _, row in ipairs(rows) do
        if row.completed then
            completed = completed + 1
        end
    end
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    return {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        rows = rows,
        summary = {
            completed = completed,
            total = #rows,
            progressText = string.format("%d/%d", completed, #rows),
            resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset),
        },
    }
end
