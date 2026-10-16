local testRunner = WowVision.testing.testRunner
local logic = WowVision.surroundingsLogic

-- A places file: zone 1 (a forest, explored by overlays) with two subzones, a village (heart at
-- 100, 0; an inn with two doorways, the north one with its outside point) and a lake (no heart,
-- crossings from the zone's land at 0, 200 and from the village at 50, 150), and a well in no
-- subzone at 10, 10; zone 2 (a city, shown whole) with a district far east.
local function newPlaces()
    return {
        key = "test", map = 0, format = 1,
        zones = {
            { 12, 1, 1429, 0, items = { { "landmark", 2, 2, { 10, 10 } } } },
            { 1519, 3, 1453, 1, items = {} },
        },
        areas = {
            { 1, 87, 4, 1, 2, { 100, 0 }, { 120, 0, 0, 1 }, { 100, 0, 110, 0 }, items = {
                { "building", 5, 4, { 103, 0, 106, 0, 80, 0, 77, 0 },
                    rooms = { { "room", 6, 4, { 104, 2, 103, 0 } } } },
            } },
            { 1, 88, 7, 1, 2, {}, { 0, 200, 0, 0, 50, 150, 1, 0 }, { 0, 220 }, items = {
                { "landmark", 2, 2, { 5, 230 } },
            } },
            { 2, 0, 8, 0, 2, { 0, 1000 }, {}, { 0, 1000 }, items = {} },
        },
        names_enUS = { "Forest", "well", "City", "Village", "Inn", "Common Room", "Lake", "Harbour" },
        names_deDE = { "Wald", "Brunnen", "Stadt", "Dorf", "Gasthaus", "Schankraum", "See", "Hafen" },
    }
end

local function find(list, label)
    for _, n in ipairs(list or {}) do
        if n.label == label then
            return n
        end
    end
end

testRunner:addSuite("Surroundings places list", {
    ["unpacks names in the client's language, English where it has none"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "deDE")
        t:assertEqual(P.zones[1].name, "Wald")
        t:assertEqual(P.areas[1].items[1].rooms[1].name, "Schankraum")
        local E = logic.placesUnpack(newPlaces(), "frFR")
        t:assertEqual(E.zones[1].name, "Forest")
        t:assertEqual(#E.zones[1].areas, 2)
        t:assertEqual(E.areas[2].doors[2].from, 1)
    end,
    ["the zone here comes first and open, its subzone here first and open, the rest by distance"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "enUS")
        local tree = logic.placesTree({ P }, { x = 0, y = 190, map = 0, zoneName = "Forest", subzone = "Village" })
        t:assertEqual(tree[1].label, "Forest")
        t:assertEqual(tree[1].expanded, true)
        t:assertEqual(tree[2].label, "City")
        t:assertEqual(tree[2].expanded, false)
        local kids = tree[1].children
        t:assertEqual(kids[1].label, "Village")
        t:assertEqual(kids[1].expanded, true)
        -- the lake leads to its nearest crossing (0, 200), the well (10, 10) is farther
        t:assertEqual(kids[2].label, "Lake")
        t:assertEqual(kids[2].x, 0)
        t:assertEqual(kids[2].y, 200)
        t:assertEqual(kids[3].label, "well")
    end,
    ["a building leads to its nearest doorway, with the point outside it"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "enUS")
        local tree = logic.placesTree({ P }, { x = 70, y = 0, map = 0, zoneName = "Forest", subzone = "" })
        local inn = find(find(tree[1].children, "Village").children, "Inn")
        t:assertEqual(inn.x, 80)
        t:assertEqual(inn.ox, 77)
        t:assertEqual(inn.children[1].label, "Common Room")
        t:assertEqual(inn.children[1].ox, 103)
        -- the room is reached through the inn's doorway first
        t:assertEqual(inn.children[1].viaX, 77)
    end,
    ["discovery mode: an unexplored subzone is nameless, reached from what is known"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "enUS")
        local tree = logic.placesTree({ P }, {
            x = 60, y = 160, map = 0, zoneName = "Forest", subzone = "", discovery = true, unexplored = "unexplored area",
            known = function(area)
                return area.name == "Village"
            end,
        })
        local kids = tree[1].children
        local lake = find(kids, "unexplored area")
        t:assertNotNil(lake)
        t:assertNil(lake.children)
        -- the crossing from the explored village is nearer than the one from the zone's land
        t:assertEqual(lake.x, 50)
        t:assertEqual(lake.y, 150)
        t:assertNil(find(kids, "Lake"))
        t:assertNotNil(find(kids, "Village"))
        -- the well in no subzone is out of sight (more than IN_SIGHT away)
        t:assertNil(find(kids, "well"))
        -- the city's map is shown whole: its district by name
        t:assertNotNil(find(tree[2].children, "Harbour"))
    end,
    ["discovery mode: only neighbours of explored subzones or the one here are listed"] = function(t)
        local raw = newPlaces()
        raw.areas[2][7] = { 50, 150, 1, 0 }
        local P = logic.placesUnpack(raw, "enUS")
        local opts = { x = 0, y = 0, map = 0, zoneName = "Forest", subzone = "", discovery = true,
            known = function()
                return false
            end }
        local kids = logic.placesTree({ P }, opts)[1].children
        -- neither the village (only beside the zone's own land) nor the lake (only beside the
        -- unexplored village); the well in sight
        t:assertEqual(#kids, 1)
        t:assertEqual(kids[1].label, "well")
        -- standing in the lake: the village beside it is listed, nameless, at their crossing
        raw = newPlaces()
        raw.areas[1][7] = { 120, 0, 0, 1, 60, 140, 2, 0 }
        P = logic.placesUnpack(raw, "enUS")
        opts.subzone = "Lake"
        kids = logic.placesTree({ P }, opts)[1].children
        t:assertEqual(kids[1].label, "Lake")
        local nameless = find(kids, "unexplored area")
        t:assertEqual(nameless.x, 60)
    end,
    ["a zone the game names otherwise is found by distance"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "enUS")
        local tree = logic.placesTree({ P }, { x = 0, y = 990, map = 0, zoneName = "Sturmwind", subzone = "" })
        t:assertEqual(tree[1].label, "City")
        t:assertEqual(tree[1].expanded, true)
    end,
    ["other continents are left out"] = function(t)
        local P = logic.placesUnpack(newPlaces(), "enUS")
        t:assertEqual(#logic.placesTree({ P }, { x = 0, y = 0, map = 1 }), 0)
    end,
})
