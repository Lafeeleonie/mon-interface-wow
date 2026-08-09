---@diagnostic disable: undefined-global, undefined-field

do
    ExBoss = ExBoss or {}
    ExBoss.UI = ExBoss.UI or {}

    local Mod = ExBoss.UI.ExtraShieldBar or {}
    ExBoss.UI.ExtraShieldBar = Mod
    local BorderUtil = ExBoss.BorderUtil

    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
    local MODULE_KEY = "ExBoss.ExtraShieldBar"
    local PREVIEW_DURATION = 3

    local DEFAULT_DB = {
        enabled = true,
        showName = true,
        showValue = true,
        anchorX = 0,
        anchorY = -170,
        growDir = "UP",
        timerBarGroup = {
            width = 260,
            height = 28,
            texture = "Melli",
            barColorR = 0.1,
            barColorG = 0.8,
            barColorB = 1.0,
            barColorA = 1,
            barBgColorR = 0,
            barBgColorG = 0,
            barBgColorB = 0,
            barBgColorA = 0.5,
            showBorder = true,
            borderTexture = "Square Full White",
            borderColorR = 0,
            borderColorG = 0,
            borderColorB = 0,
            borderColorA = 1,
            borderSize = 1,
            borderPadding = 0,
            showIcon = true,
            iconSide = "LEFT",
            iconSize = 28,
            iconOffsetX = -1,
            iconOffsetY = 0,
            showIconBorder = true,
            iconBorderTexture = "Square Full White",
            iconBorderColorR = 0,
            iconBorderColorG = 0,
            iconBorderColorB = 0,
            iconBorderColorA = 1,
            iconBorderSize = 1,
            iconBorderPadding = 0,
        },
        font_name = {
            font = "默认",
            size = 16,
            r = 1, g = 1, b = 1, a = 1,
            outline = "OUTLINE",
            shadow = false,
            shadowX = 1, shadowY = -1,
            x = 4, y = 0,
        },
        font_time = {
            font = "默认",
            size = 16,
            r = 1, g = 1, b = 1, a = 1,
            outline = "OUTLINE",
            shadow = false,
            shadowX = 1, shadowY = -1,
            x = -4, y = 0,
        },
    }

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
        LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
    end

    local anchorFrame = nil
    local shieldFrame = nil
    local shieldBar = nil
    local shieldBG = nil
    local shieldIcon = nil
    local shieldNameText = nil
    local shieldValueText = nil
    local isEditMode = false
    local styleRevision = 0
    local currentSourceKey = nil
    local currentPayload = nil
    local previewToken = 0

    local function ApplyBackdropBorder(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
        if not borderFrame or not targetFrame or not texturePath then
            return
        end
        borderFrame:SetFrameLevel(frameLevel or (targetFrame:GetFrameLevel() + 2))
        borderFrame:ClearAllPoints()
        borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
        borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)
        borderFrame:SetBackdrop({
            edgeFile = texturePath,
            edgeSize = edgeSize,
        })
        borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
        borderFrame:Show()
    end

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

    local function DB()
        local gridDB = ExwindTools and ExwindTools.GetModuleDB and ExwindTools:GetModuleDB(MODULE_KEY, DEFAULT_DB) or nil
        if type(gridDB) == "table" then
            ApplyDefaults(gridDB, DEFAULT_DB)
            ExBossDB = ExBossDB or {}
            ExBossDB.timer = ExBossDB.timer or {}
            ExBossDB.timer.extraShieldBar = ExBossDB.timer.extraShieldBar or {}
            local exdb = ExBossDB.timer.extraShieldBar
            for k, v in pairs(gridDB) do
                exdb[k] = v
            end
            return gridDB
        end

        ExBossDB = ExBossDB or {}
        ExBossDB.timer = ExBossDB.timer or {}
        ExBossDB.timer.extraShieldBar = ExBossDB.timer.extraShieldBar or {}
        local db = ExBossDB.timer.extraShieldBar
        ApplyDefaults(db, DEFAULT_DB)
        return db
    end

    local function SafeNum(v, def)
        local n = tonumber(v)
        if not n then
            return def
        end
        return n
    end

    local function IsSecretValue(value)
        return type(issecretvalue) == "function" and issecretvalue(value) == true
    end

    local function ResolveStyle()
        local db = DB()
        local style = type(db.timerBarGroup) == "table" and db.timerBarGroup or db or {}
        return {
            width = math.max(80, SafeNum(style.width, 260)),
            height = math.max(8, SafeNum(style.height, 28)),
            texture = style.texture or "Melli",
            barColorR = SafeNum(style.barColorR, 0.15),
            barColorG = SafeNum(style.barColorG, 0.85),
            barColorB = SafeNum(style.barColorB, 1.0),
            barColorA = SafeNum(style.barColorA, 1.0),
            barBgColorR = SafeNum(style.barBgColorR, 0),
            barBgColorG = SafeNum(style.barBgColorG, 0),
            barBgColorB = SafeNum(style.barBgColorB, 0),
            barBgColorA = SafeNum(style.barBgColorA, 0.5),
            showBorder = (style.showBorder ~= false),
            borderTexture = style.borderTexture or "Square Full White",
            borderColorR = SafeNum(style.borderColorR, 0),
            borderColorG = SafeNum(style.borderColorG, 0),
            borderColorB = SafeNum(style.borderColorB, 0),
            borderColorA = SafeNum(style.borderColorA, 1),
            borderSize = SafeNum(style.borderSize, 1),
            borderPadding = SafeNum(style.borderPadding, 0),
            showIcon = (style.showIcon ~= false),
            iconSide = tostring(style.iconSide or "LEFT"):upper(),
            iconSize = math.max(8, SafeNum(style.iconSize, SafeNum(style.height, 28))),
            iconOffsetX = SafeNum(style.iconOffsetX, -1),
            iconOffsetY = SafeNum(style.iconOffsetY, 0),
            showIconBorder = (style.showIconBorder ~= false),
            iconBorderTexture = style.iconBorderTexture or "Square Full White",
            iconBorderColorR = SafeNum(style.iconBorderColorR, 0),
            iconBorderColorG = SafeNum(style.iconBorderColorG, 0),
            iconBorderColorB = SafeNum(style.iconBorderColorB, 0),
            iconBorderColorA = SafeNum(style.iconBorderColorA, 1),
            iconBorderSize = SafeNum(style.iconBorderSize, 1),
            iconBorderPadding = SafeNum(style.iconBorderPadding, 0),
            growDir = tostring(db.growDir or "UP"),
        }
    end

    local function GetMediaFont(fontKey)
        local key = tostring(fontKey or "")
        if key ~= "" and LSM and type(LSM.Fetch) == "function" then
            local font = LSM:Fetch("font", key, true)
            if font and font ~= "" then
                return font
            end
        end
        return ExwindTools and ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT
    end

    local function ApplyFont(fontString, fontDB, fallbackSize)
        if not fontString then
            return
        end
        local staticDB = ExwindTools and ExwindTools.DB_Static or nil
        if staticDB and staticDB.ApplyFont and type(fontDB) == "table" then
            staticDB:ApplyFont(fontString, fontDB)
            return
        end
        fontString:SetFont(
            GetMediaFont(type(fontDB) == "table" and fontDB.font or nil),
            SafeNum(type(fontDB) == "table" and fontDB.size or nil, fallbackSize or 16),
            tostring(type(fontDB) == "table" and fontDB.outline or "OUTLINE")
        )
        fontString:SetTextColor(
            SafeNum(type(fontDB) == "table" and fontDB.r or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.g or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.b or nil, 1),
            SafeNum(type(fontDB) == "table" and fontDB.a or nil, 1)
        )
        if type(fontDB) == "table" and fontDB.shadow == false then
            fontString:SetShadowOffset(0, 0)
        else
            fontString:SetShadowOffset(
                SafeNum(type(fontDB) == "table" and fontDB.shadowX or nil, 1),
                SafeNum(type(fontDB) == "table" and fontDB.shadowY or nil, -1)
            )
            fontString:SetShadowColor(0, 0, 0, 0.9)
        end
    end

    local function SetClickThrough(frame)
        if not frame then
            return
        end
        frame:EnableMouse(false)
        if frame.SetMouseClickEnabled then pcall(frame.SetMouseClickEnabled, frame, false) end
        if frame.SetMouseMotionEnabled then pcall(frame.SetMouseMotionEnabled, frame, false) end
    end

    local function EnsureAnchorFrame()
        if anchorFrame then
            return anchorFrame
        end

        local db = DB()
        local initialHeight = math.max(20, SafeNum(db.timerBarGroup and db.timerBarGroup.height, 28))
        anchorFrame = CreateFrame("Frame", "ExBoss_ExtraShieldBar_Anchor", UIParent, "BackdropTemplate")
        anchorFrame:SetSize(math.max(140, SafeNum(db.timerBarGroup and db.timerBarGroup.width, 260)), initialHeight)
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", SafeNum(db.anchorX, 0), SafeNum(db.anchorY, -170))
        anchorFrame:SetMovable(true)
        anchorFrame:SetClampedToScreen(false)
        anchorFrame:SetFrameStrata("DIALOG")
        SetClickThrough(anchorFrame)
        anchorFrame:Hide()

        local editOverlay = anchorFrame:CreateTexture(nil, "ARTWORK")
        editOverlay:SetAllPoints()
        editOverlay:SetColorTexture(0, 0.8, 0, 0.18)
        editOverlay:Hide()
        anchorFrame.EditOverlay = editOverlay

        local editLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        editLabel:SetPoint("CENTER", anchorFrame, "CENTER")
        editLabel:SetText("|cff00ff00[" .. tostring(L["额外护盾条"]) .. "]|r")
        editLabel:Hide()
        anchorFrame.EditLabel = editLabel

        anchorFrame:SetScript("OnMouseDown", function(self, button)
            if not (ExwindTools and ExwindTools.GlobalEditMode) then return end
            if button == "LeftButton" then
                self.isMoving = true
                self:StartMoving()
            end
        end)
        anchorFrame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                self.isMoving = false
                self:StopMovingOrSizing()
                local cx, cy = UIParent:GetCenter()
                local sx, sy = self:GetCenter()
                if sx and cx then
                    local panelDB = DB()
                    panelDB.anchorX = math.floor(sx - cx)
                    panelDB.anchorY = math.floor(sy - cy)
                end
            end
        end)

        if ExwindTools and type(ExwindTools.RegisterHUD) == "function" then
            ExwindTools:RegisterHUD(MODULE_KEY, anchorFrame)
            SetClickThrough(anchorFrame)
        end
        return anchorFrame
    end

    local function ResolveAnchor()
        return EnsureAnchorFrame() or UIParent
    end

    local function EnsureShieldBar()
        if shieldFrame then
            return shieldFrame
        end

        shieldFrame = CreateFrame("Frame", "ExBoss_ExtraShieldBar_Frame", UIParent)
        shieldFrame:SetFrameStrata("DIALOG")
        shieldFrame:SetFrameLevel(200)
        shieldFrame:Hide()

        shieldBar = CreateFrame("StatusBar", nil, shieldFrame, "BackdropTemplate")
        shieldBar:SetAllPoints(shieldFrame)
        shieldBar:SetMinMaxValues(0, 1)
        shieldBar:SetValue(1)

        shieldBG = shieldBar:CreateTexture(nil, "BACKGROUND")
        shieldBG:SetAllPoints()

        shieldIcon = shieldBar:CreateTexture(nil, "OVERLAY")
        shieldIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        shieldNameText = shieldBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        shieldNameText:SetJustifyH("LEFT")

        shieldValueText = shieldBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        shieldValueText:SetJustifyH("CENTER")

        return shieldFrame
    end

    local function FormatAmount(secretValue)
        if secretValue == nil then
            return ""
        end
        if type(AbbreviateLargeNumbers) == "function" then
            local ok, text = pcall(AbbreviateLargeNumbers, secretValue)
            if ok and type(text) == "string" then
                return text
            end
        end
        if type(BreakUpLargeNumbers) == "function" then
            local ok, text = pcall(BreakUpLargeNumbers, secretValue)
            if ok and type(text) == "string" then
                return text
            end
        end
        return tostring(secretValue)
    end

    local function FormatShieldPercent(secretValue, maxValue)
        local maxNum = tonumber(maxValue) or 0
        if secretValue == nil or maxNum <= 0 then
            return ""
        end
        if type(AbbreviateNumbers) == "function" then
            local ok, text = pcall(AbbreviateNumbers, secretValue, {
                breakpointData = {
                    {
                        breakpoint = 0,
                        abbreviation = "%",
                        significandDivisor = maxNum / 100,
                        fractionDivisor = 1,
                        abbreviationIsGlobal = false,
                    },
                },
            })
            if ok and type(text) == "string" then
                return text
            end
        end
        return FormatAmount(secretValue)
    end

    local function ApplyBarStyle()
        EnsureShieldBar()
        local db = DB()
        local style = ResolveStyle()
        local anchor = ResolveAnchor()

        if anchorFrame then
            anchorFrame:SetSize(math.max(140, style.width), math.max(20, style.height))
        end

        shieldFrame:SetParent(UIParent)
        shieldFrame:ClearAllPoints()
        if style.growDir == "DOWN" then
            shieldFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        else
            shieldFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        end
        shieldFrame:SetSize(style.width, style.height)

        if shieldFrame._styleRevision == styleRevision then
            return
        end

        local tex = (LSM and type(LSM.Fetch) == "function" and LSM:Fetch("statusbar", style.texture)) or
            "Interface\\Buttons\\WHITE8X8"
        shieldBar:SetStatusBarTexture(tex)
        if shieldBar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
            shieldBar:SetFillStyle(Enum.StatusBarFillStyle.StandardNoRangeFill)
        end
        if shieldBar.SetReverseFill then
            shieldBar:SetReverseFill(false)
        end
        shieldBar:SetStatusBarColor(style.barColorR, style.barColorG, style.barColorB, style.barColorA)

        shieldBG:SetTexture(tex)
        shieldBG:SetVertexColor(style.barBgColorR, style.barBgColorG, style.barBgColorB, style.barBgColorA)

        if shieldBar.BorderFrame then
            shieldBar.BorderFrame:Hide()
        end
        if style.showBorder and style.borderTexture ~= "None" and LSM and type(LSM.Fetch) == "function" then
            local edgeTex = LSM:Fetch("border", style.borderTexture)
            if edgeTex then
                shieldBar.BorderFrame = shieldBar.BorderFrame or CreateFrame("Frame", nil, shieldBar, "BackdropTemplate")
                local pad = style.borderPadding
                ApplyBackdropBorder(
                    shieldBar.BorderFrame,
                    shieldBar,
                    edgeTex,
                    style.borderSize,
                    pad,
                    style.borderColorR,
                    style.borderColorG,
                    style.borderColorB,
                    style.borderColorA,
                    shieldBar:GetFrameLevel() + 2
                )
            end
        end

        shieldIcon:SetSize(style.iconSize, style.iconSize)
        shieldIcon:ClearAllPoints()
        if style.iconSide == "RIGHT" then
            shieldIcon:SetPoint("LEFT", shieldBar, "RIGHT", style.iconOffsetX, style.iconOffsetY)
        else
            shieldIcon:SetPoint("RIGHT", shieldBar, "LEFT", style.iconOffsetX, style.iconOffsetY)
        end
        shieldIcon:SetShown(style.showIcon ~= false)

        if shieldBar.IconBorderFrame then
            shieldBar.IconBorderFrame:Hide()
        end
        if style.showIcon ~= false and style.showIconBorder and style.iconBorderTexture ~= "None" and LSM and type(LSM.Fetch) == "function" then
            local iconEdgeTex = LSM:Fetch("border", style.iconBorderTexture)
            if iconEdgeTex then
                shieldBar.IconBorderFrame = shieldBar.IconBorderFrame or CreateFrame("Frame", nil, shieldBar, "BackdropTemplate")
                local pad = style.iconBorderPadding
                ApplyBackdropBorder(
                    shieldBar.IconBorderFrame,
                    shieldIcon,
                    iconEdgeTex,
                    style.iconBorderSize,
                    pad,
                    style.iconBorderColorR,
                    style.iconBorderColorG,
                    style.iconBorderColorB,
                    style.iconBorderColorA,
                    shieldBar:GetFrameLevel() + 2
                )
            end
        end

        ApplyFont(shieldNameText, db.font_name, 16)
        ApplyFont(shieldValueText, db.font_time, 16)

        shieldNameText:ClearAllPoints()
        shieldNameText:SetPoint("LEFT", shieldBar, "LEFT", SafeNum(db.font_name and db.font_name.x, 4), SafeNum(db.font_name and db.font_name.y, 0))
        shieldNameText:SetPoint("RIGHT", shieldValueText, "LEFT", -8, 0)
        shieldNameText:SetDrawLayer("OVERLAY", 7)

        shieldValueText:ClearAllPoints()
        shieldValueText:SetPoint("CENTER", shieldBar, "CENTER", SafeNum(db.font_time and db.font_time.x, 0), SafeNum(db.font_time and db.font_time.y, 0))
        shieldValueText:SetWidth(math.max(20, style.width - 8))
        shieldValueText:SetDrawLayer("OVERLAY", 7)

        if anchor and anchor.SetWidth then
            anchor:SetWidth(math.max(140, style.width))
        end
        shieldFrame._styleRevision = styleRevision
    end

    local function RenderPayload(payload, preview)
        EnsureAnchorFrame()
        EnsureShieldBar()
        ApplyBarStyle()

        if not preview and DB().enabled ~= true then
            shieldFrame:Hide()
            return
        end

        payload = type(payload) == "table" and payload or {}
        local db = DB()
        local value = payload.value
        local valueIsSecret = IsSecretValue(value)
        if value == nil then
            value = 0
            valueIsSecret = false
        elseif valueIsSecret ~= true then
            value = tonumber(value) or 0
        end

        local maxValue = tonumber(payload.maxValue)
        if not maxValue or maxValue <= 0 then
            if valueIsSecret == true then
                maxValue = 1
            else
                maxValue = math.max(1, tonumber(value) or 0)
            end
        end
        if valueIsSecret ~= true then
            if value < 0 then
                value = 0
            end
            if value > maxValue then
                value = maxValue
            end
        end

        if Enum and Enum.StatusBarInterpolation then
            shieldBar:SetMinMaxValues(0, maxValue, Enum.StatusBarInterpolation.Immediate)
            shieldBar:SetValue(value, Enum.StatusBarInterpolation.Immediate)
        else
            shieldBar:SetMinMaxValues(0, maxValue)
            shieldBar:SetValue(value)
        end
        if type(shieldBar.SetToTargetValue) == "function" then
            shieldBar:SetToTargetValue()
        end

        shieldIcon:SetTexture(payload.icon or 136197)

        if db.showName ~= false then
            shieldNameText:SetText(tostring(payload.name or L["护盾"]))
            shieldNameText:Show()
        else
            shieldNameText:SetText("")
            shieldNameText:Hide()
        end

        if db.showValue ~= false then
            shieldValueText:SetText(tostring(payload.text or FormatShieldPercent(value, maxValue)))
            shieldValueText:Show()
        else
            shieldValueText:SetText("")
            shieldValueText:Hide()
        end

        shieldFrame:Show()
    end

    local function ShowEditPreview()
        RenderPayload({
            name = L["护盾"],
            icon = 136197,
            value = 68,
            maxValue = 100,
            text = "68%",
        }, true)
    end

    local function SetEditMode(enabled)
        EnsureAnchorFrame()
        isEditMode = enabled == true
        if isEditMode then
            anchorFrame:EnableMouse(true)
            if anchorFrame.SetMouseClickEnabled then pcall(anchorFrame.SetMouseClickEnabled, anchorFrame, true) end
            if anchorFrame.SetMouseMotionEnabled then pcall(anchorFrame.SetMouseMotionEnabled, anchorFrame, true) end
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Show() end
            if anchorFrame.EditLabel then anchorFrame.EditLabel:Show() end
            anchorFrame:Show()
            ShowEditPreview()
        else
            SetClickThrough(anchorFrame)
            if anchorFrame.EditOverlay then anchorFrame.EditOverlay:Hide() end
            if anchorFrame.EditLabel then anchorFrame.EditLabel:Hide() end
            anchorFrame:Hide()
            if currentPayload and DB().enabled == true then
                RenderPayload(currentPayload, false)
            elseif shieldFrame then
                shieldFrame:Hide()
            end
        end
    end

    function Mod:IsEditMode()
        return isEditMode == true
    end

    function Mod:RefreshVisuals()
        styleRevision = styleRevision + 1
        EnsureAnchorFrame()
        EnsureShieldBar()
        if isEditMode then
            ShowEditPreview()
        elseif currentPayload and DB().enabled == true then
            RenderPayload(currentPayload, false)
        else
            ApplyBarStyle()
            if shieldFrame then
                shieldFrame:Hide()
            end
        end
    end

    function Mod:Preview(duration)
        previewToken = previewToken + 1
        local token = previewToken
        if isEditMode then
            ShowEditPreview()
            return
        end
        ShowEditPreview()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(tonumber(duration) or PREVIEW_DURATION, function()
                if previewToken ~= token or isEditMode then
                    return
                end
                if currentPayload and DB().enabled == true then
                    RenderPayload(currentPayload, false)
                elseif shieldFrame then
                    shieldFrame:Hide()
                end
            end)
        end
    end

    function Mod:Show(sourceKey, payload)
        currentSourceKey = tostring(sourceKey or MODULE_KEY)
        currentPayload = type(payload) == "table" and payload or nil
        if isEditMode then
            return
        end
        if not currentPayload or DB().enabled ~= true then
            if shieldFrame then
                shieldFrame:Hide()
            end
            return
        end
        RenderPayload(currentPayload, false)
    end

    function Mod:Update(sourceKey, payload)
        self:Show(sourceKey, payload)
    end

    function Mod:Hide(sourceKey)
        if sourceKey ~= nil and tostring(sourceKey) ~= tostring(currentSourceKey or "") then
            return
        end
        currentSourceKey = nil
        currentPayload = nil
        if isEditMode then
            ShowEditPreview()
        elseif shieldFrame then
            shieldFrame:Hide()
        end
    end

    function Mod:EnterEditMode()
        EnsureAnchorFrame()
        if ExwindTools and ExwindTools.GlobalEditMode ~= true and type(ExwindTools.ToggleGlobalEditMode) == "function" then
            ExwindTools:ToggleGlobalEditMode()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    SetEditMode(true)
                end)
            else
                SetEditMode(true)
            end
            return true
        end
        SetEditMode(true)
        return true
    end

    function Mod:ExitEditMode()
        SetEditMode(false)
        if ExwindTools and ExwindTools.GlobalEditMode == true and type(ExwindTools.ToggleGlobalEditMode) == "function" then
            ExwindTools:ToggleGlobalEditMode()
            return true
        end
        return true
    end

    function Mod:ToggleEditMode()
        if self:IsEditMode() then
            return self:ExitEditMode()
        end
        return self:EnterEditMode()
    end

    EnsureAnchorFrame()
    EnsureShieldBar()

    if ExwindTools and type(ExwindTools.RegisterEditModeCallback) == "function" then
        ExwindTools:RegisterEditModeCallback(MODULE_KEY, function(active)
            if ExwindTools.GlobalEditMode == true and active == true then
                SetEditMode(true)
            elseif isEditMode then
                SetEditMode(false)
            end
        end)
    end
end
