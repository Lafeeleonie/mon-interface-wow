local ADDON_NAME, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhCN")
if not L then return end

L["EXPANSION_NAME0"] = "经典旧世"
L["EXPANSION_NAME1"] = "燃烧的远征"
L["EXPANSION_NAME2"] = "巫妖王之怒"
L["Normal"] = "普通"
L["20 Player"] = "20人"
L["40 Player"] = "40人"
L["Dungeons"] = "地下城"

L[ [=[|cffeda55fClick|r to toggle combat logging
|cffeda55fRight-Click|r to open the options menu]=] ] = [=[点击开启/关闭记录战斗日志
右键点击打开选项菜单]=]
L["Automatically turns on the combat log for selected raid and mythic+ instances."] = "自动为选定的团队副本和史诗钥石地下城开启战斗日志"
L["Disabled"] = "禁用"
L["Enable chat logging when combat logging is enabled."] = "启用战斗日志时同时启用聊天记录"
L["Enabled"] = "启用"
L["Ignore partial group"] = "忽略不完整队伍"
L["Log chat"] = "启用聊天纪录"
L["Profiles"] = "配置文件"
L["Prompt on new zone"] = "进入新区域时提示"
L["Prompt to enable logging when entering a new raid instance."] = "进入新的团队副本时提示是否启用日志记录"
L["Show minimap icon"] = "显示小地图图标"
L["Skip the prompt if your instance group has less than five players."] = "如果副本队伍少于五名玩家，则跳过提示"
L["Toggle showing or hiding the minimap icon."] = "切换显示或隐藏小地图图标。"
L["You have entered |cffd9d919%s|r. Enable logging for this zone?"] = "你已进入 |cffd9d919%s|r。是否为此区域启用战斗日志记录？"
L["You have not entered a raid instance yet! Zones will be listed after you enter them."] = "你尚未进入任何团队副本！区域将在你进入后列出。"

