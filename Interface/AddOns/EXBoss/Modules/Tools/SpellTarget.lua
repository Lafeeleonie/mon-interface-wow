-- =============================================================
-- [[ EXBoss Tools: SpellTarget ]]
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local LSM = LibStub("LibSharedMedia-3.0")

ExBoss = ExBoss or {}
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.Tools = ExBoss.Tools or {}
ExBoss.Tools.SpellTarget = ExBoss.Tools.SpellTarget or {}
ExBoss.TargetIdentity = ExBoss.TargetIdentity or {}

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
local EXWIND_MODULE_KEY = "ExBoss.Tools.SpellTarget"
local TARGET_IDENTITY_UNIT_CHANGED = "ExBoss.TargetIdentity.UnitChanged"
local TARGET_IDENTITY_ROSTER_REVISION = "ExBoss.TargetIdentity.RosterRevision"

local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local UIParent = _G.UIParent
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitCanAttack = _G.UnitCanAttack
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitCastingDuration = _G.UnitCastingDuration
local UnitChannelDuration = _G.UnitChannelDuration
local UnitClass = _G.UnitClass
local UnitIsUnit = _G.UnitIsUnit
local UnitLevel = _G.UnitLevel
local C_Spell = _G.C_Spell
local C_Timer = _G.C_Timer
local ipairs = _G.ipairs
local pairs = _G.pairs
local string = _G.string
local table = _G.table
local type = _G.type

local ExwindFactory = _G.ExwindFactory
local PARTY_UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }
local PARTY_UNIT_TOKEN_SET = {
    player = true,
    party1 = true,
    party2 = true,
    party3 = true,
    party4 = true,
}

local activeIcons = {}
local usedIconsList = {}
local previewIcons = {}
local isPreviewing = false
local isEditModeActive = false
local isEditModeVisible = true
local editModeRestore = nil
local rootFrame = nil
local TogglePreview
local UpdateCast
local ReLayout
local RefreshAll
local areEventsEnabled = false

local EX_LAYOUT
local function EX_RegisterLayout()
    EX_LAYOUT = {
        { key = "header", type = "header", x = 1, y = 1, w = 53, h = 2, label = L["框架被点名提示"], labelSize = 25 },
        { key = "enabled", type = "checkbox", x = 1, y = 4, w = 8, h = 2, label = L["启用"] },
        { key = "preview", type = "checkbox", x = 11, y = 4, w = 10, h = 2, label = L["预览模式"] },
        { key = "hideLevel92Casts", type = "checkbox", x = 22, y = 4, w = 16, h = 2, label = L["隐藏92级读条"] },
        { key = "showTimer", type = "checkbox", x = 40, y = 4, w = 12, h = 2, label = L["显示时间"] },
        { key = "enableForTank", type = "checkbox", x = 1, y = 8, w = 16, h = 2, label = L["|cff00bfff坦克职责下开启|r"], labelSize = 17 },
        { key = "enableForDps", type = "checkbox", x = 18, y = 8, w = 16, h = 2, label = L["|cffff120aDPS职责下开启|r"], labelSize = 17 },
        { key = "enableForHeal", type = "checkbox", x = 35, y = 8, w = 16, h = 2, label = L["|cff02ff0a治疗职责下开启|r"], labelSize = 17 },
        { key = "showCooldownRing", type = "checkbox", x = 1, y = 12, w = 14, h = 2, label = L["倒数圈高亮"] },
        { key = "maxBars", type = "slider", x = 1, y = 16, w = 16, h = 2, label = L["最大数量"], min = 1, max = 15 },
        { key = "iconModeTimerSize", type = "slider", x = 19, y = 16, w = 16, h = 2, label = L["秒数字号"], min = 8, max = 32 },
        { key = "spacing", type = "slider", x = 37, y = 16, w = 16, h = 2, label = L["图标间距"], min = 0, max = 50 },
        {
            key = "growDir",
            type = "dropdown",
            x = 1,
            y = 19,
            w = 20,
            h = 2,
            label = L["增长方向"],
            items = {
                { L["整排居中"], "SPREAD" },
                { L["锚点居中"], "CENTER" },
            },
        },
        {
            key = "iconStyle",
            type = "icongroup",
            x = 1,
            y = 22,
            w = 53,
            h = 28,
            label = L["图标外观"],
            opts = {
                enableOffset = true,
            },
        },
    }


    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)
