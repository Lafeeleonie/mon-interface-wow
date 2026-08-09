PetAlert
========

Version: 3.1.1
Author: Kowkow

PetAlert is a lightweight World of Warcraft addon that displays clear combat
alerts when an important combat pet is missing, in danger, or left in passive
mode.

Version 3.1.1 keeps the gameplay behavior stable and adds advanced pet health
bar customization with live preview styles, themes, textures, display toggles,
and opacity controls.

The options panel remains a premium alert console with a custom generated banner
texture, cleaner sections, stronger previews, visual presets, and client-locale
aware panel text.


Supported Alerts
----------------

Missing Pet Alert
- Shows when a monitored character enters combat without an active living pet.
- Uses the class/spec-appropriate alert icon unless a custom icon is selected.
- Can be moved, locked, reset, resized, enabled, or disabled.

Low HP Alert
- Shows when the active pet drops below the configured health threshold.
- Defaults to 25 percent.
- Uses a secret-safe health visibility curve on modern WoW clients.
- Low HP audio is intentionally not triggered on modern secret-value clients to
  avoid Lua errors and false-positive sound alerts.
- Can be moved, locked, reset, resized, enabled, or disabled.

Passive Mode Alert
- Shows when the active pet is set to Passive mode.
- Uses the passive pet command icon unless a custom icon is selected.
- Can be moved, locked, reset, resized, enabled, or disabled.

Pet Health Bar
- Optional movable pet health bar with pet icon and live percentage display.
- Uses Blizzard-safe status bar updates for modern secret-value clients.
- Includes a preview mode that appears above the configuration panel.
- Width, height, and RGB bar color can be adjusted from the options panel.
- Includes visual styles, color themes, fill textures, icon/percent/shine
  toggles, and opacity controls for faster customization.


Supported Classes
-----------------

Warlock
- Demonology only.
- Alert text/icon target: Felguard.

Death Knight
- Unholy only.
- Alert text/icon target: Ghoul.

Hunter
- Any active living pet.
- Marksmanship is monitored only when the relevant pet talent/spell is known.

Mage
- Frost only.
- Requires Water Elemental support.


Configuration
-------------

Open the panel from:

Game Menu -> Options -> AddOns -> PetAlert

or with:

/pa
/petalert

Available settings:
- Enable alerts out of combat.
- Enable or disable audio alerts.
- Select the audio alert sound.
- Test the current audio alert.
- Enable minimal icon-only mode.
- Show or hide the pet health bar.
- Preview and move the pet health bar.
- Adjust the pet health bar width, height, and RGB color.
- Apply pet health bar styles, themes, fill textures, display toggles, and
  opacity settings with live preview.
- Trigger live preview alerts from the Test Center.
- Run a full Missing -> Low HP -> Passive preview sequence.
- Apply Compact, Readable, Streamer, or Minimal visual presets.
- Show or hide the minimap shortcut.
- Lock or unlock the minimap shortcut position.
- Reset the minimap shortcut position.
- Choose a custom alert icon from the macro icon pool.
- Restore automatic class/spec icons.
- Enable or disable each alert type independently.
- Adjust the Low HP threshold from 1 to 99 percent.
- Adjust each alert icon size independently.
- Move, lock, and reset each alert position independently.
- Preview all alerts directly in the options panel.


Slash Commands
--------------

Main alert:
- /pa move
- /pa lock
- /pa reset
- /pa X Y

Out-of-combat behavior:
- /pa ooc on
- /pa ooc off

Low HP alert:
- /pa hpmove
- /pa hplock
- /pa hpreset
- /pa hp on
- /pa hp off
- /pa hp 25
- /pa hp X Y

Passive mode alert:
- /pa passivemove
- /pa passivelock
- /pa passivereset
- /pa passive on
- /pa passive off
- /pa passive X Y

Custom icon:
- /pa icon <textureID or texture path>
- /pa icon reset

Minimap shortcut:
- /pa minimap on
- /pa minimap off
- /pa minimap lock
- /pa minimap unlock
- /pa minimap reset

Test Center:
- /pa test
- /pa test main
- /pa test hp
- /pa test passive
- /pa test stop

Presets:
- /pa preset compact
- /pa preset readable
- /pa preset streamer
- /pa preset minimal


Examples
--------

/pa 0 200
Move the main alert higher on the screen.

/pa hp 30
Set Low HP alert to trigger at 30 percent.

/pa passive -200 0
Move the passive alert to the left.

/pa minimap reset
Restore the minimap shortcut to its default position.

/pa test
Run the full live alert preview sequence.

/pa preset streamer
Apply a large high-visibility baseline for streaming or raid leading.


Performance
-----------

PetAlert is designed to stay lightweight:
- No combat log scanning.
- No heavy background polling.
- Event-driven updates.
- Combat-focused alert behavior by default.
- Blizzard-safe textures and standard addon UI APIs.


Localization
------------

The options panel, minimap tooltip, test center, presets, sound labels, pet
health bar controls, and primary addon messages adapt to the client locale when
available. If a future key is missing, PetAlert falls back to English.

Covered WoW locales:
- enUS / enGB
- frFR
- deDE
- esES / esMX
- itIT
- ptBR
- ruRU
- koKR
- zhCN
- zhTW


Generated UI Assets
-------------------

Version 3.1.1 includes the custom generated console banner introduced in 3.0.0:
- media/petalert_panel_banner.tga
- media/petalert_panel_banner_source.png
- media/petalert_console_emblem.tga
- media/petalert_console_emblem_source.png

The TGA files are the addon-facing textures used by the options panel. The PNG
files are kept as source/reference assets for future iterations.


Version History
---------------

3.1.1
- Added pet health bar frame styles for faster visual customization.
- Added selectable pet health bar fill textures and color themes.
- Added display toggles for icon, percentage text, and shine highlight.
- Added background and border opacity controls.
- Updated the pet health bar preview workflow so theme and texture changes apply
  immediately.
- Updated addon metadata and configuration panel version display.

3.1.0
- Added an optional pet health bar with icon, live percentage, saved position,
  and Blizzard-safe status updates.
- Added pet health bar controls to the options panel: enable, preview, width,
  height, and RGB color.
- Made the pet health bar preview appear above the configuration panel.
- Reworked live alert visuals: removed the black backdrop, removed the cheap
  glow/ring treatment, added a simple alert-colored icon border, and added a
  subtle vertical shake animation.
- Removed unsafe Low HP audio attempts on modern secret-value clients. Low HP
  remains a visual alert only when the client seals pet health values.
- Expanded client-locale text coverage for the new pet health bar controls.

3.0.0
- Rebuilt the configuration panel with a custom premium console layout.
- Added generated panel banner and console emblem textures under media/.
- Added a polished minimap shortcut with tooltip, saved position, drag support,
  lock support, reset support, and slash commands.
- Added a Test Center that triggers the real alert frames and full alert sequence.
- Added a local timer fallback for the Test Center preview sequence.
- Added Compact, Readable, Streamer, and Minimal presets.
- Added premium alert fade, glow, ring, and pulse treatment without changing
  core alert rules.
- Added broad client-locale aware text coverage for the panel and addon messages.
- Improved section previews, button styling, spacing, and visual hierarchy.
- Added safer compatibility fallbacks around options registration and spell-known checks.
- Kept the existing alert behavior and saved variable structure.

2.2.6
- Previous stable release before the 3.0.0 interface refresh.

2.2.5
- Added optional audio alerts.
- Added selectable in-game alert sounds.
- Added minimal mode for icon-only alerts.
