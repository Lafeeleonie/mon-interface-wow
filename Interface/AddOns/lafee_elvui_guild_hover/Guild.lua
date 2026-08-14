local addonName, addon = ...

local GUILD_REQUEST_INTERVAL = 15
local guildSource
local lastGuildRosterRequest

local function GuildStatus(status, isMobile)
    if isMobile then
        if status == 1 then return "Mobile — absent" end
        if status == 2 then return "Mobile — occupé" end
        return "Mobile"
    end
    if status == 1 then return "Absent" end
    if status == 2 then return "Occupé" end
    return "En ligne"
end

local function RequestGuildRoster()
    if not IsInGuild or not IsInGuild() then return end
    if not C_GuildInfo or not C_GuildInfo.GuildRoster then return end
    if lastGuildRosterRequest and (GetTime() - lastGuildRosterRequest) < GUILD_REQUEST_INTERVAL then return end

    lastGuildRosterRequest = GetTime()
    C_GuildInfo.GuildRoster()
end

local function BuildGuildMembers()
    local members = {}
    if not IsInGuild or not IsInGuild() then return members end

    local playerGUID = UnitGUID("player")
    local totalMembers = GetNumGuildMembers and GetNumGuildMembers() or 0
    for index = 1, totalMembers do
        local fullName, _, _, level, _, zone, _, _, online, status, classFile, _, _, isMobile, _, _, guid = GetGuildRosterInfo(index)
        -- Mobile guild chat does not mean that the character is logged into WoW.
        if fullName and online then
            local isSelf = guid and playerGUID and guid == playerGUID
            local inGroup = not isSelf and (UnitInParty(fullName) or UnitInRaid(fullName)) or false
            local member = {
                id = guid or fullName,
                name = Ambiguate and Ambiguate(fullName, "none") or fullName,
                fullName = fullName,
                level = level,
                classFile = classFile,
                zone = zone or (isMobile and "Mobile" or ""),
                status = GuildStatus(status, isMobile),
                isMobile = isMobile and true or false,
                isSelf = isSelf and true or false,
                isInGroup = inGroup and true or false,
            }

            member.canWhisper = not member.isSelf and member.fullName ~= nil
            member.canInvite = online and not member.isMobile and not member.isSelf and not member.isInGroup and member.fullName ~= nil
            member.whisperCallback = function() addon:WhisperMember(member) end
            member.inviteCallback = function() addon:InviteMember(member) end
            members[#members + 1] = member
        end
    end

    table.sort(members, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return members
end

function addon:RegisterGuildDataText()
    if guildSource then return end

    guildSource = {
        key = "Guilde interactive",
        listName = "Guilde interactive",
        displayName = "Guilde",
        isGuild = true,
        members = {},
        RefreshMembers = function(source)
            RequestGuildRoster()
            source.members = BuildGuildMembers()
        end,
    }

    addon:RegisterDataText(guildSource)
    guildSource:RefreshMembers()
end
