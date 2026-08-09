-- ExwindDB.lua - 全局共享数据库
-- 提供职业、专精等静态数据，减少API调用，供所有模块使用

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 创建全局数据库表
local EXDB = {}
_G.EXDB = EXDB

-------------------------------------------------------
-- 职业数据
-------------------------------------------------------
EXDB.Classes = {
    [1]  = { id = 1, name = "战士", nameEN = "WARRIOR", colorHex = "C79C6E", colorRGB = { 198, 155, 109 }, icon = 626003 },
    [2]  = { id = 2, name = "圣骑士", nameEN = "PALADIN", colorHex = "F48CBA", colorRGB = { 244, 140, 186 }, icon = 626000 },
    [3]  = { id = 3, name = "猎人", nameEN = "HUNTER", colorHex = "ABD473", colorRGB = { 170, 211, 114 }, icon = 626008 },
    [4]  = { id = 4, name = "潜行者", nameEN = "ROGUE", colorHex = "FFF468", colorRGB = { 255, 244, 104 }, icon = 626005 },
    [5]  = { id = 5, name = "牧师", nameEN = "PRIEST", colorHex = "FFFFFF", colorRGB = { 255, 255, 255 }, icon = 626004 },
    [6]  = { id = 6, name = "死亡骑士", nameEN = "DEATHKNIGHT", colorHex = "C41E3A", colorRGB = { 196, 30, 58 }, icon = 135771 },
    [7]  = { id = 7, name = "萨满祭司", nameEN = "SHAMAN", colorHex = "0070DD", colorRGB = { 0, 112, 221 }, icon = 626006 },
    [8]  = { id = 8, name = "法师", nameEN = "MAGE", colorHex = "3FC7EB", colorRGB = { 63, 199, 235 }, icon = 626001 },
    [9]  = { id = 9, name = "术士", nameEN = "WARLOCK", colorHex = "8788EE", colorRGB = { 135, 136, 238 }, icon = 626007 },
    [10] = { id = 10, name = "武僧", nameEN = "MONK", colorHex = "00FF98", colorRGB = { 0, 255, 152 }, icon = 626002 },
    [11] = { id = 11, name = "德鲁伊", nameEN = "DRUID", colorHex = "FF7C0A", colorRGB = { 255, 124, 10 }, icon = 625999 },
    [12] = { id = 12, name = "恶魔猎手", nameEN = "DEMONHUNTER", colorHex = "A330C9", colorRGB = { 163, 48, 201 }, icon = 1260827 },
    [13] = { id = 13, name = "唤魔师", nameEN = "EVOKER", colorHex = "33937F", colorRGB = { 51, 147, 127 }, icon = 4574311 },
}

-------------------------------------------------------
-- 专精数据
-------------------------------------------------------
EXDB.Specs = {
    -- 法师 (8) - 智力
    { id = 62, name = "奥术", classID = 8, icon = 135932, role = "DAMAGER", primaryStat = "智力", RangeSpell = 30451 }, --奥冲
    { id = 63, name = "火焰", classID = 8, icon = 135810, role = "DAMAGER", primaryStat = "智力", RangeSpell = 133 }, --火球
    { id = 64, name = "冰霜", classID = 8, icon = 135846, role = "DAMAGER", primaryStat = "智力", RangeSpell = 30455 }, --冰枪

    -- 圣骑士 (2) - 力量/智力
    { id = 65, name = "神圣", classID = 2, icon = 135920, role = "HEALER", primaryStat = "智力", RangeSpell = 275773 }, --审判
    { id = 66, name = "防护", classID = 2, icon = 236264, role = "TANK", primaryStat = "力量", RangeSpell = 96231 }, --责难
    { id = 70, name = "惩戒", classID = 2, icon = 135873, role = "DAMAGER", primaryStat = "力量", RangeSpell = 383328 }, --裁决

    -- 战士 (1) - 力量
    { id = 71, name = "武器", classID = 1, icon = 132355, role = "DAMAGER", primaryStat = "力量", RangeSpell = 12294 }, --致死
    { id = 72, name = "狂怒", classID = 1, icon = 132347, role = "DAMAGER", primaryStat = "力量", RangeSpell = 23881 }, --嗜血
    { id = 73, name = "防护", classID = 1, icon = 132341, role = "TANK", primaryStat = "力量", RangeSpell = 23922 }, --盾猛

    -- 德鲁伊 (11) - 敏捷/智力
    { id = 102, name = "平衡", classID = 11, icon = 136096, role = "DAMAGER", primaryStat = "智力", RangeSpell = 8921 }, --月火
    { id = 103, name = "野性", classID = 11, icon = 132115, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 22568 }, --咬
    { id = 104, name = "守护", classID = 11, icon = 132276, role = "TANK", primaryStat = "敏捷", RangeSpell = 33917 }, --列
    { id = 105, name = "恢复", classID = 11, icon = 136041, role = "HEALER", primaryStat = "智力", RangeSpell = 8921 }, --月火

    -- 死亡骑士 (6) - 力量
    { id = 250, name = "鲜血", classID = 6, icon = 135770, role = "TANK", primaryStat = "力量", RangeSpell = 49998 }, --灵打
    { id = 251, name = "冰霜", classID = 6, icon = 135773, role = "DAMAGER", primaryStat = "力量", RangeSpell = 49998 }, --灵打
    { id = 252, name = "邪恶", classID = 6, icon = 135775, role = "DAMAGER", primaryStat = "力量", RangeSpell = 49998 }, --灵打

    -- 猎人 (3) - 敏捷
    { id = 253, name = "野兽控制", classID = 3, icon = 461112, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 187707 }, --压制
    { id = 254, name = "射击", classID = 3, icon = 236179, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 147362 }, --反制射击
    { id = 255, name = "生存", classID = 3, icon = 461113, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 147362 }, --反制射击

    -- 牧师 (5) - 智力
    { id = 256, name = "戒律", classID = 5, icon = 135940, role = "HEALER", primaryStat = "智力", RangeSpell = 585 }, --惩击
    { id = 257, name = "神圣", classID = 5, icon = 237542, role = "HEALER", primaryStat = "智力", RangeSpell = 585 }, --惩击
    { id = 258, name = "暗影", classID = 5, icon = 136207, role = "DAMAGER", primaryStat = "智力", RangeSpell = 8902 }, --震爆

    -- 潜行者 (4) - 敏捷
    { id = 259, name = "奇袭", classID = 4, icon = 236270, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766 }, --脚踢
    { id = 260, name = "狂徒", classID = 4, icon = 236286, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766 }, --脚踢
    { id = 261, name = "敏锐", classID = 4, icon = 132320, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766 }, --脚踢

    -- 萨满祭司 (7) - 敏捷/智力
    { id = 262, name = "元素", classID = 7, icon = 136048, role = "DAMAGER", primaryStat = "智力", RangeSpell = 188196 }, -- 闪电箭
    { id = 263, name = "增强", classID = 7, icon = 237581, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 60103 }, --熔岩猛击
    { id = 264, name = "恢复", classID = 7, icon = 136052, role = "HEALER", primaryStat = "智力", RangeSpell = 188196 }, -- 闪电箭

    -- 术士 (9) - 智力
    { id = 265, name = "痛苦", classID = 9, icon = 136145, role = "DAMAGER", primaryStat = "智力", RangeSpell = 686 }, --暗影箭
    { id = 266, name = "恶魔学识", classID = 9, icon = 136172, role = "DAMAGER", primaryStat = "智力", RangeSpell = 105174 }, --古尔丹之手
    { id = 267, name = "毁灭", classID = 9, icon = 136186, role = "DAMAGER", primaryStat = "智力", RangeSpell = 116858 }, --混乱箭

    -- 武僧 (10) - 敏捷
    { id = 268, name = "酒仙", classID = 10, icon = 608951, role = "TANK", primaryStat = "敏捷", RangeSpell = 100780 }, --虎掌
    { id = 269, name = "踏风", classID = 10, icon = 608953, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 100780 }, --虎掌
    { id = 270, name = "织雾", classID = 10, icon = 608952, role = "HEALER", primaryStat = "智力", RangeSpell = 100780 }, --虎掌

    -- 恶魔猎手 (12) - 敏捷
    { id = 577, name = "浩劫", classID = 12, icon = 1247264, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 162794 }, --混打
    { id = 581, name = "复仇", classID = 12, icon = 1247265, role = "TANK", primaryStat = "敏捷", RangeSpell = 263642 }, --破裂
    { id = 1480, name = "噬灭", classID = 12, icon = 7455385, role = "DAMAGER", primaryStat = "智力", RangeSpell = 473662 }, --吞噬

    -- 唤魔师 (13) - 智力
    { id = 1467, name = "湮灭", classID = 13, icon = 4511811, role = "DAMAGER", primaryStat = "智力", RangeSpell = 362969 }, --碧蓝打击
    { id = 1468, name = "恩护", classID = 13, icon = 4511812, role = "HEALER", primaryStat = "智力", RangeSpell = 362969 }, --碧蓝打击
    { id = 1473, name = "增辉", classID = 13, icon = 5198700, role = "DAMAGER", primaryStat = "智力", RangeSpell = 395160 }, --喷发
}

