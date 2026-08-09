---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.UI = ExBoss.UI or {}

local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local function EnsureIconDB(db, key)
    if type(db) ~= "table" then return nil end
    if key then
        if type(db[key]) ~= "table" then
            db[key] = {}
        end
        db = db[key]
    end
    if db.showIcon == nil then db.showIcon = true end
    if db.iconID == nil then db.iconID = nil end
    if db.reverse == nil then db.reverse = false end
    if tonumber(db.width) == nil then db.width = 64 end
    if tonumber(db.height) == nil then db.height = 64 end
    if tonumber(db.x) == nil then db.x = 0 end
    if tonumber(db.y) == nil then db.y = 0 end
    if db.showBorder == nil then db.showBorder = true end
    if db.borderTexture == nil then db.borderTexture = "Square Full White" end
    if db.borderColorR == nil then db.borderColorR = 0 end
    if db.borderColorG == nil then db.borderColorG = 0 end
    if db.borderColorB == nil then db.borderColorB = 0 end
    if db.borderColorA == nil then db.borderColorA = 1 end
    if tonumber(db.borderSize) == nil then db.borderSize = 1 end
    if tonumber(db.borderPadding) == nil then db.borderPadding = 0 end
    return db
end

function ExBoss.UI.CreateIconGroupV2(parent, width, label, db, key, onUpdate, opts)
    local iconDB = EnsureIconDB(db, key)
    if not iconDB then return nil end
    opts = type(opts) == "table" and opts or {}
    local disableOffset = (opts.disableOffset == true)
    if disableOffset then
        iconDB.x = 0
        iconDB.y = 0
    end

    local groupWidth = width or 750
    local groupHeight = 430
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(groupWidth, groupHeight)
    container:SetBackdrop(EXUI.TooltipBackdrop)
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    local header = CreateFrame("Frame", nil, container)
    header:SetSize(groupWidth, 40)
    header:SetPoint("TOPLEFT")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText(label or L["图标设置"])
    title:SetTextColor(1, 0.82, 0)

    local topLine = header:CreateTexture(nil, "ARTWORK")
    topLine:SetPoint("BOTTOMLEFT", 10, 5)
    topLine:SetPoint("BOTTOMRIGHT", -10, 5)
    topLine:SetHeight(1)
    topLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    topLine:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.5), CreateColor(1, 1, 1, 0.05))

    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight - 40)
    content:SetPoint("TOPLEFT", 0, -40)

    local col1, col2, col3 = 15, 275, 535
    local row1, row2, row3 = -25, -95, -165
    local itemW = 225

    local cbShow = EXUI:CreateCheckbox(content, L["显示图标"], iconDB.showIcon, function(c)
        iconDB.showIcon = c
        if onUpdate then onUpdate() end
    end)
    cbShow:SetPoint("TOPLEFT", col1, row1 - 5)

    local inputIcon = EXUI:CreateEditBox(
        content,
        tostring(iconDB.iconID or ""),
        itemW,
        32,
        L["图标ID (可选)"],
        {
            onEnter = function(v)
                iconDB.iconID = tonumber(v) or nil
                if onUpdate then onUpdate() end
            end,
            onEditFocusLost = function(v)
                iconDB.iconID = tonumber(v) or nil
                if onUpdate then onUpdate() end
            end,
            labelPos = "top",
        }
    )
    inputIcon:SetPoint("TOPLEFT", col2, row1 - 10)

    local cbRev = EXUI:CreateCheckbox(content, L["倒数反转"], iconDB.reverse, function(c)
        iconDB.reverse = c
        if onUpdate then onUpdate() end
    end)
    cbRev:SetPoint("TOPLEFT", col3, row1 - 5)

    local sWidth = EXUI:CreateSlider(content, itemW, L["宽度 (Width)"], 10, 300, iconDB.width or 64, 1, nil, function(v)
        iconDB.width = v
        if onUpdate then onUpdate() end
    end)
    sWidth:SetPoint("TOPLEFT", col1, row2)

    local sHeight = EXUI:CreateSlider(content, itemW, L["高度 (Height)"], 10, 300, iconDB.height or 64, 1, nil, function(v)
        iconDB.height = v
        if onUpdate then onUpdate() end
    end)
    sHeight:SetPoint("TOPLEFT", col2, row2)

    if not disableOffset then
        local sPosX = EXUI:CreateSlider(content, itemW, L["水平偏移 (X)"], -1000, 1000, iconDB.x or 0, 1, nil, function(v)
            iconDB.x = v
            if onUpdate then onUpdate() end
        end)
        sPosX:SetPoint("TOPLEFT", col1, row3)

        local sPosY = EXUI:CreateSlider(content, itemW, L["垂直偏移 (Y)"], -1000, 1000, iconDB.y or 0, 1, nil, function(v)
            iconDB.y = v
            if onUpdate then onUpdate() end
        end)
        sPosY:SetPoint("TOPLEFT", col2, row3)
    end

    local borderHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    borderHeader:SetPoint("TOPLEFT", 15, -235)
    borderHeader:SetText(L["边框"])
    borderHeader:SetTextColor(0.95, 0.82, 0.26)

    local borderLine = content:CreateTexture(nil, "ARTWORK")
    borderLine:SetPoint("TOPLEFT", borderHeader, "BOTTOMLEFT", 0, -6)
    borderLine:SetPoint("RIGHT", content, "RIGHT", -15, 0)
    borderLine:SetHeight(1)
    borderLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    borderLine:SetVertexColor(1, 1, 1, 0.12)

    local cbBorder = EXUI:CreateCheckbox(content, L["显示边框"], iconDB.showBorder, function(c)
        iconDB.showBorder = c
        if onUpdate then onUpdate() end
    end)
    cbBorder:SetPoint("TOPLEFT", col1, -270)

    local borderTexture = EXUI:CreateLSMTextureDropdown(
        content,
        "border",
        itemW,
        L["边框材质"],
        iconDB.borderTexture or "Square Full White",
        function(v)
            iconDB.borderTexture = v
            if onUpdate then onUpdate() end
        end
    )
    borderTexture:SetPoint("TOPLEFT", col2, -275)

    local borderColor = EXUI:CreateColorButton(content, L["边框颜色"], iconDB, "borderColor", true, function()
        if onUpdate then onUpdate() end
    end)
    borderColor:SetPoint("TOPLEFT", col3, -272)

    local borderSize = EXUI:CreateSlider(content, itemW, L["边框粗细"], 1, 20, iconDB.borderSize or 1, 1, nil, function(v)
        iconDB.borderSize = v
        if onUpdate then onUpdate() end
    end)
    borderSize:SetPoint("TOPLEFT", col1, -340)

    local borderPadding = EXUI:CreateSlider(content, itemW, L["边框外扩"], -20, 20, iconDB.borderPadding or 0, 1, nil, function(v)
        iconDB.borderPadding = v
        if onUpdate then onUpdate() end
    end)
    borderPadding:SetPoint("TOPLEFT", col2, -340)

    return container
end
