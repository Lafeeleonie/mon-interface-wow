local addonName, ns = ...

ns.DeveloperMode = ns.DeveloperMode or {}
local DeveloperMode = ns.DeveloperMode

-- Refresh cadences.
--   REFRESH_INTERVAL       : light-weight fields (FPS, combat, zone, modules)
--   HEAVY_REFRESH_INTERVAL : UpdateAddOnMemoryUsage walks every loaded addon
--                            and GetNetStats polls the socket, so those are
--                            refreshed on a much slower tick.
-- IMPORTANT: When the overlay is hidden SetEnabled(false) detaches the frame's
-- OnUpdate script entirely (see bottom of this file), so none of these costs
-- are paid when dev mode is off. The only live code path is the one-shot
-- Settings lookup in Initialize() during login.
local REFRESH_INTERVAL = 0.2
local HEAVY_REFRESH_INTERVAL = 2.0
local MAX_MODULE_LINES = 12
local HEADER_LINE_COUNT = 5

local math_floor = math.floor

local function BoolText(value)
    return value and "Y" or "N"
end

local function BuildStatusText(status)
    if status.enabled then
        return "ACTIVE"
    end

    if not status.configured then
        return "DISABLED"
    end

    if not status.available then
        return ("BLOCKED (%s)"):format(tostring(status.reason))
    end

    if not ns.Settings:IsGlobalEnabled() then
        return "GLOBAL OFF"
    end

    return "INACTIVE"
end

local function BuildRuntimeText(status)
    if not ns.ModuleRegistry or not ns.ModuleRegistry.GetModule then
        return nil
    end

    local module = ns.ModuleRegistry:GetModule(status.id)
    if not module or type(module.GetDebugState) ~= "function" then
        return nil
    end

    local ok, state = pcall(module.GetDebugState, module)
    if not ok or type(state) ~= "table" then
        return nil
    end

    -- Modules may define FormatDebugState() themselves for a tailored line.
    if type(module.FormatDebugState) == "function" then
        local fok, text = pcall(module.FormatDebugState, module, state)
        if fok and type(text) == "string" then
            return text
        end
    end

    -- Generic fallback: flatten scalar fields into "key=value" pairs.
    local parts = {}
    for key, value in pairs(state) do
        if type(value) ~= "table" then
            parts[#parts + 1] = (("%s=%s"):format(tostring(key), tostring(value)))
        end
        if #parts >= 6 then
            break
        end
    end

    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Cached heavy-field values. Refreshed on HEAVY_REFRESH_INTERVAL only while
-- the overlay is visible. Also populated once immediately when the overlay
-- is enabled (see SetEnabled) so the first frame doesn't show zeroes.
local heavyCache = {
    memoryKB = 0,
    latencyHome = 0,
    latencyWorld = 0,
    bandwidthIn = 0,
    bandwidthOut = 0,
    addonVersion = nil,
}

local function RefreshHeavyCache()
    if type(UpdateAddOnMemoryUsage) == "function" then
        UpdateAddOnMemoryUsage()
    end

    if type(GetAddOnMemoryUsage) == "function" and ns.addonName then
        local ok, kb = pcall(GetAddOnMemoryUsage, ns.addonName)
        if ok and type(kb) == "number" then
            heavyCache.memoryKB = kb
        end
    end

    if type(GetNetStats) == "function" then
        local bIn, bOut, lHome, lWorld = GetNetStats()
        heavyCache.bandwidthIn = bIn or 0
        heavyCache.bandwidthOut = bOut or 0
        heavyCache.latencyHome = lHome or 0
        heavyCache.latencyWorld = lWorld or 0
    end

    -- Version is immutable for the session; look it up once and cache.
    if not heavyCache.addonVersion then
        heavyCache.addonVersion = (ns.Compat and ns.Compat.GetAddOnVersion
            and ns.Compat.GetAddOnVersion(ns.addonName)) or "?"
    end
end

local function BuildGroupText()
    if type(GetNumGroupMembers) ~= "function" then
        return "Solo"
    end
    local n = GetNumGroupMembers() or 0
    if IsInRaid() then
        return ("Raid (%d)"):format(n)
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return ("Instance (%d)"):format(n)
    end
    if IsInGroup() then
        return ("Party (%d)"):format(n)
    end
    return "Solo"
end

-- Populates the fixed header lines from cheap per-tick reads + the cached
-- heavy values. Called at REFRESH_INTERVAL.
local function BuildHeaderLines(lines, activeCount, statusCount)
    local version = heavyCache.addonVersion or "?"
    local fps = (type(GetFramerate) == "function") and math_floor(GetFramerate() + 0.5) or 0
    local eventCount = (ns.EventBus and ns.EventBus.GetRegisteredEventCount
        and ns.EventBus:GetRegisteredEventCount()) or 0

    lines[1]:SetText(("ThyraxUtil v%s | Global: %s | Modules: %d/%d | FPS: %d | Events: %d"):format(
        version,
        ns.Settings:IsGlobalEnabled() and "ON" or "OFF",
        activeCount,
        statusCount,
        fps,
        eventCount
    ))

    local pName = (type(UnitName) == "function" and UnitName("player")) or "?"
    local pRealm = (type(GetRealmName) == "function" and GetRealmName()) or ""
    local pLvl = (type(UnitLevel) == "function" and UnitLevel("player")) or 0
    local classToken = tostring(ns.context and ns.context.classToken or "?")
    local specID = tostring(ns.context and ns.context.specID or "?")
    lines[2]:SetText(("Player: %s-%s | Lv%d %s | Spec: %s"):format(
        pName, pRealm, pLvl, classToken, specID
    ))

    local realZone = (type(GetRealZoneText) == "function" and GetRealZoneText()) or "?"
    local subZone = (type(GetSubZoneText) == "function" and GetSubZoneText()) or ""
    local iName, iType = "none", "none"
    if type(GetInstanceInfo) == "function" then
        local n, t = GetInstanceInfo()
        iName = n or "none"
        iType = t or "none"
    end
    local zoneText
    if subZone ~= "" and subZone ~= realZone then
        zoneText = ("Zone: %s / %s"):format(realZone, subZone)
    else
        zoneText = ("Zone: %s"):format(realZone)
    end
    lines[3]:SetText(("%s | Instance: %s (%s)"):format(
        zoneText, iName, iType
    ))

    local inCombat = (type(InCombatLockdown) == "function") and InCombatLockdown() or false
    lines[4]:SetText(("Combat: %s | Group: %s | Latency: H %dms W %dms | BW: in %d / out %d kBps"):format(
        BoolText(inCombat),
        BuildGroupText(),
        heavyCache.latencyHome,
        heavyCache.latencyWorld,
        heavyCache.bandwidthIn,
        heavyCache.bandwidthOut
    ))

    local uiScale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
    local devEnabled = ns.Settings:IsDeveloperModeEnabled()
    local theme = (ns.Settings and ns.Settings.GetTheme and ns.Settings:GetTheme()) or "?"
    lines[5]:SetText(("Memory: %.1f KB | UI Scale: %.2f | Theme: %s | Dev Mode: %s"):format(
        heavyCache.memoryKB,
        uiScale,
        tostring(theme),
        BoolText(devEnabled)
    ))
end

function DeveloperMode:EnsureFrame()
    if self.frame then
        return
    end

    -- Total line slots: header + "Modules:" label + module rows.
    local totalLines = HEADER_LINE_COUNT + 1 + MAX_MODULE_LINES
    local lineTopOffset = 28
    local lineHeight = 16
    local frameHeight = lineTopOffset + (totalLines * lineHeight) + 12

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetSize(900, frameHeight)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -140)
    frame:Hide()

    if ns.UI and ns.UI.ApplyTheme then
        ns.UI:ApplyTheme(frame)
    else
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(0, 0, 0, 0.7)
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    title:SetText(("ThyraxUtil Developer Mode (%s)"):format(addonName))

    local lines = {}
    for index = 1, totalLines do
        local line = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(lineTopOffset + ((index - 1) * lineHeight)))
        line:SetJustifyH("LEFT")
        line:SetWidth(870)
        line:SetWordWrap(false)
        line:SetText("")
        lines[index] = line
    end

    self.frame = frame
    self.lines = lines
    self.elapsed = 0
    self.heavyElapsed = HEAVY_REFRESH_INTERVAL
