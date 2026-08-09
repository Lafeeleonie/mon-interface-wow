local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

-- Schema 2 adds per-shard lifetime income/expense running totals (see
-- ComputeShardLifetime). Schema 3 adds lazy blob storage metadata. Schema 4
-- drops the per-shard moneyLog sample array (it was written on every
-- PLAYER_MONEY but never read by any view -- pure SavedVariables/RAM cost).
-- The migration backfills/cleans without deleting ledger history.
local ACCOUNTING_SCHEMA_VERSION = 4
local ITEM_CLASS_CONTAINER = 1 -- Enum.ItemClass.Container
local ITEM_CLASS_HOUSING = 20 -- Enum.ItemClass.Housing in WoW 12.0.5
local ITEM_CLASS_LABELS = {
    [0] = "Consumable",
    [1] = "Container",
    [2] = "Weapon",
    [3] = "Gem",
    [4] = "Armor",
    [5] = "Reagent",
    [6] = "Projectile",
    [7] = "Trade Goods",
    [8] = "Item Enhancement",
    [9] = "Recipe",
    [10] = "Currency Token",
    [11] = "Quiver",
    [12] = "Quest Item",
    [13] = "Key",
    [14] = "Permanent",
    [15] = "Miscellaneous",
    [16] = "Glyph",
    [17] = "Battle Pet",
    [18] = "WoW Token",
    [19] = "Profession",
    [20] = "Housing",
}
local ITEM_CLASS_FILTER_ORDER = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
}

-- ============================================================================
-- AccountingTracker
--
-- TSM-Accounting-style ledger: persists every gold-affecting event with a
-- source tag so the player can review sales, purchases, vendor flow, repairs,
-- quest income and unattributed money deltas.
--
-- Data is per realm + faction + character (a "shard"). The module ships with
-- no UI overlay in MVP -- everything is read back via /thyrax accounting <cmd>.
-- ============================================================================

local module = {
    id = "accounting_tracker",
    name = "Accounting",
    version = ns.Versions.ACCOUNTING_TRACKER,
    source = "core",
    internal = true,
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\accounting.tga",
    subtitle = "Tracks gold flow, AH sales, vendor transactions and quest rewards.",
    onboardingDescription =
    "Records every gold-affecting event (AH sales, work orders, vendor transactions, repairs, quest rewards, mail money) into a per-character ledger. Review with /thyrax accounting summary or /thyrax accounting recent.",
    events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_MONEY",
        "MERCHANT_SHOW",
        "MERCHANT_CLOSED",
        "MERCHANT_UPDATE",
        "MAIL_SHOW",
        "MAIL_CLOSED",
        "MAIL_INBOX_UPDATE",
        "GET_ITEM_INFO_RECEIVED",
        "QUEST_TURNED_IN",
        "CHAT_MSG_MONEY",
        "UPDATE_INVENTORY_DURABILITY",
        "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED",
        -- AUCTION_HOUSE_AUCTION_CREATED fires AFTER PLAYER_MONEY, so hints
        -- pushed from it would arrive too late for money attribution -- we
        -- hook C_AuctionHouse.PostItem/PostCommodity for that. BUT the event
        -- is still useful for the name->ID cache: it carries the auctionID
        -- of the just-posted listing, which we can resolve via
        -- GetAuctionInfoByID even after the user immediately closes the AH.
        "AUCTION_HOUSE_AUCTION_CREATED",
        "CRAFTINGORDERS_CLAIMED_ORDER_ADDED",
        "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED",
        "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED",
        "CRAFTINGORDERS_UPDATE_CUSTOMER_NAME",
        -- COMMODITY_PURCHASE_SUCCEEDED / ITEM_PURCHASED are similarly too
        -- late for money attribution; we hook the C_AuctionHouse pre-call
        -- API instead (see InstallAHHooks).
        "TRADE_SHOW",
        "TRADE_CLOSED",
        "TRADE_ACCEPT_UPDATE",
    },
    defaults = {
        enabled = false,
        -- Per-shard ledger lives in self.settings.shards[shardKey]. The key
        -- is "<realm>-<faction>-<player>". A shard owns: entries{} and the
        -- lastMoney baseline used to compute PLAYER_MONEY deltas.
        shards = {},
        -- Pruning: when a shard's entries{} grows past maxEntries, the oldest
        -- 10% gets trimmed to keep SavedVariables size bounded.
        maxEntries = 20000,
        -- Attribution window in seconds. When PLAYER_MONEY fires, we look at
        -- the most recent source hint within this window and attribute the
        -- delta to it. 0.5s is enough to cover MERCHANT_UPDATE -> PLAYER_MONEY
        -- and QUEST_TURNED_IN -> PLAYER_MONEY ordering.
        attributionWindow = 0.5,
        -- Toggle: log raw money deltas with "unknown" source if nothing
        -- attributed within attributionWindow. Off by default to avoid
        -- spamming the ledger with tiny unattributed deltas.
        logUnattributed = false,
        -- Toggle: write a verbose console line each time an entry is recorded.
        -- Off by default; enable for live debugging only.
        verboseLogging = false,
        -- Ledger window placement and last-used filters.
        window = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 860,
            height = 560,
            tab = "overview",
            bucket = "7d",
            search = "",
            groupBy = "source",
            chartView = "daily",
            hiddenItemTypes = {},
            characterFilter = "current",
            columns = {
                time = true,
                source = true,
                itemType = true,
                who = true,
                amount = true,
                detail = true,
            },
        },
        defaultTab = "last",
        windowAlpha = 0.92,
        showMinimapButton = true,
        chartBarLabels = true,
        chartCumulativeLine = false,
        chartShowAvgLine = false,
        moneyCompactAlways = false,
        moneyThousandsSeparator = ".",
        showCategoryAH = true,
        showCategoryVendor = true,
        showCategoryQuest = true,
        showCategoryLoot = true,
        showCategoryMail = true,
        showCategoryTrade = true,
        showCategoryWorkOrders = true,
        showCategoryOther = true,
        showDebugActions = true,
        customTheme = false,
        accentColor = { 0.95, 0.78, 0.30, 1 },
        surfaceColor = { 0.18, 0.13, 0.07, 0.95 },
        -- Persistent map of item name -> itemID so AH sale mails (which
        -- carry only gold + the item name as plain text) can be resolved
        -- to full item links with tooltips and categories. Growth is bounded
        -- by a two-generation scheme: when this table reaches
        -- ITEM_NAME_CACHE_CAP names it is archived into itemNameToIDPrev
        -- (created lazily by CacheItemNameToID) and restarted, so the cache
        -- never holds more than ~2x cap names.
        itemNameToID = {},
        -- Options-panel collapsible dev/diagnostics section toggle.
        devPanelExpanded = false,
    },
}

-- Expose the module table to sibling files in Modules/AccountingTracker/.
-- Each subfile reads ns._sharedModules.accounting at the top of its chunk to
-- attach its own methods (Minimap.lua, future Charts.lua, etc).
ns._sharedModules = ns._sharedModules or {}
ns._sharedModules.accounting = module

module.CONSTANTS = {
    -- Time bucket cutoffs in seconds (relative to now).
    BUCKET_24H = 24 * 60 * 60,
    BUCKET_7D  = 7 * 24 * 60 * 60,
    BUCKET_14D = 14 * 24 * 60 * 60,
    BUCKET_30D = 30 * 24 * 60 * 60,
    BUCKET_90D = 90 * 24 * 60 * 60,

    -- Attribution kinds. Keep these as short stable strings -- they're stored
    -- in SavedVariables and used as keys in summary aggregation.
    KIND_AH_SALE      = "ah_sale",
    KIND_AH_BUY       = "ah_buy",
    KIND_AH_DEPOSIT   = "ah_deposit",
    KIND_AH_CANCEL    = "ah_cancel",
    KIND_AH_EXPIRED   = "ah_expired",
    KIND_VENDOR_SELL  = "vendor_sell",
    KIND_VENDOR_BUY   = "vendor_buy",
    KIND_REPAIR       = "repair",
    KIND_QUEST        = "quest",
    KIND_LOOT         = "loot",
    KIND_MAIL_MONEY   = "mail_money",
    KIND_TRADE_IN     = "trade_in",
    KIND_TRADE_OUT    = "trade_out",
    KIND_WORK_ORDER   = "work_order",
    KIND_COD_PAID     = "cod_paid",
    KIND_COD_RECEIVED = "cod_received",
    KIND_AH_OUTBID    = "ah_outbid",     -- refund of a losing bid
    KIND_POSTAGE      = "postage",       -- outgoing mail send cost
    KIND_UNKNOWN      = "unknown",
    -- Internal marker: a hint with this kind tells OnPlayerMoney to consume
    -- and discard the next delta. Used when a transaction was already recorded
    -- directly (quest / trade) so the mirrored PLAYER_MONEY tick doesn't
    -- double-count or land as unknown.
    KIND_SUPPRESS     = "__suppress__",

    -- Name->ID cache generation size. The cache is seeded from every
    -- GET_ITEM_INFO_RECEIVED, so without a bound it would converge on "every
    -- item the client ever resolved" (unbounded SavedVariables growth). Two
    -- generations of this size cap it at ~8000 names; lookups promote hits
    -- from the archived generation back into the live one, so names that are
    -- actually used survive rotations (see CacheItemNameToID).
    ITEM_NAME_CACHE_CAP = 4000,

    -- Mail subject classification fallbacks. We prefer GetInboxInvoiceInfo's
    -- invoiceType field (which is locale-neutral), but for cancellation and
    -- expiration there is no invoice -- only a localized subject. We snapshot
    -- Blizzard's localized templates at addon-load time so we don't have to
    -- worry about a /reload changing the locale mid-session.
    --
    -- Filled lazily on first MAIL_INBOX_UPDATE because the globals are only
    -- guaranteed available after PLAYER_LOGIN.
    SUBJECT_CACHE = nil,
}

local KIND_LABELS = {
    [module.CONSTANTS.KIND_AH_SALE] = "AH Sale",
    [module.CONSTANTS.KIND_AH_BUY] = "AH Purchase",
    [module.CONSTANTS.KIND_AH_DEPOSIT] = "AH Deposit",
    [module.CONSTANTS.KIND_AH_CANCEL] = "AH Cancel",
    [module.CONSTANTS.KIND_AH_EXPIRED] = "AH Expired",
    [module.CONSTANTS.KIND_AH_OUTBID] = "AH Outbid Refund",
    [module.CONSTANTS.KIND_VENDOR_SELL] = "Vendor Sale",
    [module.CONSTANTS.KIND_VENDOR_BUY] = "Vendor Purchase",
    [module.CONSTANTS.KIND_REPAIR] = "Repair",
    [module.CONSTANTS.KIND_QUEST] = "Quest Reward",
    [module.CONSTANTS.KIND_LOOT] = "Loot",
    [module.CONSTANTS.KIND_MAIL_MONEY] = "Mail Money",
    [module.CONSTANTS.KIND_POSTAGE] = "Postage",
    [module.CONSTANTS.KIND_TRADE_IN] = "Trade In",
    [module.CONSTANTS.KIND_TRADE_OUT] = "Trade Out",
    [module.CONSTANTS.KIND_WORK_ORDER] = "Work Order",
    [module.CONSTANTS.KIND_COD_PAID] = "COD Paid",
    [module.CONSTANTS.KIND_COD_RECEIVED] = "COD Received",
    [module.CONSTANTS.KIND_UNKNOWN] = "Unattributed",
}

