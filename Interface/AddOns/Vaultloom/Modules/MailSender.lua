local _, Addon = ...

local Sender = {
    queue = {
        active = false,
        kind = nil,
        status = "idle",
        processedLetters = 0,
        processedAttachments = 0,
        processedItemUnits = 0,
    },
    preview = nil,
    timerToken = 0,
    pendingManualRecipient = nil,
    lastStatus = "idle",
}
Addon.MailSender = Sender

local FEATURE_ID = "mailbox"
local FALLBACK_ATTACHMENTS_MAX = 12
local MAX_RECENT = 20
local MAX_FAVORITES = 30
local MAX_RULES = 50
local MAX_TEMPLATES = 20
local MAX_MASS_RECIPIENTS = 100
local SEND_TIMEOUT = 12

local function getSetting(settingKey, fallback)
    if Addon.FeatureRegistry and Addon.FeatureRegistry:GetDefinition(FEATURE_ID) then
        local value = Addon.FeatureRegistry:GetSetting(FEATURE_ID, settingKey)
        if value ~= nil then return value end
    end
    return fallback
end

local function featureEnabled()
    return Addon.FeatureRegistry and Addon.FeatureRegistry:IsEnabled(FEATURE_ID) == true
end

local function getText(editBox)
    if editBox and type(editBox.GetText) == "function" then
        local ok, value = pcall(editBox.GetText, editBox)
        if ok then return tostring(value or "") end
    end
    return ""
end

local function setText(editBox, value)
    if editBox and type(editBox.SetText) == "function" then
        pcall(editBox.SetText, editBox, tostring(value or ""))
        return true
    end
    return false
end

local function getSendDatabase()
    local db = Addon.Database:Get()
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.recentRecipients = type(db.mailbox.recentRecipients) == "table"
        and db.mailbox.recentRecipients or {}
    db.mailbox.send = type(db.mailbox.send) == "table" and db.mailbox.send or {}
    local send = db.mailbox.send
    send.favorites = type(send.favorites) == "table" and send.favorites or {}
    send.rules = type(send.rules) == "table" and send.rules or {}
    send.templates = type(send.templates) == "table" and send.templates or {}
    send.nextRuleID = math.max(1, math.floor(tonumber(send.nextRuleID) or 1))
    send.nextTemplateID = math.max(1, math.floor(tonumber(send.nextTemplateID) or 1))
    return db.mailbox, send
end

local function currentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
        or Addon.WoWApi:GetCurrentCharacterIdentity()
    return type(identity) == "table" and identity.key or ""
end

local function isSelfRecipient(recipient)
    recipient = Addon.MailSendLogic:NormalizeRecipient(recipient)
    if not recipient then return false end
    local identity = Addon.StateStore:Get("character.identity")
        or Addon.WoWApi:GetCurrentCharacterIdentity()
    local name = type(identity) == "table" and tostring(identity.name or "") or ""
    local key = type(identity) == "table" and tostring(identity.key or "") or ""
    local needle = string.lower(recipient)
    return needle == string.lower(name) or needle == string.lower(key)
end

local function attachmentMaximum()
    return math.max(1, math.floor(tonumber(ATTACHMENTS_MAX_SEND) or FALLBACK_ATTACHMENTS_MAX))
end

local function bagIDs()
    local indices = Enum and Enum.BagIndex or {}
    local values = {
        indices.Backpack or BACKPACK_CONTAINER or 0,
        indices.Bag_1 or 1,
        indices.Bag_2 or 2,
        indices.Bag_3 or 3,
        indices.Bag_4 or 4,
        indices.ReagentBag or 5,
    }
    local result, seen = {}, {}
    for _, value in ipairs(values) do
        value = tonumber(value)
        if value ~= nil and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    return result
end

local function containerSlots(bagID)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, count = pcall(C_Container.GetContainerNumSlots, bagID)
        if ok then return math.max(0, math.floor(tonumber(count) or 0)) end
    end
    return 0
end

local function containerInfo(bagID, slotID)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

