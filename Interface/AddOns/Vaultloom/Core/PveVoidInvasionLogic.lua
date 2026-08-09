local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_VOID_INVASION

local Logic = {}
Addon.PveVoidInvasionLogic = Logic
Logic.snapshotVersion = 3

local LABEL_KEYS = {
    showdown = "PVE_VOID_INVASION_SHOWDOWN_LABEL",
    disruption = "PVE_VOID_INVASION_DISRUPTION_LABEL",
    enemies = "PVE_VOID_INVASION_ENEMIES_LABEL",
    world_boss = "PVE_VOID_INVASION_WORLD_BOSS_LABEL",
}

local function inspectQuest(questID, isTask)
    if not questID then
        return nil
    end
    if QuestApi:IsCompleted(questID) then
        return "complete"
    end
    if QuestApi:IsActive(questID) then
        return "active"
    end
    if isTask and QuestApi:IsTaskActive(questID) then
        return "active"
    end
    return nil
end

local function getCurrentInstanceDifficulty()
    if type(GetInstanceInfo) ~= "function" or type(GetDifficultyInfo) ~= "function" then
        return nil
    end

    local ok, _, _, difficultyID = pcall(GetInstanceInfo)
    difficultyID = ok and tonumber(difficultyID) or nil
    if not difficultyID or difficultyID <= 0 then
        return nil
    end

    local infoOK, _, _, isHeroic, _, _, _, toggleDifficultyID = pcall(GetDifficultyInfo, difficultyID)
    if not infoOK then
        return nil
    end
    if isHeroic == true then
        return "heroic"
    end

    toggleDifficultyID = tonumber(toggleDifficultyID)
    if not toggleDifficultyID or toggleDifficultyID <= 0 then
        return nil
    end
    local toggleOK, _, _, toggleIsHeroic = pcall(GetDifficultyInfo, toggleDifficultyID)
    return toggleOK and toggleIsHeroic == true and "normal" or nil
end

local function inspectZone(zone, currentMapID, instanceDifficulty)
    local mapQuestIDs = {}
    for _, questID in ipairs(QuestApi:GetTaskQuestIDsOnMap(zone.mapID)) do
        mapQuestIDs[questID] = true
    end

    local evidence = {
        score = 0,
        difficulty = nil,
        difficultySource = nil,
        variants = {},
    }
    if currentMapID == zone.mapID and instanceDifficulty then
        evidence.score = 9
        evidence.difficulty = instanceDifficulty
        evidence.difficultySource = "instance"
    end

    local worldBoss = zone.rows.world_boss
    local mapDifficulty, mapDifficultyAmbiguous
    for _, difficulty in ipairs({ "normal", "heroic" }) do
        if mapQuestIDs[worldBoss[difficulty]] then
            if mapDifficulty and mapDifficulty ~= difficulty then
                mapDifficultyAmbiguous = true
            else
                mapDifficulty = difficulty
            end
        end
    end
    if evidence.difficultySource ~= "instance" and mapDifficulty and not mapDifficultyAmbiguous then
        evidence.score = math.max(evidence.score, 7)
        evidence.difficulty = mapDifficulty
        evidence.difficultySource = "map"
    end
    for _, rowKey in ipairs(DATA.rowOrder) do
        local definition = zone.rows[rowKey]
        local variants = {}
        for _, difficulty in ipairs({ "normal", "heroic" }) do
            local questID = definition[difficulty]
            local state = inspectQuest(questID, definition.task == true)
            variants[difficulty] = {
                questID = questID,
                state = state,
            }
            if state then
                local score = state == "active" and 4 or 2
                if definition.task then
                    score = score + 1
                end
                if evidence.difficultySource ~= "instance"
                    and evidence.difficultySource ~= "map"
                    and (score > evidence.score or (score == evidence.score and difficulty == "heroic"))
                then
                    evidence.score = score
                    evidence.difficulty = difficulty
                    evidence.difficultySource = state
                end
            end
        end
        evidence.variants[rowKey] = variants
    end
    return evidence
end

local function getCurrentMapID()
    local api = C_Map and C_Map.GetBestMapForUnit
    if type(api) ~= "function" then
        return nil
    end
    local ok, mapID = pcall(api, "player")
    return ok and tonumber(mapID) or nil
end

local function chooseZone(existingSnapshot)
    local selectedZone, selectedEvidence
    local currentMapID = getCurrentMapID()
    local instanceDifficulty = getCurrentInstanceDifficulty()
    for _, zone in ipairs(DATA.zones) do
        local evidence = inspectZone(zone, currentMapID, instanceDifficulty)
        if currentMapID == zone.mapID then
            evidence.score = math.max(evidence.score, 6)
        end
        if not selectedEvidence or evidence.score > selectedEvidence.score then
            selectedZone = zone
            selectedEvidence = evidence
        end
    end
    if selectedEvidence and selectedEvidence.score > 0 then
        return selectedZone, selectedEvidence
    end

    local existingKey = type(existingSnapshot) == "table" and existingSnapshot.zoneKey or nil
    for _, zone in ipairs(DATA.zones) do
        if zone.key == existingKey then
            return zone, inspectZone(zone, currentMapID, instanceDifficulty)
        end
    end
    return nil, nil
