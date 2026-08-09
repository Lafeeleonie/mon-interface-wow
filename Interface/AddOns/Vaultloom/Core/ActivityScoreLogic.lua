local _, Addon = ...

local Logic = {}
Addon.ActivityScoreLogic = Logic

local TIERS = {
    { minimum = 80, key = "orange", color = { 1.00, 0.50, 0.00 }, hex = "ffff8000" },
    { minimum = 60, key = "purple", color = { 0.64, 0.21, 0.93 }, hex = "ffa335ee" },
    { minimum = 40, key = "blue", color = { 0.00, 0.44, 0.87 }, hex = "ff0070dd" },
    { minimum = 20, key = "green", color = { 0.12, 1.00, 0.00 }, hex = "ff1eff00" },
    { minimum = 0, key = "gray", color = { 0.62, 0.62, 0.62 }, hex = "ff9d9d9d" },
}

local WEIGHTS = {
    vault = 18,
    weekly = 10,
    events = 8,
    world = 8,
    delves = 10,
    prey = 8,
    pvp = 5,
    professions = 7,
}

local WORLD_SCORE_KEYS = {
    world_boss_weekly = true,
    world_key_shards = true,
    world_dundun_shards = true,
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or 0))
end

local function isCurrentSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    local resetAt = tonumber(snapshot.resetAt) or 0
    return resetAt <= 0 or type(time) ~= "function" or resetAt > time()
end

local function isAvailable(row)
    if type(row) ~= "table" or row.available == false or row.unlocked == false then
        return false
    end
    local status = tostring(row.status or "")
    return status ~= "locked" and status ~= "unavailable" and status ~= "disabled"
end

local function isComplete(row)
    if type(row) ~= "table" then
        return false
    end
    local status = tostring(row.status or "")
    if row.completed == true or status == "complete" or status == "completed" or status == "done" then
        return true
    end
    local current = tonumber(row.count or row.current or row.progress)
    local maximum = tonumber(row.maxCount or row.cap or row.total)
    return current ~= nil and maximum ~= nil and maximum > 0 and current >= maximum
end

local function getTier(score)
    for _, tier in ipairs(TIERS) do
        if score >= tier.minimum then
            return tier
        end
    end
    return TIERS[#TIERS]
end

local function addComponent(result, key, label, weight, completed, total)
    total = math.max(0, tonumber(total) or 0)
    completed = clamp(completed, 0, total)
    if total <= 0 then
        return
    end
    local ratio = completed / total
    result.maximum = result.maximum + weight
    result.earned = result.earned + (weight * ratio)
    result.details[#result.details + 1] = {
        key = key,
        label = label,
        completed = completed,
        total = total,
        ratio = ratio,
        value = string.format("%d/%d", math.floor(completed + 0.5), math.floor(total + 0.5)),
    }
end

local function addRows(result, key, label, weight, snapshot, predicate)
    if not isCurrentSnapshot(snapshot) then
        return
    end
    local completed, total = 0, 0
    for _, row in ipairs(snapshot.rows or {}) do
        if (type(predicate) ~= "function" or predicate(row)) and isAvailable(row) then
            total = total + 1
            if isComplete(row) then
                completed = completed + 1
            end
        end
    end
    addComponent(result, key, label, weight, completed, total)
end

function Logic:GetVaultSummary(record)
    local snapshot = type(record) == "table" and type(record.snapshots) == "table"
        and record.snapshots.vault or nil
    local summary = {
        available = isCurrentSnapshot(snapshot),
        ratio = 0,
        raid = { key = "raid", current = nil, maximum = nil },
        dungeon = { key = "dungeon", current = nil, maximum = nil },
        world = { key = "world", current = nil, maximum = nil },
    }
    if not summary.available then
        return summary
    end

    local ratioTotal, ratioCount = 0, 0
    for _, key in ipairs({ "raid", "dungeon", "world" }) do
        local row = snapshot.rows and snapshot.rows[key]
        local thresholds = row and row.thresholds or {}
        local maximum = math.max(0, tonumber(thresholds[#thresholds]) or 0)
        local current = maximum > 0 and math.min(maximum, math.max(0, tonumber(row and row.completedCount) or 0)) or 0
        summary[key] = {
            key = key,
            current = current,
            maximum = maximum,
            complete = maximum > 0 and current >= maximum,
        }
        if maximum > 0 then
            ratioTotal = ratioTotal + (current / maximum)
            ratioCount = ratioCount + 1
        end
    end
    summary.ratio = ratioCount > 0 and ratioTotal / ratioCount or 0
    return summary
end

function Logic:Build(record)
    local snapshots = type(record) == "table" and type(record.snapshots) == "table" and record.snapshots or {}
    local result = {
        earned = 0,
        maximum = 0,
        details = {},
        vault = self:GetVaultSummary(record),
    }

    if result.vault.available then
        local completed, total = 0, 0
        for _, key in ipairs({ "raid", "dungeon", "world" }) do
            local entry = result.vault[key]
            if (entry.maximum or 0) > 0 then
                completed = completed + clamp(entry.current, 0, entry.maximum)
                total = total + entry.maximum
            end
        end
        addComponent(result, "vault", Addon.L.ACTIVITY_SCORE_VAULT, WEIGHTS.vault, completed, total)
    end

    addRows(result, "weekly", Addon.L.ACTIVITY_SCORE_WEEKLY, WEIGHTS.weekly, snapshots.pveWeekly)
    addRows(result, "events", Addon.L.ACTIVITY_SCORE_EVENTS, WEIGHTS.events, snapshots.pveEvents)
    addRows(result, "world", Addon.L.ACTIVITY_SCORE_WORLD, WEIGHTS.world, snapshots.pveWorld, function(row)
        return WORLD_SCORE_KEYS[tostring(row and row.key or "")] == true
    end)
    addRows(result, "delves", Addon.L.ACTIVITY_SCORE_DELVES, WEIGHTS.delves, snapshots.pveDelves)

    local prey = snapshots.pvePrey
    if isCurrentSnapshot(prey) then
        local completed, total = 0, 0
        if isAvailable(prey.weeklyQuest) then
            total = total + 1
            if isComplete(prey.weeklyQuest) then completed = completed + 1 end
        end
        for _, key in ipairs({ "normal", "hard", "nightmare" }) do
            local difficulty = prey.difficulties and prey.difficulties[key]
            if type(difficulty) == "table" and difficulty.unlocked ~= false then
                local cap = math.max(1, tonumber(difficulty.cap or prey.difficultyCap) or 1)
                total = total + cap
                completed = completed + clamp(difficulty.count, 0, cap)
            end
        end
        addComponent(result, "prey", Addon.L.ACTIVITY_SCORE_PREY, WEIGHTS.prey, completed, total)
    end

    addRows(result, "pvp", Addon.L.ACTIVITY_SCORE_PVP, WEIGHTS.pvp, snapshots.pvpWeekly)
    addRows(result, "professions", Addon.L.ACTIVITY_SCORE_PROFESSIONS, WEIGHTS.professions, snapshots.professions, function(row)
        return tostring(row and row.key or ""):find("^profession_service_") ~= nil
    end)

    result.score = result.maximum > 0 and math.floor(clamp((result.earned / result.maximum) * 100, 0, 100) + 0.5) or 0
    local tier = getTier(result.score)
    result.tier = tier.key
    result.color = tier.color
    result.hex = tier.hex
    result.label = string.format(Addon.L.ACTIVITY_SCORE_FORMAT, result.score)
    result.coloredLabel = string.format("|c%s%s|r", tier.hex, result.label)
    return result
end
