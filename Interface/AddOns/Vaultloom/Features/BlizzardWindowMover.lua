local _, Addon = ...

local FEATURE_ID = "blizzard_window_mover"
local MIN_SCALE = 0.30
local MAX_SCALE = 2.50
local SCALE_STEP = 0.10
local POSITION_MARGIN = 24
local SCALE_CAPTURE_STRATA = "TOOLTIP"
local SCALE_CAPTURE_LEVEL = 9999

local VALID_FRAME_POINTS = {
    BOTTOM = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    TOPLEFT = true,
    TOPRIGHT = true,
}

local FRAME_STRATA_RANK = {
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}

local CORE_WINDOWS = {
    "AddonList",
    "BankFrame",
    "CharacterFrame",
    "ChatConfigFrame",
    "ContainerFrameCombinedBags",
    "DestinyFrame",
    "DressUpFrame",
    "FriendsFrame",
    "GossipFrame",
    "GuildInviteFrame",
    "GuildRegistrarFrame",
    "HelpFrame",
    "ItemTextFrame",
    "LootFrame",
    "MailFrame",
    "MerchantFrame",
    "ModelPreviewFrame",
    "PetitionFrame",
    "PingSystemTutorial",
    "PVEFrame",
    "QuestFrame",
    "QuestLogPopupDetailFrame",
    "QuickKeybindFrame",
    "ReadyCheckFrame",
    "RecruitAFriendRecruitmentFrame",
    "RecruitAFriendRewardsFrame",
    "SettingsPanel",
    "SplashFrame",
    "TabardFrame",
    "TalkingHeadFrame",
    "TaxiFrame",
    "TradeFrame",
    "TutorialFrame",
    "WorldMapFrame",
}

local ADDON_WINDOWS = {
    Blizzard_AccountStore = { "AccountStoreFrame" },
    Blizzard_AchievementUI = { "AchievementFrame" },
    Blizzard_AlliedRacesUI = { "AlliedRacesFrame" },
    Blizzard_AnimaDiversionUI = { "AnimaDiversionFrame" },
    Blizzard_ArchaeologyUI = { "ArchaeologyFrame", "ArcheologyDigsiteProgressBar" },
    Blizzard_ArtifactUI = { "ArtifactFrame", "ArtifactRelicForgeFrame" },
    Blizzard_AuctionHouseUI = { "AuctionHouseFrame" },
    Blizzard_AuctionUI = { "AuctionFrame" },
    Blizzard_AzeriteEssenceUI = { "AzeriteEssenceUI" },
    Blizzard_AzeriteRespecUI = { "AzeriteRespecFrame" },
    Blizzard_AzeriteUI = { "AzeriteEmpoweredItemUI" },
    Blizzard_BindingUI = { "KeyBindingFrame", "QuickKeybindFrame" },
    Blizzard_BlackMarketUI = { "BlackMarketFrame" },
    Blizzard_Calendar = { "CalendarFrame" },
    Blizzard_ChallengesUI = { "ChallengesKeystoneFrame" },
    Blizzard_Channels = { "ChannelFrame" },
    Blizzard_ChromieTimeUI = { "ChromieTimeFrame" },
    Blizzard_ClassTalentUI = { "ClassTalentFrame" },
    Blizzard_ClickBindingUI = { "ClickBindingFrame", "ClickBindingFrame.TutorialFrame" },
    Blizzard_Collections = { "CollectionsJournal" },
    Blizzard_Communities = {
        "CommunitiesFrame",
        "CommunitiesFrame.RecruitmentDialog",
        "CommunitiesGuildLogFrame",
        "CommunitiesGuildNewsFiltersFrame",
        "CommunitiesGuildTextEditFrame",
        "CommunitiesSettingsDialog",
    },
    Blizzard_Contribution = { "ContributionCollectionFrame" },
    Blizzard_CooldownViewer = { "CooldownViewerSettings" },
    Blizzard_CovenantPreviewUI = { "CovenantPreviewFrame" },
    Blizzard_CovenantRenown = { "CovenantRenownFrame" },
    Blizzard_CovenantSanctum = { "CovenantSanctumFrame" },
    Blizzard_DeathRecap = { "DeathRecapFrame" },
    Blizzard_DelvesCompanionConfiguration = {
        "DelvesCompanionAbilityListFrame",
        "DelvesCompanionConfigurationFrame",
    },
    Blizzard_DelvesDifficultyPicker = { "DelvesDifficultyPickerFrame" },
    Blizzard_EncounterJournal = { "EncounterJournal" },
    Blizzard_ExpansionLandingPage = { "ExpansionLandingPage" },
    Blizzard_FlightMap = { "FlightMapFrame" },
    Blizzard_GarrisonUI = {
        "BFAMissionFrame",
        "CovenantMissionFrame",
        "GarrisonBuildingFrame",
        "GarrisonCapacitiveDisplayFrame",
        "GarrisonLandingPage",
        "GarrisonMissionFrame",
        "GarrisonMonumentFrame",
        "GarrisonRecruiterFrame",
        "GarrisonRecruitSelectFrame",
        "GarrisonShipyardFrame",
        "OrderHallMissionFrame",
    },
    Blizzard_GenericTraitUI = { "GenericTraitFrame" },
    Blizzard_GuildBankUI = { "GuildBankFrame" },
    Blizzard_GuildControlUI = { "GuildControlUI" },
    Blizzard_GuildRename = { "GuildRenameFrame" },
    Blizzard_GuildUI = { "GuildFrame" },
    Blizzard_HouseEditor = { "HouseEditorFrame.StoragePanel" },
    Blizzard_HouseList = { "HouseListFrame" },
    Blizzard_HousingBulletinBoard = {
        "HousingBulletinBoardFrame",
        "HousingInviteResidentFrame",
        "NeighborhoodChangeNameDialog",
    },
    Blizzard_HousingCharter = { "HousingCharterRequestSignatureDialog" },
    Blizzard_HousingCornerstone = {
        "HousingCornerstoneFrame",
        "HousingCornerstoneHouseInfoFrame",
        "HousingCornerstonePurchaseFrame",
        "HousingCornerstoneVisitorFrame",
        "ImportHouseConfirmationDialog",
        "MoveHouseConfirmationDialog",
    },
    Blizzard_HousingCreateNeighborhood = {
        "HousingCreateCharterNeighborhoodConfirmationFrame",
        "HousingCreateNeighborhoodCharterFrame",
    },
    Blizzard_HousingDashboard = { "HousingDashboardFrame" },
    Blizzard_HousingHouseFinder = { "HouseFinderFrame" },
    Blizzard_HousingHouseSettings = {
        "AbandonHouseConfirmationDialog",
        "HousingHouseSettingsFrame",
    },
    Blizzard_HousingModelPreview = { "HousingModelPreviewFrame" },
    Blizzard_InspectUI = { "InspectFrame" },
    Blizzard_IslandsPartyPoseUI = { "IslandsPartyPoseFrame" },
    Blizzard_IslandsQueueUI = { "IslandsQueueFrame" },
    Blizzard_ItemInteractionUI = { "ItemInteractionFrame" },
    Blizzard_ItemSocketingUI = { "ItemSocketingFrame" },
    Blizzard_ItemUpgradeUI = { "ItemUpgradeFrame" },
    Blizzard_MacroUI = { "MacroFrame" },
    Blizzard_MatchCelebrationPartyPoseUI = { "MatchCelebrationPartyPoseFrame" },
    Blizzard_ObliterumUI = { "ObliterumForgeFrame" },
    Blizzard_OrderHallUI = { "OrderHallTalentFrame" },
    Blizzard_PlayerChoice = {
        { key = "PlayerChoiceFrame", secureHandle = true },
    },
    Blizzard_PlayerChoiceUI = {
        { key = "PlayerChoiceFrame", secureHandle = true },
    },
    Blizzard_PlayerSpells = { "HeroTalentsSelectionDialog", "PlayerSpellsFrame" },
    Blizzard_Professions = {
        "InspectRecipeFrame",
        "ProfessionsFrame",
        "ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog",
        "ProfessionsFrame.OrdersPage.OrderView.OrderDetails.SchematicForm.QualityDialog",
    },
    Blizzard_ProfessionsBook = { "ProfessionsBookFrame" },
    Blizzard_ProfessionsCustomerOrders = { "ProfessionsCustomerOrdersFrame" },
    Blizzard_PVPMatch = { "PVPMatchResults" },
    Blizzard_PVPUI = { "PVPMatchScoreboard" },
    Blizzard_RemixArtifactUI = { "RemixArtifactFrame" },
    Blizzard_RuneforgeUI = { "RuneforgeFrame" },
    Blizzard_ScrappingMachineUI = { "ScrappingMachineFrame" },
    Blizzard_Soulbinds = { "SoulbindViewer" },
    Blizzard_StableUI = { "StableFrame" },
    Blizzard_SubscriptionInterstitialUI = { "SubscriptionInterstitialFrame" },
    Blizzard_TalentUI = { "PlayerTalentFrame", "TalentFrame" },
    Blizzard_TimeManager = { "TimeManagerFrame" },
    Blizzard_TokenUI = { "CurrencyTransferMenu" },
    Blizzard_TorghastLevelPicker = { "TorghastLevelPickerFrame" },
    Blizzard_TradeSkillUI = { "TradeSkillFrame" },
    Blizzard_TrainerUI = { "ClassTrainerFrame" },
    Blizzard_Transmog = { "TransmogFrame" },
    Blizzard_VoidStorageUI = { "VoidStorageFrame" },
    Blizzard_WarfrontsPartyPoseUI = { "WarfrontsPartyPoseFrame" },
    Blizzard_WeeklyRewards = { "WeeklyRewardsFrame" },
}