local KIND_CATEGORY = {
    [module.CONSTANTS.KIND_AH_SALE] = "ah",
    [module.CONSTANTS.KIND_AH_BUY] = "ah",
    [module.CONSTANTS.KIND_AH_DEPOSIT] = "ah",
    [module.CONSTANTS.KIND_AH_CANCEL] = "ah",
    [module.CONSTANTS.KIND_AH_EXPIRED] = "ah",
    [module.CONSTANTS.KIND_AH_OUTBID] = "ah",
    [module.CONSTANTS.KIND_VENDOR_SELL] = "vendor",
    [module.CONSTANTS.KIND_VENDOR_BUY] = "vendor",
    [module.CONSTANTS.KIND_REPAIR] = "vendor",
    [module.CONSTANTS.KIND_QUEST] = "quest",
    [module.CONSTANTS.KIND_LOOT] = "loot",
    [module.CONSTANTS.KIND_MAIL_MONEY] = "mail",
    [module.CONSTANTS.KIND_POSTAGE] = "mail",
    [module.CONSTANTS.KIND_COD_PAID] = "mail",
    [module.CONSTANTS.KIND_COD_RECEIVED] = "mail",
    [module.CONSTANTS.KIND_TRADE_IN] = "trade",
    [module.CONSTANTS.KIND_TRADE_OUT] = "trade",
    [module.CONSTANTS.KIND_WORK_ORDER] = "work_order",
    [module.CONSTANTS.KIND_UNKNOWN] = "other",
}

local CATEGORY_LABELS = {
    ah = "Auction House",
    vendor = "Vendor",
    quest = "Quests",
    loot = "Loot",
    mail = "Mail",
    trade = "Trade",
    work_order = "Work Orders",
    other = "Other",
}

local CATEGORY_SETTING_KEYS = {
    ah = "showCategoryAH",
    vendor = "showCategoryVendor",
    quest = "showCategoryQuest",
    loot = "showCategoryLoot",
    mail = "showCategoryMail",
    trade = "showCategoryTrade",
    work_order = "showCategoryWorkOrders",
    other = "showCategoryOther",
}
module.ACCOUNTING_SCHEMA_VERSION = ACCOUNTING_SCHEMA_VERSION

local CATEGORY_ORDER = { "ah", "vendor", "quest", "loot", "mail", "trade", "work_order", "other" }

module.ITEM_CLASS_HOUSING = ITEM_CLASS_HOUSING
module.ITEM_CLASS_LABELS = ITEM_CLASS_LABELS
module.ITEM_CLASS_FILTER_ORDER = ITEM_CLASS_FILTER_ORDER
module.CATEGORY_SETTING_KEYS = CATEGORY_SETTING_KEYS
module.CATEGORY_ORDER = CATEGORY_ORDER

function module:GetKindLabel(kind)
    return KIND_LABELS[kind] or tostring(kind or "Unknown")
end

function module:GetEntryCategory(entry)
    local kind = type(entry) == "table" and entry.kind or entry
    return KIND_CATEGORY[kind] or "other"
end

function module:GetCategoryLabel(category)
    return CATEGORY_LABELS[category] or "Other"
end

-- ============================================================================
-- Shard helpers
-- ============================================================================

-- Returns the stable shard key for the current character. Faction is fixed at
-- character creation and never changes mid-session.
local function GetShardKey()
    local realm = GetRealmName and GetRealmName() or "UnknownRealm"
    local player = UnitName and UnitName("player") or "UnknownPlayer"
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    return realm .. "-" .. faction .. "-" .. player
end

-- Lifetime totals survive the maxEntries pruning in Record. We persist a
-- running income/expense sum per shard so the window footer can show a true
-- "since install" figure even after the oldest entries are trimmed. The fields
-- are backfilled once from the stored entries when missing; this is exact
-- unless the shard was already pruned before this field existed, in which case
-- the pre-existing pruned portion is unrecoverable (best-effort baseline).
-- Self-healing: any caller (migration, footer render) can call this and it
-- only walks the entries on the first touch, then returns O(1).
local function ComputeShardLifetime(shard)
    if type(shard) ~= "table" then return 0, 0 end
    if shard.lifetimeIncome == nil or shard.lifetimeExpense == nil then
        local inc, exp = 0, 0
        if type(shard.entries) == "table" then
            for _, e in ipairs(shard.entries) do
                local a = tonumber(e.amount) or 0
                if a > 0 then inc = inc + a
                elseif a < 0 then exp = exp + a end
            end
        end
        if shard.lifetimeIncome == nil then shard.lifetimeIncome = inc end
        if shard.lifetimeExpense == nil then shard.lifetimeExpense = exp end
    end
    return shard.lifetimeIncome, shard.lifetimeExpense
end

local function GetBlobEntryCount(blob)
    if type(blob) ~= "string" then return nil end
    local count = blob:match("^TBLOB[12];(%d+);")
    return tonumber(count)
end

local function MigrateShard(shard)
    if type(shard) ~= "table" then return end
    local fromVersion = tonumber(shard.schemaVersion) or 0
    if fromVersion < 1 then
        -- Ancient shards (pre-v1) have no blob; ensure a live entries table.
        if type(shard.entries) ~= "table" and not shard.blob then shard.entries = {} end
    end
    if fromVersion < 2 then
        ComputeShardLifetime(shard)
    end
    if fromVersion < 3 then
        -- Schema 3 introduces lazy-blob storage: history can live in shard.blob
        -- with shard.entries dropped while the shard is at rest. Seed the
        -- entry-count cache used by the at-rest displays.
        if shard.count == nil then
            shard.count = (type(shard.entries) == "table" and #shard.entries) or GetBlobEntryCount(shard.blob) or 0
        end
        -- Flag the FIRST blob conversion of pre-existing data for a full
        -- round-trip check (see DematerializeShard) so migrating a real ledger
        -- can never silently corrupt it. Cleared once verified.
        if type(shard.entries) == "table" and #shard.entries > 0 then
            shard._needsBlobVerify = true
        end
    end
    if fromVersion < 4 then
        -- Schema 4 removes the moneyLog sample array: it was appended on every
        -- PLAYER_MONEY (capped at 2880 samples per shard) but no view ever read
        -- it back -- dead weight in RAM and SavedVariables, per character.
        shard.moneyLog = nil
    end
    shard.schemaVersion = ACCOUNTING_SCHEMA_VERSION
end

-- Exposed so subfiles (EntryBlob's CompactInactiveShards) can run the full
-- per-shard migration before serializing an inactive shard.
module._migrateShard = MigrateShard

function module:GetShard()
    if not self.settings then return nil end
    if type(self.settings.shards) ~= "table" then
        self.settings.shards = {}
    end
    local key = GetShardKey()
    local shard = self.settings.shards[key]
    if type(shard) ~= "table" then
        shard = {
            schemaVersion = ACCOUNTING_SCHEMA_VERSION,
            entries = {},
            lastMoney = nil,
            lifetimeIncome = 0,
            lifetimeExpense = 0,
            count = 0,
        }
        self.settings.shards[key] = shard
    end
    MigrateShard(shard)
    -- The current character's shard is always live during its session: recording
    -- and item enrichment write directly to shard.entries. MaterializeShard is a
    -- cheap no-op when entries already exist, and deserializes shard.blob when
    -- the shard was left at rest by a previous session / compaction pass. (Never
    -- force entries = {} above: that would shadow an at-rest blob and a later
    -- DematerializeShard would overwrite real data with an empty list.)
    self:MaterializeShard(shard)
    return shard, key
end

-- Returns (lifetimeIncome, lifetimeExpense) for a shard, backfilling the
-- running totals from stored entries on first access. Exposed for the window
-- footer, which sums this across the in-scope shards to show all-time totals.
function module:GetShardLifetime(shard)
    return ComputeShardLifetime(shard)
end

function module:GetShardShortLabel(key)
    local realm, faction, player = tostring(key or ""):match("^(.*)%-([^%-]+)%-([^%-]+)$")
    if player and player ~= "" then return player end
    return tostring(key or "Unknown")
end

function module:GetShardLabel(key)
    local realm, faction, player = tostring(key or ""):match("^(.*)%-([^%-]+)%-([^%-]+)$")
    if player and player ~= "" then
        return string.format("%s - %s (%s)", player, realm or "UnknownRealm", faction or "Neutral")
    end
    return tostring(key or "Unknown")
end

function module:GetKnownShardKeys()
    local keys = {}
    self:GetShard()
    if not (self.settings and type(self.settings.shards) == "table") then return keys end
    for key, shard in pairs(self.settings.shards) do
        if type(key) == "string" and type(shard) == "table" then
            MigrateShard(shard)
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        return module:GetShardLabel(a) < module:GetShardLabel(b)
    end)
    return keys
end

function module:GetWindowShardFilter()
    local windowSettings = self.settings and self.settings.window
    if self.settings and type(windowSettings) ~= "table" then
        self.settings.window = {}
        windowSettings = self.settings.window
    end
    local value = windowSettings and windowSettings.characterFilter or "current"
    if value == "account" then value = "all" end
    if value ~= "current" and value ~= "all" then
        if not (self.settings and type(self.settings.shards) == "table" and type(self.settings.shards[value]) == "table") then
            value = "current"
        end
    end
    if windowSettings then windowSettings.characterFilter = value end
    return value
end

function module:SetWindowShardFilter(value)
    local windowSettings = self.settings and self.settings.window
    if self.settings and type(windowSettings) ~= "table" then
        self.settings.window = {}
        windowSettings = self.settings.window
    end
    if not windowSettings then return end
    if value ~= "current" and value ~= "all" then
        if not (self.settings and type(self.settings.shards) == "table" and type(self.settings.shards[value]) == "table") then
            value = "current"
        end
    end
    windowSettings.characterFilter = value or "current"
    self.windowState = self.windowState or {}
    self.windowState.characterFilter = windowSettings.characterFilter
end

function module:GetWindowShardList()
    local currentShard, currentKey = self:GetShard()
    local filter = self:GetWindowShardFilter()
    local list = {}
    if filter == "all" then
        for _, key in ipairs(self:GetKnownShardKeys()) do
            local shard = self.settings and self.settings.shards and self.settings.shards[key]
            if type(shard) == "table" then
                list[#list + 1] = { key = key, shard = shard }
            end
        end
    elseif filter ~= "current" then
        local shard = self.settings and self.settings.shards and self.settings.shards[filter]
        if type(shard) == "table" then
            list[#list + 1] = { key = filter, shard = shard }
        end
    end
    if #list == 0 and currentShard then
        list[#list + 1] = { key = currentKey, shard = currentShard }
    end
    return list
end

function module:GetWindowShardFilterButtonLabel()
    local filter = self:GetWindowShardFilter()
    if filter == "all" then return "Characters: All" end
    if filter == "current" then
        local _, currentKey = self:GetShard()
        return "Character: " .. self:GetShardShortLabel(currentKey)
    end
    return "Character: " .. self:GetShardShortLabel(filter)
end

function module:GetWindowShardFilterTitle()
    local filter = self:GetWindowShardFilter()
    if filter == "all" then return "All account characters" end
    if filter == "current" then
        local _, currentKey = self:GetShard()
        return self:GetShardLabel(currentKey)
    end
    return self:GetShardLabel(filter)
end

-- ============================================================================
-- Subject cache for mail classification
-- ============================================================================

-- Some Blizzard globals embed "%s" or other format specifiers in the localized
-- string. We strip everything from the first "%" onwards so prefix matching
-- against header subjects works ("Auction expired: Iron Bar" matches the
-- cached prefix "Auction expired:").
local function StripFormatSpecifiers(s)
    if type(s) ~= "string" then return nil end
    local cut = s:find("%%", 1, true)
    if cut then return s:sub(1, cut - 1) end
    return s
end

local function BuildSubjectCache()
    return {
        SOLD     = StripFormatSpecifiers(_G.AUCTION_SOLD_MAIL_SUBJECT),
        INVOICE  = StripFormatSpecifiers(_G.AUCTION_INVOICE_MAIL_SUBJECT),
        EXPIRED  = StripFormatSpecifiers(_G.AUCTION_EXPIRED_MAIL_SUBJECT),
        REMOVED  = StripFormatSpecifiers(_G.AUCTION_REMOVED_MAIL_SUBJECT),
        OUTBID   = StripFormatSpecifiers(_G.AUCTION_OUTBID_MAIL_SUBJECT),
        WON      = StripFormatSpecifiers(_G.AUCTION_WON_MAIL_SUBJECT),
    }
end

function module:EnsureSubjectCache()
    if module.CONSTANTS.SUBJECT_CACHE then return module.CONSTANTS.SUBJECT_CACHE end
    module.CONSTANTS.SUBJECT_CACHE = BuildSubjectCache()
    return module.CONSTANTS.SUBJECT_CACHE
end

-- ClassifySubject / ExtractItemFromSubject moved to
-- Modules/AccountingTracker/Mail.lua (mail-only consumers).

-- Detect an ItemLocation table (the Blizzard mixin used by C_AuctionHouse.
-- PostItem / PostCommodity). ItemLocations have bagID+slotIndex (bag) or
-- equipmentSlotIndex (equipped). GetItemInfo errors when handed one of
-- these, so we route them through C_Item.GetItemID instead.
local function IsItemLocationTable(value)
    if type(value) ~= "table" then return false end
    if value.bagID ~= nil and value.slotIndex ~= nil then return true end
    if value.equipmentSlotIndex ~= nil then return true end
    return false
end

local function GetItemInfoSafe(itemInfo)
    if itemInfo == nil then return nil, nil end

    -- ItemLocation tables make GetItemInfo throw a "bad argument" error
    -- ("Usage: local itemName, itemLink, ... = GetItemInfo(itemID|itemString|itemName)").
    -- Inside a hooksecurefunc body that error aborts the rest of the hook
    -- silently -- the exact failure mode that left AH-posted items un-cached.
    -- Translate the ItemLocation to an itemID first, then resolve normally.
    if IsItemLocationTable(itemInfo) then
        if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemID) == "function" then
            local okID, id = pcall(_G.C_Item.GetItemID, itemInfo)
            if okID and id then
                itemInfo = id
            else
                return nil, nil
            end
        else
            return nil, nil
        end
    end

    local getInfo
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfo) == "function" then
        getInfo = _G.C_Item.GetItemInfo
    elseif type(_G.GetItemInfo) == "function" then
        getInfo = _G.GetItemInfo
    end
    if not getInfo then return nil, nil end

    -- pcall belt-and-braces for any remaining edge cases (battle pet links,
    -- empty strings, etc.). Caught errors don't surface to the user.
    local ok, first, second = pcall(getInfo, itemInfo)
    if not ok then return nil, nil end
    if type(first) == "table" then
        return first.itemName or first.name, first.hyperlink or first.itemLink
    end
    return first, second
end

local function ExtractItemID(itemInfo)
    if type(itemInfo) == "number" then return itemInfo end
    if type(itemInfo) ~= "string" then return nil end
    return tonumber(itemInfo:match("item:(%d+)")) or tonumber(itemInfo)
end
module.GetItemInfoSafe = GetItemInfoSafe
module.ExtractItemID = ExtractItemID

local function GetItemInstantSafe(itemInfo)
    if itemInfo == nil then return nil end

    -- Same ItemLocation guard as GetItemInfoSafe -- GetItemInfoInstant also
    -- rejects ItemLocation tables.
    if IsItemLocationTable(itemInfo) then
        if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemID) == "function" then
            local okID, id = pcall(_G.C_Item.GetItemID, itemInfo)
            if okID and id then
                itemInfo = id
            else
                return nil
            end
        else
            return nil
        end
    end

    local getInstant
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfoInstant) == "function" then
        getInstant = _G.C_Item.GetItemInfoInstant
    elseif type(_G.GetItemInfoInstant) == "function" then
        getInstant = _G.GetItemInfoInstant
    end
    if not getInstant then return nil end

    local ok, itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = pcall(getInstant, itemInfo)
    if not ok then return nil end
    if type(itemID) == "table" then
        local info = itemID
        return {
            itemID = tonumber(info.itemID or info.itemId or info.id),
            itemClassName = info.itemType or info.className or info.itemClassName,
            itemSubClassName = info.itemSubType or info.subClassName or info.itemSubClassName,
            itemEquipLoc = info.itemEquipLoc or info.inventoryType,
            itemIcon = info.icon or info.itemIcon,
            itemClassID = tonumber(info.classID or info.itemClassID),
            itemSubClassID = tonumber(info.subClassID or info.itemSubClassID),
        }
    end
    return {
        itemID = tonumber(itemID),
        itemClassName = itemType,
        itemSubClassName = itemSubType,
        itemEquipLoc = itemEquipLoc,
        itemIcon = icon,
        itemClassID = tonumber(classID),
        itemSubClassID = tonumber(subClassID),
    }
