local ADDON_NAME, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "ptBR")
if not L then return end

L["EXPANSION_NAME0"] = "Classic"
L["EXPANSION_NAME1"] = "Burning Crusade"
L["EXPANSION_NAME2"] = "Wrath of the Lich King"
L["Normal"] = "Normal"
L["20 Player"] = "20 jogadores"
L["40 Player"] = "40 jogadores"
L["Dungeons"] = "Masmorras"

L[ [=[|cffeda55fClick|r to toggle combat logging
|cffeda55fRight-Click|r to open the options menu]=] ] = "|cffeda55fClique|r para habilitar/desabilitar o registro de combate |cffeda55fClique-Direito|r para abrir o menu de opções"
L["Automatically turns on the combat log for selected raid and mythic+ instances."] = "Habilita automaticamente o registro de combate para raides selecionadas e instâncias míticas+."
L["Disabled"] = "Desativado"
L["Enable chat logging when combat logging is enabled."] = "Habilita o registro de chat quando o registro de combate estiver habilitado."
L["Enabled"] = "Ativado"
L["Ignore partial group"] = "Ignorar grupo parcial"
L["Log chat"] = "Registrar o chat"
L["Profiles"] = "Perfis"
L["Prompt on new zone"] = "Perguntar em novas áreas"
L["Prompt to enable logging when entering a new raid instance."] = "Pergunta se deseja habilitar o registro de combate quando entrar em uma nova instância de raide."
L["Show minimap icon"] = "Mostrar ícone no mini-mapa"
L["Skip the prompt if your instance group has less than five players."] = "Deixa de perguntar quando seu grupo de instância tiver menos de cinco jogadores."
L["Toggle showing or hiding the minimap icon."] = "Alterna entre mostrar ou esconder o ícone do mini-mapa."
L["You have entered |cffd9d919%s|r. Enable logging for this zone?"] = "Você entrou em |cffd9d919%s|r. Deseja habilitar o registro de combate para esta área?"
L["You have not entered a raid instance yet! Zones will be listed after you enter them."] = "Você não entrou em uma instância de raide ainda! As áreas serão listadas aqui depois que você entrar nelas."