local SKIPPED_WINDOWS = {
    CinematicFrame = true,
    GameMenuFrame = true,
    MovieFrame = true,
    WarbandCollectionFrame = true,
    WarbandCollectionsFrame = true,
    WarbandSceneCollectionFrame = true,
    WarbandSceneJournalFrame = true,
    WardrobeCollectionFrame = true,
    WardrobeFrame = true,
}

local Runtime = {
    enabled = false,
    generation = 0,
    records = {},
    recordsByFrame = {},
    sessionPositions = {},
    sessionScales = {},
}

local function safeCall(object, methodName, ...)
    local method = object and object[methodName]
    if type(method) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(method, object, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function clampScale(value)
    return clamp(value, MIN_SCALE, MAX_SCALE)
end

local function roundOne(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor((value * 10) + 0.5) / 10
    end
    return math.ceil((value * 10) - 0.5) / 10
end

local function copyPosition(position)
    if type(position) ~= "table" then return nil end
    local point = string.upper(tostring(position.point or "CENTER"))
    if not VALID_FRAME_POINTS[point] then point = "CENTER" end
    local relativePoint = string.upper(tostring(position.relativePoint or point))
    if not VALID_FRAME_POINTS[relativePoint] then relativePoint = point end
    return {
        point = point,
        relativePoint = relativePoint,
        x = tonumber(position.x) or 0,
        y = tonumber(position.y) or 0,
    }
end

local function isFrame(frame)
    if not frame then return false end
    if type(frame.IsObjectType) == "function" then
        local ok, result = pcall(frame.IsObjectType, frame, "Frame")
        if ok then return result == true end
    end
    return type(frame) == "table" and type(frame.SetPoint) == "function"
end

local function isForbidden(frame)
    return safeCall(frame, "IsForbidden") == true
end

local function isProtected(frame)
    return safeCall(frame, "IsProtected") == true
end

local function isCombatBlocked()
    -- A nominally unprotected top-level window may contain protected Blizzard
    -- or third-party unit-frame children. Mutating its movement state in combat
    -- can therefore taint a protected path even when frame:IsProtected() is false.
    return Addon.WoWApi:IsInCombatLockdown()
end

local function isAddonLoaded(addonName)
    return Addon.WoWApi:IsAddOnLoaded(addonName)
end

local function resolveFrame(framePath)
    if type(framePath) ~= "string" or framePath == "" then return nil end
    local current = _G
    for token in framePath:gmatch("[^%.]+") do
        current = current and current[token]
    end
    if isFrame(current) and not isForbidden(current) then return current end
    return nil
end

local function capturePoints(frame)
    local points = {}
    local count = math.max(0, math.floor(tonumber(safeCall(frame, "GetNumPoints")) or 0))
    if count == 0 and type(frame.GetPoint) == "function" then count = 1 end
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = safeCall(frame, "GetPoint", index)
        if type(point) == "string" then
            points[#points + 1] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = type(relativePoint) == "string" and relativePoint or point,
                x = tonumber(x) or 0,
                y = tonumber(y) or 0,
            }
        end
    end
    return #points > 0 and points or nil
end

local function applyPoints(frame, points)
    if not frame or type(points) ~= "table" or isCombatBlocked(frame) then return false end
    safeCall(frame, "ClearAllPoints")
    for _, position in ipairs(points) do
        safeCall(
            frame,
            "SetPoint",
            position.point or "CENTER",
            position.relativeTo or UIParent,
            position.relativePoint or position.point or "CENTER",
            tonumber(position.x) or 0,
            tonumber(position.y) or 0
        )
    end
    return true
end

local function normalizedDescriptor(value)
    if type(value) == "string" then
        return { key = value, frame = value, secureHandle = false }
    end
    if type(value) ~= "table" then return nil end
    local key = value.key or value.frame
    if type(key) ~= "string" or key == "" then return nil end
    return {
        key = key,
        frame = value.frame or key,
        frameRef = value.frameRef,
        secureHandle = value.secureHandle == true,
    }
end

local function showMessage(message)
    if type(message) ~= "string" or message == "" then return end
    if Addon.Print then
        Addon:Print(message)
    elseif UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        UIErrorsFrame:AddMessage(message, 1, 0.82, 0.22)
    end
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.windowMover = type(db.features.windowMover) == "table"
        and db.features.windowMover or {}
    local store = db.features.windowMover
    store.positions = type(store.positions) == "table" and store.positions or {}
    store.scales = type(store.scales) == "table" and store.scales or {}
    return store
end

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function modifierDown()
    return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

local function controlDown()
    return type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
end

local function isShown(frame)
    local shown = safeCall(frame, "IsShown")
    return shown == nil or shown == true
end

local function isMouseOver(frame)
    if type(MouseIsOver) == "function" then
        local ok, result = pcall(MouseIsOver, frame)
        if ok then return result == true end
    end
    local result = safeCall(frame, "IsMouseOver")
    return result == true
end

local function getFrameStackRank(frame)
    local strata = safeCall(frame, "GetFrameStrata")
    local level = tonumber(safeCall(frame, "GetFrameLevel")) or 0
    return ((FRAME_STRATA_RANK[strata] or 0) * 100000) + level
end

function Runtime:GetSaveMode()
    return setting("save_mode") == "permanent" and "permanent" or "session"
end

function Runtime:IsScalingEnabled()
    return setting("scaling") ~= false
end

function Runtime:RequiresMoveModifier()
    return setting("require_move_modifier") == true
end

function Runtime:GetStoredPosition(frameKey, mode)
    mode = mode or self:GetSaveMode()
    if mode == "permanent" then return getStore().positions[frameKey] end
    return self.sessionPositions[frameKey]
end

function Runtime:GetStoredScale(frameKey, mode)
    mode = mode or self:GetSaveMode()
    if mode == "permanent" then return getStore().scales[frameKey] end
    return self.sessionScales[frameKey]
end

function Runtime:SetStoredPosition(frameKey, position, mode)
    mode = mode or self:GetSaveMode()
    if mode == "permanent" then
        getStore().positions[frameKey] = copyPosition(position)
    else
        self.sessionPositions[frameKey] = copyPosition(position)
    end
end

function Runtime:SetStoredScale(frameKey, scale, mode)
    mode = mode or self:GetSaveMode()
    if mode == "permanent" then
        getStore().scales[frameKey] = scale and clampScale(scale) or nil
    else
        self.sessionScales[frameKey] = scale and clampScale(scale) or nil
    end
end

function Runtime:ClearStoredPosition(frameKey)
    self.sessionPositions[frameKey] = nil
    getStore().positions[frameKey] = nil
end

function Runtime:ClearStoredScale(frameKey)
    self.sessionScales[frameKey] = nil
    getStore().scales[frameKey] = nil
end

function Runtime:ClearStoredState(frameKey)
    self:ClearStoredPosition(frameKey)
    self:ClearStoredScale(frameKey)
end

function Runtime:ClearSkippedWindowState()
    for frameKey in pairs(SKIPPED_WINDOWS) do
        self:ClearStoredState(frameKey)
        local record = self.records[frameKey]
        if record then
            record.active = false
            self:RestoreOriginal(record)
            self.recordsByFrame[record.frame] = nil
            self.records[frameKey] = nil
        end
    end
end

function Runtime:GetFrameScale(frame)
    return math.max(0.01, tonumber(safeCall(frame, "GetScale")) or 1)
end

function Runtime:GetScreenSize()
    local width = type(GetScreenWidth) == "function" and tonumber(GetScreenWidth()) or nil
    local height = type(GetScreenHeight) == "function" and tonumber(GetScreenHeight()) or nil
    if width and height and width > 0 and height > 0 then return width, height end

    local parentScale = math.max(
        0.01,
        tonumber(safeCall(UIParent, "GetEffectiveScale"))
            or tonumber(safeCall(UIParent, "GetScale"))
            or 1
    )
    return (tonumber(safeCall(UIParent, "GetWidth")) or 0) * parentScale,
        (tonumber(safeCall(UIParent, "GetHeight")) or 0) * parentScale
end

function Runtime:GetPositionCenter(record, position)
    position = copyPosition(position)
    if not position then return nil end

    local parentWidth, parentHeight = self:GetScreenSize()
    if parentWidth <= 0 or parentHeight <= 0 then return nil end
    local scale = self:GetFrameScale(record.frame)
    local frameWidth = math.max(0, tonumber(safeCall(record.frame, "GetWidth")) or 0) * scale
    local frameHeight = math.max(0, tonumber(safeCall(record.frame, "GetHeight")) or 0) * scale
    local point = string.upper(position.point or "CENTER")
    local relativePoint = string.upper(position.relativePoint or point)

    local relativeX = string.find(relativePoint, "LEFT", 1, true) and 0
        or (string.find(relativePoint, "RIGHT", 1, true) and parentWidth or parentWidth * 0.5)
    local relativeY = string.find(relativePoint, "BOTTOM", 1, true) and 0
        or (string.find(relativePoint, "TOP", 1, true) and parentHeight or parentHeight * 0.5)
    local anchorX = string.find(point, "LEFT", 1, true) and (-frameWidth * 0.5)
        or (string.find(point, "RIGHT", 1, true) and frameWidth * 0.5 or 0)
    local anchorY = string.find(point, "BOTTOM", 1, true) and (-frameHeight * 0.5)
        or (string.find(point, "TOP", 1, true) and frameHeight * 0.5 or 0)
    return relativeX + position.x - anchorX, relativeY + position.y - anchorY
end

function Runtime:ClampPosition(record, position)
    position = copyPosition(position)
    if not position then return nil end

    local parentWidth, parentHeight = self:GetScreenSize()
    if parentWidth <= 0 or parentHeight <= 0 then return position end

    local frameScale = self:GetFrameScale(record.frame)
    local frameWidth = math.max(0, tonumber(safeCall(record.frame, "GetWidth")) or 0) * frameScale
    local frameHeight = math.max(0, tonumber(safeCall(record.frame, "GetHeight")) or 0) * frameScale
    local horizontalMargin = math.min(parentWidth * 0.5, math.max(POSITION_MARGIN, frameWidth * 0.5))
    local verticalMargin = math.min(parentHeight * 0.5, math.max(POSITION_MARGIN, frameHeight * 0.5))
    local centerX, centerY = self:GetPositionCenter(record, position)
    if not centerX or not centerY then return position end
    position.x = position.x
        + (clamp(centerX, horizontalMargin, parentWidth - horizontalMargin) - centerX)
    position.y = position.y
        + (clamp(centerY, verticalMargin, parentHeight - verticalMargin) - centerY)
    return position
end

function Runtime:CaptureLivePosition(record)
    if type(record) ~= "table" or not record.frame then return nil end
    local frame = record.frame
    local scale = self:GetFrameScale(frame)
    local parentWidth, parentHeight = self:GetScreenSize()
    if parentWidth <= 0 or parentHeight <= 0 then return nil end
    local left = tonumber(safeCall(frame, "GetLeft"))
    local right = tonumber(safeCall(frame, "GetRight"))
    local top = tonumber(safeCall(frame, "GetTop"))
    local bottom = tonumber(safeCall(frame, "GetBottom"))
    if left and right and top and bottom then
        left, right, top, bottom = left * scale, right * scale, top * scale, bottom * scale
    else
        local centerX, centerY = safeCall(frame, "GetCenter")
        if not centerX or not centerY then return nil end
        centerX, centerY = tonumber(centerX) * scale, tonumber(centerY) * scale
        local halfWidth = ((tonumber(safeCall(frame, "GetWidth")) or 0) * scale) * 0.5
        local halfHeight = ((tonumber(safeCall(frame, "GetHeight")) or 0) * scale) * 0.5
        left, right = centerX - halfWidth, centerX + halfWidth
        bottom, top = centerY - halfHeight, centerY + halfHeight
    end

    local centerX = (left + right) * 0.5
    local centerY = (bottom + top) * 0.5
    local horizontalCenterOffset = centerX - (parentWidth * 0.5)
    local verticalCenterOffset = centerY - (parentHeight * 0.5)
    local point = ""
    local x, y
    if left < (parentWidth - right) and left < math.abs(horizontalCenterOffset) then
        point, x = "LEFT", left
    elseif (parentWidth - right) < math.abs(horizontalCenterOffset) then
        point, x = "RIGHT", right - parentWidth
    else
        x = horizontalCenterOffset
    end
    if bottom < (parentHeight - top) and bottom < math.abs(verticalCenterOffset) then
        point, y = "BOTTOM" .. point, bottom
    elseif (parentHeight - top) < math.abs(verticalCenterOffset) then
        point, y = "TOP" .. point, top - parentHeight
    else
        y = verticalCenterOffset
    end
    if point == "" then point = "CENTER" end
    return self:ClampPosition(record, {
        point = point,
        relativePoint = point,
        x = roundOne(x),
        y = roundOne(y),
    })
end

function Runtime:EnsurePositionAnchor()
    if self.positionAnchorFrame then return self.positionAnchorFrame end
    if type(CreateFrame) ~= "function" then return UIParent end
    local ok, frame = pcall(CreateFrame, "Frame", nil, nil, "SecureFrameTemplate")
    if not ok or not frame then return UIParent end
    safeCall(frame, "SetAllPoints", UIParent)
    self.positionAnchorFrame = frame
    return frame
end

function Runtime:ApplyPosition(record, position)
    if type(record) ~= "table" or not record.frame or isCombatBlocked(record.frame) then
        return false
    end
    position = self:ClampPosition(record, position)
    if not position then return false end

    local scale = self:GetFrameScale(record.frame)
    local userPlaced = safeCall(record.frame, "IsUserPlaced")
    record.applyingPosition = true
    safeCall(record.frame, "ClearAllPoints")
    local setPoint = record.frame.SetPointBase or record.frame.SetPoint
    if type(setPoint) == "function" then
        pcall(
            setPoint,
            record.frame,
            position.point or "CENTER",
            self:EnsurePositionAnchor(),
            position.relativePoint or position.point or "CENTER",
            position.x / scale,
            position.y / scale
        )
    end
    if userPlaced ~= nil then safeCall(record.frame, "SetUserPlaced", userPlaced == true) end
    record.applyingPosition = false
    return true
end

function Runtime:SavePosition(record)
    local position = self:CaptureLivePosition(record)
    if not position then return false end
    self:SetStoredPosition(record.key, position)
    return true
end

function Runtime:SaveScale(record, scale)
    if type(record) ~= "table" then return false end
    self:SetStoredScale(record.key, scale)
    return true
end

function Runtime:CaptureOriginal(frame)
    return {
        points = capturePoints(frame),
        scale = tonumber(safeCall(frame, "GetScale")) or 1,
        mouse = safeCall(frame, "IsMouseEnabled"),
        mouseWheel = safeCall(frame, "IsMouseWheelEnabled"),
        movable = safeCall(frame, "IsMovable"),
        clamped = safeCall(frame, "IsClampedToScreen"),
        userPlaced = safeCall(frame, "IsUserPlaced"),
    }
end

function Runtime:RestoreFrameAccess(record)
    if type(record) ~= "table" or not record.frame or not record.original then return false end
    if isCombatBlocked(record.frame) then return false end
    if record.moving then
        safeCall(record.frame, "StopMovingOrSizing")
        record.moving = false
    end
    if record.handle then
        record.handle.onDragStartCallback = function() return false end
        safeCall(record.handle, "Hide")
    end
    if record.original.mouse ~= nil then
        safeCall(record.frame, "EnableMouse", record.original.mouse == true)
    end
    if record.original.mouseWheel ~= nil then
        safeCall(record.frame, "EnableMouseWheel", record.original.mouseWheel == true)
    end
    if record.original.movable ~= nil then
        safeCall(record.frame, "SetMovable", record.original.movable == true)
    end
    if record.original.clamped ~= nil then
        safeCall(record.frame, "SetClampedToScreen", record.original.clamped == true)
    end
    if record.original.userPlaced ~= nil then
        safeCall(record.frame, "SetUserPlaced", record.original.userPlaced == true)
    end
    return true
end

function Runtime:RestoreOriginal(record)
    if not self:RestoreFrameAccess(record) then return false end
    record.applyingPosition = true
    safeCall(record.frame, "SetScale", record.original.scale or 1)
    if record.original.points then applyPoints(record.frame, record.original.points) end
    record.applyingPosition = false
    return true
end

function Runtime:ApplyStoredState(record)
    if type(record) ~= "table" or not record.frame or isCombatBlocked(record.frame) then
        return false
    end
    local scale = tonumber(self:GetStoredScale(record.key))
    if scale then safeCall(record.frame, "SetScale", clampScale(scale)) end
    local position = self:GetStoredPosition(record.key)
    if position then self:ApplyPosition(record, position) end
    return true
end

function Runtime:ResetPosition(record, silent)
    if type(record) ~= "table" or not record.frame or isCombatBlocked(record.frame) then
        return false
    end
    self:ClearStoredPosition(record.key)
    record.applyingPosition = true
    if record.original and record.original.points then
        applyPoints(record.frame, record.original.points)
    end
    if record.original and record.original.userPlaced ~= nil then
        safeCall(record.frame, "SetUserPlaced", record.original.userPlaced == true)
    end
    record.applyingPosition = false
    if not silent then showMessage(Addon.L.WINDOW_MOVER_RESET_POSITION) end
    return true
end

function Runtime:ResetScale(record, silent)
    if type(record) ~= "table" or not record.frame or isCombatBlocked(record.frame) then
        return false
    end
    local position = self:CaptureLivePosition(record)
    self:ClearStoredScale(record.key)
    safeCall(record.frame, "SetScale", record.original and record.original.scale or 1)
    if position then
        self:ApplyPosition(record, position)
        self:SetStoredPosition(record.key, position)
    end
    if not silent then showMessage(Addon.L.WINDOW_MOVER_RESET_SCALE) end
    return true
end

function Runtime:ResetRecord(record, resetPosition, resetScale, silent)
    if type(record) ~= "table" or not record.frame or isCombatBlocked(record.frame) then
        return false
    end
    if resetPosition and resetScale then
        self:ClearStoredState(record.key)
        record.applyingPosition = true
        safeCall(record.frame, "SetScale", record.original and record.original.scale or 1)
        if record.original and record.original.points then
            applyPoints(record.frame, record.original.points)
        end
        if record.original and record.original.userPlaced ~= nil then
            safeCall(record.frame, "SetUserPlaced", record.original.userPlaced == true)
        end
        record.applyingPosition = false
        if not silent then showMessage(Addon.L.WINDOW_MOVER_RESET_BOTH) end
        return true
    end
    if resetPosition then return self:ResetPosition(record, silent) end
    if resetScale then return self:ResetScale(record, silent) end
    return false
end

function Runtime:ResetAll()
    if Addon.WoWApi:IsInCombatLockdown() then
        Addon.CombatQueue:RunOrQueue(FEATURE_ID .. ".reset", function()
            Runtime:ResetAll()
        end)
        showMessage(Addon.L.WINDOW_MOVER_COMBAT_BLOCKED)
        return true
    end

    for key in pairs(self.sessionPositions) do self.sessionPositions[key] = nil end
    for key in pairs(self.sessionScales) do self.sessionScales[key] = nil end
    local store = getStore()
    for key in pairs(store.positions) do store.positions[key] = nil end
    for key in pairs(store.scales) do store.scales[key] = nil end
    for _, record in pairs(self.records) do
        if record.active then self:ResetRecord(record, true, true, true) end
    end
    showMessage(Addon.L.WINDOW_MOVER_RESET_ALL_DONE)
    return true
end

local function merchantFrameOwnedByFilters(recordOrKey)
    local key = type(recordOrKey) == "table" and recordOrKey.key or recordOrKey
    local merchantFilters = Addon.MerchantFilters
    return key == "MerchantFrame"
        and merchantFilters
        and merchantFilters.enabled == true
        and type(merchantFilters.GetEffectiveDisplayMode) == "function"
        and merchantFilters:GetEffectiveDisplayMode() == "replace"
end

function Runtime:IsRecordActive(record)
    if merchantFrameOwnedByFilters(record) then
        return false
    end
    return self.enabled == true
        and not self.compatBlocked
        and type(record) == "table"
        and record.active == true
        and record.frame ~= nil
        and not isForbidden(record.frame)
end

function Runtime:GetRecordFromFocus(focus)
    local current = focus
    for _ = 1, 40 do
        local record = self.recordsByFrame[current]
        if record then return record end
        current = safeCall(current, "GetParent")
        if not current then break end
    end
    return nil
end

function Runtime:StartMove(record)
    if not self:IsRecordActive(record) or isCombatBlocked(record.frame) then return false end
    if self:RequiresMoveModifier() and not modifierDown() then return false end

    safeCall(record.frame, "SetMovable", true)
    safeCall(record.frame, "SetClampedToScreen", true)
    local userPlaced = safeCall(record.frame, "IsUserPlaced")
    record.moving = true

    if record.handle then
        record.handle.onDragStartCallback = nil
    else
        local ok = pcall(record.frame.StartMoving, record.frame)
        if not ok then
            record.moving = false
            return false
        end
    end
    if userPlaced ~= nil then safeCall(record.frame, "SetUserPlaced", userPlaced == true) end
    return true
end

function Runtime:StopMove(record)
    if type(record) ~= "table" or not record.moving then return false end
    if record.handle then
        record.handle.onDragStartCallback = function() return false end
    end
    if not isCombatBlocked(record.frame) then safeCall(record.frame, "StopMovingOrSizing") end
    record.moving = false
    local saved = self:SavePosition(record)
    if saved then self:ApplyPosition(record, self:GetStoredPosition(record.key)) end
    return saved
end

function Runtime:OnMouseDown(record, button)
    if button == "LeftButton" then
        record.mouseDownPosition = self:CaptureLivePosition(record)
        self:StartMove(record)
    end
end

function Runtime:OnMouseUp(record, button)
    if not self:IsRecordActive(record) then return end
    if button == "LeftButton" then
        if record.moving then
            self:StopMove(record)
        elseif record.mouseDownPosition and not isCombatBlocked(record.frame) then
            local currentPosition = self:CaptureLivePosition(record)
            local startX, startY = self:GetPositionCenter(record, record.mouseDownPosition)
            local currentX, currentY = self:GetPositionCenter(record, currentPosition)
            if startX and startY and currentX and currentY
                and (math.abs(currentX - startX) > 0.5 or math.abs(currentY - startY) > 0.5)
            then
                self:SetStoredPosition(record.key, currentPosition)
                self:ApplyPosition(record, currentPosition)
            end
        end
        record.mouseDownPosition = nil
        return
    end
    if button ~= "RightButton" or isCombatBlocked(record.frame) then return end

    local shift = modifierDown()
    local control = controlDown()
    if shift or control then
        self:ResetRecord(record, shift, control, false)
    end
end

function Runtime:ScaleRecord(record, delta)
    if not self:IsRecordActive(record)
        or not self:IsScalingEnabled()
        or not controlDown()
        or isCombatBlocked(record.frame)
    then
        return false
    end

    local position = self:CaptureLivePosition(record)
    local current = tonumber(safeCall(record.frame, "GetScale")) or 1
    local newScale = clampScale(current + ((tonumber(delta) or 0) * SCALE_STEP))
    if math.abs(newScale - current) < 0.0001 then return false end
    safeCall(record.frame, "SetScale", newScale)
    self:SaveScale(record, newScale)
    if position then
        self:ApplyPosition(record, position)
        self:SetStoredPosition(record.key, position)
    end
    return true
end

function Runtime:GetMouseFoci()
    if type(GetMouseFoci) == "function" then
        local ok, result = pcall(GetMouseFoci)
        if ok and type(result) == "table" then return result end
    end
    if type(GetMouseFocus) == "function" then
        local ok, focus = pcall(GetMouseFocus)
        if ok and focus then return { focus } end
    end
    return nil
end

function Runtime:FindHoveredScaleRecord()
    local foci = self:GetMouseFoci()
    if foci then
        for _, focus in ipairs(foci) do
            if focus and not isForbidden(focus) then
                local record = self:GetRecordFromFocus(focus)
                if self:IsRecordActive(record) and isShown(record.frame) then return record end
                local wheelEnabled = safeCall(focus, "IsMouseWheelEnabled") == true
                local clickEnabled = safeCall(focus, "IsMouseClickEnabled") == true
                    or safeCall(focus, "IsMouseEnabled") == true
                if wheelEnabled or clickEnabled then return nil end
            end
        end
        return nil
    end

    local bestRecord, bestRank
    for _, record in pairs(self.records) do
        if self:IsRecordActive(record) and isShown(record.frame) and isMouseOver(record.frame) then
            local rank = getFrameStackRank(record.frame)
            if not bestRank or rank > bestRank then
                bestRecord, bestRank = record, rank
            end
        end
    end
    return bestRecord
end

function Runtime:RefreshScaleCapture()
    local capture = self.scaleCaptureFrame
    if not capture then return end
    capture:EnableMouseWheel(false)
    self.hoveredScaleRecord = nil

    if not self.enabled
        or self.compatBlocked
        or Addon.WoWApi:IsInCombatLockdown()
        or not self:IsScalingEnabled()
        or not controlDown()
    then
        capture:SetScript("OnUpdate", nil)
        capture.updating = false
        return
    end

    local record = self:FindHoveredScaleRecord()
    self.hoveredScaleRecord = record
    capture:EnableMouseWheel(record ~= nil)
    if not capture.updating then
        capture:SetScript("OnUpdate", function() Runtime:RefreshScaleCapture() end)
        capture.updating = true
    end
end

function Runtime:EnsureScaleCaptureFrame()
    if self.scaleCaptureFrame then return end
    local capture = CreateFrame("Frame", nil, UIParent)
    capture:SetAllPoints(UIParent)
    capture:SetFrameStrata(SCALE_CAPTURE_STRATA)
    capture:SetFrameLevel(SCALE_CAPTURE_LEVEL)
    capture:EnableMouseWheel(false)
    capture:SetScript("OnMouseWheel", function(_, delta)
        local record = Runtime.hoveredScaleRecord or Runtime:FindHoveredScaleRecord()
        if Runtime:ScaleRecord(record, delta) then Runtime:RefreshScaleCapture() end
    end)
    capture:SetScript("OnEvent", function() Runtime:RefreshScaleCapture() end)
    capture:Hide()
    self.scaleCaptureFrame = capture
end

function Runtime:SetScaleCaptureEnabled(enabled)
    self:EnsureScaleCaptureFrame()
    local capture = self.scaleCaptureFrame
    enabled = enabled == true
    if enabled and not self.scaleCaptureEventRegistered then
        local ok, registered = pcall(capture.RegisterEvent, capture, "MODIFIER_STATE_CHANGED")
        self.scaleCaptureEventRegistered = ok and registered ~= false
    elseif not enabled and self.scaleCaptureEventRegistered then
        pcall(capture.UnregisterEvent, capture, "MODIFIER_STATE_CHANGED")
        self.scaleCaptureEventRegistered = false
    end
    if enabled then
        capture:Show()
    else
        capture:EnableMouseWheel(false)
        capture:SetScript("OnUpdate", nil)
        capture.updating = false
        self.hoveredScaleRecord = nil
        capture:Hide()
    end
end

function Runtime:CreateSecureMoveHandle(record)
    if record.handle then
        record.handle:Show()
        return record.handle
    end

    local handle = CreateFrame("Frame", nil, record.frame, "PanelDragBarTemplate")
    handle:SetParent(record.frame)
    handle:SetAllPoints(record.frame)
    handle:SetFrameLevel((tonumber(safeCall(record.frame, "GetFrameLevel")) or 1) + 1)
    safeCall(handle, "SetPropagateMouseMotion", true)
    safeCall(handle, "SetPropagateMouseClicks", true)
    safeCall(handle, "EnableMouse", true)
    safeCall(handle, "RegisterForDrag", "LeftButton")
    if type(RegisterStateDriver) == "function" then
        local ok = pcall(RegisterStateDriver, handle, "visibility", "[combat] hide; show")
        record.handleCombatDriver = ok == true
    end
    handle.onDragStartCallback = function() return false end
    handle:HookScript("OnMouseDown", function(_, button)
        Runtime:OnMouseDown(record, button)
    end)
    handle:HookScript("OnMouseUp", function(_, button)
        Runtime:OnMouseUp(record, button)
    end)
    handle:HookScript("OnDragStop", function()
        Runtime:OnMouseUp(record, "LeftButton")
    end)
    record.handle = handle
    handle:Show()
    return handle
end

function Runtime:HookRecord(record)
    if record.hooked then return end
    record.hooked = true
    record.frame:HookScript("OnShow", function()
        Runtime:OnFrameShow(record)
    end)
    record.frame:HookScript("OnHide", function()
        Runtime:OnFrameHide(record)
    end)

    if record.useSecureHandle then
        self:CreateSecureMoveHandle(record)
    else
        record.frame:HookScript("OnMouseDown", function(_, button)
            Runtime:OnMouseDown(record, button)
        end)
        record.frame:HookScript("OnMouseUp", function(_, button)
            Runtime:OnMouseUp(record, button)
        end)
    end

    if type(hooksecurefunc) == "function" then
        for _, methodName in ipairs({ "ClearAllPoints", "SetPoint", "SetAllPoints" }) do
            if type(record.frame[methodName]) == "function" then
                pcall(hooksecurefunc, record.frame, methodName, function()
                    Runtime:OnFrameSetPoint(record)
                end)
            end
        end
    end
end

function Runtime:ApplyFrameAccess(record)
    if not self:IsRecordActive(record) or isCombatBlocked(record.frame) then return false end
    safeCall(record.frame, "SetMovable", true)
    safeCall(record.frame, "SetClampedToScreen", true)
    if record.useSecureHandle then
        self:CreateSecureMoveHandle(record)
    else
        safeCall(record.frame, "EnableMouse", true)
    end
    self:ApplyStoredState(record)
    return true
end

function Runtime:OnFrameShow(record)
    if not self:IsRecordActive(record) then return end
    if isCombatBlocked(record.frame) then
        self:ScheduleRegistration(0.25)
        return
    end
    self:ApplyFrameAccess(record)
    local generation = self.generation
    local function reapply()
        if Runtime.enabled
            and Runtime.generation == generation
            and Runtime:IsRecordActive(record)
            and not record.moving
        then
            Runtime:ApplyStoredState(record)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        for _, delay in ipairs({ 0, 0.05, 0.20 }) do
            C_Timer.After(delay, function()
                reapply()
            end)
        end
    else
        reapply()
    end
end

function Runtime:RefreshStoredPositions(group)
    if not self.enabled then return end
    for key, record in pairs(self.records) do
        local isContainer = key == "ContainerFrameCombinedBags"
            or string.match(key, "^ContainerFrame%d+$") ~= nil
        local groupMatches = group == nil
            or (group == "containers" and isContainer)
            or (group == "panels" and not isContainer)
        if groupMatches
            and self:IsRecordActive(record)
            and not record.moving
            and self:GetStoredPosition(key)
            and safeCall(record.frame, "IsShown") ~= false
        then
            self:ApplyPosition(record, self:GetStoredPosition(key))
        end
    end
end

function Runtime:RefreshPanelPositionsNow(frame)
    if not self.enabled or Addon.WoWApi:IsInCombatLockdown() or self.compatBlocked then
        return false
    end

    local frameName = safeCall(frame, "GetName")
    local isKnownPanel = type(frameName) == "string"
        and frameName ~= ""
        and (
            self.records[frameName] ~= nil
            or (type(UIPanelWindows) == "table" and UIPanelWindows[frameName] ~= nil)
        )
    if isKnownPanel then
        self:RegisterWindow({ key = frameName, frameRef = frame })
    end

    self:RefreshStoredPositions("panels")
    return true
end

function Runtime:ScheduleStoredPositionRefresh(group, delay)
    if not self.enabled then return end
    self.layoutRefreshPending = self.layoutRefreshPending or {}
    local pendingKey = tostring(group or "all") .. ":" .. tostring(tonumber(delay) or 0)
    if self.layoutRefreshPending[pendingKey] then return end
    self.layoutRefreshPending[pendingKey] = true
    local generation = self.generation
    local function refresh()
        Runtime.layoutRefreshPending[pendingKey] = nil
        if Runtime.enabled and Runtime.generation == generation then
            Runtime:RefreshStoredPositions(group)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(tonumber(delay) or 0, refresh)
    else
        refresh()
    end
end

function Runtime:SchedulePanelRegistration()
    if self.enabled then
        self:ScheduleRegistration(0)
        self:ScheduleRegistration(0.10)
        self:ScheduleStoredPositionRefresh("panels", 0)
        self:ScheduleStoredPositionRefresh("panels", 0.10)
    end
end

function Runtime:ScheduleContainerRefresh()
    if self.enabled then
        self:ScheduleStoredPositionRefresh("containers", 0)
        self:ScheduleStoredPositionRefresh("containers", 0.10)
    end
end

function Runtime:InstallGlobalHook(globalName, callback)
    self.globalHooks = self.globalHooks or {}
    if self.globalHooks[globalName]
        or type(hooksecurefunc) ~= "function"
        or type(_G[globalName]) ~= "function"
    then
        return false
    end
    local ok = pcall(hooksecurefunc, globalName, callback)
    if ok then self.globalHooks[globalName] = true end
    return ok
end

function Runtime:OnFrameHide(record)
    if record and record.moving then self:StopMove(record) end
end

function Runtime:OnFrameSetPoint(record)
    if not self:IsRecordActive(record)
        or record.applyingPosition
        or record.moving
        or not self:GetStoredPosition(record.key)
        or record.positionRefreshPending
    then
        return
    end
    record.positionRefreshPending = true
    local generation = self.generation
    local function reapplyPosition()
        record.positionRefreshPending = false
        if Runtime.enabled
            and Runtime.generation == generation
            and Runtime:IsRecordActive(record)
            and not record.moving
        then
            Runtime:ApplyPosition(record, Runtime:GetStoredPosition(record.key))
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, reapplyPosition) else reapplyPosition() end
end

function Runtime:RegisterWindow(value)
    local descriptor = normalizedDescriptor(value)
    if not descriptor or SKIPPED_WINDOWS[descriptor.key] then
        if descriptor then self:ClearStoredState(descriptor.key) end
        return false
    end
    local frame = descriptor.frameRef or resolveFrame(descriptor.frame)
    if not frame or isCombatBlocked(frame) then return false end
    if merchantFrameOwnedByFilters(descriptor.key) then
        return false
    end

    local record = self.records[descriptor.key]
    if record and record.frame ~= frame then
        record.active = false
        self:RestoreOriginal(record)
        self.recordsByFrame[record.frame] = nil
        record = nil
    end
    if not record then
        record = {
            key = descriptor.key,
            frame = frame,
            original = self:CaptureOriginal(frame),
            active = true,
            useSecureHandle = descriptor.secureHandle or isProtected(frame),
        }
        self.records[descriptor.key] = record
        self.recordsByFrame[frame] = record
        self:HookRecord(record)
    else
        record.active = true
        record.useSecureHandle = descriptor.secureHandle or isProtected(frame)
    end
    self:ApplyFrameAccess(record)
    return true
end

function Runtime:RegisterCoreWindows()
    for _, frameName in ipairs(CORE_WINDOWS) do self:RegisterWindow(frameName) end
    for index = 1, 13 do self:RegisterWindow("ContainerFrame" .. index) end
end

function Runtime:RegisterUIPanelWindows()
    if type(UIPanelWindows) ~= "table" then return end
    for frameName in pairs(UIPanelWindows) do
        if type(frameName) == "string" and frameName ~= "" then self:RegisterWindow(frameName) end
    end
end

function Runtime:RegisterAddonWindows(addonName)
    for _, descriptor in ipairs(ADDON_WINDOWS[addonName] or {}) do
        self:RegisterWindow(descriptor)
    end
end

function Runtime:RegisterLoadedAddonWindows()
    for addonName in pairs(ADDON_WINDOWS) do
        if isAddonLoaded(addonName) then self:RegisterAddonWindows(addonName) end
    end
end

function Runtime:RegisterAllWindows()
    if not self.enabled then return false end
    self:EnsurePermanentHooks()
    if Addon.WoWApi:IsInCombatLockdown() then
        self:RefreshScaleCapture()
        return false
    end
    if self:IsCompatBlocked() then
        self:DeactivateAll(true)
        self:RefreshScaleCapture()
        return false
    end
    self:RegisterCoreWindows()
    self:RegisterUIPanelWindows()
    self:RegisterLoadedAddonWindows()
    self:RefreshScaleCapture()
    return true
end

function Runtime:ScheduleRegistration(delay)
    if not self.enabled then return end
    local generation = self.generation
    if C_Timer and type(C_Timer.After) == "function" then
        local register = function()
            if Runtime.enabled and Runtime.generation == generation then Runtime:RegisterAllWindows() end
        end
        C_Timer.After(
            tonumber(delay) or 0,
            Addon.PerformanceDiagnostics:Wrap(
                Runtime,
                "timer",
                "window_mover.register",
                register
            )
        )
    else
        local register = Addon.PerformanceDiagnostics:Wrap(
            Runtime,
            "timer",
            "window_mover.register",
            function() Runtime:RegisterAllWindows() end
        )
        register()
    end
end

function Runtime:EnsurePermanentHooks()
    if not self.containerHooked
        and type(hooksecurefunc) == "function"
        and type(ContainerFrameMixin) == "table"
        and type(ContainerFrameMixin.OnLoad) == "function"
    then
        local ok = pcall(hooksecurefunc, ContainerFrameMixin, "OnLoad", function(frame)
            if Runtime.enabled then
                Runtime:RegisterWindow({ key = safeCall(frame, "GetName"), frameRef = frame })
            end
        end)
        self.containerHooked = ok == true
    end

    self:InstallGlobalHook("ShowUIPanel", function(frame)
        Runtime:RefreshPanelPositionsNow(frame)
        Runtime:SchedulePanelRegistration()
    end)
    self:InstallGlobalHook("ToggleFrame", function(frame)
        Runtime:RefreshPanelPositionsNow(frame)
        Runtime:SchedulePanelRegistration()
    end)
    self:InstallGlobalHook("UpdateUIPanelPositions", function()
        Runtime:RefreshPanelPositionsNow()
        Runtime:ScheduleStoredPositionRefresh("panels", 0)
    end)
    self:InstallGlobalHook("UpdateContainerFrameAnchors", function()
        Runtime:ScheduleContainerRefresh()
    end)
    self:InstallGlobalHook("ContainerFrame_UpdateAll", function()
        Runtime:ScheduleContainerRefresh()
    end)
end

function Runtime:IsCompatBlocked()
    local blocked = isAddonLoaded("BlizzMove")
    self.compatBlocked = blocked
    if blocked and not self.compatWarned then
        self.compatWarned = true
        showMessage(Addon.L.WINDOW_MOVER_COMPAT)
    end
    return blocked
end

function Runtime:DeactivateAll(restoreOriginal)
    for _, record in pairs(self.records) do
        if restoreOriginal then self:RestoreOriginal(record) else self:RestoreFrameAccess(record) end
        record.active = false
    end
    self:RefreshScaleCapture()
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "PLAYER_REGEN_DISABLED" then
        self.hoveredScaleRecord = nil
        if self.scaleCaptureFrame then
            self.scaleCaptureFrame:EnableMouseWheel(false)
            self.scaleCaptureFrame:SetScript("OnUpdate", nil)
            self.scaleCaptureFrame.updating = false
        end
        for _, record in pairs(self.records) do
            record.moving = false
            if record.handle then
                record.handle.onDragStartCallback = function() return false end
            end
        end
        return
    end
    if eventName == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BlizzMove" then
            self:IsCompatBlocked()
            self:DeactivateAll(true)
            return
        end
        if not self:IsCompatBlocked() then
            self:RegisterAddonWindows(addonName)
            self:ScheduleRegistration(0)
            self:ScheduleRegistration(0.15)
            self:ScheduleRegistration(0.75)
        end
        return
    end
    if eventName == "DISPLAY_SIZE_CHANGED" or eventName == "UI_SCALE_CHANGED" then
        self:ScheduleRegistration(0)
        return
    end
    self:RegisterAllWindows()
end

function Runtime:OnSettingChanged(settingKey)
    if settingKey == "save_mode" then
        for _, record in pairs(self.records) do
            if record.active and not isCombatBlocked(record.frame) then
                record.applyingPosition = true
                safeCall(record.frame, "SetScale", record.original and record.original.scale or 1)
                if record.original and record.original.points then applyPoints(record.frame, record.original.points) end
                record.applyingPosition = false
                self:ApplyStoredState(record)
            end
        end
    elseif settingKey == "scaling" then
        self:RefreshScaleCapture()
    end
end

function Runtime:OnSettingsReset()
    self:OnSettingChanged("save_mode")
    self:RefreshScaleCapture()
end

function Runtime:OnAction(actionKey)
    if actionKey == "reset_layout" then return self:ResetAll() end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    self.compatBlocked = false
    self.generation = self.generation + 1
    self:ClearSkippedWindowState()
    self:SetScaleCaptureEnabled(true)
    self:EnsurePermanentHooks()
    for _, eventName in ipairs({
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "DISPLAY_SIZE_CHANGED",
        "UI_SCALE_CHANGED",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:RegisterAllWindows()
    self:ScheduleRegistration(0.25)
    self:ScheduleRegistration(1)
end

function Runtime:OnDisable()
    self.enabled = false
    self.generation = self.generation + 1
    self:SetScaleCaptureEnabled(false)
    self:DeactivateAll(true)
    self.compatBlocked = false
end

Addon.BlizzardWindowMover = Runtime

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Blizzard Window Mover runtime.")
end
