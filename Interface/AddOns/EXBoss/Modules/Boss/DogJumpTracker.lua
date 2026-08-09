---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local Mod = ExBoss.Modules.Boss.DogJumpTracker or {}
ExBoss.Modules.Boss.DogJumpTracker = Mod
local BorderUtil = ExBoss.BorderUtil
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local MODULE_KEY = "ExBoss.Boss.DogJumpTracker"
local ENCOUNTER_ID = 2066
local EVENT_ID = 237
local MAX_AURAS = 40
local PRE_WINDOW = 1
local POST_WINDOW = 3
local PANEL_WIDTH = 260
local PANEL_HEIGHT = 64
local PREVIEW_CLASS_IDS = { 6, 8, 11, 2, 4, 7, 12, 13, 10 }
local CANDIDATE_GLOW_KEY = "dogJump.candidates"
local CURRENT_GLOW_KEY = "dogJump.current"
local CANDIDATE_GLOW_DURATION = 5
local CURRENT_GLOW_DURATION = 5
local CANDIDATE_GLOW_COLOR = { 1, 0.85, 0.05, 1 }
local CURRENT_GLOW_COLOR = { 1, 0.05, 0.05, 1 }
local DEFAULTS = {
    enabled = true,
    preview = false,
    panelX = 360,
    panelY = 120,
}

Mod.currentEncounterID = Mod.currentEncounterID
Mod.activeUntil = Mod.activeUntil or 0
Mod.windowID = Mod.windowID or 0
Mod.windowResolved = Mod.windowResolved == true
Mod.auraCache = Mod.auraCache or {}
Mod.recentAdds = Mod.recentAdds or {}
Mod.lastTargets = Mod.lastTargets or {}
Mod.currentTarget = Mod.currentTarget
Mod.userClosed = Mod.userClosed == true
-- 缓存的候选 unit 列表（最近一次 BuildCandidates 的结果）
Mod.lastCandidateUnits = Mod.lastCandidateUnits or {}

local function DB()
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, db = pcall(ExwindTools.GetModuleDB, ExwindTools, MODULE_KEY, DEFAULTS)
        if ok and type(db) == "table" then
            if db.enabled == nil then db.enabled = DEFAULTS.enabled end
            if db.preview == nil then db.preview = DEFAULTS.preview end
            return db
        end
    end
    ExBossDB = ExBossDB or {}
    ExBossDB.bossModules = ExBossDB.bossModules or {}
    ExBossDB.bossModules.dogJumpTracker = ExBossDB.bossModules.dogJumpTracker or {}
    local db = ExBossDB.bossModules.dogJumpTracker
    if db.enabled == nil then db.enabled = DEFAULTS.enabled end
    if db.preview == nil then db.preview = DEFAULTS.preview end
    return db
end

local function PublishSettingsState()
    if ExwindTools and type(ExwindTools.UpdateState) == "function" then
        ExwindTools:UpdateState(MODULE_KEY .. ".SettingsChanged", GetTime and GetTime() or 0)
    end
end

function Mod:IsEnabled()
    return DB().enabled ~= false
end

function Mod:IsPreviewing()
    return DB().preview == true
end

local function Now()
    return GetTime and GetTime() or 0
end

local function SavePanelPosition(frame)
    local db = DB()
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if left == nil or bottom == nil then return end
    db.panelX = left + frame:GetWidth() / 2 - UIParent:GetWidth() / 2
    db.panelY = bottom + frame:GetHeight() / 2 - UIParent:GetHeight() / 2
end

local function RestorePanelPosition(frame)
    local db = DB()
    frame:ClearAllPoints()
    local x = db.panelX ~= nil and db.panelX or DEFAULTS.panelX
    local y = db.panelY ~= nil and db.panelY or DEFAULTS.panelY
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function ApplyFont(fs, size, r, g, b, a)
    if not fs then
        return
    end
    local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(font, size or 14, "OUTLINE")
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function IsTrackedUnit(unit)
    if unit == "player" then
        return true
    end
    return type(unit) == "string" and unit:match("^party[1-4]$") ~= nil
end

local function UnitDisplayName(unit)
    local name = UnitName(unit)
    if type(name) ~= "string" or name == "" then
        return tostring(unit)
    end
    if Ambiguate then
        return Ambiguate(name, "short") or name
    end
    return name
end

local function ClassColorHexByID(classID)
    local EXDB = _G.EXDB
    if EXDB and EXDB.Classes and EXDB.Classes[classID] then
        return EXDB.Classes[classID].colorHex
    end
    return "FFFFFF"
end

