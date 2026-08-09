local _, Addon = ...

local Logic = {}
Addon.ActionBarsLogic = Logic

Logic.GROUP_ORDER = {
    "normal",
    "attack_cd",
    "def_cd",
    "heal",
    "utility",
    "interrupt",
    "movement",
    "item",
    "custom_1",
    "custom_2",
    "custom_3",
    "custom_4",
    "none",
}

Logic.DEFAULT_COLORS = {
    normal = { 0.72, 0.76, 0.82, 0.98 },
    attack_cd = { 1.00, 0.48, 0.12, 0.98 },
    def_cd = { 0.20, 1.00, 0.48, 0.98 },
    heal = { 0.95, 0.95, 0.48, 0.98 },
    utility = { 0.25, 0.62, 1.00, 0.98 },
    interrupt = { 1.00, 0.22, 0.20, 0.98 },
    movement = { 0.18, 0.95, 0.92, 0.98 },
    item = { 0.72, 0.42, 1.00, 0.98 },
    custom_1 = { 0.36, 0.86, 1.00, 0.98 },
    custom_2 = { 0.62, 0.52, 1.00, 0.98 },
    custom_3 = { 1.00, 0.62, 0.84, 0.98 },
    custom_4 = { 1.00, 0.72, 0.46, 0.98 },
    none = { 0.32, 0.32, 0.34, 0.48 },
}

Logic.COLOR_PALETTE = {
    { 0.92, 0.92, 0.92, 0.98 },
    { 0.72, 0.76, 0.82, 0.98 },
    { 0.48, 0.52, 0.60, 0.98 },
    { 0.25, 0.62, 1.00, 0.98 },
    { 0.18, 0.95, 0.92, 0.98 },
    { 0.72, 0.42, 1.00, 0.98 },
    { 0.98, 0.38, 0.70, 0.98 },
    { 1.00, 0.22, 0.20, 0.98 },
    { 1.00, 0.48, 0.12, 0.98 },
    { 1.00, 0.82, 0.20, 0.98 },
    { 0.45, 0.90, 0.34, 0.98 },
    { 0.20, 1.00, 0.48, 0.98 },
    { 0.86, 0.70, 0.42, 0.98 },
}

local VALID_GROUPS = {}
for _, groupKey in ipairs(Logic.GROUP_ORDER) do
    VALID_GROUPS[groupKey] = true
end

local COMMON_SPELL_GROUPS = {
    interrupt = {
        1766, 6552, 2139, 47528, 57994, 78675, 96231, 106839, 116705,
        147362, 183752, 187707, 19647, 351338,
    },
    movement = {
        100, 781, 1850, 1953, 2983, 6544, 36554, 48020, 58875, 109132,
        190784, 192063, 195457, 198793, 212552,
    },
    def_cd = {
        498, 642, 871, 22812, 31224, 48707, 48792, 104773, 108271,
        108416, 110959, 118038, 122783, 184364, 186265, 196555, 198589,
    },
    heal = {
        17, 139, 596, 633, 774, 1064, 2050, 2060, 2061, 5185, 8004,
        8936, 19750, 20473, 33076, 48438, 82326, 85673, 115175, 115310,
        116670, 116680, 119611, 124682, 183998, 18562, 212051, 360995,
        361469, 367226, 370888, 382614,
    },
    utility = {
        527, 633, 694, 853, 1022, 1044, 20484, 106898, 108199, 115750,
        116844, 116849, 186257, 197214, 212295,
    },
}