end

function DeveloperMode:Refresh()
    if not self.frame or not self.lines then
        return
    end

    -- Heavy scans (memory, net stats) only every HEAVY_REFRESH_INTERVAL.
    if (self.heavyElapsed or 0) >= HEAVY_REFRESH_INTERVAL then
        RefreshHeavyCache()
        self.heavyElapsed = 0
    end

    local statuses = ns.ModuleRegistry:GetAllStatuses()
    local activeCount = 0
    for _, status in ipairs(statuses) do
        if status.enabled then
            activeCount = activeCount + 1
        end
    end

    BuildHeaderLines(self.lines, activeCount, #statuses)

    -- "Modules:" separator line.
    local modulesLineIndex = HEADER_LINE_COUNT + 1
    self.lines[modulesLineIndex]:SetText("Modules:")

    for index = 1, MAX_MODULE_LINES do
        local lineIndex = index + HEADER_LINE_COUNT + 1
        local status = statuses[index]
        if status then
            local runtimeText = BuildRuntimeText(status)
            local suffix = runtimeText and (" | " .. runtimeText) or ""
            self.lines[lineIndex]:SetText(("- %s (%s): %s%s"):format(
                status.name,
                status.id,
                BuildStatusText(status),
                suffix
            ))
        else
            self.lines[lineIndex]:SetText("")
        end
    end
end

function DeveloperMode:SetEnabled(enabled)
    self:EnsureFrame()

    if enabled then
        self.frame:Show()
        self.elapsed = 0
        -- Force a heavy refresh on the very first Refresh so the overlay
        -- shows real numbers immediately instead of zeroes.
        self.heavyElapsed = HEAVY_REFRESH_INTERVAL
        self:Refresh()
        self.frame:SetScript("OnUpdate", function(_, elapsed)
            DeveloperMode.elapsed = (DeveloperMode.elapsed or 0) + elapsed
            DeveloperMode.heavyElapsed = (DeveloperMode.heavyElapsed or 0) + elapsed
            if DeveloperMode.elapsed < REFRESH_INTERVAL then
                return
            end
            DeveloperMode.elapsed = 0
            DeveloperMode:Refresh()
        end)
        return
    end

    -- CRITICAL: detach the OnUpdate script fully so NO work runs while the
    -- overlay is hidden. This is the guarantee that dev mode is free when off.
    self.frame:SetScript("OnUpdate", nil)
    self.frame:Hide()
end

function DeveloperMode:Initialize()
    local enabled = ns.Settings:IsDeveloperModeEnabled()
    self:SetEnabled(enabled)
end
