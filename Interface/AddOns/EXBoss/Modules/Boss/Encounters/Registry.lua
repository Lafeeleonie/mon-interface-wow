---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.BossEncounters = ExBoss.BossEncounters or {}

local Registry = ExBoss.BossEncounters

Registry.byEncounterID = Registry.byEncounterID or {}
Registry.order = Registry.order or {}

function Registry:Register(def)
    if type(def) ~= "table" then
        return false
    end

    local encounterID = tonumber(def.encounterID)
    if not encounterID then
        return false
    end

    def.encounterID = encounterID
    if not self.byEncounterID[encounterID] then
        self.order[#self.order + 1] = encounterID
    end
    self.byEncounterID[encounterID] = def
    return true
end

function Registry:Get(encounterID)
    return self.byEncounterID[tonumber(encounterID)]
end

function Registry:GetAll()
    return self.byEncounterID
end

