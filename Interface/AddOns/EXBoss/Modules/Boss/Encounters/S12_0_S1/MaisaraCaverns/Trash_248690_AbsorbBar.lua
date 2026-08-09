local ondev = flase
if ondev then
    return
end


---@diagnostic disable: undefined-global

do
    ExBoss = ExBoss or {}
    ExBoss.Modules = ExBoss.Modules or {}
    ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}
    local Mod = ExBoss.Modules.Boss.MaisaraTrash248690Absorb or {}
    ExBoss.Modules.Boss.MaisaraTrash248690Absorb = Mod

    local L = ExBoss and ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
    local BorderUtil = ExBoss.BorderUtil

    local MODULE_KEY = "ExBoss.Boss.MaisaraTrash248690Absorb"
    local MODULE_EVENT_PREFIX = "ExBoss_Maisara_Trash248690_Absorb"
    local TARGET_INSTANCE_ID = 2874
    local TARGET_NPC_ID = 248690
    local TARGET_SPELL_ID = 1270085
    local SHIELD_BASE_AMOUNT = 729045
    local MAX_NAMEPLATES = 40
    local REFRESH_INTERVAL = 0.20
    local EVENT_THROTTLE_SECONDS = 0.10
    local PREVIEW_UNIT_COUNT = 8
    local PREVIEW_UNITS = {}
    for i = 1, PREVIEW_UNIT_COUNT do
        PREVIEW_UNITS[i] = "__preview" .. i
    end
    local SUPPLEMENTAL_TRAIT_ROWS = {
        {
            dungeon = "迈萨拉洞窟",
            npcID = TARGET_NPC_ID,
            name = "阴冷散兵",
            level = 90,
            sex = 1,
            power = 1,
            classID = 1,
            buffCount = 1,
            boss = "2,3",
            nonElite = false,
            hasCastSpell = false,
            hasChannelSpell = false,
            cannotInterrupt = true,
            spellIDs = { 1270079, 1270085 },
        },
    }

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local TrashData = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
    local Observation = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Observation or nil
    local Inference = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Inference or nil
    local Calibration = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Calibration or nil
    if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
        LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
    end

    local eventFrame = nil
    local anchorFrame = nil
    local groupFrame = nil
    local barsByUnit = {}
    local trackedUnits = {}
    local observationState = {}
    local shieldIconTexture = nil
    local debugStateByUnit = {}
    local buffCountByUnit = {}
    local scheduledRefreshSerialByUnit = {}
    local pendingRefreshByUnit = {}
    local isEditMode = false
    local layoutDirty = false
    local layoutSuspendDepth = 0
    local styleRevision = 0
    local refreshTicker = nil
    local RefreshUnitBar = nil

    local function ApplyBackdropBorder(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
        if not borderFrame or not targetFrame or not texturePath then
            return
        end
        borderFrame:SetFrameLevel(frameLevel or (targetFrame:GetFrameLevel() + 2))
        borderFrame:ClearAllPoints()
        borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
        borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)
        borderFrame:SetBackdrop({
            edgeFile = texturePath,
            edgeSize = edgeSize,
        })
        borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
        borderFrame:Show()
    end

    local function SafeNum(value, fallback)
        local n = tonumber(value)
        if n == nil then
            return fallback
        end
        return n
    end

    local function IsSecretValue(value)
        return type(issecretvalue) == "function" and issecretvalue(value) == true
    end

    local function GetTrashDebug()
        return ExBoss and ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest or nil
    end

    local function IsDebugEnabled()
        local test = GetTrashDebug()
        return test and type(test.IsDebug) == "function" and test.IsDebug() == true
    end

    local function DebugLog(msg)
        if not IsDebugEnabled() then
            return
        end
        local test = GetTrashDebug()
        if test and type(test.AppendExternalDebug) == "function" then
            test.AppendExternalDebug("Trash248690", msg, true)
            return
        end
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ExBoss Trash248690|r " .. tostring(msg or ""))
        end
    end

    local function SetDebugState(unit, state, detail)
        if type(unit) == "string" then
            local index = unit:match("^nameplate(%d+)$")
            unit = index and ("nameplate" .. index) or unit
        else
            unit = tostring(unit or "?")
        end
        local msg = tostring(state or "?")
        if detail and detail ~= "" then
            msg = msg .. " " .. detail
        end
        if debugStateByUnit[unit] == msg then
            return
        end
        debugStateByUnit[unit] = msg
        DebugLog("unit=" .. unit .. " " .. msg)
    end

    local function GetPlayerInstanceID()
        local state = ExwindTools and ExwindTools.State or nil
        local stateInstanceID = tonumber(state and state.InstanceID)
        if stateInstanceID and stateInstanceID > 0 then
            return stateInstanceID
        end
        if type(GetInstanceInfo) == "function" then
            local instanceID = select(8, GetInstanceInfo())
            return tonumber(instanceID)
        end
        return nil
    end

    local function IsInMaisaraCaverns()
        return GetPlayerInstanceID() == TARGET_INSTANCE_ID
    end

    local function NormalizeNameplateUnit(unit)
        local api = ExBoss and ExBoss.Trash and ExBoss.Trash.NormalizeNameplateUnit or nil
        if type(api) == "function" then
            return api(unit)
        end
        if type(unit) ~= "string" then
            return nil
        end
        local index = unit:match("^nameplate(%d+)$")
        if not index then
            return nil
        end
        return "nameplate" .. index
    end

    local function CollectNormalizedBuffCount(unit)
        unit = NormalizeNameplateUnit(unit)
        if not unit then
            return nil
        end
        if Observation and type(Observation.CollectObservedUnit) == "function" then
            local obs = Observation.CollectObservedUnit(unit)
            local buffCount = type(obs) == "table" and obs.buffCount or nil
            return type(buffCount) == "number" and buffCount or tonumber(buffCount)
        end
        ---@diagnostic disable-next-line: undefined-field
        local fn = _G.EXDB and _G.EXDB._s
        if type(fn) ~= "function" then
            return nil
        end
        local ok, _, _, _, _, _, _, buffCount = pcall(fn, unit)
        if not ok then
            return nil
        end
        return type(buffCount) == "number" and buffCount or tonumber(buffCount)
    end

    local function IsHostileNameplate(unit)
        return type(unit) == "string"
            and UnitExists and UnitExists(unit)
            and UnitCanAttack and UnitCanAttack("player", unit)
            and UnitIsDead and not UnitIsDead(unit)
    end

    local function IsUnitInCombat(unit)
        return type(unit) == "string"
            and UnitExists and UnitExists(unit)
            and UnitAffectingCombat and UnitAffectingCombat(unit) == true
    end

    local function GetCurrentTrashContext()
        local instanceID, dungeonName = nil, nil
        if TrashData and type(TrashData.GetCurrentInstanceContext) == "function" then
            instanceID, dungeonName = TrashData.GetCurrentInstanceContext()
        end
        local dungeonKey = TrashData and type(TrashData.NormalizeNameKey) == "function"
            and TrashData.NormalizeNameKey(dungeonName)
            or tostring(dungeonName or "")
        local trashMapID = nil
        if Calibration and type(Calibration.GetCurrentTrashMapID) == "function" then
            trashMapID = Calibration.GetCurrentTrashMapID(dungeonKey)
        elseif TrashData and type(TrashData.GetTrashMapIDByNameKey) == "function" then
            local byNameKey = TrashData.GetTrashMapIDByNameKey()
            trashMapID = type(byNameKey) == "table" and tonumber(byNameKey[dungeonKey]) or nil
        end
        return tonumber(instanceID), dungeonKey, tonumber(trashMapID)
    end

    local supplementalTraitInjected = false

    local function EnsureSupplementalTraitRow()
        if supplementalTraitInjected == true then
            return
        end
        local traits = TrashData and type(TrashData.GetTrashMobTraitsRoot) == "function" and
            TrashData.GetTrashMobTraitsRoot() or nil
        local baseRows = type(traits) == "table" and type(traits.rows) == "table" and traits.rows or {}
        for i = 1, #baseRows do
            local row = baseRows[i]
            if type(row) == "table"
                and tonumber(row.npcID or row[3]) == TARGET_NPC_ID
                and tostring(row.dungeon or row[2] or "") == "迈萨拉洞窟" then
                supplementalTraitInjected = true
                return
            end
        end
        for i = 1, #SUPPLEMENTAL_TRAIT_ROWS do
            baseRows[#baseRows + 1] = SUPPLEMENTAL_TRAIT_ROWS[i]
        end
        supplementalTraitInjected = true
    end

    local function GetTraitRows()
        EnsureSupplementalTraitRow()
        local traits = TrashData and type(TrashData.GetTrashMobTraitsRoot) == "function" and
            TrashData.GetTrashMobTraitsRoot() or nil
        return type(traits) == "table" and type(traits.rows) == "table" and traits.rows or {}
    end

    local function ResolveUnitRuntime(unit)
        unit = NormalizeNameplateUnit(unit)
        if not unit or not IsHostileNameplate(unit) then
            return nil, nil, false
        end
        if not (Observation and type(Observation.CollectTrackedNameplate) == "function"
                and type(Observation.GetRuntimeObs) == "function"
                and Inference and type(Inference.ResolveCandidates) == "function") then
            return nil, nil, false
        end

        local instanceID, dungeonKey, trashMapID = GetCurrentTrashContext()
        if instanceID ~= TARGET_INSTANCE_ID or trashMapID ~= TARGET_INSTANCE_ID or dungeonKey == "" then
            SetDebugState(unit, "context-miss", string.format(
                "instance=%s trashMap=%s key=%s",
                tostring(instanceID or "nil"),
                tostring(trashMapID or "nil"),
                tostring(dungeonKey or "")
            ))
            return nil, nil, false
        end

        local obs = Observation.CollectTrackedNameplate(observationState, unit, IsHostileNameplate, nil, false)
        local runtime = Observation.GetRuntimeObs(observationState, unit)
        if not obs then
            SetDebugState(unit, "obs-missing")
            return runtime, nil, false
        end
        if obs.pending == true then
            return runtime, nil, true, tonumber(obs.retryAfter) or 0.12
        end

        local result = Inference.ResolveCandidates(obs, dungeonKey, GetTraitRows(), runtime, trashMapID, GetTime())
        local resolved = type(result) == "table" and result.resolved or nil
        local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
        if runtime and resolvedNPCID then
            runtime.matchedMapID = trashMapID
            runtime.matchedNPCID = resolvedNPCID
        end
        return runtime, resolvedNPCID, false
    end

    local function PanelDB()
        _G.ExBossDB = _G.ExBossDB or {}
        _G.ExBossDB.timer = _G.ExBossDB.timer or {}
        local db = _G.ExBossDB.timer.trash248690AbsorbPanel
        if type(db) ~= "table" then
            db = {
                anchorX_1205 = 360,
                anchorY_1205 = -40,
                width = 220,
                height = 18,
                growDir = "UP",
                maxVisibleBars = 6,
                stackGap = 4,
            }
            _G.ExBossDB.timer.trash248690AbsorbPanel = db
        end
        if db.maxVisibleBars == nil then
            db.maxVisibleBars = 6
        end
        if db.stackGap == nil then
            db.stackGap = 4
        end
        if db.enabled == nil then
            db.enabled = true
        end
        return db
    end

    local function IsModuleEnabled()
        return PanelDB().enabled ~= false
    end

    local function GetConfiguredMaxBars()
        return math.max(1, math.floor(SafeNum(PanelDB().maxVisibleBars, 6)))
    end

    local function StyleDB()
        _G.ExBossDB = _G.ExBossDB or {}
        _G.ExBossDB.timer = _G.ExBossDB.timer or {}
        local db = _G.ExBossDB.timer.trash248690AbsorbStyle
        if type(db) ~= "table" then
            local legacy = _G.ExBossDB.timer.castProgressBar
            if type(legacy) == "table" then
                local migrated = {}
                DeepCopyInto(migrated, legacy)
                db = migrated
            else
                db = {}
            end
            _G.ExBossDB.timer.trash248690AbsorbStyle = db
        end
        return db
    end

    local function GetPercentFontDB(styleDB)
        if type(styleDB) ~= "table" then
            return nil
        end
        if type(styleDB.font_percent) == "table" then
            return styleDB.font_percent
        end
        if type(styleDB.font_time) == "table" then
            return styleDB.font_time
        end
        return nil
    end

    local function GetShieldLevelMultiplier()
        local state = ExwindTools and ExwindTools.State or nil
        if not state or state.InMythicPlus ~= true then
            return 1
        end
        local level = tonumber(state and state.MythicPlusLevel) or 0
        local db = _G.EXDB
        local multipliers = db and db.MythicDamageData and db.MythicDamageData.LevelMultipliers or nil
        local multiplier = multipliers and multipliers[level] or nil
        return tonumber(multiplier) or 1
    end

    local function GetConfiguredShieldMaxValue()
        return SHIELD_BASE_AMOUNT * GetShieldLevelMultiplier()
    end

    local function ResolveStyle()
        local panelDB = PanelDB()
        local db = StyleDB()
        local style = type(db) == "table" and type(db.timerBarGroup) == "table" and db.timerBarGroup or db or {}
        return {
            width = math.max(80, SafeNum(style.width, SafeNum(panelDB.width, 180))),
            height = math.max(8, SafeNum(style.height, SafeNum(panelDB.height, 18))),
            texture = style.texture or "Melli",
            barColorR = SafeNum(style.barColorR, 0.15),
            barColorG = SafeNum(style.barColorG, 0.85),
            barColorB = SafeNum(style.barColorB, 1.00),
            barColorA = SafeNum(style.barColorA, 1.00),
            barBgColorR = SafeNum(style.barBgColorR, 0.00),
            barBgColorG = SafeNum(style.barBgColorG, 0.00),
            barBgColorB = SafeNum(style.barBgColorB, 0.00),
            barBgColorA = SafeNum(style.barBgColorA, 0.50),
            showBorder = (style.showBorder ~= false),
            borderTexture = style.borderTexture or "Square Full White",
            borderColorR = SafeNum(style.borderColorR, 0.00),
            borderColorG = SafeNum(style.borderColorG, 0.00),
            borderColorB = SafeNum(style.borderColorB, 0.00),
            borderColorA = SafeNum(style.borderColorA, 1.00),
            borderSize = SafeNum(style.borderSize, 1),
            borderPadding = SafeNum(style.borderPadding, 0),
            showIcon = (style.showIcon ~= false),
            iconSide = tostring(style.iconSide or "LEFT"):upper(),
            iconSize = math.max(8, SafeNum(style.iconSize, SafeNum(style.height, 18))),
            iconOffsetX = SafeNum(style.iconOffsetX, -1),
            iconOffsetY = SafeNum(style.iconOffsetY, 0),
            showIconBorder = (style.showIconBorder ~= false),
            iconBorderTexture = style.iconBorderTexture or "Square Full White",
            iconBorderColorR = SafeNum(style.iconBorderColorR, 0.00),
            iconBorderColorG = SafeNum(style.iconBorderColorG, 0.00),
            iconBorderColorB = SafeNum(style.iconBorderColorB, 0.00),
            iconBorderColorA = SafeNum(style.iconBorderColorA, 1.00),
            iconBorderSize = SafeNum(style.iconBorderSize, 1),
            iconBorderPadding = SafeNum(style.iconBorderPadding, 0),
            growDir = tostring(panelDB.growDir or "UP"),
            stackGap = math.max(0, SafeNum(panelDB.stackGap, 4)),
        }
    end

    local function GetMediaFont(fontKey)
        local key = tostring(fontKey or "")
        if key ~= "" and LSM and type(LSM.Fetch) == "function" then
            local font = LSM:Fetch("font", key, true)
            if font and font ~= "" then
                return font
            end
        end
        return ExwindTools and ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT
    end

    local function ApplyFont(fontString, fontDB, fallbackSize)
        if not fontString then
            return
        end
        local staticDB = ExwindTools and ExwindTools.DB_Static or nil
        if staticDB and staticDB.ApplyFont and type(fontDB) == "table" then
            staticDB:ApplyFont(fontString, fontDB)
            return
        end
        fontString:SetFont(
            GetMediaFont(type(fontDB) == "table" and fontDB.font or nil),
            SafeNum(type(fontDB) == "table" and fontDB.size or nil, fallbackSize or 14),
            tostring(type(fontDB) == "table" and fontDB.outline or "OUTLINE")
        )
        fontString:SetTextColor(
            SafeNum(type(fontDB) == "table" and fontDB.r or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.g or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.b or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.a or nil, 1)
        )
        if type(fontDB) == "table" and fontDB.shadow == false then
            fontString:SetShadowOffset(0, 0)
        else
            fontString:SetShadowOffset(
                SafeNum(type(fontDB) == "table" and fontDB.shadowX or nil, 1),
                SafeNum(type(fontDB) == "table" and fontDB.shadowY or nil, -1)
            )
            fontString:SetShadowColor(0, 0, 0, 0.90)
        end
    end

    local function ResolveSpellIcon()
        if shieldIconTexture then
            return shieldIconTexture
        end
        if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, tex = pcall(C_Spell.GetSpellTexture, TARGET_SPELL_ID)
            if ok and tex then
                shieldIconTexture = tex
                return tex
            end
        end
        shieldIconTexture = 136197
        return shieldIconTexture
    end

    local function SetClickThrough(frame)
        if not frame then
            return
        end
        frame:EnableMouse(false)
        if frame.SetMouseClickEnabled then pcall(frame.SetMouseClickEnabled, frame, false) end
        if frame.SetMouseMotionEnabled then pcall(frame.SetMouseMotionEnabled, frame, false) end
    end

    local function EnsureAnchorFrame()
        if anchorFrame then
            return anchorFrame
        end

        local db = PanelDB()
        anchorFrame = CreateFrame("Frame", "ExBoss_Maisara_Trash248690_Anchor", UIParent, "BackdropTemplate")
        anchorFrame:SetSize(math.max(120, SafeNum(db.width, 220)), 120)
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", SafeNum(db.anchorX_1205, 360), SafeNum(db.anchorY_1205, -40))
        anchorFrame:SetMovable(true)
        anchorFrame:SetClampedToScreen(true)
        anchorFrame:SetFrameStrata("DIALOG")
        SetClickThrough(anchorFrame)
        anchorFrame:Hide()

        local editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
        editOverlay:SetAllPoints()
        editOverlay:SetColorTexture(0, 0.8, 0, 0.18)
        editOverlay:Hide()
        anchorFrame.EditOverlay = editOverlay

        local editLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        editLabel:SetPoint("CENTER", anchorFrame, "CENTER")
        editLabel:SetText("|cff00ff00[" .. tostring(L["小怪护盾面板"]) .. "]|r")
        editLabel:Hide()
        anchorFrame.EditLabel = editLabel

        anchorFrame:SetScript("OnMouseDown", function(self, button)
            if not (ExwindTools and ExwindTools.GlobalEditMode) then return end
            if button == "LeftButton" then
                self.isMoving = true
                self:StartMoving()
            end
        end)
        anchorFrame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                self.isMoving = false
                self:StopMovingOrSizing()
                local cx, cy = UIParent:GetCenter()
                local sx, sy = self:GetCenter()
                if sx and cx then
                    local panelDB = PanelDB()
                    panelDB.anchorX_1205 = math.floor(sx - cx)
                    panelDB.anchorY_1205 = math.floor(sy - cy)
                end
            end
        end)
        anchorFrame:SetScript("OnHide", function(self)
            if self.isMoving then
                self.isMoving = false
                self:StopMovingOrSizing()
            end
        end)

        if ExwindTools and type(ExwindTools.RegisterHUD) == "function" then
            ExwindTools:RegisterHUD(MODULE_KEY, anchorFrame)
            SetClickThrough(anchorFrame)
        end
        return anchorFrame
    end

    local function ResolveAnchor()
        return EnsureAnchorFrame() or UIParent
    end

    local function FormatAmount(secretValue)
        if secretValue == nil then
            return ""
        end
        if type(AbbreviateLargeNumbers) == "function" then
            local ok, text = pcall(AbbreviateLargeNumbers, secretValue)
            if ok and type(text) == "string" then
                return text
            end
        end
        if type(BreakUpLargeNumbers) == "function" then
            local ok, text = pcall(BreakUpLargeNumbers, secretValue)
            if ok and type(text) == "string" then
                return text
            end
        end
        return ""
    end

    local function FormatShieldPercent(secretValue, maxValue)
        local maxNum = tonumber(maxValue) or 0
        if secretValue == nil or maxNum <= 0 then
            return ""
        end
        if type(AbbreviateNumbers) == "function" then
            local ok, text = pcall(AbbreviateNumbers, secretValue, {
                breakpointData = {
                    {
                        breakpoint = 0,
                        abbreviation = "%",
                        significandDivisor = maxNum / 100,
                        fractionDivisor = 1,
                        abbreviationIsGlobal = false,
                    },
                },
            })
            if ok and type(text) == "string" then
                return text
            end
        end
        return FormatAmount(secretValue)
    end

    local function ApplyFrameStrata(frame)
        if not frame then
            return
        end
        frame:SetFrameStrata("DIALOG")
        if frame.SetFixedFrameStrata then
            frame:SetFixedFrameStrata(true)
        end
        if frame.SetFixedFrameLevel then
            frame:SetFixedFrameLevel(true)
        end
    end

    local function EnsureBar(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil
        end
        local bar = barsByUnit[unit]
        if bar then
            return bar
        end

        bar = CreateFrame("Frame", nil, UIParent)
        bar:SetSize(180, 18)
        ApplyFrameStrata(bar)
        bar:SetFrameLevel(6200)
        bar:EnableMouse(false)
        bar:Hide()

        local statusBar = CreateFrame("StatusBar", nil, bar, "BackdropTemplate")
        statusBar:SetAllPoints(bar)
        statusBar:SetMinMaxValues(0, 1)
        statusBar:SetValue(1)
        statusBar:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.statusBar = statusBar

        local bg = statusBar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(statusBar)
        bar.bg = bg

        local borderFrame = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
        borderFrame:SetFrameLevel(statusBar:GetFrameLevel() + 2)
        borderFrame:Hide()
        statusBar.BorderFrame = borderFrame

        local icon = statusBar:CreateTexture(nil, "OVERLAY")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar.icon = icon

        local iconBorderFrame = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
        iconBorderFrame:SetFrameLevel(statusBar:GetFrameLevel() + 2)
        iconBorderFrame:Hide()
        statusBar.IconBorderFrame = iconBorderFrame

        local textFrame = CreateFrame("Frame", nil, bar)
        textFrame:SetAllPoints(bar)
        textFrame:SetFrameLevel(statusBar:GetFrameLevel() + 4)
        textFrame:EnableMouse(false)
        bar.textFrame = textFrame

        local label = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        bar.label = label

        local value = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        value:SetJustifyV("MIDDLE")
        bar.value = value

        barsByUnit[unit] = bar
        return bar
    end

    local function EnsureGroupFrame()
        if groupFrame then
            return groupFrame
        end
        groupFrame = CreateFrame("Frame", "ExBoss_Maisara_Trash248690_Group", UIParent)
        ApplyFrameStrata(groupFrame)
        groupFrame:SetFrameLevel(6190)
        groupFrame:EnableMouse(false)
        groupFrame:Hide()
        return groupFrame
    end

    local function ResetBarState(bar)
        if not bar then
            return
        end
        bar._active = false
        bar._preview = nil
        if bar.value then
            bar.value:SetText("")
        end
        if bar.label then
            bar.label:SetText("")
        end
        if bar.statusBar then
            if Enum and Enum.StatusBarInterpolation then
                bar.statusBar:SetMinMaxValues(0, 1, Enum.StatusBarInterpolation.Immediate)
                bar.statusBar:SetValue(0, Enum.StatusBarInterpolation.Immediate)
            else
                bar.statusBar:SetMinMaxValues(0, 1)
                bar.statusBar:SetValue(0)
            end
        end
    end

    local function HideBar(unit)
        local bar = barsByUnit[unit]
        if not bar then
            return
        end
        local wasActive = bar._active == true or bar:IsShown()
        ResetBarState(bar)
        bar:Hide()
        if wasActive then
            layoutDirty = true
        end
    end

    local ApplyBarStyle = nil
    local LayoutVisibleBars = nil
    local RefreshTrackedUnits = nil

    local StartRefreshTicker = nil
    local StopRefreshTicker = nil
    local ResetAll = nil
    local ScanVisibleNameplates = nil

    local function MarkLayoutDirty()
        layoutDirty = true
    end

    local function FlushLayoutIfDirty()
        if layoutSuspendDepth > 0 or layoutDirty ~= true or not LayoutVisibleBars then
            return
        end
        layoutDirty = false
        LayoutVisibleBars()
    end

    local function HasPendingRefresh()
        return next(pendingRefreshByUnit) ~= nil
    end

    local function QueueUnitRefresh(unit)
        unit = NormalizeNameplateUnit(unit)
        if not unit or not IsModuleEnabled() then
            return
        end
        pendingRefreshByUnit[unit] = true
        if StartRefreshTicker then
            StartRefreshTicker()
        end
    end

    local function QueueTrackedUnitsRefresh()
        if not IsModuleEnabled() then
            return
        end
        for unit in pairs(trackedUnits) do
            pendingRefreshByUnit[unit] = true
        end
        if StartRefreshTicker then
            StartRefreshTicker()
        end
    end

    local function ResolveTrackedUnitFromEventUnit(unit)
        local normalized = NormalizeNameplateUnit(unit)
        if normalized and trackedUnits[normalized] == true then
            return normalized
        end
        if type(unit) ~= "string" then
            return nil
        end
        local ownerUnit = unit:match("^(nameplate%d+)target$")
        if ownerUnit and trackedUnits[ownerUnit] == true then
            return ownerUnit
        end
        return nil
    end

    local function ScheduleThrottledUnitRefresh(unit)
        unit = ResolveTrackedUnitFromEventUnit(unit)
        if not IsModuleEnabled() or not IsInMaisaraCaverns() or not unit then
            if not IsModuleEnabled() or not IsInMaisaraCaverns() then
                ResetAll()
            end
            return
        end
        local nextSerial = (scheduledRefreshSerialByUnit[unit] or 0) + 1
        scheduledRefreshSerialByUnit[unit] = nextSerial
        if not (C_Timer and type(C_Timer.After) == "function") then
            QueueUnitRefresh(unit)
            return
        end
        C_Timer.After(EVENT_THROTTLE_SECONDS, function()
            if scheduledRefreshSerialByUnit[unit] ~= nextSerial then
                return
            end
            scheduledRefreshSerialByUnit[unit] = nil
            if trackedUnits[unit] == true and IsInMaisaraCaverns() then
                QueueUnitRefresh(unit)
            end
        end)
    end

    local function BeginLayoutBatch()
        layoutSuspendDepth = layoutSuspendDepth + 1
    end

    local function EndLayoutBatch()
        if layoutSuspendDepth > 0 then
            layoutSuspendDepth = layoutSuspendDepth - 1
        end
        FlushLayoutIfDirty()
    end

    local function ConfigurePreviewBar(bar, index)
        if not bar then
            return
        end

        ApplyBarStyle(bar)
        local shieldMaxValue = GetConfiguredShieldMaxValue()
        local previewRatios = { 0.82, 0.69, 0.57, 0.48, 0.40, 0.31, 0.24, 0.16 }
        local currentValue = shieldMaxValue * (previewRatios[index] or 0.5)

        if bar.statusBar.SetMinMaxValues then
            if Enum and Enum.StatusBarInterpolation then
                bar.statusBar:SetMinMaxValues(0, shieldMaxValue, Enum.StatusBarInterpolation.Immediate)
            else
                bar.statusBar:SetMinMaxValues(0, shieldMaxValue)
            end
        end
        if Enum and Enum.StatusBarInterpolation then
            bar.statusBar:SetValue(currentValue, Enum.StatusBarInterpolation.Immediate)
        else
            bar.statusBar:SetValue(currentValue)
        end
        if type(bar.statusBar.SetToTargetValue) == "function" then
            bar.statusBar:SetToTargetValue()
        end

        bar.label:SetText("")
        bar.value:SetText(FormatShieldPercent(currentValue, shieldMaxValue))
        bar._active = true
        bar._preview = index
    end

    local function ClearEditPreview()
        for i = 1, #PREVIEW_UNITS do
            HideBar(PREVIEW_UNITS[i])
        end
    end

    local function ShowStaticEditPreview()
        ClearEditPreview()
        local maxBars = math.min(GetConfiguredMaxBars(), #PREVIEW_UNITS)
        for i = 1, maxBars do
            local bar = EnsureBar(PREVIEW_UNITS[i])
            ConfigurePreviewBar(bar, i)
        end
        LayoutVisibleBars()
    end

    ApplyBarStyle = function(bar)
        if not bar then
            return
        end
        if bar._styleRevision == styleRevision then
            return
        end

        local db = StyleDB() or {}
        local style = ResolveStyle()
        local texture = (LSM and type(LSM.Fetch) == "function" and LSM:Fetch("statusbar", style.texture)) or
            "Interface\\Buttons\\WHITE8X8"

        bar:SetSize(style.width, style.height)
        bar.statusBar:SetStatusBarTexture(texture)
        bar.statusBar:SetStatusBarColor(style.barColorR, style.barColorG, style.barColorB, style.barColorA)
        if bar.statusBar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
            bar.statusBar:SetFillStyle(Enum.StatusBarFillStyle.StandardNoRangeFill)
        end
        if bar.statusBar.SetReverseFill then
            bar.statusBar:SetReverseFill(false)
        end
        bar.bg:SetTexture(texture)
        bar.bg:SetVertexColor(style.barBgColorR, style.barBgColorG, style.barBgColorB, style.barBgColorA)

        if bar.statusBar.BorderFrame then
            bar.statusBar.BorderFrame:Hide()
        end
        if style.showBorder and style.borderTexture ~= "None" and LSM and type(LSM.Fetch) == "function" then
            local edgeTex = LSM:Fetch("border", style.borderTexture)
            if edgeTex then
                local pad = style.borderPadding
                ApplyBackdropBorder(
                    bar.statusBar.BorderFrame,
                    bar.statusBar,
                    edgeTex,
                    style.borderSize,
                    pad,
                    style.borderColorR,
                    style.borderColorG,
                    style.borderColorB,
                    style.borderColorA,
                    bar.statusBar:GetFrameLevel() + 2
                )
            end
        end

        bar.icon:SetSize(style.iconSize, style.iconSize)
        bar.icon:ClearAllPoints()
        if style.iconSide == "RIGHT" then
            bar.icon:SetPoint("LEFT", bar.statusBar, "RIGHT", style.iconOffsetX, style.iconOffsetY)
        else
            bar.icon:SetPoint("RIGHT", bar.statusBar, "LEFT", style.iconOffsetX, style.iconOffsetY)
        end
        bar.icon:SetShown(style.showIcon ~= false)
        bar.icon:SetTexture(ResolveSpellIcon())

        if bar.statusBar.IconBorderFrame then
            bar.statusBar.IconBorderFrame:Hide()
        end
        if style.showIcon ~= false and style.showIconBorder and style.iconBorderTexture ~= "None" and LSM and type(LSM.Fetch) == "function" then
            local iconEdgeTex = LSM:Fetch("border", style.iconBorderTexture)
            if iconEdgeTex then
                local pad = style.iconBorderPadding
                ApplyBackdropBorder(
                    bar.statusBar.IconBorderFrame,
                    bar.icon,
                    iconEdgeTex,
                    style.iconBorderSize,
                    pad,
                    style.iconBorderColorR,
                    style.iconBorderColorG,
                    style.iconBorderColorB,
                    style.iconBorderColorA,
                    bar.statusBar:GetFrameLevel() + 2
                )
            end
        end

        local percentFont = GetPercentFontDB(db)

        ApplyFont(bar.label, db.font_name, 14)
        ApplyFont(bar.value, percentFont, 14)
        bar.label:SetDrawLayer("OVERLAY", 6)
        bar.value:SetDrawLayer("OVERLAY", 7)

        bar.label:ClearAllPoints()
        bar.label:SetPoint(
            "LEFT",
            bar.statusBar,
            "LEFT",
            SafeNum(type(db.font_name) == "table" and db.font_name.x or nil, 4),
            SafeNum(type(db.font_name) == "table" and db.font_name.y or nil, 0)
        )
        bar.label:SetPoint("RIGHT", bar.value, "LEFT", -8, 0)
        bar.label:SetText("")

        bar.value:ClearAllPoints()
        bar.value:SetPoint(
            "RIGHT",
            bar.statusBar,
            "RIGHT",
            SafeNum(type(percentFont) == "table" and percentFont.x or nil, -4),
            SafeNum(type(percentFont) == "table" and percentFont.y or nil, 0)
        )
        bar.value:SetWidth(math.max(40, style.width - 40))
        bar.value:SetShown(not (type(percentFont) == "table" and percentFont.enabled == false))
        bar._styleRevision = styleRevision
    end

    local function BuildVisibleUnitList()
        local out = {}
        local maxBars = GetConfiguredMaxBars()
        if isEditMode then
            for i = 1, #PREVIEW_UNITS do
                local unit = PREVIEW_UNITS[i]
                local bar = barsByUnit[unit]
                if bar and bar._active == true and bar._preview then
                    out[#out + 1] = unit
                    if #out >= maxBars then
                        break
                    end
                end
            end
            return out
        end
        for unit in pairs(trackedUnits) do
            local bar = barsByUnit[unit]
            if bar and bar._active == true and bar._preview ~= true then
                out[#out + 1] = unit
            end
        end
        table.sort(out, function(a, b)
            local ai = tonumber(tostring(a or ""):match("^nameplate(%d+)$")) or 999
            local bi = tonumber(tostring(b or ""):match("^nameplate(%d+)$")) or 999
            return ai < bi
        end)
        while #out > maxBars do
            out[#out] = nil
        end
        return out
    end

    LayoutVisibleBars = function()
        EnsureAnchorFrame()
        local frame = EnsureGroupFrame()
        local style = ResolveStyle()
        local units = BuildVisibleUnitList()
        local count = #units
        if count <= 0 then
            frame:Hide()
            for _, bar in pairs(barsByUnit) do
                if bar and bar._active ~= true then
                    bar:Hide()
                end
            end
            return
        end

        local anchor = ResolveAnchor()
        local barHeight = math.max(1, style.height)
        local gap = math.max(0, SafeNum(style.stackGap, 4))
        local totalHeight = barHeight * count + gap * math.max(0, count - 1)

        frame:ClearAllPoints()
        if tostring(style.growDir or "UP"):upper() == "DOWN" then
            frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        else
            frame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        end
        frame:SetSize(style.width, totalHeight)
        frame:Show()

        for index = 1, count do
            local unit = units[index]
            local bar = barsByUnit[unit]
            if bar then
                bar:ClearAllPoints()
                if tostring(style.growDir or "UP"):upper() == "DOWN" then
                    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -((index - 1) * (barHeight + gap)))
                else
                    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, (index - 1) * (barHeight + gap))
                end
                bar:Show()
            end
        end
    end

    local function SetEditMode(enabled)
        EnsureAnchorFrame()
        isEditMode = enabled == true
        if isEditMode then
            anchorFrame:EnableMouse(true)
            if anchorFrame.SetMouseClickEnabled then pcall(anchorFrame.SetMouseClickEnabled, anchorFrame, true) end
            if anchorFrame.SetMouseMotionEnabled then pcall(anchorFrame.SetMouseMotionEnabled, anchorFrame, true) end
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
            if anchorFrame.EditLabel then anchorFrame.EditLabel:Show() end
            anchorFrame:Show()
            ShowStaticEditPreview()
        else
            SetClickThrough(anchorFrame)
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
            if anchorFrame.EditLabel then anchorFrame.EditLabel:Hide() end
            anchorFrame:Hide()
            ClearEditPreview()
            RefreshTrackedUnits()
        end
    end

    function Mod:RefreshVisuals()
        EnsureAnchorFrame()
        EnsureGroupFrame()
        styleRevision = styleRevision + 1
        MarkLayoutDirty()
        if isEditMode then
            ShowStaticEditPreview()
        else
            RefreshTrackedUnits()
        end
    end

    function Mod:IsEditMode()
        return isEditMode == true
    end

    function Mod:EnterEditMode()
        EnsureAnchorFrame()
        if ExwindTools and ExwindTools.GlobalEditMode ~= true and type(ExwindTools.ToggleGlobalEditMode) == "function" then
            ExwindTools:ToggleGlobalEditMode()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    SetEditMode(true)
                end)
            else
                SetEditMode(true)
            end
            return true
        end
        SetEditMode(true)
        return true
    end

    function Mod:ExitEditMode()
        SetEditMode(false)
        if ExwindTools and ExwindTools.GlobalEditMode == true and type(ExwindTools.ToggleGlobalEditMode) == "function" then
            ExwindTools:ToggleGlobalEditMode()
            return true
        end
        return true
    end

    function Mod:ToggleEditMode()
        if self:IsEditMode() then
            return self:ExitEditMode()
        end
        return self:EnterEditMode()
    end

    function Mod:IsEnabled()
        return PanelDB().enabled ~= false
    end

    function Mod:SetEnabled(v)
        PanelDB().enabled = (v == true)
        if v == true then
            if ScanVisibleNameplates then ScanVisibleNameplates() end
            QueueTrackedUnitsRefresh()
        else
            if self:IsEditMode() then
                self:ExitEditMode()
            end
            if StopRefreshTicker then
                StopRefreshTicker()
            end
            if ResetAll then ResetAll() end
        end
    end

    local function HandleUnitAura(unit)
        if not IsModuleEnabled() then
            return
        end
        unit = NormalizeNameplateUnit(unit)
        if not unit or trackedUnits[unit] ~= true then
            return
        end
        if not IsInMaisaraCaverns() or not (UnitExists and UnitExists(unit)) then
            return
        end
        QueueUnitRefresh(unit)
    end

    RefreshUnitBar = function(unit)
        if not IsModuleEnabled() then
            HideBar(unit)
            return
        end
        local bar = barsByUnit[unit]
        if not bar then
            return
        end
        if trackedUnits[unit] ~= true then
            HideBar(unit)
            return
        end
        if not IsInMaisaraCaverns() or not (UnitExists and UnitExists(unit)) then
            trackedUnits[unit] = nil
            SetDebugState(unit, "unit-missing")
            HideBar(unit)
            return
        end
        if not IsUnitInCombat(unit) then
            SetDebugState(unit, "unit-not-in-combat")
            HideBar(unit)
            return
        end
        local runtime, resolvedNPCID, pending = ResolveUnitRuntime(unit)
        if pending == true then
            SetDebugState(unit, "pending")
            HideBar(unit)
            QueueUnitRefresh(unit)
            return
        end
        if resolvedNPCID ~= TARGET_NPC_ID then
            trackedUnits[unit] = nil
            scheduledRefreshSerialByUnit[unit] = nil
            if Observation and type(Observation.UntrackNameplate) == "function" then
                Observation.UntrackNameplate(observationState, unit, nil)
            end
            buffCountByUnit[unit] = nil
            SetDebugState(unit, "resolved-other", "npcID=" .. tostring(resolvedNPCID or "nil"))
            HideBar(unit)
            return
        end
        local currentBuffCount = CollectNormalizedBuffCount(unit)
        if currentBuffCount ~= nil then
            buffCountByUnit[unit] = currentBuffCount
            if currentBuffCount < 1 then
                SetDebugState(unit, "buff-zero-hide", "value=" .. tostring(currentBuffCount))
                HideBar(unit)
                return
            end
        end
        local absorbAmount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
        if absorbAmount == nil then
            SetDebugState(unit, "absorb-nil")
            HideBar(unit)
            return
        end
        if IsSecretValue(absorbAmount) ~= true and absorbAmount <= 0 then
            SetDebugState(unit, "absorb-zero", "value=" .. tostring(absorbAmount))
            HideBar(unit)
            return
        end

        local wasActive = bar._active == true
        ApplyBarStyle(bar)
        local shieldMaxValue = GetConfiguredShieldMaxValue()
        if bar.statusBar.SetMinMaxValues then
            if Enum and Enum.StatusBarInterpolation then
                bar.statusBar:SetMinMaxValues(0, shieldMaxValue, Enum.StatusBarInterpolation.Immediate)
            else
                bar.statusBar:SetMinMaxValues(0, shieldMaxValue)
            end
        end
        if Enum and Enum.StatusBarInterpolation then
            bar.statusBar:SetValue(absorbAmount, Enum.StatusBarInterpolation.Immediate)
        else
            bar.statusBar:SetValue(absorbAmount)
        end
        if type(bar.statusBar.SetToTargetValue) == "function" then
            bar.statusBar:SetToTargetValue()
        end
        bar.value:SetText(FormatShieldPercent(absorbAmount, shieldMaxValue))
        if IsSecretValue(absorbAmount) == true then
            SetDebugState(unit, "show", "npcID=248690 absorb=secret")
        else
            SetDebugState(unit, "show", "npcID=248690 absorb=" .. tostring(absorbAmount))
        end
        bar._active = true
        if not wasActive then
            MarkLayoutDirty()
        end
    end

    RefreshTrackedUnits = function()
        for unit in pairs(trackedUnits) do
            pendingRefreshByUnit[unit] = true
        end
        if StartRefreshTicker then
            StartRefreshTicker()
        end
    end

    local function TrackUnit(unit)
        unit = NormalizeNameplateUnit(unit)
        if not unit then
            return
        end
        if trackedUnits[unit] ~= true then
            DebugLog("track unit=" .. unit)
        end
        trackedUnits[unit] = true
        QueueUnitRefresh(unit)
    end

    local function UntrackUnit(unit)
        unit = NormalizeNameplateUnit(unit)
        if not unit then
            return
        end
        if trackedUnits[unit] == true then
            DebugLog("untrack unit=" .. unit)
        end
        trackedUnits[unit] = nil
        scheduledRefreshSerialByUnit[unit] = nil
        pendingRefreshByUnit[unit] = nil
        if Observation and type(Observation.UntrackNameplate) == "function" then
            Observation.UntrackNameplate(observationState, unit, nil)
        end
        buffCountByUnit[unit] = nil
        debugStateByUnit[unit] = nil
        HideBar(unit)
        FlushLayoutIfDirty()
    end

    ResetAll = function()
        for unit in pairs(trackedUnits) do
            trackedUnits[unit] = nil
        end
        for unit in pairs(scheduledRefreshSerialByUnit) do
            scheduledRefreshSerialByUnit[unit] = nil
        end
        for unit in pairs(pendingRefreshByUnit) do
            pendingRefreshByUnit[unit] = nil
        end
        if type(observationState) == "table" then
            for k in pairs(observationState) do
                observationState[k] = nil
            end
        end
        for unit in pairs(debugStateByUnit) do
            debugStateByUnit[unit] = nil
        end
        for unit in pairs(buffCountByUnit) do
            buffCountByUnit[unit] = nil
        end
        for unit in pairs(barsByUnit) do
            HideBar(unit)
        end
        FlushLayoutIfDirty()
    end

    local function ProcessPendingRefreshes()
        if not IsInMaisaraCaverns() then
            ResetAll()
            if StopRefreshTicker then
                StopRefreshTicker()
            end
            return
        end
        if not HasPendingRefresh() then
            if StopRefreshTicker then
                StopRefreshTicker()
            end
            return
        end

        BeginLayoutBatch()
        for unit in pairs(pendingRefreshByUnit) do
            pendingRefreshByUnit[unit] = nil
            RefreshUnitBar(unit)
        end
        EndLayoutBatch()

        if not HasPendingRefresh() and StopRefreshTicker then
            StopRefreshTicker()
        end
    end

    StartRefreshTicker = function()
        if refreshTicker then
            return
        end
        if not (C_Timer and type(C_Timer.NewTicker) == "function") then
            ProcessPendingRefreshes()
            return
        end
        refreshTicker = C_Timer.NewTicker(REFRESH_INTERVAL, ProcessPendingRefreshes)
    end

    StopRefreshTicker = function()
        if not refreshTicker then
            return
        end
        refreshTicker:Cancel()
        refreshTicker = nil
    end

    local function EnsureBarsInitialized()
        if next(barsByUnit) then
            return
        end
        for i = 1, MAX_NAMEPLATES do
            EnsureBar("nameplate" .. tostring(i))
        end
    end

    ScanVisibleNameplates = function()
        if PanelDB().enabled == false or not IsInMaisaraCaverns() then
            ResetAll()
            return
        end
        BeginLayoutBatch()
        for i = 1, MAX_NAMEPLATES do
            local unit = "nameplate" .. tostring(i)
            if IsHostileNameplate(unit) then
                TrackUnit(unit)
            else
                UntrackUnit(unit)
            end
        end
        EndLayoutBatch()
    end

    local function EnsureEventFrame()
        if eventFrame then
            return eventFrame
        end
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then
                if not IsModuleEnabled() then
                    return
                end
                unit = NormalizeNameplateUnit(unit)
                if unit and IsHostileNameplate(unit) then
                    TrackUnit(unit)
                elseif unit then
                    UntrackUnit(unit)
                end
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                UntrackUnit(unit)
            elseif event == "UNIT_AURA" then
                HandleUnitAura(unit)
            elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                ScheduleThrottledUnitRefresh(unit)
            elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
                EnsureBarsInitialized()
                ScanVisibleNameplates()
            end
        end)
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        eventFrame:RegisterEvent("UNIT_AURA")
        eventFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        return eventFrame
    end

    EnsureSupplementalTraitRow()
    EnsureAnchorFrame()
    EnsureGroupFrame()
    EnsureBarsInitialized()
    EnsureEventFrame()
    if ExwindTools and type(ExwindTools.RegisterEditModeCallback) == "function" then
        ExwindTools:RegisterEditModeCallback(MODULE_KEY, SetEditMode)
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("PLAYER_REGEN_DISABLED", MODULE_EVENT_PREFIX .. "_regen_start", function()
            ScanVisibleNameplates()
            QueueTrackedUnitsRefresh()
        end)
        ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_EVENT_PREFIX .. "_regen", function()
            ScanVisibleNameplates()
            QueueTrackedUnitsRefresh()
        end)
    end
end
