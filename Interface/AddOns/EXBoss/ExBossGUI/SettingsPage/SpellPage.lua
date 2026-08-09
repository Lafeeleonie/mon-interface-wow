---@diagnostic disable: undefined-global, undefined-field
-- =============================================================
-- ExBossGUI/SettingsPage/SpellPage.lua
-- 法术设置页：按 Boss 浏览每条技能，可覆盖显示/预警开关
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI.Panel.SpellPage = ExBoss.UI.Panel.SpellPage or {}
local Page = ExBoss.UI.Panel.SpellPage
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

-- ── 布局常量 ─────────────────────────────────────────────────
local BOSS_BTN_H   = 28
local BOSS_BTN_W   = 200
local ROW_H        = 26
local COL_SPELL_W  = 180
local COL_CHECK_W  = 90

-- ── 运行时状态 ────────────────────────────────────────────────
local root
local bossScrollFrame, bossScrollChild
local spellScrollFrame, spellScrollChild
local selectedEncounterID
local activeBossButtons = {}
local activeSpellRows   = {}

-- ── DB 访问 ──────────────────────────────────────────────────
local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function OverrideDB(eventID, createIfMissing)
    local cfg = GetBossConfig()
    if cfg and cfg.GetOverrideRootForEvent then
        local db = cfg:GetOverrideRootForEvent(eventID, createIfMissing == true)
        if type(db) == "table" then
            return db
        end
    end
    return nil
end

local function GetOverride(encounterID, spellID, createIfMissing)
    local db = OverrideDB(spellID, createIfMissing)
    if type(db) ~= "table" then
        return nil
    end
    local row = db[spellID]
    if type(row) ~= "table" and createIfMissing == true then
        row = {}
        db[spellID] = row
    end
    return row
end

local function SaveActiveProfileForEvent(eventID)
    local cfg = GetBossConfig()
    if cfg and cfg.CompactEventOverride then
        cfg:CompactEventOverride(eventID)
    end
    if cfg and cfg.ApplyPersistedChange then
        cfg:ApplyPersistedChange(eventID)
    end
    local Profiles = ExBoss and ExBoss.Voice and ExBoss.Voice.Profiles
    if Profiles and Profiles.SaveEventToActiveProfile then
        Profiles:SaveEventToActiveProfile(eventID)
    end
end

-- ── 取原始技能默认值 ─────────────────────────────────────────
local function GetSkillDefault(skill, field)
    if field == "showBunBar"   then return skill.showBunBar  ~= false end
    if field == "showTimerBar" then return skill.showTimerBar ~= false end
    if field == "screenAlert"  then return skill.screenAlert == true end
    if field == "preAlert"     then return skill.preAlert or 5 end
    return nil
end

local function GetEffectiveValue(encounterID, spellID, skill, field)
    local ov = GetOverride(encounterID, spellID, false)
    if type(ov) == "table" and ov[field] ~= nil then return ov[field] end
    return GetSkillDefault(skill, field)
end

