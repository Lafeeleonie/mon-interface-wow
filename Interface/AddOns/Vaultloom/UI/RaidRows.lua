local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Assets = Addon.Assets
local Widgets = Addon.Widgets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local RaidRows = {}
Addon.RaidRows = RaidRows

RaidRows.selectionRowHeight = 52
RaidRows.wrappedSelectionRowHeight = 68
RaidRows.threeLineSelectionRowHeight = 84
RaidRows.fourLineSelectionRowHeight = 100
RaidRows.selectionRowSpacing = 6

local DEFAULT_SELECTION_ICON_TEX_COORD = { 0.08, 0.92, 0.08, 0.92 }

local STATUS_COLORS = {
    complete = { 0.34, 0.88, 0.48, 1 },
    open = Theme.colors.gold,
    repeatable = Theme.colors.gold,
    dailyOpen = Theme.colors.cyan,
    partial = Theme.colors.gold,
    missing = { 0.62, 0.59, 0.54, 1 },
}

local function applyBackdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.025, 0.022, 0.020, alpha or 0.86)
    frame:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
end

local function addCircularMask(owner, texture)
    if type(owner.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then return nil end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function setSelectionRowLayout(row, valuePlacement)
    row.title:ClearAllPoints()
    row.meta:ClearAllPoints()
    row.value:ClearAllPoints()

    if valuePlacement == "stacked" then
        row.value:SetPoint("TOPRIGHT", -12, -8)
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 58, -25)
        row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -25)
        row.meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 58, 9)
        row.meta:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 9)
    else
        row.title:SetPoint("TOPLEFT", row.iconBackplate, "TOPRIGHT", 10, -6)
    end
    if valuePlacement == "top" then
        row.value:SetPoint("TOPRIGHT", -12, -10)
        row.title:SetPoint("TOPRIGHT", row.value, "TOPLEFT", -8, 4)
        row.meta:SetPoint("BOTTOMLEFT", row.iconBackplate, "BOTTOMRIGHT", 10, 9)
        row.meta:SetPoint("BOTTOMRIGHT", -12, 9)
    elseif valuePlacement ~= "stacked" then
        row.title:SetPoint("TOPRIGHT", -12, -6)
        row.value:SetPoint("BOTTOMRIGHT", -12, 9)
        row.meta:SetPoint("BOTTOMLEFT", row.iconBackplate, "BOTTOMRIGHT", 10, 9)
        row.meta:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    end
    row.valuePlacement = valuePlacement
    row.valueOnTop = valuePlacement == "top" or valuePlacement == "stacked"
end

function RaidRows:CreateSelectionRow(parent, previous)
    local row = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(self.selectionRowHeight)
    applyBackdrop(row)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -6)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.background:SetTexture(Assets.row)
    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -6)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 6)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)
    row.iconBackplate = row:CreateTexture(nil, "ARTWORK")
    row.iconBackplate:SetSize(36, 36)
    row.iconBackplate:SetPoint("LEFT", 12, 0)
    row.iconBackplate:SetTexture(Assets.classBackplate)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(31, 31)
    row.icon:SetPoint("CENTER", row.iconBackplate, "CENTER", 0, 0)
    row.icon:SetTexCoord(unpack(DEFAULT_SELECTION_ICON_TEX_COORD))
    row.iconMask = addCircularMask(row, row.icon)
    row.iconRing = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.iconRing:SetSize(36, 36)
    row.iconRing:SetPoint("CENTER", row.iconBackplate, "CENTER", 0, 0)
    row.iconRing:SetTexture(Assets.classRing)
    row.title = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.title:SetWordWrap(true)
    if type(row.title.SetMaxLines) == "function" then row.title:SetMaxLines(2) end
    row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.meta = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.meta:SetWordWrap(false)
    if type(row.meta.SetMaxLines) == "function" then row.meta:SetMaxLines(1) end
    setSelectionRowLayout(row, "bottom")
    row.selection = row:CreateTexture(nil, "HIGHLIGHT")
    row.selection:SetPoint("TOPLEFT", 5, -5)
    row.selection:SetPoint("BOTTOMRIGHT", -5, 5)
    row.selection:SetColorTexture(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.07)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.90)
    end)
    row:SetScript("OnLeave", function(self)
        local color = self.selected and Theme.colors.gold or Theme.colors.goldDim
        self:SetBackdropBorderColor(color[1], color[2], color[3], self.selected and 0.80 or 0.55)
    end)
    row:Hide()
    return row
end

