------------------------------------------------------
-- MajesticBeastTracker Talent Data
-- Locale-safe talent detection via numeric pathNode IDs
-- All IDs from Midnight Skinning profession tree
------------------------------------------------------

local addonName, ns = ...

-- Midnight Skinning skill line
local MIDNIGHT_SKILL_LINE = 2917

------------------------------------------------------
-- PathNode IDs (universal, locale-safe)
------------------------------------------------------

-- Tree roots (3 main specializations)
local TREE_THOROUGH_TANNING = 106089   -- +1 Skill per point (root)
local TREE_GAINFUL_GATHERING = 106059  -- +1 Deftness per point (root)
local TREE_TALENTED_TRACKER = 106119   -- +1 Skill per point (root), lure unlocks

-- Sub-specializations of Thorough Tanning
local PATH_SUPERB_SCALES = 106087     -- +1 Skill per point (scaled creatures)
local PATH_LASTING_LEATHER = 106088   -- +1 Skill per point (leathery creatures)

-- Sub-specializations of Gainful Gathering
local PATH_DEDICATED_DIFFUSER = 106056  -- +1 Deftness per point (essence creatures)
local PATH_TROPHY_TAKER = 106057       -- +1 Perception per point (bone creatures)
local PATH_CAREFUL_CARVING = 106058    -- +2 Finesse per point (meat carving)

-- Sub-specializations of Talented Tracker
local PATH_COMPONENT_COLLECTOR = 106117  -- +1 Finesse per point (renowned beasts)
local PATH_MAJESTIC_MATERIALS = 106118   -- +1 Perception per point (renowned beasts)

-- All paths in display order
-- perPointAmount defaults to 1 when omitted
local ALL_PATHS = {
    -- Thorough Tanning
    { id = TREE_THOROUGH_TANNING,  name = "Thorough Tanning",   isRoot = true,  tree = "tanning",  perPoint = "Skill" },
    { id = PATH_SUPERB_SCALES,     name = "Superb Scales",      isRoot = false, tree = "tanning",  perPoint = "Skill" },
    { id = PATH_LASTING_LEATHER,   name = "Lasting Leather",     isRoot = false, tree = "tanning",  perPoint = "Skill" },
    -- Gainful Gathering
    { id = TREE_GAINFUL_GATHERING, name = "Gainful Gathering",  isRoot = true,  tree = "gathering", perPoint = "Deftness" },
    { id = PATH_DEDICATED_DIFFUSER, name = "Dedicated Diffuser", isRoot = false, tree = "gathering", perPoint = "Deftness" },
    { id = PATH_TROPHY_TAKER,      name = "Trophy Taker",       isRoot = false, tree = "gathering", perPoint = "Perception" },
    { id = PATH_CAREFUL_CARVING,    name = "Careful Carving",    isRoot = false, tree = "gathering", perPoint = "Finesse", perPointAmount = 2 },
    -- Talented Tracker
    { id = TREE_TALENTED_TRACKER,  name = "Talented Tracker",   isRoot = true,  tree = "tracker",  perPoint = "Skill" },
    { id = PATH_COMPONENT_COLLECTOR, name = "Component Collector", isRoot = false, tree = "tracker", perPoint = "Finesse" },
    { id = PATH_MAJESTIC_MATERIALS,  name = "Majestic Materials",  isRoot = false, tree = "tracker", perPoint = "Perception" },
}

