local ExwindTools = _G.ExwindTools
if not ExwindTools then
    return
end

local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame
local issecretvalue = _G.issecretvalue
local math = _G.math
local pairs = _G.pairs
local string = _G.string
local table = _G.table
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type

local AnchorController = {}
AnchorController.__index = AnchorController

local function CloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, innerValue in pairs(value) do
        copy[key] = CloneValue(innerValue)
    end
    return copy
end

local function NormalizePoint(point, fallback)
    local text = type(point) == "string" and point or fallback or "CENTER"
    return string.upper(text)
end

local function SetClickThrough(frame)
    if not frame then
        return
    end

    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        pcall(frame.SetMouseClickEnabled, frame, false)
    end
    if frame.SetMouseMotionEnabled then
        pcall(frame.SetMouseMotionEnabled, frame, false)
    end
end

local function SetInteractive(frame)
    if not frame then
        return
    end

    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then
        pcall(frame.SetMouseClickEnabled, frame, true)
    end
    if frame.SetMouseMotionEnabled then
        pcall(frame.SetMouseMotionEnabled, frame, true)
    end
end

local function ResolveFramePath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local target = _G
    for part in string.gmatch(path, "([^%.]+)") do
        if target then
            target = target[part]
        else
            break
        end
    end

    if type(target) ~= "table" then
        return nil
    end

    if type(target.GetPoint) ~= "function" and type(target.GetCenter) ~= "function" then
        return nil
    end

    return target
end

local function SafeGetScale(frame)
    if frame and type(frame.GetEffectiveScale) == "function" then
        local scale = frame:GetEffectiveScale()
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return 1
end

local function CanMeasureFrame(frame)
    if not frame then
        return false
    end

    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end

    return true
end

local function SafeGetRect(frame)
    if not CanMeasureFrame(frame) then
        return nil, nil, nil, nil
    end

    if type(frame.GetLeft) ~= "function"
        or type(frame.GetRight) ~= "function"
        or type(frame.GetTop) ~= "function"
        or type(frame.GetBottom) ~= "function" then
        return nil, nil, nil, nil
    end

    local okLeft, left = pcall(frame.GetLeft, frame)
    local okRight, right = pcall(frame.GetRight, frame)
    local okTop, top = pcall(frame.GetTop, frame)
    local okBottom, bottom = pcall(frame.GetBottom, frame)
    if not okLeft or type(left) ~= "number" then
        return nil, nil, nil, nil
    end
    if not okRight or not okTop or not okBottom then
        return nil, nil, nil, nil
    end

    if issecretvalue and (issecretvalue(left) or issecretvalue(right) or issecretvalue(top) or issecretvalue(bottom)) then
        return nil, nil, nil, nil
    end

    if type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then
        return nil, nil, nil, nil
    end

    return left, right, top, bottom
end

local function ResolvePointPosition(frame, point)
    if not frame then
        return nil, nil
    end

    local normalizedPoint = NormalizePoint(point, "CENTER")
    local left, right, top, bottom = SafeGetRect(frame)
    local centerX, centerY = type(frame.GetCenter) == "function" and frame:GetCenter() or nil, nil
    if type(frame.GetCenter) == "function" then
        centerX, centerY = frame:GetCenter()
    end

    local x = centerX
    if normalizedPoint:find("LEFT", 1, true) then
        x = left
    elseif normalizedPoint:find("RIGHT", 1, true) then
        x = right
    elseif not x and left and right then
        x = (left + right) / 2
    end

    local y = centerY
    if normalizedPoint:find("TOP", 1, true) then
        y = top
    elseif normalizedPoint:find("BOTTOM", 1, true) then
        y = bottom
    elseif not y and top and bottom then
        y = (top + bottom) / 2
    end

    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then
        return nil, nil
    end

    return x, y
end

local function SyncGridWidget(moduleKey, widgetKey, value, rangeInfo)
    if type(widgetKey) ~= "string" or widgetKey == "" then
        return
    end

    local Grid = _G.ExwindGrid
    if not Grid or type(Grid.Widgets) ~= "table" then
        return
    end
    if not ExwindTools.UI or ExwindTools.UI.CurrentModule ~= moduleKey then
        return
    end

    local widget = Grid.Widgets[widgetKey]
    if not widget then
        return
    end

    if type(value) == "boolean" then
        if widget.SetChecked then
            widget:SetChecked(value)
        end
        return
    end

    if type(value) == "string" then
        local editBox = widget.editBox or widget
        if editBox and editBox.SetText then
            editBox:SetText(value)
        end
        return
    end

    if type(value) ~= "number" then
        return
    end

    if rangeInfo and widget.Init then
        local minValue = tonumber(rangeInfo.min)
        local maxValue = tonumber(rangeInfo.max)
        local stepValue = tonumber(rangeInfo.step) or 1
        if minValue and maxValue and maxValue ~= minValue then
            widget:Init(value, minValue, maxValue, (maxValue - minValue) / stepValue)
            return
        end
    end

    if widget.SetValue then
        widget:SetValue(value)
        if widget.ValueText then
            widget.ValueText:SetText(tostring(value))
        end
    end
