local ADDON_NAME, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

L["EXPANSION_NAME0"] = "Classic"
L["EXPANSION_NAME1"] = "Burning Crusade"
L["EXPANSION_NAME2"] = "Wrath of the Lich King"
L["Normal"] = "Normal"
L["20 Player"] = "20 Spieler"
L["40 Player"] = "40 Spieler"
L["Dungeons"] = "Dungeons"

L[ [=[|cffeda55fClick|r to toggle combat logging
|cffeda55fRight-Click|r to open the options menu]=] ] = [=[|cffeda55fLinksklick|r, um die Kampfaufzeichnung ein-/auszuschalten
|cffeda55fRechtsklick|r, um die Einstellungen zu öffnen]=]
L["Automatically turns on the combat log for selected raid and mythic+ instances."] = "Schaltet die Kampfaufzeichnung automatisch für ausgewählte Schlachtzugsinstanzen und Mythisch+-Dungeons ein."
L["Disabled"] = "Deaktiviert"
L["Enable chat logging when combat logging is enabled."] = "Chat-Aufzeichnung immer aktivieren wenn die Aufzeichnung des Kampflogs aktiviert ist"
L["Enabled"] = "Aktiviert"
L["Log chat"] = "Chat-Aufzeichnung aktivieren"
L["Profiles"] = "Profile"
L["Prompt on new zone"] = "Abfrage bei Zonenwechsel"
L["Prompt to enable logging when entering a new raid instance."] = "Abfrage bei Betreten einer neuen Instanz?"
L["Show minimap icon"] = "Minikartensymbol anzeigen"
L["Toggle showing or hiding the minimap icon."] = "Die Anzeige des Minikartensymbols ein-/ausschalten"
L["You have entered |cffd9d919%s|r. Enable logging for this zone?"] = "Du hast |cffd9d919%s|r betreten. Die Aufzeichnung für dieses Gebiet aktivieren?"
L["You have not entered a raid instance yet! Zones will be listed after you enter them."] = "Du hast noch keine Instanz betreten! Gebiete werden nach dem Betreten gelistet."

