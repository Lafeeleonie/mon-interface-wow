local _, Addon = ...

local QuestApi = {}
Addon.QuestApi = QuestApi

local function call(api, ...)
    if type(api) ~= "function" then
        return false
    end
    return pcall(api, ...)
end

local function parseFraction(text)
    if type(text) ~= "string" then
        return nil, nil
    end
    local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
    current, maximum = tonumber(current), tonumber(maximum)
    if current and maximum and maximum > 0 then
        return current, maximum
    end
    return nil, nil
end

function QuestApi:ParseObjectiveFraction(text)
    return parseFraction(text)
end

local function objectiveProgress(objective)
    if type(objective) ~= "table" then
        return parseFraction(objective)
    end
    local current = tonumber(objective.numFulfilled or objective.fulfilledAmount or objective.currentAmount
        or objective.quantity or objective.numCollected or objective.curValue)
    local maximum = tonumber(objective.numRequired or objective.requiredAmount or objective.totalAmount
        or objective.total or objective.targetAmount or objective.maxValue)
    if current and maximum and maximum > 0 then
        return math.max(0, current), math.max(1, maximum)
    end
    return parseFraction(objective.text or objective.description)
end

function QuestApi:IsAvailable()
    return type(C_QuestLog) == "table"
        and type(C_QuestLog.IsQuestFlaggedCompleted) == "function"
        and (type(C_QuestLog.IsOnQuest) == "function" or type(C_QuestLog.GetLogIndexForQuestID) == "function")
end

function QuestApi:IsCompleted(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return false
    end
    local ok, completed = call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID)
    if ok then
        return completed == true
    end
    ok, completed = call(IsQuestFlaggedCompleted, questID)
    return ok and completed == true or false
end

function QuestApi:IsCompletedOnAccount(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return false
    end
    local ok, completed = call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount, questID)
    if ok then
        return completed == true
    end
    return self:IsCompleted(questID)
end

