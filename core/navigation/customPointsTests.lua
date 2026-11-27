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

    ["points get their own ids; a danger point keeps no radius of its own (the default applies)"] = function(t)
        local store = cp.store({})
        local a = cp.add(store, "waypoint", 10, 20, 5, 0, "Camp")
        local b = cp.add(store, "danger", 30, 40, nil, 0)
        t:assertTrue(a.id ~= b.id)
        t:assertNil(a.radius)
        t:assertNil(b.radius, "not stored")
        t:assertEqual(cp.dangerSpawns(store, 0)[1].radius, cp.DANGER_RADIUS, "the default radius for the engine")
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
        t:assertNil(store.dangers[1].radius, "the default radius is not stored")
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

    ["a shipped point keeps only a radius of its own"] = function(t)
        local store = cp.store({})
        cp.mergeShipped(store, {
            { id = "wv:r1", kind = "danger", x = 1, y = 1, map = 0, radius = 20 },
            { id = "wv:r2", kind = "danger", x = 2, y = 2, map = 0, radius = cp.DANGER_RADIUS },
        })
        t:assertEqual(cp.find(store, "danger", "wv:r1").radius, 20)
        t:assertNil(cp.find(store, "danger", "wv:r2").radius)
        t:assertEqual(cp.dangerSpawns(store, 0)[1].radius, 20)
    end,

    ["a shipped name the player cleared is not filled in again"] = function(t)
        local store = cp.store({})
        local shipped = { { id = "wv:n1", kind = "danger", x = 1, y = 1, map = 0, name = "Vulture" } }
        cp.mergeShipped(store, shipped)
        t:assertEqual(cp.find(store, "danger", "wv:n1").name, "Vulture")
        cp.rename(store, "danger", "wv:n1", "")
        local added, named = cp.mergeShipped(store, shipped)
        t:assertEqual(added, 0)
        t:assertEqual(named, 0, "no change, so no rebuild")
        t:assertNil(cp.find(store, "danger", "wv:n1").name, "the default name stays")
        -- a new name of his own ends the cleared state; clearing again keeps it cleared
        cp.rename(store, "danger", "wv:n1", "Mine")
        t:assertNil(cp.find(store, "danger", "wv:n1").nameCleared)
        cp.rename(store, "danger", "wv:n1", " ")
        cp.mergeShipped(store, shipped)
        t:assertNil(cp.find(store, "danger", "wv:n1").name)
    end,

    ["changes in a provisional store are made again in the client's store"] = function(t)
        -- the provisional store: a copy of the account as this character last saw it
        local real = cp.store({})
        local old = cp.add(real, "waypoint", 1, 1, nil, 0, "Old")
        local gone = cp.add(real, "danger", 2, 2, nil, 0)
        local provisional = cp.store({ customPoints = {
            waypoints = { { id = old.id, name = "Old", x = 1, y = 1, map = 0 } },
            dangers = { { id = gone.id, x = 2, y = 2, map = 0 } },
            nextId = real.nextId, shippedSeen = {},
        } })
        -- another character added a point to the real store meanwhile: it took the next id
        local other = cp.add(real, "waypoint", 9, 9, nil, 0, "Other")
        local journal = {}
        local new = cp.add(provisional, "waypoint", 5, 5, nil, 0, "Camp")
        journal[#journal + 1] = cp.journalEntry("add", "waypoint", new)
        cp.rename(provisional, "waypoint", new.id, "Camp 2")
        journal[#journal + 1] = cp.journalEntry("rename", "waypoint", new)
        cp.rename(provisional, "waypoint", old.id, "Renamed")
        journal[#journal + 1] = cp.journalEntry("rename", "waypoint", cp.find(provisional, "waypoint", old.id))
        local removed = cp.find(provisional, "danger", gone.id)
        cp.remove(provisional, "danger", gone.id)
        journal[#journal + 1] = cp.journalEntry("remove", "danger", removed)
        t:assertEqual(new.id, other.id, "the provisional id collides with the other character's point")

        t:assertEqual(cp.replay(real, journal), 4)
        t:assertEqual(#real.waypoints, 3, "old, other, camp")
        t:assertEqual(cp.find(real, "waypoint", other.id).name, "Other", "the other point is untouched")
        t:assertEqual(real.waypoints[3].name, "Camp 2", "the new point with its later name")
        t:assertTrue(real.waypoints[3].id ~= other.id, "an id of the real store")
        t:assertEqual(cp.find(real, "waypoint", old.id).name, "Renamed")
        t:assertEqual(#real.dangers, 0, "the deletion carried over")
    end,

    ["replay drops a change whose point is another one in the client's store"] = function(t)
        local real = cp.store({})
        cp.add(real, "waypoint", 50, 50, nil, 0, "Theirs")
        local journal = { { op = "rename", kind = "waypoint", id = "u1", x = 1, y = 1, map = 0, name = "Mine" },
            { op = "remove", kind = "waypoint", id = "u1", x = 1, y = 1, map = 0 } }
        t:assertEqual(cp.replay(real, journal), 0)
        t:assertEqual(real.waypoints[1].name, "Theirs")
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
        t:assertEqual(select(2, cp.mergeShipped(store, shipped)), 1, "one point named")
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

    ["a blocked passage: its link in its own zone, only where its waypoints still are"] = function(t)
        local store = cp.store({})
        local p, status = cp.addBlocked(store, 101, 102, 10, 10, 20, 30, 0)
        t:assertEqual(status, "added")
        t:assertEqual(p.x, 15)
        t:assertEqual(p.y, 20)
        t:assertEqual(cp.label(p, "blocked", L), "Blocked passage")
        local positions = { [101] = { 10, 10 }, [102] = { 20.5, 30 } }
        local zone = {
            owns = function(id)
                return id >= 100 and id < 200
            end,
            position = function(id)
                local pos = positions[id]
                if pos then
                    return pos[1], pos[2]
                end
            end,
            touches = function()
                return true
            end,
            linksNear = function()
                return {}
            end,
        }
        local links = cp.blockedInZone(store, 0, zone)
        t:assertEqual(#links, 1)
        t:assertEqual(links[1][1], 101)
        t:assertEqual(links[1][2], 102)
        t:assertEqual(#cp.blockedInZone(store, 1, zone), 0, "another map")
        local otherZone = { owns = function()
            return false
        end, position = zone.position, touches = zone.touches, linksNear = zone.linksNear }
        t:assertEqual(#cp.blockedInZone(store, 0, otherZone), 0, "another zone")
        positions[102] = { 60, 30 }
        t:assertEqual(#cp.blockedInZone(store, 0, zone), 0, "the waypoint moved: other route data")
        -- shipped passages keep their link fields
        cp.mergeShipped(store, { { id = "wv:rock", kind = "blocked", a = 7, b = 8, ax = 1, ay = 1, bx = 2, by = 2,
            map = 0, x = 1.5, y = 1.5 } })
        local rock = cp.find(store, "blocked", "wv:rock")
        t:assertEqual(rock.a, 7)
        t:assertEqual(rock.bx, 2)
        t:assertNil(rock.kind)
    end,

    ["a blocked passage saved again: known at the same positions, replaced when its waypoints moved"] = function(t)
        local store = cp.store({})
        local p = cp.addBlocked(store, 101, 102, 10, 10, 20, 30, 0)
        cp.rename(store, "blocked", p.id, "The rock")
        local again, status = cp.addBlocked(store, 102, 101, 20, 30, 10.5, 10, 0)
        t:assertTrue(again == p, "the same link, either way round")
        t:assertEqual(status, "known")
        t:assertEqual(#store.blocked, 1)
        local moved, movedStatus, old = cp.addBlocked(store, 101, 102, 40, 40, 50, 50, 0)
        t:assertEqual(movedStatus, "moved", "same ids, other positions: other route data")
        t:assertTrue(old == p)
        t:assertEqual(#store.blocked, 1, "the stale entry is gone")
        t:assertEqual(moved.ax, 40)
        t:assertEqual(moved.name, "The rock", "its name is kept")
        t:assertEqual(select(2, cp.addBlocked(store, 101, 102, 40, 40, 50, 50, 1)), "added", "another map")
    end,

    ["a blocked spot: its links where its circle meets the zone, a spot saved again is known"] = function(t)
        local store = cp.store({})
        local spot, status = cp.addBlockedSpot(store, 100, 100, 80, 0)
        t:assertEqual(status, "added")
        t:assertEqual(spot.radius, cp.BLOCKED_SPOT_RADIUS)
        t:assertEqual(select(2, cp.addBlockedSpot(store, 100.5, 100, 80, 0)), "known")
        t:assertEqual(select(2, cp.addBlockedSpot(store, 100, 100, 60, 0)), "added", "another height")
        table.remove(store.blocked)
        local asked, askedRadius = nil, nil
        local touches = true
        local zone = {
            owns = function()
                return true
            end,
            position = function()
                return 0, 0
            end,
            touches = function(x, y, radius)
                return touches and x == 100 and y == 100 and radius == cp.BLOCKED_SPOT_RADIUS
            end,
            linksNear = function(point, radius)
                asked, askedRadius = point, radius
                return { { 1, 2 }, { 3, 4 } }
            end,
        }
        local links = cp.blockedInZone(store, 0, zone)
        t:assertTrue(asked == spot, "the spot is handed to the network side")
        t:assertEqual(askedRadius, cp.BLOCKED_SPOT_RADIUS)
        t:assertEqual(#links, 2)
        touches = false
        t:assertEqual(#cp.blockedInZone(store, 0, zone), 0, "the circle does not meet the zone")
    end,

    ["blocked passages saved while the store is provisional are made in the client's store"] = function(t)
        local provisional = cp.store({})
        local journal = {}
        local link = cp.addBlocked(provisional, 101, 102, 10, 10, 20, 30, 0)
        link.name = "Rock"
        journal[#journal + 1] = cp.journalEntry("add", "blocked", link)
        local spot = cp.addBlockedSpot(provisional, 50, 60, 70, 0, 9)
        journal[#journal + 1] = cp.journalEntry("add", "blocked", spot)
        local client = cp.store({})
        cp.add(client, "waypoint", 1, 1, nil, 0, "taken id")
        t:assertEqual(cp.replay(client, journal), 2)
        t:assertEqual(#client.blocked, 2)
        local copy = client.blocked[1]
        t:assertEqual(copy.a, 101)
        t:assertEqual(copy.by, 30)
        t:assertEqual(copy.name, "Rock")
        t:assertTrue(copy.id ~= link.id, "a new id of the client's store")
        local spotCopy = client.blocked[2]
        t:assertNil(spotCopy.a)
        t:assertEqual(spotCopy.radius, 9)
        t:assertEqual(spotCopy.z, 70)
        -- replayed into a store that already has the link: nothing doubled, its own name stays
        local again = cp.store({})
        local own = cp.addBlocked(again, 101, 102, 10, 10, 20, 30, 0)
        own.name = "Mine"
        cp.replay(again, journal)
        t:assertEqual(#again.blocked, 2)
        t:assertEqual(own.name, "Mine")
    end,

    ["coordinates: the forms with spaces, comma or semicolon between the numbers"] = function(t)
        local parse = WowVision.mapCoordinates.parse
        local function check(text, mode, a, b)
            local m, x, y = parse(text)
            t:assertEqual(m, mode, text)
            t:assertEqual(x, a, text)
            t:assertEqual(y, b, text)
        end
        check("45.2 63.1", "map", 45.2, 63.1)
        check("  45.2   63.1  ", "map", 45.2, 63.1)
        check("45,2 63,1", "map", 45.2, 63.1)
        check("45.2,63.1", "map", 45.2, 63.1)
        check("45.2, 63.1", "map", 45.2, 63.1)
        check("45.2 , 63.1", "map", 45.2, 63.1)
        check("45,63", "map", 45, 63)
        check("45; 63", "map", 45, 63)
        check("45,2;63,1", "map", 45.2, 63.1)
        check("45,2 ; 63,1", "map", 45.2, 63.1)
        check("world 1198.2 -1116", "world", 1198.2, -1116)
        check("World 1198.2,-1116", "world", 1198.2, -1116)
        check("WORLD -5,5 7", "world", -5.5, 7)
        check("world 1198.2 , -1116", "world", 1198.2, -1116)
        t:assertNil(parse("hello"))
        t:assertNil(parse("45.2"))
        t:assertNil(parse("45,2,63,1"), "decimal commas with a comma between: ambiguous")
        t:assertNil(parse("45,2, 63,1"), "ambiguous too")
        t:assertNil(parse("145 20"), "map percent above 100")
        t:assertNil(parse("-1 20"), "map percent below 0")
        t:assertNil(parse(nil))
    end,
})
