------------------------------------------------------
-- MajesticBeastTracker UI - Visual tracker
-- PSL-inspired style with BackdropTemplate
------------------------------------------------------

local addonName, ns = ...
local LURES = ns.LURES
local WEEKLIES = ns.SKINNING_WEEKLIES

-- Constants
ns.CHECKMARK_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

-- Layout
local ICON_SIZE = 26
local COL_WIDTH = 62
local NAME_COL_WIDTH = 150
local BASE_NAME_COL_WIDTH = 150
local ROW_HEIGHT = 18
local TOOLBAR_HEIGHT = 22
local BOTTOM_BAR_HEIGHT = 24  -- base height, grows to 40 when stats+TSM shown
local TITLE_HEIGHT = 4  -- reduced after title moved to toolbar
local ZONE_LABEL_HEIGHT = 10
local ICON_ROW_HEIGHT = ICON_SIZE + 6 + ZONE_LABEL_HEIGHT
local REAGENT_ICON_SIZE = 20
local REAGENT_COUNT_HEIGHT = 10
local REAGENT_GAP = 8
local REAGENT_ROW_HEIGHT = REAGENT_ICON_SIZE + REAGENT_COUNT_HEIGHT + 4
local PAD = 8

-- Consumables to track (test with Holiday Cheesewheel)
local CONSUMABLES = {
    { itemID = 242299, name = "Sanguithorn Tea", buffSpellID = 1269152, minLevel = 80, stockMax = 5, stockStep = 1 },
    { itemID = 241317, name = "Haranir Phial of Perception", buffSpellID = 1236763, altItemID = 241316, minLevel = 81, stockMax = 10, stockStep = 1 },
    { itemID = 238367, name = "Root Crab", buffSpellID = 1235216, minLevel = 80, stackable = true, stockMax = 200, stockStep = 5 },
    { itemID = 237372, name = "Refulgent Razorstone", minLevel = 80, isToolEnchant = true, stockMax = 5, stockStep = 1 },
    { spellID = 1223388, name = "Sharpen Your Knife", isSpell = true, minLevel = 80 },
    { spellID = 1226037, name = "Carve Meat", isSpell = true, minLevel = 80 },
}
local NUM_EXTRA_COLS = #CONSUMABLES
ns.CONSUMABLE_ITEMS = CONSUMABLES

-- Travel items, buttons, and constants in UI/TravelBar.lua

-- Colors
local C_ACCENT = CreateColor(0.82, 0.71, 0.35)
local C_BORDER_RGB = { 0.82, 0.71, 0.35 }
local C_ROW_ALT = { 0.1, 0.1, 0.14, 0.4 }
local C_SEPARATOR = { 0.82, 0.71, 0.35, 0.3 }

local MEDIA_PATH = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

local BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Expose shared constants for other files
ns.MEDIA_PATH = MEDIA_PATH
ns.BACKDROP = BACKDROP
ns.C_BORDER_RGB = C_BORDER_RGB
ns.C_ACCENT = C_ACCENT
ns.ROW_HEIGHT = ROW_HEIGHT
ns.PAD = PAD
ns.NAME_COL_WIDTH = NAME_COL_WIDTH
ns.COL_WIDTH = COL_WIDTH
ns.ICON_SIZE = ICON_SIZE
ns.REAGENT_ICON_SIZE = REAGENT_ICON_SIZE
ns.REAGENT_COUNT_HEIGHT = REAGENT_COUNT_HEIGHT
ns.REAGENT_GAP = REAGENT_GAP
ns.REAGENT_ROW_HEIGHT = REAGENT_ROW_HEIGHT
ns.ICON_ROW_HEIGHT = ICON_ROW_HEIGHT
ns.TOOLBAR_HEIGHT = TOOLBAR_HEIGHT
ns.TITLE_HEIGHT = TITLE_HEIGHT
ns.BOTTOM_BAR_HEIGHT = BOTTOM_BAR_HEIGHT
ns.BASE_NAME_COL_WIDTH = BASE_NAME_COL_WIDTH
ns.contentTop = -(TOOLBAR_HEIGHT + TITLE_HEIGHT + 2)

------------------------------------------------------
-- Helpers
------------------------------------------------------

