local ADDON_NAME = ...
local DISPLAY_NAME = "Lafee ElvUI Frame Group"

local controller = CreateFrame("Frame")
local rootDatabase
local database
local activeProfileName
local movers = {}
local wrappedMovers = setmetatable({}, { __mode = "k" })
local selectedGroupId
local activeDrag
local DiscoverMovers
local RefreshGroupPanel
local UpdateGroupPanelVisibility

local RED = { 0.95, 0.10, 0.10, 0.42 }
local SELECTED = { 1.00, 0.72, 0.05, 0.28 }

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040" .. DISPLAY_NAME .. "|r: " .. message)
end

local function GetElvUIProfileName()
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if engine and engine.data and engine.data.GetCurrentProfile then
        local profileName = engine.data:GetCurrentProfile()
        if profileName and profileName ~= "" then
            return profileName
        end
    end

    return "Default"
end

local function SelectProfileDatabase(profileName)
    profileName = profileName or GetElvUIProfileName()
    rootDatabase.profiles = type(rootDatabase.profiles) == "table" and rootDatabase.profiles or {}
    rootDatabase.profiles[profileName] = type(rootDatabase.profiles[profileName]) == "table" and rootDatabase.profiles[profileName] or {}

    database = rootDatabase.profiles[profileName]
    database.groups = type(database.groups) == "table" and database.groups or {}
    database.positions = type(database.positions) == "table" and database.positions or {}
    database.nextGroupId = tonumber(database.nextGroupId) or 1
    activeProfileName = profileName
end

local function GetDatabase()
    if type(LafeeElvUIFrameGroupDB) ~= "table" then
        LafeeElvUIFrameGroupDB = {}
    end

    rootDatabase = LafeeElvUIFrameGroupDB
    if type(rootDatabase.profiles) ~= "table" and (type(rootDatabase.groups) == "table" or type(rootDatabase.positions) == "table") then
        rootDatabase.profiles = {
            [GetElvUIProfileName()] = {
                groups = rootDatabase.groups,
                positions = rootDatabase.positions,
                nextGroupId = rootDatabase.nextGroupId,
            },
        }
        rootDatabase.groups = nil
        rootDatabase.positions = nil
        rootDatabase.nextGroupId = nil
    end
    SelectProfileDatabase()
end

local function IsFrame(value)
    if not value or not value.GetObjectType then
        return false
    end

    local objectType = value:GetObjectType()
    return objectType == "Frame" or objectType == "Button"
end

local function GetMoverName(mover)
    return mover and (mover.LafeeFrameGroupName or mover:GetName())
end

local function GetGroup(groupId)
    return database and database.groups[groupId]
end

local function CountMembers(group)
    local count = 0
    if group and group.movers then
        for _ in pairs(group.movers) do
            count = count + 1
        end
    end
    return count
end

local function GetGroupName(groupId)
    local group = GetGroup(groupId)
    if group and type(group.name) == "string" and group.name ~= "" then
        return group.name
    end
    return "Groupe " .. tostring(groupId)
end

local function FindGroupId(moverName)
    if not database then
        return nil
    end

    for groupId, group in pairs(database.groups) do
        if group.movers and group.movers[moverName] then
            return groupId
        end
    end
end

local function EnsureOverlay(mover)
    local overlay = mover.LafeeFrameGroupOverlay
    if not overlay then
        -- ElvUI movers now use more overlay layers themselves.  Keep our
        -- markers in low, valid sublevels so a full mover does not abort the
        -- whole discovery pass.
        overlay = mover:CreateTexture(nil, "OVERLAY", nil, 1)
        overlay:SetAllPoints(mover)
        overlay:SetColorTexture(unpack(RED))
        overlay:Hide()
        mover.LafeeFrameGroupOverlay = overlay
    end

    if not mover.LafeeFrameGroupSelectedOverlay then
        local selectedOverlay = mover:CreateTexture(nil, "OVERLAY", nil, 2)
        selectedOverlay:SetAllPoints(mover)
        selectedOverlay:SetColorTexture(unpack(SELECTED))
        selectedOverlay:Hide()
        mover.LafeeFrameGroupSelectedOverlay = selectedOverlay
    end

    return overlay
