local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "darkness_announcer",
    name = "Darkness Announcer",
    version = ns.Versions.DARKNESS_ANNOUNCER,
    source = "core",
    internal = true,
    subtitle = "Announce Darkness start/end in group chat.",
    onboardingDescription = "Automatically announces the start and end of Darkness.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\darkness.tga",
    events = { "ENCOUNTER_START", "ENCOUNTER_END" },
    unitEvents = {
        { event = "UNIT_SPELLCAST_SUCCEEDED", unit = "player" },
        { event = "UNIT_AURA", unit = "player" },
    },
    defaults = {
        enabled         = false,
        channelStart    = "AUTO",
        channelEnd      = "AUTO",
        instancesOnly   = true,
        durationSeconds = 8,
        endMessage      = ">>> Darkness Over <<<",
        startMessage    = ">>> DARKNESS <<<",
        onlyInGroup     = false,
    },
}

-- Constants & Policy
module.CONSTANTS = {
    DARKNESS_SPELL_ID = 196718,
    FALLBACK_DURATION = 9,
    MIN_CAST_INTERVAL = 0.25,
    RECHECK_DELAY = 0.5,
    SAFETY_MARGIN = 0.05,
}

-- Helper functions
local function IsInAnyGroup()
    return IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
end

local function ResolveChannel(requested)
    local c = string.upper(requested or "AUTO")

    if c == "INSTANCE_CHAT" then
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or nil, "not_in_instance_group"
    end
    if c == "PARTY" then
        return IsInGroup() and "PARTY" or nil, "not_in_party"
    end

    -- AUTO logic
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup() then return "PARTY" end
    return nil, "no_group_channel"
end

function module:IsAvailable(context)
    local classToken = context and context.classToken or ns.Compat.GetPlayerClassToken()
    if classToken ~= "DEMONHUNTER" then return false, "Demon Hunter only" end
    return true
end

function module:ResetState()
    self.castActive = false
    self.endMessageSent = true
    self.lastCastAt = 0
    self.castToken = 0
    self.darknessAuraPresent = false
    self.encounterActive = false
    self.warningCache = self.warningCache or {}
end

function module:CancelTimer()
    if self.endTimer then
        self.endTimer:Cancel()
        self.endTimer = nil
    end
end

function module:CanAnnounce()
    local s = self.settings
    if not s then return false, "no_settings" end
    if s.instancesOnly and not ns.Compat.IsInInstance() then return false, "not_in_instance" end
    if s.onlyInGroup and not IsInAnyGroup() then return false, "not_in_group" end
    return true
end

function module:SendAnnouncement(requestedChannel, message)
    if not self:CanAnnounce() or self.encounterActive then return end

    local channel, reason = ResolveChannel(requestedChannel)
    if not channel then
        if ns.Diagnostics and reason and reason ~= "no_group_channel" then
            local key = reason .. ":" .. requestedChannel
            if not self.warningCache[key] then
                self.warningCache[key] = true
                ns.Diagnostics:Warn(("Darkness Announcer: Blocked (%s)."):format(reason))
            end
        end
        return
    end

    pcall(SendChatMessage, message, channel)
end

