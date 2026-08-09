local _, Addon = ...

local FEATURE_ID = "auto_accept_quests"
local Logic = Addon.AutoAcceptQuestsLogic
local QuestApi = Addon.QuestApi

local SELECT_DELAY = 0.06
local ACTION_DELAY = 0.05
local NEXT_QUEST_DELAY = 0.20
local DECLINE_PAUSE_SECONDS = 10

local Runtime = {
    enabled = false,
    hooksReady = false,
    generation = 0,
    selectToken = 0,
    actionToken = 0,
    declinePauseUntil = 0,
    sessionActive = false,
    attemptedAvailable = {},
    attemptedTurnIn = {},
    completedTurnIn = {},
    approvedTurnIn = {},
}

Addon.AutoAcceptQuests = Runtime

local function now()
    return type(GetTime) == "function" and tonumber(GetTime()) or 0
end

local function isCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function isPartySyncActive()
    if not C_QuestSession then
        return false
    end
    for _, methodName in ipairs({ "HasJoined", "Exists" }) do
        local method = C_QuestSession[methodName]
        if type(method) == "function" then
            local ok, active = pcall(method)
            if ok and active == true then
                return true
            end
        end
    end
    return false
end

local function currentQuestID()
    if type(GetQuestID) ~= "function" then
        return nil
    end
    local ok, questID = pcall(GetQuestID)
    questID = ok and tonumber(questID) or nil
    return questID and questID > 0 and questID or nil
end

local function defaultQuestFrequency()
    return tonumber(Enum and Enum.QuestFrequency and Enum.QuestFrequency.Default) or 1
end

local function copyQuestInfo(info)
    local result = {}
    for key, value in pairs(type(info) == "table" and info or {}) do
        result[key] = value
    end
    result.questID = tonumber(result.questID)
    return result
end

local function callNumber(api, ...)
    if type(api) ~= "function" then
        return nil, false
    end
    local ok, value = pcall(api, ...)
    value = ok and tonumber(value) or nil
    return value, ok and value ~= nil
end

local function getRequiredCount(api)
    local value, known = callNumber(api)
    if known then
        return value, true
    end
    value, known = callNumber(api, "required")
    return value, known
end

function Runtime:BuildCostSnapshot()
    local choiceCount, choiceCountKnown = callNumber(GetNumQuestChoices)
    local requiredMoney, requiredMoneyKnown = callNumber(GetQuestMoneyToGet)
    local requiredItems, requiredItemsKnown = getRequiredCount(GetNumQuestItems)
    local requiredCurrencies, requiredCurrenciesKnown = getRequiredCount(GetNumQuestCurrencies)

    local requiredItemsHidden
    local requiredItemsHiddenKnown = false
    if C_QuestOffer and type(C_QuestOffer.GetHideRequiredItems) == "function" then
        local ok, hidden = pcall(C_QuestOffer.GetHideRequiredItems)
        if ok and type(hidden) == "boolean" then
            requiredItemsHidden = hidden
            requiredItemsHiddenKnown = true
        end
    end

    return {
        choiceCount = choiceCount,
        choiceCountKnown = choiceCountKnown,
        requiredMoney = requiredMoney,
        requiredMoneyKnown = requiredMoneyKnown,
        requiredItems = requiredItems,
        requiredItemsKnown = requiredItemsKnown,
        requiredCurrencies = requiredCurrencies,
        requiredCurrenciesKnown = requiredCurrenciesKnown,
        requiredItemsHidden = requiredItemsHidden,
        requiredItemsHiddenKnown = requiredItemsHiddenKnown,
    }
end

function Runtime:IsZeroCostAcceptance(snapshot)
    if type(snapshot) ~= "table"
        or snapshot.requiredMoneyKnown ~= true
        or snapshot.requiredItemsKnown ~= true
        or snapshot.requiredCurrenciesKnown ~= true
        or snapshot.requiredItemsHiddenKnown ~= true
    then
        return false, "unknown-cost"
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

