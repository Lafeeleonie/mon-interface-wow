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

local SIMPLE_ROWS = {
    { key = "raid", label = function() return L.VAULT_RAIDS end },
    { key = "dungeon", label = function() return L.VAULT_DUNGEONS end },
    { key = "world", label = function() return L.VAULT_WORLD end },
}

local SIMPLE_CATEGORY_TEXTURES = Assets.vaultSimpleCategories or {}
local SIMPLE_CATEGORY_ART_WIDTH = 279
local SIMPLE_CATEGORY_ART_HEIGHT = 112

local SIMPLE_REWARD_ATLASES = {
    locked = "evergreen-weeklyrewards-reward-locked",
    unlocked = "evergreen-weeklyrewards-reward-unlocked",
}

local WEEKLY_REWARDS_ADDON = "Blizzard_WeeklyRewards"
local weeklyRewardsAssetsReady = false

local function ensureWeeklyRewardsAssets()
    if weeklyRewardsAssetsReady then
        return true
    end
    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(loadAddOn) == "function" then
        local ok, loaded = pcall(loadAddOn, WEEKLY_REWARDS_ADDON)
        weeklyRewardsAssetsReady = ok and loaded == true
    end
    return weeklyRewardsAssetsReady
end

ensureWeeklyRewardsAssets()

local function applySimpleCategoryTexture(texture, rowKey)
    local source = SIMPLE_CATEGORY_TEXTURES[rowKey]
    if not source then
        return false
    end
    if source.atlas and type(texture.SetAtlas) == "function" then
        local ok = pcall(texture.SetAtlas, texture, source.atlas, true)
        if ok then
            texture:SetSize(SIMPLE_CATEGORY_ART_WIDTH, SIMPLE_CATEGORY_ART_HEIGHT)
        end
        return ok
    end
    if source.texture then
        texture:SetTexture(source.texture)
        texture:SetTexCoord(
            source.left or 0,
            source.right or 1,
            source.top or 0,
            source.bottom or 1
        )
        return true
    end
    return false
end

local function applySimpleCategoryTextures(frame)
    for _, row in ipairs(frame.simpleRows or {}) do
        applySimpleCategoryTexture(row.categoryArt, row.rowKey)
    end
end