-- Calculate how many times a recipe can be crafted with current reagents
function ns.GetCraftableCount(recipeID)
    if not recipeID then return 0 end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok then return 0 end
    if not schematic or not schematic.reagentSlotSchematics then return 0 end

    local minCrafts = math.huge
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic and slot.required then
            local needed = slot.quantityRequired
            if not needed or needed <= 0 then
                if slot.GetQuantityRequired then
                    needed = slot:GetQuantityRequired()
                end
                if not needed or needed <= 0 then needed = 1 end
            end
            local have = 0
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then
                    -- Try item name first (counts all quality variants), fallback to ID
                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                    local count = 0
                    if itemName then
                        count = C_Item.GetItemCount(itemName, true, false, true, true)
                    else
                        count = C_Item.GetItemCount(reagent.itemID, true, false, true, true)
                    end
                    have = have + count
                end
            end
            minCrafts = math.min(minCrafts, math.floor(have / needed))
        end
    end
    return minCrafts == math.huge and 0 or minCrafts
end

------------------------------------------------------
-- Main Frame
------------------------------------------------------

local frame = CreateFrame("Frame", "MajesticBeastTrackerFrame", UIParent, "BackdropTemplate")
ns.frame = frame
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
frame:SetFrameStrata("MEDIUM")
frame:SetFrameLevel(200)
frame:SetBackdrop(BACKDROP)
frame:SetBackdropColor(0, 0, 0, 0.95)
frame:SetBackdropBorderColor(unpack(C_BORDER_RGB))
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

-- Drag
frame:SetScript("OnDragStart", function(self)
    ns.EnsureDB()
    if not MajesticBeastTrackerDB.settings.locked then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    MajesticBeastTrackerDB.settings.framePosition = { point, "UIParent", relPoint, x, y }
    -- Reposition loot summary if open
    if ns.lootSummary and ns.lootSummary:IsShown() and ns.RepositionLootSummary then
        ns.RepositionLootSummary()
    end
end)

-- Autohide: fade in/out on hover
local function IsMouseOverAnyMBT()
    if frame:IsMouseOver() then return true end
    if ns.lootSummary and ns.lootSummary:IsShown() and ns.lootSummary:IsMouseOver() then return true end
    if ns.lootEditor and ns.lootEditor:IsShown() and ns.lootEditor:IsMouseOver() then return true end
    return false
end

function ns.RefreshAutoHide()
    if not frame:IsShown() then return end
    ns.EnsureDB()
    if MajesticBeastTrackerDB.settings.autoHide and not IsMouseOverAnyMBT() then
        UIFrameFadeOut(frame, 0.5, frame:GetAlpha(), 0)
        if ns.lootSummary and ns.lootSummary:IsShown() then
            UIFrameFadeOut(ns.lootSummary, 0.5, ns.lootSummary:GetAlpha(), 0)
        end
        if ns.lootEditor and ns.lootEditor:IsShown() then
            UIFrameFadeOut(ns.lootEditor, 0.5, ns.lootEditor:GetAlpha(), 0)
        end
    else
        UIFrameFadeIn(frame, 0.1, frame:GetAlpha(), 1)
        if ns.lootSummary and ns.lootSummary:IsShown() then
            UIFrameFadeIn(ns.lootSummary, 0.1, ns.lootSummary:GetAlpha(), 1)
        end
        if ns.lootEditor and ns.lootEditor:IsShown() then
            UIFrameFadeIn(ns.lootEditor, 0.1, ns.lootEditor:GetAlpha(), 1)
        end
    end
end

local function OnFrameEnter()
    ns.EnsureDB()
    if MajesticBeastTrackerDB.settings.autoHide then
        UIFrameFadeIn(frame, 0.1, frame:GetAlpha(), 1)
    end
end
local function OnFrameLeave()
    ns.EnsureDB()
    if MajesticBeastTrackerDB.settings.autoHide and not IsMouseOverAnyMBT() then
        UIFrameFadeOut(frame, 0.5, frame:GetAlpha(), 0)
    end
end
frame:SetScript("OnEnter", OnFrameEnter)
frame:SetScript("OnLeave", OnFrameLeave)
frame:SetScript("OnHide", function()
    if ns.lootSummary then ns.lootSummary:Hide() end
    if ns.lootEditor then ns.lootEditor:Hide() end
    if ns.gearPopup then ns.gearPopup:Hide() end
    if MBT_SettingsDropdown then MBT_SettingsDropdown:Hide() end
    if MBT_SettingsSubmenu then MBT_SettingsSubmenu:Hide() end
end)

