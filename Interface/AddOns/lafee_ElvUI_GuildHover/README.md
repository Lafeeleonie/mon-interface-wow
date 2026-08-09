# Lafee ElvUI Guild Hover

Lafee ElvUI Guild Hover is a World of Warcraft Retail extension for ElvUI. It adds interactive datatexts that show online contacts and members from your guild and each of your WoW communities.

Hover a datatext to open a clickable member list: left-click a member to whisper them, or right-click to invite their active WoW character.

## Requirements

- World of Warcraft Retail
- ElvUI (required)

This addon does not modify any ElvUI files.

## Features

- A dedicated **Guilde interactive** datatext for your guild.
- A dedicated **Contacts interactifs** datatext for WoW and Battle.net friends.
- One separate datatext for every subscribed WoW community.
- Community datatext IDs are stable and based on the community `clubId`, so duplicate or renamed community names are handled safely.
- Online member count displayed directly on every datatext.
- Interactive, ElvUI-styled member list instead of a static tooltip.
- Compact member rows with level and class-colored name.
- BattleTags are displayed in a right-hand column for Battle.net contacts only.
- Battle.net favorites are sorted first; Battle.net-only contacts are shown in blue.
- Contacts lists include online WoW and Battle.net friends only.
- Left-click to open a whisper.
- Right-click to invite eligible characters.
- Scrollable lists for communities or guilds with more than 18 online members.
- Debounced updates for guild and community roster events.
- Native friend-event updates plus a lightweight fallback refresh while a datatext is visible.
- `/lgh refresh` and optional debug mode.

## Installing

1. Download and extract the archive.
2. Place the `lafee_ElvUI_GuildHover` folder in:
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Start the game or type `/reload`.

## Adding the Datatexts in ElvUI

1. Open ElvUI options with `/ec`.
2. Open **Datatexts**, then select the panel and slot you want to use.
3. Select **Guilde interactive** for your guild roster.
4. Select **Contacts interactifs** for your WoW and Battle.net contacts.
5. Select a community by its exact community name for its own roster.

Each community is registered as a separate ElvUI datatext and appears in the normal datatext selection list.

## Member List Actions

- **Left-click:** opens a whisper to the selected member when a valid character or Battle.net chat target is available.
- **Right-click:** invites the selected member when a valid active WoW character is available.

Invites are disabled for your own character, members already in your group, mobile-only members without a playable WoW character, and restricted combat situations.

## Battle.net Community Limitations

Battle.net community members connected only through mobile chat are not counted as online WoW characters.

The addon never guesses a character name from a BattleTag. If the game does not provide a valid WoW character, the invite action is disabled. A Battle.net whisper is only offered when Blizzard provides usable account information.

## Commands

| Command | Description |
| --- | --- |
| `/lafeeguildhover` | Shows the addon version, registered community count, and help. |
| `/lgh` | Short command alias. |
| `/lgh refresh` | Manually refreshes guild and community member lists. |
| `/lgh debug` | Toggles debug messages. Disabled by default. |

If a community is removed, use `/reload` to remove its datatext cleanly from ElvUI's options.

## Troubleshooting

To show Lua errors, enter:

```text
/console scriptErrors 1
```

Then type `/reload` and report the full error message.
