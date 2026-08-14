local _, Addon = ...

local FEATURE_ID = "quiet_loot"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_VISIBLE_LOOT_ROWS = 6
local MAX_TOAST_ROWS = 5
local DEDUPE_WINDOW = 1.25
local ANIMATION_DURATION = 0.28
local LOOT_ALL_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
local MODERN_WINDOW_BACKDROP = {
    bgFile = WHITE_TEXTURE,
    edgeFile = WHITE_TEXTURE,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local ROUNDED_WINDOW_BACKDROP = {
    bgFile = WHITE_TEXTURE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local ROUNDED_ROW_FILL_BACKDROP = {
    bgFile = WHITE_TEXTURE,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local ROUNDED_ROW_BORDER_BACKDROP = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 9,
}

local ALERT_EVENTS = {
    "SHOW_LOOT_TOAST",
    "SHOW_LOOT_TOAST_UPGRADE",
    "SHOW_LOOT_TOAST_LEGENDARY_LOOTED",
}

local NATIVE_LOOT_EVENTS = {
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "LOOT_SLOT_CLEARED",
}

local DEFAULTS = {
    loot_window_mode = "compact",
    loot_alert_mode = "compact",
    boss_alert_mode = "compact",
    visual_style = "standard",
    background_opacity_percent = 100,
    quality_border = true,
    animation_style = "fade",
    growth_direction = "down",
    loot_scale_percent = 100,
    toast_scale_percent = 100,
    toast_duration = 5,
}

local Runtime = {
    enabled = false,
    customLootActive = false,
    previewMode = false,
    lootRows = {},
    toastRows = {},
    normalToastRows = {},
    toasts = {},
    recent = {},
    refreshGeneration = 0,
    toastGeneration = 0,
    lootSessionActive = false,
    lootFrameState = nil,
    lootRegisterHooks = setmetatable({}, { __mode = "k" }),
    alertState = nil,
    alertRegisterHooks = setmetatable({}, { __mode = "k" }),
    bossHook = nil,
}

Addon.QuietLoot = Runtime

local function setting(key)
    local state = Addon.FeatureRegistry:GetState(FEATURE_ID)
    local value = state.settings[key]
    return value == nil and DEFAULTS[key] or value
end

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function getBackgroundOpacity()
    return clamp(setting("background_opacity_percent"), 0, 100, 100) / 100
end

local function getVisualStyle()
    local style = setting("visual_style")
    if style == "clean" then return "clean" end
    if style == "round" or style == "rounded" then return "round" end
    return "standard"
end

local function useMinimalStyle()
    return getVisualStyle() == "clean"
end

local function getAnimationStyle()
    local style = setting("animation_style")
    if style == "none"
        or style == "slide_right"
        or style == "slide_up"
        or style == "pop"
    then
        return style
    end
    return "fade"
end

local function getLootRowHeight()
    return getVisualStyle() == "clean" and 34 or 40
end

local function getToastRowHeight()
    return getVisualStyle() == "clean" and 34 or 40
end

local function getModeLabel(mode)
    if mode == "hidden" then
        return Addon.L.FEATURE_VALUE_OFF or "Off"
    elseif mode == "blizzard" then
        return Addon.L.FEATURE_VALUE_BLIZZARD or "Blizzard"
    end
    return Addon.L.FEATURE_VALUE_VAULTLOOM or "Vaultloom"
end

local function getWindowModeLabel(mode)
    if mode == "blizzard" then
        return Addon.L.FEATURE_VALUE_BLIZZARD or "Blizzard"
    end
    return Addon.L.FEATURE_VALUE_VAULTLOOM or "Vaultloom"
end

local function now()
    if type(GetTimePreciseSec) == "function" then
        return tonumber(GetTimePreciseSec()) or 0
    end
    return type(GetTime) == "function" and (tonumber(GetTime()) or 0) or 0
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then return false end
    return pcall(callback, ...)
end

local function setShown(frame, shown)
    if not frame then return end
    if type(frame.SetShown) == "function" then
        frame:SetShown(shown == true)
    elseif shown and type(frame.Show) == "function" then
        frame:Show()
    elseif not shown and type(frame.Hide) == "function" then
        frame:Hide()
    end
end

local function resolveLinkName(link)
    return tostring(link or ""):match("|h%[([^]]+)%]|h")
        or tostring(link or ""):match("%[([^]]+)%]")
end

local function getQualityColor(quality)
    quality = math.max(0, math.floor(tonumber(quality) or 1))
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1
    end
    if type(GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(GetItemQualityColor, quality)
        if ok then return r or 1, g or 1, b or 1 end
    end
    return 0.92, 0.76, 0.24
end

local function getItemInfo(linkOrID)
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(getter) ~= "function" then return nil end
    local ok, name, link, quality, itemLevel, minimumLevel, itemType,
        itemSubType, stackCount, equipLocation, icon = pcall(getter, linkOrID)
    if not ok then return nil end
    return {
        name = name,
        link = link,
        quality = quality,
        icon = icon,
    }
end

local function getItemInstant(linkOrID)
    local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(getter) ~= "function" then return nil end
    local ok, itemID, _, _, _, icon = pcall(getter, linkOrID)
    if not ok then return nil end
    return itemID, icon
end

local function getCurrencyInfo(currencyID)
    if not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then
        return nil
    end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    return ok and type(info) == "table" and info or nil
end

local function isValidIcon(icon)
    if type(icon) == "number" then return icon > 0 end
    return type(icon) == "string"
        and icon ~= ""
        and not icon:match("^INVTYPE_")
end

local function resolveItemIcon(icon, linkOrID, itemID)
    if isValidIcon(icon) then return icon end

    local lookup = linkOrID or itemID
    if C_Item and type(C_Item.GetItemIconByID) == "function" and lookup then
        local ok, result = pcall(C_Item.GetItemIconByID, lookup)
        if ok and isValidIcon(result) then return result end
    end
    if type(GetItemIcon) == "function" and lookup then
        local ok, result = pcall(GetItemIcon, lookup)
        if ok and isValidIcon(result) then return result end
    end

    return 134400
end

local function resolveCurrencyIcon(icon)
    return isValidIcon(icon) and icon or 463447
end

local function getPositionStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.quietLoot = type(db.features.quietLoot) == "table"
        and db.features.quietLoot or {}
    local store = db.features.quietLoot
    store.lootWindow = type(store.lootWindow) == "table" and store.lootWindow or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 40,
    }
    store.toast = type(store.toast) == "table" and store.toast or {
        point = "TOP",
        relativePoint = "TOP",
        x = 0,
        y = -185,
    }
    return store
end

local function applyPosition(frame, record, defaultPoint, defaultX, defaultY)
    if not frame then return end
    record = type(record) == "table" and record or {}
    local point = type(record.point) == "string" and record.point or defaultPoint
    local relativePoint = type(record.relativePoint) == "string"
        and record.relativePoint or defaultPoint
    frame:ClearAllPoints()
    frame:SetPoint(
        point,
        UIParent,
        relativePoint,
        tonumber(record.x) or defaultX,
        tonumber(record.y) or defaultY
    )
end

local function savePosition(frame, record, defaultPoint)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    record.point = type(point) == "string" and point or defaultPoint
    record.relativePoint = type(relativePoint) == "string" and relativePoint or record.point
    record.x = tonumber(x) or 0
    record.y = tonumber(y) or 0
end

function Runtime:BuildItemData(linkOrID, quantity)
    local link = type(linkOrID) == "string" and linkOrID or nil
    local itemID = Addon.QuietLootLogic:GetItemID(linkOrID)
    local info = getItemInfo(linkOrID)
    local instantID, instantIcon = getItemInstant(linkOrID)
    itemID = itemID or instantID
    link = (info and info.link) or link
    return {
        kind = "item",
        itemID = itemID,
        link = link,
        name = (info and info.name) or resolveLinkName(link) or ("Item " .. tostring(itemID or "")),
        icon = resolveItemIcon((info and info.icon) or instantIcon, link or linkOrID, itemID),
        quality = (info and info.quality) or 1,
        quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
    }
end

function Runtime:BuildCurrencyData(linkOrID, quantity)
    local link = type(linkOrID) == "string" and linkOrID or nil
    local currencyID = Addon.QuietLootLogic:GetCurrencyID(linkOrID)
    local info = currencyID and getCurrencyInfo(currencyID) or nil
    return {
        kind = "currency",
        currencyID = currencyID,
        link = link,
        name = (info and info.name) or resolveLinkName(link)
            or (Addon.L.QUIET_LOOT_PREVIEW_CURRENCY or "Currency"),
        icon = resolveCurrencyIcon(info and (info.iconFileID or info.icon)),
        quality = (info and info.quality) or 1,
        quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
    }
end

function Runtime:BuildLootSlotData(slotIndex)
    if type(GetLootSlotInfo) ~= "function" then return nil end
    local ok, texture, itemName, quantity, currencyID, quality, locked, isQuestItem, questID =
        pcall(GetLootSlotInfo, slotIndex)
    if not ok then return nil end

    local link
    if type(GetLootSlotLink) == "function" then
        local linkOK, result = pcall(GetLootSlotLink, slotIndex)
        if linkOK then link = result end
    end

    local slotType
    if type(GetLootSlotType) == "function" then
        local typeOK, result = pcall(GetLootSlotType, slotIndex)
        if typeOK then slotType = result end
    end

    local data
    if link and Addon.QuietLootLogic:GetItemID(link) then
        data = self:BuildItemData(link, quantity)
    elseif (currencyID and tonumber(currencyID) and tonumber(currencyID) > 0)
        or (link and Addon.QuietLootLogic:GetCurrencyID(link))
    then
        data = self:BuildCurrencyData(link or currencyID, quantity)
    elseif slotType == (_G.LOOT_SLOT_MONEY or 1) then
        data = {
            kind = "money",
            name = itemName or (Addon.L.QUIET_LOOT_TITLE or "Loot"),
            icon = texture or 133784,
            quality = 1,
            quantity = 1,
        }
    else
        data = {
            kind = isQuestItem and "quest" or "item",
            link = link,
            name = itemName or resolveLinkName(link) or (Addon.L.QUIET_LOOT_TITLE or "Loot"),
            icon = texture or 134400,
            quality = quality or 1,
            quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
            questID = questID,
        }
    end
    data.slotIndex = slotIndex
    data.locked = locked == true
    data.questID = data.questID or questID
    if isValidIcon(texture) then data.icon = texture end
    if itemName and itemName ~= "" then data.name = itemName end
    if quality ~= nil then data.quality = quality end
    return data
end

function Runtime:CollectLoot()
    local result = {}
    if type(GetNumLootItems) ~= "function" then return result end
    local ok, count = pcall(GetNumLootItems)
    if not ok then return result end
    for slotIndex = 1, math.max(0, math.floor(tonumber(count) or 0)) do
        local data = self:BuildLootSlotData(slotIndex)
        if data then result[#result + 1] = data end
    end
    return result
end

function Runtime:GetPreviewLoot()
    return {
        {
            kind = "item",
            itemID = 19019,
            link = "|cffff8000|Hitem:19019|h[Thunderfury]|h|r",
            name = Addon.L.QUIET_LOOT_PREVIEW_ITEM or "Gilded Adventurer's Cache",
            icon = 134344,
            quality = 4,
            quantity = 1,
        },
        {
            kind = "currency",
            currencyID = 2245,
            name = Addon.L.QUIET_LOOT_PREVIEW_CURRENCY or "Warband Token",
            icon = 463447,
            quality = 2,
            quantity = 12,
        },
    }
end

function Runtime:ShowTooltip(row)
    local data = row and row.data
    if not data or not GameTooltip then return end
    if type(GameTooltip.SetOwner) == "function" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    end
    if data.link and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(data.link)
    elseif data.currencyID and type(GameTooltip.SetCurrencyByID) == "function" then
        GameTooltip:SetCurrencyByID(data.currencyID)
    else
        if type(GameTooltip.SetText) == "function" then GameTooltip:SetText(data.name or "") end
    end
    if data.locked and type(GameTooltip.AddLine) == "function" then
        GameTooltip:AddLine(Addon.L.QUIET_LOOT_LOCKED or "Not lootable yet", 1, 0.25, 0.2)
    end
    if type(GameTooltip.Show) == "function" then GameTooltip:Show() end
end

function Runtime:HideTooltip()
    if GameTooltip and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
end

local function createIconQualityBorder(row)
    local border = {}
    border.top = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border.top:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 0, 0)
    border.top:SetHeight(1)

    border.bottom = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border.bottom:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(1)

    border.left = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border.left:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(1)

    border.right = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border.right:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(1)

    return border
end

local function createRowBorder(row)
    local border = {}
    border.top = row:CreateTexture(nil, "ARTWORK", nil, 2)
    border.top:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    border.top:SetHeight(1)

    border.bottom = row:CreateTexture(nil, "ARTWORK", nil, 2)
    border.bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(1)

    border.left = row:CreateTexture(nil, "ARTWORK", nil, 2)
    border.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(1)

    border.right = row:CreateTexture(nil, "ARTWORK", nil, 2)
    border.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(1)
    return border
end

local function createRoundedRowBorder(row)
    local border = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    border:SetAllPoints(row)
    border:SetFrameLevel(row:GetFrameLevel() + 2)
    border:EnableMouse(false)
    border:SetBackdrop(ROUNDED_ROW_BORDER_BACKDROP)
    border:Hide()
    return border
end

function Runtime:ResetFrameAnimation(frame)
    if not frame then return end
    local group = frame.lootActiveAnimation
    frame.lootActiveAnimation = nil
    frame.lootAnimationDirection = nil
    frame.lootAnimationEntry = nil
    frame.lootAnimationHideOnFinish = nil
    if group and type(group.Stop) == "function" then
        pcall(group.Stop, group)
    end
    if type(frame.SetAlpha) == "function" then frame:SetAlpha(1) end
end

function Runtime:GetAnimationGroup(frame, style)
    if not frame or style == "none" or type(frame.CreateAnimationGroup) ~= "function" then
        return nil
    end
    frame.lootAnimationGroups = type(frame.lootAnimationGroups) == "table"
        and frame.lootAnimationGroups or {}
    if frame.lootAnimationGroups[style] then
        return frame.lootAnimationGroups[style]
    end

    local group = frame:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetOrder(1)
    alpha:SetDuration(ANIMATION_DURATION)
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)

    if style == "slide_right" or style == "slide_up" then
        local translation = group:CreateAnimation("Translation")
        translation:SetOrder(1)
        translation:SetDuration(ANIMATION_DURATION)
        translation:SetOffset(style == "slide_right" and 36 or 0, style == "slide_up" and 22 or 0)
    elseif style == "pop" then
        local scale = group:CreateAnimation("Scale")
        scale:SetOrder(1)
        scale:SetDuration(ANIMATION_DURATION)
        scale:SetOrigin("CENTER", 0, 0)
        scale:SetScaleFrom(1, 1)
        scale:SetScaleTo(0.88, 0.88)
    end

    group:SetScript("OnFinished", function()
        if frame.lootActiveAnimation ~= group then return end
        local direction = frame.lootAnimationDirection
        local entry = frame.lootAnimationEntry
        local hideOnFinish = frame.lootAnimationHideOnFinish == true
        frame.lootActiveAnimation = nil
        frame.lootAnimationDirection = nil
        frame.lootAnimationEntry = nil
        frame.lootAnimationHideOnFinish = nil
        if direction == "out" and entry then
            Runtime:ExpireToast(entry)
        elseif direction == "out" and hideOnFinish then
            frame:Hide()
            frame:SetAlpha(1)
        else
            frame:SetAlpha(1)
        end
    end)
    frame.lootAnimationGroups[style] = group
    return group
end

function Runtime:PlayFrameAnimation(frame, direction, entry, windowOnly)
    if not frame then return false end
    self:ResetFrameAnimation(frame)
    local configuredStyle = getAnimationStyle()
    if configuredStyle == "none" then return false end
    local style = windowOnly and "fade" or configuredStyle
    local group = self:GetAnimationGroup(frame, style)
    if not group or type(group.Play) ~= "function" then return false end

    frame.lootActiveAnimation = group
    frame.lootAnimationDirection = direction
    frame.lootAnimationEntry = entry
    frame.lootAnimationHideOnFinish = windowOnly and direction == "out"
    frame.lastLootAnimationStyle = configuredStyle
    local ok = pcall(group.Play, group, direction == "in")
    if not ok then
        self:ResetFrameAnimation(frame)
        return false
    end
    return true
end

function Runtime:ExpireToast(entry)
    for index = #self.toasts, 1, -1 do
        if self.toasts[index] == entry then
            table.remove(self.toasts, index)
            self:RefreshToasts()
            return true
        end
    end
    return false
end

function Runtime:PlayToastExit(entry)
    if type(entry) ~= "table" or self.previewMode or getAnimationStyle() == "none" then
        return false
    end
    local active = false
    for _, current in ipairs(self.toasts) do
        if current == entry then
            active = true
            break
        end
    end
    if not active then return false end
    for _, rows in ipairs({ self.normalToastRows, self.toastRows }) do
        for _, row in ipairs(rows) do
            if row.entry == entry and row:IsShown() then
                entry.animationExiting = true
                return self:PlayFrameAnimation(row, "out", entry, false)
            end
        end
    end
    return false
end

function Runtime:ResetToastAnimations(replay)
    for _, rows in ipairs({ self.normalToastRows, self.toastRows }) do
        for _, row in ipairs(rows) do
            self:ResetFrameAnimation(row)
            row.entry = nil
        end
    end
    if replay then
        for _, entry in ipairs(self.toasts) do
            entry.animationEntered = nil
            entry.animationExiting = nil
        end
    end
end

function Runtime:ApplyRowStyle(row, data, isToast)
    if not row then return end
    local style = getVisualStyle()
    local r, g, b = getQualityColor(data and data.quality)
    local backgroundOpacity = getBackgroundOpacity()
    local rounded = style == "round"
    local backgroundR = 0.020 + (r * 0.025)
    local backgroundG = 0.021 + (g * 0.025)
    local backgroundB = 0.024 + (b * 0.025)
    local backgroundA = (isToast and 0.94 or 0.90) * backgroundOpacity
    if type(row.SetBackdrop) == "function" then
        row:SetBackdrop(rounded and ROUNDED_ROW_FILL_BACKDROP or nil)
    end
    row.bg:SetTexture(WHITE_TEXTURE)
    row.bg:SetVertexColor(1, 1, 1, 1)
    if style == "clean" then
        row.bg:SetColorTexture(0.015, 0.018, 0.022, 0)
        row.bg:SetAlpha(1)
    elseif rounded then
        row.bg:SetColorTexture(backgroundR, backgroundG, backgroundB, 0)
        row.bg:SetAlpha(1)
        if type(row.SetBackdropColor) == "function" then
            row:SetBackdropColor(backgroundR, backgroundG, backgroundB, backgroundA)
        end
    else
        row.bg:SetColorTexture(backgroundR, backgroundG, backgroundB, backgroundA)
        row.bg:SetAlpha(1)
    end
    local borderR, borderG, borderB, borderA = r, g, b, 0.92
    for _, edge in pairs(row.rowBorder or {}) do
        edge:SetColorTexture(borderR, borderG, borderB, borderA)
        edge:SetShown(style ~= "clean" and not rounded)
    end
    if row.roundedBorder then
        row.roundedBorder:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
        row.roundedBorder:SetShown(rounded)
    end
    for _, edge in pairs(row.iconQualityBorder or {}) do
        edge:SetColorTexture(r, g, b, 1)
        edge:SetShown(setting("quality_border") == true)
    end
    if row.topLine then
        row.topLine:Hide()
    end
    if row.bottomLine then
        row.bottomLine:Hide()
    end
end

function Runtime:CreateLootRow(parent)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(38)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(0.02, 0.025, 0.03, 0.72)
    row.rowBorder = createRowBorder(row)
    row.roundedBorder = createRoundedRowBorder(row)

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.07)
    row.hover:Hide()

    row.topLine = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.topLine:SetPoint("TOPLEFT", 4, -3)
    row.topLine:SetPoint("TOPRIGHT", -4, -3)
    row.topLine:SetHeight(1)
    row.topLine:Hide()

    row.bottomLine = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.bottomLine:SetPoint("BOTTOMLEFT", 4, 3)
    row.bottomLine:SetPoint("BOTTOMRIGHT", -4, 3)
    row.bottomLine:SetHeight(1)
    row.bottomLine:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    row.iconQualityBorder = createIconQualityBorder(row)

    row.name = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -3)
    row.name:SetPoint("TOPRIGHT", -42, -3)
    row.name:SetMaxLines(1)

    row.detail = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 3)
    row.detail:SetPoint("BOTTOMRIGHT", -42, 3)
    row.detail:SetMaxLines(1)

    row.quantity = Addon.Widgets:CreateLabel(row, "GameFontNormal", "RIGHT")
    row.quantity:SetPoint("RIGHT", -9, 0)
    row.quantity:SetWidth(34)

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        Runtime:ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        Runtime:HideTooltip()
    end)
    row:SetScript("OnClick", function(self)
        if Runtime.previewMode or not Runtime.customLootActive then return end
        Runtime:TakeLootSlot(self.data)
    end)
    return row
