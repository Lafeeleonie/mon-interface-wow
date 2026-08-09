local _, addon = ...
local LECF = addon.LECF
if not LECF then return end

local E = LECF.E
local L = LECF.L

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

function LECF:GetChatFrameByID(id)
    id = tonumber(id)
    if not id or id <= 0 then return end

    if FCF_GetChatFrameByID then
        return FCF_GetChatFrameByID(id)
    end
    return _G["ChatFrame" .. id]
end

function LECF:GetSafeChatWindowName(id)
    if not FCF_GetChatWindowInfo then
        return string.format(L.CHAT_WINDOW_ID, id)
    end

    local name = FCF_GetChatWindowInfo(id)
    if E:NotSecretValue(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return string.format(L.CHAT_WINDOW_ID, id)
end

function LECF:IsPersistentChatWindowActive(id)
    local chatFrame = self:GetChatFrameByID(id)
    if not chatFrame or chatFrame.isTemporary then
        return false
    end

    if FCF_IsChatWindowIndexActive then
        local ok, active = pcall(FCF_IsChatWindowIndexActive, id)
        return ok and active and true or false
    end

    if not FCF_GetChatWindowInfo then
        return chatFrame:IsShown() or chatFrame.isDocked
    end

    local ok, shown = pcall(function()
        return select(7, FCF_GetChatWindowInfo(id))
    end)
    return ok and (shown or chatFrame.isDocked) and true or false
end

function LECF:GetChatWindowValues()
    local values = { [0] = L.NO_CHAT_WINDOW }

    local function AddWindow(chatFrame, id)
        if chatFrame and not chatFrame.isTemporary and id and id > 0 then
            values[id] = string.format(L.CHAT_WINDOW_ENTRY, id, self:GetSafeChatWindowName(id))
            self:Debug(L.DEBUG_DETECTED, id, self:GetSafeChatWindowName(id))
        end
    end

    if FCF_IterateActiveChatWindows then
        FCF_IterateActiveChatWindows(AddWindow)
    elseif CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local chatFrame = _G[frameName]
            if chatFrame and self:IsPersistentChatWindowActive(chatFrame:GetID()) then
                AddWindow(chatFrame, chatFrame:GetID())
            end
        end
    end

    for index = 1, self.MAX_FRAMES do
        local config = self:GetFrameConfig(index)
        local id = config and tonumber(config.chatWindowID)
        if id and id > 0 and not values[id] then
            values[id] = string.format(L.CHAT_WINDOW_MISSING_ENTRY, id)
        end
    end

    return values
end

function LECF:GetAssignmentStatus(index)
    local config = self:GetFrameConfig(index)
    local id = config and tonumber(config.chatWindowID)
    if not id or id <= 0 then
        return L.STATUS_UNASSIGNED
    end

    if self:IsPersistentChatWindowActive(id) then
        return string.format(L.STATUS_ATTACHED, self:GetSafeChatWindowName(id), id)
    end
    return string.format(L.STATUS_MISSING, id)
end

function LECF:RestoreChatFrame(chatFrame)
    if not chatFrame then return end

    chatFrame:ClearAllPoints()
    local chatModule = E:GetModule("Chat", true)
    if chatFrame == DEFAULT_CHAT_FRAME and chatModule and chatModule.PositionChat then
        chatModule:PositionChat(chatFrame)
    elseif FCF_RestorePositionAndDimensions then
        FCF_RestorePositionAndDimensions(chatFrame)
    end
end

function LECF:ReleaseSlot(index)
    self.attachedBySlot = self.attachedBySlot or {}
    self.slotByChatFrame = self.slotByChatFrame or {}

    local chatFrame = self.attachedBySlot[index]
    if not chatFrame then return end

    local id = chatFrame:GetID()
    self.attachedBySlot[index] = nil
    self.slotByChatFrame[chatFrame] = nil
    self:RestoreChatFrame(chatFrame)
    self:Debug(L.DEBUG_DETACHED, id, index)
end

function LECF:AttachSlot(index)
    local config = self:GetFrameConfig(index)
    local container = self.containers and self.containers[index]
    local id = config and tonumber(config.chatWindowID)

    if not self:IsSlotActive(index) or not id or id <= 0 or not container then
        self:ReleaseSlot(index)
        return
    end

    if not self:IsPersistentChatWindowActive(id) then
        self:ReleaseSlot(index)
        return
    end

    local chatFrame = self:GetChatFrameByID(id)
    if not chatFrame then
        self:ReleaseSlot(index)
        return
    end

    local previousSlot = self.slotByChatFrame and self.slotByChatFrame[chatFrame]
    if previousSlot and previousSlot ~= index then
        self:ReleaseSlot(previousSlot)
    end

    local oldFrame = self.attachedBySlot and self.attachedBySlot[index]
    if oldFrame and oldFrame ~= chatFrame then
        self:ReleaseSlot(index)
    end

    if chatFrame ~= DEFAULT_CHAT_FRAME and chatFrame.isDocked and FCF_UnDockFrame then
        FCF_UnDockFrame(chatFrame)
    end

    chatFrame:ClearAllPoints()
    chatFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    chatFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    chatFrame:SetUserPlaced(true)
    chatFrame:SetMovable(true)
    chatFrame:SetClampedToScreen(false)

    if FCF_SetLocked then
        FCF_SetLocked(chatFrame, chatFrame == DEFAULT_CHAT_FRAME or config.locked)
    end

    local tab = _G[chatFrame:GetName() .. "Tab"]
    chatFrame:Show()
    if tab then
        tab:Show()
    end

    self.attachedBySlot = self.attachedBySlot or {}
    self.slotByChatFrame = self.slotByChatFrame or {}
    self.attachedBySlot[index] = chatFrame
    self.slotByChatFrame[chatFrame] = index
    self:Debug(L.DEBUG_ATTACHED, id, index)
end

function LECF:SetChatAssignment(index, id)
    id = tonumber(id) or 0

    if id > 0 then
        for otherIndex = 1, self.MAX_FRAMES do
            if otherIndex ~= index then
                local otherConfig = self:GetFrameConfig(otherIndex)
                if otherConfig and tonumber(otherConfig.chatWindowID) == id then
                    otherConfig.chatWindowID = 0
                    self:Debug(L.DUPLICATE_ASSIGNMENT, id, otherIndex, index)
                end
            end
        end
    end

    self:GetFrameConfig(index).chatWindowID = id
    self:ScheduleApplyAll("ASSIGNMENT_CHANGED")
    self:RefreshOptions()
end

function LECF:DetachSlot(index)
    local config = self:GetFrameConfig(index)
    if config then
        config.chatWindowID = 0
    end

    if IsInCombat() then
        self.pendingCombatUpdate = true
        self:Debug(L.DEBUG_DEFERRED)
    else
        self:ReleaseSlot(index)
    end
    self:RefreshOptions()
end

function LECF:ApplyAll()
    if not self.initialized then return end
    if IsInCombat() then
        self.pendingCombatUpdate = true
        self:Debug(L.DEBUG_DEFERRED)
        return
    end

    self:RefreshDatabase()
    self:UpdateAllMovers()

    for index = 1, self.MAX_FRAMES do
        local attached = self.attachedBySlot and self.attachedBySlot[index]
        local config = self:GetFrameConfig(index)
        local desiredID = self:IsSlotActive(index) and config and tonumber(config.chatWindowID) or 0
        if attached and attached:GetID() ~= desiredID then
            self:ReleaseSlot(index)
        end
    end

    for index = 1, self.MAX_FRAMES do
        self:AttachSlot(index)
    end
end

function LECF:ScheduleApplyAll()
    if not self.initialized or self.applyScheduled then return end
    if IsInCombat() then
        self.pendingCombatUpdate = true
        self:Debug(L.DEBUG_DEFERRED)
        return
    end

    self.applyScheduled = true
    C_Timer.After(0, function()
        self.applyScheduled = nil
        self:ApplyAll()
    end)
end

function LECF:OnChatWindowsChanged()
    self:ScheduleApplyAll("CHAT_WINDOWS_CHANGED")
    self:RefreshOptions()
end

function LECF:InitializeChatFrameHooks()
    self.attachedBySlot = {}
    self.slotByChatFrame = {}

    local chatModule = E:GetModule("Chat", true)
    if chatModule then
        if chatModule.SetupChat then
            self:SecureHook(chatModule, "SetupChat", "OnChatWindowsChanged")
        end
        if chatModule.PositionChats then
            self:SecureHook(chatModule, "PositionChats", "OnChatWindowsChanged")
        end
        if chatModule.PositionChat then
            self:SecureHook(chatModule, "PositionChat", "OnChatWindowsChanged")
        end
    end

    local globalHooks = {
        "FCF_OpenNewWindow",
        "FCF_Close",
        "FCF_DockFrame",
        "FCF_UnDockFrame",
        "FCF_SavePositionAndDimensions",
        "FCF_SetWindowName",
    }

    for _, functionName in ipairs(globalHooks) do
        if type(_G[functionName]) == "function" then
            self:SecureHook(functionName, "OnChatWindowsChanged")
        end
    end
end
