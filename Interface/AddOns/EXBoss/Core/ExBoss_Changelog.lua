-- =============================================================
-- ExBoss_Changelog.lua
-- 核心更新日志系统：
-- 1. 将当前版本写入 WTF
-- 2. 根据 WTF 记录判断是否需要在打开设置面板时弹窗（每版本仅一次）
-- 3. 提供手动打开更新日志窗口的 API
-- =============================================================

local ExBoss = _G.ExBoss
if not ExBoss then return end

local ExwindTools = _G.ExwindTools

local changelogFrame
local MAX_SCROLL_CONTENT_HEIGHT = 12000

local PANEL_THEME = {
    Background = { 0, 0, 0, 1 },
    Border = { 0.22, 0.56, 0.34, 0.9 },
    BodyText = { 0.84, 0.86, 0.89, 1.0 },
    BulletText = { 0.90, 0.92, 0.95, 1.0 },
    NoteText = { 0.95, 0.74, 0.45, 1.0 },
    H1Text = { 1.00, 0.86, 0.45, 1.0 },
    H2Text = { 0.43, 0.68, 0.86, 1.0 },
    DividerText = { 0.52, 0.64, 0.74, 0.75 },
}
local FONT_PATH = (GameFontNormal and select(1, GameFontNormal:GetFont())) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local PANEL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function GetCurrentVersion()
    return tostring(ExBoss.VERSION or (_G.ExBoss_MetaData and _G.ExBoss_MetaData.version) or "v0.0.0.0000")
end

local function GetChangelogDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.Changelog = type(ExBossDB.Changelog) == "table" and ExBossDB.Changelog or {}
    return ExBossDB.Changelog
end

local function GetMetaChangelog()
    local meta = _G.ExBoss_MetaData
    return meta and meta.changelog
end

local function GetChangelogContent()
    local current = GetCurrentVersion()
    local data = GetMetaChangelog()

    if type(data) == "string" and data ~= "" then
        return data
    end

    if type(data) == "table" then
        if type(data[current]) == "string" and data[current] ~= "" then
            return data[current]
        end
        if type(data.content) == "string" and data.content ~= "" then
            return data.content
        end
    end

    return "暂无更新日志内容。"
end

local function GetChangelogFontSize()
    local data = GetMetaChangelog()
    if type(data) == "table" then
        local n = tonumber(data.fontSize)
        if n then
            n = math.floor(n)
            if n < 10 then n = 10 end
            if n > 28 then n = 28 end
            return n
        end
    end
    return 14
end

