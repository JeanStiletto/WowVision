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
        -- the lake's water under the bridge (row 0, column 5) is a floor piece of its own, a
        -- liquid's (piece 3, water); its way out at 95, 20, climbed out toward the north (angle 0)
        liquids = { 3, 1 },
        exits = { 95, 20, 10, 0 },
        exitFloors = { 3 },
        -- a dock over row 1, columns 1 and 2 (world y 40 to 20), its north side a drop into water;
        -- a wall over row 1, columns 4 and 5, its wall-walk (high piece 1) dropping 12 yd to the
        -- south at x = 81; stepped onto from the ground at its east end (x 88, y 1) or out of a
        -- building at x 85, y 25; the wall-walk joins a tower top (piece 2) over row 0, column 4
        structs = { "dock", "wall" },
        structCells = { 1, 1, 1, 1, 2, 1, 1, 4, 2, 1, 5, 2 },
        edges = {
            { 1, 0, 3, 1, 0, 90, 34, 90, 32, 90, 30, 90, 28, 90, 26, l = 0, u = 3 },
            { 2, 180, 12, 0, 0, 81, 14, 81, 12, l = 1 },
            -- a low edge of the dock's structure
            { 1, 180, 3, 0, 0, 82, 38, 82, 36, l = 0 },
        },
        -- the floor pieces: the wall-walk (1) and the tower top (2) with their values, the ground
        -- under both; joins: from the ground at the wall-walk's east end, from the building's door
        -- (a = -1), the wall-walk to the tower top at x 90
        floorCells = { 1, 4, 1, 40000, 1, 5, 1, 40000, 0, 4, 2, 38090, 0, 5, 3, 50000 },
        noGround = {},
        joins = { 0, 1, 88, 1, -1, -1, 1, 85, 25, -1, 1, 2, 90, 15, -1 },
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
-- at row 0, columns 2 and 3; deep water east of it (rows 2 and 3, column 6); a canal (a liquid's
-- piece of its own, no place on the grid) south of it (row 4, columns 1 to 3); open land
-- elsewhere; the Test Bank's door on its south-east corner.
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
    z.structs, z.structCells, z.edges, z.joins = {}, {}, {}, {}
    z.floorCells = { 4, 1, 1, 50000, 4, 2, 1, 50000, 4, 3, 1, 50000 }
    z.noGround = { 4, 1, 4, 2, 4, 3 }
    z.liquids = { 1, 2 }
    z.exits, z.exitFloors = {}, {}
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
    z.interiors = { { "Test City", 0, 0, 1, -1, 0, 0, -1, c = 1 } } -- the city itself: its name is the zone's
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
        edges = { { 1, 180, 80, 3, 1, 72, 20, 72, 22, l = 0 } }, -- its floor belongs to the great hall (room 1)
    }
    return z
end

