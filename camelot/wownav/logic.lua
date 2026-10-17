-- WowNav as WowVision's route engine: the pure part (no WoW API), so the headless tests run it on the real network.
-- N is WowNav's NavNetwork (WowVisionNavigationNavNetwork), G its Guidance (WowVisionNavigationGuidance); both come
-- from the WowNav submodule (mapdata/WowNav, loaded through its engine.xml).
--
-- What is taken from WowNav: its route data and how it computes a route from it (entry point, target binding, the
-- search with the road preference, routes across zones), the floors at a point, and the data's own rules for
-- moving on along a route: a radius per waypoint, the gate line at narrow spots, the turning point in the open, and
-- getting back onto the route after a detour. Beacon, sounds, turning and transit guidance stay WowVision's.

local logic = {}
WowVision.wownavLogic = logic

local sqrt, min, max, floor = math.sqrt, math.min, math.max, math.floor

-- Bands closer than this belong to one floor (NavNetwork's own rule for an ambiguous height, chapter 4.1).
logic.FLOOR_GAP = 2.0
-- A target outside every cell binds to the nearest cell within this reach (NavNetwork TARGET_RADIUS).
logic.TARGET_REACH = 30
-- A target farther than this from the last network point gets its own last waypoint.
logic.FINAL_GAP = 0.5
-- Getting back onto the route (WowNav CheckApproach and CheckBlockage): the distance to the waypoint did not shrink
-- by APPROACH_GAIN within a window in which the player travelled APPROACH_TRAVEL; or the player tries to walk and
-- moves less than STUCK_MOVE over STUCK_TIME.
logic.APPROACH_WINDOW = 10
logic.APPROACH_GAIN = 2.0
logic.APPROACH_TRAVEL = 5.0
logic.STUCK_MOVE = 1.0
logic.STUCK_TIME = 1.5

local function distance(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return sqrt(dx * dx + dy * dy)
end
logic.distance = distance

-- The zones of the index whose map is the player's map and whose boxes hold the point (the index boxes are per map,
-- so a point of the tram map must not pick an Eastern Kingdoms zone).
function logic.zonesAt(N, x, y, map)
    local zones = {}
    for _, id in ipairs(N.ZonesForPoint(x, y)) do
        local entry = N.index[id]
        local native = entry and (entry.nativeMapId or entry.mapId)
        if map == nil or native == map then
            local zone = N.LoadZone(id)
            if zone then
                zones[#zones + 1] = zone
            end
        end
    end
    return zones
end

-- Whether the network covers this map at all.
function logic.coversMap(N, map)
    for _, entry in pairs(N.index) do
        if (entry.nativeMapId or entry.mapId) == map then
            return true
        end
    end
    return false
end

-- The floors above a point: the height bands of the cells there, bands at most FLOOR_GAP apart joined to one floor,
-- lowest first. Each floor: { zMin, zMax, z (middle), index }.
function logic.floorsAt(N, x, y, swimming)
    local bands = N.HeightBands(x, y, { swimming = swimming })
    local floors = {}
    for _, band in ipairs(bands) do
        local last = floors[#floors]
        if last ~= nil and band.zMin - last.zMax <= logic.FLOOR_GAP then
            last.zMax = max(last.zMax, band.zMax)
        else
            floors[#floors + 1] = { zMin = band.zMin, zMax = band.zMax }
        end
    end
    for i, f in ipairs(floors) do
        f.index = i
        f.z = (f.zMin + f.zMax) / 2
    end
    return floors
end

-- Action edges WowNav may route over: the ones without conditions (the same rule as WowNav's own core).
function logic.actionAllowed(action)
    local conditions = type(action) == "table" and action.conditions or nil
    return type(conditions) == "table" and conditions.status == "unconditional" and conditions.proof ~= nil
end

-- The first transit (action) edge of a route result, or nil.
function logic.firstAction(result)
    for _, edge in ipairs(result.edges or {}) do
        if edge.action ~= nil then
            return edge.action
        end
    end
    return nil
end

-- A route result -> the waypoints for WowVision's Path: { id, x, y, z, radius, gate, area } per steering target
-- (WowNav drops the pass-through branch points), cut at the first transit edge (the route ends where the portal,
-- tram or lift begins; transit = that action). The positions are copied, so the path keeps working when a zone is
-- dropped later.
function logic.buildWaypoints(N, result)
    local ids = N.SteeringTargets(result.path)
    local action = logic.firstAction(result)
    if action ~= nil then
        for i, id in ipairs(ids) do
            if id == action.fromNode then
                for j = #ids, i + 1, -1 do
                    ids[j] = nil
                end
                break
            end
        end
    end
    local waypoints = {}
    for _, id in ipairs(ids) do
        local x, y, z = N.Position(id)
        waypoints[#waypoints + 1] = {
            id = id, x = x, y = y, z = z,
            radius = N.Radius(id), gate = N.GateHalfWidth(id), area = N.Area(id),
        }
    end
    return waypoints, action
end

-- The yards along the waypoints from the player.
function logic.routeLength(waypoints, px, py)
    local sum, x, y = 0, px, py
    for _, wp in ipairs(waypoints) do
        sum = sum + distance(x, y, wp.x, wp.y)
        x, y = wp.x, wp.y
    end
    return sum
end

-- The route's height at the player: linear between the previous and the current waypoint (WowNav G.Height), from
-- the copied positions. nil while swimming (WowNav's rule: a swimmer has no floor).
function logic.heightAlong(previous, current, x, y, swimming)
    if swimming or current == nil or current.z == nil then
        return nil
    end
    if previous == nil or previous.z == nil then
        return current.z
    end
    local before = distance(x, y, previous.x, previous.y)
    local after = distance(x, y, current.x, current.y)
    local total = before + after
    if total <= 0 then
        return current.z
    end
    return previous.z + (current.z - previous.z) * (before / total)
end

-- Whether the player has reached waypoint index of the path (WowNav G.Reached: radius, gate line, turning point in
-- the open). p: x, y, px, py (previous position), z, swimming, finalRadius (the last waypoint at the target).
-- Returns reached, rule.
function logic.reached(N, G, waypoints, index, p)
    local wp = waypoints[index]
    if wp == nil then
        return false
    end
    if wp.final then
        return distance(p.x, p.y, wp.x, wp.y) <= (p.finalRadius or 1.5), "final"
    end
    if wp.id ~= nil and N.Exists(wp.id) then
        local previous = waypoints[index - 1]
        local nextWp = waypoints[index + 1]
        local previousId = previous ~= nil and previous.id ~= nil and N.Exists(previous.id) and previous.id or nil
        local nextId = nextWp ~= nil and not nextWp.final and nextWp.id ~= nil and N.Exists(nextWp.id) and nextWp.id or nil
        return G.Reached({
            x = p.x, y = p.y, px = p.px, py = p.py, z = p.z, swimming = p.swimming,
            waypointId = wp.id, previousId = previousId, nextId = nextId,
        })
    end
    -- the zone of this point was dropped: its copied radius still holds
    return distance(p.x, p.y, wp.x, wp.y) <= (wp.radius or 3), "radius"
end

-- A later stretch of the route the player stands on: within the radius of waypoint k (from the data) of the line
-- from waypoint k - 1 to k, at the same height where the route's height is known (NavNetwork's 3 yd tolerance).
-- The nearest such stretch wins. Returns k or nil.
function logic.laterStretch(waypoints, index, x, y, z)
    local best, bestDistance
    for k = index + 1, #waypoints do
        local a, b = waypoints[k - 1], waypoints[k]
        if not b.final and b.radius ~= nil then
            local dx, dy = b.x - a.x, b.y - a.y
            local l2 = dx * dx + dy * dy
            local t = l2 > 0 and ((x - a.x) * dx + (y - a.y) * dy) / l2 or 1
            t = max(0, min(1, t))
            local qx, qy = a.x + t * dx, a.y + t * dy
            local d = distance(x, y, qx, qy)
            local heightOk = true
            if z ~= nil and a.z ~= nil and b.z ~= nil then
                heightOk = math.abs(a.z + (b.z - a.z) * t - z) <= 3.0
            end
            if d <= b.radius and heightOk and (bestDistance == nil or d < bestDistance) then
                best, bestDistance = k, d
            end
        end
    end
    return best
end

-- Back onto the route: WowNav's rule first (G.Reenter: a later waypoint that is closer than the current one and
-- whose attachment cell holds the player), else a later stretch the player stands on (WowNav's cells mostly attach
-- link points, so its rule alone finds few spots). Returns the new index or nil.
function logic.rejoinIndex(N, G, waypoints, index, x, y, z, swimming)
    local found = logic.reenterIndex(N, G, waypoints, index, x, y, z, swimming)
    if found ~= nil then
        return found
    end
    return logic.laterStretch(waypoints, index, x, y, z)
end

function logic.reenterIndex(N, G, waypoints, index, x, y, z, swimming)
    local ids, map = {}, {}
    for i, wp in ipairs(waypoints) do
        if not wp.final and wp.id ~= nil and N.Exists(wp.id) then
            ids[#ids + 1] = wp.id
            map[#ids] = i
        end
    end
    local current
    for k, i in pairs(map) do
        if i == index then
            current = k
        end
    end
    if current == nil then
        return nil
    end
    local found = G.Reenter(ids, current, x, y, z, { swimming = swimming })
    return found and map[found] or nil
end

-- The approach watch of a path (WowNav CheckApproach / CheckBlockage), fed once per update. state is the path's own
-- table. Returns true when the player is off the route: no approach within the window although travelling, or stuck
-- while trying to walk. now in seconds; moving: the player tries to walk.
function logic.offRoute(state, now, x, y, wpx, wpy, moving)
    local d = distance(x, y, wpx, wpy)
    if state.windowStart == nil then
        state.windowStart, state.windowDistance, state.travelled = now, d, 0
        state.lastX, state.lastY = x, y
        state.stuckSince, state.stuckX, state.stuckY = moving and now or nil, x, y
        return false
    end
    local step = distance(state.lastX, state.lastY, x, y)
    state.lastX, state.lastY = x, y
    if moving then
        state.travelled = state.travelled + step
    end
    if state.windowDistance - d >= logic.APPROACH_GAIN then
        state.windowStart, state.windowDistance, state.travelled = now, d, 0
    elseif now - state.windowStart >= logic.APPROACH_WINDOW and state.travelled >= logic.APPROACH_TRAVEL then
        state.windowStart, state.windowDistance, state.travelled = now, d, 0
        return true
    end
    -- stuck: trying to walk, but within STUCK_MOVE of where the episode began
    if moving then
        if distance(state.stuckX, state.stuckY, x, y) >= logic.STUCK_MOVE then
            state.stuckSince, state.stuckX, state.stuckY, state.stuckDone = now, x, y, nil
        elseif state.stuckSince == nil then
            state.stuckSince = now
        elseif not state.stuckDone and now - state.stuckSince >= logic.STUCK_TIME then
            state.stuckDone = true
            return true
        end
    else
        state.stuckSince, state.stuckX, state.stuckY, state.stuckDone = nil, x, y, nil
    end
    return false
end

-- The zones a route touches (to keep them decoded) plus extra ones.
function logic.routeZones(N, result, extra)
    local keep = {}
    for _, id in ipairs(result.path or {}) do
        if id < N.VIRT_BASE then
            keep[floor(id / N.ZONE_BASE)] = true
        else
            local point = N.virt[id]
            if point and point.zone then
                keep[point.zone.id] = true
            end
        end
    end
    for _, id in ipairs(extra or {}) do
        keep[id] = true
    end
    return keep
end

-- The catalog of a zone as destinations for the F10 list: { id, n, x, y, z }, names in the client's language.
function logic.zoneDestinations(N, zoneId, german)
    local catalog = N.LogicalTargets(zoneId)
    local out = {}
    if type(catalog) ~= "table" or type(catalog.targets) ~= "table" then
        return out
    end
    for _, target in ipairs(catalog.targets) do
        local name = german and target.nameDe or target.nameEn
        if (name == nil or name == "") then
            name = target.nameEn
        end
        if name ~= nil and target.x ~= nil and target.y ~= nil then
            out[#out + 1] = {
                id = "wownav:" .. tostring(target.id), n = name, x = target.x, y = target.y,
                z = target.zStatus == "known" and target.z or nil,
            }
        end
    end
    return out
end
