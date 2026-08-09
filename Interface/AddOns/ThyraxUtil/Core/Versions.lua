local _, ns = ...

-- Centralized version management for the ThyraxUtil suite.
-- Any changes here will be visible in the Git history for easier tracking of module updates.

-- Module versions are manually curated. They drive the onboarding "NEW" badge
-- (see Core/Onboarding.lua), so bump a module's version ONLY when that module
-- gets a user-visible new feature worth announcing -- not on every addon patch.
-- The addon-level version lives in ThyraxUtil.toc and is read via
-- C_AddOns.GetAddOnMetadata (ns.Compat.GetAddOnVersion).
ns.Versions = {
    CROSSHAIR = "0.4.9",  -- 0.4.9: Edit Mode button
    DARKNESS_ANNOUNCER = "0.4.5",
    DYNAMIC_FLIGHT_TRACKER = "0.4.6",
    MOUSE_TRACKER = "0.4.9",  -- 0.4.9: opacity slider (lannimite feedback)
    QUEST_ACCEPT_HOTKEY = "0.4.6",
    AUCTION_FILTER_PERSIST = "0.5.0",  -- 0.5.0: new module - persists Browse-tab AH filters across sessions with status overlay
    ACCOUNTING_TRACKER = "0.6.0",  -- 0.6.0: new module - per-character ledger of AH sales, vendor flow, repairs, quests, etc.
    CHARACTER_PANEL_ENHANCER = "0.1.0",  -- 0.1.0: CharacterFrame/InspectFrame gear readiness and custom stat overlays
}