end

local function RefreshHighlights()
    for moverName, mover in pairs(movers) do
        local overlay = EnsureOverlay(mover)
        local groupId = FindGroupId(moverName)
        if groupId then
            overlay:Show()
        else
            overlay:Hide()
        end

        local selectedOverlay = mover.LafeeFrameGroupSelectedOverlay
        if selectedOverlay then
            if groupId and groupId == selectedGroupId then
                selectedOverlay:Show()
            else
                selectedOverlay:Hide()
            end
        end
    end
end

local function GetMoverPosition(mover)
    local left, bottom = mover:GetLeft(), mover:GetBottom()
    if not left or not bottom then
        return nil
    end
    return left, bottom
end

local function PlaceMover(mover, left, bottom)
    if not mover or not left or not bottom then
        return
    end

    mover:ClearAllPoints()
    mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function SaveGroupPositions(groupId)
    local group = GetGroup(groupId)
    if not group then
        return
    end

    for moverName in pairs(group.movers) do
        local mover = movers[moverName]
        if mover then
            local left, bottom = GetMoverPosition(mover)
            if left then
                database.positions[moverName] = { left = left, bottom = bottom }
            end
        end
    end
end

local function ApplySavedPositions()
    -- Since ElvUI 15, movers can be protected after its profile update.
    -- Restoring positions here via ClearAllPoints taints that protected path.
    -- ElvUI already restores its own mover positions, so groups only need to
    -- retain their membership and follow a drag while Move UI is open.
end

local function SyncElvUIProfile()
    if not rootDatabase then
        return
    end

    local profileName = GetElvUIProfileName()
    if profileName == activeProfileName then
        return
    end

    activeDrag = nil
    selectedGroupId = nil
    SelectProfileDatabase(profileName)
    RefreshHighlights()
    RefreshGroupPanel()
    C_Timer.After(0, function()
        if DiscoverMovers() then
            ApplySavedPositions()
        end
        UpdateGroupPanelVisibility()
    end)
end

local function CreateGroup()
    local groupId = tostring(database.nextGroupId)
    database.nextGroupId = database.nextGroupId + 1
    database.groups[groupId] = { movers = {}, name = "Groupe " .. groupId }
    selectedGroupId = groupId
    return groupId
end

local function SelectMover(moverName)
    local currentGroupId = FindGroupId(moverName)
    if currentGroupId then
        selectedGroupId = currentGroupId
        RefreshHighlights()
        RefreshGroupPanel()
        Print(GetGroupName(currentGroupId) .. " sélectionné (" .. CountMembers(GetGroup(currentGroupId)) .. " cadres).")
        return
    end

    local group = GetGroup(selectedGroupId)
    if not group then
        selectedGroupId = CreateGroup()
        group = GetGroup(selectedGroupId)
    end

    group.movers[moverName] = true
    RefreshHighlights()
    RefreshGroupPanel()
    Print("Cadre ajouté à « " .. GetGroupName(selectedGroupId) .. " ».")
end

local function RemoveMover(moverName)
    local groupId = FindGroupId(moverName)
    if not groupId then
        return
    end

    local group = GetGroup(groupId)
    group.movers[moverName] = nil
    database.positions[moverName] = nil

    if CountMembers(group) == 0 then
        database.groups[groupId] = nil
        if selectedGroupId == groupId then
            selectedGroupId = nil
        end
    end

    RefreshHighlights()
    RefreshGroupPanel()
    Print("Cadre retiré de « " .. GetGroupName(groupId) .. " ».")
end

local function UpdateLinkedMovers()
    if not activeDrag then
        return
    end

    local leaderLeft, leaderBottom = GetMoverPosition(activeDrag.leader)
    if not leaderLeft then
        return
    end

    local deltaLeft = leaderLeft - activeDrag.startLeft
    local deltaBottom = leaderBottom - activeDrag.startBottom
    for moverName, startPosition in pairs(activeDrag.members) do
        if moverName ~= activeDrag.leaderName then
            local mover = movers[moverName]
            if mover then
                PlaceMover(mover, startPosition.left + deltaLeft, startPosition.bottom + deltaBottom)
            end
        end
    end
end

