local _, Addon = ...

local L = Addon.L
local DATA = Addon.Data.DUNGEONS
local Logic = {}
Addon.DungeonJournalLogic = Logic
local dungeonCatalogCache

function Logic:InvalidateCatalog()
    dungeonCatalogCache = nil
end

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

local function normalize(value)
    return Addon.RaidJournalLogic:NormalizeKey(value)
end

local seasonalCanonicalKeys = {}
for canonicalKey, aliases in pairs(DATA.seasonalKeyGroups or {}) do
    local normalizedCanonicalKey = normalize(canonicalKey)
    seasonalCanonicalKeys[normalizedCanonicalKey] = normalizedCanonicalKey
    for _, alias in ipairs(aliases or {}) do
        seasonalCanonicalKeys[normalize(alias)] = normalizedCanonicalKey
    end
end

local function canonicalSeasonalKey(value)
    local key = normalize(value)
    return seasonalCanonicalKeys[key] or key
end

function Logic:IsDifficultyKey(key)
    return DATA.difficultyIDs[key] ~= nil
end

function Logic:IsSubTabKey(key)
    for _, definition in ipairs(DATA.subTabs or {}) do
        if definition.key == key then return true end
    end
    return false
end

function Logic:IsSnapshotValid(snapshot, currentTime)
    currentTime = number(currentTime) or now()
    return type(snapshot) == "table"
        and Addon.WoWApi:GetResetState(snapshot.resetAt, currentTime) ~= Addon.WoWApi.RESET_EXPIRED
end

local function getSubTabDefinition(subTabKey)
    for _, definition in ipairs(DATA.subTabs) do
        if definition.key == subTabKey then return definition end
    end
    return DATA.subTabs[1]
end

