local _, Addon = ...

local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Navigation = {}
Addon.VerticalNavigation = Navigation

local View = {}
View.__index = View

local function getLabel(definition)
    if type(definition.label) == "function" then
        local ok, label = pcall(definition.label)
        return ok and tostring(label or "") or ""
    end
    return tostring(definition.label or "")
end

local function isVisible(definition)
    if type(definition.visible) ~= "function" then
        return true
    end
    local ok, visible = pcall(definition.visible)
    return ok and visible == true
end

function View:SetOnSelect(callback)
    self.onSelect = callback
end

function View:SetDefinitions(definitions)
    for _, entry in ipairs(self.entries) do
        entry:Hide()
    end

    self.definitions = definitions or {}
    self.entries = {}
    self.buttonsByKey = {}
    self.entriesByKey = {}
    self.labelsByKey = {}

    for _, definition in ipairs(self.definitions) do
        local entry
        if definition.heading == true then
            entry = CreateFrame("Frame", nil, self.list)
            entry:SetHeight(20)
            entry.label = Widgets:CreateLabel(entry, "GameFontNormalSmall", "LEFT")
            entry.label:SetPoint("LEFT", 8, 0)
            entry.label:SetPoint("RIGHT", -8, 0)
            entry.label:SetTextColor(0.92, 0.76, 0.24, 0.92)
            entry.divider = entry:CreateTexture(nil, "ARTWORK")
            entry.divider:SetPoint("BOTTOMLEFT", 8, 0)
            entry.divider:SetPoint("BOTTOMRIGHT", -8, 0)
            entry.divider:SetHeight(1)
            entry.divider:SetColorTexture(0.40, 0.31, 0.10, 0.55)
        else
            entry = Widgets:CreateButton(self.list, "", self.listWidth, 34, "tab")
            entry.subTabKey = definition.key
            entry:SetScript("OnClick", function(selfButton)
                if self.onSelect then
                    self.onSelect(selfButton.subTabKey)
                end
            end)
            self.buttonsByKey[definition.key] = entry
        end

        entry.definition = definition
        self.entries[#self.entries + 1] = entry
        if definition.key then
            self.entriesByKey[definition.key] = entry
        end
    end

    self:Refresh()
end

function View:Refresh()
    local y = 0
    self.visibleByKey = {}

    for _, entry in ipairs(self.entries) do
        local definition = entry.definition
        local visible = isVisible(definition)
        entry:SetShown(visible)
        if visible then
            local label = getLabel(definition)
            entry.label:SetText(label)
            if definition.key then
                self.labelsByKey[definition.key] = label
            end

            if definition.heading == true and y < 0 then
                y = y - 10
            end
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, y)
            entry:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, y)

            if definition.heading == true then
                y = y - 28
            else
                self.visibleByKey[definition.key] = true
                y = y - 40
            end
        end
    end

    self.list:SetHeight(math.max(10, -y + 4))
    ScrollFrames:Refresh(self.scroll)
    self:SetSelected(self.selectedKey)
end

function View:SetSelected(key)
    self.selectedKey = key
    for buttonKey, button in pairs(self.buttonsByKey) do
        Widgets:SetButtonActive(button, buttonKey == key and self.visibleByKey[buttonKey] == true)
    end
end

function View:IsVisible(key)
    return self.visibleByKey[key] == true
end

function View:GetLabel(key)
    return self.labelsByKey[key]
end

function Navigation:Create(parent, width)
    width = math.max(120, tonumber(width) or 168)
    local rail = Widgets:CreatePanel(parent, "cardInset")
    rail:SetWidth(width)

    local scroll = CreateFrame("ScrollFrame", nil, rail, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -12)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)

    local list = CreateFrame("Frame", nil, scroll)
    local listWidth = math.max(80, width - 24)
    list:SetSize(listWidth, 10)
    scroll:SetScrollChild(list)
    scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * 38)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)

    local view = setmetatable({
        frame = rail,
        scroll = scroll,
        list = list,
        listWidth = listWidth,
        definitions = {},
        entries = {},
        entriesByKey = {},
        buttonsByKey = {},
        labelsByKey = {},
        visibleByKey = {},
    }, View)
    ScrollFrames:Style(scroll, {
        autoHide = true,
        onVisibilityChanged = function(_, visible)
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", 12, -12)
            scroll:SetPoint("BOTTOMRIGHT", visible and -28 or -12, 12)
            view.listWidth = math.max(80, width - (visible and 40 or 24))
            list:SetWidth(view.listWidth)
        end,
    })
    rail.navigationView = view
    return view
end
