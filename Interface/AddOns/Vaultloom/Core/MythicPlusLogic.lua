local _, Addon = ...

local L = Addon.L
local Data = Addon.Data.MYTHIC_PLUS
local Logic = {}
Addon.MythicPlusLogic = Logic
local WEEK_SECONDS = 7 * 24 * 60 * 60

local function numeric(value)
    return tonumber(value) or 0
end

local function safeCall(api, method, ...)
    if type(api) ~= "table" or type(api[method]) ~= "function" then
        return false
    end
    return pcall(api[method], ...)
end

local function mapInfo(mapID)
    local ok, name, _, timeLimit, texture, background = safeCall(C_ChallengeMode, "GetMapUIInfo", mapID)
    if not ok then return nil end
    return {
        name = type(name) == "string" and name ~= "" and name or string.format(L.MYTHIC_PLUS_MAP_FALLBACK, numeric(mapID)),
        timeLimitSec = numeric(timeLimit),
        texture = texture or background or Data.fallbackIcon,
    }
end

local function timestamp(dateInfo)
    if type(dateInfo) ~= "table" or type(time) ~= "function" then return nil end
    local ok, value = pcall(time, {
        year = numeric(dateInfo.year) > 0 and numeric(dateInfo.year) or 1970,
        month = numeric(dateInfo.month) > 0 and numeric(dateInfo.month) or 1,
        day = numeric(dateInfo.day or dateInfo.monthDay) > 0 and numeric(dateInfo.day or dateInfo.monthDay) or 1,
        hour = numeric(dateInfo.hour),
        min = numeric(dateInfo.minute or dateInfo.min),
        sec = numeric(dateInfo.second or dateInfo.sec),
    })
    return ok and value or nil
end

function Logic:FormatDuration(durationSec)
    local total = math.max(0, math.floor(numeric(durationSec)))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local seconds = total % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds) end
    return string.format("%d:%02d", minutes, seconds)
end

function Logic:FormatRelative(updatedAt)
    local age = math.max(0, (type(time) == "function" and time() or 0) - numeric(updatedAt))
    if age < 60 then return L.TIME_JUST_NOW end
    if age < 3600 then return string.format(L.TIME_MIN, math.floor(age / 60)) end
    if age < 86400 then return string.format(L.TIME_HOUR_MIN, math.floor(age / 3600), math.floor((age % 3600) / 60)) end
    return string.format(L.TIME_DAY_HOUR, math.floor(age / 86400), math.floor((age % 86400) / 3600))
end

function Logic:GetSnapshotFreshness(snapshot, currentTime, nextResetAt)
    if type(snapshot) ~= "table" then return "missing" end
    currentTime = tonumber(currentTime) or (type(time) == "function" and time() or 0)
    local updatedAt = numeric(snapshot.updatedAt)
    local resetAt = numeric(snapshot.resetAt)
    if resetAt > 0 and currentTime >= resetAt then return "stale" end

    if resetAt <= 0 and updatedAt > 0 and Addon.WoWApi
        and type(Addon.WoWApi.GetWeeklyResetInfo) == "function"
    then
        nextResetAt = numeric(nextResetAt)
        if nextResetAt <= 0 then
            local _, apiResetAt = Addon.WoWApi:GetWeeklyResetInfo()
            nextResetAt = numeric(apiResetAt)
        end
        local previousResetAt = nextResetAt - WEEK_SECONDS
        if previousResetAt > 0 and updatedAt < previousResetAt then return "stale" end
    end

    if updatedAt <= 0 or (currentTime > 0 and currentTime - updatedAt > WEEK_SECONDS) then
        return "stale"
    end
    return "current"
end

function Logic:GetScoreColor(score)
    local value = numeric(score)
    local ok, color = safeCall(C_ChallengeMode, "GetDungeonScoreRarityColor", value)
    if ok and type(color) == "table" then
        return {
            tonumber(color.r or color[1]) or Addon.Theme.colors.gold[1],
            tonumber(color.g or color[2]) or Addon.Theme.colors.gold[2],
            tonumber(color.b or color[3]) or Addon.Theme.colors.gold[3],
            1,
        }
    end
    if value >= 3000 then return { 1.00, 0.55, 0.18, 1 } end
    if value >= 2500 then return { 0.73, 0.44, 0.98, 1 } end
    if value >= 2000 then return { 0.24, 0.72, 1.00, 1 } end
    if value >= 1500 then return { 0.34, 0.86, 0.52, 1 } end
    return Addon.Theme.colors.gold
