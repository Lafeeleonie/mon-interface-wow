local _, Addon = ...

local Module = {
    id = "arsenal.snapshots",
    defaultEnabled = true,
}

local Service = {
    revision = 0,
    pending = {},
    bankOpen = false,
    enabled = false,
    generation = 0,
}
Addon.Arsenal = Service

local ENCHANTABLE_SLOT_IDS = {
    [1] = true,
    [3] = true,
    [5] = true,
    [7] = true,
    [8] = true,
    [11] = true,
    [12] = true,
    [16] = true,
    [17] = true,
}

local TRACK_HINTS = {
    "explorer", "adventurer", "veteran", "champion", "hero", "myth", "mythic",
    "entdecker", "abenteurer", "veteran", "champion", "held", "mythisch",
    "explorateur", "aventurier", "héros", "mythique",
    "explorador", "aventurero", "veterano", "campeón", "héroe", "mítico",
}

local emptySocketLines

local function now()
    return type(time) == "function" and time() or 0
end

local function currentIdentity()
    return Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
end

local function ensureCharacterSnapshot()
    local identity = currentIdentity()
    if type(identity) ~= "table" or type(identity.key) ~= "string" or identity.key == "" then
        return nil, nil
    end
    local db = Addon.Database:Get()
    local record = type(db.characters[identity.key]) == "table" and db.characters[identity.key] or {}
    record.identity = type(record.identity) == "table" and record.identity or identity
    record.arsenal = type(record.arsenal) == "table" and record.arsenal or {}
    record.arsenal.version = 1
    db.characters[identity.key] = record
    return record.arsenal, identity
end

