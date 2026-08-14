local addonName, addon = ...
local L = addon.L

local function PrintStandalone(message)
    local text = string.format("|cff2eb7e6%s|r: %s", L.ADDON_NAME, message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

if not ElvUI then
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        PrintStandalone(L.ELVUI_MISSING)
    end)
    return
end

local E, _, _, P = unpack(ElvUI)
local AceAddon = E.Libs and E.Libs.AceAddon
local EP = E.Libs and E.Libs.EP

if not AceAddon or not EP or not E.CreateMover or not E.ConfigMode_AddGroup then
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        PrintStandalone(L.ELVUI_INCOMPATIBLE)
    end)
    return
end

local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 180

P.lecf = {
    enabled = true,
    frameCount = 1,
    debug = false,
    frames = {
        { enabled = true, name = "", width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, backdrop = true, locked = true, chatWindowID = 0 },
        { enabled = true, name = "", width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, backdrop = true, locked = true, chatWindowID = 0 },
        { enabled = true, name = "", width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, backdrop = true, locked = true, chatWindowID = 0 },
        { enabled = true, name = "", width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, backdrop = true, locked = true, chatWindowID = 0 },
    },
}

local LECF = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0")

addon.LECF = LECF
LECF.addonName = addonName
LECF.E = E
LECF.EP = EP
LECF.L = L
LECF.MAX_FRAMES = 4
LECF.MIN_WIDTH = 220
LECF.MAX_WIDTH = 900
LECF.MIN_HEIGHT = 100
LECF.MAX_HEIGHT = 600
LECF.MIN_ELVUI_VERSION = 15.18

function LECF:Print(message)
    E:Print(string.format("|cff2eb7e6%s|r: %s", L.ADDON_NAME, message))
end

function LECF:Debug(message, ...)
    if not self.db or not self.db.debug then
        return
    end

    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    self:Print(string.format("|cff80dfff%s|r", message))
end

function LECF:IsElvUICompatible()
    local version = tonumber(E.version)
    return E.CreateMover
        and E.ConfigMode_AddGroup
        and EP.RegisterPlugin
        and (not version or version >= self.MIN_ELVUI_VERSION)
end

function LECF:RefreshDatabase()
    self.db = E.db.lecf
end

function LECF:EnsurePluginOptionsGroup()
    if not C_AddOns.IsAddOnLoaded("ElvUI_Options") then
        return true
    end

    local options = E.Options
    local plugins = options and options.args and options.args.plugins
    if plugins and plugins.args and plugins.args.plugins then
        return true
    end

    if options and options.args and type(EP.GetPluginOptions) == "function" then
        return pcall(EP.GetPluginOptions, EP)
    end

    return false
end

function LECF:RegisterPluginOptions()
    self:EnsurePluginOptionsGroup()

    local callback = function()
        self:RegisterOptions()
    end
    local registered = pcall(EP.RegisterPlugin, EP, addonName, callback)

    if not registered and C_AddOns.IsAddOnLoaded("ElvUI_Options") and E.Options and E.Options.args then
        self:RegisterOptions()
        registered = true
    end

    if not registered then
        PrintStandalone(L.ELVUI_INCOMPATIBLE)
    end
end

function LECF:OnProfileChanged()
    self:RefreshDatabase()
    self:ScheduleApplyAll("PROFILE_CHANGED")
    self:RefreshOptions()
end

function LECF:PLAYER_ENTERING_WORLD()
    self:ScheduleApplyAll("PLAYER_ENTERING_WORLD")
end

function LECF:PLAYER_REGEN_ENABLED()
    self:ProcessPendingMoverResets()
    if self.pendingCombatUpdate then
        self.pendingCombatUpdate = nil
        self:ScheduleApplyAll("PLAYER_REGEN_ENABLED")
    end
end

function LECF:UPDATE_CHAT_WINDOWS()
    self:OnChatWindowsChanged("UPDATE_CHAT_WINDOWS")
end

function LECF:UPDATE_FLOATING_CHAT_WINDOWS()
    self:OnChatWindowsChanged("UPDATE_FLOATING_CHAT_WINDOWS")
end

function LECF:OpenOptions()
    E:ToggleOptions("lecf")
end

function LECF:HandleSlashCommand(input)
    local command = strtrim(string.lower(input or ""))
    if command == "" or command == "config" then
        self:OpenOptions()
    elseif command == "reset" then
        self:ShowResetAllConfirmation()
    else
        self:Print(L.COMMAND_HELP)
    end
end

function LECF:RegisterSlashCommands()
    SLASH_LAFEEELVUICHATFRAME1 = "/lecf"
    SlashCmdList.LAFEEELVUICHATFRAME = function(input)
        LECF:HandleSlashCommand(input)
    end
end

function LECF:Initialize()
    if self.initialized or self.initializing then
        return
    end
    self.initializing = true

    if not self:IsElvUICompatible() then
        self.initializing = nil
        PrintStandalone(L.ELVUI_INCOMPATIBLE)
        return
    end

    self:RefreshDatabase()
    self:RegisterSlashCommands()
    self:InitializeMovers()
    self:InitializeChatFrameHooks()
    self:InitializeConfig()

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")

    E.data.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    E.data.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    E.data.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    self:RegisterPluginOptions()

    self.initialized = true
    self.initializing = nil
end

if E.initialized then
    LECF:Initialize()
else
    EP:HookInitialize(LECF, LECF.Initialize)
end
