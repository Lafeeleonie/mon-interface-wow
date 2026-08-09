local _, Addon = ...

local Module = {
    id = "character.identity",
    defaultEnabled = true,
}

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "PLAYER_EQUIPMENT_CHANGED",
    "SKILL_LINES_CHANGED",
    "TRADE_SKILL_LIST_UPDATE",
}

local function updateMoney()
    local identity = Addon.StateStore:Get(Module.id)
    if type(identity) ~= "table" then
        Addon.RefreshScheduler:Invalidate(Module.id, 0)
        return
    end
    local money = type(GetMoney) == "function" and tonumber(GetMoney()) or nil
    if money == nil or identity.money == money then
        return
    end

    identity.money = money
    identity.lastSeen = type(time) == "function" and time() or identity.lastSeen
    local record = Addon.Database:Get().characters[identity.key]
    if type(record) == "table" and type(record.identity) == "table" then
        record.identity.money = money
        record.identity.lastSeen = identity.lastSeen
    end

    if Addon:IsMainWindowShown() and Addon.UI then
        if type(Addon.UI.RefreshSidebar) == "function" then Addon.UI:RefreshSidebar() end
        if type(Addon.UI.RefreshCharacterContext) == "function" then Addon.UI:RefreshCharacterContext() end
    end
end

local function collectIdentity()
    local identity = Addon.WoWApi:GetCurrentCharacterIdentity()
    local db = Addon.Database:Get()
    local record = type(db.characters[identity.key]) == "table" and db.characters[identity.key] or {}
    if identity.professions == nil and type(record.identity) == "table" then
        identity.professions = record.identity.professions
    end
    record.identity = identity
    db.characters[identity.key] = record

    if type(db.mainCharacterKey) ~= "string" or db.mainCharacterKey == "" then
        db.mainCharacterKey = identity.key
    end
    if type(db.ui.selectedCharacterKey) ~= "string" or db.ui.selectedCharacterKey == "" then
        db.ui.selectedCharacterKey = identity.key
    end
    return identity
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectIdentity)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            local delay = event == "PLAYER_ENTERING_WORLD" and 0.10 or 0.05
            Addon.RefreshScheduler:Invalidate(Module.id, delay)
        end)
    end
    Addon.EventBus:Subscribe("PLAYER_MONEY", self, updateMoney)
    Addon.RefreshScheduler:Invalidate(self.id, 0)
end

Addon.ModuleRegistry:Register(Module)
