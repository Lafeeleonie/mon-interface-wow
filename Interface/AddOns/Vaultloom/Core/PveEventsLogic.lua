local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_EVENTS

local Logic = {}
Addon.PveEventsLogic = Logic

local function call(api, ...)
    if type(api) ~= "function" then
        return false
    end
    return pcall(api, ...)
end

local function completedRow(key, label, questID, title)
    return {
        key = key,
        label = label,
        text = L.PVE_EVENTS_STATUS_DONE,
        status = "complete",
        seen = true,
        completed = true,
        questID = questID,
        tooltipTitle = title or label,
        tooltipLines = { L.PVE_EVENTS_DONE_HINT },
    }
end

local function activeRow(key, label, questID, title, turnInText)
    local ready = QuestApi:IsTurnInReady(questID)
    local lines = QuestApi:GetObjectiveLines(questID)
    if #lines == 0 then
        lines[1] = ready and L.PVE_EVENTS_TURNIN_HINT or L.PVE_EVENTS_ACTIVE_HINT
    end
    return {
        key = key,
        label = label,
        text = ready and (turnInText or L.PVE_EVENTS_STATUS_TURNIN)
            or QuestApi:GetObjectiveProgressText(questID)
            or L.PVE_EVENTS_STATUS_OPEN,
        status = ready and "turnin" or "open",
        seen = true,
        completed = false,
        questID = questID,
        turnInQuestID = ready and questID or nil,
        tooltipTitle = title and title ~= label and string.format("%s - %s", label, title) or label,
        tooltipLines = lines,
    }
end

local function buildQuestPoolRow(config)
    local activeQuestID, completedQuestID
    for _, questID in ipairs(config.questPool or {}) do
        if QuestApi:IsCompleted(questID) then
            completedQuestID = questID
            break
        elseif not activeQuestID and QuestApi:IsActive(questID) then
            activeQuestID = questID
        end
    end
    if completedQuestID then
        return completedRow(config.key, config.label, completedQuestID, QuestApi:GetTitle(completedQuestID, config.label))
    end
    if activeQuestID then
        return activeRow(config.key, config.label, activeQuestID, QuestApi:GetTitle(activeQuestID, config.label))
    end
    local firstQuestID = config.questPool and config.questPool[1] or nil
    return {
        key = config.key,
        label = config.label,
        text = L.PVE_EVENTS_STATUS_MISSING,
        status = "missing",
        seen = false,
        completed = false,
        questID = firstQuestID,
        tooltipTitle = config.label,
        tooltipLines = { config.acceptHint },
    }
end

local function taskQuestVisible(questID, mapIDs)
    for _, mapID in ipairs(mapIDs or {}) do
        for _, visibleQuestID in ipairs(QuestApi:GetTaskQuestIDsOnMap(mapID)) do
            if visibleQuestID == questID then
                return true, mapID
            end
        end
    end
    return false
end