local function setTextureColor(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function simpleGoalLabel(rowKey, threshold)
    if rowKey == "raid" then
        return string.format(L.VAULT_SIMPLE_RAID_GOAL, threshold)
    elseif rowKey == "dungeon" then
        return string.format(L.VAULT_SIMPLE_DUNGEON_GOAL, threshold)
    end
    return string.format(L.VAULT_SIMPLE_WORLD_GOAL, threshold)
end

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

local function createSimpleSlot(parent)
    local slot = Widgets:CreatePanel(parent, "cardInset")
    slot:SetSize(176, 92)
    slot:SetBackdrop(nil)

    slot.blizzardBackground = slot:CreateTexture(nil, "BACKGROUND")
    slot.blizzardBackground:SetSize(176, 101)
    slot.blizzardBackground:SetPoint("CENTER")
    slot.blizzardBackground:SetAtlas(SIMPLE_REWARD_ATLASES.locked, false)

    slot.goal = Widgets:CreateLabel(slot, "GameFontHighlightSmall", "CENTER")
    slot.goal:SetPoint("TOPLEFT", 32, -8)
    slot.goal:SetPoint("TOPRIGHT", -8, -8)
    slot.goal:SetHeight(24)
    slot.goal:SetJustifyV("TOP")
    slot.goal:SetWordWrap(true)
    slot.goal:SetMaxLines(2)

    slot.statusIcon = slot:CreateTexture(nil, "ARTWORK")
    slot.statusIcon:SetAtlas("activities-icon-checkmark", true)
    slot.statusIcon:SetPoint("TOPLEFT", 8, -8)
    slot.statusIcon:Hide()

    slot.progress = Widgets:CreateLabel(slot, "GameFontNormal", "RIGHT")
    slot.progress:SetPoint("BOTTOMRIGHT", -12, 10)

    slot.reward = Widgets:CreateLabel(slot, "GameFontDisableSmall", "LEFT")
    slot.reward:SetPoint("BOTTOMLEFT", 12, 10)
    slot.reward:SetPoint("BOTTOMRIGHT", slot.progress, "BOTTOMLEFT", -6, 0)

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(selfSlot)
        if GameTooltip and type(GameTooltip.AddLine) == "function" then
            GameTooltip:SetOwner(selfSlot, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:SetText(selfSlot.tooltipTitle or L.VAULT_TITLE, 0.92, 0.76, 0.24)
            GameTooltip:AddDoubleLine(
                L.VAULT_SIMPLE_TOOLTIP_PROGRESS,
                selfSlot.tooltipProgress or "--",
                0.93, 0.89, 0.77,
                1, 1, 1
            )
            if selfSlot.tooltipUnlocked then
                GameTooltip:AddLine(L.VAULT_SIMPLE_TOOLTIP_UNLOCKED, 0.45, 0.90, 0.45)
            elseif selfSlot.tooltipMissingToSlot then
                GameTooltip:AddLine(
                    string.format(L.VAULT_SIMPLE_TOOLTIP_TO_SLOT, selfSlot.tooltipMissingToSlot),
                    0.93, 0.89, 0.77
                )
            end
            if selfSlot.tooltipRewardItemLevel then
                GameTooltip:AddDoubleLine(
                    L.VAULT_SIMPLE_TOOLTIP_REWARD,
                    string.format(L.VAULT_SIMPLE_ITEM_LEVEL, selfSlot.tooltipRewardItemLevel),
                    0.93, 0.89, 0.77,
                    1, 1, 1
                )
            end
            if selfSlot.tooltipUpgradeItemLevel
                and selfSlot.tooltipUpgradeItemLevel > (selfSlot.tooltipRewardItemLevel or 0)
            then
                GameTooltip:AddDoubleLine(
                    L.VAULT_SIMPLE_TOOLTIP_NEXT_REWARD,
                    string.format(L.VAULT_SIMPLE_ITEM_LEVEL, selfSlot.tooltipUpgradeItemLevel),
                    0.93, 0.89, 0.77,
                    0.92, 0.76, 0.24
                )
            end
            if selfSlot.tooltipMissingToMax ~= nil then
                GameTooltip:AddLine(
                    selfSlot.tooltipMissingToMax <= 0
                        and L.VAULT_SIMPLE_TOOLTIP_MAX_REACHED
                        or string.format(L.VAULT_SIMPLE_TOOLTIP_TO_MAX, selfSlot.tooltipMissingToMax),
                    selfSlot.tooltipMissingToMax <= 0 and 0.45 or 0.93,
                    selfSlot.tooltipMissingToMax <= 0 and 0.90 or 0.89,
                    selfSlot.tooltipMissingToMax <= 0 and 0.45 or 0.77
                )
            end
            GameTooltip:Show()
        end
    end)
    slot:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return slot
end

local function refreshSimpleSlot(slot, rowKey, slotData, completed, index, missingToMax, targetItemLevel)
    local threshold = math.max(0, tonumber(slotData and slotData.threshold) or 0)
    local rawProgress = math.max(completed, tonumber(slotData and slotData.progress) or 0)
    local progress = threshold > 0 and math.min(rawProgress, threshold) or 0
    local unlocked = threshold > 0 and rawProgress >= threshold
    local rewardItemLevel = tonumber(slotData and slotData.rewardItemLevel)
    local hasMaximumReward = rewardItemLevel
        and targetItemLevel and targetItemLevel > 0
        and rewardItemLevel >= targetItemLevel

    slot.goal:SetText(threshold > 0
        and simpleGoalLabel(rowKey, threshold)
        or string.format(L.VAULT_SLOT_LABEL, index))
    slot.progress:SetText(threshold > 0 and string.format("%d/%d", progress, threshold) or "--")
    slot.blizzardBackground:SetAtlas(unlocked
        and SIMPLE_REWARD_ATLASES.unlocked or SIMPLE_REWARD_ATLASES.locked, false)
    slot.statusIcon:SetShown(unlocked)
    slot.reward:SetText(rewardItemLevel
        and string.format(L.VAULT_SIMPLE_ITEM_LEVEL, rewardItemLevel)
        or L.VAULT_CURRENT_NONE)
    slot.rewardLink = slotData and slotData.rewardLink or nil
    slot.tooltipTitle = slot.goal:GetText()
    slot.tooltipProgress = threshold > 0 and string.format("%d/%d", progress, threshold) or "--"
    slot.tooltipUnlocked = unlocked
    slot.tooltipMissingToSlot = threshold > 0 and not unlocked and math.max(0, threshold - rawProgress) or nil
    slot.tooltipRewardItemLevel = rewardItemLevel
    slot.tooltipUpgradeItemLevel = tonumber(slotData and slotData.upgradeItemLevel)
    slot.tooltipMissingToMax = hasMaximumReward and 0 or missingToMax

end

local function createSimpleRow(parent, definition, previous)
    local row = Widgets:CreatePanel(parent, "sectionInset")
    row:SetHeight(112)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
    else
        row:SetPoint("TOPLEFT", 12, -48)
        row:SetPoint("TOPRIGHT", -12, -48)
    end
    row.rowKey = definition.key

    local color = ROW_COLORS[definition.key] or Theme.colors.gold
    -- BackdropTemplate also renders the row background on BACKGROUND. Keeping
    -- the category atlas on that layer leaves their draw order undefined when
    -- the Overview card is hidden and shown again. Put the art above the
    -- backdrop while keeping it below the row's labels and child slot frames.
    row.categoryArt = row:CreateTexture(nil, "ARTWORK", nil, -8)
    row.categoryArt:SetPoint("LEFT", 0, 0)
    row.categoryArt:SetSize(SIMPLE_CATEGORY_ART_WIDTH, SIMPLE_CATEGORY_ART_HEIGHT)

    row.title = Widgets:CreateLabel(row, "GameFontNormalLarge", "LEFT")
    row.title:SetPoint("TOPLEFT", 16, -24)
    row.title:SetPoint("RIGHT", row, "LEFT", 142, 0)
    row.title:SetText(definition.label())
    row.title:SetTextColor(color[1], color[2], color[3], color[4])

    row.progress = Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.progress:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -12)

    row.slots = {}
    local previousSlot
    for index = 1, 3 do
        local slot = createSimpleSlot(row)
        if previousSlot then
            slot:SetPoint("LEFT", previousSlot, "RIGHT", 8, 0)
        else
            slot:SetPoint("TOPLEFT", row, "TOPLEFT", 159, -10)
        end
        row.slots[index] = slot
        previousSlot = slot
    end
    return row
