local _, Addon = ...

local Logger = {
    maxEntries = 200,
    entries = {},
    debugEnabled = false,
}

Addon.Logger = Logger

local function now()
    if type(GetTimePreciseSec) == "function" then
        return GetTimePreciseSec()
    end
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function formatMessage(message, ...)
    if select("#", ...) == 0 then
        return tostring(message or "")
    end

    local ok, result = pcall(string.format, tostring(message or ""), ...)
    return ok and result or tostring(message or "")
end

function Logger:SetDebugEnabled(enabled)
    self.debugEnabled = enabled == true
end

function Logger:IsDebugEnabled()
    return self.debugEnabled == true
end

function Logger:Write(level, scope, message, ...)
    level = tostring(level or "INFO")
    if level == "DEBUG" and not self.debugEnabled then
        return nil
    end

    local entry = {
        at = now(),
        level = level,
        scope = tostring(scope or "core"),
        message = formatMessage(message, ...),
    }
    self.entries[#self.entries + 1] = entry
    if #self.entries > self.maxEntries then
        table.remove(self.entries, 1)
    end
    return entry
end

function Logger:GetEntries()
    return self.entries
end

function Logger:Clear()
    for index = #self.entries, 1, -1 do
        self.entries[index] = nil
    end
end

function Logger:ProtectedCall(scope, callback, ...)
    if type(callback) ~= "function" then
        return false, "callback is not a function"
    end

    local args = { ... }
    local function errorHandler(err)
        local trace = type(debugstack) == "function" and debugstack(2, 8, 8) or ""
        local message = tostring(err)
        if trace ~= "" then
            message = message .. "\n" .. trace
        end
        self:Write("ERROR", scope, message)
        return message
    end

    return xpcall(function()
        return callback(unpack(args))
    end, errorHandler)
end

function Addon:SafeCall(scope, callback, ...)
    return Logger:ProtectedCall(scope, callback, ...)
end

function Addon:AreChatMessagesEnabled()
    local database = self.Database
    if not database or type(database.GetUI) ~= "function" then
        return true
    end
    local ok, ui = pcall(database.GetUI, database)
    if not ok or type(ui) ~= "table" then
        return true
    end
    return ui.chatMessagesEnabled ~= false
end

function Addon:SetChatMessagesEnabled(enabled)
    local database = self.Database
    if not database or type(database.GetUI) ~= "function" then
        return false
    end
    local ui = database:GetUI()
    ui.chatMessagesEnabled = enabled ~= false
    return true
end

function Addon:Print(message, ...)
    if not self:AreChatMessagesEnabled() then
        return false
    end
    local text = formatMessage(message, ...)
    local prefix = "|cff63d7ff" .. tostring(self.Identity.displayName) .. "|r"
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. text)
    elseif type(print) == "function" then
        print(prefix .. ": " .. text)
    end
    return true
end

function Addon:Debug(scope, message, ...)
    Logger:Write("DEBUG", scope, message, ...)
end
