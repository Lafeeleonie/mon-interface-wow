---@diagnostic disable: undefined-global, undefined-field, need-check-nil

ExBoss.UI.Panel.HomePage = ExBoss.UI.Panel.HomePage or {}
local Page = ExBoss.UI.Panel.HomePage
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

do
    local zhCN = ExBoss.NewLocale and ExBoss:NewLocale("zhCN")
    if zhCN then
        zhCN["隐藏 EXBoss 小地图按钮"] = true
    end
    local enUS = ExBoss.NewLocale and ExBoss:NewLocale("enUS")
    if enUS then
        enUS["隐藏 EXBoss 小地图按钮"] = "Hide EXBoss Minimap Button"
    end
end

local MODULE_KEY = "ExBoss.HomePage"
local GRID_COLS = 100

local scrollFrame = nil
local scrollChild = nil
local missingDepsText = nil
local RefreshPage = nil
local pageLayoutData = nil

local THEME = {
    gold = { 1.00, 0.82, 0.35 },
    cyan = { 0.36, 0.82, 1.00 },
    green = { 0.48, 0.92, 0.72 },
    red = { 1.00, 0.36, 0.32 },
}

local VOICE_PACKS = {
    "夏一可(Yike)", "顾衣衿(Guyijin)", "砂糖悠鸣(SatouYumei)", "糖糖酱(Tangtangjiang)",
    "毬亚(Akumaria)", "然然(Ranran)", "忘忧景久(WYJJ)", "步萌(Boom)", "你好牛(Niuniu)",
    "露露緹婭(Rurutia)", "绫零(Ayarei)", "初音软芙芙(mikufufu)", "可乐(kele)", "苏苏(SUSU)",
    "小羊(Yagi)", "小月灼(Moonburn)", "捏口捏(Nico)", "哈老师(Hati)", "静静(Jingjing)",
    "桃桃(TAOTAO)", "鲜克(AC)", "猫猫茶壶(NyanyaTea)",
}

local LOCALE_LABELS = {
    AUTO = L["自动跟随客户端"],
    zhCN = L["强制 zhCN"],
    zhTW = L["强制 zhTW"],
    enUS = L["强制 enUS"],
    koKR = L["强制 koKR"],
    deDE = L["强制 deDE"],
    esES = L["强制 esES"],
    esMX = L["强制 esMX"],
    itIT = L["强制 itIT"],
    ptBR = L["强制 ptBR"],
    frFR = L["强制 frFR"],
    ruRU = L["强制 ruRU"],
}

local LOCALE_OPTIONS = {
    { L["自动跟随客户端"], "AUTO" },
    { L["强制 zhCN"], "zhCN" },
    { L["强制 zhTW"], "zhTW" },
    { L["强制 enUS"], "enUS" },
    { L["强制 koKR"], "koKR" },
    { L["强制 deDE"], "deDE" },
    { L["强制 esES"], "esES" },
    { L["强制 esMX"], "esMX" },
    { L["强制 itIT"], "itIT" },
    { L["强制 ptBR"], "ptBR" },
    { L["强制 frFR"], "frFR" },
    { L["强制 ruRU"], "ruRU" },
}

local SPECIAL_LINKS = {
    special_zimeng = "https://www.douyu.com/zimengovo",
    special_kira = "https://www.twitch.tv/kiratank_tv",
    special_naowh = "https://www.twitch.tv/naowh",
    special_stove = "https://www.twitch.tv/stovepov",
    support_afdian = "https://afdian.com/a/Exwind",
    announcement_url_cn = "https://exwind.net/addon?lang=zhCN",
    announcement_url_en = "exwind.net/addon?lang=enUS",
}

local FEEDBACK_LINKS = {
    feedback_qq = "2168036546",
    feedback_bili_msg = "space.bilibili.com/3494364483422992",
    feedback_bili_live = "live.bilibili.com/1741633656",
    feedback_discord = "discord.gg/6fwVhRHyg9",
}

local LOCALE_LINKS = {
    locale_github = "github.com/Ex-wind/EXBOSS-Locale",
}


