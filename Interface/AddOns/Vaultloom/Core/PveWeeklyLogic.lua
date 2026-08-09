local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DEFINITIONS = Addon.Data.PVE_WEEKLY

local Logic = {}
Addon.PveWeeklyLogic = Logic

local function containsPattern(text, patterns)
    text = string.lower(tostring(text or ""))
    for _, pattern in ipairs(patterns or {}) do
        if text:find(string.lower(pattern), 1, true) then
            return true
        end
    end
    return false
end

local function getActiveStatusText(questID, readyToTurnIn)
    if readyToTurnIn then
        return L.PVE_WEEKLY_STATUS_TURNIN
    end
    return QuestApi:GetObjectiveProgressText(questID) or L.PVE_WEEKLY_STATUS_OPEN
end

local function missingRow(config)
    return {
        key = config.key,
        label = config.label,
        text = L.PVE_WEEKLY_STATUS_MISSING,
        status = "missing",
        seen = false,
        completed = false,
        tooltipTitle = config.label,
        tooltipLines = { config.acceptHint },
        accountWide = config.accountWide == true,
    }
end

local function completedRow(config, questID, title)
    return {
        key = config.key,
        label = config.label,
        text = L.PVE_WEEKLY_STATUS_DONE,
        status = "complete",
        seen = true,
        completed = true,
        questID = questID,
        tooltipTitle = title or config.label,
        tooltipLines = { config.doneHint },
        accountWide = config.accountWide == true,
    }
end

local function activeRow(config, questID, title)
    local ready = config.allowTurnIn ~= false and QuestApi:IsTurnInReady(questID)
    local lines = QuestApi:GetObjectiveLines(questID)
    if #lines == 0 then
        lines[1] = ready and config.turnInHint or config.activeHint
    end
    return {
        key = config.key,
        label = config.label,
        text = getActiveStatusText(questID, ready),
        status = ready and "turnin" or "open",
        seen = true,
        completed = false,
        questID = questID,
        turnInQuestID = ready and questID or nil,
        tooltipTitle = title and title ~= config.label and string.format("%s - %s", config.label, title) or config.label,
        tooltipLines = lines,
        accountWide = config.accountWide == true,
    }
end

local function localizedConfig(key)
    local source = DEFINITIONS[key]
    local config = {}
    for field, value in pairs(source) do
        config[field] = value
    end
    if key == "spark" then
        config.label = L.PVE_WEEKLY_SPARK_LABEL
        config.acceptHint = L.PVE_WEEKLY_SPARK_ACCEPT_HINT
        config.activeHint = L.PVE_WEEKLY_SPARK_ACTIVE_HINT
        config.turnInHint = L.PVE_WEEKLY_SPARK_TURNIN_HINT
        config.doneHint = L.PVE_WEEKLY_SPARK_DONE_HINT
        config.allowTurnIn = true
    elseif key == "omnium_folio" then
        config.label = L.PVE_WEEKLY_OMNIUM_LABEL
        config.acceptHint = L.PVE_WEEKLY_OMNIUM_ACCEPT_HINT
        config.activeHint = L.PVE_WEEKLY_OMNIUM_ACTIVE_HINT
        config.turnInHint = L.PVE_WEEKLY_GENERIC_TURNIN_HINT
        config.doneHint = L.PVE_WEEKLY_GENERIC_DONE_HINT
    elseif key == "rotating_world_weekly" then
        config.label = L.PVE_WEEKLY_DUNGEON_LABEL
        config.acceptHint = L.PVE_WEEKLY_DUNGEON_ACCEPT_HINT
        config.activeHint = L.PVE_WEEKLY_GENERIC_ACTIVE_HINT
        config.turnInHint = L.PVE_WEEKLY_GENERIC_TURNIN_HINT
        config.doneHint = L.PVE_WEEKLY_GENERIC_DONE_HINT
    elseif key == "rotating_world_aethas" then
        config.label = L.PVE_WEEKLY_AETHAS_LABEL
        config.acceptHint = L.PVE_WEEKLY_AETHAS_ACCEPT_HINT
        config.activeHint = L.PVE_WEEKLY_GENERIC_ACTIVE_HINT
        config.turnInHint = L.PVE_WEEKLY_GENERIC_TURNIN_HINT
        config.doneHint = L.PVE_WEEKLY_GENERIC_DONE_HINT
    else
        config.label = L.PVE_WEEKLY_HOUSING_LABEL
        config.acceptHint = L.PVE_WEEKLY_HOUSING_ACCEPT_HINT
        config.activeHint = L.PVE_WEEKLY_GENERIC_ACTIVE_HINT
        config.turnInHint = L.PVE_WEEKLY_GENERIC_TURNIN_HINT
        config.doneHint = L.PVE_WEEKLY_GENERIC_DONE_HINT
    end
    return config
