local TocName, Env = ...
local Copybara = LibStub("AceAddon-3.0"):NewAddon(TocName, "AceConsole-3.0", "AceEvent-3.0")
Env.Addon = Copybara
local C_AddOns = C_AddOns

local function SafeGetAddOnMetadata(name, key)
    if C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(name, key) or ""
    else
        return GetAddOnMetadata and GetAddOnMetadata(name, key) or ""
    end
end

Copybara.displayName = SafeGetAddOnMetadata(TocName, "Title")
setglobal("Copybara", Copybara)

local LibDeflate = LibStub:GetLibrary("LibDeflate")
local LibSerialize = LibStub("LibSerialize")

local configForDeflate = {level = 9}
local configForLS = {
   errorOnUnserializableType =  false
}

-- WoW API's
local _G = _G
local GetChatWindowInfo, GetChatWindowMessages, GetChatWindowChannels, GetChatWindowSavedDimensions, GetChatWindowSavedPosition, SetChatWindowName, SetChatWindowColor, SetChatWindowAlpha, SetChatWindowSize, SetChatWindowShown, SetChatWindowLocked, SetChatWindowDocked, SetChatWindowUninteractable, SetChatWindowSavedDimensions = GetChatWindowInfo, GetChatWindowMessages, GetChatWindowChannels, GetChatWindowSavedDimensions, GetChatWindowSavedPosition, SetChatWindowName, SetChatWindowColor, SetChatWindowAlpha, SetChatWindowSize, SetChatWindowShown, SetChatWindowLocked, SetChatWindowDocked, SetChatWindowUninteractable, SetChatWindowSavedDimensions

local ChatFrame_RemoveAllMessageGroups, ChatFrame_RemoveAllChannels, ChatFrame_ReceiveAllPrivateMessages, ChatFrame_AddMessageGroup = ChatFrame_RemoveAllMessageGroups, ChatFrame_RemoveAllChannels, ChatFrame_ReceiveAllPrivateMessages, ChatFrame_AddMessageGroup

local private = {}

local Options = {}
Copybara.Options = Options

Options.defaults = {
   profile = {},
   global = {
      lastSyncMessage = nil,
   },
}

Options.constructor = {
   name = TocName,
   handler = Options,
   type = "group",
   set = "Setter",
   get = "Getter",
   args = {
      about = {
         name = format("%s:%s by %s\n\n", GAME_VERSION_LABEL, SafeGetAddOnMetadata(TocName, "Version"), SafeGetAddOnMetadata(TocName, "Author")),
         type = "description",
         order = 0,
      },
      selectedCharacter = {
         name = "Select character to copy chat settings from",
         type = "select",
         style = "dropdown",
         values = function(self)
            local profileNames = {}

            for name in pairs(Copybara.Options.DB.profiles) do
               profileNames[name] = name
            end

            return profileNames
         end,
         sorting = function(self)
            local values = self.option.values()
            local tempTbl = {}

            for key in pairs(values) do
               table.insert(tempTbl, key)
            end

            table.sort(tempTbl)

            return tempTbl
         end,
         order = 1,
      },
      copy = {
         type = "execute",
         desc = "Copying chat settings from the selected character to the character you are currently on",
         name = APPLY,
         order = 2,
         func = function(self)
            local currentProfile = Copybara.DB:GetCurrentProfile()
            local selectedCharacter = Copybara.DB.profiles[currentProfile].selectedCharacter

            if selectedCharacter then
               local chatConfig = Copybara.DB.profiles[selectedCharacter].chatConfig
               Copybara:LoadConfig(chatConfig)
            end
         end,
      },
      br1 = { type = "description", name = "", order = 3},
      transmitInputBox = {
         type = "input",
         name = "Import/Export",
         multiline = true,
         width = "double",
         order = 4,
         get = function(self)
            return private.transmitInputBoxText or ""
         end,
         set = function(self, value)
            private.transmitInputBoxText = value
         end,
      },
      br2 = { type = "description", name = "", order = 5},
      import = {
         type = "execute",
         name = "Import",
         order = 6,
         func = function(self)
            Copybara:ImportConfigString()
         end,
      },
      export = {
         type = "execute",
         name = "Export",
         order = 7,
         func = function(self)
            Copybara:ExportConfig()
         end,
      },
      br3 = { type = "description", name = "", order = 8},
      syncAllCharacters = {
         type = "execute",
         name = "Sync All Characters",
         desc = "Replace all character settings with the current character's settings",
         func = function()
            Copybara:SyncAllCharacters()
         end,
         order = 9,
      },
      br4 = { type = "description", name = "", order = 99},
      reset = {
         type = "execute",
         name = CHAT_DEFAULTS,
         func = function(self)
          FCF_ResetAllWindows()
         end,
         order = 100,
         hidden = true,
      },
   },
}