local function cleanText(text)
    text = tostring(text or "")
    text = text:gsub("|A:[^|]+|a", "")
    text = text:gsub("|T[^|]+|t", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("%s+", " ")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getTooltipLines(slotID, itemLink)
    local lines = {}
    if C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem) == "function" then
        local ok, tooltipData = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
        if ok and type(tooltipData) == "table" and type(tooltipData.lines) == "table" then
            for _, line in ipairs(tooltipData.lines) do
                if type(line and line.leftText) == "string" and line.leftText ~= "" then
                    lines[#lines + 1] = line.leftText
                end
            end
        end
    end

    if #lines > 0 or type(itemLink) ~= "string" or type(CreateFrame) ~= "function" then
        return lines
    end

    local tooltip = _G.VaultloomArsenalScanTooltip
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "VaultloomArsenalScanTooltip", UIParent, "GameTooltipTemplate")
        if tooltip and type(tooltip.SetOwner) == "function" then
            tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
    end
    if not tooltip or type(tooltip.SetHyperlink) ~= "function" then
        return lines
    end

    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)
    local lineCount = type(tooltip.NumLines) == "function" and tooltip:NumLines() or 0
    for index = 1, lineCount do
        local line = _G["VaultloomArsenalScanTooltipTextLeft" .. index]
        local text = line and type(line.GetText) == "function" and line:GetText() or nil
        if type(text) == "string" and text ~= "" then
            lines[#lines + 1] = text
        end
    end
    tooltip:ClearLines()
    return lines
end

local function getEmptySocketLines()
    if emptySocketLines then
        return emptySocketLines
    end
    emptySocketLines = {}
    for globalName, value in pairs(_G) do
        if type(globalName) == "string"
            and type(value) == "string"
            and globalName:find("EMPTY_SOCKET_", 1, true)
        then
            emptySocketLines[#emptySocketLines + 1] = cleanText(value)
        end
    end
    return emptySocketLines
end

local function getItemInstant(itemLink)
    if not (C_Item and type(C_Item.GetItemInfoInstant) == "function") then
        return nil
    end
    local ok, itemID, _, _, equipLoc, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemLink)
    if not ok then
        return nil
    end
    return {
        itemID = tonumber(itemID),
        equipLoc = equipLoc,
        icon = icon,
        classID = tonumber(classID),
        subClassID = tonumber(subClassID),
    }
end

local function getGemLink(itemLink, gemIndex)
    if C_Item and type(C_Item.GetItemGem) == "function" then
        local ok, _, link = pcall(C_Item.GetItemGem, itemLink, gemIndex)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    if type(GetItemGem) == "function" then
        local ok, _, link = pcall(GetItemGem, itemLink, gemIndex)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    return nil
end

local function getSocketData(itemLink, tooltipLines)
    local sockets, filled, empty = {}, 0, 0
    for index = 1, 4 do
        local gemLink = getGemLink(itemLink, index)
        if gemLink then
            local instant = getItemInstant(gemLink)
            sockets[#sockets + 1] = {
                itemLink = gemLink,
                icon = instant and instant.icon or "Interface\\Icons\\INV_Misc_Gem_01",
                empty = false,
            }
            filled = filled + 1
        end
    end

    local socketNames = getEmptySocketLines()
    for _, rawLine in ipairs(tooltipLines or {}) do
        local line = cleanText(rawLine)
        for _, socketName in ipairs(socketNames) do
            if socketName ~= "" and line:find(socketName, 1, true) then
                sockets[#sockets + 1] = {
                    icon = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
                    empty = true,
                }
                empty = empty + 1
                break
            end
        end
    end
    return sockets, filled, empty
end

local function getUpgradeTrack(tooltipLines)
    for _, rawLine in ipairs(tooltipLines or {}) do
        local line = cleanText(rawLine)
        local lower = string.lower(line)
        if line:match("%d+%s*/%s*%d+") then
            for _, hint in ipairs(TRACK_HINTS) do
                if lower:find(hint, 1, true) then
                    return line:gsub("^%s*[^:]+:%s*", "")
                end
            end
        end
    end
    return nil
end

local function isOffhandWeapon(itemLink)
    local instant = getItemInstant(itemLink)
    if not instant then return false end
    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    if instant.classID == weaponClass then return true end
    return instant.equipLoc == "INVTYPE_WEAPON" or instant.equipLoc == "INVTYPE_WEAPONOFFHAND"
end

local function canEnchant(slotID, itemLink)
    slotID = tonumber(slotID)
    if not slotID or ENCHANTABLE_SLOT_IDS[slotID] ~= true then
        return false
    end
    return slotID ~= 17 or isOffhandWeapon(itemLink)
end

local function getDetailedItemLevel(itemLink)
    if C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local ok, itemLevel = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(itemLevel) then return math.floor(tonumber(itemLevel) + 0.5) end
    end
    if type(GetDetailedItemLevelInfo) == "function" then
        local ok, itemLevel = pcall(GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(itemLevel) then return math.floor(tonumber(itemLevel) + 0.5) end
    end
    return nil
end

local function scanEquipmentSlot(definition)
    local slotID, emptyTexture = Addon.ArsenalLogic:GetSlotID(definition)
    if not slotID then return nil, nil end
    local itemLink = type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", slotID) or nil
    if type(itemLink) ~= "string" or itemLink == "" then
        return slotID, {
            slotID = slotID,
            slotName = definition.name,
            emptyTexture = emptyTexture,
            empty = true,
        }
    end

    local itemID = Addon.ArsenalLogic:ParseItemID(itemLink)
    local instant = getItemInstant(itemLink)
    local icon = type(GetInventoryItemTexture) == "function" and GetInventoryItemTexture("player", slotID) or nil
    icon = icon or (instant and instant.icon)
    local quality = type(GetInventoryItemQuality) == "function"
        and tonumber(GetInventoryItemQuality("player", slotID)) or nil
    local tooltipLines = getTooltipLines(slotID, itemLink)
    local sockets, filledSockets, emptySockets = getSocketData(itemLink, tooltipLines)
    local enchantable = canEnchant(slotID, itemLink)
    local enchantID = tonumber(itemLink:match("item:%-?%d+:(%-?%d+)")) or 0
    local durabilityCurrent, durabilityMaximum
    if type(GetInventoryItemDurability) == "function" then
        durabilityCurrent, durabilityMaximum = GetInventoryItemDurability(slotID)
    end

    return slotID, {
        slotID = slotID,
        slotName = definition.name,
        itemID = itemID,
        itemLink = itemLink,
        itemName = Addon.ArsenalLogic:GetItemName(itemLink, itemID),
        icon = icon,
        quality = quality,
        itemLevel = getDetailedItemLevel(itemLink),
        enchantable = enchantable,
        enchanted = enchantable and enchantID > 0 or false,
        enchantID = enchantID > 0 and enchantID or nil,
        sockets = sockets,
        filledSockets = filledSockets,
        emptySockets = emptySockets,
        upgradeTrack = getUpgradeTrack(tooltipLines),
        durabilityCurrent = tonumber(durabilityCurrent),
        durabilityMaximum = tonumber(durabilityMaximum),
        empty = false,
    }
end

local function addBagID(list, seen, bagID, kind, index)
    bagID = tonumber(bagID)
    if bagID == nil or seen[bagID] then return end
    seen[bagID] = true
    list[#list + 1] = {
        bagID = bagID,
        kind = kind,
        index = index or #list + 1,
    }
end

local function bagIndex()
    return Enum and Enum.BagIndex or {}
end

local function characterBagDefinitions()
    local indices = bagIndex()
    local list, seen = {}, {}
    addBagID(list, seen, indices.Backpack or BACKPACK_CONTAINER or 0, "backpack", 1)
    addBagID(list, seen, indices.Bag_1 or 1, "bag", 1)
    addBagID(list, seen, indices.Bag_2 or 2, "bag", 2)
    addBagID(list, seen, indices.Bag_3 or 3, "bag", 3)
    addBagID(list, seen, indices.Bag_4 or 4, "bag", 4)
    if indices.ReagentBag ~= nil then
        addBagID(list, seen, indices.ReagentBag, "bag", 5)
    end
    return list
end

local function getPurchasedBankTabs(bankType)
    if not (C_Bank and type(C_Bank.FetchPurchasedBankTabData) == "function" and bankType ~= nil) then
        return nil
    end
    local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
    return ok and type(tabs) == "table" and tabs or nil
end

local function characterBankDefinitions()
    local indices = bagIndex()
    local list, seen = {}, {}

    local characterTabs = Enum and Enum.BankType and getPurchasedBankTabs(Enum.BankType.Character) or nil
    if indices.CharacterBankTab_1 ~= nil then
        local tabCount = characterTabs and #characterTabs or 6
        for index = 1, tabCount do
            local bagID = indices["CharacterBankTab_" .. index]
            if bagID ~= nil then
                addBagID(list, seen, bagID, "bankTab", index)
                local entry = list[#list]
                local tab = characterTabs and characterTabs[index]
                entry.name = type(tab) == "table" and (tab.name or tab.tabName) or nil
                entry.icon = type(tab) == "table" and (tab.icon or tab.iconID) or nil
            end
        end
    else
        -- The legacy bank API exposes one base container plus purchased bag slots.
        -- Modern character-bank tabs replace that base container; including both
        -- creates a phantom "Bank 0/0" selector with no corresponding tab.
        addBagID(list, seen, indices.Bank or BANK_CONTAINER or -1, "bank", 1)
        for index = 1, 7 do
            addBagID(list, seen, indices["BankBag_" .. index], "bankTab", index)
        end
    end

    local reagentID = indices.Reagentbank or indices.ReagentBank or REAGENTBANK_CONTAINER
    addBagID(list, seen, reagentID, "reagents", 1)
    return list
end

local function warbandBankDefinitions()
    local indices = bagIndex()
    local bankType = Enum and Enum.BankType and Enum.BankType.Account or nil
    local tabs = getPurchasedBankTabs(bankType)
    if not tabs then return {} end

    local list, seen = {}, {}
    for index, tab in ipairs(tabs) do
        local bagID = indices["AccountBankTab_" .. index]
        if bagID ~= nil then
            addBagID(list, seen, bagID, "warband", index)
            local entry = list[#list]
            entry.name = type(tab) == "table" and (tab.name or tab.tabName) or nil
            entry.icon = type(tab) == "table" and (tab.icon or tab.iconID) or nil
        end
    end
    return list
end

local function getContainerSlots(bagID)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, count = pcall(C_Container.GetContainerNumSlots, bagID)
        if ok then return math.max(0, tonumber(count) or 0) end
    end
    if type(GetContainerNumSlots) == "function" then
        local ok, count = pcall(GetContainerNumSlots, bagID)
        if ok then return math.max(0, tonumber(count) or 0) end
    end
    return 0
end

local function getContainerItem(bagID, slotID)
    local info, link
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, value = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(value) == "table" then info = value end
    end
    if info then
        link = info.hyperlink or info.itemLink
    elseif C_Container and type(C_Container.GetContainerItemLink) == "function" then
        local ok, value = pcall(C_Container.GetContainerItemLink, bagID, slotID)
        if ok then link = value end
    elseif type(GetContainerItemLink) == "function" then
        local ok, value = pcall(GetContainerItemLink, bagID, slotID)
        if ok then link = value end
    end

    local itemID = tonumber(info and info.itemID) or Addon.ArsenalLogic:ParseItemID(link)
    if not itemID then return nil end
    local instant = getItemInstant(link or itemID)
    return {
        itemID = itemID,
        itemLink = link,
        itemName = Addon.ArsenalLogic:GetItemName(link, itemID),
        icon = info and (info.iconFileID or info.icon) or (instant and instant.icon),
        quality = tonumber(info and info.quality),
        count = math.max(1, math.floor(tonumber(info and (info.stackCount or info.quantity or info.count)) or 1)),
    }
end

local function scanContainers(definitions)
    local containers, scannedAny = {}, false
    for _, definition in ipairs(definitions or {}) do
        local totalSlots = getContainerSlots(definition.bagID)
        if totalSlots > 0 then scannedAny = true end
        local container = {
            bagID = definition.bagID,
            kind = definition.kind,
            index = definition.index,
            name = definition.name,
            icon = definition.icon,
            totalSlots = totalSlots,
            items = {},
        }
        for slotID = 1, totalSlots do
            local item = getContainerItem(definition.bagID, slotID)
            if item then container.items[slotID] = item end
        end
        containers[#containers + 1] = container
    end
    return containers, scannedAny
end

function Service:Publish()
    self.revision = self.revision + 1
    Addon.StateStore:Set("arsenal.snapshots", {
        revision = self.revision,
        updatedAt = now(),
    })
end

function Service:ScanEquipment()
    local snapshot = ensureCharacterSnapshot()
    if not snapshot then return false end
    local equipment = {}
    for _, column in pairs(Addon.ArsenalLogic:GetSlotColumns()) do
        for _, definition in ipairs(column) do
            local slotID, entry = scanEquipmentSlot(definition)
            if slotID and entry then equipment[slotID] = entry end
        end
    end
    snapshot.equipment = equipment
    snapshot.equipmentSummary = Addon.ArsenalLogic:BuildEquipmentSummary(equipment)
    snapshot.equipmentUpdatedAt = now()
    self:Publish()
    return true
end

function Service:ScanBags()
    local snapshot = ensureCharacterSnapshot()
    if not snapshot then return false end
    local containers, scanned = scanContainers(characterBagDefinitions())
    if not scanned then return false end
    snapshot.bags = {
        containers = containers,
        updatedAt = now(),
    }
    self:Publish()
    return true
end

function Service:ScanBank()
    if self.bankOpen ~= true then return false end
    local snapshot = ensureCharacterSnapshot()
    if not snapshot then return false end
    local containers, scanned = scanContainers(characterBankDefinitions())
    if not scanned then return false end
    snapshot.bank = {
        containers = containers,
        updatedAt = now(),
    }
    self:Publish()
    return true
end

function Service:ScanWarbandBank()
    if self.bankOpen ~= true then return false end
    local definitions = warbandBankDefinitions()
    if #definitions == 0 then return false end
    local containers, scanned = scanContainers(definitions)
    if not scanned then return false end
    local db = Addon.Database:Get()
    db.arsenal.warband = {
        containers = containers,
        updatedAt = now(),
    }
    self:Publish()
    return true
end

function Service:Queue(kind, delay)
    if self.enabled ~= true then return false end
    local generation = self.generation
    if self.pending[kind] == generation then return true end
    self.pending[kind] = generation
    local function run()
        if Service.pending[kind] == generation then Service.pending[kind] = nil end
        if Service.enabled ~= true or Service.generation ~= generation then return end
        if kind == "equipment" then
            Service:ScanEquipment()
        elseif kind == "bags" then
            Service:ScanBags()
        elseif kind == "bank" then
            Service:ScanBank()
            Service:ScanWarbandBank()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(
            math.max(0, tonumber(delay) or 0),
            Addon.PerformanceDiagnostics:Wrap(
                Module,
                "timer",
                "arsenal." .. tostring(kind),
                run
            )
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Module,
            "timer",
            "arsenal." .. tostring(kind),
            run
        )
        wrapped()
    end
    return true
end

function Service:RefreshCurrent()
    self:Queue("equipment", 0.05)
    self:Queue("bags", 0.08)
    if self.bankOpen then self:Queue("bank", 0.12) end
end

local function removeLegacyBaseBankFromSnapshot(snapshot)
    local indices = bagIndex()
    local containers = type(snapshot and snapshot.bank) == "table"
        and snapshot.bank.containers
        or nil
    if indices.CharacterBankTab_1 == nil or type(containers) ~= "table" then return end
    for index = #containers, 1, -1 do
        if type(containers[index]) == "table" and containers[index].kind == "bank" then
            table.remove(containers, index)
        end
    end
end

function Service:GetCharacterSnapshot(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    local snapshot = type(record) == "table" and type(record.arsenal) == "table" and record.arsenal or nil
    removeLegacyBaseBankFromSnapshot(snapshot)
    return snapshot
end

function Service:GetWarbandSnapshot()
    return Addon.Database:Get().arsenal.warband
end

function Service:GetView(mode, characterKey)
    local character = characterKey and Addon.Database:Get().characters[characterKey] or nil
    local identity = type(character) == "table" and character.identity or nil
    local characterSnapshot = self:GetCharacterSnapshot(characterKey)
    local snapshot
    if mode == "equipment" then
        snapshot = characterSnapshot and {
            equipment = characterSnapshot.equipment,
            summary = characterSnapshot.equipmentSummary,
            updatedAt = characterSnapshot.equipmentUpdatedAt,
        } or nil
    elseif mode == "bags" then
        snapshot = characterSnapshot and characterSnapshot.bags or nil
    elseif mode == "bank" then
        snapshot = characterSnapshot and characterSnapshot.bank or nil
    elseif mode == "warband" then
        snapshot = self:GetWarbandSnapshot()
    end
    return {
        mode = mode,
        character = identity,
        snapshot = snapshot,
        current = characterKey ~= nil and Addon.WarbandRoster:IsCurrent(characterKey),
        accountWide = mode == "warband",
    }
end

function Module:OnEnable()
    Service.enabled = true
    Service.generation = Service.generation + 1
    Addon.StateStore:Set("arsenal.snapshots", {
        revision = 0,
        updatedAt = 0,
    })

    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        Service:Queue("equipment", 0.60)
        Service:Queue("bags", 0.75)
    end)
    Addon.EventBus:Subscribe("PLAYER_EQUIPMENT_CHANGED", self, function()
        Service:Queue("equipment", 0.10)
    end)
    Addon.EventBus:Subscribe("BAG_UPDATE_DELAYED", self, function()
        Service:Queue("bags", 0.08)
        if Service.bankOpen then Service:Queue("bank", 0.18) end
    end)
    Addon.EventBus:Subscribe("BANKFRAME_OPENED", self, function()
        Service.bankOpen = true
        Service:Queue("bank", 0.30)
    end)
    Addon.EventBus:Subscribe("BANKFRAME_CLOSED", self, function()
        Service.bankOpen = false
    end)
    for _, eventName in ipairs({
        "PLAYERBANKSLOTS_CHANGED",
        "REAGENTBANK_PURCHASED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function()
            if Service.bankOpen then Service:Queue("bank", 0.15) end
        end)
    end

    Service:RefreshCurrent()
end

function Module:OnDisable()
    Service.enabled = false
    Service.generation = Service.generation + 1
    Service.pending = {}
    Service.bankOpen = false
end

Addon.ModuleRegistry:Register(Module)
