local _, Addon = ...

local Module = {
    id = "focus.tasks",
    defaultEnabled = true,
}

local Service = {}
Addon.Focus = Service

local SOURCE_SLICES = {
    "vault.progress",
    "pve.weekly",
    "pve.coiled_isle",
    "pve.void_invasion",
    "pve.daily",
    "pve.events",
    "pve.world",
    "pve.delves",
    "pve.prey",
    "pvp.weekly",
    "systems.professions",
    "character.identity",
    "warband.selection",
}

local function ensureDB()
    local root = Addon.Database:Get()
    root.focus = type(root.focus) == "table" and root.focus or {}
    local db = root.focus
    db.global = Addon.FocusLogic:NormalizeStore(db.global)
    db.characters = type(db.characters) == "table" and db.characters or {}
    db.meta = type(db.meta) == "table" and db.meta or {}
    db.tracker = Addon.FocusLogic:NormalizeTracker(db.tracker)
    for characterKey, store in pairs(db.characters) do
        if type(characterKey) ~= "string" or characterKey == "" or type(store) ~= "table" then
            db.characters[characterKey] = nil
        else
            db.characters[characterKey] = Addon.FocusLogic:NormalizeStore(store)
            db.characters[characterKey].useGlobal = db.characters[characterKey].useGlobal == true
        end
    end
    return db
end

local function resolveCharacterKey(characterKey, current)
    if type(characterKey) == "table" then characterKey = characterKey.key end
    if type(characterKey) == "string" and characterKey ~= "" then return characterKey end
    if current then return Addon.WarbandRoster:GetCurrentKey() end
    local selected = Addon.WarbandRoster:GetSelected()
    return selected and selected.key or Addon.WarbandRoster:GetCurrentKey()
end

local function characterStore(characterKey, create)
    local db = ensureDB()
    characterKey = resolveCharacterKey(characterKey)
    if not characterKey then return nil end
    if type(db.characters[characterKey]) ~= "table" then
        if not create then return nil end
        db.characters[characterKey] = Addon.FocusLogic:NormalizeStore({})
    end
    local store = Addon.FocusLogic:NormalizeStore(db.characters[characterKey])
    store.useGlobal = store.useGlobal == true
    db.characters[characterKey] = store
    return store
end

local function activeStore(characterKey, create)
    local db = ensureDB()
    local store = characterStore(characterKey, create)
    if store and store.useGlobal then return db.global, "global" end
    return store, "character"
end

local function removeFromOrder(order, taskID)
    for index = #order, 1, -1 do
        if order[index] == taskID then table.remove(order, index) end
    end
end

function Service:GetSettings()
    return ensureDB().tracker
end

function Service:IsUsingGlobal(characterKey)
    local store = characterStore(characterKey, true)
    return store and store.useGlobal == true or false
end

function Service:GetScope(characterKey)
    local _, scope = activeStore(characterKey, true)
    return scope
end

function Service:GetTaskIDs(characterKey)
    local store = activeStore(characterKey, false)
    return Addon.FocusLogic:GetTaskIDs(store)
end

function Service:IsSelected(taskID, characterKey)
    local store = activeStore(characterKey, false)
    return store and store.items[tostring(taskID or "")] == true or false
end

function Service:GetCatalog(characterKey)
    return Addon.FocusLogic:BuildCatalog(resolveCharacterKey(characterKey))
end

function Service:GetView(characterKey)
    characterKey = resolveCharacterKey(characterKey)
    local store = activeStore(characterKey, false)
    return Addon.FocusLogic:BuildView(characterKey, store, ensureDB().meta)
end

function Service:GetCurrentView()
    return self:GetView(resolveCharacterKey(nil, true))
end

function Service:Publish()
    local selectedKey = resolveCharacterKey()
    local state = {
        selectedCharacterKey = selectedKey,
        view = self:GetView(selectedKey),
        currentView = self:GetCurrentView(),
        tracker = self:GetSettings(),
    }
    Addon.StateStore:Set(Module.id, state)
    if Addon.FocusTracker and type(Addon.FocusTracker.Refresh) == "function" then
        Addon.FocusTracker:Refresh(state.currentView, state.tracker)
    end
    return state