------------------------------------------------------
-- Perk bonuses: fixed stat grants at specific perkNode IDs
-- Data from skinning.json — each perk gives stats when unlocked
------------------------------------------------------
local PERK_BONUSES = {
    -- Superb Scales (106087): +Skill/+Deftness scaled creatures
    [106067] = { Deftness = 5 },   -- 5pts
    [106066] = { Skill = 5 },      -- 10pts
    [106065] = { Deftness = 5 },   -- 15pts
    [106064] = { Skill = 10 },     -- 20pts
    [106063] = { Deftness = 10 },  -- 25pts
    [106062] = { Skill = 15 },     -- 30pts
    [106061] = { Deftness = 10 },  -- 35pts
    [106060] = { Skill = 20, Perception = 30 },  -- 40pts (major)
    [106068] = {},  -- unlock (no stat shown in game UI)

    -- Lasting Leather (106088): +Skill/+Deftness leathery creatures
    [106076] = { Deftness = 5 },
    [106075] = { Skill = 5 },
    [106074] = { Deftness = 5 },
    [106073] = { Skill = 10 },
    [106072] = { Deftness = 10 },
    [106071] = { Skill = 15 },
    [106070] = { Deftness = 10 },
    [106069] = { Skill = 20, Perception = 30 },  -- major
    [106077] = {},  -- unlock (no stat shown in game UI)

    -- Thorough Tanning root (106089): +Skill perks
    [106085] = { Skill = 5 },
    [106083] = { Skill = 5 },
    [106081] = { Skill = 5 },
    [106079] = { Skill = 5 },
    [106086] = {},  -- unlock: Sharpen Your Knife (no stat)

    -- Dedicated Diffuser (106056): diffuser perks (no direct stats tracked)
    -- Trophy Taker (106057): +Perception
    [106042] = { Perception = 5 },
    [106041] = { Perception = 5 },
    [106040] = { Perception = 10 },
    [106039] = { Perception = 10 },
    [106038] = { Perception = 10 },
    [106037] = { Perception = 10 },
    [106036] = { Perception = 15, Deftness = 30 },  -- major
    [106043] = {},  -- unlock: species-specific reagents (no stat shown in game UI)

    -- Careful Carving (106058): +Perception
    [106033] = { Perception = 5 },
    [106032] = { Perception = 5 },
    [106031] = { Perception = 10 },
    [106030] = { Perception = 10 },
    [106029] = { Perception = 10 },
    [106028] = { Perception = 10 },
    [106035] = { Perception = 15, Deftness = 30 },  -- major (40pts perk, recheck ID)
    [106034] = {},  -- unlock: Carve Meat (no stat shown in game UI)

    -- Gainful Gathering root (106059): +Deftness perks
    [106054] = { Deftness = 5 },
    [106052] = { Deftness = 5 },
    [106050] = { Deftness = 5 },
    [106048] = { Deftness = 5 },
    [106055] = {},  -- unlock (species-specific reagents, no stat)

    -- Component Collector (106117): +Finesse renowned beasts
    [106097] = { Finesse = 5 },
    [106096] = { Finesse = 5 },
    [106095] = { Finesse = 10 },
    [106094] = { Finesse = 10 },
    [106093] = { Finesse = 10 },
    [106092] = { Finesse = 10 },
    [106091] = { Finesse = 15, Deftness = 30 },  -- major
    [106098] = {},  -- unlock (no stat shown in game UI)

    -- Majestic Materials (106118): +Perception renowned beasts
    [106104] = { Perception = 5 },
    [106103] = { Perception = 5 },
    [106102] = { Perception = 10 },
    [106101] = { Perception = 10 },
    [106100] = { Perception = 10 },
    [106099] = { Perception = 15, Skill = 30 },  -- major
    [106105] = {},  -- unlock (no stat shown in game UI)

    -- Talented Tracker root (106119): +Skill perks
    [106115] = { Skill = 5 },
    [106113] = { Skill = 5 },
    [106111] = { Skill = 10 },
    [106109] = { Skill = 15 },
    [106116] = {},  -- unlock: Eversong Lure (no stat)
}

------------------------------------------------------
-- API: Get invested points for a single node
------------------------------------------------------

local function GetNodePoints(configID, nodeID)
    local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if ok and info and info.activeRank and info.activeRank > 0 then
        return math.max(info.activeRank - 1, 0)  -- -1: "learned" counts as rank 1
    end
    return 0
end

------------------------------------------------------
-- API: Get configID for Midnight Skinning
------------------------------------------------------

