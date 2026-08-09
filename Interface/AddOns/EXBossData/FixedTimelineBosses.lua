---@diagnostic disable: undefined-global
-- =============================================================
-- EXBossData/FixedTimelineBosses.lua
-- 统一触发配置中心（TIME / AI / BLZ）
--
-- 触发类型说明：
--   TIME = 固定轴（first/interval 展开）
--   AI   = duration->eventID 映射推理
--   BLZ  = 暴雪原生时间轴
--
-- 兼容导出：
--   _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS  (TIME 白名单)
--   _G.EXBOSS_DURATION_EVENT_RULES        (AI 映射表)
--   _G.EXBOSS_ENCOUNTER_TRIGGERS          (完整触发配置)
-- =============================================================
-- 如果STATE不FINISH 单独处里语音  格式
--   eventActions = {
--       [145] = { finishMode = "timer" },
--       [168] = { castStartUnit = "boss1" }, -- 首领圆环/怪物施法进度条只认 boss1 真实读条开始
--   },





local TRIGGER_TIME = "TIME"
local TRIGGER_AI = "AI"
local TRIGGER_BLZ = "BLZ"

local function NormalizeTrigger(v)
    local t = tostring(v or ""):upper()
    if t == TRIGGER_TIME or t == TRIGGER_AI or t == TRIGGER_BLZ then
        return t
    end
    return TRIGGER_BLZ
end

