local _, Addon = ...

local FEATURE_ID = "profession_knowledge_badges"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MASK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local RING_TEXTURE = "Interface\\AddOns\\" .. Addon.Identity.addonName
    .. "\\Assets\\gathering_pin_ring_world.tga"
local BASE_BADGE_SIZE = 22

local DEFAULTS = {
    badge_scale_percent = 100,
}

local Runtime = {
    enabled = false,
    hooksReady = false,
    hookedFrame = nil,
    badges = {},
    refreshGeneration = 0,
}

Addon.ProfessionKnowledgeBadges = Runtime

local function setting(key)
    local state = Addon.FeatureRegistry:GetState(FEATURE_ID)
    local value = state.settings[key]
    return value == nil and DEFAULTS[key] or value
end

local function getBadgeScale()
    return math.max(0.80, math.min(1.30, (tonumber(setting("badge_scale_percent")) or 100) / 100))
end

local function getCurrentCharacterKey()
    local identity = Addon.StateStore:Get("character.identity")
    return type(identity) == "table" and identity.key or nil
end

local function getKnowledgeState()
    local characterKey = getCurrentCharacterKey()
    local runtimeState = Addon.StateStore:Get("systems.professions")
    if type(runtimeState) == "table"
        and type(runtimeState.knowledge) == "table"
        and (not characterKey or runtimeState.characterKey == characterKey)
    then
        return runtimeState.knowledge
    end
    if characterKey and Addon.Professions and type(Addon.Professions.GetKnowledge) == "function" then
        return Addon.Professions:GetKnowledge(characterKey)
    end
    return nil
end

local function getNestedProfessionButton(container)
    if not container then return nil end
    for _, field in ipairs({
        "SpellButtonBottom",
        "spellButtonBottom",
        "SkillButton",
        "skillButton",
        "ProfessionButton",
        "professionButton",
        "Button",
        "button",
    }) do
        local candidate = container[field]
        if candidate then return candidate end
    end
    return nil
end

local function resolveProfessionButton(slotIndex)
    local globalName = string.format("PrimaryProfession%dSpellButtonBottom", slotIndex)
    if _G[globalName] then return _G[globalName] end

    local container = _G[string.format("PrimaryProfession%d", slotIndex)]
    local nested = getNestedProfessionButton(container)
    if nested then return nested end

    local book = _G.ProfessionsBookFrame
    if not book then return nil end
    if book[globalName] then return book[globalName] end
    container = book[string.format("PrimaryProfession%d", slotIndex)]
    nested = getNestedProfessionButton(container)
    if nested then return nested end
    if type(book.PrimaryProfessions) == "table" then
        return getNestedProfessionButton(book.PrimaryProfessions[slotIndex])
            or book.PrimaryProfessions[slotIndex]
    end
    return nil
end

local function setBadgePoints(badge, points, professionName)
    points = math.max(0, math.floor(tonumber(points) or 0))
    badge.points = points
    badge.professionName = professionName
    badge.text:SetText(points > 99 and "99+" or tostring(points))
end

