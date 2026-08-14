local _, Addon = ...

local FEATURE_ID = "mailbox"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local SEND_PANEL_WIDTH = 440
local SEND_PANEL_HEIGHT = 590
local INBOX_PANEL_WIDTH = 318
local INBOX_PANEL_HEIGHT = 465
local RECIPIENTS_PER_PAGE = 8
local RULES_PER_PAGE = 4

local Runtime = {
    enabled = false,
    panel = nil,
    inboxHooksReady = false,
    sendHooksReady = false,
}
Addon.MailboxFeature = Runtime

local FILTERS = {
    { key = "all", labelKey = "MAILBOX_COLLECT_ALL" },
    { key = "money", labelKey = "MAILBOX_COLLECT_MONEY" },
    { key = "items", labelKey = "MAILBOX_COLLECT_ITEMS" },
    { key = "auction", labelKey = "MAILBOX_COLLECT_AUCTION" },
    { key = "expiring", labelKey = "MAILBOX_COLLECT_EXPIRING" },
}

local SEND_VIEWS = {
    { key = "quick", labelKey = "MAILBOX_SEND_TAB_QUICK" },
    { key = "rules", labelKey = "MAILBOX_SEND_TAB_RULES" },
    { key = "mass", labelKey = "MAILBOX_SEND_TAB_MASS" },
}

local SEND_STATUS_KEYS = {
    recipient_required = "MAILBOX_SEND_RECIPIENT_REQUIRED",
    seed_required = "MAILBOX_SEND_SEED_REQUIRED",
    item_data_missing = "MAILBOX_SEND_UNAVAILABLE",
    nothing_to_send = "MAILBOX_SEND_NOTHING",
    attachments_full = "MAILBOX_SEND_ATTACHMENTS_FULL",
    template_incomplete = "MAILBOX_SEND_TEMPLATE_INCOMPLETE",
    mailbox_required = "MAILBOX_SEND_MAILBOX_REQUIRED",
    clear_attachments = "MAILBOX_SEND_CLEAR_ATTACHMENTS",
    send_unavailable = "MAILBOX_SEND_UNAVAILABLE",
    message_required = "MAILBOX_SEND_MESSAGE_REQUIRED",
    attach_failed = "MAILBOX_SEND_FAILED",
    timeout = "MAILBOX_SEND_TIMEOUT",
    send_failed = "MAILBOX_SEND_FAILED",
    complete = "MAILBOX_SEND_COMPLETE",
    failed = "MAILBOX_SEND_FAILED",
    stopped = "MAILBOX_SEND_STOPPED",
    queue_busy = "MAILBOX_QUEUE_BUSY",
}

local function getSetting(settingKey)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, settingKey)
end

local function currentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
        or Addon.WoWApi:GetCurrentCharacterIdentity()
    return type(identity) == "table" and identity.key or nil
end

local function getText(editBox)
    return editBox and type(editBox.GetText) == "function" and tostring(editBox:GetText() or "") or ""
end

local function setText(editBox, value)
    if editBox and type(editBox.SetText) == "function" then editBox:SetText(tostring(value or "")) end
end

local function setButtonEnabled(button, enabled)
    if not button then return end
    if enabled and type(button.Enable) == "function" then
        button:Enable()
    elseif not enabled and type(button.Disable) == "function" then
        button:Disable()
    end
end

local function frameShown(frame)
    return frame and (type(frame.IsShown) ~= "function" or frame:IsShown())
end

local function createEditBox(parent, width, height, numeric)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, height)
    editBox:SetAutoFocus(false)
    if type(editBox.SetTextInsets) == "function" then editBox:SetTextInsets(7, 7, 0, 0) end
    if numeric and type(editBox.SetNumeric) == "function" then editBox:SetNumeric(true) end
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return editBox
end

local function statusText(status)
    local localizationKey = SEND_STATUS_KEYS[tostring(status or "idle")]
    return localizationKey and Addon.L[localizationKey] or ""
end

function Runtime:GetMailboxMode()
    return frameShown(SendMailFrame) and "send" or frameShown(InboxFrame) and "inbox" or nil
end

function Runtime:ShouldShowPanel()
    return self.enabled == true
        and Addon.Mailbox
        and Addon.Mailbox:IsOpen()
        and self:GetMailboxMode() ~= nil
end

