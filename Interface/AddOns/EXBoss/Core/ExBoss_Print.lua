---@diagnostic disable: undefined-global
-- Core/ExBoss_Print.lua
-- 统一聊天框 print 入口 + 进入副本提示表

ExBoss = ExBoss or {}
ExBoss.Print = ExBoss.Print or {}

local PREFIX = "|cff00ffff<EXBOSS>|r"

function ExBoss.Print.Say(msg)
    if type(msg) ~= "string" or msg == "" then return end
    print(PREFIX .. " " .. msg)
end

-- MapID -> 进入副本要打印的提示行（按顺序输出）
local ENTRY_NOTICES = {
    [658]  = { "进入 |cffffd100萨隆矿坑|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [1209] = { "进入 |cffffd100通天峰|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [1753] = {
        "进入 |cffffd100执政团之座|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!",
        "2号BOSS |cffffd100狗跳点名模块|r已载入 该功能测试中 仅供参考!",
    },
    [2526] = { "进入 |cffffd100艾杰斯亚学院|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [2805] = { "进入 |cffffd100风行者之塔|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [2811] = { "进入 |cffffd100魔导师平台|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [2874] = { "进入 |cffffd100迈萨拉洞窟|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
    [2915] = { "进入 |cffffd100节点希纳斯|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!" },
}

local function HandleMapChange(newID, oldID)
    if newID == oldID then return end
    local lines = ENTRY_NOTICES[tonumber(newID) or 0]
    if not lines then return end
    for i = 1, #lines do
        ExBoss.Print.Say(lines[i])
    end
end

if ExwindTools and type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState("MapID", "ExBoss.Print.EntryNotice", HandleMapChange)
end