function Runtime:BaseContext()
    return {
        enabled = self.enabled,
        altPaused = type(IsAltKeyDown) == "function" and IsAltKeyDown() == true,
        declinePaused = now() < (tonumber(self.declinePauseUntil) or 0),
        inCombat = isCombatLocked(),
        partySync = isPartySyncActive(),
        acceptTrivial = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "trivial_quests") == true,
        safeTurnIn = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "safe_turn_in") == true,
        defaultFrequency = defaultQuestFrequency(),
    }
end

function Runtime:ContextForAvailable(info)
    local questID = tonumber(info and info.questID)
    local context = self:BaseContext()
    context.attempted = questID and self.attemptedAvailable[questID] == true
    context.onQuest = questID and QuestApi:IsActive(questID) == true
    return context
end

function Runtime:ContextForTurnIn(info)
    local questID = tonumber(info and info.questID)
    local context = self:BaseContext()
    context.attempted = questID and self.attemptedTurnIn[questID] == true
    context.completedThisSession = questID and self.completedTurnIn[questID] == true
    context.ready = questID and QuestApi:IsTurnInReady(questID) == true
    return context
end

function Runtime:ActionContext(info, progressApproved)
    local questID = tonumber(info and info.questID)
    local context = self:ContextForTurnIn(info)
    context.attempted = false
    context.selectedThisSession = questID and self.attemptedTurnIn[questID] == true
    context.currentQuestMatches = questID and currentQuestID() == questID
    context.progressApproved = progressApproved == true

    if type(IsQuestCompletable) == "function" then
        local ok, completable = pcall(IsQuestCompletable)
        context.completable = progressApproved == true or (ok and completable == true)
    else
        context.completable = progressApproved == true
    end
    return context
end

function Runtime:InvalidateTimers()
    self.generation = self.generation + 1
    self.selectToken = self.selectToken + 1
    self.actionToken = self.actionToken + 1
end

function Runtime:ResetSession()
    self.sessionActive = false
    self.pendingAccept = nil
    self.pendingTurnIn = nil
    self.attemptedAvailable = {}
    self.attemptedTurnIn = {}
    self.completedTurnIn = {}
    self.approvedTurnIn = {}
    self:InvalidateTimers()
end

function Runtime:BeginSession()
    if self.sessionActive then
        return
    end
    self:ResetSession()
    self.sessionActive = true
end

function Runtime:RecordDecision(action, questID, allowed, reason)
    self.lastDecision = {
        action = action,
        questID = tonumber(questID),
        allowed = allowed == true,
        reason = tostring(reason or ""),
    }
end

local function availableQuests()
    if not (C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function") then
        return nil
    end
    local ok, quests = pcall(C_GossipInfo.GetAvailableQuests)
    return ok and type(quests) == "table" and quests or nil
end

local function activeQuests()
    if not (C_GossipInfo and type(C_GossipInfo.GetActiveQuests) == "function") then
        return nil
    end
    local ok, quests = pcall(C_GossipInfo.GetActiveQuests)
    return ok and type(quests) == "table" and quests or nil
end

function Runtime:SelectTurnInQuest()
    local quests = activeQuests()
    if type(quests) ~= "table" then
        return false
    end

    local chosen, reason = Logic:ChooseSingleTurnIn(quests, function(info)
        return Runtime:ContextForTurnIn(info)
    end)
    if not chosen then
        self:RecordDecision("select-turn-in", nil, false, reason)
        return false
    end

    local questID = tonumber(chosen.questID)
    if not (questID
        and C_GossipInfo
        and type(C_GossipInfo.SelectActiveQuest) == "function")
    then
        self:RecordDecision("select-turn-in", questID, false, "api")
        return false
    end

    self.attemptedTurnIn[questID] = true
    self.pendingTurnIn = copyQuestInfo(chosen)
    local ok = pcall(C_GossipInfo.SelectActiveQuest, questID)
    self:RecordDecision("select-turn-in", questID, ok, ok and "selected" or "api")
    return ok
end

function Runtime:SelectAvailableQuest()
    local quests = availableQuests()
    if type(quests) ~= "table" then
        return false
    end

    for _, info in ipairs(quests) do
        local allowed, reason = Logic:IsAvailableQuestAllowed(info, self:ContextForAvailable(info))
        local questID = tonumber(type(info) == "table" and info.questID)
        if allowed then
            if not (C_GossipInfo and type(C_GossipInfo.SelectAvailableQuest) == "function") then
                self:RecordDecision("select-available", questID, false, "api")
                return false
            end
            self.attemptedAvailable[questID] = true
            self.pendingAccept = copyQuestInfo(info)
            local ok = pcall(C_GossipInfo.SelectAvailableQuest, questID)
            self:RecordDecision("select-available", questID, ok, ok and "selected" or "api")
            return ok
        end
        self:RecordDecision("select-available", questID, false, reason)
    end
    return false
end

function Runtime:SelectNextQuest()
    if self.enabled ~= true
        or self.sessionActive ~= true
        or self.pendingAccept
        or self.pendingTurnIn
        or Logic:IsAutomationPaused(self:BaseContext())
    then
        return false
    end
    if Addon.FeatureRegistry:GetSetting(FEATURE_ID, "safe_turn_in") == true
        and self:SelectTurnInQuest()
    then
        return true
    end
    return self:SelectAvailableQuest()
end

function Runtime:ScheduleSelect(delay)
    if self.enabled ~= true then
        return false
    end
    self.selectToken = self.selectToken + 1
    local token = self.selectToken
    local generation = self.generation
    local callback = function()
        if Runtime.enabled == true
            and Runtime.generation == generation
            and Runtime.selectToken == token
        then
            Runtime:SelectNextQuest()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or SELECT_DELAY, callback)
    else
        callback()
    end
    return true
