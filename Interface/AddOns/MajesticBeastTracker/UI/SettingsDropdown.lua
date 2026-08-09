------------------------------------------------------
-- MajesticBeastTracker UI - Settings Dropdown
-- Gold-themed fly-out settings menu
------------------------------------------------------

local _, ns = ...
local C_BORDER_RGB = ns.C_BORDER_RGB

-- Settings dropdown frame (custom, gold-themed)
local settingsDropdown = CreateFrame("Frame", "MBT_SettingsDropdown", UIParent, "BackdropTemplate")
settingsDropdown:SetBackdrop(ns.BACKDROP)
settingsDropdown:SetBackdropColor(0, 0, 0, 0.97)
settingsDropdown:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3])
settingsDropdown:SetFrameStrata("DIALOG")
settingsDropdown:SetFrameLevel(500)
settingsDropdown:EnableMouse(true)
settingsDropdown:Hide()
settingsDropdown:SetClampedToScreen(true)

local SD_WIDTH = 230
local SD_ROW_HEIGHT = 18
local SD_PAD = 6
local SD_GOLD = { 0.82, 0.71, 0.35 }
local SD_TEXT = { 0.9, 0.9, 0.9 }
local SD_DIM = { 0.5, 0.5, 0.5 }
local SD_ARROW = " |cffD1B559>|r"

-- Category definitions: { name, buildFunc }
local sdCurrentView = nil  -- nil = main menu, string = category name
local sdCategories = {}
local sdRowFrames = {}

