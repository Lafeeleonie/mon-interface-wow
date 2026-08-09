---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.Panel.ImportExportPage = ExBoss.UI.Panel.ImportExportPage or {}
local Page = ExBoss.UI.Panel.ImportExportPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

-- ─── 工具函数 ─────────────────────────────────────────────────

local function Trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ─── 照抄 ExwindToolsUI 的常量 ───────────────────────────────

local BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BACKDROP_SIMPLE = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = nil,
}
local TOOLTIP_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 20, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local THEME = {
    Background  = { 0.04, 0.04, 0.05, 0.98 },
    Border      = { 0.25, 0.25, 0.28, 1 },
    Primary     = { 0.64, 0.19, 0.79 },
    Success     = { 0.13, 0.77, 0.37 },
    Danger      = { 0.87, 0.26, 0.26 },
    TextMain    = { 0.9,  0.9,  0.9,  1 },
    TextSub     = { 0.6,  0.6,  0.65, 1 },
    TextDim     = { 0.4,  0.4,  0.45, 1 },
    CardBg      = { 0.18, 0.18, 0.22, 0.6 },
}

-- ─── 照抄 CreateSmallButton ───────────────────────────────────

local function CreateSmallButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(120, 28)
    btn:SetBackdrop(BACKDROP_SIMPLE)
    btn:SetBackdropColor(0.2, 0.2, 0.25, 0.9)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject("GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    fs:SetTextColor(unpack(THEME.TextMain))
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.3, 0.35, 0.95) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 0.9)  end)
    return btn
end

-- ─── 照抄 CreateActionButton ─────────────────────────────────

local function CreateActionButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(180, 40)
    btn:SetBackdrop(BACKDROP)
    btn:SetBackdropColor(unpack(THEME.Primary))
    btn:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.8)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject("GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    fs:SetTextColor(1, 1, 1, 1)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.Primary[1]*1.3, THEME.Primary[2]*1.3, THEME.Primary[3]*1.3, 1)
        self:SetBackdropBorderColor(0.8, 0.5, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(THEME.Primary))
        self:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.8)
    end)
    return btn
end

-- ─── 照抄 CreateEditBox（多行模式）────────────────────────────

local function CreateMultiLineEditBox(parent, w, h)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(w, h)
    container:SetBackdrop(TOOLTIP_BACKDROP)
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local sf = CreateFrame("ScrollFrame", nil, container, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(sf)
    end
    sf:SetPoint("TOPLEFT",     container, "TOPLEFT",     5, -5)
    sf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -25, 5)

    local scrollContent = CreateFrame("Frame", nil, sf)
    scrollContent:SetSize(w - 30, 2000)
    sf:SetScrollChild(scrollContent)

    local eb = CreateFrame("EditBox", nil, scrollContent)
    eb:SetPoint("TOPLEFT",  scrollContent, "TOPLEFT",  0, 0)
    eb:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    eb:SetHeight(2000)
    eb:SetMultiLine(true)
    eb:SetTextInsets(8, 8, 8, 8)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP")
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextColor(0.7, 0.9, 0.7)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(0.64, 0.19, 0.79, 1)
    end)
    eb:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end)
    eb:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local vs = sf:GetVerticalScroll()
        local fh = sf:GetHeight()
        local cursorY = -y
        if cursorY < vs then
            sf:SetVerticalScroll(cursorY)
        elseif (cursorY + height) > (vs + fh) then
            sf:SetVerticalScroll(cursorY + height - fh)
        end
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 20, self:GetVerticalScrollRange())))
    end)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    container.editBox = eb
    function container:GetText() return self.editBox:GetText() end
    function container:SetText(t)  self.editBox:SetText(t or "") end
    function container:SetFocus()  self.editBox:SetFocus() end
    function container:HighlightText() self.editBox:HighlightText() end

    return container
end

-- ─── 照抄 ShowExportResultPopup ──────────────────────────────

local exportPopup = nil
local builtInAuthorPopup = nil

