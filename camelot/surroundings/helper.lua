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
-- the landings between, to the far end, onto its floor. Up or down alike.

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

-- The building helper's list (user 2026-11-24: "take all described exits of a room, reusing the existing ordering
-- logic for Alt-L"): every exit the describe key names where the player stands, in the order it names them, one
-- entry per direction said ("street of Old Town to the northwest and south" is two). Alt-I steps forward through
-- it, Alt-Shift-I back; the module keeps the list while the player stays in the same room or on the same square.
-- `ctx`: { room = id } in a room of the zone (its doorways, logic.roomDoorways as logic.roomText asks), or
-- { region = r } on a square or a hall of the indoor layer (its openings, logic.describeEdgeItems as the describe
-- key's spot text). Each entry: { key, label, class, kind, x, y, mouth or door, fixedDir, via, place, rec,
-- floor }; nothing else is computed here: the route is made when the entry is chosen (logic.choiceRoute).

-- The end record a climb's opening stands at (`px`, `py` one of its points), or nil.
local function endRecordAt(zone, px, py)
    local ix = zone._index
    for _, list in ipairs({ ix.climbFeet or {}, ix.climbTops or {} }) do
        for _, f in ipairs(list) do
            if f.x == px and f.y == py then
                return f
            end
        end
    end
    return nil
end

-- One entry for the opening `m` of the region, seen from (x, y).
local function mouthEntry(zone, region, item, m, x, y)
    local _d, px, py = logic.nearestOfPoints(m.points, x, y)
    local e = { label = item.label, class = item.class, mouth = m, x = px, y = py, floor = zone._index.floor or 0 }
    if m.climb then
        e.kind = "climb"
        e.rec = m.endRecord and endRecordAt(zone, px, py) or nil
        e.value = m.value
    elseif m.class == "entrance" then
        e.kind = "entrance"
    elseif m.class == "room" then
        -- (in the indoor layer: a passage, stairs or the way out, through its doorway)
        e.kind = "doorway"
    else
        -- a street, road, square or hall: to where it begins on the square (the middle of its opening, as the
        -- guidance leads to it: logic.wayBeginnings), else to its opening's nearest point (a street along the side)
        e.kind = "way"
        e.place = m.value and logic.placeOf(m.value) or nil
        for _, b in ipairs(logic.wayBeginnings(zone, region)) do
            if b.mouth == m then
                e.x, e.y, e.through = b.x, b.y, b.onward
                break
            end
        end
    end
    e.key = e.kind .. "|" .. e.label .. "|" .. math.floor(e.x + 0.5) .. "," .. math.floor(e.y + 0.5)
    return e
end