end

local function GetAuctionItemLocationDisplay(itemLocation)
    local itemName, itemLink = GetItemInfoSafe(itemLocation)
    local itemID = ExtractItemID(itemLink)

    -- ItemLocation -> itemID via the canonical Blizzard API. This is the
    -- only path that reliably works when the item is mid-flight (just dragged
    -- from bag into AH post slot) and GetItemInfo hasn't been called for it
    -- yet this frame. Without this, GetAuctionItemLocationDisplay can return
    -- nil/nil/nil for the very item the player is posting -> no name cache,
    -- so the resulting sale mail later shows as plain text.
    if not itemID and type(_G.C_Item) == "table" and type(_G.C_Item.GetItemID) == "function" then
        local okID, idFromLoc = pcall(_G.C_Item.GetItemID, itemLocation)
        if okID then itemID = tonumber(idFromLoc) end
    end
    if itemID and (not itemName or not itemLink) then
        local n, l = GetItemInfoSafe(itemID)
        itemName = itemName or n
        itemLink = itemLink or l
    end
    if itemName or itemLink then
        return itemName, itemLink, itemID
    end

    if type(_G.C_AuctionHouse) == "table" and type(_G.C_AuctionHouse.GetItemKeyFromItem) == "function" then
        local okKey, itemKey = pcall(_G.C_AuctionHouse.GetItemKeyFromItem, itemLocation)
        if okKey and type(itemKey) == "table" then
            itemID = itemID or tonumber(itemKey.itemID or itemKey.itemId)
            if itemID then
                itemName, itemLink = GetItemInfoSafe(itemID)
            end
            if type(_G.C_AuctionHouse.GetItemKeyInfo) == "function" then
                local okInfo, keyInfo = pcall(_G.C_AuctionHouse.GetItemKeyInfo, itemKey)
                if okInfo and type(keyInfo) == "table" then
                    itemName = itemName or keyInfo.itemName or keyInfo.name
                    itemLink = itemLink or keyInfo.battlePetLink
                end
            end
        end
    end
    return itemName, itemLink, itemID
end

local function GetAuctionIDDisplay(auctionID)
    auctionID = tonumber(auctionID)
    if not auctionID then return nil, nil, nil end
    if type(_G.C_AuctionHouse) ~= "table" or type(_G.C_AuctionHouse.GetAuctionInfoByID) ~= "function" then
        return nil, nil, nil
    end
    local ok, info = pcall(_G.C_AuctionHouse.GetAuctionInfoByID, auctionID)
    if not ok or type(info) ~= "table" then return nil, nil, nil end
    local itemKey = info.itemKey
    local itemID = tonumber(info.itemID or (type(itemKey) == "table" and (itemKey.itemID or itemKey.itemId)))
    local itemName, itemLink
    if itemID then
        itemName, itemLink = GetItemInfoSafe(itemID)
    end
    if type(itemKey) == "table" and type(_G.C_AuctionHouse.GetItemKeyInfo) == "function" then
        local okInfo, keyInfo = pcall(_G.C_AuctionHouse.GetItemKeyInfo, itemKey)
        if okInfo and type(keyInfo) == "table" then
            itemName = itemName or keyInfo.itemName or keyInfo.name
            itemLink = itemLink or keyInfo.battlePetLink
        end
    end
    return itemName, itemLink, itemID
end

