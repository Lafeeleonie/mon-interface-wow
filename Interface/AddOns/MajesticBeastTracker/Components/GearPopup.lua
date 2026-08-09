------------------------------------------------------
-- MajesticBeastTracker Gear Popup + Dropdown
-- Gear inspection, stats, weekly knowledge popup
------------------------------------------------------

local addonName, ns = ...
local LURES = ns.LURES

-- Local aliases from shared ns constants
local BACKDROP = ns.BACKDROP
local C_BORDER_RGB = ns.C_BORDER_RGB
local C_ACCENT = ns.C_ACCENT
local MEDIA_PATH = ns.MEDIA_PATH

------------------------------------------------------
-- Gear popup (shown when clicking character name)
------------------------------------------------------

local GEAR_ICON_SIZE = 24
local GEAR_PAD = 6

local gearPopup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
gearPopup:SetFrameStrata("DIALOG")
gearPopup:SetClampedToScreen(true)
gearPopup:SetBackdrop(BACKDROP)
gearPopup:SetBackdropColor(0, 0, 0, 0.97)
gearPopup:SetBackdropBorderColor(unpack(C_BORDER_RGB))
gearPopup:EnableMouse(true)
gearPopup:Hide()

local gearPopupTitle = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearPopupTitle:SetPoint("TOPLEFT", gearPopup, "TOPLEFT", GEAR_PAD + 2, -GEAR_PAD)
gearPopupTitle:SetTextColor(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)

local gearPopupRows = {}
for slot = 1, 3 do
    local row = CreateFrame("Frame", nil, gearPopup)
    row:SetHeight(GEAR_ICON_SIZE)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(GEAR_ICON_SIZE, GEAR_ICON_SIZE)
    icon:SetPoint("LEFT")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetFont(label:GetFont(), 9)
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    gearPopupRows[slot] = row
end

-- Stat lines in gear popup
local POPUP_STAT_LABELS = {
    { key = "skill",      label = "Skill",      color = "ffFFD100" },
    { key = "perception", label = "Perception",  color = "ff1EFF00" },
    { key = "finesse",    label = "Finesse",     color = "ff0070DD" },
    { key = "deftness",   label = "Deftness",    color = "ffA335EE" },
}

local gearPopupStatHeader = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearPopupStatHeader:SetFont(gearPopupStatHeader:GetFont(), 9)
gearPopupStatHeader:SetTextColor(0.6, 0.6, 0.6)
gearPopupStatHeader:SetText("Base Stats against Majestic Beasts")

local gearPopupStatLines = {}
for i, info in ipairs(POPUP_STAT_LABELS) do
    local line = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line:SetFont(line:GetFont(), 9)
    line:SetJustifyH("LEFT")
    gearPopupStatLines[i] = line
end

-- Weekly KP header + lines
local gearPopupWeeklyHeader = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearPopupWeeklyHeader:SetFont(gearPopupWeeklyHeader:GetFont(), 9)
gearPopupWeeklyHeader:SetTextColor(0.6, 0.6, 0.6)
gearPopupWeeklyHeader:SetText("Weekly Knowledge")

local WEEKLIES = ns.SKINNING_WEEKLIES
local gearPopupWeeklyLines = {}
for i = 1, #WEEKLIES do
    local line = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line:SetFont(line:GetFont(), 9)
    line:SetJustifyH("LEFT")
    gearPopupWeeklyLines[i] = line
end