end

EX_RegisterLayout()

local EX_DEFAULTS = {
    enableForDps = true,
    enableForHeal = true,
    enableForTank = true,
    enabled = false,
    hideLevel92Casts = false,
    iconModeTimerSize = 16,
    iconStyle = {
        borderColorA = 1,
        borderColorB = 0,
        borderColorG = 0,
        borderColorR = 0,
        borderPadding = 0,
        borderSize = 1,
        borderTexture = "Square Full White",
        height = 28,
        reverse = true,
        showBorder = true,
        showIcon = true,
        width = 27,
        x = 2,
        y = 1,
    },
    maxBars = 3,
    preview = false,
    growDir = "SPREAD",
    showCooldownRing = true,
    showTimer = true,
    spacing = 1,
}


local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)

local function IsRoleEnabled()
    local roleKey = ExwindTools and ExwindTools.State and tostring(ExwindTools.State.RoleKey or ""):lower() or "unknown"
    if roleKey == "tank" then
        return EX_DB.enableForTank == true
    end
    if roleKey == "heal" then
        return EX_DB.enableForHeal == true
    end
    if roleKey == "dps" then
        return EX_DB.enableForDps == true
    end
    return false
end

local function GetIconStyleDB()
    local iconDb = EX_DB.iconStyle
    if type(iconDb) ~= "table" then
        iconDb = {}
        EX_DB.iconStyle = iconDb
    end
    return iconDb
end

local function CreateRootFrame()
    if rootFrame then return end
    rootFrame = CreateFrame("Frame", "ExBossSpellTargetRoot", UIParent)
    rootFrame:SetSize(1, 1)
    rootFrame:SetPoint("CENTER")
    rootFrame:SetFrameStrata("TOOLTIP")
    if rootFrame.SetFixedFrameStrata then
        rootFrame:SetFixedFrameStrata(true)
    end
    rootFrame:EnableMouse(false)
    rootFrame:Show()
    ExwindTools:RegisterHUD(EXWIND_MODULE_KEY, rootFrame)
end

local function ResolveAssignedTargetToken(unit)
    if not unit then
        return nil
    end

    local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
    if not (targetIdentity and type(targetIdentity.GetObservedTargetPartyUnit) == "function") then
        return nil
    end
    return targetIdentity.GetObservedTargetPartyUnit(unit)
end

local function CanReferenceFrame(frame)
    if frame == nil then
        return false
    end

    local frameType = type(frame)
    if frameType ~= "table" and frameType ~= "userdata" then
        return false
    end

    if type(frame.GetObjectType) == "function" then
        local okType, objectType = pcall(frame.GetObjectType, frame)
        if okType and type(objectType) == "string" and objectType == "" then
            return false
        end
    end

    if type(frame.GetPoint) ~= "function" and type(frame.SetPoint) ~= "function" then
        return false
    end

    return true
end

local function IsFrameShown(frame)
    if not CanReferenceFrame(frame) then
        return false
    end

    if type(frame.IsShown) == "function" then
        local okShown, isShown = pcall(frame.IsShown, frame)
        if not okShown or not isShown then
            return false
        end
    end

    if type(frame.IsVisible) == "function" then
        local okVisible, isVisible = pcall(frame.IsVisible, frame)
        if okVisible and not isVisible then
            return false
        end
    end

    return true
end

local function IsTrackedPartyUnit(unitToken)
    return type(unitToken) == "string" and PARTY_UNIT_TOKEN_SET[unitToken] == true
end

local function ResolveAssignedTargetFrame(unitToken)
    if not IsTrackedPartyUnit(unitToken) then return nil end
    local UF = ExwindTools and ExwindTools.UnitFrame
    if not (UF and type(UF.FindUnitFrame) == "function") then return nil end
    local frame = UF.FindUnitFrame(unitToken)
    if IsFrameShown(frame) then return frame end
    return nil
end

