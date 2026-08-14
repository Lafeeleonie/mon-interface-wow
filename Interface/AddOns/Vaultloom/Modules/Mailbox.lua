local _, Addon = ...

local Module = {
    id = "mailbox.snapshots",
    defaultEnabled = true,
}

local FEATURE_ID = "mailbox"
local ATTACHMENT_FALLBACK_MAX = 16
local QUEUE_DELAY = 0.20
local COMMAND_SETTLE_TIMEOUT = 1.50

local Service = {
    enabled = false,
    mailboxOpen = false,
    revision = 0,
    inboxRevision = 0,
    generation = 0,
    timerToken = 0,
    alertShown = false,
    queue = {
        active = false,
        filterKey = "all",
        failed = {},
        staleActions = {},
        processedKeys = {},
        processedMessages = 0,
        collectedAttachments = 0,
        collectedMoney = 0,
        skipped = 0,
        status = "idle",
    },
}
Addon.Mailbox = Service

local function serverTime()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and tonumber(value) then return math.max(0, math.floor(tonumber(value))) end
    end
    return type(time) == "function" and math.max(0, tonumber(time()) or 0) or 0
end

local function elapsedTime()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and tonumber(value) then return math.max(0, tonumber(value)) end
    end
    return serverTime()
end

local function currentIdentity()
    return Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
end

local function getFeatureState()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or { states = {} }
    db.features.states = type(db.features.states) == "table" and db.features.states or {}
    local state = db.features.states[FEATURE_ID]
    return type(state) == "table" and state or nil
end

local function getSetting(settingKey, fallback)
    if Addon.FeatureRegistry and Addon.FeatureRegistry:GetDefinition(FEATURE_ID) then
        local value = Addon.FeatureRegistry:GetSetting(FEATURE_ID, settingKey)
        if value ~= nil then return value end
    end
    local state = getFeatureState()
    local value = state and type(state.settings) == "table" and state.settings[settingKey] or nil
    return value == nil and fallback or value
end

local function isMailboxFeatureEnabled()
    local state = getFeatureState()
    return state ~= nil and state.enabled == true
end

local function ensureMailboxDatabase()
    local db = Addon.Database:Get()
    db.mailbox = type(db.mailbox) == "table" and db.mailbox or {}
    db.mailbox.version = 2
    db.mailbox.snapshots = type(db.mailbox.snapshots) == "table" and db.mailbox.snapshots or {}
    db.mailbox.recentRecipients = type(db.mailbox.recentRecipients) == "table"
        and db.mailbox.recentRecipients or {}
    db.mailbox.send = type(db.mailbox.send) == "table" and db.mailbox.send or {}
    db.mailbox.send.favorites = type(db.mailbox.send.favorites) == "table"
        and db.mailbox.send.favorites or {}
    db.mailbox.send.rules = type(db.mailbox.send.rules) == "table"
        and db.mailbox.send.rules or {}
    db.mailbox.send.templates = type(db.mailbox.send.templates) == "table"
        and db.mailbox.send.templates or {}
    db.mailbox.send.nextRuleID = math.max(
        1,
        math.floor(tonumber(db.mailbox.send.nextRuleID) or 1)
    )
    db.mailbox.send.nextTemplateID = math.max(
        1,
        math.floor(tonumber(db.mailbox.send.nextTemplateID) or 1)
    )
    return db.mailbox
end

local function getInboxCounts()
    if type(GetInboxNumItems) ~= "function" then return 0, 0 end
    local ok, visible, total = pcall(GetInboxNumItems)
    if not ok then return 0, 0 end
    visible = math.max(0, math.floor(tonumber(visible) or 0))
    total = math.max(visible, math.floor(tonumber(total) or visible))
    return visible, total
end

local function getInboxItemLink(inboxIndex, attachmentIndex)
    if type(GetInboxItemLink) ~= "function" then return nil end
    local ok, itemLink = pcall(GetInboxItemLink, inboxIndex, attachmentIndex)
    return ok and type(itemLink) == "string" and itemLink ~= "" and itemLink or nil
