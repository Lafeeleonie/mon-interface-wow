---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Inference or {}
ExBoss.TrashCD.Inference = Mod
ExBoss.Trash.Inference = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil

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

function Mod.BuildLayer1Candidates(obs, currentDungeonKey, rows, mapID, runtime)
    rows = type(rows) == "table" and rows or {}
    if Layer1 and type(Layer1.BuildCandidates) == "function" then
        return Layer1.BuildCandidates(obs, currentDungeonKey, rows, mapID, runtime)
    end
    return {}
end

function Mod.ApplyLayer2Candidates(candidates, obs, runtime, mapID, now)
    if Layer2 and type(Layer2.FilterCandidates) == "function" then
        return Layer2.FilterCandidates(candidates, obs, runtime, mapID, now)
    end
    return candidates
end

function Mod.ResolveCandidates(obs, currentDungeonKey, rows, runtime, mapID, now)
    local layer1Candidates = Mod.BuildLayer1Candidates(obs, currentDungeonKey, rows, mapID, runtime)
    local layer2Candidates = Mod.ApplyLayer2Candidates(layer1Candidates, obs, runtime, mapID, now)
    return {
        dungeonKey = NormalizeNameKey(currentDungeonKey),
        layer1Candidates = layer1Candidates,
        candidates = layer2Candidates,
        resolved = type(layer2Candidates) == "table" and #layer2Candidates == 1 and layer2Candidates[1] or nil,
    }
end
