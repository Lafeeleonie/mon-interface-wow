local _, ns = ...
local module = ns._sharedModules and ns._sharedModules.characterPanel
if not module then return end

-- ============================================================================
-- Inspect frame readiness bar + inspect refresh lifecycle
-- ============================================================================
-- Split out of CharacterPanelEnhancer.lua. Shared helpers are pulled from the
-- module table / Core (set up by the main file before this subfile loads).

local CONSTANTS = module.CONSTANTS
local INSPECT_REFRESH_DELAYS = module.INSPECT_REFRESH_DELAYS
local SLOT_DEFS = module:GetSlotDefinitions()
local GetSafeItemLevel = module.GetSafeItemLevel
local ResolveAccentPalette = module.ResolveAccentPalette
local FormatNumber = ns.Format.Number
local ColorHex = ns.Color.ToHex

function module:InstallInspectHooks()
    if self.inspectHooksInstalled then
        return
    end
    local inspectFrame = _G.InspectFrame
    if not inspectFrame then
        return
    end
    self.inspectHooksInstalled = true
    inspectFrame:HookScript("OnShow", function()
        if module.isActive then
            module:RefreshInspectWithFreshData()
            module:ScheduleInspectRefresh()
        end
    end)
    inspectFrame:HookScript("OnHide", function()
        module._inspectRefreshToken = (module._inspectRefreshToken or 0) + 1
        module:HideGear("inspect")
        if module.inspectReadiness then
            module.inspectReadiness.container:Hide()
        end
    end)
end

function module:GetInspectUnit()
    local inspectFrame = _G.InspectFrame
    if inspectFrame and type(inspectFrame.unit) == "string" and inspectFrame.unit ~= "" then
        return inspectFrame.unit
    end
    return "target"
end

-- Format helpers for the inspect bar -----------------------------------------

local function ColoredFraction(present, required, ok)
    local hex = ColorHex(ok and CONSTANTS.COLOR_READY or CONSTANTS.COLOR_ERROR)
    return hex .. present .. " / " .. required .. "|r"
end

-- Best-effort average item level for any unit. Prefers Blizzard's official
-- helper (which mirrors the value the inspect target's character sheet shows)
-- and falls back to a simple slot-by-slot average when the API is missing or
-- not yet populated for the inspected unit.
function module:ComputeAverageItemLevel(unit)
    if type(_G.C_PaperDollInfo) == "table"
        and type(_G.C_PaperDollInfo.GetInspectItemLevel) == "function" then
        local ok, avg = pcall(_G.C_PaperDollInfo.GetInspectItemLevel, unit)
        if ok then
            local n = tonumber(tostring(avg))
            if n and n > 0 then return n end
        end
    end
    local total, count = 0, 0
    if type(_G.GetInventoryItemLink) == "function" then
        for _, slotDef in ipairs(SLOT_DEFS) do
            local ok, link = pcall(_G.GetInventoryItemLink, unit, slotDef.id)
            if ok and link then
                local ilvl = GetSafeItemLevel(link)
                if ilvl and ilvl > 0 then
                    total = total + ilvl
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil end
    return total / count
end

function module:EnsureInspectReadiness()
    if self.inspectReadiness then
        return self.inspectReadiness
    end
    local inspectFrame = _G.InspectFrame
    if not inspectFrame then
        return nil
    end

    -- Slim top-bar docked ABOVE the inspect frame so it never overlaps the
    -- inspected player's name / portrait area. Behaves like an integrated
    -- header that summarises gear in three columns: Item Level | Enchants |
    -- Sockets.
    local bar = CreateFrame("Frame", nil, inspectFrame, "BackdropTemplate")
    bar:SetHeight(22)
    bar:SetPoint("BOTTOMLEFT", inspectFrame, "TOPLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", inspectFrame, "TOPRIGHT", 0, 2)
    bar:SetFrameLevel((inspectFrame:GetFrameLevel() or 1) + 10)
    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
        })
        -- Initial paint; RefreshInspectReadiness re-tints on every refresh so
        -- runtime accent / theme switches propagate without a /reload.
        local palette = ResolveAccentPalette()
        bar:SetBackdropColor(palette.surfaceDark[1], palette.surfaceDark[2], palette.surfaceDark[3], 0.95)
        bar:SetBackdropBorderColor(palette.header[1], palette.header[2], palette.header[3], 0.50)
    end

    -- Three text columns: LEFT / CENTER / RIGHT inside the bar. Each stays in
    -- its corner so adding a row later is just another bar below this one.
    local function MakeColumn(anchor, ox)
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        if anchor == "LEFT" then
            fs:SetPoint("LEFT", bar, "LEFT", ox, 0)
            fs:SetJustifyH("LEFT")
        elseif anchor == "RIGHT" then
            fs:SetPoint("RIGHT", bar, "RIGHT", ox, 0)
            fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("CENTER", bar, "CENTER", ox, 0)
            fs:SetJustifyH("CENTER")
        end
        return fs
    end

    local ilvlText    = MakeColumn("LEFT",   10)
    local enchantText = MakeColumn("CENTER", 0)
    local socketText  = MakeColumn("RIGHT",  -10)

    bar:Hide()
    self.inspectReadiness = {
        container = bar,
        ilvl      = ilvlText,
        enchants  = enchantText,
        sockets   = socketText,
    }
    return self.inspectReadiness