-- Helper: layout weekly lines in gear popup, returns total height used
local function LayoutWeeklyLines(charData, anchorFontString, startY, trackMaxWidth)
    local weeklyHeight = 0
    local hasWeeklies = charData and charData.weeklies
    local weeklyExpired = charData and charData.weeklyResetTime and GetServerTime() > charData.weeklyResetTime
    local dmfUp = ns.IsDarkmoonFaireUp and ns.IsDarkmoonFaireUp()

    if hasWeeklies and not weeklyExpired then
        gearPopupWeeklyHeader:ClearAllPoints()
        gearPopupWeeklyHeader:SetPoint("TOPLEFT", anchorFontString, "BOTTOMLEFT", 2, startY)
        gearPopupWeeklyHeader:Show()
        local row = 0
        for i, w in ipairs(WEEKLIES) do
            local line = gearPopupWeeklyLines[i]
            if w.dmf and not dmfUp then
                line:Hide()
            else
                local val = charData.weeklies[w.key]
                local status
                if w.mode == "each" then
                    local total = #w.questIDs
                    local count = val or 0
                    local totalKP = total * w.kp
                    if count >= total then
                        status = "|cff00ff00" .. count .. "/" .. total .. "|r"
                    elseif count > 0 then
                        status = "|cffffff00" .. count .. "/" .. total .. "|r"
                    else
                        status = "|cffff4444" .. count .. "/" .. total .. "|r"
                    end
                    line:SetText(w.label .. " |cff888888(" .. totalKP .. " KP)|r " .. status)
                else
                    local done = val
                    local icon = done and "|cff00ff00done|r" or "|cffff4444todo|r"
                    line:SetText(w.label .. " |cff888888(" .. w.kp .. " KP)|r " .. icon)
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", anchorFontString, "BOTTOMLEFT", 2, startY - 10 - row * 12)
                line:Show()
                if trackMaxWidth then
                    trackMaxWidth[1] = math.max(trackMaxWidth[1], line:GetStringWidth())
                end
                row = row + 1
            end
        end
        weeklyHeight = 6 + 10 + row * 12 + 2
    else
        gearPopupWeeklyHeader:Hide()
        for i = 1, #WEEKLIES do
            gearPopupWeeklyLines[i]:Hide()
        end
    end
    return weeklyHeight
end

-- Auto-hide when clicking elsewhere
gearPopup:SetScript("OnUpdate", function(self)
    if self:IsShown() and not self:IsMouseOver() and not ns.frame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
        self:Hide()
    end
end)

local function ShowGearPopup(anchor, charKey)
    ns.EnsureDB()
    local charData = MajesticBeastTrackerDB.chars[charKey]
    if not charData or not charData.gear or #charData.gear == 0 then
        -- No gear data — show empty message + stats if available
        gearPopupTitle:SetText(ns.GetDemoName(charKey))
        for _, row in ipairs(gearPopupRows) do
            row:Hide()
            row.label:Hide()
        end
        local noGear = gearPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noGear:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT", 0, -4)
        local isCurrentChar = charKey == ns.GetCharKey()
        local noGearMsg = isCurrentChar and "No gear equipped" or "No gear data (login required)"
        noGear:SetText("|cff666666" .. noGearMsg .. "|r")
        noGear:SetFont(noGear:GetFont(), 9)
        gearPopup.noGear = noGear

        -- Still show stats if we have them
        local statsHeight = 0
        local hasStats = charData and charData.stats and (charData.stats.skill or 0) > 0
        if hasStats then
            local headerY = -(4 + 14 + 6)
            gearPopupStatHeader:ClearAllPoints()
            gearPopupStatHeader:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT", 2, headerY)
            gearPopupStatHeader:Show()
            for i, info in ipairs(POPUP_STAT_LABELS) do
                local line = gearPopupStatLines[i]
                local val = charData.stats[info.key] or 0
                line:SetText("|c" .. info.color .. info.label .. ":|r " .. val)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT", 2, headerY - 10 - (i - 1) * 12)
                line:Show()
            end
            statsHeight = 6 + 10 + #POPUP_STAT_LABELS * 12 + 2
        else
            gearPopupStatHeader:Hide()
            for i = 1, #POPUP_STAT_LABELS do
                gearPopupStatLines[i]:Hide()
            end
        end

        -- Weeklies in no-gear view
        local weeklyY = -(4 + 14 + statsHeight + 6)
        local weeklyHeight = LayoutWeeklyLines(charData, gearPopupTitle, weeklyY, nil)

        gearPopup:SetSize(180, GEAR_PAD * 2 + 14 + 16 + statsHeight + weeklyHeight)
        gearPopup:ClearAllPoints()
        gearPopup:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, 0)
        gearPopup:Show()
        return
    end

    -- Clean up previous no-gear text
    if gearPopup.noGear then gearPopup.noGear:Hide() end

    gearPopupTitle:SetText(ns.GetClassColor(charData.class) .. ns.GetDemoName(charKey) .. "|r")

    local maxLabelWidth = 0
    for slot, row in ipairs(gearPopupRows) do
        local gear = charData.gear[slot]
        if gear then
            local tex = gear.icon or ns.GetItemIcon(gear.itemID)
            if tex then row.icon:SetTexture(tex) end
            row.itemLink = gear.link
            local displayName = gear.name or ""
            -- Color by item rarity from link
            if gear.link then
                local _, _, quality = GetItemInfo(gear.link)
                if quality and ITEM_QUALITY_COLORS[quality] then
                    displayName = ITEM_QUALITY_COLORS[quality].hex .. displayName .. "|r"
                end
            end
            row.label:SetText(displayName)
            row.label:SetWidth(180)
            row:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT",
                0, -(4 + (slot - 1) * (GEAR_ICON_SIZE + 3)))
            row:Show()
            row.label:Show()
            maxLabelWidth = math.max(maxLabelWidth, row.label:GetStringWidth())
        else
            row:Hide()
            row.label:Hide()
        end
    end

    local numGear = #charData.gear
    local gearHeight = numGear * (GEAR_ICON_SIZE + 3)

    -- Show stats below gear
    local statsHeight = 0
    local hasStats = charData.stats and (charData.stats.skill or 0) > 0
    if hasStats then
        local headerY = -(4 + gearHeight + 6)
        gearPopupStatHeader:ClearAllPoints()
        gearPopupStatHeader:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT", 2, headerY)
        gearPopupStatHeader:Show()
        for i, info in ipairs(POPUP_STAT_LABELS) do
            local line = gearPopupStatLines[i]
            local val = charData.stats[info.key] or 0
            line:SetText("|c" .. info.color .. info.label .. ":|r " .. val)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", gearPopupTitle, "BOTTOMLEFT", 2, headerY - 10 - (i - 1) * 12)
            line:Show()
            maxLabelWidth = math.max(maxLabelWidth, line:GetStringWidth())
        end
        statsHeight = 6 + 10 + #POPUP_STAT_LABELS * 12 + 2
    else
        gearPopupStatHeader:Hide()
        for i = 1, #POPUP_STAT_LABELS do
            gearPopupStatLines[i]:Hide()
        end
    end

    -- Show weeklies below stats
    local weeklyY = -(4 + gearHeight + statsHeight + 6)
    local widthTracker = { maxLabelWidth }
    local weeklyHeight = LayoutWeeklyLines(charData, gearPopupTitle, weeklyY, widthTracker)
    maxLabelWidth = widthTracker[1]

    local popupW = GEAR_PAD * 2 + GEAR_ICON_SIZE + 8 + math.max(maxLabelWidth, 160)
    local popupH = GEAR_PAD * 2 + 14 + gearHeight + statsHeight + weeklyHeight
    -- Set row width to cover full popup for hover tooltip
    for _, row in ipairs(gearPopupRows) do
        row:SetWidth(popupW - GEAR_PAD * 2)
    end
    gearPopup:SetSize(popupW, popupH)
    gearPopup:ClearAllPoints()
    gearPopup:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, 0)
    gearPopup:Show()
