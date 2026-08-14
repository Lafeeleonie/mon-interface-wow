local _, Addon = ...

local Logic = {}
Addon.MailLogic = Logic

local DAY_SECONDS = 24 * 60 * 60

local function normalizeNumber(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function normalizeText(value)
    value = tostring(value or "")
    value = value:gsub("|A:[^|]+|a", "")
    value = value:gsub("|T[^|]+|t", "")
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|r", "")
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return string.lower(value)
end

function Logic:NormalizeText(value)
    return normalizeText(value)
end

function Logic:ParseItemID(value)
    value = type(value) == "table" and (value.itemID or value.itemLink or value.link) or value
    if type(value) == "number" and value > 0 then
        return math.floor(value)
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local itemID = tonumber(value:match("item:(%-?%d+)"))
    return itemID and itemID > 0 and math.floor(itemID) or nil
end

function Logic:BuildMessageKey(message)
    message = type(message) == "table" and message or {}
    local attachmentParts = {}
    for _, attachment in ipairs(type(message.attachments) == "table" and message.attachments or {}) do
        attachmentParts[#attachmentParts + 1] = table.concat({
            tostring(normalizeNumber(attachment.slot)),
            tostring(normalizeNumber(attachment.itemID)),
            tostring(normalizeNumber(attachment.count)),
            attachment.isCurrency == true and "currency" or "item",
        }, ":")
    end
    local expiryMinute = math.floor(normalizeNumber(message.expiresAt) / 60)
    return table.concat({
        normalizeText(message.sender),
        normalizeText(message.subject),
        tostring(normalizeNumber(message.money)),
        tostring(normalizeNumber(message.cod)),
        tostring(expiryMinute),
        table.concat(attachmentParts, ","),
    }, "\031")
end

function Logic:BuildThreadKey(message)
    message = type(message) == "table" and message or {}
    local expiryMinute = math.floor(normalizeNumber(message.expiresAt) / 60)
    return table.concat({
        normalizeText(message.sender),
        normalizeText(message.subject),
        tostring(expiryMinute),
        message.isAuction == true and "auction" or "mail",
        message.isGM == true and "gm" or "player",
    }, "\031")
end

function Logic:GetExpiryState(message, warningDays, timestamp)
    message = type(message) == "table" and message or {}
    timestamp = normalizeNumber(timestamp)
    warningDays = math.max(1, math.floor(tonumber(warningDays) or 3))
    local expiresAt = normalizeNumber(message.expiresAt)
    if expiresAt <= 0 then
        return "unknown", nil
    end
    local remaining = expiresAt - timestamp
    if remaining <= 0 then
        return "expired", 0
    end
    if remaining <= DAY_SECONDS then
        return "urgent", remaining
    end
    if remaining <= warningDays * DAY_SECONDS then
        return "warning", remaining
    end
    return "normal", remaining
end

function Logic:IsExpiring(message, warningDays, timestamp)
    local state = self:GetExpiryState(message, warningDays, timestamp)
    return state == "expired" or state == "urgent" or state == "warning"
end

function Logic:MatchesSearch(message, search)
    local needle = normalizeText(search)
    if needle == "" then
        return true
    end
    message = type(message) == "table" and message or {}
    local parts = {
        message.sender,
        message.subject,
    }
    for _, attachment in ipairs(type(message.attachments) == "table" and message.attachments or {}) do
        parts[#parts + 1] = attachment.itemName
        parts[#parts + 1] = attachment.itemLink
    end
    return normalizeText(table.concat(parts, " ")):find(needle, 1, true) ~= nil
end

function Logic:MatchesFilter(message, filterKey, warningDays, timestamp)
    message = type(message) == "table" and message or {}
    filterKey = tostring(filterKey or "all")
    local attachments = type(message.attachments) == "table" and message.attachments or {}
    if filterKey == "items" then
        return #attachments > 0
    elseif filterKey == "money" then
        return normalizeNumber(message.money) > 0
    elseif filterKey == "auction" then
        return message.isAuction == true
    elseif filterKey == "expiring" then
        return self:IsExpiring(message, warningDays, timestamp)
    end
    return true
end

function Logic:IsSafeToCollect(message)
    message = type(message) == "table" and message or {}
    if message.isGM == true then
        return false, "gm"
    end
    if normalizeNumber(message.cod) > 0 then
        return false, "cod"
    end
    if normalizeNumber(message.money) == 0
        and #(type(message.attachments) == "table" and message.attachments or {}) == 0
    then
        return false, "empty"
    end
    return true
end

function Logic:CanCollect(message, filterKey, warningDays, timestamp)
    local safe, reason = self:IsSafeToCollect(message)
    if not safe then
        return false, reason
    end
    if not self:MatchesFilter(message, filterKey, warningDays, timestamp) then
        return false, "filter"
    end
    return true
end

function Logic:FilterMessages(messages, search, filterKey, warningDays, timestamp)
    local result = {}
    for _, message in ipairs(type(messages) == "table" and messages or {}) do
        if type(message) == "table"
            and self:MatchesSearch(message, search)
            and self:MatchesFilter(message, filterKey, warningDays, timestamp)
        then
            result[#result + 1] = message
        end
    end
    return result
end

function Logic:BuildSummary(messages, warningDays, timestamp)
    local summary = {
        messages = 0,
        attachments = 0,
        itemUnits = 0,
        money = 0,
        cod = 0,
        gm = 0,
        auction = 0,
        expiring = 0,
        collectable = 0,
    }
    for _, message in ipairs(type(messages) == "table" and messages or {}) do
        if type(message) == "table" then
            summary.messages = summary.messages + 1
            summary.money = summary.money + normalizeNumber(message.money)
            summary.cod = summary.cod + normalizeNumber(message.cod)
            if message.isGM == true then summary.gm = summary.gm + 1 end
            if message.isAuction == true then summary.auction = summary.auction + 1 end
            if self:IsExpiring(message, warningDays, timestamp) then
                summary.expiring = summary.expiring + 1
            end
            local safe = self:IsSafeToCollect(message)
            if safe then summary.collectable = summary.collectable + 1 end
            for _, attachment in ipairs(type(message.attachments) == "table" and message.attachments or {}) do
                summary.attachments = summary.attachments + 1
                summary.itemUnits = summary.itemUnits + math.max(1, normalizeNumber(attachment.count))
            end
        end
    end
    return summary
end

function Logic:BuildSnapshot(characterKey, messages, updatedAt, totalMessages, warningDays)
    updatedAt = normalizeNumber(updatedAt)
    messages = type(messages) == "table" and messages or {}
    local snapshot = {
        version = 1,
        characterKey = tostring(characterKey or ""),
        updatedAt = updatedAt,
        totalMessages = math.max(#messages, normalizeNumber(totalMessages)),
        messages = messages,
    }
    snapshot.summary = self:BuildSummary(messages, warningDays, updatedAt)
    return snapshot
end

function Logic:CountExpiringSnapshots(snapshots, warningDays, timestamp)
    local characters, messages = 0, 0
    for _, snapshot in pairs(type(snapshots) == "table" and snapshots or {}) do
        local characterMessages = 0
        for _, message in ipairs(type(snapshot and snapshot.messages) == "table" and snapshot.messages or {}) do
            if self:IsExpiring(message, warningDays, timestamp) then
                characterMessages = characterMessages + 1
            end
        end
        if characterMessages > 0 then
            characters = characters + 1
            messages = messages + characterMessages
        end
    end
    return messages, characters
end
