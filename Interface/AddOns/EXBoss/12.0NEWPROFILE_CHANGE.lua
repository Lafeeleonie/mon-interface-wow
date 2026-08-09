---@diagnostic disable: undefined-global

local PROMPT_KEY = "12.0NEWPROFILE_CHANGE"
local TARGET_AUTHOR = "EXWIND_CN"
local TARGET_TRASH_PRESET = "builtin:EXWIND_CN"
local SOURCE_AUTHOR = "PresetConfig"

local SLOT_ORDER = {
    "mplus_tank",
    "mplus_heal",
    "mplus_dps",
}

local SLOT_LABELS = {
    mplus_tank = "大米坦克",
    mplus_heal = "大米治疗",
    mplus_dps = "大米DPS",
}

local PANEL_NAME = "ExBossNewProfileChangePromptFrame"
local promptFrame = nil

local function IsSupportedLocale()
    local locale = tostring(GetLocale() or "")
    return locale == "zhCN" or locale == "zhTW"
end

local function EnsurePromptDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.profileUpgradePrompts = ExBossDB.profileUpgradePrompts or {}
    return ExBossDB.profileUpgradePrompts
end

local function GetPromptState()
    local db = EnsurePromptDB()
    return db[PROMPT_KEY]
end

local function SetPromptState(status)
    local db = EnsurePromptDB()
    db[PROMPT_KEY] = {
        status = tostring(status or ""),
        version = tostring((ExBoss and ExBoss.VERSION) or ""),
        decidedAt = time(),
    }
end

local function GetBossConfig()
    local bossCfg = ExBoss and ExBoss.BossConfig or nil
    if type(bossCfg) ~= "table" then
        return nil
    end
    if type(bossCfg.GetSelectedAuthor) ~= "function" or type(bossCfg.SetSelectedAuthor) ~= "function" or type(bossCfg.GetAuthorItems) ~= "function" then
        return nil
    end
    return bossCfg
end

local function SlotHasAuthor(bossCfg, slotKey, authorKey)
    for _, row in ipairs(bossCfg:GetAuthorItems(slotKey) or {}) do
        if tostring(row[2] or "") == tostring(authorKey or "") then
            return true
        end
    end
    return false
end

