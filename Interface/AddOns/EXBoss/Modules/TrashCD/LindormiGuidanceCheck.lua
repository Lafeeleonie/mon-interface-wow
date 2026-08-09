---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.LindormiGuidanceCheck or {}
ExBoss.TrashCD.LindormiGuidanceCheck = Mod

local MODULE_KEY = "ExBoss.TrashCD.LindormiGuidanceCheck"
local POPUP_KEY = "EXBOSS_LINDORMI_GUIDANCE_WARNING"
local AURA_SPELL_ID = 1295927
local CHECK_DELAY = 5
local ROSTER_CHECK_DELAY = 1
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

Mod._scheduledToken = tonumber(Mod._scheduledToken) or 0
Mod._warningActive = Mod._warningActive == true

local function GetPrintAPI()
    return ExBoss and ExBoss.Print or nil
end

local function GetWarningMessage()
    return "|cffff3333" ..
        tostring(L["检测到玩家(或是队友) 已经开启\"林多尔米指引\"(Lindormi's Guidance)的功能,此功能会导致小怪内置CD失效/乱报\n请回到主城降钥石NPC(传送门旁边) 对话关闭"]) ..
        "|r"
end

local function EnsureWarningPopup()
    if type(StaticPopupDialogs) ~= "table" or StaticPopupDialogs[POPUP_KEY] then
        return
    end
    StaticPopupDialogs[POPUP_KEY] = {
        text = GetWarningMessage(),
        button1 = OKAY,
        OnAccept = function()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
end

local function ShowWarning()
    local msg = GetWarningMessage()
    EnsureWarningPopup()
    if type(StaticPopup_Show) == "function" then
        StaticPopup_Show(POPUP_KEY)
        return
    end
    local api = GetPrintAPI()
    if api and type(api.Say) == "function" then
        api.Say(msg)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff<EXBOSS>|r " .. msg)
    end
end

local function HasAuraOnUnit(unit)
    if type(unit) ~= "string" or not UnitExists or not UnitExists(unit) then
        return false
    end
    if not (C_UnitAuras and type(C_UnitAuras.GetUnitAuraBySpellID) == "function") then
        return false
    end
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, AURA_SPELL_ID)
    return ok and aura ~= nil
end

local function HasAuraOnPlayer()
    if not (C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function") then
        return false
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, AURA_SPELL_ID)
    return ok and aura ~= nil
end

local function IsTankRole(unit)
    if type(unit) ~= "string" or not UnitExists or not UnitExists(unit) then
        return false
    end
    if type(UnitGroupRolesAssigned) ~= "function" then
        return false
    end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return ok and role == "TANK"
end

local function FindAuraTankUnit()
    if IsTankRole("player") and HasAuraOnPlayer() then
        return "player"
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if IsTankRole(unit) and HasAuraOnUnit(unit) then
            return unit
        end
    end
    return nil
end

function Mod:CheckNow()
    if not (C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function") then
        return
    end
    local ok, shouldBeSecret = pcall(C_Secrets.ShouldAurasBeSecret)
    if not ok or shouldBeSecret ~= false then
        return
    end
    local activeUnit = FindAuraTankUnit()
    if activeUnit then
        if self._warningActive ~= true then
            self._warningActive = true
            if type(StaticPopup_Visible) ~= "function" or not StaticPopup_Visible(POPUP_KEY) then
                ShowWarning()
            end
        end
        return
    end
    self._warningActive = false
end

function Mod:ScheduleCheck(delay)
    self._scheduledToken = (tonumber(self._scheduledToken) or 0) + 1
    local token = self._scheduledToken
    local wait = tonumber(delay) or CHECK_DELAY
    if wait < 0 then
        wait = 0
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(wait, function()
            if Mod._scheduledToken ~= token then
                return
            end
            Mod:CheckNow()
        end)
    else
        self:CheckNow()
    end
end

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. ".PEW", function()
        Mod:ScheduleCheck(CHECK_DELAY)
    end)
    ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", MODULE_KEY .. ".Roster", function()
        Mod:ScheduleCheck(ROSTER_CHECK_DELAY)
    end)
    ExwindTools:RegisterEvent("PLAYER_ROLES_ASSIGNED", MODULE_KEY .. ".Roles", function()
        Mod:ScheduleCheck(ROSTER_CHECK_DELAY)
    end)
end
