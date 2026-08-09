local _, Addon = ...

local FEATURE_ID = "action_loom"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING_TEXTURE = "Interface\\AddOns\\"
    .. Addon.Identity.addonName
    .. "\\Assets\\gathering_pin_ring.tga"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local EDITOR_ROWS = 12
local LAYOUT_SETTINGS = {
    button_scale_percent = true,
    button_spacing = true,
}

local BAR_SPECS = {
    { name = "MainActionBar", kind = "action" },
    { name = "MultiBarBottomLeft", kind = "action" },
    { name = "MultiBarBottomRight", kind = "action" },
    { name = "MultiBarRight", kind = "action" },
    { name = "MultiBarLeft", kind = "action" },
    { name = "MultiBar5", kind = "action" },
    { name = "MultiBar6", kind = "action" },
    { name = "MultiBar7", kind = "action" },
    { name = "PetActionBar", kind = "pet" },
    { name = "StanceBar", kind = "stance" },
    { name = "PossessActionBar", kind = "possess" },
}

local GROUP_LABELS = {
    normal = "ACTION_BARS_GROUP_NORMAL",
    attack_cd = "ACTION_BARS_GROUP_ATTACK",
    def_cd = "ACTION_BARS_GROUP_DEFENSIVE",
    heal = "ACTION_BARS_GROUP_HEAL",
    utility = "ACTION_BARS_GROUP_UTILITY",
    interrupt = "ACTION_BARS_GROUP_INTERRUPT",
    movement = "ACTION_BARS_GROUP_MOVEMENT",
    item = "ACTION_BARS_GROUP_ITEM",
    custom_1 = "ACTION_BARS_GROUP_CUSTOM_1",
    custom_2 = "ACTION_BARS_GROUP_CUSTOM_2",
    custom_3 = "ACTION_BARS_GROUP_CUSTOM_3",
    custom_4 = "ACTION_BARS_GROUP_CUSTOM_4",
    none = "ACTION_BARS_GROUP_NONE",
}

local Runtime = {
    enabled = false,
    registered = {},
    recordByButton = setmetatable({}, { __mode = "k" }),
    visuals = setmetatable({}, { __mode = "k" }),
    slotButtons = {},
    kindButtons = {},
    discoveredBars = {},
    barLayouts = setmetatable({}, { __mode = "k" }),
    buttonLayouts = setmetatable({}, { __mode = "k" }),
    layoutPending = false,
    refreshQueued = false,
    refreshGeneration = 0,
    alertManager = nil,
    alertHooksReady = false,
    editor = nil,
    editorRows = {},
    editorEntries = nil,
    editorPage = 1,
    spellLookup = {},
    stats = {
        visualBundles = 0,
        fullRefreshes = 0,
        buttonRefreshes = 0,
    },
}

Addon.ActionBars = Runtime

local function setting(key)
    return Addon.FeatureRegistry:GetSetting(FEATURE_ID, key)
end

local function getStore()
    local db = Addon.Database:Get()
    db.features = type(db.features) == "table" and db.features or {}
    db.features.actionBars = Addon.ActionBarsLogic:NormalizeStore(db.features.actionBars)
    return db.features.actionBars
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, first, second, third, fourth = pcall(callback, ...)
    if not ok then return nil end
    return first, second, third, fourth
end

local function isSecret(value)
    return type(_G.issecretvalue) == "function"
        and _G.issecretvalue(value) == true
end

local function getClassTag()
    local _, classTag = safeCall(_G.UnitClass, "player")
    return classTag
end

local function getActionInfo(slot)
    if C_ActionBar and type(C_ActionBar.GetActionInfo) == "function" then
        return safeCall(C_ActionBar.GetActionInfo, slot)
    end
    return safeCall(_G.GetActionInfo, slot)
end

local function getActionTexture(slot)
    if C_ActionBar and type(C_ActionBar.GetActionTexture) == "function" then
        return safeCall(C_ActionBar.GetActionTexture, slot)
    end
    return safeCall(_G.GetActionTexture, slot)
end