local function CollectUpgradeableSlots(bossCfg)
    local slots = {}
    for _, slotKey in ipairs(SLOT_ORDER) do
        local current = tostring(bossCfg:GetSelectedAuthor(slotKey) or "")
        if current == SOURCE_AUTHOR and SlotHasAuthor(bossCfg, slotKey, TARGET_AUTHOR) then
            slots[#slots + 1] = slotKey
        end
    end
    return slots
end

local function BuildSlotText(slots)
    local parts = {}
    for _, slotKey in ipairs(slots or {}) do
        parts[#parts + 1] = SLOT_LABELS[slotKey] or slotKey
    end
    return table.concat(parts, " / ")
end

local function GetTrashStore()
    local store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
    if type(store) ~= "table" then
        return nil
    end
    if type(store.GetPluginPreset) ~= "function" or type(store.ImportPluginPreset) ~= "function" then
        return nil
    end
    return store
end

local function ApplyUpgrade(data)
    local bossCfg = GetBossConfig()
    local trashStore = GetTrashStore()
    if not bossCfg or not trashStore or type(data) ~= "table" then
        return
    end

    local trashPreset = trashStore.GetPluginPreset(TARGET_TRASH_PRESET)
    if type(trashPreset) ~= "table" or type(trashPreset.trashConfig) ~= "table" then
        if ExBoss and ExBoss.Print and type(ExBoss.Print.Say) == "function" then
            ExBoss.Print.Say("新版小怪配置不存在，未执行切换。")
        end
        return
    end

    local trashOk, trashErr = trashStore.ImportPluginPreset(TARGET_TRASH_PRESET)
    if not trashOk then
        if ExBoss and ExBoss.Print and type(ExBoss.Print.Say) == "function" then
            ExBoss.Print.Say("导入新版小怪配置失败: " .. tostring(trashErr or ""))
        end
        return
    end

    local changed = {}
    for _, slotKey in ipairs(data.slots or {}) do
        if tostring(bossCfg:GetSelectedAuthor(slotKey) or "") == SOURCE_AUTHOR and SlotHasAuthor(bossCfg, slotKey, TARGET_AUTHOR) then
            local ok = bossCfg:SetSelectedAuthor(slotKey, TARGET_AUTHOR)
            if ok then
                changed[#changed + 1] = SLOT_LABELS[slotKey] or slotKey
            end
        end
    end

    SetPromptState("accepted")

    local BossPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if BossPage and BossPage.RefreshSpellUI then
        BossPage:RefreshSpellUI()
    end

    local TrashPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TrashCDPage
    if TrashPage and TrashPage.RefreshSpellList then
        TrashPage:RefreshSpellList()
    end
    if TrashPage and TrashPage.RefreshSelectedSpell then
        TrashPage:RefreshSelectedSpell()
    end

    if #changed > 0 and ExBoss and ExBoss.Print and type(ExBoss.Print.Say) == "function" then
        ExBoss.Print.Say("已切换新版配置: " .. table.concat(changed, " / ") .. "，并覆盖导入新版小怪配置。")
    elseif ExBoss and ExBoss.Print and type(ExBoss.Print.Say) == "function" then
        ExBoss.Print.Say("已覆盖导入新版小怪配置。")
    end
end

local function BuildFlatBackdrop()
    return {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    }
end

local function CreateChoiceButton(parent, width, height, text, normalColor, hoverColor)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    button:SetNormalFontObject("GameFontNormalLarge")
    button:SetHighlightFontObject("GameFontHighlightLarge")
    button:SetBackdrop(BuildFlatBackdrop())
    button:SetBackdropColor(normalColor[1], normalColor[2], normalColor[3], 0.95)
    button:SetBackdropBorderColor(0.08, 0.08, 0.08, 0.98)
    button:SetText(text)
    button._normalColor = normalColor
    button._hoverColor = hoverColor
    button:SetScript("OnEnter", function(self)
        local c = self._hoverColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end)
    button:SetScript("OnLeave", function(self)
        local c = self._normalColor
        self:SetBackdropColor(c[1], c[2], c[3], 0.95)
    end)
    button:SetScript("OnMouseDown", function(self)
        self:ClearAllPoints()
        self:SetPoint(self._anchorPoint, self._anchorRelativeTo, self._anchorRelativePoint, self._anchorX, self._anchorY - 1)
    end)
    button:SetScript("OnMouseUp", function(self)
        self:ClearAllPoints()
        self:SetPoint(self._anchorPoint, self._anchorRelativeTo, self._anchorRelativePoint, self._anchorX, self._anchorY)
    end)
    return button
end

local function EnsurePromptFrame()
    if promptFrame then
        return promptFrame
    end

    local frame = CreateFrame("Frame", PANEL_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(560, 350)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(240)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetBackdrop(BuildFlatBackdrop())
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    frame:SetBackdropBorderColor(0.92, 0.56, 0.24, 0.95)
    frame:Hide()

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(40)
    header:SetBackdrop(BuildFlatBackdrop())
    header:SetBackdropColor(0.16, 0.10, 0.06, 0.98)
    header:SetBackdropBorderColor(0.35, 0.22, 0.12, 0.95)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    frame.Header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText("新版大秘境配置")
    frame.Title = title

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    close:SetScript("OnClick", function()
        SetPromptState("skipped")
        frame:Hide()
    end)
    frame.CloseButton = close

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 22, -20)
    text:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -22, -20)
    text:SetPoint("BOTTOM", frame, "BOTTOM", 0, 96)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    text:SetSpacing(8)
    text:SetTextColor(1, 1, 1, 0.98)
    frame.BodyText = text

    local accept = CreateChoiceButton(
        frame,
        190,
        40,
        "启用新配置",
        { 0.13, 0.50, 0.18 },
        { 0.18, 0.62, 0.22 }
    )
    accept._anchorPoint = "BOTTOMLEFT"
    accept._anchorRelativeTo = frame
    accept._anchorRelativePoint = "BOTTOMLEFT"
    accept._anchorX = 56
    accept._anchorY = 24
    accept:SetPoint(accept._anchorPoint, accept._anchorRelativeTo, accept._anchorRelativePoint, accept._anchorX, accept._anchorY)
    frame.AcceptButton = accept

    local cancel = CreateChoiceButton(
        frame,
        190,
        40,
        "使用当前配置",
        { 0.60, 0.12, 0.12 },
        { 0.74, 0.16, 0.16 }
    )
    cancel._anchorPoint = "BOTTOMRIGHT"
    cancel._anchorRelativeTo = frame
    cancel._anchorRelativePoint = "BOTTOMRIGHT"
    cancel._anchorX = -56
    cancel._anchorY = 24
    cancel:SetPoint(cancel._anchorPoint, cancel._anchorRelativeTo, cancel._anchorRelativePoint, cancel._anchorX, cancel._anchorY)
    frame.CancelButton = cancel

    accept:SetScript("OnClick", function()
        ApplyUpgrade(frame._payload)
        frame:Hide()
    end)
    cancel:SetScript("OnClick", function()
        SetPromptState("skipped")
        frame:Hide()
    end)

    if UISpecialFrames then
        table.insert(UISpecialFrames, PANEL_NAME)
    end

    promptFrame = frame
    return frame
end

local function ShowPromptFrame(slots)
    local frame = EnsurePromptFrame()
    frame._payload = { slots = slots }
    frame.BodyText:SetText(
        "EXBOSS 现已更新全新的配置\n"
            .. "新配置参考多位世界顶尖和MDI选手设置综合!\n"
            .. "使用体验提高非常多! ! !\n\n"
            .. "如果你当前配置没有太多修改 建议启用新配置\n"
            .. "如果你已经花费很多时间调试 则建议保留旧配置\n\n"
            .. "PS:所有BOSS设置再切换后仍可以切回当前配置\n"
            .. "PS:所有小怪设置一但切换使用新配置后 则会覆盖! !"
    )
    frame:Show()
    frame:Raise()
end

local function ShowPrompt()
    if not IsSupportedLocale() then
        return
    end
    if GetPromptState() ~= nil then
        return
    end

    local bossCfg = GetBossConfig()
    if not bossCfg then
        return
    end

    local slots = CollectUpgradeableSlots(bossCfg)
    if #slots == 0 then
        return
    end

    ShowPromptFrame(slots)
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(1, ShowPrompt)
end)
