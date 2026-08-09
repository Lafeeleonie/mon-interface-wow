------------------------------------------------------
-- MajesticBeastTracker UI/UpdateUI.lua
-- Split from UI.lua: character rows, state computation,
-- layout positioning, and data refresh
------------------------------------------------------
-- Required ns.* exports from UI.lua (must be set before this file loads):
--   ns.fishIcon, ns.fishBtn, ns.coinIcon, ns.coinBtn
--   ns.autoHideIcon, ns.timerLabel, ns.timerBtn
--   ns.statsTexts, ns.weeklyMainLines, ns.STAT_LABELS
--   ns.lockIcon, ns.CONSUMABLES
------------------------------------------------------

local addonName, ns = ...
local LURES = ns.LURES
local WEEKLIES = ns.SKINNING_WEEKLIES

------------------------------------------------------
-- Local aliases for ns constants (performance)
------------------------------------------------------
local ICON_SIZE          = ns.ICON_SIZE
local COL_WIDTH          = ns.COL_WIDTH
local BASE_NAME_COL_WIDTH = ns.BASE_NAME_COL_WIDTH
local ROW_HEIGHT         = ns.ROW_HEIGHT
local TOOLBAR_HEIGHT     = ns.TOOLBAR_HEIGHT
local BOTTOM_BAR_HEIGHT  = ns.BOTTOM_BAR_HEIGHT
local TITLE_HEIGHT       = ns.TITLE_HEIGHT
local ZONE_LABEL_HEIGHT  = 10  -- matches UI.lua
local ICON_ROW_HEIGHT    = ns.ICON_ROW_HEIGHT
local REAGENT_ICON_SIZE  = ns.REAGENT_ICON_SIZE
local REAGENT_COUNT_HEIGHT = ns.REAGENT_COUNT_HEIGHT
local REAGENT_GAP        = ns.REAGENT_GAP
local REAGENT_ROW_HEIGHT = ns.REAGENT_ROW_HEIGHT
local PAD                = ns.PAD
local MEDIA_PATH         = ns.MEDIA_PATH
local BACKDROP           = ns.BACKDROP
local C_BORDER_RGB       = ns.C_BORDER_RGB

------------------------------------------------------
-- Mutable NAME_COL_WIDTH (local copy, updated per frame)
------------------------------------------------------
local NAME_COL_WIDTH = BASE_NAME_COL_WIDTH

------------------------------------------------------
-- Character rows
------------------------------------------------------

local charRows = {}
ns.charRows = charRows
local dataTop = ns.contentTop - REAGENT_ROW_HEIGHT - ICON_ROW_HEIGHT - 5

function ns.GetStatusText(charData, lureName)
    if not charData then return "?", 0.4, 0.4, 0.4 end
    local timestamp = charData.lures[lureName]
    if not timestamp then
        return "-", 0.4, 0.4, 0.4
    elseif ns.IsLureReady(timestamp) then
        return "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t", 0.2, 0.9, 0.4
    else
        local timeLeft = ns.GetLureTimeRemaining(timestamp)
        local h = math.floor(timeLeft / 3600)
        local m = math.floor((timeLeft % 3600) / 60)
        if h > 0 then
            return h .. "h", 0.9, 0.3, 0.3
        else
            return m .. "m", 1, 0.6, 0.2
        end
    end
end

local function CreateCharRow(index)
    local frame = ns.charScrollChild or ns.frame
    local C_ROW_ALT = { 0.1, 0.1, 0.14, 0.4 }
    local C_TOOLBAR_ICON = ns.C_TOOLBAR_ICON
    local row = {}
    local yOffset = dataTop - (index - 1) * ROW_HEIGHT

    -- Alternating row background
    if index % 2 == 0 then
        local rowBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        rowBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, yOffset)
        rowBg:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
        rowBg:SetHeight(ROW_HEIGHT)
        rowBg:SetColorTexture(unpack(C_ROW_ALT))
        row.bg = rowBg
    end

    -- Name button (clickable to show gear popup)
    local nameBtn = CreateFrame("Button", nil, frame)
    nameBtn:SetSize(NAME_COL_WIDTH - 4, ROW_HEIGHT)
    nameBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 6, yOffset)

    local nameLabel = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetAllPoints()
    nameLabel:SetFont(nameLabel:GetFont(), 10)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetJustifyV("MIDDLE")
    nameLabel:SetWordWrap(false)

    local nameHl = nameBtn:CreateTexture(nil, "HIGHLIGHT")
    nameHl:SetAllPoints()
    nameHl:SetColorTexture(0.82, 0.71, 0.35, 0.08)

    nameBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nameBtn.label = nameLabel
    row.name = nameBtn
    row.nameLabel = nameLabel

    -- Tool icon (shown inside name cell, left side, for current char when Razorstone is active)
    local toolIcon = CreateFrame("Button", "MBT_ToolIcon" .. index, frame, "SecureActionButtonTemplate")
    toolIcon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    -- Position set dynamically in UpdateUI (anchored to frame, not nameBtn)
    toolIcon:RegisterForClicks("AnyUp", "AnyDown")
    toolIcon:SetFrameLevel(nameBtn:GetFrameLevel() + 5)
    toolIcon:Hide()
    local toolTex = toolIcon:CreateTexture(nil, "ARTWORK")
    toolTex:SetAllPoints()
    toolTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    toolIcon.icon = toolTex
    -- Golden hover border
    local toolHl = toolIcon:CreateTexture(nil, "HIGHLIGHT")
    toolHl:SetAllPoints()
    toolHl:SetColorTexture(1, 0.84, 0, 0.3)
    toolIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.slotID then
            GameTooltip:SetInventoryItem("player", self.slotID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to apply enchant", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    toolIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Secure macro: /use <slotID> applies enchant cursor to that slot
    toolIcon:SetAttribute("type", "macro")
    row.toolIcon = toolIcon

    row.cells = {}
    for i = 1, #LURES do
        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(COL_WIDTH, ROW_HEIGHT)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PAD + 4 + NAME_COL_WIDTH + (i - 1) * COL_WIDTH,
            yOffset)

        local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetAllPoints()
        label:SetFont(label:GetFont(), 10)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        cell.label = label

        -- Highlight on hover
        local hl = cell:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.82, 0.71, 0.35, 0.1)

        cell.lureIndex = i
        row.cells[i] = cell
    end

    -- Goblin loot icon (right side of row)
    local goblinBtn = CreateFrame("Button", nil, frame)
    goblinBtn:SetSize(14, 14)
    local goblinX = PAD + 4 + NAME_COL_WIDTH + #LURES * COL_WIDTH + 4
    goblinBtn:SetPoint("LEFT", frame, "TOPLEFT", goblinX, yOffset - ROW_HEIGHT / 2)
    local goblinIcon = goblinBtn:CreateTexture(nil, "ARTWORK")
    goblinIcon:SetAllPoints()
    goblinIcon:SetTexture(MEDIA_PATH .. "Icon_Results")
    goblinIcon:SetTexCoord(0, 1, 0, 1)
    goblinIcon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
    goblinBtn.icon = goblinIcon
    goblinBtn:RegisterForClicks("LeftButtonUp")
    goblinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    goblinBtn:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        if ns.lootEditor:IsShown() and ns.lootEditor.charKey == row._charKey then
            ns.lootEditor:Hide()
        else
            ns.ShowLootEditor(self, row._charKey)
        end
    end)
    goblinBtn:Hide()
    row.goblinBtn = goblinBtn

    return row
end

function ns.HideAllRows()
    for _, row in ipairs(charRows) do
        row.name:Hide()
        if row.bg then row.bg:Hide() end
        for _, cell in ipairs(row.cells) do
            cell:Hide()
        end
        if row.goblinBtn then row.goblinBtn:Hide() end
    end
end

-- Character rows created lazily in LayoutUI/RefreshStatus when needed

