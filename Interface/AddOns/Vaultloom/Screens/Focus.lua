local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local StatusRows = Addon.StatusRows
local Assets = Addon.Assets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ScrollFrames = Addon.ScrollFrames

local function syncScrollWidth(scroll, child)
    local width = tonumber(scroll and scroll.GetWidth and scroll:GetWidth()) or 0
    if width > 20 then
        child:SetWidth(math.max(10, width - 2))
    elseif (tonumber(child and child.GetWidth and child:GetWidth()) or 0) < 20 then
        child:SetWidth(scroll.fallbackChildWidth)
    end
end

local function createScroll(parent, topAnchor, fallbackWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    scroll:EnableMouseWheel(true)
    scroll.fallbackChildWidth = fallbackWidth
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(fallbackWidth, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, width)
        if (tonumber(width) or 0) > 20 then child:SetWidth(math.max(10, width - 2))
        else syncScrollWidth(self, child) end
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = tonumber(self:GetVerticalScroll()) or 0
        local maximum = tonumber(self:GetVerticalScrollRange()) or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - (delta * 34))))
    end)
    ScrollFrames:Style(scroll)
    return scroll, child
end

local function setTooltip(button, title, body)
    button.tooltipTitle = title
    button.tooltipBody = body
    local previousEnter = button:GetScript("OnEnter")
    local previousLeave = button:GetScript("OnLeave")
    button:SetScript("OnEnter", function(self)
        if previousEnter then previousEnter(self) end
        if not GameTooltip or not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(self.tooltipTitle, Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], true)
        if self.tooltipBody then GameTooltip:AddLine(self.tooltipBody, 0.92, 0.92, 0.92, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if previousLeave then previousLeave(self) end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function createMoveButton(parent, texture, tooltipTitle, tooltipBody)
    local button = Widgets:CreateButton(parent, "", 28, 26)
    button.label:Hide()
    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetSize(12, 12)
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetTexture(texture)
    button.icon:SetVertexColor(1, 1, 1, 0.96)
    button:EnableMouse(true)
    setTooltip(button, tooltipTitle, tooltipBody)
    return button
end

local function createTaskRow(parent, previous)
    local row = StatusRows:Create(parent, previous and previous.index + 1 or 1, previous)
    row:ClearAllPoints()
    if previous then
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 16, 0)
    row.label:SetPoint("RIGHT", -312, 0)
    row.badgeFrame:Hide()
    row.badge:Hide()
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -174, 0)
    row.value:SetWidth(108)

    row.hitbox:ClearAllPoints()
    row.hitbox:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.hitbox:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -174, 0)

    row.up = createMoveButton(row, Assets.scrollArrowUp, L.CUSTOM_TASKS_MOVE_UP, L.CUSTOM_TASKS_MOVE_UP_TOOLTIP)
    row.up:SetPoint("RIGHT", -138, 0)
    row.down = createMoveButton(row, Assets.scrollArrowDown, L.CUSTOM_TASKS_MOVE_DOWN, L.CUSTOM_TASKS_MOVE_DOWN_TOOLTIP)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
    row.remove = Widgets:CreateButton(row, L.CUSTOM_TASKS_REMOVE, 98, 26)
    row.remove:SetPoint("RIGHT", -8, 0)
    local controlLevel = row.hitbox:GetFrameLevel() + 1
    row.up:SetFrameLevel(controlLevel)
    row.down:SetFrameLevel(controlLevel)
    row.remove:SetFrameLevel(controlLevel)
    return row
end

