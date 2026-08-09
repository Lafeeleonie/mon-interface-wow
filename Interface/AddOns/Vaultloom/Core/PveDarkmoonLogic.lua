local _, Addon = ...

local L = Addon.L
local DATA = Addon.Data.PVE_DARKMOON
local QuestApi = Addon.QuestApi
local Logic = {}
Addon.PveDarkmoonLogic = Logic

local function localizedTitle(definition)
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    local titles = type(definition.title) == "table" and definition.title or {}
    return titles[locale] or titles.enUS or titles.deDE
end

local function buildRow(definition)
    local questID = tonumber(definition.id)
    if C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(C_QuestLog.RequestLoadQuestByID, questID)
    end

    local fallback = localizedTitle(definition) or string.format(L.PVE_DARKMOON_QUEST_FALLBACK, questID)
    local label = QuestApi:GetTitle(questID, fallback)
    local completed = QuestApi:IsCompleted(questID)
    local active = not completed and QuestApi:IsActive(questID)
    local ready = active and QuestApi:IsTurnInReady(questID) or false
    local resetType = definition.reset == "daily" and "daily" or "darkmoon"
    local status = completed and "complete" or ready and "turnin" or active and "open" or "missing"
    local text = completed and L.PVE_DARKMOON_STATUS_DONE
        or ready and L.PVE_DARKMOON_STATUS_TURNIN
        or active and (QuestApi:GetObjectiveProgressText(questID) or L.PVE_DARKMOON_STATUS_OPEN)
        or L.PVE_DARKMOON_STATUS_MISSING
    local tooltipLines = {}
    local startItemID = tonumber(definition.startItemID)
    local costItemID = tonumber(definition.costItemID)

    if startItemID then
        tooltipLines[#tooltipLines + 1] = string.format(
            L.PVE_DARKMOON_START_ITEM_HINT,
            Addon.WoWApi:GetItemDisplayName(startItemID)
        )
        if Addon.WoWApi:GetItemCount(startItemID) > 0 and status == "missing" then
            status = "turnin"
            text = L.PVE_DARKMOON_STATUS_TURNIN
        end
    end
    if costItemID then
        tooltipLines[#tooltipLines + 1] = string.format(
            L.PVE_DARKMOON_TOKEN_HINT,
            Addon.WoWApi:GetItemDisplayName(costItemID)
        )
    end
    tooltipLines[#tooltipLines + 1] = resetType == "daily"
        and L.PVE_DARKMOON_DAILY_HINT
        or L.PVE_DARKMOON_MONTHLY_HINT

    if status == "missing" then
        tooltipLines[#tooltipLines + 1] = L.PVE_DARKMOON_ACCEPT_HINT
    elseif status == "turnin" then
        tooltipLines[#tooltipLines + 1] = L.PVE_DARKMOON_TURNIN_HINT
    elseif status == "complete" then
        tooltipLines[#tooltipLines + 1] = resetType == "daily"
            and L.PVE_DARKMOON_DONE_DAILY_HINT
            or L.PVE_DARKMOON_DONE_MONTHLY_HINT
    else
        local objectives = QuestApi:GetObjectiveLines(questID)
        if #objectives == 0 then
            tooltipLines[#tooltipLines + 1] = L.PVE_DARKMOON_ACTIVE_HINT
        else
            for _, line in ipairs(objectives) do
                tooltipLines[#tooltipLines + 1] = line
            end
        end
    end

    return {
        key = "darkmoon_" .. definition.key,
        label = label,
        text = text,
        status = status,
        completed = completed,
        seen = completed or active or status == "turnin",
        questID = questID,
        turnInQuestID = status == "turnin" and questID or nil,
        resetType = resetType,
        category = definition.category,
        startItemID = startItemID,
        costItemID = costItemID,
        tooltipTitle = label,
        tooltipLines = tooltipLines,
    }
end

local function preserveCompletedRows(rows, existing)
    local completedByKey = {}
    for _, row in ipairs(type(existing) == "table" and existing.rows or {}) do
        if type(row) == "table" and row.key and row.completed == true then
            completedByKey[row.key] = row
        end
    end
    for index, row in ipairs(rows) do
        if not row.completed and completedByKey[row.key] then
            rows[index] = completedByKey[row.key]
        end
    end
end

function Logic:BuildSnapshot(detectorState, existing)
    if type(detectorState) ~= "table" or detectorState.active ~= true or not QuestApi:IsAvailable() then
        return nil
    end
    local rows = {}
    for _, definition in ipairs(DATA.quests) do
        rows[#rows + 1] = buildRow(definition)
    end
    preserveCompletedRows(rows, existing)

    local completed, open = 0, 0
    for _, row in ipairs(rows) do
        if row.completed then
            completed = completed + 1
        elseif row.seen then
            open = open + 1
        end
    end
    local dailySeconds, dailyResetAt = Addon.WoWApi:GetDailyResetInfo()
    return {
        active = true,
        generatedAt = type(time) == "function" and time() or 0,
        dailyResetAt = dailyResetAt,
        faireResetKey = detectorState.resetKey,
        faireStartAt = detectorState.startAt,
        faireEndAt = detectorState.endAt,
        rows = rows,
        summary = {
            completed = completed,
            open = open,
            total = #rows,
            progressText = string.format("%d/%d", completed, #rows),
            dailyResetText = Addon.WoWApi:FormatDurationShort(dailySeconds),
        },
    }
end
