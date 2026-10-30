-- The building helper (Alt plus the turn key): a beacon route from where the player stands through the next
-- exit the surroundings point at. A doorway, an entrance or a way out of the water: to it. The foot of a ramp or
-- stairs, or a climb the player stands on: along the climb's own centre line to its other end and to the join of
-- the floor there (the next landing: the griffon ramp's platform, a tower's upper floor). Pure: the module turns the
-- points into a path.
-- The route has no points of its own beyond these (user 2026-10-17: "i don't want extra artificial points"). It
-- ends where the surroundings' own rules say the player is there, on the line they say for it (helperArrived): out
-- of the water on the place beyond, in the room beyond the doorway, on the landing's floor.
--
-- It reads what the export stored (the climbs' line stretches with their floor piece, the joins between pieces,
-- the feet with their bearing up); it computes nothing the export could store, it only follows the stored lines.
-- Where a climb's line ends before any landing (the line ends short in the data), the route ends at the line's end
-- and says so (`short`).

local logic = WowVision.surroundingsLogic

logic.HELPER_FOOT = 6      -- yd: a climb's line end at most this far from its foot belongs to it
logic.HELPER_NEAR = 4      -- yd: a climb line beginning this near the player is the one to lead up
logic.HELPER_LANDING = 6   -- yd: a join at most this far from the line's end is where the climb lands
logic.HELPER_RADIUS = 1.5  -- yd: a point of the route counts as reached within this
logic.HELPER_SIDE = 3      -- yd: passing a point's line (across the way in) counts within this beside it

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- The stretches of a climb piece's line near (x, y) (the lane buckets of the cells within 80 yd), each once.
local function climbLanes(zone, piece, x, y)
    return logic.lanesNear(zone, x, y, 80, function(lane)
        return lane.piece == piece
    end)
end

