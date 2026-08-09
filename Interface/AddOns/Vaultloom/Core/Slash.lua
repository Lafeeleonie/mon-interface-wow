local _, Addon = ...

local RELOAD_SLASH_KEY = "VAULTLOOM_RELOAD"
local RELOAD_SLASH_ALIAS = "/rl"

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function isSlashAliasRegistered(alias)
    local normalizedAlias = string.lower(trim(alias))
    if normalizedAlias == "" then
        return false
    end

    for globalName, value in pairs(_G) do
        if type(globalName) == "string"
            and globalName:match("^SLASH_.+%d+$")
            and type(value) == "string"
            and string.lower(trim(value)) == normalizedAlias
        then
            return true
        end
    end

    return false
end

function Addon:RegisterSlashCommands()
    if self.Runtime.slashRegistered then
        return
    end
    self.Runtime.slashRegistered = true

    local key = "VAULTLOOM"
    for index, command in ipairs(self.Identity.slashCommands) do
        _G["SLASH_" .. key .. index] = command
    end
    SlashCmdList[key] = function(message)
        Addon:HandleSlashCommand(message)
    end
end

function Addon:RegisterReloadSlashCommand()
    if self.Runtime.reloadSlashRegistered then
        return true
    end
    if type(SlashCmdList) ~= "table"
        or type(ReloadUI) ~= "function"
        or isSlashAliasRegistered(RELOAD_SLASH_ALIAS)
    then
        return false
    end

    _G["SLASH_" .. RELOAD_SLASH_KEY .. "1"] = RELOAD_SLASH_ALIAS
    SlashCmdList[RELOAD_SLASH_KEY] = function()
        ReloadUI()
    end
    self.Runtime.reloadSlashRegistered = true
    return true
end

function Addon:HandleSlashCommand(message)
    local raw = trim(message)
    local command, remainder = raw:match("^(%S+)%s*(.-)$")
    command = string.lower(command or "")
    if command == "" then
        self.UI:Toggle()
        return
    end
    if command == "help" or command == "hilfe" or command == "aide" or command == "ayuda" or command == "aiuto" or command == "ajuda" or command == "помощь" or command == "도움말" or command == "帮助" or command == "幫助" or command == "說明" then
        self:Print(self.L.COMMAND_HELP)
        return
    end
    if command == "status" or command == "statut" or command == "estado" or command == "stato" or command == "статус" or command == "상태" or command == "状态" or command == "狀態" then
        local enabled, total = self.ModuleRegistry:GetStats()
        self:Print(self.L.COMMAND_STATUS, self.version, enabled, total, self.StateStore:GetSliceCount())
        return
    end
    if command == "debug" then
        local db = self.Database:Get()
        db.debug.enabled = not db.debug.enabled
        self.Logger:SetDebugEnabled(db.debug.enabled)
        self:Print(db.debug.enabled and self.L.COMMAND_DEBUG_ON or self.L.COMMAND_DEBUG_OFF)
        return
    end
    if command == "reset"
        or command == "reinitialiser"
        or command == "réinitialiser"
        or command == "restablecer"
        or command == "ripristina"
        or command == "reimposta"
        or command == "redefinir"
        or command == "сброс"
        or command == "초기화"
        or command == "重置"
        or command == "重設"
    then
        self.Database:ResetWindowSettings()
        if self.UI.frame then
            self.UI:ResetWindowSettings()
        end
        self:Print(self.L.COMMAND_RESET)
        return
    end
    if command == "resetwindows"
        or command == "fensterreset"
        or command == "fenetres"
        or command == "fenêtres"
        or command == "ventanas"
        or command == "finestre"
        or command == "janelas"
        or command == "окна"
        or command == "창초기화"
        or command == "重置窗口"
        or command == "重設視窗"
    then
        if self.BlizzardWindowMover and type(self.BlizzardWindowMover.ResetAll) == "function" then
            self.BlizzardWindowMover:ResetAll()
        else
            self:Print(self.L.COMMAND_UNKNOWN)
        end
        return
    end
    if command == "shop"
        or command == "einkauf"
        or command == "achats"
        or command == "compras"
        or command == "acquisti"
        or command == "покупки"
        or command == "쇼핑"
        or command == "구매"
        or command == "购物"
        or command == "購物"
    then
        if self.ShoppingList and type(self.ShoppingList.Toggle) == "function" then
            self.ShoppingList:Toggle()
        else
            self:Print(self.L.COMMAND_UNKNOWN)
        end
        return
    end
    if command == "find"
        or command == "finder"
        or command == "suche"
        or command == "inventar"
    then
        if self.ItemFinder and type(self.ItemFinder.Toggle) == "function" then
            self.ItemFinder:Toggle(remainder)
        else
            self:Print(self.L.COMMAND_UNKNOWN)
        end
        return
    end
    if command == "bannertest" or command == "banner" then
        if self.UI and type(self.UI.ToggleBannerPreview) == "function" then
            self.UI:ToggleBannerPreview()
        else
            self:Print(self.L.COMMAND_UNKNOWN)
        end
        return
    end
    if command == "vaultrewardtest" or command == "truhentest" then
        local db = self.Database:Get()
        local characters = db.characters or {}
        local characterKey = db.mainCharacterKey
        if type(characterKey) ~= "string" or type(characters[characterKey]) ~= "table" then
            characterKey = self.WarbandRoster:GetCurrentKey()
        end
        local changed, enabled = self.VaultProgress:ToggleTestReward(characterKey)
        if changed then
            self:Print(
                enabled and self.L.COMMAND_VAULT_REWARD_TEST_ON
                    or self.L.COMMAND_VAULT_REWARD_TEST_OFF
            )
        else
            self:Print(self.L.COMMAND_UNKNOWN)
        end
        return
    end
    if (command == "stats"
        or command == "werte"
        or command == "caracteristiques"
        or command == "caractéristiques"
        or command == "estadisticas"
        or command == "estadísticas"
        or command == "statistiche"
        or command == "estatisticas"
        or command == "estatísticas"
        or command == "характеристики"
        or command == "능력치"
        or command == "属性"
        or command == "屬性")
        and self.StatFocus and type(self.StatFocus.HandleSlash) == "function"
    then
        self.StatFocus:HandleSlash(remainder)
        return
    end
    self:Print(self.L.COMMAND_UNKNOWN)
end