function Copybara:OnInitialize()
   self.DB = LibStub("AceDB-3.0"):New(TocName .. "DB", self.Options.defaults)
   self.Options.DB = self.DB
   LibStub("AceConfig-3.0"):RegisterOptionsTable(self.displayName, self.Options.constructor)
   self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(self.displayName, self.displayName)

   if C_AddOns.IsAddOnLoaded("Blizzard_CombatLog") then
      self:SetupCombatLog()
   else
      self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
   end

   self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
   self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
end

function Copybara:OnAddonLoaded(event, addon)
   if addon == "Blizzard_CombatLog" then
      self:SetupCombatLog()
      self:UnregisterEvent("ADDON_LOADED")
   end
end

function Copybara:SetupCombatLog()
   -- Add any combat log specific setup here
end

function Copybara:OnLogin()
   if self.DB.global.lastSyncMessage then
      self:Print(self.DB.global.lastSyncMessage)
      self.DB.global.lastSyncMessage = nil
   end
end

function Copybara:OnLogout()
   self:SaveConfig()
end

function Copybara:GetConfig()
   local chatConfig = {}

   for i = 1, NUM_CHAT_WINDOWS do
      local f = _G["ChatFrame" .. i]
      local width, height = GetChatWindowSavedDimensions(i)
      local point, xOfs, yOfs = GetChatWindowSavedPosition(i)
      local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i)
      local DefaultMessages = { GetChatWindowMessages(f:GetID()) }
      local DefaultChannels = { GetChatWindowChannels(f:GetID()) }


      chatConfig[i] = {
         width = width,
         height = height,
         point = point,
         xOfs = xOfs,
         yOfs = yOfs,
         name = name,
         fontSize = fontSize,
         r = r,
         g = g,
         b = b,
         alpha = alpha,
         shown = shown,
         locked = locked,
         docked = docked,
         uninteractable = uninteractable,
         DefaultMessages = DefaultMessages,
         DefaultChannels = DefaultChannels,
         parentName = f:GetParent():GetName(),
      }
   end

   return chatConfig
end

function Copybara:SaveConfig()
   local currentProfile = self.DB:GetCurrentProfile()

   self.DB.profiles[currentProfile] = self.DB.profiles[currentProfile] or {}
   self.DB.profiles[currentProfile].chatConfig = self:GetConfig()
end

function Copybara:SyncAllCharacters()
   local currentProfile = self.DB:GetCurrentProfile()
   local currentConfig = self:GetConfig()
   local charactersToSync = {}

   for profileName, _ in pairs(self.DB.profiles) do
      if profileName ~= currentProfile then
         table.insert(charactersToSync, profileName)
      end
   end

   if #charactersToSync == 0 then
      self:Print("No other characters found to sync settings to.")
      return
   end

   local characterList = table.concat(charactersToSync, "\n")
   
   StaticPopupDialogs["COPYBARA_CONFIRM_SYNC"] = {
      text = string.format("This will apply the current chat settings to the following characters:\n\n%s\n\nDo you want to continue?", characterList),
      button1 = "Yes",
      button2 = "No",
      OnAccept = function()
         for _, profileName in ipairs(charactersToSync) do
            self.DB.profiles[profileName].chatConfig = CopyTable(currentConfig)
         end
         self.DB.global.lastSyncMessage = "Chat settings synced to all other characters."
         self:Print(self.DB.global.lastSyncMessage)
         -- Removed the ShowReloadPopup call here
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
   }
   StaticPopup_Show("COPYBARA_CONFIRM_SYNC")
end

function Copybara:ImportConfigString()
   local input = private.transmitInputBoxText
   local chatConfig = private.StringToTable(input)

   if type(chatConfig) == "table" then
      self:LoadConfig(chatConfig)
   else
      self:Print("Error: Invalid input string, try again.")
   end
end

function Copybara:ExportConfig()
   local exportString = Copybara:GetExportString()
   private.transmitInputBoxText = exportString
end

