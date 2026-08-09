local addonName, Addon = ...

local FEATURE_ID = "travel_bar"
local DOMAIN_ID = "feature.travelBar"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local SECURE_BUTTON_TEMPLATE = BACKDROP_TEMPLATE
    and "SecureActionButtonTemplate,BackdropTemplate"
    or "SecureActionButtonTemplate"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICON_TEXEL_INSET = 3 / 64
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local HOUSING_ICON = "Interface\\AddOns\\" .. addonName .. "\\Assets\\travel_bar_housing_icon.tga"
local SCALE_MIN = 0.70
local SCALE_MAX = 1.45
local SCALE_STEP = 0.05
local MANAGER_MIN_FRAME_LEVEL = 50
local DEFAULT_POSITION = {
    point = "TOP",
    relativePoint = "TOP",
    x = 0,
    y = -272,
}

local HEARTH_TOY_IDS = {
    184353, 183716, 180290, 182773, 54452, 64488, 93672, 142542,
    162973, 163045, 165669, 165670, 165802, 166746, 166747, 168907,
    172179, 193588, 188952, 200630, 190237, 190196, 209035, 208704,
    206195, 212337, 210455, 228940, 235016, 236687, 245970, 246565,
    263489, 257736, 265100, 263933,
}
local EXTRA_TRAVEL_ITEM_IDS = {
    132119, 132120, 95567, 95568, 112059, 132517, 48933, 87215,
    151652, 168807, 168808, 172924, 198156, 221965, 221966, 248485,
    253629, 276371,
}
local RELEVANT_ITEM_IDS = {
    [6948] = true,
    [140192] = true,
    [110560] = true,
}
for _, itemID in ipairs(HEARTH_TOY_IDS) do RELEVANT_ITEM_IDS[itemID] = true end
for _, itemID in ipairs(EXTRA_TRAVEL_ITEM_IDS) do RELEVANT_ITEM_IDS[itemID] = true end
local CLASS_TRAVEL_SPELLS = {
    DRUID = 193753,
    MONK = 126892,
    DEATHKNIGHT = 50977,
    SHAMAN = 556,
    MAGE = 193759,
}
local COVENANT_REQUIREMENTS = {
    [184353] = 1,
    [183716] = 2,
    [180290] = 3,
    [182773] = 4,
}
local RING_COLORS = {
    gold = { 0.92, 0.76, 0.24 },
    cyan = { 0.20, 0.82, 0.92 },
    green = { 0.30, 0.86, 0.42 },
    red = { 0.94, 0.24, 0.20 },
    purple = { 0.68, 0.38, 0.92 },
}
local COOLDOWN_RING = { 0.48, 0.48, 0.50 }

local Runtime = {
    enabled = false,
    frame = nil,
    buttons = {},
    manager = nil,
    managerRows = {},
    model = nil,
    currentHearthKey = nil,
    pendingRefresh = false,
    actionCache = nil,
    dirty = nil,
    itemInfoCache = {},
    toyInfoCache = {},
    housingHouses = nil,
    awaitingHousingList = false,
}

Addon.TravelBar = Runtime

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function copyHousingTarget(house)
    if type(house) ~= "table"
        or not house.neighborhoodGUID
        or not house.houseGUID
        or tonumber(house.plotID) == nil
    then
        return nil
    end
    return {
        neighborhoodGUID = house.neighborhoodGUID,
        houseGUID = house.houseGUID,
        plotID = tonumber(house.plotID),
        houseName = house.houseName,
        neighborhoodName = house.neighborhoodName,
    }
end

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function inCombat()
    return Addon.WoWApi:IsInCombatLockdown()
end

local function showMessage(message)
    if type(message) == "string" and message ~= "" then Addon:Print(message) end
end

local function bringManagerToFront(manager)
    if not manager then return end
    local frameLevel = MANAGER_MIN_FRAME_LEVEL
    local shellFrame = Addon.UI and Addon.UI.frame
    local featuresPanel = shellFrame and shellFrame.featuresPanel
    local settingsDialog = featuresPanel and featuresPanel.settingsDialog
    if settingsDialog and type(settingsDialog.GetFrameLevel) == "function" then
        local ok, value = pcall(settingsDialog.GetFrameLevel, settingsDialog)
        if ok then frameLevel = math.max(frameLevel, (tonumber(value) or 0) + 10) end
    end
    manager:SetFrameStrata("DIALOG")
    manager:SetFrameLevel(frameLevel)
    manager:Raise()
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.travelBar = type(db.features.travelBar) == "table"
        and db.features.travelBar or {}
    local store = db.features.travelBar
    store.position = type(store.position) == "table" and store.position or {}
    store.scale = clamp(store.scale, SCALE_MIN, SCALE_MAX)
    store.hidden = type(store.hidden) == "table" and store.hidden or {}
    store.order = type(store.order) == "table" and store.order or {}
    if store.simpleSelectionVersion ~= 1 then
        store.order = {}
        store.fixedHearthKey = nil
        store.simpleSelectionVersion = 1
    end
    return store
end

local function applyPosition(frame)
    local position = getStore().position
    frame:ClearAllPoints()
    frame:SetPoint(
        type(position.point) == "string" and position.point or DEFAULT_POSITION.point,
        UIParent,
        type(position.relativePoint) == "string" and position.relativePoint or DEFAULT_POSITION.relativePoint,
        tonumber(position.x) or DEFAULT_POSITION.x,
        tonumber(position.y) or DEFAULT_POSITION.y
    )
end