end

function Runtime:SetLootRow(row, data, index)
    local style = getVisualStyle()
    local minimal = style == "clean"
    local rowHeight = getLootRowHeight()
    row.data = data
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.lootWindow.child, "TOPLEFT", 0, -((index - 1) * rowHeight))
    row:SetPoint("TOPRIGHT", self.lootWindow.child, "TOPRIGHT", 0, -((index - 1) * rowHeight))
    local rowVisualHeight = minimal and 30 or 36
    row:SetHeight(rowVisualHeight)
    row.icon:ClearAllPoints()
    local iconSize = minimal and 28 or rowVisualHeight
    local iconOffset = 0
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", row, "LEFT", iconOffset, 0)
    row.bg:ClearAllPoints()
    row.bg:SetAllPoints(row)
    row.name:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.quantity:ClearAllPoints()
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.detail:Hide()
    row.quantity:SetPoint("RIGHT", minimal and 0 or -9, 0)
    local icon = data.kind == "currency"
        and resolveCurrencyIcon(data.icon)
        or resolveItemIcon(data.icon, data.link, data.itemID)
    data.icon = icon
    row.icon:SetTexture(icon)
    row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    row.icon:SetVertexColor(1, 1, 1, 1)
    row.icon:SetBlendMode("BLEND")
    row.icon:Show()
    row.name:SetText(data.name or Addon.L.QUIET_LOOT_TITLE or "Loot")
    local detail = data.locked and (Addon.L.QUIET_LOOT_LOCKED or "Not lootable yet")
        or data.kind == "currency" and (Addon.L.QUIET_LOOT_TYPE_CURRENCY or "Currency")
        or data.kind == "money" and (Addon.L.QUIET_LOOT_TYPE_MONEY or "Money")
        or data.kind == "quest" and (Addon.L.QUIET_LOOT_TYPE_QUEST or "Quest")
        or ""
    row.detail:SetText(detail)
    row.quantity:SetText((tonumber(data.quantity) or 1) > 1 and ("×" .. data.quantity) or "")
    local r, g, b = getQualityColor(data.quality)
    row.name:SetTextColor(r, g, b, 1)
    if data.locked then
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(0.55)
        row:Disable()
    else
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
        row:Enable()
    end
    self:ApplyRowStyle(row, data, false)
    row:Show()
