---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss = ExBoss or {}
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.Tools = ExBoss.Tools or {}
ExBoss.Tools.StateIcons = ExBoss.Tools.StateIcons or {}

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
local C_Spell = _G.C_Spell
local C_Item = _G.C_Item
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local LibStub = _G.LibStub
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT
local UIParent = _G.UIParent
local issecretvalue = _G.issecretvalue
local PlaySoundFile = _G.PlaySoundFile
local wipe = _G.wipe
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local MODULE_KEY = "ExBoss.Tools.StateIcons"
local TARGET_CELL_PX = 18
local BASE_GRID_COLS = 100
local MIN_GRID_COLS = 100
local MAX_GRID_COLS = 100
local LAYOUT_CACHE = {}

local function IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function CanApplyBackdrop(frame)
    if not frame then
        return false
    end
    if type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function" then
        return true
    end

    local okWidth, width = pcall(frame.GetWidth, frame)
    local okHeight, height = pcall(frame.GetHeight, frame)
    if not okWidth or not okHeight then
        return false
    end
    if IsSecretValue(width) or IsSecretValue(height) then
        return false
    end
    return true
end

local function SafeSetBackdrop(frame, backdrop)
    if not frame or type(frame.SetBackdrop) ~= "function" then
        return false
    end
    if not CanApplyBackdrop(frame) then
        return false
    end
    local ok = pcall(frame.SetBackdrop, frame, backdrop)
    return ok
end

local DEFAULTS = {
    anchorX = -228,
    anchorY = -61,
    attachToCustom = false,
    customAttachTarget = "",
    checkbox_8436 = false,
    enabled = false,
    hideTimeText = false,
    font_count = {
        a = 1,
        b = 1,
        color = {
            1,
            0.82,
            0,
            1,
        },
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 17,
        x = 0,
        y = -26,
    },
    font_time = {
        a = 1,
        b = 1,
        color = {
            1,
            1,
            1,
            1,
        },
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 18,
        x = 0,
        y = 0,
    },
    growDir = "RIGHT",
    icon = {
        borderColorA = 1,
        borderColorB = 0,
        borderColorG = 0,
        borderColorR = 0,
        borderPadding = 1,
        borderSize = 2,
        borderTexture = "Square Full White",
        height = 43,
        reverse = true,
        showBorder = true,
        showIcon = true,
        width = 43,
        x = 0,
        y = 0,
    },
    slot1 = "potion_1236616",
    slot1EndMode = "NORMAL",
    slot1Glow = true,
    slot1TriggerSound = "",
    slot1ExpireSound = "",
    slot1TriggerSoundEnabled = false,
    slot1ExpireSoundEnabled = false,
    slot2 = "trinket_249343_a",
    slot2EndMode = "FADE",
    slot2Glow = true,
    slot2TriggerSound = "",
    slot2ExpireSound = "",
    slot2TriggerSoundEnabled = false,
    slot2ExpireSoundEnabled = false,
    slot3 = "trinket_249343_b",
    slot3EndMode = "FADE",
    slot3Glow = true,
    slot3TriggerSound = "",
    slot3ExpireSound = "",
    slot3TriggerSoundEnabled = false,
    slot3ExpireSoundEnabled = false,
    slot4 = "trinket_249346",
    slot4EndMode = "FADE",
    slot4Glow = true,
    slot4TriggerSound = "",
    slot4ExpireSound = "",
    slot4TriggerSoundEnabled = false,
    slot4ExpireSoundEnabled = false,
    slot5 = "trinket_249344",
    slot5EndMode = "FADE",
    slot5Glow = true,
    slot5TriggerSound = "",
    slot5ExpireSound = "",
    slot5TriggerSoundEnabled = false,
    slot5ExpireSoundEnabled = false,
    slot6 = "trinket_249808",
    slot6EndMode = "FADE",
    slot6Glow = true,
    slot6TriggerSound = "",
    slot6ExpireSound = "",
    slot6TriggerSoundEnabled = false,
    slot6ExpireSoundEnabled = false,
    slot7 = "trinket_2500256",
    slot7EndMode = "FADE",
    slot7Glow = true,
    slot7TriggerSound = "",
    slot7ExpireSound = "",
    slot7TriggerSoundEnabled = false,
    slot7ExpireSoundEnabled = false,
    spacing = 1,
}


