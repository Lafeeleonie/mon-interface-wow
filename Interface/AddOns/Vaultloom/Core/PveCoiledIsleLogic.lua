local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_COILED_ISLE

local Logic = {}
Addon.PveCoiledIsleLogic = Logic

local function visibleTaskQuests()
    local visible = {}
    for _, mapID in ipairs(DATA.mapIDs or {}) do
        for _, questID in ipairs(QuestApi:GetTaskQuestIDsOnMap(mapID)) do
            visible[questID] = true
        end
    end
    return visible
end

local function tooltipLines(definition, ready, active)
    local lines = active and QuestApi:GetObjectiveLines(definition.questID) or {}
    if #lines == 0 then
        local mapName = Addon.WoWApi:GetMapName(definition.mapID)
        if type(mapName) == "string" and mapName ~= "" then
            lines[1] = mapName
        elseif ready then
            lines[1] = L.PVE_WEEKLY_STATUS_TURNIN
        end
    end
    return lines
end

local function buildActivityRow(definition, visible)
    local questID = definition.questID
    local completed = QuestApi:IsCompleted(questID)
    local accepted = QuestApi:IsActive(questID)
    local taskActive = QuestApi:IsTaskActive(questID) or visible[questID] == true
    local available = not accepted and taskActive
    local ready = accepted and QuestApi:IsTurnInReady(questID)
    local title = QuestApi:GetTitle(questID, definition.fallbackName)
    local status = completed and "complete" or ready and "turnin" or accepted and "open" or "missing"
    local text = completed and L.PVE_WEEKLY_STATUS_DONE
        or ready and L.PVE_WEEKLY_STATUS_TURNIN
        or accepted and (QuestApi:GetObjectiveProgressText(questID) or L.PVE_WEEKLY_STATUS_OPEN)
        or L.PVE_WEEKLY_STATUS_MISSING
    return {
        key = definition.key,
        label = title,
        text = text,
        status = status,
        seen = completed or accepted or available,
        completed = completed,
        questID = questID,
        turnInQuestID = ready and questID or nil,
        resetType = definition.resetType,
        tooltipTitle = title,
        tooltipLines = tooltipLines(definition, ready, accepted),
    }
end

local function buildWorldBossRow(definition, memory)
    if type(definition) ~= "table" or type(Addon.RaidJournalLogic) ~= "table"
        or type(Addon.RaidJournalLogic.GetBossProgress) ~= "function"
    then
        return nil
    end
    local progress = Addon.RaidJournalLogic:GetBossProgress(definition)
    memory = type(memory) == "table" and memory or {}
    if progress.completed then memory.worldBossCompleted = true end
    local completed = progress.completed or memory.worldBossCompleted == true
    local name = type(progress.name) == "string" and progress.name ~= ""
        and progress.name or definition.fallbackName
    local difficultyName = definition.difficultyIDs and definition.difficultyIDs[1] or 172
    if type(GetDifficultyInfo) == "function" then
        local ok, localized = pcall(GetDifficultyInfo, difficultyName)
        if ok and type(localized) == "string" and localized ~= "" then difficultyName = localized end
    end
    if type(difficultyName) ~= "string" then difficultyName = "World" end
    local tooltip = {}
    if type(progress.description) == "string" and progress.description ~= "" then
        tooltip[#tooltip + 1] = progress.description
    end
    tooltip[#tooltip + 1] = string.format("%s+: %s", difficultyName, completed and "1/1" or "0/1")
    return {
        key = definition.key,
        label = name,
        text = (progress.available or completed) and (completed and "1/1" or "0/1") or "?",
        status = completed and "complete" or progress.available and "open" or "missing",
        seen = true,
        completed = completed,
        resetType = definition.resetType or "weekly",
        icon = progress.icon,
        encounterID = progress.journalEncounterID,
        tooltipTitle = name,
        tooltipLines = tooltip,
    }
end

local function refreshSummary(snapshot)
    local completed, total = 0, 0
    for _, row in ipairs(snapshot.rows or {}) do
        if row.counted ~= false then
            total = total + 1
            if row.completed or row.status == "complete" then completed = completed + 1 end
        end
    end
    snapshot.summary.completed = completed
    snapshot.summary.total = total
    snapshot.summary.progressText = string.format("%d/%d", completed, total)
end

function Logic:BuildSnapshot(existingSnapshot, memory)
    if not DATA.enabled or not QuestApi:IsAvailable() then return existingSnapshot end

    local dailySeconds, dailyResetAt = Addon.WoWApi:GetDailyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.dailyResetAt or nil
    )
    local weeklySeconds, weeklyResetAt = Addon.WoWApi:GetWeeklyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.weeklyResetAt or nil
    )

    local visible = visibleTaskQuests()
    local rows, dailyRows = {}, {}
    for _, definition in ipairs(DATA.activities or {}) do
        local row = buildActivityRow(definition, visible)
        if definition.resetType == "weekly" then
            rows[#rows + 1] = row
        elseif row.seen then
            dailyRows[#dailyRows + 1] = row
        end
    end
    local worldBossRow = buildWorldBossRow(DATA.worldBoss, memory)
    if worldBossRow then rows[#rows + 1] = worldBossRow end
    if #dailyRows == 0 then
        dailyRows[1] = {
            key = "daily_rotation",
            label = L.PVE_COILED_ISLE_SECTION_DAILY,
            text = L.PVE_WEEKLY_STATUS_MISSING,
            status = "missing",
            resetType = "daily",
            counted = false,
            tooltipTitle = L.PVE_COILED_ISLE_SECTION_DAILY,
            tooltipLines = {},
        }
    end
    for _, row in ipairs(dailyRows) do rows[#rows + 1] = row end

    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = dailyResetAt,
        dailyResetAt = dailyResetAt,
        weeklyResetAt = weeklyResetAt,
        factionID = DATA.factionID,
        rows = rows,
        summary = {
            dailyResetText = Addon.WoWApi:FormatDurationShort(dailySeconds),
            weeklyResetText = Addon.WoWApi:FormatDurationShort(weeklySeconds),
        },
    }
    refreshSummary(snapshot)
    return snapshot
end
