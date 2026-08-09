local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local Assets = Addon.Assets

local ROW_MAP = {
    raids = "raid",
    dungeons = "dungeon",
    world = "world",
}

local ROW_COLORS = {
    raid = Theme.colors.raid,
    dungeon = Theme.colors.dungeon,
    world = Theme.colors.world,
}

local SUB_TABS = {
    { key = "raids", label = function() return L.VAULT_RAIDS end },
    { key = "dungeons", label = function() return L.VAULT_DUNGEONS end },
    { key = "world", label = function() return L.VAULT_WORLD end },
}

local function createValueLine(parent, labelText, anchor)
    local label = Widgets:CreateLabel(parent, "GameFontDisableSmall", "LEFT")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    label:SetText(labelText)

    local value = Widgets:CreateLabel(parent, "GameFontNormal", "RIGHT")
    value:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    value:SetPoint("CENTER", label, "CENTER", 0, 0)
    return label, value
end

local function createSlotCard(parent, index)
    local card = Widgets:CreatePanel(parent, "cardInset")
    card:SetSize(224, 118)

    card.title = Widgets:CreateLabel(card, "GameFontHighlight", "LEFT")
    card.title:SetPoint("TOPLEFT", 14, -14)
    card.title:SetText(string.format(L.VAULT_SLOT_LABEL, index))

    card.reward = Widgets:CreateLabel(card, "GameFontHighlightSmall", "RIGHT")
    card.reward:SetPoint("TOPRIGHT", -14, -14)

    card.unlockLabel, card.unlockValue = createValueLine(card, L.VAULT_UNLOCK_LABEL, card.title)
    card.unlockBar = Widgets:CreateProgressBar(card)
    card.unlockBar:SetPoint("TOPLEFT", card.unlockLabel, "BOTTOMLEFT", 0, -6)
    card.unlockBar:SetPoint("TOPRIGHT", -14, 0)
    card.unlockBar:SetHeight(12)

    card.goalLabel, card.goalValue = createValueLine(card, L.VAULT_GOAL_LABEL, card.unlockBar)
    card.goalBar = Widgets:CreateProgressBar(card)
    card.goalBar:SetPoint("TOPLEFT", card.goalLabel, "BOTTOMLEFT", 0, -6)
    card.goalBar:SetPoint("TOPRIGHT", -14, 0)
    card.goalBar:SetHeight(12)

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(selfCard)
        if selfCard.rewardLink and GameTooltip and type(GameTooltip.SetHyperlink) == "function" then
            GameTooltip:SetOwner(selfCard, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(selfCard.rewardLink)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return card
end

local function refreshSlot(card, slot, goalSlot, completed, color)
    local threshold = math.max(0, tonumber(slot and slot.threshold) or 0)
    local progress = threshold > 0 and math.min(completed, threshold) or 0
    local goalThreshold = math.max(0, tonumber(goalSlot and goalSlot.threshold) or threshold)
    local goalProgress = math.max(0, tonumber(goalSlot and goalSlot.count) or 0)

    if tonumber(slot and slot.rewardItemLevel) and tonumber(slot.rewardItemLevel) > 0 then
        card.reward:SetText(string.format(L.VAULT_CURRENT_REWARD, tonumber(slot.rewardItemLevel)))
    elseif slot and slot.rewardLink then
        card.reward:SetText(L.VAULT_CURRENT_UNKNOWN)
    else
        card.reward:SetText(L.VAULT_CURRENT_NONE)
    end
    card.unlockValue:SetText(threshold > 0 and string.format("%d/%d", progress, threshold) or "--")
    card.goalValue:SetText(goalSlot and (goalSlot.displayText or goalSlot.countText) or "--")
    card.rewardLink = slot and slot.rewardLink or nil
    Widgets:SetProgress(card.unlockBar, progress, threshold, color)
    Widgets:SetProgress(card.goalBar, goalProgress, goalThreshold, Theme.colors.goal)
end

local function createVaultScreen(_, host)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.subTabButtons = {}
    frame.subTabOrder = {}
    frame.slotCards = {}
    frame.layoutVersion = "legacy-vault-1"

    local previous
    for _, subTab in ipairs(SUB_TABS) do
        local button = Widgets:CreateButton(frame, subTab.label(), 188, 24, "tab")
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", 0, 0)
        end
        button.subTabKey = subTab.key
        button:SetScript("OnClick", function(selfButton)
            Addon.Database:GetUI().selectedSubTabs.vault = selfButton.subTabKey
            frame:Refresh()
        end)
        frame.subTabButtons[subTab.key] = button
        frame.subTabOrder[#frame.subTabOrder + 1] = button
        previous = button
    end

    frame.card = Widgets:CreatePanel(frame, "card")
    Widgets:ApplyStandardGoldFrame(frame.card, Assets.vaultCard)
    frame.card:SetPoint("TOPLEFT", 0, -38)
    frame.card:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.card.title = Widgets:CreateLabel(frame.card, "GameFontNormalLarge", "LEFT")
    frame.card.title:SetPoint("TOPLEFT", 14, -18)

    frame.card.rewardSummary = Widgets:CreateLabel(frame.card, "GameFontHighlightSmall", "LEFT")
    frame.card.rewardSummary:SetPoint("TOPLEFT", frame.card.title, "BOTTOMLEFT", 0, -8)
    frame.card.rewardSummary:SetPoint("TOPRIGHT", -14, 0)

    frame.card.breakpoints = Widgets:CreateLabel(frame.card, "GameFontDisableSmall", "LEFT")
    frame.card.breakpoints:SetPoint("TOPLEFT", frame.card.rewardSummary, "BOTTOMLEFT", 0, -8)
    frame.card.breakpoints:SetPoint("TOPRIGHT", -14, 0)

    frame.card.unlockLabel = Widgets:CreateLabel(frame.card, "GameFontHighlightSmall", "LEFT")
    frame.card.unlockLabel:SetPoint("TOPLEFT", frame.card.breakpoints, "BOTTOMLEFT", 0, -18)
    frame.card.unlockLabel:SetText(L.VAULT_UNLOCK_LABEL)
    frame.card.unlockValue = Widgets:CreateLabel(frame.card, "GameFontHighlight", "RIGHT")
    frame.card.unlockValue:SetPoint("RIGHT", frame.card, "RIGHT", -14, 0)
    frame.card.unlockValue:SetPoint("CENTER", frame.card.unlockLabel, "CENTER", 0, 0)
    frame.card.unlockBar = Widgets:CreateProgressBar(frame.card)
    frame.card.unlockBar:SetPoint("TOPLEFT", frame.card.unlockLabel, "BOTTOMLEFT", 0, -8)
    frame.card.unlockBar:SetPoint("TOPRIGHT", -14, 0)
    frame.card.unlockBar:SetHeight(14)

    -- Keep both domains stacked and visually separate: unlock progress is not
    -- interchangeable with the max-itemlevel-only goal progress below it.
    frame.card.goalLabel = Widgets:CreateLabel(frame.card, "GameFontHighlightSmall", "LEFT")
    frame.card.goalLabel:SetPoint("TOPLEFT", frame.card.unlockBar, "BOTTOMLEFT", 0, -18)
    frame.card.goalLabel:SetText(L.VAULT_GOAL_LABEL)
    frame.card.goalValue = Widgets:CreateLabel(frame.card, "GameFontHighlight", "RIGHT")
    frame.card.goalValue:SetPoint("RIGHT", frame.card, "RIGHT", -14, 0)
    frame.card.goalValue:SetPoint("CENTER", frame.card.goalLabel, "CENTER", 0, 0)
    frame.card.goalBar = Widgets:CreateProgressBar(frame.card)
    frame.card.goalBar:SetPoint("TOPLEFT", frame.card.goalLabel, "BOTTOMLEFT", 0, -8)
    frame.card.goalBar:SetPoint("TOPRIGHT", -14, 0)
    frame.card.goalBar:SetHeight(14)

    frame.card.note = Widgets:CreateLabel(frame.card, "GameFontDisableSmall", "LEFT")
    frame.card.note:SetPoint("TOPLEFT", frame.card.goalBar, "BOTTOMLEFT", 0, -12)
    frame.card.note:SetPoint("RIGHT", -14, 0)
    frame.card.note:SetHeight(22)
    frame.card.note:SetJustifyV("TOP")
    frame.card.note:SetWordWrap(true)

    previous = nil
    for index = 1, 3 do
        local slotCard = createSlotCard(frame.card, index)
        if previous then
            slotCard:SetPoint("LEFT", previous, "RIGHT", 14, 0)
        else
            slotCard:SetPoint("TOPLEFT", frame.card.note, "BOTTOMLEFT", 0, -18)
        end
        frame.slotCards[index] = slotCard
        previous = slotCard
    end

    function frame:Refresh()
        local selectedSubTab = Addon.Database:GetUI().selectedSubTabs.vault
        local rowKey = ROW_MAP[selectedSubTab] or "raid"
        local color = ROW_COLORS[rowKey] or Theme.colors.gold
        for key, button in pairs(self.subTabButtons) do
            Widgets:SetButtonActive(button, key == selectedSubTab)
        end

        local selected = Addon.WarbandRoster:GetSelected()
        local snapshot = selected and Addon.VaultProgress:GetSnapshot(selected.key) or nil
        local row = snapshot and snapshot.rows and snapshot.rows[rowKey]
        if not row then
            self.card.title:SetText(L.VAULT_EMPTY)
            self.card.rewardSummary:SetText(selected and string.format("%s-%s", selected.name or L.UNKNOWN, selected.realm or L.UNKNOWN) or "")
            self.card.breakpoints:SetText("")
            self.card.unlockValue:SetText("--")
            self.card.goalValue:SetText("--")
            self.card.note:SetText(snapshot and snapshot.summary and snapshot.summary.headline or "")
            Widgets:SetProgress(self.card.unlockBar, 0, 1, color)
            Widgets:SetProgress(self.card.goalBar, 0, 1, Theme.colors.goal)
            Widgets:SetProgressBreakpoints(self.card.unlockBar, nil, 0)
            Widgets:SetProgressBreakpoints(self.card.goalBar, nil, 0)
            for index, slotCard in ipairs(self.slotCards) do
                slotCard.title:SetText(string.format(L.VAULT_SLOT_LABEL, index))
                refreshSlot(slotCard, nil, nil, 0, color)
            end
            return
        end

        local maximum = tonumber(row.thresholds[#row.thresholds]) or 0
        local completed = maximum > 0 and math.min(tonumber(row.completedCount) or 0, maximum) or 0
        local goal = row.goal or {}
        self.card.title:SetText(row.label or L.VAULT_TITLE)
        self.card.rewardSummary:SetText(row.advice and row.advice.bestLabel
            and string.format(L.VAULT_TOP_CURRENT, row.advice.bestLabel) or L.VAULT_NONE_TOP)
        self.card.breakpoints:SetText(string.format(L.VAULT_BREAKPOINTS, table.concat(row.thresholds, " / ")))
        self.card.unlockValue:SetText(string.format("%d/%d", completed, maximum))
        self.card.goalValue:SetText(goal.displayText or "--")
        self.card.note:SetText(row.note or "")
        Widgets:SetProgress(self.card.unlockBar, completed, maximum, color)
        Widgets:SetProgress(self.card.goalBar, goal.displayCount, goal.maxThreshold, Theme.colors.goal)
        Widgets:SetProgressBreakpoints(self.card.unlockBar, row.thresholds, maximum)
        Widgets:SetProgressBreakpoints(self.card.goalBar, row.thresholds, goal.maxThreshold or maximum)
        for index, slotCard in ipairs(self.slotCards) do
            slotCard.title:SetText(string.format(L.VAULT_SLOT_LABEL, index))
            refreshSlot(slotCard, row.slots[index], goal.slots and goal.slots[index], completed, color)
        end
    end

    Addon.StateStore:Subscribe("vault.progress", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)

    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "vault",
    order = 1,
    label = function() return L.SCREEN_VAULT end,
    Create = createVaultScreen,
})