end

function Service:SetUseGlobal(characterKey, useGlobal)
    local store = characterStore(characterKey, true)
    if not store then return false end
    store.useGlobal = useGlobal == true
    self:Publish()
    return true
end

function Service:SetSelected(taskID, selected, characterKey, metadata)
    taskID = tostring(taskID or "")
    if taskID == "" then return false end
    characterKey = resolveCharacterKey(characterKey)
    local store = activeStore(characterKey, true)
    if not store then return false end
    if selected == true then
        if store.items[taskID] ~= true then store.order[#store.order + 1] = taskID end
        store.items[taskID] = true
        if type(metadata) ~= "table" then metadata = self:GetCatalog(characterKey).index[taskID] end
        if type(metadata) == "table" then
            ensureDB().meta[taskID] = {
                label = metadata.label,
                groupLabel = metadata.groupLabel,
            }
        end
    else
        store.items[taskID] = nil
        removeFromOrder(store.order, taskID)
    end
    Addon.FocusLogic:NormalizeStore(store)
    self:Publish()
    return true
end

function Service:Move(taskID, direction, characterKey)
    taskID = tostring(taskID or "")
    direction = tonumber(direction) or 0
    if taskID == "" or direction == 0 then return false end
    local store = activeStore(resolveCharacterKey(characterKey), true)
    if not store then return false end
    Addon.FocusLogic:NormalizeStore(store)
    local current
    for index, value in ipairs(store.order) do
        if value == taskID then current = index; break end
    end
    if not current then return false end
    local target = current + (direction < 0 and -1 or 1)
    if target < 1 or target > #store.order then return false end
    store.order[current], store.order[target] = store.order[target], store.order[current]
    self:Publish()
    return true
end

function Service:CopyGlobalToCharacter(characterKey)
    local db = ensureDB()
    local store = characterStore(characterKey, true)
    if not store then return false end
    Addon.FocusLogic:CopyStore(db.global, store)
    store.useGlobal = false
    self:Publish()
    return true
end

function Service:SaveCharacterAsGlobal(characterKey)
    local db = ensureDB()
    local store = characterStore(characterKey, true)
    if not store then return false end
    Addon.FocusLogic:CopyStore(store, db.global)
    self:Publish()
    return true
end

function Service:SetTrackerShown(shown)
    self:GetSettings().shown = shown == true
    self:Publish()
end

function Service:SetTrackerLocked(locked)
    self:GetSettings().locked = locked == true
    self:Publish()
end

function Service:CycleTrackerStyle()
    local settings = self:GetSettings()
    settings.styleKey = settings.styleKey == "frame" and "rows"
        or settings.styleKey == "rows" and "text"
        or "frame"
    settings.background = settings.styleKey == "frame"
    self:Publish()
end

function Service:CycleTrackerFont()
    local settings = self:GetSettings()
    settings.fontKey = settings.fontKey == "normal" and "compact"
        or settings.fontKey == "compact" and "large"
        or "normal"
    self:Publish()
end

function Service:SetTrackerScalePercent(value)
    self:GetSettings().scalePercent = math.max(70, math.min(140, math.floor(tonumber(value) or 100)))
    self:Publish()
end

function Service:SetTrackerOpacityPercent(value)
    self:GetSettings().opacityPercent = math.max(35, math.min(100, math.floor(tonumber(value) or 90)))
    self:Publish()
end

function Service:SetTrackerPosition(point, relativePoint, x, y)
    self:GetSettings().point = {
        point = type(point) == "string" and point or "CENTER",
        relativePoint = type(relativePoint) == "string" and relativePoint or "CENTER",
        x = tonumber(x) or 360,
        y = tonumber(y) or 0,
    }
end

function Module:OnEnable()
    ensureDB()
    for _, sliceID in ipairs(SOURCE_SLICES) do
        Addon.StateStore:Subscribe(sliceID, self, function()
            Service:Publish()
        end)
    end
    Service:Publish()
end

function Module:OnDisable()
    if Addon.FocusTracker and Addon.FocusTracker.frame then
        Addon.FocusTracker.frame:Hide()
    end
end

Addon.ModuleRegistry:Register(Module)
