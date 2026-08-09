------------------------------------------------------
-- MajesticBeastTracker - Multi-Character Lure Cooldown Tracker
-- Tracks Majestic Lure beast kill cooldowns (daily reset)
-- Kill detection via hidden quest flags (CLEU removed in Midnight 12.0)
------------------------------------------------------

local addonName, ns = ...

-- Lure data: ordered by Talented Tracker unlock threshold
local LURES = {
    { npcID = 245688, itemID = 238652, recipeID = 1225943, questID = 88545, name = "Eversong",    color = "|cff00ff96", colorRGB = {0, 1, 0.59},       requiredPoints = 1,  waypoint = { map = 2395, x = 0.4195, y = 0.8005 },
      reagents = { { itemID = 238371, count = 8 }, { itemID = 238366, count = 8 } } },  -- Arcane Wyrmfish, Lynxfish
    { npcID = 245699, itemID = 238653, recipeID = 1225944, questID = 88526, name = "Zul'Aman",    color = "|cff00ccff", colorRGB = {0, 0.8, 1},        requiredPoints = 10, waypoint = { map = 2437, x = 0.4769, y = 0.5325 },
      reagents = { { itemID = 238382, count = 8 } } },  -- Gore Guppy
    { npcID = 245690, itemID = 238654, recipeID = 1225945, questID = 88531, name = "Harandar",    color = "|cffff9900", colorRGB = {1, 0.6, 0},        requiredPoints = 20, waypoint = { map = 2413, x = 0.6628, y = 0.4791 },
      reagents = { { itemID = 238375, count = 8 }, { itemID = 238374, count = 8 } } },  -- Fungalskin Pike, Tender Lumifin
    { npcID = 247096, itemID = 238655, recipeID = 1225946, questID = 88532, name = "Voidstorm",   color = "|cffa335ee", colorRGB = {0.64, 0.21, 0.93}, requiredPoints = 30, waypoint = { map = 2405, x = 0.5460, y = 0.6580 },
      reagents = { { itemID = 238373, count = 4 } } },  -- Ominous Octopus
    { npcID = 247101, itemID = 238656, recipeID = 1225948, questID = 88524, name = "Grand Beast", color = "|cffff3333", colorRGB = {1, 0.2, 0.2},      requiredPoints = 40, waypoint = { map = 2405, x = 0.4325, y = 0.8275 },
      reagents = { { itemID = 238380, count = 4 } } },  -- Null Voidfish
}
ns.LURES = LURES

-- Returns ordered lure indices based on user's route order setting
function ns.GetRouteOrder()
    local order = MajesticBeastTrackerDB and MajesticBeastTrackerDB.settings and MajesticBeastTrackerDB.settings.routeOrder
    -- Validate: must contain exactly #LURES unique indices 1..#LURES
    if order and #order == #LURES then
        local valid = true
        local seen = {}
        for _, idx in ipairs(order) do
            if type(idx) ~= "number" or idx < 1 or idx > #LURES or seen[idx] then
                valid = false; break
            end
            seen[idx] = true
        end
        if valid then return order end
    end
    -- Default: natural order
    local default = {}
    for i = 1, #LURES do default[i] = i end
    return default
end

-- Fast lookup: questID -> lure index (kill detection via hidden quest flags)
local questToIndex = {}
for i, lure in ipairs(LURES) do
    if lure.questID then
        questToIndex[lure.questID] = i
    end
end

-- Skinning loot items per beast (excluding Torn Material, Fine VT Hide, Manafused Sample)
local BEAST_LOOT = {
    ["Eversong"]    = { 238511, 238512, 238518, 238519, 238523, 238525, 238528, 238529 },
    ["Zul'Aman"]    = { 238513, 238514, 238520, 238521, 238528 },
    ["Harandar"]    = { 238513, 238514, 238520, 238521, 238530, 238522 },
    ["Voidstorm"]   = { 238511, 238512, 238518, 238519, 238528, 238529, 238525, 238523 },
    ["Grand Beast"] = { 238513, 238514, 238520, 238521, 238528, 238529, 238530, 238522 },
}
ns.BEAST_LOOT = BEAST_LOOT