end

function AnchorController:GetDB()
    local options = self.options
    if type(options.getDB) == "function" then
        local ok, db = pcall(options.getDB, self)
        if ok and type(db) == "table" then
            return db
        end
    end

    if type(options.db) == "table" then
        return options.db
    end

    return nil
end

function AnchorController:GetOffsetKeys()
    return self.options.offsetXKey, self.options.offsetYKey
end

function AnchorController:GetAnchorPoint(target)
    local options = self.options
    if type(options.getAnchorPoint) == "function" then
        return NormalizePoint(options.getAnchorPoint(self, target), options.anchorPoint or "CENTER")
    end
    return NormalizePoint(options.anchorPoint, "CENTER")
end

function AnchorController:GetRelativePoint(target)
    local options = self.options
    if type(options.getRelativePoint) == "function" then
        return NormalizePoint(options.getRelativePoint(self, target), options.relativePoint or "CENTER")
    end
    return NormalizePoint(options.relativePoint, "CENTER")
end

function AnchorController:GetAttachTargetPath()
    local db = self:GetDB()
    if not db then
        return nil
    end

    local key = self.options.attachTargetKey
    if type(key) ~= "string" or key == "" then
        return nil
    end

    return db[key]
end

function AnchorController:IsAttachEnabled()
    local db = self:GetDB()
    if not db then
        return false
    end

    local enabledKey = self.options.attachEnabledKey
    if type(enabledKey) ~= "string" or enabledKey == "" then
        return false
    end

    return db[enabledKey] == true
end

function AnchorController:ResolveAttachTarget()
    if not self:IsAttachEnabled() then
        return nil
    end

    local path = self:GetAttachTargetPath()
    return ResolveFramePath(path)
end

function AnchorController:GetResolvedTarget()
    return self:ResolveAttachTarget() or UIParent
end

function AnchorController:SyncWidgets(keys)
    local db = self:GetDB()
    if not db then
        return
    end

    local widgetRanges = self.options.widgetRanges or {}
    local widgetKeys = keys or self.options.syncWidgets or {
        self.options.offsetXKey,
        self.options.offsetYKey,
        self.options.attachEnabledKey,
        self.options.attachTargetKey,
    }

    for _, key in ipairs(widgetKeys) do
        if type(key) == "string" and key ~= "" then
            SyncGridWidget(self.options.moduleKey, key, db[key], widgetRanges[key])
        end
    end
end

function AnchorController:ApplyPosition()
    local frame = self.frame
    local db = self:GetDB()
    if not frame or not db or frame.isMoving then
        return false
    end

    local offsetXKey, offsetYKey = self:GetOffsetKeys()
    local offsetX = tonumber(db[offsetXKey]) or tonumber(self.options.defaultOffsetX) or 0
    local offsetY = tonumber(db[offsetYKey]) or tonumber(self.options.defaultOffsetY) or 0
    local target = self:GetResolvedTarget()
    local anchorPoint = self:GetAnchorPoint(target)
    local relativePoint = self:GetRelativePoint(target)
    if type(self.options.getAppliedOffsets) == "function" then
        local ok, appliedOffsetX, appliedOffsetY = pcall(self.options.getAppliedOffsets, self, target, offsetX, offsetY)
        if ok then
            offsetX = tonumber(appliedOffsetX) or offsetX
            offsetY = tonumber(appliedOffsetY) or offsetY
        end
    end

    frame:ClearAllPoints()
    frame:SetPoint(anchorPoint, target, relativePoint, offsetX, offsetY)
    return true
end

