-- MonkStaggerBarPrime - Simple moveable stagger bar for Brewmaster Monks
-- Version 2.0.0 (addon Sounds folder + custom scrollable dropdown)

local addonName = ...
local title = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Title") or GetAddOnMetadata(addonName, "Title")
local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or GetAddOnMetadata(addonName, "Version")

-- Stagger spell IDs for icons
local STAGGER_LIGHT    = 124275
local STAGGER_MODERATE = 124274
local STAGGER_HEAVY    = 124273

-- ============================================================================
-- Addon Sounds (MANUAL LIST)
-- Folder: Interface\AddOns\MonkStaggerBarPrime\Sounds\
-- ============================================================================
addonSounds = {
    -- Sound files in the Sounds folder
    { name = "Aggro", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Aggro.mp3" },
    { name = "Arrow Swoosh", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Arrow_Swoosh.mp3" },
    { name = "Bam", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Bam.mp3" },
    { name = "Bear Polar", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Bear Polar.mp3" },
    { name = "Big Kiss", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Big Kiss.mp3" },
    { name = "Bite", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Bite.mp3" },
    { name = "Bloodbath", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Bloodbath.mp3" },
    { name = "Burp", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Burp.mp3" },
    { name = "Cat", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Cat.mp3" },
    { name = "Chant1", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Chant1.mp3" },
    { name = "Chant2", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Chant2.mp3" },
    { name = "Chimes", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Chimes.mp3" },
    { name = "Cookie", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Cookie.mp3" },
    { name = "Espark", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Espark.mp3" },
    { name = "Fireball", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Fireball.mp3" },
    { name = "Gasp", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Gasp.mp3" },
    { name = "Health Low", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Health_Low.mp3" },
    { name = "Heartbeat", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Heartbeat.mp3" },
    { name = "Hic", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Hic.mp3" },
    { name = "Huh", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Huh.mp3" },
    { name = "Hurricane", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Hurricane.mp3" },
    { name = "Hyena", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Hyena.mp3" },
    { name = "Kaching", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Kaching.mp3" },
    { name = "Mana Low", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Mana_Low.mp3" },
    { name = "Moan", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Moan.mp3" },
    { name = "Panther", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Panther.mp3" },
    { name = "Phone", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Phone.mp3" },
    { name = "Punch", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Punch.mp3" },
    { name = "Rainroof", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Rainroof.mp3" },
    { name = "Rocket", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Rocket.mp3" },
    { name = "Ship Horn", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Ship_Horn.mp3" },
    { name = "Shot", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Shot.mp3" },
    { name = "Snake", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Snake.mp3" },
    { name = "Sneeze", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Sneeze.mp3" },
    { name = "Sonar", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Sonar.mp3" },
    { name = "Splash", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Splash.mp3" },
    { name = "Squeaky", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Squeaky.mp3" },
    { name = "Sword", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Sword.mp3" },
    { name = "Throw", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Throw.mp3" },
    { name = "Thunder", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Thunder.mp3" },
    { name = "Vengeance", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Vengeance.mp3" },
    { name = "Warpath", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Warpath.mp3" },
    { name = "Wicked Laugh Female", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Wicked_Laugh_Female.mp3" },
    { name = "Wicked Laugh Male", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Wicked_Laugh_Male.mp3" },
    { name = "Wilhelm", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Wilhelm.mp3" },
    { name = "Wolf", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Wolf.mp3" },
    { name = "Yeehaw", path = "Interface\\AddOns\\MonkStaggerBarPrime\\Sounds\\Yeehaw.mp3" },
}

MSBP_SOUND_THRESHOLD_MAX = 200
MSBP_FLASH_THRESHOLD_MAX = 200

-- Get icon textures
local function GetSpellIcon(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellId)
        if icon then return icon end
    end
    return "Interface\\Icons\\monk_stance_drunkenox"
end

local iconLight    = GetSpellIcon(STAGGER_LIGHT)
local iconModerate = GetSpellIcon(STAGGER_MODERATE)
local iconHeavy    = GetSpellIcon(STAGGER_HEAVY)
local iconNone     = "Interface\\Icons\\monk_stance_drunkenox"

local function Clamp(n, minv, maxv)
    if n < minv then return minv end
    if n > maxv then return maxv end
    return n
end

-- Defaults
local defaults = {
    locked = false,
    width = 200,
    height = 24,
    fontSize = 12,
    posX = 0,
    posY = -200,
    texture = 1,
    hideOOC = false,
    hideZeroStagger = false,
    displayMode = 1, -- 1 = Bar Only, 2 = Icon Only, 3 = Icon + Bar
    textMode = 1, -- 1 = Value + Percent, 2 = Percent Only
    iconSize = 32,

    -- Alert options
    alertEnabled = true,
    alertThreshold = 40, -- percent
    alertSoundIndex = 1,

    -- flashing border
    flashEnabled = true,
    flashThreshold = 100,
}

-- Display mode names
local displayModeNames = {
    [1] = "Bar Only",
    [2] = "Icon Only",
    [3] = "Icon + Bar",
}

-- Texture options
local texturePaths = {
    [1] = "Interface\\TargetingFrame\\UI-StatusBar",
    [2] = "Interface\\Buttons\\WHITE8x8",
    [3] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
local textureNames = {
    [1] = "Default",
    [2] = "Smooth",
    [3] = "Raid",
}

-- Stagger colors
local colorNone     = {0.3,  0.3,  0.3,  1}
local colorLight    = {0.52, 0.90, 0.52, 1}
local colorModerate = {1.0,  0.85, 0.36, 1}
local colorHeavy    = {1.0,  0.42, 0.42, 1}

-- State
local inCombat = false
local testMode = false

-- Sound alert anti-spam
local wasAboveAlert = false
local lastAlertTime = 0

-- ============================================================================
-- Main bar frame
-- ============================================================================
local frame = CreateFrame("Frame", "MonkStaggerBarPrimeFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)

-- Icon frame
local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
iconFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
iconFrame:SetBackdropColor(0, 0, 0, 0.8)
iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 2, -2)
icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Bar frame
local barFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
barFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
barFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
barFrame:SetBackdropBorderColor(0, 0, 0, 1)

-- Status bar
local bar = CreateFrame("StatusBar", nil, barFrame)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
bar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 2, -2)
bar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -2, 2)

-- Overflow bar
local overflowBar = CreateFrame("StatusBar", nil, barFrame)
overflowBar:SetMinMaxValues(0, 1)
overflowBar:SetValue(0)
overflowBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 2, -2)
overflowBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -2, 2)
overflowBar:SetFrameLevel(bar:GetFrameLevel() + 1)
overflowBar:Hide()

-- flashing border
local flashBorder = CreateFrame("Frame", nil, barFrame, "BackdropTemplate")
flashBorder:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -5, 5)
flashBorder:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 5, -5)
flashBorder:SetFrameLevel(barFrame:GetFrameLevel() + 10)

flashBorder:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 5,
})
flashBorder:SetBackdropBorderColor(1, 1, 1, 0)
flashBorder:Hide()

flashBorder.glow = flashBorder:CreateTexture(nil, "BACKGROUND")
flashBorder.glow:SetPoint("TOPLEFT", flashBorder, "TOPLEFT", -6, 6)
flashBorder.glow:SetPoint("BOTTOMRIGHT", flashBorder, "BOTTOMRIGHT", 6, -6)
flashBorder.glow:SetColorTexture(1, 1, 1, 0.1)

-- flashing animation
flashBorder.anim = flashBorder:CreateAnimationGroup()
flashBorder.anim:SetLooping("REPEAT")

local fadeIn = flashBorder.anim:CreateAnimation("Alpha")
fadeIn:SetOrder(1)
fadeIn:SetFromAlpha(0.15)
fadeIn:SetToAlpha(0.95)
fadeIn:SetDuration(0.25)

local fadeOut = flashBorder.anim:CreateAnimation("Alpha")
fadeOut:SetOrder(2)
fadeOut:SetFromAlpha(0.95)
fadeOut:SetToAlpha(0.15)
fadeOut:SetDuration(0.25)

-- Text
local text = bar:CreateFontString(nil, "OVERLAY")
text:SetDrawLayer("OVERLAY", 7)
text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
text:SetPoint("CENTER", bar, "CENTER", 0, 0)
text:SetTextColor(1, 1, 1, 1)
text:SetText("Stagger: 0")

-- Apply layout based on display mode
local function UpdateLayout()
    local db = MonkStaggerBarPrimeDB
    if not db then return end

    local mode = db.displayMode or 1
    local iconSize = db.iconSize or 32
    local barWidth = db.width or 200
    local barHeight = db.height or 24

    iconFrame:SetSize(iconSize, iconSize)
    barFrame:SetSize(barWidth, barHeight)

    if mode == 1 then
        iconFrame:Hide()
        barFrame:Show()
        barFrame:ClearAllPoints()
        barFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame:SetSize(barWidth, barHeight)
    elseif mode == 2 then
        iconFrame:Show()
        barFrame:Hide()
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame:SetSize(iconSize, iconSize)
    else
        iconFrame:Show()
        barFrame:Show()
        iconFrame:ClearAllPoints()
        barFrame:ClearAllPoints()
        iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
        barFrame:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
        frame:SetSize(iconSize + 4 + barWidth, math.max(iconSize, barHeight))
    end
end

local function StartFlashBorder()
    flashBorder:Show()
    flashBorder:SetAlpha(1)
    flashBorder:SetBackdropBorderColor(1, 1, 1, 0.9)
    flashBorder.glow:SetAlpha(0.25)

    if not flashBorder.anim:IsPlaying() then
        flashBorder.anim:Play()
    end
end

local function StopFlashBorder()
    if flashBorder.anim:IsPlaying() then
        flashBorder.anim:Stop()
    end

    flashBorder:SetAlpha(1)
    flashBorder:SetBackdropBorderColor(1, 1, 1, 0)
    flashBorder.glow:SetAlpha(0)
    flashBorder:Hide()
end

function ApplySettings()
    local db = MonkStaggerBarPrimeDB
    if not db then return end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)

    local texIdx = db.texture or 1
    if texIdx < 1 or texIdx > 3 then texIdx = 1 end
    bar:SetStatusBarTexture(texturePaths[texIdx])
    overflowBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fontSize = db.fontSize or 12
    text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

    UpdateLayout()
end

-- Dragging
frame:SetScript("OnDragStart", function(self)
    if MonkStaggerBarPrimeDB and not MonkStaggerBarPrimeDB.locked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if MonkStaggerBarPrimeDB then
        local _, _, _, x, y = self:GetPoint()
        MonkStaggerBarPrimeDB.posX = math.floor(x + 0.5)
        MonkStaggerBarPrimeDB.posY = math.floor(y + 0.5)
    end
end)

-- Helpers
local function FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(math.floor(num))
end

local function IsBrewmaster()
    local _, class = UnitClass("player")
    if class ~= "MONK" then return false end
    local spec = GetSpecialization()
    return spec == 1
end

-- Update bar
function UpdateBar()
    if not IsBrewmaster() then
        frame:Hide()
        return
    end

    local db = MonkStaggerBarPrimeDB
    local stagger
        if testMode then
            stagger = testStaggerValue or 0
        else
            stagger = UnitStagger("player") or 0
        end
    local maxHP = UnitHealthMax("player") or 1
    local pct = stagger / maxHP
    local baseStagger = math.min(stagger, maxHP)
    local overload = math.max(stagger - maxHP, 0)
    local overloadPct = overload / maxHP

    if db.hideOOC and not inCombat then
        frame:Hide()
        return
    end

    if db.hideZeroStagger and stagger == 0 then
        frame:Hide()
        return
    end

    frame:Show()

    -- Alert sound logic (only once when crossing above threshold, only in combat)
    do
        local enabled = db.alertEnabled
        local thresholdPct = (tonumber(db.alertThreshold) or 40) / 100
        thresholdPct = Clamp(thresholdPct, 0, MSBP_SOUND_THRESHOLD_MAX / 100)

        local now = GetTime()
        local above = enabled and (stagger > 0) and (pct >= thresholdPct)

        if not inCombat and not testMode then
            above = false
        end

        local cooldown = 2.0
        if above and (not wasAboveAlert) and (now - lastAlertTime >= cooldown) then
            MSB_TryPlaySelectedSound()
            lastAlertTime = now
        end

        wasAboveAlert = above
    end

    bar:SetValue(baseStagger / maxHP)

    local color = colorNone
    local currentIcon = iconNone

    if pct >= 0.6 then
        color = colorHeavy
        currentIcon = iconHeavy
    elseif pct >= 0.3 then
        color = colorModerate
        currentIcon = iconModerate
    elseif pct > 0 then
        color = colorLight
        currentIcon = iconLight
    end

    if pct > 1 then
        overflowBar:SetValue(math.min(overloadPct, 1))
        overflowBar:SetStatusBarColor(1, 1, 1, 0.4)
        overflowBar:Show()
        if db.textMode == 2 then
            text:SetText(string.format("%.0f%%", pct * 100))
        else
            text:SetText(string.format("%s + %s / %.0f%%", FormatNumber(maxHP), FormatNumber(overload), pct * 100))
        end
    else
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
        overflowBar:SetValue(0)
        overflowBar:Hide()
        if db.textMode == 2 then
            text:SetText(string.format("%.0f%%", pct * 100))
        else
            text:SetText(string.format("%s / %.0f%%", FormatNumber(stagger), pct * 100))
        end
    end

    if db.flashEnabled and (pct * 100) >= (db.flashThreshold or 100) then
        StartFlashBorder()
    else
        StopFlashBorder()
    end

    icon:SetTexture(currentIcon)
    iconFrame:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end

-- ============================================================================
-- UI Helpers
-- ============================================================================
local function CreateButton(parent, label, x, y, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, h)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function CreateEditBox(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    return eb
end

local function CreateLabel(parent, txt, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(txt)
    return fs
end

local function CreateCheckbox(parent, label, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local cbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText(label)
    cb:SetScript("OnClick", onClick)
    return cb
end

-- ============================================================================
-- Custom Scroll Dropdown (replaces UIDropDownMenu)
-- ============================================================================
local dropdownCatcher = nil

local function EnsureDropdownCatcher()
    if dropdownCatcher then return end
    dropdownCatcher = CreateFrame("Frame", nil, UIParent)
    dropdownCatcher:SetAllPoints(UIParent)
    dropdownCatcher:EnableMouse(true)
    dropdownCatcher:SetFrameStrata("DIALOG")
    dropdownCatcher:Hide()
end

-- Creates a dropdown that can scroll (hard maxVisible rows)
-- items: array { {name=..., path=...}, ... }
-- getIndex(): returns selectedIndex
-- setIndex(i): sets selectedIndex
local function CreateScrollDropdown(parent, x, y, width, maxVisible, items, getIndex, setIndex)
    EnsureDropdownCatcher()

    local dd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dd:SetSize(width, 22)
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    dd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dd:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dd:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local textFS = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textFS:SetPoint("LEFT", dd, "LEFT", 6, 0)
    textFS:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
    textFS:SetJustifyH("LEFT")
    textFS:SetText("")

    local arrow = CreateFrame("Button", nil, dd, "UIPanelButtonTemplate")
    arrow:SetSize(18, 18)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -2, 0)
    arrow:SetText("v")

    -- Popup
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    popup:EnableMouse(true)
    popup:Hide()

    -- Hard max height
    local rowH = 18
    local visible = Clamp(maxVisible or 10, 4, 25)
    local maxH = (visible * rowH) + 6
    popup:SetSize(width, maxH)

    -- ScrollFrame
    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -24, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 30, 1)
    scroll:SetScrollChild(content)

    -- Create buttons
    local buttons = {}

    local function UpdateText()
        local idx = getIndex()
        idx = Clamp(idx or 1, 1, math.max(#items, 1))
        local item = items[idx]
        textFS:SetText(item and item.name or "None")
    end

    local function ClosePopup()
        popup:Hide()
        dropdownCatcher:Hide()
    end

    local function OpenPopup()
        if popup:IsShown() then
            ClosePopup()
            return
        end

        -- Position under the dropdown
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)

        -- Catch outside clicks
        dropdownCatcher:Show()
        dropdownCatcher:SetScript("OnMouseDown", function()
            ClosePopup()
        end)

        popup:Show()
    end

    local function RefreshButtons()
        -- Height based on item count
        content:SetHeight(#items * rowH)

        for i = 1, #items do
            if not buttons[i] then
                local b = CreateFrame("Button", nil, content, "BackdropTemplate")
                b:SetHeight(rowH)
                b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * rowH))
                b:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((i - 1) * rowH))
                b:EnableMouse(true)

                b:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                })
                b:SetBackdropColor(0, 0, 0, 0)

                local dot = b:CreateTexture(nil, "OVERLAY")
                dot:SetSize(10, 10)
                dot:SetPoint("LEFT", b, "LEFT", 6, 0)
                dot:SetTexture("Interface\\Buttons\\UI-RadioButton")
                dot:SetTexCoord(0, 0.25, 0, 0.25)

                local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", b, "LEFT", 20, 0)
                label:SetJustifyH("LEFT")

                b._dot = dot
                b._label = label

                b:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(1, 1, 1, 0.06)
                end)
                b:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0, 0, 0, 0)
                end)

                b:SetScript("OnClick", function()
                    setIndex(i)
                    UpdateText()

                    -- update radio dots
                    for j = 1, #items do
                        if buttons[j] then
                            local on = (j == getIndex())
                            if on then
                                buttons[j]._dot:SetTexCoord(0.25, 0.5, 0, 0.25) -- selected
                            else
                                buttons[j]._dot:SetTexCoord(0, 0.25, 0, 0.25) -- unselected
                            end
                        end
                    end

                    ClosePopup()
                end)

                buttons[i] = b
            end

            local b = buttons[i]
            b._label:SetText(items[i].name)

            local on = (i == getIndex())
            if on then
                b._dot:SetTexCoord(0.25, 0.5, 0, 0.25)
            else
                b._dot:SetTexCoord(0, 0.25, 0, 0.25)
            end

            b:Show()
        end

        -- Hide any extra buttons if list shrank
        for i = #items + 1, #buttons do
            if buttons[i] then buttons[i]:Hide() end
        end
    end

    -- Mouse wheel scrolling
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(_, delta)
        local cur = scroll:GetVerticalScroll()
        local step = rowH * 2
        local maxScroll = math.max(0, content:GetHeight() - (maxH - 10))
        local next = Clamp(cur - (delta * step), 0, maxScroll)
        scroll:SetVerticalScroll(next)
    end)

    dd:EnableMouse(true)
    dd:SetScript("OnMouseDown", OpenPopup)
    arrow:SetScript("OnClick", OpenPopup)

    dd.Update = function()
        UpdateText()
        RefreshButtons()
    end

    dd.Close = ClosePopup

    -- ESC close support
    table.insert(UISpecialFrames, popup:GetName() or "")

    -- If popup has no name, we still close via catcher click / selecting item.
    -- (UISpecialFrames requires a global name; optional.)

    -- Initialize
    dd.Update()

    return dd
end

-- ============================================================================
-- Events
-- ============================================================================
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        MonkStaggerBarPrimeDB = MonkStaggerBarPrimeDB or {}
        for k, v in pairs(defaults) do
            if MonkStaggerBarPrimeDB[k] == nil then
                MonkStaggerBarPrimeDB[k] = v
            end
        end

        if #addonSounds > 0 then
            MonkStaggerBarPrimeDB.alertSoundIndex = Clamp(tonumber(MonkStaggerBarPrimeDB.alertSoundIndex) or 1, 1, #addonSounds)
        else
            MonkStaggerBarPrimeDB.alertSoundIndex = 1
        end

        iconLight    = GetSpellIcon(STAGGER_LIGHT)
        iconModerate = GetSpellIcon(STAGGER_MODERATE)
        iconHeavy    = GetSpellIcon(STAGGER_HEAVY)

        ApplySettings()

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        UpdateBar()

    elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 == "player" then
        UpdateBar()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateBar()

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateBar()
    end
end)

-- OnUpdate
local elapsed = 0
frame:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed >= 0.05 then
        elapsed = 0
        if self:IsShown() then
            if IsPlayerInWorld() then
                UpdateBar()
            end
        end
    end
end)

-- ============================================================================
-- Test Functions
-- ============================================================================


function StartStaggerBarTest()
    testMode = true
    testStaggerValue = 0

    if MonkStaggerBarTestTicker then
        MonkStaggerBarTestTicker:Cancel()
        MonkStaggerBarTestTicker = nil
    end

    local maxHP = UnitHealthMax("player") or 1
    local step = maxHP * 0.05   -- 5% per tick

    MonkStaggerBarTestTicker = C_Timer.NewTicker(0.20, function()
        if not testMode then
            if MonkStaggerBarTestTicker then
                MonkStaggerBarTestTicker:Cancel()
                MonkStaggerBarTestTicker = nil
            end
            return
        end

        testStaggerValue = testStaggerValue + step

        if testStaggerValue > (maxHP * 2) then
            testStaggerValue = 0
        end

        UpdateBar()
    end)
end

function StopStaggerBarTest()
    testMode = false
    testStaggerValue = 0

    if MonkStaggerBarTestTicker then
        MonkStaggerBarTestTicker:Cancel()
        MonkStaggerBarTestTicker = nil
    end

    UpdateBar()
end

function ToggleStaggerBarTest()
    if testMode then
        StopStaggerBarTest()
    else
        StartStaggerBarTest()
    end
end



-- ============================================================================
-- Slash command
-- ============================================================================
SLASH_MONKSTAGGERBAR1 = "/msb"

SlashCmdList["MONKSTAGGERBAR"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""

    if cmd == "" then
        if not MonkStaggerBarPrimeOptions then
            local opt = CreateMonkStaggerOptionsWindow()
            opt:Show()
            return
        end

        if MonkStaggerBarPrimeOptions:IsShown() then
            MonkStaggerBarPrimeOptions:Hide()
        else
            MonkStaggerBarPrimeOptions:Show()
        end

    elseif cmd == "sound" then
        MSB_TryPlaySelectedSound()

    else
        print("|cff00ff00" .. title .. ":|r /msb to open options (or /msb sound to test)")
    end
end
--bljakk need change
print("|cff00ff00" .. title .. version .. "|r loaded - /msb for options")