------------------------------------------------------
-- Layout state
------------------------------------------------------

local function UpdateLockVisual()
    ns.EnsureDB()
    ns.lockIcon[MajesticBeastTrackerDB.settings.locked and "Show" or "Hide"](ns.lockIcon)
end
ns.UpdateLockVisual = UpdateLockVisual

ns._layoutDirty = true  -- force initial layout

function ns.InvalidateLayout()
    ns._layoutDirty = true
    if not ns._layoutPending then
        ns._layoutPending = true
        C_Timer.After(0.1, function()
            ns._layoutPending = nil
            ns.UpdateUI()
        end)
    end
end

------------------------------------------------------
-- computeState() — Pure computation, no UI calls
------------------------------------------------------

local function computeState()
    local frame = ns.frame
    local headerIcons    = ns.headerIcons
    local reagentIcons   = ns.reagentIcons
    local TSM_PRICE_HEIGHT = ns.TSM_PRICE_HEIGHT
    local contentTop     = ns.contentTop
    local CONSUMABLES    = ns.CONSUMABLES

    ns.EnsureDB()
    local currentChar = ns.GetCharKey()
    if not currentChar then return nil end

    -- Ensure current character level is stored
    if MajesticBeastTrackerDB.chars[currentChar] then
        MajesticBeastTrackerDB.chars[currentChar].level = UnitLevel("player")
    end

    -- Reagent layout values
    local showReagents = MajesticBeastTrackerDB.settings.showReagents ~= false
    local showTSM = MajesticBeastTrackerDB.settings.tsmIntegration
    local tsmExtra = (showReagents and TSM_API and showTSM) and TSM_PRICE_HEIGHT or 0
    local reagentExtra = showReagents and (REAGENT_ROW_HEIGHT + tsmExtra) or 0

    -- Route skip computation
    local routeSkip = MajesticBeastTrackerDB.settings.routeSkip or {}
    local harandarMinLvl = MajesticBeastTrackerDB.settings.routeHarandarMinLevel or 80
    local hideSkipped = MajesticBeastTrackerDB.settings.routeHideSkipped or false
    local lureSkipped = {}
    local visibleLureCount = 0
    for li, lure in ipairs(LURES) do
        local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
        lureSkipped[li] = routeSkip[lure.name] or MajesticBeastTrackerDB.settings[skipKey] or false
        if not lureSkipped[li] or not hideSkipped then
            visibleLureCount = visibleLureCount + 1
        end
    end
    local numVisibleLures = hideSkipped and visibleLureCount or #LURES

    -- Map lure index -> visible column index
    local routeOrder = ns.GetRouteOrder()
    local lureToCol = {}
    local colIdx = 0
    for _, li in ipairs(routeOrder) do
        if hideSkipped and lureSkipped[li] then
            lureToCol[li] = -1  -- hidden
        else
            lureToCol[li] = colIdx
            colIdx = colIdx + 1
        end
    end

    -- Count characters needing each lure
    -- charsNeedLure: for Done/Ready display (beast not killed = needs lure)
    -- charsNeedCraft: for reagent calculation (beast not killed AND no lure in bags)
    local hiddenCharsForCount = MajesticBeastTrackerDB.settings.hiddenChars or {}
    local charsNeedLure = {}
    local charsNeedCraft = {}
    for li = 1, #LURES do
        charsNeedLure[li] = 0
        charsNeedCraft[li] = 0
        if not lureSkipped[li] then
            for charKey, cData in pairs(MajesticBeastTrackerDB.chars) do
                if not hiddenCharsForCount[charKey] and ns.CanSeeLure(cData, li) then
                    local skipForLevel = false
                    if LURES[li].name == "Harandar" and cData.level and cData.level < harandarMinLvl then
                        skipForLevel = true
                    end
                    if not skipForLevel then
                        local ts = cData.lures[LURES[li].name]
                        if not ts or ns.IsLureReady(ts) then
                            charsNeedLure[li] = charsNeedLure[li] + 1
                            local hasBagged = cData.lureBags and cData.lureBags[LURES[li].name]
                            if not hasBagged then
                                charsNeedCraft[li] = charsNeedCraft[li] + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Gather eligible characters
    local keys = {}
    local hiddenChars = MajesticBeastTrackerDB.settings.hiddenChars or {}
    local showHidden = MajesticBeastTrackerDB.settings.showHiddenChars
    for key, charData in pairs(MajesticBeastTrackerDB.chars) do
        if charData.hasSkinning and (not hiddenChars[key] or showHidden) then
            keys[#keys + 1] = key
        end
    end
    -- Check if a character has any beast ready to kill (no active cooldown)
    local function hasReadyBeast(charKey)
        local cData = MajesticBeastTrackerDB.chars[charKey]
        if not cData then return false end
        for li, lure in ipairs(LURES) do
            if not lureSkipped[li] then
                local ts = cData.lures[lure.name]
                if not ts or ns.IsLureReady(ts) then
                    return true
                end
            end
        end
        return false
    end
    local readyMap = {}
    for _, key in ipairs(keys) do
        readyMap[key] = hasReadyBeast(key)
    end
    table.sort(keys, function(a, b)
        if a == currentChar then return true end
        if b == currentChar then return false end
        if readyMap[a] ~= readyMap[b] then return readyMap[a] end
        return a < b
    end)

    -- Header height
    local lureHeaderH = reagentExtra + ICON_ROW_HEIGHT + 5
    local consHeaderH = ns.CONS_BOX_HEIGHT + 2 + ns.TRAVEL_ICON_SIZE + 8 + 5
    local headerH = math.max(lureHeaderH, consHeaderH)
    local dynDataTop = contentTop - headerH

    -- Count visible consumables
    local totalVisibleCons = 0
    for _, cons in ipairs(CONSUMABLES) do
        local showKey = "consShow_" .. (cons.itemID or cons.spellID)
        if MajesticBeastTrackerDB.settings[showKey] ~= false then
            totalVisibleCons = totalVisibleCons + 1
        end
    end
    local consSpacing = totalVisibleCons > 0
        and math.max(BASE_NAME_COL_WIDTH / totalVisibleCons, ns.CONS_ITEM_WIDTH)
        or ns.CONS_ITEM_WIDTH
    local consWidth = totalVisibleCons * consSpacing

    -- Travel buttons list (built before column width: the travel row also widens the name column)
    local activeTravelBtns = {}
    for _, btn in ipairs(ns.travelButtons) do
        activeTravelBtns[#activeTravelBtns + 1] = btn
    end
    local showWormhole = ns.HasEngineering() and PlayerHasToy(ns.WORMHOLE_ITEM.itemID)
    if showWormhole then
        activeTravelBtns[#activeTravelBtns + 1] = ns.wormholeBtn
    end
    local _, _, playerClassID = UnitClass("player")
    if playerClassID == 8 then
        activeTravelBtns[#activeTravelBtns + 1] = ns.mageTeleportBtn
    end
    local _, _, playerRaceID = UnitRace("player")
    if playerRaceID == 35 then
        activeTravelBtns[#activeTravelBtns + 1] = ns.vulperaReturnBtn
    end
    if ns.PATH_WINDRUNNERS and IsPlayerSpell(ns.PATH_WINDRUNNERS.spellID) then
        activeTravelBtns[#activeTravelBtns + 1] = ns.pathWindrunnersBtn
    end
    local travelWidth = #activeTravelBtns * (ns.TRAVEL_ICON_SIZE + ns.TRAVEL_SPACING)
    local dynamicNameColWidth = math.max(BASE_NAME_COL_WIDTH, consWidth, travelWidth)

    -- Frame dimensions
    local n = math.max(#keys, 1)
    local MAX_VISIBLE_ROWS = ns.MAX_VISIBLE_ROWS or 15
    local visibleRows = math.min(n, MAX_VISIBLE_ROWS)
    local goblinColWidth = 18
    local w = PAD * 2 + 8 + dynamicNameColWidth + numVisibleLures * COL_WIDTH + goblinColWidth
    local h -- set after actualBarH is computed
    local divY = -(TOOLBAR_HEIGHT + TITLE_HEIGHT + 2 + headerH + visibleRows * ROW_HEIGHT + 2)

    -- Compute TSM grand total (used by both LayoutUI for bar height and RefreshStatus for label)
    local grandTotal = 0
    local allPriced = true
    if showTSM and TSM_API and ns.GetTSMPrice then
        for li, lure in ipairs(LURES) do
            if not lureSkipped[li] and lure.reagents and charsNeedCraft[li] > 0 then
                local reagentAllChars = MajesticBeastTrackerDB.settings.reagentAllChars ~= false
                local numNeed = reagentAllChars and charsNeedCraft[li] or 1
                for _, reagent in ipairs(lure.reagents) do
                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                    local have = itemName and C_Item.GetItemCount(itemName, true, false, true, true) or 0
                    local totalNeed = reagent.count * numNeed
                    local missing = math.max(totalNeed - have, 0)
                    if missing > 0 then
                        local price = ns.GetTSMPrice(reagent.itemID)
                        if price then
                            grandTotal = grandTotal + price * missing
                        else
                            allPriced = false
                        end
                    end
                end
            end
        end
    end
    local hasTSMTotal = allPriced and grandTotal > 0

    -- Bottom bar height: hasAnyStats = current char is a skinner (cheap check, no tooltip scan)
    local curCharData = MajesticBeastTrackerDB.chars[currentChar]
    local hasAnyStats = curCharData and curCharData.hasSkinning
    local actualBarH = 24
    h = TOOLBAR_HEIGHT + TITLE_HEIGHT + 2 + headerH + visibleRows * ROW_HEIGHT + actualBarH + PAD + 10

    -- Loot tracking state
    local lootTrackingOn = MajesticBeastTrackerDB.settings.lootTracking ~= false
    local showConsBorders = MajesticBeastTrackerDB.settings.showConsBorders ~= false
    local showLureBorders = MajesticBeastTrackerDB.settings.showLureBorders ~= false

    return {
        currentChar       = currentChar,
        charData          = MajesticBeastTrackerDB.chars[currentChar],
        keys              = keys,
        lureToCol         = lureToCol,
        lureSkipped       = lureSkipped,
        numVisibleLures   = numVisibleLures,
        showReagents      = showReagents,
        showTSM           = showTSM,
        tsmExtra          = tsmExtra,
        reagentExtra      = reagentExtra,
        hideSkipped       = hideSkipped,
        harandarMinLvl    = harandarMinLvl,
        charsNeedLure     = charsNeedLure,
        charsNeedCraft    = charsNeedCraft,
        hiddenChars       = hiddenChars,
        headerH           = headerH,
        dynDataTop        = dynDataTop,
        totalVisibleCons  = totalVisibleCons,
        consSpacing       = consSpacing,
        dynamicNameColWidth = dynamicNameColWidth,
        w                 = w,
        h                 = h,
        divY              = divY,
        n                 = n,
        activeTravelBtns  = activeTravelBtns,
        lootTrackingOn    = lootTrackingOn,
        hasTSMTotal       = hasTSMTotal,
        grandTotal        = grandTotal,
        hasAnyStats       = hasAnyStats,
        actualBarH        = actualBarH,
        showConsBorders   = showConsBorders,
        showLureBorders   = showLureBorders,
        playerLevel       = UnitLevel("player"),
    }
end

------------------------------------------------------
-- ns.LayoutUI(state) — Positioning only
-- Called only when layoutDirty AND not InCombatLockdown()
------------------------------------------------------

function ns.LayoutUI(state)
    local frame          = ns.frame
    local headerIcons    = ns.headerIcons
    local zoneLabels     = ns.zoneLabels
    local reagentIcons   = ns.reagentIcons
    local lureBoxes      = ns.lureBoxes
    local tsmPriceLabels = ns.tsmPriceLabels
    local contentTop     = ns.contentTop
    local CONSUMABLES    = ns.CONSUMABLES
    local C_TOOLBAR_ICON = ns.C_TOOLBAR_ICON
    local lureToCol      = state.lureToCol
    local showReagents   = state.showReagents
    local reagentExtra   = state.reagentExtra
    local numVisibleLures = state.numVisibleLures
    local keys           = state.keys
    local dynDataTop     = state.dynDataTop
    local headerH        = state.headerH
    local w              = state.w
    local h              = state.h
    local divY           = state.divY
    local currentChar    = state.currentChar
    local hiddenChars    = state.hiddenChars
    local showConsBorders = state.showConsBorders
    local activeTravelBtns = state.activeTravelBtns

    -- Update mutable NAME_COL_WIDTH for this cycle
    NAME_COL_WIDTH = state.dynamicNameColWidth

    -- Reposition lure icons and separator based on reagent visibility + route order
    for i = 1, #LURES do
        if lureToCol[i] == -1 then
            headerIcons[i]:Hide()
        else
            headerIcons[i]:ClearAllPoints()
            local lureY = contentTop - 2 - reagentExtra
            if not showReagents then
                local consTravelH = ns.CONS_BOX_HEIGHT + 2 + ns.TRAVEL_ICON_SIZE + 8
                local lureH = ICON_SIZE + ZONE_LABEL_HEIGHT + 2
                local vPad = math.max((consTravelH - lureH) / 2, 0)
                lureY = contentTop - 2 - vPad
            end
            headerIcons[i]:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PAD + 4 + NAME_COL_WIDTH + lureToCol[i] * COL_WIDTH + (COL_WIDTH - ICON_SIZE) / 2,
                lureY)
            zoneLabels[i]:ClearAllPoints()
            zoneLabels[i]:SetPoint("TOP", headerIcons[i], "BOTTOM", 0, -1)
        end
    end

    -- Position consumable box at contentTop
    ns.consumableBox:ClearAllPoints()
    ns.consumableBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, contentTop - 2)

    -- iconSep: below whichever is taller (lure icons or consumable+travel)
    local lureSepY = contentTop - reagentExtra - ICON_ROW_HEIGHT - 2
    local consSepY = contentTop - 2 - ns.CONS_BOX_HEIGHT - 2 - ns.TRAVEL_ICON_SIZE - 8 - 4
    local sepY = math.min(lureSepY, consSepY)
    ns.iconSep:ClearAllPoints()
    ns.iconSep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, sepY)
    ns.iconSep:SetPoint("RIGHT", frame, "RIGHT", -(PAD + 4), 0)

    -- Hide all rows, then create/position visible ones
    ns.HideAllRows()

    local scrollParent = ns.charScrollChild or frame
    for idx, key in ipairs(keys) do
        if not charRows[idx] then
            charRows[idx] = CreateCharRow(idx)
        end
        local row = charRows[idx]
        local yOff = -(idx - 1) * ROW_HEIGHT  -- relative to scroll child top

        -- Row positioning (relative to scroll child)
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", PAD + 6, yOff)
        if row.bg then
            row.bg:ClearAllPoints()
            row.bg:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", 5, yOff)
            row.bg:SetPoint("RIGHT", scrollParent, "RIGHT", -5, 0)
        end

        -- Cell positioning based on lureToCol
        for ci = 1, #LURES do
            if row.cells and row.cells[ci] then
                local col = lureToCol[ci]
                if col and col >= 0 then
                    row.cells[ci]:ClearAllPoints()
                    row.cells[ci]:SetPoint("TOPLEFT", scrollParent, "TOPLEFT",
                        PAD + 4 + NAME_COL_WIDTH + col * COL_WIDTH, yOff)
                end
            end
        end

        -- Goblin icon positioning
        if row.goblinBtn then
            row.goblinBtn:ClearAllPoints()
            local goblinX = PAD + 4 + NAME_COL_WIDTH + numVisibleLures * COL_WIDTH + 4
            row.goblinBtn:SetPoint("LEFT", scrollParent, "TOPLEFT", goblinX, yOff - ROW_HEIGHT / 2)
        end

        -- Tool icon layout (SecureActionButton — combat guard is caller's responsibility)
        if row.toolIcon then
            local showTool = false
            if key == currentChar then
                local razorID = 237372
                local showKey = "consShow_" .. razorID
                local enchantActive = ns.GetToolEnchantRemaining and ns.GetToolEnchantRemaining() and ns.GetToolEnchantRemaining() > 0
                if MajesticBeastTrackerDB.settings[showKey] ~= false and not enchantActive then
                    pcall(function()
                        local prof1, prof2 = GetProfessions()
                        local profID
                        if prof1 then
                            local _, _, _, _, _, _, sklID, _, _, _, _, pID = GetProfessionInfo(prof1)
                            if sklID == 393 then profID = pID or Enum.Profession.Skinning end
                        end
                        if not profID and prof2 then
                            local _, _, _, _, _, _, sklID, _, _, _, _, pID = GetProfessionInfo(prof2)
                            if sklID == 393 then profID = pID or Enum.Profession.Skinning end
                        end
                        if profID then
                            local s = C_TradeSkillUI.GetProfessionSlots(profID)
                            if s and s[1] then
                                local itemID = GetInventoryItemID("player", s[1])
                                if itemID then
                                    local tex = ns.GetItemIcon(itemID)
                                    if tex then
                                        row.toolIcon.icon:SetTexture(tex)
                                        row.toolIcon.slotID = s[1]
                                        row.toolIcon._pendingSlot = s[1]
                                        showTool = true
                                    end
                                end
                            end
                        end
                    end)
                end
            end
            if showTool then
                if row.toolIcon._pendingSlot then
                    row.toolIcon:SetAttribute("macrotext", "/use " .. row.toolIcon._pendingSlot)
                    row.toolIcon._pendingSlot = nil
                end
                row.toolIcon:ClearAllPoints()
                row.toolIcon:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", PAD + 6, yOff)
                row.toolIcon:Show()
                row.nameLabel:ClearAllPoints()
                row.nameLabel:SetPoint("LEFT", row.name, "LEFT", ROW_HEIGHT, 0)
                row.nameLabel:SetPoint("RIGHT", row.name, "RIGHT", 0, 0)
            else
                row.toolIcon:Hide()
                row.nameLabel:ClearAllPoints()
                row.nameLabel:SetPoint("TOPLEFT", row.name, "TOPLEFT", 0, 0)
                row.nameLabel:SetPoint("BOTTOMRIGHT", row.name, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- Reagent icon repositioning
    for i, lure in ipairs(LURES) do
        if lureToCol[i] == -1 then
            if reagentIcons[i] then
                for _, rBtn in ipairs(reagentIcons[i]) do rBtn:Hide() end
            end
        elseif reagentIcons[i] and showReagents and lure.reagents then
            local col = lureToCol[i]
            local lureCenter = PAD + 4 + NAME_COL_WIDTH + col * COL_WIDTH + COL_WIDTH / 2
            local numR = #lure.reagents
            local totalW = numR * REAGENT_ICON_SIZE + (numR - 1) * REAGENT_GAP
            for j, rBtn in ipairs(reagentIcons[i]) do
                rBtn:ClearAllPoints()
                local rx = lureCenter - totalW / 2 + (j - 1) * (REAGENT_ICON_SIZE + REAGENT_GAP)
                rBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", rx, contentTop - 2 - 1)
            end
        end
    end

    -- Consumable button positioning
    local visibleConsIdx = 0
    for i, cons in ipairs(CONSUMABLES) do
        local btn = ns.consumableButtons[i]
        local showKey = "consShow_" .. (cons.itemID or cons.spellID)
        local isVisible = MajesticBeastTrackerDB.settings[showKey] ~= false
        if isVisible and frame:IsShown() then
            btn:ClearAllPoints()
            local consSpacing = state.consSpacing
            local xOffset = visibleConsIdx * consSpacing + (consSpacing - ns.CONS_ICON_SIZE) / 2
            btn:SetPoint("TOPLEFT", ns.consumableBox, "TOPLEFT",
                xOffset, -ns.CONS_PAD)
            ns.consumableLabels[i]:ClearAllPoints()
            ns.consumableLabels[i]:SetPoint("TOP", btn, "BOTTOM", 0, -1)
            ns.consumableLabels[i]:SetJustifyH("CENTER")
            btn:Show()
            ns.consumableLabels[i]:Show()
            visibleConsIdx = visibleConsIdx + 1
        else
            btn:Hide()
            ns.consumableLabels[i]:Hide()
        end
    end

    -- Resize consumable box
    if visibleConsIdx > 0 and frame:IsShown() then
        ns.consumableBox:SetWidth(NAME_COL_WIDTH)
        ns.consumableBox:SetBackdrop(showConsBorders and BACKDROP or nil)
        if showConsBorders then
            ns.consumableBox:SetBackdropColor(0, 0, 0, 0.9)
            ns.consumableBox:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3], 0.7)
        end
        ns.consumableBox:Show()
    else
        NAME_COL_WIDTH = BASE_NAME_COL_WIDTH
        ns.consumableBox:Hide()
    end

    -- Row counts for scroll + frame sizing
    local totalRows = math.max(#keys, 1)
    local MAX_VIS = ns.MAX_VISIBLE_ROWS or 15
    local visRows = math.min(totalRows, MAX_VIS)

    -- Bottom bar height from state (single source of truth)
    local bottomBar = ns.tsmTotalLabel:GetParent()
    bottomBar:SetHeight(state.actualBarH)
    frame:SetSize(w, h)

    -- Scroll area for character rows
    local scrollTop = -(TOOLBAR_HEIGHT + TITLE_HEIGHT + 2 + headerH)
    local scrollBottom = state.actualBarH + PAD + 6
    if ns.charScroll then
        ns.charScroll:ClearAllPoints()
        ns.charScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, scrollTop)
        ns.charScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, scrollBottom)
        ns.charScrollChild:SetWidth(w - 12)
        ns.charScrollChild:SetHeight(totalRows * ROW_HEIGHT + 4)
        ns.charScrollbar:ClearAllPoints()
        ns.charScrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, scrollTop)
        ns.charScrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, scrollBottom)
        -- Update scrollbar
        local viewH = visRows * ROW_HEIGHT
        local contentH = totalRows * ROW_HEIGHT
        if contentH > viewH then
            ns.charScrollbar:SetMinMaxValues(0, contentH - viewH)
            ns.charScrollbar:SetValueStep(ROW_HEIGHT * 3)
            local ratio = viewH / contentH
            ns.charScrollbar.thumb:SetHeight(math.max(viewH * ratio, 20))
            ns.charScrollbar:Show()
        else
            ns.charScroll:SetVerticalScroll(0)
            ns.charScrollbar:SetValue(0)
            ns.charScrollbar:Hide()
        end
    end

    -- Travel separator hidden
    ns.travelSep:Hide()

    -- Hide all travel buttons first
    for _, btn in ipairs(ns.travelButtons) do btn:Hide() end
    ns.wormholeBtn:Hide()
    ns.mageTeleportBtn:Hide()
    ns.vulperaReturnBtn:Hide()
    ns.pathWindrunnersBtn:Hide()

    -- Travel box positioning
    local numTravel = #activeTravelBtns
    ns.travelBox:ClearAllPoints()
    ns.travelBox:SetPoint("TOPLEFT", ns.consumableBox, "BOTTOMLEFT", 0, -2)
    ns.travelBox:SetWidth(NAME_COL_WIDTH)
    ns.travelBox:SetHeight(ns.TRAVEL_ICON_SIZE + 8)

    local travelSpacing = numTravel > 0 and math.max(NAME_COL_WIDTH / numTravel, ns.TRAVEL_ICON_SIZE + ns.TRAVEL_SPACING) or 0
    for idx, btn in ipairs(activeTravelBtns) do
        btn:ClearAllPoints()
        btn:SetParent(ns.travelBox)
        local xOff = (idx - 1) * travelSpacing + (travelSpacing - ns.TRAVEL_ICON_SIZE) / 2
        btn:SetPoint("TOPLEFT", ns.travelBox, "TOPLEFT", xOff, -4)
        if frame:IsShown() then
            btn:Show()
        end
    end
    if numTravel > 0 and frame:IsShown() then
        ns.travelBox:SetBackdrop(showConsBorders and BACKDROP or nil)
        if showConsBorders then
            ns.travelBox:SetBackdropColor(0, 0, 0, 0.9)
            ns.travelBox:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3], 0.7)
        end
        ns.travelBox:Show()
    else
        ns.travelBox:Hide()
    end

    -- Stats + TSM total inside bottom bar (center stack component)
    local statsTexts = ns.statsTexts
    local STAT_LABELS = ns.STAT_LABELS
    local profStats = ns.CalculateProfessionStats and ns.CalculateProfessionStats() or nil
    local hasAnyStats = state.hasAnyStats

    -- Stats centered inside bottom bar
    local statsOffsetY = ns.tsmTotalLabel:IsShown() and 6 or 0
    if hasAnyStats and profStats then
        local visibleStats = {}
        for i, stat in ipairs(STAT_LABELS) do
            local val = profStats[stat.key] or 0
            if val > 0 then
                statsTexts[i]:SetText(stat.label .. ":" .. val)
                visibleStats[#visibleStats + 1] = i
            else
                statsTexts[i]:Hide()
            end
        end
        -- Measure total width first
        local totalW = 0
        for _, si in ipairs(visibleStats) do
            totalW = totalW + statsTexts[si]:GetStringWidth() + 6
        end
        -- Center the block horizontally in bottom bar
        local statsX = totalW / 2
        for ri = 1, #visibleStats do
            local si = visibleStats[ri]
            statsTexts[si]:ClearAllPoints()
            statsTexts[si]:SetPoint("LEFT", bottomBar, "CENTER", -statsX, statsOffsetY)
            statsX = statsX - statsTexts[si]:GetStringWidth() - 6
            statsTexts[si]:Show()
        end
    else
        for i = 1, #STAT_LABELS do
            statsTexts[i]:Hide()
        end
    end

    -- Weekly knowledge removed from main window (visible in character detail popup)
end

------------------------------------------------------
-- ns.RefreshStatus(state) — Data-only updates
-- SetText, SetTextColor, SetAlpha, SetDesaturated, etc.
-- Runs every UpdateUI call (even if layout is not dirty)
------------------------------------------------------

function ns.RefreshStatus(state)
    local frame          = ns.frame
    local headerIcons    = ns.headerIcons
    local zoneLabels     = ns.zoneLabels
    local reagentIcons   = ns.reagentIcons
    local lureBoxes      = ns.lureBoxes
    local tsmPriceLabels = ns.tsmPriceLabels
    local TSM_PRICE_HEIGHT = ns.TSM_PRICE_HEIGHT
    local contentTop     = ns.contentTop
    local CONSUMABLES    = ns.CONSUMABLES
    local C_TOOLBAR_ICON = ns.C_TOOLBAR_ICON
    local C_TOOLBAR_ICON_HOVER = ns.C_TOOLBAR_ICON_HOVER
    local lureToCol      = state.lureToCol
    local showReagents   = state.showReagents
    local reagentExtra   = state.reagentExtra
    local currentChar    = state.currentChar
    local charData       = state.charData
    local keys           = state.keys
    local lureSkipped    = state.lureSkipped
    local harandarMinLvl = state.harandarMinLvl
    local numVisibleLures = state.numVisibleLures
    local charsNeedLure  = state.charsNeedLure
    local hiddenChars    = state.hiddenChars
    local dynDataTop     = state.dynDataTop
    local showTSM        = state.showTSM
    local lootTrackingOn = state.lootTrackingOn
    local showLureBorders = state.showLureBorders
    local showConsBorders = state.showConsBorders
    local w              = state.w
    local divY           = state.divY

    -- Update mutable NAME_COL_WIDTH for this cycle
    NAME_COL_WIDTH = state.dynamicNameColWidth

    -- Local references to UI elements from ns
    local fishIcon     = ns.fishIcon
    local fishBtn      = ns.fishBtn
    local coinIcon     = ns.coinIcon
    local coinBtn      = ns.coinBtn
    local autoHideIcon = ns.autoHideIcon
    local timerLabel   = ns.timerLabel
    local timerBtn     = ns.timerBtn

    -- Header icons: texture, count, glow, desaturation
    for i, lure in ipairs(LURES) do
        local isHidden = lureToCol[i] == -1
        if isHidden then
            if not InCombatLockdown() then headerIcons[i]:Hide() end
            zoneLabels[i]:Hide()
            if reagentIcons[i] then
                for _, rBtn in ipairs(reagentIcons[i]) do rBtn:Hide() end
            end
            if lureBoxes[i] then lureBoxes[i]:Hide() end
            if tsmPriceLabels[i] then tsmPriceLabels[i]:Hide() end
        else
            local tex = ns.GetItemIcon(lure.itemID)
            if tex then headerIcons[i].icon:SetTexture(tex) end

            local canCraft = charData and ns.CanSeeLure(charData, i)
            headerIcons[i].icon:SetDesaturated(not canCraft)
            headerIcons[i].icon:SetAlpha(canCraft and 1.0 or 0.4)

            -- Craftable count
            local craftable = ns.GetCraftableCount(lure.recipeID)
            local lureName = C_Item.GetItemNameByID(lure.itemID)
            if not lureName then C_Item.RequestLoadItemDataByID(lure.itemID) end
            local inBags = lureName and C_Item.GetItemCount(lureName) or C_Item.GetItemCount(lure.itemID)

            if inBags > 0 or craftable > 0 then
                local text = ""
                if inBags > 0 and craftable > 0 then
                    text = "|cffffffff" .. inBags .. "|r+|cff00ff00" .. craftable .. "|r"
                elseif inBags > 0 then
                    text = "|cffffffff" .. inBags .. "|r"
                else
                    text = "|cff00ff00" .. craftable .. "|r"
                end
                headerIcons[i].countText:SetText(text)
                headerIcons[i].countText:Show()
            else
                headerIcons[i].countText:SetText("")
                headerIcons[i].countText:Hide()
            end

            -- Glow
            local lureReady = charData and ns.CanSeeLure(charData, i)
                and (not charData.lures[lure.name] or ns.IsLureReady(charData.lures[lure.name]))
            if inBags > 0 and lureReady then
                headerIcons[i].glow.Show()
            else
                headerIcons[i].glow.Hide()
            end

            if not InCombatLockdown() then
                headerIcons[i]:Show()
            end
            zoneLabels[i]:Show()
        end
    end

    -- Reagent icon data (textures, counts, desaturation, tooltips)
    for i, lure in ipairs(LURES) do
        if lureToCol[i] == -1 then
            if reagentIcons[i] then
                for _, rBtn in ipairs(reagentIcons[i]) do rBtn:Hide() end
            end
        elseif reagentIcons[i] and showReagents and lure.reagents then
            local numNeedKill = charsNeedLure[i]   -- for Done/Ready display
            local numNeedCraft = state.charsNeedCraft[i]  -- for reagent calculation (excludes bagged lures)
            local anyMissing = false

            -- First pass: textures, desaturation, tooltips
            for j, rBtn in ipairs(reagentIcons[i]) do
                if lure.reagents[j] then
                    local reagent = lure.reagents[j]
                    local tex = ns.GetItemIcon(reagent.itemID)
                    if tex then rBtn.icon:SetTexture(tex) end

                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                    local have = 0
                    if itemName then
                        have = C_Item.GetItemCount(itemName, true, false, true, true)
                    else
                        have = C_Item.GetItemCount(reagent.itemID, true, false, true, true)
                    end
                    local perLure = reagent.count
                    local reagentAllChars = MajesticBeastTrackerDB.settings.reagentAllChars ~= false
                    local totalNeed = perLure * (reagentAllChars and numNeedCraft or 1)
                    local missing = math.max(totalNeed - have, 0)

                    rBtn.icon:SetDesaturated(missing > 0 and numNeedCraft > 0)
                    if missing > 0 then anyMissing = true end

                    rBtn._have = have
                    rBtn._missing = missing
                    rBtn._totalNeed = totalNeed

                    rBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
                        GameTooltip:SetItemByID(reagent.itemID)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(string.format("Per lure: %d  |  Need craft: %d  |  Need kill: %d",
                            perLure, numNeedCraft, numNeedKill), 0.8, 0.8, 0.8)
                        if numNeedCraft > 0 then
                            GameTooltip:AddLine(string.format("Need: %d  |  Have: %d",
                                totalNeed, have), 1, 1, 1)
                            if missing > 0 then
                                GameTooltip:AddLine("Missing: " .. missing, 0.9, 0.3, 0.3)
                            else
                                GameTooltip:AddLine("Ready to go!", 0.2, 0.9, 0.4)
                            end
                        elseif numNeedKill > 0 then
                            GameTooltip:AddLine("Lures crafted, waiting for kills", 1, 0.82, 0)
                        else
                            GameTooltip:AddLine("All characters done!", 0.2, 0.9, 0.4)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Shift-click: Link to chat", 0.5, 0.8, 1)
                        GameTooltip:Show()
                    end)

                    rBtn:Show()
                else
                    rBtn:Hide()
                end
            end

            -- Second pass: count text
            local anyEligible = false
            for _, cData in pairs(MajesticBeastTrackerDB.chars) do
                if ns.CanSeeLure(cData, i) then anyEligible = true; break end
            end
            -- alwaysShowReagentCounts: keep numeric counts visible even when Done/Ready
            -- (for stocking up ahead of time); "Locked" always wins
            local alwaysShowCounts = MajesticBeastTrackerDB.settings.alwaysShowReagentCounts
            local singleLabel
            if not anyEligible then
                singleLabel = "|cff666666Locked|r"
            elseif numNeedKill == 0 then
                if not alwaysShowCounts then singleLabel = "|cff00ff00Done|r" end
            elseif not anyMissing then
                if not alwaysShowCounts then singleLabel = "|cff00ff00Ready|r" end
            end
            for j, rBtn in ipairs(reagentIcons[i]) do
                if rBtn.countText and lure.reagents[j] then
                    if singleLabel then
                        if j == 1 then
                            rBtn.countText:SetText(singleLabel)
                            rBtn.countText:ClearAllPoints()
                            local numR = #lure.reagents
                            local totalW = numR * REAGENT_ICON_SIZE + (numR - 1) * REAGENT_GAP
                            local offsetX = totalW / 2 - REAGENT_ICON_SIZE / 2
                            rBtn.countText:SetPoint("TOP", rBtn, "BOTTOM", offsetX, -1)
                            rBtn.countText:Show()
                        else
                            rBtn.countText:SetText("")
                        end
                    elseif MajesticBeastTrackerDB.settings.showMissingCount then
                        rBtn.countText:ClearAllPoints()
                        rBtn.countText:SetPoint("TOP", rBtn, "BOTTOM", 0, -1)
                        rBtn.countText:SetJustifyH("CENTER")
                        rBtn.countText:SetWidth(COL_WIDTH)
                        local missing = rBtn._missing or 0
                        if missing > 0 then
                            rBtn.countText:SetText("|cffff3333-" .. missing .. "|r")
                        elseif alwaysShowCounts then
                            rBtn.countText:SetText("|cff00ff00" .. (rBtn._have or 0) .. "|r")
                        else
                            rBtn.countText:SetText("|cff00ff00" .. ns.CHECKMARK_ICON .. "|r")
                        end
                        rBtn.countText:Show()
                    else
                        rBtn.countText:ClearAllPoints()
                        local numR = #lure.reagents
                        if numR > 1 and j == 1 then
                            rBtn.countText:SetPoint("TOPLEFT", rBtn, "BOTTOMLEFT", -6, -1)
                            rBtn.countText:SetJustifyH("LEFT")
                        elseif numR > 1 and j == numR then
                            rBtn.countText:SetPoint("TOPRIGHT", rBtn, "BOTTOMRIGHT", 6, -1)
                            rBtn.countText:SetJustifyH("RIGHT")
                        else
                            rBtn.countText:SetPoint("TOP", rBtn, "BOTTOM", 0, -1)
                            rBtn.countText:SetJustifyH("CENTER")
                        end
                        local maxW = numR > 1 and (COL_WIDTH / 2 - 1) or COL_WIDTH
                        rBtn.countText:SetWidth(maxW)
                        local have = rBtn._have or 0
                        local total = rBtn._totalNeed or 0
                        local missingVal = rBtn._missing or 0
                        if missingVal > 0 then
                            rBtn.countText:SetText("|cffff3333" .. have .. "/" .. total .. "|r")
                        else
                            rBtn.countText:SetText("|cff00ff00" .. have .. "|r")
                        end
                        rBtn.countText:Show()
                    end
                end
            end
        elseif reagentIcons[i] then
            for _, rBtn in ipairs(reagentIcons[i]) do
                rBtn:Hide()
            end
        end
    end

    -- TSM price labels
    local hasTSM = TSM_API ~= nil
    local showTSMPrices = hasTSM and showReagents and showTSM
    for i, lure in ipairs(LURES) do
        local label = tsmPriceLabels[i]
        if showTSMPrices and lure.reagents then
            local totalCost = 0
            local hasPrice = true
            for j, rBtn in ipairs(reagentIcons[i]) do
                if lure.reagents[j] then
                    local missing = rBtn._missing or 0
                    if missing > 0 then
                        local price = ns.GetTSMPrice(lure.reagents[j].itemID)
                        if price then
                            totalCost = totalCost + price * missing
                        else
                            hasPrice = false
                            break
                        end
                    end
                end
            end
            if hasPrice and totalCost > 0 then
                label:SetText(ns.FormatGold(totalCost))
                label:SetTextColor(1, 0.84, 0)
                label:ClearAllPoints()
                local colCenter = PAD + 4 + NAME_COL_WIDTH + lureToCol[i] * COL_WIDTH + COL_WIDTH / 2
                label:SetPoint("TOP", frame, "TOPLEFT", colCenter, contentTop - 2 - REAGENT_ICON_SIZE - REAGENT_COUNT_HEIGHT - 3)
                label:Show()
            else
                label:Hide()
            end
        else
            label:Hide()
        end
    end

    -- Lure column boxes
    for i, lure in ipairs(LURES) do
        local box = lureBoxes[i]
        if not showLureBorders or lureToCol[i] == -1 then
            box:Hide()
        else
            local boxPad = 3
            local colX = PAD + 4 + NAME_COL_WIDTH + lureToCol[i] * COL_WIDTH
            local boxTop = contentTop - 2 + boxPad
            local boxBottom
            if showReagents and lure.reagents and #lure.reagents > 0 then
                boxBottom = contentTop - 2 - reagentExtra - ICON_SIZE - boxPad
            else
                local consTravelH = ns.CONS_BOX_HEIGHT + 2 + ns.TRAVEL_ICON_SIZE + 8
                boxBottom = contentTop - 2 - consTravelH + boxPad
            end
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", frame, "TOPLEFT", colX - boxPad, boxTop)
            box:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", colX + COL_WIDTH + boxPad, boxBottom)
            box:Show()
        end
    end

    -- Fish toggle button visual
    fishIcon:SetDesaturated(not showReagents)
    fishIcon:SetAlpha(showReagents and 1.0 or 0.4)
    fishBtn:Show()

    -- Autohide button visual
    local ahEnabled = MajesticBeastTrackerDB.settings.autoHide
    autoHideIcon:SetTexture(MEDIA_PATH .. (ahEnabled and "Icon_Show" or "Icon_Hide"))
    autoHideIcon:SetAlpha(ahEnabled and 1.0 or 0.4)

    -- Coin toggle button visual
    local tsmEnabled = MajesticBeastTrackerDB.settings.tsmIntegration
    local tsmActive = tsmEnabled and TSM_API
    coinIcon:SetDesaturated(not tsmActive)
    coinIcon:SetAlpha(tsmActive and 1.0 or 0.4)
    coinBtn:Show()

    -- Global goblin button state
    ns.globalGoblinIcon:SetDesaturated(not lootTrackingOn)
    ns.globalGoblinIcon:SetAlpha(lootTrackingOn and 1.0 or 0.4)
    ns.globalGoblinBtn:ClearAllPoints()
    ns.globalGoblinBtn:SetPoint("RIGHT", coinBtn, "LEFT", -2, 0)
    ns.globalGoblinBtn:Show()

    -- Dynamic button chain: globalGoblin <- auctionator <- warbank
    local lastBtn = ns.globalGoblinBtn
    if C_AddOns.IsAddOnLoaded("Auctionator") then
        ns.auctionatorBtn:ClearAllPoints()
        ns.auctionatorBtn:SetPoint("RIGHT", lastBtn, "LEFT", -2, 0)
        ns.auctionatorBtn:Show()
        lastBtn = ns.auctionatorBtn
    else
        ns.auctionatorBtn:Hide()
    end
    if ns.isBankOpen and MajesticBeastTrackerDB.settings.warbankDeposit then
        ns.warbankBtn:ClearAllPoints()
        ns.warbankBtn:SetPoint("RIGHT", lastBtn, "LEFT", -2, 0)
        ns.warbankBtn:Show()
    else
        ns.warbankBtn:Hide()
    end

    -- Character row data
    for idx, key in ipairs(keys) do
        if not charRows[idx] then
            charRows[idx] = CreateCharRow(idx)
        end
        local row = charRows[idx]
        local yOff = dynDataTop - (idx - 1) * ROW_HEIGHT
        local cData = MajesticBeastTrackerDB.chars[key]
        row._charKey = key
        local classColor = ns.GetClassColor(cData.class)
        local name = ns.GetDemoName(key)
        if key == currentChar then name = name .. " *" end
        local isCharHidden = hiddenChars[key]
        if isCharHidden then name = name .. " |cff666666(hidden)|r" end

        row.nameLabel:SetText(classColor .. name .. "|r")

        -- Name button click handler
        row.name:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                local isHidden = MajesticBeastTrackerDB.settings.hiddenChars[key]
                local items = {
                    { text = ns.GetDemoName(key), isTitle = true },
                    { text = isHidden and "|cff00ff00Show character|r" or "|cff999999Hide character|r", func = function()
                        if isHidden then
                            MajesticBeastTrackerDB.settings.hiddenChars[key] = nil
                        else
                            MajesticBeastTrackerDB.settings.hiddenChars[key] = true
                        end
                        ns.UpdateUI()
                    end },
                    { text = "|cffff4444Remove character|r", func = function()
                        StaticPopup_Show("MBT_REMOVE_CHAR", ns.GetDemoName(key), nil, key)
                    end },
                }
                ns.ShowDropdown(self, items)
            else
                if ns.gearPopup:IsShown() and ns.gearPopup.currentKey == key then
                    ns.gearPopup:Hide()
                else
                    ns.gearPopup.currentKey = key
                    ns.ShowGearPopup(self, key)
                end
            end
        end)
        row.name:Show()
        if row.bg then row.bg:Show() end

        -- Cell data
        for i, lure in ipairs(LURES) do
            local cell = row.cells[i]
            cell.charKey = key
            local canSee = ns.CanSeeLure(cData, i)
            local isSkipped = lureSkipped[i]
            if not isSkipped and lure.name == "Harandar" and cData.level and cData.level < harandarMinLvl then
                isSkipped = true
            end
            if lureToCol[i] == -1 then
                cell:Hide()
            elseif isSkipped then
                cell.label:SetText("|cffff4444Skip|r")
                cell.label:SetTextColor(1, 0.27, 0.27)
                cell:SetScript("OnClick", nil)
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
                    GameTooltip:AddLine("Skipped via Route settings", 0.9, 0.3, 0.3)
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                cell:Show()
            else
                local text, r, g, b = ns.GetStatusText(cData, lure.name)
                cell.label:SetText(text)
                if canSee then
                    cell.label:SetTextColor(r, g, b)
                else
                    cell.label:SetTextColor(r * 0.5, g * 0.5, b * 0.5)
                end
                if canSee then
                    cell:SetScript("OnClick", function()
                        ns.EnsureDB()
                        local cd = MajesticBeastTrackerDB.chars[key]
                        if not cd then return end
                        local ts = cd.lures[lure.name]
                        if not ts or ns.IsLureReady(ts) then
                            cd.lures[lure.name] = GetServerTime()
                            if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                                print("|cff3FC7EB[MBT]|r " .. lure.color .. lure.name .. "|r marked for " .. key)
                            end
                        else
                            cd.lures[lure.name] = nil
                            if MajesticBeastTrackerDB.settings.chatNotify ~= false then
                                print("|cff3FC7EB[MBT]|r " .. lure.color .. lure.name .. "|r cleared for " .. key)
                            end
                        end
                        ns.UpdateUI()
                    end)
                    cell:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
                        local ts = cData.lures[lure.name]
                        if not ts or ns.IsLureReady(ts) then
                            GameTooltip:AddLine("Click to mark as killed", 0.7, 0.7, 0.7)
                        else
                            GameTooltip:AddLine("Click to clear", 0.7, 0.7, 0.7)
                        end
                        GameTooltip:Show()
                    end)
                    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    cell:SetScript("OnClick", nil)
                    cell:SetScript("OnEnter", nil)
                    cell:SetScript("OnLeave", nil)
                end
                cell:Show()
            end
        end

        -- Per-character goblin loot icon
        local goblin = row.goblinBtn
        if goblin then
            if not lootTrackingOn then
                goblin.icon:SetDesaturated(true)
                goblin.icon:SetAlpha(0.2)
                goblin:SetScript("OnEnter", nil)
                goblin:SetScript("OnClick", nil)
                goblin:Show()
            else
                local loot = ns.GetCharLoot(cData)
                local hasLoot = loot and loot.allTime and next(loot.allTime)
                goblin.icon:SetDesaturated(not hasLoot)
                goblin.icon:SetAlpha(hasLoot and 1.0 or 0.4)
                local capturedKey = key
                local capturedData = cData
                goblin:SetScript("OnEnter", function(self)
                    self.icon:SetVertexColor(C_TOOLBAR_ICON_HOVER[1], C_TOOLBAR_ICON_HOVER[2], C_TOOLBAR_ICON_HOVER[3], 1)
                    local charLoot = ns.GetCharLoot(capturedData)
                    if charLoot and hasLoot then
                        ns.ShowLootTooltip(self, ns.GetDemoName(capturedKey) .. " - Loot",
                            charLoot.thisReset, charLoot.allTime, charLoot.prices,
                            charLoot.trackedKills, charLoot.trackedPerBeast)
                    else
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT", -4, 0)
                        GameTooltip:AddLine(ns.GetDemoName(capturedKey) .. " - Loot", 0.82, 0.71, 0.35)
                        GameTooltip:AddLine("No loot data yet", 0.5, 0.5, 0.5)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Click to edit loot", 0.5, 0.8, 1)
                        GameTooltip:Show()
                    end
                end)
                goblin:SetScript("OnLeave", function(self)
                    self.icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
                    ns.HideLootTooltip()
                    GameTooltip:Hide()
                end)
                goblin:Show()
            end
        end
    end

    -- Consumable icon textures/desaturation (NOT positioning)
    local playerLevel = state.playerLevel
    for i, cons in ipairs(CONSUMABLES) do
        local meetsLevel = not cons.minLevel or playerLevel >= cons.minLevel
        ns.consumableIcons[i].icon:SetDesaturated(not meetsLevel)
        ns.consumableIcons[i].icon:SetAlpha(meetsLevel and 1.0 or 0.4)
        if cons.isSpell then
            local spellInfo = C_Spell.GetSpellInfo(cons.spellID)
            if spellInfo and spellInfo.iconID then
                ns.consumableIcons[i].icon:SetTexture(spellInfo.iconID)
            end
        elseif cons.itemID then
            local tex = ns.GetItemIcon(cons.itemID)
            if tex then ns.consumableIcons[i].icon:SetTexture(tex) end
        end
    end

    -- TSM total label (uses pre-computed grandTotal from computeState)
    if state.hasTSMTotal then
        ns.tsmTotalLabel:SetText("Total needed: " .. ns.FormatGold(state.grandTotal))
        ns.tsmTotalLabel:ClearAllPoints()
        ns.tsmTotalLabel:SetPoint("CENTER", ns.tsmTotalLabel:GetParent(), "CENTER", 0, -6)
        ns.tsmTotalLabel:Show()
    else
        ns.tsmTotalLabel:Hide()
    end

    -- Reposition stats based on TSM label visibility
    local newStatsY = ns.tsmTotalLabel:IsShown() and 6 or 0
    local bottomBar = ns.tsmTotalLabel:GetParent()
    for _, st in ipairs(ns.statsTexts) do
        if st:IsShown() then
            local _, _, _, _, oldY = st:GetPoint()
            if oldY and math.abs(oldY - newStatsY) > 1 then
                local point, rel, relPoint, x = st:GetPoint()
                st:ClearAllPoints()
                st:SetPoint(point, rel, relPoint, x, newStatsY)
            end
        end
    end

    -- Travel button icon textures + cooldown sweeps
    for _, btn in ipairs(state.activeTravelBtns) do
        if btn.itemInfo.isSpell then
            local spellInfo = C_Spell.GetSpellInfo(btn.itemInfo.spellID)
            if spellInfo and spellInfo.iconID then btn.icon:SetTexture(spellInfo.iconID) end
            local cdInfo = C_Spell.GetSpellCooldown(btn.itemInfo.spellID)
            if cdInfo and cdInfo.duration and not issecretvalue(cdInfo.duration) and cdInfo.duration > 0 then
                btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            else
                btn.cooldown:Clear()
            end
        else
            local tex = ns.GetItemIcon(btn.itemInfo.itemID)
            if tex then btn.icon:SetTexture(tex) end
            local start, duration, enable = C_Item.GetItemCooldown(btn.itemInfo.itemID)
            if start and duration and not issecretvalue(duration) and duration > 0 then
                btn.cooldown:SetCooldown(start, duration)
            else
                btn.cooldown:Clear()
            end
        end
    end

    -- Timer display
    if ns.IsTimerRunning() then
        timerLabel:SetText("|cff00ff00" .. ns.FormatTimerElapsed() .. "|r")
    elseif ns.GetTimerElapsed() > 0 then
        timerLabel:SetText("|cff888888" .. ns.FormatTimerElapsed() .. "|r")
    else
        timerLabel:SetText("|cff555555" .. ns.FormatTimerElapsed() .. "|r")
    end
    timerLabel:Show()
    timerBtn:SetWidth(math.max(timerLabel:GetStringWidth() + 4, 50))
    timerBtn:Show()

    -- Empty state row
    if #keys == 0 then
        if not charRows[1] then charRows[1] = CreateCharRow(1) end
        charRows[1].nameLabel:SetText(ns.C_ACCENT:WrapTextInColorCode("No skinners found"))
        if not InCombatLockdown() then charRows[1].name:SetWidth(w - PAD * 2) end
        charRows[1].name:SetScript("OnClick", nil)
        charRows[1].name:Show()
        for _, cell in ipairs(charRows[1].cells) do
            cell:Hide()
        end
    end

    -- Loot editor sync overlay
    if ns.lootEditor and ns.lootEditor:IsShown() then
        if ns.isSyncingLoot then
            ns.lootEditor.syncOverlay:Show()
            ns.lootEditor._wasSyncing = true
        else
            ns.lootEditor.syncOverlay:Hide()
            if ns.lootEditor._wasSyncing and ns.lootEditor.charKey then
                ns.lootEditor._wasSyncing = nil
                ns.ShowLootEditor(ns.lootEditor, ns.lootEditor.charKey)
            end
        end
    end
