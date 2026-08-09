local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Assets = Addon.Assets
local VaultRewardBadge = Addon.VaultRewardBadge
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local Overview = {}
Addon.WarbandOverview = Overview

local CARD_COLUMNS = 3
local CARD_WIDTH = 336
local CARD_PROFESSION_HEIGHT = 178
local CARD_GAP = 10
local COMPACT_WIDTH = 1028
local COMPACT_HEIGHT = 58
local COMPACT_GAP = 6

local STATUS_FILTERS = { "all", "reward", "current", "main", "max_level" }
local SORT_MODES = { "name", "level", "itemLevel", "activityScore", "vault", "lastSeen" }
local LAYOUT_MODES = { "compact", "cards" }

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function addCircularMask(owner, texture)
    if not owner or not texture
        or type(owner.CreateMaskTexture) ~= "function"
        or type(texture.AddMaskTexture) ~= "function"
    then
        return nil
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function setClassIcon(texture, classFile)
    if not texture then return end
    local customIcon = Assets.classIcons and Assets.classIcons[classFile]
    if customIcon then
        texture:SetTexture(customIcon)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile]
    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function applyPortrait(texture, character, current)
    if current and type(SetPortraitTexture) == "function" then
        texture:SetTexCoord(0, 1, 0, 1)
        local ok = pcall(SetPortraitTexture, texture, "player")
        if ok then return end
    end
    setClassIcon(texture, character and character.classFile)
end

local function formatMoney(money)
    money = math.max(0, math.floor(tonumber(money) or 0))
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(money, 12)
    end
    return tostring(math.floor(money / 10000)) .. "g"
end

