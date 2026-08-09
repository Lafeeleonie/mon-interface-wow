local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.accounting
if not module then return end

local CATEGORY_SETTING_KEYS = module.CATEGORY_SETTING_KEYS or {}
local CATEGORY_ORDER = module.CATEGORY_ORDER or {}
local ACCOUNTING_SCHEMA_VERSION = module.ACCOUNTING_SCHEMA_VERSION or 1
local NowEpoch = module.NowEpoch or function() return time and time() or 0 end

-- ============================================================================
-- Summary / reporting
-- ============================================================================

local function NowMinusBucket(bucketSeconds)
    if not bucketSeconds then return 0 end
    return NowEpoch() - bucketSeconds
end

-- Aggregate ledger entries newer than `sinceEpoch` into per-kind totals.
function module:Aggregate(sinceEpoch)
    local shard = self:GetShard()
    if not shard then return {}, 0 end
    local totals = {}
    local total = 0
    for _, entry in ipairs(shard.entries) do
        if (entry.t or 0) >= sinceEpoch then
            local k = entry.kind or "unknown"
            totals[k] = (totals[k] or 0) + (entry.amount or 0)
            total = total + (entry.amount or 0)
        end
    end
    return totals, total
end

function module:IsCategoryVisible(category)
    local key = CATEGORY_SETTING_KEYS[category or "other"] or CATEGORY_SETTING_KEYS.other
    if not self.settings then return true end
    return self.settings[key] ~= false
end

function module:PrintSummary(bucketName)
    local bucketSeconds
    local label
    if bucketName == "24h" or bucketName == "1d" or bucketName == "day" then
        bucketSeconds = self.CONSTANTS.BUCKET_24H
        label = "Last 24h"
    elseif bucketName == "14d" then
        bucketSeconds = self.CONSTANTS.BUCKET_14D
        label = "Last 14 days"
    elseif bucketName == "30d" or bucketName == "month" then
        bucketSeconds = self.CONSTANTS.BUCKET_30D
        label = "Last 30 days"
    elseif bucketName == "90d" then
        bucketSeconds = self.CONSTANTS.BUCKET_90D
        label = "Last 90 days"
    elseif bucketName == "all" then
        bucketSeconds = nil
        label = "All time"
    else
        bucketSeconds = self.CONSTANTS.BUCKET_7D
        label = "Last 7 days"
    end

    local sinceEpoch = bucketSeconds and NowMinusBucket(bucketSeconds) or 0
    local totals, total = self:Aggregate(sinceEpoch)

    ns.Diagnostics:Info(("|cff95d955=== Accounting summary (%s) ===|r"):format(label))
    -- Stable kind order so output stays readable across calls.
    local order = {
        self.CONSTANTS.KIND_AH_SALE,
        self.CONSTANTS.KIND_AH_BUY,
        self.CONSTANTS.KIND_AH_DEPOSIT,
        self.CONSTANTS.KIND_AH_CANCEL,
        self.CONSTANTS.KIND_AH_EXPIRED,
        self.CONSTANTS.KIND_AH_OUTBID,
        self.CONSTANTS.KIND_VENDOR_SELL,
        self.CONSTANTS.KIND_VENDOR_BUY,
        self.CONSTANTS.KIND_REPAIR,
        self.CONSTANTS.KIND_QUEST,
        self.CONSTANTS.KIND_LOOT,
        self.CONSTANTS.KIND_MAIL_MONEY,
        self.CONSTANTS.KIND_POSTAGE,
        self.CONSTANTS.KIND_TRADE_IN,
        self.CONSTANTS.KIND_TRADE_OUT,
        self.CONSTANTS.KIND_WORK_ORDER,
        self.CONSTANTS.KIND_COD_PAID,
        self.CONSTANTS.KIND_COD_RECEIVED,
        self.CONSTANTS.KIND_UNKNOWN,
    }
    local seen = {}
    for _, kind in ipairs(order) do
        local amt = totals[kind]
        if amt and amt ~= 0 then
            ns.Diagnostics:Info(("  %-18s %s"):format(self:GetKindLabel(kind), self:FormatMoney(amt)))
            seen[kind] = true
        end
    end
    -- Catch any kinds not in our static order (forward-compat).
    for kind, amt in pairs(totals) do
        if not seen[kind] and amt ~= 0 then
            ns.Diagnostics:Info(("  %-18s %s"):format(self:GetKindLabel(kind), self:FormatMoney(amt)))
        end
    end
    ns.Diagnostics:Info(("|cff95d955-------- Net: %s --------|r"):format(self:FormatMoney(total)))
