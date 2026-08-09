------------------------------------------------------
-- MajesticBeastTracker Loot UI
-- Loot Editor, Loot Summary, Loot Tooltip helpers
------------------------------------------------------

local addonName, ns = ...
local LURES = ns.LURES

local LS_COL_DROP = 70  -- Drop % column width (shared by tooltip + summary)

-- Format drop rate: % mode (capped at 100%) or /kill mode
local function FormatDropRate(pct)
    if MajesticBeastTrackerDB.settings.dropPercentFormat then
        -- Per kill format
        return string.format("%.1f/kill", pct / 100)
    else
        -- Percentage format (capped at 100%)
        return string.format("%.0f%%", math.min(pct, 100))
    end
end

-- Cached item name lookup (avoids repeated C_Item.GetItemNameByID calls)
local itemNameCache = {}
local function GetCachedItemName(id)
    if not itemNameCache[id] then
        itemNameCache[id] = C_Item.GetItemNameByID(id) or false
    end
    return itemNameCache[id] or ("Item " .. id)
end

-- Local aliases from shared ns constants (set by UI.lua)
local MEDIA_PATH, BACKDROP, C_BORDER_RGB, C_TOOLBAR_ICON, C_TOOLBAR_ICON_HOVER, CreateToolbarButton

-- Deferred init: UI.lua sets ns.* before this file's frames are used
local function InitShared()
    MEDIA_PATH = ns.MEDIA_PATH
    BACKDROP = ns.BACKDROP
    C_BORDER_RGB = ns.C_BORDER_RGB
    C_TOOLBAR_ICON = ns.C_TOOLBAR_ICON
    C_TOOLBAR_ICON_HOVER = ns.C_TOOLBAR_ICON_HOVER
    CreateToolbarButton = ns.CreateToolbarButton
end
-- Call immediately since UI.lua loads before us
InitShared()

-- Block 1: Loot tooltip helpers
-- Helper: get TSM min buyout price for an item (returns copper or nil)
function ns.GetTSMPrice(itemID)
    if not TSM_API then return nil end
    local ok, price = pcall(TSM_API.GetCustomPriceValue, "DBMinBuyout", "i:" .. itemID)
    if ok and price and price > 0 then return price end
    return nil
end

-- Helper: get AH unit price from any available source: TSM, then Auctionator scan data
function ns.GetAHPrice(itemID)
    local price = ns.GetTSMPrice(itemID)
    if price then return price end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "MajesticBeastTracker", itemID)
        if ok and p and p > 0 then return p end
    end
    return nil
end

-- Helper: build loot tooltip lines from item count table
function ns.AddLootTooltipLines(lootTable, header, savedPrices)
    if not lootTable then return 0 end
    local hasAny = false
    for _, c in pairs(lootTable) do
        if c > 0 then hasAny = true; break end
    end
    if not hasAny then return 0 end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(header, 1, 0.84, 0)

    local totalValue = 0
    local hasTSM = TSM_API ~= nil
    -- List each item individually (separate quality tiers)
    local items = {}
    for id, count in pairs(lootTable) do
        if count > 0 then
            local name = GetCachedItemName(id)
            local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id) or 0
            items[#items + 1] = { id = id, name = name, quality = quality, count = count }
        end
    end
    table.sort(items, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.quality < b.quality
    end)

    for _, entry in ipairs(items) do
        local displayName = entry.name
        if entry.quality > 0 then
            displayName = displayName .. " |A:Professions-ChatIcon-Quality-12-Tier" .. entry.quality .. ":12:12::1|a"
        end
        local line = displayName .. "  x" .. entry.count
        if hasTSM then
            local price = savedPrices and savedPrices[entry.id]
            if not price then price = ns.GetTSMPrice(entry.id) end
            if price then
                local value = price * entry.count
                totalValue = totalValue + value
                line = line .. "  |cffffd700" .. ns.FormatGoldPositive(value) .. "|r"
            end
        end
        local r, g, b = 0.9, 0.9, 0.9
        local itemQuality = select(3, C_Item.GetItemInfo(entry.id))
        if itemQuality then
            local color = ITEM_QUALITY_COLORS[itemQuality]
            if color then r, g, b = color.r, color.g, color.b end
        end
        GameTooltip:AddLine(line, r, g, b)
    end

    if hasTSM and totalValue > 0 then
        GameTooltip:AddLine("Value: " .. ns.FormatGoldPositive(totalValue), 1, 0.84, 0)
    end
    return totalValue
end

-- Helper: build sorted item list from loot table
local function BuildItemList(lootTable, savedPrices)
    if not lootTable then return {}, 0 end
    local items = {}
    local totalValue = 0
    local hasTSM = TSM_API ~= nil
    for id, count in pairs(lootTable) do
        if count > 0 then
            local name = GetCachedItemName(id)
            local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id) or 0
            local displayName = name
            if quality > 0 then
                displayName = displayName .. " |A:Professions-ChatIcon-Quality-12-Tier" .. quality .. ":12:12::1|a"
            end
            local priceText = ""
            if hasTSM then
                local price = savedPrices and savedPrices[id]
                if not price then price = ns.GetTSMPrice(id) end
                if price then
                    totalValue = totalValue + price * count
                    priceText = "  |cffffd700" .. ns.FormatGoldPositive(price * count) .. "|r"
                end
            end
            local r, g, b = 0.9, 0.9, 0.9
            local itemQuality = select(3, C_Item.GetItemInfo(id))
            if itemQuality then
                local color = ITEM_QUALITY_COLORS[itemQuality]
                if color then r, g, b = color.r, color.g, color.b end
            end
            items[#items + 1] = { name = displayName, count = count, priceText = priceText, r = r, g = g, b = b, sortKey = name .. string.format("%02d", quality), itemID = id }
        end
    end
    table.sort(items, function(a, b) return a.sortKey < b.sortKey end)
    return items, totalValue
end

------------------------------------------------------
-- Loot Tooltip (custom frame, 3-column layout)
------------------------------------------------------
local LT_COL_ITEM = 130
local LT_COL_COUNT = 45
local LT_COL_VALUE = 65
local LT_COL_GAP = 4
local LT_RESET_X = 8 + LT_COL_ITEM + LT_COL_GAP
local LT_ALLTIME_X = LT_RESET_X + LT_COL_COUNT + LT_COL_VALUE + LT_COL_GAP
local LT_WIDTH = 8 + LT_COL_ITEM + LT_COL_GAP + (LT_COL_COUNT + LT_COL_VALUE) * 2 + LT_COL_GAP + 12
local LT_ROW_HEIGHT = 14

local lootTooltip = CreateFrame("Frame", "MBT_LootTooltip", UIParent, "BackdropTemplate")
lootTooltip:SetFrameStrata("TOOLTIP")
lootTooltip:SetClampedToScreen(true)
lootTooltip:SetBackdrop(ns.BACKDROP)
lootTooltip:SetBackdropColor(0, 0, 0, 0.95)
lootTooltip:SetBackdropBorderColor(unpack(ns.C_BORDER_RGB))
lootTooltip:EnableMouse(false)
lootTooltip:Hide()
lootTooltip.rows = {}

local lootTTTitle = lootTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
lootTTTitle:SetPoint("TOPLEFT", lootTooltip, "TOPLEFT", 8, -6)

local function CreateLootTooltipRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LT_ROW_HEIGHT)
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.item:SetFont(row.item:GetFont(), 9)
    row.item:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.item:SetWidth(LT_COL_ITEM)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    row.resetCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.resetCount:SetFont(row.resetCount:GetFont(), 9)
    row.resetCount:SetPoint("LEFT", row, "LEFT", LT_RESET_X, 0)
    row.resetCount:SetWidth(LT_COL_COUNT)
    row.resetCount:SetJustifyH("LEFT")
    row.resetValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.resetValue:SetFont(row.resetValue:GetFont(), 9)
    row.resetValue:SetPoint("LEFT", row, "LEFT", LT_RESET_X + LT_COL_COUNT, 0)
    row.resetValue:SetWidth(LT_COL_VALUE)
    row.resetValue:SetJustifyH("LEFT")
    row.alltimeCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.alltimeCount:SetFont(row.alltimeCount:GetFont(), 9)
    row.alltimeCount:SetPoint("LEFT", row, "LEFT", LT_ALLTIME_X, 0)
    row.alltimeCount:SetWidth(LT_COL_COUNT)
    row.alltimeCount:SetJustifyH("LEFT")
    row.alltimeValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.alltimeValue:SetFont(row.alltimeValue:GetFont(), 9)
    row.alltimeValue:SetPoint("LEFT", row, "LEFT", LT_ALLTIME_X + LT_COL_COUNT, 0)
    row.alltimeValue:SetWidth(LT_COL_VALUE)
    row.alltimeValue:SetJustifyH("LEFT")
    row.dropPercent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dropPercent:SetFont(row.dropPercent:GetFont(), 9)
    row.dropPercent:SetWidth(LS_COL_DROP)
    row.dropPercent:SetJustifyH("RIGHT")
    row.dropPercent:Hide()
    return row
end

