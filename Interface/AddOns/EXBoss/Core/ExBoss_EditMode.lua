---@diagnostic disable: undefined-global

local ET = _G.ExwindTools
if not ET then
    return
end

ExBoss = ExBoss or {}
ExBoss.EditMode = ExBoss.EditMode or {}
local Mod = ExBoss.EditMode
if Mod._installed == true then
    return
end
Mod._installed = true

local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local PANEL_WIDTH = 560
local PANEL_MIN_HEIGHT = 320
local PANEL_INIT_HEIGHT = 340
local PANEL_DEFAULT_X = 510
local PANEL_DEFAULT_Y = 130
local LEFT_COLUMN_X = 20
local RIGHT_COLUMN_X = 290
local HEADER_ROW_WIDTH = 520
local GROUP_ROW_WIDTH = 520
local SYSTEM_ROW_WIDTH = 240
local SYSTEM_LABEL_WIDTH = 180

local SYSTEM_TITLES = {
    ["ExBoss.TimerBar"] = L["计时条"],
    ["ExBoss.BunBar"] = L["束状条"],
    ["ExBoss.Countdown"] = L["倒计时"],
    ["ExBoss.FlashText"] = L["中央文字"],
    ["ExBoss.FlashTextMedium"] = L["中央文字(中)"],
    ["ExBoss.RingProgress"] = L["圆环进度"],
    ["ExBoss.IconAlert"] = L["图标"],
    ["ExBoss.CastProgressBar"] = L["施法进度条"],
    ["ExBoss.ExtraShieldBar"] = L["额外护盾条"],
    ["ExBoss.TargetAlert"] = L["被点名提示"],
    ["ExBoss.PrivateAuraMonitor"] = L["私人光环"],
    ["ExBoss.Boss.MaisaraTrash248690Absorb"] = L["小怪护盾监控"],
    ["ExBoss.Tools.MythicCast"] = L["大米怪物施法"],
    ["ExBoss.Tools.SpellTarget"] = L["框架被点名提示"],
    ["ExBoss.Tools.StateIcons"] = L["饰品监控"],
    ["ExBoss.Tools.InterruptTracker"] = L["队友打断监控"],
    ["ExTools.MiniTools.CombatAlert.Enter"] = L["进入战斗提示"],
    ["ExTools.MiniTools.CombatAlert.Leave"] = L["离开战斗提示"],
}

local FAMILY_COLORS = {
    EXBoss = {
        border = { 1.00, 0.48, 0.16, 0.92 },
        fill = { 0.18, 0.10, 0.06, 0.38 },
        header = { 0.30, 0.15, 0.09, 0.92 },
        tag = { 1.00, 0.78, 0.55, 1.00 },
    },
    ExwindTools = {
        border = { 0.68, 0.36, 1.00, 0.92 },
        fill = { 0.10, 0.08, 0.18, 0.38 },
        header = { 0.16, 0.10, 0.28, 0.92 },
        tag = { 0.86, 0.77, 1.00, 1.00 },
    },
    Default = {
        border = { 0.32, 0.66, 1.00, 0.92 },
        fill = { 0.07, 0.12, 0.18, 0.38 },
        header = { 0.11, 0.18, 0.28, 0.92 },
        tag = { 0.78, 0.89, 1.00, 1.00 },
    },
}

Mod.systems = Mod.systems or {}
Mod.panel = nil
Mod.rows = Mod.rows or {}
local EXUI = ET.UI
local RefreshAllSystemsForEditMode
local EXCLUDED_MODULE_KEYS = {}

local originalRegisterHUD = ET.RegisterHUD
local originalRegisterEditModeCallback = ET.RegisterEditModeCallback
local originalToggleGlobalEditMode = ET.ToggleGlobalEditMode

local function EnsureDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.ui = ExBossDB.ui or {}
    ExBossDB.ui.editMode = ExBossDB.ui.editMode or {}
    local db = ExBossDB.ui.editMode
    db.hiddenSystems = type(db.hiddenSystems) == "table" and db.hiddenSystems or {}
    -- 废弃旧版编辑面板位置持久化，每次登录恢复默认位置。
    db.panelX = nil
    db.panelY = nil
    return db