end

function Runtime:ScheduleAction(callback, delay)
    if self.enabled ~= true or type(callback) ~= "function" then
        return false
    end
    self.actionToken = self.actionToken + 1
    local token = self.actionToken
    local generation = self.generation
    local run = function()
        if Runtime.enabled == true
            and Runtime.generation == generation
            and Runtime.actionToken == token
        then
            callback(Runtime)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or ACTION_DELAY, run)
    else
        run()
    end
    return true
end

function Runtime:AcceptPendingQuest()
    local info = self.pendingAccept
    local questID = tonumber(info and info.questID)
    local allowed, reason = Logic:IsAvailableQuestAllowed(info, {
        enabled = self.enabled,
        altPaused = type(IsAltKeyDown) == "function" and IsAltKeyDown() == true,
        declinePaused = now() < (tonumber(self.declinePauseUntil) or 0),
        inCombat = isCombatLocked(),
        partySync = isPartySyncActive(),
        acceptTrivial = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "trivial_quests") == true,
        defaultFrequency = defaultQuestFrequency(),
        attempted = false,
        onQuest = questID and QuestApi:IsActive(questID) == true,
    })
    if not allowed or currentQuestID() ~= questID then
        self:RecordDecision("accept", questID, false, reason or "quest-changed")
        self.pendingAccept = nil
        return false
    end

    local zeroCost, costReason = self:IsZeroCostAcceptance(self:BuildCostSnapshot())
    if not zeroCost or type(AcceptQuest) ~= "function" then
        self:RecordDecision("accept", questID, false, costReason or "api")
        self.pendingAccept = nil
        return false
    end

    local ok = pcall(AcceptQuest)
    self:RecordDecision("accept", questID, ok, ok and "accepted" or "api")
    return ok
end

function Runtime:CompletePendingQuest()
    local info = self.pendingTurnIn
    local questID = tonumber(info and info.questID)
    local snapshot = self:BuildCostSnapshot()
    local allowed, reason = Logic:CanCompleteSelectedTurnIn(
        info,
        self:ActionContext(info, false),
        snapshot
    )
    if not allowed or type(CompleteQuest) ~= "function" then
        self:RecordDecision("complete", questID, false, reason or "api")
        return false
    end

    self.approvedTurnIn[questID] = true
    local ok = pcall(CompleteQuest)
    if not ok then
        self.approvedTurnIn[questID] = nil
    end
    self:RecordDecision("complete", questID, ok, ok and "approved" or "api")
    return ok
end

