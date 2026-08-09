local _, Addon = ...

local Diagnostics = {
    active = false,
    reason = nil,
    startedAt = nil,
    stoppedAt = nil,
    records = {},
    ownerCache = {},
    stack = {},
}

Addon.PerformanceDiagnostics = Diagnostics

local function profileClock()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    if type(GetTimePreciseSec) == "function" then
        return GetTimePreciseSec() * 1000
    end
    if type(GetTime) == "function" then
        return GetTime() * 1000
    end
    return 0
end

local function luaMemoryKB()
    if type(collectgarbage) ~= "function" then
        return nil
    end
    local ok, value = pcall(collectgarbage, "count")
    if ok then
        return tonumber(value)
    end
    return nil
end

local function hasNativeCallProfiler()
    return type(C_AddOnProfiler) == "table"
        and type(C_AddOnProfiler.MeasureCall) == "function"
end

local function resolveText(value)
    if type(value) == "function" then
        local ok, result = pcall(value)
        return ok and tostring(result or "") or ""
    end
    return tostring(value or "")
end

local function displayName(kind, id, title)
    title = tostring(title or "")
    if title == "" or title == id then
        return string.format("%s: %s", kind, id)
    end
    return string.format("%s: %s", kind, title)
end

function Diagnostics:ResolveOwner(owner)
    if owner == nil then
        return "core.unknown", "Core: unknown", "core"
    end

    local cached = self.ownerCache[owner]
    if cached then
        return cached.id, cached.label, cached.kind
    end

    local featureRegistry = Addon.FeatureRegistry
    if featureRegistry and type(featureRegistry.runtimes) == "table" then
        for featureID, runtime in pairs(featureRegistry.runtimes) do
            if runtime == owner then
                local definition = featureRegistry.definitions
                    and featureRegistry.definitions[featureID]
                local title = definition and resolveText(definition.title) or featureID
                cached = {
                    id = "feature." .. featureID,
                    label = displayName("Feature", featureID, title),
                    kind = "feature",
                }
                break
            end
        end
    end

    local moduleRegistry = Addon.ModuleRegistry
    if not cached and moduleRegistry and type(moduleRegistry.definitions) == "table" then
        for moduleID, definition in pairs(moduleRegistry.definitions) do
            if definition == owner then
                cached = {
                    id = "module." .. moduleID,
                    label = displayName("Module", moduleID, moduleID),
                    kind = "module",
                }
                break
            end
        end
    end

    local screenRegistry = Addon.ScreenRegistry
    if not cached and screenRegistry then
        for screenID, definition in pairs(screenRegistry.definitions or {}) do
            if definition == owner then
                local title = resolveText(definition.label)
                cached = {
                    id = "screen." .. screenID,
                    label = displayName("Screen", screenID, title),
                    kind = "screen",
                }
                break
            end
        end
        for screenID, instance in pairs(screenRegistry.instances or {}) do
            if not cached and instance == owner then
                local definition = screenRegistry.definitions
                    and screenRegistry.definitions[screenID]
                local title = definition and resolveText(definition.label) or screenID
                cached = {
                    id = "screen." .. screenID,
                    label = displayName("Screen", screenID, title),
                    kind = "screen",
                }
                break
            end
        end
    end

    if not cached and type(owner) == "table" and type(owner.id) == "string" then
        cached = {
            id = "owner." .. owner.id,
            label = displayName("Core", owner.id, owner.id),
            kind = "core",
        }
    end

    if not cached then
        for key, value in pairs(Addon) do
            if value == owner and type(key) == "string" then
                cached = {
                    id = "core." .. key,
                    label = displayName("Core", key, key),
                    kind = "core",
                }
                break
            end
        end
    end

    if not cached then
        cached = {
            id = "core." .. tostring(owner),
            label = "Core: " .. tostring(owner),
            kind = "core",
        }
    end
    self.ownerCache[owner] = cached
    return cached.id, cached.label, cached.kind
end

function Diagnostics:EnsureRecord(owner)
    local id, label, kind = self:ResolveOwner(owner)
    local record = self.records[id]
    if not record then
        record = {
            id = id,
            label = label,
            kind = kind,
            calls = 0,
            totalMs = 0,
            peakMs = 0,
            allocatedKB = 0,
            deallocatedKB = 0,
            luaDeltaKB = 0,
            luaPositiveKB = 0,
            details = {},
        }
        self.records[id] = record
    else
        record.label = label
        record.kind = kind
    end
    return record