-------------------------------------------------------
-- 快速查询表 (索引表)
-------------------------------------------------------

-- 专精ID -> 专精数据
EXDB.SpecByID = {}
-- 专精ID -> 角色键（tank/heal/dps）
EXDB.SpecRoleKeyByID = {}
-- 按角色分组的专精列表
EXDB.SpecsByRole = {
    tank = {},
    heal = {},
    dps = {},
}
-- 职业ID -> 专精列表
EXDB.SpecsByClassID = {}
for _, spec in ipairs(EXDB.Specs) do
    EXDB.SpecByID[spec.id] = spec

    local roleKey
    if spec.role == "TANK" then
        roleKey = "tank"
    elseif spec.role == "HEALER" then
        roleKey = "heal"
    elseif spec.role == "DAMAGER" or spec.role == "DPS" then
        roleKey = "dps"
    end
    EXDB.SpecRoleKeyByID[spec.id] = roleKey

    if roleKey and EXDB.SpecsByRole[roleKey] then
        table.insert(EXDB.SpecsByRole[roleKey], spec)
    end

    if spec.classID then
        EXDB.SpecsByClassID[spec.classID] = EXDB.SpecsByClassID[spec.classID] or {}
        table.insert(EXDB.SpecsByClassID[spec.classID], spec)
    end
end

-- 坦克专精列表
EXDB.TankSpecs = {
    [66] = true,  -- 圣骑士-防护
    [73] = true,  -- 战士-防护
    [104] = true, -- 德鲁伊-守护
    [250] = true, -- 死亡骑士-鲜血
    [268] = true, -- 武僧-酒仙
    [581] = true, -- 恶魔猎手-复仇
}

-- 治疗专精列表
EXDB.HealerSpecs = {
    [65] = true,   -- 圣骑士-神圣
    [105] = true,  -- 德鲁伊-恢复
    [256] = true,  -- 牧师-戒律
    [257] = true,  -- 牧师-神圣
    [264] = true,  -- 萨满祭司-恢复
    [270] = true,  -- 武僧-织雾
    [1468] = true, -- 唤魔师-恩护
}

-- 职业排序 (常用排序: DK, 战士, 骑士, 猎人, 萨满, 唤魔师, 盗贼, DH, 武僧, 德鲁伊, 法师, 术士, 牧师)
EXDB.ClassOrder = { 6, 1, 2, 3, 7, 13, 4, 12, 10, 11, 8, 9, 5 }

-------------------------------------------------------
-- 全职业打断技能数据 (用于 ExM+.InterruptTracker 等)
-- [SpecID] = { id = SpellID, cd = BaseSeconds }
-- 仅包含核心打断技能(Kick/Counterspell等)。无打断专精 id=0。
-------------------------------------------------------
EXDB.InterruptData = {
    -- 死亡骑士 (Death Knight)
    [250] = { id = 47528, cd = 12 }, -- 鲜血: 心灵冰冻
    [251] = { id = 47528, cd = 12 }, -- 冰霜: 心灵冰冻
    [252] = { id = 47528, cd = 12 }, -- 邪恶: 心灵冰冻

    -- 恶魔猎手 (Demon Hunter)
    [577] = { id = 183752, cd = 15 }, -- 浩劫: 吞噬魔法
    [581] = { id = 183752, cd = 15 }, -- 复仇: 吞噬魔法
    [1480] = { id = 183752, cd = 15 },
    -- 德鲁伊 (Druid)
    [102] = { id = 0, cd = 0 },       -- 平衡: 日光术(不启用)
    [103] = { id = 106839, cd = 15 }, -- 野性: 迎头痛击
    [104] = { id = 106839, cd = 15 }, -- 守护: 迎头痛击
    [105] = { id = 0, cd = 0 },       -- 恢复: 无

    -- 唤魔师 (Evoker)
    [1467] = { id = 351338, cd = 20 }, -- 湮灭: 镇压
    [1468] = { id = 0, cd = 0 },       -- 恩护: 无
    [1473] = { id = 351338, cd = 18 }, -- 增辉: 镇压

    -- 猎人 (Hunter)
    [253] = { id = 147362, cd = 24 }, -- 兽王: 反制射击
    [254] = { id = 147362, cd = 24 }, -- 射击: 反制射击
    [255] = { id = 187707, cd = 15 }, -- 生存: 压制

    -- 法师 (Mage)
    [62] = { id = 2139, cd = 20 }, -- 奥术: 法术反制
    [63] = { id = 2139, cd = 20 }, -- 火焰: 法术反制
    [64] = { id = 2139, cd = 20 }, -- 冰霜: 法术反制

    -- 武僧 (Monk)
    [268] = { id = 116705, cd = 15 }, -- 酒仙: 切喉手
    [269] = { id = 116705, cd = 15 }, -- 踏风: 切喉手
    [270] = { id = 0, cd = 0 },       -- 织雾: 无

    -- 圣骑士 (Paladin)
    [66] = { id = 96231, cd = 15 }, -- 防护: 责难
    [70] = { id = 96231, cd = 15 }, -- 惩戒: 责难
    [65] = { id = 0, cd = 0 },      -- 神圣: 无

    -- 牧师 (Priest)
    [258] = { id = 15487, cd = 30 }, -- 暗影: 沉默
    [256] = { id = 0, cd = 0 },      -- 戒律: 无
    [257] = { id = 0, cd = 0 },      -- 神圣: 无

    -- 潜行者 (Rogue)
    [259] = { id = 1766, cd = 15 }, -- 奇袭: 脚踢
    [260] = { id = 1766, cd = 15 }, -- 狂徒: 脚踢
    [261] = { id = 1766, cd = 15 }, -- 敏锐: 脚踢

    -- 萨满祭司 (Shaman)
    [262] = { id = 57994, cd = 12 }, -- 元素: 风剪
    [263] = { id = 57994, cd = 12 }, -- 增强: 风剪
    [264] = { id = 57994, cd = 30 }, -- 恢复: 风剪

    -- 术士 (Warlock)
    [265] = { id = 19647, cd = 24 }, -- 痛苦: 法术封锁
    [266] = { id = 19647, cd = 30 }, -- 恶魔: 法术封锁
    [267] = { id = 19647, cd = 24 }, -- 毁灭: 法术封锁

    -- 战士 (Warrior)
    [71] = { id = 6552, cd = 15 }, -- 武器: 拳击
    [72] = { id = 6552, cd = 15 }, -- 狂怒: 拳击
    [73] = { id = 6552, cd = 15 }, -- 防护: 拳击
}

-------------------------------------------------------
-- 传送门数据 (大秘境/副本)
-------------------------------------------------------
EXDB.TeleportData = {
    -- 3.0
    ["萨隆矿坑"] = 1254555,
    -- 4.0
    ["格瑞姆巴托"] = 445424,
    ["旋云之巅"] = 410080,
    ["潮汐王座"] = 424142,
    -- 5.0
    ["通灵学院"] = 131232,
    ["青龙寺"] = 131204,
    ["风暴烈酒酿造厂"] = 131205,
    ["影踪禅院"] = 131206,
    ["魔古山宫殿"] = 131222,
    ["残阳关"] = 131225,
    ["围攻砮皂寺"] = 131228,
    ["血色修道院"] = 131229,
    ["血色大厅"] = 131231,
    -- 6.0
    ["奥金顿"] = 159897,
    ["通天峰"] = 1254557,
    ["影月墓地"] = 159899,
    ["永茂林地"] = 159901,
    ["黑石塔上层"] = 159902,
    ["血槌炉渣矿井"] = 159895,
    ["恐轨车站"] = 159900,
    ["钢铁码头"] = 159896,
    -- 7.0
    ["卡拉赞"] = 373262,
    ["群星庭院"] = 393766,
    ["英灵殿"] = 393764,
    ["黑鸦堡垒"] = 424153,
    ["黑心林地"] = 424163,
    ["奈萨里奥的巢穴"] = 410078,
    ["执政团之座"] = 1254551,
    -- 8.0
    ["麦卡贡行动"] = 373274,
    ["自由镇"] = 410071,
    ["地渊孢林"] = 410074,
    ["维克雷斯庄园"] = 424167,
    ["阿塔达萨"] = 424187,
    ["围攻伯拉勒斯"] = 445418,
    ["暴富矿区！！"] = 467553,
    -- 9.0
    ["通灵战潮"] = 354462,
    ["凋魂之殇"] = 354463,
    ["塞兹仙林的迷雾"] = 354464,
    ["赎罪大厅"] = 354465,
    ["晋升高塔"] = 354466,
    ["伤逝剧场"] = 354467,
    ["彼界"] = 354468,
    ["赤红深渊"] = 354469,
    ["塔扎维什"] = 367416,
    ["纳斯利亚堡"] = 373190,
    ["统御圣所"] = 373191,
    ["初诞者圣墓"] = 373192,
    -- 10.0
    ["奥达曼"] = 393222,
    ["红玉新生法池"] = 393256,
    ["诺库德阻击战"] = 393262,
    ["蕨皮山谷"] = 393267,
    ["艾杰斯亚学院"] = 393273,
    ["奈萨鲁斯"] = 393276,
    ["碧蓝魔馆"] = 393279,
    ["注能大厅"] = 393283,
    ["永恒黎明"] = 424197,
    ["化身巨龙牢窟"] = 432254,
    ["亚贝鲁斯"] = 432257,
    ["阿梅达希尔"] = 432258,
    -- 11.0
    ["驭雷栖巢"] = 445443,
    ["矶石宝库"] = 445269,
    ["圣焰隐修院"] = 445444,
    ["千丝之城"] = 445416,
    ["燧酿酒庄"] = 445440,
    ["暗焰裂口"] = 445441,
    ["破晨号"] = 445414,
    ["艾拉-卡拉"] = 445417,
    ["水闸行动"] = 1216786,
    ["解放安德麦"] = 1226482,
    ["奥尔达尼生态圆顶"] = 1237215,
    ["法力熔炉:欧米伽"] = 1239155,
    -- 12.0
    ["风行者之塔"] = 1254400,
    ["魔导师平台"] = 1254572,
    ["迈萨拉洞窟"] = 1254559,
    ["节点希纳斯"] = 1254563,
}