------------------------------------------------------
-- Bottom Bar (timer + logout)
------------------------------------------------------
local bottomBar = CreateFrame("Frame", nil, frame)
bottomBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
bottomBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
bottomBar:SetHeight(BOTTOM_BAR_HEIGHT)
bottomBar:SetFrameLevel(frame:GetFrameLevel() + 25)

local bottomBarBg = bottomBar:CreateTexture(nil, "BACKGROUND")
bottomBarBg:SetAllPoints()
bottomBarBg:SetColorTexture(0, 0, 0, 0.4)

local bottomBarSep = bottomBar:CreateTexture(nil, "ARTWORK")
bottomBarSep:SetHeight(1)
bottomBarSep:SetPoint("TOPLEFT", bottomBar, "TOPLEFT", 0, 0)
bottomBarSep:SetPoint("TOPRIGHT", bottomBar, "TOPRIGHT", 0, 0)
bottomBarSep:SetColorTexture(0.82, 0.71, 0.35, 0.3)

-- Logout button (right side of bottom bar)
local logoutBtn = CreateFrame("Button", nil, bottomBar, "SecureActionButtonTemplate")
logoutBtn:SetSize(BOTTOM_BAR_HEIGHT, BOTTOM_BAR_HEIGHT)
logoutBtn:SetAttribute("type", "macro")
logoutBtn:SetAttribute("macrotext", "/logout")
logoutBtn:RegisterForClicks("AnyUp", "AnyDown")
local logoutText = logoutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
logoutText:SetFont(logoutText:GetFont(), 9)
logoutText:SetText("|cff999999Logout|r")
logoutText:SetPoint("CENTER")
logoutBtn:SetWidth(logoutText:GetStringWidth() + 8)
logoutBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -2, 0)
logoutBtn:SetHighlightTexture("Interface/Buttons/UI-Panel-MinimizeButton-Highlight")
logoutBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
    GameTooltip:AddLine("Logout", 1, 1, 1)
    GameTooltip:AddLine("Switch character quickly", 0.5, 0.8, 1)
    GameTooltip:Show()
end)
logoutBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Timer display (left side of bottom bar)
local timerLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timerLabel:SetFont(timerLabel:GetFont(), 9)
timerLabel:SetPoint("LEFT", bottomBar, "LEFT", 6, 0)
timerLabel:SetTextColor(0.5, 0.5, 0.5)
timerLabel:Hide()

local timerBtn = CreateFrame("Button", nil, bottomBar)
timerBtn:SetHeight(BOTTOM_BAR_HEIGHT)
timerBtn:SetPoint("LEFT", bottomBar, "LEFT", 2, 0)
timerBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
timerBtn:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
        ns.ResetTimer()
    elseif ns.IsTimerRunning() then
        ns.StopTimer()
    else
        ns.StartTimer()
    end
end)
timerBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
    GameTooltip:AddLine("Route Timer", 1, 0.82, 0)
    if ns.IsTimerRunning() then
        GameTooltip:AddLine("Click to stop", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("Click to start", 0.7, 0.7, 0.7)
    end
    if ns.GetTimerElapsed() > 0 then
        GameTooltip:AddLine("Right-click to reset", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end)
timerBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
ns.timerLabel = timerLabel
ns.timerBtn = timerBtn

------------------------------------------------------
-- Toolbar
------------------------------------------------------
local toolbar = CreateFrame("Frame", nil, frame)
toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
toolbar:SetHeight(TOOLBAR_HEIGHT)
toolbar:SetFrameLevel(frame:GetFrameLevel() + 25)

-- Toolbar background
local toolbarBg = toolbar:CreateTexture(nil, "BACKGROUND")
toolbarBg:SetAllPoints()
toolbarBg:SetColorTexture(0, 0, 0, 0.4)

-- Toolbar separator line
local toolbarSep = toolbar:CreateTexture(nil, "ARTWORK")
toolbarSep:SetHeight(1)
toolbarSep:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 0, 0)
toolbarSep:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", 0, 0)
toolbarSep:SetColorTexture(0.82, 0.71, 0.35, 0.3)

-- Toolbar title (left side)
local toolbarTitle = toolbar:CreateFontString(nil, "OVERLAY")
toolbarTitle:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
toolbarTitle:SetPoint("LEFT", toolbar, "LEFT", TOOLBAR_HEIGHT + 4, 0)
toolbarTitle:SetTextColor(0.6, 0.6, 0.6)
toolbarTitle:SetText("|cffD1B559MBT|r")  -- version set after GetMBTVersion is defined below

