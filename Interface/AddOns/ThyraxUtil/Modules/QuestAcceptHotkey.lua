local _, ns = ...
if type(ns) ~= "table" or type(ns.ModuleRegistry) ~= "table" then
    return
end

local module = {
    id = "quest_accept_hotkey",
    name = "Dialog & Quest Accept",
    version = ns.Versions.QUEST_ACCEPT_HOTKEY,
    source = "core",
    internal = true,
    subtitle = "Confirm dialogues and quests via hotkey.",
    onboardingDescription = "Allows quest and dialogue actions via a freely selectable key.",
    previewTexture = "Interface\\AddOns\\ThyraxUtil\\Media\\Previews\\questhotkey.tga",
    events = {
        "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_DETAIL", "QUEST_PROGRESS",
        "QUEST_COMPLETE", "QUEST_FINISHED", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
    },
    defaults = {
        enabled = false,
        acceptKey = "SPACE",
        disableInInstance = true,
    },
}

-- Constants & Registry
module.CONSTANTS = {
    DEFAULT_KEY = "SPACE",
    POLL_INTERVAL = 0.1,
    MAX_DIALOGS = 4,
    MIN_STR_MATCH = 4,
    HINT_PADDING = 6,
    HINT_MAX_WIDTH = 120,

    BLACKLIST = {
        ["DEATH"] = true, ["RESURRECT"] = true, ["RESURRECT_NO_SICKNESS"] = true,
        ["RESURRECT_NO_TIMER"] = true, ["AREA_SPIRIT_HEAL"] = true,
    },

    BUTTON_ORDER = {
        "QuestFrame.AcceptButton", "QuestFrameAcceptButton",
        "QuestFrame.CompleteQuestButton", "QuestFrameCompleteQuestButton",
        "QuestFrame.CompleteButton", "QuestFrameCompleteButton",
        "QuestFrame.GoodbyeButton", "QuestFrameGoodbyeButton",
    },

    BUTTON_HINTS = {
        AcceptButton = "Accept quest",
        CompleteQuestButton = "Complete quest",
        CompleteButton = "Complete quest",
        GoodbyeButton = "Continue",
    }
}

-- Pre-allocated static tables for candidate data to prevent memory churn
local gossipArg = { selectFunc = nil, id = nil }
local candidateTarget = { source = nil, button = nil, action = nil, executeType = nil, executeArg = nil }

local function ResetCandidate()
    candidateTarget.source = nil
    candidateTarget.button = nil
    candidateTarget.action = nil
    candidateTarget.executeType = nil
    candidateTarget.executeArg = nil
    gossipArg.selectFunc = nil
    gossipArg.id = nil
end