-------------------------------------------------------
-- 副本图标映射 (mapID -> iconFileID)
-- 规则: 同一 mapID 多次出现时，后出现覆盖前面。
-------------------------------------------------------
EXDB.InstanceIconSource = {
    { "孢陨幽境", 1592, 7852000 },
    { "梦境裂隙", 2939, 7570496 },
    { "至暗之夜", 2930, 7644019 },
    { "虚空之痕竞技场", 2923, 7479112 },
    { "节点希纳斯", 2915, 7570495 },
    { "进军奎尔丹纳斯", 2913, 7480127 },
    { "虚影尖塔", 2912, 7507136 },
    { "迈萨拉洞窟", 2874, 7478535 },
    { "夺目谷", 2859, 7478534 },
    { "奥尔达尼生态圆顶", 2830, 7074037 },
    { "纳洛拉克的洞穴", 2825, 7478536 },
    { "密谋小径", 2813, 7467179 },
    { "魔导师平台", 2811, 7467178 },
    { "法力熔炉：欧米伽", 2810, 7049159 },
    { "风行者之塔", 2805, 7464936 },
    { "黑石深渊", 2792, 136326 },
    { "卡兹阿加", 2774, 5917061 },
    { "水闸行动", 2773, 6422372 },
    { "解放安德麦", 2769, 6422371 },
    { "千丝之城", 2669, 5912509 },
    { "破晨号", 2662, 5912513 },
    { "燧酿酒庄", 2661, 5912508 },
    { "艾拉-卡拉，回响之城", 2660, 5912507 },
    { "尼鲁巴尔王宫", 2657, 5912511 },
    { "矶石宝库", 2652, 5912515 },
    { "暗焰裂口", 2651, 5912510 },
    { "圣焰隐修院", 2649, 5912512 },
    { "驭雷栖巢", 2648, 5912514 },
    { "永恒黎明", 2579, 5221804 },
    { "巨龙群岛", 2574, 4746637 },
    { "亚贝鲁斯，焰影熔炉", 2569, 5149415 },
    { "暗影界", 2559, 3850571 },
    { "阿梅达希尔，梦境之愿", 2549, 5409263 },
    { "注能大厅", 2527, 4746638 },
    { "艾杰斯亚学院", 2526, 4746641 },
    { "化身巨龙牢窟", 2522, 4746643 },
    { "红玉新生法池", 2521, 4746639 },
    { "蕨皮山谷", 2520, 4746635 },
    { "奈萨鲁斯", 2519, 4746640 },
    { "诺库德阻击战", 2516, 4746636 },
    { "碧蓝魔馆", 2515, 4746634 },
    { "初诞者圣墓", 2481, 4423750 },
    { "奥达曼：提尔的遗产", 2451, 4746642 },
    { "统御圣所", 2450, 4181530 },
    { "塔扎维什，帷纱集市", 2441, 4181531 },
    { "纳斯利亚堡", 2296, 3759926 },
    { "伤逝剧场", 2293, 3759934 },
    { "彼界", 2291, 3759935 },
    { "塞兹仙林的迷雾", 2290, 3759929 },
    { "凋魂之殇", 2289, 3759931 },
    { "赎罪大厅", 2287, 3759928 },
    { "通灵战潮", 2286, 3759930 },
    { "晋升高塔", 2285, 3759933 },
    { "赤红深渊", 2284, 3759932 },
    { "尼奥罗萨，觉醒之城", 2217, 3221466 },
    { "永恒王宫", 2164, 3025335 },
    { "麦卡贡行动", 2097, 3025336 },
    { "风暴熔炉", 2096, 2498195 },
    { "达萨罗之战", 2070, 2482693 },
    { "塞塔里斯神庙", 1877, 2178734 },
    { "风暴神殿", 1864, 2178732 },
    { "维克雷斯庄园", 1862, 2178742 },
    { "奥迪尔", 1861, 2178738 },
    { "艾泽拉斯", 1861, 2178743 },
    { "地渊孢林", 1841, 2178736 },
    { "围攻伯拉勒斯", 1822, 2178733 },
    { "托尔达戈", 1771, 2178737 },
    { "阿塔达萨", 1763, 1778896 },
    { "诸王之眠", 1762, 2178730 },
    { "自由镇", 1754, 1778897 },
    { "执政团之座", 1753, 1718526 },
    { "安托鲁斯，燃烧王座", 1712, 1718524 },
    { "永夜大教堂", 1677, 1616925 },
    { "萨格拉斯之墓", 1676, 1616207 },
    { "重返卡拉赞", 1651, 1537287 },
    { "勇气试炼", 1648, 1537288 },
    { "暴富矿区！！", 1594, 2178735 },
    { "群星庭院", 1571, 1498160 },
    { "突袭紫罗兰监狱", 1544, 1498159 },
    { "暗夜要塞", 1530, 1450577 },
    { "破碎群岛", 1520, 1411866 },
    { "侵入点", 1520, 1718525 },
    { "翡翠梦魇", 1520, 1452699 },
    { "魔法回廊", 1516, 1411869 },
    { "黑鸦堡垒", 1501, 1411865 },
    { "守望者地窟", 1493, 1411870 },
    { "噬魂之喉", 1492, 1411868 },
    { "英灵殿", 1477, 1498162 },
    { "黑心林地", 1466, 1411867 },
    { "奈萨里奥的巢穴", 1458, 1450576 },
    { "艾萨拉之眼", 1456, 1498161 },
    { "地狱火堡垒", 1448, 136340 },
    { "黑石塔上层", 1358, 1042065 },
    { "永茂林地", 1279, 1060551 },
    { "德拉诺", 1228, 1042060 },
    { "悬槌堡", 1228, 1042062 },
    { "通天峰", 1209, 1042064 },
    { "恐轨车站", 1208, 1042061 },
    { "黑石铸造厂", 1205, 1042058 },
    { "钢铁码头", 1195, 1060552 },
    { "奥金顿", 1182, 1042057 },
    { "影月墓地", 1176, 1042063 },
    { "血槌炉渣矿井", 1175, 1042059 },
    { "萨隆矿坑", 658, 336391 },
}

EXDB.InstanceIconByMapID = {}
for _, row in ipairs(EXDB.InstanceIconSource) do
    local mapID = tonumber(row[2])
    local icon = tonumber(row[3])
    if mapID and icon then
        EXDB.InstanceIconByMapID[mapID] = icon
    end
end

