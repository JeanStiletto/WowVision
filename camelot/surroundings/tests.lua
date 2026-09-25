local testRunner = WowVision.testing.testRunner
local logic = WowVision.surroundingsLogic

-- A tiny zone: 3 rows x 6 columns of 10 yd cells; north edge at x = 100, west edge at y = 60.
-- Row 0: forest | shore (water to the east) | bridge (running east-west)
-- Row 1: open land everywhere; row 2: outside the data.
local function newZone()
    return {
        key = "test", map = 0, top = 100, left = 60, cell = 10, rows = 3, cols = 6,
        dirs = { "water to the %s", "deep water to the %s", "land to the %s", "drop to the %s",
            "rock wall to the %s", "building to the %s", "to the %s", "running %s" },
        compass = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" },
        axes = { "north-south", "northeast-southwest", "east-west", "northwest-southeast" },
        places = {
            { "forest", "forest" },
            { "shore", "shore of Test Lake" },
            { "bridge", "bridge" },
            { "open land", "open land" },
            { "deep water", "deep water of Test Lake" },
        },
        grid = { "100*2,213*2,383*2", "400*6", "0*6" },
        bridgeUnder = { 0, 5, 5 },
        -- frames chosen so that the building frame equals world x and y
        interiors = { { "Test Inn", 0, 0, 1, -1, 0, 0, -1 }, { "Test Barn", 0, 0, 1, -1, 0, 0, -1 } },
        rooms = {
            { 1, "common room", "large hall", { 0, 0, 10, 10 } },
            { 1, "upstairs landing", "stairs", { 0, 0, 10, 10 } },   -- stacked over the common room
            { 1, "back room", "room", { 11, 0, 20, 10 } },
            { 2, "barn", "large hall", { 30, 0, 40, 10 } },
        },
        -- doors {room a, room b, interior, centre x, y, facing nx, ny, side of room a}:
        -- outside to the common room; back room to the upstairs landing (a doorway at x = 10.5,
        -- the back room on its +x side); common room to landing, the stairs, at y = 5 (common
        -- room on the -y side)
        doors = {
            { 0, 1, 1, 0, 5, 1, 0, 0 },
            { 3, 2, 1, 10.5, 5, 1, 0, 1 },
            { 1, 2, 1, 5, 5, 0, 1, -1 },
        },
    }
end

