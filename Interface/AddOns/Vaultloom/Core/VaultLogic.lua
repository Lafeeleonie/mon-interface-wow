local _, Addon = ...

local L = Addon.L
local Logic = {}
Addon.VaultLogic = Logic

local DELVE_ITEM_LEVELS = Addon.Data.DELVES_GREAT_VAULT_ITEM_LEVEL

local function call(api, ...)
    if type(api) ~= "function" then
        return false
    end
    return pcall(api, ...)
end

local function getLayout()
    local rewardType = Enum and Enum.WeeklyRewardChestThresholdType
    if not rewardType then
        return nil
    end
    return {
        { key = "raid", type = rewardType.Raid, label = L.VAULT_RAIDS },
        { key = "dungeon", type = rewardType.Activities, label = L.VAULT_DUNGEONS },
        { key = "world", type = rewardType.World, label = L.VAULT_WORLD },
    }
end

local function getRewardLinks(activityID)
    local ok, rewardLink, upgradeLink = call(
        C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks,
        activityID
    )
    if not ok then
        return nil, nil
    end
    return rewardLink ~= "" and rewardLink or nil, upgradeLink ~= "" and upgradeLink or nil
end

local function getRewardLinkFromCachedRewards(activity)
    if type(activity) ~= "table" or type(activity.rewards) ~= "table" then
        return nil
    end
    local itemType = Enum and Enum.CachedRewardType and Enum.CachedRewardType.Item
    for _, reward in ipairs(activity.rewards) do
        local isItem = reward and ((itemType and reward.type == itemType) or tonumber(reward.type) == 1)
        if isItem and reward.itemDBID then
            local ok, link = call(C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink, reward.itemDBID)
            if ok and type(link) == "string" and link ~= "" then
                return link
            end
        end
    end
    return nil
end

local function getItemLevel(itemLink)
    if not itemLink then
        return nil
    end
    local ok, itemLevel = call(C_Item and C_Item.GetDetailedItemLevelInfo, itemLink)
    itemLevel = ok and tonumber(itemLevel) or nil
    return itemLevel and itemLevel > 0 and itemLevel or nil
end

local function getNextTierItemLevel(activityTierID, level)
    activityTierID, level = tonumber(activityTierID), tonumber(level)
    if not activityTierID or activityTierID <= 0 or level == nil then
        return nil
    end
    local ok, hasSeasonData, _, nextLevel, itemLevel = call(
        C_WeeklyRewards and C_WeeklyRewards.GetNextActivitiesIncrease,
        activityTierID,
        math.max(0, level)
    )
    itemLevel = ok and hasSeasonData and tonumber(itemLevel) or nil
    if itemLevel and itemLevel > 0 then
        return itemLevel, tonumber(nextLevel) or 0
    end
    return nil
end

local function getTierItemLevel(activityTierID, level)
    level = tonumber(level) or 0
    if level <= 0 then
        return nil
    end
    local itemLevel, nextLevel = getNextTierItemLevel(activityTierID, level - 1)
    if itemLevel and (nextLevel <= 0 or nextLevel == level) then
        return itemLevel
    end
    return nil
end

local function getRewardData(rowKey, activity)
    local rewardLink, upgradeLink = getRewardLinks(activity.id)
    rewardLink = rewardLink or getRewardLinkFromCachedRewards(activity)
    local rewardItemLevel = getItemLevel(rewardLink)
        or getTierItemLevel(activity.activityTierID, activity.level)
    local upgradeItemLevel = getItemLevel(upgradeLink)
        or getNextTierItemLevel(activity.activityTierID, activity.level)

    local level = tonumber(activity.level) or 0
    if rowKey == "world" then
        rewardItemLevel = rewardItemLevel or DELVE_ITEM_LEVELS[level]
        upgradeItemLevel = upgradeItemLevel or DELVE_ITEM_LEVELS[level + 1]
    end
    return rewardItemLevel, rewardLink, upgradeItemLevel, upgradeLink
end