local function itemMetadata(value)
    local itemID = Addon.MailLogic:ParseItemID(value)
    local classID, subClassID, equipLoc
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, resolvedID, _, _, resolvedEquipLoc, _, resolvedClassID, resolvedSubClassID = pcall(
            C_Item.GetItemInfoInstant,
            value or itemID
        )
        if ok then
            itemID = tonumber(resolvedID) or itemID
            equipLoc = type(resolvedEquipLoc) == "string" and resolvedEquipLoc or ""
            classID = tonumber(resolvedClassID)
            subClassID = tonumber(resolvedSubClassID)
        end
    end
    local itemName = itemID and Addon.WoWApi:GetItemDisplayName(itemID) or nil
    return {
        itemID = itemID,
        itemName = itemName,
        classID = classID,
        subClassID = subClassID,
        equipLoc = equipLoc or "",
    }
end

local function itemIsBound(bagID, slotID, info)
    if type(info) == "table" and info.isBound == true then return true end
    if C_Item and type(C_Item.IsBound) == "function"
        and ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function"
    then
        local okLocation, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bagID, slotID)
        if okLocation and location then
            local ok, bound = pcall(C_Item.IsBound, location)
            if ok then return bound == true end
        end
    end
    return false
end

local function currentAttachmentCount()
    local count = 0
    for index = 1, attachmentMaximum() do
        local present = false
        if type(HasSendMailItem) == "function" then
            local ok, value = pcall(HasSendMailItem, index)
            present = ok and value == true
        elseif type(GetSendMailItem) == "function" then
            local ok, value = pcall(GetSendMailItem, index)
            present = ok and value ~= nil
        end
        if present then count = count + 1 end
    end
    return count
end

local function attachmentSeed()
    if type(GetSendMailItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetSendMailItemLink, 1)
    if not ok or type(link) ~= "string" or link == "" then return nil end
    local seed = itemMetadata(link)
    seed.itemLink = link
    if type(GetSendMailItem) == "function" then
        local infoOK, name, itemID, _, count = pcall(GetSendMailItem, 1)
        if infoOK then
            seed.itemName = type(name) == "string" and name or seed.itemName
            seed.itemID = tonumber(itemID) or seed.itemID
            seed.count = math.max(1, math.floor(tonumber(count) or 1))
        end
    end
    return seed
end

local function composeValues()
    return {
        recipient = getText(SendMailNameEditBox),
        subject = getText(SendMailSubjectEditBox),
        body = getText(SendMailBodyEditBox),
    }
end

local function setCompose(letter)
    setText(SendMailNameEditBox, letter and letter.recipient)
    setText(SendMailSubjectEditBox, letter and letter.subject)
    setText(SendMailBodyEditBox, letter and letter.body)
end

local function sendFrameVisible()
    return SendMailFrame
        and (type(SendMailFrame.IsShown) ~= "function" or SendMailFrame:IsShown())
end

local function composeHasMoneyOrCOD()
    local amount = 0
    if SendMailMoney and type(MoneyInputFrame_GetCopper) == "function" then
        local ok, value = pcall(MoneyInputFrame_GetCopper, SendMailMoney)
        if ok then amount = math.max(0, tonumber(value) or 0) end
    end
    return amount > 0
end

local function sendPace()
    local pace = tostring(getSetting("send_pace", "normal"))
    return pace == "safe" and 0.75 or pace == "fast" and 0.25 or 0.45
end

function Sender:ScanBags()
    local protectEquipment = getSetting("protect_equipment", true) ~= false
    local result = {}
    for _, bagID in ipairs(bagIDs()) do
        for slotID = 1, containerSlots(bagID) do
            local info = containerInfo(bagID, slotID)
            local itemID = tonumber(info and info.itemID)
            local count = math.max(0, math.floor(tonumber(
                info and (info.stackCount or info.quantity or info.count)
            ) or 0))
            if itemID and count > 0 then
                local link = info.hyperlink or info.itemLink
                local metadata = itemMetadata(link or itemID)
                local locked = info.isLocked == true
                local bound = itemIsBound(bagID, slotID, info)
                local equipment = metadata.equipLoc ~= ""
                result[#result + 1] = {
                    bagID = bagID,
                    slotID = slotID,
                    itemID = itemID,
                    itemName = metadata.itemName,
                    itemLink = link,
                    count = count,
                    classID = metadata.classID,
                    subClassID = metadata.subClassID,
                    equipLoc = metadata.equipLoc,
                    eligible = not locked and not bound and (not protectEquipment or not equipment),
                    locked = locked,
                    bound = bound,
                    equipment = equipment,
                }
            end
        end
    end
    return result
