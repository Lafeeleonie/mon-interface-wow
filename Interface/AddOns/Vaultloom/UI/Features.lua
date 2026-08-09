local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Registry = Addon.FeatureRegistry
local Assets = Addon.Assets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Features = {}
Addon.FeaturesUI = Features

local STATUS_KEYS = {
    planned = "FEATURE_STATUS_PLANNED",
    disabled = "FEATURE_STATUS_DISABLED",
    enabled = "FEATURE_STATUS_ENABLED",
    pending = "FEATURE_STATUS_PENDING",
    error = "FEATURE_STATUS_ERROR",
}

local STATUS_COLORS = {
    planned = { 0.68, 0.58, 0.38, 1 },
    disabled = Theme.colors.muted,
    enabled = { 0.46, 0.88, 0.48, 1 },
    pending = Theme.colors.gold,
    error = { 1.00, 0.30, 0.24, 1 },
}

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function resolveText(value)
    return Registry:ResolveText(value)
end

local function setControlEnabled(control, enabled)
    if not control then return end
    control.vlEnabled = enabled == true
    if control.vlEnabled then
        if type(control.Enable) == "function" then control:Enable() end
        control:SetAlpha(1)
    else
        if type(control.Disable) == "function" then control:Disable() end
        control:SetAlpha(0.42)
    end
end

local function createCheckControl(parent, size)
    local control = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    control:SetSize(size or 22, size or 22)
    if type(control.SetBackdrop) == "function" then
        control:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        control:SetBackdropColor(0.035, 0.030, 0.026, 0.96)
        control:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    end

    control.mark = control:CreateTexture(nil, "OVERLAY")
    control.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    control.mark:SetPoint("CENTER", 0, 0)
    control.mark:SetSize((size or 22) + 4, (size or 22) + 4)
    control.mark:SetVertexColor(unpackColor(Theme.colors.gold))
    control.mark:Hide()

    control:SetScript("OnEnter", function(self)
        if type(self.SetBackdropBorderColor) == "function" and self.vlEnabled ~= false then
            self:SetBackdropBorderColor(unpackColor(Theme.colors.gold))
        end
    end)
    control:SetScript("OnLeave", function(self)
        if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(unpackColor(self.checked and Theme.colors.gold or Theme.colors.goldDim))
        end
        if GameTooltip then GameTooltip:Hide() end
    end)

    function control:SetChecked(checked)
        self.checked = checked == true
        self.mark:SetShown(self.checked)
        if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(unpackColor(self.checked and Theme.colors.gold or Theme.colors.goldDim))
        end
    end

    return control
end

local function showFeatureInfoTooltip(owner, feature)
    if not GameTooltip or not owner or not feature then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(resolveText(feature.title), unpackColor(Theme.colors.gold))
    GameTooltip:AddLine(L.FEATURE_INFO_TOOLTIP, 0.88, 0.86, 0.82, true)
    GameTooltip:Show()
end

local function createCategoryButton(parent, width)
    local button = Widgets:CreateButton(parent, "", width, 34, "row")
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 12, 0)
    button.label:SetPoint("RIGHT", -44, 0)
    button.label:SetJustifyH("LEFT")

    button.count = Widgets:CreateLabel(button, "GameFontDisableSmall", "RIGHT")
    button.count:SetPoint("RIGHT", -12, 0)
    button.count:SetWidth(28)
    return button
end