end

function Diagnostics:SeedOwners()
    local featureRegistry = Addon.FeatureRegistry
    if featureRegistry then
        for featureID, runtime in pairs(featureRegistry.runtimes or {}) do
            if featureRegistry.enabled and featureRegistry.enabled[featureID] == true then
                self:EnsureRecord(runtime)
            end
        end
    end

    local moduleRegistry = Addon.ModuleRegistry
    if moduleRegistry then
        for moduleID, definition in pairs(moduleRegistry.definitions or {}) do
            if moduleRegistry.enabled and moduleRegistry.enabled[moduleID] == true then
                self:EnsureRecord(definition)
            end
        end
    end

    local screenRegistry = Addon.ScreenRegistry
    if screenRegistry then
        for _, instance in pairs(screenRegistry.instances or {}) do
            self:EnsureRecord(instance)
        end
    end
end

function Diagnostics:Reset()
    for key in pairs(self.records) do
        self.records[key] = nil
    end
    for index = #self.stack, 1, -1 do
        self.stack[index] = nil
    end
    self.startedAt = self.active and profileClock() or nil
    self.stoppedAt = nil
    self:SeedOwners()
end

function Diagnostics:Start(reason)
    self.active = true
    self.reason = tostring(reason or "manual")
    self.startedAt = profileClock()
    self.stoppedAt = nil
    self:Reset()
    return true
end

function Diagnostics:Stop()
    if not self.active then
        return false
    end
    self.stoppedAt = profileClock()
    self.active = false
    for index = #self.stack, 1, -1 do
        self.stack[index] = nil
    end
    return true
end

function Diagnostics:IsActive()
    return self.active == true
end

function Diagnostics:Begin(owner, category, detail)
    if not self.active then
        return nil
    end

    local record = self:EnsureRecord(owner)
    local detailKey = string.format("%s: %s", tostring(category or "work"), tostring(detail or "unknown"))
    local token = {
        record = record,
        detailKey = detailKey,
        startedAt = profileClock(),
        childMs = 0,
        childAllocatedKB = 0,
        childDeallocatedKB = 0,
        depth = #self.stack + 1,
    }
    if token.depth == 1 and not hasNativeCallProfiler() then
        token.luaStartedKB = luaMemoryKB()
    end
    self.stack[token.depth] = token
    return token
end

function Diagnostics:Finish(token, nativeResult)
    if type(token) ~= "table" or type(token.record) ~= "table" then
        return
    end

    local elapsedMs = type(nativeResult) == "table"
        and tonumber(nativeResult.elapsedMilliseconds)
        or nil
    elapsedMs = math.max(0, elapsedMs or (profileClock() - (tonumber(token.startedAt) or 0)))
    local exclusiveMs = math.max(0, elapsedMs - (tonumber(token.childMs) or 0))
    local allocatedKB = type(nativeResult) == "table"
        and ((tonumber(nativeResult.allocatedBytes) or 0) / 1024)
        or 0
    local deallocatedKB = type(nativeResult) == "table"
        and ((tonumber(nativeResult.deallocatedBytes) or 0) / 1024)
        or 0
    local exclusiveAllocatedKB = math.max(
        0,
        allocatedKB - (tonumber(token.childAllocatedKB) or 0)
    )
    local exclusiveDeallocatedKB = math.max(
        0,
        deallocatedKB - (tonumber(token.childDeallocatedKB) or 0)
    )
    local record = token.record
    record.calls = record.calls + 1
    record.totalMs = record.totalMs + exclusiveMs
    record.peakMs = math.max(record.peakMs, exclusiveMs)
    record.allocatedKB = record.allocatedKB + exclusiveAllocatedKB
    record.deallocatedKB = record.deallocatedKB + exclusiveDeallocatedKB
    if type(nativeResult) == "table" then
        record.luaDeltaKB = record.luaDeltaKB
            + exclusiveAllocatedKB - exclusiveDeallocatedKB
        record.luaPositiveKB = record.luaPositiveKB + exclusiveAllocatedKB
    end

    local detail = record.details[token.detailKey]
    if not detail then
        detail = {
            key = token.detailKey,
            calls = 0,
            totalMs = 0,
            peakMs = 0,
            allocatedKB = 0,
            deallocatedKB = 0,
        }
        record.details[token.detailKey] = detail
    end
    detail.calls = detail.calls + 1
    detail.totalMs = detail.totalMs + exclusiveMs
    detail.peakMs = math.max(detail.peakMs, exclusiveMs)
    detail.allocatedKB = detail.allocatedKB + exclusiveAllocatedKB
    detail.deallocatedKB = detail.deallocatedKB + exclusiveDeallocatedKB

    if type(nativeResult) ~= "table" and token.depth == 1 and token.luaStartedKB ~= nil then
        local finishedKB = luaMemoryKB()
        if finishedKB ~= nil then
            local deltaKB = finishedKB - token.luaStartedKB
            record.luaDeltaKB = record.luaDeltaKB + deltaKB
            if deltaKB > 0 then
                record.luaPositiveKB = record.luaPositiveKB + deltaKB
            end
        end
    end

    self.stack[token.depth] = nil
    local parent = self.stack[token.depth - 1]
    if parent then
        parent.childMs = (tonumber(parent.childMs) or 0) + elapsedMs
        parent.childAllocatedKB = (tonumber(parent.childAllocatedKB) or 0) + allocatedKB
        parent.childDeallocatedKB = (tonumber(parent.childDeallocatedKB) or 0) + deallocatedKB
    end
