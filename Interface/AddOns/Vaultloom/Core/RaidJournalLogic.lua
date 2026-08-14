local _, Addon = ...

local L = Addon.L
local DATA = Addon.Data.RAIDS
local Logic = {}
Addon.RaidJournalLogic = Logic

local function now()
    return type(time) == "function" and time() or 0
end

local function number(value)
    return tonumber(value)
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, entry in pairs(value) do result[copy(key, seen)] = copy(entry, seen) end
    return result
end

function Logic:NormalizeKey(value)
    local text = string.lower(tostring(value or ""))
    text = text:gsub("Ä", "a"):gsub("ä", "a")
    text = text:gsub("Ö", "o"):gsub("ö", "o")
    text = text:gsub("Ü", "u"):gsub("ü", "u")
    text = text:gsub("ß", "ss")
    text = text:gsub("[^%w]+", "-"):gsub("%-+", "-")
    return text:gsub("^%-", ""):gsub("%-$", "")
end

function Logic:IsDifficultyKey(key)
    return DATA.difficultyIDs[key] ~= nil
end

function Logic:GetContentType(instanceID, raidKey)
    local mappings = type(DATA.instanceContentTypes) == "table" and DATA.instanceContentTypes or {}
    local byInstanceID = type(mappings.byInstanceID) == "table" and mappings.byInstanceID or {}
    local byKey = type(mappings.byKey) == "table" and mappings.byKey or {}
    local contentType = byInstanceID[number(instanceID)] or byKey[self:NormalizeKey(raidKey)] or "raid"
    if type(contentType) == "table" then contentType = contentType.key end
    return DATA.contentTypes[contentType] and contentType or "raid"
end

function Logic:IsSnapshotValid(snapshot, currentTime)
    currentTime = number(currentTime) or now()
    return type(snapshot) == "table"
        and Addon.WoWApi:GetResetState(snapshot.resetAt, currentTime) ~= Addon.WoWApi.RESET_EXPIRED
end

local function fallbackSnapshot(resetAt, currentTime, reason)
    local raids = {}
    for index, definition in ipairs(DATA.fallbackRaids) do
        raids[#raids + 1] = {
            key = definition.key,
            name = string.format("%s %d", L.WISHLIST_SOURCE_RAID or L.SCREEN_RAIDS or "Raid", index),
            description = L.RAID_JOURNAL_UNAVAILABLE,
            icon = definition.icon,
            contentType = definition.contentType or "raid",
            bosses = {},
        }
    end
    return {
        updatedAt = currentTime,
        resetAt = resetAt,
        source = "fallback",
        unavailableReason = reason,
        raids = raids,
    }
end

local function findMidnightTier()
    if type(EJ_GetNumTiers) ~= "function" then
        return nil, "api-unavailable"
    end
    local okCount, tierCount = pcall(EJ_GetNumTiers)
    if not okCount then return nil, "tier-scan-failed" end
    tierCount = math.max(0, math.floor(number(tierCount) or 0))
    if tierCount == 0 then return nil, "midnight-tier-missing" end
    -- Encounter Journal tier names are localized by the WoW client. Looking
    -- for the English word "Midnight" therefore fails on Korean and other
    -- clients. Tiers are chronological, so the newest expansion is last.
    return tierCount
end

local function readLockouts(difficultyID, isCurrentCharacter, normalize)
    if not isCurrentCharacter then return {}, false end
    if type(GetNumSavedInstances) ~= "function"
        or type(GetSavedInstanceInfo) ~= "function"
        or type(GetSavedInstanceEncounterInfo) ~= "function"
    then
        return {}, false
    end
    local result = {}
    local okCount, instanceCount = pcall(GetNumSavedInstances)
    if not okCount then return {}, false end
    for instanceIndex = 1, number(instanceCount) or 0 do
        local ok, name, _, _, savedDifficultyID, locked, _, _, isRaid, _, _, encounterTotal, encounterProgress =
            pcall(GetSavedInstanceInfo, instanceIndex)
        if ok and isRaid == true and locked == true and number(savedDifficultyID) == number(difficultyID)
            and type(name) == "string" and name ~= ""
        then
            local entry = {
                name = name,
                progress = number(encounterProgress) or 0,
                total = number(encounterTotal) or 0,
                kills = {},
            }
            for encounterIndex = 1, entry.total do
                local encounterOk, bossName, _, killed = pcall(GetSavedInstanceEncounterInfo, instanceIndex, encounterIndex)
                if encounterOk and type(bossName) == "string" and bossName ~= "" then
                    entry.kills[normalize(bossName)] = killed == true
                end
            end
            result[normalize(name)] = entry
        end
    end
    return result, true
