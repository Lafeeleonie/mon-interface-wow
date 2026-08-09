local addonName, Companion = ...

local function getMetadata(key)
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, addonName, key)
        if ok then return value end
    elseif type(GetAddOnMetadata) == "function" then
        local ok, value = pcall(GetAddOnMetadata, addonName, key)
        if ok then return value end
    end
end

local bridgeName = getMetadata("X-Vaultloom-Bridge") or "VaultloomCompendiumBridge"
local bridge = _G[bridgeName]
local catalog = Companion.Data and Companion.Data.MidnightCompendium
if type(bridge) == "table" and type(bridge.RegisterCatalog) == "function" and type(catalog) == "table" then
    bridge:RegisterCatalog(catalog)
end
