local _, Addon = ...

local L = Addon.L
local Theme = Addon.Theme
local Widgets = Addon.Widgets
local ScrollFrames = Addon.ScrollFrames
local Assets = Addon.Assets
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local Dialog = {}
Addon.CharacterOrderDialog = Dialog

local WINDOW_WIDTH = 480
local WINDOW_HEIGHT = 590
local ROW_HEIGHT = 46
local ROW_GAP = 5
local EDGE_SIZE = 30
local SCROLL_SPEED = 280

local function unpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function copyArray(values)
    local result = {}
    for index, value in ipairs(type(values) == "table" and values or {}) do
        result[index] = value
    end
    return result
end

local function arraysEqual(a, b)
    if #a ~= #b then return false end
    for index, value in ipairs(a) do
        if b[index] ~= value then return false end
    end
    return true
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function setClassIcon(texture, classFile)
    local customIcon = Assets.classIcons and Assets.classIcons[classFile]
    if customIcon then
        texture:SetTexture(customIcon)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end

    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile]
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function setEnabled(button, enabled)
    if not button then return end
    if enabled then button:Enable() else button:Disable() end
    button:SetAlpha(enabled and 1 or 0.42)
end

function Dialog:Create(parent, callbacks)
    callbacks = callbacks or {}
    local frame = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
    frame.callbacks = callbacks
    frame.rows = {}
    frame.charactersByKey = {}
    frame.order = {}
    frame.originalOrder = {}
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel((parent and parent:GetFrameLevel() or 1) + 100)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    Widgets:ApplyStandardGoldFrame(frame, Assets.windowBackground, Theme.colors.goldDim, true)

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", 14, -10)
    frame.dragBar:SetPoint("TOPRIGHT", -58, -10)
    frame.dragBar:SetHeight(50)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    frame.title = Widgets:CreateLabel(frame, "GameFontNormalHuge", "LEFT")
    frame.title:SetPoint("TOPLEFT", 22, -18)
    frame.title:SetPoint("TOPRIGHT", -64, -18)
    frame.title:SetText(L.CHARACTER_ORDER_TITLE)
    frame.title:SetTextColor(unpackColor(Theme.colors.gold))

    frame.subtitle = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetPoint("TOPRIGHT", -24, 0)
    frame.subtitle:SetText(L.CHARACTER_ORDER_SUBTITLE)

    frame.closeButton = Widgets:CreateButton(frame, "X", 28, 26)
    frame.closeButton:SetPoint("TOPRIGHT", -18, -16)

    frame.moveLabel = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "LEFT")
    frame.moveLabel:SetPoint("TOPLEFT", 22, -75)
    frame.moveLabel:SetSize(106, 24)
    frame.moveLabel:SetText(L.CHARACTER_ORDER_MOVE)
    frame.moveLabel:SetTextColor(unpackColor(Theme.colors.muted))

    frame.moveButtons = {}
    local moveDefinitions = {
        { key = "top", label = L.CHARACTER_ORDER_TOP, width = 84 },
        { key = "up", label = L.CHARACTER_ORDER_UP, width = 62 },
        { key = "down", label = L.CHARACTER_ORDER_DOWN, width = 66 },
        { key = "bottom", label = L.CHARACTER_ORDER_BOTTOM, width = 94 },
    }
    local previousMoveButton
    for _, definition in ipairs(moveDefinitions) do
        local button = Widgets:CreateButton(frame, definition.label, definition.width, 24)
        if previousMoveButton then
            button:SetPoint("LEFT", previousMoveButton, "RIGHT", 6, 0)
        else
            button:SetPoint("LEFT", frame.moveLabel, "RIGHT", 6, 0)
        end
        button.moveAction = definition.key
        button:SetScript("OnClick", function(selfButton)
            frame:MoveSelected(selfButton.moveAction)
        end)
        frame.moveButtons[definition.key] = button
        previousMoveButton = button
    end

    frame.listPanel = Widgets:CreatePanel(frame, "inset")
    frame.listPanel:SetPoint("TOPLEFT", 18, -108)
    frame.listPanel:SetPoint("BOTTOMRIGHT", -18, 92)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame.listPanel, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 8, -8)
    frame.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    frame.scroll:EnableMouseWheel(true)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(WINDOW_WIDTH - 82, 10)
    frame.scroll:SetScrollChild(frame.list)
    frame.scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
        local range = math.max(0, tonumber(selfScroll:GetVerticalScrollRange()) or 0)
        local nextValue = (tonumber(selfScroll:GetVerticalScroll()) or 0) - (delta * (ROW_HEIGHT + ROW_GAP))
        selfScroll:SetVerticalScroll(math.max(0, math.min(range, nextValue)))
    end)

    frame.marker = CreateFrame("Frame", nil, frame.list)
    frame.marker:SetHeight(2)
    frame.marker:SetFrameLevel(frame.list:GetFrameLevel() + 20)
    frame.marker.line = frame.marker:CreateTexture(nil, "OVERLAY")
    frame.marker.line:SetAllPoints()
    frame.marker.line:SetColorTexture(unpackColor(Theme.colors.gold))
    frame.marker:Hide()

    frame.status = Widgets:CreateLabel(frame, "GameFontHighlightSmall", "CENTER")
    frame.status:SetPoint("BOTTOMLEFT", 118, 56)
    frame.status:SetPoint("BOTTOMRIGHT", -118, 56)
    frame.status:SetHeight(18)
    frame.status:SetTextColor(unpackColor(Theme.colors.gold))

    frame.azButton = Widgets:CreateButton(frame, L.CHARACTER_ORDER_AZ, 90, 28)
    frame.azButton:SetPoint("BOTTOMLEFT", 20, 20)
    frame.cancelButton = Widgets:CreateButton(frame, L.SIDEBAR_CANCEL, 100, 28)
    frame.cancelButton:SetPoint("BOTTOMRIGHT", -130, 20)
    frame.saveButton = Widgets:CreateButton(frame, L.CHARACTER_ORDER_SAVE, 100, 28)
    frame.saveButton:SetPoint("BOTTOMRIGHT", -20, 20)

    function frame:BuildOrder(characters, preferredOrder)
        self.charactersByKey = {}
        local available, result, seen = {}, {}, {}
        for _, character in ipairs(type(characters) == "table" and characters or {}) do
            if type(character) == "table" and type(character.key) == "string" and character.key ~= "" then
                self.charactersByKey[character.key] = character
                available[#available + 1] = character.key
            end
        end
        local function add(characterKey)
            if self.charactersByKey[characterKey] and not seen[characterKey] then
                result[#result + 1] = characterKey
                seen[characterKey] = true
            end
        end
        for _, characterKey in ipairs(type(preferredOrder) == "table" and preferredOrder or {}) do
            add(characterKey)
        end
        for _, characterKey in ipairs(available) do add(characterKey) end
        return result
    end

    function frame:EnsureRows(count)
        for index = #self.rows + 1, count do
            local row = Widgets:CreateButton(self.list, "", WINDOW_WIDTH - 86, ROW_HEIGHT, "row")
            row:RegisterForClicks("LeftButtonUp")
            row:RegisterForDrag("LeftButton")
            row.label:Hide()

            row.position = Widgets:CreateLabel(row, "GameFontHighlightSmall", "CENTER")
            row.position:SetPoint("LEFT", 8, 0)
            row.position:SetSize(24, ROW_HEIGHT)
            row.position:SetTextColor(unpackColor(Theme.colors.goldDim))

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(32, 32)
            row.icon:SetPoint("LEFT", 38, 0)

            row.name = Widgets:CreateLabel(row, "GameFontNormal", "LEFT")
            row.name:SetPoint("TOPLEFT", 80, -7)
            row.name:SetPoint("TOPRIGHT", -12, -7)
            row.name:SetHeight(17)
            row.name:SetWordWrap(false)
            row.name:SetMaxLines(1)

            row.meta = Widgets:CreateLabel(row, "GameFontHighlightSmall", "LEFT")
            row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.meta:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
            row.meta:SetHeight(15)
            row.meta:SetWordWrap(false)
            row.meta:SetMaxLines(1)

            row:SetScript("OnClick", function(selfRow)
                frame.selectedKey = selfRow.characterKey
                frame:RefreshSelection()
            end)
            row:SetScript("OnDragStart", function(selfRow)
                frame:BeginDrag(selfRow)
            end)
            row:SetScript("OnDragStop", function()
                frame:CommitDrag()
            end)
            self.rows[index] = row
        end
    end

    function frame:FindOrderIndex(characterKey)
        for index, orderedKey in ipairs(self.order) do
            if orderedKey == characterKey then return index end
        end
        return nil
    end

    function frame:RefreshChanged()
        self.changed = not arraysEqual(self.order, self.originalOrder)
        self.status:SetText(self.changed and L.CHARACTER_ORDER_UNSAVED or "")
        return self.changed
    end

    function frame:RefreshSelection()
        local selectedIndex = self:FindOrderIndex(self.selectedKey)
        for _, row in ipairs(self.rows) do
            Widgets:SetButtonActive(row, row.characterKey ~= nil and row.characterKey == self.selectedKey)
        end
        local count = #self.order
        setEnabled(self.moveButtons.top, selectedIndex ~= nil and selectedIndex > 1)
        setEnabled(self.moveButtons.up, selectedIndex ~= nil and selectedIndex > 1)
        setEnabled(self.moveButtons.down, selectedIndex ~= nil and selectedIndex < count)
        setEnabled(self.moveButtons.bottom, selectedIndex ~= nil and selectedIndex < count)
    end

    function frame:Refresh()
        self:EnsureRows(#self.order)
        for index, row in ipairs(self.rows) do
            local characterKey = self.order[index]
            local character = characterKey and self.charactersByKey[characterKey] or nil
            if character then
                row.characterKey = characterKey
                row.position:SetText(tostring(index))
                row.name:SetText(character.name or characterKey)
                local classR, classG, classB = Addon.WoWApi:GetClassColor(character.classFile)
                row.name:SetTextColor(classR, classG, classB, 1)
                setClassIcon(row.icon, character.classFile)
                local meta = character.realm or L.UNKNOWN
                if character.isMain then meta = meta .. "  |  " .. L.SIDEBAR_MAIN end
                if type(callbacks.isHidden) == "function" and callbacks.isHidden(characterKey) then
                    meta = meta .. "  |  " .. L.CHARACTER_ORDER_HIDDEN
                    row:SetAlpha(0.62)
                else
                    row:SetAlpha(1)
                end
                row.meta:SetText(meta)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -((index - 1) * (ROW_HEIGHT + ROW_GAP)))
                row:SetPoint("TOPRIGHT", 0, -((index - 1) * (ROW_HEIGHT + ROW_GAP)))
                row:Show()
            else
                row.characterKey = nil
                row:Hide()
            end
        end
        self.list:SetHeight(math.max(10, (#self.order * (ROW_HEIGHT + ROW_GAP)) - ROW_GAP))
        ScrollFrames:Refresh(self.scroll)
        self:RefreshChanged()
        self:RefreshSelection()
    end

    function frame:MoveKeyToIndex(characterKey, targetIndex)
        local sourceIndex = self:FindOrderIndex(characterKey)
        if not sourceIndex then return false end
        targetIndex = math.floor(tonumber(targetIndex) or sourceIndex)
        table.remove(self.order, sourceIndex)
        targetIndex = math.max(1, math.min(#self.order + 1, targetIndex))
        table.insert(self.order, targetIndex, characterKey)
        self.selectedKey = characterKey
        self:Refresh()
        return sourceIndex ~= targetIndex
    end

    function frame:MoveSelected(action)
        local sourceIndex = self:FindOrderIndex(self.selectedKey)
        if not sourceIndex then return false end
        local targetIndex = sourceIndex
        if action == "top" then
            targetIndex = 1
        elseif action == "up" then
            targetIndex = math.max(1, sourceIndex - 1)
        elseif action == "down" then
            targetIndex = math.min(#self.order, sourceIndex + 1)
        elseif action == "bottom" then
            targetIndex = #self.order
        end
        return self:MoveKeyToIndex(self.selectedKey, targetIndex)
    end

    function frame:SortAlphabetically()
        table.sort(self.order, function(a, b)
            local left, right = self.charactersByKey[a] or {}, self.charactersByKey[b] or {}
            local leftName, rightName = lower(left.name or a), lower(right.name or b)
            if leftName ~= rightName then return leftName < rightName end
            local leftRealm, rightRealm = lower(left.realm), lower(right.realm)
            if leftRealm ~= rightRealm then return leftRealm < rightRealm end
            return lower(a) < lower(b)
        end)
        self:Refresh()
        return true
    end

    function frame:ClearDropTarget()
        if self.drag then self.drag.targetIndex = nil end
        self.marker:Hide()
    end

    function frame:SetDropTarget(targetIndex, anchorRow, insertAfter)
        if not self.drag or not anchorRow then
            self:ClearDropTarget()
            return false
        end
        self.drag.targetIndex = targetIndex
        self.marker:ClearAllPoints()
        if insertAfter then
            self.marker:SetPoint("TOPLEFT", anchorRow, "BOTTOMLEFT", 0, -2)
            self.marker:SetPoint("TOPRIGHT", anchorRow, "BOTTOMRIGHT", 0, -2)
        else
            self.marker:SetPoint("BOTTOMLEFT", anchorRow, "TOPLEFT", 0, 2)
            self.marker:SetPoint("BOTTOMRIGHT", anchorRow, "TOPRIGHT", 0, 2)
        end
        self.marker:Show()
        return true
    end

    function frame:UpdateDrag(elapsed)
        if not self.drag or type(GetCursorPosition) ~= "function" then return false end
        local cursorX, cursorY = GetCursorPosition()
        local scale = type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1
        scale = math.max(0.01, tonumber(scale) or 1)
        cursorX = (tonumber(cursorX) or 0) / scale
        cursorY = (tonumber(cursorY) or 0) / scale

        local top = type(self.scroll.GetTop) == "function" and self.scroll:GetTop() or nil
        local bottom = type(self.scroll.GetBottom) == "function" and self.scroll:GetBottom() or nil
        local left = type(self.scroll.GetLeft) == "function" and self.scroll:GetLeft() or nil
        local right = type(self.scroll.GetRight) == "function" and self.scroll:GetRight() or nil
        if left and right and (cursorX < left - EDGE_SIZE or cursorX > right + EDGE_SIZE) then
            self:ClearDropTarget()
            return false
        end
        if top and bottom then
            local range = math.max(0, tonumber(self.scroll:GetVerticalScrollRange()) or 0)
            local current = math.max(0, tonumber(self.scroll:GetVerticalScroll()) or 0)
            local delta = SCROLL_SPEED * math.max(0.01, tonumber(elapsed) or 0.016)
            if cursorY >= top - EDGE_SIZE then
                self.scroll:SetVerticalScroll(math.max(0, current - delta))
            elseif cursorY <= bottom + EDGE_SIZE then
                self.scroll:SetVerticalScroll(math.min(range, current + delta))
            end
            if cursorY > top + EDGE_SIZE or cursorY < bottom - EDGE_SIZE then
                self:ClearDropTarget()
                return false
            end
        end

        local candidateIndex, lastCandidate = 0, nil
        for _, row in ipairs(self.rows) do
            if row.characterKey and row.characterKey ~= self.drag.sourceKey and row:IsShown()
                and type(row.GetTop) == "function" and type(row.GetBottom) == "function"
            then
                local rowTop, rowBottom = row:GetTop(), row:GetBottom()
                if rowTop and rowBottom then
                    candidateIndex = candidateIndex + 1
                    lastCandidate = row
                    if cursorY >= ((rowTop + rowBottom) / 2) then
                        return self:SetDropTarget(candidateIndex, row, false)
                    end
                end
            end
        end
        if lastCandidate then
            return self:SetDropTarget(candidateIndex + 1, lastCandidate, true)
        end
        self:ClearDropTarget()
        return false
    end

    function frame:BeginDrag(row)
        if self.drag or not row or not row.characterKey or #self.order < 2 then return false end
        self.selectedKey = row.characterKey
        self.drag = {
            sourceKey = row.characterKey,
            sourceRow = row,
        }
        row:SetAlpha(0.55)
        row:SetScript("OnUpdate", function(_, elapsed) frame:UpdateDrag(elapsed) end)
        self:RefreshSelection()
        self:UpdateDrag(0)
        return true
    end

    function frame:CancelDrag()
        if not self.drag then return false end
        local sourceRow = self.drag.sourceRow
        if sourceRow then
            sourceRow:SetScript("OnUpdate", nil)
            local hidden = type(callbacks.isHidden) == "function"
                and callbacks.isHidden(sourceRow.characterKey)
            sourceRow:SetAlpha(hidden and 0.62 or 1)
        end
        self.marker:Hide()
        self.drag = nil
        return true
    end

    function frame:CommitDrag()
        if not self.drag then return false end
        local sourceKey = self.drag.sourceKey
        local targetIndex = self.drag.targetIndex
        self:CancelDrag()
        if not targetIndex then return false end
        return self:MoveKeyToIndex(sourceKey, targetIndex)
    end

    function frame:Open()
        self:CancelDrag()
        local characters = type(callbacks.getCharacters) == "function" and callbacks.getCharacters() or {}
        local preferredOrder = type(callbacks.getOrder) == "function" and callbacks.getOrder() or {}
        self.order = self:BuildOrder(characters, preferredOrder)
        self.originalOrder = copyArray(self.order)
        self.selectedKey = nil
        self.scroll:SetVerticalScroll(0)
        self:Refresh()
        self:Show()
        self:Raise()
        return true
    end

    function frame:Cancel()
        self:CancelDrag()
        self.order = copyArray(self.originalOrder)
        self:Hide()
        return true
    end

    function frame:Save()
        self:CancelDrag()
        if type(callbacks.save) ~= "function" or callbacks.save(copyArray(self.order)) ~= true then
            return false
        end
        self.originalOrder = copyArray(self.order)
        self.changed = false
        self:Hide()
        return true
    end

    frame.closeButton:SetScript("OnClick", function() frame:Cancel() end)
    frame.azButton:SetScript("OnClick", function() frame:SortAlphabetically() end)
    frame.cancelButton:SetScript("OnClick", function() frame:Cancel() end)
    frame.saveButton:SetScript("OnClick", function() frame:Save() end)
    frame:SetScript("OnKeyDown", function(selfFrame, key)
        if key == "ESCAPE" then
            selfFrame:SetPropagateKeyboardInput(false)
            if not selfFrame:CancelDrag() then selfFrame:Cancel() end
        else
            selfFrame:SetPropagateKeyboardInput(true)
        end
    end)
    frame:SetScript("OnHide", function() frame:CancelDrag() end)
    frame:Hide()
    return frame
end