local function BuildVoicePackText()
    local rows = {}
    local line = {}
    for i = 1, #VOICE_PACKS do
        line[#line + 1] = VOICE_PACKS[i]
        if #line >= 3 then
            rows[#rows + 1] = table.concat(line, "   ")
            line = {}
        end
    end
    if #line > 0 then
        rows[#rows + 1] = table.concat(line, "   ")
    end
    return table.concat(rows, "\n")
end

local function BuildAnnouncementBody()
    return L["将你的配置/语音打包成插件"]
end

local function BuildHeroBody()
    local version = tostring((GetAddOnMetadata and GetAddOnMetadata("EXBoss", "Version")) or "")
    local lines = {
        L["副本首领时间轴、语音提示、团队框架发光与配置方案。"],
        L["插件作者: EXWIND"],
        "",
        L["如果你觉得插件不错，可以小额赞助。"],
    }
    if version ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Version " .. version
    end
    return table.concat(lines, "\n")
end

local function BuildCreditsText()
    return table.concat({
        "|cffffce45" .. L["插件作者"] .. "|r  EXWIND",
        "|cffc8d6e5" .. L["开发协助"] .. "|r  @露露緹婭 @小海牛 @绿色歹人",
        "|cffc8d6e5" .. L["测试协助"] .. "|r  @誓言 @苏苏 @明日奈奈子",
        "|cff99aabb" .. L["额外感谢"] .. "|r  @野顾 @永恒 @shun @semage @硬玩复仇 @Sora @毛天使 @末城 @苏帕米",
    }, "\n")
end

local function BuildLocalizationText()
    return table.concat({
        "@TyrNebula",
        "deDE  @CRAZUDEMZY",
        "esES  @KullThran",
        "ruRU  @alistrata",
        "frFR  @Melune  @eskna",
        "",
        L["如有遗漏请提醒我"],
    }, "\n")
end

local function BuildCopyrightText()
    return table.concat({
        L["语音包版权归语音包作者所有。每位作者方案不同，如需单独使用请咨询语音包作者。"],
        "",
        L["插件本体（不含 Lib）版权：CC BY-NC-ND 4.0"],
    }, "\n")
end

local function BuildFooterText()
    return table.concat({
        L["感谢使用 EXBoss。"],
        L["反馈请尽量附上副本、首领、难度、职业职责、错误截图或复现步骤。"],
    }, "\n")
end

local function GetLocaleModeLabel(mode)
    local value = tostring(mode or ""):gsub("%s+", "")
    return LOCALE_LABELS[value] or L["自动跟随客户端"]
end

local function BuildLocaleStatusText()
    local localeMode = ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or "AUTO"
    local clientLocale = ExBoss.Locale and ExBoss.Locale.GetClientLocale and ExBoss.Locale:GetClientLocale() or GetLocale()
    local effectiveLocale = ExBoss.GetEffectiveLocale and ExBoss:GetEffectiveLocale(localeMode) or clientLocale
    return string.format(
        L["当前设置：%s | 客户端：%s | 当前生效：%s\n仅影响 EXBoss 自身本地化文本，切换后建议重载界面。"],
        GetLocaleModeLabel(localeMode),
        tostring(clientLocale or "zhCN"),
        tostring(effectiveLocale or "zhCN")
    )
end

local function GetPageDBDefaults()
    return {
        localeMode = "AUTO",
        special_zimeng = SPECIAL_LINKS.special_zimeng,
        special_kira = SPECIAL_LINKS.special_kira,
        special_naowh = SPECIAL_LINKS.special_naowh,
        special_stove = SPECIAL_LINKS.special_stove,
        support_afdian = SPECIAL_LINKS.support_afdian,
        announcement_url_cn = SPECIAL_LINKS.announcement_url_cn,
        announcement_url_en = SPECIAL_LINKS.announcement_url_en,
        feedback_qq = FEEDBACK_LINKS.feedback_qq,
        feedback_bili_msg = FEEDBACK_LINKS.feedback_bili_msg,
        feedback_bili_live = FEEDBACK_LINKS.feedback_bili_live,
        feedback_discord = FEEDBACK_LINKS.feedback_discord,
        locale_github = LOCALE_LINKS.locale_github,
        exbossMinimapHidden = false,
    }
end

local function GetPageDB()
    if not (ExwindTools and ExwindTools.GetModuleDB) then
        return GetPageDBDefaults()
    end
    return ExwindTools:GetModuleDB(MODULE_KEY, GetPageDBDefaults())
end

local function SyncPageDBFromRuntime()
    local db = GetPageDB()
    if ExBoss.GetLocaleMode then
        db.localeMode = tostring(ExBoss:GetLocaleMode() or "AUTO")
    end
    db.special_zimeng = SPECIAL_LINKS.special_zimeng
    db.special_kira = SPECIAL_LINKS.special_kira
    db.special_naowh = SPECIAL_LINKS.special_naowh
    db.special_stove = SPECIAL_LINKS.special_stove
    db.support_afdian = SPECIAL_LINKS.support_afdian
    db.announcement_url_cn = SPECIAL_LINKS.announcement_url_cn
    db.announcement_url_en = SPECIAL_LINKS.announcement_url_en
    db.feedback_qq = FEEDBACK_LINKS.feedback_qq
    db.feedback_bili_msg = FEEDBACK_LINKS.feedback_bili_msg
    db.feedback_bili_live = FEEDBACK_LINKS.feedback_bili_live
    db.feedback_discord = FEEDBACK_LINKS.feedback_discord
    db.locale_github = LOCALE_LINKS.locale_github
    db.exbossMinimapHidden = ExwindTools and ExwindTools.IsEXBossMinimapButtonHidden and ExwindTools:IsEXBossMinimapButtonHidden() or false
    return db
end

local function IsGridEditActive()
    local Grid = _G.ExwindGrid
    return Grid and Grid.IsLiveEditing == true and Grid.LiveContainer == scrollChild
end

local function BuildLayout()
    return {
        { key = "header_main", type = "header", x = 1, y = 2, w = 58, h = 2, label = L["首页"], labelSize = 24 },
        {
            key = "btn_toggle_grid_edit",
            type = "button",
            x = 86, y = 2, w = 13, h = 2,
            label = IsGridEditActive() and L["退出布局编辑"] or L["开启布局编辑"],
            func = function()
                local Grid = _G.ExwindGrid
                if Grid and scrollChild then
                    Grid:ToggleLiveEdit(scrollChild)
                    C_Timer.After(0, function()
                        if type(RefreshPage) == "function" then
                            RefreshPage(false)
                        end
                    end)
                end
            end
        },

        -- 第一行：EXBoss / Announcement / 制作名单
        { key = "card_hero",         type = "card", x = 2,  y = 6, w = 31, h = 15, title = "EXBoss",                  desc = "", accentColor = { r = THEME.gold[1], g = THEME.gold[2], b = THEME.gold[3], a = 1 } },
        { key = "card_announcement", type = "card", x = 35, y = 6, w = 31, h = 15, title = "Developer Announcement",  desc = "", accentColor = { r = THEME.gold[1], g = THEME.gold[2], b = THEME.gold[3], a = 1 } },
        { key = "card_credits",      type = "card", x = 68, y = 6, w = 31, h = 15, title = L["制作名单"],              desc = "", accentColor = { r = THEME.gold[1], g = THEME.gold[2], b = THEME.gold[3], a = 1 } },
        { key = "support_afdian", type = "input", x = 4, y = 10, w = 27, h = 2, label = L["如果你觉得插件不错，可以小额赞助"], labelPos = "top" },
        { key = "desc_announcement",   type = "description", x = 37, y = 9,  w = 27, h = 3, label = BuildAnnouncementBody() },
        { key = "announcement_url_cn", type = "input", x = 37, y = 13, w = 27, h = 2, label = L["中文"], labelPos = "top" },
        { key = "announcement_url_en", type = "input", x = 37, y = 16, w = 27, h = 2, label = L["英文"], labelPos = "top" },
        { key = "desc_credits",      type = "description", x = 70, y = 9,  w = 27, h = 6,  label = BuildCreditsText() },

        -- 第二行：问题反馈 / 版权说明 / 特别协助（h=17 容纳一列四行输入框）
        { key = "card_feedback",  type = "card", x = 2,  y = 23, w = 31, h = 17, title = L["问题反馈"], desc = L["复制或选中下面联系方式即可。"], accentColor = { r = THEME.cyan[1], g = THEME.cyan[2], b = THEME.cyan[3], a = 1 } },
        { key = "card_copyright", type = "card", x = 35, y = 23, w = 31, h = 17, title = L["版权说明"], desc = "",                               accentColor = { r = THEME.red[1],  g = THEME.red[2],  b = THEME.red[3],  a = 1 } },
        { key = "card_special",   type = "card", x = 68, y = 23, w = 31, h = 17, title = L["特别协助"], desc = L["复制或选中下面链接即可。"],     accentColor = { r = THEME.cyan[1], g = THEME.cyan[2], b = THEME.cyan[3], a = 1 } },
        { key = "feedback_qq",        type = "input", x = 4, y = 28, w = 27, h = 2, label = "QQ群",      labelPos = "top" },
        { key = "feedback_bili_msg",  type = "input", x = 4, y = 31, w = 27, h = 2, label = "B站(私信)", labelPos = "top" },
        { key = "feedback_bili_live", type = "input", x = 4, y = 34, w = 27, h = 2, label = "B站直播间", labelPos = "top" },
        { key = "feedback_discord",   type = "input", x = 4, y = 37, w = 27, h = 2, label = "DC频道",    labelPos = "top" },
        { key = "desc_copyright",     type = "description", x = 37, y = 27, w = 27, h = 10, label = BuildCopyrightText() },
        { key = "special_zimeng", type = "input", x = 70, y = 28, w = 27, h = 2, label = "子梦(Zimeng)", labelPos = "top" },
        { key = "special_kira",   type = "input", x = 70, y = 31, w = 27, h = 2, label = "KIRA",         labelPos = "top" },
        { key = "special_naowh",  type = "input", x = 70, y = 34, w = 27, h = 2, label = "Naowh",        labelPos = "top" },
        { key = "special_stove",  type = "input", x = 70, y = 37, w = 27, h = 2, label = "STOVE",        labelPos = "top" },

        -- 第三行：本地化翻译 / 界面语言 / 感谢（y=42，第二行 h=17 后下移 2 格）
        { key = "card_localize", type = "card", x = 2,  y = 42, w = 31, h = 15, title = L["本地化翻译"],       desc = "", accentColor = { r = THEME.green[1], g = THEME.green[2], b = THEME.green[3], a = 1 } },
        { key = "card_locale",   type = "card", x = 35, y = 42, w = 31, h = 15, title = L["界面语言"],         desc = "", accentColor = { r = THEME.cyan[1],  g = THEME.cyan[2],  b = THEME.cyan[3],  a = 1 } },
        { key = "card_footer",   type = "card", x = 68, y = 42, w = 31, h = 15, title = L["感谢使用 EXBoss。"], desc = "", accentColor = { r = THEME.cyan[1],  g = THEME.cyan[2],  b = THEME.cyan[3],  a = 1 } },
        { key = "desc_localize_intro", type = "description", x = 4,  y = 44, w = 27, h = 2, label = L["如果你想参与本地化或是反馈，可以在："] },
        { key = "locale_github",       type = "input",       x = 4,  y = 46, w = 27, h = 2, label = "GitHub", labelPos = "top" },
        { key = "desc_localize",       type = "description", x = 4,  y = 49, w = 27, h = 8, label = BuildLocalizationText() },
        { key = "exbossMinimapHidden", type = "checkbox",    x = 37, y = 44, w = 20, h = 2, label = L["隐藏 EXBoss 小地图按钮"] },
        { key = "localeMode",          type = "dropdown",    x = 37, y = 47, w = 15, h = 2, label = "", items = LOCALE_OPTIONS, search = true },
        { key = "btn_reload_ui",       type = "button",      x = 53, y = 47, w = 10, h = 2, label = L["立即重载界面"], func = function() ReloadUI() end, frameLevelOffset = 8 },
        { key = "desc_locale_status",  type = "description", x = 37, y = 50, w = 27, h = 5, label = BuildLocaleStatusText() },
        { key = "desc_footer",         type = "description", x = 70, y = 46, w = 27, h = 4, label = BuildFooterText() },

        -- 第四行：语音包列表
        { key = "card_voice",  type = "card",        x = 2, y = 59, w = 96, h = 14, title = L["语音包列表"], desc = "", accentColor = { r = THEME.green[1], g = THEME.green[2], b = THEME.green[3], a = 1 } },
        { key = "desc_voice",  type = "description", x = 4, y = 62, w = 92, h = 11, label = BuildVoicePackText() },
    }
end

local function FindLayoutEntry(layout, key)
    if type(layout) ~= "table" then
        return nil
    end
    for i = 1, #layout do
        local item = layout[i]
        if item and item.key == key then
            return item
        end
    end
    return nil
end

local function UpdateLayoutData(layout)
    local db = SyncPageDBFromRuntime()
    local updates = {
        btn_toggle_grid_edit = { label = IsGridEditActive() and L["退出布局编辑"] or L["开启布局编辑"] },
        desc_announcement = { label = BuildAnnouncementBody() },
        desc_hero = { label = BuildHeroBody() },
        desc_credits = { label = BuildCreditsText() },
        desc_localize = { label = BuildLocalizationText() },
        desc_localize_intro = { label = L["如果你想参与本地化或是反馈，可以在："] },
        desc_voice = { label = BuildVoicePackText() },
        desc_locale_status = { label = BuildLocaleStatusText() },
        desc_copyright = { label = BuildCopyrightText() },
        desc_footer = { label = BuildFooterText() },
        localeMode = { items = LOCALE_OPTIONS },
    }

    db.localeMode = tostring(ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or db.localeMode or "AUTO")

    for key, fields in pairs(updates) do
        local item = FindLayoutEntry(layout, key)
        if item then
            for field, value in pairs(fields) do
                item[field] = value
            end
        end
    end
end

local function GetOrBuildLayout()
    if type(pageLayoutData) ~= "table" then
        pageLayoutData = BuildLayout()
    end
    UpdateLayoutData(pageLayoutData)
    return pageLayoutData
end

local function RenderGrid(contentFrame, resetScroll)
    local Grid = _G.ExwindGrid
    local EXUI = ExwindTools and ExwindTools.UI
    if not (Grid and EXUI and ExwindTools) then
        return false
    end

    local layout = GetOrBuildLayout()
    ExwindTools:RegisterModuleLayout(MODULE_KEY, layout)

    if not scrollFrame then
        scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)
    end

    if missingDepsText then
        missingDepsText:Hide()
    end

    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    if resetScroll == true then
        scrollFrame:SetVerticalScroll(0)
    end
    scrollFrame:Show()

    C_Timer.After(0, function()
        if not (scrollFrame and scrollFrame:IsShown() and scrollChild) then
            return
        end
        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 1400
        end
        scrollChild:SetWidth(width - 16)
        scrollChild:SetHeight(1)
        scrollChild:SetParent(scrollFrame)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", 0, 0)
        scrollChild:Show()

        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = scrollChild
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        if Grid.SetContainerCols then
            Grid:SetContainerCols(scrollChild, GRID_COLS)
        end
        Grid:Render(scrollChild, layout, GetPageDB(), MODULE_KEY)
    end)

    return true
end

RefreshPage = function(resetScroll)
    local contentFrame = Page._contentFrame
    if not contentFrame then
        return
    end

    if RenderGrid(contentFrame, resetScroll) then
        return
    end

    if scrollFrame then
        scrollFrame:Hide()
    end
    if not missingDepsText then
        missingDepsText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        missingDepsText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 20, -20)
        missingDepsText:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -20, 0)
        missingDepsText:SetJustifyH("LEFT")
        missingDepsText:SetJustifyV("TOP")
    end
    missingDepsText:SetText(L["首页依赖 ExwindTools.UI 与 ExwindGrid，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"])
    missingDepsText:Show()
end

local function HandleDatabaseChanged(info)
    local db = GetPageDB()
    local key = tostring(info and info.key or "")
    if key == "localeMode" then
        local mode = tostring(db.localeMode or "AUTO")
        if ExBoss.SetLocaleMode then
            ExBoss:SetLocaleMode(mode)
        end
    elseif key == "exbossMinimapHidden" then
        if ExwindTools and ExwindTools.SetEXBossMinimapButtonHidden then
            ExwindTools:SetEXBossMinimapButtonHidden(db.exbossMinimapHidden == true)
        end
    end
    if type(RefreshPage) == "function" then
        RefreshPage(false)
    end
end

function Page:Render(contentFrame)
    Page._contentFrame = contentFrame
    SyncPageDBFromRuntime()
    RefreshPage(true)
end

function Page:Hide()
    if scrollFrame then
        scrollFrame:Hide()
    end
    if missingDepsText then
        missingDepsText:Hide()
    end
end

if ExwindTools and not Page._gridEventsRegistered then
    Page._gridEventsRegistered = true
    ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY .. "_db", function(info)
        HandleDatabaseChanged(info)
    end)
end