function Runtime:RefreshInboxView()
    local panel = self.panel
    if not panel then return end
    local snapshot = Addon.Mailbox:GetSnapshot(currentCharacterKey())
    local summary = type(snapshot and snapshot.summary) == "table" and snapshot.summary or {
        messages = 0,
        attachments = 0,
        money = 0,
        cod = 0,
        expiring = 0,
    }
    panel.summary:SetText(string.format(
        Addon.L.MAILBOX_PANEL_SUMMARY,
        summary.messages or 0,
        summary.attachments or 0,
        Addon.Mailbox:FormatMoney(summary.money or 0)
    ))
    panel.warning:SetText(string.format(
        Addon.L.MAILBOX_PANEL_WARNINGS,
        summary.expiring or 0,
        summary.cod and summary.cod > 0 and Addon.Mailbox:FormatMoney(summary.cod) or "0"
    ))

    local queue = Addon.Mailbox:GetQueueState() or {}
    local active = queue.active == true
    if active then
        panel.status:SetText(string.format(
            Addon.L.MAILBOX_QUEUE_RUNNING,
            queue.processedMessages or 0,
            queue.collectedAttachments or 0,
            Addon.Mailbox:FormatMoney(queue.collectedMoney or 0)
        ))
    elseif queue.status == "blocked" then
        panel.status:SetText(Addon.L.MAILBOX_QUEUE_BAGS_FULL)
    elseif queue.status == "complete" and (queue.processedMessages or 0) > 0 then
        panel.status:SetText(string.format(
            Addon.L.MAILBOX_QUEUE_DONE,
            queue.processedMessages or 0,
            queue.collectedAttachments or 0
        ))
    else
        panel.status:SetText(Addon.L.MAILBOX_QUEUE_READY)
    end
    for filterKey, button in pairs(panel.filterButtons) do
        Addon.Widgets:SetButtonActive(button, active and queue.filterKey == filterKey)
        setButtonEnabled(button, not active)
    end
    panel.stop:SetShown(active)
    panel.keepFree:SetText(string.format(
        Addon.L.MAILBOX_PANEL_KEEP_FREE,
        tonumber(getSetting("keep_free_slots")) or 1
    ))
end

