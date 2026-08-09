# Majestic Beast Tracker

## [v2.1.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v2.1.0) (2026-08-07)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v2.0.3...v2.1.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Profession stat fixes, AH price comparison for lures, Carve Meat and Path of the Windrunners buttons, always-visible reagent counts

### Profession Stat Fixes
- **Careful Carving corrected** — Now grants +2 Finesse per point (was wrongly +1 Perception)
- **Thorough Tanning corrected** — Root now grants +1 Skill per point (was wrongly +1 Perception)
- **No more double-counting** — Points in sub-paths no longer also grant the tree root's per-point stat
- **Unlock breakpoints fixed** — Unlock perks (Sharpen Your Knife, species reagents, Carve Meat, lures) no longer add phantom +5 stats
- **Argentleaf Tea detected** — Relaxed buff (+Finesse) now included in profession stats
- **Haranir Phial of Finesse detected** — Now included in profession stats alongside the Perception phial

### AH Price Comparison (NEW)
- **Lure profitability at a glance** — Lure tooltips now show the lure's craft cost vs. the AH value of its Majestic drops (Hide, Claw, Fin, Fantastic Fur, Peerless Plumage, Carving Canine)
- **Works without TSM** — Prices come from TSM when available, otherwise from Auctionator scan data

### New Buttons
- **Carve Meat** — Track the Carve Meat cooldown next to Sharpen Your Knife in the consumable bar (own show/hide toggle in settings)
- **Path of the Windrunners** — Travel button for the Windrunner Spire teleport, shown when the Keystone Hero spell is known

### Reagent Display
- **Always Show Counts** — New optional setting keeps reagent numbers and colors visible even when lures are Ready/Done, so you can see your stock while gathering for the week ahead
- **Travel bar layout** — The panel now widens automatically when many travel buttons are shown instead of overflowing

## [v2.0.3](https://github.com/VichobAddons/MajesticBeastTracker/tree/v2.0.3) (2026-06-17)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v2.0.2...v2.0.3) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Add WoW 12.0.7 interface support

### Compatibility
- **12.0.7 support** — TOC updated to support the 12.0.7 patch alongside existing 12.0.1 and 12.0.5

## [v2.0.2](https://github.com/VichobAddons/MajesticBeastTracker/tree/v2.0.2) (2026-04-12)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v2.0.1...v2.0.2) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Add WoW 12.0.5 interface support

### Compatibility
- **12.0.5 support** — TOC updated to support upcoming 12.0.5 patch alongside existing 12.0.1

## [v2.0.1](https://github.com/VichobAddons/MajesticBeastTracker/tree/v2.0.1) (2026-04-12)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v2.0.0...v2.0.1) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Performance overhaul, drop rate tracking, character row scrolling, and multiple bug fixes

### Performance
- **Significantly reduced CPU usage** — Layout and refresh logic separated; layout only runs when UI structure changes, not on every update
- **Event debouncing** — Rapid bag/inventory events coalesced instead of triggering individual full updates
- **Combat optimization** — Heavy events unregistered during combat, re-registered after
- **Cached calculations** — Profession stats, item icons, item names, and tool enchant state cached with smart invalidation

### Drop Rate Tracking (NEW)
- **Drop % column** — Optional column in Loot Summary showing personal drop rates per item
- **Two display modes** — Percentage (capped at 100%) or per-kill average (e.g. 2.3/kill), toggle via Shift-click or Settings
- **Per-character and global** — Drop rates shown in character loot tooltips and global Loot Summary
- **Beast breakdown** — Per-beast drop rates in the breakdown view
- **Tracked from v2.0.1** — Kill counter starts fresh to ensure accurate data; footer shows sample size

### Character Row Scrolling (NEW)
- **Scrollable character list** — Configurable max visible rows (5-30) with gold-themed scrollbar
- **Smart sorting** — Characters with beasts ready to kill shown first, characters on cooldown sorted to bottom

### Consumable Improvements
- **Locale-safe buff detection** — Consumable buffs detected via spell IDs instead of English names
- **Per-consumable stock ranges** — Tea (0-5), Phial (0-10), Root Crab (0-200), Razorstone (0-5)
- **Disabled consumables excluded** — Hidden consumables no longer appear in Auctionator shopping list
- **Razorstone timer** — Shows "Active" when enchant has more than 30 minutes remaining