local function getSpellInfo(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = safeCall(C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" then return info.name, info.iconID end
    end
    local name, _, icon = safeCall(_G.GetSpellInfo, spellID)
    return name, icon
end

local function getItemInfo(itemID)
    local name, link, icon
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        name, link = safeCall(C_Item.GetItemInfo, itemID)
        icon = safeCall(C_Item.GetItemIconByID, itemID)
    else
        local ok, resultName, resultLink, quality, itemLevel, requiredLevel,
            itemType, itemSubType, stackCount, equipLocation, resultIcon =
            pcall(_G.GetItemInfo, itemID)
        if ok then
            name, link, icon = resultName, resultLink, resultIcon
        end
    end
    return name, icon, link
end

local function parseItemID(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end
    return tonumber(value:match("item:(%d+)"))
end

local function getButtonIcon(button)
    return button and (button.icon or button.Icon) or nil
end

local function getButtonSlot(button)
    if not button then return nil end
    local action = tonumber(button.action)
    if action then return action end
    if type(button.GetAttribute) == "function" then
        action = tonumber(button:GetAttribute("action"))
        if action then return action end
    end
    return type(button.GetID) == "function" and tonumber(button:GetID()) or nil
end

local function getRegion(button, field, getter)
    local region = button and button[field] or nil
    if not region and button and type(button[getter]) == "function" then
        region = safeCall(button[getter], button)
    end
    return region
end

local function captureAlpha(bundle, key, region)
    if not region then return end
    bundle.originalAlpha[key] = type(region.GetAlpha) == "function" and region:GetAlpha() or 1
end

local function setRegionAlpha(region, alpha)
    if region and type(region.SetAlpha) == "function" then region:SetAlpha(alpha) end
end

local function addMask(region, mask)
    if region and type(region.AddMaskTexture) == "function" then region:AddMaskTexture(mask) end
end

local function removeMask(region, mask)
    if region and type(region.RemoveMaskTexture) == "function" then
        region:RemoveMaskTexture(mask)
    end
end

local function originalAlpha(bundle, key)
    local value = bundle.originalAlpha[key]
    return value == nil and 1 or value
end

local function collectTextures(frame)
    local textures = {}
    if not frame then return textures end
    if type(frame.GetRegions) == "function" then
        local ok, regions = pcall(function() return { frame:GetRegions() } end)
        if ok then
            for _, region in ipairs(regions) do
                if region and type(region.AddMaskTexture) == "function" then
                    textures[#textures + 1] = region
                end
            end
        end
    end
    return textures
end

local function setCooldownMask(bundle, cooldown, enabled)
    if not cooldown then return end
    bundle.cooldownMasks = bundle.cooldownMasks or setmetatable({}, { __mode = "k" })
    local state = bundle.cooldownMasks[cooldown]
    if not state and type(cooldown.CreateMaskTexture) == "function" then
        local mask = cooldown:CreateMaskTexture(nil, "OVERLAY")
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(cooldown)
        state = { mask = mask, textures = {}, applied = setmetatable({}, { __mode = "k" }) }
        bundle.cooldownMasks[cooldown] = state
    end
    if not state then return end

    if enabled then
        for _, texture in ipairs(collectTextures(cooldown)) do
            if not state.applied[texture] then
                addMask(texture, state.mask)
                state.applied[texture] = true
                state.textures[#state.textures + 1] = texture
            end
        end
    else
        for _, texture in ipairs(state.textures) do
            removeMask(texture, state.mask)
            state.applied[texture] = nil
        end
        state.textures = {}
    end
end

local function setCooldownShape(bundle, round)
    setCooldownMask(bundle, bundle.nativeCooldown, round)
    setCooldownMask(bundle, bundle.nativeChargeCooldown, round)
    setCooldownMask(bundle, bundle.nativeLossCooldown, round)
end

local function alertFrames(button)
    local frames, seen = {}, {}
    local function add(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    add(button and button.SpellActivationAlert)
    add(button
        and button.AssistedCombatRotationFrame
        and button.AssistedCombatRotationFrame.SpellActivationAlert)
    return frames
end

function Runtime:EnsureVisual(button)
    local bundle = self.visuals[button]
    if bundle then return bundle end

    local icon = getButtonIcon(button)
    if not icon then return nil end
    bundle = {
        button = button,
        icon = icon,
        originalAlpha = {},
        originalTexCoord = { icon:GetTexCoord() },
        alertStates = setmetatable({}, { __mode = "k" }),
    }
    bundle.normal = getRegion(button, "NormalTexture", "GetNormalTexture")
    bundle.pushed = getRegion(button, "PushedTexture", "GetPushedTexture")
    bundle.checked = getRegion(button, "CheckedTexture", "GetCheckedTexture")
    bundle.highlight = getRegion(button, "HighlightTexture", "GetHighlightTexture")
    bundle.slotBackground = button.SlotBackground
    bundle.slotArt = button.SlotArt
    bundle.nativeCooldown = button.cooldown or button.Cooldown
    bundle.nativeChargeCooldown = button.chargeCooldown or button.ChargeCooldown
    bundle.nativeLossCooldown = button.lossOfControlCooldown or button.LossOfControlCooldown
    bundle.hotKey = button.HotKey or button.hotkey
    bundle.count = button.Count or button.count

    captureAlpha(bundle, "normal", bundle.normal)
    captureAlpha(bundle, "pushed", bundle.pushed)
    captureAlpha(bundle, "checked", bundle.checked)
    captureAlpha(bundle, "highlight", bundle.highlight)
    captureAlpha(bundle, "slotBackground", bundle.slotBackground)
    captureAlpha(bundle, "slotArt", bundle.slotArt)
    captureAlpha(bundle, "nativeCooldown", bundle.nativeCooldown)
    captureAlpha(bundle, "nativeChargeCooldown", bundle.nativeChargeCooldown)
    captureAlpha(bundle, "nativeLossCooldown", bundle.nativeLossCooldown)
    captureAlpha(bundle, "hotKey", bundle.hotKey)
    captureAlpha(bundle, "count", bundle.count)

    bundle.mask = button:CreateMaskTexture(nil, "ARTWORK")
    bundle.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    bundle.mask:SetAllPoints(icon)

    bundle.rings = {}
    for index = 1, 4 do
        local ring = button:CreateTexture(nil, "OVERLAY", nil, 5)
        ring:SetTexture(RING_TEXTURE)
        ring:Hide()
        bundle.rings[index] = ring
    end
    bundle.ring = bundle.rings[1]

    bundle.ready = button:CreateTexture(nil, "OVERLAY", nil, 6)
    bundle.ready:SetTexture(WHITE_TEXTURE)
    bundle.ready:SetAllPoints(icon)
    bundle.ready:SetBlendMode("ADD")
    bundle.ready:SetAlpha(0.24)

    bundle.edges = {}
    for index = 1, 4 do
        local edge = button:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetTexture(WHITE_TEXTURE)
        bundle.edges[index] = edge
    end

    bundle.procFrame = CreateFrame("Frame", nil, button)
    bundle.procFrame:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 8)
    bundle.procFrame:EnableMouse(false)
    bundle.procGlow = bundle.procFrame:CreateTexture(nil, "OVERLAY")
    bundle.procGlow:SetAllPoints(bundle.procFrame)
    bundle.procGlow:SetTexture(RING_TEXTURE)
    bundle.procGlow:SetBlendMode("ADD")
    bundle.procFrame:SetAlpha(0.92)
    bundle.procFrame:Hide()
    bundle.procPulse = bundle.procFrame:CreateAnimationGroup()
    if type(bundle.procPulse.SetLooping) == "function" then bundle.procPulse:SetLooping("BOUNCE") end
    local pulse = bundle.procPulse:CreateAnimation("Alpha")
    pulse:SetFromAlpha(0.58)
    pulse:SetToAlpha(1)
    pulse:SetDuration(0.55)

    self.visuals[button] = bundle
    self.stats.visualBundles = self.stats.visualBundles + 1
    return bundle
end

function Runtime:EnsureAlertState(bundle, frame)
    local state = bundle.alertStates[frame]
    if state then return state end
    state = {
        originalAlpha = type(frame.GetAlpha) == "function" and frame:GetAlpha() or 1,
    }
    bundle.alertStates[frame] = state
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            if Runtime.enabled == true then Runtime:ApplyProcStyle(bundle) end
        end)
        frame:HookScript("OnHide", function()
            if Runtime.enabled == true then Runtime:ApplyProcStyle(bundle) end
        end)
    end
    return state
end

function Runtime:ApplyProcStyle(bundle, forceShown)
    if not bundle then return end
    local style = setting("proc_style") or "match"
    local matchRound = style == "match" and setting("icon_shape") == "round"
    local hideNative = style == "hidden" or matchRound
    local anyShown = forceShown == true
    for _, frame in ipairs(alertFrames(bundle.button)) do
        local state = self:EnsureAlertState(bundle, frame)
        setRegionAlpha(frame, hideNative and 0 or state.originalAlpha)
        if type(frame.IsShown) == "function" and frame:IsShown() then anyShown = true end
    end
    local showCustom = matchRound and anyShown
    bundle.procFrame:SetShown(showCustom)
    if showCustom then
        if type(bundle.procPulse.IsPlaying) ~= "function" or not bundle.procPulse:IsPlaying() then
            bundle.procPulse:Play()
        end
    else
        bundle.procPulse:Stop()
    end
end

function Runtime:RestoreProcStyle(bundle)
    if not bundle then return end
    for frame, state in pairs(bundle.alertStates or {}) do
        setRegionAlpha(frame, state.originalAlpha)
    end
    bundle.procPulse:Stop()
    bundle.procFrame:Hide()
end

function Runtime:EnsureAlertHooks()
    local manager = _G.ActionButtonSpellAlertManager
    if self.alertHooksReady and self.alertManager == manager then return end
    if not manager or type(_G.hooksecurefunc) ~= "function" then return end
    local showHooked, hideHooked = false, false
    if type(manager.ShowAlert) == "function" then
        showHooked = pcall(_G.hooksecurefunc, manager, "ShowAlert", function(_, button)
            if Runtime.enabled == true then
                Runtime:ApplyProcStyle(Runtime.visuals[button], true)
                -- BetterBlizzFrames can restore the native burst alpha after
                -- roughly a quarter second. Reassert the selected style after
                -- that compatibility window without touching the secure alert.
                C_Timer.After(0.30, function()
                    if Runtime.enabled == true then
                        Runtime:ApplyProcStyle(Runtime.visuals[button])
                    end
                end)
            end
        end)
    end
    if type(manager.HideAlert) == "function" then
        hideHooked = pcall(_G.hooksecurefunc, manager, "HideAlert", function(_, button)
            if Runtime.enabled == true then
                Runtime:ApplyProcStyle(Runtime.visuals[button])
            end
        end)
    end
    self.alertManager = manager
    self.alertHooksReady = showHooked or hideHooked
end

function Runtime:ApplyText(bundle)
    if not bundle then return end
    setRegionAlpha(bundle.hotKey, setting("keybinds") == true and originalAlpha(bundle, "hotKey") or 0)
    setRegionAlpha(bundle.count, setting("counts") == true and originalAlpha(bundle, "count") or 0)
end

function Runtime:RestoreVisual(bundle)
    if not bundle then return end
    if bundle.roundApplied then
        removeMask(bundle.icon, bundle.mask)
        removeMask(bundle.ready, bundle.mask)
        removeMask(bundle.pushed, bundle.mask)
        removeMask(bundle.checked, bundle.mask)
        removeMask(bundle.highlight, bundle.mask)
        bundle.roundApplied = false
    end
    setCooldownShape(bundle, false)
    self:RestoreProcStyle(bundle)
    if bundle.originalTexCoord and type(bundle.icon.SetTexCoord) == "function" then
        bundle.icon:SetTexCoord(unpack(bundle.originalTexCoord))
    end
    for key, region in pairs({
        normal = bundle.normal,
        pushed = bundle.pushed,
        checked = bundle.checked,
        highlight = bundle.highlight,
        slotBackground = bundle.slotBackground,
        slotArt = bundle.slotArt,
        nativeCooldown = bundle.nativeCooldown,
        nativeChargeCooldown = bundle.nativeChargeCooldown,
        nativeLossCooldown = bundle.nativeLossCooldown,
        hotKey = bundle.hotKey,
        count = bundle.count,
    }) do
        setRegionAlpha(region, originalAlpha(bundle, key))
    end
    for _, ring in ipairs(bundle.rings) do ring:Hide() end
    bundle.ready:Hide()
    for _, edge in ipairs(bundle.edges) do edge:Hide() end
end

function Runtime:ApplyShape(bundle, color, groupKey)
    local shape = setting("icon_shape")
    local thickness = tonumber(setting("border_thickness")) or 2
    local offset = tonumber(setting("border_offset")) or 2
    local r, g, b, a = unpack(color)
    for _, ring in ipairs(bundle.rings) do ring:SetVertexColor(r, g, b, a) end
    bundle.ready:SetVertexColor(r, g, b, 1)
    bundle.procGlow:SetVertexColor(r, g, b, 1)
    bundle.procFrame:ClearAllPoints()
    bundle.procFrame:SetPoint("TOPLEFT", bundle.icon, "TOPLEFT", -(offset + 3), offset + 3)
    bundle.procFrame:SetPoint("BOTTOMRIGHT", bundle.icon, "BOTTOMRIGHT", offset + 3, -(offset + 3))

    -- Vaultloom owns only the replacement chrome. Blizzard's click feedback and
    -- securely-updated cooldown frames stay intact in both shapes.
    setRegionAlpha(bundle.normal, 0)
    setRegionAlpha(bundle.slotBackground, 0)
    setRegionAlpha(bundle.slotArt, 0)
    setRegionAlpha(bundle.nativeCooldown, originalAlpha(bundle, "nativeCooldown"))
    setRegionAlpha(bundle.nativeChargeCooldown, originalAlpha(bundle, "nativeChargeCooldown"))
    setRegionAlpha(bundle.nativeLossCooldown, originalAlpha(bundle, "nativeLossCooldown"))

    if shape == "round" then
        if not bundle.roundApplied then
            addMask(bundle.icon, bundle.mask)
            addMask(bundle.ready, bundle.mask)
            addMask(bundle.pushed, bundle.mask)
            addMask(bundle.checked, bundle.mask)
            addMask(bundle.highlight, bundle.mask)
            bundle.roundApplied = true
        end
        bundle.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        setRegionAlpha(bundle.pushed, originalAlpha(bundle, "pushed"))
        setRegionAlpha(bundle.checked, originalAlpha(bundle, "checked"))
        setRegionAlpha(bundle.highlight, originalAlpha(bundle, "highlight"))
        setCooldownShape(bundle, true)
        for index, ring in ipairs(bundle.rings) do
            local layerOffset = offset + ((index - 1) * 0.65)
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", bundle.icon, "TOPLEFT", -layerOffset, layerOffset)
            ring:SetPoint(
                "BOTTOMRIGHT",
                bundle.icon,
                "BOTTOMRIGHT",
                layerOffset,
                -layerOffset
            )
            ring:SetShown(groupKey ~= "none" and index <= thickness)
        end
        for _, edge in ipairs(bundle.edges) do edge:Hide() end
    else
        if bundle.roundApplied then
            removeMask(bundle.icon, bundle.mask)
            removeMask(bundle.ready, bundle.mask)
            removeMask(bundle.pushed, bundle.mask)
            removeMask(bundle.checked, bundle.mask)
            removeMask(bundle.highlight, bundle.mask)
            bundle.roundApplied = false
        end
        setCooldownShape(bundle, false)
        if bundle.originalTexCoord then bundle.icon:SetTexCoord(unpack(bundle.originalTexCoord)) end
        setRegionAlpha(bundle.pushed, originalAlpha(bundle, "pushed"))
        setRegionAlpha(bundle.checked, originalAlpha(bundle, "checked"))
        setRegionAlpha(bundle.highlight, originalAlpha(bundle, "highlight"))
        for _, ring in ipairs(bundle.rings) do ring:Hide() end
        local left, right, top, bottom = unpack(bundle.edges)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", bundle.icon, "TOPLEFT", -offset, offset)
        left:SetPoint("BOTTOMLEFT", bundle.icon, "BOTTOMLEFT", -offset, -offset)
        left:SetWidth(thickness)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", bundle.icon, "TOPRIGHT", offset, offset)
        right:SetPoint("BOTTOMRIGHT", bundle.icon, "BOTTOMRIGHT", offset, -offset)
        right:SetWidth(thickness)
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", bundle.icon, "TOPLEFT", -offset, offset)
        top:SetPoint("TOPRIGHT", bundle.icon, "TOPRIGHT", offset, offset)
        top:SetHeight(thickness)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", bundle.icon, "BOTTOMLEFT", -offset, -offset)
        bottom:SetPoint("BOTTOMRIGHT", bundle.icon, "BOTTOMRIGHT", offset, -offset)
        bottom:SetHeight(thickness)
        for _, edge in ipairs(bundle.edges) do
            edge:SetVertexColor(r, g, b, a)
            edge:SetShown(groupKey ~= "none")
        end
    end
    self:ApplyProcStyle(bundle)
end

function Runtime:ResolveActionRecord(record)
    local button, kind = record.button, record.kind
    local index = getButtonSlot(button) or record.index
    local entry = {
        button = button,
        kind = kind,
        index = index,
        slot = kind == "action" and index or nil,
        slotKey = kind .. ":" .. tostring(index or record.index or 0),
        empty = false,
    }

    if kind == "action" then
        local actionType, actionID, subType = getActionInfo(index)
        entry.actionType, entry.actionID = actionType, tonumber(actionID) or actionID
        entry.empty = actionType == nil
        if actionType == "spell" then
            entry.spellID = tonumber(actionID)
            entry.semanticKey = entry.spellID and ("spell:" .. entry.spellID) or nil
            entry.name, entry.icon = getSpellInfo(entry.spellID)
        elseif actionType == "item" then
            entry.itemID = tonumber(actionID)
            entry.semanticKey = entry.itemID and ("item:" .. entry.itemID) or nil
            entry.name, entry.icon = getItemInfo(entry.itemID)
        elseif actionType == "macro" then
            entry.name, entry.icon = safeCall(_G.GetMacroInfo, actionID)
            local macroSpell = tonumber(safeCall(_G.GetMacroSpell, actionID))
            if macroSpell then
                entry.actionType, entry.actionID, entry.spellID = "spell", macroSpell, macroSpell
                entry.semanticKey = "spell:" .. macroSpell
            else
                local _, macroItem = safeCall(_G.GetMacroItem, actionID)
                local itemID = parseItemID(macroItem)
                if itemID then
                    entry.actionType, entry.actionID, entry.itemID = "item", itemID, itemID
                    entry.semanticKey = "item:" .. itemID
                else
                    entry.semanticKey = "macro:" .. tostring(actionID)
                end
            end
        else
            entry.semanticKey = actionType and (actionType .. ":" .. tostring(actionID or subType or index)) or nil
        end
        entry.icon = entry.icon or getActionTexture(index)
    elseif kind == "pet" then
        entry.actionType = "pet"
        entry.semanticKey = "pet:" .. tostring(index)
        entry.name, entry.icon = safeCall(_G.GetPetActionInfo, index)
    elseif kind == "stance" then
        entry.actionType = "stance"
        entry.semanticKey = "stance:" .. tostring(index)
        entry.icon, _, _, entry.spellID = safeCall(_G.GetShapeshiftFormInfo, index)
        entry.name = entry.spellID and getSpellInfo(entry.spellID) or nil
    else
        entry.actionType = "possess"
        entry.semanticKey = "possess:" .. tostring(index)
        local icon = getButtonIcon(button)
        entry.icon = icon and icon:GetTexture() or nil
    end

    entry.autoGroup = Addon.ActionBarsLogic:Classify(
        entry.actionType,
        entry.actionID or entry.spellID,
        self.spellLookup
    )
    if kind == "action"
        and C_ActionBar
        and type(C_ActionBar.IsInterruptAction) == "function"
    then
        local isInterrupt = safeCall(C_ActionBar.IsInterruptAction, entry.slot)
        if not isSecret(isInterrupt) and isInterrupt == true then
            entry.autoGroup = "interrupt"
        end
    end
    entry.groupKey, entry.groupSource = Addon.ActionBarsLogic:ResolveGroup(
        entry,
        getStore(),
        setting("auto_classify") == true
    )
    return entry
end

function Runtime:UpdateReady(record, usable, noMana)
    local bundle, entry = self.visuals[record.button], record.entry
    if not bundle or not entry then return end
    local eligible = entry.groupKey == "attack_cd"
        or entry.groupKey == "def_cd"
        or entry.groupKey == "interrupt"
    if usable == nil and record.kind == "action" then
        if C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
            usable, noMana = safeCall(C_ActionBar.IsUsableAction, entry.slot)
        else
            usable, noMana = safeCall(_G.IsUsableAction, entry.slot)
        end
    end
    if isSecret(usable) or isSecret(noMana) then
        bundle.ready:Hide()
        return
    end
    bundle.ready:SetShown(
        setting("ready_highlight") == true
            and eligible
            and usable == true
            and noMana ~= true
    )
end

function Runtime:RefreshRecord(record)
    if not record or not record.button then return end
    local entry = self:ResolveActionRecord(record)
    record.entry = entry
    local bundle = self:EnsureVisual(record.button)
    if not bundle then return end
    self:ApplyShape(bundle, Addon.ActionBarsLogic:GetGroupColor(getStore(), entry.groupKey), entry.groupKey)
    self:ApplyText(bundle)
    self:UpdateReady(record)
    self.stats.buttonRefreshes = self.stats.buttonRefreshes + 1
end

function Runtime:CaptureButtonLayout(button)
    local layout = self.buttonLayouts[button]
    if layout then return layout end
    layout = {
        scale = type(button.GetScale) == "function" and button:GetScale() or 1,
        points = {},
    }
    local count = type(button.GetNumPoints) == "function" and button:GetNumPoints() or 0
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = button:GetPoint(index)
        layout.points[#layout.points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
        }
    end
    self.buttonLayouts[button] = layout
    return layout
end

function Runtime:RestoreButtonPoints(button)
    local layout = self.buttonLayouts[button]
    if not layout or type(button.ClearAllPoints) ~= "function" or type(button.SetPoint) ~= "function" then
        return
    end
    button:ClearAllPoints()
    for _, anchor in ipairs(layout.points) do
        button:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            anchor.x,
            anchor.y
        )
    end
end

local function adjustedAnchor(anchor, buttonIndex, indexByButton, spacing)
    local referenceIndex = indexByButton[anchor.relativeTo]
    if not referenceIndex then return anchor.x, anchor.y, false end
    local point = tostring(anchor.point or "")
    local relativePoint = tostring(anchor.relativePoint or "")
    local distance = math.max(1, math.abs(buttonIndex - referenceIndex))
    local adjustment = spacing * distance
    local x, y = anchor.x, anchor.y
    local changed = false

    if point:find("LEFT", 1, true) and relativePoint:find("RIGHT", 1, true) then
        x, changed = x + adjustment, true
    elseif point:find("RIGHT", 1, true) and relativePoint:find("LEFT", 1, true) then
        x, changed = x - adjustment, true
    elseif point:find("TOP", 1, true) and relativePoint:find("BOTTOM", 1, true) then
        y, changed = y + adjustment, true
    elseif point:find("BOTTOM", 1, true) and relativePoint:find("TOP", 1, true) then
        y, changed = y - adjustment, true
    elseif x ~= 0 and math.abs(x) >= math.abs(y) then
        x, changed = x + (x > 0 and adjustment or -adjustment), true
    elseif y ~= 0 then
        y, changed = y + (y > 0 and adjustment or -adjustment), true
    end
    return x, y, changed
end

function Runtime:ApplyBarSpacing(buttons, spacing)
    local indexByButton = {}
    for index, button in ipairs(buttons) do
        indexByButton[button] = index
        self:CaptureButtonLayout(button)
        self:RestoreButtonPoints(button)
    end
    if spacing == 0 then return end

    for buttonIndex, button in ipairs(buttons) do
        local layout = self.buttonLayouts[button]
        local changed, anchors = false, {}
        for _, anchor in ipairs(layout and layout.points or {}) do
            local x, y, adjusted = adjustedAnchor(anchor, buttonIndex, indexByButton, spacing)
            changed = changed or adjusted
            anchors[#anchors + 1] = {
                point = anchor.point,
                relativeTo = anchor.relativeTo,
                relativePoint = anchor.relativePoint,
                x = x,
                y = y,
            }
        end
        if changed and type(button.ClearAllPoints) == "function" and type(button.SetPoint) == "function" then
            button:ClearAllPoints()
            for _, anchor in ipairs(anchors) do
                button:SetPoint(
                    anchor.point,
                    anchor.relativeTo,
                    anchor.relativePoint,
                    anchor.x,
                    anchor.y
                )
            end
        end
    end
end

function Runtime:ApplyLayout()
    if Addon.WoWApi:IsInCombatLockdown() then
        self.layoutPending = true
        return false
    end
    local scale = (tonumber(setting("button_scale_percent")) or 100) / 100
    local spacing = tonumber(setting("button_spacing")) or 0
    for _, barRecord in ipairs(self.discoveredBars) do
        local bar, buttons = barRecord.bar, barRecord.buttons
        if bar and type(bar.SetScale) == "function" then
            local layout = self.barLayouts[bar]
            if not layout then
                layout = { scale = type(bar.GetScale) == "function" and bar:GetScale() or 1 }
                self.barLayouts[bar] = layout
            end
            bar:SetScale(layout.scale * scale)
        else
            for _, button in ipairs(buttons) do
                local layout = self:CaptureButtonLayout(button)
                if type(button.SetScale) == "function" then button:SetScale(layout.scale * scale) end
            end
        end
        self:ApplyBarSpacing(buttons, spacing)
    end
    self.layoutPending = false
    return true
end

function Runtime:RestoreLayout()
    if Addon.WoWApi:IsInCombatLockdown() then
        self.layoutPending = true
        return false
    end
    for bar, layout in pairs(self.barLayouts) do
        if bar and type(bar.SetScale) == "function" then bar:SetScale(layout.scale) end
    end
    for button, layout in pairs(self.buttonLayouts) do
        self:RestoreButtonPoints(button)
        if button and type(button.SetScale) == "function" then button:SetScale(layout.scale) end
    end
    self.layoutPending = false
    return true
end

function Runtime:RegisterButton(button, kind, index, seen)
    if not button or seen[button] then return end
    seen[button] = true
    local record = { button = button, kind = kind, index = index }
    self.registered[#self.registered + 1] = record
    self.recordByButton[button] = record
    self.kindButtons[kind] = self.kindButtons[kind] or {}
    self.kindButtons[kind][#self.kindButtons[kind] + 1] = record
    if kind == "action" then
        local slot = getButtonSlot(button)
        if slot then
            self.slotButtons[slot] = self.slotButtons[slot] or {}
            self.slotButtons[slot][#self.slotButtons[slot] + 1] = record
        end
    end
end

function Runtime:DiscoverButtons()
    self.registered = {}
    self.recordByButton = setmetatable({}, { __mode = "k" })
    self.slotButtons = {}
    self.kindButtons = {}
    self.discoveredBars = {}
    local seen = setmetatable({}, { __mode = "k" })
    for _, spec in ipairs(BAR_SPECS) do
        local bar = _G[spec.name]
        if bar and type(bar.actionButtons) == "table" then
            local buttons = {}
            for index, button in ipairs(bar.actionButtons) do
                self:RegisterButton(button, spec.kind, index, seen)
                if button then buttons[#buttons + 1] = button end
            end
            self.discoveredBars[#self.discoveredBars + 1] = {
                bar = bar,
                buttons = buttons,
            }
        end
    end
    if not _G.MainActionBar or type(_G.MainActionBar.actionButtons) ~= "table" then
        for index = 1, 12 do
            self:RegisterButton(_G["ActionButton" .. index], "action", index, seen)
        end
    end
end

function Runtime:RefreshAll()
    if self.enabled ~= true then return end
    self:DiscoverButtons()
    self:EnsureAlertHooks()
    self:ApplyLayout()
    for _, record in ipairs(self.registered) do self:RefreshRecord(record) end
    self.stats.fullRefreshes = self.stats.fullRefreshes + 1
    if self.editor and self.editor:IsShown() then self:RefreshEditor() end
end

function Runtime:ScheduleRefresh()
    if self.enabled ~= true or self.refreshQueued then return end
    self.refreshQueued = true
    self.refreshGeneration = self.refreshGeneration + 1
    local generation = self.refreshGeneration
    local refresh = function()
        if Runtime.enabled ~= true or generation ~= Runtime.refreshGeneration then return end
        Runtime.refreshQueued = false
        Runtime:RefreshAll()
    end
    C_Timer.After(
        0,
        Addon.PerformanceDiagnostics:Wrap(Runtime, "timer", "action_bars.refresh", refresh)
    )
end

function Runtime:RefreshSlot(slot)
    slot = tonumber(slot)
    if not slot or slot == 0 then self:ScheduleRefresh() return end
    for _, record in ipairs(self.slotButtons[slot] or {}) do self:RefreshRecord(record) end
end

function Runtime:RefreshKind(kind)
    for _, record in ipairs(self.kindButtons[kind] or {}) do self:RefreshRecord(record) end
end

function Runtime:RefreshCooldowns()
    for _, record in ipairs(self.registered) do
        self:UpdateReady(record)
    end
end

function Runtime:OnUsableChanged(changes)
    if isSecret(changes) or type(changes) ~= "table" then
        for _, record in ipairs(self.registered) do self:UpdateReady(record) end
        return
    end
    for _, change in ipairs(changes) do
        local slotValue = change.slot
        if not isSecret(slotValue) then
            if slotValue == nil then slotValue = change.action end
            if not isSecret(slotValue) then
                local slot = tonumber(slotValue)
                for _, record in ipairs(slot and self.slotButtons[slot] or {}) do
                    self:UpdateReady(record, change.usable, change.noMana)
                end
            end
        end
    end
end

function Runtime:GetGroupLabel(groupKey)
    return Addon.L[GROUP_LABELS[groupKey]] or groupKey
end

function Runtime:BuildEditorEntries()
    local entries = {}
    for _, record in ipairs(self.registered) do
        if record.entry and record.entry.empty ~= true then entries[#entries + 1] = record.entry end
    end
    table.sort(entries, function(left, right)
        if left.kind ~= right.kind then return left.kind < right.kind end
        return (tonumber(left.index) or 0) < (tonumber(right.index) or 0)
    end)
    self.editorEntries = entries
end

function Runtime:ApplyEditorOverride(entry, exactSlot)
    if not entry then return end
    local store = getStore()
    local overrides = exactSlot and store.slotOverrides or store.actionOverrides
    local key = exactSlot and entry.slotKey or entry.semanticKey
    if not key then return end
    local current = overrides[key] or entry.groupKey
    overrides[key] = Addon.ActionBarsLogic:CycleGroup(current)
    self:RefreshAll()
end

function Runtime:ResetEditorOverride(entry)
    if not entry then return end
    local store = getStore()
    if entry.slotKey then store.slotOverrides[entry.slotKey] = nil end
    if entry.semanticKey then store.actionOverrides[entry.semanticKey] = nil end
    self:RefreshAll()
end

function Runtime:CreateEditor()
    if self.editor then return end
    local frame = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(650, 580)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Addon.Widgets:ApplyStandardGoldFrame(frame, Addon.Assets.panelBackground)

    frame.title = Addon.Widgets:CreateLabel(frame, "GameFontNormalLarge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 18, -14)
    frame.title:SetText(Addon.L.ACTION_BARS_EDITOR_TITLE)
    frame.note = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.note:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.note:SetPoint("TOPRIGHT", -18, -42)
    frame.note:SetText(Addon.L.ACTION_BARS_EDITOR_NOTE)
    frame.note:SetWordWrap(true)
    local close = Addon.Widgets:CreateButton(frame, "×", 28, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.groups = {}
    for index, groupKey in ipairs(Addon.ActionBarsLogic.GROUP_ORDER) do
        local button = Addon.Widgets:CreateButton(frame, "", 142, 24, "row")
        local column = index <= 7 and 0 or 1
        local rowIndex = column == 0 and index or index - 7
        button:SetPoint("TOPLEFT", 18 + (column * 150), -74 - ((rowIndex - 1) * 28))
        button.groupKey = groupKey
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(self, mouseButton)
            local store = getStore()
            if mouseButton == "RightButton" then
                store.groupColors[self.groupKey] = nil
            else
                Addon.ActionBarsLogic:CycleColor(store, self.groupKey)
            end
            Runtime:RefreshAll()
        end)
        frame.groups[#frame.groups + 1] = button
    end

    frame.pageText = Addon.Widgets:CreateLabel(frame, "GameFontHighlightSmall", "CENTER")
    frame.pageText:SetPoint("TOP", 0, -272)
    local previous = Addon.Widgets:CreateButton(frame, Addon.L.ACTION_BARS_PREVIOUS, 90, 24)
    previous:SetPoint("RIGHT", frame.pageText, "LEFT", -12, 0)
    previous:SetScript("OnClick", function()
        Runtime.editorPage = math.max(1, Runtime.editorPage - 1)
        Runtime:RefreshEditor()
    end)
    local nextButton = Addon.Widgets:CreateButton(frame, Addon.L.ACTION_BARS_NEXT, 90, 24)
    nextButton:SetPoint("LEFT", frame.pageText, "RIGHT", 12, 0)
    nextButton:SetScript("OnClick", function()
        Runtime.editorPage = Runtime.editorPage + 1
        Runtime:RefreshEditor()
    end)

    for index = 1, EDITOR_ROWS do
        local row = Addon.Widgets:CreateButton(frame, "", 614, 21, "row")
        row:SetPoint("TOPLEFT", 18, -298 - ((index - 1) * 22))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.nameLabel = Addon.Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
        row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.nameLabel:SetWidth(270)
        row.metaLabel = Addon.Widgets:CreateLabel(row, "GameFontHighlightSmall", "RIGHT")
        row.metaLabel:SetPoint("RIGHT", -8, 0)
        row.metaLabel:SetWidth(290)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                Runtime:ResetEditorOverride(self.entry)
            else
                Runtime:ApplyEditorOverride(
                    self.entry,
                    type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() == true
                )
            end
        end)
        self.editorRows[index] = row
    end
    frame:SetScript("OnHide", function()
        Runtime.editorEntries = nil
    end)
    self.editor = frame
end

function Runtime:RefreshEditor()
    if not self.editor then return end
    self:BuildEditorEntries()
    local pageCount = math.max(1, math.ceil(#self.editorEntries / EDITOR_ROWS))
    self.editorPage = math.max(1, math.min(pageCount, self.editorPage))
    self.editor.pageText:SetFormattedText(
        Addon.L.ACTION_BARS_PAGE,
        self.editorPage,
        pageCount
    )
    for _, button in ipairs(self.editor.groups) do
        local color = Addon.ActionBarsLogic:GetGroupColor(getStore(), button.groupKey)
        button.label:SetText(self:GetGroupLabel(button.groupKey))
        button:SetBackdropBorderColor(unpack(color))
    end
    local offset = (self.editorPage - 1) * EDITOR_ROWS
    for index, row in ipairs(self.editorRows) do
        local entry = self.editorEntries[offset + index]
        row.entry = entry
        if entry then
            row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.nameLabel:SetText(entry.name or entry.semanticKey or entry.slotKey)
            row.metaLabel:SetText(
                tostring(entry.slotKey)
                    .. "  •  "
                    .. self:GetGroupLabel(entry.groupKey)
                    .. " ("
                    .. tostring(entry.groupSource)
                    .. ")"
            )
            row:Show()
        else
            row:Hide()
        end
    end
end

function Runtime:OpenEditor()
    if self.enabled ~= true then return end
    self:CreateEditor()
    self.editorPage = 1
    self:RefreshEditor()
    self.editor:Show()
end

function Runtime:OnEvent(eventName, ...)
    if eventName == "PLAYER_REGEN_ENABLED" then
        if self.layoutPending then self:RefreshAll() end
    elseif eventName == "ACTIONBAR_SLOT_CHANGED" then
        self:RefreshSlot(...)
    elseif eventName == "ACTION_USABLE_CHANGED" then
        self:OnUsableChanged(...)
    elseif eventName == "UPDATE_BINDINGS" or eventName == "GAME_PAD_ACTIVE_CHANGED" then
        for _, record in ipairs(self.registered) do self:ApplyText(self.visuals[record.button]) end
    elseif eventName == "PET_BAR_UPDATE"
        or eventName == "PET_BAR_SHOWGRID"
        or eventName == "PET_BAR_HIDEGRID"
    then
        self:RefreshKind("pet")
    elseif eventName == "UPDATE_SHAPESHIFT_FORM" or eventName == "UPDATE_SHAPESHIFT_FORMS" then
        self:RefreshKind("stance")
    elseif eventName == "ACTIONBAR_UPDATE_COOLDOWN"
        or eventName == "SPELL_UPDATE_COOLDOWN"
        or eventName == "BAG_UPDATE_COOLDOWN"
    then
        self:RefreshCooldowns()
    else
        self:ScheduleRefresh()
    end
end

function Runtime:OnSettingChanged(settingKey)
    if LAYOUT_SETTINGS[settingKey] and Addon.WoWApi:IsInCombatLockdown() then
        self.layoutPending = true
    end
    self:RefreshAll()
end

function Runtime:OnSettingsReset()
    self:RefreshAll()
end

function Runtime:ResetSettingValues()
end

function Runtime:OnAction(actionKey)
    if actionKey == "open_editor" then
        self:OpenEditor()
        return true
    end
    if actionKey == "reset_overrides" then
        local store = getStore()
        store.slotOverrides = {}
        store.actionOverrides = {}
        store.groupColors = {}
        self:RefreshAll()
        Addon:Print(Addon.L.ACTION_BARS_RESET_DONE)
        return true
    end
    return false
end

function Runtime:OnEnable()
    self.enabled = true
    self.refreshQueued = false
    self.layoutPending = false
    self.spellLookup = Addon.ActionBarsLogic:BuildSpellGroupLookup(getClassTag())
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "ACTIONBAR_SLOT_CHANGED",
        "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR",
        "UPDATE_VEHICLE_ACTIONBAR",
        "UPDATE_SHAPESHIFT_FORM",
        "UPDATE_SHAPESHIFT_FORMS",
        "PET_BAR_UPDATE",
        "PET_BAR_SHOWGRID",
        "PET_BAR_HIDEGRID",
        "ACTION_USABLE_CHANGED",
        "UPDATE_BINDINGS",
        "GAME_PAD_ACTIVE_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
        "SPELLS_CHANGED",
        "ACTIONBAR_UPDATE_COOLDOWN",
        "SPELL_UPDATE_COOLDOWN",
        "BAG_UPDATE_COOLDOWN",
    }) do
        Addon.EventBus:Subscribe(eventName, self, function(event, ...)
            Runtime:OnEvent(event, ...)
        end)
    end
    self:RefreshAll()
end

function Runtime:OnDisable()
    self.enabled = false
    self.refreshGeneration = self.refreshGeneration + 1
    self.refreshQueued = false
    self:RestoreLayout()
    for _, record in ipairs(self.registered) do
        self:RestoreVisual(self.visuals[record.button])
    end
    if self.editor then self.editor:Hide() end
    self.editorEntries = nil
    self.registered = {}
    self.recordByButton = setmetatable({}, { __mode = "k" })
    self.slotButtons = {}
    self.kindButtons = {}
    self.discoveredBars = {}
    self.barLayouts = setmetatable({}, { __mode = "k" })
    self.buttonLayouts = setmetatable({}, { __mode = "k" })
end

function Runtime:GetDebugStats()
    return {
        registeredButtons = #self.registered,
        visualBundles = self.stats.visualBundles,
        fullRefreshes = self.stats.fullRefreshes,
        buttonRefreshes = self.stats.buttonRefreshes,
        editorRows = #self.editorRows,
        editorEntriesRetained = self.editorEntries and #self.editorEntries or 0,
        refreshQueued = self.refreshQueued == true,
        layoutPending = self.layoutPending == true,
        discoveredBars = #self.discoveredBars,
    }
end

if not Addon.FeatureRegistry:RegisterRuntime(FEATURE_ID, Runtime) then
    error("Vaultloom could not register the Action Bars feature runtime.")
end
