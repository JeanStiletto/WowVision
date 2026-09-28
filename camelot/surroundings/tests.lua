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
        bridgeUnder = { 0, 5, 500 },
        exits = { 95, 20, 10, 1 },   -- climbed out toward the north
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
    z.bridgeUnder = { 4, 1, 500, 4, 2, 500, 4, 3, 500 }
    z.structs, z.structCells, z.edges, z.pieceCells, z.access, z.links = {}, {}, {}, {}, {}, {}
    z.interiors = { { "Test Bank", 0, 0, 1, -1, 0, 0, -1 } }
    z.rooms = { { 1, "entrance", "room", { 60, 10, 62, 20 } } }
    z.doors = { { 0, 1, 1, 65, 15, 1, 0, 0 } }
    return z
end

-- A road with its centre line: 5 rows x 6 columns of 4 yd cells; north edge at x = 100, west edge
-- at y = 60. Forest with a road on columns 2 and 3 (y 52 to 44) in rows 0 to 3; row 4 a bridge
-- there. The centre line runs north-south at y = 48 from x = 100 to x = 84: the road counts from
-- 2 yd off the line and stops beyond 4 yd.
local function newLaneZone()
    return {
        key = "lane", map = 0, top = 100, left = 60, cell = 4, rows = 5, cols = 6,
        dirs = { "running %s" },
        compass = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" },
        axes = { "north-south", "northeast-southwest", "east-west", "northwest-southeast" },
        places = { { "forest", "forest" }, { "road", "Test road" }, { "bridge", "bridge" } },
        grid = { "100*2,211*2,100*2", "100*2,211*2,100*2", "100*2,211*2,100*2", "100*2,211*2,100*2",
            "100*2,300*2,100*2" },
        lanes = { 100, 48, 84, 48, 211, 20, 40 },
    }
end

-- A canal walk between a square and the water: 4 rows x 7 columns of 4 yd cells; north edge at
-- x = 100, west edge at y = 60. Columns 0 and 1 (y 60 to 52) square, 2 to 4 (y 52 to 40) canal walk,
-- 5 and 6 water (no place). The walk's centre line runs north-south at y = 46: it counts from 2 yd
-- off the line and stops beyond 4 yd.
local function newWalkZone()
    return {
        key = "walk", map = 0, top = 100, left = 60, cell = 4, rows = 4, cols = 7,
        dirs = { "running %s" },
        compass = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" },
        axes = { "north-south", "northeast-southwest", "east-west", "northwest-southeast" },
        places = { { "square", "square of Test" }, { "canal walk", "canal walk" } },
        grid = { "100*2,211*3,0*2", "100*2,211*3,0*2", "100*2,211*3,0*2", "100*2,211*3,0*2" },
        lanes = { 100, 46, 84, 46, 211, 20, 40 },
    }
end

