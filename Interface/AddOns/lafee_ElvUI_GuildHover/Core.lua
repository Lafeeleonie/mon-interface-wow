local addonName, addon = ...

local E, L, V, P, G = unpack(ElvUI)
local DT = E:GetModule("DataTexts")

addon.name = addonName
addon.version = "1.1.10"
addon.E = E
addon.DT = DT
addon.sources = {}
addon.communitySources = {}
addon.debug = false
addon.initialized = false
addon.initialClubsLoaded = false

local format = string.format
local floor = math.floor
local max = math.max
local min = math.min
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local wipe = wipe

local function SecureCall(func, ...)
    if not func then return end
    if securecallfunction then
        return securecallfunction(func, ...)
    end
    return func(...)
end

local POPUP_WIDTH = 440
local ROW_HEIGHT = 22
local MAX_VISIBLE_ROWS = 18
local POPUP_PADDING = 10
local COMMUNITY_DISCOVERY_RETRY_DELAY = 1
local COMMUNITY_DISCOVERY_MAX_RETRIES = 15

local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_GUILD_UPDATE",
    "GUILD_ROSTER_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "CLUB_ADDED",
    "CLUB_REMOVED",
    "CLUB_UPDATED",
    "CLUB_MEMBER_ADDED",
    "CLUB_MEMBER_REMOVED",
    "CLUB_MEMBER_UPDATED",
    "CLUB_MEMBERS_UPDATED",
    "CLUB_MEMBER_PRESENCE_UPDATED",
    "INITIAL_CLUBS_LOADED",
    "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_FRIEND_INFO_CHANGED",
    "FRIENDLIST_UPDATE",
    "CHAT_MSG_SYSTEM",
}
local SUPPORTED_REFRESH_EVENTS = {}

local function IsSafeValue(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    if E.NotSecretValue then
        return E:NotSecretValue(value)
    end
    return value ~= nil
end

local function ClassColor(classFile)
    return classFile and RAID_CLASS_COLORS[classFile]
end

local function GroupContains(fullName)
    if not fullName then return false end
    return UnitInParty(fullName) or UnitInRaid(fullName)
end

function addon:Print(message)
    E:Print(format("|cff4da6ff%s|r : %s", addonName, message))
end

function addon:Debug(message)
    if self.debug then
        self:Print("DEBUG - " .. message)
    end
end

function addon:InitializeDatabase()
    if type(LafeeElvUIGuildHoverDB) ~= "table" then
        LafeeElvUIGuildHoverDB = {}
    end
    if type(LafeeElvUIGuildHoverDB.communities) ~= "table" then
        LafeeElvUIGuildHoverDB.communities = {}
    end
    self.db = LafeeElvUIGuildHoverDB
end

function addon:GetClassFile(classID)
    if not classID then return nil end
    local _, classFile = GetClassInfo(classID)
    return classFile
end

function addon:CanInviteMember(member)
    return member and member.canInvite and not InCombatLockdown()
end

function addon:WhisperMember(member)
    if not member or not member.canWhisper then
        self:Print("Chuchotement indisponible pour ce membre.")
        return
    end

    if member.bnetAccountName then
        local sendBNetTell = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if sendBNetTell then
            sendBNetTell(member.bnetAccountName)
        else
            self:Print("Chuchotement Battle.net indisponible.")
        end
        return
    end

    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(member.fullName)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(member.fullName)
    else
        self:Print("Chuchotement indisponible.")
    end
end

function addon:InviteMember(member)
    if not member or not member.canInvite then
        self:Print("Invitation indisponible pour ce membre.")
        return
    end
    if InCombatLockdown() then
        self:Print("Invitation différée : action indisponible en combat.")
        return
    end

    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(member.fullName)
    elseif InviteUnit then
        InviteUnit(member.fullName)
    end
end

function addon:CreatePopup()
    if self.popup then return self.popup end

    local popup = CreateFrame("Frame", addonName .. "MemberPopup", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetSize(POPUP_WIDTH, 120)
    popup:CreateBackdrop("Transparent")
    popup.backdrop:SetBackdropColor(0.05, 0.05, 0.05, 0.96)

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.title:SetPoint("TOPLEFT", POPUP_PADDING, -POPUP_PADDING)
    popup.title:SetJustifyH("LEFT")
    popup.title:SetWidth(POPUP_WIDTH - (POPUP_PADDING * 2))

    popup.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.empty:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -8)
    popup.empty:SetText("Aucun membre connecté.")

    popup.scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    popup.scroll:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -6)
    popup.scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -28, 26)

    popup.content = CreateFrame("Frame", nil, popup.scroll)
    popup.content:SetSize(POPUP_WIDTH - 42, 1)
    popup.scroll:SetScrollChild(popup.content)

    popup.legend = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.legend:SetPoint("BOTTOMLEFT", POPUP_PADDING, 8)
    popup.legend:SetText("Clic gauche : chuchoter    Clic droit : inviter")

    popup.rows = {}
    popup:SetScript("OnEnter", function()
        addon:CancelPopupHide()
    end)
    popup:SetScript("OnLeave", function()
        addon:SchedulePopupHide()
    end)
    popup:Hide()

    self.popup = popup
    return popup
