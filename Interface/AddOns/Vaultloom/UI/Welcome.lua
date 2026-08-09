local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local DISCORD_URL = "https://discord.gg/FAKtRYjcrH"
local CAMPAIGN_ID = "vaultloom-1.0-beta"

local Welcome = {
    campaignID = CAMPAIGN_ID,
    discordURL = DISCORD_URL,
    loginScheduled = false,
}

Addon.Welcome = Welcome

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function styleEditBox(editBox)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    editBox:SetBackdropColor(0.025, 0.022, 0.020, 0.98)
    editBox:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    editBox:SetTextInsets(10, 10, 0, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlight)
    editBox:SetTextColor(unpackColor(Theme.colors.cyan))
end

local function selectEditBoxText(editBox)
    editBox:SetText(DISCORD_URL)
    editBox:SetFocus()
    if type(editBox.HighlightText) == "function" then
        editBox:HighlightText()
    end
end

function Welcome:GetDiscordURL()
    return DISCORD_URL
end

function Welcome:CreateDiscordDialog()
    if self.discordDialog then return self.discordDialog end

    local frame = Widgets:CreatePanel(UIParent, "content")
    frame:SetSize(560, 162)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 20, -18)
    frame.title:SetText(L.DISCORD_COPY_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.close = Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -14, -13)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.text = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.text:SetPoint("TOPRIGHT", frame.close, "BOTTOMLEFT", -12, 0)
    frame.text:SetText(L.DISCORD_COPY_TEXT)
    frame.text:SetWordWrap(true)

    frame.editBox = CreateFrame("EditBox", nil, frame, BACKDROP_TEMPLATE)
    frame.editBox:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -14)
    frame.editBox:SetPoint("RIGHT", -20, 0)
    frame.editBox:SetHeight(30)
    styleEditBox(frame.editBox)
    frame.editBox:SetText(DISCORD_URL)
    frame.editBox:SetScript("OnEscapePressed", function(selfEditBox)
        selfEditBox:ClearFocus()
        frame:Hide()
    end)
    frame.editBox:SetScript("OnEnterPressed", function(selfEditBox)
        selectEditBoxText(selfEditBox)
    end)
    frame.editBox:SetScript("OnEditFocusGained", function(selfEditBox)
        if type(selfEditBox.HighlightText) == "function" then selfEditBox:HighlightText() end
    end)

    frame.done = Widgets:CreateButton(frame, L.DISCORD_COPY_CLOSE, 120, 26)
    frame.done:SetPoint("BOTTOMRIGHT", -20, 14)
    frame.done:SetScript("OnClick", function() frame:Hide() end)

    frame:Hide()
    self.discordDialog = frame
    return frame
end

function Welcome:ShowDiscordLink()
    local frame = self:CreateDiscordDialog()
    frame:Show()
    frame:Raise()
    selectEditBoxText(frame.editBox)
    return true
end

function Welcome:CreateFrame()
    if self.frame then return self.frame end

    local frame = Widgets:CreatePanel(UIParent, "content")
    frame:SetSize(640, 270)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 24, -22)
    frame.title:SetPoint("TOPRIGHT", -190, -22)
    frame.title:SetText(L.WELCOME_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.badge = Widgets:CreateLabel(frame, "GameFontNormalSmall", "RIGHT")
    frame.badge:SetPoint("TOPRIGHT", -56, -25)
    frame.badge:SetText(L.WELCOME_BADGE)
    frame.badge:SetTextColor(unpackColor(Theme.colors.cyan))

    frame.close = Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -16, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetPoint("TOPLEFT", 24, -57)
    frame.divider:SetPoint("TOPRIGHT", -24, -57)
    frame.divider:SetHeight(1)
    frame.divider:SetColorTexture(
        Theme.colors.goldDim[1],
        Theme.colors.goldDim[2],
        Theme.colors.goldDim[3],
        0.80
    )

    frame.text = Widgets:CreateLabel(frame, "GameFontHighlight", "LEFT")
    frame.text:SetPoint("TOPLEFT", 28, -82)
    frame.text:SetPoint("TOPRIGHT", -28, -82)
    frame.text:SetHeight(76)
    frame.text:SetJustifyV("TOP")
    frame.text:SetWordWrap(true)
    frame.text:SetText(L.WELCOME_TEXT)

    frame.discordURL = Widgets:CreateLabel(frame, "GameFontNormal", "CENTER")
    frame.discordURL:SetPoint("TOPLEFT", 28, -166)
    frame.discordURL:SetPoint("TOPRIGHT", -28, -166)
    frame.discordURL:SetText(DISCORD_URL)
    frame.discordURL:SetTextColor(unpackColor(Theme.colors.cyan))

    frame.open = Widgets:CreateButton(frame, L.WELCOME_OPEN, 178, 30)
    frame.open:SetPoint("BOTTOMLEFT", 24, 20)
    frame.open:SetScript("OnClick", function()
        frame:Hide()
        if not Addon.UI then return end
        if not Addon:IsMainWindowShown() then
            Addon.UI:Toggle()
        else
            Addon.UI:ShowScreen("vault")
            if Addon.UI.frame then Addon.UI.frame:Raise() end
        end
    end)

    frame.discord = Widgets:CreateButton(frame, L.WELCOME_DISCORD, 218, 30)
    frame.discord:SetPoint("LEFT", frame.open, "RIGHT", 10, 0)
    frame.discord:SetScript("OnClick", function()
        Welcome:ShowDiscordLink()
    end)

    frame.later = Widgets:CreateButton(frame, L.WELCOME_LATER, 146, 30)
    frame.later:SetPoint("BOTTOMRIGHT", -24, 20)
    frame.later:SetScript("OnClick", function() frame:Hide() end)

    frame:Hide()
    self.frame = frame
    return frame
end

function Welcome:ShouldShow()
    local ui = Addon.Database:GetUI()
    return type(ui) == "table" and ui.welcomeSeenRelease ~= CAMPAIGN_ID
end

function Welcome:Show()
    if not self:ShouldShow() then return false end
    local frame = self:CreateFrame()
    Addon.Database:GetUI().welcomeSeenRelease = CAMPAIGN_ID
    frame:Show()
    frame:Raise()
    return true
end

function Welcome:TryShow()
    if not self:ShouldShow() then return false end
    if Addon.CombatQueue then
        return Addon.CombatQueue:RunOrQueue("welcome.banner", function()
            Welcome:Show()
        end)
    end
    return self:Show()
end

function Welcome:OnLogin()
    if self.loginScheduled or not self:ShouldShow() then return false end
    self.loginScheduled = true
    local callback = function()
        Welcome.loginScheduled = false
        Welcome:TryShow()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(1.25, callback)
    else
        callback()
    end
    return true
end
