local _, Addon = ...

local FEATURE_ID = "prey_bar"
local DOMAIN_ID = "feature.preyBar"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local WIDGET_ID = 7663
local SCALE_MIN = 0.70
local SCALE_MAX = 1.45
local SCALE_STEP = 0.05
local FRAME_WIDTHS = {
    compact = { clean = 220, framed = 240 },
    normal = { clean = 320, framed = 340 },
    wide = { clean = 420, framed = 440 },
}
local DEFAULT_POSITION = {
    point = "TOP",
    relativePoint = "TOP",
    x = 0,
    y = -160,
}
local BASE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "QUEST_REMOVED",
}
local ACTIVE_EVENTS = {
    "QUEST_LOG_UPDATE",
    "UPDATE_UI_WIDGET",
    "UPDATE_ALL_UI_WIDGETS",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
}

local Runtime = {
    enabled = false,
    frame = nil,
    model = nil,
    lastProgress = nil,
    lastQuestID = nil,
    activeEventsEnabled = false,
    preview = false,
    widgetInfo = nil,
    widgetObservedAt = 0,
    widgetFrames = setmetatable({}, { __mode = "k" }),
    widgetAlpha = setmetatable({}, { __mode = "k" }),
    widgetMouse = setmetatable({}, { __mode = "k" }),
    widgetShown = setmetatable({}, { __mode = "k" }),
    widgetOnShowHooked = setmetatable({}, { __mode = "k" }),
    widgetHooked = false,
}

Addon.PreyBar = Runtime

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function positiveInteger(value)
    value = Addon.PreyBarLogic:CoerceNumber(value)
    value = value and math.floor(value) or nil
    return value and value > 0 and value or nil
end

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function showMessage(message)
    if type(message) == "string" and message ~= "" then
        Addon:Print(message)
    end
end

local function currentTime()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok then return tonumber(value) or 0 end
    end
    return 0
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.preyBar = type(db.features.preyBar) == "table"
        and db.features.preyBar or {}
    local store = db.features.preyBar
    store.position = type(store.position) == "table" and store.position or {}
    store.scale = clamp(store.scale, SCALE_MIN, SCALE_MAX)
    return store
end

local function applyPosition(frame)
    if not frame then return end
    local position = getStore().position
    frame:ClearAllPoints()
    frame:SetPoint(
        type(position.point) == "string" and position.point or DEFAULT_POSITION.point,
        UIParent,
        type(position.relativePoint) == "string" and position.relativePoint or DEFAULT_POSITION.relativePoint,
        tonumber(position.x) or DEFAULT_POSITION.x,
        tonumber(position.y) or DEFAULT_POSITION.y
    )
end