local function ShowExportPopup(encoded, configName, titleText, hintText)
    if not exportPopup then
        local popup = CreateFrame("Frame", "ExBoss_ExportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(600, 350)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        popup:SetBackdropBorderColor(unpack(THEME.Border))
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
        if not tContains(UISpecialFrames, "ExBoss_ExportPopup") then
            table.insert(UISpecialFrames, "ExBoss_ExportPopup")
        end

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
        title:SetPoint("TOP", 0, -15)
        title:SetText("|cff00ff80" .. L["导出成功"] .. "|r")
        popup.Title = title

        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() popup:Hide() end)

        local hint = popup:CreateFontString(nil, "OVERLAY")
        hint:SetFontObject("GameFontHighlight")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetText("|cffffd100Ctrl+C|r " .. L["复制并自动关闭，或点击"] .. " |cffffd100" .. L["全选复制"] .. "|r " .. L["按钮"])
        hint:SetTextColor(0.8, 0.8, 0.8)
        popup.Hint = hint

        -- 复制成功提示层（照抄 CopyHint）
        local copyHint = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        copyHint:SetSize(200, 60)
        copyHint:SetPoint("CENTER", popup, "CENTER", 0, 0)
        copyHint:SetFrameLevel(popup:GetFrameLevel() + 10)
        copyHint:SetBackdrop(BACKDROP)
        copyHint:SetBackdropColor(0.1, 0.3, 0.1, 0.95)
        copyHint:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        copyHint:Hide()
        local copyHintText = copyHint:CreateFontString(nil, "OVERLAY")
        copyHintText:SetFontObject("GameFontNormalLarge")
        copyHintText:SetPoint("CENTER")
        copyHintText:SetText("|cff00ff00" .. L["已复制到剪贴板"] .. "|r")
        popup.CopyHint = copyHint

        -- EditBox 容器（照抄 editFrame + scrollFrame）
        local editFrame = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        editFrame:SetSize(560, 200)
        editFrame:SetPoint("TOP", hint, "BOTTOM", 0, -10)
        editFrame:SetBackdrop(BACKDROP_SIMPLE)
        editFrame:SetBackdropColor(0.1, 0.1, 0.12, 1)

        local sf = CreateFrame("ScrollFrame", nil, editFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        sf:SetPoint("TOPLEFT",     editFrame, "TOPLEFT",      5, -5)
        sf:SetPoint("BOTTOMRIGHT", editFrame, "BOTTOMRIGHT", -25, 5)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetSize(530, 190)
        eb:SetFontObject("ChatFontNormal")
        eb:SetTextColor(0.7, 0.9, 0.7)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(999999)
        sf:SetScrollChild(eb)
        popup.EditBox = eb

        -- 照抄 OnUpdate 追踪 Ctrl 键
        popup.lastCtrlDown = 0
        popup:SetScript("OnUpdate", function(self)
            if IsControlKeyDown() then self.lastCtrlDown = GetTime() end
        end)

        -- 照抄 OnKeyUp 监听 Ctrl+C
        eb:SetScript("OnKeyUp", function(self, key)
            local wasCtrl = IsControlKeyDown() or (GetTime() - popup.lastCtrlDown < 0.5)
            if wasCtrl and key == "C" then
                self:ClearFocus()
                popup.CopyHint:Show()
                popup.CopyHint:SetAlpha(1)
                C_Timer.After(0.6, function()
                    popup:Hide()
                    popup.CopyHint:Hide()
                end)
            end
        end)

        -- 照抄底部按钮
        local selectBtn = CreateSmallButton(popup, L["全选复制"], function()
            eb:SetFocus()
            eb:HighlightText()
        end)
        selectBtn:SetSize(100, 28)
        selectBtn:SetPoint("BOTTOM", popup, "BOTTOM", -60, 15)

        local closeBtn2 = CreateSmallButton(popup, L["关闭"], function()
            popup:Hide()
        end)
        closeBtn2:SetSize(80, 28)
        closeBtn2:SetPoint("BOTTOM", popup, "BOTTOM", 60, 15)

        exportPopup = popup
    end

    exportPopup.EditBox:SetText(encoded or "")
    exportPopup.Title:SetText((titleText and titleText ~= "") and titleText or ("|cff00ff80" .. L["导出成功"] .. "|r - " .. tostring(configName or "")))
    exportPopup.Hint:SetText((hintText and hintText ~= "") and hintText or ("|cffffd100Ctrl+C|r " .. L["复制并自动关闭，或点击"] .. " |cffffd100" .. L["全选复制"] .. "|r " .. L["按钮"]))
    exportPopup.CopyHint:Hide()
    exportPopup:Show()
    exportPopup.EditBox:SetFocus()
    exportPopup.EditBox:HighlightText()
end

local function ShowBuiltInAuthorPopup(request, items, onAccept)
    if not builtInAuthorPopup then
        local popup = CreateFrame("Frame", "ExBoss_BuiltInAuthorPopup", UIParent, "BackdropTemplate")
        popup:SetSize(420, 180)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        popup:SetBackdropBorderColor(unpack(THEME.Border))
        popup:EnableMouse(true)
        if not tContains(UISpecialFrames, "ExBoss_BuiltInAuthorPopup") then
            table.insert(UISpecialFrames, "ExBoss_BuiltInAuthorPopup")
        end

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        title:SetPoint("TOP", 0, -16)
        title:SetText("|cff00ff80" .. L["选择内置作者"] .. "|r")

        local desc = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", 20, -48)
        desc:SetPoint("TOPRIGHT", -20, -48)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(unpack(THEME.TextSub))
        desc:SetText(L["选择要生成到哪个内置作者文件。"])

        local warn = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        warn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
        warn:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -8)
        warn:SetJustifyH("LEFT")
        warn:SetTextColor(1, 0.82, 0.35)
        warn:SetText(L["注意：这是给内置作者使用的选项。"])

        local EXUI = _G.ExwindTools and _G.ExwindTools.UI
        if EXUI and EXUI.CreateDropdown then
            popup.dropdown = EXUI:CreateDropdown(popup, 320, L["内置作者"], {}, "", function(value)
                popup._selectedValue = tostring(value or "")
                popup._selectedLabel = popup._selectedValue
                for i = 1, #(popup._items or {}) do
                    local row = popup._items[i]
                    if tostring(row[2]) == popup._selectedValue then
                        popup._selectedLabel = tostring(row[1])
                        break
                    end
                end
            end)
            popup.dropdown:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -104)
        end

        popup.confirm = CreateSmallButton(popup, L["确认"], function()
            if type(popup._onAccept) ~= "function" then
                return
            end
            local key = tostring(popup._selectedValue or "")
            if key == "" then
                return
            end
            local name = tostring(popup._selectedLabel or key)
            local req = popup._request
            popup:Hide()
            popup._onAccept(req, key, name)
        end)
        popup.confirm:SetSize(90, 30)
        popup.confirm:SetPoint("BOTTOM", popup, "BOTTOM", -56, 18)

        popup.cancel = CreateSmallButton(popup, L["取消"], function()
            popup:Hide()
        end)
        popup.cancel:SetSize(90, 30)
        popup.cancel:SetPoint("LEFT", popup.confirm, "RIGHT", 20, 0)

        builtInAuthorPopup = popup
    end

    builtInAuthorPopup._request = request
    builtInAuthorPopup._items = items or {}
    builtInAuthorPopup._onAccept = onAccept

    local first = items and items[1] or nil
    builtInAuthorPopup._selectedValue = tostring(first and first[2] or "")
    builtInAuthorPopup._selectedLabel = tostring(first and first[1] or "")

    if builtInAuthorPopup.dropdown then
        builtInAuthorPopup.dropdown._items = items or {}
        builtInAuthorPopup.dropdown._currentValue = builtInAuthorPopup._selectedValue
        builtInAuthorPopup.dropdown:SetText(builtInAuthorPopup._selectedLabel ~= "" and builtInAuthorPopup._selectedLabel or L["无"])
        if builtInAuthorPopup.dropdown.Enable and builtInAuthorPopup.dropdown.Disable then
            if first then
                builtInAuthorPopup.dropdown:Enable()
            else
                builtInAuthorPopup.dropdown:Disable()
            end
        end
    end

    builtInAuthorPopup:Show()
end

-- ─── 模块级状态 ───────────────────────────────────────────────

local scrollFrame
local scrollChild

local SLOT_ROWS = {
    { key = "raid_tank",  label = L["团本坦克"] },
    { key = "raid_dps",   label = L["团本DPS"]  },
    { key = "raid_heal",  label = L["团本治疗"] },
    { key = "mplus_tank", label = L["大米坦克"] },
    { key = "mplus_dps",  label = L["大米DPS"]  },
    { key = "mplus_heal", label = L["大米治疗"] },
}

local exportNameBox
local exportNoteBox
local exportAppearanceCheck
local exportTrashCDCheck
local exportSlotChecks = {}
local exportStatus

local importInputBox     -- CreateMultiLineEditBox 返回的 container
local importSummaryLeft
local importSummaryRight
local importAppearanceCheck
local importTrashCDCheck
local importSlotChecks = {}
local importNamePrefixBox
local importStatus

local manageProfileDropdown
local manageNameBox
local manageStatus
local manageInfo
local manageRenameBtn
local manageDeleteBtn
local manageTitleText

