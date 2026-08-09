---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Layer1Filter or {}
ExBoss.TrashCD.Layer1Filter = Mod
ExBoss.Trash.Layer1Filter = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Rules = ExBoss.TrashCD and ExBoss.TrashCD.InferenceRules or nil
local ExwindTools = _G.ExwindTools
local LAST_DEBUG = nil

local ACADEMY_DUNGEON_MAP_ID = 2526
local ACADEMY_ZONE_ROUTED_NPCS = {
    [192333] = true,
    [192680] = true,
    [196671] = true,
    [197219] = true,
}

local function UnpackRow(row)
    ---@diagnostic disable-next-line: undefined-field
    local _fn = _G.EXDB and _G.EXDB._r
    if type(row) ~= "table" or row[1] == nil or type(_fn) ~= "function" then
        return row
    end
    local t = _fn(row[1])
    if type(t) ~= "table" then
        return row
    end
    t.dungeon        = row[2]
    t.npcID          = row[3]
    t.name           = row[4]
    t.boss           = row[5]
    t.castTimeSet    = row[6]
    t.channelTimeSet = row[7]
    t.spellIDs       = row[8]
    return t
end

local function NormalizeNameKey(name)
    if Data and type(Data.NormalizeNameKey) == "function" then
        return Data.NormalizeNameKey(name)
    end
    local s = tostring(name or "")
    s = s:lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

local function GetCanonicalDungeonKey(currentDungeonKey, mapID)
    local mid = tonumber(mapID)
    if mid and Data then
        local root = type(Data.GetTrashCDDataRoot) == "function" and Data.GetTrashCDDataRoot() or nil
        local mapRow = type(root) == "table" and type(root[mid]) == "table" and root[mid] or nil
        local mapName = type(mapRow) == "table" and tostring(mapRow.mapName or "") or ""
        local key = NormalizeNameKey(mapName)
        if key ~= "" then
            return key
        end
    end
    return NormalizeNameKey(currentDungeonKey)
end

function Mod.HasPrimaryIdentityData(row)
    if type(row) ~= "table" then
        return false
    end
    if row.sex ~= nil and row.sex ~= "" then return true end
    if row.power ~= nil and row.power ~= "" then return true end
    if row.classID ~= nil and row.classID ~= "" then return true end
    if row.buffCount ~= nil and row.buffCount ~= "" then return true end
    if row.nonElite == true then return true end
    return false
end

local function GetCurrentBossProgressIndex()
    local state = ExwindTools and ExwindTools.State or nil
    local idx = tonumber(state and state.DungeonBossProgressIndex) or 0
    return idx > 0 and idx or nil
end

local function GetCurrentPlayerMapID()
    local state = ExwindTools and ExwindTools.State or nil
    local mapID = tonumber(state and state.MapID) or 0
    return mapID > 0 and mapID or nil
end

