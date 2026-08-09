---@diagnostic disable: undefined-global

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local Presentation = {}
ExBoss.Modules.Boss.TimelinePresentation = Presentation

local ModeRules = ExBoss.Modules.Boss.TimelineModeRules
local SPECIAL_CAST_OBSERVE_ORDINALS = {
    [106] = 3,
}
local SPECIAL_CAST_OBSERVE_WINDOW_AFTER = {
    [106] = 10,
    [296] = 3,
    [308] = 3,
}

local function NormalizeText(v)
    if type(v) ~= "string" then
        return ""
    end
    local s = v:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local _encounterEventIndexCache = nil
local _encounterEventIndexSource = nil

local function BuildEncounterEventIndex()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if _encounterEventIndexCache and _encounterEventIndexSource == data then
        return _encounterEventIndexCache
    end
    local out = {}
    if type(data) == "table" and type(data.maps) == "table" then
        for _, mapRow in pairs(data.maps) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for rawEventID, eventRow in pairs(bossRow.events) do
                            local eid = tonumber(rawEventID) or
                            (type(eventRow) == "table" and tonumber(eventRow.eventID))
                            if eid and type(eventRow) == "table" then
                                out[eid] = eventRow
                            end
                        end
                    end
                end
            end
        end
    end
    _encounterEventIndexCache = out
    _encounterEventIndexSource = data
    return out
end

local function GetEncounterEventRow(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    return BuildEncounterEventIndex()[eid]
end

local function GetResolvedEventConfig(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.GetResolvedEventConfig) == "function" then
        local ok, row = pcall(cfg.GetResolvedEventConfig, cfg, eid)
        if ok and type(row) == "table" then
            return row
        end
    end
    if _G.EXBossData and type(_G.EXBossData.GetResolvedEventConfig) == "function" then
        local ok, row = pcall(_G.EXBossData.GetResolvedEventConfig, eid)
        if ok and type(row) == "table" then
            return row
        end
    end
    return nil
end

local function ResolveLinkedTextFields(row)
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.ResolveLinkedTextFields) == "function" then
        local ok, resolved = pcall(cfg.ResolveLinkedTextFields, cfg, row)
        if ok and type(resolved) == "table" then
            return resolved
        end
    end
    return {
        preAlertText = "",
        timerBarRenameText = "",
    }
end

local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then
        return nil
    end
    return tonumber(timer.eventID) or tonumber(timer.timelineEventID)
end

local function ResolveDefaultCentralText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    local text = NormalizeText(timer.screenText)
    if text ~= "" then
        return LocalizeDynamicText(text)
    end
    text = NormalizeText(timer.displayName)
    if text ~= "" then
        return LocalizeDynamicText(text)
    end
    return ""
end

local function ResolveDefaultPreAlertLead(timer)
    if type(timer) ~= "table" then
        return 0
    end
    local castTime = tonumber(timer.castTime)
    local preAlertTime = tonumber(timer.preAlertTime)
    if castTime and preAlertTime then
        return math.max(0, castTime - preAlertTime)
    end
    return tonumber(timer.timelinePreAlertLead) or 0
end

local function IsBlizzardHintCountdownEnabledByGlobal()
    local db = _G.ExBossDB
    local general = db and db.ui and db.ui.general
    if type(general) ~= "table" then
        return true
    end
    if general.enableBlizzardHintCountdown == nil then
        return true
    end
    return general.enableBlizzardHintCountdown == true
end

