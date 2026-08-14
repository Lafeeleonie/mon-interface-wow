local _, Addon = ...

local Module = {
    id = "warband.activityScore",
    defaultEnabled = true,
}

local Service = {}
Addon.ActivityScore = Service

local DEPENDENCY_SLICES = {
    "warband.roster",
    "vault.progress",
    "pve.weekly",
    "pve.events",
    "pve.world",
    "pve.delves",
    "pve.prey",
    "pvp.weekly",
    "systems.professions",
}

local DEPENDENCY_REFRESH_DELAY = 0.01

local function collectScores()
    local scores = {}
    for characterKey, record in pairs(Addon.Database:Get().characters or {}) do
        if type(record) == "table" and type(record.identity) == "table" then
            scores[characterKey] = Addon.ActivityScoreLogic:Build(record)
        end
    end
    return {
        generatedAt = type(time) == "function" and time() or 0,
        scores = scores,
    }
end

function Service:Get(characterKey)
    local state = Addon.StateStore:Get(Module.id)
    return type(state) == "table" and type(state.scores) == "table" and state.scores[characterKey] or nil
end

function Service:GetVaultSummary(characterKey)
    local score = self:Get(characterKey)
    if type(score) == "table" and type(score.vault) == "table" then
        return score.vault
    end
    local record = type(characterKey) == "string" and Addon.Database:Get().characters[characterKey] or nil
    return Addon.ActivityScoreLogic:GetVaultSummary(record)
end

function Service:Refresh()
    Addon.RefreshScheduler:Invalidate(Module.id, 0)
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectScores)
    for _, sliceID in ipairs(DEPENDENCY_SLICES) do
        Addon.StateStore:Subscribe(sliceID, self, function()
            -- Several source slices can change in the same event burst. Keep one
            -- pending score rebuild until WoW reaches the next frame.
            Addon.RefreshScheduler:Invalidate(Module.id, DEPENDENCY_REFRESH_DELAY)
        end)
    end
    Addon.RefreshScheduler:Invalidate(self.id, 0)
end

Addon.ModuleRegistry:Register(Module)
