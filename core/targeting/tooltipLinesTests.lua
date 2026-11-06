local testRunner = WowVision.testing.testRunner
local tooltipLines = WowVision.tooltipLines

-- A stand-in secret string: only issecretvalue knows it.
local SECRET = setmetatable({}, {
    __concat = function()
        return SECRET
    end,
})

local function withSecrets(fn)
    local saved = issecretvalue
    issecretvalue = function(value)
        return value == SECRET
    end
    local ok, err = pcall(fn)
    issecretvalue = saved
    if not ok then
        error(err, 0)
    end
end

local function facts(extra)
    local result = {
        levelWord = "Level",
        keepWords = { Dead = true, Corpse = true },
        pvpWords = { pvp = true, alliance = true, horde = true },
        ownerPatterns = { tooltipLines.formatPattern("%s's Pet") },
    }
    for key, value in pairs(extra or {}) do
        result[key] = value
    end
    return result
end

local function kindsOf(lines, unitFacts)
    return tooltipLines.classify(lines, unitFacts or facts())
end

testRunner:addSuite("TargetTooltipLines", {
    ["a classic player tooltip sorts by text"] = function(t)
        local kinds = kindsOf({
            { "Thrall" },
            { "<Horde Heroes>" },
            { "Level 60 Orc Shaman (Player)" },
            { "Horde" },
            { "PvP" },
        }, facts({ isPlayer = true, guild = "Horde Heroes" }))
        t:assertEqual(kinds[1], "name")
        t:assertEqual(kinds[2], "guild")
        t:assertEqual(kinds[3], "level")
        t:assertEqual(kinds[4], "pvp")
        t:assertEqual(kinds[5], "pvp")
    end,

    ["an NPC title is always read, an unknown line is other"] = function(t)
        local kinds = kindsOf({
            { "Innkeeper Farley" },
            { "<Innkeeper>" },
            { "Level 30 Humanoid" },
            { "Skinnable" },
        })
        t:assertEqual(kinds[2], "keep")
        t:assertEqual(kinds[3], "level")
        t:assertEqual(kinds[4], "other")
    end,

    -- From a WoW: Forever capture (2026-11-06): every line typed None, the
    -- title without brackets, the level line without the level word.
    ["a Forever NPC: title before the level, level by number, PvP"] = function(t)
        local kinds = kindsOf({
            { "Donaal Downbreeze" },
            { "Gastwirt" },
            { "Stufe 10" },
            { "PvP" },
        }, facts({ levelWord = "Niveau", level = 10 }))
        t:assertEqual(kinds[2], "keep")
        t:assertEqual(kinds[3], "level")
        t:assertEqual(kinds[4], "pvp")
    end,

    ["a Forever player: class line counts as level, no title rule"] = function(t)
        local kinds = kindsOf({
            { "Xanthippe Petronas" },
            { "Stufe 12 Himmelsgeborene des Hohen Ordens (Spieler)" },
            { "Druidin" },
            { "Allianz" },
            { "Recent Allies" },
        }, facts({ levelWord = "Stufe", level = 12, className = "Druidin", isPlayer = true }))
        t:assertEqual(kinds[2], "level")
        t:assertEqual(kinds[3], "level")
        t:assertEqual(kinds[4], "other")
        t:assertEqual(kinds[5], "other")
    end,

    -- From a WoW: Forever capture (2026-11-06 13:49): level word "St.".
    ["a Forever beast: creature type line counts as level, threat by type"] = function(t)
        local kinds = kindsOf({
            { "Himmelshüpfer" },
            { "Stufe 8" },
            { "Wildtier" },
            { "100% Bedrohung", typeName = "UnitThreat" },
        }, facts({ levelWord = "St.", level = 8, creatureType = "Wildtier" }))
        t:assertEqual(kinds[2], "level")
        t:assertEqual(kinds[3], "level")
        t:assertEqual(kinds[4], "threat")
    end,

    ["a level 2 kobold with 2 of 8 killed: only the level line is level"] = function(t)
        local kinds = kindsOf({
            { "Kobold-Arbeiter" },
            { "Stufe 2" },
            { "2 Kobolde zu viel" },
            { "Kobold-Arbeiter getötet: 2/8" },
            { "2/8 Kobold-Arbeiter" },
            { "Fortschritt 2%" },
        }, facts({ levelWord = "Niveau", level = 2 }))
        t:assertEqual(kinds[2], "level")
        t:assertEqual(kinds[3], "other")
        t:assertEqual(kinds[4], "other")
        t:assertEqual(kinds[5], "other")
        t:assertEqual(kinds[6], "other")
    end,

    ["a count or objective near the top is never the level line"] = function(t)
        local kinds = kindsOf({
            { "Kobold-Arbeiter" },
            { "2/8 Kobold-Arbeiter" },
            { "Kobolde: 2" },
        }, facts({ levelWord = "Niveau", level = 2 }))
        t:assertEqual(kinds[2], "other")
        t:assertEqual(kinds[3], "other")
    end,

    ["the level number must be the line's first number, within line 3"] = function(t)
        local kinds = kindsOf({
            { "Wolf" },
            { "Rudel 3, Stufe 2" },
            { "Elite" },
            { "Stufe 2" },
        }, facts({ levelWord = "Niveau", level = 2 }))
        t:assertEqual(kinds[2], "other")
        t:assertEqual(kinds[4], "other")
    end,

    ["without a level line an NPC's lines are not taken for a title"] = function(t)
        local kinds = kindsOf({ { "Wisp" }, { "Something" }, { "<Vendor>" } })
        t:assertEqual(kinds[2], "other")
        t:assertEqual(kinds[3], "other")
    end,

    ["the level word ignores case and no-break spaces"] = function(t)
        local kinds = kindsOf({ { "x" }, { "level\194\16030 Beast" }, { "PVP" } })
        t:assertEqual(kinds[2], "level")
        t:assertEqual(kinds[3], "pvp")
    end,

    ["a pet's owner line needs a player-controlled non-player"] = function(t)
        local lines = { { "Wolf" }, { "Rexxar's Pet" }, { "Level 60 Beast" } }
        t:assertEqual(kindsOf(lines, facts({ playerControlled = true }))[2], "owner")
        -- On an NPC the same line, above the level, is its title.
        t:assertEqual(kindsOf(lines, facts())[2], "keep")
    end,

    ["dead and blank lines"] = function(t)
        local kinds = kindsOf({ { "Kobold" }, { "Level 5 Humanoid" }, { "Dead" }, { "" }, { "|cffffffff|r" } })
        t:assertEqual(kinds[3], "keep")
        t:assertEqual(kinds[4], "blank")
        t:assertEqual(kinds[5], "blank")
    end,

    ["colour codes are ignored in the comparison"] = function(t)
        local kinds = kindsOf({ { "x" }, { "|cffff0000PvP|r" } })
        t:assertEqual(kinds[2], "pvp")
    end,

    ["line types win over text"] = function(t)
        local kinds = kindsOf({
            { "Defias Bandit", typeName = "UnitName" },
            { "Level 12 Humanoid", typeName = "UnitLevel" },
            { "Collect Red Bandanas", typeName = "QuestTitle" },
            { " - Red Bandana: 3/10", typeName = "QuestObjective" },
            { "Something", typeName = "LearnableSpell" },
            { "Alliance", typeName = "None" },
        })
        t:assertEqual(kinds[2], "level")
        t:assertEqual(kinds[3], "quest")
        t:assertEqual(kinds[4], "quest")
        t:assertEqual(kinds[5], "other")
        t:assertEqual(kinds[6], "pvp")
    end,

    ["a secret line without a usable type is always read"] = function(t)
        withSecrets(function()
            local kinds = kindsOf({
                { SECRET },
                { SECRET },
                { SECRET, typeName = tooltipLines.SECRET },
                { SECRET, typeName = "None" },
            })
            t:assertEqual(kinds[1], "name")
            t:assertEqual(kinds[2], "keep")
            t:assertEqual(kinds[3], "keep")
            t:assertEqual(kinds[4], "keep")
        end)
    end,

    ["a secret line with a plain type is sorted by its type"] = function(t)
        withSecrets(function()
            local kinds = kindsOf({ { SECRET }, { SECRET, typeName = "UnitLevel" } })
            t:assertEqual(kinds[2], "level")
        end)
    end,

    ["the filter drops switched-off kinds and blanks, never the name"] = function(t)
        local lines = { { "Thrall" }, { "<Horde Heroes>" }, { "Level 60" }, { "" }, { "PvP" } }
        local kinds = { "name", "guild", "level", "blank", "pvp" }
        local kept = tooltipLines.filter(lines, kinds, { guild = true, pvp = true })
        t:assertEqual(#kept, 2)
        t:assertEqual(kept[1][1], "Thrall")
        t:assertEqual(kept[2][1], "Level 60")
    end,

    ["format strings become whole-line patterns"] = function(t)
        t:assertEqual(tooltipLines.formatPattern("%s's Pet"), "^.+'s Pet$")
        t:assertEqual(tooltipLines.formatPattern("%1$s (Minion)"), "^.+ %(Minion%)$")
        t:assertTrue(("Rexxar's Pet"):find(tooltipLines.formatPattern("%s's Pet")) ~= nil)
        t:assertTrue(("Begleiter von Rexxar"):find(tooltipLines.formatPattern("Begleiter von %s")) ~= nil)
    end,
})