local parsedPayload = nil

-- ─── 删除确认弹窗 ─────────────────────────────────────────────

local function ShowDeleteProfileConfirm(profileKey, profileName, onAccept)
    if not StaticPopupDialogs or not StaticPopup_Show then
        if type(onAccept) == "function" then onAccept(profileKey) end
        return
    end
    local dialogKey = "EXBOSS_DELETE_PROFILE_CONFIRM"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["确认删除方案：%s ？"],
            button1 = L["删除"],
            button2 = L["取消"],
            OnAccept = function(_, data)
                if type(data) == "table" and type(data.onAccept) == "function" then
                    data.onAccept(data.profileKey)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(dialogKey, tostring(profileName or profileKey), nil, {
        profileKey = profileKey,
        onAccept   = onAccept,
    })
end

-- ─── 复选框 GetChecked 工具 ───────────────────────────────────

local function CBChecked(cb)
    if not cb then return false end
    if cb.GetChecked then return cb:GetChecked() end
    if cb.checkbox and cb.checkbox.GetChecked then return cb.checkbox:GetChecked() end
    return false
end

local function SetCBChecked(cb, value)
    if not cb then return end
    if cb.SetChecked then
        cb:SetChecked(value == true)
        return
    end
    if cb.checkbox and cb.checkbox.SetChecked then
        cb.checkbox:SetChecked(value == true)
    end
end

local function GetCheckboxButton(cb)
    if type(cb) ~= "table" then
        return nil
    end
    if cb.checkbox then
        return cb.checkbox
    end
    return cb
end

-- ─── 导出逻辑 ─────────────────────────────────────────────────

local function BuildExportRequest()
    local inclAppearance = CBChecked(exportAppearanceCheck)
    local inclTrashCD = CBChecked(exportTrashCDCheck)
    local includeSlots = {}
    for _, row in ipairs(SLOT_ROWS) do
        includeSlots[row.key] = CBChecked(exportSlotChecks[row.key])
    end
    local selectedCount = 0
    if inclAppearance then
        selectedCount = selectedCount + 1
    end
    if inclTrashCD then
        selectedCount = selectedCount + 1
    end
    local selectedSlotKey = nil
    for slotKey, enabled in pairs(includeSlots) do
        if enabled == true then
            selectedCount = selectedCount + 1
            selectedSlotKey = slotKey
        end
    end

    if selectedCount == 0 then
        return nil, L["请先勾选一个导出目标"]
    end

    local configName = Trim(exportNameBox and exportNameBox:GetText() or "")
    local note       = Trim(exportNoteBox  and exportNoteBox:GetText()  or "")
    if configName == "" or configName == L["未命名配置"] then configName = L["未命名配置"] end
    return {
        includeAppearance = inclAppearance,
        includeTrashCD    = inclTrashCD,
        includeSlots      = includeSlots,
        configName        = configName,
        note              = note,
        authorName        = configName,
        selectedSlotKey   = selectedSlotKey,
    }, nil
end

local function BuildLuaExportRequest()
    local request, requestErr = BuildExportRequest()
    if not request then
        return nil, requestErr
    end

    local selectedCount = 0
    if request.includeAppearance == true then
        selectedCount = selectedCount + 1
    end
    if request.includeTrashCD == true then
        selectedCount = selectedCount + 1
    end
    for _, row in ipairs(SLOT_ROWS) do
        if type(request.includeSlots) == "table" and request.includeSlots[row.key] == true then
            selectedCount = selectedCount + 1
        end
    end

    if selectedCount > 1 then
        return nil, L["导出Lua一次只能选择一个目标"]
    end

    return request, nil
end