end

function addon:CreateRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:EnableMouse(true)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0, 0, 0, 0)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", 4, 0)
    row.level:SetWidth(28)
    row.level:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.level, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")

    row.secondary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.secondary:SetPoint("RIGHT", -8, 0)
    row.secondary:SetWidth(150)
    row.secondary:SetJustifyH("RIGHT")
    row.secondary:SetTextColor(0.35, 0.65, 1)
    row.secondary:Hide()

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.55, 0.9, 0.2)
        addon:CancelPopupHide()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        addon:SchedulePopupHide()
    end)
    row:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            addon:WhisperMember(self.member)
        elseif button == "RightButton" then
            addon:InviteMember(self.member)
        end
    end)

    return row
end

function addon:UpdateRow(row, member)
    row.member = member
    local classColor = ClassColor(member.classFile)
    row.level:SetText(member.level and tostring(member.level) or "--")
    row.name:SetText((member.isFavorite and "|TInterface\\COMMON\\FavoritesIcon:12:12:0:0|t " or "") .. (member.name or "Inconnu"))
    if member.nameColor then
        row.name:SetTextColor(member.nameColor.r, member.nameColor.g, member.nameColor.b)
    elseif classColor then
        row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        row.name:SetTextColor(1, 1, 1)
    end

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.level, "RIGHT", 8, 0)
    if member.secondaryText and member.secondaryText ~= "" then
        row.secondary:SetText(member.secondaryText)
        row.secondary:Show()
        row.name:SetPoint("RIGHT", row.secondary, "LEFT", -8, 0)
    else
        row.secondary:SetText("")
        row.secondary:Hide()
        row.name:SetPoint("RIGHT", -8, 0)
    end
    row:Show()
end

function addon:PositionPopup(owner, popup)
    popup:ClearAllPoints()
    local screenTop = UIParent:GetTop() or UIParent:GetHeight()
    local ownerTop = owner:GetTop() or 0
    local ownerBottom = owner:GetBottom() or 0
    local spaceAbove = max(0, screenTop - ownerTop)
    local spaceBelow = max(0, ownerBottom)

    if spaceAbove >= popup:GetHeight() + 4 or spaceAbove >= spaceBelow then
        popup:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    else
        popup:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    end
end

