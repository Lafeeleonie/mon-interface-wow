---@diagnostic disable: undefined-global, undefined-field

ExBoss.UI.Panel.TrashCDPage = ExBoss.UI.Panel.TrashCDPage or {}
local Page = ExBoss.UI.Panel.TrashCDPage

local ExwindTools = _G.ExwindTools
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local TrashStore = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local TrashData = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local TrashCore = ExBoss.TrashCD and ExBoss.TrashCD.Core or nil
local TrashCustomEvents = ExBoss.TrashCD and ExBoss.TrashCD.CustomEvents or nil

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

local SPELL_SETTINGS_MODULE_KEY = "ExBoss.TrashCD.SpellEditor"
local C = {
    SPELL_CARD = {
        cols = 1,
        gapX = 6,
        gapY = 6,
        height = 50,
        titleFontSizes = { 16, 14, 13, 11 },
    },
}

-- 在这里写入小怪面板左侧 被点名提示的图标法术ID
ExBoss.TargetAlert = ExBoss.TargetAlert or {}
ExBoss.TargetAlert.SupportedTrashSpellIDs = {
    [1262508] = true,
    [1262506] = true,
    [388942] = true,
    [1252622] = true,
    [1281657] = true,
    [1258820] = true,
    [1258475] = true,
    [1258174] = true,
    [1282050] = true,
    [1244907] = true,
    [1252062] = true,
    [1271623] = true,
    [1253446] = true,
}
local TEST_THREAT_ATLAS_SPELLS = ExBoss.TargetAlert.SupportedTrashSpellIDs
local TEST_THREAT_ATLAS_NAME = "Ping_Marker_Icon_Threat"
local TEST_THREAT_ATLAS_TOOLTIP = "可设置「被点名提示」!"
local EVENT_COLOR_ITEMS_FUNC = "func:ExBoss.Voice.ColorSchemes.BuildDropdownItems"
local LABEL_ITEMS_FUNC = "func:ExBoss.Voice.LabelCatalog.GetDropdownItems"
local TRIGGER_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}
local COUNTDOWN_LEAD_ITEMS = {
    { "1", "1" },
    { "2", "2" },
    { "3", "3" },
    { "4", "4" },
    { "5", "5" },
    { "6", "6" },
    { "7", "7" },
    { "8", "8" },
    { "9", "9" },
}
local TRIGGER_OFFSET_MODE_ITEMS = {
    { L["延迟"], "delay" },
    { L["提前"], "early" },
}
local SETTINGS_LAYOUT = {}
local CACHE = {
    challengeMapLookup = nil,
    spellTextCache = {},
    spellCachePending = {},
    spellRowsByMap = {},
}

local root
local mapPane
local spellPane
local detailPane
local settingsPane
local mapScrollFrame
local mapScrollChild
local spellScrollFrame
local spellScrollChild
local settingsScrollFrame
local settingsScrollChild
local detailIcon
local detailPlaceholder
local detailTitle
local detailMeta
local detailCast
local detailBody
local detailInfo
local detailDivider
local settingsVoiceDisabledNote

local activeDungeonButtons = {}
local dungeonButtonPool = {}
local activeSpellRows = {}
local spellRowPool = {}
local spellDividerPool = {}
local selectedMapID
local selectedNPCID
local selectedSpellID
local _suspendSpellSettingPersist = false
local GetSpellRows
local GetRowSpellDescription
local GetSelectedSpellRow
local _asyncHandler
local _spellListBuildToken = 0
local _selectionRefreshToken = 0

local function RegisterSpellSettingsGridAsActive(moduleKey)
    if not (Page._visible and settingsScrollChild and ExwindTools and ExwindTools.UI) then
        return
    end
    ExwindTools.UI.ActivePageFrame = settingsScrollChild
    if type(moduleKey) == "string" and moduleKey ~= "" then
        ExwindTools.UI.CurrentModule = moduleKey
    end
end

local function ClearSpellSettingsGridActiveRegistration()
    if not (ExwindTools and ExwindTools.UI and settingsScrollChild) then
        return
    end
    if ExwindTools.UI.ActivePageFrame == settingsScrollChild then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
end

local MAP_COLS = 4
local MAP_CELL_W = 76
local MAP_CELL_H = 78
local MAP_CELL_GAP_X = 8
local MAP_CELL_GAP_Y = 10
local SPELL_ROW_H = 32
local SPELL_CACHE_PRIME_LIMIT = 12
local MDT_ENEMY_NAME_BY_NPCID = {
    [75964] = "Ranjit",
    [75976] = "Outcast Servant",
    [76087] = "Solar Construct",
    [76132] = "Soaring Chakram Master",
    [76141] = "Araknath",
    [76142] = "Skyreach Sun Construct Prototype",
    [76143] = "Rukhran",
    [76149] = "Dread Raven",
    [76154] = "Sun Talon Tamer",
    [76205] = "Blooded Bladefeather",
    [76227] = "Sunwings",
    [76266] = "High Sage Viryx",
    [76285] = "Arakkoa Magnifying Glass",
    [78932] = "Driving Gale-Caller",
    [78933] = "Herald of Sunrise",
    [79093] = "Skyreach Sun Talon",
    [79303] = "Adorned Bladetalon",
    [79462] = "Blinding Sun Priestess",
    [79466] = "Initiate of the Rising Sun",
    [79467] = "Adept of the Dawn",
    [122056] = "Viceroy Nezhar",
    [122313] = "Zuraal the Ascended",
    [122316] = "Saprish",
    [122319] = "Darkfang",
    [122322] = "Famished Broken",
    [122403] = "Shadowguard Champion",
    [122404] = "Dire Voidbender",
    [122405] = "Dark Conjurer",
    [122412] = "Bound Voidcaller",
    [122413] = "Ruthless Riftstalker",
    [122421] = "Umbral War-Adept",
    [122423] = "Grand Shadow-Weaver",
    [122571] = "Rift Warden",
    [122716] = "Coalesced Void",
    [122827] = "Umbral Tentacle",
    [124171] = "Merciless Subjugator",
    [124729] = "L'ura",
    [125340] = "Shadewing",
    [190609] = "Echo of Doragosa",
    [191736] = "Crawth",
    [192329] = "Territorial Eagle",
    [192333] = "Alpha Eagle",
    [192680] = "Guardian Sentry",
    [194181] = "Vexamus",
    [196044] = "Unruly Textbook",
    [196045] = "Corrupted Manafiend",
    [196200] = "Algeth'ar Echoknight",
    [196202] = "Spectral Invoker",
    [196482] = "Overgrown Ancient",
    [196577] = "Spellbound Battleaxe",
    [196671] = "Arcane Ravager",
    [196694] = "Arcane Forager",
    [197219] = "Vile Lasher",
    [197398] = "Hungry Lasher",
    [197406] = "Aggravated Skitterfly",
    [231606] = "Emberdawn",
    [231626] = "Kalis",
    [231629] = "Latch",
    [231631] = "Commander Kroluk",
    [231636] = "Restless Heart",
    [231861] = "Arcanotron Custos",
    [231863] = "Seranel Sunlash",
    [231864] = "Gemellus",
    [231865] = "Degentrius",
    [232056] = "Territorial Dragonhawk",
    [232063] = "Apex Lynx",
    [232067] = "Creeping Spindleweb",
    [232070] = "Restless Steward",
    [232071] = "Dutiful Groundskeeper",
    [232106] = "Brightscale Wyrm",
    [232113] = "Spellguard Magus",
    [232116] = "Windrunner Soldier",
    [232118] = "Flaming Updraft",
    [232119] = "Swiftshot Archer",
    [232121] = "Phalanx Breaker",
    [232122] = "Phalanx Breaker",
    [232146] = "Phantasmal Mystic",
    [232147] = "Lingering Marauder",
    [232148] = "Spectral Axethrower",
    [232171] = "Ardent Cutthroat",
    [232173] = "Fervent Apothecary",
    [232175] = "Devoted Woebringer",
    [232176] = "Flesh Behemoth",
    [232232] = "Zealous Reaver",
    [232283] = "Loyal Worg",
    [232369] = "Arcane Magister",
    [234062] = "Arcane Sentry",
    [234064] = "Dreaded Voidwalker",
    [234065] = "Hollowsoul Shredder",
    [234066] = "Devouring Tyrant",
    [234067] = "Vigilant Librarian",
    [234068] = "Shadowrift Voidcaller",
    [234069] = "Voidling",
    [234089] = "Animated Codex",
    [234124] = "Sunblade Enforcer",
    [234486] = "Lightward Healer",
    [234673] = "Spindleweb Hatchling",
    [236894] = "Bloated Lasher",
    [238049] = "Scouting Trapper",
    [238099] = "Pesty Lashling",
    [239636] = "Gemellus",
    [240973] = "Runed Spellbreaker",
    [241354] = "Void-Infused Brightscale",
    [241397] = "Celestial Drifter",
    [241539] = "Kasreth",
    [241542] = "Corewarden Nysarra",
    [241546] = "Lothraxion",
    [241642] = "Lingering Image",
    [241643] = "Shadowguard Defender",
    [241644] = "Corewright Arcanist",
    [241645] = "Hollowsoul Scrounger",
    [241647] = "Flux Engineer",
    [241660] = "Duskfright Herald",
    [242964] = "Keen Headhunter",
    [247570] = "Muro'jin",
    [247572] = "Nekraxx",
    [248373] = "Circuit Seer",
    [248501] = "Reformed Voidling",
    [248502] = "Null Sentinel",
    [248506] = "Dreadflail",
    [248595] = "Vordaza",
    [248605] = "Rak'tul",
    [248678] = "Hulking Juggernaut",
    [248684] = "Frenzied Berserker",
    [248685] = "Ritual Hexxer",
    [248686] = "Dread Souleater",
    [248690] = "Grim Skirmisher",
    [248692] = "Reanimated Warrior",
    [248693] = "Mire Laborer",
    [248706] = "Cursed Voidcaller",
    [248708] = "Nexus Adept",
    [248769] = "Smudge",
    [249002] = "Warding Mask",
    [249020] = "Hexbound Eagle",
    [249022] = "Bramblemaw Bear",
    [249024] = "Hollow Soulrender",
    [249025] = "Bound Defender",
    [249030] = "Restless Gnarldin",
    [249036] = "Tormented Shade",
    [249086] = "Void Infuser",
    [249711] = "Core Technician",
    [250299] = "[DNT] Conduit Stalker",
    [250443] = "Unstable Phantom",
    [250883] = "Scouting Trapper",
    [250992] = "Raging Squall",
    [251024] = "Null Guardian",
    [251031] = "Wretched Supplicant",
    [251047] = "Soulbind Totem",
    [251568] = "Fractured Image",
    [251852] = "Nullifier",
    [251853] = "Grand Nullifier",
    [251861] = "Blazing Pyromancer",
    [251878] = "Voidcaller",
    [251880] = "Solar Orb",
    [252551] = "Deathwhisper Necrolyte",
    [252555] = "Lumbering Plaguehorror",
    [252558] = "Rotting Ghoul",
    [252559] = "Leaping Geist",
    [252561] = "Quarry Tormentor",
    [252563] = "Dreadpulse Lich",
    [252564] = "Glacieth",
    [252565] = "Wrathbone Enforcer",
    [252566] = "Rimebone Coldwraith",
    [252567] = "Gloombound Shadebringer",
    [252602] = "Risen Soldier",
    [252603] = "Arcanist Cadaver",
    [252606] = "Plungetalon Gargoyle",
    [252610] = "Ymirjar Graveblade",
    [252621] = "Krick",
    [252625] = "Ick",
    [252635] = "Forgemaster Garfrost",
    [252648] = "Scourgelord Tyrannus",
    [252653] = "Rimefang",
    [252756] = "Void-Infused Destroyer",
    [252825] = "Mana Battery",
    [252852] = "Corespark Conduit",
    [253302] = "Hex Guardian",
    [253458] = "Zil'jan",
    [253473] = "Gloomwing Bat",
    [253683] = "Rokh'zal",
    [253701] = "Death's Grasp",
    [254227] = "Corewarden Nysarra",
    [254233] = "Rokh'zal",
    [254459] = "Broken Pipe",
    [254485] = "Corespark Pylon",
    [254684] = "Rotling",
    [254691] = "Scourge Plaguespreader",
    [254740] = "Umbral Shadowbinder",
    [254926] = "Lightwrought",
    [254928] = "Flarebat",
    [254932] = "Radiant Swarm",
    [255037] = "Shade of Krick",
    [255179] = "Fractured Image",
    [255320] = "Ravenous Umbralfin",
    [255376] = "Unstable Voidling",
    [255551] = "Depravation Wave Stalker",
    [256424] = "Void Tentacle",
    [257190] = "Iceborn Proto-Drake",
    [257447] = "Hollowsoul Shredder",
    [258868] = "Haunting Grunt",
    [259387] = "Spellwoven Familiar",
    [259569] = "Mana Battery",
}
local DUNGEON_DISPLAY_NAME_BY_MAPID = {
    [1753] = { zhCN = "执政团之座", enUS = "SEAT" },
    [658] = { zhCN = "萨隆矿坑", enUS = "POS" },
    [1209] = { zhCN = "通天峰", enUS = "SR" },
    [2526] = { zhCN = "艾杰斯亚学院", enUS = "AA" },
    [2805] = { zhCN = "风行者之塔", enUS = "WS" },
    [2811] = { zhCN = "魔导师平台", enUS = "MT" },
    [2874] = { zhCN = "迈萨拉洞窟", enUS = "MC" },
    [2915] = { zhCN = "节点希纳斯", enUS = "NPX" },
}