function Runtime:GetSelectedRule()
    local panel = self.panel
    local rules = Addon.MailSender and Addon.MailSender:GetRules() or {}
    if #rules == 0 then
        panel.ruleIndex = 0
        return nil, rules
    end
    panel.ruleIndex = math.max(1, math.min(#rules, tonumber(panel.ruleIndex) or 1))
    return rules[panel.ruleIndex], rules
end

function Runtime:GetSelectedTemplate()
    local panel = self.panel
    local templates = Addon.MailSender and Addon.MailSender:GetTemplates() or {}
    if #templates == 0 then
        panel.templateIndex = 0
        return nil, templates
    end
    panel.templateIndex = math.max(1, math.min(#templates, tonumber(panel.templateIndex) or 1))
    return templates[panel.templateIndex], templates
end

function Runtime:RefreshRecipientDropdown()
    local panel = self.panel
    if not panel or not panel.recipientPopup or not panel.recipientPopup:IsShown() then return end
    local suggestions = Addon.MailSender:GetRecipientSuggestions(100, "")
    local pageCount = math.max(1, math.ceil(#suggestions / RECIPIENTS_PER_PAGE))
    panel.recipientPage = math.max(1, math.min(pageCount, tonumber(panel.recipientPage) or 1))
    local startIndex = ((panel.recipientPage - 1) * RECIPIENTS_PER_PAGE) + 1
    local visibleCount = math.min(RECIPIENTS_PER_PAGE, math.max(0, #suggestions - startIndex + 1))
    panel.recipientPopup:SetHeight(#suggestions == 0 and 50
        or 18 + (visibleCount * 27) + (pageCount > 1 and 34 or 3))
    local currentRecipient = getText(SendMailNameEditBox)
    for rowIndex, button in ipairs(panel.recipientRows) do
        local suggestion = suggestions[startIndex + rowIndex - 1]
        button:SetShown(suggestion ~= nil)
        button.recipient = suggestion and suggestion.name or nil
        if suggestion then
            button.label:SetText(suggestion.name)
            Addon.Widgets:SetButtonActive(button, suggestion.name == currentRecipient)
        end
    end
    panel.recipientEmpty:SetShown(#suggestions == 0)
    panel.recipientPageLabel:SetShown(pageCount > 1)
    panel.recipientPrevious:SetShown(pageCount > 1)
    panel.recipientNext:SetShown(pageCount > 1)
    panel.recipientPageLabel:SetText(string.format(
        Addon.L.MAILBOX_SEND_PAGE,
        panel.recipientPage,
        pageCount
    ))
    setButtonEnabled(panel.recipientPrevious, panel.recipientPage > 1)
    setButtonEnabled(panel.recipientNext, panel.recipientPage < pageCount)
end

function Runtime:RefreshSendView()
    local panel = self.panel
    if not panel or not Addon.MailSender then return end
    local queue = Addon.MailSender:GetQueueState() or {}
    local active = queue.active == true
    local currentRecipient = getText(SendMailNameEditBox)
    panel.recipientSelector.label:SetText((currentRecipient ~= ""
        and currentRecipient or Addon.L.MAILBOX_SEND_SELECT_RECIPIENT) .. "  v")
    setButtonEnabled(panel.recipientSelector, not active)
    self:RefreshRecipientDropdown()

    panel.favorite.label:SetText(Addon.MailSender:IsFavorite(currentRecipient)
        and Addon.L.MAILBOX_SEND_UNFAVORITE or Addon.L.MAILBOX_SEND_FAVORITE)
    setButtonEnabled(panel.favorite, currentRecipient ~= "" and not active)

    for viewKey, view in pairs(panel.sendViews) do view:SetShown(panel.sendView == viewKey) end
    for viewKey, button in pairs(panel.sendTabButtons) do
        Addon.Widgets:SetButtonActive(button, panel.sendView == viewKey)
    end

    local attachmentCount = 0
    if type(HasSendMailItem) == "function" then
        for index = 1, math.max(1, tonumber(ATTACHMENTS_MAX_SEND) or 12) do
            if HasSendMailItem(index) then attachmentCount = attachmentCount + 1 end
        end
    elseif type(GetSendMailItem) == "function" then
        for index = 1, math.max(1, tonumber(ATTACHMENTS_MAX_SEND) or 12) do
            if GetSendMailItem(index) then attachmentCount = attachmentCount + 1 end
        end
    end
    panel.quickInfo:SetText(string.format(Addon.L.MAILBOX_SEND_ATTACHMENTS, attachmentCount))

    local rule, rules = self:GetSelectedRule()
    local rulePageCount = math.max(1, math.ceil(#rules / RULES_PER_PAGE))
    if rule then panel.rulePage = math.ceil(panel.ruleIndex / RULES_PER_PAGE) end
    panel.rulePage = math.max(1, math.min(rulePageCount, tonumber(panel.rulePage) or 1))
    local firstRule = ((panel.rulePage - 1) * RULES_PER_PAGE) + 1
    for rowIndex, button in ipairs(panel.ruleRows) do
        local ruleIndex = firstRule + rowIndex - 1
        local rowRule = rules[ruleIndex]
        button:SetShown(rowRule ~= nil)
        button.ruleIndex = rowRule and ruleIndex or nil
        if rowRule then
            button.label:SetText(string.format(
                Addon.L.MAILBOX_SEND_RULE_ROW,
                ruleIndex,
                rowRule.enabled == false and Addon.L.FEATURE_STATUS_DISABLED or Addon.L.FEATURE_STATUS_ENABLED,
                Addon.MailSendLogic:BuildRuleLabel(rowRule),
                tonumber(rowRule.keepCount) or 0
            ))
            Addon.Widgets:SetButtonActive(button, ruleIndex == panel.ruleIndex)
        end
    end
    panel.ruleEmpty:SetShown(#rules == 0)
    panel.rulePageLabel:SetText(string.format(Addon.L.MAILBOX_SEND_PAGE, panel.rulePage, rulePageCount))
    setButtonEnabled(panel.rulePrevious, panel.rulePage > 1 and not active)
    setButtonEnabled(panel.ruleNext, panel.rulePage < rulePageCount and not active)
    for _, button in ipairs(panel.ruleActionButtons) do setButtonEnabled(button, rule ~= nil and not active) end

    local template, templates = self:GetSelectedTemplate()
    panel.templateLabel:SetShown(template ~= nil)
    panel.templateLabel:SetText(template and string.format(
        Addon.L.MAILBOX_SEND_TEMPLATE_ENTRY,
        panel.templateIndex,
        #templates,
        tostring(template.name or "")
    ) or "")
    setButtonEnabled(panel.templateApply, template ~= nil and not active)
    setButtonEnabled(panel.templateDelete, template ~= nil and not active)
    setButtonEnabled(panel.templatePrevious, #templates > 1 and not active)
    setButtonEnabled(panel.templateNext, #templates > 1 and not active)
    setButtonEnabled(panel.templateSave, not active)

    local preview = Addon.MailSender:GetPreview()
    if preview and preview.summary then
        panel.sendPreview:Show()
        panel.sendPreview:SetText(string.format(
            Addon.L.MAILBOX_SEND_PREVIEW,
            preview.summary.letters or 0,
            preview.summary.recipients or 0,
            preview.summary.attachments or 0,
            preview.summary.itemUnits or 0
        ))
    else
        panel.sendPreview:Hide()
    end
    local sendStatus = ""
    if active then
        sendStatus = string.format(
            Addon.L.MAILBOX_SEND_QUEUE_RUNNING,
            queue.processedLetters or 0,
            queue.totalLetters or 0,
            queue.processedAttachments or 0
        )
    elseif queue.status == "complete" and (queue.processedLetters or 0) > 0 then
        sendStatus = string.format(
            Addon.L.MAILBOX_SEND_QUEUE_DONE,
            queue.processedLetters or 0,
            queue.processedAttachments or 0
        )
    else
        sendStatus = statusText(Addon.MailSender.lastStatus or queue.status)
    end
    panel.sendStatus:SetText(sendStatus)
    panel.sendStatus:SetShown(sendStatus ~= "")
    panel.sendStop:SetShown(active)
    setButtonEnabled(panel.rulePreview, not active)
    setButtonEnabled(panel.ruleStart, not active)
    setButtonEnabled(panel.addItemRule, not active)
    setButtonEnabled(panel.addTypeRule, not active)
    setButtonEnabled(panel.massPreview, not active)
    setButtonEnabled(panel.massStart, not active)
    setButtonEnabled(panel.massAddCurrent, not active)
    setButtonEnabled(panel.massClear, not active)
    for _, button in pairs(panel.quickButtons) do setButtonEnabled(button, not active) end
end

function Runtime:RefreshPanel()
    local panel = self.panel
    if not panel then return end
    panel:SetShown(self:ShouldShowPanel())
    if not panel:IsShown() then
        if panel.recipientPopup then panel.recipientPopup:Hide() end
        return
    end
    local mode = self:GetMailboxMode()
    panel:SetSize(
        mode == "send" and SEND_PANEL_WIDTH or INBOX_PANEL_WIDTH,
        mode == "send" and SEND_PANEL_HEIGHT or INBOX_PANEL_HEIGHT
    )
    if mode ~= "send" and panel.recipientPopup then panel.recipientPopup:Hide() end
    panel.inboxView:SetShown(mode == "inbox")
    panel.sendViewFrame:SetShown(mode == "send")
    panel.title:SetText(mode == "send" and Addon.L.MAILBOX_SEND_TITLE or Addon.L.MAILBOX_PANEL_TITLE)
    if mode == "send" then self:RefreshSendView() else self:RefreshInboxView() end
end

function Runtime:EnsureInboxHooks()
    if self.inboxHooksReady then return true end
    if not InboxFrame or type(InboxFrame.HookScript) ~= "function" then return false end
    InboxFrame:HookScript("OnShow", function() Runtime:RefreshPanel() end)
    InboxFrame:HookScript("OnHide", function() Runtime:RefreshPanel() end)
    self.inboxHooksReady = true
    return true
end

function Runtime:EnsureSendHooks()
    if self.sendHooksReady then return true end
    if not SendMailFrame or type(SendMailFrame.HookScript) ~= "function" then return false end
    SendMailFrame:HookScript("OnShow", function() Runtime:RefreshPanel() end)
    SendMailFrame:HookScript("OnHide", function() Runtime:RefreshPanel() end)
    if SendMailNameEditBox and type(SendMailNameEditBox.HookScript) == "function" then
        SendMailNameEditBox:HookScript("OnTextChanged", function() Runtime:RefreshSendView() end)
    end
    if SendMailMailButton and type(SendMailMailButton.HookScript) == "function" then
        SendMailMailButton:HookScript("OnClick", function()
            if Runtime.enabled and Addon.MailSender then Addon.MailSender:PrepareManualSend() end
        end)
    end
    self.sendHooksReady = true
    return true
end

local function buildInboxView(panel)
    local view = CreateFrame("Frame", nil, panel)
    view:SetPoint("TOPLEFT", 14, -42)
    view:SetPoint("BOTTOMRIGHT", -14, 14)
    panel.inboxView = view
    panel.filterButtons = {}

    panel.summary = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.summary:SetPoint("TOPLEFT", 0, 0)
    panel.summary:SetPoint("RIGHT", 0, 0)
    panel.warning = Addon.Widgets:CreateLabel(view, "GameFontDisableSmall", "LEFT")
    panel.warning:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -5)
    panel.warning:SetPoint("RIGHT", 0, 0)
    panel.buttonTitle = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.buttonTitle:SetPoint("TOPLEFT", panel.warning, "BOTTOMLEFT", 0, -15)
    panel.buttonTitle:SetPoint("RIGHT", 0, 0)
    panel.buttonTitle:SetText(Addon.L.MAILBOX_PANEL_COLLECT_TITLE)

    local previousLeft, previousRight
    for index, definition in ipairs(FILTERS) do
        local button = Addon.Widgets:CreateButton(
            view,
            Addon.L[definition.labelKey] or definition.key,
            index == 5 and 290 or 142,
            25
        )
        if index == 5 then
            button:SetPoint("TOPLEFT", previousLeft, "BOTTOMLEFT", 0, -6)
        elseif index % 2 == 1 then
            button:SetPoint("TOPLEFT", index == 1 and panel.buttonTitle or previousLeft, "BOTTOMLEFT", 0, index == 1 and -8 or -6)
            previousLeft = button
        else
            button:SetPoint("TOPLEFT", previousRight or panel.buttonTitle, "BOTTOMLEFT", index == 2 and 148 or 0, index == 2 and -8 or -6)
            previousRight = button
        end
        button.filterKey = definition.key
        button:SetScript("OnClick", function(selfButton)
            Addon.Mailbox:StartCollect(selfButton.filterKey)
            Runtime:RefreshPanel()
        end)
        panel.filterButtons[definition.key] = button
    end

    panel.keepFree = Addon.Widgets:CreateLabel(view, "GameFontDisableSmall", "LEFT")
    panel.keepFree:SetPoint("BOTTOMLEFT", 0, 41)
    panel.keepFree:SetPoint("RIGHT", 0, 0)
    panel.status = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.status:SetPoint("BOTTOMLEFT", 0, 17)
    panel.status:SetPoint("BOTTOMRIGHT", -82, 17)
    panel.status:SetWordWrap(false)
    panel.stop = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_QUEUE_STOP, 72, 24)
    panel.stop:SetPoint("BOTTOMRIGHT", 0, 8)
    panel.stop:SetScript("OnClick", function()
        Addon.Mailbox:StopCollect("user")
        Runtime:RefreshPanel()
    end)
end

local function buildQuickView(panel, parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -105)
    view:SetPoint("BOTTOMRIGHT", 0, 70)
    panel.sendViews.quick = view
    panel.quickInfo = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.quickInfo:SetPoint("TOPLEFT", 0, 0)
    panel.quickInfo:SetPoint("RIGHT", 0, 0)
    panel.quickButtons = {}
    local definitions = {
        { "same", "MAILBOX_SEND_ATTACH_SAME" },
        { "type", "MAILBOX_SEND_ATTACH_TYPE" },
        { "materials", "MAILBOX_SEND_ATTACH_MATERIALS" },
        { "all", "MAILBOX_SEND_ATTACH_ALL" },
    }
    for index, definition in ipairs(definitions) do
        local button = Addon.Widgets:CreateButton(view, Addon.L[definition[2]], 201, 30)
        local row = math.floor((index - 1) / 2)
        local column = (index - 1) % 2
        button:SetPoint("TOPLEFT", 211 * column, -35 - (38 * row))
        button:SetScript("OnClick", function()
            Addon.MailSender:QuickAttach(definition[1])
            Runtime:RefreshSendView()
        end)
        panel.quickButtons[definition[1]] = button
    end
end

local function buildRulesView(panel, parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -105)
    view:SetPoint("BOTTOMRIGHT", 0, 70)
    panel.sendViews.rules = view
    panel.ruleCreateTitle = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.ruleCreateTitle:SetPoint("TOPLEFT", 0, 0)
    panel.ruleCreateTitle:SetText(Addon.L.MAILBOX_SEND_NEW_RULE)
    panel.keepLabel = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.keepLabel:SetPoint("TOPLEFT", 0, -29)
    panel.keepLabel:SetText(Addon.L.MAILBOX_SEND_KEEP)
    panel.ruleKeep = createEditBox(view, 52, 24, true)
    panel.ruleKeep:SetPoint("LEFT", panel.keepLabel, "RIGHT", 8, 0)
    panel.ruleKeep:SetNumber(0)
    panel.addItemRule = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_RULE_ITEM, 201, 28)
    panel.addItemRule:SetPoint("TOPLEFT", 0, -57)
    panel.addTypeRule = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_RULE_TYPE, 201, 28)
    panel.addTypeRule:SetPoint("LEFT", panel.addItemRule, "RIGHT", 10, 0)
    panel.addItemRule:SetScript("OnClick", function()
        if Addon.MailSender:AddRuleFromCompose("item", panel.ruleKeep:GetNumber()) then
            panel.ruleIndex = #Addon.MailSender:GetRules()
        end
        Runtime:RefreshSendView()
    end)
    panel.addTypeRule:SetScript("OnClick", function()
        if Addon.MailSender:AddRuleFromCompose("subclass", panel.ruleKeep:GetNumber()) then
            panel.ruleIndex = #Addon.MailSender:GetRules()
        end
        Runtime:RefreshSendView()
    end)
    panel.ruleListTitle = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.ruleListTitle:SetPoint("TOPLEFT", 0, -94)
    panel.ruleListTitle:SetText(Addon.L.MAILBOX_SEND_SAVED_RULES)
    panel.ruleRows = {}
    for rowIndex = 1, RULES_PER_PAGE do
        local row = Addon.Widgets:CreateButton(view, "", 412, 28, "row")
        row:SetPoint("TOPLEFT", 0, -116 - ((rowIndex - 1) * 33))
        row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(selfRow)
            if selfRow.ruleIndex then panel.ruleIndex = selfRow.ruleIndex end
            Runtime:RefreshSendView()
        end)
        panel.ruleRows[rowIndex] = row
    end
    panel.ruleEmpty = Addon.Widgets:CreateLabel(view, "GameFontDisableSmall", "LEFT")
    panel.ruleEmpty:SetPoint("TOPLEFT", 7, -124)
    panel.ruleEmpty:SetText(Addon.L.MAILBOX_SEND_NO_RULES)

    panel.rulePrevious = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_PREVIOUS, 95, 25)
    panel.rulePrevious:SetPoint("TOPLEFT", 0, -250)
    panel.rulePageLabel = Addon.Widgets:CreateLabel(view, "GameFontDisableSmall", "CENTER")
    panel.rulePageLabel:SetPoint("TOPLEFT", 103, -255)
    panel.rulePageLabel:SetSize(98, 20)
    panel.ruleNext = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_NEXT, 95, 25)
    panel.ruleNext:SetPoint("TOPLEFT", 209, -250)
    panel.rulePrevious:SetScript("OnClick", function()
        panel.rulePage = math.max(1, (panel.rulePage or 1) - 1)
        panel.ruleIndex = ((panel.rulePage - 1) * RULES_PER_PAGE) + 1
        Runtime:RefreshSendView()
    end)
    panel.ruleNext:SetScript("OnClick", function()
        panel.rulePage = (panel.rulePage or 1) + 1
        panel.ruleIndex = ((panel.rulePage - 1) * RULES_PER_PAGE) + 1
        Runtime:RefreshSendView()
    end)

    panel.ruleActionButtons = {}
    local ruleActions = {
        { "MAILBOX_SEND_MOVE_UP", 82, function(rule) Addon.MailSender:MoveRule(rule.id, -1); panel.ruleIndex = math.max(1, panel.ruleIndex - 1) end },
        { "MAILBOX_SEND_MOVE_DOWN", 82, function(rule) Addon.MailSender:MoveRule(rule.id, 1); panel.ruleIndex = panel.ruleIndex + 1 end },
        { "MAILBOX_SEND_TOGGLE", 104, function(rule) Addon.MailSender:ToggleRule(rule.id) end },
        { "MAILBOX_SEND_DELETE", 118, function(rule) Addon.MailSender:DeleteRule(rule.id) end },
    }
    local x = 0
    for _, definition in ipairs(ruleActions) do
        local button = Addon.Widgets:CreateButton(view, Addon.L[definition[1]], definition[2], 25)
        button:SetPoint("TOPLEFT", x, -283)
        x = x + definition[2] + 8
        button:SetScript("OnClick", function()
            local rule = Runtime:GetSelectedRule()
            if rule then definition[3](rule) end
            Runtime:RefreshSendView()
        end)
        panel.ruleActionButtons[#panel.ruleActionButtons + 1] = button
    end
    panel.rulePreview = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_PREVIEW_BUTTON, 120, 28)
    panel.rulePreview:SetPoint("TOPLEFT", 0, -318)
    panel.ruleStart = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_START, 282, 28)
    panel.ruleStart:SetPoint("LEFT", panel.rulePreview, "RIGHT", 10, 0)
    panel.rulePreview:SetScript("OnClick", function() Addon.MailSender:BuildRulePreview(); Runtime:RefreshSendView() end)
    panel.ruleStart:SetScript("OnClick", function() Addon.MailSender:StartRuleQueue(); Runtime:RefreshSendView() end)
end

local function buildMassView(panel, parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 0, -105)
    view:SetPoint("BOTTOMRIGHT", 0, 70)
    panel.sendViews.mass = view
    panel.massRecipientLabel = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.massRecipientLabel:SetPoint("TOPLEFT", 0, 0)
    panel.massRecipientLabel:SetText(Addon.L.MAILBOX_SEND_MASS_RECIPIENTS)
    panel.massRecipients = createEditBox(view, 412, 27, false)
    panel.massRecipients:SetPoint("TOPLEFT", 0, -24)
    panel.massAddCurrent = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_ADD_CURRENT, 201, 28)
    panel.massAddCurrent:SetPoint("TOPLEFT", 0, -59)
    panel.massClear = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_CLEAR_LIST, 201, 28)
    panel.massClear:SetPoint("LEFT", panel.massAddCurrent, "RIGHT", 10, 0)
    panel.massAddCurrent:SetScript("OnClick", function()
        local current = getText(SendMailNameEditBox)
        if current ~= "" then
            local existing = getText(panel.massRecipients)
            setText(panel.massRecipients, existing ~= "" and (existing .. ", " .. current) or current)
        end
    end)
    panel.massClear:SetScript("OnClick", function() setText(panel.massRecipients, "") end)
    panel.massPreview = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_PREVIEW_BUTTON, 120, 28)
    panel.massPreview:SetPoint("TOPLEFT", 0, -94)
    panel.massStart = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_MASS_START, 282, 28)
    panel.massStart:SetPoint("LEFT", panel.massPreview, "RIGHT", 10, 0)
    panel.massPreview:SetScript("OnClick", function()
        Addon.MailSender:BuildMassPreview(getText(panel.massRecipients))
        Runtime:RefreshSendView()
    end)
    panel.massStart:SetScript("OnClick", function()
        Addon.MailSender:StartMassQueue(getText(panel.massRecipients))
        Runtime:RefreshSendView()
    end)

    panel.templateTitle = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.templateTitle:SetPoint("TOPLEFT", 0, -143)
    panel.templateTitle:SetText(Addon.L.MAILBOX_SEND_TEMPLATES)
    panel.templateLabel = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.templateLabel:SetPoint("TOPLEFT", 0, -168)
    panel.templateLabel:SetPoint("RIGHT", 0, 0)
    panel.templatePrevious = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_PREVIOUS, 74, 25)
    panel.templatePrevious:SetPoint("TOPLEFT", 0, -195)
    panel.templateNext = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_NEXT, 74, 25)
    panel.templateNext:SetPoint("TOPLEFT", 80, -195)
    panel.templateApply = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_TEMPLATE_APPLY, 72, 25)
    panel.templateApply:SetPoint("TOPLEFT", 160, -195)
    panel.templateSave = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_TEMPLATE_SAVE, 82, 25)
    panel.templateSave:SetPoint("TOPLEFT", 238, -195)
    panel.templateDelete = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_DELETE, 86, 25)
    panel.templateDelete:SetPoint("TOPLEFT", 326, -195)
    panel.templatePrevious:SetScript("OnClick", function()
        local templates = Addon.MailSender:GetTemplates()
        panel.templateIndex = #templates > 0 and ((panel.templateIndex - 2) % #templates) + 1 or 0
        Runtime:RefreshSendView()
    end)
    panel.templateNext:SetScript("OnClick", function()
        local templates = Addon.MailSender:GetTemplates()
        panel.templateIndex = #templates > 0 and (panel.templateIndex % #templates) + 1 or 0
        Runtime:RefreshSendView()
    end)
    panel.templateApply:SetScript("OnClick", function()
        local template = Runtime:GetSelectedTemplate()
        if template then
            local recipients = Addon.MailSender:ApplyTemplate(template.id)
            if recipients then setText(panel.massRecipients, recipients) end
        end
        Runtime:RefreshSendView()
    end)
    panel.templateSave:SetScript("OnClick", function()
        local templateID = Addon.MailSender:SaveTemplate(getText(panel.massRecipients))
        if templateID then panel.templateIndex = #Addon.MailSender:GetTemplates() end
        Runtime:RefreshSendView()
    end)
    panel.templateDelete:SetScript("OnClick", function()
        local template = Runtime:GetSelectedTemplate()
        if template then Addon.MailSender:DeleteTemplate(template.id) end
        Runtime:RefreshSendView()
    end)
