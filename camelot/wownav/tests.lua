local testRunner = WowVision.testing.testRunner
local logic = WowVision.wownavLogic

-- The logic on WowNav's real network (the submodule mapdata/WowNav, loaded by tools/headless-tests.lua through its
-- engine.xml). Without the submodule the suite only checks the parts that need no network.
local N = _G.WowVisionNavigationNavNetwork
local G = _G.WowVisionNavigationGuidance
local haveNetwork = N ~= nil and N.RouteJob ~= nil and type(_G.WVN7Index) == "table"

local WESTFALL, STORMWIND = 52, 84

local function setup()
    N.LoadIndex()
    N.ActionAllowed = logic.actionAllowed
    N.SetComfort(50)
end

-- the first waypoint of a zone that binds to the network
local function firstBinding(zoneId)
    N.LoadZone(zoneId)
    for i = 0, 400 do
        local x, y, z = N.Position(zoneId * N.ZONE_BASE + i)
        local b = N.Bind(x, y, z, { radius = 30 })
        if b then
            return b
        end
    end
end

local suite = {
    ["an unconditional action may be routed over, any other may not"] = function(t)
        t:assertTrue(logic.actionAllowed({ conditions = { status = "unconditional", proof = "p" } }))
        t:assertFalse(logic.actionAllowed({ conditions = { status = "resolved", proof = "p" } }))
        t:assertFalse(logic.actionAllowed({ conditions = { status = "unconditional" } }))
        t:assertFalse(logic.actionAllowed({}))
    end,

    ["the route's height runs linearly between two waypoints, none while swimming"] = function(t)
        local a, b = { x = 0, y = 0, z = 10 }, { x = 10, y = 0, z = 20 }
        t:assertEqual(logic.heightAlong(a, b, 5, 0, false), 15)
        t:assertEqual(logic.heightAlong(nil, b, 5, 0, false), 20)
        t:assertNil(logic.heightAlong(a, b, 5, 0, true))
    end,

    ["walking towards the waypoint is no detour; travelling without getting closer is"] = function(t)
        local state = {}
        t:assertFalse(logic.offRoute(state, 0, 0, 0, 100, 0, true))
        -- 6 s straight at it: closer by far more than 2 yd
        t:assertFalse(logic.offRoute(state, 6, 40, 0, 100, 0, true))
        -- circling at the same distance for 11 s while moving 20 yd
        local x, y = 40, 0
        local off = false
        for s = 1, 11 do
            y = (s % 2 == 0) and 3 or -3
            off = logic.offRoute(state, 6 + s, x, y, 100, 0, true) or off
        end
        t:assertTrue(off, "no approach within the window although travelling")
    end,

    ["trying to walk without moving for 1.5 s counts once per episode"] = function(t)
        local state = {}
        logic.offRoute(state, 0, 0, 0, 100, 0, true)
        t:assertFalse(logic.offRoute(state, 1.0, 0.2, 0, 100, 0, true))
        t:assertTrue(logic.offRoute(state, 1.6, 0.3, 0, 100, 0, true))
        t:assertFalse(logic.offRoute(state, 2.5, 0.3, 0, 100, 0, true), "the same episode")
    end,

    ["WowVision's arrival radius is a waypoint's minimum radius"] = function(t)
        t:assertEqual(logic.radiusOf(4, 3), 4, "never smaller than the data's")
        t:assertEqual(logic.radiusOf(0.3, 5), 5)
        t:assertEqual(logic.radiusOf(4, nil), 4)
        t:assertNil(logic.radiusOf(nil, 3))
        -- a waypoint of a dropped zone: its copied radius, widened the same way
        local dropped = { Exists = function() return false end }
        local copy = { { x = 0, y = 0, radius = 4, id = 10 ^ 13 } }
        t:assertTrue(logic.reached(dropped, nil, copy, 1, { x = 3, y = 0, minRadius = 1 }))
        t:assertFalse(logic.reached(dropped, nil, copy, 1, { x = 4.5, y = 0, minRadius = 1 }))
        t:assertTrue(logic.reached(dropped, nil, copy, 1, { x = 4.5, y = 0, minRadius = 5 }))
        t:assertFalse(logic.reached(dropped, nil, copy, 1, { x = 5.5, y = 0, minRadius = 5 }))
    end,

    ["the final point of a route counts within the arrival distance"] = function(t)
        local waypoints = { { x = 0, y = 0, final = true } }
        t:assertTrue(logic.reached(nil, nil, waypoints, 1, { x = 1, y = 0, finalRadius = 1.5 }))
        t:assertFalse(logic.reached(nil, nil, waypoints, 1, { x = 2, y = 0, finalRadius = 1.5 }))
    end,
}

