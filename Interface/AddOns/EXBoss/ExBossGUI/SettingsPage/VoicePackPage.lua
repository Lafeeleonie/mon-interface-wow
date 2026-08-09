---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/VoicePackPage.lua
-- 语音包选择页
-- =============================================================

ExBoss.UI.Panel.VoicePackPage             = ExBoss.UI.Panel.VoicePackPage or {}
local Page                                = ExBoss.UI.Panel.VoicePackPage
local L                                   = (ExBoss and ExBoss.L) or
    setmetatable({}, { __index = function(_, k) return k end })

local root                                = nil
local packDropdown                        = nil
local ui                                  = {}
local RefreshInfo                         = nil
local RefreshPage                         = nil
local TrashStore                          = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local DEFAULT_VOICE_PACK                  = "EXWIND(默认)"
local ENGLISH_VOICE_PACK                  = "英文(ENG)"
local ENGLISH_VOICE_PACK_ADDON            = "EXBOSS-ENG"
local VOICE_PACK_LOCALE_MIGRATION_VERSION = 1
local NEW_MPLUS_AUTHOR_KEY                = "EXWIND_CN"
local NEW_TRASH_PRESET_KEY                = "builtin:EXWIND_CN"
local selectedTrashPresetKey              = nil
local selectedSettingsPresetKey           = nil

local THEME                               = {
    accent = { 1.00, 0.82, 0.22 },
    cyan   = { 0.24, 0.78, 1.00 },
    ok     = { 0.20, 0.95, 0.50 },
    muted  = { 0.55, 0.60, 0.68 },
    border = { 0.18, 0.22, 0.28 },
    cardBg = { 0.03, 0.04, 0.07 },
}

-- ─── 帮助函数 ─────────────────────────────────────────────────

local function Bg(parent, r, g, b, a)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(r or 0.03, g or 0.04, b or 0.07, a or 0.92)
    f:SetBackdropBorderColor(
        THEME.border[1], THEME.border[2], THEME.border[3], 0.95)
    return f
end

local function TopBar(parent, r, g, b)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, 0.95)
    t:SetHeight(2)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    return t
end

local function Divider(parent, anchor, offY)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(0.22, 0.26, 0.32, 0.85)
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY or -10)
    t:SetPoint("TOPRIGHT", parent, "RIGHT", -16, 0)
    return t
end

local function Chip(parent, r, g, b)
    local chip = Bg(parent, r * 0.18, g * 0.18, b * 0.18, 0.88)
    chip:SetBackdropBorderColor(r * 0.6, g * 0.6, b * 0.6, 0.90)
    local fs = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetTextColor(r, g, b)
    chip.label = fs
    return chip
end

-- ─── DB / 语音包工具 ──────────────────────────────────────────

local function GetClientLocaleTag()
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.GetCurrentLocale) == "function" then
        local locale = tostring(ExBoss.Locale:GetCurrentLocale() or ""):gsub("%s+", "")
        if locale ~= "" then
            if locale == "enGB" then
                return "enUS"
            end
            return locale
        end
    end
    if ExBoss and type(ExBoss.GetEffectiveLocale) == "function" and type(ExBoss.GetLocaleMode) == "function" then
        local locale = tostring(ExBoss:GetEffectiveLocale(ExBoss:GetLocaleMode()) or ""):gsub("%s+", "")
        if locale ~= "" then
            if locale == "enGB" then
                return "enUS"
            end
            return locale
        end
    end
    if type(GetLocale) == "function" then
        local locale = tostring(GetLocale() or ""):gsub("%s+", "")
        if locale == "enGB" then
            return "enUS"
        end
        return locale
    end
    return ""
end

local function IsEnglishClientLocale(locale)
    locale = tostring(locale or "")
    return locale == "enUS" or locale == "enGB"
end

local function HasInstalledVoicePack(addonName)
    addonName = tostring(addonName or "")
    if addonName == "" then
        return false
    end
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
        local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
        if title ~= nil then
            return true
        end
    end
    if type(GetAddOnMetadata) == "function" then
        local title = GetAddOnMetadata(addonName, "Title")
        if title ~= nil then
            return true
        end
    end
    return false
end

local function HasRegisteredVoicePack(packName)
    packName = tostring(packName or "")
    if packName == "" then
        return false
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return false
    end
    local prefix = "[" .. packName .. "]"
    for key in pairs(LSM:HashTable("sound") or {}) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function HasUsableVoicePack(addonName, packName)
    if not HasInstalledVoicePack(addonName) then
        return false
    end
    return HasRegisteredVoicePack(packName)
end

local function ResolveDefaultVoicePack()
    if IsEnglishClientLocale(GetClientLocaleTag()) and HasUsableVoicePack(ENGLISH_VOICE_PACK_ADDON, ENGLISH_VOICE_PACK) then
        return ENGLISH_VOICE_PACK
    end
    return DEFAULT_VOICE_PACK
end

local function ShouldForceEnglishVoicePack(globalCfg)
    if type(globalCfg) ~= "table" then
        return false
    end
    if not IsEnglishClientLocale(GetClientLocaleTag()) then
        return false
    end
    if not HasUsableVoicePack(ENGLISH_VOICE_PACK_ADDON, ENGLISH_VOICE_PACK) then
        return false
    end
    return globalCfg.allowNonEnglishVoicePackOnEnglishLocale ~= true
end

local function ApplyVoicePackLocaleMigration(globalCfg)
    if type(globalCfg) ~= "table" then
        return
    end
    local localeTag = GetClientLocaleTag()
    local migratedVersion = tonumber(globalCfg.localeVoicePackMigrationVersion)
    local migratedLocale = tostring(globalCfg.localeVoicePackMigrationLocale or "")
    local targetPack = ResolveDefaultVoicePack()

    if ShouldForceEnglishVoicePack(globalCfg) then
        globalCfg.selectedVoicePack = ENGLISH_VOICE_PACK
        return
    end

    if migratedVersion == VOICE_PACK_LOCALE_MIGRATION_VERSION and migratedLocale == localeTag then
        return
    end

    if migratedVersion ~= VOICE_PACK_LOCALE_MIGRATION_VERSION then
        globalCfg.selectedVoicePack = targetPack
    elseif globalCfg.selectedVoicePack == nil or globalCfg.selectedVoicePack == "" then
        globalCfg.selectedVoicePack = targetPack
    elseif migratedLocale ~= localeTag then
        globalCfg.selectedVoicePack = targetPack
    end

    globalCfg.localeVoicePackMigrationVersion = VOICE_PACK_LOCALE_MIGRATION_VERSION
    globalCfg.localeVoicePackMigrationLocale = localeTag