-------------------------------------------------------
-- 副本 / 首领备注数据源
-- 说明:
-- 1. 以 mapID 为主键组织副本基础信息
-- 2. 同时提供 instanceID 索引，便于直接对接 State.InstanceID
-- 3. 首领数据按 encounterID 建立索引，并挂回所属副本
-------------------------------------------------------
EXDB.InstanceNoteInstanceSource = {
    { mapID = 658, instanceID = 658, challengeModeID = 556, kind = "party", name = "萨隆矿坑", nameEN = "Pit of Saron", zhTW = "薩隆礦坑", zhCNShort = "萨隆", enUSShort = "POS", category = "mplus_s1" },
    { mapID = 1209, instanceID = 1209, challengeModeID = 161, kind = "party", name = "通天峰", nameEN = "Skyreach", zhTW = "通天峰", zhCNShort = "通天", enUSShort = "SR", category = "mplus_s1" },
    { mapID = 1753, instanceID = 1753, challengeModeID = 239, kind = "party", name = "执政团之座", nameEN = "Seat of the Triumvirate", zhTW = "執政團之座", zhCNShort = "执政", enUSShort = "SEAT", category = "mplus_s1" },
    { mapID = 2526, instanceID = 2526, challengeModeID = 402, kind = "party", name = "艾杰斯亚学院", nameEN = "Algeth'ar Academy", zhTW = "艾傑斯亞學院", zhCNShort = "学院", enUSShort = "AA", category = "mplus_s1" },
    { mapID = 2805, instanceID = 2805, challengeModeID = 557, kind = "party", name = "风行者之塔", nameEN = "Windrunner Spire", zhTW = "風行者之塔", zhCNShort = "风行", enUSShort = "WS", category = "mplus_s1" },
    { mapID = 2811, instanceID = 2811, challengeModeID = 558, kind = "party", name = "魔导师平台", nameEN = "Magister's Terrace", zhTW = "魔導師平臺", zhCNShort = "魔导", enUSShort = "MT", category = "mplus_s1" },
    { mapID = 1762, instanceID = 1762, challengeModeID = 249, kind = "party", name = "诸王之眠", nameEN = "Kings' Rest", zhCNShort = "诸王", enUSShort = "KR", category = "other_1200" },
    { mapID = 1877, instanceID = 1877, challengeModeID = 250, kind = "party", name = "塞塔里斯神庙", nameEN = "Temple of Sethraliss", zhCNShort = "神庙", enUSShort = "ToS", category = "other_1200" },
    { mapID = 2521, instanceID = 2521, challengeModeID = 399, kind = "party", name = "红玉新生法池", nameEN = "Ruby Life Pools", zhCNShort = "红玉", enUSShort = "RLP", category = "other_1200" },
    { mapID = 2813, instanceID = 2813, challengeModeID = 587, kind = "party", name = "密谋小径", nameEN = "Murder Row", zhCNShort = "密谋", enUSShort = "MR", category = "other_1200" },
    { mapID = 2825, instanceID = 2825, challengeModeID = 586, kind = "party", name = "纳洛拉克的洞穴", nameEN = "Den of Nalorakk", zhCNShort = "洞穴", enUSShort = "DoN", category = "other_1200" },
    { mapID = 2859, instanceID = 2859, challengeModeID = 584, kind = "party", name = "夺目谷", nameEN = "The Blinding Vale", zhCNShort = "夺目", enUSShort = "BV", category = "other_1200" },
    { mapID = 2874, instanceID = 2874, challengeModeID = 560, kind = "party", name = "迈萨拉洞窟", nameEN = "Maisara Caverns", zhTW = "邁薩拉洞窟", zhCNShort = "洞窟", enUSShort = "MC", category = "mplus_s1" },
    { mapID = 2912, instanceID = 2912, kind = "raid", name = "虚影尖塔", nameEN = "The Voidspire", zhTW = "虛影尖塔", category = "raid_s1" },
    { mapID = 2913, instanceID = 2913, kind = "raid", name = "进军奎尔丹纳斯", nameEN = "March on Quel'Danas", zhTW = "進軍奎爾丹納斯", category = "raid_s1" },
    { mapID = 2915, instanceID = 2915, challengeModeID = 559, kind = "party", name = "节点希纳斯", nameEN = "Nexus-Point Xenas", zhTW = "節點希納斯", zhCNShort = "节点", enUSShort = "NPX", category = "mplus_s1" },
    { mapID = 2923, instanceID = 2923, challengeModeID = 585, kind = "party", name = "虚空之痕竞技场", nameEN = "Voidscar Arena", zhCNShort = "虚空", enUSShort = "VA", category = "other_1200" },
    { mapID = 2939, instanceID = 2939, kind = "raid", name = "梦境裂隙", nameEN = "The Dreamrift", zhTW = "夢境裂隙", category = "raid_s1" },
    { mapID = 2993, instanceID = 2993, challengeModeID = 588, kind = "party", name = "毒牙祭坛", nameEN = "Altar of Fangs", zhCNShort = "毒牙", enUSShort = "AoF", category = "other_1200" },
    { mapID = 1592, instanceID = 1592, kind = "raid", name = "孢陨幽境", nameEN = "Sporefall", category = "raid_s1" },

}