local function GetQuestTitleSafe(questID)
    questID = tonumber(questID)
    if not questID then return nil end
    if type(_G.C_QuestLog) == "table" and type(_G.C_QuestLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(_G.C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then return title end
    end
    return nil
end

-- GetInboxItemDisplay moved to Modules/AccountingTracker/Mail.lua.

function module:TrackPendingItemInfo(itemID)
    itemID = tonumber(itemID)
    if not itemID then return end
    self.pendingItemInfo = self.pendingItemInfo or {}
    self.pendingItemInfo[itemID] = true
end

function module:NormalizeItemFields(fields)
    if type(fields) ~= "table" then return end
    if fields.itemLink and not fields.item then
        fields.item = fields.itemLink
    end
    if not fields.itemName and type(fields.item) == "string" and fields.item ~= ""
        and not ExtractItemID(fields.item)
        and fields.item:find("^itemID:", 1, false) ~= 1
    then
        fields.itemName = fields.item
    end
    local itemID = tonumber(fields.itemID) or ExtractItemID(fields.itemLink) or ExtractItemID(fields.item)
    if not itemID then
        local lookup = fields.itemName or fields.item
        if type(lookup) == "string" and lookup ~= "" then
            -- Try persistent name->ID cache first (populated at AH posting)
            local cachedID = self:LookupItemIDByName(lookup)
            if cachedID then
                itemID = cachedID
                local cachedName, cachedLink = GetItemInfoSafe(cachedID)
                if cachedName and not fields.itemName then fields.itemName = cachedName end
                if cachedLink and not fields.itemLink then fields.itemLink = cachedLink end
                if cachedLink and not fields.item then fields.item = cachedLink end
            else
                local nameByLookup, linkByLookup = GetItemInfoSafe(lookup)
                if nameByLookup and not fields.itemName then fields.itemName = nameByLookup end
                if linkByLookup and not fields.itemLink then fields.itemLink = linkByLookup end
                if linkByLookup and not fields.item then fields.item = linkByLookup end
                itemID = ExtractItemID(linkByLookup)
            end
        end
    end
    if itemID and not fields.itemID then fields.itemID = itemID end
    if not itemID then return end

    local name, link = GetItemInfoSafe(itemID)
    if name and not fields.itemName then fields.itemName = name end
    if link and not fields.itemLink then fields.itemLink = link end
    local instant = GetItemInstantSafe(fields.itemLink or itemID)
    if instant then
        if instant.itemID and not fields.itemID then fields.itemID = instant.itemID end
        if instant.itemClassID and not fields.itemClassID then fields.itemClassID = instant.itemClassID end
        if instant.itemSubClassID and not fields.itemSubClassID then fields.itemSubClassID = instant.itemSubClassID end
        if instant.itemClassName and not fields.itemClassName then fields.itemClassName = instant.itemClassName end
        if instant.itemSubClassName and not fields.itemSubClassName then fields.itemSubClassName = instant.itemSubClassName end
        if instant.itemEquipLoc and not fields.itemEquipLoc then fields.itemEquipLoc = instant.itemEquipLoc end
        if instant.itemIcon and not fields.itemIcon then fields.itemIcon = instant.itemIcon end
    end
    if fields.item == nil or tostring(fields.item):find("^itemID:", 1, false) == 1 then
        fields.item = fields.itemLink or fields.itemName or ("itemID:" .. tostring(itemID))
    end
    if not name or not link then
        self:TrackPendingItemInfo(itemID)
    end
    -- Populate persistent name -> itemID cache for AH sale mail resolution
    if itemID and fields.itemName and type(fields.itemName) == "string" and fields.itemName ~= "" then
        self:CacheItemNameToID(fields.itemName, itemID)
    end
end

-- Persistent item name -> itemID lookup cache.
-- AH sale mails only carry a plain-text item name (no link, no ID).
-- This cache is populated from AH posting hooks and NormalizeItemFields
-- so we can resolve the name back to an itemID when the sale mail arrives.

function module:CacheItemNameToID(name, itemID)
    if not self.settings then return end
    if type(name) ~= "string" or name == "" then return end
    itemID = tonumber(itemID)
    if not itemID then return end
    if type(self.settings.itemNameToID) ~= "table" then
        self.settings.itemNameToID = {}
    end
    local cache = self.settings.itemNameToID
    if cache[name] == itemID then return end
    local isNewName = cache[name] == nil
    -- Live-generation size, counted lazily once per session (re-seeded after
    -- ApplySettings / ClearItemNameCache nil it) and then kept incrementally.
    -- A recount-on-demand session counter cannot drift across reloads the way
    -- a persisted counter would.
    if self._itemNameCacheCount == nil then
        local n = 0
        for _ in pairs(cache) do n = n + 1 end
        self._itemNameCacheCount = n
    end
    if isNewName and self._itemNameCacheCount >= (module.CONSTANTS.ITEM_NAME_CACHE_CAP or 4000) then
        -- Generation rotation: archive the full live table and restart it.
        -- Archived names stay resolvable via itemNameToIDPrev and are promoted
        -- back into the live generation on lookup (see LookupItemIDByName), so
        -- names in actual use survive; names never looked up again age out
        -- when the NEXT rotation discards this archive.
        self.settings.itemNameToIDPrev = cache
        cache = {}
        self.settings.itemNameToID = cache
        self._itemNameCacheCount = 0
    end
    if isNewName then
        self._itemNameCacheCount = self._itemNameCacheCount + 1
    end
    cache[name] = itemID
end

function module:LookupItemIDByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not self.settings then return nil end
    if type(self.settings.itemNameToID) == "table" then
        local id = tonumber(self.settings.itemNameToID[name])
        if id then return id end
    end
    local prev = self.settings.itemNameToIDPrev
    if type(prev) == "table" then
        local id = tonumber(prev[name])
        if id then
            -- Promote archived hits into the live generation so frequently
            -- used names keep surviving rotations.
            self:CacheItemNameToID(name, id)
            return id
        end
    end
    return nil
end

function module:BuildBagItemFields(bag, slot)
    if type(_G.C_Container) ~= "table" or type(_G.C_Container.GetContainerItemInfo) ~= "function" then
        return nil
    end
    local info = _G.C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" then return nil end

    local itemID = tonumber(info.itemID) or ExtractItemID(info.hyperlink)
    if not itemID and not info.hyperlink then return nil end

    local fields = {
        item = info.hyperlink or (itemID and ("itemID:" .. tostring(itemID)) or nil),
        itemLink = info.hyperlink or nil,
        itemID = itemID,
        qty = tonumber(info.stackCount) or 1,
    }
    self:NormalizeItemFields(fields)
    return fields, info.hasLoot == true
end

function module:IsLootContainerItem(fields)
    if type(fields) ~= "table" then return false end
    if tonumber(fields.itemClassID) == ITEM_CLASS_CONTAINER then return true end
    return fields.itemClassName == ITEM_CLASS_LABELS[ITEM_CLASS_CONTAINER]
end

-- Diagnostic chat print for AH post hooks. Visible only when verboseLogging
-- is enabled. Lets the user verify a post actually triggered our hook and
-- what we managed to extract from the itemLocation argument -- key for
-- diagnosing "post happened but cache stayed empty" reports.
function module:DebugLogPostHook(hookName, itemLocation, itemName, itemLink, itemID, quantity)
    if not (self.settings and self.settings.verboseLogging) then return end
    if not ns.Diagnostics then return end
    local locType = type(itemLocation)
    local locDesc = locType
    if locType == "number" then
        locDesc = "number(" .. tostring(itemLocation) .. ")"
    elseif locType == "table" then
        local idMethod = nil
        if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemID) == "function" then
            local ok, id = pcall(_G.C_Item.GetItemID, itemLocation)
            if ok then idMethod = tostring(id) end
        end
        locDesc = "table (C_Item.GetItemID=" .. tostring(idMethod) .. ")"
    end
    ns.Diagnostics:Info(string.format(
        "[acc-debug] %s fired: arg=%s name=%s id=%s qty=%s",
        tostring(hookName), locDesc,
        tostring(itemName), tostring(itemID), tostring(quantity)
    ))
end

-- Diagnostic snapshot of the persistent name -> itemID cache. Returns a
-- sorted list of { name, itemID, link } so the debug UI can render it as
-- a table without having to know the internal storage shape.
function module:GetItemNameCacheSnapshot()
    local entries = {}
    if not self.settings then return entries end
    local seen = {}
    local function collect(map)
        if type(map) ~= "table" then return end
        for name, itemID in pairs(map) do
            if not seen[name] then
                seen[name] = true
                local _, link = GetItemInfoSafe(tonumber(itemID))
                entries[#entries + 1] = {
                    name   = tostring(name),
                    itemID = tonumber(itemID),
                    link   = link,
                }
            end
        end
    end
    -- Live generation first so it wins over a stale archived duplicate.
    collect(self.settings.itemNameToID)
    collect(self.settings.itemNameToIDPrev)
    table.sort(entries, function(a, b) return a.name < b.name end)
    return entries
end

function module:ClearItemNameCache()
    if not self.settings then return 0 end
    local count = 0
    local current = self.settings.itemNameToID
    if type(current) == "table" then
        for _ in pairs(current) do count = count + 1 end
    end
    local prev = self.settings.itemNameToIDPrev
    if type(prev) == "table" then
        for name in pairs(prev) do
            if not (type(current) == "table" and current[name] ~= nil) then
                count = count + 1
            end
        end
    end
    self.settings.itemNameToID = {}
    self.settings.itemNameToIDPrev = nil
    self._itemNameCacheCount = 0
    return count
end

-- Seed the name->ID cache from existing ledger entries that already carry
-- both an itemID and an itemName. Helps populate the cache retroactively
-- for users who used the addon before the cache feature existed.
function module:BackfillItemNameCacheFromLedger()
    if not (self.settings and type(self.settings.shards) == "table") then return 0 end
    local added = 0
    for _, shard in pairs(self.settings.shards) do
        if type(shard) == "table" and type(shard.entries) == "table" then
            for _, entry in ipairs(shard.entries) do
                local id = tonumber(entry.itemID)
                local name = type(entry.itemName) == "string" and entry.itemName or nil
                if id and name and name ~= "" and not self:LookupItemIDByName(name) then
                    self:CacheItemNameToID(name, id)
                    added = added + 1
                end
            end
        end
    end
    return added
end

-- For each unresolved ledger entry (has itemName but no itemID), try a live
-- GetItemInfo lookup. If the client has the item cached this session, we
-- enrich the entry on the spot and seed the cache so it sticks across reloads.
-- Returns count of entries enriched.
function module:ResolveUnresolvedLedgerEntries()
    if not (self.settings and type(self.settings.shards) == "table") then return 0 end
    local resolved = 0
    for _, shard in pairs(self.settings.shards) do
        if type(shard) == "table" and type(shard.entries) == "table" then
            for _, entry in ipairs(shard.entries) do
                if not entry.itemID and not entry.itemLink and type(entry.itemName) == "string" and entry.itemName ~= "" then
                    local name, link = GetItemInfoSafe(entry.itemName)
                    local id = ExtractItemID(link)
                    if id then
                        entry.itemID = id
                        if name then entry.itemName = name end
                        if link then entry.itemLink = link end
                        if link and (not entry.item or tostring(entry.item):find("^itemID:", 1, false) == 1 or entry.item == name) then
                            entry.item = link
                        end
                        self:NormalizeItemFields(entry)
                        self:CacheItemNameToID(entry.itemName, id)
                        resolved = resolved + 1
                    end
                end
            end
        end
    end
    if resolved > 0 then self:QueueWindowRefresh() end
    return resolved
end

function module:IsHousingEntry(entry)
    return type(entry) == "table" and tonumber(entry.itemClassID) == ITEM_CLASS_HOUSING
end

function module:GetItemTypeLabel(entry)
    if self:IsHousingEntry(entry) then return "Housing" end
    if type(entry) ~= "table" then return "No item type" end
    if entry.itemClassName then return entry.itemClassName end
    if entry.itemClass then return entry.itemClass end
    local classID = tonumber(entry.itemClassID)
    if classID and ITEM_CLASS_LABELS[classID] then return ITEM_CLASS_LABELS[classID] end
    if entry.itemSubClassName then return entry.itemSubClassName end
    if entry.itemID or entry.itemLink or entry.item or entry.itemName then return "Item" end
    if entry.kind == module.CONSTANTS.KIND_QUEST then return "Quests" end
    return "No item type"
end

function module:EnsureEntryItemMetadata(entry)
    if type(entry) ~= "table" then return end
    if entry.itemClassID and entry.itemLink then return end
    if not entry.itemID and not entry.itemLink and not entry.item and not entry.itemName then return end
    self:NormalizeItemFields(entry)
end

function module:EnsureEntryQuestMetadata(entry)
    if type(entry) ~= "table" then return end
    if entry.kind ~= module.CONSTANTS.KIND_QUEST then return end
    if entry.questName or not entry.questID then return end
    local questTitle = GetQuestTitleSafe(entry.questID)
    if questTitle then
        entry.questName = questTitle
        if not entry.who or tostring(entry.who):find("^questID:", 1, false) == 1 then
            entry.who = questTitle
        end
    end
end

-- ============================================================================
-- Ledger writes
-- ============================================================================

local function NowEpoch()
    return time and time() or 0
end

local function NowPrecise()
    return GetTimePreciseSec and GetTimePreciseSec() or 0
end
module.NowEpoch = NowEpoch

-- Append a record to the current shard. Prunes oldest entries when capacity
-- is reached. Returns the appended entry (caller may decorate further).
function module:Record(kind, amount, fields)
    local shard = self:GetShard()
    if not shard then return nil end
    if type(kind) ~= "string" or kind == "" then return nil end

    local entry = {
        t      = NowEpoch(),
        kind   = kind,
        amount = tonumber(amount) or 0,
    }
    if type(fields) == "table" then
        self:NormalizeItemFields(fields)
        for k, v in pairs(fields) do
            if entry[k] == nil then entry[k] = v end
        end
    end

    local entries = shard.entries
    entries[#entries + 1] = entry

    -- CRITICAL: the shard may still carry an at-rest blob from a previous
    -- session (MaterializeShard keeps it so an UNCHANGED shard can be dropped
    -- again cheaply). This entry just made that blob stale. Without this
    -- invalidation, DematerializeShard's fast path would later discard the
    -- grown live entries in favour of the old blob -- silently rolling the
    -- ledger back to the blob snapshot on the next alt login / window close
    -- (the "ledger frozen since release day" bug). Never touch a blob that
    -- failed to parse (_blobError): that one is preserved for recovery.
    if shard.blob ~= nil and not shard._blobError then
        shard.blob = nil
    end

    -- Lifetime running totals. Incremented here, never decremented by the
    -- maxEntries pruning below, so the footer's all-time figure stays correct
    -- after old entries are trimmed. GetShard -> MigrateShard already ensured
    -- these fields are non-nil; the `or 0` is belt-and-suspenders.
    local recordedAmount = entry.amount or 0
    if recordedAmount > 0 then
        shard.lifetimeIncome = (shard.lifetimeIncome or 0) + recordedAmount
    elseif recordedAmount < 0 then
        shard.lifetimeExpense = (shard.lifetimeExpense or 0) + recordedAmount
    end

    -- Mark the ledger as needing a sweep when this new entry has an item
    -- name but no item ID resolved yet. OnItemInfoReceived's cross-shard
    -- scan reads this latch so it can skip the O(shards * entries) walk
    -- entirely once every unresolved entry has been upgraded. Over-setting
    -- is harmless (the scan re-evaluates the state every time it runs);
    -- the only correctness requirement is that we set it here whenever an
    -- unresolved entry enters the ledger.
    if entry.itemName and not entry.itemID then
        self._needsLedgerSweep = true
    end

    local cap = tonumber(self.settings.maxEntries) or 20000
    if #entries > cap then
        -- Drop oldest 10% in one go so we don't trim every single insert.
        local drop = math.floor(cap * 0.1)
        if drop < 1 then drop = 1 end
        -- Batch shift instead of looping table.remove(entries, 1): the latter
        -- is O(N) per call so dropping `drop` entries is O(N*drop) -- with the
        -- default cap=20000 / drop=2000 would be a large hitch with repeated
        -- table.remove(entries, 1) during power-user sessions (vendor sprees,
        -- AH sessions). The single-pass shift below is O(N) total.
        local n = #entries
        local kept = n - drop
        for i = 1, kept do
            entries[i] = entries[i + drop]
        end
        for i = kept + 1, n do
            entries[i] = nil
        end
    end

    if self.settings.verboseLogging and ns.Diagnostics then
        ns.Diagnostics:Info(("[Accounting] %s %s%s"):format(
            kind,
            self:FormatMoney(entry.amount),
            entry.item and (" " .. tostring(entry.item)) or ""
        ))
    end

    self:QueueWindowRefresh()
    return entry
end

function module:QueueWindowRefresh()
    if not (self.window and self.window:IsShown()) then return end
    if self.windowRefreshQueued then return end
    self.windowRefreshQueued = true
    local function refresh()
        module.windowRefreshQueued = false
        if module.window and module.window:IsShown() then
            module:RefreshWindow()
        end
    end
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0.05, refresh)
    else
        refresh()
    end
end

function module:GetPendingItemInfoCount()
    local total = 0
    if type(self.pendingItemInfo) == "table" then
        for _ in pairs(self.pendingItemInfo) do total = total + 1 end
    end
    return total
end

function module:OnItemInfoReceived(itemID, success)
    itemID = tonumber(itemID)
    if not itemID then return end
    -- Clear the pending marker even on success == false (item does not exist
    -- or cannot be resolved): a failed ID will never get a follow-up fire, so
    -- leaving it in pendingItemInfo would strand it for the whole session.
    if type(self.pendingItemInfo) == "table" then
        self.pendingItemInfo[itemID] = nil
    end
    if success == false then return end

    local itemName, itemLink = GetItemInfoSafe(itemID)
    if not itemName and not itemLink then return end

    -- Seed the persistent name->ID cache from every GET_ITEM_INFO_RECEIVED.
    -- This makes the lookup work for ANY item the client has ever queried,
    -- not just items the player posted to the AH via our hook.
    if itemName then
        self:CacheItemNameToID(itemName, itemID)
    end

    if type(self.hints) == "table" then
        for _, hint in ipairs(self.hints) do
            if hint.fields then
                local hintMatches = tonumber(hint.fields.itemID) == itemID
                if not hintMatches and itemName and not hint.fields.itemID
                    and (hint.fields.itemName == itemName or hint.fields.item == itemName)
                then
                    hint.fields.itemID = itemID
                    hintMatches = true
                end
                if hintMatches then self:NormalizeItemFields(hint.fields) end
            end
        end
    end

    -- Cross-shard sweep: upgrade any ledger entry that matches this itemID
    -- or whose plain-text item name finally resolves. This walk is the
    -- single most expensive thing the module does -- O(shards * entries)
    -- per fire, and GET_ITEM_INFO_RECEIVED bursts can run 100+ times during
    -- login alone. We gate it on the _needsLedgerSweep latch:
    --   * Record() sets the latch true whenever a new entry lands without
    --     an itemID (the only situation that creates work for this sweep).
    --   * The sweep itself clears the latch when it confirms no unresolved
    --     entries remain.
    -- Net effect for the login burst: the first few fires do the full walk
    -- and resolve everything, the remaining ~95% of fires short-circuit
    -- here without touching shard data.
    if not self._needsLedgerSweep then return end

    local changed = false
    local stillUnresolved = false
    if self.settings and type(self.settings.shards) == "table" then
        for _, shard in pairs(self.settings.shards) do
            if type(shard) == "table" and type(shard.entries) == "table" then
                for _, entry in ipairs(shard.entries) do
                    -- Match by itemID OR by itemName for entries that never got
                    -- an itemID resolved (typically AH sale mails -- the invoice
                    -- carries only a plain-text item name). Once GetItemInfo
                    -- delivers the data for a name we've seen, every matching
                    -- entry retroactively gets its link/category/icon.
                    local matchesByID = tonumber(entry.itemID) == itemID
                    local matchesByName = not matchesByID
                        and not entry.itemID
                        and itemName
                        and (entry.itemName == itemName
                            or (type(entry.item) == "string" and entry.item == itemName))
                    if matchesByID or matchesByName then
                        if matchesByName then entry.itemID = itemID end
                        if itemName and not entry.itemName then entry.itemName = itemName end
                        if itemLink and not entry.itemLink then entry.itemLink = itemLink end
                        if itemLink and (not entry.item or tostring(entry.item):find("^itemID:", 1, false) == 1 or entry.item == itemName) then
                            entry.item = itemLink
                        elseif itemName and (not entry.item or tostring(entry.item):find("^itemID:", 1, false) == 1) then
                            entry.item = itemName
                        end
                        self:NormalizeItemFields(entry)
                        changed = true
                    end
                    -- After potential mutation above, re-check: does this
                    -- entry still need a future sweep? Stays true if any
                    -- entry anywhere has an item name but no resolved ID.
                    if entry.itemName and not entry.itemID then
                        stillUnresolved = true
                    end
                end
            end
        end
    end
    -- If the walk confirmed every entry is resolved, latch the flag off so
    -- subsequent fires short-circuit. The latch is re-armed automatically
    -- whenever Record() inserts a new unresolved entry.
    if not stillUnresolved then
        self._needsLedgerSweep = false
    end
    if changed then
        self:QueueWindowRefresh()
    end
end

-- ============================================================================
-- Money formatting
-- ============================================================================

-- Format a signed copper amount as "+12g 34s 56c" or "-12g 34s 56c". Uses
-- Blizzard's GetCoinTextureString when available for proper icon rendering;
-- falls back to plain text for chat output.
function module:FormatMoney(copper)
    local n = tonumber(copper) or 0
    local abs = math.abs(n)
    local sign = n < 0 and "-" or "+"
    local g = math.floor(abs / 10000)
    local s = math.floor((abs % 10000) / 100)
    local c = abs % 100

    local texStr = ""
    if _G.GetCoinTextureString then
        local gIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
        local sIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
        local cIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
        if g > 0 then
            texStr = string.format("%d%s %02d%s %02d%s", g, gIcon, s, sIcon, c, cIcon)
        elseif s > 0 then
            texStr = string.format("%d%s %02d%s", s, sIcon, c, cIcon)
        else
            texStr = string.format("%d%s", c, cIcon)
        end
    else
        if g > 0 then
            texStr = string.format("%dg %02ds %02dc", g, s, c)
        elseif s > 0 then
            texStr = string.format("%ds %02dc", s, c)
        else
            texStr = string.format("%dc", c)
        end
    end
    return sign .. texStr
end

function module:FormatMoneyColored(copper)
    local n = tonumber(copper) or 0
    local text = self:FormatMoney(copper)
    if n > 0 then return "|cff00ff00" .. text .. "|r"
    elseif n < 0 then return "|cffff0000" .. text .. "|r"
    else return "|cffffffff" .. text .. "|r" end
end

-- ============================================================================
-- Source-hint queue (PLAYER_MONEY attribution)
-- ============================================================================

-- The attribution model: every "interesting" event (vendor click, quest turn
-- in, loot message, repair confirmation) leaves a hint with a timestamp.
-- When PLAYER_MONEY fires, we look back over hints within attributionWindow,
-- pick the most recent one, and record the delta with that source.
--
-- Hints are dequeued after use so back-to-back unrelated PLAYER_MONEY events
-- (e.g. mail money take + something else) don't reuse the same hint.
function module:PushHint(kind, fields, ttl)
    self.hints = self.hints or {}
    self.hints[#self.hints + 1] = {
        kind = kind,
        time = NowPrecise(),
        fields = fields or {},
        ttl = tonumber(ttl),
    }
    -- Cap hint history at 8 to bound search cost.
    while #self.hints > 8 do
        table.remove(self.hints, 1)
    end
end

function module:GetHintExpectedSign(kind)
    if kind == module.CONSTANTS.KIND_VENDOR_SELL
        or kind == module.CONSTANTS.KIND_AH_SALE
        or kind == module.CONSTANTS.KIND_AH_OUTBID
        or kind == module.CONSTANTS.KIND_QUEST
        or kind == module.CONSTANTS.KIND_LOOT
        or kind == module.CONSTANTS.KIND_MAIL_MONEY
        or kind == module.CONSTANTS.KIND_TRADE_IN
        or kind == module.CONSTANTS.KIND_WORK_ORDER
        or kind == module.CONSTANTS.KIND_COD_RECEIVED then
        return 1
    end
    if kind == module.CONSTANTS.KIND_VENDOR_BUY
        or kind == module.CONSTANTS.KIND_REPAIR
        or kind == module.CONSTANTS.KIND_AH_BUY
        or kind == module.CONSTANTS.KIND_AH_DEPOSIT
        or kind == module.CONSTANTS.KIND_POSTAGE
        or kind == module.CONSTANTS.KIND_TRADE_OUT
        or kind == module.CONSTANTS.KIND_COD_PAID then
        return -1
    end
    return nil
end

function module:HintMatchesDelta(hint, delta)
    if not hint then return false end
    if hint.kind == module.CONSTANTS.KIND_SUPPRESS then return true end
    local n = tonumber(delta) or 0
    if n == 0 then return false end
    if self.merchantOpen then
        if n > 0 and hint.kind ~= module.CONSTANTS.KIND_VENDOR_SELL then return false end
        if n < 0 and hint.kind ~= module.CONSTANTS.KIND_VENDOR_BUY and hint.kind ~= module.CONSTANTS.KIND_REPAIR then return false end
    end
    local fields = hint.fields or {}
    local exactAmount = tonumber(fields.amount)
    if exactAmount and exactAmount ~= 0 then
        if not ((exactAmount > 0 and n > 0) or (exactAmount < 0 and n < 0)) then return false end
        if math.abs(math.abs(exactAmount) - math.abs(n)) <= 1 then return true end
        if self.merchantOpen and hint.kind == module.CONSTANTS.KIND_VENDOR_BUY and n < 0 then
            fields._useDeltaAmount = true
            return true
        end
        return false
    end
    local expected = self:GetHintExpectedSign(hint.kind)
    if expected == 1 then return n > 0 end
    if expected == -1 then return n < 0 end
    return true
end

function module:ConsumeHint(delta)
    if not self.hints or #self.hints == 0 then return nil end
    local windowSec = tonumber(self.settings.attributionWindow) or 0.5
    local now = NowPrecise()
    -- Prefer exact-amount hints first, otherwise consume the oldest matching
    -- hint. Pure FIFO is wrong when an older sign-only AH deposit hint is
    -- still alive but a later exact repair/buy hint matches the delta.
    local fallbackIndex = nil
    local exactIndex = nil
    local i = 1
    while i <= #self.hints do
        local h = self.hints[i]
        local ttl = tonumber(h.ttl) or windowSec
        if (now - h.time) > ttl or not self:HintMatchesDelta(h, delta) then
            table.remove(self.hints, i)
        else
            local fields = h.fields or {}
            local exactAmount = tonumber(fields.amount)
            if exactAmount and exactAmount ~= 0 then
                exactIndex = i
                break
            end
            if not fallbackIndex then fallbackIndex = i end
            i = i + 1
        end
    end
    local index = exactIndex or fallbackIndex
    if index then return table.remove(self.hints, index) end
    return nil
end

-- ============================================================================
-- Money baseline
-- ============================================================================

function module:ResetMoneyBaseline()
    local shard = self:GetShard()
    if not shard then return end
    if _G.GetMoney then
        shard.lastMoney = _G.GetMoney()
    end
end

function module:OnPlayerMoney()
    local shard = self:GetShard()
    if not shard then return end
    local now = _G.GetMoney and _G.GetMoney() or 0
    local prev = shard.lastMoney
    shard.lastMoney = now
    if prev == nil then
        -- First read after login -- no delta to record. Seed baseline only.
        return
    end
    local delta = now - prev
    if delta == 0 then return end

    local hint = self:ConsumeHint(delta)
    if hint then
        -- KIND_SUPPRESS hint means a transaction was already recorded
        -- directly (quest reward, completed trade) and this PLAYER_MONEY tick
        -- is the mirrored delta -- swallow it silently.
        if hint.kind == module.CONSTANTS.KIND_SUPPRESS then return end
        local kind = hint.kind
        local fields = hint.fields or {}
        -- Some hint sources already know the amount precisely (repair cost,
        -- AH bid). When the hint declares amount, prefer the precise value
        -- over the delta (handles overlapping deltas).
        local amount = fields._useDeltaAmount and delta or fields.amount or delta
        fields.amount = nil
        fields._useDeltaAmount = nil
        self:Record(kind, amount, fields)
        return
    end

    if self.merchantOpen and delta > 0 then
        self:Record(module.CONSTANTS.KIND_VENDOR_SELL, delta, nil)
        return
    end

    if self.merchantOpen and delta < 0 then
        local repairCost = tonumber(self.merchantRepairCost) or 0
        if repairCost > 0 and math.abs(math.abs(delta) - repairCost) <= 1 then
            self:Record(module.CONSTANTS.KIND_REPAIR, delta, nil)
        else
            self:Record(module.CONSTANTS.KIND_VENDOR_BUY, delta, nil)
        end
        return
    end

    if self.settings.logUnattributed then
        self:Record(module.CONSTANTS.KIND_UNKNOWN, delta, nil)
    end
end

-- ============================================================================
-- Mail invoice scanning (AH sale/buy attribution)
-- ============================================================================
-- Moved to Modules/AccountingTracker/Mail.lua: MakeInvoiceKey / MakeSaleKey,
-- ClassifySubject / ExtractItemFromSubject / GetInboxItemDisplay, RecordAuctionSale,
-- OnMailInboxUpdate, AttachBuyerInvoiceToPurchase, ProcessMailEntry, OnMailClose,
-- RecordMailSaleFromCache / RecordMailSaleFromInvoice, OnTakeInboxMoney /
-- OnTakeInboxItem, OnSendMail, OnAutoLootMailItem, InstallMailHooks.

-- ============================================================================
-- Merchant hooks (vendor sell / buy / repair)
-- ============================================================================

-- Hook BuyMerchantItem to capture vendor buys with precise item info.
-- Hook UseContainerItem to capture vendor sells while a merchant is open and
-- loot containers while no merchant is open. The hooks themselves don't
-- record -- they push source hints so PLAYER_MONEY attribution gets the
-- precise item details.
function module:OnContainerItemUsed(bag, slot)
    local fields, hasLoot = self:BuildBagItemFields(bag, slot)
    if self.merchantOpen then
        if fields and (fields.itemLink or fields.itemID) then
            self:PushHint(module.CONSTANTS.KIND_VENDOR_SELL, fields, 3)
        end
        return
    end

    if hasLoot or self:IsLootContainerItem(fields) then
        self:PushHint(module.CONSTANTS.KIND_LOOT, fields, 5)
    end
end

function module:InstallMerchantHooks()
    if not self.buyHooked and type(_G.BuyMerchantItem) == "function" then
        hooksecurefunc("BuyMerchantItem", function(index, quantity)
            if not module.isActive then return end
            if not module.merchantOpen then return end
            local name, _, price, stackCount = nil, nil, nil, nil
            if type(_G.C_MerchantFrame) == "table" and type(_G.C_MerchantFrame.GetItemInfo) == "function" then
                local info = _G.C_MerchantFrame.GetItemInfo(index)
                if type(info) == "table" then
                    name       = info.name
                    price      = info.price
                    stackCount = info.stackCount
                end
            end
            local itemLink
            if type(_G.GetMerchantItemLink) == "function" then
                itemLink = _G.GetMerchantItemLink(index)
            end
            if not price and type(_G.GetMerchantItemInfo) == "function" then
                -- Legacy fallback (pre-11.0.5 retail or classic).
                name, _, price, stackCount = _G.GetMerchantItemInfo(index)
            end
            local qty = (tonumber(quantity) or 1) * (tonumber(stackCount) or 1)
            local totalPrice = -((tonumber(price) or 0) * (tonumber(quantity) or 1))
            module:PushHint(module.CONSTANTS.KIND_VENDOR_BUY, {
                item = itemLink or name,
                itemLink = itemLink,
                itemName = name,
                qty = qty,
                amount = totalPrice ~= 0 and totalPrice or nil,
            }, 3)
        end)
        self.buyHooked = true
    end

    if not self.buybackHooked and type(_G.BuybackItem) == "function" then
        hooksecurefunc("BuybackItem", function(index)
            if not module.isActive then return end
            local name, _, price = nil, nil, nil
            if type(_G.GetBuybackItemInfo) == "function" then
                name, _, price = _G.GetBuybackItemInfo(index)
            end
            local itemLink
            if type(_G.GetBuybackItemLink) == "function" then
                itemLink = _G.GetBuybackItemLink(index)
            end
            module:PushHint(module.CONSTANTS.KIND_VENDOR_BUY, {
                item   = itemLink or name,
                itemLink = itemLink,
                itemName = name,
                amount = price and -price or nil,
            }, 3)
        end)
        self.buybackHooked = true
    end

    -- Vendor sell / loot container: hook UseContainerItem once and gate the
    -- attribution path on the current merchant state inside the handler.
    if not self.sellHooked and type(_G.C_Container) == "table" and type(_G.C_Container.UseContainerItem) == "function" then
        hooksecurefunc(_G.C_Container, "UseContainerItem", function(bag, slot)
            if not module.isActive then return end
            module:OnContainerItemUsed(bag, slot)
        end)
        self.sellHooked = true
    end

    self.merchantHooksInstalled = self.buyHooked or self.buybackHooked or self.sellHooked
end

-- Repair detection: when the merchant frame is open and supports repair, we
-- snapshot the repair cost. On PLAYER_MONEY with a matching negative delta
-- shortly after the user clicks Repair, we record the expense.
function module:OnMerchantShow()
    self.merchantOpen = true
    -- Snapshot the repair cost so RepairAllItems / "Repair Equipment" can be
    -- attributed even when the user doesn't click via our hook surface.
    if type(_G.CanMerchantRepair) == "function" and _G.CanMerchantRepair() then
        if type(_G.GetRepairAllCost) == "function" then
            local cost = _G.GetRepairAllCost()
            self.merchantRepairCost = tonumber(cost) or 0
        end
    end
    self:InstallMerchantHooks()
    -- Install one-shot hook on RepairAllItems for precise attribution.
    if type(_G.RepairAllItems) == "function" and not self.repairHooked then
        hooksecurefunc("RepairAllItems", function(useGuildBank)
            if not module.isActive then return end
            if useGuildBank then return end -- guild repair has no personal money delta
            local cost = module.merchantRepairCost or 0
            if cost > 0 then
                module:PushHint(module.CONSTANTS.KIND_REPAIR, {
                    amount = -cost,
                })
            end
        end)
        self.repairHooked = true
    end
end

function module:OnMerchantUpdate()
    -- Refresh repair-cost snapshot (durability ticks while merchant frame is
    -- open should keep our cached cost in sync).
    if self.merchantOpen and type(_G.CanMerchantRepair) == "function" and _G.CanMerchantRepair() then
        if type(_G.GetRepairAllCost) == "function" then
            local cost = _G.GetRepairAllCost()
            self.merchantRepairCost = tonumber(cost) or 0
        end
    end
end

function module:OnMerchantClose()
    self.merchantOpen = false
    self.merchantRepairCost = nil
end

-- ============================================================================
-- Quest reward
-- ============================================================================

function module:OnQuestTurnedIn(questID, xpReward, moneyReward)
    local amount = tonumber(moneyReward) or 0
    if amount <= 0 then return end
    local questTitle = GetQuestTitleSafe(questID)
    -- Record directly: the amount is known precisely from the event payload,
    -- and going through the hint queue would race with concurrent loot/vendor
    -- ticks (CHAT_MSG_MONEY firing in the same frame as QUEST_TURNED_IN).
    self:Record(module.CONSTANTS.KIND_QUEST, amount, {
        questID = tonumber(questID),
        questName = questTitle,
        who = questTitle or ("questID:" .. tostring(questID)),
        qty = tonumber(xpReward) or nil,
    })
    -- Suppress the mirroring PLAYER_MONEY delta so it doesn't land as unknown
    -- (or get attributed to whatever stale hint is in the queue).
    self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
end

-- ============================================================================
-- Loot money tag
-- ============================================================================

function module:OnLootMoney()
    -- CHAT_MSG_MONEY arrives immediately before PLAYER_MONEY. Push a hint
    -- so the delta lands under KIND_LOOT. We don't parse the text since
    -- the PLAYER_MONEY delta is more accurate (and locale-independent).
    self:PushHint(module.CONSTANTS.KIND_LOOT, {})
end

-- ============================================================================
-- Work order fulfillment
-- ============================================================================

local function GetWorkOrderTypeLabel(orderType)
    local enum = _G.Enum and _G.Enum.CraftingOrderType
    if enum then
        if orderType == enum.Public then return "Public Work Order" end
        if orderType == enum.Guild then return "Guild Work Order" end
        if orderType == enum.Personal then return "Personal Work Order" end
        if orderType == enum.Npc then return "Patron Work Order" end
    end
    return "Work Order"
end

local function CopyWorkOrderSnapshot(order)
    if type(order) ~= "table" then return nil end
    return {
        orderID = tonumber(order.orderID),
        tipAmount = tonumber(order.tipAmount) or 0,
        consortiumCut = tonumber(order.consortiumCut) or 0,
        customerName = order.customerName,
        orderType = order.orderType,
        outputItemHyperlink = order.outputItemHyperlink,
        recraftItemHyperlink = order.recraftItemHyperlink,
        spellID = tonumber(order.spellID),
        isRecraft = order.isRecraft,
    }
end

function module:SnapshotClaimedWorkOrder()
    local api = _G.C_CraftingOrders
    if type(api) ~= "table" or type(api.GetClaimedOrder) ~= "function" then return nil end
    local ok, order = pcall(api.GetClaimedOrder)
    if not ok or type(order) ~= "table" then return nil end
    local snapshot = CopyWorkOrderSnapshot(order)
    if snapshot and snapshot.orderID then
        self.claimedWorkOrderSnapshot = snapshot
    end
    return snapshot
end

function module:GetWorkOrderForFulfillment(orderID)
    orderID = tonumber(orderID)
    local live = self:SnapshotClaimedWorkOrder()
    if live and tonumber(live.orderID) == orderID then return live end
    local snapshot = self.claimedWorkOrderSnapshot
    if type(snapshot) == "table" and tonumber(snapshot.orderID) == orderID then return snapshot end
    return nil
end

function module:BuildWorkOrderHintFields(orderID)
    local order = self:GetWorkOrderForFulfillment(orderID)
    if type(order) ~= "table" then return nil end

    local tip = tonumber(order.tipAmount) or 0
    local cut = tonumber(order.consortiumCut) or 0
    local net = tip - cut
    if net <= 0 then return nil end

    local itemLink = order.outputItemHyperlink or order.recraftItemHyperlink
    local itemName
    if itemLink then
        itemName = GetItemInfoSafe(itemLink)
    end

    local fields = {
        amount = net,
        tipAmount = tip,
        consortiumCut = cut,
        workOrderID = tonumber(order.orderID),
        workOrderType = GetWorkOrderTypeLabel(order.orderType),
        who = order.customerName,
        item = itemLink or itemName,
        itemLink = itemLink,
        itemName = itemName,
        itemID = ExtractItemID(itemLink),
        qty = 1,
        spellID = tonumber(order.spellID),
    }
    self:NormalizeItemFields(fields)
    return fields
end

function module:InstallWorkOrderHooks()
    if self.workOrderFulfillHooked then return end
    local api = _G.C_CraftingOrders
    if type(api) ~= "table" or type(api.FulfillOrder) ~= "function" then return end
    hooksecurefunc(api, "FulfillOrder", function(orderID)
        if not module.isActive then return end
        local fields = module:BuildWorkOrderHintFields(orderID)
        if fields then
            module:PushHint(module.CONSTANTS.KIND_WORK_ORDER, fields, 8)
        end
    end)
    self.workOrderFulfillHooked = true
end

-- ============================================================================
-- AH posting / cancellation
-- ============================================================================

-- AH hooks. Installed at OnEnable because C_AuctionHouse is part of the core
-- API (always loaded; not gated by Blizzard_AuctionHouseUI LoD). We hook
-- BEFORE the server call so the hint lands in the queue ahead of the
-- resulting PLAYER_MONEY tick -- the event-based path is too late.
function module:InstallAHHooks()
    if type(_G.C_AuctionHouse) ~= "table" then return end

    -- Commodity purchase: ConfirmCommoditiesPurchase fires the actual
    -- money-deducting RPC. itemID is in the args; precise amount comes via
    -- the resulting PLAYER_MONEY delta.
    if not self.ahBuyHooked and type(_G.C_AuctionHouse.ConfirmCommoditiesPurchase) == "function" then
        hooksecurefunc(_G.C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
            if not module.isActive then return end
            local itemName, itemLink = GetItemInfoSafe(itemID)
            module:PushHint(module.CONSTANTS.KIND_AH_BUY, {
                item = itemLink or itemName or ("itemID:" .. tostring(itemID)),
                itemLink = itemLink,
                itemName = itemName,
                itemID = tonumber(itemID),
                qty = tonumber(quantity) or 1,
            }, 5)
        end)
        self.ahBuyHooked = true
    end

    -- Item bid / buyout. bidAmount is the exact copper that'll be deducted.
    -- Direct buyout uses the same API with bidAmount == buyout. Bids on
    -- non-buyout items also deduct copper here (refunded if outbid).
    if not self.ahBidHooked and type(_G.C_AuctionHouse.PlaceBid) == "function" then
        hooksecurefunc(_G.C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
            if not module.isActive then return end
            local amt = tonumber(bidAmount) or 0
            if amt <= 0 then return end
            local itemName, itemLink, itemID = GetAuctionIDDisplay(auctionID)
            module:PushHint(module.CONSTANTS.KIND_AH_BUY, {
                amount = -amt,
                item = itemLink or itemName,
                itemLink = itemLink,
                itemName = itemName,
                itemID = itemID,
                qty = 1,
                who    = "auctionID:" .. tostring(auctionID),
            }, 5)
        end)
        self.ahBidHooked = true
    end

    -- Posting: deposit is deducted immediately on the post call. We don't
    -- know the deposit amount up front without calling CalculateItemDeposit,
    -- so let the PLAYER_MONEY delta carry the cost.
    if not self.ahPostItemHooked and type(_G.C_AuctionHouse.PostItem) == "function" then
        hooksecurefunc(_G.C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity)
            if not module.isActive then return end
            local itemName, itemLink, itemID = GetAuctionItemLocationDisplay(itemLocation)
            module:DebugLogPostHook("PostItem", itemLocation, itemName, itemLink, itemID, quantity)
            module:RememberLastPostedItem(itemLocation, itemName, itemLink, itemID, quantity)
            if itemName and itemID then
                module:CacheItemNameToID(itemName, itemID)
            elseif itemID then
                module:TrackPendingItemInfo(itemID)
                GetItemInfoSafe(itemID)
            end
            module:PushHint(module.CONSTANTS.KIND_AH_DEPOSIT, {
                item = itemLink or itemName or (itemID and ("itemID:" .. tostring(itemID)) or nil),
                itemLink = itemLink,
                itemName = itemName,
                itemID = itemID,
                qty = tonumber(quantity) or 1,
            }, 5)
        end)
        self.ahPostItemHooked = true
    end

    if not self.ahPostCommodityHooked and type(_G.C_AuctionHouse.PostCommodity) == "function" then
        hooksecurefunc(_G.C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity)
            if not module.isActive then return end
            local itemName, itemLink, itemID = GetAuctionItemLocationDisplay(itemLocation)
            module:DebugLogPostHook("PostCommodity", itemLocation, itemName, itemLink, itemID, quantity)
            module:RememberLastPostedItem(itemLocation, itemName, itemLink, itemID, quantity)
            if itemName and itemID then
                module:CacheItemNameToID(itemName, itemID)
            elseif itemID then
                module:TrackPendingItemInfo(itemID)
                GetItemInfoSafe(itemID)
            end
            module:PushHint(module.CONSTANTS.KIND_AH_DEPOSIT, {
                item = itemLink or itemName or (itemID and ("itemID:" .. tostring(itemID)) or nil),
                itemLink = itemLink,
                itemName = itemName,
                itemID = itemID,
                qty = tonumber(quantity) or 1,
            }, 5)
        end)
        self.ahPostCommodityHooked = true
    end

    self.ahHooksInstalled = self.ahBuyHooked or self.ahBidHooked or self.ahPostItemHooked or self.ahPostCommodityHooked
