local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Assets = Addon.Assets
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MASK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local RewardBadge = {}
Addon.VaultRewardBadge = RewardBadge

local function unpackColor(color, alpha)
    return color[1], color[2], color[3], alpha or color[4] or 1
end

local function decorateIcon(frame)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetPoint("TOPLEFT", 1.5, -1.5)
    frame.background:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    frame.background:SetTexture(WHITE_TEXTURE)
    frame.background:SetVertexColor(0.035, 0.03, 0.02, 0.98)

    if type(frame.CreateMaskTexture) == "function"
        and type(frame.background.AddMaskTexture) == "function"
    then
        frame.backgroundMask = frame:CreateMaskTexture(nil, "ARTWORK")
        frame.backgroundMask:SetTexture(
            MASK_TEXTURE,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        frame.backgroundMask:SetAllPoints(frame.background)
        frame.background:AddMaskTexture(frame.backgroundMask)
    end

    frame.icon = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.icon:SetPoint("TOPLEFT", 1.5, -1.5)
    frame.icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    frame.icon:SetTexture(Assets.vaultRewardIcon)
    frame.icon:SetTexCoord(0, 1, 0, 1)

    if type(frame.CreateMaskTexture) == "function"
        and type(frame.icon.AddMaskTexture) == "function"
    then
        frame.iconMask = frame:CreateMaskTexture(nil, "ARTWORK")
        frame.iconMask:SetTexture(
            MASK_TEXTURE,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        frame.iconMask:SetAllPoints(frame.icon)
        frame.icon:AddMaskTexture(frame.iconMask)
    end

    frame.ring = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.ring:SetAllPoints(frame)
    frame.ring:SetTexture(Assets.vaultRewardRing)
    frame.ring:SetVertexColor(unpackColor(Theme.colors.gold, 1))
end

local function showReminderTooltip(owner, reminder)
    if not GameTooltip or type(reminder) ~= "table" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.VAULT_REWARD_TOOLTIP, unpackColor(Theme.colors.gold))
    GameTooltip:Show()
end

function RewardBadge:Create(parent, size)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(size or 16, size or 16)
    badge:EnableMouse(true)
    if type(parent.GetFrameLevel) == "function" then
        badge:SetFrameLevel(parent:GetFrameLevel() + 6)
    end
    decorateIcon(badge)
    badge:SetScript("OnEnter", function(selfBadge)
        showReminderTooltip(selfBadge, selfBadge.reminder)
    end)
    badge:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    badge:Hide()
    return badge
end

function RewardBadge:SetCharacter(badge, characterKey)
    if not badge then return false end
    local reminder = Addon.VaultProgress
        and Addon.VaultProgress:GetRewardReminder(characterKey) or nil
    badge.reminder = reminder
    badge:SetShown(reminder ~= nil)
    return reminder ~= nil
end

function RewardBadge:CreateSummary(parent, onClick)
    local summary = CreateFrame("Button", nil, parent)
    summary:SetSize(42, 22)
    summary.iconFrame = CreateFrame("Frame", nil, summary)
    summary.iconFrame:SetSize(17, 17)
    summary.iconFrame:SetPoint("LEFT", 0, 0)
    summary.iconFrame:EnableMouse(false)
    decorateIcon(summary.iconFrame)
    summary.count = summary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary.count:SetPoint("LEFT", summary.iconFrame, "RIGHT", 4, 0)
    summary.count:SetTextColor(unpackColor(Theme.colors.gold))
    summary:SetScript("OnEnter", function(selfSummary)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfSummary, "ANCHOR_RIGHT")
        local count = math.max(0, tonumber(selfSummary.rewardCount) or 0)
        local text = count == 1 and L.VAULT_REWARD_CHARACTER_ONE
            or string.format(L.VAULT_REWARD_CHARACTER_COUNT, count)
        GameTooltip:AddLine(text, unpackColor(Theme.colors.gold))
        GameTooltip:Show()
    end)
    summary:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    if type(onClick) == "function" then summary:SetScript("OnClick", onClick) end
    return summary
end

function RewardBadge:SetSummaryCount(summary, count, hideWhenEmpty)
    if not summary then return 0 end
    count = math.max(0, math.floor(tonumber(count) or 0))
    summary.rewardCount = count
    summary.count:SetText(tostring(count))
    summary:SetAlpha(count > 0 and 1 or 0.44)
    summary:SetShown(not hideWhenEmpty or count > 0)
    return count
end
