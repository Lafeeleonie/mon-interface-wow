local _, Addon = ...

local Seasons = Addon.Data.SEASONS
local activeSeason = Seasons:GetDefinition(Seasons:GetActiveKey("mythicPlus"))

Addon.Data.MYTHIC_PLUS = {
    seasonKey = activeSeason.key,
    stateID = Seasons:GetStateID("mythicplus", activeSeason.key),
    fallbackIcon = "Interface\\Icons\\Inv_10_gearupgrade_drakesshadowflameenhancedcrest",
    maxRecentRuns = 6,
    portalLevel = 10,
    subTabs = {
        { key = activeSeason.key, labelKey = activeSeason.mythicPlusLabelKey },
    },
    seasonKeys = {
        [activeSeason.key] = true,
    },
    goals = {
        { key = "explorer", labelKey = "MYTHIC_PLUS_REWARD_EXPLORER", timedRuns = 1, value = "1 Run" },
        { key = "conqueror", labelKey = "MYTHIC_PLUS_REWARD_CONQUEROR", score = 1500, warningAt = 1200 },
        { key = "master", labelKey = "MYTHIC_PLUS_REWARD_MASTER", score = 2000, warningAt = 1700 },
        { key = "hero", labelKey = "MYTHIC_PLUS_REWARD_HERO", score = 2500, warningAt = 2200 },
        { key = "legend", labelKey = "MYTHIC_PLUS_REWARD_LEGEND", score = 3000, warningAt = 2700 },
        { key = "umbralHero", labelKey = "MYTHIC_PLUS_REWARD_UMBRAL_HERO", percentile = "0.1%" },
    },
}
