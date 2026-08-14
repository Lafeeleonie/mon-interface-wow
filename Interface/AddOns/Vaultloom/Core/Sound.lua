local _, Addon = ...

local Sound = {}
Addon.Sound = Sound

local SOUND_KITS = {
    windowOpen = "IG_CHARACTER_INFO_OPEN",
    windowClose = "IG_CHARACTER_INFO_CLOSE",
    tabSwitch = "IG_CHARACTER_INFO_TAB",
    menuOpen = "IG_MAINMENU_OPEN",
    menuClose = "IG_MAINMENU_CLOSE",
    bagSwitch = "IG_BACKPACK_OPEN",
    option = "IG_MAINMENU_OPTION",
    toggleOn = "IG_MAINMENU_OPTION_CHECKBOX_ON",
    toggleOff = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
}

function Sound:GetSettings()
    local ui = Addon.Database and Addon.Database:GetUI()
    if type(ui) ~= "table" then
        return nil
    end
    ui.sounds = type(ui.sounds) == "table" and ui.sounds or {}
    if ui.sounds.enabled == nil then
        ui.sounds.enabled = true
    end
    return ui.sounds
end

function Sound:IsEnabled()
    local settings = self:GetSettings()
    return settings == nil or settings.enabled ~= false
end

function Sound:SetEnabled(enabled)
    local settings = self:GetSettings()
    if not settings then
        return false
    end
    settings.enabled = enabled == true
    return settings.enabled
end

function Sound:GetSoundKit(eventKey)
    local soundKitKey = SOUND_KITS[eventKey]
    local soundKits = _G.SOUNDKIT
    if type(soundKitKey) ~= "string" or type(soundKits) ~= "table" then
        return nil
    end
    return tonumber(soundKits[soundKitKey])
end

function Sound:Play(eventKey, force)
    if force ~= true and not self:IsEnabled() then
        return false
    end

    local soundKitID = self:GetSoundKit(eventKey)
    if not soundKitID then
        return false
    end

    local playSound = type(_G.PlaySound) == "function" and _G.PlaySound
        or type(_G.C_Sound) == "table" and type(_G.C_Sound.PlaySound) == "function"
            and _G.C_Sound.PlaySound or nil
    if not playSound then
        return false
    end

    local ok, played, soundHandle = pcall(playSound, soundKitID)
    if not ok or played == false then
        return false
    end
    return true, soundHandle
end

function Sound:Preview(eventKey)
    return self:Play(eventKey or "tabSwitch", true)
end

