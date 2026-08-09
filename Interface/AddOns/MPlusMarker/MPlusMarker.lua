local addonName, addonTable = ...
local L = addonTable.L

--- Widen UIPanelButton-style buttons to fit localized text (prevents clipping).
local function FitPanelButtonWidth(button, minWidth, padX)
    padX = padX or 20
    minWidth = minWidth or 40
    if not button then return end
    local tw = 0
    if button.GetTextWidth then
        tw = button:GetTextWidth()
    end
    if (not tw or tw <= 0) and button.GetFontString then
        local fs = button:GetFontString()
        if fs then tw = fs:GetStringWidth() end
    end
    local w = tw + padX
    if w < minWidth then w = minWidth end
    button:SetWidth(w)
end

--- GameTooltip:AddLine with word wrap for long translations.
local function TooltipShowWrapped(self, anchor, text, r, g, b)
    r, g, b = r or 1, g or 1, b or 1
    GameTooltip:SetOwner(self, anchor)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(text, r, g, b, true)
    GameTooltip:Show()
end

local MACRO_NAME = "MPlusMarker"
local MACRO_FOCUS_NAME = "MPlusFocus"
local MACRO_KICK_NAME = "MPlusKick"
local MACRO_KICK_AUTO_NAME = "MPlusKickAuto"
local MACRO_AVENGERS_NAME = "MPlusAvengers"
local MACRO_STOP_NAME = "MPlusStop"

local pendingMacroUpdate = false
local pendingTmTildeSplash = false

local SPLASH_TM_TILDE_ID = "tmTildeMarking_v1"
local MARK_MODIFIERS = { "shift", "ctrl", "alt" }

--- Resolve spell name in the client's locale (required for /cast lines in macros).
local function GetSpellNameLocalized(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

-- Retail interrupt spell IDs (Wowhead retail, Jun 2026). Names resolved via client API.
local DRUID_SKULL_BASH_CAST_ID = 221514   -- Skull Bash (Feral/Guardian cast)
local DRUID_SKULL_BASH_TALENT_ID = 106839 -- Skull Bash (talent entry fallback)
local DRUID_SOLAR_BEAM_ID = 78675         -- Solar Beam (Balance)

local INTERRUPT_SPELL_IDS = {
    WARRIOR = 6552,    -- Pummel
    PALADIN = 96231,   -- Rebuke
    HUNTER = 147362,   -- Counter Shot
    ROGUE = 1766,      -- Kick
    PRIEST = 15487,    -- Silence
    DEATHKNIGHT = 47528, -- Mind Freeze
    SHAMAN = 57994,    -- Wind Shear
    MAGE = 2139,       -- Counterspell
    WARLOCK = 119898,  -- Command Demon (Felhunter: Spell Lock)
    MONK = 116705,     -- Spear Hand Strike
    DRUID = { DRUID_SKULL_BASH_CAST_ID, DRUID_SKULL_BASH_TALENT_ID },
    DEMONHUNTER = 183752, -- Disrupt
    EVOKER = 351338,   -- Quell
}

-- Protection Paladin (66): Rebuke on MPlusKick/MPlusKickAuto; Avenger's Shield on separate MPlusAvengers macro.
local INTERRUPT_SPELL_IDS_BY_SPEC = {
    -- Paladin
    [66] = 96231, -- Protection: Rebuke (31935 = MPlusAvengers)
    -- Druid
    [102] = { DRUID_SOLAR_BEAM_ID, DRUID_SKULL_BASH_CAST_ID, DRUID_SKULL_BASH_TALENT_ID }, -- Balance
    [103] = { DRUID_SKULL_BASH_CAST_ID, DRUID_SKULL_BASH_TALENT_ID }, -- Feral
    [104] = { DRUID_SKULL_BASH_CAST_ID, DRUID_SKULL_BASH_TALENT_ID }, -- Guardian
    -- Hunter
    [255] = { 187707, 147362 }, -- Survival: Muzzle, fallback Counter Shot
    -- Warlock
    [266] = { 89766, 119898 }, -- Demonology: Axe Toss, fallback Command Demon
}

-- Protection Paladin (66): Rebuke and Avenger's Shield are separate macros (no dual-cast).
local PROT_PALADIN_SPEC_ID = 66
local PROT_PALADIN_KICK_ID_AVENGERS_SHIELD = 31935
local PROT_PALADIN_KICK_ID_REBUKE = 96231

local STOP_SPELL_IDS = {
    WARRIOR = 107570,
    PALADIN = 853,
    HUNTER = 19577,
    ROGUE = 2094,
    PRIEST = 64044,
    DEATHKNIGHT = 221562,
    SHAMAN = 51514,
    MAGE = 118,
    WARLOCK = 6789,
    MONK = 115078,
    DRUID = 5211,
    DEMONHUNTER = 217832,
    EVOKER = 360806,
}

-- Legacy English defaults (saved variables from older versions)
local LEGACY_ENGLISH_INTERRUPTS = {
    WARRIOR = "Pummel", PALADIN = "Rebuke", HUNTER = "Counter Shot", ROGUE = "Kick",
    PRIEST = "Silence", DEATHKNIGHT = "Mind Freeze", SHAMAN = "Wind Shear", MAGE = "Counterspell",
    WARLOCK = "Command Demon", MONK = "Spear Hand Strike", DRUID = "Skull Bash",
    DEMONHUNTER = "Disrupt", EVOKER = "Quell",
}
local LEGACY_ENGLISH_STOPS = {
    WARRIOR = "Storm Bolt", PALADIN = "Hammer of Justice", HUNTER = "Intimidation", ROGUE = "Blind",
    PRIEST = "Psychic Horror", DEATHKNIGHT = "Asphyxiate", SHAMAN = "Hex", MAGE = "Polymorph",
    WARLOCK = "Mortal Coil", MONK = "Paralysis", DRUID = "Mighty Bash",
    DEMONHUNTER = "Imprison", EVOKER = "Sleep Walk",
}

--- Localized creature name for /tar (matches client's language).
local function GetLocalizedCreatureName(npcID)
    if not npcID then return nil end
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tooltipData = C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-" .. npcID)
        if tooltipData and tooltipData.lines and tooltipData.lines[1] then
            local fetchedName = tooltipData.lines[1].leftText
            if fetchedName then
                -- Wrap the string manipulation in a pcall to catch restricted 'secret strings'
                local success, cleanName = pcall(function()
                    return string.gsub(string.gsub(fetchedName, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
                end)
                
                if success then
                    fetchedName = cleanName
                else
                    fetchedName = nil -- Safely drop the secret string so the addon uses the default name
                end
            end
            if fetchedName and fetchedName ~= "" and fetchedName ~= "Unknown" then
                return fetchedName
            end
        end
    end
    return nil
end

--- Name used in target macros: prefer API resolution from npcId so /tar works in every locale.
local function GetMobTargetName(mob)
    if not mob then return "" end
    if mob.npcId then
        local n = GetLocalizedCreatureName(mob.npcId)
        if n and n ~= "" then return n end
    end
    return mob.name or ""
end

--- Persist client-local creature names for saved entries (fixes /tar when English fallbacks are stored).
local function RefreshMobListLocalizedNames(mobs)
    if not mobs then return end
    for _, mob in ipairs(mobs) do
        if mob.npcId then
            local n = GetLocalizedCreatureName(mob.npcId)
            if n and n ~= "" then
                mob.name = n
            end
        end
    end
end

local function RefreshLocalizedNamesForInstance(instanceID)
    if not instanceID or not MPlusMarkerDB[instanceID] or not MPlusMarkerDB[instanceID].mobs then
        return
    end
    RefreshMobListLocalizedNames(MPlusMarkerDB[instanceID].mobs)
end

--- Call on load / PEW / import so stored English names are replaced once the client has creature data.
local function RefreshAllSavedMobLocalizedNames()
    for id, data in pairs(MPlusMarkerDB) do
        local numId = tonumber(id)
        if numId and type(data) == "table" and data.mobs then
            RefreshMobListLocalizedNames(data.mobs)
        end
    end
end

local function ChatPrint(msg)
    print("|cFF00FF00" .. L.CHAT_PREFIX .. "|r " .. msg)
end
local function ChatPrintWarn(msg)
    print("|cFFFFFF00" .. L.CHAT_PREFIX .. "|r " .. msg)
end
local function ChatPrintErr(msg)
    print("|cFFFF0000" .. L.CHAT_PREFIX .. "|r " .. msg)
end

-- Stable English keys for SavedVariables (display names use L.* via GetGroupDisplayName)
local GROUP_S1 = "Midnight Season 1"
local GROUP_M0 = "Midnight M0's"
local GROUP_NS = "Non Seasonal Instances"

local function GetGroupDisplayName(gName)
    if gName == GROUP_S1 then return L.GROUP_MIDNIGHT_S1 end
    if gName == GROUP_M0 then return L.GROUP_MIDNIGHT_M0 end
    if gName == GROUP_NS then return L.GROUP_NON_SEASONAL end
    return gName
end

-- Default Data (Only used to initialize the database on first load). Dungeon names use C_Map when available.
-- npcId = creature ID (MDT enemy id / journal); names are English fallbacks if the client has not cached the NPC yet.
local DefaultZones = {
    [2874] = { name = "Maisara Caverns", group = GROUP_S1, mobs = {
        { name = "Keen Headhunter", npcId = 242964, marker = 1, backupMarker = 0 },
        { name = "Ritual Hexxer", npcId = 248685, marker = 2, backupMarker = 0 },
        { name = "Umbral Shadowbinder", npcId = 254740, marker = 7, backupMarker = 0 },
    } },
    [2805] = { name = "Windrunner Spire", group = GROUP_S1, mobs = {
        { name = "Devoted Woebringer", npcId = 232175, marker = 1, backupMarker = 0 },
        { name = "Ardent Cutthroat", npcId = 232171, marker = 2, backupMarker = 0 },
        { name = "Phantasmal Mystic", npcId = 232146, marker = 3, backupMarker = 0 },
    } },
    [2915] = { name = "Nexus-Point Xenas", group = GROUP_S1, mobs = {
        { name = "Circuit Seer", npcId = 248373, marker = 1, backupMarker = 0 },
        { name = "Grand Nullifier", npcId = 251853, marker = 2, backupMarker = 0 },
        { name = "Dreadflail", npcId = 248506, marker = 3, backupMarker = 0 },
    } },
    [2811] = { name = "Magisters' Terrace", group = GROUP_S1, mobs = {
        { name = "Blazing Pyromancer", npcId = 251861, marker = 2, backupMarker = 0 },
        { name = "Arcane Magister", npcId = 232369, marker = 4, backupMarker = 0 },
        { name = "Void Terror", marker = 8, backupMarker = 0 },
    } },
    [1209] = { name = "Skyreach", group = GROUP_S1, mobs = {
        { name = "Blinding Sun Priestess", npcId = 79462, marker = 3, backupMarker = 0 },
        { name = "Driving Gale-Caller", npcId = 78932, marker = 1, backupMarker = 0 },
        { name = "High Sage Viryx", npcId = 76266, marker = 7, backupMarker = 0 },
    } },
    [658]  = { name = "Pit of Saron", group = GROUP_S1, mobs = {
        { name = "Rimebone Coldwraith", npcId = 252566, marker = 1, backupMarker = 0 },
        { name = "Gloombound Shadebringer", npcId = 252567, marker = 2, backupMarker = 0 },
        { name = "Arcanist Cadaver", npcId = 252603, marker = 7, backupMarker = 0 },
    } },
    [1753] = { name = "Seat of the Triumvirate", group = GROUP_S1, mobs = {
        { name = "Rift Warden", npcId = 122571, marker = 1, backupMarker = 0 },
        { name = "Shadewing", npcId = 125340, marker = 2, backupMarker = 0 },
        { name = "Dire Voidbender", npcId = 122404, marker = 7, backupMarker = 0 },
    } },
    [2526] = { name = "Algeth'ar Academy", group = GROUP_S1, mobs = {
        { name = "Spectral Invoker", npcId = 196202, marker = 1, backupMarker = 0 },
        { name = "Unruly Textbook", npcId = 196044, marker = 2, backupMarker = 0 },
        { name = "Corrupted Manafiend", npcId = 196045, marker = 7, backupMarker = 0 },
    } },

    [2825] = { name = "Den of Nalorakk", group = GROUP_M0, mobs = {
        { name = "Magma Totem", marker = 7, backupMarker = 0 },
        { name = "Keen-Eyed Screecher", marker = 1, backupMarker = 0 },
        { name = "starvation effigy", marker = 2, backupMarker = 0 },
        { name = "Frigid Mauler", marker = 3, backupMarker = 0 },
        { name = "Ruthless totemcaller", marker = 4, backupMarker = 0 },
    } },
    [2813] = { name = "Murder Row", group = GROUP_M0, mobs = {
        { name = "Street Sneak", marker = 1, backupMarker = 0 },
        { name = "Felonious mage", marker = 2, backupMarker = 0 },
        { name = "Seductive Sayaad", marker = 3, backupMarker = 0 },
    } },
    [2859] = { name = "The Blinding Vale", group = GROUP_M0, mobs = {
        { name = "Lightgorged Lasher", marker = 1, backupMarker = 0 },
        { name = "Lightfeather Petalwing", marker = 2, backupMarker = 0 },
    } },
    [2923] = { name = "Voidscar Arena", group = GROUP_M0, mobs = {
        { name = "Kilivore Screamer", marker = 8, backupMarker = 0 },
        { name = "Enthralled Shaman", marker = 1, backupMarker = 0 },
    } },
}

-- Default zone names stay as written above (C_Map IDs can resolve to wrong labels).

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- Triggers when user swaps specs
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Triggers when combat drops

local ConfigGUI
local UpdateMacroForZone

-- String Encoding/Decoding functions to safely package multi-line notes for Export/Import
local function EncodeString(str)
    if not str then return "" end
    -- Safely encode delimiters (commas, pipes, semicolons) and newlines
    return string.gsub(str, "([%|%,%;%%\n])", function(c) return string.format("%%%02X", string.byte(c)) end)
end

local function DecodeString(str)
    if not str then return "" end
    return string.gsub(str, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

-- Base64 Encoder to generate "Random Codes" for safe sharing
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64decTable = {}
for i = 1, 64 do b64decTable[string.byte(b64chars, i)] = i - 1 end

local function Base64Encode(source_str)
    if not source_str then return "" end
    local b64 = {}
    local bit = _G.bit
    for i = 1, #source_str, 3 do
        local a, b, c = string.byte(source_str, i, i+2)
        local v = bit.lshift(a, 16) + bit.lshift(b or 0, 8) + (c or 0)
        table.insert(b64, string.sub(b64chars, bit.rshift(v, 18) + 1, bit.rshift(v, 18) + 1))
        table.insert(b64, string.sub(b64chars, bit.band(bit.rshift(v, 12), 63) + 1, bit.band(bit.rshift(v, 12), 63) + 1))
        table.insert(b64, not b and "=" or string.sub(b64chars, bit.band(bit.rshift(v, 6), 63) + 1, bit.band(bit.rshift(v, 6), 63) + 1))
        table.insert(b64, not c and "=" or string.sub(b64chars, bit.band(v, 63) + 1, bit.band(v, 63) + 1))
    end
    return table.concat(b64)
end

local function Base64Decode(b64str)
    if not b64str then return "" end
    local text = {}
    local bit = _G.bit
    b64str = string.gsub(b64str, "[^%w%+%/%=]", "")
    b64str = string.gsub(b64str, "=", "")
    
    for i = 1, #b64str, 4 do
        local a, b, c, d = string.byte(b64str, i, i+3)
        local v1 = b64decTable[a] or 0
        local v2 = b64decTable[b] or 0
        local v3 = b64decTable[c] or 0
        local v4 = b64decTable[d] or 0
        
        local v = bit.lshift(v1, 18) + bit.lshift(v2, 12) + bit.lshift(v3, 6) + v4
        table.insert(text, string.char(bit.band(bit.rshift(v, 16), 255)))
        if c then table.insert(text, string.char(bit.band(bit.rshift(v, 8), 255))) end
        if d then table.insert(text, string.char(bit.band(v, 255))) end
    end
    return table.concat(text)
end

local function IsPlayerSpellKnownForInterrupt(spellID)
    if not spellID then return false end
    if IsSpellKnown then
        if IsSpellKnown(spellID) then return true end
        if IsSpellKnown(spellID, true) then return true end
    end
    if C_Spell and C_Spell.IsSpellKnown then
        return C_Spell.IsSpellKnown(spellID)
    end
    return false
end

local function ResolveInterruptFromEntry(entry)
    if type(entry) == "number" then
        return entry
    end
    if type(entry) == "table" then
        for _, sid in ipairs(entry) do
            if IsPlayerSpellKnownForInterrupt(sid) then
                return sid
            end
        end
        return entry[1]
    end
end

local function ResolveInterruptSpellID(specID, playerClass)
    local specEntry = specID and INTERRUPT_SPELL_IDS_BY_SPEC[specID]
    if specEntry then
        return ResolveInterruptFromEntry(specEntry)
    end
    return ResolveInterruptFromEntry(INTERRUPT_SPELL_IDS[playerClass])
end

-- Healer specs without baseline interrupts (Resto Shaman excluded)
local NO_INTERRUPT_SPEC_IDS = {
    [65] = true,   -- Holy Paladin
    [256] = true,  -- Discipline Priest
    [257] = true,  -- Holy Priest
    [270] = true,  -- Mistweaver Monk
    [105] = true,  -- Restoration Druid
    [1468] = true, -- Preservation Evoker
}

-- Helper to Determine the Best Kick Spell dynamically based on active Specialization
local function GetDefaultInterrupt()
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec) or nil

    if specID and NO_INTERRUPT_SPEC_IDS[specID] then
        return nil
    end

    local _, playerClass = UnitClass("player")

    local sid = ResolveInterruptSpellID(specID, playerClass)
    return GetSpellNameLocalized(sid) or L.FALLBACK_KICK
end

--- Resolve spell ID by name for custom kick field parsing.
local function TryResolveSpellIdFromName(spellName)
    if not spellName or spellName == "" then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellName)
        if type(info) == "table" and info.spellID then
            return info.spellID
        end
    end
    if GetSpellInfo then
        local info = GetSpellInfo(spellName)
        if type(info) == "table" and info.spellID then
            return info.spellID
        end
    end
    return nil
end

--- Parse kickSpell saved value: blank = auto-detect, otherwise one spell name or ID.
local function ParseKickSpellConfig()
    local custom = MPlusMarkerDB and MPlusMarkerDB.kickSpell
    if not custom or strtrim(custom) == "" then
        return nil
    end
    local first = strtrim(string.match(strtrim(custom), "^([^,]+)"))
    if not first or first == "" then return nil end
    return { raw = first }
end

--- Resolve kick spell config to localized ability name for /cast lines.
local function ResolveKickCastName(raw)
    if not raw or raw == "" then return nil end
    local n = tonumber(raw)
    if n then
        return GetSpellNameLocalized(n) or raw
    end
    local id = TryResolveSpellIdFromName(raw)
    if id then
        return GetSpellNameLocalized(id) or raw
    end
    return raw
end

local function ResolveKickSpellNameFromID(spellID, fallback)
    return GetSpellNameLocalized(spellID) or fallback
end

local function IsProtPaladin()
    local _, classFile = UnitClass("player")
    if classFile ~= "PALADIN" then return false end
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec) or nil
    return specID == PROT_PALADIN_SPEC_ID
end

--- Shared kick plan for MPlusKick and MPlusKickAuto (single spell only).
local function ResolveKickMacroPlan()
    local parsed = ParseKickSpellConfig()
    if parsed then
        local name = ResolveKickCastName(parsed.raw)
        if not name or strtrim(name) == "" then return nil end
        return { type = "single", t = name, show = name }
    end

    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec) or nil
    if specID and NO_INTERRUPT_SPEC_IDS[specID] then
        return nil
    end

    if IsProtPaladin() then
        local name = ResolveKickSpellNameFromID(PROT_PALADIN_KICK_ID_REBUKE, L.FALLBACK_KICK)
        return { type = "single", t = name, show = name }
    end

    local _, playerClass = UnitClass("player")
    local spellID = ResolveInterruptSpellID(specID, playerClass)
    local kSpell = ResolveKickSpellNameFromID(spellID, L.FALLBACK_KICK)
    if not kSpell or strtrim(kSpell) == "" then return nil end
    return { type = "single", t = kSpell, show = kSpell }
end

--- Default kick label for the GUI.
local function GetKickDefaultDisplayText()
    if ParseKickSpellConfig() then return nil end
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec) or nil
    if specID and NO_INTERRUPT_SPEC_IDS[specID] then return nil end
    if IsProtPaladin() then
        return GetSpellNameLocalized(PROT_PALADIN_KICK_ID_REBUKE) or L.FALLBACK_KICK
    end
    return GetDefaultInterrupt()
