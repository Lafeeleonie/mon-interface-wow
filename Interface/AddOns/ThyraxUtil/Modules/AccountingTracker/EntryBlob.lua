local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.accounting
if not module then return end

-- ============================================================================
-- Entry blob (de)serialization
-- ============================================================================
-- Large ledgers are stored at idle as a compact serialized STRING per shard
-- instead of thousands of live Lua tables. WoW loads SavedVariables at login;
-- a single string costs a fraction of the memory of the equivalent
-- array-of-tables (no per-table overhead), so other characters' history does
-- not bloat RAM during normal play. The string is only expanded back into live
-- entry tables while the ledger window is open (see MaterializeShard, added in
-- a later step). This file only provides the lossless (de)serialization and is
-- self-contained / side-effect free so it can be unit-tested in isolation
-- before any live storage is switched over.
--
-- Format v1 (legacy, still readable) stores every key/value as length-prefixed
-- tokens. Format v2 keeps the same fail-safe framing but writes compact key
-- codes and a per-blob string dictionary for repeated values. This cuts the
-- resident SavedVariables string size substantially for large ledgers while
-- keeping old TBLOB1 blobs readable.
--
-- All raw string values are length-prefixed, so any byte -- including item-link "|"
-- codes, brackets and newlines -- round-trips losslessly with no escaping):
--   blob v1 := "TBLOB1" ";" entryCount ";" entry*
--   blob v2 := "TBLOB2" ";" entryCount ";" dictCount ";" rawStringToken* entry*
--   entry   := pairCount ";" pair*
--   pair    := token(key) token(value)
--   token   := typeTag len ":" bytes | "k" keyCode | "r" dictIndex ";"
--   typeTag : "s"=string, "n"=number, "b"=boolean
-- Entries produced by Record are flat tables of scalar values; nested tables
-- are never stored, so the format does not support them (serialize skips a
-- nested value defensively rather than emitting something unparseable).

local MAGIC_V1 = "TBLOB1"
local MAGIC_V2 = "TBLOB2"
local MAGIC = MAGIC_V2
local MAX_STRING_REFS = 512

local tconcat = table.concat
local mfloor = math.floor
local ssub = string.sub
local sfind = string.find
local sformat = string.format
local slen = string.len

local KEY_NAME_TO_CODE = {
    t = "a",
    kind = "b",
    amount = "c",
    who = "d",
    itemName = "e",
    itemID = "f",
    qty = "g",
    item = "h",
    itemFiltered = "i",
    itemLink = "j",
    itemClassID = "k",
    itemClassName = "l",
    itemSubClassID = "m",
    itemSubClassName = "n",
    workOrderType = "o",
    questName = "p",
    questID = "q",
    subject = "r",
    consortiumCut = "s",
    refunded = "u",
}

local KEY_CODE_TO_NAME = {}
for name, code in pairs(KEY_NAME_TO_CODE) do
    KEY_CODE_TO_NAME[code] = name
end

local function digits(n)
    return slen(tostring(n or 0))
end

local function encodeRawString(s)
    return "s" .. #s .. ":" .. s
end

local function encodeNumber(v)
    -- "%.0f" for integer-valued numbers avoids the 32-bit cast that "%d"
    -- performs (copper amounts and epochs can exceed 2^31). Doubles are exact
    -- for integers up to 2^53, which bounds every numeric field we store.
    -- Non-integers fall back to "%.17g" for a lossless round-trip.
    local s
    if v == mfloor(v) and v < 9e15 and v > -9e15 then
        s = sformat("%.0f", v)
    else
        s = sformat("%.17g", v)
    end
    return "n" .. #s .. ":" .. s
end