local function rewardLabel(activity, itemLevel)
    local tier = tonumber(activity and activity.level) or 0
    if itemLevel and tier > 0 then
        return string.format(L.VAULT_REWARD_TIER_ITEM_LEVEL, tier, itemLevel)
    elseif itemLevel then
        return string.format(L.VAULT_REWARD_ITEM_LEVEL, itemLevel)
    elseif tier > 0 then
        return string.format(L.VAULT_REWARD_TIER, tier)
    end
    return nil
end

local function targetItemLevel(rowKey, slots)
    local target = 0
    for _, slot in ipairs(slots or {}) do
        target = math.max(target, tonumber(slot.rewardItemLevel) or 0)
    end
    if rowKey == "world" then
        target = math.max(target, tonumber(DELVE_ITEM_LEVELS[8]) or 0)
    end
    return target
end

local function firstMaximumDelveLevel()
    local maximum, firstLevel = 0, nil
    for _, itemLevel in pairs(DELVE_ITEM_LEVELS) do
        maximum = math.max(maximum, tonumber(itemLevel) or 0)
    end
    for level, itemLevel in pairs(DELVE_ITEM_LEVELS) do
        if tonumber(itemLevel) == maximum and (not firstLevel or level < firstLevel) then
            firstLevel = level
        end
    end
    return firstLevel
end

local function getWorldGoalProgress(rewardType, maximum)
    local maximumLevel = firstMaximumDelveLevel()
    local ok, entries = call(
        C_WeeklyRewards and C_WeeklyRewards.GetSortedProgressForActivity,
        rewardType,
        true
    )
    if not maximumLevel or not ok or type(entries) ~= "table" then
        return nil
    end

    local progress = 0
    for _, entry in ipairs(entries) do
        if tonumber(entry and entry.difficulty) and tonumber(entry.difficulty) >= maximumLevel then
            progress = progress + math.max(0, tonumber(entry.numPoints) or 0)
        end
    end
    return maximum > 0 and math.min(progress, maximum) or progress
end