local function GetConfigID()
    if not C_ProfSpecs then return nil end
    local ok, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, MIDNIGHT_SKILL_LINE)
    if ok and configID and configID > 0 then return configID end
    return nil
end

------------------------------------------------------
-- Get invested points for a tree (root + all children recursively)
------------------------------------------------------

local function GetTreePoints(configID, rootNodeID)
    local ok, total = pcall(function()
        local todo = { rootNodeID }
        local points = 0
        while #todo > 0 do
            local nodeID = table.remove(todo)
            local children = C_ProfSpecs.GetChildrenForPath(nodeID)
            if children then
                for _, childID in ipairs(children) do
                    table.insert(todo, childID)
                end
            end
            local info = C_Traits.GetNodeInfo(configID, nodeID)
            if info and info.activeRank and info.activeRank > 0 then
                points = points + info.activeRank
            end
        end
        return points
    end)
    return ok and total or 0
end

------------------------------------------------------
-- PUBLIC API: Get stat bonuses from unlocked perks
-- Returns: { Skill = N, Perception = N, Finesse = N, Deftness = N }
------------------------------------------------------

function ns.GetPerkBonusStats()
    local configID = GetConfigID()
    if not configID then return nil end
    local stats = { Skill = 0, Perception = 0, Finesse = 0, Deftness = 0 }
    for perkNodeID, bonuses in pairs(PERK_BONUSES) do
        local ok, info = pcall(C_Traits.GetNodeInfo, configID, perkNodeID)
        if ok and info and info.activeRank and info.activeRank > 0 then
            for stat, amount in pairs(bonuses) do
                stats[stat] = (stats[stat] or 0) + amount
            end
        end
    end
    return stats
end

------------------------------------------------------
-- PUBLIC API: Get full talent breakdown for current character
-- Returns: { paths = { [pathName] = points, ... }, tracker = N, totalPoints = N }
------------------------------------------------------

function ns.GetTalentBreakdown()
    local configID = GetConfigID()
    if not configID then return nil end

    local result = {
        paths = {},
        ownPoints = {},  -- points invested in the node itself (roots excl. children) — use for per-point stats
        trees = { tanning = 0, gathering = 0, tracker = 0 },
        tracker = 0,
        totalPoints = 0,
    }

    for _, path in ipairs(ALL_PATHS) do
        local points
        if path.isRoot then
            points = GetTreePoints(configID, path.id)
        else
            points = GetNodePoints(configID, path.id)
        end
        result.paths[path.name] = points
        result.ownPoints[path.name] = GetNodePoints(configID, path.id)
        if path.isRoot then
            result.trees[path.tree] = points
        end
        result.totalPoints = result.totalPoints + (path.isRoot and 0 or points)  -- avoid double-counting
    end

    result.tracker = result.trees.tracker
    return result
end

------------------------------------------------------
-- PUBLIC API: Get Talented Tracker points (replaces old DetectTalentedTrackerPoints)
------------------------------------------------------

function ns.GetTrackerPoints()
    local configID = GetConfigID()
    if not configID then return 0 end
    return GetTreePoints(configID, TREE_TALENTED_TRACKER)
end

------------------------------------------------------
-- PUBLIC API: Save talent data to charData
------------------------------------------------------

function ns.SaveTalentData(charData)
    if not charData then return end
    local breakdown = ns.GetTalentBreakdown()
    if not breakdown then return end

    charData.talentPoints = breakdown.tracker
    charData.talents = {}
    for _, path in ipairs(ALL_PATHS) do
        charData.talents[path.name] = breakdown.paths[path.name] or 0
    end
end

------------------------------------------------------
-- PUBLIC API: Get path info table for UI display
------------------------------------------------------

function ns.GetTalentPaths()
    return ALL_PATHS
end

ns.TREE_TALENTED_TRACKER = TREE_TALENTED_TRACKER
ns.TREE_THOROUGH_TANNING = TREE_THOROUGH_TANNING
ns.TREE_GAINFUL_GATHERING = TREE_GAINFUL_GATHERING
