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

local ANCHOR_POINTS = {
    "TOPLEFT",
    "TOP",
    "TOPRIGHT",
    "LEFT",
    "CENTER",
    "RIGHT",
    "BOTTOMLEFT",
    "BOTTOM",
    "BOTTOMRIGHT",
}
LECF.ANCHOR_POINTS = ANCHOR_POINTS

local POINT_FACTORS = {
    TOPLEFT = { 0, 1 },
    TOP = { 0.5, 1 },
    TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}

local function GetAnchorCoordinates(frame, point)
    local factor = POINT_FACTORS[point]
    if not frame or not factor or not frame.GetRect then return end

    local left, bottom, width, height = frame:GetRect()
    if not left or not bottom or not width or not height then return end

    return left + (width * factor[1]), bottom + (height * factor[2])
end

local function GetSavedMoverAnchor(moverName)
    local setting = E.db and E.db.movers and E.db.movers[moverName]
    if type(setting) ~= "string" then return end

    local delimiter = string.find(setting, "\031", 1, true) and "\031" or ","
    local point, targetName, relativePoint, xOffset, yOffset = strsplit(delimiter, setting)
    if not point or not targetName or not relativePoint then return end

    return point, targetName, relativePoint, tonumber(xOffset) or 0, tonumber(yOffset) or 0
end

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

function LECF:GetAnchorPointValues()
    return {
        TOPLEFT = L.POINT_TOPLEFT,
        TOP = L.POINT_TOP,
        TOPRIGHT = L.POINT_TOPRIGHT,
        LEFT = L.POINT_LEFT,
        CENTER = L.POINT_CENTER,
        RIGHT = L.POINT_RIGHT,
        BOTTOMLEFT = L.POINT_BOTTOMLEFT,
        BOTTOM = L.POINT_BOTTOM,
        BOTTOMRIGHT = L.POINT_BOTTOMRIGHT,
    }
end

function LECF:GetAnchorTargetValues(index)
    local ownName = self:GetMoverName(index)
    local values = { UIParent = L.SCREEN }

    local function AddMovers(collection)
        for name, holder in pairs(collection) do
            local mover = holder and holder.mover
            if name ~= ownName and mover and _G[name] then
                values[name] = mover.textString or name
            end
        end
    end

    AddMovers(E.CreatedMovers)
    AddMovers(E.DisabledMovers)
    return values
end

function LECF:GetAnchorTargetOrder(index)
    local values = self:GetAnchorTargetValues(index)
    local order = { "UIParent" }
    local movers = {}

    for name in pairs(values) do
        if name ~= "UIParent" then
            movers[#movers + 1] = name
        end
    end

    table.sort(movers, function(a, b)
        return string.lower(values[a]) < string.lower(values[b])
    end)
    for _, name in ipairs(movers) do
        order[#order + 1] = name
    end
    return order
end

function LECF:GetMoverAnchor(index)
    local moverName = self:GetMoverName(index)
    local point, targetName, relativePoint, xOffset, yOffset = GetSavedMoverAnchor(moverName)
    if point then
        return point, targetName, relativePoint, xOffset, yOffset
    end

    local holder = E:GetMoverHolder(moverName)
    local mover = holder and holder.mover
    if not mover then
        return "CENTER", "UIParent", "CENTER", 0, 0
    end

    local actualPoint, relativeTo, actualRelativePoint, actualXOffset, actualYOffset = mover:GetPoint()
    local actualTargetName = relativeTo and relativeTo.GetName and relativeTo:GetName()
    return actualPoint or "CENTER", actualTargetName or "UIParent", actualRelativePoint or actualPoint or "CENTER", actualXOffset or 0, actualYOffset or 0
end

function LECF:WouldCreateAnchorCycle(index, targetName)
    local ownName = self:GetMoverName(index)
    local visited = {}
    local current = targetName

    while current and current ~= "UIParent" and not visited[current] do
        if current == ownName then
            return true
        end

        visited[current] = true
        local holder = E:GetMoverHolder(current)
        local mover = holder and holder.mover
        local _, relativeTo = mover and mover:GetPoint()
        current = relativeTo and relativeTo.GetName and relativeTo:GetName()
    end

    return false
end

function LECF:SetMoverAnchor(index, changedField, value)
    local point, targetName, relativePoint, xOffset, yOffset = self:GetMoverAnchor(index)
    local moverName = self:GetMoverName(index)
    local holder = E:GetMoverHolder(moverName)
    local mover = holder and holder.mover
    if not mover then return end

    if changedField == "point" then
        point = value
    elseif changedField == "target" then
        targetName = value
    elseif changedField == "relativePoint" then
        relativePoint = value
    elseif changedField == "xOffset" then
        xOffset = value
    elseif changedField == "yOffset" then
        yOffset = value
    end

    local target = _G[targetName]
    if not target then
        targetName = "UIParent"
        target = E.UIParent
    end

    if self:WouldCreateAnchorCycle(index, targetName) then
        self:Print(L.ANCHOR_CYCLE_ERROR)
        self:RefreshOptions()
        return
    end

    if changedField == "point" or changedField == "target" or changedField == "relativePoint" then
        local moverX, moverY = GetAnchorCoordinates(mover, point)
        local targetX, targetY = GetAnchorCoordinates(target, relativePoint)
        if moverX and targetX then
            xOffset = E:Round(moverX - targetX)
            yOffset = E:Round(moverY - targetY)
        end
    end

    E.db.movers = E.db.movers or {}
    E.db.movers[moverName] = string.format(
        "%s,%s,%s,%d,%d",
        point,
        targetName,
        relativePoint,
        E:Round(tonumber(xOffset) or 0),
        E:Round(tonumber(yOffset) or 0)
    )

    if not (InCombatLockdown and InCombatLockdown()) then
        E:SetMoverPoints(moverName)
    end
    self:ScheduleApplyAll("ANCHOR_CHANGED")
    self:RefreshOptions()
end

function LECF:UpdateMoverBackdrop(index)
    local container = self.containers and self.containers[index]
    local config = self:GetFrameConfig(index)
    local backdrop = container and container.backdrop
    if not backdrop or not config then return end

    if not self:IsSlotActive(index) or not config.backdrop then
        backdrop:Hide()
        return
    end

    -- Reapplying the template keeps borders in sync after an ElvUI media/profile change.
    backdrop:SetTemplate("Transparent", nil, true)

    local chatModule = E:GetModule("Chat", true)
    local panelColor = chatModule and chatModule.db and chatModule.db.panelColor
    if panelColor then
        backdrop:SetBackdropColor(panelColor.r, panelColor.g, panelColor.b, panelColor.a)
    end

    backdrop:Show()
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
        container:CreateBackdrop("Transparent", nil, true)
        container.backdrop:EnableMouse(false)
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
                LECF:RefreshOptions()
            end,
            "ALL,LAFEE",
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

    local moverName = self:GetMoverName(index)
    local isActive = self:IsSlotActive(index)
    if isActive and E.DisabledMovers[moverName] then
        E:EnableMover(moverName)
    end
    E:SetMoverPoints(moverName)

    local width = math.max(self.MIN_WIDTH, math.min(self.MAX_WIDTH, tonumber(config.width) or self.MIN_WIDTH))
    local height = math.max(self.MIN_HEIGHT, math.min(self.MAX_HEIGHT, tonumber(config.height) or self.MIN_HEIGHT))
    config.width = width
    config.height = height
    container:SetSize(width, height)
    self:UpdateMoverLabel(index)
    self:UpdateMoverBackdrop(index)

    if not isActive and E.CreatedMovers[moverName] then
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
