---@diagnostic disable: undefined-global

do
    local MAP_ID = 2805
    local NPC_ID = 232113
    local EVENT_SPELL_ID = 1253683
    local EVENT_KEY = string.format("%d:%d:%d:cast_start", MAP_ID, NPC_ID, EVENT_SPELL_ID)

    local function ResolveSpellName(spellID)
        local fallback = "护法者庇护"
        local locale = type(GetLocale) == "function" and tostring(GetLocale() or "") or ""
        if locale ~= "enUS" and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            local apiName = ok and info and tostring(info.name or "") or ""
            if apiName ~= "" then
                return apiName
            end
        end
        return fallback
    end

    local function ResolveSpellIcon(spellID)
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            local icon = ok and info and tonumber(info.iconID) or nil
            if icon and icon > 0 then
                return icon
            end
        end
        return 134400
    end

    local CustomEvents = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.CustomEvents or nil
    if CustomEvents and type(CustomEvents.Register) == "function" then
        CustomEvents.Register({
            mapID = MAP_ID,
            mapName = "风行者之塔",
            npcID = NPC_ID,
            mobName = "护法魔导师",
            spellID = EVENT_SPELL_ID,
            spellName = ResolveSpellName(EVENT_SPELL_ID),
            description = "",
            trigger = "cast_start",
            firstOnly = true,
            iconFileID = ResolveSpellIcon(EVENT_SPELL_ID),
        })
    end

    local function GetRuntime(unit)
        local api = ExBoss and ExBoss.Trash and ExBoss.Trash.GetRuntimeByUnit or nil
        if type(api) ~= "function" then
            return nil
        end
        return api(unit)
    end

    local function ResolveActiveCastSpellID(unit)
        if type(unit) ~= "string" or type(UnitCastingInfo) ~= "function" then
            return nil
        end
        local ok, _, _, _, _, _, _, _, spellID = pcall(UnitCastingInfo, unit)
        if not ok then
            return nil
        end
        return tonumber(spellID)
    end

    local function FireFirstCastEvent(unit)
        if ResolveActiveCastSpellID(unit) ~= EVENT_SPELL_ID then
            return
        end
        local runtime = GetRuntime(unit)
        if type(runtime) ~= "table" then
            return
        end
        if tonumber(runtime.matchedMapID) ~= MAP_ID then
            return
        end
        if tonumber(runtime.matchedNPCID) ~= NPC_ID then
            return
        end

        runtime._customTrashOnceByKey = runtime._customTrashOnceByKey or {}
        if runtime._customTrashOnceByKey[EVENT_KEY] == true then
            return
        end
        runtime._customTrashOnceByKey[EVENT_KEY] = true

        if ExBoss and type(ExBoss.TriggerTrashEvent) == "function" then
            ExBoss:TriggerTrashEvent({
                mapID = MAP_ID,
                npcID = NPC_ID,
                spellID = EVENT_SPELL_ID,
                trigger = "cast_start",
                unit = unit,
                runtime = runtime,
                displayName = ResolveSpellName(EVENT_SPELL_ID),
            })
        end
    end

    local function TryFireFirstCastEvent(unit, allowRetry)
        local runtime = GetRuntime(unit)
        if type(runtime) ~= "table"
            or tonumber(runtime.matchedMapID) ~= MAP_ID
            or tonumber(runtime.matchedNPCID) ~= NPC_ID then
            if allowRetry == true and C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.05, function()
                    FireFirstCastEvent(unit)
                end)
            end
            return
        end
        FireFirstCastEvent(unit)
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("UNIT_SPELLCAST_START", "ExBoss_WS_Trash_FirstCast_232113", function(_, unit)
            TryFireFirstCastEvent(unit, true)
        end)
    end
end

do
    local MAP_ID = 2805
    local NPC_ID = 232122
    local SPELL_BREAK_RANKS = 471648
    local SPELL_INTERRUPTING_SCREECH = 471643
    local FORCED_CAST_SEQUENCE = {
        [1] = SPELL_BREAK_RANKS,
        [2] = SPELL_INTERRUPTING_SCREECH,
        [3] = SPELL_BREAK_RANKS,
        [4] = SPELL_BREAK_RANKS,
        [5] = SPELL_INTERRUPTING_SCREECH,
    }

    local previousResolver = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.ResolveObservedStartSpellID or nil

    local function ResolveForcedSpellID(runtime, castKind)
        if type(runtime) ~= "table" then
            return nil
        end
        if tonumber(runtime.matchedMapID) ~= MAP_ID or tonumber(runtime.matchedNPCID) ~= NPC_ID then
            return nil
        end
        if tostring(castKind or runtime.activeCastKind or "") ~= "cast" then
            return nil
        end

        local seq = tonumber(runtime.activeCastSeq)
        if not seq then
            return nil
        end

        if tonumber(runtime._ws232122ForcedSeq) ~= seq then
            local nextIndex = (tonumber(runtime._ws232122ForcedCastIndex) or 0) + 1
            runtime._ws232122ForcedSeq = seq
            runtime._ws232122ForcedCastIndex = nextIndex
            runtime._ws232122ForcedSpellID = FORCED_CAST_SEQUENCE[nextIndex]
        end

        return tonumber(runtime._ws232122ForcedSpellID)
    end

    ExBoss.TrashCD = ExBoss.TrashCD or {}
    ExBoss.TrashCD.ResolveObservedStartSpellID = function(runtime, castKind)
        local forcedSpellID = ResolveForcedSpellID(runtime, castKind)
        if forcedSpellID then
            return forcedSpellID
        end
        if type(previousResolver) == "function" then
            return previousResolver(runtime, castKind)
        end
        return nil
    end
end
