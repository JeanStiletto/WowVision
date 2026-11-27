-- The sources of the safe routes' danger rules (Broesel's TargetCatalog hooks C.NpcFaction, C.NpcLevel and
-- C.PlayerLevel; engine/README.md, "Changes for WowVision"): which faction a creature is friendly to and its highest
-- level, from Questie, and the player's level. Sighted players see all three: the colour of a name, the levels in the
-- tooltip and the target frame.
--
-- Questie is read through the Questie backend of the quest adapter (classic/quests/questie.lua, the one place that
-- knows Questie's internal module names and field shapes; Forever loads it from camelot/modules.xml before this
-- folder). module.lua installs the hooks every frame it runs (danger.install) and so notes when an input of the rules
-- changed: then the safe routes ask the catalogue again (its bumpDanger), and the catalogue's token (C:DangerSpawns)
-- tells whether the spawn list really changed.

local danger = {}
WowVision.wownavDanger = danger

local questie = nil          -- the Questie backend, made once Questie is there
local seen = nil             -- the inputs the danger tables were last asked with: { level, faction, questieReady }

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

-- tests: forget the backend and the noted inputs
function danger.reset()
    questie, seen = nil, nil
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

-- C.PlayerLevel: UnitLevel("player"), or nil while the game does not give it (it can be nil at the first frames).
function danger.playerLevel()
    if UnitLevel == nil then
        return nil
    end
    local ok, level = pcall(UnitLevel, "player")
    if not ok or (issecretvalue ~= nil and issecretvalue(level)) or type(level) ~= "number" then
        return nil
    end
    return level
end

-- Calls bump(N) when the player's level, the player's faction or whether Questie answers differs from the last call
-- (also from unknown to known: UnitLevel nil then 34, the faction unknown at the first build, Questie ready after the
-- first route, with or without its RegisterOnReady). The first call always bumps. True when it bumped.
function danger.noteInputs(N, bump)
    local source = danger.questie()
    local level = danger.playerLevel()
    local faction = N.PlayerFaction ~= nil and N.PlayerFaction() or nil
    local questieReady = source ~= nil and source.isReady() == true
    if seen ~= nil and seen[1] == level and seen[2] == faction and seen[3] == questieReady then
        return false
    end
    seen = { level, faction, questieReady }
    bump(N)
    return true
end

-- Sets the catalogue's hooks (C = WowVisionNavigationTargetCatalog) and notes the inputs (noteInputs).
function danger.install(N, C, bump)
    if C == nil then
        return
    end
    C.NpcFaction, C.NpcLevel, C.PlayerLevel = danger.npcFaction, danger.npcLevel, danger.playerLevel
    danger.noteInputs(N, bump)
end