### CSV Export
- **Full history export** — All 90 days of history plus current reset and AllTime remainder
- **Character metadata** — Class and level included in export
- **Import improvements** — Creates missing characters, supports append mode, imports TSM prices

### Bug Fixes
- Fix Auctionator shopping list crash with spell-only consumables (Sharpen Your Knife)
- Fix secret value taint error in dungeons/instances
- Fix Sharpen Your Knife button losing spell type after clicking
- Fix "Done" status showing when lures are in bags but beast not killed
- Fix tool icon not hiding when Razorstone enchant is active
- Fix tool icon reappearing after zone change (hearthstone, teleport)
- Fix character detail popup not closing when main frame hides
- Fix TSM price labels disappearing when lure borders are hidden
- Fix settings toggles not updating the tracker layout

## [v2.0.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v2.0.0) (2026-04-06)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.6.0...v2.0.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Major overhaul: architecture refactor, gold UI theme, loot history with calendar, CSV export, consumable tracker expansion, and loot editor redesign

### Architecture Refactor
- **File split** — UI.lua split into UI, LootUI, GearPopup, Settings, CalendarPicker, and Components/ConsumableBar for maintainability
- **Component extraction** — ConsumableBar is now a standalone reusable component

### Toolbar (NEW)
- **Dedicated toolbar row** — All action buttons moved to a separate toolbar at the top of the tracker
- **Custom Tabler icons** — Gold-themed icons for Close, Auto-Hide, Reagents, TSM Coins, Loot Summary, Warbank Deposit, Auctionator Shopping List
- **Title in toolbar** — "Majestic Beast Tracker vX" displayed in the toolbar
- **Consistent hover effects** — Gold icons brighten on hover, close button turns red

### Loot Summary Window (NEW)
- **Separate loot window** — Click the loot summary button to open a dedicated loot summary window instead of a tooltip
- **3-column layout** — Item name, Reset count+value, and All Time count+value in clearly separated columns
- **Beast breakdown toggle** — Expand to see loot grouped by beast with localized headers (Zone — NPC Name via tooltip scan)
- **Custom scroll** — Custom mousewheel scroll handler replacing UIPanelScrollFrameTemplate (fixes rendering glitch)
- **Dynamic item name width** — Adapts to longest item name for locale support
- **Smart positioning** — Window opens on the left side if the tracker is near the right edge of the screen, auto-repositions when dragging the main frame
- **Custom loot tooltip** — Replaces GameTooltip for per-char and global hover with proper 3-column layout

### Loot History (NEW)
- **90-day archive** — Daily loot is archived on reset and stored for 90 days (covers a full patch cycle)
- **Per-character history** — Browse historical loot data per character with pagination
- **Global summary history** — View combined loot history across all characters
- **Calendar picker** — Reusable CalendarPicker component with data dots on days that have loot data
- **Server reset awareness** — Calendar dates align with server daily reset cycle, not local midnight

### CSV Export (NEW)
- **Export button** — Click in the loot summary toolbar to export loot data
- **Per-character flat data** — Item ID, quality, beast, date in analytics-ready format
- **Beast breakdown** — Grouped by beast with reset date headers
- **Gold values** — Includes TSM gold values to avoid overflow
- **Scrollable window** — View and copy export data from a scrollable text popup

### Loot Editor Redesign
- **3-column layout** — Separate Reset (editable) and All Time (readonly) columns
- **Toolbar** — Title bar with close button and lock toggle
- **Lock toggle** — Lock/Unlock All Time values with Lock/LockOpen icon states
- **Minus control** — Minus button disabled by default, toggle in toolbar to enable; always allows reset decrease

### Consumable Bar (Enhanced)
- **Razorstone tracker** — Tooltip scan for remaining tool enchant duration
- **Sharpen Your Knife tracker** — Spell cooldown tracking with secret value pcall wrapping
- **Show/hide per item** — Settings toggle for each consumable (Tea/Crab default OFF)
- **Moved to header area** — Consumables and travel buttons relocated from bottom to the old title space
- **Even spacing** — Dynamic NAME_COL_WIDTH based on visible consumable count
- **TravelBox** — Travel buttons in their own gold-bordered box below consumable box
- **Dynamic header height** — Adapts to max of lure icons vs consumable+travel boxes

