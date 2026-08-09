-- =========================================================
-- ExwindDevTest.lua - 开发调试工具套件
-- 集成性能分析、日志系统、实时监控
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local M = {}
ExwindTools.DevTest = M
M.name = "DevTest"

-- =========================================================
-- 配置
-- =========================================================
local LOG_TABLE = {}
local MAX_LOGS = 1000

-- =========================================================
-- 日志系统
-- =========================================================

-- 获取精确时间戳
local function GetExactTime()
    return date("%H:%M:%S")
end

-- 添加日志（增强版，支持颜色和类型）
local function AddLog(msg, logType)
    if not ExwindTools.DevTestMode then return end

    local entry = {
        ts = GetExactTime(),
        msg = msg,
        type = logType or "info", -- info, warning, error, pool, perf
    }
    table.insert(LOG_TABLE, entry)

    -- 限制大小
    if #LOG_TABLE > MAX_LOGS then
        table.remove(LOG_TABLE, 1)
    end

    -- 置脏标记，由监控面板 OnUpdate 节流刷新（避免每条日志都全刷）
    if ExwindTools.DevMonitor then
        ExwindTools.DevMonitor:MarkLogDirty()
    end
end

-- =========================================================
-- 性能记录
-- =========================================================

-- 记录性能统计
local function RecordPerfStats(tag)
    if not ExwindTools.DevTestMode then return end

    UpdateAddOnCPUUsage()
    UpdateAddOnMemoryUsage()

    local name = "ExwindCore"
    local cpuRaw = GetAddOnCPUUsage(name)
    local memRaw = GetAddOnMemoryUsage(name)

    local cpuVal = cpuRaw        -- 秒
    local memVal = memRaw / 1024 -- MB

    local memStr = string.format("%.2f MB", memVal)
    local cpuStr = string.format("%.2f s", cpuVal)

    local logMsg = string.format("[%s] CPU: %s | 内存: %s", tag or "Stats", cpuStr, memStr)
    AddLog(logMsg, "perf")

    return "CPU: " .. cpuStr .. " 内存: " .. memStr
end

-- 暴露给外部调用
ExwindTools.RecordPerfStats = RecordPerfStats

-- =========================================================
-- GC 测试工具
-- =========================================================

