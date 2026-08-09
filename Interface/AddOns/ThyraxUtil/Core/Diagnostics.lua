local addonName, ns = ...

ns.Diagnostics = ns.Diagnostics or {}
local Diagnostics = ns.Diagnostics
local unpack = unpack

local function Format(level, message)
    local tag = ns.displayName or addonName
    return ("|cff33ff99%s|r [%s] %s"):format(tag, level, tostring(message))
end

function Diagnostics:Info(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(Format("INFO", message))
    end
end

function Diagnostics:Warn(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(Format("WARN", message))
    end
end

function Diagnostics:Debug(message)
    if ns.Settings and ns.Settings.GetDebugSettings then
        local debugSettings = ns.Settings:GetDebugSettings()
        if debugSettings and debugSettings.verbose then
            self:Info(message)
        end
    end
end

function Diagnostics:SafeCall(label, func, ...)
    if type(func) ~= "function" then
        return true
    end

    -- Direct pcall in WoW Lua (5.1/LuaJIT) avoids table and closure creation.
    local ok, a, b, c = pcall(func, ...)

    if not ok then
        local errorMsg = tostring(a)
        self:Warn(("Error in %s: %s"):format(tostring(label), errorMsg))
        return false, errorMsg
    end

    return true, a, b, c
end

function Diagnostics:RunStartupChecks()
    local requiredApis = {
        "CreateFrame",
        "InCombatLockdown",
        "SendChatMessage",
    }

    for _, apiName in ipairs(requiredApis) do
        if type(_G[apiName]) ~= "function" then
            self:Warn(("Missing API function: %s"):format(apiName))
        end
    end
end