local function GetBuiltInBossAuthorItems(slotKey)
    local items, seen = {}, {}
    local root = _G.EXBOSS_AUTHOR_PRESETS
    local slots = type(root) == "table" and type(root.slots) == "table" and root.slots or nil
    local slot = slots and slots[tostring(slotKey or "")]
    if type(slot) ~= "table" then
        return items
    end
    for key, preset in pairs(slot) do
        if type(preset) == "table" and preset.builtIn == true then
            local value = tostring(key or "")
            if value ~= "" and not seen[value] then
                seen[value] = true
                items[#items + 1] = {
                    tostring(preset.name or preset.author or value),
                    value,
                }
            end
        end
    end
    table.sort(items, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
    return items
end

local function GetAllBuiltInBossAuthorItems()
    local items, seen = {}, {}
    local root = _G.EXBOSS_AUTHOR_PRESETS
    local slots = type(root) == "table" and type(root.slots) == "table" and root.slots or nil
    if type(slots) ~= "table" then
        return items
    end
    for _, slot in pairs(slots) do
        if type(slot) == "table" then
            for key, preset in pairs(slot) do
                if type(preset) == "table" and preset.builtIn == true then
                    local value = tostring(key or "")
                    if value ~= "" and not seen[value] then
                        seen[value] = true
                        items[#items + 1] = {
                            tostring(preset.name or preset.author or value),
                            value,
                        }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
    return items
end

local function GetBuiltInPresetItems(kind)
    local api = _G.EXBossData
    if type(api) ~= "table" then
        return {}
    end
    local fn = (kind == "settings") and api.GetSettingsPluginPresetList or api.GetTrashPluginPresetList
    if type(fn) ~= "function" then
        return {}
    end
    local ok, rows = pcall(fn)
    if not ok or type(rows) ~= "table" then
        return {}
    end
    local items, seen = {}, {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and row.builtIn == true then
            local value = tostring(row.authorKey or row.authorName or row.pluginKey or "")
            if value ~= "" and not seen[value] then
                seen[value] = true
                items[#items + 1] = {
                    tostring(row.authorName or row.title or value),
                    value,
                }
            end
        end
    end
    table.sort(items, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
    if #items == 0 then
        return GetAllBuiltInBossAuthorItems()
    end
    return items
end

local function BuildBuiltInAuthorItems(request)
    request = type(request) == "table" and request or {}
    if request.includeAppearance == true and request.includeTrashCD ~= true then
        local hasSlot = false
        for _, row in ipairs(SLOT_ROWS) do
            if request.includeSlots and request.includeSlots[row.key] == true then
                hasSlot = true
                break
            end
        end
        if not hasSlot then
            return GetBuiltInPresetItems("settings")
        end
    end
    if request.includeTrashCD == true and request.includeAppearance ~= true then
        local hasSlot = false
        for _, row in ipairs(SLOT_ROWS) do
            if request.includeSlots and request.includeSlots[row.key] == true then
                hasSlot = true
                break
            end
        end
        if not hasSlot then
            return GetBuiltInPresetItems("trash")
        end
    end
    local slotKey = request.selectedSlotKey
    if slotKey then
        return GetBuiltInBossAuthorItems(slotKey)
    end
    return {}
end

local function GetSingleSelectedExportSlot(includeSlots)
    local selected = nil
    local count = 0
    for _, row in ipairs(SLOT_ROWS) do
        if type(includeSlots) == "table" and includeSlots[row.key] == true then
            selected = row.key
            count = count + 1
        end
    end
    if count == 1 then
        return selected, nil
    end
    if count == 0 then
        return nil, L["请先勾选一个Boss槽位"]
    end
    return nil, L["作者Lua导出一次只能勾选一个Boss槽位"]
end

local function DoExport()
    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end
    local request, requestErr = BuildExportRequest()
    if not request then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(requestErr) .. "|r") end
        return
    end

    local encoded, err = IE:Export(request)

    if not encoded then
        if exportStatus then
            exportStatus:SetText("|cffff6666" .. L["导出失败："] .. "|r" .. tostring(err))
        end
        return
    end

    if exportStatus then exportStatus:SetText("|cff33ee77" .. L["导出成功"] .. "|r") end
    ShowExportPopup(encoded, request.configName)
end

local function DoExportLua()
    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local request, requestErr = BuildLuaExportRequest()
    if not request then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(requestErr) .. "|r") end
        return
    end

    local snippet, err, exportInfo
    if request.includeAppearance == true then
        snippet, err, exportInfo = IE:ExportPluginSettingsPageSnippet(request)
    elseif request.includeTrashCD == true then
        snippet, err, exportInfo = IE:ExportPluginTrashConfigSnippet(request)
    else
        snippet, err, exportInfo = IE:ExportPluginAuthorSlotSnippet(request)
    end

    if not snippet then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导出失败："] .. "|r" .. tostring(err)) end
        return
    end

    if exportStatus then exportStatus:SetText("|cff33ee77" .. L["作者插件Lua已生成"] .. "|r") end
    local titleText = string.format("|cff00ff80%s|r", L["导出作者插件Lua"])
    local hintText = string.format("%s %s", L["把内容直接粘贴到对应作者文件："], tostring(exportInfo and exportInfo.targetPath or ""))
    ShowExportPopup(snippet, request.configName, titleText, hintText)
end

local function DoExportBuiltInLua()
    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local request, requestErr = BuildLuaExportRequest()
    if not request then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(requestErr) .. "|r") end
        return
    end

    local items = BuildBuiltInAuthorItems(request)
    if #items == 0 then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["当前没有可用的内置作者"] .. "|r") end
        return
    end

    ShowBuiltInAuthorPopup(request, items, function(req, builtInAuthorKey, builtInAuthorName)
        req.builtInAuthorKey = builtInAuthorKey
        req.builtInAuthorName = builtInAuthorName

        local snippet, err, exportInfo
        if req.includeAppearance == true then
            snippet, err, exportInfo = IE:ExportBuiltInSettingsPageSnippet(req)
        elseif req.includeTrashCD == true then
            snippet, err, exportInfo = IE:ExportBuiltInTrashConfigSnippet(req)
        else
            snippet, err, exportInfo = IE:ExportBuiltInAuthorSlotSnippet(req)
        end

        if not snippet then
            if exportStatus then
                exportStatus:SetText("|cffff6666" .. L["导出失败："] .. "|r" .. tostring(err))
            end
            return
        end

        if exportStatus then
            exportStatus:SetText("|cff33ee77" .. L["内置作者Lua已生成"] .. "|r")
        end

        local titleText = string.format(
            "|cff00ff80%s|r - %s",
            L["导出内置作者Lua"],
            tostring(exportInfo and exportInfo.authorKey or builtInAuthorKey)
        )
        local hintText = string.format(
            "%s %s",
            L["把内容直接粘贴到对应作者文件："],
            tostring(exportInfo and exportInfo.targetPath or "")
        )
        ShowExportPopup(snippet, exportInfo and exportInfo.authorKey or req.configName, titleText, hintText)
    end)
end

local function DoExportPluginAuthorSlot()
    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local request, requestErr = BuildExportRequest()
    if not request then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(requestErr) .. "|r") end
        return
    end

    if request.includeAppearance == true then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["作者Lua导出不包含设置页外观"] .. "|r") end
        return
    end

    if request.includeTrashCD == true then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["作者Lua导出不包含小怪CD"] .. "|r") end
        return
    end

    local _, slotErr = GetSingleSelectedExportSlot(request.includeSlots)
    if slotErr then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(slotErr) .. "|r") end
        return
    end

    local snippet, err, exportInfo = IE:ExportPluginAuthorSlotSnippet(request)
    if not snippet then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导出失败："] .. "|r" .. tostring(err)) end
        return
    end

    if exportStatus then exportStatus:SetText("|cff33ee77" .. L["作者插件Lua已生成"] .. "|r") end
    local titleText = string.format("|cff00ff80%s|r", L["导出作者插件Lua"])
    local hintText = string.format("%s %s", L["把内容直接粘贴到对应作者文件："], tostring(exportInfo and exportInfo.targetPath or ""))
    ShowExportPopup(snippet, request.configName, titleText, hintText)
end

local function DoExportPluginTrashConfig()
    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local request, requestErr = BuildExportRequest()
    if not request then
        if exportStatus then exportStatus:SetText("|cffff6666" .. tostring(requestErr) .. "|r") end
        return
    end

    if request.includeAppearance == true then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["小怪作者Lua导出不包含设置页外观"] .. "|r") end
        return
    end

    if request.includeTrashCD ~= true then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["请先勾选小怪CD设置"] .. "|r") end
        return
    end

    for _, enabled in pairs(request.includeSlots or {}) do
        if enabled == true then
            if exportStatus then exportStatus:SetText("|cffff6666" .. L["小怪作者Lua导出不包含Boss槽位"] .. "|r") end
            return
        end
    end

    local snippet, err, exportInfo = IE:ExportPluginTrashConfigSnippet(request)
    if not snippet then
        if exportStatus then exportStatus:SetText("|cffff6666" .. L["导出失败："] .. "|r" .. tostring(err)) end
        return
    end

    if exportStatus then exportStatus:SetText("|cff33ee77" .. L["小怪作者Lua已生成"] .. "|r") end
    local titleText = string.format("|cff00ff80%s|r", L["导出小怪作者Lua"])
    local hintText = string.format("%s %s", L["把内容直接粘贴到对应作者文件："], tostring(exportInfo and exportInfo.targetPath or ""))
    ShowExportPopup(snippet, request.configName, titleText, hintText)