end

local function buildSendView(panel)
    local view = CreateFrame("Frame", nil, panel)
    view:SetPoint("TOPLEFT", 14, -42)
    view:SetPoint("BOTTOMRIGHT", -14, 14)
    panel.sendViewFrame = view
    panel.sendViews = {}
    panel.sendTabButtons = {}
    panel.sendView = "quick"
    panel.ruleIndex = 1
    panel.rulePage = 1
    panel.templateIndex = 1
    panel.recipientPage = 1

    panel.recipientTitle = Addon.Widgets:CreateLabel(view, "GameFontNormal", "LEFT")
    panel.recipientTitle:SetPoint("TOPLEFT", 0, 0)
    panel.recipientTitle:SetText(Addon.L.MAILBOX_SEND_RECIPIENTS)
    panel.recipientSelector = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_SELECT_RECIPIENT, 262, 28)
    panel.recipientSelector:SetPoint("TOPLEFT", 0, -23)
    panel.favorite = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_SEND_FAVORITE, 140, 28)
    panel.favorite:SetPoint("LEFT", panel.recipientSelector, "RIGHT", 10, 0)
    panel.favorite:SetScript("OnClick", function()
        Addon.MailSender:ToggleFavorite(getText(SendMailNameEditBox))
        Runtime:RefreshSendView()
    end)
    for index, definition in ipairs(SEND_VIEWS) do
        local width = index == 3 and 136 or 132
        local button = Addon.Widgets:CreateButton(view, Addon.L[definition.labelKey], width, 28)
        button:SetPoint("TOPLEFT", (index - 1) * 138, -65)
        button:SetScript("OnClick", function()
            panel.sendView = definition.key
            panel.recipientPopup:Hide()
            Runtime:RefreshSendView()
        end)
        panel.sendTabButtons[definition.key] = button
    end
    buildQuickView(panel, view)
    buildRulesView(panel, view)
    buildMassView(panel, view)

    local popup = CreateFrame("Frame", nil, view, BACKDROP_TEMPLATE)
    popup:SetSize(262, 50)
    popup:SetPoint("TOPLEFT", panel.recipientSelector, "BOTTOMLEFT", 0, -2)
    popup:SetFrameLevel((view:GetFrameLevel() or 1) + 30)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    Addon.Widgets:ApplyPanelStyle(popup, "content")
    popup:Hide()
    panel.recipientPopup = popup
    panel.recipientRows = {}
    for rowIndex = 1, RECIPIENTS_PER_PAGE do
        local row = Addon.Widgets:CreateButton(popup, "", 242, 25, "row")
        row:SetPoint("TOPLEFT", 10, -9 - ((rowIndex - 1) * 27))
        row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(selfRow)
            if selfRow.recipient then setText(SendMailNameEditBox, selfRow.recipient) end
            popup:Hide()
            Runtime:RefreshSendView()
        end)
        panel.recipientRows[rowIndex] = row
    end
    panel.recipientEmpty = Addon.Widgets:CreateLabel(popup, "GameFontDisableSmall", "LEFT")
    panel.recipientEmpty:SetPoint("TOPLEFT", 12, -17)
    panel.recipientEmpty:SetText(Addon.L.MAILBOX_SEND_NO_RECIPIENTS)
    panel.recipientPrevious = Addon.Widgets:CreateButton(popup, Addon.L.MAILBOX_SEND_PREVIOUS, 72, 23)
    panel.recipientPrevious:SetPoint("BOTTOMLEFT", 10, 7)
    panel.recipientPageLabel = Addon.Widgets:CreateLabel(popup, "GameFontDisableSmall", "CENTER")
    panel.recipientPageLabel:SetPoint("BOTTOMLEFT", 87, 9)
    panel.recipientPageLabel:SetSize(88, 18)
    panel.recipientNext = Addon.Widgets:CreateButton(popup, Addon.L.MAILBOX_SEND_NEXT, 72, 23)
    panel.recipientNext:SetPoint("BOTTOMLEFT", 180, 7)
    panel.recipientPrevious:SetScript("OnClick", function()
        panel.recipientPage = math.max(1, (panel.recipientPage or 1) - 1)
        Runtime:RefreshRecipientDropdown()
    end)
    panel.recipientNext:SetScript("OnClick", function()
        panel.recipientPage = (panel.recipientPage or 1) + 1
        Runtime:RefreshRecipientDropdown()
    end)
    popup:SetScript("OnMouseWheel", function(_, delta)
        panel.recipientPage = math.max(1, (panel.recipientPage or 1) + (delta < 0 and 1 or -1))
        Runtime:RefreshRecipientDropdown()
    end)
    panel.recipientSelector:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            panel.recipientPage = 1
            popup:Show()
            Runtime:RefreshRecipientDropdown()
        end
    end)

    panel.sendPreview = Addon.Widgets:CreateLabel(view, "GameFontDisableSmall", "LEFT")
    panel.sendPreview:SetPoint("BOTTOMLEFT", 0, 31)
    panel.sendPreview:SetPoint("RIGHT", 0, 0)
    panel.sendStatus = Addon.Widgets:CreateLabel(view, "GameFontHighlightSmall", "LEFT")
    panel.sendStatus:SetPoint("BOTTOMLEFT", 0, 8)
    panel.sendStatus:SetPoint("BOTTOMRIGHT", -82, 9)
    panel.sendStop = Addon.Widgets:CreateButton(view, Addon.L.MAILBOX_QUEUE_STOP, 72, 23)
    panel.sendStop:SetPoint("BOTTOMRIGHT", 0, 1)
    panel.sendStop:SetScript("OnClick", function()
        Addon.MailSender:StopQueue("user")
        Runtime:RefreshSendView()
    end)
