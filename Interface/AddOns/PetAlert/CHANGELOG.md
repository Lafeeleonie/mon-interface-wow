# PetAlert Changelog

## 3.1.1

- Added pet health bar frame styles for faster visual customization.
- Added selectable pet health bar fill textures and color themes.
- Added display toggles for icon, percentage text, and shine highlight.
- Added background and border opacity controls.
- Kept manual width, height, and RGB sliders so presets can be fine-tuned.
- Updated the live pet health bar preview to reflect style, theme, texture, and display changes immediately.
- Updated addon metadata and configuration panel version display.

## 3.1.0

- Added an optional pet health bar with pet icon, live percentage display, saved position, and Blizzard-safe status bar updates.
- Added pet health bar options in the configuration panel: enable toggle, preview button, width, height, and RGB color sliders.
- Made the pet health bar preview render above the configuration panel.
- Reworked alert visuals by removing the black backdrop and glow/ring effect, replacing them with a clean alert-colored icon border.
- Added a subtle slow vertical shake animation to live alert frames.
- Removed unsafe Low HP audio attempts on modern secret-value clients. Low HP remains a visual alert when pet health values are sealed by Blizzard.
- Updated new pet health bar UI text across all supported client locales.

## 3.0.0

- Rebuilt the configuration panel with a custom premium console layout.
- Added generated panel banner and console emblem textures under `media/`.
- Added a polished minimap shortcut with tooltip, saved position, drag support, lock support, reset support, and slash commands.
- Added a Test Center that triggers the real alert frames and full alert sequence.
- Added Compact, Readable, Streamer, and Minimal presets.
- Added broad client-locale aware text coverage for the panel and addon messages.

## 2.2.6

- Previous stable release before the 3.0.0 interface refresh.

## 2.2.5

- Added optional audio alerts.
- Added selectable in-game alert sounds.
- Added minimal mode for icon-only alerts.
