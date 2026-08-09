---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.LabelCatalog = ExBoss.Voice.LabelCatalog or {}
local Catalog = ExBoss.Voice.LabelCatalog

local function LText(key)
    local L = ExBoss and ExBoss.L
    if L then
        return L[key]
    end
    return key
end

local function NormalizeStandardLabel(label, triggerIndex)
    label = tostring(label or "")
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then
        if tonumber(triggerIndex) == 2 then
            return "54321"
        end
        return nil
    end

    local lowered = label:lower()
    if label == "无" or lowered == "none" then
        if tonumber(triggerIndex) == 2 then
            return "54321"
        end
        return nil
    end
    return label
end

-- AUTO-GENERATED STANDARD LABELS START
local SCHEMA_STANDARD_LABELS = {
    "准备AOE",
    "准备引线",
    "准备打断",
    "准备拉人",
    "准备挡线",
    "准备接圈",
    "准备消层",
    "准备点名",
    "准备踩箭",
    "准备进圈",
    "准备连线",
    "准备送球",
    "准备钩人",
    "准备集合",
    "准备驱散",
    "去撞分身",
    "坦克尖刺",
    "快卡视角",
    "快去消水",
    "快找光柱",
    "快踩陷阱",
    "54321",
    "注意击退",
    "注意头前",
    "注意挡球",
    "注意消球",
    "注意躲避",
    "点名头前",
    "点名放水",
    "点名消线",
    "躲开头前",
    "转火小怪",
    "转阶段",
    "远离BOSS",
    "靠近分散",
    "风筝小怪",
    "Boss狂暴",
    "Boss易伤",
    "你是白色",
    "你是黑色",
    "准备AOE(断条)",
    "准备吸球",
    "出去放水",
    "去接小怪",
    "射线点你",
    "小心冲击波",
    "小心击飞",
    "强化奶骑",
    "强化惩戒骑",
    "强化防骑",
    "快分散",
    "快打断",
    "快救人",
    "快破盾",
    "快进罩子",
    "拉断连线",
    "易伤爆发",
    "注意减伤",
    "注意治疗",
    "特殊技能",
    "转火大怪",
    "远离大怪",
    "集合分摊",
    "5",
    "4",
    "3",
    "2",
    "1",
    "集合放圈",
    "控断钢条",
    "坦克击退",
    "召唤小怪",
    "注意点名",
    "注意躲圈",
    "注意击飞",
    "准备跑圈",
    "准备追人",
    "召唤分身",
    "AOE",
    "小心脚下",
    "连续躲圈",
    "准备抓人",
    "控制小怪",
    "瞄准音符",
    "唤醒小怪",
    "贴边放水",
    "靠近BOSS",
    "消除连线",
    "5秒后AOE",
    "补给协议",
    "超大AOE",
    "持续AOE",
    "打背面",
    "召唤大怪",
    "躲开冲锋",
    "躲球",
    "躲圈",
    "躲射线",
    "勾BOSS",
    "获得增益",
    "集合移动",
    "靠近连线",
    "快打宝珠",
    "快躲开",
    "快跑",
    "快跑！你被点名",
    "连线点你",
    "裂隙点你",
    "你被点名",
    "圈住电水",
    "停止施法",
    "吸收治疗",
    "小心炸弹",
    "小心自爆",
    "易伤结束",
    "音效_Glass",
    "音效_Info",
    "音效_叮咚",
    "远离人群",
    "注意躲风",
    "注意吐息",
    "准备易伤",
    "目标是你",
    "吸收盾",
    "注意大怪",
    "小怪快打",
    "注意箭矢",
    "远离",
    "引导位置",
    "注意射线",
    "黑色",
    "蓝色",
    "炸弹",
    "打破",
    "吐息",
    "注意控断",
    "锁链",
    "冲锋",
    "清除",
    "分身",
    "诅咒",
    "躲地板",
    "疾病",
    "驱散",
    "持续伤害",
    "放水",
    "激怒",
    "追人",
    "抓握",
    "注意钩人",
    "进入",
    "阶段转换",
    "打断施法",
    "风筝",
    "击飞",
    "跳跃",
    "连线",
    "卡视野",
    "点名",
    "移动",
    "靠近",
    "宝珠",
    "出出出",
    "传递",
    "刷新",
    "注意大圈",
    "定身",
    "救人",
    "护盾",
    "吸收",
    "进攻驱散",
    "分裂",
    "分散",
    "集合站位",
    "目标转换",
    "坦克承伤",
    "坦克击飞",
    "图腾",
    "陷阱",
    "易伤",
    "齐射",
    "注意躲波",
    "白色",
    "躲风",
    "黄色",
    "唤醒小怪(AOE)",
    "红色连线",
    "绿色连线",
}
-- AUTO-GENERATED STANDARD LABELS END

