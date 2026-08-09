---@diagnostic disable: undefined-global

-- ─── EXBoss × Wago LibAddonProfiles Integration Layer ────────────
-- Wraps existing IE:Export / IE:Import under the function names
-- required by the Wago LibAddonProfiles API.
-- No import/export logic is modified in this file.
-- ──────────────────────────────────────────────────────────────────

EXBossWagoAPI = EXBossWagoAPI or {}

local ALL_SLOTS = {
    raid_tank = true,
    raid_dps = true,
    raid_heal = true,
    mplus_tank = true,
    mplus_dps = true,
    mplus_heal = true,
}

-- These meta fields change on every export and must be stripped before comparison,
-- otherwise Wago will falsely detect a config change on every export.
local VOLATILE_META_KEYS = { "exportedAt", "exporter", "addonVersion" }

local function GetIE()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
end

local function StripVolatileMeta(payload)
    if type(payload) == "table" and type(payload.meta) == "table" then
        for _, k in ipairs(VOLATILE_META_KEYS) do
            payload.meta[k] = nil
        end
    end
    return payload
end

-- ─── 1. ExportProfile ────────────────────────────────────────────
-- Called by Wago: pack author exports the current full config.
-- v1: profileKey is ignored; always exports all slots.
---@param profileKey string
---@return string|nil
function EXBossWagoAPI:ExportProfile(profileKey)
    local IE = GetIE()
    if not IE then return nil end
    local str, _ = IE:Export({
        includeAppearance = true,
        includeTrashCD    = true,
        includeSlots      = ALL_SLOTS,
        configName        = "Wago",
    })
    return str
end

-- ─── 2. ImportProfile ────────────────────────────────────────────
-- Called by Wago: imports config when a player installs a pack.
-- Equivalent to manually pasting a string into the import panel.
-- Backs up the current config to ExBossDB.wagoBackup.lastImportBefore first.
-- Must NOT call ReloadUI() here; Wago manages the reload timing.
---@param profileString string
---@param profileKey string
function EXBossWagoAPI:ImportProfile(profileString, profileKey)
    local IE = GetIE()
    if not IE then return end

    -- Backup current config so the user can restore it later if needed.
    local currentStr = IE:Export({
        includeAppearance = true,
        includeTrashCD    = true,
        includeSlots      = ALL_SLOTS,
    })
    if currentStr and ExBossDB then
        ExBossDB.wagoBackup = ExBossDB.wagoBackup or {}
        ExBossDB.wagoBackup.lastImportBefore = currentStr
    end

    local payload, _ = IE:DecodePayload(profileString)
    if not payload then return end
    IE:Import(payload, {
        importAppearance = true,
        importTrashCD    = true,
        importSlots      = ALL_SLOTS,
    })
end

-- ─── 3. DecodeProfileString ──────────────────────────────────────
-- Called by Wago: decodes a profile string without importing it,
-- used for diffing and change logs.
-- Volatile meta fields are stripped before returning to prevent
-- Wago from falsely reporting a config change.
---@param profileString string
---@return table|nil
function EXBossWagoAPI:DecodeProfileString(profileString)
    local IE = GetIE()
    if not IE then return nil end
    local payload, _ = IE:DecodePayload(profileString)
    if not payload then return nil end
    return StripVolatileMeta(payload)
end

-- ─── 4. SetProfile ───────────────────────────────────────────────
-- v1 has only a single "Global" profile, so this is a no-op.
---@param profileKey string
function EXBossWagoAPI:SetProfile(profileKey) end

-- ─── 5. GetProfileKeys ───────────────────────────────────────────
-- v1 always returns a single "Global" profile key.
---@return table
function EXBossWagoAPI:GetProfileKeys()
    return { Global = true }
end

-- ─── 6. GetCurrentProfileKey ─────────────────────────────────────
-- v1 always returns "Global".
---@return string
function EXBossWagoAPI:GetCurrentProfileKey()
    return "Global"
end

-- ─── 7. GetProfileAssignments ────────────────────────────────────
-- Optional: returns a character→profile mapping. Not implemented in v1.
---@return nil
function EXBossWagoAPI:GetProfileAssignments()
    return nil
end

-- ─── 8. OpenConfig / CloseConfig ─────────────────────────────────
-- Called by Wago: opens or closes the EXBoss settings panel.
function EXBossWagoAPI:OpenConfig()
    if ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.Show then
        ExBoss.UI.Panel:Show()
    end
end

function EXBossWagoAPI:CloseConfig()
    if ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.Hide then
        ExBoss.UI.Panel:Hide()
    end
end