end

function module:RefreshInspectReadiness()
    local widget = self:EnsureInspectReadiness()
    if not widget then return end
    if not self.isActive
        or not self.settings
        or self.settings.showInspectGear ~= true
        or not _G.InspectFrame
        or not _G.InspectFrame:IsShown() then
        widget.container:Hide()
        return
    end

    -- Re-tint to the current accent palette on every refresh so accent /
    -- theme switches at runtime propagate to the inspect bar without a /reload.
    if widget.container.SetBackdropColor then
        local palette = ResolveAccentPalette()
        widget.container:SetBackdropColor(palette.surfaceDark[1], palette.surfaceDark[2], palette.surfaceDark[3], 0.95)
        widget.container:SetBackdropBorderColor(palette.header[1], palette.header[2], palette.header[3], 0.50)
    end

    local unit = self:GetInspectUnit()
    local r = self:ComputeReadiness(unit)
    local showAny = false

    local avg = self:ComputeAverageItemLevel(unit)
    if avg and avg > 0 then
        widget.ilvl:SetText("Item Level  " .. ColorHex(CONSTANTS.COLOR_ILVL) .. FormatNumber(avg, 1) .. "|r")
        widget.ilvl:Show()
        showAny = true
    else
        widget.ilvl:Hide()
    end

    if r.enchantRequired > 0 or r.enchantPresent > 0 then
        -- Display denominator never undershoots present: an inspected target
        -- with 8 enchants while we only require 7 shows "8 / 8", not "8 / 7".
        local denom = math.max(r.enchantPresent, r.enchantRequired)
        local ok = r.enchantPresent >= r.enchantRequired
        widget.enchants:SetText("Enchants  " .. ColoredFraction(r.enchantPresent, denom, ok))
        widget.enchants:Show()
        showAny = true
    else
        widget.enchants:Hide()
    end

    if r.socketsTotal > 0 then
        local ok = r.socketsFilled >= r.socketsTotal
        widget.sockets:SetText("Sockets  " .. ColoredFraction(r.socketsFilled, r.socketsTotal, ok))
        widget.sockets:Show()
        showAny = true
    else
        widget.sockets:Hide()
    end

    if showAny then
        widget.container:Show()
    else
        widget.container:Hide()
    end
end

function module:RefreshInspect()
    self:InstallInspectHooks()
    local inspectFrame = _G.InspectFrame
    if not inspectFrame or not inspectFrame:IsShown() then
        self:HideGear("inspect")
        if self.inspectReadiness then self.inspectReadiness.container:Hide() end
        return
    end
    self:RefreshGear("inspect", self:GetInspectUnit(), inspectFrame, true)
    self:RefreshInspectReadiness()
end

-- Cheap completion check on the just-populated slot-info cache. Returns true
-- when every slot either has no item (offhand on a 2H spec) or has a
-- resolved item level. When the first wave already saw complete data, the
-- caller bumps the refresh token so the late timer waves bail without
-- triggering another 16-slot rescan + readiness recompute.
function module:IsInspectDataComplete()
    local frame = _G.InspectFrame
    if not frame or not frame.IsShown or not frame:IsShown() then
        return true
    end
    local unit = self:GetInspectUnit()
    local bucket = self._slotInfoCache and self._slotInfoCache[unit]
    if not bucket then return false end
    for _, slotDef in ipairs(SLOT_DEFS) do
        local info = bucket[slotDef.key]
        if not info then return false end
        if info.itemLink and not info.itemLevel then return false end
    end
    return true
end

function module:RefreshInspectWithFreshData()
    self:InvalidateSlotInfoCache()
    self._readinessDirty = true
    self:RefreshInspect()
    -- If the wave we just ran already saw complete data, invalidate the
    -- remaining timer-deferred waves so they don't repeat the same 16-slot
    -- scan for no gain.
    if self:IsInspectDataComplete() then
        self._inspectRefreshToken = (self._inspectRefreshToken or 0) + 1
    end
end

function module:ScheduleInspectRefresh()
    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then
        return
    end

    local token = (self._inspectRefreshToken or 0) + 1
    self._inspectRefreshToken = token

    for _, delay in ipairs(INSPECT_REFRESH_DELAYS) do
        timer.After(delay, function()
            if module._inspectRefreshToken ~= token or not module.isActive then
                return
            end
            local inspectFrame = _G.InspectFrame
            if not inspectFrame or not inspectFrame.IsShown or not inspectFrame:IsShown() then
                return
            end
            module:RefreshInspectWithFreshData()
        end)
    end
end
