---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Display = ExBoss.Display or {}

local Mod = ExBoss.Display.PartyFrameGlow or {}
ExBoss.Display.PartyFrameGlow = Mod

local DEFAULT_STYLE = "Pixel Glow"
local DEFAULT_COLOR = { 1, 0.86, 0.1, 1 }
local DEFAULT_DURATION = 5
local DEFAULT_FREQUENCY = 0.35
local DEFAULT_LINES = 10
local DEFAULT_SCALE = 2
local DEFAULT_OFFSET = 0
local active = Mod.active or {}
Mod.active = active
Mod._token = tonumber(Mod._token) or 0

local VALID_STYLES = {
    ["Pixel Glow"] = true,
    ["Action Button Glow"] = true,
    ["Autocast Shine"] = true,
    ["Proc Glow"] = true,
}

local function ClampNumber(value, minValue, maxValue, defaultValue)
    local n = tonumber(value)
    if not n then
        return defaultValue
    end
    if minValue and n < minValue then
        return minValue
    end
    if maxValue and n > maxValue then
        return maxValue
    end
    return n
end

function Mod.GetDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.partyFrameGlow = ExBossDB.ui.partyFrameGlow or {}
    local db = ExBossDB.ui.partyFrameGlow

    if db.glowEnabled == nil then db.glowEnabled = true end
    if not VALID_STYLES[tostring(db.glowStyle or "")] then db.glowStyle = DEFAULT_STYLE end
    db.glowColorR = ClampNumber(db.glowColorR, 0, 1, DEFAULT_COLOR[1])
    db.glowColorG = ClampNumber(db.glowColorG, 0, 1, DEFAULT_COLOR[2])
    db.glowColorB = ClampNumber(db.glowColorB, 0, 1, DEFAULT_COLOR[3])
    db.glowColorA = ClampNumber(db.glowColorA, 0, 1, DEFAULT_COLOR[4])
    db.glowFrequency = ClampNumber(db.glowFrequency, 0.1, 5, DEFAULT_FREQUENCY)
    db.glowLines = math.floor(ClampNumber(db.glowLines, 1, 30, DEFAULT_LINES) + 0.5)
    db.glowScale = ClampNumber(db.glowScale, 0.5, 3, DEFAULT_SCALE)
    db.glowOffset = ClampNumber(db.glowOffset, -50, 50, DEFAULT_OFFSET)
    db.duration = ClampNumber(db.duration, 0.1, 60, DEFAULT_DURATION)
    return db
end

function Mod.BuildOptions(opts)
    opts = type(opts) == "table" and opts or {}

    local out = {
        enabled = true,
        style = DEFAULT_STYLE,
        color = DEFAULT_COLOR,
        duration = DEFAULT_DURATION,
        frequency = DEFAULT_FREQUENCY,
        lines = DEFAULT_LINES,
        scale = DEFAULT_SCALE,
        offset = DEFAULT_OFFSET,
    }

    if opts.useGlobalSettings == true then
        local db = Mod.GetDB()
        out.enabled = db.glowEnabled ~= false
        out.style = db.glowStyle or DEFAULT_STYLE
        out.color = { db.glowColorR, db.glowColorG, db.glowColorB, db.glowColorA }
        out.duration = db.duration
        out.frequency = db.glowFrequency
        out.lines = db.glowLines
        out.scale = db.glowScale
        out.offset = db.glowOffset
    end

    if opts.enabled ~= nil then out.enabled = opts.enabled ~= false end
    if VALID_STYLES[tostring(opts.style or "")] then out.style = opts.style end
    if type(opts.color) == "table" then out.color = opts.color end
    if opts.duration ~= nil then out.duration = ClampNumber(opts.duration, 0.1, 60, out.duration) end
    if opts.frequency ~= nil then out.frequency = ClampNumber(opts.frequency, 0.1, 5, out.frequency) end
    if opts.lines ~= nil then out.lines = math.floor(ClampNumber(opts.lines, 1, 30, out.lines) + 0.5) end
    if opts.scale ~= nil then out.scale = ClampNumber(opts.scale, 0.5, 3, out.scale) end
    if opts.offset ~= nil then out.offset = ClampNumber(opts.offset, -50, 50, out.offset) end

    return out
end

local function Now()
    return GetTime and GetTime() or 0
end

function Mod.FindUnitFrame(unit, opts)
    if type(ExwindTools) ~= "table"
    or type(ExwindTools.UnitFrame) ~= "table"
    or type(ExwindTools.UnitFrame.FindUnitFrame) ~= "function" then
        return nil
    end
    return ExwindTools.UnitFrame.FindUnitFrame(unit, opts)
end

local function GetGlowLib()
    if LibStub then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibCustomGlow-1.0", true)
        if ok then
            return lib
        end
    end
    return nil
end

