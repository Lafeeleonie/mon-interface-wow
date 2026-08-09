local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.accounting
if not module then return end

-- ============================================================================
-- Mail invoice scanning (AH sale/buy attribution)
-- ============================================================================
-- Split out of AccountingTracker.lua. The subject-classification and inbox
-- helpers below are mail-only, so they live here as file-locals. Item info /
-- ID helpers are shared and pulled from the module table (promoted in the main
-- file before this subfile loads).

local GetItemInfoSafe = module.GetItemInfoSafe
local ExtractItemID = module.ExtractItemID

-- Classify a subject string against the cached localized prefixes. Returns
-- (kind, matchedPrefix) so the caller can also strip the prefix to recover
-- the item name without relying on a colon-based gsub (CJK localizations use
-- full-width colon, and any future locale that puts a colon in the prefix
-- itself would break the colon split). Order matters: longer / more specific
-- prefixes must come first so e.g. "Auction successful:" beats "Auction:".
local function ClassifySubject(subject, cache)
    if type(subject) ~= "string" or type(cache) ~= "table" then return nil, nil end
    local function matches(prefix)
        if not prefix or prefix == "" then return false end
        return subject:find(prefix, 1, true) == 1
    end
    if matches(cache.SOLD)    then return module.CONSTANTS.KIND_AH_SALE,    cache.SOLD    end
    if matches(cache.INVOICE) then return module.CONSTANTS.KIND_AH_SALE,    cache.INVOICE end
    if matches(cache.EXPIRED) then return module.CONSTANTS.KIND_AH_EXPIRED, cache.EXPIRED end
    if matches(cache.REMOVED) then return module.CONSTANTS.KIND_AH_CANCEL,  cache.REMOVED end
    if matches(cache.OUTBID)  then return module.CONSTANTS.KIND_AH_OUTBID,  cache.OUTBID  end
    if matches(cache.WON)     then return module.CONSTANTS.KIND_AH_BUY,     cache.WON     end
    return nil, nil
end

