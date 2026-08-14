local _, Addon = ...

local FEATURE_ID = "item_finder"
local MAX_RESULTS = 100
local ROW_HEIGHT = 82
local ROW_GAP = 8
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local BAG_FRAME_LIMIT = 13
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"

local Runtime = {
    enabled = false,
    window = nil,
    rows = {},
    lastIndex = nil,
    bagButton = nil,
    entrypointRefreshQueued = false,
}

Addon.ItemFinder = Runtime

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.itemFinder = type(db.features.itemFinder) == "table"
        and db.features.itemFinder or {}
    local store = db.features.itemFinder
    store.window = type(store.window) == "table" and store.window or {}
    return store
end

local function isShown(frame)
    if not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function showEntrypointTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
    local gold = Addon.Theme.colors.gold
    GameTooltip:AddLine(Addon.L.ITEM_FINDER_BUTTON_TOOLTIP, gold[1], gold[2], gold[3])
    local windowOpen = Runtime.window and Runtime.window:IsShown()
    GameTooltip:AddLine(
        windowOpen and Addon.L.ITEM_FINDER_BUTTON_CLOSE or Addon.L.ITEM_FINDER_BUTTON_OPEN,
        0.72,
        0.78,
        0.88,
        true
    )
    GameTooltip:Show()
end

local function addSearchIcon(button, size)
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(SEARCH_ICON)
    icon:SetSize(size or 18, size or 18)
    icon:SetPoint("CENTER", 0, 0)
    local gold = Addon.Theme.colors.gold
    icon:SetVertexColor(gold[1], gold[2], gold[3], 0.96)
    button.itemFinderIcon = icon
end

function Runtime:EnsureBagButton()
    if self.bagButton then return self.bagButton end
    local button = Addon.Widgets:CreateSimpleGoldButton(UIParent, "", 30, 28)
    addSearchIcon(button, 18)
    button:SetFrameStrata("HIGH")
    button:SetScript("OnClick", function()
        Runtime:Toggle()
    end)
    local baseEnter = button:GetScript("OnEnter")
    local baseLeave = button:GetScript("OnLeave")
    button:SetScript("OnEnter", function(selfButton)
        if baseEnter then baseEnter(selfButton) end
        showEntrypointTooltip(selfButton)
    end)
    button:SetScript("OnLeave", function(selfButton)
        if baseLeave then baseLeave(selfButton) end
        hideTooltip()
    end)
    button:Hide()
    self.bagButton = button
    return button
end

function Runtime:QueueEntrypointRefresh()
    if self.entrypointRefreshQueued then return end
    self.entrypointRefreshQueued = true
    local callback = function()
        Runtime.entrypointRefreshQueued = false
        if Runtime.enabled then Runtime:RefreshEntrypoints() end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, callback)
    else
        callback()
    end
end

function Runtime:HookBagFrame(frame)
    if not frame or frame.VaultloomItemFinderHooked == true
        or type(frame.HookScript) ~= "function"
    then
        return
    end
    frame.VaultloomItemFinderHooked = true
    frame:HookScript("OnShow", function() Runtime:QueueEntrypointRefresh() end)
    frame:HookScript("OnHide", function() Runtime:QueueEntrypointRefresh() end)
end

function Runtime:FindBagAnchor()
    local combined = _G.ContainerFrameCombinedBags
    self:HookBagFrame(combined)
    if isShown(combined) then return combined end

    local backpack
    local fallback
    local frameLimit = math.max(BAG_FRAME_LIMIT, tonumber(NUM_CONTAINER_FRAMES) or 0)
    for index = 1, frameLimit do
        local frame = _G["ContainerFrame" .. index]
        self:HookBagFrame(frame)
        if isShown(frame) then
            fallback = fallback or frame
            local ok, bagID = false, nil
            if type(frame.GetID) == "function" then
                ok, bagID = pcall(frame.GetID, frame)
            end
            if ok and tonumber(bagID) == 0 then
                backpack = frame
                break
            end
        end
    end
    return backpack or fallback
end