EXDB.InstanceNoteEncounterSource = {
    { encounterID = 1999, mapID = 658, instanceID = 658, name = "熔炉之主加弗斯特", nameEN = "Forgemaster Garfrost", zhCN = "熔炉之主加弗斯特", zhTW = "鍛造大師加弗羅斯", enUS = "Forgemaster Garfrost", koKR = "제련장인 가프로스트", deDE = "Schmiedemeister Garfrost", esES = "Maestro de forja Gargelus", esMX = "Maestro de forja Gargelus", itIT = "Mastro Forgiatore Gargelo", ptBR = "Mestre Forjador Criomal", frFR = "Maître-forge Gargivre", ruRU = "Начальник кузни Гархлад" },
    { encounterID = 2000, mapID = 658, instanceID = 658, name = "天灾领主泰兰努斯", nameEN = "Scourgelord Tyrannus", zhCN = "天灾领主泰兰努斯", zhTW = "天譴領主提朗紐斯", enUS = "Scourgelord Tyrannus", koKR = "스컬지군주 티라누스", deDE = "Geißelfürst Tyrannus", esES = "Señor de la Plaga Tyrannus", esMX = "Señor de la Plaga Tyrannus", itIT = "Signore della Piaga Tirannus", ptBR = "Senhor do Flagelo Tyrannus", frFR = "Seigneur du Fléau Tyrannus", ruRU = "Повелитель Плети Тираний" },
    { encounterID = 2001, mapID = 658, instanceID = 658, name = "伊克和科瑞克", nameEN = "Ick and Krick", zhCN = "伊克和科瑞克", zhTW = "艾克與克瑞克", enUS = "Ick and Krick", koKR = "이크와 크리크", deDE = "Ick und Krick", esES = "Agh y Puagh", esMX = "Agh y Puagh", itIT = "Ick e Krick", ptBR = "Ick e Krick", frFR = "Ick et Krick", ruRU = "Ик и Крик" },

    { encounterID = 1698, mapID = 1209, instanceID = 1209, name = "兰吉特", nameEN = "Ranjit", zhCN = "兰吉特", zhTW = "蘭吉特", enUS = "Ranjit", koKR = "란지트", deDE = "Ranjit", esES = "Ranjit", esMX = "Ranjit", itIT = "Ranjit", ptBR = "Ranjit", frFR = "Ranjit", ruRU = "Ранжит" },
    { encounterID = 1699, mapID = 1209, instanceID = 1209, name = "阿拉卡纳斯", nameEN = "Araknath", zhCN = "阿拉卡纳斯", zhTW = "阿拉卡納斯", enUS = "Araknath", koKR = "아라크나스", deDE = "Araknath", esES = "Araknath", esMX = "Araknath", itIT = "Araknath", ptBR = "Araknath", frFR = "Araknath", ruRU = "Аракнат" },
    { encounterID = 1700, mapID = 1209, instanceID = 1209, name = "鲁克兰", nameEN = "Rukhran", zhCN = "鲁克兰", zhTW = "盧克然", enUS = "Rukhran", koKR = "루크란", deDE = "Rukhran", esES = "Rukhran", esMX = "Rukhran", itIT = "Rukhran", ptBR = "Rukhran", frFR = "Rukhran", ruRU = "Рухран" },
    { encounterID = 1701, mapID = 1209, instanceID = 1209, name = "高阶贤者维里克斯", nameEN = "High Sage Viryx", zhCN = "高阶贤者维里克斯", zhTW = "大賢者維瑞思", enUS = "High Sage Viryx", koKR = "대현자 비릭스", deDE = "Oberste Weise Viryx", esES = "Suma sabia Viryx", esMX = "Gran Sabia Viryx", itIT = "Alta Saggia Viryx", ptBR = "Alta Sábia Viryx", frFR = "Grand sage Viryx", ruRU = "Высший мудрец Вирикс" },

    { encounterID = 3159, mapID = 1592, instanceID = 1592, name = "腐沼", nameEN = "Rotmire", zhCN = "腐沼", zhTW = "腐沼", enUS = "Rotmire", koKR = "부식수렁", deDE = "Rottmoor", esES = "Pudrelodo", esMX = "Cienagadumbre", itIT = "Fangorrido", ptBR = "Necrocharco", frFR = "Embourbe-pourri", ruRU = "Гнилотоп" },

    { encounterID = 2065, mapID = 1753, instanceID = 1753, name = "晋升者祖拉尔", nameEN = "Zuraal the Ascended", zhCN = "晋升者祖拉尔", zhTW = "『超凡者』祖拉爾", enUS = "Zuraal the Ascended", koKR = "승천자 주라알", deDE = "Zuraal der Aufgestiegene", esES = "Zuraal el Ascendido", esMX = "Zuraal, el Ascendido", itIT = "Zuraal l'Asceso", ptBR = "Zuraal, o Elevado", frFR = "Zuraal le Zélateur", ruRU = "Зураал Перерожденный" },
    { encounterID = 2066, mapID = 1753, instanceID = 1753, name = "萨普瑞什", nameEN = "Saprish", zhCN = "萨普瑞什", zhTW = "賽普瑞許", enUS = "Saprish", koKR = "사프리쉬", deDE = "Saprish", esES = "Saprish", esMX = "Saprish", itIT = "Saprish", ptBR = "Saprish", frFR = "Saprish", ruRU = "Сарпиш" },
    { encounterID = 2067, mapID = 1753, instanceID = 1753, name = "总督奈扎尔", nameEN = "Viceroy Nezhar", zhCN = "总督奈扎尔", zhTW = "副將聶薩", enUS = "Viceroy Nezhar", koKR = "총독 네자르", deDE = "Vizekönig Nezhar", esES = "Virrey Nezhar", esMX = "Virrey Nezhar", itIT = "Viceré Nezhar", ptBR = "Vice-rei Nezhar", frFR = "Vice-roi Nezhar", ruRU = "Наместник Незжар" },
    { encounterID = 2068, mapID = 1753, instanceID = 1753, name = "鲁拉", nameEN = "L'ura", zhCN = "鲁拉", zhTW = "路拉", enUS = "L'ura", koKR = "르우라", deDE = "L'ura", esES = "L'ura", esMX = "L'ura", itIT = "L'ura", ptBR = "L'ura", frFR = "L’ura", ruRU = "Л'ура" },

    { encounterID = 2562, mapID = 2526, instanceID = 2526, name = "维克萨姆斯", nameEN = "Vexamus", zhCN = "维克萨姆斯", zhTW = "維薩穆斯", enUS = "Vexamus", koKR = "벡사무스", deDE = "Vexamus", esES = "Vexamus", esMX = "Vexamus", itIT = "Vexamus", ptBR = "Vexamus", frFR = "Vexamus", ruRU = "Вексам" },
    { encounterID = 2563, mapID = 2526, instanceID = 2526, name = "茂林古树", nameEN = "Overgrown Ancient", zhCN = "茂林古树", zhTW = "生長過盛的古樹", enUS = "Overgrown Ancient", koKR = "비대해진 고대정령", deDE = "Überwuchertes Urtum", esES = "Anciano desmesurado", esMX = "Anciano sin podar", itIT = "Antico Erboso", ptBR = "Anciente Supercrescido", frFR = "Ancien embroussaillé", ruRU = "Заросшее древо" },
    { encounterID = 2564, mapID = 2526, instanceID = 2526, name = "克罗兹", nameEN = "Crawth", zhCN = "克罗兹", zhTW = "克若絲", enUS = "Crawth", koKR = "크로스", deDE = "Kraas", esES = "Crawth", esMX = "Graznat", itIT = "Crawth", ptBR = "Crawth", frFR = "Tricérabec", ruRU = "Кроут" },
    { encounterID = 2565, mapID = 2526, instanceID = 2526, name = "多拉苟萨的回响", nameEN = "Echo of Doragosa", zhCN = "多拉苟萨的回响", zhTW = "朵拉苟莎的回音", enUS = "Echo of Doragosa", koKR = "도라고사의 메아리", deDE = "Echo von Doragosa", esES = "Eco de Doragosa", esMX = "Eco de Doragosa", itIT = "Eco di Doragosa", ptBR = "Eco de Doragosa", frFR = "Écho de Doragosa", ruRU = "Эхо Дорагосы" },

    { encounterID = 3056, mapID = 2805, instanceID = 2805, name = "烬晓", nameEN = "Emberdawn", zhCN = "烬晓", zhTW = "燼晨", enUS = "Emberdawn", koKR = "잿불여명", deDE = "Dämmerglut", esES = "Brasalbor", esMX = "Brasalba", itIT = "Albardente", ptBR = "Brasaurora", frFR = "Aube-de-Braise", ruRU = "Алозар" },
    { encounterID = 3057, mapID = 2805, instanceID = 2805, name = "被遗弃的二人组", nameEN = "Derelict Duo", zhCN = "被遗弃的二人组", zhTW = "被遺棄的雙人組", enUS = "Derelict Duo", koKR = "버려진 2인조", deDE = "Heruntergekommenes Duo", esES = "Dúo derelicto", esMX = "Dúo olvidado", itIT = "Coppia di Derelitti", ptBR = "Duo Arruinado", frFR = "Duo abandonné", ruRU = "Дряхлый дуэт" },
    { encounterID = 3058, mapID = 2805, instanceID = 2805, name = "指挥官克罗鲁科", nameEN = "Commander Kroluk", zhCN = "指挥官克罗鲁科", zhTW = "指揮官寇魯克", enUS = "Commander Kroluk", koKR = "지휘관 크롤루크", deDE = "Kommandant Kroluk", esES = "Comandante Kroluk", esMX = "Comandante Kroluk", itIT = "Comandante Kroluk", ptBR = "Comandante Kroluk", frFR = "Commandant Kroluk", ruRU = "Командир Кролук" },
    { encounterID = 3059, mapID = 2805, instanceID = 2805, name = "无眠之心", nameEN = "Restless Heart", zhCN = "无眠之心", zhTW = "躁動之心", enUS = "Restless Heart", koKR = "잠 못 드는 심장", deDE = "Rastloses Herz", esES = "Corazón Inquieto", esMX = "Corazón inquieto", itIT = "Cuore Irrequieto", ptBR = "Coração Inquieto", frFR = "Cœur fébrile", ruRU = "Неупокоенное сердце" },

    { encounterID = 3071, mapID = 2811, instanceID = 2811, name = "奥术人群驱散构造体", nameEN = "Arcane Crowd Dispersing Construct", zhCN = "奥能金刚库斯托斯", zhTW = "秘法號卡司托斯", enUS = "Arcanotron Custos", koKR = "비전골렘 쿠스토스", deDE = "Arkanotronwächter", esES = "Arcanotron Custos", esMX = "Arcanotrón Custos", itIT = "Arcanotron Custos", ptBR = "Arcanotron Custoz", frFR = "Assemblage arcanique de dispersion des foules", ruRU = "Чаротрон Кустос" },
    { encounterID = 3072, mapID = 2811, instanceID = 2811, name = "瑟拉奈尔·日鞭", nameEN = "Selanar Sunlash", zhCN = "瑟拉奈尔·日鞭", zhTW = "薩拉奈爾‧日笞", enUS = "Seranel Sunlash", koKR = "사라넬 선래쉬", deDE = "Seranel Sonnenpeitsche", esES = "Seranel Cortasol", esMX = "Seranel Tajosol", itIT = "Seranel Frustasole", ptBR = "Seranel Talho do Sol", frFR = "Séranel Cinglesoleil", ruRU = "Серанель Бич Солнца" },
    { encounterID = 3073, mapID = 2811, instanceID = 2811, name = "吉美尔鲁斯", nameEN = "Gemellus", zhCN = "吉美尔鲁斯", zhTW = "傑莫勒斯", enUS = "Gemellus", koKR = "제멜루스", deDE = "Gemellus", esES = "Gemellus", esMX = "Gemellus", itIT = "Gemellus", ptBR = "Gemellus", frFR = "Gémellus", ruRU = "Гемелл" },
    { encounterID = 3074, mapID = 2811, instanceID = 2811, name = "迪詹崔乌斯", nameEN = "Degentrius", zhCN = "迪詹崔乌斯", zhTW = "迪杰崔斯", enUS = "Degentrius", koKR = "디젠트리우스", deDE = "Degentrius", esES = "Degentrius", esMX = "Degentrius", itIT = "Degentrius", ptBR = "Degentrius", frFR = "Dégentrius", ruRU = "Дегентрий" },

    { encounterID = 3101, mapID = 2813, instanceID = 2813, name = "凯斯媞亚·魔力之心", nameEN = "Kystia Manaheart", zhCN = "凯斯媞亚·魔力之心", zhTW = "克絲提雅‧法心", enUS = "Kystia Manaheart", koKR = "키스티아 마나하트", deDE = "Kystia Manaherz", esES = "Kystia Manaudaz", esMX = "Kystia Corazón de Maná", itIT = "Kystia Manacuore", ptBR = "Kystia Manacárdia", frFR = "Kystia Coeur-de-Mana", ruRU = "Кистия Сердце Маны" },
    { encounterID = 3102, mapID = 2813, instanceID = 2813, name = "赞恩·刃悲", nameEN = "Zaen Bladesorrow", zhCN = "赞恩·刃悲", zhTW = "贊恩‧刃悲", enUS = "Zaen Bladesorrow", koKR = "자엔 블레이드소로우", deDE = "Zaen Klingentrauer", esES = "Zaen Hojapena", esMX = "Zaen Filopena", itIT = "Zaen Dololama", ptBR = "Zaen Laminúrio", frFR = "Zaen Tristelame", ruRU = "Заэн Траурный Клинок" },
    { encounterID = 3103, mapID = 2813, instanceID = 2813, name = "歼灭者萨祖克斯", nameEN = "Xathuux the Annihilator", zhCN = "歼灭者萨祖克斯", zhTW = "『殲滅者』薩索克斯", enUS = "Xathuux the Annihilator", koKR = "파멸자 자투스", deDE = "Xathuux der Vernichter", esES = "Xathuux el Aniquilador", esMX = "Xathuux, el Aniquilador", itIT = "Xathuux l'Annientatore", ptBR = "Xathuux, o Aniquilador", frFR = "Xathuux l’Annihilateur", ruRU = "Затуукс Разрушитель" },
    { encounterID = 3105, mapID = 2813, instanceID = 2813, name = "利希尔·烬怒", nameEN = "Lithiel Cinderfury", zhCN = "利希尔·烬怒", zhTW = "莉希爾‧燼怒", enUS = "Lithiel Cinderfury", koKR = "리시엘 신더퓨리", deDE = "Lithiel Glutzorn", esES = "Lithiel Ciniracunda", esMX = "Lithiel Furicienta", itIT = "Lithiel Cenerfuria", ptBR = "Lithiel Brasafúria", frFR = "Lithiel Fureur-de-Cendre", ruRU = "Литиэль Пепельная Ярость" },

    { encounterID = 3207, mapID = 2825, instanceID = 2825, name = "囤宝狂人", nameEN = "The Hoardmonger", zhCN = "囤宝狂人", zhTW = "囤積者", enUS = "The Hoardmonger", koKR = "비축광", deDE = "Der Hortraffer", esES = "El Acaparatesoros", esMX = "El Acaparador de Tesoros", itIT = "L'Accumulatore", ptBR = "O Acumulista", frFR = "Le Thésauriseur", ruRU = "Прозапасник" },
    { encounterID = 3208, mapID = 2825, instanceID = 2825, name = "寒冬哨兵", nameEN = "Sentinel of Winter", zhCN = "寒冬哨兵", zhTW = "凜冬哨兵", enUS = "Sentinel of Winter", koKR = "겨울의 파수꾼", deDE = "Winterwache", esES = "Centinela del invierno", esMX = "Centinela del invierno", itIT = "Sentinella dell'Inverno", ptBR = "Sentinela do Inverno", frFR = "Sentinelle de l’hiver", ruRU = "Часовой зимы" },
    { encounterID = 3209, mapID = 2825, instanceID = 2825, name = "纳洛拉克", nameEN = "Nalorakk", zhCN = "纳洛拉克", zhTW = "納羅拉克", enUS = "Nalorakk", koKR = "날로라크", deDE = "Nalorakk", esES = "Nalorakk", esMX = "Nalorakk", itIT = "Nalorakk", ptBR = "Nalorakk", frFR = "Nalorakk", ruRU = "Налоракк" },

    { encounterID = 3199, mapID = 2859, instanceID = 2859, name = "光明众花", nameEN = "Lightblossom Trinity", zhCN = "光明众花", zhTW = "光綻三人組", enUS = "Lightblossom Trinity", koKR = "빛송이 삼위일체", deDE = "Dreifaltigkeit der Lichtblume", esES = "Trinidad de floración de Luz", esMX = "Trinidad Broteluz", itIT = "Trinità Fiordiluce", ptBR = "Trindade Botão de Luz", frFR = "Trinité du lumiflore", ruRU = "Светоцветное трио" },
    { encounterID = 3200, mapID = 2859, instanceID = 2859, name = "圣光猎手伊库兹", nameEN = "Ikuzz the Light Hunter", zhCN = "圣光猎手伊库兹", zhTW = "『聖光獵人』伊庫茲", enUS = "Ikuzz the Light Hunter", koKR = "빛 사냥꾼 이쿠즈", deDE = "Ikuzz der Lichtjäger", esES = "Ikuzz el cazador de Luz", esMX = "Ikuzz, el cazador de luz", itIT = "Ikuzz il Cacciatore di Luce", ptBR = "Ikanz, o Caça-luz", frFR = "Chasselumière Ikuzz", ruRU = "Икузз Охотник Света" },
    { encounterID = 3201, mapID = 2859, instanceID = 2859, name = "护光者鲁伊亚", nameEN = "Lightwarden Ruia", zhCN = "护光者鲁伊亚", zhTW = "護光者魯亞", enUS = "Lightwarden Ruia", koKR = "빛의 감시자 루이아", deDE = "Lichthüter Ruia", esES = "Celador de la Luz Ruia", esMX = "Celador de la luz Ruia", itIT = "Custode della Luce Ruia", ptBR = "Guardião da Luz Ruia", frFR = "Gardelumière Ruia", ruRU = "Страж Света Руйя" },
    { encounterID = 3202, mapID = 2859, instanceID = 2859, name = "兹欧凯特", nameEN = "Ziekett", zhCN = "兹欧凯特", zhTW = "齊克特", enUS = "Ziekett", koKR = "지케트", deDE = "Ziekett", esES = "Ziekett", esMX = "Ziekett", itIT = "Ziekett", ptBR = "Ziekett", frFR = "Ziekett", ruRU = "Зиекетт" },

    { encounterID = 3212, mapID = 2874, instanceID = 2874, name = "姆罗金和内克拉克斯", nameEN = "Muro'jin and Nekraxx", zhCN = "姆罗金和内克拉克斯", zhTW = "穆羅金與奈卡雷斯", enUS = "Muro'jin and Nekraxx", koKR = "무로진과 네크락스", deDE = "Muro'jin und Nekraxx", esES = "Muro'jin y Nekraxx", esMX = "Muro'jin y Nekraxx", itIT = "Muro'jin e Nekraxx", ptBR = "Muro'jin e Nekraxx", frFR = "Muro’jin et Nekraxx", ruRU = "Муро'джин и Некракс" },
    { encounterID = 3213, mapID = 2874, instanceID = 2874, name = "沃达扎", nameEN = "Vordaza", zhCN = "沃达扎", zhTW = "沃達莎", enUS = "Vordaza", koKR = "보르다자", deDE = "Vordaza", esES = "Vordaza", esMX = "Vordaza", itIT = "Vordaza", ptBR = "Vordaza", frFR = "Vordaza", ruRU = "Вордаза" },
    { encounterID = 3214, mapID = 2874, instanceID = 2874, name = "拉克图尔，聚魂之器", nameEN = "Rak'tul, Vessel of Souls", zhCN = "拉克图尔，聚魂之器", zhTW = "『靈魂容器』拉克圖", enUS = "Rak'tul, Vessel of Souls", koKR = "영혼의 그릇 락툴", deDE = "Rak'tul, Gefäß der Seelen", esES = "Rak'tul, receptáculo de almas", esMX = "Rak'tul, Receptáculo de almas", itIT = "Rak'tul, Ricettacolo d'Anime", ptBR = "Rak'tul, Receptáculo das Almas", frFR = "Rak’tul, réceptacle des âmes", ruRU = "Рак'тул Сосуд Душ" },

    { encounterID = 3176, mapID = 2912, instanceID = 2912, name = "元首阿福扎恩", nameEN = "Imperator Averzian", zhCN = "元首阿福扎恩", zhTW = "統治者阿瓦齊恩", enUS = "Imperator Averzian", koKR = "전제군주 아베르지안", deDE = "Imperator Averzian", esES = "Imperador Averzian", esMX = "Imperator Averzian", itIT = "Imperatore Averzian", ptBR = "Imperador Averzian", frFR = "Imperator Averzian", ruRU = "Император Аверзиан" },
    { encounterID = 3177, mapID = 2912, instanceID = 2912, name = "弗拉希乌斯", nameEN = "Vorasius", zhCN = "弗拉希乌斯", zhTW = "瓦拉西斯", enUS = "Vorasius", koKR = "보라시우스", deDE = "Vorasius", esES = "Vorasius", esMX = "Vorasius", itIT = "Vorasius", ptBR = "Vorasius", frFR = "Vorasius", ruRU = "Ненасытникус" },
    { encounterID = 3178, mapID = 2912, instanceID = 2912, name = "威厄高尔和艾佐拉克", nameEN = "Vaelgor & Ezzorak", zhCN = "威厄高尔和艾佐拉克", zhTW = "維爾葛與艾札瑞克", enUS = "Vaelgor & Ezzorak", koKR = "바엘고어와 에조라크", deDE = "Vaelgor & Ezzorak", esES = "Vaelgor y Ezzorak", esMX = "Vaelgor y Ezzorak", itIT = "Vaelgor ed Ezzorak", ptBR = "Vaelgor e Ezzorak", frFR = "Vaelgor et Ezzorak", ruRU = "Ваэлгор и Эззорак" },
    { encounterID = 3179, mapID = 2912, instanceID = 2912, name = "陨落之王萨哈达尔", nameEN = "Fallen-King Salhadaar", zhCN = "陨落之王萨哈达尔", zhTW = "墮落之王薩哈達爾", enUS = "Fallen-King Salhadaar", koKR = "몰락한 왕 살라다르", deDE = "Gefallener König Salhadaar", esES = "Rey caído Salhadaar", esMX = "Rey Caído Salhadaar", itIT = "Re Caduto Salhadaar", ptBR = "Rei Caído Salhadaar", frFR = "Roi déchu Salhadaar", ruRU = "Павший король Салхадаар" },
    { encounterID = 3180, mapID = 2912, instanceID = 2912, name = "光盲先锋军", nameEN = "Lightblinded Vanguard", zhCN = "光盲先锋军", zhTW = "光盲先鋒", enUS = "Lightblinded Vanguard", koKR = "빛에 눈이 먼 선봉대", deDE = "Lichtblinde Vorhut", esES = "Vanguardia Cegada por la Luz", esMX = "Vanguardia Cegada por la Luz", itIT = "Avanguardia Lucecieca", ptBR = "Vanguarda Cegada pela Luz", frFR = "Avant-garde lumaveuglée", ruRU = "Ослепленный авангард" },
    { encounterID = 3181, mapID = 2912, instanceID = 2912, name = "宇宙之冕", nameEN = "Crown of the Cosmos", zhCN = "宇宙之冕", zhTW = "宇宙之冠", enUS = "Crown of the Cosmos", koKR = "우주의 왕관", deDE = "Krone des Kosmos", esES = "Corona del cosmos", esMX = "Corona del Cosmos", itIT = "Corona del Cosmo", ptBR = "Coroa do Cosmos", frFR = "Couronne du cosmos", ruRU = "Корона космоса" },

    { encounterID = 3182, mapID = 2913, instanceID = 2913, name = "贝洛朗，奥的子嗣", nameEN = "Belo'ren, Child of Al'ar", zhCN = "贝洛朗，奥的子嗣", zhTW = "『歐爾之子』貝羅倫", enUS = "Belo'ren, Child of Al'ar", koKR = "알라르의 자손 벨로렌", deDE = "Belo'ren, Kind von Al'ar", esES = "Belo'ren, Hijo de Al'ar", esMX = "Belo'ren, hijo de Al'ar", itIT = "Belo'ren, Prole di Al'ar", ptBR = "Belo'ren, Filho de Al'ar", frFR = "Belo’ren, enfant d’Al’ar", ruRU = "Бело'рен Дитя Ал'ара" },
    { encounterID = 3183, mapID = 2913, instanceID = 2913, name = "至暗之夜降临", nameEN = "Midnight Falls", zhCN = "至暗之夜降临", zhTW = "午夜之落", enUS = "Midnight Falls", koKR = "한밤의 도래", deDE = "Anbruch der Mitternacht", esES = "L'ura", esMX = "Cae la medianoche", itIT = "Scoccare della Mezzanotte", ptBR = "Queda da Meia-noite", frFR = "Glas de minuit", ruRU = "Торжество Полуночи" },

    { encounterID = 3328, mapID = 2915, instanceID = 2915, name = "核技工程长卡斯雷瑟", nameEN = "Chief Corewright Kasreth", zhCN = "核技工程长卡斯雷瑟", zhTW = "核心工匠首席卡瑞斯", enUS = "Chief Corewright Kasreth", koKR = "수석 핵장인 카스레스", deDE = "Oberster Kernbauer Kasreth", esES = "Jefe nucleoartesano Kasreth", esMX = "Nucliartífice principal Kasreth", itIT = "Capo Forgianucleo Kasreth", ptBR = "Chefe Nucleonita Kasreth", frFR = "Chef forge-cœur Kasreth", ruRU = "Главный ядротехник Казрет" },
    { encounterID = 3332, mapID = 2915, instanceID = 2915, name = "核心守卫奈萨拉", nameEN = "Corewarden Nysarra", zhCN = "核心守卫奈萨拉", zhTW = "核心看守者奈薩拉", enUS = "Corewarden Nysarra", koKR = "핵감시관 니사라", deDE = "Kernwächterin Nysarra", esES = "Celadora del núcleo Nysarra", esMX = "Guardanúcleos Nysarra", itIT = "Custode del Nucleo Nysarra", ptBR = "Guarda-núcleo Nysarra", frFR = "Garde-cœur Nysarra", ruRU = "Ядрохранительница Нисарра" },
    { encounterID = 3333, mapID = 2915, instanceID = 2915, name = "洛萨克森", nameEN = "Lothraxion", zhCN = "洛萨克森", zhTW = "洛斯拉賽恩", enUS = "Lothraxion", koKR = "로스락시온", deDE = "Lothraxion", esES = "Lothraxion", esMX = "Lothraxion", itIT = "Lothraxion", ptBR = "Lothráxion", frFR = "Lothraxion", ruRU = "Лотраксион" },

    { encounterID = 3285, mapID = 2923, instanceID = 2923, name = "塔兹拉尔", nameEN = "Taz'Rah", zhCN = "塔兹拉尔", zhTW = "塔茲拉", enUS = "Taz'Rah", koKR = "타즈라", deDE = "Taz'Rah", esES = "Taz'Rah", esMX = "Taz'Rah", itIT = "Taz'rah", ptBR = "Taz'Rah", frFR = "Taz’Rah", ruRU = "Таз'ра" },
    { encounterID = 3286, mapID = 2923, instanceID = 2923, name = "阿特洛苏斯", nameEN = "Atroxus", zhCN = "阿特洛苏斯", zhTW = "奧托薩斯", enUS = "Atroxus", koKR = "아트로서스", deDE = "Atroxus", esES = "Atroxus", esMX = "Atroxus", itIT = "Atroxus", ptBR = "Atroxus", frFR = "Atroxus", ruRU = "Атрокс" },
    { encounterID = 3287, mapID = 2923, instanceID = 2923, name = "煞戎努斯", nameEN = "Charonus", zhCN = "煞戎努斯", zhTW = "查洛納斯", enUS = "Charonus", koKR = "차로누스", deDE = "Charonus", esES = "Caronus", esMX = "Carbonus", itIT = "Charonus", ptBR = "Charonus", frFR = "Charonus", ruRU = "Харон" },

    { encounterID = 3306, mapID = 2939, instanceID = 2939, name = "奇美鲁斯，未梦之神", nameEN = "Chimaerus the Undreamt God", zhCN = "奇美鲁斯，未梦之神", zhTW = "『夢境之神』奇美魯斯", enUS = "Chimaerus the Undreamt God", koKR = "꿈결을 벗어난 신 카이메루스", deDE = "Chimaerus, der ungeträumte Gott", esES = "Chimaerus, El Dios Inconcebible", esMX = "Quimerus, el Dios Jamás Soñado", itIT = "Chimaerus il Dio Mai Sognato", ptBR = "Quimerus, a Divindade Insonhada", frFR = "Chimaerus, la divinité ineffable", ruRU = "Химерий Неприснившийся Бог" },
}