local function savePosition(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local position = getStore().position
    position.point = type(point) == "string" and point or DEFAULT_POSITION.point
    position.relativePoint = type(relativePoint) == "string" and relativePoint or position.point
    position.x = tonumber(x) or 0
    position.y = tonumber(y) or 0

    if relativeTo and relativeTo ~= UIParent
        and type(frame.GetCenter) == "function"
        and type(UIParent.GetCenter) == "function"
    then
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if centerX and centerY and parentX and parentY then
            position.point, position.relativePoint = "CENTER", "CENTER"
            position.x, position.y = centerX - parentX, centerY - parentY
        end
    end
end

local function resetLayout()
    local store = getStore()
    store.position.point = DEFAULT_POSITION.point
    store.position.relativePoint = DEFAULT_POSITION.relativePoint
    store.position.x = DEFAULT_POSITION.x
    store.position.y = DEFAULT_POSITION.y
    store.scale = 1
    if Runtime.frame then
        Runtime.frame:SetScale(1)
        applyPosition(Runtime.frame)
    end
end

local function callNumber(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    return ok and positiveInteger(value) or nil
end

local function getActiveQuestID()
    return C_QuestLog and callNumber(C_QuestLog.GetActivePreyQuest) or nil
end

local function getQuestMapID(questID)
    local candidates = {}
    local function addCandidate(mapID)
        if mapID then candidates[#candidates + 1] = mapID end
    end
    if C_TaskQuest then
        addCandidate(callNumber(C_TaskQuest.GetQuestZoneID, questID))
    end
    if C_QuestLog then
        addCandidate(callNumber(C_QuestLog.GetQuestUiMapID, questID))
    end
    addCandidate(callNumber(_G.GetQuestUiMapID, questID))
    return Addon.PreyBarLogic:SelectQuestMapID(candidates)
end

local function getPlayerMapID()
    if not (C_Map and type(C_Map.GetBestMapForUnit) == "function") then return nil end
    return callNumber(C_Map.GetBestMapForUnit, "player")
end

local function getParentMapID(mapID)
    if not (C_Map and type(C_Map.GetMapInfo) == "function") then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    return ok and type(info) == "table" and positiveInteger(info.parentMapID) or nil
end

local function getMapName(mapID)
    if not (mapID and C_Map and type(C_Map.GetMapInfo) == "function") then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    return ok and type(info) == "table" and type(info.name) == "string" and info.name or nil
end

local function getQuestTitle(questID)
    if not (C_QuestLog and questID) then return nil end
    if type(C_QuestLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then return title end
    end
    if type(C_QuestLog.GetLogIndexForQuestID) == "function"
        and type(C_QuestLog.GetInfo) == "function"
    then
        local okIndex, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if okIndex and tonumber(index) and tonumber(index) > 0 then
            local okInfo, info = pcall(C_QuestLog.GetInfo, index)
            if okInfo and type(info) == "table"
                and type(info.title) == "string" and info.title ~= ""
            then
                return info.title
            end
        end
    end
    return nil
end

local function getQuestObjectives(questID)
    if not (C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function") then
        return {}
    end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    return ok and type(objectives) == "table" and objectives or {}
end

local function widgetInfoMatches(info)
    if type(info) ~= "table" then return false end
    local widgetID = positiveInteger(info.widgetID or info.widgetId)
    return widgetID == nil or widgetID == WIDGET_ID
end

local function frameMatchesWidget(frame)
    if frame == nil then return false end
    local ok, widgetID, widgetInfo, gainAnim, transitionAnim = pcall(function()
        return frame.widgetID or frame.widgetId,
            frame.widgetInfo,
            frame.PlayGainProgressAnim,
            frame.PlayTransitionAnim
    end)
    if not ok then return false end
    if positiveInteger(widgetID) == WIDGET_ID then return true end
    if type(widgetInfo) == "table"
        and positiveInteger(widgetInfo.widgetID or widgetInfo.widgetId) == WIDGET_ID
    then
        return true
    end
    return type(gainAnim) == "function" and type(transitionAnim) == "function"
end

local function stopWidgetVisuals(frame, visited)
    if not frame then return end
    visited = visited or {}
    if visited[frame] then return end
    visited[frame] = true

    local okController, controller = pcall(function() return frame.effectController end)
    if okController and controller and type(controller.CancelEffect) == "function" then
        pcall(controller.CancelEffect, controller)
        pcall(function() frame.effectController = nil end)
    end

    for _, key in ipairs({ "GainProgressAnim", "TransitionAnim", "GlowAnim", "PulseAnim" }) do
        local okAnimation, animation = pcall(function() return frame[key] end)
        if okAnimation and animation and type(animation.Stop) == "function" then
            pcall(animation.Stop, animation)
        end
    end
    local okShine, shineAnimation = pcall(function()
        return frame.ShineFrame and frame.ShineFrame.Anim
    end)
    if okShine and shineAnimation and type(shineAnimation.Stop) == "function" then
        pcall(shineAnimation.Stop, shineAnimation)
    end

    if type(frame.GetAnimationGroups) == "function" then
        local okGroups, groups = pcall(function() return { frame:GetAnimationGroups() } end)
        if okGroups then
            for _, animation in ipairs(groups or {}) do
                if animation and type(animation.Stop) == "function" then
                    pcall(animation.Stop, animation)
                end
            end
        end
    end
    if type(frame.GetChildren) == "function" then
        local okChildren, children = pcall(function() return { frame:GetChildren() } end)
        if okChildren then
            for _, child in ipairs(children or {}) do
                stopWidgetVisuals(child, visited)
            end
        end
    end
end

function Runtime:ShouldSuppressBlizzardWidget()
    return self.enabled == true
        and self.preview ~= true
        and setting("widget_visibility") == "hidden"
        and self.model
        and self.model.visible == true
end

function Runtime:EnsureWidgetOnShowHook(frame)
    if not frame or self.widgetOnShowHooked[frame] or type(frame.HookScript) ~= "function" then
        return
    end
    self.widgetOnShowHooked[frame] = true
    frame:HookScript("OnShow", function()
        if not Runtime:ShouldSuppressBlizzardWidget() then return end
        local function suppressAgain()
            if Runtime:ShouldSuppressBlizzardWidget() then
                Runtime:ApplyBlizzardWidgetVisibility()
            end
        end
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, suppressAgain)
            C_Timer.After(0.08, suppressAgain)
        else
            suppressAgain()
        end
    end)
end

function Runtime:QueryWidgetInfo()
    if C_UIWidgetManager
        and type(C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo) == "function"
    then
        local ok, info = pcall(
            C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo,
            WIDGET_ID
        )
        if ok and type(info) == "table" then return info end
    end
    if type(self.widgetInfo) == "table"
        and (currentTime() - (tonumber(self.widgetObservedAt) or 0)) <= 2
    then
        return self.widgetInfo
    end
    return nil
end

function Runtime:FindWidgetFrames()
    local container = _G.UIWidgetPowerBarContainerFrame
    if not container or type(container.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { container:GetChildren() } end)
    if not ok then return end
    for _, child in ipairs(children) do
        if frameMatchesWidget(child) then self.widgetFrames[child] = true end
    end
end

function Runtime:RestoreBlizzardWidget()
    for frame in pairs(self.widgetFrames) do
        if frame then
            if self.widgetAlpha[frame] ~= nil and type(frame.SetAlpha) == "function" then
                pcall(frame.SetAlpha, frame, self.widgetAlpha[frame])
            end
            if self.widgetMouse[frame] ~= nil and type(frame.EnableMouse) == "function" then
                pcall(frame.EnableMouse, frame, self.widgetMouse[frame])
            end
            local wasShown = self.widgetShown[frame]
            local huntStillVisible = self.model and self.model.visible == true
            if wasShown == true and huntStillVisible and type(frame.Show) == "function" then
                pcall(frame.Show, frame)
            end
        end
        self.widgetAlpha[frame] = nil
        self.widgetMouse[frame] = nil
        self.widgetShown[frame] = nil
    end
end

function Runtime:ApplyBlizzardWidgetVisibility()
    self:EnsureWidgetHook()
    self:FindWidgetFrames()
    local suppress = self:ShouldSuppressBlizzardWidget()
    if not suppress then
        self:RestoreBlizzardWidget()
        return
    end

    for frame in pairs(self.widgetFrames) do
        self:EnsureWidgetOnShowHook(frame)
        if self.widgetShown[frame] == nil and type(frame.IsShown) == "function" then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok then self.widgetShown[frame] = shown == true end
        end
        if self.widgetAlpha[frame] == nil then
            local alpha = 1
            if type(frame.GetAlpha) == "function" then
                local ok, value = pcall(frame.GetAlpha, frame)
                if ok then alpha = tonumber(value) or 1 end
            end
            self.widgetAlpha[frame] = alpha
        end
        if self.widgetMouse[frame] == nil then
            local enabled = true
            if type(frame.IsMouseEnabled) == "function" then
                local ok, value = pcall(frame.IsMouseEnabled, frame)
                if ok then enabled = value == true end
            end
            self.widgetMouse[frame] = enabled
        end
        stopWidgetVisuals(frame)
        if type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, 0) end
        if type(frame.EnableMouse) == "function" then pcall(frame.EnableMouse, frame, false) end
        if type(frame.Hide) == "function"
            and not (type(InCombatLockdown) == "function" and InCombatLockdown())
        then
            pcall(frame.Hide, frame)
        end
    end
end

function Runtime:EnsureWidgetHook()
    if self.widgetHooked then return end
    local mixin = _G.UIWidgetTemplatePreyHuntProgressMixin
    if type(mixin) ~= "table" or type(mixin.Setup) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return
    end
    hooksecurefunc(mixin, "Setup", function(frame, info)
        if frame ~= nil then Runtime.widgetFrames[frame] = true end
        if type(info) == "table" and widgetInfoMatches(info) then
            Runtime.widgetInfo = info
            Runtime.widgetObservedAt = currentTime()
        end
        if Runtime.enabled then
            Runtime:ApplyBlizzardWidgetVisibility()
            Runtime:ScheduleRefresh(0)
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function() Runtime:ApplyBlizzardWidgetVisibility() end)
                C_Timer.After(0.08, function() Runtime:ApplyBlizzardWidgetVisibility() end)
            end
        end
    end)
    self.widgetHooked = true
end

function Runtime:CollectModel()
    local questID = getActiveQuestID()
    if not questID then
        self.lastQuestID = nil
        self.lastProgress = nil
        return Addon.PreyBarLogic:BuildModel({}, nil)
    end

    if self.lastQuestID ~= questID then
        self.lastQuestID = questID
        self.lastProgress = nil
    end
    local questMapID = getQuestMapID(questID)
    local playerMapID = getPlayerMapID()
    local inZone = Addon.PreyBarLogic:IsPlayerInQuestZone(
        playerMapID,
        questMapID,
        getParentMapID
    )
    local model = Addon.PreyBarLogic:BuildModel({
        questID = questID,
        questMapID = questMapID,
        playerMapID = playerMapID,
        inZone = inZone,
        mapName = getMapName(questMapID),
        questTitle = getQuestTitle(questID),
        objectives = getQuestObjectives(questID),
        widgetInfo = self:QueryWidgetInfo(),
    }, self.lastProgress)
    if model.progress and model.progress.hidden ~= true then
        self.lastProgress = model.progress
    end
    return model
end

function Runtime:GetSettingValue(settingKey)
    if settingKey == "scale_percent" then
        return math.floor((getStore().scale * 100) + 0.5)
    end
    return nil
end

function Runtime:SetSettingValue(settingKey, value)
    if settingKey ~= "scale_percent" then return false end
    local store = getStore()
    store.scale = clamp((tonumber(value) or 100) / 100, SCALE_MIN, SCALE_MAX)
    if self.frame then self.frame:SetScale(store.scale) end
    return true
end

function Runtime:StartMoving()
    if not self.frame or setting("locked") == true then return end
    self.frame:StartMoving()
end

function Runtime:StopMoving()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    savePosition(self.frame)
end

function Runtime:ChangeScale(delta)
    if not self.frame or setting("locked") == true
        or type(IsShiftKeyDown) ~= "function" or not IsShiftKeyDown()
    then
        return
    end
    local current = self:GetSettingValue("scale_percent") or 100
    Addon.FeatureRegistry:SetSetting(
        FEATURE_ID,
        "scale_percent",
        current + (delta > 0 and SCALE_STEP * 100 or -SCALE_STEP * 100)
    )
end

function Runtime:CreateFrame()
    local frame = CreateFrame("Frame", "VaultloomPreyBar", UIParent, BACKDROP_TEMPLATE)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() Runtime:StartMoving() end)
    frame:SetScript("OnDragStop", function() Runtime:StopMoving() end)
    frame:SetScript("OnMouseWheel", function(_, delta) Runtime:ChangeScale(delta) end)
    frame:SetScript("OnEnter", function() Runtime:ShowTooltip() end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetJustifyH("LEFT")
    frame.title:SetMaxLines(1)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)
    frame.percent = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.percent:SetJustifyH("RIGHT")
    frame.percent:SetTextColor(0.96, 0.88, 0.72, 1)
    frame.bar = Addon.Widgets:CreateProgressBar(frame)
    frame.phase = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.phase:SetPoint("CENTER", 0, 0)
    frame.phase:SetTextColor(1, 0.96, 0.88, 1)

    self.frame = frame
    frame:SetScale(getStore().scale)
    applyPosition(frame)
end

function Runtime:ApplyFrameStyle(frameStyle)
    if not self.frame then return end
    local clean = frameStyle == "clean" or frameStyle == "dark_red"
    local widthMode = setting("bar_width")
    local widths = FRAME_WIDTHS[widthMode] or FRAME_WIDTHS.normal
    local showTitle = frameStyle ~= "dark_red" and setting("show_title") ~= false
    self.frame.title:ClearAllPoints()
    self.frame.percent:ClearAllPoints()
    self.frame.bar:ClearAllPoints()
    self.frame.title:SetShown(showTitle)
    self.frame.percent:SetShown(showTitle)
    if clean then
        self.frame:SetBackdrop(nil)
        self.frame:SetSize(widths.clean, showTitle and 46 or 22)
        if showTitle then
            self.frame.title:SetPoint("TOPLEFT", 2, -1)
            self.frame.percent:SetPoint("TOPRIGHT", -2, -1)
            self.frame.bar:SetPoint("BOTTOMLEFT", 2, 3)
            self.frame.bar:SetPoint("BOTTOMRIGHT", -2, 3)
        else
            self.frame.bar:SetPoint("LEFT", 2, 0)
            self.frame.bar:SetPoint("RIGHT", -2, 0)
        end
    else
        self.frame:SetBackdrop({
            bgFile = Addon.Assets.cardInset,
            edgeFile = TOOLTIP_BORDER,
            tile = false,
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        self.frame:SetBackdropColor(1, 1, 1, 1)
        self.frame:SetBackdropBorderColor(0.82, 0.64, 0.20, 1)
        self.frame:SetSize(widths.framed, showTitle and 58 or 38)
        if showTitle then
            self.frame.title:SetPoint("TOPLEFT", 14, -11)
            self.frame.percent:SetPoint("TOPRIGHT", -14, -11)
            self.frame.bar:SetPoint("BOTTOMLEFT", 14, 11)
            self.frame.bar:SetPoint("BOTTOMRIGHT", -14, 11)
        else
            self.frame.bar:SetPoint("LEFT", 14, 0)
            self.frame.bar:SetPoint("RIGHT", -14, 0)
        end
    end
    if showTitle then
        self.frame.title:SetPoint("RIGHT", self.frame.percent, "LEFT", -10, 0)
    end
    self.frame.bar:SetHeight(16)
end

function Runtime:ApplyBarVisualStyle(frameStyle)
    if not (self.frame and self.frame.bar) then return end
    local bar = self.frame.bar
    local darkRed = frameStyle == "dark_red"

    if darkRed then
        bar.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.backdrop:SetVertexColor(0.28, 0.035, 0.045, 0.96)
        bar.background:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.background:SetVertexColor(0.045, 0.010, 0.016, 0.98)
        if bar.fill then
            bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        bar.fillOverlay:Hide()
        bar.glow:Hide()
        bar.spark:Hide()
        bar.topEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.topEdge:SetVertexColor(0.42, 0.075, 0.09, 0.42)
        bar.bottomEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.bottomEdge:SetVertexColor(0.01, 0.004, 0.006, 0.72)
        for _, marker in ipairs(bar.markers or {}) do
            marker:SetTexture("Interface\\Buttons\\WHITE8X8")
            marker:SetSize(1, 12)
            marker:SetBlendMode("BLEND")
            marker:SetVertexColor(0.72, 0.32, 0.34, 0.46)
        end
        self.frame.title:SetTextColor(0.96, 0.78, 0.76, 1)
        self.frame.percent:SetTextColor(1, 0.92, 0.90, 1)
        self.frame.phase:SetTextColor(1, 0.88, 0.86, 1)
        return
    end

    bar.backdrop:SetTexture(Addon.Assets.barBackground)
    bar.backdrop:SetVertexColor(0.08, 0.07, 0.06, 0.22)
    bar.background:SetTexture(Addon.Assets.barBackground)
    bar.background:SetVertexColor(1, 1, 1, 0.94)
    if bar.fill then
        bar.fill:SetTexture(Addon.Assets.barFill)
    end
    bar.fillOverlay:SetTexture(Addon.Assets.barOverlay)
    bar.glow:SetTexture(Addon.Assets.barOverlay)
    bar.spark:SetTexture(Addon.Assets.barSpark)
    bar.spark:SetSize(16, 20)
    bar.topEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.topEdge:SetVertexColor(
        Addon.Theme.colors.parchment[1],
        Addon.Theme.colors.parchment[2],
        Addon.Theme.colors.parchment[3],
        0.10
    )
    bar.bottomEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.bottomEdge:SetVertexColor(0.01, 0.01, 0.01, 0.16)
    for _, marker in ipairs(bar.markers or {}) do
        marker:SetTexture(Addon.Assets.barMarker)
        marker:SetSize(16, 16)
        marker:SetBlendMode("BLEND")
        marker:SetVertexColor(0.96, 0.82, 0.48, 0.54)
    end
    self.frame.title:SetTextColor(1, 0.82, 0.24, 1)
    self.frame.percent:SetTextColor(0.96, 0.88, 0.72, 1)
    self.frame.phase:SetTextColor(1, 0.96, 0.88, 1)
end

function Runtime:GetDisplayModel()
    if not self.preview then return self.model end
    return {
        active = true,
        inZone = true,
        visible = true,
        preview = true,
        mapName = Addon.L.PREY_BAR_PREVIEW_ZONE,
        questTitle = Addon.L.PREY_BAR_PREVIEW_QUEST,
        targetName = Addon.L.PREY_BAR_PREVIEW_TARGET,
        progress = {
            questID = 0,
            stage = 2,
            percent = 58,
            source = "preview",
        },
    }
end

function Runtime:Render()
    if self.enabled ~= true then return end
    if not self.frame then self:CreateFrame() end
    local model = self:GetDisplayModel()
    if not (model and model.visible and model.progress) then
        self.frame:Hide()
        self:ApplyBlizzardWidgetVisibility()
        return
    end

    local frameStyle = setting("frame_style")
    self:ApplyFrameStyle(frameStyle)
    local target = model.targetName or model.questTitle or Addon.L.PREY_BAR_UNKNOWN_TARGET
    local progress = model.progress
    local percent = clamp(progress.percent, 0, 100)
    local stage = math.max(0, math.min(3, math.floor((tonumber(progress.stage) or 0) + 0.5)))
    self.frame.title:SetText(string.format(Addon.L.PREY_BAR_TITLE_FORMAT, target))
    self.frame.percent:SetText(string.format(Addon.L.PREY_BAR_PERCENT_FORMAT, math.floor(percent + 0.5)))
    self.frame.phase:SetText(string.format(Addon.L.PREY_BAR_PHASE_FORMAT, stage, 3))
    local barColor = frameStyle == "dark_red"
        and { 0.48, 0.025, 0.04, 1 }
        or { 0.78, 0.16, 0.12, 1 }
    Addon.Widgets:SetProgress(self.frame.bar, percent, 100, barColor)
    Addon.Widgets:SetProgressBreakpoints(self.frame.bar, { 33, 66 }, 100)
    self:ApplyBarVisualStyle(frameStyle)
    self.frame:SetScale(getStore().scale)
    self.frame:Show()
    self:ApplyBlizzardWidgetVisibility()
end

function Runtime:ShowTooltip()
    local model = self:GetDisplayModel()
    if not (GameTooltip and model and model.visible) then return end
    GameTooltip:SetOwner(self.frame, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Addon.L.FEATURE_PREY_BAR, 1, 0.82, 0.24)
    if type(model.questTitle) == "string" and model.questTitle ~= "" then
        GameTooltip:AddLine(model.questTitle, 1, 1, 1, true)
    end
    if type(model.mapName) == "string" and model.mapName ~= "" then
        GameTooltip:AddDoubleLine(
            Addon.L.PREY_BAR_ZONE_LABEL,
            model.mapName,
            0.75, 0.75, 0.75,
            1, 0.82, 0.24
        )
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Addon.L.PREY_BAR_MOVE_HINT, 0.70, 0.70, 0.70, true)
    GameTooltip:Show()
end

function Runtime:SetActiveEventsEnabled(enabled)
    enabled = enabled == true
    if enabled == self.activeEventsEnabled then return end
    self.activeEventsEnabled = enabled
    if enabled then
        for _, eventName in ipairs(ACTIVE_EVENTS) do
            Addon.EventBus:Subscribe(eventName, self, function(event, ...)
                Runtime:OnEvent(event, ...)
            end)
        end
    else
        for _, eventName in ipairs(ACTIVE_EVENTS) do
            Addon.EventBus:Unsubscribe(self, eventName)
        end
    end
end

function Runtime:ScheduleRefresh(delay)
    if self.enabled ~= true then return false end
    return Addon.RefreshScheduler:Invalidate(DOMAIN_ID, delay or 0)
end

function Runtime:OnModelChanged(model)
    self.model = type(model) == "table" and model or { visible = false }
    self:SetActiveEventsEnabled(self.model.active == true and self.model.inZone == true)
    self:Render()
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "UPDATE_UI_WIDGET" then
        local widgetID = positiveInteger(...)
        if widgetID and widgetID ~= WIDGET_ID then return end
    end
    if eventName == "PLAYER_DEAD"
        or eventName == "PLAYER_ALIVE"
        or eventName == "PLAYER_UNGHOST"
    then
        self.lastProgress = nil
    end
    if eventName == "QUEST_ACCEPTED"
        or eventName == "QUEST_TURNED_IN"
        or eventName == "QUEST_REMOVED"
    then
        self.lastProgress = nil
    end
    local delay = eventName == "PLAYER_ENTERING_WORLD" and 0.20 or 0
    self:ScheduleRefresh(delay)
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "widget_visibility" then
        self:ApplyBlizzardWidgetVisibility()
    else
        self:Render()
    end
end

function Runtime:ResetSettingValues()
    resetLayout()
end

function Runtime:OnSettingsReset()
    self.preview = false
    self:Render()
end

function Runtime:OnSettingsClosed()
    if not self.preview then return end
    self.preview = false
    self:Render()
end

function Runtime:OnAction(actionKey)
    if actionKey == "preview" then
        self.preview = not self.preview
        self:Render()
        return true
    end
    if actionKey == "reset_layout" then
        self.preview = false
        resetLayout()
        self:Render()
        showMessage(Addon.L.PREY_BAR_LAYOUT_RESET)
        return true
    end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    self.preview = false
    self.lastProgress = nil
    self.lastQuestID = nil
    self:EnsureWidgetHook()
    Addon.RefreshScheduler:Register(DOMAIN_ID, self, function()
        return Runtime:CollectModel()
    end)
    Addon.StateStore:Subscribe(DOMAIN_ID, self, function(model)
        Runtime:OnModelChanged(model)
    end, false)
    for _, eventName in ipairs(BASE_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:ScheduleRefresh(0)
end

function Runtime:OnDisable()
    self.enabled = false
    self.preview = false
    self.lastProgress = nil
    self.lastQuestID = nil
    self:SetActiveEventsEnabled(false)
    if self.frame then self.frame:Hide() end
    self:RestoreBlizzardWidget()
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Prey Hunt Progress Bar runtime.")
end
