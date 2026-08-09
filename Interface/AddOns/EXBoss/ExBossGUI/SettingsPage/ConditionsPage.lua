---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/ConditionsPage.lua
-- 固定轴条件系统设置页（嵌入“设置”页，使用 ExwindGrid 渲染）。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local EXUI = ExwindTools.UI
local Grid = ExwindTools.Grid
if not (EXUI and Grid) then return end

ExBoss.UI.Panel.ConditionsPage = ExBoss.UI.Panel.ConditionsPage or {}
local Page = ExBoss.UI.Panel.ConditionsPage

local MODULE_KEY = "ExBoss.Conditions.RuleEditor"
local GRID_COLS = 82
local LABEL_ITEMS_FUNC = "func:ExBoss.Voice.LabelCatalog.GetDropdownItems"

local ACTION_ITEMS = {
    { L["倒数文字"], "countdown" },
    { L["播放音效"], "voice" },
}

local SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}

local EDITOR_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 82, h = 2, label = L["规则编辑"], labelSize = 24 },
    { key = "name", type = "input", x = 1, y = 5, w = 24, h = 2, label = L["条件命名"] },
    { key = "enabled", type = "checkbox", x = 27, y = 5, w = 10, h = 2, label = L["启用"] },
    { key = "eventID", type = "input", x = 1, y = 9, w = 10, h = 2, label = L["事件ID"] },
    { key = "remaining", type = "input", x = 13, y = 9, w = 10, h = 2, label = L["剩余时间"] },
    { key = "hint", type = "description", x = 25, y = 9, w = 55, h = 2, label = L["只对 fixed / fixed_ai 生效。文本可用 {name}、{eventID}、{spellID}。"] },

    { key = "divider_action", type = "divider", x = 1, y = 13, w = 81, h = 1, label = L["动作设置"] },
    { key = "actionType", type = "dropdown", x = 1, y = 16, w = 14, h = 2, label = L["动作"], items = ACTION_ITEMS },
    { key = "text", type = "input", x = 17, y = 16, w = 44, h = 2, label = L["文本内容"] },

    { key = "divider_voice", type = "divider", x = 1, y = 20, w = 81, h = 1, label = L["音效设置"] },
    { key = "voiceSource", type = "dropdown", x = 1, y = 23, w = 13, h = 2, label = L["音效来源"], items = SOURCE_ITEMS },
    { key = "voiceLabel", type = "dropdown", x = 16, y = 23, w = 28, h = 2, label = L["语音标签"], items = LABEL_ITEMS_FUNC },
    { key = "voiceLSM", type = "lsm_sound", x = 16, y = 23, w = 28, h = 2, label = L["LSM音效"] },
    { key = "voicePath", type = "input", x = 16, y = 23, w = 34, h = 2, label = L["文件路径"] },
    { key = "voiceTest", type = "button", x = 46, y = 23, w = 5, h = 2, label = L["试听"] },
}

local selectedIndex = 1
local suppressRefresh = false

local selector
local globalEnabled
local addButton
local copyButton
local deleteButton
local statusText
local root
local gridScrollFrame
local gridScrollChild
local emptyText

local function Store()
    return ExBoss and ExBoss.Conditions and ExBoss.Conditions.Store or nil
end

local function NormalizeSource(v)
    local s = tostring(v or "pack")
    if s == "lsm" or s == "file" then
        return s
    end
    return "pack"
end

local function GetRules()
    local store = Store()
    return store and store:GetRules() or {}
end

local function GetSelectedRule()
    local rules = GetRules()
    if #rules == 0 then
        selectedIndex = 0
        return nil
    end
    if selectedIndex < 1 then selectedIndex = 1 end
    if selectedIndex > #rules then selectedIndex = #rules end
    rules[selectedIndex] = rules[selectedIndex] or {}
    local store = Store()
    if store then
        store:ApplyRuleDefaults(rules[selectedIndex])
    end
    return rules[selectedIndex]
end

local function GetActionLabel(actionType)
    actionType = tostring(actionType or "countdown")
    for i = 1, #ACTION_ITEMS do
        if ACTION_ITEMS[i][2] == actionType then
            return ACTION_ITEMS[i][1]
        end
    end
    return actionType
end

local function BuildRuleItems()
    local rules = GetRules()
    local items = {}
    for i = 1, #rules do
        local rule = rules[i] or {}
        local store = Store()
        local normalized = store and store:NormalizeRule(rule, i) or {}
        local displayName = tostring(normalized.name or "")
        if displayName == "" then
            displayName = string.format(L["条件 %02d"], i)
        end
        local enabledText = normalized.enabled and "" or (" [" .. L["停用"] .. "]")
        items[#items + 1] = {
            displayName .. enabledText,
            i,
        }
    end
    if #items == 0 then
        items[1] = { L["暂无规则"], 0 }
    end
    return items
end

local function RefreshSelector()
    if not selector then return end
    local items = BuildRuleItems()
    selector._items = items
    selector._currentValue = selectedIndex
    local text = items[1] and items[1][1] or L["暂无规则"]
    for i = 1, #items do
        if tonumber(items[i][2]) == tonumber(selectedIndex) then
            text = items[i][1]
            break
        end
    end
    selector:SetText(text)