local CLASS_SPELL_GROUPS = {
    PALADIN = {
        attack_cd = { 31884, 231895, 255937, 343527, 343721, 375576, 406086 },
        def_cd = { 498, 633, 642, 86659, 184662, 204018, 205191, 31850 },
        heal = { 633, 19750, 20473, 82326, 85673, 85222, 114165, 156910, 183998 },
        utility = { 853, 1022, 1044, 694, 115750, 20066, 20473, 210256, 24275, 4987 },
        interrupt = { 96231 },
        movement = { 190784 },
    },
    WARRIOR = {
        attack_cd = { 107574, 1719, 262161 },
        def_cd = { 118038, 12975, 184364, 23920, 871 },
        utility = { 5246, 64382, 97462, 3411 },
        interrupt = { 6552 },
        movement = { 100, 6544 },
    },
    MAGE = {
        attack_cd = { 12042, 12472, 190319 },
        def_cd = { 45438, 110959, 235450, 414658 },
        utility = { 118, 122, 475, 55342 },
        interrupt = { 2139 },
        movement = { 1953, 212653 },
    },
    PRIEST = {
        attack_cd = { 10060, 194249, 34433 },
        def_cd = { 19236, 33206, 47585, 47788 },
        heal = { 17, 139, 596, 2050, 2060, 2061, 33076, 34861, 47788, 64843, 64901 },
        utility = { 527, 73325, 8122, 32375 },
        interrupt = { 15487 },
        movement = { 121536 },
    },
    ROGUE = {
        attack_cd = { 121471, 13750, 51690, 79140 },
        def_cd = { 1966, 31224, 5277 },
        utility = { 2094, 408, 6770, 1856 },
        interrupt = { 1766 },
        movement = { 2983, 36554, 195457 },
    },
    SHAMAN = {
        attack_cd = { 114050, 114051, 51533 },
        def_cd = { 108271, 198103 },
        heal = { 8004, 1064, 61295, 73685, 77472, 108280 },
        utility = { 192058, 51490, 5394, 98008 },
        interrupt = { 57994 },
        movement = { 58875, 192063 },
    },
    DRUID = {
        attack_cd = { 102543, 102560, 106951, 194223 },
        def_cd = { 22812, 61336, 102342 },
        heal = { 774, 8936, 5185, 48438, 18562, 33763, 102342, 102351, 145205, 155777 },
        utility = { 102359, 20484, 2782, 5211 },
        interrupt = { 106839, 78675 },
        movement = { 1850, 252216, 77764 },
    },
    DEATHKNIGHT = {
        attack_cd = { 275699, 42650, 49206 },
        def_cd = { 48707, 48792, 49039, 55233 },
        utility = { 49576, 51052, 108199 },
        interrupt = { 47528 },
        movement = { 48265 },
    },
    HUNTER = {
        attack_cd = { 193530, 19574, 266779, 288613 },
        def_cd = { 186265, 109304 },
        utility = { 187650, 19577, 34477 },
        interrupt = { 147362, 187707 },
        movement = { 186257, 781 },
    },
    WARLOCK = {
        attack_cd = { 1122, 113858, 113860, 205180, 265187 },
        def_cd = { 104773, 108416 },
        utility = { 5782, 6789, 30283 },
        interrupt = { 19647 },
        movement = { 48020 },
    },
    MONK = {
        attack_cd = { 123904, 137639, 152173 },
        def_cd = { 115203, 122278, 122783, 122470, 116849 },
        heal = { 115175, 116670, 116680, 116694, 119611, 124682, 191837, 322101 },
        utility = { 115078, 116844, 119381 },
        interrupt = { 116705 },
        movement = { 109132, 115008 },
    },
    DEMONHUNTER = {
        attack_cd = { 191427, 258860 },
        def_cd = { 187827, 196555, 198589 },
        utility = { 179057, 202137, 207684 },
        interrupt = { 183752 },
        movement = { 195072, 198793 },
    },
    EVOKER = {
        attack_cd = { 375087, 375796, 403631 },
        def_cd = { 363916, 374348, 374227 },
        heal = { 355913, 357170, 360995, 361469, 363534, 364343, 367226, 370888, 382614 },
        utility = { 360806, 370665, 374251 },
        interrupt = { 351338 },
        movement = { 358267, 370553 },
    },
}

local function validColor(color)
    return type(color) == "table"
        and tonumber(color[1]) ~= nil
        and tonumber(color[2]) ~= nil
        and tonumber(color[3]) ~= nil
end

function Logic:IsGroup(groupKey)
    return VALID_GROUPS[groupKey] == true
end