-- Majestic-tier drops (the valuable rares) per beast, derived from BEAST_LOOT
-- 238522 Peerless Plumage, 238523 Carving Canine, 238525 Fantastic Fur,
-- 238528 Majestic Claw, 238529 Majestic Hide, 238530 Majestic Fin
local MAJESTIC_SET = { [238522] = true, [238523] = true, [238525] = true, [238528] = true, [238529] = true, [238530] = true }
local MAJESTIC_LOOT = {}  -- [beastName] = { itemID, ... }
for beast, items in pairs(BEAST_LOOT) do
    local t = {}
    for _, id in ipairs(items) do
        if MAJESTIC_SET[id] then t[#t + 1] = id end
    end
    MAJESTIC_LOOT[beast] = t
end
ns.MAJESTIC_LOOT = MAJESTIC_LOOT

-- All tracked loot item IDs (fast set lookup)
local TRACKED_LOOT = {}
for _, items in pairs(BEAST_LOOT) do
    for _, id in ipairs(items) do
        TRACKED_LOOT[id] = true
    end
end
ns.TRACKED_LOOT = TRACKED_LOOT

-- Lure reagent items (fish used to craft lures)
local LURE_REAGENTS = {}
for _, lure in ipairs(LURES) do
    if lure.reagents then
        for _, r in ipairs(lure.reagents) do
            LURE_REAGENTS[r.itemID] = true
        end
    end
end
ns.LURE_REAGENTS = LURE_REAGENTS

local charKey
local MIDNIGHT_SKINNING_SKILL_LINE = 2917

-- Midnight Skinning weekly Knowledge Point sources
-- Multiple quest IDs = Blizzard rotates different quest each week, ANY = done
-- mode: "rotation" = any quest = done (trainer rotates weekly)
--        "each" = each quest is independent, track count (drops)
--        "single" = one quest (default)
local SKINNING_WEEKLIES = {
    { key = "trainer",  label = "Trainer Quest",     questIDs = { 93710, 93711, 93712, 93713, 93714 }, kp = 3, mode = "rotation" },
    { key = "drop",     label = "Skinning Drop",     questIDs = { 88534, 88549, 88536, 88537, 88530 }, kp = 1, mode = "each" },
    { key = "bonusDrop",label = "Bonus Drop",        questIDs = { 88529 },                             kp = 3 },
    { key = "treatise", label = "Treatise",           questIDs = { 95136 },                             kp = 1 },
    { key = "dmf",      label = "Darkmoon Faire",    questIDs = { 29519 },                             kp = 3, dmf = true },
}
ns.SKINNING_WEEKLIES = SKINNING_WEEKLIES

-- DMF is up from first Sunday of the month for 7 days
local function IsDarkmoonFaireUp()
    local dayOfWeek = tonumber(date("%w"))
    local dayOfMonth = tonumber(date("%e"))
    local firstSundayOfMonth = ((dayOfMonth - (dayOfWeek + 1)) % 7) + 1
    local daysSinceFirstSunday = dayOfMonth - firstSundayOfMonth
    return daysSinceFirstSunday >= 0 and daysSinceFirstSunday <= 6
end
ns.IsDarkmoonFaireUp = IsDarkmoonFaireUp

-- Lookup set of all weekly quest IDs for fast QUEST_TURNED_IN check
local weeklyQuestIDs = {}
for _, w in ipairs(SKINNING_WEEKLIES) do
    for _, qid in ipairs(w.questIDs) do
        weeklyQuestIDs[qid] = true
    end
end

-- Refresh weekly quest status for current character
local function RefreshWeeklies()
    local key = ns.GetCharKey and ns.GetCharKey()
    if not key then return end
    local charData = MajesticBeastTrackerDB and MajesticBeastTrackerDB.chars and MajesticBeastTrackerDB.chars[key]
    if not charData or not charData.hasSkinning then return end

    local weeklies = {}
    for _, w in ipairs(SKINNING_WEEKLIES) do
        if w.mode == "each" then
            local completed = 0
            for _, qid in ipairs(w.questIDs) do
                if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                    completed = completed + 1
                end
            end
            weeklies[w.key] = completed
        elseif w.mode == "rotation" then
            local done = false
            for _, qid in ipairs(w.questIDs) do
                if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                    done = true
                    break
                end
            end
            weeklies[w.key] = done
        else
            weeklies[w.key] = C_QuestLog.IsQuestFlaggedCompleted(w.questIDs[1])
        end
    end
    charData.weeklies = weeklies
    charData.weeklyResetTime = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
end

-- Debug buffer for Mechanic console integration
ns.debugBuffer = {}

-- Demo mode: mask character names for screenshots (does NOT touch DB)
ns.demoMode = false
local demoNames = { "Skinnyboi", "Hideripper", "Stabsworth", "Beastshot", "Zenleaf", "Bonechill", "Axegrind", "Lightblade", "Felgaze", "Moonhide", "Furstreak", "Peeltank" }
local demoNameMap = {}
local DEMO_REALM = "NotReallyARealm"
ns.GetDemoName = function(realName)
    if not ns.demoMode then return realName end
    if not demoNameMap[realName] then
        local idx = 0
        for _ in pairs(demoNameMap) do idx = idx + 1 end
        local fakeName = demoNames[idx + 1] or ("Skinner" .. (idx + 1))
        demoNameMap[realName] = fakeName .. "-" .. DEMO_REALM
    end
    return demoNameMap[realName]
end

-- Instance detection: disable addon in dungeons/raids/pvp/arenas (toggleable)
ns.isInInstance = false
local function CheckInstance()
    local inInstance, instanceType = IsInInstance()
    local rawInInstance = inInstance and instanceType ~= "none"
    -- Respect user setting (default: enabled)
    ns.EnsureDB()
    local settingEnabled = MajesticBeastTrackerDB.settings.disableInInstance ~= false
    ns.isInInstance = rawInInstance and settingEnabled
    if ns.isInInstance then
        if ns.frame and ns.frame:IsShown() then ns.frame:Hide() end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

------------------------------------------------------
-- Cached lookups (shared via ns)
------------------------------------------------------

local iconCache = {}
function ns.GetItemIcon(id)
    if not iconCache[id] then
        iconCache[id] = C_Item.GetItemIconByID(id) or false
    end
    return iconCache[id] or nil
end

------------------------------------------------------
-- Helpers
------------------------------------------------------

local function GetCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

local function GetClassColor(class)
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "|cffffffff"
end

local function FormatTimeLeft(seconds)
    if seconds <= 0 then return "|cff00ff00READY|r" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then
        return string.format("|cffff3333%dh %dm|r", h, m)
    else
        return string.format("|cffff9900%dm|r", m)
    end
end

-- Save per-character lure bag counts to SavedVariables
local function SaveLureBagCounts()
    ns.EnsureDB()
    local key = GetCharKey()
    local charData = MajesticBeastTrackerDB.chars[key]
    if not charData then return end
    local counts = {}
    for _, lure in ipairs(LURES) do
        local count = C_Item.GetItemCount(lure.itemID, false, false, false, false)  -- bags only, no bank
        if count > 0 then
            counts[lure.name] = math.min(count, 1)  -- cap at 1 (only 1 useful per day)
        end
    end
    charData.lureBags = counts
end
ns.SaveLureBagCounts = SaveLureBagCounts

local DEMO_TIME_OFFSET = 8 * 3600  -- 8 hours back in demo mode

local function GetLastDailyReset()
    local secondsUntil = C_DateAndTime.GetSecondsUntilDailyReset()
    if ns.demoMode then secondsUntil = secondsUntil + DEMO_TIME_OFFSET end
    return GetServerTime() + secondsUntil - 86400
end

-- Get the date string for the current reset period
function ns.GetResetDate()
    return date("%Y-%m-%d", GetLastDailyReset())
end

local function IsLureReady(timestamp)
    if not timestamp then return false end
    return timestamp < GetLastDailyReset()
end

local function GetLureTimeRemaining(timestamp)
    if not timestamp then return 0 end
    if timestamp < GetLastDailyReset() then return 0 end
    local secondsUntil = C_DateAndTime.GetSecondsUntilDailyReset()
    if ns.demoMode then secondsUntil = secondsUntil + DEMO_TIME_OFFSET end
    return secondsUntil
end

local function GetLureStatus(timestamp)
    if not timestamp then
        return "|cffffff00???|r"
    elseif IsLureReady(timestamp) then
        return "|cff00ff00READY|r"
    else
        return FormatTimeLeft(GetLureTimeRemaining(timestamp))
    end
end

------------------------------------------------------
-- Loot tracking: bag snapshot & recording
------------------------------------------------------

-- Pending loot state: set on QUEST_TURNED_IN, consumed on LOOT_CLOSED/BAG_UPDATE_DELAYED
local pendingLootBeast = nil     -- lure name (e.g. "Eversong")
local pendingLootSnapshot = nil  -- { [itemID] = count, ... }
local pendingLootTime = 0        -- GetTime() when snapshot was taken
local preCombatSnapshot = nil    -- taken on PLAYER_REGEN_DISABLED (before any loot)

-- Snapshot current bag counts for all tracked loot items
local function SnapshotTrackedItems()
    local snap = {}
    for id in pairs(TRACKED_LOOT) do
        snap[id] = C_Item.GetItemCount(id, false, false, false, false) or 0
    end
    return snap
end

-- Diff two snapshots, return only positive deltas
local function DiffSnapshots(before, after)
    local diffs = {}
    for id in pairs(TRACKED_LOOT) do
        local delta = (after[id] or 0) - (before[id] or 0)
        if delta > 0 then
            diffs[id] = delta
        end
    end
    return diffs
end

-- Snapshot active consumable buffs at kill time
local function SnapshotActiveBuffs()
    local buffs = {}
    local consItems = ns.CONSUMABLE_ITEMS
    if not consItems then return buffs end
    for _, cons in ipairs(consItems) do
        local active = false
        if cons.isToolEnchant then
            -- Check tool enchant via GetWeaponEnchantInfo or tooltip
            active = ns.GetToolEnchantRemaining and ns.GetToolEnchantRemaining() and ns.GetToolEnchantRemaining() > 0
        elseif cons.isSpell then
            -- Check if spell buff is active (Sharpen Your Knife)
            local buffName = C_Spell.GetSpellName(cons.spellID)
            if buffName then
                local aura = C_UnitAuras.GetAuraDataBySpellName("player", buffName, "HELPFUL")
                active = aura ~= nil
            end
        elseif cons.buffSpellID then
            local buffName = C_Spell.GetSpellName(cons.buffSpellID)
            if buffName then
                local aura = C_UnitAuras.GetAuraDataBySpellName("player", buffName, "HELPFUL")
                active = aura ~= nil
            end
        end
        if active then
            buffs[#buffs + 1] = cons.name
        end
    end
    return buffs
end

-- Record loot diffs for a beast into charData
local function RecordLoot(beastName, diffs)
    if not charKey or not diffs then return end
    local hasAny = false
    for _ in pairs(diffs) do hasAny = true; break end
    if not hasAny then return end

    local charData = MajesticBeastTrackerDB.chars[charKey]
    if not charData then return end

    -- Initialize loot structure if needed
    if not charData.loot then
        charData.loot = { thisReset = {}, allTime = {}, resetTime = GetServerTime() }
    end

    -- Reset thisReset if daily reset has passed — archive to history first
    if charData.loot.resetTime and charData.loot.resetTime < GetLastDailyReset() then
        -- Archive previous day's loot to history
        if charData.loot.thisReset and next(charData.loot.thisReset) then
            if not charData.loot.history then charData.loot.history = {} end
            local entry = {
                date = date("%Y-%m-%d", charData.loot.resetTime),
                items = charData.loot.thisReset,
                perBeast = charData.loot.perBeastReset,
                prices = charData.loot.prices,
                killBuffs = charData.loot.killBuffsReset,
            }
            table.insert(charData.loot.history, 1, entry)  -- newest first
            -- Keep max 90 days
            while #charData.loot.history > 90 do
                table.remove(charData.loot.history)
            end
        end
        charData.loot.thisReset = {}
        charData.loot.perBeastReset = {}
        charData.loot.killBuffsReset = {}
        charData.loot.resetTime = GetServerTime()
    end

    -- Add diffs to both thisReset, allTime, perBeast, and perBeastReset; snapshot TSM prices
    if not charData.loot.prices then charData.loot.prices = {} end
    if not charData.loot.perBeast then charData.loot.perBeast = {} end
    if not charData.loot.perBeast[beastName] then charData.loot.perBeast[beastName] = {} end
    if not charData.loot.perBeastReset then charData.loot.perBeastReset = {} end
    if not charData.loot.perBeastReset[beastName] then charData.loot.perBeastReset[beastName] = {} end
    local beastLoot = charData.loot.perBeast[beastName]
    local beastResetLoot = charData.loot.perBeastReset[beastName]
    -- Snapshot active buffs at kill time
    local activeBuffs = SnapshotActiveBuffs()
    if #activeBuffs > 0 then
        if not charData.loot.killBuffs then charData.loot.killBuffs = {} end
        charData.loot.killBuffs[beastName] = activeBuffs
        -- Also store in per-reset for history archiving
        if not charData.loot.killBuffsReset then charData.loot.killBuffsReset = {} end
        charData.loot.killBuffsReset[beastName] = activeBuffs
    end
    -- Track kill count per beast (for drop % calculation)
    if not charData.loot.trackedKills then charData.loot.trackedKills = {} end
    charData.loot.trackedKills[beastName] = (charData.loot.trackedKills[beastName] or 0) + 1
    -- Track per-beast items separately for drop % (independent of allTime)
    if not charData.loot.trackedPerBeast then charData.loot.trackedPerBeast = {} end
    if not charData.loot.trackedPerBeast[beastName] then charData.loot.trackedPerBeast[beastName] = {} end

    for id, count in pairs(diffs) do
        charData.loot.thisReset[id] = (charData.loot.thisReset[id] or 0) + count
        charData.loot.allTime[id] = (charData.loot.allTime[id] or 0) + count
        beastLoot[id] = (beastLoot[id] or 0) + count
        beastResetLoot[id] = (beastResetLoot[id] or 0) + count
        charData.loot.trackedPerBeast[beastName][id] = (charData.loot.trackedPerBeast[beastName][id] or 0) + count
        -- Snapshot price at loot time (only if TSM available and no price yet this reset)
        if ns.GetTSMPrice and not charData.loot.prices[id] then
            charData.loot.prices[id] = ns.GetTSMPrice(id)
        end
    end

    if MajesticBeastTrackerDB.settings.chatNotify ~= false then
        local totalItems = 0
        for _, c in pairs(diffs) do totalItems = totalItems + c end
        print("|cff3FC7EB[MBT]|r Loot tracked: " .. totalItems .. " items from " .. beastName)
    end
end
ns.RecordLoot = RecordLoot

-- Get loot data for a character (auto-resets thisReset if daily reset passed)
function ns.GetCharLoot(charData)
    if not charData or not charData.loot then return nil end
    local loot = charData.loot
    -- Auto-reset thisReset if daily reset has passed — archive to history first
    if loot.resetTime and loot.resetTime < GetLastDailyReset() then
        if loot.thisReset and next(loot.thisReset) then
            if not loot.history then loot.history = {} end
            table.insert(loot.history, 1, {
                date = date("%Y-%m-%d", loot.resetTime),
                items = loot.thisReset,
                perBeast = loot.perBeastReset,
                prices = loot.prices,
                killBuffs = loot.killBuffsReset,
            })
            while #loot.history > 90 do table.remove(loot.history) end
        end
        loot.thisReset = {}
        loot.perBeastReset = {}
        loot.killBuffsReset = {}
        loot.prices = {}
        loot.resetTime = GetServerTime()
    end
    return loot
end

-- Get aggregated loot across all characters
function ns.GetGlobalLoot()
    if not MajesticBeastTrackerDB or not MajesticBeastTrackerDB.chars then return nil, nil, nil, nil, nil end
    local globalReset = {}
    local globalAllTime = {}
    local globalPrices = {}
    local globalPerBeast = {}
    local globalPerBeastReset = {}
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        local loot = ns.GetCharLoot(charData)
        if loot then
            for id, count in pairs(loot.thisReset or {}) do
                globalReset[id] = (globalReset[id] or 0) + count
            end
            for id, count in pairs(loot.allTime or {}) do
                globalAllTime[id] = (globalAllTime[id] or 0) + count
            end
            -- Merge prices (keep latest non-nil)
            for id, price in pairs(loot.prices or {}) do
                if price then globalPrices[id] = price end
            end
            -- Merge per-beast data (all time)
            for beastName, items in pairs(loot.perBeast or {}) do
                if not globalPerBeast[beastName] then globalPerBeast[beastName] = {} end
                for id, count in pairs(items) do
                    globalPerBeast[beastName][id] = (globalPerBeast[beastName][id] or 0) + count
                end
            end
            -- Merge per-beast data (this reset)
            for beastName, items in pairs(loot.perBeastReset or {}) do
                if not globalPerBeastReset[beastName] then globalPerBeastReset[beastName] = {} end
                for id, count in pairs(items) do
                    globalPerBeastReset[beastName][id] = (globalPerBeastReset[beastName][id] or 0) + count
                end
            end
        end
    end
    -- Aggregate tracked kills/loot (for drop % calculation)
    local globalTrackedKills = {}
    local globalTrackedPerBeast = {}
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        local loot = ns.GetCharLoot(charData)
        if loot then
            for beastName, kills in pairs(loot.trackedKills or {}) do
                globalTrackedKills[beastName] = (globalTrackedKills[beastName] or 0) + kills
            end
            for beastName, items in pairs(loot.trackedPerBeast or {}) do
                if not globalTrackedPerBeast[beastName] then globalTrackedPerBeast[beastName] = {} end
                for id, count in pairs(items) do
                    globalTrackedPerBeast[beastName][id] = (globalTrackedPerBeast[beastName][id] or 0) + count
                end
            end
        end
    end
    return globalReset, globalAllTime, globalPrices, globalPerBeast, globalPerBeastReset, globalTrackedKills, globalTrackedPerBeast
end

-- Accumulated loot diffs (collected across multiple LOOT_CLOSED events)
local pendingLootAccum = {}

-- Accumulate loot diffs without consuming the pending state
local function AccumulatePendingLoot()
    if not pendingLootBeast or not pendingLootSnapshot then return end
    local afterSnap = SnapshotTrackedItems()
    local diffs = DiffSnapshots(pendingLootSnapshot, afterSnap)
    -- Merge new diffs into accumulator (use max, since snapshot is from start)
    for id, count in pairs(diffs) do
        pendingLootAccum[id] = count  -- always overwrite: total diff from original snapshot
    end
end

-- Finalize pending loot: record accumulated diffs and clear state
local function FinalizePendingLoot()
    if not pendingLootBeast then return false end
    AccumulatePendingLoot()
    RecordLoot(pendingLootBeast, pendingLootAccum)
    pendingLootBeast = nil
    pendingLootSnapshot = nil
    pendingLootTime = 0
    pendingLootAccum = {}
    ns.isSyncingLoot = false
    return true
end

-- Midnight Skinning spell ID (from profession trainer)
local MIDNIGHT_SKINNING_SPELL = 471014

-- Returns: true (has Midnight Skinning), false (no skinning), nil (API not ready)
local function HasSkinning()
    local prof1, prof2 = GetProfessions()
    if not prof1 and not prof2 then
        if charKey then return false end
        return nil
    end
    -- Check for base Skinning first
    local hasBase = false
    if prof1 then
        local _, _, _, _, _, _, skillLineID = GetProfessionInfo(prof1)
        if skillLineID == 393 then hasBase = true end
    end
    if not hasBase and prof2 then
        local _, _, _, _, _, _, skillLineID = GetProfessionInfo(prof2)
        if skillLineID == 393 then hasBase = true end
    end
    if not hasBase then return false end
    -- Check for Midnight Skinning via spell known check
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, MIDNIGHT_SKINNING_SPELL)
        if ok then return known end
    end
    -- API not available, keep existing data
    return nil
end

-- Returns the base skinning skill level (e.g. 80/100)
local function GetSkinningSkillLevel()
    local prof1, prof2 = GetProfessions()
    -- Check for Midnight Skinning specifically (professionName must match expansion name)
    if prof1 then
        local _, _, skillLevel, _, _, _, skillLineID, _, _, _, professionName = GetProfessionInfo(prof1)
        if skillLineID == 393 and professionName and professionName:find("Midnight") then
            return skillLevel or 0
        end
    end
    if prof2 then
        local _, _, skillLevel, _, _, _, skillLineID, _, _, _, professionName = GetProfessionInfo(prof2)
        if skillLineID == 393 and professionName and professionName:find("Midnight") then
            return skillLevel or 0
        end
    end
    return 0
end

------------------------------------------------------
-- Talented Tracker auto-detection
------------------------------------------------------

-- Talented Tracker detection delegated to TalentData.lua (locale-safe pathNode IDs)
local function DetectTalentedTrackerPoints()
    if not HasSkinning() then return 0 end
    return ns.GetTrackerPoints and ns.GetTrackerPoints() or 0
end

------------------------------------------------------
-- Profession stats calculation (Skill, Perception, Finesse, Deftness)
-- Sources: talent perks, per-point bonuses, gear tooltips
------------------------------------------------------

-- Localized stat names from spell IDs (locale-safe, lazy-initialized)
local STAT_SPELL_IDS = { Skill = 1265719, Perception = 1265727, Finesse = 1265723, Deftness = 1265730 }
local L_STAT_NAMES = {}  -- localized name → internal key
local L_STAT_KEYS = {}   -- internal key → localized name
local L_MIDNIGHT_SKINNING = nil
local L_SKILL = nil
local L_STATS_INITIALIZED = false

local function EnsureStatNames()
    if L_STATS_INITIALIZED then return end
    local allResolved = true
    for key, spellID in pairs(STAT_SPELL_IDS) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            L_STAT_NAMES[name] = key
            L_STAT_KEYS[key] = name
        else
            allResolved = false
        end
    end
    L_MIDNIGHT_SKINNING = C_Spell.GetSpellName(471014)
    L_SKILL = L_STAT_KEYS.Skill
    if allResolved and L_MIDNIGHT_SKINNING and L_SKILL then
        L_STATS_INITIALIZED = true
    end
end

-- Parse stat bonuses from a perk/path description string (locale-safe)
-- Handles: "+5 Perception", "Perception increased by 60", "+5 Midnight Skinning Skill"
local function ParseStatsFromText(text, stats)
    if not text then return end
    EnsureStatNames()
    for key, localName in pairs(L_STAT_KEYS) do
        -- Pattern 1: "+N StatName" or "+NStatName" (talents, gear — handles CJK without space)
        for amount in text:gmatch("%+(%d+)%s*" .. localName) do
            stats[key] = (stats[key] or 0) + tonumber(amount)
        end
        -- Pattern 2: "StatName ... N" (buff tooltips, locale-safe)
        -- Match "Wahrnehmung um 38", "Wahrnehmung von Midnight um 50", "Perception increased by 60"
        -- Find stat name, then the LAST number on the same line (before any period)
        if text:find(localName) and not text:match("%+%d+%s+" .. localName) then
            -- Extract the portion after the stat name and find the number
            local afterStat = text:match(localName .. "(.*)")
            if afterStat then
                local byAmount = afterStat:match("(%d+)")
                if byAmount then
                    stats[key] = (stats[key] or 0) + tonumber(byAmount)
                end
            end
        end
    end
    -- "+N Midnight Skinning Skill" from gear tooltips (locale-safe)
    if L_MIDNIGHT_SKINNING and L_SKILL then
        local mssPattern = "%+(%d+)%s*" .. L_MIDNIGHT_SKINNING .. "%s*" .. L_SKILL
        local skillAmount = text:match(mssPattern)
        if skillAmount then
            stats.Skill = (stats.Skill or 0) + tonumber(skillAmount)
        end
    end
end

-- Get invested points for a single node (not recursive)
local function GetNodePoints(configID, nodeID)
    local info = C_Traits.GetNodeInfo(configID, nodeID)
    if info and info.activeRank and info.activeRank > 0 then
        return info.activeRank
    end
    return 0
end

-- Parse per-point bonus from path description (locale-safe)
-- e.g. "gaining +1 Perception while skinning ... per point"
local function ParsePerPointBonus(desc)
    if not desc then return nil, nil end
    EnsureStatNames()
    for key, localName in pairs(L_STAT_KEYS) do
        local amount = desc:match("%+(%d+)%s+" .. localName)
        if amount then
            return key, tonumber(amount)
        end
    end
    return nil, nil
end

-- DEBUG: Test profession stats APIs
local function TestProfessionStatsAPIs()
    if not HasSkinning() or not C_ProfSpecs then
        print("|cff3FC7EB[MBT TEST]|r No skinning or no C_ProfSpecs")
        return
    end

    local ok, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, MIDNIGHT_SKINNING_SKILL_LINE)
    print("|cff3FC7EB[MBT TEST]|r configID: ok=" .. tostring(ok) .. " val=" .. tostring(configID))
    if not ok or not configID or configID == 0 then return end

    local ok2, tabIDs = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, MIDNIGHT_SKINNING_SKILL_LINE)
    print("|cff3FC7EB[MBT TEST]|r tabIDs: ok=" .. tostring(ok2) .. " count=" .. tostring(tabIDs and #tabIDs))
    if not ok2 or not tabIDs then return end

    for _, tabID in ipairs(tabIDs) do
        local ok3, tabInfo = pcall(C_ProfSpecs.GetTabInfo, tabID)
        print("|cff3FC7EB[MBT TEST]|r Tab " .. tabID .. ": " .. tostring(tabInfo and tabInfo.name))

        -- Try to get root path and its perks
        if ok3 and tabInfo and tabInfo.rootNodeID then
            local ok4, perks = pcall(C_ProfSpecs.GetPerksForPath, tabInfo.rootNodeID)
            print("|cff3FC7EB[MBT TEST]|r   GetPerksForPath: ok=" .. tostring(ok4) .. " count=" .. tostring(perks and #perks))
            if ok4 and perks then
                for pi, perk in ipairs(perks) do
                    local ok5, desc = pcall(C_ProfSpecs.GetDescriptionForPerk, perk.perkID)
                    local okS, state = pcall(C_ProfSpecs.GetStateForPerk, perk.perkID)
                    local okR, rank = pcall(C_ProfSpecs.GetUnlockRankForPerk, perk.perkID)
                    print("|cff3FC7EB[MBT TEST]|r   Perk " .. pi .. " state=" .. tostring(state) .. " unlockRank=" .. tostring(rank) .. " (id=" .. tostring(perk.perkID) .. "): " .. tostring(desc))
                end
            end

            -- Also try children paths
            local ok6, children = pcall(C_ProfSpecs.GetChildrenForPath, tabInfo.rootNodeID)
            if ok6 and children then
                for _, childID in ipairs(children) do
                    local ok7, childPerks = pcall(C_ProfSpecs.GetPerksForPath, childID)
                    local ok8, childDesc = pcall(C_ProfSpecs.GetDescriptionForPath, childID)
                    print("|cff3FC7EB[MBT TEST]|r   Child " .. childID .. ": desc=" .. tostring(childDesc))
                    if ok7 and childPerks then
                        for pi, perk in ipairs(childPerks) do
                            local ok9, pdesc = pcall(C_ProfSpecs.GetDescriptionForPerk, perk.perkID)
                            local okS, state = pcall(C_ProfSpecs.GetStateForPerk, perk.perkID)
                            local okR, rank = pcall(C_ProfSpecs.GetUnlockRankForPerk, perk.perkID)
                            print("|cff3FC7EB[MBT TEST]|r     Perk " .. pi .. " state=" .. tostring(state) .. " unlockRank=" .. tostring(rank) .. ": " .. tostring(pdesc))
                        end
                    end
                end
            end
        end
    end
end
ns.TestProfessionStatsAPIs = TestProfessionStatsAPIs

-- Route Timer: tracks total time across character switches
local function EnsureTimer()
    if not MajesticBeastTrackerDB then return false end
    if not MajesticBeastTrackerDB.timer then
        MajesticBeastTrackerDB.timer = { running = false, accumulated = 0, sessionStart = nil }
    end
    return true
end

function ns.StartTimer()
    if not EnsureTimer() then return end
    local t = MajesticBeastTrackerDB.timer
    if t.running then return end -- already running
    t.running = true
    t.sessionStart = GetServerTime()
    if MajesticBeastTrackerDB.settings.chatNotify ~= false then
        print("|cff3FC7EB[MBT]|r Route timer started.")
    end
    if ns.UpdateUI then ns.UpdateUI() end
end

function ns.StopTimer()
    if not EnsureTimer() then return end
    local t = MajesticBeastTrackerDB.timer
    if not t.running then return end -- already stopped
    if t.sessionStart then
        t.accumulated = t.accumulated + (GetServerTime() - t.sessionStart)
        t.sessionStart = nil
    end
    t.running = false
    if MajesticBeastTrackerDB.settings.chatNotify ~= false then
        print("|cff3FC7EB[MBT]|r Route timer stopped: " .. ns.FormatTimerElapsed())
    end
    if ns.UpdateUI then ns.UpdateUI() end
end

function ns.ResetTimer()
    if not MajesticBeastTrackerDB then return end
    MajesticBeastTrackerDB.timer = { running = false, accumulated = 0, sessionStart = nil }
    if ns.UpdateUI then ns.UpdateUI() end
end

function ns.GetTimerElapsed()
    if not EnsureTimer() then return end
    local t = MajesticBeastTrackerDB.timer
    local total = t.accumulated or 0
    if t.running and t.sessionStart then
        total = total + (GetServerTime() - t.sessionStart)
    end
    return total
end

function ns.FormatTimerElapsed()
    local elapsed = ns.GetTimerElapsed()
    local h = math.floor(elapsed / 3600)
    local m = math.floor((elapsed % 3600) / 60)
    local s = elapsed % 60
    if h > 0 then
        return string.format("%dh %02dm %02ds", h, m, s)
    else
        return string.format("%dm %02ds", m, s)
    end
end

function ns.IsTimerRunning()
    if not EnsureTimer() then return end
    return MajesticBeastTrackerDB.timer.running
end

-- Pause timer on logout (save accumulated time)
function ns.PauseTimerForLogout()
    if not EnsureTimer() then return end
    local t = MajesticBeastTrackerDB.timer
    if t.running and t.sessionStart then
        t.accumulated = t.accumulated + (GetServerTime() - t.sessionStart)
        t.sessionStart = nil
        -- Keep running=true so it resumes on next login
    end
end

-- Resume timer on login (if it was running)
function ns.ResumeTimerOnLogin()
    if not EnsureTimer() then return end
    local t = MajesticBeastTrackerDB.timer
    if t.running then
        t.sessionStart = GetServerTime()
    end
end

-- Check if all route beasts are done for all visible characters
function ns.IsRouteComplete()
    if not MajesticBeastTrackerDB or not MajesticBeastTrackerDB.settings then return false end
    local settings = MajesticBeastTrackerDB.settings
    local routeSkip = settings.routeSkip or {}
    local hiddenChars = settings.hiddenChars or {}
    local harandarMinLvl = settings.routeHarandarMinLevel or 80

    for key, charData in pairs(MajesticBeastTrackerDB.chars) do
        if not hiddenChars[key] and charData.hasSkinning then
            for i, lure in ipairs(LURES) do
                -- Skip globally skipped beasts
                local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
                local isSkipped = routeSkip[lure.name] or settings[skipKey]
                if not isSkipped then
                    -- Skip Harandar level check
                    if lure.name == "Harandar" and charData.level and charData.level < harandarMinLvl then
                        isSkipped = true
                    end
                end
                if not isSkipped and ns.CanSeeLure(charData, i) then
                    local ts = charData.lures and charData.lures[lure.name]
                    if not ts or IsLureReady(ts) then
                        return false -- this char still has work to do
                    end
                end
            end
        end
    end
    return true
end

-- Namespace exports for UI.lua
ns.IsLureReady = IsLureReady
ns.GetLureTimeRemaining = GetLureTimeRemaining
ns.FormatTimeLeft = FormatTimeLeft
ns.GetLureStatus = GetLureStatus
ns.GetCharKey = GetCharKey
ns.GetClassColor = GetClassColor

-- Auto-waypoint: after killing a beast, pin the next one in route order
local lastWaypointLure = nil
local lastWaypointTime = 0
function ns.SetNextRouteWaypoint(killedLureIdx)
    if not MajesticBeastTrackerDB or not MajesticBeastTrackerDB.settings then return end
    if not MajesticBeastTrackerDB.settings.autoRouteWaypoint then return end
    -- Dedup: don't fire twice for the same kill (QUEST_TURNED_IN + SyncKillsFromQuests)
    local now = GetTime()
    if killedLureIdx == lastWaypointLure and (now - lastWaypointTime) < 10 then return end
    lastWaypointLure = killedLureIdx
    lastWaypointTime = now

    local key = GetCharKey()
    if not key then return end
    local charData = MajesticBeastTrackerDB.chars[key]
    if not charData then return end

    local routeOrder = ns.GetRouteOrder()
    local routeSkip = MajesticBeastTrackerDB.settings.routeSkip or {}
    local harandarMinLvl = MajesticBeastTrackerDB.settings.routeHarandarMinLevel or 80

    -- Find position of killed beast in route
    local killedPos = nil
    for pos, li in ipairs(routeOrder) do
        if li == killedLureIdx then
            killedPos = pos
            break
        end
    end
    if not killedPos then return end

    -- Search forward in route for next available beast
    for offset = 1, #LURES - 1 do
        local nextPos = ((killedPos - 1 + offset) % #LURES) + 1
        local li = routeOrder[nextPos]
        local lure = LURES[li]

        -- Skip: globally skipped
        local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
        if routeSkip[lure.name] or MajesticBeastTrackerDB.settings[skipKey] then
            -- skip this one
        -- Skip: Harandar level check
        elseif lure.name == "Harandar" and charData.level and charData.level < harandarMinLvl then
            -- skip this one
        -- Skip: can't see this lure (not enough talent points)
        elseif not ns.CanSeeLure(charData, li) then
            -- skip this one
        -- Skip: already killed today
        elseif charData.lures[lure.name] and not IsLureReady(charData.lures[lure.name]) then
            -- skip this one
        else
            -- Found next available beast — set waypoint
            local wp = lure.waypoint
            if wp then
                local mapPoint = UiMapPoint.CreateFromCoordinates(wp.map, wp.x, wp.y)
                C_Map.SetUserWaypoint(mapPoint)
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                    print("|cff3FC7EB[MBT]|r Next route: " .. lure.color .. lure.name .. "|r (waypoint set)")
                end
            end
            return
        end
    end

    -- All beasts done — clear waypoint and notify
    if C_Map.HasUserWaypoint() then
        C_Map.ClearUserWaypoint()
    end
    if MajesticBeastTrackerDB.settings.chatNotify ~= false then
        print("|cff3FC7EB[MBT]|r Route complete! All beasts done for today.")
    end
end

------------------------------------------------------
-- Core functions
------------------------------------------------------

local SETTINGS_DEFAULTS = {
    showFrame = true,
    locked = false,
    showMinimap = true,
    autoCraft = true,
    chatNotify = true,
    hideInCombat = false,
    windowScale = 1.0,
    minimap = { hide = false },
    warbankDeposit = false,
    warbankAutoDeposit = false,
    warbankDepositRewards = true,
    warbankDepositReagents = true,
    showMissingCount = false,
    ahAutofillQuantity = true,
    consumableStock = {},  -- per-item stock targets: { [itemID] = count }
    -- Route: per-beast skip toggles and level thresholds
    routeSkip = {},  -- { ["Zul'Aman"] = true, ... }
    routeHarandarMinLevel = 80,  -- slider 80-90
    routeHideSkipped = false,  -- hide entire column for skipped beasts
    routeOrder = {},  -- custom column order: { 4, 5, 1, 3, 2 } = Voidstorm, Grand, Eversong, Harandar, Zul'Aman
    autoRouteWaypoint = false,  -- auto-set waypoint to next route beast after kill
    autoHide = false,  -- fade out when mouse leaves tracker
    hiddenChars = {},  -- { ["Name-Realm"] = true, ... }
    showHiddenChars = false,  -- temporarily show hidden characters
}

local function EnsureDB()
    if not MajesticBeastTrackerDB then MajesticBeastTrackerDB = {} end
    if not MajesticBeastTrackerDB.chars then MajesticBeastTrackerDB.chars = {} end
    if not MajesticBeastTrackerDB.settings then MajesticBeastTrackerDB.settings = {} end
    for k, v in pairs(SETTINGS_DEFAULTS) do
        if MajesticBeastTrackerDB.settings[k] == nil then
            if type(v) == "table" then
                MajesticBeastTrackerDB.settings[k] = {}
                for k2, v2 in pairs(v) do
                    MajesticBeastTrackerDB.settings[k][k2] = v2
                end
            else
                MajesticBeastTrackerDB.settings[k] = v
            end
        end
    end
end
ns.EnsureDB = EnsureDB

local function EnsureChar(key)
    EnsureDB()
    if not MajesticBeastTrackerDB.chars[key] then
        local _, class = UnitClass("player")
        MajesticBeastTrackerDB.chars[key] = {
            class = class,
            lures = {},
            hasSkinning = false,
            talentPoints = 0,
        }
    end
    if MajesticBeastTrackerDB.chars[key].hasSkinning == nil then
        MajesticBeastTrackerDB.chars[key].hasSkinning = false
    end
    if not MajesticBeastTrackerDB.chars[key].talentPoints then
        MajesticBeastTrackerDB.chars[key].talentPoints = 0
    end
end

local function RecordLureKill(index)
    EnsureChar(charKey)
    local charData = MajesticBeastTrackerDB.chars[charKey]
    charData.lures[LURES[index].name] = GetServerTime()
    local _, class = UnitClass("player")
    charData.class = class
    local requiredForThisKill = LURES[index].requiredPoints
    if requiredForThisKill > charData.talentPoints then
        charData.talentPoints = requiredForThisKill
    end
    charData.hasSkinning = true
    local lure = LURES[index]
    print("|cff3FC7EB[MBT]|r " .. lure.color .. lure.name .. "|r beast killed! Cooldown tracked.")
    -- Auto-stop timer if all characters are done
    C_Timer.After(2, function()
        if ns.IsTimerRunning() and ns.IsRouteComplete() then
            ns.StopTimer()
            if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                print("|cff3FC7EB[MBT]|r All characters done! Timer stopped: " .. ns.FormatTimerElapsed())
            end
        end
    end)
end

-- Sync kill status from quest flags (authoritative source)
local function SyncKillsFromQuests(skipSanityCheck)
    if not charKey then return end
    EnsureChar(charKey)
    local charData = MajesticBeastTrackerDB.chars[charKey]
    local changed = false
    -- First pass: collect quest flag results
    local flagged = {}
    local flagCount = 0
    for i, lure in ipairs(LURES) do
        if lure.questID then
            local completed = C_QuestLog.IsQuestFlaggedCompleted(lure.questID)
            if completed then
                flagged[i] = true
                flagCount = flagCount + 1
            end
        end
    end
    -- Sanity check (login only): if ALL quests flagged but character has no existing kills,
    -- this is likely a false positive (player hasn't specced Talented Tracker)
    if not skipSanityCheck and flagCount == #LURES then
        local hasAnyKill = false
        for _, lure in ipairs(LURES) do
            if charData.lures[lure.name] then
                hasAnyKill = true
                break
            end
        end
        if not hasAnyKill then return false end
    end
    -- Second pass: record kills for flagged quests
    for i, lure in ipairs(LURES) do
        if flagged[i] then
            local existing = charData.lures[lure.name]
            -- Record kill if: no timestamp yet, OR old timestamp is from before daily reset (lure was "ready")
            if not existing or existing < GetLastDailyReset() then
                charData.lures[lure.name] = GetServerTime()
                changed = true
                -- Auto-waypoint to next route beast (if not already triggered by QUEST_TURNED_IN)
                ns.SetNextRouteWaypoint(i)
                -- Start loot tracking if we have a pre-combat snapshot
                if not pendingLootBeast and preCombatSnapshot then
                    pendingLootBeast = lure.name
                    pendingLootSnapshot = preCombatSnapshot
                    preCombatSnapshot = nil
                    pendingLootTime = GetTime()
                    pendingLootAccum = {}
                    ns.isSyncingLoot = true
                    -- Auto-finalize after 15s
                    C_Timer.After(5, function()
                        if pendingLootBeast then
                            FinalizePendingLoot()
                            ns.isSyncingLoot = false
                            if ns.UpdateUI then ns.UpdateUI() end
                        end
                    end)
                end
            end
        end
    end
    return changed
end
ns.SyncKillsFromQuests = SyncKillsFromQuests

-- Detect skinning profession gear using C_TradeSkillUI.GetProfessionSlots
-- Returns the actual inventory slot IDs for the skinning profession
local function DetectSkinningGear()
    local prof1, prof2 = GetProfessions()
    local skinningProfID = nil  -- the profession enum/ID for GetProfessionSlots
    if prof1 then
        local name, _, _, _, _, _, skillLineID, _, _, _, _, profID = GetProfessionInfo(prof1)
        if skillLineID == 393 then skinningProfID = profID or Enum.Profession.Skinning end
    end
    if not skinningProfID and prof2 then
        local name, _, _, _, _, _, skillLineID, _, _, _, _, profID = GetProfessionInfo(prof2)
        if skillLineID == 393 then skinningProfID = profID or Enum.Profession.Skinning end
    end
    if not skinningProfID then return nil end

    -- Get the actual slot IDs for this profession
    local ok, slots = pcall(C_TradeSkillUI.GetProfessionSlots, skinningProfID)
    if not ok or not slots or #slots == 0 then
        -- Fallback: try Enum.Profession.Skinning directly
        ok, slots = pcall(C_TradeSkillUI.GetProfessionSlots, Enum.Profession.Skinning)
        if not ok or not slots or #slots == 0 then return nil end
    end

    local gear = {}
    for idx, slotID in ipairs(slots) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            local itemLink = GetInventoryItemLink("player", slotID)
            local icon = ns.GetItemIcon(itemID)
            gear[#gear + 1] = {
                slotID = slotID,
                itemID = itemID,
                name = itemName or "",
                link = itemLink or "",
                icon = icon,
                slotType = idx == 1 and "tool" or "accessory",
            }
        end
    end
    return gear
end

-- Cached tooltip frames (created once, reused for all scanning)
local MBT_ScanTooltip = CreateFrame("GameTooltip", "MBT_ScanTooltip", nil, "GameTooltipTemplate")
MBT_ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
local MBT_EnchantScanTip = CreateFrame("GameTooltip", "MBT_EnchantScanTip", nil, "GameTooltipTemplate")
MBT_EnchantScanTip:SetOwner(UIParent, "ANCHOR_NONE")
local MBT_StatScanTip = CreateFrame("GameTooltip", "MBT_StatScanTip", nil, "GameTooltipTemplate")
MBT_StatScanTip:SetOwner(UIParent, "ANCHOR_NONE")
local MBT_BuffScanTip = CreateFrame("GameTooltip", "MBT_BuffScanTip", nil, "GameTooltipTemplate")
MBT_BuffScanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- DEBUG: Test gear stat reading from tooltips
local function TestGearStats()
    local gear = DetectSkinningGear()
    if not gear or #gear == 0 then
        print("|cff3FC7EB[MBT TEST]|r No gear detected")
        return
    end
    local tip = MBT_ScanTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    for _, item in ipairs(gear) do
        print("|cff3FC7EB[MBT TEST]|r Gear: " .. tostring(item.name) .. " (slot " .. item.slotID .. ")")
        tip:ClearLines()
        tip:SetInventoryItem("player", item.slotID)
        for i = 1, tip:NumLines() do
            local line = _G["MBT_ScanTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()
                if text then
                    print("|cff3FC7EB[MBT TEST]|r   Line " .. i .. ": " .. text)
                end
            end
        end
    end
    tip:Hide()
end
ns.TestGearStats = TestGearStats

-- Check if skinning tool has temporary enchant (e.g. Razor Sharp from Razorstone)
-- Returns: remainingSeconds (0 if not active), isActive
-- Cached: result stored for 10 seconds (tooltip scan is expensive)
local enchantCache = { time = 0, remaining = 0, active = false }
function ns.InvalidateEnchantCache()
    enchantCache.time = 0
end
function ns.GetToolEnchantRemaining()
    local now = GetTime()
    if now - enchantCache.time < 10 then
        -- Adjust remaining by elapsed time
        local elapsed = now - enchantCache.time
        local rem = math.max(enchantCache.remaining - elapsed, 0)
        return rem, enchantCache.active and rem > 0
    end
    local gear = DetectSkinningGear()
    if not gear or #gear == 0 then
        enchantCache = { time = now, remaining = 0, active = false }
        return 0, false
    end
    local tip = MBT_EnchantScanTip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    for _, item in ipairs(gear) do
        if item.slotID then
            tip:ClearLines()
            tip:SetInventoryItem("player", item.slotID)
            for i = 1, tip:NumLines() do
                local line = _G["MBT_EnchantScanTipTextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if text then
                        local hours = text:match("(%d+)%s*[Hh]ou?r")
                            or text:match("(%d+)%s*[Ss]tund")
                            or text:match("(%d+)%s*[Hh]eure")
                        local mins = text:match("(%d+)%s*[Mm]in")
                        if hours or mins then
                            local secs = (tonumber(hours) or 0) * 3600 + (tonumber(mins) or 0) * 60
                            if secs > 0 then
                                tip:Hide()
                                enchantCache = { time = now, remaining = secs, active = true }
                                return secs, true
                            end
                        end
                    end
                end
            end
        end
    end
    tip:Hide()
    enchantCache = { time = now, remaining = 0, active = false }
    return 0, false
end

-- Calculate total profession stats from talents + gear
-- Cached profession stats (invalidated by talent/gear/buff changes)
local cachedProfStats = nil
local cachedProfStatsTime = 0
local PROF_STATS_CACHE_TTL = 5  -- seconds

local function CalculateProfessionStats()
    -- Return cached result if fresh enough
    if cachedProfStats and (GetTime() - cachedProfStatsTime) < PROF_STATS_CACHE_TTL then
        return cachedProfStats
    end
    local stats = { Skill = 0, Perception = 0, Finesse = 0, Deftness = 0 }
    if not HasSkinning() then return stats end

    -- Base profession skill level
    stats.Skill = GetSkinningSkillLevel()

    if not C_ProfSpecs then return stats end

    local ok, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, MIDNIGHT_SKINNING_SKILL_LINE)
    if not ok or not configID or configID == 0 then return stats end

    -- Talent stats: per-point bonuses from TalentData paths
    -- Uses ownPoints (node's own invested points): root tree totals include children,
    -- which would wrongly grant the root's stat for points spent in sub-paths
    local breakdown = ns.GetTalentBreakdown and ns.GetTalentBreakdown()
    if breakdown then
        for _, path in ipairs(ns.GetTalentPaths()) do
            local invested = (breakdown.ownPoints and breakdown.ownPoints[path.name])
                or breakdown.paths[path.name] or 0
            if invested > 0 and path.perPoint then
                local amount = path.perPointAmount or 1
                stats[path.perPoint] = (stats[path.perPoint] or 0) + invested * amount
            end
        end
    end

    -- Perk bonuses: fixed stat grants from unlocked perks (locale-safe via perkNode IDs)
    local perkStats = ns.GetPerkBonusStats and ns.GetPerkBonusStats()
    if perkStats then
        for stat, amount in pairs(perkStats) do
            stats[stat] = (stats[stat] or 0) + amount
        end
    end

    -- Gear stats from tooltip scanning
    local gear = DetectSkinningGear()
    if gear and #gear > 0 then
        local tip = MBT_StatScanTip
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        for _, item in ipairs(gear) do
            tip:ClearLines()
            tip:SetInventoryItem("player", item.slotID)
            for i = 1, tip:NumLines() do
                local line = _G["MBT_StatScanTipTextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if text then
                        ParseStatsFromText(text, stats)
                    end
                end
            end
        end
        tip:Hide()
    end

    -- Snapshot stats before buffs (for saving to DB)
    stats.SkillBase = stats.Skill
    stats.PerceptionBase = stats.Perception
    stats.FinesseBase = stats.Finesse
    stats.DeftnessBase = stats.Deftness

    -- Buff stats from active auras (tooltip scanning, locale-safe via spell IDs)
    local STAT_BUFFS = {
        { spellID = 1269152 },   -- Sanguithorn Tea "Relaxed"
        { spellID = 1269171 },   -- Argentleaf Tea "Relaxed" (+Finesse)
        { spellID = 1236763 },   -- Haranir Phial of Perception
        { spellID = 1236767 },   -- Haranir Phial of Finesse
        { spellID = 1235216 },   -- Root Crab "Midnight Perception"
    }
    local seenAuras = {}  -- both teas' buffs are named "Relaxed"; scan each aura once
    for _, buff in ipairs(STAT_BUFFS) do
        local buffName = C_Spell.GetSpellName(buff.spellID)
        local auraData = buffName and C_UnitAuras.GetAuraDataBySpellName("player", buffName, "HELPFUL") or nil
        if auraData and auraData.auraInstanceID and not seenAuras[auraData.auraInstanceID] then
            seenAuras[auraData.auraInstanceID] = true
            local tip = MBT_BuffScanTip
            tip:SetOwner(UIParent, "ANCHOR_NONE")
            tip:ClearLines()
            tip:SetUnitBuffByAuraInstanceID("player", auraData.auraInstanceID)
            for i = 1, tip:NumLines() do
                local line = _G["MBT_BuffScanTipTextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if text then
                        ParseStatsFromText(text, stats)
                    end
                end
            end
            tip:Hide()
        end
    end

    cachedProfStats = stats
    cachedProfStatsTime = GetTime()
    return stats
end
ns.CalculateProfessionStats = CalculateProfessionStats

-- Invalidate stats cache (called on talent/gear/buff changes)
function ns.InvalidateProfStatsCache()
    cachedProfStats = nil
    cachedProfStatsTime = 0
end

local function DetectSkinningAndTalent()
    EnsureChar(charKey)
    local charData = MajesticBeastTrackerDB.chars[charKey]
    local skinning = HasSkinning()
    if skinning == true then
        charData.hasSkinning = true
        local points = DetectTalentedTrackerPoints()
        if points > 0 then
            charData.talentPoints = points
        end
        -- Save full talent breakdown (all paths)
        if ns.SaveTalentData then
            ns.SaveTalentData(charData)
        end
        -- Save profession gear
        local gear = DetectSkinningGear()
        if gear then
            charData.gear = gear
        end
        -- Save profession stats (without buffs)
        local stats = CalculateProfessionStats()
        if stats then
            charData.stats = {
                skill = stats.SkillBase or 0,
                perception = stats.PerceptionBase or 0,
                finesse = stats.FinesseBase or 0,
                deftness = stats.DeftnessBase or 0,
            }
        end
        -- Check weekly KP quests
        local weeklies = {}
        for _, w in ipairs(SKINNING_WEEKLIES) do
            if w.mode == "each" then
                -- Each quest is independent, count completed
                local completed = 0
                for _, qid in ipairs(w.questIDs) do
                    if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                        completed = completed + 1
                    end
                end
                weeklies[w.key] = completed  -- number: 0-5
            elseif w.mode == "rotation" then
                -- Rotates weekly, any = done
                local done = false
                for _, qid in ipairs(w.questIDs) do
                    if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                        done = true
                        break
                    end
                end
                weeklies[w.key] = done
            else
                -- Single quest
                weeklies[w.key] = C_QuestLog.IsQuestFlaggedCompleted(w.questIDs[1])
            end
        end
        charData.weeklies = weeklies
        charData.weeklyResetTime = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
    elseif skinning == false then
        -- API confirmed no skinning, safe to clear
        charData.hasSkinning = false
        charData.talentPoints = 0
        charData.gear = nil
    end
    -- skinning == nil: API not ready, keep existing data
end

function ns.CanSeeLure(charData, lureIndex)
    if not charData.hasSkinning then return false end
    if not charData.talentPoints or charData.talentPoints <= 0 then return false end
    return charData.talentPoints >= LURES[lureIndex].requiredPoints
end

------------------------------------------------------
-- Warband Bank Deposit
------------------------------------------------------

ns.isBankOpen = false

-- Find a partial stack or empty slot in warband bank for an item
local function FindWarbankSlot(itemID)
    if not C_Bank or not C_Bank.FetchPurchasedBankTabIDs then return nil, nil end
    local tabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)
    if not tabIDs then return nil, nil end
    -- First: find partial stack of same item
    for _, bagID in ipairs(tabIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID == itemID then
                local maxStack = info.stackSize or (select(8, C_Item.GetItemInfo(itemID)) or 200)
                if (info.stackCount or 0) < maxStack then
                    return bagID, slot
                end
            end
        end
    end
    -- Second: find empty slot
    for _, bagID in ipairs(tabIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if not info then
                return bagID, slot
            end
        end
    end
    return nil, nil
end

-- Collect depositable items in player bags based on settings
local function CollectBagItems()
    EnsureDB()
    local depositRewards = MajesticBeastTrackerDB.settings.warbankDepositRewards
    local depositReagents = MajesticBeastTrackerDB.settings.warbankDepositReagents

    local function shouldDeposit(itemID)
        if depositRewards and TRACKED_LOOT[itemID] then return true end
        if depositReagents and LURE_REAGENTS[itemID] then return true end
        return false
    end

    local found = {}
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and shouldDeposit(info.itemID) then
                found[#found + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount }
            end
        end
    end
    -- Also check reagent bag
    local reagentBag = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    local ok, numSlots = pcall(C_Container.GetContainerNumSlots, reagentBag)
    if ok and numSlots and numSlots > 0 then
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(reagentBag, slot)
            if info and shouldDeposit(info.itemID) then
                found[#found + 1] = { bag = reagentBag, slot = slot, itemID = info.itemID, count = info.stackCount }
            end
        end
    end
    return found
end

-- Try to click Blizzard's built-in "Deposit All Warband Items" button
local function TryClickDepositAllButton()
    local candidates = {
        AccountBankPanel and AccountBankPanel.AutoDepositFrame and AccountBankPanel.AutoDepositFrame.DepositButton,
        AccountBankPanel and AccountBankPanel.ItemDepositFrame and AccountBankPanel.ItemDepositFrame.DepositButton,
        AccountBankPanel and AccountBankPanel.DepositButton,
        BankPanel and BankPanel.AutoDepositFrame and BankPanel.AutoDepositFrame.DepositButton,
        BankPanel and BankPanel.ItemDepositFrame and BankPanel.ItemDepositFrame.DepositButton,
        BankPanel and BankPanel.DepositButton,
        _G["AutoDepositFrameDepositButton"],
        _G["AccountBankPanelAutoDepositFrameDepositButton"],
    }
    for _, btn in ipairs(candidates) do
        if btn and btn.IsVisible and btn:IsVisible() and btn.Click then
            local ok = pcall(btn.Click, btn)
            if ok then return true end
        end
    end
    return false
end

-- Fallback: cursor-based deposit for individual items (wrapped in pcall to contain taint)
local function CursorDepositItems(items, callback)
    local totalDeposited = 0
    local function depositNext(idx)
        if idx > #items then
            if callback then callback(totalDeposited) end
            return
        end

        local entry = items[idx]
        local ok = pcall(function()
            ClearCursor()
            C_Container.PickupContainerItem(entry.bag, entry.slot)
        end)
        if not ok then
            depositNext(idx + 1)
            return
        end
        C_Timer.After(0.3, function()
            -- Verify item is on cursor before finding destination
            local cursorType = GetCursorInfo()
            if cursorType ~= "item" then
                depositNext(idx + 1)
                return
            end
            local destBag, destSlot = FindWarbankSlot(entry.itemID)
            if not destBag then
                pcall(ClearCursor)
                depositNext(idx + 1)
                return
            end
            pcall(C_Container.PickupContainerItem, destBag, destSlot)
            C_Timer.After(0.5, function()
                local cursorType2 = GetCursorInfo()
                if cursorType2 == "item" then
                    -- Retry with a different slot
                    local destBag2, destSlot2 = FindWarbankSlot(entry.itemID)
                    if destBag2 then
                        pcall(C_Container.PickupContainerItem, destBag2, destSlot2)
                    end
                    C_Timer.After(0.5, function()
                        pcall(ClearCursor)
                        totalDeposited = totalDeposited + 1
                        depositNext(idx + 1)
                    end)
                else
                    totalDeposited = totalDeposited + 1
                    depositNext(idx + 1)
                end
            end)
        end)
    end
    depositNext(1)
end

-- Deposit specific items using UseContainerItem API (no cursor, no taint)
local function UseItemDeposit(items, callback)
    local deposited = 0
    local function depositNext(idx)
        if idx > #items then
            if callback then callback(deposited) end
            return
        end
        local entry = items[idx]
        local ok = pcall(C_Container.UseContainerItem, entry.bag, entry.slot, nil, Enum.BankType.Account)
        if ok then deposited = deposited + 1 end
        -- Small delay between items to let server process
        C_Timer.After(0.15, function()
            depositNext(idx + 1)
        end)
    end
    depositNext(1)
end

-- Deposit tracked items to warband bank
function ns.DepositTrackedToWarbank(callback)
    EnsureDB()
    if not ns.isBankOpen then
        if MajesticBeastTrackerDB.settings.chatNotify then
            print("|cff3FC7EB[MBT]|r Warband Bank is not open.")
        end
        if callback then callback(0) end
        return
    end

    local items = CollectBagItems()
    if #items == 0 then
        if MajesticBeastTrackerDB.settings.chatNotify then
            print("|cff3FC7EB[MBT]|r No tracked reagents in bags to deposit.")
        end
        if callback then callback(0) end
        return
    end

    if MajesticBeastTrackerDB.settings.chatNotify then
        print("|cff3FC7EB[MBT]|r Depositing " .. #items .. " stack(s) to Warband Bank...")
    end

    -- Method 1: UseContainerItem per tracked item (clean API, no cursor, item-specific)
    UseItemDeposit(items, function(count)
        if count > 0 then
            if MajesticBeastTrackerDB.settings.chatNotify then
                print("|cff3FC7EB[MBT]|r Deposited " .. count .. " stack(s) to Warband Bank.")
            end
            if callback then callback(count) end
            return
        end
        -- Method 2: try Blizzard's built-in deposit button
        if TryClickDepositAllButton() then
            if MajesticBeastTrackerDB.settings.chatNotify then
                print("|cff3FC7EB[MBT]|r Used Blizzard Deposit All button.")
            end
            if callback then callback(#items) end
            return
        end
        -- Method 3: cursor-based fallback (longer delays)
        CursorDepositItems(items, function(cursorCount)
            if cursorCount > 0 and MajesticBeastTrackerDB.settings.chatNotify then
                print("|cff3FC7EB[MBT]|r Deposited " .. cursorCount .. " stack(s) to Warband Bank (cursor).")
            end
            if callback then callback(cursorCount) end
        end)
    end)
end

------------------------------------------------------
-- Auction House Integration
-- Auto-fill quantity for missing reagents + Auctionator shopping list
------------------------------------------------------

-- Calculate missing reagents across all lures
-- Returns: { [itemID] = missingCount, ... }
function ns.GetMissingReagents()
    EnsureDB()
    local missing = {}
    local routeSkip = MajesticBeastTrackerDB.settings.routeSkip or {}
    local harandarMinLvl = MajesticBeastTrackerDB.settings.routeHarandarMinLevel or 80
    local hiddenChars = MajesticBeastTrackerDB.settings.hiddenChars or {}
    for i, lure in ipairs(LURES) do
        -- Skip globally skipped lures
        local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
        local isSkipped = routeSkip[lure.name] or MajesticBeastTrackerDB.settings[skipKey] or false
        if isSkipped then
            -- do nothing, skip this lure entirely
        elseif lure.reagents then
            -- Count characters that still need this lure crafted today
            local numLeft = 0
            for charKey, cData in pairs(MajesticBeastTrackerDB.chars) do
                if not hiddenChars[charKey] and ns.CanSeeLure(cData, i) then
                    -- Harandar level check
                    local skipForLevel = lure.name == "Harandar" and cData.level and cData.level < harandarMinLvl
                    if not skipForLevel then
                        local ts = cData.lures[lure.name]
                        if not ts or ns.IsLureReady(ts) then
                            -- Character needs this lure, but check if they already have one in bags
                            local hasBagged = cData.lureBags and cData.lureBags[lure.name]
                            if not hasBagged then
                                numLeft = numLeft + 1
                            end
                        end
                    end
                end
            end
            if numLeft > 0 then
                local reagentAllChars = MajesticBeastTrackerDB.settings.reagentAllChars ~= false
                for _, reagent in ipairs(lure.reagents) do
                    local totalNeed = reagent.count * (reagentAllChars and numLeft or 1)
                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                    local have = 0
                    if itemName then
                        have = C_Item.GetItemCount(itemName, true, false, true, true)
                    else
                        have = C_Item.GetItemCount(reagent.itemID, true, false, true, true)
                    end
                    local need = math.max(totalNeed - have, 0)
                    if need > 0 then
                        missing[reagent.itemID] = (missing[reagent.itemID] or 0) + need
                    end
                end
            end
        end
    end
    return missing
end

-- Build reverse lookup: reagent itemID -> total missing across all lures
-- (used by AH hook to pre-fill quantity)
local ahHookInstalled = false
function ns.InstallAHHook()
    if ahHookInstalled then return end
    ahHookInstalled = true

    -- Hook into Blizzard's CommoditiesBuyFrame to auto-fill quantity
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    hookFrame:SetScript("OnEvent", function()
        local ahFrame = AuctionHouseFrame
        if not ahFrame or not ahFrame.CommoditiesBuyFrame then return end
        local buyDisplay = ahFrame.CommoditiesBuyFrame.BuyDisplay
        if not buyDisplay or buyDisplay._mbtHooked then return end
        buyDisplay._mbtHooked = true

        hooksecurefunc(buyDisplay, "SetItemIDAndPrice", function(self, itemID)
            if not itemID then return end
            EnsureDB()
            local settings = MajesticBeastTrackerDB.settings
            if not settings.ahAutofillQuantity then return end
            if settings.showReagents == false then return end
            -- Check missing reagents
            local missingReagents = ns.GetMissingReagents()
            local needed = missingReagents[itemID]
            -- Check missing consumables (per-item stock target, bags only — not bank/warbank)
            if not needed and ns.CONSUMABLE_ITEMS then
                local stockTargets = type(settings.consumableStock) == "table" and settings.consumableStock or {}
                local target = stockTargets[itemID] or settings["consStock_" .. itemID] or 0
                if target > 0 then
                    local itemName = C_Item.GetItemNameByID(itemID)
                    local have = 0
                    if itemName then
                        have = C_Item.GetItemCount(itemName, false, false, false, false)
                    else
                        have = C_Item.GetItemCount(itemID, false, false, false, false)
                    end
                    needed = math.max(target - have, 0)
                end
            end
            if needed and needed > 0 then
                -- Use Blizzard's own event system to set quantity safely
                C_Timer.After(0.1, function()
                    if self:GetItemID() == itemID then
                        self:GetAuctionHouseFrame():TriggerEvent(
                            AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, needed)
                    end
                end)
            end
        end)
    end)
end

-- Create Auctionator shopping list with missing reagents + consumables
function ns.CreateAuctionatorShoppingList()
    local loaded = C_AddOns.IsAddOnLoaded("Auctionator")
    if not loaded then return false end

    EnsureDB()

    -- Collect all itemIDs we need names for
    local pendingItems = {}  -- { {itemID, count}, ... } for reagents
    local missingReagents = ns.GetMissingReagents()
    for itemID, count in pairs(missingReagents) do
        if count > 0 then
            pendingItems[#pendingItems + 1] = { itemID = itemID, count = count }
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    -- Consumable stock items
    local pendingCons = {}
    local stockTargets = type(MajesticBeastTrackerDB.settings.consumableStock) == "table" and MajesticBeastTrackerDB.settings.consumableStock or {}
    if ns.CONSUMABLE_ITEMS then
        for _, cons in ipairs(ns.CONSUMABLE_ITEMS) do
            if not cons.itemID then break end  -- spell-only (Sharpen Your Knife), skip rest
            local showKey = "consShow_" .. cons.itemID
            if MajesticBeastTrackerDB.settings[showKey] ~= false then
                local target = stockTargets[cons.itemID] or MajesticBeastTrackerDB.settings["consStock_" .. cons.itemID] or 0
                if target > 0 then
                    pendingCons[#pendingCons + 1] = { itemID = cons.itemID, target = target }
                    C_Item.RequestLoadItemDataByID(cons.itemID)
                end
            end
        end
    end

    -- Build list after item data is loaded (retry until all names resolve or timeout)
    local attempts = 0
    local function BuildList()
        attempts = attempts + 1
        local searchStrings = {}
        local allResolved = true

        for _, entry in ipairs(pendingItems) do
            local itemName = C_Item.GetItemNameByID(entry.itemID)
            if itemName then
                table.insert(searchStrings, Auctionator.API.v1.ConvertToSearchString(
                    "MajesticBeastTracker",
                    { searchString = itemName, isExact = true, categoryKey = "", tier = "", quantity = entry.count }
                ))
            else
                allResolved = false
            end
        end

        for _, entry in ipairs(pendingCons) do
            local itemName = C_Item.GetItemNameByID(entry.itemID)
            if itemName then
                local have = C_Item.GetItemCount(itemName, false, false, false, false)
                local need = math.max(entry.target - have, 0)
                if need > 0 then
                    table.insert(searchStrings, Auctionator.API.v1.ConvertToSearchString(
                        "MajesticBeastTracker",
                        { searchString = itemName, isExact = true, categoryKey = "", tier = "", quantity = need }
                    ))
                end
            else
                allResolved = false
            end
        end

        -- Retry if items not yet cached (max 5 attempts, 0.2s apart)
        if not allResolved and attempts < 5 then
            C_Timer.After(0.2, BuildList)
            return
        end

        if #searchStrings > 0 then
            Auctionator.API.v1.CreateShoppingList("MajesticBeastTracker", "MBT Reagents", searchStrings)
            if MajesticBeastTrackerDB.settings.chatNotify then
                print("|cff3FC7EB[MBT]|r Auctionator shopping list updated (" .. #searchStrings .. " items).")
            end
        else
            -- Nothing missing, clean up list if it exists
            if Auctionator.Shopping and Auctionator.Shopping.ListManager then
                if Auctionator.Shopping.ListManager:GetIndexForName("MBT Reagents") then
                    Auctionator.Shopping.ListManager:Delete("MBT Reagents")
                end
            end
            if MajesticBeastTrackerDB.settings.chatNotify then
                print("|cff3FC7EB[MBT]|r All reagents ready — no shopping list needed.")
            end
        end
    end

    -- Start building (first attempt immediate, retries with delay)
    BuildList()
    return true
end

------------------------------------------------------
-- Event handler
-- Kill detection: quest flags (QUEST_TURNED_IN + SyncKillsFromQuests)
-- Weekly tracking: BAG_UPDATE_DELAYED + QUEST_TURNED_IN
------------------------------------------------------

f:SetScript("OnEvent", function(_, event, ...)
    -- Instance detection: check on every zone change
    if event == "PLAYER_ENTERING_WORLD" then
        CheckInstance()
        if ns.isInInstance then return end
    end
    -- Skip most events while in instanced content
    if ns.isInInstance and event ~= "PLAYER_LOGIN" and event ~= "PLAYER_LOGOUT" and event ~= "PLAYER_ENTERING_WORLD" then
        return
    end
    if event == "BANKFRAME_OPENED" then
        ns.isBankOpen = true
        if ns.UpdateUI then ns.UpdateUI() end
        EnsureDB()
        if MajesticBeastTrackerDB.settings.warbankDeposit and MajesticBeastTrackerDB.settings.warbankAutoDeposit then
            C_Timer.After(0.5, function()
                ns.DepositTrackedToWarbank()
            end)
        end
        return
    elseif event == "BANKFRAME_CLOSED" then
        ns.isBankOpen = false
        if ns.UpdateUI then ns.UpdateUI() end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: snapshot bags BEFORE any loot arrives
        preCombatSnapshot = SnapshotTrackedItems()
        return
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        -- Beast kill quest
        if questToIndex[questID] then
            local lureIdx = questToIndex[questID]
            RecordLureKill(lureIdx)
            -- Auto-waypoint to next route beast
            ns.SetNextRouteWaypoint(lureIdx)
            -- Use pre-combat snapshot if available (taken before loot), else snapshot now
            pendingLootBeast = LURES[lureIdx].name
            pendingLootSnapshot = preCombatSnapshot or SnapshotTrackedItems()
            preCombatSnapshot = nil
            pendingLootTime = GetTime()
            pendingLootAccum = {}
            ns.isSyncingLoot = true
            -- Auto-finalize after 15s (covers: kill → loot → skin → done)
            C_Timer.After(5, function()
                if pendingLootBeast then
                    FinalizePendingLoot()
                    ns.isSyncingLoot = false
                    if ns.UpdateUI then ns.UpdateUI() end
                end
            end)
            if ns.UpdateUI then ns.InvalidateLayout() end
        end
        -- Weekly knowledge quest
        if weeklyQuestIDs[questID] then
            C_Timer.After(1, function()
                RefreshWeeklies()
                if ns.UpdateUI then ns.InvalidateLayout() end
            end)
        end
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Quest flags already set by the time bag updates resolve
        SyncKillsFromQuests(true)
        RefreshWeeklies()
        SaveLureBagCounts()
        -- Finalize pending loot after timeout (kill → regular loot → skinning → done)
        if pendingLootBeast and (GetTime() - pendingLootTime) > 15 then
            FinalizePendingLoot()
        end
        if ns.UpdateUI then ns.InvalidateLayout() end
        return
    elseif event == "LOOT_CLOSED" then
        -- Check quest flags after loot window closes (catches skinning kills)
        -- Immediate check + delayed check for flag propagation
        SyncKillsFromQuests(true)
        -- Accumulate loot diffs (don't finalize yet — skinning may come after regular loot)
        if pendingLootBeast then
            C_Timer.After(0.5, function()
                AccumulatePendingLoot()
            end)
        end
        if ns.UpdateUI then ns.InvalidateLayout() end
        C_Timer.After(2, function()
            if SyncKillsFromQuests(true) then
                if ns.UpdateUI then ns.InvalidateLayout() end
            end
        end)
        return
    elseif event == "SKILL_LINES_CHANGED" then
        -- Profession learned/unlearned mid-session
        if charKey then
            DetectSkinningAndTalent()
            if ns.UpdateUI then ns.InvalidateLayout() end
        end
        return
    elseif event == "PLAYER_LOGOUT" then
        ns.PauseTimerForLogout()
        return
    elseif event == "PLAYER_LOGIN" then
        charKey = GetCharKey()
        EnsureChar(charKey)
        local _, class = UnitClass("player")
        MajesticBeastTrackerDB.chars[charKey].class = class
        MajesticBeastTrackerDB.chars[charKey].level = UnitLevel("player")
        -- Defer heavy detection to avoid blocking login
        SyncKillsFromQuests()
        ns.ResumeTimerOnLogin()
        C_Timer.After(3, function()
            DetectSkinningAndTalent()
            SyncKillsFromQuests()
            SaveLureBagCounts()
            if ns.UpdateUI then ns.InvalidateLayout() end
        end)
        -- MechanicLib integration
        local MechanicLib = LibStub and LibStub("MechanicLib-1.0", true)
        if MechanicLib then
            MechanicLib:Register(addonName, {
                version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.1",
                getDebugBuffer = function() return ns.debugBuffer end,
                clearDebugBuffer = function() wipe(ns.debugBuffer) end,
            })
        end

        -- Install AH quantity hook
        ns.InstallAHHook()

        print("|cff3FC7EB[MBT]|r Loaded! |cffffff00/mbt help|r for commands")

    end
end)

------------------------------------------------------
-- Slash commands
------------------------------------------------------

SLASH_MAJESTICBEASTTRACKER1 = "/mbt"
SLASH_MAJESTICBEASTTRACKER2 = "/beast"
SLASH_MAJESTICBEASTTRACKER3 = "/lure"
SlashCmdList["MAJESTICBEASTTRACKER"] = function(msg)
    msg = msg:lower():trim()
    if msg == "" or msg == "ui" or msg == "show" then
        if ns.ShowFrame then ns.ShowFrame() end
    elseif msg == "hide" then
        if ns.HideFrame then ns.HideFrame() end
    elseif msg == "lock" then
        if ns.ToggleLock then ns.ToggleLock() end
    elseif msg == "nuke all" then
        MajesticBeastTrackerDB = { chars = {}, settings = MajesticBeastTrackerDB.settings or {} }
        EnsureChar(charKey)
        DetectSkinningAndTalent()
        print("|cff3FC7EB[MBT]|r ALL data cleared.")
        if ns.UpdateUI then ns.InvalidateLayout() end
    elseif msg == "nuke" then
        EnsureChar(charKey)
        MajesticBeastTrackerDB.chars[charKey].lures = {}
        print("|cff3FC7EB[MBT]|r " .. charKey .. " data cleared.")
        if ns.UpdateUI then ns.InvalidateLayout() end
    elseif msg:find("^talent ") then
        local points = tonumber(msg:match("^talent (%d+)"))
        if points and points >= 0 and points <= 40 then
            EnsureChar(charKey)
            MajesticBeastTrackerDB.chars[charKey].talentPoints = points
            if points > 0 then
                MajesticBeastTrackerDB.chars[charKey].hasSkinning = true
            end
            print("|cff3FC7EB[MBT]|r Talented Tracker set to " .. points .. " points.")
            if ns.UpdateUI then ns.InvalidateLayout() end
        else
            print("|cff3FC7EB[MBT]|r Usage: /mbt talent 0-40")
        end
    elseif msg:find("^debug ") then
        local sub = msg:gsub("^debug ", ""):trim()
        if sub == "stats" then
            ns.TestProfessionStatsAPIs()
        elseif sub == "gear" then
            ns.TestGearStats()
        elseif sub == "calc" then
            local s = ns.CalculateProfessionStats()
            print("|cff3FC7EB[MBT]|r Stats: Skill=" .. s.Skill .. " Per=" .. s.Perception .. " Fin=" .. s.Finesse .. " Dft=" .. s.Deftness)
            if C_ProfSpecs then
                local ok, cid = pcall(C_ProfSpecs.GetConfigIDForSkillLine, 2917)
                if ok and cid and cid ~= 0 then
                    local ok2, tabs = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, 2917)
                    if ok2 and tabs then
                        for _, tabID in ipairs(tabs) do
                            local ok3, ti = pcall(C_ProfSpecs.GetTabInfo, tabID)
                            if ok3 and ti then
                                local rp = GetNodePoints(cid, ti.rootNodeID)
                                print("|cff3FC7EB[MBT]|r  " .. ti.name .. " rank=" .. rp)
                                local ok6, ch = pcall(C_ProfSpecs.GetChildrenForPath, ti.rootNodeID)
                                if ok6 and ch then
                                    for _, childID in ipairs(ch) do
                                        local sp = GetNodePoints(cid, childID)
                                        local ok8, cd = pcall(C_ProfSpecs.GetDescriptionForPath, childID)
                                        local cname = cd and cd:match("^(.-)[,.]") or tostring(childID)
                                        print("|cff3FC7EB[MBT]|r    " .. cname .. " rank=" .. sp)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        elseif sub == "demo" then
            ns.demoMode = not ns.demoMode
            print("|cff3FC7EB[MBT]|r Demo mode: " .. (ns.demoMode and "|cff00ff00ON|r (names masked)" or "|cffff3333OFF|r"))
            if ns.UpdateUI then ns.InvalidateLayout() end
        else
            print("|cff3FC7EB[MBT]|r Debug commands: stats, gear, calc, demo")
        end
    elseif msg:find("^remove ") then
        local target = msg:gsub("^remove ", ""):trim()
        EnsureDB()
        local found = nil
        for key, _ in pairs(MajesticBeastTrackerDB.chars) do
            if key:lower() == target:lower() then
                found = key
                break
            end
        end
        if found then
            MajesticBeastTrackerDB.chars[found] = nil
            print("|cff3FC7EB[MBT]|r Removed " .. found)
            if ns.UpdateUI then ns.InvalidateLayout() end
        else
            print("|cff3FC7EB[MBT]|r Character not found: " .. target)
        end
    elseif msg == "settings" or msg == "config" or msg == "options" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif msg == "help" or msg == "?" then
        print("|cff3FC7EB[MBT]|r === Commands ===")
        print("  |cffffff00/mbt|r - Show tracker frame")
        print("  |cffffff00/mbt hide|r - Hide tracker frame")
        print("  |cffffff00/mbt lock|r - Toggle frame lock")
        print("  |cffffff00/mbt settings|r - Open settings")
        print("  |cffffff00/mbt talent N|r - Override points (0-40)")
        print("  |cffffff00/mbt remove Name-Realm|r - Remove character")
        print("  |cffffff00/mbt debug stats|gear|calc|demo|r - Debug tools")
        print("  |cffffff00/mbt help|r - This help")
    else
        if ns.ShowFrame then ns.ShowFrame() end
    end
end