-- Helper: create a toolbar icon button
local TOOLBAR_ICON_SIZE = 16
local TOOLBAR_BTN_PADDING = 3
local C_TOOLBAR_ICON = { 0.82, 0.71, 0.35 }  -- gold/amber default
local C_TOOLBAR_ICON_HOVER = { 1.0, 0.88, 0.44 }  -- brighter gold on hover
ns.C_TOOLBAR_ICON = C_TOOLBAR_ICON
ns.C_TOOLBAR_ICON_HOVER = C_TOOLBAR_ICON_HOVER
local function CreateToolbarButton(parent, texture, tooltipTitle, tooltipDesc, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(TOOLBAR_HEIGHT, TOOLBAR_HEIGHT)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TOOLBAR_ICON_SIZE, TOOLBAR_ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexture(texture)
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
    btn.icon = icon
    btn:SetScript("OnEnter", function(self)
        icon:SetVertexColor(C_TOOLBAR_ICON_HOVER[1], C_TOOLBAR_ICON_HOVER[2], C_TOOLBAR_ICON_HOVER[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        if type(tooltipTitle) == "function" then
            tooltipTitle(self)
        else
            GameTooltip:AddLine(tooltipTitle, 1, 1, 1)
            if tooltipDesc then
                GameTooltip:AddLine(tooltipDesc, 0.5, 0.8, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
        GameTooltip:Hide()
        if ns.HideLootTooltip then ns.HideLootTooltip() end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end
ns.CreateToolbarButton = CreateToolbarButton

-- Close button
local closeBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Close",
    "Close", nil,
    function() ns.HideFrame() end)
closeBtn:SetPoint("RIGHT", toolbar, "RIGHT", -2, 0)
closeBtn.icon:SetTexCoord(0, 1, 0, 1)
closeBtn:SetScript("OnEnter", function(self)
    closeBtn.icon:SetVertexColor(1, 0.3, 0.3, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
    GameTooltip:AddLine("Close", 1, 1, 1)
    GameTooltip:Show()
end)
closeBtn:SetScript("OnLeave", function()
    closeBtn.icon:SetVertexColor(C_TOOLBAR_ICON[1], C_TOOLBAR_ICON[2], C_TOOLBAR_ICON[3], 1)
    GameTooltip:Hide()
end)

-- Settings dropdown button (gear icon, right of close)
local settingsBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Settings",
    "Settings", nil, nil)
settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
settingsBtn.icon:SetTexCoord(0, 1, 0, 1)
ns._settingsBtn = settingsBtn
-- Settings dropdown logic in UI/SettingsDropdown.lua

-- Autohide toggle button (eye icon) — left side of toolbar, before title
local autoHideBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Show",
    function(self)
        ns.EnsureDB()
        local state = MajesticBeastTrackerDB.settings.autoHide
        GameTooltip:AddLine(state and "Auto Hide: ON" or "Auto Hide: OFF", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle. Fades tracker when mouse leaves.", 0.5, 0.8, 1, true)
    end,
    nil, nil)
autoHideBtn:SetScript("OnClick", function(self)
    ns.EnsureDB()
    MajesticBeastTrackerDB.settings.autoHide = not MajesticBeastTrackerDB.settings.autoHide
    ns.RefreshAutoHide()
    local state = MajesticBeastTrackerDB.settings.autoHide
    self.icon:SetTexture(MEDIA_PATH .. (state and "Icon_Show" or "Icon_Hide"))
    self.icon:SetAlpha(state and 1.0 or 0.4)
end)
autoHideBtn:SetPoint("LEFT", toolbar, "LEFT", 2, 0)
autoHideBtn.icon:SetTexCoord(0, 1, 0, 1)
local autoHideIcon = autoHideBtn.icon
ns.autoHideIcon = autoHideIcon

-- Title removed — version shown in toolbar ("MBT vX")
local function GetMBTVersion()
    local devLoaded = C_AddOns.IsAddOnLoaded("MajesticBeastTrackerDev")
    if devLoaded then
        return (C_AddOns.GetAddOnMetadata("MajesticBeastTrackerDev", "Version") or "?") .. " Dev"
    end
    return C_AddOns.GetAddOnMetadata("MajesticBeastTracker", "Version") or "?"
end
toolbarTitle:SetText("|cffD1B559Majestic Beast Tracker|r v" .. GetMBTVersion())

-- Lock indicator (shown in toolbar)
local lockIcon = toolbar:CreateTexture(nil, "OVERLAY")
lockIcon:SetSize(10, 10)
lockIcon:SetPoint("LEFT", toolbarTitle, "RIGHT", 4, 0)
lockIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
lockIcon:SetVertexColor(0.6, 0.6, 0.6)
lockIcon:Hide()
ns.lockIcon = lockIcon

-- Toggle fish button (show/hide reagent icons)
local fishBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Reagents",
    function(self)
        local shown = MajesticBeastTrackerDB.settings.showReagents ~= false
        GameTooltip:AddLine(shown and "Hide Reagents" or "Show Reagents", 1, 1, 1)
    end,
    nil,
    function()
        local settings = MajesticBeastTrackerDB.settings
        if settings.showReagents == nil then settings.showReagents = true end
        settings.showReagents = not settings.showReagents
        ns.InvalidateLayout()
    end)
fishBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -2, 0)
local fishIcon = fishBtn.icon
ns.fishBtn = fishBtn
ns.fishIcon = fishIcon

-- Global loot summary button (goblin icon)
local globalGoblinBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Results",
    function(self)
        ns.EnsureDB()
        local resetLoot, allTimeLoot, globalPrices = ns.GetGlobalLoot()
        if resetLoot or allTimeLoot then
            ns.ShowLootTooltip(self, "Loot Summary (All Characters)", resetLoot, allTimeLoot, globalPrices)
            return  -- ShowLootTooltip handles display, skip GameTooltip:Show
        else
            GameTooltip:AddLine("Loot Summary", 0.82, 0.71, 0.35)
            GameTooltip:AddLine("No loot data yet", 0.5, 0.5, 0.5)
        end
    end,
    nil,
    function() ns.ToggleLootSummary() end)
ns.globalGoblinIcon = globalGoblinBtn.icon
ns.globalGoblinBtn = globalGoblinBtn

-- Warband Bank deposit button (bank icon, only visible when bank is open)
local warbankBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Bank",
    function(self)
        GameTooltip:AddLine("Deposit Reagents to Warband Bank", 0.82, 0.71, 0.35)
        GameTooltip:AddLine("Click to deposit all tracked skinning reagents.", 0.8, 0.8, 0.8, true)
    end,
    nil,
    function() ns.DepositTrackedToWarbank() end)