-- The climb piece whose line has a free end nearest (x, y) within `reach` (on the floor `fromFloor`'s side),
-- with that end. nil when no climb line ends there. A climb that goes UP from here (the free end is its foot:
-- the line runs from it the way the climb rises, riseOf) comes before one that goes down, whatever is nearer:
-- on Northshire Abbey's gallery the main ramp's top lay 2 yd off and the bell tower ramp's foot 3 yd, and Alt-I
-- always led down to the hall (user 2026-10-18).
-- `floor` (optional): only climbs joined to that floor piece; `upOnly`: only ends that are feet (or unknown).
function logic.climbAtFoot(zone, x, y, reach, floor, upOnly)
    local ix = zone._index
    if ix.lineFloors == nil then
        return nil
    end
    local joined = floor ~= nil and ix.joined[floor] or nil
    local best, bx, by, bd, bRank
    for _, lane in ipairs(logic.lanesNear(zone, x, y, reach + logic.LANE_REACH, function(lane)
        return ix.lineFloors[lane.piece] and (floor == nil or lane.piece ~= floor and joined and joined[lane.piece])
    end)) do
        for _, e in ipairs({ { lane.free1, lane.x1, lane.y1, lane.x2, lane.y2 }, { lane.free2, lane.x2, lane.y2, lane.x1, lane.y1 } }) do
            if e[1] then
                local d = dist(x, y, e[2], e[3])
                -- 0 up from here, 1 down, 0.5 unknown (no rise in the value)
                local rank = 0.5
                local up = logic.riseOf(zone, lane.value)
                if up ~= nil and (e[4] ~= e[2] or e[5] ~= e[3]) then
                    local away = logic.bearingOf(e[4] - e[2], e[5] - e[3])
                    local off = math.abs((away - up + 180) % 360 - 180)
                    rank = off < 90 and 0 or 1
                end
                if d <= reach and not (upOnly and rank == 1) and (bd == nil or rank < bRank or (rank == bRank and d < bd)) then
                    best, bx, by, bd, bRank = lane.piece, e[2], e[3], d, rank
                end
            end
        end
    end
    return best, bx, by
end

-- The climb's line from the point (sx, sy) on it: the stretches followed end to end (at a fork the one that turns
-- least). Returns the points, the first one (sx, sy).
local function followLine(lanes, sx, sy, skip)
    local points, used = { { x = sx, y = sy } }, {}
    if skip then
        used[skip] = true
    end
    local px, py = sx, sy
    local ax, ay = nil, nil   -- the direction walked so far
    while true do
        local best, bx, by, bestTurn
        for _, lane in ipairs(lanes) do
            if not used[lane] then
                local nx, ny
                if lane.x1 == px and lane.y1 == py then
                    nx, ny = lane.x2, lane.y2
                elseif lane.x2 == px and lane.y2 == py then
                    nx, ny = lane.x1, lane.y1
                end
                if nx then
                    local turn = 0
                    if ax then
                        local l = dist(px, py, nx, ny)
                        turn = l > 0 and -((nx - px) * ax + (ny - py) * ay) / l or 0
                    end
                    if best == nil or turn < bestTurn then
                        best, bx, by, bestTurn = lane, nx, ny, turn
                    end
                end
            end
        end
        if best == nil then
            break
        end
        used[best] = true
        local l = dist(px, py, bx, by)
        if l > 0 then
            ax, ay = (bx - px) / l, (by - py) / l
        end
        px, py = bx, by
        points[#points + 1] = { x = px, y = py }
    end
    return points
end

-- Where the climb `piece` lands at its line's end (ex, ey): the nearest join of the piece within HELPER_LANDING of
-- it. A join onto the floor the climb starts from (`footFloor`, the foot at footX, footY; a line of `length` yd)
-- counts only within HELPER_SAME_FLOOR of the end and in the climb's upper part: the ground joins the griffon ramp
-- all along its side, and that is no landing. Returns piece, x, y or nil.
logic.HELPER_SAME_FLOOR = 3
local function landingAt(zone, piece, ex, ey, footFloor, footX, footY, length)
    local best, bx, by, bd
    for other, list in pairs(zone._index.joinPoints[piece] or {}) do
        for i = 1, #list, 2 do
            local jx, jy = list[i], list[i + 1]
            local d = dist(jx, jy, ex, ey)
            local ok = d <= logic.HELPER_LANDING
            if ok and other == footFloor and footX ~= nil then
                ok = d <= logic.HELPER_SAME_FLOOR and dist(jx, jy, footX, footY) >= 0.6 * (length or 0)
            end
            if ok and (bd == nil or d < bd) then
                best, bx, by, bd = other, jx, jy, d
            end
        end
    end
    return best, bx, by
end

local function lineLength(points)
    local sum = 0
    for k = 2, #points do
        sum = sum + dist(points[k - 1].x, points[k - 1].y, points[k].x, points[k].y)
    end
    return sum
end

-- Ends a climb route on its landing: the join point (from there the floor tracking puts the player on it).
local function onto(points, jx, jy)
    local last = points[#points]
    if dist(last.x, last.y, jx, jy) > 0.5 then
        points[#points + 1] = { x = jx, y = jy }
    end
end

-- A climb route from its foot (fx, fy) on the floor `footFloor`: { points, piece, landing, short }, or nil.
function logic.climbRoute(zone, fx, fy, footFloor)
    -- a climb joined to the foot's floor that goes up from it (two feet share the Abbey gallery's west end: the bell
    -- tower ramp's on the gallery and, 16 yd below, the main ramp's on the hall floor)
    local piece, ex, ey = logic.climbAtFoot(zone, fx, fy, logic.HELPER_FOOT, footFloor, true)
    if piece == nil and footFloor ~= nil then
        piece, ex, ey = logic.climbAtFoot(zone, fx, fy, logic.HELPER_FOOT)
    end
    if piece == nil then
        return nil
    end
    local points = followLine(climbLanes(zone, piece, ex, ey), ex, ey)
    if dist(fx, fy, ex, ey) > 0.5 then
        table.insert(points, 1, { x = fx, y = fy })
    end
    local top = points[#points]
    local landing, jx, jy = landingAt(zone, piece, top.x, top.y, footFloor or 0, fx, fy, lineLength(points))
    if landing then
        onto(points, jx, jy)
    end
    return { points = points, piece = piece, landing = landing, short = landing == nil }
end

-- Climb ends (data since trial L4e: zone.climbTops beside the feet; user 2026-10-20: Alt-I and the turn key fully on
-- the new system). A staircase is led through from one end record to the other: along each flight's line, across
-- the landings between, to the far end, onto its floor. Up or down alike; the end of a climb just crossed is skipped
-- (logic.noteClimbStep), as the guidance skips it.

-- The end records (feet and tops) on the floor piece `floor` within `reach` of (x, y), nearest first: { rec, d }.
function logic.climbEndsNear(zone, x, y, floor, reach)
    local ix = zone._index
    local crossed = ix.crossed
    local out = {}
    for _, list in ipairs({ ix.climbFeet or {}, ix.climbTops or {} }) do
        for _, f in ipairs(list) do
            if (f.floor or 0) == (floor or 0) and not (crossed and logic.placeOf(f.value) == crossed.place) then
                local d = dist(x, y, f.x, f.y)
                if d <= reach then
                    out[#out + 1] = { rec = f, d = d }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return a.d < b.d
    end)
    return out
end

-- The free end of a climb line within HELPER_FOOT of the end record `rec`, on a piece joined to its floor: of its own
-- place first, then the nearest. Piece, x, y, or nil.
local function lineEndAt(zone, rec)
    local ix = zone._index
    if ix.lineFloors == nil then
        return nil
    end
    local joined = ix.joined[rec.floor or 0] or {}
    local place = logic.placeOf(rec.value)
    local best, bx, by, bd, bOwn
    for _, lane in ipairs(logic.lanesNear(zone, rec.x, rec.y, logic.HELPER_FOOT + logic.LANE_REACH, function(lane)
        return ix.lineFloors[lane.piece] and joined[lane.piece]
    end)) do
        local own = logic.placeOf(lane.value) == place
        for _, e in ipairs({ { lane.free1, lane.x1, lane.y1 }, { lane.free2, lane.x2, lane.y2 } }) do
            local d = e[1] and dist(rec.x, rec.y, e[2], e[3])
            if d and d <= logic.HELPER_FOOT
                and (bd == nil or (own and not bOwn) or (own == bOwn and d < bd)) then
                best, bx, by, bd, bOwn = lane.piece, e[2], e[3], d, own
            end
        end
    end
    return best, bx, by
end

-- The far end record of a staircase where its line ends at (ex, ey): within HELPER_LANDING, on a floor joined to the
-- piece `piece`, not where the route began (`from`, a point).
local function endAt(zone, piece, ex, ey, from)
    local ix = zone._index
    local joined = ix.joined[piece] or {}
    local best, bd
    for _, list in ipairs({ ix.climbFeet or {}, ix.climbTops or {} }) do
        for _, f in ipairs(list) do
            if joined[f.floor or 0] and not (from and dist(f.x, f.y, from.x, from.y) < 0.5) then
                local d = dist(ex, ey, f.x, f.y)
                if d <= logic.HELPER_LANDING and (bd == nil or d < bd) then
                    best, bd = f, d
                end
            end
        end
    end
    return best
end

-- The next flight from a line's end (ex, ey): a climb piece with a line, not `used`, joined to `piece` (a landing
-- between flights is such a piece, with its short line), whose line has a free end within HELPER_NEXT (a landing's own
-- line is a stub, its flights' lines begin across it). Piece, x, y.
logic.HELPER_NEXT = 10
local function nextFlight(zone, piece, ex, ey, used)
    local ix = zone._index
    local joined = ix.joined[piece] or {}
    local best, bx, by, bd
    for _, lane in ipairs(logic.lanesNear(zone, ex, ey, logic.HELPER_NEXT + logic.LANE_REACH, function(lane)
        return ix.lineFloors[lane.piece] and not used[lane.piece] and joined[lane.piece]
    end)) do
        for _, e in ipairs({ { lane.free1, lane.x1, lane.y1 }, { lane.free2, lane.x2, lane.y2 } }) do
            local d = e[1] and dist(ex, ey, e[2], e[3])
            if d and d <= logic.HELPER_NEXT and (bd == nil or d < bd) then
                best, bx, by, bd = lane.piece, e[2], e[3], d
            end
        end
    end
    return best, bx, by
end

-- On from the last of `points` on the climb `piece` through its staircase (`used`: the pieces walked): at a far end
-- record there, to it (no point beyond: being on its floor is the module's floor rule, helperArrived); else into the
-- next flight along its line, and so on; with no end record found, onto the piece joined at the last line's end as
-- before (landingAt). The route { points, piece, landing, short, last end }.
local function throughStaircase(zone, points, piece, used, from)
    for _ = 1, 12 do
        local last = points[#points]
        local e = endAt(zone, piece, last.x, last.y, from)
        if e then
            if dist(last.x, last.y, e.x, e.y) > 0.5 then
                points[#points + 1] = { x = e.x, y = e.y }
            end
            return { points = points, piece = piece, landing = e.floor or 0, short = false, ending = e }
        end
        local q, qx, qy = nextFlight(zone, piece, last.x, last.y, used)
        if q == nil then
            break
        end
        used[q] = true
        for _, p in ipairs(followLine(climbLanes(zone, q, qx, qy), qx, qy)) do
            points[#points + 1] = p
        end
        piece = q
    end
    local last = points[#points]
    local landing, jx, jy = landingAt(zone, piece, last.x, last.y, nil, nil, nil, nil)
    if landing then
        onto(points, jx, jy)
    end
    return { points = points, piece = piece, landing = landing, short = landing == nil }
end

-- The route through a staircase from its end record `rec` (a foot or a top, or a guidance target made from one): from
-- it along the climb's line there, through the staircase to its far end and onto that floor. Without a line there: to
-- the end and on along its way on (short).
function logic.endRoute(zone, rec)
    local piece, ex, ey = lineEndAt(zone, rec)
    if piece == nil then
        return { points = logic.throughRoute({ x = rec.x, y = rec.y, bearing = rec.bearing, through = rec.bearing }),
            kind = "climb", short = true }
    end
    local points = followLine(climbLanes(zone, piece, ex, ey), ex, ey)
    if dist(rec.x, rec.y, ex, ey) > 0.5 then
        table.insert(points, 1, { x = rec.x, y = rec.y })
    end
    local route = throughStaircase(zone, points, piece, { [piece] = true }, rec)
    route.kind = "climb"
    return route
end

-- A climb whose line begins within `reach` of the player at (x, y) on a piece joined to the player's floor `floor`
-- (a foot the data has no foot record for: many a spiral's): the climb route from that line's end, or nil.
function logic.climbNear(zone, x, y, floor, reach)
    -- a climb that goes up from this floor (the Abbey gallery: the main ramp's top lay nearest and Alt-I led down)
    local piece, ex, ey = logic.climbAtFoot(zone, x, y, reach, floor or 0, true)
    if piece == nil then
        return nil
    end
    return logic.climbRoute(zone, ex, ey, floor or 0)
end

logic.HELPER_FLOOR_REACH = 40   -- yd: a climb's foot on the player's own floor piece that Alt-I leads to along its line

-- The way along a piece's own line (a landing's or platform's, path-line data) from where the player stands to
-- near the point (fx, fy): the stretch nearest the player, then its chain followed the way that comes within
-- HELPER_FOOT of the point, cut there. Points, or nil (no line of the piece within reach, or none reaching the point).
function logic.lineRouteTo(zone, piece, x, y, fx, fy)
    local lanes = climbLanes(zone, piece, x, y)
    local best, bx, by, bd
    for _, lane in ipairs(lanes) do
        if lane.x1 ~= lane.x2 or lane.y1 ~= lane.y2 then
            local px, py, d = logic.segmentPoint(x, y, lane.x1, lane.y1, lane.x2, lane.y2)
            if d <= logic.LANE_REACH and (bd == nil or d < bd) then
                best, bx, by, bd = lane, px, py, d
            end
        end
    end
    if best == nil then
        return nil
    end
    local choice
    for _, e in ipairs({ { best.x2, best.y2 }, { best.x1, best.y1 } }) do
        local chain = followLine(lanes, e[1], e[2], best)
        local k, kd
        for i, p in ipairs(chain) do
            local d = dist(p.x, p.y, fx, fy)
            if kd == nil or d < kd then
                k, kd = i, d
            end
        end
        if kd ~= nil and kd <= logic.HELPER_FOOT and (choice == nil or kd < choice.kd) then
            choice = { chain = chain, k = k, kd = kd }
        end
    end
    if choice == nil then
        return nil
    end
    local points = { { x = bx, y = by } }
    for i = 1, choice.k do
        -- the stretch's end is left out where the chain turns back past the player's point at once (two paths'
        -- stretches overlap on a platform ring: no 3 yd east to come back west)
        local p, nxt = choice.chain[i], choice.chain[i + 1]
        if not (i == 1 and nxt and i < choice.k and dist(bx, by, nxt.x, nxt.y) < dist(p.x, p.y, nxt.x, nxt.y)) then
            points[#points + 1] = p
        end
    end
    return points
end

-- A route up from the player's own floor piece when no climb begins within HELPER_NEAR: to the nearest foot on
-- this piece within HELPER_FLOOR_REACH along the piece's own line (the safe way round: Northshire Abbey's gallery
-- to the bell tower ramp's foot at its west end, not along the 2 yd strip over the hall, user 2026-10-18), then up
-- the climb as climbRoute. { points, piece, landing, short, name }, or nil.
function logic.floorClimbRoute(zone, floor, x, y)
    local ix = zone._index
    if floor == nil or floor == 0 then
        return nil
    end
    -- with end records: the nearest end on this floor of either kind (a top leads down as a foot leads up), along
    -- the floor's own line to it
    if ix.climbTops then
        for _, near in ipairs(logic.climbEndsNear(zone, x, y, floor, logic.HELPER_FLOOR_REACH)) do
            local climb = logic.endRoute(zone, near.rec)
            if climb and not climb.short then
                local lead = logic.lineRouteTo(zone, floor, x, y, near.rec.x, near.rec.y)
                if lead then
                    local points = {}
                    for _, p in ipairs(lead) do
                        points[#points + 1] = p
                    end
                    for _, p in ipairs(climb.points) do
                        points[#points + 1] = p
                    end
                    climb.points = points
                end
                climb.foot = near.rec
                return climb
            end
        end
        return nil
    end
    -- (only a foot a climb goes UP from, as climbNear: a foot stored at a climb's top, the Abbey main ramp's on the
    -- gallery in trial K9, led Alt-I down the ramp, walk 2026-10-19 22:15)
    local best, bd
    for _, f in ipairs(ix.climbFeet or {}) do
        if (f.floor or 0) == floor then
            local d = dist(x, y, f.x, f.y)
            if d <= logic.HELPER_FLOOR_REACH and (bd == nil or d < bd)
                and logic.climbAtFoot(zone, f.x, f.y, logic.HELPER_FOOT, floor, true) ~= nil then
                best, bd = f, d
            end
        end
    end
    if best == nil then
        return nil
    end
    local climb = logic.climbRoute(zone, best.x, best.y, floor)
    if climb == nil then
        return nil
    end
    local lead = logic.lineRouteTo(zone, floor, x, y, best.x, best.y)
    if lead then
        local points = {}
        for _, p in ipairs(lead) do
            points[#points + 1] = p
        end
        for _, p in ipairs(climb.points) do
            points[#points + 1] = p
        end
        climb.points = points
    end
    climb.kind = "climb"
    climb.foot = best
    return climb
end

-- A climb route for a player standing on the climb `piece` at (x, y), facing `facing` (radians as GetPlayerFacing,
-- or nil): along its line toward the end the player faces (from the nearest point of the line on), onto the floor
-- joined there. Returns as climbRoute, or nil when the piece has no line here.
function logic.climbRouteFrom(zone, piece, x, y, facing)
    local lanes = climbLanes(zone, piece, x, y)
    -- the free ends of the line: start from one, the whole line in order
    local sx, sy
    for _, lane in ipairs(lanes) do
        if lane.free1 then
            sx, sy = lane.x1, lane.y1
            break
        elseif lane.free2 then
            sx, sy = lane.x2, lane.y2
            break
        end
    end
    if sx == nil then
        return nil
    end
    local line = followLine(lanes, sx, sy)
    -- the nearest point on the line and the stretch it lies on
    local bestK, bestT, bestD = 1, 0, nil
    for k = 1, #line - 1 do
        local a, b = line[k], line[k + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / l2)) or 0
        local d = dist(x, y, a.x + t * dx, a.y + t * dy)
        if bestD == nil or d < bestD then
            bestK, bestT, bestD = k, t, d
        end
    end
    -- toward the end the player faces along that stretch (no facing: away from the first end)
    local forward = true
    if facing ~= nil and #line > 1 then
        local a, b = line[bestK], line[math.min(bestK + 1, #line)]
        forward = (b.x - a.x) * math.cos(facing) + (b.y - a.y) * math.sin(facing) >= 0
    end
    local points = {}
    if forward then
        for k = bestK + 1, #line do
            points[#points + 1] = line[k]
        end
    else
        for k = bestK, 1, -1 do
            points[#points + 1] = line[k]
        end
    end
    if #points == 0 then
        return nil
    end
    -- the player's point on the line, where the route sets out from, and the way its stretch runs toward the end
    -- faced (the turn key's climbLineFacing)
    local a, b = line[bestK], line[math.min(bestK + 1, #line)]
    local from = { x = a.x + bestT * (b.x - a.x), y = a.y + bestT * (b.y - a.y) }
    local along = forward and math.atan2(b.y - a.y, b.x - a.x) or math.atan2(a.y - b.y, a.x - b.x)
    local first = forward and line[1] or line[#line]
    -- with end records: on through the staircase to the end faced, onto its floor
    if zone._index.climbTops then
        local route = throughStaircase(zone, points, piece, { [piece] = true }, nil)
        route.from, route.along = from, along
        return route
    end
    local top = points[#points]
    local landing, jx, jy = landingAt(zone, piece, top.x, top.y, nil, first.x, first.y, lineLength(line))
    if landing then
        onto(points, jx, jy)
    end
    return { points = points, piece = piece, landing = landing, short = landing == nil, from = from, along = along }
end

-- yd along a climb route from the player's point on the line to its last point
local function routeLength(route)
    local px, py, n = route.from.x, route.from.y, 0
    for _, p in ipairs(route.points) do
        n = n + dist(px, py, p.x, p.y)
        px, py = p.x, p.y
    end
    return n
end

-- The turn key on a climb with a line of its own (STATE bug 116, user 2026-10-27: "make it follow the Alt-I line"):
-- toward the first point of the route Alt-I leads by from here (climbRouteFrom: the whole line toward the end the
-- player faces, past its stretches' ends, through the staircase onto the floor there) that lies LANE_AHEAD yd or
-- more on along it from the player's point on the line, else its last. The line's own rule aimed LANE_AHEAD on along
-- the stretch under the player only, held at the stretch's end: on Ironforge's wide ramp in the Hall of Mysteries,
-- 4 yd beside the line, it turned the player 27 to 83 degrees across the ramp (walk 2026-10-26); the zeppelin tower's
-- walks went by Alt-I's route.
-- Bug 123 (walk 2026-10-27, measured on every logged press by a straight walk on the world's surfaces, the user
-- picked both): facing square across the climb (CLIMB_SQUARE or more off its line both ways) with under CLIMB_AT_END yd
-- of route left the way faced, the route the other way, away from that end (at the ramp's foot it took the
-- way down and off); and beside the line the aim lies twice as far on as the player stands from the line, at least
-- LANE_AHEAD (4.7 yd off, the point 3.8 yd on led over the ramp's side). Returns the facing (radians, as
-- GetPlayerFacing), or nil: no climb line here, or its point within HELPER_RADIUS of the player (the line's rule then).
logic.CLIMB_SQUARE = 60   -- degrees
logic.CLIMB_AT_END = 3.0  -- yd

function logic.climbLineFacing(zone, piece, x, y, facing)
    local ix = zone._index
    if piece == nil or piece == 0 or ix.lineFloors == nil or not ix.lineFloors[piece] then
        return nil
    end
    local route = logic.climbRouteFrom(zone, piece, x, y, facing)
    if route == nil or route.from == nil then
        return nil
    end
    if facing ~= nil and math.abs(math.abs(logic.degreesBetween(route.along, facing)) - 90) < 90 - logic.CLIMB_SQUARE
            and routeLength(route) < logic.CLIMB_AT_END then
        local other = logic.climbRouteFrom(zone, piece, x, y, route.along + math.pi)
        if other and other.from and routeLength(other) > routeLength(route) then
            route = other
        end
    end
    local ahead = math.max(logic.LANE_AHEAD, 2 * dist(x, y, route.from.x, route.from.y))
    local px, py, along, aim = route.from.x, route.from.y, 0, nil
    for _, p in ipairs(route.points) do
        along = along + dist(px, py, p.x, p.y)
        px, py, aim = p.x, p.y, p
        if along >= ahead then
            break
        end
    end
    if aim == nil or dist(x, y, aim.x, aim.y) <= logic.HELPER_RADIUS then
        return nil
    end
    return math.rad(-logic.bearingOf(aim.x - x, aim.y - y))
end

-- The point of a doorway, an entrance or a way out (the rest is the surroundings' rules: helperArrived).
function logic.throughRoute(t)
    return { { x = t.x, y = t.y } }
end

-- The helper's route for a guidance target `t` (the surroundings' target, texts.lua): { points, kind, short,
-- landing, piece }, or nil (a target nothing leads through: an aim on a flight, a way's beginning alone).
function logic.helperRoute(zone, t)
    if t == nil then
        return nil
    end
    if t.kind == "climb" and zone._index.climbTops then
        return logic.endRoute(zone, t)
    end
    if t.kind == "climb" then
        local route = logic.climbRoute(zone, t.x, t.y, t.floor)
        if route then
            route.kind = "climb"
            return route
        end
        -- no line at this foot: to the foot and on up the way its bearing says
        return { points = logic.throughRoute(t), kind = "climb", short = true }
    end
    if t.kind == "doorway" or t.kind == "entrance" or t.kind == "exit" then
        return { points = logic.throughRoute(t), kind = t.kind }
    end
    if t.kind == "way" then
        return { points = { { x = t.x, y = t.y } }, kind = "way" }
    end
    return nil
end

-- Has the player arrived where the route `route` leads, by the surroundings' own rules? Asked when the module says
-- (or logs) a place or room line, the moment it holds the player on a new place. `start` and `now`: { floor (the
-- floor piece in the route's grid), liquid (that piece is a liquid's), room, inside }. Out of the water: off the
-- piece swum in, on floor; through a doorway or an entrance: another room, or in or out of the building; up or down
-- a climb with a landing: on the landing's piece. A route of none of these (a way's beginning, a climb whose line
-- ends short) ends at its last point. Returns true, false, or nil (no rule: the last point decides).
function logic.helperArrived(route, start, now)
    local kind = route and route.kind
    if kind == "exit" then
        return now.floor ~= start.floor and not now.liquid
    end
    if kind == "doorway" or kind == "entrance" then
        return now.room ~= start.room or now.inside ~= start.inside
    end
    if kind == "climb" and route.landing ~= nil then
        return now.floor == route.landing and now.floor ~= start.floor
    end
    return nil
end

-- Passing a route point: within HELPER_RADIUS of it, or the move from (px, py) to (x, y) crossed the line across the
-- way in (from the previous point `a` to this one `w`) through it, within HELPER_SIDE beside it. The second keeps a
-- tight spiral's points from being missed.
function logic.helperPassed(px, py, x, y, a, w)
    if dist(x, y, w.x, w.y) <= logic.HELPER_RADIUS then
        return true
    end
    if a == nil or px == nil then
        return false
    end
    local l = dist(a.x, a.y, w.x, w.y)
    if l < 1e-6 then
        return false
    end
    local ux, uy = (w.x - a.x) / l, (w.y - a.y) / l
    local before = (px - w.x) * ux + (py - w.y) * uy
    local after = (x - w.x) * ux + (y - w.y) * uy
    if not (before < 0 and after >= 0) then
        return false
    end
    local t = before / (before - after)
    local sx, sy = px + (x - px) * t, py + (y - py) * t
    return math.abs((sx - w.x) * -uy + (sy - w.y) * ux) <= logic.HELPER_SIDE
end
