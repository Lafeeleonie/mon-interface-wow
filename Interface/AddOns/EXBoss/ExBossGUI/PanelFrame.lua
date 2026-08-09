---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/PanelFrame.lua
-- 主面板骨架：窗口 + 顶部 Tab + 左侧导航框架 + 右侧内容区
-- 无任何外部依赖（不需要 ExwindTools / ExwindGrid / ExwindFactory）
-- =============================================================

-- print("|cffff4400Ex|r|cff00ccffBoss|r PanelFrame.lua 开始加载")

-- 挂载到 ExBoss.UI.Panel（ExBoss.lua 已预建此表）
local Panel = ExBoss.UI.Panel
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

-- =============================================================
-- 常量
-- =============================================================
local PANEL_W   = 1560
local PANEL_H   = 980
local TAB_H     = 36
local TAB_BAR_Y = -30
local LEFT_W    = 380
local CONTENT_X = LEFT_W + 10

local TABS = {
    { key = "home",          label = L["首页"] },
    { key = "voicepack",     label = L["语音/配置"] },
    { key = "boss",          label = L["副本(首领)"] },
    { key = "trash",         label = L["小怪CD"] },
    { key = "tools",         label = L["小工具"] },
    { key = "globalsettings",label = L["设置"] },
    { key = "importexport",  label = L["导入导出"] },
    { key = "about",         label = L["关于插件"] },
}

-- =============================================================
-- 运行时状态
-- =============================================================
local mainFrame    = nil
local tabButtons   = {}
local tabIndexByKey = {}
local leftFrame    = nil
local contentFrame = nil
local currentTab   = "home"

local GLOBAL_SETTINGS_REDIRECTS = {
    ["timerbar"] = "timerbar",
    ["bunbar"] = "bunbar",
    ["countdown"] = "countdown",
    ["flashtext"] = "flashtext",
    ["flashtextmedium"] = "flashtextmedium",
    ["ringprogress"] = "ringprogress",
    ["iconalert"] = "iconalert",
    ["castprogressbar"] = "castprogressbar",
    ["extrashieldbar"] = "extrashieldbar",
    ["conditions"] = "conditions",
    ["privateauramonitor"] = "privateauramonitor",
    ["targetalert"] = "targetalert",
    ["mythiccast"] = "mythiccast",
    ["spelltarget"] = "spelltarget",
    ["stateicons"] = "stateicons",
    ["interrupttracker"] = "interrupttracker",
    ["dungeonextra"] = "dungeonextra",

    ["ExBoss.TimerBar"] = "timerbar",
    ["ExBoss.BunBar"] = "bunbar",
    ["ExBoss.Countdown"] = "countdown",
    ["ExBoss.FlashText"] = "flashtext",
    ["ExBoss.FlashTextMedium"] = "flashtextmedium",
    ["ExBoss.RingProgress"] = "ringprogress",
    ["ExBoss.IconAlert"] = "iconalert",
    ["ExBoss.CastProgressBar"] = "castprogressbar",
    ["ExBoss.ExtraShieldBar"] = "extrashieldbar",
    ["ExBoss.PrivateAuraMonitor"] = "privateauramonitor",
    ["ExBoss.TargetAlert"] = "targetalert",
    ["ExBoss.Tools.MythicCast"] = "mythiccast",
    ["ExBoss.Tools.SpellTarget"] = "spelltarget",
    ["ExBoss.Tools.StateIcons"] = "stateicons",
    ["ExBoss.Tools.InterruptTracker"] = "interrupttracker",
    ["ExBoss.Boss.MaisaraTrash248690Absorb"] = "dungeonextra",
}

local function IsMDTEnabled()
    if ExBoss and ExBoss.MDT and type(ExBoss.MDT.IsEnabled) == "function" then
        return ExBoss.MDT.IsEnabled()
    end
    return true
end