local function EnsureFallback(frame, key)
    frame.__ExBossPartyFrameFallbackGlows = frame.__ExBossPartyFrameFallbackGlows or {}
    if frame.__ExBossPartyFrameFallbackGlows[key] then
        return frame.__ExBossPartyFrameFallbackGlows[key]
    end
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glow:SetFrameStrata(frame:GetFrameStrata())
    glow:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    glow:Hide()
    frame.__ExBossPartyFrameFallbackGlows[key] = glow
    return glow
end

local function StartFrameGlow(frame, key, opts)
    opts = Mod.BuildOptions(opts)
    local color = opts.color or DEFAULT_COLOR
    local style = opts.style or DEFAULT_STYLE
    local lines = math.max(1, math.floor(tonumber(opts.lines) or DEFAULT_LINES))
    local frequency = tonumber(opts.frequency) or DEFAULT_FREQUENCY
    local scale = tonumber(opts.scale) or DEFAULT_SCALE
    local offset = tonumber(opts.offset) or DEFAULT_OFFSET
    local lib = GetGlowLib()
    if lib then
        if style == "Action Button Glow" and type(lib.ButtonGlow_Start) == "function" then
            lib.ButtonGlow_Start(frame, color, frequency, 20)
            return "lib_action"
        elseif style == "Autocast Shine" and type(lib.AutoCastGlow_Start) == "function" then
            lib.AutoCastGlow_Start(frame, color, lines, frequency, scale, offset, offset, key, 20)
            return "lib_autocast"
        elseif style == "Proc Glow" and type(lib.ProcGlow_Start) == "function" then
            lib.ProcGlow_Start(frame, {
                key = key,
                color = color,
                frameLevel = 20,
                xOffset = offset,
                yOffset = offset,
                duration = 1,
            })
            return "lib_proc"
        elseif type(lib.PixelGlow_Start) == "function" then
            lib.PixelGlow_Start(frame, color, lines, frequency, nil, scale, offset, offset, false, key, 20)
            return "lib_pixel"
        end
    end

    local glow = EnsureFallback(frame, key)
    local c = color or DEFAULT_COLOR
    glow:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -(3 + offset), 3 + offset)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3 + offset, -(3 + offset))
    glow:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = math.max(1, scale),
    })
    glow:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 0, c[4] or 1)
    glow:Show()
    return "fallback"
end

local function StopFrameGlow(frame, key, mode)
    if not frame then
        return
    end
    if mode == "lib_pixel" then
        local lib = GetGlowLib()
        if lib and type(lib.PixelGlow_Stop) == "function" then
            lib.PixelGlow_Stop(frame, key)
        end
    elseif mode == "lib_autocast" then
        local lib = GetGlowLib()
        if lib and type(lib.AutoCastGlow_Stop) == "function" then
            lib.AutoCastGlow_Stop(frame, key)
        end
    elseif mode == "lib_proc" then
        local lib = GetGlowLib()
        if lib and type(lib.ProcGlow_Stop) == "function" then
            lib.ProcGlow_Stop(frame, key)
        end
    elseif mode == "lib_action" then
        local lib = GetGlowLib()
        if lib and type(lib.ButtonGlow_Stop) == "function" then
            lib.ButtonGlow_Stop(frame)
        end
    elseif frame.__ExBossPartyFrameFallbackGlows and frame.__ExBossPartyFrameFallbackGlows[key] then
        frame.__ExBossPartyFrameFallbackGlows[key]:Hide()
    end
end

function Mod.Hide(key)
    key = tostring(key or "")
    local entry = active[key]
    if not entry then
        return
    end
    for i = 1, #(entry.frames or {}) do
        local row = entry.frames[i]
        StopFrameGlow(row.frame, key, row.mode)
    end
    active[key] = nil
end

function Mod.ShowUnits(key, units, opts)
    key = tostring(key or "")
    if key == "" then
        return false
    end

    Mod.Hide(key)
    if type(units) ~= "table" then
        return false
    end

    opts = Mod.BuildOptions(opts)
    if opts.enabled == false then
        return false
    end

    local duration = math.max(0.1, tonumber(opts.duration) or DEFAULT_DURATION)
    Mod._token = Mod._token + 1
    local entry = {
        token = Mod._token,
        expires = Now() + duration,
        frames = {},
    }

    for i = 1, #units do
        local unit = units[i]
        local frame = Mod.FindUnitFrame(unit, opts)
        if frame then
            local mode = StartFrameGlow(frame, key, opts)
            entry.frames[#entry.frames + 1] = { frame = frame, mode = mode }
        end
    end

    active[key] = entry
    local token = entry.token
    if C_Timer and C_Timer.After then
        C_Timer.After(duration, function()
            local current = active[key]
            if current and current.token == token then
                Mod.Hide(key)
            end
        end)
    end
    return #entry.frames > 0
end

function Mod.Refresh(key, units, opts)
    return Mod.ShowUnits(key, units, opts)
end
