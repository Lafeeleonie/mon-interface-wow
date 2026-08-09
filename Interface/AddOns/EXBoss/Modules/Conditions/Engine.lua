---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Modules/Conditions/Engine.lua
-- 固定轴条件系统运行时。规则在计时器创建时绑定，OnUpdate 只检查绑定结果。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.Conditions = ExBoss.Conditions or {}

local Engine = ExBoss.Conditions.Engine or {}
ExBoss.Conditions.Engine = Engine

local function IsAllowedTimer(timer)
    if type(timer) ~= "table" then
        return false
    end
    if timer.timelineManaged == true then
        return false
    end
    if timer.source ~= "fixed" and timer.source ~= "fixed_ai" then
        return false
    end
    return tonumber(timer.eventID) ~= nil and tonumber(timer.castTime) ~= nil
end

function Engine:AttachToTimer(timer)
    if not IsAllowedTimer(timer) then
        timer.conditionTriggers = nil
        return nil
    end
    local compiler = ExBoss.Conditions and ExBoss.Conditions.Compiler
    local rules = compiler and compiler.GetRulesForEventID and compiler:GetRulesForEventID(timer.eventID) or nil
    if type(rules) ~= "table" or #rules == 0 then
        timer.conditionTriggers = nil
        return nil
    end

    local castTime = tonumber(timer.castTime)
    local triggers = {}
    for i = 1, #rules do
        local rule = rules[i]
        local remaining = math.max(0, tonumber(rule.remaining) or 0)
        triggers[#triggers + 1] = {
            ruleID = rule.id,
            ruleName = rule.name,
            fireAt = castTime - remaining,
            remaining = remaining,
            actionType = rule.actionType,
            text = rule.text,
            voiceSource = rule.voiceSource,
            voiceLabel = rule.voiceLabel,
            voiceLSM = rule.voiceLSM,
            voicePath = rule.voicePath,
            fired = false,
        }
    end
    timer.conditionTriggers = triggers
    return triggers
end

function Engine:UpdateTimer(timer, now)
    if not IsAllowedTimer(timer) or type(timer.conditionTriggers) ~= "table" then
        return
    end
    now = tonumber(now) or (GetTime and GetTime()) or 0
    local castTime = tonumber(timer.castTime)
    if not castTime then
        return
    end

    local actions = ExBoss.Conditions and ExBoss.Conditions.Actions
    if not (actions and actions.Run) then
        return
    end

    for i = 1, #timer.conditionTriggers do
        local trigger = timer.conditionTriggers[i]
        if trigger and trigger.fired ~= true then
            local fireAt = tonumber(trigger.fireAt) or castTime
            if now >= fireAt and now <= castTime + 0.15 then
                trigger.fired = true
                local remaining = math.max(0.1, castTime - now)
                actions:Run(timer, trigger, now, remaining)
            elseif now > castTime + 0.15 then
                trigger.fired = true
            end
        end
    end
end

function Engine:OnRulesChanged()
    local compiler = ExBoss.Conditions and ExBoss.Conditions.Compiler
    if compiler and compiler.Invalidate then
        compiler:Invalidate()
    end
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    local active = scheduler and scheduler._active or nil
    if type(active) == "table" then
        for _, timer in pairs(active) do
            self:AttachToTimer(timer)
        end
    end
end