local LAYOUT = {
    { key = "header", type = "header", x = 2, y = 1, w = 95, h = 3, label = L["饰品监控"], labelSize = 25 },
    { key = "enabled", type = "checkbox", x = 2, y = 5, w = 8, h = 2, label = L["启用"] },
    { key = "checkbox_8436", type = "checkbox", x = 14, y = 5, w = 8, h = 2, label = L["预览"] },
    { key = "hideTimeText", type = "checkbox", x = 24, y = 5, w = 18, h = 2, label = L["隐藏时间文本"] },
    { key = "growDir", type = "dropdown", x = 2, y = 20, w = 20, h = 3, label = L["增长方向"], items = { { L["向右"], "RIGHT" }, { L["向左"], "LEFT" }, { L["向上"], "UP" }, { L["向下"], "DOWN" }, { L["居中"], "CENTER" } } },
    { key = "spacing", type = "slider", x = 23, y = 20, w = 20, h = 2, label = L["图标间距"], min = 0, max = 40 },
    { key = "slot1", type = "dropdown", x = 2, y = 35, w = 20, h = 3, label = L["第一个图标"], items = {} },
    { key = "slot1Glow", type = "checkbox", x = 36, y = 35, w = 12, h = 3, label = L["发光"] },

    { key = "slot1EndMode", type = "dropdown", x = 23, y = 35, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot1TriggerSoundEnabled", type = "checkbox", x = 48, y = 35, w = 10, h = 3, label = L["触发"] },
    { key = "slot1TriggerSound", type = "lsm_sound", x = 58, y = 35, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot1ExpireSoundEnabled", type = "checkbox", x = 72, y = 35, w = 10, h = 3, label = L["结束"] },
    { key = "slot1ExpireSound", type = "lsm_sound", x = 82, y = 35, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot2", type = "dropdown", x = 2, y = 40, w = 20, h = 3, label = L["第二个图标"], items = {} },
    { key = "slot2Glow", type = "checkbox", x = 36, y = 40, w = 12, h = 3, label = L["发光"] },

    { key = "slot2EndMode", type = "dropdown", x = 23, y = 40, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot2TriggerSoundEnabled", type = "checkbox", x = 48, y = 40, w = 10, h = 3, label = L["触发"] },
    { key = "slot2TriggerSound", type = "lsm_sound", x = 58, y = 40, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot2ExpireSoundEnabled", type = "checkbox", x = 72, y = 40, w = 10, h = 3, label = L["结束"] },
    { key = "slot2ExpireSound", type = "lsm_sound", x = 82, y = 40, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot3", type = "dropdown", x = 2, y = 45, w = 20, h = 3, label = L["第三个图标"], items = {} },
    { key = "slot3Glow", type = "checkbox", x = 36, y = 45, w = 12, h = 3, label = L["发光"] },

    { key = "slot3EndMode", type = "dropdown", x = 23, y = 45, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot3TriggerSoundEnabled", type = "checkbox", x = 48, y = 45, w = 10, h = 3, label = L["触发"] },
    { key = "slot3TriggerSound", type = "lsm_sound", x = 58, y = 45, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot3ExpireSoundEnabled", type = "checkbox", x = 72, y = 45, w = 10, h = 3, label = L["结束"] },
    { key = "slot3ExpireSound", type = "lsm_sound", x = 82, y = 45, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot4", type = "dropdown", x = 2, y = 50, w = 20, h = 3, label = L["第四个图标"], items = {} },
    { key = "slot4Glow", type = "checkbox", x = 36, y = 50, w = 12, h = 3, label = L["发光"] },

    { key = "slot4EndMode", type = "dropdown", x = 23, y = 50, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot4TriggerSoundEnabled", type = "checkbox", x = 48, y = 50, w = 10, h = 3, label = L["触发"] },
    { key = "slot4TriggerSound", type = "lsm_sound", x = 58, y = 50, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot4ExpireSoundEnabled", type = "checkbox", x = 72, y = 50, w = 10, h = 3, label = L["结束"] },
    { key = "slot4ExpireSound", type = "lsm_sound", x = 82, y = 50, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot5", type = "dropdown", x = 2, y = 55, w = 20, h = 3, label = L["第五个图标"], items = {} },
    { key = "slot5Glow", type = "checkbox", x = 36, y = 55, w = 12, h = 3, label = L["发光"] },

    { key = "slot5EndMode", type = "dropdown", x = 23, y = 55, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot5TriggerSoundEnabled", type = "checkbox", x = 48, y = 55, w = 10, h = 3, label = L["触发"] },
    { key = "slot5TriggerSound", type = "lsm_sound", x = 58, y = 55, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot5ExpireSoundEnabled", type = "checkbox", x = 72, y = 55, w = 10, h = 3, label = L["结束"] },
    { key = "slot5ExpireSound", type = "lsm_sound", x = 82, y = 55, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot6", type = "dropdown", x = 2, y = 60, w = 20, h = 3, label = L["第六个图标"], items = {} },
    { key = "slot6Glow", type = "checkbox", x = 36, y = 60, w = 12, h = 3, label = L["发光"] },

    { key = "slot6EndMode", type = "dropdown", x = 23, y = 60, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot6TriggerSoundEnabled", type = "checkbox", x = 48, y = 60, w = 10, h = 3, label = L["触发"] },
    { key = "slot6TriggerSound", type = "lsm_sound", x = 58, y = 60, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot6ExpireSoundEnabled", type = "checkbox", x = 72, y = 60, w = 10, h = 3, label = L["结束"] },
    { key = "slot6ExpireSound", type = "lsm_sound", x = 82, y = 60, w = 17, h = 3, label = L["音效"], search = true },
    { key = "slot7", type = "dropdown", x = 2, y = 65, w = 20, h = 3, label = L["第七个图标"], items = {} },
    { key = "slot7Glow", type = "checkbox", x = 36, y = 65, w = 12, h = 3, label = L["发光"] },

    { key = "slot7EndMode", type = "dropdown", x = 23, y = 65, w = 12, h = 3, label = L["CD结束时"], items = { { L["隐藏"], "HIDE" }, { L["正常"], "NORMAL" }, { L["灰色"], "FADE" } } },
    { key = "slot7TriggerSoundEnabled", type = "checkbox", x = 48, y = 65, w = 10, h = 3, label = L["触发"] },
    { key = "slot7TriggerSound", type = "lsm_sound", x = 58, y = 65, w = 14, h = 3, label = L["音效"], search = true },
    { key = "slot7ExpireSoundEnabled", type = "checkbox", x = 72, y = 65, w = 10, h = 3, label = L["结束"] },
    { key = "slot7ExpireSound", type = "lsm_sound", x = 82, y = 65, w = 17, h = 3, label = L["音效"], search = true },
    { key = "anchorX", type = "slider", x = 2, y = 15, w = 20, h = 2, label = L["水平位置 (X)"], min = -2000, max = 2000 },
    { key = "anchorY", type = "slider", x = 23, y = 15, w = 20, h = 2, label = L["垂直位置 (Y)"], min = -1200, max = 1200 },
    { key = "icon", type = "icongroup", x = 2, y = 70, w = 70, h = 37, label = L["图标设置"], labelSize = 20 },
    { key = "font_count", type = "fontgroup", x = 2, y = 109, w = 70, h = 23, label = L["层数文字设置"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 2, y = 134, w = 70, h = 23, label = L["时间文本"], labelSize = 20 },
    { key = "glow", type = "glow_settings", x = 2, y = 159, w = 70, h = 22, label = L["发光设置"], labelSize = 20 },
    { key = "subheader_6792", type = "subheader", x = 2, y = 27, w = 95, h = 2, label = L["饰品顺序"], labelSize = 21 },
    { key = "divider_2447", type = "divider", x = 2, y = 29, w = 95, h = 2, label = L["新组件"] },
    { key = "attachToCustom", type = "checkbox", x = 2, y = 10, w = 10, h = 2, label = L["自由依附"] },
    { key = "customAttachTarget", type = "input", x = 13, y = 10, w = 24, h = 2, label = L["目标路径"] },
    { key = "btn_pick_frame", type = "button", x = 40, y = 10, w = 15, h = 3, label = L["鼠标选取"] },
}

local SPEC_BY_KEY = {}
local SPEC_BY_SPELL = {}
local SPEC_ORDER = {}

local function RegisterSpec(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return
    end
    SPEC_BY_KEY[spec.key] = spec
    SPEC_ORDER[#SPEC_ORDER + 1] = spec.key
    if type(spec.spellID) == "number" then
        SPEC_BY_SPELL[spec.spellID] = spec
    end
    if type(spec.spellMap) == "table" then
        for id in pairs(spec.spellMap) do
            if type(id) == "number" then
                SPEC_BY_SPELL[id] = spec
            end
        end
    end
end

RegisterSpec({
    key = "potion_1236616",
    spellMap = {
        [1236616] = { itemID = 241308 },
        [1236994] = { itemID = 241288 },
        [1236998] = { itemID = 241293 },
    },
    itemInfo = 241308,
    iconID = nil,
    duration = 30,
    cooldown = 300,
    mode = "active_cooldown",
    trigger = "spell_success",
})

RegisterSpec({
    key = "trinket_249343_a",
    spellID = 1266686,
    itemID = 249343,
    itemInfo = 249343,
    iconID = 7636702,
    duration = 12,
    mode = "extend",
    inheritCapRatio = 0.30,
    trigger = "cooldown_update",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_249343_b",
    spellID = 1266687,
    itemID = 249343,
    itemInfo = 249343,
    iconID = 2032577,
    duration = 12,
    mode = "stack_decay",
    trigger = "cooldown_update",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_249344",
    spellID = 1259633,
    itemID = 249344,
    itemInfo = 249344,
    iconID = 7636709,
    duration = 15,
    cooldown = 90,
    mode = "active_cooldown",
    trigger = "spell_success",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_249339",
    spellID = 1260633,
    itemID = 249339,
    itemInfo = 249339,
    iconID = 7636711,
    duration = 1,
    cooldown = 120,
    mode = "active_cooldown",
    trigger = "spell_success",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_249346",
    spellID = 1260459,
    itemID = 249346,
    itemInfo = 249346,
    iconID = 7636706,
    duration = 15,
    cooldown = 90,
    mode = "active_cooldown",
    trigger = "spell_success",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_193701",
    spellID = 383781,
    itemID = 193701,
    itemInfo = 193701,
    iconID = 133876,
    duration = 20,
    cooldown = 120,
    mode = "active_cooldown",
    trigger = "spell_success",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_2500256",
    spellID = 1263318,
    itemID = 250256,
    itemInfo = 250256,
    iconID = 4644003,
    duration = 10,
    mode = "refresh",
    trigger = "cooldown_update",
    requireEquipped = true,
})

RegisterSpec({
    key = "trinket_249808",
    spellID = 1258283,
    itemID = 249808,
    itemInfo = 249808,
    iconID = 7636705,
    duration = 30,
    cooldown = 90,
    mode = "active_cooldown",
    trigger = "spell_success",
    requireEquipped = true,
})
RegisterSpec({
    key = "trinket_1302265",
    displaySpellID = 1302265,
    spellMap = {
        [1287770] = {
            iconID = 236313,
        },
        [1287771] = {
            iconID = 464604,
        },
        [1287774] = {
            iconID = 135788,
        },
        [1287772] = {
            iconID = 1033914,
        },
    },
    duration = 10,
    mode = "stack_decay",
    trigger = "cooldown_update",
    requireEquipped = false,
})


local db
local anchorFrame
local anchorController
local contentFrame
local pool = {}
local activeRecords = {}
local activeOrder = {}
local stateByKey = {}
local soundStateBySlot = {}
local serial = 0
local updateFrame
local ScheduleCooldownRecalibration
local RefreshLayout
local HasPreviewStates
local editMode = false
local previewRunToken = 0
local LEGACY_SLOT_KEY_MAP = {
    alnsight = "trinket_249343_a",
    alnscorned_essence = "trinket_249343_b",
}

local function DeepApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            DeepApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function DB()
    if type(db) == "table" then
        return db
    end
    db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    DeepApplyDefaults(db, DEFAULTS)
    for i = 1, 7 do
        local slotKey = "slot" .. i
        local legacyValue = tostring(db[slotKey] or "")
        local migratedValue = LEGACY_SLOT_KEY_MAP[legacyValue]
        if migratedValue then
            db[slotKey] = migratedValue
        end
    end
    return db
end

local function GetGrowOriginPoint(growDir)
    local grow = tostring(growDir or DEFAULTS.growDir)
    if grow == "CENTER" then
        return "CENTER"
    end
    if grow == "LEFT" then
        return "TOPRIGHT"
    end
    if grow == "UP" then
        return "BOTTOMLEFT"
    end
    return "TOPLEFT"
end

local function EnsureAnchorController()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_StateIconsAnchor",
        frameTemplate = "BackdropTemplate",
        title = L["饰品监控"],
        getDB = DB,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = {
            "anchorX",
            "anchorY",
            "attachToCustom",
            "customAttachTarget",
        },
        widgetRanges = {
            anchorX = { min = -2000, max = 2000, step = 1 },
            anchorY = { min = -1200, max = 1200, step = 1 },
        },
        initialWidth = 220,
        initialHeight = 64,
        clampedToScreen = true,
        getAnchorPoint = function()
            return GetGrowOriginPoint(DB().growDir)
        end,
        getRelativePoint = function()
            return GetGrowOriginPoint(DB().growDir)
        end,
        onCreateFrame = function(_, frame)
            frame:Hide()
        end,
        onFramePicked = function()
            RefreshLayout()
        end,
        onFramePickCancelled = function()
            RefreshLayout()
        end,
        onEditModeChanged = function(_, active, visible)
            editMode = active == true and visible == true
            EnsureAnchor()
            RefreshLayout()
        end,
    })

    return anchorController
end

local function ClampInt(value, minValue, maxValue, defaultValue)
    local n = math.floor((tonumber(value) or tonumber(defaultValue) or minValue) + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

local function ResolveName(spec)
    if type(spec.name) == "string" and spec.name ~= "" then
        return spec.name
    end
    if spec.itemInfo and C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, itemName = pcall(C_Item.GetItemNameByID, spec.itemInfo)
        if ok and type(itemName) == "string" and itemName ~= "" then
            return itemName
        end
    end
    local displaySpellID = spec.displaySpellID or spec.spellID
    if displaySpellID and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(displaySpellID)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return tostring(displaySpellID or spec.key or "?")
end

local function ResolveIcon(spec)
    if spec.iconID then
        return spec.iconID
    end
    if spec.itemInfo and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, spec.itemInfo)
        if ok and icon then
            return icon
        end
    end
    local displaySpellID = spec.displaySpellID or spec.spellID
    if displaySpellID and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(displaySpellID)
        if type(info) == "table" and info.iconID then
            return info.iconID
        end
    end
    return 134400
end

local function GetItemCooldownSnapshot(itemID)
    if type(itemID) ~= "number" or not C_Item or type(C_Item.GetItemCooldown) ~= "function" then
        return 0, 0, false
    end
    local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, itemID)
    if not ok then
        return 0, 0, false
    end
    return tonumber(startTime) or 0, tonumber(duration) or 0, enabled == true
end

local function GetActiveItemCooldown(itemID)
    local startTime, duration, enabled = GetItemCooldownSnapshot(itemID)
    if enabled ~= true or startTime <= 0 or duration <= 1.5 then
        return nil, nil, nil
    end
    local expiresAt = startTime + duration
    if expiresAt <= GetTime() then
        return nil, nil, nil
    end
    return startTime, duration, expiresAt
end

local function ResolveInheritedCarry(state, spec, now)
    local remaining = math.max(0, (tonumber(state and state.expiresAt) or 0) - (tonumber(now) or 0))
    local cap = tonumber(spec and spec.inheritCapSeconds) or 0
    if cap <= 0 then
        local baseDuration = tonumber(spec and spec.duration) or 0
        local ratio = tonumber(spec and spec.inheritCapRatio) or 0
        if baseDuration > 0 and ratio > 0 then
            cap = baseDuration * ratio
        end
    end
    if cap <= 0 then
        return remaining
    end
    if remaining > cap then
        return cap
    end
    return remaining
end

local function SetClickThrough(frame)
    if not frame then return end
    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        pcall(frame.SetMouseClickEnabled, frame, false)
    end
    if frame.SetMouseMotionEnabled then
        pcall(frame.SetMouseMotionEnabled, frame, false)
    end
end

local function BuildSpecItems()
    local items = {
        { L["无"] or "无", "" },
    }
    for _, key in ipairs(SPEC_ORDER) do
        local spec = SPEC_BY_KEY[key]
        if spec then
            local label = tostring(ResolveName(spec))
            local icon = ResolveIcon(spec)
            if icon then
                label = string.format("|T%d:16:16:0:0|t %s", icon, label)
            end
            items[#items + 1] = { label, key }
        end
    end
    return items
end

local function PlayConfiguredSound(soundKey)
    local key = tostring(soundKey or "")
    if key == "" or not LSM or type(LSM.Fetch) ~= "function" or type(PlaySoundFile) ~= "function" then
        return false
    end
    local ok, soundPath = pcall(LSM.Fetch, LSM, "sound", key, true)
    if not ok or type(soundPath) ~= "string" or soundPath == "" then
        return false
    end
    local played = pcall(PlaySoundFile, soundPath, "Master")
    return played
end

local function PlaySlotSoundForState(stateKey, soundKind)
    local cfg = DB()
    for slotIndex = 1, 7 do
        if tostring(cfg["slot" .. slotIndex] or "") == tostring(stateKey or "") then
            local suffix = soundKind == "expire" and "ExpireSound" or "TriggerSound"
            local enabled = cfg["slot" .. slotIndex .. suffix .. "Enabled"] == true
            if enabled then
                PlayConfiguredSound(cfg["slot" .. slotIndex .. suffix])
            end
        end
    end
end

local function IsSpecAvailable(spec)
    if type(spec) ~= "table" then
        return false
    end
    if spec.requireEquipped == true and type(spec.itemID) == "number" then
        if C_Item and type(C_Item.IsEquippedItem) == "function" then
            local ok, equipped = pcall(C_Item.IsEquippedItem, spec.itemID)
            if ok then
                return equipped == true
            end
        end
        return false
    end
    return true
end

local function GetBorderTexture(name)
    if not name or name == "None" then
        return nil
    end
    if LSM and type(LSM.Fetch) == "function" then
        local ok, path = pcall(LSM.Fetch, LSM, "border", name, true)
        if ok and path then
            return path
        end
    end
    return name
end

local function GetGlowLib()
    if LibStub then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibCustomGlow-1.0", true)
        if ok then
            return lib
        end
    end
    return nil
end

local function BuildGlowOptions(cfg)
    return {
        enabled = cfg.glowEnabled == true,
        style = tostring(cfg.glowStyle or "Pixel Glow"),
        color = {
            tonumber(cfg.glowColorR) or 1,
            tonumber(cfg.glowColorG) or 0.86,
            tonumber(cfg.glowColorB) or 0.10,
            tonumber(cfg.glowColorA) or 1,
        },
        frequency = tonumber(cfg.glowFrequency) or 0.25,
        lines = math.max(1, math.floor(tonumber(cfg.glowLines) or 8)),
        scale = tonumber(cfg.glowScale) or 1,
        offset = tonumber(cfg.glowOffset) or 0,
    }
end

local function BuildGlowSignature(opts)
    if type(opts) ~= "table" then
        return "noglow"
    end
    local color = opts.color or {}
    return table.concat({
        tostring(opts.enabled == true),
        tostring(opts.style or ""),
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or ""),
        tostring(opts.frequency or ""),
        tostring(opts.lines or ""),
        tostring(opts.scale or ""),
        tostring(opts.offset or ""),
    }, "|")
end

local function StartWidgetGlow(target, key, opts)
    if not target or type(opts) ~= "table" or opts.enabled == false then
        return nil
    end
    local lib = GetGlowLib()
    if not lib then
        return nil
    end
    local style = tostring(opts.style or "Pixel Glow")
    local color = opts.color or { 1, 0.86, 0.10, 1 }
    local lines = math.max(1, math.floor(tonumber(opts.lines) or 8))
    local frequency = tonumber(opts.frequency) or 0.25
    local scale = tonumber(opts.scale) or 1
    local offset = tonumber(opts.offset) or 0
    if style == "Action Button Glow" and type(lib.ButtonGlow_Start) == "function" then
        lib.ButtonGlow_Start(target, color, frequency, 20)
        return "lib_action"
    elseif style == "Autocast Shine" and type(lib.AutoCastGlow_Start) == "function" then
        lib.AutoCastGlow_Start(target, color, lines, frequency, scale, offset, offset, key, 20)
        return "lib_autocast"
    elseif style == "Proc Glow" and type(lib.ProcGlow_Start) == "function" then
        lib.ProcGlow_Start(target,
            { key = key, color = color, frameLevel = 20, xOffset = offset, yOffset = offset, duration = 1 })
        return "lib_proc"
    elseif type(lib.PixelGlow_Start) == "function" then
        lib.PixelGlow_Start(target, color, lines, frequency, nil, scale, offset, offset, false, key, 20)
        return "lib_pixel"
    end
    return nil
end

local function StopWidgetGlow(target, key, mode)
    if not target then
        return
    end
    local lib = GetGlowLib()
    if mode == "lib_pixel" and lib and type(lib.PixelGlow_Stop) == "function" then
        lib.PixelGlow_Stop(target, key)
    elseif mode == "lib_autocast" and lib and type(lib.AutoCastGlow_Stop) == "function" then
        lib.AutoCastGlow_Stop(target, key)
    elseif mode == "lib_proc" and lib and type(lib.ProcGlow_Stop) == "function" then
        lib.ProcGlow_Stop(target, key)
    elseif mode == "lib_action" and lib and type(lib.ButtonGlow_Stop) == "function" then
        lib.ButtonGlow_Stop(target)
    end
end

local function ApplyAnchorPosition()
    EnsureAnchorController():ApplyPosition()
end

local function EnsureAnchor()
    if anchorFrame then
        if not anchorFrame.isMoving then
            ApplyAnchorPosition()
        end
        return anchorFrame
    end

    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    anchorFrame:SetBackdropColor(0, 0, 0, 0)
    anchorFrame:SetBackdropBorderColor(0, 0, 0, 0)

    contentFrame = CreateFrame("Frame", nil, anchorFrame)
    contentFrame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    contentFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    SetClickThrough(contentFrame)

    ApplyAnchorPosition()
    return anchorFrame
end

local function AcquireRecord()
    local record = table.remove(pool)
    if record then
        return record
    end

    local holder = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
    holder:SetSize(48, 48)
    holder:SetBackdrop({
        bgFile = nil,
        edgeFile = nil,
        edgeSize = 1,
    })
    SetClickThrough(holder)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(holder)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local borderFrame = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    borderFrame:SetFrameLevel(holder:GetFrameLevel() + 5)
    SetClickThrough(borderFrame)

    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder)
    cooldown:SetReverse(false)
    cooldown:SetHideCountdownNumbers(true)
    SetClickThrough(cooldown)
    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(true)
    end
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(true)
    end

    local textFrame = CreateFrame("Frame", nil, holder)
    textFrame:SetAllPoints(holder)
    textFrame:SetFrameLevel(holder:GetFrameLevel() + 40)
    SetClickThrough(textFrame)

    local countText = textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    countText:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -3, 2)
    countText:SetJustifyH("RIGHT")
    countText:SetDrawLayer("OVERLAY", 30)

    local timeText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    timeText:SetPoint("CENTER", holder, "CENTER", 0, 0)
    timeText:SetJustifyH("CENTER")

    local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("TOP", holder, "BOTTOM", 0, -2)
    nameText:SetWidth(120)
    nameText:SetJustifyH("CENTER")

    return {
        frame = holder,
        icon = icon,
        borderFrame = borderFrame,
        cooldown = cooldown,
        textFrame = textFrame,
        countText = countText,
        timeText = timeText,
        nameText = nameText,
        stateKey = nil,
        glowMode = nil,
        glowKey = nil,
        glowSignature = nil,
    }
end

local function ReleaseRecord(record)
    if not record then
        return
    end
    record.stateKey = nil
    record.frame:Hide()
    record.frame:ClearAllPoints()
    record.countText:SetText("")
    record.timeText:SetText("")
    record.nameText:SetText("")
    record.icon:SetDesaturated(false)
    if record.glowMode then
        StopWidgetGlow(record.frame, record.glowKey or record.stateKey or "", record.glowMode)
        record.glowMode = nil
        record.glowKey = nil
    end
    record.glowSignature = nil
    pool[#pool + 1] = record
end

local function SortStates(a, b)
    local sa = stateByKey[a]
    local sb = stateByKey[b]
    if not sa and not sb then return a < b end
    if not sa then return false end
    if not sb then return true end
    if (sa.expiresAt or 0) == (sb.expiresAt or 0) then
        return (sa.serial or 0) < (sb.serial or 0)
    end
    return (sa.expiresAt or 0) > (sb.expiresAt or 0)
end

local function FormatRemaining(seconds)
    local s = tonumber(seconds) or 0
    if s <= 0 then
        return ""
    end
    if s >= 60 then
        local totalSeconds = math.ceil(s)
        local minutes = math.floor(totalSeconds / 60)
        local remainingSeconds = totalSeconds % 60
        return string.format("%d:%02d", minutes, remainingSeconds)
    end
    if s >= 10 then
        return tostring(math.ceil(s))
    end
    return string.format("%.1f", s)
end

local function ResolveFontColor(cfg, defaultCfg, fallbackR, fallbackG, fallbackB, fallbackA)
    local color = type(cfg and cfg.color) == "table" and cfg.color or
        type(defaultCfg and defaultCfg.color) == "table" and defaultCfg.color or nil
    local r = tonumber(cfg and cfg.r) or tonumber(color and color[1]) or tonumber(defaultCfg and defaultCfg.r) or
        tonumber(color and color[1]) or fallbackR
    local g = tonumber(cfg and cfg.g) or tonumber(color and color[2]) or tonumber(defaultCfg and defaultCfg.g) or
        tonumber(color and color[2]) or fallbackG
    local b = tonumber(cfg and cfg.b) or tonumber(color and color[3]) or tonumber(defaultCfg and defaultCfg.b) or
        tonumber(color and color[3]) or fallbackB
    local a = tonumber(cfg and cfg.a) or tonumber(color and color[4]) or tonumber(defaultCfg and defaultCfg.a) or
        tonumber(color and color[4]) or fallbackA
    return r, g, b, a
end

local function ApplyCountFont(record, fontCfg)
    if not record or not record.countText then
        return
    end
    local cfg = type(fontCfg) == "table" and fontCfg or DEFAULTS.font_count
    local fontKey = cfg.font
    local fontPath = (fontKey and LSM and LSM.Fetch and LSM:Fetch("font", fontKey, true)) or
        STANDARD_TEXT_FONT
    local size = math.max(6, tonumber(cfg.size) or tonumber(DEFAULTS.font_count.size) or 20)
    local outline = tostring(cfg.outline or DEFAULTS.font_count.outline or "")
    if outline == "NONE" then
        outline = ""
    end
    record.countText:SetFont(fontPath, size, outline)
    local r, g, b, a = ResolveFontColor(cfg, DEFAULTS.font_count, 1, 0.82, 0, 1)
    record.countText:SetTextColor(
        r,
        g,
        b,
        a
    )
    if cfg.shadow == true then
        record.countText:SetShadowColor(0, 0, 0, 1)
        record.countText:SetShadowOffset(tonumber(cfg.shadowX) or 1, tonumber(cfg.shadowY) or -1)
    else
        record.countText:SetShadowColor(0, 0, 0, 0)
        record.countText:SetShadowOffset(0, 0)
    end
    record.countText:ClearAllPoints()
    record.countText:SetPoint(
        "CENTER",
        record.frame,
        "CENTER",
        tonumber(cfg.x) or tonumber(DEFAULTS.font_count.x) or 0,
        tonumber(cfg.y) or tonumber(DEFAULTS.font_count.y) or 0
    )
end

local function ApplyTimeFont(record, fontCfg)
    if not record or not record.timeText then
        return
    end
    local cfg = type(fontCfg) == "table" and fontCfg or DEFAULTS.font_time
    local fontKey = cfg.font
    local fontPath = (fontKey and LSM and LSM.Fetch and LSM:Fetch("font", fontKey, true)) or
        STANDARD_TEXT_FONT
    local size = math.max(6, tonumber(cfg.size) or tonumber(DEFAULTS.font_time.size) or 18)
    local outline = tostring(cfg.outline or DEFAULTS.font_time.outline or "")
    if outline == "NONE" then
        outline = ""
    end
    record.timeText:SetFont(fontPath, size, outline)
    local r, g, b, a = ResolveFontColor(cfg, DEFAULTS.font_time, 1, 1, 1, 1)
    record.timeText:SetTextColor(
        r,
        g,
        b,
        a
    )
    if cfg.shadow == true then
        record.timeText:SetShadowColor(0, 0, 0, 1)
        record.timeText:SetShadowOffset(tonumber(cfg.shadowX) or 1, tonumber(cfg.shadowY) or -1)
    else
        record.timeText:SetShadowColor(0, 0, 0, 0)
        record.timeText:SetShadowOffset(0, 0)
    end
    record.timeText:ClearAllPoints()
    record.timeText:SetPoint(
        "CENTER",
        record.frame,
        "CENTER",
        tonumber(cfg.x) or tonumber(DEFAULTS.font_time.x) or 0,
        tonumber(cfg.y) or tonumber(DEFAULTS.font_time.y) or 0
    )
end

local function PruneState(state)
    if not state then
        return false
    end
    local now = GetTime()
    if state.mode == "stack_decay" and type(state.stackExpiries) == "table" then
        if state.previewStatic == true then
            return true
        end
        local kept = {}
        for _, expiry in ipairs(state.stackExpiries) do
            if expiry > now then
                kept[#kept + 1] = expiry
            end
        end
        state.stackExpiries = kept
        state.stacks = #kept
        local maxExpiry = 0
        for _, expiry in ipairs(kept) do
            if expiry > maxExpiry then
                maxExpiry = expiry
            end
        end
        state.expiresAt = maxExpiry
        if state.stacks <= 0 then
            state.active = false
            state.expiresAt = 0
        end
    elseif state.mode == "active_cooldown" then
        if state.previewStatic == true then
            return true
        end
        if (state.activeExpiresAt or 0) > now then
            state.phase = "active"
            state.startedAt = tonumber(state.activeStartedAt) or state.startedAt or now
            state.displayDuration = tonumber(state.activeDuration) or tonumber(state.displayDuration) or 0
            state.expiresAt = state.activeExpiresAt
            state.active = true
            return true
        end
        if (state.cooldownExpiresAt or 0) > now then
            state.phase = "cooldown"
            state.startedAt = tonumber(state.cooldownStartedAt) or state.startedAt or now
            state.displayDuration = tonumber(state.cooldownDuration) or tonumber(state.displayDuration) or 0
            state.expiresAt = state.cooldownExpiresAt
            state.active = true
            return true
        end
        state.active = false
        state.expiresAt = 0
        state.phase = nil
    elseif state.mode == "cooldown_only" then
        if state.previewStatic == true then
            return true
        end
        if (state.cooldownExpiresAt or state.expiresAt or 0) > now then
            state.phase = "cooldown"
            state.startedAt = tonumber(state.cooldownStartedAt) or state.startedAt or now
            state.displayDuration = tonumber(state.cooldownDuration) or tonumber(state.displayDuration) or 0
            state.expiresAt = state.cooldownExpiresAt or state.expiresAt
            state.active = true
            return true
        end
        state.active = false
        state.expiresAt = 0
        state.phase = nil
    else
        if state.previewStatic == true then
            return true
        end
        if (state.expiresAt or 0) <= now then
            state.active = false
            state.expiresAt = 0
        end
    end
    return state.active == true
end

local function ApplyCooldownCalibration(state, spec, preserveActiveWindow)
    if type(state) ~= "table" or type(spec) ~= "table" or type(spec.itemID) ~= "number" then
        return false
    end

    local startTime, duration, expiresAt = GetActiveItemCooldown(spec.itemID)
    if not startTime then
        state.cooldownStartedAt = nil
        state.cooldownDuration = nil
        state.cooldownExpiresAt = 0
        if state.phase == "cooldown" then
            state.phase = nil
            state.active = false
            state.startedAt = 0
            state.displayDuration = tonumber(spec.duration) or 0
            state.expiresAt = 0
        end
        return false
    end

    state.cooldownStartedAt = startTime
    state.cooldownDuration = duration
    state.cooldownExpiresAt = expiresAt

    if preserveActiveWindow == true and state.mode == "active_cooldown" and (state.activeExpiresAt or 0) > GetTime() then
        return true
    end

    if state.mode == "active_cooldown" or state.mode == "cooldown_only" then
        state.phase = "cooldown"
        state.active = true
        state.startedAt = startTime
        state.displayDuration = duration
        state.expiresAt = expiresAt
        state.stacks = 0
    end

    return true
end

local function RecalibrateCooldownStatesFromItemAPI()
    local cfg = DB()
    if cfg.enabled ~= true then
        return
    end

    for _, key in ipairs(SPEC_ORDER) do
        local spec = SPEC_BY_KEY[key]
        if spec and type(spec.itemID) == "number" and (spec.mode == "active_cooldown" or spec.mode == "cooldown_only") then
            local state = stateByKey[key]
            if state then
                ApplyCooldownCalibration(state, spec, false)
            else
                local startTime, duration, expiresAt = GetActiveItemCooldown(spec.itemID)
                if startTime and expiresAt then
                    serial = serial + 1
                    stateByKey[key] = {
                        key = spec.key,
                        spec = spec,
                        name = ResolveName(spec),
                        icon = ResolveIcon(spec),
                        serial = serial,
                        mode = spec.mode,
                        active = true,
                        phase = "cooldown",
                        stacks = 0,
                        stackExpiries = {},
                        displayDuration = duration,
                        startedAt = startTime,
                        expiresAt = expiresAt,
                        cooldownStartedAt = startTime,
                        cooldownDuration = duration,
                        cooldownExpiresAt = expiresAt,
                    }
                end
            end
        end
    end
end

local function PurgeUnequippedSpecStates()
    local removed = false
    for key, state in pairs(stateByKey) do
        local spec = (type(state) == "table" and state.spec) or SPEC_BY_KEY[key]
        if spec and spec.requireEquipped == true and type(state) == "table" then
            if state.previewToken == nil and state.previewStatic ~= true and not IsSpecAvailable(spec) then
                stateByKey[key] = nil
                removed = true
            end
        end
    end
    return removed
end

local function RecheckEquippedTrinkets()
    PurgeUnequippedSpecStates()
    RecalibrateCooldownStatesFromItemAPI()
    EnsureAnchor()
    RefreshLayout()
end

local cooldownCalibrationNonce = 0
ScheduleCooldownRecalibration = function(delaySeconds)
    local delay = tonumber(delaySeconds) or 1
    if delay < 0 then
        delay = 0
    end
    cooldownCalibrationNonce = cooldownCalibrationNonce + 1
    local nonce = cooldownCalibrationNonce
    C_Timer.After(delay, function()
        if nonce ~= cooldownCalibrationNonce then
            return
        end
        RecalibrateCooldownStatesFromItemAPI()
        EnsureAnchor()
        RefreshLayout()
    end)
end

RefreshLayout = function()
    local cfg = DB()
    EnsureAnchor()

    if cfg.enabled ~= true and editMode ~= true and not HasPreviewStates() then
        wipe(activeOrder)
        wipe(soundStateBySlot)
        for key, record in pairs(activeRecords) do
            activeRecords[key] = nil
            ReleaseRecord(record)
        end
        anchorFrame:Hide()
        anchorFrame:SetBackdropColor(0, 0, 0, 0)
        return
    end

    wipe(activeOrder)
    local activeByKey = {}
    for key, state in pairs(stateByKey) do
        local isActive = PruneState(state)
        activeByKey[key] = isActive == true
        if isActive then
            activeOrder[#activeOrder + 1] = key
        end
    end
    local used = {}
    local slotDefs = {
        { stateKey = tostring(cfg.slot1 or ""), glow = cfg.slot1Glow == true, endMode = tostring(cfg.slot1EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot2 or ""), glow = cfg.slot2Glow == true, endMode = tostring(cfg.slot2EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot3 or ""), glow = cfg.slot3Glow == true, endMode = tostring(cfg.slot3EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot4 or ""), glow = cfg.slot4Glow == true, endMode = tostring(cfg.slot4EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot5 or ""), glow = cfg.slot5Glow == true, endMode = tostring(cfg.slot5EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot6 or ""), glow = cfg.slot6Glow == true, endMode = tostring(cfg.slot6EndMode or "HIDE") },
        { stateKey = tostring(cfg.slot7 or ""), glow = cfg.slot7Glow == true, endMode = tostring(cfg.slot7EndMode or "HIDE") },
    }

    for slotIndex, slot in ipairs(slotDefs) do
        local stateKey = slot.stateKey
        local isActive = stateKey ~= "" and activeByKey[stateKey] == true
        local previous = soundStateBySlot[slotIndex]
        if previous and previous.key == stateKey and previous.active == true and not isActive then
            PlaySlotSoundForState(stateKey, "expire")
        end
        soundStateBySlot[slotIndex] = {
            key = stateKey,
            active = isActive,
        }
    end

    local iconCfg = type(cfg.icon) == "table" and cfg.icon or DEFAULTS.icon
    local countFontCfg = type(cfg.font_count) == "table" and cfg.font_count or DEFAULTS.font_count
    local timeFontCfg = type(cfg.font_time) == "table" and cfg.font_time or DEFAULTS.font_time
    local width = ClampInt(iconCfg.width, 24, 300, DEFAULTS.icon.width)
    local height = ClampInt(iconCfg.height, 24, 300, DEFAULTS.icon.height)
    local iconOffsetX = tonumber(iconCfg.x) or 0
    local iconOffsetY = tonumber(iconCfg.y) or 0
    local borderTexture = GetBorderTexture(iconCfg.borderTexture)
    local borderSize = math.max(1, tonumber(iconCfg.borderSize) or 1)
    local borderPadding = tonumber(iconCfg.borderPadding) or 0
    local borderR = tonumber(iconCfg.borderColorR)
    local borderG = tonumber(iconCfg.borderColorG)
    local borderB = tonumber(iconCfg.borderColorB)
    local borderA = tonumber(iconCfg.borderColorA)
    local borderEnabled = iconCfg.showBorder == true and borderTexture ~= nil
    local frameWidth = width
    local frameHeight = height
    local spacing = tonumber(cfg.spacing) or DEFAULTS.spacing
    local grow = tostring(cfg.growDir or DEFAULTS.growDir)
    local glowOpts = BuildGlowOptions(cfg)
    local maxWidth, maxHeight = frameWidth, frameHeight
    local shown = 0

    local visibleSlots = {}
    for _, slot in ipairs(slotDefs) do
        if slot.stateKey ~= "" then
            local spec = SPEC_BY_KEY[slot.stateKey]
            local hasState = type(stateByKey[slot.stateKey]) == "table"
            local isAvailable = IsSpecAvailable(spec)
            if spec and (isAvailable or (hasState and spec.requireEquipped ~= true)) then
                visibleSlots[#visibleSlots + 1] = slot
            end
        end
    end

    for index = 1, #visibleSlots do
        local slot = visibleSlots[index]
        local stateKey = slot.stateKey
        if stateKey ~= "" then
            local state = stateByKey[stateKey]
            if not state then
                local spec = SPEC_BY_KEY[stateKey]
                if spec then
                    state = {
                        key = spec.key,
                        spec = spec,
                        name = ResolveName(spec),
                        icon = ResolveIcon(spec),
                        serial = 0,
                        mode = spec.mode,
                        active = false,
                        stacks = 0,
                        stackExpiries = {},
                        displayDuration = tonumber(spec.duration) or 0,
                        startedAt = 0,
                        expiresAt = 0,
                    }
                end
            end
            local endMode = tostring(slot.endMode or "HIDE")
            if state and (state.active == true or endMode ~= "HIDE") then
                shown = shown + 1
                local record = activeRecords[state.key]
                if not record then
                    record = AcquireRecord()
                    activeRecords[state.key] = record
                end
                used[state.key] = true
                record.stateKey = state.key

                record.frame:SetSize(frameWidth, frameHeight)
                record.icon:ClearAllPoints()
                record.icon:SetPoint("CENTER", record.frame, "CENTER", iconOffsetX, iconOffsetY)
                record.icon:SetSize(width, height)
                record.icon:SetTexture(state.icon or ResolveIcon(state.spec) or iconCfg.iconID or 134400)
                record.icon:SetDesaturated(false)
                record.icon:SetShown(iconCfg.showIcon ~= false or editMode == true)
                if record.frame._backdropInitialized ~= true then
                    SafeSetBackdrop(record.frame, {
                        bgFile = nil,
                        edgeFile = nil,
                        edgeSize = 1,
                    })
                    record.frame._backdropInitialized = true
                end
                record.borderFrame:ClearAllPoints()
                record.borderFrame:SetPoint("TOPLEFT", record.icon, "TOPLEFT", -borderPadding, borderPadding)
                record.borderFrame:SetPoint("BOTTOMRIGHT", record.icon, "BOTTOMRIGHT", borderPadding, -borderPadding)
                local borderApplied = false
                if borderEnabled then
                    borderApplied = SafeSetBackdrop(record.borderFrame, {
                        edgeFile = borderTexture,
                        edgeSize = borderSize,
                    })
                end
                if borderEnabled and borderApplied then
                    record.borderFrame:SetBackdropBorderColor(
                        borderR or 0,
                        borderG or 0,
                        borderB or 0,
                        borderA or 1
                    )
                    record.borderFrame:Show()
                else
                    record.borderFrame:Hide()
                end
                ApplyCountFont(record, countFontCfg)
                ApplyTimeFont(record, timeFontCfg)
                record.frame:Show()

                local remaining = state.previewStatic == true
                    and math.max(0, tonumber(state.previewRemaining) or 0)
                    or math.max(0, (state.expiresAt or 0) - GetTime())
                if record.cooldown.SetCooldown then
                    local duration = math.max(0, tonumber(state.displayDuration) or tonumber(state.spec.duration) or 0)
                    if state.previewStatic == true then
                        if _G.CooldownFrame_Clear then
                            _G.CooldownFrame_Clear(record.cooldown)
                        else
                            record.cooldown:SetCooldown(0, 0)
                        end
                        record.cooldown:Hide()
                    elseif state.active == true and duration > 0 and remaining > 0 then
                        local startedAt = tonumber(state.startedAt) or ((state.expiresAt or 0) - duration)
                        record.cooldown:SetReverse(iconCfg.reverse == true)
                        record.cooldown:SetCooldown(startedAt, duration)
                        record.cooldown:Show()
                    else
                        if _G.CooldownFrame_Clear then
                            _G.CooldownFrame_Clear(record.cooldown)
                        else
                            record.cooldown:SetCooldown(0, 0)
                        end
                        record.cooldown:Hide()
                    end
                end
                local inactive = state.active ~= true
                record.icon:SetDesaturated(state.phase == "cooldown" or (inactive and endMode == "FADE"))
                record.frame:SetAlpha(1)
                record.countText:SetText((state.active == true and (state.stacks or 0) > 0) and tostring(state.stacks) or
                    "")
                local showTimerText = cfg.hideTimeText ~= true
                record.timeText:SetText((state.active == true and showTimerText) and FormatRemaining(remaining) or "")
                record.nameText:SetShown(state.active == true and cfg.showName == true)
                record.nameText:SetText((state.active == true and cfg.showName == true) and
                    tostring(state.name or ResolveName(state.spec)) or "")
                local shouldGlow = false
                if state.previewToken ~= nil then
                    shouldGlow = index == 1
                else
                    shouldGlow = state.active == true and slot.glow == true and state.phase ~= "cooldown"
                end
                if shouldGlow then
                    local glowKey = "stateicons:" .. tostring(state.key)
                    local glowSignature = BuildGlowSignature(glowOpts)
                    if record.glowMode == nil or record.glowKey ~= glowKey or record.glowSignature ~= glowSignature then
                        if record.glowMode then
                            StopWidgetGlow(record.frame, record.glowKey or "", record.glowMode)
                        end
                        record.glowMode = StartWidgetGlow(record.frame, glowKey, glowOpts)
                        record.glowKey = glowKey
                        record.glowSignature = glowSignature
                    end
                elseif record.glowMode then
                    StopWidgetGlow(record.frame, record.glowKey or "", record.glowMode)
                    record.glowMode = nil
                    record.glowKey = nil
                    record.glowSignature = nil
                end

                record.frame:ClearAllPoints()
                local offset = index - 1
                if grow == "CENTER" then
                    if offset == 0 then
                        record.frame:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
                    else
                        local sideIndex = math.floor((offset + 1) / 2)
                        local direction = (offset % 2 == 1) and 1 or -1
                        record.frame:SetPoint("CENTER", contentFrame, "CENTER",
                            direction * sideIndex * (frameWidth + spacing), 0)
                    end
                elseif grow == "LEFT" then
                    record.frame:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -((frameWidth + spacing) * offset), 0)
                elseif grow == "UP" then
                    record.frame:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 0, (frameHeight + spacing) * offset)
                elseif grow == "DOWN" then
                    record.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -((frameHeight + spacing) * offset))
                else
                    record.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", (frameWidth + spacing) * offset, 0)
                end

                if grow == "LEFT" or grow == "RIGHT" or grow == "CENTER" then
                    maxWidth = frameWidth + (index - 1) * (frameWidth + spacing)
                    maxHeight = math.max(maxHeight, frameHeight + (cfg.showName == true and 16 or 0))
                else
                    maxHeight = frameHeight + (index - 1) * (frameHeight + spacing) + (cfg.showName == true and 16 or 0)
                    maxWidth = math.max(maxWidth, frameWidth)
                end
            end
        end
    end

    for key, record in pairs(activeRecords) do
        if not used[key] then
            activeRecords[key] = nil
            ReleaseRecord(record)
        end
    end

    anchorFrame:SetSize(math.max(width, maxWidth), math.max(height, maxHeight))
    if shown > 0 or editMode == true then
        anchorFrame:Show()
    elseif cfg.enabled == true then
        anchorFrame:Hide()
    end

    anchorFrame:SetBackdropColor(0, 0, 0, 0)
end

local function ClearAllStates()
    wipe(stateByKey)
    wipe(soundStateBySlot)
    RefreshLayout()
end

HasPreviewStates = function()
    for _, state in pairs(stateByKey) do
        if type(state) == "table" and state.previewToken ~= nil then
            return true
        end
    end
    return false
end

local function ClearPreviewStates(token)
    local removed = false
    for key, state in pairs(stateByKey) do
        if type(state) == "table" and state.previewToken == token then
            stateByKey[key] = nil
            removed = true
        end
    end
    if removed then
        RefreshLayout()
    end
end

local function HasLiveDynamicStates()
    local now = GetTime()
    for _, state in pairs(stateByKey) do
        if type(state) == "table" then
            if state.previewToken ~= nil or state.previewStatic == true then
                return true
            end
            if state.active == true then
                if (tonumber(state.expiresAt) or 0) > now then
                    return true
                end
                if state.mode == "stack_decay" and type(state.stackExpiries) == "table" and #state.stackExpiries > 0 then
                    return true
                end
            end
        end
    end
    return false
end

local function EnsureUpdateLoop()
    if updateFrame then
        return
    end
    updateFrame = CreateFrame("Frame")
    local elapsedSince = 0
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSince = elapsedSince + (elapsed or 0)
        if elapsedSince < 0.05 then
            return
        end
        elapsedSince = 0
        if editMode == true or HasLiveDynamicStates() then
            RefreshLayout()
        end
    end)
end

local function ResolveIconForTrigger(spec, triggerSpellID)
    if triggerSpellID and type(spec.spellMap) == "table" then
        local entry = spec.spellMap[triggerSpellID]
        if entry then
            if entry.iconID then
                return entry.iconID
            elseif entry.itemID and C_Item and type(C_Item.GetItemIconByID) == "function" then
                local ok, icon = pcall(C_Item.GetItemIconByID, entry.itemID)
                if ok and icon then return icon end
            end
        end
    end
    return ResolveIcon(spec)
end

local function TriggerSpec(spec, force, triggerSpellID)
    if type(spec) ~= "table" then
        return
    end
    local cfg = DB()
    if cfg.enabled ~= true and force ~= true then
        return
    end
    EnsureAnchor()
    EnsureUpdateLoop()

    local now = GetTime()
    local state = stateByKey[spec.key]
    if type(state) ~= "table" then
        serial = serial + 1
        state = {
            key = spec.key,
            spec = spec,
            name = ResolveName(spec),
            icon = ResolveIconForTrigger(spec, triggerSpellID),
            serial = serial,
            mode = spec.mode,
            active = false,
            stacks = 0,
            stackExpiries = {},
            displayDuration = tonumber(spec.duration) or 0,
            startedAt = 0,
            expiresAt = 0,
        }
        stateByKey[spec.key] = state
    end

    local duration = tonumber(spec.duration) or 0
    local cooldown = tonumber(spec.cooldown) or 0
    if force ~= true then
        state.previewToken = nil
    end
    state.active = true
    state.displayDuration = duration
    state.name = ResolveName(spec)
    state.icon = ResolveIconForTrigger(spec, triggerSpellID)
    state.phase = nil

    if spec.mode == "stack_decay" then
        PruneState(state)
        state.stackExpiries = state.stackExpiries or {}
        state.stackExpiries[#state.stackExpiries + 1] = now + duration
        state.stacks = #state.stackExpiries
        state.active = true
        state.startedAt = now
        state.displayDuration = duration
        state.expiresAt = now + duration
        if C_Timer then
            C_Timer.After(duration, function()
                local current = stateByKey[spec.key]
                if not current then
                    return
                end
                PruneState(current)
                RefreshLayout()
            end)
        end
    elseif spec.mode == "refresh" then
        state.startedAt = now
        state.displayDuration = duration
        state.expiresAt = now + duration
        state.stacks = 0
    elseif spec.mode == "active_cooldown" then
        state.phase = "active"
        state.activeStartedAt = now
        state.activeDuration = duration
        state.activeExpiresAt = now + duration
        state.cooldownStartedAt = now
        state.cooldownDuration = cooldown
        state.cooldownExpiresAt = now + cooldown
        state.startedAt = now
        state.displayDuration = duration
        state.expiresAt = now + duration
        state.stacks = 0
    elseif spec.mode == "cooldown_only" then
        state.phase = "cooldown"
        state.cooldownStartedAt = now
        state.cooldownDuration = cooldown
        state.cooldownExpiresAt = now + cooldown
        state.startedAt = now
        state.displayDuration = cooldown
        state.expiresAt = now + cooldown
        state.stacks = 0
    else
        local carry = 0
        if (state.expiresAt or 0) > now then
            carry = ResolveInheritedCarry(state, spec, now)
        end
        state.startedAt = now
        state.displayDuration = duration + carry
        state.expiresAt = now + duration + carry
        state.stacks = 0
    end

    if type(spec.itemID) == "number" then
        ApplyCooldownCalibration(state, spec, true)
        if spec.mode == "active_cooldown" or spec.mode == "cooldown_only" then
            ScheduleCooldownRecalibration(1)
        end
    end

    PlaySlotSoundForState(spec.key, "trigger")
    RefreshLayout()
end

local function ResetSpecCooldown(state)
    if type(state) ~= "table" then
        return
    end

    state.cooldownStartedAt = nil
    state.cooldownDuration = nil
    state.cooldownExpiresAt = 0

    if state.phase == "cooldown" then
        state.phase = nil
        state.active = false
        state.startedAt = 0
        state.displayDuration = tonumber(state.spec and state.spec.duration) or 0
        state.expiresAt = 0
    end
end

function ExBoss.Tools.StateIcons:RegisterSpec(spec)
    RegisterSpec(spec)
end

function ExBoss.Tools.StateIcons:Trigger(keyOrSpellID)
    local spec = nil
    if type(keyOrSpellID) == "number" then
        spec = SPEC_BY_SPELL[keyOrSpellID]
    elseif type(keyOrSpellID) == "string" and keyOrSpellID ~= "" then
        spec = SPEC_BY_KEY[keyOrSpellID]
    end
    if not spec then
        return false
    end
    TriggerSpec(spec, false)
    return true
end

local function Preview(durationSeconds)
    ClearAllStates()
    previewRunToken = previewRunToken + 1
    local token = previewRunToken
    local now = GetTime()
    local duration = math.max(1, tonumber(durationSeconds) or 10)
    local cfg = DB()

    for slotIndex = 1, 7 do
        local slotKey = tostring(cfg["slot" .. slotIndex] or "")
        local spec = SPEC_BY_KEY[slotKey]
        if spec then
            serial = serial + 1
            local state = {
                key = spec.key,
                spec = spec,
                name = ResolveName(spec),
                icon = ResolveIcon(spec),
                serial = serial,
                mode = spec.mode,
                active = true,
                stacks = 0,
                stackExpiries = {},
                displayDuration = duration,
                startedAt = now,
                expiresAt = now + duration,
                previewToken = token,
            }

            if spec.mode == "stack_decay" then
                local stackCount = math.max(3, math.min(15, slotIndex + 2))
                for i = 1, stackCount do
                    state.stackExpiries[i] = now + duration
                end
                state.stacks = stackCount
            elseif spec.mode == "active_cooldown" then
                state.phase = "active"
                state.activeStartedAt = now
                state.activeDuration = duration
                state.activeExpiresAt = now + duration
                state.cooldownStartedAt = now
                state.cooldownDuration = duration
                state.cooldownExpiresAt = now + duration
            elseif spec.mode == "cooldown_only" then
                state.phase = "cooldown"
                state.cooldownStartedAt = now
                state.cooldownDuration = duration
                state.cooldownExpiresAt = now + duration
            end

            stateByKey[spec.key] = state
        end
    end

    EnsureAnchor()
    EnsureUpdateLoop()
    RefreshLayout()

    if C_Timer then
        C_Timer.After(duration, function()
            ClearPreviewStates(token)
        end)
    end
end

local function HandleSpellUpdateCooldown(_, spellID, baseSpellID)
    if type(spellID) ~= "number" and type(baseSpellID) ~= "number" then
        return
    end
    local spec = SPEC_BY_SPELL[spellID] or SPEC_BY_SPELL[baseSpellID]
    if not spec then
        return
    end
    if tostring(spec.trigger or "") ~= "cooldown_update" then
        return
    end
    TriggerSpec(spec, false, spellID or baseSpellID)
end

local function HandleSpellcastSucceeded(_, unitTarget, _, spellID)
    if unitTarget ~= "player" or type(spellID) ~= "number" then
        return
    end
    local spec = SPEC_BY_SPELL[spellID]
    if not spec then
        return
    end
    if tostring(spec.trigger or "") ~= "spell_success" then
        return
    end
    TriggerSpec(spec, false, spellID)
end

local function HandleChallengeModeStart()
    ScheduleCooldownRecalibration(1)
end

local function HandleEncounterStart()
    ScheduleCooldownRecalibration(1)
end

local function HandleEncounterEnd()
    ScheduleCooldownRecalibration(1)
end

local function HandleEquippedItemChanged()
    C_Timer.After(0, RecheckEquippedTrinkets)
end

ExwindTools:RegisterEvent("SPELL_UPDATE_COOLDOWN", MODULE_KEY, HandleSpellUpdateCooldown)
ExwindTools:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", MODULE_KEY, HandleSpellcastSucceeded)
ExwindTools:RegisterEvent("CHALLENGE_MODE_START", MODULE_KEY, HandleChallengeModeStart)
ExwindTools:RegisterEvent("ENCOUNTER_START", MODULE_KEY, HandleEncounterStart)
ExwindTools:RegisterEvent("ENCOUNTER_END", MODULE_KEY, HandleEncounterEnd)
ExwindTools:RegisterEvent("ITEM_LOCK_CHANGED", MODULE_KEY, HandleEquippedItemChanged)
ExwindTools:RegisterEvent("ITEM_UNLOCKED", MODULE_KEY, HandleEquippedItemChanged)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    C_Timer.After(0, function()
        DB()
        if db then
            db.checkbox_8436 = false
        end
        EnsureAnchor()
        EnsureUpdateLoop()
        RefreshLayout()
        ScheduleCooldownRecalibration(1)
    end)
end)

EnsureAnchorController():RegisterEditModeHandler()
ExwindTools:ReportReady(MODULE_KEY)

-- 重置注册（供 ToolsPage 重置按钮调用）
ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[MODULE_KEY] = function()
    local moduleDB = _G.ExwindToolsDB and _G.ExwindToolsDB.ModuleDB
    if not moduleDB or not moduleDB[MODULE_KEY] then return end
    wipe(moduleDB[MODULE_KEY])
    db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    DeepApplyDefaults(db, DEFAULTS)
    ExwindTools:UpdateState(MODULE_KEY .. ".DatabaseChanged", { key = "*" })
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

ExwindTools:WatchState(MODULE_KEY .. ".DatabaseChanged", MODULE_KEY, function(info)
    db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    DeepApplyDefaults(db, DEFAULTS)
    if info and info.key == "checkbox_8436" then
        local shouldPreview = db.checkbox_8436 == true
        db.checkbox_8436 = false
        if shouldPreview then
            Preview(10)
            return
        end
    end
    EnsureAnchor()
    RefreshLayout()
end)

local function StartFramePicker()
    EnsureAnchorController():StartFramePicker()
end

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY, function(info)
    if not info then
        return
    end
    if info.key == "btn_edit" then
        if ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    elseif info.key == "btn_preview" then
        Preview(10)
    elseif info.key == "btn_clear" then
        ClearAllStates()
    elseif info.key == "btn_pick_frame" then
        StartFramePicker()
    end
end)

ExBoss.UI.Panel.StateIconsPage = ExBoss.UI.Panel.StateIconsPage or {}
local GUIPage = ExBoss.UI.Panel.StateIconsPage

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then
        return BASE_GRID_COLS
    end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < MIN_GRID_COLS then cols = MIN_GRID_COLS end
    if cols > MAX_GRID_COLS then cols = MAX_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then
        return LAYOUT
    end
    local cached = LAYOUT_CACHE[toCols]
    if cached then
        return cached
    end

    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then
                    row[k] = v
                end
            end
            if type(item.x) == "number" and type(item.w) == "number" then
                local nx = math.floor(((item.x - 1) * scale) + 1 + 0.5)
                local nw = math.max(1, math.floor(item.w * scale + 0.5))
                if nx < 1 then nx = 1 end
                if nx > toCols then nx = toCols end
                if nx + nw - 1 > toCols then
                    nw = math.max(1, toCols - nx + 1)
                end
                row.x = nx
                row.w = nw
            end
            if type(item.children) == "table" then
                row.children = ScaleItems(item.children)
            end
            out[#out + 1] = row
        end
        return out
    end

    cached = ScaleItems(items)
    LAYOUT_CACHE[toCols] = cached
    return cached
end

function GUIPage:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    local gridDB = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    DeepApplyDefaults(gridDB, DEFAULTS)
    local specItems = BuildSpecItems()
    for _, item in ipairs(LAYOUT) do
        if item.key == "slot1" or item.key == "slot2" or item.key == "slot3" or item.key == "slot4" or item.key == "slot5" or item.key == "slot6" or item.key == "slot7" then
            item.items = specItems
        end
    end

    if not GUIPage._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_StateIconsSettingsScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        GUIPage._scrollFrame = sf
        GUIPage._scrollChild = sc
    end

    local sf = GUIPage._scrollFrame
    local sc = GUIPage._scrollChild
    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if not sf:IsShown() then
            return
        end
        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 820
        end
        sc:SetWidth(width - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()

        local cols = ResolveGridCols(sc:GetWidth() or width)
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end

        ExwindTools.UI.ActivePageFrame = sc
        ExwindTools.UI.CurrentModule = MODULE_KEY
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), gridDB, MODULE_KEY)
    end)
end

function GUIPage:Hide()
    if GUIPage._scrollFrame then
        GUIPage._scrollFrame:Hide()
        if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == GUIPage._scrollChild then
            ExwindTools.UI.ActivePageFrame = nil
            ExwindTools.UI.CurrentModule = nil
        end
    end
end