-- Item name from a subject given the matched prefix. Falls back to a generic
-- single-colon split (works for all current locales but breaks if a future
-- locale uses a colon inside the prefix template).
local function ExtractItemFromSubject(subject, prefix)
    if type(subject) ~= "string" then return nil end
    if prefix and prefix ~= "" and subject:sub(1, #prefix) == prefix then
        local rest = subject:sub(#prefix + 1)
        return (rest:gsub("^%s+", ""))
    end
    return (subject:gsub("^[^:]+:%s*", ""))
end

local function GetInboxItemDisplay(mailIndex, itemIndex)
    local link
    if type(_G.GetInboxItemLink) == "function" then
        link = _G.GetInboxItemLink(mailIndex, itemIndex)
    end
    local name, itemID, count
    if type(_G.GetInboxItem) == "function" then
        name, itemID, _, count = _G.GetInboxItem(mailIndex, itemIndex)
    end
    return name, link, itemID, count
end

-- A processed-invoice marker so we don't double-count an invoice that fires
-- MAIL_INBOX_UPDATE multiple times during a mail session. The key must be
-- STABLE across re-fires within a session, so we deliberately exclude
-- `daysLeft` (a float that decreases continuously between fetches and would
-- produce a different key every minute even for the same mail).
local function MakeInvoiceKey(sender, subject, money, codAmount)
    return string.format("%s|%s|%d|%d",
        tostring(sender or ""),
        tostring(subject or ""),
        tonumber(money) or 0,
        tonumber(codAmount) or 0
    )
end

local function MakeSaleKey(sender, subject, itemName, playerName, bid, consignment, qtyCount)
    return string.format("%s|%s|%s|%s|%d|%d|%d",
        tostring(sender or ""),
        tostring(subject or ""),
        tostring(itemName or ""),
        tostring(playerName or ""),
        tonumber(bid) or 0,
        tonumber(consignment) or 0,
        tonumber(qtyCount) or 1
    )
end

function module:RecordAuctionSale(amount, fields)
    local saleKey = type(fields) == "table" and fields.saleKey or nil
    self.recordedSaleKeys = self.recordedSaleKeys or {}
    if saleKey and self.recordedSaleKeys[saleKey] then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return nil
    end
    local entry = self:Record(module.CONSTANTS.KIND_AH_SALE, amount, fields)
    if entry and saleKey then
        self.recordedSaleKeys[saleKey] = true
    end
    return entry
end

function module:OnMailInboxUpdate()
    if not _G.GetInboxNumItems then return end
    local count = _G.GetInboxNumItems()
    if not count or count <= 0 then return end

    local cache = self:EnsureSubjectCache()
    self.seenInvoices = self.seenInvoices or {}
    self.mailCache = {}

    for i = 1, count do
        -- Per warcraft.wiki GetInboxHeaderInfo returns:
        --   packageIcon, stationeryIcon, sender, subject, money, CODAmount,
        --   daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply, isGM
        local _, _, sender, subject, money, codAmount, _, _, _, _, _, _, isGM
            = _G.GetInboxHeaderInfo(i)

        local key = MakeInvoiceKey(sender, subject, money, codAmount)
        local alreadySeen = self.seenInvoices[key] == true
        -- Defensive: GM/refund mail can carry money but should never enter
        -- the accounting ledger -- it'd skew summaries with one-off Blizzard
        -- support transactions.
        if isGM then
            self.seenInvoices[key] = true
        else
            local processed = self:ProcessMailEntry(i, sender, subject, money, codAmount, cache, key, alreadySeen)
            if processed then self.seenInvoices[key] = true end
        end
    end
end

function module:AttachBuyerInvoiceToPurchase(itemName, bid, qtyCount, playerName, itemLink, itemID)
    local shard = self:GetShard()
    if not (shard and type(shard.entries) == "table") then return false end
    local fields = {
        item = itemLink or itemName,
        itemName = itemName,
        itemLink = itemLink,
        itemID = itemID,
        qty = tonumber(qtyCount) or 1,
        who = playerName,
    }
    self:NormalizeItemFields(fields)
    local bidAmount = tonumber(bid) or 0
    for i = #shard.entries, math.max(1, #shard.entries - 80), -1 do
        local entry = shard.entries[i]
        if entry and entry.kind == module.CONSTANTS.KIND_AH_BUY then
            local entryAmount = math.abs(tonumber(entry.amount) or 0)
            local amountMatches = bidAmount <= 0 or math.abs(entryAmount - bidAmount) <= 1
            if amountMatches and (not entry.itemLink or not entry.itemName or tostring(entry.item or "") == "") then
                if fields.item then entry.item = fields.item end
                if fields.itemName then entry.itemName = fields.itemName end
                if fields.itemLink then entry.itemLink = fields.itemLink end
                if fields.itemID then entry.itemID = fields.itemID end
                if fields.itemClassID then entry.itemClassID = fields.itemClassID end
                if fields.itemSubClassID then entry.itemSubClassID = fields.itemSubClassID end
                if fields.itemClassName then entry.itemClassName = fields.itemClassName end
                if fields.itemSubClassName then entry.itemSubClassName = fields.itemSubClassName end
                if fields.qty then entry.qty = fields.qty end
                if fields.who then entry.who = fields.who end
                self:QueueWindowRefresh()
                return true
            end
        end
    end
    return false
end

-- Process a single inbox entry. Split out from OnMailInboxUpdate so the
-- isGM / seen-key gating stays readable and we can re-use ProcessMailEntry
-- from the TakeInboxMoney/Item hooks for the same per-mail classification.
function module:ProcessMailEntry(i, sender, subject, money, codAmount, cache, key, alreadySeen)
    local invoiceType, itemName, playerName, bid, buyout, deposit,
          consignment, moneyDelay, etaHour, etaMin, qtyCount, commerceAuction
    if _G.GetInboxInvoiceInfo then
        invoiceType, itemName, playerName, bid, buyout, deposit, consignment,
            moneyDelay, etaHour, etaMin, qtyCount, commerceAuction
            = _G.GetInboxInvoiceInfo(i)
    end

    -- GetInboxInvoiceInfo returns nil for unread mail. For SOLD / INVOICE /
    -- WON / Buyer prefixes we KNOW there's an invoice, so trigger a force-
    -- fetch via GetInboxText (which marks the mail read) and retry once.
    -- Without this, sale invoices vanish until the user manually clicks the
    -- mail in the UI -- a silent data-loss path.
    if invoiceType == nil and _G.GetInboxText then
        local cls = ClassifySubject(subject, cache)
        if cls == module.CONSTANTS.KIND_AH_SALE or cls == module.CONSTANTS.KIND_AH_BUY then
            pcall(_G.GetInboxText, i)
            if _G.GetInboxInvoiceInfo then
                invoiceType, itemName, playerName, bid, buyout, deposit, consignment,
                    moneyDelay, etaHour, etaMin, qtyCount, commerceAuction
                    = _G.GetInboxInvoiceInfo(i)
            end
        end
    end

    local subjectKind, subjectPrefix = ClassifySubject(subject, cache)
    local subjectItemName = ExtractItemFromSubject(subject, subjectPrefix)
    local mailItemName, mailItemLink, mailItemID, mailItemCount = GetInboxItemDisplay(i, 1)
    itemName = itemName or mailItemName or subjectItemName
    local itemLink = mailItemLink
    local itemID = mailItemID or ExtractItemID(itemLink)
    -- AH sale mails have no item attachment. Resolve link via name->ID cache.
    if not itemLink and itemName then
        local cachedID = self:LookupItemIDByName(itemName)
        if cachedID then
            itemID = itemID or cachedID
            local _, resolvedLink = GetItemInfoSafe(cachedID)
            if resolvedLink then itemLink = resolvedLink end
        end
    end
    if not itemLink and itemID then
        local _, resolvedLink = GetItemInfoSafe(itemID)
        if resolvedLink then itemLink = resolvedLink end
    end
    local itemQty = tonumber(qtyCount) or tonumber(mailItemCount) or 1

    if invoiceType == "seller" then
        -- Prefer the attached mail money; that is the amount the player
        -- actually receives and matches the mailbox UI.
        -- Cache this and record it only when the player actually takes the
        -- money. MAIL_INBOX_UPDATE can fire many times while indices shift.
        local headerMoney = tonumber(money) or 0
        local proceeds = headerMoney > 0 and headerMoney or ((tonumber(bid) or 0) - (tonumber(consignment) or 0))
        local saleKey = MakeSaleKey(sender, subject, itemName, playerName, bid, consignment, itemQty)
        self.mailCache = self.mailCache or {}
        self.mailCache[i] = {
            kind = module.CONSTANTS.KIND_AH_SALE,
            amount = proceeds,
            fields = {
                item        = itemLink or itemName,
                itemLink    = itemLink,
                itemName    = itemName,
                itemID      = itemID,
                qty         = itemQty,
                who         = commerceAuction and "<commodity buyers>" or playerName,
                grossBid    = tonumber(bid) or 0,
                deposit     = tonumber(deposit) or 0,
                ahCut       = tonumber(consignment) or 0,
                saleKey     = saleKey,
            },
        }
        self:NormalizeItemFields(self.mailCache[i].fields)
        return true
    elseif invoiceType == "seller_temp_invoice" then
        -- Sale Pending: 1-hour hold before the real "seller" invoice
        -- replaces this mail with the final data. Skip recording so
        -- the same sale doesn't appear twice -- the real invoice arrives
        -- with the same financials under a different subject.
        return true
    elseif invoiceType == "buyer" then
        -- Buyer invoices arrive after the AH purchase already moved money and
        -- was recorded by the C_AuctionHouse pre-call hook. Enrich that row
        -- with the invoice item instead of recording a second purchase row.
        self:AttachBuyerInvoiceToPurchase(itemName, bid, itemQty, playerName, itemLink, itemID)
        return true
    else
        -- Not an AH invoice (or one not yet readable). Subject-based fallback
        -- for expired / cancelled / outbid that DON'T have a normal invoice.
        local kind, matchedPrefix = subjectKind, subjectPrefix
        if kind == module.CONSTANTS.KIND_AH_EXPIRED then
            if not alreadySeen then self:Record(module.CONSTANTS.KIND_AH_EXPIRED, 0, {
                item = ExtractItemFromSubject(subject, matchedPrefix),
            }) end
            return true
        elseif kind == module.CONSTANTS.KIND_AH_CANCEL then
            -- Cancel mail. Refund (money > 0) only happens for cancels >=12h
            -- before expiry; older cancels lose deposit. Record refund amount
            -- on the cancel entry itself so the user sees it in one row.
            if not alreadySeen then self:Record(module.CONSTANTS.KIND_AH_CANCEL, tonumber(money) or 0, {
                item = ExtractItemFromSubject(subject, matchedPrefix),
                refunded = (tonumber(money) or 0) > 0 or nil,
            }) end
            return true
        elseif kind == module.CONSTANTS.KIND_AH_OUTBID then
            -- Outbid: the bid amount is returned. money on the header is the
            -- refund value. Record on the TakeInboxMoney hook so the entry
            -- timestamp matches when the player actually accepts the refund.
            -- (Just mark seen here so the scan doesn't keep re-evaluating.)
            return true
        elseif (tonumber(codAmount) or 0) > 0 then
            -- COD mail received: deduction happens on TakeInboxItem hook.
            -- Don't record here; the hook will record KIND_COD_PAID.
            return true
        elseif (tonumber(money) or 0) > 0 then
            -- Regular mail with money attached (gift / return). Recorded
            -- when the player takes the money via TakeInboxMoney hook.
            return true
        else
            -- Pure item attachment (or empty). Nothing accounting-relevant.
            return true
        end
    end
end

-- Truncate mailbox caches when the mailbox closes so a fresh session re-scans
-- the current inbox state.
function module:OnMailClose()
    self.seenInvoices = nil
    self.mailCache = nil
    self.recordedSaleKeys = nil
end

-- Shared helpers for OnTakeInboxMoney and OnAutoLootMailItem so both
-- code paths record AH sales identically with full item metadata.

function module:RecordMailSaleFromCache(index, amount)
    local cached = self.mailCache and self.mailCache[index]
    if cached and cached.kind == module.CONSTANTS.KIND_AH_SALE then
        local saleAmount = cached.amount or amount or 0
        self:RecordAuctionSale(saleAmount, cached.fields)
        self.mailCache[index] = nil
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return true
    end
    return false
end

function module:RecordMailSaleFromInvoice(index, sender, subject, amount)
    local invoiceType, itemName, playerName, bid, buyout, deposit,
          consignment, moneyDelay, etaHour, etaMin, qtyCount, commerceAuction
    if type(_G.GetInboxInvoiceInfo) == "function" then
        invoiceType, itemName, playerName, bid, buyout, deposit, consignment,
            moneyDelay, etaHour, etaMin, qtyCount, commerceAuction
            = _G.GetInboxInvoiceInfo(index)
    end

    if invoiceType == "seller" then
        local mailItemName, mailItemLink, mailItemID, mailItemCount = GetInboxItemDisplay(index, 1)
        local cache = self:EnsureSubjectCache()
        local _, matchedPrefix = ClassifySubject(subject, cache)
        itemName = itemName or mailItemName or ExtractItemFromSubject(subject, matchedPrefix)
        local itemLink = mailItemLink
        local itemID = mailItemID or ExtractItemID(itemLink)
        -- Resolve link from item name when no attachment is present.
        -- AH sale mails contain only gold; the item was already sold.
        -- Use persistent name->ID cache populated at posting time.
        if not itemLink and itemName then
            local cachedID = self:LookupItemIDByName(itemName)
            if cachedID then
                itemID = itemID or cachedID
                local resolvedName, resolvedLink = GetItemInfoSafe(cachedID)
                if resolvedLink then
                    itemLink = resolvedLink
                end
            end
        end
        if not itemLink and itemID then
            local _, resolvedLink = GetItemInfoSafe(itemID)
            if resolvedLink then itemLink = resolvedLink end
        end
        local itemQty = tonumber(qtyCount) or tonumber(mailItemCount) or 1
        local proceeds = amount > 0 and amount or ((tonumber(bid) or 0) - (tonumber(consignment) or 0))
        local fields = {
            item        = itemLink or itemName,
            itemLink    = itemLink,
            itemName    = itemName,
            itemID      = itemID,
            qty         = itemQty,
            who         = commerceAuction and "<commodity buyers>" or playerName,
            grossBid    = tonumber(bid) or amount,
            deposit     = tonumber(deposit) or 0,
            ahCut       = tonumber(consignment) or 0,
            saleKey     = MakeSaleKey(sender, subject, itemName, playerName, bid, consignment, itemQty),
        }
        self:NormalizeItemFields(fields)
        self:RecordAuctionSale(proceeds, fields)
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return true
    elseif invoiceType == "seller_temp_invoice" then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return true
    end
    return false
end

function module:OnTakeInboxMoney(index)
    if type(_G.GetInboxHeaderInfo) ~= "function" then return end
    local _, _, sender, subject, money, codAmount, _, _, _, _, _, _, isGM
        = _G.GetInboxHeaderInfo(index)
    local amount = tonumber(money) or 0

    if isGM then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return
    end

    -- Try cached sale data first (from MAIL_INBOX_UPDATE scan)
    if self:RecordMailSaleFromCache(index, amount) then return end

    -- Try reading invoice directly
    if self:RecordMailSaleFromInvoice(index, sender, subject, amount) then return end

    if amount <= 0 then return end

    local cache = self:EnsureSubjectCache()
    local kind, matchedPrefix = ClassifySubject(subject, cache)
    if kind == module.CONSTANTS.KIND_AH_SALE then
        local subjectItem = ExtractItemFromSubject(subject, matchedPrefix)
        local fields = {
            item = subjectItem,
            itemName = subjectItem,
            who = sender,
            saleKey = MakeSaleKey(sender, subject, subjectItem, sender, amount, 0, 1),
        }
        self:NormalizeItemFields(fields)
        self:RecordAuctionSale(amount, fields)
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return
    end
    if kind == module.CONSTANTS.KIND_AH_CANCEL then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return
    end
    if kind == module.CONSTANTS.KIND_AH_OUTBID then
        self:PushHint(module.CONSTANTS.KIND_AH_OUTBID, {
            amount = amount,
            item = ExtractItemFromSubject(subject, matchedPrefix),
            who = sender,
        })
        return
    end

    self:PushHint(module.CONSTANTS.KIND_MAIL_MONEY, {
        amount = amount,
        who = sender,
        subject = subject,
        codAmount = (tonumber(codAmount) or 0) > 0 and tonumber(codAmount) or nil,
    })
end

function module:OnTakeInboxItem(index, itemIndex)
    if type(_G.GetInboxHeaderInfo) ~= "function" then return end
    local _, _, sender, subject, _, codAmount = _G.GetInboxHeaderInfo(index)
    local cod = tonumber(codAmount) or 0
    if cod <= 0 then return end

    local itemName, itemLink, itemID, count = GetInboxItemDisplay(index, itemIndex)
    self:PushHint(module.CONSTANTS.KIND_COD_PAID, {
        amount = -cod,
        item = itemLink or itemName,
        itemLink = itemLink,
        itemName = itemName,
        itemID = itemID,
        qty = tonumber(count) or 1,
        who = sender,
        subject = subject,
    })
end

function module:OnSendMail(target, subject)
    local postage = 0
    if type(_G.GetSendMailPrice) == "function" then
        postage = tonumber(_G.GetSendMailPrice()) or 0
    end
    local money = 0
    if type(_G.GetSendMailMoney) == "function" then
        money = tonumber(_G.GetSendMailMoney()) or 0
    end
    local cod = 0
    if type(_G.GetSendMailCOD) == "function" then
        cod = tonumber(_G.GetSendMailCOD()) or 0
    end

    local recorded = false
    if money > 0 then
        self:Record(module.CONSTANTS.KIND_MAIL_MONEY, -money, {
            who = target,
            subject = subject,
        })
        recorded = true
    end
    if postage > 0 then
        self:Record(module.CONSTANTS.KIND_POSTAGE, -postage, {
            who = target,
            subject = subject,
            codAmount = cod > 0 and cod or nil,
        })
        recorded = true
    end
    if recorded then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
    end
end

function module:OnAutoLootMailItem(index)
    if type(_G.GetInboxHeaderInfo) ~= "function" then return end
    local _, _, sender, subject, money, codAmount, _, _, _, _, _, _, isGM
        = _G.GetInboxHeaderInfo(index)
    local amount = tonumber(money) or 0

    if isGM then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
        return
    end

    -- Try cached sale data first (from MAIL_INBOX_UPDATE scan)
    if self:RecordMailSaleFromCache(index, amount) then return end

    -- Try reading invoice directly
    if self:RecordMailSaleFromInvoice(index, sender, subject, amount) then return end

    -- COD handling
    local cod = tonumber(codAmount) or 0
    if cod > 0 then
        local itemName, itemLink, itemID, count = GetInboxItemDisplay(index, 1)
        self:PushHint(module.CONSTANTS.KIND_COD_PAID, {
            amount = -cod,
            item = itemLink or itemName,
            itemLink = itemLink,
            itemName = itemName,
            itemID = itemID,
            qty = tonumber(count) or 1,
            who = sender,
            subject = subject,
        })
        return
    end

    -- Regular mail money
    if amount > 0 then
        local cache = self:EnsureSubjectCache()
        local kind, matchedPrefix = ClassifySubject(subject, cache)
        if kind == module.CONSTANTS.KIND_AH_SALE then
            local subjectItem = ExtractItemFromSubject(subject, matchedPrefix)
            local fields = {
                item = subjectItem,
                itemName = subjectItem,
                who = sender,
                saleKey = MakeSaleKey(sender, subject, subjectItem, sender, amount, 0, 1),
            }
            self:NormalizeItemFields(fields)
            self:RecordAuctionSale(amount, fields)
            self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
            return
        end
        if kind == module.CONSTANTS.KIND_AH_CANCEL then
            self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
            return
        end
        if kind == module.CONSTANTS.KIND_AH_OUTBID then
            self:PushHint(module.CONSTANTS.KIND_AH_OUTBID, {
                amount = amount,
                item = ExtractItemFromSubject(subject, matchedPrefix),
                who = sender,
            })
            return
        end
        self:PushHint(module.CONSTANTS.KIND_MAIL_MONEY, {
            amount = amount,
            who = sender,
            subject = subject,
        })
    end
end

function module:InstallMailHooks()
    if self.mailHooksInstalled then return end

    if type(_G.TakeInboxMoney) == "function" then
        hooksecurefunc("TakeInboxMoney", function(index)
            if not module.isActive then return end
            module:OnTakeInboxMoney(index)
        end)
        self.takeInboxMoneyHooked = true
    end

    if type(_G.TakeInboxItem) == "function" then
        hooksecurefunc("TakeInboxItem", function(index, itemIndex)
            if not module.isActive then return end
            module:OnTakeInboxItem(index, itemIndex)
        end)
        self.takeInboxItemHooked = true
    end

    -- AutoLootMailItem is used by Shift-click and "Open All" / "Collect All".
    -- Without this hook, AH sale gold taken via fast-loot is silently lost.
    if type(_G.AutoLootMailItem) == "function" then
        hooksecurefunc("AutoLootMailItem", function(index)
            if not module.isActive then return end
            module:OnAutoLootMailItem(index)
        end)
        self.autoLootMailItemHooked = true
    end

    if type(_G.SendMail) == "function" then
        hooksecurefunc("SendMail", function(target, subject)
            if not module.isActive then return end
            module:OnSendMail(target, subject)
        end)
        self.sendMailHooked = true
    end

    self.mailHooksInstalled = true
end
