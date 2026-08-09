------------------------------------------------------
-- MajesticBeastTracker ConsumableBar Component
------------------------------------------------------

local addonName, ns = ...
local CONSUMABLES = ns.CONSUMABLE_ITEMS
local BACKDROP = ns.BACKDROP
local C_BORDER_RGB = ns.C_BORDER_RGB
local frame = ns.frame

-- Consumable box (floating panel anchored to main frame)
local CONS_ICON_SIZE = 20
local CONS_SPACING = 4
local CONS_PAD = 6
local CONS_LABEL_HEIGHT = 12
local CONS_ITEM_WIDTH = CONS_ICON_SIZE + CONS_SPACING + 8
local CONS_BOX_WIDTH = #CONSUMABLES * CONS_ITEM_WIDTH + CONS_PAD * 2
local CONS_BOX_HEIGHT = CONS_ICON_SIZE + CONS_LABEL_HEIGHT + 10

local consumableBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
consumableBox:SetSize(CONS_BOX_WIDTH, CONS_BOX_HEIGHT)
consumableBox:SetBackdrop(BACKDROP)
consumableBox:SetBackdropColor(0, 0, 0, 0.9)
consumableBox:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3], 0.7)
consumableBox:SetFrameStrata("MEDIUM")
consumableBox:SetFrameLevel(201)
local consumableIcons = {}
local consumableButtons = {}
local consumableLabels = {}
for i, cons in ipairs(CONSUMABLES) do
    local btn = CreateFrame("Button", "MBT_ConsumableBtn" .. i, consumableBox, "SecureActionButtonTemplate")
    btn:SetSize(CONS_ICON_SIZE, CONS_ICON_SIZE)
    btn:SetFrameLevel(consumableBox:GetFrameLevel() + 1)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:Hide()

    if cons.isSpell then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", cons.spellID)
    elseif cons.isToolEnchant then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", "item:" .. cons.itemID)
    else
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", "item:" .. cons.itemID)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Cooldown sweep overlay (for spells with charges)
    local cdHolder = CreateFrame("Frame", nil, btn)
    cdHolder:SetAllPoints()
    local cd = CreateFrame("Cooldown", nil, cdHolder, "CooldownFrameTemplate")
    cd:SetSize(CONS_ICON_SIZE / 0.7, CONS_ICON_SIZE / 0.7)
    cd:SetScale(0.7)
    cd:SetPoint("CENTER")
    cd:SetDrawEdge(true)
    btn.cooldown = cd

    -- Golden border glow (shown when item in bags but buff inactive)
    -- Four edge textures around the icon
    local glowSize = 2
    local glowColor = {1, 0.75, 0, 0.9}
    local glowTop = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    glowTop:SetPoint("TOPLEFT", icon, "TOPLEFT", -glowSize, glowSize)
    glowTop:SetPoint("TOPRIGHT", icon, "TOPRIGHT", glowSize, glowSize)
    glowTop:SetHeight(glowSize)
    glowTop:SetColorTexture(unpack(glowColor))
    local glowBot = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    glowBot:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -glowSize, -glowSize)
    glowBot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", glowSize, -glowSize)
    glowBot:SetHeight(glowSize)
    glowBot:SetColorTexture(unpack(glowColor))
    local glowLeft = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    glowLeft:SetPoint("TOPLEFT", icon, "TOPLEFT", -glowSize, glowSize)
    glowLeft:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -glowSize, -glowSize)
    glowLeft:SetWidth(glowSize)
    glowLeft:SetColorTexture(unpack(glowColor))
    local glowRight = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    glowRight:SetPoint("TOPRIGHT", icon, "TOPRIGHT", glowSize, glowSize)
    glowRight:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", glowSize, -glowSize)
    glowRight:SetWidth(glowSize)
    glowRight:SetColorTexture(unpack(glowColor))
    local glowParts = {glowTop, glowBot, glowLeft, glowRight}
    for _, g in ipairs(glowParts) do g:Hide() end
    btn.glow = {
        Show = function() for _, g in ipairs(glowParts) do g:Show() end end,
        Hide = function() for _, g in ipairs(glowParts) do g:Hide() end end,
    }

    -- Hover border highlight
    for _, info in ipairs({
        {"TOPLEFT", "TOPRIGHT", true},
        {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false},
        {"TOPRIGHT", "BOTTOMRIGHT", false},
    }) do
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(1, 0.84, 0, 0.7)
        if info[3] then
            hl:SetPoint(info[1], icon, info[1], -1, 1)
            hl:SetPoint(info[2], icon, info[2], 1, 1)
            hl:SetHeight(1)
        else
            hl:SetPoint(info[1], icon, info[1], -1, 1)
            hl:SetPoint(info[2], icon, info[2], -1, -1)
            hl:SetWidth(1)
        end
    end

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        if cons.isSpell then
            GameTooltip:SetSpellByID(cons.spellID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: Cast spell", 0.5, 0.8, 1)
        else
            GameTooltip:SetItemByID(cons.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: Use item", 0.5, 0.8, 1)
            GameTooltip:AddLine("Shift-click: Search in AH", 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PreClick: block on shift (AH search) or if buff has >20% remaining
    btn:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        if IsShiftKeyDown() then
            self:SetAttribute("type", nil)
            return
        end
        -- Prioritize item: use primary itemID, fallback to altItemID if primary not in bags
        if cons.itemID and cons.altItemID and not cons.isSpell then
            local primaryCount = C_Item.GetItemCount(cons.itemID)
            if primaryCount > 0 then
                self:SetAttribute("item", "item:" .. cons.itemID)
            else
                local altCount = C_Item.GetItemCount(cons.altItemID)
                if altCount > 0 then
                    self:SetAttribute("item", "item:" .. cons.altItemID)
                end
            end
        end
        -- Block if buff still has >20% duration left (skip for stackable, spells, and tool enchants)
        if not cons.stackable and not cons.isSpell and not cons.isToolEnchant then
            local buffName = cons.buffSpellID and C_Spell.GetSpellName(cons.buffSpellID) or cons.name
            local buffInfo = C_UnitAuras.GetAuraDataBySpellName("player", buffName, "HELPFUL")
            if buffInfo and buffInfo.duration and not issecretvalue(buffInfo.duration) and buffInfo.duration > 0 and buffInfo.expirationTime then
                local remaining = buffInfo.expirationTime - GetTime()
                if remaining / buffInfo.duration > 0.2 then
                    self:SetAttribute("type", nil)
                    if not self._blockedMsg or (GetTime() - self._blockedMsg) > 1 then
                        if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                            local timeLeft = remaining >= 60 and (math.ceil(remaining / 60) .. "m") or (math.floor(remaining) .. "s")
                            print("|cff3FC7EB[MBT]|r Buff still has " .. timeLeft .. " left. Not consumed.")
                        end
                        self._blockedMsg = GetTime()
                    end
                end
            end
        end
    end)
    btn:SetScript("PostClick", function(self)
        -- Restore correct type attribute
        if not InCombatLockdown() then
            if cons.isSpell then
                self:SetAttribute("type", "spell")
            else
                self:SetAttribute("type", "item")
            end
        end
        if IsShiftKeyDown() then
            if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
                local itemName = C_Item.GetItemNameByID(cons.itemID)
                if itemName then
                    AuctionHouseFrame.SearchBar.SearchBox:SetText(itemName)
                    AuctionHouseFrame.SearchBar.SearchButton:Click()
                end
            else
                if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                    print("|cff3FC7EB[MBT]|r Open the Auction House first!")
                end
            end
        end
    end)

    -- Status label to the right of icon (on consumableBox, high strata)
    local label = consumableBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetFont(label:GetFont(), 10)
    label:SetJustifyH("LEFT")

    consumableIcons[i] = btn
    consumableButtons[i] = btn
    consumableLabels[i] = label
end

-- Refresh consumable labels (called every 1s for real-time buff timers)
function ns.RefreshConsumableLabels()
    local playerLevel = UnitLevel("player")
    for i, cons in ipairs(CONSUMABLES) do
        local meetsLevel = not cons.minLevel or playerLevel >= cons.minLevel

        -- Tool enchant type: scan skinning tool tooltip for remaining time
        if cons.isToolEnchant then
            local count = C_Item.GetItemCount(cons.itemID)
            if not meetsLevel then
                consumableLabels[i]:SetText("Lv" .. cons.minLevel)
                consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
                consumableButtons[i].glow:Hide()
            else
                local remaining, isActive = ns.GetToolEnchantRemaining()
                if isActive and remaining > 0 then
                    local timeText
                    local totalMin = math.floor(remaining / 60)
                    if totalMin > 30 then
                        timeText = "Active"
                    elseif totalMin > 0 then
                        timeText = totalMin .. "m"
                    else
                        timeText = math.floor(remaining) .. "s"
                    end
                    if count > 0 then timeText = timeText .. " " .. count .. "x" end
                    consumableLabels[i]:SetText(timeText)
                    consumableLabels[i]:SetTextColor(0.2, 0.9, 0.4)
                    consumableButtons[i].glow:Hide()
                elseif count > 0 then
                    consumableLabels[i]:SetText(count .. "x")
                    consumableLabels[i]:SetTextColor(1, 1, 1)
                    consumableButtons[i].glow:Show()
                else
                    consumableLabels[i]:SetText("0")
                    consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
                    consumableButtons[i].glow:Hide()
                end
            end

        -- Spell type: show charges + cooldown (all inside pcall to handle secret values)
        elseif cons.isSpell then
            if not meetsLevel then
                consumableLabels[i]:SetText("Lv" .. cons.minLevel)
                consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
                consumableButtons[i].glow:Hide()
            else
                local ok, labelText, lr, lg, lb, showGlow, cdStart, cdDur = pcall(function()
                    local curCharges, maxCharges, cdRemaining = 0, 1, 0
                    local cdStartTime, cdDuration = 0, 0
                    local chargeInfo = C_Spell.GetSpellCharges(cons.spellID)
                    if chargeInfo then
                        curCharges = chargeInfo.currentCharges or 0
                        maxCharges = chargeInfo.maxCharges or 1
                        if curCharges < maxCharges and chargeInfo.cooldownStartTime and chargeInfo.cooldownDuration and chargeInfo.cooldownDuration > 0 then
                            cdRemaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
                            cdStartTime = chargeInfo.cooldownStartTime
                            cdDuration = chargeInfo.cooldownDuration
                            if cdRemaining < 0 then cdRemaining = 0 end
                        end
                    else
                        local cdInfo = C_Spell.GetSpellCooldown(cons.spellID)
                        if cdInfo and cdInfo.duration and not issecretvalue(cdInfo.duration) and cdInfo.duration > 0 then
                            cdRemaining = (cdInfo.startTime + cdInfo.duration) - GetTime()
                            cdStartTime = cdInfo.startTime
                            cdDuration = cdInfo.duration
                            if cdRemaining < 0 then cdRemaining = 0 end
                        end
                        maxCharges = 1
                        curCharges = cdRemaining > 0 and 0 or 1
                    end
                    local function fmtCd(rem, prefix)
                        if rem <= 0 then return "" end
                        if rem >= 3600 then return prefix .. math.ceil(rem / 3600) .. "h" end
                        if rem >= 60 then return prefix .. math.ceil(rem / 60) .. "m" end
                        return prefix .. math.floor(rem) .. "s"
                    end
                    if curCharges > 0 then
                        if curCharges >= maxCharges then
                            return curCharges .. "/" .. maxCharges, 0.2, 0.9, 0.4, true, 0, 0
                        else
                            return curCharges .. "/" .. maxCharges .. fmtCd(cdRemaining, " "), 0.9, 0.8, 0.2, true, 0, 0
                        end
                    else
                        return "0/" .. maxCharges, 0.9, 0.3, 0.3, false, cdStartTime, cdDuration
                    end
                end)
                if ok and labelText then
                    consumableLabels[i]:SetText(labelText)
                    consumableLabels[i]:SetTextColor(lr, lg, lb)
                    if showGlow then consumableButtons[i].glow:Show() else consumableButtons[i].glow:Hide() end
                    -- Cooldown sweep on icon
                    if cdStart and cdDur and cdDur > 0 then
                        consumableButtons[i].cooldown:SetCooldown(cdStart, cdDur)
                    else
                        consumableButtons[i].cooldown:Clear()
                    end
                else
                    consumableLabels[i]:SetText("?")
                    consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
                    consumableButtons[i].glow:Hide()
                    consumableButtons[i].cooldown:Clear()
                end
            end
        else

        -- Item type: existing logic (locale-safe via itemID and buffSpellID)
        local count = C_Item.GetItemCount(cons.itemID)
        if cons.altItemID then
            count = count + C_Item.GetItemCount(cons.altItemID)
        end
        local buffName = cons.buffSpellID and C_Spell.GetSpellName(cons.buffSpellID) or cons.name
        local buffInfo = buffName and C_UnitAuras.GetAuraDataBySpellName("player", buffName, "HELPFUL") or nil
        local remaining = buffInfo and buffInfo.expirationTime and (buffInfo.expirationTime - GetTime()) or 0
        if not meetsLevel then
            consumableLabels[i]:SetText("Lv" .. cons.minLevel)
            consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
            consumableButtons[i].glow:Hide()
        elseif cons.stackable and buffInfo and remaining > 0 then
            local label = remaining >= 60 and (math.ceil(remaining / 60) .. "m") or (math.floor(remaining) .. "s")
            if count > 0 then label = label .. " " .. count .. "x" end
            consumableLabels[i]:SetText(label)
            consumableLabels[i]:SetTextColor(0.2, 0.9, 0.4)
            if count > 0 then consumableButtons[i].glow:Show() else consumableButtons[i].glow:Hide() end
        elseif buffInfo and remaining > 0 then
            consumableLabels[i]:SetText(remaining >= 60 and (math.ceil(remaining / 60) .. "m") or (math.floor(remaining) .. "s"))
            consumableLabels[i]:SetTextColor(0.2, 0.9, 0.4)
            consumableButtons[i].glow:Hide()
        elseif count > 0 then
            consumableLabels[i]:SetText(count .. "x")
            consumableLabels[i]:SetTextColor(1, 1, 1)
            consumableButtons[i].glow:Show()
        else
            consumableLabels[i]:SetText("0")
            consumableLabels[i]:SetTextColor(0.4, 0.4, 0.4)
            consumableButtons[i].glow:Hide()
        end
        end -- close spell/item if-else
    end
end

-- Expose to ns for UpdateUI
ns.consumableBox = consumableBox
ns.consumableButtons = consumableButtons
ns.consumableLabels = consumableLabels
ns.consumableIcons = consumableIcons
ns.CONS_ICON_SIZE = CONS_ICON_SIZE
ns.CONS_ITEM_WIDTH = CONS_ITEM_WIDTH
ns.CONS_BOX_HEIGHT = CONS_BOX_HEIGHT
ns.CONS_PAD = CONS_PAD
ns.CONS_BOX_WIDTH = CONS_BOX_WIDTH