function RaidRows:SetSelectionRow(row, entry)
    if not entry then row:Hide(); return end
    local valuePlacement = entry.valuePlacement == "stacked" and "stacked"
        or entry.valuePlacement == "top" and "top"
        or "bottom"
    if row.valuePlacement ~= valuePlacement then setSelectionRowLayout(row, valuePlacement) end
    if type(row.title.SetMaxLines) == "function" then
        row.title:SetMaxLines(valuePlacement == "stacked" and 3 or 2)
    end
    local color = STATUS_COLORS[entry.colorKey or entry.status] or STATUS_COLORS.missing
    row.value:SetText(entry.value or "")
    row.title:SetText(entry.title or L.UNKNOWN)
    row.meta:SetText(entry.meta or "")
    local fontHeight = 14
    if type(row.title.GetFont) == "function" then
        local _, measuredFontHeight = row.title:GetFont()
        fontHeight = tonumber(measuredFontHeight) or fontHeight
    end
    local textHeight = type(row.title.GetStringHeight) == "function" and row.title:GetStringHeight() or fontHeight
    if valuePlacement == "stacked" then
        local desiredHeight = 38 + textHeight + ((entry.meta or "") ~= "" and 16 or 0)
        local rowHeight = self.selectionRowHeight
        if desiredHeight > self.threeLineSelectionRowHeight then
            rowHeight = self.fourLineSelectionRowHeight
        elseif desiredHeight > self.wrappedSelectionRowHeight then
            rowHeight = self.threeLineSelectionRowHeight
        elseif desiredHeight > self.selectionRowHeight then
            rowHeight = self.wrappedSelectionRowHeight
        end
        row:SetHeight(rowHeight)
    else
        row:SetHeight(textHeight > (fontHeight * 1.35) and self.wrappedSelectionRowHeight or self.selectionRowHeight)
    end
    row.value:SetTextColor(color[1], color[2], color[3], 1)
    row.statusLine:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local iconTexCoord = entry.iconTexCoord or DEFAULT_SELECTION_ICON_TEX_COORD
    row.icon:SetTexCoord(unpack(iconTexCoord))
    row.selected = entry.selected == true
    row.selection:SetShown(row.selected)
    local border = row.selected and Theme.colors.gold or Theme.colors.goldDim
    row:SetBackdropBorderColor(border[1], border[2], border[3], row.selected and 0.80 or 0.55)
    row:Show()
end

function RaidRows:GetSelectionListHeight(rows)
    if type(rows) ~= "table" then
        local count = math.max(0, tonumber(rows) or 0)
        return math.max(10, (count * (self.selectionRowHeight + self.selectionRowSpacing)) - self.selectionRowSpacing)
    end

    local total, visible = 0, 0
    for _, row in ipairs(rows) do
        if type(row.IsShown) ~= "function" or row:IsShown() then
            total = total + (tonumber(row:GetHeight()) or self.selectionRowHeight)
            visible = visible + 1
        end
    end
    if visible > 1 then total = total + ((visible - 1) * self.selectionRowSpacing) end
    return math.max(10, total)
end

local function trackerTexture(state)
    if state == "wish" then return Assets.raidTrackerWish end
    if state == "obtained" then return Assets.raidTrackerObtained end
    return Assets.raidTrackerNone
end