end

function Diagnostics:Call(owner, category, detail, scope, callback, ...)
    if not self.active then
        return Addon:SafeCall(scope, callback, ...)
    end

    local token = self:Begin(owner, category, detail)
    if hasNativeCallProfiler() then
        local function protectedCallback(...)
            return Addon:SafeCall(scope, callback, ...)
        end
        local apiOK, nativeResult, ok, first, second, third, fourth = pcall(
            C_AddOnProfiler.MeasureCall,
            protectedCallback,
            ...
        )
        if apiOK and type(nativeResult) == "table" then
            self:Finish(token, nativeResult)
            return ok, first, second, third, fourth
        end
    end
    local ok, first, second, third, fourth = Addon:SafeCall(scope, callback, ...)
    self:Finish(token)
    return ok, first, second, third, fourth
end

function Diagnostics:Wrap(owner, category, detail, callback)
    if not self.active or type(callback) ~= "function" then
        return callback
    end
    local scope = string.format(
        "diagnostics.%s.%s",
        tostring(category or "work"),
        tostring(detail or "unknown")
    )
    return function(...)
        local _, first, second, third, fourth = Diagnostics:Call(
            owner,
            category,
            detail,
            scope,
            callback,
            ...
        )
        return first, second, third, fourth
    end
end

function Diagnostics:GetAddonCPUMetrics()
    if type(C_AddOnProfiler) ~= "table"
        or type(C_AddOnProfiler.GetAddOnMetric) ~= "function"
        or type(Enum) ~= "table"
        or type(Enum.AddOnProfilerMetric) ~= "table"
    then
        return nil
    end

    local metrics = {}
    for key, enumKey in pairs({
        session = "SessionAverageTime",
        recent = "RecentAverageTime",
        peak = "PeakTime",
    }) do
        local metric = Enum.AddOnProfilerMetric[enumKey]
        if metric ~= nil then
            local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, Addon.name, metric)
            if ok then
                metrics[key] = tonumber(value)
            end
        end
    end
    return next(metrics) and metrics or nil
end

function Diagnostics:GetAddonMemoryKB(refresh)
    if refresh == true and type(UpdateAddOnMemoryUsage) == "function" then
        pcall(UpdateAddOnMemoryUsage)
    end
    if type(GetAddOnMemoryUsage) == "function" then
        local ok, value = pcall(GetAddOnMemoryUsage, Addon.name)
        if ok then
            return tonumber(value)
        end
    end
    return nil
end

function Diagnostics:GetDurationMs()
    if not self.startedAt then
        return 0
    end
    local finishedAt = self.active and profileClock() or self.stoppedAt or self.startedAt
    return math.max(0, finishedAt - self.startedAt)
