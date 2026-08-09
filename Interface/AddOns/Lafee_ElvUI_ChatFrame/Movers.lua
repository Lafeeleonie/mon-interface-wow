local _, addon = ...
local LECF = addon.LECF
if not LECF then return end

local E = LECF.E
local L = LECF.L

local DEFAULT_POINTS = {
    { "TOPLEFT", E.UIParent, "TOPLEFT", 34, -220 },
    { "TOPRIGHT", E.UIParent, "TOPRIGHT", -34, -220 },
    { "BOTTOMLEFT", E.UIParent, "BOTTOMLEFT", 34, 220 },
    { "BOTTOMRIGHT", E.UIParent, "BOTTOMRIGHT", -34, 220 },
}

function LECF:GetMoverName(index)
    return "LafeeChatFrameMover" .. index
end

function LECF:GetFrameConfig(index)
    return self.db and self.db.frames and self.db.frames[index]
end

function LECF:GetFrameDisplayName(index)
    local config = self:GetFrameConfig(index)
    if config and config.name and config.name ~= "" then
        return config.name
    end
    return string.format(L.FRAME_GENERIC_NAME, index)
end

function LECF:IsSlotActive(index)
    local config = self:GetFrameConfig(index)
    return self.db
        and self.db.enabled
        and index <= self.db.frameCount
        and config
        and config.enabled
end

function LECF:InitializeMovers()
    self.containers = {}
    E:ConfigMode_AddGroup("LAFEE", L.ADDON_NAME)

    for index = 1, self.MAX_FRAMES do
        local container = CreateFrame("Frame", "LafeeChatFrameContainer" .. index, E.UIParent)
        container:SetPoint(unpack(DEFAULT_POINTS[index]))
        container:SetSize(self.MIN_WIDTH, self.MIN_HEIGHT)
        container:SetFrameStrata("BACKGROUND")
        container:EnableMouse(false)
        container:Show()

        self.containers[index] = container

        E:CreateMover(
            container,
            self:GetMoverName(index),
            self:GetFrameDisplayName(index),
            nil,
            nil,
            function()
                LECF:ScheduleApplyAll("MOVER_DRAGGED")
            end,
            "LAFEE",
            function()
                return not LECF:IsSlotActive(index)
            end,
            "lecf,frame" .. index
        )
    end

    self:UpdateAllMovers()
end

function LECF:UpdateMoverLabel(index)
    local holder = E:GetMoverHolder(self:GetMoverName(index))
    local mover = holder and holder.mover
    if not mover then return end

    local name = self:GetFrameDisplayName(index)
    mover.textString = name
    mover.text:SetText(name)
end

function LECF:UpdateMover(index)
    local container = self.containers and self.containers[index]
    local config = self:GetFrameConfig(index)
    if not container or not config then return end

    local width = math.max(self.MIN_WIDTH, math.min(self.MAX_WIDTH, tonumber(config.width) or self.MIN_WIDTH))
    local height = math.max(self.MIN_HEIGHT, math.min(self.MAX_HEIGHT, tonumber(config.height) or self.MIN_HEIGHT))
    config.width = width
    config.height = height
    container:SetSize(width, height)
    self:UpdateMoverLabel(index)

    local moverName = self:GetMoverName(index)
    if self:IsSlotActive(index) then
        if E.DisabledMovers[moverName] then
            E:EnableMover(moverName)
        end
    elseif E.CreatedMovers[moverName] then
        E:DisableMover(moverName)
    end
end

function LECF:UpdateAllMovers()
    for index = 1, self.MAX_FRAMES do
        self:UpdateMover(index)
    end
end

function LECF:ResetMoverPosition(index)
    if InCombatLockdown and InCombatLockdown() then
        self.pendingMoverResets = self.pendingMoverResets or {}
        self.pendingMoverResets[index] = true
        self.pendingCombatUpdate = true
        self:Debug(L.DEBUG_DEFERRED)
        return false
    end

    local moverName = self:GetMoverName(index)
    if E.db.movers then
        E.db.movers[moverName] = nil
    end

    local wasDisabled = E.DisabledMovers[moverName] ~= nil
    if wasDisabled then
        E:EnableMover(moverName)
    end

    E:SetMoverPoints(moverName)

    if wasDisabled then
        E:DisableMover(moverName)
    end

    self:ScheduleApplyAll("RESET_POSITION")
    return true
end

function LECF:ResetAllMoverPositions()
    local completed = true
    for index = 1, self.MAX_FRAMES do
        completed = self:ResetMoverPosition(index) and completed
    end
    if completed then
        self:Print(L.RESET_COMPLETE)
    else
        self.pendingResetMessage = true
    end
end

function LECF:ProcessPendingMoverResets()
    if not self.pendingMoverResets then return end

    local pending = self.pendingMoverResets
    self.pendingMoverResets = nil
    for index in pairs(pending) do
        self:ResetMoverPosition(index)
    end

    if self.pendingResetMessage then
        self.pendingResetMessage = nil
        self:Print(L.RESET_COMPLETE)
    end
end
