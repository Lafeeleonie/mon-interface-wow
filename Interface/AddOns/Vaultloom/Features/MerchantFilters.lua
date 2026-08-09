local _, Addon = ...

local FEATURE_ID = "merchant_filters"
local WINDOW_WIDTH = 720
local WINDOW_HEIGHT = 620
local ROW_HEIGHT = 56
local ROW_GAP = 5
local ROW_COST_ICON_SIZE = 16
local FOOTER_CURRENCY_ICON_SIZE = 17
local REPAIR_BUTTON_MIN_WIDTH = 196
local REPAIR_BUTTON_TEXT_PADDING = 34
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SCALE_MIN = 75
local SCALE_MAX = 135
local SCALE_STEP = 5
local DISPLAY_MODE_REPLACE = "replace"
local DISPLAY_MODE_COMPANION = "companion"
local DISPLAY_MODE_FILTER_ONLY = "filter_only"

local Logic = Addon.MerchantFiltersLogic
local Widgets = Addon.Widgets
local Theme = Addon.Theme

local Runtime = {
    enabled = false,
    generation = 0,
    refreshGeneration = 0,
    fullRefreshPending = false,
    merchantKey = nil,
    filters = nil,
    search = "",
    activeTab = "buy",
    items = {},
    filtered = {},
    buyback = {},
    itemRows = {},
    classificationCache = {},
    currencyCache = {},
    merchantCurrencies = {},
    merchantCurrencyOrder = {},
    nativeState = nil,
    compatWarned = false,
    frame = nil,
    floatingButton = nil,
    nativeFilterPanel = nil,
    originalFilterApplied = false,
    restoringOriginal = false,
    nativeUpdateHooked = false,
    scanner = nil,
}

Addon.MerchantFilters = Runtime

local SETTING_DEFAULTS = {
    display_mode = "replace",
    save_scope = "merchant",
    scale_percent = 100,
}

local CATEGORY_BUTTONS = {
    { key = "all", label = "MERCHANT_FILTER_CATEGORY_ALL" },
    { key = "recipes", label = "MERCHANT_FILTER_CATEGORY_RECIPES" },
    { key = "gear", label = "MERCHANT_FILTER_CATEGORY_GEAR" },
    { key = "collectibles", label = "MERCHANT_FILTER_CATEGORY_COLLECTIBLES" },
    { key = "decor", label = "MERCHANT_FILTER_CATEGORY_DECOR" },
}

local GEAR_LABELS = {
    head = "MERCHANT_FILTER_GEAR_HEAD",
    neck = "MERCHANT_FILTER_GEAR_NECK",
    shoulder = "MERCHANT_FILTER_GEAR_SHOULDER",
    back = "MERCHANT_FILTER_GEAR_BACK",
    chest = "MERCHANT_FILTER_GEAR_CHEST",
    wrist = "MERCHANT_FILTER_GEAR_WRIST",
    hands = "MERCHANT_FILTER_GEAR_HANDS",
    waist = "MERCHANT_FILTER_GEAR_WAIST",
    legs = "MERCHANT_FILTER_GEAR_LEGS",
    feet = "MERCHANT_FILTER_GEAR_FEET",
    finger = "MERCHANT_FILTER_GEAR_FINGER",
    trinket = "MERCHANT_FILTER_GEAR_TRINKET",
    weapon = "MERCHANT_FILTER_GEAR_WEAPON",
    offhand = "MERCHANT_FILTER_GEAR_OFFHAND",
}