end

local function BuildNoInterruptKickMacroText()
    local esc = (L.PRINT_NO_INTERRUPT_SPEC):gsub("\"", "\\\"")
    local pfx = L.CHAT_PREFIX:gsub("\"", "\\\"")
    return "#showtooltip\n/run print(\"|cFFFF0000" .. pfx .. "|r " .. esc .. "\")"
end

local function BuildFocusKickMacroFromPlan(plan)
    return "#showtooltip " .. plan.show .. "\n/cast [@focus,exists,nodead] [] " .. plan.t
end

local function BuildAutoKickMacroFromPlan(plan)
    local t = plan.t
    local tail = "\n/stopmacro [@focus,exists,nodead,harm]"
        .. "\n/focus target"
        .. "\n/cleartarget"
        .. "\n/targetenemy"
        .. "\n/cast " .. t
        .. "\n/target focus"
        .. "\n/clearfocus"
        .. "\n/startattack"

    return "#showtooltip " .. plan.show
        .. "\n/cast [@focus,exists,nodead,harm] " .. t
        .. tail
end

local function BuildProtAvengersMacroText()
    local name = ResolveKickSpellNameFromID(PROT_PALADIN_KICK_ID_AVENGERS_SHIELD, "Avenger's Shield")
    return "#showtooltip " .. name .. "\n/cast [@focus,exists,nodead] [] " .. name
end

local function DeleteMacroIfExists(macroName)
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex > 0 then
        DeleteMacro(macroIndex)
    end
end

-- Helper to Determine the Default Stop/CC Spell
local function GetDefaultStop()
    local _, playerClass = UnitClass("player")
    local sid = STOP_SPELL_IDS[playerClass]
    return GetSpellNameLocalized(sid) or L.FALLBACK_STOP
end

--- Clear saved custom spell when it matches legacy English or current auto-detected default (allows auto-detect after locale/API updates).
local function ClearLegacySavedSpell(dbKey, legacyEnglish, spellID)
    local saved = MPlusMarkerDB[dbKey]
    if not saved or strtrim(saved) == "" then return end
    if legacyEnglish and saved == legacyEnglish then
        MPlusMarkerDB[dbKey] = nil
        return
    end
    local localized = spellID and GetSpellNameLocalized(spellID)
    if localized and saved == localized then
        MPlusMarkerDB[dbKey] = nil
    end
end

local function NormalizeMarkModifier(value)
    if type(value) == "string" then
        value = string.lower(value)
        for _, mod in ipairs(MARK_MODIFIERS) do
            if value == mod then return mod end
        end
    end
    return "shift"
end

local function GetMarkModifierLabel(modTag)
    modTag = NormalizeMarkModifier(modTag)
    if modTag == "ctrl" then return L.MOD_CTRL end
    if modTag == "alt" then return L.MOD_ALT end
    return L.MOD_SHIFT
end

local function GetBackupMarkModifierTag()
    return NormalizeMarkModifier(MPlusMarkerDB and MPlusMarkerDB.backupMarkModifier)
end

local function GetFocusClearMarkModifierTag()
    return NormalizeMarkModifier(MPlusMarkerDB and MPlusMarkerDB.focusClearMarkModifier)
end

--- MPlusFocus macro text. Uses /tm ~N so an existing raid marker is never overwritten.
--- [nomouseover] clearfocus clears focus when the cursor is not over a unit (empty ground).
local function BuildFocusMacroText()
    local fMarker = MPlusMarkerDB.globalFocusMarker or 4
    local markerArg = "~" .. fMarker
    local modTag = GetFocusClearMarkModifierTag()
    local focusText = "/tm [mod:" .. modTag .. ",@mouseover,exists] 0;[mod:" .. modTag .. ",@target,exists] 0;[mod:" .. modTag .. ",@focus,exists] 0\n/stopmacro [mod:" .. modTag .. "]\n/tm [@focus,exists] 0\n/clearfocus [nomouseover]\n/focus [@mouseover,nodead,exists] [@target,nodead,exists]\n/tm [@focus,exists,nodead] " .. markerArg
    if string.len(focusText) > 255 then
        ChatPrintErr(L.PRINT_MACRO_LIMIT)
        focusText = "/tm [@focus,exists] 0\n/clearfocus [nomouseover]\n/focus [@mouseover,nodead,exists] [@target,nodead,exists]\n/tm [@focus,exists,nodead] " .. markerArg
    end
    return focusText
end

-- Helper to Build/Edit Macros Safely
local function CreateOrUpdateMacro(macroName, text, zoneName, macroTypeLabel, iconID)
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex > 0 then
        local name, icon, body = GetMacroInfo(macroIndex)
        -- Only edit the macro and print to chat if the text has actually changed!
        if body and strtrim(body) == strtrim(text) then
            return 
        end
        EditMacro(macroIndex, macroName, iconID or 134400, text)
        ChatPrint(string.format(L.PRINT_AUTO_UPDATED_MACRO, macroTypeLabel, zoneName))
    else
        -- Changing the 4th parameter to 'false' places the macro in the General Macros tab
        local newMacroID = CreateMacro(macroName, iconID or 134400, text, false)
        if newMacroID > 0 then
            ChatPrint(string.format(L.PRINT_CREATED_MACRO, macroTypeLabel, zoneName, macroName))
        end
    end
end

