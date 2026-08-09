---@diagnostic disable: undefined-global
-- =============================================================
-- ExBoss — 全局命名空间初始化（最先加载）
-- 测试 4:08
-- =============================================================

ExBoss = ExBoss or {}
if not _G.UnitDisplayID then _G.UnitDisplayID = function() return 0 end end
local meta = _G.ExBoss_MetaData or { version = "DEV-Build" }
ExBoss.MetaData = meta
ExBoss.VERSION  = tostring(meta.version or "DEV-Build")

-- 子模块挂载点（预建，防止子模块因顺序问题拿到 nil）
ExBoss.Voice    = ExBoss.Voice    or {}
ExBoss.Voice.Engine = ExBoss.Voice.Engine or {}
ExBoss.Voice.OtherSounds = ExBoss.Voice.OtherSounds or {}
ExBoss.Voice.Profiles = ExBoss.Voice.Profiles or {}
ExBoss.Voice.ImportExport = ExBoss.Voice.ImportExport or {}
ExBoss.Timeline = ExBoss.Timeline or {}
ExBoss.MDT      = ExBoss.MDT      or {}
ExBoss.UI       = ExBoss.UI       or {}
ExBoss.UI.TimerBar   = ExBoss.UI.TimerBar   or {}
ExBoss.UI.BunBar     = ExBoss.UI.BunBar     or {}
ExBoss.UI.RingProgress = ExBoss.UI.RingProgress or {}
ExBoss.UI.IconAlert = ExBoss.UI.IconAlert or {}
ExBoss.UI.CastProgressBar = ExBoss.UI.CastProgressBar or {}
ExBoss.UI.Countdown  = ExBoss.UI.Countdown  or {}
ExBoss.UI.FlashText  = ExBoss.UI.FlashText  or {}
ExBoss.UI.FlashTextMedium = ExBoss.UI.FlashTextMedium or {}
ExBoss.UI.HeadAlert  = ExBoss.UI.HeadAlert  or {}
ExBoss.UI.Panel      = ExBoss.UI.Panel      or {}
ExBoss.UI.Panel.MDTPage = ExBoss.UI.Panel.MDTPage or {}
ExBoss.UI.Panel.OtherVoicePage = ExBoss.UI.Panel.OtherVoicePage or {}
ExBoss.UI.Panel.ImportExportPage = ExBoss.UI.Panel.ImportExportPage or {}
ExBoss.UI.Panel.ToolsPage = ExBoss.UI.Panel.ToolsPage or {}
ExBoss.Data     = ExBoss.Data     or {}
ExBoss.DB       = ExBoss.DB       or {}
ExBoss.Export   = ExBoss.Export   or {}
ExBoss.Modules  = ExBoss.Modules  or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}
ExBoss.BossEncounters = ExBoss.BossEncounters or {}
ExBoss.PrivateAura = ExBoss.PrivateAura or {}
ExBoss.BossConfig = ExBoss.BossConfig or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}
ExBoss.TargetAlert = ExBoss.TargetAlert or {}
ExBoss.Debug = ExBoss.Debug or {}
ExBoss.Debug.AIVoice = ExBoss.Debug.AIVoice or { enabled = false }
ExBoss.Debug.CastBar = ExBoss.Debug.CastBar or { enabled = false }
ExBoss.Debug.TrashVoice = ExBoss.Debug.TrashVoice or { enabled = false }
ExBoss.Debug.TargetClear = ExBoss.Debug.TargetClear or { enabled = false }
ExBoss.Debug.TargetAlert = ExBoss.Debug.TargetAlert or { enabled = false }
ExBoss.Debug.ShowNameplateNPCID = false
ExBoss._initLoaded = ExBoss._initLoaded or false