if haveNetwork then
    suite["at login no zone is decoded; a route decodes what it needs"] = function(t)
        t:assertTrue(N.ZoneAvailable(WESTFALL))
        setup()
        N.KeepZones({})
        t:assertNil(next(N.zones))
        t:assertNotNil(N.LoadZone(WESTFALL))
    end

    suite["a route across a seam becomes waypoints with their own radius"] = function(t)
        setup()
        local s, g = firstBinding(WESTFALL), firstBinding(STORMWIND)
        t:assertNotNil(s)
        t:assertNotNil(g)
        local result = N.Route(s, g)
        t:assertNotNil(result, "Westfall to Stormwind")
        local waypoints, action = logic.buildWaypoints(N, result)
        t:assertEqual(#waypoints, #N.SteeringTargets(result.path))
        for _, wp in ipairs(waypoints) do
            t:assertNotNil(wp.x)
            t:assertNotNil(wp.radius, "every steering target has a radius")
        end
        local zones = logic.routeZones(N, result, {})
        t:assertTrue(zones[s.zone.id] == true and zones[g.zone.id] == true, "the start's and the target's zones")
        -- the same route in time slices
        local tick = 0
        local job = N.RouteJob(s, g)
        local done, sliced
        local steps = 0
        repeat
            steps = steps + 1
            done, sliced = job:Step(1, function()
                tick = tick + 1
                return tick
            end)
        until done or steps > 100000
        t:assertTrue(steps > 2, "the search yielded")
        t:assertEqual(#sliced.path, #result.path)
    end

    suite["a route over a portal ends where the portal begins"] = function(t)
        setup()
        local zone = N.LoadZone(STORMWIND)
        local action
        for _, a in ipairs(zone.actions) do
            if a.kind == "portal" and logic.actionAllowed(a) then
                action = a
            end
        end
        t:assertNotNil(action, "Stormwind has a portal action")
        local fx, fy, fz = N.Position(action.fromNode)
        N.LoadZone(action.toZoneId)
        local tx, ty, tz = N.Position(action.toNode)
        local result = N.Route(N.Bind(fx, fy, fz, {}), N.Bind(tx, ty, tz, { radius = 30 }))
        t:assertNotNil(result)
        local waypoints, transit = logic.buildWaypoints(N, result)
        if logic.firstAction(result) ~= nil then
            t:assertEqual(transit, logic.firstAction(result))
            t:assertEqual(waypoints[#waypoints].id, transit.fromNode)
        end
    end

    suite["a waypoint counts by its radius; the player far off does not"] = function(t)
        setup()
        local result = N.Route(firstBinding(WESTFALL), firstBinding(STORMWIND))
        local waypoints = logic.buildWaypoints(N, result)
        local wp = waypoints[3]
        t:assertTrue(logic.reached(N, G, waypoints, 3, { x = wp.x, y = wp.y, z = wp.z }))
        t:assertFalse(logic.reached(N, G, waypoints, 3, { x = wp.x + 500, y = wp.y + 500, z = wp.z }))
        -- a dropped zone: the copied radius still holds
        local copy = { { x = wp.x, y = wp.y, radius = 4, id = 10 ^ 13 } }
        t:assertTrue(logic.reached(N, G, copy, 1, { x = wp.x + 3, y = wp.y }))
    end

    suite["on the network the arrival radius caps the data radius, the larger one changes nothing"] = function(t)
        setup()
        local result = N.Route(firstBinding(WESTFALL), firstBinding(STORMWIND))
        local waypoints = logic.buildWaypoints(N, result)
        -- a waypoint with a wide radius, alone: without a previous one only the radius rule can count it
        local wp
        for _, candidate in ipairs(waypoints) do
            wp = wp or ((N.Radius(candidate.id) or 0) >= 2 and candidate or nil)
        end
        t:assertNotNil(wp, "the route has a waypoint with a radius of 2 yd or more")
        local alone = { wp }
        local r = N.Radius(wp.id)
        local p = { x = wp.x + r * 0.9, y = wp.y, z = wp.z }
        t:assertTrue(logic.reached(N, G, alone, 1, p))
        p.minRadius = r * 0.5
        t:assertTrue(logic.reached(N, G, alone, 1, p), "a smaller arrival radius keeps the data's")
        p.minRadius = nil
        p.x = wp.x + r + 1
        t:assertFalse(logic.reached(N, G, alone, 1, p), "outside the data radius")
        p.minRadius = r + 2
        t:assertTrue(logic.reached(N, G, alone, 1, p), "a larger arrival radius widens it")
    end

    suite["off the route, a later waypoint whose cell holds the player is where it goes on"] = function(t)
        setup()
        local result = N.Route(firstBinding(WESTFALL), firstBinding(STORMWIND))
        local waypoints = logic.buildWaypoints(N, result)
        -- standing at a later waypoint while the route still leads to waypoint 2: somewhere along the route a cell
        -- there is attached to a later waypoint (not every waypoint's own spot is)
        local index
        for k = 4, #waypoints - 1 do
            local wp = waypoints[k]
            index = index or logic.rejoinIndex(N, G, waypoints, 2, wp.x, wp.y, wp.z, false)
        end
        t:assertNotNil(index)
        t:assertTrue(index > 2)
    end

    suite["stacked floors are listed lowest first, close bands as one floor"] = function(t)
        setup()
        local zone = N.LoadZone(STORMWIND)
        local found
        for i = 1, zone.cells do
            local x, y = zone.cellX[i] + zone.cellSize[i] / 2, zone.cellY[i] + zone.cellSize[i] / 2
            local floors = logic.floorsAt(N, x, y, false)
            if #floors > 1 then
                found = floors
                break
            end
        end
        t:assertNotNil(found, "Stormwind has a spot with stacked floors")
        for i = 2, #found do
            t:assertTrue(found[i].zMin - found[i - 1].zMax > logic.FLOOR_GAP)
            t:assertEqual(found[i].index, i)
        end
    end

    suite["the zone's catalog becomes destinations in the client's language"] = function(t)
        setup()
        local english = logic.zoneDestinations(N, 37, false)
        local german = logic.zoneDestinations(N, 37, true)
        t:assertTrue(#english > 100)
        t:assertEqual(#english, #german)
        t:assertEqual(english[1].id:sub(1, 7), "wownav:")
        N.DropTargets(37)
    end
end

testRunner:addSuite("WowNav routes", suite)