end

local function oldRaidByKey(existing)
    local result = {}
    for _, raid in ipairs(type(existing) == "table" and existing.raids or {}) do
        if type(raid) == "table" and type(raid.key) == "string" then result[raid.key] = raid end
    end
    return result
end

local function oldRaidByInstanceID(existing)
    local result = {}
    for _, raid in ipairs(type(existing) == "table" and existing.raids or {}) do
        local instanceID = number(type(raid) == "table" and raid.instanceID)
        if instanceID then result[instanceID] = raid end
    end
    return result
end

local function oldBossByKey(raid)
    local result = {}
    for _, boss in ipairs(type(raid) == "table" and raid.bosses or {}) do
        if type(boss) == "table" and type(boss.key) == "string" then result[boss.key] = boss end
    end
    return result
end

local function getInstanceInfo(instanceID)
    if type(EJ_GetInstanceInfo) ~= "function" then return nil end
    if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end
    local ok, name, description, background, buttonImage1, _, buttonImage2, _, _, _, mapID =
        pcall(EJ_GetInstanceInfo, instanceID)
    if not ok or type(name) ~= "string" or name == "" then return nil end
    return {
        instanceID = number(instanceID),
        name = name,
        description = type(description) == "string" and description or "",
        icon = buttonImage1 or buttonImage2 or background,
        mapID = number(mapID),
    }
end