local function savePosition(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local position = getStore().position
    position.point = type(point) == "string" and point or DEFAULT_POSITION.point
    position.relativePoint = type(relativePoint) == "string" and relativePoint or position.point
    position.x = tonumber(x) or 0
    position.y = tonumber(y) or 0
end

local function resetConfiguration()
    local store = getStore()
    store.position.point = DEFAULT_POSITION.point
    store.position.relativePoint = DEFAULT_POSITION.relativePoint
    store.position.x = DEFAULT_POSITION.x
    store.position.y = DEFAULT_POSITION.y
    store.scale = 1
    store.hidden = {}
    store.order = {}
    store.fixedHearthKey = nil
    store.selectedExtraKey = nil
    store.housingTarget = nil
    Runtime.currentHearthKey = nil
    Runtime.actionCache = nil
    Runtime.dirty = {
        toys = true,
        inventory = true,
        class = true,
        housing = true,
    }
    Runtime.housingHouses = nil
    if type(Runtime.StopHousingRequest) == "function" then
        Runtime:StopHousingRequest()
    else
        Runtime.awaitingHousingList = false
    end
    if Runtime.frame then
        Runtime.frame:SetScale(1)
        applyPosition(Runtime.frame)
    end
end

local function getRingColor()
    local key = setting("ring_color")
    if key ~= "class" and RING_COLORS[key] then return unpack(RING_COLORS[key]) end
    local classFile
    if type(UnitClass) == "function" then
        local ok, _, value = pcall(UnitClass, "player")
        if ok then classFile = value end
    end
    local colors = type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS
        or type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS
    local color = colors and colors[classFile] or nil
    if color then
        return tonumber(color.r) or 1, tonumber(color.g) or 0.82, tonumber(color.b) or 0.24
    end
    return unpack(RING_COLORS.gold)
end

local function getBarOpacity()
    return clamp(setting("bar_opacity_percent"), 30, 100) / 100
end

local function getItemCount(itemID)
    if C_Item and type(C_Item.GetItemCount) == "function" then
        local ok, count = pcall(C_Item.GetItemCount, itemID, false, false, true)
        if ok then return math.max(0, tonumber(count) or 0) end
    end
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID, false, false, true)
        if ok then return math.max(0, tonumber(count) or 0) end
    end
    return 0
end

local function ownsToy(itemID)
    if type(PlayerHasToy) ~= "function" then return false end
    local ok, value = pcall(PlayerHasToy, itemID)
    return ok and value == true
end

local function getToyInfo(itemID)
    local cached = Runtime.toyInfoCache[itemID]
    if cached then return cached.name, cached.icon end
    if not C_ToyBox or type(C_ToyBox.GetToyInfo) ~= "function" then return nil, nil end
    local ok, first, second, third = pcall(C_ToyBox.GetToyInfo, itemID)
    if not ok then return nil, nil end
    local name, icon
    if type(first) == "number" then
        name, icon = second, third
    else
        name, icon = first, second
    end
    if name ~= nil or icon ~= nil then
        Runtime.toyInfoCache[itemID] = { name = name, icon = icon }
    end
    return name, icon
end

local function getItemInfo(itemID)
    local cached = Runtime.itemInfoCache[itemID]
    if cached then return cached.name, cached.icon, cached.link end
    local name, link
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, first, second = pcall(C_Item.GetItemInfo, itemID)
        if ok then name, link = first, second end
    elseif type(GetItemInfo) == "function" then
        local ok, first, second = pcall(GetItemInfo, itemID)
        if ok then name, link = first, second end
    end
    local icon
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = value end
    elseif type(GetItemIcon) == "function" then
        local ok, value = pcall(GetItemIcon, itemID)
        if ok then icon = value end
    end
    if name ~= nil or icon ~= nil or link ~= nil then
        Runtime.itemInfoCache[itemID] = {
            name = name,
            icon = icon,
            link = link,
        }
    end
    return name, icon, link
end

local function toyAllowed(itemID)
    if not ownsToy(itemID) then return false end
    local covenantID = COVENANT_REQUIREMENTS[itemID]
    if covenantID and C_Covenants and type(C_Covenants.GetActiveCovenantID) == "function" then
        local ok, activeID = pcall(C_Covenants.GetActiveCovenantID)
        if ok and tonumber(activeID) ~= covenantID then
            local mastered = false
            if type(GetAchievementInfo) == "function" then
                local achievementOK, _, _, _, completed = pcall(GetAchievementInfo, 15241)
                mastered = achievementOK and completed == true
            end
            if not mastered then return false end
        end
    end
    if itemID == 210455 and type(UnitRace) == "function" then
        local ok, _, _, raceID = pcall(UnitRace, "player")
        if ok and raceID ~= 11 and raceID ~= 30 then return false end
    end
    return true
end

local function createToyAction(itemID, key, group, direct)
    if not toyAllowed(itemID) then return nil end
    local name, icon = getToyInfo(itemID)
    return {
        key = key or ("toy_" .. tostring(itemID)),
        kind = "toy",
        itemID = itemID,
        token = type(name) == "string" and name or tostring(itemID),
        label = type(name) == "string" and name or ("Item " .. tostring(itemID)),
        icon = icon or UNKNOWN_ICON,
        group = group,
        direct = direct == true,
    }
end

local function createItemAction(itemID, key, group, direct)
    if getItemCount(itemID) <= 0 then return nil end
    local name, icon, link = getItemInfo(itemID)
    return {
        key = key or ("item_" .. tostring(itemID)),
        kind = "item",
        itemID = itemID,
        token = link or ("item:" .. tostring(itemID)),
        label = type(name) == "string" and name or ("Item " .. tostring(itemID)),
        icon = icon or UNKNOWN_ICON,
        group = group,
        direct = direct == true,
    }
end

local function createItemOrToyAction(itemID, key, group, direct)
    if ownsToy(itemID) then return createToyAction(itemID, key, group, direct) end
    return createItemAction(itemID, key, group, direct)
end

local function getSpellInfo(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok then return name, icon end
    end
    return nil, nil
end

local function createClassAction()
    local classFile
    if type(UnitClass) == "function" then
        local ok, _, value = pcall(UnitClass, "player")
        if ok then classFile = value end
    end
    local spellID = classFile and CLASS_TRAVEL_SPELLS[classFile] or nil
    if not spellID then return nil end
    local known = false
    if type(IsPlayerSpell) == "function" then
        local ok, value = pcall(IsPlayerSpell, spellID)
        known = ok and value == true
    end
    if not known and type(IsSpellKnown) == "function" then
        local ok, value = pcall(IsSpellKnown, spellID)
        known = ok and value == true
    end
    if not known then return nil end
    local name, icon = getSpellInfo(spellID)
    if type(name) ~= "string" or name == "" then return nil end
    return {
        key = "class_travel",
        kind = "spell",
        spellID = spellID,
        token = name,
        label = name,
        icon = icon or UNKNOWN_ICON,
        group = "travel",
        direct = true,
    }
end

local function ensureHousingProxy()
    if Runtime.housingProxy then return Runtime.housingProxy end
    local button = CreateFrame(
        "Button",
        "VaultloomTravelHousingProxy",
        UIParent,
        "SecureActionButtonTemplate"
    )
    button:SetSize(1, 1)
    button:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -1, -1)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    Runtime.housingProxy = button
    return button