end

function module:OnAuctionHouseShow()
    self.ahOpen = true
    self:InstallAHHooks()
    self:RequestOwnedAuctionsScan()
end

-- Snapshot the most recent PostItem/PostCommodity argument so that
-- OnAuctionHouseAuctionCreated can fall back to it when GetAuctionInfoByID
-- returns nothing (which happens reliably when the user closes the AH frame
-- in the same frame as the post -- the local auction-info cache is torn
-- down before the 0.5s retry can run).
function module:RememberLastPostedItem(itemLocation, itemName, itemLink, itemID, quantity)
    -- Re-extract itemID via every known path; if even ONE works we're set.
    if not itemID and type(_G.C_Item) == "table" and type(_G.C_Item.GetItemID) == "function" then
        local ok, id = pcall(_G.C_Item.GetItemID, itemLocation)
        if ok then itemID = tonumber(id) end
    end
    if itemID and not itemName then
        itemName = GetItemInfoSafe(itemID)
    end
    self.lastPostedItem = {
        time     = NowPrecise(),
        itemID   = itemID,
        itemName = itemName,
        itemLink = itemLink,
        quantity = tonumber(quantity) or 1,
    }
end

-- Fires after the server confirms a new posting. Carries auctionID, which
-- we resolve via GetAuctionInfoByID -> itemKey -> itemID -> itemName. This
-- is the critical fix for "post then close AH immediately" because the
-- owned-auctions scanner needs the AH frame open to round-trip the query,
-- but GetAuctionInfoByID works straight off the just-created auction. When
-- even that returns nothing (cache cleared by AH close), the lastPostedItem
-- snapshot taken inside the PostItem/PostCommodity hook saves us.
function module:OnAuctionHouseAuctionCreated(auctionID)
    auctionID = tonumber(auctionID)
    if not auctionID then return end

    local itemName, itemLink, itemID = GetAuctionIDDisplay(auctionID)

    -- Fall back to whatever the most recent PostItem/PostCommodity hook
    -- saw, as long as it was within the last 5 seconds (i.e. plausibly the
    -- same post that just got confirmed by the server).
    if (not itemName or not itemID) and type(self.lastPostedItem) == "table" then
        local age = NowPrecise() - (self.lastPostedItem.time or 0)
        if age >= 0 and age <= 5 then
            itemName = itemName or self.lastPostedItem.itemName
            itemLink = itemLink or self.lastPostedItem.itemLink
            itemID   = itemID   or self.lastPostedItem.itemID
        end
    end

    if self.settings and self.settings.verboseLogging and ns.Diagnostics then
        ns.Diagnostics:Info(string.format(
            "[acc-debug] AUCTION_HOUSE_AUCTION_CREATED auctionID=%d name=%s id=%s",
            auctionID, tostring(itemName), tostring(itemID)
        ))
    end

    if itemName and itemID then
        self:CacheItemNameToID(itemName, itemID)
    elseif itemID then
        self:TrackPendingItemInfo(itemID)
        GetItemInfoSafe(itemID)
    end

    -- GetAuctionInfoByID can return nil right at AUCTION_HOUSE_AUCTION_CREATED
    -- because the local cache hasn't been populated yet. Retry after a beat.
    if (not itemName or not itemID) and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0.5, function()
            if not module.isActive then return end
            local n, _, id = GetAuctionIDDisplay(auctionID)
            if n and id then module:CacheItemNameToID(n, id) end
        end)
    end
