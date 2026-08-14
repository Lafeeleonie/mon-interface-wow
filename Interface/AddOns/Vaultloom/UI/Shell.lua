local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local VaultRewardBadge = Addon.VaultRewardBadge
local Dimensions = Theme.dimensions
local Assets = Addon.Assets
local ScrollFrames = Addon.ScrollFrames
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WOW_DIALOG_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
local ITEM_FINDER_SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"
local LANGUAGE_RELOAD_DIALOG = "VAULTLOOM_LANGUAGE_RELOAD"
local TOGGLE_BINDING_BUTTON_NAME = "VaultloomToggleBindingButton"
local TOGGLE_BINDING_COMMAND = "CLICK " .. TOGGLE_BINDING_BUTTON_NAME .. ":LeftButton"
local MAIN_TAB_MIN_WIDTH = 88
local MAIN_TAB_TEXT_PADDING = 34
local UTILITY_RESOURCE_ROW_HEIGHT = 28
local UTILITY_RESOURCE_ROW_STRIDE = 32
local SIDEBAR_SPEC_BACKGROUND_ALPHA = 0.50
local SIDEBAR_CLASS_BACKGROUND_ALPHA = 0.32
local SIDEBAR_BACKGROUND_BRIGHTNESS = 0.55
local PLAYER_SPELLS_ADDON = "Blizzard_PlayerSpells"
local playerSpellsAssetsReady = false
local BLIZZARD_FRONT_MENUS = {
    "GameMenuFrame",
    "SettingsPanel",
    "AddonList",
    "KeyBindingFrame",
    "QuickKeybindFrame",
    "ClickBindingFrame",
    "EditModeManagerFrame",
    "ColorPickerFrame",
    "StaticPopup1",
    "StaticPopup2",
    "StaticPopup3",
    "StaticPopup4",
}

local Shell = {
    activeScreenID = nil,
    activeScreen = nil,
    sessionOpenDefaultsApplied = false,
    optionsOpen = false,
    wishlistOpen = false,
    featuresOpen = false,
    warbandOverviewOpen = false,
    mythicPlusOverviewOpen = false,
    rosterButtons = {},
    visibilityRows = {},
    tabButtons = {},
    blizzardMenuFrames = {},
}

Addon.UI = Shell

local function callFrameMethod(frame, methodName, ...)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, frame, ...)
    return value, ok
end

local function registerEscapeCloseFrame(globalName)
    if type(globalName) ~= "string" or globalName == "" then return false end
    if type(_G.UISpecialFrames) ~= "table" then _G.UISpecialFrames = {} end
    for _, frameName in ipairs(_G.UISpecialFrames) do
        if frameName == globalName then return true end
    end
    table.insert(_G.UISpecialFrames, globalName)
    return true
end

function Shell:RestoreBlizzardMenuLayer(frame)
    local original = frame and frame.vaultloomMenuLayerOriginal
    if not original then return false end
    callFrameMethod(frame, "SetFrameStrata", original.strata)
    callFrameMethod(frame, "SetFrameLevel", original.level)
    frame.vaultloomMenuLayerOriginal = nil
    return true
end

function Shell:RaiseBlizzardMenuLayer(frame)
    if not frame or not self.frame or not self.frame:IsShown() then return false end
    if not frame.vaultloomMenuLayerOriginal then
        local strata = callFrameMethod(frame, "GetFrameStrata") or "DIALOG"
        local level = callFrameMethod(frame, "GetFrameLevel") or 1
        frame.vaultloomMenuLayerOriginal = { strata = strata, level = level }
    end
    local _, raised = callFrameMethod(frame, "SetFrameStrata", "TOOLTIP")
    if not raised then
        frame.vaultloomMenuLayerOriginal = nil
        return false
    end
    return true
end

function Shell:HookBlizzardFrontMenu(name, frame)
    if type(name) ~= "string" or not frame or type(frame.HookScript) ~= "function" then
        return false
    end
    if not frame.vaultloomMenuLayerHooked then
        frame.vaultloomMenuLayerHooked = true
        frame:HookScript("OnShow", function(menu)
            Shell:RaiseBlizzardMenuLayer(menu)
        end)
        frame:HookScript("OnHide", function(menu)
            Shell:RestoreBlizzardMenuLayer(menu)
        end)
    end
    self.blizzardMenuFrames[name] = frame
    if type(frame.IsShown) == "function" and frame:IsShown() then
        self:RaiseBlizzardMenuLayer(frame)
    end
    return true
end

function Shell:EnsureBlizzardMenusAbove()
    for _, name in ipairs(BLIZZARD_FRONT_MENUS) do
        local frame = _G[name]
        if frame and self.blizzardMenuFrames[name] ~= frame then
            self:HookBlizzardFrontMenu(name, frame)
        end
    end
end

function Shell:RestoreBlizzardMenuLayers()
    for _, frame in pairs(self.blizzardMenuFrames) do
        self:RestoreBlizzardMenuLayer(frame)
    end
end

local function ensureLanguageReloadDialog()
    if type(StaticPopupDialogs) ~= "table" then
        return false
    end

    local dialog = StaticPopupDialogs[LANGUAGE_RELOAD_DIALOG] or {}
    dialog.text = L.OPTIONS_LANGUAGE_RELOAD_CONFIRM
    dialog.button1 = L.OPTIONS_LANGUAGE_RELOAD_NOW
    dialog.button2 = L.SIDEBAR_CANCEL
    dialog.OnAccept = function()
        if type(ReloadUI) == "function" then
            ReloadUI()
        end
    end
    dialog.timeout = 0
    dialog.whileDead = true
    dialog.hideOnEscape = true
    dialog.preferredIndex = 3
    StaticPopupDialogs[LANGUAGE_RELOAD_DIALOG] = dialog
    return true