end

function module:PrintRecent(n)
    local shard = self:GetShard()
    if not shard then return end
    n = tonumber(n) or 10
    if n < 1 then n = 1 end
    if n > 50 then n = 50 end
    local entries = shard.entries
    local count = #entries
    local first = math.max(1, count - n + 1)
    ns.Diagnostics:Info(("|cff95d955=== Last %d accounting entries ===|r"):format(math.min(n, count)))
    if count == 0 then
        ns.Diagnostics:Info("  (no entries recorded yet)")
        return
    end
    for i = first, count do
        local e = entries[i]
        local ago = NowEpoch() - (e.t or 0)
        local agoStr
        if ago < 60 then
            agoStr = string.format("%ds ago", ago)
        elseif ago < 3600 then
            agoStr = string.format("%dm ago", math.floor(ago / 60))
        elseif ago < 86400 then
            agoStr = string.format("%dh ago", math.floor(ago / 3600))
        else
            agoStr = string.format("%dd ago", math.floor(ago / 86400))
        end
        local tail = e.item and (" " .. tostring(e.item)) or ""
        if e.qty and e.qty > 1 then tail = tail .. (" x" .. tostring(e.qty)) end
        if e.who then tail = tail .. (" <-> " .. tostring(e.who)) end
        ns.Diagnostics:Info(("  [%s] %-18s %s%s"):format(
            agoStr, self:GetKindLabel(e.kind), self:FormatMoney(e.amount or 0), tail
        ))
    end
end

function module:ClearShard()
    local shard, key = self:GetShard()
    if not shard then return end
    shard.entries = {}
    shard.lastMoney = _G.GetMoney and _G.GetMoney() or nil
    -- Also drop the at-rest blob / count cache, else a cleared shard could be
    -- re-hydrated from stale serialized history.
    shard.blob = nil
    shard.count = 0
    shard._blobError = nil
    ns.Diagnostics:Info(("Accounting ledger cleared for %s."):format(tostring(key)))
    if self.window then self:RefreshWindow() end
end

function module:ClearAllShards()
    if not (self.settings and type(self.settings.shards) == "table") then return 0 end
    local currentShard = self:GetShard()
    local removed = 0
    for _, shard in pairs(self.settings.shards) do
        if type(shard) == "table" then
            removed = removed + (self.GetShardEntryCount and self:GetShardEntryCount(shard) or 0)
            shard.entries = {}
            shard.lastMoney = shard == currentShard and (_G.GetMoney and _G.GetMoney() or nil) or nil
            shard.blob = nil
            shard.count = 0
            shard._blobError = nil
            shard.schemaVersion = ACCOUNTING_SCHEMA_VERSION
        end
    end
    ns.Diagnostics:Info(("Accounting ledger cleared account-wide (%d entries removed)."):format(removed))
    if self.window then self:RefreshWindow() end
    return removed
end

-- Reset only the lifetime running totals (the all-time footer figures). The
-- ledger entries are kept; this is the dedicated "clear" for the all-time
-- numbers, separate from ClearShard which leaves lifetime intact. Sets the
-- counters to 0 so they start counting forward again from now.
function module:ClearShardLifetime()
    local shard, key = self:GetShard()
    if not shard then return end
    shard.lifetimeIncome = 0
    shard.lifetimeExpense = 0
    ns.Diagnostics:Info(("Accounting all-time totals reset for %s."):format(tostring(key)))
    if self.window then self:RefreshWindow() end
end

function module:ClearAllShardLifetime()
    if not (self.settings and type(self.settings.shards) == "table") then return end
    for _, shard in pairs(self.settings.shards) do
        if type(shard) == "table" then
            shard.lifetimeIncome = 0
            shard.lifetimeExpense = 0
        end
    end
    ns.Diagnostics:Info("Accounting all-time totals reset account-wide.")
    if self.window then self:RefreshWindow() end
end

-- Format an absolute (unsigned) money amount for display. FormatMoney prefixes
-- a sign which is wrong for "current money" lines.
function module:FormatMoneyAbs(copper)
    local n = tonumber(copper) or 0
    if _G.GetCoinTextureString then
        return _G.GetCoinTextureString(n)
    end
    local g = math.floor(n / 10000)
    local s = math.floor((n % 10000) / 100)
    local c = n % 100
    return string.format("%dg %ds %dc", g, s, c)
end