local function BuildFactoryDefaultLabels()
    local seen = {}
    local out = {}

    local function Add(label)
        label = tostring(label or "")
        label = label:gsub("^%s+", ""):gsub("%s+$", "")
        if label == "" or seen[label] then
            return
        end
        seen[label] = true
        out[#out + 1] = label
    end

    local encounterRoot = _G.EXBossData and _G.EXBossData.GetEncounterDataRoot and _G.EXBossData.GetEncounterDataRoot()
    if type(encounterRoot) == "table" then
        for _, mapRow in pairs(encounterRoot) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for _, eventRow in pairs(bossRow.events) do
                            if type(eventRow) == "table" and type(eventRow.voiceLabel) == "string" then
                                Add(NormalizeStandardLabel(eventRow.voiceLabel, 1))
                            end
                        end
                    end
                end
            end
        end
    end

    local trashPresetRoot = nil
    if _G.EXBossData and type(_G.EXBossData.GetTrashCDPresetRoot) == "function" then
        trashPresetRoot = _G.EXBossData.GetTrashCDPresetRoot()
    end
    if type(trashPresetRoot) ~= "table" then
        trashPresetRoot = rawget(_G, "EXBOSS_TRASH_CD_PRESET")
    end
    if type(trashPresetRoot) == "table" then
        for _, mapRow in pairs(trashPresetRoot) do
            if type(mapRow) == "table" then
                for _, npcRow in pairs(mapRow) do
                    if type(npcRow) == "table" then
                        for _, spellRow in pairs(npcRow) do
                            if type(spellRow) == "table" then
                                Add(NormalizeStandardLabel(spellRow.voice1Label or spellRow.castVoiceLabel, 1))
                                Add(NormalizeStandardLabel(spellRow.voice2Label or spellRow.pre5VoiceLabel or spellRow.voiceLabel, 2))
                            end
                        end
                    end
                end
            end
        end
    end

    Add("54321")
    for i = 1, #SCHEMA_STANDARD_LABELS do
        Add(SCHEMA_STANDARD_LABELS[i])
    end

    if #out == 0 then
        return nil
    end

    table.sort(out, function(a, b) return a < b end)
    return out
end

local function GetGeneratedDefaultLabels()
    local built = BuildFactoryDefaultLabels()
    if type(built) == "table" and #built > 0 then
        _G.EXBOSSEXWIND_LABELS = built
        _G.EXBV_LABELS = built
        return built
    end
    if type(_G.EXBOSSEXWIND_LABELS) == "table" and #_G.EXBOSSEXWIND_LABELS > 0 then
        return _G.EXBOSSEXWIND_LABELS
    end
    if type(_G.EXBV_LABELS) == "table" and #_G.EXBV_LABELS > 0 then
        return _G.EXBV_LABELS
    end
    return nil
end

-- 提前注册 _G.EXBV_LABELS，供 ExwindCore 下拉控件读取当前默认包标签池。
do
    local generated = BuildFactoryDefaultLabels()
    if type(generated) == "table" and #generated > 0 then
        _G.EXBOSSEXWIND_LABELS = generated
        _G.EXBV_LABELS = generated
    end
end

-- 从 LSM 动态读取指定语音包的所有标签
local function GetLabelsFromLSM(packName)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local tbl = LSM:HashTable("sound")
    if type(tbl) ~= "table" then return nil end
    local prefix = "[" .. tostring(packName) .. "]"
    local out = {}
    for key in pairs(tbl) do
        if key:sub(1, #prefix) == prefix then
            local label = key:sub(#prefix + 1)
            if label and label ~= "" then
                out[#out + 1] = label
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return a < b end)
    return out
end

-- 获取指定语音包的标签列表。
function Catalog.GetPackLabels(packName)
    packName = tostring(packName or "")

    -- 默认语音包优先使用当前数据生成的标签池。
    if packName == "EXWIND(默认)" or packName == "" then
        local generatedLabels = GetGeneratedDefaultLabels()
        if generatedLabels then
            return generatedLabels
        end
    end

    -- 1. 优先从 LSM 动态读取
    local lsmLabels = GetLabelsFromLSM(packName)
    if lsmLabels then return lsmLabels end

    return {}
end

function Catalog.GetStandardLabels()
    local labels = GetGeneratedDefaultLabels()
    if labels then
        return labels
    end
    return {}
end

-- 给语音页触发器下拉使用：返回 {text, value} 格式
function Catalog.GetDropdownItems()
    local labels = Catalog.GetStandardLabels()

    local out = {}
    for _, label in ipairs(labels) do
        out[#out + 1] = { LText(label), label }
    end
    table.sort(out, function(a, b)
        local ta = tostring(a and a[1] or "")
        local tb = tostring(b and b[1] or "")
        if ta == tb then
            return tostring(a and a[2] or "") < tostring(b and b[2] or "")
        end
        return ta < tb
    end)
    if #out == 0 then
        out[1] = { "（无标签）", "" }
    end
    return out
end