### UI Theme
- **Gold color scheme** — All borders, separators, title text, and accent colors changed from blue to gold
- **Border toggles** — Separate settings for Lure+Reagents and Travel+Consumables borders
- **All borders 0.7 alpha** — Consistent transparency across all border elements
- **Lure borders** — Always visible when toggled on, match consumable+travel height when reagents are off
- **Lure icon centering** — Centered vertically relative to consumable+travel area

### Window Management
- **Autohide sync** — Auto-hide state synced across all MBT windows (main, loot summary, editor, calendar)
- **OnHide cascading** — Closing the main window cascades to all sub-windows
- **Smart positioning** — All windows auto-reposition on drag, calendar follows loot summary

### Settings Dropdown (NEW)
- **Toolbar gear icon** — Quick settings access from the tracker toolbar
- **Fly-out submenus** — Hover a category to open its settings panel beside the main menu
- **Categories** — Route, Reagents & AH, Consumables, Loot Tracking, Warband Bank, Display, Borders
- **Enabled/Disabled** — Green/red status labels for each toggle
- **Auto-Hide button** — Moved to left side of toolbar for quick toggle

### Travel Bar (Enhanced)
- **Dalaran Hearthstone** — Added as static travel button
- **Hearthstone toy selector** — Drag any Hearthstone toy onto the HS slot to replace it (validates via tooltip text)
- **Shift+Right-click** — Reset custom HS back to default
- **Mage Teleport: Silvermoon** — Class-conditional travel button (classID 8)
- **Vulpera Return to Camp** — Race-conditional travel button (raceID 35)
- **Spell travel buttons** — Full support for spell-type travel (icon, cooldown, tooltip, secure action)

### Consumable Bar (Enhanced)
- **Sharpen Your Knife charges** — Shows X/Y charges with recharge timer, cooldown sweep when 0 charges
- **Razorstone auto-apply** — Click Razorstone icon, then click tool icon next to character name to apply enchant
- **Tool icon on tracker** — Skinning tool shown next to current character name when Razorstone is active and no enchant applied
- **Secret value taint fix** — All spell charge/cooldown logic inside pcall for instanced content

### Buff Tracking (NEW)
- **Kill-time buff snapshot** — Active consumable buffs recorded per beast kill (tea, phial, crab, razorstone, sharpen knife)
- **History integration** — Buff data archived with daily loot history (90 days)
- **Loot editor display** — "Buffs:" line shown in per-character loot editor (current day + history)
- **CSV export** — Active Buffs column added to CSV export (semicolon-separated per beast)

### Lure Bag Tracking (NEW)
- **Pre-crafted lure detection** — Tracks lures already in bags per character
- **Reagent count reduction** — Characters with lures in bags excluded from reagent need calculations
- **Cap at 1** — Only one lure per type matters (soulbound, one use per day)

### Locale Support
- **Stat parsing** — Skill, Perception, Finesse, Deftness names resolved from spell IDs (locale-safe)
- **Talented Tracker** — Detection via pathNode ID 106119 instead of English name search (fixes "Locked" on non-English clients)
- **TalentData.lua** — New module with all 10 skinning talent path IDs for locale-safe talent detection
- **Numeric IDs** — ClassID/RaceID used for Mage/Vulpera travel button detection

### Instance Guard (NEW)
- **Disable in instances** — Addon hides and stops processing in dungeons, raids, PvP, arenas, scenarios (including Delves)
- **Toggleable** — Settings > Display > "Disable in Instances" (default ON)
- **Chat notification** — Shows message when trying to open tracker in instance

### Bottom Bar (NEW)
- **Dedicated bottom bar** — Timer, Total Needed (gold), and Logout button in a styled bar
- **Consistent theme** — Same dark background and gold separator as top toolbar

### Warband Bank
- **Taint warning** — Added note in Warband Bank settings about potential bag interaction issues after depositing

## [v1.6.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.6.0) (2026-03-27)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.5.1...v1.6.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Route system with custom beast ordering, per-beast skip toggles, and auto-waypoint navigation