function module:PrintStatus()
    local shard, key = self:GetShard()
    if not shard then
        ns.Diagnostics:Info("Accounting: no shard yet.")
        return
    end
    local hintCount = self.hints and #self.hints or 0
    local baselineDisplay = shard.lastMoney
        and self:FormatMoneyAbs(shard.lastMoney)
        or "(not seeded yet)"
    ns.Diagnostics:Info(("|cff95d955=== Accounting status ===|r"))
    ns.Diagnostics:Info(("shard          : %s"):format(tostring(key)))
    ns.Diagnostics:Info(("isActive       : %s"):format(tostring(self.isActive or false)))
    ns.Diagnostics:Info(("entries        : %d"):format(#shard.entries))
    ns.Diagnostics:Info(("pending hints  : %d"):format(hintCount))
    ns.Diagnostics:Info(("merchant open  : %s   AH open: %s   trade open: %s"):format(
        tostring(self.merchantOpen or false),
        tostring(self.ahOpen or false),
        tostring(self.tradeOpen or false)
    ))
    ns.Diagnostics:Info(("hooks: buy=%s buyback=%s sell=%s repair=%s"):format(
        tostring(self.buyHooked or false),
        tostring(self.buybackHooked or false),
        tostring(self.sellHooked or false),
        tostring(self.repairHooked or false)
    ))
    ns.Diagnostics:Info(("ah hooks: buy=%s bid=%s postItem=%s postCom=%s"):format(
        tostring(self.ahBuyHooked or false),
        tostring(self.ahBidHooked or false),
        tostring(self.ahPostItemHooked or false),
        tostring(self.ahPostCommodityHooked or false)
    ))
    ns.Diagnostics:Info(("mail hooks: money=%s item=%s autoLoot=%s send=%s pending=%d"):format(
        tostring(self.takeInboxMoneyHooked or false),
        tostring(self.takeInboxItemHooked or false),
        tostring(self.autoLootMailItemHooked or false),
        tostring(self.sendMailHooked or false),
        self:GetPendingItemInfoCount()
    ))
    ns.Diagnostics:Info(("work order hook: %s"):format(tostring(self.workOrderFulfillHooked or false)))
    local cacheSize, archivedSize = 0, 0
    if self.settings and type(self.settings.itemNameToID) == "table" then
        for _ in pairs(self.settings.itemNameToID) do cacheSize = cacheSize + 1 end
    end
    if self.settings and type(self.settings.itemNameToIDPrev) == "table" then
        for _ in pairs(self.settings.itemNameToIDPrev) do archivedSize = archivedSize + 1 end
    end
    ns.Diagnostics:Info(("name->ID cache : %d live, %d archived"):format(cacheSize, archivedSize))
    ns.Diagnostics:Info(("money baseline : %s"):format(baselineDisplay))
end

-- Window UI lives in Modules/AccountingTracker/Window.lua.

-- ============================================================================
-- Slash command entrypoint (called from SlashCommands.lua)
-- ============================================================================

function module:HandleSlash(tokens)
    local sub = string.lower(tokens[2] or "")
    if sub == "" then
        -- Default action: open the ledger window. Power users still have
        -- explicit subcommands for chat-only output.
        self:ToggleWindow()
        return
    end
    if sub == "help" then
        ns.Diagnostics:Info("Accounting commands:")
        ns.Diagnostics:Info("  /thyrax accounting                open / close ledger window")
        ns.Diagnostics:Info("  /thyrax accounting show           force-open ledger window")
        ns.Diagnostics:Info("  /thyrax accounting hide           close ledger window")
        ns.Diagnostics:Info("  /thyrax accounting summary [24h|7d|14d|30d|90d|all]  print to chat")
        ns.Diagnostics:Info("  /thyrax accounting recent [N]     print last N to chat (1..50)")
        ns.Diagnostics:Info("  /thyrax accounting status         print module state to chat")
        ns.Diagnostics:Info("  /thyrax accounting clear          wipe this character's ledger")
        return
    end
    if sub == "show" or sub == "window" or sub == "open" then
        self:ShowWindow()
        return
    end
    if sub == "hide" or sub == "close" then
        self:HideWindow()
        return
    end
    if sub == "summary" then
        self:PrintSummary(tokens[3])
        return
    end
    if sub == "recent" then
        self:PrintRecent(tonumber(tokens[3]) or 10)
        return
    end
    if sub == "status" then
        self:PrintStatus()
        return
    end
    if sub == "clear" then
        self:ClearShard()
        return
    end
    ns.Diagnostics:Warn("Unknown accounting subcommand. Try /thyrax accounting help.")
end