local function CollectPreviewOwnerFrames()
    local frames = {}
    local seen = {}

    local function AddFrame(frame)
        if IsFrameShown(frame) and not seen[frame] then
            seen[frame] = true
            table.insert(frames, frame)
        end
    end

    for _, unitToken in ipairs(PARTY_UNIT_TOKENS) do
        AddFrame(ResolveAssignedTargetFrame(unitToken))
    end

    return frames
end

local function UpdateIconVisuals(icon)
    if not icon then return end

    local iconStyle = GetIconStyleDB()
    local width = math.max(20, iconStyle.width or 36)
    local height = math.max(20, iconStyle.height or 36)
    local timerFontSize = math.max(8, EX_DB.iconModeTimerSize or 16)
    local borderTex = iconStyle.showBorder and iconStyle.borderTexture and iconStyle.borderTexture ~= "None"
        and LSM and LSM:Fetch("border", iconStyle.borderTexture) or nil

    icon:SetSize(width, height)

    if icon.Icon then
        icon.Icon:SetAllPoints(icon)
        icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.Icon:SetShown(iconStyle.showIcon ~= false)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
    end

    if borderTex and icon.BorderFrame then
        local edgeSize = iconStyle.borderSize or 1
        local pad = iconStyle.borderPadding or 0
        icon.BorderFrame:ClearAllPoints()
        icon.BorderFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        icon.BorderFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        icon.BorderFrame:SetBackdrop({ edgeFile = borderTex, edgeSize = edgeSize })
        icon.BorderFrame:SetBackdropBorderColor(
            iconStyle.borderColorR or 0,
            iconStyle.borderColorG or 0,
            iconStyle.borderColorB or 0,
            iconStyle.borderColorA or 1
        )
        icon.BorderFrame:Show()
    elseif icon.BorderFrame then
        icon.BorderFrame:Hide()
    end

    if icon.Cooldown then
        local showCooldownRing = EX_DB.showCooldownRing ~= false
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetAllPoints(icon)
        icon.Cooldown:SetReverse(iconStyle.reverse ~= false)
        -- 跟 EXBoss.TargetAlert 一致：用 Cooldown 自带的扫圈 + 边缘高亮，而不是自定义遮罩色。
        icon.Cooldown:SetDrawSwipe(showCooldownRing)
        icon.Cooldown:SetDrawEdge(showCooldownRing)
        icon.Cooldown:SetDrawBling(false)
        if icon.Cooldown.SetMinimumCountdownDuration then
            icon.Cooldown:SetMinimumCountdownDuration(0)
        end
        if icon.Cooldown.SetCountdownMillisecondsThreshold then
            icon.Cooldown:SetCountdownMillisecondsThreshold(10)
        end
        if icon.Cooldown.SetCountdownAbbrevThreshold then
            icon.Cooldown:SetCountdownAbbrevThreshold(0)
        end
        icon.Cooldown:SetHideCountdownNumbers(not EX_DB.showTimer)

        local countdown = icon.Cooldown.GetCountdownFontString and icon.Cooldown:GetCountdownFontString() or nil
        if countdown then
            local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            countdown:ClearAllPoints()
            countdown:SetPoint("CENTER", icon, "CENTER", 0, 0)
            countdown:SetJustifyH("CENTER")
            countdown:SetFont(font, timerFontSize, "OUTLINE")
        end
    end
end

local function ApplyIconLayer(icon, owner)
    if not icon then
        return
    end

    icon:SetFrameStrata("TOOLTIP")
    if icon.SetFixedFrameStrata then
        icon:SetFixedFrameStrata(true)
    end

    local baseLevel = 200
    if owner and type(owner.GetFrameLevel) == "function" then
        local ownerLevel = owner:GetFrameLevel()
        if type(ownerLevel) == "number" then
            baseLevel = ownerLevel + 50
        end
    end

    icon:SetFrameLevel(baseLevel)
    if icon.BorderFrame then
        icon.BorderFrame:SetFrameStrata("TOOLTIP")
        if icon.BorderFrame.SetFixedFrameStrata then
            icon.BorderFrame:SetFixedFrameStrata(true)
        end
        icon.BorderFrame:SetFrameLevel(baseLevel + 1)
    end
    if icon.Cooldown then
        icon.Cooldown:SetFrameLevel(baseLevel + 2)
    end
end

