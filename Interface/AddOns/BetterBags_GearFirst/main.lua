---@class BetterBags: AceAddon
local BetterBags = LibStub('AceAddon-3.0'):GetAddon("BetterBags")
---@class Localization: AceModule
local L = BetterBags:GetModule('Localization')
---@class Database: AceModule
local db = BetterBags:GetModule('Database')
---@class Constants: AceModule
local const = BetterBags:GetModule('Constants')
---@class Events: AceModule
local events = BetterBags:GetModule('Events')
---@class Sort: AceModule
local sort = BetterBags:GetModule('Sort')
---@class Config: AceModule
local config = BetterBags:GetModule('Config')

---@enum Add gear section order
const.GEAR_SECTION_ORDER = {
    "Head",
    "Neck",
    "Shoulder",
    "Back",
    "Chest",
    "Wrist",
    "Hands",
    "Waist",
    "Legs",
    "Feet",
    "Finger",
    "Trinket",
    "Main Hand",
    "Two-Hand",
    "One-Hand",
    "Off Hand",
    "Held In Off-hand",
    "Ranged",
    "Low iLvl"
}
---@enum Add sort types
const.SECTION_SORT_TYPE.GEAR_ALPHABETICALLY = 4
const.SECTION_SORT_TYPE.HEARTHSTONE_GEAR_ALPHABETICALLY = 5

-- Add config option
local selectValueToLabel = {
    [const.SECTION_SORT_TYPE.ALPHABETICALLY] = L:G("Alphabetically"),
    [const.SECTION_SORT_TYPE.SIZE_DESCENDING] = L:G("Size Descending"),
    [const.SECTION_SORT_TYPE.SIZE_ASCENDING] = L:G("Size Ascending"),
    [const.SECTION_SORT_TYPE.GEAR_ALPHABETICALLY] = L:G("Gear > Alphabetically"),
    [const.SECTION_SORT_TYPE.HEARTHSTONE_GEAR_ALPHABETICALLY] = L:G("Hearthstone > Gear > Alphabetically")
}
local selectLabelToValue = {
    [L:G("Alphabetically")] = const.SECTION_SORT_TYPE.ALPHABETICALLY,
    [L:G("Size Descending")] = const.SECTION_SORT_TYPE.SIZE_DESCENDING,
    [L:G("Size Ascending")] = const.SECTION_SORT_TYPE.SIZE_ASCENDING,
    [L:G("Gear > Alphabetically")] = const.SECTION_SORT_TYPE.GEAR_ALPHABETICALLY,
    [L:G("Hearthstone > Gear > Alphabetically")] = const.SECTION_SORT_TYPE.HEARTHSTONE_GEAR_ALPHABETICALLY
}

local eventFrame = CreateFrame("Frame", "GearFirstEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...;
        if name ~= "BetterBags_GearFirst" then return end
        config:AddPluginConfig("Gear First", {
            {
                name = "Section Order",
                desc = "The order of sections in the backpack when not pinned.\nThis option overrides the default \"Backpack > Section Order\" option.",
                type = "select",
                values = selectValueToLabel,
                get = function()
                    return selectValueToLabel[db:GetSectionSortType(const.BAG_KIND.BACKPACK, db:GetBagView(const.BAG_KIND.BACKPACK))]
                end,
                set = function(ctx, value)
                    db:SetSectionSortType(const.BAG_KIND.BACKPACK, db:GetBagView(const.BAG_KIND.BACKPACK), selectLabelToValue[value])
                    events:SendMessage(ctx, "bags/FullRefreshAll")
                end,
            }
        })
    end
end)

-- Override sort function getter
---@param kind BagKind
---@param view BagView
---@return function
function sort:GetSectionSortFunction(kind, view)
    local sortType = db:GetSectionSortType(kind, view)
    if sortType == const.SECTION_SORT_TYPE.ALPHABETICALLY then
        return function(a, b)
            return self.SortSectionsAlphabetically(kind, a, b)
        end
    elseif sortType == const.SECTION_SORT_TYPE.SIZE_ASCENDING then
        return function(a, b)
            return self.SortSectionsBySizeAscending(kind, a, b)
        end
    elseif sortType == const.SECTION_SORT_TYPE.SIZE_DESCENDING then
        return function(a, b)
            return self.SortSectionsBySizeDescending(kind, a, b)
        end
    elseif sortType == const.SECTION_SORT_TYPE.GEAR_ALPHABETICALLY then
        return function(a, b)
            return self.SortSectionsGearAlphabetically(kind, a, b)
        end
    elseif sortType == const.SECTION_SORT_TYPE.HEARTHSTONE_GEAR_ALPHABETICALLY then
        return function(a, b)
            return self.SortSectionsHearthstoneGearAlphabetically(kind, a, b)
        end
    end
    assert(false, "Unknown sort type: " .. sortType)
    -- Fallback to alphabetical sort
    return function(a, b)
        return self.SortSectionsAlphabetically(kind, a, b)
    end
end

-- Add gear sort function
---@param a Section
---@param b Section
---@return boolean
function sort.SortSectionsGearAlphabetically(kind, a, b)
    local shouldSort, sortResult = sort.SortSectionsByPriority(kind, a, b)
    if shouldSort then return sortResult end
    
    if a.title:GetText() == L:G("Recent Items") then return true end
    if b.title:GetText() == L:G("Recent Items") then return false end
    
    for _, gearType in pairs(const.GEAR_SECTION_ORDER) do
        if a.title:GetText() == L:G(gearType) then return true end
        if b.title:GetText() == L:G(gearType) then return false end
    end

    if string.find(a.title:GetText(), L:G("Gear") .. ":") then return true end
    if string.find(b.title:GetText(), L:G("Gear") .. ":") then return false end

    if a:GetFillWidth() then return false end
    if b:GetFillWidth() then return true end

    if a.title:GetText() == L:G("Free Space") then return false end
    if b.title:GetText() == L:G("Free Space") then return true end
    
    return stripColorCode(a.title:GetText()) < stripColorCode(b.title:GetText())
end

-- Add hearthstone + gear sort function
---@param a Section
---@param b Section
---@return boolean
function sort.SortSectionsHearthstoneGearAlphabetically(kind, a, b)
    local shouldSort, sortResult = sort.SortSectionsByPriority(kind, a, b)
    if shouldSort then return sortResult end
    
    if a.title:GetText() == L:G("Recent Items") then return true end
    if b.title:GetText() == L:G("Recent Items") then return false end

    if a.title:GetText() == L:G("Hearthstones") then return true end
    if b.title:GetText() == L:G("Hearthstones") then return false end

    for _, gearType in pairs(const.GEAR_SECTION_ORDER) do
        if a.title:GetText() == L:G(gearType) then return true end
        if b.title:GetText() == L:G(gearType) then return false end
    end

    if string.find(a.title:GetText(), L:G("Gear") .. ":") then return true end
    if string.find(b.title:GetText(), L:G("Gear") .. ":") then return false end

    if a:GetFillWidth() then return false end
    if b:GetFillWidth() then return true end

    if a.title:GetText() == L:G("Free Space") then return false end
    if b.title:GetText() == L:G("Free Space") then return true end

    return stripColorCode(a.title:GetText()) < stripColorCode(b.title:GetText())
end

---@param text string
---@return string
function stripColorCode(text)
    if string.sub(text, 1, 4) == "|cff" then
        return string.sub(text, 11)
    end
    return text
end