function addon:RenderPopup(source, owner)
    local popup = self:CreatePopup()
    local members = source.members or {}
    local visibleRows = min(#members, MAX_VISIBLE_ROWS)
    local contentHeight = max(1, #members * ROW_HEIGHT)
    local popupHeight = 60 + max(1, visibleRows) * ROW_HEIGHT

    popup.source = source
    popup.owner = owner
    popup.title:SetText(format("%s : %d connecté(s)", source.displayName, #members))
    popup.empty:SetShown(#members == 0)
    popup.scroll:SetShown(#members > 0)
    popup.content:SetHeight(contentHeight)
    popup:SetHeight(popupHeight)

    for index, member in ipairs(members) do
        local row = popup.rows[index]
        if not row then
            row = self:CreateRow(popup.content)
            popup.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))
        self:UpdateRow(row, member)
    end
    for index = #members + 1, #popup.rows do
        popup.rows[index]:Hide()
    end

    self:PositionPopup(owner, popup)
    popup:Show()
end

function addon:ShowMemberList(owner, source)
    self:CancelPopupHide()
    if source.RefreshMembers then
        source:RefreshMembers()
    end
    self:RenderPopup(source, owner)
end

function addon:OpenSourceWindow(source)
    if not source then return end
    if InCombatLockdown() then
        self:Print("Ouverture indisponible en combat.")
        return
    end

    self:CancelPopupHide()
    if self.popup then
        self.popup:Hide()
    end

    local clubId = source.clubId
    if source.isGuild and C_Club and C_Club.GetGuildClubId then
        clubId = C_Club.GetGuildClubId()
    end

    if not clubId then
        if source.isGuild and ToggleGuildFrame then
            SecureCall(ToggleGuildFrame)
        elseif source.isGuild then
            self:Print("Fenêtre de guilde indisponible.")
        end
        return
    end

    local communitiesFrame = CommunitiesFrame
    if not communitiesFrame or not communitiesFrame:IsShown() then
        local toggleFrame = source.isGuild and ToggleGuildFrame or ToggleCommunitiesFrame
        toggleFrame = toggleFrame or ToggleCommunitiesFrame or ToggleGuildFrame
        if not toggleFrame then
            self:Print("Fenêtre des communautés indisponible.")
            return
        end
        SecureCall(toggleFrame)
        communitiesFrame = CommunitiesFrame
    end

    -- Do not call CommunitiesFrame:SelectClub() here. In 12.x that path reaches
    -- restricted C_Club functions and is blocked when initiated by an addon.
end

function addon:SchedulePopupHide()
    self.popupHideGeneration = (self.popupHideGeneration or 0) + 1
    local generation = self.popupHideGeneration
    C_Timer.After(0.15, function()
        if generation ~= addon.popupHideGeneration or not addon.popup then return end
        local popup = addon.popup
        local owner = popup.owner
        if not popup:IsMouseOver() and not (owner and owner:IsMouseOver()) then
            popup:Hide()
        end
    end)
end

function addon:CancelPopupHide()
    self.popupHideGeneration = (self.popupHideGeneration or 0) + 1
end

function addon:UpdatePanel(panel, source)
    if not panel or not panel.text then return end
    panel.text:SetText(format("%s : %d", source.displayName, #(source.members or {})))
end

function addon:IsSourcePanelAssigned(source, panel)
    local assigned = DT.AssignedDatatexts and DT.AssignedDatatexts[panel]
    return assigned and assigned.name == source.key
end

function addon:RefreshSource(source)
    if source and not source.removed and source.RefreshMembers then
        source:RefreshMembers()
        for panel in pairs(source.panels or {}) do
            if self:IsSourcePanelAssigned(source, panel) then
                self:UpdatePanel(panel, source)
            else
                source.panels[panel] = nil
            end
        end
    end
end

function addon:RefreshAll()
    for _, source in pairs(self.sources) do
        self:RefreshSource(source)
    end
    if self.popup and self.popup:IsShown() and self.popup.source then
        self:RenderPopup(self.popup.source, self.popup.owner)
    end
end

function addon:ScheduleRefresh(reason)
    self.refreshGeneration = (self.refreshGeneration or 0) + 1
    local generation = self.refreshGeneration
    C_Timer.After(0.35, function()
        if generation ~= addon.refreshGeneration then return end
        addon:Debug("Rafraîchissement : " .. (reason or "événement"))
        if addon.DiscoverCommunities then
            addon:DiscoverCommunities(false)
        end
        addon:RefreshAll()
    end)
end

-- Club data is populated asynchronously during login.  ADDON_LOADED and even
-- PLAYER_ENTERING_WORLD can happen before C_Club returns the subscribed clubs.
-- Retry briefly until INITIAL_CLUBS_LOADED arrives so community datatexts are
-- registered on the first login just as they are after a UI reload.
function addon:ScheduleCommunityDiscoveryRetry(attempt)
    attempt = attempt or 1
    if attempt > COMMUNITY_DISCOVERY_MAX_RETRIES then return end

    self.communityDiscoveryRetryGeneration = (self.communityDiscoveryRetryGeneration or 0) + 1
    local generation = self.communityDiscoveryRetryGeneration
    C_Timer.After(COMMUNITY_DISCOVERY_RETRY_DELAY, function()
        if generation ~= addon.communityDiscoveryRetryGeneration then return end
        if addon.initialClubsLoaded then return end

        if addon.DiscoverCommunities then
            addon:DiscoverCommunities(false)
        end
        addon:RefreshAll()
        addon:ScheduleCommunityDiscoveryRetry(attempt + 1)
    end)
end

function addon:OnInitialClubsLoaded()
    self.initialClubsLoaded = true
    self.communityDiscoveryRetryGeneration = (self.communityDiscoveryRetryGeneration or 0) + 1

    -- Defer one frame: Blizzard can dispatch INITIAL_CLUBS_LOADED just before
    -- the returned club records are readable by C_Club.
    C_Timer.After(0, function()
        if addon.DiscoverCommunities then
            addon:DiscoverCommunities(false)
        end
        addon:RefreshAll()
    end)
end

function addon:HasVisibleDataText()
    if self.popup and self.popup:IsShown() then
        return true
    end

    for _, source in pairs(self.sources) do
        for panel in pairs(source.panels or {}) do
            if self:IsSourcePanelAssigned(source, panel) and panel:IsShown() then
                return true
            end
            source.panels[panel] = nil
        end
    end
    return false
end

function addon:StartAutoRefresh()
    if self.autoRefreshTicker or not (C_Timer and C_Timer.NewTicker) then return end

    self.autoRefreshTicker = C_Timer.NewTicker(20, function()
        if addon:HasVisibleDataText() then
            addon:ScheduleRefresh("timer")
        end
    end)
end

function addon:RegisterDataText(source)
    if source.registered then return end
    source.panels = setmetatable({}, { __mode = "k" })

    DT:RegisterDatatext(source.key, "Lafee GuildHover", SUPPORTED_REFRESH_EVENTS, function(panel, event)
        source.panels[panel] = true
        addon:ScheduleRefresh(event)
        addon:UpdatePanel(panel, source)
    end, nil, function(_, button)
        if button == "LeftButton" then
            addon:OpenSourceWindow(source)
        end
    end, function(panel)
        source.panels[panel] = true
        addon:ShowMemberList(panel, source)
    end, function()
        addon:SchedulePopupHide()
    end, source.listName or source.displayName)

    source.registered = true
    self.sources[source.key] = source
    if DT.Initialized and DT.UpdateQuickDT then
        DT:UpdateQuickDT()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
for _, event in ipairs(REFRESH_EVENTS) do
    local registered = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if registered then
        tinsert(SUPPORTED_REFRESH_EVENTS, event)
    else
        addon:Debug("Événement indisponible ignoré : " .. event)
    end
end

local function InitializeSources()
    if addon.initialized then return end

    addon.initialized = true
    addon:InitializeDatabase()
    if addon.RegisterGuildDataText then
        addon:RegisterGuildDataText()
    end
    if addon.RegisterContactsDataText then
        addon:RegisterContactsDataText()
    end
    if addon.RestoreSavedCommunities then
        addon:RestoreSavedCommunities()
    end
    if addon.DiscoverCommunities then
        addon:DiscoverCommunities(true)
        addon:ScheduleCommunityDiscoveryRetry()
    end
    addon:StartAutoRefresh()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        InitializeSources()
        addon:ScheduleRefresh(event)
        return
    end

    if event == "PLAYER_LOGOUT" then
        if addon.SaveCommunityCache then
            addon:SaveCommunityCache()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        InitializeSources()
    end
    if event == "INITIAL_CLUBS_LOADED" then
        addon:OnInitialClubsLoaded()
        return
    end
    addon:ScheduleRefresh(event)
end)

SLASH_LAFEEELVUIGUILDHOVER1 = "/lafeeguildhover"
SLASH_LAFEEELVUIGUILDHOVER2 = "/lgh"
SlashCmdList.LAFEEELVUIGUILDHOVER = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "refresh" then
        if addon.DiscoverCommunities then addon:DiscoverCommunities(false) end
        addon:RefreshAll()
        addon:Print("Rafraîchissement demandé.")
    elseif command == "debug" then
        addon.debug = not addon.debug
        addon:Print("Mode debug " .. (addon.debug and "activé." or "désactivé."))
    else
        local count = 0
        for _, source in pairs(addon.communitySources) do
            if not source.removed then count = count + 1 end
        end
        addon:Print(format("version %s — %d datatext(s) communautaire(s) enregistré(s).", addon.version, count))
        addon:Print("Commandes : /lgh refresh, /lgh debug")
    end
end