ReLayout = function()
    local list = isPreviewing and previewIcons or usedIconsList
    local maxLimit = EX_DB.maxBars or 5
    local spacing = EX_DB.spacing or 0
    local growDir = tostring(EX_DB.growDir or "SPREAD")
    local iconStyle = GetIconStyleDB()
    local iconHeight = math.max(20, iconStyle.height or 36)
    local targetGroups = {}
    local targetCounts = {}
    local orderedTargets = {}

    for _, icon in ipairs(list) do
        if IsFrameShown(icon._assignedTargetFrame) then
            local owner = icon._assignedTargetFrame
            local shownCount = targetCounts[owner] or 0
            if shownCount < maxLimit then
                local groupList = targetGroups[owner]
                if not groupList then
                    groupList = {}
                    targetGroups[owner] = groupList
                    table.insert(orderedTargets, owner)
                end
                table.insert(groupList, icon)
                targetCounts[owner] = shownCount + 1
                icon:Show()
                icon:EnableMouse(false)
            else
                icon:Hide()
            end
        else
            icon:Hide()
        end
    end

    for _, owner in ipairs(orderedTargets) do
        local icons = targetGroups[owner]
        local iconSpread = iconHeight + spacing

        for i, icon in ipairs(icons) do
            local xOffset
            if growDir == "CENTER" then
                local offset = i - 1
                if offset == 0 then
                    xOffset = 0
                else
                    local sideIndex = math.floor((offset + 1) / 2)
                    local direction = (offset % 2 == 1) and 1 or -1
                    xOffset = direction * sideIndex * iconSpread
                end
            else
                local centerOffset = ((#icons - 1) * iconSpread) / 2
                xOffset = ((i - 1) * iconSpread) - centerOffset
            end
            icon:ClearAllPoints()
            icon:SetPoint("BOTTOM", owner, "BOTTOM", (iconStyle.x or 0) + xOffset, (iconStyle.y or 6))
        end
    end
end

RefreshAll = function()
    if isPreviewing then
        TogglePreview(false)
        TogglePreview(true)
        return
    end

    for unit, _ in pairs(activeIcons) do
        UpdateCast(unit)
    end
    ReLayout()
end

local function InitIconStructure(icon)
    icon:EnableMouse(false)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.BorderFrame = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    icon.BorderFrame:Hide()
    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    ApplyIconLayer(icon, nil)
end

CreateRootFrame()
if ExwindFactory then
    ExwindFactory:InitPool("ExBossSpellTargetIcon", "Frame", nil, InitIconStructure)
end

local function AcquireIcon()
    if not ExwindFactory then return end
    local icon = ExwindFactory:Acquire("ExBossSpellTargetIcon", rootFrame)
    icon._isPreview = nil
    icon._assignedTargetFrame = nil
    icon.unit = nil
    UpdateIconVisuals(icon)
    return icon
end

local function ReleaseIcon(icon)
    if not ExwindFactory or not icon then return end
    icon.unit = nil
    icon._assignedTargetFrame = nil
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    ExwindFactory:Release("ExBossSpellTargetIcon", icon)
end

local function RemoveIconForUnit(unit)
    local icon = activeIcons[unit]
    if not icon then return end

    activeIcons[unit] = nil
    for i, usedIcon in ipairs(usedIconsList) do
        if usedIcon == icon then
            table.remove(usedIconsList, i)
            break
        end
    end
    ReleaseIcon(icon)
    ReLayout()
end

UpdateCast = function(unit)
    if isPreviewing then return end
    if not IsRoleEnabled() then
        RemoveIconForUnit(unit)
        return
    end

    if EX_DB.hideLevel92Casts and UnitLevel(unit) == 92 then
        RemoveIconForUnit(unit)
        return
    end

    if not UnitAffectingCombat(unit) then
        RemoveIconForUnit(unit)
        return
    end

    local activeObj = UnitCastingDuration(unit) or UnitChannelDuration(unit)
    local isChanneling = UnitChannelDuration(unit) ~= nil
    if not activeObj then
        RemoveIconForUnit(unit)
        return
    end

    local assignedToken = ResolveAssignedTargetToken(unit)
    local assignedFrame = ResolveAssignedTargetFrame(assignedToken)
    if not assignedFrame then
        RemoveIconForUnit(unit)
        return
    end

    local name, texture
    if isChanneling then
        name, _, texture = UnitChannelInfo(unit)
    else
        name, _, texture = UnitCastingInfo(unit)
    end
    if not name then
        RemoveIconForUnit(unit)
        return
    end

    local icon = activeIcons[unit]
    if not icon then
        icon = AcquireIcon()
        activeIcons[unit] = icon
        table.insert(usedIconsList, icon)
    end

    icon.unit = unit
    icon._assignedTargetFrame = assignedFrame
    ApplyIconLayer(icon, assignedFrame)
    if icon.Icon then
        icon.Icon:SetTexture(texture)
    end

    UpdateIconVisuals(icon)

    if icon.Cooldown then
        icon.Cooldown:SetHideCountdownNumbers(not EX_DB.showTimer)
        if icon.Cooldown.SetCooldownFromDurationObject then
            icon.Cooldown:SetCooldownFromDurationObject(activeObj, true)
        end
    end

    ReLayout()
end

function TogglePreview(enable)
    isPreviewing = enable

    if enable then
        for _, icon in pairs(activeIcons) do
            icon:Hide()
        end

        for i = #previewIcons, 1, -1 do
            local icon = previewIcons[i]
            icon:Hide()
            ReleaseIcon(icon)
            table.remove(previewIcons, i)
        end

        local maxLimit = EX_DB.maxBars or 5
        local previewOwnerFrames = CollectPreviewOwnerFrames()
        local iconStyle = GetIconStyleDB()
        local previewTexture = 136197
        if iconStyle.iconID and C_Spell and C_Spell.GetSpellTexture then
            previewTexture = C_Spell.GetSpellTexture(iconStyle.iconID) or previewTexture
        end

        for ownerIndex, ownerFrame in ipairs(previewOwnerFrames) do
            for iconIndex = 1, maxLimit do
                local icon = AcquireIcon()
                icon._isPreview = true
                icon._assignedTargetFrame = ownerFrame
                ApplyIconLayer(icon, icon._assignedTargetFrame)
                icon._previewRaidIndex = ((ownerIndex - 1) * maxLimit + iconIndex - 1) % 8 + 1

                if icon.Icon then
                    icon.Icon:SetTexture(previewTexture)
                end
                UpdateIconVisuals(icon)

                if icon.Cooldown then
                    icon.Cooldown:SetHideCountdownNumbers(not EX_DB.showTimer)
                    if icon.Cooldown.SetCooldown then
                        icon.Cooldown:SetCooldown(GetTime(), 2.5)
                    end
                end
                table.insert(previewIcons, icon)
            end
        end
    else
        for i = #previewIcons, 1, -1 do
            local icon = previewIcons[i]
            icon:Hide()
            ReleaseIcon(icon)
            table.remove(previewIcons, i)
        end

        for unit in pairs(activeIcons) do
            UpdateCast(unit)
        end
    end

    ReLayout()
end

local function OnEvent(event, unit, castBarID)
    if not EX_DB.enabled or not IsRoleEnabled() or not unit then return end

    if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
        if targetIdentity and type(targetIdentity.BeginObservedCast) == "function" then
            targetIdentity.BeginObservedCast(unit, castBarID, { source = "spelltarget" })
        end
        UpdateCast(unit)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
        if targetIdentity and type(targetIdentity.EndObservedCast) == "function" then
            targetIdentity.EndObservedCast(unit, castBarID)
        end
        RemoveIconForUnit(unit)
    else
        UpdateCast(unit)
    end
end

local function OnUnitRemoved(_, unit)
    RemoveIconForUnit(unit)
end

local function EnableEnvEvents()
    if areEventsEnabled then return end
    areEventsEnabled = true

    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY, OnEvent)
    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY, OnUnitRemoved)

    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, eventName in ipairs(events) do
        ExwindTools:RegisterEvent(eventName, EXWIND_MODULE_KEY, OnEvent)
    end