-- Dynamic Macro Builder
UpdateMacroForZone = function()
    if InCombatLockdown() then
        if not pendingMacroUpdate then
            pendingMacroUpdate = true
            ChatPrintWarn(L.PRINT_COMBAT_QUEUED)
        end
        return
    end
    
    pendingMacroUpdate = false
    
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()

    -- Keep /tar lines in the client's language for this dungeon before rebuilding macros
    RefreshLocalizedNamesForInstance(instanceID)
    
    -- 1. Build Target Macro (Only if we have recognized data for this specific zone)
    if instanceID and MPlusMarkerDB[instanceID] and MPlusMarkerDB[instanceID].mobs and #MPlusMarkerDB[instanceID].mobs > 0 then
        local zoneData = MPlusMarkerDB[instanceID]
        local targetText = "/cleartarget\n"
        for _, mob in ipairs(zoneData.mobs) do
            local tmLine = ""
            if mob.backupMarker and mob.backupMarker > 0 then
                local modTag = GetBackupMarkModifierTag()
                tmLine = "/tm [mod:" .. modTag .. ",exists,nodead] ~" .. mob.backupMarker .. "; [exists,nodead] " .. mob.marker .. "\n"
            else
                tmLine = "/tm [exists,nodead] " .. mob.marker .. "\n"
            end
            
            local nextLine = "/tar " .. GetMobTargetName(mob) .. "\n" .. tmLine
            
            if string.len(targetText) + string.len(nextLine) > 255 then
                ChatPrintErr(L.PRINT_MACRO_LIMIT)
                break
            end
            targetText = targetText .. nextLine
        end
        CreateOrUpdateMacro(MACRO_NAME, targetText, zoneData.name, L.MACRO_TYPE_TARGET, 1322722)
    else
        -- Fallback: Create a placeholder Target macro if it doesn't exist so users can bind it in a city
        if GetMacroIndexByName(MACRO_NAME) == 0 then
            local esc = (L.PRINT_ENTER_DUNGEON_PLACEHOLDER):gsub("\"", "\\\"")
            local pfx = L.CHAT_PREFIX:gsub("\"", "\\\"")
            CreateOrUpdateMacro(MACRO_NAME, "/run print(\"|cFFFF0000" .. pfx .. "|r " .. esc .. "\")", L.MACRO_ZONE_PLACEHOLDER, L.MACRO_TYPE_TARGET, 1322722)
        end
    end

    -- 2. Build Focus Macro (Universal Mouseover - Updates Everywhere)
    -- Hold configured modifier: clear raid marker on mouseover, else target, else focus; then stop (no focus/mark apply).
    -- Apply uses /tm ~N so focus marking never overwrites an existing raid marker.
    CreateOrUpdateMacro(MACRO_FOCUS_NAME, BuildFocusMacroText(), L.MACRO_ZONE_GLOBAL, L.MACRO_TYPE_FOCUS, 1033497)

    -- 3 & 4. Build Kick + Auto Kick macros (shared spell plan from GUI kickSpell field)
    local kickPlan = ResolveKickMacroPlan()
    local kickText, autoKickText
    if not kickPlan then
        kickText = BuildNoInterruptKickMacroText()
        autoKickText = kickText
    else
        kickText = BuildFocusKickMacroFromPlan(kickPlan)
        autoKickText = BuildAutoKickMacroFromPlan(kickPlan)
        if string.len(autoKickText) > 255 then
            ChatPrintErr(L.PRINT_MACRO_LIMIT)
        end
    end
    CreateOrUpdateMacro(MACRO_KICK_NAME, kickText, L.MACRO_ZONE_GLOBAL, L.MACRO_TYPE_KICK, 134400)
    CreateOrUpdateMacro(MACRO_KICK_AUTO_NAME, autoKickText, L.MACRO_ZONE_GLOBAL, L.MACRO_TYPE_KICK_AUTO, 134400)

    -- Prot Paladin: Avenger's Shield on its own macro (never combined with Rebuke).
    if IsProtPaladin() then
        CreateOrUpdateMacro(MACRO_AVENGERS_NAME, BuildProtAvengersMacroText(), L.MACRO_ZONE_GLOBAL, L.MACRO_TYPE_AVENGERS, 134400)
    else
        DeleteMacroIfExists(MACRO_AVENGERS_NAME)
    end

    -- 5. Build Focus CC/Stop Macro (Universal Mouseover - Updates Everywhere)
    local sSpell = MPlusMarkerDB.stopSpell
    if not sSpell or strtrim(sSpell) == "" then
        sSpell = GetDefaultStop()
    end
    
    local stopText = "#showtooltip\n/cast [@focus,exists,nodead] [] " .. sSpell
    CreateOrUpdateMacro(MACRO_STOP_NAME, stopText, L.MACRO_ZONE_GLOBAL, L.MACRO_TYPE_STOP, 134400)
end

-- ============================================================================
-- In-instance focus marker bar (adapted from FocusMarker — pick icon without opening config)
-- ============================================================================

local focusBarFrame
local FOCUS_BAR_ICON_COORDS = {
    {0.0,0.25,0.0,0.25},{0.25,0.5,0.0,0.25},{0.5,0.75,0.0,0.25},{0.75,1.0,0.0,0.25},
    {0.0,0.25,0.25,0.5},{0.25,0.5,0.25,0.5},{0.5,0.75,0.25,0.5},{0.75,1.0,0.25,0.5},
}

local function SetGlobalFocusMarker(markerIndex)
    markerIndex = tonumber(markerIndex)
    if not markerIndex or markerIndex < 1 or markerIndex > 8 then return end
    MPlusMarkerDB.globalFocusMarker = markerIndex
    if type(UpdateMacroForZone) == "function" then
        UpdateMacroForZone()
    end
    if focusBarFrame and focusBarFrame.UpdateSelection then
        focusBarFrame:UpdateSelection()
    end
    if ConfigGUI and type(ConfigGUI.Refresh) == "function" and ConfigGUI:IsShown() then
        ConfigGUI.Refresh()
    end
end

local function ShouldShowFocusMarkerBar()
    if MPlusMarkerDB.focusBarEnabled == false then return false end
    if IsInInstance() then return true end
    -- Show in the Focus tab so the bar can be repositioned outside instances
    if ConfigGUI and ConfigGUI:IsShown() and ConfigGUI.activeTab == "focus" then return true end
    return false
end

local function FocusBarStartMoving(frame)
    if InCombatLockdown() then return end
    frame:StartMoving()
end

local function SaveFocusBarPosition(frame)
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
    local relName = "UIParent"
    if relativeTo and type(relativeTo) ~= "string" and relativeTo.GetName then
        relName = relativeTo:GetName()
    elseif type(relativeTo) == "string" then
        relName = relativeTo
    end
    MPlusMarkerDB.focusBarPosition = { point, relName, relativePoint, xOfs, yOfs }
end

local function FocusBarStopMoving(frame)
    frame:StopMovingOrSizing()
    SaveFocusBarPosition(frame)
end

local function ApplyFocusBarPosition()
    if not focusBarFrame then return end
    focusBarFrame:ClearAllPoints()
    local pos = MPlusMarkerDB.focusBarPosition
    if not pos then
        pos = { "CENTER", "UIParent", "CENTER", 0, -120 }
        MPlusMarkerDB.focusBarPosition = pos
    end
    local p, r, rp, x, y = unpack(pos)
    if not p then
        p, r, rp, x, y = "CENTER", "UIParent", "CENTER", 0, -120
    end
    if type(r) ~= "string" then r = "UIParent" end
    local ok = pcall(function() focusBarFrame:SetPoint(p, r, rp, x, y) end)
    if not ok then
        focusBarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
end

local function UpdateFocusBarLayout()
    if not focusBarFrame then return end
    local size = MPlusMarkerDB.focusBarIconSize or 32
    local orientation = MPlusMarkerDB.focusBarOrientation or "HORIZONTAL"
    local spacing = 4

    for i, btn in ipairs(focusBarFrame.buttons) do
        btn:Show()
        btn:SetSize(size, size)
        btn:ClearAllPoints()
        if i == 1 then
            if orientation == "HORIZONTAL" then
                btn:SetPoint("LEFT", focusBarFrame, "LEFT", 0, 0)
            else
                btn:SetPoint("TOP", focusBarFrame, "TOP", 0, 0)
            end
        else
            local prev = focusBarFrame.buttons[i - 1]
            if orientation == "HORIZONTAL" then
                btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
            else
                btn:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
            end
        end
    end

    if orientation == "HORIZONTAL" then
        focusBarFrame:SetSize((8 * size) + (7 * spacing), size)
    else
        focusBarFrame:SetSize(size, (8 * size) + (7 * spacing))
    end

    if ShouldShowFocusMarkerBar() then
        focusBarFrame:Show()
    else
        focusBarFrame:Hide()
    end

    focusBarFrame:SetMovable(true)

    if focusBarFrame.UpdateSelection then
        focusBarFrame:UpdateSelection()
    end
end

function UpdateFocusBarVisibility()
    if focusBarFrame then
        UpdateFocusBarLayout()
    end
end

local function BuildFocusMarkerBar()
    focusBarFrame = CreateFrame("Frame", "MPlusMarkerFocusBar", UIParent)
    focusBarFrame:SetClampedToScreen(false)
    focusBarFrame:SetMovable(true)
    focusBarFrame:RegisterForDrag("LeftButton")
    focusBarFrame:SetFrameStrata("LOW")
    focusBarFrame:EnableMouse(true)

    focusBarFrame.bg = focusBarFrame:CreateTexture(nil, "BACKGROUND")
    focusBarFrame.bg:SetAllPoints()
    focusBarFrame.bg:SetColorTexture(0, 0, 0, 0.25)

    focusBarFrame:SetScript("OnDragStart", function(self)
        FocusBarStartMoving(self)
    end)
    focusBarFrame:SetScript("OnDragStop", function(self)
        FocusBarStopMoving(self)
    end)

    ApplyFocusBarPosition()

    focusBarFrame.buttons = {}
    for i = 1, 8 do
        local btn = CreateFrame("Button", nil, focusBarFrame)
        btn:SetID(i)
        btn:RegisterForDrag("LeftButton")

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        tex:SetTexCoord(unpack(FOCUS_BAR_ICON_COORDS[i]))
        tex:SetAllPoints()

        btn.highlight = btn:CreateTexture(nil, "OVERLAY")
        btn.highlight:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        btn.highlight:SetBlendMode("ADD")
        btn.highlight:SetPoint("TOPLEFT", -6, 6)
        btn.highlight:SetPoint("BOTTOMRIGHT", 6, -6)
        btn.highlight:Hide()

        btn:SetScript("OnClick", function()
            SetGlobalFocusMarker(i)
        end)

        btn:SetScript("OnEnter", function(self)
            TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_FOCUS_BAR_ICON)
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnDragStart", function()
            FocusBarStartMoving(focusBarFrame)
        end)
        btn:SetScript("OnDragStop", function()
            FocusBarStopMoving(focusBarFrame)
        end)

        focusBarFrame.buttons[i] = btn
    end

    function focusBarFrame:UpdateSelection()
        local current = MPlusMarkerDB.globalFocusMarker or 4
        for i, btn in ipairs(self.buttons) do
            if i == current then
                btn.highlight:Show()
            else
                btn.highlight:Hide()
            end
        end
    end

    UpdateFocusBarLayout()
end

-- MDT uses English keys in characteristics; map to locale table keys for display
local function GetLocalizedCCTypeName(ccKey)
    local map = {
        Stun = "CC_STUN", Silence = "CC_SILENCE", Incapacitate = "CC_INCAPACITATE",
        Disorient = "CC_DISORIENT", Fear = "CC_FEAR", Root = "CC_ROOT", Knock = "CC_KNOCK", Grip = "CC_GRIP",
    }
    local lk = map[ccKey]
    return lk and L[lk] or ccKey
end

-- Build MDT tooltip string from enemyData (MDT uses English names; id is creature NPC id)
local function BuildMDTInfoString(enemyData)
    local parts = {}

    if enemyData.stealthDetect or (enemyData.characteristics and enemyData.characteristics["Stealth Detect"]) then
        table.insert(parts, L.MDT_DETECTS_STEALTH)
    end

    if enemyData.spells then
        local spellList = {}
        for spellId, _ in pairs(enemyData.spells) do
            if type(spellId) == "number" then
                local spellName
                if C_Spell and C_Spell.GetSpellName then
                    spellName = C_Spell.GetSpellName(spellId)
                elseif GetSpellInfo then
                    spellName = GetSpellInfo(spellId)
                end
                if spellName and spellName ~= "" then
                    table.insert(spellList, spellName)
                end
            end
        end
        if #spellList > 0 then
            table.sort(spellList)
            table.insert(parts, string.format(L.MDT_CASTS_PREFIX, table.concat(spellList, ", ")))
        end
    end

    local immunities = {}
    local ccChecks = {"Stun", "Silence", "Incapacitate", "Disorient", "Fear", "Root", "Knock", "Grip"}
    if enemyData.characteristics then
        for _, cc in ipairs(ccChecks) do
            if not enemyData.characteristics[cc] then
                table.insert(immunities, GetLocalizedCCTypeName(cc))
            end
        end
    else
        for _, cc in ipairs(ccChecks) do
            table.insert(immunities, GetLocalizedCCTypeName(cc))
        end
    end

    if #immunities == 0 then
        table.insert(parts, L.MDT_FULLY_CC)
    elseif #immunities == #ccChecks then
        table.insert(parts, L.MDT_CC_IMMUNE)
    else
        table.insert(parts, string.format(L.MDT_IMMUNE_TO, table.concat(immunities, ", ")))
    end

    if #parts > 0 then
        return table.concat(parts, " | ")
    end
    return nil
end

-- includeLocalizedMatch: when true, also matches saved mob.name to the client's name for enemyData.id
-- (MDT stores English names; German/French/etc. lists need this). Avoid on hot paths (e.g. every tooltip refresh).
local function MobMatchesMDTEnemy(mobOrName, enemyData, includeLocalizedMatch)
    local npcId = type(mobOrName) == "table" and mobOrName.npcId or nil
    if npcId and enemyData.id == npcId then
        return true
    end
    local nameStr = type(mobOrName) == "table" and mobOrName.name or mobOrName
    if enemyData.name and nameStr and string.lower(enemyData.name) == string.lower(nameStr) then
        return true
    end
    if includeLocalizedMatch and enemyData.id and nameStr and nameStr ~= "" then
        local localized = GetLocalizedCreatureName(enemyData.id)
        if localized and string.lower(localized) == string.lower(nameStr) then
            return true
        end
    end
    return false
