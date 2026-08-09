local _, Addon = ...

local L = Addon.L
local DATA = Addon.Data.PROFESSIONS
local Logic = {}
Addon.ProfessionCooldownLogic = Logic

local MAX_REASONABLE_COOLDOWN_SECONDS = 60 * 60 * 24 * 35
local CONCENTRATION_REGEN_SECONDS = 360
local CRAFTING_PROFESSIONS = {
    alchemy = true,
    blacksmithing = true,
    enchanting = true,
    engineering = true,
    inscription = true,
    jewelcrafting = true,
    leatherworking = true,
    tailoring = true,
}
local PROFESSION_NAME_PATTERNS = {
    alchemy = { "alchemy", "alchemie" },
    blacksmithing = { "blacksmith", "schmied" },
    enchanting = { "enchant", "verzauber" },
    engineering = { "engineer", "ingenieur" },
    inscription = { "inscription", "inschrift" },
    jewelcrafting = { "jewel", "juwel" },
    leatherworking = { "leather", "leder" },
    tailoring = { "tailor", "schneider", "schneid" },
}

Logic.concentrationRegenSeconds = CONCENTRATION_REGEN_SECONDS
Logic.craftingProfessions = CRAFTING_PROFESSIONS

local function now()
    return type(time) == "function" and time() or 0
end

local function number(value)
    return tonumber(value)
end

local function normalizeName(value)
    return type(value) == "string" and string.lower(value) or ""
end

local function keyFromName(name)
    local lowered = normalizeName(name)
    for professionKey, patterns in pairs(PROFESSION_NAME_PATTERNS) do
        for _, pattern in ipairs(patterns) do
            if string.find(lowered, pattern, 1, true) then
                return professionKey
            end
        end
    end
    return nil
end

local function getIdentityProfessions(identity)
    return type(identity) == "table" and type(identity.professions) == "table" and identity.professions or {}
end

local function getProfessionKey(name, skillLineID, identity)
    skillLineID = number(skillLineID)
    if skillLineID and DATA.skillLineToKey[skillLineID] then
        return DATA.skillLineToKey[skillLineID]
    end
    local byName = keyFromName(name)
    if byName then
        return byName
    end
    local lowered = normalizeName(name)
    for _, profession in ipairs(getIdentityProfessions(identity)) do
        local professionKey = DATA.skillLineToKey[number(profession.skillLineID)]
        local professionName = normalizeName(profession.name)
        if professionKey and lowered ~= "" and professionName ~= ""
            and (string.find(lowered, professionName, 1, true)
                or string.find(professionName, lowered, 1, true))
        then
            return professionKey
        end
    end
    return nil
end

local function getProfessionName(professionKey, fallback, identity)
    for _, profession in ipairs(getIdentityProfessions(identity)) do
        if DATA.skillLineToKey[number(profession.skillLineID)] == professionKey
            and type(profession.name) == "string" and profession.name ~= ""
        then
            return profession.name
        end
    end
    return type(fallback) == "string" and fallback ~= "" and fallback or professionKey or L.UNKNOWN
end

local function addUnique(list, seen, value)
    value = number(value)
    if value and value > 0 and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function applyTradeSkillInfo(result, raw)
    if type(raw) ~= "table" then
        if type(raw) == "string" and raw ~= "" and not result.name then
            result.name = raw
        end
        return
    end
    result.name = result.name or raw.professionName or raw.parentProfessionName or raw.name or raw.displayName
    result.skillLineID = result.skillLineID or number(raw.skillLineID or raw.parentSkillLineID or raw.professionSkillLineID)
    addUnique(result.professionIDs, result.seenIDs, raw.professionID)
    addUnique(result.professionIDs, result.seenIDs, raw.parentProfessionID)
    addUnique(result.professionIDs, result.seenIDs, raw.skillLineID)
    addUnique(result.professionIDs, result.seenIDs, raw.parentSkillLineID)
end

local function readOpenTradeSkillInfo()
    local result = { professionIDs = {}, seenIDs = {} }
    local apiNames = { "GetTradeSkillLine", "GetBaseProfessionInfo", "GetChildProfessionInfo" }
    for _, apiName in ipairs(apiNames) do
        local api = C_TradeSkillUI and C_TradeSkillUI[apiName]
        if type(api) == "function" then
            local ok, value = pcall(api)
            if ok then applyTradeSkillInfo(result, value) end
        end
    end
    if not result.name and type(GetTradeSkillLine) == "function" then
        local ok, value = pcall(GetTradeSkillLine)
        if ok then
            applyTradeSkillInfo(result, value)
        end
    end
    result.seenIDs = nil
    return result
