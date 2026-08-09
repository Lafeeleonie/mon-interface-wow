_G.EXBossData.RegisterBossPreset("mplus_heal", {
    key = "EXWIND_US",
    name = "EXWIND_US",
    author = "EXWIND_US",
    builtIn = true,
    events = {
        [6] = { enabled = false },
        [278] = {
            enabled = true,
            rules = {
                castWindow = {
                    enabled = true,
                    ringEnabled = true,
                    interruptCheckEnabled = true,
                    windowBefore = 1,
                    windowAfter = 2,
                },
            },
        },
    },
})
