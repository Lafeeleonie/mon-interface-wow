local _, Addon = ...

local Module = { id = "systems.cooldowns", defaultEnabled = true }
local Service = {}
Addon.ProfessionCooldowns = Service
local scanRequested = false
local professionOpen = false

local function getRecord(characterKey)
    local record = Addon.Database:Get().characters[characterKey]
    return type(record) == "table" and record or nil
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local snapshot = record and type(record.snapshots) == "table" and record.snapshots.professionCooldowns or nil
    return type(snapshot) == "table" and snapshot or nil
end

function Service:GetView(characterKey)
    local record = type(characterKey) == "string" and getRecord(characterKey) or nil
    local identity = record and record.identity or nil
    return Addon.ProfessionCooldownLogic:BuildView(
        identity,
        self:GetSnapshot(characterKey),
        Addon.WarbandRoster:IsCurrent(characterKey)
    )
end

local function collectCooldowns()
    local identity = Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
    local record = identity and identity.key and getRecord(identity.key) or nil
    if not record then return nil end
    record.snapshots = type(record.snapshots) == "table" and record.snapshots or {}
    local snapshot = record.snapshots.professionCooldowns
    local scanned = false
    if scanRequested then
        snapshot, scanned = Addon.ProfessionCooldownLogic:ScanOpenProfession(identity, snapshot)
        if snapshot then record.snapshots.professionCooldowns = snapshot end
        scanRequested = false
    end
    return { characterKey = identity.key, snapshot = snapshot, scanned = scanned == true }
end

function Service:Refresh(scan, delaySeconds)
    scanRequested = scanRequested or scan == true
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectCooldowns)
    Addon.EventBus:Subscribe("PLAYER_ENTERING_WORLD", self, function()
        Service:Refresh(false, 1.0)
    end)
    Addon.EventBus:Subscribe("TRADE_SKILL_SHOW", self, function()
        professionOpen = true
        Service:Refresh(true, 0.15)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.75, function()
                if professionOpen then
                    Service:Refresh(true, 0.05)
                end
            end)
        end
    end)
    Addon.EventBus:Subscribe("TRADE_SKILL_CLOSE", self, function()
        professionOpen = false
        scanRequested = false
        Addon.RefreshScheduler:Cancel(Module.id)
    end)
    Addon.EventBus:Subscribe("TRADE_SKILL_LIST_UPDATE", self, function()
        if professionOpen then
            Service:Refresh(true, 0.20)
        end
    end)
    Addon.EventBus:Subscribe("CURRENCY_DISPLAY_UPDATE", self, function()
        if professionOpen then
            Service:Refresh(true, 0.20)
        end
    end)
    Addon.StateStore:Subscribe("character.identity", self, function()
        Service:Refresh(false, 0.15)
    end)
    Service:Refresh(false, 0.70)
end

Addon.ModuleRegistry:Register(Module)