end

local function ResolveFamily(moduleKey)
    local key = tostring(moduleKey or "")
    if key:match("^ExBoss%.") then
        return "EXBoss"
    end
    return "ExwindTools"
end

local function ResolveTitle(moduleKey)
    local key = tostring(moduleKey or "")
    if SYSTEM_TITLES[key] then
        return SYSTEM_TITLES[key]
    end
    if ET and ET.ModuleIndexByKey and ET.ModuleList then
        local idx = ET.ModuleIndexByKey[key]
        local meta = idx and ET.ModuleList[idx] or nil
        if type(meta) == "table" and type(meta.Name) == "string" and meta.Name ~= "" then
            return meta.Name
        end
    end
    local tail = key:match("([^.]+)$")
    if tail and tail ~= "" then
        return tail
    end
    return key ~= "" and key or L["未命名"]
end

local function GetColorSet(family)
    return FAMILY_COLORS[family] or FAMILY_COLORS.Default
end

local function ShouldManageSystem(moduleKey)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        return false
    end
    if EXCLUDED_MODULE_KEYS[moduleKey] == true then
        return false
    end
    return Mod.systems[moduleKey] ~= nil
end

local function IsSystemVisible(moduleKey)
    if ET.IsEditModeModuleVisible then
        return ET:IsEditModeModuleVisible(moduleKey)
    end
    local hidden = EnsureDB().hiddenSystems
    return hidden[moduleKey] ~= true
end

local function HideObject(obj)
    if obj and obj.Hide then
        obj:Hide()
    end
end

local function HideLegacyDecor(frame)
    if not frame then
        return
    end
    HideObject(frame.EditOverlay)
    HideObject(frame.EditLabel)
    HideObject(frame.CenterMarker)
    HideObject(frame.bg)
    HideObject(frame.label)
end

local function SetFrameHiddenForEdit(system, hidden)
    local frame = system and system.frame
    if not frame then
        return
    end

    if hidden then
        if system._editHidden ~= true then
            system._editHidden = true
            system._editWasShown = frame:IsShown() == true
        end
        frame:Hide()
        if frame.EnableMouse then
            frame:EnableMouse(false)
        end
        return
    end

    if system._editHidden == true then
        if system._editWasShown and frame.Show then
            frame:Show()
        end
        system._editWasShown = nil
        system._editHidden = nil
    end
end

local function EnsureStandardOverlay(system)
    local frame = system and system.frame
    if not frame or system.standardOverlay then
        return
    end

    local family = ResolveFamily(system.moduleKey)
    local colors = GetColorSet(family)
    local headerHeight = 20
    local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, headerHeight)
    overlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, headerHeight)
    overlay:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata(frame:GetFrameStrata())
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 24)
    overlay:EnableMouse(false)
    overlay:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    overlay:SetBackdropColor(0, 0, 0, 0)
    overlay:SetBackdropBorderColor(unpack(colors.border))
    overlay:Hide()

    local content = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    content:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -headerHeight)
    content:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, -headerHeight)
    content:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    content:SetBackdropColor(unpack(colors.fill))
    overlay.Content = content

    local header = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    header:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    header:SetHeight(headerHeight)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not frame then
            return
        end

        local onDragStart = frame:GetScript("OnDragStart")
        if type(onDragStart) == "function" then
            onDragStart(frame)
            return
        end

        local onMouseDown = frame:GetScript("OnMouseDown")
        if type(onMouseDown) == "function" then
            onMouseDown(frame, "LeftButton")
            return
        end

        if frame.StartMoving then
            frame.isMoving = true
            frame:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        if not frame then
            return
        end

        local onDragStop = frame:GetScript("OnDragStop")
        if type(onDragStop) == "function" then
            onDragStop(frame)
            return
        end

        local onMouseUp = frame:GetScript("OnMouseUp")
        if type(onMouseUp) == "function" then
            onMouseUp(frame, "LeftButton")
            return
        end

        if frame.StopMovingOrSizing then
            frame:StopMovingOrSizing()
        end
    end)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    header:SetBackdropColor(unpack(colors.header))
    overlay.Header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 1, 1, 1)
    title:SetText(system.title or ResolveTitle(system.moduleKey))
    overlay.Title = title

    local tag = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    tag:SetJustifyH("RIGHT")
    tag:SetTextColor(unpack(colors.tag))
    tag:SetText(family)
    overlay.Tag = tag

    system.standardOverlay = overlay
