---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.IconAlertPage = ExBoss.UI.Panel.IconAlertPage or {}
local Page = ExBoss.UI.Panel.IconAlertPage

local MODULE_KEY = "ExBoss.IconAlert"

local DEFAULTS = {
    enabled = true,
    anchorX = 0,
    anchorY = -40,
    attachToCustom = false,
    customAttachTarget = "",
    growDir = "RIGHT",
    spacing = 8,
    maxVisible = 5,
    showText = true,
    font_text = {
        font = "默认",
        size = 13,
        outline = "OUTLINE",
        r = 1,
        g = 0.82,
        b = 0.2,
        a = 1,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
        x = 0,
        y = -4,
    },
    icon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 64,
        height = 64,
        x = 0,
        y = 0,
        showBorder = true,
        borderTexture = "Square Full White",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 1,
        borderPadding = 0,
    },
    glowEnabled = false,
    glowStyle = "Pixel Glow",
    glowColorR = 1,
    glowColorG = 0.82,
    glowColorB = 0,
    glowColorA = 1,
    glowFrequency = 0.25,
    glowLines = 8,
    glowScale = 1,
    glowOffset = 0,
}

local function ApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function EnsureDB()
    local db = ExwindTools.GetModuleDB and ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS) or nil
    if type(db) ~= "table" then
        ExBossDB = ExBossDB or {}
        ExBossDB.timer = ExBossDB.timer or {}
        ExBossDB.timer.iconAlert = ExBossDB.timer.iconAlert or {}
        db = ExBossDB.timer.iconAlert
    end
    ApplyDefaults(db, DEFAULTS)
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.iconAlert = ExBossDB.timer.iconAlert or {}
    ApplyDefaults(ExBossDB.timer.iconAlert, DEFAULTS)
    for k, v in pairs(db) do
        ExBossDB.timer.iconAlert[k] = v
    end
    return db
end

local function SyncLegacyTimerDB(db)
    if type(db) ~= "table" then
        return
    end
    ExBossDB = ExBossDB or {}
    ExBossDB.timer = ExBossDB.timer or {}
    ExBossDB.timer.iconAlert = ExBossDB.timer.iconAlert or {}
    local legacy = ExBossDB.timer.iconAlert
    for k in pairs(legacy) do
        legacy[k] = nil
    end
    for k, v in pairs(db) do
        if type(v) == "table" then
            local copy = {}
            for ck, cv in pairs(v) do
                copy[ck] = cv
            end
            legacy[k] = copy
        else
            legacy[k] = v
        end
    end
end

local function PublishChanged()
    SyncLegacyTimerDB(ExwindTools.GetModuleDB and ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS) or EnsureDB())
    local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
    if icon and type(icon.RefreshVisuals) == "function" then
        icon:RefreshVisuals()
    end
end