end

-- ─── 导入解析 ─────────────────────────────────────────────────

local function ParseImport()
    parsedPayload = nil

    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if importStatus then importStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local raw = Trim(importInputBox and importInputBox:GetText() or "")
    if raw == "" then
        if importStatus then importStatus:SetText("|cffff6666" .. L["请先粘贴导出字符串"] .. "|r") end
        return
    end

    local payload, err = IE:DecodePayload(raw)
    if not payload then
        if importStatus then
            importStatus:SetText("|cffff6666" .. L["解析失败："] .. "|r" .. tostring(err))
        end
        return
    end

    parsedPayload = payload

    local summary, sumErr = IE:GetImportSummary(payload)
    if not summary then
        if importStatus then
            importStatus:SetText("|cffff6666" .. L["读取摘要失败："] .. "|r" .. tostring(sumErr))
        end
        return
    end

    if importSummaryLeft and importSummaryRight then
        local leftLines = {}
        local rightLines = {}
        leftLines[#leftLines+1] = string.format("|cffffd16d%s|r%s", L["配置名："], tostring(summary.configName))
        leftLines[#leftLines+1] = string.format("|cffffd16d%s|r%s", L["导出者："], tostring(summary.exporter))
        if summary.exportedAt and summary.exportedAt ~= "" then
            leftLines[#leftLines+1] = string.format("|cffffd16d%s|r%s", L["时间："], tostring(summary.exportedAt))
        end
        if summary.note and summary.note ~= "" then
            leftLines[#leftLines+1] = string.format("|cffffd16d%s|r%s", L["备注："], tostring(summary.note))
        end
        leftLines[#leftLines+1] = ""
        leftLines[#leftLines+1] = string.format("%s%s",
            L["设置页配置："], summary.hasAppearance and "|cff33ee77" .. L["包含"] .. "|r" or "|cffaaaaaa" .. L["无"] .. "|r")
        leftLines[#leftLines+1] = string.format("%s%s",
            L["小怪CD设置："], summary.hasTrashCD and "|cff33ee77" .. L["包含"] .. "|r" or "|cffaaaaaa" .. L["无"] .. "|r")
        leftLines[#leftLines+1] = string.format("%s%s%s",
            L["大米配置："],
            summary.hasMplus and "|cff33ee77" .. L["包含"] .. "|r" or "|cffaaaaaa" .. L["无"] .. "|r",
            summary.hasMplus and string.format(L[" (%d 条事件)"], summary.mplusEventCount) or "")
        leftLines[#leftLines+1] = string.format("%s%s%s",
            L["团本配置："],
            summary.hasRaid and "|cff33ee77" .. L["包含"] .. "|r" or "|cffaaaaaa" .. L["无"] .. "|r",
            summary.hasRaid and string.format(L[" (%d 条事件)"], summary.raidEventCount) or "")

        for _, row in ipairs(SLOT_ROWS) do
            if summary.slotAvailability and summary.slotAvailability[row.key] then
                local count = summary.slotEventCount and summary.slotEventCount[row.key] or 0
                rightLines[#rightLines+1] = string.format("%s%s|cff33ee77%s|r%s", row.label, L["："], L["包含"], string.format(L[" (%d 条事件)"], count))
            else
                rightLines[#rightLines+1] = string.format("%s%s|cffaaaaaa%s|r", row.label, L["："], L["无"])
            end
        end
        importSummaryLeft:SetText(table.concat(leftLines, "\n"))
        importSummaryRight:SetText(table.concat(rightLines, "\n"))
    end

    local function SetCB(cb, enabled)
        if not cb then return end
        if cb.SetEnabled then cb:SetEnabled(enabled)
        elseif cb.checkbox then
            if enabled then cb.checkbox:Enable() else cb.checkbox:Disable() end
            cb:SetAlpha(enabled and 1 or 0.45)
        end
        if not enabled then
            if cb.SetChecked then cb:SetChecked(false)
            elseif cb.checkbox and cb.checkbox.SetChecked then cb.checkbox:SetChecked(false) end
        end
    end
    SetCB(importAppearanceCheck, summary.hasAppearance)
    SetCB(importTrashCDCheck, summary.hasTrashCD == true)
    for _, row in ipairs(SLOT_ROWS) do
        SetCB(importSlotChecks[row.key], summary.slotAvailability and summary.slotAvailability[row.key] == true)
    end

    if importStatus then
        importStatus:SetText("|cff33ee77" .. L["解析成功，选择要导入的内容后点击[执行导入]"] .. "|r")
    end
end

-- ─── 导入执行 ─────────────────────────────────────────────────

local function DoImport()
    if not parsedPayload then
        if importStatus then importStatus:SetText("|cffff6666" .. L["请先点击[解析]按钮"] .. "|r") end
        return
    end

    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not IE then
        if importStatus then importStatus:SetText("|cffff6666" .. L["导入导出模块未加载"] .. "|r") end
        return
    end

    local doAppearance = CBChecked(importAppearanceCheck)
    local doTrashCD = CBChecked(importTrashCDCheck)
    local importSlots = {}
    for _, row in ipairs(SLOT_ROWS) do
        importSlots[row.key] = CBChecked(importSlotChecks[row.key])
    end
    local hasSlot = false
    for _, enabled in pairs(importSlots) do
        if enabled == true then
            hasSlot = true
            break
        end
    end

    if not doAppearance and not doTrashCD and not hasSlot then
        if importStatus then importStatus:SetText("|cffff6666" .. L["请至少勾选一项导入内容"] .. "|r") end
        return
    end

    local namePrefix = Trim(importNamePrefixBox and importNamePrefixBox:GetText() or "")

    local ok, msg = IE:Import(parsedPayload, {
        importAppearance = doAppearance,
        importTrashCD    = doTrashCD,
        importSlots      = importSlots,
        namePrefix       = namePrefix ~= "" and namePrefix or nil,
    })

    if importStatus then
        if ok then
            importStatus:SetText("|cff33ee77" .. L["导入成功："] .. "|r" .. tostring(msg))
        else
            importStatus:SetText("|cffff6666" .. L["导入失败："] .. "|r" .. tostring(msg))
        end
    end

    RefreshManagePanel()
end

-- ─── 管理区刷新 ───────────────────────────────────────────────

local function BuildManageProfileItems()
    local items = {}
    local bossCfg = ExBoss and ExBoss.BossConfig
    if not (type(bossCfg) == "table" and type(bossCfg.GetManagedAuthorProfiles) == "function") then
        return items
    end
    bossCfg:Ensure()
    local list = bossCfg:GetManagedAuthorProfiles() or {}
    for i = 1, #list do
        local row = list[i]
        if type(row) == "table" then
            items[#items+1] = {
                tostring(row.displayName or row.authorKey or ""),
                tostring(row.authorKey or ""),
            }
        end
    end
    return items
end

function RefreshManagePanel()
    if not manageProfileDropdown then return end
    local bossCfg = ExBoss and ExBoss.BossConfig
    if not (type(bossCfg) == "table" and type(bossCfg.GetManagedAuthorProfiles) == "function") then
        return
    end
    bossCfg:Ensure()

    local items = BuildManageProfileItems()
    manageProfileDropdown._items = items
    local currentKey = manageProfileDropdown._currentValue

    local found = false
    for _, row in ipairs(items) do
        if row[2] == currentKey then found = true; break end
    end
    if not found then
        currentKey = (items[1] and items[1][2]) or ""
        manageProfileDropdown._currentValue = currentKey
        manageProfileDropdown:SetText(items[1] and items[1][1] or "(无方案)")
    end

    if manageInfo and currentKey ~= "" then
        local summary = bossCfg:GetManagedAuthorProfiles() or {}
        local found
        for i = 1, #summary do
            local row = summary[i]
            if row.authorKey == currentKey then
                found = row
                break
            end
        end
        if found then
            local slotNames = {}
            if type(found.slots) == "table" then
                for _, slotKey in ipairs(found.slots) do
                    slotNames[#slotNames + 1] = tostring(bossCfg:GetSlotLabel(slotKey))
                end
            end
            manageInfo:SetText(string.format(
                L["作者方案：%s    槽位：%s"],
                tostring(found.displayName or found.authorKey or ""),
                (#slotNames > 0 and table.concat(slotNames, "、") or "-")
            ))
        else
            manageInfo:SetText("")
        end
    end

    if manageRenameBtn then
        if currentKey ~= "" then manageRenameBtn:Enable() else manageRenameBtn:Disable() end
    end
    if manageDeleteBtn then
        if currentKey ~= "" then manageDeleteBtn:Enable() else manageDeleteBtn:Disable() end
    end
    if manageNameBox then
        manageNameBox:SetText(currentKey or "")
    end
end

-- ─── Section 背景 ─────────────────────────────────────────────

local function SectionBg(parent, title, topR, topG, topB)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(unpack(THEME.Background))
    f:SetBackdropBorderColor(unpack(THEME.Border))

    local bar = f:CreateTexture(nil, "BORDER")
    bar:SetColorTexture(topR or 1, topG or 0.82, topB or 0.22, 0.90)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -6)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    if title and title ~= "" then
        local fs = f:CreateFontString(nil, "OVERLAY")
        if ExwindTools.MAIN_FONT then
            fs:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
        else
            fs:SetFontObject("GameFontNormal")
        end
        fs:SetPoint("TOPLEFT", 14, -14)
        fs:SetText(title)
        fs:SetTextColor(topR or 1, topG or 0.82, topB or 0.22)
        f._titleFS = fs
    end
    return f
end

-- ─── 照抄单行 InputBox（GridInput 风格）────────────────────────

local function CreateSingleLineInput(parent, w, placeholder)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w or 300, 28)
    eb:SetBackdrop(TOOLTIP_BACKDROP)
    eb:SetBackdropColor(0, 0, 0, 0.6)
    eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetMaxLetters(128)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.64, 0.19, 0.79, 1)
        if placeholder and self:GetText() == placeholder then self:SetText("") end
        self:SetTextColor(unpack(THEME.TextMain))
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        if placeholder and Trim(self:GetText()) == "" then
            self:SetText(placeholder)
            self:SetTextColor(unpack(THEME.TextDim))
        end
    end)
    if placeholder then
        eb:SetText(placeholder)
        eb:SetTextColor(unpack(THEME.TextDim))
    end
    return eb
end

-- ─── MakeCheckbox ─────────────────────────────────────────────

local function MakeCheckbox(parent, label, defaultVal)
    local EXUI = _G.ExwindTools and _G.ExwindTools.UI
    if EXUI and EXUI.CreateCheckbox then
        local cb = EXUI:CreateCheckbox(parent, label, defaultVal, nil)
        if not cb.GetChecked then
            function cb:GetChecked()
                if self.checkbox and self.checkbox.GetChecked then return self.checkbox:GetChecked() end
                return false
            end
        end
        if not cb.SetChecked then
            function cb:SetChecked(v)
                if self.checkbox and self.checkbox.SetChecked then self.checkbox:SetChecked(v) end
            end
        end
        if not cb.SetEnabled then
            function cb:SetEnabled(v)
                if self.checkbox then
                    if v then self.checkbox:Enable() else self.checkbox:Disable() end
                end
                self:SetAlpha(v and 1 or 0.45)
            end
        end
        return cb
    end
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label or "")
    fs:SetTextColor(unpack(THEME.TextMain))
    cb:SetChecked(defaultVal == true)
    return cb
end

-- ─── Label 小工具 ─────────────────────────────────────────────

local function MakeLabel(parent, text, isSmall)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if isSmall then
        fs:SetFontObject("GameFontHighlightSmall")
    else
        fs:SetFontObject("GameFontHighlight")
    end
    fs:SetText(text or "")
    fs:SetTextColor(unpack(THEME.TextSub))
    fs:SetJustifyH("LEFT")
    return fs
end

-- ─── 构建 UI ──────────────────────────────────────────────────

local uiBuilt = false

local function EnsureUI(contentFrame)
    if uiBuilt and scrollFrame and scrollFrame:GetParent() == contentFrame then return end
    uiBuilt = false

    if scrollFrame then
        scrollFrame:Hide()
        scrollFrame:SetParent(UIParent)
    end

    local EXUI = _G.ExwindTools and _G.ExwindTools.UI

    -- 滚动容器
    scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
    end
    scrollFrame:SetPoint("TOPLEFT",     contentFrame, "TOPLEFT",     4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -26, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(contentFrame:GetWidth() - 40, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local fullW = (contentFrame:GetWidth() or 1100) - 50
    local colW  = math.floor((fullW - 20) / 2) - 6

    local y = -16

    -- ══ 导出区 ═══════════════════════════════════════════════
    local expSec = SectionBg(scrollChild, L["导出"], THEME.Primary[1], THEME.Primary[2], THEME.Primary[3])
    expSec:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, y)
    expSec:SetWidth(colW)

    local ey = -38

    local nameLbl = MakeLabel(expSec, L["配置名称"], true)
    nameLbl:SetPoint("TOPLEFT", 14, ey)
    ey = ey - 18

    exportNameBox = CreateSingleLineInput(expSec, colW - 28, L["未命名配置"])
    exportNameBox:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 38

    local noteLbl = MakeLabel(expSec, L["备注（可选）"], true)
    noteLbl:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 18

    exportNoteBox = CreateSingleLineInput(expSec, colW - 28, L["无"])
    exportNoteBox:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 38

    local inclLbl = MakeLabel(expSec, L["导出内容"], true)
    inclLbl:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 24

    exportAppearanceCheck = MakeCheckbox(expSec, L["设置页全部设置"], false)
    exportAppearanceCheck:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 28

    exportTrashCDCheck = MakeCheckbox(expSec, L["小怪CD设置"], false)
    exportTrashCDCheck:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
    ey = ey - 28

    exportSlotChecks = {}
    for _, row in ipairs(SLOT_ROWS) do
        local cb = MakeCheckbox(expSec, row.label, false)
        cb:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)
        exportSlotChecks[row.key] = cb
        ey = ey - 28
    end
    ey = ey - 16

    local expBtn = CreateActionButton(expSec, L["导出字符串"], DoExport)
    expBtn:SetSize(140, 36)
    expBtn:SetPoint("TOPLEFT", expSec, "TOPLEFT", 14, ey)

    local expLuaBtn = CreateActionButton(expSec, L["作者插件Lua"], DoExportLua)
    expLuaBtn:SetSize(140, 36)
    expLuaBtn:SetPoint("LEFT", expBtn, "RIGHT", 10, 0)

    local expBuiltInLuaBtn = CreateActionButton(expSec, L["内置作者Lua"], DoExportBuiltInLua)
    expBuiltInLuaBtn:SetSize(140, 36)
    expBuiltInLuaBtn:SetPoint("LEFT", expLuaBtn, "RIGHT", 10, 0)

    ey = ey - 48

    exportStatus = expSec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    exportStatus:SetPoint("TOPLEFT",  expSec, "TOPLEFT",  14, ey)
    exportStatus:SetPoint("TOPRIGHT", expSec, "TOPRIGHT", -14, 0)
    exportStatus:SetJustifyH("LEFT")
    exportStatus:SetTextColor(unpack(THEME.TextSub))
    exportStatus:SetText("")
    ey = ey - 26

    expSec:SetHeight(math.abs(ey) + 16)

    -- ══ 导入区 ═══════════════════════════════════════════════
    local impSec = SectionBg(scrollChild, L["导入"], THEME.Success[1], THEME.Success[2], THEME.Success[3])
    impSec:SetPoint("TOPLEFT", expSec, "TOPRIGHT", 20, 0)
    impSec:SetWidth(colW)

    local iy = -38

    local strLbl = MakeLabel(impSec, L["粘贴导出字符串"], true)
    strLbl:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 20

    -- 照抄 CreateEditBox 多行模式
    importInputBox = CreateMultiLineEditBox(impSec, colW - 28, 80)
    importInputBox:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 90

    local parseBtn = CreateActionButton(impSec, L["解析"], ParseImport)
    parseBtn:SetSize(100, 32)
    parseBtn:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 42

    local summaryFrame = CreateFrame("Frame", nil, impSec)
    summaryFrame:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    summaryFrame:SetSize(colW - 28, 150)

    importSummaryLeft = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importSummaryLeft:SetPoint("TOPLEFT", summaryFrame, "TOPLEFT", 0, 0)
    importSummaryLeft:SetWidth(math.floor((colW - 46) * 0.48))
    importSummaryLeft:SetJustifyH("LEFT")
    importSummaryLeft:SetJustifyV("TOP")
    importSummaryLeft:SetTextColor(unpack(THEME.TextMain))
    importSummaryLeft:SetText("")

    importSummaryRight = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importSummaryRight:SetPoint("TOPRIGHT", summaryFrame, "TOPRIGHT", 0, 0)
    importSummaryRight:SetWidth(math.floor((colW - 46) * 0.48))
    importSummaryRight:SetJustifyH("LEFT")
    importSummaryRight:SetJustifyV("TOP")
    importSummaryRight:SetTextColor(unpack(THEME.TextMain))
    importSummaryRight:SetText("")

    iy = iy - 160

    local divLine = impSec:CreateTexture(nil, "ARTWORK")
    divLine:SetHeight(1)
    divLine:SetColorTexture(unpack(THEME.Border))
    divLine:SetPoint("TOPLEFT",  impSec, "TOPLEFT",  14, iy)
    divLine:SetPoint("TOPRIGHT", impSec, "TOPRIGHT", -14, 0)
    iy = iy - 16

    local inclLbl2 = MakeLabel(impSec, L["导入内容"], true)
    inclLbl2:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 24

    importAppearanceCheck = MakeCheckbox(impSec, L["导入设置页全部设置（立即应用）"], false)
    importAppearanceCheck:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    if importAppearanceCheck.SetEnabled then importAppearanceCheck:SetEnabled(false) end
    iy = iy - 28

    importTrashCDCheck = MakeCheckbox(impSec, L["导入小怪CD设置（全量覆盖）"], false)
    importTrashCDCheck:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    if importTrashCDCheck.SetEnabled then importTrashCDCheck:SetEnabled(false) end
    iy = iy - 28

    importSlotChecks = {}
    for _, row in ipairs(SLOT_ROWS) do
        local cb = MakeCheckbox(impSec, row.label, false)
        cb:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
        if cb.SetEnabled then cb:SetEnabled(false) end
        importSlotChecks[row.key] = cb
        iy = iy - 28
    end
    iy = iy - 10

    local prefixLbl = MakeLabel(impSec, L["导入作者名（留空则使用配置名）"], true)
    prefixLbl:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 20

    importNamePrefixBox = CreateSingleLineInput(impSec, colW - 28)
    importNamePrefixBox:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    importNamePrefixBox:Enable()
    iy = iy - 44

    local impBtn = CreateActionButton(impSec, L["执行导入"], DoImport)
    impBtn:SetSize(140, 36)
    impBtn:SetPoint("TOPLEFT", impSec, "TOPLEFT", 14, iy)
    iy = iy - 44

    importStatus = impSec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatus:SetPoint("TOPLEFT",  impSec, "TOPLEFT",  14, iy)
    importStatus:SetPoint("TOPRIGHT", impSec, "TOPRIGHT", -14, 0)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetTextColor(unpack(THEME.TextSub))
    importStatus:SetText("")
    iy = iy - 26

    local maxH = math.max(math.abs(ey) + 16, math.abs(iy) + 16)
    expSec:SetHeight(maxH)
    impSec:SetHeight(maxH)

    local sectionBottom = y - maxH

    -- ══ 管理区 ═══════════════════════════════════════════════
    local manY = sectionBottom - 20

    local manSec = SectionBg(scrollChild, L["槽位概览"],
        THEME.Success[1]*0.8, THEME.Success[2]*0.8, THEME.Success[3]*0.8)
    manSec:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  10, manY)
    manSec:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, 0)

    local my = -38

    if EXUI and EXUI.CreateDropdown then
        manageProfileDropdown = EXUI:CreateDropdown(manSec, 420, L["选择方案"],
            BuildManageProfileItems(), "", function(value)
                manageProfileDropdown._currentValue = value
                RefreshManagePanel()
            end)
        manageProfileDropdown:SetPoint("TOPLEFT", manSec, "TOPLEFT", 14, my)
        my = my - 44
    end

    manageInfo = manSec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manageInfo:SetPoint("TOPLEFT",  manSec, "TOPLEFT",  14, my)
    manageInfo:SetPoint("TOPRIGHT", manSec, "TOPRIGHT", -14, 0)
    manageInfo:SetJustifyH("LEFT")
    manageInfo:SetTextColor(unpack(THEME.TextMain))
    manageInfo:SetText("")
    my = my - 36

    -- 只读说明
    local renameLbl = MakeLabel(manSec, L["此区域展示所有已导入的作者方案；重命名/删除会作用到整套作者方案。"], true)
    renameLbl:SetPoint("TOPLEFT", manSec, "TOPLEFT", 14, my)
    my = my - 20

    manageNameBox = CreateSingleLineInput(manSec, 320)
    manageNameBox:SetPoint("TOPLEFT", manSec, "TOPLEFT", 14, my)
    manageNameBox:Enable()

    manageRenameBtn = CreateSmallButton(manSec, L["重命名"], function()
        local bossCfg = ExBoss and ExBoss.BossConfig
        local oldKey = manageProfileDropdown and tostring(manageProfileDropdown._currentValue or "") or ""
        local newKey = Trim(manageNameBox and manageNameBox:GetText() or "")
        if not (type(bossCfg) == "table" and type(bossCfg.RenameManagedAuthorProfile) == "function") then
            if manageStatus then manageStatus:SetText("|cffff6666" .. L["Boss 配置模块未加载"] .. "|r") end
            return
        end
        if oldKey == "" then
            if manageStatus then manageStatus:SetText("|cffffcc66" .. L["请选择要重命名的方案。"] .. "|r") end
            return
        end
        if newKey == "" then
            if manageStatus then manageStatus:SetText("|cffffcc66" .. L["请输入新的方案名称。"] .. "|r") end
            return
        end
        local ok, err = bossCfg:RenameManagedAuthorProfile(oldKey, newKey)
        if manageStatus then
            manageStatus:SetText(ok and ("|cff33ee77" .. L["已重命名："] .. "|r" .. tostring(newKey)) or ("|cffff6666" .. L["重命名失败："] .. "|r" .. tostring(err)))
        end
        if ok and manageProfileDropdown then
            manageProfileDropdown._currentValue = newKey
        end
        RefreshManagePanel()
    end)
    manageRenameBtn:SetSize(100, 28)
    manageRenameBtn:SetPoint("LEFT", manageNameBox, "RIGHT", 10, 0)
    my = my - 40

    -- 删除按钮（Danger 色）
    manageDeleteBtn = CreateFrame("Button", nil, manSec, "BackdropTemplate")
    manageDeleteBtn:SetSize(90, 28)
    manageDeleteBtn:SetPoint("TOPLEFT", manSec, "TOPLEFT", 14, my)
    manageDeleteBtn:SetBackdrop(BACKDROP_SIMPLE)
    manageDeleteBtn:SetBackdropColor(THEME.Danger[1]*0.5, THEME.Danger[2]*0.5, THEME.Danger[3]*0.5, 0.9)
    local delFS = manageDeleteBtn:CreateFontString(nil, "OVERLAY")
    delFS:SetFontObject("GameFontNormal")
    delFS:SetPoint("CENTER")
    delFS:SetText(L["删除"])
    delFS:SetTextColor(1, 1, 1, 1)
    manageDeleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(THEME.Danger))
    end)
    manageDeleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.Danger[1]*0.5, THEME.Danger[2]*0.5, THEME.Danger[3]*0.5, 0.9)
    end)
    manageDeleteBtn:SetScript("OnClick", function()
        local bossCfg = ExBoss and ExBoss.BossConfig
        local currentKey = manageProfileDropdown and tostring(manageProfileDropdown._currentValue or "") or ""
        if not (type(bossCfg) == "table" and type(bossCfg.DeleteManagedAuthorProfile) == "function") then
            if manageStatus then manageStatus:SetText("|cffff6666" .. L["Boss 配置模块未加载"] .. "|r") end
            return
        end
        if currentKey == "" then
            if manageStatus then manageStatus:SetText("|cffffcc66" .. L["请选择要删除的方案。"] .. "|r") end
            return
        end
        ShowDeleteProfileConfirm(currentKey, currentKey, function(profileKey)
            local ok, err = bossCfg:DeleteManagedAuthorProfile(profileKey)
            if manageStatus then
                manageStatus:SetText(ok and ("|cff33ee77" .. L["已删除："] .. "|r" .. tostring(profileKey)) or ("|cffff6666" .. L["删除失败："] .. "|r" .. tostring(err)))
            end
            if ok and manageProfileDropdown then
                manageProfileDropdown._currentValue = ""
            end
            RefreshManagePanel()
        end)
    end)
    my = my - 44

    manageStatus = manSec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manageStatus:SetPoint("TOPLEFT",  manSec, "TOPLEFT",  14, my)
    manageStatus:SetPoint("TOPRIGHT", manSec, "TOPRIGHT", -14, 0)
    manageStatus:SetJustifyH("LEFT")
    manageStatus:SetTextColor(unpack(THEME.TextSub))
    manageStatus:SetText("")
    my = my - 26

    manSec:SetHeight(math.abs(my) + 16)

    local totalH = math.abs(manY) + math.abs(my) + 40
    scrollChild:SetHeight(totalH)

    uiBuilt = true
end

-- ─── 公开接口 ─────────────────────────────────────────────────

function Page:Render(contentFrame)
    EnsureUI(contentFrame)
    if not scrollFrame then return end
    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT",     contentFrame, "TOPLEFT",     4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -26, 4)
    scrollFrame:Show()
    scrollChild:SetWidth(contentFrame:GetWidth() - 40)
    RefreshManagePanel()
end

function Page:Hide()
    if scrollFrame then scrollFrame:Hide() end
end