end

function Sender:GetQueueState()
    return self.queue
end

function Sender:GetPreview()
    return self.preview
end

function Sender:Publish()
    local _, send = getSendDatabase()
    local queue = self.queue or {}
    Addon.StateStore:Set("mailbox.send", {
        active = queue.active == true,
        kind = queue.kind,
        status = queue.status or "idle",
        reason = queue.reason,
        processedLetters = queue.processedLetters or 0,
        processedAttachments = queue.processedAttachments or 0,
        processedItemUnits = queue.processedItemUnits or 0,
        totalLetters = queue.totalLetters or 0,
        rules = #send.rules,
        templates = #send.templates,
        favorites = #send.favorites,
        preview = self.preview and self.preview.summary or nil,
        lastStatus = self.lastStatus,
    })
end

function Sender:RecordRecent(recipient)
    if getSetting("remember_recipients", true) == false then return false end
    recipient = Addon.MailSendLogic:NormalizeRecipient(recipient)
    if not recipient or isSelfRecipient(recipient) then return false end
    local mailbox = getSendDatabase()
    local recent = mailbox.recentRecipients
    local needle = string.lower(recipient)
    for index = #recent, 1, -1 do
        if string.lower(tostring(recent[index])) == needle then table.remove(recent, index) end
    end
    table.insert(recent, 1, recipient)
    while #recent > MAX_RECENT do table.remove(recent) end
    self:Publish()
    return true
end

function Sender:PrepareManualSend(recipient)
    if self.queue and self.queue.active then return false end
    recipient = Addon.MailSendLogic:NormalizeRecipient(recipient or getText(SendMailNameEditBox))
    self.pendingManualRecipient = recipient
    return recipient ~= nil
end

function Sender:CommitManualSend()
    local recipient = self.pendingManualRecipient
    self.pendingManualRecipient = nil
    return recipient and self:RecordRecent(recipient) or false
end

function Sender:GetRecipientSuggestions(limit, query)
    local mailbox, send = getSendDatabase()
    local roster = Addon.WarbandRoster and Addon.WarbandRoster:GetAll() or {}
    return Addon.MailSendLogic:BuildRecipientSuggestions(
        send.favorites,
        mailbox.recentRecipients,
        roster,
        currentCharacterKey(),
        limit,
        query
    )
end

function Sender:IsFavorite(recipient)
    recipient = Addon.MailSendLogic:NormalizeRecipient(recipient)
    if not recipient then return false end
    local _, send = getSendDatabase()
    local needle = string.lower(recipient)
    for _, value in ipairs(send.favorites) do
        if string.lower(tostring(value)) == needle then return true end
    end
    return false
end

function Sender:ToggleFavorite(recipient)
    recipient = Addon.MailSendLogic:NormalizeRecipient(recipient or getText(SendMailNameEditBox))
    if not recipient or isSelfRecipient(recipient) then return false end
    local _, send = getSendDatabase()
    local needle = string.lower(recipient)
    for index, value in ipairs(send.favorites) do
        if string.lower(tostring(value)) == needle then
            table.remove(send.favorites, index)
            self.lastStatus = "favorite_removed"
            self:Publish()
            return true
        end
    end
    table.insert(send.favorites, 1, recipient)
    while #send.favorites > MAX_FAVORITES do table.remove(send.favorites) end
    self.lastStatus = "favorite_added"
    self:Publish()
    return true
end

