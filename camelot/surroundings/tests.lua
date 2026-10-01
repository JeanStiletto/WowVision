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
        grid = { "10000*2,21090*2,38090*2", "40000*6", "0*6" },
        bridgeUnder = { 0, 5, 50000 },
        exits = { 95, 20, 10, 0 },   -- climbed out toward the north (angle 0)
        -- a dock over row 1, columns 1 and 2 (world y 40 to 20), its north side a drop into water;
        -- a wall over row 1, columns 4 and 5, its wall-walk (high piece 1) dropping 12 yd to the
        -- south at x = 81; stepped onto from the ground at its east end (x 88, y 1) or out of a
        -- building at x 85, y 25; the wall-walk joins a tower top (piece 2) over row 0, column 4
        structs = { "dock", "wall" },
        structCells = { 1, 1, 1, 1, 2, 1, 1, 4, 2, 1, 5, 2 },
        edges = {
            { 1, 0, 3, 1, 0, 90, 34, 90, 32, 90, 30, 90, 28, 90, 26 },
            { 2, 180, 12, 0, 1, 81, 14, 81, 12 },
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
    z.grid = { "30000*2,28000*2,30000*3", "30000,10000*5,30000", "30000,10000*5,40000", "30000,10000*5,40000", "0*7" }
    z.bridgeUnder = { 4, 1, 50000, 4, 2, 50000, 4, 3, 50000 }
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
        grid = { "10000*2,21000*2,10000*2", "10000*2,21000*2,10000*2", "10000*2,21000*2,10000*2", "10000*2,21000*2,10000*2",
            "10000*2,30000*2,10000*2" },
        lanes = { 100, 48, 84, 48, 21000, 20, 40 },
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
        grid = { "10000*2,21000*3,0*2", "10000*2,21000*3,0*2", "10000*2,21000*3,0*2", "10000*2,21000*3,0*2" },
        lanes = { 100, 46, 84, 46, 21000, 20, 40 },
    }
end

-- A city hall with an indoor layer: newZone's grid and places plus a hall place; one interior
-- (frame = world) with a great hall of 1200 sq yd (x 80 to 100, y 10 to 40), a shop west of it
-- (y 40 to 50), a passage south of it running north-south (x 70 to 80, y 0 to 10) and winding
-- stairs; doors: hall to shop at x 90, y 40; hall to passage at x 80, y 5; outside to the hall at
-- x 100, y 25. The layer covers the hall: rows 0 and 1 hall; a lava edge of the hall at x 72 facing south.
local function newHallZone()
    local z = newZone()
    table.insert(z.places, { "hall", "great hall of Test" }) -- place 7
    table.insert(z.places, { "pier", "pier of Test" }) -- place 8
    z.interiors = { { "Test City", 0, 0, 1, -1, 0, 0, -1 } }
    z.rooms = {
        { 1, "great hall", "large hall", { 80, 10, 100, 40 }, f = 1200 },
        { 1, "shop", "room", { 80, 40, 100, 50 }, f = 150, s = 1 },
        { 1, "passage", "corridor", { 70, 0, 80, 10 }, f = 90, a = 0 },
        { 1, "stairs", "stairs", { 70, 50, 80, 60 }, f = 40, w = -1 },
    }
    z.doors = {
        { 1, 2, 1, 90, 40, 0, 1, -1 },
        { 1, 3, 1, 80, 5, 1, 0, 1 },
        { 0, 1, 1, 100, 25, 0, 0, 0 },
    }
    z.indoor = {
        rooms = { 1 },
        grid = { "70000*6", "70000*6", "0*6" },
        lanes = {},
        structs = { "Test City" }, waterStructs = { 1 },
        structCells = { 1, 1, 1, 1, 2, 1 },
        edges = { { 1, 180, 80, 3, 1, 72, 20, 72, 22 } }, -- its floor belongs to the great hall (room 1)
    }
    return z
end

