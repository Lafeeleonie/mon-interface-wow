---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Modules/Conditions/Store.lua
-- 固定轴条件系统 DB。只服务 fixed / fixed_ai 计时器。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.Conditions = ExBoss.Conditions or {}

local Store = ExBoss.Conditions.Store or {}
ExBoss.Conditions.Store = Store

local ACTION_DEFAULT = "countdown"
local ACTIONS = {
    countdown = true,
    voice = true,
}

local SOURCES = {
    pack = true,
    lsm = true,
    file = true,
}

local DEFAULTS = {
    fixedRulesEnabled = true,
    revision = 0,
    rules = {},
}

local RULE_DEFAULTS = {
    enabled = false,
    name = "",
    eventID = "",
    remaining = 5,
    actionType = ACTION_DEFAULT,
    text = "",
    voiceSource = "pack",
    voiceLabel = "",
    voiceLSM = "",
    voicePath = "",
}

local function EnsureDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.conditions = ExBossDB.conditions or {}
    local db = ExBossDB.conditions
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
            else
                db[k] = v
            end
        end
    end
    if type(db.rules) ~= "table" then
        db.rules = {}
    end
    return db
end

local function NormalizeAction(actionType)
    actionType = tostring(actionType or ACTION_DEFAULT)
    if not ACTIONS[actionType] then
        return ACTION_DEFAULT
    end
    return actionType
end

local function NormalizeSource(source)
    source = tostring(source or "pack")
    if not SOURCES[source] then
        return "pack"
    end
    return source
end

local function NormalizeRule(rule, index)
    if type(rule) ~= "table" then
        rule = {}
    end
    for k, v in pairs(RULE_DEFAULTS) do
        if rule[k] == nil then
            rule[k] = v
        end
    end

    local eventID = tonumber(rule.eventID)
    local remaining = tonumber(rule.remaining)
    if remaining == nil then
        remaining = tonumber(RULE_DEFAULTS.remaining) or 5
    end

    rule.enabled = rule.enabled == true
    rule.name = tostring(rule.name or "")
    rule.eventID = eventID and tostring(math.floor(eventID)) or tostring(rule.eventID or "")
    rule.remaining = math.max(0, remaining)
    rule.actionType = NormalizeAction(rule.actionType)
    rule.text = tostring(rule.text or "")
    rule.voiceSource = NormalizeSource(rule.voiceSource)
    rule.voiceLabel = tostring(rule.voiceLabel or "")
    rule.voiceLSM = tostring(rule.voiceLSM or "")
    rule.voicePath = tostring(rule.voicePath or "")

    return {
        id = index,
        enabled = rule.enabled,
        name = rule.name,
        eventID = eventID and math.floor(eventID) or nil,
        remaining = rule.remaining,
        actionType = rule.actionType,
        text = rule.text,
        voiceSource = rule.voiceSource,
        voiceLabel = rule.voiceLabel,
        voiceLSM = rule.voiceLSM,
        voicePath = rule.voicePath,
    }
end

function Store:GetDB()
    return EnsureDB()
end

function Store:GetRules()
    return EnsureDB().rules
end

function Store:GetNormalizedRules()
    local rules = self:GetRules()
    local out = {}
    for i = 1, #rules do
        out[#out + 1] = NormalizeRule(rules[i], i)
    end
    return out
end

function Store:GetRevision()
    return tonumber(EnsureDB().revision) or 0
end

function Store:BumpRevision()
    local db = EnsureDB()
    db.revision = (tonumber(db.revision) or 0) + 1
    local compiler = ExBoss.Conditions and ExBoss.Conditions.Compiler
    if compiler and compiler.Invalidate then
        compiler:Invalidate()
    end
    local engine = ExBoss.Conditions and ExBoss.Conditions.Engine
    if engine and engine.OnRulesChanged then
        engine:OnRulesChanged()
    end
end

function Store:AddRule()
    local rules = self:GetRules()
    local rule = {}
    for k, v in pairs(RULE_DEFAULTS) do
        rule[k] = v
    end
    rules[#rules + 1] = rule
    self:BumpRevision()
    return #rules, rule
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = CopyValue(v)
    end
    return out
end

local function BuildCopiedName(baseName, rules)
    local base = tostring(baseName or "")
    if base == "" then
        base = "NEW"
    end
    local used = {}
    for i = 1, #rules do
        local name = tostring(rules[i] and rules[i].name or "")
        if name ~= "" then
            used[name] = true
        end
    end
    for i = 1, 99 do
        local candidate = string.format("%s%02d", base, i)
        if not used[candidate] then
            return candidate
        end
    end
    return base .. tostring(#rules + 1)
end

function Store:CopyRule(index)
    local rules = self:GetRules()
    index = tonumber(index)
    if not index or index < 1 or index > #rules then
        return nil
    end
    local source = rules[index]
    if type(source) ~= "table" then
        return nil
    end
    self:ApplyRuleDefaults(source)
    local copied = CopyValue(source)
    copied.name = BuildCopiedName(source.name, rules)
    rules[#rules + 1] = copied
    self:BumpRevision()
    return #rules, copied
end

function Store:DeleteRule(index)
    local rules = self:GetRules()
    index = tonumber(index)
    if not index or index < 1 or index > #rules then
        return false
    end
    table.remove(rules, index)
    self:BumpRevision()
    return true
end

function Store:NormalizeRule(rule, index)
    return NormalizeRule(rule, index)
end

function Store:ApplyRuleDefaults(rule)
    if type(rule) ~= "table" then
        return
    end
    NormalizeRule(rule)
end
