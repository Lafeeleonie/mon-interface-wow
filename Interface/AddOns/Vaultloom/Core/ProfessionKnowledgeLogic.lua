local _, Addon = ...

local DATA = Addon.Data.PROFESSIONS
local Logic = {}
Addon.ProfessionKnowledgeLogic = Logic
local cachedState = nil

local function resolveTradeSkillLine(index)
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function"
        or not C_TradeSkillUI
        or type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) ~= "function"
        or type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) ~= "function"
    then
        return nil
    end
    local professionIndex = select(index, GetProfessions())
    if not professionIndex then
        return nil
    end
    local name, icon, _, _, _, spellOffset, baseSkillLineID, _, _, _, subcategoryName = GetProfessionInfo(professionIndex)
    local desiredName = type(subcategoryName) == "string" and subcategoryName ~= "" and subcategoryName or name
    local candidateID, candidateName
    local ok, skillLines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if ok and type(skillLines) == "table" then
        for _, rawID in ipairs(skillLines) do
            local infoOk, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, rawID)
            if infoOk and type(info) == "table" then
                local infoName = info.professionName
                if desiredName and infoName == desiredName then
                    return tonumber(rawID), infoName, icon, tonumber(baseSkillLineID), tonumber(spellOffset)
                end
                if not candidateID and (infoName == name
                    or tonumber(info.parentProfessionID) == tonumber(baseSkillLineID)
                    or tonumber(rawID) == tonumber(baseSkillLineID))
                then
                    candidateID, candidateName = tonumber(rawID), infoName
                end
            end
        end
    end
    return candidateID or tonumber(baseSkillLineID), candidateName or desiredName or name, icon,
        tonumber(baseSkillLineID), tonumber(spellOffset)
end

local function getUnspentKnowledge(skillLineID)
    if not skillLineID or not C_ProfSpecs or not C_Traits
        or type(C_ProfSpecs.GetConfigIDForSkillLine) ~= "function"
        or type(C_ProfSpecs.GetSpecTabIDsForSkillLine) ~= "function"
        or type(C_ProfSpecs.GetTabInfo) ~= "function"
        or type(C_ProfSpecs.GetSpendCurrencyForPath) ~= "function"
        or type(C_Traits.GetTreeCurrencyInfo) ~= "function"
        or type(C_Traits.GetTreeNodes) ~= "function"
        or type(C_Traits.GetNodeInfo) ~= "function"
        or type(C_Traits.CanPurchaseRank) ~= "function"
    then
        return 0, false
    end
    local configOk, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, skillLineID)
    configID = configOk and tonumber(configID) or nil
    local tabsOk, treeIDs = false, nil
    if configID then
        tabsOk, treeIDs = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, skillLineID)
    end
    if not configID or configID <= 0 or not tabsOk or type(treeIDs) ~= "table" then
        return 0, false
    end
    local total, canPurchase, seenCurrencies = 0, false, {}
    for _, rawTreeID in ipairs(treeIDs) do
        local treeID = tonumber(rawTreeID)
        local tabOk, tabInfo = pcall(C_ProfSpecs.GetTabInfo, treeID)
        local rootNodeID = tabOk and type(tabInfo) == "table" and tonumber(tabInfo.rootNodeID) or nil
        local currencyOk, currencyID = false, nil
        if rootNodeID then
            currencyOk, currencyID = pcall(C_ProfSpecs.GetSpendCurrencyForPath, rootNodeID)
        end
        currencyID = currencyOk and tonumber(currencyID) or nil
        if currencyID and not seenCurrencies[currencyID] then
            seenCurrencies[currencyID] = true
            local infoOk, currencies = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, true)
            if infoOk and type(currencies) == "table" then
                for _, currency in ipairs(currencies) do
                    if tonumber(currency.traitCurrencyID) == currencyID then
                        total = total + math.max(0, tonumber(currency.quantity) or 0)
                        break
                    end
                end
            end
        end
        local nodesOk, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        for _, rawNodeID in ipairs(nodesOk and type(nodeIDs) == "table" and nodeIDs or {}) do
            local nodeID = tonumber(rawNodeID)
            local nodeOk, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
            if nodeOk and type(nodeInfo) == "table" and nodeInfo.isVisible then
                local entryID = type(nodeInfo.activeEntry) == "table" and nodeInfo.activeEntry.entryID or nil
                local purchaseOk, purchasable = pcall(C_Traits.CanPurchaseRank, configID, nodeID, entryID)
                canPurchase = canPurchase or (purchaseOk and purchasable == true)
            end
        end
    end
    return total, canPurchase
end

function Logic:BuildState(forceRefresh)
    if forceRefresh ~= true and type(cachedState) == "table" then
        return cachedState
    end
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil
    end
    local state = {
        updatedAt = type(time) == "function" and time() or 0,
        totalPoints = 0,
        professionCount = 0,
        hasUnspent = false,
        professions = {},
    }
    for index = 1, 2 do
        local skillLineID, name, icon, baseSkillLineID, spellOffset = resolveTradeSkillLine(index)
        if skillLineID then
            local points, canPurchase = getUnspentKnowledge(skillLineID)
            points = math.max(0, tonumber(points) or 0)
            local hasUnspent = canPurchase and points > 0
            state.professions[#state.professions + 1] = {
                slotIndex = index,
                skillLineID = skillLineID,
                baseSkillLineID = baseSkillLineID,
                spellOffset = spellOffset,
                professionKey = DATA.skillLineToKey[baseSkillLineID] or DATA.skillLineToKey[skillLineID],
                name = name or Addon.L.UNKNOWN,
                icon = icon,
                points = points,
                hasUnspent = hasUnspent,
                canPurchase = canPurchase == true,
            }
            if hasUnspent then
                state.totalPoints = state.totalPoints + points
            end
        end
    end
    table.sort(state.professions, function(left, right)
        return tostring(left.name or "") < tostring(right.name or "")
    end)
    state.professionCount = #state.professions
    state.hasUnspent = state.totalPoints > 0
    cachedState = state
    return state
end