end

local function GetEditorWidgets()
    local state = Grid.ContainerStates and Grid.ContainerStates[gridScrollChild] or nil
    return state and state.widgets or {}
end

local function SetWidgetShown(widget, shown)
    if not widget then return end
    if shown then widget:Show() else widget:Hide() end
end

local function SetWidgetUsable(widget, usable)
    if not widget then return end
    local isInput = widget._gridType == "GridInput" or (widget.IsObjectType and widget:IsObjectType("EditBox"))
    if isInput then
        if widget.Enable then widget:Enable() end
        if widget.EnableMouse then widget:EnableMouse(true) end
    elseif widget.SetEnabled then
        widget:SetEnabled(usable == true)
    elseif widget.Enable and widget.Disable then
        if usable then widget:Enable() else widget:Disable() end
    end
    widget:SetAlpha(usable and 1 or 0.45)
    if widget._exLabel then
        widget._exLabel:SetAlpha(usable and 1 or 0.45)
    elseif widget.labelText then
        widget.labelText:SetAlpha(usable and 1 or 0.45)
    end
end

local function RestoreGridInputWidgets()
    local widgets = GetEditorWidgets()
    for _, widget in pairs(widgets) do
        if widget and (widget._gridType == "GridInput" or (widget.IsObjectType and widget:IsObjectType("EditBox"))) then
            if widget.Enable then widget:Enable() end
            if widget.EnableMouse then widget:EnableMouse(true) end
            if widget.SetAutoFocus then widget:SetAutoFocus(false) end
        end
    end
end

local function RefreshEditorLabels()
    local widgets = GetEditorWidgets()
    for _, key in ipairs({ "eventID", "remaining" }) do
        local widget = widgets[key]
        if widget and widget.SetTextColor then
            widget:SetTextColor(1, 1, 1, 1)
        end
        local label = widget and (widget._exLabel or widget.labelText or widget.label)
        if label and label.SetTextColor then
            label:SetTextColor(1, 1, 1, 1)
        end
    end

    local textWidget = widgets.text
    local textLabel = textWidget and (textWidget._exLabel or textWidget.labelText or textWidget.label)
    if textLabel and textLabel.SetText then
        textLabel:SetText(L["文本内容"])
    end
end

local function RefreshEditorDynamicWidgets()
    local rule = GetSelectedRule()
    if not rule then return end
    local widgets = GetEditorWidgets()
    local actionType = tostring(rule.actionType or "countdown")
    local voiceOn = actionType == "voice"
    local countdownOn = actionType == "countdown"
    local source = NormalizeSource(rule.voiceSource)

    SetWidgetShown(widgets.text, countdownOn)
    SetWidgetUsable(widgets.text, countdownOn)
    SetWidgetShown(widgets.divider_voice, voiceOn)
    SetWidgetShown(widgets.voiceSource, voiceOn)
    SetWidgetShown(widgets.voiceTest, voiceOn)
    SetWidgetUsable(widgets.voiceSource, voiceOn)
    SetWidgetUsable(widgets.voiceTest, voiceOn)

    SetWidgetShown(widgets.voiceLabel, voiceOn and source == "pack")
    SetWidgetShown(widgets.voiceLSM, voiceOn and source == "lsm")
    SetWidgetShown(widgets.voicePath, voiceOn and source == "file")
    SetWidgetUsable(widgets.voiceLabel, voiceOn and source == "pack")
    SetWidgetUsable(widgets.voiceLSM, voiceOn and source == "lsm")
    SetWidgetUsable(widgets.voicePath, voiceOn and source == "file")
    RefreshEditorLabels()
end

local function MarkRulesChanged()
    local store = Store()
    if store then
        local rule = GetSelectedRule()
        if rule then
            store:ApplyRuleDefaults(rule)
        end
        store:BumpRevision()
    end
end

local function PlayVoicePreview()
    local rule = GetSelectedRule()
    if type(rule) ~= "table" then return end
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and engine.TryPlayStandaloneSound) then return end

    local source = NormalizeSource(rule.voiceSource)
    local triggerCfg = { enabled = true, sourceType = source }
    if source == "pack" then
        local label = tostring(rule.voiceLabel or "")
        if label == "" then return end
        triggerCfg.label = label
    elseif source == "lsm" then
        local key = tostring(rule.voiceLSM or "")
        if key == "" then return end
        triggerCfg.customLSM = key
    else
        local path = tostring(rule.voicePath or "")
        if path == "" then return end
        triggerCfg.customPath = path
    end
    engine:TryPlayStandaloneSound(triggerCfg, "condition_preview:" .. tostring(selectedIndex), { triggerIndex = 1 })
end