end

local function bagKeystoneName()
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local getLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    if type(getSlots) ~= "function" or type(getLink) ~= "function" then return nil end
    for bag = 0, 4 do
        for slot = 1, numeric(getSlots(bag)) do
            local link = getLink(bag, slot)
            if type(link) == "string" and link:lower():find("keystone", 1, true) then
                local label = link:match("%[(.-)%]")
                if label then return label:gsub("^[Kk]eystone:%s*", "") end
            end
        end
    end
end

function Logic:GetCurrentKey()
    local _, level = safeCall(C_MythicPlus, "GetOwnedKeystoneLevel")
    local _, mapID = safeCall(C_MythicPlus, "GetOwnedKeystoneChallengeMapID")
    level, mapID = numeric(level), numeric(mapID)
    if level <= 0 or mapID <= 0 then
        local ok, activeLevel, activeMapID = safeCall(C_ChallengeMode, "GetActiveKeystoneInfo")
        if ok then
            level = math.max(level, numeric(activeLevel))
            mapID = math.max(mapID, numeric(activeMapID))
        end
    end
    local info = mapID > 0 and mapInfo(mapID) or nil
    return {
        level = level,
        mapChallengeModeID = mapID,
        name = info and info.name or bagKeystoneName(),
        texture = info and info.texture or Data.fallbackIcon,
    }
end

local function normalizedRun(info)
    if type(info) ~= "table" or numeric(info.level) <= 0 then return nil end
    return {
        level = numeric(info.level),
        durationSec = numeric(info.durationSec),
        dungeonScore = numeric(info.dungeonScore or info.runScore),
        completionDate = info.completionDate,
    }
end

local function chooseBest(intime, overtime)
    intime, overtime = normalizedRun(intime), normalizedRun(overtime)
    if intime and overtime then
        if intime.dungeonScore >= overtime.dungeonScore then return intime, "timed" end
        return overtime, "overtime"
    end
    if intime then return intime, "timed" end
    if overtime then return overtime, "overtime" end
end