end

local function getInboxAttachment(inboxIndex, attachmentIndex)
    if type(GetInboxItem) ~= "function" then return nil end
    local ok, itemName, itemID, texture, count, quality, canUse, isCurrency = pcall(
        GetInboxItem,
        inboxIndex,
        attachmentIndex
    )
    if not ok or (itemName == nil and itemID == nil and texture == nil) then return nil end
    local itemLink = getInboxItemLink(inboxIndex, attachmentIndex)
    itemID = tonumber(itemID) or Addon.MailLogic:ParseItemID(itemLink)
    return {
        slot = attachmentIndex,
        itemID = itemID and math.floor(itemID) or nil,
        itemName = type(itemName) == "string" and itemName or nil,
        itemLink = itemLink,
        icon = texture,
        count = math.max(1, math.floor(tonumber(count) or 1)),
        quality = tonumber(quality),
        canUse = canUse == true,
        isCurrency = isCurrency == true,
    }
end

local function isAuctionMail(inboxIndex, sender)
    if type(GetInboxInvoiceInfo) == "function" then
        local ok, invoiceType = pcall(GetInboxInvoiceInfo, inboxIndex)
        if ok and invoiceType ~= nil then return true end
    end
    local auctionSender = type(AUCTION_HOUSE_MAIL_FROM) == "string" and AUCTION_HOUSE_MAIL_FROM or nil
    return auctionSender ~= nil and tostring(sender or "") == auctionSender
end