function Runtime:RefreshBagButton()
    local button = self.bagButton
    local visible = self.enabled == true
        and Addon.FeatureRegistry:GetSetting(FEATURE_ID, "bag_button") == true
    local anchor = visible and self:FindBagAnchor() or nil
    if not anchor then
        if button then button:Hide() end
        return
    end

    button = button or self:EnsureBagButton()
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, -2)
    if type(anchor.GetFrameStrata) == "function" then
        button:SetFrameStrata(anchor:GetFrameStrata() or "HIGH")
    end
    if type(anchor.GetFrameLevel) == "function" then
        button:SetFrameLevel((tonumber(anchor:GetFrameLevel()) or 1) + 10)
    end
    button:Show()
end

function Runtime:RefreshEntrypoints()
    self:RefreshBagButton()
    if Addon.UI and type(Addon.UI.RefreshItemFinderButton) == "function" then
        Addon.UI:RefreshItemFinderButton()
    end
end

local function savePosition(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local destination = getStore().window
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

local function applyPosition(frame)
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

local function isUnknownName(name)
    return type(name) ~= "string"
        or name == ""
        or name == Addon.L.UNKNOWN
        or name == "Unknown"
end

local function resolveItemMetadata(entry)
    if type(entry) ~= "table" or not tonumber(entry.itemID) then
        return false
    end
    local itemID = tonumber(entry.itemID)

    local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local needsItemInfo = isUnknownName(entry.itemName)
        or type(entry.itemLink) ~= "string"
        or entry.itemLink == ""
        or entry.icon == nil
        or entry.quality == nil
    if needsItemInfo and type(getItemInfo) == "function" then
        local ok, name, itemLink, quality, _, _, _, _, _, _, icon = pcall(getItemInfo, itemID)
        if ok then
            if type(name) == "string" and name ~= "" then entry.itemName = name end
            if type(itemLink) == "string" and itemLink ~= "" then entry.itemLink = itemLink end
            if tonumber(quality) then entry.quality = tonumber(quality) end
            if icon ~= nil then entry.icon = icon end
        end
    end
    if not entry.icon and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon ~= nil then entry.icon = icon end
    end
    if isUnknownName(entry.itemName)
        and C_Item and type(C_Item.GetItemNameByID) == "function"
    then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(name) == "string" and name ~= "" then entry.itemName = name end
    end
    if isUnknownName(entry.itemName)
        and not entry.finderLoadRequested
        and C_Item and type(C_Item.RequestLoadItemDataByID) == "function"
    then
        entry.finderLoadRequested = true
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return not isUnknownName(entry.itemName)
end

function Runtime:ResolveIndexMetadata(index)
    for _, entry in pairs(type(index and index.items) == "table" and index.items or {}) do
        resolveItemMetadata(entry)
    end
    self.lastIndex = index
end

local function qualityColor(quality)
    local color = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[tonumber(quality)] or nil
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    local fallback = Addon.Theme.colors.parchment
    return fallback[1], fallback[2], fallback[3]
end

local function showItemTooltip(row)
    local result = row and row.result
    if not result or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if type(result.itemLink) == "string"
        and result.itemLink ~= ""
        and type(GameTooltip.SetHyperlink) == "function"
    then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, result.itemLink)
        if not ok then GameTooltip:AddLine(result.itemName or Addon.L.UNKNOWN) end
    else
        GameTooltip:AddLine(result.itemName or Addon.L.UNKNOWN)
        GameTooltip:AddLine(string.format(Addon.L.ITEM_FINDER_ITEM_ID, result.itemID), 0.72, 0.68, 0.58)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Addon.L.ITEM_FINDER_ROW_HINT, 0.64, 0.76, 1, true)
    GameTooltip:Show()
end

local function insertItemLink(result)
    if not result or type(ChatEdit_InsertLink) ~= "function" then return false end
    local itemLink = result.itemLink or ("item:" .. tostring(result.itemID))
    local ok, inserted = pcall(ChatEdit_InsertLink, itemLink)
    return ok and inserted ~= false