end

local function getSpellName(spellID)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, value = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, value = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(value) == "table" and type(value.name) == "string" then
            return value.name
        elseif ok and type(value) == "string" then
            return value
        end
    end
    return nil
end

function Logic:ParseRecipeCooldown(recipeID, currentTime)
    recipeID = number(recipeID)
    if not recipeID then
        return nil
    end
    currentTime = number(currentTime) or now()
    local remainingSeconds, durationSeconds, currentCharges, maxCharges
    local isDayCooldown = false
    if C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeCooldown) == "function" then
        local ok, remaining, dayCooldown, charges, maximum = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
        if ok then
            remainingSeconds = number(remaining)
            isDayCooldown = dayCooldown == true
            currentCharges = number(charges)
            maxCharges = number(maximum)
        end
    end
    if C_Spell and type(C_Spell.GetSpellCharges) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCharges, recipeID)
        if ok and type(info) == "table" then
            currentCharges = currentCharges or number(info.currentCharges)
            maxCharges = maxCharges or number(info.maxCharges)
            local startTime = number(info.cooldownStartTime or info.startTime)
            local duration = number(info.cooldownDuration or info.duration)
            if startTime and duration and duration > 0 then
                durationSeconds = durationSeconds or duration
                local remaining = math.max(0, (startTime + duration) - currentTime)
                if remaining > 0 then
                    remainingSeconds = math.max(number(remainingSeconds) or 0, remaining)
                end
            end
        end
    end
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, recipeID)
        if ok and type(info) == "table" then
            local startTime = number(info.startTime or info.cooldownStartTime)
            local duration = number(info.duration or info.cooldownDuration)
            if startTime and duration and duration > 0 then
                durationSeconds = durationSeconds or duration
                local remaining = math.max(0, (startTime + duration) - currentTime)
                if remaining > 0 then
                    remainingSeconds = math.max(number(remainingSeconds) or 0, remaining)
                end
            end
        end
    end
    remainingSeconds = math.max(0, number(remainingSeconds) or 0)
    durationSeconds = math.max(0, number(durationSeconds) or remainingSeconds)
    if remainingSeconds > MAX_REASONABLE_COOLDOWN_SECONDS then remainingSeconds = 0 end
    if durationSeconds > MAX_REASONABLE_COOLDOWN_SECONDS then durationSeconds = 0 end
    maxCharges = maxCharges and math.max(0, math.floor(maxCharges + 0.5)) or nil
    currentCharges = currentCharges and math.max(0, math.floor(currentCharges + 0.5)) or nil
    if maxCharges and maxCharges <= 0 then maxCharges = nil end
    if currentCharges and maxCharges then currentCharges = math.min(maxCharges, currentCharges) end
    if maxCharges and currentCharges == nil then
        currentCharges = remainingSeconds > 0 and math.max(0, maxCharges - 1) or maxCharges
    end
    local hasCapability = isDayCooldown or (maxCharges and maxCharges > 0) or remainingSeconds > 0
    local readyTime = remainingSeconds > 0 and currentTime + remainingSeconds or 0
    local startTime = readyTime > 0 and math.max(0, readyTime - durationSeconds) or 0
    return {
        hasCooldownCapability = hasCapability == true,
        remainingSeconds = remainingSeconds,
        durationSeconds = durationSeconds,
        currentCharges = currentCharges,
        maxCharges = maxCharges,
        isDayCooldown = isDayCooldown,
        startTime = startTime,
        readyTime = readyTime,
    }
end

local function readConcentration(info, currentTime)
    if not C_TradeSkillUI or type(C_TradeSkillUI.GetConcentrationCurrencyID) ~= "function"
        or not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function"
    then
        return nil
    end
    for _, professionID in ipairs(info.professionIDs or {}) do
        local idOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, professionID)
        currencyID = idOk and number(currencyID) or nil
        if currencyID and currencyID > 0 then
            local infoOk, currency = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if infoOk and type(currency) == "table" and number(currency.quantity) then
                local current = math.max(0, math.floor(number(currency.quantity) + 0.5))
                local maximum = number(currency.maxQuantity or currency.maxWeeklyQuantity) or math.max(current, 1000)
                return {
                    currencyID = currencyID,
                    current = current,
                    maximum = math.max(current, math.floor(maximum + 0.5)),
                    scanTime = currentTime,
                }
            end
        end
    end
    return nil
