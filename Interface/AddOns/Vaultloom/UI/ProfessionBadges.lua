local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Assets = Addon.Assets
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local ProfessionBadges = {}
Addon.ProfessionBadges = ProfessionBadges

local function getProfessionKey(profession)
    if type(profession) ~= "table" then
        return nil
    end
    if type(profession.professionKey) == "string" and profession.professionKey ~= "" then
        return profession.professionKey
    end
    local skillLineID = tonumber(profession.baseSkillLineID or profession.skillLineID)
    return skillLineID
        and Addon.Data.PROFESSIONS.skillLineToKey[skillLineID]
        or nil
end

local function isPrimaryProfession(profession)
    if profession.category == "primary" then
        return true
    end
    if profession.category == "secondary" then
        return false
    end
    local slotIndex = tonumber(profession.slotIndex)
    return slotIndex ~= nil and slotIndex <= 2
end

function ProfessionBadges:GetProfessions(characterOrKey, primaryOnly)
    local character = type(characterOrKey) == "table" and characterOrKey or nil
    local characterKey = character and character.key
        or (type(characterOrKey) == "string" and characterOrKey or nil)
    local professions = character and character.professions or nil
    if type(professions) ~= "table" and characterKey then
        local record = Addon.Database:Get().characters[characterKey]
        professions = type(record) == "table"
            and type(record.identity) == "table"
            and record.identity.professions
            or nil
    end

    local result = {}
    for _, profession in ipairs(type(professions) == "table" and professions or {}) do
        if type(profession) == "table"
            and (primaryOnly ~= true or isPrimaryProfession(profession))
        then
            result[#result + 1] = profession
        end
    end
    table.sort(result, function(left, right)
        local leftSlot = tonumber(left.slotIndex) or 99
        local rightSlot = tonumber(right.slotIndex) or 99
        if leftSlot ~= rightSlot then
            return leftSlot < rightSlot
        end
        return tostring(left.name or left.professionName or "")
            < tostring(right.name or right.professionName or "")
    end)
    return result
end

function ProfessionBadges:CreateButton(parent, size)
    size = math.max(18, tonumber(size) or 24)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:RegisterForClicks("LeftButtonUp")

    button.ring = button:CreateTexture(nil, "ARTWORK")
    button.ring:SetAllPoints(button)
    button.ring:SetTexture(PORTRAIT_MASK)

    button.inner = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.inner:SetSize(size - 3, size - 3)
    button.inner:SetPoint("CENTER")
    button.inner:SetTexture(PORTRAIT_MASK)
    button.inner:SetVertexColor(0.055, 0.047, 0.038, 0.96)

    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetSize(size - 7, size - 7)
    button.icon:SetPoint("CENTER")
    if type(button.CreateMaskTexture) == "function"
        and type(button.icon.AddMaskTexture) == "function"
    then
        button.iconMask = button:CreateMaskTexture(nil, "OVERLAY")
        button.iconMask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        button.iconMask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(button.iconMask)
    end

    button:SetScript("OnClick", function(selfButton)
        if selfButton.canOpen
            and selfButton.profession
            and Addon.Professions
            and type(Addon.Professions.Open) == "function"
        then
            Addon.Professions:Open(selfButton.profession, selfButton.characterKey)
        end
    end)
    button:SetScript("OnEnter", function(selfButton)
        local profession = selfButton.profession
        if type(profession) ~= "table" or not GameTooltip then
            return
        end
        local name = profession.name or profession.professionName or L.UNKNOWN
        GameTooltip:SetOwner(selfButton, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:AddLine(
            name,
            Theme.colors.gold[1],
            Theme.colors.gold[2],
            Theme.colors.gold[3],
            true
        )
        GameTooltip:AddLine(
            isPrimaryProfession(profession)
                and L.HERO_PROFESSION_PRIMARY_LABEL
                or L.HERO_PROFESSION_SECONDARY_LABEL,
            0.72,
            0.78,
            0.88,
            true
        )
        local skillLevel = tonumber(profession.skillLevel)
        local maximum = tonumber(profession.maxSkillLevel)
        if skillLevel and maximum and maximum > 0 then
            GameTooltip:AddLine(string.format("%d/%d", skillLevel, maximum), 0.88, 0.86, 0.80, true)
        end
        GameTooltip:AddLine(
            selfButton.canOpen and L.HERO_PROFESSION_OPEN_HINT or L.HERO_PROFESSION_ALT_HINT,
            0.72,
            0.78,
            0.88,
            true
        )
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:Hide()
    return button
end

function ProfessionBadges:Apply(button, profession, characterKey, canOpen)
    if not button or type(profession) ~= "table" then
        if button then
            button.profession = nil
            button.characterKey = nil
            button.canOpen = false
            button:Hide()
        end
        return false
    end

    local professionKey = getProfessionKey(profession)
    local texture = profession.icon
        or (Assets.professionBadges and Assets.professionBadges[professionKey])
        or "Interface\\ICONS\\INV_Misc_QuestionMark"
    button.profession = profession
    button.characterKey = characterKey
    button.canOpen = canOpen == true
    button.icon:SetTexture(texture)
    button.icon:SetTexCoord(0, 1, 0, 1)
    button.ring:SetVertexColor(
        Theme.colors.gold[1],
        Theme.colors.gold[2],
        Theme.colors.gold[3],
        button.canOpen and 1 or 0.68
    )
    button:SetAlpha(button.canOpen and 1 or 0.72)
    button:Show()
    return true
end

function ProfessionBadges:Populate(container, buttons, professions, characterKey, canOpen, size, gap)
    if not container then
        return 0
    end
    buttons = buttons or {}
    professions = type(professions) == "table" and professions or {}
    size = math.max(18, tonumber(size) or 24)
    gap = math.max(0, tonumber(gap) or 5)

    local total = math.max(#professions, #buttons)
    for index = 1, total do
        local button = buttons[index]
        if not button then
            button = self:CreateButton(container, size)
            buttons[index] = button
        end
        local profession = professions[index]
        if profession then
            button:ClearAllPoints()
            button:SetPoint("LEFT", container, "LEFT", (index - 1) * (size + gap), 0)
            self:Apply(button, profession, characterKey, canOpen)
        else
            self:Apply(button, nil)
        end
    end

    local width = #professions > 0
        and ((#professions * size) + ((#professions - 1) * gap))
        or size
    container:SetSize(width, size)
    container:SetShown(#professions > 0)
    return #professions
end
