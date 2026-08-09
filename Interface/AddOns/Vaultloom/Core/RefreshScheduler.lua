local _, Addon = ...

local Scheduler = {
    collectors = {},
    pending = {},
    generations = {},
}

Addon.RefreshScheduler = Scheduler

function Scheduler:Register(domainID, owner, collector)
    if type(domainID) ~= "string" or domainID == "" or owner == nil or type(collector) ~= "function" then
        return false
    end

    self.collectors[domainID] = {
        owner = owner,
        callback = collector,
    }
    return true
end

function Scheduler:Run(domainID)
    self.pending[domainID] = nil
    local collector = self.collectors[domainID]
    if not collector then
        return false
    end

    local ok, result
    if Addon.PerformanceDiagnostics.active == true then
        ok, result = Addon.PerformanceDiagnostics:Call(
            collector.owner,
            "collector",
            domainID,
            "collector." .. domainID,
            collector.callback
        )
    else
        ok, result = Addon:SafeCall("collector." .. domainID, collector.callback)
    end
    if ok and result ~= nil then
        Addon.StateStore:Set(domainID, result)
    end
    return ok
end

function Scheduler:Invalidate(domainID, delaySeconds)
    if not self.collectors[domainID] then
        return false
    end
    if self.pending[domainID] then
        return true
    end

    self.generations[domainID] = (tonumber(self.generations[domainID]) or 0) + 1
    local generation = self.generations[domainID]
    self.pending[domainID] = generation

    local function run()
        if self.pending[domainID] ~= generation then
            return
        end
        self:Run(domainID)
    end

    local delay = math.max(0, tonumber(delaySeconds) or 0)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, run)
    else
        run()
    end
    return true
end

function Scheduler:Cancel(domainID)
    if self.pending[domainID] then
        self.pending[domainID] = nil
        self.generations[domainID] = (tonumber(self.generations[domainID]) or 0) + 1
    end
end

function Scheduler:UnregisterOwner(owner)
    for domainID, collector in pairs(self.collectors) do
        if collector.owner == owner then
            self:Cancel(domainID)
            self.collectors[domainID] = nil
        end
    end
end
