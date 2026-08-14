local addonName, addon = ...
local DT = addon.DT

local CLUB_TYPE_GUILD = Enum and Enum.ClubType and Enum.ClubType.Guild
local CLUB_TYPE_BNET = Enum and Enum.ClubType and Enum.ClubType.BattleNet
local PRESENCE = Enum and Enum.ClubMemberPresence or {}

local function IsSafeValue(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    if addon.E.NotSecretValue then
        return addon.E:NotSecretValue(value)
    end
    return value ~= nil
end

-- Club data arrives in stages during login.  With the 12.x secret-value API,
-- a member can be reported online before their identity fields are readable.
-- Never turn that transient record into a fake "Battle.net" member.
local function GetSafeMemberField(memberInfo, field)
    local ok, value = pcall(function()
        return memberInfo[field]
    end)
    if not ok then return nil end

    local safe, isSafe = pcall(IsSafeValue, value)
    if safe and isSafe then return value end
end

local function IsOnlinePresence(presence)
    -- Match Blizzard's online counter. OnlineMobile is Battle.net/mobile chat,
    -- not a character currently logged into World of Warcraft.
    return presence == PRESENCE.Online
        or presence == PRESENCE.Away
        or presence == PRESENCE.Busy
end

local function PresenceLabel(presence, isMobile)
    if presence == PRESENCE.Away then
        return isMobile and "Mobile — absent" or "Absent"
    elseif presence == PRESENCE.Busy then
        return isMobile and "Mobile — occupé" or "Occupé"
    elseif presence == PRESENCE.OnlineMobile or isMobile then
        return "Mobile"
    end
    return "En ligne"
end

local function GetCharacterName(guid, name, characterName, realmName)
    if guid and name then
        return name
    end
    if characterName then
        if realmName and realmName ~= "" then
            return characterName .. "-" .. realmName
        end
        return characterName
    end
end

local function GetBNetAccountName(bnetAccountName, battleTag, name, isBattleNetClub, characterName)
    if not isBattleNetClub then return nil end
    if bnetAccountName then return bnetAccountName end
    if battleTag then return battleTag end
    if not characterName and name then return name end
end

local function RequestCommunityMembers(source)
    if not (source and source.clubId and C_Club and C_Club.FocusMembers) then return end
    if source.membersFocusRequested then return end

    -- Blizzard calls FocusMembers whenever a club is selected. Without it the
    -- login cache can contain club metadata but no current member presence.
    local success
    if securecallfunction then
        success = pcall(securecallfunction, C_Club.FocusMembers, source.clubId)
    else
        success = pcall(C_Club.FocusMembers, source.clubId)
    end
    if success then
        source.membersFocusRequested = true
    end
end

local function BuildCommunityMembers(source)
    local members = {}
    if not (C_Club and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return members end

    RequestCommunityMembers(source)

    local memberIDs = C_Club.GetClubMembers(source.clubId)
    if not IsSafeValue(memberIDs) or not memberIDs then return members end

    local playerGUID = UnitGUID("player")
    for _, memberID in ipairs(memberIDs) do
        local success, memberInfo = pcall(C_Club.GetMemberInfo, source.clubId, memberID)
        if success and IsSafeValue(memberInfo) and memberInfo then
            local presence = GetSafeMemberField(memberInfo, "presence")
            local guid = GetSafeMemberField(memberInfo, "guid")
            local name = GetSafeMemberField(memberInfo, "name")
            local characterName = GetSafeMemberField(memberInfo, "characterName")
            local realmName = GetSafeMemberField(memberInfo, "realmName")
            local bnetName = GetSafeMemberField(memberInfo, "bnetAccountName")
            local battleTag = GetSafeMemberField(memberInfo, "battleTag")
            local fullName = GetCharacterName(guid, name, characterName, realmName)
            local bnetAccountName = GetBNetAccountName(bnetName, battleTag, name, source.isBattleNet, fullName)

            -- The roster is still hydrating.  Skip this record until Blizzard
            -- exposes an actual identity; a later roster event refreshes it.
            if IsOnlinePresence(presence) and (fullName or bnetAccountName or name) then
                local isMobile = presence == PRESENCE.OnlineMobile or GetSafeMemberField(memberInfo, "isMobile") == true
                local isSelf = guid and playerGUID and guid == playerGUID
                local inGroup = fullName and not isSelf and (UnitInParty(fullName) or UnitInRaid(fullName)) or false
                local classFile = addon:GetClassFile(GetSafeMemberField(memberInfo, "classID"))
                local displayName = fullName or name or bnetAccountName
                local member = {
                    id = GetSafeMemberField(memberInfo, "memberId") or memberID,
                    name = Ambiguate and fullName and Ambiguate(fullName, "none") or displayName,
                    fullName = fullName,
                    level = GetSafeMemberField(memberInfo, "level"),
                    classFile = classFile,
                    zone = GetSafeMemberField(memberInfo, "zone") or "",
                    status = PresenceLabel(presence, isMobile),
                    isMobile = isMobile,
                    isSelf = isSelf and true or false,
                    isInGroup = inGroup and true or false,
                    bnetAccountName = bnetAccountName,
                }

                member.canWhisper = not member.isSelf and (member.fullName ~= nil or member.bnetAccountName ~= nil)
                member.canInvite = member.fullName ~= nil and not member.isMobile and not member.isSelf and not member.isInGroup
                member.whisperCallback = function() addon:WhisperMember(member) end
                member.inviteCallback = function() addon:InviteMember(member) end
                members[#members + 1] = member
            end
        end
    end

    table.sort(members, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return members
end

local function CreateCommunitySource(clubInfo)
    local clubId = GetSafeMemberField(clubInfo, "clubId")
    if not clubId then return nil end

    local clubType = GetSafeMemberField(clubInfo, "clubType")
    local clubName = GetSafeMemberField(clubInfo, "name")
    local isBattleNet = GetSafeMemberField(clubInfo, "isBattleNet")
    local key = "lafee_Community_" .. tostring(clubId)
    local source = {
        key = key,
        clubId = clubId,
        displayName = clubName or ("Communauté " .. tostring(clubId)),
        isBattleNet = isBattleNet == true or clubType == CLUB_TYPE_BNET,
        members = {},
        RefreshMembers = function(self)
            self.members = BuildCommunityMembers(self)
        end,
    }
    return source
end

function addon:RestoreSavedCommunities()
    local cachedCommunities = self.db and self.db.communities
    if type(cachedCommunities) ~= "table" then return end

    for clubId, clubInfo in pairs(cachedCommunities) do
        if type(clubInfo) == "table" and clubInfo.clubId and not self.communitySources[tostring(clubId)] then
            local source = CreateCommunitySource(clubInfo)
            if source then
                self.communitySources[tostring(clubId)] = source
                self:RegisterDataText(source)
            end
        end
    end
end

function addon:SaveCommunityCache()
    if not self.db then return end

    local cachedCommunities = {}
    for clubId, source in pairs(self.communitySources) do
        if not source.removed and source.clubId then
            cachedCommunities[clubId] = {
                clubId = source.clubId,
                name = source.displayName,
                isBattleNet = source.isBattleNet and true or false,
            }
        end
    end
    self.db.communities = cachedCommunities
end

function addon:DiscoverCommunities(initial)
    if not (C_Club and C_Club.GetSubscribedClubs) then return end

    local clubs = C_Club.GetSubscribedClubs()
    if not IsSafeValue(clubs) or not clubs then return end

    local seen = {}
    local added = false
    for _, clubInfo in ipairs(clubs) do
        local rawClubId = IsSafeValue(clubInfo) and GetSafeMemberField(clubInfo, "clubId")
        local clubType = IsSafeValue(clubInfo) and GetSafeMemberField(clubInfo, "clubType")
        if rawClubId and clubType ~= CLUB_TYPE_GUILD then
            local clubId = tostring(rawClubId)
            seen[clubId] = true
            local source = self.communitySources[clubId]
            if not source then
                source = CreateCommunitySource(clubInfo)
                if source then
                    self.communitySources[clubId] = source
                    self:RegisterDataText(source)
                    added = true
                end
            else
                source.displayName = GetSafeMemberField(clubInfo, "name") or source.displayName
                source.isBattleNet = clubType == CLUB_TYPE_BNET
                source.removed = false
                if DT.DataTextList then
                    DT.DataTextList[source.key] = source.displayName
                end
            end
        end
    end

    local removed = false
    -- Before INITIAL_CLUBS_LOADED, an empty result simply means the login
    -- handshake is still in progress; it must not be interpreted as every
    -- community having been removed.
    if self.initialClubsLoaded then
        for clubId, source in pairs(self.communitySources) do
            if not seen[clubId] then
                source.removed = true
                source.members = {}
                removed = true
            end
        end
    end

    if not initial and removed then
        self:Print("les communautés ont changé, utilisez /reload.")
    elseif added and DT.Initialized and DT.UpdateQuickDT then
        DT:UpdateQuickDT()
    end

    self:SaveCommunityCache()
end