function Presentation:Resolve(timer, explicitMode)
    local mode = (ModeRules and ModeRules:ResolveMode(timer, explicitMode)) or "fixed"
    local rules = (ModeRules and ModeRules:Get(mode)) or {}
    local capabilities = type(rules.capabilities) == "table" and rules.capabilities or {}
    local sources = type(rules.sources) == "table" and rules.sources or {}
    local resolvedEventID = ResolveTimerEventID(timer)
    local row = GetResolvedEventConfig(resolvedEventID)
    local encounterRow = GetEncounterEventRow(resolvedEventID)

    local perEventCentralEnabled = false
    if type(row) == "table" then
        perEventCentralEnabled = (row.centralEnabled == true)
    elseif type(timer) == "table" then
        perEventCentralEnabled = (timer.centralEnabled == true)
    end

    local out = {
        mode = mode,
        usePerEventEnabled = capabilities.perEventEnabled ~= false,
        eventEnabled = true,
        useEventColor = capabilities.eventColor ~= false,
        useCentralText = capabilities.centralText == true,
        usePreAlertText = capabilities.preAlertText == true,
        useTimerBarRename = capabilities.timerBarRename == true,
        useRingProgress = capabilities.ringProgress == true,
        useOccurrenceCount = capabilities.occurrenceCount ~= false,
        useBlizzardHintCountdown = false,
        useBlizzardHintCentral = false,
        eventColorSource = tostring(sources.eventColor or "own"),
        countdownSource = tostring(sources.countdown or "own"),
        centralSource = tostring(sources.central or "own"),
        castVoiceSource = tostring(sources.castVoice or "own"),
        preAlertVoiceSource = tostring(sources.preAlertVoice or "own"),
        occurrenceDisplayMode = tostring(rules.occurrenceDisplayMode or "inline"),
        blizzardHintCountdownLead = tonumber(rules.blizzardHintCountdownLead) or 5,
        blizzardHintCentralLead = tonumber(rules.blizzardHintCentralLead) or 2,
        blizzardHintCentralDuration = tonumber(rules.blizzardHintCentralDuration) or 2,
        countdownMode = "none",
        centralMode = "none",
        showBunBar = type(timer) == "table" and timer.showBunBar ~= false or true,
        showTimerBar = type(timer) == "table" and timer.showTimerBar ~= false or true,
        screenAlert = type(timer) == "table" and timer.screenAlert == true or false,
        ringEnabled = false,
        castProgressBarEnabled = false,
        ringCastCheckEnabled = false,
        ringWindowBefore = 1,
        ringWindowAfter = 2,
        ringCastDuration = nil,
        ringChannelDuration = nil,
        ringPlan = nil,
        iconFlags = 0,
        colorConfig = nil,
        timerTextColor = nil,
        voiceTriggers = nil,
        voiceLabel = nil,
        voicePlan = nil,
        countdownVoiceEnabled = false,
        countdownPlayName = false,
        preAlertEnabled = false,
        preAlertLead = 0,
        preAlertText = nil,
        centralEnabled = false,
        centralLead = 0,
        centralText = nil,
        timerBarRenameEnabled = false,
        timerBarRenameText = nil,
    }

    if out.usePerEventEnabled and type(row) == "table" and row.enabled == false then
        out.eventEnabled = false
    end

    if out.usePerEventEnabled and type(row) == "table" then
        if row.showBunBar ~= nil then
            out.showBunBar = (row.showBunBar == true)
        end
        if row.showTimerBar ~= nil then
            out.showTimerBar = (row.showTimerBar == true)
        end
        if row.screenAlert ~= nil then
            out.screenAlert = (row.screenAlert == true)
        end
    end

    local blizzardHintSessionEnabled = (type(timer) == "table" and timer.blizzardHintSessionEnabled == true)
    out.useBlizzardHintCountdown = (capabilities.blizzardHintCountdown == true and
        IsBlizzardHintCountdownEnabledByGlobal() and blizzardHintSessionEnabled)
    out.useBlizzardHintCentral = (capabilities.blizzardHintCentral == true and
        perEventCentralEnabled == true and blizzardHintSessionEnabled)

    if out.useRingProgress and type(row) == "table" and type(row.rules) == "table" and type(row.rules.castWindow) == "table" then
        local cw = row.rules.castWindow
        out.ringEnabled = (cw.enabled == true and cw.ringEnabled ~= false)
        out.castProgressBarEnabled = (cw.enabled == true and cw.castBarEnabled == true)
        out.castObserveLead = tonumber(cw.observeLead)
        out.castObserveOrdinal = tonumber(cw.observeOrdinal)
        if SPECIAL_CAST_OBSERVE_ORDINALS[tonumber(resolvedEventID)] then
            out.castObserveOrdinal = SPECIAL_CAST_OBSERVE_ORDINALS[tonumber(resolvedEventID)]
        end
        out.castObserveExpectedKind = NormalizeText(cw.observeExpectedKind)
        if type(cw.observeUnit) == "table" then
            out.castObserveUnitFilter = DeepCopy(cw.observeUnit)
        elseif type(cw.observeUnits) == "table" then
            out.castObserveUnitFilter = DeepCopy(cw.observeUnits)
        elseif type(cw.observeUnit) == "string" or type(cw.observeUnits) == "string" then
            out.castObserveUnitFilter = tostring(cw.observeUnit or cw.observeUnits or "")
        end
        out.castProgressBarRenameEnabled = (cw.castBarRenameEnabled == true)
        if out.castProgressBarRenameEnabled then
            local rename = NormalizeText(cw.castBarRenameText)
            if rename ~= "" then
                out.castProgressBarRenameText = rename
            end
        end
        out.ringCastCheckEnabled = (cw.castCheckEnabled == true or cw.ringCastCheckEnabled == true)
        out.ringWindowBefore = tonumber(cw.windowBefore) or 1
        out.ringWindowAfter = tonumber(cw.windowAfter) or 2
        if SPECIAL_CAST_OBSERVE_WINDOW_AFTER[tonumber(resolvedEventID)] then
            out.ringWindowAfter = SPECIAL_CAST_OBSERVE_WINDOW_AFTER[tonumber(resolvedEventID)]
        end
    end

    if type(encounterRow) == "table" then
        out.ringCastDuration = tonumber(encounterRow.castDuration)
        out.ringChannelDuration = tonumber(encounterRow.channelDuration)
        out.iconFlags = tonumber(encounterRow.iconFlags) or 0
        local rawVoiceLabel = NormalizeText(encounterRow.voiceLabel)
        if rawVoiceLabel ~= "" then
            out.voiceLabel = rawVoiceLabel
        end
    end

    do
        local castDuration = tonumber(out.ringCastDuration)
        local channelDuration = tonumber(out.ringChannelDuration)
        if castDuration and castDuration > 0 and channelDuration and channelDuration > 0 then
            out.ringPlan = {
                { duration = castDuration,    castKind = "cast" },
                { duration = channelDuration, castKind = "channel" },
            }
        elseif castDuration and castDuration > 0 then
            out.ringPlan = {
                { duration = castDuration, castKind = "cast" },
            }
        elseif channelDuration and channelDuration > 0 then
            out.ringPlan = {
                { duration = channelDuration, castKind = "channel" },
            }
        end
    end

    if out.useEventColor and type(row) == "table" and type(row.color) == "table" and row.color.enabled ~= false then
        out.colorConfig = DeepCopy(row.color)
    end

    if out.usePerEventEnabled and type(row) == "table" and row.timerTextColorEnabled == true then
        local r = tonumber(row.timerTextColorR)
        local g = tonumber(row.timerTextColorG)
        local b = tonumber(row.timerTextColorB)
        local a = tonumber(row.timerTextColorA) or 1
        if r and g and b then
            out.timerTextColor = { r = r, g = g, b = b, a = a }
        end
    end

    if out.castVoiceSource == "own" and type(row) == "table" and row.enabled ~= false and type(row.triggers) == "table" then
        out.voiceTriggers = DeepCopy(row.triggers)
    end

    if out.usePreAlertText then
        local enabled = true
        if type(row) == "table" and row.countdownEnabled ~= nil then
            enabled = (row.countdownEnabled == true)
        elseif type(row) == "table" and row.preAlertEnabled == false then
            enabled = false
        elseif type(timer) == "table" and timer.preAlertEnabled == false then
            enabled = false
        end
        out.preAlertEnabled = enabled
        if enabled then
            local lead = type(row) == "table" and tonumber(row.countdownLead) or nil
            if lead == nil then
                lead = type(row) == "table" and tonumber(row.preAlert) or nil
            end
            if lead == nil then
                lead = ResolveDefaultPreAlertLead(timer)
            end
            out.preAlertLead = math.min(30, math.max(0, tonumber(lead) or 0))
            local linked = ResolveLinkedTextFields(row)
            local txt = type(linked) == "table" and NormalizeText(linked.preAlertText) or ""
            if txt == "" and type(timer) == "table" then
                txt = NormalizeText(timer.preAlertText)
            end
            if txt ~= "" then
                out.preAlertText = LocalizeDynamicText(txt)
            end
        end
        if type(row) == "table" and row.countdownVoiceEnabled ~= nil then
            out.countdownVoiceEnabled = (row.countdownVoiceEnabled == true)
        elseif type(row) == "table" and row.countdownPlayName == true then
            out.countdownVoiceEnabled = true
        end
        if type(row) == "table" and row.countdownPlayName == true then
            out.countdownPlayName = true
        end
    end

    if out.useCentralText then
        local enabled = perEventCentralEnabled
        out.centralEnabled = enabled
        if enabled then
            out.centralLead = math.max(0,
                tonumber(type(row) == "table" and row.centralLead or (type(timer) == "table" and timer.centralLead)) or 0)
            local txt = type(row) == "table" and NormalizeText(row.centralText) or ""
            if txt == "" then
                txt = ResolveDefaultCentralText(timer)
            end
            if txt ~= "" then
                out.centralText = LocalizeDynamicText(txt)
            end
        end
    end

    if out.useTimerBarRename then
        local enabled = type(row) == "table" and row.timerBarRenameEnabled == true
        out.timerBarRenameEnabled = enabled
        if enabled then
            local linked = ResolveLinkedTextFields(row)
            local txt = type(linked) == "table" and NormalizeText(linked.timerBarRenameText) or ""
            if txt ~= "" then
                out.timerBarRenameText = LocalizeDynamicText(txt)
            end
        end
    end

    if out.useBlizzardHintCountdown == true then
        out.countdownMode = "blizzard_hint"
    elseif out.preAlertEnabled == true and out.preAlertLead > 0 and NormalizeText(out.preAlertText) ~= "" then
        out.countdownMode = "own"
    end

    if out.useBlizzardHintCentral == true then
        out.centralMode = "blizzard_hint"
    elseif out.centralEnabled == true and NormalizeText(out.centralText) ~= "" then
        out.centralMode = "own"
    end

    do
        local label = NormalizeText(out.voiceLabel)
        if label == "" then
            label = nil
        end
        local triggers = type(out.voiceTriggers) == "table" and DeepCopy(out.voiceTriggers) or nil
        if triggers or label then
            out.voicePlan = {
                enabled = (out.eventEnabled ~= false),
                source = tostring(out.castVoiceSource or "own"),
                triggers = triggers,
                label = label,
            }
        end
    end

    return out
end
