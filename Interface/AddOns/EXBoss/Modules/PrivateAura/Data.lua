---@diagnostic disable: undefined-global

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.PrivateAura = ExBoss.PrivateAura or {}
ExBoss.Modules.PrivateAura = ExBoss.PrivateAura

local PrivateAura = ExBoss.PrivateAura

local EMPTY = {
    raid = {},
    mplus = {},
}

local function normalizeVoiceCategory(value)
    local num = tonumber(value)
    if num == 1 or num == 2 then
        return num
    end
    return 3
end

local function normalizeKey(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text:lower()
end

function PrivateAura:GetRawData()
    local data = _G.EXBOSS_PRIVATE_AURA_DATA
    if type(data) ~= "table" then
        return EMPTY
    end
    data.raid = type(data.raid) == "table" and data.raid or {}
    data.mplus = type(data.mplus) == "table" and data.mplus or {}
    return data
end

function PrivateAura:NormalizeVoiceCategory(value)
    return normalizeVoiceCategory(value)
end

function PrivateAura:InvalidateCaches()
    self._browseIndex = nil
    self._mplusKeyIndex = nil
end

function PrivateAura:GetRaidBoss(encounterID)
    local eid = tonumber(encounterID)
    if not eid then
        return nil
    end
    return self:GetRawData().raid[eid]
end

function PrivateAura:GetMplusKeyIndex()
    if self._mplusKeyIndex then
        return self._mplusKeyIndex
    end

    local map = {}
    for dungeonName, row in pairs(self:GetRawData().mplus) do
        if type(row) == "table" then
            map[normalizeKey(dungeonName)] = row
            local en = row.dungeonEN
            if type(en) == "string" and en ~= "" then
                map[normalizeKey(en)] = row
            end
            local zh = row.dungeon
            if type(zh) == "string" and zh ~= "" then
                map[normalizeKey(zh)] = row
            end
        end
    end

    self._mplusKeyIndex = map
    return map
end

function PrivateAura:GetMplusDungeon(dungeonKey)
    if type(dungeonKey) ~= "string" and type(dungeonKey) ~= "number" then
        return nil
    end
    return self:GetMplusKeyIndex()[normalizeKey(dungeonKey)]
end

function PrivateAura:FindRaidSpell(encounterID, spellID)
    local row = self:GetRaidBoss(encounterID)
    if type(row) ~= "table" or type(row.spells) ~= "table" then
        return nil
    end
    return row.spells[tonumber(spellID or 0)]
end

function PrivateAura:FindMplusSpell(dungeonKey, spellID)
    local row = self:GetMplusDungeon(dungeonKey)
    if type(row) ~= "table" or type(row.spells) ~= "table" then
        return nil
    end
    return row.spells[tonumber(spellID or 0)]
end