### Route System (NEW)
- **Per-beast skip** — Skip individual beasts from your daily route (e.g. skip Zul'Aman and Harandar)
- **Harandar min level** — Automatically skip Harandar for characters below a set level (80-90 slider) since the mobs are high level and slow to kill on lower characters
- **Hide Skipped Columns** — Completely remove skipped beast columns from the tracker for a cleaner view
- **Custom route order** — Reorder beasts in the Settings panel with up/down arrow buttons to match your preferred route
- **Auto-Waypoint** — After killing a beast, automatically sets a map waypoint to the next beast in your route. Skips beasts that are already killed, skipped, or locked. Clears waypoint when route is complete

### Hide Characters
- **Hide from tracker** — Right-click a character name and select "Hide character" to remove them from the tracker without deleting their data
- **Show Hidden Characters** — Toggle in Data Management to temporarily reveal hidden characters
- **Route-aware** — Hidden characters are excluded from reagent counts, costs, and AH calculations

### Auto-Hide
- **Fade on mouse leave** — Tracker fades out when your mouse leaves the frame, fades back in on hover
- **Toggle button** — Invisibility icon next to close button for quick toggle
- **Settings toggle** — "Auto-Hide on Mouse Leave" in Display section

### Per-Beast Loot Tracking
- **Loot breakdown by beast** — Hover the goblin icon to see loot per beast (e.g. how much you got from Voidstorm vs Grand Beast)
- **This Reset vs All Time** — Two-column tooltip showing daily and total loot with item quality colors

### Expandable Settings
- Settings panel reorganized into collapsible sections: Route, Reagents & AH, Loot Goblin, Warband Bank, Display, Data Management, and Slash Commands
- General settings (Minimap Icon, Chat Notifications, Hide on Non-Skinners) always visible at the top

### Improvements
- **Warband Bank deposit** — More reliable item deposits using UseContainerItem API instead of cursor manipulation
- **Stats layout** — Profession stats automatically wrap to two rows when the tracker is narrow (fewer columns)
- **Consumable stock fix** — AH autofill now correctly counts only items in your bags, not your warband bank

## [v1.5.1](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.5.1) (2026-03-18)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.5.0...v1.5.1) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Fixed version label showing "Dev" when MajesticBeastTrackerDev addon is installed but disabled

## [v1.5.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.5.0) (2026-03-18)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.4.1...v1.5.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

### Auction House Integration (NEW)
- **Autofill AH Quantity** — When browsing commodities in the Auction House, automatically fills the buy quantity with the number of missing reagents or consumables
  - Hooks into Blizzard's `CommoditiesBuyFrame` via `hooksecurefunc` using the native event system to avoid taint
  - Works with both lure reagents and consumables (based on stock targets)
  - Respects "Show Reagent Icons" toggle — disabled when reagents are hidden
  - New "Autofill AH Quantity" toggle in settings
- **Auctionator Shopping List** — New button (scroll icon) next to the loot goblin creates/updates an "MBT Reagents" shopping list in Auctionator
  - Includes all missing lure reagents with exact quantities needed
  - Includes consumables below their stock target (per-item configurable)
  - Uses `Auctionator.API.v1.CreateShoppingList` and `ConvertToSearchString` with quantity support
  - Button only visible when Auctionator addon is loaded
  - Automatically removes the list when all reagents are ready

### Reagent Display
- **Show Missing Count** — New toggle to show missing reagent counts (e.g. "-56") instead of have/need (e.g. "16/72")
  - Checkmark icon shown when all reagents are available
  - Per-reagent values centered under each icon

### Settings Overhaul
- New **Reagents** section grouping: Show Reagent Icons, Count for All Characters, Show Missing Count, Autofill AH Quantity, and per-consumable stock sliders
- New **Display** section for Show Weekly Knowledge, Hide in Combat, Lock Frame, Window Scale
- **Consumable Stock Targets** — Per-item sliders (0–200) for Sanguithorn Tea, Haranir Phial of Perception, and Root Crab
  - Controls how many of each consumable to include in the Auctionator shopping list
  - Also used by AH autofill when buying consumables

### Bugfixes
- Fixed all remaining ADDON_ACTION_BLOCKED taint errors — wrapped title, consumable box, travel buttons, stats, and all other layout operations in a single `InCombatLockdown()` guard
- Fixed title text overlapping character rows when reagent icons are hidden — adaptive 2-line/3-line title based on reagent toggle state
- Fixed version label showing CurseForge version instead of Dev version when running MajesticBeastTrackerDev
- Fixed dynamic button positioning — Auctionator and Warband Bank buttons chain correctly based on visibility

## [v1.4.1](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.4.1) (2026-03-14)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.4.0...v1.4.1) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Fixed ADDON_ACTION_BLOCKED error that could occur during combat, preventing loot tracking from updating

## [v1.4.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.4.0) (2026-03-14)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.3.0...v1.4.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Major feature update with 1500+ lines of new code: loot tracking, TSM price integration, warband bank deposit, loot editor, craftable count, consumable overhaul, UI redesign, and numerous bugfixes

### Loot Tracking (NEW)
- Automatic loot tracking from Majestic Beast kills using pre-combat bag snapshots
- Tracks all skinning reagents per character with daily reset and all-time totals
- Pre-combat bag snapshot (`PLAYER_REGEN_DISABLED`) captures bag state before loot arrives
- Kill detection via `SyncKillsFromQuests` triggers loot diff with 5-second finalization window
- Per-character goblin icons — click to open loot editor, hover for loot summary tooltip
- Global loot summary goblin icon shows combined loot across all characters
- Loot data persists in SavedVariables with automatic daily reset

### TSM Price Integration (NEW)
- Loot values calculated using TSM `DBMinBuyout` prices snapshotted at loot time
- Prices stored per-item in SavedVariables — shows what you earned when you looted, not current market price
- Falls back to current TSM price for items without saved prices
- Toggle TSM integration via coin icon button or settings
- "Total needed" gold display shows reagent cost for remaining lure crafts
- `FormatGold` / `FormatGoldPositive` helpers for consistent gold formatting

### Loot Editor (NEW)
- Click goblin icon to open per-character loot editor panel
- Shows all tracked reagents with quality tier atlas icons (`Professions-ChatIcon-Quality-12-TierX`)
- Click count to type exact values via inline EditBox — Enter to confirm, Escape to cancel
- Plus/minus buttons for quick adjustments
- Item tooltips on hover (`GameTooltip:SetItemByID`)
- "Loot sync in progress..." overlay blocks editing during active sync
- Closes only via X button or when tracker closes (no accidental close on misclick)
- Item names preloaded asynchronously via `C_Item.RequestLoadItemDataByID` to prevent blank entries on first open

### Warband Bank Deposit (NEW)
- New "Warband Bank" settings section with four toggles:
  - "Enable Warband Bank Deposit" — shows deposit button on tracker when bank is open
  - "Automatically Deposit on Bank Open" — deposits tracked reagents when you open the bank
  - "Deposit Beast Rewards" — include skinning loot (hides, leather, plating, scales)
  - "Deposit Lure Reagents" — include fish used to craft lures
- Primary method: clicks Blizzard's built-in "Deposit All Warband Items" button (no taint)
- Fallback: pcall-wrapped cursor-based item transfer for individual deposits
- Finds partial stacks first, then empty slots via `C_Bank.FetchPurchasedBankTabIDs`
- Deposit button appears on tracker only when Warband Bank is open (`BANKFRAME_OPENED`/`BANKFRAME_CLOSED`)

### Craftable Count (NEW)
- `GetCraftableCount(recipeID)` calculates how many lures you can craft from current reagents
- Counts reagents from bags + bank + warband bank via `C_Item.GetItemCount`
- Displayed in lure header tooltips and reagent icon tooltips

### Consumables (NEW + Enhanced)
- Added Root Crab (Midnight Perception buff) as third consumable alongside Tea and Phial
- Root Crab supports stackable buff — shows remaining time + bag count simultaneously (e.g. "30s 83x")
- Stackable buffs bypass the 20% duration block so you can keep stacking
- Real-time 1-second ticker updates consumable buff timers live (no more stale times)
- Time display shows seconds when under 60s (was always rounding up to 1m)
- Root Crab's Midnight Perception buff included in profession stat calculation

### Header Icon Buttons (NEW)
- Fish toggle button — show/hide reagent icons above lure headers
- Coin toggle button — enable/disable TSM price display
- Global goblin summary button — hover for all-character loot totals
- Warband deposit button — click to deposit tracked items (visible when bank open)
- All header buttons with icon textures, tooltips, and hover highlights

### UI Overhaul
- New branding: "Majestic Beast Tracker" multiline title with version number in the lure icon area
- Bottom bar redesign: consumable box, travel icons, and profession stats on a single compact row
- Golden hover border highlights on lure icons, travel buttons, and consumable icons (HIGHLIGHT layer)
- Zone labels below lure icons enlarged for readability (7pt → 9pt)
- Travel icon cooldown numbers scaled down (0.7x) for readability on smaller icons
- Divider line separates character rows from bottom bar
- Goblin icons stay visible when loot tracking is disabled (greyed out, no interaction)
- Frame width remains constant when toggling loot tracking on/off

### Midnight Skinning Detection
- Now requires actual Midnight Skinning specialization, not just base Skinning
- Uses `C_SpellBook.IsSpellKnown(471014)` for reliable detection
- Characters with only base Skinning are no longer shown in the tracker
- Real-time detection via `SKILL_LINES_CHANGED` — learns/unlearns update instantly without reload

### Quest Flag False Positive Fix
- Players without Talented Tracker had all 5 beast quest flags returning true (Blizzard API quirk)
- Added sanity check on login: if all 5 flags are true but no kills recorded, flags are ignored
- Real-time events (`LOOT_CLOSED`, `BAG_UPDATE_DELAYED`) bypass sanity check so actual kills are always recorded

### Skill Stat Calculation Fix
- Fixed Skill showing 11 instead of 1 for new Midnight Skinning learners
- `GetSkinningSkillLevel()` now verifies professionName contains "Midnight" before returning skill level
- Fixed perk counting: perks with unlockRank=0 no longer counted when player has 0 talent points

### Locked Lure Display
- Lure icons greyed out (desaturated + dimmed) for lures the character can't craft
- "Locked" label shown when no characters are eligible for a lure column
- Kill status still visible on locked lures (dimmed colors) so tracking works regardless of talent points

### Consumable Level Requirements
- Consumables now show level requirement when player is too low level
- Sanguithorn Tea requires level 80, Haranir Phial of Perception requires level 81, Root Crab requires level 80
- Icons greyed out with "Lv80"/"Lv81" label for ineligible characters

### Character Management
- Right-click a character name to open context menu with "Remove character" option
- Confirmation dialog before removal to prevent accidents

### Gear Popup Improvements
- Current character shows "No gear equipped" instead of generic message
- Other characters show "No gear data (login required)" for clarity

### New Slash Commands
- `/mbt debug stats` — show profession stat breakdown
- `/mbt debug gear` — show skinning gear detection
- `/mbt debug calc` — show stat calculation details

## [v1.3.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.3.0) (2026-03-12)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.2.0...v1.3.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Major feature update: reagent tracking, weekly knowledge quests, quest-based kill detection, and UI overhaul

### Kill Detection Overhaul
- Kill detection completely rewritten using hidden quest flags per beast
- Each beast has a daily quest ID that Blizzard flags on kill - 100% reliable
- Real-time tracking via QUEST_TURNED_IN event
- Quest flags sync on login, catching kills from other sessions or addons
- Removed old LOOT_OPENED + target GUID system which could miss kills when target changed
- Ready status shown with proper green checkmark icon instead of UTF-8 character

### Reagent Icons
- Reagent icons displayed above each lure column header
- Shows have/need count (e.g., 4/48) when materials are missing
- "Ready" centered across the column when all reagents are sufficient
- "Done" when all characters have already killed that beast
- Only counts characters that still need the lure (excludes already-killed)
- Includes Warbank/Account Bank in item counts
- Shift-click any reagent icon to link item to chat
- Tooltip shows per-lure cost, total need, and missing count
- Fish toggle button next to close button to quickly show/hide reagent icons
- New "Show Reagent Icons" setting
- New "Reagent Count: All Characters" setting to toggle between total need vs single lure need

### Weekly Knowledge Quest Tracking
- Tracks Midnight Skinning weekly knowledge quests per character:
  - Trainer Quest (3 KP, weekly rotation)
  - Skinning Drop / Fine Void-Tempered Hide (5 KP, each tracked individually)
  - Bonus Drop / Mana-Infused Bone (3 KP)
  - Treatise (1 KP, only triggers when consumed, not when in bags)
  - Darkmoon Faire (3 KP, only shown during DMF week)
- Gear popup shows full weekly status for each character
- Main tracker shows only incomplete quests below stats (disappears when all done)
- Real-time updates via BAG_UPDATE_DELAYED and QUEST_TURNED_IN
- Resets automatically on weekly server reset
- New "Show Weekly Knowledge" setting (controls main window only)

### Zone Labels
- Zone names shown below lure icons (Eversong, Zul'Aman, Harandar, Voidstorm, Grand Beast)
- Color-coded to match each lure's theme color

### Lure Column Borders
- Each lure column has a colored border box matching the lure's theme color
- Visual separation between lure columns for better readability

### Profession Stats in Gear Popup
- Gear popup shows per-character stats: Skill, Perception, Finesse, Deftness
- Stats saved to DB per character (base + talents + gear, excluding buffs)
- Updates on login, talent changes, skill changes, and gear swaps
- Item names colored by rarity (green/blue/purple)

### Non-Skinner Auto-Hide
- Tracker no longer opens automatically on characters without Skinning
- Minimap icon always available, frame can still be opened manually
- New "Hide on Non-Skinners" setting

### Layout Improvements
- Column width increased for better reagent count readability
- Two-reagent lures: count texts spread outward for clear separation
- 8px gap between reagent icons on multi-reagent lures

## [v1.2.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.2.0) (2026-03-10)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.1.1...v1.2.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Profession stats display showing Skill, Perception, Finesse, and Deftness

### Profession Stats
- Shows your total Skill, Perception, Finesse, and Deftness at the bottom of the tracker
- Combines stats from talent tree perks, per-point bonuses, equipped gear, and active buffs
- Updates automatically when you drink consumables, change gear, or apply talent points
- Color-coded labels: Skill (gold), Perception (green), Finesse (blue), Deftness (orange)

### Debug Commands
- New `/mbt debug calc` command to see detailed stats breakdown
- New `/mbt debug stats` and `/mbt debug gear` for advanced troubleshooting

## [v1.1.1](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.1.1) (2026-03-10)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.1.0...v1.1.1) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Settings improvements and UI polish

### New Settings
- **Chat Notifications** toggle - disable [MBT] messages in chat
- **Hide in Combat** toggle - automatically hide the tracker during combat

### Improvements
- Logout button moved to bottom-right corner with text label
- Wormhole Generator now correctly detected as a toy
- Removed debug messages from chat output

## [v1.1.0](https://github.com/VichobAddons/MajesticBeastTracker/tree/v1.1.0) (2026-03-09)
[Full Changelog](https://github.com/VichobAddons/MajesticBeastTracker/compare/v1.0.5...v1.1.0) [Previous Releases](https://github.com/VichobAddons/MajesticBeastTracker/releases)

- Consumables, travel buttons, lure enhancements, gear popup

### Consumable Tracking
- Track Sanguithorn Tea and Haranir Phial of Perception with icons at the top of the frame
- Shows remaining buff duration or bag count
- Click to use, Shift-click to search in Auction House
- Golden glow when item is in bags but buff is not active
- Won't accidentally consume if buff still has over 20% duration left

### Lure Improvements
- Click a lure icon to use it directly
- Shift-click to open recipe, press Shift-click again while recipe window is open to start crafting
- Right-click to set a waypoint to the lure's location
- Shows craftable count (including materials in Warbound bank)
- Yellow glow when a lure is ready to use

### Travel Buttons
- Quick-access buttons below the tracker: Hearthstone, Arcantina Key, and Wormhole Generator (Engineering only)
- Shows cooldown timers on each button

### Gear Popup
- Click a character's name to see their equipped skinning tools and accessories

### Logout Button
- Quick logout/character switch button next to the close button
