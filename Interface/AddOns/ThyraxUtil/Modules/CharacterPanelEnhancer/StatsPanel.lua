local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.characterPanel
if not module then return end

-- ============================================================================
-- Character stats panel (overlay docked to Blizzard's CharacterStatsPane)
-- ============================================================================
-- Split out of CharacterPanelEnhancer.lua. Shared helpers are pulled from the
-- module table / Core (set up by the main file before this subfile loads).

local CONSTANTS = module.CONSTANTS
local CopyColor = ns.Color.RGBA
local SetScaledFont = module.SetScaledFont
local ResolveAccentPalette = module.ResolveAccentPalette

-- Coercing clamp: settings values may be nil / non-numeric, so coerce to the
-- minimum before clamping via the shared Core helper.
local function Clamp(value, minValue, maxValue)
    return ns.Color.Clamp(tonumber(value) or minValue, minValue, maxValue)
end

local STAT_CATEGORIES = {
    { title = "Item Level",   keys = { "itemLevel" } },
    { title = "Gear",         keys = { "enchantReady", "socketReady" } },
    { title = "Attributes",   keys = { "primary", "stamina", "health", "armor" } },
    { title = "Enhancements", keys = { "crit", "haste", "mastery", "versatility" } },
    { title = "Survival",     keys = { "leech", "avoidance", "speed", "dodge", "parry", "block" } },
}

local STAT_SETTINGS = {
    itemLevel = "showStatItemLevel",
    enchantReady = "showStatEnchantReady",
    socketReady = "showStatSocketReady",
    health = "showStatHealth",
    armor = "showStatArmor",
    primary = "showStatPrimary",
    stamina = "showStatStamina",
    crit = "showStatCrit",
    haste = "showStatHaste",
    mastery = "showStatMastery",
    versatility = "showStatVersatility",
    leech = "showStatLeech",
    avoidance = "showStatAvoidance",
    speed = "showStatSpeed",
    dodge = "showStatTank",
    parry = "showStatTank",
    block = "showStatTank",
}

function module:GetVisibleStatCategories(stats)
    local result = {}
    stats = stats or {}
    local settings = self.settings or self.defaults
    for _, category in ipairs(STAT_CATEGORIES) do
        local keys = {}
        for _, statKey in ipairs(category.keys) do
            local settingKey = STAT_SETTINGS[statKey]
            if stats[statKey] and (not settingKey or settings[settingKey] == true) then
                keys[#keys + 1] = statKey
            end
        end
        if #keys > 0 then
            result[#result + 1] = { title = category.title, keys = keys }
        end
    end
    return result
end

function module:EnsureStatsPanel()
    if self.statsPanel then
        return self.statsPanel
    end
    -- The stats display overlays Blizzard's native CharacterStatsPane so it is
    -- integrated into the character sheet and follows the paperdoll tab's
    -- show/hide automatically. Showing the overlay covers Blizzard's stats;
    -- hiding it (collapse) reveals them again.
    local host = _G.CharacterStatsPane
    if not host then
        return nil
    end

    -- Parent the overlay to the stats pane's PARENT (a sibling of the pane),
    -- so CharacterStatsPane itself can be hidden without hiding our overlay.
    local statsParent = host:GetParent() or host
    local panel = CreateFrame("Frame", "ThyraxCharacterStatsPanel", statsParent)
    panel:SetAllPoints(host)
    panel:SetFrameLevel((host:GetFrameLevel() or 1) + 10)
    -- Capture mouse events so they do not pass through to Blizzard's stat
    -- rows under us -- otherwise hovering our rows would also trigger
    -- Blizzard's original tooltips for the (now hidden behind us) stats.
    panel:EnableMouse(true)

    -- All sidebar-related hooks defer their refresh by one frame via
    -- ScheduleStatsRefresh. Blizzard's tab switch does (hide active pane,
    -- show next pane) sequentially in one frame, and running our refresh
    -- between those two calls used to evaluate the sidebar state on a
    -- half-finished tab switch -- which caused us to re-show host
    -- (CharacterStatsPane) right before Blizzard showed Titles or Equipment
    -- Manager, leaving two panes stacked. Deferring waits for the dust to
    -- settle. The suppress flag still prevents the recursion that comes
    -- from our own host:Hide() inside RefreshStats.
    host:HookScript("OnShow", function()
        if module.isActive and not module._suppressStatsHook then
            module:ScheduleStatsRefresh()
        end
    end)
    host:HookScript("OnHide", function()
        if module.isActive and not module._suppressStatsHook then
            module:ScheduleStatsRefresh()
        end
    end)

    -- Direct hooks on the sidebar TAB BUTTONS (most reliable interaction
    -- signal -- fires regardless of which pane Blizzard chooses to manage).
    for i = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab and tab.HookScript then
            tab:HookScript("OnClick", function()
                if module.isActive then module:ScheduleStatsRefresh() end
            end)
        end
    end

    -- Best-effort hooks on the sibling sidebar panes as a third signal in
    -- case the tab buttons or host:OnHide miss something.
    for _, paneName in ipairs({ "PaperDollTitlesPane", "PaperDollEquipmentManagerPane" }) do
        local sidebarPane = _G[paneName]
        if sidebarPane and sidebarPane.HookScript then
            sidebarPane:HookScript("OnShow", function()
                if module.isActive then module:ScheduleStatsRefresh() end
            end)
            sidebarPane:HookScript("OnHide", function()
                if module.isActive then module:ScheduleStatsRefresh() end
            end)
        end
    end

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
    panel.bg = bg

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(frame, delta)
        local statsPanel = module.statsPanel
        local range = (statsPanel and statsPanel.scrollRange) or 0
        local newScroll = (frame:GetVerticalScroll() or 0) - delta * 28
        if newScroll < 0 then newScroll = 0 end
        if newScroll > range then newScroll = range end
        frame:SetVerticalScroll(newScroll)
        module:UpdateScrollThumb()
    end)
    panel.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    panel.content = content

    local track = panel:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -6)
    track:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 6)
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.06)
    panel.scrollTrack = track

    local thumb = panel:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(CopyColor(CONSTANTS.COLOR_HEADER))
    thumb:Hide()
    panel.scrollThumb = thumb

    panel.rows = {}
    panel.headers = {}
    self.statsPanel = panel
    return panel