-- ── 法术行构建 ───────────────────────────────────────────────
local function BuildSpellRows(encounterID)
    -- 清空旧行
    for _, row in ipairs(activeSpellRows) do
        row:Hide()
    end
    activeSpellRows = {}

    if not spellScrollChild then return end

    local bossDef = ExBoss.Timeline._bosses and ExBoss.Timeline._bosses[encounterID]
    if not bossDef or not bossDef.skills then
        local empty = spellScrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        empty:SetPoint("TOPLEFT", 8, -8)
        empty:SetText(L["该 Boss 无固定时间轴技能数据"])
        table.insert(activeSpellRows, empty)
        return
    end

    -- 表头
    local header = CreateFrame("Frame", nil, spellScrollChild)
    header:SetSize(spellScrollChild:GetWidth() or 600, ROW_H)
    header:SetPoint("TOPLEFT", 0, 0)
    local function MakeHeaderLabel(text, x, w)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(1, 0.82, 0.45)
        return fs
    end
    MakeHeaderLabel(L["技能名称"],  8,             COL_SPELL_W)
    MakeHeaderLabel(L["束状条"],    8 + COL_SPELL_W,            COL_CHECK_W)
    MakeHeaderLabel(L["计时条"],    8 + COL_SPELL_W + COL_CHECK_W,     COL_CHECK_W)
    MakeHeaderLabel(L["屏幕警告"],  8 + COL_SPELL_W + COL_CHECK_W * 2, COL_CHECK_W)
    MakeHeaderLabel(L["预警(秒)"],  8 + COL_SPELL_W + COL_CHECK_W * 3, COL_CHECK_W)
    table.insert(activeSpellRows, header)

    -- 分隔线
    local sep = spellScrollChild:CreateTexture(nil, "BACKGROUND")
    sep:SetColorTexture(1, 0.82, 0.45, 0.3)
    sep:SetPoint("TOPLEFT", 0, -ROW_H)
    sep:SetSize((spellScrollChild:GetWidth() or 600) - 4, 1)
    table.insert(activeSpellRows, sep)

    local yOff = -(ROW_H + 2)
    local barPriorityColor = {
        [1] = { 1.0, 0.3, 0.3 },
        [2] = { 1.0, 0.8, 0.2 },
        [3] = { 0.6, 0.6, 0.6 },
    }

    for _, skill in ipairs(bossDef.skills) do
        local spellID = skill.spellID
        local eventID = tonumber(skill.eventID) or tonumber(spellID)
        local row = CreateFrame("Frame", nil, spellScrollChild)
        row:SetSize((spellScrollChild:GetWidth() or 600), ROW_H)
        row:SetPoint("TOPLEFT", 0, yOff)

        -- 背景
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.15)

        -- 技能名（带优先级颜色）
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 8, 0)
        nameFS:SetWidth(COL_SPELL_W - 4)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText(skill.displayName or tostring(spellID))
        local pc = barPriorityColor[skill.barPriority or 2]
        if pc then nameFS:SetTextColor(pc[1], pc[2], pc[3]) end

        -- 三个复选框（showBunBar / showTimerBar / screenAlert）
        local checkFields = { "showBunBar", "showTimerBar", "screenAlert" }
        for ci, field in ipairs(checkFields) do
            local xPos = 8 + COL_SPELL_W + COL_CHECK_W * (ci - 1) + 10
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(20, 20)
            cb:SetPoint("LEFT", row, "LEFT", xPos, 0)
            cb:SetChecked(GetEffectiveValue(encounterID, spellID, skill, field))
            cb:SetScript("OnClick", function(self)
                local ov = GetOverride(encounterID, spellID, true)
                ov[field] = (self:GetChecked() == true)
                SaveActiveProfileForEvent(eventID)
            end)
        end

        -- 预警秒数输入框
        local xPreAlert = 8 + COL_SPELL_W + COL_CHECK_W * 3 + 8
        local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        eb:SetSize(50, 20)
        eb:SetPoint("LEFT", row, "LEFT", xPreAlert, 0)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(4)
        eb:SetNumeric(true)
        eb:SetText(tostring(GetEffectiveValue(encounterID, spellID, skill, "preAlert")))
        eb:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v and v >= 0 and v <= 30 then
                local ov = GetOverride(encounterID, spellID, true)
                ov.preAlert = v
                SaveActiveProfileForEvent(eventID)
            end
            self:ClearFocus()
        end)

        -- 重置按钮（单行）
        local resetBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        resetBtn:SetSize(40, 18)
        resetBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        resetBtn:SetText(L["重置"])
        resetBtn:SetScript("OnClick", function()
            local db = OverrideDB()
            db[spellID] = nil
            SaveActiveProfileForEvent(eventID)
            -- 刷新本行
            BuildSpellRows(encounterID)
        end)

        table.insert(activeSpellRows, row)
        yOff = yOff - ROW_H - 2
    end

    spellScrollChild:SetHeight(math.abs(yOff) + 8)
end