function ns.ShowLootTooltip(anchor, title, resetTable, allTimeTable, savedPrices, trackedKills, trackedPerBeast)
    local resetItems, resetTotal = BuildItemList(resetTable, savedPrices)
    local allTimeItems, allTimeTotal = BuildItemList(allTimeTable, savedPrices)
    local hasTSM = TSM_API ~= nil

    -- Collect unique keys
    local allNames = {}
    local nameSet = {}
    for _, item in ipairs(resetItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    for _, item in ipairs(allTimeItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    table.sort(allNames)

    local resetByKey = {}
    for _, item in ipairs(resetItems) do resetByKey[item.sortKey] = item end
    local allTimeByKey = {}
    for _, item in ipairs(allTimeItems) do allTimeByKey[item.sortKey] = item end

    lootTTTitle:SetText("|cffD1B559" .. title .. "|r")

    -- Measure widest item name for dynamic column width
    local measureFS = lootTTTitle  -- reuse for measuring
    local maxNameWidth = LT_COL_ITEM  -- minimum
    for _, key in ipairs(allNames) do
        local ref = allTimeByKey[key] or resetByKey[key]
        if ref then
            measureFS:SetText(ref.name)
            local w = measureFS:GetStringWidth()
            if w and w > maxNameWidth then maxNameWidth = w end
        end
    end
    measureFS:SetText("|cffD1B559" .. title .. "|r")  -- restore title
    maxNameWidth = math.min(maxNameWidth + 8, 250)  -- cap + padding

    -- Dynamic offsets based on name width
    local dynResetX = 8 + maxNameWidth + LT_COL_GAP
    local dynAlltimeX = dynResetX + LT_COL_COUNT + LT_COL_VALUE + LT_COL_GAP
    local dynWidth = 8 + maxNameWidth + LT_COL_GAP + (LT_COL_COUNT + LT_COL_VALUE) * 2 + LT_COL_GAP + 12
    local showDropPct = MajesticBeastTrackerDB.settings.showDropPercent and trackedKills and next(trackedKills)
    local dynDropX = dynAlltimeX + LT_COL_COUNT + LT_COL_VALUE + LT_COL_GAP
    if showDropPct then dynWidth = dynWidth + LS_COL_DROP + LT_COL_GAP end
    -- Build reverse map for drop %
    local itemToBeast = {}
    if showDropPct then
        for beastName, items in pairs(ns.BEAST_LOOT) do
            for _, id in ipairs(items) do
                if not itemToBeast[id] then itemToBeast[id] = {} end
                itemToBeast[id][#itemToBeast[id] + 1] = beastName
            end
        end
    end

    local idx = 0
    local yOff = -20

    -- Header
    idx = idx + 1
    local headerRow = lootTooltip.rows[idx]
    if not headerRow or not headerRow.item then
        headerRow = CreateLootTooltipRow(lootTooltip)
        lootTooltip.rows[idx] = headerRow
    end
    headerRow:SetPoint("TOPLEFT", lootTooltip, "TOPLEFT", 0, yOff)
    headerRow:SetPoint("TOPRIGHT", lootTooltip, "TOPRIGHT", 0, yOff)
    headerRow.item:SetText("")
    headerRow.item:SetWidth(maxNameWidth)
    headerRow.resetCount:SetText("|cffffd700Reset|r")
    headerRow.resetCount:ClearAllPoints()
    headerRow.resetCount:SetPoint("LEFT", headerRow, "LEFT", dynResetX, 0)
    headerRow.resetValue:SetText("")
    headerRow.alltimeCount:SetText("|cffffd700All Time|r")
    headerRow.alltimeCount:ClearAllPoints()
    headerRow.alltimeCount:SetPoint("LEFT", headerRow, "LEFT", dynAlltimeX, 0)
    headerRow.alltimeValue:SetText("")
    if showDropPct then
        headerRow.dropPercent:ClearAllPoints()
        headerRow.dropPercent:SetPoint("LEFT", headerRow, "LEFT", dynDropX, 0)
        headerRow.dropPercent:SetText("|cffffd700Drop %|r")
        headerRow.dropPercent:Show()
    else
        headerRow.dropPercent:Hide()
    end
    headerRow:Show()
    yOff = yOff - LT_ROW_HEIGHT

    -- Item rows
    for _, key in ipairs(allNames) do
        local ri = resetByKey[key]
        local ai = allTimeByKey[key]
        local ref = ai or ri
        if ref then
            idx = idx + 1
            local row = lootTooltip.rows[idx]
            if not row or not row.item then
                row = CreateLootTooltipRow(lootTooltip)
                lootTooltip.rows[idx] = row
            end
            row:SetPoint("TOPLEFT", lootTooltip, "TOPLEFT", 0, yOff)
            row:SetPoint("TOPRIGHT", lootTooltip, "TOPRIGHT", 0, yOff)
            row.item:SetText(ref.name)
            row.item:SetTextColor(ref.r, ref.g, ref.b)
            row.item:SetWidth(maxNameWidth)
            row.resetCount:ClearAllPoints()
            row.resetCount:SetPoint("LEFT", row, "LEFT", dynResetX, 0)
            row.resetCount:SetText(ri and ("x" .. ri.count) or "|cff666666—|r")
            row.resetCount:SetTextColor(ri and 0.9 or 0.4, ri and 0.9 or 0.4, ri and 0.9 or 0.4)
            row.resetValue:ClearAllPoints()
            row.resetValue:SetPoint("LEFT", row, "LEFT", dynResetX + LT_COL_COUNT, 0)
            row.resetValue:SetText(ri and ri.priceText ~= "" and ri.priceText or "")
            row.alltimeCount:ClearAllPoints()
            row.alltimeCount:SetPoint("LEFT", row, "LEFT", dynAlltimeX, 0)
            row.alltimeCount:SetText(ai and ("x" .. ai.count) or "")
            row.alltimeCount:SetTextColor(0.9, 0.9, 0.9)
            row.alltimeValue:ClearAllPoints()
            row.alltimeValue:SetPoint("LEFT", row, "LEFT", dynAlltimeX + LT_COL_COUNT, 0)
            row.alltimeValue:SetText(ai and ai.priceText ~= "" and ai.priceText or "")
            if showDropPct and ref.itemID then
                local beasts = itemToBeast[ref.itemID]
                if beasts then
                    local totalKills, totalDrops = 0, 0
                    for _, bn in ipairs(beasts) do
                        totalKills = totalKills + (trackedKills[bn] or 0)
                        if trackedPerBeast and trackedPerBeast[bn] then
                            totalDrops = totalDrops + (trackedPerBeast[bn][ref.itemID] or 0)
                        end
                    end
                    row.dropPercent:ClearAllPoints()
                    row.dropPercent:SetPoint("LEFT", row, "LEFT", dynDropX, 0)
                    if totalKills > 0 then
                        local pct = (totalDrops / totalKills) * 100
                        row.dropPercent:SetText(FormatDropRate(pct))
                        row.dropPercent:SetTextColor(0.7, 0.9, 1)
                    else
                        row.dropPercent:SetText("-")
                        row.dropPercent:SetTextColor(0.4, 0.4, 0.4)
                    end
                    row.dropPercent:Show()
                else
                    row.dropPercent:Hide()
                end
            else
                row.dropPercent:Hide()
            end
            row:Show()
            yOff = yOff - LT_ROW_HEIGHT
        end
    end

    -- Value total
    if hasTSM and (resetTotal > 0 or allTimeTotal > 0) then
        idx = idx + 1
        local totalRow = lootTooltip.rows[idx]
        if not totalRow or not totalRow.item then
            totalRow = CreateLootTooltipRow(lootTooltip)
            lootTooltip.rows[idx] = totalRow
        end
        totalRow:SetPoint("TOPLEFT", lootTooltip, "TOPLEFT", 0, yOff)
        totalRow:SetPoint("TOPRIGHT", lootTooltip, "TOPRIGHT", 0, yOff)
        totalRow.item:SetText("|cffffd700Value:|r")
        totalRow.item:SetWidth(maxNameWidth)
        totalRow.resetCount:ClearAllPoints()
        totalRow.resetCount:SetPoint("LEFT", totalRow, "LEFT", dynResetX, 0)
        totalRow.resetCount:SetText("")
        totalRow.resetValue:ClearAllPoints()
        totalRow.resetValue:SetPoint("LEFT", totalRow, "LEFT", dynResetX + LT_COL_COUNT, 0)
        totalRow.resetValue:SetText(resetTotal > 0 and ("|cffffd700" .. ns.FormatGoldPositive(resetTotal) .. "|r") or "")
        totalRow.alltimeCount:ClearAllPoints()
        totalRow.alltimeCount:SetPoint("LEFT", totalRow, "LEFT", dynAlltimeX, 0)
        totalRow.alltimeCount:SetText("")
        totalRow.alltimeValue:ClearAllPoints()
        totalRow.alltimeValue:SetPoint("LEFT", totalRow, "LEFT", dynAlltimeX + LT_COL_COUNT, 0)
        totalRow.alltimeValue:SetText(allTimeTotal > 0 and ("|cffffd700" .. ns.FormatGoldPositive(allTimeTotal) .. "|r") or "")
        totalRow:Show()
        yOff = yOff - LT_ROW_HEIGHT
    end

    -- Footer
    idx = idx + 1
    local footerRow = lootTooltip.rows[idx]
    if not footerRow or not footerRow.item then
        footerRow = CreateLootTooltipRow(lootTooltip)
        lootTooltip.rows[idx] = footerRow
    end
    footerRow:SetPoint("TOPLEFT", lootTooltip, "TOPLEFT", 0, yOff - 2)
    footerRow:SetPoint("TOPRIGHT", lootTooltip, "TOPRIGHT", 0, yOff - 2)
    footerRow.item:SetText("|cff888888Click to edit loot|r")
    footerRow.item:SetTextColor(0.5, 0.5, 0.5)
    footerRow.resetCount:SetText("")
    footerRow.resetValue:SetText("")
    footerRow.alltimeCount:SetText("")
    footerRow.alltimeValue:SetText("")
    footerRow:Show()
    yOff = yOff - LT_ROW_HEIGHT - 2

    -- Hide unused rows
    for i = idx + 1, #lootTooltip.rows do
        lootTooltip.rows[i]:Hide()
    end

    lootTooltip:SetSize(dynWidth, math.abs(yOff) + 6)
    lootTooltip:ClearAllPoints()
    -- Position near anchor but ensure visibility above everything
    lootTooltip:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", 4, 0)
    lootTooltip:SetFrameLevel(100)
    lootTooltip:Show()
end

function ns.HideLootTooltip()
    lootTooltip:Hide()
end

-- Legacy tooltip function (used by global goblin hover)
-- Reusable component: format a single loot column (item + count + value)
local function FormatLootEntry(item)
    if not item then return "|cff666666—|r" end
    local text = "x" .. item.count
    if item.priceText ~= "" then text = text .. " " .. item.priceText end
    return text
end

-- Reusable component: add a loot column to tooltip
-- lootTable = { [itemID] = count }, header = "Reset" or "All Time"
local function AddLootColumnToTooltip(items, total, header, isLeft)
    -- Returns formatted lines for this column
    local lines = {}
    for _, item in ipairs(items) do
        lines[item.sortKey] = FormatLootEntry(item)
    end
    return lines, total
end

function ns.AddLootTooltipColumns(resetTable, allTimeTable, savedPrices, perBeast, perBeastReset)
    local resetItems, resetTotal = BuildItemList(resetTable, savedPrices)
    local allTimeItems, allTimeTotal = BuildItemList(allTimeTable, savedPrices)
    local hasTSM = TSM_API ~= nil

    -- Collect all unique item keys
    local allNames = {}
    local nameSet = {}
    for _, item in ipairs(resetItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    for _, item in ipairs(allTimeItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    table.sort(allNames)

    -- Build lookup by sortKey
    local resetByKey = {}
    for _, item in ipairs(resetItems) do resetByKey[item.sortKey] = item end
    local allTimeByKey = {}
    for _, item in ipairs(allTimeItems) do allTimeByKey[item.sortKey] = item end

    -- Header
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("|cffffd700Reset|r", "|cffffd700All Time|r", 1, 0.84, 0, 1, 0.84, 0)

    -- Rows: left = item name + reset entry, right = alltime entry
    for _, key in ipairs(allNames) do
        local ri = resetByKey[key]
        local ai = allTimeByKey[key]
        local ref = ai or ri
        if ref then
            local leftText = ref.name .. "  " .. FormatLootEntry(ri)
            local rightText = FormatLootEntry(ai)
            GameTooltip:AddDoubleLine(leftText, rightText, ref.r, ref.g, ref.b, 0.9, 0.9, 0.9)
        end
    end

    -- Value totals
    if hasTSM and (resetTotal > 0 or allTimeTotal > 0) then
        local leftVal = resetTotal > 0 and ("|cffffd700Value: " .. ns.FormatGoldPositive(resetTotal) .. "|r") or " "
        local rightVal = allTimeTotal > 0 and ("|cffffd700Value: " .. ns.FormatGoldPositive(allTimeTotal) .. "|r") or " "
        GameTooltip:AddDoubleLine(leftVal, rightVal, 1, 0.84, 0, 1, 0.84, 0)
    end
end

-- Helper: add per-beast breakdown lines to tooltip
function ns.AddPerBeastTooltipLines(perBeastReset, perBeastAllTime)
    if not perBeastReset and not perBeastAllTime then return end
    local resetData = perBeastReset or {}
    local allTimeData = perBeastAllTime or {}

    -- Helper: format item name with quality icon
    local function formatItem(id)
        local name = GetCachedItemName(id)
        local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
        if quality and quality > 0 then
            name = name .. " |A:Professions-ChatIcon-Quality-12-Tier" .. quality .. ":12:12::1|a"
        end
        return name
    end

    local function getItemColor(id)
        local r, g, b = 0.9, 0.9, 0.9
        local itemQuality = select(3, C_Item.GetItemInfo(id))
        if itemQuality then
            local color = ITEM_QUALITY_COLORS[itemQuality]
            if color then r, g, b = color.r, color.g, color.b end
        end
        return r, g, b
    end

    for _, lure in ipairs(LURES) do
        local resetBl = resetData[lure.name]
        local allTimeBl = allTimeData[lure.name]
        local hasReset = resetBl and next(resetBl)
        local hasAllTime = allTimeBl and next(allTimeBl)
        if hasReset or hasAllTime then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(
                lure.color .. lure.name .. " (Reset)|r",
                lure.color .. lure.name .. " (All Time)|r",
                1, 1, 1, 1, 1, 1)

            -- Collect all item IDs from both
            local allIDs = {}
            local idSet = {}
            for id in pairs(allTimeBl or {}) do if not idSet[id] then idSet[id] = true; allIDs[#allIDs + 1] = id end end
            for id in pairs(resetBl or {}) do if not idSet[id] then idSet[id] = true; allIDs[#allIDs + 1] = id end end
            table.sort(allIDs, function(a, b)
                return GetCachedItemName(a) < GetCachedItemName(b)
            end)

            for _, id in ipairs(allIDs) do
                local name = formatItem(id)
                local r, g, b = getItemColor(id)
                local rc = resetBl and resetBl[id]
                local ac = allTimeBl and allTimeBl[id]
                local leftText = rc and ("  " .. name .. " x" .. rc) or " "
                local rightText = ac and (name .. " x" .. ac) or " "
                local lr, lg, lb = rc and r or 0.4, rc and g or 0.4, rc and b or 0.4
                local rr, rg, rb = ac and r or 0.4, ac and g or 0.4, ac and b or 0.4
                GameTooltip:AddDoubleLine(leftText, rightText, lr, lg, lb, rr, rg, rb)
            end
        end
    end
end

------------------------------------------------------
-- Loot Editor Panel
------------------------------------------------------

ns.lootEditor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
ns.lootEditor:SetFrameStrata("MEDIUM")
ns.lootEditor:SetClampedToScreen(true)
ns.lootEditor:SetBackdrop(ns.BACKDROP)
ns.lootEditor:SetBackdropColor(0, 0, 0, 0.97)
ns.lootEditor:SetBackdropBorderColor(unpack(ns.C_BORDER_RGB))
ns.lootEditor:EnableMouse(true)
ns.lootEditor:Hide()
-- OnHide set later after toolbar buttons are created (see below)
ns.lootEditor.rows = {}
ns.lootEditor.charKey = nil

local LOOT_ROW_HEIGHT = 22
local LOOT_EDITOR_WIDTH = 360
local LE_TOOLBAR_HEIGHT = 20

-- Loot Editor toolbar
local leToolbar = CreateFrame("Frame", nil, ns.lootEditor)
leToolbar:SetPoint("TOPLEFT", ns.lootEditor, "TOPLEFT", 4, -4)
leToolbar:SetPoint("TOPRIGHT", ns.lootEditor, "TOPRIGHT", -4, -4)
leToolbar:SetHeight(LE_TOOLBAR_HEIGHT)
local leToolbarBg = leToolbar:CreateTexture(nil, "BACKGROUND")
leToolbarBg:SetAllPoints()
leToolbarBg:SetColorTexture(0, 0, 0, 0.4)
local leToolbarSep = leToolbar:CreateTexture(nil, "ARTWORK")
leToolbarSep:SetHeight(1)
leToolbarSep:SetPoint("BOTTOMLEFT", leToolbar, "BOTTOMLEFT")
leToolbarSep:SetPoint("BOTTOMRIGHT", leToolbar, "BOTTOMRIGHT")
leToolbarSep:SetColorTexture(ns.C_BORDER_RGB[1], ns.C_BORDER_RGB[2], ns.C_BORDER_RGB[3], 0.3)

-- Title in toolbar
local lootTitle = leToolbar:CreateFontString(nil, "OVERLAY")
lootTitle:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
lootTitle:SetPoint("LEFT", leToolbar, "LEFT", 4, 0)
lootTitle:SetTextColor(0.82, 0.71, 0.35)
ns.lootEditor.title = lootTitle

-- Close button (toolbar)
local lootClose = CreateToolbarButton(leToolbar,
    MEDIA_PATH .. "Icon_Close", "Close", nil,
    function() ns.lootEditor:Hide() end)
lootClose:SetSize(LE_TOOLBAR_HEIGHT, LE_TOOLBAR_HEIGHT)
lootClose:SetPoint("RIGHT", leToolbar, "RIGHT", -2, 0)
lootClose.icon:SetTexCoord(0, 1, 0, 1)
lootClose:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 0.3, 0.3, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
    GameTooltip:AddLine("Close", 1, 1, 1)
    GameTooltip:Show()
end)
lootClose:SetScript("OnLeave", function(self)
    self.icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
    GameTooltip:Hide()
end)

-- Allow Decrease toggle (toolbar)
ns.lootEditorAllowDecrease = false
local leDecreaseBtn = CreateToolbarButton(leToolbar,
    MEDIA_PATH .. "Icon_Lock",
    function(self)
        local state = ns.lootEditorAllowDecrease
        GameTooltip:AddLine(state and "Lock All Time" or "Unlock All Time", 1, 1, 1)
        GameTooltip:AddLine("Allow decreasing Reset and All Time counts", 0.5, 0.8, 1, true)
    end,
    nil, nil)
leDecreaseBtn:SetSize(LE_TOOLBAR_HEIGHT, LE_TOOLBAR_HEIGHT)
leDecreaseBtn:SetPoint("RIGHT", lootClose, "LEFT", -2, 0)
leDecreaseBtn.icon:SetTexCoord(0, 1, 0, 1)
leDecreaseBtn.icon:SetAlpha(0.4)
leDecreaseBtn:SetScript("OnClick", function()
    ns.lootEditorAllowDecrease = not ns.lootEditorAllowDecrease
    leDecreaseBtn.icon:SetTexture(MEDIA_PATH .. (ns.lootEditorAllowDecrease and "Icon_LockOpen" or "Icon_Lock"))
    leDecreaseBtn.icon:SetAlpha(ns.lootEditorAllowDecrease and 1.0 or 0.4)
end)

-- History toggle (toolbar)
local leHistoryBtn = CreateToolbarButton(leToolbar,
    MEDIA_PATH .. "Icon_History",
    function(self)
        GameTooltip:AddLine("Loot History", 1, 1, 1)
        GameTooltip:AddLine("View daily loot history", 0.5, 0.8, 1, true)
    end,
    nil, nil)
leHistoryBtn:SetSize(LE_TOOLBAR_HEIGHT, LE_TOOLBAR_HEIGHT)
leHistoryBtn:SetPoint("RIGHT", leDecreaseBtn, "LEFT", -2, 0)
leHistoryBtn.icon:SetTexCoord(0, 1, 0, 1)
ns.lootEditorHistoryMode = false
ns.lootEditorHistoryPage = 0  -- 0 = current, 1 = yesterday, etc
local leCalendar  -- forward declaration, assigned after chevrons
local lePageLeft  -- forward declaration, used in lePageRight OnClick
-- History pagination controls (left of history button)
-- ChevronRight (>) = newer day (lower page number)
local lePageRight = CreateToolbarButton(leToolbar,
    MEDIA_PATH .. "Icon_ChevronRight", "Newer", nil, nil)
lePageRight:SetSize(LE_TOOLBAR_HEIGHT, LE_TOOLBAR_HEIGHT)
lePageRight:SetPoint("RIGHT", leHistoryBtn, "LEFT", 0, 0)
lePageRight.icon:SetTexCoord(0, 1, 0, 1)
lePageRight:Hide()
lePageRight:SetScript("OnClick", function()
    if ns.lootEditorHistoryPage > 1 then
        ns.lootEditorHistoryPage = ns.lootEditorHistoryPage - 1
        ns._repopulateLootEditor()
        -- Sync calendar selection
        if ns.lootEditor.charKey then
            local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
            local entry = charData and charData.loot and charData.loot.history and charData.loot.history[ns.lootEditorHistoryPage]
            if entry then leCalendar:SetSelectedDate(entry.date) end
        end
    elseif ns.lootEditorHistoryPage == 1 then
        -- Return to current reset data
        ns.lootEditorHistoryMode = false
        ns.lootEditorHistoryPage = 0
        leHistoryBtn.icon:SetAlpha(0.4)
        leDecreaseBtn:Show()
        lePageLeft:Hide()
        lePageRight:Hide()
        leCalendar:Hide()
        ns._repopulateLootEditor()
    end
end)

-- ChevronLeft (<) = older day (higher page number)
lePageLeft = CreateToolbarButton(leToolbar,
    MEDIA_PATH .. "Icon_ChevronLeft", "Older", nil, nil)
lePageLeft:SetSize(LE_TOOLBAR_HEIGHT, LE_TOOLBAR_HEIGHT)
lePageLeft:SetPoint("RIGHT", lePageRight, "LEFT", 0, 0)
lePageLeft.icon:SetTexCoord(0, 1, 0, 1)
lePageLeft:Hide()
lePageLeft:SetScript("OnClick", function()
    if not ns.lootEditor.charKey then return end
    local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
    local maxPage = charData and charData.loot and charData.loot.history and #charData.loot.history or 0
    if ns.lootEditorHistoryPage < maxPage then
        ns.lootEditorHistoryPage = ns.lootEditorHistoryPage + 1
        ns._repopulateLootEditor()
        -- Sync calendar selection
        local entry = charData and charData.loot and charData.loot.history and charData.loot.history[ns.lootEditorHistoryPage]
        if entry then leCalendar:SetSelectedDate(entry.date) end
    end
end)

-- Calendar picker for editor history date selection
leCalendar = ns.CreateCalendarPicker(ns.lootEditor, function(dateStr)
    local resetDate = ns.GetResetDate()
    if dateStr == resetDate then
        -- Today = back to current reset data
        ns.lootEditorHistoryMode = false
        ns.lootEditorHistoryPage = 0
        leHistoryBtn.icon:SetAlpha(0.4)
        leDecreaseBtn:Show()
        lePageLeft:Hide()
        lePageRight:Hide()
        ns._repopulateLootEditor()
        leCalendar:Hide()
        return
    end
    -- Find which history page matches this date for this character
    if not ns.lootEditor.charKey then return end
    local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
    if charData and charData.loot and charData.loot.history then
        for page, entry in ipairs(charData.loot.history) do
            if entry.date == dateStr then
                ns.lootEditorHistoryPage = page
                ns._repopulateLootEditor()
                return
            end
        end
    end
    -- No data for this date
    ns.lootEditor.title:SetText(ns.GetDemoName(ns.lootEditor.charKey) .. " — No data")
end)

-- Position calendar relative to editor
local function RepositionLeCalendar()
    leCalendar:ClearAllPoints()
    local frameCenter = ns.frame:GetCenter() or 0
    local editorCenter = ns.lootEditor:GetCenter() or 0
    if editorCenter < frameCenter then
        leCalendar:SetPoint("TOPRIGHT", ns.lootEditor, "TOPLEFT", -4, 0)
    else
        leCalendar:SetPoint("TOPLEFT", ns.lootEditor, "TOPRIGHT", 4, 0)
    end
end
leCalendar:SetScript("OnShow", RepositionLeCalendar)

-- Update calendar highlights from this character's history
local function UpdateLeCalendarHighlights()
    local dates = {}
    if ns.lootEditor.charKey then
        local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
        if charData and charData.loot and charData.loot.history then
            for _, entry in ipairs(charData.loot.history) do
                dates[entry.date] = true
            end
        end
    end
    -- Also highlight current reset day if there's data
    local resetDate = ns.GetResetDate()
    if ns.lootEditor.charKey then
        local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
        if charData and charData.loot and charData.loot.thisReset and next(charData.loot.thisReset) then
            dates[resetDate] = true
        end
    end
    leCalendar:SetHighlightDates(dates)
end

-- Show calendar when clicking history button
leHistoryBtn:SetScript("OnClick", function()
    ns.lootEditorHistoryMode = not ns.lootEditorHistoryMode
    leHistoryBtn.icon:SetAlpha(ns.lootEditorHistoryMode and 1.0 or 0.4)
    if ns.lootEditorHistoryMode then
        ns.lootEditorHistoryPage = 1
        leDecreaseBtn:Hide()
        lePageLeft:Show()
        lePageRight:Show()
        UpdateLeCalendarHighlights()
        -- Select the history page's date in the calendar
        if ns.lootEditor.charKey then
            local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
            if charData and charData.loot and charData.loot.history and charData.loot.history[1] then
                leCalendar:SetSelectedDate(charData.loot.history[1].date)
            end
        end
        leCalendar:Show()
    else
        ns.lootEditorHistoryPage = 0
        leDecreaseBtn:Show()
        lePageLeft:Hide()
        lePageRight:Hide()
        leCalendar:Hide()
    end
    if ns.lootEditor:IsShown() and ns.lootEditor.charKey then
        ns._repopulateLootEditor()
    end
end)

-- Reset history state when editor closes
ns.lootEditor:SetScript("OnHide", function()
    ns.lootEditorHistoryMode = false
    ns.lootEditorHistoryPage = 0
    leHistoryBtn.icon:SetAlpha(0.4)
    leDecreaseBtn:Show()
    lePageLeft:Hide()
    lePageRight:Hide()
    leCalendar:Hide()
end)

-- Syncing overlay
local syncOverlay = CreateFrame("Frame", nil, ns.lootEditor)
syncOverlay:SetAllPoints()
syncOverlay:SetFrameLevel(ns.lootEditor:GetFrameLevel() + 10)
syncOverlay:EnableMouse(true)
syncOverlay:Hide()
local syncBg = syncOverlay:CreateTexture(nil, "BACKGROUND")
syncBg:SetAllPoints()
syncBg:SetColorTexture(0, 0, 0, 0.7)
local syncText = syncOverlay:CreateFontString(nil, "OVERLAY")
syncText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
syncText:SetPoint("CENTER", 0, 0)
syncText:SetText("|cffD1B559Loot sync in progress...|r")
ns.lootEditor.syncOverlay = syncOverlay

-- Build sorted list of all tracked item IDs (sorted by name, then quality tier)
local function BuildSortedLootList()
    local items = {}
    for id in pairs(ns.TRACKED_LOOT) do
        local name = GetCachedItemName(id)
        local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id) or 0
        items[#items + 1] = { id = id, name = name, quality = quality }
    end
    table.sort(items, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.quality < b.quality
    end)
    return items
end

-- Inner function that actually populates the editor (called after items are cached)
local function PopulateLootEditor(anchor, charKey)
    ns.lootEditor.charKey = charKey
    if anchor ~= ns.lootEditor then
        ns.lootEditor._anchor = anchor
    end
    local charData = MajesticBeastTrackerDB.chars[charKey]
    if not charData then return end

    -- Ensure loot structure
    if not charData.loot then
        charData.loot = { thisReset = {}, allTime = {}, resetTime = GetServerTime() }
    end
    local loot = ns.GetCharLoot(charData)
    local isHistory = ns.lootEditorHistoryMode and ns.lootEditorHistoryPage > 0
    local historyEntry = nil
    local historyLoot = nil

    if isHistory then
        local history = charData.loot and charData.loot.history
        if history and history[ns.lootEditorHistoryPage] then
            historyEntry = history[ns.lootEditorHistoryPage]
            historyLoot = historyEntry.items or {}
        else
            isHistory = false
        end
    end

    -- Show/hide pagination controls
    if ns.lootEditorHistoryMode then
        lePageLeft:Show()
        lePageRight:Show()
        if isHistory and historyEntry then
            ns.lootEditor.title:SetText(ns.GetDemoName(charKey) .. " — " .. historyEntry.date)
        else
            ns.lootEditor.title:SetText(ns.GetDemoName(charKey) .. " — No history yet")
        end
    else
        lePageLeft:Hide()
        lePageRight:Hide()
        ns.lootEditor.title:SetText(ns.GetDemoName(charKey) .. " - Edit Loot")
    end

    local sortedItems = BuildSortedLootList()

    -- Layout columns
    local LE_NAME_W = 150
    local LE_RESET_X = 8 + 18 + 5 + LE_NAME_W + 4  -- icon + name + gap
    local LE_ALLTIME_X = LE_RESET_X + 80  -- reset area (count + edit + buttons)

    local yOff = -(LE_TOOLBAR_HEIGHT + 8)

    -- Column header
    if not ns.lootEditor._header then
        local hdr = CreateFrame("Frame", nil, ns.lootEditor)
        hdr:SetHeight(14)
        local hdrReset = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdrReset:SetFont(hdrReset:GetFont(), 9)
        hdrReset:SetPoint("LEFT", hdr, "LEFT", LE_RESET_X, 0)
        hdr._resetLabel = hdrReset
        local hdrAllTime = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdrAllTime:SetFont(hdrAllTime:GetFont(), 9)
        hdrAllTime:SetPoint("LEFT", hdr, "LEFT", LE_ALLTIME_X, 0)
        hdrAllTime:SetText("|cffffd700All Time|r")
        ns.lootEditor._header = hdr
    end
    ns.lootEditor._header._resetLabel:SetText(isHistory and "|cffffd700Day|r" or "|cffffd700Reset|r")
    ns.lootEditor._header:SetPoint("TOPLEFT", ns.lootEditor, "TOPLEFT", 0, yOff)
    ns.lootEditor._header:SetPoint("TOPRIGHT", ns.lootEditor, "TOPRIGHT", 0, yOff)
    ns.lootEditor._header:Show()
    yOff = yOff - 16

    for idx, entry in ipairs(sortedItems) do
        local itemID = entry.id
        local row = ns.lootEditor.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, ns.lootEditor)
            row:SetHeight(LOOT_ROW_HEIGHT)
            row:EnableMouse(true)

            -- Item icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", 8, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.icon = icon

            -- Item name
            local name = row:CreateFontString(nil, "OVERLAY")
            name:SetFont(STANDARD_TEXT_FONT, 10)
            name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            name:SetWidth(LE_NAME_W)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
            row.nameText = name

            -- Reset count display (clickable to edit)
            local countBtn = CreateFrame("Button", nil, row)
            countBtn:SetSize(36, LOOT_ROW_HEIGHT)
            countBtn:SetPoint("LEFT", row, "LEFT", LE_RESET_X, 0)
            local countLabel = countBtn:CreateFontString(nil, "OVERLAY")
            countLabel:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            countLabel:SetAllPoints()
            countLabel:SetJustifyH("CENTER")
            row.countLabel = countLabel
            row.countBtn = countBtn

            -- Inline EditBox (hidden by default)
            local editBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
            editBox:SetSize(36, 16)
            editBox:SetPoint("LEFT", row, "LEFT", LE_RESET_X, 0)
            editBox:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            editBox:SetJustifyH("CENTER")
            editBox:SetAutoFocus(false)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(5)
            editBox:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            editBox:SetBackdropColor(0, 0, 0, 0.9)
            editBox:SetBackdropBorderColor(0.82, 0.71, 0.35, 0.6)
            editBox:SetTextColor(1, 0.84, 0)
            editBox:Hide()
            row.editBox = editBox

            -- Minus button
            local minusBtn = CreateFrame("Button", nil, row)
            minusBtn:SetSize(18, 18)
            minusBtn:SetPoint("LEFT", row, "LEFT", LE_RESET_X + 38, 0)
            local minusTex = minusBtn:CreateFontString(nil, "OVERLAY")
            minusTex:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
            minusTex:SetAllPoints()
            minusTex:SetText("|cffff4444-|r")
            local minusHl = minusBtn:CreateTexture(nil, "HIGHLIGHT")
            minusHl:SetAllPoints()
            minusHl:SetColorTexture(1, 0.3, 0.3, 0.15)
            row.minusBtn = minusBtn

            -- Plus button
            local plusBtn = CreateFrame("Button", nil, row)
            plusBtn:SetSize(18, 18)
            plusBtn:SetPoint("LEFT", row, "LEFT", LE_RESET_X + 56, 0)
            local plusTex = plusBtn:CreateFontString(nil, "OVERLAY")
            plusTex:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
            plusTex:SetAllPoints()
            plusTex:SetText("|cff44ff44+|r")
            local plusHl = plusBtn:CreateTexture(nil, "HIGHLIGHT")
            plusHl:SetAllPoints()
            plusHl:SetColorTexture(0.3, 1, 0.3, 0.15)
            row.plusBtn = plusBtn

            -- All Time label (readonly)
            local allTimeLabel = row:CreateFontString(nil, "OVERLAY")
            allTimeLabel:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            allTimeLabel:SetPoint("LEFT", row, "LEFT", LE_ALLTIME_X, 0)
            allTimeLabel:SetJustifyH("LEFT")
            allTimeLabel:SetTextColor(0.7, 0.7, 0.7)
            row.allTimeLabel = allTimeLabel

            ns.lootEditor.rows[idx] = row
        end

        row:SetPoint("TOPLEFT", ns.lootEditor, "TOPLEFT", 0, yOff)
        row:SetPoint("TOPRIGHT", ns.lootEditor, "TOPRIGHT", 0, yOff)

        -- Set item data
        local tex = ns.GetItemIcon(itemID)
        if tex then row.icon:SetTexture(tex) end
        local itemName = GetCachedItemName(itemID)
        if entry.quality and entry.quality > 0 then
            itemName = itemName .. " |A:Professions-ChatIcon-Quality-12-Tier" .. entry.quality .. ":17:15::1|a"
        end
        row.nameText:SetText(itemName)
        row.nameText:SetTextColor(0.9, 0.9, 0.9)

        if isHistory then
            -- History mode: read-only, show history day count
            local histCount = historyLoot[itemID] or 0
            local allCount = loot.allTime[itemID] or 0
            row.countLabel:SetText(histCount > 0 and ("|cffffd700" .. histCount .. "|r") or "|cff666666—|r")
            row.allTimeLabel:SetText(tostring(allCount))
            row.editBox:Hide()
            row.countBtn:Show()
            row.minusBtn:Hide()
            row.plusBtn:Hide()
        else
            -- Normal edit mode
            local resetCount = loot.thisReset[itemID] or 0
            local allCount = loot.allTime[itemID] or 0
            row.countLabel:SetText("|cffffd700" .. resetCount .. "|r")
            row.allTimeLabel:SetText(tostring(allCount))
            row.editBox:Hide()
            row.countBtn:Show()
            row.minusBtn:Show()
            row.plusBtn:Show()
        end

        -- Item tooltip on hover
        local capturedID = itemID
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
            GameTooltip:SetItemByID(capturedID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Capture for closures
        local capturedIdx = idx

        -- Helper: update display after any edit
        local function RefreshRow()
            local cl = ns.GetCharLoot(charData)
            local rc = cl.thisReset[capturedID] or 0
            local ac = cl.allTime[capturedID] or 0
            ns.lootEditor.rows[capturedIdx].countLabel:SetText("|cffffd700" .. rc .. "|r")
            ns.lootEditor.rows[capturedIdx].allTimeLabel:SetText(tostring(ac))
            if ns.UpdateUI then ns.UpdateUI() end
        end

        -- Click count to type a value
        row.countBtn:SetScript("OnClick", function()
            local cl = ns.GetCharLoot(charData)
            row.countBtn:Hide()
            row.editBox:SetText(tostring(cl.thisReset[capturedID] or 0))
            row.editBox:Show()
            row.editBox:SetFocus()
            row.editBox:HighlightText()
        end)

        -- EditBox: commit on Enter, cancel on Escape
        local function CommitEdit()
            local val = tonumber(row.editBox:GetText()) or 0
            local cl = ns.GetCharLoot(charData)
            local oldReset = cl.thisReset[capturedID] or 0
            local delta = val - oldReset
            cl.thisReset[capturedID] = val > 0 and val or nil
            cl.allTime[capturedID] = math.max((cl.allTime[capturedID] or 0) + delta, 0)
            if cl.allTime[capturedID] <= 0 then cl.allTime[capturedID] = nil end
            row.editBox:Hide()
            row.countBtn:Show()
            RefreshRow()
        end
        row.editBox:SetScript("OnEnterPressed", CommitEdit)
        row.editBox:SetScript("OnEscapePressed", function()
            row.editBox:Hide()
            row.countBtn:Show()
        end)
        row.editBox:SetScript("OnEditFocusLost", function()
            row.editBox:Hide()
            row.countBtn:Show()
        end)

        row.minusBtn:SetScript("OnClick", function()
            local cl = ns.GetCharLoot(charData)
            -- Reset: always decreasable
            if cl.thisReset[capturedID] and cl.thisReset[capturedID] > 0 then
                cl.thisReset[capturedID] = cl.thisReset[capturedID] - 1
                if cl.thisReset[capturedID] <= 0 then cl.thisReset[capturedID] = nil end
            end
            -- All Time: only when unlocked
            if ns.lootEditorAllowDecrease then
                if cl.allTime[capturedID] and cl.allTime[capturedID] > 0 then
                    cl.allTime[capturedID] = cl.allTime[capturedID] - 1
                    if cl.allTime[capturedID] <= 0 then cl.allTime[capturedID] = nil end
                end
            end
            RefreshRow()
        end)

        row.plusBtn:SetScript("OnClick", function()
            local cl = ns.GetCharLoot(charData)
            cl.thisReset[capturedID] = (cl.thisReset[capturedID] or 0) + 1
            cl.allTime[capturedID] = (cl.allTime[capturedID] or 0) + 1
            RefreshRow()
        end)

        row:Show()
        yOff = yOff - LOOT_ROW_HEIGHT
    end

    -- Hide unused rows
    for i = #sortedItems + 1, #ns.lootEditor.rows do
        ns.lootEditor.rows[i]:Hide()
    end

    -- Show active buffs in history mode
    if not ns.lootEditor.buffsLabel then
        local bl = ns.lootEditor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bl:SetFont(bl:GetFont(), 9)
        bl:SetJustifyH("LEFT")
        bl:SetTextColor(0.7, 0.7, 0.7)
        ns.lootEditor.buffsLabel = bl
    end
    local buffsLabel = ns.lootEditor.buffsLabel
    if isHistory and historyEntry and historyEntry.killBuffs then
        -- Collect all unique buffs across all beasts for this day
        local allBuffs = {}
        local seen = {}
        for _, buffList in pairs(historyEntry.killBuffs) do
            for _, b in ipairs(buffList) do
                if not seen[b] then seen[b] = true; allBuffs[#allBuffs + 1] = b end
            end
        end
        if #allBuffs > 0 then
            yOff = yOff - 4
            buffsLabel:ClearAllPoints()
            buffsLabel:SetPoint("TOPLEFT", ns.lootEditor, "TOPLEFT", 8, yOff)
            buffsLabel:SetWidth(LOOT_EDITOR_WIDTH - 16)
            buffsLabel:SetText("|cffD1B559Buffs:|r " .. table.concat(allBuffs, ", "))
            buffsLabel:Show()
            yOff = yOff - 14
        else
            buffsLabel:Hide()
        end
    elseif not isHistory then
        -- Show current buffs for today's kills
        local charData = MajesticBeastTrackerDB.chars[ns.lootEditor.charKey]
        local killBuffs = charData and charData.loot and charData.loot.killBuffsReset
        if killBuffs then
            local allBuffs = {}
            local seen = {}
            for _, buffList in pairs(killBuffs) do
                for _, b in ipairs(buffList) do
                    if not seen[b] then seen[b] = true; allBuffs[#allBuffs + 1] = b end
                end
            end
            if #allBuffs > 0 then
                yOff = yOff - 4
                buffsLabel:ClearAllPoints()
                buffsLabel:SetPoint("TOPLEFT", ns.lootEditor, "TOPLEFT", 8, yOff)
                buffsLabel:SetWidth(LOOT_EDITOR_WIDTH - 16)
                buffsLabel:SetText("|cffD1B559Buffs:|r " .. table.concat(allBuffs, ", "))
                buffsLabel:Show()
                yOff = yOff - 14
            else
                buffsLabel:Hide()
            end
        else
            buffsLabel:Hide()
        end
    else
        buffsLabel:Hide()
    end

    ns.lootEditor:SetSize(LOOT_EDITOR_WIDTH, math.abs(yOff) + 8)
    ns.lootEditor:ClearAllPoints()
    -- Anchor to main frame side (same logic as loot summary)
    local frameRight = ns.frame:GetRight() or 0
    local screenWidth = GetScreenWidth()
    if frameRight + LOOT_EDITOR_WIDTH + 8 > screenWidth then
        ns.lootEditor:SetPoint("TOPRIGHT", ns.frame, "TOPLEFT", -4, 0)
    else
        ns.lootEditor:SetPoint("TOPLEFT", ns.frame, "TOPRIGHT", 4, 0)
    end
    -- Hide loot summary when editor opens (same space)
    if ns.lootSummary and ns.lootSummary:IsShown() then
        ns.lootSummary:Hide()
    end
    ns.lootEditor:Show()

    -- Show syncing overlay when loot sync is active
    if ns.isSyncingLoot then
        ns.lootEditor.syncOverlay:Show()
    else
        ns.lootEditor.syncOverlay:Hide()
    end
end

-- Preload item data then open editor
ns.ShowLootEditor = function(anchor, charKey)
    local pending = 0
    local allCached = true
    for id in pairs(ns.TRACKED_LOOT) do
        if not itemNameCache[id] and not C_Item.GetItemNameByID(id) then
            allCached = false
            pending = pending + 1
            C_Item.RequestLoadItemDataByID(id, function()
                pending = pending - 1
                if pending <= 0 then
                    PopulateLootEditor(anchor, charKey)
                end
            end)
        end
    end
    if allCached then
        PopulateLootEditor(anchor, charKey)
    end
end

-- Forward reference for history pagination
ns._repopulateLootEditor = function()
    if ns.lootEditor:IsShown() and ns.lootEditor.charKey then
        PopulateLootEditor(ns.lootEditor, ns.lootEditor.charKey)
    end
end

------------------------------------------------------
-- Loot Summary Window
------------------------------------------------------
local LS_COL_ITEM = 130
local LS_COL_COUNT = 45
local LS_COL_VALUE = 70
local LS_COL_GAP = 6
local LS_RESET_X = 8 + LS_COL_ITEM + LS_COL_GAP
local LS_ALLTIME_X = LS_RESET_X + LS_COL_COUNT + LS_COL_VALUE + LS_COL_GAP
local LOOT_SUMMARY_WIDTH = 8 + LS_COL_ITEM + LS_COL_GAP + (LS_COL_COUNT + LS_COL_VALUE) * 2 + LS_COL_GAP + 12
local LOOT_SUMMARY_ROW_HEIGHT = 16

ns.lootSummary = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
ns.lootSummary:SetFrameStrata("MEDIUM")
ns.lootSummary:SetClampedToScreen(true)
ns.lootSummary:SetBackdrop(ns.BACKDROP)
ns.lootSummary:SetBackdropColor(0, 0, 0, 0.97)
ns.lootSummary:SetBackdropBorderColor(unpack(ns.C_BORDER_RGB))
ns.lootSummary:EnableMouse(true)
ns.lootSummary:SetMovable(true)
ns.lootSummary:RegisterForDrag("LeftButton")
ns.lootSummary:SetScript("OnDragStart", function(self) self:StartMoving() end)
ns.lootSummary:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ns.lootSummary:SetScript("OnEnter", function() ns.RefreshAutoHide() end)
ns.lootSummary:SetScript("OnLeave", function() ns.RefreshAutoHide() end)
ns.lootSummary:Hide()
ns.lootSummary.rows = {}

local LOOT_SUMMARY_MAX_HEIGHT = 400
local LS_TOOLBAR_HEIGHT = 20

-- Loot Summary toolbar
local lsToolbar = CreateFrame("Frame", nil, ns.lootSummary)
lsToolbar:SetPoint("TOPLEFT", ns.lootSummary, "TOPLEFT", 4, -4)
lsToolbar:SetPoint("TOPRIGHT", ns.lootSummary, "TOPRIGHT", -4, -4)
lsToolbar:SetHeight(LS_TOOLBAR_HEIGHT)
local lsToolbarBg = lsToolbar:CreateTexture(nil, "BACKGROUND")
lsToolbarBg:SetAllPoints()
lsToolbarBg:SetColorTexture(0, 0, 0, 0.4)
local lsToolbarSep = lsToolbar:CreateTexture(nil, "ARTWORK")
lsToolbarSep:SetHeight(1)
lsToolbarSep:SetPoint("BOTTOMLEFT", lsToolbar, "BOTTOMLEFT")
lsToolbarSep:SetPoint("BOTTOMRIGHT", lsToolbar, "BOTTOMRIGHT")
lsToolbarSep:SetColorTexture(ns.C_BORDER_RGB[1], ns.C_BORDER_RGB[2], ns.C_BORDER_RGB[3], 0.3)

local lootSumTitle = lsToolbar:CreateFontString(nil, "OVERLAY")
lootSumTitle:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
lootSumTitle:SetPoint("LEFT", lsToolbar, "LEFT", 4, 0)  -- re-anchored after lsExportBtn creation
lootSumTitle:SetTextColor(0.82, 0.71, 0.35)
lootSumTitle:SetText("Loot Summary")

-- Close button (toolbar)
local lootSumClose = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_Close", "Close", nil,
    function() ns.lootSummary:Hide() end)
lootSumClose:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lootSumClose:SetPoint("RIGHT", lsToolbar, "RIGHT", -2, 0)
lootSumClose.icon:SetTexCoord(0, 1, 0, 1)
lootSumClose:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 0.3, 0.3, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
    GameTooltip:AddLine("Close", 1, 1, 1)
    GameTooltip:Show()
end)
lootSumClose:SetScript("OnLeave", function(self)
    self.icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
    GameTooltip:Hide()
end)

-- Show Breakdown toggle (toolbar)
ns.lootSummaryShowBreakdown = true
local lsBreakdownBtn = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_Results",
    function(self)
        local state = ns.lootSummaryShowBreakdown
        GameTooltip:AddLine(state and "Hide Beast Breakdown" or "Show Beast Breakdown", 1, 1, 1)
    end,
    nil, nil)
lsBreakdownBtn:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsBreakdownBtn:SetPoint("RIGHT", lootSumClose, "LEFT", -2, 0)
lsBreakdownBtn.icon:SetTexCoord(0, 1, 0, 1)
lsBreakdownBtn:SetScript("OnClick", function()
    ns.lootSummaryShowBreakdown = not ns.lootSummaryShowBreakdown
    lsBreakdownBtn.icon:SetAlpha(ns.lootSummaryShowBreakdown and 1.0 or 0.4)
    if ns.lootSummary:IsShown() and ns._populateLootSummary then
        ns._populateLootSummary()
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
    end
end)

-- History toggle (toolbar)
ns.lootSummaryHistoryMode = false
ns.lootSummaryHistoryPage = 0
local lsHistoryBtn = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_History",
    function(self)
        GameTooltip:AddLine("Loot History", 1, 1, 1)
        GameTooltip:AddLine("View daily loot history for all characters", 0.5, 0.8, 1, true)
    end,
    nil, nil)
lsHistoryBtn:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsHistoryBtn:SetPoint("RIGHT", lsBreakdownBtn, "LEFT", -2, 0)

-- Drop % toggle button
local lsDropPctBtn = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_Coins",
    function(self)
        ns.EnsureDB()
        local on = MajesticBeastTrackerDB.settings.showDropPercent
        GameTooltip:AddLine("Drop %", 1, 1, 1)
        GameTooltip:AddLine(on and "Click to hide drop rates" or "Click to show drop rates", 0.5, 0.8, 1, true)
        if on then
            local fmt = MajesticBeastTrackerDB.settings.dropPercentFormat and "per kill" or "percentage"
            GameTooltip:AddLine("Shift-click: switch format (now: " .. fmt .. ")", 0.5, 0.5, 0.5, true)
        end
    end,
    nil, nil)
lsDropPctBtn:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsDropPctBtn:SetPoint("RIGHT", lsHistoryBtn, "LEFT", -2, 0)
lsDropPctBtn.icon:SetTexCoord(0, 1, 0, 1)
lsDropPctBtn:SetScript("OnClick", function()
    ns.EnsureDB()
    if IsShiftKeyDown() then
        -- Shift-click: toggle format (% vs /kill)
        MajesticBeastTrackerDB.settings.dropPercentFormat = not MajesticBeastTrackerDB.settings.dropPercentFormat
    else
        MajesticBeastTrackerDB.settings.showDropPercent = not MajesticBeastTrackerDB.settings.showDropPercent
    end
    lsDropPctBtn.icon:SetAlpha(MajesticBeastTrackerDB.settings.showDropPercent and 1.0 or 0.4)
    ns._populateLootSummary()
end)

-- Export CSV button
local lsExportBtn = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_ExportData",
    function(self)
        GameTooltip:AddLine("Export CSV", 1, 1, 1)
        GameTooltip:AddLine("Copy loot data to clipboard", 0.5, 0.8, 1, true)
    end,
    nil, nil)
lsExportBtn:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsExportBtn:SetPoint("LEFT", lsToolbar, "LEFT", 2, 0)

lsExportBtn.icon:SetTexCoord(0, 1, 0, 1)
-- Re-anchor title to the right of export button
lootSumTitle:ClearAllPoints()
lootSumTitle:SetPoint("LEFT", lsExportBtn, "RIGHT", 2, 0)
lsExportBtn:SetScript("OnClick", function()
    ns.EnsureDB()
    local LURES = ns.LURES
    local resetLoot, allTimeLoot, globalPrices, globalPerBeast, globalPerBeastReset
    local resetDateStr = ns.GetResetDate()

    if ns.lootSummaryHistoryMode and ns.lootSummaryHistoryPage > 0 then
        resetLoot = {}
        globalPrices = {}
        globalPerBeastReset = {}
        resetDateStr = "?"
        for _, charData in pairs(MajesticBeastTrackerDB.chars) do
            if charData.loot and charData.loot.history then
                local entry = charData.loot.history[ns.lootSummaryHistoryPage]
                if entry then
                    if resetDateStr == "?" then resetDateStr = entry.date end
                    for id, count in pairs(entry.items or {}) do
                        resetLoot[id] = (resetLoot[id] or 0) + count
                    end
                    if entry.prices then
                        for id, price in pairs(entry.prices) do
                            if not globalPrices[id] then globalPrices[id] = price end
                        end
                    end
                    if entry.perBeast then
                        for beastName, items in pairs(entry.perBeast) do
                            if not globalPerBeastReset[beastName] then globalPerBeastReset[beastName] = {} end
                            for id, count in pairs(items) do
                                globalPerBeastReset[beastName][id] = (globalPerBeastReset[beastName][id] or 0) + count
                            end
                        end
                    end
                end
            end
        end
        _, allTimeLoot, _, globalPerBeast = ns.GetGlobalLoot()
    else
        resetLoot, allTimeLoot, globalPrices, globalPerBeast, globalPerBeastReset = ns.GetGlobalLoot()
    end

    local hasTSM = TSM_API ~= nil
    local csvLines = {}

    -- Characters section (all chars, with hidden status)
    local hiddenChars = MajesticBeastTrackerDB.settings.hiddenChars or {}
    csvLines[#csvLines + 1] = "#Characters"
    csvLines[#csvLines + 1] = "Character,Class,Level,Hidden"
    for charKey, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.hasSkinning then
            csvLines[#csvLines + 1] = string.format("%s,%s,%d,%s",
                charKey:gsub(",", ";"), charData.class or "UNKNOWN", charData.level or 0,
                hiddenChars[charKey] and "yes" or "no")
        end
    end
    csvLines[#csvLines + 1] = ""
    csvLines[#csvLines + 1] = "#Loot"
    csvLines[#csvLines + 1] = "Date,Character,Beast,Item ID,Item,Quality,Count,Unit Price (gold),Value (gold),Active Buffs"

    -- Helper: get quality tier for an item
    local function getQuality(id)
        local q = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
        return q and q > 0 and q or 0
    end

    -- Helper: format one CSV row
    local function addRow(dateStr, charName, beast, id, count, unused, prices, buffsStr)
        local name = (GetCachedItemName(id)):gsub(",", ";")
        local quality = getQuality(id)
        local unitPrice = 0
        if hasTSM then
            local price = prices and prices[id] or ns.GetTSMPrice(id)
            if price then unitPrice = math.floor(price / 10000 + 0.5) end
        end
        local value = count * unitPrice
        csvLines[#csvLines + 1] = string.format("%s,%s,%s,%d,%s,%d,%d,%d,%d,%s",
            dateStr, charName, beast, id, name, quality, count, unitPrice, value, buffsStr or "")
    end

    -- Helper: export one day's loot for a character
    local function exportDay(charName, dateStr, items, perBeast, prices, killBuffs)
        if not items or not next(items) then return end
        -- Per-beast breakdown
        if perBeast then
            for _, lure in ipairs(LURES) do
                local beastItems = perBeast[lure.name]
                if beastItems and next(beastItems) then
                    local beastIDs = {}
                    for id in pairs(beastItems) do beastIDs[#beastIDs + 1] = id end
                    table.sort(beastIDs)
                    local buffsStr = killBuffs and killBuffs[lure.name] and table.concat(killBuffs[lure.name], "; ") or ""
                    for _, id in ipairs(beastIDs) do
                        addRow(dateStr, charName, lure.name, id, beastItems[id] or 0, 0, prices, buffsStr)
                    end
                end
            end
        else
            -- No per-beast data, export as "All"
            local allIDs = {}
            for id in pairs(items) do allIDs[#allIDs + 1] = id end
            table.sort(allIDs)
            for _, id in ipairs(allIDs) do
                addRow(dateStr, charName, "All", id, items[id] or 0, 0, prices)
            end
        end
    end

    if ns.lootSummaryHistoryMode and ns.lootSummaryHistoryPage > 0 then
        -- History mode: export only the selected day
        for charKey, charData in pairs(MajesticBeastTrackerDB.chars) do
            if charData.loot and charData.loot.history then
                local entry = charData.loot.history[ns.lootSummaryHistoryPage]
                if entry then
                    exportDay(charKey:gsub(",", ";"), entry.date, entry.items, entry.perBeast, entry.prices, entry.killBuffs)
                end
            end
        end
    else
        -- Full export: all history days + current reset, per character
        for charKey, charData in pairs(MajesticBeastTrackerDB.chars) do
            if charData.loot then
                local loot = ns.GetCharLoot(charData)
                if loot then
                    local charName = charKey:gsub(",", ";")
                    -- History days (oldest first)
                    if loot.history then
                        for i = #loot.history, 1, -1 do
                            local entry = loot.history[i]
                            exportDay(charName, entry.date, entry.items, entry.perBeast, entry.prices, entry.killBuffs)
                        end
                    end
                    -- Current reset
                    if loot.thisReset and next(loot.thisReset) then
                        exportDay(charName, resetDateStr, loot.thisReset, loot.perBeastReset, loot.prices, loot.killBuffsReset)
                    end
                    -- All Time remainder (allTime minus sum of history + thisReset)
                    if loot.allTime and next(loot.allTime) then
                        -- Sum all historied + current reset counts per item
                        local historied = {}
                        if loot.history then
                            for _, entry in ipairs(loot.history) do
                                for id, cnt in pairs(entry.items or {}) do
                                    historied[id] = (historied[id] or 0) + cnt
                                end
                            end
                        end
                        if loot.thisReset then
                            for id, cnt in pairs(loot.thisReset) do
                                historied[id] = (historied[id] or 0) + cnt
                            end
                        end
                        -- Export only the untracked remainder
                        local allIDs = {}
                        for id in pairs(loot.allTime) do allIDs[#allIDs + 1] = id end
                        table.sort(allIDs)
                        for _, id in ipairs(allIDs) do
                            local remainder = (loot.allTime[id] or 0) - (historied[id] or 0)
                            if remainder > 0 then
                                addRow("AllTime", charName, "All", id, remainder, 0, loot.prices)
                            end
                        end
                    end
                end
            end
        end
    end
    -- Show in scrollable copy window
    if not ns._exportFrame or not ns._exportFrame.importBtn then
        if ns._exportFrame then ns._exportFrame:Hide(); ns._exportFrame = nil end
        local ef = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ef:SetSize(500, 300)
        ef:SetPoint("CENTER")
        ef:SetFrameStrata("DIALOG")
        ef:SetBackdrop(ns.BACKDROP)
        ef:SetBackdropColor(0, 0, 0, 0.95)
        ef:SetBackdropBorderColor(unpack(ns.C_BORDER_RGB))
        ef:SetMovable(true)
        ef:EnableMouse(true)
        ef:RegisterForDrag("LeftButton")
        ef:SetScript("OnDragStart", function(s) s:StartMoving() end)
        ef:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
        ef:Hide()

        -- Toolbar
        local toolbar = CreateFrame("Frame", nil, ef)
        toolbar:SetPoint("TOPLEFT", ef, "TOPLEFT", 4, -4)
        toolbar:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -4, -4)
        toolbar:SetHeight(20)
        local toolbarBg = toolbar:CreateTexture(nil, "BACKGROUND")
        toolbarBg:SetAllPoints()
        toolbarBg:SetColorTexture(0, 0, 0, 0.4)
        local toolbarSep = toolbar:CreateTexture(nil, "ARTWORK")
        toolbarSep:SetHeight(1)
        toolbarSep:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT")
        toolbarSep:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT")
        toolbarSep:SetColorTexture(ns.C_BORDER_RGB[1], ns.C_BORDER_RGB[2], ns.C_BORDER_RGB[3], 0.3)

        local title = toolbar:CreateFontString(nil, "OVERLAY")
        title:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        title:SetPoint("LEFT", toolbar, "LEFT", 4, 0)
        title:SetTextColor(0.82, 0.71, 0.35)
        title:SetText("Export CSV")

        local closeBtn = CreateFrame("Button", nil, toolbar)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("RIGHT", toolbar, "RIGHT", -2, 0)
        local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
        closeTex:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        closeTex:SetAllPoints()
        closeTex:SetText("|cffff4444×|r")
        closeBtn:SetScript("OnClick", function() ef:Hide() end)
        closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3) end)
        closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.82, 0.71, 0.35) end)

        local scroll = CreateFrame("ScrollFrame", nil, ef, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -28)
        scroll:SetPoint("BOTTOMRIGHT", -28, 8)

        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(460)
        editBox:SetTextColor(0.9, 0.9, 0.9)
        editBox:SetScript("OnEscapePressed", function() ef:Hide() end)
        scroll:SetScrollChild(editBox)

        -- Import button
        local importBtn = CreateFrame("Button", nil, toolbar)
        importBtn:SetSize(60, 20)
        importBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
        local importBtnText = importBtn:CreateFontString(nil, "OVERLAY")
        importBtnText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        importBtnText:SetAllPoints()
        importBtnText:SetText("|cffD1B559Import|r")
        local importHl = importBtn:CreateTexture(nil, "HIGHLIGHT")
        importHl:SetAllPoints()
        importHl:SetColorTexture(1, 1, 1, 0.1)
        ef.importBtn = importBtn
        ef.importBtnText = importBtnText
        ef.title = title

        -- Back button (visible only in import mode)
        local backBtn = CreateFrame("Button", nil, toolbar)
        backBtn:SetSize(50, 20)
        backBtn:SetPoint("LEFT", toolbar, "LEFT", 2, 0)
        local backBtnText = backBtn:CreateFontString(nil, "OVERLAY")
        backBtnText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        backBtnText:SetAllPoints()
        backBtnText:SetText("|cffD1B559< Back|r")
        local backHl = backBtn:CreateTexture(nil, "HIGHLIGHT")
        backHl:SetAllPoints()
        backHl:SetColorTexture(1, 1, 1, 0.1)
        backBtn:Hide()
        ef.backBtn = backBtn

        -- Append toggle (visible in import mode, below toolbar)
        local appendCheck = CreateFrame("CheckButton", nil, ef, "UICheckButtonTemplate")
        appendCheck:SetSize(20, 20)
        appendCheck:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -26)
        appendCheck:SetChecked(false)
        appendCheck:Hide()
        local appendLabel = ef:CreateFontString(nil, "OVERLAY")
        appendLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        appendLabel:SetPoint("LEFT", appendCheck, "RIGHT", 2, 0)
        appendLabel:SetText("|cffD1B559Append mode|r |cff888888(add to existing data instead of skip)|r")
        appendLabel:Hide()
        ef.appendCheck = appendCheck
        ef.appendLabel = appendLabel

        -- Import mode toggle
        ef._importMode = false
        ef._lastExportCSV = ""

        local function ShowExportMode()
            ef._importMode = false
            importBtnText:SetText("|cffD1B559Import|r")
            title:SetText("Export CSV — Ctrl+A, Ctrl+C")
            title:ClearAllPoints()
            title:SetPoint("LEFT", toolbar, "LEFT", 4, 0)
            backBtn:Hide()
            appendCheck:Hide()
            appendLabel:Hide()
            scroll:SetPoint("TOPLEFT", 8, -28)
            if ef._lastExportCSV and #ef._lastExportCSV > 0 then
                editBox:SetText(ef._lastExportCSV)
                editBox:SetFocus()
                editBox:HighlightText()
            end
        end

        backBtn:SetScript("OnClick", ShowExportMode)

        importBtn:SetScript("OnClick", function()
            if not ef._importMode then
                -- Switch to import mode
                ef._importMode = true
                title:SetText("Import CSV — Paste data, click Run Import")
                title:ClearAllPoints()
                title:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
                importBtnText:SetText("|cff00ff00Run Import|r")
                backBtn:Show()
                appendCheck:Show()
                appendLabel:Show()
                scroll:SetPoint("TOPLEFT", 8, -46)
                editBox:SetText("")
                editBox:SetFocus()
            else
                -- Run import
                local text = editBox:GetText()
                if text and #text > 10 then
                    local appendMode = appendCheck:GetChecked()
                    local imported, skipped = ns.ImportCSV(text, appendMode)
                    title:SetText("Import done: " .. imported .. " imported, " .. skipped .. " skipped")
                    if ns.UpdateUI then ns.UpdateUI() end
                else
                    ShowExportMode()
                end
            end
        end)

        ef.editBox = editBox
        ns._exportFrame = ef
    end
    local csv = table.concat(csvLines, "\n")
    ns._exportFrame._lastExportCSV = csv
    ns._exportFrame._importMode = false
    if ns._exportFrame.importBtnText then
        ns._exportFrame.importBtnText:SetText("|cffD1B559Import|r")
    end
    if ns._exportFrame.title then
        ns._exportFrame.title:SetText("Export CSV — Ctrl+A, Ctrl+C")
    end
    if ns._exportFrame.backBtn then
        ns._exportFrame.backBtn:Hide()
    end
    ns._exportFrame.editBox:SetText(csv)
    ns._exportFrame:Show()
    ns._exportFrame.editBox:SetFocus()
    ns._exportFrame.editBox:HighlightText()
end)
lsHistoryBtn.icon:SetTexCoord(0, 1, 0, 1)
lsHistoryBtn.icon:SetAlpha(0.4)
lsHistoryBtn:SetScript("OnClick", function()
    ns.lootSummaryHistoryMode = not ns.lootSummaryHistoryMode
    lsHistoryBtn.icon:SetAlpha(ns.lootSummaryHistoryMode and 1.0 or 0.4)
    if ns.lootSummaryHistoryMode then
        ns.lootSummaryHistoryPage = 1
    else
        ns.lootSummaryHistoryPage = 0
    end
    if ns.lootSummary:IsShown() and ns._populateLootSummary then
        ns._populateLootSummary()
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
    end
end)

-- Pagination (chevrons + date in title)
local lsPageLeft  -- forward declaration, used in lsPageRight OnClick
local UpdateExportAnchor  -- forward declaration, defined after chevrons
local lsPageRight = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_ChevronRight", "Newer", nil, nil)
lsPageRight:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsPageRight:SetPoint("RIGHT", lsHistoryBtn, "LEFT", 0, 0)
lsPageRight.icon:SetTexCoord(0, 1, 0, 1)
lsPageRight:Hide()
-- Helper: find history date for a given page across all characters
local function GetGlobalHistoryDate(page)
    ns.EnsureDB()
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.loot and charData.loot.history and charData.loot.history[page] then
            return charData.loot.history[page].date
        end
    end
    return nil
end

lsPageRight:SetScript("OnClick", function()
    if ns.lootSummaryHistoryPage > 1 then
        ns.lootSummaryHistoryPage = ns.lootSummaryHistoryPage - 1
        if ns._populateLootSummary then ns._populateLootSummary() end
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
        -- Sync calendar selection
        local d = GetGlobalHistoryDate(ns.lootSummaryHistoryPage)
        if d and ns.lsCalendar then ns.lsCalendar:SetSelectedDate(d) end
    elseif ns.lootSummaryHistoryPage == 1 then
        -- Return to current reset data
        ns.lootSummaryHistoryMode = false
        ns.lootSummaryHistoryPage = 0
        lsHistoryBtn.icon:SetAlpha(0.4)
        lsPageLeft:Hide()
        lsPageRight:Hide()
        UpdateExportAnchor()
        ns.lsCalendar:Hide()
        if ns._populateLootSummary then ns._populateLootSummary() end
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
    end
end)

lsPageLeft = CreateToolbarButton(lsToolbar,
    MEDIA_PATH .. "Icon_ChevronLeft", "Older", nil, nil)
lsPageLeft:SetSize(LS_TOOLBAR_HEIGHT, LS_TOOLBAR_HEIGHT)
lsPageLeft:SetPoint("RIGHT", lsPageRight, "LEFT", 0, 0)
lsPageLeft.icon:SetTexCoord(0, 1, 0, 1)
lsPageLeft:Hide()
lsPageLeft:SetScript("OnClick", function()
    -- Find max history across all characters
    local maxPage = 0
    ns.EnsureDB()
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.loot and charData.loot.history then
            maxPage = math.max(maxPage, #charData.loot.history)
        end
    end
    if ns.lootSummaryHistoryPage < maxPage then
        ns.lootSummaryHistoryPage = ns.lootSummaryHistoryPage + 1
        if ns._populateLootSummary then ns._populateLootSummary() end
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
        -- Sync calendar selection
        local d = GetGlobalHistoryDate(ns.lootSummaryHistoryPage)
        if d and ns.lsCalendar then ns.lsCalendar:SetSelectedDate(d) end
    end
end)

-- Export is now left-anchored, no dynamic re-anchoring needed
UpdateExportAnchor = function() end

-- Calendar picker for history date selection
ns.lsCalendar = ns.CreateCalendarPicker(ns.lootSummary, function(dateStr)
    local resetDate = ns.GetResetDate()
    if dateStr == resetDate then
        -- Today = current reset data (not archived yet)
        ns.lootSummaryHistoryMode = false
        ns.lootSummaryHistoryPage = 0
        lsHistoryBtn.icon:SetAlpha(0.4)
        lsPageLeft:Hide()
        lsPageRight:Hide()
        UpdateExportAnchor()
        if ns._populateLootSummary then ns._populateLootSummary() end
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
        ns.lsCalendar:Hide()
        return
    end
    -- Find which history page matches this date
    ns.EnsureDB()
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.loot and charData.loot.history then
            for page, entry in ipairs(charData.loot.history) do
                if entry.date == dateStr then
                    ns.lootSummaryHistoryPage = page
                    if ns._populateLootSummary then ns._populateLootSummary() end
                    if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
                    return
                end
            end
        end
    end
    -- No data for this date
    ns.lootSummaryHistoryPage = 0
    lootSumTitle:SetText("History — No data for " .. dateStr)
end)
-- Position calendar: same side as loot summary relative to main frame (always outward)
local function RepositionCalendar()
    ns.lsCalendar:ClearAllPoints()
    local frameCenter = ns.frame:GetCenter() or 0
    local sumCenter = ns.lootSummary:GetCenter() or 0
    if sumCenter < frameCenter then
        -- Summary is left of main → calendar goes further left
        ns.lsCalendar:SetPoint("TOPRIGHT", ns.lootSummary, "TOPLEFT", -4, 0)
    else
        -- Summary is right of main → calendar goes further right
        ns.lsCalendar:SetPoint("TOPLEFT", ns.lootSummary, "TOPRIGHT", 4, 0)
    end
end
ns.lsCalendar:SetScript("OnShow", RepositionCalendar)

-- Update calendar highlight dates from history
local function UpdateCalendarHighlights()
    local dates = {}
    ns.EnsureDB()
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.loot and charData.loot.history then
            for _, entry in ipairs(charData.loot.history) do
                dates[entry.date] = true
            end
        end
    end
    -- Also highlight current reset day if there's data
    local resetDate = ns.GetResetDate()
    local resetLoot = ns.GetGlobalLoot()
    if resetLoot and next(resetLoot) then dates[resetDate] = true end
    ns.lsCalendar:SetHighlightDates(dates)
end

-- Show calendar when clicking history button while history mode is on
lsHistoryBtn:SetScript("OnClick", function()
    ns.lootSummaryHistoryMode = not ns.lootSummaryHistoryMode
    lsHistoryBtn.icon:SetAlpha(ns.lootSummaryHistoryMode and 1.0 or 0.4)
    if ns.lootSummaryHistoryMode then
        ns.lootSummaryHistoryPage = 1
        lsPageLeft:Show()
        lsPageRight:Show()
        UpdateExportAnchor()
        UpdateCalendarHighlights()
        -- Select the first history date in the calendar
        local d = GetGlobalHistoryDate(1)
        if d then ns.lsCalendar:SetSelectedDate(d) end
        ns.lsCalendar:Show()
    else
        ns.lootSummaryHistoryPage = 0
        lsPageLeft:Hide()
        lsPageRight:Hide()
        UpdateExportAnchor()
        ns.lsCalendar:Hide()
        -- Return to current reset data
        if ns._populateLootSummary then ns._populateLootSummary() end
        if ns._lootSumScrollbar then ns._lootSumScrollbar:SetValue(0) end
    end
end)

-- Reset history on hide
ns.lootSummary:SetScript("OnHide", function()
    ns.lootSummaryHistoryMode = false
    ns.lootSummaryHistoryPage = 0
    lsHistoryBtn.icon:SetAlpha(0.4)
    lsPageLeft:Hide()
    lsPageRight:Hide()
    UpdateExportAnchor()
    ns.lsCalendar:Hide()
end)

-- Custom scroll frame (no UIPanelScrollFrameTemplate — avoids rendering glitches)
local lsHeaderHeight = LS_TOOLBAR_HEIGHT + 4
local LS_SCROLL_SPEED = LOOT_SUMMARY_ROW_HEIGHT * 3

local lootSumScroll = CreateFrame("ScrollFrame", nil, ns.lootSummary)
lootSumScroll:SetPoint("TOPLEFT", ns.lootSummary, "TOPLEFT", 0, -lsHeaderHeight)
lootSumScroll:SetPoint("BOTTOMRIGHT", ns.lootSummary, "BOTTOMRIGHT", -8, 4)

local lootSumChild = CreateFrame("Frame", nil, lootSumScroll)
lootSumChild:SetWidth(LOOT_SUMMARY_WIDTH - 16)
lootSumScroll:SetScrollChild(lootSumChild)

-- Vertical scrollbar (custom slider)
local lsScrollbar = CreateFrame("Slider", nil, ns.lootSummary, "UISliderTemplate")
ns._lootSumScrollbar = lsScrollbar
lsScrollbar:SetPoint("TOPRIGHT", ns.lootSummary, "TOPRIGHT", -2, -lsHeaderHeight)
lsScrollbar:SetPoint("BOTTOMRIGHT", ns.lootSummary, "BOTTOMRIGHT", -2, 4)
lsScrollbar:SetWidth(8)
lsScrollbar:SetMinMaxValues(0, 1)
lsScrollbar:SetValue(0)
lsScrollbar:SetValueStep(1)
lsScrollbar:SetOrientation("VERTICAL")
lsScrollbar:SetObeyStepOnDrag(true)
lsScrollbar.thumb = lsScrollbar:GetThumbTexture()
lsScrollbar.thumb:SetPoint("CENTER")
lsScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.4)
lsScrollbar.thumb:SetWidth(8)
if lsScrollbar.NineSlice then lsScrollbar.NineSlice:Hide() end
lsScrollbar:SetScript("OnValueChanged", function(_, value)
    lootSumScroll:SetVerticalScroll(value)
end)
lsScrollbar:SetScript("OnEnter", function() lsScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.7) end)
lsScrollbar:SetScript("OnLeave", function() lsScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.4) end)

local function UpdateLootSumScrollbar()
    local viewH = lootSumScroll:GetHeight()
    local contentH = lootSumChild:GetHeight()
    if contentH > viewH then
        lsScrollbar:SetMinMaxValues(0, contentH - viewH)
        lsScrollbar:SetValueStep(LS_SCROLL_SPEED)
        local ratio = viewH / contentH
        lsScrollbar.thumb:SetHeight(math.max(viewH * ratio, 20))
        lsScrollbar:Show()
    else
        lootSumScroll:SetVerticalScroll(0)
        lsScrollbar:SetValue(0)
        lsScrollbar:Hide()
    end
end

lootSumScroll:EnableMouseWheel(true)
lootSumScroll:SetScript("OnMouseWheel", function(_, delta)
    lsScrollbar:SetValue(lsScrollbar:GetValue() - delta * LS_SCROLL_SPEED)
end)
lootSumScroll:SetScript("OnSizeChanged", UpdateLootSumScrollbar)
lootSumChild:SetScript("OnSizeChanged", UpdateLootSumScrollbar)

-- Column group borders (inside scroll child, resized dynamically)


local function CreateLootSummaryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LOOT_SUMMARY_ROW_HEIGHT)
    -- Item name
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.item:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.item:SetWidth(LS_COL_ITEM)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    -- Reset count (left-aligned in reset group)
    row.resetCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.resetCount:SetPoint("LEFT", row, "LEFT", LS_RESET_X, 0)
    row.resetCount:SetWidth(LS_COL_COUNT)
    row.resetCount:SetJustifyH("LEFT")
    -- Reset value (left-aligned in reset group)
    row.resetValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.resetValue:SetPoint("LEFT", row, "LEFT", LS_RESET_X + LS_COL_COUNT, 0)
    row.resetValue:SetWidth(LS_COL_VALUE)
    row.resetValue:SetJustifyH("LEFT")
    -- AllTime count (left-aligned in alltime group)
    row.alltimeCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.alltimeCount:SetPoint("LEFT", row, "LEFT", LS_ALLTIME_X, 0)
    row.alltimeCount:SetWidth(LS_COL_COUNT)
    row.alltimeCount:SetJustifyH("LEFT")
    -- AllTime value (left-aligned in alltime group)
    row.alltimeValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.alltimeValue:SetPoint("LEFT", row, "LEFT", LS_ALLTIME_X + LS_COL_COUNT, 0)
    row.alltimeValue:SetWidth(LS_COL_VALUE)
    row.alltimeValue:SetJustifyH("LEFT")
    -- Drop % (optional column, positioned dynamically)
    row.dropPercent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dropPercent:SetWidth(LS_COL_DROP)
    row.dropPercent:SetJustifyH("RIGHT")
    row.dropPercent:Hide()
    return row
end

local function PopulateLootSummary()
    local container = lootSumChild
    local isHistory = ns.lootSummaryHistoryMode and ns.lootSummaryHistoryPage > 0
    local resetLoot, allTimeLoot, globalPrices, globalPerBeast, globalPerBeastReset

    if isHistory then
        -- Aggregate history from all characters for the given page
        resetLoot = {}
        globalPrices = {}
        globalPerBeastReset = {}
        local histDate = nil
        ns.EnsureDB()
        for _, charData in pairs(MajesticBeastTrackerDB.chars) do
            if charData.loot and charData.loot.history then
                local entry = charData.loot.history[ns.lootSummaryHistoryPage]
                if entry then
                    if not histDate then histDate = entry.date end
                    for id, count in pairs(entry.items or {}) do
                        resetLoot[id] = (resetLoot[id] or 0) + count
                    end
                    if entry.prices then
                        for id, price in pairs(entry.prices) do
                            if not globalPrices[id] then globalPrices[id] = price end
                        end
                    end
                    if entry.perBeast then
                        for beastName, items in pairs(entry.perBeast) do
                            if not globalPerBeastReset[beastName] then globalPerBeastReset[beastName] = {} end
                            for id, count in pairs(items) do
                                globalPerBeastReset[beastName][id] = (globalPerBeastReset[beastName][id] or 0) + count
                            end
                        end
                    end
                end
            end
        end
        -- All time still from live data
        _, allTimeLoot, _, globalPerBeast = ns.GetGlobalLoot()
        -- Show/hide pagination
        lsPageLeft:Show()
        lsPageRight:Show()
        UpdateExportAnchor()
        lootSumTitle:SetText("History — " .. (histDate or "No data"))
        if not next(resetLoot) then
            for _, row in ipairs(ns.lootSummary.rows) do row:Hide() end
            lootSumTitle:SetText("History — No data for this day")
            ns.lootSummary:SetSize(LOOT_SUMMARY_WIDTH, 40)
            return
        end
    else
        local globalTrackedKills, globalTrackedPerBeast
        resetLoot, allTimeLoot, globalPrices, globalPerBeast, globalPerBeastReset, globalTrackedKills, globalTrackedPerBeast = ns.GetGlobalLoot()
        ns._lsTrackedKills = globalTrackedKills
        ns._lsTrackedPerBeast = globalTrackedPerBeast
        lsPageLeft:Hide()
        lsPageRight:Hide()
        UpdateExportAnchor()
        if not resetLoot and not allTimeLoot then
            for _, row in ipairs(ns.lootSummary.rows) do row:Hide() end
            lootSumTitle:SetText("Loot Summary — No data yet")
            ns.lootSummary:SetSize(LOOT_SUMMARY_WIDTH, 40)
            return
        end
        lootSumTitle:SetText("Loot Summary")
    end

    local hasTSM = TSM_API ~= nil

    local resetItems, resetTotal = BuildItemList(resetLoot, globalPrices)
    local allTimeItems, allTimeTotal = BuildItemList(allTimeLoot, globalPrices)

    -- Collect all unique item keys
    local allNames = {}
    local nameSet = {}
    for _, item in ipairs(resetItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    for _, item in ipairs(allTimeItems) do
        if not nameSet[item.sortKey] then nameSet[item.sortKey] = true; allNames[#allNames + 1] = item.sortKey end
    end
    table.sort(allNames)

    local resetByKey = {}
    for _, item in ipairs(resetItems) do resetByKey[item.sortKey] = item end
    local allTimeByKey = {}
    for _, item in ipairs(allTimeItems) do allTimeByKey[item.sortKey] = item end

    -- Measure widest item name for dynamic column width
    local measureFS = lootSumTitle
    local maxNameW = LS_COL_ITEM
    for _, key in ipairs(allNames) do
        local ref = allTimeByKey[key] or resetByKey[key]
        if ref then
            measureFS:SetText(ref.name)
            local w = measureFS:GetStringWidth()
            if w and w > maxNameW then maxNameW = w end
        end
    end
    measureFS:SetText("Loot Summary")
    maxNameW = math.min(maxNameW + 8, 250)

    local dynResetX = 8 + maxNameW + LS_COL_GAP
    local dynAlltimeX = dynResetX + LS_COL_COUNT + LS_COL_VALUE + LS_COL_GAP
    local dynWidth = 8 + maxNameW + LS_COL_GAP + (LS_COL_COUNT + LS_COL_VALUE) * 2 + LS_COL_GAP + 32

    local idx = 0
    local yOff = -2

    -- Header row
    idx = idx + 1
    local headerRow = ns.lootSummary.rows[idx]
    if not headerRow then
        headerRow = CreateLootSummaryRow(container)
        ns.lootSummary.rows[idx] = headerRow
    end
    headerRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
    headerRow:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)
    headerRow.item:SetText("")
    headerRow.item:SetWidth(maxNameW)
    headerRow.resetCount:SetText("|cffffd700Reset|r")
    headerRow.resetCount:ClearAllPoints()
    headerRow.resetCount:SetPoint("LEFT", headerRow, "LEFT", dynResetX, 0)
    headerRow.resetValue:SetText("")
    headerRow.alltimeCount:SetText("|cffffd700All Time|r")
    headerRow.alltimeCount:ClearAllPoints()
    headerRow.alltimeCount:SetPoint("LEFT", headerRow, "LEFT", dynAlltimeX, 0)
    headerRow.alltimeValue:SetText("")
    -- Drop % header (only when not in history mode and tracked kills exist)
    local showDropPct = not isHistory and MajesticBeastTrackerDB.settings.showDropPercent and ns._lsTrackedKills and next(ns._lsTrackedKills)
    local dynDropX = dynAlltimeX + LS_COL_COUNT + LS_COL_VALUE + LS_COL_GAP
    if showDropPct then
        headerRow.dropPercent:ClearAllPoints()
        headerRow.dropPercent:SetPoint("LEFT", headerRow, "LEFT", dynDropX, 0)
        headerRow.dropPercent:SetText("|cffffd700Drop %|r")
        headerRow.dropPercent:Show()
        dynWidth = dynWidth + LS_COL_DROP + LS_COL_GAP
    else
        headerRow.dropPercent:Hide()
    end
    -- Build reverse map: itemID → beast names (for drop % lookup)
    local itemToBeast = {}
    if showDropPct then
        for beastName, items in pairs(ns.BEAST_LOOT) do
            for _, id in ipairs(items) do
                if not itemToBeast[id] then itemToBeast[id] = {} end
                itemToBeast[id][#itemToBeast[id] + 1] = beastName
            end
        end
    end
    headerRow:Show()
    yOff = yOff - LOOT_SUMMARY_ROW_HEIGHT

    yOff = yOff - 2

    -- Item rows — one row per item, 3 columns
    for _, key in ipairs(allNames) do
        local ri = resetByKey[key]
        local ai = allTimeByKey[key]
        if ai or ri then
            idx = idx + 1
            local row = ns.lootSummary.rows[idx]
            if not row then
                row = CreateLootSummaryRow(container)
                ns.lootSummary.rows[idx] = row
            end
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
            row:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)

            -- Item name (use alltime or reset data)
            local ref = ai or ri
            row.item:SetText(ref.name)
            row.item:SetTextColor(ref.r, ref.g, ref.b)
            row.item:SetWidth(maxNameW)

            -- This Reset: count + value
            row.resetCount:ClearAllPoints()
            row.resetCount:SetPoint("LEFT", row, "LEFT", dynResetX, 0)
            row.resetValue:ClearAllPoints()
            row.resetValue:SetPoint("LEFT", row, "LEFT", dynResetX + LS_COL_COUNT, 0)
            if ri then
                row.resetCount:SetText("x" .. ri.count)
                row.resetCount:SetTextColor(0.9, 0.9, 0.9)
                row.resetValue:SetText(ri.priceText ~= "" and ri.priceText or "")
                row.resetValue:SetTextColor(0.9, 0.9, 0.9)
            else
                row.resetCount:SetText("|cff666666—|r")
                row.resetCount:SetTextColor(0.4, 0.4, 0.4)
                row.resetValue:SetText("")
            end

            -- All Time: count + value
            row.alltimeCount:ClearAllPoints()
            row.alltimeCount:SetPoint("LEFT", row, "LEFT", dynAlltimeX, 0)
            row.alltimeValue:ClearAllPoints()
            row.alltimeValue:SetPoint("LEFT", row, "LEFT", dynAlltimeX + LS_COL_COUNT, 0)
            if ai then
                row.alltimeCount:SetText("x" .. ai.count)
                row.alltimeCount:SetTextColor(0.9, 0.9, 0.9)
                row.alltimeValue:SetText(ai.priceText ~= "" and ai.priceText or "")
                row.alltimeValue:SetTextColor(0.9, 0.9, 0.9)
            else
                row.alltimeCount:SetText("")
                row.alltimeValue:SetText("")
            end

            -- Drop % column
            if showDropPct and ref and ref.itemID then
                local beasts = itemToBeast[ref.itemID]
                if beasts then
                    local totalKills = 0
                    local totalDrops = 0
                    for _, beastName in ipairs(beasts) do
                        totalKills = totalKills + (ns._lsTrackedKills[beastName] or 0)
                        if ns._lsTrackedPerBeast and ns._lsTrackedPerBeast[beastName] then
                            totalDrops = totalDrops + (ns._lsTrackedPerBeast[beastName][ref.itemID] or 0)
                        end
                    end
                    row.dropPercent:ClearAllPoints()
                    row.dropPercent:SetPoint("LEFT", row, "LEFT", dynDropX, 0)
                    if totalKills > 0 then
                        local pct = (totalDrops / totalKills) * 100
                        row.dropPercent:SetText(FormatDropRate(pct))
                        row.dropPercent:SetTextColor(0.7, 0.9, 1)
                    else
                        row.dropPercent:SetText("-")
                        row.dropPercent:SetTextColor(0.4, 0.4, 0.4)
                    end
                    row.dropPercent:Show()
                else
                    row.dropPercent:Hide()
                end
            else
                row.dropPercent:Hide()
            end

            row:Show()
            yOff = yOff - LOOT_SUMMARY_ROW_HEIGHT
        end
    end

    -- Value totals
    if hasTSM and (resetTotal > 0 or allTimeTotal > 0) then
        yOff = yOff - 4

        idx = idx + 1
        local totalRow = ns.lootSummary.rows[idx]
        if not totalRow then
            totalRow = CreateLootSummaryRow(container)
            ns.lootSummary.rows[idx] = totalRow
        end
        totalRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
        totalRow:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)
        totalRow.item:SetText("|cffffd700Value:|r")
        totalRow.item:SetWidth(maxNameW)
        totalRow.resetCount:ClearAllPoints()
        totalRow.resetCount:SetPoint("LEFT", totalRow, "LEFT", dynResetX, 0)
        totalRow.resetCount:SetText("")
        totalRow.resetValue:ClearAllPoints()
        totalRow.resetValue:SetPoint("LEFT", totalRow, "LEFT", dynResetX + LS_COL_COUNT, 0)
        totalRow.resetValue:SetText(resetTotal > 0 and ("|cffffd700" .. ns.FormatGoldPositive(resetTotal) .. "|r") or "")
        totalRow.alltimeCount:ClearAllPoints()
        totalRow.alltimeCount:SetPoint("LEFT", totalRow, "LEFT", dynAlltimeX, 0)
        totalRow.alltimeCount:SetText("")
        totalRow.alltimeValue:ClearAllPoints()
        totalRow.alltimeValue:SetPoint("LEFT", totalRow, "LEFT", dynAlltimeX + LS_COL_COUNT, 0)
        totalRow.alltimeValue:SetText(allTimeTotal > 0 and ("|cffffd700" .. ns.FormatGoldPositive(allTimeTotal) .. "|r") or "")
        totalRow:Show()
        yOff = yOff - LOOT_SUMMARY_ROW_HEIGHT
    end

    -- Per-beast breakdown (only if toggle is on)
    if ns.lootSummaryShowBreakdown and (globalPerBeastReset or globalPerBeast) then
        -- Divider between summary and breakdown
        yOff = yOff - 2
        idx = idx + 1
        local divRow = ns.lootSummary.rows[idx]
        if not divRow or not divRow.item then
            divRow = CreateLootSummaryRow(container)
            ns.lootSummary.rows[idx] = divRow
        end
        divRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
        divRow:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)
        divRow.item:SetText("|cff555555" .. string.rep("—", 60) .. "|r")
        divRow.item:SetWidth(dynWidth)
        divRow.resetCount:SetText("")
        divRow.resetValue:SetText("")
        divRow.alltimeCount:SetText("")
        divRow.alltimeValue:SetText("")
        divRow.dropPercent:Hide()
        divRow:Show()
        yOff = yOff - 10
        local perResetData = globalPerBeastReset or {}
        local perAllTimeData = globalPerBeast or {}

        for _, lure in ipairs(LURES) do
            local resetBl = perResetData[lure.name]
            local allTimeBl = perAllTimeData[lure.name]
            local hasReset = resetBl and next(resetBl)
            local hasAllTime = allTimeBl and next(allTimeBl)
            if hasReset or hasAllTime then
                -- Space before beast header (no separator frame to avoid scroll rendering glitch)
                yOff = yOff - 8

                idx = idx + 1
                local beastHeader = ns.lootSummary.rows[idx]
                if not beastHeader then
                    beastHeader = CreateLootSummaryRow(container)
                    ns.lootSummary.rows[idx] = beastHeader
                end
                beastHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
                beastHeader:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)
                beastHeader.item:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
                beastHeader.item:SetWidth(dynWidth - 16)
                -- Localized header: "Zone - NPC Name"
                local zoneName = lure.name
                if lure.waypoint and lure.waypoint.map then
                    local mapInfo = C_Map.GetMapInfo(lure.waypoint.map)
                    if mapInfo and mapInfo.name then zoneName = mapInfo.name end
                end
                local npcName = ""
                if lure.npcID then
                    -- Create hidden tooltip to scan NPC name
                    if not ns._npcTooltip then
                        ns._npcTooltip = CreateFrame("GameTooltip", "MBT_NPCTooltip", nil, "GameTooltipTemplate")
                        ns._npcTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
                    end
                    ns._npcTooltip:SetHyperlink("unit:Creature-0-0-0-0-" .. lure.npcID .. "-0")
                    local line1 = _G["MBT_NPCTooltipTextLeft1"]
                    if line1 then
                        local text = line1:GetText()
                        if text and text ~= "" then npcName = text end
                    end
                    ns._npcTooltip:ClearLines()
                end
                local headerText = zoneName
                if npcName ~= "" then headerText = headerText .. " — " .. npcName end
                beastHeader.item:SetText(lure.color .. headerText .. "|r")
                beastHeader.resetCount:SetText("")
                beastHeader.resetValue:SetText("")
                beastHeader.alltimeCount:SetText("")
                beastHeader.alltimeValue:SetText("")
                beastHeader.dropPercent:Hide()
                beastHeader:Show()
                yOff = yOff - LOOT_SUMMARY_ROW_HEIGHT - 2
                -- Reset font for item rows back to small after header
                -- (header uses 11pt, items use default 9pt from CreateLootSummaryRow)

                local allIDs = {}
                local idSet = {}
                for id in pairs(allTimeBl or {}) do if not idSet[id] then idSet[id] = true; allIDs[#allIDs + 1] = id end end
                for id in pairs(resetBl or {}) do if not idSet[id] then idSet[id] = true; allIDs[#allIDs + 1] = id end end
                table.sort(allIDs, function(a, b)
                    return GetCachedItemName(a) < GetCachedItemName(b)
                end)

                for _, id in ipairs(allIDs) do
                    local name = GetCachedItemName(id)
                    local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
                    if quality and quality > 0 then
                        name = name .. " |A:Professions-ChatIcon-Quality-12-Tier" .. quality .. ":12:12::1|a"
                    end
                    local r, g, b = 0.9, 0.9, 0.9
                    local itemQuality = select(3, C_Item.GetItemInfo(id))
                    if itemQuality then
                        local color = ITEM_QUALITY_COLORS[itemQuality]
                        if color then r, g, b = color.r, color.g, color.b end
                    end
                    local rc = resetBl and resetBl[id]
                    local ac = allTimeBl and allTimeBl[id]

                    idx = idx + 1
                    local beastRow = ns.lootSummary.rows[idx]
                    if not beastRow then
                        beastRow = CreateLootSummaryRow(container)
                        ns.lootSummary.rows[idx] = beastRow
                    end
                    beastRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
                    beastRow:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOff)
                    beastRow.item:SetFont(beastRow.item:GetFont(), 9)
                    beastRow.item:SetText(name)
                    beastRow.item:SetTextColor(r, g, b)
                    beastRow.item:SetWidth(maxNameW)
                    beastRow.resetCount:ClearAllPoints()
                    beastRow.resetCount:SetPoint("LEFT", beastRow, "LEFT", dynResetX, 0)
                    beastRow.resetCount:SetText(rc and ("x" .. rc) or "|cff666666—|r")
                    beastRow.resetCount:SetTextColor(rc and 0.9 or 0.4, rc and 0.9 or 0.4, rc and 0.9 or 0.4)
                    beastRow.resetValue:SetText("")
                    beastRow.alltimeCount:ClearAllPoints()
                    beastRow.alltimeCount:SetPoint("LEFT", beastRow, "LEFT", dynAlltimeX, 0)
                    beastRow.alltimeCount:SetText(ac and ("x" .. ac) or "")
                    beastRow.alltimeCount:SetTextColor(0.9, 0.9, 0.9)
                    beastRow.alltimeValue:SetText("")
                    -- Drop % per beast (more accurate than combined)
                    if showDropPct then
                        local beastKills = ns._lsTrackedKills and ns._lsTrackedKills[lure.name] or 0
                        local trackedCount = ns._lsTrackedPerBeast and ns._lsTrackedPerBeast[lure.name] and ns._lsTrackedPerBeast[lure.name][id] or 0
                        beastRow.dropPercent:ClearAllPoints()
                        beastRow.dropPercent:SetPoint("LEFT", beastRow, "LEFT", dynDropX, 0)
                        if beastKills > 0 then
                            local pct = (trackedCount / beastKills) * 100
                            beastRow.dropPercent:SetText(FormatDropRate(pct))
                            beastRow.dropPercent:SetTextColor(0.7, 0.9, 1)
                        else
                            beastRow.dropPercent:SetText("-")
                            beastRow.dropPercent:SetTextColor(0.4, 0.4, 0.4)
                        end
                        beastRow.dropPercent:Show()
                    else
                        beastRow.dropPercent:Hide()
                    end
                    beastRow:Show()
                    yOff = yOff - LOOT_SUMMARY_ROW_HEIGHT
                end
            end
        end
    end

    -- Hide unused rows
    for i = idx + 1, #ns.lootSummary.rows do
        ns.lootSummary.rows[i]:Hide()
    end

    -- Drop % bottom bar (fixed, not scrollable)
    local lsFooterHeight = 0
    if showDropPct then
        local totalTracked = 0
        for _, k in pairs(ns._lsTrackedKills) do totalTracked = totalTracked + k end
        if not ns._lsFooterBar then
            local bar = CreateFrame("Frame", nil, ns.lootSummary, "BackdropTemplate")
            bar:SetHeight(18)
            bar:SetPoint("BOTTOMLEFT", ns.lootSummary, "BOTTOMLEFT", 4, 4)
            bar:SetPoint("BOTTOMRIGHT", ns.lootSummary, "BOTTOMRIGHT", -4, 4)
            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.4)
            local sep = bar:CreateTexture(nil, "ARTWORK")
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", bar, "TOPLEFT")
            sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
            sep:SetColorTexture(0.82, 0.71, 0.35, 0.3)
            local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetFont(text:GetFont(), 8)
            text:SetPoint("CENTER", bar, "CENTER", 0, 0)
            text:SetTextColor(0.7, 0.65, 0.5)
            bar.text = text
            ns._lsFooterBar = bar
        end
        ns._lsFooterBar.text:SetText("Drop % based on " .. totalTracked .. " tracked kills — data collected from v2.0.1 onwards")
        ns._lsFooterBar:Show()
        lsFooterHeight = 22
    else
        if ns._lsFooterBar then ns._lsFooterBar:Hide() end
    end

    local contentH = math.abs(yOff) + 8
    lootSumChild:SetHeight(contentH)
    lootSumChild:SetWidth(dynWidth - 24)
    local windowH = math.min(contentH + lsHeaderHeight + 4 + lsFooterHeight, LOOT_SUMMARY_MAX_HEIGHT)
    ns.lootSummary:SetSize(dynWidth, windowH)
    -- Adjust scroll area to not overlap footer bar
    lootSumScroll:SetPoint("BOTTOMRIGHT", ns.lootSummary, "BOTTOMRIGHT", -12, 4 + lsFooterHeight)
    ns.lootSummary._dynWidth = dynWidth

