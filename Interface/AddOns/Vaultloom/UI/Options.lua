local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Options = {}
Addon.OptionsUI = Options

local PAGE_DEFINITIONS = {
    { key = "general", label = function() return L.OPTIONS_PAGE_GENERAL end },
    { key = "language", label = function() return L.OPTIONS_PAGE_LANGUAGE end },
    { key = "navigation", label = function() return L.OPTIONS_PAGE_NAVIGATION end },
    { key = "diagnostics", label = function() return L.OPTIONS_PAGE_DIAGNOSTICS end },
    { key = "patchnotes", label = function() return L.OPTIONS_PAGE_PATCHNOTES end },
}

local VALID_PAGES = {
    general = true,
    language = true,
    navigation = true,
    diagnostics = true,
    patchnotes = true,
}

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function createSectionTitle(parent, text)
    local title = Widgets:CreateLabel(parent, "GameFontNormalLarge", "LEFT")
    title:SetText(text or "")
    title:SetTextColor(unpackColor(Theme.colors.gold))
    return title
end

local function createDescription(parent, text)
    local label = Widgets:CreateLabel(parent, "GameFontHighlightSmall", "LEFT")
    label:SetText(text or "")
    label:SetWordWrap(true)
    label:SetJustifyV("TOP")
    return label
end

local function createPercentRow(parent, labelText, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 18, yOffset)
    row:SetPoint("TOPRIGHT", -18, yOffset)
    row:SetHeight(30)

    row.title = Widgets:CreateLabel(row, "GameFontHighlight", "LEFT")
    row.title:SetPoint("LEFT", 0, 0)
    row.title:SetText(labelText)

    row.plus = Widgets:CreateButton(row, "+", 32, 26)
    row.plus:SetPoint("RIGHT", 0, 0)

    row.value = Widgets:CreateLabel(row, "GameFontNormal", "CENTER")
    row.value:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
    row.value:SetSize(62, 26)
    row.value:SetTextColor(unpackColor(Theme.colors.gold))

    row.minus = Widgets:CreateButton(row, "-", 32, 26)
    row.minus:SetPoint("RIGHT", row.value, "LEFT", -4, 0)

    return row
end