end

-- mobOrName: mob table { name, npcId? } or legacy string name
-- includeLocalizedNameMatch: pass true when adding mobs or bulk "Fetch MDT" so non-English names resolve and npcId can backfill.
local function FetchMDTEnemyInfoForMob(mobOrName, includeLocalizedNameMatch)
    if not MDT or not MDT.dungeonEnemies then return nil end
    local tryLoc = includeLocalizedNameMatch and true or false
    for dungeonIndex, enemies in pairs(MDT.dungeonEnemies) do
        for enemyId, enemyData in pairs(enemies) do
            if MobMatchesMDTEnemy(mobOrName, enemyData, tryLoc) then
                if type(mobOrName) == "table" and enemyData.id and (not mobOrName.npcId or mobOrName.npcId == 0) then
                    mobOrName.npcId = enemyData.id
                end
                return BuildMDTInfoString(enemyData)
            end
        end
    end
    return nil
end

-- Function to safely Add a Mob
local function AddMobToZone(input, markerID, targetInstanceID, targetZoneName)
    local currentZoneName, instanceType, _, _, _, _, _, currentInstanceID = GetInstanceInfo()
    
    local instanceID = targetInstanceID or currentInstanceID
    local zoneName = targetZoneName or currentZoneName
    
    if not instanceID then
        ChatPrintErr(L.PRINT_CANNOT_DETERMINE_ZONE)
        return
    end

    -- Dynamically initialize new zones if they don't exist in the database yet
    if not MPlusMarkerDB[instanceID] then
        MPlusMarkerDB[instanceID] = { name = zoneName or string.format(L.ZONE_FALLBACK_PREFIX, instanceID), group = GROUP_NS, mobs = {} }
        ChatPrint(string.format(L.PRINT_INITIALIZED_ZONE, MPlusMarkerDB[instanceID].name))
    end

    if input == nil or input == "" then return end

    local mobName = input
    local id = tonumber(input)

    -- Translate Numeric ID to string name via Tooltip API
    if id then
        if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then
            ChatPrintErr(string.format(L.PRINT_COULD_NOT_RESOLVE_ID, id))
            return
        end
        local tooltipData = C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-"..id)
        if tooltipData and tooltipData.lines and tooltipData.lines[1] then
            local fetchedName = tooltipData.lines[1].leftText
            if fetchedName then
                local success, cleanName = pcall(function()
                    return string.gsub(string.gsub(fetchedName, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
                end)
                
                if success then
                    fetchedName = cleanName
                else
                    fetchedName = nil
                end
            end
            
            if fetchedName and fetchedName ~= "" and fetchedName ~= "Unknown" then
                mobName = fetchedName
            else
                ChatPrintErr(string.format(L.PRINT_COULD_NOT_RESOLVE_ID, id))
                return
            end
        else
            ChatPrintErr(string.format(L.PRINT_INVALID_MOB_ID, id))
            return
        end
    end

    if not MPlusMarkerDB[instanceID].mobs then MPlusMarkerDB[instanceID].mobs = {} end

    -- Prevent duplicates in the active list
    for _, mob in ipairs(MPlusMarkerDB[instanceID].mobs) do
        if id and mob.npcId and mob.npcId == id then
            ChatPrintWarn(L.PRINT_MOB_ALREADY_IN_LIST)
            return
        end
        if string.lower(mob.name) == string.lower(mobName) then
            ChatPrintWarn(L.PRINT_MOB_ALREADY_IN_LIST)
            return
        end
    end

    local newMobEntry = { name = mobName, marker = markerID or 8, backupMarker = 0 }
    if id then
        newMobEntry.npcId = id
    end

    -- Auto-fetch MDT info immediately upon adding the mob
    local autoFetchedMDT = FetchMDTEnemyInfoForMob(newMobEntry, true)
    if autoFetchedMDT then
        newMobEntry.mdtInfo = autoFetchedMDT
    end

    table.insert(MPlusMarkerDB[instanceID].mobs, newMobEntry)
    ChatPrint(string.format(L.PRINT_ADDED_MOB, "|cFF00FFFF" .. mobName .. "|r", MPlusMarkerDB[instanceID].name))
    
    UpdateMacroForZone()
    if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
end

-- Export & Import Logic
local function ExportPriorityList()
    if not MPlusMarkerDB then return "MPM:" end
    local parts = {}
    for id, data in pairs(MPlusMarkerDB) do
        local numId = tonumber(id)
        if numId and type(data) == "table" and type(data.mobs) == "table" and #data.mobs > 0 then
            local mobParts = {}
            for _, mob in ipairs(data.mobs) do
                local mName = mob.name or "Unknown"
                local mMarker = mob.marker or 8
                local bMarker = mob.backupMarker or 0
                local eNote = EncodeString(mob.note or "")
                local row = mName .. "," .. mMarker .. "," .. bMarker .. "," .. eNote
                if mob.npcId and mob.npcId > 0 then
                    row = row .. "," .. mob.npcId
                end
                table.insert(mobParts, row)
            end
            if #mobParts > 0 then
                table.insert(parts, numId .. ":" .. table.concat(mobParts, "|"))
            end
        end
    end
    return "MPM:" .. table.concat(parts, ";")
end

local function ImportPriorityList(encodedStr)
    if not encodedStr or encodedStr == "" then return false end
    
    -- Clean up the string to remove any hidden newlines/spaces from Discord/forums
    encodedStr = string.gsub(encodedStr, "[\r\n]", "")
    encodedStr = strtrim(encodedStr)
    
    local str = encodedStr
    if not string.match(str, "^MPM:") then
        -- Attempt to Base64 decode it if it doesn't have the plain MPM: header
        str = Base64Decode(encodedStr)
    end

    if not str or not string.match(str, "^MPM:") then
        ChatPrintErr(L.PRINT_INVALID_IMPORT)
        return false
    end
    str = string.sub(str, 5) -- strip "MPM:"
    
    for zoneStr in string.gmatch(str, "([^;]+)") do
        local idStr, mobsStr = string.match(zoneStr, "^(%d+):(.+)$")
        local id = tonumber(idStr)
        if id and mobsStr then
            if not MPlusMarkerDB[id] then
                MPlusMarkerDB[id] = {
                    name = (DefaultZones[id] and DefaultZones[id].name) or string.format(L.IMPORTED_ZONE_PREFIX, id),
                    group = (DefaultZones[id] and DefaultZones[id].group) or GROUP_NS,
                    mobs = {}
                }
            else
                MPlusMarkerDB[id].mobs = {} -- Clear old priorities for imported zone
            end
            
            for mobStr in string.gmatch(mobsStr, "([^|]+)") do
                local mobName, markerStr, backupStr, encodedNote, npcStr = string.match(mobStr, "^([^,]+),(%d+),(%d*),([^,]*),(%d+)$")
                local npcId
                if mobName and npcStr then
                    npcId = tonumber(npcStr)
                else
                    mobName, markerStr, backupStr, encodedNote = string.match(mobStr, "^([^,]+),(%d+),(%d*),?(.*)$")
                end
                local marker = tonumber(markerStr)
                local backupMarker = tonumber(backupStr) or 0
                local decodedNote = DecodeString(encodedNote or "")
                if mobName and marker then
                    local entry = { name = mobName, marker = marker, backupMarker = backupMarker, note = decodedNote }
                    if npcId and npcId > 0 then
                        entry.npcId = npcId
                    end
                    table.insert(MPlusMarkerDB[id].mobs, entry)
                end
            end
        end
    end
    
    RefreshAllSavedMobLocalizedNames()
    UpdateMacroForZone()
    if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
    ChatPrint(L.PRINT_IMPORT_SUCCESS)
    return true
end

-- Custom Secure Popup Frame to bypass Action Blocked errors
local RolePrompt = CreateFrame("Frame", "MPlusMarkerRolePrompt", UIParent, "BackdropTemplate")
RolePrompt:SetSize(360, 110)
RolePrompt:SetPoint("TOP", UIParent, "TOP", 0, -200)
RolePrompt:SetFrameStrata("DIALOG")
RolePrompt.backdropInfo = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}
RolePrompt:ApplyBackdrop()
RolePrompt:Hide()

RolePrompt.text = RolePrompt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
RolePrompt.text:SetPoint("TOP", 0, -25)
RolePrompt.text:SetText(L.ROLE_PROMPT_TEXT)
RolePrompt.text:SetWidth(340)
RolePrompt.text:SetWordWrap(true)
RolePrompt.text:SetJustifyH("CENTER")

-- The "Yes" Button is secretly a Secure Macro Button
RolePrompt.btnYes = CreateFrame("Button", nil, RolePrompt, "SecureActionButtonTemplate, UIPanelButtonTemplate")
RolePrompt.btnYes:SetSize(110, 25)
RolePrompt.btnYes:SetPoint("BOTTOMLEFT", 45, 20)
RolePrompt.btnYes:SetText(_G.YES or "Yes")
RolePrompt.btnYes:RegisterForClicks("AnyUp", "AnyDown")
RolePrompt.btnYes:SetAttribute("type", "macro")

-- Hide the prompt securely after click and provide feedback
RolePrompt.btnYes:SetScript("PostClick", function()
    ChatPrint(L.PRINT_ROLE_MARKS_APPLIED)
    if not InCombatLockdown() then MPlusMarkerRolePrompt:Hide() end
end)

RolePrompt.btnNo = CreateFrame("Button", nil, RolePrompt, "UIPanelButtonTemplate")
RolePrompt.btnNo:SetSize(110, 25)
RolePrompt.btnNo:SetPoint("BOTTOMRIGHT", -45, 20)
RolePrompt.btnNo:SetText(_G.NO or "No")
RolePrompt.btnNo:SetScript("OnClick", function()
    MPlusMarkerRolePrompt:Hide()
end)

FitPanelButtonWidth(RolePrompt.btnYes, 72, 22)
FitPanelButtonWidth(RolePrompt.btnNo, 72, 22)
do
    local pw = math.max(380, RolePrompt.text:GetStringWidth() + 40)
    RolePrompt:SetWidth(math.min(560, pw))
    local _, lineCount = string.gsub(L.ROLE_PROMPT_TEXT, "\n", "")
    RolePrompt:SetHeight(math.max(110, 78 + (lineCount + 1) * 16))
end

-- One-time splash: Blizzard /tm ~ non-overwriting marks + refresh macros button
local function HasSeenTmTildeSplash()
    return MPlusMarkerDB
        and MPlusMarkerDB.seenSplashes
        and MPlusMarkerDB.seenSplashes[SPLASH_TM_TILDE_ID]
end

local function MarkTmTildeSplashSeen()
    MPlusMarkerDB.seenSplashes = MPlusMarkerDB.seenSplashes or {}
    MPlusMarkerDB.seenSplashes[SPLASH_TM_TILDE_ID] = true
    pendingTmTildeSplash = false
end

local function TryShowTmTildeSplash()
    if HasSeenTmTildeSplash() then return end
    if InCombatLockdown() then
        pendingTmTildeSplash = true
        return
    end
    pendingTmTildeSplash = false
    if MPlusMarkerTmTildeSplash and not MPlusMarkerTmTildeSplash:IsShown() then
        MPlusMarkerTmTildeSplash:Show()
    end
end

local TmTildeSplash = CreateFrame("Frame", "MPlusMarkerTmTildeSplash", UIParent, "BackdropTemplate")
TmTildeSplash:SetSize(440, 200)
TmTildeSplash:SetPoint("TOP", UIParent, "TOP", 0, -120)
TmTildeSplash:SetFrameStrata("FULLSCREEN_DIALOG")
TmTildeSplash:EnableMouse(true)
TmTildeSplash:SetMovable(true)
TmTildeSplash:RegisterForDrag("LeftButton")
TmTildeSplash:SetScript("OnDragStart", TmTildeSplash.StartMoving)
TmTildeSplash:SetScript("OnDragStop", TmTildeSplash.StopMovingOrSizing)
TmTildeSplash.backdropInfo = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}
TmTildeSplash:ApplyBackdrop()
TmTildeSplash:Hide()

TmTildeSplash.title = TmTildeSplash:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
TmTildeSplash.title:SetPoint("TOP", 0, -20)
TmTildeSplash.title:SetText(L.SPLASH_TM_TILDE_TITLE)

TmTildeSplash.text = TmTildeSplash:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
TmTildeSplash.text:SetPoint("TOP", TmTildeSplash.title, "BOTTOM", 0, -12)
TmTildeSplash.text:SetWidth(400)
TmTildeSplash.text:SetWordWrap(true)
TmTildeSplash.text:SetJustifyH("CENTER")
TmTildeSplash.text:SetText(L.SPLASH_TM_TILDE_BODY)

TmTildeSplash.btnUpdate = CreateFrame("Button", nil, TmTildeSplash, "UIPanelButtonTemplate")
TmTildeSplash.btnUpdate:SetHeight(28)
TmTildeSplash.btnUpdate:SetPoint("BOTTOM", TmTildeSplash, "BOTTOM", -70, 18)
TmTildeSplash.btnUpdate:SetText(L.BTN_SPLASH_UPDATE_MACROS)
TmTildeSplash.btnUpdate:SetScript("OnClick", function()
    MarkTmTildeSplashSeen()
    UpdateMacroForZone()
    ChatPrint(L.PRINT_SPLASH_MACROS_UPDATED)
    TmTildeSplash:Hide()
end)