function ExwindDevGC()
    if not ExwindTools.DevTestMode then
        print("|cffff5555请先输入 |cff00ff00/ex devtestmode|r |cffff5555开启调试模式|r")
        return
    end

    local statsHistory = {}

    local function GetMem()
        UpdateAddOnMemoryUsage()
        return GetAddOnMemoryUsage("ExwindCore") / 1024
    end

    local function RunStep(step)
        local before = GetMem()
        collectgarbage("collect")
        local after = GetMem()

        table.insert(statsHistory, { step = step, before = before, after = after })

        local logMsg = string.format("GC测试[%d]: %.2f MB -> %.2f MB (回收: %.2f MB)",
            step, before, after, before - after)
        AddLog(logMsg, "perf")
        print(string.format(
            "|cffA330C9ExwindDev:|r [Step %d] GC Before: |cffffaa55%.2fMB|r -> After: |cff55ff55%.2fMB|r",
            step, before, after))
    end

    print("|cffA330C9ExwindDev:|r 开始 GC 性能测试 (共 5 次)")
    RunStep(1)

    local count = 1
    C_Timer.NewTicker(1, function()
        count = count + 1
        RunStep(count)

        if count >= 5 then
            print("|cffA330C9ExwindDev:|r 测试完成。")
            print("|cff00ffff=== GC 测试结果汇总 ===|r")
            print("次数 | GC前(MB) | GC后(MB) | 回收量(MB)")
            for _, s in ipairs(statsHistory) do
                local diff = s.before - s.after
                print(string.format("  %d   |   %.2f   |   %.2f   |   %.2f",
                    s.step, s.before, s.after, diff))
            end
            print("|cff00ffff=======================|r")

            AddLog("GC 测试完成，共回收 " ..
                string.format("%.2f MB", statsHistory[#statsHistory].before - statsHistory[#statsHistory].after),
                "perf")
        end
    end, 4)
end

-- =========================================================
-- Hook 系统
-- =========================================================

local hooksInitialized = false

local function InitHooks()
    if hooksInitialized then return end
    hooksInitialized = true

    -- Hook 主界面操作
    local EXUI = ExwindTools.UI
    if EXUI then
        if EXUI.MainFrame then
            EXUI.MainFrame:HookScript("OnShow", function()
                RecordPerfStats("界面打开")
                AddLog("面板操作: [打开] 主窗口", "info")
            end)
            EXUI.MainFrame:HookScript("OnHide", function()
                RecordPerfStats("界面关闭")
                AddLog("面板操作: [关闭] 主窗口", "info")
            end)
        end

        -- Hook 模块切换
        if EXUI.ShowModuleSettingsPage then
            hooksecurefunc(EXUI, "ShowModuleSettingsPage", function(self)
                local currentModule = ExwindTools.State.SelectedModule or "Unknown"
                RecordPerfStats("切换模块: " .. currentModule)
                AddLog("面板操作: [切换模块] -> " .. currentModule, "info")
            end)
        end

        -- Hook 页面切换
        if EXUI.ShowHomePage then
            hooksecurefunc(EXUI, "ShowHomePage", function()
                AddLog("面板操作: [切换页面] 首页", "info")
            end)
        end
        if EXUI.ShowLoadSettingsPage then
            hooksecurefunc(EXUI, "ShowLoadSettingsPage", function()
                AddLog("面板操作: [切换页面] 加载设置", "info")
            end)
        end
        if EXUI.ShowDiagnosticPage then
            hooksecurefunc(EXUI, "ShowDiagnosticPage", function()
                AddLog("面板操作: [切换页面] 诊断信息", "info")
            end)
        end
    end

    -- Hook 框架池操作
    local EXFactory = _G.ExwindFactory
    if EXFactory then
        -- 保存原始 Acquire
        if not EXFactory.OrigAcquire then
            EXFactory.OrigAcquire = EXFactory.Acquire
            EXFactory.Acquire = function(self, type, parent)
                local frame, isNew = self.OrigAcquire(self, type, parent)

                if ExwindTools.DevTestMode then
                    local pool = self.Pools[type]
                    local inactive = 0
                    if pool and pool.inactiveObjects then
                        for _ in pairs(pool.inactiveObjects) do
                            inactive = inactive + 1
                        end
                    end

                    local statusStr = isNew and "|cffff5555[新建]|r" or "|cff55ff55[复用]|r"
                    local addr = tostring(frame):gsub("table: ", ""):sub(1, 8)

                    local logMsg = string.format("框架池: Acquire %s -> %s %s (库存:%d)",
                        type, addr, isNew and "[新建]" or "[复用]", inactive)
                    AddLog(logMsg, "pool")
                end

                return frame, isNew
            end
        end

        -- 保存原始 Release
        if not EXFactory.OrigRelease then
            EXFactory.OrigRelease = EXFactory.Release
            EXFactory.Release = function(self, type, frame)
                if ExwindTools.DevTestMode then
                    local pool = self.Pools[type]
                    local active = 0
                    if pool and pool.activeObjects then
                        for _ in pairs(pool.activeObjects) do
                            active = active + 1
                        end
                    end

                    local addr = tostring(frame):gsub("table: ", ""):sub(1, 8)
                    local logMsg = string.format("框架池: Release %s -> %s (在用:%d)",
                        type, addr, active)
                    AddLog(logMsg, "pool")
                end

                self.OrigRelease(self, type, frame)
            end
        end
    end

    AddLog("Hook 系统初始化完成", "info")
end

-- =========================================================
-- 命令处理
-- =========================================================

local function HookExCommand()
    local oldFunc = SlashCmdList["EX"]
    if not oldFunc then return end

    SlashCmdList["EX"] = function(msg)
        local arg = (msg or ""):trim():lower()

        -- 调试模式开关
        if arg == "devtestmode" then
            ExwindTools.DevTestMode = not ExwindTools.DevTestMode

            local status = ExwindTools.DevTestMode and "|cff55ff55开启|r" or "|cffff5555关闭|r"
            print("|cffA330C9Exwind 工具调试模式:|r " .. status)

            if ExwindTools.DevTestMode then
                InitHooks()
                AddLog("=== 调试模式开启 ===", "info")
                RecordPerfStats("初始化")

                -- 自动打开监控面板
                if ExwindTools.DevMonitor then
                    C_Timer.After(0.1, function()
                        ExwindTools.DevMonitor:Show()
                    end)
                end
            else
                AddLog("=== 调试模式关闭 ===", "info")

                -- 关闭监控面板
                if ExwindTools.DevMonitor then
                    ExwindTools.DevMonitor:Hide()
                end
            end
            return
        end

        -- 打印日志
        if arg == "devprint" then
            print("|cff00ffffExwind 调试日志 (最新 300 条):|r")
            local start = math.max(1, #LOG_TABLE - 300)
            for i = start, #LOG_TABLE do
                local entry = LOG_TABLE[i]

                -- 根据类型设置颜色
                local color = "|cffaaaaaa"
                if entry.type == "error" then
                    color = "|cffff5555"
                elseif entry.type == "warning" then
                    color = "|cffffaa55"
                elseif entry.type == "pool" then
                    color = "|cff55aaff"
                elseif entry.type == "perf" then
                    color = "|cffaa55ff"
                end

                print(string.format("|cff666666[%s]|r %s%s|r", entry.ts, color, entry.msg))
            end
            print(string.format("共 %d 条记录。", #LOG_TABLE))
            return
        end

        -- 清空日志
        if arg == "devclear" then
            wipe(LOG_TABLE)
            print("|cffA330C9ExwindDev:|r 日志已清空")
            if ExwindTools.DevMonitor then
                ExwindTools.DevMonitor:UpdateLogViewer()
            end
            return
        end

        -- 性能快照
        if arg == "devstats" or arg == "devperf" then
            local stats = RecordPerfStats("手动快照")
            print("|cffA330C9ExwindDev:|r " .. stats)
            return
        end

        -- GC 测试
        if arg == "devgc" then
            ExwindDevGC()
            return
        end

        -- 帮助信息
        if arg == "devhelp" then
            print("|cffA330C9=== ExwindDev 调试工具 ===|r")
            print("|cff00ff00/ex devtestmode|r - 开启/关闭调试模式")
            print("|cff00ff00/ex devmonitor|r 或 |cff00ff00/ex dm|r - 打开实时监控面板")
            print("|cff00ff00/ex devprint|r - 打印日志到聊天框")
            print("|cff00ff00/ex devclear|r - 清空日志")
            print("|cff00ff00/ex devstats|r - 显示性能快照")
            print("|cff00ff00/ex devgc|r - 运行 GC 测试")
            return
        end

        -- 调用原有的处理逻辑
        oldFunc(msg)
    end
end

-- 延迟 Hook
C_Timer.After(1, HookExCommand)

-- =========================================================
-- 导出
-- =========================================================
ExwindTools.DevLogTable = LOG_TABLE
ExwindTools.AddDevLog = AddLog
