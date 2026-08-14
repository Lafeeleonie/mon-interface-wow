local _, Addon = ...

local L = Addon.L
local Logic = {}
Addon.FocusLogic = Logic

local SECTION_SOURCES = {
    { key = "pve_weekly", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_WEEKLY end, service = "PveWeekly" },
    { key = "pve_coiled_isle", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_COILED_ISLE end, service = "PveCoiledIsle" },
    { key = "pve_void_invasion", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_VOID_INVASION end, service = "PveVoidInvasion" },
    { key = "pve_daily", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_DAILY end, service = "PveDaily" },
    { key = "pve_events", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_EVENTS end, service = "PveEvents" },
    { key = "pve_world", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_WORLD end, service = "PveWorld" },
    { key = "pve_delves", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_DELVES end, service = "PveDelves" },
    { key = "pve_prey", group = function() return L.SCREEN_PVE .. " / " .. L.PVE_TAB_PREY end, service = "PvePrey", prey = true },
    { key = "pvp_weekly", group = function() return L.SCREEN_PVP .. " / " .. L.PVP_TAB_WEEKLY end, service = "PvpWeekly" },
    { key = "systems_professions", group = function() return L.SCREEN_SYSTEMS .. " / " .. L.SYSTEMS_TAB_PROFESSIONS end, service = "Professions" },
}