local function StartLinkedDrag(mover)
    if IsShiftKeyDown() or InCombatLockdown() then
        return
    end

    local moverName = GetMoverName(mover)
    local groupId = moverName and FindGroupId(moverName)
    local group = groupId and GetGroup(groupId)
    if not group or CountMembers(group) < 2 then
        return
    end

    local startLeft, startBottom = GetMoverPosition(mover)
    if not startLeft then
        return
    end

    local members = {}
    for memberName in pairs(group.movers) do
        local member = movers[memberName]
        if member then
            local left, bottom = GetMoverPosition(member)
            if left then
                members[memberName] = { left = left, bottom = bottom }
            end
        end
    end

    activeDrag = {
        groupId = groupId,
        leader = mover,
        leaderName = moverName,
        startLeft = startLeft,
        startBottom = startBottom,
        members = members,
    }
end

local function StopLinkedDrag(mover)
    if not activeDrag or activeDrag.leader ~= mover then
        return
    end

    UpdateLinkedMovers()
    SaveGroupPositions(activeDrag.groupId)
    activeDrag = nil
end

controller:SetScript("OnUpdate", UpdateLinkedMovers)

local function HandleMoverMouseDown(mover, button)
    if not IsShiftKeyDown() then
        return false
    end

    local moverName = GetMoverName(mover)
    if not moverName then
        return false
    end

    if button == "LeftButton" then
        SelectMover(moverName)
        return true
    elseif button == "RightButton" then
        RemoveMover(moverName)
        return true
    end

    return false
end

local function WrapMover(mover, moverName)
    if wrappedMovers[mover] then
        return
    end

    moverName = moverName or GetMoverName(mover)
    if not moverName then
        return
    end

    mover.LafeeFrameGroupName = moverName
    wrappedMovers[mover] = true
    local originalMouseDown = mover:GetScript("OnMouseDown")
    mover:SetScript("OnMouseDown", function(frame, button, ...)
        if HandleMoverMouseDown(frame, button) then
            frame.LafeeFrameGroupSelectionHandled = true
            return
        end
        if originalMouseDown then
            return originalMouseDown(frame, button, ...)
        end
    end)

    -- ElvUI can replace its mouse script while entering move mode.  The hook
    -- remains active in that case and keeps Maj-clic selection available.
    mover:HookScript("OnMouseDown", function(frame, button)
        if frame.LafeeFrameGroupSelectionHandled then
            frame.LafeeFrameGroupSelectionHandled = nil
        else
            HandleMoverMouseDown(frame, button)
        end
    end)
    mover:HookScript("OnDragStart", StartLinkedDrag)
    mover:HookScript("OnDragStop", StopLinkedDrag)
end