end

local function EnsureDB()
    ExBossDB = ExBossDB or {}
    ExBossDB.voice = ExBossDB.voice or {}
    ExBossDB.voice.global = ExBossDB.voice.global or {}
    local g = ExBossDB.voice.global
    ApplyVoicePackLocaleMigration(g)
    g.selectedVoicePack = g.selectedVoicePack or ResolveDefaultVoicePack()
    return g
end

local function GetVoicePacks()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local seen, list = {}, {}
    if LSM then
        for key in pairs(LSM:HashTable("sound") or {}) do
            local pack = key:match("^%[([^%]]+)%]")
            if pack and not seen[pack] then
                seen[pack] = true
                list[#list + 1] = pack
            end
        end
    end
    if #list == 0 then list[1] = "EXWIND(默认)" end
    table.sort(list)
    return list
end

local function RefreshPackDropdownText()
    if not packDropdown then
        return
    end
    local g = EnsureDB()
    packDropdown._currentValue = g.selectedVoicePack
    if packDropdown.SetText then
        packDropdown:SetText(g.selectedVoicePack or L["请选择..."])
    end
end

local function FinalizePackSelection(g, packName)
    local prev = g.selectedVoicePack
    g.selectedVoicePack = packName
    g.voicePackUserSelected = true
    g.localeVoicePackMigrationVersion = VOICE_PACK_LOCALE_MIGRATION_VERSION
    g.localeVoicePackMigrationLocale = GetClientLocaleTag()
    if packName ~= prev then
        local Eng = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
        if Eng and Eng.InvalidateLabelCache then Eng:InvalidateLabelCache() end
        if Eng and Eng.ApplyEventOverridesToAPI then
            local _, t = GetInstanceInfo()
            if t == "raid" or t == "party" then
                C_Timer.After(0, function() Eng:ApplyEventOverridesToAPI() end)
            end
        end
    end
    RefreshPackDropdownText()
end

local function ShowNonEnglishVoicePackConfirm(packName, onChanged)
    if not StaticPopupDialogs or not StaticPopup_Show then
        return false
    end
    local dialogKey = "EXBOSS_CONFIRM_NON_ENGLISH_VOICE_PACK"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["这是非英文语音包。\n确认后将停止英文环境下的自动强制切换。"],
            button1 = L["确定"],
            button2 = CANCEL,
            OnAccept = function(_, data)
                if type(data) ~= "table" then
                    return
                end
                local g = EnsureDB()
                g.allowNonEnglishVoicePackOnEnglishLocale = true
                FinalizePackSelection(g, data.packName)
                if type(data.onChanged) == "function" then
                    data.onChanged()
                end
            end,
            OnCancel = function()
                RefreshPackDropdownText()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(dialogKey, nil, nil, {
        packName = packName,
        onChanged = onChanged,
    })
    return true
end

local function SetPack(packName)
    local g = EnsureDB()
    if ShouldForceEnglishVoicePack(g) and tostring(packName or "") ~= ENGLISH_VOICE_PACK then
        local shown = ShowNonEnglishVoicePackConfirm(packName, function()
            if type(RefreshPage) == "function" then
                C_Timer.After(0, function()
                    RefreshPage(false)
                end)
            end
        end)
        if shown then
            return false
        end
    end
    FinalizePackSelection(g, packName)
    return true
end

local PACK_META = {
    ["英文(ENG)"] = {
        displayName = "English (ENG)",
        subtitle    = "English Voice Pack",
        description = "English voice pack with the same standard labels and filenames.",
        addonName   = "EXBOSS-ENG",
    },
    ["EXWIND(默认)"] = {
        displayName = "EXWIND (Default)",
        subtitle    = L["ExBoss 官方默认语音包"],
        description = L["覆盖常见首领与大秘境语音标签，标准参考实现。"],
        addonName   = "EXBOSS-EXWIND",
    },
    ["忘忧景久"] = {
        displayName = "忘忧景久",
        subtitle    = L["中文配音语音包"],
        description = L["忘忧景久语音包，标签与默认包兼容，可直接替换全局语音。"],
        addonName   = "EXBOSS-WYJJ",
    },
    ["顾衣衿-少女音"] = {
        displayName = "顾衣衿 · 少女音",
        subtitle    = L["中文配音语音包"],
        description = L["顾衣衿少女音版本，保留同一套标签结构，便于统一切换。"],
        addonName   = "EXBOSS-GUYIJIN-GIRL",
    },
    ["顾衣衿-御姐音"] = {
        displayName = "顾衣衿 · 御姐音",
        subtitle    = L["中文配音语音包"],
        description = L["顾衣衿御姐音版本，保持标签兼容，适配现有副本方案。"],
        addonName   = "EXBOSS-GUYIJIN-LADY",
    },
    ["Kele"] = {
        displayName = "Kele",
        subtitle    = L["中文配音语音包"],
        description = L["Kele 语音包，标签兼容默认方案，可直接用于副本配置。"],
        addonName   = "EXBOSS-KELE",
    },
    ["夏一可"] = {
        displayName = "夏一可",
        subtitle    = L["中文配音语音包"],
        description = L["夏一可语音包，保持标准标签兼容，可直接切换使用。"],
        addonName   = "EXBOSS-XIAYIKE",
    },
    ["然然"] = {
        displayName = "然然",
        subtitle    = L["中文配音语音包"],
        description = L["然然语音包，包含标准标签与倒数语音。"],
        addonName   = "EXBOSS-RANRAN",
    },
    ["糖糖酱"] = {
        displayName = "糖糖酱",
        subtitle    = L["中文配音语音包"],
        description = L["糖糖酱语音包，标签结构与默认包兼容。"],
        addonName   = "EXBOSS-TANGTANGJIANG",
    },
    ["小羊(Yagi)"] = {
        displayName = "小羊 (Yagi)",
        subtitle    = L["中文配音语音包"],
        description = L["小羊 Yagi 语音包，包含标准标签与倒数语音。"],
        addonName   = "EXBOSS-YAGI",
    },
    ["你好牛(niuniu)"] = {
        displayName = "你好牛 (niuniu)",
        subtitle    = L["中文配音语音包"],
        description = L["你好牛语音包，来源目录为牛师傅，包含标准标签与倒数语音。"],
        addonName   = "EXBOSS-NIUNIU",
    },
    ["绫零(Ayarei)"] = {
        displayName = "绫零 (Ayarei)",
        subtitle    = L["中文配音语音包"],
        description = L["绫零语音包，使用标准标签结构，兼容默认包配置。"],
        addonName   = "EXBOSS-AYAREI",
    },
    ["露露緹婭"] = {
        displayName = "露露緹婭",
        subtitle    = L["中文配音语音包"],
        description = L["露露緹婭语音包，标签结构与默认包兼容。"],
        addonName   = "EXBOSS-RURU",
    },
}

local function NormalizePackKey(name)
    name = tostring(name or "")
    if PACK_META[name] then return name end
    local u = name:upper()
    if name:find("英文", 1, true) or u:find("EXBOSS%-ENG", 1, true) or u:find("%(ENG%)", 1, true) then return "英文(ENG)" end
    if name:find("忘忧景久", 1, true) or u:find("WYJJ", 1, true) then return "忘忧景久" end
    if name:find("少女音", 1, true) or u:find("GUYIJIN%-GIRL", 1, true) then return "顾衣衿-少女音" end
    if name:find("御姐音", 1, true) or u:find("GUYIJIN%-LADY", 1, true) then return "顾衣衿-御姐音" end
    if u:find("KELE", 1, true) then return "Kele" end
    if name:find("夏一可", 1, true) or u:find("XIAYIKE", 1, true) then return "夏一可" end
    if name:find("然然", 1, true) or u:find("RANRAN", 1, true) then return "然然" end
    if name:find("糖糖酱", 1, true) or u:find("TANGTANGJIANG", 1, true) then return "糖糖酱" end
    if name:find("小羊", 1, true) or u:find("YAGI", 1, true) then return "小羊(Yagi)" end
    if name:find("你好牛", 1, true) or name:find("牛师傅", 1, true) or u:find("NIUNIU", 1, true) then return "你好牛(niuniu)" end
    if name:find("绫零", 1, true) or u:find("AYAREI", 1, true) then return "绫零(Ayarei)" end
    if name:find("露露", 1, true) or name:find("緹婭", 1, true) or u:find("RURU", 1, true) or u:find("RURUTIA", 1, true) then
        return
        "露露緹婭"
    end
    if u:find("EXWIND", 1, true) then return "EXWIND(默认)" end
    return name
end

local function GetPackInfo(packName)
    local key   = NormalizePackKey(packName)
    local base  = PACK_META[key] or {}
    local addon = base.addonName
    local title, notes, author, version
    if addon and GetAddOnMetadata then
        title   = GetAddOnMetadata(addon, "Title")
        notes   = GetAddOnMetadata(addon, "Notes")
        author  = GetAddOnMetadata(addon, "Author")
        version = GetAddOnMetadata(addon, "Version")
    end
    local labelCount = 0
    local Catalog = ExBoss and ExBoss.Voice and ExBoss.Voice.LabelCatalog
    if Catalog and Catalog.GetPackLabels then
        local t = Catalog.GetPackLabels(packName)
        if type(t) == "table" then labelCount = #t end
    end
    return {
        displayName = (title ~= "" and title) or base.displayName or key,
        subtitle    = base.subtitle or "Voice Pack",
        description = (notes ~= "" and notes) or base.description or L["暂无描述"],
        author      = (author ~= "" and author) or L["—"],
        version     = version or L["—"],
        labelCount  = labelCount,
    }
end

local function BuildLabelSet(labels)
    local set = {}
    for i = 1, #(labels or {}) do
        local label = tostring(labels[i] or "")
        if label ~= "" then
            set[label] = true
        end
    end
    return set
end

local MISSING_LABEL_IGNORE = {
    ["54321"] = true,
    ["准备跑圈"] = true,
    ["准备追人"] = true,
    ["召唤小怪"] = true,
    ["坦克击退"] = true,
    ["注意击飞"] = true,
    ["集合放圈"] = true,
}

local function GetMissingLabelsForPack(packName)
    local Catalog = ExBoss and ExBoss.Voice and ExBoss.Voice.LabelCatalog
    if not (Catalog and Catalog.GetPackLabels) then
        return nil, L["标签目录未加载"]
    end

    local baseline = Catalog.GetPackLabels("EXWIND(默认)") or {}
    local current = Catalog.GetPackLabels(packName) or {}
    local currentSet = BuildLabelSet(current)

    local missing, seen = {}, {}
    for i = 1, #baseline do
        local label = tostring(baseline[i] or "")
        if label ~= "" and not MISSING_LABEL_IGNORE[label] and not currentSet[label] and not seen[label] then
            seen[label] = true
            missing[#missing + 1] = label
        end
    end
    return missing, nil
end

local function GetProfiles()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.Profiles
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local FindItemText

local function BuildAuthorItems(slotKey)
    local bossCfg = GetBossConfig()
    if bossCfg and bossCfg.GetAuthorItems then
        return bossCfg:GetAuthorItems(slotKey)
    end
    return {}
end

local MODULE_KEY = "ExBoss.VoicePackPage"
local GRID_COLS = 100
local scrollFrame = nil
local scrollChild = nil
local missingDepsText = nil
local pageSyncLock = false
local pageLayoutData = nil
local pageStatus = {
    configText = "",
    configOk = nil,
    settingsText = "",
    settingsError = false,
    trashText = "",
    trashError = false,
}

local function GetPageDBDefaults()
    return {
        selectedVoicePack = "",
        selectedSettingsPresetKey = "",
        selectedTrashPresetKey = "",
        slot_raid_tank = "",
        slot_raid_dps = "",
        slot_raid_heal = "",
        slot_mplus_tank = "",
        slot_mplus_dps = "",
        slot_mplus_heal = "",
    }
end

local function GetPageDB()
    if not (ExwindTools and ExwindTools.GetModuleDB) then
        return GetPageDBDefaults()
    end
    return ExwindTools:GetModuleDB(MODULE_KEY, GetPageDBDefaults())
end

local function IsGridEditActive()
    local Grid = _G.ExwindGrid
    return Grid and Grid.IsLiveEditing == true and Grid.LiveContainer == scrollChild
end

local function ApplyStatusColor(text, ok, isError)
    local value = tostring(text or "")
    if value == "" then
        return ""
    end
    if isError == true or ok == false then
        return "|cffff6666" .. value .. "|r"
    end
    if ok == true then
        return "|cff33ee77" .. value .. "|r"
    end
    return "|cffbfc8d6" .. value .. "|r"
end

local function BuildPackItemsForGrid()
    local items = {}
    local packs = GetVoicePacks()
    for i = 1, #packs do
        local pack = tostring(packs[i] or "")
        items[#items + 1] = { pack, pack }
    end
    return items
end

local function NormalizeGridSelection(items, currentValue)
    local value = tostring(currentValue or "")
    if value == "" then
        return items[1] and tostring(items[1][2] or items[1][1] or "") or ""
    end
    for i = 1, #items do
        local row = items[i]
        local candidate = type(row) == "table" and tostring(row[2] or row[1] or "") or tostring(row or "")
        if candidate == value then
            return value
        end
    end
    return items[1] and tostring(items[1][2] or items[1][1] or "") or ""
end

local function GetCurrentPackName()
    local db = GetPageDB()
    local value = tostring(db.selectedVoicePack or "")
    if value == "" then
        value = tostring(EnsureDB().selectedVoicePack or ResolveDefaultVoicePack())
    end
    return value
end

local function GetCurrentPackInfo()
    return GetPackInfo(GetCurrentPackName())
end

local function BuildMissingVoiceText()
    local missing, err = GetMissingLabelsForPack(GetCurrentPackName())
    if err then
        return string.format("|cffff6666%s|r\n%s", L["缺少语音：?"], tostring(err))
    end
    if type(missing) == "table" and #missing > 0 then
        return string.format("|cffffaa55%s|r\n%s", string.format(L["缺少语音：%d"], #missing), table.concat(missing, L["、"]))
    end
    return "|cff33dd88" .. L["缺少语音：0"] .. "|r\n" .. L["已覆盖默认语音标签"]
end

local function BuildSummaryText()
    local bossCfg = GetBossConfig()
    if not bossCfg then
        return L["Boss 配置模块未加载"]
    end
    local summary = bossCfg.GetSelectionSummary and bossCfg:GetSelectionSummary() or nil
    if type(summary) ~= "table" or #summary == 0 then
        return L["暂无槽位摘要"]
    end

    local lines = {}
    local slotLabels = {
        raid_tank = L["团本坦克"],
        raid_dps = L["团本DPS"],
        raid_heal = L["团本治疗"],
        mplus_tank = L["大米坦克"],
        mplus_dps = L["大米DPS"],
        mplus_heal = L["大米治疗"],
    }
    for i = 1, #summary do
        local item = summary[i]
        local slotKey = tostring(item.slotKey or "")
        local slotLabel = tostring(slotLabels[slotKey] or item.label or slotKey or "")
        lines[#lines + 1] = string.format("%s: %s", slotLabel, tostring(item.author or ""))
    end
    local role = ExwindTools and ExwindTools.State and tostring(ExwindTools.State.RoleKey or "") or "dps"
    local roleLabelMap = {
        tank = L["坦克"],
        heal = L["治疗"],
        healer = L["治疗"],
        dps = "DPS",
    }
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(L["当前职责：%s"], tostring(roleLabelMap[role] or role))
    return table.concat(lines, "\n")
end

local function BuildDefaultConfigStatusText()
    local bossCfg = GetBossConfig()
    if not bossCfg then
        return L["Boss 配置模块未加载"], false
    end
    return L["6 槽位作者方案已接入，副本页会按当前职责自动写入对应方案。"], nil
end

local function SetStatus(text, ok)
    pageStatus.configText = tostring(text or "")
    pageStatus.configOk = ok
    if type(RefreshPage) == "function" then
        RefreshPage(false)
    end
end

local function ShowReloadAfterAuthorSwitchConfirm(slotLabel)
    if not StaticPopupDialogs or not StaticPopup_Show then
        return
    end
    local dialogKey = "EXBOSS_AUTHOR_SWITCH_RELOAD_CONFIRM"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["切换成功：%s\n是否现在重载界面以完整生效？"],
            button1 = L["确定"],
            button2 = L["取消"],
            OnAccept = function()
                if ReloadUI then
                    ReloadUI()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(dialogKey, tostring(slotLabel or L["当前槽位"]))
end

local SLOT_ROWS = {
    { slot = "raid_tank", label = L["团本坦克"] },
    { slot = "raid_dps", label = L["团本DPS"] },
    { slot = "raid_heal", label = L["团本治疗"] },
    { slot = "mplus_tank", label = L["大米坦克"] },
    { slot = "mplus_dps", label = L["大米DPS"] },
    { slot = "mplus_heal", label = L["大米治疗"] },
}

local function ApplySlotSelection(slotKey, value)
    local bossCfg = GetBossConfig()
    if not bossCfg then
        SetStatus(L["Boss 配置模块未加载"], false)
        return
    end
    local ok, err = bossCfg:SetSelectedAuthor(slotKey, value)
    local slotLabel = tostring(bossCfg:GetSlotLabel(slotKey))
    SetStatus(ok and (L["已切换 "] .. slotLabel) or (L["应用失败："] .. tostring(err)), ok)
    local BossPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if BossPage and BossPage.RefreshSpellUI then
        BossPage:RefreshSpellUI()
    end
    if ok then
        ShowReloadAfterAuthorSwitchConfirm(slotLabel)
    end
end

local function SetTrashPresetStatus(text, isError)
    pageStatus.trashText = tostring(text or "")
    pageStatus.trashError = (isError == true)
    if type(RefreshPage) == "function" then
        RefreshPage(false)
    end
end

local function SetSettingsPresetStatus(text, isError)
    pageStatus.settingsText = tostring(text or "")
    pageStatus.settingsError = (isError == true)
    if type(RefreshPage) == "function" then
        RefreshPage(false)
    end
end

local function BuildSettingsPresetItems()
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetSettingsPluginPresetList) ~= "function" then
        return {}
    end
    local ok, rows = pcall(api.GetSettingsPluginPresetList)
    if not ok or type(rows) ~= "table" then
        return {}
    end
    local items = {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and type(row.settingsPageConfig) == "table" then
            local authorName = tostring(row.authorName or row.title or row.pluginKey or "")
            local pluginKey = tostring(row.pluginKey or "")
            local label = authorName
            if pluginKey ~= "" and pluginKey ~= authorName then
                label = string.format("%s (%s)", authorName, pluginKey)
            end
            items[#items + 1] = { label, pluginKey }
        end
    end
    return items
end

local function GetSelectedSettingsPresetRow()
    if not selectedSettingsPresetKey or selectedSettingsPresetKey == "" then
        return nil
    end
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetSettingsPluginPreset) ~= "function" then
        return nil
    end
    return api.GetSettingsPluginPreset(selectedSettingsPresetKey)
end

local function RefreshSettingsPresetControls()
    local items = BuildSettingsPresetItems()
    local value = NormalizeGridSelection(items, selectedSettingsPresetKey)
    selectedSettingsPresetKey = value

    if pageStatus.settingsText == "" then
        if value == "" then
            pageStatus.settingsText = L["当前没有可用的综合设置方案，请先在作者插件的 Presets/SettingsPage.lua 粘贴“导出Lua”。"]
            pageStatus.settingsError = false
        end
    elseif value ~= "" and (
            pageStatus.settingsText == L["当前没有可用的综合设置方案"]
            or pageStatus.settingsText == L["当前没有可用的综合设置方案，请先在作者插件的 Presets/SettingsPage.lua 粘贴“导出Lua”。"]
        ) then
        pageStatus.settingsText = ""
        pageStatus.settingsError = false
    end
end

local function ApplySelectedSettingsPreset()
    if not selectedSettingsPresetKey or selectedSettingsPresetKey == "" then
        SetSettingsPresetStatus(L["请先选择综合设置方案"], true)
        return
    end

    local row = GetSelectedSettingsPresetRow()
    if type(row) ~= "table" or type(row.settingsPageConfig) ~= "table" then
        SetSettingsPresetStatus(L["综合设置方案数据无效"], true)
        return
    end

    local IE = ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
    if not (type(IE) == "table" and type(IE.ApplySettingsPageConfig) == "function") then
        SetSettingsPresetStatus(L["综合设置方案导入接口未就绪"], true)
        return
    end

    local ok, err = IE:ApplySettingsPageConfig(row.settingsPageConfig)
    if not ok then
        SetSettingsPresetStatus(string.format("%s%s", L["导入综合设置失败："], tostring(err or "")), true)
        return
    end

    SetSettingsPresetStatus(L["综合设置已导入（覆盖当前本地设置）"], false)
end

local function ShowSettingsPresetImportConfirm()
    local row = GetSelectedSettingsPresetRow()
    local presetName = row and tostring(row.authorName or row.title or row.pluginKey or "") or ""
    if not StaticPopupDialogs or not StaticPopup_Show then
        ApplySelectedSettingsPreset()
        return
    end
    local dialogKey = "EXBOSS_SETTINGS_PRESET_IMPORT_CONFIRM"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["确认导入综合设置方案：%s ？\n这会直接覆盖当前本地综合设置。"],
            button1 = L["导入"],
            button2 = L["取消"],
            OnAccept = function()
                ApplySelectedSettingsPreset()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(dialogKey, presetName ~= "" and presetName or L["当前方案"])
end

local function BuildTrashPresetItems()
    local items = {}
    if not (TrashStore and type(TrashStore.GetPluginPresetItems) == "function") then
        return items
    end
    local rows = TrashStore.GetPluginPresetItems() or {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and type(row.trashConfig) == "table" then
            local authorName = tostring(row.authorName or row.title or row.pluginKey or "")
            local pluginKey = tostring(row.pluginKey or "")
            local label = authorName
            if pluginKey ~= "" and pluginKey ~= authorName then
                label = string.format("%s (%s)", authorName, pluginKey)
            end
            items[#items + 1] = { label, pluginKey }
        end
    end
    return items
end

local function GetSelectedTrashPresetRow()
    if not selectedTrashPresetKey or selectedTrashPresetKey == "" then
        return nil
    end
    if not (TrashStore and type(TrashStore.GetPluginPreset) == "function") then
        return nil
    end
    return TrashStore.GetPluginPreset(selectedTrashPresetKey)
end

local function RefreshTrashPresetControls()
    local items = BuildTrashPresetItems()
    local value = NormalizeGridSelection(items, selectedTrashPresetKey)
    selectedTrashPresetKey = value

    if pageStatus.trashText == "" then
        if value == "" then
            pageStatus.trashText = L["当前没有可用的小怪作者方案，请先在作者插件的 Presets/TrashConfig.lua 粘贴“导出Lua”。"]
            pageStatus.trashError = false
        end
    elseif value ~= "" and (
            pageStatus.trashText == L["当前没有可用的小怪作者方案"]
            or pageStatus.trashText == L["当前没有可用的小怪作者方案，请先在作者插件的 Presets/TrashConfig.lua 粘贴“导出Lua”。"]
        ) then
        pageStatus.trashText = ""
        pageStatus.trashError = false
    end
end

local function ApplySelectedTrashPreset()
    if not selectedTrashPresetKey or selectedTrashPresetKey == "" then
        SetTrashPresetStatus(L["请先选择小怪作者方案"], true)
        return
    end
    if not (TrashStore and type(TrashStore.ImportPluginPreset) == "function") then
        SetTrashPresetStatus(L["小怪作者方案导入接口未就绪"], true)
        return
    end

    local ok, err = TrashStore.ImportPluginPreset(selectedTrashPresetKey)
    if not ok then
        SetTrashPresetStatus(string.format("%s%s", L["导入作者小怪配置失败："], tostring(err or "")), true)
        return
    end

    SetTrashPresetStatus(L["作者小怪配置已导入（覆盖当前本地配置）"], false)
    local TrashPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TrashCDPage
    if TrashPage and TrashPage.RefreshSpellList then
        TrashPage:RefreshSpellList()
    end
    if TrashPage and TrashPage.RefreshSelectedSpell then
        TrashPage:RefreshSelectedSpell()
    end
end

local function HasAuthorInSlot(slotKey, authorKey)
    local items = BuildAuthorItems(slotKey)
    for i = 1, #items do
        local row = items[i]
        if type(row) == "table" and tostring(row[2] or "") == tostring(authorKey or "") then
            return true
        end
    end
    return false
end

local function ApplyRecommendedMplusAndTrash()
    local bossCfg = GetBossConfig()
    if not bossCfg then
        SetStatus(L["Boss 配置模块未加载"], false)
        return
    end

    local missingSlots = {}
    local mplusSlots = { "mplus_tank", "mplus_dps", "mplus_heal" }
    for _, slotKey in ipairs(mplusSlots) do
        if not HasAuthorInSlot(slotKey, NEW_MPLUS_AUTHOR_KEY) then
            missingSlots[#missingSlots + 1] = tostring(bossCfg:GetSlotLabel(slotKey))
        end
    end
    if #missingSlots > 0 then
        SetStatus(string.format(L["以下槽位缺少新版配置：%s"], table.concat(missingSlots, " / ")), false)
        return
    end

    if not (TrashStore and type(TrashStore.GetPluginPreset) == "function" and type(TrashStore.ImportPluginPreset) == "function") then
        SetTrashPresetStatus(L["小怪作者方案导入接口未就绪"], true)
        return
    end

    local preset = TrashStore.GetPluginPreset(NEW_TRASH_PRESET_KEY)
    if type(preset) ~= "table" or type(preset.trashConfig) ~= "table" then
        SetTrashPresetStatus(L["新版小怪作者方案不存在"], true)
        return
    end

    local changedSlots = {}
    for _, slotKey in ipairs(mplusSlots) do
        if tostring(bossCfg:GetSelectedAuthor(slotKey) or "") ~= NEW_MPLUS_AUTHOR_KEY then
            local ok, err = bossCfg:SetSelectedAuthor(slotKey, NEW_MPLUS_AUTHOR_KEY)
            if not ok then
                SetStatus(L["应用失败："] .. tostring(err), false)
                return
            end
            changedSlots[#changedSlots + 1] = tostring(bossCfg:GetSlotLabel(slotKey))
        end
    end

    local trashOk, trashErr = TrashStore.ImportPluginPreset(NEW_TRASH_PRESET_KEY)
    if not trashOk then
        SetTrashPresetStatus(string.format("%s%s", L["导入作者小怪配置失败："], tostring(trashErr or "")), true)
        return
    end

    selectedTrashPresetKey = NEW_TRASH_PRESET_KEY
    local db = GetPageDB()
    db.selectedTrashPresetKey = NEW_TRASH_PRESET_KEY

    if #changedSlots > 0 then
        SetStatus(string.format(L["大米方案已切换为新版配置：%s"], table.concat(changedSlots, " / ")), true)
    else
        SetStatus(L["大米方案已是新版配置"], true)
    end
    SetTrashPresetStatus(L["作者小怪配置已导入（覆盖当前本地配置）"], false)

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

    ShowReloadAfterAuthorSwitchConfirm(L["大米新版配置"])
end

local function ShowRecommendedMplusAndTrashConfirm()
    if not StaticPopupDialogs or not StaticPopup_Show then
        ApplyRecommendedMplusAndTrash()
        return
    end

    local dialogKey = "EXBOSS_APPLY_NEW_MPLUS_AND_TRASH_CONFIRM"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["确认切换大米方案到 [CN] 12.0 新版，并导入 EXWIND_CN 小怪作者方案？\n这会覆盖当前本地小怪配置。"],
            button1 = L["确定"],
            button2 = L["取消"],
            OnAccept = function()
                ApplyRecommendedMplusAndTrash()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show(dialogKey)
end

local function ShowTrashPresetImportConfirm()
    local row = GetSelectedTrashPresetRow()
    local presetName = row and tostring(row.authorName or row.title or row.pluginKey or "") or ""
    if not StaticPopupDialogs or not StaticPopup_Show then
        ApplySelectedTrashPreset()
        return
    end
    local dialogKey = "EXBOSS_TRASH_PRESET_IMPORT_CONFIRM"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = L["确认导入小怪作者方案：%s ？\n这会直接覆盖当前本地小怪配置。"],
            button1 = L["导入"],
            button2 = L["取消"],
            OnAccept = function()
                ApplySelectedTrashPreset()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(dialogKey, presetName ~= "" and presetName or L["当前方案"])
end

local function GetSelectedSettingsPresetValue()
    local db = GetPageDB()
    return tostring(db.selectedSettingsPresetKey or selectedSettingsPresetKey or "")
end

local function GetSelectedTrashPresetValue()
    local db = GetPageDB()
    return tostring(db.selectedTrashPresetKey or selectedTrashPresetKey or "")
end

FindItemText = function(items, value)
    local target = tostring(value or "")
    for i = 1, #(items or {}) do
        local row = items[i]
        if type(row) == "table" and tostring(row[2] or row[1] or "") == target then
            return tostring(row[1] or "")
        end
    end
    return L["请选择配置"]
end

local function SyncRuntimeToPageDB()
    local db = GetPageDB()
    pageSyncLock = true
    db.selectedVoicePack = tostring(EnsureDB().selectedVoicePack or ResolveDefaultVoicePack())

    local bossCfg = GetBossConfig()
    for _, row in ipairs(SLOT_ROWS) do
        local key = "slot_" .. tostring(row.slot)
        local current = bossCfg and bossCfg.GetSelectedAuthor and bossCfg:GetSelectedAuthor(row.slot) or ""
        db[key] = tostring(current or "")
    end

    selectedSettingsPresetKey = tostring(db.selectedSettingsPresetKey or selectedSettingsPresetKey or "")
    selectedTrashPresetKey = tostring(db.selectedTrashPresetKey or selectedTrashPresetKey or "")

    RefreshSettingsPresetControls()
    RefreshTrashPresetControls()

    db.selectedSettingsPresetKey = tostring(selectedSettingsPresetKey or "")
    db.selectedTrashPresetKey = tostring(selectedTrashPresetKey or "")
    pageSyncLock = false
end

local function BuildVoicePackInfoBody()
    local info = GetCurrentPackInfo()
    local lines = {
        string.format("|cff66d0ff%s|r", tostring(info.description or "")),
        "",
        string.format("|cffffd16d%s|r  %s", L["标签"], string.format(L["%d 标签"], tonumber(info.labelCount) or 0)),
        string.format("|cffffd16d%s|r  %s", L["作者"], tostring(info.author or L["—"])),
        string.format("|cffffd16d%s|r  %s", L["版本"], tostring(info.version or L["—"])),
        "",
        BuildMissingVoiceText(),
    }
    return table.concat(lines, "\n")
end

local function FindLayoutEntry(items, key)
    for i = 1, #(items or {}) do
        local item = items[i]
        if type(item) == "table" then
            if item.key == key then
                return item
            end
            if type(item.children) == "table" then
                local found = FindLayoutEntry(item.children, key)
                if found then
                    return found
                end
            end
        end
    end
    return nil
end

local function BuildLayout()
    local info = GetCurrentPackInfo()
    local configStatusText, configStatusOk = BuildDefaultConfigStatusText()
    if pageStatus.configText ~= "" then
        configStatusText = pageStatus.configText
        configStatusOk = pageStatus.configOk
    end

    local settingsStatusText = pageStatus.settingsText
    if settingsStatusText == "" and GetSelectedSettingsPresetValue() == "" then
        settingsStatusText = L["当前没有可用的综合设置方案，请先在作者插件的 Presets/SettingsPage.lua 粘贴“导出Lua”。"]
    end

    local trashStatusText = pageStatus.trashText
    if trashStatusText == "" and GetSelectedTrashPresetValue() == "" then
        trashStatusText = L["当前没有可用的小怪作者方案，请先在作者插件的 Presets/TrashConfig.lua 粘贴“导出Lua”。"]
    end

    return {
        { key = "header_main", type = "header", x = 1, y = 2, w = 52, h = 2, label = L["语音 / 配置"], labelSize = 24 },
        {
            key = "btn_toggle_grid_edit",
            type = "button",
            x = 88,
            y = 1,
            w = 11,
            h = 2,
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
        { key = "card_pack_picker", type = "card", x = 2, y = 6, w = 30, h = 20, title = L["语音包"], desc = L["选择当前生效的语音包。"], accentAlign = "left", accentColor = { r = THEME.accent[1], g = THEME.accent[2], b = THEME.accent[3], a = 1 } },
        { key = "selectedVoicePack", type = "dropdown", x = 3, y = 12, w = 25, h = 2, label = L["当前语音包"], items = BuildPackItemsForGrid(), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },

        { key = "card_pack_details", type = "card", x = 2, y = 29, w = 30, h = 20, title = tostring(info.displayName or ""), desc = tostring(info.subtitle or ""), accentAlign = "left", accentColor = { r = THEME.accent[1], g = THEME.accent[2], b = THEME.accent[3], a = 1 } },
        { key = "desc_pack_info", type = "description", x = 3, y = 33, w = 19, h = 19, label = BuildVoicePackInfoBody() },

        { key = "card_mplus_profiles", type = "card", x = 68, y = 6, w = 30, h = 22, title = L["大米方案"], desc = L["当前职责进入大米时自动使用。"], accentAlign = "left", accentColor = { r = THEME.cyan[1], g = THEME.cyan[2], b = THEME.cyan[3], a = 1 } },
        { key = "slot_mplus_tank", type = "dropdown", x = 69, y = 12, w = 28, h = 2, label = L["大米坦克"], items = BuildAuthorItems("mplus_tank"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "slot_mplus_dps", type = "dropdown", x = 69, y = 17, w = 28, h = 2, label = L["大米DPS"], items = BuildAuthorItems("mplus_dps"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "slot_mplus_heal", type = "dropdown", x = 69, y = 22, w = 28, h = 2, label = L["大米治疗"], items = BuildAuthorItems("mplus_heal"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "btn_apply_new_mplus_and_trash", type = "button", x = 69, y = 26, w = 28, h = 2, label = L["一键切换新版+导入小怪"], func = ShowRecommendedMplusAndTrashConfirm, frameLevelOffset = 8 },

        { key = "card_settings_preset", type = "card", x = 35, y = 6, w = 30, h = 20, title = L["综合设置方案"], desc = L["从作者插件导入整套综合设置；这是一次性覆盖。"], accentAlign = "left", accentColor = { r = THEME.ok[1], g = THEME.ok[2], b = THEME.ok[3], a = 1 } },
        { key = "selectedSettingsPresetKey", type = "dropdown", x = 36, y = 12, w = 28, h = 2, label = L["综合设置方案"], items = BuildSettingsPresetItems(), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "btn_import_settings", type = "button", x = 54, y = 15, w = 10, h = 2, label = L["导入"], func = ShowSettingsPresetImportConfirm, frameLevelOffset = 8 },
        { key = "desc_settings_status", type = "description", x = 36, y = 17, w = 28, h = 2, label = ApplyStatusColor(settingsStatusText, not pageStatus.settingsError, pageStatus.settingsError) },
        { key = "divider_6049", type = "divider", x = 36, y = 19, w = 28, h = 1, label = "" },
        { key = "selectedTrashPresetKey", type = "dropdown", x = 36, y = 20, w = 28, h = 2, label = L["小怪作者方案"], items = BuildTrashPresetItems(), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "btn_import_trash", type = "button", x = 54, y = 23, w = 10, h = 2, label = L["导入"], func = ShowTrashPresetImportConfirm, frameLevelOffset = 8 },
        { key = "desc_trash_status", type = "description", x = 36, y = 25, w = 28, h = 2, label = ApplyStatusColor(trashStatusText, not pageStatus.trashError, pageStatus.trashError) },

        { key = "card_summary", type = "card", x = 35, y = 29, w = 30, h = 20, title = L["当前摘要"], desc = L["当前职责会自动命中对应槽位。"], accentAlign = "left", accentColor = { r = THEME.cyan[1], g = THEME.cyan[2], b = THEME.cyan[3], a = 1 } },
        { key = "desc_config_status", type = "description", x = 36, y = 35, w = 28, h = 2, label = ApplyStatusColor(configStatusText, configStatusOk, configStatusOk == false) },
        { key = "desc_summary", type = "description", x = 36, y = 39, w = 28, h = 7, label = BuildSummaryText() },

        { key = "card_raid_profiles", type = "card", x = 68, y = 29, w = 30, h = 20, title = L["团本方案"], desc = L["当前职责进入团本时自动使用。"], accentAlign = "left", accentColor = { r = THEME.accent[1], g = THEME.accent[2], b = THEME.accent[3], a = 1 } },
        { key = "slot_raid_tank", type = "dropdown", x = 69, y = 35, w = 28, h = 2, label = L["团本坦克"], items = BuildAuthorItems("raid_tank"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "slot_raid_dps", type = "dropdown", x = 69, y = 40, w = 28, h = 2, label = L["团本DPS"], items = BuildAuthorItems("raid_dps"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
        { key = "slot_raid_heal", type = "dropdown", x = 69, y = 45, w = 28, h = 2, label = L["团本治疗"], items = BuildAuthorItems("raid_heal"), labelPos = "top", labelWrap = true, labelMaxLines = 2, search = true },
    }
end

local function UpdateLayoutData(layout)
    if type(layout) ~= "table" then
        return
    end

    local info = GetCurrentPackInfo()
    local configStatusText, configStatusOk = BuildDefaultConfigStatusText()
    if pageStatus.configText ~= "" then
        configStatusText = pageStatus.configText
        configStatusOk = pageStatus.configOk
    end

    local settingsStatusText = pageStatus.settingsText
    if settingsStatusText == "" and GetSelectedSettingsPresetValue() == "" then
        settingsStatusText = L["当前没有可用的综合设置方案，请先在作者插件的 Presets/SettingsPage.lua 粘贴“导出Lua”。"]
    end

    local trashStatusText = pageStatus.trashText
    if trashStatusText == "" and GetSelectedTrashPresetValue() == "" then
        trashStatusText = L["当前没有可用的小怪作者方案，请先在作者插件的 Presets/TrashConfig.lua 粘贴“导出Lua”。"]
    end

    local updates = {
        btn_toggle_grid_edit = { label = IsGridEditActive() and L["退出布局编辑"] or L["开启布局编辑"] },
        selectedVoicePack = { items = BuildPackItemsForGrid() },
        card_pack_details = { title = tostring(info.displayName or ""), desc = tostring(info.subtitle or "") },
        desc_pack_info = { label = BuildVoicePackInfoBody() },
        slot_raid_tank = { items = BuildAuthorItems("raid_tank") },
        slot_raid_dps = { items = BuildAuthorItems("raid_dps") },
        slot_raid_heal = { items = BuildAuthorItems("raid_heal") },
        slot_mplus_tank = { items = BuildAuthorItems("mplus_tank") },
        slot_mplus_dps = { items = BuildAuthorItems("mplus_dps") },
        slot_mplus_heal = { items = BuildAuthorItems("mplus_heal") },
        selectedSettingsPresetKey = { items = BuildSettingsPresetItems() },
        desc_settings_status = { label = ApplyStatusColor(settingsStatusText, not pageStatus.settingsError, pageStatus.settingsError) },
        selectedTrashPresetKey = { items = BuildTrashPresetItems() },
        desc_trash_status = { label = ApplyStatusColor(trashStatusText, not pageStatus.trashError, pageStatus.trashError) },
        desc_config_status = { label = ApplyStatusColor(configStatusText, configStatusOk, configStatusOk == false) },
        desc_summary = { label = BuildSummaryText() },
    }

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
    if not Grid then
        return
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
        root = scrollFrame
    end

    missingDepsText = nil
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
            width = 1160
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
end

RefreshPage = function(resetScroll)
    SyncRuntimeToPageDB()
    local contentFrame = Page._contentFrame
    if not contentFrame then
        return
    end
    local EXUI = _G.ExwindTools and _G.ExwindTools.UI
    local Grid = _G.ExwindGrid
    if not (ExwindTools and EXUI and EXUI.CreateDropdown and Grid) then
        if scrollFrame then
            scrollFrame:Hide()
        end
        if not missingDepsText then
            missingDepsText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            missingDepsText:SetPoint("TOPLEFT", 24, -24)
            missingDepsText:SetPoint("RIGHT", contentFrame, "RIGHT", -24, 0)
            missingDepsText:SetJustifyH("LEFT")
            missingDepsText:SetTextColor(1, 0.4, 0.4)
        end
        missingDepsText:SetText(L["语音/配置页面依赖 ExwindTools.UI 与 ExwindGrid，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"])
        missingDepsText:Show()
        return
    end
    if missingDepsText then
        missingDepsText:Hide()
    end
    RenderGrid(contentFrame, resetScroll == true)
end

local function HandleDatabaseChanged(info)
    if pageSyncLock then
        return
    end
    local db = GetPageDB()
    local key = tostring(info and info.key or "")
    if key == "" then
        return
    end

    if key == "selectedVoicePack" then
        local changed = SetPack(db.selectedVoicePack)
        if changed == false then
            SyncRuntimeToPageDB()
        end
    elseif key == "selectedSettingsPresetKey" then
        selectedSettingsPresetKey = tostring(db.selectedSettingsPresetKey or "")
    elseif key == "selectedTrashPresetKey" then
        selectedTrashPresetKey = tostring(db.selectedTrashPresetKey or "")
    elseif key:sub(1, 5) == "slot_" then
        local slotKey = key:sub(6)
        ApplySlotSelection(slotKey, db[key])
    end

    if type(RefreshPage) == "function" then
        RefreshPage(false)
    end
end

function Page:Render(contentFrame)
    Page._contentFrame = contentFrame
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
