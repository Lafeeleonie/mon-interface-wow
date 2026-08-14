local _, Addon = ...

local FEATURE_ID = "gathering_nodes"
local PIN_TEMPLATE = "VaultloomGatheringNodeWorldMapPinTemplate"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MASK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ASSET_ROOT = "Interface\\AddOns\\" .. Addon.Identity.addonName .. "\\Assets\\"
local MINIMAP_RING = ASSET_ROOT .. "gathering_pin_ring.tga"
local BASE_WORLD_PIN_SIZE = 17
local BASE_MINIMAP_PIN_SIZE = 14
local LAUNCHER_MINIMAP_DEFAULT_ANGLE = 135
local LAUNCHER_MINIMAP_RADIUS_OFFSET = 7
local MINIMAP_POSITION_INTERVAL = 1 / 60
local MINIMAP_POSITION_INTERVAL_MEDIUM = 1 / 30
local MINIMAP_POSITION_INTERVAL_DENSE = 1 / 20
local MINIMAP_MEDIUM_PIN_COUNT = 32
local MINIMAP_DENSE_PIN_COUNT = 64
local MINIMAP_FULL_INTERVAL = 1.0
local MINIMAP_IDLE_INTERVAL = 1.0
local MINIMAP_RANGE_FACTOR = 0.74
local MINIMAP_RETRY_DELAYS = { 0.25, 0.75, 1.50 }
local MAP_GEOMETRY_CACHE = {}
local RECENT_GATHER_SECONDS = 10
local RECENT_LOOT_SECONDS = 1.5

local LAUNCHER_MINIMAP_SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local Logic = Addon.GatheringNodesLogic
local unpackColor = table.unpack or unpack

local DEFAULTS = {
    world_map = true,
    minimap = true,
    world_scale_percent = 100,
    minimap_scale_percent = 100,
    show_mining = true,
    show_herbalism = true,
    show_leather = true,
    show_wood = true,
    show_fish = true,
    show_cooking = true,
    only_current_professions = false,
    launcher_mode = "minimap",
    locked = false,
}

local KINDS = {
    mining = {
        icon = 136248,
        color = { 0.92, 0.72, 0.36, 1 },
        skillLines = { [186] = true },
        spells = { [2575] = true, [195122] = true, [423341] = true, [471013] = true },
    },
    herbalism = {
        icon = 136065,
        color = { 0.38, 0.86, 0.42, 1 },
        skillLines = { [182] = true },
        spells = { [2366] = true },
    },
    leather = {
        icon = 134366,
        color = { 0.78, 0.52, 0.30, 1 },
        skillLines = { [165] = true, [393] = true },
        spells = {},
    },
    wood = {
        icon = 134063,
        color = { 0.60, 0.42, 0.22, 1 },
        skillLines = {},
        spells = {},
    },
    fish = {
        icon = 133889,
        color = { 0.34, 0.70, 0.96, 1 },
        skillLines = { [356] = true },
        spells = {},
    },
    cooking = {
        icon = 133971,
        color = { 0.95, 0.54, 0.28, 1 },
        skillLines = { [185] = true },
        spells = {},
    },
}

local FISHING_SPELLS = {
    [7620] = true,
    [131474] = true,
}

local LEGACY_ICON_NAMES = {
    herbalism = {
        "aethril", "akundas_bite", "anchor_weed", "ancient_lichen", "arathorsspear",
        "argentleaf", "arthas_tears", "astralglory", "azeroot", "black_lotus",
        "blessing", "blindweed", "briarthorn", "bruiseweed", "bubblepoppy",
        "cinderbloom", "deathblossom", "dreamfoil", "dreaming_glory", "dreamleaf",
        "earthroot", "fadeleaf", "felweed", "felwort", "firebloom", "fjarnskaggl",
        "fools_cap", "foxflower", "ghost_mushroom", "goldclover", "goldthorn",
        "grave_moss", "green_tea_leaf", "gromsblood", "heartblossom", "hochenblume",
        "icecap", "icethorn", "khadgars_whisker", "kingsblood", "liferoot",
        "luredrop", "mageroyal", "mana_thistle", "manalily", "marrowroot",
        "mycobloom", "netherbloom", "nightmare_vine", "nightshade", "orbinid",
        "peacebloom", "phantombloom", "plaguebloom", "purple_lotus", "rain_poppy",
        "risingglory", "riverbud", "sanguithorn", "saxifrage", "seastalk", "shaherb",
        "silkweed", "silverleaf", "sirens_pollen", "snow_lily", "star_moss",
        "starlightrose", "stormvine", "stranglekelp", "sungrass", "terocone",
        "tigerlily", "tranquilitybloom", "twilightjasmine", "vigilstorch", "whiptail",
        "widowbloom", "wild_steelbloom", "winters_kiss", "wintersbite", "writhebark",
        "zinanthid",
    },
    mining = {
        "adamantium", "aqirite", "bismuth", "blackrock", "brilliantsilver", "cobalt",
        "copper", "darkiron", "draconium", "elementium", "elethium", "empyrium",
        "feliron", "felslate", "ghostiron", "gold", "iron", "ironclaw", "karesh",
        "khorium", "kyparite", "laestrite", "leystone", "mithril", "monelite",
        "obsidian", "osmenite", "oxxein", "phaedrite", "platinum", "pyrite",
        "refulgentcopper", "saronite", "serevite", "silver", "sinvyr", "solenium",
        "stormsilver", "thorium", "tin", "titanium", "trueiron", "truesilver",
        "umbraltin", "white_trillium",
    },
}