function Logic:NormalizeStore(store)
    store = type(store) == "table" and store or {}
    store.version = 1
    store.slotOverrides = type(store.slotOverrides) == "table" and store.slotOverrides or {}
    store.actionOverrides = type(store.actionOverrides) == "table" and store.actionOverrides or {}
    store.groupColors = type(store.groupColors) == "table" and store.groupColors or {}

    for key, groupKey in pairs(store.slotOverrides) do
        if type(key) ~= "string" or not VALID_GROUPS[groupKey] then
            store.slotOverrides[key] = nil
        end
    end
    for key, groupKey in pairs(store.actionOverrides) do
        if type(key) ~= "string" or not VALID_GROUPS[groupKey] then
            store.actionOverrides[key] = nil
        end
    end
    for groupKey, color in pairs(store.groupColors) do
        if not VALID_GROUPS[groupKey] or not validColor(color) then
            store.groupColors[groupKey] = nil
        else
            for index = 1, 4 do
                color[index] = math.max(0, math.min(1, tonumber(color[index]) or (index == 4 and 1 or 0)))
            end
        end
    end
    return store
end

function Logic:GetGroupColor(store, groupKey)
    store = self:NormalizeStore(store)
    groupKey = VALID_GROUPS[groupKey] and groupKey or "normal"
    return store.groupColors[groupKey] or self.DEFAULT_COLORS[groupKey]
end

function Logic:CycleGroup(current)
    local currentIndex = 0
    for index, groupKey in ipairs(self.GROUP_ORDER) do
        if groupKey == current then currentIndex = index break end
    end
    return self.GROUP_ORDER[(currentIndex % #self.GROUP_ORDER) + 1]
end

function Logic:CycleColor(store, groupKey)
    store = self:NormalizeStore(store)
    if not VALID_GROUPS[groupKey] then return nil end
    local current = self:GetGroupColor(store, groupKey)
    local currentIndex = 0
    for index, color in ipairs(self.COLOR_PALETTE) do
        if math.abs(color[1] - current[1]) < 0.01
            and math.abs(color[2] - current[2]) < 0.01
            and math.abs(color[3] - current[3]) < 0.01
        then
            currentIndex = index
            break
        end
    end
    local nextColor = self.COLOR_PALETTE[(currentIndex % #self.COLOR_PALETTE) + 1]
    store.groupColors[groupKey] = { nextColor[1], nextColor[2], nextColor[3], nextColor[4] }
    return store.groupColors[groupKey]
end

function Logic:BuildSpellGroupLookup(classTag)
    local lookup = {}
    local function add(groupKey, spellIDs)
        for _, spellID in ipairs(spellIDs or {}) do
            lookup[tonumber(spellID)] = groupKey
        end
    end
    for _, groupKey in ipairs({ "interrupt", "movement", "def_cd", "utility", "heal" }) do
        add(groupKey, COMMON_SPELL_GROUPS[groupKey])
    end
    local classGroups = CLASS_SPELL_GROUPS[classTag]
    if classGroups then
        for _, groupKey in ipairs({ "attack_cd", "def_cd", "heal", "utility", "interrupt", "movement" }) do
            add(groupKey, classGroups[groupKey])
        end
    end
    return lookup
end

function Logic:Classify(actionType, actionID, spellLookup)
    if actionType == "item" then return "item" end
    if actionType == "spell" then
        return type(spellLookup) == "table" and spellLookup[tonumber(actionID)] or nil
    end
    if actionType == "flyout" or actionType == "pet" or actionType == "stance"
        or actionType == "possess"
    then
        return "utility"
    end
    return nil
end

function Logic:ResolveGroup(entry, store, autoClassify)
    store = self:NormalizeStore(store)
    if type(entry) ~= "table" then return "none", "auto" end
    local slotGroup = entry.slotKey and store.slotOverrides[entry.slotKey] or nil
    if VALID_GROUPS[slotGroup] then return slotGroup, "slot" end
    local actionGroup = entry.semanticKey and store.actionOverrides[entry.semanticKey] or nil
    if VALID_GROUPS[actionGroup] then return actionGroup, "action" end
    if autoClassify ~= false and VALID_GROUPS[entry.autoGroup] then
        return entry.autoGroup, "auto"
    end
    return entry.empty == true and "none" or "normal", "auto"
end

