local _, Addon = ...

local Logic = {
    version = 1,
}

Addon.AutoAcceptQuestsLogic = Logic

local function validQuestID(value)
    local questID = tonumber(value)
    return questID and questID > 0 and questID or nil
end

function Logic:IsRepeatable(info, defaultFrequency)
    if type(info) ~= "table" then
        return true
    end
    if info.repeatable == true
        or info.isRepeatable == true
        or info.isDaily == true
        or info.isWeekly == true
    then
        return true
    end

    local frequency = tonumber(info.frequency or info.questFrequency)
    defaultFrequency = tonumber(defaultFrequency) or 1
    return frequency ~= nil and frequency > 0 and frequency ~= defaultFrequency
end

function Logic:IsAutomationPaused(context)
    context = type(context) == "table" and context or {}
    return context.enabled == false
        or context.altPaused == true
        or context.declinePaused == true
        or context.inCombat == true
        or context.partySync == true
end

function Logic:IsAvailableQuestAllowed(info, context)
    context = type(context) == "table" and context or {}
    local questID = validQuestID(info and info.questID)
    if not questID or self:IsAutomationPaused(context) then
        return false, "invalid"
    end
    if info.isIgnored == true
        or info.isHidden == true
        or context.onQuest == true
        or context.attempted == true
    then
        return false, "unavailable"
    end
    if context.acceptTrivial ~= true and info.isTrivial == true then
        return false, "trivial"
    end
    if self:IsRepeatable(info, context.defaultFrequency) then
        return false, "repeatable"
    end
    return true
end

function Logic:IsTurnInQuestInspectable(info, context)
    context = type(context) == "table" and context or {}
    local questID = validQuestID(info and info.questID)
    if not questID or self:IsAutomationPaused(context) or context.safeTurnIn ~= true then
        return false, "disabled"
    end
    if info.isIgnored == true
        or info.isHidden == true
        or info.isImportant == true
        or info.isLegendary == true
        or info.isMeta == true
        or context.attempted == true
        or context.completedThisSession == true
    then
        return false, "protected"
    end
    if context.acceptTrivial ~= true and info.isTrivial == true then
        return false, "trivial"
    end
    if self:IsRepeatable(info, context.defaultFrequency) then
        return false, "repeatable"
    end
    if info.isComplete ~= true and context.ready ~= true then
        return false, "incomplete"
    end
    return true
end

function Logic:ChooseSingleTurnIn(activeQuests, contextForQuest)
    if type(activeQuests) ~= "table" then
        return nil, "unknown"
    end

    local chosen
    local count = 0
    for _, info in ipairs(activeQuests) do
        if type(info) ~= "table" or not validQuestID(info.questID) then
            return nil, "unknown"
        end
        local context = type(contextForQuest) == "function"
            and contextForQuest(info)
            or contextForQuest
        if self:IsTurnInQuestInspectable(info, context) then
            count = count + 1
            chosen = info
        end
    end

    if count ~= 1 then
        return nil, count == 0 and "none" or "ambiguous"
    end
    return chosen
end

function Logic:IsZeroCostTurnIn(snapshot)
    if type(snapshot) ~= "table"
        or snapshot.choiceCountKnown ~= true
        or snapshot.requiredMoneyKnown ~= true
        or snapshot.requiredItemsKnown ~= true
        or snapshot.requiredCurrenciesKnown ~= true
        or snapshot.requiredItemsHiddenKnown ~= true
    then
        return false, "unknown"
    end
    if (tonumber(snapshot.choiceCount) or 0) ~= 0 then
        return false, "reward-choice"
    end
    if (tonumber(snapshot.requiredMoney) or 0) ~= 0 then
        return false, "money"
    end
    if (tonumber(snapshot.requiredItems) or 0) ~= 0 then
        return false, "items"
    end
    if (tonumber(snapshot.requiredCurrencies) or 0) ~= 0 then
        return false, "currencies"
    end
    if snapshot.requiredItemsHidden == true then
        return false, "hidden-items"
    end
    return true
end

function Logic:CanCompleteSelectedTurnIn(info, context, snapshot)
    local allowed, reason = self:IsTurnInQuestInspectable(info, context)
    if not allowed then
        return false, reason
    end
    if context.selectedThisSession ~= true
        or context.currentQuestMatches ~= true
        or context.completable ~= true
    then
        return false, "state"
    end
    return self:IsZeroCostTurnIn(snapshot)
end

function Logic:CanRewardSelectedTurnIn(info, context, snapshot)
    if context.progressApproved ~= true then
        return false, "not-approved"
    end
    return self:CanCompleteSelectedTurnIn(info, context, snapshot)
end