end

------------------------------------------------------
-- ns.UpdateUI() — Main entry point
------------------------------------------------------

function ns.UpdateUI()
    if not ns.frame or not ns.frame:IsShown() then return end
    if ns.isInInstance then return end

    local uiOk, uiErr = pcall(function()
        local state = computeState()
        if not state then return end

        if ns._layoutDirty then
            ns._layoutDirty = false
            if not InCombatLockdown() then
                local layoutOk, layoutErr = pcall(ns.LayoutUI, state)
                if not layoutOk then
                    print("|cffff3333[MBT ERROR]|r LayoutUI: " .. tostring(layoutErr))
                end
            end
        end
        local refreshOk, refreshErr = pcall(ns.RefreshStatus, state)
        if not refreshOk then
            print("|cffff3333[MBT ERROR]|r RefreshStatus: " .. tostring(refreshErr))
        end
    end)
    if not uiOk then
        print("|cffff3333[MBT ERROR]|r UpdateUI: " .. tostring(uiErr))
    end
end

-- Alias for backward compat (old callers used _doUpdateUI)
ns._doUpdateUI = ns.UpdateUI

------------------------------------------------------
-- Right-click menu
------------------------------------------------------

-- Deferred setup: frame:SetScript for right-click is done after frame exists
-- This runs at load time; ns.frame is already created by UI.lua
local frame = ns.frame
if frame then
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ns.EnsureDB()
            local lockText = MajesticBeastTrackerDB.settings.locked and "Unlock Frame" or "Lock Frame"
            local timerRunning = ns.IsTimerRunning()
            local timerText = timerRunning and ("|cff00ff00Stop Timer|r (" .. ns.FormatTimerElapsed() .. ")") or "Start Timer"
            ns.ShowDropdown(self, {
                { text = "Majestic Beast Tracker", isTitle = true },
                { text = timerText, func = function()
                    if ns.IsTimerRunning() then
                        ns.StopTimer()
                    else
                        ns.StartTimer()
                    end
                end },
                { text = "Reset Timer", func = function()
                    ns.ResetTimer()
                end, disabled = timerRunning },
                { text = lockText, func = function()
                    MajesticBeastTrackerDB.settings.locked = not MajesticBeastTrackerDB.settings.locked
                    UpdateLockVisual()
                end },
                { text = "Reset Position", func = function()
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
                    MajesticBeastTrackerDB.settings.framePosition = nil
                end },
                { text = "Settings", func = function()
                    ns.OpenSettings()
                end },
                { text = "Close", func = function()
                    ns.HideFrame()
                end },
            })
        end
    end)
end