local function getLegacyIcon(kind, name)
    local names = LEGACY_ICON_NAMES[kind]
    if not names then return nil end
    local compact = Logic:NormalizeText(name):gsub("[^%w]", "")
    if compact == "" then return nil end
    local bestName, bestLength
    for _, fileName in ipairs(names) do
        local key = fileName:gsub("_", "")
        if compact:find(key, 1, true) and (not bestLength or #key > bestLength) then
            bestName, bestLength = fileName, #key
        end
    end
    if not bestName then return nil end
    local folder = kind == "mining" and "Mine" or "Herb"
    return ASSET_ROOT .. "GatheringNodes\\" .. folder .. "\\" .. bestName .. ".tga"
end

local REAGENT_SUBCLASS_ENUM_KEYS = {
    leather = { "Leather" },
    mining = { "MetalStone", "MetalAndStone", "Metal" },
    herbalism = { "Herb", "Herbalism" },
    cooking = { "Cooking" },
}

local REAGENT_SUBCLASS_GLOBAL_KEYS = {
    leather = { "LE_ITEM_TRADEGOODS_LEATHER" },
    mining = { "LE_ITEM_TRADEGOODS_METAL_AND_STONE" },
    herbalism = { "LE_ITEM_TRADEGOODS_HERB" },
    cooking = { "LE_ITEM_TRADEGOODS_COOKING" },
}

local function getReagentSubclassKind(subClassID)
    subClassID = tonumber(subClassID)
    if not subClassID then return nil end

    local reagentSubclass = Enum and Enum.ItemReagentSubclass
    for _, kind in ipairs({ "leather", "mining", "herbalism", "cooking" }) do
        for _, key in ipairs(REAGENT_SUBCLASS_ENUM_KEYS[kind]) do
            if type(reagentSubclass) == "table"
                and tonumber(reagentSubclass[key]) == subClassID
            then
                return kind
            end
        end
        for _, key in ipairs(REAGENT_SUBCLASS_GLOBAL_KEYS[kind]) do
            if tonumber(_G[key]) == subClassID then return kind end
        end
    end
    return nil
end

local Runtime = {
    enabled = false,
    provider = nil,
    providerAdded = false,
    store = nil,
    index = nil,
    currentProfessions = {},
    pendingCast = nil,
    recentGather = nil,
    recentNode = nil,
    recentFishingAt = nil,
    recentLoot = {},
    minimapPins = {},
    minimapPool = {},
    miniButton = nil,
    minimapButton = nil,
    pendingItemNames = {},
    refreshGeneration = 0,
    minimapRefreshGeneration = 0,
    minimapRetryAttempt = 0,
    minimapIdleGeneration = 0,
    minimapIdleTimer = nil,
    lastWorldPinCount = 0,
    worldPinCache = nil,
}

Addon.GatheringNodes = Runtime

local function now()
    if type(GetTimePreciseSec) == "function" then return tonumber(GetTimePreciseSec()) or 0 end
    if type(GetTime) == "function" then return tonumber(GetTime()) or 0 end
    return 0
end

local function setting(key)
    local state = Addon.FeatureRegistry:GetState(FEATURE_ID)
    local value = state.settings[key]
    return value == nil and DEFAULTS[key] or value
end

local function getKindLabel(kind)
    return Addon.L["GATHERING_KIND_" .. string.upper(tostring(kind or ""))]
        or tostring(kind or "")
end

local function getKindColor(kind)
    return KINDS[kind] and KINDS[kind].color or { 1, 0.82, 0.24, 1 }
end

local function getKindIcon(kind)
    return KINDS[kind] and KINDS[kind].icon or 134400
end

local function getCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
    if type(identity) == "table" and type(identity.key) == "string" and identity.key ~= "" then
        return identity.key
    end
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    if type(name) == "string" and name ~= "" and type(realm) == "string" and realm ~= "" then
        return Addon.WoWApi:BuildCharacterKey(name, realm)
    end
    return "current"
end

local function getXY(vector)
    if not vector then return nil, nil end
    if type(vector.GetXY) == "function" then
        local ok, x, y = pcall(vector.GetXY, vector)
        if ok then return tonumber(x), tonumber(y) end
    end
    return tonumber(vector.x), tonumber(vector.y)
end

local function getUnitWorldPosition()
    if type(UnitPosition) ~= "function" then return nil end
    local ok, worldY, worldX, _, instanceID = pcall(UnitPosition, "player")
    worldX, worldY, instanceID = tonumber(worldX), tonumber(worldY), tonumber(instanceID)
    if not ok or not worldX or not worldY or not instanceID then return nil end
    return worldX, worldY, instanceID
end

local function anchorSnapshotToUnitPosition(snapshot)
    if type(snapshot) ~= "table" then return false end
    local worldX, worldY, instanceID = getUnitWorldPosition()
    snapshot.worldAnchorX = worldX
    snapshot.worldAnchorY = worldY
    snapshot.worldInstanceID = instanceID
    snapshot.worldAnchorMapX = worldX and snapshot.x or nil
    snapshot.worldAnchorMapY = worldY and snapshot.y or nil
    return worldX ~= nil
end

local function isInInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inInstance = pcall(IsInInstance)
    return ok and inInstance == true
end

local function getMapGeometry(mapID)
    mapID = tonumber(mapID)
    if not mapID then return nil, nil end
    local cached = MAP_GEOMETRY_CACHE[mapID]
    if cached then return cached.width, cached.height end
    if not C_Map or type(C_Map.GetMapWorldSize) ~= "function" then return nil, nil end

    local okSize, mapWidth, mapHeight = pcall(C_Map.GetMapWorldSize, mapID)
    if not okSize then return nil, nil end
    local width, height = tonumber(mapWidth), tonumber(mapHeight)
    if not width or width <= 0 or not height or height <= 0 then return nil, nil end

    MAP_GEOMETRY_CACHE[mapID] = { width = width, height = height }
    return width, height
end

local function getMapSnapshot(reuse)
    if isInInstance() or not C_Map
        or type(C_Map.GetBestMapForUnit) ~= "function"
        or type(C_Map.GetPlayerMapPosition) ~= "function"
    then
        return nil
    end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = okMap and tonumber(mapID) or nil
    if not mapID then return nil end
    local okPosition, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if okPosition then x, y = getXY(position) end
    if not x or not y or x <= 0 or x > 1 or y <= 0 or y > 1 then return nil end

    local width, height = getMapGeometry(mapID)
    local result = type(reuse) == "table" and reuse or {}
    result.mapID = mapID
    result.x = x
    result.y = y
    result.width = width
    result.height = height
    result.positionSource = "map"
    anchorSnapshotToUnitPosition(result)
    return result
end

local function updateMapSnapshotPosition(snapshot)
    if type(snapshot) ~= "table" or not snapshot.mapID or not C_Map
        or type(C_Map.GetPlayerMapPosition) ~= "function"
    then
        return nil
    end
    local worldX, worldY, instanceID = getUnitWorldPosition()
    if worldX and worldY
        and instanceID == snapshot.worldInstanceID
        and snapshot.worldAnchorX and snapshot.worldAnchorY
        and snapshot.worldAnchorMapX and snapshot.worldAnchorMapY
        and snapshot.width and snapshot.width > 0
        and snapshot.height and snapshot.height > 0
    then
        local x = snapshot.worldAnchorMapX
            - ((worldX - snapshot.worldAnchorX) / snapshot.width)
        local y = snapshot.worldAnchorMapY
            - ((worldY - snapshot.worldAnchorY) / snapshot.height)
        if x > 0 and x <= 1 and y > 0 and y <= 1 then
            snapshot.x = x
            snapshot.y = y
            snapshot.positionSource = "unit"
            return snapshot
        end
    end
    local okPosition, position = pcall(C_Map.GetPlayerMapPosition, snapshot.mapID, "player")
    local x, y
    if okPosition then x, y = getXY(position) end
    if not x or not y or x <= 0 or x > 1 or y <= 0 or y > 1 then return nil end
    snapshot.x = x
    snapshot.y = y
    snapshot.positionSource = "map"
    anchorSnapshotToUnitPosition(snapshot)
    return snapshot
end

local function parseItemID(value)
    return tonumber(value) or tonumber(tostring(value or ""):match("item:(%d+)"))
end

local function getItemInfo(value, fallbackName, fallbackIcon)
    local itemID = parseItemID(value)
    if not itemID then return nil end
    local name, link, icon, classID, subClassID, subType
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, itemName, itemLink, _, _, _, _, itemSubType, _, _, itemIcon, _, itemClassID, itemSubClassID =
            pcall(C_Item.GetItemInfo, value)
        if ok then
            name, link, subType, icon, classID, subClassID =
                itemName, itemLink, itemSubType, itemIcon, itemClassID, itemSubClassID
        end
    elseif type(GetItemInfo) == "function" then
        local ok, itemName, itemLink, _, _, _, _, itemSubType, _, _, itemIcon, _, itemClassID, itemSubClassID =
            pcall(GetItemInfo, value)
        if ok then
            name, link, subType, icon, classID, subClassID =
                itemName, itemLink, itemSubType, itemIcon, itemClassID, itemSubClassID
        end
    end
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, instantID, _, instantSubType, _, instantIcon, instantClassID, instantSubClassID =
            pcall(C_Item.GetItemInfoInstant, value)
        if ok then
            itemID = tonumber(instantID) or itemID
            subType = subType or instantSubType
            icon = icon or instantIcon
            classID = tonumber(classID) or tonumber(instantClassID)
            subClassID = tonumber(subClassID) or tonumber(instantSubClassID)
        end
    end
    if not icon and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, itemIcon = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = itemIcon end
    end
    if not name and type(fallbackName) == "string" then name = fallbackName end
    return {
        itemID = itemID,
        name = name,
        link = link or (type(value) == "string" and value or nil),
        icon = icon or fallbackIcon,
        classID = classID,
        subClassID = subClassID,
        subType = subType,
    }
end

local function getCurrentClientItemName(resource)
    local itemID = parseItemID(type(resource) == "table" and resource.itemID or resource)
    if not itemID then return nil end

    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, name = pcall(function()
            local value = C_Item.GetItemNameByID(itemID)
            return type(value) == "string" and value ~= "" and value or nil
        end)
        if ok and name then
            Runtime.pendingItemNames[itemID] = nil
            return name
        end
    end

    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, name = pcall(function()
            local value = C_Item.GetItemInfo(itemID)
            return type(value) == "string" and value ~= "" and value or nil
        end)
        if ok and name then
            Runtime.pendingItemNames[itemID] = nil
            return name
        end
    end

    if not Runtime.pendingItemNames[itemID]
        and C_Item and type(C_Item.RequestLoadItemDataByID) == "function"
    then
        Runtime.pendingItemNames[itemID] = true
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return nil
end

local function getDisplayResourceName(resource)
    if type(resource) ~= "table" then return "" end
    return getCurrentClientItemName(resource)
        or resource.name
        or resource.nodeName
        or getKindLabel(resource.kind)
end

local function getLootSlotItem(slotIndex)
    if type(GetLootSlotLink) ~= "function" then return nil end
    local okLink, itemLink = pcall(GetLootSlotLink, slotIndex)
    if not okLink or not itemLink then return nil end
    local name, icon
    if type(GetLootSlotInfo) == "function" then
        local okInfo, texture, itemName = pcall(GetLootSlotInfo, slotIndex)
        if okInfo then icon, name = texture, itemName end
    end
    return getItemInfo(itemLink, name, icon)
end

local function parseChatLoot(text)
    if type(text) ~= "string" then return nil end
    local link = text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        or text:match("(|Hitem:.-|h%[.-%]|h)")
    if not link then return nil end
    local name = link:match("%[([^%]]+)%]")
    return getItemInfo(link, name)
end

local function getTooltipTargetName()
    local tooltip = _G.GameTooltip
    if not tooltip or (type(tooltip.IsShown) == "function" and not tooltip:IsShown()) then return nil end
    local firstLine = tooltip.TextLeft1
    local text = firstLine and type(firstLine.GetText) == "function" and firstLine:GetText() or nil
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or nil
    return text ~= "" and text or nil
end

local function addCircularMask(owner, texture, key)
    if not owner or not texture or owner[key] then return end
    if type(owner.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then return end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    owner[key] = mask
end

function Runtime:GetStore()
    local db = Addon.Database:Get()
    db.features.gatheringNodes = type(db.features.gatheringNodes) == "table"
        and db.features.gatheringNodes or {}
    local root = db.features.gatheringNodes
    if type(root.data) ~= "table" and type(root.maps) == "table" then
        root.data = {
            version = tonumber(root.version) or 1,
            maps = root.maps,
        }
        root.maps = nil
    end
    root.data = type(root.data) == "table" and root.data or { version = Logic.schemaVersion, maps = {} }
    root.hiddenByCharacter = type(root.hiddenByCharacter) == "table" and root.hiddenByCharacter or {}
    root.displayEnabled = root.displayEnabled ~= false
    root.button = type(root.button) == "table" and root.button or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 410,
        y = -92,
        scale = 1,
    }
    root.minimapButton = type(root.minimapButton) == "table" and root.minimapButton or {}
    root.minimapButton.angle = tonumber(root.minimapButton.angle) or LAUNCHER_MINIMAP_DEFAULT_ANGLE
    return root
end

function Runtime:PrepareStore()
    local root = self:GetStore()
    root.data = Logic:CreateStore(root.data)
    self.store = root.data
    self.index = Logic:BuildIndex(self.store)
    self:InvalidateWorldPinCache()
    return self.store
end

function Runtime:InvalidateWorldPinCache()
    self.worldPinCache = nil
end

function Runtime:GetHiddenStore()
    local root = self:GetStore()
    local characterKey = getCharacterKey()
    if self.hiddenCharacterKey == characterKey and type(self.hiddenStore) == "table" then
        return self.hiddenStore
    end
    self:InvalidateWorldPinCache()
    root.hiddenByCharacter[characterKey] = type(root.hiddenByCharacter[characterKey]) == "table"
        and root.hiddenByCharacter[characterKey] or {}
    self.hiddenCharacterKey = characterKey
    self.hiddenStore = root.hiddenByCharacter[characterKey]
    return self.hiddenStore
end

function Runtime:IsDisplayEnabled()
    return self:GetStore().displayEnabled ~= false
end

function Runtime:SetDisplayEnabled(enabled)
    self:GetStore().displayEnabled = enabled == true
    self:RefreshMiniButton()
    self:RequestWorldRefresh(0)
    self:RequestMinimapRefresh(true)
end

function Runtime:IsKindVisible(kind)
    if setting("show_" .. tostring(kind)) ~= true then return false end
    if setting("only_current_professions") == true
        and next(self.currentProfessions)
        and kind ~= "wood"
        and self.currentProfessions[kind] ~= true
    then
        return false
    end
    return true
end

function Runtime:IsNodeVisible(node)
    if type(node) ~= "table" or not self:IsKindVisible(node.kind) then return false end
    local hidden = self:GetHiddenStore()
    return hidden[node.resourceKey] ~= true
end

function Runtime:ScanProfessions()
    self.currentProfessions = {}
    for _, profession in ipairs(Addon.WoWApi:GetCurrentProfessions() or {}) do
        local skillLineID = tonumber(profession.skillLineID)
        for kind, definition in pairs(KINDS) do
            if definition.skillLines[skillLineID] then self.currentProfessions[kind] = true end
        end
    end
    self:InvalidateWorldPinCache()
end

function Runtime:GetVisibleNodes(mapID)
    local result = {}
    for _, node in ipairs(Logic:GetNodesForMap(self.store or self:PrepareStore(), mapID)) do
        if self:IsNodeVisible(node) then result[#result + 1] = node end
    end
    return result
end

function Runtime:AddNode(kind, nodeName, itemInfo, snapshot)
    if self.enabled ~= true or isInInstance() or not Logic:IsValidKind(kind) then return nil end
    snapshot = snapshot or getMapSnapshot()
    if not snapshot then return nil end
    itemInfo = type(itemInfo) == "table" and itemInfo or {}
    local displayName = itemInfo.name or nodeName or getKindLabel(kind)
    local key, added = Logic:AddNode(self.store, self.index, snapshot.mapID, {
        kind = kind,
        itemID = itemInfo.itemID,
        name = displayName,
        nodeName = nodeName,
        icon = itemInfo.icon or getLegacyIcon(kind, nodeName) or getKindIcon(kind),
        x = snapshot.x,
        y = snapshot.y,
    })
    if not key then return nil end
    if (kind == "mining" or kind == "herbalism") and itemInfo.itemID == nil then
        self.recentNode = {
            mapID = snapshot.mapID,
            key = key,
            kind = kind,
            nodeName = nodeName,
            seenAt = now(),
            resolved = false,
        }
    end
    if added then
        self:NotifyDataChanged()
    else
        self:InvalidateWorldPinCache()
        self:RequestWorldRefresh(0)
        self:RequestMinimapRefresh(true)
    end
    return key, added
end

function Runtime:ResolveRecentNode(itemInfo)
    local recent = self.recentNode
    if type(recent) ~= "table" or now() - (tonumber(recent.seenAt) or 0) > RECENT_GATHER_SECONDS then
        return false
    end
    local bucket = self.store and self.store.maps and self.store.maps[tostring(recent.mapID)]
    local node = type(bucket) == "table" and bucket[recent.key] or nil
    if type(node) ~= "table" then return false end
    if itemInfo.classID and tonumber(itemInfo.classID) ~= 7 then return false end
    local kind = Logic:ClassifyLoot(itemInfo, {
        subclassKind = getReagentSubclassKind(itemInfo.subClassID),
    })
    if kind ~= recent.kind then return false end
    node.itemID = itemInfo.itemID or node.itemID
    node.name = itemInfo.name or node.name
    node.icon = itemInfo.icon or node.icon
    recent.resolved = true
    self.recentNode = nil
    self.recentGather = nil
    self:NotifyDataChanged()
    return true
end

function Runtime:GetRecentGatherKind()
    local recent = self.recentGather
    if type(recent) ~= "table"
        or now() - (tonumber(recent.seenAt) or 0) > RECENT_GATHER_SECONDS
    then
        self.recentGather = nil
        return nil
    end
    return Logic:IsValidKind(recent.kind) and recent.kind or nil
end

function Runtime:IsRecentFishing()
    local seenAt = tonumber(self.recentFishingAt)
    return seenAt ~= nil and now() - seenAt >= 0 and now() - seenAt <= RECENT_GATHER_SECONDS
end

function Runtime:IsDuplicateLoot(itemInfo, snapshot)
    if type(itemInfo) ~= "table" or type(snapshot) ~= "table" then return false end
    local signature = string.format(
        "%d:%d:%d:%d",
        tonumber(itemInfo.itemID) or 0,
        tonumber(snapshot.mapID) or 0,
        Logic:QuantizeCoordinate(snapshot.x) or 0,
        Logic:QuantizeCoordinate(snapshot.y) or 0
    )
    local timestamp = now()
    local seenAt = tonumber(self.recentLoot[signature])
    if seenAt and timestamp - seenAt < RECENT_LOOT_SECONDS then return true end
    self.recentLoot[signature] = timestamp
    for key, recordedAt in pairs(self.recentLoot) do
        if timestamp - (tonumber(recordedAt) or 0) > 8 then self.recentLoot[key] = nil end
    end
    return false
end

function Runtime:RecordLoot(itemInfo)
    if self.enabled ~= true or isInInstance() or type(itemInfo) ~= "table" then return false end
    if itemInfo.classID and tonumber(itemInfo.classID) ~= 7 then return false end
    local snapshot = getMapSnapshot()
    if not snapshot then return false end
    if self:ResolveRecentNode(itemInfo) then
        self:IsDuplicateLoot(itemInfo, snapshot)
        return true
    end

    local context = {
        recentFishing = self:IsRecentFishing(),
        subclassKind = getReagentSubclassKind(itemInfo.subClassID),
    }
    local kind = Logic:ClassifyLoot(itemInfo, context)
    if not kind and getLegacyIcon("mining", itemInfo.name) then
        kind = "mining"
    elseif not kind and getLegacyIcon("herbalism", itemInfo.name) then
        kind = "herbalism"
    end
    if not kind then return false end
    if (kind == "mining" or kind == "herbalism")
        and self:GetRecentGatherKind() ~= kind
    then
        return false
    end
    if kind == "fish" and context.recentFishing ~= true then return false end
    if self:IsDuplicateLoot(itemInfo, snapshot) then return false end
    local recorded = self:AddNode(kind, itemInfo.name, itemInfo, snapshot) ~= nil
    if recorded and (kind == "mining" or kind == "herbalism") then
        self.recentGather = nil
    end
    return recorded
end

function Runtime:ScanLootWindow()
    if isInInstance() or type(GetNumLootItems) ~= "function" then return false end
    local ok, count = pcall(GetNumLootItems)
    count = ok and tonumber(count) or 0
    local recorded = false
    for slotIndex = 1, count do
        if self:RecordLoot(getLootSlotItem(slotIndex)) then recorded = true end
    end
    return recorded
end

function Runtime:CapturePendingTarget()
    local pending = self.pendingCast
    if type(pending) ~= "table" or pending.nodeName or isInInstance() then return false end
    local name = getTooltipTargetName()
    if not name or name == pending.spellName or name == getKindLabel(pending.kind) then return false end
    pending.nodeName = name
    return true
end

function Runtime:OnSpellSent(unit, target, castGUID, spellID)
    if unit ~= "player" or isInInstance() then
        self.pendingCast = nil
        return
    end
    spellID = tonumber(spellID)
    if FISHING_SPELLS[spellID] then self.recentFishingAt = now() end
    local kind
    for candidateKind, definition in pairs(KINDS) do
        if definition.spells[spellID] then kind = candidateKind break end
    end
    if not kind then
        self.pendingCast = nil
        return
    end
    local spellName
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then spellName = info.name end
    end
    self.pendingCast = {
        kind = kind,
        spellID = spellID,
        spellName = spellName,
        nodeName = type(target) == "string" and target ~= "" and target or nil,
        castGUID = castGUID,
    }
    self:CapturePendingTarget()
end

function Runtime:OnSpellSucceeded(unit, castGUID, spellID)
    local pending = self.pendingCast
    if unit ~= "player" or type(pending) ~= "table" or isInInstance() then return end
    if pending.castGUID and castGUID and pending.castGUID ~= castGUID then return end
    if pending.spellID and tonumber(spellID) and pending.spellID ~= tonumber(spellID) then return end
    self:CapturePendingTarget()
    self.pendingCast = nil
    self.recentGather = {
        kind = pending.kind,
        seenAt = now(),
    }
    if pending.nodeName then self:AddNode(pending.kind, pending.nodeName) end
end

function Runtime:CancelPendingCast(unit, _, spellID)
    if unit == nil or unit == "player" then
        self.pendingCast = nil
        if FISHING_SPELLS[tonumber(spellID)] then self.recentFishingAt = nil end
    end
end

function Runtime:NotifyDataChanged()
    self:InvalidateWorldPinCache()
    Addon.StateStore:Set("gathering.nodes", {
        total = tonumber(self.index and self.index.total) or 0,
    })
    self:RequestWorldRefresh(0)
    self:RequestMinimapRefresh(true)
    self:RefreshMiniButton()
    if self.manager and self.manager:IsShown() then self:RefreshManager() end
end

local function applyWorldPinVisual(holder, node)
    if not holder or type(node) ~= "table" then return end
    local size = math.max(12, math.floor((BASE_WORLD_PIN_SIZE * setting("world_scale_percent") / 100) + 0.5))
    local color = getKindColor(node.kind)
    holder:SetSize(size, size)
    holder.Ring:SetTexture(WHITE_TEXTURE)
    holder.Ring:SetAllPoints(holder)
    holder.Ring:SetVertexColor(color[1], color[2], color[3], 1)
    addCircularMask(holder, holder.Ring, "ringMask")
    holder.Icon:ClearAllPoints()
    holder.Icon:SetPoint("CENTER")
    holder.Icon:SetSize(math.max(9, size - 4), math.max(9, size - 4))
    holder.Icon:SetTexture(node.icon or getKindIcon(node.kind))
    holder.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    addCircularMask(holder, holder.Icon, "iconMask")
    if holder.Count then
        holder.Count:SetText((tonumber(node.count) or 1) > 1 and tostring(node.count) or "")
    end
end

local basePinMixin = type(MapCanvasPinMixin) == "table" and MapCanvasPinMixin or {}
local PinMixin = type(CreateFromMixins) == "function" and CreateFromMixins(basePinMixin) or {}
_G.VaultloomGatheringNodeWorldMapPinMixin = PinMixin

function PinMixin:SetPassThroughButtons()
end

function PinMixin:CheckMouseButtonPassthrough()
    return false
end

function PinMixin:OnLoad()
    self:SetSize(BASE_WORLD_PIN_SIZE, BASE_WORLD_PIN_SIZE)
    if type(self.RegisterForClicks) == "function" then
        self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    if type(self.UseFrameLevelType) == "function" then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    if type(self.SetScalingLimits) == "function" then self:SetScalingLimits(1, 1, 1.35) end
end

function PinMixin:OnAcquired(node)
    self.node = node
    applyWorldPinVisual(self, node)
    if type(self.SetPosition) == "function" then
        self:SetPosition(Logic:ExpandCoordinate(node.x), Logic:ExpandCoordinate(node.y))
    end
end

function PinMixin:OnReleased()
    self.node = nil
end

function Runtime:AddTooltip(node, minimap)
    if not GameTooltip or type(node) ~= "table" then return end
    local members = type(node.members) == "table" and node.members or { node }
    for index, member in ipairs(members) do
        local color = getKindColor(member.kind)
        GameTooltip:AddLine(getDisplayResourceName(member),
            color[1], color[2], color[3], true)
        if index >= 8 and #members > 8 then
            GameTooltip:AddLine(string.format(Addon.L.GATHERING_TOOLTIP_MORE, #members - 8),
                0.72, 0.70, 0.66, true)
            break
        end
    end
    if #members == 1 then
        GameTooltip:AddLine(getKindLabel(node.kind), 0.76, 0.74, 0.70, true)
    end
    GameTooltip:AddLine(Addon.L.GATHERING_TOOLTIP_WAYPOINT, 0.64, 0.76, 1, true)
    GameTooltip:AddLine(Addon.L.GATHERING_TOOLTIP_DELETE, 0.82, 0.58, 0.34, true)
    if minimap then
        GameTooltip:AddLine(Addon.L.GATHERING_TOOLTIP_MINIMAP, 0.68, 0.72, 0.66, true)
    end
end

function PinMixin:OnMouseEnter()
    if not self.node or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end
    Runtime:AddTooltip(self.node, false)
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function Runtime:SetWaypoint(node)
    if type(node) ~= "table" or not C_Map
        or type(C_Map.SetUserWaypoint) ~= "function"
        or not UiMapPoint or type(UiMapPoint.CreateFromCoordinates) ~= "function"
    then
        return false
    end
    local okPoint, point = pcall(
        UiMapPoint.CreateFromCoordinates,
        tonumber(node.mapID),
        Logic:ExpandCoordinate(node.x),
        Logic:ExpandCoordinate(node.y)
    )
    if not okPoint or not point then return false end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok == true
end

function Runtime:OpenClusterDeleteMenu(owner, node)
    local members = type(node) == "table" and node.members or nil
    if type(members) ~= "table" or #members < 2
        or type(MenuUtil) ~= "table"
        or type(MenuUtil.CreateContextMenu) ~= "function"
    then
        return false
    end

    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        if type(rootDescription.CreateTitle) == "function" then
            rootDescription:CreateTitle(Addon.L.GATHERING_DELETE_TITLE)
        end
        if type(rootDescription.CreateButton) ~= "function" then return end
        for _, member in ipairs(members) do
            local selected = member
            local x = (Logic:ExpandCoordinate(selected.x) or 0) * 100
            local y = (Logic:ExpandCoordinate(selected.y) or 0) * 100
            local label = string.format(
                "%s  (%.1f, %.1f)",
                getDisplayResourceName(selected),
                x,
                y
            )
            rootDescription:CreateButton(label, function()
                Runtime:RemoveNode(selected)
            end)
        end
    end)
    return true
end

function Runtime:RemoveNode(node)
    if type(node) ~= "table" or type(node.members) == "table" then return false end
    if not Logic:RemoveNode(self.store, self.index, node.mapID, node.key) then return false end
    self:NotifyDataChanged()
    return true
end

function Runtime:HandleNodeClick(owner, node, button)
    if type(node) ~= "table" then return false end
    if button == "LeftButton" then
        return self:SetWaypoint(node)
    elseif button == "RightButton" and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        if type(node.members) == "table" then
            return self:OpenClusterDeleteMenu(owner, node)
        end
        return self:RemoveNode(node)
    end
    return false
end

function PinMixin:OnClick(button)
    return Runtime:HandleNodeClick(self, self.node, button)
end

function PinMixin:OnMouseUp(button)
    return self:OnClick(button)
end

function Runtime:CollectWorldPins(mapID)
    mapID = tonumber(mapID)
    local cached = self.worldPinCache
    if mapID and type(cached) == "table" and cached.mapID == mapID then
        return cached.nodes
    end
    local nodes = self:GetVisibleNodes(mapID)
    for _, node in ipairs(nodes) do node.mapID = tonumber(mapID) end
    local clustered = Logic:Cluster(nodes, 90)
    self.worldPinCache = {
        mapID = mapID,
        nodes = clustered,
    }
    return clustered
end

function Runtime:CreateProvider()
    if self.provider then return self.provider end
    if type(MapCanvasDataProviderMixin) ~= "table" then return nil end
    local provider = type(CreateFromMixins) == "function"
        and CreateFromMixins(MapCanvasDataProviderMixin) or {}
    function provider:RemoveAllData()
        local map = type(self.GetMap) == "function" and self:GetMap() or nil
        if map and type(map.RemoveAllPinsByTemplate) == "function" then
            map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
        end
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        Runtime.lastWorldPinCount = 0
        if Runtime.enabled ~= true or Runtime:IsDisplayEnabled() ~= true
            or setting("world_map") ~= true or isInInstance()
        then
            return
        end
        local map = type(self.GetMap) == "function" and self:GetMap() or nil
        local mapID = map and type(map.GetMapID) == "function" and tonumber(map:GetMapID()) or nil
        if not mapID or type(map.AcquirePin) ~= "function" then return end
        for _, node in ipairs(Runtime:CollectWorldPins(mapID)) do
            node.mapID = mapID
            map:AcquirePin(PIN_TEMPLATE, node)
            Runtime.lastWorldPinCount = Runtime.lastWorldPinCount + 1
        end
    end
    self.provider = provider
    return provider
end

function Runtime:EnsureProvider()
    if self.providerAdded then return true end
    local provider = self:CreateProvider()
    if not provider or not Addon.WorldMapPins:AddProvider(provider, self) then return false end
    self.providerAdded = true
    return true
end

function Runtime:RemoveProvider()
    if self.provider then Addon.WorldMapPins:RemoveProvider(self.provider) end
    self.providerAdded = false
    self.lastWorldPinCount = 0
end

function Runtime:RequestWorldRefresh(delay)
    if self.enabled ~= true or not Addon.WorldMapPins:IsShown() then return false end
    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local function refresh()
        if Runtime.enabled ~= true or Runtime.refreshGeneration ~= generation
            or not Addon.WorldMapPins:IsShown()
        then
            return
        end
        if Runtime:EnsureProvider() then Addon.WorldMapPins:RefreshProvider(Runtime.provider) end
    end
    delay = math.max(0, tonumber(delay) or 0)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, refresh)
    else
        refresh()
    end
    return true
end

function Runtime:OnWorldMapShown()
    self:RequestWorldRefresh(0.05)
end

function Runtime:OnWorldMapHidden()
    self.refreshGeneration = self.refreshGeneration + 1
end

function Runtime:OnWorldMapChanged()
    self:RequestWorldRefresh(0.05)
end

function Runtime:RecycleMinimapPins()
    for key, pin in pairs(self.minimapPins) do
        pin:Hide()
        pin.node = nil
        pin.mapX = nil
        pin.mapY = nil
        self.minimapPool[#self.minimapPool + 1] = pin
        self.minimapPins[key] = nil
    end
    self.minimapPinCount = 0
end

function Runtime:CancelMinimapIdleRefresh()
    self.minimapIdleGeneration = (tonumber(self.minimapIdleGeneration) or 0) + 1
    local timer = self.minimapIdleTimer
    self.minimapIdleTimer = nil
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

function Runtime:ScheduleMinimapIdleRefresh()
    if self.minimapIdleTimer or self.enabled ~= true
        or not C_Timer or type(C_Timer.NewTimer) ~= "function"
    then
        return false
    end
    self.minimapIdleGeneration = (tonumber(self.minimapIdleGeneration) or 0) + 1
    local generation = self.minimapIdleGeneration
    self.minimapIdleTimer = C_Timer.NewTimer(MINIMAP_IDLE_INTERVAL, function()
        if Runtime.enabled ~= true or Runtime.minimapIdleGeneration ~= generation then
            return
        end
        Runtime.minimapIdleTimer = nil
        local token = Addon.PerformanceDiagnostics:Begin(
            Runtime,
            "timer",
            "gathering_nodes.idle_minimap"
        )
        Runtime:RefreshMinimap(false)
        Addon.PerformanceDiagnostics:Finish(token)
    end)
    return self.minimapIdleTimer ~= nil
end

function Runtime:ScheduleMinimapRetry()
    if self.enabled ~= true or not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end
    local attempt = (tonumber(self.minimapRetryAttempt) or 0) + 1
    local delay = MINIMAP_RETRY_DELAYS[attempt]
    if not delay then return false end

    self.minimapRetryAttempt = attempt
    local generation = tonumber(self.minimapRefreshGeneration) or 0
    C_Timer.After(delay, function()
        if Runtime.enabled ~= true
            or Runtime.minimapRefreshGeneration ~= generation
        then
            return
        end
        local token = Addon.PerformanceDiagnostics:Begin(
            Runtime,
            "timer",
            "gathering_nodes.minimap_retry"
        )
        Runtime:RefreshMinimap(true)
        Addon.PerformanceDiagnostics:Finish(token)
    end)
    return true
end

function Runtime:RequestMinimapRefresh(force)
    self.minimapRefreshGeneration = (tonumber(self.minimapRefreshGeneration) or 0) + 1
    self.minimapRetryAttempt = 0
    return self:RefreshMinimap(force == true)
end

function Runtime:AcquireMinimapPin(key)
    local pin = self.minimapPins[key]
    if pin then return pin end
    pin = table.remove(self.minimapPool)
    if not pin then
        pin = CreateFrame("Button", nil, Minimap)
        pin:EnableMouse(true)
        pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pin.ring = pin:CreateTexture(nil, "OVERLAY")
        pin.ring:SetAllPoints(pin)
        pin.ring:SetTexture(MINIMAP_RING)
        pin:SetScript("OnEnter", function(selfPin)
            if not selfPin.node or not GameTooltip then return end
            GameTooltip:SetOwner(selfPin, "ANCHOR_LEFT")
            if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end
            Runtime:AddTooltip(selfPin.node, true)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        pin:SetScript("OnClick", function(selfPin, button)
            Runtime:HandleNodeClick(selfPin, selfPin.node, button)
        end)
    end
    pin:SetParent(Minimap)
    pin:SetFrameStrata(type(Minimap.GetFrameStrata) == "function" and Minimap:GetFrameStrata() or "MEDIUM")
    pin:SetFrameLevel((type(Minimap.GetFrameLevel) == "function" and Minimap:GetFrameLevel() or 1) + 2)
    self.minimapPins[key] = pin
    return pin
end

local function getMinimapContext()
    if not Minimap then return nil end
    local radius = 120
    if C_Minimap and type(C_Minimap.GetViewRadius) == "function" then
        local ok, value = pcall(C_Minimap.GetViewRadius)
        if ok then radius = math.max(60, tonumber(value) or radius) end
    end
    local rotate = C_CVar and type(C_CVar.GetCVar) == "function"
        and C_CVar.GetCVar("rotateMinimap") == "1"
    local facing = rotate and type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
    if rotate and not facing then return nil end
    return {
        radius = radius,
        range = radius * MINIMAP_RANGE_FACTOR,
        halfWidth = (type(Minimap.GetWidth) == "function" and Minimap:GetWidth() or 140) / 2,
        halfHeight = (type(Minimap.GetHeight) == "function" and Minimap:GetHeight() or 140) / 2,
        rotate = rotate,
        facing = facing,
        sinFacing = facing and math.sin(facing) or nil,
        cosFacing = facing and math.cos(facing) or nil,
    }
end

local function minimapDistance(snapshot, node, pin)
    if not snapshot or not snapshot.width or not snapshot.height then return nil, nil end
    local x = pin and pin.mapX or Logic:ExpandCoordinate(node.x)
    local y = pin and pin.mapY or Logic:ExpandCoordinate(node.y)
    if not x or not y then return nil, nil end
    return (x - snapshot.x) * snapshot.width, (y - snapshot.y) * snapshot.height
end

function Runtime:PositionMinimapPin(pin, node, snapshot, context, refreshVisual)
    refreshVisual = refreshVisual == true or pin.node ~= node or not pin.mapX or not pin.mapY
    if refreshVisual then
        pin.mapX = Logic:ExpandCoordinate(node.x)
        pin.mapY = Logic:ExpandCoordinate(node.y)
    end
    local xDistance, yDistance = minimapDistance(snapshot, node, pin)
    if not xDistance or not yDistance then return false end
    local distanceSquared = (xDistance * xDistance) + (yDistance * yDistance)
    if distanceSquared > context.range * context.range then return false end

    if context.rotate then
        local x, y = xDistance, yDistance
        xDistance = x * context.cosFacing + y * context.sinFacing
        yDistance = -x * context.sinFacing + y * context.cosFacing
    end

    if refreshVisual then
        local size = math.max(10, math.floor(
            (BASE_MINIMAP_PIN_SIZE * setting("minimap_scale_percent") / 100) + 0.5
        ))
        local color = getKindColor(node.kind)
        pin.node = node
        pin:SetSize(size, size)
        pin.ring:SetVertexColor(color[1], color[2], color[3], 0.96)
        pin:SetAlpha(1)
        pin:Show()
    end
    pin:ClearAllPoints()
    pin:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        (xDistance / context.radius) * context.halfWidth,
        -(yDistance / context.radius) * context.halfHeight
    )
    return true
end

function Runtime:RefreshMinimap(force)
    if self.enabled ~= true or self:IsDisplayEnabled() ~= true
        or setting("minimap") ~= true or not Minimap
        or (type(Minimap.IsVisible) == "function" and not Minimap:IsVisible())
        or isInInstance()
    then
        self.minimapTrackingNeeded = false
        self.minimapContext = nil
        self.minimapLastLayoutX = nil
        self.minimapLastLayoutY = nil
        self.minimapLastLayoutFacing = nil
        self:RecycleMinimapPins()
        self:RefreshUpdateFrame()
        return
    end
    local snapshot = getMapSnapshot(self.minimapSnapshot)
    local context = snapshot and getMinimapContext() or nil
    if not snapshot or not context or not snapshot.width or not snapshot.height then
        self.minimapTrackingNeeded = false
        self.minimapContext = nil
        self.minimapLastLayoutX = nil
        self.minimapLastLayoutY = nil
        self.minimapLastLayoutFacing = nil
        self:RecycleMinimapPins()
        self:RefreshUpdateFrame()
        self:ScheduleMinimapRetry()
        return false
    end
    self.minimapRetryAttempt = 0
    self.minimapSnapshot = snapshot
    self.minimapContext = context
    local mapIndex = self.index and self.index.maps and self.index.maps[snapshot.mapID]
    self.minimapTrackingNeeded = type(mapIndex) == "table"
        and (tonumber(mapIndex.count) or 0) > 0
    local shown = {}
    local xRadius = math.ceil((context.range / snapshot.width) * Logic.coordinateScale)
    local yRadius = math.ceil((context.range / snapshot.height) * Logic.coordinateScale)
    local nearbyNodes = Logic:GetNodesNear(
        self.store,
        self.index,
        snapshot.mapID,
        Logic:QuantizeCoordinate(snapshot.x),
        Logic:QuantizeCoordinate(snapshot.y),
        xRadius,
        yRadius
    )
    for _, node in ipairs(nearbyNodes) do
        node.resourceKey = Logic:GetResourceKey(node.kind, node.itemID, node.name, node.nodeName)
        if self:IsNodeVisible(node) then
            local key = tostring(snapshot.mapID) .. ":" .. tostring(node.key)
            local pin = self:AcquireMinimapPin(key)
            node.mapID = snapshot.mapID
            if self:PositionMinimapPin(pin, node, snapshot, context, true) then shown[pin] = true end
        end
    end
    for key, pin in pairs(self.minimapPins) do
        if not shown[pin] then
            pin:Hide()
            pin.node = nil
            pin.mapX = nil
            pin.mapY = nil
            self.minimapPool[#self.minimapPool + 1] = pin
            self.minimapPins[key] = nil
        end
    end
    local pinCount = 0
    for _ in pairs(self.minimapPins) do pinCount = pinCount + 1 end
    self.minimapPinCount = pinCount
    self.minimapLastLayoutX = snapshot.x
    self.minimapLastLayoutY = snapshot.y
    self.minimapLastLayoutFacing = context.rotate and context.facing or false
    self:RefreshUpdateFrame()
    return true
end

function Runtime:UpdateMinimapPositions()
    if not next(self.minimapPins) then return end
    local snapshot = updateMapSnapshotPosition(self.minimapSnapshot)
    local context = snapshot and self.minimapContext or nil
    if not snapshot or not context then
        self:RecycleMinimapPins()
        return
    end
    local facing = false
    if context.rotate then
        facing = type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
        if not facing then
            self:RecycleMinimapPins()
            return
        end
        context.facing = facing
        context.sinFacing = math.sin(facing)
        context.cosFacing = math.cos(facing)
    end
    if snapshot.x == self.minimapLastLayoutX
        and snapshot.y == self.minimapLastLayoutY
        and facing == self.minimapLastLayoutFacing
    then
        return
    end
    self.minimapLastLayoutX = snapshot.x
    self.minimapLastLayoutY = snapshot.y
    self.minimapLastLayoutFacing = facing
    for key, pin in pairs(self.minimapPins) do
        if not self:PositionMinimapPin(pin, pin.node, snapshot, context, false) then
            pin:Hide()
            pin.node = nil
            pin.mapX = nil
            pin.mapY = nil
            self.minimapPool[#self.minimapPool + 1] = pin
            self.minimapPins[key] = nil
            self.minimapPinCount = math.max(0, (tonumber(self.minimapPinCount) or 1) - 1)
        end
    end
    if self.minimapPinCount == 0 then
        self:RefreshUpdateFrame()
    end
end

function Runtime:GetMinimapPositionInterval()
    local pinCount = tonumber(self.minimapPinCount) or 0
    if pinCount > MINIMAP_DENSE_PIN_COUNT then return MINIMAP_POSITION_INTERVAL_DENSE end
    if pinCount > MINIMAP_MEDIUM_PIN_COUNT then return MINIMAP_POSITION_INTERVAL_MEDIUM end
    return MINIMAP_POSITION_INTERVAL
end

function Runtime:EnsureUpdateFrame()
    if self.updateFrame then return self.updateFrame end
    local frame = CreateFrame("Frame")
    frame.positionElapsed = 0
    frame.fullElapsed = 0
    frame:SetScript("OnUpdate", function(selfFrame, elapsed)
        if Runtime.enabled ~= true then
            selfFrame:Hide()
            return
        end
        elapsed = math.max(0, tonumber(elapsed) or 0)
        selfFrame.positionElapsed = selfFrame.positionElapsed + elapsed
        selfFrame.fullElapsed = selfFrame.fullElapsed + elapsed
        if selfFrame.fullElapsed >= MINIMAP_FULL_INTERVAL then
            selfFrame.fullElapsed = 0
            selfFrame.positionElapsed = 0
            local token = Addon.PerformanceDiagnostics:Begin(
                Runtime,
                "update",
                "gathering_nodes.full_minimap"
            )
            Runtime:RefreshMinimap(false)
            Addon.PerformanceDiagnostics:Finish(token)
        else
            if not next(Runtime.minimapPins) then
                selfFrame.positionElapsed = 0
                return
            end
            local positionInterval = Runtime:GetMinimapPositionInterval()
            if selfFrame.positionElapsed < positionInterval then return end
            selfFrame.positionElapsed = selfFrame.positionElapsed % positionInterval
            local token = Addon.PerformanceDiagnostics:Begin(
                Runtime,
                "update",
                "gathering_nodes.position_minimap"
            )
            Runtime:UpdateMinimapPositions()
            Addon.PerformanceDiagnostics:Finish(token)
        end
    end)
    frame:Hide()
    self.updateFrame = frame
    return frame
end

function Runtime:RefreshUpdateFrame()
    local frame = self:EnsureUpdateFrame()
    local tracking = self.enabled == true and self:IsDisplayEnabled() == true
        and setting("minimap") == true and Minimap
        and (type(Minimap.IsVisible) ~= "function" or Minimap:IsVisible())
        and not isInInstance()
        and self.minimapTrackingNeeded == true
    local hasPins = tracking and (tonumber(self.minimapPinCount) or 0) > 0
        and next(self.minimapPins) ~= nil
    local canSleep = tracking and not hasPins
        and C_Timer and type(C_Timer.NewTimer) == "function"
    if canSleep then
        self:ScheduleMinimapIdleRefresh()
    else
        self:CancelMinimapIdleRefresh()
    end
    local active = tracking and (hasPins or not canSleep)
    frame:SetShown(active == true)
end

local function updateLauncherMinimapPosition(button)
    if not button or not Minimap then return false end
    local position = Runtime:GetStore().minimapButton
    local angleValue = tonumber(position.angle) or LAUNCHER_MINIMAP_DEFAULT_ANGLE
    while angleValue < 0 do angleValue = angleValue + 360 end
    angleValue = angleValue % 360
    position.angle = angleValue

    local angle = math.rad(angleValue)
    local width = type(Minimap.GetWidth) == "function" and Minimap:GetWidth() or 140
    local height = type(Minimap.GetHeight) == "function" and Minimap:GetHeight() or 140
    local radiusX = math.max(54, (tonumber(width) or 140) * 0.5 + LAUNCHER_MINIMAP_RADIUS_OFFSET)
    local radiusY = math.max(54, (tonumber(height) or 140) * 0.5 + LAUNCHER_MINIMAP_RADIUS_OFFSET)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    local roundQuadrants = LAUNCHER_MINIMAP_SHAPES[shape] or LAUNCHER_MINIMAP_SHAPES.ROUND
    if roundQuadrants[quadrant] then
        x, y = x * radiusX, y * radiusY
    else
        local diagonalX = math.sqrt(2 * radiusX * radiusX) - 10
        local diagonalY = math.sqrt(2 * radiusY * radiusY) - 10
        x = math.max(-radiusX, math.min(x * diagonalX, radiusX))
        y = math.max(-radiusY, math.min(y * diagonalY, radiusY))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    return true
end

local function updateLauncherMinimapDrag(button)
    if not button or not Minimap or type(GetCursorPosition) ~= "function"
        or type(Minimap.GetCenter) ~= "function"
    then
        return
    end
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = type(Minimap.GetEffectiveScale) == "function"
        and Minimap:GetEffectiveScale()
        or (UIParent and type(UIParent.GetEffectiveScale) == "function"
            and UIParent:GetEffectiveScale() or 1)
    centerX, centerY, cursorX, cursorY =
        tonumber(centerX), tonumber(centerY), tonumber(cursorX), tonumber(cursorY)
    scale = tonumber(scale) or 1
    if not centerX or not centerY or not cursorX or not cursorY or scale == 0 then return end
    local deltaX = (cursorX / scale) - centerX
    local deltaY = (cursorY / scale) - centerY
    local angle
    if math.atan2 then
        angle = math.deg(math.atan2(deltaY, deltaX))
    elseif deltaX ~= 0 then
        angle = math.deg(math.atan(deltaY / deltaX))
        if deltaX < 0 then angle = angle + 180 end
    else
        angle = deltaY >= 0 and 90 or 270
    end
    if angle < 0 then angle = angle + 360 end
    Runtime:GetStore().minimapButton.angle = angle % 360
    updateLauncherMinimapPosition(button)
end

function Runtime:StoreButtonPosition()
    if not self.miniButton then return end
    local point, _, relativePoint, x, y = self.miniButton:GetPoint(1)
    local data = self:GetStore().button
    data.point = point or "CENTER"
    data.relativePoint = relativePoint or "CENTER"
    data.x = tonumber(x) or 0
    data.y = tonumber(y) or 0
end

function Runtime:ApplyButtonPosition()
    if not self.miniButton then return end
    local data = self:GetStore().button
    self.miniButton:ClearAllPoints()
    self.miniButton:SetPoint(
        data.point or "CENTER",
        UIParent,
        data.relativePoint or "CENTER",
        tonumber(data.x) or 410,
        tonumber(data.y) or -92
    )
    self.miniButton:SetScale(math.max(0.70, math.min(1.40, tonumber(data.scale) or 1)))
end

function Runtime:EnsureMiniButton()
    if self.miniButton then return self.miniButton end
    local button = CreateFrame(
        "Button",
        "VaultloomGatheringNodesButton",
        UIParent,
        BACKDROP_TEMPLATE
    )
    button:SetSize(46, 46)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(20)
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:EnableMouseWheel(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.backplate = button:CreateTexture(nil, "BACKGROUND")
    button.backplate:SetPoint("TOPLEFT", -2, 2)
    button.backplate:SetPoint("BOTTOMRIGHT", 2, -2)
    button.backplate:SetTexture(Addon.Assets.classBackplate)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(37, 37)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexture(getKindIcon("mining"))
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addCircularMask(button, button.icon, "iconMask")

    button.ring = button:CreateTexture(nil, "OVERLAY")
    button.ring:SetPoint("TOPLEFT", -2, 2)
    button.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    button.ring:SetTexture(Addon.Assets.classRing)

    button:SetScript("OnClick", function(_, clicked)
        if clicked == "RightButton" then
            Runtime:ToggleManager()
        else
            Runtime:SetDisplayEnabled(not Runtime:IsDisplayEnabled())
        end
    end)
    button:SetScript("OnDragStart", function(selfButton)
        if setting("locked") == true or (InCombatLockdown and InCombatLockdown()) then return end
        selfButton:StartMoving()
    end)
    button:SetScript("OnDragStop", function(selfButton)
        selfButton:StopMovingOrSizing()
        Runtime:StoreButtonPosition()
    end)
    button:SetScript("OnMouseWheel", function(selfButton, delta)
        if setting("locked") == true
            or (type(IsShiftKeyDown) == "function" and not IsShiftKeyDown())
        then
            return
        end
        local data = Runtime:GetStore().button
        data.scale = math.max(0.70, math.min(1.40,
            (tonumber(data.scale) or 1) + (delta > 0 and 0.05 or -0.05)))
        selfButton:SetScale(data.scale)
    end)
    button:SetScript("OnEnter", function(selfButton)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Addon.L.FEATURE_GATHERING_NODES, 1, 0.82, 0.24, true)
        GameTooltip:AddLine(
            string.format(Addon.L.GATHERING_BUTTON_COUNT, tonumber(Runtime.index and Runtime.index.total) or 0),
            0.88, 0.86, 0.82, true
        )
        GameTooltip:AddLine(
            Runtime:IsDisplayEnabled() and Addon.L.GATHERING_BUTTON_PINS_ON
                or Addon.L.GATHERING_BUTTON_PINS_OFF,
            0.60, 0.86, 0.62, true
        )
        GameTooltip:AddLine(Addon.L.GATHERING_BUTTON_HINT, 0.72, 0.72, 0.70, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.miniButton = button
    self:ApplyButtonPosition()
    return button
end

function Runtime:EnsureMinimapButton()
    if self.minimapButton or not Minimap then return self.minimapButton end
    local button = CreateFrame("Button", "VaultloomGatheringNodesMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((type(Minimap.GetFrameLevel) == "function"
        and Minimap:GetFrameLevel() or 1) + 10)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(getKindIcon("mining"))
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addCircularMask(button, button.icon, "iconMask")
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetColorTexture(1.00, 0.82, 0.46, 0.16)
    button.highlight:SetBlendMode("ADD")
    button.highlight:SetSize(24, 24)
    button.highlight:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    addCircularMask(button, button.highlight, "highlightMask")

    button:SetScript("OnClick", function(_, clicked)
        if clicked == "RightButton" then
            Runtime:ToggleManager()
        else
            Runtime:SetDisplayEnabled(not Runtime:IsDisplayEnabled())
        end
    end)
    button:SetScript("OnDragStart", function(selfButton)
        if setting("locked") == true or (InCombatLockdown and InCombatLockdown()) then return end
        selfButton.dragging = true
        if type(selfButton.LockHighlight) == "function" then selfButton:LockHighlight() end
        if GameTooltip then GameTooltip:Hide() end
        selfButton:SetScript("OnUpdate", function(activeButton)
            updateLauncherMinimapDrag(activeButton)
        end)
    end)
    button:SetScript("OnDragStop", function(selfButton)
        if selfButton.dragging ~= true then return end
        selfButton.dragging = false
        selfButton:SetScript("OnUpdate", nil)
        if type(selfButton.UnlockHighlight) == "function" then selfButton:UnlockHighlight() end
        updateLauncherMinimapPosition(selfButton)
    end)
    button:SetScript("OnEnter", function(selfButton)
        if selfButton.dragging or not GameTooltip then return end
        GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(Addon.L.FEATURE_GATHERING_NODES, 1, 0.82, 0.24, true)
        GameTooltip:AddLine(
            string.format(Addon.L.GATHERING_BUTTON_COUNT, tonumber(Runtime.index and Runtime.index.total) or 0),
            0.88, 0.86, 0.82, true
        )
        GameTooltip:AddLine(
            Runtime:IsDisplayEnabled() and Addon.L.GATHERING_BUTTON_PINS_ON
                or Addon.L.GATHERING_BUTTON_PINS_OFF,
            0.60, 0.86, 0.62, true
        )
        GameTooltip:AddLine(Addon.L.GATHERING_MINIMAP_BUTTON_HINT, 0.72, 0.72, 0.70, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    updateLauncherMinimapPosition(button)
    button:Hide()
    self.minimapButton = button
    return button
end

function Runtime:RefreshMiniButton()
    local mode = self.enabled == true and setting("launcher_mode") or "off"
    local floatingButton
    if mode == "floating" then
        floatingButton = self:EnsureMiniButton()
        floatingButton:Show()
    elseif self.miniButton then
        self.miniButton:Hide()
    end
    local minimapButton
    if mode == "minimap" then
        minimapButton = self:EnsureMinimapButton()
        if minimapButton then
            updateLauncherMinimapPosition(minimapButton)
            minimapButton:Show()
        end
    elseif self.minimapButton then
        self.minimapButton:Hide()
    end
    local active = self:IsDisplayEnabled()
    local function updateVisual(button)
        if button and button.icon then
            button.icon:SetDesaturated(not active)
            button.icon:SetAlpha(active and 1 or 0.46)
        end
    end
    updateVisual(floatingButton or self.miniButton)
    updateVisual(minimapButton or self.minimapButton)
end

local function createCheck(parent)
    local check = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    check:SetSize(21, 21)
    check:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    check:SetBackdropColor(0.03, 0.025, 0.02, 0.96)
    check:SetBackdropBorderColor(0.72, 0.54, 0.18, 0.86)
    check.mark = check:CreateTexture(nil, "OVERLAY")
    check.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check.mark:SetSize(25, 25)
    check.mark:SetPoint("CENTER")
    function check:SetChecked(value)
        self.checked = value == true
        self.mark:SetShown(self.checked)
    end
    return check
end

local function createManagerRow(parent)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    Addon.Widgets:ApplyPanelStyle(row, "cardInset")
    row:SetHeight(38)
    row:RegisterForClicks("LeftButtonUp")
    row.check = createCheck(row)
    row.check:SetPoint("LEFT", 8, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(25, 25)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 7, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.label = Addon.Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", -100, 0)
    row.count = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "RIGHT")
    row.count:SetPoint("RIGHT", -10, 0)
    row.count:SetWidth(82)
    row:SetScript("OnClick", function(self)
        if self.resourceKey then
            Runtime:SetResourceVisible(self.resourceKey, not self.check.checked)
        end
    end)
    return row
end

function Runtime:SetResourceVisible(resourceKey, visible)
    if type(resourceKey) ~= "string" or resourceKey == "" then return false end
    local hidden = self:GetHiddenStore()
    if visible == true then
        hidden[resourceKey] = nil
    else
        hidden[resourceKey] = true
    end
    self:InvalidateWorldPinCache()
    self:RequestWorldRefresh(0)
    self:RequestMinimapRefresh(true)
    if self.manager and self.manager:IsShown() then self:RefreshManager() end
    return true
end

function Runtime:EnsureManager()
    if self.manager then return self.manager end
    local frame = CreateFrame(
        "Frame",
        "VaultloomGatheringNodesManager",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(590, 540)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(120)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -20)
    frame.title:SetPoint("TOPRIGHT", -60, -20)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)
    frame.title:SetText(Addon.L.GATHERING_MANAGER_TITLE)

    frame.subtitle = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.subtitle:SetPoint("TOPRIGHT", -22, -50)
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(Addon.L.GATHERING_MANAGER_SUBTITLE)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.summary = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "LEFT")
    frame.summary:SetPoint("TOPLEFT", 22, -84)
    frame.summary:SetPoint("TOPRIGHT", -22, -84)

    frame.showAll = Addon.Widgets:CreateButton(frame, Addon.L.GATHERING_SHOW_ALL, 142, 28)
    frame.showAll:SetPoint("TOPLEFT", 22, -112)
    frame.showAll:SetScript("OnClick", function()
        local hidden = Runtime:GetHiddenStore()
        for key in pairs(hidden) do hidden[key] = nil end
        Runtime:InvalidateWorldPinCache()
        Runtime:RequestWorldRefresh(0)
        Runtime:RequestMinimapRefresh(true)
        Runtime:RefreshManager()
    end)

    frame.clearMap = Addon.Widgets:CreateButton(frame, Addon.L.GATHERING_CLEAR_MAP, 170, 28)
    frame.clearMap:SetPoint("LEFT", frame.showAll, "RIGHT", 8, 0)
    frame.clearMap:SetScript("OnClick", function()
        Runtime:ShowManagerConfirmation("map")
    end)

    frame.clearAll = Addon.Widgets:CreateButton(frame, Addon.L.GATHERING_CLEAR_ALL, 142, 28)
    frame.clearAll:SetPoint("LEFT", frame.clearMap, "RIGHT", 8, 0)
    frame.clearAll:SetScript("OnClick", function()
        Runtime:ShowManagerConfirmation("all")
    end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -154)
    frame.scroll:SetPoint("BOTTOMRIGHT", -42, 24)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(520, 10)
    frame.scroll:SetScrollChild(frame.child)
    Addon.ScrollFrames:Style(frame.scroll, { autoHide = true })
    frame.rows = {}

    frame.empty = Addon.Widgets:CreateLabel(frame.child, "GameFontDisable", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 14, -30)
    frame.empty:SetPoint("TOPRIGHT", -14, -30)
    frame.empty:SetText(Addon.L.GATHERING_MANAGER_EMPTY)

    frame.confirm = Addon.Widgets:CreatePanel(frame, "content")
    frame.confirm:SetSize(420, 154)
    frame.confirm:SetPoint("CENTER")
    frame.confirm:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.confirm.title = Addon.Widgets:CreateLabel(frame.confirm, "GameFontNormalLarge", "CENTER")
    frame.confirm.title:SetPoint("TOPLEFT", 18, -20)
    frame.confirm.title:SetPoint("TOPRIGHT", -18, -20)
    frame.confirm.message = Addon.Widgets:CreateLabel(frame.confirm, "GameFontHighlightSmall", "CENTER")
    frame.confirm.message:SetPoint("TOPLEFT", 22, -54)
    frame.confirm.message:SetPoint("TOPRIGHT", -22, -54)
    frame.confirm.message:SetWordWrap(true)
    frame.confirm.cancel = Addon.Widgets:CreateButton(frame.confirm, Addon.L.SIDEBAR_CANCEL, 112, 28)
    frame.confirm.cancel:SetPoint("BOTTOMLEFT", 42, 20)
    frame.confirm.accept = Addon.Widgets:CreateButton(frame.confirm, Addon.L.GATHERING_DELETE, 112, 28)
    frame.confirm.accept:SetPoint("BOTTOMRIGHT", -42, 20)
    frame.confirm.cancel:SetScript("OnClick", function() frame.confirm:Hide() end)
    frame.confirm.accept:SetScript("OnClick", function()
        local scope = frame.confirm.scope
        frame.confirm:Hide()
        if scope == "map" then
            local snapshot = getMapSnapshot()
            if snapshot then Logic:ClearMap(Runtime.store, Runtime.index, snapshot.mapID) end
        elseif scope == "all" then
            Logic:ClearAll(Runtime.store, Runtime.index)
        end
        Runtime:NotifyDataChanged()
    end)
    frame.confirm:Hide()

    frame:Hide()
    self.manager = frame
    return frame
end

function Runtime:ShowManagerConfirmation(scope)
    local frame = self:EnsureManager()
    frame.confirm.scope = scope
    frame.confirm.title:SetText(Addon.L.GATHERING_DELETE_TITLE)
    frame.confirm.message:SetText(
        scope == "map" and Addon.L.GATHERING_CLEAR_MAP_CONFIRM
            or Addon.L.GATHERING_CLEAR_ALL_CONFIRM
    )
    frame.confirm:Show()
    if type(frame.confirm.Raise) == "function" then frame.confirm:Raise() end
end

function Runtime:RefreshManager()
    local frame = self:EnsureManager()
    local catalog = Logic:BuildCatalog(self.store or self:PrepareStore())
    for _, entry in ipairs(catalog) do
        entry.displayName = getDisplayResourceName(entry)
    end
    table.sort(catalog, function(first, second)
        local firstOrder = Logic:GetKindOrder(first.kind)
        local secondOrder = Logic:GetKindOrder(second.kind)
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        return Logic:NormalizeText(first.displayName) < Logic:NormalizeText(second.displayName)
    end)
    local hidden = self:GetHiddenStore()
    frame.summary:SetText(string.format(
        Addon.L.GATHERING_MANAGER_SUMMARY,
        tonumber(self.index and self.index.total) or 0,
        #catalog
    ))
    frame.empty:SetShown(#catalog == 0)
    local previous
    for index, entry in ipairs(catalog) do
        local row = frame.rows[index]
        if not row then
            row = createManagerRow(frame.child)
            frame.rows[index] = row
        end
        row:ClearAllPoints()
        if previous then
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -5)
        else
            row:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", frame.child, "RIGHT", 0, 0)
        row.resourceKey = entry.key
        row.check:SetChecked(hidden[entry.key] ~= true)
        row.check:SetScript("OnClick", function(selfCheck)
            Runtime:SetResourceVisible(row.resourceKey, not selfCheck.checked)
        end)
        row.icon:SetTexture(entry.icon or getKindIcon(entry.kind))
        row.label:SetText(entry.displayName)
        row.count:SetText(string.format(Addon.L.GATHERING_NODE_COUNT, entry.count))
        row:SetAlpha(hidden[entry.key] and 0.52 or 1)
        row:Show()
        previous = row
    end
    for index = #catalog + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.child:SetHeight(math.max(10, (#catalog * 43) - 5))
end

function Runtime:ToggleManager()
    local frame = self:EnsureManager()
    if frame:IsShown() then
        frame:Hide()
    else
        self:RefreshManager()
        frame:Show()
        if type(frame.Raise) == "function" then frame:Raise() end
    end
end

local function createPreviewPin(parent, x, y, kind, minimap)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetPoint("CENTER", parent, "TOPLEFT", x, y)
    pin.kind = kind
    if minimap then
        pin.ring = pin:CreateTexture(nil, "ARTWORK")
        pin.ring:SetAllPoints(pin)
        pin.ring:SetTexture(MINIMAP_RING)
    else
        pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
        pin.Ring:SetAllPoints(pin)
        pin.Icon = pin:CreateTexture(nil, "ARTWORK")
        pin.Icon:SetPoint("CENTER")
        pin.Count = Addon.Widgets:CreateLabel(pin, "GameFontNormalSmall", "CENTER")
        pin.Count:SetPoint("BOTTOMRIGHT", 4, -4)
    end
    return pin
end

function Runtime:EnsurePreview()
    if self.preview then return self.preview end
    local frame = CreateFrame(
        "Frame",
        "VaultloomGatheringNodesPreview",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(620, 360)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(125)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -20)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)
    frame.title:SetText(Addon.L.GATHERING_PREVIEW_TITLE)
    frame.subtitle = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.subtitle:SetPoint("TOPRIGHT", -24, -50)
    frame.subtitle:SetText(Addon.L.GATHERING_PREVIEW_SUBTITLE)
    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.worldTitle = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "CENTER")
    frame.worldTitle:SetPoint("TOP", frame, "TOP", -145, -88)
    frame.worldTitle:SetText(Addon.L.GATHERING_PREVIEW_WORLD)
    frame.minimapTitle = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "CENTER")
    frame.minimapTitle:SetPoint("TOP", frame, "TOP", 145, -88)
    frame.minimapTitle:SetText(Addon.L.GATHERING_PREVIEW_MINIMAP)
    frame.worldPins, frame.minimapPins = {}, {}
    local kinds = { "mining", "herbalism", "leather", "wood", "fish", "cooking" }
    for index, kind in ipairs(kinds) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        frame.worldPins[index] = createPreviewPin(frame, 98 + (column * 70), -158 - (row * 86), kind, false)
        frame.minimapPins[index] = createPreviewPin(frame, 386 + (column * 70), -158 - (row * 86), kind, true)
    end
    frame:Hide()
    self.preview = frame
    return frame
end

function Runtime:RefreshPreview()
    local frame = self.preview
    if not frame or not frame:IsShown() then return end
    for _, pin in ipairs(frame.worldPins) do
        applyWorldPinVisual(pin, {
            kind = pin.kind,
            icon = getKindIcon(pin.kind),
            count = 1,
        })
    end
    for _, pin in ipairs(frame.minimapPins) do
        local size = math.max(10, math.floor(
            (BASE_MINIMAP_PIN_SIZE * setting("minimap_scale_percent") / 100) + 0.5
        ))
        local color = getKindColor(pin.kind)
        pin:SetSize(size, size)
        pin.ring:SetVertexColor(color[1], color[2], color[3], 0.96)
    end
end

function Runtime:TogglePreview()
    local frame = self:EnsurePreview()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        if type(frame.Raise) == "function" then frame:Raise() end
        self:RefreshPreview()
    end
end

function Runtime:ResetLayout()
    local root = self:GetStore()
    local button = root.button
    button.point = "CENTER"
    button.relativePoint = "CENTER"
    button.x = 410
    button.y = -92
    button.scale = 1
    root.minimapButton.angle = LAUNCHER_MINIMAP_DEFAULT_ANGLE
    self:ApplyButtonPosition()
    updateLauncherMinimapPosition(self.minimapButton)
end

function Runtime:GetSettingValue(key)
    if DEFAULTS[key] == nil then return nil end
    return setting(key)
end

function Runtime:SetSettingValue(key, value)
    if DEFAULTS[key] == nil then return false end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[key] = value
    if key == "launcher_mode" or key == "locked" then self:RefreshMiniButton() end
    self:ScanProfessions()
    self:RefreshPreview()
    self:RequestWorldRefresh(0)
    self:RequestMinimapRefresh(true)
    return true
end

function Runtime:ResetSettingValues()
    self:InvalidateWorldPinCache()
    self:RefreshMiniButton()
    self:RefreshPreview()
    self:RequestWorldRefresh(0)
    self:RequestMinimapRefresh(true)
end

function Runtime:OnSettingsReset()
    self:ResetSettingValues()
end

function Runtime:OnSettingsClosed()
    if self.preview then self.preview:Hide() end
end

function Runtime:OnAction(actionKey)
    if actionKey == "manage" then
        self:ToggleManager()
        return true
    elseif actionKey == "preview" then
        self:TogglePreview()
        return true
    elseif actionKey == "reset_layout" then
        self:ResetLayout()
        return true
    end
    return false
end

function Runtime:RegisterEvents()
    Addon.EventBus:Subscribe("ADDON_LOADED", self, function(_, addonName)
        if addonName == "Blizzard_WorldMap" then
            Addon.WorldMapPins:EnsureHooks()
            Runtime:RequestWorldRefresh(0.05)
        end
    end)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        Runtime.pendingCast = nil
        Runtime.recentGather = nil
        Runtime.recentFishingAt = nil
        Runtime.pendingItemNames = {}
        Runtime.hiddenCharacterKey = nil
        Runtime.hiddenStore = nil
        Runtime:ScanProfessions()
        Runtime:RequestWorldRefresh(0.10)
        Runtime:RequestMinimapRefresh(true)
    end)
    Addon.EventBus:Subscribe("ZONE_CHANGED_NEW_AREA", self, function()
        Runtime.pendingCast = nil
        Runtime.recentGather = nil
        Runtime.recentFishingAt = nil
        Runtime:RequestWorldRefresh(0.05)
        Runtime:RequestMinimapRefresh(true)
    end)
    Addon.EventBus:Subscribe("SKILL_LINES_CHANGED", self, function()
        Runtime:ScanProfessions()
        Runtime:RequestWorldRefresh(0.05)
        Runtime:RequestMinimapRefresh(true)
    end)
    Addon.EventBus:Subscribe("MINIMAP_UPDATE_ZOOM", self, function()
        Runtime:RequestMinimapRefresh(true)
    end)
    Addon.EventBus:Subscribe("CVAR_UPDATE", self, function(_, cvar)
        if cvar == "rotateMinimap" then Runtime:RequestMinimapRefresh(true) end
    end)
    Addon.EventBus:Subscribe("UNIT_SPELLCAST_SENT", self, function(_, ...)
        Runtime:OnSpellSent(...)
    end)
    Addon.EventBus:Subscribe("UNIT_SPELLCAST_SUCCEEDED", self, function(_, ...)
        Runtime:OnSpellSucceeded(...)
    end)
    Addon.EventBus:Subscribe("UNIT_SPELLCAST_FAILED", self, function(_, ...)
        Runtime:CancelPendingCast(...)
    end)
    Addon.EventBus:Subscribe("UNIT_SPELLCAST_INTERRUPTED", self, function(_, ...)
        Runtime:CancelPendingCast(...)
    end)
    Addon.EventBus:Subscribe("CURSOR_CHANGED", self, function()
        Runtime:CapturePendingTarget()
    end)
    Addon.EventBus:Subscribe("CHAT_MSG_LOOT", self, function(_, text)
        Runtime:RecordLoot(parseChatLoot(text))
    end)
    Addon.EventBus:Subscribe("LOOT_READY", self, function()
        Runtime:ScanLootWindow()
    end)
    Addon.EventBus:Subscribe("LOOT_OPENED", self, function()
        Runtime:ScanLootWindow()
    end)
    Addon.EventBus:Subscribe("ITEM_DATA_LOAD_RESULT", self, function(_, itemID, success)
        itemID = tonumber(itemID)
        if itemID then Runtime.pendingItemNames[itemID] = nil end
        if success ~= false and Runtime.manager and Runtime.manager:IsShown() then
            Runtime:RefreshManager()
        end
    end)
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshGeneration = self.refreshGeneration + 1
    self:PrepareStore()
    self:ScanProfessions()
    self:RegisterEvents()
    Addon.WorldMapPins:Activate(self)
    self:EnsureUpdateFrame()
    self:RefreshMiniButton()
    self:RequestMinimapRefresh(true)
    if Addon.WorldMapPins:IsShown() then self:OnWorldMapShown() end
    self:NotifyDataChanged()
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self.minimapRefreshGeneration = self.minimapRefreshGeneration + 1
    self.minimapRetryAttempt = 0
    self.minimapTrackingNeeded = false
    self.pendingCast = nil
    self.recentGather = nil
    self.recentFishingAt = nil
    self.recentNode = nil
    self.hiddenCharacterKey = nil
    self.hiddenStore = nil
    self:InvalidateWorldPinCache()
    self:CancelMinimapIdleRefresh()
    Addon.WorldMapPins:Deactivate(self)
    self:RemoveProvider()
    self:RecycleMinimapPins()
    if self.updateFrame then self.updateFrame:Hide() end
    if self.miniButton then self.miniButton:Hide() end
    if self.minimapButton then self.minimapButton:Hide() end
    if self.manager then self.manager:Hide() end
    if self.preview then self.preview:Hide() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Gathering Nodes runtime.")
end
