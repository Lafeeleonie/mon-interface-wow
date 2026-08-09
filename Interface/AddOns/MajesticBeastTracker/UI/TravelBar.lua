------------------------------------------------------
-- MajesticBeastTracker UI - Travel Buttons
-- Hearthstone, Dalaran HS, Arcantina, Wormhole, Mage TP, Vulpera
------------------------------------------------------

local _, ns = ...

-- Travel items
local TRAVEL_ITEMS = {
    { itemID = 6948, name = "Hearthstone" },
    { itemID = 140192, name = "Dalaran Hearthstone", isToy = true },
    { itemID = 253629, name = "Personal Key to the Arcantina", isToy = true },
}
-- Wormhole Generator: conditional on Engineering profession + item in bags
local WORMHOLE_ITEM = { itemID = 248485, name = "Wormhole Generator: Quel'Thalas", spellID = 1229928, requiresEngineering = true, isToy = true }
-- Mage Teleport: Silvermoon City (conditional on class)
local MAGE_TELEPORT = { spellID = 1259190, name = "Teleport: Silvermoon City", isSpell = true, requiresClass = "MAGE" }
-- Vulpera Return to Camp (conditional on race)
local VULPERA_RETURN = { spellID = 312372, name = "Return to Camp", isSpell = true, requiresRace = "Vulpera" }
-- Path of the Windrunners: Windrunner Spire teleport, Eversong access (conditional on knowing the spell)
local PATH_WINDRUNNERS = { spellID = 1254400, name = "Path of the Windrunners", isSpell = true, requiresKnown = true }

local TRAVEL_ICON_SIZE = 22
local TRAVEL_SPACING = 3

-- Expose constants for UpdateUI (layout calculations)
ns.TRAVEL_ICON_SIZE = TRAVEL_ICON_SIZE
ns.TRAVEL_SPACING = TRAVEL_SPACING
ns.TRAVEL_ITEMS = TRAVEL_ITEMS
ns.WORMHOLE_ITEM = WORMHOLE_ITEM

local frame = ns.frame
local C_BORDER_RGB = ns.C_BORDER_RGB
local C_SEPARATOR = { 0.82, 0.71, 0.35, 0.3 }
local NAME_COL_WIDTH = ns.NAME_COL_WIDTH
local BACKDROP = ns.BACKDROP

------------------------------------------------------
-- Travel separator + box
------------------------------------------------------

ns.travelSep = frame:CreateTexture(nil, "ARTWORK")
ns.travelSep:SetHeight(1)
ns.travelSep:SetColorTexture(unpack(C_SEPARATOR))
ns.travelSep:Hide()

local travelBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
travelBox:SetSize(NAME_COL_WIDTH, TRAVEL_ICON_SIZE + 8)
travelBox:SetBackdrop(BACKDROP)
travelBox:SetBackdropColor(0, 0, 0, 0.9)
travelBox:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3], 0.7)
travelBox:SetFrameStrata("MEDIUM")
travelBox:SetFrameLevel(201)
ns.travelBox = travelBox

------------------------------------------------------
-- CreateTravelButton
------------------------------------------------------

local travelButtons = {}

local function CreateTravelButton(index, itemInfo)
    local btn = CreateFrame("Button", "MBT_TravelBtn" .. index, frame, "SecureActionButtonTemplate")
    btn:SetSize(TRAVEL_ICON_SIZE, TRAVEL_ICON_SIZE)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:Hide()

    if itemInfo.isSpell then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", itemInfo.spellID)
    elseif itemInfo.isToy then
        btn:SetAttribute("type", "toy")
        btn:SetAttribute("toy", itemInfo.itemID)
    else
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", itemInfo.name)
        -- Cache item name async
        C_Item.RequestLoadItemDataByID(itemInfo.itemID)
        local ticker
        ticker = C_Timer.NewTicker(1, function()
            local name = C_Item.GetItemNameByID(itemInfo.itemID)
            if name and not InCombatLockdown() then
                btn:SetAttribute("item", name)
                ticker:Cancel()
            end
        end, 10)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local cdHolder = CreateFrame("Frame", nil, btn)
    cdHolder:SetAllPoints()
    local cd = CreateFrame("Cooldown", nil, cdHolder, "CooldownFrameTemplate")
    cd:SetSize(TRAVEL_ICON_SIZE / 0.7, TRAVEL_ICON_SIZE / 0.7)
    cd:SetScale(0.7)
    cd:SetPoint("CENTER")
    cd:SetDrawEdge(true)
    btn.cooldown = cd

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

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        if itemInfo.isSpell then
            GameTooltip:SetSpellByID(itemInfo.spellID)
        elseif itemInfo.isToy then
            GameTooltip:SetToyByItemID(itemInfo.itemID)
        else
            GameTooltip:SetItemByID(itemInfo.itemID)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: Use", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn.itemInfo = itemInfo
    return btn
end

-- Create static travel buttons (Hearthstone + Dalaran HS + Arcantina)
for i, item in ipairs(TRAVEL_ITEMS) do
    travelButtons[i] = CreateTravelButton(i, item)
end

------------------------------------------------------
-- Hearthstone slot: replaceable by dragging a toy
------------------------------------------------------

local hsBtn = travelButtons[1]