end

------------------------------------------------------
-- Custom dropdown
------------------------------------------------------

local dropdown

local function CreateDropdown()
    if dropdown then return dropdown end
    dropdown = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("DIALOG")
    dropdown:SetClampedToScreen(true)
    dropdown:SetBackdrop(BACKDROP)
    dropdown:SetBackdropColor(0, 0, 0, 0.97)
    dropdown:SetBackdropBorderColor(unpack(C_BORDER_RGB))
    dropdown:EnableMouse(true)
    dropdown:Hide()
    dropdown.buttons = {}

    dropdown:SetScript("OnUpdate", function(self)
        if self:IsShown() and not self:IsMouseOver() and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
            self:Hide()
        end
    end)

    return dropdown
end

local function ShowDropdown(anchor, items)
    local dd = CreateDropdown()
    for _, btn in ipairs(dd.buttons) do btn:Hide() end

    local btnHeight = 20
    local btnWidth = 150
    local yOff = -6

    for idx, item in ipairs(items) do
        local btn = dd.buttons[idx]
        if not btn then
            btn = CreateFrame("Button", nil, dd)
            btn:SetHeight(btnHeight)
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            btn.label = label

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.82, 0.71, 0.35, 0.15)

            dd.buttons[idx] = btn
        end

        btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 6, yOff)
        btn:SetPoint("TOPRIGHT", dd, "TOPRIGHT", -6, yOff)
        btn.label:SetText(item.text)
        if item.isTitle then
            btn.label:SetTextColor(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
            btn:SetScript("OnClick", nil)
            btn:Disable()
        else
            btn.label:SetTextColor(0.9, 0.9, 0.9)
            btn:Enable()
            btn:SetScript("OnClick", function()
                dd:Hide()
                if item.func then item.func() end
            end)
        end
        btn:Show()
        yOff = yOff - btnHeight
    end

    dd:SetSize(btnWidth + 12, math.abs(yOff) + 6)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    dd:Show()
end

-- Expose to other files via ns
ns.gearPopup = gearPopup
ns.ShowGearPopup = ShowGearPopup
ns.ShowDropdown = ShowDropdown