local function GetEffectiveDisplayLocale()
    if ExBoss and ExBoss.GetEffectiveLocale then
        local mode = ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or "AUTO"
        return tostring(ExBoss:GetEffectiveLocale(mode) or "zhCN")
    end
    return "zhCN"
end

local function GetAsyncHandler()
    if _asyncHandler and _asyncHandler ~= false then
        return _asyncHandler
    end
    local lib = LibStub and LibStub("LibAsync", true)
    if not lib then
        _asyncHandler = nil
        return nil
    end
    _asyncHandler = lib:GetHandler({
        type = "everyFrame",
        maxTime = 6,
        maxTimeCombat = 4,
        errorHandler = geterrorhandler(),
    })
    return _asyncHandler
end

local function CreateSectionBackdrop(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, 0.90)
    frame:SetBackdropBorderColor(0.22, 0.22, 0.25, 0.95)
    return frame
end

local function Clamp01(v, fallback)
    local n = tonumber(v)
    if not n then return fallback or 0 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function NormalizeTriggerSource(value)
    local source = tostring(value or "pack")
    if source ~= "pack" and source ~= "lsm" and source ~= "file" then
        source = "pack"
    end
    return source
end

local function NormalizeMapNameKey(name)
    local s = tostring(name or ""):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

local function GetDisplayDungeonName(mapID, fallbackName)
    local id = tonumber(mapID)
    local locale = GetEffectiveDisplayLocale()
    if locale == "enGB" then locale = "enUS" end

    -- 优先从 EXDB 取对应语言，找不到 fallback enUS
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if id and EXDB and EXDB.InstanceNoteByMapID then
        local meta = EXDB.InstanceNoteByMapID[id]
        if meta then
            local v = meta[locale]
            if v and v ~= "" then return v end
            local en = meta["enUS"] or meta.nameEN
            if en and en ~= "" then return en end
        end
    end

    -- 兜底：静态表
    if id and DUNGEON_DISPLAY_NAME_BY_MAPID[id] then
        local row = DUNGEON_DISPLAY_NAME_BY_MAPID[id]
        if locale == "enUS" and row.enUS then return row.enUS end
        if row.zhCN then return row.zhCN end
    end

    return tostring(fallbackName or "")
end

local function GetShortDisplayDungeonName(mapID, fallbackName)
    local id = tonumber(mapID)
    local locale = GetEffectiveDisplayLocale()
    if locale == "enGB" then locale = "enUS" end
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if id and EXDB and EXDB.InstanceNoteByMapID then
        local meta = EXDB.InstanceNoteByMapID[id]
        if meta then
            if locale == "enUS" then
                local shortEN = tostring(meta.enUSShort or "")
                if shortEN ~= "" then
                    return shortEN
                end
            else
                local shortCN = tostring(meta.zhCNShort or "")
                if shortCN ~= "" then
                    return shortCN
                end
            end
        end
    end

    local mapName = tostring(GetDisplayDungeonName(id, fallbackName) or "")
    local nameLen = (type(strlenutf8) == "function" and strlenutf8(mapName)) or #mapName
    if nameLen > 5 then
        if type(UTF8Left) == "function" then
            mapName = UTF8Left(mapName, 5)
        else
            mapName = string.sub(mapName, 1, 5)
        end
    end
    return mapName
end

local function GetDisplayMobName(npcID, fallbackName)
    local locale = GetEffectiveDisplayLocale()
    local id = tonumber(npcID) or 0
    -- 优先查多语言名称表
    local localeTable = _G.EXBOSS_TRASH_CD_LOCALE
    if localeTable and id > 0 then
        local row = localeTable[id]
        if row then
            local v = row[locale]
            if type(v) == "string" and v ~= "" then return v end
            local en = row["enUS"]
            if type(en) == "string" and en ~= "" then return en end
        end
    end
    -- fallback: MDT 英文名
    if locale == "enUS" then
        local name = MDT_ENEMY_NAME_BY_NPCID[id]
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(fallbackName or ("NPC " .. tostring(npcID or "")))
end

local function SetWidgetUsable(widget, usable)
    if not widget then
        return
    end
    usable = usable ~= false
    widget:SetAlpha(usable and 1 or 0.45)
    if widget.checkbox and widget.checkbox.Enable then
        if usable then
            widget.checkbox:Enable()
        else
            widget.checkbox:Disable()
        end
    end
    if widget.editBox and widget.editBox.Enable then
        if usable then
            widget.editBox:Enable()
        else
            widget.editBox:Disable()
        end
    end
    if widget.button and widget.button.Enable then
        if usable then
            widget.button:Enable()
        else
            widget.button:Disable()
        end
    end
    if widget.Enable then
        if usable then
            widget:Enable()
        else
            widget:Disable()
        end
    elseif widget.EnableMouse then
        widget:EnableMouse(usable)
    end
end

local function GetMapIcon(mapID)
    local id = tonumber(mapID)
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    local mapRow = rootData and rootData[id] or nil
    local mapName = tostring(mapRow and (mapRow.mapName or mapRow.name) or "")
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil

    if id and EXDB and type(EXDB.InstanceIconByMapID) == "table" then
        local icon = EXDB.InstanceIconByMapID[id]
        if icon then
            return icon
        end
    end
    if mapRow and mapRow.icon then
        return mapRow.icon
    end

    if CACHE.challengeMapLookup == nil then
        local lookup = {}
        if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" and type(C_ChallengeMode.GetMapUIInfo) == "function" then
            local ok, idList = pcall(C_ChallengeMode.GetMapTable)
            if ok and type(idList) == "table" then
                for _, cmID in ipairs(idList) do
                    local okInfo, name, _, _, icon = pcall(C_ChallengeMode.GetMapUIInfo, cmID)
                    if okInfo and type(name) == "string" and name ~= "" and icon then
                        local key = NormalizeMapNameKey(name)
                        if key ~= "" and not lookup[key] then
                            lookup[key] = { id = tonumber(cmID), icon = icon }
                        end
                    end
                end
            end
        end
        CACHE.challengeMapLookup = lookup
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and id and id > 0 then
        local _, _, _, icon = C_ChallengeMode.GetMapUIInfo(id)
        if icon then
            return icon
        end
    end

    if mapName ~= "" then
        local hit = CACHE.challengeMapLookup and CACHE.challengeMapLookup[NormalizeMapNameKey(mapName)] or nil
        if hit and hit.icon then
            return hit.icon
        end
    end
    return "Interface\\LFGFrame\\LFGIcon-Dungeon"
end

local function IsSpellDataReady(spellID)
    if not spellID then
        return true
    end
    if C_Spell and C_Spell.IsSpellDataCached then
        local ok, cached = pcall(C_Spell.IsSpellDataCached, spellID)
        if ok then
            return cached and true or false
        end
    end
    return true
end

local function RequestSpellDataLoad(spellID)
    if not spellID or not (C_Spell and C_Spell.RequestLoadSpellData) then
        return
    end
    if CACHE.spellCachePending[spellID] then
        return
    end
    CACHE.spellCachePending[spellID] = true
    pcall(C_Spell.RequestLoadSpellData, spellID)
end

local function PrimeSpellCache(rows)
    local primed = 0
    for _, row in ipairs(rows or {}) do
        if primed >= SPELL_CACHE_PRIME_LIMIT then
            break
        end
        if not (row and row.isCustomEvent == true) then
            local spellID = tonumber(row and row.spellID)
            if spellID and not IsSpellDataReady(spellID) then
                RequestSpellDataLoad(spellID)
                primed = primed + 1
            end
        end
    end
end

local function GetAuthorVoiceDisableText(cfg)
    if type(cfg) ~= "table" or cfg.authorVoiceDisabled ~= true then
        return nil
    end
    local key = tostring(cfg.authorVoiceDisableReasonKey or "")
    if key ~= "" then
        return tostring(L[key] or key)
    end
    local reason = tostring(cfg.authorVoiceDisableReason or "")
    if reason ~= "" then
        return reason
    end
    return L["该技能语音已被作者临时禁用"]
end

local function CurrentTrashHasSpellID(spellID)
    local sid = tonumber(spellID)
    if not sid then
        return false
    end
    if tonumber(selectedSpellID) == sid then
        return true
    end
    local rows = GetSpellRows(selectedMapID)
    for i = 1, #rows do
        if tonumber(rows[i].spellID) == sid then
            return true
        end
    end
    return false
end

local function NormalizeSpellDescText(text)
    local s = tostring(text or "")
    if s == "" then
        return ""
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("\r\n", "\n")
    return s
end

