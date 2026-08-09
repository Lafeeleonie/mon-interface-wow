------------------------------------------------------
-- MajesticBeastTracker UI - Lure Header Icons
-- Header lure icons, zone labels, reagent icons,
-- lure column border boxes, TSM price labels
------------------------------------------------------

local _, ns = ...

local LURES = ns.LURES
local frame = ns.frame
local ICON_SIZE = ns.ICON_SIZE
local COL_WIDTH = ns.COL_WIDTH
local NAME_COL_WIDTH = ns.NAME_COL_WIDTH
local PAD = ns.PAD
local REAGENT_ICON_SIZE = ns.REAGENT_ICON_SIZE
local REAGENT_COUNT_HEIGHT = ns.REAGENT_COUNT_HEIGHT
local REAGENT_GAP = ns.REAGENT_GAP
local REAGENT_ROW_HEIGHT = ns.REAGENT_ROW_HEIGHT
local ICON_ROW_HEIGHT = ns.ICON_ROW_HEIGHT
local TOOLBAR_HEIGHT = ns.TOOLBAR_HEIGHT
local TITLE_HEIGHT = ns.TITLE_HEIGHT
local C_BORDER_RGB = ns.C_BORDER_RGB
local C_SEPARATOR = { 0.82, 0.71, 0.35, 0.3 }

local contentTop = ns.contentTop

------------------------------------------------------
-- Header icons (lures) - SecureActionButton for item use
------------------------------------------------------

