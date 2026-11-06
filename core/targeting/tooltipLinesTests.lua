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
        pvpWords = { PvP = true, Alliance = true, Horde = true },
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

    ["a pet's owner line needs a player-controlled non-player"] = function(t)
        local lines = { { "Wolf" }, { "Rexxar's Pet" }, { "Level 60 Beast" } }
        t:assertEqual(kindsOf(lines, facts({ playerControlled = true }))[2], "owner")
        t:assertEqual(kindsOf(lines, facts())[2], "other")
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