TmTildeSplash.btnLater = CreateFrame("Button", nil, TmTildeSplash, "UIPanelButtonTemplate")
TmTildeSplash.btnLater:SetHeight(28)
TmTildeSplash.btnLater:SetPoint("BOTTOM", TmTildeSplash, "BOTTOM", 70, 18)
TmTildeSplash.btnLater:SetText(L.BTN_SPLASH_LATER)
TmTildeSplash.btnLater:SetScript("OnClick", function()
    MarkTmTildeSplashSeen()
    TmTildeSplash:Hide()
end)

FitPanelButtonWidth(TmTildeSplash.btnUpdate, 120, 24)
FitPanelButtonWidth(TmTildeSplash.btnLater, 90, 24)
do
    local textH = TmTildeSplash.text:GetStringHeight()
    local frameW = math.max(420, math.min(520, TmTildeSplash.text:GetStringWidth() + 48))
    local frameH = math.max(190, 88 + textH + TmTildeSplash.btnUpdate:GetHeight() + 28)
    TmTildeSplash:SetSize(frameW, frameH)
    TmTildeSplash.text:SetWidth(frameW - 40)
end

-- Custom Multi-line Import/Export Frame
local IEFrame = CreateFrame("Frame", "MPlusMarkerIEFrame", UIParent, "BasicFrameTemplateWithInset")
IEFrame:SetSize(400, 300)
IEFrame:SetPoint("CENTER")
IEFrame:Hide()
IEFrame:SetFrameStrata("DIALOG")
IEFrame:SetMovable(true)
IEFrame:EnableMouse(true)
IEFrame:RegisterForDrag("LeftButton")
IEFrame:SetScript("OnDragStart", IEFrame.StartMoving)
IEFrame:SetScript("OnDragStop", IEFrame.StopMovingOrSizing)

IEFrame.title = IEFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
IEFrame.title:SetPoint("TOP", 0, -5)
IEFrame.title:SetText(L.IE_TITLE)

local ieScrollFrame = CreateFrame("ScrollFrame", nil, IEFrame, "UIPanelScrollFrameTemplate")
ieScrollFrame:SetPoint("TOPLEFT", 15, -35)
ieScrollFrame:SetPoint("BOTTOMRIGHT", -35, 45)

local ieEditBox = CreateFrame("EditBox", nil, ieScrollFrame)
ieEditBox:SetMultiLine(true)
ieEditBox:SetFontObject("ChatFontNormal")
ieEditBox:SetWidth(335)
ieEditBox:SetAutoFocus(true)
ieEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
ieScrollFrame:SetScrollChild(ieEditBox)

local btnImportAction = CreateFrame("Button", nil, IEFrame, "UIPanelButtonTemplate")
btnImportAction:SetSize(100, 25)
btnImportAction:SetPoint("BOTTOMLEFT", 15, 10)
btnImportAction:SetText(L.BTN_IMPORT)
btnImportAction:SetScript("OnClick", function()
    local text = ieEditBox:GetText()
    if text and text ~= "" then
        ImportPriorityList(text)
    end
    IEFrame:Hide()
end)

local btnCloseIE = CreateFrame("Button", nil, IEFrame, "UIPanelButtonTemplate")
btnCloseIE:SetSize(100, 25)
btnCloseIE:SetPoint("BOTTOMRIGHT", -15, 10)
btnCloseIE:SetText(L.BTN_CLOSE)
btnCloseIE:SetScript("OnClick", function() IEFrame:Hide() end)

FitPanelButtonWidth(btnImportAction, 90, 22)
FitPanelButtonWidth(btnCloseIE, 90, 22)
IEFrame:SetWidth(math.max(420, math.max(btnImportAction:GetWidth(), btnCloseIE:GetWidth()) + 280))
ieEditBox:SetWidth(IEFrame:GetWidth() - 65)

local lblHelpIE = IEFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lblHelpIE:SetPoint("BOTTOM", 0, 15)
lblHelpIE:SetWidth(IEFrame:GetWidth() - 40)
lblHelpIE:SetWordWrap(true)
lblHelpIE:SetJustifyH("CENTER")
lblHelpIE:SetText(L.IE_HELP)

-- Custom Multi-line Note Editor Frame
local NoteEditor = CreateFrame("Frame", "MPlusMarkerNoteEditor", UIParent, "BasicFrameTemplateWithInset")
NoteEditor:SetSize(350, 250)
NoteEditor:SetPoint("CENTER")
NoteEditor:Hide()
NoteEditor:SetFrameStrata("DIALOG")
NoteEditor:SetMovable(true)
NoteEditor:EnableMouse(true)
NoteEditor:RegisterForDrag("LeftButton")
NoteEditor:SetScript("OnDragStart", NoteEditor.StartMoving)
NoteEditor:SetScript("OnDragStop", NoteEditor.StopMovingOrSizing)

NoteEditor.title = NoteEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
NoteEditor.title:SetPoint("TOP", 0, -5)
NoteEditor.title:SetText(L.NOTE_TITLE)

local neScrollFrame = CreateFrame("ScrollFrame", nil, NoteEditor, "UIPanelScrollFrameTemplate")
neScrollFrame:SetPoint("TOPLEFT", 15, -35)
neScrollFrame:SetPoint("BOTTOMRIGHT", -35, 45)

local neEditBox = CreateFrame("EditBox", nil, neScrollFrame)
neEditBox:SetMultiLine(true)
neEditBox:SetFontObject("ChatFontNormal")
neEditBox:SetWidth(285)
neEditBox:SetAutoFocus(true)
neEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
neScrollFrame:SetScrollChild(neEditBox)
NoteEditor.editBox = neEditBox

local neBtnSave = CreateFrame("Button", nil, NoteEditor, "UIPanelButtonTemplate")
neBtnSave:SetSize(90, 25)
neBtnSave:SetText(L.BTN_SAVE)

local neBtnClear = CreateFrame("Button", nil, NoteEditor, "UIPanelButtonTemplate")
neBtnClear:SetSize(100, 25)
neBtnClear:SetText(L.BTN_CLEAR_NOTE)

local neBtnCancel = CreateFrame("Button", nil, NoteEditor, "UIPanelButtonTemplate")
neBtnCancel:SetSize(90, 25)
neBtnCancel:SetText(L.BTN_CANCEL)
neBtnCancel:SetScript("OnClick", function() NoteEditor:Hide() end)

FitPanelButtonWidth(neBtnSave, 72, 18)
FitPanelButtonWidth(neBtnClear, 88, 18)
FitPanelButtonWidth(neBtnCancel, 72, 18)
do
    local pad = 10
    local total = neBtnSave:GetWidth() + neBtnClear:GetWidth() + neBtnCancel:GetWidth() + pad * 2
    local nw = math.max(380, total + 48)
    NoteEditor:SetWidth(nw)
    neEditBox:SetWidth(nw - 65)
    local start = (nw - total) / 2
    neBtnSave:ClearAllPoints()
    neBtnClear:ClearAllPoints()
    neBtnCancel:ClearAllPoints()
    neBtnSave:SetPoint("BOTTOMLEFT", NoteEditor, "BOTTOMLEFT", start, 10)
    neBtnClear:SetPoint("LEFT", neBtnSave, "RIGHT", pad, 0)
    neBtnCancel:SetPoint("LEFT", neBtnClear, "RIGHT", pad, 0)
end

local currentEditingMob = nil
neBtnSave:SetScript("OnClick", function()
    if currentEditingMob then
        currentEditingMob.note = NoteEditor.editBox:GetText()
        if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
    end
    NoteEditor:Hide()
end)

neBtnClear:SetScript("OnClick", function()
    if currentEditingMob then
        currentEditingMob.note = ""
        if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
    end
    NoteEditor:Hide()
end)

local function OpenNoteEditor(mob)
    currentEditingMob = mob
    NoteEditor.title:SetText(string.format(L.NOTE_TITLE_WITH_NAME, GetMobTargetName(mob)))
    NoteEditor.editBox:SetText(mob.note or "")
    NoteEditor:Show()
end