testRunner:addSuite("Surroundings", {
    ["the turn hint says which way to turn to face along the road"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        -- the test road runs north-south; facing is counter-clockwise from north (west = 90)
        t:assertEqual(logic.turnHint(z, 92, 48, 0), 0)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(5)), 0)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(12)), -1)    -- facing a little west of north
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(-30)), 1)    -- facing northeast-ish
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(170)), 1)    -- walking south, 10 degrees off
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(90)), nil)   -- facing across the road
        -- with the said axis (north to south): only while the facing's compass word is north or
        -- south; facing northeast the words tell already
        t:assertEqual(logic.axisOf(z, 211), 1)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(20), 1), -1)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(-30), 1), 0)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(190), 1), -1)
    end,

    ["where the road leads ahead follows its centre line into a gentle bend"] = function(t)
        local z = newLaneZone()
        -- north-south to x = 90, then bending toward the east (y falls) down to x = 80
        z.lanes = { 100, 48, 90, 48, 211, 20, 40, 90, 48, 80, 44, 211, 20, 40 }
        logic.unpack(z)
        local south = math.rad(180)
        local function degrees(a)
            return math.deg(a) % 360
        end
        -- far before the bend the road leads south
        local dir, ahead = logic.wayAhead(z, 98, 48, south, 10)
        t:assertTrue(math.abs(degrees(dir) - 180) < 8)
        t:assertEqual(ahead, 211)
        -- nearer, the road ahead has turned left (east, walking south) by more than 15 degrees
        dir = logic.wayAhead(z, 92, 48, south, 10)
        t:assertTrue(degrees(dir) - 180 > 15)
        -- a step aside does not change where the road leads
        local aside = logic.wayAhead(z, 92, 50, south, 10)
        t:assertTrue(math.abs(degrees(aside) - degrees(dir)) < 1)
        -- facing across the road: no direction
        t:assertEqual(logic.wayAhead(z, 92, 48, math.rad(90), 10), nil)
    end,

    ["a gentle bend is said only while the facing has not turned along it"] = function(t)
        local r = math.rad
        -- walking south (178), the road ahead turns from 180 to 201: turn left
        t:assertEqual(logic.bendTurn(r(180), r(201), r(178), 15), 1)
        -- below the threshold: nothing, the reference stays
        local turn, moveOn = logic.bendTurn(r(180), r(190), r(178), 15)
        t:assertEqual(turn, 0)
        t:assertEqual(moveOn, false)
        -- the road turns right from 155 to 138, the player faces 131 already: nothing, but the
        -- reference moves on (from a walk: "turn slightly right" here carried the player off)
        turn, moveOn = logic.bendTurn(r(155), r(138), r(131), 15)
        t:assertEqual(turn, 0)
        t:assertEqual(moveOn, true)
        -- facing only 5 degrees short of the road: close enough, nothing
        t:assertEqual(logic.bendTurn(r(155), r(138), r(143), 15), 0)
        -- still facing the old way: turn right
        t:assertEqual(logic.bendTurn(r(155), r(138), r(155), 15), -1)
        -- more than 60 degrees: turning round or another road
        t:assertEqual(logic.bendTurn(r(180), r(260), r(180), 15), 0)
    end,

    ["a canal walk counts near its centre line; off it, what lies beside on the player's side"] = function(t)
        local z = newWalkZone()
        logic.unpack(z)
        t:assertEqual(logic.laneValue(z, 94, 46, 211, false), 211)
        -- 4.5 yd off toward the square: the square
        local v, decided = logic.laneValue(z, 94, 50.5, 211, true)
        t:assertEqual(v, 100)
        t:assertEqual(decided, true)
        -- 4.5 yd off toward the water: nothing beside the walk there, it stays the walk (the grid)
        v, decided = logic.laneValue(z, 94, 41.5, 211, true)
        t:assertEqual(v, 211)
        t:assertEqual(decided, false)
        -- the square counts until the walk's line is near
        t:assertEqual(logic.laneValue(z, 94, 49, 211, false), 100)
        -- only road lines when asked for roads
        t:assertEqual(logic.nearestLane(z, 94, 46, 12, { road = true }), nil)
    end,

    ["the road centre line decides when the road counts, with a gap between on and off"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        -- on the line
        t:assertEqual(logic.laneValue(z, 94, 48, 211, false), 211)
        -- 3 yd off, on the grid's road cells: not yet on the road (the forest beside it) ...
        local v, decided = logic.laneValue(z, 94, 51, 211, false)
        t:assertEqual(v, 100)
        t:assertEqual(decided, true)
        -- ... but still on it when already there
        t:assertEqual(logic.laneValue(z, 94, 51, 211, true), 211)
        -- 5 yd off: off the road even from on it
        t:assertEqual(logic.laneValue(z, 94, 53, 100, true), 100)
        -- the bridge keeps its own place
        v, decided = logic.laneValue(z, 82, 48, 300, true)
        t:assertEqual(v, 300)
        t:assertEqual(decided, false)
        -- the nearest point on the line: across the road (3 yd east), past its end the end point
        local d, _i, px, py = logic.nearestLane(z, 94, 51)
        t:assertEqual(d, 3)
        t:assertEqual(logic.compassIndex(px - 94, py - 51), 3)
        d = logic.nearestLane(z, 103, 48)
        t:assertEqual(d, 3)
        t:assertEqual(logic.nearestLane(z, 94, 52, 3), nil)
    end,

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
        logic.unpack(z)
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
        t:assertEqual(logic.underBridge(z, r, c), 500)
        t:assertNil(logic.underBridge(z, 0, 0))
        logic.pack(z)
        t:assertNil(z._index)
    end,

    ["compass words for world offsets (x north, y west)"] = function(t)
        t:assertEqual(logic.compassIndex(10, 0), 1)     -- north
        t:assertEqual(logic.compassIndex(0, -10), 3)    -- east
        t:assertEqual(logic.compassIndex(-10, 10), 6)   -- southwest
        local vx, vy = logic.compassVector(3)
        t:assertEqual(math.floor(vx + 0.5), 0)
        t:assertEqual(math.floor(vy + 0.5), -1)
    end,

    ["pushing against an object names it; only objects of the room, the way one pushes"] = function(t)
        local z = newSquareZone()
        -- a barrel outdoors at 78, 30 (1 yd across); a crate 4 yd long along north-south at 70, 35
        -- (angle 0) in room 1; a counter outdoors east of the crate at 70, 31 (angle 90: its long
        -- axis runs east-west, 2 yd long)
        z.objectNames = { "barrel", "crate", "counter" }
        z.objects = { 78, 30, 5, 5, 0, 1, 0, 70, 35, 20, 5, 0, 2, 1, 70, 31, 10, 3, 90, 3, 0 }
        logic.unpack(z)
        -- at 78, 31.5 pushing east (y falls): the barrel, 1 yd away
        local o, d = logic.objectAhead(z, 78, 31.5, 0, -1, 1.5, 0)
        t:assertEqual(o.name, "barrel")
        t:assertEqual(d, 1)
        t:assertNil(logic.objectAhead(z, 78, 31.5, 0, 1, 1.5, 0))        -- pushing west: nothing
        t:assertNil(logic.objectAhead(z, 78, 31.5, 0, -1, 0.5, 0))       -- too far
        -- beside the crate's long side (x 70, 1 yd west of it), pushing east: the crate, but only
        -- for its room
        t:assertNil(logic.objectAhead(z, 71, 36.5, 0, -1, 1.5, 0))
        o = logic.objectAhead(z, 71, 36.5, 0, -1, 1.5, 1)
        t:assertEqual(o.name, "crate")
        -- the counter's short end is 1 yd from y 31 along its axis: at 70, 29 pushing west
        o = logic.objectAhead(z, 70, 29, 0, 1, 1.5, 0)
        t:assertEqual(o.name, "counter")
    end,

    ["whose wall: the room ahead, by its floor or its outline; a structure's floor"] = function(t)
        local z = newZone()
        -- the barn (room 4, floor x 30 to 40, y 0 to 10) gets an outline a yard wider
        z.rooms[4][5] = { 29, -1, 41, 11 }
        logic.unpack(z)
        t:assertNil(logic.wallOwner(z, 44, 5, -1, 0, 2.5))                   -- the outline 3 yd south: too far
        t:assertEqual(logic.wallOwner(z, 42.5, 5, -1, 0, 2.5), "Test Barn")  -- the outline 1.5 yd south
        -- the dock (a structure with a drop edge) lies under 85, 45
        t:assertEqual(logic.wallOwner(z, 85, 55, 0, -1, 2.5), nil)
        t:assertEqual(logic.wallOwner(z, 85, 51, 0, -1, 2.5), "dock")
    end,

    ["degrees between an offset and a compass direction"] = function(t)
        t:assertEqual(logic.angleOff(10, 0, 1), 0)                     -- due north, north
        t:assertEqual(math.floor(logic.angleOff(10, 4, 1) + 0.5), 22)  -- a bit west of north
        t:assertEqual(math.floor(logic.angleOff(10, 4, 8) + 0.5), 23)  -- and from northwest
        t:assertEqual(logic.angleOff(-10, 0, 1), 180)
    end,

    ["the nearest way out of the water, with its direction"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local i, d, dir, exit = logic.nearestExit(z, 95, 30, 25)
        t:assertEqual(exit.out, 1)                         -- one climbs out toward the north
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

    ["the edge ahead in the view wins over a nearer one; warned edges are left out"] = function(t)
        local z = newZone()
        -- a second dock edge, its drop to the west at y = 40
        z.edges[3] = { 1, 7, 3, 1, 0, 84, 40, 86, 40 }
        logic.unpack(z)
        -- at 87, 36: the north edge 3.6 yd away (north-northeast), the west edge 4.1 yd (west)
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}), 1)
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}, 0), 1)               -- facing north
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}, math.pi / 2), 3)     -- facing west
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}, 3 * math.pi / 2), 1) -- facing east: the north edge ahead left
        -- facing east with the north edge warned: nothing ahead, the nearest other one
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}, 3 * math.pi / 2, { [1] = true }), 3)
        t:assertEqual(logic.nearestEdge(z, 87, 36, 5, {}, 0, { [1] = true }), 3)
        t:assertEqual(math.floor(logic.edgeDistance(z, 3, 87, 36) * 10), 41)
    end,

    ["an edge in the path warns ahead, with its distance; not when walking along it"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- on the dock at 82, 30, its north edge 8 yd ahead when moving north
        local i, along = logic.edgeAhead(z, 82, 30, 1, 0, 10)
        t:assertEqual(i, 1)
        t:assertEqual(along, 8)
        t:assertNil(logic.edgeAhead(z, 82, 30, 1, 0, 5))           -- farther than the look-ahead
        t:assertNil(logic.edgeAhead(z, 82, 30, 0, -1, 10))         -- moving east, along the edge
        t:assertNil(logic.edgeAhead(z, 82, 30, -1, 0, 10))         -- moving away from it
        t:assertNil(logic.edgeAhead(z, 82, 30, 1, 0, 10, {}, { [1] = true }))
    end,

    ["a square's exits leave out ways that lead nowhere"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        -- the street north of the square ends in open land: a dead end
        local exits = logic.aroundItems(region, 78, 35, { classes = { way = true }, leading = true, zone = z })
        t:assertEqual(#exits, 0)
        -- with a road joining the street, it leads on
        z = newSquareZone()
        table.insert(z.places, { "road", "road" })
        z.grid[1] = "300*2,281*2,600,300*2"
        logic.unpack(z)
        region = logic.regionAt(z, 78, 35)
        exits = logic.aroundItems(region, 78, 35, { classes = { way = true }, leading = true, zone = z })
        t:assertEqual(#exits, 1)
        t:assertEqual(exits[1].label, "street of Test")
    end,

    ["cliffs and water near a place: nearest first, directions not neighbours on the compass"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local classes = { ["open land"] = "land", ["deep water"] = "water" }
        local items = logic.featuresAround(z, 75, 35, 35, classes)
        t:assertEqual(items[1].label, "land")
        -- open land 22 yd northeast, 28 northwest, 30 west, 32 east: northeast, then northwest
        t:assertEqual(table.concat(items[1].dirs, "+"), "2+8")
        t:assertEqual(items[2].label, "water")
        t:assertEqual(table.concat(items[2].dirs, "+"), "3")
        items = logic.featuresAround(z, 75, 35, 25, classes)
        t:assertEqual(#items, 1)
        t:assertEqual(table.concat(items[1].dirs, "+"), "2")
        t:assertEqual(#logic.featuresAround(z, 75, 35, 35, classes, { land = true, water = true }), 0)
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
        logic.unpack(z)
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
        local frame = { ox = 100, oy = 200, scale = 1, m00 = 0, m01 = -1, m10 = 1, m11 = 0 }
        -- local (3, 0): world x = 100 - (0*3 + -1*0) = 100, world y = 200 - (1*3 + 0) = 197
        local vx, vy = logic.toBuilding(frame, 100, 197)
        t:assertEqual(math.floor(vx * 1000 + 0.5) / 1000, 3)
        t:assertEqual(math.floor(vy * 1000 + 0.5) / 1000, 0)
    end,

    ["walking through a doorway switches between stacked rooms"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- the common room and the landing cover the same floor; the stairs doorway at y = 5
        t:assertEqual(logic.resolveRoom(z, 5, 7, 1, 5, 3), 2)       -- crossed from -y to +y: upstairs
        t:assertEqual(logic.resolveRoom(z, 5, 3, 2, 5, 7), 1)       -- and back down
        t:assertEqual(logic.resolveRoom(z, 5, 8, 2, 5, 7), 2)       -- no crossing: stay
        t:assertEqual(logic.resolveRoom(z, 9, 5, 3, 12, 5), 2)      -- back room through its door
        t:assertNil(logic.crossedDoor(z, 3, 30, 5, 29, 5))          -- far from any doorway
    end,

    ["entrances: doorways to outside in world yards, with the room unless it is the entrance"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- the only outside door: common room of the Test Inn (its frame equals world x and y)
        local list = logic.entrances(z)
        t:assertEqual(#list, 1)
        t:assertEqual(list[1].text, "Test Inn, common room")
        -- a flat opening: the common room's way out is south (from its middle), so one goes in north
        t:assertEqual(list[1].inDir, 1)
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
        logic.unpack(z)
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

    ["a street leading on from a short opening is a beginning, with the way it leads on"] = function(t)
        local z = newSquareZone()
        table.insert(z.places, { "road", "road of Test" })
        z.grid[1] = "300*2,281*2,600,300*2"   -- the street goes on into a road
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local list = logic.wayBeginnings(z, region)
        t:assertEqual(#list, 1)
        t:assertEqual(list[1].label, "street of Test")
        t:assertEqual(list[1].kind, "street")
        t:assertEqual(list[1].onward, 1)   -- north: along its axis, away from the square
        local i, d, dir, b = logic.nearestBeginning(z, region, 78, 35, 30)
        t:assertEqual(i, 1)
        t:assertEqual(b, list[1])
        t:assertEqual(math.floor(d + 0.5), 20)
        t:assertEqual(dir, 8)
        t:assertNil(logic.nearestBeginning(z, region, 78, 35, 15))   -- out of reach
    end,

    ["a street along the square's side and a street leading nowhere are no beginnings"] = function(t)
        local z = newSquareZone()
        table.insert(z.places, { "road", "road of Test" })
        -- along the west side (rows 1 to 3, 20 yd of border), going on into a road at the north
        z.grid = { "600,300*6", "281,100*5,300", "281,100*5,400", "281,100*5,400", "0*7" }
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        t:assertEqual(#logic.wayBeginnings(z, region), 0)
        -- the plain test square: its street meets no other way
        z = newSquareZone()
        logic.unpack(z)
        t:assertEqual(#logic.wayBeginnings(z, logic.regionAt(z, 78, 35)), 0)
    end,

    ["a room names its doorways with their fixed direction, the way out first"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- common room: the way out (a flat opening: from the room's middle 5, 5 toward 0, 5:
        -- south), the upstairs landing through a doorway at y 5 with the landing on its +y side
        -- (west)
        local items = logic.roomDoorways(z, 1)
        t:assertEqual(#items, 2)
        t:assertEqual(items[1].class, "way out")
        t:assertEqual(items[1].dirs[1], 5)
        t:assertEqual(items[2].label, "upstairs landing")
        t:assertEqual(items[2].dirs[1], 7)
        -- the same from the landing's side: the common room east, the back room north
        items = logic.roomDoorways(z, 2)
        t:assertEqual(items[1].label, "back room")
        t:assertEqual(items[1].dirs[1], 1)
        t:assertEqual(items[2].label, "common room")
        t:assertEqual(items[2].dirs[1], 3)
        -- more than the count: the one the player came through goes first
        t:assertEqual(logic.roomDoorways(z, 1, { max = 1, cameFrom = 0 })[1].label, "upstairs landing")
        t:assertEqual(logic.roomDoorways(z, 1, { max = 1, cameFrom = 2 })[1].class, "way out")
    end,

    ["the client's language replaces the data's words, the logic keeps working"] = function(t)
        local z = newZone()
        z.rooms[3][2] = "entrance"
        z.locales = {
            deDE = {
                dirs = { "Wasser im %s", "tiefes Wasser im %s", "Land im %s", "Abgrund im %s",
                    "Felswand im %s", "Gebäude im %s", "im %s", "%s" },
                compass = { "Norden", "Nordosten", "Osten", "Südosten", "Süden", "Südwesten", "Westen", "Nordwesten" },
                axes = { "Nord nach Süd", "Nordost nach Südwest", "Ost nach West", "Nordwest nach Südost" },
                places = { { "Wald" }, { "Ufer, Testsee" }, { "Brücke" }, { "offenes Gelände" },
                    { "tiefes Wasser, Testsee" }, { "beim Brunnen", "Teststraße im Norden" } },
                interiors = { "Testgasthaus", "Testscheune" },
                rooms = { "Schankraum", "Obergeschoss", "Eingang", "Scheune" },
                structs = { "Dock", "Mauer" },
            },
        }
        logic.unpack(z, "deDE")
        t:assertEqual(logic.describe(z, 213, true), "Ufer, Testsee, Wasser im Osten")
        t:assertEqual(logic.describe(z, 383, true), "Brücke, Ost nach West")
        t:assertEqual(logic.axisOf(z, 383), 3)
        t:assertEqual(logic.describe(z, 600, true), "beim Brunnen, Teststraße im Norden")
        t:assertEqual(logic.describeRoom(z, 1, nil), "Testgasthaus, Schankraum")
        t:assertEqual(z.structs[2], "Mauer")
        t:assertEqual(z.rooms[3].entrance, true)
        t:assertEqual(z.locales, nil)
        t:assertEqual(logic.entrances(z)[1].text, "Testgasthaus, Schankraum")
        -- once per zone
        logic.pack(z)
        logic.unpack(z, "frFR")
        t:assertEqual(logic.describe(z, 100, true), "Wald")
    end,

    ["without the client's language the English words stay"] = function(t)
        local z = newZone()
        z.locales = { deDE = { places = { { "Wald" } } } }
        logic.unpack(z, "enUS")
        t:assertEqual(logic.describe(z, 383, true), "bridge, east to west")
        t:assertEqual(logic.describe(z, 100, true), "forest")
    end,

    ["outdoor keys: roads and canals with their direction, other places by the place"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        t:assertEqual(logic.outdoorKey(z, 100), 1)
        t:assertEqual(logic.outdoorKey(z, 211), "r211")
        t:assertNil(logic.outdoorKey(z, 0))
        t:assertEqual(logic.isRoadKey("r211"), true)
        t:assertEqual(logic.keyPlace("r211"), 2)
        t:assertEqual(logic.keyLabel(z, "r211"), "Test road")
        t:assertEqual(logic.keyLabel(z, 3), "bridge")
    end,

    ["swimming under a bridge: the water, never decided by a centre line"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.outdoorValue(z, 95, 5, false, false), 383)   -- on the bridge
        local v, decided = logic.outdoorValue(z, 95, 5, true, true)
        t:assertEqual(v, 500)
        t:assertEqual(decided, false)
        t:assertEqual(logic.outdoorValue(z, 75, 30, false, false), 0)    -- no data
    end,

    ["things around are said as a list with their directions"] = function(t)
        local z = newZone()
        t:assertEqual(logic.joinWords({ "north" }), "north")
        t:assertEqual(logic.joinWords({ "north", "west" }), "north and west")
        t:assertEqual(logic.joinWords({ "north", "west", "south" }), "north, west and south")
        local text = logic.itemsText(z, {
            { label = "street of Test", class = "way", dirs = { 1, 7 } },
            { label = "cliff edge", class = "cliff edge", dirs = { 3 } },
            { label = "Test Bank", class = "entrance", dirs = {} },
        })
        t:assertEqual(text, "street of Test to the north and west, cliff edge to the east, entrance of Test Bank here")
    end,

    ["a drop edge says its direction first, then the drop; ahead with its distance"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.edgeText(z, 1), "north, drop into water")
        t:assertEqual(logic.edgeText(z, 2, 7.6), "south in 8 yards, drop 12 yards")
    end,

    ["guidance names a target once, and the way through only where it differs"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- 10 yd north of the inn's door (world 0, 5); one goes in toward the north
        local target = logic.footTarget(z, 7, 5)
        t:assertEqual(target.kind, "entrance")
        t:assertEqual(logic.guideText(z, target, true, false), "entrance of Test Inn, common room, 7 to the south, in to the north")
        t:assertEqual(logic.guideText(z, target, false, false), "entrance, 7 to the south")
        t:assertEqual(logic.guideText(z, target, false, true), "at the entrance, in to the north")
        t:assertNil(logic.footTarget(z, 20, 5))   -- beyond the guidance reach
        target = logic.exitTarget(z, 95, 30)
        t:assertEqual(logic.guideText(z, target, true, false), "way out of the water, 10 to the east, out to the north")
    end,

    ["a room says its doorways, at most the count, the way the player came left out first"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 1, nil, false), "Test Inn, common room, way out to the south, upstairs landing to the west")
        t:assertEqual(logic.roomText(z, 1, 2, true), "common room, way out to the south, upstairs landing to the west")
    end,

    ["a square says its ways on, and where it lies the nearest road"] = function(t)
        local z = newSquareZone()
        table.insert(z.places, { "road", "road of Test" })
        z.grid[1] = "300*2,281*2,600,300*2"
        logic.unpack(z)
        local text, region, said = logic.spotText(z, 78, 35, 100, nil, { cut = true })
        t:assertEqual(text, "square of Test, street of Test to the north")
        t:assertEqual(region.label, "square of Test")
        -- the street's mouth counts as said (not said again on coming close); the water does not
        for _, m in ipairs(region.mouths) do
            t:assertEqual(said[m], m.class == "way" or nil)
        end
        -- the describe key also names the building entrances and what is farther
        text = logic.spotText(z, 78, 35, 100, nil, {})
        t:assertEqual(text, "square of Test, street of Test to the north, entrance of Test Bank to the southeast")
    end,
})