end

ns._populateLootSummary = PopulateLootSummary

local function RepositionLootSummary()
    ns.lootSummary:ClearAllPoints()
    local w = ns.lootSummary._dynWidth or LOOT_SUMMARY_WIDTH
    local frameRight = ns.frame:GetRight() or 0
    local screenWidth = GetScreenWidth()
    if frameRight + w + 8 > screenWidth then
        ns.lootSummary:SetPoint("TOPRIGHT", ns.frame, "TOPLEFT", -4, 0)
    else
        ns.lootSummary:SetPoint("TOPLEFT", ns.frame, "TOPRIGHT", 4, 0)
    end
end
ns.RepositionLootSummary = RepositionLootSummary

function ns.ToggleLootSummary()
    if ns.lootSummary:IsShown() then
        ns.lootSummary:Hide()
    else
        -- Hide loot editor when summary opens (same space)
        if ns.lootEditor and ns.lootEditor:IsShown() then
            ns.lootEditor:Hide()
        end
        PopulateLootSummary()
        RepositionLootSummary()
        ns.lootSummary:Show()
    end
end

------------------------------------------------------
-- CSV Import
-- Format: Date,Character,Beast,Item ID,Item,Quality,Count,Unit Price,Value,Active Buffs
-- Only fills empty data — does NOT overwrite existing values
------------------------------------------------------

