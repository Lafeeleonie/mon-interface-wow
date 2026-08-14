# Mon interface WoW

Version publique et assainie de mon interface World of Warcraft Retail.

## Contenu

- `Interface/AddOns/` : les addons installés, sans les bases de joueurs générées ni les addons contenant mes médias personnels ;
- `WTF/Account/ACCOUNT/SavedVariables/` : une sélection de profils d'interface utiles ;
- `Build-Public-Snapshot.ps1` : le script qui reconstruit cette version publique à partir de mon installation locale.

Les noms de compte, royaumes et personnages sont remplacés par des valeurs génériques. Les BattleTags, e-mails, GUID, adresses IP, identifiants Discord, chemins utilisateur, webhooks et valeurs ressemblant à des secrets sont également neutralisés.

Ne sont volontairement pas publiés : historiques de discussion, combat, enchères et guilde, macros, caches, fichiers propres aux personnages, captures d'écran, journaux, polices générées, sauvegardes temporaires et archives de profils supprimés.

## Mes addons

<!-- ADDON_CATALOG_START -->
Ce catalogue référence **79 dossiers**, dont **78 modules WoW détectés** par leur fichier `.toc`.
Le **dossier auxiliaire** sans `.toc` est également indiqué pour que l'inventaire reste exhaustif.

Les descriptions et versions proviennent directement des métadonnées installées ; leur langue peut donc varier selon l'addon.

<details>
<summary><strong>Addons personnels</strong> — 6 dossier(s)</summary>

| Addon | Version | Auteur | Présentation |
|---|---:|---|---|
| [__recap](Interface/AddOns/__recap)<br><sub>__recap</sub> | — | — | Dossier auxiliaire sans fichier TOC. |
| [Lafee Damage Type Tracker](Interface/AddOns/lafee_damage_tracker)<br><sub>lafee_damage_tracker</sub> | 1.1.0 | Lafee | Suit les dégâts physiques et magiques subis avec un bouton de minicarte configurable et une fenêtre de temps glissante. |
| [Lafee ElvUI Chat Frame](Interface/AddOns/lafee_elvui_chat_frame)<br><sub>lafee_elvui_chat_frame</sub> | 1.2.2 | Lafee | Ajoute des movers ElvUI liés au profil pour les fenêtres de discussion Blizzard. |
| [Lafee ElvUI Frame Group](Interface/AddOns/lafee_elvui_frame_group)<br><sub>lafee_elvui_frame_group</sub> | 1.1.4 | Lafee | Link ElvUI movers so they can be moved together. |
| [Lafee ElvUI Guild Hover](Interface/AddOns/lafee_elvui_guild_hover)<br><sub>lafee_elvui_guild_hover</sub> | 1.1.11 | Lafee | Interactive ElvUI datatexts for contacts, guild and community members. |
| [Lafee Macro Manager](Interface/AddOns/lafee_macro_manager)<br><sub>lafee_macro_manager</sub> | 0.5.7 | Lafee | Edit character and global macros with a minimap button. |

</details>

<details>
<summary><strong>Interface et affichage</strong> — 10 dossier(s)</summary>

