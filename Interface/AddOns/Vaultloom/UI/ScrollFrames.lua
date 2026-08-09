local _, Addon = ...

local Assets = Addon.Assets
local ScrollFrames = {}
Addon.ScrollFrames = ScrollFrames

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function resolveScrollBar(scrollFrame)
    if not scrollFrame then return nil end
    if scrollFrame.ScrollBar then return scrollFrame.ScrollBar end
    local name = type(scrollFrame.GetName) == "function" and scrollFrame:GetName() or nil
    return name and _G[name .. "ScrollBar"] or nil
end

local function styleArrowButton(scrollBar, button, direction)
    if not button then return end

    button:ClearAllPoints()
    if direction == "up" then
        button:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    else
        button:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
    end
    button:SetSize(16, 16)

    local normal = type(button.GetNormalTexture) == "function" and button:GetNormalTexture() or nil
    local pushed = type(button.GetPushedTexture) == "function" and button:GetPushedTexture() or nil
    local disabled = type(button.GetDisabledTexture) == "function" and button:GetDisabledTexture() or nil
    local highlight = type(button.GetHighlightTexture) == "function" and button:GetHighlightTexture() or nil
    if normal then normal:SetAlpha(0) end
    if pushed then pushed:SetAlpha(0) end
    if disabled then disabled:SetAlpha(0) end
    if highlight then highlight:SetAlpha(0) end

    if not button.vaultloomBackground then
        button.vaultloomBackground = button:CreateTexture(nil, "BACKGROUND")
        button.vaultloomBackground:SetAllPoints(button)
        button.vaultloomBackground:SetTexture(Assets.buttonNormal)

        button.vaultloomHover = button:CreateTexture(nil, "ARTWORK")
        button.vaultloomHover:SetAllPoints(button)
        button.vaultloomHover:SetTexture(Assets.buttonHover)

        button.vaultloomPressed = button:CreateTexture(nil, "ARTWORK", nil, 1)
        button.vaultloomPressed:SetAllPoints(button)
        button.vaultloomPressed:SetTexture(Assets.buttonPressed)
    end

    button.vaultloomBackground:SetVertexColor(1, 1, 1, 0.92)
    button.vaultloomHover:SetAlpha(0)
    button.vaultloomPressed:SetAlpha(0)

    if not button.vaultloomArrow then
        button.vaultloomArrow = button:CreateTexture(nil, "OVERLAY")
    end
    button.vaultloomArrow:SetTexture(direction == "up" and Assets.scrollArrowUp or Assets.scrollArrowDown)
    button.vaultloomArrow:SetSize(12, 12)
    button.vaultloomArrow:ClearAllPoints()
    button.vaultloomArrow:SetPoint("CENTER", 0, 0)
    button.vaultloomArrow:SetVertexColor(1, 1, 1, 0.96)
    button.vaultloomArrow:Show()

    if not button.vaultloomStateHooks and type(button.HookScript) == "function" then
        button:HookScript("OnEnter", function(self)
            self.vaultloomHover:SetAlpha(1)
        end)
        button:HookScript("OnLeave", function(self)
            self.vaultloomHover:SetAlpha(0)
            self.vaultloomPressed:SetAlpha(0)
        end)
        button:HookScript("OnMouseDown", function(self)
            self.vaultloomHover:SetAlpha(0)
            self.vaultloomPressed:SetAlpha(1)
        end)
        button:HookScript("OnMouseUp", function(self)
            self.vaultloomPressed:SetAlpha(0)
            self.vaultloomHover:SetAlpha(type(self.IsMouseOver) == "function" and self:IsMouseOver() and 1 or 0)
        end)
        button.vaultloomStateHooks = true
    end
end

function ScrollFrames:ClampPosition(scrollFrame, forceTop)
    if not scrollFrame then return end
    if type(scrollFrame.UpdateScrollChildRect) == "function" then
        scrollFrame:UpdateScrollChildRect()
    end

    local current = type(scrollFrame.GetVerticalScroll) == "function"
        and (tonumber(scrollFrame:GetVerticalScroll()) or 0) or 0
    local range = type(scrollFrame.GetVerticalScrollRange) == "function"
        and (tonumber(scrollFrame:GetVerticalScrollRange()) or 0) or 0
    local target = forceTop and 0 or clamp(current, 0, math.max(0, range))
    if type(scrollFrame.SetVerticalScroll) == "function" then
        scrollFrame:SetVerticalScroll(target)
    end

    local scrollBar = resolveScrollBar(scrollFrame)
    if scrollBar and type(scrollBar.SetValue) == "function" then
        scrollBar:SetValue(target)
    end
end