local function createBadge(parent, interactive)
    local badge = CreateFrame("Button", nil, parent)
    badge:SetSize(BASE_BADGE_SIZE, BASE_BADGE_SIZE)
    badge:SetFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 8)
    badge:SetScale(getBadgeScale())
    badge:EnableMouse(interactive ~= false)
    if type(badge.RegisterForClicks) == "function" then badge:RegisterForClicks("LeftButtonUp") end

    badge.fill = badge:CreateTexture(nil, "BACKGROUND")
    badge.fill:SetPoint("TOPLEFT", 2, -2)
    badge.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    badge.fill:SetTexture(WHITE_TEXTURE)
    badge.fill:SetVertexColor(0.045, 0.040, 0.035, 0.98)

    if type(badge.CreateMaskTexture) == "function"
        and type(badge.fill.AddMaskTexture) == "function"
    then
        badge.fillMask = badge:CreateMaskTexture(nil, "ARTWORK")
        badge.fillMask:SetTexture(
            MASK_TEXTURE,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        badge.fillMask:SetAllPoints(badge.fill)
        badge.fill:AddMaskTexture(badge.fillMask)
    end

    badge.ring = badge:CreateTexture(nil, "OVERLAY")
    badge.ring:SetAllPoints(badge)
    badge.ring:SetTexture(RING_TEXTURE)
    badge.ring:SetVertexColor(0.92, 0.72, 0.25, 1)

    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetTextColor(1, 0.94, 0.76, 1)
    badge.text:SetShadowOffset(1, -1)
    badge.text:SetShadowColor(0, 0, 0, 1)

    if interactive ~= false then
        badge:SetScript("OnEnter", function(self)
            if not GameTooltip or (tonumber(self.points) or 0) <= 0 then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(
                self.professionName or Addon.L.PROFESSIONS_KNOWLEDGE_LABEL,
                1,
                0.82,
                0.24,
                true
            )
            GameTooltip:AddLine(
                string.format(
                    Addon.L.PROFESSION_KNOWLEDGE_BADGE_TOOLTIP,
                    tonumber(self.points) or 0
                ),
                1,
                1,
                1,
                true
            )
            GameTooltip:AddLine(
                Addon.L.PROFESSION_KNOWLEDGE_BADGE_CLICK_HINT,
                0.72,
                0.72,
                0.70,
                true
            )
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        badge:SetScript("OnClick", function(self, mouseButton)
            local owner = self:GetParent()
            if owner and type(owner.Click) == "function" then
                pcall(owner.Click, owner, mouseButton or "LeftButton")
            end
        end)
    end

    badge:Hide()
    return badge
end

function Runtime:HideAllBadges()
    for _, badge in pairs(self.badges) do
        badge:Hide()
    end
end

function Runtime:EnsureBadge(slotIndex, parentButton)
    if not parentButton then return nil end
    local badge = self.badges[slotIndex]
    if not badge then
        badge = createBadge(parentButton, true)
        self.badges[slotIndex] = badge
    end
    badge:SetParent(parentButton)
    badge:SetFrameLevel((parentButton.GetFrameLevel and parentButton:GetFrameLevel() or 1) + 8)
    badge:SetScale(getBadgeScale())
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", parentButton, "TOPLEFT", 5, -5)
    return badge
end

function Runtime:IsProfessionBookShown()
    local frame = _G.ProfessionsBookFrame
    return frame ~= nil
        and (type(frame.IsShown) ~= "function" or frame:IsShown())
end

function Runtime:Refresh()
    if self.enabled ~= true or not self:IsProfessionBookShown() then
        self:HideAllBadges()
        return
    end

    local knowledge = getKnowledgeState()
    local entriesBySlot = {}
    for _, entry in ipairs(type(knowledge) == "table" and knowledge.professions or {}) do
        local slotIndex = tonumber(entry and entry.slotIndex)
        if slotIndex and slotIndex >= 1 and slotIndex <= 2 then
            entriesBySlot[slotIndex] = entry
        end
    end

    for slotIndex = 1, 2 do
        local parentButton = resolveProfessionButton(slotIndex)
        local entry = entriesBySlot[slotIndex]
        local badge = parentButton and self:EnsureBadge(slotIndex, parentButton)
            or self.badges[slotIndex]
        local points = math.max(0, tonumber(entry and entry.points) or 0)
        if badge and parentButton and entry and points > 0 then
            setBadgePoints(badge, points, entry.name)
            badge:Show()
        elseif badge then
            badge:Hide()
        end
    end

    if type(knowledge) ~= "table"
        and Addon.Professions
        and type(Addon.Professions.Refresh) == "function"
    then
        Addon.Professions:Refresh(0.05)
    end
end

function Runtime:QueueRefresh(delay)
    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local callback = function()
        if Runtime.enabled == true and generation == Runtime.refreshGeneration then
            Runtime:Refresh()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" and (tonumber(delay) or 0) > 0 then
        C_Timer.After(
            delay,
            Addon.PerformanceDiagnostics:Wrap(
                Runtime,
                "timer",
                "profession_knowledge_badges.refresh",
                callback
            )
        )
    else
        local wrapped = Addon.PerformanceDiagnostics:Wrap(
            Runtime,
            "timer",
            "profession_knowledge_badges.refresh",
            callback
        )
        wrapped()
    end
end

function Runtime:EnsureHooks()
    local frame = _G.ProfessionsBookFrame
    if not frame or type(frame.HookScript) ~= "function" then return false end
    if self.hooksReady and self.hookedFrame == frame then
        Addon.EventBus:Unsubscribe(self, "ADDON_LOADED")
        return true
    end

    frame:HookScript("OnShow", function()
        if Runtime.enabled == true then Runtime:QueueRefresh(0.10) end
    end)
    frame:HookScript("OnHide", function()
        Runtime.refreshGeneration = Runtime.refreshGeneration + 1
        Runtime:HideAllBadges()
    end)
    self.hooksReady = true
    self.hookedFrame = frame
    Addon.EventBus:Unsubscribe(self, "ADDON_LOADED")
    if self.enabled == true and self:IsProfessionBookShown() then self:QueueRefresh(0.05) end
    return true
end

local function createPreviewProfession(parent, name, icon, points)
    local card = Addon.Widgets:CreatePanel(parent, "cardInset")
    card:SetSize(225, 82)

    card.iconButton = CreateFrame("Button", nil, card, BACKDROP_TEMPLATE)
    card.iconButton:SetSize(50, 50)
    card.iconButton:SetPoint("LEFT", 16, 0)
    card.iconButton:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    card.iconButton:SetBackdropColor(0.025, 0.022, 0.018, 0.96)
    card.iconButton:SetBackdropBorderColor(0.56, 0.43, 0.18, 0.92)

    card.icon = card.iconButton:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 2, -2)
    card.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    card.icon:SetTexture(icon)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.label = Addon.Widgets:CreateLabel(card, "GameFontNormal", "LEFT")
    card.label:SetPoint("LEFT", card.iconButton, "RIGHT", 14, 8)
    card.label:SetPoint("RIGHT", -10, 8)
    card.label:SetText(name)

    card.note = Addon.Widgets:CreateLabel(card, "GameFontDisableSmall", "LEFT")
    card.note:SetPoint("LEFT", card.iconButton, "RIGHT", 14, -12)
    card.note:SetPoint("RIGHT", -10, -12)
    card.note:SetText(Addon.L.PROFESSIONS_KNOWLEDGE_LABEL)

    card.badge = createBadge(card.iconButton, false)
    card.badge:SetPoint("RIGHT", card.iconButton, "TOPLEFT", 5, -5)
    setBadgePoints(card.badge, points, name)
    card.badge:Show()
    return card
end

function Runtime:EnsurePreview()
    if self.preview then return self.preview end
    local frame = CreateFrame(
        "Frame",
        "VaultloomProfessionKnowledgePreview",
        UIParent,
        BACKDROP_TEMPLATE
    )
    frame:SetSize(560, 280)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(125)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.windowBackground)

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -20)
    frame.title:SetPoint("TOPRIGHT", -60, -20)
    frame.title:SetTextColor(1, 0.82, 0.24, 1)
    frame.title:SetText(Addon.L.PROFESSION_KNOWLEDGE_PREVIEW_TITLE)

    frame.subtitle = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.subtitle:SetPoint("TOPRIGHT", -22, -50)
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(Addon.L.PROFESSION_KNOWLEDGE_PREVIEW_SUBTITLE)

    frame.close = Addon.Widgets:CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -18, -16)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.alchemy = createPreviewProfession(
        frame,
        Addon.L.PROFESSION_KNOWLEDGE_PREVIEW_ALCHEMY,
        136240,
        12
    )
    frame.alchemy:SetPoint("BOTTOMLEFT", 34, 46)
    frame.herbalism = createPreviewProfession(
        frame,
        Addon.L.PROFESSION_KNOWLEDGE_PREVIEW_HERBALISM,
        136065,
        145
    )
    frame.herbalism:SetPoint("BOTTOMRIGHT", -34, 46)
    frame.previewBadges = { frame.alchemy.badge, frame.herbalism.badge }
    frame:Hide()
    self.preview = frame
    return frame