-- A tower: 3 rows x 6 columns of 10 yd cells; north edge at x = 100, west edge at y = 60; open
-- land, a road on row 2. A flight of stairs (piece 1) over row 0, columns 1 and 2 (y 50 to 30)
-- leads east onto a landing (piece 2) over columns 2 and 3 (y 40 to 20); the ground joins the
-- flight at its foot (y 52), the flight the landing at y 35. The flight's south rim beside the
-- join is a drop (an edge of the flight, its points 2 yd from the join), and farther west too;
-- the next flight's foot (stairs to the top) stands on the landing at y 25.
local function newTowerZone()
    local z = newZone()
    z.places = {
        { "open land", "open land" },
        { "stairs", "stairs to the landing", of = "tower" },
        { "platform", "landing", of = "tower" },
        { "road", "road" },
        { "stairs", "stairs to the top", of = "tower" },
    }
    z.grid = { "10000*6", "10000*6", "40000*6" }
    z.liquids, z.exits, z.exitFloors, z.interiors, z.rooms, z.doors = {}, {}, {}, {}, {}, {}
    z.structs = { "tower" }
    z.structCells = { 0, 1, 1, 0, 2, 1, 0, 3, 1 }
    z.edges = {
        { 1, 180, 12, 0, 0, 93, 36, 93, 34, l = 1, u = 0 },
        { 1, 180, 12, 0, 0, 93, 52, 93, 50, l = 1, u = 0 },
    }
    -- the next flight (piece 3) rises from the middle of the landing, over its cell at column 3
    z.floorCells = { 0, 1, 1, 20000, 0, 2, 1, 20000, 0, 2, 2, 30000, 0, 3, 2, 30000, 0, 3, 3, 50000 }
    z.noGround = {}
    z.joins = { 0, 1, 95, 52, 90, 1, 2, 95, 35, 90, 2, 3, 95, 25, 90 }
    z.ofTemplate = "%s of %s"
    z.climbFeetFields = 5
    z.climbFeet = { 96, 25, 50000, 90, 2 }
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

    ["in the halls the ground beside a ramp with a piece of its own keeps the hall's name"] = function(t)
        local z = newHallZone()
        table.insert(z.places, { "ramp", "ramp" }) -- place 9
        -- a ramp (piece 1) in row 0, column 2; the ground's cell there carries its name
        z.indoor.grid = { "70000*2,90000,70000*3", "70000*6", "0*6" }
        z.indoor.floorCells = { 0, 2, 1, 90000 }
        z.indoor.noGround = {}
        logic.unpack(z)
        local layer = logic.layer(z)
        local x, y = logic.cellCentre(layer, 0, 2)
        t:assertEqual(logic.describe(layer, logic.outdoorValue(layer, x, y), true), "great hall of Test")
        -- on the ramp's piece the ramp
        logic.setFloor(layer, 1)
        t:assertEqual(logic.describe(layer, logic.outdoorValue(layer, x, y), true), "ramp")
        -- without a piece of its own there the cell stays the ramp
        logic.pack(z)
        z.indoor.floorCells = {}
        logic.unpack(z)
        layer = logic.layer(z)
        t:assertEqual(logic.describe(layer, logic.outdoorValue(layer, x, y), true), "ramp")
    end,

    ["a building's levels on a grid of their own join where they meet, not next to each other"] = function(t)
        local z = newHallZone()
        -- the halls the game calls indoors, on cells of 5 yd: stairs (level 1) from their foot at
        -- y 59 west to y 45 (row 0, columns 0 to 2), the landing (level 2) over all of row 0, the
        -- stairs' foot too (the Brill tavern's landing lies over the foot of its stairs); the
        -- stairs are stepped onto at their foot and join the landing at their top, y 47
        z.indoorIn = {
            top = 100, left = 60, cell = 5, rows = 2, cols = 12,
            rooms = { 1 }, grid = { "70000*12", "70000*12" }, lanes = {},
            floorCells = { 0, 0, 1, 70000, 0, 1, 1, 70000, 0, 2, 1, 70000,
                0, 0, 2, 70000, 0, 1, 2, 70000, 0, 2, 2, 70000, 0, 3, 2, 70000, 0, 4, 2, 70000, 0, 5, 2, 70000 },
            noGround = {},
            -- the joins run east (y down): from the main floor into the stairs at their foot,
            -- from the stairs into the landing at their top
            joins = { 0, 1, 98, 59, 90, 1, 2, 98, 47, 90 },
        }
        logic.unpack(z)
        local layer = logic.layer(z, true)
        t:assertEqual(layer.cell, 5)
        t:assertEqual(layer.cols, 12)
        -- up the stairs' foot: on the stairs, not on the landing over it
        logic.updateFloor(layer, 98, 58, false, 98, 60)
        t:assertEqual(layer._index.floor, 1)
        -- past their top: the landing
        logic.updateFloor(layer, 98, 46, false, 98, 50)
        t:assertEqual(layer._index.floor, 2)
        -- on the landing alone: still
        logic.updateFloor(layer, 98, 38, false, 98, 46)
        t:assertEqual(layer._index.floor, 2)
        -- back down the stairs: the join crossed the other way
        logic.updateFloor(layer, 98, 48, false, 98, 46)
        t:assertEqual(layer._index.floor, 1)
        -- and off their foot onto the main floor
        logic.updateFloor(layer, 98, 60, false, 98, 58)
        t:assertEqual(layer._index.floor, 0)
        -- a look ending 0.3 yd past the foot's join (within the margin) changes nothing yet ...
        logic.updateFloor(layer, 98, 58.7, false, 98, 61)
        t:assertEqual(layer._index.floor, 0)
        -- ... and the next look, beginning past the join, still counts the crossing (the zeppelin
        -- tower's deck, walk 2026-10-06: the stairs were never entered)
        logic.updateFloor(layer, 98, 56, false, 98, 58.7)
        t:assertEqual(layer._index.floor, 1)
        -- strafing along the join within the margin counts nothing
        logic.updateFloor(layer, 98, 60, false, 98, 56)
        t:assertEqual(layer._index.floor, 0)
        logic.updateFloor(layer, 97, 59.2, false, 98, 59.3)
        logic.updateFloor(layer, 99, 58.8, false, 97, 59.2)
        t:assertEqual(layer._index.floor, 0)
    end,

    ["a flight with a wall side says its way up toward that side, and its foot the same way on"] = function(t)
        local z = newTowerZone()
        -- the first flight (piece 1, up to the east) aimed at its top on the north side; the next
        -- flight (piece 3, foot at 96, 25) at 98, 15
        z.climbAims = { 1, 20000, 97, 37, 90, 3, 50000, 98, 15, 90 }
        logic.unpack(z)
        local wallSide = logic.wallSide
        logic.setFloor(z, 1)
        -- the setting off: nothing
        logic.wallSide = false
        t:assertNil(logic.aimTarget(z, 92, 48))
        logic.wallSide = true
        -- 3 yd south of its line: the way up said toward the point, northeast, not east
        local target = logic.aimTarget(z, 92, 48)
        t:assertEqual(target.kind, "aim")
        t:assertEqual(logic.guideText(z, target, true, false), "on to the northeast")
        t:assertEqual(logic.atTarget(z, target, 92, 48), false)
        -- facing down the flight: not said (it is the way up)
        t:assertNil(logic.aimTarget(z, 92, 48, 270))
        t:assertEqual(logic.aimTarget(z, 92, 48, 60).kind, "aim")
        -- within AIM_DONE of the point along the way up: no longer said (the top's guidance)
        t:assertNil(logic.aimTarget(z, 95, 38))
        -- no point on the landing
        logic.setFloor(z, 2)
        t:assertNil(logic.aimTarget(z, 95, 30))
        -- the next flight's foot: its way on toward its point (79 degrees); with the setting off
        -- the climb's own (none in this test's value)
        local foot = logic.footTarget(z, 95, 30)
        t:assertEqual(foot.kind, "climb")
        t:assertEqual(foot.through, 79)
        logic.wallSide = false
        foot = logic.footTarget(z, 95, 30)
        t:assertNil(foot.through)
        logic.wallSide = wallSide
    end,

    ["on a platform its doors are guided to from anywhere on it"] = function(t)
        local z = newTowerZone()
        -- a roost's door at the landing's east end (x 95, y 21), 17 yd from its west end
        z.interiors = { { "Test Roost", 0, 0, 1, -1, 0, 0, -1 } }
        z.rooms = { { 1, "Test Roost", "large hall", { 90, 10, 100, 20 } } }
        z.doors = { { 0, 1, 1, 95, 21, 0, -1, 0 } }
        logic.unpack(z)
        logic.setFloor(z, 2)
        local target = logic.footTarget(z, 95, 38)
        t:assertEqual(target.kind, "entrance")
        t:assertEqual(math.floor(target.d + 0.5), 17)
        t:assertEqual(target.reach, logic.PLATFORM_REACH)
        -- on the ground beside the tower: the door is beyond the guidance reach
        logic.setFloor(z, 0)
        t:assertNil(logic.footTarget(z, 95, 45))
    end,

    ["a structure's place says the structure's name only where the player is not on it"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        -- from outside (or with the around key): with the structure's name
        t:assertEqual(logic.describe(z, 30000, false), "landing of tower")
        t:assertEqual(logic.describe(z, 30000, false, nil, nil, nil), "landing of tower")
        -- coming from a place of the same structure: without it
        t:assertEqual(logic.describe(z, 30000, false, nil, nil, "tower"), "landing")
        -- a place of no structure: as it was
        t:assertEqual(logic.describe(z, 40000, false, nil, nil, "tower"), "road")
    end,

    ["a level reached by a ramp at one structure and by stairs at another is one named floor"] = function(t)
        local z = newTowerZone()
        z.floors = {
            { "platform", "platform", "ramp to the platform", "ramp" },
            { "platform", "platform", "stairs to the platform", "stairs" },
        }
        logic.unpack(z)
        t:assertEqual(logic.floorOf(z, "platform"), 1)
        local on, bare = logic.floorOf(z, "stairs to the platform")
        t:assertEqual(on, 1)
        t:assertEqual(bare, "stairs")
        -- up there, the stairs up to it are said plainly
        t:assertEqual(logic.floorLabel(z, "stairs to the platform", 1), "stairs")
    end,

    ["a stair joined in the middle of a platform is one of its openings"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        logic.setFloor(z, 2)
        local region = logic.regionAt(z, 95, 22)
        t:assertEqual(region ~= nil, true)
        local found = false
        for _, m in ipairs(region.mouths) do
            if m.label == "stairs to the top" then
                found = true
            end
        end
        t:assertEqual(found, true)
    end,

    ["a structure's platform says what lies around it, as a square"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        t:assertEqual(logic.hasEdge(z, 30000), true)
        t:assertEqual(logic.hasEdge(z, 20000), false)
    end,

    ["up on a piece, the drop edge of a piece joined to it counts near their join"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        -- (the flight's rims are a stairs' edges: they warn facing their drop, to the south)
        local south = math.pi
        -- on the landing beside the join: the flight's rim there warns
        logic.setFloor(z, 2)
        t:assertEqual(logic.nearestEdge(z, 95, 35, 4, nil, south), 1)
        t:assertNil(logic.nearestEdge(z, 95, 35, 4, nil, math.pi / 2))   -- walking along it: quiet
        -- on the landing, the flight's rim 15 yd from the join does not
        t:assertEqual(logic.nearestEdge(z, 95, 51, 4, nil, south), nil)
        -- on the flight itself both do
        logic.setFloor(z, 1)
        t:assertEqual(logic.nearestEdge(z, 95, 51, 4, nil, south), 2)
        -- on the ground (it joins the foot of every flight) neither
        logic.setFloor(z, 0)
        t:assertEqual(logic.nearestEdge(z, 95, 35, 4, nil, south), nil)
    end,

    ["a step over a rim falls, a push against its railing does not"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        -- from the landing over the flight's rim beside the join, pushing against something
        logic.setFloor(z, 2)
        logic.updateFloor(z, 91, 35, false, 95, 35, true)
        t:assertEqual(z._index.floor, 2)
        -- the same step, moving freely: a fall onto the ground
        logic.setFloor(z, 2)
        logic.updateFloor(z, 91, 35, false, 95, 35, false)
        t:assertEqual(z._index.floor, 0)
    end,

    ["up on a piece that joins the ground nowhere, the ground's paint is nothing"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        -- the landing joins only the flight: the road below it is not its neighbour
        logic.setFloor(z, 2)
        t:assertEqual(logic.valueAtCell(z, 2, 5), 0)
        t:assertEqual(logic.valueAtCell(z, 0, 3), 30000)
        -- the flight joins the ground at its foot: the road is
        logic.setFloor(z, 1)
        t:assertEqual(logic.valueAtCell(z, 2, 5), 40000)
    end,

    ["on a flight, the next flight's foot on the landing at its top is guided to"] = function(t)
        local z = newTowerZone()
        logic.unpack(z)
        -- up the flight from the ground: the foot on the landing it joins
        logic.updateFloor(z, 95, 49, false, 95, 53)
        t:assertEqual(z._index.floor, 1)
        local target = logic.footTarget(z, 95, 31)
        t:assertEqual(target ~= nil and target.kind, "climb")
        -- down the flight from the landing: not back to it
        logic.setFloor(z, 2)
        logic.updateFloor(z, 95, 37, false, 95, 33)
        t:assertEqual(z._index.floor, 1)
        target = logic.footTarget(z, 95, 31)
        t:assertEqual(target, nil)
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

    ["an entrance is guided to only from the floor its doorway lies on"] = function(t)
        local z = newHallZone()
        z.indoor.doorFloors = { 2, 0, 0 }   -- the shop's doorway lies on piece 2 (a walkway over the hall)
        logic.unpack(z)
        local layer = logic.layer(z)
        t:assertEqual(select(4, logic.nearestEntrance(layer, 90, 36, 8, nil, false)).text, "shop")   -- unfiltered
        t:assertNil(logic.nearestEntrance(layer, 90, 36, 8, nil, true))                            -- on the hall's floor
        logic.setFloor(layer, 2)
        t:assertEqual(select(4, logic.nearestEntrance(layer, 90, 36, 8, nil, true)).text, "shop")    -- up on its floor
        -- data without doorFloors: as before
        local old = newHallZone()
        logic.unpack(old)
        t:assertEqual(select(4, logic.nearestEntrance(logic.layer(old), 90, 36, 8, nil, true)).text, "shop")
    end,

    ["a stairs' edge beside the player warns only while they face its drop"] = function(t)
        local z = newHallZone()
        z.indoor.edges[1][5] = 4   -- its floor is the stairs' (room 4, kind stairs); the drop is to the south
        logic.unpack(z)
        local layer = logic.layer(z)
        local stairs = { [4] = true }
        t:assertTrue(logic.isStairEdge(layer, 1))
        t:assertEqual(logic.nearestEdge(layer, 74, 21, 3, stairs, math.pi, nil), 1)     -- facing south, into it
        t:assertNil(logic.nearestEdge(layer, 74, 21, 3, stairs, math.pi / 2, nil))      -- walking along it
        t:assertNil(logic.nearestEdge(layer, 74, 21, 3, stairs, 0, nil))                -- facing away
        t:assertNil(logic.nearestEdge(layer, 74, 21, 3, stairs, nil, nil))              -- no facing known
        -- a path into it still warns
        t:assertEqual(logic.edgeAhead(layer, 76, 21, -1, 0, 10, stairs, nil), 1)
        -- any other room's edge as before
        t:assertFalse(logic.isStairEdge(logic.layer((function() local h = newHallZone(); logic.unpack(h); return h end)()), 1))
    end,

    ["a big room says its doorways from where the player stands, nearest first"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 1, nil, false, 95, 25),
            "great hall, way outside to the north, shop to the west, passage to the southeast")
        -- without a position (or in a small room) the fixed directions stay
        t:assertEqual(logic.roomText(z, 3, 1, false, 75, 5), "passage, north to south, great hall to the north")
        -- guidance to the nearest doorway of the big room
        local target = logic.roomDoorTarget(z, 1, 96, 25)
        t:assertEqual(logic.guideText(z, target, true, false), "way outside, 4 to the north")
        t:assertEqual(logic.roomDoorTarget(z, 3, 76, 6), nil)
    end,

    ["the next section of the same thing: no name, its way when it changed, its doorways on"] = function(t)
        local z = newZone()
        z.interiors = { { "Test Mine", 0, 0, 1, -1, 0, 0, -1 } }
        z.rooms = {
            { 1, "mine", "corridor", { 0, 0, 10, 30 }, f = 300, a = 0 },
            { 1, "mine 2", "corridor", { 0, 30, 10, 60 }, f = 300, a = 0 },
            { 1, "mine 3", "room", { 10, 30, 20, 40 }, f = 100 },
            { 1, "gallery", "room", { 0, 60, 10, 70 }, f = 100 },
            { 1, "stairs", "stairs", { -10, 30, 0, 40 }, f = 40, a = 90 },
            { 1, "stairs", "stairs", { -20, 30, -10, 40 }, f = 40, a = 45 },
            { 1, "mine 4", "room", { 20, 30, 30, 40 }, f = 100 },
        }
        z.doors = {
            { 1, 2, 1, 5, 30, 0, 1, -1 },
            { 2, 3, 1, 10, 35, 1, 0, -1 },
            { 2, 4, 1, 5, 60, 0, 1, -1 },
            { 2, 5, 1, 0, 35, 1, 0, 1 },
            { 5, 6, 1, -10, 35, 1, 0, 1 },
            { 0, 6, 1, -20, 35, 0, 0, 0 },
            { 3, 7, 1, 20, 35, 1, 0, -1 },
        }
        logic.unpack(z)
        t:assertTrue(logic.sameRoomName(z, 1, 2))
        -- into mine 2 from mine: the way runs as said already, so only the doorways on, not back
        local text, way = logic.sectionText(z, 2, 1, logic.roomWay(z, 1))
        t:assertEqual(way, logic.roomWay(z, 1))
        t:assertTrue(text:find("mine 3", 1, true) ~= nil and text:find("gallery", 1, true) ~= nil
            and text:find("stairs", 1, true) ~= nil)
        t:assertNil(text:find("mine to", 1, true))
        t:assertNil(text:find(way, 1, true))
        -- back into mine: nothing left to say
        t:assertNil((logic.sectionText(z, 1, 2, way)))
        -- up the staircase: the next piece says its way and the way out, not the piece below
        text = logic.sectionText(z, 6, 5, logic.roomWay(z, 5))
        t:assertTrue(text:find(logic.roomWay(z, 6), 1, true) == 1)
        t:assertTrue(text:find("way out", 1, true) ~= nil)
        t:assertNil(text:find("stairs", 1, true))
        -- a passage whose only way on is the next section of the same thing: no choice, nothing said
        t:assertNil((logic.sectionText(z, 3, 2, way)))
        -- a doorway into another piece of the same staircase is no way on
        t:assertEqual(#logic.roomDoorways(z, 5, { section = true, cameFrom = 2 }), 0)
    end,

    ["winding stairs say they wind, not which way going up"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 4, 1, false), "stairs, winding")
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

    ["the turn key without a beacon faces along the centre line, the way nearer the facing"] = function(t)
        local z = newLaneZone()
        logic.unpack(z)
        local function near(a, degrees)
            return math.abs(logic.degreesBetween(a, math.rad(degrees))) < 0.5
        end
        local facings, fork = logic.lineFacings(z, 92, 48, 21000, math.rad(12))
        t:assertEqual(#facings, 2)
        t:assertEqual(fork, false)
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(12), fork), 0))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-80), fork), 0))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(170), fork), 180))
        -- facing along it already: the same way again (turning around is not the key's)
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(1), fork), 0))
        -- no centre line: the forest, a bridge with neither a line nor a direction
        t:assertNil((logic.lineFacings(z, 92, 56, 10000, 0)))
        t:assertNil((logic.lineFacings(z, 82, 48, 30000, 0)))
    end,

    ["the turn key without a beacon faces along a bridge: the direction it is said with"] = function(t)
        local function near(a, degrees)
            return math.abs(logic.degreesBetween(a, math.rad(degrees))) < 1
        end
        -- no line on the bridge: the direction said, northeast to southwest (axis 45)
        local z = newLaneZone()
        logic.unpack(z)
        local facings = logic.lineFacings(z, 82, 48, 31045, 0)
        t:assertEqual(#facings, 2)
        t:assertTrue(near(logic.lineTurnFacing(facings, 0, false), -45))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(170), false), 135))
        -- a line on the bridge (running east, 6 degrees off) changes nothing: the direction said
        z = newLaneZone()
        z.lanes = { 100, 48, 84, 48, 21000, 20, 40, 83, 58, 81, 38, 31045, 20, 40 }
        logic.unpack(z)
        facings = logic.lineFacings(z, 82, 48, 31045, math.rad(-90))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-90), false), -45))
    end,

    ["the turn key without a beacon faces along a canal: the direction it is said with"] = function(t)
        local function near(a, bearing)
            return math.abs(logic.degreesBetween(a, math.rad(-bearing))) < 1
        end
        -- a canal running east to west (axis 90), no centre line: along it, the way nearer the facing
        local z = newLaneZone()
        table.insert(z.places, { "canal", "canal" }) -- place 4
        logic.unpack(z)
        t:assertEqual(logic.axisOf(z, 41090), 90)
        local facings, fork = logic.lineFacings(z, 82, 48, 41090, 0)
        t:assertEqual(#facings, 2)
        t:assertEqual(fork, false)
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-60), false), 90))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(80), false), 270))
        -- a canal said without a direction: nothing to face along
        t:assertNil((logic.lineFacings(z, 82, 48, 40000, 0)))
    end,

    ["the turn key without a beacon faces along a ramp or stairs: the direction it is said with"] = function(t)
        local function near(a, bearing)
            return math.abs(logic.degreesBetween(a, math.rad(-bearing))) < 1
        end
        -- a ramp rising to the northeast (52) with a line running south on it (another flight's,
        -- or a scrap across it): the direction said, either way
        local z = newLaneZone()
        table.insert(z.places, { "ramp", "ramp" }) -- place 4
        z.lanes = { 100, 48, 84, 48, 21000, 20, 40, 83, 48, 81, 48, 40052, 20, 40 }
        logic.unpack(z)
        t:assertEqual(logic.riseOf(z, 40052), 52)
        local facings = logic.lineFacings(z, 82, 48, 40052, 0)
        t:assertEqual(#facings, 2)
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-40), false), 52))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(170), false), 232))
    end,

    ["the turn key without a beacon reads the heading of the way ahead stored with the stretch"] = function(t)
        local function near(a, bearing)
            return math.abs(logic.degreesBetween(a, math.rad(-bearing))) < 0.5
        end
        -- the stretch runs south (x falls), 16 yd in two samples; stored at the second (x 88): 190
        -- going south, 3 going north
        local z = newLaneZone()
        z.lanes = { 100, 48, 84, 48, 21000, 20, 40 }
        z.laneHeadings = { 2, 180, 0, 190, 3 }
        logic.unpack(z)
        local facings = logic.lineFacings(z, 92, 48, 21000, math.rad(180))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-170), false), 190))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(10), false), 3))
        -- the first sample (x 96): the straight line
        facings = logic.lineFacings(z, 96, 48, 21000, math.rad(180))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-170), false), 180))
        -- near the line's end no heading ahead (-1): the other one turned round
        z = newLaneZone()
        z.lanes = { 100, 48, 84, 48, 21000, 20, 40 }
        z.laneHeadings = { 2, 180, 0, -1, 3 }
        logic.unpack(z)
        facings = logic.lineFacings(z, 92, 48, 21000, math.rad(180))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(-170), false), 183))
    end,

    ["the turn key without a beacon faces along the stretch of the line it stands by"] = function(t)
        local z = newLaneZone()
        -- north-south to x = 90, then bending toward the east (y falls) down to x = 80
        z.lanes = { 100, 48, 90, 48, 21000, 20, 40, 90, 48, 80, 44, 21000, 20, 40 }
        logic.unpack(z)
        local function near(a, degrees)
            return math.abs(logic.degreesBetween(a, math.rad(degrees))) < 0.5
        end
        -- before the bend the straight stretch, past it the bend's (201.8 degrees facing south)
        local facings = logic.lineFacings(z, 92, 48, 21000, math.rad(180))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(180), false), 180))
        facings = logic.lineFacings(z, 86, 46.4, 21000, math.rad(180))
        t:assertTrue(near(logic.lineTurnFacing(facings, math.rad(180), false), 201.8))
    end,

    ["the turn key without a beacon turns to a fork's arms, the next clockwise each press"] = function(t)
        local z = newLaneZone()
        z.places[4] = { "fork", "fork, Test road <d0,120>, street <d240>" }
        logic.unpack(z)
        local function near(a, bearing)
            -- a facing is counter-clockwise from north, the label's angles clockwise
            return math.abs(logic.degreesBetween(a, math.rad(-bearing))) < 0.5
        end
        local facings, fork = logic.lineFacings(z, 92, 48, 40000, 0)
        t:assertEqual(#facings, 3)
        t:assertEqual(fork, true)
        -- first the arm nearest the facing (east-southeast: the arm at 120)
        local f = logic.lineTurnFacing(facings, math.rad(-100), fork)
        t:assertTrue(near(f, 120))
        -- facing it, the next press turns on clockwise: 240, then 0, then 120 again
        f = logic.lineTurnFacing(facings, f + math.rad(2), fork)
        t:assertTrue(near(f, 240))
        f = logic.lineTurnFacing(facings, f, fork)
        t:assertTrue(near(f, 0))
        f = logic.lineTurnFacing(facings, f - math.rad(2.5), fork)
        t:assertTrue(near(f, 120))
        -- out of the 3 degree calm zone the press corrects onto the arm nearest, as on a way
        t:assertTrue(near(logic.lineTurnFacing(facings, f + math.rad(4), fork), 120))
        -- a fork whose label carries no directions: nothing
        z = newLaneZone()
        z.places[4] = { "fork", "fork" }
        logic.unpack(z)
        t:assertNil((logic.lineFacings(z, 92, 48, 40000, 0)))
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
        -- a whole direction word or more: no bend (45 degrees with compass words, 30 with the clock)
        t:assertEqual(logic.bendTurn(r(180), r(260), r(180), 15), 0)
        t:assertEqual(logic.bendTurn(r(180), r(215), r(180), 15), 1)
        local clock = logic.clock
        logic.clock = true
        t:assertEqual(logic.bendTurn(r(180), r(215), r(180), 15), 0)
        t:assertEqual(logic.bendTurn(r(180), r(205), r(180), 15), 1)
        logic.clock = clock
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

    ["a bridge next to a drop counts near its centre line; off it the place beside, away from drops the cell"] = function(t)
        -- 4 rows x 7 columns of 4 yd cells: columns 0 and 1 (y 60 to 52) square, 2 to 4 (y 52 to
        -- 40) bridge, 5 and 6 canal; the bridge's line runs north-south at y = 46, enter 2, leave 4;
        -- a drop edge to the west along y = 53 from x 92 to 96 (structure 1 on the bridge's cell
        -- in row 1)
        local z = newWalkZone()
        z.places = { { "square", "square of Test" }, { "bridge", "bridge" }, { "canal", "canal of Test" } }
        z.grid = { "10000*2,20000*3,30000*2", "10000*2,20000*3,30000*2", "10000*2,20000*3,30000*2", "10000*2,20000*3,30000*2" }
        z.lanes = { 100, 46, 84, 46, 20000, 20, 40 }
        z.structCells = { 1, 2, 1 }
        z.edges = { { 1, 270, 5, 0, 0, 92, 53, 94, 53, 96, 53, l = 0 } }
        logic.unpack(z)
        t:assertEqual(logic.laneValue(z, 94, 46, 20000, false), 20000)
        t:assertEqual(logic.laneValue(z, 94, 47.5, 20000, false), 20000)
        -- 4.5 yd off toward the square, 2.5 yd from the drop: the square beside the bridge (the
        -- courtyard bridge's north head, walk 2026-10-15 15:36:25)
        t:assertEqual(logic.laneValue(z, 94, 50.5, 20000, false), 10000)
        -- on the bridge 3 yd off: within its leave distance it stays
        t:assertEqual(logic.laneValue(z, 94, 49, 20000, true), 20000)
        -- coming from the square 3 yd off: beyond the enter distance, but the drop is 4 yd away
        t:assertEqual(logic.laneValue(z, 94, 49, 20000, false), 20000)
        t:assertEqual(logic.laneValue(z, 94, 50, 20000, false), 10000)
        -- as far off the line with no drop near: the cell decides, the bridge (a wide deck)
        t:assertEqual(logic.laneValue(z, 86, 50.5, 20000, false), 20000)
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

    ["a liquid is a floor piece: swimming puts the player on it, on foot off it"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local _v, r, c = logic.valueAt(z, 95, 5)
        t:assertEqual(logic.liquidIn(z, r * z.cols + c), 1)
        t:assertNil(logic.liquidIn(z, 0))
        -- on the bridge: the bridge; swimming under it: the lake's piece, and the lake
        t:assertEqual(logic.valueAt(z, 95, 5), 38090)
        logic.updateFloor(z, 95, 5, false, 95, 6, false, true)
        t:assertEqual(z._index.floor, 3)
        t:assertEqual(logic.valueAt(z, 95, 5), 50000)
        -- in the air (jumping out of the water): no change; on foot again: no floor here joins the
        -- lake, the ground neither, so still in the lake; walking out of its cell, the ground
        logic.updateFloor(z, 95, 4, false, 95, 5, false, nil)
        t:assertEqual(z._index.floor, 3)
        logic.updateFloor(z, 95, 4, false, 95, 4, false, false)
        t:assertEqual(z._index.floor, 3)
        logic.updateFloor(z, 75, 4, false, 95, 4, false, false)
        t:assertEqual(z._index.floor, 0)
        -- falling off the dock's north edge into the lake: on the lake's piece
        logic.updateFloor(z, 89, 30, false, 89, 30)
        logic.updateFloor(z, 91, 30, false, 89, 30)
        t:assertEqual(z._index.floor, 3)
        logic.pack(z)
        t:assertNil(z._index)
    end,

    ["a join counts only where it is; out of a liquid only onto a floor it joins or the ground"] = function(t)
        local z = newZone()
        -- the tower top (piece 2) also lies in the lake's cell, joined to the lake nowhere, and the
        -- ground is absent there: standing up in the lake is no way onto it
        z.floorCells = { 1, 4, 1, 40000, 1, 5, 1, 40000, 0, 4, 2, 38090, 0, 5, 3, 50000, 0, 5, 2, 38090 }
        z.noGround = { 0, 5 }
        logic.unpack(z)
        -- the wall-walk joins the tower top at x 90, y 15: here, not 10 yd away
        t:assertTrue(logic.joinedHere(z, 1, 2, 90, 15))
        t:assertTrue(logic.joinedHere(z, 2, 1, 88, 12))
        t:assertFalse(logic.joinedHere(z, 1, 2, 80, 15))
        t:assertFalse(logic.joinedHere(z, 1, 3, 90, 15))
        -- swimming in the lake (the only liquid here), then standing: no floor joins the lake here
        -- and the ground is absent, so the lake stays the floor
        logic.updateFloor(z, 95, 5, false, 95, 6, false, true)
        t:assertEqual(z._index.floor, 3)
        logic.updateFloor(z, 95, 5, false, 95, 5, false, false)
        t:assertEqual(z._index.floor, 3)
        logic.pack(z)
    end,

    ["standing up in a liquid split into pieces: a floor joined to a piece of it joined to this one"] = function(t)
        local z = newZone()
        -- the lake's cell (row 0, column 5) holds a second piece of the same water (4, joined to
        -- 3 at 95, 8) and a ledge (5) joined to piece 4 only, as the Ruins of Lordaeron's sewer
        z.liquids = { 3, 1, 4, 1 }
        z.floorCells = { 1, 4, 1, 40000, 1, 5, 1, 40000, 0, 4, 2, 38090, 0, 5, 3, 50000, 0, 5, 4, 50000, 0, 5, 5, 21090 }
        z.joins = { 0, 1, 88, 1, -1, -1, 1, 85, 25, -1, 1, 2, 90, 15, -1, 3, 4, 95, 8, -1, 4, 5, 95, 2, -1 }
        logic.unpack(z)
        logic.setFloor(z, 3)
        logic.updateFloor(z, 95, 5, false, 95, 5, false, false)
        t:assertEqual(z._index.floor, 5)
        -- without the seam the ledge is no way out of piece 3: on foot on it never swum in (a fall
        -- the game did not make), the ground; standing up after swimming in it, still in it
        z.joins = { 0, 1, 88, 1, -1, -1, 1, 85, 25, -1, 1, 2, 90, 15, -1, 4, 5, 95, 2, -1 }
        logic.pack(z)
        logic.unpack(z)
        logic.setFloor(z, 3)
        logic.updateFloor(z, 95, 5, false, 95, 5, false, false)
        t:assertEqual(z._index.floor, 0)
        logic.setFloor(z, 3)
        logic.updateFloor(z, 95, 5, false, 95, 5, false, true)
        t:assertEqual(z._index.floor, 3)
        logic.updateFloor(z, 95, 5, false, 95, 5, false, false)
        t:assertEqual(z._index.floor, 3)
        logic.pack(z)
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

    ["the nearest way out of the liquid the player is on, with its direction"] = function(t)
        local z = newZone()
        logic.unpack(z)
        local target = logic.exitTarget(z, 95, 30, 3)
        t:assertEqual(target.name, "way out of the water")
        t:assertEqual(target.through, 0)                   -- one climbs out toward the north
        t:assertEqual(target.key, 1)
        t:assertEqual(target.d, 10)
        t:assertEqual(target.dir, 90)                      -- y 20 is east of y 30
        t:assertNil(logic.exitTarget(z, 95, 30, 0))        -- on the ground: none of its own
        -- two stretches of one way out (a long shore) share their group: one target to the
        -- guidance, whichever stretch is nearer
        z = newZone()
        z.exits, z.exitFloors, z.exitGroups = { 95, 20, 10, 0, 95, 10, 10, 0 }, { 3, 3 }, { 1, 1 }
        logic.unpack(z)
        local a, b = logic.exitTarget(z, 95, 22, 3), logic.exitTarget(z, 95, 8, 3)
        t:assertEqual(a.key, b.key)
        t:assertEqual(a.y, 20)
        t:assertEqual(b.y, 10)
        t:assertNil(logic.exitTarget(z, 95, 60, 3))        -- beyond EXIT_REACH while swimming
    end,

    ["a moat: its edge says moat, its way out is found from anywhere down in it"] = function(t)
        local z = newZone()
        z.edges[1][4] = 4   -- the dock's edge now drops into a moat
        z.places[7] = { "moat", "moat" }
        z.exitFloors = { 0 }  -- the moat is the ground here
        logic.unpack(z)
        t:assertEqual(logic.edgeText(z, 1), "north, moat")
        t:assertEqual(logic.edgeText(z, 1, 6.2), "6 north, moat")
        t:assertNil(logic.exitTarget(z, 95, 60, 1))                    -- on another piece: none
        local target = logic.exitTarget(z, 95, 60, 0, 70000)           -- down in the moat: 40 yd away
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
        z.edges[3] = { 1, 270, 3, 1, 0, 84, 40, 86, 40, l = 0 }
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

    ["stairs beside a square: up or down from it is kept for the way on, never said"] = function(t)
        -- user's walk 2026-10-03: on a landing "stairs at 1" did not say up or down; 2026-10-04:
        -- no "up" or "down" any more (word monsters), the mouths keep it for the way on
        local function stairsItems(code)
            local z = newSquareZone()
            z.dirs[9] = "up to the %s"
            table.insert(z.places, { "stairs", "stairs" })
            z.grid[1] = "30000*2," .. (60000 + code) .. "*2,30000*3"
            logic.unpack(z)
            local region = logic.regionAt(z, 78, 35)
            return logic.aroundItems(region, 78, 35, { classes = { way = true } }), z
        end
        -- rising to the north, away from the square: up
        local items, z = stairsItems(9000)
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].mouths[1].rise, "up")
        t:assertEqual(logic.itemsText(z, items), "stairs to the north")
        -- rising to the south, toward the square: down
        items = stairsItems(9180)
        t:assertEqual(items[1].mouths[1].rise, "down")
        -- rising to the east, along the square's side
        items = stairsItems(9090)
        t:assertEqual(#items, 1)
        t:assertNil(items[1].mouths[1].rise)
    end,

    ["stairs beside a square are on its entry line: they lead to another floor"] = function(t)
        local z = newSquareZone()
        z.dirs[9] = "up to the %s"
        table.insert(z.places, { "stairs", "stairs" })
        z.grid[1] = "30000*2,69000*2,30000*3"
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        local exits = logic.aroundItems(region, 78, 35, { classes = { way = true }, leading = true, zone = z })
        t:assertEqual(#exits, 1)
        t:assertEqual(exits[1].label, "stairs")
        -- no way begins there: the climb's foot is guided to as a climb
        t:assertEqual(#logic.wayBeginnings(z, region), 0)
    end,

    ["in a building layer a room's opening into another room is its doorway"] = function(t)
        -- a house (not a city's complex): the great hall (named as its room is) with the shop west
        -- of it (y 40 to 50) and a porch east of it (y 0 to 10) on the layer's grid; a door to the
        -- shop at x 90, y 40, none to the porch: a wall between them, whatever the grid shows
        local z = newHallZone()
        z.interiors[1].c = nil
        z.places[7] = { "hall", "great hall" }
        table.insert(z.places, { "hall", "shop" }) -- place 9
        table.insert(z.places, { "hall", "porch" }) -- place 10
        table.insert(z.rooms, { 1, "porch", "room", { 80, 0, 100, 10 }, f = 100 }) -- room 5
        z.indoor.rooms = { 1, 2, 5 }
        z.indoor.grid = { "0,90000,70000*3,100000", "0,90000,70000*3,100000", "0*6" }
        logic.unpack(z)
        local layer = logic.layer(z)
        local region = logic.regionAt(layer, 90, 25)
        t:assertEqual(region.label, "great hall")
        local byLabel = {}
        for _, m in ipairs(region.mouths) do
            byLabel[m.label] = m
        end
        t:assertNil(byLabel["porch"])
        local shop = byLabel["shop"]
        t:assertEqual(shop ~= nil, true)
        t:assertEqual(#shop.points, 2)
        t:assertEqual(shop.points[1], 90)
        t:assertEqual(shop.points[2], 40)
        -- its distance and direction are the doorway's, not the border's middle (90, 45)
        local d = logic.mouthDistance(shop, 82, 12)
        t:assertEqual(math.floor(d + 0.5), 29)
        -- the way outside is still there, by its door
        t:assertEqual(byLabel["way outside"] ~= nil, true)
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
        -- walking along the foot of the wall: under the wall-walk, never on it
        logic.updateFloor(z, 85, 35, false, 85, 37)
        logic.updateFloor(z, 83, 14, false, 85, 35)
        t:assertEqual(z._index.floor, 0)
        t:assertNil(logic.nearestEdge(z, 83, 14, 3))
        -- up at the east end (the join from the ground), then along the wall-walk to its edge
        logic.updateFloor(z, 88, 1, false, 88, 5)
        t:assertEqual(z._index.floor, 1)
        logic.updateFloor(z, 83, 14, false, 88, 1)
        t:assertEqual(z._index.floor, 1)
        local i, d = logic.nearestEdge(z, 83, 14, 3)
        t:assertEqual(i, 2)
        t:assertEqual(d, 2)
        -- over the join to the tower top
        logic.updateFloor(z, 95, 15, false, 88, 15)
        t:assertEqual(z._index.floor, 2)
        -- off every piece's cells: the ground again
        logic.updateFloor(z, 85, 35, false, 88, 25)
        t:assertEqual(z._index.floor, 0)
    end,

    ["coming out of a building onto a wall-walk counts; walking past that spot does not"] = function(t)
        local z = newZone()
        logic.unpack(z)
        logic.updateFloor(z, 86, 25, false, 86, 27)
        t:assertEqual(z._index.floor, 0)
        logic.updateFloor(z, 86, 25, true, 86, 27)
        t:assertEqual(z._index.floor, 1)
        -- the tower top alone is not stepped onto from below
        logic.setFloor(z, 0)
        logic.updateFloor(z, 95, 15, false, 95, 17)
        t:assertEqual(z._index.floor, 0)
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

    ["stacked rooms: the floor piece the player is on names the room (rooms by floor)"] = function(t)
        local z = newZone()
        -- the inn's indoor layer on a grid of its own (5 yd cells, x 20 to 0, y 20 to 0): the common
        -- room's floor is its ground, the upstairs landing piece 1 over it (joined), the back room
        -- the ground east of them; the landing's piece also reaches the cell north of (5, 5)
        z.indoorIn = {
            top = 20, left = 20, cell = 5, rows = 4, cols = 4,
            rooms = {}, grid = { "0*4", "0*4", "0*4", "0*4" }, lanes = {}, edges = {},
            floorCells = {}, noGround = {}, joins = { 0, 1, 5, 2, -1 },
            floorRooms = { 3, 3, 0, 1, 3, 3, 1, 2, 1, 3, 0, 3, 2, 3, 1, 2 },
        }
        logic.unpack(z)
        local layer = logic.layer(z, true)
        -- on the ground: the common room, where the boxes alone leave it unknown
        local boxesOnly = newZone()
        logic.unpack(boxesOnly)
        t:assertNil(logic.resolveRoom(boxesOnly, 5, 5, nil, nil, nil, false, false, true))
        t:assertEqual(logic.resolveRoom(z, 5, 5, nil, nil, nil, false, false, true), 1)
        t:assertEqual(logic.resolveRoom(z, 15, 5, nil, nil, nil, false, false, true), 3)
        -- up on the landing's piece: the landing, even coming from the common room
        logic.setFloor(layer, 1)
        t:assertEqual(logic.resolveRoom(z, 5, 5, 1, nil, nil, false, false, true), 2)
        -- a cell that does not list the piece: the cells around it say
        t:assertEqual(logic.floorRoomsAt(layer, 12, 2)[1], 2)
        -- on the ground the cells around count only for the room the player is in or one joined to
        -- it by a doorway (the ground holds floors at any height)
        logic.setFloor(layer, 0)
        local around, aside = logic.floorRoomsAt(layer, 8, 2)
        t:assertTrue(aside)
        t:assertEqual(#around, 2)                                                    -- back room, common room
        t:assertEqual(logic.resolveRoom(z, 8, 2, 4, nil, nil, false, false, true), nil)  -- from the barn: neither
        t:assertEqual(logic.resolveRoom(z, 8, 2, 1, nil, nil, false, false, true), 1)    -- in the common room: it holds
        logic.setFloor(layer, 1)
        -- a piece no record names: the boxes decide, as before (two of them here: unknown)
        logic.setFloor(layer, 5)
        t:assertNil(logic.floorRoomsAt(layer, 5, 5))
        t:assertNil(logic.resolveRoom(z, 5, 5, nil, nil, nil, false, false, true))
        -- the common room's floor lies on the ground: not near from piece 5
        t:assertFalse(logic.roomFloorNear(layer, 1, 5, 5))
        -- through the common room's doorway from piece 5: onto the common room's floor, the ground
        t:assertEqual(logic.roomPieceHere(layer, 1, 5, 5), 0)
        t:assertEqual(logic.roomPieceHere(layer, 2, 12, 2), 1)   -- the landing's, from the cell beside
        t:assertNil(logic.roomPieceHere(layer, 4, 5, 5))         -- the barn has no floor here
        logic.setFloor(layer, 1)
        t:assertFalse(logic.roomFloorNear(layer, 1, 5, 5))        -- a piece joined to its floor is not its floor
        t:assertTrue(logic.roomFloorNear(layer, 2, 5, 5))
        t:assertEqual(logic.roomPieceHere(layer, 1, 5, 5), 0)    -- onto its floor
        logic.setFloor(layer, 0)
        t:assertTrue(logic.roomFloorNear(layer, 1, 5, 5))
        t:assertNil(logic.roomPieceHere(layer, 1, 5, 5))         -- on its floor: the floor stays
        logic.setFloor(layer, 1)
        t:assertNil(logic.roomFloorNear(layer, 4, 5, 5))          -- the barn: no floor in the records, nothing known
        -- data without rooms by floor: nothing known
        t:assertNil(logic.roomFloorNear(logic.layer(newZone(), true), 1, 5, 5))
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

    ["numbered room names are said without their number, kept as the rooms' identity"] = function(t)
        local z = newZone()
        -- two back rooms the same way from the common room: numbered in the data, said plain
        z.rooms[2] = { 1, "back room 2", "room", { 0, 0, 10, 10 } }
        z.doors[2] = { 3, 1, 1, 10.5, 5, 1, 0, 1 }
        z.spoken = { ["back room 2"] = "back room", ["stairs to the back room 2"] = "stairs to the back room" }
        logic.unpack(z)
        t:assertEqual(logic.describeRoom(z, 2, 1), "back room")
        t:assertEqual(logic.describeRoom(z, 2, nil), "Test Inn, back room")
        t:assertEqual(z._index.rooms[2].name, "back room 2")   -- the identity keeps the number
        -- the doorways into both said once, with both directions
        local items = logic.roomDoorways(z, 1)
        local backRooms = 0
        for _, item in ipairs(items) do
            if item.label == "back room" then
                backRooms = backRooms + 1
            end
        end
        t:assertEqual(backRooms, 1)
        -- a label said as it is: only where it stands as a name of its own
        t:assertEqual(logic.spokenText(z, "back room 2 to the east, stairs to the back room 2"),
            "back room to the east, stairs to the back room")
        t:assertEqual(logic.spokenText(z, "back room 20"), "back room 20")
        t:assertEqual(logic.spokenText(z, "the back room 2, 8 yards"), "the back room, 8 yards")
    end,

    ["the wall of a building named only by its place is the place's"] = function(t)
        local z = newZone()
        z.interiors[1].w = "Test Town"
        logic.unpack(z)
        local owner, what = logic.wallOwner(z, -1, 5, 1, 0, 3)
        t:assertEqual(owner, "Test Town")
        t:assertEqual(what, "place")
        owner, what = logic.wallOwner(z, 29, 5, 1, 0, 3)       -- the barn keeps its name
        t:assertEqual(owner, "Test Barn")
        t:assertNil(what)
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

    ["a hall counts only on the floor piece it lies on, the game's area only makes it certain"] = function(t)
        local z = newZone()
        -- the barn moved to row 1, column 4 (x 80..90, y 10..20): a canal hall on the zone's floor
        -- piece 7, deep under the ground's floor there (both in the cell)
        z.rooms[4][4] = { 80, 10, 90, 20 }
        z.rooms[4].g, z.rooms[4].ar, z.rooms[4].zp = 1458, "Canals", { 7 }
        table.insert(z.floorCells, 1); table.insert(z.floorCells, 4); table.insert(z.floorCells, 7); table.insert(z.floorCells, 40000)
        logic.unpack(z)
        t:assertFalse(logic.inHallFloor(z, 85, 15, 1458, 0))     -- up on the ground over it: not in it
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 7))      -- on its floor piece
        t:assertFalse(logic.inHallFloor(z, 85, 15, 1420, 7))     -- the game's map elsewhere
        -- the game names its area: on its floor piece; another area, or already on it: nothing
        t:assertEqual(logic.hallPieceForArea(z, 85, 15, 1458, "Canals", 0), 7)
        t:assertNil(logic.hallPieceForArea(z, 85, 15, 1458, "Ruins of Lordaeron", 0))
        t:assertNil(logic.hallPieceForArea(z, 85, 15, 1458, "Canals", 7))
        t:assertNil(logic.hallPieceForArea(z, 85, 15, 1458, "", 0))
        -- a hall on the ground and on piece 7: on the ground only where its floor is the ground
        local function onBoth(hallGround)
            local z2 = newZone()
            z2.rooms[4][4] = { 80, 10, 90, 20 }
            z2.rooms[4].g, z2.rooms[4].zp = 1458, { 0, 7 }
            z2.hallGround = hallGround
            logic.unpack(z2)
            return z2
        end
        z = onBoth({})
        t:assertFalse(logic.inHallFloor(z, 85, 15, 1458, 0))     -- the ground here is other floor (a courtyard over it)
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 7))
        z = onBoth({ 1, 4 })
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 0))      -- here its floor is the ground
        -- on the ground the game's area must not name another place than the hall's own
        z._index.rooms[4].subzone = "Test Quarter"
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 0, false, "Test Quarter"))
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 0, false, ""))
        t:assertFalse(logic.inHallFloor(z, 85, 15, 1458, 0, false, "Test Ruins"))
        t:assertTrue(logic.inHallFloor(z, 85, 15, 1458, 7, false, "Test Ruins"))   -- its own floor piece
        -- two halls with no doorway between them and no floor piece in common are apart
        z = newZone()
        z.rooms[1].g, z.rooms[1].zp = 1458, { 0 }
        z.rooms[3].g, z.rooms[3].zp = 1458, { 7 }
        z.rooms[4].g, z.rooms[4].zp = 1458, { 0, 7 }
        logic.unpack(z)
        t:assertTrue(logic.hallsApart(z, 1, 4) == false)          -- a piece in common
        t:assertTrue(logic.hallsApart(z, 3, 4) == false)
        z.rooms[4].zp = { 9 }
        z._index = nil
        logic.unpack(z)
        t:assertTrue(logic.hallsApart(z, 1, 4))                   -- nothing in common, no doorway
        -- a hall whose pieces are not known: only keeps the player in the halls
        z = newZone()
        z.rooms[4].g = 1458
        logic.unpack(z)
        t:assertFalse(logic.inHallFloor(z, 35, 5, 1458, 0))
        t:assertTrue(logic.inHallFloor(z, 35, 5, 1458, 0, true))
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

    ["a doorway with its width is crossed anywhere across its opening"] = function(t)
        local z = newZone()
        -- the back room's doorway at x = 10.5, y = 5: 4 yd off its centre the old 3 yd circle
        -- missed the crossing; with the opening 5 yd to either side it counts, 7 yd off not
        logic.unpack(z)
        t:assertNil(logic.crossedDoor(z, 3, 11, 9, 10, 9))
        logic.pack(z)
        z.doors[2][9] = 5
        logic.unpack(z)
        t:assertEqual(logic.crossedDoor(z, 3, 11, 9, 10, 9), 2)
        t:assertNil(logic.crossedDoor(z, 3, 11, 12, 10, 12))
        t:assertNil(logic.crossedDoor(z, 3, 15, 9, 14, 9))           -- 3.5 yd from its plane
    end,

    ["one step through two doorways side by side takes the one whose room fits"] = function(t)
        local z = newZone()
        -- a second doorway of the common room 0.8 yd before the stairs', into the back room (the
        -- Trade Quarter's: the canal tunnel's doorway under the shop's)
        table.insert(z.doors, 3, { 1, 3, 1, 5, 4.2, 0, 1, -1 })
        logic.unpack(z)
        t:assertEqual(logic.crossedDoor(z, 1, 5, 3, 5, 7), 3)
        t:assertEqual(logic.crossedDoor(z, 1, 5, 3, 5, 7, function(id) return id ~= 3 end), 2)
        t:assertNil(logic.crossedDoor(z, 1, 5, 3, 5, 7, function() return false end))
    end,

    ["a room entered through a doorway holds while its floor is near, even over another room's floor"] = function(t)
        local z = newZone()
        -- the landing's floor shrunk to a patch in the common room's middle (the Abbey's stairs:
        -- a stair surface of two big triangles came out as dots)
        z.rooms[2][4] = { 4, 4, 6, 6 }
        logic.unpack(z)
        t:assertEqual(logic.resolveRoom(z, 5, 7, 1, 5, 3), 2)             -- up the stairs through their door
        t:assertEqual(logic.resolveRoom(z, 7.5, 5, 2, 5, 5), 1)           -- a step on: only the common room's floor
        t:assertEqual(logic.resolveRoom(z, 7.5, 5, 2, 5, 5, true), 2)     -- ... but entered by the door: the stairs hold
        t:assertEqual(logic.resolveRoom(z, 9, 5, 2, 7.5, 5, true), 2)     -- 3 yd off their floor, 4 from their door: still held
        t:assertEqual(logic.resolveRoom(z, 5, 9.5, 2, 5, 8.5, true), 1)   -- beyond both (the back room door is at x 10.5): left them
        t:assertEqual(logic.resolveRoom(z, 15, 5, 1, 14, 5, true), 3)     -- holding never blocks a clear room elsewhere
        t:assertEqual(logic.resolveRoom(z, 5, 3, 2, 5, 7, true), 1)       -- a doorway crossing still wins
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

    ["a room of the city's own complex never names the city"] = function(t)
        local z = newHallZone()
        logic.unpack(z)
        t:assertEqual(logic.describeRoom(z, 1, nil), "great hall")
        t:assertEqual(logic.describeRoom(z, 2, 1), "shop")
    end,

    ["a city complex's room says its district only from another district"] = function(t)
        local function quarters()
            local z = newHallZone()
            z.rooms[1].d = "Trade Quarter"                 -- the quarter's hall: its name is the district
            z.rooms[3] = { 1, "canal, Trade Quarter 4", "corridor", { 70, 0, 80, 10 }, f = 90, d = "Trade Quarter", sn = "canal 4" }
            z.rooms[4] = { 1, "canal, War Quarter 2", "corridor", { 70, 50, 80, 60 }, f = 90, d = "War Quarter", sn = "canal 2" }
            z.locales = { deDE = { roomsShort = { "", "", "Kanal 4", "Kanal 2" },
                rooms = { "Handwerksviertel", "Laden", "Kanal, Handwerksviertel 4", "Kanal, Kriegsviertel 2" } } }
            return z
        end
        local z = quarters()
        logic.unpack(z)
        t:assertEqual(logic.describeRoom(z, 3, 1), "canal 4")                  -- from the quarter's hall
        t:assertEqual(logic.describeRoom(z, 4, 3), "canal, War Quarter 2")     -- into another district
        t:assertEqual(logic.describeRoom(z, 3, nil), "canal, Trade Quarter 4") -- the describe key: all of it
        t:assertEqual(logic.describeRoom(z, 3, 2), "canal, Trade Quarter 4")   -- from a room that names none
        z = quarters()
        logic.unpack(z, "deDE")
        t:assertEqual(logic.describeRoom(z, 3, 1), "Kanal 4")
        t:assertEqual(logic.describeRoom(z, 4, 1), "Kanal, Kriegsviertel 2")
    end,

    ["a way between two places says only the other one from either"] = function(t)
        local z = newHallZone()
        z.rooms[1].e = "War Quarter"                   -- the quarter's hall: a place ways join
        z.rooms[2].e = "canal"                         -- a canal
        z.rooms[3] = { 1, "passage between War Quarter and canal", "corridor", { 70, 0, 80, 10 }, f = 25,
            d = "way War Quarter|canal", sn = "passage", wa = "War Quarter", wb = "canal",
            ta = "passage to canal", tb = "passage to War Quarter" }
        z.rooms[4][2] = "passage between War Quarter and canal"
        z.rooms[4].d, z.rooms[4].sn = "way War Quarter|canal", "passage"
        logic.unpack(z)
        t:assertEqual(logic.describeRoom(z, 3, 2), "passage to War Quarter")   -- from the canal
        t:assertEqual(logic.describeRoom(z, 3, 1), "passage to canal")         -- from the quarter
        t:assertEqual(logic.describeRoom(z, 3, 4), "passage")                  -- inside the way
        t:assertEqual(logic.describeRoom(z, 3, nil), "passage between War Quarter and canal")
    end,

    ["a big room never guides to a doorway into another piece of the same thing"] = function(t)
        local z = newHallZone()
        z.rooms[3][2] = "great hall"     -- the passage west of it is a piece of the same hall
        logic.unpack(z)
        -- 2 yd from the passage's doorway (80, 5): the way out (100, 25) is the target, not the seam
        local _d, door = logic.nearestDoorway(z, 1, 82, 6, 40)
        t:assertEqual(door.a, 0)
        t:assertNil(logic.nearestDoorway(z, 1, 82, 6, 5))
    end,

    ["a big room never guides into a niche"] = function(t)
        local z = newHallZone()
        z.rooms[3].ni = 1                -- the passage west of the hall as a niche: a small dead end
        logic.unpack(z)
        t:assertNil(logic.nearestDoorway(z, 1, 82, 6, 5))
        local _d, door = logic.nearestDoorway(z, 1, 82, 6, 40)
        t:assertEqual(door.a, 0)
    end,

    ["a square finds what borders it: streets, canals, water and entrances, not open land"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        t:assertEqual(logic.hasEdge(z, 10000), true)
        t:assertEqual(logic.hasEdge(z, 28000), false)   -- a street with a direction
        t:assertEqual(logic.hasEdge(z, 20000), false)   -- a street without one: a way, as a road
        t:assertEqual(logic.hasEdge(z, 30000), false)
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

    ["a square's region is the same from whichever of its cells it is first worked out"] = function(t)
        local z = newSquareZone()
        logic.unpack(z)
        local function signature(region)
            local n = 0
            for _ in pairs(region.cells) do
                n = n + 1
            end
            local parts = { tostring(n) }
            for _, m in ipairs(region.mouths) do
                parts[#parts + 1] = m.label .. "@" .. table.concat(m.points, ",")
            end
            return table.concat(parts, "|")
        end
        local value = logic.valueAt(z, 78, 35)
        local first = signature(logic.regionAt(z, 78, 35))
        local tried = 0
        for r = 0, z.rows - 1 do
            for c = 0, z.cols - 1 do
                local x, y = logic.cellCentre(z, r, c)
                if logic.valueAt(z, x, y) == value then
                    logic.forgetRegions(z)
                    t:assertEqual(signature(logic.regionAt(z, x, y)), first)
                    tried = tried + 1
                end
            end
        end
        t:assertTrue(tried > 1)
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
        z.floorCells, z.noGround, z.liquids = {}, {}, {}   -- (row 4 is the square here: no canal)
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

    ["a small room cut into pieces of one name says through each its own doorway beyond"] = function(t)
        local z = newZone()
        -- a hall in three pieces along +x (north) in the barn: the lift south of the first, a
        -- niche north of the last (walk 2026-10-15: the Undercity's lift halls)
        z.rooms[5] = { 2, "hall", "room", { 30, 20, 35, 25 } }
        z.rooms[6] = { 2, "hall", "room", { 35, 20, 40, 25 } }
        z.rooms[7] = { 2, "hall", "room", { 40, 20, 45, 25 } }
        z.rooms[8] = { 2, "lift", "lift shaft", { 25, 20, 30, 25 } }
        z.rooms[9] = { 2, "niche", "room", { 45, 20, 50, 25 } }
        z.doors[4] = { 8, 5, 2, 30, 22.5, 1, 0, -1 }
        z.doors[5] = { 5, 6, 2, 35, 22.5, 1, 0, -1 }
        z.doors[6] = { 6, 7, 2, 40, 22.5, 1, 0, -1 }
        z.doors[7] = { 7, 9, 2, 45, 22.5, 1, 0, -1 }
        -- through door 5 from the first piece into the middle the niche's doorway (7), back the lift's (4)
        z.doorVia = { 0, 0, 0, 0, 0, 0, 0, 0, 7, 4, 7, 4, 0, 0 }
        logic.unpack(z)
        -- the middle piece: the lift through the doorway south, the niche through the one north
        local items = logic.roomDoorways(z, 6)
        t:assertEqual(#items, 2)
        t:assertEqual(items[1].label, "lift")
        t:assertEqual(items[1].dirs[1], 180)
        t:assertEqual(items[2].label, "niche")
        t:assertEqual(items[2].dirs[1], 0)
        -- the piece at the lift: the lift, and the niche through the next piece
        items = logic.roomDoorways(z, 5)
        t:assertEqual(#items, 2)
        t:assertEqual(items[1].label, "lift")
        t:assertEqual(items[2].label, "niche")
        t:assertEqual(items[2].dirs[1], 0)
        -- stepping on from the first piece: not the way back
        items = logic.roomDoorways(z, 6, { section = true, cameFrom = 5 })
        t:assertEqual(#items, 1)
        t:assertEqual(items[1].label, "niche")
        -- numbered rooms said alike are one thing too: "hall 2" in the middle
        z.rooms[6][2] = "hall 2"
        z._index = nil
        logic.unpack(z)
        items = logic.roomDoorways(z, 6)
        t:assertEqual(#items, 2)
        t:assertEqual(items[1].label, "lift")
        t:assertEqual(items[2].label, "niche")
        -- walking on through it: its only way on leads through the same thing, no choice, unsaid
        t:assertEqual(logic.sectionText(z, 6, 5, nil, 37, 22), nil)
        -- a doorway into a room said alike with no doorway out beyond it: that room, as before
        z.doorVia[11] = 0
        z._index = nil
        logic.unpack(z)
        items = logic.roomDoorways(z, 6)
        t:assertEqual(items[2].label, "hall")
        z.rooms[6][2] = "hall"
        -- data without doorVia: the middle piece says nothing, as before
        z.doorVia, z._index = nil, nil
        logic.unpack(z)
        t:assertEqual(#logic.roomDoorways(z, 6), 0)
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
        t:assertEqual(logic.outdoorValue(z, 95, 5, false), 38090)          -- on the bridge
        logic.setFloor(z, 3)                                              -- on the lake's piece
        local v, decided = logic.outdoorValue(z, 95, 5, true)
        t:assertEqual(v, 50000)
        t:assertEqual(decided, false)
        logic.setFloor(z, 0)
        t:assertEqual(logic.outdoorValue(z, 75, 30, false), 0)             -- no data
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
        -- 5 yd north of the inn's door (world 0, 5); one goes in toward the north
        local target = logic.footTarget(z, 5, 5)
        t:assertEqual(target.kind, "entrance")
        t:assertEqual(target.reach, logic.GUIDE_REACH)   -- kept while within it (module checkGuide)
        t:assertEqual(logic.guideText(z, target, true, false), "entrance of Test Inn, common room, 5 to the south, in to the north")
        -- a repeat: the yards and the direction; at it: the way through (user 2026-10-01)
        t:assertEqual(logic.guideText(z, target, false, false), "5 south")
        t:assertEqual(logic.guideText(z, target, false, true), "in to the north")
        t:assertEqual(logic.guideText(z, target, true, true), "in to the north")
        t:assertNil(logic.footTarget(z, 20, 5))   -- beyond the guidance reach
        target = logic.exitTarget(z, 95, 30, 3)
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
        -- 6 yd west of the foot (y 50): the ramp by name with the way on up it (no "up" since
        -- 2026-10-04), then only the yards and the direction, at it only the way on
        local target = logic.footTarget(z, 92, 50)
        t:assertEqual(target.kind, "climb")
        t:assertEqual(logic.guideText(z, target, true, false), "ramp to the bank, 6 to the east, on to the northeast")
        t:assertEqual(logic.guideText(z, target, false, false), "6 east")
        t:assertEqual(logic.guideText(z, target, false, true), "on to the northeast")
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
        -- standing on the ramp 4 yd beside its foot: not its target any more; within 3 yd of the
        -- foot it stays ("up to the northeast" is said there)
        target = logic.footTarget(z, 92, 48)
        t:assertEqual(logic.pastTarget(z, target, 92, 48), false)
        t:assertEqual(logic.onClimb(z, target, 92, 48, nil), true)
        target = logic.footTarget(z, 92, 46.5)
        t:assertEqual(logic.onClimb(z, target, 92, 46.5, nil), false)
        -- another climb under the feet (a different value): still guided to this foot
        target = logic.footTarget(z, 92, 48)
        target.value = 22090
        t:assertEqual(logic.onClimb(z, target, 92, 48, nil), false)
    end,

    ["in a fork that names a climb among its ways the climb's foot is not guided to"] = function(t)
        local function zoneWithFork(label)
            local z = newWalkZone()
            z.dirs = { "running %s", "up to the %s" }
            z.places = { { "square", "square of Test" }, { "ramp", "ramp to the bank" }, { "fork", label } }
            -- the fork in row 2, column 1 (x 88 to 92, y 52 to 56); the ramp's foot at (92, 48)
            z.grid = { "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000,30000,22045*3,0*2", "10000*2,22045*3,0*2" }
            z.lanes = {}
            z.climbFeet = { 92, 48, 22045 }
            logic.unpack(z)
            return z
        end
        -- the fork lists the ramp with its direction tag, as the data keeps it: the fork said it
        local z = zoneWithFork("fork, square of Test <d270,0>, ramp to the bank <d45>")
        t:assertNil(logic.footTarget(z, 90, 53))
        -- a fork that does not list the ramp: its foot is guided to there too
        z = zoneWithFork("fork, square of Test <d270,0,180>")
        t:assertEqual(logic.footTarget(z, 90, 53).kind, "climb")
    end,

    ["fallen off a climb with a floor piece of its own its foot is still guided to"] = function(t)
        local z = newWalkZone()
        z.dirs = { "running %s", "up to the %s" }
        z.places = { { "square", "square of Test" }, { "ramp", "ramp to the bank" } }
        z.grid = { "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2" }
        z.lanes = {}
        z.climbFeetFields = 4
        z.climbFeet = { 92, 44, 22045, 60 }
        -- the ramp is floor piece 1 over the ground, from its foot's cell up to the northeast
        z.floorCells = { 2, 4, 1, 22045, 1, 3, 1, 22045, 1, 4, 1, 22045 }
        logic.unpack(z)
        -- walking by on the ground, never on the ramp: past its foot as before
        local target = logic.footTarget(z, 94, 40.5)
        t:assertEqual(logic.belowClimb(z, target), false)
        t:assertEqual(logic.pastTarget(z, target, 94, 40.5), true)
        -- walked down the ramp and off it (no fall): the same
        z._index.floor, z._index.cameFrom = 0, 1
        t:assertEqual(logic.belowClimb(z, target), false)
        -- fallen off its side onto the ground 4 yd up the ramp's way from its foot (the ground
        -- painted with the ramp): neither past the foot nor on the ramp
        -- (what updateFloor leaves after a fall from piece 1: a drop edge of it crossed)
        z._index.floor, z._index.cameFrom, z._index.fellFrom = 0, 1, 1
        target = logic.footTarget(z, 94, 40.5)
        t:assertEqual(target.kind, "climb")
        t:assertEqual(logic.belowClimb(z, target), true)
        t:assertEqual(logic.pastTarget(z, target, 94, 40.5), false)
        target = logic.footTarget(z, 92, 48)
        t:assertEqual(logic.onClimb(z, target, 92, 48, nil), false)
        -- up on the ramp's piece the rules hold as before
        logic.setFloor(z, 1)
        t:assertEqual(logic.belowClimb(z, target), false)
        t:assertEqual(logic.onClimb(z, target, 92, 48, nil), true)
        t:assertEqual(logic.pastTarget(z, target, 94, 40.5), true)
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
        local target = logic.exitTarget(z, 95, 30, 3)
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
        local value, yards = logic.pieceAhead(z, 92, 46, math.pi, 21000, logic.AHEAD_LOOK)
        t:assertEqual(value, 21045)
        -- the distance along the line (4 yd to the bend, then onto the next stretch)
        t:assertEqual(math.floor(yards * 10 + 0.5) / 10, 5.4)
        t:assertEqual(logic.describe(z, value, true), "canal walk, northeast to southwest")
        -- walking north, away from it: nothing ahead
        t:assertNil(logic.pieceAhead(z, 96, 46, 0, 21000, logic.AHEAD_LOOK))
    end,

    ["a piece is stepped onto from the ground, not from a piece lying over the ground there"] = function(t)
        local z = newWalkZone()
        -- the landing (piece 1) joins the ground at x 90, y 50; piece 2 lies on the same cells
        -- (the Brill tavern's room upstairs over the cellar stairs' top) and joins piece 1 at x 86
        z.floorCells = { 2, 2, 1, 10000, 2, 3, 1, 10000, 2, 2, 2, 10000, 2, 3, 2, 10000 }
        z.joins = { 0, 1, 90, 50, -1, 1, 2, 86, 50, 180 }
        logic.unpack(z)
        -- from the ground the step joins it
        logic.updateFloor(z, 90, 50, false, 90, 52)
        t:assertEqual(z._index.floor, 1)
        -- up on piece 2 the ground's join is no join: the floor stays
        logic.setFloor(z, 2)
        logic.updateFloor(z, 90, 50, false, 90, 52)
        t:assertEqual(z._index.floor, 2)
        -- from piece 1 over its join into piece 2, and back the other way
        logic.setFloor(z, 1)
        logic.updateFloor(z, 85, 50, false, 88, 50)
        t:assertEqual(z._index.floor, 2)
        logic.updateFloor(z, 88, 50, false, 85, 50)
        t:assertEqual(z._index.floor, 1)
        -- a fall over the landing's edge lands on the ground (u = 0)
        z.structs, z.structCells = { "landing" }, { 2, 2, 1, 2, 3, 1 }
        z.edges = { { 1, 90, 3, 0, 0, 90, 44, 86, 44, l = 1, u = 0 } }
        logic.pack(z)
        logic.unpack(z)
        logic.setFloor(z, 1)
        logic.updateFloor(z, 88, 42, false, 88, 46)
        t:assertEqual(z._index.floor, 0)
    end,

    ["a kept floor is found again by the place it carries at the spot, not by its number"] = function(t)
        local z = newWalkZone()
        -- piece 1 carries the square at (2, 2), piece 2 the canal walk at (2, 3) next to it
        z.floorCells = { 2, 2, 1, 10000, 2, 3, 2, 21000 }
        logic.unpack(z)
        t:assertEqual(logic.pieceLabel(z, 90, 50, 1), "square of Test")
        t:assertEqual(logic.pieceLabel(z, 90, 50, 0), nil)
        t:assertEqual(logic.pieceLabel(z, 90, 50, 2), nil)
        -- a number from before a re-export means another piece now: the label decides
        t:assertEqual(logic.pieceWithLabel(z, 90, 50, "square of Test", 7), 1)
        t:assertEqual(logic.pieceWithLabel(z, 90, 50, "canal walk", 2), 2)
        t:assertEqual(logic.pieceWithLabel(z, 90, 50, "hall", 1), nil)
        -- without a label only the number itself, where that piece lies
        t:assertEqual(logic.pieceWithLabel(z, 90, 50, nil, 1), 1)
        t:assertEqual(logic.pieceWithLabel(z, 90, 50, nil, 5), nil)
    end,

    ["up on a piece a cell without its value reads it from the cells around, else from a joined piece"] = function(t)
        local z = newWalkZone()
        -- piece 1 (the square's landing) lists only (2, 2); piece 2 (a canal walk piece joined
        -- to it) lists (2, 4)
        z.floorCells = { 2, 2, 1, 10000, 2, 4, 2, 21000 }
        z.joins = { 1, 2, 90, 44, -1 }
        logic.unpack(z)
        logic.setFloor(z, 1)
        t:assertEqual(logic.valueAt(z, 90, 50), 10000)
        -- the cell beside it has no value of piece 1: the piece's value next door, not the paint
        t:assertEqual(logic.valueAt(z, 90, 46), 10000)
        -- two cells on, only the joined piece is there: its value
        t:assertEqual(logic.valueAt(z, 90, 42), 21000)
        -- off every piece's cells and their neighbours the paint stands
        t:assertEqual(logic.valueAt(z, 78, 34), 0)
        logic.setFloor(z, 0)
        t:assertEqual(logic.valueAt(z, 90, 46), 21000)
    end,

    ["a raised piece over other floor says its place only up on it, and its lines count only there"] = function(t)
        local z = newWalkZone()
        -- a landing (high piece 1) over the walk's cells (row 2, columns 2 and 3): up on it the
        -- square's value (100), below it the walk's (211); stepped onto from the ground at x 90,
        -- y 50; its line runs at y = 48 over the walk's line at y = 46
        z.floorCells = { 2, 2, 1, 10000, 2, 3, 1, 10000 }
        z.joins = { 0, 1, 90, 50, -1 }
        z.laneFields = 8
        z.lanes = { 100, 46, 84, 46, 21000, 20, 40, 0, 92, 48, 88, 48, 10000, 20, 40, 1 }
        logic.unpack(z)
        -- below: the walk and its line
        t:assertEqual(logic.valueAt(z, 90, 50), 21000)
        local _d, lane = logic.nearestLane(z, 90, 47)
        t:assertEqual(lane.value, 21000)
        -- stepping onto the landing: its value, its line; the walk's line below does not count
        local _f, changed = logic.updateFloor(z, 90, 50, false, 90, 52)
        t:assertEqual(z._index.floor, 1)
        t:assertEqual(changed, true)
        t:assertEqual(logic.valueAt(z, 90, 50), 10000)
        _d, lane = logic.nearestLane(z, 90, 47)
        t:assertEqual(lane.value, 10000)
        -- passing the join again leaves it where it is: a join without a direction only leads in
        _f, changed = logic.updateFloor(z, 90, 50, false, 90, 52)
        t:assertEqual(changed, false)
        -- off its cells (two cells away; the cell beside counts as still on it): below again
        logic.updateFloor(z, 90, 54, false, 90, 50)
        t:assertEqual(z._index.floor, 1)
        logic.updateFloor(z, 90, 58, false, 90, 54)
        t:assertEqual(z._index.floor, 0)
        t:assertEqual(logic.valueAt(z, 90, 50), 21000)
        -- a cell with no ground and only the piece puts the player on it (the middle of a moat)
        z.noGround = { 2, 3 }
        logic.pack(z)
        logic.unpack(z)
        logic.updateFloor(z, 90, 46, false, 90, 42)
        t:assertEqual(z._index.floor, 1)
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
        local value, yards = logic.pieceAhead(z, 92, 46, math.pi, 21000, logic.AHEAD_LOOK)
        t:assertEqual(value, 21045)
        t:assertEqual(yards, 4)
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

    ["on a bridge the street beside is not said"] = function(t)
        local z = newWalkZone()
        z.places[1] = { "bridge", "bridge" }
        logic.unpack(z)
        -- stepped off the walk onto the bridge, 11 yd west of the walk's centre line
        t:assertEqual(logic.spotText(z, 92, 57, 10000, "r2:0", { cut = true }), "bridge")
        t:assertEqual(logic.spotText(z, 92, 57, 10000, nil, {}), "bridge")
    end,

    ["inside one way only the direction changes: its name is said once"] = function(t)
        local z = newWalkZone()
        logic.unpack(z)
        -- onto the walk from the square: its name and direction
        t:assertEqual(logic.spotText(z, 96, 46, 21000, 1, { cut = true, named = 1 }), "canal walk, north to south")
        -- its next piece, the walk's name the last said: the direction only
        t:assertEqual(logic.sameWay(21045, "r2:0", 2), true)
        t:assertEqual(logic.spotText(z, 96, 46, 21045, "r2:0", { cut = true, named = 2 }), "northeast to southwest")
        -- after another way was named (the next piece ahead): the name again
        t:assertEqual(logic.sameWay(21045, "r2:0", 5), false)
        t:assertEqual(logic.spotText(z, 96, 46, 21045, "r2:0", { cut = true, named = 5 }), "canal walk, northeast to southwest")
        -- another place, or coming from no way: no
        t:assertEqual(logic.sameWay(11000, "r2:0", 1), false)
        t:assertEqual(logic.sameWay(21045, 2, 2), false)
        -- the describe key always names it
        t:assertEqual(logic.spotText(z, 96, 46, 21045, "r2:0", { named = 2 }), "canal walk, northeast to southwest")
        t:assertEqual(logic.directionText(z, 21045), "northeast to southwest")
        t:assertNil(logic.directionText(z, 20000))
    end,

    ["a room says its doorways, at most the count, the way the player came left out first"] = function(t)
        local z = newZone()
        logic.unpack(z)
        t:assertEqual(logic.roomText(z, 1, nil, false), "Test Inn, common room, way outside to the south, upstairs landing to the west")
        t:assertEqual(logic.roomText(z, 1, 2, true), "common room, way outside to the south, upstairs landing to the west")
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

    ["off a street at its end the square's ways on; stepping off it sideways where the street is"] = function(t)
        local z = newSquareZone()
        -- the street goes on into a road at the north: it leads on, so it begins on the square
        table.insert(z.places, { "road", "road of Test" })
        z.grid[1] = "30000*2,28000*2,60000,30000*2"
        logic.unpack(z)
        local region = logic.regionAt(z, 78, 35)
        -- the street (place 2) begins on the square at its north side, about x 90, y 40
        t:assertEqual(logic.leftAtEnd(z, region, 2, 91, 40), true)
        t:assertEqual(logic.leftAtEnd(z, region, 2, 82, 62), false)   -- 23 yd from its beginning
        t:assertEqual(logic.leftAtEnd(z, region, 1, 91, 40), false)   -- no beginning of that place
        -- sideways: as open land, the square's name and where the street is; nothing of it comes
        -- close (every mouth counts as said)
        local text, sq, said = logic.spotText(z, 88, 35, 10000, 2, { cut = true, sideways = true })   -- 2 yd off the street
        t:assertEqual(text, "square of Test, street to the north")
        t:assertEqual(sq.label, "square of Test")
        for _, m in ipairs(sq.mouths) do
            t:assertEqual(said[m], true)
        end
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

    ["a stop on a floor piece is found only up on it: the zeppelin tower's top, not its foot"] = function(t)
        local z = newZone()
        -- a zeppelin stop whose waiting floor lies on pieces 2 and 3 (the tower's platform over
        -- the cells of row 1, cut in two by its stairs); the ship's stop on the ground (no list:
        -- data from before the field)
        z.stops = {
            { "zeppelin", "Orgrimmar", 0, { 1, 1, 1, 2 }, { 75, 40, 75, 20 }, { 2, 3 } },
            { "ship", "Test Harbor", 0, { 1, 4 }, { 75, 10, 75, 0 } },
        }
        logic.unpack(z)
        -- on the ground under the platform: nothing
        t:assertEqual(logic.stopAt(z, 85, 35, nil), nil)
        logic.setFloor(z, 2)
        t:assertEqual(logic.stopAt(z, 85, 35, nil), 1)
        t:assertEqual(logic.stopText(z, 1, 85, 35), "wait for the zeppelin to Orgrimmar, zeppelin to the south")
        logic.setFloor(z, 3)
        t:assertEqual(logic.stopAt(z, 85, 35, nil), 1)
        -- up on the platform the ground's stop is not here
        t:assertEqual(logic.stopAt(z, 85, 15, nil), nil)
        logic.setFloor(z, 0)
        t:assertEqual(logic.stopAt(z, 85, 15, nil), 2)
    end,

    ["a stop's destination comes in the client's language"] = function(t)
        local z = newZone()
        z.stops = { { "tram", "Stormwind City", 0, { 1, 0 }, { 80, 50, 80, 58 } } }
        z.locales = { deDE = { stops = { "Sturmwind" } } }
        logic.unpack(z, "deDE")
        t:assertEqual(logic.stopText(z, 1, 85, 55), "wait for the tram to Sturmwind, tram to the south")
    end,

    ["a named floor is said once: its rooms and the stairs up to it without it on it"] = function(t)
        -- user 2026-10-04 upstairs in the Brill tavern: "Obergeschoss, Treppe Richtung Obergeschoss
        -- at 12, Raum Südost, Obergeschoss at 5"
        local z = { floors = { { "Obergeschoss", "Obergeschoss", "Treppe Richtung Obergeschoss", "Treppe" } } }
        local i, bare = logic.floorOf(z, "Raum Südost, Obergeschoss")
        t:assertEqual(i, 1)
        t:assertEqual(bare, "Raum Südost")
        t:assertEqual(logic.floorOf(z, "Obergeschoss"), 1)
        t:assertEqual(select(2, logic.floorOf(z, "Treppe Richtung Obergeschoss")), "Treppe")
        t:assertNil(logic.floorOf(z, "Schankraum"))
        t:assertNil(logic.floorOf(z, "Raum, erster Stock"))
        -- on the floor: without it; elsewhere (no floor, the common room below) the full name
        t:assertEqual(logic.floorLabel(z, "Raum Südost, Obergeschoss", 1), "Raum Südost")
        t:assertEqual(logic.floorLabel(z, "Treppe Richtung Obergeschoss", 1), "Treppe")
        t:assertEqual(logic.floorLabel(z, "Obergeschoss", 1), "Obergeschoss")
        t:assertEqual(logic.floorLabel(z, "Raum Südost, Obergeschoss", nil), "Raum Südost, Obergeschoss")
        t:assertEqual(logic.floorLabel(z, "Schankraum", 1), "Schankraum")
    end,

    ["a ramp is a way keyed per flight, said like a street; its side is named when bumped"] = function(t)
        local z = newWalkZone()
        -- the walk's columns (y 52 to 40) are a ramp rising to the northeast
        z.dirs = { "running %s", "up to the %s" }
        z.places = { { "square", "square of Test" }, { "ramp", "ramp to the bank" }, { "stairs", "stairs" }, { "ramp", "ramp" } }
        z.grid = { "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2", "10000*2,22045*3,0*2" }
        z.lanes = { 100, 46, 84, 46, 22045, 20, 40 }
        logic.unpack(z)
        -- keyed by the way it rises (each flight its own piece), said with its axis: the same up or down
        t:assertEqual(logic.outdoorKey(z, 22045), "r2:u2")
        t:assertEqual(logic.describe(z, 22045, true), "ramp to the bank, " .. logic.axisWords(z, 45))
        -- a flight rising the other way (the Brill tavern's stairs: up north, then up south) is
        -- another piece, said with the same axis
        t:assertEqual(logic.outdoorKey(z, 22225), "r2:u6")
        t:assertEqual(logic.directionText(z, 22225), logic.directionText(z, 22045))
        t:assertEqual(logic.sameWay(22225, "r2:u2", 2), true)
        -- a winding climb's flights called stairs and ramp by turns: a plain one straight after a
        -- climb says only its direction; one named after where it leads says its name (places 3
        -- and 4: plain stairs and ramp)
        t:assertEqual(logic.sameWay(30032, "r4:u1", 4, z), true)
        t:assertEqual(logic.sameWay(40127, "r3:u1", 4, z), true)
        t:assertEqual(logic.sameWay(22045, "r4:u1", 4, z), false)
        t:assertEqual(logic.sameWay(30032, "r4:u1", 4), false)
        t:assertEqual(logic.sameWay(30032, 1, 1, z), false)
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
        t:assertEqual((logic.outdoorValue(z, 92, 50, false)), 21000)
        -- 6 yd off the line, past its leave distance: the square again
        t:assertEqual((logic.outdoorValue(z, 92, 44, true)), 10000)
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
            -- a list's "o'clock" follows its last hour, not a text appended after it (the describe
            -- key said "fork, ... at 5, 5 at 2 o'clock, canal o'clock")
            t:assertEqual(logic.finishText(logic.itemsText(z, {
                { label = "street of Test", class = "way", dirs = { 0, 270 } },
            }) .. ", " .. logic.edgeText(z, 2, 7.6)), "street of Test at 12 and 9 o'clock, 8 at 6 o'clock, drop 12")
            -- an edge ahead is said toward the point in the path, an edge beside by its drop
            t:assertEqual(logic.finishText(logic.edgeText(z, 2, 7.6, 80, 14.5, 87.6, 14.5)), "8 at 12 o'clock, drop 12")
            t:assertEqual(logic.finishText(logic.edgeText(z, 2, nil, 80, 14.5, 87.6, 14.5)), "at 6, drop 12")
            local target = logic.footTarget(z, 5, 5)
            t:assertEqual(logic.finishText(logic.guideText(z, target, true, false)),
                "entrance of Test Inn, common room, 5 yards at 6 o'clock, in at 12")
            t:assertEqual(logic.finishText(logic.guideText(z, target, false, false)), "5 at 6 o'clock")
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
        t:assertEqual(logic.finishText(logic.turnText(1)), "left")
        t:assertEqual(logic.expandDirs(z, "fork, Test road <d120,45>"), "fork, Test road to the northeast and southeast")
        t:assertEqual(logic.finishText("no hours"), "no hours")
        if not ok then
            error(err, 0)
        end
    end,
})