function Runtime:RewardPendingQuest()
    local info = self.pendingTurnIn
    local questID = tonumber(info and info.questID)
    local approved = questID and self.approvedTurnIn[questID] == true
    local allowed, reason = Logic:CanRewardSelectedTurnIn(
        info,
        self:ActionContext(info, approved),
        self:BuildCostSnapshot()
    )
    if not allowed or type(GetQuestReward) ~= "function" then
        self:RecordDecision("reward", questID, false, reason or "api")
        return false
    end

    local ok = pcall(GetQuestReward, 0)
    self:RecordDecision("reward", questID, ok, ok and "rewarded" or "api")
    return ok
end

function Runtime:EnsureHooks()
    if self.hooksReady then
        return
    end
    self.hooksReady = true
    if type(hooksecurefunc) == "function" and type(DeclineQuest) == "function" then
        pcall(hooksecurefunc, "DeclineQuest", function()
            Runtime.declinePauseUntil = now() + DECLINE_PAUSE_SECONDS
            Runtime.actionToken = Runtime.actionToken + 1
            Runtime.selectToken = Runtime.selectToken + 1
        end)
    end
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "GOSSIP_SHOW" or eventName == "QUEST_GREETING" then
        self:BeginSession()
        self:ScheduleSelect(SELECT_DELAY)
    elseif eventName == "GOSSIP_CLOSED" then
        local interactionIsContinuing = ...
        self.selectToken = self.selectToken + 1
        if interactionIsContinuing ~= true then
            self:ResetSession()
        end
    elseif eventName == "QUEST_DETAIL" then
        self:ScheduleAction(self.AcceptPendingQuest, ACTION_DELAY)
    elseif eventName == "QUEST_PROGRESS" then
        self:ScheduleAction(self.CompletePendingQuest, ACTION_DELAY)
    elseif eventName == "QUEST_COMPLETE" then
        self:ScheduleAction(self.RewardPendingQuest, ACTION_DELAY)
    elseif eventName == "QUEST_ACCEPTED" then
        local firstArg, secondArg = ...
        local questID = tonumber(secondArg) or tonumber(firstArg)
        if self.pendingAccept and tonumber(self.pendingAccept.questID) == questID then
            self.pendingAccept = nil
        end
        self:ScheduleSelect(NEXT_QUEST_DELAY)
    elseif eventName == "QUEST_TURNED_IN" then
        local questID = tonumber((...))
        if questID then
            self.completedTurnIn[questID] = true
            self.approvedTurnIn[questID] = nil
        end
        if self.pendingTurnIn and tonumber(self.pendingTurnIn.questID) == questID then
            self.pendingTurnIn = nil
        end
        self:ScheduleSelect(NEXT_QUEST_DELAY)
    elseif eventName == "QUEST_FINISHED" then
        self.actionToken = self.actionToken + 1
        self.pendingAccept = nil
        self.pendingTurnIn = nil
        self:ScheduleSelect(NEXT_QUEST_DELAY)
    elseif eventName == "PLAYER_REGEN_DISABLED" then
        self.selectToken = self.selectToken + 1
        self.actionToken = self.actionToken + 1
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self:ResetSession()
    self:EnsureHooks()
    for _, eventName in ipairs({
        "GOSSIP_SHOW",
        "GOSSIP_CLOSED",
        "QUEST_GREETING",
        "QUEST_DETAIL",
        "QUEST_PROGRESS",
        "QUEST_COMPLETE",
        "QUEST_ACCEPTED",
        "QUEST_TURNED_IN",
        "QUEST_FINISHED",
        "PLAYER_REGEN_DISABLED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(dispatchedEvent, ...)
            Runtime:OnEvent(dispatchedEvent, ...)
        end)
    end
end

function Runtime:OnDisable()
    self.enabled = false
    Addon.EventBus:UnsubscribeOwner(self)
    self:ResetSession()
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "safe_turn_in"
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "safe_turn_in") ~= true
    then
        self.pendingTurnIn = nil
        self.approvedTurnIn = {}
        self.actionToken = self.actionToken + 1
    end
    self.selectToken = self.selectToken + 1
    self:ScheduleSelect(0)
end

assert(
    Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime),
    "Auto-Accept Quests runtime registration failed"
)