function Page:RenderEditor()
    if not gridScrollChild then return end
    local rule = GetSelectedRule()
    RefreshSelector()
    if globalEnabled and globalEnabled.checkbox then
        local db = Store() and Store():GetDB() or nil
        globalEnabled.checkbox:SetChecked(type(db) == "table" and db.fixedRulesEnabled ~= false)
    end

    if not rule then
        gridScrollFrame:Hide()
        if emptyText then emptyText:Show() end
        SetWidgetUsable(copyButton, false)
        SetWidgetUsable(deleteButton, false)
        return
    end

    if emptyText then emptyText:Hide() end
    gridScrollFrame:Show()
    SetWidgetUsable(copyButton, true)
    SetWidgetUsable(deleteButton, true)
    suppressRefresh = true
    if Grid.SetContainerCols then
        Grid:SetContainerCols(gridScrollChild, GRID_COLS)
    end
    Grid:Render(gridScrollChild, EDITOR_LAYOUT, rule, MODULE_KEY)
    suppressRefresh = false
    RestoreGridInputWidgets()
    RefreshEditorLabels()
    RefreshEditorDynamicWidgets()
end

local function EnsureFrames(contentFrame)
    if root then
        return
    end

    root = CreateFrame("Frame", nil, contentFrame)
    root:SetAllPoints(contentFrame)
    Page._root = root
    Page._scrollFrame = root

    local title = EXUI:CreateHeader(root, L["条件系统（固定轴/AI轴）"], 1000)
    title:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)

    local desc = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -8)
    desc:SetWidth(980)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["规则创建时按 eventID 绑定到 fixed/fixed_ai 计时器；运行时只检查计时器自身条件，不扫描全表。"])

    globalEnabled = EXUI:CreateCheckbox(root, L["启用条件系统"], true, function(v)
        local store = Store()
        if store then
            store:GetDB().fixedRulesEnabled = v == true
            store:BumpRevision()
        end
    end)
    globalEnabled:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)

    selector = EXUI:CreateDropdown(root, 470, L["选择规则"], BuildRuleItems(), selectedIndex, function(value)
        local index = tonumber(value) or 0
        if index > 0 then
            selectedIndex = index
            Page:RenderEditor()
        end
    end)
    selector:SetPoint("TOPLEFT", globalEnabled, "BOTTOMLEFT", 0, -24)

    addButton = EXUI:CreateButton(root, 80, 26, L["新增规则"], function()
        local store = Store()
        if store then
            local index = store:AddRule()
            selectedIndex = index
        end
        Page:RenderEditor()
        if statusText then statusText:SetText(L["|cff33ee77已新增规则|r"]) end
    end)
    addButton:SetPoint("LEFT", selector, "RIGHT", 12, 0)

    copyButton = EXUI:CreateButton(root, 80, 26, L["复制规则"], function()
        local store = Store()
        if store and selectedIndex > 0 and store.CopyRule then
            local index = store:CopyRule(selectedIndex)
            if index then
                selectedIndex = index
            end
        end
        Page:RenderEditor()
        if statusText then statusText:SetText(L["|cff33ee77已复制规则|r"]) end
    end)
    copyButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)

    deleteButton = EXUI:CreateButton(root, 80, 26, L["删除规则"], function()
        local store = Store()
        if store and selectedIndex > 0 then
            store:DeleteRule(selectedIndex)
            local count = #GetRules()
            selectedIndex = math.min(math.max(1, selectedIndex), count)
        end
        Page:RenderEditor()
        if statusText then statusText:SetText(L["|cffff8888已删除规则|r"]) end
    end)
    deleteButton:SetPoint("LEFT", copyButton, "RIGHT", 8, 0)

    statusText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", deleteButton, "RIGHT", 12, 0)
    statusText:SetText("")

    emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 2, -28)
    emptyText:SetText(L["当前没有规则。点击“新增规则”后开始编辑。"])

    gridScrollFrame = CreateFrame("ScrollFrame", "ExBoss_ConditionsSettingsScroll", root, "ScrollFrameTemplate")
    gridScrollFrame:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", -10, -22)
    gridScrollFrame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -24, 4)

    gridScrollChild = CreateFrame("Frame", nil, gridScrollFrame)
    gridScrollChild:SetWidth(1000)
    gridScrollChild:SetHeight(520)
    gridScrollFrame:SetScrollChild(gridScrollChild)
    Page._gridScrollFrame = gridScrollFrame
    Page._scrollChild = gridScrollChild

    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(gridScrollFrame)
    end
end

function Page:Render(contentFrame)
    if not contentFrame then return end
    EnsureFrames(contentFrame)

    root:SetParent(contentFrame)
    root:ClearAllPoints()
    root:SetAllPoints(contentFrame)
    root:Show()

    local w = root:GetWidth()
    if w < 100 then
        w = 1000
    end
    gridScrollChild:SetWidth(w - 42)
    gridScrollFrame:SetVerticalScroll(0)

    self:RenderEditor()
end

function Page:Hide()
    if root then
        root:Hide()
    end
end

if not Page._eventsRegistered then
    ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_db", function(info)
        if suppressRefresh then return end
        MarkRulesChanged()
        local key = info and info.key
        if key == "actionType" or key == "voiceSource" then
            RefreshEditorDynamicWidgets()
        end
        RefreshSelector()
    end)
    ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
        if info and info.key == "voiceTest" then
            PlayVoicePreview()
        end
    end)
    Page._eventsRegistered = true
end