end

local function RefreshSystemOverlay(moduleKey, enabled)
    local system = Mod.systems[moduleKey]
    if not system or not system.frame then
        return
    end

    EnsureStandardOverlay(system)
    HideLegacyDecor(system.frame)

    if system.standardOverlay then
        system.standardOverlay.Title:SetText(system.title or ResolveTitle(moduleKey))
        system.standardOverlay.Tag:SetText(system.family or ResolveFamily(moduleKey))
        system.standardOverlay:SetShown(enabled == true)
    end
end

local function SortSystems()
    local list = {}
    for _, system in pairs(Mod.systems) do
        if system and system.frame then
            list[#list + 1] = system
        end
    end
    table.sort(list, function(a, b)
        if (a.family or "") ~= (b.family or "") then
            return (a.family or "") < (b.family or "")
        end
        return (a.title or a.moduleKey or "") < (b.title or b.moduleKey or "")
    end)
    return list
end

local function BuildDisplayEntries()
    local systems = SortSystems()
    local entries = {}
    local lastFamily = nil

    for i = 1, #systems do
        local system = systems[i]
        local family = system.family or "Default"
        if family ~= lastFamily then
            entries[#entries + 1] = {
                entryType = "header",
                family = family,
            }
            entries[#entries + 1] = {
                entryType = "group_toggle",
                family = family,
            }
            lastFamily = family
        end
        entries[#entries + 1] = {
            entryType = "system",
            system = system,
        }
    end

    return entries
end

local function GetFamilyDisplayName(family)
    if family == "EXBoss" then
        return "EXBoss"
    end
    return "ExwindTools"
end

local function IsFamilyAllVisible(family)
    local hasAny = false
    for _, system in pairs(Mod.systems) do
        if system and system.frame and (system.family or "Default") == family then
            hasAny = true
            if not IsSystemVisible(system.moduleKey) then
                return false
            end
        end
    end
    return hasAny
end

local function SetFamilyVisible(family, visible)
    local hiddenSystems = EnsureDB().hiddenSystems
    for _, system in pairs(Mod.systems) do
        if system and system.frame and (system.family or "Default") == family then
            hiddenSystems[system.moduleKey] = visible and nil or true
            if ET.SetEditModeModuleVisible then
                ET:SetEditModeModuleVisible(system.moduleKey, visible, true)
            end
        end
    end
    RefreshAllSystemsForEditMode()
end

local function UpdatePanelRows()
    local panel = Mod.panel
    if not panel then
        return
    end

    local entries = BuildDisplayEntries()
    local y = -78
    local column = 0
    for i = 1, #entries do
        local entry = entries[i]
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetSize(HEADER_ROW_WIDTH, 24)

            if EXUI and EXUI.CreateCheckbox then
                local check = EXUI:CreateCheckbox(row, "", false, function(checked)
                    if row.entryType == "group_toggle" then
                        if row.family then
                            SetFamilyVisible(row.family, checked)
                        end
                        return
                    end

                    local currentKey = row.moduleKey
                    if not currentKey or currentKey == "" then
                        return
                    end

                    if ExBoss.EditMode and ExBoss.EditMode._dbg then
                        print(string.format("[EditMode] CLICK %s  finalChecked=%s  type=%s  stack=%s",
                            currentKey, tostring(checked), type(checked),
                            debugstack and debugstack(2, 3, 0) or "n/a"))
                    end

                    EnsureDB().hiddenSystems[currentKey] = checked and nil or true
                    if ET.SetEditModeModuleVisible then
                        ET:SetEditModeModuleVisible(currentKey, checked, true)
                    end
                    RefreshAllSystemsForEditMode()

                    if checked then
                        row.Label:SetTextColor(1, 1, 1, 1)
                    else
                        row.Label:SetTextColor(0.58, 0.58, 0.62, 1)
                    end
                end)
                check:SetSize(24, 24)
                check:ClearAllPoints()
                check:SetPoint("LEFT", row, "LEFT", 0, 0)
                if check.label then
                    check.label:SetText("")
                    check.label:Hide()
                end
                row.Check = check
            else
                local check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
                check:SetSize(24, 24)
                check:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.Check = check
            end

            local swatch = row:CreateTexture(nil, "ARTWORK")
            swatch:SetPoint("LEFT", row.Check, "RIGHT", 6, 0)
            swatch:SetSize(8, 8)
            row.Swatch = swatch

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
            label:SetJustifyH("LEFT")
            label:SetWidth(170)
            row.Label = label

            local family = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            family:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            family:SetJustifyH("RIGHT")
            row.Family = family

            panel.rows[i] = row
        end

        if entry.entryType == "header" then
            if column == 1 then
                y = y - 26
                column = 0
            end
            local colors = GetColorSet(entry.family)
            row:SetSize(HEADER_ROW_WIDTH, 22)
            row.entryType = "header"
            row.family = entry.family
            row.moduleKey = nil
            row.system = nil
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_COLUMN_X, y)
            row.Check:Hide()
            row.Swatch:Hide()
            row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.Label:SetWidth(HEADER_ROW_WIDTH)
            row.Label:SetText(GetFamilyDisplayName(entry.family))
            row.Label:SetTextColor(unpack(colors.tag))
            row.Family:SetText("")
            row.Family:Hide()
            row:Show()
            y = y - 24
        elseif entry.entryType == "group_toggle" then
            if column == 1 then
                y = y - 26
                column = 0
            end
            local colors = GetColorSet(entry.family)
            row:SetSize(GROUP_ROW_WIDTH, 22)
            row.entryType = "group_toggle"
            row.family = entry.family
            row.moduleKey = nil
            row.system = nil
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_COLUMN_X, y)
            row.Check:Show()
            row.Swatch:Hide()
            row.Label:SetPoint("LEFT", row.Check, "RIGHT", 6, 0)
            row.Label:SetWidth(GROUP_ROW_WIDTH - 60)
            row.Label:SetText(L["全选"])
            row.Label:SetTextColor(0.92, 0.92, 0.92, 1)
            row.Family:SetText("")
            row.Family:Hide()
            row.Check:SetChecked(IsFamilyAllVisible(entry.family))
            row:Show()
            y = y - 24
        else
            local system = entry.system
            local colors = GetColorSet(system.family)
            local moduleKey = system.moduleKey
            local x = (column == 0) and LEFT_COLUMN_X or RIGHT_COLUMN_X
            row:SetSize(SYSTEM_ROW_WIDTH, 24)
            row.entryType = "system"
            row.family = system.family
            row.moduleKey = system.moduleKey
            row.system = system
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
            row.Check:Show()
            row.Swatch:Show()
            row.Label:SetPoint("LEFT", row.Swatch, "RIGHT", 8, 0)
            row.Label:SetWidth(SYSTEM_LABEL_WIDTH)
            row.Swatch:SetColorTexture(colors.border[1], colors.border[2], colors.border[3], 1)
            row.Label:SetText(system.title or system.moduleKey)
            row.Family:SetText("")
            row.Family:Hide()

            row.Check:SetChecked(IsSystemVisible(moduleKey))

            if IsSystemVisible(moduleKey) then
                row.Label:SetTextColor(1, 1, 1, 1)
            else
                row.Label:SetTextColor(0.58, 0.58, 0.62, 1)
            end
            row:Show()
            if column == 0 then
                column = 1
            else
                column = 0
                y = y - 26
            end
        end
    end

    if column == 1 then
        y = y - 26
    end

    for i = #entries + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    panel:SetHeight(math.max(PANEL_MIN_HEIGHT, -y + 70))