-- Builds and Refreshes the Settings Window
local function BuildGUI()
    local GUI = CreateFrame("Frame", "MPlusMarkerConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    GUI:SetSize(520, 550)
    GUI:SetPoint("CENTER")
    GUI:Hide()
    GUI:SetMovable(true)
    GUI:EnableMouse(true)
    GUI:RegisterForDrag("LeftButton")
    GUI:SetScript("OnDragStart", GUI.StartMoving)
    GUI:SetScript("OnDragStop", GUI.StopMovingOrSizing)
    GUI:SetScript("OnHide", function()
        UpdateFocusBarVisibility()
    end)
    
    GUI.title = GUI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GUI.title:SetPoint("TOP", GUI, "TOP", 0, -5)
    GUI.title:SetText(L.GUI_TITLE)

    -- Tab System
    GUI.activeTab = "mobs"

    local tabTarget = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    tabTarget:SetSize(120, 22)
    tabTarget:SetPoint("TOPLEFT", 15, -30)
    tabTarget:SetText(L.TAB_TARGET)

    local tabFocus = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    tabFocus:SetSize(120, 22)
    tabFocus:SetPoint("LEFT", tabTarget, "RIGHT", 5, 0)
    tabFocus:SetText(L.TAB_FOCUS)

    -- Generate Macros Button (Top Right)
    local btnGenerate = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    btnGenerate:SetSize(120, 22)
    btnGenerate:SetPoint("TOPRIGHT", -15, -30)
    btnGenerate:SetText(L.BTN_GENERATE_MACROS)
    btnGenerate:SetScript("OnClick", function()
        UpdateMacroForZone()
        ChatPrint(L.PRINT_MACROS_GENERATED)
    end)
    btnGenerate:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_TOP", L.TOOLTIP_GENERATE_MACROS) end)
    btnGenerate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Fetch MDT Info Button
    local btnFetchMDT = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    btnFetchMDT:SetSize(120, 22)
    btnFetchMDT:SetPoint("TOP", btnGenerate, "BOTTOM", 0, -5)
    btnFetchMDT:SetText(L.BTN_FETCH_MDT)
    btnFetchMDT:SetScript("OnClick", function()
        if not MDT then
            ChatPrintErr(L.PRINT_MDT_NOT_LOADED)
            return
        end
        local count = 0
        for id, data in pairs(MPlusMarkerDB) do
            if type(data) == "table" and data.mobs then
                for _, mob in ipairs(data.mobs) do
                    local info = FetchMDTEnemyInfoForMob(mob, true)
                    if info then
                        mob.mdtInfo = info
                        count = count + 1
                    end
                end
            end
        end
        RefreshAllSavedMobLocalizedNames()
        ChatPrint(string.format(L.PRINT_MDT_CACHED, count))
        GUI.Refresh()
    end)
    btnFetchMDT:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_TOP", L.TOOLTIP_FETCH_MDT) end)
    btnFetchMDT:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Add Top Controls (Zone Dropdown, Input Box & Button)
    local addLabel = GUI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", 15, -60)
    addLabel:SetText(L.LABEL_ZONE_ADD_MOB)

    GUI.selectedTargetZoneID = nil

    local zoneDropdown = CreateFrame("DropdownButton", nil, GUI, "WowStyle1DropdownTemplate")
    zoneDropdown:SetPoint("TOPLEFT", 15, -80)
    zoneDropdown:SetWidth(150)
    zoneDropdown:SetupMenu(function(dropdown, rootDescription)
        rootDescription:CreateRadio(L.DROPDOWN_CURRENT_ZONE,
            function() return GUI.selectedTargetZoneID == nil end,
            function() GUI.selectedTargetZoneID = nil end
        )
        
        -- Gather and sort zones alphabetically
        local sortedZones = {}
        for id, data in pairs(MPlusMarkerDB) do
            if type(data) == "table" and data.name then
                table.insert(sortedZones, {id = id, name = data.name})
            end
        end
        table.sort(sortedZones, function(a, b) return a.name < b.name end)
        
        for _, z in ipairs(sortedZones) do
            rootDescription:CreateRadio(z.name,
                function() return GUI.selectedTargetZoneID == z.id end,
                function() GUI.selectedTargetZoneID = z.id end
            )
        end
    end)

    local inputBox = CreateFrame("EditBox", nil, GUI, "InputBoxTemplate")
    inputBox:SetSize(130, 20)
    inputBox:SetPoint("LEFT", zoneDropdown, "RIGHT", 15, 0)
    inputBox:SetAutoFocus(false)
    inputBox:SetScript("OnEnterPressed", function(self)
        local tName = GUI.selectedTargetZoneID and MPlusMarkerDB[GUI.selectedTargetZoneID].name or nil
        AddMobToZone(self:GetText(), 8, GUI.selectedTargetZoneID, tName)
        self:SetText("")
        self:ClearFocus()
    end)

    local btnAddTyped = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    btnAddTyped:SetSize(80, 22)
    btnAddTyped:SetPoint("LEFT", inputBox, "RIGHT", 5, 0)
    btnAddTyped:SetText(L.BTN_ADD_MOB)
    btnAddTyped:SetScript("OnClick", function()
        local tName = GUI.selectedTargetZoneID and MPlusMarkerDB[GUI.selectedTargetZoneID].name or nil
        AddMobToZone(inputBox:GetText(), 8, GUI.selectedTargetZoneID, tName)
        inputBox:SetText("")
        inputBox:ClearFocus()
    end)

    local function UpdateTabs()
        if GUI.activeTab == "mobs" then
            tabTarget:LockHighlight()
            tabFocus:UnlockHighlight()
            addLabel:Show()
            zoneDropdown:Show()
            inputBox:Show()
            btnAddTyped:Show()
        else
            tabTarget:UnlockHighlight()
            tabFocus:LockHighlight()
            addLabel:Hide()
            zoneDropdown:Hide()
            inputBox:Hide()
            btnAddTyped:Hide()
        end
    end
    UpdateTabs()

    tabTarget:SetScript("OnClick", function()
        GUI.activeTab = "mobs"
        UpdateTabs()
        UpdateFocusBarVisibility()
        GUI.Refresh()
    end)

    tabFocus:SetScript("OnClick", function()
        GUI.activeTab = "focus"
        UpdateTabs()
        UpdateFocusBarVisibility()
        GUI.Refresh()
    end)

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, GUI, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -115)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    -- Stream Plug Footer
    local plugText = GUI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plugText:SetPoint("BOTTOMLEFT", GUI, "BOTTOMLEFT", 15, 15)
    plugText:SetJustifyH("LEFT")
    plugText:SetText(L.PLUG_FOOTER)

    -- Import / Export Buttons
    local btnExport = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    btnExport:SetSize(70, 22)
    btnExport:SetPoint("BOTTOMRIGHT", -15, 15)
    btnExport:SetText(L.BTN_EXPORT)
    btnExport:SetScript("OnClick", function()
        IEFrame.title:SetText(L.IE_TITLE_EXPORT)
        ieEditBox:SetText(Base64Encode(ExportPriorityList()))
        ieEditBox:HighlightText()
        ieEditBox:SetFocus()
        btnImportAction:Disable()
        IEFrame:Show()
    end)

    local btnImport = CreateFrame("Button", nil, GUI, "UIPanelButtonTemplate")
    btnImport:SetSize(70, 22)
    btnImport:SetPoint("RIGHT", btnExport, "LEFT", -5, 0)
    btnImport:SetText(L.BTN_IMPORT)
    btnImport:SetScript("OnClick", function()
        IEFrame.title:SetText(L.IE_TITLE_IMPORT)
        ieEditBox:SetText("")
        ieEditBox:SetFocus()
        btnImportAction:Enable()
        IEFrame:Show()
    end)

    -- Fit top/bottom buttons to localized labels; widen frame so tabs and right column do not overlap
    FitPanelButtonWidth(tabTarget, 96, 22)
    FitPanelButtonWidth(tabFocus, 96, 22)
    FitPanelButtonWidth(btnGenerate, 96, 22)
    FitPanelButtonWidth(btnFetchMDT, 96, 22)
    FitPanelButtonWidth(btnAddTyped, 68, 18)
    FitPanelButtonWidth(btnExport, 56, 14)
    FitPanelButtonWidth(btnImport, 56, 14)
    do
        local topW = 15 + tabTarget:GetWidth() + 5 + tabFocus:GetWidth() + 20 + math.max(btnGenerate:GetWidth(), btnFetchMDT:GetWidth()) + 15
        local bottomW = 15 + btnImport:GetWidth() + 5 + btnExport:GetWidth() + 15
        GUI:SetWidth(math.max(500, math.max(topW, bottomW)))
    end
    addLabel:SetWidth(GUI:GetWidth() - 30)
    addLabel:SetWordWrap(true)
    addLabel:SetJustifyH("LEFT")
    plugText:SetWidth(GUI:GetWidth() - 30)
    plugText:SetWordWrap(true)

    GUI.Refresh = function()
        if scrollFrame.content then scrollFrame.content:Hide() end

        local contentW = math.max(360, GUI:GetWidth() - 50)
        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(contentW, 100)
        scrollFrame:SetScrollChild(content)
        scrollFrame.content = content

        local yOffset = -10
        
        -- Initialize collapse state tables if they dont exist
        GUI.collapsedState = GUI.collapsedState or {}
        GUI.collapsedGroupState = GUI.collapsedGroupState or {}
        
        if GUI.activeTab == "mobs" then
            local backupModLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            backupModLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
            backupModLabel:SetText(L.LABEL_BACKUP_MARK_MODIFIER)

            local backupModDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
            backupModDropdown:SetPoint("LEFT", backupModLabel, "RIGHT", 8, 0)
            backupModDropdown:SetWidth(100)
            backupModDropdown:SetupMenu(function(dropdown, rootDescription)
                for _, mod in ipairs(MARK_MODIFIERS) do
                    rootDescription:CreateRadio(GetMarkModifierLabel(mod),
                        function() return GetBackupMarkModifierTag() == mod end,
                        function()
                            MPlusMarkerDB.backupMarkModifier = mod
                            UpdateMacroForZone()
                            if dropdown.SetDefaultText then
                                dropdown:SetDefaultText(GetMarkModifierLabel(mod))
                            end
                        end
                    )
                end
            end)
            if backupModDropdown.SetDefaultText then
                backupModDropdown:SetDefaultText(GetMarkModifierLabel(GetBackupMarkModifierTag()))
            end
            backupModDropdown:SetScript("OnEnter", function(self)
                TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_BACKUP_MARK_MODIFIER)
            end)
            backupModDropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)

            yOffset = yOffset - 32

            -- Group the zones based on their group tag
            local groupedZones = {}
            -- Ensure Non Seasonal Instances is always populated as a group
            groupedZones[GROUP_NS] = {}
            
            for id, data in pairs(MPlusMarkerDB) do
                if type(data) == "table" and data.name then
                    local gName = data.group or GROUP_NS
                    if not groupedZones[gName] then groupedZones[gName] = {} end
                    table.insert(groupedZones[gName], {id = id, name = data.name, activeList = data.mobs or {}})
                end
            end
            
            -- Sort group names: Midnight S1 first, M0 second, non-seasonal last
            local sortedGroups = {}
            for gName in pairs(groupedZones) do table.insert(sortedGroups, gName) end
            local gS1, gM0, gNS = GROUP_S1, GROUP_M0, GROUP_NS
            table.sort(sortedGroups, function(a, b)
                if a == gS1 and b ~= gS1 then return true end
                if b == gS1 and a ~= gS1 then return false end
                if a == gM0 and b ~= gM0 then return true end
                if b == gM0 and a ~= gM0 then return false end
                if a == gNS and b ~= gNS then return false end
                if b == gNS and a ~= gNS then return true end
                return a < b
            end)

            for _, gName in ipairs(sortedGroups) do
                local isGroupCollapsed = GUI.collapsedGroupState[gName]

                -- Make the Group Header a Clickable Button
                local groupHeaderBtn = CreateFrame("Button", nil, content)
                groupHeaderBtn:SetSize(math.max(220, contentW - 20), 20)
                groupHeaderBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)

                local groupHeader = groupHeaderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                groupHeader:SetPoint("LEFT", groupHeaderBtn, "LEFT", 0, 0)
                groupHeader:SetTextColor(0.6, 0.2, 0.8) -- Void purple color
                groupHeader:SetText((isGroupCollapsed and "[+] " or "[-] ") .. GetGroupDisplayName(gName))

                -- Click to Expand/Collapse Group
                groupHeaderBtn:SetScript("OnClick", function()
                    GUI.collapsedGroupState[gName] = not isGroupCollapsed
                    GUI.Refresh()
                end)
                
                -- Hover Highlight Effect for Group
                groupHeaderBtn:SetScript("OnEnter", function(self) groupHeader:SetTextColor(0.8, 0.4, 1.0) end) -- Lighter Void purple on hover
                groupHeaderBtn:SetScript("OnLeave", function(self) groupHeader:SetTextColor(0.6, 0.2, 0.8) end)

                yOffset = yOffset - 25

                if not isGroupCollapsed then
                    -- Show helpful instructional note directly under "Non Seasonal Instances"
                    if gName == GROUP_NS then
                        local noteText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                        noteText:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset + 3)
                        noteText:SetText(L.NOTE_NON_SEASONAL)
                        yOffset = yOffset - 20
                    end

                    local sortedZones = groupedZones[gName]
                    table.sort(sortedZones, function(a, b) return a.name < b.name end)

                    for _, zData in ipairs(sortedZones) do
                        local isCollapsed = GUI.collapsedState[zData.id]

                        -- Make the Dungeon Header a Clickable Button, indented beneath the Group
                        local headerBtn = CreateFrame("Button", nil, content)
                        headerBtn:SetSize(math.max(200, contentW - 60), 20)
                        headerBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)

                        local header = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        header:SetPoint("LEFT", headerBtn, "LEFT", 0, 0)
                        header:SetText((isCollapsed and "[+] " or "[-] ") .. zData.name)

                        -- Click to Expand/Collapse
                        headerBtn:SetScript("OnClick", function()
                            GUI.collapsedState[zData.id] = not isCollapsed
                            GUI.Refresh()
                        end)
                        
                        -- Hover Highlight Effect
                        headerBtn:SetScript("OnEnter", function(self) header:SetTextColor(1, 1, 1) end)
                        headerBtn:SetScript("OnLeave", function(self) header:SetTextColor(1, 0.82, 0) end)
                        
                        -- Provide a delete option for non-default Custom/Imported Additions
                        if not DefaultZones[zData.id] then
                            local btnDelZone = CreateFrame("Button", nil, content, "UIPanelCloseButton")
                            btnDelZone:SetSize(24, 24)
                            btnDelZone:SetPoint("TOPLEFT", content, "TOPLEFT", math.max(55, contentW - 32), yOffset + 2)
                            btnDelZone:SetScript("OnClick", function()
                                MPlusMarkerDB[zData.id] = nil
                                UpdateMacroForZone()
                                GUI.Refresh()
                            end)
                            btnDelZone:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_LEFT", L.BTN_DELETE_LOCATION) end)
                            btnDelZone:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        end

                        yOffset = yOffset - 22

                        -- Only render the mobs if the header is expanded
                        if not isCollapsed then
                            local listToRender = zData.activeList

                            if #listToRender == 0 then
                                local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                                emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 30, yOffset)
                                emptyText:SetText(L.EMPTY_PRIORITY_LIST)
                                yOffset = yOffset - 25
                            else
                                local iconColX = math.max(200, math.min(contentW - 52, 310))
                                local mobNameW = math.max(80, iconColX - 105)
                                for index, mob in ipairs(listToRender) do
                                    -- Delete Button [X]
                                    local btnDel = CreateFrame("Button", nil, content, "UIPanelCloseButton")
                                    btnDel:SetSize(24, 24)
                                    btnDel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset + 5)
                                    btnDel:SetScript("OnClick", function()
                                        table.remove(listToRender, index)
                                        UpdateMacroForZone()
                                        GUI.Refresh()
                                    end)
                                    btnDel:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_DELETE_MOB) end)
                                    btnDel:SetScript("OnLeave", function() GameTooltip:Hide() end)

                                    -- Up Button [^]
                                    local btnUp = CreateFrame("Button", nil, content)
                                    btnUp:SetSize(32, 32)
                                    btnUp:SetPoint("LEFT", btnDel, "RIGHT", -2, 0)
                                    btnUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
                                    btnUp:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
                                    btnUp:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
                                    if index == 1 then btnUp:Disable() end
                                    btnUp:SetScript("OnClick", function()
                                        listToRender[index], listToRender[index-1] = listToRender[index-1], listToRender[index]
                                        UpdateMacroForZone()
                                        GUI.Refresh()
                                    end)
                                    btnUp:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_MOVE_UP) end)
                                    btnUp:SetScript("OnLeave", function() GameTooltip:Hide() end)

                                    -- Down Button [v]
                                    local btnDown = CreateFrame("Button", nil, content)
                                    btnDown:SetSize(32, 32)
                                    btnDown:SetPoint("LEFT", btnUp, "RIGHT", -2, 0)
                                    btnDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                                    btnDown:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
                                    btnDown:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
                                    if index == #listToRender then btnDown:Disable() end
                                    btnDown:SetScript("OnClick", function()
                                        listToRender[index], listToRender[index+1] = listToRender[index+1], listToRender[index]
                                        UpdateMacroForZone()
                                        GUI.Refresh()
                                    end)
                                    btnDown:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_MOVE_DOWN) end)
                                    btnDown:SetScript("OnLeave", function() GameTooltip:Hide() end)

                                    -- Mob Name Button (for Tooltips & Editing)
                                    local mobNameBtn = CreateFrame("Button", nil, content)
                                    mobNameBtn:SetSize(mobNameW, 20)
                                    mobNameBtn:SetPoint("LEFT", btnDown, "RIGHT", 5, 0)
                                    mobNameBtn:RegisterForClicks("AnyUp")

                                    local mobNameText = mobNameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                                    mobNameText:SetPoint("LEFT", mobNameBtn, "LEFT", 0, 0)
                                    mobNameText:SetWidth(mobNameW) -- Shrink/grow with panel width for long mob names
                                    mobNameText:SetWordWrap(false)
                                    mobNameText:SetJustifyH("LEFT")
                                    mobNameText:SetText(GetMobTargetName(mob))

                                    -- Prefer cached MDT text; live lookup only with English/name-id match (no per-enemy locale scan every hover)
                                    local mdtInfo = mob.mdtInfo or FetchMDTEnemyInfoForMob(mob, false)

                                    if mob.note and mob.note ~= "" then
                                        mobNameText:SetTextColor(0, 1, 1) -- Cyan to indicate custom info exists
                                    else
                                        mobNameText:SetTextColor(1, 1, 1)
                                    end

                                    mobNameBtn:SetScript("OnEnter", function(self)
                                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                        GameTooltip:ClearLines()
                                        GameTooltip:AddLine(GetMobTargetName(mob), 1, 0.82, 0, true)
                                        
                                        if mdtInfo then
                                            GameTooltip:AddLine(L.MDT_INFO_HEADER, 0.5, 0.8, 1)
                                            GameTooltip:AddLine(mdtInfo, 1, 1, 1, true)
                                            if mob.note and mob.note ~= "" then
                                                GameTooltip:AddLine(" ", 1, 1, 1)
                                                GameTooltip:AddLine(L.MDT_CUSTOM_NOTE_HEADER, 0.5, 1, 0.5)
                                                GameTooltip:AddLine(mob.note, 1, 1, 1, true)
                                            end
                                        elseif mob.note and mob.note ~= "" then
                                            GameTooltip:AddLine(mob.note, 1, 1, 1, true)
                                        else
                                            GameTooltip:AddLine(L.MDT_NO_ABILITIES, 0.5, 0.5, 0.5, true)
                                        end

                                        GameTooltip:AddLine(" ", 1, 1, 1) -- Empty line
                                        GameTooltip:AddLine(L.MDT_SHIFT_EDIT_HINT, 0.2, 1, 0.2, true)
                                        GameTooltip:Show()
                                    end)
                                    mobNameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                                    mobNameBtn:SetScript("OnClick", function()
                                        if IsShiftKeyDown() then
                                            OpenNoteEditor(mob)
                                        end
                                    end)

                                    -- Primary Marker Cycle Button
                                    local btnIcon = CreateFrame("Button", nil, content)
                                    btnIcon:SetSize(20, 20)
                                    btnIcon:SetPoint("TOPLEFT", content, "TOPLEFT", iconColX, yOffset)
                                    
                                    -- Backup Marker Cycle Button (Hold Shift to Apply)
                                    local btnBackupIcon = CreateFrame("Button", nil, content)
                                    btnBackupIcon:SetSize(16, 16)
                                    btnBackupIcon:SetPoint("LEFT", btnIcon, "RIGHT", 8, 0)
                                    
                                    local function UpdateIcons()
                                        btnIcon:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mob.marker)
                                        
                                        if not mob.backupMarker or mob.backupMarker == 0 then
                                            btnBackupIcon:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                                            btnBackupIcon:SetAlpha(0.4)
                                        else
                                            btnBackupIcon:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mob.backupMarker)
                                            btnBackupIcon:SetAlpha(1.0)
                                        end
                                    end

                                    -- Primary Marker Cycling Logic
                                    btnIcon:SetScript("OnClick", function()
                                        local nextMarker = mob.marker
                                        for i = 1, 8 do
                                            nextMarker = nextMarker + 1
                                            if nextMarker > 8 then nextMarker = 1 end
                                            
                                            if nextMarker ~= (mob.backupMarker or 0) then
                                                local isUsed = false
                                                for checkIndex, checkMob in ipairs(listToRender) do
                                                    if checkIndex ~= index and (checkMob.marker == nextMarker or checkMob.backupMarker == nextMarker) then
                                                        isUsed = true
                                                        break
                                                    end
                                                end
                                                if not isUsed then break end
                                            end
                                        end
                                        mob.marker = nextMarker
                                        UpdateIcons()
                                        UpdateMacroForZone()
                                    end)
                                    btnIcon:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_LEFT", L.TOOLTIP_PRIMARY_MARKER) end)
                                    btnIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                                    
                                    -- Backup Marker Cycling Logic
                                    btnBackupIcon:SetScript("OnClick", function()
                                        local nextMarker = (mob.backupMarker or 0)
                                        for i = 1, 9 do
                                            nextMarker = nextMarker + 1
                                            if nextMarker > 8 then nextMarker = 0 end
                                            
                                            if nextMarker == 0 then break end
                                            
                                            if nextMarker ~= mob.marker then
                                                local isUsed = false
                                                for checkIndex, checkMob in ipairs(listToRender) do
                                                    if checkIndex ~= index and (checkMob.marker == nextMarker or checkMob.backupMarker == nextMarker) then
                                                        isUsed = true
                                                        break
                                                    end
                                                end
                                                if not isUsed then break end
                                            end
                                        end
                                        mob.backupMarker = nextMarker
                                        UpdateIcons()
                                        UpdateMacroForZone()
                                    end)
                                    btnBackupIcon:SetScript("OnEnter", function(self)
                                        TooltipShowWrapped(self, "ANCHOR_LEFT", string.format(L.TOOLTIP_BACKUP_MARKER, GetMarkModifierLabel(GetBackupMarkModifierTag())))
                                    end)
                                    btnBackupIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

                                    UpdateIcons()
                                    
                                    yOffset = yOffset - 25
                                end
                            end
                        end -- Closes the 'if not isCollapsed then' check
                        
                        -- Add bottom padding after a dungeon list, or a smaller gap if collapsed
                        if not isCollapsed then
                            yOffset = yOffset - 15
                        else
                            yOffset = yOffset - 5
                        end
                    end
                end -- Closes the 'if not isGroupCollapsed then' check
                
                -- Extra padding after completing a full group
                yOffset = yOffset - 10
            end
        else
            -- Render Global Focus Icon Picker Tab (y tracks distance down from content top; negative = below)
            local y = -20
            local desc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            desc:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
            desc:SetText(L.FOCUS_TAB_DESC)
            desc:SetWidth(contentW - 60)
            desc:SetWordWrap(true)
            desc:SetJustifyH("LEFT")
            y = y - desc:GetStringHeight() - 8

            local btnIcon = CreateFrame("Button", nil, content)
            btnIcon:SetSize(32, 32)
            btnIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)

            local function UpdateFocusIcon()
                btnIcon:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (MPlusMarkerDB.globalFocusMarker or 4))
            end

            btnIcon:SetScript("OnClick", function()
                local next = (MPlusMarkerDB.globalFocusMarker or 4) + 1
                if next > 8 then next = 1 end
                SetGlobalFocusMarker(next)
            end)
            btnIcon:SetScript("OnEnter", function(self) TooltipShowWrapped(self, "ANCHOR_LEFT", L.TOOLTIP_CYCLE_FOCUS_ICON) end)
            btnIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            UpdateFocusIcon()

            y = y - 32 - 12

            local clearModLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            clearModLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            clearModLabel:SetText(L.LABEL_FOCUS_CLEAR_MARK_MODIFIER)

            local clearModDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
            clearModDropdown:SetPoint("LEFT", clearModLabel, "RIGHT", 8, 0)
            clearModDropdown:SetWidth(100)
            clearModDropdown:SetupMenu(function(dropdown, rootDescription)
                for _, mod in ipairs(MARK_MODIFIERS) do
                    rootDescription:CreateRadio(GetMarkModifierLabel(mod),
                        function() return GetFocusClearMarkModifierTag() == mod end,
                        function()
                            MPlusMarkerDB.focusClearMarkModifier = mod
                            UpdateMacroForZone()
                            if dropdown.SetDefaultText then
                                dropdown:SetDefaultText(GetMarkModifierLabel(mod))
                            end
                        end
                    )
                end
            end)
            if clearModDropdown.SetDefaultText then
                clearModDropdown:SetDefaultText(GetMarkModifierLabel(GetFocusClearMarkModifierTag()))
            end
            clearModDropdown:SetScript("OnEnter", function(self)
                TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_FOCUS_CLEAR_MARK_MODIFIER)
            end)
            clearModDropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)

            y = y - 32 - 4

            local barDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            barDesc:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            barDesc:SetWidth(contentW - 30)
            barDesc:SetWordWrap(true)
            barDesc:SetJustifyH("LEFT")
            barDesc:SetText(L.FOCUS_BAR_DESC)
            y = y - barDesc:GetStringHeight() - 12

            local chkFocusBar = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            chkFocusBar:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            chkFocusBar:SetSize(26, 26)
            chkFocusBar:SetChecked(MPlusMarkerDB.focusBarEnabled ~= false)

            local chkFocusBarLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            chkFocusBarLabel:SetPoint("TOPLEFT", chkFocusBar, "TOPRIGHT", 5, -4)
            chkFocusBarLabel:SetWidth(math.max(80, contentW - 70))
            chkFocusBarLabel:SetWordWrap(true)
            chkFocusBarLabel:SetJustifyH("LEFT")
            chkFocusBarLabel:SetText(L.CHK_FOCUS_BAR_INSTANCE)

            chkFocusBar:SetScript("OnClick", function(self)
                MPlusMarkerDB.focusBarEnabled = self:GetChecked()
                UpdateFocusBarVisibility()
            end)

            y = y - math.max(28, chkFocusBarLabel:GetStringHeight() + 8) - 8

            local btnOrient = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            btnOrient:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            btnOrient:SetHeight(24)
            local function UpdateFocusBarOrientButton()
                local o = MPlusMarkerDB.focusBarOrientation or "HORIZONTAL"
                btnOrient:SetText(o == "VERTICAL" and L.FOCUS_BAR_ORIENT_VERTICAL or L.FOCUS_BAR_ORIENT_HORIZONTAL)
                FitPanelButtonWidth(btnOrient, 160, 22)
            end
            btnOrient:SetScript("OnClick", function()
                local o = MPlusMarkerDB.focusBarOrientation or "HORIZONTAL"
                MPlusMarkerDB.focusBarOrientation = (o == "HORIZONTAL") and "VERTICAL" or "HORIZONTAL"
                UpdateFocusBarLayout()
                UpdateFocusBarOrientButton()
            end)
            btnOrient:SetScript("OnEnter", function(self)
                TooltipShowWrapped(self, "ANCHOR_RIGHT", L.TOOLTIP_FOCUS_BAR_ORIENT)
            end)
            btnOrient:SetScript("OnLeave", function() GameTooltip:Hide() end)
            UpdateFocusBarOrientButton()

            y = y - btnOrient:GetHeight() - 10

            -- Kick Spell Input
            local lblKick = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lblKick:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            lblKick:SetWidth(contentW - 30)
            lblKick:SetWordWrap(true)
            lblKick:SetJustifyH("LEFT")
            lblKick:SetText(L.LABEL_CUSTOM_KICK)
            y = y - lblKick:GetStringHeight() - 10

            local kickInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
            kickInput:SetSize(math.min(220, math.max(120, contentW - 50)), 20)
            kickInput:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
            kickInput:SetAutoFocus(false)
            kickInput:SetText(MPlusMarkerDB.kickSpell or "")

            kickInput:SetScript("OnEditFocusLost", function(self)
                MPlusMarkerDB.kickSpell = self:GetText()
                UpdateMacroForZone()
            end)
            kickInput:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            y = y - 20 - 6
            local defaultSpell = GetKickDefaultDisplayText()
            local kickDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            kickDesc:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            kickDesc:SetWidth(contentW - 25)
            kickDesc:SetWordWrap(true)
            kickDesc:SetJustifyH("LEFT")
            if not defaultSpell or strtrim(defaultSpell or "") == "" then
                kickDesc:SetText(L.KICK_DESC_NONE_SPEC)
            else
                kickDesc:SetText(string.format(L.KICK_DESC_WITH_DEFAULT, defaultSpell))
            end
            y = y - kickDesc:GetStringHeight() - 10

            local kickAutoDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            kickAutoDesc:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            kickAutoDesc:SetWidth(contentW - 25)
            kickAutoDesc:SetWordWrap(true)
            kickAutoDesc:SetJustifyH("LEFT")
            kickAutoDesc:SetText(string.format(L.KICK_AUTO_DESC, MACRO_KICK_AUTO_NAME))
            y = y - kickAutoDesc:GetStringHeight() - 6

            if IsProtPaladin() then
                local avengersDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                avengersDesc:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
                avengersDesc:SetWidth(contentW - 25)
                avengersDesc:SetWordWrap(true)
                avengersDesc:SetJustifyH("LEFT")
                avengersDesc:SetText(string.format(
                    L.KICK_AVENGERS_DESC,
                    MACRO_AVENGERS_NAME,
                    GetSpellNameLocalized(PROT_PALADIN_KICK_ID_AVENGERS_SHIELD) or "Avenger's Shield"
                ))
                y = y - avengersDesc:GetStringHeight() - 12
            else
                y = y - 12
            end

            -- CC/Stop Spell Input
            local lblStop = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lblStop:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            lblStop:SetWidth(contentW - 30)
            lblStop:SetWordWrap(true)
            lblStop:SetJustifyH("LEFT")
            lblStop:SetText(L.LABEL_CUSTOM_STOP)
            y = y - lblStop:GetStringHeight() - 10

            local stopInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
            stopInput:SetSize(math.min(220, math.max(120, contentW - 50)), 20)
            stopInput:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
            stopInput:SetAutoFocus(false)
            stopInput:SetText(MPlusMarkerDB.stopSpell or "")

            stopInput:SetScript("OnEditFocusLost", function(self)
                MPlusMarkerDB.stopSpell = self:GetText()
                UpdateMacroForZone()
            end)
            stopInput:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            y = y - 20 - 6
            local defaultStopSpell = GetDefaultStop()
            local stopDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            stopDesc:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            stopDesc:SetWidth(contentW - 25)
            stopDesc:SetWordWrap(true)
            stopDesc:SetJustifyH("LEFT")
            stopDesc:SetText(string.format(L.STOP_DESC, defaultStopSpell))
            y = y - stopDesc:GetStringHeight() - 20

            -- Announce Checkbox (label to the right, wraps for long locales)
            local chkAnnounce = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            chkAnnounce:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            chkAnnounce:SetSize(26, 26)
            chkAnnounce:SetChecked(MPlusMarkerDB.announceFocus)

            local chkLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            chkLabel:SetPoint("TOPLEFT", chkAnnounce, "TOPRIGHT", 5, -4)
            chkLabel:SetWidth(math.max(80, contentW - 70))
            chkLabel:SetWordWrap(true)
            chkLabel:SetJustifyH("LEFT")
            chkLabel:SetText(L.CHK_ANNOUNCE_FOCUS)

            chkAnnounce:SetScript("OnClick", function(self)
                MPlusMarkerDB.announceFocus = self:GetChecked()
            end)

            y = y - math.max(28, chkLabel:GetStringHeight() + 8) - 8

            -- Auto-Mark Roles Prompt Checkbox
            local chkAutoMark = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            chkAutoMark:SetPoint("TOPLEFT", content, "TOPLEFT", 15, y)
            chkAutoMark:SetSize(26, 26)
            chkAutoMark:SetChecked(MPlusMarkerDB.autoMarkRolesPrompt)

            local chkAutoMarkLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            chkAutoMarkLabel:SetPoint("TOPLEFT", chkAutoMark, "TOPRIGHT", 5, -4)
            chkAutoMarkLabel:SetWidth(math.max(80, contentW - 70))
            chkAutoMarkLabel:SetWordWrap(true)
            chkAutoMarkLabel:SetJustifyH("LEFT")
            chkAutoMarkLabel:SetText(L.CHK_AUTO_MARK_ROLES)

            chkAutoMark:SetScript("OnClick", function(self)
                MPlusMarkerDB.autoMarkRolesPrompt = self:GetChecked()
            end)

            y = y - math.max(28, chkAutoMarkLabel:GetStringHeight() + 8) - 15
            yOffset = y
        end
        content:SetHeight(math.abs(yOffset))
    end

    ConfigGUI = GUI
    ConfigGUI.Refresh()