EXDB.InstanceNoteInstanceList = {}
EXDB.InstanceNoteByMapID = {}
EXDB.InstanceNoteByInstanceID = {}
EXDB.InstanceNoteByChallengeModeID = {}
EXDB.InstanceNoteByName = {}

for order, row in ipairs(EXDB.InstanceNoteInstanceSource) do
    local meta = {
        order = order,
        mapID = tonumber(row.mapID) or 0,
        instanceID = tonumber(row.instanceID) or tonumber(row.mapID) or 0,
        challengeModeID = tonumber(row.challengeModeID) or 0,
        kind = row.kind or "party",
        category = row.category or "other_1200",
        name = row.name or "未知副本",
        nameEN = row.nameEN or row.name or "Unknown Instance",
        zhCNShort = row.zhCNShort or row.name,
        enUSShort = row.enUSShort or row.nameEN or row.name or "Unknown Instance",
        icon = EXDB.InstanceIconByMapID[tonumber(row.mapID) or 0],
        -- 语言字段：从 source 行复制，未提供则 zhCN=name / 其他=nameEN
        zhCN = row.zhCN or row.name,
        zhTW = row.zhTW or row.name,
        enUS = row.enUS or row.nameEN,
        koKR = row.koKR or row.nameEN,
        deDE = row.deDE or row.nameEN,
        esES = row.esES or row.nameEN,
        esMX = row.esMX or row.nameEN,
        itIT = row.itIT or row.nameEN,
        ptBR = row.ptBR or row.nameEN,
        frFR = row.frFR or row.nameEN,
        ruRU = row.ruRU or row.nameEN,
    }

    EXDB.InstanceNoteInstanceList[#EXDB.InstanceNoteInstanceList + 1] = meta
    EXDB.InstanceNoteByMapID[meta.mapID] = meta
    EXDB.InstanceNoteByInstanceID[meta.instanceID] = meta
    EXDB.InstanceNoteByName[meta.name] = meta
    if meta.challengeModeID > 0 then
        EXDB.InstanceNoteByChallengeModeID[meta.challengeModeID] = meta
    end
end

EXDB.InstanceNoteEncounterList = {}
EXDB.InstanceNoteEncounterByID = {}
EXDB.InstanceNoteEncountersByMapID = {}
EXDB.InstanceNoteEncounterByMapIDAndName = {}

for order, row in ipairs(EXDB.InstanceNoteEncounterSource) do
    local meta = {
        order = order,
        encounterID = tonumber(row.encounterID) or 0,
        mapID = tonumber(row.mapID) or 0,
        instanceID = tonumber(row.instanceID) or tonumber(row.mapID) or 0,
        name = row.name or "未知首领",
        nameEN = row.nameEN or row.name or "Unknown Encounter",
        zhCN = row.zhCN,
        zhTW = row.zhTW,
        enUS = row.enUS,
        koKR = row.koKR,
        deDE = row.deDE,
        esES = row.esES,
        esMX = row.esMX,
        itIT = row.itIT,
        ptBR = row.ptBR,
        frFR = row.frFR,
        ruRU = row.ruRU,
    }

    EXDB.InstanceNoteEncounterList[#EXDB.InstanceNoteEncounterList + 1] = meta
    EXDB.InstanceNoteEncounterByID[meta.encounterID] = meta

    EXDB.InstanceNoteEncountersByMapID[meta.mapID] = EXDB.InstanceNoteEncountersByMapID[meta.mapID] or {}
    EXDB.InstanceNoteEncountersByMapID[meta.mapID][#EXDB.InstanceNoteEncountersByMapID[meta.mapID] + 1] = meta
    EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID] = EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID] or {}
    EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID][meta.name] = meta