local COMPAT_ADDONS = {
    "VendorFilter",
    "BetterMerchant",
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function clearTable(target)
    for key in pairs(target or {}) do
        target[key] = nil
    end
end

local function safeMethod(object, methodName, ...)
    local method = object and object[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f, g, h = pcall(method, object, ...)
    if ok then
        return a, b, c, d, e, f, g, h
    end
    return nil
end

local function showMessage(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    Addon:Print(message)
end

local function setButtonText(button, text)
    if not button then
        return
    end
    if button.label and type(button.label.SetText) == "function" then
        button.label:SetText(text or "")
    elseif type(button.SetText) == "function" then
        button:SetText(text or "")
    end
end

local function fitRepairButton(button)
    if not button or not button.label then
        return 0
    end
    local textWidth
    if type(button.label.GetUnboundedStringWidth) == "function" then
        textWidth = safeMethod(button.label, "GetUnboundedStringWidth")
    end
    if not tonumber(textWidth) or textWidth <= 0 then
        textWidth = safeMethod(button.label, "GetStringWidth")
    end
    local requiredWidth = math.ceil((tonumber(textWidth) or 0) + REPAIR_BUTTON_TEXT_PADDING)
    local width = math.max(REPAIR_BUTTON_MIN_WIDTH, requiredWidth)
    button:SetWidth(width)
    button.vaultloomRequiredWidth = requiredWidth
    return width
end

local function getSavedSetting(settingKey)
    local value = Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
    if value == nil then
        return SETTING_DEFAULTS[settingKey]
    end
    return value
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.merchantFilters = type(db.features.merchantFilters) == "table"
        and db.features.merchantFilters or {}
    local store = db.features.merchantFilters
    store.version = Logic.version
    store.window = type(store.window) == "table" and store.window or {}
    store.globalFilters = type(store.globalFilters) == "table" and store.globalFilters or {}
    store.merchantProfiles = type(store.merchantProfiles) == "table" and store.merchantProfiles or {}
    return store
end

local function applyPosition(frame)
    if not frame then
        return
    end
    local position = getStore().window
    frame:ClearAllPoints()
    frame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        tonumber(position.x) or 0,
        tonumber(position.y) or 0
    )
end

local function savePosition(frame)
    if not frame or type(frame.GetPoint) ~= "function" then
        return
    end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local position = getStore().window
    position.point = type(point) == "string" and point or "CENTER"
    position.relativePoint = type(relativePoint) == "string" and relativePoint or position.point
    position.x = tonumber(x) or 0
    position.y = tonumber(y) or 0

    if relativeTo and relativeTo ~= UIParent
        and type(frame.GetCenter) == "function"
        and type(UIParent.GetCenter) == "function"
    then
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if centerX and centerY and parentX and parentY then
            position.point = "CENTER"
            position.relativePoint = "CENTER"
            position.x = centerX - parentX
            position.y = centerY - parentY
        end
    end
end

local function formatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    if C_CurrencyInfo and type(C_CurrencyInfo.GetCoinTextureString) == "function" then
        local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper, 12)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    if type(GetCoinTextureString) == "function" then
        local ok, text = pcall(GetCoinTextureString, copper, 12)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    if type(GetMoneyString) == "function" then
        local ok, text = pcall(GetMoneyString, copper)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return tostring(copper) .. "c"
end

local function getMoney()
    if type(GetMoney) ~= "function" then
        return nil
    end
    local ok, money = pcall(GetMoney)
    return ok and tonumber(money) or nil
end

local function isAddonLoaded(addonName)
    return Addon.WoWApi:IsAddOnLoaded(addonName)
end

local function getMerchantCount()
    if C_MerchantFrame and type(C_MerchantFrame.GetNumItems) == "function" then
        local ok, count = pcall(C_MerchantFrame.GetNumItems)
        if ok and tonumber(count) then
            return math.max(0, math.floor(tonumber(count)))
        end
    end
    if type(GetMerchantNumItems) == "function" then
        local ok, count = pcall(GetMerchantNumItems)
        if ok and tonumber(count) then
            return math.max(0, math.floor(tonumber(count)))
        end
    end
    return 0
end

local function getMerchantInfo(index)
    if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then
            return {
                name = info.name,
                texture = info.texture,
                price = math.max(0, tonumber(info.price) or 0),
                stackCount = math.max(1, tonumber(info.stackCount or info.quantity) or 1),
                numAvailable = tonumber(info.numAvailable),
                isPurchasable = info.isPurchasable ~= false,
                isUsable = info.isUsable ~= false,
                hasExtendedCost = info.hasExtendedCost == true,
                currencyID = tonumber(info.currencyID),
                quality = tonumber(info.quality),
                isQuestStartItem = info.isQuestStartItem == true,
            }
        end
    end
    if type(GetMerchantItemInfo) == "function" then
        local ok, name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, hasExtendedCost = pcall(GetMerchantItemInfo, index)
        if ok then
            return {
                name = name,
                texture = texture,
                price = math.max(0, tonumber(price) or 0),
                stackCount = math.max(1, tonumber(stackCount) or 1),
                numAvailable = tonumber(numAvailable),
                isPurchasable = isPurchasable ~= false,
                isUsable = isUsable ~= false,
                hasExtendedCost = hasExtendedCost == true,
            }
        end
    end
    return nil
end

local function getMerchantLink(index)
    if type(GetMerchantItemLink) ~= "function" then
        return nil
    end
    local ok, link = pcall(GetMerchantItemLink, index)
    return ok and type(link) == "string" and link ~= "" and link or nil
end

local function getMerchantItemID(index, link)
    if type(GetMerchantItemID) == "function" then
        local ok, itemID = pcall(GetMerchantItemID, index)
        if ok and tonumber(itemID) then
            return tonumber(itemID)
        end
    end
    return Logic:GetItemIDFromLink(link)
end

local function getStaticItemInfo(itemReference)
    if itemReference == nil then
        return {}
    end

    local result = {}
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(instant) == "function" then
        local ok, itemID, itemType, itemSubType, equipLocation, icon, classID,
            subclassID = pcall(instant, itemReference)
        if ok then
            result.itemID = tonumber(itemID)
            result.itemType = itemType
            result.itemSubType = itemSubType
            result.equipLocation = equipLocation
            result.icon = icon
            result.classID = tonumber(classID)
            result.subclassID = tonumber(subclassID)
        end
    end

    local api = C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(api) == "function" then
        local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount,
            equipLocation, icon, sellPrice, classID, subclassID = pcall(api, itemReference)
        if ok then
            result.name = name
            result.link = link
            result.quality = tonumber(quality)
            result.itemLevel = tonumber(itemLevel)
            result.minLevel = tonumber(minLevel)
            result.itemType = itemType or result.itemType
            result.itemSubType = itemSubType or result.itemSubType
            result.stackCount = tonumber(stackCount)
            result.equipLocation = equipLocation or result.equipLocation
            result.icon = icon or result.icon
            result.sellPrice = tonumber(sellPrice)
            result.classID = tonumber(classID) or result.classID
            result.subclassID = tonumber(subclassID) or result.subclassID
        end
    end
    return result
end

local function requestItemData(itemID)
    if itemID
        and C_Item
        and type(C_Item.RequestLoadItemDataByID) == "function"
    then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function getTooltipLines(index)
    local lines = {}
    local unavailableReason
    local function getColorChannels(color)
        if type(color) ~= "table" then
            return nil
        end
        local red = tonumber(color.r or color[1])
        local green = tonumber(color.g or color[2])
        local blue = tonumber(color.b or color[3])
        if red and green and blue then
            return red, green, blue
        end
        if type(color.GetRGB) == "function" then
            local ok, r, g, b = pcall(color.GetRGB, color)
            if ok then
                return tonumber(r), tonumber(g), tonumber(b)
            end
        end
        return nil
    end
    local function isRestrictionColor(color)
        local red, green, blue = getColorChannels(color)
        return red ~= nil
            and red >= 0.65
            and (green or 1) <= 0.45
            and (blue or 1) <= 0.45
    end
    if C_TooltipInfo and type(C_TooltipInfo.GetMerchantItem) == "function" then
        local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for lineIndex, line in ipairs(data.lines) do
                if type(line) == "table" then
                    local left = type(line.leftText) == "string" and line.leftText or ""
                    local right = type(line.rightText) == "string" and line.rightText or ""
                    local text = left ~= "" and right ~= "" and (left .. " " .. right)
                        or left ~= "" and left or right
                    if text ~= "" then
                        lines[#lines + 1] = text
                        local color = left ~= "" and line.leftColor or line.rightColor
                        if lineIndex > 1
                            and unavailableReason == nil
                            and isRestrictionColor(color)
                        then
                            unavailableReason = text
                        end
                    end
                end
            end
        end
    end
    return lines, unavailableReason
end

local function tooltipSaysKnown(lines)
    local knownText = Logic:NormalizeText(ITEM_SPELL_KNOWN)
    if knownText == "" then
        return false
    end
    for _, line in ipairs(lines or {}) do
        if Logic:NormalizeText(line):find(knownText, 1, true) then
            return true
        end
    end
    return false
end

local function getProfessionNames()
    local result = {}
    for _, profession in ipairs(Addon.WoWApi:GetCurrentProfessions() or {}) do
        local name = Logic:NormalizeText(profession.name)
        if name ~= "" then
            result[name] = true
        end
    end
    return result
end

local function professionMatches(requiredProfession, professionNames)
    local required = Logic:NormalizeText(requiredProfession)
    if required == "" then
        return false
    end
    for professionName in pairs(professionNames or {}) do
        if required == professionName
            or required:find(professionName, 1, true)
            or professionName:find(required, 1, true)
        then
            return true
        end
    end
    return false
end

local function isGenericRecipe(staticInfo)
    local recipeSubclass = Enum and Enum.ItemRecipeSubclass
    return recipeSubclass
        and recipeSubclass.Book ~= nil
        and tonumber(staticInfo.subclassID) == tonumber(recipeSubclass.Book)
end

local function collectCollectionFlags(itemID, link, staticInfo, tooltipLines)
    local flags = {
        isDecor = false,
        isToy = false,
        isPet = false,
        isMount = false,
        isCosmetic = false,
        isKnown = tooltipSaysKnown(tooltipLines),
    }

    if link and C_Item and type(C_Item.IsDecorItem) == "function" then
        local ok, value = pcall(C_Item.IsDecorItem, link)
        flags.isDecor = ok and value == true
    end
    if link and C_Item and type(C_Item.IsCosmeticItem) == "function" then
        local ok, value = pcall(C_Item.IsCosmeticItem, link)
        flags.isCosmetic = ok and value == true
    end
    if staticInfo.equipLocation == "INVTYPE_COSMETIC" then
        flags.isCosmetic = true
    end

    if itemID and C_ToyBox and type(C_ToyBox.GetToyInfo) == "function" then
        local ok, toyName = pcall(C_ToyBox.GetToyInfo, itemID)
        flags.isToy = ok and toyName ~= nil
        if flags.isToy and type(PlayerHasToy) == "function" then
            local knownOk, known = pcall(PlayerHasToy, itemID)
            flags.isKnown = flags.isKnown or (knownOk and known == true)
        end
    end

    if itemID and C_PetJournal and type(C_PetJournal.GetPetInfoByItemID) == "function" then
        local ok, speciesID = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
        flags.isPet = ok and tonumber(speciesID) ~= nil
        if flags.isPet and type(C_PetJournal.GetNumCollectedInfo) == "function" then
            local countOk, count = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
            flags.isKnown = flags.isKnown or (countOk and (tonumber(count) or 0) > 0)
        end
    end

    if itemID and C_MountJournal and type(C_MountJournal.GetMountFromItem) == "function" then
        local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
        flags.isMount = ok and tonumber(mountID) ~= nil
        if flags.isMount and type(C_MountJournal.GetMountInfoByID) == "function" then
            local infoOk, _, _, _, _, _, _, _, _, _, _, isCollected =
                pcall(C_MountJournal.GetMountInfoByID, mountID)
            flags.isKnown = flags.isKnown or (infoOk and isCollected == true)
        end
    end

    if itemID and C_Heirloom and type(C_Heirloom.IsItemHeirloom) == "function" then
        local heirloomOk, isHeirloom = pcall(C_Heirloom.IsItemHeirloom, itemID)
        if heirloomOk and isHeirloom and type(C_Heirloom.PlayerHasHeirloom) == "function" then
            local knownOk, known = pcall(C_Heirloom.PlayerHasHeirloom, itemID)
            flags.isKnown = flags.isKnown or (knownOk and known == true)
        end
    end

    if link and (flags.isCosmetic or staticInfo.equipLocation) and C_TransmogCollection then
        if type(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance) == "function" then
            local ok, known = pcall(
                C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance,
                link
            )
            flags.isKnown = flags.isKnown or (ok and known == true)
        elseif type(C_TransmogCollection.PlayerHasTransmogByItemInfo) == "function" then
            local ok, known = pcall(C_TransmogCollection.PlayerHasTransmogByItemInfo, link)
            flags.isKnown = flags.isKnown or (ok and known == true)
        end
    end
    return flags
end

local function buildTagText(entry)
    local tags = {}
    local function add(condition, key)
        if condition then
            tags[#tags + 1] = Addon.L[key]
        end
    end
    add(entry.isRecipe, "MERCHANT_FILTER_TAG_RECIPE")
    if entry.requiredProfession then
        tags[#tags + 1] = entry.requiredProfession
    end
    add(entry.isDecor, "MERCHANT_FILTER_TAG_DECOR")
    add(entry.isMount, "MERCHANT_FILTER_TAG_MOUNT")
    add(entry.isPet, "MERCHANT_FILTER_TAG_PET")
    add(entry.isToy, "MERCHANT_FILTER_TAG_TOY")
    add(entry.isCosmetic, "MERCHANT_FILTER_TAG_COSMETIC")
    add(entry.isKnown, "MERCHANT_FILTER_TAG_KNOWN")
    return table.concat(tags, " | ")
end

local function getCurrencyInfo(currencyID)
    currencyID = tonumber(currencyID)
    if not currencyID then
        return nil
    end
    local cached = Runtime.currencyCache[currencyID]
    if C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and type(info) == "table" then
            cached = cached or {}
            cached.name = type(info.name) == "string" and info.name ~= "" and info.name or cached.name
            cached.iconFileID = info.iconFileID or info.icon or cached.iconFileID
            cached.quantity = tonumber(info.quantity)
            cached.quality = tonumber(info.quality) or cached.quality
            Runtime.currencyCache[currencyID] = cached
        end
    end
    return cached
end

local function getItemCostInfo(itemID)
    local staticInfo = getStaticItemInfo(itemID)
    return {
        name = staticInfo.name,
        icon = staticInfo.icon,
        quality = tonumber(staticInfo.quality),
    }
end

local function getOwnedCostAmount(cost)
    if cost.currencyID then
        local info = getCurrencyInfo(cost.currencyID)
        return info and tonumber(info.quantity) or nil
    end
    if cost.itemID then
        if C_Item and type(C_Item.GetItemCount) == "function" then
            local ok, count = pcall(C_Item.GetItemCount, cost.itemID, true, false, true)
            if ok and tonumber(count) then
                return tonumber(count)
            end
        end
        if type(GetItemCount) == "function" then
            local ok, count = pcall(GetItemCount, cost.itemID, true)
            if ok and tonumber(count) then
                return tonumber(count)
            end
        end
    end
    return nil
end

local function collectCosts(index)
    local costs = {}
    if type(GetMerchantItemCostInfo) ~= "function"
        or type(GetMerchantItemCostItem) ~= "function"
    then
        return costs
    end
    local ok, count = pcall(GetMerchantItemCostInfo, index)
    count = ok and math.max(0, tonumber(count) or 0) or 0
    for costIndex = 1, count do
        local costOk, texture, amount, link, name =
            pcall(GetMerchantItemCostItem, index, costIndex)
        if costOk and (texture or link or name) then
            local cost = Logic:ResolveCost({
                texture = texture,
                amount = amount,
                link = link,
                name = name,
            }, getCurrencyInfo, getItemCostInfo, getOwnedCostAmount)
            cost.merchantIndex = index
            cost.costIndex = costIndex
            costs[#costs + 1] = cost
        end
    end
    return costs
end

local function canAfford(index, price, costs)
    local apiAffordable
    if type(CanAffordMerchantItem) == "function" then
        local ok, value = pcall(CanAffordMerchantItem, index)
        if ok then
            apiAffordable = Logic:NormalizeApiAffordability(value)
        end
    end
    return Logic:IsAffordable(price, costs, getMoney(), apiAffordable)
end

local function buildStaticClassification(index, info, link, professionNames)
    local itemID = getMerchantItemID(index, link)
    local staticInfo = getStaticItemInfo(link or itemID)
    if itemID and not staticInfo.name then
        requestItemData(itemID)
    end
    local tooltipLines, unavailableReason = getTooltipLines(index)
    local recipeClass = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    local isRecipe = tonumber(staticInfo.classID) == tonumber(recipeClass)
    local requiredProfession = isRecipe
        and type(staticInfo.itemSubType) == "string"
        and staticInfo.itemSubType ~= ""
        and staticInfo.itemSubType or nil
    local hasProfession = professionMatches(requiredProfession, professionNames)
    local collection = collectCollectionFlags(itemID, link, staticInfo, tooltipLines)
    local gearSlot = Logic.gearSlotByEquipLocation[staticInfo.equipLocation]
    local isGear = gearSlot ~= nil
        or tonumber(staticInfo.classID) == tonumber(weaponClass)
        or tonumber(staticInfo.classID) == tonumber(armorClass)

    local entry = {
        itemID = itemID,
        link = link,
        name = info.name or staticInfo.name,
        icon = info.texture or staticInfo.icon,
        quality = tonumber(staticInfo.quality) or tonumber(info.quality),
        itemType = staticInfo.itemType,
        itemSubType = staticInfo.itemSubType,
        equipLocation = staticInfo.equipLocation,
        gearSlot = gearSlot,
        isGear = isGear,
        isRecipe = isRecipe,
        requiredProfession = requiredProfession,
        hasMatchingProfession = hasProfession,
        isOtherProfessionRecipe = isRecipe
            and requiredProfession ~= nil
            and not hasProfession
            and not isGenericRecipe(staticInfo),
        isDecor = collection.isDecor,
        isToy = collection.isToy,
        isPet = collection.isPet,
        isMount = collection.isMount,
        isCosmetic = collection.isCosmetic,
        isKnown = collection.isKnown,
        minLevel = staticInfo.minLevel,
        unavailableReason = unavailableReason,
    }
    entry.name = type(entry.name) == "string" and entry.name ~= ""
        and entry.name or ("Item " .. tostring(itemID or index))
    entry.icon = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    entry.tagText = buildTagText(entry)
    return entry
end

local function classificationKey(index, itemID, link)
    if itemID then
        return "item:" .. tostring(itemID)
    end
    if type(link) == "string" and link ~= "" then
        return link
    end
    return "merchant:" .. tostring(index)
end

local function copyStaticEntry(staticEntry)
    local result = {}
    for key, value in pairs(staticEntry or {}) do
        result[key] = value
    end
    return result
end

local function isMerchantOpen()
    if MerchantFrame and type(MerchantFrame.IsShown) == "function" then
        local ok, shown = pcall(MerchantFrame.IsShown, MerchantFrame)
        if ok and shown == true then
            return true
        end
    end
    if C_PlayerInteractionManager
        and type(C_PlayerInteractionManager.IsInteractingWithNpcOfType) == "function"
        and Enum
        and Enum.PlayerInteractionType
        and Enum.PlayerInteractionType.Merchant
    then
        local ok, interacting = pcall(
            C_PlayerInteractionManager.IsInteractingWithNpcOfType,
            Enum.PlayerInteractionType.Merchant
        )
        return ok and interacting == true
    end
    return false
end

local function getMerchantTitle()
    local function usableText(value)
        return not Logic:IsSecretValue(value)
            and type(value) == "string"
            and value ~= ""
    end

    if type(UnitName) == "function" then
        for _, unit in ipairs({ "npc", "target", "mouseover" }) do
            local ok, name = pcall(UnitName, unit)
            if ok and usableText(name) then
                return name
            end
        end
    end

    local titleRegions = {}
    local function addTitleRegion(region)
        if region then titleRegions[#titleRegions + 1] = region end
    end
    addTitleRegion(_G.MerchantFrameTitleText)
    addTitleRegion(MerchantFrame and MerchantFrame.TitleText)
    addTitleRegion(MerchantFrame and MerchantFrame.TitleContainer
        and MerchantFrame.TitleContainer.TitleText)
    for _, region in ipairs(titleRegions) do
        if region and type(region.GetText) == "function" then
            local ok, title = pcall(region.GetText, region)
            if ok and usableText(title) then return title end
        end
    end
    return MERCHANT or Addon.L.MERCHANT_FILTER_TITLE
end

local function getMerchantGUID()
    if type(UnitGUID) ~= "function" then
        return nil
    end
    for _, unit in ipairs({ "npc", "target", "mouseover" }) do
        local ok, guid = pcall(UnitGUID, unit)
        if ok and not Logic:IsSecretValue(guid) and Logic:GetNPCIDFromGUID(guid) then
            return guid
        end
    end
    return nil
end

local function qualityColor(quality)
    local color = type(ITEM_QUALITY_COLORS) == "table"
        and ITEM_QUALITY_COLORS[tonumber(quality)] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return Theme.colors.parchment[1], Theme.colors.parchment[2], Theme.colors.parchment[3]
end

local function qualityBorderColor(quality)
    local color = type(ITEM_QUALITY_COLORS) == "table"
        and ITEM_QUALITY_COLORS[tonumber(quality)] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3]
end

local function costBorderColor(quality)
    local color = type(ITEM_QUALITY_COLORS) == "table"
        and ITEM_QUALITY_COLORS[tonumber(quality)] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    end
    return Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.82
end

local function formatEntryCost(entry)
    local parts = {}
    if tonumber(entry.price) and entry.price > 0 then
        parts[#parts + 1] = formatMoney(entry.price)
    end
    for _, cost in ipairs(entry.costs or {}) do
        local amount = tostring(math.max(0, tonumber(cost.amount) or 0))
        local colorStart = ""
        local colorEnd = ""
        if cost.owned ~= nil and tonumber(cost.owned) < (tonumber(cost.amount) or 0) then
            colorStart = "|cffff6060"
            colorEnd = "|r"
        end
        if cost.texture then
            parts[#parts + 1] = string.format(
                "%s|T%s:14:14:0:0|t %s%s",
                colorStart,
                tostring(cost.texture),
                amount,
                colorEnd
            )
        else
            parts[#parts + 1] = colorStart .. amount .. " " .. tostring(cost.name or "") .. colorEnd
        end
    end
    return #parts > 0 and table.concat(parts, "   ") or Addon.L.MERCHANT_FILTER_FREE
end

local function setItemTooltip(owner, entry, buyback)
    if not GameTooltip or type(entry) ~= "table" then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if buyback and type(GameTooltip.SetBuybackItem) == "function" then
        pcall(GameTooltip.SetBuybackItem, GameTooltip, entry.index)
    elseif not buyback and type(GameTooltip.SetMerchantItem) == "function" then
        pcall(GameTooltip.SetMerchantItem, GameTooltip, entry.index)
    elseif entry.link and type(GameTooltip.SetHyperlink) == "function" then
        pcall(GameTooltip.SetHyperlink, GameTooltip, entry.link)
    end
    if type(GameTooltip.Show) == "function" then
        GameTooltip:Show()
    end
end

local function setCostTooltip(owner, cost)
    if not GameTooltip or type(cost) ~= "table" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(GameTooltip.ClearLines) == "function" then GameTooltip:ClearLines() end

    local applied = false
    if cost.currencyID and type(GameTooltip.SetCurrencyByID) == "function" then
        applied = pcall(GameTooltip.SetCurrencyByID, GameTooltip, cost.currencyID)
    elseif cost.link and type(GameTooltip.SetHyperlink) == "function" then
        applied = pcall(GameTooltip.SetHyperlink, GameTooltip, cost.link)
    elseif cost.itemID and type(GameTooltip.SetItemByID) == "function" then
        applied = pcall(GameTooltip.SetItemByID, GameTooltip, cost.itemID)
    elseif cost.merchantIndex and cost.costIndex
        and type(GameTooltip.SetMerchantCostItem) == "function"
    then
        applied = pcall(
            GameTooltip.SetMerchantCostItem,
            GameTooltip,
            cost.merchantIndex,
            cost.costIndex
        )
    end
    if not applied and type(GameTooltip.AddLine) == "function" then
        GameTooltip:AddLine(tostring(cost.name or ""), 1, 0.82, 0.24, true)
    end
    if type(GameTooltip.Show) == "function" then GameTooltip:Show() end
end

local function createIconBorder(owner, target, thickness, red, green, blue, alpha)
    local border = {}
    local function edge()
        local texture = owner:CreateTexture(nil, "OVERLAY", nil, 2)
        texture:SetColorTexture(red, green, blue, alpha)
        return texture
    end

    border.top = edge()
    border.top:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
    border.top:SetHeight(thickness)

    border.bottom = edge()
    border.bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(thickness)

    border.left = edge()
    border.left:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(thickness)

    border.right = edge()
    border.right:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(thickness)
    return border
end

local function setIconBorderColor(border, red, green, blue, alpha)
    for _, edge in pairs(border or {}) do
        edge:SetColorTexture(red, green, blue, alpha)
    end
end

local function createCostButton(parent, iconSize, maximumWidth)
    local button = CreateFrame("Button", nil, parent)
    button.iconSize = iconSize
    button.maximumWidth = maximumWidth
    button:SetHeight(iconSize + 2)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if type(button.SetPropagateMouseClicks) == "function" then
        button:SetPropagateMouseClicks(false)
    end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("LEFT", 0, 0)
    button.icon:SetSize(iconSize, iconSize)
    button.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    button.iconBorder = createIconBorder(
        button,
        button.icon,
        1,
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        0.82
    )
    button.amount = Widgets:CreateLabel(button, "GameFontHighlightSmall", "LEFT")
    button.amount:SetPoint("LEFT", button.icon, "RIGHT", 3, 0)
    button.amount:SetPoint("RIGHT", 0, 0)
    button.amount:SetWordWrap(false)
    button.amount:SetMaxLines(1)
    button:SetScript("OnEnter", function(self)
        setCostTooltip(self, self.cost)
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function() end)
    return button
end

local function applyCostButton(button, cost, amount)
    amount = tostring(amount == nil and math.max(0, tonumber(cost and cost.amount) or 0) or amount)
    button.cost = cost
    button.icon:SetTexture(cost and cost.texture)
    setIconBorderColor(button.iconBorder, costBorderColor(cost and cost.quality))
    button.amount:SetText(amount)
    local enough = not cost or cost.owned == nil
        or tonumber(cost.owned) >= (tonumber(cost.amount) or 0)
    if enough then
        button.amount:SetTextColor(
            Theme.colors.parchment[1],
            Theme.colors.parchment[2],
            Theme.colors.parchment[3],
            1
        )
    else
        button.amount:SetTextColor(1, 0.38, 0.38, 1)
    end
    local textWidth = type(button.amount.GetStringWidth) == "function"
        and tonumber(button.amount:GetStringWidth()) or (#amount * 7)
    button:SetWidth(math.min(
        tonumber(button.maximumWidth) or 64,
        (tonumber(button.iconSize) or 16) + 3 + math.max(7, textWidth or 0)
    ))
end

local function updateMerchantCursor(owner, entry, buyback)
    if not owner or type(entry) ~= "table" then
        return
    end
    local mode
    if buyback and type(ShowBuybackSellCursor) == "function" then
        mode = "buyback:" .. tostring(entry.index or 0)
        if owner.merchantCursorMode ~= mode then
            owner.merchantCursorMode = mode
            pcall(ShowBuybackSellCursor, entry.index)
        end
        return
    end
    if not buyback
        and type(IsModifiedClick) == "function"
        and IsModifiedClick("DRESSUP")
        and type(ShowInspectCursor) == "function"
    then
        mode = "inspect"
        if owner.merchantCursorMode ~= mode then
            owner.merchantCursorMode = mode
            pcall(ShowInspectCursor)
        end
        return
    end
    local canUse = buyback and entry.isAffordable ~= false
    if not buyback then
        canUse = entry.isAffordable == true
        if type(CanAffordMerchantItem) == "function" then
            local ok, affordable = pcall(CanAffordMerchantItem, entry.index)
            if ok then
                affordable = Logic:NormalizeApiAffordability(affordable)
                if affordable ~= nil then
                    canUse = affordable
                end
            end
        end
    end
    mode = canUse and "BUY_CURSOR" or "BUY_ERROR_CURSOR"
    if owner.merchantCursorMode ~= mode and type(SetCursor) == "function" then
        owner.merchantCursorMode = mode
        pcall(SetCursor, mode)
    end
end

local function resetMerchantCursor()
    if MerchantFrame then
        MerchantFrame.itemHover = nil
    end
    if type(ResetCursor) == "function" then
        pcall(ResetCursor)
    end
end

local function handleModifiedItemClick(link)
    if type(link) ~= "string" or link == "" or type(HandleModifiedItemClick) ~= "function" then
        return false
    end
    local ok, handled = pcall(HandleModifiedItemClick, link)
    return ok and handled == true
end

local function configurePurchaseProxy(button, entry)
    if not button or type(entry) ~= "table" then
        return
    end
    if type(button.SetID) == "function" then
        button:SetID(entry.index)
    end
    button.count = entry.stackCount or 1
    button.price = entry.price or 0
    button.extendedCost = entry.hasExtendedCost == true
    button.showNonrefundablePrompt = entry.showNonrefundablePrompt == true
    button.name = entry.name
    button.link = entry.link
    button.texture = entry.icon
    button.hasItem = true
end

function Runtime:IsCompatBlocked()
    for _, addonName in ipairs(COMPAT_ADDONS) do
        if isAddonLoaded(addonName) then
            if not self.compatWarned then
                self.compatWarned = true
                showMessage(Addon.L.MERCHANT_FILTER_COMPAT)
            end
            return true
        end
    end
    return false
end

function Runtime:GetEffectiveDisplayMode()
    if self:IsCompatBlocked() then
        return DISPLAY_MODE_COMPANION
    end
    local mode = getSavedSetting("display_mode")
    if mode == DISPLAY_MODE_COMPANION or mode == DISPLAY_MODE_FILTER_ONLY then
        return mode
    end
    return DISPLAY_MODE_REPLACE
end

function Runtime:LoadFilters()
    self.merchantKey = Logic:GetMerchantKey(getMerchantGUID(), getMerchantTitle())
    local store = getStore()
    local scope = getSavedSetting("save_scope")
    if scope == "global" then
        self.filters = Logic:CopyFilters(store.globalFilters)
    elseif scope == "merchant" then
        self.filters = Logic:CopyFilters(store.merchantProfiles[self.merchantKey])
    else
        self.filters = Logic:DefaultFilters()
    end
end

function Runtime:PersistFilters()
    self.filters = Logic:CopyFilters(self.filters)
    local scope = getSavedSetting("save_scope")
    local store = getStore()
    if scope == "global" then
        store.globalFilters = Logic:CopyFilters(self.filters)
    elseif scope == "merchant" and self.merchantKey then
        store.merchantProfiles[self.merchantKey] = Logic:CopyFilters(self.filters)
    end
end

function Runtime:SetCategory(category)
    self.filters = Logic:NormalizeFilters(self.filters)
    self.filters.category = category
    self:PersistFilters()
    self:ApplyFilters()
    self:RefreshWindow(true)
    self:ApplyOriginalFrameFilters()
    self:RefreshNativeFilterPanel()
end

function Runtime:SetFilterValue(filterKey, value)
    self.filters = Logic:NormalizeFilters(self.filters)
    if self.filters[filterKey] ~= nil then
        self.filters[filterKey] = value == true
        self:PersistFilters()
        self:ApplyFilters()
        self:RefreshWindow(true)
        self:ApplyOriginalFrameFilters()
        self:RefreshNativeFilterPanel()
    end
end

function Runtime:SetGearFilter(slotKey, value)
    self.filters = Logic:NormalizeFilters(self.filters)
    self.filters.hiddenGearSlots[slotKey] = value == true and true or nil
    self:PersistFilters()
    self:ApplyFilters()
    self:RefreshWindow(true)
    self:ApplyOriginalFrameFilters()
    self:RefreshNativeFilterPanel()
end

function Runtime:ResetFilters(showConfirmation)
    self.filters = Logic:DefaultFilters()
    self:PersistFilters()
    self.search = ""
    if self.frame and self.frame.search then
        self.frame.search:SetText("")
    end
    if self.nativeFilterPanel and self.nativeFilterPanel.search then
        self.nativeFilterPanel.search:SetText("")
    end
    self:ApplyFilters()
    self:RefreshWindow(true)
    self:ApplyOriginalFrameFilters()
    self:RefreshNativeFilterPanel()
    if showConfirmation then
        showMessage(Addon.L.MERCHANT_FILTER_RESET_DONE)
    end
end

function Runtime:ApplyFilters()
    self.filtered = Logic:FilterItems(self.items, self.filters, self.search)
    self:RefreshFloatingButton()
end

function Runtime:ScanMerchant(fullClassification)
    local professionNames = getProfessionNames()
    clearTable(self.items)
    clearTable(self.merchantCurrencies)
    clearTable(self.merchantCurrencyOrder)

    for index = 1, getMerchantCount() do
        local info = getMerchantInfo(index)
        local link = getMerchantLink(index)
        if info then
            if info.currencyID then
                local currencyInfo = getCurrencyInfo(info.currencyID)
                if currencyInfo then
                    info.name = currencyInfo.name or info.name
                    info.texture = currencyInfo.iconFileID or info.texture
                end
            end

            local itemID = getMerchantItemID(index, link)
            local cacheKey = classificationKey(index, itemID, link)
            local staticEntry = not fullClassification and self.classificationCache[cacheKey] or nil
            if not staticEntry then
                staticEntry = buildStaticClassification(index, info, link, professionNames)
                self.classificationCache[cacheKey] = staticEntry
            end

            local entry = copyStaticEntry(staticEntry)
            entry.index = index
            entry.link = link or entry.link
            entry.name = info.name or entry.name
            entry.icon = info.texture or entry.icon
            entry.price = info.price
            entry.stackCount = info.stackCount
            entry.numAvailable = info.numAvailable
            entry.isPurchasable = info.isPurchasable
            entry.isUsable = info.isUsable
            entry.hasExtendedCost = info.hasExtendedCost
            entry.isQuestStartItem = info.isQuestStartItem == true
            entry.costs = collectCosts(index)
            entry.isAffordable = canAfford(index, entry.price, entry.costs)
            entry.isSoldOut = tonumber(entry.numAvailable) == 0
            entry.canBuy = entry.isPurchasable
                and entry.isAffordable
                and not entry.isSoldOut
            entry.costText = formatEntryCost(entry)
            if C_MerchantFrame and type(C_MerchantFrame.IsMerchantItemRefundable) == "function" then
                local ok, refundable = pcall(C_MerchantFrame.IsMerchantItemRefundable, index)
                entry.showNonrefundablePrompt = ok and refundable == false
            end
            self.items[#self.items + 1] = entry

            for _, cost in ipairs(entry.costs) do
                if cost.key and not self.merchantCurrencies[cost.key] then
                    self.merchantCurrencies[cost.key] = cost
                    self.merchantCurrencyOrder[#self.merchantCurrencyOrder + 1] = cost.key
                elseif cost.key and cost.owned ~= nil then
                    self.merchantCurrencies[cost.key].owned = cost.owned
                end
            end
        end
    end
    self:ApplyFilters()
end

function Runtime:ScanBuyback()
    clearTable(self.buyback)
    if type(GetNumBuybackItems) ~= "function" or type(GetBuybackItemInfo) ~= "function" then
        return
    end
    local ok, count = pcall(GetNumBuybackItems)
    count = ok and math.max(0, tonumber(count) or 0) or 0
    local money = getMoney()
    for index = 1, count do
        local itemOk, name, texture, price, quantity = pcall(GetBuybackItemInfo, index)
        if itemOk and name then
            local link
            if type(GetBuybackItemLink) == "function" then
                local linkOk, value = pcall(GetBuybackItemLink, index)
                link = linkOk and value or nil
            end
            self.buyback[#self.buyback + 1] = {
                index = index,
                name = name,
                icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                price = math.max(0, tonumber(price) or 0),
                quantity = math.max(1, tonumber(quantity) or 1),
                link = link,
                costText = formatMoney(price),
                isAffordable = money == nil or money >= (tonumber(price) or 0),
            }
        end
    end
end

function Runtime:CaptureNativeState()
    local frame = MerchantFrame
    if not frame or self.nativeState then
        return
    end
    self.nativeState = {
        frame = frame,
        alpha = safeMethod(frame, "GetAlpha"),
        mouse = safeMethod(frame, "IsMouseEnabled"),
        strata = safeMethod(frame, "GetFrameStrata"),
        level = safeMethod(frame, "GetFrameLevel"),
    }
end

function Runtime:ConcealNative()
    local frame = MerchantFrame
    if not frame then
        return
    end
    self:CaptureNativeState()
    safeMethod(frame, "SetAlpha", 0)
    safeMethod(frame, "EnableMouse", false)
    safeMethod(frame, "SetFrameStrata", "BACKGROUND")
end

function Runtime:RestoreNative()
    local state = self.nativeState
    self.nativeState = nil
    if type(state) ~= "table" or not state.frame then
        return
    end
    safeMethod(state.frame, "SetAlpha", state.alpha == nil and 1 or state.alpha)
    safeMethod(state.frame, "EnableMouse", state.mouse ~= false)
    if state.strata then
        safeMethod(state.frame, "SetFrameStrata", state.strata)
    end
    if state.level then
        safeMethod(state.frame, "SetFrameLevel", state.level)
    end
    local windowMover = Addon.BlizzardWindowMover
    if windowMover
        and windowMover.enabled == true
        and type(windowMover.RegisterWindow) == "function"
    then
        windowMover:RegisterWindow("MerchantFrame")
    end
end

function Runtime:Purchase(entry, quantity, proxy)
    if type(entry) ~= "table" or not entry.canBuy or type(BuyMerchantItem) ~= "function" then
        return false
    end
    quantity = math.max(1, math.floor(tonumber(quantity) or entry.stackCount or 1))
    proxy = proxy or (self.frame and self.frame.purchaseProxy)
    configurePurchaseProxy(proxy, entry)

    if proxy and type(MerchantFrame_ConfirmExtendedItemCost) == "function" then
        local ok = pcall(MerchantFrame_ConfirmExtendedItemCost, proxy, quantity)
        if ok then
            self:ScheduleRefresh(0.08, false)
            return true
        end
    end

    local ok = pcall(BuyMerchantItem, entry.index, quantity)
    if ok then
        self:ScheduleRefresh(0.08, false)
    end
    return ok
end

local function restoreStackSplitFrameStrata(frame)
    if not frame or not frame.vaultloomMerchantOriginalStrata then
        return
    end
    safeMethod(frame, "SetFrameStrata", frame.vaultloomMerchantOriginalStrata)
    frame.vaultloomMerchantOriginalStrata = nil
end

local function elevateStackSplitFrame(frame)
    if not frame then
        return
    end
    if not frame.vaultloomMerchantStrataHooked and type(frame.HookScript) == "function" then
        frame.vaultloomMerchantStrataHooked = true
        frame:HookScript("OnHide", function(self)
            restoreStackSplitFrameStrata(self)
        end)
    end
    if not frame.vaultloomMerchantOriginalStrata then
        frame.vaultloomMerchantOriginalStrata = safeMethod(frame, "GetFrameStrata") or "HIGH"
    end
    safeMethod(frame, "SetFrameStrata", "FULLSCREEN_DIALOG")
end

function Runtime:OpenQuantity(entry, proxy)
    if type(entry) ~= "table" or not entry.canBuy then
        return false
    end
    local maxStack = entry.stackCount or 1
    if type(GetMerchantItemMaxStack) == "function" then
        local ok, value = pcall(GetMerchantItemMaxStack, entry.index)
        if ok and tonumber(value) then
            maxStack = math.max(maxStack, tonumber(value))
        end
    end

    local maximum = maxStack
    if entry.price and entry.price > 0 and getMoney() then
        maximum = math.min(
            maximum,
            math.floor(getMoney() / math.max(1, entry.price / math.max(1, entry.stackCount)))
        )
    end
    for _, cost in ipairs(entry.costs or {}) do
        if cost.owned ~= nil and cost.amount and cost.amount > 0 then
            maximum = math.min(
                maximum,
                math.floor(cost.owned / math.max(0.0001, cost.amount / entry.stackCount))
            )
        end
    end
    maximum = math.max(0, math.floor(maximum))
    if maximum <= entry.stackCount then
        return self:Purchase(entry, entry.stackCount, proxy)
    end

    configurePurchaseProxy(proxy, entry)
    proxy.SplitStack = function(button, split)
        Runtime:Purchase(entry, split, button)
    end
    if StackSplitFrame and type(StackSplitFrame.OpenStackSplitFrame) == "function" then
        elevateStackSplitFrame(StackSplitFrame)
        local ok = pcall(
            StackSplitFrame.OpenStackSplitFrame,
            StackSplitFrame,
            maximum,
            proxy,
            "BOTTOMLEFT",
            "TOPLEFT",
            entry.stackCount
        )
        if not ok then
            restoreStackSplitFrameStrata(StackSplitFrame)
        end
        return ok
    end
    return self:Purchase(entry, entry.stackCount, proxy)
end

function Runtime:HandleItemClick(entry, button, proxy, buyback)
    if handleModifiedItemClick(entry and entry.link) then
        return
    end
    if buyback then
        if type(BuybackItem) == "function" then
            pcall(BuybackItem, entry.index)
            self:ScheduleRefresh(0.08, false)
        end
        return
    end
    if type(IsModifiedClick) == "function" and IsModifiedClick("SPLITSTACK") then
        self:OpenQuantity(entry, proxy)
        return
    end
    self:Purchase(entry, entry.stackCount, proxy)
end

local function createCheckButton(parent, label, width)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetSize(24, 24)
    button.label = Widgets:CreateLabel(button, "GameFontHighlightSmall", "LEFT")
    button.label:SetPoint("LEFT", button, "RIGHT", 1, 0)
    button.label:SetWidth(width or 160)
    button.label:SetText(label or "")
    return button
end

local function createItemIcon(parent, size)
    local iconFrame = CreateFrame(
        "Frame",
        nil,
        parent,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    iconFrame:SetSize(size, size)
    iconFrame:EnableMouse(false)
    iconFrame:SetBackdrop({
        bgFile = Addon.Assets.cardInset,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    iconFrame:SetBackdropColor(1, 1, 1, 1)
    iconFrame:SetBackdropBorderColor(
        Theme.colors.goldDim[1],
        Theme.colors.goldDim[2],
        Theme.colors.goldDim[3],
        1
    )
    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("TOPLEFT", 2, -2)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return iconFrame
end

function Runtime:EnsureItemRow(parent, index)
    if self.itemRows[index] then
        return self.itemRows[index]
    end
    local row = CreateFrame(
        "Button",
        nil,
        parent,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    Widgets:ApplyPanelStyle(row, "row")
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.iconButton = createItemIcon(row, 40)
    row.iconButton:SetPoint("LEFT", 8, 0)
    row.nameLabel = Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.nameLabel:SetPoint("TOPLEFT", row.iconButton, "TOPRIGHT", 9, -1)
    row.nameLabel:SetPoint("RIGHT", -154, 0)
    row.nameLabel:SetWordWrap(false)
    row.nameLabel:SetMaxLines(1)
    row.tags = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.tags:SetPoint("TOPLEFT", row.nameLabel, "BOTTOMLEFT", 0, -4)
    row.tags:SetPoint("RIGHT", -154, 0)
    row.tags:SetWordWrap(false)
    row.tags:SetMaxLines(1)
    row.cost = Widgets:CreateLabel(row, "GameFontHighlightSmall", "RIGHT")
    row.cost:SetWordWrap(false)
    row.cost:SetMaxLines(1)
    row.costButtons = {}
    row.stock = Widgets:CreateLabel(row, "GameFontDisableSmall", "RIGHT")
    row.stock:SetPoint("BOTTOMRIGHT", -9, 8)
    row.stock:SetWidth(116)
    row.stock:SetWordWrap(false)
    row.stock:SetMaxLines(1)
    row.lockIcon = row:CreateTexture(nil, "OVERLAY")
    row.lockIcon:SetPoint("BOTTOMRIGHT", -9, 6)
    row.lockIcon:SetSize(18, 18)
    row.lockIcon:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    row.lockIcon:SetVertexColor(1, 0.30, 0.30, 1)
    row.lockIcon:Hide()
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetPoint("TOPLEFT", 1, -1)
    row.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    row.hover:SetColorTexture(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        0.10
    )
    row.hover:SetAlpha(0)
    self.itemRows[index] = row
    return row
end

function Runtime:ApplyItemRow(row, entry, buyback)
    row.unavailableReason = nil
    row.compactUnavailableReason = false
    if row.lockIcon then row.lockIcon:Hide() end
    row.iconButton.icon:SetTexture(entry.icon)
    local quality = entry.quality
    if buyback and entry.link and C_Item and type(C_Item.GetItemQualityByID) == "function" then
        local ok, value = pcall(C_Item.GetItemQualityByID, entry.link)
        quality = ok and value or quality
    end
    local r, g, b = qualityColor(quality)
    local borderR, borderG, borderB = qualityBorderColor(quality)
    row.iconButton:SetBackdropBorderColor(borderR, borderG, borderB, 1)
    row.nameLabel:SetText(entry.name)
    row.nameLabel:SetTextColor(r, g, b, 1)
    row.tags:SetText(buyback and ("x" .. tostring(entry.quantity or 1)) or (entry.tagText or ""))
    for _, button in ipairs(row.costButtons) do
        button:Hide()
        button.cost = nil
    end
    local costs = not buyback and entry.costs or nil
    local costAnchorX = -9
    for costIndex = #(costs or {}), 1, -1 do
        local cost = costs[costIndex]
        local button = row.costButtons[costIndex]
        if not button then
            button = createCostButton(row, ROW_COST_ICON_SIZE, 52)
            button:SetFrameLevel(row:GetFrameLevel() + 3)
            row.costButtons[costIndex] = button
        end
        applyCostButton(button, cost)
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", row, "TOPRIGHT", costAnchorX, -6)
        costAnchorX = costAnchorX - button:GetWidth() - 7
        button:Show()
    end
    row.cost:ClearAllPoints()
    row.cost:SetPoint("TOPRIGHT", row, "TOPRIGHT", costAnchorX, -8)
    row.cost:SetWidth(math.max(54, 140 + costAnchorX + 9))
    local goldCost = tonumber(entry.price) or 0
    if goldCost > 0 then
        row.cost:SetText(formatMoney(goldCost))
        row.cost:Show()
    elseif #(costs or {}) == 0 then
        row.cost:SetText(Addon.L.MERCHANT_FILTER_FREE)
        row.cost:Show()
    else
        row.cost:SetText("")
        row.cost:Hide()
    end
    if buyback then
        row.stock:SetText("")
        row.stock:SetTextColor(
            Theme.colors.muted[1],
            Theme.colors.muted[2],
            Theme.colors.muted[3],
            1
        )
    else
        if entry.isSoldOut then
            row.stock:SetText(Addon.L.MERCHANT_FILTER_SOLD_OUT)
            row.stock:SetTextColor(1, 0.30, 0.30, 1)
        elseif not entry.isPurchasable or not entry.isUsable then
            local reason = entry.unavailableReason
            local playerLevel = type(UnitLevel) == "function" and tonumber(UnitLevel("player")) or nil
            if (type(reason) ~= "string" or reason == "")
                and tonumber(entry.minLevel)
                and (playerLevel == nil or playerLevel < tonumber(entry.minLevel))
            then
                local template = ITEM_MIN_LEVEL or Addon.L.MERCHANT_FILTER_REQUIRES_LEVEL
                local ok, text = pcall(string.format, template, entry.minLevel)
                reason = ok and text or nil
            end
            reason = type(reason) == "string" and reason ~= ""
                and reason or Addon.L.MERCHANT_FILTER_UNAVAILABLE
            row.unavailableReason = reason
            row.stock:SetText("")
            row.stock:SetTextColor(
                Theme.colors.muted[1],
                Theme.colors.muted[2],
                Theme.colors.muted[3],
                1
            )
            if row.lockIcon then row.lockIcon:Show() end
        elseif tonumber(entry.numAvailable) and entry.numAvailable > 0 then
            row.stock:SetText(string.format(Addon.L.MERCHANT_FILTER_STOCK, entry.numAvailable))
            row.stock:SetTextColor(
                Theme.colors.muted[1],
                Theme.colors.muted[2],
                Theme.colors.muted[3],
                1
            )
        else
            row.stock:SetText("")
            row.stock:SetTextColor(
                Theme.colors.muted[1],
                Theme.colors.muted[2],
                Theme.colors.muted[3],
                1
            )
        end
    end

    row:SetScript("OnEnter", function(self)
        self.hover:SetAlpha(1)
        self:SetBackdropBorderColor(
            Theme.colors.gold[1],
            Theme.colors.gold[2],
            Theme.colors.gold[3],
            1
        )
        setItemTooltip(self, entry, buyback)
        if not buyback and MerchantFrame then
            MerchantFrame.itemHover = entry.index
        end
        updateMerchantCursor(self, entry, buyback)
        self:SetScript("OnUpdate", function(activeRow)
            updateMerchantCursor(activeRow, entry, buyback)
        end)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.merchantCursorMode = nil
        if MerchantFrame and MerchantFrame.itemHover == entry.index then
            MerchantFrame.itemHover = nil
        end
        if type(ResetCursor) == "function" then
            pcall(ResetCursor)
        end
        self.hover:SetAlpha(0)
        self:SetBackdropBorderColor(
            Theme.colors.goldDim[1],
            Theme.colors.goldDim[2],
            Theme.colors.goldDim[3],
            1
        )
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", function(self, button)
        if buyback and not entry.isAffordable then
            return
        end
        Runtime:HandleItemClick(entry, button, self, buyback)
    end)
    configurePurchaseProxy(row, entry)
end

function Runtime:BuildWindow()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame(
        "Frame",
        "VaultloomMerchantWindow",
        UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)
    applyPosition(frame)
    frame:SetScale(clamp(getSavedSetting("scale_percent"), SCALE_MIN, SCALE_MAX) / 100)

    frame.purchaseProxy = CreateFrame("Button", nil, frame)
    frame.purchaseProxy:Hide()

    frame.header = Widgets:CreatePanel(frame, "hero")
    frame.header:SetPoint("TOPLEFT", 14, -14)
    frame.header:SetPoint("TOPRIGHT", -14, -14)
    frame.header:SetHeight(60)
    frame.header:EnableMouse(true)
    frame.header:EnableMouseWheel(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        frame.dragging = true
        frame:StartMoving()
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame)
        frame.dragging = false
    end)

    local function scaleWithWheel(_, delta)
        local control = type(IsControlKeyDown) == "function" and IsControlKeyDown()
        local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
        if not control and not shift then
            return
        end
        local current = clamp(getSavedSetting("scale_percent"), SCALE_MIN, SCALE_MAX)
        local nextValue = clamp(
            current + (delta > 0 and SCALE_STEP or -SCALE_STEP),
            SCALE_MIN,
            SCALE_MAX
        )
        Addon.FeatureRegistry:SetSetting(FEATURE_ID, "scale_percent", nextValue)
    end
    frame:SetScript("OnMouseWheel", scaleWithWheel)
    frame.header:SetScript("OnMouseWheel", scaleWithWheel)

    frame.portraitRing = frame.header:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.portraitRing:SetSize(50, 50)
    frame.portraitRing:SetPoint("LEFT", 7, 0)
    frame.portraitRing:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    frame.portraitRing:SetVertexColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )
    frame.portrait = frame.header:CreateTexture(nil, "OVERLAY")
    frame.portrait:SetSize(46, 46)
    frame.portrait:SetPoint("CENTER", frame.portraitRing, "CENTER", 0, 0)
    frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.portraitMask = frame.header:CreateMaskTexture()
    frame.portraitMask:SetTexture(
        "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    frame.portraitMask:SetAllPoints(frame.portrait)
    frame.portrait:AddMaskTexture(frame.portraitMask)
    frame.title = Widgets:CreateLabel(frame.header, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", frame.portrait, "TOPRIGHT", 10, -3)
    frame.title:SetPoint("RIGHT", -52, 0)
    frame.title:SetTextColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )
    frame.subtitle = Widgets:CreateLabel(frame.header, "GameFontDisableSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.subtitle:SetPoint("RIGHT", -52, 0)
    frame.subtitle:SetText(Addon.L.MERCHANT_FILTER_SUBTITLE)
    frame.close = Widgets:CreateButton(frame.header, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -8, -8)
    frame.close:SetScript("OnClick", function()
        if Runtime:GetEffectiveDisplayMode() == "replace" and type(CloseMerchant) == "function" then
            CloseMerchant()
        else
            frame:Hide()
        end
    end)

    frame.buyTab = Widgets:CreateButton(frame, Addon.L.MERCHANT_FILTER_BUY_TAB, 138, 30, "tab")
    frame.buyTab:SetPoint("TOPLEFT", 20, -86)
    frame.buybackTab = Widgets:CreateButton(frame, Addon.L.MERCHANT_FILTER_BUYBACK_TAB, 138, 30, "tab")
    frame.buybackTab:SetPoint("LEFT", frame.buyTab, "RIGHT", 7, 0)
    frame.buyTab:SetScript("OnClick", function()
        Runtime.activeTab = "buy"
        Runtime:RefreshWindow(true)
    end)
    frame.buybackTab:SetScript("OnClick", function()
        Runtime.activeTab = "buyback"
        Runtime:ScanBuyback()
        Runtime:RefreshWindow(true)
    end)

    frame.filterPanel = Widgets:CreatePanel(frame, "sidebar")
    frame.filterPanel:SetPoint("TOPLEFT", 20, -126)
    frame.filterPanel:SetPoint("BOTTOMLEFT", 20, 62)
    frame.filterPanel:SetWidth(214)
    frame.filterTitle = Widgets:CreateLabel(frame.filterPanel, "GameFontNormal", "LEFT")
    frame.filterTitle:SetPoint("TOPLEFT", 12, -11)
    frame.filterTitle:SetText(Addon.L.MERCHANT_FILTERS)
    frame.filterTitle:SetTextColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )

    frame.categoryButtons = {}
    frame.basicControls = {}
    local previous
    for _, descriptor in ipairs(CATEGORY_BUTTONS) do
        local button = Widgets:CreateButton(
            frame.filterPanel,
            Addon.L[descriptor.label],
            188,
            25,
            "row"
        )
        if previous then
            button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -5)
        else
            button:SetPoint("TOPLEFT", 12, -38)
        end
        button:SetScript("OnClick", function()
            Runtime:SetCategory(descriptor.key)
        end)
        frame.categoryButtons[descriptor.key] = button
        frame.basicControls[#frame.basicControls + 1] = button
        previous = button
    end

    frame.filterChecks = {}
    for index, descriptor in ipairs({
        { key = "hideKnown", label = "MERCHANT_FILTER_HIDE_KNOWN" },
        { key = "hideOtherProfessions", label = "MERCHANT_FILTER_HIDE_OTHER_PROFESSIONS" },
        { key = "affordableOnly", label = "MERCHANT_FILTER_AFFORDABLE_ONLY" },
        { key = "usableOnly", label = "MERCHANT_FILTER_USABLE_ONLY" },
    }) do
        local check = createCheckButton(frame.filterPanel, Addon.L[descriptor.label], 166)
        if index == 1 then
            check:SetPoint("TOPLEFT", 12, -198)
        else
            check:SetPoint("TOPLEFT", frame.filterChecks[index - 1], "BOTTOMLEFT", 0, -5)
        end
        check:SetScript("OnClick", function(self)
            Runtime:SetFilterValue(descriptor.key, self:GetChecked())
        end)
        frame.filterChecks[index] = check
        frame.filterChecks[descriptor.key] = check
        frame.basicControls[#frame.basicControls + 1] = check
    end

    frame.advanced = Widgets:CreateButton(
        frame.filterPanel,
        Addon.L.MERCHANT_FILTER_ADVANCED,
        188,
        27
    )
    frame.advanced:SetPoint("BOTTOMLEFT", 12, 45)
    frame.advanced:SetScript("OnClick", function()
        frame.showAdvanced = true
        Runtime:RefreshFilterControls()
    end)
    frame.basicControls[#frame.basicControls + 1] = frame.advanced

    frame.resetFilters = Widgets:CreateButton(
        frame.filterPanel,
        Addon.L.MERCHANT_FILTER_RESET,
        188,
        27
    )
    frame.resetFilters:SetPoint("BOTTOMLEFT", 12, 12)
    frame.resetFilters:SetScript("OnClick", function()
        Runtime:ResetFilters(false)
    end)

    frame.advancedControls = {}
    frame.basic = Widgets:CreateButton(
        frame.filterPanel,
        Addon.L.MERCHANT_FILTER_BASIC,
        188,
        27
    )
    frame.basic:SetPoint("TOPLEFT", 12, -38)
    frame.basic:SetScript("OnClick", function()
        frame.showAdvanced = false
        Runtime:RefreshFilterControls()
    end)
    frame.advancedControls[#frame.advancedControls + 1] = frame.basic

    frame.hideAllGear = createCheckButton(
        frame.filterPanel,
        Addon.L.MERCHANT_FILTER_HIDE_ALL_GEAR,
        166
    )
    frame.hideAllGear:SetPoint("TOPLEFT", 12, -75)
    frame.hideAllGear:SetScript("OnClick", function(self)
        Runtime:SetFilterValue("hideAllGear", self:GetChecked())
    end)
    frame.advancedControls[#frame.advancedControls + 1] = frame.hideAllGear

    frame.gearChecks = {}
    for index, slotKey in ipairs(Logic.gearSlotOrder) do
        local check = createCheckButton(frame.filterPanel, Addon.L[GEAR_LABELS[slotKey]], 68)
        local column = (index - 1) % 2
        local rowIndex = math.floor((index - 1) / 2)
        check:SetPoint("TOPLEFT", 12 + (column * 96), -112 - (rowIndex * 34))
        check:SetScript("OnClick", function(self)
            Runtime:SetGearFilter(slotKey, self:GetChecked())
        end)
        frame.gearChecks[slotKey] = check
        frame.advancedControls[#frame.advancedControls + 1] = check
    end

    frame.search = CreateFrame(
        "EditBox",
        nil,
        frame,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    frame.search:SetPoint("TOPLEFT", 248, -126)
    frame.search:SetSize(285, 28)
    frame.search:SetAutoFocus(false)
    frame.search:SetFontObject("GameFontHighlightSmall")
    frame.search:SetTextInsets(8, 8, 0, 0)
    Widgets:ApplyPanelStyle(frame.search, "cardInset")
    frame.searchHint = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.searchHint:SetPoint("RIGHT", -8, 0)
    frame.searchHint:SetText(Addon.L.MERCHANT_FILTER_SEARCH_HINT)
    frame.search:SetScript("OnTextChanged", function(self)
        Runtime.search = self:GetText() or ""
        frame.searchHint:SetShown(Runtime.search == "")
        Runtime:ApplyFilters()
        Runtime:RefreshWindow(true)
    end)
    frame.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.results = Widgets:CreateLabel(frame, "GameFontDisableSmall", "RIGHT")
    frame.results:SetPoint("LEFT", frame.search, "RIGHT", 10, 0)
    frame.results:SetPoint("RIGHT", -24, 0)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 248, -164)
    frame.scroll:SetPoint("BOTTOMRIGHT", -40, 62)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(426, 20)
    frame.scroll:SetScrollChild(frame.child)
    Addon.ScrollFrames:Style(frame.scroll, { autoHide = true })
    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisable", "CENTER")
    frame.empty:SetPoint("TOP", 0, -48)
    frame.empty:SetWidth(370)

    frame.footer = Widgets:CreatePanel(frame, "utility")
    frame.footer:SetPoint("BOTTOMLEFT", 20, 14)
    frame.footer:SetPoint("BOTTOMRIGHT", -20, 14)
    frame.footer:SetHeight(38)
    frame.money = Widgets:CreateLabel(frame.footer, "GameFontHighlightSmall", "LEFT")
    frame.money:SetPoint("LEFT", 10, 0)
    frame.money:SetWidth(180)
    frame.repair = Widgets:CreateButton(
        frame.footer,
        Addon.L.MERCHANT_FILTER_REPAIR,
        REPAIR_BUTTON_MIN_WIDTH,
        26
    )
    frame.repair:SetPoint("RIGHT", -7, 0)
    frame.repair.label:SetWordWrap(false)
    frame.repair.label:SetMaxLines(1)
    fitRepairButton(frame.repair)
    frame.repair:SetScript("OnClick", function()
        if type(RepairAllItems) == "function" then
            pcall(RepairAllItems, false)
            Runtime:ScheduleRefresh(0.08, false)
        end
    end)
    frame.currencies = CreateFrame("Frame", nil, frame.footer)
    frame.currencies:SetPoint("LEFT", frame.money, "RIGHT", 10, 0)
    frame.currencies:SetPoint("RIGHT", frame.repair, "LEFT", -8, 0)
    frame.currencies:SetHeight(24)
    frame.currencyButtons = {}

    frame:SetScript("OnShow", function()
        Runtime:RefreshWindow(false)
    end)
    frame:Hide()
    self.frame = frame
    self:RefreshFilterControls()
    return frame
end

function Runtime:RefreshFilterControls()
    local frame = self.frame
    if not frame then
        return
    end
    self.filters = Logic:NormalizeFilters(self.filters)
    local advanced = frame.showAdvanced == true
    for _, control in ipairs(frame.basicControls or {}) do
        control:SetShown(not advanced)
    end
    for _, control in ipairs(frame.advancedControls or {}) do
        control:SetShown(advanced)
    end
    for category, button in pairs(frame.categoryButtons or {}) do
        Widgets:SetButtonActive(button, self.filters.category == category)
    end
    for key, check in pairs(frame.filterChecks or {}) do
        if type(key) == "string" and type(check.SetChecked) == "function" then
            check:SetChecked(self.filters[key] == true)
        end
    end
    frame.hideAllGear:SetChecked(self.filters.hideAllGear == true)
    for slotKey, check in pairs(frame.gearChecks or {}) do
        check:SetChecked(self.filters.hiddenGearSlots[slotKey] == true)
    end
end

function Runtime:RefreshFooter()
    local frame = self.frame
    if not frame then
        return
    end
    frame.money:SetText(formatMoney(getMoney() or 0))
    local shownCurrencies = 0
    local previousCurrencyButton
    for _, key in ipairs(self.merchantCurrencyOrder) do
        if shownCurrencies >= 5 then break end
        local cost = self.merchantCurrencies[key]
        if cost and cost.texture then
            shownCurrencies = shownCurrencies + 1
            local button = frame.currencyButtons[shownCurrencies]
            if not button then
                button = createCostButton(frame.currencies, FOOTER_CURRENCY_ICON_SIZE, 56)
                frame.currencyButtons[shownCurrencies] = button
            end
            applyCostButton(
                button,
                cost,
                cost.owned == nil and "?" or tostring(math.floor(cost.owned))
            )
            button:ClearAllPoints()
            if previousCurrencyButton then
                button:SetPoint("LEFT", previousCurrencyButton, "RIGHT", 7, 0)
            else
                button:SetPoint("LEFT", frame.currencies, "LEFT", 0, 0)
            end
            button:Show()
            previousCurrencyButton = button
        end
    end
    for index = shownCurrencies + 1, #frame.currencyButtons do
        frame.currencyButtons[index]:Hide()
        frame.currencyButtons[index].cost = nil
    end

    local canRepair = false
    if type(CanMerchantRepair) == "function" then
        local ok, value = pcall(CanMerchantRepair)
        canRepair = ok and value == true
    end
    frame.repair:SetShown(canRepair)
    if canRepair and type(GetRepairAllCost) == "function" then
        local ok, cost, possible = pcall(GetRepairAllCost)
        if ok then
            setButtonText(
                frame.repair,
                Addon.L.MERCHANT_FILTER_REPAIR .. (cost and cost > 0 and ("  " .. formatMoney(cost)) or "")
            )
            fitRepairButton(frame.repair)
            if possible == false or (getMoney() and cost and cost > getMoney()) then
                frame.repair:Disable()
            else
                frame.repair:Enable()
            end
        end
    end
end

function Runtime:RefreshWindow(resetScroll)
    local frame = self.frame
    if not frame or not frame:IsShown() then
        return
    end
    self:RefreshFilterControls()
    Widgets:SetButtonActive(frame.buyTab, self.activeTab == "buy")
    Widgets:SetButtonActive(frame.buybackTab, self.activeTab == "buyback")

    local entries
    local buyback = self.activeTab == "buyback"
    if buyback then
        entries = {}
        for _, entry in ipairs(self.buyback) do
            if Logic:MatchesSearch(entry, self.search) then
                entries[#entries + 1] = entry
            end
        end
        frame.results:SetText(string.format(Addon.L.MERCHANT_FILTER_RESULTS, #entries, #self.buyback))
        frame.empty:SetText(Addon.L.MERCHANT_FILTER_BUYBACK_EMPTY)
    else
        entries = self.filtered
        frame.results:SetText(string.format(Addon.L.MERCHANT_FILTER_RESULTS, #entries, #self.items))
        frame.empty:SetText(Addon.L.MERCHANT_FILTER_EMPTY)
    end

    for _, row in ipairs(self.itemRows) do
        row:Hide()
    end
    local previous
    for index, entry in ipairs(entries) do
        local row = self:EnsureItemRow(frame.child, index)
        row:ClearAllPoints()
        if previous then
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_GAP)
        else
            row:SetPoint("TOPLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", -2, 0)
        self:ApplyItemRow(row, entry, buyback)
        row:Show()
        previous = row
    end
    local contentHeight = math.max(
        20,
        (#entries * ROW_HEIGHT) + (math.max(0, #entries - 1) * ROW_GAP)
    )
    frame.child:SetHeight(contentHeight)
    frame.empty:SetShown(#entries == 0)
    Addon.ScrollFrames:Refresh(frame.scroll, resetScroll == true)
    self:RefreshFooter()
end

local function getOriginalMerchantSlot(buttonIndex)
    local slot = _G["MerchantItem" .. buttonIndex]
        or _G["MerchantFrameItem" .. buttonIndex]
    local itemButton = _G["MerchantItem" .. buttonIndex .. "ItemButton"]
        or (slot and slot.ItemButton)
    local itemName = _G["MerchantItem" .. buttonIndex .. "Name"]
        or (slot and slot.Name)
    return slot, itemButton, itemName
end

local function setOriginalSlotVertexColor(slot, itemButton, red, green, blue)
    if slot and type(SetItemButtonNameFrameVertexColor) == "function" then
        pcall(SetItemButtonNameFrameVertexColor, slot, red, green, blue)
    end
    if slot and type(SetItemButtonSlotVertexColor) == "function" then
        pcall(SetItemButtonSlotVertexColor, slot, red, green, blue)
    end
    if itemButton and type(SetItemButtonTextureVertexColor) == "function" then
        pcall(SetItemButtonTextureVertexColor, itemButton, red, green, blue)
    end
    if itemButton and type(SetItemButtonNormalTextureVertexColor) == "function" then
        pcall(SetItemButtonNormalTextureVertexColor, itemButton, red, green, blue)
    end
end

local function hideOriginalSlotCosts(buttonIndex)
    local moneyFrame = _G["MerchantItem" .. buttonIndex .. "MoneyFrame"]
    local altCurrency = _G["MerchantItem" .. buttonIndex .. "AltCurrencyFrame"]
    if moneyFrame then
        moneyFrame:Hide()
    end
    if altCurrency then
        altCurrency:Hide()
    end
    for costIndex = 1, tonumber(MAX_ITEM_COST) or 3 do
        local name = "MerchantItem" .. buttonIndex .. "AltCurrencyFrameItem" .. costIndex
        local button = _G[name]
        local count = _G[name .. "Count"] or (button and button.Count)
        local icon = _G[name .. "IconTexture"]
            or (button and (button.Icon or button.icon))
        if button then
            button:Hide()
        end
        if count then
            count:SetText("")
            count:Hide()
        end
        if icon then
            icon:SetTexture(nil)
            icon:Hide()
        end
    end
end

local function applyCorrectedOriginalCosts(buttonIndex, entry)
    local moneyFrame = _G["MerchantItem" .. buttonIndex .. "MoneyFrame"]
    local altCurrency = _G["MerchantItem" .. buttonIndex .. "AltCurrencyFrame"]
    local nameFrame = _G["MerchantItem" .. buttonIndex .. "NameFrame"]
    local costs = entry.costs or {}
    hideOriginalSlotCosts(buttonIndex)

    if #costs > 0 and type(MerchantFrame_UpdateAltCurrency) == "function" then
        pcall(
            MerchantFrame_UpdateAltCurrency,
            entry.index,
            buttonIndex,
            entry.isAffordable == true
        )
    end

    for costIndex = 1, tonumber(MAX_ITEM_COST) or 3 do
        local name = "MerchantItem" .. buttonIndex .. "AltCurrencyFrameItem" .. costIndex
        local button = _G[name]
        local count = _G[name .. "Count"] or (button and button.Count)
        local icon = _G[name .. "IconTexture"]
            or (button and (button.Icon or button.icon))
        local cost = costs[costIndex]
        if button and cost then
            button.index = entry.index
            button.item = costIndex
            button.itemLink = cost.link
            button.link = cost.link
            if type(button.SetID) == "function" then
                button:SetID(entry.index)
            end
            if count then
                count:SetText(tostring(math.max(0, tonumber(cost.amount) or 0)))
                count:Show()
            end
            if icon then
                icon:SetTexture(cost.texture)
                icon:Show()
            end
            button:Show()
        elseif button then
            button:Hide()
        end
    end

    if altCurrency then
        if #costs > 0 and type(altCurrency.ClearAllPoints) == "function" then
            altCurrency:ClearAllPoints()
            if (tonumber(entry.price) or 0) > 0 and moneyFrame then
                altCurrency:SetPoint("LEFT", moneyFrame, "RIGHT", -14, 0)
            elseif nameFrame then
                altCurrency:SetPoint("BOTTOMLEFT", nameFrame, "BOTTOMLEFT", 0, 31)
            end
        end
        altCurrency:SetShown(#costs > 0)
    end
    if moneyFrame and type(MoneyFrame_Update) == "function" then
        local frameName = type(moneyFrame.GetName) == "function"
            and moneyFrame:GetName() or ("MerchantItem" .. buttonIndex .. "MoneyFrame")
        pcall(MoneyFrame_Update, frameName, math.max(0, tonumber(entry.price) or 0))
        moneyFrame:SetShown((tonumber(entry.price) or 0) > 0 or #costs == 0)
    end
end

local function clearOriginalMerchantSlot(buttonIndex)
    local slot, itemButton, itemName = getOriginalMerchantSlot(buttonIndex)
    if not slot then
        return
    end
    slot:Hide()
    if type(slot.SetAlpha) == "function" then
        slot:SetAlpha(1)
    end
    if type(slot.EnableMouse) == "function" then
        slot:EnableMouse(false)
    end
    if type(slot.SetID) == "function" then
        slot:SetID(buttonIndex)
    end
    slot.itemIndex = nil
    slot.index = nil
    if itemName then
        itemName:SetText("")
    end
    if itemButton then
        if type(itemButton.SetID) == "function" then
            itemButton:SetID(buttonIndex)
        end
        itemButton.hasItem = nil
        itemButton.link = nil
        itemButton.texture = nil
        itemButton:Hide()
        if itemButton.IconQuestTexture then
            itemButton.IconQuestTexture:Hide()
        end
        if type(SetItemButtonDesaturated) == "function" then
            pcall(SetItemButtonDesaturated, itemButton, false)
        end
    end
    setOriginalSlotVertexColor(slot, itemButton, 1, 1, 1)
    hideOriginalSlotCosts(buttonIndex)
end

local function updateOriginalMerchantSlot(buttonIndex, entry)
    if type(entry) ~= "table" or not entry.index then
        clearOriginalMerchantSlot(buttonIndex)
        return
    end
    local slot, itemButton, itemName = getOriginalMerchantSlot(buttonIndex)
    if not slot or not itemButton then
        return
    end

    slot:Show()
    if type(slot.SetAlpha) == "function" then
        slot:SetAlpha(1)
    end
    if type(slot.EnableMouse) == "function" then
        slot:EnableMouse(true)
    end
    if type(slot.SetID) == "function" then
        slot:SetID(entry.index)
    end
    slot.itemIndex = entry.index
    slot.index = entry.index
    if itemName then
        itemName:SetText(entry.name or "")
    end

    itemButton:SetID(entry.index)
    itemButton.count = entry.stackCount or 1
    itemButton.price = entry.price or 0
    itemButton.extendedCost = entry.hasExtendedCost == true
    itemButton.showNonrefundablePrompt = entry.showNonrefundablePrompt == true
    itemButton.name = entry.name
    itemButton.link = entry.link
    itemButton.texture = entry.icon
    itemButton.hasItem = true
    if type(SetItemButtonTexture) == "function" then
        pcall(SetItemButtonTexture, itemButton, entry.icon)
    elseif itemButton.Icon then
        itemButton.Icon:SetTexture(entry.icon)
    end
    if type(SetItemButtonCount) == "function" then
        pcall(SetItemButtonCount, itemButton, entry.stackCount or 1)
    end
    if type(SetItemButtonStock) == "function" then
        pcall(SetItemButtonStock, itemButton, entry.numAvailable)
    end
    if itemButton.IconQuestTexture then
        itemButton.IconQuestTexture:SetShown(entry.isQuestStartItem == true)
    end
    if type(SetItemButtonDesaturated) == "function" then
        pcall(SetItemButtonDesaturated, itemButton, false)
    end
    itemButton:Show()
    if type(MerchantFrameItem_UpdateQuality) == "function" then
        pcall(MerchantFrameItem_UpdateQuality, slot, entry.link)
    end

    applyCorrectedOriginalCosts(buttonIndex, entry)
    if entry.isSoldOut then
        setOriginalSlotVertexColor(slot, itemButton, 0.5, 0.5, 0.5)
    elseif not entry.isPurchasable or not entry.isUsable then
        setOriginalSlotVertexColor(slot, itemButton, 0.9, 0, 0)
    else
        setOriginalSlotVertexColor(slot, itemButton, 1, 1, 1)
    end
end

function Runtime:RestoreOriginalMerchantItems()
    if not self.originalFilterApplied then
        return
    end
    local perPage = tonumber(MERCHANT_ITEMS_PER_PAGE) or 10
    for buttonIndex = 1, perPage do
        local slot = _G["MerchantItem" .. buttonIndex]
            or _G["MerchantFrameItem" .. buttonIndex]
        if slot then
            slot:Show()
            if type(slot.SetAlpha) == "function" then
                slot:SetAlpha(1)
            end
            if type(slot.EnableMouse) == "function" then
                slot:EnableMouse(true)
            end
        end
    end
    self.originalFilterApplied = false
    if isMerchantOpen() and type(MerchantFrame_Update) == "function" then
        self.restoringOriginal = true
        pcall(MerchantFrame_Update)
        self.restoringOriginal = false
    end
end

function Runtime:ApplyOriginalFrameFilters()
    if not self.enabled
        or self:GetEffectiveDisplayMode() ~= DISPLAY_MODE_FILTER_ONLY
        or not isMerchantOpen()
        or (MerchantFrame and MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1)
    then
        self:RestoreOriginalMerchantItems()
        return
    end
    local searchActive = Logic:NormalizeText(self.search) ~= ""
    if not Logic:HasActiveFilters(self.filters) and not searchActive then
        self:RestoreOriginalMerchantItems()
        return
    end

    local perPage = tonumber(MERCHANT_ITEMS_PER_PAGE) or 10
    local totalPages = math.max(1, math.ceil(#self.filtered / math.max(1, perPage)))
    local page = math.max(1, math.min(totalPages, tonumber(MerchantFrame.page) or 1))
    MerchantFrame.page = page
    local offset = (page - 1) * perPage
    local updateSucceeded = true
    for buttonIndex = 1, perPage do
        local ok, errorMessage = pcall(
            updateOriginalMerchantSlot,
            buttonIndex,
            self.filtered[offset + buttonIndex]
        )
        if not ok then
            if Addon.Logger and type(Addon.Logger.Write) == "function" then
                Addon.Logger:Write(
                    "ERROR",
                    "merchant_filters.native",
                    "Could not update Blizzard merchant slot %d: %s",
                    buttonIndex,
                    tostring(errorMessage)
                )
            end
            updateSucceeded = false
            break
        end
    end
    if not updateSucceeded then
        self.originalFilterApplied = true
        self:RestoreOriginalMerchantItems()
        return
    end

    if MerchantPageText then
        if #self.filtered > perPage then
            MerchantPageText:SetFormattedText(MERCHANT_PAGE_NUMBER or "%d / %d", page, totalPages)
            MerchantPageText:Show()
        else
            MerchantPageText:Hide()
        end
    end
    if MerchantPrevPageButton then
        MerchantPrevPageButton:SetShown(#self.filtered > perPage)
        if page <= 1 then MerchantPrevPageButton:Disable() else MerchantPrevPageButton:Enable() end
    end
    if MerchantNextPageButton then
        MerchantNextPageButton:SetShown(#self.filtered > perPage)
        if page >= totalPages then MerchantNextPageButton:Disable() else MerchantNextPageButton:Enable() end
    end
    self.originalFilterApplied = true
end

function Runtime:EnsureNativeUpdateHook()
    if self.nativeUpdateHooked
        or type(hooksecurefunc) ~= "function"
        or type(MerchantFrame_Update) ~= "function"
    then
        return
    end
    self.nativeUpdateHooked = true
    hooksecurefunc("MerchantFrame_Update", function()
        if Runtime.restoringOriginal then
            return
        end
        if Runtime.enabled
            and Runtime:GetEffectiveDisplayMode() == DISPLAY_MODE_FILTER_ONLY
        then
            Runtime:ScheduleRefresh(0.04, false)
        end
    end)
end

function Runtime:PositionNativeFilterPanel()
    local panel = self.nativeFilterPanel
    if not panel then
        return
    end
    panel:ClearAllPoints()
    if MerchantFrame then
        panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, -80)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 360, 0)
    end
end

function Runtime:BuildNativeFilterPanel()
    if self.nativeFilterPanel then
        return self.nativeFilterPanel
    end
    local panel = Widgets:CreatePanel(UIParent, "sidebar")
    panel:SetSize(250, 476)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(80)
    panel:SetClampedToScreen(true)
    panel.showAdvanced = false

    panel.title = Widgets:CreateLabel(panel, "GameFontNormal", "LEFT")
    panel.title:SetPoint("TOPLEFT", 14, -11)
    panel.title:SetText(Addon.L.MERCHANT_FILTERS)
    panel.title:SetTextColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )
    panel.close = Widgets:CreateButton(panel, "X", 24, 22)
    panel.close:SetPoint("TOPRIGHT", -8, -8)
    panel.close:SetScript("OnClick", function()
        panel:Hide()
    end)
    panel.summary = Widgets:CreateLabel(panel, "GameFontDisableSmall", "LEFT")
    panel.summary:SetPoint("TOPLEFT", 14, -34)
    panel.summary:SetPoint("RIGHT", -14, 0)

    panel.search = CreateFrame(
        "EditBox",
        nil,
        panel,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    panel.search:SetPoint("TOPLEFT", 14, -56)
    panel.search:SetSize(222, 26)
    panel.search:SetAutoFocus(false)
    panel.search:SetFontObject("GameFontHighlightSmall")
    panel.search:SetTextInsets(7, 7, 0, 0)
    Widgets:ApplyPanelStyle(panel.search, "cardInset")
    panel.searchHint = Widgets:CreateLabel(panel.search, "GameFontDisableSmall", "LEFT")
    panel.searchHint:SetPoint("LEFT", 7, 0)
    panel.searchHint:SetPoint("RIGHT", -7, 0)
    panel.searchHint:SetText(Addon.L.MERCHANT_FILTER_SEARCH_HINT)
    panel.search:SetScript("OnTextChanged", function(self)
        Runtime.search = self:GetText() or ""
        panel.searchHint:SetShown(Runtime.search == "")
        Runtime:ApplyFilters()
        Runtime:ApplyOriginalFrameFilters()
        Runtime:RefreshNativeFilterPanel()
    end)
    panel.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    panel.categoryButtons = {}
    panel.filterChecks = {}
    panel.gearChecks = {}
    panel.basicControls = {}
    panel.advancedControls = {}
    local previous
    for _, descriptor in ipairs(CATEGORY_BUTTONS) do
        local button = Widgets:CreateButton(
            panel,
            Addon.L[descriptor.label],
            222,
            23,
            "row"
        )
        if previous then
            button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
        else
            button:SetPoint("TOPLEFT", 14, -94)
        end
        button:SetScript("OnClick", function()
            Runtime:SetCategory(descriptor.key)
        end)
        panel.categoryButtons[descriptor.key] = button
        panel.basicControls[#panel.basicControls + 1] = button
        previous = button
    end

    for index, descriptor in ipairs({
        { key = "hideKnown", label = "MERCHANT_FILTER_HIDE_KNOWN" },
        { key = "hideOtherProfessions", label = "MERCHANT_FILTER_HIDE_OTHER_PROFESSIONS" },
        { key = "affordableOnly", label = "MERCHANT_FILTER_AFFORDABLE_ONLY" },
        { key = "usableOnly", label = "MERCHANT_FILTER_USABLE_ONLY" },
    }) do
        local check = createCheckButton(panel, Addon.L[descriptor.label], 194)
        check:SetPoint("TOPLEFT", 14, -236 - ((index - 1) * 28))
        check:SetScript("OnClick", function(self)
            Runtime:SetFilterValue(descriptor.key, self:GetChecked())
        end)
        panel.filterChecks[descriptor.key] = check
        panel.basicControls[#panel.basicControls + 1] = check
    end

    panel.advanced = Widgets:CreateButton(
        panel,
        Addon.L.MERCHANT_FILTER_ADVANCED,
        222,
        26
    )
    panel.advanced:SetPoint("BOTTOMLEFT", 14, 47)
    panel.advanced:SetScript("OnClick", function()
        panel.showAdvanced = true
        Runtime:RefreshNativeFilterPanel()
    end)
    panel.basicControls[#panel.basicControls + 1] = panel.advanced

    panel.basic = Widgets:CreateButton(
        panel,
        Addon.L.MERCHANT_FILTER_BASIC,
        222,
        26
    )
    panel.basic:SetPoint("TOPLEFT", 14, -94)
    panel.basic:SetScript("OnClick", function()
        panel.showAdvanced = false
        Runtime:RefreshNativeFilterPanel()
    end)
    panel.advancedControls[#panel.advancedControls + 1] = panel.basic

    panel.hideAllGear = createCheckButton(
        panel,
        Addon.L.MERCHANT_FILTER_HIDE_ALL_GEAR,
        194
    )
    panel.hideAllGear:SetPoint("TOPLEFT", 14, -130)
    panel.hideAllGear:SetScript("OnClick", function(self)
        Runtime:SetFilterValue("hideAllGear", self:GetChecked())
    end)
    panel.advancedControls[#panel.advancedControls + 1] = panel.hideAllGear

    for index, slotKey in ipairs(Logic.gearSlotOrder) do
        local column = (index - 1) % 2
        local rowIndex = math.floor((index - 1) / 2)
        local check = createCheckButton(panel, Addon.L[GEAR_LABELS[slotKey]], 84)
        check:SetPoint("TOPLEFT", 14 + (column * 111), -166 - (rowIndex * 32))
        check:SetScript("OnClick", function(self)
            Runtime:SetGearFilter(slotKey, self:GetChecked())
        end)
        panel.gearChecks[slotKey] = check
        panel.advancedControls[#panel.advancedControls + 1] = check
    end

    panel.reset = Widgets:CreateButton(
        panel,
        Addon.L.MERCHANT_FILTER_RESET,
        222,
        26
    )
    panel.reset:SetPoint("BOTTOMLEFT", 14, 14)
    panel.reset:SetScript("OnClick", function()
        Runtime:ResetFilters(false)
    end)
    panel:Hide()
    self.nativeFilterPanel = panel
    self:PositionNativeFilterPanel()
    self:RefreshNativeFilterPanel()
    return panel
end

function Runtime:RefreshNativeFilterPanel()
    local panel = self.nativeFilterPanel
    if not panel then
        return
    end
    self.filters = Logic:NormalizeFilters(self.filters)
    panel.summary:SetText(string.format(
        Addon.L.MERCHANT_FILTER_RESULTS,
        #self.filtered,
        #self.items
    ))
    local advanced = panel.showAdvanced == true
    for _, control in ipairs(panel.basicControls or {}) do
        control:SetShown(not advanced)
    end
    for _, control in ipairs(panel.advancedControls or {}) do
        control:SetShown(advanced)
    end
    for category, button in pairs(panel.categoryButtons or {}) do
        Widgets:SetButtonActive(button, self.filters.category == category)
    end
    for key, check in pairs(panel.filterChecks or {}) do
        check:SetChecked(self.filters[key] == true)
    end
    panel.hideAllGear:SetChecked(self.filters.hideAllGear == true)
    for slotKey, check in pairs(panel.gearChecks or {}) do
        check:SetChecked(self.filters.hiddenGearSlots[slotKey] == true)
    end
    self:RefreshFloatingButton()
end

function Runtime:ToggleNativeFilterPanel()
    local panel = self:BuildNativeFilterPanel()
    if panel:IsShown() then
        panel:Hide()
        return
    end
    self:PositionNativeFilterPanel()
    if panel.search:GetText() ~= self.search then
        panel.search:SetText(self.search or "")
    end
    self:RefreshNativeFilterPanel()
    panel:Show()
end

function Runtime:HideNativeFilterPanel()
    if self.nativeFilterPanel then
        self.nativeFilterPanel:Hide()
    end
end

function Runtime:RefreshFloatingButton()
    local button = self.floatingButton
    if not button then
        return
    end
    if self:GetEffectiveDisplayMode() == DISPLAY_MODE_FILTER_ONLY then
        setButtonText(
            button,
            (Logic:HasActiveFilters(self.filters) or Logic:NormalizeText(self.search) ~= "")
                and Addon.L.MERCHANT_FILTER_NATIVE_BUTTON_ACTIVE
                or Addon.L.MERCHANT_FILTER_NATIVE_BUTTON
        )
    else
        setButtonText(
            button,
            Logic:HasActiveFilters(self.filters)
                and Addon.L.MERCHANT_FILTER_BUTTON_ACTIVE
                or Addon.L.MERCHANT_FILTER_BUTTON
        )
    end
end

function Runtime:EnsureFloatingButton()
    if self.floatingButton then
        return self.floatingButton
    end
    local button = Widgets:CreateButton(
        UIParent,
        Addon.L.MERCHANT_FILTER_BUTTON,
        108,
        30
    )
    button:SetFrameStrata("DIALOG")
    button:SetClampedToScreen(true)
    button:SetScript("OnClick", function()
        if Runtime:GetEffectiveDisplayMode() == DISPLAY_MODE_FILTER_ONLY then
            Runtime:ToggleNativeFilterPanel()
            return
        end
        local frame = Runtime:BuildWindow()
        if frame:IsShown() then
            frame:Hide()
        else
            Runtime:ScanMerchant(false)
            Runtime:ScanBuyback()
            frame:Show()
            Runtime:RefreshWindow(true)
        end
    end)
    button:Hide()
    self.floatingButton = button
    return button
end

function Runtime:ShowFloatingButton()
    local button = self:EnsureFloatingButton()
    button:ClearAllPoints()
    if MerchantFrame then
        button:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 7, -28)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 390, 160)
    end
    self:RefreshFloatingButton()
    button:Show()
end

function Runtime:HideFloatingButton()
    if self.floatingButton then
        self.floatingButton:Hide()
    end
    self:HideNativeFilterPanel()
end

function Runtime:RefreshPortrait()
    local frame = self.frame
    if not frame then
        return
    end
    local function isUsablePortrait(texture)
        return texture ~= nil
            and texture ~= 0
            and not tostring(texture):find("TempPortraitAlphaMask", 1, true)
    end

    local portraitSet = false
    if type(SetPortraitTexture) == "function" then
        for _, unit in ipairs({ "npc", "target" }) do
            local exists = type(UnitExists) ~= "function" or UnitExists(unit)
            if exists then
                frame.portrait:SetTexture(nil)
                pcall(SetPortraitTexture, frame.portrait, unit)
                local texture = type(frame.portrait.GetTexture) == "function"
                    and frame.portrait:GetTexture() or nil
                if isUsablePortrait(texture) then
                    portraitSet = true
                    frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    break
                end
            end
        end
    end

    if not portraitSet then
        local candidates = {}
        local function addCandidate(candidate)
            if candidate then
                candidates[#candidates + 1] = candidate
            end
        end
        addCandidate(
            MerchantFrame
                and MerchantFrame.PortraitContainer
                and (MerchantFrame.PortraitContainer.portrait
                    or MerchantFrame.PortraitContainer.Portrait)
        )
        addCandidate(MerchantFrame and MerchantFrame.portrait)
        addCandidate(_G.MerchantFramePortrait)
        addCandidate(_G.MerchantFramePortraitFramePortrait)
        addCandidate(_G.MerchantFramePortraitTexture)
        for _, nativePortrait in ipairs(candidates) do
            local texture = nativePortrait
                and type(nativePortrait.GetTexture) == "function"
                and nativePortrait:GetTexture() or nil
            if isUsablePortrait(texture) then
                frame.portrait:SetTexture(texture)
                frame.portrait:SetTexCoord(0, 1, 0, 1)
                portraitSet = true
                break
            end
        end
    end

    if not portraitSet then
        frame.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    frame.portrait:SetAlpha(1)
    frame.portrait:Show()
end

function Runtime:SchedulePortraitRefresh()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    local generation = self.generation
    for _, delay in ipairs({ 0, 0.12 }) do
        C_Timer.After(delay, function()
            if Runtime.enabled
                and Runtime.generation == generation
                and Runtime:GetEffectiveDisplayMode() == DISPLAY_MODE_REPLACE
                and Runtime.frame
                and Runtime.frame:IsShown()
            then
                Runtime:RefreshPortrait()
            end
        end)
    end
end

function Runtime:HandleMerchantShow()
    if not self.enabled then
        return
    end
    self.generation = self.generation + 1
    clearTable(self.classificationCache)
    self.search = ""
    self.activeTab = "buy"
    self:LoadFilters()
    self:ScanMerchant(true)
    self:ScanBuyback()
    self:EnsureNativeUpdateHook()

    local mode = self:GetEffectiveDisplayMode()
    if mode == DISPLAY_MODE_REPLACE then
        self:RestoreOriginalMerchantItems()
        self:HideFloatingButton()
        self:ConcealNative()
        local frame = self:BuildWindow()
        frame.search:SetText("")
        frame.title:SetText(getMerchantTitle())
        frame:Show()
        self:RefreshPortrait()
        self:SchedulePortraitRefresh()
        self:RefreshWindow(true)
    else
        self:RestoreNative()
        if self.frame then
            self.frame:Hide()
        end
        self:ShowFloatingButton()
        if mode == DISPLAY_MODE_FILTER_ONLY then
            self:ApplyOriginalFrameFilters()
            self:RefreshNativeFilterPanel()
        else
            self:RestoreOriginalMerchantItems()
        end
    end
end

function Runtime:HandleMerchantClosed()
    self.generation = self.generation + 1
    self.refreshGeneration = self.refreshGeneration + 1
    self.fullRefreshPending = false
    resetMerchantCursor()
    if self.frame then
        self.frame:Hide()
    end
    self:HideFloatingButton()
    self:RestoreOriginalMerchantItems()
    self:RestoreNative()
    clearTable(self.items)
    clearTable(self.filtered)
    clearTable(self.buyback)
    clearTable(self.classificationCache)
end

function Runtime:RefreshNow(fullClassification)
    if not self.enabled or not isMerchantOpen() then
        return
    end
    self:ScanMerchant(fullClassification)
    self:ScanBuyback()
    self:RefreshWindow(false)
    self:ApplyOriginalFrameFilters()
    self:RefreshNativeFilterPanel()
end

function Runtime:ScheduleRefresh(delay, fullClassification)
    if not self.enabled then
        return
    end
    self.fullRefreshPending = self.fullRefreshPending or fullClassification == true
    self.refreshGeneration = self.refreshGeneration + 1
    local token = self.refreshGeneration
    local generation = self.generation
    local function refresh()
        if not Runtime.enabled
            or Runtime.refreshGeneration ~= token
            or Runtime.generation ~= generation
        then
            return
        end
        local needsFull = Runtime.fullRefreshPending
        Runtime.fullRefreshPending = false
        Runtime:RefreshNow(needsFull)
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(
            tonumber(delay) or 0,
            Addon.PerformanceDiagnostics:Wrap(
                Runtime,
                "timer",
                "merchant_filters.refresh",
                refresh
            )
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Runtime,
            "timer",
            "merchant_filters.refresh",
            refresh
        )
        wrapped()
    end
end

function Runtime:ApplyDisplayMode()
    if not self.enabled or not isMerchantOpen() then
        return
    end
    resetMerchantCursor()
    if self.frame then
        self.frame:Hide()
    end
    self:HideFloatingButton()
    self:RestoreOriginalMerchantItems()
    self:RestoreNative()
    local mode = self:GetEffectiveDisplayMode()
    if mode == DISPLAY_MODE_REPLACE then
        self:ConcealNative()
        local frame = self:BuildWindow()
        frame.title:SetText(getMerchantTitle())
        frame:Show()
        self:RefreshPortrait()
        self:SchedulePortraitRefresh()
        self:RefreshWindow(true)
    else
        self:ShowFloatingButton()
        if mode == DISPLAY_MODE_FILTER_ONLY then
            self:EnsureNativeUpdateHook()
            self:ApplyOriginalFrameFilters()
            self:RefreshNativeFilterPanel()
        end
    end
end

function Runtime:ResetLayout()
    local store = getStore()
    store.window.point = "CENTER"
    store.window.relativePoint = "CENTER"
    store.window.x = 0
    store.window.y = 0
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings.scale_percent = 100
    if self.frame then
        applyPosition(self.frame)
        self.frame:SetScale(1)
    end
    showMessage(Addon.L.MERCHANT_FILTER_LAYOUT_RESET_DONE)
end

function Runtime:GetSettingValue(settingKey)
    if SETTING_DEFAULTS[settingKey] == nil then
        return nil
    end
    return Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
end

function Runtime:SetSettingValue(settingKey, value)
    if SETTING_DEFAULTS[settingKey] == nil then
        return false
    end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value
    if settingKey == "display_mode" then
        self:ApplyDisplayMode()
    elseif settingKey == "save_scope" then
        self:PersistFilters()
    elseif settingKey == "scale_percent" and self.frame then
        self.frame:SetScale(clamp(value, SCALE_MIN, SCALE_MAX) / 100)
    end
    return true
end

function Runtime:ResetSettingValues()
    if self.frame then
        self.frame:SetScale(1)
    end
end

function Runtime:OnSettingsReset()
    self:ApplyDisplayMode()
    if self.frame then
        self.frame:SetScale(1)
    end
end

function Runtime:OnAction(actionKey)
    if actionKey == "reset_filters" then
        self:ResetFilters(true)
        return true
    elseif actionKey == "reset_layout" then
        self:ResetLayout()
        return true
    end
    return false
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "MERCHANT_SHOW" then
        self:HandleMerchantShow()
        return
    elseif eventName == "MERCHANT_CLOSED" then
        self:HandleMerchantClosed()
        return
    elseif eventName == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if Enum
            and Enum.PlayerInteractionType
            and interactionType == Enum.PlayerInteractionType.Merchant
        then
            self:ScheduleRefresh(0, true)
            local generation = self.generation
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    if Runtime.enabled and Runtime.generation == generation then
                        Runtime:HandleMerchantShow()
                    end
                end)
            else
                self:HandleMerchantShow()
            end
        end
        return
    elseif eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if Enum
            and Enum.PlayerInteractionType
            and interactionType == Enum.PlayerInteractionType.Merchant
        then
            self:HandleMerchantClosed()
        end
        return
    elseif eventName == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_UIPanels_Game" then
            self:EnsureNativeUpdateHook()
        end
        for _, compatAddon in ipairs(COMPAT_ADDONS) do
            if addonName == compatAddon then
                self:ApplyDisplayMode()
                return
            end
        end
    elseif eventName == "MERCHANT_UPDATE" then
        self:ScheduleRefresh(0.06, true)
        return
    elseif eventName == "GET_ITEM_INFO_RECEIVED" or eventName == "ITEM_DATA_LOAD_RESULT" then
        self:ScheduleRefresh(0.04, true)
        return
    elseif eventName == "PLAYER_MONEY" or eventName == "BAG_UPDATE_DELAYED" then
        self:ScheduleRefresh(0.08, false)
        return
    end
end

function Runtime:OnEnable()
    self.enabled = true
    self.generation = self.generation + 1
    self.compatWarned = false
    self.filters = Logic:DefaultFilters()
    self:EnsureNativeUpdateHook()
    for _, eventName in ipairs({
        "ADDON_LOADED",
        "MERCHANT_SHOW",
        "MERCHANT_UPDATE",
        "MERCHANT_CLOSED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
        "PLAYER_MONEY",
        "BAG_UPDATE_DELAYED",
        "GET_ITEM_INFO_RECEIVED",
        "ITEM_DATA_LOAD_RESULT",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    if isMerchantOpen() then
        self:HandleMerchantShow()
    end
end

function Runtime:OnDisable()
    self.enabled = false
    self.generation = self.generation + 1
    self.refreshGeneration = self.refreshGeneration + 1
    self.fullRefreshPending = false
    resetMerchantCursor()
    if self.frame then
        self.frame:Hide()
    end
    self:HideFloatingButton()
    self:RestoreOriginalMerchantItems()
    self:RestoreNative()
    clearTable(self.items)
    clearTable(self.filtered)
    clearTable(self.buyback)
    clearTable(self.classificationCache)
    clearTable(self.currencyCache)
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Merchant Filters runtime.")
end