DiscoverMovers = function()
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if not engine then
        return false
    end

    local moverLists = {}
    if type(engine.CreatedMovers) == "table" then
        moverLists[#moverLists + 1] = engine.CreatedMovers
    end
    if type(engine.Movers) == "table" then
        moverLists[#moverLists + 1] = engine.Movers
    end

    for _, moverList in ipairs(moverLists) do
        if type(moverList) == "table" then
            for moverKey, candidate in pairs(moverList) do
                local mover = candidate
                if type(mover) == "string" then
                    mover = _G[mover]
                end
                if not IsFrame(mover) and type(candidate) == "table" then
                    mover = candidate.mover or candidate.frame
                end
                if type(mover) == "string" then
                    mover = _G[mover]
                end
                if not IsFrame(mover) and type(moverKey) == "string" then
                    mover = _G[moverKey]
                end

                local moverName = IsFrame(mover) and (mover:GetName() or (type(moverKey) == "string" and moverKey))
                if moverName then
                    movers[moverName] = mover
                    WrapMover(mover, moverName)
                end
            end
        end
    end

    -- Some ElvUI modules use named movers without exposing their frame in the
    -- primary movers table, so collect those as well.
    for globalName, candidate in pairs(_G) do
        if type(globalName) == "string" and globalName:match("Mover$") and IsFrame(candidate) then
            movers[globalName] = candidate
            WrapMover(candidate, globalName)
        end
    end

    RefreshHighlights()
    return next(movers) ~= nil
end

local function QueueDiscovery()
    C_Timer.After(0, function()
        if DiscoverMovers() then
            ApplySavedPositions()
        end
        UpdateGroupPanelVisibility()
    end)
end

local function IsElvUIMoveModeOpen()
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    return engine and (engine.ConfigurationMode == true or engine.configMode == true) or false
end

local function InstallMoveUIIntegration()
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if not engine or type(engine.ToggleMoveMode) ~= "function" or controller.moveUIHooked then
        return
    end

    hooksecurefunc(engine, "ToggleMoveMode", function()
        -- ElvUI updates ConfigurationMode inside ToggleMoveMode.  Defer our
        -- refresh by one frame so every mover created by ElvUI is available.
        C_Timer.After(0, function()
            controller.moveUIOpen = IsElvUIMoveModeOpen()
            QueueDiscovery()
        end)
    end)

    controller.moveUIHooked = true
    controller.moveUIOpen = IsElvUIMoveModeOpen()
end

local function QueueProfileSync()
    C_Timer.After(0, SyncElvUIProfile)
end

local function InstallProfileIntegration()
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if not engine or controller.profileIntegrationInstalled then
        return
    end

    local profileDatabase = engine.data
    if profileDatabase and profileDatabase.RegisterCallback then
        -- AceDB exposes its callbacks directly on the database object.  Its
        -- RegisterCallback signature here is (eventName, callback), unlike
        -- CallbackHandler's standalone registration API.
        profileDatabase:RegisterCallback("OnProfileChanged", QueueProfileSync)
        profileDatabase:RegisterCallback("OnProfileCopied", QueueProfileSync)
        profileDatabase:RegisterCallback("OnProfileReset", QueueProfileSync)
    end

    if engine.UpdateAll then
        hooksecurefunc(engine, "UpdateAll", QueueProfileSync)
    end

    controller.profileIntegrationInstalled = true
end

local function RegisterElvUIPlugin()
    if controller.elvUIPluginRegistered then
        return
    end

    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    local plugins = engine and engine.Libs and engine.Libs.EP
    if not plugins or type(plugins.RegisterPlugin) ~= "function" then
        return
    end

    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    plugins:RegisterPlugin(ADDON_NAME, nil, false, version)
    controller.elvUIPluginRegistered = true
end

local groupPanel
local groupDropdown
local groupDropdownList
local groupDropdownRows = {}
local groupNameBox
local groupCountText
local minimapButton

local function ApplyElvUIButtonSkin(button)
    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if not engine or not engine.GetModule or button.LafeeElvUIStyled then
        return
    end

    local success, skins = pcall(engine.GetModule, engine, "Skins", true)
    if success and skins and skins.HandleButton then
        skins:HandleButton(button, true)
        button.LafeeElvUIStyled = true
    end
end

local function ApplyElvUISkin()
    if not groupPanel then
        return
    end

    local elvUI = _G.ElvUI
    local engine = elvUI and elvUI[1]
    if groupPanel.SetTemplate then
        groupPanel:SetTemplate("Transparent")
        return
    end

    local media = engine and engine.media
    if media then
        groupPanel:SetBackdrop({
            bgFile = media.normTex or "Interface\\Buttons\\WHITE8x8",
            edgeFile = media.blankTex or "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })

        local background = media.backdropfadecolor or { 0.06, 0.06, 0.06, 0.94 }
        local border = media.bordercolor or { 0.15, 0.15, 0.15, 1 }
        groupPanel:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
        groupPanel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
end

local function GetSortedGroupIds()
    local groupIds = {}
    for groupId in pairs(database.groups) do
        groupIds[#groupIds + 1] = groupId
    end
    table.sort(groupIds, function(left, right)
        return tonumber(left) < tonumber(right)
    end)
    return groupIds
end

local function RefreshGroupDropdown()
    if not groupDropdownList then
        return
    end

    local groupIds = GetSortedGroupIds()
    groupDropdownList:SetHeight(math.max(1, #groupIds) * 25 + 8)
    for index, groupId in ipairs(groupIds) do
        local row = groupDropdownRows[index]
        if not row then
            row = CreateFrame("Button", nil, groupDropdownList, "UIPanelButtonTemplate")
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 4, -4 - ((index - 1) * 25))
            row:SetPoint("TOPRIGHT", -4, -4 - ((index - 1) * 25))
            groupDropdownRows[index] = row
            ApplyElvUIButtonSkin(row)
        end

        row.groupId = groupId
        row:SetText(GetGroupName(groupId))
        row:SetShown(true)
        row:SetScript("OnClick", function(button)
            selectedGroupId = button.groupId
            groupDropdownList:Hide()
            RefreshHighlights()
            RefreshGroupPanel()
        end)
    end

    for index = #groupIds + 1, #groupDropdownRows do
        groupDropdownRows[index]:Hide()
    end
end

local function ToggleGroupDropdown()
    if groupDropdownList:IsShown() then
        groupDropdownList:Hide()
    else
        RefreshGroupDropdown()
        groupDropdownList:Show()
    end
end

local function SaveActiveGroupName()
    local group = GetGroup(selectedGroupId)
    if not group or not groupNameBox then
        return
    end

    local name = groupNameBox:GetText():match("^%s*(.-)%s*$")
    group.name = name ~= "" and name:sub(1, 32) or "Groupe " .. selectedGroupId
    RefreshGroupPanel()
end

local function RestorePanelPosition()
    if rootDatabase and rootDatabase.panelLayoutVersion ~= 2 then
        rootDatabase.panelPosition = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -20, y = -120 }
        rootDatabase.panelLayoutVersion = 2
    end

    local position = rootDatabase and rootDatabase.panelPosition
    if position then
        groupPanel:ClearAllPoints()
        groupPanel:SetPoint(position.point or "TOPLEFT", UIParent, position.relativePoint or "TOPLEFT", position.x or 24, position.y or -130)
    end
end

local function SavePanelPosition()
    if not rootDatabase then
        return
    end

    local point, _, relativePoint, x, y = groupPanel:GetPoint()
    rootDatabase.panelPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function CreateGroupPanel()
    if groupPanel then
        return
    end

    groupPanel = CreateFrame("Frame", "LafeeElvUIFrameGroupPanel", UIParent, "BackdropTemplate")
    groupPanel:SetSize(380, 320)
    groupPanel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -120)
    groupPanel:SetFrameStrata("DIALOG")
    groupPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    groupPanel:SetBackdropColor(0.04, 0.04, 0.04, 0.94)
    groupPanel:SetBackdropBorderColor(0.85, 0.15, 0.15, 1)
    groupPanel:SetClampedToScreen(true)

    local dragHandle = CreateFrame("Button", nil, groupPanel)
    dragHandle:SetPoint("TOPLEFT", 4, -4)
    dragHandle:SetPoint("TOPRIGHT", -4, -4)
    dragHandle:SetHeight(42)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        groupPanel:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        groupPanel:StopMovingOrSizing()
        SavePanelPosition()
    end)
    groupPanel:SetMovable(true)
    RestorePanelPosition()

    local title = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -13)
    title:SetWidth(340)
    title:SetJustifyH("CENTER")
    title:SetText("Groupes de cadres ElvUI")

    local profile = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profile:SetPoint("TOP", title, "BOTTOM", 0, -4)
    profile:SetWidth(340)
    profile:SetJustifyH("CENTER")
    profile:SetText("Profil ElvUI actif")
    groupPanel.profileText = profile

    local groupLabel = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("TOPLEFT", 18, -57)
    groupLabel:SetText("Groupe actif")

    groupDropdown = CreateFrame("Button", nil, groupPanel, "UIPanelButtonTemplate")
    groupDropdown:SetSize(240, 22)
    groupDropdown:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", 3, -5)
    groupDropdown:SetText("Choisir un groupe")
    groupDropdown:SetScript("OnClick", ToggleGroupDropdown)
    ApplyElvUIButtonSkin(groupDropdown)

    groupDropdownList = CreateFrame("Frame", nil, groupPanel, "BackdropTemplate")
    groupDropdownList:SetPoint("TOPLEFT", groupDropdown, "BOTTOMLEFT", 0, -3)
    groupDropdownList:SetPoint("TOPRIGHT", groupDropdown, "BOTTOMRIGHT", 0, -3)
    groupDropdownList:SetFrameStrata("TOOLTIP")
    groupDropdownList:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    if groupDropdownList.SetTemplate then
        groupDropdownList:SetTemplate("Transparent")
    else
        groupDropdownList:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
        groupDropdownList:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    end
    groupDropdownList:Hide()

    local newButton = CreateFrame("Button", nil, groupPanel, "UIPanelButtonTemplate")
    newButton:SetSize(86, 22)
    newButton:SetPoint("TOPRIGHT", groupPanel, "TOPRIGHT", -18, -78)
    newButton:SetText("Nouveau")
    newButton:SetScript("OnClick", function()
        CreateGroup()
        RefreshGroupPanel()
    end)
    ApplyElvUIButtonSkin(newButton)

    local nameLabel = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", 0, -51)
    nameLabel:SetText("Nom")

    groupNameBox = CreateFrame("EditBox", nil, groupPanel, "InputBoxTemplate")
    groupNameBox:SetSize(265, 22)
    groupNameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 3, -5)
    groupNameBox:SetAutoFocus(false)
    groupNameBox:SetMaxLetters(32)
    groupNameBox:SetScript("OnEnterPressed", function(box)
        SaveActiveGroupName()
        box:ClearFocus()
    end)
    groupNameBox:SetScript("OnEscapePressed", function(box)
        RefreshGroupPanel()
        box:ClearFocus()
    end)

    local saveButton = CreateFrame("Button", nil, groupPanel, "UIPanelButtonTemplate")
    saveButton:SetSize(70, 22)
    saveButton:SetPoint("TOPRIGHT", groupPanel, "TOPRIGHT", -18, -146)
    saveButton:SetText("Valider")
    saveButton:SetScript("OnClick", SaveActiveGroupName)
    groupPanel.saveButton = saveButton
    ApplyElvUIButtonSkin(saveButton)

    local deleteButton = CreateFrame("Button", nil, groupPanel, "UIPanelButtonTemplate")
    deleteButton:SetSize(92, 22)
    deleteButton:SetPoint("TOPRIGHT", groupPanel, "TOPRIGHT", -18, -176)
    deleteButton:SetText("Supprimer")
    deleteButton:SetScript("OnClick", function()
        local group = GetGroup(selectedGroupId)
        if not group then
            return
        end

        for moverName in pairs(group.movers) do
            database.positions[moverName] = nil
        end
        database.groups[selectedGroupId] = nil
        selectedGroupId = nil
        RefreshHighlights()
        RefreshGroupPanel()
    end)
    groupPanel.deleteButton = deleteButton
    ApplyElvUIButtonSkin(deleteButton)

    groupCountText = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupCountText:SetPoint("TOPLEFT", groupNameBox, "BOTTOMLEFT", -3, -9)

    local helpTitle = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpTitle:SetPoint("TOPLEFT", groupCountText, "BOTTOMLEFT", 0, -14)
    helpTitle:SetText("Commandes et raccourcis")

    local help = groupPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", helpTitle, "BOTTOMLEFT", 0, -6)
    help:SetWidth(340)
    help:SetJustifyH("LEFT")
    help:SetJustifyV("TOP")
    help:SetText("/moveui : ouvre ou ferme ce mode\nListe déroulante : choisir le groupe actif\nMaj-clic gauche : ajoute un cadre ou sélectionne son groupe\nMaj-clic droit : retire un cadre du groupe\nGlisser un cadre rouge : déplace tout son groupe\n/lfg new : crée un groupe  •  /lfg clear : supprime le groupe actif\nÉchap : ferme le panneau  •  Glisser l’en-tête : déplace le panneau")

    groupPanel:Hide()
    groupPanel:HookScript("OnHide", function()
        groupDropdownList:Hide()
    end)
    table.insert(UISpecialFrames, "LafeeElvUIFrameGroupPanel")
    ApplyElvUISkin()
end

RefreshGroupPanel = function()
    if not groupPanel or not database then
        return
    end

    groupPanel.profileText:SetText("Profil ElvUI : " .. activeProfileName)
    local group = GetGroup(selectedGroupId)
    if group then
        groupDropdown:SetText(GetGroupName(selectedGroupId))
        groupNameBox:SetText(GetGroupName(selectedGroupId))
        groupNameBox:Enable()
        groupPanel.saveButton:Enable()
        groupPanel.deleteButton:Enable()
        groupCountText:SetText(CountMembers(group) .. " cadre(s) lié(s)")
    else
        groupDropdown:SetText("Choisir un groupe")
        groupNameBox:SetText("")
        groupNameBox:Disable()
        groupPanel.saveButton:Disable()
        groupPanel.deleteButton:Disable()
        groupCountText:SetText("Créez ou sélectionnez un groupe.")
    end

    if groupDropdownList and groupDropdownList:IsShown() then
        RefreshGroupDropdown()
    end
end

UpdateGroupPanelVisibility = function()
    if not groupPanel then
        return
    end

    controller.moveUIOpen = IsElvUIMoveModeOpen()
    if controller.moveUIOpen then
        RefreshGroupPanel()
        groupPanel:Show()
    else
        groupPanel:Hide()
    end
end

local function PositionMinimapButton()
    if not minimapButton or not rootDatabase then
        return
    end

    local angle = rootDatabase.minimapButtonAngle or -1.25
    local radius = (Minimap:GetWidth() * 0.5) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateMinimapButtonFromCursor()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    rootDatabase.minimapButtonAngle = math.atan2((cursorY / scale) - centerY, (cursorX / scale) - centerX)
    PositionMinimapButton()
end

local function CreateMinimapButton()
    if minimapButton then
        return
    end

    minimapButton = CreateFrame("Button", "LafeeElvUIFrameGroupMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    minimapButton.icon = icon

    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(button)
        button.isDragging = true
        button:SetScript("OnUpdate", UpdateMinimapButtonFromCursor)
    end)
    minimapButton:SetScript("OnDragStop", function(button)
        button:SetScript("OnUpdate", nil)
        UpdateMinimapButtonFromCursor()
        C_Timer.After(0, function()
            button.isDragging = nil
        end)
    end)
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and not minimapButton.isDragging then
            local elvUI = _G.ElvUI
            local engine = elvUI and elvUI[1]
            if engine and type(engine.ToggleMoveMode) == "function" then
                engine:ToggleMoveMode()
            end
        end
    end)
    minimapButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine(DISPLAY_NAME)
        GameTooltip:AddLine("Clic gauche : ouvrir / fermer les movers et le panneau.", 1, 1, 1, true)
        GameTooltip:AddLine("Glisser : déplacer ce bouton.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", GameTooltip_Hide)
    PositionMinimapButton()