end

local function cloneState(existing)
    local result = { updatedAt = number(type(existing) == "table" and existing.updatedAt) or 0, professions = {} }
    for key, value in pairs(type(existing) == "table" and existing.professions or {}) do
        result.professions[key] = value
    end
    return result
end

function Logic:ScanOpenProfession(identity, existing, currentTime)
    if not C_TradeSkillUI or type(C_TradeSkillUI.GetAllRecipeIDs) ~= "function" then
        return existing, false
    end
    currentTime = number(currentTime) or now()
    local info = readOpenTradeSkillInfo()
    local professionKey = getProfessionKey(info.name, info.skillLineID, identity)
    if not professionKey or not CRAFTING_PROFESSIONS[professionKey] then
        return existing, false
    end
    local state = cloneState(existing)
    local previous = type(state.professions[professionKey]) == "table" and state.professions[professionKey] or {}
    local professionState = {
        professionKey = professionKey,
        professionName = getProfessionName(professionKey, info.name, identity),
        skillLineID = number(info.skillLineID) or previous.skillLineID,
        updatedAt = currentTime,
        concentration = readConcentration(info, currentTime) or previous.concentration,
        cooldowns = {},
    }
    local recipesOk, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not recipesOk or type(recipeIDs) ~= "table" then
        professionState.cooldowns = previous.cooldowns or {}
        state.professions[professionKey] = professionState
        state.updatedAt = currentTime
        return state, true
    end
    local previousCooldowns = type(previous.cooldowns) == "table" and previous.cooldowns or {}
    for _, rawRecipeID in ipairs(recipeIDs) do
        local recipeID = number(rawRecipeID)
        if recipeID then
            local recipeInfo
            if type(C_TradeSkillUI.GetRecipeInfo) == "function" then
                local ok, value = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                recipeInfo = ok and type(value) == "table" and value or nil
            end
            if not recipeInfo or recipeInfo.learned ~= false then
                local cooldown = self:ParseRecipeCooldown(recipeID, currentTime) or {}
                local old = previousCooldowns[recipeID] or previousCooldowns[tostring(recipeID)]
                local oldEntry = type(old) == "table" and old or nil
                local name = recipeInfo and recipeInfo.name or (type(old) == "table" and old.name) or getSpellName(recipeID)
                if type(name) == "string" and name ~= "" and (cooldown.hasCooldownCapability or type(old) == "table") then
                    professionState.cooldowns[recipeID] = {
                        recipeID = recipeID,
                        name = name,
                        icon = recipeInfo and (recipeInfo.iconFileID or recipeInfo.icon) or (oldEntry and oldEntry.icon),
                        expansionID = recipeInfo and number(recipeInfo.expansionID) or (oldEntry and oldEntry.expansionID),
                        expansionName = recipeInfo and recipeInfo.expansionName or (oldEntry and oldEntry.expansionName),
                        currentCharges = cooldown.currentCharges,
                        maxCharges = cooldown.maxCharges,
                        durationSeconds = cooldown.durationSeconds or (oldEntry and oldEntry.durationSeconds) or 0,
                        startTime = cooldown.startTime or 0,
                        readyTime = cooldown.readyTime or 0,
                        isDayCooldown = cooldown.isDayCooldown == true,
                        lastSeen = currentTime,
                    }
                end
            end
        end
    end
    state.professions[professionKey] = professionState
    state.updatedAt = currentTime
    return state, true
end