end

function Runtime:ApplyLootWindowStyle()
    local frame = self.lootWindow
    if not frame then return end
    local style = getVisualStyle()
    if style == "clean" then
        if type(frame.SetBackdrop) == "function" then frame:SetBackdrop(nil) end
    elseif style == "round" and type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop(ROUNDED_WINDOW_BACKDROP)
        frame:SetBackdropColor(0.010, 0.012, 0.016, 0.94 * getBackgroundOpacity())
        if type(frame.SetBackdropBorderColor) == "function" then
            frame:SetBackdropBorderColor(0.32, 0.34, 0.40, 0.92)
        end
    elseif type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop(MODERN_WINDOW_BACKDROP)
        frame:SetBackdropColor(0.010, 0.012, 0.016, 0.94 * getBackgroundOpacity())
        if type(frame.SetBackdropBorderColor) == "function" then
            frame:SetBackdropBorderColor(0.32, 0.34, 0.40, 0.92)
        end
    end
end

function Runtime:EnsureLootWindow()
    if self.lootWindow then
        self.lootWindow:SetScale(clamp(setting("loot_scale_percent"), 70, 140, 100) / 100)
        return self.lootWindow
    end
    local frame = CreateFrame("Frame", "VaultloomQuietLootFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(350, 100)
    frame:SetScale(clamp(setting("loot_scale_percent"), 70, 140, 100) / 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(80)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local store = getPositionStore()
        savePosition(self, store.lootWindow, "CENTER")
        applyPosition(Runtime.normalToastHolder, store.lootWindow, "CENTER", 0, 40)
        if Runtime.previewMode then Runtime.previewLootMoved = true end
    end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)
    frame:SetBackdropColor(1, 1, 1, getBackgroundOpacity())

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 14, -13)
    frame.title:SetPoint("TOPRIGHT", -76, -13)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)

    frame.takeAll = Addon.Widgets:CreateButton(frame, "", 25, 25)
    frame.takeAll:SetPoint("TOPRIGHT", -42, -9)
    frame.takeAll.icon = frame.takeAll:CreateTexture(nil, "ARTWORK")
    frame.takeAll.icon:SetSize(17, 17)
    frame.takeAll.icon:SetPoint("CENTER")
    frame.takeAll.icon:SetTexture(
        Addon.Assets and Addon.Assets.vaultRewardIcon or LOOT_ALL_ICON
    )
    frame.takeAll.icon:SetTexCoord(0, 1, 0, 1)
    frame.takeAll:SetScript("OnClick", function() Runtime:TakeAllLoot() end)
    frame.takeAll:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Addon.L.QUIET_LOOT_TAKE_ALL or "Loot all")
        GameTooltip:Show()
    end)
    frame.takeAll:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 25, 25)
    frame.close:SetPoint("TOPRIGHT", -10, -9)
    frame.close:SetScript("OnClick", function()
        if Runtime.previewMode then
            Runtime:HidePreview()
        else
            Runtime:CloseLootWindow()
        end
    end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 13, -45)
    frame.scroll:SetPoint("BOTTOMRIGHT", -34, 10)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(302, 1)
    frame.scroll:SetScrollChild(frame.child)
    Addon.ScrollFrames:Style(frame.scroll, { autoHide = true })

    frame.empty = Addon.Widgets:CreateLabel(frame.child, "GameFontDisable", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 8, -15)
    frame.empty:SetPoint("TOPRIGHT", -8, -15)
    frame.empty:SetText(Addon.L.QUIET_LOOT_EMPTY or "No loot available.")

    frame.modeStatus = Addon.Widgets:CreateLabel(frame.child, "GameFontHighlight", "CENTER")
    frame.modeStatus:SetPoint("TOPLEFT", 8, -14)
    frame.modeStatus:SetPoint("TOPRIGHT", -8, -14)
    frame.modeStatus:SetWordWrap(true)
    frame.modeStatus:Hide()

    self.lootWindow = frame
    applyPosition(frame, getPositionStore().lootWindow, "CENTER", 0, 40)
    self:ApplyLootWindowStyle()
    frame:Hide()
    return frame