end

-- Scan the player's owned auctions and seed the name->ID cache from each
-- one. This is the safety-net path: it works regardless of WHICH posting API
-- the user used (Blizzard UI, TSM, third-party batch posters). The post-hook
-- path can fail when the addon was loaded mid-flight or the posting API
-- bypasses C_AuctionHouse, but every owned auction will eventually show up
-- here as long as the player opens the AH window.
function module:ScanOwnedAuctions()
    if type(_G.C_AuctionHouse) ~= "table" then return 0 end
    local getNum = _G.C_AuctionHouse.GetNumOwnedAuctions
    local getInfo = _G.C_AuctionHouse.GetOwnedAuctionInfo
    if type(getNum) ~= "function" or type(getInfo) ~= "function" then return 0 end
    local okCount, count = pcall(getNum)
    if not okCount or type(count) ~= "number" or count <= 0 then
        if self.settings and self.settings.verboseLogging and ns.Diagnostics then
            ns.Diagnostics:Info(string.format("[acc-debug] ScanOwnedAuctions: 0 owned auctions (ok=%s)", tostring(okCount)))
        end
        return 0
    end
    local added = 0
    for i = 1, count do
        local okInfo, info = pcall(getInfo, i)
        if okInfo and type(info) == "table" then
            local itemKey = info.itemKey
            local itemID = tonumber(info.itemID
                or (type(itemKey) == "table" and (itemKey.itemID or itemKey.itemId)))
            local itemName
            if itemID then
                itemName = GetItemInfoSafe(itemID)
                if not itemName and type(_G.C_AuctionHouse.GetItemKeyInfo) == "function" and type(itemKey) == "table" then
                    local okKey, keyInfo = pcall(_G.C_AuctionHouse.GetItemKeyInfo, itemKey)
                    if okKey and type(keyInfo) == "table" then
                        itemName = keyInfo.itemName or keyInfo.name
                    end
                end
            end
            if itemName and itemID and not self:LookupItemIDByName(itemName) then
                self:CacheItemNameToID(itemName, itemID)
                added = added + 1
            elseif itemID and not itemName then
                -- Trigger async fetch; OnItemInfoReceived will cache later.
                self:TrackPendingItemInfo(itemID)
                GetItemInfoSafe(itemID)
            end
        end
    end
    if self.settings and self.settings.verboseLogging and ns.Diagnostics then
        ns.Diagnostics:Info(string.format("[acc-debug] ScanOwnedAuctions: %d auctions, %d new cache entries", count, added))
    end
    return added
