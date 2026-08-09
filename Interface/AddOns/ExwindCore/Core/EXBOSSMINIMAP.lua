local _, ExwindTools = ...
if not ExwindTools then return end

local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })

_G.ExwindToolsDB = _G.ExwindToolsDB or {}
local db = _G.ExwindToolsDB
db.EXBossMinimap = db.EXBossMinimap or { hide = false }

local function IsEXBossLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("EXBoss")
    end
    return _G.ExBoss ~= nil
end

function ExwindTools:IsEXBossMinimapButtonHidden()
    db.EXBossMinimap = db.EXBossMinimap or { hide = false }
    return db.EXBossMinimap.hide == true
end

function ExwindTools:SetEXBossMinimapButtonHidden(hidden)
    db.EXBossMinimap = db.EXBossMinimap or { hide = false }
    db.EXBossMinimap.hide = hidden and true or false

    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDBIcon then return end
    if LDBIcon:IsRegistered("EXBoss") then
        LDBIcon:Refresh("EXBoss", db.EXBossMinimap)
    end
end

local function ToggleEXBossPanel()
    local panel = _G.ExBoss and _G.ExBoss.UI and _G.ExBoss.UI.Panel
    if panel and panel.Toggle then
        panel:Toggle()
    end
end

local function ToggleGlobalEditMode()
    if ExwindTools and ExwindTools.ToggleGlobalEditMode then
        ExwindTools:ToggleGlobalEditMode()
    end
end

local function InitEXBossMinimapButton()
    if not IsEXBossLoaded() then
        return
    end

    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    db.EXBossMinimap = db.EXBossMinimap or { hide = false }

    if not LDBIcon:IsRegistered("EXBoss") then
        local dataObject = LDB.GetDataObjectByName and LDB:GetDataObjectByName("EXBoss") or nil
        if not dataObject then
            dataObject = LDB:NewDataObject("EXBoss", {
                type = "launcher",
                text = "EXBoss",
                icon = [[Interface\AddOns\ExwindCore\Textures\LOGO\EXBOSS.jpg]],
                OnClick = function(_, button)
                    if button == "LeftButton" then
                        ToggleEXBossPanel()
                    elseif button == "RightButton" then
                        ToggleGlobalEditMode()
                    end
                end,
                OnTooltipShow = function(tt)
                    local version = _G.ExBoss and _G.ExBoss.VERSION or "DEV-Build"
                    tt:AddLine("|cffff4400Ex|r|cff00ccffBoss|r " .. tostring(version))
                    tt:AddLine(" ")
                    tt:AddLine(string.format("|cff00ff00%s|r %s", L["左键:"], L["打开 EXBoss 面板"]))
                    tt:AddLine(string.format("|cff00ff00%s|r %s", L["右键:"], L["切换编辑模式"]))
                end,
            })
        end

        LDBIcon:Register("EXBoss", dataObject, db.EXBossMinimap)
    end

    LDBIcon:Refresh("EXBoss", db.EXBossMinimap)
end

C_Timer.After(0.5, InitEXBossMinimapButton)
