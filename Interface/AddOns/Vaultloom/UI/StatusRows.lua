local _, Addon = ...

local Theme = Addon.Theme
local Assets = Addon.Assets
local Widgets = Addon.Widgets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local StatusRows = {}
Addon.StatusRows = StatusRows

local STATUS_BADGE_SIZE = 22
local CUSTOM_ICON_SIZE = STATUS_BADGE_SIZE - 14

local STATUS = {
    complete = { color = { 0.34, 0.88, 0.48, 1 }, texture = function() return Assets.statusBadgeComplete end },
    turnin = { color = { 0.98, 0.76, 0.22, 1 }, texture = function() return Assets.statusBadgeTurnIn end },
    open = { color = Theme.colors.gold, texture = function() return Assets.statusBadgeOpen end },
    missing = { color = { 0.62, 0.59, 0.54, 1 }, texture = function() return Assets.statusBadgeMissing end },
    locked = { color = { 0.42, 0.40, 0.38, 1 }, texture = function() return Assets.statusBadgeLocked end },
    failed = { color = { 0.92, 0.30, 0.24, 1 }, texture = function() return Assets.statusBadgeFailed end },
    repeatable = { color = Theme.colors.cyan, texture = function() return Assets.statusBadgeRepeatable end },
    warning = { color = { 0.92, 0.56, 0.16, 1 }, texture = function() return Assets.statusBadgeWarning end },
    unknown = { color = { 0.62, 0.59, 0.54, 1 }, texture = function() return Assets.statusBadgeOpen end },
    pending = { color = { 0.76, 0.62, 0.34, 1 }, texture = function() return Assets.statusBadgePending end },
}

function StatusRows:Create(parent, index, previous)
    local row = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    row:SetHeight(42)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Assets.roundedColorBorder,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.025, 0.022, 0.020, 0.88)
    row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
    elseif parent.summary then
        row:SetPoint("TOPLEFT", parent.summary, "BOTTOMLEFT", 0, -16)
        row:SetPoint("TOPRIGHT", -16, 0)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
        row:SetPoint("TOPRIGHT", -16, 0)
    end

    -- Match Compendium rows: keep the decorative plate below the backdrop
    -- edge so it cannot cover the rounded side and corner pixels.
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.background:SetTexture(Assets.row)
    row.statusLine = row:CreateTexture(nil, "ARTWORK")
    row.statusLine:SetPoint("TOPLEFT", 4, -6)
    row.statusLine:SetPoint("BOTTOMLEFT", 4, 6)
    row.statusLine:SetWidth(3)
    row.statusLineMask = Widgets:AddRoundedStatusLineMask(row, row.statusLine)
    row.label = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.label:SetPoint("LEFT", 16, 0)
    row.label:SetPoint("RIGHT", -132, 0)
    row.badgeFrame = row:CreateTexture(nil, "ARTWORK")
    row.badgeFrame:SetSize(STATUS_BADGE_SIZE, STATUS_BADGE_SIZE)
    row.badgeFrame:SetPoint("RIGHT", -10, 0)
    row.badgeFrame:SetTexture(Assets.statusBadgeFrame)
    row.badgeFrame:Hide()
    row.badge = row:CreateTexture(nil, "OVERLAY")
    row.badge:SetSize(STATUS_BADGE_SIZE, STATUS_BADGE_SIZE)
    row.badge:SetPoint("CENTER", row.badgeFrame, "CENTER", 0, 0)
    row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.value:SetPoint("RIGHT", row.badgeFrame, "LEFT", -8, 0)
    row.value:SetWidth(90)
    row.hitbox = CreateFrame("Button", nil, row)
    row.hitbox:SetAllPoints(row)
    row.hitbox:RegisterForClicks("LeftButtonUp")
    row.hitbox:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" or not row.questID or not Addon.QuestApi then
            return
        end
        if Addon.QuestApi:OpenQuest(row.questID) and GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row.hitbox:SetScript("OnEnter", function()
        row:SetBackdropBorderColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 0.85)
        if row.tooltipTitle and GameTooltip then
            GameTooltip:SetOwner(row.hitbox, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(row.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
            for _, line in ipairs(row.tooltipLines or {}) do
                GameTooltip:AddLine(line, 0.92, 0.92, 0.92, true)
            end
            GameTooltip:Show()
        end
    end)
    row.hitbox:SetScript("OnLeave", function()
        row:SetBackdropBorderColor(Theme.colors.goldDim[1], Theme.colors.goldDim[2], Theme.colors.goldDim[3], 0.55)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row.index = index
    return row
end

function StatusRows:Set(row, entry)
    if not entry then
        row.tooltipTitle = nil
        row.tooltipLines = nil
        row.questID = nil
        row:Hide()
        return
    end
    local visual = STATUS[entry.status] or STATUS.missing
    row.label:SetText(entry.label or "")
    row.value:SetText(entry.text or "")
    row.value:SetTextColor(visual.color[1], visual.color[2], visual.color[3], 1)
    row.statusLine:SetColorTexture(visual.color[1], visual.color[2], visual.color[3], 0.95)
    local hidden = entry.hideStatusBadge == true
    row.badge:ClearAllPoints()
    row.badge:SetPoint("CENTER", row.badgeFrame, "CENTER", 0, 0)
    local fullBadgeTexture = entry.badgeFullTexture
    local customIconTexture = not fullBadgeTexture and entry.badgeTexture or nil
    row.badgeUsesFrame = customIconTexture ~= nil and entry.hideBadgeFrame ~= true and not hidden
    row.badgeFrame:SetShown(row.badgeUsesFrame)
    row.badge:SetSize(
        fullBadgeTexture and 28 or row.badgeUsesFrame and CUSTOM_ICON_SIZE or STATUS_BADGE_SIZE,
        fullBadgeTexture and 28 or row.badgeUsesFrame and CUSTOM_ICON_SIZE or STATUS_BADGE_SIZE
    )
    row.badge:SetTexture(fullBadgeTexture or customIconTexture or visual.texture())
    local texCoord = entry.badgeTexCoord
    if not texCoord and customIconTexture then texCoord = { 0.08, 0.92, 0.08, 0.92 } end
    if type(texCoord) == "table" then
        row.badge:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
    else
        row.badge:SetTexCoord(0, 1, 0, 1)
    end
    row.badge:SetShown(not hidden)
    row.tooltipTitle = entry.tooltipTitle or entry.label
    row.tooltipLines = entry.tooltipLines
    row.questID = tonumber(entry.questID)
    row:Show()
end
