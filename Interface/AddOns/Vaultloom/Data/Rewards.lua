local _, Addon = ...

Addon.Data = Addon.Data or {}

-- Fallback used when the live weekly-reward API has not cached an item link yet.
Addon.Data.DELVES_GREAT_VAULT_ITEM_LEVEL = {
    233, 237, 240, 243, 246, 253, 256, 259, 259, 259, 259,
}

-- Midnight utility currencies shown in the right resources column.
-- Keep this order stable: it is part of the visible UI contract and of the
-- character snapshot format.
Addon.Data.MID_UTILITY_UPGRADE_CRESTS = {
    3347, 3345, 3343, 3341, 3383,
}

Addon.Data.MID_UTILITY_RESOURCE_ENTRIES = {
    { currencyID = 3028 },
    { currencyID = 3310 },
    { currencyID = 3316 },
    { itemID = 242241 },
    { itemID = 246951 },
    { currencyID = 3379 },
    { currencyID = 3392 },
    { currencyID = 3405 },
    { currencyID = 3376 },
    { currencyID = 3377 },
    { currencyID = 2803 },
    { currencyID = 1602 },
    { currencyID = 1792 },
    { currencyID = 2123 },
    { currencyID = 2797 },
}