function Sender:GetRules()
    local _, send = getSendDatabase()
    return send.rules
end

function Sender:AddRuleFromCompose(matchType, keepCount)
    local values = composeValues()
    local recipient = Addon.MailSendLogic:NormalizeRecipient(values.recipient)
    local seed = attachmentSeed()
    if not recipient or isSelfRecipient(recipient) then
        self.lastStatus = "recipient_required"
        self:Publish()
        return false
    end
    if not seed or not seed.itemID then
        self.lastStatus = "seed_required"
        self:Publish()
        return false
    end
    if matchType ~= "item" and matchType ~= "subclass" then return false end
    if matchType == "subclass" and (seed.classID == nil or seed.subClassID == nil) then
        self.lastStatus = "item_data_missing"
        self:Publish()
        return false
    end

    local _, send = getSendDatabase()
    local rule = Addon.MailSendLogic:NormalizeRule({
        id = send.nextRuleID,
        enabled = true,
        name = seed.itemName or ("#" .. tostring(seed.itemID)),
        recipient = recipient,
        matchType = matchType,
        itemID = seed.itemID,
        classID = seed.classID,
        subClassID = seed.subClassID,
        keepCount = keepCount,
        subject = values.subject,
    })
    if not rule then return false end
    send.nextRuleID = send.nextRuleID + 1
    table.insert(send.rules, rule)
    while #send.rules > MAX_RULES do table.remove(send.rules, 1) end
    self.lastStatus = "rule_saved"
    self.preview = nil
    self:Publish()
    return rule.id
end

function Sender:DeleteRule(ruleID)
    local _, send = getSendDatabase()
    ruleID = tonumber(ruleID)
    for index, rule in ipairs(send.rules) do
        if tonumber(rule.id) == ruleID then
            table.remove(send.rules, index)
            self.lastStatus = "rule_deleted"
            self.preview = nil
            self:Publish()
            return true
        end
    end
    return false
end

function Sender:ToggleRule(ruleID)
    local _, send = getSendDatabase()
    ruleID = tonumber(ruleID)
    for _, rule in ipairs(send.rules) do
        if tonumber(rule.id) == ruleID then
            rule.enabled = rule.enabled == false
            self.lastStatus = rule.enabled and "rule_enabled" or "rule_disabled"
            self.preview = nil
            self:Publish()
            return true
        end
    end
    return false
end

function Sender:MoveRule(ruleID, direction)
    local _, send = getSendDatabase()
    ruleID = tonumber(ruleID)
    direction = tonumber(direction) and tonumber(direction) < 0 and -1 or 1
    for index, rule in ipairs(send.rules) do
        if tonumber(rule.id) == ruleID then
            local target = index + direction
            if target < 1 or target > #send.rules then return false end
            send.rules[index], send.rules[target] = send.rules[target], send.rules[index]
            self.preview = nil
            self:Publish()
            return true
        end
    end
    return false
end

