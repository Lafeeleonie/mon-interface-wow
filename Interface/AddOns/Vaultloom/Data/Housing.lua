local _, Addon = ...

Addon.Data.HOUSING = {
    currencyID = 3363,
    houseXPPerEndeavor = 2250,
    requestCooldown = 2.5,
    maxActivityEntries = 10,
    subTabs = {
        { key = "endeavors", labelKey = "HOUSING_TAB_ENDEAVORS" },
        { key = "activity", labelKey = "HOUSING_TAB_REWARDS" },
    },
    switchModes = { "off", "ask", "automatic" },
}
