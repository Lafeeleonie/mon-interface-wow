---@diagnostic disable: undefined-global, undefined-field, need-check-nil

ExBoss.UI.Panel.PrivateAuraPage = ExBoss.UI.Panel.PrivateAuraPage or {}
local Page = ExBoss.UI.Panel.PrivateAuraPage
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local root
local listScroll
local listChild
local detailScroll
local detailChild
local headerText
local summaryText
local detailTitleText
local detailMetaText
local detailBodyText
local emptyDetailText

local entryPool = {}
local activeEntryButtons = {}
local selectedEntryKey

local function WipeArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function BuildDisplayEntries()
    local out = {}
    local registry = ExBoss.PrivateAura
    if not registry then
        return out
    end

    local raidEntries = registry:GetRaidBossEntries() or {}
    for i = 1, #raidEntries do
        local row = raidEntries[i]
        out[#out + 1] = {
            key = "raid:" .. tostring(row.encounterID),
            kind = "raid",
            label = string.format("%s - %s", tostring(row.dungeon or ""), tostring(row.boss or "")),
            subText = string.format(L["encounterID:%s  共%d个私人光环法术"], tostring(row.encounterID or "-"), tonumber(row.spellCount) or 0),
            data = row,
        }
    end

    local mplusEntries = registry:GetMplusDungeonEntries() or {}
    for i = 1, #mplusEntries do
        local row = mplusEntries[i]
        out[#out + 1] = {
            key = "mplus:" .. tostring(row.dungeon or i),
            kind = "mplus",
            label = tostring(row.dungeon or "未知大米副本"),
            subText = string.format(L["共%d个私人光环法术"], tonumber(row.spellCount) or 0),
            data = row,
        }
    end

    return out
end

