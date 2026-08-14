local _, Addon = ...

local FEATURE_ID = "shopping_list"
local MINI_SCALE_MIN = 0.65
local MINI_SCALE_MAX = 1.75
local MINI_SCALE_STEP = 0.05
local MINIMAP_DEFAULT_ANGLE = 315
local MINIMAP_RADIUS_OFFSET = 7
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local MINIMAP_SHAPES = {
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

local Runtime = {
    enabled = false,
    revision = 0,
    window = nil,
    miniButton = nil,
    minimapButton = nil,
    professionButton = nil,
    auctionButton = nil,
    projectRows = {},
    purchaseRows = {},
}

Addon.ShoppingList = Runtime

local function parseItemID(value)
    if type(value) == "number" and value > 0 then
        return math.floor(value)
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, value)
        itemID = ok and tonumber(itemID) or nil
        if itemID and itemID > 0 then
            return math.floor(itemID)
        end
    end
    local itemID = tonumber(value:match("item:(%d+)"))
    return itemID and itemID > 0 and math.floor(itemID) or nil
end

local function getItemDetails(value, fallback)
    local itemID = parseItemID(value)
    if not itemID then
        return nil
    end

    local details = {
        itemID = itemID,
        itemLink = type(value) == "string" and value:find("|Hitem:", 1, true) and value
            or type(fallback) == "table" and fallback.itemLink or nil,
        name = type(fallback) == "table" and fallback.name or nil,
        icon = type(fallback) == "table" and fallback.icon or nil,
        quality = tonumber(type(fallback) == "table" and fallback.quality) or 1,
    }

    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, name, itemLink, quality, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
        if ok then
            details.name = type(name) == "string" and name ~= "" and name or details.name
            details.itemLink = type(itemLink) == "string" and itemLink ~= "" and itemLink or details.itemLink
            details.quality = tonumber(quality) or details.quality
            details.icon = icon or details.icon
        end
    end
    if not details.icon and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok then details.icon = icon end
    end
    if not details.name and C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(name) == "string" and name ~= "" then details.name = name end
    end
    if not details.name then
        details.name = string.format(Addon.L.SHOPPING_ITEM_FALLBACK, itemID)
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end
    details.icon = details.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    return details
end

local function getStore()
    local db = Addon.Database:Get()
    db.features.shoppingList = type(db.features.shoppingList) == "table"
        and db.features.shoppingList or {}
    local store = db.features.shoppingList
    store.entries = type(store.entries) == "table" and store.entries or {}
    store.order = type(store.order) == "table" and store.order or {}
    store.nextID = math.max(1, math.floor(tonumber(store.nextID) or 1))
    store.window = type(store.window) == "table" and store.window or {}
    store.miniButton = type(store.miniButton) == "table" and store.miniButton or {}
    store.minimapButton = type(store.minimapButton) == "table" and store.minimapButton or {}
    store.minimapButton.angle = tonumber(store.minimapButton.angle) or MINIMAP_DEFAULT_ANGLE
    return store
end