local function NormalizeZoneText(text)
    local s = tostring(text or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%s+", " ")
    return s
end

local function GetCurrentZoneText()
    local state = ExwindTools and ExwindTools.State or nil
    local text = NormalizeZoneText(state and (state.ZoneText or state.MinimapZoneText) or "")
    if text ~= "" then
        return text
    end
    if type(GetMinimapZoneText) == "function" then
        local ok, zoneText = pcall(GetMinimapZoneText)
        if ok then
            text = NormalizeZoneText(zoneText)
            if text ~= "" then
                return text
            end
        end
    end
    return nil
end

local function GetMythicPlusForcesPercent()
    local state = ExwindTools and ExwindTools.State or nil
    if type(state) ~= "table" or state.MythicPlusForcesValid ~= true then
        return nil
    end
    return tonumber(state.MythicPlusForcesPercent)
end

local function ResolveAcademyForcesNPC()
    local percent = GetMythicPlusForcesPercent()
    if percent and percent < 20 then
        return 197219, "forces<20"
    end
    if percent and percent > 20 and percent < 25 then
        return 192680, "forces>20<25"
    end
    if percent and percent > 26 and percent < 42 then
        return 192333, "forces>26<42"
    end
    return 196671, percent and "forces-other" or "forces-invalid"
end

local function BuildAcademyForcesRuleDebugText()
    return "<20=197219 | >20<25=192680 | >26<42=192333 | other=196671"
end

local function ParsePlacementSet(text)
    if type(text) ~= "string" or text == "" then
        return nil, nil
    end
    local stageSet = {}
    local mapSet = {}
    for token in text:gmatch("[^,]+") do
        local n = tonumber((tostring(token):gsub("%s+", "")))
        if n and n > 0 then
            if n <= 20 then
                stageSet[n] = true
            else
                mapSet[n] = true
            end
        end
    end
    if next(stageSet) == nil then
        stageSet = nil
    end
    if next(mapSet) == nil then
        mapSet = nil
    end
    return stageSet, mapSet
end

local function IsPlacementAllowed(row, dungeonMapID)
    if type(row) ~= "table" then
        return true
    end
    if tonumber(dungeonMapID) == ACADEMY_DUNGEON_MAP_ID then
        return true
    end
    local stageSet, mapSet = ParsePlacementSet(tostring(row.bossStages or row.bossStage or row.boss or ""))
    if not stageSet and not mapSet then
        return true
    end
    if mapSet then
        if Data and type(Data.IsCurrentPlacementSetAllowed) == "function"
            and Data.IsCurrentPlacementSetAllowed(mapSet) ~= true then
            return false
        end
    end
    if stageSet then
        local currentStage = GetCurrentBossProgressIndex()
        if currentStage and stageSet[currentStage] ~= true then
            return false
        end
    end
    return true
end

local function FormatValue(value)
    if value == nil then
        return "nil"
    end
    if value == "" then
        return "\"\""
    end
    return tostring(value)
end

local function HasPositiveDurationValue(value)
    if type(value) == "table" then
        for _, item in pairs(value) do
            if HasPositiveDurationValue(item) then
                return true
            end
        end
        return false
    end
    if type(value) == "string" then
        for item in string.gmatch(value, "[^,;/|%s]+") do
            if (tonumber(item) or 0) > 0 then
                return true
            end
        end
        return false
    end
    return (tonumber(value) or 0) > 0
end

local function GetMobCDData(mapID, npcID)
    local root = Data and type(Data.GetTrashCDDataRoot) == "function" and Data.GetTrashCDDataRoot() or nil
    local mapRow = type(root) == "table" and type(root[tonumber(mapID)]) == "table" and root[tonumber(mapID)] or nil
    local mobs = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs or nil
    return mobs and mobs[tonumber(npcID)] or nil
end

local function MobCDSupportsCast(mapID, npcID)
    local mobData = GetMobCDData(mapID, npcID)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if type(spells) ~= "table" then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table"
            and (HasPositiveDurationValue(spellData.castTime)
                or HasPositiveDurationValue(spellData.castTimeExtra)
                or HasPositiveDurationValue(spellData.castTimeSet)) then
            return true
        end
    end
    return false
end

local function MobCDSupportsChannel(mapID, npcID)
    local mobData = GetMobCDData(mapID, npcID)
    local spells = type(mobData) == "table" and type(mobData.spells) == "table" and mobData.spells or nil
    if type(spells) ~= "table" then
        return false
    end
    for _, spellData in pairs(spells) do
        if type(spellData) == "table"
            and (HasPositiveDurationValue(spellData.channelTime)
                or HasPositiveDurationValue(spellData.channelDuration)
                or HasPositiveDurationValue(spellData.channelTimeSet)) then
            return true
        end
    end
    return false
end

local function GetTestLevelOffset()
    local offset = ExBoss and ExBoss.TrashCD and tonumber(ExBoss.TrashCD.TestLevelOffset) or nil
    if offset and offset ~= 0 then
        return offset
    end
    return nil
end

local function MatchesAcademyZoneRouteSignature(obs)
    if type(obs) ~= "table" then
        return false
    end
    local observedLevel = tonumber(obs.level)
    if observedLevel == nil then
        return false
    end
    local expectedLevel = 91
    local offset = GetTestLevelOffset()
    if offset then
        expectedLevel = expectedLevel + offset
    end
    if observedLevel ~= expectedLevel and observedLevel ~= (expectedLevel - 60) then
        return false
    end
    if tonumber(obs.sex) ~= 1 then return false end
    if tonumber(obs.power) ~= 1 then return false end
    if tonumber(obs.classID) ~= 1 then return false end
    if tonumber(obs.buffCount) ~= 0 then return false end
    return true
end

function Mod.MatchRow(row, obs, runtime, dungeonMapID)
    if type(row) ~= "table" or type(obs) ~= "table" then
        return false, 0, 0, "bad-row-or-obs"
    end

    if not IsPlacementAllowed(row, dungeonMapID) then
        return false, 0, 0, "placement"
    end

    if not Mod.HasPrimaryIdentityData(row) then
        return false, 0, 0, "no-primary-identity"
    end

    local score = 0
    local strength = 0

    local function checkLevel(templateValue, observedValue)
        if templateValue == nil or templateValue == "" then
            return true
        end
        strength = strength + 1
        if observedValue == nil then
            return true
        end

        local tn = tonumber(templateValue)
        local on = tonumber(observedValue)
        if not tn or not on then
            return false, string.format("db=%s obs=%s", FormatValue(templateValue), FormatValue(observedValue))
        end
        local offset = GetTestLevelOffset()
        local effective = offset and (tn + offset) or tn
        if on == effective or on == (effective - 60) then
            score = score + 1
            return true
        end
        if offset then
            return false,
                string.format("db=%s effective=%s offset=%s obs=%s", FormatValue(templateValue), FormatValue(effective),
                    FormatValue(offset), FormatValue(observedValue))
        end
        return false, string.format("db=%s obs=%s", FormatValue(templateValue), FormatValue(observedValue))
    end

    local function checkNumber(templateValue, observedValue, fuzzy)
        if templateValue == nil or templateValue == "" then
            return true
        end
        strength = strength + 1
        if observedValue == nil then
            return true
        end
        if fuzzy then
            local tn = tonumber(templateValue)
            local on = tonumber(observedValue)
            if tn and on and math.abs(tn - on) <= fuzzy then
                score = score + 1
                return true
            end
            return false,
                string.format("db=%s obs=%s fuzzy=%s", FormatValue(templateValue), FormatValue(observedValue),
                    FormatValue(fuzzy))
        end
        if tonumber(templateValue) == tonumber(observedValue) then
            score = score + 1
            return true
        end
        return false, string.format("db=%s obs=%s", FormatValue(templateValue), FormatValue(observedValue))
    end

    local ok, reason = checkLevel(row.level, obs.level); if not ok then return false, 0, 0, "level " .. tostring(reason) end
    ok, reason = checkNumber(row.sex, obs.sex, nil); if not ok then return false, 0, 0, "sex " .. tostring(reason) end
    ok, reason = checkNumber(row.power, obs.power, nil); if not ok then return false, 0, 0, "power " .. tostring(reason) end
    ok, reason = checkNumber(row.classID, obs.classID, nil); if not ok then
        return false, 0, 0,
            "class " .. tostring(reason)
    end
    ok, reason = checkNumber(row.buffCount, obs.buffCount, nil); if not ok then
        return false, 0, 0,
            "buffCount " .. tostring(reason)
    end
    if obs.unitClassification ~= nil then
        strength = strength + 1
        if row.nonElite == true and obs.unitClassification ~= "elite" then
            score = score + 1
        elseif row.nonElite ~= true and obs.unitClassification == "elite" then
            score = score + 1
        else
            return false, 0, 0,
                string.format("classification dbNonElite=%s obs=%s", tostring(row.nonElite == true),
                    tostring(obs.unitClassification))
        end
    elseif row.nonElite ~= true then
        return false, 0, 0, "classification missing for elite row"
    end

    local cdSupportsCast = nil
    local cdSupportsChannel = nil

    if obs.sawCastStart then
        strength = strength + 1
        cdSupportsCast = MobCDSupportsCast(dungeonMapID, row.npcID)
        if row.hasCastSpell == true or cdSupportsCast == true then
            score = score + 1
        else
            return false, 0, 0, "saw-cast-but-row-has-no-cast"
        end
    end

    if obs.sawChannelStart then
        strength = strength + 1
        local castIntoChannel = type(runtime) == "table" and runtime.sawCastIntoChannel == true
        if cdSupportsCast == nil then
            cdSupportsCast = MobCDSupportsCast(dungeonMapID, row.npcID)
        end
        cdSupportsChannel = MobCDSupportsChannel(dungeonMapID, row.npcID)
        if row.hasChannelSpell == true
            or cdSupportsChannel == true
            or (castIntoChannel and (row.hasCastSpell == true or cdSupportsCast == true)) then
            score = score + 1
        else
            return false, 0, 0, "saw-channel-but-row-has-no-channel"
        end
    end

    if obs.sawInterrupted then
        strength = strength + 1
        if row.cannotInterrupt == true then
            return false, 0, 0, "saw-interrupt-but-row-cannot-interrupt"
        end
        score = score + 1
    end

    return true, score, strength
end

function Mod.BuildCandidates(obs, currentDungeonKey, rows, explicitMapID, runtime)
    rows = type(rows) == "table" and rows or {}
    local mapID = tonumber(explicitMapID)
    if not mapID then
        local mapIDByNameKey = Data and type(Data.GetTrashMapIDByNameKey) == "function" and Data.GetTrashMapIDByNameKey() or
            {}
        local lookupKey = NormalizeNameKey(currentDungeonKey)
        mapID = type(mapIDByNameKey) == "table" and mapIDByNameKey[lookupKey] or nil
    end
    local normalizedDungeonKey = GetCanonicalDungeonKey(currentDungeonKey, mapID)
    local out = {}
    local debug = {
        currentDungeonKey = tostring(currentDungeonKey or ""),
        normalizedDungeonKey = tostring(normalizedDungeonKey or ""),
        mapID = mapID,
        zoneText = GetCurrentZoneText(),
        academyZoneRules = BuildAcademyForcesRuleDebugText(),
        totalRows = #rows,
        dungeonRows = 0,
        testedRows = 0,
        matchedRows = 0,
        samples = {},
    }
    for i = 1, #rows do
        local row = rows[i]
        local t = type(row) == "table" and UnpackRow(row) or {}
        if NormalizeNameKey(t.dungeon or "") == normalizedDungeonKey then
            debug.dungeonRows = debug.dungeonRows + 1
            local matchRow = t
            if mapID and Rules and type(Rules.GetLayer1Rule) == "function" then
                local layer1Rule = Rules.GetLayer1Rule(mapID, t.npcID)
                if type(layer1Rule) == "table" then
                    matchRow = setmetatable({}, {
                        __index = function(_, key)
                            local value = layer1Rule[key]
                            if value ~= nil then
                                return value
                            end
                            return t and t[key] or nil
                        end,
                    })
                end
            end
            debug.testedRows = debug.testedRows + 1
            local ok, score, strength, reason = Mod.MatchRow(matchRow, obs, runtime, mapID)
            if ok then
                debug.matchedRows = debug.matchedRows + 1
                out[#out + 1] = {
                    dungeon = tostring(t.dungeon or ""),
                    npcID = tonumber(t.npcID),
                    name = tostring(t.name or "?"),
                    score = score,
                    strength = strength,
                    row = t,
                }
            elseif #debug.samples < 8 then
                debug.samples[#debug.samples + 1] = {
                    npcID = tonumber(t.npcID),
                    name = tostring(t.name or "?"),
                    reason = tostring(reason or "unknown"),
                    level = t.level,
                    sex = t.sex,
                    power = t.power,
                    classID = t.classID,
                    buffCount = t.buffCount,
                    nonElite = t.nonElite,
                }
            end
        end
    end
    if tonumber(mapID) == ACADEMY_DUNGEON_MAP_ID then
        local zoneRouteEligible = MatchesAcademyZoneRouteSignature(obs)
        local expectedNPCID, areaID, areaName, playerMapID, zoneReason = nil, nil, nil, nil, nil
        if zoneRouteEligible then
            expectedNPCID, zoneReason = ResolveAcademyForcesNPC()
        end
        debug.academyZoneExpectedNPCID = expectedNPCID
        debug.academyZoneAreaID = areaID
        debug.academyZoneAreaName = areaName
        debug.academyPlayerMapID = playerMapID
        debug.academyZoneReason = zoneReason
        debug.academyZoneRouteEligible = zoneRouteEligible
        debug.mythicPlusForcesPercent = GetMythicPlusForcesPercent()
        if expectedNPCID then
            local filtered = {}
            for i = 1, #out do
                local npcID = tonumber(out[i] and out[i].npcID)
                if ACADEMY_ZONE_ROUTED_NPCS[npcID] ~= true or npcID == expectedNPCID then
                    filtered[#filtered + 1] = out[i]
                end
            end
            out = filtered
            debug.matchedRows = #out
        end
    end
    LAST_DEBUG = debug

    table.sort(out, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.strength ~= b.strength then
            return a.strength > b.strength
        end
        if a.dungeon ~= b.dungeon then
            return a.dungeon < b.dungeon
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return out
end

function Mod.GetLastDebug()
    return LAST_DEBUG
end