warbankBtn:Hide()
ns.warbankBtn = warbankBtn

-- Auctionator shopping list button
local auctionatorBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_ShoppingList",
    function(self)
        GameTooltip:AddLine("Create Auctionator Shopping List", 0.82, 0.71, 0.35)
        GameTooltip:AddLine("Creates/updates 'MBT Reagents' list with all missing reagents.", 0.8, 0.8, 0.8, true)
    end,
    nil,
    function() ns.CreateAuctionatorShoppingList() end)
auctionatorBtn:Hide()
ns.auctionatorBtn = auctionatorBtn

-- Toggle TSM prices button (coin icon)
local coinBtn = CreateToolbarButton(toolbar,
    MEDIA_PATH .. "Icon_Coins",
    function(self)
        local enabled = MajesticBeastTrackerDB.settings.tsmIntegration
        if not TSM_API then
            GameTooltip:AddLine("TSM not installed", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine(enabled and "Hide TSM Prices" or "Show TSM Prices", 1, 1, 1)
        end
    end,
    nil,
    function()
        if not TSM_API then return end
        local settings = MajesticBeastTrackerDB.settings
        settings.tsmIntegration = not settings.tsmIntegration
        ns.InvalidateLayout()
    end)
coinBtn:SetPoint("RIGHT", fishBtn, "LEFT", -2, 0)
local coinIcon = coinBtn.icon
ns.coinBtn = coinBtn
ns.coinIcon = coinIcon

------------------------------------------------------
-- Content area
------------------------------------------------------

-- Header icons, zone labels, reagent icons, lure boxes, TSM labels in UI/LureIcons.lua


-- 1-second ticker for real-time consumable buff timers + route timer
C_Timer.NewTicker(3, function()
    if ns.isInInstance then return end
    if InCombatLockdown() then return end
    if frame:IsShown() then
        ns.RefreshConsumableLabels()
        if ns.IsTimerRunning() then
            timerLabel:SetText("|cff00ff00" .. ns.FormatTimerElapsed() .. "|r")
            timerBtn:SetWidth(math.max(timerLabel:GetStringWidth() + 4, 40))
            timerLabel:Show()
            timerBtn:Show()
        end
    end
end)

-- Separator under icons — created in UI/LureIcons.lua

-- Scroll frame for character rows (between iconSep and bottomBar)
local MAX_VISIBLE_ROWS = 10  -- default, overridden by settings on login
local charScroll = CreateFrame("ScrollFrame", nil, frame)
charScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)  -- repositioned dynamically in LayoutUI
charScroll:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
local charScrollChild = CreateFrame("Frame", nil, charScroll)
charScrollChild:SetPoint("TOPLEFT", charScroll, "TOPLEFT", 0, 0)
charScrollChild:SetWidth(1)  -- set dynamically
charScrollChild:SetHeight(1) -- set dynamically
charScroll:SetScrollChild(charScrollChild)