-- ── Boss 列表构建 ─────────────────────────────────────────────
local function BuildBossList()
    for _, btn in ipairs(activeBossButtons) do btn:Hide() end
    activeBossButtons = {}

    if not bossScrollChild then return end

    local bosses = ExBoss.Timeline and ExBoss.Timeline._bosses
    if not bosses then return end

    -- 按 mapID 分组排序
    local grouped = {}  -- { mapID -> { {encounterID, bossDef}, ... } }
    for eid, def in pairs(bosses) do
        local mid = def.mapID or 0
        grouped[mid] = grouped[mid] or {}
        table.insert(grouped[mid], { eid = eid, def = def })
    end
    -- mapID 排序
    local mapIDs = {}
    for mid in pairs(grouped) do table.insert(mapIDs, mid) end
    table.sort(mapIDs)

    local yOff = 0
    for _, mid in ipairs(mapIDs) do
        local list = grouped[mid]
        table.sort(list, function(a, b) return a.eid < b.eid end)

        -- 副本小标题
        local maps = _G.EXBossData and _G.EXBossData.GetEncounterDataRoot and _G.EXBossData.GetEncounterDataRoot()
        local encData = maps and maps[mid]
        local mapName = (encData and (encData.mapName or encData.name)) or (L["副本 "] .. tostring(mid))
        local titleFS = bossScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleFS:SetPoint("TOPLEFT", 6, yOff - 4)
        titleFS:SetWidth(BOSS_BTN_W - 10)
        titleFS:SetJustifyH("LEFT")
        titleFS:SetText(mapName)
        titleFS:SetTextColor(0.6, 0.8, 1.0)
        table.insert(activeBossButtons, titleFS)
        yOff = yOff - 20

        for _, item in ipairs(list) do
            local eid = item.eid
            local def = item.def
            local btn = CreateFrame("Button", nil, bossScrollChild)
            btn:SetSize(BOSS_BTN_W, BOSS_BTN_H)
            btn:SetPoint("TOPLEFT", 0, yOff)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg._btn = btn
            btn._bg = bg

            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
            fs:SetWidth(BOSS_BTN_W - 16)
            fs:SetJustifyH("LEFT")
            fs:SetText(def.name or tostring(eid))
            btn._fs = fs

            local function Refresh()
                local active = (selectedEncounterID == eid)
                bg:SetColorTexture(active and 0.2 or 0.05, active and 0.4 or 0.05, active and 0.7 or 0.05, 1)
                fs:SetTextColor(active and 1 or 0.8, active and 1 or 0.8, active and 1 or 0.8)
            end
            btn._refresh = Refresh
            Refresh()

            btn:SetScript("OnClick", function()
                selectedEncounterID = eid
                for _, b in ipairs(activeBossButtons) do
                    if b._refresh then b._refresh() end
                end
                BuildSpellRows(eid)
            end)

            table.insert(activeBossButtons, btn)
            yOff = yOff - BOSS_BTN_H - 2
        end
        yOff = yOff - 6
    end

    bossScrollChild:SetHeight(math.abs(yOff) + 8)
end

-- ── UI 初始化 ─────────────────────────────────────────────────
local function EnsureUI(contentFrame)
    if root then return end

    root = CreateFrame("Frame", nil, contentFrame)
    root:SetAllPoints(contentFrame)

    -- 左侧 Boss 列表
    local LEFT_W = 210
    local leftPanel = CreateFrame("Frame", nil, root)
    leftPanel:SetPoint("TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(LEFT_W)

    local leftBg = leftPanel:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints()
    leftBg:SetColorTexture(0.05, 0.05, 0.06, 0.6)

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 8, -8)
    leftTitle:SetText(L["选择 Boss"])
    leftTitle:SetTextColor(1, 0.82, 0.45)

    bossScrollFrame = CreateFrame("ScrollFrame", nil, leftPanel, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(bossScrollFrame)
    end
    bossScrollFrame:SetPoint("TOPLEFT", 0, -28)
    bossScrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -20, 4)

    bossScrollChild = CreateFrame("Frame", nil, bossScrollFrame)
    bossScrollChild:SetWidth(LEFT_W - 22)
    bossScrollChild:SetHeight(400)
    bossScrollFrame:SetScrollChild(bossScrollChild)

    -- 右侧法术设置区
    local rightPanel = CreateFrame("Frame", nil, root)
    rightPanel:SetPoint("TOPLEFT", LEFT_W + 4, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", 8, -8)
    rightTitle:SetText(L["技能显示设置"])
    rightTitle:SetTextColor(1, 0.82, 0.45)

    local hint = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -26)
    hint:SetText(L["勾选控制每条技能是否在束状条/计时条/屏幕显示，预警秒数可单独调整。留空=使用技能默认值。"])
    hint:SetWidth(rightPanel:GetWidth() and (rightPanel:GetWidth() - 16) or 600)
    hint:SetJustifyH("LEFT")

    spellScrollFrame = CreateFrame("ScrollFrame", nil, rightPanel, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(spellScrollFrame)
    end
    spellScrollFrame:SetPoint("TOPLEFT", 0, -44)
    spellScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -20, 4)

    spellScrollChild = CreateFrame("Frame", nil, spellScrollFrame)
    spellScrollChild:SetWidth((rightPanel:GetWidth() or 700) - 22)
    spellScrollChild:SetHeight(400)
    spellScrollFrame:SetScrollChild(spellScrollChild)

    BuildBossList()
end

-- ── Page 接口 ─────────────────────────────────────────────────
function Page:Render(contentFrame)
    EnsureUI(contentFrame)
    root:SetParent(contentFrame)
    root:ClearAllPoints()
    root:SetAllPoints(contentFrame)
    root:Show()
    BuildBossList()
    if selectedEncounterID then
        BuildSpellRows(selectedEncounterID)
    end
end

function Page:Hide()
    if root then root:Hide() end
end