end

function Runtime:BuildPanel()
    if self.panel then
        self:EnsureInboxHooks()
        self:EnsureSendHooks()
        return self.panel
    end
    if not MailFrame then return nil end
    local panel = CreateFrame("Frame", "VaultloomMailboxPanel", MailFrame, BACKDROP_TEMPLATE)
    panel:SetSize(INBOX_PANEL_WIDTH, INBOX_PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 7, -26)
    Addon.Widgets:ApplyPanelStyle(panel, "content")
    panel.title = Addon.Widgets:CreateLabel(panel, "GameFontNormalLarge", "LEFT")
    panel.title:SetPoint("TOPLEFT", 14, -13)
    panel.title:SetPoint("TOPRIGHT", -14, -13)
    buildInboxView(panel)
    buildSendView(panel)
    panel:SetScript("OnShow", function() Runtime:RefreshPanel() end)
    panel:SetScript("OnHide", function()
        if panel.recipientPopup then panel.recipientPopup:Hide() end
    end)
    panel:Hide()
    self.panel = panel
    self:EnsureInboxHooks()
    self:EnsureSendHooks()
    return panel
end

function Runtime:OnEnable()
    self.enabled = true
    Addon.StateStore:Subscribe("mailbox.snapshots", self, function() Runtime:RefreshPanel() end)
    Addon.StateStore:Subscribe("mailbox.queue", self, function() Runtime:RefreshPanel() end)
    Addon.StateStore:Subscribe("mailbox.send", self, function() Runtime:RefreshPanel() end)
    Addon.EventBus:Subscribe("MAIL_SHOW", self, function()
        Runtime:BuildPanel()
        if Addon.MailSender then Addon.MailSender:Publish() end
        Runtime:RefreshPanel()
    end)
    Addon.EventBus:Subscribe("MAIL_CLOSED", self, function()
        if Addon.MailSender then Addon.MailSender:OnMailClosed() end
        Runtime:RefreshPanel()
    end)
    Addon.EventBus:Subscribe("MAIL_SEND_SUCCESS", self, function()
        if Addon.MailSender then Addon.MailSender:OnSendSuccess() end
    end)
    Addon.EventBus:Subscribe("MAIL_FAILED", self, function()
        if Addon.MailSender then Addon.MailSender:OnSendFailed() end
    end)
    Addon.EventBus:Subscribe("MAIL_SEND_INFO_UPDATE", self, function() Runtime:RefreshSendView() end)
    Addon.EventBus:Subscribe("BAG_UPDATE_DELAYED", self, function() Runtime:RefreshSendView() end)
    if Addon.MailSender then Addon.MailSender:Publish() end
    if Addon.Mailbox and Addon.Mailbox:IsOpen() then
        self:BuildPanel()
        self:RefreshPanel()
    end
end

function Runtime:OnDisable()
    self.enabled = false
    if Addon.Mailbox and Addon.Mailbox:GetQueueState().active then
        Addon.Mailbox:StopCollect("disabled", true)
    end
    if Addon.MailSender and Addon.MailSender:GetQueueState().active then
        Addon.MailSender:StopQueue("disabled", true)
    end
    if self.panel then self.panel:Hide() end
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "include_inventory" and Addon.Mailbox then Addon.Mailbox:PublishSnapshots() end
    self:RefreshPanel()
end

function Runtime:OnSettingsReset()
    if Addon.Mailbox then Addon.Mailbox:PublishSnapshots() end
    self:RefreshPanel()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Mailbox feature runtime.")
end
