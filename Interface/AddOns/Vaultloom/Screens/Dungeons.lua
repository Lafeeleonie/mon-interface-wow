local _, Addon = ...

local L = Addon.L
local DATA = Addon.Data.DUNGEONS

local subTabs = {}
for _, definition in ipairs(DATA.subTabs) do
    local entry = definition
    subTabs[#subTabs + 1] = {
        key = entry.key,
        label = function() return L[entry.labelKey] end,
    }
end

Addon.ScreenRegistry:Register({
    id = "dungeons",
    order = 6,
    label = function() return L.SCREEN_DUNGEONS end,
    Create = function(_, host)
        return Addon.JournalScreen.Create({
            screenID = "dungeons",
            stateID = "dungeons.journal",
            layoutVersion = "journal-dungeons-5",
            data = DATA,
            defaultSubTab = "midnight",
            subTabs = subTabs,
            getService = function() return Addon.DungeonJournal end,
            primarySingular = function() return L.DUNGEON_JOURNAL_PRIMARY_LABEL end,
            primaryPlural = function() return L.SCREEN_DUNGEONS end,
            defaultListSubtitle = function() return L.DUNGEON_JOURNAL_MIDNIGHT_SUBTITLE end,
            detailSubtitle = function() return L.DUNGEON_JOURNAL_DETAILS_SUBTITLE end,
            unavailable = function() return L.DUNGEON_JOURNAL_UNAVAILABLE end,
            isDungeon = true,
        }, host)
    end,
})