function AnchorController:SavePosition()
    local frame = self.frame
    local db = self:GetDB()
    if not frame or not db then
        return false
    end

    local target = self:GetResolvedTarget()
    local anchorPoint = self:GetAnchorPoint(target)
    local relativePoint = self:GetRelativePoint(target)
    local anchorX, anchorY = ResolvePointPosition(frame, anchorPoint)
    local targetX, targetY = ResolvePointPosition(target, relativePoint)
    if not anchorX or not anchorY or not targetX or not targetY then
        return false
    end

    local anchorScale = SafeGetScale(frame)
    local targetScale = SafeGetScale(target)
    local offsetX = math.floor(((anchorX * anchorScale) - (targetX * targetScale)) / anchorScale)
    local offsetY = math.floor(((anchorY * anchorScale) - (targetY * targetScale)) / anchorScale)
    if type(self.options.normalizeSavedOffsets) == "function" then
        local ok, normalizedOffsetX, normalizedOffsetY = pcall(self.options.normalizeSavedOffsets, self, target, offsetX, offsetY)
        if ok then
            offsetX = math.floor(tonumber(normalizedOffsetX) or offsetX)
            offsetY = math.floor(tonumber(normalizedOffsetY) or offsetY)
        end
    end
    local offsetXKey, offsetYKey = self:GetOffsetKeys()

    if type(offsetXKey) == "string" and offsetXKey ~= "" then
        db[offsetXKey] = offsetX
    end
    if type(offsetYKey) == "string" and offsetYKey ~= "" then
        db[offsetYKey] = offsetY
    end

    self:SyncWidgets()

    if type(self.options.onPositionSaved) == "function" then
        pcall(self.options.onPositionSaved, self, offsetX, offsetY)
    end

    return true
end

function AnchorController:StartFramePicker()
    if type(ExwindTools.StartFramePicker) ~= "function" then
        return false
    end

    local db = self:GetDB()
    if not db then
        return false
    end

    local targetKey = self.options.attachTargetKey
    if type(targetKey) ~= "string" or targetKey == "" then
        return false
    end

    local enabledKey = self.options.attachEnabledKey
    local prevTarget = db[targetKey]
    local prevEnabled = type(enabledKey) == "string" and db[enabledKey] or nil

    ExwindTools:StartFramePicker(
        function(name)
            db[targetKey] = name
            if type(enabledKey) == "string" and enabledKey ~= "" then
                db[enabledKey] = true
            end
            self:SyncWidgets({ targetKey, enabledKey })
            self:ApplyPosition()
            if type(self.options.onFramePicked) == "function" then
                pcall(self.options.onFramePicked, self, name)
            end
        end,
        function()
            db[targetKey] = prevTarget
            if type(enabledKey) == "string" and enabledKey ~= "" then
                db[enabledKey] = prevEnabled
            end
            self:SyncWidgets({ targetKey, enabledKey })
            if type(self.options.onFramePickCancelled) == "function" then
                pcall(self.options.onFramePickCancelled, self)
            end
        end
    )

    return true
end

function AnchorController:ShowOverlay()
    if self.options.useStandardOverlay == false then
        return
    end
    if self.frame and ExwindTools.ShowExwindToolsEditOverlay then
        ExwindTools:ShowExwindToolsEditOverlay(self.options.moduleKey, self.frame, {
            title = self.options.title,
            ownerFrame = self.frame,
        })
    end
end

function AnchorController:HideOverlay()
    if self.frame and ExwindTools.HideExwindToolsEditOverlay then
        ExwindTools:HideExwindToolsEditOverlay(self.frame)
    end
end

function AnchorController:BackupRestoreKeys()
    if self.restoreSnapshot then
        return
    end

    local db = self:GetDB()
    if not db then
        return
    end

    local restoreKeys = self.options.restoreKeys
    if type(restoreKeys) ~= "table" or #restoreKeys <= 0 then
        return
    end

    self.restoreSnapshot = {}
    for _, key in ipairs(restoreKeys) do
        if type(key) == "string" and key ~= "" then
            self.restoreSnapshot[key] = CloneValue(db[key])
        end
    end
end

function AnchorController:RestoreKeys()
    local db = self:GetDB()
    local snapshot = self.restoreSnapshot
    if not db or type(snapshot) ~= "table" then
        self.restoreSnapshot = nil
        return
    end

    for key, value in pairs(snapshot) do
        db[key] = CloneValue(value)
    end

    self.restoreSnapshot = nil
    self:SyncWidgets()
end

function AnchorController:EnterEditMode()
    self.editActive = true
    self:BackupRestoreKeys()

    if type(self.options.onEnterEditMode) == "function" then
        pcall(self.options.onEnterEditMode, self)
    end
end