end

function Runtime:RefreshLootWindow(overrideData)
    local frame = self:EnsureLootWindow()
    local wasShown = frame:IsShown()
    local previewWindowMode = self.previewMode and setting("loot_window_mode") or nil
    local previewAlertMode = self.previewMode and setting("loot_alert_mode") or nil
    local previewUsesCompact = self.previewMode
        and (previewWindowMode == "compact" or previewAlertMode == "compact")
    local data = type(overrideData) == "table" and overrideData or self:CollectLoot()
    if self.previewMode and not previewUsesCompact then data = {} end
    local style = getVisualStyle()
    local minimal = style == "clean"
    local rowHeight = getLootRowHeight()
    local headerHeight = self.previewMode and 38
        or minimal and 30
        or 39
    local frameWidth = minimal and 300 or 354
    local count = #data
    local visibleRows = math.max(1, math.min(MAX_VISIBLE_LOOT_ROWS, count))
    frame:SetWidth(frameWidth)
    frame:SetHeight(headerHeight + 13 + (visibleRows * rowHeight))
    frame.child:SetWidth(frameWidth - (minimal and 22 or 48))
    frame.child:SetHeight(math.max(1, count * rowHeight))
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", minimal and 0 or 13, -headerHeight)
    frame.scroll:SetPoint("BOTTOMRIGHT", minimal and -22 or -34, 8)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", minimal and 2 or 14, self.previewMode and -11 or -13)
    frame.title:SetPoint("TOPRIGHT", -40, self.previewMode and -11 or -13)
    frame.title:SetText(self.previewMode
        and (Addon.L.QUIET_LOOT_NORMAL or "Normal loot")
        or (Addon.L.QUIET_LOOT_TITLE or "Loot"))
    frame.title:SetShown(not minimal or self.previewMode)
    frame.takeAll:SetShown(not self.previewMode and count > 0)
    frame.close:SetShown(not minimal or not self.previewMode)
    frame.empty:SetShown(count == 0 and not self.previewMode)
    frame.modeStatus:SetShown(self.previewMode and not previewUsesCompact)
    if self.previewMode and not previewUsesCompact then
        frame.modeStatus:SetText(string.format(
            "%s: %s\n%s: %s",
            Addon.L.QUIET_LOOT_WINDOW_SHORT or "Loot window",
            getWindowModeLabel(previewWindowMode),
            Addon.L.QUIET_LOOT_ALERTS_SHORT or "Loot alerts",
            getModeLabel(previewAlertMode)
        ))
    end

    for index, entry in ipairs(data) do
        local row = self.lootRows[index]
        if not row then
            row = self:CreateLootRow(frame.child)
            self.lootRows[index] = row
        end
        self:SetLootRow(row, entry, index)
    end
    for index = count + 1, #self.lootRows do
        self.lootRows[index]:Hide()
    end
    Addon.ScrollFrames:Refresh(frame.scroll, true)
    frame:Show()
    if not wasShown then self:PlayFrameAnimation(frame, "in", nil, true) end
end

function Runtime:ScanGatheringLoot()
    local gathering = Addon.GatheringNodes
    if gathering and type(gathering.ScanLootWindow) == "function" then
        pcall(gathering.ScanLootWindow, gathering)
    end
end

function Runtime:TakeLootSlot(data)
    if type(data) ~= "table" or data.locked or not data.slotIndex then return false end
    if type(LootSlot) ~= "function" then return false end
    self:ScanGatheringLoot()
    Addon.QuietLootLogic:ShouldSuppress(self.recent, data, "manual-loot", now(), DEDUPE_WINDOW)
    local ok = pcall(LootSlot, data.slotIndex)
    if ok then self:RequestLootRefresh(0) end
    return ok
