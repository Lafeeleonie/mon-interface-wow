---@diagnostic disable: undefined-global, unused-local, unused-function

local ondev = true
if ondev then
    return
end


local R = ExBoss and ExBoss.BossEncounters
if not R then return end

local ENCOUNTER_ID           = 3214
local EVENT_ID               = 157
local LOOP_SECONDS           = 6
local repeatLoopTicker       = nil
local encounterActive        = false
local waitingForFirstTrigger = false
local watchFrame             = nil

local function HasShadowSchool(schoolMask)
    local mask = tonumber(schoolMask)
    if not mask then
        return false
    end
    if mask == 32 then
        return true
    end
    if bit and type(bit.band) == "function" then
        return bit.band(mask, 32) == 32
    end
    if bit32 and type(bit32.band) == "function" then
        return bit32.band(mask, 32) == 32
    end
    return false
end

local function ResolveLoopDisplayName()
    local locale = type(GetLocale) == "function" and tostring(GetLocale() or "") or ""
    if locale == "zhCN" or locale == "zhTW" then
        return "AOE"
    end
    return "AOE"
end

local function ShowCastBar(seconds)
    local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
    if not (castBar and type(castBar.ShowEntry) == "function") then
        return
    end
    local now = GetTime()
    castBar:ShowEntry({
        duration = seconds,
        endTime = now + seconds,
        castKind = "cast",
        displayName = ResolveLoopDisplayName(),
        iconFileID = 136208,
    })
end

local function StopLoop()
    if repeatLoopTicker and type(repeatLoopTicker.Cancel) == "function" then
        repeatLoopTicker:Cancel()
    end
    repeatLoopTicker = nil
    encounterActive = false
    waitingForFirstTrigger = false
end

local function BeginRepeatingLoop()
    if encounterActive ~= true then
        return
    end
    if repeatLoopTicker and type(repeatLoopTicker.Cancel) == "function" then
        repeatLoopTicker:Cancel()
    end
    ShowCastBar(LOOP_SECONDS)
    repeatLoopTicker = C_Timer.NewTicker(LOOP_SECONDS, function()
        if encounterActive ~= true then
            return
        end
        ShowCastBar(LOOP_SECONDS)
    end)
end

local function StartFirstLoop()
    if encounterActive ~= true then
        return
    end
    waitingForFirstTrigger = false
    BeginRepeatingLoop()
end

local function StartEncounterWatch()
    StopLoop()
    encounterActive = true
    waitingForFirstTrigger = true
end

-- [ORIG] 原触发方式：监听暗系伤害作为首次触发信号
-- local function OnUnitCombat(unitTarget, schoolMask)
--     if encounterActive ~= true or waitingForFirstTrigger ~= true then return end
--     if tostring(unitTarget or "") ~= "player" then return end
--     if not HasShadowSchool(schoolMask) then return end
--     StartFirstLoop()
-- end

do
    watchFrame = CreateFrame("Frame")
    watchFrame:SetScript("OnEvent", function(_, event, ...)
        -- [ORIG] if event == "UNIT_COMBAT" then
        --     local unitTarget, _, _, _, schoolMask = ...
        --     OnUnitCombat(unitTarget, schoolMask)
        -- els
        if event == "ENCOUNTER_START" then
            local encounterID = ...
            if tonumber(encounterID) ~= ENCOUNTER_ID then
                return
            end
            StartEncounterWatch()
        elseif event == "ENCOUNTER_END" then
            local encounterID = ...
            if encounterID ~= nil and tonumber(encounterID) ~= ENCOUNTER_ID then
                return
            end
            StopLoop()
        elseif event == "PLAYER_ENTERING_WORLD" then
            StopLoop()
        end
    end)
    watchFrame:RegisterEvent("ENCOUNTER_START")
    watchFrame:RegisterEvent("ENCOUNTER_END")
    watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- [ORIG] watchFrame:RegisterEvent("UNIT_COMBAT")
end

-- 5 秒广播：EVENT_ID 剩余 ≤5s 时触发，精确在 remaining-0.1 秒后启动循环
if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent(
        "EXBOSS_TIMER_FIVE_SEC_REMAINING",
        "ExBoss_Raktul_FiveSecLoop",
        function(_, payload)
            if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then return end
            if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_ID then return end
            if encounterActive ~= true then return end

            local Scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
            local token     = Scheduler and Scheduler._sessionToken
            local remaining = math.max(0, tonumber(payload.remaining) or 0)

            C_Timer.After(math.max(0, remaining - 0.1), function()
                if Scheduler and Scheduler._sessionToken ~= token then return end
                if encounterActive ~= true then return end
                BeginRepeatingLoop()
            end)
        end
    )
end

R:Register({
    encounterID = ENCOUNTER_ID,
    dungeon = { key = "maisara_caverns", name = "Maisara Caverns", zhCN = "迈萨拉洞窟" },
    boss = { key = "raktul_vessel_of_souls", name = "Rak'tul, Vessel of Souls", zhCN = "拉克图尔，聚魂之器" },
    healthThresholds = {},
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