end

local function findExistingRow(existingSnapshot, rowKey, zoneKey, difficulty)
    if type(existingSnapshot) ~= "table"
        or existingSnapshot.zoneKey ~= zoneKey
    then
        return nil
    end

    local view = type(existingSnapshot.views) == "table" and existingSnapshot.views[difficulty] or nil
    local rows = type(view) == "table" and view.rows or nil
    if type(rows) ~= "table" and existingSnapshot.difficulty == difficulty then
        rows = existingSnapshot.rows
    end
    if type(rows) ~= "table" then
        return nil
    end

    for _, row in ipairs(rows) do
        if row.key == rowKey and row.difficulty == difficulty then
            return row
        end
    end
    return nil
end

local function chooseVariant(variants, selectedDifficulty)
    if selectedDifficulty == "normal" or selectedDifficulty == "heroic" then
        local variant = variants and variants[selectedDifficulty]
        if variant and variant.state then
            return variant, selectedDifficulty
        end
        return nil, selectedDifficulty
    end
    for _, difficulty in ipairs({ "heroic", "normal" }) do
        local variant = variants and variants[difficulty]
        if variant and variant.state == "active" then
            return variant, difficulty
        end
    end
    for _, difficulty in ipairs({ "heroic", "normal" }) do
        local variant = variants and variants[difficulty]
        if variant and variant.state == "complete" then
            return variant, difficulty
        end
    end
    return nil, nil
end

local function completedRow(rowKey, label, questID, title, difficulty)
    return {
        key = rowKey,
        label = label,
        text = L.PVE_WEEKLY_STATUS_DONE,
        status = "complete",
        seen = true,
        completed = true,
        questID = questID,
        difficulty = difficulty,
        tooltipTitle = title or label,
        tooltipLines = { L.PVE_VOID_INVASION_DONE_HINT },
    }
end

local function activeRow(rowKey, label, questID, title, difficulty, isTask)
    local ready = not isTask and QuestApi:IsTurnInReady(questID) or false
    local lines = QuestApi:GetObjectiveLines(questID)
    if #lines == 0 then
        lines[1] = isTask and L.PVE_VOID_INVASION_WORLD_BOSS_HINT
            or L.PVE_VOID_INVASION_ACTIVE_HINT
    end
    return {
        key = rowKey,
        label = label,
        text = ready and L.PVE_WEEKLY_STATUS_TURNIN
            or QuestApi:GetObjectiveProgressText(questID)
            or (isTask and L.PVE_VOID_INVASION_STATUS_AVAILABLE or L.PVE_WEEKLY_STATUS_OPEN),
        status = ready and "turnin" or "open",
        seen = true,
        completed = false,
        questID = questID,
        turnInQuestID = ready and questID or nil,
        difficulty = difficulty,
        tooltipTitle = title or label,
        tooltipLines = lines,
    }
end

local function unavailableRow(rowKey, label, locked, isTask)
    return {
        key = rowKey,
        label = label,
        text = locked and L.PVE_VOID_INVASION_STATUS_LOCKED
            or (isTask and L.PVE_VOID_INVASION_STATUS_AVAILABLE or L.PVE_WEEKLY_STATUS_MISSING),
        status = locked and "locked" or "missing",
        seen = false,
        completed = false,
        tooltipTitle = label,
        tooltipLines = {
            locked and L.PVE_VOID_INVASION_LOCKED_HINT
                or (isTask and L.PVE_VOID_INVASION_WORLD_BOSS_HINT or L.PVE_VOID_INVASION_ACCEPT_HINT),
        },
    }
end

local function buildRow(zone, evidence, rowKey, difficulty, locked, existingSnapshot)
    local label = L[LABEL_KEYS[rowKey]] or rowKey
    local definition = zone and zone.rows[rowKey] or nil
    local variant, selectedDifficulty = chooseVariant(
        evidence and evidence.variants[rowKey],
        difficulty
    )
    local existing = findExistingRow(
        existingSnapshot,
        rowKey,
        zone and zone.key,
        difficulty
    )

    if locked then
        return unavailableRow(rowKey, label, true, definition and definition.task == true)
    end

    if variant and variant.state == "complete" then
        local title = QuestApi:GetTitle(variant.questID, label)
        return completedRow(rowKey, label, variant.questID, title, selectedDifficulty)
    end
    if variant and variant.state == "active" then
        local title = QuestApi:GetTitle(variant.questID, label)
        return activeRow(
            rowKey,
            label,
            variant.questID,
            title,
            selectedDifficulty,
            definition.task == true
        )
    end
    if existing and existing.status == "complete" then
        return existing
    end
    return unavailableRow(rowKey, label, locked, definition and definition.task == true)
