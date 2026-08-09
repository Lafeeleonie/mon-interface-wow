local ADDON_NAME, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhTW")
if not L then return end

L["EXPANSION_NAME0"] = "艾澤拉斯"
L["EXPANSION_NAME1"] = "燃燒的遠征"
L["EXPANSION_NAME2"] = "巫妖王之怒"
L["Normal"] = "普通"
L["20 Player"] = "20人"
L["40 Player"] = "40人"
L["Dungeons"] = "地城"

L[ [=[|cffeda55fClick|r to toggle combat logging
|cffeda55fRight-Click|r to open the options menu]=] ] = [=[點擊開啟/關閉記錄戰斗日志
右鍵點擊打開選項菜單]=]
L["Automatically turns on the combat log for selected raid and mythic+ instances."] = "自動為選定的團隊副本與傳奇+地城開啟戰鬥記錄"
L["Disabled"] = "停用"
L["Enable chat logging when combat logging is enabled."] = "啟用戰鬥記錄時同時啟用聊天記錄"
L["Enabled"] = "啟用"
L["Ignore partial group"] = "忽略非完整隊伍"
L["Log chat"] = "記錄聊天"
L["Profiles"] = "設定檔"
L["Prompt on new zone"] = "進入新區域時詢問"
L["Prompt to enable logging when entering a new raid instance."] = "進入新的團隊副本時，詢問是否啟用戰鬥記錄"
L["Show minimap icon"] = "顯示小地圖圖標"
L["Skip the prompt if your instance group has less than five players."] = "若你的副本隊伍少於五名玩家，則跳過詢問"
L["Toggle showing or hiding the minimap icon."] = "切換顯示或隱藏小地圖圖示"
L["You have entered |cffd9d919%s|r. Enable logging for this zone?"] = "你已進入 |cffd9d919%s|r。是否為此區域啟用戰鬥記錄？"
L["You have not entered a raid instance yet! Zones will be listed after you enter them."] = "你尚未進入任何團隊副本！區域將在你進入後列出"