function Copybara:GetExportString()
   local currentProfile = self.DB:GetCurrentProfile()
   local selectedCharacter = self.DB.profiles[currentProfile].selectedCharacter

   if selectedCharacter then
      local chatConfig = self.DB.profiles[selectedCharacter].chatConfig
      local encodedChatConfig = private.TableToString(chatConfig)

      return encodedChatConfig
   end
end

function Copybara:LoadConfig(config)
   if config then
      for chatFrameIndex = 1, NUM_CHAT_WINDOWS do
         local chatFrame = _G["ChatFrame" .. chatFrameIndex]
         local savedFrame = config[chatFrameIndex]

         if ( not savedFrame.name or savedFrame.name == "" ) then
            savedFrame.name = format(CHAT_NAME_TEMPLATE, chatFrameIndex)
         end

         -- Initialize the frame
         chatFrame:SetParent(_G[savedFrame.parentName])
         SetChatWindowName(chatFrameIndex, savedFrame.name)
         SetChatWindowColor(chatFrameIndex, savedFrame.r, savedFrame.g, savedFrame.b)
         SetChatWindowAlpha(chatFrameIndex, savedFrame.alpha)
         SetChatWindowSize(chatFrameIndex, savedFrame.fontSize)
         SetChatWindowShown(chatFrameIndex, savedFrame.shown)
         SetChatWindowLocked(chatFrameIndex, savedFrame.locked)
         SetChatWindowDocked(chatFrameIndex, savedFrame.docked)
         SetChatWindowUninteractable(chatFrameIndex, savedFrame.uninteractable)
         SetChatWindowSavedDimensions(chatFrameIndex, savedFrame.width, savedFrame.height)

         if savedFrame.point then
            SetChatWindowSavedPosition(chatFrameIndex, savedFrame.point, savedFrame.xOfs, savedFrame.yOfs)
         end

         -- Remove old msg configuration
         ChatFrame_RemoveAllMessageGroups(chatFrame)
         ChatFrame_RemoveAllChannels(chatFrame)
         ChatFrame_ReceiveAllPrivateMessages(chatFrame)

         -- Restore new message groups
         for _, messageType in pairs(savedFrame.DefaultMessages) do
            ChatFrame_AddMessageGroup(chatFrame, messageType)
         end

         -- Restore new channels
         for _, channel in pairs(savedFrame.DefaultChannels) do
            ChatFrame_AddChannel(chatFrame, channel)
         end
      end

      self:ShowReloadPopup()
   end
end

function Copybara:ShowReloadPopup()
    StaticPopupDialogs["COPYBARA_RELOAD_UI"] = {
        text = "Chat settings have been updated. Do you want to reload the UI to apply these changes?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("COPYBARA_RELOAD_UI")
end

function Options:Setter(...)
   local info, arg2, arg3 = ...
   local scope = private.GetDBScopeForInfo(self.DB.profile, info)

   local key = info[#info]
   local val = arg2

   if arg3 ~= nil then
      local subKey = arg2
      val = arg3
      scope[key][subKey] = val
   else
      scope[key] = val
   end
end

function Options:Getter(...)
   local info, subKey = ...
   local infoScope = private.GetDBScopeForInfo(self.DB.profile, info)
   local key = info[#info]

   if subKey then
      return infoScope[key][subKey]
   end

   return infoScope[key]
end

function private.StringToTable(inString)
   local _, _, _, encoded = inString:find("^(!COPYBARA:)(.+)$")

   if encoded then
      local decoded = LibDeflate:DecodeForPrint(encoded)

      if not decoded then
         return "Error decoding."
      end

      local decompressed = LibDeflate:DecompressDeflate(decoded)

      if not(decompressed) then
         return "Error decompressing"
      end

      local success, deserialized = LibSerialize:Deserialize(decompressed)

      if not(success) then
         return "Error deserializing"
      end

      return deserialized
   end
end

function private.TableToString(inTable)
   local serialized = LibSerialize:SerializeEx(configForLS, inTable)
   local compressed = LibDeflate:CompressDeflate(serialized, configForDeflate)

   local encoded = "!COPYBARA:"
   encoded = encoded .. LibDeflate:EncodeForPrint(compressed)
   return encoded
end

function private.GetDBScopeForInfo(DB, info)
   assert(DB and info and type(info) == "table" and type(DB) == "table")

   local scope = DB

   for i = 1, #info - 1 do
      scope = scope[info[i]]
   end

   return scope
end
