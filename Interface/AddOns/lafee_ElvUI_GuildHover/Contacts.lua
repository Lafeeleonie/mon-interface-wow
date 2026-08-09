local addonName, addon = ...

local BNET_CLIENT_WOW = BNET_CLIENT_WOW or "WoW"
local CURRENT_WOW_PROJECT = WOW_PROJECT_ID
local contactsSource

local function IsSafeValue(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    if addon.E.NotSecretValue then
        return addon.E:NotSecretValue(value)
    end
    return value ~= nil
end

local function GetClassFile(className)
    if not className or not addon.E.UnlocalizedClassName then return nil end
    local ok, classFile = pcall(addon.E.UnlocalizedClassName, addon.E, className)
    return ok and classFile or nil
end

local function ContactStatus(isAFK, isDND, fallback)
    if isAFK then return "Absent" end
    if isDND then return "Occupé" end
    return fallback or "En ligne"
end

local function GetFullCharacterName(gameInfo, battleTag)
    if not gameInfo or gameInfo.clientProgram ~= BNET_CLIENT_WOW then return nil end
    if gameInfo.wowProjectID and CURRENT_WOW_PROJECT and gameInfo.wowProjectID ~= CURRENT_WOW_PROJECT then return nil end

    local characterName = gameInfo.characterName
    if BNet_GetValidatedCharacterName then
        local ok, validatedName = pcall(BNet_GetValidatedCharacterName, characterName, battleTag, gameInfo.clientProgram)
        if ok and validatedName and validatedName ~= "" then
            characterName = validatedName
        end
    end
    if not IsSafeValue(characterName) or not characterName or characterName == "" then return nil end

    local realmName = gameInfo.realmName
    if IsSafeValue(realmName) and realmName and realmName ~= "" and not characterName:find("-", 1, true) then
        return characterName .. "-" .. realmName
    end
    return characterName
end

local function FindActiveRetailCharacter(friendIndex, accountInfo)
    if not (C_BattleNet and C_BattleNet.GetFriendGameAccountInfo and C_BattleNet.GetFriendNumGameAccounts) then
        return accountInfo and accountInfo.gameAccountInfo or nil
    end

    local okCount, count = pcall(C_BattleNet.GetFriendNumGameAccounts, friendIndex)
    if okCount and count then
        for gameIndex = 1, count do
            local okInfo, gameInfo = pcall(C_BattleNet.GetFriendGameAccountInfo, friendIndex, gameIndex)
            if okInfo and IsSafeValue(gameInfo) and gameInfo and gameInfo.isOnline == true
                and gameInfo.clientProgram == BNET_CLIENT_WOW
                and (not gameInfo.wowProjectID or not CURRENT_WOW_PROJECT or gameInfo.wowProjectID == CURRENT_WOW_PROJECT) then
                return gameInfo
            end
        end
    end

    return accountInfo and accountInfo.gameAccountInfo or nil
end

local function AddWoWContacts(members)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end

    local playerGUID = UnitGUID("player")
    local count = C_FriendList.GetNumFriends() or 0
    for index = 1, count do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, index)
        if ok and IsSafeValue(info) and info and info.connected == true and IsSafeValue(info.name) and info.name then
            local fullName = info.name
            local isSelf = info.guid and playerGUID and info.guid == playerGUID
            local inGroup = not isSelf and (UnitInParty(fullName) or UnitInRaid(fullName)) or false
            members[#members + 1] = {
                id = info.guid or fullName,
                name = Ambiguate and Ambiguate(fullName, "none") or fullName,
                fullName = fullName,
                level = info.level,
                classFile = GetClassFile(info.className),
                zone = info.area or "",
                status = ContactStatus(info.afk, info.dnd),
                isMobile = false,
                isFavorite = info.isFavorite == true,
                isSelf = isSelf and true or false,
                isInGroup = inGroup and true or false,
                canWhisper = not isSelf,
                canInvite = not isSelf and not inGroup,
            }
        end
    end
end

local function AddBattleNetContacts(members)
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end

    local total = BNGetNumFriends() or 0
    for friendIndex = 1, total do
        local ok, accountInfo = pcall(C_BattleNet.GetFriendAccountInfo, friendIndex)
        local defaultGame = ok and IsSafeValue(accountInfo) and accountInfo and accountInfo.gameAccountInfo or nil
        if defaultGame and defaultGame.isOnline == true then
            local gameInfo = FindActiveRetailCharacter(friendIndex, accountInfo)
            local fullName = GetFullCharacterName(gameInfo, accountInfo.battleTag)
            local inGroup = fullName and (UnitInParty(fullName) or UnitInRaid(fullName)) or false
            local accountName = IsSafeValue(accountInfo.accountName) and accountInfo.accountName or nil
            local displayName = fullName or accountName or (IsSafeValue(accountInfo.battleTag) and accountInfo.battleTag) or "Battle.net"
            local isMobile = not fullName and gameInfo and (gameInfo.clientProgram == "App" or gameInfo.clientProgram == "BSAp")
            local statusFallback = fullName and "En ligne" or (isMobile and "Mobile" or "Battle.net")

            members[#members + 1] = {
                id = accountInfo.bnetAccountID or friendIndex,
                name = fullName and (Ambiguate and Ambiguate(fullName, "none") or fullName) or displayName,
                fullName = fullName,
                level = fullName and gameInfo.characterLevel or nil,
                classFile = fullName and GetClassFile(gameInfo.className) or nil,
                zone = fullName and (gameInfo.areaName or "") or (gameInfo.richPresence or ""),
                status = ContactStatus(accountInfo.isAFK or gameInfo.isGameAFK, accountInfo.isDND or gameInfo.isGameBusy, statusFallback),
                isMobile = isMobile and true or false,
                isFavorite = accountInfo.isFavorite == true,
                isSelf = false,
                isInGroup = inGroup and true or false,
                bnetAccountName = accountName,
                secondaryText = IsSafeValue(accountInfo.battleTag) and accountInfo.battleTag or nil,
                nameColor = not fullName and { r = 0.35, g = 0.65, b = 1 } or nil,
                canWhisper = accountName ~= nil,
                canInvite = fullName ~= nil and not inGroup,
            }
        end
    end
end

local function BuildContacts()
    local members = {}
    AddWoWContacts(members)
    AddBattleNetContacts(members)
    table.sort(members, function(left, right)
        if left.isFavorite ~= right.isFavorite then
            return left.isFavorite == true
        end
        return (left.name or ""):lower() < (right.name or ""):lower()
    end)
    return members
end

function addon:RegisterContactsDataText()
    if contactsSource then return end

    contactsSource = {
        key = "Contacts interactifs",
        listName = "Contacts interactifs",
        displayName = "Contacts",
        members = {},
        RefreshMembers = function(source)
            source.members = BuildContacts()
        end,
    }

    addon:RegisterDataText(contactsSource)
    contactsSource:RefreshMembers()
end