function ScrollFrames:UpdateVisibility(scrollFrame)
    if not scrollFrame then return false end
    local scrollBar = resolveScrollBar(scrollFrame)
    local options = scrollFrame.vaultloomScrollOptions or {}
    local range = type(scrollFrame.GetVerticalScrollRange) == "function"
        and (tonumber(scrollFrame:GetVerticalScrollRange()) or 0) or 0
    local visible = options.autoHide ~= true or range > 0.5

    if scrollBar and type(scrollBar.SetShown) == "function" then
        scrollBar:SetShown(visible)
    elseif scrollBar then
        if visible and type(scrollBar.Show) == "function" then scrollBar:Show()
        elseif not visible and type(scrollBar.Hide) == "function" then scrollBar:Hide() end
    end

    if scrollFrame.vaultloomScrollVisible ~= visible then
        scrollFrame.vaultloomScrollVisible = visible
        if type(options.onVisibilityChanged) == "function" then
            options.onVisibilityChanged(scrollFrame, visible)
        end
    end
    return visible
end

function ScrollFrames:Refresh(scrollFrame, forceTop)
    if not scrollFrame then return false end
    self:ClampPosition(scrollFrame, forceTop)
    local visible = self:UpdateVisibility(scrollFrame)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if scrollFrame then
                ScrollFrames:ClampPosition(scrollFrame, forceTop)
                ScrollFrames:UpdateVisibility(scrollFrame)
            end
        end)
    end
    return visible
end

function ScrollFrames:Style(scrollFrame, options)
    if not scrollFrame then return end
    options = options or {}
    if options.autoHide == nil then
        options.autoHide = true
    end
    scrollFrame.vaultloomScrollStyle = true
    scrollFrame.vaultloomScrollOptions = options

    local scrollBar = resolveScrollBar(scrollFrame)
    scrollFrame.vaultloomScrollBar = scrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 18, -2)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 18, 2)
        scrollBar:SetWidth(18)

        if type(scrollBar.GetRegions) == "function" then
            for _, region in ipairs({ scrollBar:GetRegions() }) do
                if region and type(region.IsObjectType) == "function" and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
        end
        if scrollBar.Track and type(scrollBar.Track.Hide) == "function" then
            scrollBar.Track:Hide()
        end

        if not scrollBar.vaultloomTrack then
            scrollBar.vaultloomTrack = CreateFrame("Frame", nil, scrollBar)
            scrollBar.vaultloomTrack:SetPoint("TOPLEFT", 3, -18)
            scrollBar.vaultloomTrack:SetPoint("BOTTOMRIGHT", -3, 18)
            scrollBar.vaultloomTrack.background = scrollBar.vaultloomTrack:CreateTexture(nil, "BACKGROUND")
            scrollBar.vaultloomTrack.background:SetAllPoints(scrollBar.vaultloomTrack)
            scrollBar.vaultloomTrack.gloss = scrollBar.vaultloomTrack:CreateTexture(nil, "ARTWORK")
            scrollBar.vaultloomTrack.gloss:SetPoint("TOPLEFT", 1, -1)
            scrollBar.vaultloomTrack.gloss:SetPoint("TOPRIGHT", -1, -1)
            scrollBar.vaultloomTrack.gloss:SetHeight(1)
            scrollBar.vaultloomTrack.gloss:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        scrollBar.vaultloomTrack.background:SetTexture(Assets.scrollTrack)
        scrollBar.vaultloomTrack.background:SetVertexColor(1, 1, 1, 0.92)
        scrollBar.vaultloomTrack.gloss:SetColorTexture(1, 1, 1, 0.02)

        local thumb = scrollBar.ThumbTexture
            or (type(scrollBar.GetThumbTexture) == "function" and scrollBar:GetThumbTexture())
        if thumb then
            thumb:SetTexture(Assets.scrollThumb)
            thumb:SetSize(12, 40)
            thumb:SetVertexColor(1, 1, 1, 0.94)
        end

        local name = type(scrollBar.GetName) == "function" and scrollBar:GetName() or nil
        styleArrowButton(
            scrollBar,
            scrollBar.ScrollUpButton or (name and _G[name .. "ScrollUpButton"]),
            "up"
        )
        styleArrowButton(
            scrollBar,
            scrollBar.ScrollDownButton or (name and _G[name .. "ScrollDownButton"]),
            "down"
        )
    end

    if not scrollFrame.vaultloomVisibilityHooks and type(scrollFrame.HookScript) == "function" then
        scrollFrame:HookScript("OnShow", function(self)
            ScrollFrames:Refresh(self)
        end)
        scrollFrame:HookScript("OnSizeChanged", function(self)
            ScrollFrames:Refresh(self)
        end)
        scrollFrame.vaultloomVisibilityHooks = true
    end
    local child = type(scrollFrame.GetScrollChild) == "function" and scrollFrame:GetScrollChild() or nil
    if child and not child.vaultloomScrollVisibilityHook and type(child.HookScript) == "function" then
        child:HookScript("OnSizeChanged", function()
            ScrollFrames:Refresh(scrollFrame)
        end)
        child.vaultloomScrollVisibilityHook = true
    end
    self:Refresh(scrollFrame)
end