function AnchorController:ExitEditMode()
    self.editActive = false
    self:RestoreKeys()
    self:ApplyPosition()

    if type(self.options.onExitEditMode) == "function" then
        pcall(self.options.onExitEditMode, self)
    end
end

function AnchorController:SetEditVisible(visible)
    self.editVisible = visible == true

    if type(self.options.onSetEditVisible) == "function" then
        pcall(self.options.onSetEditVisible, self, self.editVisible)
    end
end

function AnchorController:RefreshEditMode(active, visible)
    self.editActive = active == true
    self.editVisible = visible == true

    if self.editActive and self.editVisible then
        SetInteractive(self.frame)
        self:ShowOverlay()
    else
        SetClickThrough(self.frame)
        self:HideOverlay()
    end

    if type(self.options.applyEditModeState) == "function" then
        pcall(self.options.applyEditModeState, self, self.editActive, self.editVisible)
    elseif type(self.options.onEditModeChanged) == "function" then
        pcall(self.options.onEditModeChanged, self, self.editActive, self.editVisible)
    end
end

function AnchorController:RegisterEditModeHandler()
    if self.editHandlerRegistered == true then
        return
    end

    local handler = {
        EnterEditMode = function()
            self:EnterEditMode()
        end,
        ExitEditMode = function()
            self:ExitEditMode()
        end,
        SetEditVisible = function(_, visible)
            self:SetEditVisible(visible)
        end,
        RefreshEditMode = function(_, active, visible)
            self:RefreshEditMode(active, visible)
        end,
    }

    ExwindTools:RegisterEditModeHandler(self.options.moduleKey, handler)
    self.editHandlerRegistered = true
end

function AnchorController:GetFrame()
    return self.frame
end

function AnchorController:Ensure()
    if self.frame then
        return self.frame
    end

    local options = self.options
    local frame = CreateFrame("Frame", options.frameName, options.parent or UIParent, options.frameTemplate)
    self.frame = frame

    frame:SetSize(tonumber(options.initialWidth) or 1, tonumber(options.initialHeight) or 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(options.clampedToScreen == true)
    if type(options.frameStrata) == "string" and options.frameStrata ~= "" then
        frame:SetFrameStrata(options.frameStrata)
    end
    if type(options.frameLevel) == "number" then
        frame:SetFrameLevel(options.frameLevel)
    end
    if options.fixedFrameStrata == true and frame.SetFixedFrameStrata then
        pcall(frame.SetFixedFrameStrata, frame, true)
    end

    SetClickThrough(frame)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner)
        if not (self.editActive and self.editVisible) then
            return
        end
        owner.isMoving = true
        owner:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(owner)
        if not owner.isMoving then
            return
        end
        owner.isMoving = false
        owner:StopMovingOrSizing()
        self:SavePosition()
    end)
    frame:SetScript("OnHide", function(owner)
        if owner.isMoving then
            owner.isMoving = false
            owner:StopMovingOrSizing()
        end
    end)
    frame:SetScript("OnMouseDown", function(owner, button)
        if not (self.editActive and self.editVisible) then
            return
        end
        if button == "LeftButton" then
            local onDragStart = owner:GetScript("OnDragStart")
            if type(onDragStart) == "function" then
                onDragStart(owner)
            end
        elseif button == "RightButton" and ExwindTools.OpenConfig then
            ExwindTools:OpenConfig(options.moduleKey)
        end
    end)
    frame:SetScript("OnMouseUp", function(owner, button)
        if button == "LeftButton" and owner.isMoving then
            local onDragStop = owner:GetScript("OnDragStop")
            if type(onDragStop) == "function" then
                onDragStop(owner)
            end
        end
    end)

    if type(options.onCreateFrame) == "function" then
        pcall(options.onCreateFrame, self, frame)
    end

    self:ApplyPosition()

    if options.registerHUD ~= false then
        ExwindTools:RegisterHUD(options.moduleKey, frame)
        if not (self.editActive and self.editVisible) then
            SetClickThrough(frame)
        end
    end

    self:RegisterEditModeHandler()
    return frame
end

function ExwindTools:CreateAnchorController(options)
    if type(options) ~= "table" then
        error("CreateAnchorController: options must be table", 2)
    end
    if type(options.moduleKey) ~= "string" or options.moduleKey == "" then
        error("CreateAnchorController: moduleKey must be string", 2)
    end

    local controller = setmetatable({
        options = options,
        editActive = false,
        editVisible = true,
        restoreSnapshot = nil,
        frame = nil,
        editHandlerRegistered = false,
    }, AnchorController)

    return controller
end