end

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function createWishlistListIcon(button)
    button.wishlistChecks = {}
    button.wishlistLines = {}
    button.wishlistIconTextures = {}
    for index = 1, 3 do
        local yOffset = 5 - ((index - 1) * 5)
        local check = button:CreateTexture(nil, "ARTWORK", nil, 1)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetSize(7, 7)
        check:SetPoint("CENTER", -6, yOffset)
        check:SetVertexColor(unpackColor(Theme.colors.gold))
        button.wishlistChecks[index] = check
        button.wishlistIconTextures[#button.wishlistIconTextures + 1] = check

        local line = button:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(
            Theme.colors.parchment[1],
            Theme.colors.parchment[2],
            Theme.colors.parchment[3],
            0.78
        )
        line:SetSize(8, 1)
        line:SetPoint("LEFT", check, "RIGHT", 4, 0)
        button.wishlistLines[index] = line
        button.wishlistIconTextures[#button.wishlistIconTextures + 1] = line
    end
end

local function createItemFinderSearchIcon(button)
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(ITEM_FINDER_SEARCH_ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetVertexColor(unpackColor(Theme.colors.gold))
    button.itemFinderIcon = icon
end

local function formatLastSeen(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 or type(time) ~= "function" then
        return L.UNKNOWN
    end

    local elapsed = math.max(0, time() - timestamp)
    if elapsed < 60 then
        return "now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. "m"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. "h"
    end
    return math.floor(elapsed / 86400) .. "d"
end

local function formatCoinMoney(money)
    money = math.max(0, math.floor(tonumber(money) or 0))
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(money, 12)
    end

    local gold = math.floor(money / 10000)
    local silver = math.floor((money % 10000) / 100)
    local copper = money % 100
    return string.format(
        "%d |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t  %d |TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t  %d |TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
        gold,
        silver,
        copper
    )
end

local function setClassIcon(texture, classFile)
    if not texture then
        return
    end

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

local function getSpecializationBackground(specID)
    specID = tonumber(specID)
    if not specID then return nil end

    if type(ClassTalentUtil) == "table"
        and type(ClassTalentUtil.GetVisualsForSpecID) == "function"
    then
        local ok, visuals = pcall(ClassTalentUtil.GetVisualsForSpecID, specID)
        if ok and type(visuals) == "table"
            and type(visuals.background) == "string" and visuals.background ~= ""
        then
            return visuals.background
        end
    end
    local backgrounds = Assets.specializationBackgrounds
    return backgrounds and backgrounds[specID] or nil
end

local function ensurePlayerSpellsAssets()
    if playerSpellsAssetsReady then return true end
    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(loadAddOn) == "function" then
        local ok, loaded = pcall(loadAddOn, PLAYER_SPELLS_ADDON)
        playerSpellsAssetsReady = ok and loaded == true
    end
    return playerSpellsAssetsReady
end

local function applyAtlasStretch(texture, atlas)
    if not texture or type(texture.SetTexture) ~= "function" then return false end
    ensurePlayerSpellsAssets()

    local atlasInfo
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and type(info) == "table" then atlasInfo = info end
    end
    local file = atlasInfo and atlasInfo.file
    if not atlasInfo or not file
        or pcall(texture.SetTexture, texture, file) ~= true
    then
        return false
    end
    local left = tonumber(atlasInfo and atlasInfo.leftTexCoord)
    local right = tonumber(atlasInfo and atlasInfo.rightTexCoord)
    local top = tonumber(atlasInfo and atlasInfo.topTexCoord)
    local bottom = tonumber(atlasInfo and atlasInfo.bottomTexCoord)
    if left and right and top and bottom then
        texture:SetTexCoord(left, right, top, bottom)
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", 2, -2)
    texture:SetPoint("BOTTOMRIGHT", -2, 2)
    texture.vaultloomAtlas = atlas
    return true
end

local function applySidebarCharacterBackground(card, character, enabled)
    local texture = card and card.specializationBackground
    if not texture then return end
    texture:Hide()
    if enabled ~= true then return end

    local specializationAtlas = getSpecializationBackground(character and character.specID)
    local usingSpecializationArt = specializationAtlas
        and applyAtlasStretch(texture, specializationAtlas) or false
    local applied = usingSpecializationArt
    if not applied then
        local classTexture = Assets.classHeroPlates
            and character and Assets.classHeroPlates[character.classFile]
        if classTexture then
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", 2, -2)
            texture:SetPoint("BOTTOMRIGHT", -2, 2)
            texture:SetTexture(classTexture)
            texture:SetTexCoord(0, 1, 0, 1)
            texture.vaultloomAtlas = nil
            applied = true
        end
    end
    if not applied then return end

    if type(texture.SetDesaturated) == "function" then texture:SetDesaturated(false) end
    texture:SetVertexColor(
        SIDEBAR_BACKGROUND_BRIGHTNESS,
        SIDEBAR_BACKGROUND_BRIGHTNESS,
        SIDEBAR_BACKGROUND_BRIGHTNESS,
        1
    )
    texture:SetAlpha(usingSpecializationArt
        and SIDEBAR_SPEC_BACKGROUND_ALPHA or SIDEBAR_CLASS_BACKGROUND_ALPHA)
    texture:Show()
end

local function applyHeroPlate(frame, classFile)
    local hero = frame and frame.hero
    if not hero then
        return
    end

    local classHeroPlates = Assets.classHeroPlates
    local backgroundTexture = classHeroPlates and classHeroPlates[classFile] or Assets.heroPlate
    if hero.vaultloomBackgroundTexture == backgroundTexture then
        return
    end

    Widgets:ApplyStandardGoldFrame(hero, backgroundTexture, Theme.colors.goldDim, true)
    hero.vaultloomBackgroundTexture = backgroundTexture
end

local function addCircularMask(owner, texture)
    if not owner or not texture or type(owner.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then
        return nil
    end
    local mask = owner:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

local function refreshHeroProfessionBadges(frame, character)
    if not frame or not frame.heroProfessionFrame or not Addon.ProfessionBadges then
        return false
    end
    local professions = character
        and Addon.ProfessionBadges:GetProfessions(character, false)
        or {}
    local characterKey = character and character.key or nil
    local canOpen = characterKey and Addon.WarbandRoster:IsCurrent(characterKey) or false
    local count = Addon.ProfessionBadges:Populate(
        frame.heroProfessionFrame,
        frame.heroProfessionButtons,
        professions,
        characterKey,
        canOpen,
        24,
        5
    )

    frame.heroTitle:ClearAllPoints()
    frame.heroTitle:SetPoint("TOPLEFT", frame.heroPortraitBackplate, "TOPRIGHT", 18, -2)
    if count > 0 then
        frame.heroTitle:SetPoint("TOPRIGHT", frame.heroProfessionFrame, "TOPLEFT", -10, -2)
    else
        frame.heroTitle:SetPoint("TOPRIGHT", -18, -2)
    end
    return count > 0
end

local function setDesaturated(texture, desaturated)
    if texture and type(texture.SetDesaturated) == "function" then
        texture:SetDesaturated(desaturated == true)
    end
end

local function showUtilityTooltip(owner, currencyID, itemID, hint)
    if not GameTooltip or not owner then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    if currencyID and type(GameTooltip.SetCurrencyByID) == "function" then
        GameTooltip:SetCurrencyByID(currencyID)
    elseif itemID and type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(itemID)
    end
    if type(hint) == "string" and hint ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(hint, 0.82, 0.78, 0.66, true)
    end
    GameTooltip:Show()
end

local function hideGameTooltip()
    if GameTooltip and type(GameTooltip.Hide) == "function" then
        GameTooltip:Hide()
    end
end

local function createUtilitySectionTitle(parent, text)
    local title = CreateFrame("Frame", nil, parent)
    title:SetHeight(20)
    title.label = Widgets:CreateLabel(title, "GameFontNormalLarge", "CENTER")
    title.label:SetAllPoints(title)
    title.label:SetText(text or "")
    title.label:SetTextColor(unpackColor(Theme.colors.parchment))
    if type(title.label.GetFont) == "function" and type(title.label.SetFont) == "function" then
        local fontFile, fontHeight, fontFlags = title.label:GetFont()
        if fontFile and tonumber(fontHeight) then
            title.label:SetFont(fontFile, math.max(9, tonumber(fontHeight) - 2), fontFlags)
        end
    end
    return title
end

local function createUtilityCurrencyButton(parent)
    local button = CreateFrame("Frame", nil, parent)
    button:SetSize(40, 52)
    button:EnableMouse(true)
    button.iconBorder = CreateFrame("Frame", nil, button, BACKDROP_TEMPLATE)
    button.iconBorder:SetSize(34, 34)
    button.iconBorder:SetPoint("TOP", 0, -2)
    Widgets:ApplyStandardGoldFrame(button.iconBorder, nil, Theme.colors.goldDim)
    button.icon = button.iconBorder:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(32, 32)
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetTexCoord(2 / 32, 30 / 32, 2 / 32, 30 / 32)
    button.iconMask = Widgets:AddRoundedIconMask(button.iconBorder, button.icon)
    button.count = Widgets:CreateLabel(button, "GameFontHighlightSmall", "CENTER")
    button.count:SetPoint("TOP", button.iconBorder, "BOTTOM", 0, -4)
    button.count:SetWidth(42)
    button:SetScript("OnEnter", function(selfButton)
        showUtilityTooltip(selfButton, selfButton.currencyID, nil)
    end)
    button:SetScript("OnLeave", hideGameTooltip)
    return button
end

local function layoutUtilityCurrencyButtons(panel, buttons)
    local total = #buttons
    if total == 0 then return end
    local totalWidth = (total * 40) + ((total - 1) * 8)
    for index, button in ipairs(buttons) do
        button:ClearAllPoints()
        if index == 1 then
            button:SetPoint("TOPLEFT", panel, "TOP", -(totalWidth / 2), -10)
        else
            button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 8, 0)
        end
    end
end

local SIDEBAR_META_SEPARATOR = "  |  "

local function usesStackedSidebarMeta()
    local locale = tostring(Addon.locale or Addon.clientLocale or "")
    return locale == "zhCN" or locale == "zhTW" or locale == "koKR"
end

local function buildSidebarMetaParts(character, settings)
    local fields = settings and settings.fields or {}
    local parts = {}
    if fields.level then
        parts[#parts + 1] = string.format(L.SIDEBAR_LEVEL_SHORT, tonumber(character and character.level) or 0)
    end
    if fields.itemLevel then
        local itemLevel = tonumber(character and character.itemLevel)
        parts[#parts + 1] = string.format(L.SIDEBAR_ITEM_LEVEL_SHORT, itemLevel and string.format("%.1f", itemLevel) or "-")
    end
    if fields.activityScore and Addon.ActivityScore then
        local score = Addon.ActivityScore:Get(character and character.key)
        if score then parts[#parts + 1] = score.coloredLabel end
    end
    return parts
end

local function hasSidebarMeta(settings)
    local fields = settings and settings.fields or {}
    return fields.level == true or fields.itemLevel == true or fields.activityScore == true
end

local function getSidebarDisplayName(character, settings)
    return character and character.name or L.UNKNOWN
end

local function createVaultStrip(parent, leftOffset)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(16)
    strip:SetPoint("BOTTOMLEFT", leftOffset or 52, 6)
    strip:SetPoint("BOTTOMRIGHT", -10, 6)
    strip.labels = {}
    for index, key in ipairs({ "raid", "dungeon", "world" }) do
        local label = Widgets:CreateLabel(strip, "GameFontHighlightSmall", "LEFT")
        label:SetWidth(42)
        label:SetPoint("LEFT", strip, "LEFT", (index - 1) * 46, 0)
        strip.labels[key] = label
    end
    return strip
end

local function stripSidebarMetaFormatting(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

local function measureSidebarMetaLine(region, text)
    if not region then return nil end
    region:SetText(stripSidebarMetaFormatting(text))
    local measure = region.GetUnboundedStringWidth or region.GetStringWidth
    if type(measure) ~= "function" then return nil end
    local ok, width = pcall(measure, region)
    if not ok or type(width) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        local secretOk, secret = pcall(issecretvalue, width)
        if secretOk and secret then return nil end
    end
    return width
end

local function buildAdaptiveSidebarMetaLines(region, parts, contentWidth)
    parts = type(parts) == "table" and parts or {}
    contentWidth = math.max(1, tonumber(contentWidth) or 1)
    region:SetWidth(contentWidth)
    if type(region.SetWordWrap) == "function" then region:SetWordWrap(false) end
    if type(region.SetMaxLines) == "function" then region:SetMaxLines(1) end

    if #parts > 1 and usesStackedSidebarMeta() then
        return parts
    end

    local singleLine = table.concat(parts, SIDEBAR_META_SEPARATOR)
    local singleWidth = measureSidebarMetaLine(region, singleLine)
    if #parts < 2 or not singleWidth or singleWidth <= contentWidth then
        return { singleLine }
    end

    local bestSplit = math.max(1, #parts - 1)
    local bestWidth
    for splitIndex = #parts - 1, 1, -1 do
        local left = table.concat(parts, SIDEBAR_META_SEPARATOR, 1, splitIndex)
        local right = table.concat(parts, SIDEBAR_META_SEPARATOR, splitIndex + 1, #parts)
        local leftWidth = measureSidebarMetaLine(region, left)
        local rightWidth = measureSidebarMetaLine(region, right)
        if leftWidth and rightWidth then
            local widest = math.max(leftWidth, rightWidth)
            if widest <= contentWidth then
                bestSplit = splitIndex
                bestWidth = widest
                break
            end
            if not bestWidth or widest < bestWidth then
                bestSplit = splitIndex
                bestWidth = widest
            end
        end
    end

    local left = table.concat(parts, SIDEBAR_META_SEPARATOR, 1, bestSplit)
    local right = table.concat(parts, SIDEBAR_META_SEPARATOR, bestSplit + 1, #parts)
    return { left, right }
end

local function createSidebarMetaLabels(card)
    card.metaLines = {}
    for index = 1, 3 do
        local line = Widgets:CreateLabel(card, "GameFontHighlightSmall", "LEFT")
        line:SetHeight(14)
        line:SetWordWrap(false)
        line:SetMaxLines(1)
        if index > 1 then line:Hide() end
        card.metaLines[index] = line
    end
    card.meta = card.metaLines[1]
end

local function getSidebarCardHeight(settings, currentCard, metaHeight)
    local fields = settings and settings.fields or {}
    local showMeta = hasSidebarMeta(settings)
    local contentBottom = currentCard and 51 or 27
    if showMeta then contentBottom = contentBottom + math.max(14, tonumber(metaHeight) or 14) + 4 end
    if fields.realm == true then contentBottom = contentBottom + 18 end
    if fields.gold == true then contentBottom = contentBottom + 18 end
    if fields.professions == true then contentBottom = contentBottom + 26 end
    if fields.vault == true then contentBottom = contentBottom + 20 end
    return math.max(currentCard and 68 or 44, contentBottom + 8)
end

local function applySidebarCardLayout(card, settings, currentCard, metaParts)
    local fields = settings and settings.fields or {}
    local showMeta = hasSidebarMeta(settings)
    local showRealm = fields.realm == true
    local showMoney = fields.gold == true
    local showProfessions = fields.professions == true
    local showVault = fields.vault == true
    local contentWidth = currentCard and 142 or 174
    local metaLines = showMeta
        and buildAdaptiveSidebarMetaLines(card.meta, metaParts, contentWidth)
        or {}
    local metaLineCount = showMeta and math.max(1, #metaLines) or 0
    local metaHeight = math.max(14, metaLineCount * 14)
    local previous = card.name
    local height = getSidebarCardHeight(settings, currentCard, metaHeight)
    card:SetHeight(height)

    local function placeLine(region, shown, lineHeight, gap)
        region:SetShown(shown)
        if shown then
            region:ClearAllPoints()
            region:SetHeight(lineHeight)
            region:SetWidth(contentWidth)
            region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap == nil and 4 or gap))
            previous = region
        end
    end

    for index, line in ipairs(card.metaLines or { card.meta }) do
        local lineShown = showMeta and index <= metaLineCount
        if lineShown then line:SetText(metaLines[index] or "") end
        placeLine(line, lineShown, 14, index == 1 and 4 or 0)
    end
    placeLine(card.realm, showRealm, 14)
    placeLine(card.money, showMoney, 14)
    placeLine(card.professionFrame, showProfessions, 22)
    placeLine(card.vaultStrip, showVault, 16)

    return height, showMoney, showVault, showProfessions
end

local function refreshSidebarProfessions(card, character, settings, current)
    if not card or not card.professionFrame then return 0 end
    local showProfessions = settings
        and settings.fields
        and settings.fields.professions == true
    local professions = showProfessions
        and Addon.ProfessionBadges:GetProfessions(character, true)
        or {}
    return Addon.ProfessionBadges:Populate(
        card.professionFrame,
        card.professionButtons,
        professions,
        character and character.key,
        current == true,
        22,
        5
    )
end

local function refreshVaultStrip(strip, characterKey)
    if not strip then return end
    local summary = Addon.ActivityScore and Addon.ActivityScore:GetVaultSummary(characterKey) or nil
    local shortLabels = {
        raid = L.SIDEBAR_VAULT_RAID_SHORT,
        dungeon = L.SIDEBAR_VAULT_DUNGEON_SHORT,
        world = L.SIDEBAR_VAULT_WORLD_SHORT,
    }
    for _, key in ipairs({ "raid", "dungeon", "world" }) do
        local label = strip.labels[key]
        local entry = summary and summary[key]
        if entry and (tonumber(entry.maximum) or 0) > 0 then
            label:SetText(string.format("%s %d/%d", shortLabels[key], entry.current or 0, entry.maximum))
            if entry.complete then
                label:SetTextColor(unpackColor(Theme.colors.world))
            elseif (tonumber(entry.current) or 0) > 0 then
                label:SetTextColor(unpackColor(Theme.colors.gold))
            else
                label:SetTextColor(unpackColor(Theme.colors.muted))
            end
        else
            label:SetText(string.format("%s %s", shortLabels[key], L.SIDEBAR_VAULT_UNKNOWN))
            label:SetTextColor(unpackColor(Theme.colors.muted))
        end
    end
end

local function positionSidebarCardName(button, showMainTag)
    if not button or not button.name then return end
    button.name:ClearAllPoints()
    button.name:SetPoint("TOPLEFT", 56, -10)
    if showMainTag and button.mainTag then
        button.name:SetPoint("TOPRIGHT", button.mainTag, "TOPLEFT", -5, 0)
    else
        button.name:SetPoint("TOPRIGHT", -12, -10)
    end
end

local function showActivityScoreTooltip(owner, characterKey)
    if not GameTooltip or not Addon.ActivityScore then return end
    local score = Addon.ActivityScore:Get(characterKey)
    if not score then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.ACTIVITY_SCORE_TOOLTIP_TITLE, unpackColor(Theme.colors.gold))
    local color = score.color or Theme.colors.muted
    GameTooltip:AddLine(string.format(L.ACTIVITY_SCORE_TOOLTIP_VALUE, score.score or 0), color[1], color[2], color[3], true)
    GameTooltip:AddLine(L.ACTIVITY_SCORE_TOOLTIP_LINE, 0.72, 0.78, 0.88, true)
    for _, detail in ipairs(score.details or {}) do
        GameTooltip:AddDoubleLine(detail.label or detail.key, detail.value or "", 0.84, 0.82, 0.74, 0.93, 0.89, 0.77)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.SIDEBAR_RIGHT_CLICK_MAIN, 0.72, 0.78, 0.88, true)
    GameTooltip:Show()
end

local function applyCharacterPortrait(texture, character, usePlayerPortrait)
    if not texture then
        return
    end
    if usePlayerPortrait and type(SetPortraitTexture) == "function" then
        texture:SetTexCoord(0, 1, 0, 1)
        local ok = pcall(SetPortraitTexture, texture, "player")
        if ok then
            return
        end
    end
    setClassIcon(texture, character and character.classFile)
end

local SORT_OPTIONS = {
    { key = "name", label = function() return L.SIDEBAR_SORT_NAME end },
    { key = "level", label = function() return L.SIDEBAR_SORT_LEVEL end },
    { key = "itemLevel", label = function() return L.SIDEBAR_SORT_ITEM_LEVEL end },
    { key = "realm", label = function() return L.SIDEBAR_SORT_REALM end },
    { key = "activityScore", label = function() return L.SIDEBAR_SORT_ACTIVITY_SCORE end },
    { key = "vault", label = function() return L.SIDEBAR_SORT_VAULT end },
}

local BANNER_PREVIEW_CLASSES = {
    { classFile = "DEATHKNIGHT", label = "Todesritter" },
    { classFile = "DEMONHUNTER", label = "Dämonenjäger" },
    { classFile = "DRUID", label = "Druide" },
    { classFile = "EVOKER", label = "Rufer" },
    { classFile = "HUNTER", label = "Jäger" },
    { classFile = "MAGE", label = "Magier" },
    { classFile = "MONK", label = "Mönch" },
    { classFile = "PALADIN", label = "Paladin" },
    { classFile = "PRIEST", label = "Priester" },
    { classFile = "ROGUE", label = "Schurke" },
    { classFile = "SHAMAN", label = "Schamane" },
    { classFile = "WARLOCK", label = "Hexer" },
    { classFile = "WARRIOR", label = "Krieger" },
}

local function getBannerPreviewDefinition(classFile)
    for _, definition in ipairs(BANNER_PREVIEW_CLASSES) do
        if definition.classFile == classFile then
            return definition
        end
    end
    return nil
end

function Shell:ApplyDisplaySettings()
    if not self.frame then
        return
    end
    local ui = Addon.Database:GetUI()
    if math.abs((tonumber(self.frame:GetScale()) or 1) - ui.scale) > 0.0001 then
        self.frame:SetScale(ui.scale)
    end
    if math.abs((tonumber(self.frame:GetAlpha()) or 1) - ui.opacity) > 0.0001 then
        self.frame:SetAlpha(ui.opacity)
    end
end

function Shell:SetScale(value)
    local ui = Addon.Database:GetUI()
    ui.scale = math.max(0.70, math.min(1.25, tonumber(value) or 1))
    self:ApplyDisplaySettings()
    self:ApplyWindowPosition()
    return ui.scale
end

function Shell:SetOpacity(value)
    local ui = Addon.Database:GetUI()
    ui.opacity = math.max(0.65, math.min(1, tonumber(value) or 1))
    self:ApplyDisplaySettings()
    return ui.opacity
end

function Shell:ApplyWindowPosition()
    if not self.frame then
        return
    end
    local ui = Addon.Database:GetUI()
    local window = ui.window
    local scale = math.max(0.01, tonumber(ui.scale) or 1)
    self.frame:ClearAllPoints()
    -- StopMoving stores screen-space offsets. SetPoint offsets on a scaled
    -- frame are frame-local, so undo the frame scale when restoring them.
    self.frame:SetPoint(
        window.point,
        UIParent,
        window.relativePoint,
        (tonumber(window.x) or 0) / scale,
        (tonumber(window.y) or 0) / scale
    )
end

function Shell:StoreWindowPosition(positionFromMoving)
    if not self.frame then
        return
    end
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    if not point then
        return
    end
    local window = Addon.Database:GetUI().window
    window.point = point
    window.relativePoint = relativePoint or point
    local scale = math.max(0.01, tonumber(self.frame:GetScale()) or 1)
    local coordinateScale = positionFromMoving == true and 1 or scale
    window.x = (tonumber(x) or 0) * coordinateScale
    window.y = (tonumber(y) or 0) * coordinateScale
end

function Shell:StartWindowDrag()
    local frame = self.frame
    if not frame then return false end

    -- StartMoving can mark globally named frames as user placed. Keep the
    -- position under Vaultloom's SavedVariables control.
    frame:SetUserPlaced(false)
    frame:StartMoving()
    return true
end

function Shell:StopWindowDrag()
    local frame = self.frame
    if not frame then return false end

    frame:StopMovingOrSizing()
    self:StoreWindowPosition(true)
    frame:SetUserPlaced(false)
    -- Replace Blizzard's transient drag anchor with one stable UIParent
    -- anchor so later layout updates cannot make the next drag jump.
    self:ApplyWindowPosition()
    return true
end

function Shell:ApplySessionOpenDefaults()
    if self.sessionOpenDefaultsApplied or not self.frame then
        return false
    end

    self.sessionOpenDefaultsApplied = true
    self.optionsOpen = false
    self.wishlistOpen = false
    self.featuresOpen = false

    local frame = self.frame
    if frame.optionsPanel then frame.optionsPanel:Hide() end
    if frame.wishlistPanel then frame.wishlistPanel:Hide() end
    if frame.featuresPanel then frame.featuresPanel:Hide() end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Addon.Database:GetUI().selectedScreen = "vault"
    return true
end

function Shell:ResetWindowSettings()
    Addon.Database:ResetWindowSettings()
    self:ApplyDisplaySettings()
    self:ApplyWindowPosition()
end

function Shell:ResetDisplaySettings()
    Addon.Database:ResetDisplaySettings()
    self:ApplyDisplaySettings()
    self:ApplyWindowPosition()
end

function Shell:ResetWindowPosition()
    Addon.Database:ResetWindowPosition()
    self:ApplyWindowPosition()
end

function Shell:CreateTitleBar(frame)
    local function enableWindowDrag(handle)
        handle:EnableMouse(true)
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", function()
            Shell:StartWindowDrag()
        end)
        handle:SetScript("OnDragStop", function()
            Shell:StopWindowDrag()
        end)
    end

    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -8)
    frame.titleBar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -3, -8)
    frame.titleBar:SetHeight(Dimensions.titleHeight)
    enableWindowDrag(frame.titleBar)

    frame.titleBarFill = frame.titleBar:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.titleBarFill:SetAllPoints()
    frame.titleBarFill:SetColorTexture(0.12, 0.085, 0.060, 0.98)

    frame.titleBarTexture = frame.titleBar:CreateTexture(nil, "BACKGROUND")
    frame.titleBarTexture:SetAllPoints()
    frame.titleBarTexture:SetTexture(Assets.titleBarStone)
    frame.titleBarTexture:SetHorizTile(false)
    frame.titleBarTexture:SetVertTile(false)
    frame.titleBarTexture:SetVertexColor(1, 1, 1, 1)

    frame.titleBarShade = frame.titleBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.titleBarShade:SetAllPoints()
    frame.titleBarShade:SetColorTexture(0, 0, 0, 0.10)

    frame.titleBarTopLine = frame.titleBar:CreateTexture(nil, "BORDER")
    frame.titleBarTopLine:SetPoint("TOPLEFT", 0, -1)
    frame.titleBarTopLine:SetPoint("TOPRIGHT", 0, -1)
    frame.titleBarTopLine:SetHeight(1)
    frame.titleBarTopLine:SetColorTexture(0.76, 0.63, 0.38, 0.58)

    frame.titleBarBottomLine = frame.titleBar:CreateTexture(nil, "BORDER")
    frame.titleBarBottomLine:SetPoint("BOTTOMLEFT", 0, 1)
    frame.titleBarBottomLine:SetPoint("BOTTOMRIGHT", 0, 1)
    frame.titleBarBottomLine:SetHeight(1)
    frame.titleBarBottomLine:SetColorTexture(0.05, 0.035, 0.025, 0.82)

    frame.titleMedallion = frame.titleBar:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.titleMedallion:SetSize(69, 69)
    frame.titleMedallion:SetPoint("CENTER", frame.titleBar, "LEFT", 19, -8)
    frame.titleMedallion:SetTexture(Assets.titleMedallion)
    frame.titleMedallion:SetTexCoord(0, 1, 0, 1)

    frame.titleMedallionDrag = CreateFrame("Frame", nil, frame.titleBar)
    frame.titleMedallionDrag:SetSize(61, 61)
    frame.titleMedallionDrag:SetPoint("CENTER", frame.titleBar, "LEFT", 19, -8)
    enableWindowDrag(frame.titleMedallionDrag)

    frame.brand = Widgets:CreateLabel(frame.titleBar, "GameFontNormal", "CENTER")
    frame.brand:SetPoint("CENTER", 0, 0)
    frame.brand:SetText(L.WINDOW_TITLE)
    frame.brand:SetTextColor(unpackColor(Theme.colors.gold))

    frame.development = Widgets:CreateLabel(frame.titleBar, "GameFontHighlightSmall", "LEFT")
    frame.development:SetPoint("LEFT", frame.brand, "RIGHT", 10, 0)
    frame.development:SetText(L.DEVELOPMENT_BADGE)
    frame.development:SetTextColor(unpackColor(Theme.colors.cyan))

    frame.version = Widgets:CreateLabel(frame.titleBar, "GameFontDisableSmall", "RIGHT")
    frame.version:SetPoint("RIGHT", -36, 0)
    frame.version:SetText(Addon.version)

    frame.closeButton = CreateFrame("Button", nil, frame.titleBar)
    frame.closeButton:SetSize(28, 28)
    frame.closeButton:SetPoint("CENTER", frame.titleBar, "RIGHT", -11, 0)
    frame.closeButtonArt = frame.closeButton:CreateTexture(nil, "ARTWORK")
    frame.closeButtonArt:SetAllPoints()
    frame.closeButtonArt:SetTexture(Assets.titleCloseButton)
    frame.closeButtonArt:SetTexCoord(0, 1, 0, 1)

    frame.closeButtonHighlight = frame.closeButton:CreateTexture(nil, "HIGHLIGHT")
    frame.closeButtonHighlight:SetAllPoints()
    frame.closeButtonHighlight:SetTexture(Assets.titleCloseButton)
    frame.closeButtonHighlight:SetTexCoord(0, 1, 0, 1)
    frame.closeButtonHighlight:SetBlendMode("ADD")
    frame.closeButtonHighlight:SetAlpha(0.18)
    frame.closeButton:SetScript("OnMouseDown", function()
        frame.closeButtonArt:SetAlpha(0.78)
    end)
    frame.closeButton:SetScript("OnMouseUp", function()
        frame.closeButtonArt:SetAlpha(1)
    end)
    frame.closeButton:SetScript("OnLeave", function()
        frame.closeButtonArt:SetAlpha(1)
    end)
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
end

function Shell:FitMainTabButton(button)
    if not button or not button.label then
        return 0
    end

    local textWidth
    if type(button.label.GetUnboundedStringWidth) == "function" then
        textWidth = callFrameMethod(button.label, "GetUnboundedStringWidth")
    end
    if not tonumber(textWidth) or textWidth <= 0 then
        textWidth = callFrameMethod(button.label, "GetStringWidth")
    end

    local width = math.max(MAIN_TAB_MIN_WIDTH, math.ceil((tonumber(textWidth) or 0) + MAIN_TAB_TEXT_PADDING))
    button:SetWidth(width)
    button.vaultloomFittedTextWidth = tonumber(textWidth) or 0
    return width
end

function Shell:CreateTabs(frame)
    frame.tabBar = CreateFrame("Frame", nil, frame.body)
    frame.tabBar:SetPoint("TOPLEFT", 0, 0)
    frame.tabBar:SetPoint("TOPRIGHT", 0, 0)
    frame.tabBar:SetHeight(Dimensions.tabHeight)

    local previous
    for _, definition in ipairs(Addon.ScreenRegistry:GetDefinitions()) do
        local button = Widgets:CreateButton(frame.tabBar, definition.label(), MAIN_TAB_MIN_WIDTH, 30, "tab")
        self:FitMainTabButton(button)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end
        button.screenID = definition.id
        if definition.id == "housing" or definition.id == "compendium" then
            button.newBadge = Widgets:CreateLabel(button, "GameFontNormalSmall", "RIGHT")
            button.newBadge:SetPoint("TOPRIGHT", -3, -1)
            button.newBadge:SetText(L.OPTIONS_NEW_BADGE)
            button.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
            button.newBadge:Hide()
        end
        button:SetScript("OnClick", function(self)
            local changed = Shell.activeScreenID ~= self.screenID
                or Shell.optionsOpen == true
                or Shell.wishlistOpen == true
                or Shell.featuresOpen == true
            if changed and Addon.Sound then
                Addon.Sound:Play("tabSwitch")
            end
            if Shell:ShowScreen(self.screenID) then
                if self.screenID == "housing" then
                    Shell:MarkNewInterfaceSeen("housing_tab")
                elseif self.screenID == "compendium" then
                    Shell:MarkNewInterfaceSeen("compendium_tab")
                end
            end
        end)
        self.tabButtons[definition.id] = button
        previous = button
    end

    frame.wishlistButton = Widgets:CreateButton(frame.tabBar, "", 38, 30, "tab")
    frame.wishlistButton:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    frame.wishlistButton.label:Hide()
    createWishlistListIcon(frame.wishlistButton)
    frame.wishlistButton:SetScript("OnClick", function()
        Shell:ToggleWishlist()
    end)
    local wishlistEnter = frame.wishlistButton:GetScript("OnEnter")
    local wishlistLeave = frame.wishlistButton:GetScript("OnLeave")
    frame.wishlistButton:SetScript("OnEnter", function(selfButton)
        if wishlistEnter then wishlistEnter(selfButton) end
        local character = Addon.WarbandRoster:GetSelected() or Addon.StateStore:Get("character.identity")
        local counts = Addon.JournalLootTracker:GetCounts(character and character.key)
        if GameTooltip then
            GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(L.WISHLIST_BUTTON_TOOLTIP, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(string.format(L.WISHLIST_BUTTON_SUMMARY, counts.wish, counts.obtained), 0.86, 0.86, 0.82, true)
            GameTooltip:AddLine(
                Shell.wishlistOpen and L.WISHLIST_BUTTON_CLOSE or L.WISHLIST_BUTTON_OPEN,
                0.72,
                0.78,
                0.88,
                true
            )
            GameTooltip:Show()
        end
    end)
    frame.wishlistButton:SetScript("OnLeave", function(selfButton)
        if wishlistLeave then wishlistLeave(selfButton) end
        hideGameTooltip()
    end)

    frame.itemFinderButton = Widgets:CreateButton(frame.tabBar, "", 38, 30, "tab")
    frame.itemFinderButton:SetPoint("LEFT", frame.wishlistButton, "RIGHT", 4, 0)
    frame.itemFinderButton.label:Hide()
    createItemFinderSearchIcon(frame.itemFinderButton)
    frame.itemFinderButton:SetScript("OnClick", function()
        if Addon.ItemFinder and type(Addon.ItemFinder.Toggle) == "function" then
            Addon.ItemFinder:Toggle()
        end
    end)
    local itemFinderEnter = frame.itemFinderButton:GetScript("OnEnter")
    local itemFinderLeave = frame.itemFinderButton:GetScript("OnLeave")
    frame.itemFinderButton:SetScript("OnEnter", function(selfButton)
        if itemFinderEnter then itemFinderEnter(selfButton) end
        if GameTooltip then
            local windowOpen = Addon.ItemFinder
                and Addon.ItemFinder.window
                and Addon.ItemFinder.window:IsShown()
            GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:AddLine(L.ITEM_FINDER_BUTTON_TOOLTIP, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(
                windowOpen and L.ITEM_FINDER_BUTTON_CLOSE or L.ITEM_FINDER_BUTTON_OPEN,
                0.72,
                0.78,
                0.88,
                true
            )
            GameTooltip:Show()
        end
    end)
    frame.itemFinderButton:SetScript("OnLeave", function(selfButton)
        if itemFinderLeave then itemFinderLeave(selfButton) end
        hideGameTooltip()
    end)

    frame.optionsButton = Widgets:CreateButton(frame.tabBar, L.OPTIONS, 82, 30)
    frame.optionsButton:SetPoint("RIGHT", 0, 0)
    frame.optionsButton.newBadge = Widgets:CreateLabel(frame.optionsButton, "GameFontNormalSmall", "RIGHT")
    frame.optionsButton.newBadge:SetPoint("TOPRIGHT", -3, -1)
    frame.optionsButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.optionsButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.optionsButton:SetScript("OnClick", function()
        Shell:ToggleOptions()
    end)

    frame.featuresButton = Widgets:CreateButton(frame.tabBar, L.FEATURES, 88, 30)
    frame.featuresButton:SetPoint("RIGHT", frame.optionsButton, "LEFT", -4, 0)
    frame.featuresButton.newBadge = Widgets:CreateLabel(frame.featuresButton, "GameFontNormalSmall", "RIGHT")
    frame.featuresButton.newBadge:SetPoint("TOPRIGHT", -3, -1)
    frame.featuresButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.featuresButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.featuresButton:SetScript("OnClick", function()
        Shell:ToggleFeatures()
    end)

    self:RefreshMainTabs()
    self:RefreshOptionsButton()
    self:RefreshFeaturesButton()
end

function Shell:GetOptionSettings()
    local ui = Addon.Database:GetUI()
    ui.options = type(ui.options) == "table" and ui.options or {
        selectedPage = "general",
        hiddenMainTabs = {},
        lastReadRelease = "",
    }
    ui.options.hiddenMainTabs = type(ui.options.hiddenMainTabs) == "table"
        and ui.options.hiddenMainTabs or {}
    return ui.options
end

function Shell:GetLanguagePreference()
    return Addon.Database:GetUI().language or "auto"
end

function Shell:GetLanguageOptions()
    local registry = Addon.LocaleRegistry
    local effectiveLocale = registry:Resolve("auto", Addon.clientLocale)
    local effectiveName = registry:GetDisplayName(effectiveLocale)
    local options = {
        {
            key = "auto",
            label = L.OPTIONS_LANGUAGE_AUTOMATIC,
            detail = string.format(L.OPTIONS_LANGUAGE_CLIENT, effectiveName),
        },
    }
    for _, locale in ipairs(registry:GetAvailable()) do
        options[#options + 1] = {
            key = locale.key,
            label = locale.name,
            detail = string.format(L.OPTIONS_LANGUAGE_FIXED, locale.name),
        }
    end
    return options
end

function Shell:SetLanguagePreference(localeKey)
    if localeKey ~= "auto" and not Addon.LocaleRegistry:IsSupported(localeKey) then
        return false
    end
    local db = Addon.Database:Get()
    db.ui.language = localeKey
    _G[Addon.Identity.savedVariables] = db
    _G[Addon.Identity.languageSavedVariable] = localeKey
    return true
end

function Shell:ReloadForLanguage()
    if type(StaticPopup_Show) ~= "function"
        or not ensureLanguageReloadDialog()
    then
        return false
    end
    StaticPopup_Show(LANGUAGE_RELOAD_DIALOG)
    return true
end

function Shell:IsScreenVisible(screenID)
    return self:GetOptionSettings().hiddenMainTabs[screenID] ~= true
end

function Shell:GetVisibleScreenCount()
    local count = 0
    for _, definition in ipairs(Addon.ScreenRegistry:GetDefinitions()) do
        if self:IsScreenVisible(definition.id) then
            count = count + 1
        end
    end
    return count
end

function Shell:GetFirstVisibleScreenID()
    for _, definition in ipairs(Addon.ScreenRegistry:GetDefinitions()) do
        if self:IsScreenVisible(definition.id) then
            return definition.id
        end
    end
    return "vault"
end

function Shell:SetScreenVisible(screenID, visible)
    if not Addon.ScreenRegistry:GetDefinition(screenID) then
        return false
    end
    if visible ~= true and self:IsScreenVisible(screenID) and self:GetVisibleScreenCount() <= 1 then
        return false
    end

    local hidden = self:GetOptionSettings().hiddenMainTabs
    if visible == true then
        hidden[screenID] = nil
    else
        hidden[screenID] = true
    end
    self:RefreshMainTabs()
    if not self.optionsOpen and self.activeScreenID == screenID and visible ~= true then
        self:ShowScreen(self:GetFirstVisibleScreenID())
    end
    return true
end

function Shell:ShowAllScreens()
    local hidden = self:GetOptionSettings().hiddenMainTabs
    for screenID in pairs(hidden) do
        hidden[screenID] = nil
    end
    self:RefreshMainTabs()
end

function Shell:RefreshMainTabs()
    if not self.frame or not self.frame.tabBar then
        return
    end

    local previous
    for _, definition in ipairs(Addon.ScreenRegistry:GetDefinitions()) do
        local button = self.tabButtons[definition.id]
        if button then
            button.label:SetText(definition.label())
            self:FitMainTabButton(button)
            local visible = self:IsScreenVisible(definition.id)
            button:SetShown(visible)
            button:ClearAllPoints()
            if visible then
                if previous then
                    button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
                else
                    button:SetPoint("LEFT", 0, 0)
                end
                previous = button
            end
        end
    end
    if self.frame.wishlistButton then
        self.frame.wishlistButton:ClearAllPoints()
        if previous then
            self.frame.wishlistButton:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            self.frame.wishlistButton:SetPoint("LEFT", 0, 0)
        end
    end
    if self.frame.itemFinderButton then
        self.frame.itemFinderButton:ClearAllPoints()
        self.frame.itemFinderButton:SetPoint("LEFT", self.frame.wishlistButton, "RIGHT", 4, 0)
    end
    self:RefreshItemFinderButton()
end

function Shell:HasUnreadReleaseNotes()
    local latest = Addon.ReleaseNotes and Addon.ReleaseNotes.latestVersion or ""
    return latest ~= "" and self:GetOptionSettings().lastReadRelease ~= latest
end

function Shell:GetFeatureSettings()
    local ui = Addon.Database:GetUI()
    ui.features = type(ui.features) == "table" and ui.features or {}
    ui.features.seenNewFeatureReleases = type(ui.features.seenNewFeatureReleases) == "table"
        and ui.features.seenNewFeatureReleases or {}
    return ui.features
end

function Shell:GetCurrentNewFeatureRelease()
    local release = Addon.ReleaseNotes and Addon.ReleaseNotes.current or nil
    if not release or type(release.version) ~= "string"
        or type(release.newFeatureIDs) ~= "table"
    then
        return nil, nil
    end
    return release.version, release.newFeatureIDs
end

function Shell:IsFeatureNew(featureID)
    if type(featureID) ~= "string" or featureID == "" then return false end
    local version, featureIDs = self:GetCurrentNewFeatureRelease()
    if not version then return false end
    local listed = false
    for _, candidate in ipairs(featureIDs) do
        if candidate == featureID then
            listed = true
            break
        end
    end
    if not listed then return false end
    return self:GetFeatureSettings().seenNewFeatureReleases[featureID] ~= version
end

function Shell:HasUnseenNewFeatures()
    local _, featureIDs = self:GetCurrentNewFeatureRelease()
    for _, featureID in ipairs(featureIDs or {}) do
        if self:IsFeatureNew(featureID) then return true end
    end
    return false
end

function Shell:MarkFeatureSeen(featureID)
    if not self:IsFeatureNew(featureID) then return false end
    local version = self:GetCurrentNewFeatureRelease()
    self:GetFeatureSettings().seenNewFeatureReleases[featureID] = version
    self:RefreshFeaturesButton()
    if self.frame and self.frame.featuresPanel
        and type(self.frame.featuresPanel.RefreshRows) == "function"
    then
        self.frame.featuresPanel:RefreshRows()
    end
    return true
end

function Shell:GetNewIndicatorSettings()
    local ui = Addon.Database:GetUI()
    ui.newIndicators = type(ui.newIndicators) == "table" and ui.newIndicators or {}
    ui.newIndicators.seenReleases = type(ui.newIndicators.seenReleases) == "table"
        and ui.newIndicators.seenReleases or {}
    return ui.newIndicators
end

function Shell:GetCurrentNewInterfaceRelease()
    local release = Addon.ReleaseNotes and Addon.ReleaseNotes.current or nil
    if not release or type(release.version) ~= "string"
        or type(release.newInterfaceIDs) ~= "table"
    then
        return nil, nil
    end
    return release.version, release.newInterfaceIDs
end

function Shell:IsNewInterface(indicatorID)
    if type(indicatorID) ~= "string" or indicatorID == "" then return false end
    local version, indicatorIDs = self:GetCurrentNewInterfaceRelease()
    if not version then return false end
    local listed = false
    for _, candidate in ipairs(indicatorIDs) do
        if candidate == indicatorID then
            listed = true
            break
        end
    end
    if not listed then return false end
    return self:GetNewIndicatorSettings().seenReleases[indicatorID] ~= version
end

function Shell:RefreshNewInterfaceBadges()
    local frame = self.frame
    local specializationArtIsNew = self:IsNewInterface("warband_specialization_art")
    local sidebarSettingsButton = frame and frame.sidebarSettingsButton
    if sidebarSettingsButton and sidebarSettingsButton.newBadge then
        sidebarSettingsButton.newBadge:SetShown(specializationArtIsNew)
    end
    local specializationArtButton = frame and frame.warbandFieldButtons
        and frame.warbandFieldButtons.specializationArt
    if specializationArtButton and specializationArtButton.newBadge then
        specializationArtButton.newBadge:SetShown(specializationArtIsNew)
    end

    local housingButton = self.tabButtons and self.tabButtons.housing
    if housingButton and housingButton.newBadge then
        housingButton.newBadge:SetShown(self:IsNewInterface("housing_tab"))
    end

    local compendiumButton = self.tabButtons and self.tabButtons.compendium
    if compendiumButton and compendiumButton.newBadge then
        compendiumButton.newBadge:SetShown(self:IsNewInterface("compendium_tab"))
    end

    local utilitySettingsButton = frame and frame.utilitySettingsButton
    if utilitySettingsButton and utilitySettingsButton.newBadge then
        utilitySettingsButton.newBadge:SetShown(
            self:IsNewInterface("utility_resource_settings")
        )
    end

    local sortButton = frame and frame.sidebarSortButton
    local manualButton = frame and frame.sidebarManualOrderButton
    if sortButton and sortButton.newBadge then
        sortButton.newBadge:SetShown(self:IsNewInterface("warband_manual_order"))
    end
    if manualButton and manualButton.newBadge then
        manualButton.newBadge:SetShown(self:IsNewInterface("warband_manual_order"))
    end
    local arsenal = Addon.ScreenRegistry.instances and Addon.ScreenRegistry.instances.arsenal
    local mailButton = arsenal and arsenal.modeButtons and arsenal.modeButtons.mail
    if mailButton and mailButton.newBadge then
        mailButton.newBadge:SetShown(self:IsNewInterface("arsenal_mail"))
    end
end

function Shell:MarkNewInterfaceSeen(indicatorID)
    if not self:IsNewInterface(indicatorID) then return false end
    local version = self:GetCurrentNewInterfaceRelease()
    self:GetNewIndicatorSettings().seenReleases[indicatorID] = version
    self:RefreshNewInterfaceBadges()
    return true
end

function Shell:MarkReleaseRead(version)
    version = tostring(version or "")
    if version ~= "" then
        self:GetOptionSettings().lastReadRelease = version
    end
    self:RefreshOptionsButton()
end

function Shell:RefreshOptionsButton()
    if not self.frame or not self.frame.optionsButton then
        return
    end
    Widgets:SetButtonActive(self.frame.optionsButton, self.optionsOpen == true)
    if self.frame.optionsButton.newBadge then
        self.frame.optionsButton.newBadge:SetShown(self:HasUnreadReleaseNotes())
    end
end

function Shell:RefreshFeaturesButton()
    if not self.frame or not self.frame.featuresButton then
        return
    end
    Widgets:SetButtonActive(self.frame.featuresButton, self.featuresOpen == true)
    if self.frame.featuresButton.newBadge then
        self.frame.featuresButton.newBadge:SetShown(self:HasUnseenNewFeatures())
    end
end

function Shell:RefreshWarbandOverviewButton()
    if not self.frame or not self.frame.sidebarOverviewButton then return end
    Widgets:SetButtonActive(
        self.frame.sidebarOverviewButton,
        self.warbandOverviewOpen == true
    )
end

function Shell:RefreshMythicPlusOverviewButton()
    local screen = self.activeScreenID == "mythicplus" and self.activeScreen
        or (Addon.ScreenRegistry.instances and Addon.ScreenRegistry.instances.mythicplus)
    if screen and screen.overviewButton then
        Widgets:SetButtonActive(screen.overviewButton, self.mythicPlusOverviewOpen == true)
    end
end

function Shell:CreateSidebar(frame)
    frame.sidebar = Widgets:CreatePanel(frame.body, "sidebar")
    frame.sidebar:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -12)
    frame.sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    frame.sidebar:SetWidth(Dimensions.sidebarWidth)

    frame.sidebarTitle = Widgets:CreateLabel(frame.sidebar, "GameFontNormalLarge", "LEFT")
    frame.sidebarTitle:SetPoint("TOPLEFT", 16, -16)
    frame.sidebarTitle:SetPoint("TOPRIGHT", -130, -16)
    frame.sidebarTitle:SetText(L.SIDEBAR_TITLE)

    frame.sidebarSettingsButton = Widgets:CreateSimpleGoldButton(
        frame.sidebar,
        "",
        24,
        24,
        Assets.cardInset
    )
    frame.sidebarSettingsButton:SetPoint("TOPRIGHT", -14, -13)
    frame.sidebarSettingsButton.icon = frame.sidebarSettingsButton:CreateTexture(nil, "ARTWORK")
    frame.sidebarSettingsButton.icon:SetSize(15, 15)
    frame.sidebarSettingsButton.icon:SetPoint("CENTER", 0, 0)
    if type(frame.sidebarSettingsButton.icon.SetAtlas) == "function" then
        frame.sidebarSettingsButton.icon:SetAtlas("optionsicon-brown")
    else
        frame.sidebarSettingsButton.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    frame.sidebarSettingsButton.newBadge = Widgets:CreateLabel(
        frame.sidebarSettingsButton,
        "GameFontNormalSmall",
        "CENTER"
    )
    frame.sidebarSettingsButton.newBadge:SetPoint(
        "BOTTOM",
        frame.sidebarSettingsButton,
        "TOP",
        0,
        0
    )
    frame.sidebarSettingsButton.newBadge:SetWidth(42)
    frame.sidebarSettingsButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.sidebarSettingsButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.sidebarSettingsButton.newBadge:Hide()

    frame.sidebarOverviewButton = Widgets:CreateSimpleGoldButton(
        frame.sidebar,
        "",
        24,
        24,
        Assets.cardInset
    )
    frame.sidebarOverviewButton:SetPoint(
        "RIGHT",
        frame.sidebarSettingsButton,
        "LEFT",
        -6,
        0
    )
    frame.sidebarOverviewButton.expandLines = {}
    local expandSegments = {
        { "TOPRIGHT", -5, -5, 8, 2 },
        { "TOPRIGHT", -5, -5, 2, 8 },
        { "BOTTOMLEFT", 5, 5, 8, 2 },
        { "BOTTOMLEFT", 5, 5, 2, 8 },
    }
    for index, segment in ipairs(expandSegments) do
        local line = frame.sidebarOverviewButton:CreateTexture(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetPoint(segment[1], segment[2], segment[3])
        line:SetSize(segment[4], segment[5])
        line:SetVertexColor(
            Theme.colors.gold[1],
            Theme.colors.gold[2],
            Theme.colors.gold[3],
            0.96
        )
        frame.sidebarOverviewButton.expandLines[index] = line
    end
    frame.sidebarOverviewButton:SetScript("OnClick", function()
        Shell:ToggleWarbandOverview()
    end)
    frame.sidebarOverviewButton:HookScript("OnEnter", function(selfButton)
        if GameTooltip then
            GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.WARBAND_OVERVIEW_TITLE, unpackColor(Theme.colors.gold))
            GameTooltip:AddLine(L.WARBAND_OVERVIEW_OPEN, 0.82, 0.78, 0.68, true)
            GameTooltip:Show()
        end
    end)
    frame.sidebarOverviewButton:HookScript("OnLeave", function()
        hideGameTooltip()
    end)

    frame.sidebarRewardSummary = VaultRewardBadge:CreateSummary(frame.sidebar, function()
        Shell:OpenWarbandOverview()
        local panel = Shell.frame and Shell.frame.warbandOverviewPanel
        if panel then
            panel.statusFilter = "reward"
            panel:Refresh()
        end
    end)
    frame.sidebarRewardSummary:SetPoint(
        "RIGHT",
        frame.sidebarOverviewButton,
        "LEFT",
        -6,
        0
    )

    frame.sidebarSubtitle = Widgets:CreateLabel(frame.sidebar, "GameFontHighlightSmall", "LEFT")
    frame.sidebarSubtitle:SetPoint("TOPLEFT", frame.sidebarTitle, "BOTTOMLEFT", 0, -8)
    frame.sidebarSubtitle:SetPoint("TOPRIGHT", -16, -8)
    frame.sidebarSubtitle:SetText(L.SIDEBAR_SUBTITLE)

    frame.sidebarCurrent = Widgets:CreateButton(frame.sidebar, "", 236, 82, "row")
    frame.sidebarCurrent:SetPoint("TOPLEFT", frame.sidebarSubtitle, "BOTTOMLEFT", 0, -12)
    frame.sidebarCurrent:SetPoint("TOPRIGHT", -16, -12)
    frame.sidebarCurrent:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.sidebarCurrent.label:Hide()

    frame.sidebarCurrent.specializationBackground = frame.sidebarCurrent:CreateTexture(
        nil,
        "ARTWORK",
        nil,
        -8
    )
    frame.sidebarCurrent.specializationBackground:SetPoint("TOPLEFT", 2, -2)
    frame.sidebarCurrent.specializationBackground:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.sidebarCurrent.specializationBackground:Hide()

    frame.sidebarCurrent.iconBackplate = frame.sidebarCurrent:CreateTexture(nil, "ARTWORK")
    frame.sidebarCurrent.iconBackplate:SetSize(59, 59)
    frame.sidebarCurrent.iconBackplate:SetPoint("LEFT", 15, 0)
    frame.sidebarCurrent.iconBackplate:SetColorTexture(1, 1, 1, 1)
    frame.sidebarCurrent.iconBackplateMask = addCircularMask(
        frame.sidebarCurrent,
        frame.sidebarCurrent.iconBackplate
    )
    frame.sidebarCurrent.classIcon = frame.sidebarCurrent:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.sidebarCurrent.classIcon:SetSize(53, 53)
    frame.sidebarCurrent.classIcon:SetPoint("CENTER", frame.sidebarCurrent.iconBackplate, "CENTER", 0, 0)
    frame.sidebarCurrent.classMask = addCircularMask(frame.sidebarCurrent, frame.sidebarCurrent.classIcon)
    frame.sidebarCurrent.rewardBadge = VaultRewardBadge:Create(frame.sidebarCurrent, 19)
    frame.sidebarCurrent.rewardBadge:SetPoint(
        "BOTTOMRIGHT",
        frame.sidebarCurrent.iconBackplate,
        "BOTTOMRIGHT",
        3,
        -3
    )

    frame.sidebarCurrent.caption = Widgets:CreateLabel(frame.sidebarCurrent, "GameFontHighlightSmall", "LEFT")
    frame.sidebarCurrent.caption:SetPoint("TOPLEFT", 84, -15)
    frame.sidebarCurrent.caption:SetPoint("TOPRIGHT", -14, -15)
    frame.sidebarCurrent.caption:SetHeight(14)
    frame.sidebarCurrent.caption:SetText(L.SIDEBAR_CURRENT)
    frame.sidebarCurrent.caption:SetTextColor(unpackColor(Theme.colors.parchment))

    frame.sidebarCurrent.name = Widgets:CreateLabel(frame.sidebarCurrent, "GameFontNormalLarge", "LEFT")
    frame.sidebarCurrent.name:SetPoint("TOPLEFT", frame.sidebarCurrent.caption, "BOTTOMLEFT", 0, -5)
    frame.sidebarCurrent.name:SetSize(142, 18)
    frame.sidebarCurrent.name:SetWordWrap(false)
    frame.sidebarCurrent.name:SetMaxLines(1)

    createSidebarMetaLabels(frame.sidebarCurrent)
    frame.sidebarCurrent.realm = Widgets:CreateLabel(frame.sidebarCurrent, "GameFontHighlightSmall", "LEFT")
    frame.sidebarCurrent.realm:SetHeight(14)
    frame.sidebarCurrent.realm:SetWordWrap(false)
    frame.sidebarCurrent.realm:SetMaxLines(1)
    frame.sidebarCurrent.money = Widgets:CreateLabel(frame.sidebarCurrent, "GameFontHighlightSmall", "LEFT")
    frame.sidebarCurrent.money:SetHeight(14)
    frame.sidebarCurrent.money:Hide()
    frame.sidebarCurrent.professionFrame = CreateFrame("Frame", nil, frame.sidebarCurrent)
    frame.sidebarCurrent.professionFrame:SetSize(22, 22)
    frame.sidebarCurrent.professionFrame:Hide()
    frame.sidebarCurrent.professionButtons = {}
    frame.sidebarCurrent:SetScript("OnClick", function(selfButton, mouseButton)
        if mouseButton == "RightButton" then
            Addon.WarbandRoster:SetMain(selfButton.characterKey)
        else
            Addon.WarbandRoster:Select(selfButton.characterKey)
        end
        Shell:RefreshSidebar()
        Shell:RefreshCharacterContext()
    end)
    frame.sidebarCurrent.vaultStrip = createVaultStrip(frame.sidebarCurrent, 84)
    local currentCardEnter = frame.sidebarCurrent:GetScript("OnEnter")
    local currentCardLeave = frame.sidebarCurrent:GetScript("OnLeave")
    frame.sidebarCurrent:SetScript("OnEnter", function(selfButton)
        if currentCardEnter then currentCardEnter(selfButton) end
        local settings = Addon.WarbandRoster:GetSettings()
        if settings.fields.activityScore then showActivityScoreTooltip(selfButton, selfButton.characterKey) end
    end)
    frame.sidebarCurrent:SetScript("OnLeave", function(selfButton)
        if currentCardLeave then currentCardLeave(selfButton) end
        hideGameTooltip()
    end)

    frame.sidebarSortButton = Widgets:CreateButton(frame.sidebar, L.SIDEBAR_SORT_SHORT, 115, 24)
    frame.sidebarSortButton:SetPoint("TOPLEFT", frame.sidebarCurrent, "BOTTOMLEFT", 0, -8)
    frame.sidebarSortButton.newBadge = Widgets:CreateLabel(
        frame.sidebarSortButton,
        "GameFontNormalSmall",
        "RIGHT"
    )
    frame.sidebarSortButton.newBadge:SetPoint("TOPRIGHT", -3, -1)
    frame.sidebarSortButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.sidebarSortButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.sidebarVisibilityButton = Widgets:CreateButton(frame.sidebar, L.SIDEBAR_CHARACTERS_SHORT, 115, 24)
    frame.sidebarVisibilityButton:SetPoint("TOPRIGHT", frame.sidebarCurrent, "BOTTOMRIGHT", 0, -8)
    frame.sidebarSortButton:SetScript("OnClick", function() Shell:ToggleSidebarMenu("sort") end)
    frame.sidebarVisibilityButton:SetScript("OnClick", function() Shell:ToggleSidebarMenu("visibility") end)

    frame.sidebarSortMenu = Widgets:CreatePanel(frame.sidebar, "inset")
    frame.sidebarSortMenu:SetPoint("TOPLEFT", frame.sidebarSortButton, "BOTTOMLEFT", 0, -3)
    frame.sidebarSortMenu:SetSize(236, 64 + ((#SORT_OPTIONS + 1) * 25))
    frame.sidebarSortMenu:SetFrameLevel(frame.sidebar:GetFrameLevel() + 20)
    frame.sidebarManualOrderButton = Widgets:CreateButton(
        frame.sidebarSortMenu,
        L.SIDEBAR_SORT_MANUAL,
        224,
        24
    )
    frame.sidebarManualOrderButton:SetPoint("TOPLEFT", 6, -6)
    frame.sidebarManualOrderButton.newBadge = Widgets:CreateLabel(
        frame.sidebarManualOrderButton,
        "GameFontNormalSmall",
        "RIGHT"
    )
    frame.sidebarManualOrderButton.newBadge:SetPoint("TOPRIGHT", -5, -1)
    frame.sidebarManualOrderButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.sidebarManualOrderButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.sidebarManualOrderButton:SetScript("OnClick", function()
        Shell:MarkNewInterfaceSeen("warband_manual_order")
        Addon.WarbandRoster:SetSortMode(nil)
        frame.sidebarSortMenu:Hide()
        Shell:RefreshSidebar()
        Shell:OpenCharacterOrderDialog()
    end)
    frame.sidebarSortMenu.rows = {}
    for index, option in ipairs(SORT_OPTIONS) do
        local row = Widgets:CreateButton(frame.sidebarSortMenu, option.label(), 224, 24)
        row:SetPoint("TOPLEFT", 6, -31 - ((index - 1) * 25))
        row.sortKey = option.key
        row:SetScript("OnClick", function(selfButton)
            Addon.WarbandRoster:SetSortMode(selfButton.sortKey)
            frame.sidebarSortMenu:Hide()
            Shell:RefreshSidebar()
        end)
        frame.sidebarSortMenu.rows[index] = row
    end
    frame.sidebarSortRealmLabel = Widgets:CreateLabel(frame.sidebarSortMenu, "GameFontHighlightSmall", "LEFT")
    frame.sidebarSortRealmLabel:SetPoint("TOPLEFT", 8, -10 - ((#SORT_OPTIONS + 1) * 25))
    frame.sidebarSortRealmLabel:SetText(L.SIDEBAR_REALM_FILTER)
    frame.sidebarRealmButton = Widgets:CreateButton(frame.sidebarSortMenu, "", 220, 24)
    frame.sidebarRealmButton:SetPoint("TOPLEFT", frame.sidebarSortRealmLabel, "BOTTOMLEFT", 0, -6)
    frame.sidebarRealmButton:SetScript("OnClick", function()
        Addon.WarbandRoster:CycleRealmFilter()
        Shell:RefreshWarbandSettings()
        Shell:RefreshSidebar()
        Shell:RefreshCharacterContext()
    end)
    frame.sidebarSortMenu:Hide()

    frame.sidebarVisibilityMenu = Widgets:CreatePanel(frame.sidebar, "inset")
    frame.sidebarVisibilityMenu:SetPoint("TOPRIGHT", frame.sidebarVisibilityButton, "BOTTOMRIGHT", 0, -3)
    frame.sidebarVisibilityMenu:SetSize(236, 80)
    frame.sidebarVisibilityMenu:SetFrameLevel(frame.sidebar:GetFrameLevel() + 20)
    frame.sidebarVisibilityScroll = CreateFrame("ScrollFrame", nil, frame.sidebarVisibilityMenu, "UIPanelScrollFrameTemplate")
    frame.sidebarVisibilityScroll:SetPoint("TOPLEFT", 6, -6)
    frame.sidebarVisibilityScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    frame.sidebarVisibilityScroll:EnableMouseWheel(true)
    frame.sidebarVisibilityList = CreateFrame("Frame", nil, frame.sidebarVisibilityScroll)
    frame.sidebarVisibilityList:SetSize(190, 10)
    frame.sidebarVisibilityScroll:SetScrollChild(frame.sidebarVisibilityList)
    frame.sidebarVisibilityScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * 25)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)
    ScrollFrames:Style(frame.sidebarVisibilityScroll)
    frame.sidebarVisibilityMenu:Hide()

    frame.sidebarSettingsMenu = Widgets:CreatePanel(frame, "card")
    frame.sidebarSettingsMenu:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.sidebarSettingsMenu:SetSize(360, 330)
    frame.sidebarSettingsMenu:SetFrameStrata("DIALOG")
    frame.sidebarSettingsMenu:SetFrameLevel(frame:GetFrameLevel() + 50)
    frame.sidebarSettingsMenu:SetMovable(true)
    frame.sidebarSettingsMenu:EnableMouse(true)
    frame.sidebarSettingsMenu:SetClampedToScreen(true)
    Widgets:ApplyStandardGoldFrame(frame.sidebarSettingsMenu, Assets.menuPlate)

    frame.sidebarSettingsTitleBar = CreateFrame("Frame", nil, frame.sidebarSettingsMenu)
    frame.sidebarSettingsTitleBar:SetPoint("TOPLEFT", 16, -12)
    frame.sidebarSettingsTitleBar:SetPoint("TOPRIGHT", -16, -12)
    frame.sidebarSettingsTitleBar:SetHeight(28)
    frame.sidebarSettingsTitleBar:EnableMouse(true)
    frame.sidebarSettingsTitleBar:RegisterForDrag("LeftButton")
    frame.sidebarSettingsTitleBar:SetScript("OnDragStart", function()
        frame.sidebarSettingsMenu:StartMoving()
    end)
    frame.sidebarSettingsTitleBar:SetScript("OnDragStop", function()
        frame.sidebarSettingsMenu:StopMovingOrSizing()
    end)
    frame.sidebarSettingsDivider = frame.sidebarSettingsTitleBar:CreateTexture(nil, "OVERLAY")
    frame.sidebarSettingsDivider:SetPoint("BOTTOMLEFT", 8, 0)
    frame.sidebarSettingsDivider:SetPoint("BOTTOMRIGHT", -8, 0)
    frame.sidebarSettingsDivider:SetHeight(1)
    frame.sidebarSettingsDivider:SetColorTexture(unpackColor(Theme.colors.goldDim))

    frame.sidebarSettingsTitle = Widgets:CreateLabel(frame.sidebarSettingsTitleBar, "GameFontNormalLarge", "LEFT")
    frame.sidebarSettingsTitle:SetPoint("LEFT", 12, 0)
    frame.sidebarSettingsTitle:SetPoint("RIGHT", -50, 0)
    frame.sidebarSettingsTitle:SetText(L.SIDEBAR_SETTINGS_TITLE)
    frame.sidebarSettingsTitle:SetTextColor(unpackColor(Theme.colors.gold))
    frame.sidebarSettingsCloseButton = Widgets:CreateButton(frame.sidebarSettingsTitleBar, "X", 26, 24)
    frame.sidebarSettingsCloseButton:SetPoint("RIGHT", -8, 0)
    frame.sidebarSettingsCloseButton:SetScript("OnClick", function()
        frame.sidebarSettingsMenu:Hide()
        frame.sidebarDeleteConfirm:Hide()
    end)

    frame.sidebarFieldsLabel = Widgets:CreateLabel(frame.sidebarSettingsMenu, "GameFontHighlightSmall", "LEFT")
    frame.sidebarFieldsLabel:SetPoint("TOPLEFT", 16, -52)
    frame.sidebarFieldsLabel:SetText(L.SIDEBAR_CARD_FIELDS)
    local fieldDefinitions = {
        { key = "level", label = L.SIDEBAR_FIELD_LEVEL },
        { key = "itemLevel", label = L.SIDEBAR_FIELD_ITEM_LEVEL },
        { key = "activityScore", label = L.SIDEBAR_FIELD_ACTIVITY_SCORE },
        { key = "gold", label = L.SIDEBAR_FIELD_GOLD },
        { key = "realm", label = L.SIDEBAR_FIELD_REALM },
        { key = "professions", label = L.SIDEBAR_FIELD_PROFESSIONS },
        { key = "vault", label = L.SIDEBAR_FIELD_VAULT },
        { key = "specializationArt", label = L.SIDEBAR_FIELD_SPECIALIZATION_ART },
    }
    frame.warbandFieldButtons = {}
    for index, definition in ipairs(fieldDefinitions) do
        local button = Widgets:CreateButton(frame.sidebarSettingsMenu, definition.label, 156, 24)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        button:SetPoint("TOPLEFT", frame.sidebarFieldsLabel, "BOTTOMLEFT", column * 166, -7 - (row * 28))
        button.fieldKey = definition.key
        if definition.key == "specializationArt" then
            button.newBadge = Widgets:CreateLabel(button, "GameFontNormalSmall", "RIGHT")
            button.newBadge:SetPoint("TOPRIGHT", -3, -1)
            button.newBadge:SetText(L.OPTIONS_NEW_BADGE)
            button.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
            button.newBadge:Hide()
        end
        button:SetScript("OnClick", function(selfButton)
            if selfButton.fieldKey == "specializationArt" then
                Shell:MarkNewInterfaceSeen("warband_specialization_art")
            end
            local settings = Addon.WarbandRoster:GetSettings()
            Addon.WarbandRoster:SetCardField(selfButton.fieldKey, not settings.fields[selfButton.fieldKey])
            Shell:RefreshWarbandSettings()
            Shell:RefreshSidebar()
            Shell:RefreshWarbandOverview()
        end)
        frame.warbandFieldButtons[definition.key] = button
    end

    frame.sidebarManagementLabel = Widgets:CreateLabel(frame.sidebarSettingsMenu, "GameFontHighlightSmall", "LEFT")
    frame.sidebarManagementLabel:SetPoint("TOPLEFT", frame.warbandFieldButtons.vault, "BOTTOMLEFT", 0, -14)
    frame.sidebarManagementLabel:SetText(L.SIDEBAR_MANAGEMENT)
    frame.sidebarShowAllButton = Widgets:CreateButton(frame.sidebarSettingsMenu, L.SIDEBAR_SHOW_ALL, 156, 24)
    frame.sidebarShowAllButton:SetPoint("TOPLEFT", frame.sidebarManagementLabel, "BOTTOMLEFT", 0, -7)
    frame.sidebarDeleteButton = Widgets:CreateButton(frame.sidebarSettingsMenu, L.SIDEBAR_DELETE_SELECTED, 156, 24)
    frame.sidebarDeleteButton:SetPoint("LEFT", frame.sidebarShowAllButton, "RIGHT", 10, 0)
    frame.sidebarShowAllButton:SetScript("OnClick", function()
        Addon.WarbandRoster:ClearHidden()
        Shell:RefreshWarbandSettings()
        Shell:RefreshSidebar()
    end)

    frame.sidebarSettingsStatus = Widgets:CreateLabel(frame.sidebarSettingsMenu, "GameFontDisableSmall", "LEFT")
    frame.sidebarSettingsStatus:SetPoint("TOPLEFT", frame.sidebarShowAllButton, "BOTTOMLEFT", 0, -10)
    frame.sidebarSettingsStatus:SetPoint("TOPRIGHT", -12, 0)
    frame.sidebarSettingsStatus:SetWordWrap(true)
    frame.sidebarSettingsStatus:SetText("")

    frame.sidebarDeleteConfirm = Widgets:CreatePanel(frame.sidebarSettingsMenu, "cardInset")
    frame.sidebarDeleteConfirm:SetPoint("BOTTOMLEFT", 10, 10)
    frame.sidebarDeleteConfirm:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.sidebarDeleteConfirm:SetHeight(76)
    frame.sidebarDeleteConfirm.message = Widgets:CreateLabel(frame.sidebarDeleteConfirm, "GameFontHighlightSmall", "LEFT")
    frame.sidebarDeleteConfirm.message:SetPoint("TOPLEFT", 8, -8)
    frame.sidebarDeleteConfirm.message:SetPoint("TOPRIGHT", -8, -8)
    frame.sidebarDeleteConfirm.message:SetWordWrap(true)
    frame.sidebarDeleteConfirm.delete = Widgets:CreateButton(frame.sidebarDeleteConfirm, L.SIDEBAR_DELETE, 136, 22)
    frame.sidebarDeleteConfirm.delete:SetPoint("BOTTOMLEFT", 8, 7)
    frame.sidebarDeleteConfirm.cancel = Widgets:CreateButton(frame.sidebarDeleteConfirm, L.SIDEBAR_CANCEL, 136, 22)
    frame.sidebarDeleteConfirm.cancel:SetPoint("BOTTOMRIGHT", -8, 7)
    frame.sidebarDeleteConfirm.cancel:SetScript("OnClick", function()
        frame.sidebarDeleteConfirm:Hide()
    end)
    frame.sidebarDeleteConfirm.delete:SetScript("OnClick", function()
        local characterKey = frame.sidebarDeleteConfirm.characterKey
        frame.sidebarDeleteConfirm:Hide()
        if characterKey then
            Addon.WarbandRoster:Delete(characterKey)
            Shell:RefreshWarbandSettings()
            Shell:RefreshSidebar()
            Shell:RefreshCharacterContext()
        end
    end)
    frame.sidebarDeleteConfirm:Hide()
    frame.sidebarDeleteButton:SetScript("OnClick", function()
        local selected = Addon.WarbandRoster:GetSelected()
        if not selected or Addon.WarbandRoster:IsCurrent(selected.key) then
            frame.sidebarSettingsStatus:SetText(L.SIDEBAR_DELETE_CURRENT)
            frame.sidebarDeleteConfirm:Hide()
            return
        end
        frame.sidebarSettingsStatus:SetText("")
        frame.sidebarDeleteConfirm.characterKey = selected.key
        frame.sidebarDeleteConfirm.message:SetText(string.format(L.SIDEBAR_DELETE_CONFIRM, selected.name or selected.key))
        frame.sidebarDeleteConfirm:Show()
    end)
    frame.sidebarSettingsMenu:Hide()
    frame.sidebarSettingsButton:SetScript("OnClick", function()
        Shell:ToggleSidebarMenu("settings")
    end)

    frame.sidebarScroll = CreateFrame("ScrollFrame", nil, frame.sidebar, "UIPanelScrollFrameTemplate")
    frame.sidebarScroll:SetPoint("TOPLEFT", frame.sidebarSortButton, "BOTTOMLEFT", 0, -10)
    frame.sidebarScroll:SetPoint("BOTTOMRIGHT", -24, 16)
    frame.sidebarScroll:EnableMouseWheel(true)
    frame.sidebarList = CreateFrame("Frame", nil, frame.sidebarScroll)
    frame.sidebarList:SetSize(212, 10)
    frame.sidebarScroll:SetScrollChild(frame.sidebarList)
    frame.sidebarScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * 42)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)
    ScrollFrames:Style(frame.sidebarScroll)

    frame.sidebarEmpty = Widgets:CreateLabel(frame.sidebarList, "GameFontDisable", "LEFT")
    frame.sidebarEmpty:SetPoint("TOPLEFT", 0, 0)
    frame.sidebarEmpty:SetPoint("TOPRIGHT", 0, 0)
    frame.sidebarEmpty:SetText(L.NO_CHARACTERS)
end

function Shell:ToggleSidebarMenu(menuName)
    local sortMenu = self.frame and self.frame.sidebarSortMenu
    local visibilityMenu = self.frame and self.frame.sidebarVisibilityMenu
    local settingsMenu = self.frame and self.frame.sidebarSettingsMenu
    if not sortMenu or not visibilityMenu or not settingsMenu then
        return
    end
    if self.frame.utilitySettingsMenu then self.frame.utilitySettingsMenu:Hide() end
    if self.frame.utilitySettingsButton then
        Widgets:SetButtonActive(self.frame.utilitySettingsButton, false)
    end
    local targetMenu = menuName == "sort" and sortMenu
        or menuName == "visibility" and visibilityMenu or settingsMenu
    local wasShown = targetMenu:IsShown()
    if menuName == "sort" then
        visibilityMenu:Hide()
        settingsMenu:Hide()
        if self.frame.sidebarDeleteConfirm then self.frame.sidebarDeleteConfirm:Hide() end
        sortMenu:SetShown(not sortMenu:IsShown())
    elseif menuName == "visibility" then
        sortMenu:Hide()
        settingsMenu:Hide()
        if self.frame.sidebarDeleteConfirm then self.frame.sidebarDeleteConfirm:Hide() end
        visibilityMenu:SetShown(not visibilityMenu:IsShown())
    else
        sortMenu:Hide()
        visibilityMenu:Hide()
        local showSettings = not settingsMenu:IsShown()
        if showSettings then
            settingsMenu:ClearAllPoints()
            settingsMenu:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        end
        settingsMenu:SetShown(showSettings)
        if showSettings then
            settingsMenu:Raise()
            self:RefreshWarbandSettings()
        elseif self.frame.sidebarDeleteConfirm then
            self.frame.sidebarDeleteConfirm:Hide()
        end
    end
    if Addon.Sound then
        Addon.Sound:Play(wasShown and "menuClose" or "menuOpen")
    end
end

function Shell:CloseSidebarMenus()
    if not self.frame then return end
    if self.frame.sidebarSortMenu then self.frame.sidebarSortMenu:Hide() end
    if self.frame.sidebarVisibilityMenu then self.frame.sidebarVisibilityMenu:Hide() end
    if self.frame.sidebarSettingsMenu then self.frame.sidebarSettingsMenu:Hide() end
    if self.frame.sidebarDeleteConfirm then self.frame.sidebarDeleteConfirm:Hide() end
    if self.frame.utilitySettingsMenu then self.frame.utilitySettingsMenu:Hide() end
    if self.frame.utilitySettingsButton then
        Widgets:SetButtonActive(self.frame.utilitySettingsButton, false)
    end
end

function Shell:CreateUtility(frame)
    frame.utility = Widgets:CreatePanel(frame.body, "utility")
    frame.utility:SetPoint("TOPRIGHT", frame.tabBar, "BOTTOMRIGHT", 0, -12)
    frame.utility:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.utility:SetWidth(Dimensions.utilityWidth)

    frame.utilityStandard = CreateFrame("Frame", nil, frame.utility)
    frame.utilityStandard:SetAllPoints(frame.utility)

    frame.utilitySettingsButton = Widgets:CreateSimpleGoldButton(
        frame.utilityStandard,
        "",
        24,
        24,
        Assets.cardInset
    )
    frame.utilitySettingsButton:SetPoint("TOPRIGHT", -14, -13)
    frame.utilitySettingsButton.icon = frame.utilitySettingsButton:CreateTexture(nil, "ARTWORK")
    frame.utilitySettingsButton.icon:SetSize(15, 15)
    frame.utilitySettingsButton.icon:SetPoint("CENTER", 0, 0)
    if type(frame.utilitySettingsButton.icon.SetAtlas) == "function" then
        frame.utilitySettingsButton.icon:SetAtlas("optionsicon-brown")
    else
        frame.utilitySettingsButton.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    frame.utilitySettingsButton.newBadge = Widgets:CreateLabel(
        frame.utilitySettingsButton,
        "GameFontNormalSmall",
        "CENTER"
    )
    frame.utilitySettingsButton.newBadge:SetPoint(
        "BOTTOM",
        frame.utilitySettingsButton,
        "TOP",
        0,
        0
    )
    frame.utilitySettingsButton.newBadge:SetWidth(42)
    frame.utilitySettingsButton.newBadge:SetText(L.OPTIONS_NEW_BADGE)
    frame.utilitySettingsButton.newBadge:SetTextColor(unpackColor(Theme.colors.gold))
    frame.utilitySettingsButton.newBadge:Hide()
    frame.utilitySettingsButton:SetScript("OnEnter", function(selfButton)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(L.UTILITY_SETTINGS_TITLE, 1.00, 0.82, 0.18)
        GameTooltip:AddLine(L.UTILITY_SETTINGS_TOOLTIP, 0.82, 0.78, 0.66, true)
        GameTooltip:Show()
    end)
    frame.utilitySettingsButton:SetScript("OnLeave", hideGameTooltip)

    frame.utilityUpgradeHeader = createUtilitySectionTitle(frame.utilityStandard, L.UPGRADE_SECTION)
    frame.utilityUpgradeHeader:SetPoint("TOPLEFT", frame.utilityStandard, "TOPLEFT", 16, -19)
    frame.utilityUpgradeHeader:SetPoint("TOPRIGHT", frame.utilityStandard, "TOPRIGHT", -48, -19)

    frame.utilityUpgradePanel = Widgets:CreatePanel(frame.utilityStandard, "inset")
    frame.utilityUpgradePanel:SetPoint("TOPLEFT", frame.utilityUpgradeHeader, "BOTTOMLEFT", 0, -6)
    frame.utilityUpgradePanel:SetPoint("TOPRIGHT", frame.utilityStandard, "TOPRIGHT", -16, -6)
    frame.utilityUpgradePanel:SetHeight(72)
    frame.utilityUpgradeButtons = {}

    for index = 1, #(Addon.Data.MID_UTILITY_UPGRADE_CRESTS or {}) do
        local button = createUtilityCurrencyButton(frame.utilityUpgradePanel)
        frame.utilityUpgradeButtons[index] = button
    end
    layoutUtilityCurrencyButtons(frame.utilityUpgradePanel, frame.utilityUpgradeButtons)

    frame.utilityPvpHeader = createUtilitySectionTitle(frame.utilityStandard, L.PVP_CURRENCY_SECTION)
    frame.utilityPvpHeader:SetPoint("TOPLEFT", frame.utilityUpgradePanel, "BOTTOMLEFT", 0, -12)
    frame.utilityPvpHeader:SetPoint("TOPRIGHT", frame.utilityUpgradePanel, "BOTTOMRIGHT", 0, -12)

    frame.utilityPvpPanel = Widgets:CreatePanel(frame.utilityStandard, "inset")
    frame.utilityPvpPanel:SetPoint("TOPLEFT", frame.utilityPvpHeader, "BOTTOMLEFT", 0, -6)
    frame.utilityPvpPanel:SetPoint("TOPRIGHT", frame.utilityPvpHeader, "BOTTOMRIGHT", 0, -6)
    frame.utilityPvpPanel:SetHeight(72)
    frame.utilityPvpButtons = {}
    for index = 1, #(Addon.Data.MID_UTILITY_PVP_CURRENCIES or {}) do
        frame.utilityPvpButtons[index] = createUtilityCurrencyButton(frame.utilityPvpPanel)
    end
    layoutUtilityCurrencyButtons(frame.utilityPvpPanel, frame.utilityPvpButtons)

    frame.utilityResourceHeader = createUtilitySectionTitle(frame.utilityStandard, L.RESOURCE_SECTION)
    frame.utilityResourceHeader:SetPoint("TOPLEFT", frame.utilityPvpPanel, "BOTTOMLEFT", 0, -12)
    frame.utilityResourceHeader:SetPoint("TOPRIGHT", frame.utilityPvpPanel, "BOTTOMRIGHT", 0, -12)

    frame.utilityResourcePanel = Widgets:CreatePanel(frame.utilityStandard, "inset")
    frame.utilityResourcePanel:SetPoint("TOPLEFT", frame.utilityResourceHeader, "BOTTOMLEFT", 0, -6)
    frame.utilityResourcePanel:SetPoint("BOTTOMRIGHT", frame.utilityStandard, "BOTTOMRIGHT", -16, 16)

    frame.utilityResourceScroll = CreateFrame("ScrollFrame", nil, frame.utilityResourcePanel, "UIPanelScrollFrameTemplate")
    frame.utilityResourceScroll:SetPoint("TOPLEFT", 14, -10)
    frame.utilityResourceScroll:SetPoint("BOTTOMRIGHT", -26, 10)
    frame.utilityResourceScroll:EnableMouseWheel(true)
    frame.utilityResourceList = CreateFrame("Frame", nil, frame.utilityResourceScroll)
    frame.utilityResourceList:SetSize(216, 10)
    frame.utilityResourceScroll:SetScrollChild(frame.utilityResourceList)
    frame.utilityResourceScroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local nextValue = selfScroll:GetVerticalScroll() - (delta * UTILITY_RESOURCE_ROW_STRIDE)
        selfScroll:SetVerticalScroll(math.max(0, math.min(selfScroll:GetVerticalScrollRange(), nextValue)))
    end)
    ScrollFrames:Style(frame.utilityResourceScroll)

    frame.utilityResourceRows = {}
    function frame:EnsureUtilityResourceRows(total)
        total = math.max(0, math.floor(tonumber(total) or 0))
        while #self.utilityResourceRows < total do
            local index = #self.utilityResourceRows + 1
            local row = Widgets:CreateButton(
                self.utilityResourceList,
                "",
                216,
                UTILITY_RESOURCE_ROW_HEIGHT,
                "row"
            )
            row:SetPoint("TOPLEFT", 0, -((index - 1) * UTILITY_RESOURCE_ROW_STRIDE))
            row:SetPoint("TOPRIGHT", 0, -((index - 1) * UTILITY_RESOURCE_ROW_STRIDE))
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.label:Hide()
            row.name = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
            row.name:SetPoint("LEFT", 9, 0)
            row.name:SetPoint("RIGHT", -88, 0)
            if type(row.name.SetWordWrap) == "function" then row.name:SetWordWrap(false) end
            row.value = Widgets:CreateLabel(row, "GameFontNormalSmall", "RIGHT")
            row.value:SetPoint("RIGHT", -32, 0)
            row.value:SetWidth(52)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("RIGHT", -8, 0)
            row.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            row.iconMask = Widgets:AddRoundedIconMask(row, row.icon)
            if row.iconMask then
                row.iconMask:ClearAllPoints()
                row.iconMask:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 1, -1)
                row.iconMask:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
            end
            row.iconQualityBorder = Widgets:CreateRoundedIconBorder(
                row,
                row.icon,
                0,
                Theme.colors.goldDim
            )
            row.iconQualityBorder:ClearAllPoints()
            row.iconQualityBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 1, -1)
            row.iconQualityBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
            row:SetScript("OnEnter", function(selfRow)
                showUtilityTooltip(selfRow, selfRow.currencyID, selfRow.itemID, L.RESOURCE_HIDE_HINT)
            end)
            row:SetScript("OnLeave", hideGameTooltip)
            row:SetScript("OnClick", function(selfRow, mouseButton)
                hideGameTooltip()
                if mouseButton == "RightButton" then
                    Addon.UtilityResources:OpenCurrencyTab()
                elseif mouseButton == "LeftButton" and selfRow.entryKey then
                    Addon.UtilityResources:SetHidden(selfRow.entryKey, true)
                end
            end)
            self.utilityResourceRows[index] = row
        end
        return #self.utilityResourceRows
    end
    frame:EnsureUtilityResourceRows(#(Addon.Data.MID_UTILITY_RESOURCE_ENTRIES or {}))

    frame.utilitySettingsMenu = Widgets:CreatePanel(frame, "card")
    frame.utilitySettingsMenu:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.utilitySettingsMenu:SetSize(360, 230)
    frame.utilitySettingsMenu:SetFrameStrata("DIALOG")
    frame.utilitySettingsMenu:SetFrameLevel(frame:GetFrameLevel() + 50)
    frame.utilitySettingsMenu:SetMovable(true)
    frame.utilitySettingsMenu:EnableMouse(true)
    frame.utilitySettingsMenu:SetClampedToScreen(true)
    Widgets:ApplyStandardGoldFrame(frame.utilitySettingsMenu, Assets.menuPlate)

    frame.utilitySettingsTitleBar = CreateFrame("Frame", nil, frame.utilitySettingsMenu)
    frame.utilitySettingsTitleBar:SetPoint("TOPLEFT", 16, -12)
    frame.utilitySettingsTitleBar:SetPoint("TOPRIGHT", -16, -12)
    frame.utilitySettingsTitleBar:SetHeight(28)
    frame.utilitySettingsTitleBar:EnableMouse(true)
    frame.utilitySettingsTitleBar:RegisterForDrag("LeftButton")
    frame.utilitySettingsTitleBar:SetScript("OnDragStart", function()
        frame.utilitySettingsMenu:StartMoving()
    end)
    frame.utilitySettingsTitleBar:SetScript("OnDragStop", function()
        frame.utilitySettingsMenu:StopMovingOrSizing()
    end)
    frame.utilitySettingsDivider = frame.utilitySettingsTitleBar:CreateTexture(nil, "OVERLAY")
    frame.utilitySettingsDivider:SetPoint("BOTTOMLEFT", 8, 0)
    frame.utilitySettingsDivider:SetPoint("BOTTOMRIGHT", -8, 0)
    frame.utilitySettingsDivider:SetHeight(1)
    frame.utilitySettingsDivider:SetColorTexture(unpackColor(Theme.colors.goldDim))
    frame.utilitySettingsTitle = Widgets:CreateLabel(frame.utilitySettingsTitleBar, "GameFontNormalLarge", "LEFT")
    frame.utilitySettingsTitle:SetPoint("LEFT", 12, 0)
    frame.utilitySettingsTitle:SetPoint("RIGHT", -50, 0)
    frame.utilitySettingsTitle:SetText(L.UTILITY_SETTINGS_TITLE)
    frame.utilitySettingsTitle:SetTextColor(unpackColor(Theme.colors.gold))
    frame.utilitySettingsCloseButton = Widgets:CreateButton(frame.utilitySettingsTitleBar, "X", 26, 24)
    frame.utilitySettingsCloseButton:SetPoint("RIGHT", -8, 0)
    frame.utilitySettingsCloseButton:SetScript("OnClick", function()
        Shell:CloseSidebarMenus()
    end)

    frame.utilityUpgradeToggle = Widgets:CreateButton(
        frame.utilitySettingsMenu,
        L.UTILITY_SHOW_UPGRADES,
        310,
        26,
        "row"
    )
    frame.utilityUpgradeToggle:SetPoint("TOPLEFT", 24, -58)
    frame.utilityPvpToggle = Widgets:CreateButton(
        frame.utilitySettingsMenu,
        L.UTILITY_SHOW_PVP,
        310,
        26,
        "row"
    )
    frame.utilityPvpToggle:SetPoint("TOPLEFT", frame.utilityUpgradeToggle, "BOTTOMLEFT", 0, -8)
    frame.utilitySettingsHint = Widgets:CreateLabel(
        frame.utilitySettingsMenu,
        "GameFontHighlightSmall",
        "LEFT"
    )
    frame.utilitySettingsHint:SetPoint("TOPLEFT", frame.utilityPvpToggle, "BOTTOMLEFT", 2, -12)
    frame.utilitySettingsHint:SetPoint("TOPRIGHT", frame.utilityPvpToggle, "BOTTOMRIGHT", -2, -12)
    frame.utilitySettingsHint:SetWordWrap(true)
    frame.utilitySettingsHint:SetText(L.UTILITY_SECTION_SEPARATE_HINT)

    frame.utilitySettingsRestoreButton = Widgets:CreateButton(
        frame.utilitySettingsMenu,
        L.RESOURCE_SHOW_ALL,
        190,
        24
    )
    frame.utilitySettingsRestoreButton:SetPoint("BOTTOMLEFT", 24, 18)
    frame.utilitySettingsRestoreButton:SetScript("OnClick", function()
        Addon.UtilityResources:ClearHidden()
        Shell:RefreshUtilitySettings()
    end)
    frame.utilitySettingsRestoreButton:SetScript("OnEnter", function(selfButton)
        local hiddenCount = tonumber(selfButton.hiddenCount) or 0
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(hiddenCount > 0
            and string.format(L.RESOURCE_SHOW_ALL_TOOLTIP, hiddenCount)
            or L.RESOURCE_SHOW_ALL_TOOLTIP_NONE, 0.93, 0.89, 0.77, true)
        GameTooltip:Show()
    end)
    frame.utilitySettingsRestoreButton:SetScript("OnLeave", hideGameTooltip)
    frame.utilityUpgradeToggle:SetScript("OnClick", function()
        local settings = Addon.UtilityResources:GetSettings()
        Addon.UtilityResources:SetSectionVisible("upgrades", not settings.showUpgradeSection)
        Shell:RefreshUtilitySettings()
    end)
    frame.utilityPvpToggle:SetScript("OnClick", function()
        local settings = Addon.UtilityResources:GetSettings()
        Addon.UtilityResources:SetSectionVisible("pvp", not settings.showPvpSection)
        Shell:RefreshUtilitySettings()
    end)
    frame.utilitySettingsMenu:SetScript("OnHide", function()
        Widgets:SetButtonActive(frame.utilitySettingsButton, false)
    end)
    frame.utilitySettingsMenu:Hide()
    frame.utilitySettingsButton:SetScript("OnClick", function()
        if Shell:ToggleUtilitySettings() then
            Shell:MarkNewInterfaceSeen("utility_resource_settings")
        end
    end)
end

function Shell:RefreshUtilitySettings()
    local frame = self.frame
    if not frame or not frame.utilitySettingsMenu or not Addon.UtilityResources then return end
    local settings = Addon.UtilityResources:GetSettings()
    Widgets:SetButtonActive(frame.utilityUpgradeToggle, settings.showUpgradeSection == true)
    Widgets:SetButtonActive(frame.utilityPvpToggle, settings.showPvpSection == true)
    local hiddenCount = math.max(
        0,
        tonumber(frame.utilitySettingsRestoreButton.hiddenCount) or 0
    )
    frame.utilitySettingsRestoreButton.hiddenCount = hiddenCount
    frame.utilitySettingsRestoreButton.label:SetText(hiddenCount > 0
        and string.format(L.RESOURCE_SHOW_ALL_COUNT, hiddenCount) or L.RESOURCE_SHOW_ALL)
    Widgets:SetButtonActive(frame.utilitySettingsRestoreButton, hiddenCount > 0)
end

function Shell:ToggleUtilitySettings()
    local frame = self.frame
    if not frame or not frame.utilitySettingsMenu then return false end
    local wasShown = frame.utilitySettingsMenu:IsShown()
    self:CloseSidebarMenus()
    if not wasShown then
        frame.utilitySettingsMenu:ClearAllPoints()
        frame.utilitySettingsMenu:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.utilitySettingsMenu:Show()
        frame.utilitySettingsMenu:Raise()
        Widgets:SetButtonActive(frame.utilitySettingsButton, true)
        self:RefreshUtilitySettings()
    end
    if Addon.Sound then Addon.Sound:Play(wasShown and "menuClose" or "menuOpen") end
    return not wasShown
end

function Shell:CreateContent(frame)
    frame.content = Widgets:CreatePanel(frame.body, "content")
    frame.content:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", Dimensions.gap, 0)
    frame.content:SetPoint("BOTTOMRIGHT", frame.utility, "BOTTOMLEFT", -Dimensions.gap, 0)

    frame.hero = Widgets:CreatePanel(frame.content, "hero")
    frame.hero:SetPoint("TOPLEFT", 14, -14)
    frame.hero:SetPoint("TOPRIGHT", -14, -14)
    frame.hero:SetHeight(Dimensions.heroHeight)

    frame.heroPortraitBackplate = frame.hero:CreateTexture(nil, "ARTWORK")
    frame.heroPortraitBackplate:SetSize(70, 70)
    frame.heroPortraitBackplate:SetPoint("LEFT", 18, 0)
    frame.heroPortraitBackplate:SetColorTexture(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        1
    )
    frame.heroPortraitBackplateMask = addCircularMask(frame.hero, frame.heroPortraitBackplate)

    frame.heroPortrait = frame.hero:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.heroPortrait:SetSize(64, 64)
    frame.heroPortrait:SetPoint("CENTER", frame.heroPortraitBackplate, "CENTER", 0, 0)
    frame.heroPortraitMask = addCircularMask(frame.hero, frame.heroPortrait)

    frame.heroTitle = Widgets:CreateLabel(frame.hero, "GameFontNormalHuge", "LEFT")
    frame.heroTitle:SetPoint("TOPLEFT", frame.heroPortraitBackplate, "TOPRIGHT", 18, -2)
    frame.heroTitle:SetPoint("TOPRIGHT", -18, -2)

    frame.heroProfessionFrame = CreateFrame("Frame", nil, frame.hero)
    frame.heroProfessionFrame:SetPoint("TOPRIGHT", -18, -12)
    frame.heroProfessionFrame:SetSize(24, 24)
    frame.heroProfessionFrame:Hide()
    frame.heroProfessionButtons = {}

    frame.heroSubtitle = Widgets:CreateLabel(frame.hero, "GameFontHighlightSmall", "LEFT")
    frame.heroSubtitle:SetPoint("TOPLEFT", frame.heroTitle, "BOTTOMLEFT", 0, -8)
    frame.heroSubtitle:SetPoint("TOPRIGHT", -18, -8)

    frame.heroSync = Widgets:CreateLabel(frame.hero, "GameFontDisableSmall", "LEFT")
    frame.heroSync:SetPoint("TOPLEFT", frame.heroSubtitle, "BOTTOMLEFT", 0, -8)
    frame.heroSync:SetPoint("TOPRIGHT", -18, -8)

    frame.screenHost = CreateFrame("Frame", nil, frame.content)
    frame.screenHost:SetPoint("TOPLEFT", frame.hero, "BOTTOMLEFT", 14, -14)
    frame.screenHost:SetPoint("BOTTOMRIGHT", -14, 14)
end

function Shell:CreateWishlist(frame)
    if frame.wishlistPanel then
        return frame.wishlistPanel
    end
    frame.wishlistPanel = Addon.WishlistUI:Create(frame.body, {
        close = function()
            if Addon.Sound then Addon.Sound:Play("menuClose") end
            Shell:CloseWishlist(true)
        end,
        openSource = function(source, difficultyKey)
            Shell:OpenWishlistSource(source, difficultyKey)
        end,
        changed = function()
            Shell:RefreshWishlistButton()
        end,
    })
    frame.wishlistPanel:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", Dimensions.gap, 0)
    frame.wishlistPanel:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    return frame.wishlistPanel
end

function Shell:CreateOptions(frame)
    if frame.optionsPanel then
        return frame.optionsPanel
    end
    frame.optionsPanel = Addon.OptionsUI:Create(frame.body, {
        close = function()
            if Addon.Sound then Addon.Sound:Play("menuClose") end
            Shell:CloseOptions(true)
        end,
        getSettings = function()
            return Addon.Database:GetUI()
        end,
        setScale = function(value)
            return Shell:SetScale(value)
        end,
        setOpacity = function(value)
            return Shell:SetOpacity(value)
        end,
        resetDisplay = function()
            Shell:ResetDisplaySettings()
        end,
        resetPosition = function()
            Shell:ResetWindowPosition()
        end,
        getToggleBinding = function()
            return Shell:GetToggleBinding()
        end,
        formatToggleBinding = function(key)
            return Shell:FormatToggleBinding(key)
        end,
        setToggleBinding = function(key)
            return Shell:SetToggleBinding(key)
        end,
        clearToggleBinding = function()
            return Shell:ClearToggleBinding()
        end,
        isMinimapHidden = function()
            return Addon.MinimapLauncher and Addon.MinimapLauncher:IsHidden() or false
        end,
        setMinimapHidden = function(hidden)
            if Addon.MinimapLauncher then
                return Addon.MinimapLauncher:SetHidden(hidden)
            end
            return false
        end,
        resetMinimapPosition = function()
            if Addon.MinimapLauncher then
                return Addon.MinimapLauncher:ResetPosition()
            end
            return false
        end,
        areChatMessagesEnabled = function()
            return Addon:AreChatMessagesEnabled()
        end,
        setChatMessagesEnabled = function(enabled)
            return Addon:SetChatMessagesEnabled(enabled)
        end,
        areSoundsEnabled = function()
            return not Addon.Sound or Addon.Sound:IsEnabled()
        end,
        setSoundsEnabled = function(enabled)
            if not Addon.Sound then return false end
            local wasEnabled = Addon.Sound:IsEnabled()
            if wasEnabled and enabled ~= true then
                Addon.Sound:Play("toggleOff")
            end
            local result = Addon.Sound:SetEnabled(enabled)
            if not wasEnabled and result == true then
                Addon.Sound:Play("toggleOn")
            end
            return result
        end,
        previewSound = function()
            return Addon.Sound and Addon.Sound:Preview("tabSwitch") or false
        end,
        getDiscordURL = function()
            return Addon.Welcome and Addon.Welcome:GetDiscordURL() or ""
        end,
        showDiscordLink = function()
            return Addon.Welcome and Addon.Welcome:ShowDiscordLink() or false
        end,
        getLanguages = function()
            return Shell:GetLanguageOptions()
        end,
        getLanguage = function()
            return Shell:GetLanguagePreference()
        end,
        setLanguage = function(localeKey)
            return Shell:SetLanguagePreference(localeKey)
        end,
        reloadLanguage = function()
            return Shell:ReloadForLanguage()
        end,
        getScreens = function()
            return Addon.ScreenRegistry:GetDefinitions()
        end,
        isScreenVisible = function(screenID)
            return Shell:IsScreenVisible(screenID)
        end,
        setScreenVisible = function(screenID, visible)
            return Shell:SetScreenVisible(screenID, visible)
        end,
        showAllScreens = function()
            Shell:ShowAllScreens()
        end,
        markReleaseRead = function(version)
            Shell:MarkReleaseRead(version)
        end,
        hasUnreadReleaseNotes = function()
            return Shell:HasUnreadReleaseNotes()
        end,
        refreshOptionsButton = function()
            Shell:RefreshOptionsButton()
        end,
    })
    frame.optionsPanel:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -12)
    frame.optionsPanel:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    return frame.optionsPanel
end

function Shell:CreateFeatures(frame)
    if frame.featuresPanel then
        return frame.featuresPanel
    end
    frame.featuresPanel = Addon.FeaturesUI:Create(frame.body, {
        close = function()
            if Addon.Sound then Addon.Sound:Play("menuClose") end
            Shell:CloseFeatures(true)
        end,
        isFeatureNew = function(featureID)
            return Shell:IsFeatureNew(featureID)
        end,
        markFeatureSeen = function(featureID)
            return Shell:MarkFeatureSeen(featureID)
        end,
    })
    frame.featuresPanel:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", 0, -12)
    frame.featuresPanel:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    frame.featuresPanel:Hide()
    return frame.featuresPanel
end

function Shell:CreateCharacterOrderDialog(frame)
    if frame.characterOrderDialog then return frame.characterOrderDialog end
    frame.characterOrderDialog = Addon.CharacterOrderDialog:Create(frame, {
        getCharacters = function()
            return Addon.WarbandRoster:GetAll()
        end,
        getOrder = function()
            return Addon.WarbandRoster:GetManualOrder()
        end,
        isHidden = function(characterKey)
            return Addon.WarbandRoster:IsHidden(characterKey)
        end,
        save = function(order)
            local saved = Addon.WarbandRoster:SetManualOrder(order)
            if saved then
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
                Shell:RefreshWarbandOverview()
            end
            return saved == true
        end,
    })
    return frame.characterOrderDialog
end

function Shell:OpenCharacterOrderDialog()
    if not self.frame then self:CreateFrame() end
    if not self.frame or not Addon.CharacterOrderDialog then return false end
    self:CloseSidebarMenus()
    return self:CreateCharacterOrderDialog(self.frame):Open()
end

function Shell:CloseCharacterOrderDialog()
    local dialog = self.frame and self.frame.characterOrderDialog
    if not dialog or not dialog:IsShown() then return false end
    return dialog:Cancel()
end

function Shell:CreateWarbandOverview(frame)
    if frame.warbandOverviewPanel then return frame.warbandOverviewPanel end
    frame.warbandOverviewPanel = Addon.WarbandOverview:Create(UIParent, {
        close = function()
            Shell:CloseWarbandOverview()
        end,
        getPosition = function()
            return Addon.Database:GetUI().warbandOverview.window
        end,
        getLayoutMode = function()
            return Addon.Database:GetUI().warbandOverview.layoutMode
        end,
        setLayoutMode = function(layoutMode)
            local overview = Addon.Database:GetUI().warbandOverview
            overview.layoutMode = layoutMode == "cards" and "cards" or "compact"
            return true
        end,
        storePosition = function(overviewFrame)
            local point, _, relativePoint, x, y = overviewFrame:GetPoint(1)
            if not point then return false end
            local window = Addon.Database:GetUI().warbandOverview.window
            window.point = point
            window.relativePoint = relativePoint or point
            window.x = tonumber(x) or 0
            window.y = tonumber(y) or 0
            return true
        end,
        getCharacters = function()
            return Addon.WarbandRoster:GetAll()
        end,
        getCurrentKey = function()
            return Addon.WarbandRoster:GetCurrentKey()
        end,
        getSelectedKey = function()
            local selected = Addon.WarbandRoster:GetSelected()
            return selected and selected.key or nil
        end,
        isHidden = function(characterKey)
            return Addon.WarbandRoster:IsHidden(characterKey)
        end,
        select = function(characterKey)
            if Addon.WarbandRoster:Select(characterKey) then
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
                Shell:RefreshWishlist()
                return true
            end
            return false
        end,
        setMain = function(characterKey)
            if Addon.WarbandRoster:SetMain(characterKey) then
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
                return true
            end
            return false
        end,
        setHidden = function(characterKey, hidden)
            local changed = Addon.WarbandRoster:SetHidden(characterKey, hidden)
            if changed then
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
                Shell:RefreshWishlist()
                return true
            end
            return false
        end,
    })
    return frame.warbandOverviewPanel
end

function Shell:RefreshWarbandOverview()
    local panel = self.frame and self.frame.warbandOverviewPanel
    if panel and panel:IsShown() then panel:Refresh() end
    self:RefreshWarbandOverviewButton()
end

function Shell:OpenWarbandOverview()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return false end
    self:CloseSidebarMenus()
    local panel = self:CreateWarbandOverview(self.frame)
    self.warbandOverviewOpen = true
    panel:Show()
    panel:Raise()
    panel:Refresh()
    self:RefreshWarbandOverviewButton()
    return true
end

function Shell:CloseWarbandOverview()
    if not self.frame then return false end
    local wasOpen = self.warbandOverviewOpen == true
    self.warbandOverviewOpen = false
    if self.frame.warbandOverviewPanel then
        self.frame.warbandOverviewPanel:Hide()
    end
    self:RefreshWarbandOverviewButton()
    return wasOpen
end

function Shell:ToggleWarbandOverview()
    if self.warbandOverviewOpen then
        if Addon.Sound then Addon.Sound:Play("menuClose") end
        return self:CloseWarbandOverview()
    end
    if Addon.Sound then Addon.Sound:Play("menuOpen") end
    return self:OpenWarbandOverview()
end

function Shell:CreateMythicPlusOverview(frame)
    if frame.mythicPlusOverviewPanel then return frame.mythicPlusOverviewPanel end
    frame.mythicPlusOverviewPanel = Addon.MythicPlusOverview:Create(UIParent, {
        close = function()
            Shell:CloseMythicPlusOverview()
        end,
        getPosition = function()
            return Addon.Database:GetUI().mythicPlusOverview.window
        end,
        getSettings = function()
            return Addon.Database:GetUI().mythicPlusOverview
        end,
        setSetting = function(key, value)
            Addon.Database:GetUI().mythicPlusOverview[key] = value
            return true
        end,
        storePosition = function(overviewFrame)
            local point, _, relativePoint, x, y = overviewFrame:GetPoint(1)
            if not point then return false end
            local window = Addon.Database:GetUI().mythicPlusOverview.window
            window.point = point
            window.relativePoint = relativePoint or point
            window.x = tonumber(x) or 0
            window.y = tonumber(y) or 0
            return true
        end,
        getOverview = function()
            return Addon.MythicPlus:GetWarbandOverview()
        end,
        select = function(characterKey)
            if Addon.WarbandRoster:Select(characterKey) then
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
                return true
            end
            return false
        end,
    })
    return frame.mythicPlusOverviewPanel
end

function Shell:RefreshMythicPlusOverview()
    local panel = self.frame and self.frame.mythicPlusOverviewPanel
    if panel and panel:IsShown() then panel:Refresh() end
    self:RefreshMythicPlusOverviewButton()
end

function Shell:OpenMythicPlusOverview()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return false end
    self:CloseSidebarMenus()
    local panel = self:CreateMythicPlusOverview(self.frame)
    self.mythicPlusOverviewOpen = true
    Addon.MythicPlus:Open(panel)
    panel:Show()
    panel:Raise()
    panel:Refresh()
    self:RefreshMythicPlusOverviewButton()
    return true
end

function Shell:CloseMythicPlusOverview()
    if not self.frame then return false end
    local wasOpen = self.mythicPlusOverviewOpen == true
    self.mythicPlusOverviewOpen = false
    local panel = self.frame.mythicPlusOverviewPanel
    if panel then
        Addon.MythicPlus:Close(panel)
        panel:Hide()
    end
    self:RefreshMythicPlusOverviewButton()
    return wasOpen
end

function Shell:ToggleMythicPlusOverview()
    if self.mythicPlusOverviewOpen then
        if Addon.Sound then Addon.Sound:Play("menuClose") end
        return self:CloseMythicPlusOverview()
    end
    if Addon.Sound then Addon.Sound:Play("menuOpen") end
    return self:OpenMythicPlusOverview()
end

function Shell:CreateBannerPreviewPanel(frame)
    if not frame or frame.bannerPreviewPanel then
        return frame and frame.bannerPreviewPanel or nil
    end

    local panel = Widgets:CreatePanel(frame, "card")
    panel:SetSize(1210, 46)
    panel:SetPoint("BOTTOM", frame, "TOP", 0, 6)

    panel.title = Widgets:CreateLabel(panel, "GameFontNormal", "LEFT")
    panel.title:SetPoint("LEFT", 12, 0)
    panel.title:SetSize(88, 28)
    panel.title:SetText("Banner-Test")
    panel.title:SetTextColor(unpackColor(Theme.colors.gold))

    panel.buttonsByClass = {}
    for index, definition in ipairs(BANNER_PREVIEW_CLASSES) do
        local button = Widgets:CreateButton(panel, definition.label, 72, 28, "tab")
        button:SetPoint("LEFT", panel, "LEFT", 104 + ((index - 1) * 76), 0)
        button.classFile = definition.classFile
        button:SetScript("OnClick", function(selfButton)
            Shell:SetBannerPreviewClass(selfButton.classFile)
        end)
        panel.buttonsByClass[definition.classFile] = button
    end

    panel.closeButton = Widgets:CreateButton(panel, "Beenden", 70, 28)
    panel.closeButton:SetPoint("RIGHT", -8, 0)
    panel.closeButton:SetScript("OnClick", function()
        Shell:StopBannerPreview()
    end)

    panel:Hide()
    frame.bannerPreviewPanel = panel
    return panel
end

function Shell:SetBannerPreviewClass(classFile)
    local definition = getBannerPreviewDefinition(classFile)
    if not definition or not Assets.classHeroPlates or not Assets.classHeroPlates[classFile] then
        return false
    end

    self.bannerPreviewClass = classFile
    local panel = self.frame and self.frame.bannerPreviewPanel
    if panel then
        for buttonClass, button in pairs(panel.buttonsByClass or {}) do
            Widgets:SetButtonActive(button, buttonClass == classFile)
        end
        panel:Show()
    end
    self:RefreshCharacterContext()
    return true
end

function Shell:StopBannerPreview()
    local wasActive = self.bannerPreviewClass ~= nil
    self.bannerPreviewClass = nil
    if self.frame and self.frame.bannerPreviewPanel then
        self.frame.bannerPreviewPanel:Hide()
    end
    self:RefreshCharacterContext()
    if wasActive then
        Addon:Print("Banner-Test beendet. Der echte Charakter ist wieder aktiv.")
    end
    return wasActive
end

function Shell:ToggleBannerPreview()
    local frame = self:CreateFrame()
    if self.bannerPreviewClass then
        return self:StopBannerPreview()
    end

    self:SetBannerPreviewClass(BANNER_PREVIEW_CLASSES[1].classFile)
    if not frame:IsShown() then
        self:ApplySessionOpenDefaults()
        frame:Show()
        frame:Raise()
        self:EnsureBlizzardMenusAbove()
    end
    Addon:Print("Banner-Test aktiv: Klasse oben anklicken oder mit /vl bannertest beenden.")
    return true
end

function Shell:CreateFrame()
    if self.frame then
        return self.frame
    end

    local globalName = Addon.Identity.globalPrefix .. "MainFrame"
    local frame = CreateFrame("Frame", globalName, UIParent, BACKDROP_TEMPLATE)
    registerEscapeCloseFrame(globalName)
    frame:SetSize(Dimensions.width, Dimensions.height)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(false)
    frame:SetDontSavePosition(true)
    frame:SetUserPlaced(false)
    frame:SetBackdrop({
        bgFile = Assets.windowBackground,
        edgeFile = WOW_DIALOG_BORDER,
        tile = false,
        edgeSize = 28,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(0.62, 0.48, 0.18, 0.94)

    frame:SetScript("OnShow", function()
        if not frame.vaultloomSoundOpened then
            frame.vaultloomSoundOpened = true
            if Addon.Sound then Addon.Sound:Play("windowOpen") end
        end
        if Addon.UtilityResources and type(Addon.UtilityResources.Open) == "function" then
            Addon.UtilityResources:Open()
        end
        Shell:Refresh()
    end)
    frame:SetScript("OnHide", function()
        if frame.vaultloomSoundOpened then
            frame.vaultloomSoundOpened = false
            if Addon.Sound then Addon.Sound:Play("windowClose") end
        end
        Shell:CloseCharacterOrderDialog()
        Shell:RestoreBlizzardMenuLayers()
        if Shell.activeScreen and type(Shell.activeScreen.SetChromeVisible) == "function" then
            Shell.activeScreen:SetChromeVisible(false)
        end
        if Addon.UtilityResources and type(Addon.UtilityResources.Close) == "function" then
            Addon.UtilityResources:Close()
        end
    end)

    self.frame = frame
    self:EnsureBlizzardMenusAbove()
    self:CreateTitleBar(frame)
    self:CreateBannerPreviewPanel(frame)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 16, -52)
    frame.body:SetPoint("BOTTOMRIGHT", -16, 16)

    self:CreateTabs(frame)
    self:CreateSidebar(frame)
    self:CreateUtility(frame)
    self:CreateContent(frame)
    self:ApplyDisplaySettings()
    self:ApplyWindowPosition()

    Addon.StateStore:Subscribe("character.identity", self, function()
        if frame:IsShown() then
            Shell:RefreshCharacterContext()
        end
        Shell:RefreshWarbandOverview()
        Shell:RefreshMythicPlusOverview()
    end)
    Addon.StateStore:Subscribe("warband.roster", self, function()
        if frame:IsShown() then
            Shell:RefreshSidebar()
            Shell:RefreshCharacterContext()
        end
        Shell:RefreshWarbandOverview()
        Shell:RefreshMythicPlusOverview()
    end)
    Addon.StateStore:Subscribe("warband.selection", self, function()
        if frame:IsShown() then
            Shell:RefreshSidebar()
            Shell:RefreshCharacterContext()
            Shell:RefreshWishlist()
        end
        Shell:RefreshWarbandOverview()
        Shell:RefreshMythicPlusOverview()
    end)
    Addon.StateStore:Subscribe("character.utility", self, function()
        if frame:IsShown() then
            Shell:RefreshUtility()
        end
    end)
    Addon.StateStore:Subscribe("warband.activityScore", self, function()
        if frame:IsShown() then
            Shell:RefreshSidebar()
        end
        Shell:RefreshWarbandOverview()
    end)
    Addon.StateStore:Subscribe(Addon.Data.MYTHIC_PLUS.stateID, self, function()
        Shell:RefreshMythicPlusOverview()
    end)
    Addon.StateStore:Subscribe("vault.progress", self, function()
        if frame:IsShown() then
            Shell:RefreshSidebar()
        end
        Shell:RefreshWarbandOverview()
        Shell:RefreshMythicPlusOverview()
    end)

    frame:Hide()
    return frame
end

function Shell:EnsureRosterButtons(count)
    for index = #self.rosterButtons + 1, count do
        local button = Widgets:CreateButton(self.frame.sidebarList, "", 236, 58, "row")
        if index == 1 then
            button:SetPoint("TOPLEFT", 0, 0)
            button:SetPoint("TOPRIGHT", 0, 0)
        else
            button:SetPoint("TOPLEFT", self.rosterButtons[index - 1], "BOTTOMLEFT", 0, -4)
            button:SetPoint("TOPRIGHT", self.rosterButtons[index - 1], "BOTTOMRIGHT", 0, -4)
        end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.label:Hide()

        button.specializationBackground = button:CreateTexture(nil, "ARTWORK", nil, -8)
        button.specializationBackground:SetPoint("TOPLEFT", 2, -2)
        button.specializationBackground:SetPoint("BOTTOMRIGHT", -2, 2)
        button.specializationBackground:Hide()

        button.iconBackplate = button:CreateTexture(nil, "ARTWORK")
        button.iconBackplate:SetSize(38, 38)
        button.iconBackplate:SetPoint("LEFT", 10, 0)
        button.iconBackplate:SetColorTexture(1, 1, 1, 1)
        button.iconBackplateMask = addCircularMask(button, button.iconBackplate)
        button.classIcon = button:CreateTexture(nil, "OVERLAY", nil, 1)
        button.classIcon:SetSize(35, 35)
        button.classIcon:SetPoint("CENTER", button.iconBackplate, "CENTER", 0, 0)
        button.classMask = addCircularMask(button, button.classIcon)
        button.rewardBadge = VaultRewardBadge:Create(button, 15)
        button.rewardBadge:SetPoint(
            "BOTTOMRIGHT",
            button.iconBackplate,
            "BOTTOMRIGHT",
            2,
            -2
        )

        button.name = Widgets:CreateLabel(button, "GameFontNormal", "LEFT")
        button.name:SetHeight(18)
        button.name:SetWordWrap(false)
        button.name:SetMaxLines(1)

        button.mainTag = CreateFrame("Frame", nil, button)
        button.mainTag:SetSize(12, 14)
        button.mainTag:SetPoint("TOPRIGHT", -10, -10)
        button.mainTag:EnableMouse(true)
        button.mainTag.dot = button.mainTag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.mainTag.dot:SetPoint("CENTER", 0, 0)
        button.mainTag.dot:SetText("M")
        button.mainTag.dot:SetTextColor(unpackColor(Theme.colors.gold))
        button.mainTag:SetScript("OnEnter", function(selfTag)
            if not GameTooltip then return end
            GameTooltip:SetOwner(selfTag, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.SIDEBAR_MAIN, unpackColor(Theme.colors.gold))
            GameTooltip:Show()
        end)
        button.mainTag:SetScript("OnLeave", hideGameTooltip)
        positionSidebarCardName(button, false)

        createSidebarMetaLabels(button)
        button.realm = Widgets:CreateLabel(button, "GameFontHighlightSmall", "LEFT")
        button.realm:SetHeight(14)
        button.realm:SetWordWrap(false)
        button.realm:SetMaxLines(1)
        button.money = Widgets:CreateLabel(button, "GameFontHighlightSmall", "LEFT")
        button.money:SetHeight(14)
        button.money:Hide()
        button.professionFrame = CreateFrame("Frame", nil, button)
        button.professionFrame:SetSize(22, 22)
        button.professionFrame:Hide()
        button.professionButtons = {}

        -- Kept as a separate region for future alternate card layouts.
        button.score = Widgets:CreateLabel(button, "GameFontHighlightSmall", "RIGHT")
        button.score:SetPoint("RIGHT", button.meta, "RIGHT", 0, 0)
        button.score:Hide()
        button.vaultStrip = createVaultStrip(button, 52)
        button:SetScript("OnClick", function(selfButton, mouseButton)
            if mouseButton == "RightButton" then
                Addon.WarbandRoster:SetMain(selfButton.characterKey)
            else
                Addon.WarbandRoster:Select(selfButton.characterKey)
            end
            Shell:RefreshSidebar()
            Shell:RefreshCharacterContext()
        end)
        local rowEnter = button:GetScript("OnEnter")
        local rowLeave = button:GetScript("OnLeave")
        button:SetScript("OnEnter", function(selfButton)
            if rowEnter then rowEnter(selfButton) end
            local settings = Addon.WarbandRoster:GetSettings()
            if settings.fields.activityScore then showActivityScoreTooltip(selfButton, selfButton.characterKey) end
        end)
        button:SetScript("OnLeave", function(selfButton)
            if rowLeave then rowLeave(selfButton) end
            hideGameTooltip()
        end)
        self.rosterButtons[index] = button
    end
end

function Shell:EnsureVisibilityRows(count)
    for index = #self.visibilityRows + 1, count do
        local row = Widgets:CreateButton(self.frame.sidebarVisibilityList, "", 190, 24)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 25))
        row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(selfButton)
            if Addon.WarbandRoster:CanHide(selfButton.characterKey) then
                Addon.WarbandRoster:SetHidden(selfButton.characterKey, selfButton.isVisible)
                Shell:RefreshSidebar()
                Shell:RefreshCharacterContext()
            end
        end)
        self.visibilityRows[index] = row
    end
end

function Shell:RefreshWarbandSettings()
    if not self.frame or not self.frame.sidebarSettingsMenu then return end
    local settings = Addon.WarbandRoster:GetSettings()
    for fieldKey, button in pairs(self.frame.warbandFieldButtons or {}) do
        Widgets:SetButtonActive(button, settings.fields[fieldKey] == true)
    end
    for _, row in ipairs(self.frame.sidebarSortMenu.rows or {}) do
        row:SetShown(row.sortKey ~= "activityScore" or settings.fields.activityScore == true)
    end
    self:RefreshNewInterfaceBadges()

    local realmLabel = L.SIDEBAR_REALM_ALL
    if settings.realmFilter == "current" then
        realmLabel = L.SIDEBAR_REALM_CURRENT
    else
        local realm = type(settings.realmFilter) == "string" and settings.realmFilter:match("^realm:(.+)")
        if realm then realmLabel = string.format(L.SIDEBAR_REALM_VALUE, realm) end
    end
    self.frame.sidebarRealmButton.label:SetText(realmLabel)
    Widgets:SetButtonActive(self.frame.sidebarRealmButton, settings.realmFilter ~= "all")

    local hiddenCount = Addon.WarbandRoster:GetHiddenCount()
    Widgets:SetButtonActive(self.frame.sidebarShowAllButton, hiddenCount > 0)
    self.frame.sidebarShowAllButton:SetAlpha(hiddenCount > 0 and 1 or 0.45)
    self.frame.sidebarShowAllButton:EnableMouse(hiddenCount > 0)

    local selected = Addon.WarbandRoster:GetSelected()
    local canDelete = selected and not Addon.WarbandRoster:IsCurrent(selected.key)
    self.frame.sidebarDeleteButton:SetAlpha(canDelete and 1 or 0.45)
    self.frame.sidebarDeleteButton:EnableMouse(canDelete == true)
    if canDelete then self.frame.sidebarSettingsStatus:SetText("") end
end

function Shell:RefreshSidebar()
    if not self.frame then
        return
    end

    local allCharacters = Addon.WarbandRoster:GetAll()
    local ui = Addon.Database:GetUI()
    local roster = Addon.WarbandRoster:GetVisibleRoster(ui.sidebarSortMode)
    local selectedCharacter = Addon.WarbandRoster:GetSelected()
    local selectedKey = selectedCharacter and selectedCharacter.key or ui.selectedCharacterKey
    local settings = Addon.WarbandRoster:GetSettings()
    self:EnsureRosterButtons(#roster)
    self:EnsureVisibilityRows(#allCharacters)
    self.frame.sidebarEmpty:SetShown(#roster == 0)
    VaultRewardBadge:SetSummaryCount(
        self.frame.sidebarRewardSummary,
        Addon.VaultProgress:GetPendingRewardCount(),
        true
    )

    local currentKey = Addon.WarbandRoster:GetCurrentKey()
    local currentCharacter
    for _, character in ipairs(allCharacters) do
        if character.key == currentKey then
            currentCharacter = character
            break
        end
    end
    if currentCharacter then
        local itemLevel = currentCharacter.itemLevel and string.format("%.1f", currentCharacter.itemLevel) or "-"
        local classR, classG, classB = Addon.WoWApi:GetClassColor(currentCharacter.classFile)
        self.frame.sidebarCurrent.characterKey = currentCharacter.key
        self.frame.sidebarCurrent.name:SetText(getSidebarDisplayName(currentCharacter, settings))
        self.frame.sidebarCurrent.name:SetTextColor(classR, classG, classB, 1)
        self.frame.sidebarCurrent.realm:SetText(string.format(L.SIDEBAR_REALM_VALUE, currentCharacter.realm or L.UNKNOWN))
        self.frame.sidebarCurrent.money:SetText(formatCoinMoney(currentCharacter.money))
        self.frame.sidebarCurrent.iconBackplate:SetColorTexture(classR, classG, classB, 1)
        applyCharacterPortrait(self.frame.sidebarCurrent.classIcon, currentCharacter, true)
        VaultRewardBadge:SetCharacter(self.frame.sidebarCurrent.rewardBadge, currentCharacter.key)
        local _, _, showVault = applySidebarCardLayout(
            self.frame.sidebarCurrent,
            settings,
            true,
            buildSidebarMetaParts(currentCharacter, settings)
        )
        applySidebarCharacterBackground(
            self.frame.sidebarCurrent,
            currentCharacter,
            settings.fields.specializationArt == true
        )
        refreshSidebarProfessions(self.frame.sidebarCurrent, currentCharacter, settings, true)
        if showVault then refreshVaultStrip(self.frame.sidebarCurrent.vaultStrip, currentCharacter.key) end
        Widgets:SetButtonActive(self.frame.sidebarCurrent, currentCharacter.key == selectedKey)
        self.frame.sidebarCurrent:Show()
    else
        VaultRewardBadge:SetCharacter(self.frame.sidebarCurrent.rewardBadge, nil)
        self.frame.sidebarCurrent:Hide()
    end

    local sortLabels = {
        name = L.SIDEBAR_SORT_NAME,
        level = L.SIDEBAR_SORT_LEVEL,
        itemLevel = L.SIDEBAR_SORT_ITEM_LEVEL,
        realm = L.SIDEBAR_SORT_REALM,
        activityScore = L.SIDEBAR_SORT_ACTIVITY_SCORE,
        vault = L.SIDEBAR_SORT_VAULT,
    }
    self.frame.sidebarSortButton.label:SetText(string.format("%s: %s", L.SIDEBAR_SORT_SHORT, sortLabels[ui.sidebarSortMode] or L.SIDEBAR_SORT_MANUAL))
    local hiddenCount = Addon.WarbandRoster:GetHiddenCount()
    self.frame.sidebarVisibilityButton.label:SetText(hiddenCount > 0
        and string.format("%s (%d)", L.SIDEBAR_CHARACTERS_SHORT, hiddenCount) or L.SIDEBAR_CHARACTERS_SHORT)
    for _, row in ipairs(self.frame.sidebarSortMenu.rows) do
        Widgets:SetButtonActive(row, row.sortKey == ui.sidebarSortMode)
    end

    for index, row in ipairs(self.visibilityRows) do
        local character = allCharacters[index]
        if character then
            local visible = not Addon.WarbandRoster:IsHidden(character.key)
            row.characterKey = character.key
            row.isVisible = visible
            row.label:SetText(string.format("%s  %s-%s", visible and "|cffd8b84f+|r" or "-", character.name or L.UNKNOWN, character.realm or L.UNKNOWN))
            row:SetAlpha(Addon.WarbandRoster:IsCurrent(character.key) and 0.58 or 1)
            Widgets:SetButtonActive(row, visible)
            row:Show()
        else
            row:Hide()
        end
    end
    self.frame.sidebarVisibilityMenu:SetHeight(math.max(38, math.min(230, 12 + (#allCharacters * 25))))
    self.frame.sidebarVisibilityList:SetHeight(math.max(10, #allCharacters * 25))
    ScrollFrames:Refresh(self.frame.sidebarVisibilityScroll)

    local rosterContentHeight = 0
    for index, button in ipairs(self.rosterButtons) do
        local character = roster[index]
        if character then
            local itemLevel = character.itemLevel and string.format("%.1f", character.itemLevel) or "-"
            button.characterKey = character.key
            Widgets:SetButtonActive(button, character.key == selectedKey)
            local classR, classG, classB = Addon.WoWApi:GetClassColor(character.classFile)
            button.name:SetText(getSidebarDisplayName(character, settings))
            button.name:SetTextColor(classR, classG, classB, 1)
            button.realm:SetText(string.format(L.SIDEBAR_REALM_VALUE, character.realm or L.UNKNOWN))
            button.money:SetText(formatCoinMoney(character.money))
            button.mainTag:SetShown(character.isMain)
            button.mainTag:ClearAllPoints()
            button.mainTag:SetPoint("TOPRIGHT", -10, -10)
            positionSidebarCardName(button, character.isMain)
            button.iconBackplate:SetColorTexture(classR, classG, classB, 1)
            setClassIcon(button.classIcon, character.classFile)
            VaultRewardBadge:SetCharacter(button.rewardBadge, character.key)
            local buttonHeight, _, showVault = applySidebarCardLayout(
                button,
                settings,
                false,
                buildSidebarMetaParts(character, settings)
            )
            applySidebarCharacterBackground(
                button,
                character,
                settings.fields.specializationArt == true
            )
            rosterContentHeight = rosterContentHeight + buttonHeight + 4
            refreshSidebarProfessions(
                button,
                character,
                settings,
                Addon.WarbandRoster:IsCurrent(character.key)
            )
            button:ClearAllPoints()
            if index == 1 then
                button:SetPoint("TOPLEFT", 0, 0)
                button:SetPoint("TOPRIGHT", 0, 0)
            else
                button:SetPoint("TOPLEFT", self.rosterButtons[index - 1], "BOTTOMLEFT", 0, -4)
                button:SetPoint("TOPRIGHT", self.rosterButtons[index - 1], "BOTTOMRIGHT", 0, -4)
            end
            if showVault then refreshVaultStrip(button.vaultStrip, character.key) end
            button:Show()
        else
            button.characterKey = nil
            VaultRewardBadge:SetCharacter(button.rewardBadge, nil)
            button:Hide()
        end
    end
    self.frame.sidebarList:SetHeight(math.max(10, rosterContentHeight - 4))
    ScrollFrames:Refresh(self.frame.sidebarScroll)
    self.frame.sidebarSubtitle:SetText(string.format(#roster == 1 and L.SIDEBAR_STORED_ONE or L.SIDEBAR_STORED_MANY, #roster))
    self:RefreshWarbandSettings()
end

function Shell:RefreshUtility()
    if not self.frame or not self.frame.utilityStandard then
        return
    end

    local character = Addon.WarbandRoster:GetSelected() or Addon.StateStore:Get("character.identity")
    local view
    if Addon.UtilityResources and type(Addon.UtilityResources.GetView) == "function" then
        view = Addon.UtilityResources:GetView(character)
    else
        view = Addon.UtilityLogic:BuildView(nil, nil, {}, {})
    end

    local showUpgradeSection = view.showUpgradeSection == true
    local showPvpSection = view.showPvpSection == true
    local previousPanel
    self.frame.utilityUpgradeHeader:SetShown(showUpgradeSection)
    self.frame.utilityUpgradePanel:SetShown(showUpgradeSection)
    if showUpgradeSection then
        self.frame.utilityUpgradeHeader:ClearAllPoints()
        self.frame.utilityUpgradeHeader:SetPoint("TOPLEFT", self.frame.utilityStandard, "TOPLEFT", 16, -19)
        self.frame.utilityUpgradeHeader:SetPoint("TOPRIGHT", self.frame.utilityStandard, "TOPRIGHT", -48, -19)
        self.frame.utilityUpgradePanel:ClearAllPoints()
        self.frame.utilityUpgradePanel:SetPoint("TOPLEFT", self.frame.utilityUpgradeHeader, "BOTTOMLEFT", 0, -6)
        self.frame.utilityUpgradePanel:SetPoint("TOPRIGHT", self.frame.utilityStandard, "TOPRIGHT", -16, -6)
        previousPanel = self.frame.utilityUpgradePanel
    end

    self.frame.utilityPvpHeader:SetShown(showPvpSection)
    self.frame.utilityPvpPanel:SetShown(showPvpSection)
    if showPvpSection then
        self.frame.utilityPvpHeader:ClearAllPoints()
        if previousPanel then
            self.frame.utilityPvpHeader:SetPoint("TOPLEFT", previousPanel, "BOTTOMLEFT", 0, -12)
            self.frame.utilityPvpHeader:SetPoint("TOPRIGHT", previousPanel, "BOTTOMRIGHT", 0, -12)
        else
            self.frame.utilityPvpHeader:SetPoint("TOPLEFT", self.frame.utilityStandard, "TOPLEFT", 16, -19)
            self.frame.utilityPvpHeader:SetPoint("TOPRIGHT", self.frame.utilityStandard, "TOPRIGHT", -48, -19)
        end
        self.frame.utilityPvpPanel:ClearAllPoints()
        self.frame.utilityPvpPanel:SetPoint("TOPLEFT", self.frame.utilityPvpHeader, "BOTTOMLEFT", 0, -6)
        self.frame.utilityPvpPanel:SetPoint("TOPRIGHT", self.frame.utilityStandard, "TOPRIGHT", -16, -6)
        previousPanel = self.frame.utilityPvpPanel
    end

    self.frame.utilityResourceHeader:ClearAllPoints()
    if previousPanel then
        self.frame.utilityResourceHeader:SetPoint("TOPLEFT", previousPanel, "BOTTOMLEFT", 0, -12)
        self.frame.utilityResourceHeader:SetPoint("TOPRIGHT", previousPanel, "BOTTOMRIGHT", 0, -12)
    else
        self.frame.utilityResourceHeader:SetPoint("TOPLEFT", self.frame.utilityStandard, "TOPLEFT", 16, -19)
        self.frame.utilityResourceHeader:SetPoint("TOPRIGHT", self.frame.utilityStandard, "TOPRIGHT", -48, -19)
    end
    self.frame.utilityResourcePanel:ClearAllPoints()
    self.frame.utilityResourcePanel:SetPoint("TOPLEFT", self.frame.utilityResourceHeader, "BOTTOMLEFT", 0, -6)
    self.frame.utilityResourcePanel:SetPoint("BOTTOMRIGHT", self.frame.utilityStandard, "BOTTOMRIGHT", -16, 16)

    local function refreshCurrencyButtons(buttons, entries, upgradeStyle)
        local visibleButtons = {}
        for index, button in ipairs(buttons) do
            local entry = entries[index]
            if entry then
                local currencyID = entry.currencyID
                local color
                if type(ITEM_QUALITY_COLORS) == "table" then
                    color = upgradeStyle
                        and ITEM_QUALITY_COLORS[currencyID == 3442 and 3 or 4]
                        or ITEM_QUALITY_COLORS[tonumber(entry.quality)]
                end
                button.currencyID = currencyID
                button.icon:SetTexture(entry.icon or "Interface\\ICONS\\INV_Misc_QuestionMark")
                button.count:SetText(entry.quantity ~= nil and tostring(entry.quantity) or L.UTILITY_VALUE_UNKNOWN)
                setDesaturated(button.icon, not entry.available)
                button:SetAlpha(entry.available and 1 or 0.44)
                local edgeR = color and color.r or Theme.colors.goldDim[1]
                local edgeG = color and color.g or Theme.colors.goldDim[2]
                local edgeB = color and color.b or Theme.colors.goldDim[3]
                button.iconBorder:SetBackdropBorderColor(edgeR, edgeG, edgeB, entry.available and 0.92 or 0.42)
                button:Show()
                visibleButtons[#visibleButtons + 1] = button
            else
                button.currencyID = nil
                button:Hide()
            end
        end
        layoutUtilityCurrencyButtons(buttons[1] and buttons[1]:GetParent() or nil, visibleButtons)
    end
    refreshCurrencyButtons(self.frame.utilityUpgradeButtons, view.upgrades or {}, true)
    refreshCurrencyButtons(self.frame.utilityPvpButtons, view.pvp or {}, false)

    local hiddenCount = math.max(0, tonumber(view.hiddenCount) or 0)
    self.frame.utilitySettingsRestoreButton.hiddenCount = hiddenCount
    self.frame.utilitySettingsRestoreButton.label:SetText(hiddenCount > 0
        and string.format(L.RESOURCE_SHOW_ALL_COUNT, hiddenCount) or L.RESOURCE_SHOW_ALL)
    Widgets:SetButtonActive(self.frame.utilitySettingsRestoreButton, hiddenCount > 0)

    self.frame:EnsureUtilityResourceRows(#view.resources)
    for index, row in ipairs(self.frame.utilityResourceRows) do
        local entry = view.resources[index]
        if entry then
            row.entryKey = entry.entryKey
            row.currencyID = entry.currencyID
            row.itemID = entry.itemID
            row.name:SetText(entry.name or "...")
            row.value:SetText(entry.quantity ~= nil and tostring(entry.quantity) or L.UTILITY_VALUE_UNKNOWN)
            row.icon:SetTexture(entry.icon or "Interface\\ICONS\\INV_Misc_QuestionMark")
            local qualityColor = type(ITEM_QUALITY_COLORS) == "table"
                and ITEM_QUALITY_COLORS[tonumber(entry.quality)] or nil
            local borderR = qualityColor and qualityColor.r or Theme.colors.goldDim[1]
            local borderG = qualityColor and qualityColor.g or Theme.colors.goldDim[2]
            local borderB = qualityColor and qualityColor.b or Theme.colors.goldDim[3]
            local borderA = entry.available and 1 or 0.48
            row.iconQualityBorder:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
            setDesaturated(row.icon, not entry.available)
            row.name:SetTextColor(entry.available and 0.88 or 0.60, entry.available and 0.88 or 0.62, entry.available and 0.84 or 0.68, 1)
            row.value:SetTextColor(entry.available and 0.94 or 0.60, entry.available and 0.92 or 0.62, entry.available and 0.82 or 0.68, 1)
            row:SetAlpha(entry.available and 1 or 0.44)
            row:Show()
        else
            row.entryKey = nil
            row.currencyID = nil
            row.itemID = nil
            row:Hide()
        end
    end
    self.frame.utilityResourceList:SetHeight(math.max(
        10,
        (#view.resources * UTILITY_RESOURCE_ROW_STRIDE)
            - (UTILITY_RESOURCE_ROW_STRIDE - UTILITY_RESOURCE_ROW_HEIGHT)
    ))
    ScrollFrames:Refresh(self.frame.utilityResourceScroll)
    self:RefreshUtilitySettings()
end

function Shell:RefreshCharacterContext()
    if not self.frame then
        return
    end

    local preview = getBannerPreviewDefinition(self.bannerPreviewClass)
    if preview then
        applyHeroPlate(self.frame, preview.classFile)
        local classR, classG, classB = Addon.WoWApi:GetClassColor(preview.classFile)
        setClassIcon(self.frame.heroPortrait, preview.classFile)
        self.frame.heroTitle:SetText("Test-" .. preview.label)
        self.frame.heroTitle:SetTextColor(classR, classG, classB, 1)
        refreshHeroProfessionBadges(self.frame, nil)
        self.frame.heroSubtitle:SetText("Stufe 90  |  " .. preview.label .. "  |  Banner-Vorschau")
        self.frame.heroSync:SetText("Nur Anzeige – keine gespeicherten Charakterdaten")
        self:RefreshUtility()
        return
    end

    local character = Addon.WarbandRoster:GetSelected() or Addon.StateStore:Get("character.identity")
    if not character then
        applyHeroPlate(self.frame, nil)
        self.frame.heroTitle:SetText(L.UNKNOWN)
        self.frame.heroSubtitle:SetText("")
        self.frame.heroSync:SetText("")
        refreshHeroProfessionBadges(self.frame, nil)
        self:RefreshUtility()
        return
    end

    applyHeroPlate(self.frame, character.classFile)
    local classR, classG, classB = Addon.WoWApi:GetClassColor(character.classFile)
    applyCharacterPortrait(self.frame.heroPortrait, character, Addon.WarbandRoster:IsCurrent(character.key))
    self.frame.heroTitle:SetText(string.format("%s-%s", character.name or L.UNKNOWN, character.realm or L.UNKNOWN))
    self.frame.heroTitle:SetTextColor(classR, classG, classB, 1)
    refreshHeroProfessionBadges(self.frame, character)
    if character.itemLevel then
        self.frame.heroSubtitle:SetText(string.format(L.HERO_ITEM_LEVEL, character.level or 0, character.className or L.UNKNOWN, character.itemLevel))
    else
        self.frame.heroSubtitle:SetText(string.format(L.HERO_LEVEL_ONLY, character.level or 0, character.className or L.UNKNOWN))
    end
    self.frame.heroSync:SetText(string.format(L.HERO_LAST_SYNC, formatLastSeen(character.lastSeen)))
    self:RefreshUtility()
end

function Shell:RefreshWishlistButton()
    if not self.frame or not self.frame.wishlistButton then return end
    local button = self.frame.wishlistButton
    local active = self.wishlistOpen == true
    Widgets:SetButtonActive(button, active)
    local character = Addon.WarbandRoster:GetSelected() or Addon.StateStore:Get("character.identity")
    local counts = Addon.JournalLootTracker:GetCounts(character and character.key)
    button:SetAlpha((counts.wish > 0 or active) and 1 or 0.90)
    local symbolAlpha = (active or counts.wish > 0) and 1 or 0.72
    for _, texture in ipairs(button.wishlistIconTextures or {}) do
        texture:SetAlpha(symbolAlpha)
    end
end

function Shell:RefreshItemFinderButton()
    if not self.frame or not self.frame.itemFinderButton then return end
    local button = self.frame.itemFinderButton
    local runtime = Addon.ItemFinder
    local visible = runtime and runtime.enabled == true
        and Addon.FeatureRegistry:GetSetting("item_finder", "wishlist_button") == true
    local active = visible and runtime.window and runtime.window:IsShown() or false
    button:SetShown(visible == true)
    Widgets:SetButtonActive(button, active == true)
    if button.itemFinderIcon then
        button.itemFinderIcon:SetAlpha(active and 1 or 0.78)
    end
end

function Shell:RefreshWishlist()
    if not self.wishlistOpen or not self.frame or not self.frame.wishlistPanel then return end
    self.frame.wishlistPanel:Refresh()
    self:RefreshWishlistButton()
end

function Shell:ApplyOptionsLayout()
    if not self.frame then
        return
    end
    local optionsPanel = self:CreateOptions(self.frame)
    if self.activeScreen then
        if type(self.activeScreen.SetChromeVisible) == "function" then
            self.activeScreen:SetChromeVisible(false)
        end
        self.activeScreen:Hide()
    end
    self:CloseSidebarMenus()
    self.frame.sidebar:Hide()
    self.frame.content:Hide()
    self.frame.utility:Hide()
    if self.frame.wishlistPanel then self.frame.wishlistPanel:Hide() end
    if self.frame.featuresPanel then self.frame.featuresPanel:Hide() end
    optionsPanel:Show()
    optionsPanel:Refresh()
    for _, button in pairs(self.tabButtons) do
        Widgets:SetButtonActive(button, false)
    end
    self:RefreshWishlistButton()
    self:RefreshOptionsButton()
    self:RefreshFeaturesButton()
end

function Shell:OpenOptions(pageKey)
    if not self.frame then
        self:CreateFrame()
    end
    if not self.frame then
        return false
    end
    self:CloseWishlist(false)
    self:CloseFeatures(false)
    if pageKey then
        self:GetOptionSettings().selectedPage = pageKey
    end
    self.optionsOpen = true
    self:ApplyOptionsLayout()
    return true
end

function Shell:CloseOptions(restoreScreen)
    if not self.frame then
        return false
    end
    local wasOpen = self.optionsOpen == true
    self.optionsOpen = false
    if self.frame.optionsPanel then
        self.frame.optionsPanel:Hide()
    end
    self:RefreshOptionsButton()
    if wasOpen and restoreScreen == true then
        local selected = Addon.Database:GetUI().selectedScreen
        if not Addon.ScreenRegistry:GetDefinition(selected) or not self:IsScreenVisible(selected) then
            selected = self:GetFirstVisibleScreenID()
        end
        self:ShowScreen(selected)
    end
    return wasOpen
end

function Shell:ToggleOptions()
    if self.optionsOpen then
        if Addon.Sound then Addon.Sound:Play("menuClose") end
        return self:CloseOptions(true)
    end
    if Addon.Sound then Addon.Sound:Play("menuOpen") end
    return self:OpenOptions()
end

function Shell:ApplyWishlistLayout()
    if not self.frame then return end
    local wishlistPanel = self:CreateWishlist(self.frame)
    if self.activeScreen then
        if type(self.activeScreen.SetChromeVisible) == "function" then
            self.activeScreen:SetChromeVisible(false)
        end
        self.activeScreen:Hide()
    end
    self:CloseSidebarMenus()
    self.frame.sidebar:Show()
    self.frame.content:Hide()
    self.frame.utility:Hide()
    if self.frame.optionsPanel then self.frame.optionsPanel:Hide() end
    if self.frame.featuresPanel then self.frame.featuresPanel:Hide() end
    wishlistPanel:Show()
    wishlistPanel:Refresh()
    self:RefreshWishlistButton()
    self:RefreshFeaturesButton()
end

function Shell:OpenWishlist()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return false end
    self:CloseOptions(false)
    self:CloseFeatures(false)
    self.wishlistOpen = true
    self:ApplyWishlistLayout()
    return true
end

function Shell:CloseWishlist(restoreScreen)
    if not self.frame then return false end
    local wasOpen = self.wishlistOpen == true
    self.wishlistOpen = false
    if self.frame.wishlistPanel then self.frame.wishlistPanel:Hide() end
    self:RefreshWishlistButton()
    if wasOpen and restoreScreen == true then
        local selected = Addon.Database:GetUI().selectedScreen
        self:ShowScreen(Addon.ScreenRegistry:GetDefinition(selected) and selected or "vault")
    end
    return wasOpen
end

function Shell:ToggleWishlist()
    if self.wishlistOpen then
        if Addon.Sound then Addon.Sound:Play("menuClose") end
        return self:CloseWishlist(true)
    end
    if Addon.Sound then Addon.Sound:Play("menuOpen") end
    return self:OpenWishlist()
end

function Shell:ApplyFeaturesLayout()
    if not self.frame then return end
    local featuresPanel = self:CreateFeatures(self.frame)
    if self.activeScreen then
        if type(self.activeScreen.SetChromeVisible) == "function" then
            self.activeScreen:SetChromeVisible(false)
        end
        self.activeScreen:Hide()
    end
    self:CloseSidebarMenus()
    self.frame.sidebar:Hide()
    self.frame.content:Hide()
    self.frame.utility:Hide()
    if self.frame.optionsPanel then self.frame.optionsPanel:Hide() end
    if self.frame.wishlistPanel then self.frame.wishlistPanel:Hide() end
    featuresPanel:Show()
    featuresPanel:Refresh()
    for _, button in pairs(self.tabButtons) do
        Widgets:SetButtonActive(button, false)
    end
    self:RefreshWishlistButton()
    self:RefreshOptionsButton()
    self:RefreshFeaturesButton()
end

function Shell:OpenFeatures()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return false end
    self:CloseOptions(false)
    self:CloseWishlist(false)
    self.featuresOpen = true
    self:ApplyFeaturesLayout()
    return true
end

function Shell:CloseFeatures(restoreScreen)
    if not self.frame then return false end
    local wasOpen = self.featuresOpen == true
    self.featuresOpen = false
    if self.frame.featuresPanel then self.frame.featuresPanel:Hide() end
    self:RefreshFeaturesButton()
    if wasOpen and restoreScreen == true then
        local selected = Addon.Database:GetUI().selectedScreen
        if not Addon.ScreenRegistry:GetDefinition(selected) or not self:IsScreenVisible(selected) then
            selected = self:GetFirstVisibleScreenID()
        end
        self:ShowScreen(selected)
    end
    return wasOpen
end

function Shell:ToggleFeatures()
    if self.featuresOpen then
        if Addon.Sound then Addon.Sound:Play("menuClose") end
        return self:CloseFeatures(true)
    end
    if Addon.Sound then Addon.Sound:Play("menuOpen") end
    return self:OpenFeatures()
end

function Shell:OpenWishlistSource(source, difficultyKey)
    if type(source) ~= "table" then return false end
    local screenID = source.mainTabKey == "dungeons" and "dungeons"
        or source.mainTabKey == "raids" and "raids" or nil
    if not screenID then return false end

    self:CloseWishlist(false)
    if not self:ShowScreen(screenID) then return false end
    local service = screenID == "dungeons" and Addon.DungeonJournal or Addon.RaidJournal
    if source.subTabKey and type(service.SetSubTab) == "function" then service:SetSubTab(source.subTabKey) end
    if difficultyKey and type(service.SetDifficulty) == "function" then service:SetDifficulty(difficultyKey) end
    if type(service.SetSelection) == "function" then
        service:SetSelection(source.raidKey or "", source.bossKey or "")
    end
    return true
end

function Shell:ApplyScreenLayout(screenID)
    if not self.frame then
        return
    end
    local fullWidth = screenID == "compendium"
    local hideHero = fullWidth or screenID == "arsenal"
    if self.frame.optionsPanel then self.frame.optionsPanel:Hide() end
    if self.frame.wishlistPanel then self.frame.wishlistPanel:Hide() end
    if self.frame.featuresPanel then self.frame.featuresPanel:Hide() end
    self.frame.content:Show()
    self.frame.sidebar:SetShown(not fullWidth)
    self.frame.utility:SetShown(not fullWidth)
    self.frame.hero:SetShown(not hideHero)

    self.frame.content:ClearAllPoints()
    if fullWidth then
        self.frame.content:SetPoint("TOPLEFT", self.frame.tabBar, "BOTTOMLEFT", 0, -12)
        self.frame.content:SetPoint("BOTTOMRIGHT", self.frame.body, "BOTTOMRIGHT", 0, 0)
        self.frame.screenHost:ClearAllPoints()
        self.frame.screenHost:SetPoint("TOPLEFT", 14, -14)
        self.frame.screenHost:SetPoint("BOTTOMRIGHT", -14, 14)
    elseif hideHero then
        self.frame.content:SetPoint("TOPLEFT", self.frame.sidebar, "TOPRIGHT", Dimensions.gap, 0)
        self.frame.content:SetPoint("BOTTOMRIGHT", self.frame.utility, "BOTTOMLEFT", -Dimensions.gap, 0)
        self.frame.screenHost:ClearAllPoints()
        self.frame.screenHost:SetPoint("TOPLEFT", 14, -14)
        self.frame.screenHost:SetPoint("BOTTOMRIGHT", -14, 14)
    else
        self.frame.content:SetPoint("TOPLEFT", self.frame.sidebar, "TOPRIGHT", Dimensions.gap, 0)
        self.frame.content:SetPoint("BOTTOMRIGHT", self.frame.utility, "BOTTOMLEFT", -Dimensions.gap, 0)
        self.frame.screenHost:ClearAllPoints()
        self.frame.screenHost:SetPoint("TOPLEFT", self.frame.hero, "BOTTOMLEFT", 14, -14)
        self.frame.screenHost:SetPoint("BOTTOMRIGHT", -14, 14)
    end
end

function Shell:ShowScreen(screenID)
    local definition = Addon.ScreenRegistry:GetDefinition(screenID)
    if not definition or not self.frame then
        return false
    end

    if self.wishlistOpen then
        self:CloseWishlist(false)
    end
    if self.optionsOpen then
        self:CloseOptions(false)
    end
    if self.featuresOpen then
        self:CloseFeatures(false)
    end

    if self.activeScreen and self.activeScreen ~= Addon.ScreenRegistry.instances[screenID] then
        if type(self.activeScreen.SetChromeVisible) == "function" then
            self.activeScreen:SetChromeVisible(false)
        end
        self.activeScreen:Hide()
    end
    self:CloseSidebarMenus()

    local screen = Addon.ScreenRegistry:GetOrCreate(screenID, self.frame.screenHost)
    if not screen then
        return false
    end

    self.activeScreenID = screenID
    self.activeScreen = screen
    Addon.Database:GetUI().selectedScreen = screenID
    self:ApplyScreenLayout(screenID)

    for id, button in pairs(self.tabButtons) do
        Widgets:SetButtonActive(button, id == screenID)
    end
    self:RefreshOptionsButton()
    self:RefreshWishlistButton()
    self:RefreshFeaturesButton()
    if type(screen.SetChromeVisible) == "function" then
        screen:SetChromeVisible(true)
    end
    if type(screen.Refresh) == "function" then
        Addon:SafeCall("screen.refresh." .. screenID, screen.Refresh, screen)
    end
    screen:Show()
    return true
end

function Shell:Refresh()
    if not self.frame then
        return
    end
    self:ApplyDisplaySettings()
    self:RefreshMainTabs()
    self:RefreshSidebar()
    self:RefreshCharacterContext()

    if self.optionsOpen then
        self:ApplyOptionsLayout()
        return
    end

    if self.wishlistOpen then
        self:ApplyWishlistLayout()
        return
    end

    if self.featuresOpen then
        self:ApplyFeaturesLayout()
        return
    end

    local selected = Addon.Database:GetUI().selectedScreen
    if not Addon.ScreenRegistry:GetDefinition(selected) then
        selected = "vault"
    end
    self:ShowScreen(selected)
end

function Shell:Toggle()
    local frame = self:CreateFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        self:ApplySessionOpenDefaults()
        frame:Show()
        frame:Raise()
        self:EnsureBlizzardMenusAbove()
    end
end

function Shell:EnsureToggleBindingButton()
    if self.toggleBindingButton then
        return self.toggleBindingButton
    end

    local button = _G[TOGGLE_BINDING_BUTTON_NAME]
    if not button then
        button = CreateFrame("Button", TOGGLE_BINDING_BUTTON_NAME, UIParent)
        button:SetSize(1, 1)
        button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4, 4)
        button:SetAlpha(0)
        button:EnableMouse(false)
        if type(button.RegisterForClicks) == "function" then
            button:RegisterForClicks("LeftButtonUp")
        end
    end
    button:SetScript("OnClick", function()
        Shell:Toggle()
    end)
    button:Show()
    self.toggleBindingButton = button
    return button
end

function Shell:GetToggleBinding()
    if type(GetBindingKey) ~= "function" then return nil end
    local ok, primary = pcall(GetBindingKey, TOGGLE_BINDING_COMMAND)
    if not ok or type(primary) ~= "string" or primary == "" then return nil end
    return primary
end

function Shell:FormatToggleBinding(key)
    key = key or self:GetToggleBinding()
    if type(key) ~= "string" or key == "" then
        return L.OPTIONS_GENERAL_KEYBIND_NOT_BOUND
    end
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key, "KEY_", false)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return key
end

local function saveCurrentBindings()
    if type(SaveBindings) ~= "function" or type(GetCurrentBindingSet) ~= "function" then
        return true
    end
    local bindingSetOK, bindingSet = pcall(GetCurrentBindingSet)
    if not bindingSetOK then return false end
    local saveOK, saved = pcall(SaveBindings, bindingSet)
    return saveOK and saved ~= false
end

function Shell:SetToggleBinding(key)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "combat"
    end
    key = type(key) == "string" and key:upper() or nil
    if not key or key == "" or type(SetBindingClick) ~= "function" then
        return false, "failed"
    end

    self:EnsureToggleBindingButton()
    local previousAction = ""
    if type(GetBindingAction) == "function" then
        local actionOK, action = pcall(GetBindingAction, key)
        if actionOK and type(action) == "string" then previousAction = action end
    end

    local oldPrimary, oldSecondary
    if type(GetBindingKey) == "function" then
        local keysOK
        keysOK, oldPrimary, oldSecondary = pcall(GetBindingKey, TOGGLE_BINDING_COMMAND)
        if not keysOK then oldPrimary, oldSecondary = nil, nil end
    end

    local setOK, setResult = pcall(
        SetBindingClick,
        key,
        TOGGLE_BINDING_BUTTON_NAME,
        "LeftButton"
    )
    if not setOK or setResult == false then
        return false, "failed"
    end
    if type(GetBindingAction) == "function" then
        local actionOK, action = pcall(GetBindingAction, key)
        if actionOK and action ~= TOGGLE_BINDING_COMMAND then
            return false, "failed"
        end
    end

    if type(SetBinding) == "function" then
        for _, oldKey in ipairs({ oldPrimary, oldSecondary }) do
            if type(oldKey) == "string" and oldKey ~= "" and oldKey ~= key then
                pcall(SetBinding, oldKey)
            end
        end
    end
    if not saveCurrentBindings() then
        return false, "failed"
    end
    local replaced = previousAction ~= "" and previousAction ~= TOGGLE_BINDING_COMMAND
    return true, replaced and "replaced" or "saved"
end

function Shell:ClearToggleBinding()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "combat"
    end
    if type(GetBindingKey) ~= "function" or type(SetBinding) ~= "function" then
        return false, "failed"
    end

    local keysOK, primary, secondary = pcall(GetBindingKey, TOGGLE_BINDING_COMMAND)
    if not keysOK then return false, "failed" end
    for _, key in ipairs({ primary, secondary }) do
        if type(key) == "string" and key ~= "" then
            local clearOK, clearResult = pcall(SetBinding, key)
            if not clearOK or clearResult == false then
                return false, "failed"
            end
        end
    end
    if not saveCurrentBindings() then
        return false, "failed"
    end
    return true, "cleared"
end

Shell:EnsureToggleBindingButton()

Addon.EventBus:Subscribe("ADDON_LOADED", Shell, function()
    Shell:EnsureBlizzardMenusAbove()
end)
