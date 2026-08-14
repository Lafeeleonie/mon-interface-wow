local _, ns = ...

ns.SlashCommands = ns.SlashCommands or {}
local SlashCommands = ns.SlashCommands

local function ToBoolean(raw)
    if type(raw) ~= "string" then
        return nil
    end

    local normalized = string.lower(raw)
    if normalized == "true" or normalized == "on" or normalized == "yes" or normalized == "1" then
        return true
    end

    if normalized == "false" or normalized == "off" or normalized == "no" or normalized == "0" then
        return false
    end

    return nil
end

local function ParseValue(raw)
    if type(raw) == "string" and string.find(raw, ",", 1, true) then
        local color = {}
        for segment in string.gmatch(raw, "[^,]+") do
            local number = tonumber((segment:gsub("^%s+", ""):gsub("%s+$", "")))
            if number == nil then
                color = nil
                break
            end
            color[#color + 1] = number
        end
        if color and (#color == 3 or #color == 4) then
            if #color == 3 then
                color[4] = 1
            end
            return color
        end
    end

    local boolValue = ToBoolean(raw)
    if boolValue ~= nil then
        return boolValue
    end

    local numberValue = tonumber(raw)
    if numberValue ~= nil then
        return numberValue
    end

    return raw
end

-- Convenience aliases so typing /thyrax module xhair off (or any of the
-- shorter/concatenated forms below) resolves to the real underscored id.
-- Resolution is case-insensitive (see ResolveModuleID) so users don't have
-- to remember capitalisation either.
local MODULE_ALIASES = {
    -- Quest hotkey
    questaccepthotkey = "quest_accept_hotkey",
    quest_hotkey      = "quest_accept_hotkey",
    quest             = "quest_accept_hotkey",
    qh                = "quest_accept_hotkey",
    -- Crosshair
    xhair             = "crosshair",
    -- Mouse tracker
    mouse             = "mouse_tracker",
    mousetracker      = "mouse_tracker",
    mt                = "mouse_tracker",
    -- Darkness announcer
    darkness          = "darkness_announcer",
    da                = "darkness_announcer",
    -- Dynamic flight tracker
    flight            = "dynamic_flight_tracker",
    flighttracker     = "dynamic_flight_tracker",
    dynamicflighttracker = "dynamic_flight_tracker",
    dft               = "dynamic_flight_tracker",
    -- Auction filter persist
    ah                = "auction_filter_persist",
    auctionfilter     = "auction_filter_persist",
    afp               = "auction_filter_persist",
    -- Accounting
    accounting        = "accounting_tracker",
    ledger            = "accounting_tracker",
    acc               = "accounting_tracker",
    -- Character panel enhancer
    character         = "character_panel_enhancer",
    char              = "character_panel_enhancer",
    gear              = "character_panel_enhancer",
    readiness         = "character_panel_enhancer",
    cpe               = "character_panel_enhancer",
}

local function Tokenize(message)
    local tokens = {}
    local text = tostring(message or "")
    local current = {}
    local inQuotes = false
    local escapeNext = false

    local function PushToken()
        if #current > 0 then
            tokens[#tokens + 1] = table.concat(current)
            current = {}
        end
    end

    for index = 1, #text do
        local ch = text:sub(index, index)
        if escapeNext then
            current[#current + 1] = ch
            escapeNext = false
        elseif ch == "\\" and inQuotes then
            escapeNext = true
        elseif ch == "\"" then
            inQuotes = not inQuotes
            if not inQuotes then
                PushToken()
            end
        elseif ch:match("%s") and not inQuotes then
            PushToken()
        else
            current[#current + 1] = ch
        end
    end

    PushToken()
    return tokens
end

local function ResolveModuleID(rawID)
    if type(rawID) ~= "string" then
        return nil
    end

    local lowerRaw = string.lower(rawID)
    if MODULE_ALIASES[lowerRaw] then
        lowerRaw = MODULE_ALIASES[lowerRaw]
    end
    for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
        if string.lower(moduleID) == lowerRaw then
            return moduleID
        end
    end

    return nil
end

-- Minimal help: only the commands a typical user needs. Power-user / debug
-- commands are reachable via /thyrax help all. Keeps the default chat dump
-- short so the user isn't overwhelmed.
function SlashCommands:PrintHelp()
    ns.Diagnostics:Info("ThyraxUtil:")
    ns.Diagnostics:Info("  /thyrax              open options")
    ns.Diagnostics:Info("  /thyrax status       list modules")
    ns.Diagnostics:Info("  /thyrax module <id> on|off")
    ns.Diagnostics:Info("  /thyrax accounting   open ledger (if enabled)")
    ns.Diagnostics:Info("  /thyrax help all     show all commands")
end

function SlashCommands:PrintHelpAll()
    ns.Diagnostics:Info("ThyraxUtil all commands:")
    ns.Diagnostics:Info("  /thyrax options [id]   open options (optionally jump to module)")
    ns.Diagnostics:Info("  /thyrax status         list modules")
    ns.Diagnostics:Info("  /thyrax global on|off")
    ns.Diagnostics:Info("  /thyrax module <id> on|off")
    ns.Diagnostics:Info("  /thyrax config <id> <key> <value>")
    ns.Diagnostics:Info("  /thyrax test <module|all> [seconds]")
    ns.Diagnostics:Info("  /thyrax dev on|off|toggle")
    ns.Diagnostics:Info("  /thyrax reload")
    ns.Diagnostics:Info("  /thyrax onboarding")
    ns.Diagnostics:Info("  /thyrax accounting [show|hide|summary|recent|status|clear|help]")
    ns.Diagnostics:Info("  /thyrax ahstatus       AH filter state")
    ns.Diagnostics:Info("  /thyrax ahdump         AH internals (advanced)")
end

function SlashCommands:PrintStatus()
    local globalState = ns.Settings:IsGlobalEnabled() and "on" or "off"
    ns.Diagnostics:Info(("Global: %s"):format(globalState))

    for _, status in ipairs(ns.ModuleRegistry:GetAllStatuses()) do
        local enabledText = status.enabled and "enabled" or "disabled"
        local configuredText = status.configured and "configured-on" or "configured-off"
        local availabilityText = status.available and "available" or ("blocked: " .. tostring(status.reason))
        ns.Diagnostics:Info(("%s (%s): %s, %s, %s"):format(
            status.name,
            status.id,
            enabledText,
            configuredText,
            availabilityText
        ))
    end
end

function SlashCommands:SetGlobal(raw)
    local value = ToBoolean(raw)
    if value == nil then
        ns.Diagnostics:Warn("Usage: /thyrax global on|off")
        return
    end

    ns.ModuleRegistry:SetGlobalEnabled(value)
    ns.Diagnostics:Info(("Global set to %s."):format(value and "on" or "off"))
end

function SlashCommands:SetModule(tokens)
    local moduleID = ResolveModuleID(tokens[2] or "")
    if not moduleID then
        ns.Diagnostics:Warn(("Unknown module id '%s'. Try /thyrax status."):format(tostring(tokens[2] or "")))
        return
    end

    local value = ToBoolean(tokens[3] or "")
    if value == nil then
        ns.Diagnostics:Warn("Usage: /thyrax module <id> on|off")
        return
    end

    local ok, reason = ns.ModuleRegistry:SetModuleEnabled(moduleID, value)
    if ok then
        ns.Diagnostics:Info(("Module '%s' set to %s."):format(moduleID, value and "on" or "off"))
    else
        ns.Diagnostics:Warn(("Module '%s' could not be enabled: %s"):format(moduleID, tostring(reason)))
    end
end

function SlashCommands:SetConfig(tokens)
    local moduleID = ResolveModuleID(tokens[2] or "")
    if not moduleID then
        ns.Diagnostics:Warn(("Unknown module id '%s'. Try /thyrax status."):format(tostring(tokens[2] or "")))
        return
    end

    local key = tokens[3]
    local rawValue = tokens[4]
    if #tokens > 4 then
        rawValue = table.concat(tokens, " ", 4)
    end
    if not key or not rawValue then
        ns.Diagnostics:Warn("Usage: /thyrax config <id> <key> <value>")
        return
    end

    -- Reject typo'd keys before they land in SavedVariables as orphans the
    -- user will never notice. Only known module-default keys are accepted
    -- (matches the keys the Options Panel writes).
    local module = ns.ModuleRegistry:GetModule(moduleID)
    if module and type(module.defaults) == "table" and module.defaults[key] == nil then
        ns.Diagnostics:Warn(("Unknown setting '%s' for module '%s'. Check the Options Panel for valid keys."):format(tostring(key), moduleID))
        return
    end

    local value = ParseValue(rawValue)
    ns.Settings:SetModuleValue(moduleID, key, value)

    if key == "enabled" then
        ns.ModuleRegistry:SetModuleEnabled(moduleID, value and true or false)
    else
        ns.ModuleRegistry:ApplyModuleSettings(moduleID)
    end

    ns.Diagnostics:Info(("Config updated: %s.%s = %s"):format(moduleID, key, tostring(value)))
end

function SlashCommands:SetDeveloperMode(raw)
    local normalized = string.lower(raw or "toggle")
    local value

    if normalized == "" or normalized == "toggle" then
        value = not ns.Settings:IsDeveloperModeEnabled()
    else
        value = ToBoolean(normalized)
    end

    if value == nil then
        ns.Diagnostics:Warn("Usage: /thyrax dev on|off|toggle")
        return
    end

    ns.Settings:SetDeveloperModeEnabled(value)
    if ns.DeveloperMode and ns.DeveloperMode.SetEnabled then
        ns.DeveloperMode:SetEnabled(value)
    end

    ns.Diagnostics:Info(("Developer mode set to %s."):format(value and "on" or "off"))
end

function SlashCommands:RunTest(tokens)
    local rawTarget = tokens[2] or "all"
    local target = string.lower(rawTarget)
    local durationSeconds = tonumber(tokens[3]) or 3
    local moduleIDs = {}

    if target == "all" then
        moduleIDs = ns.ModuleRegistry:GetModuleIDs()
    else
        local moduleID = ResolveModuleID(rawTarget)
        if not moduleID then
            ns.Diagnostics:Warn("Usage: /thyrax test <module|all> [seconds]")
            return
        end
        moduleIDs[1] = moduleID
    end

    local executed = 0
    local skippedDisabled = 0
    local lastModule
    for _, moduleID in ipairs(moduleIDs) do
        local module = ns.ModuleRegistry:GetModule(moduleID)
        if module and type(module.RunTest) == "function" then
            -- RunTest assumes the state that OnEnable sets up (update frames,
            -- timers, baselines). Running it on a disabled module either
            -- errors on nil state or leaves the test overlay stuck on screen
            -- with no event loop to hide it again -- so disabled modules are
            -- skipped instead.
            if ns.ModuleRegistry:IsModuleEnabled(moduleID) then
                executed = executed + 1
                lastModule = moduleID
                ns.Diagnostics:SafeCall(moduleID .. ":RunTest", module.RunTest, module, durationSeconds)
            else
                skippedDisabled = skippedDisabled + 1
            end
        end
    end

    -- One summary line instead of one chat line per module, so /thyrax test
    -- all doesn't bury the user under 7 lines of noise.
    if executed == 0 then
        if skippedDisabled > 0 then
            ns.Diagnostics:Warn("No test ran: the matching module(s) are disabled. Enable them first (/thyrax module <id> on).")
        else
            ns.Diagnostics:Warn("No testable modules were found for that target.")
        end
    elseif executed == 1 then
        ns.Diagnostics:Info(("Test triggered for module: %s"):format(tostring(lastModule)))
    else
        ns.Diagnostics:Info(("Test triggered for %d modules."):format(executed))
    end
end

function SlashCommands:Handle(message)
    local tokens = Tokenize(message)
    -- Empty input (just `/thyrax`) opens the options panel directly: most
    -- users want the UI, not a help dump. Help is still reachable explicitly.
    local rawCommand = tokens[1]
    if not rawCommand or rawCommand == "" then
        self:RequestOptionsOpen()
        return
    end
    local command = string.lower(rawCommand)

    if command == "help" then
        local sub = string.lower(tokens[2] or "")
        if sub == "all" or sub == "full" or sub == "advanced" then
            self:PrintHelpAll()
        else
            self:PrintHelp()
        end
        return
    end

    if command == "status" then
        self:PrintStatus()
        return
    end

    if command == "global" then
        self:SetGlobal(tokens[2])
        return
    end

    if command == "module" then
        self:SetModule(tokens)
        return
    end

    if command == "config" then
        self:SetConfig(tokens)
        return
    end

    if command == "dev" then
        self:SetDeveloperMode(tokens[2])
        return
    end

    if command == "test" then
        self:RunTest(tokens)
        return
    end

    if command == "reload" then
        ns.ModuleRegistry:ReloadAll()
        ns.Diagnostics:Info("Modules reloaded.")
        return
    end

    if command == "options" then
        -- Optional second token jumps to a specific module's page so
        -- `/thyrax options flight` lands on the Dynamic Flight Tracker
        -- options without an extra tab click.
        local rawTarget = tokens[2]
        local moduleID
        if rawTarget and rawTarget ~= "" then
            moduleID = ResolveModuleID(rawTarget)
            if not moduleID then
                ns.Diagnostics:Warn(("Unknown module id '%s'. Opening main options."):format(tostring(rawTarget)))
            end
        end
        self:RequestOptionsOpen(moduleID)
        return
    end

    if command == "onboarding" then
        self:ShowOnboarding()
        return
    end

    if command == "ahdump" then
        local mod = ns.ModuleRegistry and ns.ModuleRegistry:GetModule("auction_filter_persist")
        if mod and mod.DumpAHStructure then
            mod:DumpAHStructure()
        else
            ns.Diagnostics:Warn("AH Filter Persist module is not loaded.")
        end
        return
    end

    if command == "ahstatus" then
        local mod = ns.ModuleRegistry and ns.ModuleRegistry:GetModule("auction_filter_persist")
        if mod and mod.PrintStatus then
            mod:PrintStatus()
        else
            ns.Diagnostics:Warn("AH Filter Persist module is not loaded.")
        end
        return
    end

    if command == "accounting" or command == "ledger" then
        local mod = ns.ModuleRegistry and ns.ModuleRegistry:GetModule("accounting_tracker")
        if mod and mod.HandleSlash then
            mod:HandleSlash(tokens)
        else
            ns.Diagnostics:Warn("Accounting module is not loaded.")
        end
        return
    end

    ns.Diagnostics:Warn(("Unknown command '%s'. Try /thyrax help."):format(tostring(rawCommand)))
end

function SlashCommands:EnsureCombatQueueFrame()
    if self.combatQueueFrame then
        return
    end

    self.combatQueueFrame = CreateFrame("Frame")
    self.combatQueueFrame:SetScript("OnEvent", function()
        if not SlashCommands.pendingOptionsOpen then return end
        local moduleID = SlashCommands.pendingOptionsModuleID
        SlashCommands.pendingOptionsOpen = false
        SlashCommands.pendingOptionsModuleID = nil
        SlashCommands.combatQueueFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        SlashCommands:RequestOptionsOpen(moduleID)
    end)
end

function SlashCommands:RequestOptionsOpen(moduleID)
    if not ns.OptionsPanel or not ns.OptionsPanel.Open then
        ns.Diagnostics:Warn("Options panel is not available.")
        return
    end

    if ns.Compat.IsInCombat() then
        self.pendingOptionsOpen = true
        self.pendingOptionsModuleID = moduleID
        self:EnsureCombatQueueFrame()
        self.combatQueueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.Diagnostics:Warn("Options cannot open in combat. Queued for after combat.")
        return
    end

    if self.combatQueueFrame then
        self.combatQueueFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end

    self.pendingOptionsOpen = false
    self.pendingOptionsModuleID = nil
    local ok, reason = ns.OptionsPanel:Open(moduleID)
    if not ok then
        ns.Diagnostics:Warn(("Unable to open options (%s)."):format(tostring(reason)))
    end
end

function SlashCommands:ShowOnboarding()
    if not ns.Onboarding or not ns.Onboarding.ShowForTesting then
        ns.Diagnostics:Warn("Onboarding is not available.")
        return
    end

    if ns.Compat.IsInCombat() then
        ns.Diagnostics:Warn("Onboarding cannot open in combat.")
        return
    end

    local ok, reason = ns.Onboarding:ShowForTesting()
    if not ok then
        ns.Diagnostics:Warn(("Unable to open onboarding (%s)."):format(tostring(reason)))
    end
end

function SlashCommands:Initialize()
    if self.initialized then
        return
    end

    SLASH_THYRAXUTIL1 = "/thyrax"
    SLASH_THYRAXUTIL2 = "/thyraxutil"
    SLASH_THYRAXUTIL3 = "/tutil"
    SlashCmdList.THYRAXUTIL = function(message)
        SlashCommands:Handle(message)
    end

    self.initialized = true
end
