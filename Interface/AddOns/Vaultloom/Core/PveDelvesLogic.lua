local _, Addon = ...

local L = Addon.L
local QuestApi = Addon.QuestApi
local DATA = Addon.Data.PVE_DELVES

local Logic = {}
Addon.PveDelvesLogic = Logic

local function copyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = value
    end
    return copy
end

local function findRow(snapshot, key)
    for _, row in ipairs(type(snapshot) == "table" and snapshot.rows or {}) do
        if type(row) == "table" and row.key == key then
            return row
        end
    end
    return nil
end

local function buildTrovehuntersBountyRow()
    local itemCount = Addon.WoWApi:GetItemCount(DATA.trovehuntersBountyItemID)
    local used = QuestApi:IsCompleted(DATA.trovehuntersBountyFlagQuestID)
    local unlocked = Addon.WoWApi:GetCurrentRenownLevel(DATA.trovehuntersUnlockFactionID) >= DATA.trovehuntersUnlockRenown
        or itemCount > 0
        or used
    local text, status, tooltip
    if itemCount > 0 then
        text, status, tooltip = L.PVE_DELVES_READY, "open", L.PVE_DELVES_TROVEHUNTER_OPEN_HINT
    elseif used then
        text, status, tooltip = L.PVE_DELVES_STATUS_DONE, "complete", L.PVE_DELVES_TROVEHUNTER_DONE_HINT
    elseif unlocked then
        text, status, tooltip = L.PVE_DELVES_NOT_EARNED, "failed", L.PVE_DELVES_TROVEHUNTER_MISSING_HINT
    else
        text, status = L.PVE_DELVES_STATUS_LOCKED, "locked"
        tooltip = string.format(L.PVE_DELVES_TROVEHUNTER_LOCKED_HINT, DATA.trovehuntersUnlockRenown)
    end
    local tooltipLines = { tooltip }
    if itemCount > 0 then
        tooltipLines[#tooltipLines + 1] = string.format(L.PVE_DELVES_INVENTORY_COUNT, itemCount)
    end
    return {
        key = "delve_trovehunters_bounty",
        label = L.PVE_DELVES_TROVEHUNTER_LABEL,
        text = text,
        status = status,
        seen = unlocked,
        completed = used and itemCount <= 0,
        itemID = DATA.trovehuntersBountyItemID,
        tooltipTitle = L.PVE_DELVES_TROVEHUNTER_LABEL,
        tooltipLines = tooltipLines,
    }
end

local function buildWeeklyDropRow(memory)
    local questID = DATA.weeklyDropQuestID
    local completed = QuestApi:IsCompletedOnAccount(questID)
        or QuestApi:IsCompleted(questID)
        or (type(memory) == "table" and memory.weeklyDropCompleted == true)
    local active = QuestApi:IsActive(questID)
    local ready = active and QuestApi:IsTurnInReady(questID)
    local tooltipLines = { L.PVE_DELVES_WEEKLY_DROP_HINT }
    if active and not completed then
        local objectiveLines = QuestApi:GetObjectiveLines(questID)
        if #objectiveLines > 0 then
            tooltipLines[#tooltipLines + 1] = " "
            for _, line in ipairs(objectiveLines) do
                tooltipLines[#tooltipLines + 1] = line
            end
        end
    end
    if completed then
        if type(memory) == "table" then
            memory.weeklyDropCompleted = true
            memory.weeklyDropQuestID = questID
        end
        return {
            key = "delve_weekly_drop", label = L.PVE_DELVES_WEEKLY_DROP_LABEL,
            text = L.PVE_DELVES_STATUS_DONE, status = "complete", seen = true, completed = true,
            questID = questID, accountWide = true,
            tooltipTitle = L.PVE_DELVES_WEEKLY_DROP_LABEL, tooltipLines = tooltipLines,
        }
    end
    if ready then
        return {
            key = "delve_weekly_drop", label = L.PVE_DELVES_WEEKLY_DROP_LABEL,
            text = L.PVE_DELVES_STATUS_TURNIN, status = "turnin", seen = true, completed = false,
            questID = questID, turnInQuestID = questID, accountWide = true,
            tooltipTitle = L.PVE_DELVES_WEEKLY_DROP_LABEL, tooltipLines = tooltipLines,
        }
    end
    if active then
        return {
            key = "delve_weekly_drop", label = L.PVE_DELVES_WEEKLY_DROP_LABEL,
            text = QuestApi:GetObjectiveProgressText(questID) or L.PVE_DELVES_STATUS_OPEN,
            status = "open", seen = true, completed = false, questID = questID, accountWide = true,
            tooltipTitle = L.PVE_DELVES_WEEKLY_DROP_LABEL, tooltipLines = tooltipLines,
        }
    end
    return {
        key = "delve_weekly_drop", label = L.PVE_DELVES_WEEKLY_DROP_LABEL,
        text = L.PVE_DELVES_NOT_EARNED, status = "missing", seen = false, completed = false,
        questID = questID, accountWide = true,
        tooltipTitle = L.PVE_DELVES_WEEKLY_DROP_LABEL, tooltipLines = tooltipLines,
    }
end

local function buildBonusRenownRow()
    local completedCount, tooltipLines = 0, {}
    for _, definition in ipairs(DATA.bonusRenownFlags) do
        local completed = QuestApi:IsCompletedOnAccount(definition.questID)
        if completed then
            completedCount = completedCount + 1
        end
        tooltipLines[#tooltipLines + 1] = string.format(
            "%s: %s",
            Addon.WoWApi:GetMajorFactionName(definition.factionID, definition.fallbackName),
            completed and L.PVE_DELVES_STATUS_DONE or L.PVE_DELVES_READY
        )
    end
    tooltipLines[#tooltipLines + 1] = " "
    tooltipLines[#tooltipLines + 1] = L.PVE_DELVES_BONUS_RENOWN_HINT
    local total = #DATA.bonusRenownFlags
    return {
        key = "delve_bonus_renown",
        label = L.PVE_DELVES_BONUS_RENOWN_LABEL,
        text = string.format("%d/%d", completedCount, total),
        status = completedCount >= total and "complete" or "open",
        seen = true,
        completed = completedCount >= total,
        count = completedCount,
        maxCount = total,
        tooltipTitle = L.PVE_DELVES_BONUS_RENOWN_LABEL,
        tooltipLines = tooltipLines,
    }
end

local function getGildedStashWidgetState()
    if not (C_UIWidgetManager and type(C_UIWidgetManager.GetSpellDisplayVisualizationInfo) == "function") then
        return nil
    end
    local ok, info = pcall(C_UIWidgetManager.GetSpellDisplayVisualizationInfo, DATA.gildedStashWidgetID)
    local spellInfo = ok and type(info) == "table" and type(info.spellInfo) == "table" and info.spellInfo or nil
    if not spellInfo or tonumber(spellInfo.spellID) ~= DATA.gildedStashSpellID then
        return nil
    end
    local current, maximum = QuestApi:ParseObjectiveFraction(spellInfo.tooltip or "")
    return {
        current = current,
        maximum = maximum,
        isAccurate = spellInfo.shownState == 1,
        tooltip = spellInfo.tooltip,
        spellName = Addon.WoWApi:GetSpellName(DATA.gildedStashSpellID, L.PVE_DELVES_GILDED_STASH_LABEL),
    }
end

local function buildGildedStashRow(existingSnapshot)
    local widget = getGildedStashWidgetState()
    local tooltipTitle = widget and widget.spellName or L.PVE_DELVES_GILDED_STASH_LABEL
    local tooltipLines = { L.PVE_DELVES_GILDED_STASH_HINT }
    if widget and type(widget.tooltip) == "string" and widget.tooltip ~= "" then
        tooltipLines[#tooltipLines + 1] = " "
        tooltipLines[#tooltipLines + 1] = widget.tooltip
        if not widget.isAccurate then
            tooltipLines[#tooltipLines + 1] = L.PVE_DELVES_GILDED_STASH_STALE_HINT
        end
    else
        tooltipLines[#tooltipLines + 1] = L.PVE_DELVES_GILDED_STASH_NO_DATA
    end
    local current = widget and tonumber(widget.current) or nil
    local maximum = widget and tonumber(widget.maximum) or nil
    if current and maximum and maximum > 0 then
        return {
            key = "delve_gilded_stash", label = L.PVE_DELVES_GILDED_STASH_LABEL,
            text = string.format("%d/%d", current, maximum),
            status = current >= maximum and "complete" or "open",
            seen = true, completed = current >= maximum, count = current, maxCount = maximum,
            tooltipTitle = tooltipTitle, tooltipLines = tooltipLines,
        }
    end
    local stored = findRow(existingSnapshot, "delve_gilded_stash")
    if tonumber(stored and stored.count) and (tonumber(stored and stored.maxCount) or 0) > 0 then
        local preserved = copyTable(stored)
        preserved.tooltipTitle = tooltipTitle or preserved.tooltipTitle
        preserved.tooltipLines = tooltipLines
        return preserved
    end
    return {
        key = "delve_gilded_stash", label = L.PVE_DELVES_GILDED_STASH_LABEL,
        text = string.format("?/%d", DATA.gildedStashFallbackMaximum),
        status = "locked", seen = false, completed = false,
        tooltipTitle = tooltipTitle, tooltipLines = tooltipLines,
    }
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
        buildTrovehuntersBountyRow(),
        buildWeeklyDropRow(memory),
        buildBonusRenownRow(),
        buildGildedStashRow(existingSnapshot),
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
