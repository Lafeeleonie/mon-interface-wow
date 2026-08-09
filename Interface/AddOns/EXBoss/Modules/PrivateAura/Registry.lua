---@diagnostic disable: undefined-global

ExBoss.PrivateAura = ExBoss.PrivateAura or {}
local PrivateAura = ExBoss.PrivateAura

local function normalizeVoiceCategory(value)
    if PrivateAura and type(PrivateAura.NormalizeVoiceCategory) == "function" then
        return PrivateAura:NormalizeVoiceCategory(value)
    end
    local num = tonumber(value)
    if num == 1 or num == 2 then
        return num
    end
    return 3
end

local function copyStringArray(values)
    local out = {}
    if type(values) ~= "table" then
        return out
    end
    for i = 1, #values do
        local value = values[i]
        if type(value) == "string" and value ~= "" then
            out[#out + 1] = value
        end
    end
    table.sort(out)
    return out
end

local function copyNumberArray(values)
    local out = {}
    if type(values) ~= "table" then
        return out
    end
    for i = 1, #values do
        local value = tonumber(values[i])
        if value and value > 0 then
            out[#out + 1] = value
        end
    end
    table.sort(out)
    return out
end

local function makeSpellRecord(scopeType, ownerKey, ownerLabel, spellID, row)
    return {
        scopeType = scopeType,
        ownerKey = ownerKey,
        ownerLabel = ownerLabel,
        configType = "privateAura",
        spellID = spellID,
        name = row.name or "",
        voiceCategory = normalizeVoiceCategory(row.voiceCategory),
        bosses = copyStringArray(row.bosses),
        sources = copyStringArray(row.sources),
        sourceNPCIDs = copyNumberArray(row.sourceNPCIDs),
    }
end

local function sortSpellRecords(rows)
    table.sort(rows, function(a, b)
        local an = tostring(a.name or "")
        local bn = tostring(b.name or "")
        if an == bn then
            return (a.spellID or 0) < (b.spellID or 0)
        end
        return an < bn
    end)
end

local function buildRaidEntries(rawRaid)
    local entries = {}
    for encounterID, row in pairs(rawRaid) do
        if type(row) == "table" and type(row.spells) == "table" then
            local spells = {}
            for spellID, spellRow in pairs(row.spells) do
                local sid = tonumber(spellID)
                if sid and type(spellRow) == "table" then
                    spells[#spells + 1] = makeSpellRecord(
                        "raidBoss",
                        encounterID,
                        row.boss or "",
                        sid,
                        spellRow
                    )
                end
            end
            sortSpellRecords(spells)
            entries[#entries + 1] = {
                scopeType = "raidBoss",
                encounterID = tonumber(encounterID),
                dungeon = row.dungeon or "",
                boss = row.boss or "",
                spellCount = #spells,
                spells = spells,
            }
        end
    end

    table.sort(entries, function(a, b)
        return (a.encounterID or 0) < (b.encounterID or 0)
    end)
    return entries
end

local function buildMplusEntries(rawMplus)
    local entries = {}
    for dungeonKey, row in pairs(rawMplus) do
        if type(row) == "table" and type(row.spells) == "table" then
            local allSpells = {}
            local bossBuckets = {}
            local bossOrder = {}
            local trashSpells = {}

            for spellID, spellRow in pairs(row.spells) do
                local sid = tonumber(spellID)
                if sid and type(spellRow) == "table" then
                    local record = makeSpellRecord(
                        "mplusSpell",
                        dungeonKey,
                        row.dungeon or dungeonKey,
                        sid,
                        spellRow
                    )
                    allSpells[#allSpells + 1] = record

                    local bosses = record.bosses
                    if #bosses > 0 then
                        for i = 1, #bosses do
                            local bossName = bosses[i]
                            local bucket = bossBuckets[bossName]
                            if not bucket then
                                bucket = {
                                    scopeType = "mplusBoss",
                                    dungeon = row.dungeon or dungeonKey,
                                    dungeonEN = row.dungeonEN or "",
                                    boss = bossName,
                                    spells = {},
                                }
                                bossBuckets[bossName] = bucket
                                bossOrder[#bossOrder + 1] = bossName
                            end
                            bucket.spells[#bucket.spells + 1] = record
                        end
                    else
                        trashSpells[#trashSpells + 1] = record
                    end
                end
            end

            sortSpellRecords(allSpells)
            sortSpellRecords(trashSpells)

            local bosses = {}
            table.sort(bossOrder)
            for i = 1, #bossOrder do
                local bossName = bossOrder[i]
                local bucket = bossBuckets[bossName]
                sortSpellRecords(bucket.spells)
                bucket.spellCount = #bucket.spells
                bosses[#bosses + 1] = bucket
            end

            entries[#entries + 1] = {
                scopeType = "mplusDungeon",
                dungeon = row.dungeon or dungeonKey,
                dungeonEN = row.dungeonEN or "",
                spellCount = #allSpells,
                allSpells = allSpells,
                bosses = bosses,
                trash = {
                    scopeType = "mplusTrash",
                    dungeon = row.dungeon or dungeonKey,
                    dungeonEN = row.dungeonEN or "",
                    label = (row.dungeon or dungeonKey) .. "小怪",
                    spellCount = #trashSpells,
                    spells = trashSpells,
                },
            }
        end
    end

    table.sort(entries, function(a, b)
        return tostring(a.dungeon or "") < tostring(b.dungeon or "")
    end)
    return entries
end

function PrivateAura:BuildBrowseIndex()
    local raw = self:GetRawData()
    return {
        raidBosses = buildRaidEntries(raw.raid or {}),
        mplusDungeons = buildMplusEntries(raw.mplus or {}),
    }
end

function PrivateAura:GetBrowseIndex()
    if not self._browseIndex then
        self._browseIndex = self:BuildBrowseIndex()
    end
    return self._browseIndex
end

function PrivateAura:GetRaidBossEntries()
    return self:GetBrowseIndex().raidBosses
end

function PrivateAura:GetMplusDungeonEntries()
    return self:GetBrowseIndex().mplusDungeons
end