end

local function DisableEnvEvents()
    if not areEventsEnabled then return end
    areEventsEnabled = false

    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY)

    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, eventName in ipairs(events) do
        ExwindTools:UnregisterEvent(eventName, EXWIND_MODULE_KEY)
    end

    for unit, icon in pairs(activeIcons) do
        ReleaseIcon(icon)
        activeIcons[unit] = nil
    end
    usedIconsList = {}
end

local function CheckEnvStatus()
    local isParty = (ExwindTools.State.InstanceType == "party")
    if isParty and EX_DB.enabled and IsRoleEnabled() then
        EnableEnvEvents()
    else
        DisableEnvEvents()
    end
end

local function OnGroupRosterUpdate()
    CheckEnvStatus()
    if areEventsEnabled then
        RefreshAll()
    end
end

ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY, function()
    CheckEnvStatus()
end)

ExwindTools:WatchState("RoleKey", EXWIND_MODULE_KEY .. ".RoleChanged", function()
    CheckEnvStatus()
    if EX_DB.enabled and IsRoleEnabled() then
        RefreshAll()
    end
end)

ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY, OnGroupRosterUpdate)

ExwindTools:WatchState(TARGET_IDENTITY_ROSTER_REVISION, EXWIND_MODULE_KEY .. ".TargetIdentityRoster", function()
    if areEventsEnabled then
        RefreshAll()
    end
end)

