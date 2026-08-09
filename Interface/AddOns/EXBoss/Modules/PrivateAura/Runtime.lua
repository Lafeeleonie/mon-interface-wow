---@diagnostic disable: undefined-global

ExBoss.PrivateAura = ExBoss.PrivateAura or {}
local PrivateAura = ExBoss.PrivateAura

local ExwindTools = _G.ExwindTools
if not ExwindTools then
    return
end

local MODULE_KEY = "ExBoss.PrivateAuraOptions"

local CATEGORY_DEFAULTS = {
    enabled = true,
    sourceType = "pack",
    label = "",
    customLSM = "",
    customPath = "",
}

local activeSoundIDs = {}
local refreshPending = false

local RESTRICT_ENCOUNTER = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Encounter or 1
local RESTRICT_CHALLENGE = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.ChallengeMode or 2
local RESTRICT_PVP = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.PvPMatch or 3
local RESTRICT_STATE_INACTIVE = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0

local function NormalizeSourceType(value)
    local sourceType = tostring(value or "pack"):lower()
    if sourceType ~= "lsm" and sourceType ~= "file" then
        sourceType = "pack"
    end
    return sourceType
end

local function EnsureConfigShape(cfg)
    cfg = type(cfg) == "table" and cfg or {}
    if cfg.enabled == nil then
        cfg.enabled = CATEGORY_DEFAULTS.enabled
    else
        cfg.enabled = cfg.enabled == true
    end
    cfg.sourceType = NormalizeSourceType(cfg.sourceType or CATEGORY_DEFAULTS.sourceType)
    if type(cfg.label) ~= "string" then
        cfg.label = CATEGORY_DEFAULTS.label
    end
    if type(cfg.customLSM) ~= "string" then
        cfg.customLSM = CATEGORY_DEFAULTS.customLSM
    end
    if type(cfg.customPath) ~= "string" then
        cfg.customPath = CATEGORY_DEFAULTS.customPath
    end
    return cfg
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function NormalizeVoiceCategory(value)
    if PrivateAura and type(PrivateAura.NormalizeVoiceCategory) == "function" then
        return PrivateAura:NormalizeVoiceCategory(value)
    end
    local num = tonumber(value)
    if num == 1 or num == 2 then
        return num
    end
    return 3
end

local function GetEntryConfig(root, key)
    key = tostring(key or "")
    if key == "" then
        return nil
    end
    local entries = type(root) == "table" and type(root.entries) == "table" and root.entries or nil
    local row = entries and entries[key] or nil
    if row then
        return EnsureConfigShape(row)
    end
    return nil
end

local function ConfigHasSoundInfo(cfg)
    cfg = EnsureConfigShape(cfg)
    local sourceType = NormalizeSourceType(cfg.sourceType)
    if sourceType == "pack" then
        return type(cfg.label) == "string" and cfg.label ~= ""
    end
    if sourceType == "lsm" then
        return type(cfg.customLSM) == "string" and cfg.customLSM ~= ""
    end
    return type(cfg.customPath) == "string" and cfg.customPath ~= ""
end

local function ResolveSoundInfo(cfg)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not engine or type(engine.ResolveStandaloneSound) ~= "function" then
        return nil
    end
    return engine:ResolveStandaloneSound(cfg, { triggerIndex = 0 })
end

local function RemoveAllRegisteredSounds()
    if not (C_UnitAuras and C_UnitAuras.RemovePrivateAuraAppliedSound) then
        wipe(activeSoundIDs)
        return
    end
    for i = 1, #activeSoundIDs do
        local soundID = activeSoundIDs[i]
        if soundID then
            pcall(C_UnitAuras.RemovePrivateAuraAppliedSound, soundID)
        end
    end
    wipe(activeSoundIDs)
end