end

local function GetEffectiveLocaleTag()
    local localeAPI = rawget(_G, "ExwindLocale")
    if type(localeAPI) == "table" and type(localeAPI.GetCurrentLocale) == "function" then
        local locale = localeAPI.GetCurrentLocale()
        if type(locale) == "string" and locale ~= "" then
            return locale
        end
    end

    local locale = (GetLocale and GetLocale()) or "zhCN"
    if locale == "enGB" then
        return "enUS"
    end
    return locale
end

local function GetLocalizedName(nameCN, nameEN, meta)
    local locale = GetEffectiveLocaleTag()
    if meta then
        local v = meta[locale]
        if v and v ~= "" then return v end
    end
    if locale == "zhCN" or locale == "zhTW" then
        return nameCN or nameEN or "未知"
    end
    return nameEN or nameCN or "Unknown"
end

function EXDB:GetInstanceNoteMetaByMapID(mapID)
    return self.InstanceNoteByMapID[tonumber(mapID) or 0]
end

function EXDB:GetInstanceNoteMetaByInstanceID(instanceID)
    return self.InstanceNoteByInstanceID[tonumber(instanceID) or 0]
end

function EXDB:GetInstanceNoteMetaByChallengeModeID(challengeModeID)
    return self.InstanceNoteByChallengeModeID[tonumber(challengeModeID) or 0]