end

local function EnsurePanel()
    local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
    if icon and type(icon.RefreshVisuals) == "function" then
        pcall(function()
            icon:RefreshVisuals()
        end)
    end
    if Mod.panel then
        UpdatePanelRows()
        return Mod.panel
    end

    local db = EnsureDB()
    local panel = CreateFrame("Frame", "ExBossEditModePanel", UIParent, "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetHeight(PANEL_INIT_HEIGHT)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(200)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(false)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    panel:SetPoint("CENTER", UIParent, "CENTER", PANEL_DEFAULT_X, PANEL_DEFAULT_Y)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
    panel:SetBackdropBorderColor(0.92, 0.56, 0.24, 0.88)
    panel:Hide()
    panel.rows = {}

    local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetMovable(true)
    header:SetScript("OnDragStart", function()
        panel:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(0.16, 0.10, 0.06, 0.98)
    panel.Header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText(L["EXBoss 编辑模式"])
    panel.Title = title

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    close:SetScript("OnClick", function()
        ET:ToggleGlobalEditMode(false)
    end)
    panel.CloseButton = close

    local subTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subTitle:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -10)
    subTitle:SetTextColor(0.92, 0.92, 0.92, 0.92)
    subTitle:SetText(L["勾选编辑模式中要显示的项目"])
    panel.SubTitle = subTitle

    local tip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", subTitle, "BOTTOMLEFT", 0, -6)
    tip:SetTextColor(0.76, 0.78, 0.84, 0.90)
    tip:SetText("")
    panel.Tip = tip

    local showAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    showAll:SetSize(92, 22)
    showAll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
    showAll:SetText(L["全部显示"])
    showAll:SetScript("OnClick", function()
        wipe(EnsureDB().hiddenSystems)
        if ET.ShowAllEditModeModules then
            ET:ShowAllEditModeModules(true)
        end
        RefreshAllSystemsForEditMode()
    end)
    panel.ShowAllButton = showAll

    local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 18)
    footer:SetTextColor(0.88, 0.74, 0.58, 0.95)
    footer:SetText("EXBoss")
    panel.Footer = footer

    Mod.panel = panel
    UpdatePanelRows()
    return panel