-- encounterID -> { trigger = TIME|AI|BLZ, durationRules = { {time,eventID}, ... }? }
local encounterTriggers = {
    --==============================================================================================================================
    --========================================= 执政团之座 (Seat of the Triumvirate)================================================
    --==============================================================================================================================
    [2065] = {
        trigger = TRIGGER_AI,
        durationRules = {
            { time = 16, eventID = 223, sync = true },
            { time = 7,  eventID = 224, sync = true },
            { time = 22, eventID = 225, sync = true },
            { time = 4,  eventID = 226, sync = true },
            { time = 50, eventID = 238, sync = true },

            { time = 40, eventID = 226 },
            { time = 28, eventID = 224 },

        },
        syncCycleLimits = {
            [224] = 2,
            [226] = 2,
        },
        eventActions = {
            [238] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },

    [2066] = {
        trigger = TRIGGER_AI, -- 萨普瑞什
        durationRules = {
            { time = 4,     eventID = 237 },
            { time = 32,    eventID = 243 },
            { time = 6,     eventID = 234 },
            { time = 20,    eventID = 235 },

            { time = 9.999, eventID = 234 },
            { time = 10,    eventID = 234 },
            { time = 12,    eventID = 237 },


        },
        eventActions = {
            [235] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
            [243] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },
    [2067] = {
        trigger = TRIGGER_AI, -- 总督奈扎尔
        durationRules = {
            { time = 6,  eventID = 376, sync = true },
            { time = 26, eventID = 246, sync = true },
            { time = 45, eventID = 247, sync = true },
            { time = 4,  eventID = 244, sync = true },
            { time = 12, eventID = 245, sync = true },

            { time = 4,  eventID = 244 },
            { time = 18, eventID = 376 },
            { time = 12, eventID = 244 },
            { time = 2,  eventID = 244 },
            { time = 14, eventID = 244 },
            { time = 6,  eventID = 244 },
        },
    },
    [2068] = {
        trigger = TRIGGER_AI, -- 鲁拉
        durationRules = {
            { time = 1.5, eventID = 249, sync = true },
            { time = 12,  eventID = 251, sync = true },
            { time = 24,  eventID = 250, sync = true },
            { time = 35,  eventID = 252, sync = true },

            { time = 5,   eventID = 251, sync = true },
            { time = 17,  eventID = 250, sync = true },
            { time = 28,  eventID = 252, sync = true },

            { time = 1.5, eventID = 253 },
            { time = 20,  eventID = 254 },

        },
    },

    --==============================================================================================================================
    --==================================================== 萨隆矿坑 (Pit of Saron)================================================
    --==============================================================================================================================

    [1999] = {
        trigger = TRIGGER_AI,                 -- 熔炉之主加弗斯特
        durationRules = {
            { time = 33,     eventID = 147 }, -- 冰川过载
            { time = 7,      eventID = 146 }, -- 投掷萨隆邪铁
            { time = 20,     eventID = 144 }, -- 碎矿猛击
            { time = 41.5,   eventID = 145 }, -- 寒晶践踏
            --{ time = 0.001,  eventID = 145 },   -- 寒晶践踏
            { time = 32.999, eventID = 147 }, -- 冰川过载
        },
        eventActions = {
            [145] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },

    [2000] = {
        trigger = TRIGGER_AI,                                                                     -- 天灾领主泰兰努斯
        durationRules = {
            { time = 24, eventID = 168, sync = true },                                            -- 死亡之握
            { time = 14, eventID = 164, sync = true },                                            -- 天灾领主的印记
            { time = 52, eventID = 165, sync = true },                                            -- 亡者大军
            { time = 7,  eventID = 166, sync = true },                                            -- 白霜冲击

            { time = 28, eventID = 166, sequenceGroup = "2000_post_sync_28", sequenceOrder = 1 }, -- 白霜冲击
            { time = 28, eventID = 164, sequenceGroup = "2000_post_sync_28", sequenceOrder = 2 }, -- 天灾领主的印记
            { time = 28, eventID = 167, sequenceGroup = "2000_post_sync_28", sequenceOrder = 3 }, -- 骸骨灌注
            { time = 12, eventID = 375 },                                                         -- 寒冰弹幕
        },
    },

    [2001] = {
        trigger = TRIGGER_AI,                                                                        -- 伊克和科瑞克
        durationRules = {
            { time = 11,    eventID = 206, sync = true },                                            -- 凋零猛击
            { time = 21,    eventID = 205, sync = true },                                            -- 瘟疫喷射
            { time = 50,    eventID = 203, sync = true },                                            -- 上啊，伊克！

            { time = 19,    eventID = 206, sequenceGroup = "2001_post_sync_19", sequenceOrder = 1 }, -- 凋零猛击
            { time = 19,    eventID = 205, sequenceGroup = "2001_post_sync_19", sequenceOrder = 2 }, -- 瘟疫喷射
            { time = 28.75, eventID = 204 },                                                         -- 暗影转移
        },
    },
    --==============================================================================================================================
    --==================================================== 通天峰 (Skyreach)=========================================================
    --==============================================================================================================================

    [1698] = {
        trigger = TRIGGER_AI,                 -- 兰吉特
        durationRules = {
            { time = 12,     eventID = 299 }, -- 散刃
            { time = 5,      eventID = 298 }, -- 疾风奔涌
            { time = 35,     eventID = 301 }, -- 战轮旋风
            { time = 18,     eventID = 300 }, -- 风轮
            { time = 20,     eventID = 299 }, -- 散刃
            { time = 10,     eventID = 300 }, -- 风轮
            { time = 19.999, eventID = 299 }, -- 散刃
        },
    },
    [1699] = {
        trigger = TRIGGER_AI, -- 阿拉卡纳斯
        durationRules = {
            { time = 5,  eventID = 302 },
            { time = 6,  eventID = 303 },
            { time = 10, eventID = 302 },
            { time = 15, eventID = 302 },
            { time = 24, eventID = 303 },
            { time = 50, eventID = 304 },
        },
    },
    [1700] = {
        trigger = TRIGGER_AI, -- 鲁克兰
        durationRules = {
            { time = 5,  eventID = 306, sync = true },
            { time = 12, eventID = 305, sync = true },
            { time = 38, eventID = 308, sync = true },
            { time = 12, eventID = 306 },
            { time = 21, eventID = 305 },
        },
        eventActions = {
            [308] = {
                finishMode = "cast_start",
                castStartUnit = "boss",
            },
        },

    },
    [1701] = {
        trigger = TRIGGER_AI,                          -- 高阶贤者维里克斯
        durationRules = {
            { time = 8,  eventID = 311, sync = true }, -- 日光冲击
            { time = 12, eventID = 310, sync = true }, -- 扔下
            { time = 5,  eventID = 309, sync = true }, -- 灼烧射线
            { time = 30, eventID = 312, sync = true }, -- 眩光
            { time = 10, eventID = 309 },
            { time = 12, eventID = 311 },
        },
    },
    --==============================================================================================================================
    --========================================= 艾杰斯亚学院 (Algeth'ar Academy)================================================
    --==============================================================================================================================

    [2562] = {
        trigger = TRIGGER_AI,                                                                     -- 维克萨姆斯
        durationRules = {
            { time = 5,  eventID = 276, sync = true },                                            -- 奥术驱除
            { time = 40, eventID = 277, sync = true },                                            -- 奥术裂隙
            { time = 2,  eventID = 274, sync = true },                                            -- 奥术宝珠
            { time = 15, eventID = 275, sync = true },                                            -- 法力炸弹

            { time = 18, eventID = 274, sequenceGroup = "2562_post_sync_18", sequenceOrder = 1 }, -- 奥术宝珠
            { time = 18, eventID = 276, sequenceGroup = "2562_post_sync_18", sequenceOrder = 2 }, -- 奥术驱除
            { time = 18, eventID = 275, sequenceGroup = "2562_post_sync_18", sequenceOrder = 3 }, -- 法力炸弹

        },
    },
    [2563] = {
        trigger = TRIGGER_AI, -- 茂林古树
        durationRules = {
            { time = 9,  eventID = 282 },
            { time = 30, eventID = 283 },
            { time = 18, eventID = 284 },
            { time = 54, eventID = 285 },
            { time = 55, eventID = 285 },
            { time = 28, eventID = 282 },
            { time = 33, eventID = 284 },
        },
    },
    [2564] = {
        trigger = TRIGGER_AI, -- 克罗兹
        durationRules = {
            { time = 5,  eventID = 278 },
            { time = 14, eventID = 279 },
            { time = 20, eventID = 280 },
        },
    },
    [2565] = {
        trigger = TRIGGER_AI, -- 多拉苟萨的回响
        durationRules = {
            { time = 7,  eventID = 293 },
            { time = 9,  eventID = 294 },
            { time = 10, eventID = 293 },
            { time = 12, eventID = 294 },
            { time = 14, eventID = 295 },
            { time = 28, eventID = 296 },
        },
        eventActions = {
            [296] = {
                finishMode = "cast_start",
                castStartUnit = "boss",
            },
        },
    },
    --==============================================================================================================================
    --=========================================  迈萨拉洞窟 (Maisara Caverns)================================================
    --==============================================================================================================================

    [3212] = {
        trigger = TRIGGER_AI, -- 姆罗金和内克拉克斯
        durationRules = {
            { time = 5,  eventID = 150, sync = true },
            { time = 12, eventID = 154, sync = true },
            { time = 20, eventID = 152, sync = true },
            { time = 28, eventID = 151, sync = true },
            { time = 35, eventID = 153, sync = true },
            { time = 41, eventID = 155, sync = true },

            { time = 45, eventID = 150, sequenceGroup = "3212_loop_45", sequenceOrder = 1 },
            { time = 45, eventID = 154, sequenceGroup = "3212_loop_45", sequenceOrder = 2 },
            { time = 45, eventID = 152, sequenceGroup = "3212_loop_45", sequenceOrder = 3 },
            { time = 45, eventID = 151, sequenceGroup = "3212_loop_45", sequenceOrder = 4 },
            { time = 45, eventID = 153, sequenceGroup = "3212_loop_45", sequenceOrder = 5 },
            { time = 45, eventID = 155, sequenceGroup = "3212_loop_45", sequenceOrder = 6 },
        },
    },

    [3213] = {
        trigger = TRIGGER_AI, -- 沃达扎
        durationRules = {
            { time = 3,      eventID = 16, sync = true },
            { time = 70,     eventID = 20, sync = true },
            { time = 14.166, eventID = 19, sync = true },
            { time = 25.333, eventID = 17, sync = true },

            { time = 33.5,   eventID = 16, sequenceGroup = "3213_post_sync_33_5", sequenceOrder = 1 },
            { time = 33.5,   eventID = 19, sequenceGroup = "3213_post_sync_33_5", sequenceOrder = 2 },
            { time = 33.5,   eventID = 17, sequenceGroup = "3213_post_sync_33_5", sequenceOrder = 3 },
        },
        eventActions = {
            [20] = {
                finishMode = "cast_start",
                castStartUnit = "boss",
            },
        },
    },
    [3214] = {
        trigger = TRIGGER_AI, -- 拉克图尔，聚魂之器
        durationRules = {
            { time = 4,  eventID = 156, sync = true },
            { time = 17, eventID = 157, sync = true },
            { time = 70, eventID = 158, sync = true },

            { time = 26, eventID = 156, sequenceGroup = "3214_loop_26", sequenceOrder = 1 },
            { time = 26, eventID = 157, sequenceGroup = "3214_loop_26", sequenceOrder = 2 },
            { time = 26, eventID = 156, sequenceGroup = "3214_loop_26", sequenceOrder = 3 },

        },
    },

    --==============================================================================================================================
    --========================================= 节点希纳斯 (Nexus-Point Xenas)================================================
    --==============================================================================================================================

    [3328] = {
        trigger = TRIGGER_AI, -- 核技工程长卡斯雷瑟
        durationRules = {
            { time = 1,  eventID = 108 },
            { time = 5,  eventID = 107 },
            { time = 10, eventID = 172 },
            { time = 38, eventID = 106 },


            { time = 11, eventID = 108 },
            { time = 12, eventID = 107 },
            { time = 13, eventID = 172 },
        },



        eventActions = {
            [106] = {
                --
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
                --
                resumeFromCanceledSnapshot = true,
                resumeSnapshotTolerance = 0.35,
                resumeSnapshotWindow = 20,
                canceledSnapshotEvents = { 107, 108, 172 },
            },
        },
    },

    [3332] = {
        trigger = TRIGGER_AI, -- 核心守卫奈萨拉
        durationRules = {
            { time = 3,     eventID = 35, sync = true },
            { time = 5,     eventID = 33, sync = true },
            { time = 15,    eventID = 36, sync = true },
            { time = 28,    eventID = 34, sync = true },

            { time = 16.85, eventID = 35 },
            { time = 18,    eventID = 33 },
            { time = 15,    eventID = 313 },
        },
        eventActions = {
            --[34] = { clearActiveSnapshotAfter = 1, waitTimelineFinish = true, timelineFinishTimeout = 8 },
            [34] = { waitTimelineFinish = true, timelineFinishTimeout = 8 },
        },
    },

    [3333] = {
        trigger = TRIGGER_AI, -- 洛萨克森
        durationRules = {
            { time = 2,  eventID = 111, sync = true },
            { time = 11, eventID = 109, sync = true },
            { time = 52, eventID = 110, sync = true },
            { time = 24, eventID = 112, sync = true },

            { time = 26, eventID = 111 },
            { time = 25, eventID = 109 },
            { time = 10, eventID = 112 },

        },
        eventActions = {
            [110] = { clearActiveSnapshotAfter = 2 },
        },

    },
    --==============================================================================================================================
    --================================================== 风行者之塔 (Windrunner Spire)===============================================
    --==============================================================================================================================



    [3056] = {
        trigger = TRIGGER_AI, -- 烬晓
        durationRules = {
            { time = 6,    eventID = 241 },
            { time = 10,   eventID = 239 },
            { time = 15,   eventID = 242 },
            { time = 13,   eventID = 239 },
            { time = 15.5, eventID = 241 },
            { time = 30,   eventID = 242 },

        },
        eventActions = {
            [242] = { clearActiveSnapshotAfter = 0.1 },
        },
    },

    [3057] = {
        trigger = TRIGGER_AI, -- 被遗弃的二人组
        durationRules = {
            { time = 8,      eventID = 28 },
            { time = 17.333, eventID = 25 },
            { time = 22.666, eventID = 26 },
            { time = 27.333, eventID = 28 },
            { time = 48,     eventID = 27 },
        },
        eventActions = {
            [27] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },


    [3058] = {
        trigger = TRIGGER_AI, -- 指挥官克罗鲁科
        durationRules = {
            { time = 3,     eventID = 210, sync = true },
            { time = 10,    eventID = 212, sync = true },
            { time = 18,    eventID = 213, sync = true },
            { time = 30,    eventID = 210, sync = true },
            { time = 37,    eventID = 212, sync = true },
            { time = 45,    eventID = 213, sync = true },


            { time = 0.001, eventID = 215 },
            { time = 8,     eventID = 216 },
        },
        eventActions = {
            [215] = { clearActiveSnapshotAfter = 0.1 },
        },
    },


    [3059] = {
        trigger = TRIGGER_AI, -- 无眠之心
        durationRules = {
            { time = 9,    eventID = 23 },
            { time = 11,   eventID = 23 },
            { time = 21,   eventID = 24 },
            { time = 23.5, eventID = 538 },
            { time = 24,   eventID = 21 },
            { time = 39,   eventID = 22 },
            { time = 53,   eventID = 21 },
        },

    },
    --==============================================================================================================================
    --=========================================  魔导师平台 (Magister's Terrace)================================================
    --==============================================================================================================================

    [3071] = {
        trigger = TRIGGER_AI,                            -- 奥能金刚库斯托斯
        durationRules = {
            { time = 5,    eventID = 286, sync = true }, --2
            { time = 15,   eventID = 288, sync = true }, --2
            { time = 22,   eventID = 287, sync = true },
            { time = 45,   eventID = 281, sync = true },

            { time = 22.5, eventID = 286 },
            { time = 23,   eventID = 288 },
        },
        eventActions = {
            [281] = {
                finishMode = "cast_start",
                castStartUnit = "boss",
                clearActiveSnapshotAfter = 2,
                preEventLimits = {
                    [286] = 2,
                    [288] = 2,
                },
            },
        },

    },
    [3072] = {
        trigger = TRIGGER_AI,                         -- 瑟拉奈尔·日鞭
        durationRules = {
            { time = 7,  eventID = 95, sync = true }, --2
            { time = 17, eventID = 93, sync = true },
            { time = 26, eventID = 94, sync = true },
            { time = 51, eventID = 96, sync = true },
            { time = 29, eventID = 95 },
        },
        eventActions = {
            [96] = {
                clearActiveSnapshotAfter = 2,
                preEventLimits = {
                    [95] = 2,
                },
            },

        },
    },

    [3073] = {
        trigger = TRIGGER_AI, -- 吉美尔鲁斯
        -- 待测试 疑似转阶段STATE暂停会被sync规则移除掉
        durationRules = {

            { time = 5,  eventID = 100, sync = true },
            { time = 16, eventID = 97,  sync = true },
            { time = 29, eventID = 98,  sync = true },

            { time = 5,  eventID = 635 },
        },

    },

    [3074] = {
        trigger = TRIGGER_AI, -- 迪詹崔乌斯
        durationRules = {
            { time = 3,  eventID = 420, sync = true },
            { time = 9,  eventID = 290, sync = true },
            { time = 15, eventID = 292, sync = true },

            { time = 24, eventID = 420, sequenceGroup = "3074_loop_24", sequenceOrder = 1 },
            { time = 24, eventID = 290, sequenceGroup = "3074_loop_24", sequenceOrder = 2 },
            { time = 24, eventID = 292, sequenceGroup = "3074_loop_24", sequenceOrder = 3 },
        },
    },
    --==============================================================================================================================
    --=========================================  12.0 新团本=============================================================================================
    --==================================================================================================================================================

    [3159] = {
        trigger = TRIGGER_AI, -- 腐沼
        durationRules = {
            { time = 41,  eventID = 428, sync = true },
            { time = 21,  eventID = 427, sync = true },
            { time = 8,   eventID = 426, sync = true },
            { time = 13,  eventID = 425, sync = true },
            { time = 114, eventID = 424, sync = true },

            { time = 49,  eventID = 425, sequenceGroup = "3159_loop_49", sequenceOrder = 1 },
            { time = 49,  eventID = 426, sequenceGroup = "3159_loop_49", sequenceOrder = 2 },
            { time = 49,  eventID = 428, sequenceGroup = "3159_loop_49", sequenceOrder = 3 },

            { time = 21,  eventID = 426, },
            { time = 12,  eventID = 427, },
            { time = 13,  eventID = 427, },
        },
    },

    --==============================================================================================================================
    --========================================= 12.1虚空之痕竞技场 =============================================================================================
    --==================================================================================================================================================
    --[[
    [3286] = {
        trigger = TRIGGER_AI, --
        durationRules = {
            { time = 17, eventID = 46,  sync = true },
            { time = 7,  eventID = 47,  sync = true },
            { time = 21, eventID = 54,  sync = true },
            { time = 13, eventID = 55,  sync = true },
            { time = 42, eventID = 297, sync = true },

            { time = 25, eventID = 47, },
            { time = 23, eventID = 55, },

        },
    },
]]



    [3286] = {
        trigger = TRIGGER_AI, -- 阿特洛苏斯
        durationRules = {
            { time = 17, eventID = 46,  sync = true },
            { time = 7,  eventID = 47,  sync = true },
            { time = 21, eventID = 54,  sync = true },
            { time = 13, eventID = 55,  sync = true },
            { time = 42, eventID = 297, sync = true },

            { time = 25, eventID = 47, },
            { time = 23, eventID = 55, },

        },
    },

    [3287] = {
        trigger = TRIGGER_AI, -- 煞戎努斯
        durationRules = {
            { time = 5,    eventID = 56, sync = true },
            { time = 19,   eventID = 57, sync = true },
            { time = 36,   eventID = 58, sync = true },


            { time = 44.8, eventID = 57, },
            { time = 44,   eventID = 58, },
            { time = 40,   eventID = 56, },
        },

    },






    --==============================================================================================================================
    --========================================= 12.1夺目谷============================================================================================
    --==================================================================================================================================================
    [3200] = {
        trigger = TRIGGER_AI, -- 阿特洛苏斯
        durationRules = {
            { time = 6,  eventID = 178, sync = true },
            { time = 20, eventID = 179, sync = true },
            { time = 40, eventID = 180, sync = true },

        },
    },



    [3202] = {
        trigger = TRIGGER_AI, -- [兹欧凯特]
        durationRules = {
            { time = 18, eventID = 190, sync = true },
            { time = 4,  eventID = 189, sync = true },
            { time = 32, eventID = 191, sync = true },

            { time = 45, eventID = 189, sequenceGroup = "3202_loop_45", sequenceOrder = 1 },
            { time = 45, eventID = 190, sequenceGroup = "3202_loop_45", sequenceOrder = 2 },
            { time = 45, eventID = 191, sequenceGroup = "3202_loop_45", sequenceOrder = 3 },

        },
    },
    --==================================================================================================================================================
    --========================================= 12.1 密谋小径============================================================================================
    --===================================================================================================================================================
    [3101] = {
        trigger = TRIGGER_AI, -- [凯斯媞亚·魔力之心]
        durationRules = {
            { time = 6,  eventID = 122, sync = true },
            { time = 20, eventID = 202, sync = true },
            { time = 40, eventID = 120, sync = true },

        },
    },

    [3102] = {
        trigger = TRIGGER_AI, -- [赞恩·刃悲]
        durationRules = {
            { time = 12, eventID = 124, sync = true },
            { time = 26, eventID = 193, sync = true },
            { time = 36, eventID = 125, sync = true },
            { time = 18, eventID = 123, sync = true },
            { time = 8,  eventID = 127, sync = true },


            { time = 26, eventID = 124, },

        },
    },
    [3103] = {
        trigger = TRIGGER_AI, -- [歼灭者萨祖克斯]
        durationRules = {
            { time = 6,  eventID = 30,  sync = true },
            { time = 15, eventID = 559, sync = true },
            { time = 35, eventID = 32,  sync = true },

            { time = 27, eventID = 30, },

        },
    },
    [3105] = {
        trigger = TRIGGER_AI, -- [利希尔·烬怒]
        durationRules = {
            { time = 15, eventID = 37,  sync = true },
            { time = 10, eventID = 38,  sync = true },
            { time = 24, eventID = 207, sync = true },

            { time = 57, eventID = 38, },
            { time = 55, eventID = 37, },
            { time = 59, eventID = 207, },

        },
    },

    --==================================================================================================================================================
    --========================================= 12.1 毒牙祭坛============================================================================================
    --===================================================================================================================================================
    [3456] = {
        trigger = TRIGGER_AI,                          -- [拉维]
        durationRules = {
            { time = 8,  eventID = 797, sync = true }, --三重
            { time = 25, eventID = 795, sync = true }, --食腐
            { time = 13, eventID = 798, sync = true }, --反刍
            { time = 45, eventID = 795, sync = true }, --食腐
            { time = 24, eventID = 899, sync = true },
            { time = 24, eventID = 797, },             --三重

        },
        eventActions = {
            [795] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },

    -- 00:00 1307894 落石
    -- 00:08 1296220 点名
    -- 00:25 1296216 转阶段


    -- 00:08 1296220 点名
    -- 00:13 1296050 头前
    -- 00:24 1307894 落石
    -- 00:32 1296220 点名
    -- 00:45 1296216 转阶段


    [3457] = {
        trigger = TRIGGER_AI, -- [毒蛇]
        durationRules = {
            { time = 1,  eventID = 813, sync = true },
            { time = 11, eventID = 814, sync = true },
            { time = 19, eventID = 816, sync = true },

            { time = 10, eventID = 813, sync = true },
            { time = 28, eventID = 816, sync = true },
            { time = 20, eventID = 814, sync = true },

            { time = 20, eventID = 818, },

        },
    },

    -- 00:01 1299154 点名
    -- 00:11 1298949 坦克尖刺
    -- 00:19 1299053 转阶段

    -- 拉断线之后
    -- 00:20 1300686 同化
    -- 同化之后
    -- 00:00 冲锋+头前
    -- 00:10 1299154 点名
    -- 00:20 1298949 坦克尖刺
    -- 00:28 1299053 转阶段







    [3458] = {
        trigger = TRIGGER_AI, -- [尾王]
        durationRules = {
            { time = 30, eventID = 821, sync = true },
            { time = 16, eventID = 823, sync = true },
            { time = 24, eventID = 824, sync = true },

            { time = 62, eventID = 822, },
            { time = 32, eventID = 824, },
            { time = 16, eventID = 821, },

        },
        eventActions = {
            [822] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },
}

local fixedSet = {}
local durationRules = {}

for encounterID, row in pairs(encounterTriggers) do
    if type(row) == "table" then
        row.trigger = NormalizeTrigger(row.trigger)
        if row.trigger == TRIGGER_TIME then
            fixedSet[encounterID] = true
        end
        if type(row.durationRules) == "table" and #row.durationRules > 0 then
            durationRules[encounterID] = row.durationRules
            durationRules[tostring(encounterID)] = row.durationRules
        end
    else
        local t = NormalizeTrigger(row)
        encounterTriggers[encounterID] = { trigger = t }
        if t == TRIGGER_TIME then
            fixedSet[encounterID] = true
        end
    end
end

_G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS = fixedSet
_G.EXBOSS_DURATION_EVENT_RULES = durationRules
_G.EXBOSS_ENCOUNTER_TRIGGERS = encounterTriggers

_G.EXBossData = _G.EXBossData or {}

function _G.EXBossData.GetEncounterTriggerConfig()
    return _G.EXBOSS_ENCOUNTER_TRIGGERS
end

function _G.EXBossData.GetEncounterTrigger(encounterID)
    local id = tonumber(encounterID) or encounterID
    local row = encounterTriggers[id]
    if row == nil then
        row = encounterTriggers[tostring(id)]
    end
    if type(row) == "table" then
        return NormalizeTrigger(row.trigger)
    end
    return NormalizeTrigger(row)
end

return encounterTriggers