-- For each direction an item is said with, the first of its `parts` (nearest first) said in that direction
-- (`dirOf(part)`); an item said "here" (no direction), its first part.
local function partsByDir(item, parts, dirOf)
    if #item.dirs == 0 then
        return { parts[1] }
    end
    local out, used = {}, {}
    for _, dir in ipairs(item.dirs) do
        for i, p in ipairs(parts) do
            local pd = dirOf(p)
            if not used[i] and pd ~= nil and logic.sameDir(pd, dir) then
                used[i] = true
                out[#out + 1] = p
                break
            end
        end
    end
    return out
end

function logic.helperChoices(zone, x, y, ctx)
    local out = {}
    if ctx.room then
        local items = logic.roomDoorways(zone, ctx.room, { dirs = logic.ITEM_DIRS, x = x, y = y })
        for _, item in ipairs(items) do
            for _, d in ipairs(partsByDir(item, item.doors or {}, function(p)
                return p.dir
            end)) do
                local dx, dy = logic.doorWorld(zone, d.door)
                if dx then
                    local e = { label = item.label, class = item.class, kind = "doorway", x = dx, y = dy,
                        door = d.door, via = d.via, room = ctx.room }
                    -- a small room says its doorways with the fixed way through them (doorwayDirection), a big one
                    -- from the player (roomDoorways)
                    if not logic.isBigRoom(zone, ctx.room) then
                        e.fixedDir = d.dir
                    end
                    if d.via then
                        e.viaX, e.viaY = logic.doorWorld(zone, d.via)
                    end
                    e.key = "doorway|" .. e.label .. "|" .. math.floor(dx + 0.5) .. "," .. math.floor(dy + 0.5)
                    out[#out + 1] = e
                end
            end
        end
    elseif ctx.region then
        for _, item in ipairs(logic.describeEdgeItems(zone, x, y, ctx.region)) do
            for _, m in ipairs(partsByDir(item, item.mouths or {}, function(p)
                return select(2, logic.mouthDistance(p, x, y))
            end)) do
                if m.points and #m.points >= 2 then
                    out[#out + 1] = mouthEntry(zone, ctx.region, item, m, x, y)
                end
            end
        end
    end
    return out
end

-- The route to a chosen entry: { points, kind, ... } as logic.helperRoute. A doorway into a piece of the same room
-- (roomDoorways' `via`) is led on through that piece's own doorway; a climb's opening through the whole climb.
function logic.choiceRoute(zone, e)
    if e.kind == "climb" then
        -- (the end record itself where the opening stands at one; never changed here, it is the zone's)
        local t = e.rec or { x = e.x, y = e.y, floor = e.floor, value = e.value }
        if zone._index.climbTops then
            return logic.endRoute(zone, t)
        end
        return logic.helperRoute(zone, { kind = "climb", x = t.x, y = t.y, floor = t.floor or 0, value = t.value,
            bearing = t.bearing })
    end
    local points = { { x = e.x, y = e.y } }
    if e.viaX then
        points[2] = { x = e.viaX, y = e.viaY }
    end
    return { points = points, kind = e.kind, place = e.place, via = e.via ~= nil, zone = zone, room = e.room }
end

-- What the describe key says for the entry, from (x, y) now: its name with the one direction it lies in
-- ("stairs to the east"; "way outside to the north"), logic.itemsText's words.
function logic.choiceText(zone, e, x, y)
    local dir = e.fixedDir
    if dir == nil then
        local d
        if e.mouth then
            d, dir = logic.mouthDistance(e.mouth, x, y)
        else
            d, dir = logic.dist(e.x, e.y, x, y), logic.bearingOf(e.x - x, e.y - y)
        end
        if d < logic.HERE then
            dir = nil
        end
    end
    local floor = e.mouth and logic.floorOfValue(zone, logic.valueAt(zone, x, y)) or nil
    return logic.itemsText(zone, { { label = e.label, class = e.class, dirs = { dir } } }, floor)
end

-- The next entry from `index` (0: none chosen yet) in a list of `n`, a step forward or back, wrapping.
function logic.cycleIndex(index, n, back)
    if n == 0 then
        return nil
    end
    if index < 1 or index > n then
        return back and n or 1
    end
    if back then
        return (index - 2) % n + 1
    end
    return index % n + 1
end

-- Has the player arrived where the route `route` leads, by the surroundings' own rules? Asked when the module says
-- (or logs) a place or room line, the moment it holds the player on a new place. `start` and `now`: { floor (the
-- floor piece in the route's grid), liquid (that piece is a liquid's), room, inside }. Out of the water: off the
-- piece swum in, on floor; through a doorway or an entrance: another room, or in or out of the building; up or down
-- a climb with a landing: on the landing's piece; to a street, square or hall of the list (route.place): on that
-- place. A doorway into a piece of the same room (route.via) counts only beyond that piece. A route of none of these
-- (a way's beginning from the guidance, a climb whose line ends short) ends at its last point. `now.place`: the place
-- under the player. Returns true, false, or nil (no rule: the last point decides).
function logic.helperArrived(route, start, now)
    local kind = route and route.kind
    if kind == "exit" then
        return now.floor ~= start.floor and not now.liquid
    end
    if kind == "doorway" and route.via and now.inside == start.inside and now.room ~= nil and route.room ~= nil
        and logic.sameRoomName(route.zone, route.room, now.room) then
        return false
    end
    if kind == "doorway" or kind == "entrance" then
        return now.room ~= start.room or now.inside ~= start.inside
    end
    if kind == "way" and route.place ~= nil then
        return now.place == route.place
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
