local _, Addon = ...

Addon.Data = Addon.Data or {}

-- Active seasons are intentionally controlled from one place. Dungeons and
-- Mythic+ have separate selectors because a content update can expose a fresh
-- dungeon rotation one reset before the Mythic+ season officially begins.
local Seasons = {
    expansionKey = "midnight",
    activeKey = "season2",
    activeKeys = {
        dungeons = "season2",
        mythicPlus = "season2",
    },
    entries = {
        season1 = {
            key = "season1",
            number = 1,
            dungeonLabelKey = "DUNGEONS_TAB_SEASON1",
            dungeonSubtitleKey = "DUNGEON_JOURNAL_SEASON1_SUBTITLE",
            mythicPlusLabelKey = "MYTHIC_PLUS_TAB_SEASON1",
        },
        season2 = {
            key = "season2",
            number = 2,
            dungeonLabelKey = "DUNGEONS_TAB_SEASON2",
            dungeonSubtitleKey = "DUNGEON_JOURNAL_SEASON2_SUBTITLE",
            mythicPlusLabelKey = "MYTHIC_PLUS_TAB_SEASON2",
        },
    },
}

function Seasons:GetDefinition(key)
    return self.entries[key] or self.entries[self.activeKey] or self.entries.season1
end

function Seasons:GetActiveKey(scope)
    local scopedKey = type(scope) == "string" and self.activeKeys[scope] or nil
    return self:GetDefinition(scopedKey or self.activeKey).key
end

function Seasons:IsSeasonKey(key)
    return type(key) == "string" and self.entries[key] ~= nil
end

function Seasons:GetStateID(prefix, key)
    local definition = self:GetDefinition(key)
    return string.format("%s.%s", tostring(prefix or "season"), definition.key)
end

Addon.Data.SEASONS = Seasons