local function BuildVisibleTabs()
    local out = {}
    for i = 1, #TABS do
        local tabDef = TABS[i]
        if tabDef.key ~= "mdt" or IsMDTEnabled() then
            out[#out + 1] = tabDef
        end
    end
    return out
end

local function NormalizeTabKey(tabKey)
    local requested = tabKey or "boss"
    if GLOBAL_SETTINGS_REDIRECTS[requested] then
        return GLOBAL_SETTINGS_REDIRECTS[requested]
    end
    if requested == "voice" then
        requested = "voicepack"
    end
    if requested == "timeline" then
        requested = "fixedtimeline"
    end
    if requested == "index" then
        requested = "home"
    end
    if requested == "general" then
        requested = "globalsettings"
    end
    if requested == "import" or requested == "export" or requested == "impexp" then
        requested = "importexport"
    end
    if requested == "trashcd" then
        requested = "trash"
    end
    if requested == "tool" or requested == "widgets" or requested == "widget" then
        requested = "tools"
    end
    if requested == "condition" or requested == "conditionspage" then
        requested = "conditions"
    end
    return requested
end

local function IsTabVisible(tabKey)
    local key = NormalizeTabKey(tabKey)
    for i = 1, #TABS do
        local tabDef = TABS[i]
        if tabDef.key == key then
            if key == "mdt" then
                return IsMDTEnabled()
            end
            return true
        end
    end
    return false
end

local function ResolveSafeTab(tabKey)
    local key = NormalizeTabKey(tabKey)
    if IsTabVisible(key) then
        return key
    end
    return "home"
end

local function RefreshEditModeButtonLabel()
    if not mainFrame or not mainFrame._editModeBtn then return end
    local ET = _G.ExwindTools
    local enabled = ET and ET.GlobalEditMode == true
    mainFrame._editModeBtn:SetText(enabled and L["关闭编辑模式"] or L["开启编辑模式"])
end

local function TryHandleChangelogPopupOnUIOpen()
    if not (C_Timer and C_Timer.After) then
        return
    end
    C_Timer.After(0.05, function()
        if mainFrame and mainFrame:IsShown() and ExBoss and ExBoss.HandleChangelogPopupOnUIOpen then
            ExBoss:HandleChangelogPopupOnUIOpen()
        end
    end)
end

local function ShouldUseLeftNav(tabKey)
    return tabKey == "boss" or tabKey == "globalsettings" or tabKey == "tools"
end

local atlasExistCache = {}

local function HasAtlas(atlasName)
    if type(atlasName) ~= "string" or atlasName == "" then
        return false
    end
    local cached = atlasExistCache[atlasName]
    if cached ~= nil then
        return cached
    end
    local ok = true
    if C_Texture and C_Texture.GetAtlasInfo then
        ok = C_Texture.GetAtlasInfo(atlasName) ~= nil
    end
    atlasExistCache[atlasName] = ok and true or false
    return atlasExistCache[atlasName]
end

local function FindScrollBar(scrollFrame)
    if not scrollFrame then
        return nil
    end
    if scrollFrame.ScrollBar then
        return scrollFrame.ScrollBar
    end
    local frameName = scrollFrame.GetName and scrollFrame:GetName()
    if frameName and _G[frameName .. "ScrollBar"] then
        return _G[frameName .. "ScrollBar"]
    end
    local children = { scrollFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child and child.GetObjectType and child:GetObjectType() == "Slider" then
            return child
        end
    end
    return nil
end

local function HideLegacyScrollBar(scrollBar)
    if not scrollBar then
        return
    end
    scrollBar:Hide()
    scrollBar:EnableMouse(false)
    local barName = scrollBar.GetName and scrollBar:GetName()
    local candidates = {
        scrollBar.ScrollUpButton,
        scrollBar.ScrollDownButton,
        scrollBar.ThumbTexture,
        barName and _G[barName .. "ScrollUpButton"] or nil,
        barName and _G[barName .. "ScrollDownButton"] or nil,
        barName and _G[barName .. "ThumbTexture"] or nil,
    }
    for _, obj in ipairs(candidates) do
        if obj then
            obj:Hide()
            if obj.EnableMouse then
                obj:EnableMouse(false)
            end
        end
    end
end

local function EnsureMinimalScrollBarFallback(scrollBar)
    if not scrollBar then
        return
    end

    local track = scrollBar.Track or (scrollBar.GetTrack and scrollBar:GetTrack()) or nil
    if track then
        if not track._exFallbackLine then
            local line = track:CreateTexture(nil, "BACKGROUND")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            line:SetVertexColor(0.18, 0.18, 0.22, 0.95)
            line:SetPoint("TOP", track, "TOP", 0, 0)
            line:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
            line:SetWidth(2)
            track._exFallbackLine = line

            local glow = track:CreateTexture(nil, "BORDER")
            glow:SetTexture("Interface\\Buttons\\WHITE8X8")
            glow:SetVertexColor(0.32, 0.34, 0.42, 0.45)
            glow:SetPoint("TOP", line, "TOP", 0, 1)
            glow:SetPoint("BOTTOM", line, "BOTTOM", 0, -1)
            glow:SetWidth(6)
            track._exFallbackGlow = glow
        end
        track._exFallbackLine:Show()
        track._exFallbackGlow:Show()
    end

    local thumb = (track and track.Thumb) or (scrollBar.GetThumb and scrollBar:GetThumb()) or nil
    if thumb and not thumb._exFallbackBody then
        local body = thumb:CreateTexture(nil, "ARTWORK")
        body:SetTexture("Interface\\Buttons\\WHITE8X8")
        body:SetVertexColor(0.60, 0.64, 0.58, 0.95)
        body:SetPoint("TOP", thumb, "TOP", 0, 0)
        body:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
        body:SetWidth(6)
        thumb._exFallbackBody = body
    end
    if thumb and thumb._exFallbackBody then
        thumb._exFallbackBody:Show()
    end
end

local function ApplyModernScrollBarSkin(scrollFrame)
    if not scrollFrame then
        return
    end
    if not (ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then
        return
    end

    local legacyScrollBar = FindScrollBar(scrollFrame)
    if legacyScrollBar then
        HideLegacyScrollBar(legacyScrollBar)
    end

    local scrollBar = scrollFrame._exModernScrollBar
    if not scrollBar then
        local owner = scrollFrame:GetParent() or UIParent
        local ok, created = pcall(CreateFrame, "EventFrame", nil, owner, "MinimalScrollBar")
        if not ok or not created then
            return
        end
        scrollBar = created
        scrollBar:SetFrameStrata(scrollFrame:GetFrameStrata())
        scrollBar:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
        scrollFrame._exModernScrollBar = scrollBar
        scrollFrame:EnableMouseWheel(true)
        ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
        scrollFrame:HookScript("OnShow", function(self)
            if self._exModernScrollBar then
                self._exModernScrollBar:Show()
            end
        end)
        scrollFrame:HookScript("OnHide", function(self)
            if self._exModernScrollBar then
                self._exModernScrollBar:Hide()
            end
        end)
    end

    local owner = scrollFrame:GetParent() or UIParent
    if scrollBar:GetParent() ~= owner then
        scrollBar:SetParent(owner)
    end
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -1, 7)
    EnsureMinimalScrollBarFallback(scrollBar)
    if scrollFrame:IsShown() then
        scrollBar:Show()
    else
        scrollBar:Hide()
    end
end

ExBoss.UI.ApplyModernScrollBarSkin = ApplyModernScrollBarSkin

local function GetSidebarFontPath()
    local ET = _G.ExwindTools
    if ET and type(ET.MAIN_FONT) == "string" and ET.MAIN_FONT ~= "" then
        return ET.MAIN_FONT
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function NormalizeSidebarSearchText(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:lower()
end

local function SidebarTextContains(haystack, needle)
    local search = NormalizeSidebarSearchText(needle)
    if search == "" then
        return true
    end
    local source = NormalizeSidebarSearchText(haystack)
    return source:find(search, 1, true) ~= nil
end

local function CreateSidebarSearchBox(parent, initialText, opts)
    local config = type(opts) == "table" and opts or {}
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetHeight(config.height or 28)
    if edit.SetAutoFocus then
        edit:SetAutoFocus(false)
    end
    if edit.SetFont then
        edit:SetFont(GetSidebarFontPath(), 13, "")
    end
    if edit.SetTextColor then
        edit:SetTextColor(0.90, 0.93, 0.98, 1)
    end
    if edit.SetCursorColor then
        edit:SetCursorColor(0.0, 0.72, 1.0)
    end
    if edit.SetTextInsets then
        edit:SetTextInsets(10, 10, 0, 0)
    end
    edit:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    edit:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    edit:SetBackdropBorderColor(0.20, 0.22, 0.28, 1)

    local placeholder = edit:CreateFontString(nil, "ARTWORK")
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", -10, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetFont(GetSidebarFontPath(), 13, "")
    placeholder:SetTextColor(0.45, 0.50, 0.58, 1)
    placeholder:SetText(config.placeholder or L["搜索..."])
    edit._placeholder = placeholder

    local function RefreshPlaceholder(self)
        if self:GetText() == "" and not self:HasFocus() then
            self._placeholder:Show()
        else
            self._placeholder:Hide()
        end
    end

    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.00, 0.72, 1.00, 0.95)
        RefreshPlaceholder(self)
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.20, 0.22, 0.28, 1)
        RefreshPlaceholder(self)
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        RefreshPlaceholder(self)
        if config.onChanged then
            config.onChanged(self:GetText(), userInput, self)
        end
    end)

    edit:SetText(initialText or "")
    RefreshPlaceholder(edit)
    return edit
