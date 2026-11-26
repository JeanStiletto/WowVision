local testRunner = WowVision.testing.testRunner
local cp = WowVision.customPoints

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

testRunner:addSuite("CustomPoints", {
    ["a new store is made once and only completed after that"] = function(t)
        local data = {}
        local store = cp.store(data)
        t:assertEqual(#store.waypoints, 0)
        t:assertEqual(#store.dangers, 0)
        t:assertEqual(store.nextId, 1)
        cp.add(store, "waypoint", 1, 2, nil, 0, "Inn")
        data.customPoints.dangers = nil
        local again = cp.store(data)
        t:assertTrue(again == store, "the same table")
        t:assertEqual(#again.waypoints, 1, "the saved waypoint stays")
        t:assertEqual(#again.dangers, 0, "a missing list comes back empty")
    end,

    ["points get their own ids; dangers get the danger radius"] = function(t)
        local store = cp.store({})
        local a = cp.add(store, "waypoint", 10, 20, 5, 0, "Camp")
        local b = cp.add(store, "danger", 30, 40, nil, 0)
        t:assertTrue(a.id ~= b.id)
        t:assertNil(a.radius)
        t:assertEqual(b.radius, cp.DANGER_RADIUS)
        t:assertEqual(cp.label(a, "waypoint", L), "Camp")
        t:assertEqual(cp.label(b, "danger", L), "Monster spawn", "a danger point needs no name")
    end,

    ["rename keeps the point; a blank name goes back to the default"] = function(t)
        local store = cp.store({})
        local p = cp.add(store, "danger", 1, 1, nil, 0)
        t:assertTrue(cp.rename(store, "danger", p.id, "  Vulture  "))
        t:assertEqual(p.name, "Vulture", "trimmed")
        t:assertTrue(cp.rename(store, "danger", p.id, "   "))
        t:assertNil(p.name)
        t:assertFalse(cp.rename(store, "danger", "nope", "x"), "an unknown id")
    end,

    ["shipped points extend the list once, never replace, and a deleted one stays deleted"] = function(t)
        local store = cp.store({})
        local mine = cp.add(store, "waypoint", 5, 5, nil, 0, "Mine")
        local shipped = {
            { id = "wv:a", kind = "danger", x = 100, y = 200, map = 0 },
            { id = "wv:b", kind = "waypoint", x = 1, y = 2, map = 0, name = "Shipped place" },
        }
        t:assertEqual(cp.mergeShipped(store, shipped), 2)
        t:assertEqual(#store.dangers, 1)
        t:assertEqual(store.dangers[1].radius, cp.DANGER_RADIUS)
        t:assertEqual(store.waypoints[1], mine, "the player's own point keeps its place")
        t:assertEqual(#store.waypoints, 2)
        -- the player renames a shipped point; a later merge leaves his name
        cp.rename(store, "waypoint", "wv:b", "My name")
        t:assertEqual(cp.mergeShipped(store, shipped), 0)
        t:assertEqual(cp.find(store, "waypoint", "wv:b").name, "My name")
        -- deleted: not handed over again
        t:assertTrue(cp.remove(store, "danger", "wv:a"))
        t:assertEqual(cp.mergeShipped(store, shipped), 0)
        t:assertEqual(#store.dangers, 0)
        -- a newly shipped point still arrives
        shipped[#shipped + 1] = { id = "wv:c", kind = "danger", x = 3, y = 3, map = 0 }
        t:assertEqual(cp.mergeShipped(store, shipped), 1)
    end,

    ["a shipped point already handed over gets a name shipped later, unless the player named it"] = function(t)
        local store = cp.store({})
        local shipped = {
            { id = "wv:v1", kind = "danger", x = 1, y = 1, map = 0 },
            { id = "wv:v2", kind = "danger", x = 2, y = 2, map = 0 },
        }
        cp.mergeShipped(store, shipped)
        cp.rename(store, "danger", "wv:v2", "My vulture")
        shipped[1].name = "Pestschwingengeier"
        shipped[2].name = "Pestschwingengeier"
        t:assertEqual(cp.mergeShipped(store, shipped), 1, "one point named")
        t:assertEqual(cp.find(store, "danger", "wv:v1").name, "Pestschwingengeier")
        t:assertEqual(cp.find(store, "danger", "wv:v2").name, "My vulture", "the player's name stays")
        t:assertEqual(#store.dangers, 2, "nothing added twice")
        t:assertEqual(cp.mergeShipped(store, shipped), 0, "nothing left to do")
    end,

    ["lists are per map; danger spawns carry a unique name and the radius"] = function(t)
        local store = cp.store({})
        cp.add(store, "danger", 10, 10, nil, 0)
        cp.add(store, "danger", 50, 50, nil, 1)
        cp.add(store, "waypoint", 10, 10, nil, 0, "W")
        t:assertEqual(#cp.list(store, "danger", 0), 1)
        t:assertEqual(#cp.list(store, "danger"), 2)
        local spawns = cp.dangerSpawns(store, 0, function(x)
            return x < 20
        end)
        t:assertEqual(#spawns, 1)
        t:assertEqual(spawns[1].radius, cp.DANGER_RADIUS)
        t:assertEqual(spawns[1].name, "custom:" .. store.dangers[1].id)
        t:assertEqual(#cp.dangerSpawns(store, 0, function()
            return false
        end), 0, "not in the zone asked for")
    end,

    ["coordinates: map percent with dot or comma, or world yards"] = function(t)
        local mode, a, b = cp.parseCoordinates("45.2 63.1")
        t:assertEqual(mode, "map")
        t:assertEqual(a, 45.2)
        t:assertEqual(b, 63.1)
        mode, a, b = cp.parseCoordinates("45,2 63,1")
        t:assertEqual(a, 45.2, "decimal comma")
        t:assertEqual(b, 63.1)
        mode, a, b = cp.parseCoordinates("45.2, 63.1")
        t:assertEqual(a, 45.2, "comma and space between")
        t:assertEqual(b, 63.1)
        mode, a, b = cp.parseCoordinates("45; 63")
        t:assertEqual(a, 45)
        t:assertEqual(b, 63)
        mode, a, b = cp.parseCoordinates("world 1198.2 -1116")
        t:assertEqual(mode, "world")
        t:assertEqual(a, 1198.2)
        t:assertEqual(b, -1116)
        t:assertNil(cp.parseCoordinates("hello"))
        t:assertNil(cp.parseCoordinates("45.2"))
        t:assertNil(cp.parseCoordinates("145 20"), "map percent above 100")
    end,
})