local function getAbundanceLocation()
    local definition = DATA.abundantOfferings
    if not (C_AreaPoiInfo and type(C_AreaPoiInfo.GetEventsForMap) == "function"
        and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function") then
        return nil
    end
    local ok, poiIDs = call(C_AreaPoiInfo.GetEventsForMap, definition.continentMapID)
    if not ok or type(poiIDs) ~= "table" then
        return nil
    end
    for _, rawPoiID in ipairs(poiIDs) do
        local poiID = tonumber(rawPoiID)
        local mapID = poiID and definition.poiMap[poiID] or nil
        if mapID then
            local infoOk, info = call(C_AreaPoiInfo.GetAreaPOIInfo, definition.continentMapID, poiID)
            local poiName = infoOk and type(info) == "table" and tostring(info.name or "") or ""
            local mapName = Addon.WoWApi:GetMapName(mapID) or ""
            if mapName ~= "" and poiName ~= "" then
                return string.format("%s - %s", mapName, poiName)
            end
            if mapName ~= "" then
                return mapName
            end
            if poiName ~= "" then
                return poiName
            end
        end
    end
    return nil
end

local function buildEventAvailabilityRow(config)
    local row = buildQuestPoolRow(config)
    if row.status ~= "missing" then
        return row
    end
    local availability = type(config.getAvailability) == "function" and config.getAvailability() or nil
    local visible, visibleMapID, visibleQuestID = false, nil, nil
    if not availability then
        for _, questID in ipairs(config.questPool or {}) do
            visible, visibleMapID = taskQuestVisible(questID, config.mapIDs)
            if visible then
                visibleQuestID = questID
                break
            end
        end
        if visibleQuestID then
            availability = QuestApi:GetTitle(visibleQuestID, config.label)
            local mapName = Addon.WoWApi:GetMapName(visibleMapID)
            if mapName and mapName ~= "" then
                availability = string.format("%s - %s", mapName, availability)
            end
        end
    end
    local lines = { config.acceptHint }
    if availability then
        lines[#lines + 1] = string.format(L.PVE_EVENTS_AVAILABLE_HINT, availability)
    elseif config.metaQuestID and QuestApi:IsActive(config.metaQuestID) then
        lines[#lines + 1] = L.PVE_EVENTS_WEEKLY_ACTIVE_HINT
    end
    row.tooltipLines = lines
    row.seen = availability ~= nil or visible or (config.metaQuestID and QuestApi:IsActive(config.metaQuestID)) or false
    return row
end

local function buildCourtFavorRow(memory)
    local questID = DATA.courtFavorQuestID
    local row = buildQuestPoolRow({
        key = "court_favor",
        label = L.PVE_EVENTS_COURT_LABEL,
        questPool = { questID },
        acceptHint = L.PVE_EVENTS_COURT_ACCEPT_HINT,
    })
    local accountCompleted = QuestApi:IsCompletedOnAccount(questID)
        or (type(memory) == "table" and memory.courtFavorCompleted == true)
    if row.status == "complete" or accountCompleted then
        if type(memory) == "table" then
            memory.courtFavorCompleted = true
            memory.courtFavorQuestID = questID
        end
        row = completedRow("court_favor", L.PVE_EVENTS_COURT_LABEL, questID, L.PVE_EVENTS_COURT_LABEL)
    end
    row.accountWide = true
    return row
end

local function buildRunestoneRow()
    return buildQuestPoolRow({
        key = "runestones",
        label = L.PVE_EVENTS_RUNESTONES_LABEL,
        questPool = DATA.runestoneQuestPool,
        acceptHint = L.PVE_EVENTS_RUNESTONES_ACCEPT_HINT,
    })
end

local function buildSaltherilsFavorRow()
    local count = Addon.WoWApi:GetItemCount(DATA.saltherilsFavorItemID)
    return {
        key = "saltherils_favor",
        label = L.PVE_EVENTS_SALTHERILS_FAVOR_LABEL,
        text = tostring(count),
        status = count > 0 and "open" or "missing",
        seen = count > 0,
        completed = false,
        itemID = DATA.saltherilsFavorItemID,
        tooltipTitle = L.PVE_EVENTS_SALTHERILS_FAVOR_LABEL,
        tooltipLines = {
            L.PVE_EVENTS_SALTHERILS_FAVOR_HINT,
            string.format(L.PVE_EVENTS_SALTHERILS_FAVOR_COUNT, count),
        },
    }
end

local function buildAbundantOfferingsRow()
    local definition = DATA.abundantOfferings
    return buildEventAvailabilityRow({
        key = "abundant_offerings",
        label = L.PVE_EVENTS_ABUNDANT_LABEL,
        questPool = { definition.questID },
        metaQuestID = definition.metaQuestID,
        acceptHint = L.PVE_EVENTS_ABUNDANT_ACCEPT_HINT,
        getAvailability = getAbundanceLocation,
    })
end

local function buildLostLegendsRow()
    local definition = DATA.lostLegends
    local label = L.PVE_EVENTS_LOST_LEGENDS_LABEL
    for _, questID in ipairs(definition.repeatableQuestPool) do
        if QuestApi:IsCompleted(questID) then
            return completedRow("lost_legends", label, questID, QuestApi:GetTitle(questID, label))
        end
    end
    for _, questID in ipairs(definition.repeatableQuestPool) do
        if QuestApi:IsActive(questID) then
            return activeRow("lost_legends", label, questID, QuestApi:GetTitle(questID, label))
        end
    end
    if QuestApi:IsActive(definition.relicQuestID) then
        local row = activeRow(
            "lost_legends",
            label,
            definition.relicQuestID,
            QuestApi:GetTitle(definition.relicQuestID, label),
            L.PVE_EVENTS_LOST_LEGENDS_CHOOSE
        )
        if row.status == "turnin" then
            row.tooltipLines[#row.tooltipLines + 1] = L.PVE_EVENTS_LOST_LEGENDS_RELIC_HINT
        end
        return row
    end
    if QuestApi:IsCompleted(definition.relicQuestID) then
        return {
            key = "lost_legends",
            label = label,
            text = L.PVE_EVENTS_LOST_LEGENDS_CHOOSE,
            status = "turnin",
            seen = true,
            completed = false,
            questID = definition.relicQuestID,
            turnInQuestID = definition.relicQuestID,
            tooltipTitle = label,
            tooltipLines = { L.PVE_EVENTS_LOST_LEGENDS_RELIC_HINT },
        }
    end
    if QuestApi:IsActive(definition.questID) then
        return activeRow("lost_legends", label, definition.questID, QuestApi:GetTitle(definition.questID, label))
    end

    local visibleQuestIDs = { definition.relicQuestID, definition.questID }
    for _, questID in ipairs(definition.repeatableQuestPool) do
        visibleQuestIDs[#visibleQuestIDs + 1] = questID
    end
    local availability
    for _, questID in ipairs(visibleQuestIDs) do
        local visible = taskQuestVisible(questID, definition.mapIDs)
        if visible then
            availability = QuestApi:GetTitle(questID, label)
            break
        end
    end
    local lines = { L.PVE_EVENTS_LOST_LEGENDS_ACCEPT_HINT }
    if availability then
        lines[#lines + 1] = string.format(L.PVE_EVENTS_AVAILABLE_HINT, availability)
    elseif QuestApi:IsActive(definition.metaQuestID) then
        lines[#lines + 1] = L.PVE_EVENTS_WEEKLY_ACTIVE_HINT
    end
    return {
        key = "lost_legends",
        label = label,
        text = L.PVE_EVENTS_STATUS_MISSING,
        status = "missing",
        seen = availability ~= nil or QuestApi:IsActive(definition.metaQuestID),
        completed = false,
        tooltipTitle = label,
        tooltipLines = lines,
    }
end

local function buildStormarionRow()
    local definition = DATA.stormarionAssault
    return buildEventAvailabilityRow({
        key = "stormarion_assault",
        label = L.PVE_EVENTS_STORMARION_LABEL,
        questPool = { definition.questID },
        metaQuestID = definition.metaQuestID,
        mapIDs = definition.mapIDs,
        acceptHint = L.PVE_EVENTS_STORMARION_ACCEPT_HINT,
    })
end

local function buildVoidAssaultRow()
    return buildEventAvailabilityRow({
        key = "void_assaults",
        label = L.PVE_EVENTS_VOID_ASSAULTS_LABEL,
        questPool = DATA.voidAssaultQuestPool,
        acceptHint = L.PVE_EVENTS_VOID_ASSAULTS_ACCEPT_HINT,
    })
end

function Logic:BuildSnapshot(memory, existingSnapshot)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end
    memory = type(memory) == "table" and memory or {}
    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.resetAt or nil
    )
    local rows = {
        buildCourtFavorRow(memory),
        buildRunestoneRow(),
        buildSaltherilsFavorRow(),
        buildAbundantOfferingsRow(),
        buildLostLegendsRow(),
        buildStormarionRow(),
        buildVoidAssaultRow(),
    }
    local completed = 0
    for _, row in ipairs(rows) do
        if row.completed or row.status == "complete" then
            completed = completed + 1
        end
    end
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