end

local function configureHousingProxy(actionType, house)
    local proxy = ensureHousingProxy()
    for _, key in ipairs({
        "type", "house-neighborhood-guid", "house-guid", "house-plot-id",
    }) do
        proxy:SetAttribute(key, nil)
    end
    proxy:SetAttribute("type", actionType)
    if actionType == "teleporthome" and type(house) == "table" then
        proxy:SetAttribute("house-neighborhood-guid", house.neighborhoodGUID)
        proxy:SetAttribute("house-guid", house.houseGUID)
        proxy:SetAttribute("house-plot-id", house.plotID)
    end
    return proxy
end

local function houseKey(house)
    if type(house) ~= "table" then return nil end
    return tostring(house.houseGUID or "") .. ":" .. tostring(house.plotID or "")
end

local function copyHouse(house)
    return copyHousingTarget(house)
end

local function normalizeHouses(source)
    local houses = {}
    for _, house in ipairs(type(source) == "table" and source or {}) do
        local normalized = copyHouse(house)
        if normalized then houses[#houses + 1] = normalized end
    end
    return houses
end

local function sameHouseList(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
        return false
    end
    for index, house in ipairs(left) do
        local other = right[index]
        if houseKey(house) ~= houseKey(other)
            or house.houseName ~= other.houseName
            or house.neighborhoodName ~= other.neighborhoodName
        then
            return false
        end
    end
    return true
end

local function getHousingAction()
    if type(C_Housing) ~= "table" then return nil end
    if C_HousingNeighborhood
        and type(C_HousingNeighborhood.CanReturnAfterVisitingHouse) == "function"
    then
        local ok, canReturn = pcall(C_HousingNeighborhood.CanReturnAfterVisitingHouse)
        if ok and canReturn == true then
            local proxy = configureHousingProxy("returnhome")
            return {
                key = "housing",
                kind = "macro",
                macrotext = "/click " .. proxy:GetName(),
                label = Addon.L.TRAVEL_BAR_HOUSING_RETURN,
                icon = HOUSING_ICON,
                cooldownKind = "housing",
                group = "travel",
                direct = true,
                returning = true,
            }
        end
    end

    local source = Runtime.housingHouses
    if type(source) ~= "table" or #source == 0 then
        local housingRuntime = Addon.Housing and Addon.Housing.runtime
        if housingRuntime and type(housingRuntime.houseList) == "table"
            and #housingRuntime.houseList > 0
        then
            source = housingRuntime.houseList
        end
    end

    local houses = normalizeHouses(source)
    local store = getStore()
    if #houses == 0 then
        local remembered = copyHouse(store.housingTarget)
        if remembered then houses[1] = remembered end
    end
    if #houses == 0 then return nil end
    Runtime.housingHouses = houses

    local selected
    local selectedKey = type(store.housingTarget) == "table"
        and houseKey(store.housingTarget) or nil
    for _, house in ipairs(houses) do
        if houseKey(house) == selectedKey then selected = house break end
    end
    selected = selected or houses[1]
    store.housingTarget = {
        neighborhoodGUID = selected.neighborhoodGUID,
        houseGUID = selected.houseGUID,
        plotID = selected.plotID,
        houseName = selected.houseName,
        neighborhoodName = selected.neighborhoodName,
    }
    local proxy = configureHousingProxy("teleporthome", selected)
    return {
        key = "housing",
        kind = "macro",
        macrotext = "/click " .. proxy:GetName(),
        label = selected.houseName or Addon.L.TRAVEL_BAR_HOUSING,
        icon = HOUSING_ICON,
        cooldownKind = "housing",
        group = "travel",
        direct = true,
        houses = houses,
        housingTargetKey = houseKey(selected),
    }
end

function Runtime:StopHousingRequest()
    if self.awaitingHousingList == true then
        Addon.EventBus:Unsubscribe(self, "PLAYER_HOUSE_LIST_UPDATED")
    end
    self.awaitingHousingList = false
end

function Runtime:ApplyHousingList(houses)
    local normalized = normalizeHouses(houses)
    self:StopHousingRequest()
    if #normalized == 0 or sameHouseList(self.housingHouses, normalized) then
        return false
    end
    self.housingHouses = normalized
    self:MarkDirty("housing")
    if self.enabled == true then self:ScheduleRefresh(0) end
    return true
end

function Runtime:RequestHousingList()
    if type(C_Housing) ~= "table"
        or type(C_Housing.GetPlayerOwnedHouses) ~= "function"
    then
        return false
    end
    if self.awaitingHousingList ~= true then
        self.awaitingHousingList = Addon.EventBus:Subscribe(
            "PLAYER_HOUSE_LIST_UPDATED",
            self,
            function(_, houses)
                Runtime:ApplyHousingList(houses)
            end
        ) == true
    end
    local ok, houses = pcall(C_Housing.GetPlayerOwnedHouses)
    if ok and type(houses) == "table" then self:ApplyHousingList(houses) end
    return ok
end

local function collectToyHearths()
    local hearths = {}
    local function add(list, action)
        if type(action) == "table" then list[#list + 1] = action end
    end
    for _, itemID in ipairs(HEARTH_TOY_IDS) do
        add(hearths, createToyAction(itemID, "hearth_" .. tostring(itemID), "hearth"))
    end
    return hearths
end

local function collectInventoryActions()
    local hearths, direct, extras = {}, {}, {}
    local function add(list, action)
        if type(action) == "table" then list[#list + 1] = action end
    end
    add(hearths, createItemAction(6948, "hearthstone", "hearth"))
    add(direct, createItemOrToyAction(140192, "dalaran", "travel", true))
    add(direct, createItemOrToyAction(110560, "garrison", "travel", true))
    for _, itemID in ipairs(EXTRA_TRAVEL_ITEM_IDS) do
        add(extras, createItemOrToyAction(itemID, "travel_" .. tostring(itemID), "travel", false))
    end
    return {
        hearths = hearths,
        direct = direct,
        extras = extras,
    }
end

local function measuredCollection(detail, callback)
    if Addon.PerformanceDiagnostics.active == true then
        local ok, result = Addon.PerformanceDiagnostics:Call(
            Runtime,
            "travel",
            detail,
            "travel." .. detail,
            callback
        )
        return ok and result or nil
    end
    return callback()
end

function Runtime:MarkDirty(...)
    self.dirty = type(self.dirty) == "table" and self.dirty or {}
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        if type(key) == "string" then self.dirty[key] = true end
    end
end

function Runtime:MarkAllDirty()
    self:MarkDirty("toys", "inventory", "class", "housing")
end

function Runtime:RefreshActionCache()
    self.actionCache = type(self.actionCache) == "table" and self.actionCache or {}
    self.dirty = type(self.dirty) == "table" and self.dirty or {}
    local cache = self.actionCache

    if self.dirty.toys == true or type(cache.toys) ~= "table" then
        cache.toys = measuredCollection("toys", collectToyHearths) or {}
        self.dirty.toys = nil
    end
    if self.dirty.inventory == true or type(cache.inventory) ~= "table" then
        cache.inventory = measuredCollection("inventory", collectInventoryActions)
            or { hearths = {}, direct = {}, extras = {} }
        self.dirty.inventory = nil
    end
    if self.dirty.class == true or cache.class == nil then
        cache.class = measuredCollection("class", createClassAction) or false
        self.dirty.class = nil
    end
    if self.dirty.housing == true or cache.housing == nil then
        cache.housing = measuredCollection("housing", function()
            return getHousingAction()
        end) or false
        self.dirty.housing = nil
    end
    return cache
end

local function collectActions()
    local cache = Runtime:RefreshActionCache()
    local hearths, travels = {}, {}
    for _, action in ipairs(cache.inventory.hearths or {}) do
        hearths[#hearths + 1] = action
    end
    for _, action in ipairs(cache.toys or {}) do
        hearths[#hearths + 1] = action
    end
    for _, action in ipairs(cache.inventory.direct or {}) do
        travels[#travels + 1] = action
    end
    if type(cache.housing) == "table" then travels[#travels + 1] = cache.housing end
    if type(cache.class) == "table" then travels[#travels + 1] = cache.class end
    for _, action in ipairs(cache.inventory.extras or {}) do
        travels[#travels + 1] = action
    end
    return hearths, travels
end

function Runtime:CollectModel()
    local store = getStore()
    local hearths, travels = collectActions()
    local model = Addon.TravelBarLogic:BuildModel({
        hearths = hearths,
        travels = travels,
        hidden = store.hidden,
        hearthMode = "random",
        currentHearthKey = self.currentHearthKey,
        selectedExtraKey = store.selectedExtraKey,
    })
    if model.main then self.currentHearthKey = model.main.key end
    if model.more then store.selectedExtraKey = model.more.key end
    return model
end

local function getCooldown(action)
    if type(action) ~= "table" then return 0, 0, 0, 1 end
    if action.kind == "spell" and C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, action.spellID)
        if ok and type(info) == "table" then
            return info.startTime or 0, info.duration or 0, info.isEnabled == false and 0 or 1, info.modRate or 1
        end
    elseif action.cooldownKind == "housing"
        and C_Housing and type(C_Housing.GetVisitCooldownInfo) == "function"
    then
        local ok, info = pcall(C_Housing.GetVisitCooldownInfo)
        if ok and type(info) == "table" then
            return info.startTime or 0, info.duration or 0, info.isEnabled == false and 0 or 1, info.modRate or 1
        end
    elseif action.itemID then
        if C_Container and type(C_Container.GetItemCooldown) == "function" then
            local ok, startTime, duration, enabled, modRate = pcall(
                C_Container.GetItemCooldown,
                action.itemID
            )
            if ok and tonumber(duration) then
                return startTime or 0, duration or 0, enabled or 0, modRate or 1
            end
        end
        if C_Item and type(C_Item.GetItemCooldown) == "function" then
            local ok, info = pcall(C_Item.GetItemCooldown, action.itemID)
            if ok and type(info) == "table" then
                return info.startTime or 0, info.duration or 0, info.isEnabled == false and 0 or 1, info.modRate or 1
            end
        end
        if type(GetItemCooldown) == "function" then
            local ok, startTime, duration, enabled, modRate = pcall(GetItemCooldown, action.itemID)
            if ok then return startTime or 0, duration or 0, enabled or 0, modRate or 1 end
        end
    end
    return 0, 0, 0, 1
end

local function applyCooldown(button, action)
    local startTime, duration, enabled, modRate = getCooldown(action)
    local active = tonumber(enabled) ~= 0
        and (tonumber(startTime) or 0) > 0
        and (tonumber(duration) or 0) > 1.5
    if active then
        if type(CooldownFrame_Set) == "function" then
            CooldownFrame_Set(button.cooldown, startTime, duration, true, false, modRate or 1)
        elseif type(button.cooldown.SetCooldown) == "function" then
            button.cooldown:SetCooldown(startTime, duration, modRate or 1)
        end
        button.cooldown:Show()
    else
        if type(button.cooldown.SetCooldown) == "function" then
            button.cooldown:SetCooldown(0, 0, 1)
        end
        button.cooldown:Hide()
    end
    button.onCooldown = active
    return active
end

local function applyCooldownVisual(button, action, ringR, ringG, ringB)
    local onCooldown = applyCooldown(button, action)
    if onCooldown then
        ringR, ringG, ringB = COOLDOWN_RING[1], COOLDOWN_RING[2], COOLDOWN_RING[3]
    end
    button.roundBack:SetVertexColor(ringR, ringG, ringB, onCooldown and 0.88 or 1)
    for _, border in ipairs(button.squareBorders) do
        border:SetVertexColor(ringR, ringG, ringB, onCooldown and 0.88 or 1)
    end
    button.roundIcon:SetDesaturated(onCooldown)
    button.squareIcon:SetDesaturated(onCooldown)
    button:SetAlpha(onCooldown and 0.78 or 1)
end

local function clearSecureAttributes(button)
    for _, key in ipairs({
        "type", "item", "toy", "spell", "macrotext",
        "type1", "item1", "toy1", "spell1", "macrotext1",
        "type2", "item2", "toy2", "spell2", "macrotext2",
    }) do
        button:SetAttribute(key, nil)
    end
end

local function applySecureAction(button, action)
    clearSecureAttributes(button)
    button.travelAction = action
    if type(action) ~= "table" then return end
    if action.kind == "toy" then
        button:SetAttribute("type1", "toy")
        button:SetAttribute("toy1", action.token)
    elseif action.kind == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", action.token)
    elseif action.kind == "macro" then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", action.macrotext)
    else
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", action.token)
    end
end

local function showTooltip(button)
    local action = button and button.travelAction or nil
    if not GameTooltip or not action then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    GameTooltip:AddLine(action.label, 1, 0.82, 0.24)
    if action.key == "hearthstone" and type(GetBindLocation) == "function" then
        local ok, location = pcall(GetBindLocation)
        if ok and type(location) == "string" and location ~= "" then
            GameTooltip:AddLine(string.format(Addon.L.TRAVEL_BAR_DESTINATION, location), 0.93, 0.89, 0.77)
        end
    elseif action.key == "housing" then
        GameTooltip:AddLine(
            action.returning and Addon.L.TRAVEL_BAR_HOUSING_RETURN_HINT
                or Addon.L.TRAVEL_BAR_HOUSING_HINT,
            0.93, 0.89, 0.77,
            true
        )
    end
    GameTooltip:AddLine(Addon.L.TRAVEL_BAR_HINT_USE, 0.72, 0.68, 0.58)
    GameTooltip:AddLine(Addon.L.TRAVEL_BAR_HINT_MANAGE, 0.72, 0.68, 0.58)
    if setting("locked") ~= true then
        GameTooltip:AddLine(Addon.L.TRAVEL_BAR_HINT_MOVE_SCALE, 0.72, 0.68, 0.58)
    end
    GameTooltip:Show()
end

function Runtime:StartMoving()
    if not self.frame or setting("locked") == true or inCombat() then return end
    self:HideManager()
    self.frame:StartMoving()
end

function Runtime:StopMoving()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    savePosition(self.frame)
end

function Runtime:GetSettingValue(settingKey)
    if settingKey == "scale_percent" then
        return math.floor((getStore().scale * 100) + 0.5)
    end
    return nil
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey ~= "scale_percent" then return false end
    local store = getStore()
    store.scale = clamp((tonumber(value) or 100) / 100, SCALE_MIN, SCALE_MAX)
    if self.frame then self.frame:SetScale(store.scale) end
    return true
end

function Runtime:ChangeScale(delta)
    if not self.frame or setting("locked") == true
        or not IsShiftKeyDown or not IsShiftKeyDown()
    then
        return
    end
    local current = self:GetSettingValue("scale_percent") or 100
    Addon.FeatureRegistry:SetSetting(
        FEATURE_ID,
        "scale_percent",
        current + (delta > 0 and (SCALE_STEP * 100) or -(SCALE_STEP * 100))
    )
end

function Runtime:CreateFrame()
    local frame = CreateFrame("Frame", "VaultloomTravelBar", UIParent, BACKDROP_TEMPLATE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() Runtime:StartMoving() end)
    frame:SetScript("OnDragStop", function() Runtime:StopMoving() end)
    frame:SetScript("OnMouseWheel", function(_, delta) Runtime:ChangeScale(delta) end)
    self.frame = frame
    frame:SetScale(getStore().scale)
    applyPosition(frame)
end

local function createSquareBorders(button)
    button.squareBorders = {}
    local function edge()
        local texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        button.squareBorders[#button.squareBorders + 1] = texture
        return texture
    end
    button.squareBorderTop = edge()
    button.squareBorderTop:SetPoint("TOPLEFT", 0, 0)
    button.squareBorderTop:SetPoint("TOPRIGHT", 0, 0)
    button.squareBorderTop:SetHeight(2)
    button.squareBorderBottom = edge()
    button.squareBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    button.squareBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    button.squareBorderBottom:SetHeight(2)
    button.squareBorderLeft = edge()
    button.squareBorderLeft:SetPoint("TOPLEFT", 0, 0)
    button.squareBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    button.squareBorderLeft:SetWidth(2)
    button.squareBorderRight = edge()
    button.squareBorderRight:SetPoint("TOPRIGHT", 0, 0)
    button.squareBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    button.squareBorderRight:SetWidth(2)
end

function Runtime:CreateButton(index)
    local name = "VaultloomTravelBarButton" .. tostring(index)
    local button = CreateFrame("Button", name, self.frame, SECURE_BUTTON_TEMPLATE)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("useOnKeyDown", false)

    button.roundBack = button:CreateTexture(nil, "BACKGROUND")
    button.roundBack:SetColorTexture(1, 1, 1, 1)
    button.roundBack:SetAllPoints(button)
    button.roundBackMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.roundBackMask:SetTexture(ROUND_MASK)
    button.roundBackMask:SetAllPoints(button.roundBack)
    button.roundBack:AddMaskTexture(button.roundBackMask)

    button.roundIcon = button:CreateTexture(nil, "ARTWORK")
    button.roundIcon:SetPoint("TOPLEFT", 2, -2)
    button.roundIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.roundMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.roundMask:SetTexture(ROUND_MASK)
    button.roundMask:SetAllPoints(button.roundIcon)
    button.roundIcon:AddMaskTexture(button.roundMask)

    button.squareIcon = button:CreateTexture(nil, "ARTWORK")
    button.squareIcon:SetPoint("TOPLEFT", 2, -2)
    button.squareIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    createSquareBorders(button)

    button.roundHighlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.roundHighlight:SetColorTexture(1, 0.82, 0.24, 0.14)
    button.roundHighlight:SetAllPoints(button)
    button.roundHighlightMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.roundHighlightMask:SetTexture(ROUND_MASK)
    button.roundHighlightMask:SetAllPoints(button.roundHighlight)
    button.roundHighlight:AddMaskTexture(button.roundHighlightMask)
    button.squareHighlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.squareHighlight:SetColorTexture(1, 0.82, 0.24, 0.14)
    button.squareHighlight:SetAllPoints(button)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetPoint("TOPLEFT", 2, -2)
    button.cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    if type(button.cooldown.SetDrawEdge) == "function" then button.cooldown:SetDrawEdge(false) end
    if type(button.cooldown.SetHideCountdownNumbers) == "function" then
        button.cooldown:SetHideCountdownNumbers(false)
    end

    button:SetScript("OnEnter", function(self) showTooltip(self) end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function() Runtime:StartMoving() end)
    button:SetScript("OnDragStop", function() Runtime:StopMoving() end)
    button:SetScript("PostClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Runtime:OpenManager()
            return
        end
        if mouseButton == "LeftButton" and self.travelRole == "main" then
            Runtime:AdvanceRandomHearth(self.travelAction and self.travelAction.key)
        end
    end)
    return button
end

function Runtime:GetButton(index)
    if not self.buttons[index] then self.buttons[index] = self:CreateButton(index) end
    return self.buttons[index]
end

function Runtime:ApplyFrameStyle(frameStyle)
    if frameStyle == "clean" then
        self.frame:SetBackdrop(nil)
        return
    end
    if frameStyle == "compact" then
        self.frame:SetBackdrop({
            bgFile = Addon.Assets.cardInset,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        self.frame:SetBackdropColor(1, 1, 1, 0.96)
        self.frame:SetBackdropBorderColor(
            0.40,
            0.31,
            0.10,
            setting("outer_border") == false and 0 or 1
        )
        return
    end
    self.frame:SetBackdrop({
        bgFile = Addon.Assets.menuPlate,
        edgeFile = TOOLTIP_BORDER,
        tile = false,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    self.frame:SetBackdropColor(1, 1, 1, 1)
    self.frame:SetBackdropBorderColor(
        0.82,
        0.64,
        0.20,
        setting("outer_border") == false and 0 or 1
    )
end

local function applyButtonAppearance(button, round, showIconBorder)
    local inset = showIconBorder and 2 or 0
    button.roundIcon:ClearAllPoints()
    button.roundIcon:SetPoint("TOPLEFT", inset, -inset)
    button.roundIcon:SetPoint("BOTTOMRIGHT", -inset, inset)
    button.squareIcon:ClearAllPoints()
    button.squareIcon:SetPoint("TOPLEFT", inset, -inset)
    button.squareIcon:SetPoint("BOTTOMRIGHT", -inset, inset)
    button.cooldown:ClearAllPoints()
    button.cooldown:SetPoint("TOPLEFT", inset, -inset)
    button.cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)

    button.roundBack:SetShown(round and showIconBorder)
    button.roundBackMask:SetShown(round and showIconBorder)
    button.roundIcon:SetShown(round)
    button.roundMask:SetShown(round)
    button.roundHighlight:SetShown(round)
    button.roundHighlightMask:SetShown(round)
    button.squareIcon:SetShown(not round)
    button.squareHighlight:SetShown(not round)
    for _, border in ipairs(button.squareBorders) do
        border:SetShown(not round and showIconBorder)
    end
end

function Runtime:ApplyAppearance()
    if not self.frame then return end
    self.frame:SetAlpha(getBarOpacity())
    self:ApplyFrameStyle(self.layout and self.layout.frameStyle or setting("frame_style"))
    local round = setting("icon_shape") ~= "square"
    local showIconBorder = setting("icon_border") ~= false
    for _, button in ipairs(self.buttons) do
        applyButtonAppearance(button, round, showIconBorder)
    end
end

function Runtime:Render()
    if self.enabled ~= true then return end
    if inCombat() then
        self.pendingRefresh = true
        return
    end
    if not self.frame then self:CreateFrame() end
    local model = self.model or { buttons = {} }
    if #model.buttons == 0 then
        self.frame:Hide()
        return
    end
    local frameStyle = setting("frame_style")
    local iconShape = setting("icon_shape")
    local layout = Addon.TravelBarLogic:GetLayout(
        #model.buttons,
        setting("orientation"),
        frameStyle,
        iconShape
    )
    self.layout = layout
    self:ApplyFrameStyle(layout.frameStyle)
    self.frame:SetAlpha(getBarOpacity())
    self.frame:SetSize(layout.width, layout.height)
    local r, g, b = getRingColor()
    local showIconBorder = setting("icon_border") ~= false

    for index, entry in ipairs(model.buttons) do
        local button = self:GetButton(index)
        button.travelRole = entry.role
        button:SetSize(layout.iconSize, layout.iconSize)
        button:ClearAllPoints()
        local x, y = Addon.TravelBarLogic:GetButtonOffset(layout, index)
        button:SetPoint("TOPLEFT", x, -y)
        applySecureAction(button, entry.action)
        local icon = entry.action.icon or UNKNOWN_ICON
        button.roundIcon:SetTexture(icon)
        button.squareIcon:SetTexture(icon)
        button.roundIcon:SetTexCoord(
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET,
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET
        )
        button.squareIcon:SetTexCoord(
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET,
            ICON_TEXEL_INSET,
            1 - ICON_TEXEL_INSET
        )
        local round = iconShape ~= "square"
        applyButtonAppearance(button, round, showIconBorder)

        applyCooldownVisual(button, entry.action, r, g, b)
        button:Show()
    end
    for index = #model.buttons + 1, #self.buttons do self.buttons[index]:Hide() end
    self.frame:Show()
    if self.manager and self.manager:IsShown() then self:RefreshManager() end
end

function Runtime:AdvanceRandomHearth(avoidKey)
    if inCombat() or not self.model then
        self.pendingRefresh = true
        return
    end
    local nextAction = Addon.TravelBarLogic:PickRandom(self.model.hearths, avoidKey)
    self.currentHearthKey = nextAction and nextAction.key or nil
    local function refreshAfterClick()
        if Runtime.enabled == true and not inCombat() then Runtime:ScheduleRefresh(0) end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, refreshAfterClick)
    else
        refreshAfterClick()
    end
end

local function createManagerHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(26)
    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetPoint("LEFT", 4, 0)
    header.label:SetPoint("RIGHT", -4, 0)
    header.label:SetJustifyH("LEFT")
    header.label:SetTextColor(1, 0.82, 0.24, 1)
    header.kind = "header"
    return header
end

local function createManagerActionRow(parent)
    local row = Addon.Widgets:CreateButton(parent, "", 386, 38, "row")
    row.kind = "action"
    row.checkBox = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    row.checkBox:SetSize(16, 16)
    row.checkBox:SetPoint("LEFT", 7, 0)
    row.checkBox:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    row.checkBox:SetBackdropColor(0.08, 0.07, 0.06, 0.92)
    row.checkBox:SetBackdropBorderColor(0.56, 0.43, 0.16, 0.72)
    row.check = row.checkBox:CreateTexture(nil, "ARTWORK")
    row.check:SetTexture(CHECK_TEXTURE)
    row.check:SetSize(18, 18)
    row.check:SetPoint("CENTER", 0, 0)
    row.check:SetVertexColor(1, 0.82, 0.24, 1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(29, 29)
    row.icon:SetPoint("LEFT", 34, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 70, 0)
    row.label:SetPoint("RIGHT", -66, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.state:SetPoint("RIGHT", -10, 0)
    row.state:SetJustifyH("RIGHT")
    return row
end

function Runtime:CreateManager()
    local manager = CreateFrame(
        "Frame",
        "VaultloomTravelManager",
        UIParent,
        BACKDROP_TEMPLATE
    )
    manager:SetSize(460, 590)
    manager:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    manager:SetFrameStrata("DIALOG")
    manager:SetFrameLevel(MANAGER_MIN_FRAME_LEVEL)
    manager:SetClampedToScreen(true)
    manager:SetMovable(true)
    manager:EnableMouse(true)
    manager:RegisterForDrag("LeftButton")
    Addon.Widgets:ApplyStandardGoldFrame(manager, Addon.Assets.windowBackground)
    manager:SetScript("OnDragStart", function(self) self:StartMoving() end)
    manager:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    manager.title = manager:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    manager.title:SetPoint("TOPLEFT", 22, -20)
    manager.title:SetPoint("TOPRIGHT", -60, -20)
    manager.title:SetJustifyH("LEFT")
    manager.title:SetText(Addon.L.TRAVEL_BAR_MANAGER_TITLE)
    manager.title:SetTextColor(1, 0.82, 0.24, 1)
    manager.subtitle = manager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manager.subtitle:SetPoint("TOPLEFT", 22, -48)
    manager.subtitle:SetPoint("TOPRIGHT", -22, -48)
    manager.subtitle:SetJustifyH("LEFT")
    manager.subtitle:SetWordWrap(true)
    manager.subtitle:SetText(Addon.L.TRAVEL_BAR_MANAGER_SUBTITLE)
    manager.close = Addon.Widgets:CreateButton(manager, "X", 28, 26)
    manager.close:SetPoint("TOPRIGHT", -18, -16)
    manager.close:SetScript("OnClick", function() manager:Hide() end)
    manager.scroll = CreateFrame("ScrollFrame", nil, manager, "UIPanelScrollFrameTemplate")
    manager.scroll:SetPoint("TOPLEFT", 22, -86)
    manager.scroll:SetPoint("BOTTOMRIGHT", -42, 22)
    manager.content = CreateFrame("Frame", nil, manager.scroll)
    manager.content:SetSize(386, 10)
    manager.scroll:SetScrollChild(manager.content)
    Addon.ScrollFrames:Style(manager.scroll, { autoHide = true })
    self.manager = manager
    manager:Hide()
end

function Runtime:GetManagerRow(index, kind)
    local row = self.managerRows[index]
    if row and row.kind ~= kind then
        row:Hide()
        row = nil
    end
    if not row then
        row = kind == "header"
            and createManagerHeader(self.manager.content)
            or createManagerActionRow(self.manager.content)
        self.managerRows[index] = row
    end
    return row
end

local function countVisible(actions, hidden)
    local count = 0
    for _, action in ipairs(actions or {}) do
        if hidden[action.key] ~= true then count = count + 1 end
    end
    return count
end

function Runtime:RefreshConfiguration()
    if self.enabled == true then
        self:ScheduleRefresh(0)
    else
        self.model = self:CollectModel()
        self:RefreshManager()
    end
end

function Runtime:ToggleAction(action)
    if type(action) ~= "table" then return end
    local store = getStore()
    local hidden = store.hidden[action.key] == true
    if not hidden and action.group == "hearth"
        and self.model
        and countVisible(self.model.hearthsAll, store.hidden) <= 1
    then
        showMessage(Addon.L.TRAVEL_BAR_KEEP_ONE_HEARTH)
        return
    end
    if hidden then
        store.hidden[action.key] = nil
    else
        store.hidden[action.key] = true
    end
    self:RefreshConfiguration()
end

function Runtime:RefreshManager()
    if not self.manager or not self.manager:IsShown() then return end
    local model = self.model or self:CollectModel()
    local store = getStore()
    local entries = {
        { kind = "header", label = Addon.L.TRAVEL_BAR_GROUP_HEARTHS },
    }
    for _, action in ipairs(model.hearthsAll or {}) do
        entries[#entries + 1] = { kind = "action", action = action }
    end
    entries[#entries + 1] = { kind = "header", label = Addon.L.TRAVEL_BAR_GROUP_DESTINATIONS }
    for _, action in ipairs(model.travelAll or {}) do
        entries[#entries + 1] = { kind = "action", action = action }
    end
    local y = 0
    for index, entry in ipairs(entries) do
        local row = self:GetManagerRow(index, entry.kind)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        if entry.kind == "header" then
            row.label:SetText(entry.label)
            row:SetHeight(26)
            y = y + 30
        else
            local action = entry.action
            row.action = action
            row.label:SetText(action.label)
            row.icon:SetTexture(action.icon or UNKNOWN_ICON)
            local enabled = store.hidden[action.key] ~= true
            row.check:SetShown(enabled)
            row.state:SetText(enabled and Addon.L.TRAVEL_BAR_STATE_ON or Addon.L.TRAVEL_BAR_STATE_OFF)
            row.state:SetTextColor(
                enabled and 1 or 0.56,
                enabled and 0.82 or 0.56,
                enabled and 0.24 or 0.56,
                1
            )
            row:SetAlpha(enabled and 1 or 0.58)
            row:SetScript("OnClick", function() Runtime:ToggleAction(action) end)
            row:Show()
            y = y + 42
        end
        row:Show()
    end
    for index = #entries + 1, #self.managerRows do self.managerRows[index]:Hide() end
    self.manager.content:SetHeight(math.max(10, y))
    Addon.ScrollFrames:Refresh(self.manager.scroll, false)
end

function Runtime:OpenManager()
    if inCombat() then
        showMessage(Addon.L.TRAVEL_BAR_ERROR_COMBAT)
        return
    end
    self:RequestHousingList()
    self:MarkDirty("housing")
    if self.enabled == true then
        self:ScheduleRefresh(0)
    else
        self.model = self:CollectModel()
    end
    if not self.manager then self:CreateManager() end
    if not self.model then self.model = self:CollectModel() end
    self.manager:Show()
    bringManagerToFront(self.manager)
    self:RefreshManager()
end

function Runtime:HideManager()
    if self.manager then self.manager:Hide() end
end

function Runtime:ScheduleRefresh(delay)
    if self.enabled ~= true then return false end
    if inCombat() then
        self.pendingRefresh = true
        return false
    end
    self.pendingRefresh = false
    return Addon.RefreshScheduler:Invalidate(DOMAIN_ID, delay or 0)
end

function Runtime:OnModelChanged(model)
    self.model = type(model) == "table" and model or { buttons = {} }
    self:Render()
end

function Runtime:RefreshCooldowns()
    if self.enabled ~= true or not self.frame or not self.model then return false end
    local r, g, b = getRingColor()
    for _, button in ipairs(self.buttons) do
        if button:IsShown() and button.travelAction then
            applyCooldownVisual(button, button.travelAction, r, g, b)
        end
    end
    return true
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "PLAYER_REGEN_DISABLED" then
        self:HideManager()
        return
    end
    if eventName == "PLAYER_REGEN_ENABLED" then
        if self.pendingRefresh then self:ScheduleRefresh(0) end
        return
    end
    if eventName == "BAG_UPDATE_COOLDOWN" or eventName == "SPELL_UPDATE_COOLDOWN" then
        if not self:RefreshCooldowns() then self:ScheduleRefresh(0.05) end
        return
    end
    if eventName == "GET_ITEM_INFO_RECEIVED" then
        local itemID = tonumber((...))
        if not itemID or RELEVANT_ITEM_IDS[itemID] ~= true then return end
        self.itemInfoCache[itemID] = nil
        self:MarkDirty("inventory")
        self:ScheduleRefresh(0.05)
        return
    end
    if eventName == "BAG_UPDATE_DELAYED" then
        self:MarkDirty("inventory")
    elseif eventName == "SPELLS_CHANGED" then
        self:MarkDirty("class")
    elseif eventName == "NEW_TOY_ADDED" then
        local itemID = tonumber((...))
        if itemID then self.toyInfoCache[itemID] = nil end
        self:MarkDirty("toys", "inventory")
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        if not self.actionCache then
            self:MarkAllDirty()
        else
            self:MarkDirty("inventory", "class", "housing")
        end
        if not copyHousingTarget(getStore().housingTarget) then
            self:RequestHousingList()
        end
    end
    local delay = eventName == "PLAYER_ENTERING_WORLD" and 0.20 or 0.05
    self:ScheduleRefresh(delay)
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "bar_opacity_percent"
        or settingKey == "outer_border"
        or settingKey == "icon_border"
    then
        self:ApplyAppearance()
        return
    end
    self:ScheduleRefresh(0)
end

function Runtime:ResetSettingValues()
    resetConfiguration()
end

function Runtime:OnSettingsReset()
    self:HideManager()
    self:ScheduleRefresh(0)
end

function Runtime:OnAction(actionKey)
    if actionKey == "manage_destinations" then
        self:OpenManager()
        return true
    end
    if actionKey == "reset_layout" then
        resetConfiguration()
        self:HideManager()
        if self.enabled then self:ScheduleRefresh(0) end
        showMessage(Addon.L.TRAVEL_BAR_LAYOUT_RESET)
        return true
    end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    self.pendingRefresh = false
    self.actionCache = nil
    self.dirty = nil
    self.awaitingHousingList = false
    self:MarkAllDirty()
    Addon.RefreshScheduler:Register(DOMAIN_ID, self, function()
        return Runtime:CollectModel()
    end)
    Addon.StateStore:Subscribe(DOMAIN_ID, self, function(model)
        Runtime:OnModelChanged(model)
    end, true)
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED",
        "BAG_UPDATE_COOLDOWN",
        "SPELLS_CHANGED",
        "SPELL_UPDATE_COOLDOWN",
        "NEW_TOY_ADDED",
        "GET_ITEM_INFO_RECEIVED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    if Addon.Runtime.loggedIn == true or Addon.Runtime.initialized == true then
        if not copyHousingTarget(getStore().housingTarget) then
            self:RequestHousingList()
        end
        self:ScheduleRefresh(0.05)
    end
end

function Runtime:OnDisable()
    self.enabled = false
    self.pendingRefresh = false
    self.actionCache = nil
    self.dirty = nil
    self.housingHouses = nil
    self:StopHousingRequest()
    Addon.StateStore:Set(DOMAIN_ID, { buttons = {} })
    self.model = nil
    self:HideManager()
    if self.frame then
        self.frame:Hide()
        for _, button in ipairs(self.buttons) do button.travelAction = nil end
    end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Travel Bar feature runtime.")
end