local charScrollbar = CreateFrame("Slider", nil, frame, "UISliderTemplate")
charScrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 0)  -- repositioned dynamically
charScrollbar:SetWidth(8)
charScrollbar:SetMinMaxValues(0, 1)
charScrollbar:SetValue(0)
charScrollbar:SetValueStep(1)
charScrollbar:SetOrientation("VERTICAL")
charScrollbar:SetObeyStepOnDrag(true)
charScrollbar.thumb = charScrollbar:GetThumbTexture()
charScrollbar.thumb:SetPoint("CENTER")
charScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.4)
charScrollbar.thumb:SetWidth(8)
if charScrollbar.NineSlice then charScrollbar.NineSlice:Hide() end
charScrollbar:SetScript("OnValueChanged", function(_, value)
    charScroll:SetVerticalScroll(value)
end)
charScrollbar:SetScript("OnEnter", function() charScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.7) end)
charScrollbar:SetScript("OnLeave", function() charScrollbar.thumb:SetColorTexture(0.82, 0.71, 0.35, 0.4) end)
charScroll:EnableMouseWheel(true)
charScroll:SetScript("OnMouseWheel", function(_, delta)
    charScrollbar:SetValue(charScrollbar:GetValue() - delta * ROW_HEIGHT * 3)
end)
charScrollbar:Hide()

ns.charScroll = charScroll
ns.charScrollChild = charScrollChild
ns.charScrollbar = charScrollbar
ns.MAX_VISIBLE_ROWS = MAX_VISIBLE_ROWS

-- Travel buttons, box, and HS selector in UI/TravelBar.lua

------------------------------------------------------
-- Stats display (Skill, Perception, Finesse, Deftness)
------------------------------------------------------

local STAT_LABELS = {
    { key = "Skill",      label = "Skl", color = {1, 0.82, 0} },
    { key = "Perception", label = "Per", color = {0.2, 0.9, 0.4} },
    { key = "Finesse",    label = "Fin", color = {0.4, 0.7, 1} },
    { key = "Deftness",   label = "Dft", color = {1, 0.5, 0.2} },
}

local statsTexts = {}
for i, stat in ipairs(STAT_LABELS) do
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetFont(label:GetFont(), 9)
    label:SetTextColor(stat.color[1], stat.color[2], stat.color[3])
    label:Hide()
    statsTexts[i] = label
end

-- Total TSM cost label (below stats)
ns.tsmTotalLabel = bottomBar:CreateFontString(nil, "OVERLAY")
ns.tsmTotalLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
ns.tsmTotalLabel:SetTextColor(1, 0.84, 0)
ns.tsmTotalLabel:SetJustifyH("CENTER")
ns.tsmTotalLabel:SetPoint("CENTER", bottomBar, "CENTER", 0, 0)  -- repositioned dynamically
ns.tsmTotalLabel:Hide()

-- Weekly knowledge lines for main window (right-aligned, below stats)
local weeklyMainLines = {}
for i = 1, #ns.SKINNING_WEEKLIES do
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line:SetFont(line:GetFont(), 9)
    line:SetJustifyH("RIGHT")
    line:Hide()
    weeklyMainLines[i] = line
end
ns.STAT_LABELS = STAT_LABELS
ns.statsTexts = statsTexts
ns.weeklyMainLines = weeklyMainLines
ns.CONSUMABLES = CONSUMABLES

-- Helper: format copper as short gold string (minus prefix, no color codes)
function ns.FormatGold(copper)
    if not copper or copper <= 0 then return nil end
    local gold = math.floor(copper / 10000)
    if gold >= 1000 then
        return string.format("-%.1fk g", gold / 1000)
    elseif gold > 0 then
        return "-" .. gold .. " g"
    else
        local silver = math.floor((copper % 10000) / 100)
        return "-" .. silver .. " s"
    end
end

