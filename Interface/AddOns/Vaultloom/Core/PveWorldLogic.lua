local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_WORLD

local Logic = {}
Addon.PveWorldLogic = Logic

local function worldBossDefinitions()
    if type(DATA.worldBosses) == "table" and #DATA.worldBosses > 0 then
        return DATA.worldBosses
    end
    local definitions = {}
    for index, questID in ipairs(DATA.worldBossQuestIDs or {}) do
        definitions[#definitions + 1] = {
            key = "world-boss-" .. tostring(questID),
            questID = questID,
            contentType = "world_boss",
            namePatterns = { DATA.worldBossNamePatterns and DATA.worldBossNamePatterns[index] },
        }
    end
    return definitions
end

local function findWorldBossByQuestID(questID)
    for _, definition in ipairs(worldBossDefinitions()) do
        if tonumber(definition.questID) == tonumber(questID) then return definition end
    end
    return nil
end

local function findWorldBossByName(name)
    name = type(name) == "string" and string.lower(name) or ""
    for _, definition in ipairs(worldBossDefinitions()) do
        for _, pattern in ipairs(definition.namePatterns or {}) do
            pattern = type(pattern) == "string" and string.lower(pattern) or ""
            if pattern ~= "" and string.find(name, pattern, 1, true) then
                return definition
            end
        end
    end
    return nil
end

local function getSavedWorldBoss()
    if type(GetNumSavedWorldBosses) ~= "function" or type(GetSavedWorldBossInfo) ~= "function" then
        return nil
    end
    local ok, count = pcall(GetNumSavedWorldBosses)
    count = ok and math.max(0, tonumber(count) or 0) or 0
    for index = 1, count do
        local infoOk, name = pcall(GetSavedWorldBossInfo, index)
        local definition = infoOk and findWorldBossByName(name) or nil
        if definition then
            return name, definition
        end
    end
    return nil
end

local function buildWorldBossIdentity(definition, questID, savedBossName)
    if type(definition) ~= "table" then
        return L.PVE_WORLD_ROW_WORLD_BOSS, nil, nil
    end
    local bossName = savedBossName or (questID and QuestApi:GetTitle(questID, definition.fallbackName))
        or definition.fallbackName
    local zoneName = definition.mapID and Addon.WoWApi:GetMapName(definition.mapID)
        or definition.fallbackZoneName
    if type(zoneName) ~= "string" or zoneName == "" then zoneName = definition.fallbackZoneName end
    if type(bossName) ~= "string" or bossName == "" then bossName = definition.fallbackName end
    local label = bossName
    if type(bossName) == "string" and bossName ~= "" and type(zoneName) == "string" and zoneName ~= "" then
        label = string.format(L.PVE_WORLD_BOSS_LABEL_FORMAT, bossName, zoneName)
    end
    return label or L.PVE_WORLD_ROW_WORLD_BOSS, bossName, zoneName
end

local function buildWorldBossRow()
    local completedQuestID, activeQuestID
    for _, definition in ipairs(worldBossDefinitions()) do
        local questID = definition.questID
        if QuestApi:IsCompleted(questID) then
            completedQuestID = questID
            break
        end
        if not activeQuestID and QuestApi:IsActive(questID) then
            activeQuestID = questID
        end
    end
    local savedBossName, savedDefinition
    if not completedQuestID then savedBossName, savedDefinition = getSavedWorldBoss() end
    if completedQuestID or savedBossName then
        local definition = findWorldBossByQuestID(completedQuestID) or savedDefinition
        local label, bossName, zoneName = buildWorldBossIdentity(
            definition,
            completedQuestID,
            savedBossName
        )
        return {
            key = "world_boss_weekly",
            label = label,
            text = L.PVE_WORLD_STATUS_DONE,
            status = "complete",
            seen = true,
            completed = true,
            questID = completedQuestID,
            contentType = definition and definition.contentType or "world_boss",
            contentKey = definition and definition.key or nil,
            bossName = bossName,
            zoneName = zoneName,
            zoneMapID = definition and definition.mapID or nil,
            tooltipTitle = label,
            tooltipLines = { L.PVE_WORLD_BOSS_DONE_HINT },
        }
    end

    local definition = findWorldBossByQuestID(activeQuestID)
    local label, bossName, zoneName = buildWorldBossIdentity(definition, activeQuestID)
    local ready = activeQuestID and QuestApi:IsTurnInReady(activeQuestID) or false
    local tooltipLines = activeQuestID and QuestApi:GetObjectiveLines(activeQuestID) or {}
    if #tooltipLines == 0 then
        tooltipLines[1] = L.PVE_WORLD_BOSS_HINT
    end
    return {
        key = "world_boss_weekly",
        label = label,
        text = ready and L.PVE_WORLD_STATUS_TURNIN
            or (activeQuestID and QuestApi:GetObjectiveProgressText(activeQuestID) or nil)
            or L.PVE_WORLD_STATUS_OPEN,
        status = ready and "turnin" or "open",
        seen = activeQuestID ~= nil,
        completed = false,
        questID = activeQuestID,
        turnInQuestID = ready and activeQuestID or nil,
        contentType = definition and definition.contentType or "world_boss",
        contentKey = definition and definition.key or nil,
        bossName = bossName,
        zoneName = zoneName,
        zoneMapID = definition and definition.mapID or nil,
        tooltipTitle = label,
        tooltipLines = tooltipLines,
    }