end

local function createResultRow(parent)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(ROW_HEIGHT)
    Addon.Widgets:ApplyPanelStyle(row, "card")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(44, 44)
    row.icon:SetPoint("TOPLEFT", 12, -12)

    row.title = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.title:SetPoint("RIGHT", -125, 0)
    row.title:SetWordWrap(false)
    row.title:SetMaxLines(1)

    row.itemID = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.itemID:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.itemID:SetPoint("RIGHT", -125, 0)

    row.total = Addon.Widgets:CreateLabel(row, "GameFontNormalLarge", "RIGHT")
    row.total:SetPoint("TOPRIGHT", -14, -13)
    row.total:SetWidth(100)
    row.total:SetTextColor(
        Addon.Theme.colors.gold[1],
        Addon.Theme.colors.gold[2],
        Addon.Theme.colors.gold[3],
        1
    )

    row.locations = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.locations:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -8)
    row.locations:SetPoint("BOTTOMRIGHT", -14, 6)
    row.locations:SetWordWrap(true)
    row.locations:SetMaxLines(2)

    row:SetScript("OnEnter", showItemTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self)
        if type(IsModifiedClick) ~= "function" or IsModifiedClick("CHATLINK") then
            insertItemLink(self.result)
        end
    end)
    return row
end

local function applyResultRow(row, result)
    row.result = result
    row.icon:SetTexture(result.icon or UNKNOWN_ICON)
    local name = result.itemName
    if isUnknownName(name) then
        name = string.format(Addon.L.SHOPPING_ITEM_FALLBACK, result.itemID)
    end
    row.title:SetText(name)
    row.title:SetTextColor(qualityColor(result.quality))
    row.itemID:SetText(string.format(Addon.L.ITEM_FINDER_ITEM_ID, result.itemID))
    row.total:SetText(tostring(result.total))
    row.locations:SetText(Addon.ItemFinderLogic:BuildLocationText(result, {
        bags = Addon.L.FEATURE_INVENTORY_SOURCE_BAGS,
        bank = Addon.L.FEATURE_INVENTORY_SOURCE_BANK,
        reagents = Addon.L.FEATURE_INVENTORY_SOURCE_REAGENTS,
        equipped = Addon.L.FEATURE_INVENTORY_SOURCE_EQUIPPED,
        warband = Addon.L.FEATURE_INVENTORY_WARBAND_BANK,
        unknown = Addon.L.UNKNOWN,
        moreCharacters = Addon.L.FEATURE_INVENTORY_MORE_CHARACTERS,
    }, 3))
end

