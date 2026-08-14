local _, ns = ...

ns.Compat = ns.Compat or {}
local Compat = ns.Compat

function Compat.GetPlayerClassToken()
    local _, classToken = UnitClass("player")
    return classToken
end

function Compat.GetSpecializationID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        return select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    end
    return nil
end

function Compat.IsInCombat()
    return InCombatLockdown()
end

function Compat.IsInInstance()
    return IsInInstance()
end

function Compat.GetTime()
    return GetTimePreciseSec()
end

-- WoW 12.0 (Midnight) "Secret Values": certain APIs (GetUnitSpeed for the
-- player, aura expirationTime/duration, UnitHealth/UnitPower in restricted
-- contexts, ...) return numbers that are flagged as protected when called
-- from a tainted execution path. Tainted code may store those values but
-- cannot compare them or do arithmetic on them without raising
-- "attempt to compare/perform arithmetic on a secret number value".
-- issecretvalue is the official detection helper added in 12.0; on older
-- clients it does not exist and nothing is ever secret, so we treat any
-- regular number as safe.
local _issecretvalue = issecretvalue
function Compat.IsNonSecretNumber(v)
    if type(v) ~= "number" then return false end
    if _issecretvalue and _issecretvalue(v) then return false end
    return true
end

function Compat.GetCursorPositionScaled()
    if UIParent and UIParent.GetScaledCursorPosition then
        local scaledX, scaledY = UIParent:GetScaledCursorPosition()
        if scaledX and scaledY then
            return scaledX, scaledY
        end
    end

    local x, y  = GetCursorPosition()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if scale and scale > 0 then
        x = x / scale
        y = y / scale
    end
    return x, y
end

function Compat.GetSpellCooldown(spellID)
    local startTime = 0
    local duration  = 0
    local modRate   = 1

    -- C_Spell.GetSpellCooldown is the only supported API in 12.0.1.
    -- pcall + tonumber(tostring()) washes any tainted values before comparison.
    local ok, result = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and type(result) == "table" then
        startTime = tonumber(tostring(result.startTime)) or 0
        duration  = tonumber(tostring(result.duration)) or 0
        modRate   = tonumber(tostring(result.modRate)) or 1
        -- isEnabled is NOT read: the field is protected by Blizzard in combat (taint risk).
    end

    -- Final taint-break pass.
    startTime = tonumber(tostring(startTime)) or 0
    duration  = tonumber(tostring(duration)) or 0
    modRate   = tonumber(tostring(modRate)) or 1

    local remaining = 0
    if startTime > 0 and duration > 0 then
        remaining = math.max((startTime + duration) - Compat.GetTime(), 0)
    end

    return startTime, duration, true, modRate, remaining
end

-- Chat types that addons cannot use via automation in 12.0.1.
local RESTRICTED_AUTOMATION_CHAT_TYPES = {
    SAY        = true,
    EMOTE      = true,
    TEXT_EMOTE = true,
    CHANNEL    = true,
}

local function TrimString(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeChatType(chatType)
    local normalized = string.upper(TrimString(chatType))
    if normalized == "" then
        normalized = "AUTO"
    end
    if normalized == "INSTANCE" then
        normalized = "INSTANCE_CHAT"
    end
    return normalized
end

function Compat.GetBestGroupChatType()
    -- Priority 1: Instance Chat (for queued groups/LFG)
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end

    -- Priority 2: Raid Chat
    if IsInRaid() then
        return "RAID"
    end

    -- Priority 3: Party Chat
    if IsInGroup() then
        return "PARTY"
    end

    -- Fallback: YELL is allowed by addons inside instances (but may be restricted in combat)
    if Compat.IsInInstance() then
        return "YELL"
    end

    return nil
end

function Compat.ResolveChatType(requestedChatType)
    local chatType = NormalizeChatType(requestedChatType)

    if chatType == "AUTO" then
        local bestType = Compat.GetBestGroupChatType()
        if bestType then
            return bestType
        end
        return nil, "no_group_channel"
    end

    if RESTRICTED_AUTOMATION_CHAT_TYPES[chatType] then
        return nil, "restricted_channel"
    end

    -- YELL is allowed by addons inside instances only.
    -- Outside instances Blizzard blocks addon-driven YELL.
    if chatType == "YELL" then
        if Compat.IsInInstance() then
            return chatType
        end
        return nil, "yell_outside_instance"
    end

    if chatType == "INSTANCE_CHAT" then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            return chatType
        end
        return nil, "not_in_instance_group"
    end

    if chatType == "RAID" then
        if IsInRaid() then
            return chatType
        end
        return nil, "not_in_raid"
    end

    if chatType == "RAID_WARNING" then
        if IsInRaid() then
            if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
                return chatType
            end
            return nil, "raid_warning_requires_assist"
        end
        return nil, "not_in_raid"
    end

    if chatType == "PARTY" then
        if IsInGroup() then
            return chatType
        end
        return nil, "not_in_party"
    end

    if chatType == "WHISPER" then
        return nil, "unsupported_without_target"
    end

    if chatType == "GUILD" then
        if IsInGuild() then
            return chatType
        end
        return nil, "not_in_guild"
    end

    if chatType == "OFFICER" then
        if IsInGuild() then
            return chatType
        end
        return nil, "not_in_guild"
    end

    return chatType
end

function Compat.SendChatMessage(message, channel)
    local text = TrimString(message)
    if text == "" then
        return false
    end

    local chatType, reason = Compat.ResolveChatType(channel)
    if not chatType then
        return false, reason
    end

    local ok = pcall(SendChatMessage, text, chatType)
    if not ok then
        return false, "send_failed"
    end

    return true, nil, chatType
end

function Compat.GetSpellNameByID(spellID)
    return C_Spell.GetSpellName(spellID)
end

-- WoW 12.1 widened aura secrecy: "all of the UnitAura APIs will now either
-- return full secrets or nil when called by addons", auras are secret "during
-- combat, encounters, M+, and PvP matches", and "AuraData structs are now
-- always fully secret". That makes ANY truthiness test on a field that came out
-- of an aura struct unsafe -- including the `auraData.spellId or spellID`
-- defaulting this function used to do.
--
-- Presence-only check. Never reads a field, so it can never touch a secret and
-- is safe to call from every context, including inside a raid encounter.
function Compat.HasPlayerAura(spellID)
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return false end
    return type(auraData) == "table"
end

function Compat.FindPlayerAuraBySpellID(spellID)
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or type(auraData) ~= "table" then
        return nil
    end

    -- Pass duration / expirationTime through unmolested. Those fields can be
    -- secret numbers, and even a truthiness test is documented as forbidden on
    -- secret values. Callers must dispatch on type() and Compat.IsNonSecretNumber
    -- before doing any arithmetic or comparisons on them.
    -- spellId is resolved here instead of via `or`, which would be a truthiness
    -- test on a potentially secret number.
    local resolvedID = auraData.spellId
    if not Compat.IsNonSecretNumber(resolvedID) then
        resolvedID = spellID
    end

    return auraData.name, auraData.duration, auraData.expirationTime, auraData.sourceUnit,
        resolvedID
end

function Compat.GetAddOnVersion(name)
    return C_AddOns.GetAddOnMetadata(name, "Version")
end

-- New in 12.0.1: Native support for checking if an API is depreciated via Gethe's source patterns
function Compat.IsApiAvailable(namespace, funcName)
    if not namespace or not _G[namespace] then return false end
    return type(_G[namespace][funcName]) == "function"
end