local function orderedEntries()
    local store = getStore()
    local result, order, seen = {}, {}, {}
    for _, entryID in ipairs(store.order) do
        local entry = store.entries[entryID]
        if type(entry) == "table" and not seen[entryID] then
            result[#result + 1] = entry
            order[#order + 1] = entryID
            seen[entryID] = true
        end
    end
    for entryID, entry in pairs(store.entries) do
        if type(entryID) == "string" and type(entry) == "table" and not seen[entryID] then
            result[#result + 1] = entry
            order[#order + 1] = entryID
        end
    end
    store.order = order
    return result
end

local function findEntry(kind, itemID, recipeID)
    for _, entry in ipairs(orderedEntries()) do
        if entry.kind == kind then
            if kind == "recipe" and tonumber(entry.recipeID) == tonumber(recipeID) then
                return entry
            elseif kind == "item" and tonumber(entry.itemID) == tonumber(itemID) then
                return entry
            end
        end
    end
    return nil
end

local function nextEntryID()
    local store = getStore()
    local entryID = "shopping_" .. tostring(store.nextID)
    store.nextID = store.nextID + 1
    return entryID
end

local function now()
    return type(time) == "function" and time() or 0
end

local function savePosition(frame, destination)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    destination.point = type(point) == "string" and point or "CENTER"
    destination.relativePoint = type(relativePoint) == "string" and relativePoint or destination.point
    destination.x = tonumber(x) or 0
    destination.y = tonumber(y) or 0

    if relativeTo and relativeTo ~= UIParent
        and type(frame.GetCenter) == "function"
        and type(UIParent.GetCenter) == "function"
    then
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if centerX and centerY and parentX and parentY then
            destination.point, destination.relativePoint = "CENTER", "CENTER"
            destination.x, destination.y = centerX - parentX, centerY - parentY
        end
    end
end

local function applyPosition(frame, position, defaultX)
    position = type(position) == "table" and position or {}
    frame:ClearAllPoints()
    frame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        tonumber(position.x) or defaultX or 0,
        tonumber(position.y) or 0
    )
end

local function updateMinimapButtonPosition(button)
    if not button or not Minimap then return false end
    local position = getStore().minimapButton
    local angleValue = tonumber(position.angle) or MINIMAP_DEFAULT_ANGLE
    while angleValue < 0 do angleValue = angleValue + 360 end
    angleValue = angleValue % 360
    position.angle = angleValue

    local angle = math.rad(angleValue)
    local width = type(Minimap.GetWidth) == "function" and Minimap:GetWidth() or 140
    local height = type(Minimap.GetHeight) == "function" and Minimap:GetHeight() or 140
    local radiusX = math.max(54, (tonumber(width) or 140) * 0.5 + MINIMAP_RADIUS_OFFSET)
    local radiusY = math.max(54, (tonumber(height) or 140) * 0.5 + MINIMAP_RADIUS_OFFSET)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    local roundQuadrants = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
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

local function updateMinimapButtonDrag(button)
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
    getStore().minimapButton.angle = angle % 360
    updateMinimapButtonPosition(button)
end

local function qualityColor(quality)
    local color = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[tonumber(quality)] or nil
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return 1, 1, 1
end

local function setItemTooltip(frame, itemLink, itemID)
    frame.vaultloomShoppingItemLink = itemLink
    frame.vaultloomShoppingItemID = itemID
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local link = self.vaultloomShoppingItemLink
        local id = self.vaultloomShoppingItemID
        if not link and not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link or ("item:" .. tostring(id)))
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function showMessage(message)
    if message and message ~= "" then
        Addon:Print(message)
    end
end

function Runtime:Publish()
    self.revision = self.revision + 1
    Addon.StateStore:Set("shopping.list", {
        revision = self.revision,
        updatedAt = now(),
    })
end

function Runtime:GetPlan()
    return Addon.ShoppingListLogic:BuildPlan(orderedEntries(), function(itemID)
        return Addon.InventoryIndex:GetStoredCount(itemID, {
            includeEquipped = false,
            includeWarband = true,
        })
    end)
end

function Runtime:AddItem(value, quantity, silent)
    if self.enabled ~= true then
        if not silent then showMessage(Addon.L.SHOPPING_ERROR_DISABLED) end
        return false
    end
    local details = getItemDetails(value)
    if not details then
        if not silent then showMessage(Addon.L.SHOPPING_ERROR_NO_ITEM) end
        return false
    end

    quantity = Addon.ShoppingListLogic:ClampQuantity(quantity)
    local entry = findEntry("item", details.itemID)
    if entry then
        entry.quantity = Addon.ShoppingListLogic:ClampQuantity((tonumber(entry.quantity) or 1) + quantity)
    else
        local store = getStore()
        entry = {
            id = nextEntryID(),
            kind = "item",
            quantity = quantity,
            createdAt = now(),
        }
        store.entries[entry.id] = entry
        store.order[#store.order + 1] = entry.id
    end
    entry.itemID = details.itemID
    entry.itemLink = details.itemLink
    entry.name = details.name
    entry.icon = details.icon
    entry.quality = details.quality
    entry.updatedAt = now()
    self:Publish()
    self:Refresh()
    if not silent then
        showMessage(string.format(Addon.L.SHOPPING_ADDED_ITEM, details.name))
    end
    return true
end

local function callMethod(object, methodName, ...)
    if type(object) ~= "table" or type(object[methodName]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[methodName], object, ...)
    return ok and value or nil
end

local function getProfessionFrame()
    if type(ProfessionsFrame) == "table"
        and (type(ProfessionsFrame.IsShown) ~= "function" or ProfessionsFrame:IsShown())
    then
        return ProfessionsFrame
    end
    if type(TradeSkillFrame) == "table"
        and (type(TradeSkillFrame.IsShown) ~= "function" or TradeSkillFrame:IsShown())
    then
        return TradeSkillFrame
    end
    return nil
end

function Runtime:GetSelectedRecipeID()
    local frame = getProfessionFrame()
    if not frame then return nil end
    local candidates = {}
    local function addCandidate(value)
        local recipeID = tonumber(value)
        if recipeID and recipeID > 0 then
            candidates[#candidates + 1] = math.floor(recipeID)
        end
    end
    addCandidate(frame.selectedRecipeID)
    addCandidate(frame.selectedSkill)
    addCandidate(callMethod(frame, "GetSelectedRecipeID"))
    local page = frame.CraftingPage
    if type(page) == "table" then
        addCandidate(page.selectedRecipeID)
        addCandidate(page.recipeID)
        addCandidate(callMethod(page, "GetSelectedRecipeID"))
        local recipeInfo = callMethod(page, "GetSelectedRecipeInfo")
        if type(recipeInfo) == "table" then
            addCandidate(recipeInfo.recipeID)
        end
        local form = page.SchematicForm
        if type(form) == "table" then
            addCandidate(form.recipeID)
            addCandidate(form.selectedRecipeID)
            local formSchematic = callMethod(form, "GetRecipeSchematic")
            if type(formSchematic) == "table" then
                addCandidate(formSchematic.recipeID)
            end
            if type(form.recipeSchematic) == "table" then
                addCandidate(form.recipeSchematic.recipeID)
            end
            local transaction = callMethod(form, "GetTransaction") or form.transaction
            addCandidate(callMethod(transaction, "GetRecipeID"))
            addCandidate(type(transaction) == "table" and transaction.recipeID or nil)
        end
    end
    return candidates[1]
end

local function selectedReagentsForSlot(slotIndex)
    local frame = getProfessionFrame()
    local page = frame and frame.CraftingPage
    local form = type(page) == "table" and page.SchematicForm or nil
    local transaction = type(form) == "table"
        and (callMethod(form, "GetTransaction") or form.transaction) or nil
    local allocations = callMethod(transaction, "GetAllocations", slotIndex)
    local result, seen = {}, {}
    for _, allocation in ipairs(type(allocations) == "table" and allocations or {}) do
        local reagent = allocation.reagent or allocation.reagentInfo or allocation
        local itemID = parseItemID(
            reagent.itemID
                or reagent.itemId
                or reagent.itemLink
                or (reagent.item and reagent.item.itemID)
        )
        if itemID and not seen[itemID] and (tonumber(allocation.quantity) or 1) > 0 then
            seen[itemID] = true
            result[#result + 1] = itemID
        end
    end
    return result
end

local function isOptionalSlot(slot)
    if slot.required == false or slot.isOptional == true then
        return true
    end
    local reagentType = slot.reagentType or (slot.slotInfo and slot.slotInfo.reagentType)
    local types = Enum and Enum.CraftingReagentType or {}
    return reagentType ~= nil
        and (reagentType == types.Optional or reagentType == types.Finishing)
end

local function buildRecipeReagents(recipeID, schematic)
    local result = {}
    for slotIndex, slot in ipairs(type(schematic and schematic.reagentSlotSchematics) == "table"
        and schematic.reagentSlotSchematics or {})
    do
        local quantity = tonumber(slot.quantityRequired or slot.requiredQuantity or slot.quantity) or 0
        local selected = selectedReagentsForSlot(slotIndex)
        if quantity > 0 and (not isOptionalSlot(slot) or #selected > 0) then
            local itemIDs, seen = {}, {}
            local source = #selected > 0 and selected or slot.reagents or {}
            for _, reagent in ipairs(source) do
                local itemID = parseItemID(
                    type(reagent) == "number" and reagent
                        or type(reagent) == "table" and (
                            reagent.itemID
                            or reagent.itemId
                            or reagent.itemLink
                            or (reagent.itemInfo and reagent.itemInfo.itemID)
                        )
                )
                if itemID and not seen[itemID] then
                    seen[itemID] = true
                    itemIDs[#itemIDs + 1] = itemID
                end
            end
            table.sort(itemIDs)
            if #itemIDs > 0 then
                local selectedItemID = #selected == 1 and selected[1] or nil
                local details = getItemDetails(selectedItemID or itemIDs[1])
                result[#result + 1] = {
                    itemID = itemIDs[1],
                    itemIDs = itemIDs,
                    selectedItemID = selectedItemID,
                    itemLink = details and details.itemLink,
                    name = details and details.name,
                    icon = details and details.icon,
                    quality = details and details.quality,
                    quantity = quantity,
                }
            end
        end
    end

    if #result == 0 and C_TradeSkillUI
        and type(C_TradeSkillUI.GetRecipeNumReagents) == "function"
    then
        local ok, count = pcall(C_TradeSkillUI.GetRecipeNumReagents, recipeID)
        count = ok and tonumber(count) or 0
        for index = 1, count do
            local itemLink
            if type(C_TradeSkillUI.GetRecipeReagentItemLink) == "function" then
                local linkOK, value = pcall(C_TradeSkillUI.GetRecipeReagentItemLink, recipeID, index)
                if linkOK then itemLink = value end
            end
            local name, icon, quantity, itemID
            if type(C_TradeSkillUI.GetRecipeReagentInfo) == "function" then
                local infoOK
                infoOK, name, icon, quantity, _, _, itemID = pcall(
                    C_TradeSkillUI.GetRecipeReagentInfo,
                    recipeID,
                    index
                )
                if not infoOK then name, icon, quantity, itemID = nil, nil, nil, nil end
            end
            itemID = parseItemID(itemID or itemLink)
            if itemID and (tonumber(quantity) or 0) > 0 then
                local details = getItemDetails(itemID)
                result[#result + 1] = {
                    itemID = itemID,
                    itemIDs = { itemID },
                    selectedItemID = itemID,
                    itemLink = itemLink or details.itemLink,
                    name = name or details.name,
                    icon = icon or details.icon,
                    quality = details.quality,
                    quantity = quantity,
                }
            end
        end
    end
    return result
end

local function collectRecipe(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID or recipeID <= 0 or not C_TradeSkillUI then return nil end
    local info
    if type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local ok, value = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(value) == "table" then info = value end
    end
    local schematic
    if type(C_TradeSkillUI.GetRecipeSchematic) == "function" then
        local ok, value = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if ok and type(value) == "table" then schematic = value end
        if not schematic then
            ok, value = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID)
            if ok and type(value) == "table" then schematic = value end
        end
    end
    local itemLink
    if type(C_TradeSkillUI.GetRecipeItemLink) == "function" then
        local ok, value = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
        if ok then itemLink = value end
    end
    local itemID = parseItemID(itemLink) or parseItemID(schematic and schematic.outputItemID)
    local details = itemID and getItemDetails(itemLink or itemID) or nil
    local reagents = buildRecipeReagents(recipeID, schematic)
    if #reagents == 0 then return nil end
    return {
        kind = "recipe",
        recipeID = math.floor(recipeID),
        itemID = itemID,
        itemLink = details and details.itemLink or itemLink,
        name = details and details.name or info and info.name or tostring(recipeID),
        icon = details and details.icon or info and info.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        quality = details and details.quality or 1,
        outputQuantity = math.max(1, math.floor(tonumber(
            schematic and (schematic.quantityMin or schematic.outputQuantity)
        ) or 1)),
        reagents = reagents,
    }
end

function Runtime:AddRecipe(recipeID, quantity, silent)
    if self.enabled ~= true then
        if not silent then showMessage(Addon.L.SHOPPING_ERROR_DISABLED) end
        return false
    end
    local recipe = collectRecipe(recipeID)
    if not recipe then
        if not silent then showMessage(Addon.L.SHOPPING_ERROR_RECIPE) end
        return false
    end

    quantity = Addon.ShoppingListLogic:ClampQuantity(quantity)
    local entry = findEntry("recipe", nil, recipe.recipeID)
    if entry then
        entry.quantity = Addon.ShoppingListLogic:ClampQuantity((tonumber(entry.quantity) or 1) + quantity)
    else
        local store = getStore()
        entry = {
            id = nextEntryID(),
            kind = "recipe",
            quantity = quantity,
            createdAt = now(),
        }
        store.entries[entry.id] = entry
        store.order[#store.order + 1] = entry.id
    end
    for key, value in pairs(recipe) do entry[key] = value end
    entry.updatedAt = now()
    self:Publish()
    self:Open()
    self:Refresh()
    if not silent then showMessage(string.format(Addon.L.SHOPPING_ADDED_RECIPE, entry.name)) end
    return true
end

function Runtime:AddSelectedRecipe()
    local recipeID = self:GetSelectedRecipeID()
    if not recipeID then
        showMessage(Addon.L.SHOPPING_ERROR_NO_RECIPE)
        return false
    end
    return self:AddRecipe(recipeID, 1, false)
end

function Runtime:ChangeQuantity(entryID, delta)
    local entry = getStore().entries[entryID]
    if type(entry) ~= "table" then return false end
    local nextValue = (tonumber(entry.quantity) or 1) + (tonumber(delta) or 0)
    if nextValue <= 0 then
        return self:RemoveEntry(entryID)
    end
    entry.quantity = Addon.ShoppingListLogic:ClampQuantity(nextValue)
    entry.updatedAt = now()
    self:Publish()
    self:Refresh()
    return true
end

function Runtime:RemoveEntry(entryID)
    local store = getStore()
    if type(entryID) ~= "string" or type(store.entries[entryID]) ~= "table" then return false end
    store.entries[entryID] = nil
    local clean = {}
    for _, id in ipairs(store.order) do
        if id ~= entryID and store.entries[id] then clean[#clean + 1] = id end
    end
    store.order = clean
    self:Publish()
    self:Refresh()
    return true
end

function Runtime:Clear()
    local store = getStore()
    store.entries = {}
    store.order = {}
    self:Publish()
    self:Refresh()
end

function Runtime:SetView(viewKey)
    local store = getStore()
    store.selectedView = viewKey == "shopping" and "shopping" or "projects"
    self:Refresh()
end

function Runtime:SetFilter(filterKey)
    local store = getStore()
    store.filter = filterKey == "all" and "all"
        or filterKey == "complete" and "complete"
        or "missing"
    self:Refresh()
end

local function createIcon(parent, size, interactive)
    local frame
    if interactive then
        frame = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        Addon.Widgets:ApplyPanelStyle(frame, "cardInset")
    else
        frame = Addon.Widgets:CreatePanel(parent, "cardInset")
    end
    frame:SetSize(size, size)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(size - 3, size - 3)
    frame.icon:SetPoint("CENTER", 0, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return frame
end

local function createProjectRow(parent)
    local row = Addon.Widgets:CreatePanel(parent, "row")
    row.icon = createIcon(row, 42)
    row.icon:SetPoint("TOPLEFT", 12, -12)
    row.title = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.title:SetPoint("TOPRIGHT", -180, -13)
    row.title:SetWordWrap(false)
    row.title:SetMaxLines(1)
    row.meta = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.meta:SetPoint("RIGHT", -180, 0)
    row.summary = Addon.Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.summary:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -4)
    row.summary:SetPoint("RIGHT", -180, 0)
    row.quantity = Addon.Widgets:CreateLabel(row, "GameFontNormalLarge", "RIGHT")
    row.quantity:SetPoint("TOPRIGHT", -16, -14)
    row.quantity:SetWidth(80)
    row.minus = Addon.Widgets:CreateButton(row, "–", 26, 24)
    row.minus:SetPoint("TOPRIGHT", -104, -44)
    row.plus = Addon.Widgets:CreateButton(row, "+", 26, 24)
    row.plus:SetPoint("LEFT", row.minus, "RIGHT", 4, 0)
    row.remove = Addon.Widgets:CreateButton(row, "X", 26, 24)
    row.remove:SetPoint("LEFT", row.plus, "RIGHT", 4, 0)
    row.reagentRows = {}
    return row
end

local function ensureReagentRow(row, index)
    if row.reagentRows[index] then return row.reagentRows[index] end
    local reagentRow = Addon.Widgets:CreatePanel(row, "cardInset")
    reagentRow:SetHeight(30)
    reagentRow.icon = reagentRow:CreateTexture(nil, "ARTWORK")
    reagentRow.icon:SetPoint("LEFT", 7, 0)
    reagentRow.icon:SetSize(21, 21)
    reagentRow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    reagentRow.name = Addon.Widgets:CreateLabel(reagentRow, "GameFontHighlightSmall", "LEFT")
    reagentRow.name:SetPoint("LEFT", reagentRow.icon, "RIGHT", 7, 0)
    reagentRow.name:SetPoint("RIGHT", -230, 0)
    reagentRow.name:SetWordWrap(false)
    reagentRow.name:SetMaxLines(1)
    reagentRow.count = Addon.Widgets:CreateLabel(reagentRow, "GameFontHighlightSmall", "RIGHT")
    reagentRow.count:SetPoint("RIGHT", -10, 0)
    reagentRow.count:SetWidth(220)
    row.reagentRows[index] = reagentRow
    return reagentRow
end

local function applyProjectRow(row, project)
    local entry = project.entry
    local r, g, b = qualityColor(entry.quality)
    row.title:SetText(entry.name or Addon.L.UNKNOWN)
    row.title:SetTextColor(r, g, b, 1)
    row.icon.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.quantity:SetText("x" .. tostring(project.quantity))
    setItemTooltip(row.icon, entry.itemLink, entry.itemID)
    row.minus:SetScript("OnClick", function() Runtime:ChangeQuantity(entry.id, -1) end)
    row.plus:SetScript("OnClick", function() Runtime:ChangeQuantity(entry.id, 1) end)
    row.remove:SetScript("OnClick", function() Runtime:RemoveEntry(entry.id) end)

    if project.kind == "recipe" then
        row.meta:SetText(string.format(
            Addon.L.SHOPPING_PROJECT_RECIPE_META,
            project.quantity,
            project.quantity * project.outputQuantity
        ))
        row.summary:SetText(string.format(Addon.L.SHOPPING_PROJECT_RECIPE_SUMMARY, #project.reagents))
        local height = 88 + (#project.reagents * 36)
        row:SetHeight(height)
        for index, reagentView in ipairs(project.reagents) do
            local reagent = reagentView.reagent
            local reagentRow = ensureReagentRow(row, index)
            reagentRow:ClearAllPoints()
            if index == 1 then
                reagentRow:SetPoint("TOPLEFT", row, "TOPLEFT", 64, -80)
            else
                reagentRow:SetPoint("TOPLEFT", row.reagentRows[index - 1], "BOTTOMLEFT", 0, -6)
            end
            reagentRow:SetPoint("RIGHT", -14, 0)
            reagentRow.icon:SetTexture(reagent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local name = reagent.name or Addon.L.UNKNOWN
            if type(reagent.itemIDs) == "table" and #reagent.itemIDs > 1 and not reagent.selectedItemID then
                name = name .. " " .. Addon.L.SHOPPING_ANY_QUALITY
            end
            reagentRow.name:SetText(name)
            reagentRow.count:SetText(string.format(
                Addon.L.SHOPPING_COUNTS,
                reagentView.required,
                reagentView.owned,
                reagentView.missing
            ))
            local color = reagentView.complete and { 0.32, 0.86, 0.44 } or { 0.95, 0.68, 0.22 }
            reagentRow.count:SetTextColor(color[1], color[2], color[3], 1)
            setItemTooltip(reagentRow, reagent.itemLink, reagent.selectedItemID or reagent.itemID)
            reagentRow:Show()
        end
        for index = #project.reagents + 1, #row.reagentRows do row.reagentRows[index]:Hide() end
        return height
    end

    row:SetHeight(76)
    row.meta:SetText(Addon.L.SHOPPING_KIND_ITEM)
    row.summary:SetText(string.format(
        Addon.L.SHOPPING_COUNTS,
        project.quantity,
        project.owned or 0,
        project.missing
    ))
    row.summary:SetTextColor(
        project.complete and 0.32 or 0.95,
        project.complete and 0.86 or 0.68,
        project.complete and 0.44 or 0.22,
        1
    )
    for _, reagentRow in ipairs(row.reagentRows) do reagentRow:Hide() end
    return 76
end

local function createPurchaseRow(parent)
    local row = Addon.Widgets:CreatePanel(parent, "row")
    row:SetHeight(58)
    row.icon = createIcon(row, 38)
    row.icon:SetPoint("LEFT", 10, 0)
    row.title = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.title:SetPoint("RIGHT", -235, 0)
    row.title:SetWordWrap(false)
    row.title:SetMaxLines(1)
    row.state = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.state:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.state:SetPoint("RIGHT", -235, 0)
    row.count = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "RIGHT")
    row.count:SetPoint("RIGHT", -14, 0)
    row.count:SetWidth(220)
    return row
end

local function applyPurchaseRow(row, material)
    row.icon.icon:SetTexture(material.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local name = material.name or Addon.L.UNKNOWN
    if material.grouped then name = name .. " " .. Addon.L.SHOPPING_ANY_QUALITY end
    row.title:SetText(name)
    row.state:SetText(material.complete and Addon.L.SHOPPING_COMPLETE or Addon.L.SHOPPING_MISSING)
    row.count:SetText(string.format(
        Addon.L.SHOPPING_COUNTS,
        material.required,
        material.owned,
        material.missing
    ))
    local color = material.complete and { 0.32, 0.86, 0.44 } or { 0.95, 0.68, 0.22 }
    row.count:SetTextColor(color[1], color[2], color[3], 1)
    row:SetBackdropBorderColor(color[1], color[2], color[3], material.complete and 0.45 or 0.82)
    setItemTooltip(row, material.itemLink, material.itemID)
end

function Runtime:BuildWindow()
    local Widgets = Addon.Widgets
    local Theme = Addon.Theme
    local Assets = Addon.Assets
    local frame = CreateFrame("Frame", "VaultloomShoppingListFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(680, 650)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Widgets:ApplyStandardGoldFrame(frame, Assets.windowBackground)
    applyPosition(frame, getStore().window, 0)

    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetPoint("TOPLEFT", 14, -12)
    frame.titleBar:SetPoint("TOPRIGHT", -48, -12)
    frame.titleBar:SetHeight(48)
    frame.titleBar:EnableMouse(true)
    frame.titleBar:RegisterForDrag("LeftButton")
    frame.titleBar:SetScript("OnDragStart", function()
        frame.dragging = true
        frame:StartMoving()
    end)
    frame.titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame, getStore().window)
        frame.dragging = false
    end)
    frame.title = Widgets:CreateLabel(frame.titleBar, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 8, -2)
    frame.title:SetText(Addon.L.SHOPPING_WINDOW_TITLE)
    frame.title:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
    frame.summary = Widgets:CreateLabel(frame.titleBar, "GameFontDisableSmall", "LEFT")
    frame.summary:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.summary:SetPoint("RIGHT", -6, 0)

    frame.close = Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.clear = Widgets:CreateButton(frame, Addon.L.SHOPPING_CLEAR, 84, 26)
    frame.clear:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -6, 0)

    frame.projectsTab = Widgets:CreateButton(frame, Addon.L.SHOPPING_TAB_PROJECTS, 160, 30, "tab")
    frame.projectsTab:SetPoint("TOPLEFT", 22, -76)
    frame.shoppingTab = Widgets:CreateButton(frame, Addon.L.SHOPPING_TAB_SHOPPING, 160, 30, "tab")
    frame.shoppingTab:SetPoint("LEFT", frame.projectsTab, "RIGHT", 8, 0)
    frame.projectsTab:SetScript("OnClick", function() Runtime:SetView("projects") end)
    frame.shoppingTab:SetScript("OnClick", function() Runtime:SetView("shopping") end)

    frame.projectControls = Widgets:CreatePanel(frame, "content")
    frame.projectControls:SetPoint("TOPLEFT", 22, -116)
    frame.projectControls:SetPoint("TOPRIGHT", -22, -116)
    frame.projectControls:SetHeight(58)
    frame.drop = createIcon(frame.projectControls, 38, true)
    frame.drop:SetPoint("LEFT", 10, 0)
    frame.drop.icon:SetColorTexture(0.055, 0.045, 0.035, 0.96)
    frame.drop.icon:SetTexCoord(0, 1, 0, 1)
    frame.drop.plusH = frame.drop:CreateTexture(nil, "OVERLAY")
    frame.drop.plusH:SetTexture(WHITE_TEXTURE)
    frame.drop.plusH:SetColorTexture(
        Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1
    )
    frame.drop.plusH:SetSize(20, 4)
    frame.drop.plusH:SetPoint("CENTER")
    frame.drop.plusV = frame.drop:CreateTexture(nil, "OVERLAY")
    frame.drop.plusV:SetTexture(WHITE_TEXTURE)
    frame.drop.plusV:SetColorTexture(
        Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1
    )
    frame.drop.plusV:SetSize(4, 20)
    frame.drop.plusV:SetPoint("CENTER")
    frame.drop:RegisterForClicks("AnyUp")
    frame.drop:SetScript("OnReceiveDrag", function()
        if type(GetCursorInfo) ~= "function" then return end
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" and Runtime:AddItem(itemLink or itemID, frame.quantityInput:GetNumber()) then
            if type(ClearCursor) == "function" then ClearCursor() end
        end
    end)
    frame.drop:SetScript("OnMouseUp", function()
        if type(GetCursorInfo) ~= "function" then return end
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" and Runtime:AddItem(itemLink or itemID, frame.quantityInput:GetNumber()) then
            if type(ClearCursor) == "function" then ClearCursor() end
        end
    end)
    frame.itemInput = CreateFrame("EditBox", nil, frame.projectControls,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame.itemInput:SetPoint("LEFT", frame.drop, "RIGHT", 8, 0)
    frame.itemInput:SetSize(242, 28)
    frame.itemInput:SetAutoFocus(false)
    frame.itemInput:SetFontObject("GameFontHighlightSmall")
    frame.itemInput:SetTextInsets(8, 8, 0, 0)
    Widgets:ApplyPanelStyle(frame.itemInput, "cardInset")
    frame.inputHint = Widgets:CreateLabel(frame.itemInput, "GameFontDisableSmall", "LEFT")
    frame.inputHint:SetPoint("LEFT", 8, 0)
    frame.inputHint:SetPoint("RIGHT", -8, 0)
    frame.inputHint:SetText(Addon.L.SHOPPING_INPUT_HINT)
    frame.itemInput:SetScript("OnTextChanged", function(self)
        frame.inputHint:SetShown((self:GetText() or "") == "")
    end)
    frame.itemInput:SetScript("OnEnterPressed", function(self)
        if Runtime:AddItem(self:GetText(), frame.quantityInput:GetNumber()) then self:SetText("") end
    end)
    frame.quantityInput = CreateFrame("EditBox", nil, frame.projectControls,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame.quantityInput:SetPoint("LEFT", frame.itemInput, "RIGHT", 6, 0)
    frame.quantityInput:SetSize(48, 28)
    frame.quantityInput:SetAutoFocus(false)
    frame.quantityInput:SetNumeric(true)
    frame.quantityInput:SetNumber(1)
    frame.quantityInput:SetFontObject("GameFontHighlightSmall")
    frame.quantityInput:SetTextInsets(8, 8, 0, 0)
    Widgets:ApplyPanelStyle(frame.quantityInput, "cardInset")
    frame.add = Widgets:CreateButton(frame.projectControls, Addon.L.SHOPPING_ADD, 84, 28)
    frame.add:SetPoint("LEFT", frame.quantityInput, "RIGHT", 6, 0)
    frame.add:SetScript("OnClick", function()
        if Runtime:AddItem(frame.itemInput:GetText(), frame.quantityInput:GetNumber()) then
            frame.itemInput:SetText("")
        end
    end)
    frame.addRecipe = Widgets:CreateButton(frame.projectControls, Addon.L.SHOPPING_ADD_RECIPE, 132, 28)
    frame.addRecipe:SetPoint("LEFT", frame.add, "RIGHT", 6, 0)
    frame.addRecipe:SetScript("OnClick", function() Runtime:AddSelectedRecipe() end)

    frame.shoppingControls = Widgets:CreatePanel(frame, "content")
    frame.shoppingControls:SetPoint("TOPLEFT", 22, -116)
    frame.shoppingControls:SetPoint("TOPRIGHT", -22, -116)
    frame.shoppingControls:SetHeight(58)
    frame.filterAll = Widgets:CreateButton(frame.shoppingControls, Addon.L.SHOPPING_FILTER_ALL, 84, 26)
    frame.filterAll:SetPoint("TOPLEFT", 10, -7)
    frame.filterMissing = Widgets:CreateButton(frame.shoppingControls, Addon.L.SHOPPING_FILTER_MISSING, 96, 26)
    frame.filterMissing:SetPoint("LEFT", frame.filterAll, "RIGHT", 4, 0)
    frame.filterComplete = Widgets:CreateButton(frame.shoppingControls, Addon.L.SHOPPING_FILTER_COMPLETE, 96, 26)
    frame.filterComplete:SetPoint("LEFT", frame.filterMissing, "RIGHT", 4, 0)
    frame.filterAll:SetScript("OnClick", function() Runtime:SetFilter("all") end)
    frame.filterMissing:SetScript("OnClick", function() Runtime:SetFilter("missing") end)
    frame.filterComplete:SetScript("OnClick", function() Runtime:SetFilter("complete") end)
    frame.coverage = Widgets:CreateLabel(frame.shoppingControls, "GameFontDisableSmall", "RIGHT")
    frame.coverage:SetPoint("LEFT", frame.filterComplete, "RIGHT", 6, 0)
    frame.coverage:SetPoint("RIGHT", -10, 0)
    frame.coverage:SetWordWrap(true)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -186)
    frame.scroll:SetPoint("BOTTOMRIGHT", -42, 22)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(604, 20)
    frame.scroll:SetScrollChild(frame.child)
    Addon.ScrollFrames:Style(frame.scroll, { autoHide = true })
    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisable", "CENTER")
    frame.empty:SetPoint("TOP", 0, -46)
    frame.empty:SetWidth(500)

    frame.confirm = Widgets:CreatePanel(frame, "content")
    frame.confirm:SetSize(420, 150)
    frame.confirm:SetPoint("CENTER")
    frame.confirm:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.confirm.title = Widgets:CreateLabel(frame.confirm, "GameFontNormalLarge", "CENTER")
    frame.confirm.title:SetPoint("TOPLEFT", 18, -20)
    frame.confirm.title:SetPoint("TOPRIGHT", -18, -20)
    frame.confirm.title:SetText(Addon.L.SHOPPING_CLEAR_CONFIRM)
    frame.confirm.cancel = Widgets:CreateButton(frame.confirm, Addon.L.SIDEBAR_CANCEL, 110, 30)
    frame.confirm.cancel:SetPoint("BOTTOMLEFT", 36, 22)
    frame.confirm.accept = Widgets:CreateButton(frame.confirm, Addon.L.SHOPPING_CLEAR, 110, 30)
    frame.confirm.accept:SetPoint("BOTTOMRIGHT", -36, 22)
    frame.confirm.cancel:SetScript("OnClick", function() frame.confirm:Hide() end)
    frame.confirm.accept:SetScript("OnClick", function()
        frame.confirm:Hide()
        Runtime:Clear()
    end)
    frame.confirm:Hide()
    frame.clear:SetScript("OnClick", function() frame.confirm:Show() end)

    frame:SetScript("OnShow", function() Runtime:Refresh() end)
    frame:Hide()
    self.window = frame
    return frame
end

function Runtime:EnsureWindow()
    return self.window or self:BuildWindow()
end

function Runtime:Refresh()
    local frame = self.window
    if not frame or not frame:IsShown() then return end
    local store = getStore()
    local plan = self:GetPlan()
    frame.summary:SetText(string.format(
        Addon.L.SHOPPING_SUMMARY,
        plan.summary.projects,
        plan.summary.materials,
        plan.summary.missingTypes
    ))
    local shoppingView = store.selectedView == "shopping"
    Addon.Widgets:SetButtonActive(frame.projectsTab, not shoppingView)
    Addon.Widgets:SetButtonActive(frame.shoppingTab, shoppingView)
    frame.projectControls:SetShown(not shoppingView)
    frame.shoppingControls:SetShown(shoppingView)
    frame.clear:SetShown(not shoppingView and #plan.projects > 0)

    for _, row in ipairs(self.projectRows) do row:Hide() end
    for _, row in ipairs(self.purchaseRows) do row:Hide() end
    local contentHeight, previous, visibleCount = 0, nil, 0

    if shoppingView then
        Addon.Widgets:SetButtonActive(frame.filterAll, store.filter == "all")
        Addon.Widgets:SetButtonActive(frame.filterMissing, store.filter == "missing")
        Addon.Widgets:SetButtonActive(frame.filterComplete, store.filter == "complete")
        local coverage = Addon.InventoryIndex:GetCoverage()
        local unknownBanks = math.max(0, coverage.characters - coverage.banksKnown)
        if unknownBanks > 0 then
            frame.coverage:SetText(string.format(Addon.L.SHOPPING_BANK_WARNING, unknownBanks))
        elseif not coverage.warbandKnown then
            frame.coverage:SetText(Addon.L.SHOPPING_WARBAND_WARNING)
        else
            frame.coverage:SetText("")
        end
        local purchases = Addon.ShoppingListLogic:FilterPurchases(plan.purchases, store.filter)
        for index, material in ipairs(purchases) do
            local row = self.purchaseRows[index] or createPurchaseRow(frame.child)
            self.purchaseRows[index] = row
            row:ClearAllPoints()
            if previous then row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
            else row:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, 0) end
            row:SetPoint("RIGHT", -4, 0)
            applyPurchaseRow(row, material)
            row:Show()
            previous = row
            contentHeight = contentHeight + 58 + (index > 1 and 8 or 0)
            visibleCount = visibleCount + 1
        end
        frame.empty:SetText(store.filter == "missing"
            and Addon.L.SHOPPING_NO_MISSING or Addon.L.SHOPPING_EMPTY)
    else
        frame.coverage:SetText("")
        for index, project in ipairs(plan.projects) do
            local row = self.projectRows[index] or createProjectRow(frame.child)
            self.projectRows[index] = row
            row:ClearAllPoints()
            if previous then row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
            else row:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, 0) end
            row:SetPoint("RIGHT", -4, 0)
            local height = applyProjectRow(row, project)
            row:Show()
            previous = row
            contentHeight = contentHeight + height + (index > 1 and 8 or 0)
            visibleCount = visibleCount + 1
        end
        frame.empty:SetText(Addon.L.SHOPPING_EMPTY)
    end
    frame.empty:SetShown(visibleCount == 0)
    frame.child:SetHeight(math.max(20, contentHeight))
    Addon.ScrollFrames:Refresh(frame.scroll)
end

function Runtime:Open()
    if self.enabled ~= true then
        showMessage(Addon.L.SHOPPING_ERROR_DISABLED)
        return false
    end
    local frame = self:EnsureWindow()
    frame:Show()
    self:Refresh()
    return true
end

function Runtime:Toggle()
    if self.window and self.window:IsShown() then self.window:Hide(); return true end
    return self:Open()
end

function Runtime:EnsureMiniButton()
    if self.miniButton then return self.miniButton end
    local button = CreateFrame("Button", "VaultloomShoppingMiniButton", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    button:SetSize(46, 46)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:EnableMouse(true)
    button:EnableMouseWheel(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.backplate = button:CreateTexture(nil, "BACKGROUND")
    button.backplate:SetPoint("TOPLEFT", -2, 2)
    button.backplate:SetPoint("BOTTOMRIGHT", 2, -2)
    button.backplate:SetTexture(Addon.Assets.classBackplate)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(37, 37)
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.iconMask = button:CreateMaskTexture(nil, "ARTWORK")
    button.iconMask:SetTexture(
        "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    button.iconMask:SetAllPoints(button.icon)
    button.icon:AddMaskTexture(button.iconMask)
    button.ring = button:CreateTexture(nil, "OVERLAY")
    button.ring:SetPoint("TOPLEFT", -2, 2)
    button.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    button.ring:SetTexture(Addon.Assets.classRing)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            local position = getStore().miniButton
            position.point, position.relativePoint, position.x, position.y, position.scale =
                "CENTER", "CENTER", 460, 0, 1
            applyPosition(button, position, 460)
            button:SetScale(1)
        else
            Runtime:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, getStore().miniButton)
        self.dragging = false
    end)
    button:SetScript("OnMouseWheel", function(self, delta)
        if type(IsShiftKeyDown) == "function" and not IsShiftKeyDown() then return end
        local position = getStore().miniButton
        local scale = tonumber(position.scale) or 1
        scale = math.max(MINI_SCALE_MIN, math.min(
            MINI_SCALE_MAX,
            scale + (delta > 0 and MINI_SCALE_STEP or -MINI_SCALE_STEP)
        ))
        position.scale = scale
        self:SetScale(scale)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Addon.L.FEATURE_SHOPPING_LIST, 1, 0.82, 0.24, true)
        GameTooltip:AddLine(Addon.L.SHOPPING_MINI_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    applyPosition(button, getStore().miniButton, 460)
    button:SetScale(math.max(MINI_SCALE_MIN, math.min(
        MINI_SCALE_MAX,
        tonumber(getStore().miniButton.scale) or 1
    )))
    button:Hide()
    self.miniButton = button
    return button
end

function Runtime:EnsureMinimapButton()
    if self.minimapButton or not Minimap then return self.minimapButton end
    local button = CreateFrame("Button", "VaultloomShoppingMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((type(Minimap.GetFrameLevel) == "function"
        and Minimap:GetFrameLevel() or 1) + 9)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if type(button.icon.AddMaskTexture) == "function" then
        button.mask = button:CreateMaskTexture(nil, "ARTWORK")
        button.mask:SetTexture(
            "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        button.mask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(button.mask)
    end

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetColorTexture(1.00, 0.82, 0.46, 0.16)
    button.highlight:SetBlendMode("ADD")
    button.highlight:SetSize(24, 24)
    button.highlight:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    if type(button.highlight.AddMaskTexture) == "function" then
        button.highlightMask = button:CreateMaskTexture(nil, "HIGHLIGHT")
        button.highlightMask:SetTexture(
            "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        button.highlightMask:SetAllPoints(button.highlight)
        button.highlight:AddMaskTexture(button.highlightMask)
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            getStore().minimapButton.angle = MINIMAP_DEFAULT_ANGLE
            updateMinimapButtonPosition(button)
        else
            Runtime:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        if type(self.LockHighlight) == "function" then self:LockHighlight() end
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", function(activeButton)
            updateMinimapButtonDrag(activeButton)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if type(self.UnlockHighlight) == "function" then self:UnlockHighlight() end
        updateMinimapButtonPosition(self)
    end)
    button:SetScript("OnEnter", function(self)
        if self.dragging or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(Addon.L.FEATURE_SHOPPING_LIST, 1, 0.82, 0.24, true)
        GameTooltip:AddLine(Addon.L.SHOPPING_MINIMAP_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    updateMinimapButtonPosition(button)
    button:Hide()
    self.minimapButton = button
    return button
end

function Runtime:RefreshMiniButton()
    local mode = self.enabled
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "launcher_mode") or "off"
    if mode == "floating" then self:EnsureMiniButton():Show()
    elseif self.miniButton then self.miniButton:Hide() end
    if mode == "minimap" then
        local button = self:EnsureMinimapButton()
        if button then
            updateMinimapButtonPosition(button)
            button:Show()
        end
    elseif self.minimapButton then
        self.minimapButton:Hide()
    end
end

local function attachIntegrationButton(runtime, fieldName, parent, label, callback)
    local button = runtime[fieldName]
    if not button then
        button = Addon.Widgets:CreateButton(parent, label, 132, 28)
        button:SetFrameStrata("HIGH")
        button:SetScript("OnClick", callback)
        runtime[fieldName] = button
    end
    if type(button.SetParent) == "function" then button:SetParent(parent) end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, -62)
    return button
end

function Runtime:RefreshProfessionButton()
    local parent = getProfessionFrame()
    local visible = self.enabled
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "recipe_button") == true
        and parent ~= nil
        and self:GetSelectedRecipeID() ~= nil
    if visible then
        attachIntegrationButton(
            self,
            "professionButton",
            parent,
            Addon.L.SHOPPING_PROFESSION_BUTTON,
            function() Runtime:AddSelectedRecipe() end
        ):Show()
    elseif self.professionButton then
        self.professionButton:Hide()
    end
end

local function extractAuctionItem(value, depth)
    depth = (tonumber(depth) or 0) + 1
    if depth > 4 then return nil end
    if type(value) == "number" or type(value) == "string" then
        return parseItemID(value), type(value) == "string" and value or nil
    end
    if type(value) ~= "table" then return nil end
    local itemLink = value.itemLink or value.link or value.hyperlink
        or callMethod(value, "GetItemLink") or callMethod(value, "GetItemHyperlink")
    local itemID = parseItemID(itemLink or value.itemID or value.itemId or value.id)
        or parseItemID(callMethod(value, "GetItemID"))
        or parseItemID(callMethod(value, "GetID"))
    if itemID then return itemID, itemLink end
    for _, key in ipairs({
        "itemKey",
        "item",
        "itemInfo",
        "selectedEntry",
        "selectedResult",
        "selectedItem",
        "selectedItemKey",
    }) do
        itemID, itemLink = extractAuctionItem(value[key], depth)
        if itemID then return itemID, itemLink end
    end
    for _, methodName in ipairs({
        "GetSelectedEntry",
        "GetSelectedItem",
        "GetSelectedItemKey",
        "GetItem",
        "GetItemKey",
    }) do
        itemID, itemLink = extractAuctionItem(callMethod(value, methodName), depth)
        if itemID then return itemID, itemLink end
    end
    return nil
end

local function extractAuctionDisplay(display)
    if type(display) ~= "table" then return nil end
    local location = callMethod(display, "GetItemLocation")
    if location then
        local itemLink
        if C_Item and type(C_Item.GetItemLink) == "function" then
            local ok, value = pcall(C_Item.GetItemLink, location)
            if ok then itemLink = value end
        end
        local itemID = parseItemID(itemLink)
        if not itemID and C_AuctionHouse
            and type(C_AuctionHouse.GetItemKeyFromItem) == "function"
        then
            local ok, itemKey = pcall(C_AuctionHouse.GetItemKeyFromItem, location)
            if ok and type(itemKey) == "table" then
                itemID = parseItemID(itemKey.itemID or itemKey.itemId)
            end
        end
        if itemID then return itemID, itemLink end
    end
    return extractAuctionItem(display)
end

function Runtime:GetAuctionItem()
    local frame = type(AuctionHouseFrame) == "table" and AuctionHouseFrame or nil
    if not frame or (type(frame.IsShown) == "function" and not frame:IsShown()) then return nil end
    local candidates = {}
    local function addCandidate(value)
        if type(value) == "table" then candidates[#candidates + 1] = value end
    end
    for _, fieldName in ipairs({
        "CommoditiesSellFrame",
        "ItemSellFrame",
        "CommoditiesBuyFrame",
        "ItemBuyFrame",
        "BuyDialog",
    }) do
        local subFrame = frame[fieldName]
        if type(subFrame) == "table" then addCandidate(subFrame.ItemDisplay) end
    end
    addCandidate(frame.CommoditiesSellFrame)
    addCandidate(frame.ItemSellFrame)
    addCandidate(frame.ItemBuyFrame)
    addCandidate(frame.CommoditiesBuyFrame)
    addCandidate(frame.BrowseResultsFrame)
    addCandidate(frame.BuyDialog)
    for _, candidate in ipairs(candidates) do
        local itemID, itemLink = extractAuctionDisplay(candidate)
        if itemID then return itemLink or itemID end
    end
    return nil
end

function Runtime:AddAuctionItem()
    local value = self:GetAuctionItem()
    if not value then
        showMessage(Addon.L.SHOPPING_ERROR_AUCTION)
        return false
    end
    self:Open()
    return self:AddItem(value, 1, false)
end

function Runtime:RefreshAuctionButton()
    local parent = type(AuctionHouseFrame) == "table" and AuctionHouseFrame or nil
    local visible = self.enabled
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "auction_button") == true
        and parent ~= nil
        and (type(parent.IsShown) ~= "function" or parent:IsShown())
    if visible then
        attachIntegrationButton(
            self,
            "auctionButton",
            parent,
            Addon.L.SHOPPING_AUCTION_BUTTON,
            function() Runtime:AddAuctionItem() end
        ):Show()
    elseif self.auctionButton then
        self.auctionButton:Hide()
    end
end

function Runtime:HandleEvent(eventName)
    if eventName == "TRADE_SKILL_CLOSE" then
        if self.professionButton then self.professionButton:Hide() end
    elseif eventName == "AUCTION_HOUSE_CLOSED" then
        if self.auctionButton then self.auctionButton:Hide() end
    elseif eventName == "ITEM_DATA_LOAD_RESULT" then
        for _, entry in ipairs(orderedEntries()) do
            if entry.itemID then
                local details = getItemDetails(entry.itemID, entry)
                if details then
                    entry.itemLink, entry.name, entry.icon, entry.quality =
                        details.itemLink, details.name, details.icon, details.quality
                end
            end
            for _, reagent in ipairs(type(entry.reagents) == "table" and entry.reagents or {}) do
                local reagentID = reagent.selectedItemID or reagent.itemID
                if reagentID then
                    local details = getItemDetails(reagentID, reagent)
                    if details then
                        reagent.itemLink = details.itemLink
                        reagent.name = details.name
                        reagent.icon = details.icon
                        reagent.quality = details.quality
                    end
                end
            end
        end
        self:Refresh()
    else
        self:RefreshProfessionButton()
        self:RefreshAuctionButton()
    end
end

function Runtime:OnEnable()
    self.enabled = true
    Addon.StateStore:Subscribe("arsenal.snapshots", self, function()
        if Runtime.window and Runtime.window:IsShown() then Runtime:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.roster", self, function()
        if Runtime.window and Runtime.window:IsShown() then Runtime:Refresh() end
    end)
    Addon.StateStore:Subscribe("mailbox.snapshots", self, function()
        if Runtime.window and Runtime.window:IsShown() then Runtime:Refresh() end
    end)
    for _, eventName in ipairs({
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_CLOSE",
        "TRADE_SKILL_LIST_UPDATE",
        "PROFESSIONS_CRAFTING_FORM_REFRESH",
        "PROFESSIONS_RECIPE_LIST_SELECTION_CHANGED",
        "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED",
        "ITEM_DATA_LOAD_RESULT",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            Runtime:HandleEvent(event)
        end)
    end
    self:RefreshMiniButton()
    self:RefreshProfessionButton()
    self:RefreshAuctionButton()
    self:Publish()
end

function Runtime:OnDisable()
    self.enabled = false
    if self.window then self.window:Hide() end
    if self.miniButton then self.miniButton:Hide() end
    if self.minimapButton then self.minimapButton:Hide() end
    if self.professionButton then self.professionButton:Hide() end
    if self.auctionButton then self.auctionButton:Hide() end
end

function Runtime:OnSettingChanged()
    self:RefreshMiniButton()
    self:RefreshProfessionButton()
    self:RefreshAuctionButton()
end

function Runtime:OnSettingsReset()
    self:OnSettingChanged()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Shopping List feature runtime.")
end