end

function Runtime:TakeAllLoot()
    if self.previewMode or not self.customLootActive or type(LootSlot) ~= "function" then
        return false
    end
    self:ScanGatheringLoot()
    local entries = self:CollectLoot()
    for index = #entries, 1, -1 do
        local data = entries[index]
        if not data.locked and data.slotIndex then
            Addon.QuietLootLogic:ShouldSuppress(
                self.recent,
                data,
                "manual-loot",
                now(),
                DEDUPE_WINDOW
            )
            pcall(LootSlot, data.slotIndex)
        end
    end
    self:RequestLootRefresh(0)
    return true
end

function Runtime:CloseLootWindow()
    self.customLootActive = false
    if self.lootWindow
        and not self:PlayFrameAnimation(self.lootWindow, "out", nil, true)
    then
        self.lootWindow:Hide()
    end
    if type(CloseLoot) == "function" then pcall(CloseLoot) end
end

function Runtime:RequestLootRefresh(delay)
    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local callback = function()
        if generation ~= Runtime.refreshGeneration or not Runtime.enabled then return end
        if Runtime.customLootActive then Runtime:RefreshLootWindow() end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or 0, callback)
    else
        callback()
    end
end

function Runtime:CreateToastRow(parent)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetSize(320, 36)
    row:EnableMouse(false)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(0.015, 0.018, 0.022, 0.68)
    row.rowBorder = createRowBorder(row)
    row.roundedBorder = createRoundedRowBorder(row)

    row.topLine = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.topLine:SetPoint("TOPLEFT", 4, -3)
    row.topLine:SetPoint("TOPRIGHT", -4, -3)
    row.topLine:SetHeight(1)
    row.topLine:Hide()

    row.bottomLine = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.bottomLine:SetPoint("BOTTOMLEFT", 4, 3)
    row.bottomLine:SetPoint("BOTTOMRIGHT", -4, 3)
    row.bottomLine:SetHeight(1)
    row.bottomLine:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    row.iconQualityBorder = createIconQualityBorder(row)

    row.name = Addon.Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("TOPRIGHT", -42, -2)
    row.name:SetMaxLines(1)

    row.source = Addon.Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
    row.source:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 3)
    row.source:SetPoint("BOTTOMRIGHT", -42, 3)
    row.source:SetMaxLines(1)

    row.quantity = Addon.Widgets:CreateLabel(row, "GameFontNormal", "RIGHT")
    row.quantity:SetPoint("RIGHT", -8, 0)
    row.quantity:SetWidth(34)
    row:SetScript("OnEnter", function(self) Runtime:ShowTooltip(self) end)
    row:SetScript("OnLeave", function() Runtime:HideTooltip() end)
    return row
end

function Runtime:EnsureToastHolder(kind)
    local isBoss = kind == "boss"
    local holderKey = isBoss and "toastHolder" or "normalToastHolder"
    if self[holderKey] then
        self[holderKey]:SetScale(clamp(setting("toast_scale_percent"), 70, 140, 100) / 100)
        return self[holderKey]
    end
    local frame = CreateFrame(
        "Frame",
        isBoss and "VaultloomBossLootToasts" or "VaultloomNormalLootToasts",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame.isBossHolder = isBoss
    frame:SetSize(330, 40)
    frame:SetScale(clamp(setting("toast_scale_percent"), 70, 140, 100) / 100)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(60)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if Runtime.previewMode then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not Runtime.previewMode then return end
        self:StopMovingOrSizing()
        local store = getPositionStore()
        local record = self.isBossHolder and store.toast or store.lootWindow
        savePosition(self, record, self.isBossHolder and "TOP" or "CENTER")
        if not self.isBossHolder then
            applyPosition(Runtime.lootWindow, record, "CENTER", 0, 40)
        end
        Runtime.previewToastMoved = true
    end)

    frame.previewTitle = Addon.Widgets:CreateLabel(frame, "GameFontNormal", "LEFT")
    frame.previewTitle:SetPoint("TOPLEFT", 12, -10)
    frame.previewTitle:SetPoint("TOPRIGHT", -12, -10)
    frame.previewTitle:SetTextColor(1, 0.82, 0.24, 1)
    frame.previewTitle:Hide()

    frame.previewStatus = Addon.Widgets:CreateLabel(frame, "GameFontDisableSmall", "LEFT")
    frame.previewStatus:SetPoint("TOPLEFT", 12, -28)
    frame.previewStatus:SetPoint("TOPRIGHT", -12, -28)
    frame.previewStatus:SetWordWrap(true)
    frame.previewStatus:Hide()
    self[holderKey] = frame
    local store = getPositionStore()
    if isBoss then
        applyPosition(frame, store.toast, "TOP", 0, -185)
    else
        applyPosition(frame, store.lootWindow, "CENTER", 0, 40)
    end
    frame:Hide()
    return frame
end

function Runtime:SetToastRow(holder, row, entry, index)
    local data = entry.data
    local style = getVisualStyle()
    local minimal = style == "clean"
    local rowHeight = getToastRowHeight()
    local previewOffset = self.previewMode and 82 or 0
    local entryChanged = row.entry ~= entry
    if entryChanged then
        self:ResetFrameAnimation(row)
        row.entry = entry
    end
    row.data = data
    row:ClearAllPoints()
    local direction = setting("growth_direction")
    if self.previewMode then
        row:SetPoint("TOP", holder, "TOP", 0, -previewOffset - ((index - 1) * rowHeight))
    elseif direction == "up" then
        row:SetPoint("BOTTOM", holder, "BOTTOM", 0, (index - 1) * rowHeight)
    else
        row:SetPoint("TOP", holder, "TOP", 0, -((index - 1) * rowHeight))
    end
    row:SetSize(
        minimal and 280 or 330,
        minimal and 30 or 36
    )
    row.icon:ClearAllPoints()
    local rowVisualHeight = minimal and 30 or 36
    local iconOffset = 0
    local iconSize = minimal and 28 or rowVisualHeight
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", row, "LEFT", iconOffset, 0)
    row.bg:ClearAllPoints()
    row.bg:SetAllPoints(row)
    row.name:ClearAllPoints()
    row.source:ClearAllPoints()
    row.quantity:ClearAllPoints()
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.source:Hide()
    row.quantity:SetPoint("RIGHT", minimal and 0 or -8, 0)
    local icon = data.kind == "currency"
        and resolveCurrencyIcon(data.icon)
        or resolveItemIcon(data.icon, data.link, data.itemID)
    data.icon = icon
    row.icon:SetTexture(icon)
    row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    row.icon:SetVertexColor(1, 1, 1, 1)
    row.icon:SetBlendMode("BLEND")
    row.icon:SetDesaturated(false)
    row.icon:SetAlpha(1)
    row.icon:Show()
    row.name:SetText(data.name or Addon.L.QUIET_LOOT_TITLE or "Loot")
    row.source:SetText(entry.isBoss
        and (Addon.L.QUIET_LOOT_BOSS or "Boss loot")
        or (Addon.L.QUIET_LOOT_TITLE or "Loot"))
    row.quantity:SetText((tonumber(data.quantity) or 1) > 1 and ("×" .. data.quantity) or "")
    local r, g, b = getQualityColor(data.quality)
    row.name:SetTextColor(r, g, b, 1)
    self:ApplyRowStyle(row, data, true)
    row:Show()
    if entryChanged and entry.animationEntered ~= true then
        entry.animationEntered = true
        self:PlayFrameAnimation(row, "in", entry, false)
    end
end