local function buildGoal(rowKey, row, rewardType)
    -- This is intentionally not the normal activity count. The legacy Max-Belohnung
    -- track advances only for rewards already pushed to the row's target item level.
    -- World progress needs the sorted difficulty-point API because slot progress alone
    -- cannot distinguish maximum-level delves from lower-level completions.
    local maximum = tonumber(row.thresholds[#row.thresholds]) or 0
    local target = targetItemLevel(rowKey, row.slots)
    local displayed = rowKey == "world" and getWorldGoalProgress(rewardType, maximum) or nil
    local source = displayed ~= nil and "sorted-maximum-level" or nil
    if displayed == nil and target > 0 then
        source = "reward-item-level"
        displayed = 0
        for _, slot in ipairs(row.slots) do
            if (tonumber(slot.rewardItemLevel) or 0) >= target then
                displayed = math.max(displayed, tonumber(slot.threshold) or 0)
            end
        end
    end
    if displayed == nil then
        source = "fallback-progress"
        displayed = maximum > 0 and math.min(row.completedCount, maximum) or row.completedCount
    end

    local missingToNext = 0
    for _, threshold in ipairs(row.thresholds) do
        if displayed < threshold then
            missingToNext = threshold - displayed
            break
        end
    end
    local missingToMax = maximum > 0 and math.max(0, maximum - displayed) or 0
    local slots = {}
    for index, slot in ipairs(row.slots) do
        local threshold = tonumber(slot.threshold) or 0
        local count = threshold > 0 and math.min(displayed, threshold) or 0
        local remaining = threshold > 0 and math.max(0, threshold - displayed) or 0
        slots[index] = {
            threshold = threshold,
            count = count,
            countText = string.format("%d/%d", count, threshold),
            displayText = threshold <= 0 and "--"
                or (remaining <= 0 and L.VAULT_GOAL_REACHED or string.format(L.VAULT_GOAL_LEFT, remaining)),
        }
    end

    return {
        label = L.VAULT_GOAL_LABEL,
        displayCount = displayed,
        maxThreshold = maximum,
        displayCountText = string.format("%d/%d", displayed, maximum),
        displayText = maximum <= 0 and "--"
            or (missingToMax <= 0 and L.VAULT_GOAL_REACHED or string.format(L.VAULT_MAX_REWARD_LEFT, missingToMax)),
        slots = slots,
        missingToNext = missingToNext,
        missingToMax = missingToMax,
        targetItemLevel = target,
        source = source,
    }
end

local function buildRow(rowInfo, activities)
    local ordered = {}
    for index, activity in ipairs(activities) do
        ordered[index] = activity
    end
    table.sort(ordered, function(a, b)
        return (tonumber(a and a.index) or 0) < (tonumber(b and b.index) or 0)
    end)

    local row = {
        key = rowInfo.key,
        label = rowInfo.label,
        thresholds = {},
        slots = {},
        completedCount = 0,
        advice = {},
    }
    local bestItemLevel, bestLabel
    for index = 1, math.min(#ordered, 3) do
        local activity = ordered[index]
        local threshold = math.max(0, tonumber(activity.threshold) or 0)
        local progress = math.max(0, tonumber(activity.progress) or 0)
        local itemLevel, rewardLink, upgradeItemLevel, upgradeLink = getRewardData(rowInfo.key, activity)
        local label = rewardLabel(activity, itemLevel)
        row.thresholds[#row.thresholds + 1] = threshold
        row.completedCount = math.max(row.completedCount, progress)
        row.slots[index] = {
            index = tonumber(activity.index) or index,
            threshold = threshold,
            progress = progress,
            level = tonumber(activity.level) or 0,
            activityTierID = tonumber(activity.activityTierID) or 0,
            rewardItemLevel = itemLevel,
            rewardLink = rewardLink,
            upgradeItemLevel = upgradeItemLevel,
            upgradeRewardLink = upgradeLink,
            rewardLabel = label,
        }
        if itemLevel and (not bestItemLevel or itemLevel > bestItemLevel) then
            bestItemLevel, bestLabel = itemLevel, label
        elseif not bestLabel and label then
            bestLabel = label
        end
    end

    row.advice.bestLabel = bestLabel
    row.goal = buildGoal(rowInfo.key, row, rowInfo.type)
    local maximum = tonumber(row.thresholds[#row.thresholds]) or 0
    local displayed = maximum > 0 and math.min(row.completedCount, maximum) or row.completedCount
    local missingToNext = 0
    for _, threshold in ipairs(row.thresholds) do
        if displayed < threshold then
            missingToNext = threshold - displayed
            break
        end
    end
    if maximum <= 0 then
        row.note = L.VAULT_ROW_NOTE_NONE
    elseif row.goal.missingToMax <= 0 then
        row.note = L.VAULT_ROW_NOTE_READY
    elseif missingToNext > 0 then
        row.note = string.format(L.VAULT_ROW_NOTE_PROGRESS, missingToNext, row.goal.missingToMax)
    else
        row.note = string.format(L.VAULT_ROW_NOTE_MAX_ONLY, row.goal.missingToMax)
    end
    return row
end

function Logic:BuildSnapshot(existingSnapshot)
    local layout = getLayout()
    if not layout or not C_WeeklyRewards or type(C_WeeklyRewards.GetActivities) ~= "function" then
        return nil
    end

    local secondsUntilReset, resetAt = Addon.WoWApi:GetWeeklyResetInfo(
        type(existingSnapshot) == "table" and existingSnapshot.resetAt or nil
    )
    local snapshot = {
        generatedAt = type(time) == "function" and time() or 0,
        resetAt = resetAt,
        rows = {},
        summary = {},
    }
    local existingRows = type(existingSnapshot) == "table" and existingSnapshot.rows or nil
    local hasRows = false

    for _, rowInfo in ipairs(layout) do
        local ok, activities = call(C_WeeklyRewards.GetActivities, rowInfo.type)
        if ok and type(activities) == "table" and #activities > 0 then
            snapshot.rows[rowInfo.key] = buildRow(rowInfo, activities)
            hasRows = true
        elseif type(existingRows) == "table" and existingRows[rowInfo.key] then
            snapshot.rows[rowInfo.key] = existingRows[rowInfo.key]
            hasRows = true
        end
    end

    if not hasRows then
        return nil
    end
    snapshot.summary.headline = string.format(
        L.VAULT_SUMMARY_RESET,
        Addon.WoWApi:FormatDurationShort(secondsUntilReset)
    )
    return snapshot
end