end

function Diagnostics:GetSnapshot(refreshMemory)
    self:SeedOwners()
    local rows = {}
    local trackedMs = 0
    for _, record in pairs(self.records) do
        local hottest
        local details = {}
        for _, detail in pairs(record.details) do
            details[#details + 1] = {
                key = detail.key,
                calls = detail.calls,
                totalMs = detail.totalMs,
                peakMs = detail.peakMs,
                allocatedKB = detail.allocatedKB,
                deallocatedKB = detail.deallocatedKB,
            }
            if not hottest
                or detail.totalMs > hottest.totalMs
                or (detail.totalMs == hottest.totalMs and detail.calls > hottest.calls)
            then
                hottest = detail
            end
        end
        table.sort(details, function(left, right)
            if left.totalMs ~= right.totalMs then
                return left.totalMs > right.totalMs
            end
            return left.calls > right.calls
        end)
        trackedMs = trackedMs + record.totalMs
        rows[#rows + 1] = {
            id = record.id,
            label = record.label,
            kind = record.kind,
            calls = record.calls,
            totalMs = record.totalMs,
            averageMs = record.calls > 0 and (record.totalMs / record.calls) or 0,
            peakMs = record.peakMs,
            allocatedKB = record.allocatedKB,
            deallocatedKB = record.deallocatedKB,
            luaDeltaKB = record.luaDeltaKB,
            luaPositiveKB = record.luaPositiveKB,
            hottest = hottest and hottest.key or "-",
            hottestMs = hottest and hottest.totalMs or 0,
            details = details,
        }
    end
    table.sort(rows, function(left, right)
        if left.totalMs ~= right.totalMs then
            return left.totalMs > right.totalMs
        end
        if left.calls ~= right.calls then
            return left.calls > right.calls
        end
        return left.label < right.label
    end)
    local enabledFeatures, totalFeatures = 0, 0
    if Addon.FeatureRegistry and type(Addon.FeatureRegistry.GetStats) == "function" then
        enabledFeatures, totalFeatures = Addon.FeatureRegistry:GetStats()
    end
    local enabledModules, totalModules = 0, 0
    if Addon.ModuleRegistry and type(Addon.ModuleRegistry.GetStats) == "function" then
        enabledModules, totalModules = Addon.ModuleRegistry:GetStats()
    end
    local createdScreens = 0
    if Addon.ScreenRegistry and type(Addon.ScreenRegistry.GetCreatedCount) == "function" then
        createdScreens = Addon.ScreenRegistry:GetCreatedCount()
    end

    return {
        active = self.active == true,
        armed = self:IsArmedForReload(),
        reason = self.reason,
        durationMs = self:GetDurationMs(),
        trackedMs = trackedMs,
        memoryKB = self:GetAddonMemoryKB(refreshMemory == true),
        addonCPU = self:GetAddonCPUMetrics(),
        nativeCallProfiler = hasNativeCallProfiler(),
        coverage = {
            enabledFeatures = tonumber(enabledFeatures) or 0,
            totalFeatures = tonumber(totalFeatures) or 0,
            enabledModules = tonumber(enabledModules) or 0,
            totalModules = tonumber(totalModules) or 0,
            createdScreens = tonumber(createdScreens) or 0,
        },
        rows = rows,
    }
end

function Diagnostics:GetSettings()
    if not Addon.Database or type(Addon.Database.Get) ~= "function" then
        return nil
    end
    local db = Addon.Database:Get()
    if type(db) ~= "table" then
        return nil
    end
    db.performanceDiagnostics = type(db.performanceDiagnostics) == "table"
        and db.performanceDiagnostics or {}
    return db.performanceDiagnostics
end

function Diagnostics:ArmForReload(armed)
    local settings = self:GetSettings()
    if not settings then
        return false
    end
    settings.armOnReload = armed == true
    return true
end

function Diagnostics:IsArmedForReload()
    local settings = self:GetSettings()
    return settings ~= nil and settings.armOnReload == true
end

function Diagnostics:ConsumeReloadArm()
    local settings = self:GetSettings()
    if not settings or settings.armOnReload ~= true then
        return false
    end
    settings.armOnReload = false
    return true
end