end

local function CreateSidebarCategoryHeader(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(26)

    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("LEFT", 0, 0)
    btn.label:SetPoint("RIGHT", 0, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetFont(GetSidebarFontPath(), 18, "OUTLINE")
    btn.label:SetTextColor(0.97, 0.98, 1.0, 0.98)

    btn:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.97, 0.98, 1.0, 0.98)
    end)

    return btn
end

local function CreateSidebarModuleButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(28)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    btn.rail = btn:CreateTexture(nil, "BACKGROUND")
    btn.rail:SetPoint("TOPLEFT", 10, -2)
    btn.rail:SetPoint("BOTTOMLEFT", 10, 2)
    btn.rail:SetWidth(1)
    btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.55)

    btn.accent = btn:CreateTexture(nil, "ARTWORK")
    btn.accent:SetPoint("TOPLEFT", 10, -2)
    btn.accent:SetPoint("BOTTOMLEFT", 10, 2)
    btn.accent:SetWidth(1)
    btn.accent:SetColorTexture(0.0, 0.72, 1.0, 1.0)
    btn.accent:SetAlpha(0)

    btn.dot = btn:CreateFontString(nil, "OVERLAY")
    btn.dot:SetPoint("CENTER", btn, "LEFT", 10, 0)
    btn.dot:SetFont(GetSidebarFontPath(), 15, "OUTLINE")
    btn.dot:SetText("")
    btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)

    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("LEFT", 26, 0)
    btn.label:SetPoint("RIGHT", -10, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)
    btn.label:SetFont(GetSidebarFontPath(), 15, "")
    btn.label:SetTextColor(0.57, 0.63, 0.75, 1)

    btn:SetScript("OnEnter", function(self)
        self._hovered = true
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState then
            ExBoss.UI.ApplySidebarModuleButtonState(self, self.isActive, self.isEnabledState)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self._hovered = false
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState then
            ExBoss.UI.ApplySidebarModuleButtonState(self, self.isActive, self.isEnabledState)
        end
    end)

    return btn
