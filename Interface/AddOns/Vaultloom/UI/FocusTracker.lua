local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Tracker = {
    frame = nil,
    rows = {},
}
Addon.FocusTracker = Tracker

local FONT_OBJECTS = {
    normal = { title = "GameFontNormalSmall", label = "GameFontHighlightSmall", value = "GameFontNormalSmall" },
    compact = { title = "GameFontDisableSmall", label = "GameFontDisableSmall", value = "GameFontDisableSmall" },
    large = { title = "GameFontNormal", label = "GameFontHighlight", value = "GameFontNormal" },
}

local function applyFont(region, object)
    if region and type(region.SetFontObject) == "function" then region:SetFontObject(object) end
end

local function applyPosition(frame, settings)
    if frame.dragging then return end
    local point = type(settings.point) == "table" and settings.point or {}
    frame:ClearAllPoints()
    frame:SetPoint(
        point.point or "CENTER",
        UIParent,
        point.relativePoint or "CENTER",
        tonumber(point.x) or 360,
        tonumber(point.y) or 0
    )
end

local function savePosition(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    point = type(point) == "string" and point or "CENTER"
    relativePoint = type(relativePoint) == "string" and relativePoint or point
    x, y = tonumber(x) or 0, tonumber(y) or 0

    -- Moving can occasionally leave the frame anchored to a temporary region.
    -- Persist a UIParent-relative center in that case so the next refresh cannot
    -- snap the tracker back to an unrelated anchor.
    if relativeTo and relativeTo ~= UIParent
        and type(frame.GetCenter) == "function"
        and type(UIParent.GetCenter) == "function"
    then
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if centerX and centerY and parentX and parentY then
            point, relativePoint = "CENTER", "CENTER"
            x, y = centerX - parentX, centerY - parentY
        end
    end
    Addon.Focus:SetTrackerPosition(point, relativePoint, x, y)
end

function Tracker:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "VaultloomFocusTrackerFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(318, 84)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Widgets:ApplyPanelStyle(frame, "card")

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalSmall", "LEFT")
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetPoint("TOPRIGHT", -62, -8)
    frame.title:SetText(L.CUSTOM_TASKS_TRACKER_LABEL)
    frame.title:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)

    frame.summary = Widgets:CreateLabel(frame, "GameFontDisableSmall", "RIGHT")
    frame.summary:SetPoint("TOPRIGHT", -12, -14)
    frame.summary:SetWidth(54)

    frame.empty = Widgets:CreateLabel(frame, "GameFontDisableSmall", "LEFT")
    frame.empty:SetPoint("TOPLEFT", 14, -43)
    frame.empty:SetPoint("TOPRIGHT", -14, -43)
    frame.empty:SetWordWrap(true)
    frame.empty:SetText(L.CUSTOM_TASKS_TRACKER_EMPTY)

    frame:SetScript("OnDragStart", function(selfFrame)
        local settings = Addon.Focus and Addon.Focus:GetSettings()
        if not (settings and settings.locked) then
            selfFrame.dragging = true
            selfFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        if selfFrame.dragging and Addon.Focus then savePosition(selfFrame) end
        selfFrame.dragging = false
        if Addon.Focus then applyPosition(selfFrame, Addon.Focus:GetSettings()) end
    end)
    frame:Hide()
    self.frame = frame
    return frame
end

local function ensureRows(tracker, count)
    local frame = tracker:Create()
    while #tracker.rows < count do
        local row = StatusRows:Create(frame, #tracker.rows + 1, tracker.rows[#tracker.rows])
        if #tracker.rows == 0 then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -38)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -38)
        end
        if row.hitbox and type(row.hitbox.EnableMouse) == "function" then row.hitbox:EnableMouse(false) end
        tracker.rows[#tracker.rows + 1] = row
    end
end

function Tracker:Refresh(view, settings)
    local frame = self:Create()
    settings = settings or (Addon.Focus and Addon.Focus:GetSettings()) or {}
    if settings.shown ~= true then frame:Hide(); return end
    view = view or (Addon.Focus and Addon.Focus:GetCurrentView()) or { rows = {}, summary = {} }
    local sourceRows = type(view.rows) == "table" and view.rows or {}
    local rowCount = math.min(12, #sourceRows)
    ensureRows(self, rowCount)

    local styleKey = settings.styleKey or "frame"
    local fontKey = settings.fontKey or "normal"
    local fonts = FONT_OBJECTS[fontKey] or FONT_OBJECTS.normal
    local textOnly = styleKey == "text"
    local rowStep = textOnly and 22 or 50
    local rowHeight = textOnly and 22 or 42
    local top = 30

    frame.title:SetText(L.CUSTOM_TASKS_TRACKER_LABEL)
    frame.title:SetJustifyH("LEFT")
    applyFont(frame.title, fonts.title)
    frame.title:Show()
    frame.summary:SetShown(not textOnly)
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", 10, -32)
    frame.empty:SetPoint("TOPRIGHT", -10, -32)
    frame.empty:SetShown(rowCount == 0)
    frame.summary:SetText(view.summary and view.summary.text or "0/0")
    frame:SetBackdropColor(
        Theme.colors.panel[1],
        Theme.colors.panel[2],
        Theme.colors.panel[3],
        styleKey == "frame" and 0.96 or 0
    )
    frame:SetBackdropBorderColor(
        Theme.colors.goldDim[1],
        Theme.colors.goldDim[2],
        Theme.colors.goldDim[3],
        styleKey == "frame" and 1 or 0
    )

    for index, row in ipairs(self.rows) do
        local item = index <= rowCount and sourceRows[index] or nil
        StatusRows:Set(row, item and item.entry or nil)
        if item then
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(top + ((index - 1) * rowStep)))
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -(top + ((index - 1) * rowStep)))
            row:SetBackdropColor(0.025, 0.022, 0.020, styleKey == "rows" and 0.90 or styleKey == "frame" and 0.62 or 0)
            row:SetBackdropBorderColor(
                Theme.colors.goldDim[1],
                Theme.colors.goldDim[2],
                Theme.colors.goldDim[3],
                textOnly and 0 or 0.55
            )
            row.background:SetShown(not textOnly)
            row.statusLine:SetShown(not textOnly)
            row.badgeFrame:SetShown(not textOnly and item.entry.hideBadgeFrame ~= true and item.entry.hideStatusBadge ~= true)
            row.badge:SetShown(not textOnly and item.entry.hideStatusBadge ~= true)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", textOnly and 2 or 16, 0)
            row.label:SetPoint("RIGHT", textOnly and -86 or -132, 0)
            row.value:SetWidth(textOnly and 78 or 90)
            row.value:ClearAllPoints()
            row.value:SetPoint("RIGHT", textOnly and -2 or -44, 0)
            applyFont(row.label, fonts.label)
            applyFont(row.value, fonts.value)
        end
    end

    local height = rowCount == 0 and 60
        or top + (rowCount * rowStep) + (textOnly and 0 or 2)
    frame:SetHeight(height)
    frame:SetScale((tonumber(settings.scalePercent) or 100) / 100)
    frame:SetAlpha((tonumber(settings.opacityPercent) or 90) / 100)
    frame:EnableMouse(settings.locked ~= true)
    applyPosition(frame, settings)
    frame:Show()
end
