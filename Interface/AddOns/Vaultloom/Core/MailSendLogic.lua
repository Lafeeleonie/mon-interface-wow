local _, Addon = ...

local Logic = {}
Addon.MailSendLogic = Logic

local VALID_MATCH_TYPES = {
    item = true,
    subclass = true,
    class = true,
}

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("[%c]", " ")
    value = value:gsub("%s+", " ")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizePositive(value)
    value = math.floor(tonumber(value) or 0)
    return value > 0 and value or nil
end

local function actionKey(item)
    return tostring(item and item.bagID or "?") .. ":" .. tostring(item and item.slotID or "?")
end

function Logic:NormalizeRecipient(value)
    value = trim(value)
    if value == "" or #value > 96 or value:find("[,;]") then return nil end
    return value
end

function Logic:ParseRecipientList(value)
    value = tostring(value or ""):gsub("[\r\n;]+", ",")
    local result, seen = {}, {}
    for part in value:gmatch("[^,]+") do
        local recipient = self:NormalizeRecipient(part)
        local key = recipient and string.lower(recipient) or nil
        if recipient and not seen[key] then
            seen[key] = true
            result[#result + 1] = recipient
        end
    end
    return result
end

function Logic:BuildRecipientSuggestions(favorites, recent, roster, currentKey, limit, query)
    local result, seen = {}, {}
    limit = math.max(1, math.floor(tonumber(limit) or 8))
    currentKey = string.lower(trim(currentKey))
    query = string.lower(trim(query))

    local function add(value, source)
        local recipient = Logic:NormalizeRecipient(type(value) == "table" and value.name or value)
        local key = recipient and string.lower(recipient) or nil
        if not recipient or seen[key] or key == currentKey or #result >= limit then return end
        if query ~= "" and not key:find(query, 1, true) then return end
        seen[key] = true
        result[#result + 1] = { name = recipient, source = source }
    end

    for _, value in ipairs(type(favorites) == "table" and favorites or {}) do
        add(value, "favorite")
    end
    for _, value in ipairs(type(recent) == "table" and recent or {}) do
        add(value, "recent")
    end
    for _, character in ipairs(type(roster) == "table" and roster or {}) do
        local name = trim(character and character.name)
        local realm = trim(character and character.realm)
        local recipient = name ~= "" and (realm ~= "" and (name .. "-" .. realm) or name) or nil
        add(recipient, "alt")
    end
    return result
end

function Logic:NormalizeRule(rule)
    if type(rule) ~= "table" then return nil end
    local recipient = self:NormalizeRecipient(rule.recipient)
    local matchType = VALID_MATCH_TYPES[rule.matchType] and rule.matchType or nil
    local itemID = normalizePositive(rule.itemID)
    local classID = tonumber(rule.classID)
    local subClassID = tonumber(rule.subClassID)
    if not recipient or not matchType then return nil end
    if matchType == "item" and not itemID then return nil end
    if matchType == "class" and classID == nil then return nil end
    if matchType == "subclass" and (classID == nil or subClassID == nil) then return nil end
    return {
        id = normalizePositive(rule.id),
        enabled = rule.enabled ~= false,
        name = trim(rule.name),
        recipient = recipient,
        matchType = matchType,
        itemID = itemID,
        classID = classID and math.floor(classID) or nil,
        subClassID = subClassID and math.floor(subClassID) or nil,
        keepCount = math.max(0, math.floor(tonumber(rule.keepCount) or 0)),
        subject = trim(rule.subject),
        body = tostring(rule.body or ""),
    }
end

function Logic:RuleMatchesItem(rule, item)
    rule = self:NormalizeRule(rule)
    if not rule or rule.enabled ~= true or type(item) ~= "table" or item.eligible == false then
        return false
    end
    if rule.matchType == "item" then
        return normalizePositive(item.itemID) == rule.itemID
    elseif rule.matchType == "class" then
        return tonumber(item.classID) == rule.classID
    end
    return tonumber(item.classID) == rule.classID
        and tonumber(item.subClassID) == rule.subClassID
end

function Logic:BuildRuleLabel(rule)
    rule = self:NormalizeRule(rule)
    if not rule then return "" end
    local match = rule.name ~= "" and rule.name
        or rule.matchType == "item" and ("#" .. tostring(rule.itemID))
        or rule.matchType == "subclass" and (tostring(rule.classID) .. "." .. tostring(rule.subClassID))
        or tostring(rule.classID)
    return match .. " -> " .. rule.recipient
end

function Logic:BuildPlan(items, rules, maximumAttachments, defaultSubject, defaultBody)
    maximumAttachments = math.max(1, math.floor(tonumber(maximumAttachments) or 12))
    defaultSubject = trim(defaultSubject)
    defaultBody = tostring(defaultBody or "")
    local plan = {
        letters = {},
        summary = { letters = 0, attachments = 0, itemUnits = 0, recipients = 0, rules = 0 },
    }
    local claimed, recipients = {}, {}

    for _, rawRule in ipairs(type(rules) == "table" and rules or {}) do
        local rule = self:NormalizeRule(rawRule)
        if rule and rule.enabled then
            local matches, total = {}, 0
            for _, item in ipairs(type(items) == "table" and items or {}) do
                local key = actionKey(item)
                local count = math.max(0, math.floor(tonumber(item and item.count) or 0))
                if count > 0 and not claimed[key] and self:RuleMatchesItem(rule, item) then
                    claimed[key] = true
                    matches[#matches + 1] = item
                    total = total + count
                end
            end

            local remaining = math.max(0, total - rule.keepCount)
            local actions = {}
            for _, item in ipairs(matches) do
                if remaining <= 0 then break end
                local available = math.max(0, math.floor(tonumber(item.count) or 0))
                local sendCount = math.min(available, remaining)
                if sendCount > 0 then
                    actions[#actions + 1] = {
                        bagID = item.bagID,
                        slotID = item.slotID,
                        itemID = item.itemID,
                        count = sendCount,
                        stackCount = available,
                        itemName = item.itemName,
                        itemLink = item.itemLink,
                    }
                    remaining = remaining - sendCount
                end
            end

            if #actions > 0 then
                plan.summary.rules = plan.summary.rules + 1
                recipients[string.lower(rule.recipient)] = true
                local index = 1
                while index <= #actions do
                    local letter = {
                        recipient = rule.recipient,
                        subject = rule.subject ~= "" and rule.subject
                            or defaultSubject ~= "" and defaultSubject
                            or "Vaultloom",
                        body = rule.body ~= "" and rule.body or defaultBody,
                        ruleID = rule.id,
                        actions = {},
                        itemUnits = 0,
                    }
                    for _ = 1, maximumAttachments do
                        local action = actions[index]
                        if not action then break end
                        letter.actions[#letter.actions + 1] = action
                        letter.itemUnits = letter.itemUnits + action.count
                        plan.summary.attachments = plan.summary.attachments + 1
                        plan.summary.itemUnits = plan.summary.itemUnits + action.count
                        index = index + 1
                    end
                    plan.letters[#plan.letters + 1] = letter
                end
            end
        end
    end

    for _ in pairs(recipients) do plan.summary.recipients = plan.summary.recipients + 1 end
    plan.summary.letters = #plan.letters
    return plan
end

function Logic:BuildQuickActions(items, seed, mode, limit)
    mode = tostring(mode or "same")
    limit = math.max(0, math.floor(tonumber(limit) or 12))
    seed = type(seed) == "table" and seed or {}
    local result = {}
    for _, item in ipairs(type(items) == "table" and items or {}) do
        local matches = false
        if type(item) == "table" and item.eligible ~= false then
            if mode == "same" then
                matches = normalizePositive(seed.itemID) == normalizePositive(item.itemID)
            elseif mode == "type" then
                matches = tonumber(seed.classID) == tonumber(item.classID)
                    and tonumber(seed.subClassID) == tonumber(item.subClassID)
            elseif mode == "materials" then
                matches = tonumber(item.classID) == 7
            elseif mode == "all" then
                matches = true
            end
        end
        if matches and #result < limit then
            result[#result + 1] = {
                bagID = item.bagID,
                slotID = item.slotID,
                itemID = item.itemID,
                count = item.count,
                stackCount = item.count,
                itemName = item.itemName,
                itemLink = item.itemLink,
            }
        end
    end
    return result
end

function Logic:BuildMassPlan(recipients, subject, body)
    subject = trim(subject)
    body = tostring(body or "")
    local plan = {
        letters = {},
        summary = { letters = 0, attachments = 0, itemUnits = 0, recipients = 0, rules = 0 },
    }
    for _, recipient in ipairs(type(recipients) == "table" and recipients or {}) do
        recipient = self:NormalizeRecipient(recipient)
        if recipient then
            plan.letters[#plan.letters + 1] = {
                recipient = recipient,
                subject = subject,
                body = body,
                actions = {},
                itemUnits = 0,
            }
        end
    end
    plan.summary.letters = #plan.letters
    plan.summary.recipients = #plan.letters
    return plan
end