function Runtime:BuildWindow()
    local Widgets = Addon.Widgets
    local Theme = Addon.Theme
    local frame = CreateFrame("Frame", "VaultloomItemFinderFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(760, 650)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)
    applyPosition(frame)

    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetPoint("TOPLEFT", 14, -12)
    frame.titleBar:SetPoint("TOPRIGHT", -48, -12)
    frame.titleBar:SetHeight(48)
    frame.titleBar:EnableMouse(true)
    frame.titleBar:RegisterForDrag("LeftButton")
    frame.titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame)
    end)

    frame.title = Widgets:CreateLabel(frame.titleBar, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 8, -2)
    frame.title:SetText(Addon.L.FEATURE_ITEM_FINDER)
    frame.title:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
    frame.subtitle = Widgets:CreateLabel(frame.titleBar, "GameFontDisableSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.subtitle:SetPoint("RIGHT", -6, 0)
    frame.subtitle:SetText(Addon.L.ITEM_FINDER_SUBTITLE)

    frame.close = Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.searchPanel = Widgets:CreatePanel(frame, "content")
    frame.searchPanel:SetPoint("TOPLEFT", 22, -76)
    frame.searchPanel:SetPoint("TOPRIGHT", -22, -76)
    frame.searchPanel:SetHeight(58)

    frame.search = CreateFrame("EditBox", nil, frame.searchPanel, BACKDROP_TEMPLATE)
    frame.search:SetPoint("LEFT", 10, 0)
    frame.search:SetSize(500, 30)
    frame.search:SetAutoFocus(false)
    frame.search:SetFontObject("GameFontHighlightSmall")
    frame.search:SetTextInsets(8, 8, 0, 0)
    Widgets:ApplyPanelStyle(frame.search, "cardInset")
    frame.searchHint = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.searchHint:SetPoint("RIGHT", -8, 0)
    frame.searchHint:SetText(Addon.L.ITEM_FINDER_SEARCH_PLACEHOLDER)
    frame.search:SetScript("OnTextChanged", function(self)
        frame.searchHint:SetShown((self:GetText() or "") == "")
        Runtime:Refresh()
    end)
    frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else frame:Hide() end
    end)

    frame.clear = Widgets:CreateButton(frame.searchPanel, "X", 32, 28)
    frame.clear:SetPoint("LEFT", frame.search, "RIGHT", 6, 0)
    frame.clear:SetScript("OnClick", function()
        frame.search:SetText("")
        frame.search:SetFocus()
    end)

    frame.summary = Widgets:CreateLabel(frame.searchPanel, "GameFontHighlightSmall", "RIGHT")
    frame.summary:SetPoint("LEFT", frame.clear, "RIGHT", 8, 0)
    frame.summary:SetPoint("RIGHT", -10, 0)
    frame.summary:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)

    frame.coverage = Widgets:CreateLabel(frame, "GameFontDisableSmall", "LEFT")
    frame.coverage:SetPoint("TOPLEFT", 26, -142)
    frame.coverage:SetPoint("TOPRIGHT", -26, -142)
    frame.coverage:SetHeight(28)
    frame.coverage:SetWordWrap(true)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -174)
    frame.scroll:SetPoint("BOTTOMRIGHT", -42, 40)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(680, 20)
    frame.scroll:SetScrollChild(frame.child)
    Addon.ScrollFrames:Style(frame.scroll, { autoHide = true })

    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisableLarge", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 30, -70)
    frame.empty:SetPoint("TOPRIGHT", -30, -70)
    frame.empty:SetWordWrap(true)

    frame.hint = Widgets:CreateLabel(frame, "GameFontDisableSmall", "LEFT")
    frame.hint:SetPoint("BOTTOMLEFT", 24, 18)
    frame.hint:SetPoint("BOTTOMRIGHT", -24, 18)
    frame.hint:SetText(Addon.L.ITEM_FINDER_ROW_HINT)

    frame:SetScript("OnShow", function()
        Runtime:Refresh()
        Runtime:RefreshEntrypoints()
        frame.search:SetFocus()
    end)
    frame:SetScript("OnHide", function()
        Runtime:RefreshEntrypoints()
    end)
    frame:Hide()
    self.window = frame
    return frame
end

function Runtime:EnsureWindow()
    return self.window or self:BuildWindow()
end

function Runtime:GetSearchOptions()
    return {
        includeWarband = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "warband_bank") == true,
        includeEquipped = Addon.FeatureRegistry:GetSetting(FEATURE_ID, "equipped_items") == true,
        limit = MAX_RESULTS,
    }
end