local function createNavigationToggle(parent, definition, width)
    local row = Widgets:CreateButton(parent, "", width, 42, "row")
    row.screenID = definition.id
    row.screenDefinition = definition

    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 50, 0)
    row.label:SetPoint("BOTTOMRIGHT", -12, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(definition.label())

    row.box = CreateFrame("Frame", nil, row, BACKDROP_TEMPLATE)
    row.box:SetPoint("LEFT", 16, 0)
    row.box:SetSize(20, 20)
    if row.box.SetBackdrop then
        row.box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row.box:SetBackdropColor(0.035, 0.030, 0.026, 0.96)
        row.box:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    end

    row.check = row.box:CreateTexture(nil, "OVERLAY")
    row.check:SetPoint("CENTER", 0, 0)
    row.check:SetSize(20, 20)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:SetVertexColor(unpackColor(Theme.colors.gold))

    local baseEnter = row:GetScript("OnEnter")
    local baseLeave = row:GetScript("OnLeave")
    row:SetScript("OnEnter", function(self)
        if baseEnter then
            baseEnter(self)
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(self.label:GetText() or "", unpackColor(Theme.colors.gold))
            if self.vlLastVisible then
                GameTooltip:AddLine(L.OPTIONS_NAVIGATION_LAST_VISIBLE, 0.72, 0.78, 0.88, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if baseLeave then
            baseLeave(self)
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    return row
end

local function addReleaseHistoryHeading(frame, release)
    local row = CreateFrame("Frame", nil, frame.notesScrollChild)
    row.label = Widgets:CreateLabel(row, "GameFontNormalLarge", "LEFT")
    row.label:SetPoint("TOPLEFT", 2, -10)
    row.label:SetText(release.title or release.version or "")
    row.label:SetTextColor(unpackColor(Theme.colors.gold))

    row.state = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
    row.state:SetPoint("TOPRIGHT", -2, -12)
    row.state:SetWidth(220)
    row.state:SetText(release.state or "")
    row.state:SetTextColor(unpackColor(Theme.colors.goldDim))

    row.subtitle = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
    row.subtitle:SetPoint("TOPLEFT", 2, -36)
    row.subtitle:SetPoint("TOPRIGHT", -2, -36)
    row.subtitle:SetJustifyV("TOP")
    row.subtitle:SetWordWrap(true)
    row.subtitle:SetText(release.subtitle or "")

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetPoint("TOPLEFT", 0, 0)
    row.divider:SetPoint("TOPRIGHT", 0, 0)
    row.divider:SetHeight(2)
    row.divider:SetColorTexture(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        0.80
    )

    frame.releaseRows[#frame.releaseRows + 1] = {
        kind = "release",
        frame = row,
    }
end

local function addReleaseSections(frame, release)
    for _, section in ipairs(release.sections or {}) do
        local sectionRow = CreateFrame("Frame", nil, frame.notesScrollChild)
        sectionRow:SetHeight(28)
        sectionRow.label = Widgets:CreateLabel(sectionRow, "GameFontNormal", "LEFT")
        sectionRow.label:SetPoint("LEFT", 2, 0)
        sectionRow.label:SetPoint("RIGHT", -2, 0)
        sectionRow.label:SetText(section.title or "")
        sectionRow.label:SetTextColor(unpackColor(Theme.colors.gold))
        sectionRow.divider = sectionRow:CreateTexture(nil, "ARTWORK")
        sectionRow.divider:SetPoint("BOTTOMLEFT", 0, 0)
        sectionRow.divider:SetPoint("BOTTOMRIGHT", 0, 0)
        sectionRow.divider:SetHeight(1)
        sectionRow.divider:SetColorTexture(
            Theme.colors.goldDim[1],
            Theme.colors.goldDim[2],
            Theme.colors.goldDim[3],
            0.66
        )
        frame.releaseRows[#frame.releaseRows + 1] = {
            kind = "section",
            frame = sectionRow,
        }

        for _, itemText in ipairs(section.items or {}) do
            local itemRow = CreateFrame("Frame", nil, frame.notesScrollChild)
            itemRow.dot = itemRow:CreateTexture(nil, "ARTWORK")
            itemRow.dot:SetPoint("TOPLEFT", 4, -3)
            itemRow.dot:SetSize(6, 6)
            itemRow.dot:SetColorTexture(
                Theme.colors.gold[1],
                Theme.colors.gold[2],
                Theme.colors.gold[3],
                0.90
            )
            itemRow.label = Widgets:CreateLabel(itemRow, "GameFontHighlightSmall", "LEFT")
            itemRow.label:SetPoint("TOPLEFT", 20, 0)
            itemRow.label:SetPoint("TOPRIGHT", 0, 0)
            itemRow.label:SetJustifyV("TOP")
            itemRow.label:SetWordWrap(true)
            itemRow.label:SetText(itemText or "")
            frame.releaseRows[#frame.releaseRows + 1] = {
                kind = "item",
                frame = itemRow,
            }
        end
    end
end

local function createReleaseRows(frame)
    local releaseNotes = Addon.ReleaseNotes
    local current = releaseNotes and releaseNotes.current
    frame.releaseRows = {}
    if not current then
        return
    end

    local releases = releaseNotes.releases or { current }
    local releaseCount = math.min(#releases, tonumber(releaseNotes.maxHistory) or 10)
    for releaseIndex = 1, releaseCount do
        local release = releases[releaseIndex]
        if releaseIndex > 1 then
            addReleaseHistoryHeading(frame, release)
        end
        addReleaseSections(frame, release)
    end
end

local function layoutReleaseRows(frame)
    if not frame.notesScroll or not frame.notesScrollChild then
        return
    end

    local width = tonumber(frame.notesScroll:GetWidth()) or 0
    if width <= 0 then
        width = 1240
    end
    width = math.max(420, math.floor(width - 4))
    frame.notesScrollChild:SetWidth(width)

    local yOffset = 0
    for _, entry in ipairs(frame.releaseRows or {}) do
        local row = entry.frame
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", 0, -yOffset)
        if entry.kind == "release" then
            row:SetWidth(width)
            row.label:SetWidth(math.max(100, width - 240))
            row.subtitle:SetWidth(math.max(100, width - 4))
            local subtitleHeight = math.ceil((row.subtitle:GetStringHeight() or 14) + 2)
            local height = math.max(62, subtitleHeight + 44)
            row:SetHeight(height)
            yOffset = yOffset + height + 14
        elseif entry.kind == "section" then
            row:SetHeight(28)
            yOffset = yOffset + 38
        else
            row:SetWidth(width)
            row.label:SetWidth(math.max(100, width - 20))
            local height = math.max(18, math.ceil((row.label:GetStringHeight() or 14) + 2))
            row:SetHeight(height)
            yOffset = yOffset + height + 9
        end
    end

    frame.notesScrollChild:SetHeight(math.max(10, yOffset + 4))
    ScrollFrames:Refresh(frame.notesScroll, true)
end

local function createGeneralPage(frame, callbacks)
    local page = CreateFrame("Frame", nil, frame)
    frame.pages.general = page

    page.appearance = Widgets:CreatePanel(page, "card")
    page.appearance:SetPoint("TOPLEFT", 0, 0)
    page.appearance:SetSize(642, 222)

    page.appearanceTitle = createSectionTitle(page.appearance, L.OPTIONS_GENERAL_APPEARANCE_TITLE)
    page.appearanceTitle:SetPoint("TOPLEFT", 18, -16)
    page.appearanceText = createDescription(page.appearance, L.OPTIONS_GENERAL_APPEARANCE_TEXT)
    page.appearanceText:SetPoint("TOPLEFT", page.appearanceTitle, "BOTTOMLEFT", 0, -7)
    page.appearanceText:SetPoint("TOPRIGHT", -18, 0)
    page.appearanceText:SetHeight(34)

    page.scaleRow = createPercentRow(page.appearance, L.OPTIONS_GENERAL_SCALE, -90)
    page.opacityRow = createPercentRow(page.appearance, L.OPTIONS_GENERAL_OPACITY, -126)
    page.displayReset = Widgets:CreateButton(
        page.appearance,
        L.OPTIONS_GENERAL_RESET_DISPLAY,
        178,
        26
    )
    page.displayReset:SetPoint("BOTTOMRIGHT", -18, 16)

    page.window = Widgets:CreatePanel(page, "card")
    page.window:SetPoint("TOPLEFT", page.appearance, "TOPRIGHT", 14, 0)
    page.window:SetPoint("TOPRIGHT", 0, 0)
    page.window:SetHeight(222)

    page.windowTitle = createSectionTitle(page.window, L.OPTIONS_GENERAL_WINDOW_TITLE)
    page.windowTitle:SetPoint("TOPLEFT", 18, -16)
    page.windowText = createDescription(page.window, L.OPTIONS_GENERAL_WINDOW_TEXT)
    page.windowText:SetPoint("TOPLEFT", page.windowTitle, "BOTTOMLEFT", 0, -8)
    page.windowText:SetPoint("TOPRIGHT", -18, 0)
    page.windowText:SetHeight(66)

    local windowControlWidth = 238
    local windowControlHeight = 28
    local windowControlGap = 12
    page.positionTitle = Widgets:CreateLabel(page.window, "GameFontNormal", "LEFT")
    page.positionTitle:SetPoint("TOPLEFT", page.windowText, "BOTTOMLEFT", 0, -10)
    page.positionTitle:SetWidth(windowControlWidth)
    page.positionTitle:SetText(L.OPTIONS_GENERAL_RESET_POSITION)
    page.positionTitle:SetTextColor(unpackColor(Theme.colors.gold))
    page.positionReset = Widgets:CreateButton(
        page.window,
        L.FEATURE_ACTION_RESET,
        windowControlWidth,
        windowControlHeight
    )
    page.positionReset:SetPoint("TOPLEFT", page.positionTitle, "BOTTOMLEFT", 0, -5)

    page.keybindTitle = Widgets:CreateLabel(page.window, "GameFontNormal", "LEFT")
    page.keybindTitle:SetPoint("TOPLEFT", page.positionTitle, "TOPRIGHT", windowControlGap, 0)
    page.keybindTitle:SetWidth(windowControlWidth)
    page.keybindTitle:SetText(L.OPTIONS_GENERAL_KEYBIND_TITLE)
    page.keybindTitle:SetTextColor(unpackColor(Theme.colors.gold))
    page.keybindButton = Widgets:CreateButton(
        page.window,
        "",
        windowControlWidth,
        windowControlHeight
    )
    page.keybindButton:SetPoint("TOPLEFT", page.keybindTitle, "BOTTOMLEFT", 0, -5)
    page.keybindHint = createDescription(page.window, L.OPTIONS_GENERAL_KEYBIND_HINT)
    page.keybindHint:SetPoint("TOPLEFT", page.keybindButton, "BOTTOMLEFT", 0, -5)
    page.keybindHint:SetPoint("RIGHT", page.window, "RIGHT", -18, 0)
    page.keybindHint:SetHeight(30)

    page.launcher = Widgets:CreatePanel(page, "sectionInset")
    page.launcher:SetPoint("TOPLEFT", page.appearance, "BOTTOMLEFT", 0, -14)
    page.launcher:SetPoint("TOPRIGHT", page.window, "BOTTOMRIGHT", 0, -14)
    page.launcher:SetHeight(126)
    page.launcherTitle = createSectionTitle(page.launcher, L.OPTIONS_GENERAL_MINIMAP_TITLE)
    page.launcherTitle:SetPoint("TOPLEFT", 18, -16)
    page.launcherText = createDescription(page.launcher, L.OPTIONS_GENERAL_MINIMAP_TEXT)
    page.launcherText:SetPoint("TOPLEFT", page.launcherTitle, "BOTTOMLEFT", 0, -8)
    page.launcherText:SetWidth(610)
    page.launcherText:SetHeight(32)
    page.launcherToggle = Widgets:CreateButton(page.launcher, "", 190, 28)
    page.launcherToggle:SetPoint("BOTTOMLEFT", 18, 16)
    page.launcherReset = Widgets:CreateButton(
        page.launcher,
        L.OPTIONS_GENERAL_MINIMAP_RESET,
        190,
        28
    )
    page.launcherReset:SetPoint("LEFT", page.launcherToggle, "RIGHT", 8, 0)

    page.communityDivider = page.launcher:CreateTexture(nil, "ARTWORK")
    page.communityDivider:SetPoint("TOP", 660, -14)
    page.communityDivider:SetPoint("BOTTOM", 660, 14)
    page.communityDivider:SetWidth(1)
    page.communityDivider:SetColorTexture(
        Theme.colors.goldDim[1],
        Theme.colors.goldDim[2],
        Theme.colors.goldDim[3],
        0.62
    )

    page.communityTitle = createSectionTitle(page.launcher, L.OPTIONS_GENERAL_COMMUNITY_TITLE)
    page.communityTitle:SetPoint("TOPLEFT", 690, -16)
    page.communityText = createDescription(page.launcher, L.OPTIONS_GENERAL_COMMUNITY_TEXT)
    page.communityText:SetPoint("TOPLEFT", page.communityTitle, "BOTTOMLEFT", 0, -8)
    page.communityText:SetPoint("TOPRIGHT", -18, 0)
    page.communityText:SetHeight(20)

    page.discordLink = CreateFrame("EditBox", nil, page.launcher, BACKDROP_TEMPLATE)
    page.discordLink:SetPoint("BOTTOMLEFT", 690, 16)
    page.discordLink:SetSize(420, 28)
    page.discordLink:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    page.discordLink:SetBackdropColor(0.025, 0.022, 0.020, 0.98)
    page.discordLink:SetBackdropBorderColor(unpackColor(Theme.colors.goldDim))
    page.discordLink:SetTextInsets(10, 10, 0, 0)
    page.discordLink:SetAutoFocus(false)
    page.discordLink:SetFontObject(GameFontHighlightSmall)
    page.discordLink:SetTextColor(unpackColor(Theme.colors.cyan))
    page.discordLink:SetText(callbacks.getDiscordURL())
    page.discordLink:SetScript("OnEditFocusGained", function(selfEditBox)
        selfEditBox:SetText(callbacks.getDiscordURL())
        if type(selfEditBox.HighlightText) == "function" then selfEditBox:HighlightText() end
    end)
    page.discordLink:SetScript("OnEscapePressed", function(selfEditBox)
        selfEditBox:ClearFocus()
    end)
    page.discordLink:SetScript("OnEnterPressed", function(selfEditBox)
        selfEditBox:SetText(callbacks.getDiscordURL())
        if type(selfEditBox.HighlightText) == "function" then selfEditBox:HighlightText() end
    end)

    page.discordCopy = Widgets:CreateButton(
        page.launcher,
        L.OPTIONS_GENERAL_COMMUNITY_COPY,
        190,
        28
    )
    page.discordCopy:SetPoint("LEFT", page.discordLink, "RIGHT", 8, 0)
    page.discordCopy:SetScript("OnClick", function()
        callbacks.showDiscordLink()
    end)

    page.chat = Widgets:CreatePanel(page, "sectionInset")
    page.chat:SetPoint("TOPLEFT", page.launcher, "BOTTOMLEFT", 0, -14)
    page.chat:SetPoint("TOPRIGHT", page.launcher, "BOTTOMRIGHT", 0, -14)
    page.chat:SetHeight(126)
    page.chatTitle = createSectionTitle(page.chat, L.OPTIONS_GENERAL_CHAT_TITLE)
    page.chatTitle:SetPoint("TOPLEFT", 18, -16)
    page.chatText = createDescription(page.chat, L.OPTIONS_GENERAL_CHAT_TEXT)
    page.chatText:SetPoint("TOPLEFT", page.chatTitle, "BOTTOMLEFT", 0, -8)
    page.chatText:SetPoint("TOPRIGHT", -18, 0)
    page.chatText:SetHeight(32)
    page.chatToggle = Widgets:CreateButton(page.chat, "", 238, 28)
    page.chatToggle:SetPoint("BOTTOMLEFT", 18, 16)

    page.scaleRow.minus:SetScript("OnClick", function()
        callbacks.setScale((callbacks.getSettings().scale or 1) - 0.05)
        frame:RefreshGeneral()
    end)
    page.scaleRow.plus:SetScript("OnClick", function()
        callbacks.setScale((callbacks.getSettings().scale or 1) + 0.05)
        frame:RefreshGeneral()
    end)
    page.opacityRow.minus:SetScript("OnClick", function()
        callbacks.setOpacity((callbacks.getSettings().opacity or 1) - 0.05)
        frame:RefreshGeneral()
    end)
    page.opacityRow.plus:SetScript("OnClick", function()
        callbacks.setOpacity((callbacks.getSettings().opacity or 1) + 0.05)
        frame:RefreshGeneral()
    end)
    page.displayReset:SetScript("OnClick", function()
        callbacks.resetDisplay()
        frame:RefreshGeneral()
    end)
    page.positionReset:SetScript("OnClick", function()
        callbacks.resetPosition()
    end)
    local ignoredBindingKeys = {
        UNKNOWN = true,
        LSHIFT = true,
        RSHIFT = true,
        LCTRL = true,
        RCTRL = true,
        LALT = true,
        RALT = true,
    }
    local function setKeybindCapture(capturing)
        page.keybindCapturing = capturing == true
        if type(page.keybindButton.EnableKeyboard) == "function" then
            page.keybindButton:EnableKeyboard(page.keybindCapturing)
        end
        if type(page.keybindButton.SetPropagateKeyboardInput) == "function" then
            page.keybindButton:SetPropagateKeyboardInput(not page.keybindCapturing)
        end
        frame:RefreshGeneral()
    end
    local function setKeybindResult(ok, status, key)
        if not ok then
            page.keybindMessage = status == "combat"
                and L.OPTIONS_GENERAL_KEYBIND_COMBAT
                or L.OPTIONS_GENERAL_KEYBIND_FAILED
            return
        end
        if status == "cleared" then
            page.keybindMessage = L.OPTIONS_GENERAL_KEYBIND_CLEARED
            return
        end
        local formattedKey = callbacks.formatToggleBinding(key)
        page.keybindMessage = string.format(
            status == "replaced"
                and L.OPTIONS_GENERAL_KEYBIND_REPLACED
                or L.OPTIONS_GENERAL_KEYBIND_SAVED,
            formattedKey
        )
    end
    page.keybindButton:SetScript("OnClick", function()
        page.keybindMessage = nil
        setKeybindCapture(not page.keybindCapturing)
    end)
    page.keybindButton:SetScript("OnKeyDown", function(_, key)
        if not page.keybindCapturing or type(key) ~= "string" then return end
        key = key:upper()
        if key == "ESCAPE" then
            page.keybindMessage = nil
            setKeybindCapture(false)
            return
        end
        if key == "BACKSPACE" or key == "DELETE" then
            setKeybindCapture(false)
            setKeybindResult(callbacks.clearToggleBinding())
            frame:RefreshGeneral()
            return
        end
        if ignoredBindingKeys[key] then return end

        if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            key = "SHIFT-" .. key
        end
        if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
            key = "CTRL-" .. key
        end
        if type(IsAltKeyDown) == "function" and IsAltKeyDown() then
            key = "ALT-" .. key
        end
        setKeybindCapture(false)
        local ok, status = callbacks.setToggleBinding(key)
        setKeybindResult(ok, status, key)
        frame:RefreshGeneral()
    end)
    page:SetScript("OnHide", function()
        if page.keybindCapturing then
            setKeybindCapture(false)
        end
    end)
    page.launcherToggle:SetScript("OnClick", function()
        callbacks.setMinimapHidden(not callbacks.isMinimapHidden())
        frame:RefreshGeneral()
    end)
    page.launcherReset:SetScript("OnClick", function()
        callbacks.resetMinimapPosition()
        frame:RefreshGeneral()
    end)
    page.chatToggle:SetScript("OnClick", function()
        callbacks.setChatMessagesEnabled(not callbacks.areChatMessagesEnabled())
        frame:RefreshGeneral()
    end)
end

local function createLanguagePage(frame, callbacks)
    local page = CreateFrame("Frame", nil, frame)
    frame.pages.language = page

    page.card = Widgets:CreatePanel(page, "card")
    page.card:SetAllPoints(page)

    page.title = createSectionTitle(page.card, L.OPTIONS_LANGUAGE_TITLE)
    page.title:SetPoint("TOPLEFT", 18, -16)
    page.text = createDescription(page.card, L.OPTIONS_LANGUAGE_TEXT)
    page.text:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -8)
    page.text:SetPoint("TOPRIGHT", -18, 0)
    page.text:SetHeight(34)
    page.notice = createDescription(page.card, L.OPTIONS_LANGUAGE_RELOAD)
    page.notice:SetPoint("TOPLEFT", page.text, "BOTTOMLEFT", 0, -7)
    page.notice:SetPoint("TOPRIGHT", -18, 0)
    page.notice:SetHeight(18)
    page.notice:SetTextColor(unpackColor(Theme.colors.cyan))

    page.scroll = CreateFrame("ScrollFrame", nil, page.card, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", page.notice, "BOTTOMLEFT", 0, -14)
    page.scroll:SetPoint("BOTTOMRIGHT", -28, 18)
    page.scroll:EnableMouseWheel(true)
    page.scrollChild = CreateFrame("Frame", nil, page.scroll)
    page.scrollChild:SetSize(1200, 10)
    page.scroll:SetScrollChild(page.scrollChild)
    page.scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * 46)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)
    page.scroll:SetScript("OnSizeChanged", function(selfScroll)
        local width = tonumber(selfScroll:GetWidth()) or 0
        if width > 100 then
            page.scrollChild:SetWidth(math.floor(width - 2))
        end
    end)
    ScrollFrames:Style(page.scroll)

    page.rows = {}
    page.rowsByKey = {}
    for index, option in ipairs(callbacks.getLanguages()) do
        local row = Widgets:CreateButton(page.scrollChild, "", 1200, 42, "row")
        row.localeKey = option.key
        if index == 1 then
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", page.rows[index - 1], "BOTTOMLEFT", 0, -6)
            row:SetPoint("TOPRIGHT", page.rows[index - 1], "BOTTOMRIGHT", 0, -6)
        end

        row.check = row:CreateTexture(nil, "OVERLAY")
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 16, 0)
        row.check:SetVertexColor(unpackColor(Theme.colors.gold))

        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 50, -6)
        row.label:SetPoint("TOPRIGHT", -18, -6)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(option.label)

        row.detail = Widgets:CreateLabel(row, "GameFontDisableSmall", "LEFT")
        row.detail:SetPoint("BOTTOMLEFT", 50, 6)
        row.detail:SetPoint("BOTTOMRIGHT", -18, 6)
        row.detail:SetText(option.detail)

        row:SetScript("OnClick", function(selfRow)
            if callbacks.getLanguage() == selfRow.localeKey then
                return
            end
            if callbacks.setLanguage(selfRow.localeKey) then
                frame:RefreshLanguage()
                callbacks.reloadLanguage()
            end
        end)

        page.rows[index] = row
        page.rowsByKey[option.key] = row
    end
    page.scrollChild:SetHeight(math.max(10, (#page.rows * 48) - 6))
    ScrollFrames:Refresh(page.scroll, true)
end

local function createNavigationPage(frame, callbacks)
    local page = CreateFrame("Frame", nil, frame)
    frame.pages.navigation = page

    page.card = Widgets:CreatePanel(page, "card")
    page.card:SetAllPoints(page)
    page.title = createSectionTitle(page.card, L.OPTIONS_NAVIGATION_TITLE)
    page.title:SetPoint("TOPLEFT", 18, -16)
    page.description = createDescription(page.card, L.OPTIONS_NAVIGATION_TEXT)
    page.description:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -7)
    page.description:SetPoint("TOPRIGHT", -190, 0)
    page.description:SetHeight(34)
    page.showAll = Widgets:CreateButton(page.card, L.OPTIONS_NAVIGATION_SHOW_ALL, 142, 26)
    page.showAll:SetPoint("TOPRIGHT", -18, -18)

    page.rows = {}
    local definitions = callbacks.getScreens()
    for index, definition in ipairs(definitions) do
        local row = createNavigationToggle(page.card, definition, 614)
        local column = (index - 1) % 2
        local line = math.floor((index - 1) / 2)
        if column == 0 then
            row:SetPoint("TOPLEFT", 18, -82 - (line * 50))
        else
            row:SetPoint("TOPRIGHT", -18, -82 - (line * 50))
        end
        row:SetScript("OnClick", function(self)
            callbacks.setScreenVisible(self.screenID, not callbacks.isScreenVisible(self.screenID))
            frame:RefreshNavigation()
        end)
        page.rows[#page.rows + 1] = row
    end

    page.showAll:SetScript("OnClick", function()
        callbacks.showAllScreens()
        frame:RefreshNavigation()
    end)
end

local function formatMemory(memoryKB)
    memoryKB = tonumber(memoryKB)
    if not memoryKB then
        return L.OPTIONS_DIAGNOSTICS_MEMORY_UNKNOWN
    end
    if memoryKB >= 1024 then
        return string.format("%.1f MB", memoryKB / 1024)
    end
    return string.format("%.0f KB", memoryKB)
end

local function createDiagnosticsPage(frame)
    local page = CreateFrame("Frame", nil, frame)
    frame.pages.diagnostics = page

    page.summary = Widgets:CreatePanel(page, "card")
    page.summary:SetPoint("TOPLEFT", 0, 0)
    page.summary:SetPoint("TOPRIGHT", 0, 0)
    page.summary:SetHeight(190)

    page.title = createSectionTitle(page.summary, L.OPTIONS_DIAGNOSTICS_TITLE)
    page.title:SetPoint("TOPLEFT", 18, -16)
    page.description = createDescription(page.summary, L.OPTIONS_DIAGNOSTICS_TEXT)
    page.description:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -7)
    page.description:SetPoint("TOPRIGHT", -18, 0)
    page.description:SetHeight(34)

    page.status = Widgets:CreateLabel(page.summary, "GameFontHighlightSmall", "LEFT")
    page.status:SetPoint("TOPLEFT", page.description, "BOTTOMLEFT", 0, -8)
    page.status:SetPoint("RIGHT", -18, 0)
    page.status:SetHeight(18)

    page.memory = Widgets:CreateLabel(page.summary, "GameFontNormalSmall", "LEFT")
    page.memory:SetPoint("TOPLEFT", page.status, "BOTTOMLEFT", 0, -4)
    page.memory:SetPoint("RIGHT", -18, 0)
    page.memory:SetHeight(18)
    page.memory:SetTextColor(unpackColor(Theme.colors.cyan))

    page.cpu = Widgets:CreateLabel(page.summary, "GameFontNormalSmall", "LEFT")
    page.cpu:SetPoint("TOPLEFT", page.memory, "BOTTOMLEFT", 0, -4)
    page.cpu:SetPoint("RIGHT", -18, 0)
    page.cpu:SetHeight(18)
    page.cpu:SetTextColor(unpackColor(Theme.colors.gold))

    page.toggle = Widgets:CreateButton(page.summary, L.OPTIONS_DIAGNOSTICS_START, 168, 26)
    page.toggle:SetPoint("BOTTOMLEFT", 18, 16)
    page.reset = Widgets:CreateButton(page.summary, L.OPTIONS_DIAGNOSTICS_RESET, 168, 26)
    page.reset:SetPoint("LEFT", page.toggle, "RIGHT", 6, 0)
    page.snapshot = Widgets:CreateButton(page.summary, L.OPTIONS_DIAGNOSTICS_SNAPSHOT, 168, 26)
    page.snapshot:SetPoint("LEFT", page.reset, "RIGHT", 6, 0)
    page.arm = Widgets:CreateButton(page.summary, L.OPTIONS_DIAGNOSTICS_ARM, 208, 26)
    page.arm:SetPoint("LEFT", page.snapshot, "RIGHT", 6, 0)

    page.hint = Widgets:CreateLabel(page.summary, "GameFontDisableSmall", "LEFT")
    page.hint:SetPoint("LEFT", page.arm, "RIGHT", 12, 0)
    page.hint:SetPoint("RIGHT", -18, 0)
    page.hint:SetHeight(34)
    page.hint:SetWordWrap(true)
    page.hint:SetText(L.OPTIONS_DIAGNOSTICS_RELOAD_HINT)

    page.results = Widgets:CreatePanel(page, "inset")
    page.results:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -12)
    page.results:SetPoint("BOTTOMRIGHT", 0, 0)

    page.header = CreateFrame("Frame", nil, page.results)
    page.header:SetPoint("TOPLEFT", 14, -10)
    page.header:SetPoint("TOPRIGHT", -30, -10)
    page.header:SetHeight(22)

    local columns = {
        { key = "name", text = L.OPTIONS_DIAGNOSTICS_COLUMN_MODULE, x = 0, width = 232, justify = "LEFT" },
        { key = "calls", text = L.OPTIONS_DIAGNOSTICS_COLUMN_CALLS, x = 240, width = 58, justify = "RIGHT" },
        { key = "total", text = L.OPTIONS_DIAGNOSTICS_COLUMN_TOTAL, x = 308, width = 70, justify = "RIGHT" },
        { key = "average", text = L.OPTIONS_DIAGNOSTICS_COLUMN_AVERAGE, x = 388, width = 70, justify = "RIGHT" },
        { key = "peak", text = L.OPTIONS_DIAGNOSTICS_COLUMN_PEAK, x = 468, width = 70, justify = "RIGHT" },
        { key = "allocated", text = L.OPTIONS_DIAGNOSTICS_COLUMN_ALLOCATED, x = 548, width = 78, justify = "RIGHT" },
        { key = "lua", text = L.OPTIONS_DIAGNOSTICS_COLUMN_LUA, x = 636, width = 78, justify = "RIGHT" },
        { key = "hottest", text = L.OPTIONS_DIAGNOSTICS_COLUMN_HOTTEST, x = 728, width = 456, justify = "LEFT" },
    }
    page.columns = columns
    for _, column in ipairs(columns) do
        local label = Widgets:CreateLabel(page.header, "GameFontNormalSmall", column.justify)
        label:SetPoint("TOPLEFT", column.x, 0)
        label:SetSize(column.width, 20)
        label:SetText(column.text)
        label:SetTextColor(unpackColor(Theme.colors.gold))
        page.header[column.key] = label
    end

    page.scroll = CreateFrame("ScrollFrame", nil, page.results, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -3)
    page.scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    page.scroll:EnableMouseWheel(true)
    page.scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * 26)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)
    page.scrollChild = CreateFrame("Frame", nil, page.scroll)
    page.scrollChild:SetSize(1184, 10)
    page.scroll:SetScrollChild(page.scrollChild)
    page.scroll:SetScript("OnSizeChanged", function(selfScroll)
        local width = tonumber(selfScroll:GetWidth()) or 0
        if width > 100 then
            page.scrollChild:SetWidth(math.floor(width - 2))
        end
    end)
    ScrollFrames:Style(page.scroll)
    page.rows = {}

    local function ensureRow(index)
        if page.rows[index] then
            return page.rows[index]
        end
        local row = CreateFrame("Frame", nil, page.scrollChild)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("TOPRIGHT", 0, -((index - 1) * 24))
        row:SetHeight(23)
        row:EnableMouse(true)
        row.backdrop = row:CreateTexture(nil, "BACKGROUND")
        row.backdrop:SetAllPoints(row)
        if index % 2 == 0 then
            row.backdrop:SetColorTexture(0.13, 0.11, 0.08, 0.26)
        else
            row.backdrop:SetColorTexture(0.03, 0.03, 0.03, 0.12)
        end
        for _, column in ipairs(columns) do
            local label = Widgets:CreateLabel(row, "GameFontHighlightSmall", column.justify)
            label:SetPoint("TOPLEFT", column.x, -2)
            label:SetSize(column.width, 20)
            label:SetWordWrap(false)
            row[column.key] = label
        end
        row:SetScript("OnEnter", function(selfRow)
            local result = selfRow.result
            if not result or not GameTooltip then
                return
            end
            GameTooltip:SetOwner(selfRow, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(result.label, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(string.format(
                "%s: %d   %s: %.2f   %s: %.1f",
                L.OPTIONS_DIAGNOSTICS_COLUMN_CALLS,
                result.calls,
                L.OPTIONS_DIAGNOSTICS_COLUMN_TOTAL,
                result.totalMs,
                L.OPTIONS_DIAGNOSTICS_COLUMN_ALLOCATED,
                result.allocatedKB
            ), 0.78, 0.84, 0.92, true)
            for detailIndex = 1, math.min(8, #(result.details or {})) do
                local detail = result.details[detailIndex]
                GameTooltip:AddDoubleLine(
                    detail.key,
                    string.format("%dx  %.2f ms  %.1f KB", detail.calls, detail.totalMs, detail.allocatedKB),
                    0.85, 0.85, 0.82,
                    0.58, 0.86, 1
                )
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        page.rows[index] = row
        return row
    end
    page.EnsureRow = ensureRow

    page.toggle:SetScript("OnClick", function()
        if Addon.PerformanceDiagnostics:IsActive() then
            Addon.PerformanceDiagnostics:Stop()
        else
            Addon.PerformanceDiagnostics:Start("manual")
        end
        frame:RefreshDiagnostics(true)
    end)
    page.reset:SetScript("OnClick", function()
        Addon.PerformanceDiagnostics:Reset()
        frame:RefreshDiagnostics(true)
    end)
    page.snapshot:SetScript("OnClick", function()
        frame:RefreshDiagnostics(true)
    end)
    page.arm:SetScript("OnClick", function()
        Addon.PerformanceDiagnostics:ArmForReload(
            not Addon.PerformanceDiagnostics:IsArmedForReload()
        )
        frame:RefreshDiagnostics(false)
    end)

    page.refreshElapsed = 0
    page:SetScript("OnUpdate", function(selfPage, elapsed)
        if not Addon.PerformanceDiagnostics:IsActive() then
            return
        end
        selfPage.refreshElapsed = selfPage.refreshElapsed + (tonumber(elapsed) or 0)
        if selfPage.refreshElapsed >= 0.75 then
            selfPage.refreshElapsed = 0
            frame:RefreshDiagnostics(false)
        end
    end)
end

local function createPatchnotesPage(frame, callbacks)
    local page = CreateFrame("Frame", nil, frame)
    frame.pages.patchnotes = page
    local release = Addon.ReleaseNotes and Addon.ReleaseNotes.current

    page.header = Widgets:CreatePanel(page, "card")
    page.header:SetPoint("TOPLEFT", 0, 0)
    page.header:SetPoint("TOPRIGHT", 0, 0)
    page.header:SetHeight(92)
    page.title = createSectionTitle(page.header, release and release.title or L.OPTIONS_PAGE_PATCHNOTES)
    page.title:SetPoint("TOPLEFT", 18, -16)
    page.state = Widgets:CreateLabel(page.header, "GameFontNormalSmall", "RIGHT")
    page.state:SetPoint("TOPRIGHT", -18, -18)
    page.state:SetText(release and release.state or "")
    page.state:SetTextColor(unpackColor(Theme.colors.gold))
    page.subtitle = createDescription(page.header, release and release.subtitle or L.OPTIONS_PATCHNOTES_EMPTY)
    page.subtitle:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -9)
    page.subtitle:SetPoint("TOPRIGHT", page.state, "BOTTOMLEFT", -18, 0)
    page.subtitle:SetHeight(34)

    page.list = Widgets:CreatePanel(page, "inset")
    page.list:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -14)
    page.list:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.notesScroll = CreateFrame("ScrollFrame", nil, page.list, "UIPanelScrollFrameTemplate")
    frame.notesScroll:SetPoint("TOPLEFT", 16, -14)
    frame.notesScroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.notesScroll:EnableMouseWheel(true)
    frame.notesScroll:SetScript("OnMouseWheel", function(self, delta)
        local nextValue = self:GetVerticalScroll() - (delta * 48)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), nextValue)))
    end)
    frame.notesScrollChild = CreateFrame("Frame", nil, frame.notesScroll)
    frame.notesScrollChild:SetSize(1240, 10)
    frame.notesScroll:SetScrollChild(frame.notesScrollChild)
    frame.notesScroll:SetScript("OnSizeChanged", function()
        layoutReleaseRows(frame)
    end)
    ScrollFrames:Style(frame.notesScroll)
    createReleaseRows(frame)
    layoutReleaseRows(frame)