local function FormatSpellLine(prefix, spell)
    local spellID = tonumber(spell.spellID) or 0
    local name = tostring(spell.name or (L["法术 "] .. tostring(spellID)))
    local sourceNPCIDs = spell.sourceNPCIDs or {}
    local npcText = (#sourceNPCIDs > 0) and table.concat(sourceNPCIDs, ", ") or "-"
    return string.format("%s[%d] %s  |  NPCID: %s", prefix or "", spellID, name, npcText)
end

local function BuildDetailText(entry)
    if not entry or not entry.data then
        return "", ""
    end

    local row = entry.data
    local lines = {}
    local meta

    if entry.kind == "raid" then
        meta = string.format(L["团本首领战  |  encounterID:%s  |  法术数:%d"],
            tostring(row.encounterID or "-"),
            tonumber(row.spellCount) or 0
        )
        local spells = row.spells or {}
        for i = 1, #spells do
            lines[#lines + 1] = FormatSpellLine("", spells[i])
        end
    else
        meta = string.format(L["大秘境副本  |  法术数:%d  |  BOSS组:%d  |  小怪法术:%d"],
            tonumber(row.spellCount) or 0,
            type(row.bosses) == "table" and #row.bosses or 0,
            row.trash and tonumber(row.trash.spellCount) or 0
        )

        local bosses = row.bosses or {}
        for i = 1, #bosses do
            local bossRow = bosses[i]
            lines[#lines + 1] = string.format(L["【%s】"], tostring(bossRow.boss or L["未知首领"]))
            local bossSpells = bossRow.spells or {}
            for j = 1, #bossSpells do
                lines[#lines + 1] = FormatSpellLine("  ", bossSpells[j])
            end
            lines[#lines + 1] = ""
        end

        local trashRow = row.trash
        if trashRow and type(trashRow.spells) == "table" and #trashRow.spells > 0 then
            lines[#lines + 1] = string.format(L["【%s】"], tostring(trashRow.label or L["小怪"]))
            for i = 1, #trashRow.spells do
                lines[#lines + 1] = FormatSpellLine("  ", trashRow.spells[i])
            end
        end
    end

    return meta, table.concat(lines, "\n")
end

local function ApplyEntryButtonState(button, selected)
    if not button or not button._bg then
        return
    end
    if selected then
        button._bg:SetColorTexture(0.10, 0.22, 0.36, 0.95)
        button._border:SetColorTexture(0.20, 0.68, 1.00, 1.00)
    else
        button._bg:SetColorTexture(0.07, 0.07, 0.09, 0.94)
        button._border:SetColorTexture(0.25, 0.25, 0.28, 1.00)
    end
end

local function RefreshDetail(entry)
    if not detailTitleText then
        return
    end
    if not entry then
        detailTitleText:SetText(L["请选择左侧一个私人光环对象"])
        detailMetaText:SetText("")
        detailBodyText:SetText("")
        emptyDetailText:Show()
        return
    end

    local meta, body = BuildDetailText(entry)
    detailTitleText:SetText(tostring(entry.label or ""))
    detailMetaText:SetText(meta or "")
    detailBodyText:SetText(body or "")
    emptyDetailText:SetShown(body == "")
    detailChild:SetHeight(math.max(
        (detailBodyText:GetStringHeight() or 0),
        emptyDetailText:IsShown() and (emptyDetailText:GetStringHeight() or 0) or 0,
        1
    ) + 8)
end

local function AcquireEntryButton(parent)
    local button = table.remove(entryPool)
    if button then
        button:SetParent(parent)
        button:Show()
        return button
    end

    button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(54)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    button._bg = button
    button._border = button

    local title = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetPoint("TOPRIGHT", button, "TOPRIGHT", -12, -8)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.86, 0.26)
    button._title = title

    local sub = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("TOPRIGHT", button, "TOPRIGHT", -12, -32)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.72, 0.76, 0.82)
    button._sub = sub

    button:SetScript("OnEnter", function(self)
        if self._entryKey ~= selectedEntryKey then
            self._bg:SetColorTexture(0.09, 0.12, 0.16, 0.98)
        end
    end)
    button:SetScript("OnLeave", function(self)
        ApplyEntryButtonState(self, self._entryKey == selectedEntryKey)
    end)

    return button
end

local function ReleaseButtons()
    for i = 1, #activeEntryButtons do
        local button = activeEntryButtons[i]
        button:Hide()
        button:SetParent(nil)
        button:SetScript("OnClick", nil)
        button._entry = nil
        button._entryKey = nil
        entryPool[#entryPool + 1] = button
    end
    WipeArray(activeEntryButtons)
end

local function RefreshList()
    if not listChild then
        return
    end

    ReleaseButtons()
    local entries = BuildDisplayEntries()
    local y = -4
    local firstEntry

    for i = 1, #entries do
        local entry = entries[i]
        local button = AcquireEntryButton(listChild)
        button:SetPoint("TOPLEFT", 4, y)
        button:SetPoint("TOPRIGHT", -4, y)
        button._title:SetText(entry.label or "")
        button._sub:SetText(entry.subText or "")
        button._entry = entry
        button._entryKey = entry.key
        button:SetScript("OnClick", function(self)
            selectedEntryKey = self._entryKey
            for j = 1, #activeEntryButtons do
                local other = activeEntryButtons[j]
                ApplyEntryButtonState(other, other._entryKey == selectedEntryKey)
            end
            RefreshDetail(self._entry)
        end)
        ApplyEntryButtonState(button, entry.key == selectedEntryKey)
        activeEntryButtons[#activeEntryButtons + 1] = button
        y = y - 58
        if not firstEntry then
            firstEntry = entry
        end
    end

    listChild:SetHeight(math.max(1, -y + 8))

    local selected
    for i = 1, #entries do
        if entries[i].key == selectedEntryKey then
            selected = entries[i]
            break
        end
    end
    if not selected then
        selected = firstEntry
        selectedEntryKey = selected and selected.key or nil
        for i = 1, #activeEntryButtons do
            local button = activeEntryButtons[i]
            ApplyEntryButtonState(button, button._entryKey == selectedEntryKey)
        end
    end

    RefreshDetail(selected)

    local raidCount = ExBoss.PrivateAura and #(ExBoss.PrivateAura:GetRaidBossEntries() or {}) or 0
    local mplusCount = ExBoss.PrivateAura and #(ExBoss.PrivateAura:GetMplusDungeonEntries() or {}) or 0
    summaryText:SetText(string.format(L["团本首领：%d  |  大米副本：%d"], raidCount, mplusCount))
end

local function CreateRoot(parent)
    if root then
        return
    end

    root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)

    local title = root:CreateFontString(nil, "OVERLAY")
    title:SetFont(ExwindTools and ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 32, "OUTLINE")
    title:SetPoint("TOPLEFT", 18, -18)
    title:SetText(L["私人光环"])
    title:SetTextColor(1, 0.86, 0.26)
    headerText = title

    local summary = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    summary:SetTextColor(0.82, 0.84, 0.88)
    summaryText = summary

    local listPane = CreateFrame("Frame", nil, root, "BackdropTemplate")
    listPane:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -14)
    listPane:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 18, 18)
    listPane:SetWidth(420)
    listPane:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    listPane:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    listPane:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    local listTitle = listPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listTitle:SetPoint("TOPLEFT", 14, -14)
    listTitle:SetText(L["对象列表"])
    listTitle:SetTextColor(1, 0.86, 0.26)

    listScroll = CreateFrame("ScrollFrame", nil, listPane, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", -4, -10)
    listScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -28, 10)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(1, 1)
    listScroll:SetScrollChild(listChild)

    local detailPane = CreateFrame("Frame", nil, root, "BackdropTemplate")
    detailPane:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 14, 0)
    detailPane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -18, 18)
    detailPane:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    detailPane:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    detailPane:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    detailTitleText = detailPane:CreateFontString(nil, "OVERLAY")
    detailTitleText:SetFont(ExwindTools and ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
    detailTitleText:SetPoint("TOPLEFT", 16, -16)
    detailTitleText:SetPoint("TOPRIGHT", -16, -16)
    detailTitleText:SetJustifyH("LEFT")
    detailTitleText:SetTextColor(1, 0.86, 0.26)

    detailMetaText = detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailMetaText:SetPoint("TOPLEFT", detailTitleText, "BOTTOMLEFT", 0, -8)
    detailMetaText:SetPoint("TOPRIGHT", -16, 0)
    detailMetaText:SetJustifyH("LEFT")
    detailMetaText:SetTextColor(0.75, 0.78, 0.84)

    detailScroll = CreateFrame("ScrollFrame", nil, detailPane, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(detailScroll)
    end
    detailScroll:SetPoint("TOPLEFT", detailMetaText, "BOTTOMLEFT", 0, -12)
    detailScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -28, 12)

    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(1, 1)
    detailScroll:SetScrollChild(detailChild)

    detailBodyText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailBodyText:SetPoint("TOPLEFT", 0, 0)
    detailBodyText:SetPoint("TOPRIGHT", -8, 0)
    detailBodyText:SetJustifyH("LEFT")
    detailBodyText:SetJustifyV("TOP")
    detailBodyText:SetTextColor(0.92, 0.92, 0.92)

    emptyDetailText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyDetailText:SetPoint("TOPLEFT", 0, 0)
    emptyDetailText:SetText(L["当前对象没有私人光环法术。"])
    emptyDetailText:SetTextColor(0.55, 0.57, 0.62)

end

function Page:Render(parent)
    CreateRoot(parent)
    if root:GetParent() ~= parent then
        root:SetParent(parent)
        root:SetAllPoints(parent)
    end
    root:Show()
    RefreshList()
end

function Page:Hide()
    if root then
        root:Hide()
    end
end