end

function Runtime:RefreshScale()
    local scale = getBadgeScale()
    for _, badge in pairs(self.badges) do badge:SetScale(scale) end
    if self.preview then
        for _, badge in ipairs(self.preview.previewBadges or {}) do badge:SetScale(scale) end
    end
end

function Runtime:TogglePreview()
    local frame = self:EnsurePreview()
    if frame:IsShown() then
        frame:Hide()
    else
        self:RefreshScale()
        frame:Show()
        if type(frame.Raise) == "function" then frame:Raise() end
    end
end

function Runtime:GetSettingValue(key)
    if DEFAULTS[key] == nil then return nil end
    return setting(key)
end

function Runtime:SetSettingValue(key, value)
    if DEFAULTS[key] == nil then return false end
    Addon.FeatureRegistry:GetState(FEATURE_ID).settings[key] = value
    self:RefreshScale()
    self:QueueRefresh(0)
    return true
end

function Runtime:ResetSettingValues()
    self:RefreshScale()
    self:QueueRefresh(0)
end

function Runtime:OnSettingsReset()
    self:ResetSettingValues()
end

function Runtime:OnSettingsClosed()
    if self.preview then self.preview:Hide() end
end

function Runtime:OnAction(actionKey)
    if actionKey == "preview" then
        self:TogglePreview()
        return true
    end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshGeneration = self.refreshGeneration + 1
    Addon.EventBus:Subscribe("ADDON_LOADED", self, function()
        if Runtime:EnsureHooks() then Runtime:QueueRefresh(0.05) end
    end)
    Addon.StateStore:Subscribe("systems.professions", self, function()
        Runtime:QueueRefresh(0.05)
    end, true)
    self:EnsureHooks()
    self:QueueRefresh(0.05)
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self:HideAllBadges()
    if self.preview then self.preview:Hide() end
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Profession Knowledge Badges runtime.")
end
