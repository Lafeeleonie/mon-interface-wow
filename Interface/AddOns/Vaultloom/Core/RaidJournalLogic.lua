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

function Logic:IsSnapshotValid(snapshot, currentTime)
    currentTime = number(currentTime) or now()
    return type(snapshot) == "table" and (number(snapshot.resetAt) or 0) > currentTime
end

local function fallbackSnapshot(resetAt, currentTime, reason)
    local raids = {}
    for index, definition in ipairs(DATA.fallbackRaids) do
        raids[#raids + 1] = {
            key = definition.key,
            name = string.format("%s %d", L.WISHLIST_SOURCE_RAID or L.SCREEN_RAIDS or "Raid", index),
            description = L.RAID_JOURNAL_UNAVAILABLE,
            icon = definition.icon,
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

local function oldBossByKey(raid)
    local result = {}
    for _, boss in ipairs(type(raid) == "table" and raid.bosses or {}) do
        if type(boss) == "table" and type(boss.key) == "string" then result[boss.key] = boss end
    end
    return result
end

function Logic:ScanSnapshot(identity, existing, difficultyKey, isCurrentCharacter, currentTime)
    currentTime = number(currentTime) or now()
    difficultyKey = self:IsDifficultyKey(difficultyKey) and difficultyKey or "normal"
    local _, resetAt = Addon.WoWApi:GetWeeklyResetInfo()
    resetAt = number(resetAt) or 0
    local validExisting = self:IsSnapshotValid(existing, currentTime) and existing or nil
    local tierIndex, tierError = findMidnightTier()
    if not tierIndex or type(EJ_SelectTier) ~= "function" or type(EJ_GetInstanceByIndex) ~= "function"
        or type(EJ_GetEncounterInfoByIndex) ~= "function"
    then
        return validExisting or fallbackSnapshot(resetAt, currentTime, tierError or "api-unavailable"), false, tierError
    end
    pcall(EJ_SelectTier, tierIndex)
    local difficultyID = DATA.difficultyIDs[difficultyKey]
    local lockouts, lockoutsAvailable = readLockouts(difficultyID, isCurrentCharacter, function(value)
        return self:NormalizeKey(value)
    end)
    local previousRaids = oldRaidByKey(validExisting)
    local raids = {}
    local instanceIndex = 1
    while true do
        local ok, instanceID, name, description = pcall(EJ_GetInstanceByIndex, instanceIndex, true)
        if not ok or not instanceID then break end
        if type(name) == "string" and name ~= "" then
            local raidKey = self:NormalizeKey(name)
            local previousRaid = previousRaids[raidKey]
            local previousBosses = oldBossByKey(previousRaid)
            local raid = {
                key = raidKey,
                instanceID = number(instanceID),
                tierIndex = tierIndex,
                name = name,
                description = type(description) == "string" and description or "",
                bosses = {},
            }
            if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end
            if type(EJ_SetDifficulty) == "function" then pcall(EJ_SetDifficulty, difficultyID) end
            if type(EJ_GetInstanceInfo) == "function" then
                local infoOk, _, _, background, buttonImage1, _, buttonImage2 = pcall(EJ_GetInstanceInfo, instanceID)
                if infoOk then raid.icon = buttonImage1 or buttonImage2 or background end
            end
            local encounterIndex = 1
            while true do
                local encounterOk, bossName, bossDescription, encounterID = pcall(EJ_GetEncounterInfoByIndex, encounterIndex, instanceID)
                if not encounterOk or not bossName then break end
                local bossKey = self:NormalizeKey(bossName)
                local previousBoss = previousBosses[bossKey]
                local killedByDifficulty = copy(type(previousBoss) == "table" and previousBoss.killedByDifficulty or {})
                local observedKilled = lockouts[raidKey] and lockouts[raidKey].kills[bossKey] == true
                if lockoutsAvailable then
                    killedByDifficulty[difficultyKey] = observedKilled or killedByDifficulty[difficultyKey] == true
                end
                local icon
                if type(EJ_GetCreatureInfo) == "function" and number(encounterID) then
                    local creatureOk, _, _, _, _, creatureIcon = pcall(EJ_GetCreatureInfo, 1, encounterID)
                    if creatureOk then icon = creatureIcon end
                end
                raid.bosses[#raid.bosses + 1] = {
                    key = bossKey,
                    encounterID = number(encounterID),
                    name = bossName,
                    description = type(bossDescription) == "string" and bossDescription or "",
                    icon = icon,
                    killedByDifficulty = killedByDifficulty,
                }
                encounterIndex = encounterIndex + 1
            end
            raid.icon = raid.icon or (raid.bosses[1] and raid.bosses[1].icon)
            if #raid.bosses > 0 then raids[#raids + 1] = raid end
        end
        instanceIndex = instanceIndex + 1
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
    local raids = copy(snapshot.raids or {})
    local selectedRaid = raids[1]
    for _, raid in ipairs(raids) do
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