local function buildStringRefs(entries)
    if type(entries) ~= "table" then return nil, nil end
    local counts = {}
    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" then
            for _, v in pairs(e) do
                if type(v) == "string" and v ~= "" then
                    counts[v] = (counts[v] or 0) + 1
                end
            end
        end
    end
    local candidates = {}
    for value, count in pairs(counts) do
        if count >= 3 and #value > 2 then
            local rawLen = 2 + digits(#value) + #value
            local refLen = 2 + digits(#candidates + 1)
            local savings = (rawLen - refLen) * count - rawLen
            if savings > 0 then
                candidates[#candidates + 1] = {
                    value = value,
                    count = count,
                    savings = savings,
                }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.savings ~= b.savings then return a.savings > b.savings end
        return a.value < b.value
    end)
    local refs, values = {}, {}
    local limit = math.min(MAX_STRING_REFS, #candidates)
    for i = 1, limit do
        local value = candidates[i].value
        refs[value] = i
        values[i] = value
    end
    return refs, values
end

-- Encode a single scalar value into a "<tag><len>:<bytes>" token. Returns nil
-- for unsupported types (only nested tables are expected to hit this).
local function encodeValue(v, stringRefs)
    local t = type(v)
    if t == "string" then
        local ref = stringRefs and stringRefs[v]
        if ref then return "r" .. tostring(ref) .. ";" end
        return encodeRawString(v)
    elseif t == "number" then
        return encodeNumber(v)
    elseif t == "boolean" then
        return (v and "b1:1" or "b1:0")
    end
    return nil
end

local function encodeKey(k)
    if type(k) == "string" then
        local code = KEY_NAME_TO_CODE[k]
        if code then return "k" .. code end
        return encodeRawString(k)
    elseif type(k) == "number" then
        return encodeNumber(k)
    end
    return encodeRawString(tostring(k))
end

-- Serialize an array of flat entry tables into a single string. Returns the
-- string (never nil; an empty / non-table input yields a valid empty blob).
function module:SerializeEntries(entries)
    if type(entries) ~= "table" then
        return MAGIC .. ";0;0;"
    end
    local count = #entries
    local stringRefs, stringValues = buildStringRefs(entries)
    local dictCount = stringValues and #stringValues or 0
    local out = { MAGIC, ";", sformat("%d", count), ";", sformat("%d", dictCount), ";" }
    local n = 6
    for i = 1, dictCount do
        n = n + 1; out[n] = encodeRawString(stringValues[i])
    end
    for i = 1, count do
        local e = entries[i]
        if type(e) ~= "table" then
            -- Preserve slot alignment: emit an empty entry rather than abort.
            n = n + 1; out[n] = "0;"
        else
            local fieldBuf = {}
            local fb = 0
            for k, v in pairs(e) do
                local valTok = encodeValue(v, stringRefs)
                if valTok then
                    local keyTok = encodeKey(k)
                    fb = fb + 1; fieldBuf[fb] = keyTok
                    fb = fb + 1; fieldBuf[fb] = valTok
                end
            end
            n = n + 1; out[n] = sformat("%d", fb / 2)
            n = n + 1; out[n] = ";"
            for j = 1, fb do
                n = n + 1; out[n] = fieldBuf[j]
            end
        end
    end
    return tconcat(out)
end

local function readTypedToken(blob, pos, len, stringDict, allowKeyCodes, allowRefs)
    if pos > len then return nil, false, pos end
    local tag = ssub(blob, pos, pos)
    pos = pos + 1

    if tag == "k" and allowKeyCodes then
        if pos > len then return nil, false, pos end
        local code = ssub(blob, pos, pos)
        pos = pos + 1
        local key = KEY_CODE_TO_NAME[code]
        if not key then return nil, false, pos end
        return key, true, pos
    elseif tag == "r" and allowRefs then
        local semi = sfind(blob, ";", pos, true)
        if not semi then return nil, false, pos end
        local ref = tonumber(ssub(blob, pos, semi - 1))
        if not ref or not stringDict or stringDict[ref] == nil then
            return nil, false, semi + 1
        end
        return stringDict[ref], true, semi + 1
    end

    local colon = sfind(blob, ":", pos, true)
    if not colon then return nil, false, pos end
    local l = tonumber(ssub(blob, pos, colon - 1))
    if not l or l < 0 then return nil, false, pos end
    pos = colon + 1
    if pos + l - 1 > len then return nil, false, pos end
    local bytes = ssub(blob, pos, pos + l - 1)
    pos = pos + l
    if tag == "s" then
        return bytes, true, pos
    elseif tag == "n" then
        local num = tonumber(bytes)
        if num == nil then return nil, false, pos end
        return num, true, pos
    elseif tag == "b" then
        return (bytes == "1"), true, pos
    end
    return nil, false, pos
end

-- Deserialize a blob string back into an array of entry tables. Returns
-- (entries) on success or (nil, errorMessage) on any malformed input -- callers
-- MUST treat nil as "keep the blob, do not destroy data" (fail-safe).
function module:DeserializeEntries(blob)
    if type(blob) ~= "string" or blob == "" then
        return {}
    end
    local len = #blob
    local pos = 1

    local semi = sfind(blob, ";", pos, true)
    if not semi then return nil, "bad magic" end
    local magic = ssub(blob, pos, semi - 1)
    if magic ~= MAGIC_V1 and magic ~= MAGIC_V2 then
        return nil, "bad magic"
    end
    pos = semi + 1

    semi = sfind(blob, ";", pos, true)
    if not semi then return nil, "missing entry count" end
    local entryCount = tonumber(ssub(blob, pos, semi - 1))
    if not entryCount or entryCount < 0 then return nil, "bad entry count" end
    pos = semi + 1

    local stringDict
    if magic == MAGIC_V2 then
        semi = sfind(blob, ";", pos, true)
        if not semi then return nil, "missing string dictionary count" end
        local dictCount = tonumber(ssub(blob, pos, semi - 1))
        if not dictCount or dictCount < 0 then return nil, "bad string dictionary count" end
        pos = semi + 1
        stringDict = {}
        for i = 1, dictCount do
            local value, ok
            value, ok, pos = readTypedToken(blob, pos, len, nil, false, false)
            if not ok or type(value) ~= "string" then
                return nil, "bad string dictionary token " .. i
            end
            stringDict[i] = value
        end
    end

    local entries = {}
    for i = 1, entryCount do
        semi = sfind(blob, ";", pos, true)
        if not semi then return nil, "missing pair count at entry " .. i end
        local pc = tonumber(ssub(blob, pos, semi - 1))
        if not pc or pc < 0 then return nil, "bad pair count at entry " .. i end
        pos = semi + 1
        local e = {}
        for _ = 1, pc do
            local k, okk
            local v, okv
            k, okk, pos = readTypedToken(blob, pos, len, stringDict, magic == MAGIC_V2, false)
            v, okv, pos = readTypedToken(blob, pos, len, stringDict, false, magic == MAGIC_V2)
            if not (okk and okv) then
                return nil, "malformed token at entry " .. i
            end
            e[k] = v
        end
        entries[i] = e
    end
    return entries
end

-- Position-based token reader for the resumable chunked deserializer below.
-- Mirrors the closure in DeserializeEntries but takes/returns the cursor so it
-- can be paused between frames. Returns (value, ok, newPos).
local function readBlobToken(blob, pos, len, stringDict, allowKeyCodes, allowRefs)
    return readTypedToken(blob, pos, len, stringDict, allowKeyCodes, allowRefs)
end

-- Resumable deserialize for the async window build (Phase 1). Parses up to
-- `maxCount` entries from `blob`, appending into `out`, resuming from `cursor`.
-- Returns (out, cursor, done) on success, or (nil, cursor, false, err) on
-- malformed input. `cursor` is opaque ({ pos, parsed, total }); pass nil to
-- start. When `done` is true every entry has been parsed. This lets the window
-- materialize a huge history across several frames instead of one freeze.
function module:DeserializeEntriesChunk(blob, cursor, maxCount, out)
    out = out or {}
    if type(blob) ~= "string" or blob == "" then
        return out, { pos = 1, parsed = 0, total = 0 }, true
    end
    local len = #blob
    local pos
    if cursor then
        if cursor.parsed >= cursor.total then
            return out, cursor, true
        end
        pos = cursor.pos
    else
        pos = 1
        local semi = sfind(blob, ";", pos, true)
        if not semi then return nil, nil, false, "bad magic" end
        local magic = ssub(blob, pos, semi - 1)
        if magic ~= MAGIC_V1 and magic ~= MAGIC_V2 then
            return nil, nil, false, "bad magic"
        end
        pos = semi + 1
        semi = sfind(blob, ";", pos, true)
        if not semi then return nil, nil, false, "missing entry count" end
        local total = tonumber(ssub(blob, pos, semi - 1))
        if not total or total < 0 then return nil, nil, false, "bad entry count" end
        pos = semi + 1
        local stringDict
        if magic == MAGIC_V2 then
            semi = sfind(blob, ";", pos, true)
            if not semi then return nil, nil, false, "missing string dictionary count" end
            local dictCount = tonumber(ssub(blob, pos, semi - 1))
            if not dictCount or dictCount < 0 then return nil, nil, false, "bad string dictionary count" end
            pos = semi + 1
            stringDict = {}
            for i = 1, dictCount do
                local value, ok
                value, ok, pos = readBlobToken(blob, pos, len, nil, false, false)
                if not ok or type(value) ~= "string" then
                    return nil, nil, false, "bad string dictionary token " .. i
                end
                stringDict[i] = value
            end
        end
        cursor = { pos = pos, parsed = 0, total = total, magic = magic, stringDict = stringDict }
    end

    local total = cursor.total
    local parsed = cursor.parsed
    local magic = cursor.magic or MAGIC_V1
    local stringDict = cursor.stringDict
    local budget = tonumber(maxCount) or 5000
    if budget < 1 then budget = 1 end
    local processed = 0
    while parsed < total and processed < budget do
        local semi = sfind(blob, ";", pos, true)
        if not semi then return nil, cursor, false, "missing pair count at entry " .. (parsed + 1) end
        local pc = tonumber(ssub(blob, pos, semi - 1))
        if not pc or pc < 0 then return nil, cursor, false, "bad pair count at entry " .. (parsed + 1) end
        pos = semi + 1
        local e = {}
        for _ = 1, pc do
            local k, okk
            local v, okv
            k, okk, pos = readBlobToken(blob, pos, len, stringDict, magic == MAGIC_V2, false)
            v, okv, pos = readBlobToken(blob, pos, len, stringDict, false, magic == MAGIC_V2)
            if not (okk and okv) then
                return nil, cursor, false, "malformed token at entry " .. (parsed + 1)
            end
            e[k] = v
        end
        out[#out + 1] = e
        parsed = parsed + 1
        processed = processed + 1
    end

    cursor.pos = pos
    cursor.parsed = parsed
    return out, cursor, (parsed >= total)
end

-- ============================================================================
-- Materialize / dematerialize lifecycle
-- ============================================================================
-- A shard is either LIVE (shard.entries present -- an array of entry tables) or
-- AT REST (shard.blob present, shard.entries nil). The CURRENT character's
-- shard is kept live the whole session (recording + item enrichment need it);
-- OTHER characters are materialized only while the window shows them and
-- dropped again afterwards, so their history is not held in RAM during normal
-- play. That is where the big idle cost came from on multi-character accounts.

-- Make shard.entries available, deserializing the blob on first access. Cheap
-- no-op if already live. NEVER destroys the blob on a parse error (fail-safe):
-- it surfaces an empty working set and flags the shard so DematerializeShard
-- will not overwrite the unreadable blob with [].
function module:MaterializeShard(shard)
    if type(shard) ~= "table" then return nil end
    if type(shard.entries) == "table" then return shard.entries end
    local list, err = self:DeserializeEntries(shard.blob)
    if not list then
        if ns.Diagnostics and ns.Diagnostics.Warn then
            ns.Diagnostics:Warn(("Accounting: stored history unreadable (%s); leaving it intact."):format(tostring(err)))
        end
        shard._blobError = true
        shard.entries = {}
        return shard.entries
    end
    shard._blobError = nil
    shard.entries = list
    -- Re-arm the item sweep if any freshly materialized entry still needs its
    -- item link resolved (blobbed shards are not swept while at rest).
    for i = 1, #list do
        local e = list[i]
        if e.itemName and not e.itemID then
            self._needsLedgerSweep = true
            break
        end
    end
    return list
end

-- Serialize shard.entries back into shard.blob and drop the live table. No-op
-- if already at rest. Refuses to overwrite a blob it failed to read, and keeps
-- the live entries if the freshly written blob fails a header sanity check
-- (so a serializer regression can never silently drop the user's ledger).
-- Field-for-field equality of two flat entry arrays. Used for the one-time
-- migration verification so existing ledger data is only ever dropped in favour
-- of a blob that reproduces it EXACTLY (every entry, every key, both ways).
local function entriesDeepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        local ea, eb = a[i], b[i]
        if type(ea) ~= "table" or type(eb) ~= "table" then return false end
        for k, v in pairs(ea) do
            if eb[k] ~= v then return false end
        end
        for k, v in pairs(eb) do
            if ea[k] ~= v then return false end
        end
    end
    return true
end

function module:DematerializeShard(shard)
    if type(shard) ~= "table" or type(shard.entries) ~= "table" then return end
    if shard._blobError then
        -- Never read the original blob; keep it, just drop the empty working set.
        shard.entries = nil
        return
    end
    -- Capture lifetime totals from the live entries before they go away.
    self:GetShardLifetime(shard)
    -- FAST PATH: a valid, verified blob already exists AND still matches the
    -- live entries. That holds for shards materialized read-only for viewing
    -- (item enrichment done while viewing is re-derivable, so discarding it
    -- with the live table is safe) -- but NOT for a shard that recorded new
    -- entries while it was the current character: MaterializeShard leaves the
    -- old blob in place and Record() grows entries past it. Blindly dropping
    -- the live table here rolled such shards back to the blob snapshot,
    -- silently deleting every entry recorded since the blob was written (the
    -- "ledger frozen since release day" bug). Record() now invalidates
    -- shard.blob directly; the header-count comparison below is the
    -- self-healing second line of defense that catches any mutation site
    -- that forgets to. On any mismatch (or unparseable header) we fall
    -- through and re-serialize from the live entries.
    if shard.blob and not shard._needsBlobVerify then
        local headerCount = tonumber(type(shard.blob) == "string"
            and shard.blob:match("^TBLOB[12];(%d+);") or nil)
        if headerCount ~= nil and headerCount == #shard.entries then
            shard.entries = nil
            return
        end
    end
    local entries = shard.entries
    -- NB: no pruning here. Record already bounds the live current character to
    -- maxEntries on insert, and characters at rest never grow. Trimming during
    -- dematerialize would silently delete history on migration (e.g. if the user
    -- lowered maxEntries), which must never happen -- so we serialize exactly
    -- what is there.
    local nEntries = #entries
    local blob = self:SerializeEntries(entries)
    if shard._needsBlobVerify then
        -- One-time FULL round-trip verification when first converting EXISTING
        -- ledger data to a blob (set by MigrateShard). Deserializes the blob and
        -- compares it field-for-field against the live entries: the data is only
        -- dropped if the blob reproduces it exactly. On ANY mismatch the live
        -- entries are kept untouched (the shard simply stays unconverted and
        -- retries later) so a migration can never lose or corrupt real history.
        -- Slower, but runs once per shard; afterwards the cheap header check is
        -- used.
        local check = self:DeserializeEntries(blob)
        if not entriesDeepEqual(entries, check) then
            if ns.Diagnostics and ns.Diagnostics.Warn then
                ns.Diagnostics:Warn("Accounting: history failed full round-trip on migration; keeping live data (will retry).")
            end
            return
        end
        shard._needsBlobVerify = nil
    else
        -- Cheap integrity gate: the blob header must declare the same entry
        -- count we serialized. Full content fidelity is covered by the EntryBlob
        -- round-trip unit tests; a full re-parse on every window close would be
        -- too slow for large ledgers. On mismatch, keep the live entries.
        local headerCount = type(blob) == "string" and blob:match("^" .. MAGIC .. ";(%d+);")
        if not headerCount or tonumber(headerCount) ~= nEntries then
            if ns.Diagnostics and ns.Diagnostics.Warn then
                ns.Diagnostics:Warn("Accounting: history blob failed its sanity check; keeping live data.")
            end
            return
        end
    end
    shard.count = nEntries
    shard.blob = blob
    shard.entries = nil
end

-- Entry count that works whether the shard is live or at rest.
function module:GetShardEntryCount(shard)
    if type(shard) ~= "table" then return 0 end
    if type(shard.entries) == "table" then return #shard.entries end
    return tonumber(shard.count) or 0
end

-- Dematerialize every shard EXCEPT keepKey (defaults to the current character)
-- so other characters' history is compacted to blobs and freed from RAM. Runs
-- the full per-shard migration first so lifetime totals are captured.
function module:CompactInactiveShards(keepKey)
    if not (self.settings and type(self.settings.shards) == "table") then return end
    if keepKey == nil then
        local _, key = self:GetShard()
        keepKey = key
    end
    for key, shard in pairs(self.settings.shards) do
        if key ~= keepKey and type(shard) == "table" and type(shard.entries) == "table" then
            if module._migrateShard then module._migrateShard(shard) end
            self:DematerializeShard(shard)
        end
    end
    -- No forced collectgarbage here: a full collect is a stop-the-world pause
    -- and this runs on the window-close path. Dropped entry tables are reclaimed
    -- by Lua's incremental GC within a few seconds. Callers that specifically
    -- want immediate reclamation (the /accstress tools) collect themselves.
end

-- Frame-spread variant: compact one inactive shard per timer tick instead of
-- all at once. Used for the post-login migration pass, where the FIRST run on a
-- pre-update account serializes + full-verifies every other character's history
-- (heavy, one-time). Spreading it keeps that one-time cost from stacking into a
-- single multi-second freeze. After the first run the shards are blobs (no live
-- entries), so subsequent runs find nothing to do and return immediately.
function module:CompactInactiveShardsSpread(keepKey)
    if not (self.settings and type(self.settings.shards) == "table") then return end
    if keepKey == nil then
        local _, key = self:GetShard()
        keepKey = key
    end
    local todo = {}
    for key, shard in pairs(self.settings.shards) do
        if key ~= keepKey and type(shard) == "table" and type(shard.entries) == "table" then
            todo[#todo + 1] = key
        end
    end
    if #todo == 0 then return end
    if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.After) ~= "function" then
        -- No timer API: fall back to the synchronous pass.
        self:CompactInactiveShards(keepKey)
        return
    end
    local i = 0
    local function processNext()
        i = i + 1
        local key = todo[i]
        if not key then return end
        local shard = self.settings and self.settings.shards and self.settings.shards[key]
        if type(shard) == "table" and type(shard.entries) == "table" then
            if module._migrateShard then module._migrateShard(shard) end
            self:DematerializeShard(shard)
        end
        if i < #todo then
            _G.C_Timer.After(0.05, processNext)
        end
    end
    processNext()
end
