local _, Addon = ...

local WoWApi = {}
Addon.WoWApi = WoWApi

local function safeText(value, fallback)
    if type(value) ~= "string" or value == "" then
        return fallback or ""
    end
    return value
end

local PROFESSION_SLOT_CATEGORY = {
    [1] = "primary",
    [2] = "primary",
    [3] = "secondary",
    [4] = "secondary",
    [5] = "secondary",
    [6] = "secondary",
}

local professionFrameStrata = setmetatable({}, { __mode = "k" })
local professionFrameHooks = setmetatable({}, { __mode = "k" })

local function getShownProfessionFrame()
    local frames = { _G.ProfessionsFrame, _G.ProfessionsBookFrame }
    for index = 1, 2 do
        local frame = frames[index]
        if type(frame) == "table" and type(frame.IsShown) == "function" then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown == true then
                return frame
            end
        end
    end
    return nil
end

local function bringProfessionFrameToFront()
    local frame = getShownProfessionFrame()
    if not frame then
        return false
    end

    if not professionFrameHooks[frame] and type(frame.HookScript) == "function" then
        local hooked = pcall(frame.HookScript, frame, "OnHide", function(hiddenFrame)
            local originalStrata = professionFrameStrata[hiddenFrame]
            if originalStrata and type(hiddenFrame.SetFrameStrata) == "function" then
                pcall(hiddenFrame.SetFrameStrata, hiddenFrame, originalStrata)
            end
            professionFrameStrata[hiddenFrame] = nil
        end)
        professionFrameHooks[frame] = hooked == true
    end

    if type(frame.GetFrameStrata) == "function" and type(frame.SetFrameStrata) == "function" then
        local ok, strata = pcall(frame.GetFrameStrata, frame)
        if ok and type(strata) == "string" and strata ~= "" and strata ~= "DIALOG" then
            professionFrameStrata[frame] = professionFrameStrata[frame] or strata
        end
        pcall(frame.SetFrameStrata, frame, "DIALOG")
    end
    if type(frame.SetToplevel) == "function" then
        pcall(frame.SetToplevel, frame, true)
    end
    if type(frame.Raise) == "function" then
        pcall(frame.Raise, frame)
    end
    return true
end

local function queueProfessionFrameRaise()
    bringProfessionFrameToFront()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, bringProfessionFrameToFront)
        C_Timer.After(0.05, bringProfessionFrameToFront)
    end
end

function WoWApi:BuildCharacterKey(name, realm)
    name = safeText(name, "Unknown")
    realm = safeText(realm, "Unknown")
    return name .. "-" .. realm
end

function WoWApi:IsAddOnLoaded(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, _, loaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
        return ok and loaded == true
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addonName)
        return ok and loaded == true
    end
    return false
end

function WoWApi:GetCurrentCharacterIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    local className, classFile
    if type(UnitClass) == "function" then
        className, classFile = UnitClass("player")
    end

    local level = type(UnitLevel) == "function" and UnitLevel("player") or 0
    local itemLevel
    if type(GetAverageItemLevel) == "function" then
        local _, equipped = GetAverageItemLevel()
        itemLevel = tonumber(equipped)
    end

    local money = type(GetMoney) == "function" and GetMoney() or nil
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    local displayID = type(UnitCreatureDisplayID) == "function"
        and tonumber(UnitCreatureDisplayID("player")) or nil
    local timestamp = type(time) == "function" and time() or 0

    name = safeText(name, Addon.L.UNKNOWN or "Unknown")
    realm = safeText(realm, Addon.L.UNKNOWN or "Unknown")
    return {
        key = self:BuildCharacterKey(name, realm),
        guid = guid,
        displayID = displayID,
        name = name,
        realm = realm,
        className = safeText(className, Addon.L.UNKNOWN or "Unknown"),
        classFile = safeText(classFile, "PRIEST"),
        level = math.max(0, tonumber(level) or 0),
        itemLevel = itemLevel,
        money = tonumber(money),
        professions = self:GetCurrentProfessions(),
        lastSeen = timestamp,
    }
end

