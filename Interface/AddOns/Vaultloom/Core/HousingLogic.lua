local _, Addon = ...

local L = Addon.L
local Data = Addon.Data.HOUSING
local Logic = {}
Addon.HousingLogic = Logic

local function numeric(value)
    return tonumber(value) or 0
end

local function safeCall(api, method, ...)
    if type(api) ~= "table" or type(api[method]) ~= "function" then
        return false
    end
    return pcall(api[method], ...)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, numeric(value)))
end

local function sequence(entries)
    local result, keys = {}, {}
    if type(entries) ~= "table" then return result end
    for key, value in pairs(entries) do
        if type(key) == "number" and value ~= nil then keys[#keys + 1] = key end
    end
    if #keys > 0 then
        table.sort(keys)
        for _, key in ipairs(keys) do result[#result + 1] = entries[key] end
    else
        for _, value in pairs(entries) do
            if value ~= nil then result[#result + 1] = value end
        end
    end
    return result
end

local function formatValue(value)
    value = numeric(value)
    if math.abs(value - math.floor(value + 0.5)) < 0.01 then
        return tostring(math.floor(value + 0.5))
    end
    return string.format("%.1f", value)
end

function Logic:FormatDuration(seconds)
    seconds = math.max(0, math.floor(numeric(seconds)))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then return string.format(L.TIME_DAY_HOUR, days, hours) end
    if hours > 0 then return string.format(L.TIME_HOUR_MIN, hours, minutes) end
    return string.format(L.TIME_MIN, minutes)
end

local function findHouse(houses, neighborhoodGUID)
    if not neighborhoodGUID then return nil end
    for _, house in ipairs(houses) do
        if house.neighborhoodGUID == neighborhoodGUID then return house end
    end
end

local function chooseNeighborhood(houses, initiative, activeNeighborhoodGUID, rememberedNeighborhoodGUID)
    if rememberedNeighborhoodGUID and findHouse(houses, rememberedNeighborhoodGUID) then
        return rememberedNeighborhoodGUID
    end
    if activeNeighborhoodGUID then return activeNeighborhoodGUID end
    if type(initiative) == "table" and initiative.isLoaded == true and initiative.neighborhoodGUID then
        return initiative.neighborhoodGUID
    end
    if rememberedNeighborhoodGUID then return rememberedNeighborhoodGUID end
    return houses[1] and houses[1].neighborhoodGUID or nil
end

local function taskProgress(task)
    local requirement = type(task.requirementsList) == "table" and task.requirementsList[1] or nil
    local text = requirement and requirement.requirementText
    if type(text) == "string" and text ~= "" then
        local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
        if current and maximum then return numeric(current), math.max(1, numeric(maximum)), text end
    end
    return task.completed == true and 1 or 0, 1, nil
end

local function couponReward(task)
    if numeric(task and task.rewardQuestID) <= 0 then return 0 end
    local ok, rewards = safeCall(C_QuestLog, "GetQuestRewardCurrencies", task.rewardQuestID)
    if not ok or type(rewards) ~= "table" then return 0 end
    for _, reward in ipairs(rewards) do
        if numeric(reward.currencyID) == Data.currencyID then
            return numeric(reward.totalRewardAmount)
        end
    end
    return 0
end

local function firstPositiveNumber(...)
    for index = 1, select("#", ...) do
        local candidate = select(index, ...)
        local value = tonumber(candidate)
        if value and value > 0 then return value end
    end
end

local function addUniqueText(target, seen, value)
    if type(value) ~= "string" or value == "" or seen[value] then return end
    seen[value] = true
    target[#target + 1] = value
end

local function rewardName(reward)
    if type(reward) ~= "table" then return nil end
    for _, key in ipairs({ "rewardName", "name", "title", "displayName", "description", "rewardText" }) do
        if type(reward[key]) == "string" and reward[key] ~= "" then return reward[key] end
    end

    local decorID = tonumber(reward.decorID or reward.decorRecordID or reward.recordID)
    if decorID then
        local ok, name = safeCall(C_HousingDecor, "GetDecorName", decorID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end

    local itemID = tonumber(reward.itemID or reward.rewardItemID)
    if itemID then
        local ok, name = safeCall(C_Item, "GetItemNameByID", itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end

    local currencyID = tonumber(reward.currencyID or reward.rewardCurrencyID)
    if currencyID then
        local ok, info = safeCall(C_CurrencyInfo, "GetCurrencyInfo", currencyID)
        if ok and type(info) == "table" and type(info.name) == "string" then
            local amount = firstPositiveNumber(
                reward.amount,
                reward.quantity,
                reward.rewardAmount,
                reward.totalRewardAmount
            )
            return amount and string.format("%s %s", formatValue(amount), info.name) or info.name
        end
    end
end

local function milestoneRewardLines(milestone)
    local lines, seen = {}, {}
    if type(milestone) ~= "table" then return lines end
    for _, key in ipairs({ "rewardName", "rewardText", "rewardDescription" }) do
        addUniqueText(lines, seen, milestone[key])
    end
    for _, key in ipairs({ "reward", "rewardInfo" }) do
        addUniqueText(lines, seen, rewardName(milestone[key]))
    end
    for _, reward in ipairs(sequence(milestone.rewards or milestone.rewardList)) do
        addUniqueText(lines, seen, rewardName(reward))
    end
    addUniqueText(lines, seen, rewardName({
        decorID = milestone.rewardDecorID or milestone.decorID,
        itemID = milestone.rewardItemID or milestone.itemID,
        currencyID = milestone.rewardCurrencyID or milestone.currencyID,
        amount = milestone.rewardAmount or milestone.amount,
    }))

    local coupons = couponReward(milestone)
    if coupons > 0 then addUniqueText(lines, seen, string.format(L.HOUSING_TASK_COUPONS, coupons)) end
    return lines
end

local function trackedLookup()
    local lookup = {}
    local ok, tracked = safeCall(C_NeighborhoodInitiative, "GetTrackedInitiativeTasks")
    if ok and type(tracked) == "table" then
        for _, taskID in ipairs(type(tracked.trackedIDs) == "table" and tracked.trackedIDs or {}) do
            lookup[tonumber(taskID) or taskID] = true
        end
    end
    return lookup
end

local function collectTasks(rawTasks)
    local tasks, trackedTasks, seen = {}, {}, {}
    local tracked = trackedLookup()
    local completedCount = 0

    for _, task in ipairs(sequence(rawTasks)) do
        local taskID = tonumber(task and task.ID) or (task and task.ID)
        if type(task) == "table" and (taskID == nil or not seen[taskID]) then
            if taskID ~= nil then seen[taskID] = true end
            local current, maximum, requirementText = taskProgress(task)
            local isTracked = tracked[taskID] == true
            local completed = task.completed == true
            local repeatable = numeric(task.taskType) > 0
            local contribution = numeric(task.progressContributionAmount)
            local coupons = couponReward(task)
            local name = type(task.taskName) == "string" and task.taskName ~= "" and task.taskName or L.UNKNOWN
            local description = type(task.description) == "string" and task.description or ""
            local meta, tooltip = {}, {}
            if description ~= "" then tooltip[#tooltip + 1] = description end
            if requirementText then tooltip[#tooltip + 1] = requirementText end
            if contribution > 0 then
                local text = string.format(L.HOUSING_TASK_XP, contribution)
                meta[#meta + 1], tooltip[#tooltip + 1] = text, text
            end
            if coupons > 0 then
                local text = string.format(L.HOUSING_TASK_COUPONS, coupons)
                meta[#meta + 1], tooltip[#tooltip + 1] = text, text
            end
            if repeatable then
                meta[#meta + 1] = L.HOUSING_TASK_REPEATABLE
                tooltip[#tooltip + 1] = L.HOUSING_TASK_DIMINISHING_HINT
                tooltip[#tooltip + 1] = string.format(L.HOUSING_TASK_HOUSE_XP_CAP, Data.houseXPPerEndeavor)
            end
            if isTracked then meta[#meta + 1] = L.HOUSING_TASK_TRACKED end
            if repeatable and numeric(task.timesCompleted) > 0 then
                tooltip[#tooltip + 1] = string.format(L.HOUSING_TASK_TIMES, numeric(task.timesCompleted))
            end
            local status = completed and "complete" or current > 0 and "turnin" or "open"
            local statusText = completed and L.HOUSING_TASK_PROGRESS_DONE
                or maximum > 1 and string.format("%d/%d", current, maximum)
                or isTracked and L.HOUSING_TASK_TRACKED or L.HOUSING_TASK_PROGRESS_OPEN
            local entry = {
                id = taskID,
                title = name,
                meta = table.concat(meta, "  |  "),
                status = status,
                statusText = statusText,
                progressCurrent = current,
                progressMax = maximum,
                progressRatio = maximum > 1 and clamp(current / maximum, 0, 1) or 0,
                tooltipTitle = name,
                tooltipLines = tooltip,
                completed = completed,
                tracked = isTracked,
                sortOrder = numeric(task.sortOrder) > 0 and numeric(task.sortOrder) or 999,
            }
            tasks[#tasks + 1] = entry
            if completed then completedCount = completedCount + 1 end
            if isTracked and not completed then
                trackedTasks[#trackedTasks + 1] = {
                    id = taskID,
                    label = name,
                    text = maximum > 1 and string.format("%d/%d", current, maximum) or L.HOUSING_TASK_TRACKED,
                    status = status,
                    tooltipTitle = name,
                    tooltipLines = tooltip,
                    tracked = true,
                    hideStatusBadge = true,
                }
            end
        end
    end

    table.sort(tasks, function(left, right)
        if left.completed ~= right.completed then return not left.completed end
        if left.sortOrder ~= right.sortOrder then return left.sortOrder < right.sortOrder end
        return string.lower(left.title) < string.lower(right.title)
    end)
    table.sort(trackedTasks, function(left, right) return string.lower(left.label) < string.lower(right.label) end)
    return tasks, trackedTasks, completedCount
end

local function collectMilestones(initiative, progress)
    local entries, thresholds, source, maximum = {}, {}, {}, 0
    for _, milestone in ipairs(sequence(initiative and initiative.milestones)) do
        local threshold = numeric(milestone and milestone.requiredContributionAmount)
        if threshold > 0 then
            thresholds[#thresholds + 1] = threshold
            source[#source + 1] = { threshold = threshold, milestone = milestone }
            maximum = math.max(maximum, threshold)
        end
    end
    table.sort(thresholds)
    table.sort(source, function(left, right) return left.threshold < right.threshold end)
    for _, record in ipairs(source) do
        local threshold = record.threshold
        local remaining = math.max(0, threshold - progress)
        local rewards = milestoneRewardLines(record.milestone)
        local tooltip = { string.format("%d / %d", progress, threshold) }
        if #rewards > 0 then
            tooltip[#tooltip + 1] = L.HOUSING_MILESTONE_REWARDS
            for _, reward in ipairs(rewards) do tooltip[#tooltip + 1] = reward end
        else
            tooltip[#tooltip + 1] = L.HOUSING_MILESTONE_REWARD_HINT
        end
        entries[#entries + 1] = {
            label = string.format(L.HOUSING_MILESTONE_LABEL, threshold),
            text = remaining == 0 and L.HOUSING_MILESTONE_REWARD_READY
                or string.format(L.HOUSING_MILESTONE_LEFT, remaining),
            status = remaining == 0 and "complete"
                or remaining <= math.max(5, math.floor(threshold * 0.15)) and "turnin" or "open",
            hideStatusBadge = true,
            tooltipTitle = string.format(L.HOUSING_MILESTONE_LABEL, threshold),
            tooltipLines = tooltip,
            rewards = rewards,
        }
    end
    return entries, thresholds, maximum
end

local function taskContributionLookup(rawTasks)
    local byID, byName = {}, {}
    for _, task in ipairs(sequence(rawTasks)) do
        if type(task) == "table" then
            local amount = firstPositiveNumber(
                task.progressContributionAmount,
                task.contributionAmount,
                task.taskContributionAmount,
                task.amount
            )
            local taskID = tonumber(task.ID or task.taskID or task.initiativeTaskID)
            if amount and taskID then byID[taskID] = amount end
            if amount and type(task.taskName) == "string" then byName[task.taskName] = amount end
        end
    end
    return byID, byName
end

local function collectActivity(activityInfo, rawTasks)
    local entries = {}
    local activities = sequence(activityInfo and activityInfo.taskActivity)
    local contributionByID, contributionByName = taskContributionLookup(rawTasks)
    table.sort(activities, function(left, right)
        return numeric(left and left.completionTime) > numeric(right and right.completionTime)
    end)
    local playerName = type(UnitName) == "function" and UnitName("player") or nil
    for _, activity in ipairs(activities) do
        if #entries >= Data.maxActivityEntries then break end
        if type(activity) == "table" then
            local taskName = type(activity.taskName) == "string" and activity.taskName or L.UNKNOWN
            local sourceName = type(activity.playerName) == "string" and activity.playerName or L.UNKNOWN
            local taskInfo = type(activity.taskInfo) == "table" and activity.taskInfo
                or type(activity.task) == "table" and activity.task or nil
            local taskID = tonumber(activity.taskID or activity.initiativeTaskID or activity.ID
                or taskInfo and (taskInfo.taskID or taskInfo.initiativeTaskID or taskInfo.ID))
            local amount = firstPositiveNumber(
                activity.progressContributionAmount,
                activity.contributionAmount,
                activity.taskContributionAmount,
                activity.contribution,
                activity.amount,
                activity.quantity,
                activity.value,
                taskInfo and taskInfo.progressContributionAmount,
                taskInfo and taskInfo.contributionAmount,
                taskID and contributionByID[taskID],
                contributionByName[taskName]
            )
            local amountText = amount and string.format(L.HOUSING_ACTIVITY_AMOUNT, formatValue(amount))
                or L.HOUSING_ACTIVITY_AMOUNT_UNKNOWN
            local tooltip = { sourceName, amountText }
            if numeric(activity.completionTime) > 0 and type(date) == "function" then
                tooltip[#tooltip + 1] = date("%d.%m.%Y %H:%M", activity.completionTime)
            end
            entries[#entries + 1] = {
                label = string.format(L.HOUSING_ACTIVITY_BY, sourceName, taskName),
                text = amountText,
                status = sourceName == playerName and "complete" or "open",
                hideStatusBadge = true,
                tooltipTitle = taskName,
                tooltipLines = tooltip,
            }
        end
    end
    return entries
end

function Logic:IsAvailable()
    return type(C_Housing) == "table"
        and type(C_NeighborhoodInitiative) == "table"
        and type(C_CurrencyInfo) == "table"
        and type(C_CurrencyInfo.GetCurrencyInfo) == "function"
end

function Logic:Scan(runtime, weekly, requestedNeighborhoodGUID)
    runtime = type(runtime) == "table" and runtime or {}
    if not self:IsAvailable() then
        return nil, { unavailable = true }
    end

    local houses = type(runtime.houseList) == "table" and runtime.houseList or {}
    local _, rawInitiative = safeCall(C_NeighborhoodInitiative, "GetNeighborhoodInitiativeInfo")
    local _, activeNeighborhoodGUID = safeCall(C_NeighborhoodInitiative, "GetActiveNeighborhood")
    local targetNeighborhoodGUID = chooseNeighborhood(
        houses,
        rawInitiative,
        activeNeighborhoodGUID,
        requestedNeighborhoodGUID or runtime.selectedNeighborhoodGUID or runtime.viewingNeighborhoodGUID
    )
    local selectedHouse = findHouse(houses, targetNeighborhoodGUID)
        or findHouse(houses, activeNeighborhoodGUID)
        or houses[1]
    if not targetNeighborhoodGUID and selectedHouse then targetNeighborhoodGUID = selectedHouse.neighborhoodGUID end

    local staleInitiative = type(rawInitiative) == "table"
        and rawInitiative.isLoaded == true
        and targetNeighborhoodGUID
        and rawInitiative.neighborhoodGUID
        and rawInitiative.neighborhoodGUID ~= targetNeighborhoodGUID
    local initiative = not staleInitiative and type(rawInitiative) == "table" and rawInitiative or nil
    local rawTasks = initiative and type(initiative.tasks) == "table" and initiative.tasks or {}
    local needsTasks = initiative and initiative.isLoaded == true
        and numeric(initiative.initiativeID) > 0
        and #sequence(rawTasks) == 0

    local houseGUID = selectedHouse and selectedHouse.houseGUID
    if houseGUID then
        local okFavor, favor = safeCall(C_Housing, "GetCurrentHouseLevelFavor", houseGUID)
        if okFavor and type(favor) == "table" then
            runtime.lastHouseLevelFavor = favor
            runtime.houseLevelFavorByGUID = type(runtime.houseLevelFavorByGUID) == "table"
                and runtime.houseLevelFavorByGUID or {}
            runtime.houseLevelFavorByGUID[houseGUID] = favor
        end
    end
    local favor = houseGUID and runtime.houseLevelFavorByGUID and runtime.houseLevelFavorByGUID[houseGUID]
        or runtime.lastHouseLevelFavor

    local _, rawActivity = safeCall(C_NeighborhoodInitiative, "GetInitiativeActivityLogInfo")
    local activity = type(rawActivity) == "table"
        and rawActivity.isLoaded == true
        and (not targetNeighborhoodGUID or rawActivity.neighborhoodGUID == targetNeighborhoodGUID)
        and rawActivity or nil
    local needs = {
        houseList = #houses == 0,
        initiative = targetNeighborhoodGUID ~= nil
            and (staleInitiative or not (initiative and initiative.isLoaded == true) or needsTasks),
        activity = targetNeighborhoodGUID ~= nil and activity == nil,
        favor = houseGUID ~= nil and favor == nil,
        houseGUID = houseGUID,
        neighborhoodGUID = targetNeighborhoodGUID,
    }
    if targetNeighborhoodGUID and not (initiative and initiative.isLoaded == true) then
        return nil, needs
    end

    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(Data.currencyID) or {}
    local coupons = numeric(currencyInfo.quantity)
    local couponCap = numeric(currencyInfo.maxQuantity)
    local couponName = type(currencyInfo.name) == "string" and currencyInfo.name or L.HOUSING_HOME_COUPONS
    local currentLevel = numeric(favor and favor.houseLevel)
    local currentFavor = numeric(favor and favor.houseFavor)
    local maxLevel = 0
    local okMax, liveMaxLevel = safeCall(C_Housing, "GetMaxHouseLevel")
    if okMax then maxLevel = numeric(liveMaxLevel) end
    local nextLevelFavor = 0
    if currentLevel > 0 and maxLevel > currentLevel then
        local okNext, neededFavor = safeCall(C_Housing, "GetHouseLevelFavorForLevel", currentLevel + 1)
        if okNext then nextLevelFavor = numeric(neededFavor) end
    end

    local currentProgress = numeric(initiative and initiative.currentProgress)
    local playerContribution = numeric(initiative and initiative.playerTotalContribution)
    local tasks, trackedTasks, completedTasks = collectTasks(rawTasks)
    local milestones, thresholds, maxProgress = collectMilestones(initiative, currentProgress)
    if maxProgress <= 0 then maxProgress = math.max(1, numeric(initiative and initiative.progressRequired)) end
    local nextMilestone
    for _, threshold in ipairs(thresholds) do
        if threshold > currentProgress then nextMilestone = threshold - currentProgress; break end
    end
    local notes = {}
    if nextMilestone then
        notes[#notes + 1] = string.format(L.HOUSING_PROGRESS_NEXT, nextMilestone)
    elseif #milestones > 0 then
        notes[#notes + 1] = L.HOUSING_PROGRESS_REACHED
    end
    if numeric(initiative and initiative.duration) > 0 then
        notes[#notes + 1] = string.format(L.HOUSING_PROGRESS_DAYS, self:FormatDuration(initiative.duration))
    end
    if initiative and initiative.neighborhoodGUID and activeNeighborhoodGUID
        and initiative.neighborhoodGUID ~= activeNeighborhoodGUID
    then
        notes[#notes + 1] = L.HOUSING_NOTE_NON_ACTIVE
    end

    local houseTitle = selectedHouse and selectedHouse.houseName
    if type(houseTitle) ~= "string" or houseTitle == "" then
        houseTitle = selectedHouse and selectedHouse.neighborhoodName or L.HOUSING_HOME_NONE
    end
    local houseSubtitle = selectedHouse and selectedHouse.neighborhoodName or ""
    if houseSubtitle == houseTitle then houseSubtitle = "" end
    local activeHouse = selectedHouse and activeNeighborhoodGUID
        and selectedHouse.neighborhoodGUID == activeNeighborhoodGUID
    local taskCount = #tasks

    return {
        available = true,
        updatedAt = type(time) == "function" and time() or 0,
        neighborhoodGUID = targetNeighborhoodGUID,
        activeNeighborhoodGUID = activeNeighborhoodGUID,
        initiativeID = numeric(initiative and initiative.initiativeID),
        cycleID = numeric(initiative and (initiative.cycleID or initiative.currentCycleID or initiative.initiativeID)),
        currentProgress = currentProgress,
        maxProgress = maxProgress,
        isComplete = maxProgress > 0 and currentProgress >= maxProgress,
        isActive = targetNeighborhoodGUID ~= nil and targetNeighborhoodGUID == activeNeighborhoodGUID,
        title = initiative and initiative.title or L.HOUSING_TITLE,
        subtitle = "",
        statCards = {
            {
                label = L.HOUSING_SUMMARY_HOME_LEVEL,
                value = currentLevel > 0 and string.format("%d/%d", currentLevel, maxLevel > 0 and maxLevel or currentLevel) or "--",
                meta = currentLevel > 0 and L.HOUSING_SUMMARY_HOME_LEVEL_META or "",
            },
            {
                label = L.HOUSING_HOME_FAVOR,
                value = nextLevelFavor > 0 and string.format("%d / %d", currentFavor, nextLevelFavor)
                    or currentLevel > 0 and L.HOUSING_HOME_MAX or "--",
                meta = nextLevelFavor > 0 and L.HOUSING_SUMMARY_HOME_FAVOR_META or "",
            },
            {
                label = couponName,
                value = couponCap > 0 and string.format("%d / %d", coupons, couponCap) or tostring(coupons),
                meta = L.HOUSING_SUMMARY_COUPON_META,
            },
            {
                label = L.HOUSING_SUMMARY_CONTRIBUTION,
                value = tostring(math.floor(playerContribution + 0.5)),
                meta = string.format(L.HOUSING_SUMMARY_TASK_META, completedTasks, taskCount),
            },
        },
        progress = {
            label = L.HOUSING_PROGRESS_LABEL,
            value = string.format("%d / %d", currentProgress, maxProgress),
            ratio = maxProgress > 0 and clamp(currentProgress / maxProgress, 0, 1) or 0,
            thresholds = thresholds,
            maxThreshold = maxProgress,
            note = table.concat(notes, "  |  "),
        },
        loadingTasks = needsTasks,
        rewardSummary = {
            complete = maxProgress > 0 and currentProgress >= maxProgress,
            title = L.HOUSING_REWARD_SUMMARY_TITLE,
            status = maxProgress > 0 and currentProgress >= maxProgress
                and L.HOUSING_REWARD_SUMMARY_UNLOCKED or L.HOUSING_REWARD_SUMMARY_PROGRESS,
            text = maxProgress > 0 and currentProgress >= maxProgress
                and L.HOUSING_REWARD_SUMMARY_COMPLETE
                or nextMilestone and string.format(L.HOUSING_REWARD_SUMMARY_NEXT, nextMilestone)
                or L.HOUSING_REWARD_SUMMARY_PENDING,
        },
        house = {
            neighborhoodGUID = selectedHouse and selectedHouse.neighborhoodGUID,
            houseGUID = selectedHouse and selectedHouse.houseGUID,
            neighborhoodName = selectedHouse and selectedHouse.neighborhoodName,
            houseName = selectedHouse and selectedHouse.houseName,
            isActive = activeHouse == true,
            title = houseTitle,
            subtitle = houseSubtitle,
            meta = string.format(
                L.HOUSING_HOME_META,
                #houses,
                activeHouse and L.HOUSING_HOME_ACTIVE or L.HOUSING_HOME_VIEWING
            ),
            levelValue = currentLevel > 0 and string.format("%d/%d", currentLevel, maxLevel > 0 and maxLevel or currentLevel) or "--",
            favorValue = nextLevelFavor > 0 and string.format("%d / %d", currentFavor, nextLevelFavor)
                or currentLevel > 0 and L.HOUSING_HOME_MAX or "--",
            favorRatio = nextLevelFavor > 0 and clamp(currentFavor / nextLevelFavor, 0, 1)
                or currentLevel > 0 and 1 or 0,
            couponLabel = couponName,
            couponValue = tostring(coupons),
            couponIcon = currencyInfo.iconFileID,
        },
        weekly = weekly,
        tasks = tasks,
        trackedTasks = trackedTasks,
        milestones = milestones,
        activity = collectActivity(activity, rawTasks),
    }, needs
end

local function shallowCopy(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        result[key] = value
    end
    return result
end

local function progressNumbers(view)
    local progress = type(view) == "table" and view.progress or nil
    local maximum = numeric(view and view.maxProgress)
    if maximum <= 0 then maximum = numeric(progress and progress.maxThreshold) end
    local current = numeric(view and view.currentProgress)
    if current <= 0 and type(progress and progress.value) == "string" then
        current = numeric(progress.value:match("^(%d+)"))
    end
    return current, maximum
end

function Logic:IsViewComplete(view)
    if type(view) ~= "table" or view.available ~= true then return false end
    if view.isComplete == true then return true end
    local current, maximum = progressNumbers(view)
    return maximum > 0 and current >= maximum
end

local function neighborhoodCard(house, view, activeNeighborhoodGUID)
    local neighborhoodGUID = house and house.neighborhoodGUID or view and view.neighborhoodGUID
    local current, maximum = progressNumbers(view)
    local progress = type(view) == "table" and view.progress or nil
    local home = type(view) == "table" and view.house or nil
    local neighborhoodName = house and house.neighborhoodName or home and home.neighborhoodName
    local houseName = house and house.houseName or home and home.houseName or home and home.title
    local title = type(neighborhoodName) == "string" and neighborhoodName ~= "" and neighborhoodName
        or type(houseName) == "string" and houseName ~= "" and houseName
        or L.HOUSING_HOME_NONE
    return {
        neighborhoodGUID = neighborhoodGUID,
        houseGUID = house and house.houseGUID or home and home.houseGUID,
        title = title,
        houseName = houseName,
        endeavorTitle = view and view.title or L.HOUSING_LOADING,
        levelValue = home and home.levelValue or "--",
        favorValue = home and home.favorValue or "--",
        currentProgress = current,
        maxProgress = maximum,
        progressValue = maximum > 0 and string.format("%d / %d", current, maximum) or "--",
        progressRatio = maximum > 0 and clamp(current / maximum, 0, 1) or 0,
        complete = false,
        active = neighborhoodGUID ~= nil and neighborhoodGUID == activeNeighborhoodGUID,
        available = type(view) == "table" and view.available == true,
    }
end

function Logic:BuildPortfolio(viewsByNeighborhood, houses, activeNeighborhoodGUID, selectedNeighborhoodGUID, weekly)
    viewsByNeighborhood = type(viewsByNeighborhood) == "table" and viewsByNeighborhood or {}
    houses = type(houses) == "table" and houses or {}

    if not selectedNeighborhoodGUID or not findHouse(houses, selectedNeighborhoodGUID) then
        selectedNeighborhoodGUID = activeNeighborhoodGUID
            or houses[1] and houses[1].neighborhoodGUID
    end

    local cards, order = {}, {}
    for _, house in ipairs(houses) do
        if house.neighborhoodGUID then
            local view = viewsByNeighborhood[house.neighborhoodGUID]
            local card = neighborhoodCard(house, view, activeNeighborhoodGUID)
            card.complete = self:IsViewComplete(view)
            cards[#cards + 1] = card
            order[#order + 1] = house.neighborhoodGUID
        end
    end

    local selectedView = selectedNeighborhoodGUID and viewsByNeighborhood[selectedNeighborhoodGUID]
        or activeNeighborhoodGUID and viewsByNeighborhood[activeNeighborhoodGUID]
        or order[1] and viewsByNeighborhood[order[1]]
    local portfolio = shallowCopy(selectedView)
    if type(selectedView) ~= "table" then
        portfolio = self:BuildView(nil)
    end
    portfolio.neighborhoods = cards
    portfolio.neighborhoodOrder = order
    portfolio.houses = houses
    portfolio.viewsByNeighborhood = viewsByNeighborhood
    portfolio.activeNeighborhoodGUID = activeNeighborhoodGUID
    portfolio.selectedNeighborhoodGUID = selectedNeighborhoodGUID
    portfolio.neighborhoodGUID = selectedNeighborhoodGUID or portfolio.neighborhoodGUID
    portfolio.isActive = selectedNeighborhoodGUID ~= nil
        and selectedNeighborhoodGUID == activeNeighborhoodGUID
    portfolio.isComplete = self:IsViewComplete(selectedView)
    portfolio.weekly = weekly or portfolio.weekly

    local activeView = activeNeighborhoodGUID and viewsByNeighborhood[activeNeighborhoodGUID]
    if self:IsViewComplete(activeView) then
        local candidate
        for _, card in ipairs(cards) do
            if card.neighborhoodGUID ~= activeNeighborhoodGUID
                and card.available
                and not card.complete
                and (not candidate or card.progressRatio < candidate.progressRatio)
            then
                candidate = card
            end
        end
        if candidate then
            portfolio.switchSuggestion = {
                sourceNeighborhoodGUID = activeNeighborhoodGUID,
                targetNeighborhoodGUID = candidate.neighborhoodGUID,
                sourceTitle = activeView and activeView.house and (
                    activeView.house.neighborhoodName or activeView.house.title
                ) or L.HOUSING_HOME_ACTIVE,
                targetTitle = candidate.title,
                targetProgressValue = candidate.progressValue,
                cycleID = numeric(activeView and activeView.cycleID),
            }
        end
    end
    return portfolio
end

function Logic:SelectPortfolioView(portfolio, selectedNeighborhoodGUID)
    if type(portfolio) ~= "table" then return self:BuildView(nil) end
    local views = type(portfolio.viewsByNeighborhood) == "table" and portfolio.viewsByNeighborhood or nil
    if not views or not selectedNeighborhoodGUID or type(views[selectedNeighborhoodGUID]) ~= "table" then
        return portfolio
    end
    return self:BuildPortfolio(
        views,
        portfolio.houses or {},
        portfolio.activeNeighborhoodGUID,
        selectedNeighborhoodGUID,
        portfolio.weekly
    )
end

function Logic:BuildView(snapshot)
    if type(snapshot) ~= "table" or snapshot.available ~= true then
        return {
            available = false,
            message = L.HOUSING_NO_SNAPSHOT,
            tasks = {},
            trackedTasks = {},
            milestones = {},
            activity = {},
        }
    end
    return snapshot
end