local headerIcons = {}
for i, lure in ipairs(LURES) do
    local iconFrame = CreateFrame("Button", "MBT_LureIcon" .. i, frame, "SecureActionButtonTemplate")
    iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PAD + 4 + NAME_COL_WIDTH + (i - 1) * COL_WIDTH + (COL_WIDTH - ICON_SIZE) / 2,
        contentTop - 2 - REAGENT_ROW_HEIGHT)
    iconFrame:SetAttribute("type", "item")
    iconFrame:SetAttribute("item", lure.name)
    iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    -- Cache item name async
    C_Item.RequestLoadItemDataByID(lure.itemID)
    local lureTicker
    lureTicker = C_Timer.NewTicker(1, function()
        local itemName = C_Item.GetItemNameByID(lure.itemID)
        if itemName and not InCombatLockdown() then
            iconFrame:SetAttribute("item", itemName)
            lureTicker:Cancel()
        end
    end, 10)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon = icon

    -- Lure count text (bottom-right corner of icon)
    local countText = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 1)
    countText:SetJustifyH("RIGHT")
    countText:SetText("")
    iconFrame.countText = countText

    -- Glow border (yellow when lure in bags + usable)
    local glowSize = 2
    local glowColor = {1, 0.75, 0, 0.9}
    local gT = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    gT:SetPoint("TOPLEFT", icon, "TOPLEFT", -glowSize, glowSize)
    gT:SetPoint("TOPRIGHT", icon, "TOPRIGHT", glowSize, glowSize)
    gT:SetHeight(glowSize)
    gT:SetColorTexture(unpack(glowColor))
    local gB = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    gB:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -glowSize, -glowSize)
    gB:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", glowSize, -glowSize)
    gB:SetHeight(glowSize)
    gB:SetColorTexture(unpack(glowColor))
    local gL = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    gL:SetPoint("TOPLEFT", icon, "TOPLEFT", -glowSize, glowSize)
    gL:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -glowSize, -glowSize)
    gL:SetWidth(glowSize)
    gL:SetColorTexture(unpack(glowColor))
    local gR = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    gR:SetPoint("TOPRIGHT", icon, "TOPRIGHT", glowSize, glowSize)
    gR:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", glowSize, -glowSize)
    gR:SetWidth(glowSize)
    gR:SetColorTexture(unpack(glowColor))
    local lureGlowParts = {gT, gB, gL, gR}
    for _, g in ipairs(lureGlowParts) do g:Hide() end
    iconFrame.glow = {
        Show = function() for _, g in ipairs(lureGlowParts) do g:Show() end end,
        Hide = function() for _, g in ipairs(lureGlowParts) do g:Hide() end end,
    }

    -- Hover border highlight
    local hlSize = 1
    local hlColor = {1, 0.84, 0, 0.7}
    for _, edge in ipairs({
        {"TOPLEFT", "TOPRIGHT", hlSize, true},
        {"BOTTOMLEFT", "BOTTOMRIGHT", hlSize, true},
        {"TOPLEFT", "BOTTOMLEFT", hlSize, false},
        {"TOPRIGHT", "BOTTOMRIGHT", hlSize, false},
    }) do
        local hl = iconFrame:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(unpack(hlColor))
        if edge[4] then -- horizontal
            hl:SetPoint(edge[1], icon, edge[1], -hlSize, hlSize)
            hl:SetPoint(edge[2], icon, edge[2], hlSize, hlSize)
            hl:SetHeight(hlSize)
        else -- vertical
            hl:SetPoint(edge[1], icon, edge[1], -hlSize, hlSize)
            hl:SetPoint(edge[2], icon, edge[2], -hlSize, -hlSize)
            hl:SetWidth(hlSize)
        end
    end

    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        local r, g, b = unpack(lure.colorRGB)
        GameTooltip:AddLine(lure.name, r, g, b)
        GameTooltip:AddLine(lure.requiredPoints .. " pts required", 0.6, 0.6, 0.6)
        local lureBagName = C_Item.GetItemNameByID(lure.itemID)
        local bags = lureBagName and C_Item.GetItemCount(lureBagName) or C_Item.GetItemCount(lure.itemID)
        if bags > 0 then
            GameTooltip:AddLine("In bags: " .. bags, 1, 1, 1)
        end
        -- AH price comparison: lure craft cost vs majestic drop values (TSM or Auctionator)
        if ns.GetAHPrice then
            local craftCost, costComplete = 0, true
            if lure.reagents then
                for _, reagent in ipairs(lure.reagents) do
                    local p = ns.GetAHPrice(reagent.itemID)
                    if p then craftCost = craftCost + p * reagent.count else costComplete = false end
                end
            end
            local drops = {}
            local majestics = ns.MAJESTIC_LOOT and ns.MAJESTIC_LOOT[lure.name]
            if majestics then
                for _, id in ipairs(majestics) do
                    local itemName = C_Item.GetItemNameByID(id)
                    if not itemName then C_Item.RequestLoadItemDataByID(id) end
                    local p = ns.GetAHPrice(id)
                    if itemName and p then
                        drops[#drops + 1] = { name = itemName, price = p }
                    end
                end
                table.sort(drops, function(a, b) return a.price > b.price end)
            end
            if (costComplete and craftCost > 0) or #drops > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("AH Prices", 1, 0.84, 0)
                if costComplete and craftCost > 0 then
                    GameTooltip:AddDoubleLine("Lure craft cost", ns.FormatGold(craftCost), 0.8, 0.8, 0.8, 1, 1, 1)
                end
                for _, d in ipairs(drops) do
                    GameTooltip:AddDoubleLine(d.name, ns.FormatGold(d.price), 0.64, 0.21, 0.93, 0.2, 0.9, 0.4)
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: Use lure", 0.5, 0.8, 1)
        GameTooltip:AddLine("Shift-click: Open recipe / Craft", 0.5, 0.8, 1)
        GameTooltip:AddLine("Right-click: Set waypoint", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PreClick: shift = open recipe (block item use), right = waypoint (block item use)
    iconFrame:SetScript("PreClick", function(self, button)
        if InCombatLockdown() then return end
        if button == "RightButton" or IsShiftKeyDown() then
            self:SetAttribute("type", nil)
        end
    end)
    iconFrame:SetScript("PostClick", function(self, button)
        -- Restore secure type
        if not InCombatLockdown() then
            self:SetAttribute("type", "item")
        end
        if IsShiftKeyDown() and button == "LeftButton" then
            local now = GetTime()
            -- Throttle AnyUp/AnyDown pair (< 0.1s apart)
            if (now - (self._lastPostClick or 0)) < 0.1 then return end
            self._lastPostClick = now
            if lure.recipeID then
                if C_TradeSkillUI.IsTradeSkillReady() then
                    C_TradeSkillUI.CraftRecipe(lure.recipeID)
                else
                    C_TradeSkillUI.OpenRecipe(lure.recipeID)
                end
            end
        elseif button == "RightButton" then
            local now = GetTime()
            if (now - (self._lastWaypoint or 0)) < 0.5 then return end
            self._lastWaypoint = now
            local wp = lure.waypoint
            if wp then
                local mapPoint = UiMapPoint.CreateFromCoordinates(wp.map, wp.x, wp.y)
                C_Map.SetUserWaypoint(mapPoint)
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                    print("|cff3FC7EB[MBT]|r Waypoint set: " .. lure.color .. lure.name .. "|r")
                end
            end
        end
    end)
    headerIcons[i] = iconFrame
end

------------------------------------------------------
-- Zone labels below lure icons
------------------------------------------------------

local zoneLabels = {}
for i, lure in ipairs(LURES) do
    local zLabel = headerIcons[i]:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zLabel:SetFont(zLabel:GetFont(), 9)
    local r, g, b = unpack(lure.colorRGB)
    zLabel:SetTextColor(r, g, b, 0.8)
    zLabel:SetText(lure.name)
    zLabel:SetJustifyH("CENTER")
    zLabel:SetPoint("TOP", headerIcons[i], "BOTTOM", 0, -1)
    zoneLabels[i] = zLabel
end

------------------------------------------------------
-- Reagent icons (small icons above each lure header)
------------------------------------------------------

local reagentIcons = {}  -- reagentIcons[lureIndex] = { icon1, icon2, ... }
for i, lure in ipairs(LURES) do
    reagentIcons[i] = {}
    if lure.reagents then
        local numReagents = #lure.reagents
        for j, reagent in ipairs(lure.reagents) do
            local rBtn = CreateFrame("Button", "MBT_ReagentIcon" .. i .. "_" .. j, frame)
            rBtn:SetSize(REAGENT_ICON_SIZE, REAGENT_ICON_SIZE)
            local lureCenter = PAD + 4 + NAME_COL_WIDTH + (i - 1) * COL_WIDTH + COL_WIDTH / 2
            local totalWidth = numReagents * REAGENT_ICON_SIZE + (numReagents - 1) * REAGENT_GAP
            local reagentX = lureCenter - totalWidth / 2 + (j - 1) * (REAGENT_ICON_SIZE + REAGENT_GAP)
            rBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", reagentX, contentTop - 2 - 1)

            local rIcon = rBtn:CreateTexture(nil, "ARTWORK")
            rIcon:SetAllPoints()
            rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rBtn.icon = rIcon

            local rCount = rBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rCount:SetFont(rCount:GetFont(), 8)
            rCount:SetPoint("TOP", rBtn, "BOTTOM", 0, -1)
            rCount:SetJustifyH("CENTER")
            rBtn.countText = rCount

            C_Item.RequestLoadItemDataByID(reagent.itemID)

            rBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            rBtn:SetScript("OnClick", function(self, button)
                if IsShiftKeyDown() then
                    local _, link = C_Item.GetItemInfo(reagent.itemID)
                    if link then
                        ChatEdit_InsertLink(link)
                    end
                end
            end)
            rBtn:RegisterForClicks("LeftButtonUp")

            reagentIcons[i][j] = rBtn
        end
    end
end

------------------------------------------------------
-- TSM price labels + loot preload
------------------------------------------------------

local TSM_PRICE_HEIGHT = 10
local tsmPriceLabels = {}

for id in pairs(ns.TRACKED_LOOT) do
    C_Item.RequestLoadItemDataByID(id)
end

------------------------------------------------------
-- Lure column border boxes
------------------------------------------------------

local LURE_BOX_BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local lureBoxes = {}
for i = 1, #LURES do
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetBackdrop(LURE_BOX_BACKDROP)
    box:SetBackdropColor(0, 0, 0, 0.7)
    box:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3], 0.7)
    box:SetFrameLevel(frame:GetFrameLevel() + 1)
    headerIcons[i]:SetFrameLevel(box:GetFrameLevel() + 2)
    if reagentIcons[i] then
        for _, rBtn in ipairs(reagentIcons[i]) do
            rBtn:SetFrameLevel(box:GetFrameLevel() + 2)
        end
    end
    box:Hide()
    lureBoxes[i] = box

    local priceLabel = headerIcons[i]:CreateFontString(nil, "OVERLAY")
    priceLabel:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    priceLabel:SetTextColor(1, 0.84, 0)
    priceLabel:SetJustifyH("CENTER")
    priceLabel:SetText("")
    tsmPriceLabels[i] = priceLabel
end

------------------------------------------------------
-- Separator under icons
------------------------------------------------------

ns.iconSep = frame:CreateTexture(nil, "ARTWORK")
ns.iconSep:SetHeight(1)
ns.iconSep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, contentTop - REAGENT_ROW_HEIGHT - ICON_ROW_HEIGHT - 2)
ns.iconSep:SetPoint("RIGHT", frame, "RIGHT", -(PAD + 4), 0)
ns.iconSep:SetColorTexture(unpack(C_SEPARATOR))

------------------------------------------------------
-- Expose for UpdateUI
------------------------------------------------------

ns.headerIcons = headerIcons
ns.zoneLabels = zoneLabels
ns.reagentIcons = reagentIcons
ns.lureBoxes = lureBoxes
ns.tsmPriceLabels = tsmPriceLabels
ns.TSM_PRICE_HEIGHT = TSM_PRICE_HEIGHT
