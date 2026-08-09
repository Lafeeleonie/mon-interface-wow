---@diagnostic disable: undefined-global

-- 克罗兹易伤提示：4183 到 3 层时先提示准备，随后显示 12 秒易伤倒数。
do
    local L = ExBoss and ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
    local lastBarValue = nil
    local vulnTimer = nil

    local function GetBossState()
        local state = ExwindTools and ExwindTools.State or nil
        local isBoss = state and state.IsBossEncounter == true
        local encounterID = tonumber(state and state.EncounterID) or 0
        return isBoss, encounterID
    end

    local function ShowCenter(text, duration)
        if ExBoss and type(ExBoss.FlashText) == "function" then
            ExBoss:FlashText(tostring(text or ""), tonumber(duration) or 1.5, {
                channel = "central_medium",
                noAnimation = true,
            })
        end
    end

    local function ShowCenterCountdown(text, seconds, template)
        if ExBoss and type(ExBoss.FlashCountdown) == "function" then
            ExBoss:FlashCountdown(tostring(text or ""), tonumber(seconds) or 1, {
                channel = "central_medium",
                template = tostring(template or "{text} {time}"),
                key = "crawth:vulnerability",
                noAnimation = true,
            })
        else
            ShowCenter(tostring(text or ""), 1.5)
        end
    end

    local function CancelVulnTimer()
        if vulnTimer then
            vulnTimer:Cancel()
            vulnTimer = nil
        end
        if ExBoss and type(ExBoss.StopVulnerability) == "function" then
            ExBoss:StopVulnerability("crawth:vulnerability")
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("UPDATE_UI_WIDGET")
    f:SetScript("OnEvent", function(_, _, widgetInfo)
        if widgetInfo.widgetID ~= 4183 and widgetInfo.widgetID ~= 4184 then return end
        local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(widgetInfo.widgetID)
        if info then
            -- 4183 达到 3 层触发易伤提示
            if widgetInfo.widgetID == 4183 and info.barValue == 3 and lastBarValue ~= 3 then
                CancelVulnTimer()

                local isBoss, encounterID = GetBossState()
                if not isBoss then
                    ShowCenterCountdown(L["BOSS激活"], 14)
                elseif encounterID == 2564 then
                    if ExBoss and type(ExBoss.ShowVulnerability) == "function" then
                        ExBoss:ShowVulnerability(70, 2, 12, {
                            key = "crawth:vulnerability",
                            endText = L["易伤阶段结束"],
                            isActive = function()
                                local stillBoss, stillEncounterID = GetBossState()
                                return stillBoss and stillEncounterID == 2564
                            end,
                        })
                    else
                        ShowCenter(L["准备易伤阶段"], 2)
                        C_Timer.After(2, function()
                            local stillBoss, stillEncounterID = GetBossState()
                            if not (stillBoss and stillEncounterID == 2564) then
                                return
                            end
                            ShowCenterCountdown(string.format(L["%s易伤阶段"], "70%"), 12)
                            vulnTimer = C_Timer.NewTimer(12, function()
                                vulnTimer = nil
                                ShowCenter(L["易伤阶段结束"], 2)
                            end)
                        end)
                    end
                end
            end

            if widgetInfo.widgetID == 4183 then
                lastBarValue = info.barValue
            end
        end
    end)
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2564,
    dungeon = { key = "algethar_academy", name = "Algeth'ar Academy", zhCN = "艾杰斯亚学院" },
    boss = { key = "crawth", name = "Crawth", zhCN = "克罗兹" },
    healthThresholds = {
        {
            unit = "boss1",
            threshold = 75,
            lead = 5,
            text = "转阶段 {lead}%",
            transitionText = "阶段转换",
            output = "central_medium",
        },
        {
            unit = "boss1",
            threshold = 45,
            lead = 5,
            text = "转阶段 {lead}%",
            transitionText = "阶段转换",
            output = "central_medium",
        },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