function Sender:BuildRulePreview()
    local values = composeValues()
    local usableRules = {}
    for _, rule in ipairs(self:GetRules()) do
        if type(rule) == "table" and not isSelfRecipient(rule.recipient) then
            usableRules[#usableRules + 1] = rule
        end
    end
    self.preview = Addon.MailSendLogic:BuildPlan(
        self:ScanBags(),
        usableRules,
        attachmentMaximum(),
        values.subject,
        values.body
    )
    self.lastStatus = #self.preview.letters > 0 and "preview_ready" or "nothing_to_send"
    self:Publish()
    return self.preview
end

local function freeAttachmentSlots()
    local result = {}
    for index = 1, attachmentMaximum() do
        local occupied = false
        if type(HasSendMailItem) == "function" then
            local ok, value = pcall(HasSendMailItem, index)
            occupied = ok and value == true
        elseif type(GetSendMailItem) == "function" then
            local ok, value = pcall(GetSendMailItem, index)
            occupied = ok and value ~= nil
        end
        if not occupied then result[#result + 1] = index end
    end
    return result
end

function Sender:AttachAction(action, attachmentIndex)
    if type(action) ~= "table" or type(ClickSendMailItemButton) ~= "function" then return false end
    local info = containerInfo(action.bagID, action.slotID)
    local itemID = tonumber(info and info.itemID)
    local stackCount = math.max(0, math.floor(tonumber(
        info and (info.stackCount or info.quantity or info.count)
    ) or 0))
    local sendCount = math.max(1, math.floor(tonumber(action.count) or stackCount))
    if itemID ~= tonumber(action.itemID) or stackCount < sendCount or info.isLocked == true then
        return false
    end
    if type(ClearCursor) == "function" then pcall(ClearCursor) end
    local ok
    if sendCount < stackCount and C_Container and type(C_Container.SplitContainerItem) == "function" then
        ok = pcall(C_Container.SplitContainerItem, action.bagID, action.slotID, sendCount)
    elseif C_Container and type(C_Container.PickupContainerItem) == "function" then
        ok = pcall(C_Container.PickupContainerItem, action.bagID, action.slotID)
    elseif type(PickupContainerItem) == "function" then
        ok = pcall(PickupContainerItem, action.bagID, action.slotID)
    end
    if not ok then return false end
    local attached = pcall(ClickSendMailItemButton, attachmentIndex)
    local present = false
    if attached and type(HasSendMailItem) == "function" then
        local presentOK, value = pcall(HasSendMailItem, attachmentIndex)
        present = presentOK and value == true
    elseif attached and type(GetSendMailItem) == "function" then
        local presentOK, value = pcall(GetSendMailItem, attachmentIndex)
        present = presentOK and value ~= nil
    end
    if type(ClearCursor) == "function" then pcall(ClearCursor) end
    return attached == true and present
end

function Sender:QuickAttach(mode)
    if not featureEnabled() or not sendFrameVisible() then return false end
    if (self.queue and self.queue.active)
        or (Addon.Mailbox and Addon.Mailbox:GetQueueState().active)
    then
        self.lastStatus = "queue_busy"
        self:Publish()
        return false
    end
    local slots = freeAttachmentSlots()
    if #slots == 0 then
        self.lastStatus = "attachments_full"
        self:Publish()
        return false
    end
    local seed = (mode == "same" or mode == "type") and attachmentSeed() or {}
    if (mode == "same" or mode == "type") and not seed then
        self.lastStatus = "seed_required"
        self:Publish()
        return false
    end
    local actions = Addon.MailSendLogic:BuildQuickActions(self:ScanBags(), seed, mode, #slots)
    local attached = 0
    for index, action in ipairs(actions) do
        if self:AttachAction(action, slots[index]) then attached = attached + 1 end
    end
    self.lastStatus = attached > 0 and "quick_attached" or "nothing_to_send"
    self:Publish()
    return attached > 0, attached
end

function Sender:GetTemplates()
    local _, send = getSendDatabase()
    return send.templates
end

function Sender:SaveTemplate(recipientText)
    local values = composeValues()
    local recipients = Addon.MailSendLogic:ParseRecipientList(recipientText)
    if #recipients == 0 then recipients = Addon.MailSendLogic:ParseRecipientList(values.recipient) end
    if #recipients == 0 or (values.subject == "" and values.body == "") then
        self.lastStatus = "template_incomplete"
        self:Publish()
        return false
    end
    local _, send = getSendDatabase()
    local template = {
        id = send.nextTemplateID,
        name = values.subject ~= "" and values.subject:sub(1, 64) or recipients[1],
        recipients = recipients,
        subject = values.subject:sub(1, 128),
        body = values.body:sub(1, 4000),
    }
    send.nextTemplateID = send.nextTemplateID + 1
    table.insert(send.templates, template)
    while #send.templates > MAX_TEMPLATES do table.remove(send.templates, 1) end
    self.lastStatus = "template_saved"
    self:Publish()
    return template.id
end

function Sender:ApplyTemplate(templateID)
    templateID = tonumber(templateID)
    for _, template in ipairs(self:GetTemplates()) do
        if tonumber(template.id) == templateID then
            local recipients = type(template.recipients) == "table" and template.recipients or {}
            setText(SendMailNameEditBox, recipients[1] or "")
            setText(SendMailSubjectEditBox, template.subject)
            setText(SendMailBodyEditBox, template.body)
            self.lastStatus = "template_applied"
            self:Publish()
            return table.concat(recipients, ", ")
        end
    end
    return nil
end

function Sender:DeleteTemplate(templateID)
    templateID = tonumber(templateID)
    local _, send = getSendDatabase()
    for index, template in ipairs(send.templates) do
        if tonumber(template.id) == templateID then
            table.remove(send.templates, index)
            self.lastStatus = "template_deleted"
            self:Publish()
            return true
        end
    end
    return false
end

function Sender:BuildMassPreview(recipientText)
    local values = composeValues()
    local recipients = Addon.MailSendLogic:ParseRecipientList(recipientText)
    local filtered = {}
    for _, recipient in ipairs(recipients) do
        if not isSelfRecipient(recipient) and #filtered < MAX_MASS_RECIPIENTS then
            filtered[#filtered + 1] = recipient
        end
    end
    self.preview = Addon.MailSendLogic:BuildMassPlan(filtered, values.subject, values.body)
    self.lastStatus = #self.preview.letters > 0 and "preview_ready" or "recipient_required"
    self:Publish()
    return self.preview
end

function Sender:CanStartQueue()
    if not featureEnabled() or not Addon.Mailbox or not Addon.Mailbox:IsOpen() or not sendFrameVisible() then
        self.lastStatus = "mailbox_required"
        self:Publish()
        return false
    end
    if self.queue and self.queue.active then return false end
    if Addon.Mailbox:GetQueueState().active then
        self.lastStatus = "queue_busy"
        self:Publish()
        return false
    end
    if currentAttachmentCount() > 0 or composeHasMoneyOrCOD() then
        self.lastStatus = "clear_attachments"
        self:Publish()
        return false
    end
    if type(SendMailFrame_SendMail) ~= "function" and type(SendMail) ~= "function" then
        self.lastStatus = "send_unavailable"
        self:Publish()
        return false
    end
    return true
end

function Sender:StartRuleQueue()
    if not self:CanStartQueue() then return false end
    local plan = self:BuildRulePreview()
    if not plan or #plan.letters == 0 then return false end
    self.timerToken = self.timerToken + 1
    self.queue = {
        active = true,
        kind = "rules",
        status = "running",
        processedLetters = 0,
        processedAttachments = 0,
        processedItemUnits = 0,
        totalLetters = plan.summary.letters,
    }
    self:Publish()
    return self:SendNext()
end

function Sender:StartMassQueue(recipientText)
    if not self:CanStartQueue() then return false end
    local values = composeValues()
    if values.subject == "" and values.body == "" then
        self.lastStatus = "message_required"
        self:Publish()
        return false
    end
    local plan = self:BuildMassPreview(recipientText)
    if not plan or #plan.letters == 0 then return false end
    self.timerToken = self.timerToken + 1
    self.queue = {
        active = true,
        kind = "mass",
        status = "running",
        processedLetters = 0,
        processedAttachments = 0,
        processedItemUnits = 0,
        totalLetters = #plan.letters,
        massLetters = plan.letters,
        nextMassIndex = 1,
    }
    self:Publish()
    return self:SendNext()
end

function Sender:ScheduleNext(delay)
    if not self.queue or self.queue.active ~= true then return false end
    self.timerToken = self.timerToken + 1
    local token = self.timerToken
    local function run()
        if token == Sender.timerToken and Sender.queue and Sender.queue.active then
            Sender:SendNext()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(math.max(0, tonumber(delay) or sendPace()), run)
    else
        run()
    end
    return true
end

function Sender:StopQueue(reason, silent)
    local queue = self.queue
    if type(queue) ~= "table" then return false end
    local wasActive = queue.active == true
    queue.active = false
    queue.status = reason == "complete" and "complete"
        or reason == "failed" and "failed"
        or "stopped"
    queue.reason = reason or "stopped"
    queue.pending = nil
    self.timerToken = self.timerToken + 1
    self.lastStatus = queue.status
    self:Publish()
    if wasActive and silent ~= true and getSetting("show_summary", true) ~= false then
        if reason == "complete" then
            Addon:Print(string.format(
                Addon.L.MAILBOX_SEND_QUEUE_DONE,
                queue.processedLetters or 0,
                queue.processedAttachments or 0
            ))
        else
            Addon:Print(Addon.L.MAILBOX_SEND_QUEUE_STOPPED)
        end
    end
    if wasActive and Addon.Sound then
        Addon.Sound:Play(reason == "complete" and "toggleOn" or "toggleOff")
    end
    return wasActive
end

function Sender:GetNextLetter()
    local queue = self.queue
    if queue.kind == "mass" then
        return queue.massLetters and queue.massLetters[queue.nextMassIndex] or nil
    end
    local plan = self:BuildRulePreview()
    queue.totalLetters = math.max(queue.totalLetters or 0, (queue.processedLetters or 0) + #plan.letters)
    return plan.letters[1]
end

function Sender:SendNext()
    local queue = self.queue
    if not queue or queue.active ~= true or queue.pending then return false end
    if not Addon.Mailbox:IsOpen() or not sendFrameVisible() then
        self:StopQueue("closed")
        return false
    end
    local letter = self:GetNextLetter()
    if not letter then
        self:StopQueue("complete")
        return true
    end
    if currentAttachmentCount() > 0 then
        self:StopQueue("attachments")
        return false
    end
    for index, action in ipairs(letter.actions or {}) do
        if not self:AttachAction(action, index) then
            self:StopQueue("failed")
            self.lastStatus = "attach_failed"
            self:Publish()
            return false
        end
    end
    setCompose(letter)
    queue.pending = {
        recipient = letter.recipient,
        attachments = #(letter.actions or {}),
        itemUnits = letter.itemUnits or 0,
        startedAt = type(GetTime) == "function" and GetTime() or 0,
    }
    self:Publish()

    local ok, errorMessage
    if type(SendMailFrame_SendMail) == "function" then
        ok, errorMessage = pcall(SendMailFrame_SendMail)
    else
        ok, errorMessage = pcall(SendMail, letter.recipient, letter.subject, letter.body)
    end
    if not ok then
        Addon.Logger:Write("WARN", "mailbox.send", "Send failed: %s", tostring(errorMessage))
        self:StopQueue("failed")
        return false
    end

    local pending = queue.pending
    local timeoutToken = self.timerToken
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(SEND_TIMEOUT, function()
            if Sender.timerToken == timeoutToken
                and Sender.queue and Sender.queue.active
                and Sender.queue.pending == pending
            then
                Sender.lastStatus = "timeout"
                Sender:StopQueue("failed")
            end
        end)
    end
    return true
end

function Sender:OnSendSuccess()
    local queue = self.queue
    if not queue or queue.active ~= true or not queue.pending then
        return self:CommitManualSend()
    end
    local pending = queue.pending
    queue.pending = nil
    queue.processedLetters = (queue.processedLetters or 0) + 1
    queue.processedAttachments = (queue.processedAttachments or 0) + (pending.attachments or 0)
    queue.processedItemUnits = (queue.processedItemUnits or 0) + (pending.itemUnits or 0)
    if queue.kind == "mass" then queue.nextMassIndex = (queue.nextMassIndex or 1) + 1 end
    self:RecordRecent(pending.recipient)
    self.lastStatus = "send_success"
    self:Publish()
    return self:ScheduleNext(sendPace())
end

function Sender:OnSendFailed()
    self.pendingManualRecipient = nil
    if self.queue and self.queue.active then
        self.lastStatus = "send_failed"
        return self:StopQueue("failed")
    end
    return false
end

function Sender:OnMailClosed()
    self.pendingManualRecipient = nil
    if self.queue and self.queue.active then self:StopQueue("closed", true) end
end