end

function module:AcquireStatHeader(panel, index)
    local header = panel.headers[index]
    if header then
        return header
    end
    header = {}
    header.text = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetJustifyH("LEFT")
    header.line = panel.content:CreateTexture(nil, "ARTWORK")
    header.line:SetColorTexture(1, 1, 1, 0.10)
    header.line:SetHeight(1)
    panel.headers[index] = header
    return header
end

function module:AcquireStatRow(panel, index)
    local row = panel.rows[index]
    if row then
        return row
    end
    row = {}
    row.label = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.value = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetJustifyH("RIGHT")
    row.detail = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.detail:SetJustifyH("RIGHT")
    panel.rows[index] = row
    return row
end

function module:ToggleStatsPanelCollapsed()
    if not self.settings then return end
    local newValue = not (self.settings.statsPanelCollapsed == true)
    self.settings.statsPanelCollapsed = newValue
    if ns.Settings and ns.Settings.SetModuleValue then
        ns.Settings:SetModuleValue(self.id, "statsPanelCollapsed", newValue)
    end
    self:RefreshStats()
    self:RefreshCharacterButtons()
end

function module:UpdateScrollThumb()
    local panel = self.statsPanel
    if not panel or not panel.scrollThumb then
        return
    end
    local range = panel.scrollRange or 0
    local track = panel.scrollTrack
    local thumb = panel.scrollThumb
    local trackHeight = track:GetHeight() or 0
    if range <= 0 or trackHeight <= 0 then
        thumb:Hide()
        return
    end
    local visible = panel.scroll:GetHeight() or 1
    local total = visible + range
    local thumbHeight = math.max(20, trackHeight * (visible / total))
    local available = trackHeight - thumbHeight
    local fraction = (panel.scroll:GetVerticalScroll() or 0) / range
    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end
    thumb:ClearAllPoints()
    thumb:SetHeight(thumbHeight)
    thumb:SetPoint("TOP", track, "TOP", 0, -(available * fraction))
    thumb:Show()
end