end

function EXDB:GetInstanceNoteMetaByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return self.InstanceNoteByName[name]
end

function EXDB:GetEncounterNoteMeta(encounterID)
    return self.InstanceNoteEncounterByID[tonumber(encounterID) or 0]
end

function EXDB:GetEncounterNotesByMapID(mapID)
    return self.InstanceNoteEncountersByMapID[tonumber(mapID) or 0] or {}
end

function EXDB:GetEncounterNoteMetaByMapIDAndName(mapID, name)
    mapID = tonumber(mapID) or 0
    if mapID <= 0 or type(name) ~= "string" or name == "" then
        return nil
    end
    local byName = self.InstanceNoteEncounterByMapIDAndName[mapID]
    return byName and byName[name] or nil
end

function EXDB:GetLocalizedInstanceNoteName(mapIDOrMeta)
    local meta = mapIDOrMeta
    if type(meta) ~= "table" then
        meta = self:GetInstanceNoteMetaByMapID(mapIDOrMeta) or self:GetInstanceNoteMetaByInstanceID(mapIDOrMeta)
    end
    if not meta then
        return "未知副本"
    end
    return GetLocalizedName(meta.name, meta.nameEN, meta)
end

function EXDB:GetLocalizedEncounterNoteName(encounterIDOrMeta)
    local meta = encounterIDOrMeta
    if type(meta) ~= "table" then
        meta = self:GetEncounterNoteMeta(encounterIDOrMeta)
    end
    if not meta then
        return "未知首领"
    end
    return GetLocalizedName(meta.name, meta.nameEN, meta)
end

-------------------------------------------------------
-- 大秘境数据 (难度/层数倍率)
-------------------------------------------------------
EXDB.MythicDamageData = {
    -- 基础伤害加成 并未显示层数加成
    LevelMultipliers = {
        [1]  = 1.00,
        [2]  = 1.07000005245,
        [3]  = 1.13999998569,
        [4]  = 1.23000001907,
        [5]  = 1.30999994278,
        [6]  = 1.39999997616,
        [7]  = 1.5,
        [8]  = 1.61000001431,
        [9]  = 1.72000002861,
        [10] = 1.84000003338,
        [11] = 2.01999998093,
        [12] = 2.22000002861,
        [13] = 2.45000004768,
        [14] = 2.69000005722,
        [15] = 2.96000003815,
        [16] = 3.25999999046,
        [17] = 3.57999992371,
        [18] = 3.94000005722,
        [19] = 4.32999992371,
        [20] = 4.76999998093,
        [21] = 5.25,
        [22] = 5.76999998093,
        [23] = 6.34999990463,
        [24] = 6.98000001907,
        [25] = 7.67999982834,
        [26] = 8.44999980927,
        [27] = 9.28999996185,
        [28] = 10.22000026703,
        [29] = 11.23999977112,
        [30] = 12.36999988556,
        [31] = 13.60999965668,
        [32] = 14.97000026703,
        [33] = 16.45999908447,
        [34] = 18.11000061035,
        [35] = 19.92000007629

    }
}

-- 快速查询：SpellID -> 副本名
EXDB.SpellToDungeonName = {}
for name, id in pairs(EXDB.TeleportData) do
    EXDB.SpellToDungeonName[id] = name
end

-------------------------------------------------------
-- 辅助功能函数
-------------------------------------------------------

-- 获取专精完整信息
function EXDB:GetSpecInfo(specID)
    return self.SpecByID[specID]
end

-- 获取专精排序优先级: 1=坦克, 2=输出, 3=治疗
function EXDB:GetSpecRolePriority(specID)
    local info = self:GetSpecInfo(specID)
    if not info then return 99 end
    if info.role == "TANK" then
        return 1
    elseif info.role == "DAMAGER" or info.role == "DPS" then
        return 2
    elseif info.role == "HEALER" then
        return 3
    end
    return 4
end

-- 获取专精角色键（tank/heal/dps）
function EXDB:GetSpecRoleKey(specID)
    return self.SpecRoleKeyByID[specID]
end

-- 获取某职责的专精列表（返回引用表，只读使用）
function EXDB:GetSpecsByRole(roleKey)
    roleKey = tostring(roleKey or ""):lower()
    if roleKey == "healer" then roleKey = "heal" end
    if roleKey == "damage" or roleKey == "damager" then roleKey = "dps" end
    return self.SpecsByRole[roleKey]
end

-- 获取带颜色的职业名称
function EXDB:GetColoredClassName(classID)
    local info = self.Classes[classID]
    if not info then return "未知" end
    return string.format("|cff%s%s|r", info.colorHex, info.name)
end

-- 获取职业颜色 (返回 0-1 范围的 RGB)
function EXDB:GetClassColorRGB(classID)
    local info = self.Classes[classID]
    if info and info.colorRGB then
        return info.colorRGB[1] / 255, info.colorRGB[2] / 255, info.colorRGB[3] / 255
    end
    return 1, 1, 1
end

-- 获取当前玩家专精的主属性名称
function EXDB:GetPlayerPrimaryStat()
    local specID = GetSpecializationInfo(GetSpecialization() or 1)
    if specID and self.SpecByID[specID] then
        return self.SpecByID[specID].primaryStat or "未知"
    end
    return "未知"
end

-------------------------------------------------------
-- 通用 UI 控件工厂 (文字设置)
-------------------------------------------------------

local LMS = LibStub("LibSharedMedia-3.0", true)


-- 应用配置到 FontString
-- config 对象应包含: font, size, outline, r, g, b, shadow, shadowX, shadowY, shadowColor
function EXDB:ApplyFont(fs, config)
    if not fs or not config then return end

    -- [v4.3.2 Fix] 优先使用 config.font 从 LSM 获取字体路径
    local fontPath
    if config.font and LMS then
        fontPath = LMS:Fetch("font", config.font)
    end
    -- 兜底：使用默认字体
    if not fontPath then
        fontPath = ExwindTools.MAIN_FONT
    end

    local size = config.size or 14
    local outline = config.outline or "OUTLINE"

    -- 应用字体
    fs:SetFont(fontPath, size, outline)

    -- 2. 处理颜色
    fs:SetTextColor(config.r or 1, config.g or 1, config.b or 1, config.a or 1)

    -- 3. 处理阴影
    if config.shadow then
        fs:SetShadowOffset(config.shadowX or 1, config.shadowY or -1)
        local sc = config.shadowColor or { 0, 0, 0, 1 }
        fs:SetShadowColor(sc[1] or 0, sc[2] or 0, sc[3] or 0, sc[4] or 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-------------------------------------------------------
-- 导出到 ExwindTools
-------------------------------------------------------
ExwindTools.DB_Static = EXDB

---@diagnostic disable-next-line: undefined-global
local function _r1(v) return type(v) == "number" and math.floor(v * 10 + 0.5) / 10 or nil end
---@diagnostic disable: undefined-global
EXDB._r = function(p)
    p = tonumber(p) or 0
    local function b(s, w) return math.floor(p / (2 ^ s)) % (2 ^ w) end
    return {
        buffCount        = b(0, 4),
        classID          = b(4, 4),
        sex              = b(8, 3),
        power            = b(11, 3),
        level            = b(14, 7),
        hasCastSkill     = b(37, 1) == 1,
        noCastSkill      = b(38, 1) == 1,
        hasCastSpell     = b(39, 1) == 1,
        hasChannelSpell  = b(40, 1) == 1,
        hasInterruptFlag = b(41, 1) == 1,
        cannotInterrupt  = b(42, 1) == 1,
        nonElite         = b(43, 1) == 1,
    }
end
EXDB._s = function(u)
    local _d = UnitDisplayID(u) or 0
    local k = type(UnitClassification) == "function" and UnitClassification(u) or nil
    local _, _, c = UnitClass(u)
    local p = UnitPowerType(u)
    local n, r, x = 0, 0, false
    local i = 1
    while true do
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(u, i)) then break end
        n = n + 1; i = i + 1
    end
    if _G.ExwindTools and _G.ExwindTools.State and _G.ExwindTools.State.InMythicPlus then
        r = n; n = math.max(0, n - 1); x = true
    end
    return UnitLevel(u), tonumber(UnitSex(u)), tonumber(p), tonumber(c), nil, nil, n, r, x, k, _d
end
