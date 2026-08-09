local _, Addon = ...

local Module = {
    id = "warband.roster",
    defaultEnabled = true,
}

local Service = {}
Addon.WarbandRoster = Service

local VALID_SORT_MODES = {
    name = true,
    level = true,
    itemLevel = true,
    realm = true,
    activityScore = true,
    vault = true,
}

local VALID_CARD_FIELDS = {
    level = true,
    itemLevel = true,
    activityScore = true,
    gold = true,
    realm = true,
    professions = true,
    vault = true,
}

local function characterName(character)
    return string.lower(tostring(character and (character.name or character.key) or ""))
end

local function applyManualOrder(roster, order)
    if type(order) ~= "table" or #order == 0 then
        return roster
    end

    local byKey, seen, ordered = {}, {}, {}
    for _, character in ipairs(roster) do
        byKey[character.key] = character
    end
    for _, key in ipairs(order) do
        if byKey[key] then
            ordered[#ordered + 1] = byKey[key]
            seen[key] = true
        end
    end
    for _, character in ipairs(roster) do
        if not seen[character.key] then
            ordered[#ordered + 1] = character
        end
    end
    return ordered
end

local function sortDefault(a, b)
    if a.isMain ~= b.isMain then
        return a.isMain
    end
    if a.isCurrent ~= b.isCurrent then
        return a.isCurrent
    end
    if (a.lastSeen or 0) ~= (b.lastSeen or 0) then
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end
    if (a.level or 0) ~= (b.level or 0) then
        return (a.level or 0) > (b.level or 0)
    end
    return characterName(a) < characterName(b)
end

local function collectRoster()
    local db = Addon.Database:Get()
    local currentIdentity = Addon.StateStore:Get("character.identity")
    local currentKey = currentIdentity and currentIdentity.key
    local roster = {}

    for characterKey, record in pairs(db.characters) do
        local identity = type(record) == "table" and record.identity or nil
        if type(identity) == "table" then
            roster[#roster + 1] = {
                key = characterKey,
                guid = identity.guid,
                name = identity.name,
                realm = identity.realm,
                className = identity.className,
                classFile = identity.classFile,
                level = math.max(0, tonumber(identity.level) or 0),
                itemLevel = tonumber(identity.itemLevel),
                money = tonumber(identity.money),
                lastSeen = tonumber(identity.lastSeen) or 0,
                isMain = characterKey == db.mainCharacterKey,
                isCurrent = characterKey == currentKey,
            }
        end
    end

    table.sort(roster, sortDefault)
    roster = applyManualOrder(roster, db.ui.sidebarOrder)
    db.ui.sidebarOrder = {}
    for _, character in ipairs(roster) do
        db.ui.sidebarOrder[#db.ui.sidebarOrder + 1] = character.key
    end
    return roster
end

function Service:GetAll()
    return Addon.StateStore:Get(Module.id) or {}
end

function Service:GetSettings()
    return Addon.Database:GetUI().warband
end

function Service:GetRealmOptions()
    local realms, options = {}, {
        { key = "all" },
        { key = "current" },
    }
    for _, character in ipairs(self:GetAll()) do
        local realm = tostring(character.realm or "")
        if realm ~= "" then realms[realm] = true end
    end
    local ordered = {}
    for realm in pairs(realms) do ordered[#ordered + 1] = realm end
    table.sort(ordered, function(a, b) return string.lower(a) < string.lower(b) end)
    for _, realm in ipairs(ordered) do
        options[#options + 1] = { key = "realm:" .. realm, realm = realm }
    end
    return options
end

function Service:SetRealmFilter(filterKey)
    if filterKey ~= "all" and filterKey ~= "current"
        and (type(filterKey) ~= "string" or not filterKey:find("^realm:.+"))
    then
        return false
    end
    self:GetSettings().realmFilter = filterKey
    return true
end

function Service:CycleRealmFilter()
    local settings = self:GetSettings()
    local options = self:GetRealmOptions()
    local index = 1
    for optionIndex, option in ipairs(options) do
        if option.key == settings.realmFilter then
            index = optionIndex
            break
        end
    end
    local nextOption = options[(index % #options) + 1]
    settings.realmFilter = nextOption.key
    return nextOption
end

function Service:SetCardStyle(styleKey)
    if styleKey ~= "compact" and styleKey ~= "expanded" then
        return false
    end
    self:GetSettings().cardStyle = styleKey
    return true
end

function Service:SetCardField(fieldKey, visible)
    if not VALID_CARD_FIELDS[fieldKey] then
        return false
    end
    self:GetSettings().fields[fieldKey] = visible == true
    if fieldKey == "activityScore" and visible ~= true
        and Addon.Database:GetUI().sidebarSortMode == "activityScore"
    then
        Addon.Database:GetUI().sidebarSortMode = nil
    end
    return true
end

function Service:GetCurrentKey()
    local identity = Addon.StateStore:Get("character.identity")
    return identity and identity.key or Addon.WoWApi:GetCurrentCharacterIdentity().key
end

function Service:IsCurrent(characterKey)
    return type(characterKey) == "string" and characterKey == self:GetCurrentKey()
end

function Service:IsHidden(characterKey)
    local hidden = Addon.Database:Get().hiddenCharacters
    return type(hidden) == "table" and hidden[characterKey] == true and not self:IsCurrent(characterKey)
end

function Service:CanHide(characterKey)
    return type(characterKey) == "string" and characterKey ~= "" and not self:IsCurrent(characterKey)
end

function Service:GetHiddenCount()
    local count = 0
    for key, hidden in pairs(Addon.Database:Get().hiddenCharacters) do
        if hidden == true and not self:IsCurrent(key) then
            count = count + 1
        end
    end
    return count
end

function Service:GetVisibleRoster(sortMode)
    local visible = {}
    local settings = self:GetSettings()
    local realmFilter = settings.realmFilter
    local targetRealm
    if realmFilter == "current" then
        local identity = Addon.StateStore:Get("character.identity")
        targetRealm = identity and identity.realm
    elseif type(realmFilter) == "string" then
        targetRealm = realmFilter:match("^realm:(.+)")
    end
    for _, character in ipairs(self:GetAll()) do
        if not self:IsHidden(character.key)
            and (not targetRealm or character.realm == targetRealm)
        then
            visible[#visible + 1] = character
        end
    end

    sortMode = sortMode or Addon.Database:GetUI().sidebarSortMode
    if not VALID_SORT_MODES[sortMode] then
        return visible
    end

    table.sort(visible, function(a, b)
        if sortMode == "name" then
            local left, right = characterName(a), characterName(b)
            if left ~= right then
                return left < right
            end
        elseif sortMode == "level" and a.level ~= b.level then
            return a.level > b.level
        elseif sortMode == "itemLevel" then
            local left, right = tonumber(a.itemLevel) or 0, tonumber(b.itemLevel) or 0
            if left ~= right then
                return left > right
            end
        elseif sortMode == "realm" then
            local left, right = string.lower(tostring(a.realm or "")), string.lower(tostring(b.realm or ""))
            if left ~= right then
                return left < right
            end
        elseif sortMode == "activityScore" then
            local leftScore = Addon.ActivityScore and Addon.ActivityScore:Get(a.key)
            local rightScore = Addon.ActivityScore and Addon.ActivityScore:Get(b.key)
            local left, right = tonumber(leftScore and leftScore.score) or 0, tonumber(rightScore and rightScore.score) or 0
            if left ~= right then
                return left > right
            end
        elseif sortMode == "vault" then
            local leftSummary = Addon.ActivityScore and Addon.ActivityScore:GetVaultSummary(a.key)
            local rightSummary = Addon.ActivityScore and Addon.ActivityScore:GetVaultSummary(b.key)
            local left, right = tonumber(leftSummary and leftSummary.ratio) or 0, tonumber(rightSummary and rightSummary.ratio) or 0
            if left ~= right then
                return left > right
            end
        end

        local left, right = characterName(a), characterName(b)
        if left ~= right then
            return left < right
        end
        return tostring(a.realm or "") < tostring(b.realm or "")
    end)
    return visible
end

function Service:GetSelected()
    local db = Addon.Database:Get()
    local selectedKey = db.ui.selectedCharacterKey
    for _, character in ipairs(self:GetAll()) do
        if character.key == selectedKey and not self:IsHidden(character.key) then
            return character
        end
    end

    local currentKey = self:GetCurrentKey()
    for _, character in ipairs(self:GetVisibleRoster()) do
        if character.key == currentKey then
            db.ui.selectedCharacterKey = currentKey
            return character
        end
    end

    local fallback = self:GetVisibleRoster()[1]
    db.ui.selectedCharacterKey = fallback and fallback.key or nil
    return fallback
end

function Service:Select(characterKey)
    if type(characterKey) ~= "string" or characterKey == "" or self:IsHidden(characterKey) then
        return false
    end
    if type(Addon.Database:Get().characters[characterKey]) ~= "table" then
        return false
    end

    Addon.Database:GetUI().selectedCharacterKey = characterKey
    Addon.StateStore:Set("warband.selection", self:GetSelected())
    return true
end

function Service:SetMain(characterKey)
    if type(characterKey) ~= "string" or type(Addon.Database:Get().characters[characterKey]) ~= "table" then
        return false
    end
    Addon.Database:Get().mainCharacterKey = characterKey
    Addon.RefreshScheduler:Run(Module.id)
    return true
end

function Service:SetHidden(characterKey, hidden)
    if type(characterKey) ~= "string" or characterKey == "" then
        return false
    end
    if hidden == true and not self:CanHide(characterKey) then
        return false, "current"
    end

    local db = Addon.Database:Get()
    db.hiddenCharacters[characterKey] = hidden == true and true or nil
    if hidden == true and db.ui.selectedCharacterKey == characterKey then
        db.ui.selectedCharacterKey = self:GetCurrentKey()
    end
    Addon.StateStore:Set("warband.selection", self:GetSelected())
    return true
end

function Service:ClearHidden()
    Addon.Database:Get().hiddenCharacters = {}
    Addon.StateStore:Set("warband.selection", self:GetSelected())
end

function Service:Delete(characterKey)
    if type(characterKey) ~= "string" or characterKey == "" then
        return false, "invalid"
    end
    if self:IsCurrent(characterKey) then
        return false, "current"
    end
    local db = Addon.Database:Get()
    if type(db.characters[characterKey]) ~= "table" then
        return false, "missing"
    end

    db.characters[characterKey] = nil
    db.hiddenCharacters[characterKey] = nil
    if type(db.raidLootTracker) == "table" then db.raidLootTracker[characterKey] = nil end
    if type(db.journalLootCatalog) == "table" then db.journalLootCatalog[characterKey] = nil end
    if type(db.focus) == "table" and type(db.focus.characters) == "table" then
        db.focus.characters[characterKey] = nil
    end
    if db.mainCharacterKey == characterKey then db.mainCharacterKey = self:GetCurrentKey() end
    if db.ui.selectedCharacterKey == characterKey then db.ui.selectedCharacterKey = self:GetCurrentKey() end
    for index = #db.ui.sidebarOrder, 1, -1 do
        if db.ui.sidebarOrder[index] == characterKey then table.remove(db.ui.sidebarOrder, index) end
    end
    Addon.RefreshScheduler:Run(Module.id)
    if Addon.ActivityScore then Addon.ActivityScore:Refresh() end
    return true
end

function Service:SetSortMode(sortMode)
    if sortMode ~= nil and not VALID_SORT_MODES[sortMode] then
        return false
    end
    Addon.Database:GetUI().sidebarSortMode = sortMode
    return true
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectRoster)
    Addon.StateStore:Subscribe("character.identity", self, function()
        Addon.RefreshScheduler:Invalidate(Module.id, 0)
    end)
    Addon.StateStore:Subscribe(Module.id, self, function()
        Addon.StateStore:Set("warband.selection", Service:GetSelected())
    end)
    Addon.RefreshScheduler:Invalidate(self.id, 0)
end

Addon.ModuleRegistry:Register(Module)
