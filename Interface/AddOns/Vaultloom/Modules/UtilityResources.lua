local _, Addon = ...

local Module = {
    id = "character.utility",
    defaultEnabled = true,
}

local Service = {}
Addon.UtilityResources = Service
Service.opened = false

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "CURRENCY_DISPLAY_UPDATE",
    "BAG_UPDATE_DELAYED",
    "PLAYER_MONEY",
}

local function collectUtility()
    local identity = Addon.StateStore:Get("character.identity")
    if type(identity) ~= "table" or type(identity.key) ~= "string" then
        return nil
    end

    local snapshot = Addon.UtilityLogic:Scan()
    local db = Addon.Database:Get()
    local record = type(db.characters[identity.key]) == "table" and db.characters[identity.key] or {}
    record.utility = snapshot
    db.characters[identity.key] = record
    return {
        characterKey = identity.key,
        snapshot = snapshot,
    }
end

function Service:GetSnapshot(characterKey)
    local record = type(characterKey) == "string" and Addon.Database:Get().characters[characterKey] or nil
    return type(record) == "table" and type(record.utility) == "table" and record.utility or nil
end

function Service:GetCurrentSnapshot()
    local currentState = Addon.StateStore:Get(Module.id)
    if type(currentState) == "table" and type(currentState.snapshot) == "table" then
        return currentState.snapshot
    end
    local identity = Addon.StateStore:Get("character.identity")
    return identity and self:GetSnapshot(identity.key) or nil
end

function Service:GetView(character)
    local snapshot = character and self:GetSnapshot(character.key) or nil
    return Addon.UtilityLogic:BuildView(
        snapshot,
        self:GetCurrentSnapshot(),
        Addon.Database:GetUI().hiddenUtilityResources,
        self:GetSettings()
    )
end

function Service:GetSettings()
    local ui = Addon.Database:GetUI()
    ui.utility = type(ui.utility) == "table" and ui.utility or {}
    if ui.utility.showUpgradeSection == nil then ui.utility.showUpgradeSection = true end
    if ui.utility.showPvpSection == nil then ui.utility.showPvpSection = true end
    if (tonumber(ui.utility.fixedSectionVisibilityVersion) or 0) < 2 then
        local hidden = type(ui.hiddenUtilityResources) == "table" and ui.hiddenUtilityResources or {}
        for _, currencyID in ipairs(Addon.Data.MID_UTILITY_UPGRADE_CRESTS or {}) do
            hidden["currency:" .. tostring(currencyID)] = nil
        end
        for _, currencyID in ipairs(Addon.Data.MID_UTILITY_PVP_CURRENCIES or {}) do
            hidden["currency:" .. tostring(currencyID)] = nil
        end
        ui.hiddenUtilityResources = hidden
        ui.utility.fixedSectionVisibilityVersion = 2
    end
    return ui.utility
end

function Service:SetSectionVisible(sectionKey, visible)
    local settingKey = sectionKey == "upgrades" and "showUpgradeSection"
        or sectionKey == "pvp" and "showPvpSection" or nil
    if not settingKey then return false end
    local settings = self:GetSettings()
    local nextValue = visible == true
    if settings[settingKey] == nextValue then return false end
    if not nextValue then
        local ids = sectionKey == "upgrades" and Addon.Data.MID_UTILITY_UPGRADE_CRESTS
            or Addon.Data.MID_UTILITY_PVP_CURRENCIES
        local hidden = Addon.Database:GetUI().hiddenUtilityResources
        for _, currencyID in ipairs(ids or {}) do
            hidden["currency:" .. tostring(currencyID)] = nil
        end
    end
    settings[settingKey] = nextValue
    if Addon.UI and type(Addon.UI.RefreshUtility) == "function" then
        Addon.UI:RefreshUtility()
    end
    return true
end

function Service:IsHidden(entryKey)
    return type(entryKey) == "string"
        and Addon.Database:GetUI().hiddenUtilityResources[entryKey] == true
end

function Service:SetHidden(entryKey, hidden)
    if type(entryKey) ~= "string" or entryKey == "" then
        return false
    end
    Addon.Database:GetUI().hiddenUtilityResources[entryKey] = hidden == true and true or nil
    if Addon.UI and type(Addon.UI.RefreshUtility) == "function" then
        Addon.UI:RefreshUtility()
    end
    return true
end

function Service:ClearHidden()
    Addon.Database:GetUI().hiddenUtilityResources = {}
    if Addon.UI and type(Addon.UI.RefreshUtility) == "function" then
        Addon.UI:RefreshUtility()
    end
end

function Service:Refresh()
    Addon.RefreshScheduler:Invalidate(Module.id, 0)
end

function Service:Open()
    if self.opened then
        return false
    end
    self.opened = true
    self:Refresh()
    return true
end

function Service:Close()
    if not self.opened then
        return false
    end
    self.opened = false
    Addon.RefreshScheduler:Cancel(Module.id)
    return true
end

function Service:OpenCurrencyTab()
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_TokenUI")
    elseif type(LoadAddOn) == "function" then
        pcall(LoadAddOn, "Blizzard_TokenUI")
    end
    if type(TokenFrame_LoadUI) == "function" then
        pcall(TokenFrame_LoadUI)
    end

    local characterFrame = _G and _G.CharacterFrame
    local tokenFrame = _G and _G.TokenFrame
    local function bringToFront()
        if characterFrame and type(characterFrame.Raise) == "function" then
            pcall(characterFrame.Raise, characterFrame)
        end
    end
    if characterFrame and tokenFrame
        and type(characterFrame.IsShown) == "function"
        and type(tokenFrame.IsShown) == "function"
        and characterFrame:IsShown() and tokenFrame:IsShown()
    then
        bringToFront()
        return true
    end

    if type(ToggleCharacter) == "function" then
        local ok = pcall(ToggleCharacter, "TokenFrame")
        if ok then
            bringToFront()
            return true
        end
    end
    if characterFrame and type(CharacterFrame_ShowSubFrame) == "function" then
        pcall(CharacterFrame_ShowSubFrame, "TokenFrame")
        if type(ShowUIPanel) == "function" then
            pcall(ShowUIPanel, characterFrame)
        elseif type(characterFrame.Show) == "function" then
            characterFrame:Show()
        end
        bringToFront()
        return true
    end
    return false
end

function Module:OnEnable()
    Addon.RefreshScheduler:Register(self.id, self, collectUtility)
    Addon.StateStore:Subscribe("character.identity", self, function()
        if Service.opened then
            Addon.RefreshScheduler:Invalidate(Module.id, 0)
        end
    end)
    for _, eventName in ipairs(REFRESH_EVENTS) do
        Addon.EventBus:Subscribe(eventName, self, function(event)
            if Service.opened then
                Addon.RefreshScheduler:Invalidate(Module.id, event == "PLAYER_ENTERING_WORLD" and 0.10 or 0.05)
            end
        end)
    end
    Addon.RefreshScheduler:Invalidate(self.id, 0)
end

Addon.ModuleRegistry:Register(Module)