function ns.ImportCSV(text, appendMode)
    if not text then return 0, 0 end
    ns.EnsureDB()

    local imported, skipped = 0, 0
    local lines = { strsplit("\n", text) }

    -- Build beast name lookup
    local beastNames = {}
    for _, lure in ipairs(LURES) do
        beastNames[lure.name] = true
    end

    local section = "loot"  -- "characters" or "loot"

    for _, line in ipairs(lines) do
        if line == "#Characters" then section = "characters"
        elseif line == "#Loot" then section = "loot"
        elseif section == "characters" and line and #line > 3 and not line:match("^Character,") then
            -- Parse character metadata: Character,Class,Level,Hidden
            local fields = { strsplit(",", line) }
            local charKey = fields[1]
            local class = fields[2]
            local level = tonumber(fields[3]) or 0
            local hidden = fields[4] == "yes"
            if charKey and class then
                if not MajesticBeastTrackerDB.chars[charKey] then
                    MajesticBeastTrackerDB.chars[charKey] = {
                        hasSkinning = true,
                        class = class,
                        level = level,
                        talentPoints = 0,
                        lures = {},
                        loot = { thisReset = {}, allTime = {}, resetTime = 0 },
                    }
                    imported = imported + 1
                else
                    -- Update class/level if UNKNOWN
                    local cd = MajesticBeastTrackerDB.chars[charKey]
                    if cd.class == "UNKNOWN" and class ~= "UNKNOWN" then cd.class = class end
                    if (cd.level or 0) == 0 and level > 0 then cd.level = level end
                end
                -- Set hidden status
                if hidden then
                    if not MajesticBeastTrackerDB.settings.hiddenChars then
                        MajesticBeastTrackerDB.settings.hiddenChars = {}
                    end
                    MajesticBeastTrackerDB.settings.hiddenChars[charKey] = true
                end
            end
        elseif section == "loot" and line and #line > 10 and not line:match("^Date,") then
            local fields = { strsplit(",", line) }
            local dateStr = fields[1]
            local charKey = fields[2]
            local beast = fields[3]
            local itemID = tonumber(fields[4])
            local count = tonumber(fields[7])
            local unitPriceGold = tonumber(fields[8]) or 0  -- gold, convert to copper
            local unitPrice = unitPriceGold * 10000

            if dateStr and charKey and itemID and count and count > 0 then
                -- Ensure character exists in DB
                if not MajesticBeastTrackerDB.chars[charKey] then
                    MajesticBeastTrackerDB.chars[charKey] = {
                        hasSkinning = true,
                        class = "UNKNOWN",
                        level = 0,
                        talentPoints = 0,
                        lures = {},
                        loot = { thisReset = {}, allTime = {}, resetTime = 0 },
                    }
                end
                local charData = MajesticBeastTrackerDB.chars[charKey]
                if not charData.loot then
                    charData.loot = { thisReset = {}, allTime = {}, resetTime = 0 }
                end

                local resetDate = ns.GetResetDate()

                if dateStr == "AllTime" then
                    -- AllTime remainder: exported as (allTime - sum of history)
                    -- Always add to allTime — this represents untracked pre-history data
                    charData.loot.allTime = charData.loot.allTime or {}
                    charData.loot.allTime[itemID] = (charData.loot.allTime[itemID] or 0) + count
                    imported = imported + 1
                elseif dateStr == resetDate then
                    -- Current reset: import into thisReset
                    if not charData.loot.thisReset then charData.loot.thisReset = {} end
                    local existing = charData.loot.thisReset[itemID] or 0
                    if existing == 0 or appendMode then
                        charData.loot.thisReset[itemID] = (appendMode and existing or 0) + count
                        charData.loot.allTime[itemID] = (charData.loot.allTime[itemID] or 0) + count
                        -- Import price if available and not already set
                        if unitPrice > 0 then
                            if not charData.loot.prices then charData.loot.prices = {} end
                            if not charData.loot.prices[itemID] then
                                charData.loot.prices[itemID] = unitPrice
                            end
                        end
                        -- Per-beast if applicable
                        if beast and beast ~= "All" and beastNames[beast] then
                            if not charData.loot.perBeastReset then charData.loot.perBeastReset = {} end
                            if not charData.loot.perBeastReset[beast] then charData.loot.perBeastReset[beast] = {} end
                            if (charData.loot.perBeastReset[beast][itemID] or 0) == 0 then
                                charData.loot.perBeastReset[beast][itemID] = count
                            end
                            if not charData.loot.perBeast then charData.loot.perBeast = {} end
                            if not charData.loot.perBeast[beast] then charData.loot.perBeast[beast] = {} end
                            charData.loot.perBeast[beast][itemID] = (charData.loot.perBeast[beast][itemID] or 0) + count
                        end
                        imported = imported + 1
                    else
                        skipped = skipped + 1
                    end
                else
                    -- Historical: find or create history entry for this date
                    if not charData.loot.history then charData.loot.history = {} end
                    local histEntry
                    for _, entry in ipairs(charData.loot.history) do
                        if entry.date == dateStr then
                            histEntry = entry
                            break
                        end
                    end
                    if not histEntry then
                        histEntry = { date = dateStr, items = {}, perBeast = {} }
                        -- Insert in chronological order (newest first)
                        local inserted = false
                        for idx, entry in ipairs(charData.loot.history) do
                            if dateStr > entry.date then
                                table.insert(charData.loot.history, idx, histEntry)
                                inserted = true
                                break
                            end
                        end
                        if not inserted then
                            table.insert(charData.loot.history, histEntry)
                        end
                    end

                    -- Only fill if empty (0 or nil), or append if appendMode
                    local existingHist = histEntry.items[itemID] or 0
                    if existingHist == 0 or appendMode then
                        histEntry.items[itemID] = (appendMode and existingHist or 0) + count
                        -- Per-beast
                        if beast and beast ~= "All" and beastNames[beast] then
                            if not histEntry.perBeast then histEntry.perBeast = {} end
                            if not histEntry.perBeast[beast] then histEntry.perBeast[beast] = {} end
                            if (histEntry.perBeast[beast][itemID] or 0) == 0 then
                                histEntry.perBeast[beast][itemID] = count
                            end
                        end
                        -- Also add to allTime
                        charData.loot.allTime = charData.loot.allTime or {}
                        charData.loot.allTime[itemID] = (charData.loot.allTime[itemID] or 0) + count
                        -- Import price into history entry
                        if unitPrice > 0 then
                            if not histEntry.prices then histEntry.prices = {} end
                            if not histEntry.prices[itemID] then
                                histEntry.prices[itemID] = unitPrice
                            end
                        end
                        imported = imported + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end

    -- Trim history to 90 days
    for _, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.loot and charData.loot.history then
            while #charData.loot.history > 90 do
                table.remove(charData.loot.history)
            end
        end
    end

    return imported, skipped
end
