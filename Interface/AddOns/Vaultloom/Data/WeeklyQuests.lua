local _, Addon = ...

Addon.Data = Addon.Data or {}

Addon.Data.PVE_WEEKLY = {
    spark = {
        key = "spark",
        questPool = { 93766, 93767, 93769, 93889, 93890, 93891, 93892, 93909, 93910, 93911, 93912, 93913, 94457, 95843 },
        variantSuffix = {
            [93767] = "Arcantina",
            [93892] = "Stormarion Assault",
            [93910] = "Prey",
            [94457] = "Battlegrounds",
        },
    },
    omnium_folio = {
        key = "omnium_folio",
        memoryKey = "omnium_folio",
        questPool = { 96410, 96441, 96442, 96443, 96444 },
        fallbackNames = {
            [96410] = "Seeking Knowledge Week 1 of 5: The Omnium Folio",
            [96441] = "Seeking Knowledge Week 2 of 5: Ritualized Arcana",
            [96442] = "Seeking Knowledge Week 3 of 5: Leyline Assaults",
            [96443] = "Seeking Knowledge Week 4 of 5: Magical Primessence",
            [96444] = "Seeking Knowledge Week 5 of 5: Off-World Magic",
        },
        titlePatterns = { "seeking knowledge", "omnium folio", "ritualized arcana", "leyline assaults", "magical primessence", "off-world magic" },
        allowTurnIn = true,
        hideWhenSeriesComplete = true,
    },
    rotating_world_weekly = {
        key = "rotating_world_weekly",
        memoryKey = "rotating_world_weekly",
        questPool = { 93751, 93752, 93753, 93754, 93755, 93756, 93757, 93758 },
        titlePatterns = { "windrunner spire", "murder row", "magister's terrace", "maisara caverns", "den of nalorakk", "the blinding vale", "voidscar arena", "nexuspunkt", "nexus point", "nexuspunkt xenas", "nexus-point xenas" },
        allowTurnIn = false,
    },
    rotating_world_aethas = {
        key = "rotating_world_aethas",
        memoryKey = "rotating_world_aethas",
        questPool = { 93497, 93598, 93595, 93605, 93611, 93612, 93613, 93593 },
        fallbackNames = {
            [93598] = "Emissary of War",
            [93595] = "A Call to Delves",
            [93611] = "A Shattered Path Through Time",
            [93612] = "The Arena Calls",
        },
        titlePatterns = { "abgesandter des krieges", "ruf der tiefe", "ein zerschmetterter pfad durch die zeit", "a shattered path through time", "call of the deep", "emissary of war", "die arena ruft", "the arena calls" },
        allowTurnIn = false,
    },
    housing = {
        key = "housing",
        memoryKey = "housing_weekly",
        questPool = { 95440, 95416, 95438 },
        titlePatterns = { "community engagement", "housewarming", "housing weekly", "gemeinschaftliches engagement", "einweihungsfeier", "ab die post", "vermisste tiere", "verlorene tiere", "missing pets", "wohn", "housing" },
        allowTurnIn = true,
        accountWide = true,
    },
}