local function AddRegisteredSound(file, spellID, channel)
    if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAppliedSound) then
        return nil, "api unavailable"
    end
    if type(file) ~= "string" or file == "" then
        return nil, "empty file"
    end
    local payload = {
        unitToken = "player",
        spellID = tonumber(spellID),
        soundFileName = file,
        outputChannel = tostring(channel or "Master"),
    }
    local ok, soundID = pcall(C_UnitAuras.AddPrivateAuraAppliedSound, payload)
    if ok and soundID then
        activeSoundIDs[#activeSoundIDs + 1] = soundID
        return soundID
    end
    return nil, soundID
end

local function BuildRaidKey(encounterID, spellID)
    return "pa:raid:" .. tostring(encounterID) .. ":" .. tostring(spellID)
end

local function BuildMplusBossKey(dungeonName, bossName, spellID)
    return "pa:mplus:boss:" .. tostring(dungeonName or "unknown") .. ":" .. tostring(bossName or "unknown") .. ":" .. tostring(spellID)
end

local function FindRaidBossNameForDungeonSpell(dungeonName, spellID)
    local raw = type(PrivateAura.GetRawData) == "function" and PrivateAura:GetRawData() or nil
    local raid = raw and raw.raid or nil
    if type(raid) ~= "table" then
        return ""
    end
    local normalizedDungeon = tostring(dungeonName or "")
    for _, row in pairs(raid) do
        if type(row) == "table" and type(row.spells) == "table" then
            local rowDungeon = tostring(row.dungeon or "")
            if rowDungeon == normalizedDungeon and type(row.spells[tonumber(spellID)]) == "table" then
                local bossText = tostring(row.boss or "")
                local plain = bossText:match("^(.-)%s*%(") or bossText
                plain = tostring(plain or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if plain ~= "" then
                    return plain
                end
            end
        end
    end
    return ""
end

local function ResolveMplusBossNameForKey(dungeonName, bosses, spellID)
    local raidBossName = FindRaidBossNameForDungeonSpell(dungeonName, spellID)
    if raidBossName ~= "" then
        return raidBossName
    end
    if type(bosses) == "table" then
        for i = 1, #bosses do
            local bossName = tostring(bosses[i] or "")
            if bossName ~= "" then
                return bossName
            end
        end
    end
    return ""
end

local function CollectRaidRows(encounterID)
    local out = {}
    local row = PrivateAura:GetRaidBoss(encounterID)
    if type(row) ~= "table" or type(row.spells) ~= "table" then
        return out
    end
    for spellID, spellRow in pairs(row.spells) do
        local sid = tonumber(spellID)
        if sid and type(spellRow) == "table" then
            out[#out + 1] = {
                key = BuildRaidKey(encounterID, sid),
                spellID = sid,
                voiceCategory = NormalizeVoiceCategory(spellRow.voiceCategory),
            }
        end
    end
    table.sort(out, function(a, b) return (a.spellID or 0) < (b.spellID or 0) end)
    return out
end

local function CollectRaidRowsForCurrentInstance()
    local out = {}
    local instanceName, instanceType = GetInstanceInfo and GetInstanceInfo() or nil, nil
    if GetInstanceInfo then
        instanceName, instanceType = select(1, GetInstanceInfo()), select(2, GetInstanceInfo())
    end
    if instanceType ~= "raid" or type(instanceName) ~= "string" or instanceName == "" then
        return out
    end
    local raw = type(PrivateAura.GetRawData) == "function" and PrivateAura:GetRawData() or nil
    local raid = raw and raw.raid
    if type(raid) ~= "table" then
        return out
    end
    for encounterID, row in pairs(raid) do
        if type(row) == "table" and row.dungeon == instanceName and type(row.spells) == "table" then
            for spellID, spellRow in pairs(row.spells) do
                local sid = tonumber(spellID)
                if sid and type(spellRow) == "table" then
                    out[#out + 1] = {
                        key = BuildRaidKey(encounterID, sid),
                        spellID = sid,
                        voiceCategory = NormalizeVoiceCategory(spellRow.voiceCategory),
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.spellID or 0) == (b.spellID or 0) then
            return tostring(a.key or "") < tostring(b.key or "")
        end
        return (a.spellID or 0) < (b.spellID or 0)
    end)
    return out
end

local function CollectMplusRows()
    local out = {}
    local instanceName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
    if type(instanceName) ~= "string" or instanceName == "" then
        return out
    end
    local row = PrivateAura:GetMplusDungeon(instanceName)
    if type(row) ~= "table" or type(row.spells) ~= "table" then
        return out
    end
    for spellID, spellRow in pairs(row.spells) do
        local sid = tonumber(spellID)
        if sid and type(spellRow) == "table" then
            local bosses = type(spellRow.bosses) == "table" and spellRow.bosses or {}
            local chosenBoss = ResolveMplusBossNameForKey(row.dungeon or instanceName, bosses, sid)
            out[#out + 1] = {
                key = BuildMplusBossKey(row.dungeon or instanceName, chosenBoss, sid),
                spellID = sid,
                voiceCategory = NormalizeVoiceCategory(spellRow.voiceCategory),
                dungeon = row.dungeon or instanceName,
                boss = chosenBoss,
                bosses = bosses,
            }
        end
    end
    table.sort(out, function(a, b) return (a.spellID or 0) < (b.spellID or 0) end)
    return out
end

local function ApplyRows(rows, root)
    RemoveAllRegisteredSounds()
    for i = 1, #rows do
        local row = rows[i]
        local cfg = GetEntryConfig(root, row.key)
        if cfg and cfg.enabled ~= false then
            local soundInfo = ResolveSoundInfo(cfg)
            if soundInfo and soundInfo.file and soundInfo.file ~= "" then
                AddRegisteredSound(soundInfo.file, row.spellID, soundInfo.channel)
            end
        end
    end
end

local function CanRefreshNow()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if C_RestrictedActions and type(C_RestrictedActions.GetAddOnRestrictionState) == "function" then
        if C_RestrictedActions.GetAddOnRestrictionState(RESTRICT_ENCOUNTER) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
        if C_RestrictedActions.GetAddOnRestrictionState(RESTRICT_CHALLENGE) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
        if C_RestrictedActions.GetAddOnRestrictionState(RESTRICT_PVP) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
    elseif C_RestrictedActions and type(C_RestrictedActions.GetRestrictionState) == "function" then
        if C_RestrictedActions.GetRestrictionState(RESTRICT_ENCOUNTER) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
        if C_RestrictedActions.GetRestrictionState(RESTRICT_CHALLENGE) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
        if C_RestrictedActions.GetRestrictionState(RESTRICT_PVP) ~= RESTRICT_STATE_INACTIVE then
            return false
        end
    elseif C_RestrictedActions and type(C_RestrictedActions.IsAddOnRestrictionActive) == "function" then
        if C_RestrictedActions.IsAddOnRestrictionActive(RESTRICT_ENCOUNTER) then
            return false
        end
        if C_RestrictedActions.IsAddOnRestrictionActive(RESTRICT_CHALLENGE) then
            return false
        end
        if C_RestrictedActions.IsAddOnRestrictionActive(RESTRICT_PVP) then
            return false
        end
    elseif C_RestrictedActions and type(C_RestrictedActions.IsRestrictionActive) == "function" then
        if C_RestrictedActions.IsRestrictionActive(RESTRICT_ENCOUNTER) then
            return false
        end
        if C_RestrictedActions.IsRestrictionActive(RESTRICT_CHALLENGE) then
            return false
        end
        if C_RestrictedActions.IsRestrictionActive(RESTRICT_PVP) then
            return false
        end
    end
    return true
end

local function QueueRefresh()
    refreshPending = true
end

local function FinishRefresh()
    refreshPending = false
end

function PrivateAura:RefreshActiveRegistrations()
    if not CanRefreshNow() then
        QueueRefresh()
        return
    end

    local bossCfg = GetBossConfig()
    local instanceType = GetInstanceInfo and select(2, GetInstanceInfo()) or nil
    if instanceType == "raid" then
        local root = nil
        if bossCfg and type(bossCfg.GetRuntimeSlotForScene) == "function" and type(bossCfg.GetResolvedPrivateAuraConfig) == "function" then
            root = bossCfg:GetResolvedPrivateAuraConfig(bossCfg:GetRuntimeSlotForScene("raid"))
        end
        ApplyRows(CollectRaidRowsForCurrentInstance(), root)
        FinishRefresh()
        return
    end
    if instanceType == "party" then
        local root = nil
        if bossCfg and type(bossCfg.GetRuntimeSlotForScene) == "function" and type(bossCfg.GetResolvedPrivateAuraConfig) == "function" then
            root = bossCfg:GetResolvedPrivateAuraConfig(bossCfg:GetRuntimeSlotForScene("mplus"))
        end
        ApplyRows(CollectMplusRows(), root)
        FinishRefresh()
        return
    end
    RemoveAllRegisteredSounds()
    FinishRefresh()
end

function PrivateAura:ClearActiveRegistrations()
    RemoveAllRegisteredSounds()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_PrivateAura_PEW", function()
    PrivateAura:RefreshActiveRegistrations()
end)

ExwindTools:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ExBoss_PrivateAura_Zone", function()
    PrivateAura:RefreshActiveRegistrations()
end)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", "ExBoss_PrivateAura_ConfigChanged", function()
    PrivateAura:RefreshActiveRegistrations()
end)

ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", "ExBoss_PrivateAura_RegenEnabled", function()
    if refreshPending then
        PrivateAura:RefreshActiveRegistrations()
    end
end)

ExwindTools:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "ExBoss_PrivateAura_RestrictionChanged", function()
    if refreshPending then
        PrivateAura:RefreshActiveRegistrations()
    end
end)
