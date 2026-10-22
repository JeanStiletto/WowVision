local testRunner = WowVision.testing.testRunner
local logic = WowVision.surroundingsLogic

-- A square with a turning stairs (piece 1) and a landing (piece 2): 4 rows x 7 columns of 4 yd cells, north edge at
-- x = 100, west edge at y = 60. The stairs' own line: from its foot at 97, 50 north to 93, 50, west to 93, 54, north
-- to 89, 54 (three stretches, a turn at each end of the middle one, as a spiral's). The ground joins it at the foot;
-- the landing joins it at 88, 54 (unless `noLanding`).
local function stairsZone(noLanding)
    local z = {
        key = "stairs", map = 0, top = 100, left = 60, cell = 4, rows = 4, cols = 7,
        dirs = { "running %s" },
        compass = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" },
        axes = { "north-south", "northeast-southwest", "east-west", "northwest-southeast" },
        places = { { "square", "square of Test" }, { "stairs", "stairs to the landing" }, { "platform", "landing" } },
        grid = { "10000*7", "10000*7", "10000*7", "10000*7" },
        laneFields = 10,
        lanes = {
            97, 50, 93, 50, 20000, 10, 15, 10, 15, 1,
            93, 50, 93, 54, 20000, 10, 15, 10, 15, 1,
            93, 54, 89, 54, 20000, 10, 15, 10, 15, 1,
        },
        lineFloors = { 1 },
        floorCells = { 0, 1, 1, 30000, 0, 2, 1, 20000, 1, 1, 1, 20000, 1, 2, 1, 20000 },
        noGround = {},
        joins = noLanding and { 0, 1, 97, 50, 0 } or { 0, 1, 97, 50, 0, 1, 2, 88, 54, 0 },
        climbFeetFields = 5,
        climbFeet = { 97, 50, 20000, 0, 0 },
    }
    logic.unpack(z)
    return z
end

-- A U-shaped staircase (cells of 4 yd, north edge x = 100, west edge y = 60): the lower flight (piece 1) from the
-- ground at 88, 50 north to the landing (piece 2, a strip along x = 98 from y 50 to 42), the upper flight (piece 3)
-- from the landing at 96, 42 south to the floor upstairs (piece 4) at 88, 42. Both flights said "north to south".
local function landingZone()
    local z = {
        key = "landing", map = 0, top = 100, left = 60, cell = 4, rows = 4, cols = 7,
        dirs = { "running %s" },
        compass = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" },
        axes = { "north-south", "northeast-southwest", "east-west", "northwest-southeast" },
        places = { { "square", "square of Test" }, { "stairs", "stairs to the upstairs" }, { "platform", "upstairs" } },
        grid = { "10000*7", "10000*7", "10000*7", "10000*7" },
        laneFields = 10,
        lanes = {
            90, 50, 94, 50, 20180, 10, 15, 10, 15, 1,
            98, 49, 98, 48, 20180, 10, 15, 10, 15, 2,
            94, 42, 90, 42, 20180, 10, 15, 10, 15, 3,
        },
        lineFloors = { 1, 2, 3 },
        floorCells = {
            1, 2, 1, 20180, 2, 2, 1, 20180,
            0, 2, 2, 20090, 0, 3, 2, 20090, 0, 4, 2, 20090,
            1, 4, 3, 20180, 2, 4, 3, 20180,
            3, 4, 4, 30000,
        },
        noGround = {},
        joins = { 0, 1, 88, 50, 0, 1, 2, 96, 50, 0, 2, 3, 96, 42, 0, 3, 4, 88, 42, 0 },
    }
    logic.unpack(z)
    return z
end

local function facesToward(t, f, x, y, tx, ty, what)
    t:assertNotNil(f, what)
    local want = math.rad(-logic.bearingOf(tx - x, ty - y))
    t:assertTrue(math.abs(logic.degreesBetween(f, want)) < 1, what)
end

local function near(t, p, x, y, what)
    t:assertTrue(math.abs(p.x - x) < 0.01 and math.abs(p.y - y) < 0.01,
        string.format("%s: expected %.1f %.1f, got %.1f %.1f", what, x, y, p.x, p.y))
end

testRunner:addSuite("Surroundings building helper", {
    ["from a climb's foot along its whole line, to the landing's join at its end"] = function(t)
        local z = stairsZone()
        local route = logic.climbRoute(z, 97, 50, 0)
        t:assertNotNil(route)
        t:assertEqual(route.piece, 1)
        t:assertEqual(route.landing, 2)
        t:assertFalse(route.short)
        local p = route.points
        near(t, p[1], 97, 50, "the foot")
        near(t, p[2], 93, 50, "the first turn")
        near(t, p[3], 93, 54, "the second turn")
        near(t, p[4], 89, 54, "the line's end")
        near(t, p[5], 88, 54, "the landing's join")
        t:assertEqual(#p, 5, "no point of its own beyond the join")
    end,

    ["a line that ends before any landing ends the route there, said as short"] = function(t)
        local z = stairsZone(true)
        local route = logic.climbRoute(z, 97, 50, 0)
        t:assertTrue(route.short)
        t:assertNil(route.landing)
        near(t, route.points[#route.points], 89, 54, "the line's end")
    end,

    ["on the climb: from the nearest point on toward the end the player faces"] = function(t)
        local z = stairsZone()
        -- on the middle stretch facing west (+y): up, from its far end on
        local up = logic.climbRouteFrom(z, 1, 93, 52, math.pi / 2)
        near(t, up.points[1], 93, 54, "the next turn up")
        t:assertEqual(up.landing, 2)
        -- facing east (-y): down to the foot, onto the ground there
        local down = logic.climbRouteFrom(z, 1, 93, 52, -math.pi / 2)
        near(t, down.points[1], 93, 50, "the turn below")
        near(t, down.points[2], 97, 50, "the foot")
        t:assertEqual(down.landing, 0)
    end,

    ["along the floor only to a foot a climb goes up from, never down from a foot stored at a climb's top"] = function(t)
        -- (the Abbey main ramp's foot stored on the gallery at its top in trial K9: Alt-I led down, walk 2026-10-19)
        local z = stairsZone()
        for i = 5, #z.lanes, z.laneFields do
            z.lanes[i] = 20180   -- the stairs rise toward 180 (south), from the foot at 97, 50 to the landing
        end
        z.climbFeet = { 97, 50, 20180, 180, 0, 88, 54, 20180, 180, 2 }
        logic.unpack(z)
        t:assertNil(logic.floorClimbRoute(z, 2, 86, 54))
        local up = logic.climbRoute(z, 97, 50, 0)
        t:assertEqual(up.landing, 2)
    end,

    ["the turn key on a landing faces the flight the player did not come from, at the far end of its join"] = function(t)
        local z = landingZone()
        -- up from the lower flight: toward the upper flight's join
        facesToward(t, logic.landingFacing(z, 2, 98, 49, 0, 1), 98, 49, 96, 42, "came up: the upper flight")
        -- down from the upper flight: toward the lower flight's join
        facesToward(t, logic.landingFacing(z, 2, 98, 43, 0, 3), 98, 43, 96, 50, "came down: the lower flight")
        -- not knowing (a login on the landing): the flight nearest the facing
        local toLower = math.rad(-logic.bearingOf(96 - 98, 50 - 46))
        facesToward(t, logic.landingFacing(z, 2, 98, 46, toLower, nil), 98, 46, 96, 50, "a login: the facing's flight")
        -- a flight joined to a floor is no landing
        t:assertNil(logic.landingFacing(z, 1, 92, 50, 0, 0))
    end,

    ["the turn key at a landing's exit turns along the flight there, the way it is said with"] = function(t)
        local z = landingZone()
        -- 0.7 yd from the upper flight's join: along "north to south", toward its cells (south)
        local f = logic.landingFacing(z, 2, 96.5, 42.5, 0, 1)
        t:assertNotNil(f)
        t:assertTrue(math.abs(logic.degreesBetween(f, math.rad(-180))) < 1, "south along the flight")
    end,

    ["with end records a staircase is led through from its foot to its top, and from its top to its foot"] = function(t)
        -- user 2026-10-20: Alt-I on the climb ends; the U-staircase's foot on the ground at 88, 50 (up north), its top
        -- on the upstairs floor (piece 4) at 88, 42 (the way down north)
        local z = landingZone()
        z._index = nil
        z.climbFeetFields = 5
        z.climbFeet = { 88, 50, 20000, 0, 0 }
        z.climbTops = { 88, 42, 20000, 0, 4 }
        logic.unpack(z)
        local up = logic.endRoute(z, z._index.climbFeet[1])
        t:assertFalse(up.short)
        t:assertEqual(up.landing, 4)
        local p = up.points
        near(t, p[1], 88, 50, "the foot")
        near(t, p[2], 90, 50, "the lower flight's line")
        near(t, p[#p], 88, 42, "the top, nothing beyond")
        local down = logic.endRoute(z, z._index.climbTops[1])
        t:assertFalse(down.short)
        t:assertEqual(down.landing, 0)
        p = down.points
        near(t, p[1], 88, 42, "the top")
        near(t, p[#p], 88, 50, "the foot, nothing beyond")
        -- the guidance's target made from the top leads the same way
        local route = logic.helperRoute(z, { kind = "climb", x = 88, y = 42, value = 20000, bearing = 0, floor = 4, through = 0 })
        t:assertEqual(route.landing, 0)
    end,

    ["the turn key on a flight whose line is a stub turns along the flight, the way nearer the facing"] = function(t)
        local z = landingZone()
        z._index = nil
        z.lanes[3], z.lanes[4] = 91, 50   -- the lower flight's line a 1 yd stub
        logic.unpack(z)
        local f = logic.flightFacing(z, 1, 94, 50, 0.3)
        t:assertNotNil(f)
        t:assertTrue(math.abs(logic.degreesBetween(f, 0)) < 1, "north, nearer the facing")
        f = logic.flightFacing(z, 1, 94, 50, math.pi - 0.3)
        t:assertTrue(math.abs(logic.degreesBetween(f, math.pi)) < 1, "south, nearer the facing")
        -- a line long enough to follow: the line's rule
        t:assertNil(logic.flightFacing(landingZone(), 1, 94, 50, 0))
    end,

    ["a doorway or a way out is led to its own point, nothing beyond"] = function(t)
        local route = logic.helperRoute(nil, { kind = "doorway", x = 90, y = 40, through = 90 })
        t:assertEqual(#route.points, 1)
        near(t, route.points[1], 90, 40, "the doorway")
        local out = logic.helperRoute(nil, { kind = "exit", x = 70, y = 20, through = 248 })
        t:assertEqual(#out.points, 1)
        t:assertNil(logic.helperRoute(nil, { kind = "aim", x = 1, y = 1 }))
    end,

    ["the route ends where the surroundings' own rules put the player"] = function(t)
        local swim = { floor = 66, liquid = true, room = 5, inside = true }
        local exit = { kind = "exit" }
        t:assertFalse(logic.helperArrived(exit, swim, swim), "still in the water")
        t:assertFalse(logic.helperArrived(exit, swim, { floor = 70, liquid = true, room = 5, inside = true }),
            "another liquid's piece")
        t:assertTrue(logic.helperArrived(exit, swim, { floor = 0, liquid = false, room = 5, inside = true }),
            "on the floor beyond")
        local hall = { floor = 0, liquid = false, room = 3, inside = true }
        local door = { kind = "doorway" }
        t:assertFalse(logic.helperArrived(door, hall, hall), "the same room")
        t:assertTrue(logic.helperArrived(door, hall, { floor = 0, liquid = false, room = 4, inside = true }), "the room beyond")
        t:assertTrue(logic.helperArrived({ kind = "entrance" }, { floor = 0, inside = false },
            { floor = 0, inside = true, room = 9 }), "in the building")
        local climb = { kind = "climb", landing = 2 }
        local foot = { floor = 0, liquid = false }
        t:assertFalse(logic.helperArrived(climb, foot, { floor = 1, liquid = false }), "on the stairs")
        t:assertTrue(logic.helperArrived(climb, foot, { floor = 2, liquid = false }), "on the landing")
        t:assertNil(logic.helperArrived({ kind = "climb" }, foot, foot), "a line ending short: its last point")
        t:assertNil(logic.helperArrived({ kind = "way" }, foot, foot), "a way's beginning: its point")
    end,

    ["a point counts when reached, or when the way in's line across it is crossed close beside it"] = function(t)
        local a, w = { x = 0, y = 0 }, { x = 10, y = 0 }
        t:assertTrue(logic.helperPassed(nil, nil, 9, 0.5, a, w), "within the radius")
        t:assertTrue(logic.helperPassed(9.5, 2, 10.5, 2, a, w), "crossed 2 yd beside it")
        t:assertFalse(logic.helperPassed(9.5, 5, 10.5, 5, a, w), "crossed 5 yd beside it")
        t:assertFalse(logic.helperPassed(10.5, 2, 9.5, 2, a, w), "crossed backwards")
    end,
})