end

local function ApplySidebarModuleButtonState(btn, isActive, isEnabled)
    if not btn then
        return
    end
    btn.isActive = isActive == true
    btn.isEnabledState = (isEnabled ~= false)

    if btn.isEnabledState == false then
        btn.label:SetTextColor(0.38, 0.42, 0.50, 1)
        btn.rail:SetColorTexture(0.18, 0.20, 0.24, 0.35)
        btn.accent:SetAlpha(0)
        btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)
        return
    end

    if btn.isActive then
        btn.label:SetTextColor(0.92, 0.96, 1.00, 1)
        btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.25)
        btn.accent:SetAlpha(1)
        btn.dot:SetTextColor(0.0, 0.72, 1.0, 1.0)
        return
    end

    if btn._hovered then
        btn.label:SetTextColor(0.83, 0.88, 0.97, 1)
        btn.rail:SetColorTexture(0.34, 0.40, 0.52, 0.8)
    else
        btn.label:SetTextColor(0.57, 0.63, 0.75, 1)
        btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.55)
    end
    btn.accent:SetAlpha(0)
    btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)
end

ExBoss.UI.NormalizeSidebarSearchText = NormalizeSidebarSearchText
ExBoss.UI.SidebarTextContains = SidebarTextContains
ExBoss.UI.CreateSidebarSearchBox = CreateSidebarSearchBox
ExBoss.UI.CreateSidebarCategoryHeader = CreateSidebarCategoryHeader
ExBoss.UI.CreateSidebarModuleButton = CreateSidebarModuleButton
ExBoss.UI.ApplySidebarModuleButtonState = ApplySidebarModuleButtonState