function QuestApi:IsActive(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return false
    end
    local ok, active = call(C_QuestLog and C_QuestLog.IsOnQuest, questID)
    if ok and active then
        return true
    end
    local logIndex
    ok, logIndex = call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    return ok and tonumber(logIndex) and tonumber(logIndex) > 0 or false
end

local function loadQuestLogUI()
    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(loadAddOn) == "function" then
        pcall(loadAddOn, "Blizzard_UIPanels_Game")
        pcall(loadAddOn, "Blizzard_WorldMap")
    end
end

local function raiseQuestFrameAboveVaultloom(name, frame)
    local ui = Addon.UI
    if frame and ui and type(ui.HookBlizzardFrontMenu) == "function" then
        ui:HookBlizzardFrontMenu(name, frame)
    end
end

function QuestApi:OpenQuest(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 or not self:IsActive(questID) then
        return false
    end

    loadQuestLogUI()
    if type(QuestUtil) == "table" and type(QuestUtil.OpenQuestDetails) == "function" then
        local ok = pcall(QuestUtil.OpenQuestDetails, questID)
        if not ok then
            return false
        end
        raiseQuestFrameAboveVaultloom("QuestDetails", _G.QuestLogPopupDetailFrame)
        return true
    end

    if type(QuestMapFrame_OpenToQuestDetails) == "function" then
        local ok = pcall(QuestMapFrame_OpenToQuestDetails, questID)
        if not ok then
            return false
        end
        raiseQuestFrameAboveVaultloom("QuestLog", _G.WorldMapFrame or _G.QuestMapFrame)
        return true
    end

    if type(OpenQuestLog) ~= "function" or type(QuestMapFrame_ShowQuestDetails) ~= "function" then
        return false
    end
    local opened = pcall(OpenQuestLog)
    local shown = opened and pcall(QuestMapFrame_ShowQuestDetails, questID)
    if not shown then
        return false
    end
    raiseQuestFrameAboveVaultloom("QuestLog", _G.WorldMapFrame or _G.QuestMapFrame)
    return true
end

function QuestApi:IsTaskActive(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        return false
    end
    local ok, active = call(C_TaskQuest and C_TaskQuest.IsActive, questID)
    return ok and active == true or false
end

function QuestApi:GetTaskQuestIDsOnMap(mapID)
    local ids = {}
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 then
        return ids
    end
    local ok, quests = call(C_TaskQuest and C_TaskQuest.GetQuestsOnMap, mapID)
    if not ok or type(quests) ~= "table" then
        return ids
    end
    local seen = {}
    for _, entry in ipairs(quests) do
        local questID = tonumber(type(entry) == "table" and (entry.questID or entry.questId) or entry)
        if questID and questID > 0 and not seen[questID] then
            seen[questID] = true
            ids[#ids + 1] = questID
        end
    end
    return ids
end

function QuestApi:GetGossipQuestIDs()
    local ids = {}
    local seen = {}
    local function collect(api)
        local ok, quests = call(api)
        if not ok or type(quests) ~= "table" then
            return
        end
        for _, entry in ipairs(quests) do
            local questID = tonumber(type(entry) == "table" and (entry.questID or entry.questId) or entry)
            if questID and questID > 0 and not seen[questID] then
                seen[questID] = true
                ids[#ids + 1] = questID
            end
        end
    end
    collect(C_GossipInfo and C_GossipInfo.GetAvailableQuests)
    collect(C_GossipInfo and C_GossipInfo.GetActiveQuests)
    return ids
end

function QuestApi:GetLogEntries()
    local entries = {}
    local ok, count = call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    if not ok or not tonumber(count) then
        return entries
    end
    for index = 1, tonumber(count) do
        local infoOk, info = call(C_QuestLog and C_QuestLog.GetInfo, index)
        if infoOk and type(info) == "table" and not info.isHeader and not info.isHidden then
            entries[#entries + 1] = {
                questID = tonumber(info.questID) or 0,
                title = type(info.title) == "string" and info.title or "",
                isComplete = info.isComplete == true,
            }
        end
    end
    return entries
end

function QuestApi:GetTitle(questID, fallback)
    local ok, title = call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
    if ok and type(title) == "string" and title ~= "" then
        return title
    end
    local logIndex
    ok, logIndex = call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    if ok and tonumber(logIndex) and tonumber(logIndex) > 0 then
        local infoOk, info = call(C_QuestLog and C_QuestLog.GetInfo, logIndex)
        if infoOk and type(info) == "table" and type(info.title) == "string" and info.title ~= "" then
            return info.title
        end
    end
    return fallback
end

function QuestApi:GetObjectiveLines(questID)
    local lines = {}
    local ok, objectives = call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if ok and type(objectives) == "table" then
        for _, objective in ipairs(objectives) do
            local text = type(objective) == "table" and (objective.text or objective.description) or objective
            if type(text) == "string" and text ~= "" then
                lines[#lines + 1] = text
            end
        end
    end
    return lines
end

function QuestApi:GetObjectiveProgressText(questID, includeComplete)
    local progressEntries = {}
    local ok, objectives = call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if ok and type(objectives) == "table" then
        for _, objective in ipairs(objectives) do
            local current, maximum = objectiveProgress(objective)
            if current and maximum then
                progressEntries[#progressEntries + 1] = {
                    current = math.min(maximum, current),
                    maximum = maximum,
                }
            end
        end
    end
    for _, entry in ipairs(progressEntries) do
        if entry.current < entry.maximum or includeComplete == true then
            return string.format("%d/%d", math.floor(entry.current + 0.5), math.floor(entry.maximum + 0.5))
        end
    end
    return nil
end

function QuestApi:IsTurnInReady(questID)
    if not self:IsActive(questID) or self:IsCompleted(questID) then
        return false
    end
    local ok, ready = call(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID)
    if ok and ready then
        return true
    end
    local logIndex
    ok, logIndex = call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    if ok and tonumber(logIndex) and tonumber(logIndex) > 0 then
        local infoOk, info = call(C_QuestLog and C_QuestLog.GetInfo, logIndex)
        if infoOk and type(info) == "table" and info.isComplete == true then
            return true
        end
    end

    local sawObjective, allComplete = false, true
    local objectivesOk, objectives = call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if objectivesOk and type(objectives) == "table" then
        for _, objective in ipairs(objectives) do
            local current, maximum = objectiveProgress(objective)
            if current and maximum then
                sawObjective = true
                allComplete = allComplete and current >= maximum
            elseif type(objective) == "table" and objective.finished ~= nil then
                sawObjective = true
                allComplete = allComplete and objective.finished == true
            end
        end
    end
    return sawObjective and allComplete
end
