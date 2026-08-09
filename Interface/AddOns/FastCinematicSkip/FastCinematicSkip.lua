local L = LibStub("AceLocale-3.0"):GetLocale("FastCinematicSkip", false)

local rev = tonumber(("$Revision: 5 $"):match("%d+"))
local function msg(...)
    print("|cffd6266cFastCinematicSkip|r: ",...)
end
msg("Loaded rev "..rev)
local debug_enabled = false
local function debug(...)
  if debug_enabled then
    msg(...)
  end
end

CinematicFrame:HookScript("OnShow", function(self, ...)
  debug("CinematicFrame:OnShow",...)
  if IsModifierKeyDown() then return end
  msg(L["Cinematic"])
  CinematicFrame_CancelCinematic()
end)

local omfpf = _G["MovieFrame_PlayMovie"]
_G["MovieFrame_PlayMovie"] = function(...)
  debug("MovieFrame_PlayMovie",...)
  if IsModifierKeyDown() then return omfpf(...) end
  msg(L["Movie"])
  CinematicFinished(1)
  return true
end
