local _, Addon = ...

local Registry = Addon.FeatureRegistry

local function localized(key)
    return function()
        return Addon.L[key] or key
    end
end

local function booleanSetting(key, labelKey, defaultValue)
    return {
        key = key,
        type = "boolean",
        label = localized(labelKey),
        default = defaultValue == true,
    }
end

local function selectSetting(key, labelKey, defaultValue, options)
    return {
        key = key,
        type = "select",
        label = localized(labelKey),
        default = defaultValue,
        options = options,
    }
end

local function runtimeSelectSetting(key, labelKey, defaultValue, options)
    local setting = selectSetting(key, labelKey, defaultValue, options)
    setting.runtime = true
    return setting
end

local function runtimeBooleanSetting(key, labelKey, defaultValue)
    local setting = booleanSetting(key, labelKey, defaultValue)
    setting.runtime = true
    return setting
end

local function rangeSetting(key, labelKey, defaultValue, minimum, maximum, step, suffix)
    return {
        key = key,
        type = "range",
        label = localized(labelKey),
        default = defaultValue,
        minimum = minimum,
        maximum = maximum,
        step = step,
        suffix = suffix,
    }
end

local function runtimeRangeSetting(key, labelKey, defaultValue, minimum, maximum, step, suffix)
    local setting = rangeSetting(key, labelKey, defaultValue, minimum, maximum, step, suffix)
    setting.runtime = true
    return setting
end

local function actionSetting(key, labelKey, actionLabelKey)
    return {
        key = key,
        type = "action",
        label = localized(labelKey),
        actionLabel = localized(actionLabelKey),
    }
end

local function option(value, labelKey)
    return {
        value = value,
        label = localized(labelKey),
    }
end

local function treasurePinsDescription()
    local description = Addon.L.FEATURE_TREASURE_PINS_DESC or "Midnight treasures"
    local runtime = Addon.MidnightTreasureMapPins
    if runtime and type(runtime.GetProgressSummary) == "function" then
        local ok, summary = pcall(runtime.GetProgressSummary, runtime)
        if ok and type(summary) == "string" and summary ~= "" then
            return description .. "\n" .. summary
        end
    end
    return description
end

for _, category in ipairs({
    {
        id = "progress",
        label = localized("FEATURE_CATEGORY_PROGRESS"),
        description = localized("FEATURE_CATEGORY_PROGRESS_DESC"),
    },
    {
        id = "character",
        label = localized("FEATURE_CATEGORY_CHARACTER"),
        description = localized("FEATURE_CATEGORY_CHARACTER_DESC"),
    },
    {
        id = "inventory",
        label = localized("FEATURE_CATEGORY_INVENTORY"),
        description = localized("FEATURE_CATEGORY_INVENTORY_DESC"),
    },
    {
        id = "crafting",
        label = localized("FEATURE_CATEGORY_CRAFTING"),
        description = localized("FEATURE_CATEGORY_CRAFTING_DESC"),
    },
    {
        id = "quick_tools",
        label = localized("FEATURE_CATEGORY_QUICK_TOOLS"),
        description = localized("FEATURE_CATEGORY_QUICK_TOOLS_DESC"),
    },
    {
        id = "world_map",
        label = localized("FEATURE_CATEGORY_WORLD_MAP"),
        description = localized("FEATURE_CATEGORY_WORLD_MAP_DESC"),
    },
    {
        id = "blizzard",
        label = localized("FEATURE_CATEGORY_BLIZZARD"),
        description = localized("FEATURE_CATEGORY_BLIZZARD_DESC"),
    },
    {
        id = "action_bars",
        label = localized("FEATURE_CATEGORY_ACTION_BARS"),
        description = localized("FEATURE_CATEGORY_ACTION_BARS_DESC"),
    },
}) do
    Registry:RegisterCategory(category)
end

