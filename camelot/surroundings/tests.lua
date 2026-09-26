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
            { "landmark", "at the well", "Test road to the north" },
        },
        grid = { "100*2,213*2,383*2", "400*6", "0*6" },
        bridgeUnder = { 0, 5, 5 },
        exits = { 95, 20, 10 },
        -- a dock over row 1, columns 1 and 2 (world y 40 to 20), its north side a drop into water;
        -- a wall over row 1, columns 4 and 5, its wall-walk (high piece 1) dropping 12 yd to the
        -- south at x = 81; stepped onto from the ground at its east end (x 88, y 1) or out of a
        -- building at x 85, y 25; the wall-walk joins a tower top (piece 2) over row 0, column 4
        structs = { "dock", "wall" },
        structCells = { 1, 1, 1, 1, 2, 1, 1, 4, 2, 1, 5, 2 },
        edges = {
            { 1, 1, 3, 1, 0, 90, 34, 90, 32, 90, 30, 90, 28, 90, 26 },
            { 2, 5, 12, 0, 1, 81, 14, 81, 12 },
        },
        pieceCells = { 1, 4, 1, 1, 5, 1, 0, 4, 2 },
        access = { 1, 1, 88, 1, 1, 2, 85, 25 },
        links = { 1, 2 },
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

-- A square in a city: 5 rows x 7 columns of 10 yd cells; north edge at x = 100, west edge at
-- y = 70. The square fills rows 1 to 3, columns 1 to 5; a street (running north-south) meets it
-- at row 0, columns 2 and 3; deep water east of it (rows 2 and 3, column 6); a canal (no place,
-- said while swimming) south of it (row 4, columns 1 to 3); open land elsewhere; the Test Bank's
-- door on its south-east corner.
local function newSquareZone()
    local z = newZone()
    z.rows, z.cols, z.top, z.left = 5, 7, 100, 70
    z.places = {
        { "square", "square of Test" },
        { "street", "street of Test" },
        { "open land", "open land" },
        { "deep water", "deep water of Test" },
        { "canal", "canal of Test" },
    }
    z.grid = { "300*2,281*2,300*3", "300,100*5,300", "300,100*5,400", "300,100*5,400", "0*7" }
    z.bridgeUnder = { 4, 1, 5, 4, 2, 5, 4, 3, 5 }
    z.structs, z.structCells, z.edges, z.pieceCells, z.access, z.links = {}, {}, {}, {}, {}, {}
    z.interiors = { { "Test Bank", 0, 0, 1, -1, 0, 0, -1 } }
    z.rooms = { { 1, "entrance", "room", { 60, 10, 62, 20 } } }
    z.doors = { { 0, 1, 1, 65, 15, 1, 0, 0 } }
    return z
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
        t:assertEqual(logic.describe(z, 673, true), "at the well, to the east, Test road to the north")
        t:assertEqual(logic.describe(z, 673, false), "at the well")
        -- leaving a road: the live road hint replaces the stored nearest road
        t:assertEqual(logic.describe(z, 673, true, true), "at the well, to the east")
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

    ["compass words for world offsets (x north, y west)"] = function(t)
        t:assertEqual(logic.compassIndex(10, 0), 1)     -- north
        t:assertEqual(logic.compassIndex(0, -10), 3)    -- east
        t:assertEqual(logic.compassIndex(-10, 10), 6)   -- southwest
        local vx, vy = logic.compassVector(3)
        t:assertEqual(math.floor(vx + 0.5), 0)
        t:assertEqual(math.floor(vy + 0.5), -1)
    end,

    ["the nearest way out of the water, with its direction"] = function(t)
        local z = newZone()
        local i, d, dir = logic.nearestExit(z, 95, 30, 25)
        t:assertEqual(i, 1)
        t:assertEqual(d, 10)
        t:assertEqual(dir, 3)                              -- y 20 is east of y 30
        t:assertNil(logic.nearestExit(z, 95, 60, 25))
    end,

    ["a drop edge warns only on the structure, in front of the edge"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local i, d = logic.nearestEdge(z, 88, 30, 3)       -- on the dock, 2 yd from its north side
        t:assertEqual(i, 1)
        t:assertEqual(d, 2)
        t:assertNil(logic.nearestEdge(z, 85, 30, 3))       -- 5 yd away
        t:assertNil(logic.nearestEdge(z, 88, 55, 3))       -- beside the dock: too far from the edge
        t:assertNil(logic.nearestEdge(z, 91, 30, 3))       -- beyond the edge (in the water)
    end,

    ["a wall-walk's edge warns only after stepping onto it, not from below"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local high = {}
        -- walking along the foot of the wall: under the wall-walk, never on it
        logic.updateHigh(z, high, 85, 35)
        logic.updateHigh(z, high, 83, 14)
        t:assertNil(high[1])
        t:assertNil(logic.nearestEdge(z, 83, 14, 3, high))
        -- up at the east end, then along the wall-walk to its edge
        logic.updateHigh(z, high, 88, 2)
        t:assertEqual(high[1], true)
        logic.updateHigh(z, high, 83, 14)
        t:assertEqual(high[1], true)
        local i, d = logic.nearestEdge(z, 83, 14, 3, high)
        t:assertEqual(i, 2)
        t:assertEqual(d, 2)
        -- the joined tower top counts while walking over to it
        t:assertEqual(high[2], true)
        -- off the wall's footprint: forgotten
        logic.updateHigh(z, high, 85, 35)
        t:assertNil(high[1])
        t:assertNil(high[2])
    end,

    ["coming out of a building onto a wall-walk counts; walking past that spot does not"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local high = {}
        logic.updateHigh(z, high, 86, 25, false)
        t:assertNil(high[1])
        logic.updateHigh(z, high, 86, 25, true)
        t:assertEqual(high[1], true)
        -- the tower top alone is not stepped onto from below
        local other = {}
        logic.updateHigh(z, other, 95, 15)
        t:assertNil(other[2])
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
        t:assertEqual(e:update("forest", 0, 8), "forest")      -- leaving the road: 3 yd as well
        t:assertNil(e:update("open land", 0, 9))
        t:assertNil(e:update("open land", 0, 13))
        t:assertEqual(e:update("open land", 0, 17), "open land") -- the rest keeps 8 yd
    end,

    ["the nearest road from off the road, with its direction"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- from the forest cell (row 0, column 0) the bridge is 4 cells east
        local d, dir = logic.nearestOfKinds(z, 95, 55, { bridge = true }, 45)
        t:assertEqual(d, 40)
        t:assertEqual(dir, 3)
        t:assertNil(logic.nearestOfKinds(z, 95, 55, { bridge = true }, 20))
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

    ["entrances: doorways to outside in world yards, with the room unless it is the entrance"] = function(t)
        local z = newZone()
        -- the only outside door: common room of the Test Inn (its frame equals world x and y)
        local list = logic.entrances(z)
        t:assertEqual(#list, 1)
        t:assertEqual(list[1].text, "Test Inn, common room")
        t:assertEqual(list[1].x, 0)
        t:assertEqual(list[1].y, 5)
        local i, d, dir = logic.nearestEntrance(z, 10, 5, 15)
        t:assertEqual(i, 1)
        t:assertEqual(d, 10)
        t:assertEqual(dir, 5)                              -- the door lies south
        t:assertNil(logic.nearestEntrance(z, 40, 5, 15))
    end,

    ["a room names its interior when the interior changes"] = function(t)
        local z = newZone()
        t:assertEqual(logic.describeRoom(z, 1, nil), "Test Inn, common room")
        t:assertEqual(logic.describeRoom(z, 3, 1), "back room")
        t:assertEqual(logic.describeRoom(z, 4, 3), "Test Barn, barn")
    end,

    ["a square finds what borders it: streets, canals, water and entrances, not open land"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        t:assertEqual(logic.isAroundPlace(z, 100), true)
        t:assertEqual(logic.isAroundPlace(z, 281), false)   -- a street with a direction
        t:assertEqual(logic.isAroundPlace(z, 200), true)    -- a street without one
        t:assertEqual(logic.isAroundPlace(z, 300), false)
        local region = logic.regionAt(z, 78, 35)
        t:assertEqual(logic.regionAt(z, 65, 55), region)    -- the same square, cached
        t:assertNil(logic.regionAt(z, 95, 65))              -- open land
        local items = logic.aroundItems(region, 78, 35)
        local said = {}
        for _, item in ipairs(items) do
            said[#said + 1] = item.label .. " " .. table.concat(item.dirs, "+")
        end
        -- nearest first: street 17 yd north, canal 23 south, entrance 24 southeast, water 30 east
        t:assertEqual(table.concat(said, ", "), "street of Test 1, canal 5, Test Bank 4, water 3")
        t:assertEqual(items[2].class, "canal")
        t:assertEqual(items[3].class, "entrance")
    end,

    ["a square says at most the count; the way the player came goes first"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        t:assertEqual(#logic.aroundItems(region, 78, 35, { max = 4, cameFrom = "street of Test" }), 4)   -- fits: kept
        local items = logic.aroundItems(region, 78, 35, { max = 3, cameFrom = "street of Test" })
        t:assertEqual(#items, 3)
        t:assertEqual(items[1].label, "canal")
        items = logic.aroundItems(region, 78, 35, { max = 2, cameFrom = "somewhere else" })
        t:assertEqual(items[1].label, "street of Test")
        t:assertEqual(items[2].label, "canal")
        -- things already said are left out (back on the square soon after leaving it)
        local said = { [items[1].mouths[1]] = true }
        items = logic.aroundItems(region, 78, 35, { said = said })
        t:assertEqual(#items, 3)
        t:assertEqual(items[1].label, "canal")
    end,

    ["stepping onto a square names its nearest way on, not the nearer water or canal"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local region = logic.regionAt(z, 62, 35)   -- canal 7 yd south, street 33 yd north
        local items = logic.aroundItems(region, 62, 35, { max = 1, classes = { way = true } })
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "street of Test")
        t:assertEqual(items[1].dirs[1], 1)
    end,

    ["a thing meeting the square in several places says its nearest directions, at most the count"] = function(t)
        local z = newSquareZone()
        -- the street meets the square from the north (columns 3 and 4, apart from the other
        -- mouth) and from the west (rows 2 and 3, column 0)
        z.grid[1] = "300*3,281*2,300*2"
        z.grid[3] = "281,100*5,400"
        z.grid[4] = "281,100*5,400"
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local street = logic.aroundItems(region, 78, 35)[1]
        t:assertEqual(street.label, "street of Test")
        t:assertEqual(table.concat(street.dirs, "+"), "1+7")   -- north (17 yd), then west (30 yd)
        street = logic.aroundItems(region, 78, 35, { dirs = 1 })[1]
        t:assertEqual(table.concat(street.dirs, "+"), "1")
    end,

    ["on a square each thing is said once when the player comes close; entrances are not"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local said = {}
        local items = logic.approaching(region, 78, 35, 18, said)
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "street of Test")
        t:assertEqual(#logic.approaching(region, 78, 35, 18, said), 0)   -- once
        items = logic.approaching(region, 56, 40, 18, said)
        t:assertEqual(#items, 1)                                         -- the canal; the entrance stays with the guidance
        t:assertEqual(items[1].label, "canal")
    end,

    ["a room names its doorways, nearest first; the one the player came through goes first"] = function(t)
        local z = newZone()
        local items = logic.roomDoorways(z, 1, 5, 9)
        t:assertEqual(#items, 2)
        t:assertEqual(items[1].label, "upstairs landing")
        t:assertEqual(items[1].dirs[1], 3)                 -- east (y grows west)
        t:assertEqual(items[2].class, "out")
        t:assertEqual(items[2].dirs[1], 4)                 -- southeast
        t:assertEqual(logic.roomDoorways(z, 1, 5, 9, { max = 1, cameFrom = 0 })[1].label, "upstairs landing")
        t:assertEqual(logic.roomDoorways(z, 1, 5, 9, { max = 1, cameFrom = 2 })[1].class, "out")
        -- right at a doorway: no direction
        t:assertEqual(#logic.roomDoorways(z, 1, 0.5, 5)[1].dirs, 0)
    end,
})