local function formatLastSeen(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 or type(time) ~= "function" then return L.UNKNOWN end
    local elapsed = math.max(0, time() - timestamp)
    if elapsed < 60 then return "0m" end
    if elapsed < 3600 then return tostring(math.floor(elapsed / 60)) .. "m" end
    if elapsed < 86400 then return tostring(math.floor(elapsed / 3600)) .. "h" end
    return tostring(math.floor(elapsed / 86400)) .. "d"
end

local function getActivityScore(characterKey)
    local score = Addon.ActivityScore and Addon.ActivityScore:Get(characterKey)
    return tonumber(score and score.score) or 0, score
end

local function getVaultSummary(characterKey)
    return Addon.ActivityScore and Addon.ActivityScore:GetVaultSummary(characterKey) or nil
end

local function getVaultRatio(characterKey)
    local summary = getVaultSummary(characterKey)
    return tonumber(summary and summary.ratio) or 0
end

local function buildVaultText(characterKey)
    local summary = getVaultSummary(characterKey)
    local parts = {}
    local labels = {
        raid = L.SIDEBAR_VAULT_RAID_SHORT,
        dungeon = L.SIDEBAR_VAULT_DUNGEON_SHORT,
        world = L.SIDEBAR_VAULT_WORLD_SHORT,
    }
    for _, key in ipairs({ "raid", "dungeon", "world" }) do
        local entry = summary and summary[key]
        if entry and (tonumber(entry.maximum) or 0) > 0 then
            parts[#parts + 1] = string.format(
                "%s %d/%d",
                labels[key],
                tonumber(entry.current) or 0,
                tonumber(entry.maximum) or 0
            )
        else
            parts[#parts + 1] = labels[key] .. " " .. L.SIDEBAR_VAULT_UNKNOWN
        end
    end
    return table.concat(parts, "    ")
end

local function cycleValue(values, current)
    local currentIndex = 1
    for index, value in ipairs(values) do
        if value == current then
            currentIndex = index
            break
        end
    end
    return values[(currentIndex % #values) + 1]
end

local function createCard(parent, owner)
    local card = Widgets:CreateButton(parent, "", CARD_WIDTH, CARD_PROFESSION_HEIGHT, "row")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.label:Hide()

    card.portraitBackplate = card:CreateTexture(nil, "ARTWORK")
    card.portraitBackplate:SetSize(52, 52)
    card.portraitBackplate:SetPoint("TOPLEFT", 14, -16)
    card.portraitBackplate:SetColorTexture(1, 1, 1, 1)
    card.portraitBackplateMask = addCircularMask(card, card.portraitBackplate)

    card.portrait = card:CreateTexture(nil, "OVERLAY", nil, 1)
    card.portrait:SetSize(48, 48)
    card.portrait:SetPoint("CENTER", card.portraitBackplate, "CENTER", 0, 0)
    card.portraitMask = addCircularMask(card, card.portrait)
    card.rewardBadge = VaultRewardBadge:Create(card, 20)
    card.rewardBadge:SetPoint(
        "BOTTOMRIGHT",
        card.portraitBackplate,
        "BOTTOMRIGHT",
        3,
        -3
    )

    card.name = Widgets:CreateLabel(card, "GameFontNormalLarge", "LEFT")
    card.name:SetPoint("TOPLEFT", 76, -13)
    card.name:SetPoint("TOPRIGHT", -106, -13)
    card.name:SetHeight(18)
    card.name:SetWordWrap(false)
    card.name:SetMaxLines(1)

    card.tags = Widgets:CreateLabel(card, "GameFontNormalSmall", "RIGHT")
    card.tags:SetPoint("TOPRIGHT", -12, -14)
    card.tags:SetWidth(90)
    card.tags:SetTextColor(unpackColor(Theme.colors.gold))

    card.identity = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.identity:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
    card.identity:SetPoint("TOPRIGHT", -12, 0)
    card.identity:SetHeight(14)

    card.stats = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.stats:SetPoint("TOPLEFT", card.identity, "BOTTOMLEFT", 0, -7)
    card.stats:SetPoint("TOPRIGHT", -12, 0)
    card.stats:SetHeight(14)

    card.money = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.money:SetPoint("TOPLEFT", card.stats, "BOTTOMLEFT", 0, -6)
    card.money:SetPoint("TOPRIGHT", -12, 0)
    card.money:SetHeight(14)

    card.lastSeen = Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.lastSeen:SetPoint("TOPLEFT", card.money, "BOTTOMLEFT", 0, -6)
    card.lastSeen:SetPoint("TOPRIGHT", -12, 0)
    card.lastSeen:SetHeight(14)

    card.professionFrame = CreateFrame("Frame", nil, card)
    card.professionFrame:SetPoint("BOTTOMLEFT", 76, 42)
    card.professionFrame:SetSize(24, 24)
    card.professionFrame:Hide()
    card.professionButtons = {}

    card.divider = card:CreateTexture(nil, "ARTWORK")
    card.divider:SetPoint("BOTTOMLEFT", 14, 35)
    card.divider:SetPoint("BOTTOMRIGHT", -14, 35)
    card.divider:SetHeight(1)
    card.divider:SetColorTexture(unpackColor(Theme.colors.goldDim))

    card.vault = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
    card.vault:SetPoint("BOTTOMLEFT", 14, 13)
    card.vault:SetPoint("BOTTOMRIGHT", -75, 13)
    card.vault:SetHeight(14)

    card.visibility = Widgets:CreateButton(card, "", 58, 22)
    card.visibility:SetPoint("BOTTOMRIGHT", -12, 9)
    card.visibility:SetScript("OnClick", function(selfButton)
        if selfButton.characterKey and type(owner.callbacks.setHidden) == "function" then
            owner.callbacks.setHidden(selfButton.characterKey, not selfButton.hidden)
            owner:Refresh()
        end
    end)

    card:SetScript("OnClick", function(selfButton, mouseButton)
        if not selfButton.characterKey then return end
        if mouseButton == "RightButton" then
            if type(owner.callbacks.setMain) == "function" then
                owner.callbacks.setMain(selfButton.characterKey)
            end
        elseif not selfButton.hidden and type(owner.callbacks.select) == "function" then
            owner.callbacks.select(selfButton.characterKey)
        end
        owner:Refresh()
    end)

    local defaultEnter = card:GetScript("OnEnter")
    local defaultLeave = card:GetScript("OnLeave")
    card:SetScript("OnEnter", function(selfButton)
        if defaultEnter then defaultEnter(selfButton) end
        if GameTooltip then
            GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(selfButton.displayName or L.UNKNOWN, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(L.WARBAND_OVERVIEW_CARD_HINT, 0.78, 0.76, 0.70, true)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(selfButton)
        if defaultLeave then defaultLeave(selfButton) end
        if GameTooltip then GameTooltip:Hide() end
    end)

    return card
end

local function matchesSearch(character, query)
    if query == "" then return true end
    if lower(character.name):find(query, 1, true)
        or lower(character.realm):find(query, 1, true)
        or lower(character.className):find(query, 1, true)
        or lower(character.classFile):find(query, 1, true)
    then
        return true
    end

    for _, profession in ipairs(Addon.ProfessionBadges:GetProfessions(character, true)) do
        local skillLineID = tonumber(profession.baseSkillLineID or profession.skillLineID)
        local professionKey = profession.professionKey
            or (skillLineID and Addon.Data.PROFESSIONS.skillLineToKey[skillLineID])
        if lower(profession.name):find(query, 1, true)
            or lower(profession.professionName):find(query, 1, true)
            or lower(professionKey):find(query, 1, true)
        then
            return true
        end
    end
    return false
end

function Overview:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    frame.callbacks = callbacks
    frame.cards = {}
    frame.searchQuery = ""
    frame.realmFilter = "all"
    frame.statusFilter = "all"
    frame.sortMode = "name"
    local savedLayoutMode = type(callbacks.getLayoutMode) == "function"
        and callbacks.getLayoutMode() or nil
    frame.layoutMode = savedLayoutMode == "cards" and "cards" or "compact"
    frame:SetSize(1120, 650)
    local savedPosition = type(callbacks.getPosition) == "function"
        and callbacks.getPosition() or nil
    if type(savedPosition) == "table" then
        frame:SetPoint(
            savedPosition.point or "CENTER",
            UIParent,
            savedPosition.relativePoint or savedPosition.point or "CENTER",
            tonumber(savedPosition.x) or 0,
            tonumber(savedPosition.y) or 0
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + 80)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Widgets:ApplyStandardGoldFrame(frame, Assets.windowBackground)

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", 14, -10)
    frame.dragBar:SetPoint("TOPRIGHT", -58, -10)
    frame.dragBar:SetHeight(54)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if type(callbacks.storePosition) == "function" then
            callbacks.storePosition(frame)
        end
    end)

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalHuge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -18)
    frame.title:SetPoint("TOPRIGHT", -64, -18)
    frame.title:SetText(L.WARBAND_OVERVIEW_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.subtitle:SetPoint("TOPRIGHT", -330, 0)
    frame.subtitle:SetText(L.WARBAND_OVERVIEW_SUBTITLE)

    frame.summary = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "RIGHT")
    frame.summary:SetPoint("TOPRIGHT", -66, -50)
    frame.summary:SetWidth(180)
    frame.summary:SetTextColor(unpackColor(Theme.colors.gold))

    frame.rewardSummary = VaultRewardBadge:CreateSummary(frame, function()
        frame.statusFilter = "reward"
        frame:Refresh()
    end)
    frame.rewardSummary:SetPoint("RIGHT", frame.summary, "LEFT", -8, 0)

    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -18, -16)
    frame.closeButton:SetScript("OnClick", function()
        if type(callbacks.close) == "function" then
            callbacks.close()
        else
            frame:Hide()
        end
    end)

    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetSize(244, 28)
    frame.search:SetPoint("TOPLEFT", 22, -78)
    frame.search:SetAutoFocus(false)
    if _G.GameFontHighlightSmall and type(frame.search.SetFontObject) == "function" then
        frame.search:SetFontObject(_G.GameFontHighlightSmall)
    end
    frame.searchHint = Widgets:CreateLabel(frame.search, "GameFontDisableSmall", "LEFT")
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.searchHint:SetPoint("RIGHT", -8, 0)
    frame.searchHint:SetText(L.WARBAND_OVERVIEW_SEARCH)
    frame.search:SetScript("OnTextChanged", function(self)
        frame.searchQuery = lower(self:GetText())
        frame.searchHint:SetShown(frame.searchQuery == "")
        frame:Refresh()
    end)
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.realm = Widgets:CreateButton(frame, "", 190, 28)
    frame.realm:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
    frame.realm:SetScript("OnClick", function()
        local values = {}
        for _, option in ipairs(frame:GetRealmOptions()) do
            values[#values + 1] = option.key
        end
        frame.realmFilter = cycleValue(values, frame.realmFilter)
        frame:Refresh()
    end)

    frame.status = Widgets:CreateButton(frame, "", 175, 28)
    frame.status:SetPoint("LEFT", frame.realm, "RIGHT", 8, 0)
    frame.status:SetScript("OnClick", function()
        frame.statusFilter = cycleValue(STATUS_FILTERS, frame.statusFilter)
        frame:Refresh()
    end)

    frame.sort = Widgets:CreateButton(frame, "", 250, 28)
    frame.sort:SetPoint("LEFT", frame.status, "RIGHT", 8, 0)
    frame.sort:SetScript("OnClick", function()
        frame.sortMode = cycleValue(SORT_MODES, frame.sortMode)
        frame:Refresh()
    end)

    frame.layout = Widgets:CreateButton(frame, "", 165, 28)
    frame.layout:SetPoint("LEFT", frame.sort, "RIGHT", 8, 0)
    frame.layout:SetScript("OnClick", function()
        frame.layoutMode = cycleValue(LAYOUT_MODES, frame.layoutMode)
        if type(frame.callbacks.setLayoutMode) == "function" then
            frame.callbacks.setLayoutMode(frame.layoutMode)
        end
        frame.scroll:SetVerticalScroll(0)
        frame:Refresh()
    end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -122)
    frame.scroll:SetPoint("BOTTOMRIGHT", -42, 22)
    frame.scroll:EnableMouseWheel(true)
    frame.child = CreateFrame("Frame", nil, frame.scroll)
    frame.child:SetSize(1028, 10)
    frame.scroll:SetScrollChild(frame.child)
    frame.scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll()
            - (delta * (frame:GetCardHeight() + frame:GetCardGap()))
        selfScroll:SetVerticalScroll(math.max(
            0,
            math.min(selfScroll:GetVerticalScrollRange(), nextValue)
        ))
    end)
    ScrollFrames:Style(frame.scroll, { autoHide = true })

    frame.empty = Widgets:CreateLabel(frame.child, "GameFontDisableLarge", "CENTER")
    frame.empty:SetPoint("TOPLEFT", 20, -50)
    frame.empty:SetPoint("TOPRIGHT", -20, -50)
    frame.empty:SetText(L.WARBAND_OVERVIEW_EMPTY)
    frame.empty:Hide()

    function frame:GetCharacters()
        local characters = type(self.callbacks.getCharacters) == "function"
            and self.callbacks.getCharacters() or {}
        return type(characters) == "table" and characters or {}
    end

    function frame:GetCardHeight()
        return self.layoutMode == "compact" and COMPACT_HEIGHT or CARD_PROFESSION_HEIGHT
    end

    function frame:GetCardWidth()
        return self.layoutMode == "compact" and COMPACT_WIDTH or CARD_WIDTH
    end

    function frame:GetCardGap()
        return self.layoutMode == "compact" and COMPACT_GAP or CARD_GAP
    end

    function frame:GetCardColumns()
        return self.layoutMode == "compact" and 1 or CARD_COLUMNS
    end

    function frame:GetRealmOptions()
        local realms = {}
        for _, character in ipairs(self:GetCharacters()) do
            local realm = tostring(character.realm or "")
            if realm ~= "" then realms[realm] = true end
        end
        local names = {}
        for realm in pairs(realms) do names[#names + 1] = realm end
        table.sort(names, function(a, b) return lower(a) < lower(b) end)
        local options = {
            { key = "all", label = L.SIDEBAR_REALM_ALL },
            { key = "current", label = L.SIDEBAR_REALM_CURRENT },
        }
        for _, realm in ipairs(names) do
            options[#options + 1] = { key = "realm:" .. realm, label = realm }
        end
        return options
    end

    function frame:GetCurrentRealm(characters)
        local currentKey = type(self.callbacks.getCurrentKey) == "function"
            and self.callbacks.getCurrentKey() or nil
        for _, character in ipairs(characters) do
            if character.key == currentKey then return character.realm end
        end
        return nil
    end

    function frame:GetFilteredCharacters()
        local allCharacters = self:GetCharacters()
        local filtered = {}
        local currentKey = type(self.callbacks.getCurrentKey) == "function"
            and self.callbacks.getCurrentKey() or nil
        local currentRealm = self:GetCurrentRealm(allCharacters)
        local maximumLevel = 0
        for _, character in ipairs(allCharacters) do
            maximumLevel = math.max(maximumLevel, tonumber(character.level) or 0)
        end

        for _, character in ipairs(allCharacters) do
            local realmMatches = self.realmFilter == "all"
                or (self.realmFilter == "current" and character.realm == currentRealm)
                or character.realm == tostring(self.realmFilter):match("^realm:(.+)")
            local statusMatches = self.statusFilter == "all"
                or (self.statusFilter == "reward"
                    and Addon.VaultProgress:GetRewardReminder(character.key) ~= nil)
                or (self.statusFilter == "current" and character.key == currentKey)
                or (self.statusFilter == "main" and character.isMain == true)
                or (self.statusFilter == "max_level"
                    and (tonumber(character.level) or 0) == maximumLevel)
            if realmMatches
                and statusMatches
                and matchesSearch(character, self.searchQuery)
            then
                filtered[#filtered + 1] = character
            end
        end

        local sortMode = self.sortMode
        table.sort(filtered, function(a, b)
            local leftName, rightName = lower(a.name), lower(b.name)
            if sortMode == "level" and (a.level or 0) ~= (b.level or 0) then
                return (a.level or 0) > (b.level or 0)
            elseif sortMode == "itemLevel" then
                local left = tonumber(a.itemLevel) or 0
                local right = tonumber(b.itemLevel) or 0
                if left ~= right then return left > right end
            elseif sortMode == "activityScore" then
                local left = getActivityScore(a.key)
                local right = getActivityScore(b.key)
                if left ~= right then return left > right end
            elseif sortMode == "vault" then
                local left, right = getVaultRatio(a.key), getVaultRatio(b.key)
                if left ~= right then return left > right end
            elseif sortMode == "lastSeen" and (a.lastSeen or 0) ~= (b.lastSeen or 0) then
                return (a.lastSeen or 0) > (b.lastSeen or 0)
            end
            if leftName ~= rightName then return leftName < rightName end
            return lower(a.realm) < lower(b.realm)
        end)
        return filtered, #allCharacters
    end

    function frame:RefreshFilterLabels()
        local realmLabel = L.SIDEBAR_REALM_ALL
        for _, option in ipairs(self:GetRealmOptions()) do
            if option.key == self.realmFilter then
                realmLabel = option.label
                break
            end
        end
        local statusLabels = {
            all = L.WARBAND_OVERVIEW_ALL,
            reward = L.WARBAND_OVERVIEW_REWARD,
            current = L.WARBAND_OVERVIEW_CURRENT,
            main = L.WARBAND_OVERVIEW_MAIN,
            max_level = L.WARBAND_OVERVIEW_MAX_LEVEL,
        }
        local sortLabels = {
            name = L.SIDEBAR_SORT_NAME,
            level = L.SIDEBAR_SORT_LEVEL,
            itemLevel = L.SIDEBAR_SORT_ITEM_LEVEL,
            activityScore = L.SIDEBAR_SORT_ACTIVITY_SCORE,
            vault = L.SIDEBAR_SORT_VAULT,
            lastSeen = L.WARBAND_OVERVIEW_LAST_SEEN_SORT,
        }
        self.realm.label:SetText(string.format(L.WARBAND_OVERVIEW_REALM, realmLabel))
        self.status.label:SetText(string.format(
            L.WARBAND_OVERVIEW_STATUS,
            statusLabels[self.statusFilter] or L.WARBAND_OVERVIEW_ALL
        ))
        self.sort.label:SetText(string.format(
            L.WARBAND_OVERVIEW_SORT,
            sortLabels[self.sortMode] or L.SIDEBAR_SORT_NAME
        ))
        self.layout.label:SetText(self.layoutMode == "compact"
            and L.WARBAND_OVERVIEW_LAYOUT_COMPACT
            or L.WARBAND_OVERVIEW_LAYOUT_CARDS)
    end

    function frame:ApplyCardLayout(card)
        card.portraitBackplate:ClearAllPoints()
        card.portrait:ClearAllPoints()
        card.rewardBadge:ClearAllPoints()
        card.name:ClearAllPoints()
        card.tags:ClearAllPoints()
        card.identity:ClearAllPoints()
        card.stats:ClearAllPoints()
        card.money:ClearAllPoints()
        card.lastSeen:ClearAllPoints()
        card.professionFrame:ClearAllPoints()
        card.divider:ClearAllPoints()
        card.vault:ClearAllPoints()
        card.visibility:ClearAllPoints()

        if self.layoutMode == "compact" then
            card:SetSize(COMPACT_WIDTH, COMPACT_HEIGHT)
            card.portraitBackplate:SetSize(42, 42)
            card.portraitBackplate:SetPoint("LEFT", 10, 0)
            card.portrait:SetSize(38, 38)
            card.portrait:SetPoint("CENTER", card.portraitBackplate, "CENTER", 0, 0)
            card.rewardBadge:SetSize(16, 16)
            card.rewardBadge:SetPoint(
                "BOTTOMRIGHT",
                card.portraitBackplate,
                "BOTTOMRIGHT",
                2,
                -2
            )

            card.name:SetPoint("TOPLEFT", 62, -7)
            card.name:SetSize(150, 18)
            card.tags:SetPoint("BOTTOMLEFT", 62, 8)
            card.tags:SetSize(150, 14)
            card.tags:SetJustifyH("LEFT")

            card.identity:SetPoint("TOPLEFT", 220, -9)
            card.identity:SetSize(238, 14)
            card.stats:SetPoint("TOPLEFT", 220, -32)
            card.stats:SetSize(238, 14)

            card.money:SetPoint("TOPLEFT", 468, -9)
            card.money:SetSize(112, 14)
            card.lastSeen:SetPoint("TOPLEFT", 468, -32)
            card.lastSeen:SetSize(112, 14)

            card.professionFrame:SetPoint("LEFT", 590, 0)
            card.professionFrame:SetSize(24, 24)
            card.divider:Hide()

            card.visibility:SetSize(58, 22)
            card.visibility:SetPoint("RIGHT", -10, 0)
            card.vault:SetPoint("LEFT", 660, 0)
            card.vault:SetPoint("RIGHT", card.visibility, "LEFT", -10, 0)
            card.vault:SetHeight(14)
        else
            card:SetSize(CARD_WIDTH, CARD_PROFESSION_HEIGHT)
            card.portraitBackplate:SetSize(52, 52)
            card.portraitBackplate:SetPoint("TOPLEFT", 14, -16)
            card.portrait:SetSize(48, 48)
            card.portrait:SetPoint("CENTER", card.portraitBackplate, "CENTER", 0, 0)
            card.rewardBadge:SetSize(20, 20)
            card.rewardBadge:SetPoint(
                "BOTTOMRIGHT",
                card.portraitBackplate,
                "BOTTOMRIGHT",
                3,
                -3
            )

            card.name:SetPoint("TOPLEFT", 76, -13)
            card.name:SetPoint("TOPRIGHT", -106, -13)
            card.name:SetHeight(18)
            card.tags:SetPoint("TOPRIGHT", -12, -14)
            card.tags:SetSize(90, 14)
            card.tags:SetJustifyH("RIGHT")

            card.identity:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
            card.identity:SetPoint("TOPRIGHT", -12, 0)
            card.identity:SetHeight(14)
            card.stats:SetPoint("TOPLEFT", card.identity, "BOTTOMLEFT", 0, -7)
            card.stats:SetPoint("TOPRIGHT", -12, 0)
            card.stats:SetHeight(14)
            card.money:SetPoint("TOPLEFT", card.stats, "BOTTOMLEFT", 0, -6)
            card.money:SetPoint("TOPRIGHT", -12, 0)
            card.money:SetHeight(14)
            card.lastSeen:SetPoint("TOPLEFT", card.money, "BOTTOMLEFT", 0, -6)
            card.lastSeen:SetPoint("TOPRIGHT", -12, 0)
            card.lastSeen:SetHeight(14)

            card.professionFrame:SetPoint("BOTTOMLEFT", 76, 42)
            card.professionFrame:SetSize(24, 24)
            card.divider:SetPoint("BOTTOMLEFT", 14, 35)
            card.divider:SetPoint("BOTTOMRIGHT", -14, 35)
            card.divider:SetHeight(1)
            card.divider:Show()
            card.vault:SetPoint("BOTTOMLEFT", 14, 13)
            card.vault:SetPoint("BOTTOMRIGHT", -75, 13)
            card.vault:SetHeight(14)
            card.visibility:SetSize(58, 22)
            card.visibility:SetPoint("BOTTOMRIGHT", -12, 9)
        end
    end

    function frame:ApplyCard(card, character, selectedKey, currentKey)
        local hidden = type(self.callbacks.isHidden) == "function"
            and self.callbacks.isHidden(character.key) == true
        local current = character.key == currentKey
        local scoreValue = getActivityScore(character.key)
        local itemLevel = tonumber(character.itemLevel)
        local classR, classG, classB = Addon.WoWApi:GetClassColor(character.classFile)
        local tags = {}
        if current then tags[#tags + 1] = L.WARBAND_OVERVIEW_CURRENT_TAG end
        if character.isMain then tags[#tags + 1] = L.WARBAND_OVERVIEW_MAIN_TAG end
        if hidden then tags[#tags + 1] = L.WARBAND_OVERVIEW_HIDDEN_TAG end

        self:ApplyCardLayout(card)
        card.characterKey = character.key
        card.hidden = hidden
        card.displayName = string.format(
            "%s-%s",
            character.name or L.UNKNOWN,
            character.realm or L.UNKNOWN
        )
        card.name:SetText(character.name or L.UNKNOWN)
        card.name:SetTextColor(classR, classG, classB, 1)
        card.tags:SetText(table.concat(tags, " · "))
        card.identity:SetText(string.format(
            "%s  ·  %s",
            character.className or L.UNKNOWN,
            character.realm or L.UNKNOWN
        ))
        card.stats:SetText(string.format(
            "%s    %s    %s",
            string.format(L.SIDEBAR_LEVEL_SHORT, tonumber(character.level) or 0),
            string.format(
                L.SIDEBAR_ITEM_LEVEL_SHORT,
                itemLevel and string.format("%.1f", itemLevel) or "-"
            ),
            string.format(L.WARBAND_OVERVIEW_ACTIVITY, scoreValue)
        ))
        card.money:SetText(formatMoney(character.money))
        card.lastSeen:SetText(string.format(
            L.WARBAND_OVERVIEW_LAST_SEEN,
            formatLastSeen(character.lastSeen)
        ))
        local professions = Addon.ProfessionBadges:GetProfessions(character.key, true)
        Addon.ProfessionBadges:Populate(
            card.professionFrame,
            card.professionButtons,
            professions,
            character.key,
            current,
            24,
            6
        )
        card.vault:SetText(buildVaultText(character.key))
        card.portraitBackplate:SetColorTexture(classR, classG, classB, 1)
        applyPortrait(card.portrait, character, current)
        VaultRewardBadge:SetCharacter(card.rewardBadge, character.key)
        card.visibility.characterKey = character.key
        card.visibility.hidden = hidden
        card.visibility.label:SetText(
            hidden and L.WARBAND_OVERVIEW_SHOW or L.WARBAND_OVERVIEW_HIDE
        )
        local canHide = not current
        card.visibility:SetAlpha(canHide and 1 or 0.42)
        card.visibility:EnableMouse(canHide)
        card:SetAlpha(hidden and 0.58 or 1)
        Widgets:SetButtonActive(card, character.key == selectedKey)
        card:Show()
    end

    function frame:Refresh()
        if not self:IsShown() then return end
        local characters, total = self:GetFilteredCharacters()
        local selectedKey = type(self.callbacks.getSelectedKey) == "function"
            and self.callbacks.getSelectedKey() or nil
        local currentKey = type(self.callbacks.getCurrentKey) == "function"
            and self.callbacks.getCurrentKey() or nil
        local cardHeight = self:GetCardHeight()
        local cardWidth = self:GetCardWidth()
        local cardGap = self:GetCardGap()
        local cardColumns = self:GetCardColumns()

        for index, character in ipairs(characters) do
            local card = self.cards[index]
            if not card then
                card = createCard(self.child, self)
                self.cards[index] = card
            end
            local column = (index - 1) % cardColumns
            local row = math.floor((index - 1) / cardColumns)
            card:ClearAllPoints()
            card:SetPoint(
                "TOPLEFT",
                column * (cardWidth + cardGap),
                -(row * (cardHeight + cardGap))
            )
            self:ApplyCard(card, character, selectedKey, currentKey)
        end
        for index = #characters + 1, #self.cards do
            self.cards[index].characterKey = nil
            self.cards[index]:Hide()
        end

        local rowCount = math.ceil(#characters / cardColumns)
        local contentHeight = rowCount > 0
            and ((rowCount * cardHeight) + ((rowCount - 1) * cardGap)) or 10
        self.child:SetHeight(math.max(10, contentHeight))
        self.empty:SetShown(#characters == 0)
        self.summary:SetText(string.format(
            L.WARBAND_OVERVIEW_SUMMARY,
            #characters,
            total
        ))
        VaultRewardBadge:SetSummaryCount(
            self.rewardSummary,
            Addon.VaultProgress:GetPendingRewardCount(),
            false
        )
        self:RefreshFilterLabels()
        ScrollFrames:Refresh(self.scroll)
    end

    frame:SetScript("OnShow", function() frame:Refresh() end)
    frame:SetScript("OnHide", function()
        if type(frame.search.ClearFocus) == "function" then frame.search:ClearFocus() end
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:Hide()
    return frame
end
