------------------------------------------------------
-- MajesticBeastTracker Settings Panel
-- Separated from UI.lua for maintainability
------------------------------------------------------

local addonName, ns = ...
local LURES = ns.LURES
local CONSUMABLES = ns.CONSUMABLE_ITEMS

------------------------------------------------------
-- Static Popups
------------------------------------------------------

-- Remove character confirm popup
StaticPopupDialogs["MBT_REMOVE_CHAR"] = {
    text = "Remove %s from Majestic Beast Tracker?",
    button1 = YES,
    button2 = NO,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data)
        if data and MajesticBeastTrackerDB and MajesticBeastTrackerDB.chars then
            MajesticBeastTrackerDB.chars[data] = nil
            print("|cff3FC7EB[MBT]|r Removed " .. data)
            if ns.UpdateUI then ns.InvalidateLayout() end
        end
    end,
}

-- URL copy popup
StaticPopupDialogs["MBT_URL"] = {
    text = "Copy URL (Ctrl+C):",
    button1 = CLOSE,
    whileDead = true,
    hasEditBox = true,
    editBoxWidth = 240,
    OnShow = function(dialog, data)
        local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
        editBox:SetText(data)
        editBox:SetAutoFocus(true)
        editBox:HighlightText()
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        editBox:SetScript("OnTextChanged", function()
            editBox:SetText(data)
            editBox:HighlightText()
        end)
    end,
    OnHide = function(dialog)
        local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
        editBox:SetScript("OnEscapePressed", nil)
        editBox:SetScript("OnTextChanged", nil)
    end,
}

------------------------------------------------------
-- Settings Panel
------------------------------------------------------