function module:EvaluateEndState()
    if not self.castActive or self.endMessageSent then return end
    if self.darknessAuraPresent then
        self:ScheduleEndCheck(self.CONSTANTS.RECHECK_DELAY)
        return
    end

    local _, _, expiration = ns.Compat.FindPlayerAuraBySpellID(self.CONSTANTS.DARKNESS_SPELL_ID)

    -- WoW 12.0: aura expirationTime can be a "secret number" in restricted
    -- contexts (raid encounters). Tainted code cannot compare or do
    -- arithmetic on a secret number (and even a plain truthiness test is
    -- documented as forbidden), so we have to dispatch on type() first --
    -- type() is always safe -- and only touch the value once IsNonSecretNumber
    -- has cleared it.
    if type(expiration) ~= "number" then
        -- No aura returned from the API: it really ended.
        self:AnnounceEnd()
    elseif not ns.Compat.IsNonSecretNumber(expiration) then
        -- Aura is still on the player but the timer is opaque. Short-poll;
        -- the UNIT_AURA handler in OnEvent (which only nil-checks the aura
        -- table, never reads its fields) will fire AnnounceEnd safely when
        -- the buff actually drops.
        self.darknessAuraPresent = true
        self:ScheduleEndCheck(self.CONSTANTS.RECHECK_DELAY)
    elseif expiration > ns.Compat.GetTime() then
        self.darknessAuraPresent = true
        self:ScheduleEndCheck((expiration - ns.Compat.GetTime()) + self.CONSTANTS.SAFETY_MARGIN)
    else
        self:AnnounceEnd()
    end
end

function module:ScheduleEndCheck(delay)
    self:CancelTimer()
    local currentToken = self.castToken
    self.endTimer = C_Timer.NewTimer(math.max(delay, self.CONSTANTS.SAFETY_MARGIN), function()
        if self.castToken == currentToken then self:EvaluateEndState() end
    end)
end

function module:AnnounceEnd()
    if self.endMessageSent then return end
    self.endMessageSent = true
    self.castActive = false
    self:CancelTimer()
    
    local s = self.settings or self.defaults
    self:SendAnnouncement(s.channelEnd, s.endMessage or ">>> Darkness Over <<<")
end

function module:HandleCastTrigger()
    if self.castActive then return end
    local now = ns.Compat.GetTime()
    if (now - self.lastCastAt) < self.CONSTANTS.MIN_CAST_INTERVAL then return end

    self.castToken = self.castToken + 1
    self.lastCastAt = now
    self.castActive = true
    self.endMessageSent = false
    self.darknessAuraPresent = false

    local s = self.settings or self.defaults
    self:SendAnnouncement(s.channelStart, s.startMessage or ">>> DARKNESS <<<")

    local duration = tonumber(s.durationSeconds) or self.CONSTANTS.FALLBACK_DURATION
    self:ScheduleEndCheck(duration + self.CONSTANTS.SAFETY_MARGIN)
end

function module:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        self.encounterActive = true
    elseif event == "ENCOUNTER_END" then
        self.encounterActive = false
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if spellID == self.CONSTANTS.DARKNESS_SPELL_ID then
            self:HandleCastTrigger()
        end
    elseif event == "UNIT_AURA" then
        -- Unit filter is handled at the EventBus level (RegisterUnitEvent "player").
        -- Outside the Darkness cast window the aura check result is never used,
        -- so skip the C_UnitAuras lookup to avoid work on every HoT/DoT tick.
        if not self.castActive then return end
        local active = ns.Compat.FindPlayerAuraBySpellID(self.CONSTANTS.DARKNESS_SPELL_ID) ~= nil
        if active ~= self.darknessAuraPresent then
            self.darknessAuraPresent = active
            if not active and not self.endMessageSent then
                self:AnnounceEnd()
            end
        end
    end
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
end

function module:OnEnable(settings)
    self:ApplySettings(settings)
    self:ResetState()
    self.darknessAuraPresent = ns.Compat.FindPlayerAuraBySpellID(self.CONSTANTS.DARKNESS_SPELL_ID) ~= nil
end

function module:OnDisable()
    self:CancelTimer()
    self:ResetState()
end

function module:RunTest()
    self:HandleCastTrigger()
end

function module:GetDebugState()
    return {
        castActive = self.castActive,
        auraPresent = self.darknessAuraPresent,
        canAnnounce = self:CanAnnounce(),
    }
end

function module:GetConfiguredDuration()
    local s = self.settings or self.defaults
    return tonumber(s.durationSeconds) or self.CONSTANTS.FALLBACK_DURATION
end

ns.ModuleRegistry:Register(module)