function Runtime:RefreshCoverage(stats)
    local frame = self.window
    if not frame then return end
    local coverage = Addon.InventoryIndex:GetCoverage()
    local messages = {}
    local unknownBanks = math.max(0, coverage.characters - coverage.banksKnown)
    if unknownBanks > 0 then
        messages[#messages + 1] = string.format(Addon.L.SHOPPING_BANK_WARNING, unknownBanks)
    end
    if self:GetSearchOptions().includeWarband and not coverage.warbandKnown then
        messages[#messages + 1] = Addon.L.SHOPPING_WARBAND_WARNING
    end
    if stats and stats.truncated then
        messages[#messages + 1] = string.format(Addon.L.ITEM_FINDER_MORE_RESULTS, stats.shown, stats.totalMatches)
    end
    frame.coverage:SetText(table.concat(messages, "  •  "))
end

function Runtime:Refresh()
    local frame = self.window
    if not frame or not frame:IsShown() then return end
    local index = Addon.InventoryIndex:GetIndex()
    if self.lastIndex ~= index then self:ResolveIndexMetadata(index) end

    local query = frame.search:GetText() or ""
    local results, stats = Addon.ItemFinderLogic:Search(index, query, self:GetSearchOptions())
    local totalCopies = 0
    for _, result in ipairs(results) do totalCopies = totalCopies + (tonumber(result.total) or 0) end
    frame.summary:SetText(string.format(Addon.L.ITEM_FINDER_SUMMARY, stats.totalMatches, totalCopies))
    self:RefreshCoverage(stats)

    for _, row in ipairs(self.rows) do row:Hide() end
    local previous
    for rowIndex, result in ipairs(results) do
        local row = self.rows[rowIndex] or createResultRow(frame.child)
        self.rows[rowIndex] = row
        row:ClearAllPoints()
        if previous then
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_GAP)
        else
            row:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", -4, 0)
        applyResultRow(row, result)
        row:Show()
        previous = row
    end

    local hasQuery = query:match("%S") ~= nil
    frame.empty:SetText(hasQuery
        and string.format(Addon.L.ITEM_FINDER_NO_RESULTS, query)
        or Addon.L.ITEM_FINDER_EMPTY)
    frame.empty:SetShown(#results == 0)
    frame.child:SetHeight(math.max(20, (#results * ROW_HEIGHT) + (math.max(0, #results - 1) * ROW_GAP)))
    Addon.ScrollFrames:Refresh(frame.scroll, false)
end

function Runtime:Open(query)
    if self.enabled ~= true then
        Addon:Print(Addon.L.ITEM_FINDER_ERROR_DISABLED)
        return false
    end
    local frame = self:EnsureWindow()
    frame:Show()
    if type(query) == "string" and query:match("%S") then
        frame.search:SetText(query)
        frame.search:HighlightText()
    end
    self:Refresh()
    frame:Raise()
    return true
end

function Runtime:Toggle(query)
    if self.window and self.window:IsShown() and not (type(query) == "string" and query:match("%S")) then
        self.window:Hide()
        return true
    end
    return self:Open(query)
end

function Runtime:HandleItemData(itemID)
    local index = Addon.InventoryIndex:GetIndex()
    local entry = type(index.items) == "table" and index.items[tonumber(itemID)] or nil
    if entry then resolveItemMetadata(entry) end
    self:Refresh()
end

function Runtime:OnEnable()
    self.enabled = true
    Addon.StateStore:Subscribe("arsenal.snapshots", self, function()
        Runtime.lastIndex = nil
        Runtime:Refresh()
    end)
    Addon.StateStore:Subscribe("warband.roster", self, function()
        Runtime.lastIndex = nil
        Runtime:Refresh()
    end)
    Addon.StateStore:Subscribe("mailbox.snapshots", self, function()
        Runtime.lastIndex = nil
        Runtime:Refresh()
    end)
    Addon.EventBus:Subscribe("ITEM_DATA_LOAD_RESULT", self, function(_, itemID)
        Runtime:HandleItemData(itemID)
    end)
    Addon.EventBus:Subscribe("ADDON_LOADED", self, function()
        Runtime:QueueEntrypointRefresh()
    end)
    self:RefreshEntrypoints()
end

function Runtime:OnDisable()
    self.enabled = false
    self.lastIndex = nil
    if self.window then self.window:Hide() end
    if self.bagButton then self.bagButton:Hide() end
    self:RefreshEntrypoints()
end

function Runtime:OnSettingChanged(settingKey)
    self:Refresh()
    if settingKey == "bag_button" or settingKey == "wishlist_button" then
        self:RefreshEntrypoints()
    end
end

function Runtime:OnSettingsReset()
    self:Refresh()
    self:RefreshEntrypoints()
end

function Runtime:OnAction(actionKey)
    if actionKey == "open_finder" then
        return self:Open()
    end
    return false
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Item Finder feature runtime.")
end