local function InitSettings()
    ns.EnsureDB()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Majestic Beast Tracker")
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()

    local dbIcon = LibStub("LibDBIcon-1.0")

    -- Text mixin for custom text rows
    LureTracker_SettingsTextMixin = {}
    function LureTracker_SettingsTextMixin:Init(initializer)
        local data = initializer:GetData()
        self.LeftText:SetTextToFit(data.leftText or "")
        self.RightText:SetTextToFit(data.rightText or "")
    end

    -- Route order row mixin (arrow up/down buttons)
    LureTracker_SettingsRouteRowMixin = {}
    function LureTracker_SettingsRouteRowMixin:Init(initializer)
        local data = initializer:GetData()
        -- Store frame reference for direct label updates after swap
        ns.routeRowFrames = ns.routeRowFrames or {}
        ns.routeRowFrames[data.pos] = self
        self.Label:SetText(data.getLabel())
        self.UpButton:SetScript("OnClick", function()
            data.onMoveUp()
        end)
        self.DownButton:SetScript("OnClick", function()
            data.onMoveDown()
        end)
        -- Dim arrows at boundaries
        local canUp = data.pos > 1
        local canDown = data.pos < data.total
        self.UpButton:SetEnabled(canUp)
        self.DownButton:SetEnabled(canDown)
        self.UpButton.Arrow:SetAlpha(canUp and 1.0 or 0.2)
        self.DownButton.Arrow:SetAlpha(canDown and 1.0 or 0.2)
    end

    -- Expand mixin for collapsible sections
    LureTracker_SettingsExpandMixin = CreateFromMixins(SettingsExpandableSectionMixin)
    function LureTracker_SettingsExpandMixin:Init(initializer)
        SettingsExpandableSectionMixin.Init(self, initializer)
        self.data = initializer.data
    end
    function LureTracker_SettingsExpandMixin:OnExpandedChanged(expanded)
        self:EvaluateVisibility(expanded)
        SettingsInbound.RepairDisplay()
    end
    function LureTracker_SettingsExpandMixin:CalculateHeight()
        return 24
    end
    function LureTracker_SettingsExpandMixin:EvaluateVisibility(expanded)
        if expanded then
            self.Button.Right:SetAtlas("Options_ListExpand_Right_Expanded", TextureKitConstants.UseAtlasSize)
        else
            self.Button.Right:SetAtlas("Options_ListExpand_Right", TextureKitConstants.UseAtlasSize)
        end
    end

    -- Helper for expandable sections
    local function createExpandableSection(lay, sectionName)
        local initializer = CreateFromMixins(SettingsExpandableSectionInitializer)
        local expandData = { name = sectionName, expanded = false }
        initializer:Init("LureTracker_SettingsExpandTemplate", expandData)
        initializer.GetExtent = ScrollBoxFactoryInitializerMixin.GetExtent
        lay:AddInitializer(initializer)
        return initializer, function() return initializer.data.expanded end
    end

    -- Version
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local data = { leftText = "Version: |cffFFFFFF" .. version }
    local text = layout:AddInitializer(Settings.CreateElementInitializer("LureTracker_SettingsText", data))
    function text:GetExtent() return 14 end

    -- Support button
    layout:AddInitializer(CreateSettingsButtonInitializer("Support", "Buy Me a Coffee", function()
        StaticPopup_Show("MBT_URL", nil, nil, "https://buymeacoffee.com/vichob")
    end, "Developing this addon takes a significant amount of time and effort.\nPlease consider financially supporting the developer.", true))

    -- GitHub button
    layout:AddInitializer(CreateSettingsButtonInitializer("Feedback & Help", "GitHub", function()
        StaticPopup_Show("MBT_URL", nil, nil, "https://github.com/VichobAddons/MajesticBeastTracker")
    end, "Report bugs or give feedback on GitHub.", true))

    --------------------------------------------------------
    -- General (always visible)
    --------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))

    local s1 = Settings.RegisterAddOnSetting(category, "MBT_showMinimap", "showMinimap",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Minimap Icon", true)
    Settings.CreateCheckbox(category, s1, "Show or hide the minimap button.")
    s1:SetValueChangedCallback(function()
        MajesticBeastTrackerDB.settings.minimap.hide = not MajesticBeastTrackerDB.settings.showMinimap
        if MajesticBeastTrackerDB.settings.showMinimap then
            dbIcon:Show("MajesticBeastTracker")
        else
            dbIcon:Hide("MajesticBeastTracker")
        end
    end)

    local s2 = Settings.RegisterAddOnSetting(category, "MBT_chatNotify", "chatNotify",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Chat Notifications", true)
    Settings.CreateCheckbox(category, s2, "Show [MBT] messages in chat (waypoints, mark/clear, buff warnings).")

    local s2a = Settings.RegisterAddOnSetting(category, "MBT_hideNonSkinner", "hideNonSkinner",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Hide on Non-Skinners", true)
    Settings.CreateCheckbox(category, s2a, "Don't show the tracker automatically on characters without Skinning.")

    --------------------------------------------------------
    -- Expandable: Route
    --------------------------------------------------------
    local _, isRouteExpanded = createExpandableSection(layout, "Route")

    -- Ensure routeSkip table exists
    if type(MajesticBeastTrackerDB.settings.routeSkip) ~= "table" then
        MajesticBeastTrackerDB.settings.routeSkip = {}
    end

    -- "Skip from Route" sub-header
    local skipHeader = CreateSettingsListSectionHeaderInitializer("Skip from Route")
    skipHeader:AddShownPredicate(isRouteExpanded)
    layout:AddInitializer(skipHeader)

    -- Per-beast skip toggles
    for _, lure in ipairs(LURES) do
        local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
        if MajesticBeastTrackerDB.settings[skipKey] == nil then
            MajesticBeastTrackerDB.settings[skipKey] = MajesticBeastTrackerDB.settings.routeSkip[lure.name] or false
        end
        local sSkip = Settings.RegisterAddOnSetting(category, "MBT_" .. skipKey, skipKey,
            MajesticBeastTrackerDB.settings, Settings.VarType.Boolean,
            lure.color .. "Skip " .. lure.name .. "|r", false)
        local cbSkip = Settings.CreateCheckbox(category, sSkip, "Skip " .. lure.name .. " in your daily route. Shows 'Skip' in the tracker and excludes from reagent cost.")
        sSkip:SetValueChangedCallback(function()
            MajesticBeastTrackerDB.settings.routeSkip[lure.name] = MajesticBeastTrackerDB.settings[skipKey]
            ns.InvalidateLayout()
            if ns.refreshRouteLabels then ns.refreshRouteLabels() end
        end)
        cbSkip:AddShownPredicate(isRouteExpanded)
    end

    -- Harandar minimum level slider
    local sHarandarLvl = Settings.RegisterAddOnSetting(category, "MBT_routeHarandarMinLevel", "routeHarandarMinLevel",
        MajesticBeastTrackerDB.settings, Settings.VarType.Number, "Harandar Min Level", 80)
    local lvlOpts = Settings.CreateSliderOptions(80, 90, 1)
    lvlOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(val)
        return tostring(math.floor(val))
    end)
    local slHarandar = Settings.CreateSlider(category, sHarandarLvl, lvlOpts, "Skip Harandar for characters below this level. Harandar mobs are high level and time-consuming for lower level characters.")
    sHarandarLvl:SetValueChangedCallback(function()
        ns.InvalidateLayout()
    end)
    slHarandar:AddShownPredicate(isRouteExpanded)

    local sHideSkipped = Settings.RegisterAddOnSetting(category, "MBT_routeHideSkipped", "routeHideSkipped",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Hide Skipped Columns", false)
    local cbHideSkipped = Settings.CreateCheckbox(category, sHideSkipped, "Completely hide skipped beast columns from the tracker instead of showing 'Skip'.")
    sHideSkipped:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbHideSkipped:AddShownPredicate(isRouteExpanded)

    local sAutoWP = Settings.RegisterAddOnSetting(category, "MBT_autoRouteWaypoint", "autoRouteWaypoint",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Auto-Waypoint Next Beast", false)
    local cbAutoWP = Settings.CreateCheckbox(category, sAutoWP, "Automatically set a map waypoint to the next beast in your route after a kill. Clears waypoint when route is complete.")
    cbAutoWP:AddShownPredicate(isRouteExpanded)

    -- Route Order sub-header
    local routeOrderHeader = CreateSettingsListSectionHeaderInitializer("Route Order")
    routeOrderHeader:AddShownPredicate(isRouteExpanded)
    layout:AddInitializer(routeOrderHeader)

    -- Ensure routeOrder is initialized
    if not MajesticBeastTrackerDB.settings.routeOrder or #MajesticBeastTrackerDB.settings.routeOrder ~= #LURES then
        MajesticBeastTrackerDB.settings.routeOrder = {}
        for i = 1, #LURES do MajesticBeastTrackerDB.settings.routeOrder[i] = i end
    end

    local function getOrder() return MajesticBeastTrackerDB.settings.routeOrder end
    local function isLureSkipped(li)
        local lure = LURES[li]
        local skipKey = "routeSkip_" .. lure.name:gsub("[%s']", "")
        local routeSkipTbl = MajesticBeastTrackerDB.settings.routeSkip or {}
        return routeSkipTbl[lure.name] or MajesticBeastTrackerDB.settings[skipKey] or false
    end
    local function getRouteLabel(pos)
        local o = getOrder()
        local li = o[pos]
        if isLureSkipped(li) then
            return "|cff666666#" .. pos .. "  " .. LURES[li].name .. " (skip)|r"
        end
        return "#" .. pos .. "  " .. LURES[li].color .. LURES[li].name .. "|r"
    end

    local function refreshRouteLabels()
        if not ns.routeRowFrames then return end
        for pos = 1, #LURES do
            local f = ns.routeRowFrames[pos]
            if f and f.Label then
                f.Label:SetText(getRouteLabel(pos))
            end
        end
    end
    ns.refreshRouteLabels = refreshRouteLabels

    local function swapRoute(posA, posB)
        local o = getOrder()
        o[posA], o[posB] = o[posB], o[posA]
        MajesticBeastTrackerDB.settings.routeOrder = o
        ns.InvalidateLayout()
        refreshRouteLabels()
    end

    for pos = 1, #LURES do
        local routeInit = Settings.CreateElementInitializer("LureTracker_SettingsRouteRow", {
            pos = pos,
            total = #LURES,
            getLabel = function() return getRouteLabel(pos) end,
            onMoveUp = function() if pos > 1 then swapRoute(pos, pos - 1) end end,
            onMoveDown = function() if pos < #LURES then swapRoute(pos, pos + 1) end end,
        })
        routeInit:AddShownPredicate(isRouteExpanded)
        layout:AddInitializer(routeInit)
    end

    --------------------------------------------------------
    -- Expandable: Reagents & AH
    --------------------------------------------------------
    local _, isReagentsExpanded = createExpandableSection(layout, "Reagents & Auction House")

    local s2c = Settings.RegisterAddOnSetting(category, "MBT_showReagents", "showReagents",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Reagent Icons", true)
    local cb2c = Settings.CreateCheckbox(category, s2c, "Show reagent icons above each lure column header.")
    s2c:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cb2c:AddShownPredicate(isReagentsExpanded)

    local s2e = Settings.RegisterAddOnSetting(category, "MBT_reagentAllChars", "reagentAllChars",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Count for All Characters", true)
    local cb2e = Settings.CreateCheckbox(category, s2e, "ON: Count reagents needed for all characters. OFF: Count for a single lure only.")
    s2e:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cb2e:AddShownPredicate(isReagentsExpanded)

    local sMissing = Settings.RegisterAddOnSetting(category, "MBT_showMissingCount", "showMissingCount",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Missing Count", false)
    local cbMissing = Settings.CreateCheckbox(category, sMissing, "ON: Show how many reagents you're missing (e.g. -56). OFF: Show have/need (e.g. 16/72).")
    sMissing:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbMissing:AddShownPredicate(isReagentsExpanded)

    local sAlwaysCounts = Settings.RegisterAddOnSetting(category, "MBT_alwaysShowReagentCounts", "alwaysShowReagentCounts",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Always Show Counts", false)
    local cbAlwaysCounts = Settings.CreateCheckbox(category, sAlwaysCounts, "Keep reagent numbers and colors visible even when a lure is Ready or Done — useful when stocking up reagents for the week ahead.")
    sAlwaysCounts:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbAlwaysCounts:AddShownPredicate(isReagentsExpanded)

    local sAHFill = Settings.RegisterAddOnSetting(category, "MBT_ahAutofillQuantity", "ahAutofillQuantity",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Autofill AH Quantity", true)
    local cbAHFill = Settings.CreateCheckbox(category, sAHFill, "Automatically fill the Auction House buy quantity with the number of missing reagents when browsing commodities.")
    cbAHFill:AddShownPredicate(isReagentsExpanded)

    --------------------------------------------------------
    -- Expandable: Consumables
    --------------------------------------------------------
    local _, isConsExpanded = createExpandableSection(layout, "Consumables")

    -- Per-consumable show/hide toggles + stock sliders
    if type(MajesticBeastTrackerDB.settings.consumableStock) ~= "table" then
        MajesticBeastTrackerDB.settings.consumableStock = {}
    end

    -- Default visibility: Tea and Crab off, others on
    local CONS_DEFAULTS = {
        [242299] = false,  -- Sanguithorn Tea
        [238367] = false,  -- Root Crab
        [241317] = true,   -- Haranir Phial of Perception
    }

    for _, cons in ipairs(CONSUMABLES) do
        -- Show/hide toggle
        local showKey = "consShow_" .. (cons.itemID or cons.spellID)
        if MajesticBeastTrackerDB.settings[showKey] == nil then
            MajesticBeastTrackerDB.settings[showKey] = CONS_DEFAULTS[cons.itemID] ~= nil and CONS_DEFAULTS[cons.itemID] or true
        end
        local sShow = Settings.RegisterAddOnSetting(category, "MBT_" .. showKey, showKey,
            MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show " .. cons.name,
            CONS_DEFAULTS[cons.itemID] ~= nil and CONS_DEFAULTS[cons.itemID] or true)
        local cbShow = Settings.CreateCheckbox(category, sShow, "Show " .. cons.name .. " in the consumable tracking bar.")
        sShow:SetValueChangedCallback(function()
            ns.InvalidateLayout()
            SettingsInbound.RepairDisplay()
        end)
        cbShow:AddShownPredicate(isConsExpanded)

        -- Stock slider (skip for spells — no item to stock)
        if not cons.isSpell then
        local flatKey = "consStock_" .. (cons.itemID or cons.spellID)
        if MajesticBeastTrackerDB.settings[flatKey] == nil then
            MajesticBeastTrackerDB.settings[flatKey] = MajesticBeastTrackerDB.settings.consumableStock[cons.itemID] or 0
        end
        local ok, err = pcall(function()
            local sStock = Settings.RegisterAddOnSetting(category,
                "MBT_" .. flatKey, flatKey,
                MajesticBeastTrackerDB.settings, Settings.VarType.Number,
                "Stock: " .. cons.name, 0)
            local stockOpts = Settings.CreateSliderOptions(0, cons.stockMax or 200, cons.stockStep or 5)
            stockOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(val)
                return tostring(math.floor(val))
            end)
            local slStock = Settings.CreateSlider(category, sStock, stockOpts,
                "Number of " .. cons.name .. " to keep in stock. Used for Auctionator shopping list. 0 = exclude.")
            sStock:SetValueChangedCallback(function(setting, val)
                MajesticBeastTrackerDB.settings.consumableStock[cons.itemID] = val
            end)
            slStock:AddShownPredicate(isConsExpanded)
            slStock:AddShownPredicate(function() return MajesticBeastTrackerDB.settings[showKey] ~= false end)
        end)
        if not ok then
            print("|cff3FC7EB[MBT]|r Settings error for " .. cons.name .. ": " .. tostring(err))
        end
        end -- if not cons.isSpell
    end

    --------------------------------------------------------
    -- Expandable: Loot Tracking
    --------------------------------------------------------
    local _, isLootExpanded = createExpandableSection(layout, "Loot Tracking")

    local sLoot = Settings.RegisterAddOnSetting(category, "MBT_lootTracking", "lootTracking",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Enable Loot Tracking", true)
    local cbLoot = Settings.CreateCheckbox(category, sLoot, "Track skinning loot from Majestic Beasts. Shows goblin icons on character rows.")
    sLoot:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbLoot:AddShownPredicate(isLootExpanded)

    local sLootTSM = Settings.RegisterAddOnSetting(category, "MBT_tsmIntegration", "tsmIntegration",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Integrate TSM", false)
    local cbLootTSM = Settings.CreateCheckbox(category, sLootTSM, "Show estimated reagent cost and loot value using TradeSkillMaster price data. Requires TSM addon.")
    sLootTSM:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbLootTSM:AddShownPredicate(isLootExpanded)

    local sDropPct = Settings.RegisterAddOnSetting(category, "MBT_showDropPercent", "showDropPercent",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Drop %", false)
    local cbDropPct = Settings.CreateCheckbox(category, sDropPct, "Show personal drop percentage column in Loot Summary. Tracking starts from when this feature is first enabled — older loot data is not included.")
    sDropPct:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbDropPct:AddShownPredicate(isLootExpanded)

    local sDropFormat = Settings.RegisterAddOnSetting(category, "MBT_dropPercentFormat", "dropPercentFormat",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Drop Rate: Per Kill format", false)
    local cbDropFormat = Settings.CreateCheckbox(category, sDropFormat, "OFF = percentage (max 100%). ON = average per kill (e.g. 2.3/kill).")
    sDropFormat:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbDropFormat:AddShownPredicate(isLootExpanded)
    cbDropFormat:AddShownPredicate(function() return MajesticBeastTrackerDB.settings.showDropPercent end)

    --------------------------------------------------------
    -- Expandable: Warband Bank
    --------------------------------------------------------
    local _, isWarbankExpanded = createExpandableSection(layout, "Warband Bank")

    local sWarbank = Settings.RegisterAddOnSetting(category, "MBT_warbankDeposit", "warbankDeposit",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Enable Warband Bank Deposit", false)
    local cbWarbank = Settings.CreateCheckbox(category, sWarbank, "Show a deposit button on the tracker when the Warband Bank is open. Click to deposit all tracked skinning reagents.")
    cbWarbank:AddShownPredicate(isWarbankExpanded)

    local sWarbankAuto = Settings.RegisterAddOnSetting(category, "MBT_warbankAutoDeposit", "warbankAutoDeposit",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Automatically Deposit on Bank Open", false)
    local cbWarbankAuto = Settings.CreateCheckbox(category, sWarbankAuto, "Automatically deposit tracked reagents when you open the Warband Bank.")
    cbWarbankAuto:AddShownPredicate(isWarbankExpanded)

    local sWarbankRewards = Settings.RegisterAddOnSetting(category, "MBT_warbankDepositRewards", "warbankDepositRewards",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Deposit Beast Rewards", true)
    local cbWarbankRewards = Settings.CreateCheckbox(category, sWarbankRewards, "Include skinning loot from beast kills (hides, leather, plating, scales, etc.)")
    cbWarbankRewards:AddShownPredicate(isWarbankExpanded)

    local sWarbankReagents = Settings.RegisterAddOnSetting(category, "MBT_warbankDepositReagents", "warbankDepositReagents",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Deposit Lure Reagents", true)
    local cbWarbankReagents = Settings.CreateCheckbox(category, sWarbankReagents, "Include fish used to craft lures (Arcane Wyrmfish, Gore Guppy, Ominous Octopus, etc.)")
    cbWarbankReagents:AddShownPredicate(isWarbankExpanded)

    local warbankNoteData = { leftText = "|cffFF8800Note:|r |cffAAAAAADepositing may occasionally cause bag interaction issues due to Blizzard API restrictions. Use /reload to fix.|r" }
    local warbankNote = layout:AddInitializer(Settings.CreateElementInitializer("LureTracker_SettingsText", warbankNoteData))
    function warbankNote:GetExtent() return 26 end
    warbankNote:AddShownPredicate(isWarbankExpanded)

    --------------------------------------------------------
    -- Expandable: Display
    --------------------------------------------------------
    local _, isDisplayExpanded = createExpandableSection(layout, "Display")

    -- Weekly Knowledge removed from main window (visible in character detail popup)

    local s2b = Settings.RegisterAddOnSetting(category, "MBT_hideInCombat", "hideInCombat",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Hide in Combat", false)
    local cb2b = Settings.CreateCheckbox(category, s2b, "Automatically hide the tracker window during combat.")
    cb2b:AddShownPredicate(isDisplayExpanded)

    local sAutoHide = Settings.RegisterAddOnSetting(category, "MBT_autoHide", "autoHide",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Auto Hide", false)
    local cbAutoHide = Settings.CreateCheckbox(category, sAutoHide, "Fade out the tracker when the mouse is not hovering over it. Hover to show.")
    sAutoHide:SetValueChangedCallback(function() ns.RefreshAutoHide() end)
    cbAutoHide:AddShownPredicate(isDisplayExpanded)

    local s3 = Settings.RegisterAddOnSetting(category, "MBT_locked", "locked",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Lock Frame Position", false)
    local cb3 = Settings.CreateCheckbox(category, s3, "Prevent the tracker window from being dragged.")
    s3:SetValueChangedCallback(function() ns.UpdateLockVisual() end)
    cb3:AddShownPredicate(isDisplayExpanded)

    local s4 = Settings.RegisterAddOnSetting(category, "MBT_windowScale", "windowScale",
        MajesticBeastTrackerDB.settings, Settings.VarType.Number, "Window Scale", 1.0)
    local scaleOpts = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
    scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(val)
        return string.format("%d%%", val * 100)
    end)
    local sl4 = Settings.CreateSlider(category, s4, scaleOpts, "Scale the tracker window (50% - 200%).")
    s4:SetValueChangedCallback(function()
        ns.frame:SetScale(MajesticBeastTrackerDB.settings.windowScale)
    end)
    sl4:AddShownPredicate(isDisplayExpanded)

    local sBorderLure = Settings.RegisterAddOnSetting(category, "MBT_showLureBorders", "showLureBorders",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Borders — Lure + Reagents", true)
    local cbBorderLure = Settings.CreateCheckbox(category, sBorderLure, "Show gold borders around lure and reagent icon columns.")
    sBorderLure:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbBorderLure:AddShownPredicate(isDisplayExpanded)

    local sBorderCons = Settings.RegisterAddOnSetting(category, "MBT_showConsBorders", "showConsBorders",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Borders — Travel + Consumables", true)
    local cbBorderCons = Settings.CreateCheckbox(category, sBorderCons, "Show gold borders around the travel and consumable boxes.")
    sBorderCons:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbBorderCons:AddShownPredicate(isDisplayExpanded)

    -- Max visible character rows (scroll after this)
    if MajesticBeastTrackerDB.settings.maxVisibleRows == nil then
        MajesticBeastTrackerDB.settings.maxVisibleRows = 10
    end
    local sMaxRows = Settings.RegisterAddOnSetting(category, "MBT_maxVisibleRows", "maxVisibleRows",
        MajesticBeastTrackerDB.settings, Settings.VarType.Number, "Max Visible Rows", 10)
    local maxRowsOpts = Settings.CreateSliderOptions(5, 30, 1)
    maxRowsOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(val)
        return tostring(math.floor(val))
    end)
    local slMaxRows = Settings.CreateSlider(category, sMaxRows, maxRowsOpts,
        "Maximum number of character rows visible before scrolling. Lower = smaller window.")
    sMaxRows:SetValueChangedCallback(function(_, val)
        ns.MAX_VISIBLE_ROWS = math.floor(val)
        ns.InvalidateLayout()
    end)
    slMaxRows:AddShownPredicate(isDisplayExpanded)

    --------------------------------------------------------
    -- Expandable: Data Management
    --------------------------------------------------------
    local _, isDataExpanded = createExpandableSection(layout, "Data Management")

    local sShowHidden = Settings.RegisterAddOnSetting(category, "MBT_showHiddenChars", "showHiddenChars",
        MajesticBeastTrackerDB.settings, Settings.VarType.Boolean, "Show Hidden Characters", false)
    local cbShowHidden = Settings.CreateCheckbox(category, sShowHidden, "Temporarily show characters that have been hidden via right-click menu.")
    sShowHidden:SetValueChangedCallback(function() ns.InvalidateLayout() end)
    cbShowHidden:AddShownPredicate(isDataExpanded)

    local clearCharInit = CreateSettingsButtonInitializer("Clear Current Character", "Clear", function()
        StaticPopupDialogs["MBT_CLEAR_CHAR"] = {
            text = "Clear lure data for |cffD1B559" .. (ns.GetCharKey() or "?") .. "|r?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                ns.EnsureDB()
                local key = ns.GetCharKey()
                if key and MajesticBeastTrackerDB.chars[key] then
                    MajesticBeastTrackerDB.chars[key].lures = {}
                    ns.InvalidateLayout()
                    print("|cff3FC7EB[MBT]|r " .. key .. " data cleared.")
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("MBT_CLEAR_CHAR")
    end, "Clear all lure cooldown data for your current character.", true)
    clearCharInit:AddShownPredicate(isDataExpanded)
    layout:AddInitializer(clearCharInit)

    local clearAllInit = CreateSettingsButtonInitializer("|cffff6666Clear ALL Characters|r", "Clear All", function()
        StaticPopupDialogs["MBT_CLEAR_ALL"] = {
            text = "|cffff6666WARNING:|r This will delete ALL tracking data for ALL characters.\n\nAre you sure?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                ns.EnsureDB()
                MajesticBeastTrackerDB = { chars = {}, settings = MajesticBeastTrackerDB.settings }
                ns.EnsureDB()
                ns.InvalidateLayout()
                print("|cff3FC7EB[MBT]|r ALL data cleared.")
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
        }
        StaticPopup_Show("MBT_CLEAR_ALL")
    end, "|cffff6666Permanently delete all tracking data for every character.|r", true)
    clearAllInit:AddShownPredicate(isDataExpanded)
    layout:AddInitializer(clearAllInit)

    --------------------------------------------------------
    -- Expandable: Slash Commands
    --------------------------------------------------------
    local _, isSlashExpanded = createExpandableSection(layout, "Slash Commands")

    local cmdData = {
        leftText = "|cffFFFFFF"
            .. "/mbt\n\n"
            .. "/mbt hide\n\n"
            .. "/mbt lock\n\n"
            .. "/mbt settings\n\n"
            .. "/mbt talent |cffD1B559N|r|cffFFFFFF\n\n"
            .. "/mbt remove |cffD1B559Name-Realm|r|cffFFFFFF\n\n"
            .. "/mbt nuke\n\n"
            .. "/mbt nuke all\n\n"
            .. "/mbt debug |cffD1B559calc|stats|gear|r",
        rightText =
            "Show tracker\n\n"
            .. "Hide tracker\n\n"
            .. "Toggle frame lock\n\n"
            .. "Open settings\n\n"
            .. "Override talent points (0-40)\n\n"
            .. "Remove a character\n\n"
            .. "Clear current character\n\n"
            .. "Clear ALL data\n\n"
            .. "Debug tools (stats breakdown)",
    }
    local cmdText = layout:AddInitializer(Settings.CreateElementInitializer("LureTracker_SettingsText", cmdData))
    function cmdText:GetExtent()
        return 28 + select(2, string.gsub(cmdData.leftText, "\n", "")) * 12
    end
    cmdText:AddShownPredicate(isSlashExpanded)
end

ns.InitSettings = InitSettings

function ns.OpenSettings()
    if ns.settingsCategoryID then
        Settings.OpenToCategory(ns.settingsCategoryID)
    end
end
