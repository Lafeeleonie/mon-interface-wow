local _, ns = ...

ns.Data = ns.Data or {}

local ZONE = "Coiled Isle"
local MAP_ID = 2512

local patch = {
    dataVersion = "2026.08.12-12.1.0",
    reviewedAt = "2026-08-12",
    sources = {
        { addon = "AllTheThings", version = "5.3.0a", interface = 120100 },
        { addon = "HandyNotes_Midnight", version = "148", interface = 120100 },
        { site = "Wowhead item tooltips", checkedAt = "2026-08-12" },
    },
    entries = {},
}

local function addEntry(entry)
    entry.zone = entry.zone or ZONE
    patch.entries[#patch.entries + 1] = entry
end

local mounts = {
    { itemID = 275653, spellID = 1297216, name = "Sea-Dwelling Isle Serpent", source = "vendor", cost = { currency = { 3546, 2500 } } },
    { itemID = 275654, spellID = 1297217, name = "Caustic Venomfang", source = "vendor", cost = { currency = { 3448, 10000 } } },
    { itemID = 275656, spellID = 1297224, name = "Auriferous Venomfang", source = "achievement", achievementID = 63359 },
    { itemID = 276549, spellID = 1299961, name = "Topaz Skyfang", source = "drop", achievementID = 63358, sourceDetail = "Coiled Isle rare mobs" },
    { itemID = 276551, spellID = 1299963, name = "Violet-Backed Skyfang", source = "reputation", cost = { currency = { 3316, 8000 } } },
    { itemID = 276553, spellID = 1299965, name = "Emerald Skyfang", source = "achievement", achievementID = 63653 },
    { itemID = 276801, spellID = 1300777, name = "Venomous Coiler", source = "achievement", achievementID = 63630 },
    { itemID = 276802, spellID = 1300778, name = "Indigo Coiled Horror", source = "reputation", cost = { currency = { 3316, 6000 } } },
    { itemID = 276803, spellID = 1300779, name = "Ruby Writhe", source = "drop", achievementID = 63358, sourceDetail = "Coiled Isle rare mobs" },
}

for _, entry in ipairs(mounts) do
    entry.category = "mounts"
    entry.key = "mount-item:" .. entry.itemID
    addEntry(entry)
end

local pets = {
    { speciesID = 5011, itemID = 268644, name = "Zan", source = "quest", achievementID = 63641, waypoint = { MAP_ID, 0.609, 0.326, "Zan" } },
    { speciesID = 5028, itemID = 270214, name = "Poisoned Parasite", source = "wild", waypoint = { MAP_ID, 0.582, 0.386, "Poisoned Parasite" } },
    { speciesID = 5029, itemID = 270249, name = "Cursed Spawn", source = "wild", waypoint = { MAP_ID, 0.441, 0.466, "Cursed Spawn" } },
    { speciesID = 5030, itemID = 270253, name = "Jaundiced Slitherer", source = "wild", waypoint = { MAP_ID, 0.499, 0.558, "Jaundiced Slitherer" } },
    { speciesID = 5031, itemID = 270254, name = "Caustic Writhling", source = "wild", waypoint = { 2509, 0.381, 0.307, "Caustic Writhling" } },
    { speciesID = 5032, itemID = 270252, name = "Nightfur Kapara", source = "wild", waypoint = { MAP_ID, 0.620, 0.819, "Nightfur Kapara" } },
    { speciesID = 5033, itemID = 270251, name = "Sleek Snakebiter", source = "wild", waypoint = { MAP_ID, 0.607, 0.779, "Sleek Snakebiter" } },
    { speciesID = 5034, itemID = 270250, name = "Steady Croakfrog", source = "wild", waypoint = { MAP_ID, 0.661, 0.561, "Steady Croakfrog" } },
    { speciesID = 5035, itemID = 270248, name = "Autumn Snapling", source = "wild", waypoint = { MAP_ID, 0.679, 0.815, "Autumn Snapling" } },
    { speciesID = 5070, itemID = 275020, name = "Venom Elemental", source = "vendor" },
    { speciesID = 5071, itemID = 275631, name = "Corrosive Writhling", source = "vendor", cost = { currency = { 3448, 5000 } } },
    { speciesID = 5072, itemID = 275632, name = "Volatile Venomfang", source = "vendor", cost = { currency = { 3448, 5000 } } },
    { speciesID = 5093, itemID = 276248, name = "Snek'zali", source = "reputation", cost = { currency = { 3316, 2500 } } },
    { speciesID = 5131, itemID = 279921, name = "Ki'clak", source = "achievement", achievementID = 63633, waypoint = { MAP_ID, 0.693, 0.523, "Ki'clak" } },
    { speciesID = 5132, itemID = 280138, name = "Zesty", source = "achievement", achievementID = 62492 },
}

for _, entry in ipairs(pets) do
    entry.category = "pets"
    entry.key = "pet:" .. entry.speciesID
    addEntry(entry)
end

local toys = {
    { itemID = 268504, name = "Malfunctioning Staff", source = "treasure", waypoint = { MAP_ID, 0.7537, 0.6833, "Malfunctioning Staff" } },
    { itemID = 274921, name = "Pearl of Jubilation", source = "treasure", waypoint = { MAP_ID, 0.7063, 0.7663, "Brine-Crusted Chest" } },
    { itemID = 276925, name = "Idol of Ula'tek", source = "reputation", cost = { currency = { 3316, 4000 } } },
    { itemID = 277954, name = "Jaktu's Cursed Blade", source = "treasure", waypoint = { MAP_ID, 0.6043, 0.5946, "Jaktu's Cursed Blade" } },
    { itemID = 279021, name = "Forgotten Memento", source = "treasure", waypoint = { MAP_ID, 0.6726, 0.4846, "Grave of Someone Forgotten" } },
    { itemID = 279052, name = "Ancient Amani Mask", source = "treasure", waypoint = { MAP_ID, 0.6544, 0.0560, "Sunken Diver's Chest" } },
    { itemID = 279054, name = "Idol of Blue Water and Blue Sky", source = "treasure", waypoint = { MAP_ID, 0.7188, 0.6666, "Abandoned Amani Privateer's Cache" } },
    { itemID = 280201, name = "Book of Storytime", source = "quest", achievementID = 63641, zone = "Zul'Aman", waypoint = { 2437, 0.453, 0.487, "Book of Storytime" } },
    { itemID = 280419, name = "Cursed Badge of the Soulcoilers", source = "achievement", achievementID = 63662 },
}

for _, entry in ipairs(toys) do
    entry.category = "toys"
    entry.key = "toy:" .. entry.itemID
    addEntry(entry)
end

local decorations = {
    { 1140, 253455, "Unearthed Amani Sarcophagus Lid" },
    { 1150, 253473, "Unearthed Amani Sarcophagus Base" },
    { 1428, 244345, "Forgotten Amani Urn" },
    { 5130, 248962, "Mysterious Voodoo Mask" },
    { 5648, 249765, "Amani Supply Sack" },
    { 15156, 263316, "Amani Storage Crate" },
    { 15283, 263873, "Amani Forge" },
    { 15506, 264271, "Amani Ritual Totem" },
    { 15569, 264331, "Amani Wayfarer's Torch" },
    { 17799, 266169, "Soulcoiler Canopy" },
    { 18900, 267377, "Ula'tek Ritual Monolith" },
    { 18901, 267378, "Venom Scholar's Focus" },
    { 21102, 269637, "Serpent-Caller Spike" },
    { 21324, 269778, "Stitched Blisterfang Bag" },
    { 21325, 269779, "Fanged Scaleskin Pouch" },
    { 21615, 271175, "Venomjade Necklace" },
    { 21616, 271176, "Feathered Ula'tek Talisman" },
    { 21617, 271177, "Opened Serpentine Reliquary" },
    { 21653, 271358, "Clutch of Ula'tek" },
    { 21720, 271604, "Egg of Ula'tek" },
    { 21725, 271609, "Destroyed Clutch of Ula'tek" },
    { 21832, 271850, "Venomous Tendril" },
    { 21833, 271851, "Oozing Vilescar Barricade" },
    { 21953, 272362, "Venombound Ropes" },
    { 23871, 275628, "Cauldron of Ula'tek" },
    { 23873, 277323, "Sealed Serpentine Reliquary" },
    { 23874, 277271, "Wrapped Scaleskin Urn" },
    { 23875, 277273, "Cracked Vilescar Urn" },
    { 23876, 277275, "Charmed Blisterfang Urn" },
    { 23881, 275578, "Soulcoiler Sconce" },
    { 24512, 279917, "Soulcoiler Skull" },
    { 24519, 279919, "Soulcoiler Jaw" },
    { 25137, 281573, "Venomous Thread" },
    { 25138, 281577, "Venomous Globule" },
    { 25139, 280764, "Venomous Defender's Barricade" },
    { 25292, 279922, "Altar of Corrosion" },
    { 25294, 276457, "Amani Worship Candle" },
    { 25295, 276459, "Amani Ritual Candles" },
    { 25297, 277921, "Traditional Tortollan Tent" },
    { 25299, 277923, "Aged Tortollan Scroll Case" },
    { 25300, 277925, "Blue Tortollan Signpost" },
    { 25336, 277927, "Yellowed Kelp Pile" },
    { 26097, 277280, "Vilescar Weapon Rack" },
    { 26196, 277929, "Rustic Fishing Rack" },
    { 26197, 277931, "Hanging Yellowed Kelp" },
    { 26203, 278691, "Twilight Brazier" },
    { 26204, 281620, "Corrosive Cache" },
    { 26375, 281580, "Pungent Atal'Utek Shroom" },
    { 26376, 281582, "Atal'Utek Ivy" },
    { 26377, 279292, "Zul'Aman Pine Tree" },
    { 26481, 280218, "Tortollan Scholar Satchel" },
    { 26484, 279285, "Lost Tortollan Scroll" },
    { 27041, 279452, "\"Summoning of Ula'tek\" Mural" },
    { 27042, 279508, "\"The Hunger Awakens\" Mural" },
}

for _, definition in ipairs(decorations) do
    addEntry({
        category = "decorations",
        decorID = definition[1],
        itemID = definition[2],
        key = "decor:" .. definition[1],
        name = definition[3],
        source = "coiled_isle",
    })
end

patch.counts = {
    mounts = #mounts,
    pets = #pets,
    toys = #toys,
    decorations = #decorations,
    all = #patch.entries,
}

ns.Data.CoiledIsleCompendium = patch

local catalog = ns.Data.MidnightCompendium
if type(catalog) == "table" and type(catalog.entries) == "table" then
    for _, entry in ipairs(patch.entries) do
        catalog.entries[#catalog.entries + 1] = entry
    end
    catalog.generatedAt = patch.reviewedAt
    catalog.dataVersion = patch.dataVersion
    catalog.sourceAudit = patch.sources
end