function Runtime:RefreshToastHolder(holder, entries, rows, preview)
    local style = getVisualStyle()
    local minimal = style == "clean"
    local rowHeight = getToastRowHeight()
    local count = math.min(MAX_TOAST_ROWS, #entries)
    holder:SetWidth(minimal and 300 or 350)
    holder:SetHeight(
        preview
            and (92 + (math.max(1, count) * rowHeight))
            or math.max(rowHeight, count * rowHeight)
    )
    holder.previewTitle:SetShown(preview)
    holder.previewStatus:SetShown(preview)
    if preview then
        holder.previewTitle:SetText(Addon.L.QUIET_LOOT_NOTIFICATIONS or "Notifications")
        holder.previewStatus:SetText(string.format(
            "%s: %s",
            Addon.L.QUIET_LOOT_BOSS_SHORT or "Boss rewards",
            getModeLabel(setting("boss_alert_mode"))
        ))
        if type(holder.SetBackdrop) == "function" then holder:SetBackdrop(nil) end
    elseif type(holder.SetBackdrop) == "function" then
        holder:SetBackdrop(nil)
    end
    for index = 1, count do
        local row = rows[index]
        if not row then
            row = self:CreateToastRow(holder)
            rows[index] = row
        end
        row:EnableMouse(false)
        self:SetToastRow(holder, row, entries[index], index)
    end
    for index = count + 1, #rows do
        self:ResetFrameAnimation(rows[index])
        rows[index].entry = nil
        rows[index]:Hide()
    end
    holder:EnableMouse(preview)
    holder:SetShown(count > 0 or preview)
end

function Runtime:RefreshToasts()
    local normalHolder = self:EnsureToastHolder("normal")
    local bossHolder = self:EnsureToastHolder("boss")
    local timestamp = now()
    if not self.previewMode then
        for index = #self.toasts, 1, -1 do
            if (tonumber(self.toasts[index].expiresAt) or 0) <= timestamp then
                table.remove(self.toasts, index)
            end
        end
    end

    local normalEntries = {}
    local bossEntries = {}
    for _, entry in ipairs(self.toasts) do
        local target = entry.isBoss and bossEntries or normalEntries
        if #target < MAX_TOAST_ROWS then target[#target + 1] = entry end
    end

    if self.previewMode then
        normalHolder:EnableMouse(false)
        normalHolder:Hide()
    else
        self:RefreshToastHolder(normalHolder, normalEntries, self.normalToastRows, false)
    end
    self:RefreshToastHolder(
        bossHolder,
        bossEntries,
        self.toastRows,
        self.previewMode
    )
end

function Runtime:AddToast(data, source, isBoss, preview)
    if type(data) ~= "table" then return false end
    source = tostring(source or "unknown")
    if not preview and Addon.QuietLootLogic:ShouldSuppress(
        self.recent,
        data,
        source,
        now(),
        DEDUPE_WINDOW
    ) then
        return false
    end

    local duration = clamp(setting("toast_duration"), 2, 10, 5)
    local entry = {
        data = data,
        source = source,
        isBoss = isBoss == true,
        expiresAt = preview and math.huge or (now() + duration),
    }
    table.insert(self.toasts, 1, entry)
    while #self.toasts > MAX_TOAST_ROWS do table.remove(self.toasts) end
    self:RefreshToasts()

    if not preview and C_Timer and type(C_Timer.After) == "function" then
        self.toastGeneration = self.toastGeneration + 1
        local generation = self.toastGeneration
        C_Timer.After(math.max(0, duration - ANIMATION_DURATION), function()
            if Runtime.enabled
                and generation <= Runtime.toastGeneration
                and now() >= ((entry.expiresAt or 0) - ANIMATION_DURATION - 0.05)
            then
                Runtime:PlayToastExit(entry)
            end
        end)
        C_Timer.After(duration + 0.05, function()
            if Runtime.enabled and generation <= Runtime.toastGeneration then
                Runtime:RefreshToasts()
            end
        end)
    end
    return true
end

function Runtime:FindEventLink(...)
    local itemLink
    local currencyLink
    local linkIndex
    local count = select("#", ...)
    for index = 1, count do
        local value = select(index, ...)
        if type(value) == "string" then
            itemLink = itemLink or Addon.QuietLootLogic:ExtractItemLink(value)
            currencyLink = currencyLink or Addon.QuietLootLogic:ExtractCurrencyLink(value)
            if (itemLink or currencyLink) and not linkIndex then linkIndex = index end
        end
    end
    local quantity = 1
    if linkIndex then
        for index = linkIndex + 1, math.min(count, linkIndex + 2) do
            local value = select(index, ...)
            if type(value) == "number" and value >= 1 and value < 1000000 then
                quantity = math.floor(value)
                break
            end
        end
    end
    return itemLink, currencyLink, quantity
end

function Runtime:HandleAutomaticLoot(eventName, ...)
    if setting("loot_alert_mode") ~= "compact" or self.customLootActive then return end
    local itemLink, currencyLink, quantity = self:FindEventLink(...)
    local data
    if itemLink then
        data = self:BuildItemData(itemLink, quantity)
    elseif currencyLink then
        data = self:BuildCurrencyData(currencyLink, quantity)
    end
    if data then self:AddToast(data, eventName, false) end
end

function Runtime:HandleChatLoot(eventName, message)
    if setting("loot_alert_mode") ~= "compact" or self.customLootActive then return end
    local itemLink = Addon.QuietLootLogic:ExtractItemLink(message)
    local currencyLink = Addon.QuietLootLogic:ExtractCurrencyLink(message)
    local quantity = Addon.QuietLootLogic:ExtractQuantity(message, 1)
    if itemLink then
        self:AddToast(self:BuildItemData(itemLink, quantity), eventName, false)
    elseif currencyLink then
        self:AddToast(self:BuildCurrencyData(currencyLink, quantity), eventName, false)
    end
end

function Runtime:HandleMoney(message)
    if setting("loot_alert_mode") ~= "compact" or self.customLootActive then return end
    self:AddToast({
        kind = "money",
        name = tostring(message or Addon.L.QUIET_LOOT_TITLE or "Loot"),
        icon = 133784,
        quality = 1,
        quantity = 1,
    }, "CHAT_MSG_MONEY", false)
end

function Runtime:HandleBossLoot(encounterID, itemID, itemLink, quantity, playerName)
    if setting("boss_alert_mode") ~= "compact" then return end
    local unitName = type(UnitName) == "function" and UnitName("player") or ""
    local fullName = unitName
    if type(UnitFullName) == "function" then
        local name, realm = UnitFullName("player")
        if name then fullName = realm and realm ~= "" and (name .. "-" .. realm) or name end
    elseif type(GetRealmName) == "function" and unitName ~= "" then
        fullName = unitName .. "-" .. tostring(GetRealmName() or "")
    end
    if not Addon.QuietLootLogic:PlayerMatches(playerName, unitName, fullName) then return end
    self:AddToast(self:BuildItemData(itemLink or itemID, quantity), "ENCOUNTER_LOOT_RECEIVED", true)
end

function Runtime:IsFrameEventRegistered(frame, eventName)
    if not frame then return false end
    if type(frame.IsEventRegistered) == "function" then
        local ok, registered = pcall(frame.IsEventRegistered, frame, eventName)
        if ok then return registered == true end
    end
    if type(frame.events) == "table" then return frame.events[eventName] == true end
    return false
end

function Runtime:RestoreAlertEvents()
    local state = self.alertState
    self.alertState = nil
    if type(state) ~= "table" or not state.frame then return end
    for eventName, wasRegistered in pairs(state.registered or {}) do
        if wasRegistered and not self:IsFrameEventRegistered(state.frame, eventName) then
            pcall(state.frame.RegisterEvent, state.frame, eventName)
        end
    end
end

function Runtime:SetAlertSuppressed(suppressed)
    local frame = _G.AlertFrame
    if not suppressed then
        self:RestoreAlertEvents()
        return
    end
    if not frame then return end
    if not self.alertRegisterHooks[frame]
        and type(hooksecurefunc) == "function"
        and type(frame.RegisterEvent) == "function"
    then
        local hooked = pcall(hooksecurefunc, frame, "RegisterEvent", function(hookedFrame, eventName)
            if not Runtime.enabled or setting("loot_alert_mode") == "blizzard" then return end
            for _, protectedEvent in ipairs(ALERT_EVENTS) do
                if eventName == protectedEvent
                    and Runtime:IsFrameEventRegistered(hookedFrame, eventName)
                    and type(hookedFrame.UnregisterEvent) == "function"
                then
                    pcall(hookedFrame.UnregisterEvent, hookedFrame, eventName)
                    return
                end
            end
        end)
        if hooked then self.alertRegisterHooks[frame] = true end
    end
    if self.alertState and self.alertState.frame ~= frame then self:RestoreAlertEvents() end
    local state = self.alertState
    if not state then
        state = { frame = frame, registered = {} }
        self.alertState = state
    end
    for _, eventName in ipairs(ALERT_EVENTS) do
        local registered = self:IsFrameEventRegistered(frame, eventName)
        if registered then state.registered[eventName] = true end
        if registered and type(frame.UnregisterEvent) == "function" then
            pcall(frame.UnregisterEvent, frame, eventName)
        end
    end
end

function Runtime:RestoreBossBanner()
    local hook = self.bossHook
    self.bossHook = nil
    if type(hook) ~= "table" or not hook.frame then return end
    local current = type(hook.frame.GetScript) == "function"
        and hook.frame:GetScript("OnEvent") or nil
    if current == hook.wrapper and type(hook.frame.SetScript) == "function" then
        hook.frame:SetScript("OnEvent", hook.original)
    end
end

function Runtime:InstallBossBanner()
    if setting("boss_alert_mode") == "blizzard" then
        self:RestoreBossBanner()
        return
    end
    local frame = _G.BossBanner
    if not frame or type(frame.SetScript) ~= "function" or type(frame.GetScript) ~= "function" then
        return
    end
    if self.bossHook and self.bossHook.frame == frame then return end
    if self.bossHook then self:RestoreBossBanner() end

    local hook = {
        frame = frame,
        original = frame:GetScript("OnEvent"),
    }
    hook.wrapper = function(selfFrame, eventName, ...)
        if Runtime.enabled
            and eventName == "ENCOUNTER_LOOT_RECEIVED"
            and setting("boss_alert_mode") ~= "blizzard"
        then
            return
        end
        if type(hook.original) == "function" then
            return hook.original(selfFrame, eventName, ...)
        end
    end
    frame:SetScript("OnEvent", hook.wrapper)
    self.bossHook = hook
end

function Runtime:RestoreNativeLootEvents()
    local state = self.lootFrameState
    self.lootFrameState = nil
    if type(state) ~= "table" or not state.frame then return end
    for eventName, wasRegistered in pairs(state.registered or {}) do
        if wasRegistered and not self:IsFrameEventRegistered(state.frame, eventName) then
            pcall(state.frame.RegisterEvent, state.frame, eventName)
        end
    end
end

function Runtime:SetNativeLootSuppressed(suppressed)
    local frame = _G.LootFrame
    if not suppressed then
        self:RestoreNativeLootEvents()
        return
    end
    if not frame then return end

    if not self.lootRegisterHooks[frame]
        and type(hooksecurefunc) == "function"
        and type(frame.RegisterEvent) == "function"
    then
        local hooked = pcall(hooksecurefunc, frame, "RegisterEvent", function(hookedFrame, eventName)
            if not Runtime.enabled or setting("loot_window_mode") ~= "compact" then return end
            for _, protectedEvent in ipairs(NATIVE_LOOT_EVENTS) do
                if eventName == protectedEvent
                    and Runtime:IsFrameEventRegistered(hookedFrame, eventName)
                    and type(hookedFrame.UnregisterEvent) == "function"
                then
                    pcall(hookedFrame.UnregisterEvent, hookedFrame, eventName)
                    return
                end
            end
        end)
        if hooked then self.lootRegisterHooks[frame] = true end
    end

    if self.lootFrameState and self.lootFrameState.frame ~= frame then
        self:RestoreNativeLootEvents()
    end
    local state = self.lootFrameState
    if not state then
        state = { frame = frame, registered = {} }
        self.lootFrameState = state
    end
    for _, eventName in ipairs(NATIVE_LOOT_EVENTS) do
        local registered = self:IsFrameEventRegistered(frame, eventName)
        if registered then state.registered[eventName] = true end
        if registered and type(frame.UnregisterEvent) == "function" then
            pcall(frame.UnregisterEvent, frame, eventName)
        end
    end
end

function Runtime:ShowNativeLootIfNeeded()
    local frame = _G.LootFrame
    if not frame or type(frame.Show) ~= "function" or type(GetNumLootItems) ~= "function" then return end
    local ok, count = pcall(GetNumLootItems)
    if not ok or (tonumber(count) or 0) <= 0 then return end
    if type(frame.Open) == "function" then
        pcall(frame.Open, frame)
    elseif type(_G.LootFrame_Show) == "function" then
        pcall(_G.LootFrame_Show, frame)
    else
        frame:Show()
    end
end

function Runtime:ApplyModes()
    if not self.enabled then return end
    local windowMode = setting("loot_window_mode")
    local alertMode = setting("loot_alert_mode")
    self:SetAlertSuppressed(alertMode ~= "blizzard")
    self:SetNativeLootSuppressed(windowMode == "compact")
    if windowMode ~= "compact" then
        if self.customLootActive then
            self.customLootActive = false
            if self.lootWindow and not self.previewMode then
                self:ResetFrameAnimation(self.lootWindow)
                self.lootWindow:Hide()
            end
        end
        if self.lootSessionActive then self:ShowNativeLootIfNeeded() end
    end

    if setting("boss_alert_mode") == "blizzard" then
        self:RestoreBossBanner()
    else
        self:InstallBossBanner()
    end
end

function Runtime:ApplyVisualSettings()
    if self.lootWindow then
        local minimal = useMinimalStyle()
        self.lootWindow:SetScale(clamp(setting("loot_scale_percent"), 70, 140, 100) / 100)
        self:ApplyLootWindowStyle()
        self.lootWindow.takeAll:ClearAllPoints()
        self.lootWindow.close:ClearAllPoints()
        if minimal then
            self.lootWindow.takeAll:SetPoint("TOPRIGHT", -30, -2)
            self.lootWindow.close:SetPoint("TOPRIGHT", 0, -2)
        else
            self.lootWindow.takeAll:SetPoint("TOPRIGHT", -42, -9)
            self.lootWindow.close:SetPoint("TOPRIGHT", -10, -9)
        end
        if self.lootWindow:IsShown() then
            self:RefreshLootWindow(self.previewMode and self:GetPreviewLoot() or nil)
        end
    end
    if self.toastHolder or self.normalToastHolder then
        if self.normalToastHolder then
            self.normalToastHolder:SetScale(clamp(setting("toast_scale_percent"), 70, 140, 100) / 100)
        end
        if self.toastHolder then
            self.toastHolder:SetScale(clamp(setting("toast_scale_percent"), 70, 140, 100) / 100)
        end
        self:RefreshToasts()
    end
end

function Runtime:OnLootOpened(autoLoot)
    self.lootSessionActive = true
    if setting("loot_window_mode") ~= "compact" or autoLoot == true then
        self.customLootActive = false
        if self.lootWindow and not self.previewMode then
            self:ResetFrameAnimation(self.lootWindow)
            self.lootWindow:Hide()
        end
        return
    end
    self.customLootActive = true
    self.previewMode = false
    self:RefreshLootWindow()
end

function Runtime:OnLootClosed()
    self.lootSessionActive = false
    self.customLootActive = false
    if self.lootWindow and not self.previewMode
        and not self:PlayFrameAnimation(self.lootWindow, "out", nil, true)
    then
        self.lootWindow:Hide()
    end
end

function Runtime:RebuildPreview()
    if not self.previewMode then return end
    local samples = self:GetPreviewLoot()
    self.toasts = {}
    self:ApplyVisualSettings()
    self:RefreshLootWindow(samples)
    if setting("loot_alert_mode") == "compact" then
        self.toasts[#self.toasts + 1] = {
            data = samples[2],
            source = "preview",
            isBoss = false,
            expiresAt = math.huge,
        }
    end
    if setting("boss_alert_mode") == "compact" then
        self.toasts[#self.toasts + 1] = {
            data = samples[1],
            source = "preview",
            isBoss = true,
            expiresAt = math.huge,
        }
    end
    self:RefreshToasts()
end

function Runtime:ShowPreview()
    self.previewMode = true
    self.customLootActive = false
    self.previewLootMoved = false
    self.previewToastMoved = false
    self:EnsureLootWindow()
    self:EnsureToastHolder("normal")
    self:EnsureToastHolder("boss")
    local store = getPositionStore()
    applyPosition(self.lootWindow, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.normalToastHolder, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.toastHolder, store.toast, "TOP", 0, -185)
    self:RebuildPreview()
end

function Runtime:HidePreview()
    self.previewMode = false
    self.toasts = {}
    self:ResetToastAnimations(false)
    if self.lootWindow then
        self:ResetFrameAnimation(self.lootWindow)
        self.lootWindow:Hide()
    end
    if self.toastHolder then
        self.toastHolder:EnableMouse(false)
        self.toastHolder:Hide()
    end
    if self.normalToastHolder then
        self.normalToastHolder:EnableMouse(false)
        self.normalToastHolder:Hide()
    end
    local store = getPositionStore()
    applyPosition(self.lootWindow, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.normalToastHolder, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.toastHolder, store.toast, "TOP", 0, -185)
end

function Runtime:TogglePreview()
    if self.previewMode then self:HidePreview() else self:ShowPreview() end
end

function Runtime:ResetLayout()
    local store = getPositionStore()
    store.lootWindow.point = "CENTER"
    store.lootWindow.relativePoint = "CENTER"
    store.lootWindow.x = 0
    store.lootWindow.y = 40
    store.toast.point = "TOP"
    store.toast.relativePoint = "TOP"
    store.toast.x = 0
    store.toast.y = -185
    applyPosition(self.lootWindow, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.normalToastHolder, store.lootWindow, "CENTER", 0, 40)
    applyPosition(self.toastHolder, store.toast, "TOP", 0, -185)
end

function Runtime:GetSettingValue(settingKey)
    if settingKey ~= "loot_window_mode"
        and settingKey ~= "loot_alert_mode"
        and settingKey ~= "boss_alert_mode"
        and settingKey ~= "visual_style"
        and settingKey ~= "background_opacity_percent"
        and settingKey ~= "quality_border"
        and settingKey ~= "animation_style"
        and settingKey ~= "growth_direction"
        and settingKey ~= "loot_scale_percent"
        and settingKey ~= "toast_scale_percent"
        and settingKey ~= "toast_duration"
    then
        return nil
    end
    local value = Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey]
    if settingKey == "visual_style" and value ~= nil then
        return getVisualStyle()
    end
    return value
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey ~= "loot_window_mode"
        and settingKey ~= "loot_alert_mode"
        and settingKey ~= "boss_alert_mode"
        and settingKey ~= "visual_style"
        and settingKey ~= "background_opacity_percent"
        and settingKey ~= "quality_border"
        and settingKey ~= "animation_style"
        and settingKey ~= "growth_direction"
        and settingKey ~= "loot_scale_percent"
        and settingKey ~= "toast_scale_percent"
        and settingKey ~= "toast_duration"
    then
        return false
    end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[settingKey] = value
    if settingKey == "loot_window_mode"
        or settingKey == "loot_alert_mode"
        or settingKey == "boss_alert_mode"
    then
        self:ApplyModes()
        self:RebuildPreview()
    else
        if settingKey == "animation_style" then
            self:ResetToastAnimations(true)
        end
        self:ApplyVisualSettings()
        if settingKey == "animation_style"
            and self.lootWindow
            and self.lootWindow:IsShown()
        then
            self:PlayFrameAnimation(self.lootWindow, "in", nil, true)
        end
    end
    return true