function Logic:FormatRun(label, run, timeLimitSec)
    if type(run) ~= "table" or numeric(run.level) <= 0 then return nil end
    local status = numeric(run.durationSec) > 0 and numeric(timeLimitSec) > 0
        and (numeric(run.durationSec) <= numeric(timeLimitSec) and L.MYTHIC_PLUS_TIMED or L.MYTHIC_PLUS_OVERTIME)
        or nil
    local parts = { label, string.format("+%d", numeric(run.level)), self:FormatDuration(run.durationSec) }
    if numeric(run.durationSec) > 0 and numeric(timeLimitSec) > 0 then
        local delta = numeric(run.durationSec) - numeric(timeLimitSec)
        parts[#parts + 1] = (delta <= 0 and "-" or "+") .. self:FormatDuration(math.abs(delta))
    end
    if status then parts[#parts + 1] = status end
    return table.concat(parts, "  |  ")
end

local function affixSplit(mapID)
    local ok, scores = safeCall(C_MythicPlus, "GetSeasonBestAffixScoreInfoForMap", mapID)
    if not ok or type(scores) ~= "table" then return L.MYTHIC_PLUS_DUNGEON_SPLIT_NONE end
    local parts = {}
    for _, score in ipairs(scores) do
        local name = score.name
        if (not name or name == "") and score.affixID then
            local okName, value = safeCall(C_ChallengeMode, "GetAffixInfo", score.affixID)
            if okName then name = value end
        end
        local level = numeric(score.level or score.bestLevel or score.bestRunLevel)
        local value = numeric(score.score or score.dungeonScore or score.bestScore or score.bestOverAllScore)
        if type(name) == "string" and name ~= "" and (level > 0 or value > 0) then
            parts[#parts + 1] = level > 0 and string.format("%s +%d", name, level)
                or string.format("%s %d", name, math.floor(value + 0.5))
        end
    end
    return #parts > 0 and table.concat(parts, "  |  ") or L.MYTHIC_PLUS_DUNGEON_SPLIT_NONE
end

local function collectAffixes()
    local entries = {}
    local ok, affixes = safeCall(C_MythicPlus, "GetCurrentAffixes")
    if not ok or type(affixes) ~= "table" then return entries end
    for _, affix in ipairs(affixes) do
        local name, description = affix and affix.name, nil
        if affix and affix.id then
            local okInfo, apiName, apiDescription = safeCall(C_ChallengeMode, "GetAffixInfo", affix.id)
            if okInfo then name, description = name or apiName, apiDescription end
        end
        if type(name) == "string" and name ~= "" then
            entries[#entries + 1] = {
                label = name,
                text = L.MYTHIC_PLUS_AFFIX_ACTIVE,
                status = "open",
                hideStatusBadge = true,
                tooltipTitle = name,
                tooltipLines = description and { description } or nil,
            }
        end
    end
    return entries
end

local function collectGoals(score, timedCount)
    local entries = {}
    for _, goal in ipairs(Data.goals) do
        local complete = goal.timedRuns and timedCount >= goal.timedRuns
            or goal.score and score >= goal.score
        local near = goal.score and score >= numeric(goal.warningAt)
        entries[#entries + 1] = {
            key = goal.key,
            label = L[goal.labelKey],
            text = goal.timedRuns and string.format("%d/%d", math.min(timedCount, goal.timedRuns), goal.timedRuns)
                or goal.score and string.format("%d+", goal.score)
                or goal.percentile,
            status = complete and "complete" or near and "turnin" or goal.percentile and score > 0 and "open" or "missing",
            hideStatusBadge = true,
        }
    end
    return entries
end

local function collectRecentRuns()
    local entries = {}
    local ok, history = safeCall(C_MythicPlus, "GetRunHistory", true, false)
    if not ok or type(history) ~= "table" then return entries end
    for _, run in ipairs(history) do
        if #entries >= Data.maxRecentRuns then break end
        if type(run) == "table" and numeric(run.level) > 0 then
            local info = mapInfo(run.mapChallengeModeID)
            local name = info and info.name or L.UNKNOWN
            local parts = { run.completed and L.MYTHIC_PLUS_TIMED or L.MYTHIC_PLUS_OVERTIME }
            if numeric(run.runScore) > 0 then parts[#parts + 1] = tostring(math.floor(numeric(run.runScore) + 0.5)) end
            if run.thisWeek then parts[#parts + 1] = L.MYTHIC_PLUS_THIS_WEEK end
            entries[#entries + 1] = {
                mapChallengeModeID = numeric(run.mapChallengeModeID),
                name = name,
                level = numeric(run.level),
                score = numeric(run.runScore),
                timed = run.completed == true,
                thisWeek = run.thisWeek == true,
                label = string.format("%s  +%d", name, numeric(run.level)),
                text = table.concat(parts, "  |  "),
                status = run.completed and "complete" or "turnin",
                hideStatusBadge = true,
                tooltipTitle = name,
                tooltipLines = { string.format("+%d", numeric(run.level)) },
            }
        end
    end
    return entries
end

function Logic:Scan()
    if type(C_ChallengeMode) ~= "table" or type(C_MythicPlus) ~= "table"
        or type(C_ChallengeMode.GetMapTable) ~= "function"
        or type(C_ChallengeMode.GetMapUIInfo) ~= "function"
    then
        return nil
    end

    safeCall(C_MythicPlus, "RequestMapInfo")
    safeCall(C_ChallengeMode, "RequestMapInfo")
    safeCall(C_MythicPlus, "RequestCurrentAffixes")
    safeCall(C_MythicPlus, "RequestRewards")

    local okMaps, mapIDs = safeCall(C_ChallengeMode, "GetMapTable")
    if not okMaps or type(mapIDs) ~= "table" or #mapIDs == 0 then return nil end
    local score = 0
    local okScore, apiScore = safeCall(C_ChallengeMode, "GetOverallDungeonScore")
    if okScore then score = numeric(apiScore) end
    if score <= 0 then
        local okSummary, summary = safeCall(C_PlayerInfo, "GetPlayerMythicPlusRatingSummary", "player")
        if okSummary and type(summary) == "table" then score = numeric(summary.currentSeasonScore) end
    end
    local okWeekly, weeklyBest, rewardLevel = safeCall(C_MythicPlus, "GetWeeklyChestRewardLevel")
    if not okWeekly then weeklyBest, rewardLevel = 0, 0 end

    local dungeons, timedCount, portalCount = {}, 0, 0
    for _, mapID in ipairs(mapIDs) do
        local info = mapInfo(mapID)
        if info then
            local _, intime, overtime = safeCall(C_MythicPlus, "GetSeasonBestForMap", mapID)
            local best, bestStatus = chooseBest(intime, overtime)
            local weekly
            local okRun, durationSec, level, completionDate, _, _, dungeonScore =
                safeCall(C_MythicPlus, "GetWeeklyBestForMap", mapID)
            if okRun and numeric(level) > 0 then
                weekly = {
                    durationSec = numeric(durationSec),
                    level = numeric(level),
                    completionDate = completionDate,
                    dungeonScore = numeric(dungeonScore),
                }
            end
            local timed = normalizedRun(intime)
            if timed then
                timedCount = timedCount + 1
                if timed.level >= Data.portalLevel then portalCount = portalCount + 1 end
            end
            local bestText = self:FormatRun(L.MYTHIC_PLUS_BEST, best, info.timeLimitSec) or L.MYTHIC_PLUS_DUNGEON_BEST_NONE
            local weeklyText = self:FormatRun(L.MYTHIC_PLUS_THIS_WEEK, weekly, info.timeLimitSec) or L.MYTHIC_PLUS_DUNGEON_WEEKLY_NONE
            local splitText = affixSplit(mapID)
            dungeons[#dungeons + 1] = {
                mapChallengeModeID = numeric(mapID),
                name = info.name,
                texture = info.texture,
                timeLimitSec = info.timeLimitSec,
                best = best,
                weekly = weekly,
                bestStatus = bestStatus,
                score = numeric(best and best.dungeonScore or weekly and weekly.dungeonScore),
                bestText = bestText,
                weeklyText = weeklyText,
                splitText = splitText,
                tooltipTitle = info.name,
                tooltipLines = { bestText, weeklyText, splitText },
                completedAt = timestamp(best and best.completionDate),
            }
        end
    end

    local key = self:GetCurrentKey()
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    score = math.floor(score + 0.5)
    local snapshot = {
        available = true,
        seasonKey = Data.seasonKey,
        updatedAt = type(time) == "function" and time() or 0,
        resetAt = numeric(resetAt),
        currentWeekBestLevel = numeric(weeklyBest),
        weeklyRewardLevel = numeric(rewardLevel),
        currentKey = key,
        timedCount = timedCount,
        portalCount = portalCount,
        dungeonCount = #dungeons,
        dungeons = dungeons,
        affixes = collectAffixes(),
        rewards = collectGoals(score, timedCount),
        recentRuns = collectRecentRuns(),
    }
    snapshot.summary = {
        score = {
            label = L.MYTHIC_PLUS_SUMMARY_SCORE,
            value = tostring(score),
            meta = string.format("%d/%d %s", timedCount, #dungeons, L.MYTHIC_PLUS_TIMED_META),
            score = score,
        },
        key = {
            label = L.MYTHIC_PLUS_SUMMARY_KEY,
            value = key.level > 0 and string.format("+%d", key.level) or L.MYTHIC_PLUS_KEY_NONE,
            meta = key.name or "",
        },
        vault = {
            label = L.MYTHIC_PLUS_SUMMARY_VAULT,
            value = numeric(rewardLevel) > 0 and string.format("+%d", numeric(rewardLevel)) or L.MYTHIC_PLUS_VAULT_NONE,
            meta = numeric(weeklyBest) > 0 and string.format("%s  +%d", L.MYTHIC_PLUS_THIS_WEEK, numeric(weeklyBest))
                or L.MYTHIC_PLUS_VAULT_NONE,
        },
        portals = {
            label = L.MYTHIC_PLUS_SUMMARY_PORTALS,
            value = string.format("%d/%d", portalCount, #dungeons),
            meta = L.MYTHIC_PLUS_PORTALS_META,
        },
    }
    return snapshot
end

function Logic:BuildView(snapshot)
    if type(snapshot) ~= "table" or snapshot.seasonKey ~= Data.seasonKey then
        return {
            available = false,
            message = L.MYTHIC_PLUS_NO_SNAPSHOT,
            dungeons = {},
            affixes = {},
            rewards = {},
            recentRuns = {},
        }
    end
    return snapshot
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function getSnapshotScore(snapshot)
    return numeric(snapshot and snapshot.summary and snapshot.summary.score
        and snapshot.summary.score.score)
end

local function buildVaultStatus(snapshot)
    local row = type(snapshot) == "table" and type(snapshot.rows) == "table"
        and snapshot.rows.dungeon or nil
    local slots, unlocked = {}, 0
    local storedSlots = type(row) == "table" and type(row.slots) == "table" and row.slots or {}
    local sourceSlots = {}
    for index, slot in ipairs(storedSlots) do sourceSlots[index] = slot end
    if #sourceSlots == 0 and type(row) == "table" and type(row.thresholds) == "table" then
        for index, threshold in ipairs(row.thresholds) do
            sourceSlots[index] = {
                threshold = threshold,
                progress = row.completedCount,
            }
        end
    end
    for index, slot in ipairs(sourceSlots) do
        local threshold = numeric(slot.threshold)
        local progress = math.max(numeric(slot.progress), numeric(row.completedCount))
        local isUnlocked = threshold > 0 and progress >= threshold
        if isUnlocked then unlocked = unlocked + 1 end
        slots[index] = {
            threshold = threshold,
            progress = progress,
            unlocked = isUnlocked,
            level = numeric(slot.level),
            rewardItemLevel = numeric(slot.rewardItemLevel),
            rewardLabel = slot.rewardLabel,
        }
    end
    local total = #slots
    local completedCount = numeric(row and row.completedCount)
    local status = total <= 0 and "none"
        or unlocked >= total and "complete"
        or (unlocked > 0 or completedCount > 0) and "progress"
        or "open"
    return {
        status = status,
        slots = slots,
        unlocked = unlocked,
        total = total,
        completedCount = completedCount,
        note = row and row.note,
        missingToMax = numeric(row and row.goal and row.goal.missingToMax),
    }
end

local function getDungeonKey(dungeon)
    local mapID = numeric(dungeon and dungeon.mapChallengeModeID)
    if mapID > 0 then return tostring(mapID) end
    local name = lower(dungeon and dungeon.name)
    return name ~= "" and "name:" .. name or nil
end

function Logic:BuildWarbandOverview(roster, getSnapshot, getVaultSnapshot, isHidden, currentTime)
    roster = type(roster) == "table" and roster or {}
    currentTime = tonumber(currentTime) or (type(time) == "function" and time() or 0)
    local overview = {
        entries = {},
        dungeons = {},
        currentRealm = nil,
        resetAt = 0,
        resetSeconds = 0,
        summary = {
            characters = #roster,
            keys = 0,
            vaultComplete = 0,
            current = 0,
            stale = 0,
            missing = 0,
        },
    }
    if Addon.WoWApi and type(Addon.WoWApi.GetWeeklyResetInfo) == "function" then
        overview.resetSeconds, overview.resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    end

    local dungeonCatalog, nextDungeonOrder = {}, 0
    for _, character in ipairs(roster) do
        local snapshot = type(getSnapshot) == "function" and getSnapshot(character.key) or nil
        local vaultSnapshot = type(getVaultSnapshot) == "function" and getVaultSnapshot(character.key) or nil
        local freshness = self:GetSnapshotFreshness(snapshot, currentTime, overview.resetAt)
        local key = type(snapshot) == "table" and snapshot.currentKey or nil
        local vault = buildVaultStatus(vaultSnapshot)
        local entry = {
            characterKey = character.key,
            name = character.name or character.key,
            realm = character.realm,
            classFile = character.classFile,
            className = character.className,
            itemLevel = tonumber(character.itemLevel),
            level = numeric(character.level),
            isCurrent = character.isCurrent == true,
            isMain = character.isMain == true,
            isHidden = type(isHidden) == "function" and isHidden(character.key) == true,
            freshness = freshness,
            updatedAt = numeric(snapshot and snapshot.updatedAt),
            hasSnapshot = type(snapshot) == "table",
            keyLevel = numeric(key and key.level),
            keyName = key and key.name,
            keyTexture = key and key.texture or Data.fallbackIcon,
            score = getSnapshotScore(snapshot),
            weeklyBestLevel = freshness == "current" and numeric(snapshot and snapshot.currentWeekBestLevel) or 0,
            weeklyRewardLevel = freshness == "current" and numeric(snapshot and snapshot.weeklyRewardLevel) or 0,
            timedCount = numeric(snapshot and snapshot.timedCount),
            portalCount = numeric(snapshot and snapshot.portalCount),
            dungeonCount = numeric(snapshot and snapshot.dungeonCount),
            vault = vault,
            recentRuns = type(snapshot) == "table" and type(snapshot.recentRuns) == "table"
                and snapshot.recentRuns or {},
            dungeons = type(snapshot) == "table" and type(snapshot.dungeons) == "table"
                and snapshot.dungeons or {},
            dungeonsByKey = {},
        }
        if entry.isCurrent then overview.currentRealm = entry.realm end
        if entry.keyLevel > 0 then overview.summary.keys = overview.summary.keys + 1 end
        if vault.status == "complete" then
            overview.summary.vaultComplete = overview.summary.vaultComplete + 1
        end
        overview.summary[freshness] = numeric(overview.summary[freshness]) + 1

        for _, dungeon in ipairs(entry.dungeons) do
            local dungeonKey = getDungeonKey(dungeon)
            if dungeonKey then
                entry.dungeonsByKey[dungeonKey] = dungeon
                if not dungeonCatalog[dungeonKey] then
                    nextDungeonOrder = nextDungeonOrder + 1
                    dungeonCatalog[dungeonKey] = {
                        key = dungeonKey,
                        mapChallengeModeID = numeric(dungeon.mapChallengeModeID),
                        name = dungeon.name or L.UNKNOWN,
                        texture = dungeon.texture or Data.fallbackIcon,
                        order = nextDungeonOrder,
                    }
                end
            end
        end

        if freshness == "current" then
            if vault.status == "progress" then
                entry.attentionRank = 1
            elseif entry.keyLevel > 0 and vault.status ~= "complete" then
                entry.attentionRank = 2
            elseif entry.score > 0 and vault.status ~= "complete" then
                entry.attentionRank = 3
            else
                entry.attentionRank = 4
            end
        else
            entry.attentionRank = freshness == "stale" and 5 or 6
        end
        overview.entries[#overview.entries + 1] = entry
    end

    for _, dungeon in pairs(dungeonCatalog) do
        overview.dungeons[#overview.dungeons + 1] = dungeon
    end
    table.sort(overview.dungeons, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return lower(a.name) < lower(b.name)
    end)
    return overview
end

local function matchesSearch(entry, query)
    if query == "" then return true end
    if lower(entry.name):find(query, 1, true)
        or lower(entry.realm):find(query, 1, true)
        or lower(entry.className):find(query, 1, true)
        or lower(entry.classFile):find(query, 1, true)
        or lower(entry.keyName):find(query, 1, true)
    then
        return true
    end
    for _, dungeon in ipairs(entry.dungeons or {}) do
        if lower(dungeon.name):find(query, 1, true) then return true end
    end
    return false
end

function Logic:FilterWarbandOverview(overview, filters)
    overview = type(overview) == "table" and overview or {}
    filters = type(filters) == "table" and filters or {}
    local query = lower(filters.search)
    local realmFilter = filters.realmFilter or "all"
    local keyFilter = filters.keyFilter or "all"
    local vaultFilter = filters.vaultFilter or "all"
    local dataFilter = filters.dataFilter or "all"
    local entries = {}
    for _, entry in ipairs(type(overview.entries) == "table" and overview.entries or {}) do
        local realmMatches = realmFilter == "all"
            or (realmFilter == "current" and entry.realm == overview.currentRealm)
            or entry.realm == tostring(realmFilter):match("^realm:(.+)")
        local keyMatches = keyFilter == "all"
            or (keyFilter == "with_key" and entry.keyLevel > 0)
            or (keyFilter == "without_key" and entry.keyLevel <= 0)
        local vaultMatches = vaultFilter == "all"
            or entry.vault.status == vaultFilter
        local dataMatches = dataFilter == "all" or entry.freshness == dataFilter
        if realmMatches and keyMatches and vaultMatches and dataMatches
            and matchesSearch(entry, query)
        then
            entries[#entries + 1] = entry
        end
    end

    local sortMode = filters.sortMode or "attention"
    table.sort(entries, function(a, b)
        if sortMode == "key" and a.keyLevel ~= b.keyLevel then
            return a.keyLevel > b.keyLevel
        elseif sortMode == "score" and a.score ~= b.score then
            return a.score > b.score
        elseif sortMode == "vault" then
            if a.vault.unlocked ~= b.vault.unlocked then return a.vault.unlocked < b.vault.unlocked end
            if a.vault.completedCount ~= b.vault.completedCount then
                return a.vault.completedCount < b.vault.completedCount
            end
        elseif sortMode == "attention" and a.attentionRank ~= b.attentionRank then
            return a.attentionRank < b.attentionRank
        end
        if sortMode ~= "name" then
            if a.isMain ~= b.isMain then return a.isMain end
            if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        end
        local left, right = lower(a.name), lower(b.name)
        if left ~= right then return left < right end
        return lower(a.realm) < lower(b.realm)
    end)
    return entries
end