| Addon | Version | Auteur | Présentation |
|---|---:|---|---|
| [AddOnSkins](Interface/AddOns/AddOnSkins)<br><sub>AddOnSkins</sub> | 4.73 | Azilroka, Nihilistzsche | Module ou extension de AddOnSkins. |
| [BetterCooldownManager](Interface/AddOns/BetterCooldownManager)<br><sub>BetterCooldownManager</sub> | @project-version@ | Unhalted | BetterCooldownManager is an all-in-one AddOn that provides additional customization to the Cooldown Manager, developed by Unhalted |
| [ElvUI](Interface/AddOns/ElvUI)<br><sub>ElvUI</sub> | v15.21 | Elv, Simpy | User Interface Replacement |
| [ElvUI Libraries](Interface/AddOns/ElvUI_Libraries)<br><sub>ElvUI_Libraries</sub> | v15.21 | Elv, Simpy | Libraries that power ElvUI |
| [ElvUI Options](Interface/AddOns/ElvUI_Options)<br><sub>ElvUI_Options</sub> | v15.21 | Elv, Simpy | Powers the configuration window. Does not store any profile data. |
| [ElvUI WindTools](Interface/AddOns/ElvUI_WindTools)<br><sub>ElvUI_WindTools</sub> | 4.19 | fang2hou | Customizable enhancements for ElvUI. |
| [MiniAuras](Interface/AddOns/MiniAuras)<br><sub>MiniAuras</sub> | 5.12.2 | Verz | Shows CC and important spells on frames/nameplates/alerts in PvP. |
| [MiniCC (settings bridge for MiniAuras)](Interface/AddOns/MiniCC)<br><sub>MiniCC</sub> | 5.12.2 | Verz | Loads the old MiniCC settings file so MiniAuras can import it. Does nothing else. |
| [Platynator](https://www.curseforge.com/wow/addons/platynator)<br><sub>Platynator</sub> | 462 | plusmouse | Module ou extension de Platynator. [Mon profil](https://wago.io/OYbMwElUi) |
| [WIM - ElvUI Skin](Interface/AddOns/WIM_ElvUI_Skin)<br><sub>WIM_ElvUI_Skin</sub> | 120007.01-Release | fuba | A simple skin matching the Design of Elvui |

</details>

<details>
<summary><strong>Combat, donjons et raids</strong> — 41 dossier(s)</summary>

| Addon | Version | Auteur | Présentation |
|---|---:|---|---|
| [&lt;DBM Core&gt; IUG des options](Interface/AddOns/DBM-GUI)<br><sub>DBM-GUI</sub> | 12.1.3 | MysticalOS, QartemisT | IUG pour Deadly Boss Mods |
| [&lt;DBM Core&gt; Noyau](Interface/AddOns/DBM-Core)<br><sub>DBM-Core</sub> | 12.1.3 | MysticalOS, QartemisT | Deadly Boss Mods |
| [&lt;DBM Core&gt; Status Bar Timers](Interface/AddOns/DBM-StatusBarTimers)<br><sub>DBM-StatusBarTimers</sub> | 12.1.3 | MysticalOS, QartemisT | DBM - status bar timer library |
| [&lt;DBM Media&gt; Voicepack VEM](Interface/AddOns/DBM-VPVEM)<br><sub>DBM-VPVEM</sub> | 2f9d4f1 | Iceoven | Module ou extension de &lt;DBM Media&gt; Voicepack VEM. |
| [&lt;DBM Mod&gt; Bastonneurs](Interface/AddOns/DBM-Brawlers)<br><sub>DBM-Brawlers</sub> | — | MysticalOS | Module ou extension de &lt;DBM Mod&gt; Bastonneurs. |
| [&lt;DBM Mod&gt; Lairs (Midnight)](Interface/AddOns/DBM-Lairs-Midnight)<br><sub>DBM-Lairs-Midnight</sub> | 12.1.3 | MysticalOS | Module ou extension de &lt;DBM Mod&gt; Lairs (Midnight). |
| [&lt;DBM Mod&gt; Raids (Midnight)](Interface/AddOns/DBM-Raids-Midnight)<br><sub>DBM-Raids-Midnight</sub> | 12.1.3 | MysticalOS | Module ou extension de &lt;DBM Mod&gt; Raids (Midnight). |
| [&lt;DBM Mod&gt; World Bosses (Midnight)](Interface/AddOns/DBM-Midnight)<br><sub>DBM-Midnight</sub> | 12.1.3 | MysticalOS | Module ou extension de &lt;DBM Mod&gt; World Bosses (Midnight). |
| [&lt;DBM Tests&gt; Test runner for DBM](Interface/AddOns/DBM-Test)<br><sub>DBM-Test</sub> | — | — | Module ou extension de &lt;DBM Tests&gt; Test runner for DBM. |
| [Archon Tooltip](Interface/AddOns/ArchonTooltip)<br><sub>ArchonTooltip</sub> | 9.5.8 | Archon | Module ou extension de Archon Tooltip. |
| [Archon Tooltip DB - Europe](Interface/AddOns/ArchonTooltipDB_EU)<br><sub>ArchonTooltipDB_EU</sub> | — | Archon | Module ou extension de Archon Tooltip DB - Europe. |
| [Decursive -Ace3-](Interface/AddOns/Decursive)<br><sub>Decursive</sub> | 2.8.2 | John Wellesz | Affichage et guérison des affections avec un système évolué de filtrage et de priorité. |
| [Details! Damage Meter](Interface/AddOns/Details)<br><sub>Details</sub> | #Details.20260811.15270.172 | — | Essential tool to impress that chick in your raid. |
| [Details! Mythic+ Scoreboard](Interface/AddOns/Details_MythicPlus)<br><sub>Details_MythicPlus</sub> | #DMP.20260811.026 | — | A Details! team addon that shows a scoreboard at the end of Mythic+, and lets you keep track of your runs |
| [Details!: Compare 2.0](Interface/AddOns/Details_Compare2)<br><sub>Details_Compare2</sub> | — | — | Replace the Compare tab in the player breakdown window. |
| [Details!: Encounter Breakdown (plugin)](Interface/AddOns/Details_EncounterDetails)<br><sub>Details_EncounterDetails</sub> | — | — | Show detailed information about a boss encounter. Also provide damage per phase, graphic charts, easy weakauras creation. |
| [Details!: Raid Check (plugin)](Interface/AddOns/Details_RaidCheck)<br><sub>Details_RaidCheck</sub> | — | — | Show talents and item level for all members in your group, also shows food and flask state. |
| [Details!: Storage](Interface/AddOns/Details_DataStorage)<br><sub>Details_DataStorage</sub> | — | — | Stores information for Details! Damage Meter |
| [Details!: Streamer (plugin)](Interface/AddOns/Details_Streamer)<br><sub>Details_Streamer</sub> | — | — | Show which spells you are casting, viewers can see what are you doing and follow your steps. |
| [Details!: Tiny Threat (plugin)](Interface/AddOns/Details_TinyThreat)<br><sub>Details_TinyThreat</sub> | — | — | Threat meter plugin, show threat for group members in the window. Select it from the Plugin menu in the Orange Cogwheel. |
| [Details!: Vanguard (plugin)](Interface/AddOns/Details_Vanguard)<br><sub>Details_Vanguard</sub> | — | — | Show the health and debuffs for tanks in your group. |
| [ExBoss](Interface/AddOns/EXBoss)<br><sub>EXBoss</sub> | 1.0.0 | Exwind | BOSS 技能计时 + 语音提醒 |
| [ExBoss Data](Interface/AddOns/EXBossData)<br><sub>EXBossData</sub> | 1.0.0 | Exwind | ExBoss static encounter data module |
| [ExBoss Locale](Interface/AddOns/EXBOSS-Locale)<br><sub>EXBOSS-Locale</sub> | 1.0.0 | Exwind | EXBoss localization strings (zhCN / enUS + stubs) |
| [ExBoss Locale Base](Interface/AddOns/EXBOSS-LocaleBase)<br><sub>EXBOSS-LocaleBase</sub> | 1.0.0 | Exwind | EXBoss locale system bootstrap — must load before EXBOSS-Locale fills the stores |
| [ExBoss Voice Pack: English (ENG)](Interface/AddOns/EXBOSS-ENG)<br><sub>EXBOSS-ENG</sub> | 1.0.0 | ExwindStudio | ExBoss voice pack - English (ENG) |
| [ExBoss Voice Pack: EXWIND](Interface/AddOns/EXBOSS-EXWIND)<br><sub>EXBOSS-EXWIND</sub> | 1.0.0 | ExwindStudio | ExBoss 配套语音包，提供 EXWIND 系列语音标签 |
| [EXBOSS-VoixFrancaise02 VoicePack](Interface/AddOns/EXBOSS-VoixFrancaise02)<br><sub>EXBOSS-VoixFrancaise02</sub> | 1.0.0 | VoixFrancaise02 | EXBoss voice pack by VoixFrancaise02 |
| [Exwind Core](Interface/AddOns/ExwindCore)<br><sub>ExwindCore</sub> | 6.0.0 | Exwind | ExwindTools 核心引擎 |
| [LoggerHead Lite](Interface/AddOns/LoggerHeadLite)<br><sub>LoggerHeadLite</sub> | 1.7.3 | Neb | Automatically turns on the combat log for selected raid and mythic+ instances. |
| [M+ Marker](Interface/AddOns/MPlusMarker)<br><sub>MPlusMarker</sub> | 2.3.28 | Respls | Met à jour dynamiquement une macro de ciblage pour les donjons M+ avec une interface interactive. |
| [MDTHelper](Interface/AddOns/MDTHelper)<br><sub>MDTHelper</sub> | 9.0 | MDTHelper | Live route guide for MDT dungeon routes |
| [Method Raid Tools](Interface/AddOns/MRT)<br><sub>MRT</sub> | 5315 | ykiigor | Method Raid Tools |
| [Monk Stagger Bar Prime](Interface/AddOns/MonkStaggerBarPrime)<br><sub>MonkStaggerBarPrime</sub> | 2.0.2 | bljakk | Simple moveable stagger bar for Brewmaster Monks. Based on earlier work by Claude and Roffe. |
| [Mythic Dungeon Tools (MDT)](Interface/AddOns/MythicDungeonTools)<br><sub>MythicDungeonTools</sub> | 6.2.2 | Nnoggie | Outil pour planifier et optimiser vos parcours de donjons Mythique+ |
| [Mythic Dungeon Tools (MDT) - UI](Interface/AddOns/MythicDungeonTools_UI)<br><sub>MythicDungeonTools_UI</sub> | 6.2.2 | Nnoggie | Load-on-demand interface for Mythic Dungeon Tools |
| [Mythic Plus Pull](Interface/AddOns/MythicPlusPullReEstimated)<br><sub>MythicPlusPullReEstimated</sub> | v1.12.5 | Numy | Tracks and displays % progress gained from individual mobs or entire pulls in Mythic+ dungeons. /mpp for options |
| [O Item Level(OiLvL)](Interface/AddOns/Oilvl)<br><sub>Oilvl</sub> | 12.1.0 | OlzenKhaw, Teece | Shows Item Level of raiders in party / raid. Shows Item Level and raid progression on tooltips. |
| [PetAlert](Interface/AddOns/PetAlert)<br><sub>PetAlert</sub> | 3.1.1 | Kowkow | Premium combat pet alert console for missing pets, low health, and passive mode. |
| [Simulationcraft](Interface/AddOns/Simulationcraft)<br><sub>Simulationcraft</sub> | 12.1.0-02 | Theck, navv_, seriallos | Constructs SimC export strings |
| [WarpDeplete](Interface/AddOns/WarpDeplete)<br><sub>WarpDeplete</sub> | 5.4.2 | Happens | Module ou extension de WarpDeplete. |

</details>

<details>
<summary><strong>Sacs, économie et collections</strong> — 12 dossier(s)</summary>

| Addon | Version | Auteur | Présentation |
|---|---:|---|---|
| [Auctionator](Interface/AddOns/Auctionator)<br><sub>Auctionator</sub> | 334 | plusmouse, Borjamacare | A lightweight addon that makes it easy and fast to buy, sell and manage auctions |
| [Better Fishing](Interface/AddOns/BetterFishing)<br><sub>BetterFishing</sub> | 61 | Yuyuli | Single Keybind/Double Click Fishing and Enhanced Sound while fishing Slash command: /bf, /betterfishing |
| [BetterBags](Interface/AddOns/BetterBags)<br><sub>BetterBags</sub> | v0.4.10 | Cidan | Better Bags for everyone! |
| [BetterBags - Gear First](Interface/AddOns/BetterBags_GearFirst)<br><sub>BetterBags_GearFirst</sub> | v1.0.11 | Liwwo | Add options to show gear categories first. |
| [BetterBags - Keystones](Interface/AddOns/BetterBags_Keystones)<br><sub>BetterBags_Keystones</sub> | v1.4.1 | Avyiel | Adds a Mythic+ Keystones filter to BetterBags. |
| [FarmHud](Interface/AddOns/FarmHud)<br><sub>FarmHud</sub> | 1.1.14-release | Hizuro, CodeRedLin | Turns your minimap into a hud for gathering resources! |
| [KeystoneLoot](Interface/AddOns/KeystoneLoot)<br><sub>KeystoneLoot</sub> | 2.11.1 | Selina Ruesch | Shows the items from the mythic plus instances in a compact overview |
| [Majestic Beast Tracker](Interface/AddOns/MajesticBeastTracker)<br><sub>MajesticBeastTracker</sub> | v2.1.1 | Vichob | Tracks daily Majestic Lure beast cooldowns across all characters |
| [Myu's Knowledge Points Tracker](Interface/AddOns/MyusKnowledgePointsTracker)<br><sub>MyusKnowledgePointsTracker</sub> | 0.8.11 | Myu | Tracks acquisition of knowledge points for professions |
| [Simple Disenchant](Interface/AddOns/SimpleDisenchant)<br><sub>SimpleDisenchant</sub> | 1.7.4 | Artenola | Desenchantez facilement les objets de vos sacs |
| [Vaultloom - Compendium Data](Interface/AddOns/Vaultloom_Compendium)<br><sub>Vaultloom_Compendium</sub> | 1.1.2-beta | Legijaone | Load-on-demand Midnight collection catalog for Vaultloom. |
| [Vaultloom (Beta)](Interface/AddOns/Vaultloom)<br><sub>Vaultloom</sub> | 1.1.2-beta | Legijaone | Warband, weekly progress, character snapshots, collections, and optional quality-of-life tools. |

</details>

<details>
<summary><strong>Confort et outils</strong> — 10 dossier(s)</summary>

| Addon | Version | Auteur | Présentation |
|---|---:|---|---|
| [Account Played](Interface/AddOns/AccountPlayed)<br><sub>AccountPlayed</sub> | v1.6.3 | Jeremy-Gstein | get account /played and sort by class (/aplayed show OR minimap button) |
| [BugGrabber](Interface/AddOns/%21BugGrabber)<br><sub>!BugGrabber</sub> | v12.0.21 | Funkeh | Grabs bugs for the bug sack. |
| [BugSack](Interface/AddOns/BugSack)<br><sub>BugSack</sub> | v12.0.13 | Funkeh | Toss those bugs inna sack. |
| [Copybara](Interface/AddOns/Copybara)<br><sub>Copybara</sub> | 1.2.0 | MickeyPickey, sato942_ | Addon to copy your chat tabs and settings from one character to another. |
| [FastCinematicSkip](Interface/AddOns/FastCinematicSkip)<br><sub>FastCinematicSkip</sub> | 11.1 | BloodDragon2580 | Automatically cancels all InGame cinematics and movies. |
| [Premade Groups Filter](Interface/AddOns/PremadeGroupsFilter)<br><sub>PremadeGroupsFilter</sub> | 7.5.2 | Bernhard Saumweber | Permet de filtrer des groupes prédéfinis à l'aide d'une interface utilisateur ou d'expressions de filtre avancées. |
| [ThyraxUtil](Interface/AddOns/ThyraxUtil)<br><sub>ThyraxUtil</sub> | 5.2.5r | Thyrax | Mouse Tracker, Quest Accept Hotkey &amp; Combat QoL |
| [TomTom](Interface/AddOns/TomTom)<br><sub>TomTom</sub> | v4.3.8-release | Cladhaire, Ludovicus | Agit comme un assistant de navigation portable |
| [Unified Profile Manager](Interface/AddOns/UnifiedProfileManager)<br><sub>UnifiedProfileManager</sub> | v1.1.25 | Numy | A simple overview of all addon profiles for addons that use AceDB |
| [WIM](Interface/AddOns/WIM)<br><sub>WIM</sub> | 3.17.3 | Pazza (Bronzebeard), (Updated by Sylvanaar/MysticalOS/Humfras) | Donnez aux chuchotements une sensation de messagerie instantanée. |

</details>
<!-- ADDON_CATALOG_END -->

## Installation

1. Fermer World of Warcraft.
2. Copier `Interface` dans le dossier `_retail_`.
3. Pour récupérer les profils partagés, copier les fichiers de `WTF/Account/ACCOUNT/SavedVariables` dans le dossier `WTF/Account/<votre-compte>/SavedVariables`.
4. Lancer WoW et sélectionner/importer les profils voulus dans chaque addon.

Certains addons peuvent être désactivés ou incompatibles après une mise à jour du jeu. Les gestionnaires d'addons restent la meilleure manière de recevoir leurs mises à jour officielles.

## Mise à jour de la version publique

Le dépôt doit être placé à côté du dossier `_retail_`. Depuis ce dépôt, avec WoW fermé :

```powershell
.\Build-Public-Snapshot.ps1
git status
```

Le script applique de nouveau la liste blanche de réglages et toutes les règles d'assainissement avant publication.