testRunner:addSuite("Surroundings", {
    ["the indoor layer covers the big halls; an unknown room counts where every candidate is covered"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        local layer = logic.layer(z)
        t:assertEqual(layer ~= nil, true)
        t:assertEqual(logic.inLayer(layer, 1, 95, 25), true)
        t:assertEqual(logic.inLayer(layer, 2, 85, 45), false)
        t:assertEqual(logic.inLayer(layer, nil, 95, 25), true)
        t:assertEqual(logic.inLayer(layer, nil, 85, 45), false)
        -- the layer's places are the zone's
        t:assertEqual(logic.describe(layer, logic.valueAt(layer, 95, 25), true), "great hall of Test")
    end,

    ["the indoor layer's doorways: a shop by entrance, a passage by name, the way outside"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        local layer = logic.layer(z)
        local texts = {}
        for _, e in ipairs(logic.entrances(layer)) do
            texts[#texts + 1] = e.text .. (e.plain and " (plain)" or "")
        end
        t:assertEqual(table.concat(texts, "; "), "shop; passage (plain); way outside (plain)")
        local shop = logic.footTarget(layer, 90, 36, nil)
        t:assertEqual(logic.guideText(layer, shop, true, false), "entrance of shop, 4 to the west")
        local passage = logic.footTarget(layer, 84, 6, nil)
        t:assertEqual(logic.guideText(layer, passage, true, false), "passage, 4 to the south")
        t:assertEqual(logic.guideText(layer, passage, false, true), "through to the south")
    end,

    ["lava edges of the indoor layer warn like drop edges"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        local layer = logic.layer(z)
        -- it warns in its own room only (the flat grid holds every level)
        t:assertEqual(logic.nearestEdge(layer, 74, 21, 3, { [1] = true }, nil, nil), 1)
        t:assertEqual(logic.nearestEdge(layer, 74, 21, 3, { [3] = true }, nil, nil), nil)
        t:assertEqual(logic.edgeText(layer, 1), "south, lava")
        t:assertEqual(logic.edgeText(layer, 1, 6.2), "6 south, lava")
    end,

    ["a big room says its doorways from where the player stands, nearest first"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 1, nil, false, 95, 25),
            "Test City, great hall, way out to the north, shop to the west, passage to the southeast")
        -- without a position (or in a small room) the fixed directions stay
        t:assertEqual(logic.roomText(z, 3, 1, false, 75, 5), "passage, north to south, great hall to the north")
        -- guidance to the nearest doorway of the big room
        local target = logic.roomDoorTarget(z, 1, 96, 25)
        t:assertEqual(logic.guideText(z, target, true, false), "way outside, 4 to the north")
        t:assertEqual(logic.roomDoorTarget(z, 3, 76, 6), nil)
    end,

    ["winding stairs say which way they turn going up"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 4, 1, false), "stairs, winding, turns right going up")
    end,

    ["a pier is a way with a direction, like a street"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.outdoorKey(z, 88000), "r8:0")
        t:assertEqual(logic.describe(z, 88000, true), "pier of Test, north to south")
    end,

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
        t:assertEqual(logic.axisOf(z, 21000), 0)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(20), 0), -1)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(-30), 0), 0)
        t:assertEqual(logic.turnHint(z, 92, 48, math.rad(190), 0), -1)
    end,

    ["where the road leads ahead follows its centre line into a gentle bend"] = function(t)
        local z = newLaneZone()
        -- north-south to x = 90, then bending toward the east (y falls) down to x = 80
        z.lanes = { 100, 48, 90, 48, 21000, 20, 40, 90, 48, 80, 44, 21000, 20, 40 }
        logic.unpack(z)
        local south = math.rad(180)
        local function degrees(a)
            return math.deg(a) % 360
        end
        -- far before the bend the road leads south
        local dir, ahead = logic.wayAhead(z, 98, 48, south, 10)
        t:assertTrue(math.abs(degrees(dir) - 180) < 8)
        t:assertEqual(ahead, 21000)
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
        t:assertEqual(logic.laneValue(z, 94, 46, 21000, false), 21000)
        -- 4.5 yd off toward the square, still on a cell of the walk: the walk goes on, the line
        -- did not decide (user 2026-10-01: "I walk up a whatever and am on it")
        local v, decided = logic.laneValue(z, 94, 50.5, 21000, true)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, false)
        -- 8.5 yd off, on the square's cells: the square
        v, decided = logic.laneValue(z, 94, 54.5, 10000, true)
        t:assertEqual(v, 10000)
        t:assertEqual(decided, true)
        -- 4.5 yd off toward the water: nothing beside the walk there, it stays the walk (the grid)
        v, decided = logic.laneValue(z, 94, 41.5, 21000, true)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, false)
        -- from the square, 3 yd off the line on the walk's cells: the walk's cell, but not by the
        -- line (the entry distance still counts before it is said)
        v, decided = logic.laneValue(z, 94, 49, 21000, false)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, false)
        -- only road lines when asked for roads
        t:assertEqual(logic.nearestLane(z, 94, 46, 12, { road = true }), nil)
    end,

    ["a stretch's width per side: a wall on one side no longer narrows the other"] = function(t)
        local z = newWalkZone()
        -- the walk's line runs south along y = 46; left of that direction is east (y below 46):
        -- enter 2, leave 4 there; right (west) enter 1.5, leave 3; the cells west of y = 48 square
        z.grid = { "10000*3,21000*2,0*2", "10000*3,21000*2,0*2", "10000*3,21000*2,0*2", "10000*3,21000*2,0*2" }
        z.laneFields = 10
        z.lanes = { 100, 46, 84, 46, 21000, 20, 40, 15, 30, 0 }
        logic.unpack(z)
        local _d, lane = logic.nearestLane(z, 94, 42)
        t:assertEqual(logic.laneSide(lane, 94, 42), 1)
        t:assertEqual(logic.laneSide(lane, 94, 50), 2)
        local enter, leave = logic.laneWidths(lane, 94, 42)
        t:assertEqual(enter, 2)
        t:assertEqual(leave, 4)
        enter, leave = logic.laneWidths(lane, 94, 50)
        t:assertEqual(enter, 1.5)
        t:assertEqual(leave, 3)
        -- 3.5 yd off: on the walk to the east (the line decided), off it to the west
        local v, decided = logic.laneValue(z, 94, 42.5, 21000, true)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, true)
        v, decided = logic.laneValue(z, 94, 49.5, 10000, true)
        t:assertEqual(v, 10000)
        t:assertEqual(decided, true)
        -- data with one width per stretch (7 or 8 fields) counts it on both sides
        z = newWalkZone()
        logic.unpack(z)
        _d, lane = logic.nearestLane(z, 94, 50)
        enter, leave = logic.laneWidths(lane, 94, 50)
        t:assertEqual(enter, 2)
        t:assertEqual(leave, 4)
    end,

    ["the road centre line decides when the road counts, with a gap between on and off"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        -- on the line
        t:assertEqual(logic.laneValue(z, 94, 48, 21000, false), 21000)
        -- 3 yd off, on the grid's road cells: the road's cell, but not decided by the line (the
        -- entry distance counts before it is said; before 2026-10-01 the forest beside it) ...
        local v, decided = logic.laneValue(z, 94, 51, 21000, false)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, false)
        -- ... and on it by the line when already there
        t:assertEqual(logic.laneValue(z, 94, 51, 21000, true), 21000)
        -- 5 yd off: off the road even from on it
        t:assertEqual(logic.laneValue(z, 94, 53, 10000, true), 10000)
        -- the bridge keeps its own place
        v, decided = logic.laneValue(z, 82, 48, 30000, true)
        t:assertEqual(v, 30000)
        t:assertEqual(decided, false)
        -- the nearest point on the line: across the road (3 yd east), past its end the end point
        local d, _i, px, py = logic.nearestLane(z, 94, 51)
        t:assertEqual(d, 3)
        t:assertEqual(logic.bearingOf(px - 94, py - 51), 90)
        d = logic.nearestLane(z, 103, 48)
        t:assertEqual(d, 3)
        t:assertEqual(logic.nearestLane(z, 94, 52, 3), nil)
    end,

    ["a position finds its cell value; west and south of the edges is outside"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- x = 95 is row 0; y = 55 is column 0 (y grows west, columns grow east)
        t:assertEqual(logic.valueAt(z, 95, 55), 10000)
        t:assertEqual(logic.valueAt(z, 95, 25), 21090)   -- column 3: shore, water to the east (90)
        t:assertEqual(logic.valueAt(z, 95, 5), 38090)    -- column 5: bridge running east-west
        t:assertEqual(logic.valueAt(z, 85, 30), 40000)   -- row 1
        t:assertEqual(logic.valueAt(z, 75, 30), 0)     -- row 2: no data
        t:assertEqual(logic.valueAt(z, 105, 30), 0)    -- north of the data
        t:assertEqual(logic.covers(z, 95, 55), true)
        t:assertEqual(logic.covers(z, 95, 70), false)
    end,

    ["a value speaks its place and direction"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.describe(z, 21090, true), "shore of Test Lake, water to the east")
        t:assertEqual(logic.describe(z, 21090, false), "shore of Test Lake")
        t:assertEqual(logic.describe(z, 38090, true), "bridge, east to west")
        -- an angle between the words takes the nearest word: 110 degrees is still east
        t:assertEqual(logic.describe(z, 38110, true), "bridge, east to west")
        t:assertEqual(logic.describe(z, 21110, true), "shore of Test Lake, water to the east")
        t:assertEqual(logic.describe(z, 10000, true), "forest")
        t:assertEqual(logic.describe(z, 67090, true), "at the well, to the east, Test road to the north")
        t:assertEqual(logic.describe(z, 67090, false), "at the well")
        -- leaving a road: the live road hint replaces the stored nearest road
        t:assertEqual(logic.describe(z, 67090, true, true), "at the well, to the east")
        t:assertNil(logic.describe(z, 90000, true))
    end,

    ["the water under a bridge is known per cell"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local _v, r, c = logic.valueAt(z, 95, 5)
        t:assertEqual(logic.underBridge(z, r, c), 50000)
        t:assertNil(logic.underBridge(z, 0, 0))
        logic.pack(z)
        t:assertNil(z._index)
    end,

    ["bearings for world offsets (x north, y west), and their words"] = function(t)
        t:assertEqual(logic.bearingOf(10, 0), 0)       -- north
        t:assertEqual(logic.bearingOf(0, -10), 90)     -- east
        t:assertEqual(logic.bearingOf(-10, 10), 225)   -- southwest
        t:assertEqual(logic.wordIndex(100), 3)         -- east
        t:assertEqual(logic.wordIndex(350), 1)         -- north
        t:assertEqual(logic.hourOf(100), 3)
        t:assertEqual(logic.hourOf(350), 12)
        t:assertEqual(logic.hourOf(0), 12)
        t:assertEqual(logic.hourOf(165), 6)
        local vx, vy = logic.compassVector(90)
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
        t:assertEqual(logic.angleOff(10, 0, 0), 0)                     -- due north, north
        t:assertEqual(math.floor(logic.angleOff(10, 4, 0) + 0.5), 22)  -- a bit west of north
        t:assertEqual(math.floor(logic.angleOff(10, 4, 315) + 0.5), 23)  -- and from northwest
        t:assertEqual(logic.angleOff(-10, 0, 0), 180)
    end,

    ["the nearest way out of the water, with its direction"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local i, d, dir, exit = logic.nearestExit(z, 95, 30, 25)
        t:assertEqual(exit.out, 0)                         -- one climbs out toward the north
        t:assertEqual(i, 1)
        t:assertEqual(d, 10)
        t:assertEqual(dir, 90)                             -- y 20 is east of y 30
        t:assertNil(logic.nearestExit(z, 95, 60, 25))
    end,

    ["a moat: its edge says moat, its way out is found from anywhere down in it"] = function(t)
        local z = newZone()
        z.edges[1][4] = 4   -- the dock's edge now drops into a moat
        logic.unpack(z)
        t:assertEqual(logic.edgeText(z, 1), "north, moat")
        t:assertEqual(logic.edgeText(z, 1, 6.2), "6 north, moat")
        t:assertNil(logic.exitTarget(z, 95, 60))                       -- as a swimmer: too far
        local target = logic.exitTarget(z, 95, 60, true)               -- down in the moat: 40 yd away
        t:assertEqual(target.name, "way out of the moat")
        t:assertEqual(target.through, 0)
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
        z.edges[3] = { 1, 270, 3, 1, 0, 84, 40, 86, 40 }
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
        z.grid[1] = "30000*2,28000*2,60000,30000*2"
        logic.unpack(z)
        region = logic.regionAt(z, 78, 35)
        exits = logic.aroundItems(region, 78, 35, { classes = { way = true }, leading = true, zone = z })
        t:assertEqual(#exits, 1)
        t:assertEqual(exits[1].label, "street of Test")
    end,

    ["a street to another piece of the same square leads on"] = function(t)
        -- the lane through Stormwind's gate: forecourt and district are both "square of Trade
        -- District" (one place), joined only by the street; the street is an exit of the forecourt
        local z = newSquareZone()
        z.grid[1] = "30000,10000*5,30000"
        z.grid[2] = "30000*2,28000*2,30000*3"
        z.grid[3] = "30000,10000*5,30000"
        z.grid[4] = "30000,10000*5,40000"
        z.grid[5] = "0*7"
        logic.unpack(z)
        local region = logic.regionAt(z, 68, 35)
        t:assertEqual(region.cells[0 * z.cols + 1], nil)   -- the far piece is not this region
        local exits = logic.aroundItems(region, 68, 35, { classes = { way = true }, leading = true, zone = z })
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
        t:assertEqual(logic.wordIndex(items[1].dirs[1]) .. "+" .. logic.wordIndex(items[1].dirs[2]), "2+8")
        t:assertEqual(items[2].label, "water")
        t:assertEqual(logic.wordIndex(items[2].dirs[1]), 3)
        items = logic.featuresAround(z, 75, 35, 25, classes)
        t:assertEqual(#items, 1)
        t:assertEqual(#items[1].dirs, 1)
        t:assertEqual(logic.wordIndex(items[1].dirs[1]), 2)
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
        t:assertEqual(dir, 90)
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

    ["no floor right under the player: a floor within the slack names the room (the tram over its pit)"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- the barn's floor ends at x = 40: 1.5 yd beyond it no floor is under the player
        t:assertEqual(#logic.roomCandidates(z, 41.5, 5), 0)
        t:assertEqual(logic.resolveRoom(z, 41.5, 5, 1), 4)     -- left the common room's area: the barn
        t:assertNil(logic.resolveRoom(z, 43, 5, 1))            -- 3 yd off: nothing
    end,

    ["no floor under the player but still in the current room's area: stay in it"] = function(t)
        local z = newZone()
        -- the barn's floor in two pieces with a gap from x 34 to 36; the back room reaches into it
        z.rooms[4][4] = { 30, 0, 34, 10, 36, 0, 40, 10 }
        z.rooms[3][4] = { 11, 0, 20, 10, 35, 11, 35.5, 11.5 }
        logic.unpack(z)
        t:assertTrue(logic.inRoomArea(z, 4, 35, 5))
        t:assertEqual(logic.resolveRoom(z, 35, 9.8, 4), 4)     -- the back room's floor is near, the barn's area holds
        t:assertNil(logic.resolveRoom(z, 35, 9.8, 1))          -- coming from elsewhere: two floors near, unknown
    end,

    ["rooms differing only by their number are one name"] = function(t)
        local z = newZone()
        z.rooms[3][2] = "common room 2"
        logic.unpack(z)
        t:assertTrue(logic.sameRoomName(z, 1, 3))              -- common room, common room 2
        t:assertFalse(logic.sameRoomName(z, 1, 2))             -- common room, upstairs landing
        t:assertFalse(logic.sameRoomName(z, 1, 4))             -- another building
    end,

    ["a hall the game calls outdoors counts while the game's map is the hall's"] = function(t)
        local z = newZone()
        z.rooms[4].g = 1455   -- the barn: a hall like Ironforge's, on UI map 1455
        logic.unpack(z)
        t:assertTrue(logic.isHallMap(z, 1455))
        t:assertFalse(logic.isHallMap(z, 1426))
        t:assertFalse(logic.isHallMap(z, nil))
        t:assertTrue(logic.inHall(z, 35, 5, 1455))
        t:assertTrue(logic.inHall(z, 41.5, 5, 1455))           -- within the slack
        t:assertFalse(logic.inHall(z, 35, 5, 1426))            -- the game's map elsewhere: the ground above
        t:assertFalse(logic.inHall(z, 5, 5, 1455))             -- the inn is no such hall
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
        t:assertTrue(logic.angleGap(list[1].inDir, 0) < 10)   -- north, a few degrees off (an angle, not an index)
        t:assertEqual(list[1].x, 0)
        t:assertEqual(list[1].y, 5)
        local i, d, dir = logic.nearestEntrance(z, 10, 5, 15)
        t:assertEqual(i, 1)
        t:assertEqual(d, 10)
        t:assertEqual(dir, 180)                            -- the door lies south
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
        t:assertEqual(logic.isAroundPlace(z, 10000), true)
        t:assertEqual(logic.isAroundPlace(z, 28000), false)   -- a street with a direction
        t:assertEqual(logic.isAroundPlace(z, 20000), false)   -- a street without one: a way, as a road
        t:assertEqual(logic.isAroundPlace(z, 30000), false)
        local region = logic.regionAt(z, 78, 35)
        t:assertEqual(logic.regionAt(z, 65, 55), region)    -- the same square, cached
        t:assertNil(logic.regionAt(z, 95, 65))              -- open land
        local items = logic.aroundItems(region, 78, 35)
        local said = {}
        for _, item in ipairs(items) do
            said[#said + 1] = item.label .. " " .. logic.wordIndex(item.dirs[1])
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
        t:assertEqual(items[1].dirs[1], 0)
    end,

    ["a thing meeting the square in several places says its nearest directions, at most the count"] = function(t)
        local z = newSquareZone()
        -- the street meets the square from the north (columns 3 and 4, apart from the other
        -- mouth) and from the west (rows 2 and 3, column 0)
        z.grid[1] = "30000*3,28000*2,30000*2"
        z.grid[3] = "28000,10000*5,40000"
        z.grid[4] = "28000,10000*5,40000"
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local street = logic.aroundItems(region, 78, 35)[1]
        t:assertEqual(street.label, "street of Test")
        t:assertEqual(logic.wordIndex(street.dirs[1]) .. "+" .. logic.wordIndex(street.dirs[2]), "1+7")   -- north (17 yd), then west (30 yd)
        street = logic.aroundItems(region, 78, 35, { dirs = 1 })[1]
        t:assertEqual(#street.dirs, 1)
        t:assertEqual(logic.wordIndex(street.dirs[1]), 1)
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
        z.grid[1] = "30000*2,28000*2,60000,30000*2"   -- the street goes on into a road
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local list = logic.wayBeginnings(z, region)
        t:assertEqual(#list, 1)
        t:assertEqual(list[1].label, "street of Test")
        t:assertEqual(list[1].kind, "street")
        t:assertEqual(list[1].onward, 0)   -- north: along its axis, away from the square
        local i, d, dir, b = logic.nearestBeginning(z, region, 78, 35, 30)
        t:assertEqual(i, 1)
        t:assertEqual(b, list[1])
        t:assertEqual(math.floor(d + 0.5), 20)
        t:assertEqual(logic.wordIndex(dir), 8)
        -- reached from the reach plus half the opening's width (10 yd here)
        t:assertNil(logic.nearestBeginning(z, region, 78, 35, 10))   -- 15: out of reach
        t:assertEqual(logic.nearestBeginning(z, region, 78, 35, 16), 1)   -- 21
    end,

    ["a street along the square's side and a street leading nowhere are no beginnings"] = function(t)
        local z = newSquareZone()
        table.insert(z.places, { "road", "road of Test" })
        -- along the west side (rows 1 to 4, 30 yd of border), going on into a road at the north
        z.grid = { "60000,30000*6", "28000,10000*5,30000", "28000,10000*5,40000", "28000,10000*5,40000", "28000,10000*5,40000" }
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
        t:assertEqual(items[1].dirs[1], 180)
        t:assertEqual(items[2].label, "upstairs landing")
        t:assertEqual(items[2].dirs[1], 270)
        -- the same from the landing's side: the common room east, the back room north
        items = logic.roomDoorways(z, 2)
        t:assertEqual(items[1].label, "back room")
        t:assertEqual(items[1].dirs[1], 0)
        t:assertEqual(items[2].label, "common room")
        t:assertEqual(items[2].dirs[1], 90)
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
        t:assertEqual(logic.describe(z, 21090, true), "Ufer, Testsee, Wasser im Osten")
        t:assertEqual(logic.describe(z, 38090, true), "Brücke, Ost nach West")
        t:assertEqual(logic.axisOf(z, 38090), 90)
        t:assertEqual(logic.describe(z, 60000, true), "beim Brunnen, Teststraße im Norden")
        t:assertEqual(logic.describeRoom(z, 1, nil), "Testgasthaus, Schankraum")
        t:assertEqual(z.structs[2], "Mauer")
        t:assertEqual(z.rooms[3].entrance, true)
        t:assertEqual(z.locales, nil)
        t:assertEqual(logic.entrances(z)[1].text, "Testgasthaus, Schankraum")
        -- once per zone
        logic.pack(z)
        logic.unpack(z, "frFR")
        t:assertEqual(logic.describe(z, 10000, true), "Wald")
    end,

    ["without the client's language the English words stay"] = function(t)
        local z = newZone()
        z.locales = { deDE = { places = { { "Wald" } } } }
        logic.unpack(z, "enUS")
        t:assertEqual(logic.describe(z, 38090, true), "bridge, east to west")
        t:assertEqual(logic.describe(z, 10000, true), "forest")
    end,

    ["outdoor keys: roads and canals with their direction, other places by the place"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        t:assertEqual(logic.outdoorKey(z, 10000), 1)
        t:assertEqual(logic.outdoorKey(z, 21000), "r2:0")
        -- the key quantizes the angle to the spoken words: 20 degrees is still north-south, 30 is not
        t:assertEqual(logic.outdoorKey(z, 21020), "r2:0")
        t:assertEqual(logic.outdoorKey(z, 21030), "r2:1")
        -- on the piece already: its key sticks while the heading stays near the word said
        t:assertEqual(logic.outdoorKey(z, 21030, "r2:0"), "r2:0")
        t:assertEqual(logic.outdoorKey(z, 21040, "r2:0"), "r2:1")   -- clearly northeast-southwest now
        t:assertEqual(logic.outdoorKey(z, 21015, "r2:1"), "r2:1")   -- and back only once clearly north-south
        t:assertEqual(logic.outdoorKey(z, 21010, "r2:1"), "r2:0")
        t:assertEqual(logic.outdoorKey(z, 21030, "r3:0"), "r2:1")   -- another piece: no sticking
        t:assertNil(logic.outdoorKey(z, 0))
        t:assertEqual(logic.isWayKey("r2:0"), true)
        t:assertEqual(logic.keyPlace("r2:0"), 2)
        t:assertEqual(logic.keyLabel(z, "r2:0"), "Test road")
        t:assertEqual(logic.keyLabel(z, 3), "bridge")
    end,

    ["swimming under a bridge: the water, never decided by a centre line"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.outdoorValue(z, 95, 5, false, false), 38090)   -- on the bridge
        local v, decided = logic.outdoorValue(z, 95, 5, true, true)
        t:assertEqual(v, 50000)
        t:assertEqual(decided, false)
        t:assertEqual(logic.outdoorValue(z, 75, 30, false, false), 0)    -- no data
    end,

    ["things around are said as a list with their directions"] = function(t)
        local z = newZone()
        t:assertEqual(logic.joinWords({ "north" }), "north")
        t:assertEqual(logic.joinWords({ "north", "west" }), "north and west")
        t:assertEqual(logic.joinWords({ "north", "west", "south" }), "north, west and south")
        local text = logic.itemsText(z, {
            { label = "street of Test", class = "way", dirs = { 0, 270 } },
            { label = "cliff edge", class = "cliff edge", dirs = { 100 } },
            { label = "Test Bank", class = "entrance", dirs = {} },
        })
        t:assertEqual(text, "street of Test to the north and west, cliff edge to the east, entrance of Test Bank here")
    end,

    ["a drop edge says its direction first, then the drop; ahead with its distance"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.edgeText(z, 1), "north, water")
        t:assertEqual(logic.edgeText(z, 2, 7.6), "8 south, drop 12")
    end,

    ["an edge with a depth per point says the depth at the point nearest the player"] = function(t)
        local z = newZone()
        -- the wall-walk's edge: 3 yd deep at its first point (81, 14), 12 at the second (81, 12)
        z.edges[2].d = { 3, 12 }
        logic.unpack(z)
        t:assertEqual(logic.edgeText(z, 2, nil, 82, 14.5), "south, drop 3")
        t:assertEqual(logic.edgeText(z, 2, 7.6, 82, 11.5), "8 south, drop 12")
        -- without the player's position the edge's one value
        t:assertEqual(logic.edgeText(z, 2), "south, drop 12")
    end,

    ["guidance names a target once, and the way through only where it differs"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- 10 yd north of the inn's door (world 0, 5); one goes in toward the north
        local target = logic.footTarget(z, 7, 5)
        t:assertEqual(target.kind, "entrance")
        t:assertEqual(logic.guideText(z, target, true, false), "entrance of Test Inn, common room, 7 to the south, in to the north")
        -- a repeat: the yards and the direction; at it: the way through (user 2026-10-01)
        t:assertEqual(logic.guideText(z, target, false, false), "7 south")
        t:assertEqual(logic.guideText(z, target, false, true), "in to the north")
        t:assertEqual(logic.guideText(z, target, true, true), "in to the north")
        t:assertNil(logic.footTarget(z, 20, 5))   -- beyond the guidance reach
        target = logic.exitTarget(z, 95, 30)
        t:assertEqual(logic.guideText(z, target, true, false), "way out of the water, 10 to the east, out to the north")
    end,

    ["at a doorway only in front of it: beside the door the entrance is still guided to"] = function(t)
        local z = newZone()
        logic.unpack(z)
        -- the inn's door at (0, 5), one goes in toward the north: 2 yd south of it, in line
        local target = logic.footTarget(z, 2, 5)
        t:assertEqual(target.kind, "entrance")
        t:assertEqual(logic.atTarget(z, target, 2, 5), true)
        -- 2.7 yd away but 2.5 yd beside the line through the door: not at it
        target = logic.footTarget(z, 1, 7.5)
        t:assertEqual(logic.atTarget(z, target, 1, 7.5), false)
        t:assertEqual(logic.guideText(z, target, false, false), "3 east")
    end,

    ["a climb's foot on the way is guided to like an entrance"] = function(t)
        local z = newWalkZone()
        z.dirs = { "running %s", "up to the %s" }
        z.places = { { "square", "square of Test" }, { "ramp", "ramp to the bank" } }
        z.grid = { "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2" }
        z.lanes = {}
        -- the ramp's foot at (92, 44), the ramp rising to the northeast; a second foot of the
        -- same ramp 2 yd away is the same target
        z.climbFeet = { 92, 44, 22045, 90, 44, 22045 }
        logic.unpack(z)
        t:assertEqual(#z._index.climbFeet, 1)
        -- 6 yd west of the foot (y 50): the ramp by name with its rise, then only the yards and
        -- the direction, at it only the rise
        local target = logic.footTarget(z, 92, 50)
        t:assertEqual(target.kind, "climb")
        t:assertEqual(logic.guideText(z, target, true, false), "ramp to the bank, 6 to the east, up to the northeast")
        t:assertEqual(logic.guideText(z, target, false, false), "6 east")
        t:assertEqual(logic.guideText(z, target, false, true), "up to the northeast")
        target = logic.footTarget(z, 92, 44.8)
        t:assertEqual(logic.atTarget(z, target, 92, 44.8), true)
        -- 1.2 yd beside the line through the foot (north-west of it): not at it, still
        -- "1 southeast" (never "0")
        target = logic.footTarget(z, 92.85, 44.85)
        t:assertEqual(logic.atTarget(z, target, 92.85, 44.85), false)
        t:assertEqual(logic.guideText(z, target, false, false), "1 southeast")
        -- beyond the reach: nothing
        t:assertNil(logic.footTarget(z, 92, 58))
        -- with the line's bearing in the data (climbFeetFields 4): the ramp really runs at 60
        -- degrees, so 1.5 yd back along that line is at the foot, 1.5 yd beside the line is not
        z.climbFeetFields = 4
        z.climbFeet = { 92, 44, 22045, 60 }
        logic.pack(z)
        logic.unpack(z)
        target = logic.footTarget(z, 91.25, 45.3)
        t:assertEqual(logic.atTarget(z, target, 91.25, 45.3), true)
        target = logic.footTarget(z, 93.3, 44.75)
        t:assertEqual(logic.atTarget(z, target, 93.3, 44.75), false)
        -- the foot stays the target until the player is more than 3 yd past it up the line
        t:assertEqual(logic.pastTarget(z, target, 93.3, 44.75), false)
        target = logic.footTarget(z, 94, 40.5)   -- 4 yd up the line (bearing 60)
        t:assertEqual(logic.pastTarget(z, target, 94, 40.5), true)
        target = logic.footTarget(z, 90, 47.5)   -- 4 yd before the foot
        t:assertEqual(logic.pastTarget(z, target, 90, 47.5), false)
    end,

    ["the guidance target stays unless another is clearly nearer"] = function(t)
        local list = { { x = 0, y = 0 }, { x = 10, y = 0 } }
        -- nearer to the second by 1 yd, the first guided to last: the first stays
        local i = logic.nearestPoint(list, 5.5, 0, 20, { x = 0, y = 0 })
        t:assertEqual(i, 1)
        -- nearer by 3 yd: the second
        i = logic.nearestPoint(list, 6.5, 0, 20, { x = 0, y = 0 })
        t:assertEqual(i, 2)
        -- without a last target the nearest
        i = logic.nearestPoint(list, 5.5, 0, 20)
        t:assertEqual(i, 2)
        -- the reach plus half an opening, capped: a 30 yd wide opening from 15 yd, not 23
        t:assertEqual(logic.beginningReach(8, { span = 30 }), 15)
        t:assertEqual(logic.beginningReach(8, { span = 10 }), 13)
    end,

    ["a way out of the water onto floor that joins nothing says it leads to a dead end"] = function(t)
        local z = newZone()
        z.deadExits = { 1 }
        logic.unpack(z)
        local target = logic.exitTarget(z, 95, 30)
        t:assertEqual(logic.guideText(z, target, true, false), "way out of the water to a dead end, 10 to the east, out to the north")
        t:assertEqual(logic.guideText(z, target, false, false), "way out to a dead end, 10 to the east")
        t:assertEqual(logic.guideText(z, target, false, true), "at the way out to a dead end, out to the north")
    end,

    ["a neighbouring square is an exit even where it meets no other way"] = function(t)
        local z = newZone()
        -- square A on columns 0 to 2, square B (touching nothing else) on columns 3 to 5
        z.places = { { "square", "square of A" }, { "square", "square of B" } }
        z.grid = { "10000*3,20000*3", "10000*3,20000*3", "10000*3,20000*3" }
        logic.unpack(z)
        local region = logic.regionAt(z, 85, 45)
        local items = logic.aroundItems(region, 85, 45, { classes = { way = true }, leading = true, zone = z })
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "square of B")
    end,

    ["a street beside the opening to a square it only joins is a side street"] = function(t)
        -- square A on columns 0 to 2; square B on columns 4 and 5 and, rows 0 and 1, on column 3
        -- too (touching A); a street on column 3, rows 2 and 3, joining only A and B
        local function zoneWith(noContact)
            local z = newZone()
            z.rows = 4
            z.places = { { "square", "square of A" }, { "square", "square of B" }, { "street", "street to B" } }
            z.grid = { "10000*3,20000*3", "10000*3,20000*3", "10000*3,30000,20000*2", "10000*3,30000,20000*2" }
            z.noContact = noContact
            logic.unpack(z)
            local region = logic.regionAt(z, 85, 45)
            return logic.aroundItems(region, 85, 45, { classes = { way = true }, leading = true, zone = z })
        end
        -- one can walk from A into B: the opening is the way, the street is left out
        local items = zoneWith(nil)
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "square of B")
        -- the heights say A and B do not touch there: the street is the way to B
        items = zoneWith({ 0, 2, 0, 3, 1, 2, 1, 3 })
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "street to B")
    end,

    ["on a city walk the next piece is found ahead"] = function(t)
        local z = newWalkZone()
        -- the walk runs north-south to x = 88, then turns southeast (y falls) as a piece of its own
        z.lanes = { 100, 46, 88, 46, 21000, 20, 40, 88, 46, 84, 42, 21045, 20, 40 }
        logic.unpack(z)
        local value, yards = logic.pieceAhead(z, 96, 46, math.pi, 21000, logic.AHEAD_LOOK)
        t:assertEqual(value, 21045)
        -- the distance along the line (8 yd to the bend, then onto the next stretch)
        t:assertEqual(math.floor(yards * 10 + 0.5) / 10, 9.4)
        t:assertEqual(logic.describe(z, value, true), "canal walk, northeast to southwest")
        -- walking north, away from it: nothing ahead
        t:assertNil(logic.pieceAhead(z, 96, 46, 0, 21000, logic.AHEAD_LOOK))
    end,

    ["a raised piece over other floor says its place only up on it, and its lines count only there"] = function(t)
        local z = newWalkZone()
        -- a landing (high piece 1) over the walk's cells (row 2, columns 2 and 3): up on it the
        -- square's value (100), below it the walk's (211); stepped onto from the ground at x 90,
        -- y 50; its line runs at y = 48 over the walk's line at y = 46
        z.stacked = { 2, 2, 1, 10000, 21000, 2, 3, 1, 10000, 21000 }
        z.piecePlaces = { 1, 2 }
        z.pieceCells = { 2, 2, 1, 2, 3, 1 }
        z.access = { 1, 1, 90, 50 }
        z.laneFields = 8
        z.lanes = { 100, 46, 84, 46, 21000, 20, 40, 0, 92, 48, 88, 48, 10000, 20, 40, 1 }
        logic.unpack(z)
        local high = {}
        logic.setOn(z, high)
        -- below: the walk and its line
        t:assertEqual(logic.valueAt(z, 90, 50), 21000)
        local _d, lane = logic.nearestLane(z, 90, 47)
        t:assertEqual(lane.value, 21000)
        -- stepping onto the landing: its value, its line; the walk's line below does not count
        local _on, changed = logic.updateHigh(z, high, 90, 50)
        t:assertEqual(high[1], true)
        t:assertEqual(changed, true)
        t:assertEqual(logic.valueAt(z, 90, 50), 10000)
        _d, lane = logic.nearestLane(z, 90, 47)
        t:assertEqual(lane.value, 10000)
        _on, changed = logic.updateHigh(z, high, 90, 50)
        t:assertEqual(changed, false)
        -- off its footprint: below again
        logic.updateHigh(z, high, 90, 58)
        t:assertNil(high[1])
        t:assertEqual(logic.valueAt(z, 90, 50), 21000)
        -- a cell of its footprint painted with another place and not stacked under it is beside
        -- the piece, not on it (the bay beside the griffon ramp): with the walk (place 2) among its
        -- floor the player stays on it there, with the square alone not
        z.pieceCells = { 2, 2, 1, 2, 3, 1, 2, 4, 1 }
        logic.pack(z)
        logic.unpack(z)
        logic.setOn(z, high)
        logic.updateHigh(z, high, 90, 50)
        t:assertEqual(high[1], true)
        logic.updateHigh(z, high, 90, 42)
        t:assertEqual(high[1], true)
        high[1] = nil
        -- a step onto it counts only from a cell painted with its own floor: with the square
        -- (place 1) as its floor, the walk's cell is not
        z.piecePlaces = { 1, 1 }
        logic.pack(z)
        logic.unpack(z)
        logic.setOn(z, high)
        logic.updateHigh(z, high, 90, 50)
        t:assertNil(high[1])
        high[1] = true
        logic.updateHigh(z, high, 90, 42)
        t:assertNil(high[1])
    end,

    ["the next piece ahead is one the line leads onto, not a line beside it"] = function(t)
        local z = newWalkZone()
        -- the walk's line ends at x = 88; a stretch of another piece runs 5 yd beside it (y = 51)
        z.lanes = { 100, 46, 88, 46, 21000, 20, 40, 92, 51, 84, 51, 21045, 20, 40 }
        logic.unpack(z)
        -- walking south along the line: it ends, the line beside it is no next piece
        t:assertNil(logic.pieceAhead(z, 96, 46, math.pi, 21000, logic.AHEAD_LOOK))
        -- a stretch meeting the line's end is
        z.lanes = { 100, 46, 88, 46, 21000, 20, 40, 88, 46, 88, 30, 21045, 20, 40 }
        logic.pack(z)
        logic.unpack(z)
        local value, yards = logic.pieceAhead(z, 96, 46, math.pi, 21000, logic.AHEAD_LOOK)
        t:assertEqual(value, 21045)
        t:assertEqual(yards, 8)
    end,

    ["streets follow the road rules: keyed by direction, and off one it says where it is"] = function(t)
        local z = newWalkZone()
        z.places[1] = { "grass", "grass" }
        logic.unpack(z)
        t:assertEqual(logic.outdoorKey(z, 21000), "r2:0")
        t:assertEqual(logic.isWayKey(logic.outdoorKey(z, 21000)), true)
        -- stepped off the walk onto the grass, 11 yd west of its centre line
        t:assertEqual(logic.spotText(z, 92, 57, 10000, "r2:0", { cut = true }), "grass, street to the east")
        -- the describe key says it too; an announcement coming from elsewhere does not
        t:assertEqual(logic.spotText(z, 92, 57, 10000, nil, {}), "grass, street to the east")
        t:assertEqual(logic.spotText(z, 92, 57, 10000, nil, { cut = true }), "grass")
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
        z.grid[1] = "30000*2,28000*2,60000,30000*2"
        logic.unpack(z)
        local text, region, said = logic.spotText(z, 78, 35, 10000, nil, { cut = true })
        t:assertEqual(text, "square of Test, street of Test to the north")
        t:assertEqual(region.label, "square of Test")
        -- the street's mouth counts as said (not said again on coming close); the water does not
        for _, m in ipairs(region.mouths) do
            t:assertEqual(said[m], m.class == "way" or nil)
        end
        -- the describe key also names the building entrances and what is farther
        text = logic.spotText(z, 78, 35, 10000, nil, {})
        t:assertEqual(text, "square of Test, street of Test to the north, entrance of Test Bank to the southeast")
    end,

    ["a stop says what to wait for and which way it will be; outdoors only open floor, indoors its room"] = function(t)
        local z = newZone()
        -- a ship lying along x = 75 south of row 1 (y 40 to 20); a lift in the back room (room 3)
        -- whose car stands at x 95, y 5, its landing the cell of row 0, column 5
        z.stops = {
            { "ship", "Test Harbor", 0, { 1, 1, 1, 2 }, { 75, 40, 75, 20 } },
            { "lift down", "", 3, { 0, 5 }, { 95, 5, 95, 5 } },
        }
        z.locales = { deDE = { stops = { "Testhafen", "" } } }
        logic.unpack(z)
        local i = logic.stopAt(z, 85, 35, nil)
        t:assertEqual(i, 1)
        t:assertEqual(logic.stopText(z, i, 85, 35), "wait for the ship to Test Harbor, ship to the south")
        -- beyond the ship's end it lies to the southeast
        t:assertEqual(logic.stopText(z, i, 85, 45), "wait for the ship to Test Harbor, ship to the southeast")
        -- a stop in a room: not outdoors, only in its room
        t:assertEqual(logic.stopAt(z, 95, 5, nil), nil)
        t:assertEqual(logic.stopAt(z, 95, 5, { [1] = true }), nil)
        t:assertEqual(logic.stopAt(z, 95, 5, { [3] = true }), 2)
        t:assertEqual(logic.stopText(z, 2, 95, 9), "wait for the lift down, lift to the east")
        -- no stop off its cells
        t:assertEqual(logic.stopAt(z, 75, 35, nil), nil)
    end,

    ["a stop's destination comes in the client's language"] = function(t)
        local z = newZone()
        z.stops = { { "tram", "Stormwind City", 0, { 1, 0 }, { 80, 50, 80, 58 } } }
        z.locales = { deDE = { stops = { "Sturmwind" } } }
        logic.unpack(z, "deDE")
        t:assertEqual(logic.stopText(z, 1, 85, 55), "wait for the tram to Sturmwind, tram to the south")
    end,

    ["a ramp is a way keyed like a street, said with the way up; its side is named when bumped"] = function(t)
        local z = newWalkZone()
        -- the walk's columns (y 52 to 40) are a ramp rising to the northeast
        z.dirs = { "running %s", "up to the %s" }
        z.places = { { "square", "square of Test" }, { "ramp", "ramp to the bank" } }
        z.grid = { "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2" }
        z.lanes = { 100, 46, 84, 46, 22045, 20, 40 }
        logic.unpack(z)
        t:assertEqual(logic.outdoorKey(z, 22045), "r2:")
        t:assertEqual(logic.describe(z, 22045, true), "ramp to the bank, up to the northeast")
        -- on the square beside it, pushing east against its side
        local owner, what = logic.wallOwner(z, 94, 53, 0, -1, 2.5)
        t:assertEqual(owner, "ramp to the bank")
        t:assertEqual(what, "side")
        -- on the ramp itself its own cells are no side
        t:assertNil(logic.wallOwner(z, 94, 46, 0, -1, 2.5))
    end,

    ["a way cell without a direction takes the direction of the same way's nearest line"] = function(t)
        local z = newWalkZone()
        -- the walk's cell at row 3, column 4 (x 86, y 42) has no direction; the walk's line at y = 46 is 4 yd off
        z.grid = { "10000*2,21000*3,0*2", "10000*2,21000*3,0*2", "10000*2,21000*3,0*2", "10000*2,21000*2,20000,0*2" }
        logic.unpack(z)
        t:assertEqual(logic.valueAt(z, 86, 42), 20000)
        local v, decided = logic.laneValue(z, 86, 42, 20000, false)
        t:assertEqual(v, 21000)
        t:assertEqual(decided, false)
        t:assertEqual(logic.outdoorKey(z, v), "r2:0")
        -- another way's cell is left alone
        z.grid[4] = "10000*2,21000*2,30000,0*2"
        z.places[3] = { "street", "street of Test" }
        logic.pack(z)
        logic.unpack(z)
        v = logic.laneValue(z, 86, 42, 30000, false)
        t:assertEqual(v, 30000)
    end,

    ["a street's lane across a square: on the line the street, off it the square"] = function(t)
        local z = newWalkZone()
        z.places = { { "square", "square of Test" }, { "street", "street of Test" } }
        -- the whole grid is square; the street's lane crosses it north-south at y = 50
        z.grid = { "10000*7", "10000*7", "10000*7", "10000*7" }
        z.lanes = { 100, 50, 84, 50, 21000, 20, 40 }
        logic.unpack(z)
        t:assertEqual((logic.outdoorValue(z, 92, 50, false, false)), 21000)
        -- 6 yd off the line, past its leave distance: the square again
        t:assertEqual((logic.outdoorValue(z, 92, 44, false, true)), 10000)
    end,

    ["clock hours: bare numbers, o'clock once at the end of a list or after a yard count"] = function(t)
        local z = newZone()
        z.dirsClock = { "water at %s", "deep water at %s", "land at %s", "drop at %s",
            "rock wall at %s", "building at %s", "at %s", "%s" }
        logic.unpack(z)
        logic.clock = true
        local ok, err = pcall(function()
            -- a direction is its hour; several in one text get one "o'clock" at the end
            t:assertEqual(logic.finishText(logic.dirWord(z, 100)), "3")
            t:assertEqual(logic.finishText(logic.describe(z, 21110, true)), "shore of Test Lake, water at 4")
            t:assertEqual(logic.finishText(logic.describe(z, 38110, true)), "bridge, 10 to 4 o'clock")
            t:assertEqual(logic.finishText(logic.describe(z, 38090, true)), "bridge, 3 to 9 o'clock")
            t:assertEqual(logic.finishText(logic.describe(z, 38030, true)), "bridge, 1 to 7 o'clock")
            t:assertEqual(logic.finishText(logic.describe(z, 38170, true)), "bridge, 12 to 6 o'clock")
            t:assertEqual(logic.finishText(logic.itemsText(z, {
                { label = "street of Test", class = "way", dirs = { 0, 270 } },
                { label = "cliff edge", class = "cliff edge", dirs = { 100 } },
            })), "street of Test at 12 and 9, cliff edge at 3 o'clock")
            -- a yard count before the hour: "o'clock" right there
            t:assertEqual(logic.finishText(logic.edgeText(z, 1)), "at 12, water")
            t:assertEqual(logic.finishText(logic.edgeText(z, 2, 7.6)), "8 at 6 o'clock, drop 12")
            local target = logic.footTarget(z, 7, 5)
            t:assertEqual(logic.finishText(logic.guideText(z, target, true, false)),
                "entrance of Test Inn, common room, 7 yards at 6 o'clock, in at 12")
            t:assertEqual(logic.finishText(logic.guideText(z, target, false, false)), "7 at 6 o'clock")
            t:assertEqual(logic.finishText(logic.guideText(z, target, false, true)), "in at 12")
            -- two angles of one hour are one direction; of one word but two hours they are two
            t:assertEqual(logic.sameDir(80, 100), true)     -- both 3 o'clock
            t:assertEqual(logic.sameDir(100, 110), false)   -- 3 and 4
            t:assertEqual(logic.wordSteps(100, 125), 1)
            t:assertEqual(logic.wordSteps(100, 150), 2)
            -- the way key tells 6 axes apart
            t:assertEqual(logic.axisKey(100), 3)
            t:assertEqual(logic.axisKey(0), 0)
            t:assertEqual(logic.axisKey(170), 0)
            -- a label with its directions as angles, clockwise from north
            t:assertEqual(logic.finishText(logic.expandDirs(z, "fork, Test road <d120,45,350>")), "fork, Test road at 2, 4 and 12 o'clock")
        end)
        logic.clock = false
        t:assertEqual(logic.sameDir(100, 110), true)        -- both east
        t:assertEqual(logic.wordSteps(100, 150), 1)         -- east, southeast
        t:assertEqual(logic.finishText(logic.bendText(z, 1, 100)), "left")
        t:assertEqual(logic.expandDirs(z, "fork, Test road <d120,45>"), "fork, Test road to the northeast and southeast")
        t:assertEqual(logic.finishText("no hours"), "no hours")
        if not ok then
            error(err, 0)
        end
    end,
})