end

local function RefreshPanelVisibility()
    local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
    if icon and type(icon.RefreshVisuals) == "function" then
        pcall(function()
            icon:RefreshVisuals()
        end)
    end
    local panel = EnsurePanel()
    if ET.GlobalEditMode == true then
        panel:Show()
        panel:Raise()
        UpdatePanelRows()
    else
        panel:Hide()
    end
end

RefreshAllSystemsForEditMode = function()
    if ET.RefreshEditMode then
        ET:RefreshEditMode()
    else
        for _, system in pairs(Mod.systems) do
            if system and system.callback then
                pcall(system.callback, ET.GlobalEditMode == true)
            end
        end
    end
    if Mod.panel then
        UpdatePanelRows()
    end
end

local DBG = false -- /run ExBoss.EditMode._dbg=true 开启调试

local function MakeWrappedCallback(moduleKey, rawCallback)
    return function(enabled)
        local active = (enabled == true) and IsSystemVisible(moduleKey)
        local sys = Mod.systems[moduleKey]

        if DBG or (ExBoss.EditMode and ExBoss.EditMode._dbg) then
            print(string.format("[EditMode] %s  enabled=%s  active=%s  _editHidden=%s  frameShown=%s",
                moduleKey, tostring(enabled), tostring(active),
                tostring(sys and sys._editHidden),
                tostring(sys and sys.frame and sys.frame:IsShown())))
            -- 如果是第二次触发（_editHidden 已经是 true），打印调用栈找出来源
            if sys and sys._editHidden == true then
                print("[EditMode] STACK: " .. (debugstack and debugstack(2, 4, 0) or "n/a"))
            end
        end

        if active == true then
            -- 系统可见且编辑模式开启：强制显示 frame，不依赖 _editWasShown
            if sys then
                sys._editHidden = nil
                sys._editWasShown = nil
                if sys.frame then
                    sys.frame:Show()
                    if DBG or (ExBoss.EditMode and ExBoss.EditMode._dbg) then
                        print(string.format("[EditMode] %s  after Show() → IsShown=%s  parent=%s  parentShown=%s",
                            moduleKey, tostring(sys.frame:IsShown()),
                            tostring(sys.frame:GetParent() and sys.frame:GetParent():GetName()),
                            tostring(sys.frame:GetParent() and sys.frame:GetParent():IsShown())))
                    end
                end
            end
        elseif enabled ~= true then
            -- 编辑模式关闭：将我们主动隐藏的 frame 恢复到进入编辑模式前的状态
            SetFrameHiddenForEdit(sys, false)
        end

        pcall(rawCallback, active)

        if DBG or (ExBoss.EditMode and ExBoss.EditMode._dbg) then
            print(string.format("[EditMode] %s  after rawCb → frameShown=%s",
                moduleKey, tostring(sys and sys.frame and sys.frame:IsShown())))
        end

        if enabled == true and active ~= true then
            -- 编辑模式开启但系统被勾掉：隐藏 frame
            SetFrameHiddenForEdit(sys, true)
        end

        RefreshSystemOverlay(moduleKey, active)
    end