local function WrapColorText(text, color)
    local body = tostring(text or "")
    if body == "" or type(color) ~= "table" then
        return body
    end
    local r = math.floor((tonumber(color.r) or 1) * 255 + 0.5)
    local g = math.floor((tonumber(color.g) or 1) * 255 + 0.5)
    local b = math.floor((tonumber(color.b) or 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, body)
end

local function GetSpellNameAndIcon(spellID)
    if not spellID then
        return nil, 134400
    end
    local cached = CACHE.spellTextCache[spellID]
    if type(cached) == "table" and cached.name ~= nil and cached.icon ~= nil then
        return cached.name, cached.icon
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            local name = info.name
            local icon = info.iconID or 134400
            CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
            CACHE.spellTextCache[spellID].name = name
            CACHE.spellTextCache[spellID].icon = icon
            return name, icon
        end
    end
    return nil, 134400
end

local function GetRowSpellNameAndIcon(row)
    if type(row) == "table" and row.isCustomEvent == true then
        local name = tostring(row.spellName or "")
        local icon = tonumber(row.iconFileID) or 134400
        if name ~= "" then
            return name, icon
        end
        return nil, icon
    end
    return GetSpellNameAndIcon(type(row) == "table" and row.spellID or nil)
end

local function GetSpellIcon(spellID)
    local _, icon = GetSpellNameAndIcon(spellID)
    return icon or 134400
end

local function GetRowSpellIcon(row)
    local _, icon = GetRowSpellNameAndIcon(row)
    return icon or 134400
end

local function GetSpellDescription(spellID)
    if not spellID then
        return L["暂无描述。"]
    end
    local cached = CACHE.spellTextCache[spellID]
    if type(cached) == "table" and type(cached.desc) == "string" and cached.desc ~= "" then
        return cached.desc
    end
    if not IsSpellDataReady(spellID) then
        RequestSpellDataLoad(spellID)
    end

    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok, tip = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok and tip and tip.lines then
            local lines = {}
            for i, line in ipairs(tip.lines) do
                local text = line and line.leftText
                if i > 1 and text and text ~= "" then
                    text = NormalizeSpellDescText(text)
                    if text ~= "" then
                        lines[#lines + 1] = WrapColorText(text, line.leftColor)
                    end
                end
            end
            if #lines > 0 then
                local desc = (#lines >= 2) and ("\n" .. lines[1] .. "\n\n" .. table.concat(lines, "\n", 2)) or
                    ("\n" .. table.concat(lines, "\n"))
                CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
                CACHE.spellTextCache[spellID].desc = desc
                return desc
            end
        end
    end
    if TrashData and TrashData.GetSpellDescriptionSafe then
        local desc = TrashData.GetSpellDescriptionSafe(spellID)
        if type(desc) == "string" and desc ~= "" then
            desc = NormalizeSpellDescText(desc)
            CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
            CACHE.spellTextCache[spellID].desc = desc
            return desc
        end
    end
    CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
    CACHE.spellTextCache[spellID].desc = L["暂无描述。"]
    return L["暂无描述。"]
end

local function SplitSpellDescription(descText)
    local lines = {}
    for raw in tostring(descText or ""):gmatch("[^\n]+") do
        local line = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    local castLine = lines[1] or ""
    if #lines <= 1 then
        return castLine, ""
    end
    return castLine, table.concat(lines, "\n\n", 2)
end

local function RefreshDetailCardLayout()
    if not (detailPane and detailTitle and detailMeta and detailCast and detailBody and detailDivider) then
        return
    end
    local headerW = detailPane:GetWidth() or 0
    if headerW <= 0 then
        headerW = 980
    end

    local metaWidth = math.min(300, math.floor(headerW * 0.28))
    local titleNatural = math.ceil(detailTitle:GetUnboundedStringWidth() or 0) + 8
    local titleWidth = math.min(
        math.max(220, headerW - 44 - 14 - 12 - 12 - metaWidth - 18),
        math.max(120, titleNatural)
    )
    local bodyWidth = math.max(320, headerW - 44 - 14 - 12 - 18)

    detailTitle:SetWidth(titleWidth)
    detailMeta:ClearAllPoints()
    detailMeta:SetPoint("LEFT", detailTitle, "RIGHT", 6, 0)
    detailMeta:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailCast:SetWidth(bodyWidth)
    detailBody:SetWidth(bodyWidth)
    detailInfo:SetWidth(bodyWidth)

    local castH = detailCast:GetStringHeight() or 0
    local bodyH = detailBody:GetStringHeight() or 0
    local infoH = detailInfo:GetStringHeight() or 0
    local desiredHeight = math.max(118, math.ceil(64 + castH + 6 + bodyH + 8 + infoH + 18))
    detailPane:SetHeight(desiredHeight)
end

local function SetDetailCardEmpty(message)
    if not detailPane then
        return
    end
    if detailPlaceholder then
        detailPlaceholder:SetText(tostring(message or L["点击左侧法术后，可在此查看法术描述。"]))
        detailPlaceholder:Show()
    end
    if detailIcon then detailIcon:Hide() end
    if detailTitle then detailTitle:SetText("") end
    if detailMeta then detailMeta:SetText("") end
    if detailCast then detailCast:SetText("") end
    if detailBody then detailBody:SetText("") end
    if detailInfo then detailInfo:SetText("") end
    if detailDivider then detailDivider:Hide() end
    detailPane:SetHeight(98)
end

local function GetDungeonRows()
    local out = {}
    local seen = {}
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    for key, row in pairs(rootData) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = GetDisplayDungeonName(mapID, row.mapName or row.name)
            if mapID and mapName ~= "" then
                local mobCount = 0
                if type(row.mobs) == "table" then
                    for _ in pairs(row.mobs) do
                        mobCount = mobCount + 1
                    end
                end
                out[#out + 1] = {
                    mapID = mapID,
                    mapName = mapName,
                    mobCount = mobCount,
                }
                seen[mapID] = true
            end
        end
    end
    if TrashCustomEvents and type(TrashCustomEvents.GetRegisteredMaps) == "function" then
        for _, row in ipairs(TrashCustomEvents.GetRegisteredMaps()) do
            local mapID = tonumber(row and row.mapID)
            if mapID and not seen[mapID] then
                out[#out + 1] = {
                    mapID = mapID,
                    mapName = GetDisplayDungeonName(mapID, row and row.mapName),
                    mobCount = 0,
                }
                seen[mapID] = true
            end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.mapName) < tostring(b.mapName)
    end)
    return out
end

local function ResolveDefaultMapID()
    local _, mapName = nil, nil
    if TrashData and TrashData.GetCurrentInstanceContext then
        _, mapName = TrashData.GetCurrentInstanceContext()
    end
    if mapName and TrashData and TrashData.GetTrashMapIDByNameKey and TrashData.NormalizeNameKey then
        local lookup = TrashData.GetTrashMapIDByNameKey()
        local mapID = lookup and lookup[TrashData.NormalizeNameKey(mapName)]
        if tonumber(mapID) then
            return tonumber(mapID)
        end
    end
    local rows = GetDungeonRows()
    return rows[1] and rows[1].mapID or nil
end

GetSpellRows = function(mapID)
    local mid = tonumber(mapID)
    if not mid then
        return {}
    end
    local cached = CACHE.spellRowsByMap[mid]
    if type(cached) == "table" then
        return cached
    end
    local out = {}
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    local mapRow = rootData and rootData[mid] or nil
    local mobs = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs or nil
    if type(mobs) == "table" then
        for npcID, mob in pairs(mobs) do
            if type(mob) == "table" and type(mob.spells) == "table" then
                for spellID, spellData in pairs(mob.spells) do
                    if type(spellData) == "table" then
                        local spellName = nil
                        local apiSpellName = select(1, GetSpellNameAndIcon(tonumber(spellID)))
                        if type(apiSpellName) == "string" and apiSpellName ~= "" then
                            spellName = apiSpellName
                        else
                            spellName = tostring(spellData.name or
                                (TrashData and TrashData.GetSpellNameSafe and TrashData.GetSpellNameSafe(spellID)) or
                                spellID)
                        end
                        out[#out + 1] = {
                            mapID = mid,
                            npcID = tonumber(npcID),
                            mobName = GetDisplayMobName(npcID, mob.name),
                            spellID = tonumber(spellID),
                            spellName = spellName,
                            first = tonumber(spellData.first),
                            castTime = tonumber(spellData.castTime),
                            cd = type(spellData.cd) == "table" and spellData.cd or nil,
                        }
                    end
                end
            end
        end
    end
    if TrashCustomEvents and type(TrashCustomEvents.GetRowsForMap) == "function" then
        local customRows = TrashCustomEvents.GetRowsForMap(mid)
        for i = 1, #customRows do
            out[#out + 1] = customRows[i]
        end
    end
    table.sort(out, function(a, b)
        if a.mobName ~= b.mobName then
            return a.mobName < b.mobName
        end
        if (a.isCustomEvent == true) ~= (b.isCustomEvent == true) then
            return a.isCustomEvent == true
        end
        if a.spellName ~= b.spellName then
            return a.spellName < b.spellName
        end
        return (a.spellID or 0) < (b.spellID or 0)
    end)
    CACHE.spellRowsByMap[mid] = out
    return out
end

GetSelectedSpellRow = function()
    if not selectedMapID or not selectedNPCID or not selectedSpellID then
        return nil
    end
    local rows = GetSpellRows(selectedMapID)
    for i = 1, #rows do
        local row = rows[i]
        if row.npcID == selectedNPCID and row.spellID == selectedSpellID then
            return row
        end
    end
    return nil
end

local function GetResolvedSpellEntry(row, createIfMissing)
    if not row or not TrashStore or not TrashStore.GetResolvedSpellEntry then
        return TrashStore and TrashStore.GetSpellEntryDefaults and TrashStore.GetSpellEntryDefaults() or {}
    end
    return TrashStore.GetResolvedSpellEntry(row.mapID, row.npcID, row.spellID, createIfMissing)
end

local function GetColorSchemeModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function NormalizeEventColorMode(mode)
    local CS = GetColorSchemeModule()
    if CS and CS.NormalizeSchemeKey and CS.GetCustomKey then
        local n = CS.NormalizeSchemeKey(mode)
        if n then
            return n
        end
        return CS.GetCustomKey()
    end
    local s = tostring(mode or "")
    if s == "tank" or s == "heal" or s == "cooldown" or s == "mechanic" then
        return s
    end
    return "__custom"
end

local function NormalizeCountdownLeadSeconds(v)
    local n = tonumber(v)
    if not n then
        n = 5
    end
    n = math.floor(n + 0.0001)
    if n < 1 then n = 1 end
    if n > 9 then n = 9 end
    return n
end

local function GetSpellEditorDefaults()
    local defaults = TrashStore and TrashStore.GetSpellEntryDefaults and TrashStore.GetSpellEntryDefaults() or {}
    return {
        enabled = defaults.enabled == true,
        tankEnabled = defaults.tankEnabled == true,
        healerEnabled = defaults.healerEnabled == true,
        dpsEnabled = defaults.dpsEnabled == true,
        showBunBar = defaults.showBunBar ~= false,
        showTimerBar = defaults.showTimerBar ~= false,
        showNameplate = defaults.showNameplate == true,
        eventColorEnabled = defaults.eventColorEnabled == true,
        eventColorMode = tostring(defaults.eventColorMode or "none"),
        eventColor = type(defaults.eventColor) == "table" and {
            r = tonumber(defaults.eventColor.r) or 1,
            g = tonumber(defaults.eventColor.g) or 1,
            b = tonumber(defaults.eventColor.b) or 1,
            a = tonumber(defaults.eventColor.a) or 1,
        } or { r = 1, g = 1, b = 1, a = 1 },
        centralEnabled = defaults.centralEnabled == true,
        centralLead = tonumber(defaults.centralLead) or 0,
        centralText = tostring(defaults.centralText or ""),
        countdownEnabled = defaults.countdownEnabled == true,
        countdownLead = tostring(NormalizeCountdownLeadSeconds(defaults.countdownLead)),
        preAlertEnabled = defaults.preAlertEnabled == true,
        preAlertText = tostring(defaults.countdownText or ""),
        timerBarRenameEnabled = defaults.timerBarRenameEnabled == true,
        timerBarRenameText = tostring(defaults.timerBarName or ""),
        ringEnabled = defaults.ringEnabled == true,
        ringRenameEnabled = defaults.ringRenameEnabled == true,
        ringRenameText = tostring(defaults.ringRenameText or ""),
        castProgressBarEnabled = defaults.castProgressBarEnabled == true,
        castProgressBarRenameEnabled = defaults.castProgressBarRenameEnabled == true,
        castProgressBarRenameText = tostring(defaults.castProgressBarRenameText or ""),
        ringCastCheckEnabled = defaults.ringCastCheckEnabled == true,
        targetAlertStartEnabled = defaults.targetAlertStartEnabled == true,
        targetAlertStartLSM = tostring(defaults.targetAlertStartLSM or ""),
        targetAlertTankEnabled = defaults.targetAlertTankEnabled == true,
        targetAlertRingEnabled = defaults.targetAlertRingEnabled == true,
        targetAlertIconEnabled = defaults.targetAlertIconEnabled == true,
        targetAlertTextEnabledV2 = defaults.targetAlertTextEnabledV2 == true,
        targetAlertStealthEnabledV2 = defaults.targetAlertStealthEnabledV2 == true,
        tr1Enabled = defaults.voice1Enabled == true,
        tr1Source = tostring(defaults.voice1Source or "pack"),
        tr1Label = tostring(defaults.voice1Label or ""),
        tr1LSM = tostring(defaults.voice1LSM or ""),
        tr1Path = tostring(defaults.voice1Path or ""),
        tr1OffsetMode = tostring(defaults.voice1OffsetMode or "delay"),
        tr1OffsetSeconds = tonumber(defaults.voice1OffsetSeconds) or 0,
        tr2Enabled = defaults.countdownVoiceEnabled == true,
        tr2CountdownLead = tostring(NormalizeCountdownLeadSeconds(defaults.countdownLead)),
        tr2PlayTextEnabled = defaults.countdownPlayName == true,
        tr2Source = tostring(defaults.voice2Source or "pack"),
        tr2Label = tostring(defaults.voice2Label or ""),
        tr2LSM = tostring(defaults.voice2LSM or ""),
        tr2Path = tostring(defaults.voice2Path or ""),
        tr2OffsetMode = tostring(defaults.voice2OffsetMode or "delay"),
        tr2OffsetSeconds = tonumber(defaults.voice2OffsetSeconds) or 0,
    }
end

local function GetSpellEditorDB()
    if not ExwindTools or not ExwindTools.GetModuleDB then
        return nil
    end
    return ExwindTools:GetModuleDB(SPELL_SETTINGS_MODULE_KEY, GetSpellEditorDefaults())
end

local function CopyTable(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for key, value in pairs(src) do
        dst[key] = value
    end
    return dst
end

local function FormatCDList(cdList)
    if type(cdList) ~= "table" or #cdList == 0 then
        return "-"
    end
    local out = {}
    for i = 1, #cdList do
        out[#out + 1] = tostring(cdList[i])
    end
    return table.concat(out, ", ")
end

local function PlayVoicePreview(sourceType, label, customLSM, customPath)
    local source = NormalizeTriggerSource(sourceType)
    if source == "pack" then
        local safeLabel = tostring(label or "")
        if safeLabel == "" then
            return
        end
        local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
        if Engine and Engine.TryPlayLabel then
            Engine:TryPlayLabel(safeLabel, { source = "trash_cd_preview" })
        end
        return
    end

    local soundPath = nil
    if source == "lsm" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM and customLSM and customLSM ~= "" then
            soundPath = LSM:Fetch("sound", customLSM, true)
        end
    elseif source == "file" then
        soundPath = tostring(customPath or "")
    end
    if soundPath and soundPath ~= "" and PlaySoundFile then
        pcall(PlaySoundFile, soundPath, "Master")
    end
end

local function BuildSettingsLayout()
    if #SETTINGS_LAYOUT > 0 then
        return
    end
    local rows = {
        { key = "enabled", type = "checkbox", x = 33, y = 1, w = 8, h = 2, label = L["启用"], labelSize = 18 },
        { key = "tankEnabled", type = "checkbox", x = 11, y = 1, w = 6, h = 2, label = L["坦克"] },
        { key = "healerEnabled", type = "checkbox", x = 18, y = 1, w = 6, h = 2, label = L["治疗"] },
        { key = "dpsEnabled", type = "checkbox", x = 25, y = 1, w = 6, h = 2, label = L["输出"] },
        { key = "eventColorEnabled", type = "checkbox", x = 3, y = 7, w = 8, h = 2, label = L["颜色"] },
        { key = "eventColorMode", type = "dropdown", x = 13, y = 7, w = 15, h = 2, label = "", items = EVENT_COLOR_ITEMS_FUNC, labelPos = "left", search = true },
        { key = "eventColor", type = "color", x = 29, y = 7, w = 12, h = 2, label = L["自定义颜色"] },
        { key = "card_text", type = "card", x = 2, y = 4, w = 40, h = 25, label = L["文本设置"], accentColor = { r = 1.00, g = 0.82, b = 0.22, a = 0.95 } },
        { key = "description_trash_text_1", type = "description", x = 3, y = 10, w = 14, h = 2, label = "|cffffd637" .. L["中央文本"] .. "|r" },
        { key = "centralEnabled", type = "checkbox", x = 3, y = 12, w = 10, h = 2, label = L["启用"] },
        { key = "centralLead", type = "input", x = 13, y = 12, w = 7, h = 2, label = L["提前(秒)"], labelPos = "right" },
        { key = "centralText", type = "input", x = 13, y = 14, w = 22, h = 2, label = "" },
        { key = "description_trash_text_2", type = "description", x = 3, y = 17, w = 18, h = 2, label = "|cffffd637" .. L["倒数文本"] .. "|r" },
        { key = "countdownEnabled", type = "checkbox", x = 3, y = 19, w = 10, h = 2, label = L["启用"] },
        { key = "preAlertText", type = "input", x = 13, y = 19, w = 22, h = 2, label = "" },
        { key = "description_trash_text_3", type = "description", x = 3, y = 23, w = 18, h = 2, label = "|cffffd637" .. L["计时条改名"] .. "|r" },
        { key = "timerBarRenameEnabled", type = "checkbox", x = 3, y = 25, w = 10, h = 2, label = L["启用"] },
        { key = "timerBarRenameText", type = "input", x = 13, y = 25, w = 22, h = 2, label = "" },

        { key = "card_voice", type = "card", x = 2, y = 30, w = 80, h = 24, label = L["语音设置"], accentColor = { r = 0.28, g = 0.84, b = 1.00, a = 0.95 } },
        { key = "description_trash_voice_1", type = "description", x = 3, y = 33, w = 18, h = 2, label = "|cffffd637" .. L["施法开始"] .. "|r" },
        { key = "tr1Enabled", type = "checkbox", x = 3, y = 35, w = 8, h = 2, label = L["启用"] },
        { key = "tr1Source", type = "dropdown", x = 13, y = 35, w = 12, h = 2, label = L["语音来源"], items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr1Label", type = "dropdown", x = 27, y = 35, w = 24, h = 2, label = L["语音标签"], items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr1LSM", type = "lsm_sound", x = 27, y = 35, w = 24, h = 2, label = L["LSM音效"], search = true },
        { key = "tr1Path", type = "input", x = 27, y = 35, w = 24, h = 2, label = L["文件路径"] },
        { key = "tr1ValueTest", type = "button", x = 52, y = 35, w = 6, h = 2, label = L["试听"] },
        { key = "divider_trash_voice_1", type = "divider", x = 3, y = 38, w = 78, h = 1, label = "" },
        { key = "description_trash_voice_2", type = "description", x = 3, y = 40, w = 18, h = 2, label = "|cffffd637" .. L["倒数提示"] .. "|r" },
        { key = "tr2Enabled", type = "checkbox", x = 3, y = 42, w = 8, h = 2, label = L["启用"] },
        { key = "tr2CountdownLead", type = "dropdown", x = 13, y = 42, w = 10, h = 2, label = "", items = COUNTDOWN_LEAD_ITEMS, search = true },
        { key = "tr2PlayTextEnabled", type = "checkbox", x = 3, y = 45, w = 9, h = 2, label = L["播放文字"] },
        { key = "tr2Source", type = "dropdown", x = 13, y = 45, w = 12, h = 2, label = L["语音来源"], items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr2Label", type = "dropdown", x = 27, y = 45, w = 24, h = 2, label = L["语音标签"], items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr2LSM", type = "lsm_sound", x = 27, y = 45, w = 24, h = 2, label = L["LSM音效"], search = true },
        { key = "tr2Path", type = "input", x = 27, y = 45, w = 24, h = 2, label = L["文件路径"] },
        { key = "tr2ValueTest", type = "button", x = 52, y = 45, w = 6, h = 2, label = L["试听"] },

        { key = "card_display", type = "card", x = 5, y = 59, w = 39, h = 6, label = L["显示设置"], accentColor = { r = 1.00, g = 0.55, b = 0.18, a = 0.95 } },
        { key = "showBunBar", type = "checkbox", x = 43, y = 1, w = 6, h = 2, label = L["竖条"] },
        { key = "showTimerBar", type = "checkbox", x = 55, y = 1, w = 8, h = 2, label = L["计时条"] },
        { key = "showNameplate", type = "checkbox", x = 68, y = 1, w = 8, h = 2, label = L["姓名版"] },

        { key = "card_cast", type = "card", x = 43, y = 4, w = 39, h = 25, label = L["读条设置"], accentColor = { r = 0.40, g = 1.00, b = 0.62, a = 0.95 } },
        { key = "ringEnabled", type = "checkbox", x = 44, y = 7, w = 24, h = 2, label = L["BOSS施法时显示圆环"] },
        { key = "castProgressBarEnabled", type = "checkbox", x = 44, y = 10, w = 24, h = 2, label = L["BOSS施法时显示读条"] },
        { key = "castProgressBarRenameEnabled", type = "checkbox", x = 44, y = 12, w = 8, h = 2, label = L["改名"] },
        { key = "castProgressBarRenameText", type = "input", x = 54, y = 12, w = 22, h = 2, label = "" },
        { key = "ringCastCheckEnabled", type = "checkbox", x = 44, y = 15, w = 12, h = 2, label = L["施法检测"] },
        { key = "divider_trash_cast_1", type = "divider", x = 44, y = 17, w = 37, h = 1, label = "" },
        { key = "targetAlertStartEnabled", type = "checkbox", x = 44, y = 18, w = 14, h = 2, label = L["被点名提示"] },
        { key = "targetAlertStartLSM", type = "lsm_sound", x = 61, y = 18, w = 15, h = 2, label = L["音效"], labelPos = "left", search = true },
        { key = "targetAlertStartValueTest", type = "button", x = 76, y = 18, w = 4, h = 2, label = L["试听"] },
        { key = "targetAlertTankEnabled", type = "checkbox", x = 44, y = 21, w = 18, h = 2, label = L["坦克也生效"] },
        { key = "targetAlertRingEnabled", type = "checkbox", x = 44, y = 25, w = 8, h = 3, label = L["圆环"] },
        { key = "targetAlertIconEnabled", type = "checkbox", x = 52, y = 25, w = 8, h = 3, label = L["图标"] },
        { key = "targetAlertTextEnabledV2", type = "checkbox", x = 60, y = 25, w = 7, h = 3, label = L["文本"] },
        { key = "targetAlertStealthEnabledV2", type = "checkbox", x = 67, y = 25, w = 11, h = 3, label = "|T132089:18:18|t" .. L["隐遁提示"], labelSize = 17 },
    }
    for _, row in ipairs(rows) do
        SETTINGS_LAYOUT[#SETTINGS_LAYOUT + 1] = row
    end
    if ExwindTools and ExwindTools.RegisterModuleLayout then
        ExwindTools:RegisterModuleLayout(SPELL_SETTINGS_MODULE_KEY, SETTINGS_LAYOUT)
    end
end

local function RefreshSettingsDynamicWidgets()
    local Grid = _G.ExwindGrid
    local mdb = GetSpellEditorDB()
    if not (Grid and type(mdb) == "table") then
        return
    end
    local widgets = Grid.Widgets
    local state = settingsScrollChild and Grid.ContainerStates and Grid.ContainerStates[settingsScrollChild]
    if type(state) == "table" and type(state.widgets) == "table" then
        widgets = state.widgets
    end
    if type(widgets) ~= "table" then
        return
    end
    local selectedRow = GetSelectedSpellRow()
    local resolvedCfg = selectedRow and GetResolvedSpellEntry(selectedRow, false) or nil
    local authorVoiceDisabled = type(resolvedCfg) == "table" and resolvedCfg.authorVoiceDisabled == true
    local authorVoiceDisabledText = GetAuthorVoiceDisableText(resolvedCfg)

    if settingsVoiceDisabledNote then
        if authorVoiceDisabled and authorVoiceDisabledText then
            settingsVoiceDisabledNote:SetText(authorVoiceDisabledText)
            settingsVoiceDisabledNote:Show()
        else
            settingsVoiceDisabledNote:Hide()
        end
    end

    local modeDropdownWidget = widgets["eventColorMode"]
    local customColor = widgets["eventColor"]
    local centralLeadWidget = widgets["centralLead"]
    local centralTextWidget = widgets["centralText"]
    local preAlertTextWidget = widgets["preAlertText"]
    local timerRenameTextWidget = widgets["timerBarRenameText"]
    local ringRenameTextWidget = widgets["ringRenameText"]
    local castBarRenameTextWidget = widgets["castProgressBarRenameText"]
    local targetAlertLSMWidget = widgets["targetAlertStartLSM"]
    local targetAlertValueTestWidget = widgets["targetAlertStartValueTest"]
    local targetAlertTankWidget = widgets["targetAlertTankEnabled"]
    local targetAlertRingWidget = widgets["targetAlertRingEnabled"]
    local targetAlertIconWidget = widgets["targetAlertIconEnabled"]
    local targetAlertTextWidget = widgets["targetAlertTextEnabledV2"]
    local targetAlertStealthWidget = widgets["targetAlertStealthEnabledV2"]
    if centralLeadWidget then
        centralLeadWidget:Show()
        SetWidgetUsable(centralLeadWidget, true)
    end
    if centralTextWidget then
        centralTextWidget:Show()
        SetWidgetUsable(centralTextWidget, true)
    end
    if preAlertTextWidget then
        preAlertTextWidget:Show()
        SetWidgetUsable(preAlertTextWidget, true)
    end
    if timerRenameTextWidget then
        timerRenameTextWidget:Show()
        SetWidgetUsable(timerRenameTextWidget, true)
    end
    if ringRenameTextWidget then
        ringRenameTextWidget:Show()
        SetWidgetUsable(ringRenameTextWidget, mdb.ringRenameEnabled == true)
    end
    if castBarRenameTextWidget then
        castBarRenameTextWidget:Show()
        SetWidgetUsable(castBarRenameTextWidget, mdb.castProgressBarRenameEnabled == true)
    end
    if targetAlertLSMWidget then
        targetAlertLSMWidget:Show()
        SetWidgetUsable(targetAlertLSMWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertValueTestWidget then
        targetAlertValueTestWidget:Show()
        SetWidgetUsable(targetAlertValueTestWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertTankWidget then
        targetAlertTankWidget:Show()
        SetWidgetUsable(targetAlertTankWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertRingWidget then
        targetAlertRingWidget:Show()
        SetWidgetUsable(targetAlertRingWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertIconWidget then
        targetAlertIconWidget:Show()
        SetWidgetUsable(targetAlertIconWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertTextWidget then
        targetAlertTextWidget:Show()
        SetWidgetUsable(targetAlertTextWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertStealthWidget then
        targetAlertStealthWidget:Show()
        SetWidgetUsable(targetAlertStealthWidget, mdb.targetAlertStartEnabled == true)
    end
    local colorOn = (mdb.eventColorEnabled == true)
    local colorMode = NormalizeEventColorMode(mdb.eventColorMode)
    SetWidgetUsable(modeDropdownWidget, colorOn)
    if customColor then
        if colorOn and colorMode == "__custom" then
            customColor:Show()
            SetWidgetUsable(customColor, true)
        else
            customColor:Hide()
        end
    end

    for i = 1, 2 do
        local prefix = "tr" .. tostring(i)
        local enabled = (mdb[prefix .. "Enabled"] == true)
        local configEnabled = enabled
        if i == 2 then
            configEnabled = (mdb[prefix .. "PlayTextEnabled"] == true)
        end
        if authorVoiceDisabled then
            enabled = false
            configEnabled = false
        end
        local source = NormalizeTriggerSource(mdb[prefix .. "Source"])

        local enabledWidget = widgets[prefix .. "Enabled"]
        local sourceWidget = widgets[prefix .. "Source"]
        local packWidget = widgets[prefix .. "Label"]
        local lsmWidget = widgets[prefix .. "LSM"]
        local pathWidget = widgets[prefix .. "Path"]
        local valueTestWidget = widgets[prefix .. "ValueTest"]
        local countdownLeadWidget = widgets[prefix .. "CountdownLead"]
        local playTextWidget = widgets[prefix .. "PlayTextEnabled"]
        local offsetModeWidget = widgets[prefix .. "OffsetMode"]
        local offsetSecondsWidget = widgets[prefix .. "OffsetSeconds"]

        SetWidgetUsable(enabledWidget, not authorVoiceDisabled)
        SetWidgetUsable(sourceWidget, configEnabled)
        if countdownLeadWidget then
            countdownLeadWidget:Show()
            SetWidgetUsable(countdownLeadWidget, enabled)
        end
        if playTextWidget then
            playTextWidget:Show()
            SetWidgetUsable(playTextWidget, enabled)
        end

        if source == "pack" then
            if packWidget then packWidget:Show() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(packWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        elseif source == "lsm" then
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Show() end
            if pathWidget then pathWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(lsmWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        else
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Show() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(pathWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        end

        if offsetModeWidget then
            offsetModeWidget:Hide()
        end
        if offsetSecondsWidget then
            offsetSecondsWidget:Hide()
        end
    end
end

local function LoadSelectedSpellToEditor()
    local db = GetSpellEditorDB()
    if type(db) ~= "table" then
        return
    end
    local defaults = GetSpellEditorDefaults()
    for key in pairs(db) do
        db[key] = nil
    end
    CopyTable(db, defaults)

    local row = GetSelectedSpellRow()
    local cfg = GetResolvedSpellEntry(row, false)
    if type(cfg) == "table" then
        db.enabled = cfg.enabled == true
        db.tankEnabled = cfg.tankEnabled == true
        db.healerEnabled = cfg.healerEnabled == true
        db.dpsEnabled = cfg.dpsEnabled == true
        db.showBunBar = cfg.showBunBar ~= false
        db.showTimerBar = cfg.showTimerBar ~= false
        db.showNameplate = cfg.showNameplate == true
        db.eventColorEnabled = cfg.eventColorEnabled == true
        db.eventColorMode = tostring(cfg.eventColorMode or "none")
        db.eventColor = type(cfg.eventColor) == "table" and {
            r = tonumber(cfg.eventColor.r) or 1,
            g = tonumber(cfg.eventColor.g) or 1,
            b = tonumber(cfg.eventColor.b) or 1,
            a = tonumber(cfg.eventColor.a) or 1,
        } or { r = 1, g = 1, b = 1, a = 1 }
        db.centralEnabled = cfg.centralEnabled == true
        db.centralLead = tonumber(cfg.centralLead) or 0
        db.centralText = LocalizeDynamicText(cfg.centralText or "")
        local countdownEnabled = (cfg.countdownEnabled == true) or (cfg.preAlertEnabled == true)
        local countdownLead = tonumber(cfg.countdownLead)
        if countdownLead == nil then
            countdownLead = 5
        end
        db.countdownEnabled = (countdownEnabled == true)
        db.countdownLead = tostring(NormalizeCountdownLeadSeconds(countdownLead))
        db.tr2CountdownLead = db.countdownLead
        db.preAlertEnabled = cfg.preAlertEnabled == true
        db.preAlertText = LocalizeDynamicText(cfg.countdownText or "")
        db.timerBarRenameEnabled = cfg.timerBarRenameEnabled == true
        db.timerBarRenameText = LocalizeDynamicText(cfg.timerBarName or "")
        db.ringEnabled = cfg.ringEnabled == true
        db.ringRenameEnabled = cfg.ringRenameEnabled == true
        db.ringRenameText = tostring(cfg.ringRenameText or "")
        db.castProgressBarEnabled = cfg.castProgressBarEnabled == true
        db.castProgressBarRenameEnabled = cfg.castProgressBarRenameEnabled == true
        db.castProgressBarRenameText = tostring(cfg.castProgressBarRenameText or "")
        db.ringCastCheckEnabled = cfg.ringCastCheckEnabled == true
        db.targetAlertStartEnabled = cfg.targetAlertStartEnabled == true
        db.targetAlertStartLSM = tostring(cfg.targetAlertStartLSM or "")
        db.targetAlertTankEnabled = cfg.targetAlertTankEnabled == true
        db.targetAlertRingEnabled = cfg.targetAlertRingEnabled == true
        db.targetAlertIconEnabled = cfg.targetAlertIconEnabled == true
        db.targetAlertTextEnabledV2 = cfg.targetAlertTextEnabledV2 == true
        db.targetAlertStealthEnabledV2 = cfg.targetAlertStealthEnabledV2 == true
        db.tr1Enabled = cfg.voice1Enabled == true
        db.tr1Source = tostring(cfg.voice1Source or "pack")
        db.tr1Label = tostring(cfg.voice1Label or "")
        db.tr1LSM = tostring(cfg.voice1LSM or "")
        db.tr1Path = tostring(cfg.voice1Path or "")
        db.tr1OffsetMode = tostring(cfg.voice1OffsetMode or "delay")
        db.tr1OffsetSeconds = tonumber(cfg.voice1OffsetSeconds) or 0
        local countdownVoiceEnabled = (cfg.countdownVoiceEnabled == true) or (cfg.voice2Enabled == true)
        local playTextEnabled = (cfg.countdownPlayName == true) or (cfg.voice2Enabled == true)
        db.tr2Enabled = (countdownVoiceEnabled == true)
        db.tr2PlayTextEnabled = (playTextEnabled == true)
        db.tr2Source = tostring(cfg.voice2Source or "pack")
        db.tr2Label = tostring(cfg.voice2Label or "")
        db.tr2LSM = tostring(cfg.voice2LSM or "")
        db.tr2Path = tostring(cfg.voice2Path or "")
        db.tr2OffsetMode = tostring(cfg.voice2OffsetMode or "delay")
        db.tr2OffsetSeconds = tonumber(cfg.voice2OffsetSeconds) or 0
    end
end

local function PersistEditorToSelectedSpell(changedKey)
    if _suspendSpellSettingPersist then
        return
    end
    local row = GetSelectedSpellRow()
    if not row or not TrashStore or not TrashStore.GetSpellEntry then
        return
    end
    local db = GetSpellEditorDB()
    if type(db) ~= "table" then
        return
    end
    local saved = TrashStore.GetSpellEntry(row.mapID, row.npcID, row.spellID, true)
    if type(saved) ~= "table" then
        return
    end

    saved.enabled = db.enabled == true
    saved.tankEnabled = db.tankEnabled == true
    saved.healerEnabled = db.healerEnabled == true
    saved.dpsEnabled = db.dpsEnabled == true
    saved.showBunBar = db.showBunBar == true
    saved.showTimerBar = db.showTimerBar == true
    saved.showNameplate = db.showNameplate == true
    saved.eventColorEnabled = db.eventColorEnabled == true
    saved.eventColorMode = tostring(db.eventColorMode or "none")
    saved.eventColor = type(db.eventColor) == "table" and {
        r = tonumber(db.eventColor.r) or 1,
        g = tonumber(db.eventColor.g) or 1,
        b = tonumber(db.eventColor.b) or 1,
        a = tonumber(db.eventColor.a) or 1,
    } or nil
    saved.centralEnabled = db.centralEnabled == true
    saved.centralLead = tonumber(db.centralLead) or 0
    saved.centralText = tostring(db.centralText or "")
    if changedKey == "tr2CountdownLead" then
        db.countdownLead = tostring(NormalizeCountdownLeadSeconds(db.tr2CountdownLead))
    elseif changedKey == "countdownLead" then
        db.tr2CountdownLead = tostring(NormalizeCountdownLeadSeconds(db.countdownLead))
    end
    local countdownEnabled = (db.countdownEnabled == true)
    local countdownLead = NormalizeCountdownLeadSeconds(db.countdownLead)
    db.countdownLead = tostring(countdownLead)
    db.tr2CountdownLead = tostring(countdownLead)
    saved.countdownEnabled = countdownEnabled
    saved.countdownLead = countdownLead
    saved.preAlertEnabled = countdownEnabled
    saved.countdownText = tostring(db.preAlertText or "")
    saved.timerBarRenameEnabled = db.timerBarRenameEnabled == true
    saved.timerBarName = tostring(db.timerBarRenameText or "")
    saved.ringEnabled = db.ringEnabled == true
    saved.ringRenameEnabled = db.ringRenameEnabled == true
    saved.ringRenameText = tostring(db.ringRenameText or "")
    saved.castProgressBarEnabled = db.castProgressBarEnabled == true
    saved.castProgressBarRenameEnabled = db.castProgressBarRenameEnabled == true
    saved.castProgressBarRenameText = tostring(db.castProgressBarRenameText or "")
    saved.ringCastCheckEnabled = db.ringCastCheckEnabled == true
    saved.targetAlertStartEnabled = db.targetAlertStartEnabled == true
    saved.targetAlertStartLSM = tostring(db.targetAlertStartLSM or "")
    saved.targetAlertTankEnabled = db.targetAlertTankEnabled == true
    saved.targetAlertRingEnabled = db.targetAlertRingEnabled == true
    saved.targetAlertIconEnabled = db.targetAlertIconEnabled == true
    saved.targetAlertTextEnabledV2 = db.targetAlertTextEnabledV2 == true
    saved.targetAlertStealthEnabledV2 = db.targetAlertStealthEnabledV2 == true
    saved.targetAlertTextEnabled = nil
    saved.targetAlertStealthEnabled = nil
    saved.voice1Enabled = db.tr1Enabled == true
    saved.voice1Source = NormalizeTriggerSource(db.tr1Source)
    saved.voice1Label = tostring(db.tr1Label or "")
    saved.voice1LSM = tostring(db.tr1LSM or "")
    saved.voice1Path = tostring(db.tr1Path or "")
    saved.voice1OffsetMode = tostring(db.tr1OffsetMode or "delay")
    saved.voice1OffsetSeconds = tonumber(db.tr1OffsetSeconds) or 0
    saved.countdownVoiceEnabled = (db.tr2Enabled == true)
    saved.countdownPlayName = (db.tr2PlayTextEnabled == true)
    saved.voice2Enabled = (db.tr2PlayTextEnabled == true)
    saved.voice2Source = NormalizeTriggerSource(db.tr2Source)
    saved.voice2Label = tostring(db.tr2Label or "")
    saved.voice2LSM = tostring(db.tr2LSM or "")
    saved.voice2Path = tostring(db.tr2Path or "")
    saved.voice2OffsetMode = tostring(db.tr2OffsetMode or "delay")
    saved.voice2OffsetSeconds = tonumber(db.tr2OffsetSeconds) or 0
    saved.customName = tostring(db.customName or saved.customName or "")

    if TrashStore.PublishConfigChanged then
        TrashStore.PublishConfigChanged(changedKey or "spellEntry")
    end
end

local function RefreshDungeonButtonVisuals()
    for i = 1, #activeDungeonButtons do
        local btn = activeDungeonButtons[i]
        if btn and btn.text then
            local active = btn.mapID == selectedMapID
            local hovered = btn._hovered == true
            btn:SetBackdropColor(
                active and 0.10 or (hovered and 0.08 or 0.04),
                active and 0.40 or (hovered and 0.08 or 0.04),
                active and 0.80 or (hovered and 0.10 or 0.04),
                active and 0.30 or (hovered and 0.88 or 0.80)
            )
            btn:SetBackdropBorderColor(
                active and 0.00 or (hovered and 0.48 or 0.36),
                active and 0.80 or (hovered and 0.48 or 0.36),
                active and 1.00 or (hovered and 0.55 or 0.40),
                active and 1.00 or 0.90
            )
            btn.icon:SetDesaturated(not active and not hovered)
            btn.text:SetTextColor(active and 1 or 0.86, active and 0.92 or 0.86, active and 0.40 or 0.86)
        end
    end
end

local function ReleaseDungeonButtons()
    for i = 1, #activeDungeonButtons do
        local btn = activeDungeonButtons[i]
        btn:Hide()
        btn:ClearAllPoints()
        btn:SetParent(nil)
        table.insert(dungeonButtonPool, btn)
    end
    wipe(activeDungeonButtons)
end

local function ReleaseSpellRows()
    for i = 1, #activeSpellRows do
        local row = activeSpellRows[i]
        if row then
            row:Hide()
            row:ClearAllPoints()
            row:SetParent(nil)
            if row._divider then
                spellDividerPool[#spellDividerPool + 1] = row
            else
                spellRowPool[#spellRowPool + 1] = row
            end
        end
    end
    wipe(activeSpellRows)
end

local function AcquireDungeonButton()
    local btn = table.remove(dungeonButtonPool)
    if btn then
        return btn
    end

    btn = CreateFrame("Button", nil, mapScrollChild, "BackdropTemplate")
    btn:SetSize(72, 74)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(52, 52)
    btn.icon:SetPoint("TOP", 0, -2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("TOP", btn.icon, "BOTTOM", 0, -1)
    btn.text:SetWidth(76)
    btn.text:SetJustifyH("CENTER")
    btn.text:SetWordWrap(false)
    btn.text:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")

    btn:SetScript("OnEnter", function(self)
        self._hovered = true
        RefreshDungeonButtonVisuals()
    end)
    btn:SetScript("OnLeave", function(self)
        self._hovered = false
        RefreshDungeonButtonVisuals()
    end)

    return btn
end

local function AcquireSpellRow()
    local row = table.remove(spellRowPool)
    if row then
        return row
    end

    row = CreateFrame("Button", nil, spellScrollChild, "BackdropTemplate")
    row:SetHeight(C.SPELL_CARD.height)
    row:EnableMouse(true)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.02, 0.02, 0.03, 0.86)
    row:SetBackdropBorderColor(0.25, 0.25, 0.28, 0.90)

    row.leftBar = row:CreateTexture(nil, "ARTWORK")
    row.leftBar:SetDrawLayer("ARTWORK", -8)
    row.leftBar:SetWidth(4)
    row.leftBar:SetPoint("TOPLEFT", 0, 0)
    row.leftBar:SetPoint("BOTTOMLEFT", 0, 0)

    local check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 6, 0)
    row.check = check

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(29, 29)
    icon:SetPoint("LEFT", check, "RIGHT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local textBlock = CreateFrame("Frame", nil, row)
    textBlock:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    textBlock:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    textBlock:SetPoint("CENTER", row, "CENTER", 0, 0)
    textBlock:SetHeight(32)
    row.textBlock = textBlock

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", textBlock, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetMaxLines(2)
    label:SetSpacing(1)
    label:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
    row.label = label

    local atlasHolder = CreateFrame("Frame", nil, row)
    atlasHolder:SetPoint("RIGHT", textBlock, "RIGHT", 0, -1)
    atlasHolder:SetSize(35, 35)
    atlasHolder:EnableMouse(true)
    atlasHolder:Hide()
    row.testAtlasHolder = atlasHolder

    local atlas = atlasHolder:CreateTexture(nil, "OVERLAY")
    atlas:SetAllPoints()
    row.testAtlas = atlas

    atlasHolder:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[TEST_THREAT_ATLAS_TOOLTIP], 0.20, 1.00, 0.20, true)
        GameTooltip:Show()
    end)
    atlasHolder:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    label:SetPoint("RIGHT", atlasHolder, "LEFT", -6, 0)

    local meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    meta:SetPoint("TOPRIGHT", textBlock, "BOTTOMRIGHT", 0, -4)
    meta:SetJustifyH("LEFT")
    meta:SetJustifyV("TOP")
    meta:SetWordWrap(false)
    meta:SetFont(ExwindTools.MAIN_FONT, 13, "")
    meta:SetTextColor(0.72, 0.76, 0.82)
    row.meta = meta

    row:SetScript("OnEnter", function(self)
        self._hovered = true
        if self._applyVisual then self:_applyVisual() end
    end)
    row:SetScript("OnLeave", function(self)
        self._hovered = false
        if self._applyVisual then self:_applyVisual() end
    end)

    return row
end

local function RefreshSpellRowVisuals()
    for i = 1, #activeSpellRows do
        local row = activeSpellRows[i]
        if row then
            row._selected = (row.npcID == selectedNPCID and row.spellID == selectedSpellID)
        end
        if row and row._applyVisual then
            row:_applyVisual()
        end
    end
end

local function UpdateDetailCard()
    if not detailTitle then
        return
    end
    local row = GetSelectedSpellRow()
    if not row then
        SetDetailCardEmpty(L["点击左侧法术后，可在此查看法术描述。"])
        return
    end

    local cfg = GetResolvedSpellEntry(row, false)
    local cachedName, icon = GetRowSpellNameAndIcon(row)
    local desc = GetRowSpellDescription(row)
    local castLine, bodyText = SplitSpellDescription(desc)
    local displayName = tostring(row.spellName or "")
    if cachedName and cachedName ~= "" then
        displayName = cachedName
    end
    local infoLines
    if row.isCustomEvent == true then
        infoLines = {
            string.format("%s：%s", L["触发类型"], tostring(row.customTriggerLabel or L["自定义事件"])),
            string.format("%s：%s", L["事件分类"], L["自定义小怪事件"]),
        }
    else
        local cdText = FormatCDList(row.cd)
        infoLines = {
            string.format("%s：%s", L["首次施放时间"], tostring(row.first or "-")),
            string.format("%s：%s", L["CD时间"], cdText),
        }
    end

    if detailPlaceholder then detailPlaceholder:Hide() end
    detailIcon:Show()
    detailIcon:SetTexture(icon or 134400)
    detailTitle:SetText(displayName)
    detailMeta:SetText(string.format("%s  |cff7f8794spell:%s|r", tostring(row.mobName or "-"),
        tostring(row.spellID or "-")))
    detailCast:SetText((castLine ~= "" and tostring(castLine)) or L["暂无施法信息"])
    detailBody:SetText((bodyText ~= "" and tostring(bodyText)) or L["暂无描述。"])
    detailInfo:SetText(table.concat(infoLines, "\n"))
    if detailDivider then
        detailDivider:Show()
    end
    RefreshDetailCardLayout()
end

local function BuildDungeonButtons()
    ReleaseDungeonButtons()
    if not mapScrollChild then
        return
    end

    local rows = GetDungeonRows()
    for i = 1, #rows do
        local row = rows[i]
        local btn = AcquireDungeonButton()
        btn:SetParent(mapScrollChild)
        btn.mapID = row.mapID

        local gridRow = math.floor((i - 1) / MAP_COLS)
        local gridCol = (i - 1) % MAP_COLS
        btn:SetPoint("TOPLEFT", 10 + gridCol * (MAP_CELL_W + MAP_CELL_GAP_X),
            -4 - gridRow * (MAP_CELL_H + MAP_CELL_GAP_Y))
        btn.icon:SetTexture(GetMapIcon(row.mapID))
        btn.text:SetText(GetShortDisplayDungeonName(row.mapID, row.mapName))
        btn:Show()

        btn:SetScript("OnClick", function(self)
            selectedMapID = self.mapID
            selectedNPCID = nil
            selectedSpellID = nil
            RefreshDungeonButtonVisuals()
            Page:RefreshSpellList()
        end)

        activeDungeonButtons[#activeDungeonButtons + 1] = btn
    end

    local totalRows = math.max(1, math.ceil(#rows / MAP_COLS))
    mapScrollChild:SetSize(208, totalRows * MAP_CELL_H + math.max(0, totalRows - 1) * MAP_CELL_GAP_Y + 12)

    RefreshDungeonButtonVisuals()
end

function Page:RefreshSpellList()
    _spellListBuildToken = _spellListBuildToken + 1
    local token = _spellListBuildToken
    ReleaseSpellRows()
    if not spellScrollChild then
        return
    end

    local rows = GetSpellRows(selectedMapID)
    local enabledRows = {}
    local disabledRows = {}
    for i = 1, #rows do
        local cfg = GetResolvedSpellEntry(rows[i], false)
        if cfg.enabled == true then
            enabledRows[#enabledRows + 1] = rows[i]
        else
            disabledRows[#disabledRows + 1] = rows[i]
        end
    end
    local orderedRows = {}
    for i = 1, #enabledRows do orderedRows[#orderedRows + 1] = enabledRows[i] end
    for i = 1, #disabledRows do orderedRows[#orderedRows + 1] = disabledRows[i] end
    local function IsValid()
        return token == _spellListBuildToken and Page._visible and spellScrollChild ~= nil
    end

    local function BuildOne(rowData, index, cardW)
        local cfg = GetResolvedSpellEntry(rowData, false)
        local row = AcquireSpellRow()
        row:SetParent(spellScrollChild)
        local col = (index - 1) % C.SPELL_CARD.cols
        local gridRow = math.floor((index - 1) / C.SPELL_CARD.cols)
        local x = col * (cardW + C.SPELL_CARD.gapX)
        local y = -4 - gridRow * (C.SPELL_CARD.height + C.SPELL_CARD.gapY)
        row:SetSize(cardW, C.SPELL_CARD.height)
        row:SetPoint("TOPLEFT", 0 + x, y)
        row.npcID = rowData.npcID
        row.spellID = rowData.spellID
        row.icon:SetTexture(GetRowSpellIcon(rowData))
        row._enabled = cfg.enabled == true
        row.check:SetChecked(cfg.enabled == true)
        row.label:SetText(tostring(rowData.spellName or ""))
        if TEST_THREAT_ATLAS_SPELLS[tonumber(rowData.spellID)] then
            row.testAtlas:SetAtlas(TEST_THREAT_ATLAS_NAME, false)
            row.testAtlasHolder:Show()
        else
            row.testAtlasHolder:Hide()
        end
        row.meta:SetText(rowData.isCustomEvent == true
            and
            string.format("%s  |cff7f8794%s|r", tostring(rowData.customTriggerLabel or L["自定义事件"]),
                tostring(rowData.mobName or ""))
            or string.format("%s  |cff7f8794spell:%s|r", tostring(rowData.mobName or ""),
                tostring(rowData.spellID or "-")))
        row._selected = (rowData.npcID == selectedNPCID and rowData.spellID == selectedSpellID)
        row._hovered = false
        row._applyVisual = function(self)
            if self._selected then
                self:SetBackdropColor(0.1, 0.4, 0.8, 0.3)
                self:SetBackdropBorderColor(0, 0.8, 1, 1)
                self.leftBar:SetColorTexture(0, 0.8, 1, 1)
            elseif self._hovered then
                self:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                self.leftBar:SetColorTexture(0.5, 0.5, 0.5, 1)
            else
                self:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
                self:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.95)
                self.leftBar:SetColorTexture(0.38, 0.38, 0.38, 0.95)
            end
            if self._enabled == true then
                self.icon:SetVertexColor(1, 1, 1)
                self.label:SetTextColor(self._selected and 1 or 0.95, self._selected and 0.86 or 0.95,
                    self._selected and 0.48 or 0.95)
                self.meta:SetTextColor(0.72, 0.76, 0.82)
            else
                self.icon:SetVertexColor(0.55, 0.55, 0.55)
                self.label:SetTextColor(0.62, 0.62, 0.64)
                self.meta:SetTextColor(0.48, 0.48, 0.52)
            end
        end

        row.check:SetScript("OnClick", function(self)
            local saved = TrashStore and TrashStore.GetSpellEntry and
                TrashStore.GetSpellEntry(rowData.mapID, rowData.npcID, rowData.spellID, true) or nil
            if type(saved) == "table" then
                saved.enabled = self:GetChecked() == true
                if TrashStore.PublishConfigChanged then
                    TrashStore.PublishConfigChanged("enabled")
                end
            end
            selectedNPCID = rowData.npcID
            selectedSpellID = rowData.spellID
            Page:RefreshSpellList()
            Page:RefreshSelectedSpell()
        end)

        row:SetScript("OnClick", function()
            selectedNPCID = rowData.npcID
            selectedSpellID = rowData.spellID
            RefreshSpellRowVisuals()
            Page:RefreshSelectedSpell()
        end)

        row:_applyVisual()
        row:Show()
        activeSpellRows[#activeSpellRows + 1] = row
    end

    local function Finalize()
        if not IsValid() then
            return
        end
        local totalRows = math.max(1, math.ceil(#orderedRows / C.SPELL_CARD.cols))
        local totalH = totalRows * C.SPELL_CARD.height + math.max(0, totalRows - 1) * C.SPELL_CARD.gapY + 8
        spellScrollChild:SetHeight(math.max(200, totalH))
        if not selectedNPCID and not selectedSpellID and orderedRows[1] then
            selectedNPCID = orderedRows[1].npcID
            selectedSpellID = orderedRows[1].spellID
        end
        PrimeSpellCache(orderedRows)
        RefreshSpellRowVisuals()
        Page:RefreshSelectedSpell()
    end

    local function BuildSync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        if totalW < 240 then totalW = 360 end
        local usableW = math.max(240, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        for i = 1, #orderedRows do
            BuildOne(orderedRows[i], i, cardW)
        end
        Finalize()
    end

    local function BuildAsync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        if totalW < 240 then totalW = 360 end
        local usableW = math.max(240, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        for i = 1, #orderedRows do
            if not IsValid() then
                return
            end
            BuildOne(orderedRows[i], i, cardW)
            coroutine.yield()
        end
        Finalize()
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            BuildAsync()
        end, "EXBoss_TrashCD_SpellList", true)
    else
        BuildSync()
    end
end

local function RefreshSelectedSpellSync()
    _suspendSpellSettingPersist = true
    LoadSelectedSpellToEditor()
    _suspendSpellSettingPersist = false
    UpdateDetailCard()
    Page:RenderSettingsGrid(true)
end

GetRowSpellDescription = function(row)
    if type(row) == "table" and row.isCustomEvent == true then
        local spellID = tonumber(row.spellID)
        if spellID and spellID > 0 then
            local apiDesc = GetSpellDescription(spellID)
            if type(apiDesc) == "string" and apiDesc ~= "" and apiDesc ~= L["暂无描述。"] then
                return apiDesc
            end
        end
        local desc = tostring(row.description or "")
        if desc ~= "" then
            return desc
        end
        return L["自定义小怪事件。"]
    end
    return GetSpellDescription(type(row) == "table" and row.spellID or nil)
end

function Page:RefreshSelectedSpell()
    _selectionRefreshToken = _selectionRefreshToken + 1
    local token = _selectionRefreshToken

    local function IsValid()
        return token == _selectionRefreshToken and Page._visible and root ~= nil
    end

    local function RunAsync()
        if not IsValid() then
            return
        end
        _suspendSpellSettingPersist = true
        LoadSelectedSpellToEditor()
        _suspendSpellSettingPersist = false
        coroutine.yield()
        if not IsValid() then
            return
        end
        UpdateDetailCard()
        coroutine.yield()
        if not IsValid() then
            return
        end
        Page:RenderSettingsGrid(true)
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            RunAsync()
        end, "EXBoss_TrashCD_SelectedSpell", true)
    else
        RefreshSelectedSpellSync()
    end
end

function Page:RenderSettingsGrid(resetScroll)
    if not (settingsScrollChild and settingsPane and settingsPane:IsShown()) then
        return
    end
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end
    BuildSettingsLayout()
    local db = GetSpellEditorDB()
    local w = settingsPane:GetWidth()
    if w < 100 then
        w = 860
    end
    settingsScrollChild:SetWidth(w - 42)
    if resetScroll == true then
        settingsScrollFrame:SetVerticalScroll(0)
    end
    if Grid.SetContainerCols then
        Grid:SetContainerCols(settingsScrollChild, 81)
    end
    if Grid.SetContainerPadding then
        Grid:SetContainerPadding(settingsScrollChild, { left = 0, right = 10, top = 10, bottom = 0 })
    end
    RegisterSpellSettingsGridAsActive(SPELL_SETTINGS_MODULE_KEY)
    Grid:Render(settingsScrollChild, SETTINGS_LAYOUT, db, SPELL_SETTINGS_MODULE_KEY)
    RefreshSettingsDynamicWidgets()
end

local function EnsureUI(parent)
    if root then
        return
    end

    root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)

    local leftW = 380
    local topLeftH = 212
    local topRightH = 170
    local gap = 8

    mapPane = CreateSectionBackdrop(root)
    mapPane:SetPoint("TOPLEFT", 8, -8)
    mapPane:SetSize(leftW, topLeftH)

    spellPane = CreateSectionBackdrop(root)
    spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
    spellPane:SetPoint("BOTTOMLEFT", 8, 8)
    spellPane:SetWidth(leftW)

    detailPane = CreateSectionBackdrop(root)
    detailPane:SetPoint("TOPLEFT", mapPane, "TOPRIGHT", gap, 0)
    detailPane:SetPoint("TOPRIGHT", -8, -8)
    detailPane:SetHeight(topRightH)

    settingsPane = CreateSectionBackdrop(root)
    settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -gap)
    settingsPane:SetPoint("BOTTOMRIGHT", -8, 8)

    mapScrollFrame = CreateFrame("ScrollFrame", nil, mapPane, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(mapScrollFrame)
    end
    mapScrollFrame:SetPoint("TOPLEFT", mapPane, "TOPLEFT", 0, -8)
    mapScrollFrame:SetPoint("TOPRIGHT", mapPane, "TOPRIGHT", -24, -8)
    mapScrollFrame:SetPoint("BOTTOMLEFT", mapPane, "BOTTOMLEFT", 0, 2)

    mapScrollChild = CreateFrame("Frame", nil, mapScrollFrame)
    mapScrollChild:SetSize(208, 1)
    mapScrollFrame:SetScrollChild(mapScrollChild)

    spellScrollFrame = CreateFrame("ScrollFrame", nil, spellPane, "UIPanelScrollFrameTemplate")
    spellScrollFrame:SetPoint("TOPLEFT", 2, -8)
    spellScrollFrame:SetPoint("BOTTOMRIGHT", spellPane, "BOTTOMRIGHT", -24, 4)
    spellScrollChild = CreateFrame("Frame", nil, spellScrollFrame)
    spellScrollChild:SetWidth(leftW - 30)
    spellScrollChild:SetHeight(300)
    spellScrollFrame:SetScrollChild(spellScrollChild)

    detailPlaceholder = detailPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailPlaceholder:SetPoint("CENTER", 0, 0)
    detailPlaceholder:SetTextColor(0.55, 0.55, 0.6)
    detailPlaceholder:SetText(L["点击左侧法术后，可在此查看法术描述。"])

    detailIcon = detailPane:CreateTexture(nil, "ARTWORK")
    detailIcon:SetSize(52, 52)
    detailIcon:SetPoint("TOPLEFT", 10, -12)
    detailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    detailTitle = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 8, -1)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(false)
    detailTitle:SetFont(ExwindTools.MAIN_FONT, 23, "OUTLINE")
    detailTitle:SetTextColor(1, 0.95, 0.55)

    detailMeta = detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailMeta:SetPoint("LEFT", detailTitle, "RIGHT", 10, 0)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetWordWrap(false)
    detailMeta:SetFont(ExwindTools.MAIN_FONT, 16, "")
    detailMeta:SetTextColor(0.55, 0.57, 0.62)

    detailCast = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailCast:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -2)
    detailCast:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailCast:SetJustifyH("LEFT")
    detailCast:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    detailCast:SetTextColor(0.92, 0.92, 0.95)

    detailBody = detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailBody:SetPoint("TOPLEFT", detailCast, "BOTTOMLEFT", 0, -8)
    detailBody:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailBody:SetJustifyH("LEFT")
    detailBody:SetJustifyV("TOP")
    detailBody:SetWordWrap(true)
    detailBody:SetSpacing(2)
    detailBody:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
    detailBody:SetTextColor(1, 0.82, 0.2)

    detailDivider = detailPane:CreateTexture(nil, "ARTWORK")
    detailDivider:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 10)
    detailDivider:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -14, 10)
    detailDivider:SetHeight(1)
    detailDivider:SetColorTexture(1, 1, 1, 0.14)
    detailDivider:Hide()

    detailInfo = detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailInfo:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 16)
    detailInfo:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailInfo:SetJustifyH("LEFT")
    detailInfo:SetJustifyV("BOTTOM")
    detailInfo:SetWordWrap(true)
    detailInfo:SetTextColor(0.82, 0.86, 0.92)

    local settingsTitle = settingsPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 10, -8)
    settingsTitle:SetText(L["当前法术设置"])
    settingsTitle:SetTextColor(1, 0.82, 0.45)
    settingsTitle:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")

    settingsVoiceDisabledNote = settingsPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsVoiceDisabledNote:SetPoint("TOPLEFT", settingsPane, "TOPLEFT", 150, -10)
    settingsVoiceDisabledNote:SetPoint("RIGHT", settingsPane, "RIGHT", -28, 0)
    settingsVoiceDisabledNote:SetJustifyH("LEFT")
    settingsVoiceDisabledNote:SetWordWrap(true)
    settingsVoiceDisabledNote:SetTextColor(1, 0.82, 0.25)
    settingsVoiceDisabledNote:Hide()

    settingsScrollFrame = CreateFrame("ScrollFrame", nil, settingsPane, "ScrollFrameTemplate")
    settingsScrollFrame:SetPoint("TOPLEFT", 2, -30)
    settingsScrollFrame:SetPoint("BOTTOMRIGHT", settingsPane, "BOTTOMRIGHT", -22, 4)
    settingsScrollChild = CreateFrame("Frame", nil, settingsScrollFrame)
    settingsScrollChild:SetWidth(900)
    settingsScrollChild:SetHeight(420)
    settingsScrollFrame:SetScrollChild(settingsScrollChild)

    if ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(spellScrollFrame)
        ExBoss.UI.ApplyModernScrollBarSkin(settingsScrollFrame)
    end
    SetDetailCardEmpty(L["点击左侧法术后，可在此查看法术描述。"])
end

if ExwindTools and type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState(SPELL_SETTINGS_MODULE_KEY .. ".DatabaseChanged", "ExBoss.TrashCD.SpellEditorDB",
        function(info)
            local key = info and info.key or "spellSetting"
            PersistEditorToSelectedSpell(key)
            if key == "enabled" then
                Page:RefreshSpellList()
            end
            UpdateDetailCard()
            RefreshSettingsDynamicWidgets()
        end)

    ExwindTools:WatchState(SPELL_SETTINGS_MODULE_KEY .. ".ButtonClicked", "ExBoss.TrashCD.SpellEditorButton",
        function(info)
            local db = GetSpellEditorDB()
            if type(db) ~= "table" or type(info) ~= "table" then
                return
            end
            if info.key == "tr1ValueTest" then
                PlayVoicePreview(db.tr1Source, db.tr1Label, db.tr1LSM, db.tr1Path)
            elseif info.key == "tr2ValueTest" then
                PlayVoicePreview(db.tr2Source, db.tr2Label, db.tr2LSM, db.tr2Path)
            elseif info.key == "targetAlertStartValueTest" then
                PlayVoicePreview("lsm", "", db.targetAlertStartLSM, "")
            end
        end)
end

if ExwindTools and not Page._eventsRegistered then
    ExwindTools:RegisterEvent("SPELL_DATA_LOAD_RESULT", "ExBoss.TrashCDPage.SpellCache", function(_, spellID, success)
        if spellID then
            CACHE.spellCachePending[spellID] = nil
            CACHE.spellTextCache[spellID] = nil
        end
        if not success then
            return
        end
        if Page._visible and CurrentTrashHasSpellID(spellID) then
            Page:RefreshSelectedSpell()
        end
    end)

    ExwindTools:RegisterEvent("SPELL_TEXT_UPDATE", "ExBoss.TrashCDPage.SpellText", function()
        wipe(CACHE.spellTextCache)
        if Page._visible then
            Page:RefreshSelectedSpell()
        end
    end)

    Page._eventsRegistered = true
end

function Page:Render(contentFrame)
    EnsureUI(contentFrame)
    root:SetParent(contentFrame)
    root:ClearAllPoints()
    root:SetAllPoints(contentFrame)
    root:Show()
    Page._visible = true

    if TrashCore and TrashCore.SetMonitorUIEnabled then
        TrashCore.SetMonitorUIEnabled(true)
    end
    if TrashStore and type(TrashStore.SyncSavedToModuleDB) == "function" then
        TrashStore.SyncSavedToModuleDB()
    end

    if not selectedMapID then
        selectedMapID = ResolveDefaultMapID()
    end

    BuildDungeonButtons()
    self:RefreshSpellList()
end

function Page:Hide()
    Page._visible = false
    ClearSpellSettingsGridActiveRegistration()
    if TrashCore and TrashCore.SetMonitorUIEnabled then
        TrashCore.SetMonitorUIEnabled(false)
    end
    if root then
        root:Hide()
    end
end