local function fallbackSnapshot(subTabKey, resetAt, currentTime, reason)
    return {
        updatedAt = currentTime,
        resetAt = resetAt,
        source = "fallback",
        subTabKey = subTabKey,
        unavailableReason = reason,
        dungeons = {},
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
    -- Journal tier titles use the WoW client language. The latest expansion
    -- is the final chronological tier and can be selected without comparing
    -- localized text.
    return tierCount
end

local function readMythicLockouts(isCurrentCharacter)
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
        local ok, name, _, _, difficultyID, locked, _, _, isRaid, _, _, encounterTotal =
            pcall(GetSavedInstanceInfo, instanceIndex)
        if ok and isRaid == false and locked == true and number(difficultyID) == DATA.difficultyIDs.mythic
            and type(name) == "string" and name ~= ""
        then
            local entry = { kills = {} }
            for encounterIndex = 1, number(encounterTotal) or 0 do
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

local function oldDungeonByKey(existing)
    local result = {}
    for _, dungeon in ipairs(type(existing) == "table" and existing.dungeons or {}) do
        if type(dungeon) == "table" and type(dungeon.key) == "string" then result[dungeon.key] = dungeon end
    end
    return result
end

local function oldBossByKey(dungeon)
    local result = {}
    for _, boss in ipairs(type(dungeon) == "table" and dungeon.bosses or {}) do
        if type(boss) == "table" and type(boss.key) == "string" then result[boss.key] = boss end
    end
    return result
end

local function scanInstance(entry, difficultyKey, lockouts, lockoutsAvailable, previousDungeon)
    local instanceID = number(entry and entry.instanceID)
    if not instanceID then return nil end
    local tierIndex = number(entry.tierIndex)
    if tierIndex and type(EJ_SelectTier) == "function" then pcall(EJ_SelectTier, tierIndex) end
    if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end
    if type(EJ_SetDifficulty) == "function" then pcall(EJ_SetDifficulty, DATA.difficultyIDs[difficultyKey]) end

    local dungeon = {
        key = normalize(entry.name),
        instanceID = instanceID,
        tierIndex = tierIndex,
        challengeModeID = number(entry.challengeModeID),
        uiMapID = number(entry.uiMapID),
        name = entry.name,
        description = type(entry.description) == "string" and entry.description or "",
        icon = entry.icon,
        bosses = {},
    }
    if type(EJ_GetInstanceInfo) == "function" then
        local ok, journalName, journalDescription, background, buttonImage1, _, buttonImage2 = pcall(EJ_GetInstanceInfo, instanceID)
        if ok then
            if type(journalName) == "string" and journalName ~= "" then
                dungeon.name = journalName
                dungeon.key = normalize(journalName)
            end
            if type(journalDescription) == "string" and journalDescription ~= "" then dungeon.description = journalDescription end
            dungeon.icon = dungeon.icon or buttonImage1 or buttonImage2 or background
        end
    end

    local previousBosses = oldBossByKey(previousDungeon)
    local seenEncounterIDs = {}
    local function addBoss(bossName, bossDescription, encounterID, icon)
        encounterID = number(encounterID)
        if type(bossName) ~= "string" or bossName == "" or not encounterID or seenEncounterIDs[encounterID] then return end
        seenEncounterIDs[encounterID] = true
        local bossKey = normalize(bossName)
        local previousBoss = previousBosses[bossKey]
        local killedByDifficulty = copy(type(previousBoss) == "table" and previousBoss.killedByDifficulty or {})
        if difficultyKey == "mythic" and lockoutsAvailable then
            local observed = lockouts[dungeon.key] and lockouts[dungeon.key].kills[bossKey] == true
            killedByDifficulty.mythic = observed or killedByDifficulty.mythic == true
        end
        if not icon and type(EJ_GetCreatureInfo) == "function" then
            local creatureOk, _, _, _, _, creatureIcon = pcall(EJ_GetCreatureInfo, 1, encounterID)
            if creatureOk then icon = creatureIcon end
        end
        dungeon.bosses[#dungeon.bosses + 1] = {
            key = bossKey,
            encounterID = encounterID,
            name = bossName,
            description = type(bossDescription) == "string" and bossDescription or "",
            icon = icon,
            killedByDifficulty = killedByDifficulty,
        }
    end

    local encounterIndex = 1
    while type(EJ_GetEncounterInfoByIndex) == "function" do
        local ok, bossName, bossDescription, encounterID = pcall(EJ_GetEncounterInfoByIndex, encounterIndex, instanceID)
        if not ok or not bossName then break end
        addBoss(bossName, bossDescription, encounterID)
        encounterIndex = encounterIndex + 1
    end

    if #dungeon.bosses == 0 and type(EJ_GetNumLoot) == "function"
        and type(C_EncounterJournal) == "table"
        and type(C_EncounterJournal.GetLootInfoByIndex) == "function"
    then
        if type(EJ_ClearSearch) == "function" then pcall(EJ_ClearSearch) end
        if type(EJ_ResetLootFilter) == "function" then pcall(EJ_ResetLootFilter) end
        if type(C_EncounterJournal.ResetSlotFilter) == "function" then pcall(C_EncounterJournal.ResetSlotFilter) end
        if tierIndex and type(EJ_SelectTier) == "function" then pcall(EJ_SelectTier, tierIndex) end
        if type(EJ_SetDifficulty) == "function" then pcall(EJ_SetDifficulty, DATA.difficultyIDs[difficultyKey]) end
        if type(EJ_SelectInstance) == "function" then pcall(EJ_SelectInstance, instanceID) end

        local discovered = {}
        local okLootCount, lootCount = pcall(EJ_GetNumLoot)
        for lootIndex = 1, okLootCount and number(lootCount) or 0 do
            local okLoot, itemInfo = pcall(C_EncounterJournal.GetLootInfoByIndex, lootIndex)
            local encounterID = okLoot and type(itemInfo) == "table" and number(itemInfo.encounterID) or nil
            if encounterID and not discovered[encounterID] then
                local bossName, bossDescription
                if type(EJ_GetEncounterInfo) == "function" then
                    local okEncounter, name, description = pcall(EJ_GetEncounterInfo, encounterID)
                    if okEncounter then
                        bossName = name
                        bossDescription = description
                    end
                end
                discovered[encounterID] = {
                    encounterID = encounterID,
                    name = type(bossName) == "string" and bossName ~= "" and bossName or (tostring(L.UNKNOWN) .. " " .. tostring(encounterID)),
                    description = type(bossDescription) == "string" and bossDescription or "",
                }
            end
        end
        local ordered = {}
        for _, boss in pairs(discovered) do ordered[#ordered + 1] = boss end
        table.sort(ordered, function(left, right) return left.encounterID < right.encounterID end)
        for _, boss in ipairs(ordered) do
            addBoss(boss.name, boss.description, boss.encounterID)
        end
    end
    dungeon.icon = dungeon.icon or (dungeon.bosses[1] and dungeon.bosses[1].icon)
    return dungeon
end

local function scanMidnight(existing, difficultyKey, lockouts, lockoutsAvailable)
    local tierIndex, tierError = findMidnightTier()
    if not tierIndex or type(EJ_SelectTier) ~= "function" or type(EJ_GetInstanceByIndex) ~= "function" then
        return nil, tierError or "api-unavailable"
    end
    pcall(EJ_SelectTier, tierIndex)
    local previous = oldDungeonByKey(existing)
    local dungeons = {}
    local index = 1
    while true do
        local ok, instanceID, name, description = pcall(EJ_GetInstanceByIndex, index, false)
        if not ok or not instanceID then break end
        if type(name) == "string" and name ~= "" then
            local dungeon = scanInstance({
                instanceID = instanceID,
                tierIndex = tierIndex,
                name = name,
                description = description,
            }, difficultyKey, lockouts, lockoutsAvailable, previous[normalize(name)])
            if dungeon then dungeons[#dungeons + 1] = dungeon end
        end
        index = index + 1
    end
    return #dungeons > 0 and dungeons or nil, #dungeons > 0 and nil or "empty-journal"
end

local function buildDungeonCatalog()
    if dungeonCatalogCache then return dungeonCatalogCache.byKey, dungeonCatalogCache.byID end
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_SelectTier) ~= "function" or type(EJ_GetInstanceByIndex) ~= "function" then
        return {}, {}, "api-unavailable"
    end
    local byKey, byID = {}, {}
    local savedTier
    if type(EJ_GetCurrentTier) == "function" then
        local okTier, currentTier = pcall(EJ_GetCurrentTier)
        if okTier then savedTier = number(currentTier) end
    end
    local okCount, tierCount = pcall(EJ_GetNumTiers)
    if not okCount then return byKey, byID, "tier-scan-failed" end
    for tierIndex = 1, number(tierCount) or 0 do
        pcall(EJ_SelectTier, tierIndex)
        local instanceIndex = 1
        while true do
            local ok, instanceID, name, description = pcall(EJ_GetInstanceByIndex, instanceIndex, false)
            if not ok or not instanceID then break end
            if type(name) == "string" and name ~= "" then
                local entry = {
                    instanceID = number(instanceID),
                    tierIndex = tierIndex,
                    name = name,
                    description = type(description) == "string" and description or "",
                }
                local key = normalize(name)
                byKey[key] = byKey[key] or {}
                byKey[key][#byKey[key] + 1] = entry
                byID[entry.instanceID] = byID[entry.instanceID] or entry
            end
            instanceIndex = instanceIndex + 1
        end
    end
    if savedTier then pcall(EJ_SelectTier, savedTier) end
    if next(byID) then dungeonCatalogCache = { byKey = byKey, byID = byID } end
    return byKey, byID
end

local function journalEntryForMap(uiMapID, byID)
    if type(EJ_GetInstanceForMap) ~= "function" then return nil end
    local mapID, checked, depth = number(uiMapID), {}, 0
    while mapID and mapID > 0 and not checked[mapID] and depth < 8 do
        checked[mapID] = true
        depth = depth + 1
        local ok, instanceID = pcall(EJ_GetInstanceForMap, mapID)
        if ok and byID[number(instanceID)] then return byID[number(instanceID)] end
        local parentMapID
        if C_Map and type(C_Map.GetMapInfo) == "function" then
            local mapOk, mapInfo = pcall(C_Map.GetMapInfo, mapID)
            if mapOk and type(mapInfo) == "table" then parentMapID = number(mapInfo.parentMapID) end
        end
        if not parentMapID or parentMapID <= 0 or parentMapID == mapID then break end
        mapID = parentMapID
    end
    return nil
end

local function addSeasonalCandidate(candidates, seenInstanceIDs, entry)
    local instanceID = number(entry and entry.instanceID)
    if not instanceID or seenInstanceIDs[instanceID] then return end
    seenInstanceIDs[instanceID] = true
    candidates[#candidates + 1] = entry
end

local function seasonalCandidates(name, uiMapID, byKey, byID)
    local candidates, seenInstanceIDs = {}, {}
    addSeasonalCandidate(candidates, seenInstanceIDs, journalEntryForMap(uiMapID, byID))

    local rawKey = normalize(name)
    local canonicalKey = canonicalSeasonalKey(rawKey)
    local candidateKeys, seenKeys = {}, {}
    local function addKey(key)
        key = normalize(key)
        if key ~= "" and not seenKeys[key] then
            seenKeys[key] = true
            candidateKeys[#candidateKeys + 1] = key
        end
    end
    addKey(rawKey)
    for _, alias in ipairs((DATA.seasonalKeyGroups or {})[canonicalKey] or {}) do addKey(alias) end
    addKey(canonicalKey)

    for _, key in ipairs(candidateKeys) do
        for _, entry in ipairs(byKey[key] or {}) do
            addSeasonalCandidate(candidates, seenInstanceIDs, entry)
        end
    end

    for catalogKey, entries in pairs(byKey) do
        if #rawKey >= 6 and (catalogKey:find(rawKey, 1, true) or rawKey:find(catalogKey, 1, true)) then
            for _, entry in ipairs(entries or {}) do
                addSeasonalCandidate(candidates, seenInstanceIDs, entry)
            end
        end
    end
    return candidates
end

local function scanSeasonal(existing, difficultyKey, lockouts, lockoutsAvailable)
    if type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetMapTable) ~= "function"
        or type(C_ChallengeMode.GetMapUIInfo) ~= "function"
    then
        return nil, "challenge-mode-api-unavailable"
    end
    if type(C_ChallengeMode.RequestMapInfo) == "function" then pcall(C_ChallengeMode.RequestMapInfo) end
    if C_MythicPlus and type(C_MythicPlus.RequestMapInfo) == "function" then pcall(C_MythicPlus.RequestMapInfo) end
    local okMaps, mapIDs = pcall(C_ChallengeMode.GetMapTable)
    if not okMaps or type(mapIDs) ~= "table" or #mapIDs == 0 then return nil, "season-pool-unavailable" end

    local byKey, byID = buildDungeonCatalog()
    local previous = oldDungeonByKey(existing)
    local dungeons, seen = {}, {}
    for _, challengeModeID in ipairs(mapIDs) do
        local ok, name, _, timeLimit, texture, backgroundTexture, uiMapID = pcall(C_ChallengeMode.GetMapUIInfo, challengeModeID)
        if ok and type(name) == "string" and name ~= "" then
            local resolved
            for _, entry in ipairs(seasonalCandidates(name, uiMapID, byKey, byID)) do
                if not seen[entry.instanceID] then
                    local scanEntry = copy(entry)
                    scanEntry.challengeModeID = challengeModeID
                    scanEntry.uiMapID = uiMapID
                    scanEntry.icon = texture or backgroundTexture
                    scanEntry.timeLimit = timeLimit
                    local previousDungeon = previous[normalize(entry.name)] or previous[normalize(name)]
                    local dungeon = scanInstance(scanEntry, difficultyKey, lockouts, lockoutsAvailable, previousDungeon)
                    if dungeon and #dungeon.bosses > 0 then
                        resolved = dungeon
                        break
                    end
                end
            end
            if resolved then
                dungeons[#dungeons + 1] = resolved
                seen[resolved.instanceID] = true
            elseif not seen["challenge:" .. tostring(challengeModeID)] then
                dungeons[#dungeons + 1] = {
                    key = normalize(name),
                    challengeModeID = number(challengeModeID),
                    uiMapID = number(uiMapID),
                    name = name,
                    description = L.DUNGEON_JOURNAL_UNAVAILABLE,
                    icon = texture or backgroundTexture,
                    bosses = {},
                }
                seen["challenge:" .. tostring(challengeModeID)] = true
            end
        end
    end
    return #dungeons > 0 and dungeons or nil, #dungeons > 0 and nil or "season-pool-empty"
end

function Logic:ScanSnapshot(subTabKey, identity, existing, difficultyKey, isCurrentCharacter, currentTime)
    currentTime = number(currentTime) or now()
    subTabKey = self:IsSubTabKey(subTabKey) and subTabKey or "midnight"
    difficultyKey = self:IsDifficultyKey(difficultyKey) and difficultyKey or "normal"
    local _, resetAt = Addon.WoWApi:GetDailyResetInfo(type(existing) == "table" and existing.resetAt or nil)
    resetAt = number(resetAt) or 0
    local validExisting = self:IsSnapshotValid(existing, currentTime) and existing or nil
    local lockouts, lockoutsAvailable = readMythicLockouts(isCurrentCharacter)
    local dungeons, scanError
    local definition = getSubTabDefinition(subTabKey)
    if definition.seasonal == true then
        dungeons, scanError = scanSeasonal(validExisting, difficultyKey, lockouts, lockoutsAvailable)
    else
        dungeons, scanError = scanMidnight(validExisting, difficultyKey, lockouts, lockoutsAvailable)
    end
    if not dungeons then
        return validExisting or fallbackSnapshot(subTabKey, resetAt, currentTime, scanError), false, scanError
    end
    return {
        updatedAt = currentTime,
        resetAt = resetAt,
        source = "encounter-journal",
        subTabKey = subTabKey,
        dungeons = dungeons,
    }, true
end

local function formatRemaining(seconds)
    seconds = math.max(0, math.floor(number(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then return string.format(L.TIME_HOUR_MIN, hours, minutes) end
    return string.format(L.TIME_MIN, minutes)
end

function Logic:ScanLoot(dungeon, boss, difficultyKey, classFilterKey, identity)
    return Addon.RaidJournalLogic:ScanLoot(
        dungeon, boss, difficultyKey, classFilterKey, identity, DATA.difficultyIDs
    )
end

function Logic:BuildView(snapshot, settings, identity, loot, currentTime)
    currentTime = number(currentTime) or now()
    settings = type(settings) == "table" and settings or {}
    local subTabKey = self:IsSubTabKey(settings.subTabKey) and settings.subTabKey or "midnight"
    snapshot = type(snapshot) == "table" and snapshot or fallbackSnapshot(subTabKey, 0, currentTime, "no-snapshot")
    local difficultyKey = self:IsDifficultyKey(settings.difficultyKey) and settings.difficultyKey or "normal"
    local classFilterKey = settings.classFilterKey == "all" and "all" or "player"
    local repeatable = difficultyKey ~= "mythic"
    local dungeons = copy(snapshot.dungeons or {})
    local selectedDungeon = dungeons[1]
    for _, dungeon in ipairs(dungeons) do
        dungeon.killedCount = 0
        dungeon.totalCount = #dungeon.bosses
        dungeon.counterMode = repeatable and "repeatable" or "daily"
        for _, boss in ipairs(dungeon.bosses or {}) do
            boss.killed = not repeatable and type(boss.killedByDifficulty) == "table" and boss.killedByDifficulty.mythic == true
            boss.status = repeatable and "repeatable" or (boss.killed and "complete" or "open")
            if boss.killed then dungeon.killedCount = dungeon.killedCount + 1 end
        end
        if repeatable then
            dungeon.progressText = nil
        else
            dungeon.progressText = string.format("%d/%d", dungeon.killedCount, dungeon.totalCount)
        end
        if dungeon.key == settings.selectedRaidKey then selectedDungeon = dungeon end
    end
    local selectedBoss = selectedDungeon and selectedDungeon.bosses and selectedDungeon.bosses[1]
    if selectedDungeon then
        for _, boss in ipairs(selectedDungeon.bosses or {}) do
            if boss.key == settings.selectedBossKey then selectedBoss = boss end
        end
    end
    local definition = getSubTabDefinition(subTabKey)
    local secondsRemaining = math.max(0, (number(snapshot.resetAt) or 0) - currentTime)
    return {
        source = snapshot.source,
        unavailableReason = snapshot.unavailableReason,
        subTabKey = subTabKey,
        listSubtitle = L[definition.subtitleKey],
        raids = dungeons,
        dungeons = dungeons,
        selectedRaid = selectedDungeon,
        selectedDungeon = selectedDungeon,
        selectedBoss = selectedBoss,
        selectedRaidKey = selectedDungeon and selectedDungeon.key or "",
        selectedBossKey = selectedBoss and selectedBoss.key or "",
        difficultyKey = difficultyKey,
        classFilterKey = classFilterKey,
        classFilterName = classFilterKey == "all" and L.RAID_JOURNAL_ALL_CLASSES or (identity and identity.className or L.UNKNOWN),
        counterMode = repeatable and "repeatable" or "daily",
        loot = type(loot) == "table" and loot or {},
        updatedAt = number(snapshot.updatedAt) or 0,
        resetAt = number(snapshot.resetAt) or 0,
        resetText = (number(snapshot.resetAt) or 0) > 0 and formatRemaining(secondsRemaining) or "--",
    }
end
