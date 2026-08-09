---@diagnostic disable: undefined-global

do
    local ENCOUNTER_ID = 3213
    local EVENT_NECROTIC_MERGE = 20
    local EVENT_SPELL_ID = 1250708
    local SHIELD_BASE_AMOUNT = 1160814
    local WATCH_THROTTLE = 0.1
    local INTERRUPTIBLE_CLOSE_WINDOW = 30.0
    local FORCE_TARGET_TEST = false
    local FORCE_TARGET_UNIT = "target"

    ExBoss = ExBoss or {}
    ExBoss.Modules = ExBoss.Modules or {}
    ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

    local Mod = ExBoss.Modules.Boss.VordazaShieldBar or {}
    ExBoss.Modules.Boss.VordazaShieldBar = Mod

    local shieldWatchFrame = nil
    local watchedBossUnit = nil
    local watchActive = false
    local refreshTimer = nil
    local startWatchTimer = nil
    local armChannelTimer = nil
    local shieldMaxValue = nil
    local waitingForShieldChannelStart = false
    local interruptibleCloseExpireAt = nil
    local shieldName = nil
    local shieldIconTexture = nil
    local StartShieldWatch = nil
    local RefreshShieldBar = nil

    local function GetExtraShieldBar()
        return ExBoss and ExBoss.UI and ExBoss.UI.ExtraShieldBar or nil
    end

    local function IsVordazaActive()
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.IsBossEncounter == true and tonumber(state.EncounterID) == ENCOUNTER_ID then
            return true
        end
        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
        return type(scheduler) == "table"
            and scheduler._running == true
            and tonumber(scheduler._encounterID) == ENCOUNTER_ID
    end

    local function CancelTimer(timer)
        if timer and type(timer.Cancel) == "function" then
            pcall(timer.Cancel, timer)
        end
    end

    local function GetShieldLevelMultiplier()
        local state = ExwindTools and ExwindTools.State or nil
        if not state or state.InMythicPlus ~= true then
            return 1
        end
        local level = tonumber(state and state.MythicPlusLevel) or 0
        local db = _G.EXDB
        local multipliers = db and db.MythicDamageData and db.MythicDamageData.LevelMultipliers or nil
        local multiplier = multipliers and multipliers[level] or nil
        return tonumber(multiplier) or 1
    end

    local function GetConfiguredShieldMaxValue()
        return SHIELD_BASE_AMOUNT * GetShieldLevelMultiplier()
    end

    local function GetSpellName()
        if type(shieldName) == "string" and shieldName ~= "" then
            return shieldName
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(EVENT_SPELL_ID)
            if info and info.name then
                shieldName = info.name
                return shieldName
            end
        end
        shieldName = "死疽融合"
        return shieldName
    end

    local function GetSpellIcon()
        if shieldIconTexture then
            return shieldIconTexture
        end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, EVENT_SPELL_ID)
            if ok and tex then
                shieldIconTexture = tex
                return tex
            end
        end
        shieldIconTexture = 136197
        return shieldIconTexture
    end

    local function HideShieldBar()
        watchActive = false
        watchedBossUnit = nil
        shieldMaxValue = nil
        CancelTimer(refreshTimer)
        CancelTimer(startWatchTimer)
        CancelTimer(armChannelTimer)
        refreshTimer = nil
        startWatchTimer = nil
        armChannelTimer = nil
        waitingForShieldChannelStart = false
        interruptibleCloseExpireAt = nil
        if shieldWatchFrame then
            shieldWatchFrame:UnregisterAllEvents()
        end
        local bar = GetExtraShieldBar()
        if bar and bar.Hide then
            bar:Hide("Vordaza")
        end
    end

    local function ResolveBossUnit()
        if FORCE_TARGET_TEST == true then
            if UnitExists and UnitExists(FORCE_TARGET_UNIT) then
                watchedBossUnit = FORCE_TARGET_UNIT
                return FORCE_TARGET_UNIT
            end
            return nil
        end
        if type(watchedBossUnit) == "string" and UnitExists and UnitExists(watchedBossUnit) then
            return watchedBossUnit
        end
        for i = 1, 5 do
            local unit = "boss" .. tostring(i)
            if UnitExists and UnitExists(unit) then
                watchedBossUnit = unit
                return unit
            end
        end
        return nil
    end

    RefreshShieldBar = function()
        refreshTimer = nil
        local bar = GetExtraShieldBar()
        if not watchActive or (FORCE_TARGET_TEST ~= true and not IsVordazaActive()) then
            HideShieldBar()
            return
        end

        local unit = ResolveBossUnit()
        if not unit or not UnitExists or not UnitExists(unit) then
            return
        end

        local absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
        if absorbAmount == nil then
            return
        end

        if not shieldMaxValue then
            shieldMaxValue = GetConfiguredShieldMaxValue()
        end

        if bar and bar.Update then
            bar:Update("Vordaza", {
                name = GetSpellName(),
                icon = GetSpellIcon(),
                value = absorbAmount,
                maxValue = shieldMaxValue,
            })
        end
    end

    local function ScheduleRefresh()
        if refreshTimer then
            return
        end
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            refreshTimer = C_Timer.NewTimer(WATCH_THROTTLE, RefreshShieldBar)
        elseif C_Timer and type(C_Timer.After) == "function" then
            refreshTimer = true
            C_Timer.After(WATCH_THROTTLE, function()
                refreshTimer = nil
                RefreshShieldBar()
            end)
        else
            RefreshShieldBar()
        end
    end

    local function EnsureWatchFrame()
        if shieldWatchFrame then
            return shieldWatchFrame
        end
        shieldWatchFrame = CreateFrame("Frame")
        shieldWatchFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "PLAYER_TARGET_CHANGED" then
                if event == "PLAYER_TARGET_CHANGED" then
                    watchedBossUnit = nil
                    shieldMaxValue = nil
                end
                if watchActive then
                    ScheduleRefresh()
                end
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                if waitingForShieldChannelStart == true and type(unit) == "string" and unit:match("^boss%d$") then
                    waitingForShieldChannelStart = false
                    watchedBossUnit = unit
                    CancelTimer(startWatchTimer)
                    startWatchTimer = nil
                    if C_Timer and type(C_Timer.NewTimer) == "function" then
                        startWatchTimer = C_Timer.NewTimer(0.1, function()
                            startWatchTimer = nil
                            if IsVordazaActive() then
                                StartShieldWatch(unit)
                            end
                        end)
                    elseif C_Timer and type(C_Timer.After) == "function" then
                        startWatchTimer = true
                        C_Timer.After(0.1, function()
                            startWatchTimer = nil
                            if IsVordazaActive() then
                                StartShieldWatch(unit)
                            end
                        end)
                    else
                        StartShieldWatch(unit)
                    end
                end
            elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
                local now = GetTime()
                if watchActive
                    and type(unit) == "string"
                    and unit == watchedBossUnit
                    and tonumber(interruptibleCloseExpireAt)
                    and now <= tonumber(interruptibleCloseExpireAt) then
                    HideShieldBar()
                end
            elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
                if FORCE_TARGET_TEST == true and event == "PLAYER_ENTERING_WORLD" then
                    watchActive = true
                    ScheduleRefresh()
                else
                    HideShieldBar()
                end
            end
        end)
        return shieldWatchFrame
    end

    StartShieldWatch = function(unit)
        HideShieldBar()
        watchActive = true
        watchedBossUnit = unit or watchedBossUnit
        shieldMaxValue = nil
        interruptibleCloseExpireAt = GetTime() + INTERRUPTIBLE_CLOSE_WINDOW
        EnsureWatchFrame():RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
        EnsureWatchFrame():RegisterEvent("PLAYER_TARGET_CHANGED")
        EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
        EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "boss1", "boss2", "boss3", "boss4", "boss5")
        EnsureWatchFrame():RegisterEvent("ENCOUNTER_END")
        EnsureWatchFrame():RegisterEvent("PLAYER_ENTERING_WORLD")
        if FORCE_TARGET_TEST == true or watchedBossUnit then
            ScheduleRefresh()
        end
    end

    local function ArmShieldChannelWatch(delay)
        CancelTimer(armChannelTimer)
        armChannelTimer = nil

        local wait = math.max(0, tonumber(delay) or 0)
        if wait <= 0.05 then
            waitingForShieldChannelStart = true
            EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
            return
        end

        if C_Timer and type(C_Timer.NewTimer) == "function" then
            armChannelTimer = C_Timer.NewTimer(wait, function()
                armChannelTimer = nil
                if IsVordazaActive() then
                    waitingForShieldChannelStart = true
                    EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
                end
            end)
        elseif C_Timer and type(C_Timer.After) == "function" then
            armChannelTimer = true
            C_Timer.After(wait, function()
                armChannelTimer = nil
                if IsVordazaActive() then
                    waitingForShieldChannelStart = true
                    EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
                end
            end)
        else
            waitingForShieldChannelStart = true
            EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
        end
    end

    local function OnFixedAIEventScheduled(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_NECROTIC_MERGE then
            return
        end
        if not IsVordazaActive() then
            return
        end
        ArmShieldChannelWatch(math.max(0, (tonumber(payload and payload.remaining) or 0) - 1))
    end

    function Mod:IsEditMode()
        local bar = GetExtraShieldBar()
        return bar and bar.IsEditMode and bar:IsEditMode() == true or false
    end

    function Mod:RefreshVisuals()
        local bar = GetExtraShieldBar()
        if bar and bar.RefreshVisuals then
            bar:RefreshVisuals()
        end
        if watchActive then
            RefreshShieldBar()
        end
    end

    function Mod:EnterEditMode()
        local bar = GetExtraShieldBar()
        return bar and bar.EnterEditMode and bar:EnterEditMode() or false
    end

    function Mod:ExitEditMode()
        local bar = GetExtraShieldBar()
        return bar and bar.ExitEditMode and bar:ExitEditMode() or false
    end

    function Mod:ToggleEditMode()
        local bar = GetExtraShieldBar()
        return bar and bar.ToggleEditMode and bar:ToggleEditMode() or false
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_SCHEDULED", "ExBoss_Vordaza_ShieldWatch_Scheduled", OnFixedAIEventScheduled)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Vordaza_ShieldWatch_Reset", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                HideShieldBar()
                if FORCE_TARGET_TEST == true then
                    StartShieldWatch()
                end
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Vordaza_ShieldWatch_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID or IsVordazaActive() then
                HideShieldBar()
            end
        end)
        ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_Vordaza_ShieldWatch_PEW", function()
            if FORCE_TARGET_TEST == true then
                StartShieldWatch()
            else
                HideShieldBar()
            end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3213,
    dungeon = { key = "maisara_caverns", name = "Maisara Caverns", zhCN = "迈萨拉洞窟" },
    boss = { key = "vordaza", name = "Vordaza", zhCN = "沃达扎" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