ExwindTools:WatchState(TARGET_IDENTITY_UNIT_CHANGED, EXWIND_MODULE_KEY .. ".TargetIdentityUnit", function(info)
    if not areEventsEnabled or type(info) ~= "table" then
        return
    end
    local unit = tostring(info.unit or "")
    if string.match(unit, "^nameplate%d+$") then
        UpdateCast(unit)
    end
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".DatabaseChanged", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    if isEditModeActive and info.key == "preview" then
        return
    end

    CheckEnvStatus()

    if info.key == "preview" then
        TogglePreview(EX_DB.preview)
    elseif info.key == "enabled" or info.key == "enableForTank" or info.key == "enableForDps" or info.key == "enableForHeal" then
        if not EX_DB.enabled then
            DisableEnvEvents()
        else
            RefreshAll()
        end
    else
        RefreshAll()
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    EX_DB.preview = false
    TogglePreview(false)
    RefreshAll()
    CheckEnvStatus()
end)

local function ApplyEditModePresentation()
    if isEditModeActive then
        EX_DB.preview = isEditModeVisible
        TogglePreview(isEditModeVisible)
    else
        if editModeRestore then
            EX_DB.preview = editModeRestore.preview
            editModeRestore = nil
        end
        TogglePreview(EX_DB.preview)
    end
end

local function SetManagedEditMode(active)
    if active == true then
        if not editModeRestore then
            editModeRestore = {
                preview = EX_DB.preview,
            }
        end
        isEditModeActive = true
        isEditModeVisible = true
    else
        isEditModeActive = false
        isEditModeVisible = true
    end
    ApplyEditModePresentation()
end

ExwindTools:RegisterEditModeCallback(EXWIND_MODULE_KEY, function(active)
    SetManagedEditMode(ExwindTools.GlobalEditMode == true and active == true)
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    local wipe = _G.wipe
    local moduleDB = _G.ExwindToolsDB and _G.ExwindToolsDB.ModuleDB
    if not moduleDB or not moduleDB[EXWIND_MODULE_KEY] then return end
    wipe(moduleDB[EXWIND_MODULE_KEY])
    ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)
    ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".DatabaseChanged", { key = "*" })
end

local BASE_COLS = 53
local TARGET_CELL = 18

ExBoss.UI.Panel.SpellTargetPage = ExBoss.UI.Panel.SpellTargetPage or {}
local GUIPage = ExBoss.UI.Panel.SpellTargetPage

function GUIPage:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    if not GUIPage._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_SpellTargetSettingsScroll", contentFrame, "ScrollFrameTemplate")
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

        local cols = math.max(BASE_COLS, math.floor((((sc:GetWidth() or width) - 20) / TARGET_CELL) + 0.5))
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end

        ExwindTools.UI.ActivePageFrame = sc
        ExwindTools.UI.CurrentModule = EXWIND_MODULE_KEY
        Grid:Render(sc, EX_LAYOUT, EX_DB, EXWIND_MODULE_KEY)
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