local function createFeatureRow(parent)
    local row = Widgets:CreatePanel(parent, "cardInset")
    row:SetHeight(82)

    row.check = createCheckControl(row, 22)
    row.check:SetPoint("TOPLEFT", 16, -17)

    row.settings = Widgets:CreateSimpleGoldButton(row, "", 30, 28)
    row.settings:SetPoint("TOPRIGHT", -16, -14)
    row.settings.icon = row.settings:CreateTexture(nil, "OVERLAY")
    row.settings.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    row.settings.icon:SetPoint("CENTER", 0, 0)
    row.settings.icon:SetSize(19, 19)
    row.settings.icon:SetVertexColor(0.96, 0.82, 0.36, 0.96)

    row.info = Widgets:CreateSimpleGoldButton(row, "i", 30, 28)
    row.info:SetPoint("TOPRIGHT", row.settings, "TOPLEFT", -4, 0)
    row.info.label:SetFontObject("GameFontNormalLarge")
    row.info.label:SetTextColor(unpackColor(Theme.colors.gold))
    row.info:HookScript("OnEnter", function(self)
        showFeatureInfoTooltip(self, row.feature)
    end)
    row.info:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row.status = Widgets:CreateLabel(row, "GameFontHighlightSmall", "RIGHT")
    row.status:SetPoint("TOPRIGHT", row.info, "TOPLEFT", -12, -5)
    row.status:SetWidth(132)

    row.newBadge = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.newBadge:SetPoint("TOPRIGHT", row.status, "BOTTOMRIGHT", 0, -4)
    row.newBadge:SetWidth(48)
    row.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    row.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    row.newBadge:Hide()

    row.title = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
    row.title:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 12, 1)
    row.title:SetPoint("TOPRIGHT", -250, -16)
    row.title:SetTextColor(unpackColor(Theme.colors.gold))

    row.description = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6)
    row.description:SetPoint("TOPRIGHT", -250, -38)
    row.description:SetJustifyV("TOP")
    row.description:SetWordWrap(true)

    return row
end

local function createSettingRow(parent)
    local row = Widgets:CreatePanel(parent, "cardInset")
    row:SetHeight(48)

    row.label = Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.label:SetPoint("LEFT", 14, 0)
    row.label:SetPoint("RIGHT", -230, 0)

    row.boolean = createCheckControl(row, 22)
    row.boolean:SetPoint("RIGHT", -16, 0)
    row.boolean:Hide()

    row.select = Widgets:CreateButton(row, "", 194, 28)
    row.select:SetPoint("RIGHT", -14, 0)
    row.select:Hide()

    row.action = Widgets:CreateButton(row, "", 194, 28)
    row.action:SetPoint("RIGHT", -14, 0)
    row.action:Hide()

    row.rangePlus = Widgets:CreateButton(row, "+", 38, 28)
    row.rangePlus:SetPoint("RIGHT", -14, 0)
    row.rangePlus:Hide()

    row.rangeValue = Widgets:CreatePanel(row, "cardInset")
    row.rangeValue:SetSize(104, 28)
    row.rangeValue:SetPoint("RIGHT", row.rangePlus, "LEFT", -4, 0)
    row.rangeValue.label = Widgets:CreateLabel(row.rangeValue, "GameFontHighlightSmall", "CENTER")
    row.rangeValue.label:SetAllPoints(row.rangeValue)
    row.rangeValue:Hide()

    row.rangeMinus = Widgets:CreateButton(row, "-", 38, 28)
    row.rangeMinus:SetPoint("RIGHT", row.rangeValue, "LEFT", -4, 0)
    row.rangeMinus:Hide()

    return row
end

local function createSettingsDialog(parent, owner)
    local dialog = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    dialog:SetSize(620, 510)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(parent:GetFrameLevel() + 20)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    Widgets:ApplyStandardGoldFrame(dialog, Assets.windowBackground)
    dialog:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    dialog:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    dialog:SetScript("OnHide", function(self)
        local featureID = self.featureID
        local runtime = featureID and Registry:GetRuntime(featureID) or nil
        if runtime and type(runtime.OnSettingsClosed) == "function" then
            Addon:SafeCall(
                "feature.settings.closed." .. featureID,
                runtime.OnSettingsClosed,
                runtime
            )
        end
    end)

    dialog.title = Widgets:CreateLabel(dialog, "GameFontNormalLarge", "LEFT")
    dialog.title:SetPoint("TOPLEFT", 22, -20)
    dialog.title:SetPoint("TOPRIGHT", -64, -20)
    dialog.title:SetTextColor(unpackColor(Theme.colors.gold))

    dialog.closeButton = Widgets:CreateButton(dialog, "X", 28, 26)
    dialog.closeButton:SetPoint("TOPRIGHT", -18, -16)
    dialog.closeButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    dialog.divider = Widgets:CreateDivider(dialog)
    dialog.divider:SetPoint("TOPLEFT", 22, -58)
    dialog.divider:SetPoint("TOPRIGHT", -22, -58)

    dialog.scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 22, -74)
    dialog.scroll:SetPoint("BOTTOMRIGHT", -42, 66)

    dialog.child = CreateFrame("Frame", nil, dialog.scroll)
    dialog.child:SetSize(540, 10)
    dialog.scroll:SetScrollChild(dialog.child)
    ScrollFrames:Style(dialog.scroll, { autoHide = true })

    dialog.rows = {}

    dialog.reset = Widgets:CreateButton(dialog, L.FEATURE_SETTINGS_RESET, 150, 30)
    dialog.reset:SetPoint("BOTTOMLEFT", 22, 20)
    dialog.reset:SetScript("OnClick", function()
        if dialog.featureID then
            Registry:ResetSettings(dialog.featureID)
            owner:RefreshSettingsDialog()
            owner:Refresh()
        end
    end)

    dialog.done = Widgets:CreateButton(dialog, L.CLOSE, 116, 30)
    dialog.done:SetPoint("BOTTOMRIGHT", -22, 20)
    dialog.done:SetScript("OnClick", function()
        dialog:Hide()
    end)

    dialog:Hide()
    return dialog