-- Helper: format gold amount for loot display (positive, no minus)
function ns.FormatGoldPositive(copper)
    if not copper or copper <= 0 then return "0 g" end
    local gold = math.floor(copper / 10000)
    if gold >= 1000 then
        return string.format("%.1fk g", gold / 1000)
    elseif gold > 0 then
        return gold .. " g"
    else
        local silver = math.floor((copper % 10000) / 100)
        return silver .. " s"
    end
end


-- Helper: check if player has Engineering as second profession
function ns.HasEngineering()
    local prof1, prof2 = GetProfessions()
    if prof1 then
        local _, _, _, _, _, _, skillLineID = GetProfessionInfo(prof1)
        if skillLineID == 202 then return true end
    end
    if prof2 then
        local _, _, _, _, _, _, skillLineID = GetProfessionInfo(prof2)
        if skillLineID == 202 then return true end
    end
    return false
end

-- Character rows, UpdateUI, Layout, Refresh, right-click menu: all in UI/UpdateUI.lua

-- Periodic refresh + aura/bag tracking
------------------------------------------------------

local auraFrame = CreateFrame("Frame")
auraFrame:RegisterEvent("UNIT_AURA")
auraFrame:RegisterEvent("BAG_UPDATE")
auraFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
auraFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
auraFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
auraFrame:RegisterEvent("SKILL_LINES_CHANGED")
local lastAuraUpdate = 0
auraFrame:SetScript("OnEvent", function(_, event, unit)
    if ns.isInInstance then return end
    if event == "UNIT_AURA" then
        if unit ~= "player" then return end
        -- Only invalidate stats cache, don't trigger full UpdateUI
        if ns.InvalidateProfStatsCache then ns.InvalidateProfStatsCache() end
        return
    end
    if event == "UNIT_INVENTORY_CHANGED" then
        if unit ~= "player" then return end
        -- Tool enchant may have changed — invalidate cache and relayout
        if ns.InvalidateEnchantCache then ns.InvalidateEnchantCache() end
        ns.InvalidateLayout()
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then
        -- Enchant state may reset briefly during zone change
        if ns.InvalidateEnchantCache then ns.InvalidateEnchantCache() end
        C_Timer.After(2, function()
            if ns.InvalidateEnchantCache then ns.InvalidateEnchantCache() end
            ns.InvalidateLayout()
        end)
        return
    end
    -- BAG_UPDATE, TRAIT_CONFIG_UPDATED, SKILL_LINES_CHANGED trigger layout
    if event == "TRAIT_CONFIG_UPDATED" or event == "SKILL_LINES_CHANGED" then
        if ns.InvalidateProfStatsCache then ns.InvalidateProfStatsCache() end
    end
    if ns.InvalidateEnchantCache then ns.InvalidateEnchantCache() end
    ns.InvalidateLayout()
end)

-- Hide in combat
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    ns.EnsureDB()
    if event == "PLAYER_REGEN_DISABLED" then
        -- Unregister heavy events during combat
        auraFrame:UnregisterEvent("UNIT_AURA")
        auraFrame:UnregisterEvent("BAG_UPDATE")
        -- Hide frame if setting enabled
        if MajesticBeastTrackerDB.settings.hideInCombat and frame:IsShown() then
            frame._hiddenByCombat = true
            frame:Hide()
            ns.consumableBox:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Re-register events after combat
        auraFrame:RegisterEvent("UNIT_AURA")
        auraFrame:RegisterEvent("BAG_UPDATE")
        -- Restore frame if hidden by combat
        if frame._hiddenByCombat then
            frame._hiddenByCombat = nil
            if MajesticBeastTrackerDB.settings.showFrame ~= false then
                frame:Show()
            end
        end
        ns.InvalidateLayout()
    end
end)

-- Periodic refresh (every 30s) via timer instead of OnUpdate (avoids per-frame overhead)
C_Timer.NewTicker(30, function()
    if ns.isInInstance then return end
    if InCombatLockdown() then return end
    if frame:IsShown() then
        ns.UpdateUI()
    end
end)