-- Utility helpers
local function NormalizeKey(raw)
    local v = string.upper(tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if v == "" or v == "SPACEBAR" or v == " " then return module.CONSTANTS.DEFAULT_KEY end
    if v == "NONE" or v == "DISABLED" then return "" end
    return v
end

local function IsTrulyVisible(f)
    if not f or not f:IsVisible() then return false end
    if f:GetAlpha() == 0 then return false end
    -- Check for "Ghost Frames" by validating dimensions
    if (f:GetWidth() or 0) < 1 then return false end
    return true
end

local function IsUsable(b)
    return IsTrulyVisible(b) and (not b.IsEnabled or b:IsEnabled())
end

local function GetText(b)
    if not b then return "" end
    local txt = b.GetText and b:GetText() or b.Text and b.Text.GetText and b.Text:GetText() or ""
    return tostring(txt):gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsTyping()
    if not GetCurrentKeyBoardFocus then return false end
    local focus = GetCurrentKeyBoardFocus()
    return focus and focus:IsObjectType("EditBox")
end

-- Candidate Selection (Optimized to avoid table literals)
local function GetPopup()
    local s = module.settings or module.defaults
    if s.disableInInstance and ns.Compat.IsInInstance() then return nil end

    local count = tonumber(rawget(_G, "STATICPOPUP_NUMDIALOGS")) or 4
    for i = 1, count do
        local f = _G["StaticPopup" .. i]
        if f and IsTrulyVisible(f) and f.which and not module.CONSTANTS.BLACKLIST[f.which] then
            -- Check for standard buttons (Button1 is usually the 'Accept' or 'Yes' button)
            local b = f.button1 or _G["StaticPopup" .. i .. "Button1"]
            if IsUsable(b) then
                candidateTarget.source = "popup"
                candidateTarget.button = b
                candidateTarget.action = GetText(b) ~= "" and GetText(b) or "Confirm"
                candidateTarget.executeType = "click"
                candidateTarget.executeArg = b
                return candidateTarget
            end
        end
    end
    return nil
end

local function GetQuest()
    if not IsTrulyVisible(QuestFrame) then return nil end

    for _, name in ipairs(module.CONSTANTS.BUTTON_ORDER) do
        local b
        if name:find("%.") then
            -- Handle modern table-based paths (e.g., QuestFrame.AcceptButton)
            local part1, part2 = name:match("([^%.]+)%.([^%.]+)")
            if _G[part1] and _G[part1][part2] then
                b = _G[part1][part2]
            end
        else
            b = _G[name]
        end

        if IsUsable(b) then
            candidateTarget.source = "quest"
            candidateTarget.button = b
            candidateTarget.action = GetText(b) ~= "" and GetText(b) or (module.CONSTANTS.BUTTON_HINTS[name:match("[^%.]+$")] or "Accept")
            candidateTarget.executeType = "click"
            candidateTarget.executeArg = b
            return candidateTarget
        end
    end
    return nil
end

-- Static lists for gossip to avoid table churn in OnUpdate
local gossipEntries = {
    { listFunc = function() return C_GossipInfo.GetAvailableQuests() end, select = C_GossipInfo.SelectAvailableQuest,
        prefix = "Accept" },
    { listFunc = function() return C_GossipInfo.GetActiveQuests() end, select = C_GossipInfo.SelectActiveQuest,
        filter = function(q) return q.isComplete end, prefix = "Complete" },
    { listFunc = function() return C_GossipInfo.GetOptions() end, select = C_GossipInfo.SelectOption,
        filter = function(o) return not (o.disabled or o.isUnavailable) end, prefix = "Select" }
}

local function GetGossip()
    if not IsTrulyVisible(GossipFrame) or not C_GossipInfo then return nil end

    for _, group in ipairs(gossipEntries) do
        local list = group.listFunc()
        if list then
            for i, item in ipairs(list) do
                if not group.filter or group.filter(item) then
                    local id = item.questID or item.gossipOptionID
                    local name = item.title or item.questTitle or item.name
                    
                    candidateTarget.source = "gossip"
                    candidateTarget.action = name or group.prefix
                    candidateTarget.executeType = "gossip"
                    gossipArg.selectFunc = group.select
                    gossipArg.id = id
                    candidateTarget.executeArg = gossipArg

                    -- Attempt to find the specific button in the Gossip ScrollBox to attach the hint.
                    -- This solves the "selecting the window" visual issue.
                    if GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox then
                        local scrollBox = GossipFrame.GreetingPanel.ScrollBox
                        -- We iterate the children of the ScrollBox's ScrollTarget to find the button
                        -- matching our quest/option.
                        scrollBox:ForEachFrame(function(frame)
                            if frame:IsVisible() and frame.GetElementData then
                                local data = frame:GetElementData()
                                if not data then return end
                                local info = data.info
                                if data.questID == id
                                    or data.gossipOptionID == id
                                    or (info and (info.questID == id or info.gossipOptionID == id)) then
                                    candidateTarget.button = frame
                                end
                            end
                        end)
                    end

                    return candidateTarget
                end
            end
        end
    end
    return nil
end

-- Module Interface
function module:EnsureFrames()
    self.bindingOwner = self.bindingOwner or CreateFrame("Frame")
    -- SecureActionButton ensures we don't cause taints when clicking buttons
    self.acceptButton = self.acceptButton or
        CreateFrame("Button", "ThyraxHotkeyAcceptButton", UIParent, "SecureActionButtonTemplate")
    self.acceptButton:SetScript("OnClick", function() self:TryAccept() end)

    if not self.hintFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetHeight(14)
        if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme(f, { border = true, compact = true }) end
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("CENTER")
        self.hintFrame, self.hintText = f, t
    end
end

function module:TryAccept()
    if IsTyping() then return end
    local c = GetPopup() or GetQuest() or GetGossip()
    if not c then return end

    local success = false
    if c.executeType == "click" and c.executeArg then
        success = pcall(c.executeArg.Click, c.executeArg)
    elseif c.executeType == "gossip" and c.executeArg then
        success = pcall(c.executeArg.selectFunc, c.executeArg.id)
    end

    if success then self:UpdateBinding(false) end
end

function module:UpdateVisualHint(c)
    if not c or not self.hintFrame then
        if self.hintFrame then self.hintFrame:Hide() end
        return
    end

    local s = self.settings or self.defaults
    local key = NormalizeKey(s.acceptKey)
    self.hintText:SetText("[" .. key .. "]")
    self.hintFrame:SetWidth(math.max(34,
        math.min(self.hintText:GetStringWidth() + self.CONSTANTS.HINT_PADDING, self.CONSTANTS.HINT_MAX_WIDTH)))

    self.hintFrame:ClearAllPoints()
    if c.button and IsTrulyVisible(c.button) then
        if c.source == "popup" then
            self.hintFrame:SetPoint("TOP", c.button, "BOTTOM", 0, -4)
        else
            self.hintFrame:SetPoint("LEFT", c.button, "RIGHT", self.CONSTANTS.HINT_PADDING, 0)
        end
    else
        self.hintFrame:Hide()
        return
    end
    self.hintFrame:Show()
end

function module:UpdateBinding(force)
    -- Module gate: StaticPopup_Show/Hide hooks installed in OnEnable cannot
    -- be uninstalled (WoW limitation), so they keep calling UpdateBinding
    -- after the user disables the module. Without this guard the next popup
    -- would silently re-bind the override key the user thought they had
    -- turned off.
    if not self.isActive then return end

    -- ABSOLUTE SAFETY: Blizzard blocks binding changes in combat.
    -- If we are in combat, we MUST stop here and defer the update.
    if ns.Compat.IsInCombat() then
        self.pendingUpdate = true
        -- Hide the hint in combat, because we cannot update the binding.
        -- Showing it would be misleading as the hotkey won't work for new windows.
        self:UpdateVisualHint(nil)
        return
    end


    -- Global hygiene: Never bind if the escape menu is open
    if IsTrulyVisible(GameMenuFrame) then
        if self.bindingActive then
            ClearOverrideBindings(self.bindingOwner)
            self.bindingActive, self.boundKey = false, nil
        end
        if self.hintFrame then self.hintFrame:Hide() end
        return
    end

    ResetCandidate()
    local candidate = GetPopup() or GetQuest() or GetGossip()
    local key = NormalizeKey(self.settings.acceptKey)

    local isTyping = IsTyping()
    local shouldBind = candidate ~= nil and key ~= "" and not isTyping

    -- UNBIND LOGIC
    if not shouldBind and self.bindingActive then
        ClearOverrideBindings(self.bindingOwner)
        self.bindingActive, self.boundKey = false, nil
    end

    -- BIND LOGIC
    if shouldBind then
        if force or not self.bindingActive or self.boundKey ~= key then
            ClearOverrideBindings(self.bindingOwner)
            SetOverrideBindingClick(self.bindingOwner, true, key, self.acceptButton:GetName())
            self.bindingActive, self.boundKey = true, key
        end
    end

    -- Only show the hint when the key is actually bound right now. With a
    -- candidate but no binding (key set to NONE, or an EditBox has focus)
    -- the hint would advertise a hotkey that does nothing.
    self:UpdateVisualHint(shouldBind and candidate or nil)
end


function module:OnEnable(settings)
    -- isActive must be set BEFORE the UpdateBinding(true) call below, since
    -- UpdateBinding short-circuits on `not self.isActive` to keep the popup
    -- hooks (installed for the lifetime of the session) from re-binding the
    -- override key after a user-initiated disable.
    self.isActive = true
    self.settings = settings or self.defaults
    self:EnsureFrames()

    -- Hook into Blizzard's popup system to avoid polling
    if not self.hooksApplied then
        hooksecurefunc("StaticPopup_Show", function() self:UpdateBinding(false) end)
        hooksecurefunc("StaticPopup_Hide", function() self:UpdateBinding(false) end)

        -- Escape bypasses StaticPopup_Hide and hides the frame directly.
        -- Hook OnHide on each popup frame to catch that case.
        local count = tonumber(rawget(_G, "STATICPOPUP_NUMDIALOGS")) or 4
        for i = 1, count do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnHide", function() self:UpdateBinding(false) end)
            end
        end

        self.hooksApplied = true
    end

    self:UpdateBinding(true)
end


function module:OnDisable()
    self.isActive = false
    if self.bindingOwner then ClearOverrideBindings(self.bindingOwner) end
    if self.hintFrame then self.hintFrame:Hide() end
    self.bindingActive = false
end

-- Called by ModuleRegistry:ApplyModuleSettings after a setting changes via
-- the Options Panel. Without this hook the new acceptKey only became active
-- on the next popup open (because UpdateBinding ran from popup hooks), which
-- left a window where the old key remained bound after the user already
-- rebound it.
function module:ApplySettings(settings)
    self.settings = settings or self.settings or self.defaults
    if self.isActive then
        self:UpdateBinding(true)
    end
end

function module:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Force a clean state when exiting combat
        self.pendingUpdate = false
        self:UpdateBinding(true)
    else
        self:UpdateBinding(false)
    end
end

function module:GetDebugState()
    return {
        key = NormalizeKey(self.settings.acceptKey),
        active = self.bindingActive,
    }
end

function module:GetAcceptKey()
    return NormalizeKey(self.settings.acceptKey)
end

function module:HasAnyAction()
    return (GetPopup() or GetQuest() or GetGossip()) ~= nil
end

function module:HideVisualHint()
    self:UpdateVisualHint(nil)
end

ns.ModuleRegistry:Register(module)
