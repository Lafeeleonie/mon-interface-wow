---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Modules/Conditions/Actions.lua
-- 条件系统动作分发。当前 GUI 暴露倒数文字、播放音效。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.Conditions = ExBoss.Conditions or {}

local Actions = ExBoss.Conditions.Actions or {}
ExBoss.Conditions.Actions = Actions

local function TimerName(timer)
    if type(timer) ~= "table" then
        return "未知技能"
    end
    return tostring(timer.timerBarName or timer.displayName or timer.baseDisplayName or "未知技能")
end

local function FormatText(template, timer)
    local text = tostring(template or "")
    if text == "" then
        text = TimerName(timer)
    end
    text = text:gsub("{name}", TimerName(timer))
    text = text:gsub("{eventID}", tostring(timer and timer.eventID or ""))
    text = text:gsub("{spellID}", tostring(timer and timer.spellID or ""))
    return text
end

local function ResolveColor(timer)
    if type(timer) == "table" and type(timer.flashTextColor) == "table" then
        return timer.flashTextColor
    end
    if type(timer) == "table" and type(timer.eventColor) == "table" then
        return timer.eventColor
    end
    return nil
end

local function PlayVoice(trigger, timer)
    local source = tostring(trigger.voiceSource or "pack")
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if engine and engine.TryPlayStandaloneSound then
        local triggerCfg = {
            enabled = true,
            sourceType = source,
        }
        if source == "file" then
            triggerCfg.customPath = tostring(trigger.voicePath or "")
        elseif source == "lsm" then
            triggerCfg.customLSM = tostring(trigger.voiceLSM or "")
        else
            triggerCfg.sourceType = "pack"
            triggerCfg.label = tostring(trigger.voiceLabel or "")
        end
        local ok = engine:TryPlayStandaloneSound(
            triggerCfg,
            "condition:" .. tostring(timer and timer.id or timer and timer.timelineEventID or timer and timer.eventID or "unknown") .. ":" .. tostring(trigger.ruleID or ""),
            { triggerIndex = 1, throttle = false }
        )
        if ok then
            return true
        end
    end

    if source == "file" then
        local path = tostring(trigger.voicePath or "")
        if path ~= "" and PlaySoundFile then
            return PlaySoundFile(path, "Master")
        end
        return false
    end

    if source == "lsm" then
        local key = tostring(trigger.voiceLSM or "")
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        local file = lsm and key ~= "" and lsm:Fetch("sound", key, true) or nil
        if file and file ~= "" and PlaySoundFile then
            return PlaySoundFile(file, "Master")
        end
        return false
    end

    local label = tostring(trigger.voiceLabel or "")
    if label == "" then
        return false
    end
    if engine and engine.TryPlayLabel then
        return engine:TryPlayLabel(label, timer, { throttle = false })
    end
    return false
end

function Actions:Run(timer, trigger, now, remaining)
    if type(timer) ~= "table" or type(trigger) ~= "table" then
        return false
    end
    local actionType = tostring(trigger.actionType or "countdown")
    local text = FormatText(trigger.text, timer)
    local remain = math.max(0.1, tonumber(remaining) or tonumber(trigger.remaining) or 1)

    if actionType == "countdown" then
        local countdown = ExBoss and ExBoss.UI and ExBoss.UI.Countdown
        if countdown and countdown.Show then
            return pcall(function()
                countdown:Show({
                    displayName = text,
                    iconFileID = timer.iconFileID or 136197,
                    duration = remain,
                    color = ResolveColor(timer),
                })
            end)
        end
        return false
    end

    if actionType == "voice" then
        return pcall(PlayVoice, trigger, timer)
    end

    return false
end