function module:RefreshStats()
    local panel = self:EnsureStatsPanel()
    if not panel then
        return
    end
    -- Blizzard owns CharacterStatsPane's visibility. We treat host:IsShown()
    -- as the truth for "Stats sidebar is currently active" and never call
    -- Hide / Show on it -- doing so used to leave Blizzard's sidebar tracker
    -- in an inconsistent state, which produced both "tabs stack on top of
    -- each other" and "overlay never hides" bugs. Our overlay simply draws
    -- on top of host with a fully opaque background.
    local host = _G.CharacterStatsPane
    local statsSidebarActive = host and host:IsShown()

    -- Mirror sidebar state to the header buttons (collapse should only show
    -- when the Stats sidebar is active).
    self:RefreshCharacterButtons()

    if not self.isActive
        or self.settings.showStatsPanel ~= true
        or self.settings.statsPanelCollapsed == true
        or not statsSidebarActive
        or not CharacterFrame
        or not CharacterFrame:IsShown() then
        panel:Hide()
        return
    end

    -- Hard-coded fully opaque so Blizzard's stat rows underneath never bleed
    -- through. The user-facing opacity slider has been removed -- any value
    -- below 1.0 produces ghost text and a worse-not-better look.
    panel.bg:SetColorTexture(0.05, 0.05, 0.06, 1.0)

    -- Re-tint accent-driven elements (scroll thumb) so theme switches at
    -- runtime propagate into the stats panel without a /reload.
    local statsPalette = ResolveAccentPalette()
    if panel.scrollThumb and panel.scrollThumb.SetColorTexture then
        panel.scrollThumb:SetColorTexture(
            statsPalette.header[1], statsPalette.header[2], statsPalette.header[3], statsPalette.header[4] or 1)
    end

    local fontSize = Clamp(self.settings.fontSize, CONSTANTS.FONT_MIN, CONSTANTS.FONT_MAX)
    local rowHeight = fontSize + 9
    local headerHeight = fontSize + 16

    local content = panel.content
    content:SetWidth(math.max(10, (panel.scroll:GetWidth() or 150)))
    -- Table columns: label (left, capped) | value (right-aligned) | detail (right).
    local labelMaxW = math.max(40, content:GetWidth() - 124)

    local stats = self:GetStats()
    local categories = self:GetVisibleStatCategories(stats)

    local y = -4
    local rowIndex = 0
    local headerIndex = 0

    for _, category in ipairs(categories) do
        headerIndex = headerIndex + 1
        local header = self:AcquireStatHeader(panel, headerIndex)
        header.text:ClearAllPoints()
        header.text:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
        header.text:SetText(category.title)
        header.text:SetTextColor(statsPalette.header[1], statsPalette.header[2], statsPalette.header[3], statsPalette.header[4] or 1)
        SetScaledFont(header.text, fontSize, "")
        header.text:Show()
        header.line:ClearAllPoints()
        header.line:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - fontSize - 4)
        header.line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y - fontSize - 4)
        header.line:Show()
        y = y - headerHeight

        for _, statKey in ipairs(category.keys) do
            local stat = stats[statKey]
            if stat then
                rowIndex = rowIndex + 1
                local row = self:AcquireStatRow(panel, rowIndex)

                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                row.label:SetWidth(labelMaxW)
                row.label:SetText(stat.label or statKey)
                row.label:SetTextColor(CopyColor(CONSTANTS.COLOR_MUTED))
                SetScaledFont(row.label, fontSize, "")
                row.label:Show()

                row.value:ClearAllPoints()
                row.value:SetPoint("TOPRIGHT", content, "TOPRIGHT", -54, y)
                row.value:SetText(stat.value or "-")
                SetScaledFont(row.value, fontSize, "")

                local valueColor = CONSTANTS.COLOR_VALUE
                if statKey == "itemLevel" then
                    valueColor = CONSTANTS.COLOR_ILVL
                elseif stat.ready ~= nil then
                    -- Gear rows (Enchants / Sockets X / Y): green when
                    -- everything required is present, red when something is missing.
                    valueColor = stat.ready and CONSTANTS.COLOR_READY or CONSTANTS.COLOR_ERROR
                end
                row.value:SetTextColor(CopyColor(valueColor))
                row.value:Show()

                row.detail:ClearAllPoints()
                row.detail:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, y)
                row.detail:SetText(stat.detail or "")
                row.detail:SetTextColor(CopyColor(CONSTANTS.COLOR_MUTED))
                SetScaledFont(row.detail, math.max(CONSTANTS.FONT_MIN, fontSize - 2), "")
                row.detail:Show()

                y = y - rowHeight
            end
        end

        y = y - 5
    end

    for index = headerIndex + 1, #panel.headers do
        panel.headers[index].text:Hide()
        panel.headers[index].line:Hide()
    end
    for index = rowIndex + 1, #panel.rows do
        panel.rows[index].label:Hide()
        panel.rows[index].value:Hide()
        panel.rows[index].detail:Hide()
    end

    local contentHeight = math.max(10, (-y) + 6)
    content:SetHeight(contentHeight)

    local scrollHeight = panel.scroll:GetHeight() or 1
    panel.scrollRange = math.max(0, contentHeight - scrollHeight)
    if (panel.scroll:GetVerticalScroll() or 0) > panel.scrollRange then
        panel.scroll:SetVerticalScroll(panel.scrollRange)
    end

    panel:Show()
    self:UpdateScrollThumb()
end
