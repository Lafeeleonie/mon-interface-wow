local addonName, ns = ...
local unpack = unpack

_G.ThyraxUtil = ns
ns.addonName = addonName
ns.displayName = "ThyraxUtil"

ns.LegacyAddonGuard = ns.LegacyAddonGuard or {}

local LEGACY_ADDONS = {
    ["ThyraxUtil_Crosshair"] = "crosshair",
    ["ThyraxUtil_DarknessAnnouncer"] = "darkness_announcer",
    ["ThyraxUtil_MouseTracker"] = "mouse_tracker",
    ["ThyraxUtil_QoL"] = "quest_accept_hotkey",
}
local LEGACY_POPUP_KEY = "THYRAXUTIL_LEGACY_ADDONS_DISABLED"

local function GetLegacyEnableState(addonName)
    if not C_AddOns or type(C_AddOns.GetAddOnEnableState) ~= "function" then
        return 0
    end

    local playerName = UnitName and UnitName("player") or nil
    local attempts = {
        { addonName, playerName },
        { playerName, addonName },
        { addonName },
    }

    for _, args in ipairs(attempts) do
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, unpack(args))
        if ok and tonumber(state) then
            return tonumber(state)
        end
    end

    return 0
end

local function DisableLegacyAddon(addonName)
    if not C_AddOns or type(C_AddOns.DisableAddOn) ~= "function" then
        return false
    end

    local playerName = UnitName and UnitName("player") or nil
    local attempts = {
        { addonName, playerName },
        { playerName, addonName },
        { addonName },
    }

    for _, args in ipairs(attempts) do
        if args[1] and args[2] ~= "" then
            local ok = pcall(C_AddOns.DisableAddOn, unpack(args))
            if ok then
                return true
            end
        end
    end

    return false
end

function ns.LegacyAddonGuard:DisableLegacyAddons()
    local disabledAddons = {}
    local disabledTypes = {}
    for addon, addonType in pairs(LEGACY_ADDONS) do
        if GetLegacyEnableState(addon) > 0 and DisableLegacyAddon(addon) then
            disabledAddons[#disabledAddons + 1] = addon
            disabledTypes[addonType] = true
        end
    end

    if #disabledAddons == 0 or self.popupShown then
        return disabledTypes
    end

    self.popupShown = true

    local details = table.concat(disabledAddons, ", ")
    local popupText = (
        "|cFFFFD200ThyraxUtil Integration|r\n\n" ..
            "Old standalone modules were detected and disabled to prevent conflicts:\n|cFF00FF00%s|r\n\n" ..
            "You can safely delete these addon folders."
        ):format(details)

    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs[LEGACY_POPUP_KEY] then
            StaticPopupDialogs[LEGACY_POPUP_KEY] = {
                button1 = OKAY or "OK",
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                preferredIndex = 3,
            }
        end
        StaticPopupDialogs[LEGACY_POPUP_KEY].text = popupText
        StaticPopup_Show(LEGACY_POPUP_KEY)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200ThyraxUtil|r: " .. popupText:gsub("\n", " "))
    end

    return disabledTypes
end