-- =============================================================
-- 内容区刷新
-- =============================================================
local function RefreshContent()
    if not contentFrame then return end

    if mainFrame then
        local useLeft = ShouldUseLeftNav(currentTab)
        local expectFull = not useLeft
        if contentFrame._fullWidthMode ~= expectFull then
            local contentTopY = TAB_BAR_Y - TAB_H - 4
            contentFrame:ClearAllPoints()
            if useLeft then
                contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", CONTENT_X + 4, contentTopY)
            else
                contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, contentTopY)
            end
            contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
            contentFrame._fullWidthMode = expectFull
        end
    end

    -- Blizzard 样式 Tab 高亮
    if mainFrame and PanelTemplates_SetTab then
        local tabIndex = tabIndexByKey[currentTab]
        if tabIndex then
            PanelTemplates_SetTab(mainFrame, tabIndex)
        end
    end

    -- 隐藏占位文字（各 Tab 自己决定是否显示）
    if contentFrame._placeholder then
        contentFrame._placeholder:SetText("")
        contentFrame._placeholder:Hide()
    end

    -- 隐藏各设置页的 scrollFrame（切 Tab 时清理）
    local BossPage       = ExBoss.UI.Panel.BossPage
    local FixedTimelinePage = ExBoss.UI.Panel.FixedTimelinePage
    local HomePage       = ExBoss.UI.Panel.HomePage
    local GlobalSettingsPage = ExBoss.UI.Panel.GlobalSettingsPage
    local ImportExportPage = ExBoss.UI.Panel.ImportExportPage
    local MDTPage = ExBoss.UI.Panel.MDTPage
    local OtherVoicePage = ExBoss.UI.Panel.OtherVoicePage
    local ToolsPage = ExBoss.UI.Panel.ToolsPage
    local TimerBarPage   = ExBoss.UI.Panel.TimerBarPage
    local BunBarPage     = ExBoss.UI.Panel.BunBarPage
    local CountdownPage  = ExBoss.UI.Panel.CountdownPage
    local FlashTextPage  = ExBoss.UI.Panel.FlashTextPage
    local FlashTextMediumPage = ExBoss.UI.Panel.FlashTextMediumPage
    local VoicePackPage  = ExBoss.UI.Panel.VoicePackPage
    local TrashCDPage    = ExBoss.UI.Panel.TrashCDPage
    for _, page in ipairs({ TimerBarPage, BunBarPage, CountdownPage, FlashTextPage, FlashTextMediumPage }) do
        if page and page._scrollFrame then page._scrollFrame:Hide() end
    end
    if BossPage and BossPage.Hide then BossPage:Hide() end
    if FixedTimelinePage and FixedTimelinePage.Hide then FixedTimelinePage:Hide() end
    if HomePage and HomePage.Hide then HomePage:Hide() end
    if GlobalSettingsPage and GlobalSettingsPage.Hide then GlobalSettingsPage:Hide() end
    if ImportExportPage and ImportExportPage.Hide then ImportExportPage:Hide() end
    if VoicePackPage and VoicePackPage.Hide then VoicePackPage:Hide() end
    if MDTPage and MDTPage.Hide then MDTPage:Hide() end
    if OtherVoicePage and OtherVoicePage.Hide then OtherVoicePage:Hide() end
    if ToolsPage and ToolsPage.Hide then ToolsPage:Hide() end
    if TrashCDPage and TrashCDPage.Hide then TrashCDPage:Hide() end

    -- 分发各 Tab
    if currentTab == "home" then
        leftFrame:Hide()
        if HomePage and HomePage.Render then
            HomePage:Render(contentFrame)
        elseif contentFrame._placeholder then
            contentFrame._placeholder:SetText(L["首页（占位）"])
            contentFrame._placeholder:Show()
        end

    elseif currentTab == "boss" then
        leftFrame:Show()
        if BossPage and BossPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            BossPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["BOSS技能页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "fixedtimeline" then
        leftFrame:Hide()
        if FixedTimelinePage and FixedTimelinePage.Render then
            FixedTimelinePage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["固定时间轴预览页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "mdt" then
        leftFrame:Hide()
        if MDTPage and MDTPage.Render then
            MDTPage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["MDT页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "globalsettings" then
        leftFrame:Show()
        if GlobalSettingsPage and GlobalSettingsPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            GlobalSettingsPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["通用设置页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "voicepack" then
        leftFrame:Hide()
        if VoicePackPage and VoicePackPage.Render then
            local ok, err = pcall(function()
                VoicePackPage:Render(contentFrame)
            end)
            if not ok and contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["语音包设置页异常:\n%s"], tostring(err)))
                contentFrame._placeholder:Show()
            end
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["语音包设置页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "othervoice" then
        leftFrame:Hide()
        if OtherVoicePage and OtherVoicePage.Render then
            local ok, err = pcall(function()
                OtherVoicePage:Render(contentFrame)
            end)
            if not ok and contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["其他语音页异常:\n%s"], tostring(err)))
                contentFrame._placeholder:Show()
            end
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["其他语音页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "importexport" then
        leftFrame:Hide()
        if ImportExportPage and ImportExportPage.Render then
            ImportExportPage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["导入导出页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "trash" then
        leftFrame:Hide()
        if TrashCDPage and TrashCDPage.Render then
            TrashCDPage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["小怪CD页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "tools" then
        leftFrame:Show()
        if ToolsPage and ToolsPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            ToolsPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["设置页 [%s] — 待开发"], L["小工具"]))
                contentFrame._placeholder:Show()
            end
        end

    else
        leftFrame:Hide()
        if contentFrame._placeholder then
            contentFrame._placeholder:SetText(string.format(L["设置页 [%s] — 待开发"], currentTab))
            contentFrame._placeholder:Show()
        end
    end
end

local function FlushFocusedEditBox()
    local focus = type(GetCurrentKeyBoardFocus) == "function" and GetCurrentKeyBoardFocus() or nil
    if not focus then
        return
    end
    if focus.IsObjectType and focus:IsObjectType("EditBox") and focus.ClearFocus then
        focus:ClearFocus()
    end
end

-- =============================================================
-- 窗口创建（懒加载，只执行一次）
-- =============================================================
local function CreatePanel()
    if mainFrame then return end

--     print("|cffff4400Ex|r|cff00ccffBoss|r CreatePanel() 开始")

    -- ── 主窗口 ────────────────────────────────────────────────
    mainFrame = CreateFrame("Frame", "ExBoss_MainPanel", UIParent, "BackdropTemplate")
    mainFrame:SetSize(PANEL_W, PANEL_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    -- 允许用户将窗口拖出屏幕边界（多屏/截图/排版场景）
    mainFrame:SetClampedToScreen(false)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    mainFrame:SetScript("OnHide", function()
        FlushFocusedEditBox()
    end)
    mainFrame:Hide()

    -- 支持 ESC 关闭
    if not tContains(UISpecialFrames, "ExBoss_MainPanel") then
        table.insert(UISpecialFrames, "ExBoss_MainPanel")
    end

    mainFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    mainFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.97)
    mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    -- ── 标题栏 ────────────────────────────────────────────────
    local titleBar = mainFrame:CreateTexture(nil, "BACKGROUND")
    titleBar:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  4, -4)
    titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(28)
    titleBar:SetColorTexture(0.12, 0.12, 0.16, 1)

    local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cffff4400Ex|r|cff00ccffBoss|r  v" .. ExBoss.VERSION)

    -- ── 面板缩放控件 ──────────────────────────────────────────
    local scaleLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleLabel:SetPoint("LEFT", titleText, "RIGHT", 16, 0)
    scaleLabel:SetText(L["缩放"])
    scaleLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local scaleDropdown = CreateFrame("DropdownButton", nil, mainFrame, "WowStyle1DropdownTemplate")
    scaleDropdown:SetWidth(100)
    scaleDropdown:SetPoint("LEFT", scaleLabel, "RIGHT", 6, 0)
    scaleDropdown:SetFrameLevel(mainFrame:GetFrameLevel() + 30)

    local function ApplyPanelScale(pct)
        if ExBossDB and ExBossDB.ui and ExBossDB.ui.general then
            ExBossDB.ui.general.panelScale = pct
        end
        mainFrame:SetScale(pct / 100)
        scaleDropdown:SetText(pct .. "%")
        scaleDropdown._currentPct = pct
    end
    mainFrame._applyPanelScale = ApplyPanelScale

    local scaleOptions = { 70, 75, 80, 85, 90, 95, 100, 105, 110 }
    scaleDropdown:SetupMenu(function(self, rootDescription)
        for _, pct in ipairs(scaleOptions) do
            rootDescription:CreateRadio(pct .. "%",
                function() return self._currentPct == pct end,
                function() ApplyPanelScale(pct) end
            )
        end
    end)

    local initPct = (ExBossDB and ExBossDB.ui and ExBossDB.ui.general and ExBossDB.ui.general.panelScale) or 100
    initPct = math.max(70, math.min(110, initPct))
    scaleDropdown._currentPct = initPct
    scaleDropdown:SetText(initPct .. "%")
    mainFrame:SetScale(initPct / 100)

    -- 标题栏拖拽层：避免内容区控件吞掉鼠标，确保始终可拖动窗口
    local dragHandle = CreateFrame("Frame", nil, mainFrame)
    dragHandle:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
    end)

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        FlushFocusedEditBox()
        mainFrame:Hide()
    end)

    -- 标题栏右上角：编辑模式按钮（沿用 ExwindTools 的全局编辑模式逻辑）
    local editModeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    editModeBtn:SetSize(120, 22)
    editModeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, -1)
    editModeBtn:SetScript("OnClick", function()
        local ET = _G.ExwindTools
        if ET and ET.ToggleGlobalEditMode then
            ET:ToggleGlobalEditMode()
            RefreshEditModeButtonLabel()
            if ET.GlobalEditMode and mainFrame:IsShown() then
                FlushFocusedEditBox()
                mainFrame:Hide()
            end
        end
    end)
    mainFrame._editModeBtn = editModeBtn
    RefreshEditModeButtonLabel()
    local ET = _G.ExwindTools
    if ET and ET.RegisterEditModeHandler then
        ET:RegisterEditModeHandler("ExBoss.Panel.EditButton", {
            RefreshEditMode = function()
                RefreshEditModeButtonLabel()
            end,
        })
    end

    -- 让拖拽层避开“编辑模式 + 关闭”按钮区域，避免按钮无法点击。
    dragHandle:SetPoint("RIGHT", editModeBtn, "LEFT", -6, 0)

    -- ── 顶部 Tab 栏 ───────────────────────────────────────────
    local tabBarY = TAB_BAR_Y
    local prevTab = nil
    local visibleTabs = BuildVisibleTabs()
    for i, tabDef in ipairs(visibleTabs) do
        local btn = CreateFrame("Button", "ExBoss_MainPanelTab" .. i, mainFrame, "PanelTopTabButtonTemplate")
        btn:SetID(i)
        if prevTab then
            btn:SetPoint("LEFT", prevTab, "RIGHT", -15, 0)
        else
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, tabBarY)
        end
        btn:SetText(tabDef.label)
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(btn, 0)
        end
        btn._tabKey = tabDef.key

        btn:SetScript("OnClick", function(self)
            FlushFocusedEditBox()
            currentTab = self._tabKey
            RefreshContent()
        end)

        tabButtons[tabDef.key] = btn
        tabIndexByKey[tabDef.key] = i
        prevTab = btn
    end
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(mainFrame, #visibleTabs)
    end

    -- ── 左侧导航框架 ──────────────────────────────────────────
    local contentTopY = tabBarY - TAB_H - 4
    leftFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    leftFrame:SetPoint("TOPLEFT",    mainFrame, "TOPLEFT",  4, contentTopY)
    leftFrame:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 4)
    leftFrame:SetWidth(LEFT_W)
    leftFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    leftFrame:SetBackdropColor(0.06, 0.06, 0.08, 1)
    leftFrame:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    local leftLabel = leftFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leftLabel:SetPoint("TOP", leftFrame, "TOP", 0, -10)
    leftLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    leftLabel:SetText(L["副本 / BOSS 导航\n(待开发)"])
    leftFrame._placeholderLabel = leftLabel

    Panel.leftFrame = leftFrame

    -- ── 右侧内容区 ────────────────────────────────────────────
    contentFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    contentFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",  CONTENT_X + 4, contentTopY)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    contentFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    contentFrame:SetBackdropColor(0.07, 0.07, 0.09, 1)
    contentFrame:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    Panel.contentFrame = contentFrame

    -- 占位文字
    local placeholder = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 1)
    placeholder:SetJustifyH("CENTER")
    placeholder:SetText("")
    contentFrame._placeholder = placeholder

    -- ── 底部状态栏 ────────────────────────────────────────────
    local statusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 8)
    statusText:SetTextColor(0.5, 0.5, 0.5, 1)
    statusText:SetText(L["/exb  打开/关闭    |    /exb edit  编辑模式    |    /exb debug  调试"])
    Panel.statusText = statusText

    local changelogBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    changelogBtn:SetSize(88, 22)
    changelogBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 6)
    changelogBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 40)
    changelogBtn:SetText(L["更新日志"])
    changelogBtn:SetScript("OnClick", function()
        if ExBoss and ExBoss.ShowChangelog then
            ExBoss:ShowChangelog({ markShown = true })
        end
    end)
    Panel.changelogBtn = changelogBtn

    Panel._frame = mainFrame
