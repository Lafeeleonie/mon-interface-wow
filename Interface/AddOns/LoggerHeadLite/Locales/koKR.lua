local ADDON_NAME, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "koKR")
if not L then return end

L["EXPANSION_NAME0"] = "오리지널"
L["EXPANSION_NAME1"] = "불타는 성전"
L["EXPANSION_NAME2"] = "리치 왕의 분노"
L["Normal"] = "일반"
L["20 Player"] = "20인"
L["40 Player"] = "40인"
L["Dungeons"] = "던전"

L[ [=[|cffeda55fClick|r to toggle combat logging
|cffeda55fRight-Click|r to open the options menu]=] ] = [=[클릭: 전투 로그 토글
옵션메뉴를 열려면 우클릭]=]
L["Disabled"] = "사용 안 함"
L["Enable chat logging when combat logging is enabled."] = "전투 로그가 활성화 될때 채팅로그 활성화"
L["Enabled"] = "사용함"
L["Log chat"] = "채팅 로그 활성화"
L["Profiles"] = "프로파일"
L["Prompt on new zone"] = "새로운 지역 바로 기록"
L["Prompt to enable logging when entering a new raid instance."] = "새로운 지역에 들어서면 로그 기록을 바로 시작하시겠습니까？"
L["Show minimap icon"] = "미니맵 아이콘 보기"
L["Toggle showing or hiding the minimap icon."] = "미니맵 아이콘 토글"
L["You have entered |cffd9d919%s|r. Enable logging for this zone?"] = "|cffd9d919%s|r에 들어섰습니다. 이 지역(인스턴스던전)에 대한 로그를 파일로 기록하시겠습니까？"

