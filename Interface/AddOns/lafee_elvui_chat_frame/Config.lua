local _, addon = ...
local LECF = addon.LECF
if not LECF then return end

local E = LECF.E
local L = LECF.L

LECF.RESET_POSITION_POPUP = "LAFEE_ELVUI_CHAT_FRAME_RESET_POSITION"
LECF.RESET_ALL_POPUP = "LAFEE_ELVUI_CHAT_FRAME_RESET_ALL"

local function Disabled()
    return not LECF.db.enabled
end

function LECF:InitializeConfig()
    StaticPopupDialogs[self.RESET_POSITION_POPUP] = {
        text = L.CONFIRM_RESET_POSITION,
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, index)
            LECF:ResetMoverPosition(index)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs[self.RESET_ALL_POPUP] = {
        text = L.CONFIRM_RESET_ALL,
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            LECF:ResetAllMoverPositions()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function LECF:ShowResetPositionConfirmation(index)
    StaticPopup_Show(self.RESET_POSITION_POPUP, self:GetFrameDisplayName(index), nil, index)
end

function LECF:ShowResetAllConfirmation()
    StaticPopup_Show(self.RESET_ALL_POPUP)
end

function LECF:RefreshOptions()
    local registry = E.Libs and E.Libs.AceConfigRegistry
    if registry then
        registry:NotifyChange("ElvUI")
    end
end

function LECF:CreateFrameOptions(index)
    return {
        order = 20 + index,
        type = "group",
        name = function()
            return self:GetFrameDisplayName(index)
        end,
        hidden = function()
            return index > self.db.frameCount
        end,
        args = {
            enabled = {
                order = 1,
                type = "toggle",
                name = L.ENABLE_FRAME,
                desc = L.ENABLE_FRAME_DESC,
                get = function() return self:GetFrameConfig(index).enabled end,
                set = function(_, value)
                    self:GetFrameConfig(index).enabled = value
                    self:ScheduleApplyAll("FRAME_ENABLED")
                end,
            },
            name = {
                order = 2,
                type = "input",
                name = L.CUSTOM_NAME,
                desc = L.CUSTOM_NAME_DESC,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return self:GetFrameConfig(index).name end,
                set = function(_, value)
                    self:GetFrameConfig(index).name = strtrim(value or "")
                    self:UpdateMoverLabel(index)
                    self:RefreshOptions()
                end,
            },
            width = {
                order = 3,
                type = "range",
                name = L.WIDTH,
                min = self.MIN_WIDTH,
                max = self.MAX_WIDTH,
                step = 1,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return self:GetFrameConfig(index).width end,
                set = function(_, value)
                    self:GetFrameConfig(index).width = value
                    self:ScheduleApplyAll("SIZE_CHANGED")
                end,
            },
            height = {
                order = 4,
                type = "range",
                name = L.HEIGHT,
                min = self.MIN_HEIGHT,
                max = self.MAX_HEIGHT,
                step = 1,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return self:GetFrameConfig(index).height end,
                set = function(_, value)
                    self:GetFrameConfig(index).height = value
                    self:ScheduleApplyAll("SIZE_CHANGED")
                end,
            },
            backdrop = {
                order = 5,
                type = "toggle",
                name = L.SHOW_BACKDROP,
                desc = L.SHOW_BACKDROP_DESC,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return self:GetFrameConfig(index).backdrop end,
                set = function(_, value)
                    self:GetFrameConfig(index).backdrop = value
                    self:UpdateMoverBackdrop(index)
                end,
            },
            anchoring = {
                order = 6,
                type = "group",
                inline = true,
                name = L.ANCHORING,
                args = {
                    description = {
                        order = 1,
                        type = "description",
                        name = L.ANCHORING_DESC,
                    },
                    target = {
                        order = 2,
                        type = "select",
                        name = L.ANCHOR_TARGET,
                        desc = L.ANCHOR_TARGET_DESC,
                        values = function() return self:GetAnchorTargetValues(index) end,
                        sorting = function() return self:GetAnchorTargetOrder(index) end,
                        disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                        get = function()
                            local _, targetName = self:GetMoverAnchor(index)
                            return targetName
                        end,
                        set = function(_, value) self:SetMoverAnchor(index, "target", value) end,
                    },
                    point = {
                        order = 3,
                        type = "select",
                        name = L.FRAME_POINT,
                        values = function() return self:GetAnchorPointValues() end,
                        sorting = LECF.ANCHOR_POINTS,
                        disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                        get = function()
                            local point = self:GetMoverAnchor(index)
                            return point
                        end,
                        set = function(_, value) self:SetMoverAnchor(index, "point", value) end,
                    },
                    relativePoint = {
                        order = 4,
                        type = "select",
                        name = L.RELATIVE_POINT,
                        values = function() return self:GetAnchorPointValues() end,
                        sorting = LECF.ANCHOR_POINTS,
                        disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                        get = function()
                            local _, _, relativePoint = self:GetMoverAnchor(index)
                            return relativePoint
                        end,
                        set = function(_, value) self:SetMoverAnchor(index, "relativePoint", value) end,
                    },
                    xOffset = {
                        order = 5,
                        type = "range",
                        name = L.X_OFFSET,
                        min = -4000,
                        max = 4000,
                        step = 1,
                        disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                        get = function()
                            local _, _, _, xOffset = self:GetMoverAnchor(index)
                            return E:Round(xOffset)
                        end,
                        set = function(_, value) self:SetMoverAnchor(index, "xOffset", value) end,
                    },
                    yOffset = {
                        order = 6,
                        type = "range",
                        name = L.Y_OFFSET,
                        min = -4000,
                        max = 4000,
                        step = 1,
                        disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                        get = function()
                            local _, _, _, _, yOffset = self:GetMoverAnchor(index)
                            return E:Round(yOffset)
                        end,
                        set = function(_, value) self:SetMoverAnchor(index, "yOffset", value) end,
                    },
                },
            },
            locked = {
                order = 7,
                type = "toggle",
                name = L.LOCK_CHAT_WINDOW,
                desc = L.LOCK_CHAT_WINDOW_DESC,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return self:GetFrameConfig(index).locked end,
                set = function(_, value)
                    self:GetFrameConfig(index).locked = value
                    self:ScheduleApplyAll("LOCK_CHANGED")
                end,
            },
            chatWindow = {
                order = 8,
                type = "select",
                name = L.CHAT_WINDOW,
                desc = L.CHAT_WINDOW_DESC,
                values = function() return self:GetChatWindowValues() end,
                disabled = function() return Disabled() or not self:GetFrameConfig(index).enabled end,
                get = function() return tonumber(self:GetFrameConfig(index).chatWindowID) or 0 end,
                set = function(_, value) self:SetChatAssignment(index, value) end,
            },
            status = {
                order = 9,
                type = "description",
                name = function() return self:GetAssignmentStatus(index) end,
            },
            detach = {
                order = 10,
                type = "execute",
                name = L.DETACH,
                desc = L.DETACH_DESC,
                disabled = function()
                    return Disabled() or (tonumber(self:GetFrameConfig(index).chatWindowID) or 0) <= 0
                end,
                func = function() self:DetachSlot(index) end,
            },
            resetPosition = {
                order = 11,
                type = "execute",
                name = L.RESET_POSITION,
                desc = L.RESET_POSITION_DESC,
                disabled = Disabled,
                func = function() self:ShowResetPositionConfirmation(index) end,
            },
        },
    }
end

function LECF:RegisterOptions()
    local options = {
        order = 100,
        type = "group",
        name = L.ADDON_NAME,
        childGroups = "tab",
        args = {
            description = {
                order = 1,
                type = "description",
                name = L.ADDON_DESCRIPTION .. "\n\n" .. L.ELVUI_CHAT_RECOMMENDED,
            },
            enabled = {
                order = 2,
                type = "toggle",
                name = L.ENABLE_ADDON,
                desc = L.ENABLE_ADDON_DESC,
                get = function() return self.db.enabled end,
                set = function(_, value)
                    self.db.enabled = value
                    self:ScheduleApplyAll("ADDON_ENABLED")
                end,
            },
            frameCount = {
                order = 3,
                type = "range",
                name = L.FRAME_COUNT,
                desc = L.FRAME_COUNT_DESC,
                min = 1,
                max = self.MAX_FRAMES,
                step = 1,
                disabled = Disabled,
                get = function() return self.db.frameCount end,
                set = function(_, value)
                    self.db.frameCount = value
                    self:ScheduleApplyAll("FRAME_COUNT_CHANGED")
                    self:RefreshOptions()
                end,
            },
            openMovers = {
                order = 4,
                type = "execute",
                name = L.OPEN_MOVERS,
                desc = L.OPEN_MOVERS_DESC,
                disabled = Disabled,
                func = function() E:ToggleMoveMode("LAFEE") end,
            },
            resetAll = {
                order = 5,
                type = "execute",
                name = L.RESET_ALL,
                desc = L.RESET_ALL_DESC,
                disabled = Disabled,
                func = function() self:ShowResetAllConfirmation() end,
            },
            debug = {
                order = 6,
                type = "toggle",
                name = L.DEBUG_MODE,
                desc = L.DEBUG_MODE_DESC,
                get = function() return self.db.debug end,
                set = function(_, value) self.db.debug = value end,
            },
        },
    }

    for index = 1, self.MAX_FRAMES do
        options.args["frame" .. index] = self:CreateFrameOptions(index)
    end

    E.Options.args.lecf = options
end