-- 时间轴注册入口必须在 Boss 数据文件加载前可用；
-- toc 中 Bosses/*.lua 早于 Scheduler.lua，因此在这里先提供稳定 stub。
ExBoss.Timeline._bosses = ExBoss.Timeline._bosses or {}
if type(ExBoss.Timeline.RegisterBoss) ~= "function" then
    function ExBoss.Timeline:RegisterBoss(encounterID, def)
        if type(encounterID) ~= "number" or type(def) ~= "table" then
            return
        end
        self._bosses[encounterID] = def
    end
end

-- print("|cffff4400Ex|r|cff00ccffBoss|r [1/3] ExBoss.lua 加载完成")

-- Init.lua 异常时的兜底：仍可通过 ExwindTools 虚拟事件驱动计时器。
do
    local ET = _G.ExwindTools
    if ET and ET.RegisterEvent then
        ET:RegisterEvent("ENCOUNTER_START", "ExBoss_Bootstrap_EncStart", function(_, encounterID)
            if ExBoss._initLoaded then return end
            if ExBoss.Timeline and ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.StartBoss then
                ExBoss.Timeline.Scheduler:StartBoss(encounterID)
            end
        end)
        ET:RegisterEvent("ENCOUNTER_END", "ExBoss_Bootstrap_EncEnd", function()
            if ExBoss._initLoaded then return end
            if ExBoss.Timeline and ExBoss.Timeline.Scheduler and ExBoss.Timeline.Scheduler.EndBoss then
                ExBoss.Timeline.Scheduler:EndBoss()
            end
        end)
    end
end

-- =============================================================
-- 斜杠命令：/exb 和 /exboss
-- =============================================================
SLASH_EXBOSS1 = "/exboss"
SLASH_EXBOSS2 = "/exb"
SlashCmdList["EXBOSS"] = function(input)
    local arg = (input or ""):match("^%s*(.-)%s*$"):lower()

    do
        local rest = arg:match("^pull%s*(.*)$")
        if rest ~= nil then
            local pullCountdown = ExBoss and ExBoss.PullCountdown or nil
            if pullCountdown and type(pullCountdown.HandleSlash) == "function" then
                pullCountdown:HandleSlash(rest)
            elseif ExBoss and ExBoss.Print and ExBoss.Print.Say then
                ExBoss.Print.Say((ExBoss.L and ExBoss.L["开怪倒数功能未就绪"]) or "开怪倒数功能未就绪")
            else
                print("|cffff4400ExBoss|r " .. tostring((ExBoss.L and ExBoss.L["开怪倒数功能未就绪"]) or "开怪倒数功能未就绪"))
            end
            return
        end
    end

    do
        local state, encounterText = arg:match("^aivoicedebug%s+(on)%s*(%d*)$")
        if not state then
            state, encounterText = arg:match("^aivoicedebug%s+(off)%s*(%d*)$")
        end
        if state then
            ExBoss.Debug = ExBoss.Debug or {}
            ExBoss.Debug.AIVoice = ExBoss.Debug.AIVoice or {}
            local dbg = ExBoss.Debug.AIVoice
            dbg.enabled = state == "on"
            dbg.encounterID = tonumber(encounterText)
            dbg.lines = 0
            if dbg.enabled then
                print("|cffff4400ExBoss|r AI轴语音调试已开启 encounter=" .. tostring(dbg.encounterID or "全部"))
            else
                print("|cffff4400ExBoss|r AI轴语音调试已关闭")
            end
            return
        end
    end

    do
        local mode = arg:match("^aipause%s+(on)$")
        if not mode then
            mode = arg:match("^aipause%s+(off)$")
        end
        if mode then
            local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
            if sched and type(sched.SetDebugFixedAIPaused) == "function" then
                local enabled = mode == "on"
                local affected = sched:SetDebugFixedAIPaused(enabled)
                print(string.format(
                    "|cffff4400ExBoss|r AI轴手动暂停%s affected=%d encounter=%s mode=%s driver=%s",
                    enabled and "已开启" or "已关闭",
                    tonumber(affected) or 0,
                    tostring(sched.GetCurrentEncounterID and sched:GetCurrentEncounterID() or "nil"),
                    tostring(sched._mode or "nil"),
                    tostring(sched._fixedDriver or "nil")
                ))
            else
                print("|cffff4400ExBoss|r 调度器未就绪，无法切换 AI轴手动暂停")
            end
            return
        end
    end

    if arg == "aipause toggle" then
        local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
        if sched and type(sched.ToggleDebugFixedAIPaused) == "function" then
            local enabled, affected = sched:ToggleDebugFixedAIPaused()
            print(string.format(
                "|cffff4400ExBoss|r AI轴手动暂停%s affected=%d encounter=%s mode=%s driver=%s",
                enabled and "已开启" or "已关闭",
                tonumber(affected) or 0,
                tostring(sched.GetCurrentEncounterID and sched:GetCurrentEncounterID() or "nil"),
                tostring(sched._mode or "nil"),
                tostring(sched._fixedDriver or "nil")
            ))
        else
            print("|cffff4400ExBoss|r 调度器未就绪，无法切换 AI轴手动暂停")
        end
        return
    end

    if arg == "aipause" or arg == "aipause status" then
        local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
        if sched and type(sched.IsDebugFixedAIPaused) == "function" then
            print(string.format(
                "|cffff4400ExBoss|r AI轴手动暂停=%s encounter=%s mode=%s driver=%s",
                tostring(sched:IsDebugFixedAIPaused()),
                tostring(sched.GetCurrentEncounterID and sched:GetCurrentEncounterID() or "nil"),
                tostring(sched._mode or "nil"),
                tostring(sched._fixedDriver or "nil")
            ))
        else
            print("|cffff4400ExBoss|r 调度器未就绪，无法读取 AI轴手动暂停状态")
        end
        return
    end

    if arg == "aidump" then
        local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
        if sched and type(sched.DebugPrintFixedAIState) == "function" then
            sched:DebugPrintFixedAIState()
        else
            print("|cffff4400ExBoss|r 调度器未就绪，无法打印 AI轴状态")
        end
        return
    end

    do
        local state = arg:match("^castbardebug%s+(on)$")
        if not state then
            state = arg:match("^castbardebug%s+(off)$")
        end
        if state then
            ExBoss.Debug = ExBoss.Debug or {}
            ExBoss.Debug.CastBar = ExBoss.Debug.CastBar or {}
            ExBoss.Debug.CastBar.enabled = state == "on"
            if ExBoss.Print and ExBoss.Print.Say then
                ExBoss.Print.Say("施法条调试 " .. (state == "on" and "已开启" or "已关闭"))
            else
                print("|cffff4400ExBoss|r 施法条调试 " .. (state == "on" and "已开启" or "已关闭"))
            end
            return
        end
    end

    do
        local offsetText = arg:match("^trashlevel%s+([%+%-]?%d+)$")
        if offsetText then
            local offset = tonumber(offsetText) or 0
            ExBoss.TrashCD = ExBoss.TrashCD or {}
            if offset == 0 then
                ExBoss.TrashCD.TestLevelOffset = nil
                print("|cffff4400ExBoss|r 小怪测试等级偏移已关闭")
            else
                ExBoss.TrashCD.TestLevelOffset = offset
                print("|cffff4400ExBoss|r 小怪测试等级偏移: " .. tostring(offset) .. "，/reload 后自动失效")
            end
            return
        end
    end

    if arg == "edit" or arg == "edmode" then
        local ET = _G.ExwindTools
        if ET and ET.ToggleGlobalEditMode then
            ET:ToggleGlobalEditMode()
        else
--             print("|cffff4400ExBoss|r: ExwindTools 不可用")
        end
        return
    end

    if arg == "version" then
--         print("|cffff4400Ex|r|cff00ccffBoss|r v" .. ExBoss.VERSION)
        return
    end

    if arg == "trashdebug" or arg == "trashdebug on" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.SetDebug) == "function" then
            test.SetDebug(true)
        else
            print("|cffff4400ExBoss|r 小怪匹配调试模块未就绪")
        end
        return
    end

    if arg == "trashdebug off" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.SetDebug) == "function" then
            test.SetDebug(false)
        else
            print("|cffff4400ExBoss|r 小怪匹配调试模块未就绪")
        end
        return
    end

    if arg == "trashdebug copy" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.ShowDebugCopy) == "function" then
            test.ShowDebugCopy()
        else
            print("|cffff4400ExBoss|r 小怪匹配调试模块未就绪")
        end
        return
    end

    if arg == "trashdebug clear" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.ClearDebugBuffer) == "function" then
            test.ClearDebugBuffer()
            print("|cffff4400ExBoss|r 小怪匹配调试缓存已清空")
        else
            print("|cffff4400ExBoss|r 小怪匹配调试模块未就绪")
        end
        return
    end

    if arg == "trashvoicedebug" or arg == "trashvoicedebug on" then
        ExBoss.Debug = ExBoss.Debug or {}
        ExBoss.Debug.TrashVoice = ExBoss.Debug.TrashVoice or {}
        ExBoss.Debug.TrashVoice.enabled = true
        if ExBoss.Print and ExBoss.Print.Say then
            ExBoss.Print.Say("小怪语音调试已开启")
        else
            print("|cffff4400ExBoss|r 小怪语音调试已开启")
        end
        return
    end

    if arg == "trashvoicedebug off" then
        ExBoss.Debug = ExBoss.Debug or {}
        ExBoss.Debug.TrashVoice = ExBoss.Debug.TrashVoice or {}
        ExBoss.Debug.TrashVoice.enabled = false
        if ExBoss.Print and ExBoss.Print.Say then
            ExBoss.Print.Say("小怪语音调试已关闭")
        else
            print("|cffff4400ExBoss|r 小怪语音调试已关闭")
        end
        return
    end

    if arg == "trashvoicedebug copy" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.ShowDebugCopy) == "function" then
            test.ShowDebugCopy()
        else
            print("|cffff4400ExBoss|r 小怪语音调试模块未就绪")
        end
        return
    end

    if arg == "shownpcid on" then
        ExBoss.Debug.ShowNameplateNPCID = true
        print("|cffff4400ExBoss|r 姓名版NPCID显示已开启（调试）")
        return
    end

    if arg == "shownpcid off" then
        ExBoss.Debug.ShowNameplateNPCID = false
        print("|cffff4400ExBoss|r 姓名版NPCID显示已关闭")
        return
    end

    if arg == "trashvoicedebug clear" then
        local test = ExBoss.Trash and ExBoss.Trash.Runtime and ExBoss.Trash.Runtime.ObservationTest
        if test and type(test.ClearDebugBuffer) == "function" then
            test.ClearDebugBuffer()
            print("|cffff4400ExBoss|r 小怪语音调试缓存已清空")
        else
            print("|cffff4400ExBoss|r 小怪语音调试模块未就绪")
        end
        return
    end

    do
        local state = arg:match("^targetclear%s+(on)$")
        if not state then
            state = arg:match("^targetclear%s+(off)$")
        end
        if state then
            ExBoss.Debug = ExBoss.Debug or {}
            ExBoss.Debug.TargetClear = ExBoss.Debug.TargetClear or {}
            ExBoss.Debug.TargetClear.enabled = state == "on"
            print("|cffff4400ExBoss|r targetClear单独打印" .. (state == "on" and "已开启" or "已关闭"))
            return
        end
    end

    do
        local state = arg:match("^targetalert%s+(on)$")
        if not state then
            state = arg:match("^targetalert%s+(off)$")
        end
        if state then
            ExBoss.Debug = ExBoss.Debug or {}
            ExBoss.Debug.TargetAlert = ExBoss.Debug.TargetAlert or {}
            ExBoss.Debug.TargetAlert.enabled = state == "on"
            print("|cffff4400ExBoss|r targetAlert单独打印" .. (state == "on" and "已开启" or "已关闭"))
            return
        end
    end

    if arg == "debug" then
        local bossCount = 0
        if ExBoss.Timeline and ExBoss.Timeline._bosses then
            for _ in pairs(ExBoss.Timeline._bosses) do
                bossCount = bossCount + 1
            end
        end
        local sched = ExBoss.Timeline and ExBoss.Timeline.Scheduler
        local timelineAPI = (C_EncounterTimeline and true) or false
--         print("--- ExBoss Debug ---")
--         print("ExBoss.UI.Panel = " .. tostring(ExBoss.UI.Panel))
--         print("Panel.Toggle = " .. tostring(ExBoss.UI.Panel and ExBoss.UI.Panel.Toggle))
--         print("Timeline.Bosses = " .. tostring(bossCount))
--         print("Timeline.API = " .. tostring(timelineAPI))
--         print("Scheduler.HandlesEncounterEvents = " .. tostring(sched and sched._handlesEncounterEvents))
--         print("Scheduler = running:" .. tostring(sched and sched._running)
--             .. " mode:" .. tostring(sched and sched._mode)
--             .. " encounter:" .. tostring(sched and sched._encounterID))
--         print("ExwindTools = " .. tostring(_G.ExwindTools))
--         print("ExwindFactory = " .. tostring(_G.ExwindFactory))
        return
    end

    -- 默认：打开/关闭主面板
    local P = ExBoss.UI.Panel
    if P and P.Toggle then
        P:Toggle()
    else
--         print("|cffff4400ExBoss|r: Panel.Toggle 未就绪 — P=" .. tostring(P) .. " Toggle=" .. tostring(P and P.Toggle))
    end
end
