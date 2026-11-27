-- The sources of the safe routes' danger rules (Broesel's TargetCatalog hooks C.NpcFaction, C.NpcLevel and
-- C.PlayerLevel; engine/README.md, "Changes for WowVision"): which faction a creature is friendly to and its highest
-- level, from Questie, and the player's level. Sighted players see all three: the colour of a name, the levels in the
-- tooltip and the target frame.
--
-- Questie is read through the Questie backend of the quest adapter (classic/quests/questie.lua, the one place that
-- knows Questie's internal module names and field shapes; Forever loads it from camelot/modules.xml before this
-- folder). module.lua sets the hooks once, when the network is indexed (danger.install), and asks the catalogue again
-- (its bumpDanger) when an input of the rules may have changed, the WowVision way, by events and not by polling (user
-- decision 2026-11-27): PLAYER_LEVEL_UP, PLAYER_ENTERING_WORLD (the faction and the level are known by then; it also
-- covers the first build) and the quest module's events.ready (Questie usable; danger.watch). The catalogue's token
-- (C:DangerSpawns) tells whether the spawn list really changed.

local danger = {}
WowVision.wownavDanger = danger

local questie = nil          -- the Questie backend, made once Questie is there
local levelUp = nil          -- the level PLAYER_LEVEL_UP gave (UnitLevel can still give the old one for a moment)

-- The Questie backend, or nil without Questie.
function danger.questie()
    if questie == nil then
        local quests = WowVision.quests
        if quests ~= nil and quests.questieBackend ~= nil then
            questie = quests.questieBackend()
        end
    end
    return questie
end

-- tests: forget the backend and the noted level-up
function danger.reset()
    questie, levelUp = nil, nil
end

-- One field of a creature from Questie; second result false when Questie could not be asked.
local function npcField(entry, field)
    local source = danger.questie()
    if source == nil or source.npcField == nil then
        return nil, false
    end
    return source.npcField(entry, field)
end

-- C.NpcFaction: Questie's friendlyToFaction as "A", "H", "AH" or nil (friendly to neither); false while Questie
-- cannot be asked or does not know the ID (then his kind rule judges that creature).
function danger.npcFaction(entry)
    local friendly, asked = npcField(entry, "friendlyToFaction")
    if not asked then
        return false
    end
    if friendly == "A" or friendly == "H" then
        return friendly
    end
    if friendly == nil or friendly == "" then
        return nil
    end
    return "AH"
end

-- C.NpcLevel: Questie's maxLevel, or nil.
function danger.npcLevel(entry)
    local level = npcField(entry, "maxLevel")
    if type(level) == "number" then
        return level
    end
    return nil
end

-- C.PlayerLevel: UnitLevel("player"), or nil while the game does not give it (it can be nil at the first frames). Right
-- after a level-up the level of PLAYER_LEVEL_UP when UnitLevel still gives a lower one: a table built then would
-- otherwise keep the old level, and its token (the same spawn list) would keep that table until the next event.
function danger.playerLevel()
    local level = nil
    if UnitLevel ~= nil then
        local ok, value = pcall(UnitLevel, "player")
        if ok and not (issecretvalue ~= nil and issecretvalue(value)) and type(value) == "number" then
            level = value
        end
    end
    if levelUp ~= nil and (level == nil or level < levelUp) then
        return levelUp
    end
    return level
end

-- The game events that may change an input of the rules; the module registers them.
danger.EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }

-- The module's onEvent: true when the event may have changed an input of the rules (then the module asks the
-- catalogue again). PLAYER_LEVEL_UP's first argument is the new level.
function danger.onEvent(event, arg1)
    if event == "PLAYER_LEVEL_UP" then
        if type(arg1) == "number" then
            levelUp = arg1
        end
        return true
    end
    return event == "PLAYER_ENTERING_WORLD"
end

-- Calls ask() whenever the quest module (core/quests/module.lua) says its data source is usable (events.ready; on
-- Forever the Questie backend's onReady). quests may be nil (no quest module): then nothing.
function danger.watch(subscriber, quests, ask)
    if quests ~= nil and quests.events ~= nil and quests.events.ready ~= nil then
        quests.events.ready:subscribe(subscriber, function()
            ask()
        end)
    end
end

function danger.unwatch(subscriber, quests)
    if quests ~= nil and quests.events ~= nil and quests.events.ready ~= nil then
        quests.events.ready:unsubscribe(subscriber)
    end
end

-- Sets the catalogue's hooks (C = WowVisionNavigationTargetCatalog), once when the network is indexed.
function danger.install(C)
    if C == nil then
        return
    end
    C.NpcFaction, C.NpcLevel, C.PlayerLevel = danger.npcFaction, danger.npcLevel, danger.playerLevel
end