end

SLASH_LAFEEELVUIGROUP1 = "/lfg"
SlashCmdList.LAFEEELVUIGROUP = function(message)
    SyncElvUIProfile()
    message = (message or ""):lower():match("^%s*(.-)%s*$")

    if message == "new" then
        CreateGroup()
        RefreshGroupPanel()
        Print("Nouveau groupe créé : nommez-le puis ajoutez ses cadres avec Maj-clic gauche.")
    elseif message == "clear" then
        if selectedGroupId and GetGroup(selectedGroupId) then
            for moverName in pairs(GetGroup(selectedGroupId).movers) do
                database.positions[moverName] = nil
            end
            database.groups[selectedGroupId] = nil
            selectedGroupId = nil
            RefreshHighlights()
            RefreshGroupPanel()
            Print("Groupe actif supprimé.")
        else
            Print("Aucun groupe actif à supprimer.")
        end
    else
        Print("/moveui : ouvre les movers ElvUI. Maj-clic gauche ajoute ou sélectionne un groupe ; Maj-clic droit retire un cadre. /lfg new : prépare un autre groupe.")
    end
end

controller:RegisterEvent("PLAYER_LOGIN")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        GetDatabase()
        CreateGroupPanel()
        CreateMinimapButton()
        InstallMoveUIIntegration()
        InstallProfileIntegration()
        RegisterElvUIPlugin()
        QueueDiscovery()
        C_Timer.After(1, function()
            if DiscoverMovers() then
                ApplySavedPositions()
            end
            UpdateGroupPanelVisibility()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        QueueDiscovery()
    end
end)