local function getJournalCatalog()
    local catalog = {}
    for _, instanceID in ipairs(DATA.journalInstanceIDs or {}) do
        local info = getInstanceInfo(instanceID)
        if info then catalog[#catalog + 1] = info end
    end
    if #catalog > 0 then return catalog, true end

    if type(EJ_GetInstanceByIndex) ~= "function" then return catalog, false end
    local index = 1
    while true do
        local ok, instanceID, name, description = pcall(EJ_GetInstanceByIndex, index, true)
        if not ok or not instanceID then break end
        local info = getInstanceInfo(instanceID) or {
            instanceID = number(instanceID),
            name = name,
            description = type(description) == "string" and description or "",
        }
        if type(info.name) == "string" and info.name ~= "" then catalog[#catalog + 1] = info end
        index = index + 1
    end
    return catalog, false
end

local function getDifficultyValidity()
    if type(EJ_IsValidInstanceDifficulty) ~= "function" then return nil end
    local result, observed = {}, false
    for difficultyKey, difficultyID in pairs(DATA.difficultyIDs or {}) do
        if type(EJ_SetDifficulty) == "function" then pcall(EJ_SetDifficulty, difficultyID) end
        local ok, valid = pcall(EJ_IsValidInstanceDifficulty, difficultyID)
        if ok then
            result[difficultyKey] = valid == true
            observed = true
        end
    end
    return observed and result or nil
end

local function scanEncounterCatalog(instanceID, preferredDifficultyKey, availableDifficulties)
    local keys, seen = {}, {}
    local function add(key)
        if DATA.difficultyIDs[key] and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    add(preferredDifficultyKey)
    add("normal")
    add("lfr")
    add("heroic")
    add("mythic")

    for _, difficultyKey in ipairs(keys) do
        if not availableDifficulties or availableDifficulties[difficultyKey] ~= false then
            if type(EJ_SetDifficulty) == "function" then
                pcall(EJ_SetDifficulty, DATA.difficultyIDs[difficultyKey])
            end
            local encounters, index = {}, 1
            while true do
                local ok, bossName, bossDescription, encounterID, _, _, _, dungeonEncounterID =
                    pcall(EJ_GetEncounterInfoByIndex, index, instanceID)
                if not ok or not bossName then break end
                encounters[#encounters + 1] = {
                    name = bossName,
                    description = type(bossDescription) == "string" and bossDescription or "",
                    encounterID = number(encounterID),
                    dungeonEncounterID = number(dungeonEncounterID),
                }
                index = index + 1
            end
            if #encounters > 0 then return encounters end
        end
    end
    return {}
end

local function exactEncounterCompletion(mapID, dungeonEncounterID, difficultyID)
    local api = type(C_RaidLocks) == "table" and C_RaidLocks.IsEncounterComplete or nil
    if type(api) ~= "function" or not number(mapID) or not number(dungeonEncounterID) then
        return false, false
    end
    local ok, completed = pcall(api, mapID, dungeonEncounterID, difficultyID)
    if not ok or type(completed) ~= "boolean" then return false, false end
    return completed == true, true
end

local function achievementEarnedThisReset(achievementID)
    achievementID = number(achievementID)
    if not achievementID or type(GetAchievementInfo) ~= "function" then return false, false end

    local ok, _, _, _, completed, month, day, year, _, _, _, _, isGuild, wasEarnedByMe =
        pcall(GetAchievementInfo, achievementID)
    if not ok then return false, false end
    if completed ~= true or isGuild == true or wasEarnedByMe ~= true then return false, true end

    month, day, year = number(month), number(day), number(year)
    if not month or not day or not year or type(time) ~= "function" then return false, true end
    if year < 100 then year = year + 2000 end

    local earnedDayStart = time({ year = year, month = month, day = day, hour = 0 })
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    resetAt = number(resetAt) or 0
    if not earnedDayStart or resetAt <= 0 then return false, true end

    -- Achievement timestamps contain only a calendar date. Treat the date as
    -- current when any part of it overlaps the active weekly reset window.
    local cycleStart = resetAt - (7 * 24 * 60 * 60)
    return earnedDayStart < resetAt and (earnedDayStart + (24 * 60 * 60)) > cycleStart, true
end

function Logic:GetBossProgress(definition)
    definition = type(definition) == "table" and definition or {}
    local instanceID = number(definition.journalInstanceID)
    local journalEncounterID = number(definition.journalEncounterID)
    local instance = instanceID and getInstanceInfo(instanceID) or nil
    local encounter

    if instanceID and type(EJ_GetEncounterInfoByIndex) == "function" then
        if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end
        for _, difficultyID in ipairs(definition.difficultyIDs or {}) do
            if type(EJ_SetDifficulty) == "function" then pcall(EJ_SetDifficulty, difficultyID) end
            local index = 1
            while true do
                local ok, name, description, encounterID, _, _, _, dungeonEncounterID =
                    pcall(EJ_GetEncounterInfoByIndex, index, instanceID)
                if not ok or not name then break end
                if not journalEncounterID or number(encounterID) == journalEncounterID then
                    encounter = {
                        name = name,
                        description = type(description) == "string" and description or "",
                        encounterID = number(encounterID),
                        dungeonEncounterID = number(dungeonEncounterID),
                    }
                    break
                end
                index = index + 1
            end
            if encounter then break end
        end
    end

    local completed, available = false, false
    for _, difficultyID in ipairs(definition.difficultyIDs or {}) do
        local exact, exactAvailable = exactEncounterCompletion(
            instance and instance.mapID,
            encounter and encounter.dungeonEncounterID,
            difficultyID
        )
        completed = completed or exact
        available = available or exactAvailable
    end

    local wantedDifficulties = {}
    for _, difficultyID in ipairs(definition.difficultyIDs or {}) do
        wantedDifficulties[number(difficultyID)] = true
    end
    if type(GetNumSavedInstances) == "function"
        and type(GetSavedInstanceInfo) == "function"
        and type(GetSavedInstanceEncounterInfo) == "function"
    then
        local okCount, instanceCount = pcall(GetNumSavedInstances)
        if okCount then
            available = true
            for instanceIndex = 1, number(instanceCount) or 0 do
                local ok, _, _, _, difficultyID, locked, _, _, isRaid, _, _, encounterTotal =
                    pcall(GetSavedInstanceInfo, instanceIndex)
                if ok and isRaid == true and locked == true and wantedDifficulties[number(difficultyID)] then
                    for encounterIndex = 1, number(encounterTotal) or 0 do
                        local encounterOk, savedName, savedEncounterID, killed =
                            pcall(GetSavedInstanceEncounterInfo, instanceIndex, encounterIndex)
                        local matchingID = number(savedEncounterID)
                        local matchingName = self:NormalizeKey(savedName) == self:NormalizeKey(
                            (encounter and encounter.name) or definition.fallbackName
                        )
                        if encounterOk and (matchingName
                            or matchingID == journalEncounterID
                            or matchingID == number(encounter and encounter.dungeonEncounterID))
                        then
                            if type(savedName) == "string" and savedName ~= "" then
                                encounter = encounter or {}
                                encounter.name = savedName
                            end
                            completed = completed or killed == true
                        end
                    end
                end
            end
        end
    end

    if not completed and definition.achievementID then
        local achievementCompleted, achievementAvailable = achievementEarnedThisReset(definition.achievementID)
        completed = completed or achievementCompleted
        available = available or achievementAvailable
    end

    local icon
    if type(EJ_GetCreatureInfo) == "function" and journalEncounterID then
        local ok, _, _, _, _, creatureIcon = pcall(EJ_GetCreatureInfo, 1, journalEncounterID)
        if ok then icon = creatureIcon end
    end
    return {
        completed = completed,
        available = available,
        name = encounter and encounter.name or definition.fallbackName,
        description = encounter and encounter.description or "",
        icon = icon,
        journalEncounterID = journalEncounterID,
        dungeonEncounterID = encounter and encounter.dungeonEncounterID or nil,
    }
end

function Logic:ScanSnapshot(identity, existing, difficultyKey, isCurrentCharacter, currentTime)
    currentTime = number(currentTime) or now()
    difficultyKey = self:IsDifficultyKey(difficultyKey) and difficultyKey or "normal"
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo(type(existing) == "table" and existing.resetAt or nil)
    resetAt = number(resetAt) or 0
    local validExisting = self:IsSnapshotValid(existing, currentTime) and existing or nil
    local tierIndex, tierError = findMidnightTier()
    if not tierIndex or type(EJ_SelectTier) ~= "function"
        or type(EJ_GetEncounterInfoByIndex) ~= "function"
    then
        return validExisting or fallbackSnapshot(resetAt, currentTime, tierError or "api-unavailable"), false, tierError
    end
    pcall(EJ_SelectTier, tierIndex)
    local lockoutsByDifficulty, lockoutsAvailableByDifficulty = {}, {}
    for key, difficultyID in pairs(DATA.difficultyIDs or {}) do
        lockoutsByDifficulty[key], lockoutsAvailableByDifficulty[key] = readLockouts(
            difficultyID,
            isCurrentCharacter,
            function(value) return self:NormalizeKey(value) end
        )
    end
    local previousRaids = oldRaidByKey(validExisting)
    local previousRaidsByInstanceID = oldRaidByInstanceID(validExisting)
    local raids = {}
    local catalog, explicitCatalog = getJournalCatalog()
    local seenInstanceIDs = {}
    for _, instance in ipairs(catalog) do
        local instanceID = number(instance.instanceID)
        local name = instance.name
        if instanceID and type(name) == "string" and name ~= "" then
            seenInstanceIDs[instanceID] = true
            local raidKey = self:NormalizeKey(name)
            local previousRaid = previousRaids[raidKey] or previousRaidsByInstanceID[instanceID]
            local previousBosses = oldBossByKey(previousRaid)
            local raid = {
                key = raidKey,
                instanceID = instanceID,
                tierIndex = tierIndex,
                name = name,
                description = instance.description,
                contentType = self:GetContentType(instanceID, raidKey),
                icon = instance.icon,
                mapID = instance.mapID,
                bosses = {},
            }
            if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end
            raid.availableDifficulties = getDifficultyValidity()
            local encounters = scanEncounterCatalog(instanceID, difficultyKey, raid.availableDifficulties)
            for _, encounter in ipairs(encounters) do
                local bossName = encounter.name
                local bossKey = self:NormalizeKey(bossName)
                local previousBoss = previousBosses[bossKey]
                local killedByDifficulty = copy(type(previousBoss) == "table" and previousBoss.killedByDifficulty or {})
                for key, difficultyID in pairs(DATA.difficultyIDs or {}) do
                    local lockouts = lockoutsByDifficulty[key]
                    local observedKilled = lockouts and lockouts[raidKey]
                        and lockouts[raidKey].kills[bossKey] == true
                    local exactKilled, exactAvailable = exactEncounterCompletion(
                        raid.mapID,
                        encounter.dungeonEncounterID,
                        difficultyID
                    )
                    if exactAvailable or lockoutsAvailableByDifficulty[key] then
                        killedByDifficulty[key] = exactKilled or observedKilled
                            or killedByDifficulty[key] == true
                    end
                end
                local icon
                if type(EJ_GetCreatureInfo) == "function" and encounter.encounterID then
                    local creatureOk, _, _, _, _, creatureIcon = pcall(EJ_GetCreatureInfo, 1, encounter.encounterID)
                    if creatureOk then icon = creatureIcon end
                end
                raid.bosses[#raid.bosses + 1] = {
                    key = bossKey,
                    encounterID = encounter.encounterID,
                    dungeonEncounterID = encounter.dungeonEncounterID,
                    name = bossName,
                    description = encounter.description,
                    icon = icon,
                    killedByDifficulty = killedByDifficulty,
                }
            end
            raid.icon = raid.icon or (raid.bosses[1] and raid.bosses[1].icon)
            if #raid.bosses > 0 then
                raids[#raids + 1] = raid
            elseif previousRaid then
                local preserved = copy(previousRaid)
                preserved.availableDifficulties = raid.availableDifficulties or preserved.availableDifficulties
                raids[#raids + 1] = preserved
            end
        end
    end
    if explicitCatalog then
        for _, instanceID in ipairs(DATA.journalInstanceIDs or {}) do
            instanceID = number(instanceID)
            local previousRaid = instanceID and previousRaidsByInstanceID[instanceID] or nil
            if previousRaid and not seenInstanceIDs[instanceID] then raids[#raids + 1] = copy(previousRaid) end
        end
    end
    if #raids == 0 then
        return validExisting or fallbackSnapshot(resetAt, currentTime, "empty-journal"), false, "empty-journal"
    end
    return {
        updatedAt = currentTime,
        resetAt = resetAt,
        source = "encounter-journal",
        tierIndex = tierIndex,
        raids = raids,
    }, true
end

local function classIDFor(identity)
    local token = identity and identity.classFile
    if type(token) ~= "string" or type(GetClassInfo) ~= "function" then return 0 end
    for classID = 1, 20 do
        local ok, _, classToken = pcall(GetClassInfo, classID)
        if ok and classToken == token then return classID end
    end
    return 0
end

function Logic:ScanLoot(raid, boss, difficultyKey, classFilterKey, identity, difficultyIDs)
    if type(raid) ~= "table" or type(boss) ~= "table" or not number(boss.encounterID) then return {}, false end
    if type(EJ_SelectEncounter) ~= "function" or type(EJ_GetNumLoot) ~= "function"
        or type(EJ_SetDifficulty) ~= "function" or type(EJ_SetLootFilter) ~= "function"
        or type(C_EncounterJournal) ~= "table" or type(C_EncounterJournal.GetLootInfoByIndex) ~= "function"
    then
        return {}, false
    end
    difficultyIDs = type(difficultyIDs) == "table" and difficultyIDs or DATA.difficultyIDs
    difficultyKey = difficultyIDs[difficultyKey] and difficultyKey or "normal"
    if type(EJ_ClearSearch) == "function" then pcall(EJ_ClearSearch) end
    if type(EJ_ResetLootFilter) == "function" then pcall(EJ_ResetLootFilter) end
    if type(C_EncounterJournal.ResetSlotFilter) == "function" then pcall(C_EncounterJournal.ResetSlotFilter) end
    if type(EJ_SelectTier) == "function" and number(raid.tierIndex) then pcall(EJ_SelectTier, raid.tierIndex) end
    pcall(EJ_SetDifficulty, difficultyIDs[difficultyKey])
    if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, raid.instanceID) end
    pcall(EJ_SetLootFilter, classFilterKey == "all" and 0 or classIDFor(identity), 0)
    pcall(EJ_SelectEncounter, boss.encounterID)
    local okCount, count = pcall(EJ_GetNumLoot)
    if not okCount then return {}, false end
    local items, seen = {}, {}
    for index = 1, number(count) or 0 do
        local ok, item = pcall(C_EncounterJournal.GetLootInfoByIndex, index)
        local itemID = ok and type(item) == "table" and number(item.itemID) or nil
        if itemID and not seen[itemID] then
            seen[itemID] = true
            items[#items + 1] = {
                itemID = itemID,
                name = type(item.name) == "string" and item.name ~= "" and item.name or string.format(L.RAID_JOURNAL_ITEM_FALLBACK, itemID),
                icon = item.icon,
                link = item.link,
                slot = item.slot,
                armorType = item.armorType,
                quality = number(item.itemQuality or item.quality),
                veryRare = item.displayAsVeryRare == true,
                extremelyRare = item.displayAsExtremelyRare == true,
            }
        end
    end
    return items, true
end

local function formatRemaining(seconds)
    seconds = math.max(0, math.floor(number(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then return string.format(L.TIME_DAY_HOUR, days, hours) end
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then return string.format(L.TIME_HOUR_MIN, hours, minutes) end
    return string.format(L.TIME_MIN, minutes)
end

function Logic:BuildView(snapshot, settings, identity, loot, currentTime)
    currentTime = number(currentTime) or now()
    snapshot = type(snapshot) == "table" and snapshot or fallbackSnapshot(0, currentTime, "no-snapshot")
    settings = type(settings) == "table" and settings or {}
    local difficultyKey = self:IsDifficultyKey(settings.difficultyKey) and settings.difficultyKey or "normal"
    local classFilterKey = settings.classFilterKey == "all" and "all" or "player"
    local raids = {}
    for _, sourceRaid in ipairs(copy(snapshot.raids or {})) do
        local available = sourceRaid.availableDifficulties
        if type(available) ~= "table" or available[difficultyKey] ~= false then
            raids[#raids + 1] = sourceRaid
        end
    end
    local selectedRaid = raids[1]
    for _, raid in ipairs(raids) do
        raid.contentType = self:GetContentType(raid.instanceID, raid.key)
        raid.killedCount = 0
        raid.totalCount = #raid.bosses
        for _, boss in ipairs(raid.bosses or {}) do
            boss.killed = type(boss.killedByDifficulty) == "table" and boss.killedByDifficulty[difficultyKey] == true
            boss.status = boss.killed and "complete" or "open"
            if boss.killed then raid.killedCount = raid.killedCount + 1 end
        end
        raid.progressText = string.format("%d/%d", raid.killedCount, raid.totalCount)
        if raid.key == settings.selectedRaidKey then selectedRaid = raid end
    end
    local selectedBoss = selectedRaid and selectedRaid.bosses and selectedRaid.bosses[1]
    if selectedRaid then
        for _, boss in ipairs(selectedRaid.bosses or {}) do
            if boss.key == settings.selectedBossKey then selectedBoss = boss end
        end
    end
    local secondsRemaining = math.max(0, (number(snapshot.resetAt) or 0) - currentTime)
    return {
        source = snapshot.source,
        unavailableReason = snapshot.unavailableReason,
        raids = raids,
        selectedRaid = selectedRaid,
        selectedBoss = selectedBoss,
        selectedRaidKey = selectedRaid and selectedRaid.key or "",
        selectedBossKey = selectedBoss and selectedBoss.key or "",
        difficultyKey = difficultyKey,
        classFilterKey = classFilterKey,
        classFilterName = classFilterKey == "all" and L.RAID_JOURNAL_ALL_CLASSES or (identity and identity.className or L.UNKNOWN),
        loot = type(loot) == "table" and loot or {},
        updatedAt = number(snapshot.updatedAt) or 0,
        resetAt = number(snapshot.resetAt) or 0,
        resetText = (number(snapshot.resetAt) or 0) > 0 and formatRemaining(secondsRemaining) or "--",
    }
end