local function DefineCategories()
    sdCategories = {}
    ns.EnsureDB()
    local s = MajesticBeastTrackerDB.settings

    sdCategories[#sdCategories + 1] = { name = "Route", items = function()
        local t = {}
        for _, lure in ipairs(ns.LURES) do
            local ln = lure.name
            local flatKey = "routeSkip_" .. ln:gsub("[%s']", "")
            t[#t + 1] = { text = "Skip " .. ln, get = function()
                return (s.routeSkip and s.routeSkip[ln]) or s[flatKey] or false
            end, set = function()
                if not s.routeSkip then s.routeSkip = {} end
                local newVal = not ((s.routeSkip[ln]) or s[flatKey] or false)
                s.routeSkip[ln] = newVal
                s[flatKey] = newVal
            end }
        end
        t[#t + 1] = { text = "Hide Skipped Columns", get = function() return s.routeHideSkipped end, set = function() s.routeHideSkipped = not s.routeHideSkipped end }
        t[#t + 1] = { text = "Auto-Waypoint", get = function() return s.autoRouteWaypoint end, set = function() s.autoRouteWaypoint = not s.autoRouteWaypoint end }
        return t
    end }

    sdCategories[#sdCategories + 1] = { name = "Reagents & AH", items = function()
        return {
            { text = "Show Reagent Icons", get = function() return s.showReagents ~= false end, set = function() s.showReagents = not (s.showReagents ~= false) end },
            { text = "Count All Characters", get = function() return s.reagentAllChars end, set = function() s.reagentAllChars = not s.reagentAllChars end },
            { text = "Show Missing Count", get = function() return s.showMissingCount end, set = function() s.showMissingCount = not s.showMissingCount end },
            { text = "Always Show Counts", get = function() return s.alwaysShowReagentCounts end, set = function() s.alwaysShowReagentCounts = not s.alwaysShowReagentCounts end },
            { text = "Autofill AH Quantity", get = function() return s.ahAutofillQuantity end, set = function() s.ahAutofillQuantity = not s.ahAutofillQuantity end },
        }
    end }

    sdCategories[#sdCategories + 1] = { name = "Consumables", items = function()
        local t = {}
        for _, cons in ipairs(ns.CONSUMABLE_ITEMS) do
            local cID = cons.itemID or cons.spellID
            t[#t + 1] = { text = cons.name, get = function() return s["consShow_" .. cID] ~= false end,
                set = function() s["consShow_" .. cID] = not (s["consShow_" .. cID] ~= false) end }
        end
        return t
    end }

    sdCategories[#sdCategories + 1] = { name = "Loot Tracking", items = function()
        return {
            { text = "Enable Loot Tracking", get = function() return s.lootTracking ~= false end, set = function() s.lootTracking = not (s.lootTracking ~= false) end },
            { text = "Integrate TSM Prices", get = function() return s.tsmIntegration ~= false end, set = function() s.tsmIntegration = not (s.tsmIntegration ~= false) end },
            { text = "Show Drop %", get = function() return s.showDropPercent end, set = function() s.showDropPercent = not s.showDropPercent end },
            { text = "Drop Rate: Per Kill", get = function() return s.dropPercentFormat end, set = function() s.dropPercentFormat = not s.dropPercentFormat end },
        }
    end }

    sdCategories[#sdCategories + 1] = { name = "Warband Bank", items = function()
        return {
            { text = "Enable Deposit", get = function() return s.warbankDeposit end, set = function() s.warbankDeposit = not s.warbankDeposit end },
            { text = "Auto Deposit on Open", get = function() return s.warbankAutoDeposit end, set = function() s.warbankAutoDeposit = not s.warbankAutoDeposit end },
            { text = "Deposit Beast Rewards", get = function() return s.warbankDepositRewards end, set = function() s.warbankDepositRewards = not s.warbankDepositRewards end },
            { text = "Deposit Lure Reagents", get = function() return s.warbankDepositReagents end, set = function() s.warbankDepositReagents = not s.warbankDepositReagents end },
        }
    end }

    sdCategories[#sdCategories + 1] = { name = "Display", items = function()
        return {
            { text = "Hide in Combat", get = function() return s.hideInCombat end, set = function() s.hideInCombat = not s.hideInCombat end },
            { text = "Disable in Instances", get = function() return s.disableInInstance ~= false end, set = function() s.disableInInstance = not (s.disableInInstance ~= false) end },
            { text = "Lock Frame", get = function() return s.locked end, set = function() s.locked = not s.locked end },
            { text = "Chat Notifications", get = function() return s.chatNotify ~= false end, set = function() s.chatNotify = not (s.chatNotify ~= false) end },
            { text = "Hide on Non-Skinners", get = function() return s.hideNonSkinner end, set = function() s.hideNonSkinner = not s.hideNonSkinner end },
        }
    end }

    sdCategories[#sdCategories + 1] = { name = "Borders", items = function()
        return {
            { text = "Lure + Reagent Borders", get = function() return s.showLureBorders end, set = function() s.showLureBorders = not s.showLureBorders end },
            { text = "Travel + Consumable Borders", get = function() return s.showConsBorders ~= false end, set = function() s.showConsBorders = not (s.showConsBorders ~= false) end },
        }
    end }
end

-- Submenu frame (fly-out, appears beside main menu on hover)
local settingsSubmenu = CreateFrame("Frame", "MBT_SettingsSubmenu", UIParent, "BackdropTemplate")
settingsSubmenu:SetBackdrop(ns.BACKDROP)
settingsSubmenu:SetBackdropColor(0, 0, 0, 0.97)
settingsSubmenu:SetBackdropBorderColor(C_BORDER_RGB[1], C_BORDER_RGB[2], C_BORDER_RGB[3])
settingsSubmenu:SetFrameStrata("DIALOG")
settingsSubmenu:SetFrameLevel(501)
settingsSubmenu:EnableMouse(true)
settingsSubmenu:Hide()
settingsSubmenu:SetClampedToScreen(true)

local sdMainRowFrames = {}
local sdSubRowFrames = {}
local sdActiveCategory = nil

local function GetRowFrame(pool, parent, i)
    if not pool[i] then
        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(SD_ROW_HEIGHT)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetFont(label:GetFont(), 10)
        label:SetPoint("LEFT", 4, 0)
        label:SetJustifyH("LEFT")
        f.label = label
        local right = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        right:SetFont(right:GetFont(), 10)
        right:SetPoint("LEFT", SD_WIDTH - SD_PAD * 2 - 60, 0)
        right:SetJustifyH("LEFT")
        f.right = right
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        f.hl = hl
        pool[i] = f
    end
    pool[i]:SetParent(parent)
    return pool[i]
end

-- Show submenu for a category, anchored to the hovered row
local function ShowSubmenu(cat, anchorRow)
    local items = cat.items()
    local y = -SD_PAD
    local idx = 0

    -- Header
    idx = idx + 1
    local hf = GetRowFrame(sdSubRowFrames, settingsSubmenu, idx)
    hf:ClearAllPoints()
    hf:SetPoint("TOPLEFT", settingsSubmenu, "TOPLEFT", SD_PAD, y)
    hf:SetPoint("TOPRIGHT", settingsSubmenu, "TOPRIGHT", -SD_PAD, y)
    hf:SetHeight(SD_ROW_HEIGHT)
    hf.label:SetText("|cffD1B559" .. cat.name .. "|r")
    hf.right:SetText("")
    hf.hl:Hide()
    hf:EnableMouse(false)
    hf:SetScript("OnClick", nil)
    hf:SetScript("OnEnter", nil)
    hf:SetScript("OnLeave", nil)
    hf:Show()
    y = y - SD_ROW_HEIGHT

    for _, item in ipairs(items) do
        idx = idx + 1
        local f = GetRowFrame(sdSubRowFrames, settingsSubmenu, idx)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", settingsSubmenu, "TOPLEFT", SD_PAD, y)
        f:SetPoint("TOPRIGHT", settingsSubmenu, "TOPRIGHT", -SD_PAD, y)
        f:SetHeight(SD_ROW_HEIGHT)
        local isOn = item.get()
        f.label:SetText(item.text)
        f.label:SetTextColor(unpack(isOn and SD_TEXT or SD_DIM))
        f.right:ClearAllPoints()
        f.right:SetPoint("LEFT", SD_WIDTH - SD_PAD * 2 - 60, 0)
        f.right:SetJustifyH("LEFT")
        f.right:SetText(isOn and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r")
        f.hl:Show()
        f:EnableMouse(true)
        local itemRef = item
        local catRef = cat
        f:SetScript("OnClick", function()
            itemRef.set()
            ns.InvalidateLayout()
            ShowSubmenu(catRef, anchorRow)
        end)
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:Show()
        y = y - SD_ROW_HEIGHT
    end

    for i = idx + 1, #sdSubRowFrames do sdSubRowFrames[i]:Hide() end
    settingsSubmenu:SetSize(SD_WIDTH, math.abs(y) + SD_PAD)

    -- Position: try right side of main menu, fall back to left
    settingsSubmenu:ClearAllPoints()
    local mainRight = settingsDropdown:GetRight() or 0
    local screenW = GetScreenWidth() * UIParent:GetEffectiveScale()
    if mainRight + SD_WIDTH < screenW then
        settingsSubmenu:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 0, SD_PAD)
    else
        settingsSubmenu:SetPoint("TOPRIGHT", anchorRow, "TOPLEFT", 0, SD_PAD)
    end
    settingsSubmenu:Show()
    sdActiveCategory = cat.name
end

-- Populate main menu
local function PopulateMainMenu()
    DefineCategories()
    local y = -SD_PAD
    local idx = 0

    for _, cat in ipairs(sdCategories) do
        idx = idx + 1
        local f = GetRowFrame(sdMainRowFrames, settingsDropdown, idx)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", settingsDropdown, "TOPLEFT", SD_PAD, y)
        f:SetPoint("TOPRIGHT", settingsDropdown, "TOPRIGHT", -SD_PAD, y)
        f:SetHeight(SD_ROW_HEIGHT)
        f.label:SetText(cat.name)
        f.label:SetTextColor(SD_TEXT[1], SD_TEXT[2], SD_TEXT[3])
        f.right:ClearAllPoints()
        f.right:SetPoint("RIGHT", -4, 0)
        f.right:SetJustifyH("RIGHT")
        f.right:SetText(SD_ARROW)
        f.hl:Show()
        f:EnableMouse(true)
        local catRef = cat
        f:SetScript("OnClick", nil)
        f:SetScript("OnEnter", function(self)
            if sdActiveCategory ~= catRef.name then
                ShowSubmenu(catRef, self)
            end
        end)
        f:SetScript("OnLeave", function()
            -- Submenu hides on its own via mouse check
        end)
        f:Show()
        y = y - SD_ROW_HEIGHT
    end

    for i = idx + 1, #sdMainRowFrames do sdMainRowFrames[i]:Hide() end
    settingsDropdown:SetSize(SD_WIDTH, math.abs(y) + SD_PAD)
end

-- Toggle dropdown on settings button click
local settingsBtn = ns._settingsBtn
settingsBtn:SetScript("OnClick", function(self)
    if settingsDropdown:IsShown() then
        settingsDropdown:Hide()
        settingsSubmenu:Hide()
    else
        sdActiveCategory = nil
        PopulateMainMenu()
        settingsDropdown:ClearAllPoints()
        settingsDropdown:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
        settingsDropdown:Show()
    end
end)

-- Close dropdown + submenu when clicking outside
settingsDropdown:SetScript("OnShow", function()
    settingsDropdown:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
settingsDropdown:SetScript("OnHide", function()
    settingsDropdown:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    settingsSubmenu:Hide()
    sdActiveCategory = nil
end)
settingsDropdown:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" then
        if not self:IsMouseOver() and not settingsBtn:IsMouseOver()
           and not settingsSubmenu:IsMouseOver() then
            self:Hide()
        end
    end
end)