end

-- Build Interface Options Panel
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame", "MPlusMarkerOptionsPanel", UIParent)
    panel.name = "MPlusMarker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.OPT_TITLE)

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetWidth(520)
    description:SetWordWrap(true)
    description:SetJustifyH("LEFT")
    description:SetText(L.OPT_DESC)

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetHeight(30)
    openBtn:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
    openBtn:SetText(L.BTN_OPEN_CONFIG)
    FitPanelButtonWidth(openBtn, 100, 24)
    openBtn:SetScript("OnClick", function()
        if ConfigGUI then
            if ConfigGUI:IsShown() then ConfigGUI:Hide() else ConfigGUI:Show() end
        end
        if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Hide() end
    end)

    -- Reset Defaults Button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetHeight(30)
    resetBtn:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -20)
    resetBtn:SetText(L.BTN_RESET_DEFAULTS)
    FitPanelButtonWidth(resetBtn, 100, 24)
    resetBtn:SetScript("OnClick", function()
        -- Ask for confirmation before wiping data
        StaticPopupDialogs["MPLUSMARKER_RESET"] = {
            text = L.RESET_CONFIRM_TEXT,
            button1 = _G.YES or "Yes",
            button2 = _G.NO or "No",
            OnAccept = function()
                -- Wipe the DB and let the ADDON_LOADED logic rebuild it cleanly
                MPlusMarkerDB = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("MPLUSMARKER_RESET")
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "MPlusMarker")
        Settings.RegisterAddOnCategory(category)
    end
end

-- Build Minimap Button
local function BuildMinimapButton()
    local mmBtn = CreateFrame("Button", "MPlusMarkerMinimapButton", Minimap)
    mmBtn:SetSize(31, 31)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(8)
    
    mmBtn.bg = mmBtn:CreateTexture(nil, "BACKGROUND")
    mmBtn.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    mmBtn.bg:SetSize(25, 25)
    mmBtn.bg:SetPoint("TOPLEFT", 2, -4)
    
    mmBtn.icon = mmBtn:CreateTexture(nil, "ARTWORK")
    mmBtn.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    mmBtn.icon:SetSize(20, 20)
    mmBtn.icon:SetPoint("TOPLEFT", 7, -6)

    mmBtn.border = mmBtn:CreateTexture(nil, "OVERLAY")
    mmBtn.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mmBtn.border:SetSize(54, 54)
    mmBtn.border:SetPoint("TOPLEFT")

    mmBtn:RegisterForClicks("AnyUp")
    mmBtn:RegisterForDrag("LeftButton", "RightButton")
    mmBtn:SetMovable(true)

    local function UpdateMinimapButtonPosition()
        local angle = math.rad(MPlusMarkerDB.minimapPos or 45)
        -- Calculate radius dynamically to always sit on the outer ring
        local radius = (Minimap:GetWidth() / 2) + 10
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    mmBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if ConfigGUI then
                if ConfigGUI:IsShown() then ConfigGUI:Hide() else ConfigGUI:Show() end
            end
        end
    end)

    mmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L.MM_TITLE, 1, 1, 1, true)
        GameTooltip:AddLine(L.MM_LEFT_CLICK, 1, 1, 1, true)
        GameTooltip:AddLine(L.MM_DRAG, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    mmBtn:SetScript("OnDragStart", function()
        mmBtn:SetScript("OnUpdate", function()
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            xpos = xpos / Minimap:GetEffectiveScale()
            ypos = ypos / Minimap:GetEffectiveScale()
            
            local deltaX = xpos - (xmin + Minimap:GetWidth() / 2)
            local deltaY = ypos - (ymin + Minimap:GetHeight() / 2)
            
            local angle = math.deg(math.atan2(deltaY, deltaX))
            MPlusMarkerDB.minimapPos = angle
            UpdateMinimapButtonPosition()
        end)
    end)

    mmBtn:SetScript("OnDragStop", function()
        mmBtn:SetScript("OnUpdate", nil)
    end)

    UpdateMinimapButtonPosition()
end

-- Event Handler
frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- This ensures data is ONLY loaded and merged after WoW has securely read the WTF folder
        MPlusMarkerDB = MPlusMarkerDB or {}
        
        -- Legacy cleanup: drop saved kick/stop spells that match old English or current auto-detected defaults
        local _, playerClass = UnitClass("player")
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec) or nil
        ClearLegacySavedSpell("kickSpell", LEGACY_ENGLISH_INTERRUPTS[playerClass], ResolveInterruptSpellID(specID, playerClass))
        ClearLegacySavedSpell("stopSpell", LEGACY_ENGLISH_STOPS[playerClass], STOP_SPELL_IDS[playerClass])
        
        -- Initialize Global Focus Marker if it doesn't exist
        if not MPlusMarkerDB.globalFocusMarker then
            MPlusMarkerDB.globalFocusMarker = 4
        end

        -- Initialize Announce Setting
        if MPlusMarkerDB.announceFocus == nil then
            MPlusMarkerDB.announceFocus = true
        end

        -- Initialize Role Prompt Setting
        if MPlusMarkerDB.autoMarkRolesPrompt == nil then
            MPlusMarkerDB.autoMarkRolesPrompt = true
        end

        if MPlusMarkerDB.backupMarkModifier == nil then
            MPlusMarkerDB.backupMarkModifier = "shift"
        end
        if MPlusMarkerDB.focusClearMarkModifier == nil then
            MPlusMarkerDB.focusClearMarkModifier = "shift"
        end

        -- In-instance focus marker bar (FocusMarker-style picker)
        if MPlusMarkerDB.focusBarEnabled == nil then
            MPlusMarkerDB.focusBarEnabled = true
        end
        if MPlusMarkerDB.focusBarIconSize == nil then
            MPlusMarkerDB.focusBarIconSize = 32
        end
        if MPlusMarkerDB.focusBarOrientation == nil then
            MPlusMarkerDB.focusBarOrientation = "HORIZONTAL"
        end
        if not MPlusMarkerDB.focusBarPosition then
            MPlusMarkerDB.focusBarPosition = { "CENTER", "UIParent", "CENTER", 0, -120 }
        end
        MPlusMarkerDB.seenSplashes = MPlusMarkerDB.seenSplashes or {}

        -- Migrate Defaults to DB
        for id, data in pairs(DefaultZones) do
            if not MPlusMarkerDB[id] then
                MPlusMarkerDB[id] = { name = data.name, group = data.group, mobs = {} }
                for _, mob in ipairs(data.mobs) do
                    local row = { name = mob.name, marker = mob.marker, backupMarker = mob.backupMarker or 0, note = mob.note or "" }
                    if mob.npcId then
                        row.npcId = mob.npcId
                    end
                    table.insert(MPlusMarkerDB[id].mobs, row)
                end
            else
                -- Ensure existing DB entries get the group tag if they are missing it
                if not MPlusMarkerDB[id].group then MPlusMarkerDB[id].group = data.group end
                -- Keep canonical default zone labels (fixes saves from C_Map mis-resolved names)
                MPlusMarkerDB[id].name = data.name

                -- Ensure existing entries get the new backupMarker and note properties
                for _, mob in ipairs(MPlusMarkerDB[id].mobs) do
                    if not mob.backupMarker then mob.backupMarker = 0 end
                    if not mob.note then mob.note = "" end
                end
            end
        end

        -- Backfill npcId from default definitions (upgrades old saves; enables localized /tar)
        for id, def in pairs(DefaultZones) do
            local zoneDb = MPlusMarkerDB[id]
            if zoneDb and zoneDb.mobs and def.mobs then
                for _, dbMob in ipairs(zoneDb.mobs) do
                    if not dbMob.npcId then
                        for _, defMob in ipairs(def.mobs) do
                            if defMob.npcId and string.lower(dbMob.name) == string.lower(defMob.name) then
                                dbMob.npcId = defMob.npcId
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Assign default group to any user-added zones that don't have one
        for id, data in pairs(MPlusMarkerDB) do
            if type(data) == "table" and not data.group then
                data.group = GROUP_NS
            end
            if type(data) == "table" and data.mobs then
                for _, mob in ipairs(data.mobs) do
                    if not mob.backupMarker then mob.backupMarker = 0 end
                    if not mob.note then mob.note = "" end
                end
            end
        end

        BuildGUI()
        BuildOptionsPanel()
        BuildMinimapButton()
        BuildFocusMarkerBar()
        UpdateFocusBarVisibility()

        C_Timer.After(1.5, function()
            RefreshAllSavedMobLocalizedNames()
            UpdateMacroForZone()
            if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
        end)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateFocusBarVisibility()
        -- Run everywhere to ensure Kick and Focus macros are always set up correctly
        C_Timer.After(2, function()
            RefreshAllSavedMobLocalizedNames()
            UpdateMacroForZone()
            UpdateFocusBarVisibility()
            TryShowTmTildeSplash()
        end)
        
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- When a player swaps specs (e.g. from Prot to Holy), update the macro!
        if arg1 == "player" then
            C_Timer.After(1, function()
                UpdateMacroForZone()
                if ConfigGUI and ConfigGUI:IsShown() then ConfigGUI.Refresh() end
            end)
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingMacroUpdate then
            UpdateMacroForZone()
        end
        if pendingTmTildeSplash then
            TryShowTmTildeSplash()
        end
    
    elseif event == "READY_CHECK" then
        -- Tank/healer mark prompt: party leader only, not in a raid, out of combat (macros work everywhere; this is optional UI)
        if IsInGroup() and MPlusMarkerDB.autoMarkRolesPrompt and not IsInRaid() and UnitIsGroupLeader("player") and not InCombatLockdown() then
            local generatedMacro = ""
            local units = {"player", "party1", "party2", "party3", "party4"}
            local foundRoles = false

            for _, unit in ipairs(units) do
                if UnitExists(unit) then
                    local role = UnitGroupRolesAssigned(unit)
                    if role == "TANK" then
                        generatedMacro = generatedMacro .. "/tm [@" .. unit .. "] ~6\n"
                        foundRoles = true
                    elseif role == "HEALER" then
                        generatedMacro = generatedMacro .. "/tm [@" .. unit .. "] ~5\n"
                        foundRoles = true
                    end
                end
            end

            if foundRoles then
                MPlusMarkerRolePrompt.btnYes:SetAttribute("macrotext", generatedMacro)
                MPlusMarkerRolePrompt:Show()
                C_Timer.After(15, function()
                    if MPlusMarkerRolePrompt:IsShown() and not InCombatLockdown() then
                        MPlusMarkerRolePrompt:Hide()
                    end
                end)
            end
        end

        -- Focus marker /say: only when in a party group (not solo); never in a raid. Target/focus macros are unchanged and work solo.
        if MPlusMarkerDB.announceFocus and IsInGroup() and not IsInRaid() then
            local fMarker = MPlusMarkerDB.globalFocusMarker or 4
            SendChatMessage(string.format(L.PRINT_FOCUS_ANNOUNCE, fMarker), "SAY")
        end
    end
end)

-- Slash Commands
SLASH_MPLUSMARKER1 = "/mpm"
SLASH_MPLUSMARKER2 = "/mpmarker"
SlashCmdList["MPLUSMARKER"] = function(msg)
    -- Using strtrim prevents trailing spaces from breaking the command
    msg = strtrim(string.lower(msg or ""))
    
    if msg == "config" or msg == "gui" then
        if ConfigGUI:IsShown() then ConfigGUI:Hide() else ConfigGUI:Show() end
        return
    end

    if string.sub(msg, 1, 3) == "add" then
        local newMob = strtrim(string.sub(msg, 5)) -- grab everything after "add "
        if newMob and newMob ~= "" then
            AddMobToZone(newMob, 8)
        end
        return
    end

    if msg == "id" then
        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if instanceID then ChatPrint(string.format(L.PRINT_CURRENT_INSTANCE_ID, "|cFF00FFFF" .. instanceID .. "|r")) else ChatPrintErr(L.PRINT_NOT_IN_INSTANCE) end
        return
    end
    
    UpdateMacroForZone()
end