end

function Runtime:ResetSettingValues()
    self:ResetToastAnimations(true)
    self:ApplyVisualSettings()
end

function Runtime:OnSettingsReset()
    self:ApplyModes()
    self:ApplyVisualSettings()
    self:RebuildPreview()
end

function Runtime:OnSettingsClosed()
    if self.previewMode then self:HidePreview() end
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "loot_window_mode"
        or settingKey == "loot_alert_mode"
        or settingKey == "boss_alert_mode"
    then
        self:ApplyModes()
        self:RebuildPreview()
    end
end

function Runtime:OnAction(actionKey)
    if actionKey == "preview" then
        self:TogglePreview()
        return true
    elseif actionKey == "reset_layout" then
        self:ResetLayout()
        return true
    end
    return false
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "ADDON_LOADED" or eventName == "PLAYER_ENTERING_WORLD" then
        self:ApplyModes()
        return
    elseif eventName == "LOOT_OPENED" then
        self:OnLootOpened(...)
        return
    elseif eventName == "LOOT_CLOSED" then
        self:OnLootClosed()
        return
    elseif eventName == "LOOT_READY"
        or eventName == "LOOT_SLOT_CHANGED"
        or eventName == "LOOT_SLOT_CLEARED"
        or eventName == "GET_ITEM_INFO_RECEIVED"
    then
        if self.customLootActive then self:RequestLootRefresh(0) end
        return
    elseif eventName == "CHAT_MSG_LOOT" or eventName == "CHAT_MSG_CURRENCY" then
        self:HandleChatLoot(eventName, ...)
        return
    elseif eventName == "CHAT_MSG_MONEY" then
        self:HandleMoney(...)
        return
    elseif eventName == "ENCOUNTER_LOOT_RECEIVED" then
        self:HandleBossLoot(...)
        return
    end
    self:HandleAutomaticLoot(eventName, ...)