local definitions = {
    {
        id = "prey_bar",
        category = "progress",
        title = localized("FEATURE_PREY_BAR"),
        description = localized("FEATURE_PREY_BAR_DESC"),
        details = localized("FEATURE_PREY_BAR_DETAILS"),
        status = "available",
        settings = {
            selectSetting("widget_visibility", "FEATURE_SETTING_BLIZZARD_WIDGET", "hidden", {
                option("hidden", "FEATURE_VALUE_HIDDEN"),
                option("shown", "FEATURE_VALUE_SHOWN"),
            }),
            selectSetting("frame_style", "FEATURE_SETTING_FRAME_STYLE", "framed", {
                option("framed", "FEATURE_VALUE_FRAMED"),
                option("clean", "FEATURE_VALUE_CLEAN"),
                option("dark_red", "FEATURE_VALUE_DARK_RED"),
            }),
            selectSetting("bar_width", "FEATURE_SETTING_PREY_WIDTH", "normal", {
                option("compact", "FEATURE_VALUE_PREY_WIDTH_COMPACT"),
                option("normal", "FEATURE_VALUE_PREY_WIDTH_NORMAL"),
                option("wide", "FEATURE_VALUE_PREY_WIDTH_WIDE"),
            }),
            booleanSetting("show_title", "FEATURE_SETTING_PREY_SHOW_TITLE", true),
            runtimeRangeSetting(
                "scale_percent",
                "FEATURE_SETTING_PREY_SCALE",
                100,
                70,
                145,
                5,
                "%"
            ),
            booleanSetting("locked", "FEATURE_SETTING_LOCK_BAR", false),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_PREVIEW"),
            actionSetting("reset_layout", "FEATURE_SETTING_POSITION_SIZE", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "character_gear",
        category = "character",
        title = localized("FEATURE_CHARACTER_GEAR"),
        description = localized("FEATURE_CHARACTER_GEAR_DESC"),
        details = localized("FEATURE_CHARACTER_GEAR_DETAILS"),
        status = "available",
        settings = {
            booleanSetting("item_level", "FEATURE_SETTING_ITEM_LEVEL", true),
            selectSetting("item_level_style", "FEATURE_SETTING_ITEM_LEVEL_STYLE", "white", {
                option("white", "FEATURE_VALUE_WHITE"),
                option("quality", "FEATURE_VALUE_QUALITY_COLOR"),
            }),
            booleanSetting("enchants", "FEATURE_SETTING_ENCHANTS", true),
            booleanSetting("missing_enchants_only", "FEATURE_SETTING_ONLY_MISSING_ENCHANTS", false),
            booleanSetting("sockets", "FEATURE_SETTING_SOCKETS", true),
            booleanSetting("gems", "FEATURE_SETTING_GEMS", true),
        },
    },
    {
        id = "stat_focus",
        category = "character",
        title = localized("FEATURE_STAT_FOCUS"),
        description = localized("FEATURE_STAT_FOCUS_DESC"),
        details = localized("FEATURE_STAT_FOCUS_DETAILS"),
        status = "available",
        settings = {
            runtimeSelectSetting("tooltip_text_style", "FEATURE_SETTING_STAT_TOOLTIP_STYLE", "full", {
                option("clean", "FEATURE_VALUE_STAT_TOOLTIP_CLEAN"),
                option("full", "FEATURE_VALUE_STAT_TOOLTIP_FULL"),
            }),
            runtimeBooleanSetting("stat_colors", "FEATURE_SETTING_STAT_COLORS", false),
            runtimeBooleanSetting("stat_dots", "FEATURE_SETTING_STAT_DOTS", false),
            runtimeSelectSetting("content_profile", "FEATURE_SETTING_STAT_CONTENT_PROFILE", "solo", {
                option("solo", "FEATURE_VALUE_STAT_SOLO"),
                option("delve", "FEATURE_VALUE_STAT_DELVE"),
                option("raid", "FEATURE_VALUE_STAT_RAID"),
                option("mythicplus", "FEATURE_VALUE_STAT_MYTHIC_PLUS"),
            }),
            runtimeSelectSetting("build_profile", "FEATURE_SETTING_STAT_BUILD_PROFILE", "standard", {
                option("standard", "FEATURE_VALUE_STAT_STANDARD_BUILD"),
            }),
            runtimeSelectSetting("priority_mode", "FEATURE_SETTING_PRIORITY_MODE", "preset", {
                option("preset", "FEATURE_VALUE_PRESET"),
                option("custom", "FEATURE_VALUE_CUSTOM"),
            }),
        },
    },
    {
        id = "inventory_tracker",
        category = "inventory",
        title = localized("FEATURE_INVENTORY_TRACKER"),
        description = localized("FEATURE_INVENTORY_TRACKER_DESC"),
        details = localized("FEATURE_INVENTORY_TRACKER_DETAILS"),
        status = "available",
        settings = {
            selectSetting("tooltip_mode", "FEATURE_SETTING_TOOLTIP_MODE", "detail", {
                option("detail", "FEATURE_VALUE_DETAIL"),
                option("overview", "FEATURE_VALUE_OVERVIEW"),
                option("total", "FEATURE_VALUE_TOTAL"),
            }),
            booleanSetting("warband_bank", "FEATURE_SETTING_WARBAND_BANK", true),
            booleanSetting("equipped_items", "FEATURE_SETTING_EQUIPPED_ITEMS", true),
        },
    },
    {
        id = "mailbox",
        category = "inventory",
        title = localized("FEATURE_MAILBOX"),
        description = localized("FEATURE_MAILBOX_DESC"),
        details = localized("FEATURE_MAILBOX_DETAILS"),
        status = "available",
        settings = {
            rangeSetting("keep_free_slots", "FEATURE_SETTING_MAILBOX_FREE_SLOTS", 1, 0, 10, 1),
            rangeSetting("expiry_warning_days", "FEATURE_SETTING_MAILBOX_EXPIRY_DAYS", 3, 1, 14, 1),
            booleanSetting("include_inventory", "FEATURE_SETTING_MAILBOX_INVENTORY", true),
            booleanSetting("login_alerts", "FEATURE_SETTING_MAILBOX_ALERTS", true),
            booleanSetting("show_summary", "FEATURE_SETTING_MAILBOX_SUMMARY", true),
            booleanSetting("remember_recipients", "FEATURE_SETTING_MAILBOX_RECIPIENTS", true),
            booleanSetting("protect_equipment", "FEATURE_SETTING_MAILBOX_PROTECT_GEAR", true),
            selectSetting("send_pace", "FEATURE_SETTING_MAILBOX_SEND_PACE", "normal", {
                option("safe", "FEATURE_VALUE_MAILBOX_SEND_SAFE"),
                option("normal", "FEATURE_VALUE_MAILBOX_SEND_NORMAL"),
                option("fast", "FEATURE_VALUE_MAILBOX_SEND_FAST"),
            }),
        },
    },
    {
        id = "item_finder",
        category = "inventory",
        title = localized("FEATURE_ITEM_FINDER"),
        description = localized("FEATURE_ITEM_FINDER_DESC"),
        details = localized("FEATURE_ITEM_FINDER_DETAILS"),
        status = "available",
        settings = {
            actionSetting("open_finder", "FEATURE_SETTING_ITEM_FINDER_WINDOW", "FEATURE_ACTION_OPEN"),
            booleanSetting("bag_button", "FEATURE_SETTING_ITEM_FINDER_BAG_BUTTON", true),
            booleanSetting("wishlist_button", "FEATURE_SETTING_ITEM_FINDER_WISHLIST_BUTTON", true),
            booleanSetting("warband_bank", "FEATURE_SETTING_WARBAND_BANK", true),
            booleanSetting("equipped_items", "FEATURE_SETTING_EQUIPPED_ITEMS", true),
        },
    },
    {
        id = "item_id_tooltip",
        category = "inventory",
        title = localized("FEATURE_ITEM_ID"),
        description = localized("FEATURE_ITEM_ID_DESC"),
        details = localized("FEATURE_ITEM_ID_DETAILS"),
        status = "available",
    },
    {
        id = "auto_sell_junk",
        category = "inventory",
        title = localized("FEATURE_AUTO_SELL_JUNK"),
        description = localized("FEATURE_AUTO_SELL_JUNK_DESC"),
        details = localized("FEATURE_AUTO_SELL_JUNK_DETAILS"),
        status = "available",
        settings = {
            booleanSetting("pause_with_shift", "FEATURE_SETTING_AUTO_SELL_SHIFT_PAUSE", true),
            booleanSetting("show_summary", "FEATURE_SETTING_AUTO_SELL_SUMMARY", true),
        },
    },
    {
        id = "bag_item_level",
        category = "inventory",
        title = localized("FEATURE_BAG_ITEM_LEVEL"),
        description = localized("FEATURE_BAG_ITEM_LEVEL_DESC"),
        details = localized("FEATURE_BAG_ITEM_LEVEL_DETAILS"),
        status = "available",
        settings = {
            selectSetting("text_style", "FEATURE_SETTING_ITEM_LEVEL_STYLE", "white", {
                option("white", "FEATURE_VALUE_WHITE"),
                option("quality", "FEATURE_VALUE_QUALITY_COLOR"),
            }),
        },
    },
    {
        id = "one_click_processing",
        category = "inventory",
        title = localized("FEATURE_ONE_CLICK"),
        description = localized("FEATURE_ONE_CLICK_DESC"),
        details = localized("FEATURE_ONE_CLICK_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            selectSetting("modifier", "FEATURE_SETTING_MODIFIER", "alt", {
                option("alt", "FEATURE_VALUE_ALT"),
                option("alt_shift", "FEATURE_VALUE_ALT_SHIFT"),
                option("alt_ctrl", "FEATURE_VALUE_ALT_CTRL"),
            }),
            runtimeBooleanSetting(
                "animated_glow",
                "FEATURE_SETTING_ONE_CLICK_ANIMATION",
                true
            ),
            runtimeBooleanSetting(
                "consumable_keys",
                "FEATURE_SETTING_ONE_CLICK_KEYS",
                false
            ),
            booleanSetting(
                "disenchant_rare_epic",
                "FEATURE_SETTING_ONE_CLICK_RARE_EPIC",
                false
            ),
        },
    },
    {
        id = "shopping_list",
        category = "crafting",
        title = localized("FEATURE_SHOPPING_LIST"),
        description = localized("FEATURE_SHOPPING_LIST_DESC"),
        details = localized("FEATURE_SHOPPING_LIST_DETAILS"),
        status = "available",
        settings = {
            selectSetting("launcher_mode", "FEATURE_SETTING_SHOPPING_LAUNCHER", "minimap", {
                option("minimap", "FEATURE_OPTION_SHOPPING_LAUNCHER_MINIMAP"),
                option("floating", "FEATURE_OPTION_SHOPPING_LAUNCHER_FLOATING"),
                option("off", "FEATURE_OPTION_SHOPPING_LAUNCHER_OFF"),
            }),
            booleanSetting("recipe_button", "FEATURE_SETTING_RECIPE_BUTTON", true),
            booleanSetting("auction_button", "FEATURE_SETTING_AUCTION_BUTTON", true),
        },
    },
    {
        id = "spec_switcher",
        category = "quick_tools",
        title = localized("FEATURE_SPEC_SWITCHER"),
        description = localized("FEATURE_SPEC_SWITCHER_DESC"),
        details = localized("FEATURE_SPEC_SWITCHER_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            selectSetting("orientation", "FEATURE_SETTING_ORIENTATION", "horizontal", {
                option("horizontal", "FEATURE_VALUE_HORIZONTAL"),
                option("vertical", "FEATURE_VALUE_VERTICAL"),
            }),
            selectSetting("frame_style", "FEATURE_SETTING_FRAME_STYLE", "warcraft", {
                option("warcraft", "FEATURE_VALUE_WARCRAFT"),
                option("compact", "FEATURE_VALUE_COMPACT"),
                option("clean", "FEATURE_VALUE_CLEAN"),
            }),
            selectSetting("icon_shape", "FEATURE_SETTING_ICON_SHAPE", "round", {
                option("round", "FEATURE_VALUE_ROUND"),
                option("square", "FEATURE_VALUE_WOW_SQUARE"),
            }),
            runtimeRangeSetting("scale_percent", "FEATURE_SETTING_SCALE_PERCENT", 100, 70, 145, 5, "%"),
            runtimeRangeSetting("bar_opacity_percent", "FEATURE_SETTING_BAR_OPACITY", 100, 30, 100, 5, "%"),
            runtimeBooleanSetting("outer_border", "FEATURE_SETTING_OUTER_BORDER", true),
            runtimeBooleanSetting("icon_border", "FEATURE_SETTING_ICON_BORDER", true),
            selectSetting("ring_color", "FEATURE_SETTING_ACTIVE_RING_COLOR", "class", {
                option("class", "FEATURE_VALUE_CLASS_COLOR"),
                option("gold", "FEATURE_VALUE_GOLD"),
                option("cyan", "FEATURE_VALUE_CYAN"),
                option("green", "FEATURE_VALUE_GREEN"),
                option("red", "FEATURE_VALUE_RED"),
                option("purple", "FEATURE_VALUE_PURPLE"),
            }),
            selectSetting("loadout_label", "FEATURE_SETTING_LOADOUT_LABEL", "tooltip", {
                option("tooltip", "FEATURE_VALUE_TOOLTIP_ONLY"),
                option("active", "FEATURE_VALUE_ACTIVE_TEXT"),
                option("hidden", "FEATURE_VALUE_HIDDEN"),
            }),
            selectSetting("active_click", "FEATURE_SETTING_ACTIVE_CLICK", "cycle", {
                option("cycle", "FEATURE_VALUE_CYCLE_LOADOUTS"),
                option("menu", "FEATURE_VALUE_OPEN_MENU"),
            }),
            booleanSetting("locked", "FEATURE_SETTING_LOCK_BAR", false),
            actionSetting("reset_layout", "FEATURE_SETTING_POSITION_SIZE", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "travel_bar",
        category = "quick_tools",
        title = localized("FEATURE_TRAVEL_BAR"),
        description = localized("FEATURE_TRAVEL_BAR_DESC"),
        details = localized("FEATURE_TRAVEL_BAR_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            selectSetting("orientation", "FEATURE_SETTING_ORIENTATION", "horizontal", {
                option("horizontal", "FEATURE_VALUE_HORIZONTAL"),
                option("vertical", "FEATURE_VALUE_VERTICAL"),
                option("two_rows", "FEATURE_VALUE_TWO_ROWS"),
                option("honeycomb", "FEATURE_VALUE_HONEYCOMB"),
            }),
            selectSetting("frame_style", "FEATURE_SETTING_FRAME_STYLE", "warcraft", {
                option("warcraft", "FEATURE_VALUE_WARCRAFT"),
                option("compact", "FEATURE_VALUE_COMPACT"),
                option("clean", "FEATURE_VALUE_CLEAN"),
            }),
            selectSetting("icon_shape", "FEATURE_SETTING_ICON_SHAPE", "round", {
                option("round", "FEATURE_VALUE_ROUND"),
                option("square", "FEATURE_VALUE_WOW_SQUARE"),
            }),
            runtimeRangeSetting("scale_percent", "FEATURE_SETTING_SCALE_PERCENT", 100, 70, 145, 5, "%"),
            runtimeRangeSetting("bar_opacity_percent", "FEATURE_SETTING_BAR_OPACITY", 100, 30, 100, 5, "%"),
            runtimeBooleanSetting("outer_border", "FEATURE_SETTING_OUTER_BORDER", true),
            runtimeBooleanSetting("icon_border", "FEATURE_SETTING_ICON_BORDER", true),
            selectSetting("ring_color", "FEATURE_SETTING_RING_COLOR", "class", {
                option("class", "FEATURE_VALUE_CLASS_COLOR"),
                option("gold", "FEATURE_VALUE_GOLD"),
                option("cyan", "FEATURE_VALUE_CYAN"),
                option("green", "FEATURE_VALUE_GREEN"),
                option("red", "FEATURE_VALUE_RED"),
                option("purple", "FEATURE_VALUE_PURPLE"),
            }),
            booleanSetting("locked", "FEATURE_SETTING_LOCK_BAR", false),
            actionSetting("manage_destinations", "FEATURE_SETTING_DESTINATIONS", "FEATURE_ACTION_MANAGE"),
            actionSetting("reset_layout", "FEATURE_SETTING_POSITION_SIZE", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "auto_accept_quests",
        category = "quick_tools",
        title = localized("FEATURE_AUTO_ACCEPT_QUESTS"),
        description = localized("FEATURE_AUTO_ACCEPT_QUESTS_DESC"),
        details = localized("FEATURE_AUTO_ACCEPT_QUESTS_DETAILS"),
        status = "available",
        settings = {
            booleanSetting("trivial_quests", "FEATURE_SETTING_TRIVIAL_QUESTS", false),
            booleanSetting("safe_turn_in", "FEATURE_SETTING_SAFE_TURN_IN", false),
        },
    },
    {
        id = "prey_hunt_icons",
        category = "world_map",
        title = localized("FEATURE_PREY_ICONS"),
        description = localized("FEATURE_PREY_ICONS_DESC"),
        details = localized("FEATURE_PREY_ICONS_DETAILS"),
        status = "available",
        settings = {
            runtimeRangeSetting(
                "icon_scale_percent",
                "FEATURE_SETTING_PREY_ICON_SCALE",
                100,
                80,
                120,
                5,
                "%"
            ),
            runtimeBooleanSetting(
                "achievement_marker",
                "FEATURE_SETTING_PREY_ACHIEVEMENT_MARKER",
                true
            ),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_OPEN"),
        },
    },
    {
        id = "midnight_rare_map_pins",
        category = "world_map",
        title = localized("FEATURE_RARE_PINS"),
        description = localized("FEATURE_RARE_PINS_DESC"),
        details = localized("FEATURE_RARE_PINS_DETAILS"),
        status = "available",
        settings = {
            runtimeRangeSetting(
                "icon_scale_percent",
                "FEATURE_SETTING_RARE_PIN_SCALE",
                100,
                80,
                130,
                5,
                "%"
            ),
            runtimeSelectSetting("completed_mode", "FEATURE_SETTING_RARE_COMPLETED", "hide", {
                option("hide", "FEATURE_VALUE_HIDE_COMPLETED"),
                option("faded", "FEATURE_VALUE_FADE_COMPLETED"),
                option("shown", "FEATURE_VALUE_SHOW_COMPLETED"),
            }),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_OPEN"),
        },
    },
    {
        id = "midnight_treasure_map_pins",
        category = "world_map",
        title = localized("FEATURE_TREASURE_PINS"),
        description = treasurePinsDescription,
        details = localized("FEATURE_TREASURE_PINS_DETAILS"),
        status = "available",
        settings = {
            runtimeRangeSetting(
                "icon_scale_percent",
                "FEATURE_SETTING_TREASURE_PIN_SCALE",
                100,
                80,
                130,
                5,
                "%"
            ),
            runtimeSelectSetting("completed_mode", "FEATURE_SETTING_TREASURE_COMPLETED", "hide", {
                option("hide", "FEATURE_VALUE_HIDE_COMPLETED"),
                option("faded", "FEATURE_VALUE_FADE_COMPLETED"),
                option("shown", "FEATURE_VALUE_SHOW_COMPLETED"),
            }),
            runtimeBooleanSetting("show_treasures", "FEATURE_SETTING_TREASURE_NORMAL", true),
            runtimeBooleanSetting("show_professions", "FEATURE_SETTING_TREASURE_PROFESSIONS", true),
            runtimeBooleanSetting("show_rituals", "FEATURE_SETTING_TREASURE_RITUALS", true),
            runtimeBooleanSetting("show_delves", "FEATURE_SETTING_TREASURE_DELVES", true),
            runtimeBooleanSetting(
                "only_current_professions",
                "FEATURE_SETTING_TREASURE_ONLY_CURRENT_PROFESSIONS",
                true
            ),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_OPEN"),
        },
    },
    {
        id = "gathering_nodes",
        category = "world_map",
        status = "available",
        title = localized("FEATURE_GATHERING_NODES"),
        description = localized("FEATURE_GATHERING_NODES_DESC"),
        details = localized("FEATURE_GATHERING_NODES_DETAILS"),
        settings = {
            runtimeBooleanSetting("world_map", "FEATURE_SETTING_GATHERING_WORLD_MAP", true),
            runtimeBooleanSetting("minimap", "FEATURE_SETTING_GATHERING_MINIMAP", true),
            runtimeRangeSetting(
                "world_scale_percent",
                "FEATURE_SETTING_GATHERING_WORLD_SCALE",
                100,
                70,
                150,
                5,
                "%"
            ),
            runtimeRangeSetting(
                "minimap_scale_percent",
                "FEATURE_SETTING_GATHERING_MINIMAP_SCALE",
                100,
                70,
                150,
                5,
                "%"
            ),
            runtimeBooleanSetting("show_mining", "FEATURE_SETTING_GATHERING_MINING", true),
            runtimeBooleanSetting("show_herbalism", "FEATURE_SETTING_GATHERING_HERBALISM", true),
            runtimeBooleanSetting("show_leather", "FEATURE_SETTING_GATHERING_LEATHER", true),
            runtimeBooleanSetting("show_wood", "FEATURE_SETTING_GATHERING_WOOD", true),
            runtimeBooleanSetting("show_fish", "FEATURE_SETTING_GATHERING_FISH", true),
            runtimeBooleanSetting("show_cooking", "FEATURE_SETTING_GATHERING_COOKING", true),
            runtimeBooleanSetting(
                "only_current_professions",
                "FEATURE_SETTING_GATHERING_CURRENT_PROFESSIONS",
                false
            ),
            runtimeSelectSetting(
                "launcher_mode",
                "FEATURE_SETTING_GATHERING_LAUNCHER",
                "minimap",
                {
                    option("minimap", "FEATURE_OPTION_GATHERING_LAUNCHER_MINIMAP"),
                    option("floating", "FEATURE_OPTION_GATHERING_LAUNCHER_FLOATING"),
                    option("off", "FEATURE_OPTION_GATHERING_LAUNCHER_OFF"),
                }
            ),
            runtimeBooleanSetting("locked", "FEATURE_SETTING_GATHERING_LOCK_BUTTON", false),
            actionSetting("manage", "FEATURE_SETTING_GATHERING_MANAGE", "FEATURE_ACTION_MANAGE"),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_PREVIEW"),
            actionSetting("reset_layout", "FEATURE_SETTING_POSITION_SIZE", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "profession_knowledge_badges",
        category = "blizzard",
        title = localized("FEATURE_KNOWLEDGE_BADGES"),
        description = localized("FEATURE_KNOWLEDGE_BADGES_DESC"),
        details = localized("FEATURE_KNOWLEDGE_BADGES_DETAILS"),
        status = "available",
        settings = {
            runtimeRangeSetting(
                "badge_scale_percent",
                "FEATURE_SETTING_KNOWLEDGE_BADGE_SCALE",
                100,
                80,
                130,
                5,
                "%"
            ),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_PREVIEW"),
        },
    },
    {
        id = "quiet_loot",
        category = "blizzard",
        title = localized("FEATURE_QUIET_LOOT"),
        description = localized("FEATURE_QUIET_LOOT_DESC"),
        details = localized("FEATURE_QUIET_LOOT_DETAILS"),
        status = "available",
        settings = {
            runtimeSelectSetting("loot_window_mode", "FEATURE_SETTING_LOOT_WINDOW_MODE", "compact", {
                option("compact", "FEATURE_VALUE_VAULTLOOM"),
                option("blizzard", "FEATURE_VALUE_BLIZZARD"),
            }),
            runtimeSelectSetting("loot_alert_mode", "FEATURE_SETTING_LOOT_ALERT_MODE", "compact", {
                option("compact", "FEATURE_VALUE_VAULTLOOM"),
                option("blizzard", "FEATURE_VALUE_BLIZZARD"),
                option("hidden", "FEATURE_VALUE_OFF"),
            }),
            runtimeSelectSetting("boss_alert_mode", "FEATURE_SETTING_BOSS_ALERT_MODE", "compact", {
                option("compact", "FEATURE_VALUE_VAULTLOOM"),
                option("blizzard", "FEATURE_VALUE_BLIZZARD"),
                option("hidden", "FEATURE_VALUE_OFF"),
            }),
            runtimeSelectSetting("visual_style", "FEATURE_SETTING_QUIET_STYLE", "standard", {
                option("clean", "FEATURE_VALUE_LOOT_STYLE_CLEAN"),
                option("standard", "FEATURE_VALUE_LOOT_STYLE_STANDARD"),
                option("round", "FEATURE_VALUE_LOOT_STYLE_ROUND"),
            }),
            runtimeRangeSetting(
                "background_opacity_percent",
                "FEATURE_SETTING_LOOT_BACKGROUND_OPACITY",
                100,
                0,
                100,
                5,
                "%"
            ),
            runtimeBooleanSetting("quality_border", "FEATURE_SETTING_LOOT_QUALITY_BORDER", true),
            runtimeSelectSetting("animation_style", "FEATURE_SETTING_LOOT_ANIMATION", "fade", {
                option("none", "FEATURE_VALUE_ANIMATION_NONE"),
                option("fade", "FEATURE_VALUE_ANIMATION_FADE"),
                option("slide_right", "FEATURE_VALUE_ANIMATION_SLIDE_RIGHT"),
                option("slide_up", "FEATURE_VALUE_ANIMATION_SLIDE_UP"),
                option("pop", "FEATURE_VALUE_ANIMATION_POP"),
            }),
            runtimeSelectSetting("growth_direction", "FEATURE_SETTING_QUIET_GROWTH", "down", {
                option("down", "FEATURE_VALUE_DOWN"),
                option("up", "FEATURE_VALUE_UP"),
            }),
            runtimeRangeSetting("loot_scale_percent", "FEATURE_SETTING_LOOT_SCALE", 100, 70, 140, 5, "%"),
            runtimeRangeSetting("toast_scale_percent", "FEATURE_SETTING_TOAST_SCALE", 100, 70, 140, 5, "%"),
            runtimeRangeSetting("toast_duration", "FEATURE_SETTING_TOAST_DURATION", 5, 2, 10, 1, " s"),
            actionSetting("preview", "FEATURE_SETTING_PREVIEW", "FEATURE_ACTION_PREVIEW"),
            actionSetting("reset_layout", "FEATURE_SETTING_POSITION_SIZE", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "merchant_filters",
        category = "blizzard",
        title = localized("FEATURE_MERCHANT_FILTERS"),
        description = localized("FEATURE_MERCHANT_FILTERS_DESC"),
        details = localized("FEATURE_MERCHANT_FILTERS_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            runtimeSelectSetting("display_mode", "FEATURE_SETTING_MERCHANT_MODE", "replace", {
                option("replace", "FEATURE_VALUE_MERCHANT_REPLACE"),
                option("companion", "FEATURE_VALUE_MERCHANT_COMPANION"),
                option("filter_only", "FEATURE_VALUE_MERCHANT_FILTER_ONLY"),
            }),
            runtimeSelectSetting("save_scope", "FEATURE_SETTING_MERCHANT_SAVE_SCOPE", "merchant", {
                option("temporary", "FEATURE_VALUE_MERCHANT_TEMPORARY"),
                option("merchant", "FEATURE_VALUE_MERCHANT_PER_MERCHANT"),
                option("global", "FEATURE_VALUE_MERCHANT_GLOBAL"),
            }),
            runtimeRangeSetting(
                "scale_percent",
                "FEATURE_SETTING_MERCHANT_SCALE",
                100,
                75,
                135,
                5,
                "%"
            ),
            actionSetting(
                "reset_filters",
                "FEATURE_SETTING_MERCHANT_FILTERS",
                "FEATURE_ACTION_RESET"
            ),
            actionSetting(
                "reset_layout",
                "FEATURE_SETTING_POSITION_SIZE",
                "FEATURE_ACTION_RESET"
            ),
        },
    },
    {
        id = "blizzard_unit_frames",
        category = "blizzard",
        title = localized("FEATURE_BLIZZARD_UNIT_FRAMES"),
        description = localized("FEATURE_BLIZZARD_UNIT_FRAMES_DESC"),
        details = localized("FEATURE_BLIZZARD_UNIT_FRAMES_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            runtimeSelectSetting(
                "color_mode",
                "FEATURE_SETTING_UNIT_FRAME_COLORS",
                "class_reaction",
                {
                    option("class_reaction", "FEATURE_VALUE_CLASS_REACTION"),
                    option("class_only", "FEATURE_VALUE_CLASS_ONLY"),
                    option("blizzard", "FEATURE_VALUE_BLIZZARD"),
                }
            ),
            runtimeSelectSetting(
                "health_text",
                "FEATURE_SETTING_UNIT_FRAME_HEALTH_TEXT",
                "blizzard",
                {
                    option("blizzard", "FEATURE_VALUE_BLIZZARD"),
                    option("percent", "FEATURE_VALUE_PERCENT"),
                    option("value_percent", "FEATURE_VALUE_VALUE_PERCENT"),
                }
            ),
            runtimeSelectSetting(
                "shield_mode",
                "FEATURE_SETTING_UNIT_FRAME_SHIELDS",
                "clear",
                {
                    option("blizzard", "FEATURE_VALUE_BLIZZARD"),
                    option("clear", "FEATURE_VALUE_SHIELD_CLEAR"),
                    option("clear_value", "FEATURE_VALUE_SHIELD_CLEAR_VALUE"),
                }
            ),
            runtimeBooleanSetting(
                "dark_background",
                "FEATURE_SETTING_UNIT_FRAME_DARK_BACKGROUND",
                true
            ),
        },
    },
    {
        id = "blizzard_window_mover",
        category = "blizzard",
        title = localized("FEATURE_WINDOW_MOVER"),
        description = localized("FEATURE_WINDOW_MOVER_DESC"),
        details = localized("FEATURE_WINDOW_MOVER_DETAILS"),
        status = "available",
        combatProtected = true,
        settings = {
            selectSetting("save_mode", "FEATURE_SETTING_SAVE_MODE", "permanent", {
                option("session", "FEATURE_VALUE_SESSION"),
                option("permanent", "FEATURE_VALUE_PERMANENT"),
            }),
            booleanSetting("scaling", "FEATURE_SETTING_SCALING", true),
            booleanSetting(
                "require_move_modifier",
                "FEATURE_SETTING_WINDOW_MOVE_MODIFIER",
                false
            ),
            actionSetting("reset_layout", "FEATURE_SETTING_WINDOW_RESET", "FEATURE_ACTION_RESET"),
        },
    },
    {
        id = "action_loom",
        category = "action_bars",
        title = localized("FEATURE_ACTION_LOOM"),
        description = localized("FEATURE_ACTION_LOOM_DESC"),
        details = localized("FEATURE_ACTION_LOOM_DETAILS"),
        status = "planned",
        combatProtected = true,
        settings = {
            selectSetting("icon_shape", "FEATURE_SETTING_ICON_SHAPE", "round", {
                option("round", "FEATURE_VALUE_ROUND"),
                option("square", "FEATURE_VALUE_SQUARE"),
            }),
            rangeSetting(
                "button_scale_percent",
                "FEATURE_SETTING_ACTION_BARS_SIZE",
                100,
                70,
                150,
                5,
                "%"
            ),
            rangeSetting(
                "button_spacing",
                "FEATURE_SETTING_ACTION_BARS_SPACING",
                0,
                -4,
                18,
                1,
                " px"
            ),
            rangeSetting(
                "border_offset",
                "FEATURE_SETTING_ACTION_BARS_BORDER_OFFSET",
                2,
                -6,
                10,
                1,
                " px"
            ),
            booleanSetting("auto_classify", "FEATURE_SETTING_ACTION_BARS_AUTO_CLASSIFY", true),
            booleanSetting("keybinds", "FEATURE_SETTING_KEYBINDS", true),
            booleanSetting("counts", "FEATURE_SETTING_ACTION_BARS_COUNTS", true),
            booleanSetting("ready_highlight", "FEATURE_SETTING_ACTION_BARS_READY", true),
            rangeSetting("border_thickness", "FEATURE_SETTING_ACTION_BARS_BORDER", 2, 1, 4, 1, " px"),
            selectSetting("proc_style", "FEATURE_SETTING_ACTION_BARS_PROC_STYLE", "match", {
                option("match", "FEATURE_VALUE_ACTION_BARS_PROC_MATCH"),
                option("blizzard", "FEATURE_VALUE_ACTION_BARS_PROC_BLIZZARD"),
                option("hidden", "FEATURE_VALUE_HIDDEN"),
            }),
            actionSetting("open_editor", "FEATURE_SETTING_ACTION_BARS_EDITOR", "FEATURE_ACTION_MANAGE"),
            actionSetting("reset_overrides", "FEATURE_SETTING_ACTION_BARS_RESET", "FEATURE_ACTION_RESET"),
        },
    },
}

for index, definition in ipairs(definitions) do
    definition.order = index
    definition.status = definition.status == "available" and "available" or "planned"
    definition.defaultEnabled = false
    Registry:RegisterDefinition(definition)
end
