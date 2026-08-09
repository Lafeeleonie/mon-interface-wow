local _, Addon = ...

local Logic = {}
Addon.QuietLootLogic = Logic

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function Logic:NormalizeText(value)
    value = trim(value)
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("%s+", " ")
    return string.lower(value)
end

function Logic:ExtractItemLink(value)
    value = tostring(value or "")
    return value:match("(|Hitem:[^|]+|h%[[^]]-%]|h)")
        or value:match("(|Hitem:[^|]+|h.-|h)")
end

function Logic:ExtractCurrencyLink(value)
    value = tostring(value or "")
    return value:match("(|Hcurrency:[^|]+|h%[[^]]-%]|h)")
        or value:match("(|Hcurrency:[^|]+|h.-|h)")
end

function Logic:GetItemID(value)
    if type(value) == "number" then
        return math.max(0, math.floor(value))
    end
    return tonumber(tostring(value or ""):match("|Hitem:(%d+)"))
        or tonumber(tostring(value or ""):match("^item:(%d+)"))
end

function Logic:GetCurrencyID(value)
    if type(value) == "number" then
        return math.max(0, math.floor(value))
    end
    return tonumber(tostring(value or ""):match("|Hcurrency:(%d+)"))
        or tonumber(tostring(value or ""):match("^currency:(%d+)"))
end

function Logic:ExtractQuantity(value, fallback)
    value = tostring(value or "")
    local quantity = value:match("[xX]%s*(%d+)")
        or value:match("(%d+)%s*[xX]")
    return math.max(1, math.floor(tonumber(quantity) or tonumber(fallback) or 1))
end

function Logic:GetResourceKey(data)
    if type(data) ~= "table" then return nil end
    if data.kind == "item" then
        local itemID = self:GetItemID(data.itemID or data.link)
        if itemID then return "item:" .. itemID end
    elseif data.kind == "currency" then
        local currencyID = self:GetCurrencyID(data.currencyID or data.link)
        if currencyID then return "currency:" .. currencyID end
    elseif data.kind == "money" then
        return "money"
    elseif data.kind == "quest" and data.questID then
        return "quest:" .. tostring(data.questID)
    end

    local name = self:NormalizeText(data.name)
    if name ~= "" then
        return tostring(data.kind or "unknown") .. ":" .. name
    end
    return nil
end

function Logic:GetSignature(data)
    local key = self:GetResourceKey(data)
    if not key then return nil end
    local quantity = math.max(1, math.floor(tonumber(data.quantity) or 1))
    return key .. ":" .. quantity
end

function Logic:ShouldSuppress(recent, data, source, now, window)
    if type(recent) ~= "table" then return false end
    now = tonumber(now) or 0
    window = math.max(0, tonumber(window) or 1.25)
    source = tostring(source or "unknown")

    for signature, record in pairs(recent) do
        if type(record) ~= "table" or now - (tonumber(record.at) or 0) > math.max(3, window * 2) then
            recent[signature] = nil
        end
    end

    local signature = self:GetSignature(data)
    if not signature then return false end
    local previous = recent[signature]
    if previous
        and previous.source ~= source
        and now - (tonumber(previous.at) or 0) >= 0
        and now - (tonumber(previous.at) or 0) <= window
    then
        return true
    end

    recent[signature] = {
        source = source,
        at = now,
    }
    return false
end

function Logic:PlayerMatches(playerName, unitName, fullName)
    local candidate = self:NormalizeText(playerName)
    if candidate == "" then return false end
    local short = self:NormalizeText(unitName)
    local full = self:NormalizeText(fullName)
    if candidate == short or candidate == full then return true end
    local candidateShort = candidate:match("^([^-]+)") or candidate
    local unitShort = short:match("^([^-]+)") or short
    return candidateShort ~= "" and candidateShort == unitShort
end