end

local function buildSparkRow()
    local config = localizedConfig("spark")
    local activeQuestID, completedQuestID
    for _, questID in ipairs(config.questPool) do
        if QuestApi:IsCompleted(questID) then
            completedQuestID = questID
            break
        elseif not activeQuestID and QuestApi:IsActive(questID) then
            activeQuestID = questID
        end
    end

    local chosenQuestID = activeQuestID or completedQuestID
    local suffix = chosenQuestID and config.variantSuffix[chosenQuestID]
    if suffix then
        config.label = config.label .. " - " .. suffix
    end
    if completedQuestID then
        return completedRow(config, completedQuestID, config.label)
    elseif activeQuestID then
        return activeRow(config, activeQuestID, config.label)
    end
    return missingRow(config)
end

local function buildRememberedRow(key, memory)
    local config = localizedConfig(key)
    local activeQuestID
    for _, questID in ipairs(config.questPool or {}) do
        if QuestApi:IsActive(questID) then
            activeQuestID = questID
            break
        end
    end
    if not activeQuestID then
        for _, entry in ipairs(QuestApi:GetLogEntries()) do
            if entry.questID > 0 and containsPattern(entry.title, config.titlePatterns) then
                activeQuestID = entry.questID
                break
            end
        end
    end

    local bucket = memory[config.memoryKey] or {}
    memory[config.memoryKey] = bucket
    if activeQuestID then
        local title = QuestApi:GetTitle(activeQuestID, config.fallbackNames and config.fallbackNames[activeQuestID] or config.label)
        bucket.questID = activeQuestID
        bucket.title = title
        return activeRow(config, activeQuestID, title)
    end

    local rememberedQuestID = tonumber(bucket.questID)
    local title = rememberedQuestID and QuestApi:GetTitle(rememberedQuestID, bucket.title) or bucket.title
    if rememberedQuestID and QuestApi:IsCompleted(rememberedQuestID) then
        return completedRow(config, rememberedQuestID, title)
    end
    return missingRow(config)
end

local function isOmniumFolioComplete(accountState)
    if type(accountState) == "table" and accountState.omniumFolioComplete == true then
        return true
    end

    local config = DEFINITIONS.omnium_folio
    if not config.hideWhenSeriesComplete or #(config.questPool or {}) == 0 then
        return false
    end
    for _, questID in ipairs(config.questPool) do
        if not QuestApi:IsCompletedOnAccount(questID) and not QuestApi:IsCompleted(questID) then
            return false
        end
    end

    if type(accountState) == "table" then
        accountState.omniumFolioComplete = true
    end
    return true
end

local function refreshSummary(snapshot)
    local completed = 0
    for _, row in ipairs(snapshot.rows or {}) do
        if row.completed or row.status == "complete" then
            completed = completed + 1
        end
    end
    snapshot.summary = type(snapshot.summary) == "table" and snapshot.summary or {}
    snapshot.summary.completed = completed
    snapshot.summary.total = #(snapshot.rows or {})
    snapshot.summary.progressText = string.format("%d/%d", completed, snapshot.summary.total)
end

function Logic:ApplyAccountHides(snapshot, accountState)
    if type(snapshot) ~= "table"
        or type(snapshot.rows) ~= "table"
        or type(accountState) ~= "table"
        or accountState.omniumFolioComplete ~= true
    then
        return snapshot
    end

    local changed = false
    for index = #snapshot.rows, 1, -1 do
        if snapshot.rows[index].key == "omnium_folio" then
            table.remove(snapshot.rows, index)
            changed = true
        end
    end
    if changed then
        refreshSummary(snapshot)
    end
    return snapshot
end

function Logic:BuildSnapshot(memory, existingSnapshot, accountState)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end
    memory = type(memory) == "table" and memory or {}
    accountState = type(accountState) == "table" and accountState or {}
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    local rows = {
        buildSparkRow(),
    }
    if not isOmniumFolioComplete(accountState) then
        rows[#rows + 1] = buildRememberedRow("omnium_folio", memory)
    end
    rows[#rows + 1] = buildRememberedRow("rotating_world_weekly", memory)
    rows[#rows + 1] = buildRememberedRow("rotating_world_aethas", memory)
    rows[#rows + 1] = buildRememberedRow("housing", memory)

    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        rows = rows,
        summary = {
            resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset),
        },
    }
    refreshSummary(snapshot)
    return snapshot
end