end

-- Owned-auctions data isn't ready immediately on AUCTION_HOUSE_SHOW -- the
-- server has to round-trip the query first. We fire QueryOwnedAuctions and
-- then poll briefly (Blizzard fires OWNED_AUCTIONS_UPDATED but registering
-- that event adds noise; a couple of timed scans is simpler and effective).
function module:RequestOwnedAuctionsScan()
    if type(_G.C_AuctionHouse) ~= "table" then return end
    if type(_G.C_AuctionHouse.QueryOwnedAuctions) == "function" then
        pcall(_G.C_AuctionHouse.QueryOwnedAuctions, {})
    end
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0.6, function() if module.isActive then module:ScanOwnedAuctions() end end)
        _G.C_Timer.After(2.0, function() if module.isActive then module:ScanOwnedAuctions() end end)
    end
end

function module:OnAuctionHouseClose()
    self.ahOpen = false
end

-- ============================================================================
-- Trade window
-- ============================================================================

local function SafeCopper(value)
    if ns.Compat and ns.Compat.IsNonSecretNumber then
        if not ns.Compat.IsNonSecretNumber(value) then
            return 0
        end
    elseif type(value) ~= "number" then
        return 0
    end
    return tonumber(value) or 0
end

local function GetTradePartnerName()
    local name = (_G.UnitName and _G.UnitName("npc")) or nil
    if (not name or name == "") and _G.TradeFrameRecipientNameText
        and type(_G.TradeFrameRecipientNameText.GetText) == "function" then
        name = _G.TradeFrameRecipientNameText:GetText()
    end
    if not name or name == "" then
        if ns.Diagnostics then
            ns.Diagnostics:Warn("Accounting trade partner was unavailable.")
        end
        return "<unknown trade partner>"
    end
    return name
