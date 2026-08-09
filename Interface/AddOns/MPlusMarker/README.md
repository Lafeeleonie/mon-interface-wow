MPlusMarker (M+ Marker) - A Complete Guide 🚀



Hello! MPlusMarker is a lightweight and highly customizable World of Warcraft addon I put together to give you a huge advantage in Mythic+ dungeons. Blizzard is pretty strict about letting addons automatically target or mark enemies during combat. So, this handy tool gets around that by quietly updating your regular WoW macros on the fly every time you walk into a new dungeon or change your settings. It's really easy to use!



Here's a complete breakdown of what this addon does and how to set it up so you can get started right away.



🛠️ How It Works (The Macros)



When you log in or change zones, the addon quietly goes into your Account-Wide General Macros tab and creates five macros for you. Just drag them to your action bars once, and you're all set!



MPlusMarker (The Targeter):



What it does: It instantly clears your current target, scans the area for the enemies highest on your priority list, targets the top one, and puts a raid marker right on its head!



Backup Markers: Hold down SHIFT while pressing the macro to apply a secondary "Backup Marker" instead. Backup marks use the non-destructive `/tm ~` form, so they only apply if that enemy has no marker yet — helpful when two of the same mob are packed together.



MPlusFocus (The Focus Marker):



What it does: This is basically a universal mouseover macro! Just hover your mouse over an enemy, press the button, and they become your Focus target with a marker attached (it defaults to the Green Triangle). If that enemy already has a raid mark, your focus mark is skipped so you won't overwrite teammates.



In Instances: A row of raid icons appears on your screen while you are inside a dungeon or other instance. Left-click one to choose your focus marker on the fly. Left-click and drag the bar to move it anywhere on screen. Open the Focus Macro tab in `/mpm config` to preview the bar outside instances and adjust layout — use the orientation button to switch between horizontal and vertical.



Clearing: Press the macro with your cursor over empty ground (not on a unit) and it clears your focus and removes its mark. You can also hold SHIFT to clear the raid mark on mouseover, target, or focus without changing focus.



MPlusKick (The Smart Interrupt):



What it does: This casts your interrupt spell at your Focus target. Don't have a Focus? It just interrupts your current target instead.



Smart Detection: It knows exactly what class you're playing (like Pummel for Warriors or Counterspell for Mages). If you switch to a healer without a basic interrupt spell, it safely disables the macro so you don't get annoying error messages. Switch back to a damage-dealing class, and it's right back online!



MPlusKickAuto (Tab-to-Interrupt):



What it does: Like MPlusKick, but if your Focus isn't a valid hostile target it tabs to an enemy, interrupts, restores your previous Focus, and starts attacking. Great for off-target kicks without losing your focus assignment.



MPlusStop (The CC / Stun):



What it does: This works exactly like the interrupt macro, but it's designed for your stuns and major crowd control spells (like Storm Bolt, Paralysis, or Blinding Light).



🖥️ The Configuration Menu (/mpm config)



Just type /mpm config, click the minimap button, or look through your standard WoW AddOn settings to open the menu.



Managing Your Enemies



Dungeon Categories: Dungeons are neatly sorted into organized groups.



Reordering: Click the up and down arrows next to an enemy to change its priority. The macro will always target the enemy at the very bottom of the list first!



Assigning Markers: Click the main Raid Icon to cycle through the different marks. Hold SHIFT and click the smaller icon next to it to set up a Backup Marker.



Adding Enemies on the Fly



There is a dropdown menu and an input box at the top of the screen.



By Name: Pick a dungeon, type the enemy's name, and hit Enter. That's it!



By NPC ID: If you aren't sure how to spell the name, just type the enemy's ID number (like 196045). The addon will quietly ask the WoW server, grab the correct name with perfect capitalization, and add it for you. It's a great little feature!



🧠 Enemy Info \& MDT Integration



This addon has a wonderful tooltip and note system that connects perfectly with Mythic Dungeon Tools (MDT) if you happen to have it installed.



Hover Tooltips: Hover over any enemy in your list to see its abilities, immunities, and your own custom strategies.



The "Fetch MDT Info" Button: If you use MDT, just click this button! It checks MDT's massive database, figures out everything the enemy casts, checks if it Detects Stealth, and tells you if it's CC Immune (or fully vulnerable to crowd control). It saves all this information to MPlusMarker permanently. You can even turn MDT off afterward and the addon will still remember everything!



Custom Notes: Hold Shift and click an enemy's name to open the Note Editor. Here, you can type out your own strategies, interrupt assignments, or anything else you'd like to remember. Enemies with your custom notes will highlight in Cyan so they're easy to spot!



🛡️ Group Automation Features



These features are perfect for when you're playing with random groups and don't want to type everything out.



Ready Check Role Marking: If you're the Party Leader and start a Ready Check while out of combat, a little prompt will pop up asking if you want to mark the Tank (Square) and Healer (Moon). Just hit "Yes" and it marks them instantly! Marks use the non-destructive `/tm ~` form, so existing raid icons on those players are left alone.



Focus Announce: This automatically announces your Focus Marker in the local chat during a Ready Check, so your group knows not to overlap your interrupts. You can easily turn this off in the Focus Macro tab if you prefer.



💾 Account-Wide Settings \& Sharing



Account-Wide: Everything you set up (notes, markers, and priorities) saves to your account folder. Build your list on your main character, and your alternate characters will instantly have the exact same macros ready to go!



Import / Export: Use the buttons at the bottom of the menu to generate a text string of your dungeon priority lists (mob names, markers, notes, and NPC IDs). Custom notes are encoded safely for sharing. Import/export does not include focus-marker choice, kick/stop spell overrides, or other global settings — only per-dungeon mob lists.



Reset: Need a clean slate? Go to the standard WoW Interface AddOns menu and hit the reset button to wipe your database and bring back the default developer list.

