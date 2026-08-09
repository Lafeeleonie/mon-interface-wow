---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Modules/Conditions/Compiler.lua
-- 把用户规则编译为 eventID -> rule[]，避免 Scheduler OnUpdate 全量扫描。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.Conditions = ExBoss.Conditions or {}

local Compiler = ExBoss.Conditions.Compiler or {}
ExBoss.Conditions.Compiler = Compiler

Compiler._revision = nil
Compiler._byEventID = nil

local function GetStore()
    return ExBoss.Conditions and ExBoss.Conditions.Store or nil
end

function Compiler:Invalidate()
    self._revision = nil
    self._byEventID = nil
end

function Compiler:Compile()
    local store = GetStore()
    if not store then
        self._byEventID = {}
        self._revision = 0
        return self._byEventID
    end

    local db = store:GetDB()
    local byEventID = {}
    if db.fixedRulesEnabled ~= false then
        local rules = store:GetNormalizedRules()
        for i = 1, #rules do
            local rule = rules[i]
            if rule.enabled == true and rule.eventID and rule.eventID > 0 then
                byEventID[rule.eventID] = byEventID[rule.eventID] or {}
                byEventID[rule.eventID][#byEventID[rule.eventID] + 1] = rule
            end
        end
        for _, list in pairs(byEventID) do
            table.sort(list, function(a, b)
                local ar = tonumber(a.remaining) or 0
                local br = tonumber(b.remaining) or 0
                if ar == br then
                    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
                end
                return ar > br
            end)
        end
    end
    self._byEventID = byEventID
    self._revision = store:GetRevision()
    return byEventID
end

function Compiler:GetByEventID()
    local store = GetStore()
    local rev = store and store:GetRevision() or 0
    if self._byEventID == nil or self._revision ~= rev then
        return self:Compile()
    end
    return self._byEventID
end

function Compiler:GetRulesForEventID(eventID)
    eventID = tonumber(eventID)
    if not eventID then
        return nil
    end
    local byEventID = self:GetByEventID()
    return byEventID[math.floor(eventID)]
end