local function formatElapsed(seconds)
    seconds = math.max(0, math.floor(number(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then return string.format(L.TIME_DAY_HOUR, days, hours) end
    if hours > 0 then return string.format(L.TIME_HOUR_MIN, hours, minutes) end
    return string.format(L.TIME_MIN, minutes)
end

local function formatLastSeen(timestamp, currentTime)
    timestamp = number(timestamp)
    if not timestamp or timestamp <= 0 then return L.TIME_NEVER end
    local delta = math.max(0, currentTime - timestamp)
    if delta < 60 then return L.TIME_JUST_NOW end
    return string.format(L.TIME_AGO, formatElapsed(delta))
end

local function simulateConcentration(concentration, currentTime)
    if type(concentration) ~= "table" then return nil end
    local current, maximum, scanTime = number(concentration.current), number(concentration.maximum), number(concentration.scanTime)
    if not current or not maximum or maximum <= 0 then return nil end
    local gained = scanTime and math.floor(math.max(0, currentTime - scanTime) / CONCENTRATION_REGEN_SECONDS) or 0
    local estimated = math.min(maximum, math.max(0, math.floor(current + gained + 0.5)))
    return { current = math.floor(current + 0.5), estimated = estimated, maximum = math.floor(maximum + 0.5), scanTime = scanTime, ratio = estimated / maximum }
end

function Logic:SimulateCooldown(cooldown, currentTime)
    if type(cooldown) ~= "table" then return nil end
    local maxCharges, currentCharges = number(cooldown.maxCharges), number(cooldown.currentCharges)
    local duration = math.max(0, number(cooldown.durationSeconds) or 0)
    local readyTime = math.max(0, number(cooldown.readyTime) or 0)
    local remaining = math.max(0, readyTime - currentTime)
    if maxCharges and maxCharges > 0 then
        maxCharges = math.floor(maxCharges + 0.5)
        currentCharges = currentCharges and math.floor(currentCharges + 0.5) or (remaining > 0 and math.max(0, maxCharges - 1) or maxCharges)
        currentCharges = math.max(0, math.min(maxCharges, currentCharges))
        if duration > 0 and readyTime > 0 and currentTime >= readyTime and currentCharges < maxCharges then
            local gained = math.floor((currentTime - readyTime) / duration) + 1
            currentCharges = math.min(maxCharges, currentCharges + gained)
            if currentCharges < maxCharges then
                readyTime = readyTime + gained * duration
                remaining = math.max(0, readyTime - currentTime)
            else
                remaining = 0
            end
        end
        return { ready = currentCharges >= maxCharges, remainingSeconds = remaining, currentCharges = currentCharges, maxCharges = maxCharges }
    end
    return { ready = remaining <= 0, remainingSeconds = remaining }
end

local function addKnownProfessions(result, byKey, identity)
    for _, profession in ipairs(getIdentityProfessions(identity)) do
        local professionKey = DATA.skillLineToKey[number(profession.skillLineID)] or keyFromName(profession.name)
        if CRAFTING_PROFESSIONS[professionKey] and not byKey[professionKey] then
            local entry = { professionKey = professionKey, professionName = profession.name or professionKey, skillLineID = number(profession.skillLineID) }
            result[#result + 1] = entry
            byKey[professionKey] = entry
        end
    end
end

local function addStoredProfessions(result, byKey, snapshot)
    for professionKey, profession in pairs(type(snapshot) == "table" and snapshot.professions or {}) do
        if CRAFTING_PROFESSIONS[professionKey] and not byKey[professionKey] then
            local entry = { professionKey = professionKey, professionName = profession.professionName or professionKey, skillLineID = profession.skillLineID }
            result[#result + 1] = entry
            byKey[professionKey] = entry
        end
    end
end

function Logic:BuildView(identity, snapshot, isCurrentCharacter, currentTime)
    currentTime = number(currentTime) or now()
    local professions, byKey = {}, {}
    addKnownProfessions(professions, byKey, identity)
    addStoredProfessions(professions, byKey, snapshot)
    table.sort(professions, function(left, right) return tostring(left.professionName) < tostring(right.professionName) end)
    local concentrationRows, cooldownRows = {}, {}
    local concentrationKnown, cooldownReady, cooldownTotal = 0, 0, 0
    local updatedAt = number(type(snapshot) == "table" and snapshot.updatedAt) or 0
    for _, profession in ipairs(professions) do
        local state = type(snapshot) == "table" and type(snapshot.professions) == "table" and snapshot.professions[profession.professionKey] or nil
        local concentration = simulateConcentration(state and state.concentration, currentTime)
        local hint = isCurrentCharacter and L.PROFESSION_COOLDOWNS_OPEN_HINT or L.PROFESSION_COOLDOWNS_ALT_HINT
        local row = {
            label = string.format("%s %s", profession.professionName, L.PROFESSION_COOLDOWNS_CONCENTRATION),
            text = L.PROFESSION_COOLDOWNS_UNKNOWN_CONCENTRATION,
            ratio = 0,
            status = "missing",
            tooltipTitle = profession.professionName,
            tooltipLines = { hint },
        }
        if concentration then
            concentrationKnown = concentrationKnown + 1
            row.text = string.format("%d/%d", concentration.estimated, concentration.maximum)
            row.ratio = concentration.ratio
            row.status = concentration.estimated >= concentration.maximum and "complete" or "open"
            row.tooltipLines = {
                string.format(L.PROFESSION_COOLDOWNS_CONCENTRATION_TOOLTIP, concentration.current, concentration.maximum, concentration.estimated, concentration.maximum),
                string.format(L.PROFESSION_COOLDOWNS_LAST_SYNC, formatLastSeen(concentration.scanTime, currentTime)),
            }
            if not isCurrentCharacter then row.tooltipLines[#row.tooltipLines + 1] = L.PROFESSION_COOLDOWNS_ALT_HINT end
        end
        concentrationRows[#concentrationRows + 1] = row
        if type(state) == "table" then
            updatedAt = math.max(updatedAt, number(state.updatedAt) or 0)
            for _, cooldown in pairs(type(state.cooldowns) == "table" and state.cooldowns or {}) do
                local simulated = self:SimulateCooldown(cooldown, currentTime)
                if simulated then
                    cooldownTotal = cooldownTotal + 1
                    if simulated.ready then cooldownReady = cooldownReady + 1 end
                    local text
                    if simulated.maxCharges and simulated.maxCharges > 1 then
                        text = string.format("%d/%d", simulated.currentCharges or 0, simulated.maxCharges)
                    elseif simulated.ready then
                        text = L.PROFESSION_COOLDOWNS_READY
                    else
                        text = formatElapsed(simulated.remainingSeconds)
                    end
                    local status = simulated.ready and "complete" or ((simulated.remainingSeconds or 0) <= 3600 and "warning" or "locked")
                    local tooltipLines = { string.format("%s: %s", L.SYSTEMS_TAB_PROFESSIONS, profession.professionName) }
                    if simulated.maxCharges then
                        tooltipLines[#tooltipLines + 1] = string.format("%d/%d %s", simulated.currentCharges or 0, simulated.maxCharges, L.PROFESSION_COOLDOWNS_CHARGES)
                    end
                    if not simulated.ready then
                        tooltipLines[#tooltipLines + 1] = string.format("%s: %s", L.PROFESSION_COOLDOWNS_READY_IN, formatElapsed(simulated.remainingSeconds))
                    end
                    tooltipLines[#tooltipLines + 1] = string.format(L.PROFESSION_COOLDOWNS_LAST_SYNC, formatLastSeen(cooldown.lastSeen or updatedAt, currentTime))
                    cooldownRows[#cooldownRows + 1] = {
                        key = "profession_cooldown_" .. tostring(cooldown.recipeID),
                        label = string.format("%s - %s", profession.professionName, cooldown.name or tostring(cooldown.recipeID)),
                        text = text,
                        status = status,
                        completed = simulated.ready == true,
                        seen = true,
                        ready = simulated.ready == true,
                        remainingSeconds = simulated.remainingSeconds or 0,
                        badgeTexture = cooldown.icon,
                        tooltipTitle = cooldown.name or tostring(cooldown.recipeID),
                        tooltipLines = tooltipLines,
                    }
                end
            end
        end
    end
    table.sort(cooldownRows, function(left, right)
        if left.ready ~= right.ready then return left.ready == true end
        if left.remainingSeconds ~= right.remainingSeconds then return left.remainingSeconds < right.remainingSeconds end
        return tostring(left.label) < tostring(right.label)
    end)
    return {
        updatedAt = updatedAt,
        professions = professions,
        concentrationRows = concentrationRows,
        cooldownRows = cooldownRows,
        summary = {
            concentrationKnown = concentrationKnown,
            concentrationTotal = #concentrationRows,
            cooldownReady = cooldownReady,
            cooldownTotal = cooldownTotal,
            updatedAt = updatedAt,
            lastSyncText = updatedAt > 0 and formatLastSeen(updatedAt, currentTime) or "",
        },
    }
end