local function createScreen(_, host)
    local service = Addon.Focus
    local frame = CreateFrame("Frame", nil, host)
    frame:SetAllPoints(host)
    frame.layoutVersion = "focus-questboard-2"
    frame.taskRows = {}
    frame.menuButtons = {}
    frame.menuHeaders = {}

    frame.navigation = Widgets:CreateButton(frame, L.CUSTOM_TASKS_QUESTBOARD_TITLE, 188, 24, "tab")
    frame.navigation:SetPoint("TOPLEFT", 0, 0)
    Widgets:SetButtonActive(frame.navigation, true)
    frame.subTabButtons = { questboard = frame.navigation }

    frame.content = Widgets:CreatePanel(frame, "card")
    frame.content:SetPoint("TOPLEFT", frame.navigation, "BOTTOMLEFT", 0, -10)
    frame.content:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.title = Widgets:CreateLabel(frame.content, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 16, -14)
    frame.title:SetPoint("TOPRIGHT", -170, -14)
    frame.title:SetText(L.CUSTOM_TASKS_QUESTBOARD_TITLE)
    frame.title:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)

    frame.subtitle = Widgets:CreateLabel(frame.content, "GameFontDisableSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.subtitle:SetPoint("TOPRIGHT", -170, 0)
    frame.subtitle:SetText(L.CUSTOM_TASKS_SUBTITLE)

    frame.summary = Widgets:CreateLabel(frame.content, "GameFontNormalSmall", "LEFT")
    frame.summary:SetPoint("TOPLEFT", 16, -62)
    frame.summary:SetWidth(140)

    frame.addButton = Widgets:CreateButton(frame.content, L.CUSTOM_TASKS_ADD_MENU, 142, 28)
    frame.addButton:SetPoint("TOPRIGHT", -16, -14)
    setTooltip(frame.addButton, L.CUSTOM_TASKS_ADD_MENU, L.CUSTOM_TASKS_TOOLTIP_ADD_MENU)

    frame.profileLabel = Widgets:CreateLabel(frame.content, "GameFontDisableSmall", "LEFT")
    frame.profileLabel:SetPoint("TOPLEFT", 164, -58)
    frame.profileLabel:SetSize(40, 28)
    frame.profileLabel:SetText(L.CUSTOM_TASKS_PROFILE_LABEL)

    frame.characterButton = Widgets:CreateButton(frame.content, L.CUSTOM_TASKS_PROFILE_CHARACTER, 112, 28)
    frame.characterButton:SetPoint("LEFT", frame.profileLabel, "RIGHT", 3, 0)
    setTooltip(frame.characterButton, L.CUSTOM_TASKS_PROFILE_CHARACTER, L.CUSTOM_TASKS_TOOLTIP_CHARACTER_MODE)
    frame.globalButton = Widgets:CreateButton(frame.content, L.CUSTOM_TASKS_PROFILE_GLOBAL, 118, 28)
    frame.globalButton:SetPoint("LEFT", frame.characterButton, "RIGHT", 3, 0)
    setTooltip(frame.globalButton, L.CUSTOM_TASKS_PROFILE_GLOBAL, L.CUSTOM_TASKS_TOOLTIP_GLOBAL_MODE)
    frame.copyButton = Widgets:CreateButton(frame.content, L.CUSTOM_TASKS_COPY_GLOBAL, 104, 28)
    frame.copyButton:SetPoint("LEFT", frame.globalButton, "RIGHT", 3, 0)
    setTooltip(frame.copyButton, L.CUSTOM_TASKS_COPY_GLOBAL, L.CUSTOM_TASKS_TOOLTIP_COPY_GLOBAL)
    frame.saveButton = Widgets:CreateButton(frame.content, L.CUSTOM_TASKS_SAVE_GLOBAL, 126, 28)
    frame.saveButton:SetPoint("LEFT", frame.copyButton, "RIGHT", 3, 0)
    setTooltip(frame.saveButton, L.CUSTOM_TASKS_SAVE_GLOBAL, L.CUSTOM_TASKS_TOOLTIP_SAVE_GLOBAL)

    frame.trackerLabel = Widgets:CreateLabel(frame.content, "GameFontDisableSmall", "LEFT")
    frame.trackerLabel:SetPoint("TOPLEFT", 16, -94)
    frame.trackerLabel:SetSize(56, 26)
    frame.trackerLabel:SetText(L.CUSTOM_TASKS_TRACKER_LABEL)
    frame.trackerButton = Widgets:CreateButton(frame.content, "", 112, 26)
    frame.trackerButton:SetPoint("LEFT", frame.trackerLabel, "RIGHT", 3, 0)
    setTooltip(frame.trackerButton, L.CUSTOM_TASKS_TRACKER_LABEL, L.CUSTOM_TASKS_TOOLTIP_TRACKER_TOGGLE)
    frame.lockButton = Widgets:CreateButton(frame.content, "", 70, 26)
    frame.lockButton:SetPoint("LEFT", frame.trackerButton, "RIGHT", 3, 0)
    setTooltip(frame.lockButton, L.CUSTOM_TASKS_TRACKER_LOCK, L.CUSTOM_TASKS_TOOLTIP_TRACKER_LOCK)
    frame.styleButton = Widgets:CreateButton(frame.content, "", 112, 26)
    frame.styleButton:SetPoint("LEFT", frame.lockButton, "RIGHT", 3, 0)
    setTooltip(frame.styleButton, L.CUSTOM_TASKS_TRACKER_STYLE_FRAME, L.CUSTOM_TASKS_TOOLTIP_TRACKER_STYLE)
    frame.fontButton = Widgets:CreateButton(frame.content, "", 76, 26)
    frame.fontButton:SetPoint("LEFT", frame.styleButton, "RIGHT", 3, 0)
    setTooltip(frame.fontButton, L.CUSTOM_TASKS_TRACKER_FONT_NORMAL, L.CUSTOM_TASKS_TOOLTIP_TRACKER_FONT)

    frame.scaleDown = Widgets:CreateButton(frame.content, "-", 26, 26)
    frame.scaleDown:SetPoint("LEFT", frame.fontButton, "RIGHT", 3, 0)
    setTooltip(frame.scaleDown, L.CUSTOM_TASKS_TOOLTIP_SCALE_DOWN, L.CUSTOM_TASKS_TOOLTIP_SCALE_DOWN_TEXT)
    frame.scaleValue = Widgets:CreateLabel(frame.content, "GameFontNormalSmall", "CENTER")
    frame.scaleValue:SetPoint("LEFT", frame.scaleDown, "RIGHT", 2, 0)
    frame.scaleValue:SetSize(40, 26)
    frame.scaleUp = Widgets:CreateButton(frame.content, "+", 26, 26)
    frame.scaleUp:SetPoint("LEFT", frame.scaleValue, "RIGHT", 2, 0)
    setTooltip(frame.scaleUp, L.CUSTOM_TASKS_TOOLTIP_SCALE_UP, L.CUSTOM_TASKS_TOOLTIP_SCALE_UP_TEXT)
    frame.opacityDown = Widgets:CreateButton(frame.content, "<", 26, 26)
    frame.opacityDown:SetPoint("LEFT", frame.scaleUp, "RIGHT", 5, 0)
    setTooltip(frame.opacityDown, L.CUSTOM_TASKS_TOOLTIP_OPACITY_DOWN, L.CUSTOM_TASKS_TOOLTIP_OPACITY_DOWN_TEXT)
    frame.opacityValue = Widgets:CreateLabel(frame.content, "GameFontNormalSmall", "CENTER")
    frame.opacityValue:SetPoint("LEFT", frame.opacityDown, "RIGHT", 2, 0)
    frame.opacityValue:SetSize(40, 26)
    frame.opacityUp = Widgets:CreateButton(frame.content, ">", 26, 26)
    frame.opacityUp:SetPoint("LEFT", frame.opacityValue, "RIGHT", 2, 0)
    setTooltip(frame.opacityUp, L.CUSTOM_TASKS_TOOLTIP_OPACITY_UP, L.CUSTOM_TASKS_TOOLTIP_OPACITY_UP_TEXT)

    frame.listAnchor = CreateFrame("Frame", nil, frame.content)
    frame.listAnchor:SetPoint("TOPLEFT", 16, -126)
    frame.listAnchor:SetPoint("TOPRIGHT", -16, -126)
    frame.listAnchor:SetHeight(1)
    frame.tasksScroll, frame.tasksChild = createScroll(frame.content, frame.listAnchor, 720)

    frame.empty = Widgets:CreateLabel(frame.tasksChild, "GameFontDisableSmall", "LEFT")
    frame.empty:SetPoint("TOPLEFT", 2, -4)
    frame.empty:SetPoint("TOPRIGHT", -2, -4)
    frame.empty:SetWordWrap(true)
    frame.empty:SetText(L.CUSTOM_TASKS_EMPTY)

    frame.menu = Widgets:CreatePanel(frame.content, "cardInset")
    frame.menu:SetSize(344, 394)
    frame.menu:SetPoint("TOPRIGHT", frame.addButton, "BOTTOMRIGHT", 0, -5)
    frame.menu:SetFrameLevel(frame.content:GetFrameLevel() + 20)
    frame.menuTitle = Widgets:CreateLabel(frame.menu, "GameFontNormal", "LEFT")
    frame.menuTitle:SetPoint("TOPLEFT", 12, -10)
    frame.menuTitle:SetPoint("TOPRIGHT", -12, -10)
    frame.menuTitle:SetText(L.CUSTOM_TASKS_ADD_MENU)
    frame.menuScroll, frame.menuChild = createScroll(frame.menu, frame.menuTitle, 292)
    frame.menu:Hide()

    local function selectedKey()
        local character = Addon.WarbandRoster:GetSelected()
        return character and character.key
    end

    local function ensureTaskRows(count)
        while #frame.taskRows < count do
            frame.taskRows[#frame.taskRows + 1] = createTaskRow(frame.tasksChild, frame.taskRows[#frame.taskRows])
        end
    end

    function frame:RefreshMenu(catalog, characterKey)
        local y = 0
        local visibleButtons, visibleHeaders = {}, {}
        for _, group in ipairs(type(catalog.groups) == "table" and catalog.groups or {}) do
            local header = self.menuHeaders[group.key]
            if not header then
                header = Widgets:CreateLabel(self.menuChild, "GameFontNormalSmall", "LEFT")
                header:SetTextColor(Theme.colors.gold[1], Theme.colors.gold[2], Theme.colors.gold[3], 1)
                self.menuHeaders[group.key] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 4, y)
            header:SetPoint("TOPRIGHT", -4, y)
            header:SetHeight(20)
            header:SetText(group.label)
            header:Show()
            visibleHeaders[group.key] = true
            y = y - 24
            for _, item in ipairs(group.items) do
                local button = self.menuButtons[item.id]
                if not button then
                    button = Widgets:CreateButton(self.menuChild, "", 284, 24, "row")
                    button.taskID = item.id
                    button.box = CreateFrame("Frame", nil, button, BACKDROP_TEMPLATE)
                    button.box:SetSize(16, 16)
                    button.box:SetPoint("LEFT", 7, 0)
                    button.box:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = 1,
                    })
                    button.box:SetBackdropColor(0.08, 0.07, 0.06, 0.92)
                    button.box:SetBackdropBorderColor(
                        Theme.colors.goldDim[1],
                        Theme.colors.goldDim[2],
                        Theme.colors.goldDim[3],
                        0.72
                    )
                    button.check = button.box:CreateTexture(nil, "ARTWORK")
                    button.check:SetSize(18, 18)
                    button.check:SetPoint("CENTER", 0, 0)
                    button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                    button.check:SetVertexColor(
                        Theme.colors.gold[1],
                        Theme.colors.gold[2],
                        Theme.colors.gold[3],
                        1
                    )
                    button.label:ClearAllPoints()
                    button.label:SetPoint("LEFT", button.box, "RIGHT", 8, 0)
                    button.label:SetPoint("RIGHT", -8, 0)
                    button.label:SetWordWrap(false)
                    button:SetScript("OnClick", function(selfButton)
                        local currentCatalog = service:GetCatalog(selectedKey())
                        service:SetSelected(
                            selfButton.taskID,
                            not service:IsSelected(selfButton.taskID, selectedKey()),
                            selectedKey(),
                            currentCatalog.index[selfButton.taskID]
                        )
                    end)
                    self.menuButtons[item.id] = button
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 4, y)
                button:SetPoint("TOPRIGHT", -4, y)
                local selected = service:IsSelected(item.id, characterKey)
                button.label:SetText(item.label)
                button.check:SetShown(selected)
                Widgets:SetButtonActive(button, selected)
                button:Show()
                visibleButtons[item.id] = true
                y = y - 28
            end
            y = y - 7
        end
        for key, header in pairs(self.menuHeaders) do header:SetShown(visibleHeaders[key] == true) end
        for taskID, button in pairs(self.menuButtons) do button:SetShown(visibleButtons[taskID] == true) end
        self.menuChild:SetHeight(math.max(10, -y + 4))
    end

    function frame:Refresh()
        local characterKey = selectedKey()
        local view = service:GetView(characterKey)
        local settings = service:GetSettings()
        self.summary:SetText(string.format(L.CUSTOM_TASKS_SUMMARY_FORMAT, view.summary.total, view.summary.text))
        Widgets:SetButtonActive(self.characterButton, not service:IsUsingGlobal(characterKey))
        Widgets:SetButtonActive(self.globalButton, service:IsUsingGlobal(characterKey))
        self.trackerButton.label:SetText(settings.shown and L.CUSTOM_TASKS_TRACKER_HIDE or L.CUSTOM_TASKS_TRACKER_SHOW)
        self.lockButton.label:SetText(settings.locked and L.CUSTOM_TASKS_TRACKER_UNLOCK or L.CUSTOM_TASKS_TRACKER_LOCK)
        local styleNames = {
            frame = L.CUSTOM_TASKS_TRACKER_STYLE_FRAME,
            rows = L.CUSTOM_TASKS_TRACKER_STYLE_ROWS,
            text = L.CUSTOM_TASKS_TRACKER_STYLE_TEXT,
        }
        self.styleButton.label:SetText(string.format(L.CUSTOM_TASKS_TRACKER_STYLE_FORMAT, styleNames[settings.styleKey]))
        local fontNames = {
            normal = L.CUSTOM_TASKS_TRACKER_FONT_NORMAL,
            compact = L.CUSTOM_TASKS_TRACKER_FONT_COMPACT,
            large = L.CUSTOM_TASKS_TRACKER_FONT_LARGE,
        }
        self.fontButton.label:SetText(fontNames[settings.fontKey])
        self.scaleValue:SetText(settings.scalePercent .. "%")
        self.opacityValue:SetText(settings.opacityPercent .. "%")

        ensureTaskRows(#view.rows)
        for index, row in ipairs(self.taskRows) do
            local item = view.rows[index]
            StatusRows:Set(row, item and item.entry or nil)
            if item then
                row.badgeFrame:Hide()
                row.badge:Hide()
                row.up.taskID, row.down.taskID, row.remove.taskID = item.id, item.id, item.id
                row.up:SetShown(index > 1)
                row.down:SetShown(index < #view.rows)
                row.remove:Show()
                row.up:SetScript("OnClick", function(selfButton) service:Move(selfButton.taskID, -1, selectedKey()) end)
                row.down:SetScript("OnClick", function(selfButton) service:Move(selfButton.taskID, 1, selectedKey()) end)
                row.remove:SetScript("OnClick", function(selfButton) service:SetSelected(selfButton.taskID, false, selectedKey()) end)
            end
        end
        self.tasksChild:SetHeight(math.max(10, (#view.rows * 50) - 8))
        self.empty:SetShown(#view.rows == 0)
        self:RefreshMenu(view.catalog, characterKey)
        syncScrollWidth(self.tasksScroll, self.tasksChild)
        syncScrollWidth(self.menuScroll, self.menuChild)
    end

    frame.navigation:SetScript("OnClick", function()
        Addon.Database:GetUI().selectedSubTabs.focus = "questboard"
    end)
    frame.addButton:SetScript("OnClick", function()
        frame.menu:SetShown(not frame.menu:IsShown())
        if frame.menu:IsShown() then frame:RefreshMenu(service:GetCatalog(selectedKey()), selectedKey()) end
    end)
    frame.characterButton:SetScript("OnClick", function() service:SetUseGlobal(selectedKey(), false) end)
    frame.globalButton:SetScript("OnClick", function() service:SetUseGlobal(selectedKey(), true) end)
    frame.copyButton:SetScript("OnClick", function() service:CopyGlobalToCharacter(selectedKey()) end)
    frame.saveButton:SetScript("OnClick", function() service:SaveCharacterAsGlobal(selectedKey()) end)
    frame.trackerButton:SetScript("OnClick", function() service:SetTrackerShown(not service:GetSettings().shown) end)
    frame.lockButton:SetScript("OnClick", function() service:SetTrackerLocked(not service:GetSettings().locked) end)
    frame.styleButton:SetScript("OnClick", function() service:CycleTrackerStyle() end)
    frame.fontButton:SetScript("OnClick", function() service:CycleTrackerFont() end)
    frame.scaleDown:SetScript("OnClick", function() service:SetTrackerScalePercent(service:GetSettings().scalePercent - 5) end)
    frame.scaleUp:SetScript("OnClick", function() service:SetTrackerScalePercent(service:GetSettings().scalePercent + 5) end)
    frame.opacityDown:SetScript("OnClick", function() service:SetTrackerOpacityPercent(service:GetSettings().opacityPercent - 5) end)
    frame.opacityUp:SetScript("OnClick", function() service:SetTrackerOpacityPercent(service:GetSettings().opacityPercent + 5) end)

    frame:SetScript("OnHide", function() frame.menu:Hide() end)
    frame:SetScript("OnShow", function()
        frame:Refresh()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if frame:IsShown() then
                    syncScrollWidth(frame.tasksScroll, frame.tasksChild)
                    syncScrollWidth(frame.menuScroll, frame.menuChild)
                end
            end)
        end
    end)
    Addon.StateStore:Subscribe("focus.tasks", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)
    Addon.StateStore:Subscribe("warband.selection", frame, function()
        frame.menu:Hide()
        if frame:IsShown() then frame:Refresh() end
    end)
    frame:Hide()
    return frame
end

Addon.ScreenRegistry:Register({
    id = "focus",
    order = 9,
    label = function() return L.SCREEN_FOCUS end,
    Create = createScreen,
})