local function cloneList(source)
    local result = {}
    for _, value in ipairs(type(source) == "table" and source or {}) do
        result[#result + 1] = value
    end
    return result
end

local function normalizeTaskID(taskID)
    taskID = tostring(taskID or "")
    return taskID ~= "" and taskID or nil
end

function Logic:NormalizeStore(store)
    store = type(store) == "table" and store or {}
    store.items = type(store.items) == "table" and store.items or {}
    store.order = type(store.order) == "table" and store.order or {}
    local order, seen = {}, {}
    for _, rawTaskID in ipairs(store.order) do
        local taskID = normalizeTaskID(rawTaskID)
        if taskID and store.items[taskID] == true and not seen[taskID] then
            order[#order + 1] = taskID
            seen[taskID] = true
        end
    end
    for rawTaskID, selected in pairs(store.items) do
        local taskID = normalizeTaskID(rawTaskID)
        if taskID and selected == true then
            if rawTaskID ~= taskID then
                store.items[rawTaskID] = nil
                store.items[taskID] = true
            end
            if not seen[taskID] then
                order[#order + 1] = taskID
                seen[taskID] = true
            end
        else
            store.items[rawTaskID] = nil
        end
    end
    store.order = order
    return store
end

function Logic:NormalizeTracker(tracker)
    tracker = type(tracker) == "table" and tracker or {}
    tracker.shown = tracker.shown == true
    tracker.locked = tracker.locked == true
    tracker.scalePercent = math.max(70, math.min(140, math.floor(tonumber(tracker.scalePercent) or 100)))
    tracker.opacityPercent = math.max(35, math.min(100, math.floor(tonumber(tracker.opacityPercent) or 90)))
    if tracker.styleKey ~= "frame" and tracker.styleKey ~= "rows" and tracker.styleKey ~= "text" then
        tracker.styleKey = tracker.background == false and "rows" or "frame"
    end
    tracker.background = tracker.styleKey == "frame"
    if tracker.fontKey ~= "compact" and tracker.fontKey ~= "large" then tracker.fontKey = "normal" end
    tracker.point = type(tracker.point) == "table" and tracker.point or nil
    return tracker
end

function Logic:CopyStore(source, target)
    source = self:NormalizeStore(source)
    target = self:NormalizeStore(target)
    target.items, target.order = {}, {}
    for _, taskID in ipairs(source.order) do
        if source.items[taskID] == true then
            target.items[taskID] = true
            target.order[#target.order + 1] = taskID
        end
    end
    return target
end

function Logic:GetTaskIDs(store)
    return cloneList(self:NormalizeStore(store).order)
end

local function addItem(catalog, group, item)
    if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then return end
    item.groupKey = group.key
    item.groupLabel = group.label
    group.items[#group.items + 1] = item
    catalog.index[item.id] = item
end

local function addGroup(catalog, key, label)
    local group = { key = key, label = label, items = {} }
    catalog.groups[#catalog.groups + 1] = group
    return group
end

local function summaryEntry(key, label, text, completed, tooltipLines, status)
    return {
        key = key,
        label = label,
        text = text,
        status = status or (completed and "complete" or "open"),
        seen = status ~= "unknown",
        completed = completed == true,
        tooltipTitle = label,
        tooltipLines = tooltipLines,
    }
end

local function vaultEntry(rowKey, label, snapshot)
    local row = type(snapshot) == "table" and type(snapshot.rows) == "table" and snapshot.rows[rowKey] or nil
    if type(row) ~= "table" then
        return summaryEntry(
            "focus_vault_" .. rowKey,
            label,
            L.CUSTOM_TASKS_UNAVAILABLE_VALUE,
            false,
            { L.CUSTOM_TASKS_TRACKER_VAULT_MISSING },
            "unknown"
        )
    end
    local thresholds = type(row.thresholds) == "table" and row.thresholds or {}
    local maximum = math.max(0, tonumber(thresholds[#thresholds]) or 0)
    local completed = math.max(0, tonumber(row.completedCount) or 0)
    if maximum > 0 then completed = math.min(maximum, completed) end
    local goal = type(row.goal) == "table" and row.goal or nil
    local text = goal and (goal.displayCountText or goal.displayText)
    if type(text) ~= "string" or text == "" then
        text = maximum > 0 and string.format("%d/%d", completed, maximum) or tostring(completed)
    end
    local isComplete = (tonumber(goal and goal.missingToMax) or 1) <= 0
        or (maximum > 0 and completed >= maximum)
    local tooltip = {
        string.format("%s: %s", L.VAULT_UNLOCK_LABEL, maximum > 0 and string.format("%d/%d", completed, maximum) or tostring(completed)),
    }
    if goal and goal.displayText then
        tooltip[#tooltip + 1] = string.format("%s: %s", goal.label or L.VAULT_GOAL_LABEL, goal.displayText)
    end
    if type(row.note) == "string" and row.note ~= "" then tooltip[#tooltip + 1] = row.note end
    return summaryEntry("focus_vault_" .. rowKey, label, text, isComplete, tooltip)
end

local function addFocusTrackers(catalog, characterKey)
    local group = addGroup(catalog, "focus_trackers", L.CUSTOM_TASKS_TRACKER_GROUP)
    local vault = Addon.VaultProgress and Addon.VaultProgress:GetSnapshot(characterKey)
    local labels = {
        raid = L.CUSTOM_TASKS_TRACKER_VAULT_RAID,
        dungeon = L.CUSTOM_TASKS_TRACKER_VAULT_DUNGEON,
        world = L.CUSTOM_TASKS_TRACKER_VAULT_WORLD,
    }
    for _, rowKey in ipairs({ "raid", "dungeon", "world" }) do
        local entry = vaultEntry(rowKey, labels[rowKey], vault)
        addItem(catalog, group, { id = "focus:vault_" .. rowKey, label = entry.label, entry = entry })
    end

    local delves = Addon.PveDelves and Addon.PveDelves:GetSnapshot(characterKey)
    local delveSummary = type(delves) == "table" and type(delves.summary) == "table" and delves.summary or nil
    local delveCompleted = math.max(0, tonumber(delveSummary and delveSummary.completed) or 0)
    local delveTotal = math.max(0, tonumber(delveSummary and delveSummary.total) or 0)
    local delveLabel = L.CUSTOM_TASKS_TRACKER_DELVES
    addItem(catalog, group, {
        id = "focus:delves_progress",
        label = delveLabel,
        entry = summaryEntry(
            "focus_delves_progress",
            delveLabel,
            delveSummary and (delveSummary.progressText or string.format("%d/%d", delveCompleted, delveTotal))
                or L.CUSTOM_TASKS_UNAVAILABLE_VALUE,
            delveTotal > 0 and delveCompleted >= delveTotal,
            { L.CUSTOM_TASKS_TRACKER_DELVES_TOOLTIP },
            delveTotal > 0 and nil or "unknown"
        ),
    })

    local prey = Addon.PvePrey and Addon.PvePrey:GetSnapshot(characterKey)
    local preyTotal = math.max(0, tonumber(prey and prey.total) or 0)
    local preyCap = math.max(0, tonumber(prey and prey.totalCap) or 0)
    local preyLabel = L.CUSTOM_TASKS_TRACKER_PREY
    local preyTooltip = { L.CUSTOM_TASKS_TRACKER_PREY_TOOLTIP }
    if type(prey and prey.activeMapName) == "string" and prey.activeMapName ~= "" then
        preyTooltip[#preyTooltip + 1] = prey.activeMapName
    end
    addItem(catalog, group, {
        id = "focus:prey_progress",
        label = preyLabel,
        entry = summaryEntry(
            "focus_prey_progress",
            preyLabel,
            preyCap > 0 and string.format("%d/%d", preyTotal, preyCap) or L.CUSTOM_TASKS_UNAVAILABLE_VALUE,
            preyCap > 0 and preyTotal >= preyCap,
            preyTooltip,
            preyCap > 0 and nil or "unknown"
        ),
    })

    local knowledge = Addon.Professions and Addon.Professions:GetKnowledge(characterKey)
    local totalPoints = math.max(0, tonumber(knowledge and knowledge.totalPoints) or 0)
    local professionCount = math.max(0, tonumber(knowledge and knowledge.professionCount) or 0)
    local knowledgeLabel = L.CUSTOM_TASKS_TRACKER_PROFESSION_KNOWLEDGE
    addItem(catalog, group, {
        id = "focus:profession_knowledge",
        label = knowledgeLabel,
        entry = summaryEntry(
            "focus_profession_knowledge",
            knowledgeLabel,
            totalPoints > 0 and ("+" .. totalPoints) or "0",
            totalPoints <= 0 and professionCount > 0,
            { L.CUSTOM_TASKS_TRACKER_PROFESSION_KNOWLEDGE_TOOLTIP },
            professionCount <= 0 and "unknown" or (totalPoints > 0 and "warning" or "complete")
        ),
    })
    for index, profession in ipairs(type(knowledge) == "table" and type(knowledge.professions) == "table" and knowledge.professions or {}) do
        local name = profession.name or L.UNKNOWN
        local points = math.max(0, tonumber(profession.points) or 0)
        local token = profession.skillLineID or profession.professionKey or index
        local label = string.format(L.CUSTOM_TASKS_TRACKER_PROFESSION_FORMAT, name)
        addItem(catalog, group, {
            id = "focus:profession_knowledge_" .. tostring(token),
            label = label,
            entry = summaryEntry(
                "focus_profession_knowledge_" .. tostring(token),
                label,
                points > 0 and ("+" .. points) or "0",
                points <= 0,
                { L.CUSTOM_TASKS_TRACKER_PROFESSION_KNOWLEDGE_TOOLTIP },
                points > 0 and "warning" or "complete"
            ),
        })
    end
end

local function addSnapshotRows(catalog, source, snapshot)
    local group = { key = source.key, label = source.group(), items = {} }
    local rows
    if source.prey then
        rows = snapshot and snapshot.weeklyQuest and { snapshot.weeklyQuest } or {}
    else
        rows = type(snapshot) == "table" and type(snapshot.rows) == "table" and snapshot.rows or {}
    end
    for index, entry in ipairs(rows) do
        if type(entry) == "table" and entry.key ~= "profession_none" then
            local rowKey = source.prey and "weekly_quest" or entry.customTaskKey or entry.key
            local questID = tonumber(entry.questID)
            rowKey = rowKey or (questID and ("quest_" .. questID)) or ("row_" .. index)
            local label = entry.label or entry.tooltipTitle or L.UNKNOWN
            addItem(catalog, group, {
                id = source.key .. ":" .. tostring(rowKey),
                label = label,
                entry = entry,
            })
        end
    end
    if #group.items > 0 then catalog.groups[#catalog.groups + 1] = group end
end

function Logic:BuildCatalog(characterKey)
    local catalog = { groups = {}, index = {} }
    addFocusTrackers(catalog, characterKey)
    for _, source in ipairs(SECTION_SOURCES) do
        local service = Addon[source.service]
        local snapshot = service and type(service.GetSnapshot) == "function" and service:GetSnapshot(characterKey) or nil
        addSnapshotRows(catalog, source, snapshot)
    end
    return catalog
end

function Logic:BuildView(characterKey, store, meta)
    local catalog = self:BuildCatalog(characterKey)
    local rows, completed = {}, 0
    for _, taskID in ipairs(self:GetTaskIDs(store)) do
        local item = catalog.index[taskID]
        if not item then
            local saved = type(meta) == "table" and meta[taskID] or nil
            local label = type(saved) == "table" and saved.label or taskID
            item = {
                id = taskID,
                label = label,
                groupLabel = type(saved) == "table" and saved.groupLabel or L.CUSTOM_TASKS_UNKNOWN_GROUP,
                entry = summaryEntry(
                    "focus_unavailable",
                    label,
                    L.CUSTOM_TASKS_UNAVAILABLE_VALUE,
                    false,
                    { L.CUSTOM_TASKS_UNAVAILABLE_TOOLTIP },
                    "unknown"
                ),
            }
        end
        rows[#rows + 1] = item
        if item.entry and (item.entry.completed == true or item.entry.status == "complete") then completed = completed + 1 end
    end
    return {
        characterKey = characterKey,
        rows = rows,
        catalog = catalog,
        summary = {
            completed = completed,
            total = #rows,
            text = string.format("%d/%d", completed, #rows),
        },
    }
end