end

local function RegisterSystem(moduleKey, frame)
    if type(moduleKey) ~= "string" or moduleKey == "" or not frame then
        return
    end
    if EXCLUDED_MODULE_KEYS[moduleKey] == true then
        return
    end

    local system = Mod.systems[moduleKey] or {}
    system.moduleKey = moduleKey
    system.frame = frame
    system.family = ResolveFamily(moduleKey)
    system.title = ResolveTitle(moduleKey)
    Mod.systems[moduleKey] = system
    EnsureStandardOverlay(system)

    -- 修复时序问题：模块在文件加载时调用 RegisterEditModeCallback（此时 system 尚不存在），
    -- 导致 wrapped 未绑定。RegisterHUD 晚于 RegisterEditModeCallback 调用，在此补绑。
    if not system.callback then
        local existingCb = ET.EditModeCallbacks and ET.EditModeCallbacks[moduleKey]
        if type(existingCb) == "function" then
            local wrapped = MakeWrappedCallback(moduleKey, existingCb)
            system.callback = wrapped
            system.rawCallback = existingCb
            -- 同步替换 EditModeCallbacks，确保全局编辑模式切换时也走 wrapped 逻辑
            originalRegisterEditModeCallback(ET, moduleKey, wrapped)
        end
    end

    if Mod.panel then
        UpdatePanelRows()
    end
end

function ET:RegisterHUD(moduleKey, frame)
    originalRegisterHUD(self, moduleKey, frame)
    RegisterSystem(moduleKey, frame)
end

function ET:RegisterEditModeCallback(moduleKey, callback)
    if not ShouldManageSystem(moduleKey) then
        return originalRegisterEditModeCallback(self, moduleKey, callback)
    end

    local wrapped = MakeWrappedCallback(moduleKey, callback)

    local system = Mod.systems[moduleKey]
    if system then
        system.callback = wrapped
        system.rawCallback = callback
    end
    return originalRegisterEditModeCallback(self, moduleKey, wrapped)
end

function ET:ToggleGlobalEditMode(forceState)
    originalToggleGlobalEditMode(self, forceState)
    StaticPopup_Hide("EXWIND_EDIT_MODE_EXIT")

    if ET.GlobalEditMode == true then
        RefreshAllSystemsForEditMode()
    end

    RefreshPanelVisibility()
end