end

function Options:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = Widgets:CreatePanel(parent, "content")
    frame.layoutVersion = "options-workbench-1"
    frame.pages = {}
    frame.pageButtons = {}
    frame:Hide()

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 18, -16)
    frame.title:SetText(L.OPTIONS_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -14, -13)
    frame.closeButton:SetScript("OnClick", function()
        callbacks.close()
    end)

    frame.version = Widgets:CreateLabel(frame, "GameFontDisableSmall", "RIGHT")
    frame.version:SetPoint("RIGHT", frame.closeButton, "LEFT", -12, 0)
    frame.version:SetWidth(120)
    frame.version:SetText(Addon.version)

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -7)
    frame.subtitle:SetPoint("TOPRIGHT", frame.version, "BOTTOMLEFT", -12, 0)
    frame.subtitle:SetText(L.OPTIONS_SUBTITLE)

    frame.pageBar = CreateFrame("Frame", nil, frame)
    frame.pageBar:SetPoint("TOPLEFT", frame.subtitle, "BOTTOMLEFT", 0, -13)
    frame.pageBar:SetPoint("TOPRIGHT", -18, 0)
    frame.pageBar:SetHeight(30)

    local previous
    for _, definition in ipairs(PAGE_DEFINITIONS) do
        local button = Widgets:CreateButton(frame.pageBar, definition.label(), 158, 30, "tab")
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end
        button.pageKey = definition.key
        button:SetScript("OnClick", function(self)
            frame:SetPage(self.pageKey)
        end)
        if definition.key == "patchnotes" then
            button.newBadge = Widgets:CreateLabel(button, "GameFontNormalSmall", "RIGHT")
            button.newBadge:SetPoint("TOPRIGHT", -3, -1)
            button.newBadge:SetText(L.OPTIONS_NEW_BADGE)
            button.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
            button.newBadge:Hide()
        end
        frame.pageButtons[definition.key] = button
        previous = button
    end

    frame.pageHost = CreateFrame("Frame", nil, frame)
    frame.pageHost:SetPoint("TOPLEFT", frame.pageBar, "BOTTOMLEFT", 0, -14)
    frame.pageHost:SetPoint("BOTTOMRIGHT", -18, 18)

    createGeneralPage(frame, callbacks)
    createLanguagePage(frame, callbacks)
    createNavigationPage(frame, callbacks)
    createDiagnosticsPage(frame)
    createPatchnotesPage(frame, callbacks)
    for _, page in pairs(frame.pages) do
        page:SetAllPoints(frame.pageHost)
        page:Hide()
    end

    function frame:RefreshGeneral()
        local settings = callbacks.getSettings()
        self.pages.general.scaleRow.value:SetText(
            string.format("%d%%", math.floor(((settings.scale or 1) * 100) + 0.5))
        )
        self.pages.general.opacityRow.value:SetText(
            string.format("%d%%", math.floor(((settings.opacity or 1) * 100) + 0.5))
        )
        local minimapHidden = callbacks.isMinimapHidden()
        self.pages.general.launcherToggle.label:SetText(
            minimapHidden and L.OPTIONS_GENERAL_MINIMAP_SHOW or L.OPTIONS_GENERAL_MINIMAP_HIDE
        )
        Widgets:SetButtonActive(self.pages.general.launcherToggle, not minimapHidden)
        local chatMessagesEnabled = callbacks.areChatMessagesEnabled()
        self.pages.general.chatToggle.label:SetText(
            chatMessagesEnabled
                and L.OPTIONS_GENERAL_CHAT_DISABLE
                or L.OPTIONS_GENERAL_CHAT_ENABLE
        )
        Widgets:SetButtonActive(self.pages.general.chatToggle, chatMessagesEnabled)
        self.pages.general.discordLink:SetText(callbacks.getDiscordURL())
        local keybindPage = self.pages.general
        if keybindPage.keybindCapturing then
            keybindPage.keybindButton.label:SetText(L.OPTIONS_GENERAL_KEYBIND_CAPTURE)
            keybindPage.keybindHint:SetText(L.OPTIONS_GENERAL_KEYBIND_HINT)
            Widgets:SetButtonActive(keybindPage.keybindButton, true)
        else
            local key = callbacks.getToggleBinding()
            keybindPage.keybindButton.label:SetText(callbacks.formatToggleBinding(key))
            keybindPage.keybindHint:SetText(
                keybindPage.keybindMessage or L.OPTIONS_GENERAL_KEYBIND_HINT
            )
            Widgets:SetButtonActive(keybindPage.keybindButton, key ~= nil)
        end
    end

    function frame:RefreshLanguage()
        local selected = callbacks.getLanguage()
        for _, row in ipairs(self.pages.language.rows) do
            local active = row.localeKey == selected
            row.check:SetShown(active)
            Widgets:SetButtonActive(row, active)
        end
        ScrollFrames:Refresh(self.pages.language.scroll)
    end

    function frame:RefreshNavigation()
        local visibleCount = 0
        for _, row in ipairs(self.pages.navigation.rows) do
            if callbacks.isScreenVisible(row.screenID) then
                visibleCount = visibleCount + 1
            end
        end

        for _, row in ipairs(self.pages.navigation.rows) do
            local visible = callbacks.isScreenVisible(row.screenID)
            local lastVisible = visible and visibleCount <= 1
            row.check:SetShown(visible)
            row.vlLastVisible = lastVisible
            row:SetAlpha(lastVisible and 0.62 or 1)
            Widgets:SetButtonActive(row, visible)
            if row.box and row.box.SetBackdropBorderColor then
                row.box:SetBackdropBorderColor(unpackColor(visible and Theme.colors.gold or Theme.colors.goldDim))
            end
        end

        local hiddenCount = math.max(0, #self.pages.navigation.rows - visibleCount)
        Widgets:SetButtonActive(self.pages.navigation.showAll, hiddenCount > 0)
        self.pages.navigation.showAll:SetAlpha(hiddenCount > 0 and 1 or 0.55)
    end

    function frame:RefreshDiagnostics(refreshMemory)
        local diagnosticsToken = Addon.PerformanceDiagnostics:Begin(
            Addon.PerformanceDiagnostics,
            "diagnostics",
            "render_results"
        )
        local page = self.pages.diagnostics
        local snapshot = Addon.PerformanceDiagnostics:GetSnapshot(refreshMemory == true)
        local seconds = (tonumber(snapshot.durationMs) or 0) / 1000
        local statusText
        if snapshot.active then
            statusText = string.format(
                L.OPTIONS_DIAGNOSTICS_RUNNING,
                seconds,
                tonumber(snapshot.trackedMs) or 0
            )
        elseif seconds > 0 then
            statusText = string.format(
                L.OPTIONS_DIAGNOSTICS_STOPPED,
                seconds,
                tonumber(snapshot.trackedMs) or 0
            )
        else
            statusText = L.OPTIONS_DIAGNOSTICS_IDLE
        end
        local coverage = type(snapshot.coverage) == "table" and snapshot.coverage or {}
        page.status:SetText(statusText .. "  |  " .. string.format(
            L.OPTIONS_DIAGNOSTICS_COVERAGE,
            tonumber(coverage.enabledFeatures) or 0,
            tonumber(coverage.enabledModules) or 0,
            tonumber(coverage.createdScreens) or 0
        ))
        page.memory:SetText(string.format(
            L.OPTIONS_DIAGNOSTICS_MEMORY,
            formatMemory(snapshot.memoryKB)
        ))
        if type(snapshot.addonCPU) == "table"
            and snapshot.addonCPU.recent ~= nil
            and snapshot.addonCPU.session ~= nil
            and snapshot.addonCPU.peak ~= nil
        then
            page.cpu:SetText(string.format(
                L.OPTIONS_DIAGNOSTICS_CPU,
                snapshot.addonCPU.recent,
                snapshot.addonCPU.session,
                snapshot.addonCPU.peak
            ))
        else
            page.cpu:SetText(L.OPTIONS_DIAGNOSTICS_CPU_UNKNOWN)
        end
        page.toggle.label:SetText(snapshot.active
            and L.OPTIONS_DIAGNOSTICS_STOP or L.OPTIONS_DIAGNOSTICS_START)
        page.arm.label:SetText(snapshot.armed
            and L.OPTIONS_DIAGNOSTICS_ARMED or L.OPTIONS_DIAGNOSTICS_ARM)
        Widgets:SetButtonActive(page.toggle, snapshot.active)
        Widgets:SetButtonActive(page.arm, snapshot.armed)

        for index, result in ipairs(snapshot.rows) do
            local row = page.EnsureRow(index)
            row.name:SetText(result.label)
            row.calls:SetText(tostring(result.calls))
            row.total:SetText(string.format("%.2f", result.totalMs))
            row.average:SetText(string.format("%.3f", result.averageMs))
            row.peak:SetText(string.format("%.2f", result.peakMs))
            row.allocated:SetText(string.format("%.1f", result.allocatedKB))
            row.lua:SetText(string.format("%+.1f", result.luaDeltaKB))
            row.hottest:SetText(result.hottest)
            row.result = result
            row:Show()
        end
        for index = #snapshot.rows + 1, #page.rows do
            page.rows[index].result = nil
            page.rows[index]:Hide()
        end
        page.scrollChild:SetHeight(math.max(10, #snapshot.rows * 24))
        ScrollFrames:Refresh(page.scroll)
        Addon.PerformanceDiagnostics:Finish(diagnosticsToken)
    end

    function frame:RefreshPatchnotesBadge()
        local button = self.pageButtons.patchnotes
        if not button or not button.newBadge then return end
        local unread = type(callbacks.hasUnreadReleaseNotes) == "function"
            and callbacks.hasUnreadReleaseNotes() == true
        button.newBadge:SetShown(unread)
    end

    function frame:SetPage(pageKey)
        pageKey = VALID_PAGES[pageKey] and pageKey or "general"
        local settings = callbacks.getSettings()
        settings.options.selectedPage = pageKey
        for key, page in pairs(self.pages) do
            page:SetShown(key == pageKey)
            Widgets:SetButtonActive(self.pageButtons[key], key == pageKey)
        end
        if pageKey == "patchnotes" and Addon.ReleaseNotes then
            callbacks.markReleaseRead(Addon.ReleaseNotes.latestVersion)
        elseif pageKey == "language" then
            self:RefreshLanguage()
        elseif pageKey == "diagnostics" then
            self:RefreshDiagnostics(true)
        end
        self:RefreshPatchnotesBadge()
        callbacks.refreshOptionsButton()
    end

    function frame:Refresh()
        self.version:SetText(Addon.version)
        self:RefreshGeneral()
        self:RefreshLanguage()
        self:RefreshNavigation()
        self:RefreshDiagnostics(false)
        self:RefreshPatchnotesBadge()
        local settings = callbacks.getSettings()
        self:SetPage(settings.options.selectedPage)
    end

    return frame
end
