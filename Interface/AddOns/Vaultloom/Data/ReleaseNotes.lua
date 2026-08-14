local _, Addon = ...

local L = Addon.L
local MAX_RELEASE_HISTORY = 12

local function buildReleaseNotes()
    local releases = {
        {
            version = "1.1.2-beta",
            title = L.RELEASE_1_0_3_UPDATE_TITLE,
            state = L.RELEASE_1_0_3_UPDATE_STATE,
            subtitle = L.RELEASE_1_0_3_UPDATE_SUBTITLE,
            newFeatureIDs = {
                "stat_focus",
                "midnight_rare_map_pins",
                "midnight_treasure_map_pins",
            },
            newInterfaceIDs = {
                "compendium_tab",
                "pve_rares_tab",
            },
            sections = {
                {
                    title = L.RELEASE_1_0_3_UPDATE_SECTION_HIGHLIGHTS,
                    items = {
                        L.RELEASE_1_0_3_UPDATE_STAT_FOCUS,
                        L.RELEASE_1_0_3_UPDATE_STAT_FOCUS_NOTE,
                        L.RELEASE_1_0_3_UPDATE_COMPENDIUM,
                        L.RELEASE_1_0_3_UPDATE_RARES,
                        L.RELEASE_1_0_3_UPDATE_MAP_PINS,
                        L.RELEASE_1_0_3_UPDATE_ONE_CLICK,
                        L.RELEASE_1_0_3_UPDATE_INVENTORY,
                        L.RELEASE_1_0_3_UPDATE_REMOVE_COORDINATES,
                    },
                },
            },
        },
        {
            version = "1.1.1-beta",
            title = L.RELEASE_1_0_2_UPDATE_TITLE,
            state = L.RELEASE_1_0_2_UPDATE_STATE,
            subtitle = L.RELEASE_1_0_2_UPDATE_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_2_UPDATE_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_2_UPDATE_QUEST_ICONS,
                        L.RELEASE_1_0_2_UPDATE_WEEKLIES,
                        L.RELEASE_1_0_2_UPDATE_PROGRESS,
                        L.RELEASE_1_0_2_UPDATE_SEASON_TWO,
                    },
                },
            },
        },
        {
            version = "1.1.0-beta",
            title = L.RELEASE_1_0_10_TITLE,
            state = L.RELEASE_1_0_10_STATE,
            subtitle = L.RELEASE_1_0_10_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_10_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_10_HARDEN_SNAPSHOTS,
                        L.RELEASE_1_0_10_SMOOTH_GATHERING,
                        L.RELEASE_1_0_10_COALESCE_PVE,
                        L.RELEASE_1_0_10_REDUCE_DISPATCH,
                        L.RELEASE_1_0_10_UPDATE_RETAIL,
                    },
                },
            },
        },
        {
            version = "1.0.9-beta",
            title = L.RELEASE_1_0_9_TITLE,
            state = L.RELEASE_1_0_9_STATE,
            subtitle = L.RELEASE_1_0_9_SUBTITLE,
            newFeatureIDs = {
                "one_click_processing",
            },
            newInterfaceIDs = {
                "warband_specialization_art",
                "housing_tab",
                "utility_resource_settings",
            },
            sections = {
                {
                    title = L.RELEASE_1_0_9_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_9_IMPROVE_VISUALS,
                        L.RELEASE_1_0_9_ADD_WARBAND_SPEC_BACKGROUNDS,
                        L.RELEASE_1_0_9_REWORK_RESOURCES,
                        L.RELEASE_1_0_9_REWORK_HOUSING,
                        L.RELEASE_1_0_9_REWORK_PROCESSING,
                        L.RELEASE_1_0_9_REWORK_PVE,
                    },
                },
            },
        },
        {
            version = "1.0.8-beta",
            title = L.RELEASE_1_0_8_TITLE,
            state = L.RELEASE_1_0_8_STATE,
            subtitle = L.RELEASE_1_0_8_SUBTITLE,
            newFeatureIDs = {
                "mailbox",
            },
            newInterfaceIDs = {
                "arsenal_mail",
                "warband_manual_order",
            },
            sections = {
                {
                    title = L.RELEASE_1_0_8_SECTION_NEW,
                    items = {
                        L.RELEASE_1_0_8_ADD_MAIL_FEATURE,
                        L.RELEASE_1_0_8_ADD_ARSENAL_MAIL,
                        L.RELEASE_1_0_8_ADD_MANUAL_ORDER,
                    },
                },
                {
                    title = L.RELEASE_1_0_8_SECTION_IMPROVED,
                    items = {
                        L.RELEASE_1_0_8_IMPROVE_ESCAPE,
                        L.RELEASE_1_0_8_IMPROVE_SOUNDS,
                        L.RELEASE_1_0_8_IMPROVE_TEXTS,
                    },
                },
            },
        },
        {
            version = "1.0.7-beta",
            title = L.RELEASE_1_0_7_TITLE,
            state = L.RELEASE_1_0_7_STATE,
            subtitle = L.RELEASE_1_0_7_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_7_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_7_ADD_VAULT_OVERVIEW,
                        L.RELEASE_1_0_7_IMPROVE_BUTTONS,
                    },
                },
            },
        },
        {
            version = "1.0.6-beta",
            title = L.RELEASE_1_0_6_TITLE,
            state = L.RELEASE_1_0_6_STATE,
            subtitle = L.RELEASE_1_0_6_SUBTITLE,
            newFeatureIDs = {
                "map_coordinates",
                "item_finder",
            },
            sections = {
                {
                    title = L.RELEASE_1_0_6_SECTION_NEW,
                    items = {
                        L.RELEASE_1_0_6_ADD_MAP_COORDINATES,
                        L.RELEASE_1_0_6_ADD_ITEM_FINDER,
                    },
                },
                {
                    title = L.RELEASE_1_0_6_SECTION_IMPROVED,
                    items = {
                        L.RELEASE_1_0_6_IMPROVE_UI,
                        L.RELEASE_1_0_6_IMPROVE_MERCHANT,
                    },
                },
            },
        },
        {
            version = "1.0.5-beta",
            title = L.RELEASE_1_0_5_TITLE,
            state = L.RELEASE_1_0_5_STATE,
            subtitle = L.RELEASE_1_0_5_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_5_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_5_IMPROVE_VISUALS,
                        L.RELEASE_1_0_5_FIX_GATHERING_CPU,
                        L.RELEASE_1_0_5_ADD_VOID_DIFFICULTY,
                    },
                },
            },
        },
        {
            version = "1.0.4-beta",
            title = L.RELEASE_1_0_4_TITLE,
            state = L.RELEASE_1_0_4_STATE,
            subtitle = L.RELEASE_1_0_4_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_4_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_4_FIX_GATHERING,
                        L.RELEASE_1_0_4_IMPROVE_VISUALS,
                        L.RELEASE_1_0_4_ADJUST_MERCHANT,
                        L.RELEASE_1_0_4_ADD_CURRENCY_TOOLTIPS,
                        L.RELEASE_1_0_4_EXPAND_BARS,
                        L.RELEASE_1_0_4_EXPAND_LOOT,
                        L.RELEASE_1_0_4_ADD_VAULT_CLAIM,
                        L.RELEASE_1_0_4_FIX_AETHAS,
                        L.RELEASE_1_0_4_ADD_VOID_INVASION,
                        L.RELEASE_1_0_4_HIDE_OMNIUM,
                    },
                },
            },
        },
        {
            version = "1.0.3-beta",
            title = L.RELEASE_1_0_3_TITLE,
            state = L.RELEASE_1_0_3_STATE,
            subtitle = L.RELEASE_1_0_3_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_3_SECTION_CHANGES,
                    items = {
                        L.RELEASE_1_0_3_FIX_CPU,
                        L.RELEASE_1_0_3_IMPROVE_GATHERING,
                        L.RELEASE_1_0_3_REWORK_MYTHIC_PLUS,
                        L.RELEASE_1_0_3_ADD_KEYBIND,
                    },
                },
            },
        },
        {
            version = "1.0.2-beta.1",
            title = L.RELEASE_1_0_2_TITLE,
            state = L.RELEASE_1_0_2_STATE,
            subtitle = L.RELEASE_1_0_2_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_2_SECTION_FIXED,
                    items = {
                        L.RELEASE_1_0_2_FIX_CREST_BORDERS,
                        L.RELEASE_1_0_2_FIX_MAIN_MARKER,
                        L.RELEASE_1_0_2_FIX_JOURNAL_LOCALIZATION,
                    },
                },
            },
        },
        {
            version = "1.0.1-beta.1",
            title = L.RELEASE_1_0_1_TITLE,
            state = L.RELEASE_1_0_1_STATE,
            subtitle = L.RELEASE_1_0_1_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_1_0_1_SECTION_FIXED,
                    items = {
                        L.RELEASE_1_0_1_FIX_PREY,
                        L.RELEASE_1_0_1_FIX_GATHERING_LANGUAGE,
                        L.RELEASE_1_0_1_FIX_WORLD_MAP,
                        L.RELEASE_1_0_1_FIX_COMPENDIUM_ICON,
                        L.RELEASE_1_0_1_FIX_CRESTS,
                    },
                },
                {
                    title = L.RELEASE_1_0_1_SECTION_IMPROVED,
                    items = {
                        L.RELEASE_1_0_1_IMPROVE_WARBAND_LAYOUT,
                        L.RELEASE_1_0_1_IMPROVE_DYNAMIC_RESOURCES,
                        L.RELEASE_1_0_1_FIX_HISTORY,
                        L.RELEASE_1_0_1_IMPROVE_SHOPPING_TITLE,
                    },
                },
            },
        },
        {
            version = "1.0.0-beta.1",
            title = L.RELEASE_1_0_TITLE,
            state = L.RELEASE_1_0_STATE,
            subtitle = L.RELEASE_1_0_SUBTITLE,
            sections = {
                {
                    title = L.RELEASE_SECTION_NEW,
                    items = {
                        L.RELEASE_1_0_NEW_WARBAND,
                        L.RELEASE_1_0_NEW_ARSENAL,
                        L.RELEASE_1_0_NEW_CONTENT,
                    },
                },
                {
                    title = L.RELEASE_SECTION_FEATURES,
                    items = {
                        L.RELEASE_1_0_FEATURES_WORLD,
                        L.RELEASE_1_0_FEATURES_ITEMS,
                        L.RELEASE_1_0_FEATURES_BARS,
                        L.RELEASE_1_0_FEATURES_MERCHANT,
                    },
                },
                {
                    title = L.RELEASE_SECTION_REWORKED,
                    items = {
                        L.RELEASE_1_0_REWORKED_VAULT,
                        L.RELEASE_1_0_REWORKED_RESOURCES,
                        L.RELEASE_1_0_REWORKED_UI,
                        L.RELEASE_1_0_REWORKED_NAVIGATION,
                    },
                },
                {
                    title = L.RELEASE_SECTION_PERFORMANCE,
                    items = {
                        L.RELEASE_1_0_PERFORMANCE_SNAPSHOTS,
                        L.RELEASE_1_0_PERFORMANCE_LAZY,
                        L.RELEASE_1_0_PERFORMANCE_EVENTS,
                        L.RELEASE_1_0_PERFORMANCE_SCROLL,
                    },
                },
                {
                    title = L.RELEASE_SECTION_NOTES,
                    items = {
                        L.RELEASE_1_0_NOTE_CHRONICLE,
                        L.RELEASE_1_0_NOTE_LANGUAGES,
                        L.RELEASE_1_0_NOTE_DATABASE,
                        L.RELEASE_1_0_NOTE_ACTIONBARS,
                        L.RELEASE_1_0_NOTE_BETA,
                    },
                },
            },
        },
    }

    while #releases > MAX_RELEASE_HISTORY do
        table.remove(releases)
    end

    return {
        latestVersion = releases[1].version,
        current = releases[1],
        releases = releases,
        maxHistory = MAX_RELEASE_HISTORY,
    }
end

function Addon:RefreshReleaseNotesLocalization()
    self.ReleaseNotes = buildReleaseNotes()
    return self.ReleaseNotes
end

Addon:RefreshReleaseNotesLocalization()