end

local function createFeatureInfoDialog(parent)
    local dialog = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    dialog:SetSize(560, 280)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(parent:GetFrameLevel() + 20)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    Widgets:ApplyStandardGoldFrame(dialog, Assets.windowBackground)
    dialog:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    dialog:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    dialog.title = Widgets:CreateLabel(dialog, "GameFontNormalLarge", "LEFT")
    dialog.title:SetPoint("TOPLEFT", 22, -20)
    dialog.title:SetPoint("TOPRIGHT", -64, -20)
    dialog.title:SetTextColor(unpackColor(Theme.colors.gold))

    dialog.closeButton = Widgets:CreateButton(dialog, "X", 28, 26)
    dialog.closeButton:SetPoint("TOPRIGHT", -18, -16)
    dialog.closeButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    dialog.details = Widgets:CreateLabel(dialog, "GameFontHighlightSmall", "LEFT")
    dialog.details:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -20)
    dialog.details:SetPoint("BOTTOMRIGHT", -22, 62)
    dialog.details:SetWordWrap(true)
    dialog.details:SetJustifyV("TOP")

    dialog.done = Widgets:CreateButton(dialog, L.CLOSE, 116, 30)
    dialog.done:SetPoint("BOTTOMRIGHT", -22, 20)
    dialog.done:SetScript("OnClick", function()
        dialog:Hide()
    end)

    dialog:Hide()
    return dialog
end