function WoWApi:GetCurrentProfessions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil
    end
    local result, seen = {}, {}
    local indices = { GetProfessions() }
    for slotIndex = 1, 6 do
        local professionIndex = indices[slotIndex]
        if professionIndex then
            local name, icon, skillLevel, maxSkillLevel, _, spellOffset, skillLineID = GetProfessionInfo(professionIndex)
            skillLineID = tonumber(skillLineID)
            if type(name) == "string" and name ~= "" and skillLineID and skillLineID > 0 and not seen[skillLineID] then
                seen[skillLineID] = true
                result[#result + 1] = {
                    slotIndex = slotIndex,
                    category = PROFESSION_SLOT_CATEGORY[slotIndex] or "secondary",
                    skillLineID = skillLineID,
                    name = name,
                    icon = icon,
                    spellOffset = tonumber(spellOffset),
                    skillLevel = math.max(0, tonumber(skillLevel) or 0),
                    maxSkillLevel = math.max(0, tonumber(maxSkillLevel) or 0),
                }
            end
        end
    end
    table.sort(result, function(left, right)
        local leftPrimary = left.category == "primary" and 1 or 2
        local rightPrimary = right.category == "primary" and 1 or 2
        if leftPrimary ~= rightPrimary then
            return leftPrimary < rightPrimary
        end
        if left.slotIndex ~= right.slotIndex then
            return left.slotIndex < right.slotIndex
        end
        return tostring(left.name) < tostring(right.name)
    end)
    return result
end

function WoWApi:OpenProfession(entry)
    if type(entry) ~= "table" then
        return false
    end
    if type(ProfessionsBook_LoadUI) == "function" then
        pcall(ProfessionsBook_LoadUI)
    end
    local targetSkillLineID = tonumber(entry.skillLineID or entry.baseSkillLineID)
    local baseSkillLineID = tonumber(entry.baseSkillLineID)
    local slotIndex = tonumber(entry.slotIndex)
    local fallbackName = entry.professionName or entry.name or entry.tooltipTitle or entry.label
    local spellOffset = tonumber(entry.spellOffset)
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local indices = { GetProfessions() }
        for index = 1, 6 do
            local professionIndex = indices[index]
            if professionIndex then
                local name, _, _, _, _, currentSpellOffset, skillLineID = GetProfessionInfo(professionIndex)
                local matches = slotIndex == index
                    or targetSkillLineID == tonumber(skillLineID)
                    or baseSkillLineID == tonumber(skillLineID)
                    or (type(fallbackName) == "string" and fallbackName ~= "" and fallbackName == name)
                if matches then
                    targetSkillLineID = targetSkillLineID or tonumber(skillLineID)
                    baseSkillLineID = baseSkillLineID or tonumber(skillLineID)
                    spellOffset = spellOffset or tonumber(currentSpellOffset)
                    fallbackName = name or fallbackName
                    break
                end
            end
        end
    end

    local attempted = false
    local openSkillLineID = targetSkillLineID or baseSkillLineID
    if C_TradeSkillUI and type(C_TradeSkillUI.OpenTradeSkill) == "function" and openSkillLineID then
        attempted = pcall(C_TradeSkillUI.OpenTradeSkill, openSkillLineID) or attempted
    end

    if not getShownProfessionFrame()
        and C_SpellBook
        and type(C_SpellBook.CastSpellBookItem) == "function"
        and spellOffset
    then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        attempted = pcall(C_SpellBook.CastSpellBookItem, spellOffset + 1, bank) or attempted
    end

    if not getShownProfessionFrame()
        and type(CastSpellByName) == "function"
        and type(fallbackName) == "string"
        and fallbackName ~= ""
    then
        attempted = pcall(CastSpellByName, fallbackName) or attempted
    end

    queueProfessionFrameRaise()
    return getShownProfessionFrame() ~= nil or attempted
end

function WoWApi:GetClassColor(classFile)
    local color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return 0.92, 0.76, 0.24
end

function WoWApi:IsInCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

function WoWApi:GetWeeklyResetInfo()
    local seconds = 0
    local resetKnown = false
    if C_DateAndTime and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function" then
        local ok, value = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and tonumber(value) then
            seconds = math.max(0, tonumber(value) or 0)
            resetKnown = true
        end
    end

    local now = type(time) == "function" and time() or 0
    return seconds, resetKnown and (now + seconds) or 0
end

function WoWApi:GetDailyResetInfo()
    local seconds = 0
    local resetKnown = false
    if C_DateAndTime and type(C_DateAndTime.GetSecondsUntilDailyReset) == "function" then
        local ok, value = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and tonumber(value) then
            seconds = math.max(0, tonumber(value) or 0)
            resetKnown = true
        end
    end

    local currentTime = type(time) == "function" and time() or 0
    return seconds, resetKnown and (currentTime + seconds) or 0
end

function WoWApi:GetMapName(mapID)
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 or not (C_Map and type(C_Map.GetMapInfo) == "function") then
        return nil
    end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        return info.name
    end
    return nil