function RaidRows:CreateLootRow(parent, previous)
    local row = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(60)
    applyBackdrop(row, 0.78)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -6)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.background:SetTexture(Assets.row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 9, 0)
    row.icon:SetSize(35, 35)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.iconMask = Widgets:AddRoundedIconMask(row, row.icon)
    row.iconBorder = Widgets:CreateRoundedIconBorder(row, row.icon, 1, Theme.colors.goldDim)
    row.name = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("TOPLEFT", 51, -8)
    row.name:SetPoint("TOPRIGHT", -66, -8)
    row.meta = Widgets:CreateLabel(row, "GameFontNormalSmall", "LEFT")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.meta:SetPoint("TOPRIGHT", -66, 0)

    row.removeButton = Widgets:CreateButton(row, "X", 24, 24)
    row.removeButton:SetPoint("RIGHT", -8, 0)
    row.removeButton:SetScript("OnClick", function()
        if row.characterKey and row.difficultyKey and row.itemID then
            (row.trackerService or Addon.RaidJournal):ClearLootTrackerState(
                row.characterKey,
                row.difficultyKey,
                row.itemID
            )
        end
    end)
    row.removeButton:SetScript("OnEnter", function(button)
        if not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(
            L.WISHLIST_REMOVE,
            Theme.colors.gold[1],
            Theme.colors.gold[2],
            Theme.colors.gold[3],
            true
        )
        GameTooltip:Show()
    end)
    row.removeButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.removeButton:Hide()

    row.trackButton = Widgets:CreateButton(row, "", 24, 24)
    row.trackButton:SetPoint("RIGHT", -8, 0)
    row.trackButton.icon = row.trackButton:CreateTexture(nil, "OVERLAY")
    row.trackButton.icon:SetSize(18, 18)
    row.trackButton.icon:SetPoint("CENTER", 0, 0)
    row.trackButton.label:Hide()
    row.trackButton:SetScript("OnClick", function()
        if row.characterKey and row.difficultyKey and row.itemID then
            (row.trackerService or Addon.RaidJournal):CycleLootTrackerState(
                row.characterKey,
                row.difficultyKey,
                row.itemID,
                row.itemData,
                row.sourceData
            )
        end
    end)
    row.trackButton:SetScript("OnEnter", function(button)
        local state = (row.trackerService or Addon.RaidJournal):GetLootTrackerState(row.characterKey, row.difficultyKey, row.itemID)
        local label = state == "wish" and L.RAID_LOOT_TRACKER_WISH
            or state == "obtained" and L.RAID_LOOT_TRACKER_OBTAINED
            or L.RAID_LOOT_TRACKER_NONE
        if GameTooltip then
            GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(label, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            GameTooltip:AddLine(L.RAID_LOOT_TRACKER_CLICK, 0.72, 0.78, 0.88, true)
            GameTooltip:Show()
        end
    end)
    row.trackButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.90)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            if self.itemLink then
                GameTooltip:SetHyperlink(self.itemLink)
            elseif self.itemID and type(GameTooltip.SetItemByID) == "function" then
                GameTooltip:SetItemByID(self.itemID)
            else
                GameTooltip:AddLine(self.itemName or L.UNKNOWN, 0.92, 0.92, 0.92, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:Hide()
    return row
end

function RaidRows:SetLootRow(row, item, character, difficultyKey, trackerService, source)
    if not item then row:Hide(); return end
    row.itemID = item.itemID
    row.itemLink = item.link
    row.itemName = item.name
    row.characterKey = character and character.key
    row.difficultyKey = difficultyKey
    row.trackerService = trackerService or Addon.RaidJournal
    row.itemData = item
    row.sourceData = source
    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(item.name or L.UNKNOWN)
    local meta = item.slot or item.armorType or ""
    if item.veryRare then meta = meta ~= "" and (meta .. "  |  " .. L.RAID_LOOT_VERY_RARE) or L.RAID_LOOT_VERY_RARE end
    if item.extremelyRare then meta = meta ~= "" and (meta .. "  |  " .. L.RAID_LOOT_EXTREMELY_RARE) or L.RAID_LOOT_EXTREMELY_RARE end
    row.meta:SetText(meta)
    local qualityID = tonumber(item.quality)
    if qualityID == nil and Addon.ArsenalLogic then
        qualityID = Addon.ArsenalLogic:ResolveQuality(nil, item.link, item.itemID)
    end
    local quality = qualityID and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualityID]
    if quality then row.name:SetTextColor(quality.r, quality.g, quality.b, 1)
    else row.name:SetTextColor(Theme.colors.parchment[1], Theme.colors.parchment[2], Theme.colors.parchment[3], 1) end
    row.iconBorder:SetBackdropBorderColor(
        quality and quality.r or Theme.colors.goldDim[1],
        quality and quality.g or Theme.colors.goldDim[2],
        quality and quality.b or Theme.colors.goldDim[3],
        quality and 0.95 or 0.70
    )
    local state = row.trackerService:GetLootTrackerState(row.characterKey, difficultyKey, item.itemID)
    if state and Addon.JournalLootTracker then
        Addon.JournalLootTracker:RegisterItem(row.characterKey, difficultyKey, item, source)
    end
    row.trackButton.icon:SetTexture(trackerTexture(state))
    Widgets:SetButtonActive(row.trackButton, state ~= nil)
    row.trackButton:ClearAllPoints()
    if state then
        row.removeButton:Show()
        row.trackButton:SetPoint("RIGHT", row.removeButton, "LEFT", -4, 0)
    else
        row.removeButton:Hide()
        row.trackButton:SetPoint("RIGHT", -8, 0)
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 51, -8)
    row.name:SetPoint("TOPRIGHT", row.trackButton, "TOPLEFT", -6, -8)
    row.meta:ClearAllPoints()
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.meta:SetPoint("TOPRIGHT", row.trackButton, "BOTTOMLEFT", -6, 0)
    row:Show()
end