end

local function buildSpecialAssignmentsRow()
    local completedCount, activeCount = 0, 0
    local activeQuestIDs, availableTitles = {}, {}
    for _, definition in ipairs(DATA.specialAssignments) do
        if QuestApi:IsCompleted(definition.questID) then
            completedCount = completedCount + 1
        elseif QuestApi:IsActive(definition.questID) or QuestApi:IsCompleted(definition.unlockQuestID) then
            activeCount = activeCount + 1
            activeQuestIDs[#activeQuestIDs + 1] = QuestApi:IsActive(definition.questID) and definition.questID or nil
            availableTitles[#availableTitles + 1] = QuestApi:GetTitle(
                definition.questID,
                string.format(L.PVE_WORLD_QUEST_FALLBACK, definition.questID)
            )
        end
    end

    local count, maximum = math.min(2, completedCount), 2
    local completed = count >= maximum
    local seen = completed or count > 0 or activeCount > 0
    local tooltipLines = {
        completed and L.PVE_WORLD_SPECIAL_ASSIGNMENTS_DONE_HINT or L.PVE_WORLD_SPECIAL_ASSIGNMENTS_HINT,
    }
    if not completed and #availableTitles > 0 then
        tooltipLines[#tooltipLines + 1] = string.format(
            L.PVE_WORLD_SPECIAL_ASSIGNMENTS_AVAILABLE,
            table.concat(availableTitles, ", ")
        )
    end
    for _, questID in ipairs(activeQuestIDs) do
        for _, line in ipairs(QuestApi:GetObjectiveLines(questID)) do
            tooltipLines[#tooltipLines + 1] = line
        end
    end
    return {
        key = "special_assignments",
        label = L.PVE_WORLD_ROW_SPECIAL_ASSIGNMENTS,
        text = string.format("%d/%d", count, maximum),
        status = completed and "complete" or (seen and "open" or "missing"),
        seen = seen,
        completed = completed,
        count = count,
        maxCount = maximum,
        questID = activeQuestIDs[1],
        tooltipTitle = L.PVE_WORLD_ROW_SPECIAL_ASSIGNMENTS,
        tooltipLines = tooltipLines,
    }
end

local function buildCurrencyState(currencyIDs, fallbackName, fallbackMaximum, tooltipHint)
    local best
    for _, currencyID in ipairs(currencyIDs) do
        local info = Addon.WoWApi:GetCurrencyInfo(currencyID)
        if info then
            local currentQuantity = math.max(0, tonumber(info.quantity) or 0)
            local quantity = tonumber(info.quantityEarnedThisWeek)
            local maximum = tonumber(info.maxWeeklyQuantity)
            if info.useTotalEarnedForMaxQty and (tonumber(info.maxQuantity) or 0) > 0 then
                quantity = tonumber(info.totalEarned) or currentQuantity
                maximum = tonumber(info.maxQuantity) or fallbackMaximum
            else
                quantity = quantity or currentQuantity
                if not maximum or maximum <= 0 then
                    maximum = tonumber(info.maxQuantity) or fallbackMaximum
                end
            end
            local candidate = {
                currencyID = currencyID,
                name = info.name or fallbackName,
                quantity = math.max(0, tonumber(quantity) or 0),
                maxQuantity = math.max(0, tonumber(maximum) or fallbackMaximum),
                currentQuantity = currentQuantity,
            }
            if not best
                or candidate.maxQuantity > best.maxQuantity
                or (candidate.maxQuantity == best.maxQuantity and candidate.quantity > best.quantity)
            then
                best = candidate
            end
        end
    end
    best = best or {
        currencyID = currencyIDs[1],
        name = fallbackName,
        quantity = 0,
        maxQuantity = fallbackMaximum,
        currentQuantity = 0,
    }
    best.capped = best.maxQuantity > 0 and best.quantity >= best.maxQuantity
    best.text = best.maxQuantity > 0 and string.format("%d/%d", best.quantity, best.maxQuantity)
        or tostring(best.quantity)
    best.tooltipTitle = best.name
    best.tooltipLines = {
        tooltipHint,
        string.format(L.PVE_WORLD_CURRENCY_OWNED, best.currentQuantity),
    }
    return best
end

local function buildCurrencyRow(key, label, state)
    return {
        key = key,
        label = label,
        text = state.text,
        status = state.capped and "complete" or "open",
        seen = true,
        completed = state.capped,
        count = state.quantity,
        maxCount = state.maxQuantity,
        quantity = state.quantity,
        maxQuantity = state.maxQuantity,
        currentQuantity = state.currentQuantity,
        currencyID = state.currencyID,
        tooltipTitle = state.tooltipTitle or label,
        tooltipLines = state.tooltipLines,
    }
end

local function mergeRows(rows, existingSnapshot)
    local oldByKey = {}
    for _, row in ipairs(type(existingSnapshot) == "table" and existingSnapshot.rows or {}) do
        if type(row) == "table" and row.key then
            oldByKey[row.key] = row
        end
    end
    for index, row in ipairs(rows) do
        local old = oldByKey[row.key]
        if type(old) == "table" then
            if row.key == "world_boss_weekly" and old.completed == true and row.completed ~= true then
                old.label = row.label or old.label
                old.contentType = row.contentType or old.contentType
                old.contentKey = row.contentKey or old.contentKey
                old.bossName = row.bossName or old.bossName
                old.zoneName = row.zoneName or old.zoneName
                old.zoneMapID = row.zoneMapID or old.zoneMapID
                rows[index] = old
            elseif row.key == "special_assignments" then
                row.count = math.max(tonumber(row.count) or 0, tonumber(old.count) or 0)
                row.completed = row.count >= row.maxCount
                row.status = row.completed and "complete" or row.status
                row.seen = row.seen or row.count > 0
                row.text = string.format("%d/%d", row.count, row.maxCount)
            elseif row.currencyID then
                row.quantity = math.max(tonumber(row.quantity) or 0, tonumber(old.quantity) or 0)
                row.count = row.quantity
                row.completed = row.maxQuantity > 0 and row.quantity >= row.maxQuantity
                row.status = row.completed and "complete" or "open"
                row.text = row.maxQuantity > 0 and string.format("%d/%d", row.quantity, row.maxQuantity)
                    or tostring(row.quantity)
            end
        end
    end
end

function Logic:BuildSnapshot(existingSnapshot)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end
    local keyState = buildCurrencyState(
        DATA.keyShardCurrencyIDs,
        L.PVE_WORLD_ROW_KEY_SHARDS,
        DATA.keyShardCap,
        L.PVE_WORLD_KEY_SHARDS_HINT
    )
    local dundunState = buildCurrencyState(
        DATA.dundunCurrencyIDs,
        L.PVE_WORLD_ROW_DUNDUN_SHARDS,
        DATA.dundunCap,
        L.PVE_WORLD_DUNDUN_HINT
    )
    local rows = {
        buildWorldBossRow(),
        buildSpecialAssignmentsRow(),
        buildCurrencyRow("world_key_shards", L.PVE_WORLD_ROW_KEY_SHARDS, keyState),
        buildCurrencyRow("world_dundun_shards", L.PVE_WORLD_ROW_DUNDUN_SHARDS, dundunState),
    }
    mergeRows(rows, existingSnapshot)
    local completed = 0
    for _, row in ipairs(rows) do
        if row.completed or row.status == "complete" then
            completed = completed + 1
        end
    end
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.resetAt or nil
    )
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