testRunner:addSuite("Surroundings", {
    ["a position finds its cell value; west and south of the edges is outside"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- x = 95 is row 0; y = 55 is column 0 (y grows west, columns grow east)
        t:assertEqual(logic.valueAt(z, 95, 55), 100)
        t:assertEqual(logic.valueAt(z, 95, 25), 213)   -- column 3
        t:assertEqual(logic.valueAt(z, 95, 5), 383)    -- column 5
        t:assertEqual(logic.valueAt(z, 85, 30), 400)   -- row 1
        t:assertEqual(logic.valueAt(z, 75, 30), 0)     -- row 2: no data
        t:assertEqual(logic.valueAt(z, 105, 30), 0)    -- north of the data
        t:assertEqual(logic.covers(z, 95, 55), true)
        t:assertEqual(logic.covers(z, 95, 70), false)
    end,

    ["a value speaks its place and direction"] = function(t)
        local z = newZone()
        t:assertEqual(logic.describe(z, 213, true), "shore of Test Lake, water to the east")
        t:assertEqual(logic.describe(z, 213, false), "shore of Test Lake")
        t:assertEqual(logic.describe(z, 383, true), "bridge, east to west")
        t:assertEqual(logic.describe(z, 100, true), "forest")
        t:assertNil(logic.describe(z, 900, true))
    end,

    ["the water under a bridge is known per cell"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local _v, r, c = logic.valueAt(z, 95, 5)
        t:assertEqual(logic.underBridge(z, r, c), 5)
        t:assertNil(logic.underBridge(z, 0, 0))
        logic.pack(z)
        t:assertNil(z._rows)
    end,

    ["a place counts only after walking the entry distance inside it"] = function(t)
        local e = logic.newEntry(8)
        t:assertEqual(e:update("forest", 0, 0), "forest")      -- first place: at once
        t:assertNil(e:update("forest", 0, 1))
        t:assertNil(e:update("road", 0, 2))                    -- just stepped onto the road
        t:assertNil(e:update("road", 0, 6))                    -- 4 yd in
        t:assertNil(e:update("forest", 0, 7))                  -- back: no flicker
        t:assertNil(e:update("road", 0, 8))
        t:assertNil(e:update("road", 0, 12))
        t:assertEqual(e:update("road", 0, 16), "road")         -- 8 yd on the road
        t:assertNil(e:update("road", 0, 30))
        t:assertNil(e:update(nil, 0, 31))                      -- no data: keep the current place
        t:assertEqual(e.current, "road")
        e:reset()
        t:assertEqual(e:update("forest", 0, 40), "forest")
    end,

    ["a key can have its own entry distance"] = function(t)
        local e = logic.newEntry(8)
        e.distanceFor = function(key)
            return key == "road" and 3 or nil
        end
        e:update("forest", 0, 0)
        t:assertNil(e:update("road", 0, 1))
        t:assertEqual(e:update("road", 0, 4), "road")          -- 3 yd are enough on a road
        t:assertNil(e:update("forest", 0, 5))
        t:assertNil(e:update("forest", 0, 9))
        t:assertEqual(e:update("forest", 0, 13), "forest")     -- the rest keeps 8 yd
    end,

    ["stacked rooms: keep the current room, or the one behind a door, else stay unknown"] = function(t)
        local z = newZone()
        -- (5, 5) lies in the common room and the upstairs landing
        t:assertEqual(#logic.roomCandidates(z, 5, 5), 2)
        t:assertNil(logic.resolveRoom(z, 5, 5, nil))           -- after a reset: unknown
        t:assertEqual(logic.resolveRoom(z, 15, 5, nil), 3)     -- the back room is unambiguous
        t:assertEqual(logic.resolveRoom(z, 5, 5, 3), 2)        -- from the back room the door leads upstairs
        t:assertEqual(logic.resolveRoom(z, 5, 5, 1), 1)        -- already in the common room: stay
        t:assertEqual(logic.resolveRoom(z, 35, 5, 1), 4)
        t:assertNil(logic.resolveRoom(z, 50, 50, 1))
    end,

    ["a rotated building frame turns world positions into building positions"] = function(t)
        -- a building turned 90 degrees at world (100, 200): m = {{0,-1},{1,0}}, ox = 100, oy = 200
        local frame = { "Turned", 100, 200, 1, 0, -1, 1, 0 }
        -- local (3, 0): world x = 100 - (0*3 + -1*0) = 100, world y = 200 - (1*3 + 0) = 197
        local vx, vy = logic.toBuilding(frame, 100, 197)
        t:assertEqual(math.floor(vx * 1000 + 0.5) / 1000, 3)
        t:assertEqual(math.floor(vy * 1000 + 0.5) / 1000, 0)
    end,

    ["walking through a doorway switches between stacked rooms"] = function(t)
        local z = newZone()
        -- the common room and the landing cover the same floor; the stairs doorway at y = 5
        t:assertEqual(logic.resolveRoom(z, 5, 7, 1, 5, 3), 2)       -- crossed from -y to +y: upstairs
        t:assertEqual(logic.resolveRoom(z, 5, 3, 2, 5, 7), 1)       -- and back down
        t:assertEqual(logic.resolveRoom(z, 5, 8, 2, 5, 7), 2)       -- no crossing: stay
        t:assertEqual(logic.resolveRoom(z, 9, 5, 3, 12, 5), 2)      -- back room through its door
        t:assertNil(logic.crossedDoor(z, 3, 30, 5, 29, 5))          -- far from any doorway
    end,

    ["a room names its interior when the interior changes"] = function(t)
        local z = newZone()
        t:assertEqual(logic.describeRoom(z, 1, nil), "Test Inn, common room")
        t:assertEqual(logic.describeRoom(z, 3, 1), "back room")
        t:assertEqual(logic.describeRoom(z, 4, 3), "Test Barn, barn")
    end,
})