end

local function refreshSimpleRow(rowFrame, rowData)
    local completed = math.max(0, tonumber(rowData and rowData.completedCount) or 0)
    local thresholds = rowData and rowData.thresholds or {}
    local maximum = math.max(0, tonumber(thresholds[#thresholds]) or 0)
    local missingToMax = rowData and rowData.goal
        and math.max(0, tonumber(rowData.goal.missingToMax) or 0) or nil
    local targetItemLevel = rowData and rowData.goal
        and math.max(0, tonumber(rowData.goal.targetItemLevel) or 0) or nil
    rowFrame.progress:SetText(maximum > 0
        and string.format("%d/%d", math.min(completed, maximum), maximum)
        or "--")
    for index, slot in ipairs(rowFrame.slots) do
        refreshSimpleSlot(
            slot,
            rowFrame.rowKey,
            rowData and rowData.slots and rowData.slots[index],
            completed,
            index,
            missingToMax,
            targetItemLevel
        )
    end
end

local function createVaultScreen(_, host)
    ensureWeeklyRewardsAssets()

    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.subTabButtons = {}
    frame.subTabOrder = {}
    frame.slotCards = {}
    frame.simpleRows = {}
    frame.viewMode = "simple"
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
            local ui = Addon.Database:GetUI()
            if (ui.selectedSubTabs.vault ~= selfButton.subTabKey or frame.viewMode ~= "detail")
                and Addon.Sound
            then
                Addon.Sound:Play("tabSwitch")
            end
            ui.selectedSubTabs.vault = selfButton.subTabKey
            frame.viewMode = "detail"
            frame:Refresh()
        end)
        frame.subTabButtons[subTab.key] = button
        frame.subTabOrder[#frame.subTabOrder + 1] = button
        previous = button
    end

    frame.viewModeButton = Widgets:CreateButton(frame, L.VAULT_VIEW_SIMPLE, 124, 24, "tab")
    frame.viewModeButton:SetPoint("TOPRIGHT", 0, 0)
    frame.viewModeButton:SetScript("OnClick", function()
        if Addon.Sound then Addon.Sound:Play("tabSwitch") end
        frame.viewMode = frame.viewMode == "simple" and "detail" or "simple"
        frame:Refresh()
    end)

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

    frame.simpleCard = Widgets:CreatePanel(frame, "card")
    Widgets:ApplyStandardGoldFrame(frame.simpleCard, Assets.vaultCard)
    frame.simpleCard:SetPoint("TOPLEFT", 0, -38)
    frame.simpleCard:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.simpleCard.title = Widgets:CreateLabel(frame.simpleCard, "GameFontNormal", "LEFT")
    frame.simpleCard.title:SetPoint("TOPLEFT", 16, -17)
    frame.simpleCard.title:SetWidth(300)
    frame.simpleCard.title:SetText(L.VAULT_SIMPLE_HEADER)

    frame.simpleCard.claimNotice = Widgets:CreateLabel(frame.simpleCard, "GameFontNormal", "LEFT")
    frame.simpleCard.claimNotice:SetPoint("TOPLEFT", frame.simpleCard.title, "TOPRIGHT", 12, 0)
    frame.simpleCard.claimNotice:SetPoint("TOPRIGHT", -180, -17)
    frame.simpleCard.claimNotice:SetText(L.VAULT_REWARD_TOOLTIP)
    frame.simpleCard.claimNotice:SetTextColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        Theme.colors.gold[4]
    )
    frame.simpleCard.claimNotice:Hide()

    frame.simpleCard.subtitle = Widgets:CreateLabel(frame.simpleCard, "GameFontDisableSmall", "RIGHT")
    frame.simpleCard.subtitle:SetPoint("TOPRIGHT", -16, -17)
    frame.simpleCard.subtitle:SetWidth(150)

    previous = nil
    for _, definition in ipairs(SIMPLE_ROWS) do
        local row = createSimpleRow(frame.simpleCard, definition, previous)
        frame.simpleRows[#frame.simpleRows + 1] = row
        previous = row
    end
    frame.simpleCard:Hide()

    function frame:Refresh()
        local ui = Addon.Database:GetUI()
        local selectedSubTab = ui.selectedSubTabs.vault
        local simpleMode = self.viewMode == "simple"
        local rowKey = ROW_MAP[selectedSubTab] or "raid"
        local color = ROW_COLORS[rowKey] or Theme.colors.gold
        for key, button in pairs(self.subTabButtons) do
            Widgets:SetButtonActive(button, not simpleMode and key == selectedSubTab)
        end
        Widgets:SetButtonActive(self.viewModeButton, simpleMode)
        self.card:SetShown(not simpleMode)
        self.simpleCard:SetShown(simpleMode)

        local selected = Addon.WarbandRoster:GetSelected()
        local snapshot = selected and Addon.VaultProgress:GetSnapshot(selected.key) or nil
        local rewardReminder = selected
            and Addon.VaultProgress:GetRewardReminder(selected.key) or nil
        self.simpleCard.claimNotice:SetShown(rewardReminder ~= nil)
        if simpleMode then
            ensureWeeklyRewardsAssets()
            applySimpleCategoryTextures(self)
            local resetAt = tonumber(snapshot and snapshot.resetAt)
            local currentTime = type(time) == "function" and time() or 0
            self.simpleCard.subtitle:SetText(resetAt and resetAt > currentTime
                and string.format(
                    L.VAULT_SIMPLE_RESET,
                    Addon.WoWApi:FormatDurationShort(resetAt - currentTime)
                )
                or "")
            for _, simpleRow in ipairs(self.simpleRows) do
                refreshSimpleRow(simpleRow, snapshot and snapshot.rows and snapshot.rows[simpleRow.rowKey])
            end
            return
        end
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

    frame:SetScript("OnShow", function()
        ensureWeeklyRewardsAssets()
        frame:Refresh()
        if type(Addon.VaultProgress) == "table" and type(Addon.VaultProgress.Refresh) == "function" then
            Addon.VaultProgress:Refresh(0)
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.60, function()
                    if frame:IsShown() then Addon.VaultProgress:Refresh(0) end
                end)
            end
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