local function BuildStaticSection(parent, db)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetSize(780, 330)
    section:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    section:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    section:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["图标"])
    title:SetTextColor(1, 0.82, 0.45)

    local desc = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 10, -30)
    desc:SetPoint("RIGHT", section, "RIGHT", -10, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.82, 0.84, 0.9)
    desc:SetText(L["通用图标容器，由其他模块通过 API 推入显示条目。可选发光，并支持多个图标向左/右/上/下增长。"])

    local enabled = EXUI:CreateCheckbox(section, L["启用"], db.enabled, function(v)
        db.enabled = (v == true)
        PublishChanged()
    end)
    enabled:SetPoint("TOPLEFT", 10, -68)

    local attachEnabled = EXUI:CreateCheckbox(section, L["自由依附"], db.attachToCustom == true, function(v)
        db.attachToCustom = (v == true)
        PublishChanged()
    end)
    attachEnabled:SetPoint("TOPLEFT", 10, -104)

    local attachInput = EXUI:CreateEditBox(
        section,
        tostring(db.customAttachTarget or ""),
        360,
        32,
        L["目标路径"],
        {
            onEditFocusLost = function(text)
                db.customAttachTarget = tostring(text or "")
                PublishChanged()
            end,
            onEnter = function(text)
                db.customAttachTarget = tostring(text or "")
                PublishChanged()
            end,
        }
    )
    attachInput:SetPoint("TOPLEFT", 140, -96)

    local pickFrameBtn = EXUI:CreateButton(section, 130, 28, L["鼠标选取"], function()
        if not ExwindTools or type(ExwindTools.StartFramePicker) ~= "function" then
            return
        end
        ExwindTools:StartFramePicker(function(name)
            db.customAttachTarget = tostring(name or "")
            db.attachToCustom = true
            if attachInput and attachInput.SetText then
                attachInput:SetText(db.customAttachTarget)
            end
            if attachEnabled and attachEnabled.SetChecked then
                attachEnabled:SetChecked(true)
            end
            PublishChanged()
        end)
    end)
    pickFrameBtn:SetPoint("TOPLEFT", 520, -98)

    local growItems = {
        { L["向右"], "RIGHT" },
        { L["向左"], "LEFT" },
        { L["向上"], "UP" },
        { L["向下"], "DOWN" },
    }
    local growDir = EXUI:CreateDropdown(section, 180, L["增长方向"], growItems, db.growDir or "RIGHT", function(v)
        db.growDir = tostring(v or "RIGHT")
        PublishChanged()
    end)
    growDir:SetPoint("TOPLEFT", 10, -156)

    local spacing = EXUI:CreateSlider(section, 225, L["间距"], 0, 40, db.spacing or 8, 1, nil, function(v)
        db.spacing = tonumber(v) or 8
        PublishChanged()
    end)
    spacing:SetPoint("TOPLEFT", 220, -148)

    local maxVisible = EXUI:CreateSlider(section, 225, L["最多显示几个"], 1, 12, db.maxVisible or 5, 1, nil, function(v)
        db.maxVisible = math.floor((tonumber(v) or 5) + 0.5)
        PublishChanged()
    end)
    maxVisible:SetPoint("TOPLEFT", 460, -148)

    local showText = EXUI:CreateCheckbox(section, L["显示文本"], db.showText ~= false, function(v)
        db.showText = (v == true)
        PublishChanged()
    end)
    showText:SetPoint("TOPLEFT", 10, -190)

    local anchorX = EXUI:CreateSlider(section, 225, L["水平位置 (X)"], -1000, 1000, db.anchorX or 0, 1, nil, function(v)
        db.anchorX = tonumber(v) or 0
        PublishChanged()
    end)
    anchorX:SetPoint("TOPLEFT", 220, -216)

    local anchorY = EXUI:CreateSlider(section, 225, L["垂直位置 (Y)"], -600, 600, db.anchorY or -40, 1, nil, function(v)
        db.anchorY = tonumber(v) or -40
        PublishChanged()
    end)
    anchorY:SetPoint("TOPLEFT", 460, -216)

    local editBtn = EXUI:CreateButton(section, 130, 28, L["进入编辑模式"], function()
        if ExwindTools.ToggleGlobalEditMode then
            ExwindTools:ToggleGlobalEditMode()
        end
    end)
    editBtn:SetPoint("TOPLEFT", 10, -224)

    local previewOne = EXUI:CreateButton(section, 110, 28, L["预览自己"], function()
        local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
        if icon and type(icon.Preview) == "function" then
            icon:Preview(1, 6)
        end
    end)
    previewOne:SetPoint("TOPLEFT", 10, -264)

    local previewMany = EXUI:CreateButton(section, 150, 28, L["预览当前队伍"], function()
        local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
        if icon and type(icon.Preview) == "function" then
            icon:Preview(4, 6)
        end
    end)
    previewMany:SetPoint("TOPLEFT", 130, -264)

    local stopBtn = EXUI:CreateButton(section, 120, 28, L["停止预览"], function()
        local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil
        if icon and type(icon.Hide) == "function" then
            icon:Hide()
        end
    end)
    stopBtn:SetPoint("TOPLEFT", 290, -264)

    return section
end

function Page:Render(contentFrame)
    local db = EnsureDB()
    local icon = ExBoss and ExBoss.UI and ExBoss.UI.IconAlert or nil

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_IconAlertSettingsScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetSize(1, 1)
        sf:SetScrollChild(sc)
        Page._scrollFrame = sf
        Page._scrollChild = sc
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild
    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    sc:SetParent(sf)
    sc:ClearAllPoints()
    sc:SetPoint("TOPLEFT", 0, 0)
    sc:SetWidth(math.max(820, (contentFrame:GetWidth() or 820) - 16))
    sc:SetHeight(1480)
    sc:Show()

    if ExwindTools.UI then
        ExwindTools.UI.ActivePageFrame = sc
        ExwindTools.UI.CurrentModule = MODULE_KEY
    end

    if not Page._staticSection then
        Page._staticSection = BuildStaticSection(sc, db)
        Page._staticSection:SetPoint("TOPLEFT", 10, -10)
    end

    if not Page._iconGroup and ExBoss.UI and ExBoss.UI.CreateIconGroupV2 then
        db.icon.x = 0
        db.icon.y = 0
        Page._iconGroup = ExBoss.UI.CreateIconGroupV2(sc, 780, L["图标设置"], db, "icon", PublishChanged, {
            disableOffset = true,
        })
        Page._iconGroup:SetPoint("TOPLEFT", 10, -352)
    end

    if not Page._textFontGroup and EXUI.CreateFontGroup then
        Page._textFontGroup = EXUI:CreateFontGroup(sc, 780, L["文字设置"], db.font_text, function()
            PublishChanged()
        end)
        Page._textFontGroup:SetPoint("TOPLEFT", 10, -796)
    end

    if not Page._glowGroup and EXUI.CreateGlowSettings then
        Page._glowGroup = EXUI:CreateGlowSettings(sc, 780, L["发光样式"], db, "glow", PublishChanged)
        Page._glowGroup:SetPoint("TOPLEFT", 10, -1088)
    end

    if icon and type(icon.RefreshVisuals) == "function" then
        icon:RefreshVisuals()
    end
end