local function ParseVersion(versionText)
    if not versionText then return nil end
    local text = tostring(versionText):lower():gsub("^v", "")
    local y, m, d, hm = text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if y then
        return tonumber(y) or 0, tonumber(m) or 0, tonumber(d) or 0, tonumber(hm) or 0
    end

    local nums = {}
    for n in text:gmatch("(%d+)") do
        nums[#nums + 1] = tonumber(n) or 0
    end
    if #nums == 0 then return nil end
    while #nums < 4 do nums[#nums + 1] = 0 end
    return nums[1], nums[2], nums[3], nums[4]
end

local function VersionToScore(versionText)
    local y, m, d, hm = ParseVersion(versionText)
    if not y then return nil end
    return y * 100000000 + m * 1000000 + d * 10000 + hm
end

local function IsVersionNewer(newVersion, oldVersion)
    if not oldVersion or oldVersion == "" then return true end
    local n = VersionToScore(newVersion)
    local o = VersionToScore(oldVersion)
    if n and o then
        return n > o
    end
    return tostring(newVersion) ~= tostring(oldVersion)
end

local function MarkSeenVersion()
    local CL_DB = GetChangelogDB()
    CL_DB.LastSeenVersion = GetCurrentVersion()
    CL_DB.LastSeenAt = date("%Y-%m-%d %H:%M:%S")
end

local function MarkPopupShown()
    local CL_DB = GetChangelogDB()
    CL_DB.LastPopupVersion = GetCurrentVersion()
    CL_DB.LastPopupAt = date("%Y-%m-%d %H:%M:%S")
end

local function SplitLines(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    if text == "" then return lines end
    text = text .. "\n"
    for line in text:gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function ResolveSpellLinkToken(spellIDText)
    local spellID = tonumber(spellIDText)
    if not spellID then
        return "%" .. tostring(spellIDText or "")
    end

    local iconMarkup = ""
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local okIcon, iconFileID = pcall(C_Spell.GetSpellTexture, spellID)
        if okIcon and iconFileID then
            iconMarkup = string.format("|T%s:0|t ", tostring(iconFileID))
        end
    end

    if C_Spell and type(C_Spell.GetSpellLink) == "function" then
        local ok, spellLink = pcall(C_Spell.GetSpellLink, spellID)
        if ok and type(spellLink) == "string" and spellLink ~= "" then
            return iconMarkup .. spellLink
        end
    end

    return string.format("%s|cffff7d0a[spell:%d]|r", iconMarkup, spellID)
end

local function GetChangelogLocale()
    if ExBoss and type(ExBoss.GetEffectiveLocale) == "function" and type(ExBoss.GetLocaleMode) == "function" then
        local locale = tostring(ExBoss:GetEffectiveLocale(ExBoss:GetLocaleMode()) or ""):gsub("%s+", "")
        if locale ~= "" then
            if locale == "enGB" then locale = "enUS" end
            return locale
        end
    end
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale()
    if not locale or locale == "" then
        ---@diagnostic disable-next-line: undefined-global
        locale = (GetLocale and GetLocale()) or "zhCN"
    end
    if locale == "enGB" then locale = "enUS" end
    return locale
end

local function ResolveLocalizedName(meta, fallback)
    if not meta then return fallback end
    local locale = GetChangelogLocale()
    local name = meta[locale]
    if name and name ~= "" then return name end
    local isCN = (locale == "zhCN" or locale == "zhTW")
    if isCN then return meta.zhCN or meta.name or fallback end
    return meta.enUS or meta.nameEN or meta.name or fallback
end

local function ResolveInstanceToken(idText)
    local mapID = tonumber(idText)
    if not mapID then return "%i:" .. tostring(idText or "") end
    local db = ExwindTools and ExwindTools.DB_Static
    if not db then return "%i:" .. idText end
    local meta = db:GetInstanceNoteMetaByMapID(mapID)
    local name = ResolveLocalizedName(meta, "%i:" .. idText)
    return string.format("|cffffb84d%s|r", name)
end

local function ResolveEncounterToken(idText)
    local encID = tonumber(idText)
    if not encID then return "%e:" .. tostring(idText or "") end
    local db = ExwindTools and ExwindTools.DB_Static
    if not db then return "%e:" .. idText end
    local meta = db:GetEncounterNoteMeta(encID)
    local name = ResolveLocalizedName(meta, "%e:" .. idText)
    return string.format("|cffffb84d%s|r", name)
end

local function ResolveNPCToken(idText)
    local npcID = tonumber(idText)
    if not npcID then return "%n:" .. tostring(idText or "") end
    local locale = GetChangelogLocale()
    local trashLocale = rawget(_G, "EXBOSS_TRASH_CD_LOCALE")
    if trashLocale and trashLocale[npcID] then
        local entry = trashLocale[npcID]
        local name = entry[locale] or entry.enUS or entry.zhCN
        if name and name ~= "" then
            return string.format("|cffffb84d%s|r", name)
        end
    end
    return "%n:" .. idText
end

local function ReplaceSpellTokens(text)
    text = tostring(text or "")
    text = text:gsub("%%s:(%d+)", ResolveSpellLinkToken)
    text = text:gsub("%%i:(%d+)", ResolveInstanceToken)
    text = text:gsub("%%e:(%d+)", ResolveEncounterToken)
    text = text:gsub("%%n:(%d+)", ResolveNPCToken)
    text = text:gsub("%%(%d+)", ResolveSpellLinkToken)
    return text
end

local function ExtractSpellIDs(text)
    local ids = {}
    text = tostring(text or "")
    for spellIDText in text:gmatch("%%s:(%d+)") do
        local spellID = tonumber(spellIDText)
        if spellID then ids[#ids + 1] = spellID end
    end
    for spellIDText in text:gmatch("%%(%d+)") do
        local spellID = tonumber(spellIDText)
        if spellID then ids[#ids + 1] = spellID end
    end
    return ids
end

local function BuildInteractiveText(text)
    local lines = SplitLines(text)
    local out = {}

    for i = 1, #lines do
        local line = tostring(lines[i] or "")
        local h2 = line:match("^%s*@H2@%s*(.+)$") or line:match("^%s*##%s+(.+)$")
        local h1 = line:match("^%s*@H1@%s*(.+)$") or line:match("^%s*#%s+(.+)$")

        if h2 then
            out[#out + 1] = ReplaceSpellTokens(h2)
            out[#out + 1] = ""
        elseif h1 then
            h1 = h1:gsub("%s+%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d$", "")
            out[#out + 1] = h1
            out[#out + 1] = ""
        elseif line:match("^%s*$") then
            out[#out + 1] = ""
        else
            out[#out + 1] = ReplaceSpellTokens(line)
        end
    end

    return table.concat(out, "\n")
end

local function ResolveLineStyle(line, baseSize)
    local h2 = line:match("^%s*@H2@%s*(.+)$") or line:match("^%s*##%s+(.+)$")
    if h2 then
        return h2, baseSize + 3, PANEL_THEME.H2Text, "", 7, "h2"
    end

    local h1 = line:match("^%s*@H1@%s*(.+)$") or line:match("^%s*#%s+(.+)$")
    if h1 then
        h1 = h1:gsub("%s+%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d$", "")
        return h1, baseSize + 11, PANEL_THEME.H1Text, "OUTLINE", 10, "h1"
    end

    if line:match("^%s*$") then
        return "", baseSize, PANEL_THEME.BodyText, "", math.max(6, math.floor(baseSize * 0.5)), "blank"
    end

    if line:match("^%s*备注:") then
        return line, baseSize, PANEL_THEME.NoteText, "", math.max(6, math.floor(baseSize * 0.48)), "note"
    end

    if line:match("^%s*%-") then
        return line, baseSize, PANEL_THEME.BulletText, "", math.max(4, math.floor(baseSize * 0.42)), "bullet"
    end

    return line, baseSize, PANEL_THEME.BodyText, "", math.max(4, math.floor(baseSize * 0.4)), "body"
end

local function AcquireLine(frame, index)
    frame.LinePool = frame.LinePool or {}
    local fs = frame.LinePool[index]
    if fs then return fs end

    fs = frame.ScrollChild:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if fs.SetNonSpaceWrap then
        fs:SetNonSpaceWrap(true)
    end
    frame.LinePool[index] = fs
    return fs
end

local function AcquireDivider(frame, index)
    frame.DividerPool = frame.DividerPool or {}
    local tex = frame.DividerPool[index]
    if tex then return tex end

    tex = frame.ScrollChild:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(unpack(PANEL_THEME.DividerText))
    frame.DividerPool[index] = tex
    return tex
end

local function AcquireLineHotspot(frame, index)
    frame.LineHotspotPool = frame.LineHotspotPool or {}
    local btn = frame.LineHotspotPool[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, frame.ScrollChild)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function(self)
        local spellID = self.spellID
        if not spellID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(spellID)
        else
            GameTooltip:SetHyperlink("spell:" .. tostring(spellID))
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, button)
        local spellID = self.spellID
        if not spellID then
            return
        end
        local link = nil
        if C_Spell and type(C_Spell.GetSpellLink) == "function" then
            local ok, spellLink = pcall(C_Spell.GetSpellLink, spellID)
            if ok and type(spellLink) == "string" and spellLink ~= "" then
                link = spellLink:match("|H([^|]+)|h")
            end
        end
        SetItemRef(link or ("spell:" .. tostring(spellID)), "spell:" .. tostring(spellID), button, self)
    end)
    frame.LineHotspotPool[index] = btn
    return btn
end

local function GetMeasureFS(frame)
    if not frame.MeasureFS then
        frame.MeasureFS = frame.ScrollChild:CreateFontString(nil, "OVERLAY")
        frame.MeasureFS:SetAlpha(0)
        frame.MeasureFS:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 0, 0)
    end
    return frame.MeasureFS
end

local function ShouldShowLine(line)
    local isChinese = (function()
        local locale = GetChangelogLocale()
        return locale == "zhCN" or locale == "zhTW"
    end)()
    if line:match("^@CN@") then return isChinese end
    if line:match("^@EN@") then return not isChinese end
    return true
end

local function StripLocalePrefix(line)
    return (line:gsub("^@[CE][NE]@%s?", ""))
end

local function RenderRichContent(frame, text, contentWidth, baseSize)
    frame.LinePool = frame.LinePool or {}
    frame.DividerPool = frame.DividerPool or {}
    frame.LineHotspotPool = frame.LineHotspotPool or {}
    local lines = SplitLines(text)
    local y = 0
    local seenH1 = false
    local dividerIndex = 0
    local hotspotIndex = 0

    for i = 1, #lines do
        local fs = AcquireLine(frame, i)
        local rawLine = lines[i]

        if not ShouldShowLine(rawLine) then
            fs:Hide()
        else
            rawLine = StripLocalePrefix(rawLine)

            local lineText, fontSize, color, flags, bottomGap, styleType = ResolveLineStyle(rawLine, baseSize)
            local lineTextPre = lineText
            lineText = ReplaceSpellTokens(lineText)

            if styleType == "h1" then
                if seenH1 then
                    y = y + math.max(18, math.floor(baseSize * 1.4))
                end
                seenH1 = true
            end

            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetWidth(contentWidth)
            fs:SetFont(FONT_PATH, fontSize, flags)
            fs:SetTextColor(color[1], color[2], color[3], color[4])

            if lineText == "" then
                fs:SetText(" ")
                y = y + bottomGap
            else
                fs:SetText(lineText)
                local spellIDs = ExtractSpellIDs(rawLine)
                if #spellIDs > 0 then
                    hotspotIndex = hotspotIndex + 1
                    local hotspot = AcquireLineHotspot(frame, hotspotIndex)
                    hotspot:ClearAllPoints()
                    local xOffset = 0
                    local prefix = lineTextPre:match("^(.-)%%s:%d+") or lineTextPre:match("^(.-)%%%d+")
                    if prefix and prefix ~= "" then
                        local ruler = GetMeasureFS(frame)
                        ruler:SetFont(FONT_PATH, fontSize, flags)
                        ruler:SetText(prefix)
                        xOffset = math.max(0, ruler:GetStringWidth())
                    end
                    hotspot:SetPoint("TOPLEFT", fs, "TOPLEFT", xOffset, 0)
                    hotspot:SetSize(math.max(1, math.min(contentWidth - xOffset, fs:GetStringWidth() - xOffset)), math.max(fontSize + 4, fs:GetStringHeight()))
                    hotspot.spellID = spellIDs[1]
                    hotspot:Show()
                end
                y = y + fs:GetStringHeight() + bottomGap
                if styleType == "h1" then
                    dividerIndex = dividerIndex + 1
                    local divider = AcquireDivider(frame, dividerIndex)
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", 0, -y)
                    divider:SetSize(contentWidth, 1)
                    divider:Show()
                    y = y + 12
                end
            end
            fs:Show()
        end
    end

    for i = #lines + 1, #frame.LinePool do
        frame.LinePool[i]:Hide()
    end
    for i = dividerIndex + 1, #frame.DividerPool do
        frame.DividerPool[i]:Hide()
    end
    for i = hotspotIndex + 1, #frame.LineHotspotPool do
        frame.LineHotspotPool[i].spellID = nil
        frame.LineHotspotPool[i]:Hide()
    end

    frame.ScrollChild:SetSize(contentWidth, math.max(1, y + 10))
end

local function EnsureHTMLRenderer(frame)
    if frame.HTML then
        return frame.HTML
    end

    local html = CreateFrame("SimpleHTML", nil, frame.ScrollChild)
    html:SetPoint("TOPLEFT", 0, 0)
    html:SetWidth(1)
    html:SetHeight(MAX_SCROLL_CONTENT_HEIGHT)
    html:EnableMouse(true)
    html:SetHyperlinksEnabled(true)
    html:SetScript("OnHyperlinkEnter", function(self, link)
        if not link or link == "" then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    html:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)
    html:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button, self)
    end)

    frame.HTML = html
    return html
end

local function HideLegacyContent(frame)
    if frame.LinePool then
        for i = 1, #frame.LinePool do
            frame.LinePool[i]:Hide()
        end
    end
    if frame.DividerPool then
        for i = 1, #frame.DividerPool do
            frame.DividerPool[i]:Hide()
        end
    end
end

local function RenderHTMLContent(frame, text, contentWidth, baseSize)
    local html = EnsureHTMLRenderer(frame)
    local plainText = BuildInteractiveText(text)
    HideLegacyContent(frame)
    html:ClearAllPoints()
    html:SetPoint("TOPLEFT", 0, 0)
    html:SetWidth(contentWidth)
    html:SetHeight(MAX_SCROLL_CONTENT_HEIGHT)
    html:SetFont(FONT_PATH, baseSize, "")
    html:SetTextColor(unpack(PANEL_THEME.BodyText))
    html:SetText(plainText)
    html:Show()
    frame.ScrollChild:SetSize(contentWidth, MAX_SCROLL_CONTENT_HEIGHT)
end

local function EnsureChangelogFrame()
    if changelogFrame then return changelogFrame end

    changelogFrame = CreateFrame("Frame", "ExBossChangelogFrame", UIParent, "BackdropTemplate")
    changelogFrame:SetSize(860, 620)
    changelogFrame:SetBackdrop(PANEL_BACKDROP)
    changelogFrame:SetBackdropColor(unpack(PANEL_THEME.Background))
    changelogFrame:SetBackdropBorderColor(unpack(PANEL_THEME.Border))

    changelogFrame:SetPoint("CENTER")
    changelogFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    changelogFrame:SetFrameLevel(200)
    changelogFrame:SetToplevel(true)
    changelogFrame:SetMovable(true)
    changelogFrame:EnableMouse(true)
    changelogFrame:RegisterForDrag("LeftButton")
    changelogFrame:SetClampedToScreen(false)
    changelogFrame:SetScript("OnDragStart", changelogFrame.StartMoving)
    changelogFrame:SetScript("OnDragStop", changelogFrame.StopMovingOrSizing)
    changelogFrame:SetScript("OnHide", function()
        GameTooltip:Hide()
    end)

    local close = CreateFrame("Button", nil, changelogFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() changelogFrame:Hide() end)
    changelogFrame.CloseButton = close

    local scrollFrame = CreateFrame("ScrollFrame", nil, changelogFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 18)
    changelogFrame.ScrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    changelogFrame.ScrollChild = scrollChild
    changelogFrame.LinePool = {}
    changelogFrame.DividerPool = {}
    changelogFrame.LineHotspotPool = {}

    tinsert(UISpecialFrames, "ExBossChangelogFrame")

    local ElvUISkin = ExwindTools and ExwindTools.ElvUISkin
    local NDuiSkin = ExwindTools and ExwindTools.NDuiSkin

    if ElvUISkin and ElvUISkin:IsElvUILoaded() then
        local E = _G.ElvUI and _G.ElvUI[1]
        local S = E and E:GetModule("Skins", true)
        if S then
            pcall(function()
                if changelogFrame.SetTemplate then
                    changelogFrame:SetTemplate("Transparent")
                end
                if S.HandleCloseButton and changelogFrame.CloseButton then
                    S:HandleCloseButton(changelogFrame.CloseButton)
                end
                local sb = scrollFrame.ScrollBar
                if sb and S.HandleScrollBar then
                    S:HandleScrollBar(sb)
                end
            end)
        end
    elseif NDuiSkin and NDuiSkin:IsNDuiLoaded() then
        local NDui = _G.NDui
        local B = NDui and NDui[1]
        if B then
            pcall(function()
                B.CreateBD(changelogFrame)
                B.CreateSD(changelogFrame, nil, true)
                B.CreateTex(changelogFrame)
                if changelogFrame.CloseButton then
                    B.ReskinClose(changelogFrame.CloseButton)
                end
                local sb = scrollFrame.ScrollBar
                if sb then
                    B.ReskinScroll(sb)
                end
            end)
        end
    end

    changelogFrame:Hide()
    return changelogFrame
end

local function RefreshChangelogFrame()
    local frame = EnsureChangelogFrame()
    local fontSize = GetChangelogFontSize()
    local text = GetChangelogContent()
    local contentWidth = math.max(320, frame:GetWidth() - 62)
    if frame.HTML then
        frame.HTML:Hide()
    end
    RenderRichContent(frame, text, contentWidth, fontSize)
    frame.ScrollFrame:SetVerticalScroll(0)
end

function ExBoss:ShowChangelog(options)
    options = options or {}
    MarkSeenVersion()
    RefreshChangelogFrame()
    changelogFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    changelogFrame:SetFrameLevel(200)
    changelogFrame:Show()
    changelogFrame:Raise()

    if options.markShown ~= false then
        MarkPopupShown()
    end
end

function ExBoss:ShouldPopupChangelog()
    local currentVersion = GetCurrentVersion()
    local CL_DB = GetChangelogDB()
    local lastPopupVersion = CL_DB.LastPopupVersion
    return IsVersionNewer(currentVersion, lastPopupVersion)
end

function ExBoss:HandleChangelogPopupOnUIOpen()
    MarkSeenVersion()
    if not self:ShouldPopupChangelog() then return end
    self:ShowChangelog({ markShown = true })
end

MarkSeenVersion()