local function ClassColorHexByUnit(unit)
    if not UnitExists(unit) then
        return "FFFFFF"
    end
    local _, classFile = UnitClass(unit)
    if not classFile then
        return "FFFFFF"
    end
    local EXDB = _G.EXDB
    if EXDB and EXDB.Classes then
        for _, info in pairs(EXDB.Classes) do
            if info.nameEN == classFile then
                return info.colorHex
            end
        end
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] and RAID_CLASS_COLORS[classFile].colorStr then
        return RAID_CLASS_COLORS[classFile].colorStr:sub(3)
    end
    return "FFFFFF"
end

local function ColorizeName(name, hex)
    if type(name) ~= "string" or name == "" then
        return name or ""
    end
    return string.format("|cff%s%s|r", hex or "FFFFFF", name)
end

local function ColorizeUnitName(unit)
    local name = UnitDisplayName(unit)
    return ColorizeName(name, ClassColorHexByUnit(unit))
end

local function PreviewName(index)
    local name = UnitName("player") or "玩家"
    if Ambiguate then
        name = Ambiguate(name, "short") or name
    end
    local classID = PREVIEW_CLASS_IDS[((index - 1) % #PREVIEW_CLASS_IDS) + 1]
    return ColorizeName(name, ClassColorHexByID(classID))
end

local function GetTrackedUnits()
    local units = { "player" }
    for i = 1, 4 do
        units[#units + 1] = "party" .. i
    end
    return units
end

local function SafeAuraInstanceID(aura)
    if type(aura) ~= "table" then
        return nil
    end
    local ok, value = pcall(function()
        return aura.auraInstanceID
    end)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function GetHarmfulAuraIDs(unit)
    local ids = {}
    if not UnitExists(unit) then
        return ids
    end
    local fn = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
    if type(fn) ~= "function" then
        return ids
    end
    for index = 1, MAX_AURAS do
        local ok, aura = pcall(fn, unit, index, "HARMFUL")
        if not ok or not aura then
            break
        end
        local auraInstanceID = SafeAuraInstanceID(aura)
        if auraInstanceID then
            ids[auraInstanceID] = true
        end
    end
    return ids
end

local function TrimRecentAdds(now)
    local keepAfter = now - PRE_WINDOW - 0.5
    local recent = Mod.recentAdds
    for i = #recent, 1, -1 do
        if (tonumber(recent[i] and recent[i].at) or 0) < keepAfter then
            table.remove(recent, i)
        end
    end
end

local function PushLastTarget(name)
    if type(name) ~= "string" or name == "" then
        return
    end
    local out = {}
    out[#out + 1] = name
    for i = 1, #Mod.lastTargets do
        local old = Mod.lastTargets[i]
        if old ~= name and #out < 2 then
            out[#out + 1] = old
        end
    end
    Mod.lastTargets = out
end

-- 返回候选 unit 列表（排除坦克 + 排除最近两次被跳的人）
local function BuildCandidateUnits()
    local blocked = {}
    for i = 1, #Mod.lastTargets do
        blocked[Mod.lastTargets[i]] = true
    end
    local result = {}
    local units = GetTrackedUnits()
    for i = 1, #units do
        local unit = units[i]
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) ~= "TANK" then
            local name = UnitDisplayName(unit)
            if not blocked[name] then
                result[#result + 1] = unit
            end
        end
    end
    return result
end

local function BuildCandidateText()
    local units = BuildCandidateUnits()
    if #units == 0 then
        return L["无"]
    end
    local names = {}
    for i = 1, #units do
        names[#names + 1] = ColorizeUnitName(units[i])
    end
    return table.concat(names, " / ")
end

local function PartyGlow()
    return ExBoss and ExBoss.Display and ExBoss.Display.PartyFrameGlow or nil
end

local function BuildDogJumpGlowOpts(color, duration)
    local opts = {
        color = color,
        duration = duration,
    }

    local Glow = PartyGlow()
    if Glow and type(Glow.GetDB) == "function" then
        local db = Glow.GetDB()
        if db then
            opts.useGlobalSettings = true
            if db.glowEnabled == false then
                opts.enabled = false
            end
        end
    end

    return opts
end

local function HideCandidateGlow()
    local Glow = PartyGlow()
    if Glow and Glow.Hide then
        Glow.Hide(CANDIDATE_GLOW_KEY)
    end
    Mod.lastCandidateUnits = {}
end

local function HideCurrentGlow()
    local Glow = PartyGlow()
    if Glow and Glow.Hide then
        Glow.Hide(CURRENT_GLOW_KEY)
    end
end

local function ShowCandidateGlow(units)
    local Glow = PartyGlow()
    if not (Glow and Glow.ShowUnits) then
        return
    end
    Glow.ShowUnits(CANDIDATE_GLOW_KEY, units or {}, BuildDogJumpGlowOpts(CANDIDATE_GLOW_COLOR, CANDIDATE_GLOW_DURATION))
end

local function ShowCurrentGlow(unit)
    local Glow = PartyGlow()
    if not (Glow and Glow.ShowUnits and unit) then
        return
    end
    Glow.ShowUnits(CURRENT_GLOW_KEY, { unit }, BuildDogJumpGlowOpts(CURRENT_GLOW_COLOR, CURRENT_GLOW_DURATION))
end

local function CreatePanel()
    if Mod.panel then
        return Mod.panel
    end

    local frame = CreateFrame("Frame", "ExBoss_DogJumpTrackerPanel", UIParent)
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    RestorePanelPosition(frame)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePanelPosition(self)
    end)
    frame.bg = frame.bg or frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.bg:SetVertexColor(0, 0, 0, 0.38)
    frame.border = frame.border or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.border:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    frame.border:ClearAllPoints()
    frame.border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.border:SetBackdropBorderColor(0.1, 0.85, 1, 0.55)
    frame.border:Show()
    frame:Hide()

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    close.text = close:CreateFontString(nil, "OVERLAY")
    close.text:SetPoint("CENTER")
    ApplyFont(close.text, 14, 1, 0.35, 0.35, 1)
    close.text:SetText("X")
    close:SetScript("OnClick", function()
        if Mod:IsPreviewing() then
            Mod:SetPreview(false)
            return
        end
        Mod.userClosed = true
        frame:Hide()
    end)
    frame.close = close

    local current = frame:CreateFontString(nil, "OVERLAY")
    current:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    current:SetJustifyH("LEFT")
    current:SetWidth(PANEL_WIDTH - 30)
    ApplyFont(current, 14, 1, 0.9, 0.35, 1)
    frame.current = current

    local candidates = frame:CreateFontString(nil, "OVERLAY")
    candidates:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -9)
    candidates:SetJustifyH("LEFT")
    candidates:SetWidth(PANEL_WIDTH - 20)
    ApplyFont(candidates, 13, 0.9, 0.95, 1, 1)
    frame.candidates = candidates

    Mod.panel = frame
    return frame
end

function Mod:UpdatePanel()
    local frame = CreatePanel()
    if self:IsPreviewing() then
        frame.current:SetText(L["当前:"] .. " " .. PreviewName(1))
        frame.candidates:SetText(L["下次:"] .. " " .. PreviewName(2) .. " / " .. PreviewName(3))
        frame:Show()
        return
    end
    local currentText
    if self.currentTarget then
        local hex = ClassColorHexByUnit(self.currentTargetUnit or "")
        currentText = ColorizeName(self.currentTarget, hex)
    else
        currentText = L["等待识别"]
    end
    frame.current:SetText(L["当前:"] .. " " .. currentText)
    frame.candidates:SetText(L["下次:"] .. " " .. BuildCandidateText())
    if self:IsEnabled() and self.currentEncounterID == ENCOUNTER_ID and not self.userClosed then
        frame:Show()
    else
        frame:Hide()
    end
end

function Mod:SetEnabled(enabled)
    DB().enabled = enabled == true
    if not self:IsEnabled() then
        self:EndEncounter()
    else
        self:UpdatePanel()
    end
    PublishSettingsState()
end

function Mod:SetPreview(enabled)
    DB().preview = enabled == true
    if self:IsPreviewing() then
        self:ShowPreviewGlow()
    else
        HideCandidateGlow()
    end
    self:UpdatePanel()
    PublishSettingsState()
end

function Mod:RefreshSettings()
    if self:IsPreviewing() then
        self:ShowPreviewGlow()
    elseif self.currentEncounterID == ENCOUNTER_ID and not self.windowResolved then
        self:ShowCandidateGlow()
    end
    self:UpdatePanel()
end

function Mod:RecordTarget(unit)
    if not self:IsEnabled() then
        return
    end
    if self.windowResolved then
        return
    end
    if self.currentEncounterID ~= ENCOUNTER_ID then
        return
    end
    if not UnitExists(unit) or UnitGroupRolesAssigned(unit) == "TANK" then
        return
    end
    local name = UnitDisplayName(unit)
    self.windowResolved = true
    self.currentTarget = name
    self.currentTargetUnit = unit
    PushLastTarget(name)
    HideCandidateGlow()
    ShowCurrentGlow(unit)
    self:UpdatePanel()
end

function Mod:RefreshUnit(unit, seedOnly)
    if not self:IsEnabled() then
        return
    end
    if not IsTrackedUnit(unit) or not UnitExists(unit) then
        self.auraCache[unit] = nil
        return
    end

    local now = Now()
    local old = self.auraCache[unit] or {}
    local current = GetHarmfulAuraIDs(unit)
    self.auraCache[unit] = current

    if seedOnly then
        return
    end

    TrimRecentAdds(now)
    for auraInstanceID in pairs(current) do
        if not old[auraInstanceID] then
            local row = { unit = unit, id = auraInstanceID, at = now }
            self.recentAdds[#self.recentAdds + 1] = row
            if now <= (tonumber(self.activeUntil) or 0) then
                self:RecordTarget(unit)
            end
        end
    end
end

function Mod:RefreshGroup(seedOnly)
    local units = GetTrackedUnits()
    for i = 1, #units do
        self:RefreshUnit(units[i], seedOnly)
    end
end

function Mod:StartWindow()
    if not self:IsEnabled() then
        return
    end
    if self.currentEncounterID ~= ENCOUNTER_ID then
        return
    end

    local now = Now()
    self.windowID = (tonumber(self.windowID) or 0) + 1
    self.windowResolved = false
    self.activeUntil = now + POST_WINDOW
    TrimRecentAdds(now)

    for i = #self.recentAdds, 1, -1 do
        local row = self.recentAdds[i]
        local at = tonumber(row and row.at) or 0
        if at >= (now - PRE_WINDOW) and at <= (now + POST_WINDOW) and row.unit then
            self:RecordTarget(row.unit)
            break
        end
    end

    if not self.windowResolved then
        self:ShowCandidateGlow()
    end
end

function Mod:OnBossTimerCast(timer)
    if not self:IsEnabled() then
        return
    end
    if self.currentEncounterID ~= ENCOUNTER_ID then
        return
    end
    if tonumber(timer and timer.eventID) ~= EVENT_ID then
        return
    end
    self:StartWindow()
end

function Mod:OnBossTimerPreAlert(timer)
    if not self:IsEnabled() then
        return
    end
    if self.currentEncounterID ~= ENCOUNTER_ID then
        return
    end
    if tonumber(timer and timer.eventID) ~= EVENT_ID then
        return
    end
    self:ShowCandidateGlow()
end

function Mod:StartEncounter(encounterID)
    if not self:IsEnabled() then
        if self.panel then
            self.panel:Hide()
        end
        return
    end
    self.currentEncounterID = tonumber(encounterID)
    self.activeUntil = 0
    self.windowResolved = false
    self.auraCache = {}
    self.recentAdds = {}
    self.lastTargets = {}
    self.currentTarget = nil
    self.currentTargetUnit = nil
    self.userClosed = false
    HideCandidateGlow()
    HideCurrentGlow()
    if self.currentEncounterID == ENCOUNTER_ID then
        self:UpdatePanel()
        C_Timer.After(0.2, function()
            Mod:RefreshGroup(true)
            Mod:UpdatePanel()
        end)
    elseif self.panel then
        self.panel:Hide()
    end
end

function Mod:EndEncounter()
    self.currentEncounterID = nil
    self.activeUntil = 0
    self.windowResolved = false
    self.auraCache = {}
    self.recentAdds = {}
    self.lastTargets = {}
    self.currentTarget = nil
    self.currentTargetUnit = nil
    self.userClosed = false
    HideCandidateGlow()
    HideCurrentGlow()
    if self.panel then
        self:UpdatePanel()
    end
end

function Mod:ShowCandidateGlow()
    HideCandidateGlow()
    if not self:IsEnabled() then
        return
    end
    local units = BuildCandidateUnits()
    Mod.lastCandidateUnits = units
    ShowCandidateGlow(units)
end

function Mod:ShowPreviewGlow()
    HideCandidateGlow()
    local units = GetTrackedUnits()
    local candidates = {}
    for i = 1, #units do
        if #candidates >= 2 then
            break
        end
        local unit = units[i]
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) ~= "TANK" then
            candidates[#candidates + 1] = unit
        end
    end
    Mod.lastCandidateUnits = candidates
    ShowCandidateGlow(candidates)
end

local function Register(event, owner, func)
    if ExwindTools and ExwindTools.RegisterEvent then
        ExwindTools:RegisterEvent(event, owner, func)
        return
    end
    local frame = Mod.frame or CreateFrame("Frame")
    Mod.frame = frame
    frame:RegisterEvent(event)
    frame:SetScript("OnEvent", function(_, ev, ...)
        if ev == event then
            func(ev, ...)
        end
    end)
end

Register("ENCOUNTER_START", MODULE_KEY .. ".EncounterStart", function(_, encounterID)
    Mod:StartEncounter(encounterID)
end)

Register("ENCOUNTER_END", MODULE_KEY .. ".EncounterEnd", function()
    Mod:EndEncounter()
end)

Register("GROUP_ROSTER_UPDATE", MODULE_KEY .. ".Roster", function()
    if Mod.currentEncounterID == ENCOUNTER_ID then
        Mod:RefreshGroup(true)
        Mod:UpdatePanel()
    end
end)

Register("UNIT_AURA", MODULE_KEY .. ".UnitAura", function(_, unit)
    if not Mod:IsEnabled() then
        return
    end
    if Mod.currentEncounterID ~= ENCOUNTER_ID then
        return
    end
    Mod:RefreshUnit(unit, false)
end)