end

local function inferShowdownCompletion(evidence, existingSnapshot, zoneKey, difficulty)
    local showdown = chooseVariant(evidence and evidence.variants.showdown, difficulty)
    if showdown and showdown.state == "complete" then
        return true
    end
    for _, rowKey in ipairs({ "disruption", "enemies" }) do
        local variant = chooseVariant(evidence and evidence.variants[rowKey], difficulty)
        if variant and variant.state then
            return true
        end
    end
    local existing = findExistingRow(existingSnapshot, "showdown", zoneKey, difficulty)
    return existing and existing.status == "complete" or false
end

local function preserveInferredShowdown(row, evidence, existingSnapshot, zone, difficulty)
    if row.status == "complete"
        or not inferShowdownCompletion(evidence, existingSnapshot, zone.key, difficulty)
    then
        return row
    end
    local variants = evidence and evidence.variants.showdown
    local variant, selectedDifficulty = chooseVariant(variants, difficulty)
    local questID = variant and variant.questID or nil
    return completedRow(
        "showdown",
        L.PVE_VOID_INVASION_SHOWDOWN_LABEL,
        questID,
        questID and QuestApi:GetTitle(questID, L.PVE_VOID_INVASION_SHOWDOWN_LABEL) or nil,
        selectedDifficulty or difficulty
    )
end

local function buildRows(zone, evidence, difficulty, existingSnapshot)
    if not zone then
        return {
            unavailableRow("showdown", L.PVE_VOID_INVASION_SHOWDOWN_LABEL, false, false),
            unavailableRow("disruption", L.PVE_VOID_INVASION_DISRUPTION_LABEL, true, false),
            unavailableRow("enemies", L.PVE_VOID_INVASION_ENEMIES_LABEL, true, false),
            unavailableRow("world_boss", L.PVE_VOID_INVASION_WORLD_BOSS_LABEL, false, true),
        }
    end

    local rows = {}
    local showdown = buildRow(zone, evidence, "showdown", difficulty, false, existingSnapshot)
    showdown = preserveInferredShowdown(showdown, evidence, existingSnapshot, zone, difficulty)
    rows[1] = showdown
    local followupsLocked = showdown.status ~= "complete"
    rows[2] = buildRow(zone, evidence, "disruption", difficulty, followupsLocked, existingSnapshot)
    rows[3] = buildRow(zone, evidence, "enemies", difficulty, followupsLocked, existingSnapshot)
    rows[4] = buildRow(zone, evidence, "world_boss", difficulty, false, existingSnapshot)
    return rows
end

local function buildSummary(rows, resetText)
    local completed = 0
    for _, row in ipairs(rows) do
        if row.status == "complete" or row.completed == true then
            completed = completed + 1
        end
    end
    return {
        completed = completed,
        total = #rows,
        progressText = string.format("%d/%d", completed, #rows),
        resetText = resetText,
    }
end

function Logic:BuildSnapshot(existingSnapshot)
    if type(existingSnapshot) == "table"
        and tonumber(existingSnapshot.version) ~= Logic.snapshotVersion
    then
        existingSnapshot = nil
    end
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end

    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    if type(existingSnapshot) == "table" and tonumber(existingSnapshot.resetAt) ~= tonumber(resetAt) then
        existingSnapshot = nil
    end

    local zone, evidence = chooseZone(existingSnapshot)
    local difficulty = evidence and evidence.difficulty or nil
    if type(existingSnapshot) == "table"
        and zone
        and existingSnapshot.zoneKey == zone.key
        and evidence
        and evidence.difficultySource == "complete"
        and (existingSnapshot.autoDifficulty == "normal" or existingSnapshot.autoDifficulty == "heroic"
            or existingSnapshot.difficulty == "normal" or existingSnapshot.difficulty == "heroic")
    then
        difficulty = existingSnapshot.autoDifficulty or existingSnapshot.difficulty
    end
    if difficulty ~= "heroic" then difficulty = "normal" end

    local resetText = Addon.WoWApi:FormatDurationShort(secondsUntilReset)
    local views = {}
    for _, viewDifficulty in ipairs({ "normal", "heroic" }) do
        local viewRows = buildRows(zone, evidence, viewDifficulty, existingSnapshot)
        views[viewDifficulty] = {
            difficulty = viewDifficulty,
            rows = viewRows,
            summary = buildSummary(viewRows, resetText),
        }
    end
    local selectedView = views[difficulty]

    return {
        version = Logic.snapshotVersion,
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        zoneKey = zone and zone.key or nil,
        zoneName = zone and zone.name or nil,
        autoDifficulty = difficulty,
        difficulty = difficulty,
        rows = selectedView.rows,
        summary = selectedView.summary,
        views = views,
    }
end