local function readMessage(inboxIndex, timestamp)
    if type(GetInboxHeaderInfo) ~= "function" then return nil end
    local ok, packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft,
        itemCount, wasRead, wasReturned, textCreated, canReply, isGM,
        firstItemQuantity, firstItemLink = pcall(GetInboxHeaderInfo, inboxIndex)
    if not ok or (sender == nil and subject == nil and money == nil and itemCount == nil) then
        return nil
    end

    local attachments = {}
    local maximum = math.max(1, math.floor(tonumber(ATTACHMENTS_MAX) or ATTACHMENT_FALLBACK_MAX))
    for attachmentIndex = 1, maximum do
        local attachment = getInboxAttachment(inboxIndex, attachmentIndex)
        if attachment then attachments[#attachments + 1] = attachment end
    end

    if #attachments == 0 and type(firstItemLink) == "string" and firstItemLink ~= "" then
        attachments[1] = {
            slot = 1,
            itemID = Addon.MailLogic:ParseItemID(firstItemLink),
            itemName = firstItemLink:match("%[(.-)%]"),
            itemLink = firstItemLink,
            count = math.max(1, math.floor(tonumber(firstItemQuantity) or 1)),
            isCurrency = false,
        }
    end

    daysLeft = math.max(0, tonumber(daysLeft) or 0)
    local message = {
        inboxIndex = inboxIndex,
        packageIcon = packageIcon,
        stationeryIcon = stationeryIcon,
        sender = type(sender) == "string" and sender or "",
        subject = type(subject) == "string" and subject or "",
        money = math.max(0, math.floor(tonumber(money) or 0)),
        cod = math.max(0, math.floor(tonumber(cod) or 0)),
        daysLeft = daysLeft,
        expiresAt = timestamp + math.floor((daysLeft * 86400) + 0.5),
        itemCount = math.max(#attachments, math.floor(tonumber(itemCount) or 0)),
        wasRead = wasRead == true,
        wasReturned = wasReturned == true,
        textCreated = textCreated == true,
        canReply = canReply == true,
        isGM = isGM == true,
        isAuction = isAuctionMail(inboxIndex, sender),
        attachments = attachments,
    }
    message.key = Addon.MailLogic:BuildMessageKey(message)
    message.threadKey = Addon.MailLogic:BuildThreadKey(message)
    return message
end

function Service:ReadInbox()
    local visible, total = getInboxCounts()
    local timestamp = serverTime()
    local messages = {}
    for inboxIndex = 1, visible do
        local message = readMessage(inboxIndex, timestamp)
        if message then messages[#messages + 1] = message end
    end
    return messages, total, timestamp
end

function Service:PublishSnapshots()
    self.revision = self.revision + 1
    Addon.StateStore:Set("mailbox.snapshots", {
        revision = self.revision,
        updatedAt = serverTime(),
    })
end

function Service:ScanInbox()
    if self.enabled ~= true or self.mailboxOpen ~= true then return false end
    local identity = currentIdentity()
    if type(identity) ~= "table" or type(identity.key) ~= "string" or identity.key == "" then
        return false
    end
    local messages, total, timestamp = self:ReadInbox()
    local warningDays = getSetting("expiry_warning_days", 3)
    local snapshot = Addon.MailLogic:BuildSnapshot(
        identity.key,
        messages,
        timestamp,
        total,
        warningDays
    )
    if not Addon.Database:CommitMailboxSnapshot(identity.key, snapshot, "refresh") then
        return false
    end
    self:PublishSnapshots()
    return true
end

function Service:GetSnapshot(characterKey)
    local snapshots = ensureMailboxDatabase().snapshots
    return type(characterKey) == "string" and snapshots[characterKey] or nil
end

function Service:GetSnapshots()
    return ensureMailboxDatabase().snapshots
end

function Service:IsOpen()
    return self.mailboxOpen == true
end

function Service:GetQueueState()
    return self.queue
end

function Service:PublishQueue()
    local queue = self.queue
    Addon.StateStore:Set("mailbox.queue", {
        active = queue.active == true,
        filterKey = queue.filterKey,
        processedMessages = queue.processedMessages or 0,
        collectedAttachments = queue.collectedAttachments or 0,
        collectedMoney = queue.collectedMoney or 0,
        skipped = queue.skipped or 0,
        status = queue.status or "idle",
        reason = queue.reason,
        updatedAt = serverTime(),
    })
end

local function getBagIDs()
    local indices = Enum and Enum.BagIndex or {}
    local values = {
        indices.Backpack or BACKPACK_CONTAINER or 0,
        indices.Bag_1 or 1,
        indices.Bag_2 or 2,
        indices.Bag_3 or 3,
        indices.Bag_4 or 4,
        indices.ReagentBag,
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

local function getContainerSlots(bagID)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, count = pcall(C_Container.GetContainerNumSlots, bagID)
        if ok then return math.max(0, math.floor(tonumber(count) or 0)) end
    end
    return 0
end

local function getContainerItemInfo(bagID, slotID)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

local function getMaximumStack(itemID)
    if C_Item and type(C_Item.GetItemMaxStackSizeByID) == "function" then
        local ok, count = pcall(C_Item.GetItemMaxStackSizeByID, itemID)
        if ok and tonumber(count) then return math.max(1, math.floor(tonumber(count))) end
    end
    if type(GetItemInfo) == "function" then
        local ok, _, _, _, _, _, _, maximum = pcall(GetItemInfo, itemID)
        if ok and tonumber(maximum) then return math.max(1, math.floor(tonumber(maximum))) end
    end
    return 1
end

local function getFreeBagSlots()
    if C_Container and type(C_Container.CalculateTotalNumberOfFreeBagSlots) == "function" then
        local ok, count = pcall(C_Container.CalculateTotalNumberOfFreeBagSlots)
        if ok and tonumber(count) then return math.max(0, math.floor(tonumber(count))) end
    end
    return nil
end

function Service:CanTakeAttachment(attachment)
    if type(attachment) ~= "table" then return false end
    if attachment.isCurrency == true then return true end
    local keepFree = math.max(0, math.floor(tonumber(getSetting("keep_free_slots", 1)) or 1))
    local free = getFreeBagSlots()
    if free == nil or free > keepFree then return true end

    local itemID = tonumber(attachment.itemID)
    if not itemID then return false end
    local required = math.max(1, math.floor(tonumber(attachment.count) or 1))
    local maximum = getMaximumStack(itemID)
    if maximum <= 1 then return false end
    local capacity = 0
    for _, bagID in ipairs(getBagIDs()) do
        for slotID = 1, getContainerSlots(bagID) do
            local info = getContainerItemInfo(bagID, slotID)
            if info and tonumber(info.itemID) == itemID then
                capacity = capacity + math.max(0, maximum - math.floor(tonumber(
                    info.stackCount or info.quantity or info.count
                ) or 0))
                if capacity >= required then return true end
            end
        end
    end
    return false
end

local function commandPending()
    if C_Mail and type(C_Mail.IsCommandPending) == "function" then
        local ok, pending = pcall(C_Mail.IsCommandPending)
        return ok and pending == true
    end
    return false
end

local function setOpeningAll(opening)
    if C_Mail and type(C_Mail.SetOpeningAll) == "function" then
        pcall(C_Mail.SetOpeningAll, opening == true)
    end
end

function Service:ResetQueue(filterKey)
    self.queue = {
        active = true,
        filterKey = filterKey or "all",
        failed = {},
        staleActions = {},
        processedKeys = {},
        processedMessages = 0,
        collectedAttachments = 0,
        collectedMoney = 0,
        skipped = 0,
        status = "running",
        reason = nil,
        pending = nil,
    }
end

function Service:CompletePending(success, failureKey)
    local queue = self.queue
    local action = queue and queue.pending
    if not action then return false end
    queue.pending = nil
    if success then
        if self.inboxRevision == action.inboxRevision then
            queue.staleActions[action.actionKey] = true
        end
        if action.kind == "money" then
            queue.collectedMoney = queue.collectedMoney + math.max(0, tonumber(action.amount) or 0)
        else
            queue.collectedAttachments = queue.collectedAttachments + 1
        end
        local processedKey = action.threadKey or action.messageKey
        if not queue.processedKeys[processedKey] then
            queue.processedKeys[processedKey] = true
            queue.processedMessages = queue.processedMessages + 1
        end
    else
        queue.failed[action.actionKey] = true
        if failureKey then queue.failed[failureKey] = true end
        queue.skipped = queue.skipped + 1
    end
    self:PublishQueue()
    return true
end

function Service:FindNextAction(messages)
    local queue = self.queue
    local warningDays = getSetting("expiry_warning_days", 3)
    local timestamp = serverTime()
    local blockedByBags = false
    for _, message in ipairs(type(messages) == "table" and messages or {}) do
        local collectable = Addon.MailLogic:CanCollect(
            message,
            queue.filterKey,
            warningDays,
            timestamp
        )
        if collectable then
            local moneyKey = table.concat({
                tostring(message.key),
                tostring(message.inboxIndex),
                "money",
            }, ":")
            if queue.filterKey ~= "items"
                and (tonumber(message.money) or 0) > 0
                and not queue.failed[moneyKey]
                and not queue.staleActions[moneyKey]
            then
                return {
                    kind = "money",
                    inboxIndex = message.inboxIndex,
                    messageKey = message.key,
                    threadKey = message.threadKey,
                    actionKey = moneyKey,
                    amount = message.money,
                    inboxRevision = self.inboxRevision,
                }
            end
            if queue.filterKey ~= "money" then
                for attachmentIndex = #message.attachments, 1, -1 do
                    local attachment = message.attachments[attachmentIndex]
                    local actionKey = table.concat({
                        tostring(message.key),
                        tostring(message.inboxIndex),
                        "item",
                        tostring(attachment.slot),
                        tostring(attachment.itemID or 0),
                    }, ":")
                    if not queue.failed[actionKey] and not queue.staleActions[actionKey] then
                        if self:CanTakeAttachment(attachment) then
                            return {
                                kind = "item",
                                inboxIndex = message.inboxIndex,
                                attachmentIndex = attachment.slot,
                                messageKey = message.key,
                                threadKey = message.threadKey,
                                actionKey = actionKey,
                                attachment = attachment,
                                inboxRevision = self.inboxRevision,
                            }
                        end
                        blockedByBags = true
                    end
                end
            end
        end
    end
    return nil, blockedByBags and "bags" or "complete"
end

function Service:ScheduleStep(delay)
    local queue = self.queue
    if not queue or queue.active ~= true then return false end
    self.timerToken = self.timerToken + 1
    local token = self.timerToken
    local generation = self.generation
    local function run()
        if token == Service.timerToken and generation == Service.generation then
            Service:StepQueue()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(math.max(0, tonumber(delay) or QUEUE_DELAY), run)
    else
        run()
    end
    return true
end

function Service:StopCollect(reason, silent)
    local queue = self.queue
    if type(queue) ~= "table" then return false end
    local wasActive = queue.active == true
    queue.active = false
    queue.status = reason == "complete" and "complete"
        or reason == "bags" and "blocked"
        or reason == "nothing" and "complete"
        or "stopped"
    queue.reason = reason or "stopped"
    queue.pending = nil
    self.timerToken = self.timerToken + 1
    setOpeningAll(false)
    self:PublishQueue()

    if wasActive and silent ~= true then
        if reason == "bags" then
            Addon:Print(Addon.L.MAILBOX_QUEUE_BAGS_FULL)
        elseif queue.processedMessages > 0 and getSetting("show_summary", true) ~= false then
            Addon:Print(string.format(
                Addon.L.MAILBOX_QUEUE_SUMMARY,
                queue.processedMessages,
                queue.collectedAttachments,
                Addon.Mailbox:FormatMoney(queue.collectedMoney)
            ))
        elseif reason == "nothing" then
            Addon:Print(Addon.L.MAILBOX_QUEUE_NOTHING)
        end
        if Addon.Sound then Addon.Sound:Play(reason == "complete" and "toggleOn" or "toggleOff") end
    end
    return wasActive
end

function Service:StartCollect(filterKey)
    if self.enabled ~= true or self.mailboxOpen ~= true or not isMailboxFeatureEnabled() then
        Addon:Print(Addon.L.MAILBOX_QUEUE_REQUIRES_MAILBOX)
        return false
    end
    if Addon.MailSender and Addon.MailSender:GetQueueState().active then
        Addon:Print(Addon.L.MAILBOX_QUEUE_BUSY)
        return false
    end
    if type(TakeInboxMoney) ~= "function" or type(TakeInboxItem) ~= "function" then
        Addon:Print(Addon.L.MAILBOX_QUEUE_UNAVAILABLE)
        return false
    end
    local validFilters = { all = true, money = true, items = true, auction = true, expiring = true }
    filterKey = validFilters[filterKey] and filterKey or "all"
    if self.queue and self.queue.active then self:StopCollect("restarted", true) end
    self.generation = self.generation + 1
    self:ResetQueue(filterKey)
    setOpeningAll(true)
    self:PublishQueue()
    if Addon.Sound then Addon.Sound:Play("toggleOn") end
    self:ScheduleStep(0)
    return true
end

function Service:StepQueue()
    local queue = self.queue
    if not queue or queue.active ~= true then return end
    if not self.mailboxOpen then
        self:StopCollect("closed")
        return
    end
    if queue.pending then
        if commandPending() then
            self:ScheduleStep(QUEUE_DELAY)
            return
        end
        if elapsedTime() - (tonumber(queue.pending.startedAt) or 0) < COMMAND_SETTLE_TIMEOUT then
            self:ScheduleStep(QUEUE_DELAY)
            return
        end
        self:CompletePending(true)
    elseif commandPending() then
        self:ScheduleStep(QUEUE_DELAY)
        return
    end

    local messages = self:ReadInbox()
    local action, reason = self:FindNextAction(messages)
    if not action then
        if queue.processedMessages == 0 and reason == "complete" then reason = "nothing" end
        self:StopCollect(reason)
        return
    end

    action.startedAt = elapsedTime()
    queue.pending = action
    local ok, errorMessage
    if action.kind == "money" then
        ok, errorMessage = pcall(TakeInboxMoney, action.inboxIndex)
    else
        ok, errorMessage = pcall(TakeInboxItem, action.inboxIndex, action.attachmentIndex)
    end
    if not ok then
        Addon.Logger:Write(
            "WARN",
            "mailbox.collect",
            "Mail action %s failed: %s",
            tostring(action.kind),
            tostring(errorMessage)
        )
        self:CompletePending(false)
    end
    self:ScheduleStep(QUEUE_DELAY)
end

function Service:FormatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    if C_CurrencyInfo and type(C_CurrencyInfo.GetCoinTextureString) == "function" then
        local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper, 12)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    if type(GetCoinTextureString) == "function" then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return tostring(copper) .. "c"
end

function Service:CheckExpiryAlerts()
    if self.alertShown or not isMailboxFeatureEnabled() or getSetting("login_alerts", true) == false then
        return false
    end
    local messages, characters = Addon.MailLogic:CountExpiringSnapshots(
        ensureMailboxDatabase().snapshots,
        getSetting("expiry_warning_days", 3),
        serverTime()
    )
    if messages <= 0 then return false end
    self.alertShown = true
    Addon:Print(string.format(Addon.L.MAILBOX_EXPIRY_ALERT, messages, characters))
    return true
end

function Service:OnMailShow()
    self.mailboxOpen = true
    self.inboxRevision = self.inboxRevision + 1
    self:ScanInbox()
end

function Service:OnInboxUpdate()
    self.inboxRevision = self.inboxRevision + 1
    if self.queue and self.queue.active then
        self.queue.staleActions = {}
    end
    self:ScanInbox()
    if self.queue and self.queue.active then self:ScheduleStep(QUEUE_DELAY) end
end

function Service:OnMailClosed()
    self.mailboxOpen = false
    if self.queue and self.queue.active then self:StopCollect("closed") end
end

function Module:OnEnable()
    Service.enabled = true
    Service.generation = Service.generation + 1
    ensureMailboxDatabase()
    Service:PublishSnapshots()
    Service:PublishQueue()

    Addon.EventBus:Subscribe("MAIL_SHOW", self, function()
        Service:OnMailShow()
    end)
    Addon.EventBus:Subscribe("MAIL_CLOSED", self, function()
        Service:OnMailClosed()
    end)
    Addon.EventBus:Subscribe("MAIL_INBOX_UPDATE", self, function()
        Service:OnInboxUpdate()
    end)
    Addon.EventBus:Subscribe("MAIL_SUCCESS", self, function()
        if Service.queue and Service.queue.active and Service.queue.pending then
            Service:CompletePending(true)
            Service:ScheduleStep(QUEUE_DELAY)
        end
    end)
    Addon.EventBus:Subscribe("MAIL_FAILED", self, function(_, itemID)
        if Service.queue and Service.queue.active and Service.queue.pending then
            local key = Service.queue.pending.actionKey
            if tonumber(itemID) then key = key .. ":" .. tostring(itemID) end
            Service:CompletePending(false, key)
            Service:ScheduleStep(QUEUE_DELAY)
        end
    end)
    Addon.EventBus:Subscribe("PLAYER_LOGIN", self, function()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(1.25, function() Service:CheckExpiryAlerts() end)
        else
            Service:CheckExpiryAlerts()
        end
    end)
end

function Module:OnDisable()
    if Service.queue and Service.queue.active then Service:StopCollect("disabled", true) end
    Service.enabled = false
    Service.mailboxOpen = false
    Service.generation = Service.generation + 1
    Service.timerToken = Service.timerToken + 1
end

Addon.ModuleRegistry:Register(Module)