------------------------------------------------------
-- Init
------------------------------------------------------

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    ns.EnsureDB()
    -- Load max visible rows from settings
    if MajesticBeastTrackerDB.settings.maxVisibleRows then
        ns.MAX_VISIBLE_ROWS = MajesticBeastTrackerDB.settings.maxVisibleRows
    end
    if MajesticBeastTrackerDB.settings.framePosition then
        local pos = MajesticBeastTrackerDB.settings.framePosition
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[3], pos[4], pos[5])
    end
    if MajesticBeastTrackerDB.settings.showFrame == false then
        frame:Hide()
    else
        -- Delay show to check if current char has skinning
        C_Timer.After(1, function()
            ns.EnsureDB()
            local hideNonSkinner = MajesticBeastTrackerDB.settings.hideNonSkinner
            if hideNonSkinner == nil then hideNonSkinner = true end -- default on
            local key = ns.GetCharKey and ns.GetCharKey()
            local charData = key and MajesticBeastTrackerDB.chars[key]
            local isSkinner = charData and charData.hasSkinning
            local isHiddenChar = key and MajesticBeastTrackerDB.settings.hiddenChars and MajesticBeastTrackerDB.settings.hiddenChars[key]
            if isHiddenChar then
                -- Hidden character → don't show tracker
                frame:Hide()
            elseif isSkinner then
                frame:Show()
            elseif hideNonSkinner then
                -- Non-skinner + hide enabled → always hide on login
                frame:Hide()
            else
                frame:Show()
            end
            ns.UpdateLockVisual()
            ns.InvalidateLayout()
        end)
        return
    end
    ns.UpdateLockVisual()
    C_Timer.After(1, ns.UpdateUI)
end)

------------------------------------------------------
-- Public API
------------------------------------------------------

function ns.ShowFrame()
    if ns.isInInstance then
        print("|cff3FC7EB[MBT]|r Disabled in instances. Change in Settings > Display.")
        return
    end
    if not InCombatLockdown() then
        frame:Show()
    end
    ns.EnsureDB()
    MajesticBeastTrackerDB.settings.showFrame = true
    ns.InvalidateLayout()
    ns.RefreshAutoHide()
end

function ns.HideFrame()
    if not InCombatLockdown() then
        frame:Hide()
    end
    if ns.lootEditor then ns.lootEditor:Hide() end
    if ns.lootSummary then ns.lootSummary:Hide() end
    ns.EnsureDB()
    MajesticBeastTrackerDB.settings.showFrame = false
    -- Hide consumable buttons and box
    if not InCombatLockdown() then
        for _, btn in ipairs(ns.consumableButtons) do btn:Hide() end
        ns.consumableBox:Hide()
        for _, btn in ipairs(ns.travelButtons) do btn:Hide() end
        ns.wormholeBtn:Hide()
        ns.mageTeleportBtn:Hide()
        ns.vulperaReturnBtn:Hide()
    end
end

function ns.ToggleLock()
    ns.EnsureDB()
    MajesticBeastTrackerDB.settings.locked = not MajesticBeastTrackerDB.settings.locked
    ns.UpdateLockVisual()
    local state = MajesticBeastTrackerDB.settings.locked and "locked" or "unlocked"
    print("|cff3FC7EB[MBT]|r Frame " .. state .. ".")
end

------------------------------------------------------
-- Minimap Button (LibDBIcon)
------------------------------------------------------

local function InitMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    local lureIcon = "Interface\\AddOns\\" .. addonName .. "\\icon"

    local dataObj = LDB:NewDataObject("MajesticBeastTracker", {
        type = "data source",
        text = "Majestic Beast Tracker",
        icon = lureIcon,
        OnClick = function(_, button)
            if button == "LeftButton" then
                if frame:IsShown() then
                    ns.HideFrame()
                else
                    ns.ShowFrame()
                end
            elseif button == "RightButton" then
                ns.OpenSettings()
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip then return end
            tooltip:AddLine(C_ACCENT:WrapTextInColorCode("Majestic Beast Tracker"))
            tooltip:AddLine("Left-click: Toggle window", 0.7, 0.7, 0.7)
            tooltip:AddLine("Right-click: Settings", 0.7, 0.7, 0.7)
        end,
    })

    ns.EnsureDB()
    icon:Register("MajesticBeastTracker", dataObj, MajesticBeastTrackerDB.settings.minimap)
end

-- Init on login (Settings moved to Settings.lua)
local minimapInit = CreateFrame("Frame")
minimapInit:RegisterEvent("PLAYER_LOGIN")
minimapInit:SetScript("OnEvent", function()
    InitMinimapIcon()
    local ok, err = pcall(ns.InitSettings)
    if not ok then
        print("|cffff3333[MBT] Settings error:|r " .. tostring(err))
    end
    ns.EnsureDB()
    frame:SetScale(MajesticBeastTrackerDB.settings.windowScale)
end)