--     print("|cffff4400Ex|r|cff00ccffBoss|r CreatePanel() 完成")
end

-- =============================================================
-- 公开接口
-- =============================================================
function Panel:Toggle()
--     print("|cffff4400Ex|r|cff00ccffBoss|r Panel:Toggle() 调用")
    CreatePanel()
    currentTab = ResolveSafeTab(currentTab)
    RefreshEditModeButtonLabel()
    if mainFrame:IsShown() then
        FlushFocusedEditBox()
        mainFrame:Hide()
    else
        mainFrame:Show()
        local BossPage = ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
        if BossPage and BossPage.OnPanelShown then
            BossPage:OnPanelShown()
        end
        RefreshContent()
        TryHandleChangelogPopupOnUIOpen()
    end
end

function Panel:Show()
    CreatePanel()
    currentTab = ResolveSafeTab(currentTab)
    RefreshEditModeButtonLabel()
    mainFrame:Show()
    local BossPage = ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if BossPage and BossPage.OnPanelShown then
        BossPage:OnPanelShown()
    end
    RefreshContent()
    TryHandleChangelogPopupOnUIOpen()
end

function Panel:Hide()
    FlushFocusedEditBox()
    if mainFrame then mainFrame:Hide() end
end

function Panel:SetTab(tabKey)
    local requested = NormalizeTabKey(tabKey)
    if GLOBAL_SETTINGS_REDIRECTS[requested] then
        requested = GLOBAL_SETTINGS_REDIRECTS[requested]
    end
    if requested == "timerbar"
        or requested == "bunbar"
        or requested == "countdown"
        or requested == "flashtext"
        or requested == "flashtextmedium"
        or requested == "ringprogress"
        or requested == "iconalert"
        or requested == "castprogressbar"
        or requested == "extrashieldbar"
        or requested == "conditions"
        or requested == "privateauramonitor"
        or requested == "dungeonextra"
    then
        local globalPage = ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalSettingsPage
        if globalPage and globalPage.SetSelectedKey then
            globalPage:SetSelectedKey(requested)
        end
        requested = "globalsettings"
    end
    if requested == "targetalert" or requested == "mythiccast" or requested == "stateicons"
        or requested == "interrupttracker" then
        local toolsPage = ExBoss.UI.Panel and ExBoss.UI.Panel.ToolsPage
        if toolsPage and toolsPage.SetSelectedKey then
            toolsPage:SetSelectedKey(requested)
        end
        requested = "tools"
    end
    currentTab = ResolveSafeTab(requested)
    if mainFrame and mainFrame:IsShown() then
        FlushFocusedEditBox()
        RefreshContent()
    end
end

-- print("|cffff4400Ex|r|cff00ccffBoss|r PanelFrame.lua 加载完成，Panel:Toggle=" .. tostring(Panel.Toggle))