end

function WoWApi:GetActivePreyMapName()
    if not (C_QuestLog and type(C_QuestLog.GetActivePreyQuest) == "function") then
        return nil, nil
    end
    local ok, activeQuestID = pcall(C_QuestLog.GetActivePreyQuest)
    activeQuestID = ok and tonumber(activeQuestID) or nil
    if not activeQuestID or activeQuestID <= 0 then
        return nil, nil
    end

    local mapID
    if type(GetQuestUiMapID) == "function" then
        local mapOk, value = pcall(GetQuestUiMapID, activeQuestID)
        mapID = mapOk and tonumber(value) or nil
    end
    return self:GetMapName(mapID), activeQuestID
end

function WoWApi:GetItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return 0
    end
    if C_Item and type(C_Item.GetItemCount) == "function" then
        local ok, count = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
        if ok then
            return math.max(0, tonumber(count) or 0)
        end
    end
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID, false, false, false)
        if ok then
            return math.max(0, tonumber(count) or 0)
        end
    end
    return 0
end

function WoWApi:GetItemDisplayName(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return ""
    end
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, name, link = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(link) == "string" and link ~= "" then
            return link
        end
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(GetItemInfo) == "function" then
        local ok, name, link = pcall(GetItemInfo, itemID)
        if ok and type(link) == "string" and link ~= "" then
            return link
        end
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return string.format("Item #%d", itemID)
end

function WoWApi:GetCurrencyInfo(currencyID)
    currencyID = tonumber(currencyID)
    if not currencyID or currencyID <= 0 then
        return nil
    end
    if C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and type(info) == "table" then
            return info
        end
    end
    return nil
end

function WoWApi:GetCurrentRenownLevel(factionID)
    factionID = tonumber(factionID)
    if not factionID or factionID <= 0 then
        return 0
    end
    if C_MajorFactions and type(C_MajorFactions.GetCurrentRenownLevel) == "function" then
        local ok, level = pcall(C_MajorFactions.GetCurrentRenownLevel, factionID)
        if ok and tonumber(level) then
            return math.max(0, tonumber(level) or 0)
        end
    end
    return 0
end

function WoWApi:GetMajorFactionName(factionID, fallback)
    factionID = tonumber(factionID)
    if factionID and C_MajorFactions and type(C_MajorFactions.GetMajorFactionData) == "function" then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, factionID)
        if ok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then
            return data.name
        end
    end
    if factionID and C_Reputation and type(C_Reputation.GetFactionDataByID) == "function" then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then
            return data.name
        end
    end
    return fallback or (factionID and string.format("Faction %d", factionID)) or Addon.L.UNKNOWN
end

function WoWApi:GetSpellName(spellID, fallback)
    spellID = tonumber(spellID)
    if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if spellID and type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return fallback
end

function WoWApi:GetCreatureName(npcID, fallback)
    npcID = tonumber(npcID)
    if npcID and C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" then
        local link = string.format("unit:Creature-0-0-0-0-%d-0000000000", npcID)
        local ok, info = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(info) == "table" and type(info.lines) == "table" then
            for _, line in ipairs(info.lines) do
                local name = type(line) == "table" and line.leftText or nil
                if type(name) == "string" and name ~= "" and name ~= UNKNOWN and name ~= UNKNOWNOBJECT and name ~= RETRIEVING_DATA then
                    return name
                end
            end
        end
    end
    return fallback
end

function WoWApi:GetMountItemState(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil, false
    end
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    local icon
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        icon = ok and value or nil
    end
    if not (C_MountJournal and type(C_MountJournal.GetMountFromItem) == "function") then
        return icon, false
    end
    local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
    mountID = ok and tonumber(mountID) or nil
    if not mountID or type(C_MountJournal.GetMountInfoByID) ~= "function" then
        return icon, false
    end
    local values = { pcall(C_MountJournal.GetMountInfoByID, mountID) }
    return icon, values[1] == true and values[12] == true
end

function WoWApi:SetUserWaypoint(mapID, x, y)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or not x or not y
        or not (C_Map and type(C_Map.SetUserWaypoint) == "function")
        or not (UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function")
    then
        return false
    end
    local pointOk, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x / 100, y / 100)
    if not pointOk or not point then
        return false
    end
    local waypointOk = pcall(C_Map.SetUserWaypoint, point)
    if waypointOk and C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return waypointOk == true
end

function WoWApi:FormatDurationShort(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    end

    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end