end

function module:OnTradeShow()
    self.tradeOpen = true
    self.tradeSnapshot = nil
end

function module:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if not self.tradeOpen then return end
    -- Snapshot the final state when both sides accept. TRADE_CLOSED fires
    -- right after; we use the snapshot to decide income vs expense.
    local playerReady = playerAccepted == 1 or playerAccepted == true
    local targetReady = targetAccepted == 1 or targetAccepted == true
    if playerReady and targetReady then
        local pMoney = (_G.GetPlayerTradeMoney and _G.GetPlayerTradeMoney()) or 0
        local tMoney = (_G.GetTargetTradeMoney and _G.GetTargetTradeMoney()) or 0
        self.tradeSnapshot = {
            playerMoney = SafeCopper(pMoney),
            targetMoney = SafeCopper(tMoney),
            partner     = GetTradePartnerName(),
        }
    end
end

function module:OnTradeClose()
    self.tradeOpen = false
    local snap = self.tradeSnapshot
    self.tradeSnapshot = nil
    if not snap then return end
    -- Record both legs directly. Going via hints would either double-consume
    -- (PLAYER_MONEY fires only once with NET delta) or race with concurrent
    -- events. Trade amounts are exactly known from the accept-time snapshot.
    if snap.playerMoney > 0 then
        self:Record(module.CONSTANTS.KIND_TRADE_OUT, -snap.playerMoney, {
            who = snap.partner,
        })
    end
    if snap.targetMoney > 0 then
        self:Record(module.CONSTANTS.KIND_TRADE_IN, snap.targetMoney, {
            who = snap.partner,
        })
    end
    -- Suppress the mirroring PLAYER_MONEY tick (will fire with NET delta).
    -- Only if a money exchange actually happened -- pure item trades have
    -- no PLAYER_MONEY tick to swallow.
    if snap.playerMoney > 0 or snap.targetMoney > 0 then
        self:PushHint(module.CONSTANTS.KIND_SUPPRESS, {})
    end
end

-- Reporting and slash commands live in Modules/AccountingTracker/Commands.lua.

-- ============================================================================
-- Lifecycle
-- ============================================================================

function module:OnEnable(settings)
    self.isActive = true
    self.settings = settings or self.defaults
    -- Search filter is session-scoped: clear any stale string from the last
    -- session so the user starts with a clean ledger view. The yellow search-
    -- bar highlight + subtitle suffix make active filters obvious within a
    -- session; preserving them across logins just confuses casual users who
    -- forget they typed something the day before.
    if type(self.settings) == "table" and type(self.settings.window) == "table" then
        self.settings.window.search = ""
    end
    if type(self.windowState) == "table" then
        self.windowState.search = ""
    end
    self._drilldownSearch = nil
    -- Seed the money baseline immediately. PLAYER_ENTERING_WORLD only fires
    -- on login / zone change / reload, so mid-session enable would otherwise
    -- leave lastMoney = nil and drop the first PLAYER_MONEY's hint (the very
    -- first vendor sale right after enable would otherwise vanish).
    self:ResetMoneyBaseline()
    -- Install merchant hooks now so a vendor click immediately after enable
    -- pushes its source hint even if MERCHANT_SHOW already fired earlier.
    self:InstallMerchantHooks()
    -- AH hooks (C_AuctionHouse is core API, always available -- not LoD).
    -- Hooked at pre-call site so hints land BEFORE the resulting PLAYER_MONEY
    -- tick (the COMMODITY_PURCHASE_SUCCEEDED / ITEM_PURCHASED events fire
    -- after the money already moved, too late to attribute).
    self:InstallAHHooks()
    self:InstallWorkOrderHooks()
    self:InstallMailHooks()
    self:InstallUIHooks()
    self:UpdateMinimapButton()
    -- Subject cache lookup uses _G.AUCTION_*_MAIL_SUBJECT globals; those are
    -- populated by PLAYER_LOGIN, so any post-login enable is safe.
    self:EnsureSubjectCache()
    -- Force the first GET_ITEM_INFO_RECEIVED to actually run the cross-shard
    -- sweep, since restored SavedVariables may contain unresolved entries
    -- from prior sessions. The sweep itself will clear the latch once it
    -- confirms the ledger is clean. Without this, a nil latch would short-
    -- circuit the first sweep and leave older AH-sale entries stuck without
    -- item links forever.
    self._needsLedgerSweep = true
    -- Compact other characters' history into blobs shortly after login so it
    -- does not sit in RAM during normal play (the main idle-memory win for
    -- multi-character accounts). Deferred so it never adds to the login hitch;
    -- the current character's shard stays live for recording. Uses the
    -- frame-spread variant so the one-time first-run migration (serialize +
    -- full-verify of every other character) can never stack into a freeze.
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(3, function()
            if module.isActive and module.CompactInactiveShardsSpread then
                module:CompactInactiveShardsSpread()
            end
        end)
    elseif self.CompactInactiveShards then
        self:CompactInactiveShards()
    end
end

function module:OnDisable()
    self.isActive = false
    self.merchantOpen = false
    self.ahOpen = false
    self.tradeOpen = false
    self.hints = nil
    self.seenInvoices = nil
    self.claimedWorkOrderSnapshot = nil
    -- Close the ledger window so the user doesn't see stale data after disable.
    if self.window then self.window:Hide() end
    if self.minimapButton then self.minimapButton:Hide() end
end

function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    -- The settings table may have been swapped or wiped (profile reset,
    -- Restore Defaults): drop the session name-cache counter so the next
    -- cache write recounts against the actual table.
    self._itemNameCacheCount = nil
    local windowSettings = self.EnsureWindowSettings and self.EnsureWindowSettings(self.settings)
    if windowSettings then
        self.windowState = self.windowState or {}
        self.windowState.tab = windowSettings.tab
        self.windowState.bucket = windowSettings.bucket
        self.windowState.search = windowSettings.search
        self.windowState.groupBy = windowSettings.groupBy
        self.windowState.chartView = windowSettings.chartView
        self.windowState.hiddenItemTypes = windowSettings.hiddenItemTypes or {}
        self.windowState.characterFilter = windowSettings.characterFilter
    end
    self:UpdateMinimapButton()
    if self.window then
        self:ApplyWindowSize()
        self:ApplyWindowPosition()
        self:RefreshWindow()
    end
end

function module:OnEvent(event, arg1, arg2, arg3)
    if event == "PLAYER_ENTERING_WORLD" then
        self:ResetMoneyBaseline()
        self:EnsureSubjectCache()
        self:InstallMerchantHooks()
        self:InstallAHHooks()
        self:InstallWorkOrderHooks()
        self:InstallMailHooks()
    elseif event == "PLAYER_MONEY" then
        self:OnPlayerMoney()
    elseif event == "MERCHANT_SHOW" then
        self:OnMerchantShow()
    elseif event == "MERCHANT_UPDATE" then
        self:OnMerchantUpdate()
    elseif event == "MERCHANT_CLOSED" then
        self:OnMerchantClose()
    elseif event == "MAIL_SHOW" then
        self.mailOpen = true
    elseif event == "MAIL_INBOX_UPDATE" then
        self:OnMailInboxUpdate()
    elseif event == "MAIL_CLOSED" then
        self.mailOpen = false
        self:OnMailClose()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        self:OnItemInfoReceived(arg1, arg2)
    elseif event == "QUEST_TURNED_IN" then
        self:OnQuestTurnedIn(arg1, arg2, arg3)
    elseif event == "CHAT_MSG_MONEY" then
        self:OnLootMoney()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        -- Refresh repair cost while merchant frame is open.
        if self.merchantOpen then self:OnMerchantUpdate() end
    elseif event == "AUCTION_HOUSE_SHOW" then
        self:OnAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        self:OnAuctionHouseClose()
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        self:OnAuctionHouseAuctionCreated(arg1)
    elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_ADDED"
        or event == "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED"
        or event == "CRAFTINGORDERS_UPDATE_CUSTOMER_NAME" then
        self:SnapshotClaimedWorkOrder()
    elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED" then
        self.claimedWorkOrderSnapshot = nil
    elseif event == "TRADE_SHOW" then
        self:OnTradeShow()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        self:OnTradeAcceptUpdate(arg1, arg2)
    elseif event == "TRADE_CLOSED" then
        self:OnTradeClose()
    end
end

ns.ModuleRegistry:Register(module)
