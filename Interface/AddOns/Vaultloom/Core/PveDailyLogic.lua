local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DEFINITIONS = Addon.Data.PVE_DAILY
local BOUNTIFUL = DEFINITIONS.bountiful
local unpackArgs = unpack or table.unpack

local Logic = {}
Addon.PveDailyLogic = Logic

local function call(api, ...)
    if type(api) ~= "function" then
        return false
    end
    return pcall(api, ...)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function containsBountifulText(info)
    if type(info) ~= "table" then
        return false
    end
    local text = string.lower(table.concat({
        tostring(info.atlasName or info.atlas or ""),
        tostring(info.textureKit or ""),
        tostring(info.label or info.name or ""),
        tostring(info.description or ""),
    }, " "))
    for _, needle in ipairs({ "delves-bountiful", "bountiful", "großzügig", "grosszuegig", "grosszugig" }) do
        if text:find(needle, 1, true) then
            return true
        end
    end
    return false
end

local function gatherDelveMapIDs()
    local mapIDs, seen = {}, {}
    local function add(mapID)
        mapID = tonumber(mapID)
        if mapID and mapID > 0 and not seen[mapID] then
            seen[mapID] = true
            mapIDs[#mapIDs + 1] = mapID
        end
    end

    local ok, bestMapID = call(C_Map and C_Map.GetBestMapForUnit, "player")
    if ok then
        add(bestMapID)
    end
    if bestMapID and C_Map and type(C_Map.GetMapInfo) == "function" then
        local cursor, safety = bestMapID, 0
        while cursor and safety < 12 do
            local infoOk, info = call(C_Map.GetMapInfo, cursor)
            local parentMapID = infoOk and type(info) == "table" and tonumber(info.parentMapID) or nil
            if not parentMapID or parentMapID <= 0 then
                break
            end
            add(parentMapID)
            cursor = parentMapID
            safety = safety + 1
        end
    end

    if C_Map and type(C_Map.GetMapChildrenInfo) == "function" then
        local parents = {}
        for index, mapID in ipairs(mapIDs) do
            parents[index] = mapID
        end
        local mapTypes = Enum and Enum.UIMapType and {
            Enum.UIMapType.Continent,
            Enum.UIMapType.Zone,
        } or nil
        for _, mapID in ipairs(parents) do
            if mapTypes then
                for _, mapType in ipairs(mapTypes) do
                    local childrenOk, children = call(C_Map.GetMapChildrenInfo, mapID, mapType)
                    if childrenOk and type(children) == "table" then
                        for _, child in ipairs(children) do
                            add(type(child) == "table" and child.mapID or child)
                        end
                    end
                end
            else
                local childrenOk, children = call(C_Map.GetMapChildrenInfo, mapID)
                if childrenOk and type(children) == "table" then
                    for _, child in ipairs(children) do
                        add(type(child) == "table" and child.mapID or child)
                    end
                end
            end
        end
    end
    return mapIDs
end

local function mergedDelveMapIDs(includeSafety)
    local result, seen = {}, {}
    local function addAll(source)
        for _, mapID in ipairs(source or {}) do
            mapID = tonumber(mapID)
            if mapID and mapID > 0 and not seen[mapID] then
                seen[mapID] = true
                result[#result + 1] = mapID
            end
        end
    end
    addAll(BOUNTIFUL.knownDelveMapIDs)
    addAll(gatherDelveMapIDs())
    if includeSafety then
        addAll(BOUNTIFUL.safetyMapIDs)
    end
    return result
end

local function countBountifulTable(result)
    if type(result) ~= "table" then
        return nil
    end
    local total, remaining = 0, 0
    for _, entry in ipairs(result) do
        if type(entry) == "table" and (entry.isBountiful or entry.bountiful or entry.isBountifulDelve or containsBountifulText(entry)) then
            total = total + 1
            local completed = entry.completed or entry.isCompleted or entry.wasCompletedToday
            local available = entry.isActive or entry.active or entry.available ~= false
            if not completed and available then
                remaining = remaining + 1
            end
        end
    end
    if total <= 0 then
        return nil
    end
    if remaining <= 0 and total <= BOUNTIFUL.cap then
        remaining = total
    end
    return clamp(remaining, 0, BOUNTIFUL.cap)
end

local function knownPoiRemaining()
    if not (C_AreaPoiInfo and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function") then
        return nil
    end
    local scanned, active = 0, 0
    for _, entry in ipairs(BOUNTIFUL.knownPois) do
        local ok, info = call(C_AreaPoiInfo.GetAreaPOIInfo, entry.mapID, entry.poiID)
        if ok and type(info) == "table" then
            scanned = scanned + 1
            if info.atlasName == "delves-bountiful" then
                active = active + 1
            end
        end
    end
    if scanned <= 0 then
        return nil
    end
    return clamp(active, 0, BOUNTIFUL.cap), "known-midnight-poi"
end

local function tableApiRemaining()
    local candidates = {
        { C_DelvesUI, "GetBountifulDelvesForMap" },
        { C_DelvesUI, "GetBountifulDelvesForMapID" },
        { C_DelvesUI, "GetDelvesForMap" },
        { C_DelvesUI, "GetDelvesForMapID" },
        { C_DelvesUI, "GetDelvesForUiMapID" },
        { C_Delves, "GetBountifulDelvesForMap" },
        { C_Delves, "GetBountifulDelvesForMapID" },
        { C_Delves, "GetDelvesForMap" },
        { C_Delves, "GetDelvesForMapID" },
        { C_Delves, "GetDelvesForUiMapID" },
    }
    local argumentSets = { {}, { true }, { false } }
    for _, mapID in ipairs(gatherDelveMapIDs()) do
        argumentSets[#argumentSets + 1] = { mapID }
        argumentSets[#argumentSets + 1] = { mapID, true }
        argumentSets[#argumentSets + 1] = { mapID, false }
    end
    for _, candidate in ipairs(candidates) do
        local api, functionName = candidate[1], candidate[2]
        if type(api) == "table" and type(api[functionName]) == "function" then
            for _, arguments in ipairs(argumentSets) do
                local ok, result = call(api[functionName], unpackArgs(arguments))
                if ok then
                    local remaining = countBountifulTable(result)
                    if remaining ~= nil then
                        return remaining, "map:" .. functionName
                    end
                end
            end
        end
    end
    return nil
end

local function areaPoiRemaining()
    if not (C_AreaPoiInfo and type(C_AreaPoiInfo.GetAreaPOIsForMap) == "function"
        and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function") then
        return nil
    end
    local total, active, seen = 0, 0, {}
    for _, mapID in ipairs(mergedDelveMapIDs(true)) do
        local ok, poiIDs = call(C_AreaPoiInfo.GetAreaPOIsForMap, mapID)
        if ok and type(poiIDs) == "table" then
            for _, poiID in ipairs(poiIDs) do
                local infoOk, info = call(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
                local uniqueID = infoOk and type(info) == "table" and tostring(info.areaPoiID or poiID) or nil
                if uniqueID and not seen[uniqueID] then
                    seen[uniqueID] = true
                    if containsBountifulText(info) then
                        total = total + 1
                        if not (info.isCompleted or info.completed or info.wasCompletedToday) then
                            active = active + 1
                        end
                    end
                end
            end
        end
    end
    if total <= 0 then
        return nil
    end
    if active <= 0 and total <= BOUNTIFUL.cap then
        active = total
    end
    return clamp(active, 0, BOUNTIFUL.cap), "poi-map"
end

local function hasActiveDelveRemaining()
    if not (C_DelvesUI and type(C_DelvesUI.HasActiveDelve) == "function") then
        return nil
    end
    local checked, active = 0, 0
    for _, mapID in ipairs(mergedDelveMapIDs(false)) do
        local ok, isActive = call(C_DelvesUI.HasActiveDelve, mapID)
        if ok then
            checked = checked + 1
            if isActive then
                active = active + 1
            end
        end
    end
    if checked <= 0 then
        return nil
    end
    return clamp(active, 0, BOUNTIFUL.cap), "has-active-delve"
end

local function findBountifulRemaining()
    local remaining, source = knownPoiRemaining()
    if remaining ~= nil then
        return remaining, source
    end
    remaining, source = tableApiRemaining()
    if remaining ~= nil then
        return remaining, source
    end
    remaining, source = areaPoiRemaining()
    if remaining ~= nil then
        return remaining, source
    end
    return hasActiveDelveRemaining()
end

local function buildBountifulRow(character, memory)
    local cap = BOUNTIFUL.cap
    if (tonumber(character and character.level) or 0) < BOUNTIFUL.minimumLevel then
        return {
            key = "daily_bountiful",
            label = L.PVE_DAILY_BOUNTIFUL_LABEL,
            completed = false,
            completedCount = 0,
            cap = cap,
            source = "level-gated",
            text = string.format("0/%d", cap),
            status = "locked",
            tooltipTitle = L.PVE_DAILY_BOUNTIFUL_LABEL,
            tooltipLines = { L.PVE_DAILY_BOUNTIFUL_LEVEL_HINT },
        }
    end

    local stickyCompleted = clamp(memory and memory.completed, 0, cap)
    local activeRemaining, source = findBountifulRemaining()
    local completedCount = stickyCompleted
    if activeRemaining and activeRemaining > 0 then
        local liveCompleted = clamp(cap - activeRemaining, 0, cap)
        completedCount = math.max(stickyCompleted, liveCompleted)
    elseif activeRemaining == 0 then
        -- No visible Bountiful Delve can also mean that the map/POI data is
        -- unavailable for the current area. It is not proof that all four
        -- were completed, so retain only progress observed earlier today.
        source = source and (source .. ":no-active-signal") or "no-active-signal"
    end
    local tooltipLines = {
        L.PVE_DAILY_BOUNTIFUL_HINT,
        string.format(L.PVE_DAILY_BOUNTIFUL_PROGRESS, completedCount, cap),
    }
    if activeRemaining ~= nil then
        tooltipLines[#tooltipLines + 1] = string.format(L.PVE_DAILY_BOUNTIFUL_ACTIVE, clamp(activeRemaining, 0, cap))
    end
    return {
        key = "daily_bountiful",
        label = L.PVE_DAILY_BOUNTIFUL_LABEL,
        completed = completedCount >= cap,
        completedCount = completedCount,
        cap = cap,
        source = source or "sticky",
        text = string.format("%d/%d", completedCount, cap),
        status = completedCount >= cap and "complete" or "open",
        tooltipTitle = L.PVE_DAILY_BOUNTIFUL_LABEL,
        tooltipLines = tooltipLines,
    }
end

local function buildWantedRow(memory)
    local definition = DEFINITIONS.wantedHarandar
    local pool, poolLookup = definition.questPool, {}
    local completedIDs, activeIDs, availableIDs = {}, {}, {}
    local visibleOnMap, stickyIDs = {}, {}
    for _, questID in ipairs(pool) do
        poolLookup[questID] = true
        if QuestApi:IsCompleted(questID) then
            completedIDs[#completedIDs + 1] = questID
        elseif QuestApi:IsActive(questID) then
            activeIDs[#activeIDs + 1] = questID
        end
    end
    for _, mapID in ipairs(definition.waypoint.mapIDs or {}) do
        for _, questID in ipairs(QuestApi:GetTaskQuestIDsOnMap(mapID)) do
            if poolLookup[questID] then
                visibleOnMap[questID] = true
            end
        end
    end
    local stickyCount = 0
    for questID, known in pairs(type(memory) == "table" and memory.discoveredIDs or {}) do
        questID = tonumber(questID)
        if known and questID and poolLookup[questID] then
            stickyIDs[questID] = true
            stickyCount = stickyCount + 1
        end
    end
    for _, questID in ipairs(pool) do
        if not QuestApi:IsCompleted(questID) and not QuestApi:IsActive(questID)
            and (visibleOnMap[questID] or stickyIDs[questID] or QuestApi:IsTaskActive(questID)) then
            availableIDs[#availableIDs + 1] = questID
        end
    end

    local completedCount = #completedIDs
    local totalToday = math.max(completedCount + #activeIDs + #availableIDs, tonumber(memory and memory.lastKnownTotal) or 0, stickyCount)
    local tooltipLines, status, text = {}, "locked", L.PVE_DAILY_STATUS_UNAVAILABLE
    if totalToday > 1 then
        tooltipLines[#tooltipLines + 1] = string.format(L.PVE_DAILY_WANTED_PROGRESS, completedCount, totalToday)
    end
    if completedCount > 0 and completedCount >= math.max(1, totalToday) then
        status, text = "complete", L.PVE_DAILY_STATUS_DONE
        tooltipLines[#tooltipLines + 1] = L.PVE_DAILY_WANTED_DONE_HINT
    elseif #activeIDs > 0 then
        local ready = false
        local activeNames = {}
        for _, questID in ipairs(activeIDs) do
            ready = QuestApi:IsTurnInReady(questID) or ready
            activeNames[#activeNames + 1] = QuestApi:GetTitle(questID, string.format("Quest %d", questID))
            for _, line in ipairs(QuestApi:GetObjectiveLines(questID)) do
                tooltipLines[#tooltipLines + 1] = line
            end
        end
        status = ready and "turnin" or "open"
        text = totalToday > 1 and string.format("%d/%d", completedCount, totalToday)
            or (ready and L.PVE_DAILY_STATUS_TURNIN or QuestApi:GetObjectiveProgressText(activeIDs[1]) or L.PVE_DAILY_STATUS_ACCEPTED)
        if #activeNames > 0 then
            table.insert(tooltipLines, totalToday > 1 and 2 or 1, string.format(L.PVE_DAILY_WANTED_ACCEPTED_HINT, table.concat(activeNames, ", ")))
        end
        if #tooltipLines == 0 then
            tooltipLines[1] = ready and L.PVE_DAILY_WANTED_TURNIN_HINT or L.PVE_DAILY_WANTED_ACTIVE_HINT
        end
    elseif #availableIDs > 0 then
        status = "missing"
        text = totalToday > 1 and string.format("%d/%d", completedCount, totalToday) or L.PVE_DAILY_STATUS_ACCEPT
        tooltipLines[#tooltipLines + 1] = string.format(L.PVE_DAILY_WANTED_ACCEPT_HINT, definition.npc, definition.area)
        local names = {}
        for _, questID in ipairs(availableIDs) do
            names[#names + 1] = QuestApi:GetTitle(questID, string.format("Quest %d", questID))
        end
        if #names > 0 then
            tooltipLines[#tooltipLines + 1] = string.format(L.PVE_DAILY_WANTED_AVAILABLE_HINT, table.concat(names, ", "))
        end
    else
        tooltipLines[#tooltipLines + 1] = L.PVE_DAILY_WANTED_UNAVAILABLE_HINT
        tooltipLines[#tooltipLines + 1] = L.PVE_DAILY_WANTED_LIMITED_HINT
    end

    return {
        key = "daily_wanted_harandar",
        label = L.PVE_DAILY_WANTED_LABEL,
        text = text,
        status = status,
        seen = totalToday > 0,
        completed = status == "complete",
        questID = activeIDs[1] or availableIDs[1],
        activeIDs = activeIDs,
        availableIDs = availableIDs,
        completedIDs = completedIDs,
        totalToday = totalToday,
        lastKnownTotal = totalToday,
        discoveredIDs = stickyIDs,
        tooltipTitle = L.PVE_DAILY_WANTED_LABEL,
        tooltipLines = tooltipLines,
        waypoint = {
            mapIDs = definition.waypoint.mapIDs,
            x = definition.waypoint.x,
            y = definition.waypoint.y,
            title = string.format("%s - %s", definition.npc, definition.area),
        },
    }
end

local function buildDecorDuelRow()
    local questID = DEFINITIONS.decorDuel.questID
    local label = L.PVE_DAILY_DECOR_LABEL
    local title = QuestApi:GetTitle(questID, label)
    if QuestApi:IsCompleted(questID) then
        return {
            key = "daily_decor_duel", label = label, text = L.PVE_DAILY_STATUS_DONE,
            status = "complete", seen = true, completed = true, questID = questID,
            tooltipTitle = title, tooltipLines = { L.PVE_DAILY_DECOR_DONE_HINT },
        }
    end
    if QuestApi:IsActive(questID) then
        local ready = QuestApi:IsTurnInReady(questID)
        local lines = QuestApi:GetObjectiveLines(questID)
        if #lines == 0 then
            lines[1] = ready and L.PVE_DAILY_DECOR_TURNIN_HINT or L.PVE_DAILY_DECOR_ACTIVE_HINT
        end
        return {
            key = "daily_decor_duel", label = label,
            text = ready and L.PVE_DAILY_STATUS_TURNIN or QuestApi:GetObjectiveProgressText(questID) or L.PVE_DAILY_STATUS_ACCEPTED,
            status = ready and "turnin" or "open", seen = true, completed = false,
            questID = questID, turnInQuestID = ready and questID or nil,
            tooltipTitle = title, tooltipLines = lines,
        }
    end
    return {
        key = "daily_decor_duel", label = label, text = L.PVE_DAILY_STATUS_ACCEPT,
        status = "missing", seen = true, completed = false, questID = questID,
        tooltipTitle = title,
        tooltipLines = { QuestApi:IsTaskActive(questID) and L.PVE_DAILY_DECOR_AVAILABLE_HINT or L.PVE_DAILY_DECOR_ACCEPT_HINT },
    }
end

function Logic:GetWantedGossipQuestIDs()
    local poolLookup, result = {}, {}
    for _, questID in ipairs(DEFINITIONS.wantedHarandar.questPool) do
        poolLookup[questID] = true
    end
    for _, questID in ipairs(QuestApi:GetGossipQuestIDs()) do
        if poolLookup[questID] then
            result[#result + 1] = questID
        end
    end
    return result
end

function Logic:BuildSnapshot(memory, existingSnapshot, character)
    if not QuestApi:IsAvailable() then
        return existingSnapshot
    end
    memory = type(memory) == "table" and memory or {}
    memory.bountiful = type(memory.bountiful) == "table" and memory.bountiful or {}
    memory.wanted = type(memory.wanted) == "table" and memory.wanted or {}
    local secondsUntilReset, resetAt = Addon.WoWApi:GetDailyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.resetAt or nil
    )
    local rows = {
        buildBountifulRow(character, memory.bountiful),
        buildWantedRow(memory.wanted),
    }
    if type(DEFINITIONS.decorDuel) == "table"
        and DEFINITIONS.decorDuel.enabled == true
    then
        rows[#rows + 1] = buildDecorDuelRow()
    end
    memory.bountiful.completed = rows[1].completedCount
    memory.wanted.lastKnownTotal = rows[2].lastKnownTotal
    memory.wanted.discoveredIDs = rows[2].discoveredIDs
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
