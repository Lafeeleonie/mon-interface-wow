_G.EXBossData.RegisterBossPreset("mplus_tank", {
    key = "PresetConfig",
    name = "预设配置",
    author = "预设配置",
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
