local _, Addon = ...

local Module = { id = "dungeons.journal", defaultEnabled = true }
local Service = {}
Addon.DungeonJournal = Service

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
    ui.dungeonJournal = type(ui.dungeonJournal) == "table" and ui.dungeonJournal or {}
    local raw = ui.dungeonJournal
    raw.selectedRaidKeys = type(raw.selectedRaidKeys) == "table" and raw.selectedRaidKeys or {}
    raw.selectedBossKeys = type(raw.selectedBossKeys) == "table" and raw.selectedBossKeys or {}
    raw.difficultyKey = Addon.DungeonJournalLogic:IsDifficultyKey(raw.difficultyKey) and raw.difficultyKey or "normal"
    raw.classFilterKey = raw.classFilterKey == "all" and "all" or "player"
    local subTabKey = Addon.DungeonJournalLogic:IsSubTabKey(ui.selectedSubTabs.dungeons)
        and ui.selectedSubTabs.dungeons or "midnight"
    return {
        subTabKey = subTabKey,
        selectedRaidKey = type(raw.selectedRaidKeys[subTabKey]) == "string" and raw.selectedRaidKeys[subTabKey] or "",
        selectedBossKey = type(raw.selectedBossKeys[subTabKey]) == "string" and raw.selectedBossKeys[subTabKey] or "",
        difficultyKey = raw.difficultyKey,
        classFilterKey = raw.classFilterKey,
    }
end

function Service:GetSnapshot(characterKey, subTabKey)
    subTabKey = Addon.DungeonJournalLogic:IsSubTabKey(subTabKey) and subTabKey or self:GetSettings().subTabKey
    local record = getRecord(characterKey)
    local journal = record and type(record.snapshots) == "table" and record.snapshots.dungeonJournal or nil
    local snapshot = type(journal) == "table" and journal[subTabKey] or nil
    if type(snapshot) ~= "table" then return nil end
    if not Addon.DungeonJournalLogic:IsSnapshotValid(snapshot) then
        journal[subTabKey] = nil
        return nil
    end
    return snapshot
end

function Service:GetView(characterKey)
    local state = Addon.StateStore:Get(Module.id)
    local settings = self:GetSettings()
    if type(state) == "table" and state.characterKey == characterKey and state.subTabKey == settings.subTabKey
        and type(state.view) == "table"
    then
        return state.view
    end
    local record = getRecord(characterKey)
    return Addon.DungeonJournalLogic:BuildView(
        self:GetSnapshot(characterKey, settings.subTabKey), settings, record and record.identity or nil, nil
    )
end

function Service:GetLootTrackerState(characterKey, difficultyKey, itemID)
    return Addon.JournalLootTracker:GetState(characterKey, difficultyKey, itemID)
end

function Service:CycleLootTrackerState(characterKey, difficultyKey, itemID, item, source)
    local nextState = Addon.JournalLootTracker:CycleState(characterKey, difficultyKey, itemID, function(key)
        return Addon.DungeonJournalLogic:IsDifficultyKey(key)
    end, item, source)
    if nextState == nil and (type(characterKey) ~= "string" or not Addon.DungeonJournalLogic:IsDifficultyKey(difficultyKey)) then
        return nil
    end
    self:Refresh(false, 0)
    return nextState
end

function Service:ClearLootTrackerState(characterKey, difficultyKey, itemID)
    if not Addon.DungeonJournalLogic:IsDifficultyKey(difficultyKey) then return false end
    local removed = Addon.JournalLootTracker:RemoveEntry(characterKey, difficultyKey, itemID)
    if removed then self:Refresh(false, 0) end
    return removed
end

function Service:SetSelection(dungeonKey, bossKey)
    local settings = self:GetSettings()
    local raw = Addon.Database:GetUI().dungeonJournal
    if type(dungeonKey) == "string" then raw.selectedRaidKeys[settings.subTabKey] = dungeonKey end
    if type(bossKey) == "string" then raw.selectedBossKeys[settings.subTabKey] = bossKey end
    self:Refresh(false, 0)
end

function Service:SetSubTab(subTabKey)
    if not Addon.DungeonJournalLogic:IsSubTabKey(subTabKey) then return false end
    Addon.Database:GetUI().selectedSubTabs.dungeons = subTabKey
    self:Refresh(true, 0)
    return true
end

function Service:SetDifficulty(difficultyKey)
    if not Addon.DungeonJournalLogic:IsDifficultyKey(difficultyKey) then return false end
    Addon.Database:GetUI().dungeonJournal.difficultyKey = difficultyKey
    self:Refresh(true, 0)
    return true
end

function Service:SetClassFilter(classFilterKey)
    if classFilterKey ~= "player" and classFilterKey ~= "all" then return false end
    Addon.Database:GetUI().dungeonJournal.classFilterKey = classFilterKey
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
    local existing = Service:GetSnapshot(identity.key, settings.subTabKey)
    local snapshot = existing
    local scanned, scanError = false, nil
    if opened and scanRequested then
        loadEncounterJournal()
        snapshot, scanned, scanError = Addon.DungeonJournalLogic:ScanSnapshot(
            settings.subTabKey, identity, existing, settings.difficultyKey,
            Addon.WarbandRoster:IsCurrent(identity.key), now()
        )
        if scanned and Addon.WarbandRoster:IsCurrent(identity.key) and record then
            record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
            record.snapshots.dungeonJournal = type(record.snapshots.dungeonJournal) == "table" and record.snapshots.dungeonJournal or {}
            record.snapshots.dungeonJournal[settings.subTabKey] = snapshot
        end
        scanRequested = false
    end
    local view = Addon.DungeonJournalLogic:BuildView(snapshot, settings, identity, nil)
    local loot, lootAvailable = {}, false
    if opened and view.selectedRaid and view.selectedBoss then
        loot, lootAvailable = Addon.DungeonJournalLogic:ScanLoot(
            view.selectedRaid, view.selectedBoss, view.difficultyKey, view.classFilterKey, identity
        )
        view = Addon.DungeonJournalLogic:BuildView(snapshot, settings, identity, loot)
    end
    return {
        characterKey = identity.key,
        subTabKey = settings.subTabKey,
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
        CHALLENGE_MODE_MAPS_UPDATE = true,
        EJ_LOOT_DATA_RECIEVED = "missing-bosses",
    }
    for eventName, needsScan in pairs(events) do
        local registeredEvent = eventName
        local scanMode = needsScan
        Addon.EventBus:Subscribe(eventName, Module, function()
            if registeredEvent == "CHALLENGE_MODE_MAPS_UPDATE" then
                Addon.DungeonJournalLogic:InvalidateCatalog()
            end
            if not opened then return end
            local scanOnEvent = scanMode == true
            if scanMode == "missing-bosses" then
                local state = Addon.StateStore:Get(Module.id)
                local dungeons = state and state.view and state.view.dungeons or {}
                for _, dungeon in ipairs(dungeons) do
                    if type(dungeon.bosses) ~= "table" or #dungeon.bosses == 0 then
                        scanOnEvent = true
                        break
                    end
                end
            end
            Service:Refresh(scanOnEvent, 0.20)
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
