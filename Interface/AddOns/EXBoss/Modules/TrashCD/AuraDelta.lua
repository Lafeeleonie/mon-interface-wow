---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.AuraDelta or {}
ExBoss.TrashCD.AuraDelta = Mod
ExBoss.Trash.AuraDelta = Mod

local MAX_AURAS = 40
local RECENT_KEEP_SECONDS = 1.0
local DEFAULT_DELAY = 0.10
local DEFAULT_PRE_WINDOW = 0.10
local DEFAULT_POST_WINDOW = 0.10
local OWNER = "ExBoss.TrashCD.AuraDelta"

Mod.enabled = Mod.enabled == true
Mod.seeded = Mod.seeded == true
Mod.auraCache = Mod.auraCache or {}
Mod.recentAdds = Mod.recentAdds or {}

local function WipeTable(t)
    if type(t) ~= "table" then
        return
    end
    if wipe then
        wipe(t)
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function Now()
    return GetTime and GetTime() or 0
end

local function IsTrackedUnit(unit)
    if unit == "player" then
        return true
    end
    return type(unit) == "string" and unit:match("^party[1-4]$") ~= nil
end

local function GetTrackedUnits()
    local units = { "player" }
    for i = 1, 4 do
        units[#units + 1] = "party" .. i
    end
    return units
end

local function SafeAuraInstanceID(aura)
    if type(aura) ~= "table" then
        return nil
    end
    local ok, value = pcall(function()
        return aura.auraInstanceID
    end)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function GetHarmfulAuraIDs(unit)
    local ids = {}
    if not (type(unit) == "string" and UnitExists and UnitExists(unit)) then
        return ids
    end
    local fn = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
    if type(fn) ~= "function" then
        return ids
    end
    for index = 1, MAX_AURAS do
        local ok, aura = pcall(fn, unit, index, "HARMFUL")
        if not ok or not aura then
            break
        end
        local auraInstanceID = SafeAuraInstanceID(aura)
        if auraInstanceID then
            ids[auraInstanceID] = true
        end
    end
    return ids
end

local function TrimRecentAdds(now)
    now = tonumber(now) or Now()
    local keepAfter = now - RECENT_KEEP_SECONDS
    local recent = Mod.recentAdds
    for i = #recent, 1, -1 do
        if (tonumber(recent[i] and recent[i].at) or 0) < keepAfter then
            table.remove(recent, i)
        end
    end
end

function Mod.RefreshUnit(unit, seedOnly)
    if Mod.enabled ~= true then
        return
    end
    if not IsTrackedUnit(unit) or not (UnitExists and UnitExists(unit)) then
        Mod.auraCache[unit] = nil
        return
    end

    local now = Now()
    local old = Mod.auraCache[unit] or {}
    local current = GetHarmfulAuraIDs(unit)
    Mod.auraCache[unit] = current

    if seedOnly then
        return
    end

    TrimRecentAdds(now)
    for auraInstanceID in pairs(current) do
        if not old[auraInstanceID] then
            Mod.recentAdds[#Mod.recentAdds + 1] = {
                unit = unit,
                id = auraInstanceID,
                at = now,
            }
        end
    end
end

function Mod.RefreshGroup(seedOnly)
    local units = GetTrackedUnits()
    for i = 1, #units do
        Mod.RefreshUnit(units[i], seedOnly == true)
    end
    if seedOnly then
        Mod.seeded = true
    end
end

function Mod.SetEnabled(enabled)
    enabled = enabled == true
    if Mod.enabled == enabled then
        if enabled and Mod.seeded ~= true then
            Mod.RefreshGroup(true)
        end
        return
    end
    Mod.enabled = enabled
    WipeTable(Mod.auraCache)
    WipeTable(Mod.recentAdds)
    Mod.seeded = false
    if enabled then
        Mod.RefreshGroup(true)
    end
end

function Mod.FindRecentAdd(startAt, endAt)
    if Mod.enabled ~= true then
        return nil
    end
    local startTime = tonumber(startAt)
    local endTime = tonumber(endAt) or Now()
    if not startTime then
        return nil
    end
    TrimRecentAdds(endTime)
    local recent = Mod.recentAdds
    for i = #recent, 1, -1 do
        local row = recent[i]
        local at = tonumber(row and row.at)
        if at and at >= startTime and at <= endTime and row.unit and row.id then
            return row
        end
    end
    return nil
end

function Mod.ScheduleRuntimeCheck(runtime, kind, delay, preWindow, postWindow, callback)
    if type(postWindow) == "function" and callback == nil then
        callback = postWindow
        postWindow = nil
    end
    if type(runtime) ~= "table" or type(callback) ~= "function" then
        return false
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return false
    end
    if Mod.enabled ~= true then
        Mod.SetEnabled(true)
    elseif Mod.seeded ~= true then
        Mod.RefreshGroup(true)
    end

    local seq = tonumber(runtime.activeCastSeq)
    local castKind = tostring(kind or runtime.activeCastKind or "")
    local castBarID = runtime.activeCastBarID
    local startAt = tonumber(runtime.activeCastStartAt)
    if not seq or castKind == "" or not startAt then
        return false
    end

    local wait = tonumber(delay) or DEFAULT_DELAY
    if wait < 0 then
        wait = DEFAULT_DELAY
    end
    local pre = tonumber(preWindow) or DEFAULT_PRE_WINDOW
    if pre < 0 then
        pre = 0
    end
    local post = tonumber(postWindow) or DEFAULT_POST_WINDOW
    if post < 0 then
        post = 0
    end

    C_Timer.After(wait, function()
        if type(runtime) ~= "table" then
            return
        end
        if tonumber(runtime.activeCastSeq) ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= castKind then
            return
        end
        if runtime.activeCastBarID ~= castBarID then
            return
        end

        Mod.RefreshGroup(false)
        local now = Now()
        local endAt = startAt + post
        if endAt > now then
            endAt = now
        end
        local row = Mod.FindRecentAdd(startAt - pre, endAt)
        callback(row ~= nil, row)
    end)
    return true
end

local function Register(event, owner, func)
    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent(event, owner, func)
        return
    end
    local frame = Mod.frame or CreateFrame("Frame")
    Mod.frame = frame
    Mod._eventHandlers = Mod._eventHandlers or {}
    Mod._eventHandlers[event] = func
    frame:RegisterEvent(event)
    frame:SetScript("OnEvent", function(_, ev, ...)
        local handler = Mod._eventHandlers and Mod._eventHandlers[ev] or nil
        if type(handler) == "function" then
            handler(ev, ...)
        end
    end)
end

Register("UNIT_AURA", OWNER .. ".UnitAura", function(_, unit)
    if Mod.enabled ~= true then
        return
    end
    if not IsTrackedUnit(unit) then
        return
    end
    Mod.RefreshUnit(unit, false)
end)

Register("GROUP_ROSTER_UPDATE", OWNER .. ".Roster", function()
    if Mod.enabled == true then
        WipeTable(Mod.auraCache)
        WipeTable(Mod.recentAdds)
        Mod.seeded = false
        Mod.RefreshGroup(true)
    end
end)