local function ApplyCustomHearthstone(toyItemID)
    if InCombatLockdown() then return end
    ns.EnsureDB()
    if toyItemID then
        MajesticBeastTrackerDB.settings.hearthstoneToy = toyItemID
        hsBtn:SetAttribute("type", "toy")
        hsBtn:SetAttribute("toy", toyItemID)
        hsBtn:SetAttribute("item", nil)
        hsBtn.itemInfo = { itemID = toyItemID, name = C_Item.GetItemNameByID(toyItemID) or "Hearthstone", isToy = true, isCustomHS = true }
        local tex = ns.GetItemIcon(toyItemID)
        if tex then hsBtn.icon:SetTexture(tex) end
    else
        -- Reset to default Hearthstone
        MajesticBeastTrackerDB.settings.hearthstoneToy = nil
        hsBtn:SetAttribute("type", "item")
        hsBtn:SetAttribute("item", "Hearthstone")
        hsBtn:SetAttribute("toy", nil)
        hsBtn.itemInfo = TRAVEL_ITEMS[1]
        local tex = ns.GetItemIcon(6948)
        if tex then hsBtn.icon:SetTexture(tex) end
    end
end

-- Extract the "Use:" line from the base Hearthstone tooltip (locale-safe)
local HS_USE_TEXT
do
    local tt = CreateFrame("GameTooltip", "MBT_HSCheck", nil, "GameTooltipTemplate")
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:SetItemByID(6948)
    for i = 1, tt:NumLines() do
        local line = _G["MBT_HSCheckTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:match("^Use:") then
                HS_USE_TEXT = text:gsub("^Use:%s*", "")
                break
            end
        end
    end
    tt:Hide()
end

-- Validate that a toy is a hearthstone variant (tooltip contains base HS description)
local function IsHearthstoneToy(itemID)
    if not itemID or not PlayerHasToy(itemID) or not HS_USE_TEXT then return false end
    local tt = _G["MBT_HSCheck"]
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:SetToyByItemID(itemID)
    for i = 1, tt:NumLines() do
        local line = _G["MBT_HSCheckTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find(HS_USE_TEXT, 1, true) then
                tt:Hide()
                return true
            end
        end
    end
    tt:Hide()
    return false
end

-- Drop zone overlay: intercepts clicks when cursor holds an item
local hsDropZone = CreateFrame("Button", nil, hsBtn)
hsDropZone:SetAllPoints()
hsDropZone:SetFrameLevel(hsBtn:GetFrameLevel() + 5)
hsDropZone:RegisterForClicks("LeftButtonUp")
hsDropZone:Hide()
hsDropZone:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local infoType, id = GetCursorInfo()
    if infoType == "item" and id and IsHearthstoneToy(id) then
        ApplyCustomHearthstone(id)
        ClearCursor()
    else
        ClearCursor()
    end
end)
-- Show drop zone only when cursor holds an item
hsBtn:HookScript("OnEnter", function()
    if GetCursorInfo() then hsDropZone:Show() end
end)
hsDropZone:SetScript("OnEnter", function()
    if not GetCursorInfo() then hsDropZone:Hide() end
end)
hsDropZone:SetScript("OnLeave", function()
    hsDropZone:Hide()
end)

-- Right-click tooltip hint + reset
local origHSEnter = hsBtn:GetScript("OnEnter")
hsBtn:SetScript("OnEnter", function(self)
    if origHSEnter then origHSEnter(self) end
    if self.itemInfo.isCustomHS then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag a Hearthstone toy to replace", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Shift+Right-click: Reset to default", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag a Hearthstone toy to replace", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end)

-- PreClick: Shift+Right-click reset
hsBtn:HookScript("PreClick", function(self, button)
    if InCombatLockdown() then return end
    if button == "RightButton" and IsShiftKeyDown() and self.itemInfo.isCustomHS then
        self:SetAttribute("type", nil)
    end
end)

-- PostClick: complete reset or restore type after blocked click
hsBtn:HookScript("PostClick", function(self, button)
    if InCombatLockdown() then return end
    if button == "RightButton" and IsShiftKeyDown() and self.itemInfo.isCustomHS then
        ApplyCustomHearthstone(nil)
    end
    if not self:GetAttribute("type") then
        if self.itemInfo.isToy then
            self:SetAttribute("type", "toy")
        else
            self:SetAttribute("type", "item")
        end
    end
end)

-- Restore saved custom HS on login (retry until DB is ready)
local function RestoreCustomHearthstone()
    ns.EnsureDB()
    local savedToy = MajesticBeastTrackerDB and MajesticBeastTrackerDB.settings and MajesticBeastTrackerDB.settings.hearthstoneToy
    if savedToy and not InCombatLockdown() then
        ApplyCustomHearthstone(savedToy)
    elseif savedToy then
        C_Timer.After(2, RestoreCustomHearthstone)
    end
end
C_Timer.After(3, RestoreCustomHearthstone)

-- Conditional travel buttons (created but shown based on class/profession/race/spell)
local wormholeBtn = CreateTravelButton(#TRAVEL_ITEMS + 1, WORMHOLE_ITEM)
local mageTeleportBtn = CreateTravelButton(#TRAVEL_ITEMS + 2, MAGE_TELEPORT)
local vulperaReturnBtn = CreateTravelButton(#TRAVEL_ITEMS + 3, VULPERA_RETURN)
local pathWindrunnersBtn = CreateTravelButton(#TRAVEL_ITEMS + 4, PATH_WINDRUNNERS)

-- Expose for UpdateUI
ns.travelButtons = travelButtons
ns.wormholeBtn = wormholeBtn
ns.mageTeleportBtn = mageTeleportBtn
ns.vulperaReturnBtn = vulperaReturnBtn
ns.pathWindrunnersBtn = pathWindrunnersBtn
ns.PATH_WINDRUNNERS = PATH_WINDRUNNERS
