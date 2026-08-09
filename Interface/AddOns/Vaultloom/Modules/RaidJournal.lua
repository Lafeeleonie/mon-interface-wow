local _, Addon = ...

local Module = { id = "raids.journal", defaultEnabled = true }
local Service = {}
Addon.RaidJournal = Service

local opened = false
local scanRequested = false
local liveEventsRegistered = false

local function now()
    return type(time) == "function" and time() or 0
end

local function getRecord(characterKey)
    local record = type(characterKey) == "string" and Addon.Database:Get().characters[characterKey] or nil
    return type(record) == "table" and record or nil
end

local function getSelectedIdentity()
    local selected = Addon.WarbandRoster:GetSelected()
    local record = selected and getRecord(selected.key) or nil
    return (record and record.identity) or selected
end

function Service:GetSettings()
    local ui = Addon.Database:GetUI()
    ui.raidJournal = type(ui.raidJournal) == "table" and ui.raidJournal or {}
    ui.raidJournal.selectedRaidKey = type(ui.raidJournal.selectedRaidKey) == "string" and ui.raidJournal.selectedRaidKey or ""
    ui.raidJournal.selectedBossKey = type(ui.raidJournal.selectedBossKey) == "string" and ui.raidJournal.selectedBossKey or ""
    ui.raidJournal.difficultyKey = Addon.RaidJournalLogic:IsDifficultyKey(ui.raidJournal.difficultyKey)
        and ui.raidJournal.difficultyKey or "normal"
    ui.raidJournal.classFilterKey = ui.raidJournal.classFilterKey == "all" and "all" or "player"
    return ui.raidJournal
end

function Service:GetSnapshot(characterKey)
    local record = getRecord(characterKey)
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.raidJournal or nil
    if type(snapshot) ~= "table" then return nil end
    if not Addon.RaidJournalLogic:IsSnapshotValid(snapshot) then
        record.snapshots.raidJournal = nil
        return nil
    end
    return snapshot
end

function Service:GetView(characterKey)
    local state = Addon.StateStore:Get(Module.id)
    if type(state) == "table" and state.characterKey == characterKey and type(state.view) == "table" then
        return state.view
    end
    local record = getRecord(characterKey)
    return Addon.RaidJournalLogic:BuildView(
        self:GetSnapshot(characterKey), self:GetSettings(), record and record.identity or nil, nil
    )
end

function Service:GetLootTrackerState(characterKey, difficultyKey, itemID)
    return Addon.JournalLootTracker:GetState(characterKey, difficultyKey, itemID)
end

function Service:CycleLootTrackerState(characterKey, difficultyKey, itemID, item, source)
    local nextState = Addon.JournalLootTracker:CycleState(characterKey, difficultyKey, itemID, function(key)
        return Addon.RaidJournalLogic:IsDifficultyKey(key)
    end, item, source)
    if nextState == nil and (type(characterKey) ~= "string" or not Addon.RaidJournalLogic:IsDifficultyKey(difficultyKey)) then
        return nil
    end
    self:Refresh(false, 0)
    return nextState
end

function Service:ClearLootTrackerState(characterKey, difficultyKey, itemID)
    if not Addon.RaidJournalLogic:IsDifficultyKey(difficultyKey) then return false end
    local removed = Addon.JournalLootTracker:RemoveEntry(characterKey, difficultyKey, itemID)
    if removed then self:Refresh(false, 0) end
    return removed
end

function Service:SetSubTab(subTabKey)
    if subTabKey ~= "midnight" then return false end
    Addon.Database:GetUI().selectedSubTabs.raids = "midnight"
    self:Refresh(false, 0)
    return true
end

function Service:SetSelection(raidKey, bossKey)
    local settings = self:GetSettings()
    if type(raidKey) == "string" then settings.selectedRaidKey = raidKey end
    if type(bossKey) == "string" then settings.selectedBossKey = bossKey end
    self:Refresh(false, 0)
end

function Service:SetDifficulty(difficultyKey)
    if not Addon.RaidJournalLogic:IsDifficultyKey(difficultyKey) then return false end
    self:GetSettings().difficultyKey = difficultyKey
    self:Refresh(true, 0)
    return true
end

function Service:SetClassFilter(classFilterKey)
    if classFilterKey ~= "player" and classFilterKey ~= "all" then return false end
    self:GetSettings().classFilterKey = classFilterKey
    self:Refresh(false, 0)
    return true
end

local function loadEncounterJournal()
    if type(EJ_GetNumTiers) == "function" then return true end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif type(LoadAddOn) == "function" then
        pcall(LoadAddOn, "Blizzard_EncounterJournal")
    end
    return type(EJ_GetNumTiers) == "function"
end

local function collectJournal()
    local identity = getSelectedIdentity()
    if not identity or not identity.key then return nil end
    local record = getRecord(identity.key)
    local settings = Service:GetSettings()
    local existing = Service:GetSnapshot(identity.key)
    local snapshot = existing
    local scanned, scanError = false, nil
    if opened and scanRequested then
        loadEncounterJournal()
        snapshot, scanned, scanError = Addon.RaidJournalLogic:ScanSnapshot(
            identity, existing, settings.difficultyKey, Addon.WarbandRoster:IsCurrent(identity.key), now()
        )
        if scanned and Addon.WarbandRoster:IsCurrent(identity.key) and record then
            record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
            record.snapshots.raidJournal = snapshot
        end
        scanRequested = false
    end
    local view = Addon.RaidJournalLogic:BuildView(snapshot, settings, identity, nil)
    local loot, lootAvailable = {}, false
    if opened and view.selectedRaid and view.selectedBoss then
        loot, lootAvailable = Addon.RaidJournalLogic:ScanLoot(
            view.selectedRaid, view.selectedBoss, view.difficultyKey, view.classFilterKey, identity
        )
        view = Addon.RaidJournalLogic:BuildView(snapshot, settings, identity, loot)
    end
    return {
        characterKey = identity.key,
        opened = opened,
        scanned = scanned,
        scanError = scanError,
        lootAvailable = lootAvailable,
        snapshot = snapshot,
        view = view,
    }
end

function Service:Refresh(scan, delaySeconds)
    scanRequested = scanRequested or scan == true
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

local function registerLiveEvents()
    if liveEventsRegistered then return end
    liveEventsRegistered = true
    local events = {
        UPDATE_INSTANCE_INFO = true,
        BOSS_KILL = true,
        PLAYER_DIFFICULTY_CHANGED = true,
        EJ_LOOT_DATA_RECIEVED = false,
    }
    for eventName, needsScan in pairs(events) do
        local scanOnEvent = needsScan
        Addon.EventBus:Subscribe(eventName, Module, function()
            if opened then Service:Refresh(scanOnEvent, 0.20) end
        end)
    end
end

function Service:Open()
    if not opened then
        opened = true
        registerLiveEvents()
        loadEncounterJournal()
        self:Refresh(true, 0)
    end
end

function Service:Close()
    if not opened then return end
    opened = false
    scanRequested = false
    self:Refresh(false, 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectJournal)
    Addon.StateStore:Subscribe("warband.selection", self, function()
        if opened then Service:Refresh(true, 0.10) end
    end)
    Service:Refresh(false, 0.80)
end

function Module:OnDisable()
    opened = false
    scanRequested = false
    liveEventsRegistered = false
end

Addon.ModuleRegistry:Register(Module)