end

function Runtime:OnEnable()
    self.enabled = true
    self.recent = {}
    self.toasts = {}
    for _, eventName in ipairs({
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "LOOT_OPENED",
        "LOOT_CLOSED",
        "LOOT_READY",
        "LOOT_SLOT_CHANGED",
        "LOOT_SLOT_CLEARED",
        "CHAT_MSG_LOOT",
        "CHAT_MSG_CURRENCY",
        "CHAT_MSG_MONEY",
        "SHOW_LOOT_TOAST",
        "SHOW_LOOT_TOAST_UPGRADE",
        "SHOW_LOOT_TOAST_LEGENDARY_LOOTED",
        "ENCOUNTER_LOOT_RECEIVED",
        "LOOT_ITEM_ROLL_WON",
        "BONUS_ROLL_RESULT",
        "GET_ITEM_INFO_RECEIVED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:ApplyVisualSettings()
    self:ApplyModes()
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self.toastGeneration = self.toastGeneration + 1
    local hadCustomLoot = self.customLootActive
    local hadLootSession = self.lootSessionActive
    self.customLootActive = false
    self.lootSessionActive = false
    self.previewMode = false
    self.toasts = {}
    self.recent = {}
    self:RestoreAlertEvents()
    self:RestoreNativeLootEvents()
    self:RestoreBossBanner()
    self:ResetToastAnimations(false)
    if self.lootWindow then
        self:ResetFrameAnimation(self.lootWindow)
        self.lootWindow:Hide()
    end
    if self.toastHolder then
        self.toastHolder:EnableMouse(false)
        self.toastHolder:Hide()
    end
    if self.normalToastHolder then
        self.normalToastHolder:EnableMouse(false)
        self.normalToastHolder:Hide()
    end
    if hadCustomLoot or hadLootSession then self:ShowNativeLootIfNeeded() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Loot Overlay runtime.")
end