function Features:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = Widgets:CreatePanel(parent, "content")
    frame.callbacks = callbacks
    frame.rows = {}
    frame.categoryButtons = {}
    frame.searchQuery = ""

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalHuge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 18, -15)
    frame.title:SetText(L.FEATURES_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -7)
    frame.subtitle:SetPoint("TOPRIGHT", -720, -46)
    frame.subtitle:SetText(L.FEATURES_SUBTITLE)
    frame.subtitle:SetWordWrap(true)

    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -14, -13)
    frame.closeButton:SetScript("OnClick", function()
        if type(callbacks.close) == "function" then callbacks.close() end
    end)

    frame.activeOnly = Widgets:CreateButton(frame, "", 132, 30)
    frame.activeOnly:SetPoint("RIGHT", frame.closeButton, "LEFT", -10, 0)
    frame.activeOnly.check = createCheckControl(frame.activeOnly, 18)
    frame.activeOnly.check:SetPoint("LEFT", 8, 0)
    frame.activeOnly.check:EnableMouse(false)
    frame.activeOnly.label:ClearAllPoints()
    frame.activeOnly.label:SetPoint("LEFT", 34, 0)
    frame.activeOnly.label:SetPoint("RIGHT", -7, 0)
    frame.activeOnly.label:SetJustifyH("LEFT")
    frame.activeOnly.label:SetText(L.FEATURES_ACTIVE_ONLY)
    frame.activeOnly:SetScript("OnClick", function()
        local settings = Addon.Database:GetUI().features
        settings.activeOnly = not settings.activeOnly
        frame:Refresh()
    end)

    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetSize(244, 28)
    frame.search:SetPoint("RIGHT", frame.activeOnly, "LEFT", -10, 0)
    frame.search:SetAutoFocus(false)
    if _G.GameFontHighlightSmall and type(frame.search.SetFontObject) == "function" then
        frame.search:SetFontObject(_G.GameFontHighlightSmall)
    end
    frame.searchHint = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.searchHint:SetPoint("RIGHT", -8, 0)
    frame.searchHint:SetText(L.FEATURES_SEARCH)
    frame.search:SetScript("OnTextChanged", function(self)
        frame.searchQuery = self:GetText() or ""
        frame.searchHint:SetShown(frame.searchQuery == "")
        frame:RefreshRows()
    end)
    frame.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.summary = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "RIGHT")
    frame.summary:SetPoint("RIGHT", frame.search, "LEFT", -14, 0)
    frame.summary:SetWidth(150)
    frame.summary:SetTextColor(unpackColor(Theme.colors.gold))

    frame.categoryPanel = Widgets:CreatePanel(frame, "sidebar")
    frame.categoryPanel:SetPoint("TOPLEFT", 18, -76)
    frame.categoryPanel:SetPoint("BOTTOMLEFT", 18, 18)
    frame.categoryPanel:SetWidth(236)

    frame.categoryTitle = Widgets:CreateLabel(frame.categoryPanel, "GameFontNormalLarge", "LEFT")
    frame.categoryTitle:SetPoint("TOPLEFT", 14, -14)
    frame.categoryTitle:SetPoint("TOPRIGHT", -14, -14)
    frame.categoryTitle:SetText(L.FEATURES_CATEGORIES)
    frame.categoryTitle:SetTextColor(unpackColor(Theme.colors.gold))

    local categoryEntries = {
        {
            id = "all",
            label = function() return L.FEATURE_CATEGORY_ALL end,
            description = function() return L.FEATURE_CATEGORY_ALL_DESC end,
        },
    }
    for _, category in ipairs(Registry:GetCategories()) do
        categoryEntries[#categoryEntries + 1] = category
    end
    frame.categoryEntries = categoryEntries

    local previous
    for _, category in ipairs(categoryEntries) do
        local button = createCategoryButton(frame.categoryPanel, 208)
        if previous then
            button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -5)
        else
            button:SetPoint("TOPLEFT", frame.categoryTitle, "BOTTOMLEFT", 0, -14)
        end
        button:SetPoint("RIGHT", -14, 0)
        button.categoryID = category.id
        button:SetScript("OnClick", function(self)
            Addon.Database:GetUI().features.selectedCategory = self.categoryID
            frame:Refresh()
        end)
        frame.categoryButtons[category.id] = button
        previous = button
    end

    frame.categoryNote = Widgets:CreateLabel(frame.categoryPanel, "GameFontDisableSmall", "LEFT")
    frame.categoryNote:SetPoint("BOTTOMLEFT", 14, 16)
    frame.categoryNote:SetPoint("BOTTOMRIGHT", -14, 16)
    frame.categoryNote:SetJustifyV("BOTTOM")
    frame.categoryNote:SetWordWrap(true)

    frame.library = Widgets:CreatePanel(frame, "card")
    frame.library:SetPoint("TOPLEFT", frame.categoryPanel, "TOPRIGHT", 14, 0)
    frame.library:SetPoint("BOTTOMRIGHT", -18, 18)

    frame.libraryTitle = Widgets:CreateLabel(frame.library, "GameFontNormalLarge", "LEFT")
    frame.libraryTitle:SetPoint("TOPLEFT", 18, -15)
    frame.libraryTitle:SetPoint("TOPRIGHT", -18, -15)
    frame.libraryTitle:SetTextColor(unpackColor(Theme.colors.gold))

    frame.librarySubtitle = Widgets:CreateLabel(frame.library, "GameFontHighlightSmall", "LEFT")
    frame.librarySubtitle:SetPoint("TOPLEFT", frame.libraryTitle, "BOTTOMLEFT", 0, -7)
    frame.librarySubtitle:SetPoint("TOPRIGHT", -18, -40)
    frame.librarySubtitle:SetWordWrap(true)

    frame.listHeader = CreateFrame("Frame", nil, frame.library)
    frame.listHeader:SetPoint("TOPLEFT", frame.librarySubtitle, "BOTTOMLEFT", 0, -12)
    frame.listHeader:SetPoint("TOPRIGHT", -36, 0)
    frame.listHeader:SetHeight(20)

    frame.featureHeader = Widgets:CreateLabel(frame.listHeader, "GameFontDisableSmall", "LEFT")
    frame.featureHeader:SetPoint("LEFT", 16, 0)
    frame.featureHeader:SetText(L.FEATURES_HEADER_FEATURE)

    frame.statusHeader = Widgets:CreateLabel(frame.listHeader, "GameFontDisableSmall", "RIGHT")
    frame.statusHeader:SetPoint("RIGHT", -48, 0)
    frame.statusHeader:SetWidth(132)
    frame.statusHeader:SetText(L.FEATURES_HEADER_STATUS)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame.library, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.listHeader, "BOTTOMLEFT", 0, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", -38, 16)

    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(900, 10)
    frame.scroll:SetScrollChild(frame.child)
    ScrollFrames:Style(frame.scroll, { autoHide = true })

    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisableLarge", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 16, -28)
    frame.empty:SetPoint("TOPRIGHT", -16, -28)
    frame.empty:SetText(L.FEATURES_EMPTY)
    frame.empty:Hide()

    frame.settingsDialog = createSettingsDialog(parent, frame)
    frame.infoDialog = createFeatureInfoDialog(parent)

    function frame:GetSelectedCategory()
        local settings = Addon.Database:GetUI().features
        local selected = settings.selectedCategory
        if not self.categoryButtons[selected] then
            selected = "all"
            settings.selectedCategory = selected
        end
        return selected
    end

    function frame:GetCategoryDefinition(categoryID)
        for _, category in ipairs(self.categoryEntries) do
            if category.id == categoryID then return category end
        end
        return self.categoryEntries[1]
    end

    function frame:MarkFeatureSeen(featureID)
        if type(self.callbacks.markFeatureSeen) == "function" then
            return self.callbacks.markFeatureSeen(featureID) == true
        end
        return false
    end

    function frame:ApplyFeatureRow(row, definition)
        row.feature = definition
        row.featureID = definition.id
        row:Show()
        row.title:SetText(resolveText(definition.title))
        row.description:SetText(resolveText(definition.description))
        row.newBadge:SetShown(
            type(self.callbacks.isFeatureNew) == "function"
                and self.callbacks.isFeatureNew(definition.id) == true
        )

        local status = Registry:GetStatus(definition.id)
        row.status:SetText(L[STATUS_KEYS[status]] or status)
        row.status:SetTextColor(unpackColor(STATUS_COLORS[status] or Theme.colors.muted))
        row.check:SetChecked(status == "enabled")
        setControlEnabled(row.check, Registry:CanToggle(definition.id))
        row.check:SetScript("OnClick", function()
            if Registry:CanToggle(definition.id) then
                self:MarkFeatureSeen(definition.id)
                Registry:SetEnabled(definition.id, not Registry:IsEnabled(definition.id), "user")
                self:Refresh()
            end
        end)
        row.check:SetScript("OnEnter", function(control)
            if type(control.SetBackdropBorderColor) == "function" and control.vlEnabled ~= false then
                control:SetBackdropBorderColor(unpackColor(Theme.colors.gold))
            end
        end)

        local hasSettings = #definition.settings > 0
        local settingsAvailable = hasSettings and Registry:IsAvailable(definition.id)
        row.settings:SetShown(settingsAvailable)
        row.settings:SetScript("OnClick", function()
            self:OpenSettings(definition.id)
        end)
        row.info:ClearAllPoints()
        if settingsAvailable then
            row.info:SetPoint("TOPRIGHT", row.settings, "TOPLEFT", -4, 0)
        else
            row.info:SetPoint("TOPRIGHT", -16, -14)
        end
        row.info:Show()
        row.info:SetScript("OnClick", function()
            self:OpenInfo(definition.id)
        end)
        row.status:ClearAllPoints()
        row.status:SetPoint("TOPRIGHT", row.info, "TOPLEFT", -12, -5)

        if status == "planned" then
            row.title:SetTextColor(unpackColor(Theme.colors.goldDim))
            row.description:SetTextColor(unpackColor(Theme.colors.muted))
        else
            row.title:SetTextColor(unpackColor(Theme.colors.gold))
            row.description:SetTextColor(unpackColor(Theme.colors.parchment))
        end

        local textHeight = math.max(14, tonumber(row.description:GetStringHeight()) or 14)
        local rowHeight = math.max(78, math.ceil(53 + textHeight))
        row:SetHeight(rowHeight)
        return rowHeight
    end

    function frame:RefreshRows()
        if not self:IsShown() then return end
        local settings = Addon.Database:GetUI().features
        local selectedCategory = self:GetSelectedCategory()
        local definitions = Registry:GetDefinitions(
            selectedCategory,
            self.searchQuery,
            settings.activeOnly
        )

        local width = tonumber(self.scroll:GetWidth()) or 0
        if width <= 0 then width = 1200 end
        self.child:SetWidth(math.max(10, width - 4))

        local previousRow
        local contentHeight = 0
        for index, definition in ipairs(definitions) do
            local row = self.rows[index]
            if not row then
                row = createFeatureRow(self.child)
                self.rows[index] = row
            end
            row:ClearAllPoints()
            if previousRow then
                row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -8)
            else
                row:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, 0)
            end
            row:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", 0, 0)
            local height = self:ApplyFeatureRow(row, definition)
            contentHeight = contentHeight + height + (index > 1 and 8 or 0)
            previousRow = row
        end
        for index = #definitions + 1, #self.rows do
            self.rows[index]:Hide()
            self.rows[index].feature = nil
            self.rows[index].featureID = nil
        end

        self.empty:SetShown(#definitions == 0)
        self.empty:SetText(
            settings.activeOnly and L.FEATURES_EMPTY_ACTIVE
                or (self.searchQuery ~= "" and L.FEATURES_EMPTY_SEARCH or L.FEATURES_EMPTY)
        )
        self.child:SetHeight(math.max(10, contentHeight))
        ScrollFrames:Refresh(self.scroll, self.lastRenderedCategory ~= selectedCategory)
        self.lastRenderedCategory = selectedCategory
    end

    function frame:RefreshSettingsDialog(forceTop)
        local dialog = self.settingsDialog
        if not dialog:IsShown() or not dialog.featureID then return end
        local definition = Registry:GetDefinition(dialog.featureID)
        if not definition then
            dialog:Hide()
            return
        end

        dialog.title:SetText(string.format(L.FEATURE_SETTINGS_TITLE, resolveText(definition.title)))

        local previousRow
        for index, setting in ipairs(definition.settings) do
            local row = dialog.rows[index]
            if not row then
                row = createSettingRow(dialog.child)
                dialog.rows[index] = row
            end
            row:ClearAllPoints()
            if previousRow then
                row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -8)
            else
                row:SetPoint("TOPLEFT", dialog.child, "TOPLEFT", 0, 0)
            end
            row:SetPoint("TOPRIGHT", dialog.child, "TOPRIGHT", 0, 0)
            row.setting = setting
            row.label:SetText(resolveText(setting.label))
            row:Show()

            local value = Registry:GetSetting(definition.id, setting.key)
            if setting.type == "boolean" then
                row.action:Hide()
                row.select:Hide()
                row.rangeMinus:Hide()
                row.rangeValue:Hide()
                row.rangePlus:Hide()
                row.boolean:Show()
                row.boolean:SetChecked(value == true)
                setControlEnabled(row.boolean, true)
                row.boolean:SetScript("OnClick", function()
                    Registry:SetSetting(definition.id, setting.key, not Registry:GetSetting(definition.id, setting.key))
                    self:RefreshSettingsDialog()
                    self:Refresh()
                end)
            elseif setting.type == "select" then
                row.action:Hide()
                row.boolean:Hide()
                row.rangeMinus:Hide()
                row.rangeValue:Hide()
                row.rangePlus:Hide()
                row.select:Show()
                local currentIndex = 1
                for optionIndex, settingOption in ipairs(setting.options or {}) do
                    if settingOption.value == value then
                        currentIndex = optionIndex
                        row.select.label:SetText(resolveText(settingOption.label))
                        break
                    end
                end
                row.select:SetScript("OnClick", function()
                    local options = setting.options or {}
                    if #options == 0 then return end
                    local nextOption = options[(currentIndex % #options) + 1]
                    Registry:SetSetting(definition.id, setting.key, nextOption.value)
                    self:RefreshSettingsDialog()
                    self:Refresh()
                end)
            elseif setting.type == "range" then
                row.action:Hide()
                row.boolean:Hide()
                row.select:Hide()
                row.rangeMinus:Show()
                row.rangeValue:Show()
                row.rangePlus:Show()
                local minimum = tonumber(setting.minimum) or 0
                local maximum = tonumber(setting.maximum) or minimum
                local step = math.max(0.0001, tonumber(setting.step) or 1)
                value = tonumber(value) or tonumber(setting.default) or minimum
                local rounded = math.floor(value + 0.5)
                row.rangeValue.label:SetText(tostring(rounded) .. tostring(setting.suffix or ""))
                setControlEnabled(row.rangeMinus, value > minimum)
                setControlEnabled(row.rangePlus, value < maximum)
                row.rangeMinus:SetScript("OnClick", function()
                    Registry:SetSetting(definition.id, setting.key, value - step)
                    self:RefreshSettingsDialog()
                    self:Refresh()
                end)
                row.rangePlus:SetScript("OnClick", function()
                    Registry:SetSetting(definition.id, setting.key, value + step)
                    self:RefreshSettingsDialog()
                    self:Refresh()
                end)
            else
                row.boolean:Hide()
                row.select:Hide()
                row.rangeMinus:Hide()
                row.rangeValue:Hide()
                row.rangePlus:Hide()
                row.action:Show()
                row.action.label:SetText(resolveText(setting.actionLabel))
                row.action:SetScript("OnClick", function()
                    Registry:InvokeAction(definition.id, setting.key)
                    self:RefreshSettingsDialog()
                    self:Refresh()
                end)
            end
            previousRow = row
        end
        for index = #definition.settings + 1, #dialog.rows do
            dialog.rows[index]:Hide()
            dialog.rows[index].setting = nil
        end
        dialog.child:SetHeight(math.max(10, (#definition.settings * 56) - 8))
        ScrollFrames:Refresh(dialog.scroll, forceTop == true)
    end

    function frame:OpenInfo(featureID)
        local definition = Registry:GetDefinition(featureID)
        if not definition then return false end

        self:MarkFeatureSeen(featureID)

        local details = resolveText(definition.details)
        if details == "" then details = L.FEATURE_INFO_EMPTY end

        self.settingsDialog:Hide()
        self.infoDialog.featureID = featureID
        self.infoDialog.title:SetText(string.format(
            L.FEATURE_INFO_TITLE,
            resolveText(definition.title)
        ))
        self.infoDialog.details:SetText(details)
        self.infoDialog:Show()
        self.infoDialog:Raise()
        return true
    end

    function frame:OpenSettings(featureID)
        local definition = Registry:GetDefinition(featureID)
        if not definition or #definition.settings == 0 or not Registry:IsAvailable(featureID) then
            return false
        end
        self:MarkFeatureSeen(featureID)
        if self.settingsDialog:IsShown()
            and self.settingsDialog.featureID
            and self.settingsDialog.featureID ~= featureID
        then
            self.settingsDialog:Hide()
        end
        self.infoDialog:Hide()
        self.settingsDialog:SetHeight(math.min(620, math.max(330, 154 + (#definition.settings * 56))))
        self.settingsDialog.featureID = featureID
        self.settingsDialog:Show()
        self.settingsDialog:Raise()
        self:RefreshSettingsDialog(true)
        return true
    end

    function frame:Refresh()
        local settings = Addon.Database:GetUI().features
        local selectedCategory = self:GetSelectedCategory()
        local category = self:GetCategoryDefinition(selectedCategory)
        local enabled, total = Registry:GetStats()
        self.summary:SetText(string.format(L.FEATURES_ACTIVE_SUMMARY, enabled, total))
        self.activeOnly.check:SetChecked(settings.activeOnly)
        Widgets:SetButtonActive(self.activeOnly, settings.activeOnly)

        for _, entry in ipairs(self.categoryEntries) do
            local button = self.categoryButtons[entry.id]
            button.label:SetText(resolveText(entry.label))
            button.count:SetText(Registry:GetCategoryCount(entry.id))
            Widgets:SetButtonActive(button, entry.id == selectedCategory)
        end

        self.libraryTitle:SetText(resolveText(category.label))
        self.librarySubtitle:SetText(resolveText(category.description))
        self.categoryNote:SetText(resolveText(category.description))
        self:RefreshRows()
    end

    frame.scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then
            frame.child:SetWidth(math.max(10, width - 4))
        end
        frame:RefreshRows()
    end)
    frame:SetScript("OnHide", function()
        frame.settingsDialog:Hide()
        frame.infoDialog:Hide()
        if type(frame.search.ClearFocus) == "function" then frame.search:ClearFocus() end
    end)

    Addon.StateStore:Subscribe("features.registry", frame, function()
        if frame:IsShown() then frame:Refresh() end
    end)

    frame:Hide()
    return frame
end
