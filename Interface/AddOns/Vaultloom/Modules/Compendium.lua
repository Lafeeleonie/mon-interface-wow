local _, Addon = ...

local Module = {
    id = "compendium.catalog",
    defaultEnabled = true,
}

local Service = {
    addonName = Addon.Identity.addonName .. "_Compendium",
    opened = false,
    catalog = nil,
    prepared = nil,
    runtime = nil,
    loadError = nil,
    housingCatalogObserved = false,
}
Addon.Compendium = Service

local COLLECTION_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "COMPANION_UPDATE",
    "NEW_MOUNT_ADDED",
    "PET_JOURNAL_LIST_UPDATE",
    "TOYS_UPDATED",
    "NEW_TOY_ADDED",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "SKILL_LINES_CHANGED",
    "HOUSING_CATALOG_ENTRY_UPDATED",
}

local function currentIdentity()
    return Addon.StateStore:Get("character.identity") or Addon.WoWApi:GetCurrentCharacterIdentity()
end

local function currentRecord()
    local identity = currentIdentity()
    local characters = Addon.Database:Get().characters
    local record = identity and identity.key and characters[identity.key]
    return identity, type(record) == "table" and record or nil
end

local function decorationKeys(entry)
    local keys = {}
    if tonumber(entry and entry.decorID) then keys[#keys + 1] = "decor:" .. tostring(entry.decorID) end
    if tonumber(entry and entry.itemID) then keys[#keys + 1] = "item:" .. tostring(entry.itemID) end
    if type(entry and entry.key) == "string" and entry.key ~= "" then keys[#keys + 1] = "entry:" .. entry.key end
    return keys
end

local function getDecorationCount(entry)
    local _, record = currentRecord()
    local snapshots = record and record.compendiumDecorationCounts
    local best
    for _, key in ipairs(decorationKeys(entry)) do
        local snapshot = type(snapshots) == "table" and snapshots[key] or nil
        local count = type(snapshot) == "table" and tonumber(snapshot.ownedCount) or tonumber(snapshot)
        if count ~= nil and (best == nil or count > best) then best = count end
    end
    return best
end

local function rememberDecorationCount(entry, count)
    local _, record = currentRecord()
    count = math.max(0, math.floor(tonumber(count) or 0))
    if not record then return end
    record.compendiumDecorationCounts = type(record.compendiumDecorationCounts) == "table"
        and record.compendiumDecorationCounts or {}
    local updatedAt = type(time) == "function" and time() or 0
    for _, key in ipairs(decorationKeys(entry)) do
        local previous = record.compendiumDecorationCounts[key]
        local previousCount = type(previous) == "table" and tonumber(previous.ownedCount) or tonumber(previous)
        if previousCount == nil or count > 0 or previousCount <= 0 or Service.housingCatalogObserved then
            record.compendiumDecorationCounts[key] = {
                ownedCount = count,
                updatedAt = updatedAt,
            }
        end
    end
end

local function uiState()
    return Addon.Database:GetUI().compendium
end

local function statePayload(view)
    local identity = currentIdentity()
    return {
        opened = Service.opened,
        loaded = Service.prepared ~= nil,
        loading = Service.opened and Service.prepared == nil and Service.loadError == nil,
        loadError = Service.loadError,
        characterKey = identity and identity.key,
        rawCounts = Service.prepared and Service.prepared.rawCounts or nil,
        runtime = Service.runtime,
        view = view,
    }
end

local function publishView()
    local view = Service.runtime and Addon.CompendiumLogic:BuildView(Service.runtime, uiState()) or nil
    local state = statePayload(view)
    Addon.StateStore:Set(Module.id, state)
    return state
end

local function collect()
    if not Service.opened or not Service.prepared then return statePayload(nil) end
    local identity = currentIdentity()
    Service.housingCatalogObserved = false
    Service.runtime = Addon.CompendiumLogic:BuildRuntime(Service.prepared, {
        identity = identity,
        getDecorationCount = getDecorationCount,
        rememberDecorationCount = rememberDecorationCount,
        housingCatalogObserved = Service.housingCatalogObserved,
    })
    return statePayload(Addon.CompendiumLogic:BuildView(Service.runtime, uiState()))
end

local function loadAddon(addonName)
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        return C_AddOns.LoadAddOn(addonName)
    end
    if type(LoadAddOn) == "function" then return LoadAddOn(addonName) end
    return false, "MISSING"
end

local function addonLoaded(addonName)
    return Addon.WoWApi:IsAddOnLoaded(addonName)
end

function Service:RegisterCatalog(catalog)
    local prepared = Addon.CompendiumLogic:PrepareCatalog(catalog)
    if not prepared then return false end
    self.catalog = catalog
    self.prepared = prepared
    self.loadError = nil
    if self.opened then self:RefreshRuntime(0) else publishView() end
    return true
end

function Service:EnsureCatalogLoaded()
    if self.prepared then return true end
    local loaded, reason = addonLoaded(self.addonName), nil
    if not loaded then
        local ok
        ok, reason = loadAddon(self.addonName)
        loaded = ok == true or addonLoaded(self.addonName)
    end
    if loaded and self.prepared then
        self.loadError = nil
        return true
    end
    self.loadError = tostring(reason or (loaded and "NO_CATALOG" or "MISSING"))
    return false
end

function Service:GetState()
    return Addon.StateStore:Get(Module.id)
end

function Service:GetView()
    local state = self:GetState()
    return state and state.view
end

function Service:IsOpen()
    return self.opened == true
end

function Service:RefreshRuntime(delaySeconds)
    if not self.opened or not self.prepared then return false end
    return Addon.RefreshScheduler:Invalidate(Module.id, delaySeconds or 0)
end

function Service:Refresh()
    self.runtime = nil
    return self:RefreshRuntime(0)
end

function Service:Open()
    self.opened = true
    if not self:EnsureCatalogLoaded() then
        publishView()
        return false
    end
    if self.runtime then return true end
    return self:RefreshRuntime(0)
end

function Service:Close()
    if not self.opened then return false end
    self.opened = false
    Addon.RefreshScheduler:Cancel(Module.id)
    self.runtime = nil
    publishView()
    return true
end

local function setFilter(key, value)
    local state = uiState()
    state[key] = value
    if key == "category" then
        state.source = "all"
        state.profession = "all"
    elseif key == "profession" then
        state.source = "all"
    end
    publishView()
    return true
end

function Service:SetCategory(value)
    value = tostring(value or "all")
    local changed = setFilter("category", value)
    if value == "decorations" then self:OpenDecorationCatalog() end
    return changed
end

function Service:SetStatus(value)
    return setFilter("status", tostring(value or "missing"))
end

function Service:SetSource(value)
    return setFilter("source", tostring(value or "all"))
end

function Service:SetProfession(value)
    return setFilter("profession", tostring(value or "all"))
end

function Service:SetSearch(value)
    return setFilter("search", tostring(value or ""))
end

local function cycle(options, selected, direction)
    if type(options) ~= "table" or #options == 0 then return "all" end
    local current = 1
    for index, option in ipairs(options) do
        if option.key == selected then current = index; break end
    end
    current = ((current - 1 + (direction < 0 and -1 or 1)) % #options) + 1
    return options[current].key
end

function Service:CycleSource(direction)
    local view = self:GetView()
    if not view then return false end
    return self:SetSource(cycle(view.sourceOptions, uiState().source, tonumber(direction) or 1))
end

function Service:CycleProfession(direction)
    local view = self:GetView()
    if not view then return false end
    return self:SetProfession(cycle(view.professionOptions, uiState().profession, tonumber(direction) or 1))
end

function Service:OpenDecorationCatalog()
    for _, addonName in ipairs({ "Blizzard_HousingDashboard", "Blizzard_HousingCatalog" }) do
        pcall(loadAddon, addonName)
    end
    return self:Refresh()
end

function Service:SetWaypoint(record)
    local entry = record and (record.entry or record)
    local ok, message = Addon.CompendiumLogic:SetWaypoint(entry)
    if ok then message = string.format(Addon.L.COMPENDIUM_WAYPOINT_SET_FORMAT, record.runtime and record.runtime.name or entry.name or "") end
    if message then Addon:Print(message) end
    return ok
end

function Service:OpenAchievement(record)
    local entry = record and (record.entry or record)
    return Addon.CompendiumLogic:OpenAchievement(entry)
end

local bridgeName = Addon.Identity.globalPrefix .. "CompendiumBridge"
_G[bridgeName] = _G[bridgeName] or {}
_G[bridgeName].RegisterCatalog = function(_, catalog)
    return Service:RegisterCatalog(catalog)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collect)
    for _, eventName in ipairs(COLLECTION_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function()
            if Service.opened and Service.prepared then Service:RefreshRuntime(0.15) end
        end)
    end
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Service.opened and Service.prepared then Service:RefreshRuntime(0) end
    end)
    Addon.StateStore:Set(self.id, statePayload(nil))
end

function Module:OnDisable()
    Service:Close()
    Service.runtime = nil
end

Addon.ModuleRegistry:Register(Module)
