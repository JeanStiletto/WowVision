-- The building helper (Alt plus the turn key): a beacon route from where the player stands through the next
-- exit the surroundings point at. A doorway, an entrance or a way out of the water: to it, then through it
-- (HELPER_THROUGH yd beyond, as the places list leads into a shop). The foot of a ramp or stairs, or a climb
-- the player stands on: along the climb's own centre line to its other end and onto the floor joined there (the
-- next landing: the griffon ramp's platform, a tower's upper floor). Pure: the module turns the points into a path.
--
-- It reads what the export stored (the climbs' line stretches with their floor piece, the joins between pieces,
-- the feet with their bearing up); it computes nothing the export could store, it only follows the stored lines.
-- Where a climb's line ends before any landing (the line ends short in the data), the route ends at the line's end
-- and says so (`short`).

local logic = WowVision.surroundingsLogic

logic.HELPER_THROUGH = 3   -- yd beyond a doorway, an entrance, a way out
logic.HELPER_FOOT = 6      -- yd: a climb's line end at most this far from its foot belongs to it
logic.HELPER_NEAR = 4      -- yd: a climb line beginning this near the player is the one to lead up
logic.HELPER_LANDING = 6   -- yd: a join at most this far from the line's end is where the climb lands
logic.HELPER_ONTO = 2      -- yd onto the landing past its join
logic.HELPER_RADIUS = 1.5  -- yd: a point of the route counts as reached within this
logic.HELPER_SIDE = 3      -- yd: passing a point's line (across the way in) counts within this beside it

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- The stretches of a climb piece's line near (x, y) (the lane buckets of the cells around), each once.
local function climbLanes(zone, piece, x, y)
    local ix = zone._index
    local out, seen = {}, {}
    local r0, c0 = logic.cellOf(zone, x, y)
    local reach = math.ceil(80 / zone.cell)
    for r = r0 - reach, r0 + reach do
        for c = c0 - reach, c0 + reach do
            for _, lane in ipairs(ix.lanes[r * zone.cols + c] or {}) do
                if lane.piece == piece and not seen[lane] then
                    seen[lane] = true
                    out[#out + 1] = lane
                end
            end
        end
    end
    return out
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
    local r0, c0 = logic.cellOf(zone, x, y)
    local best, bx, by, bd, bRank
    local span = math.ceil((reach + logic.LANE_REACH) / zone.cell)
    for r = r0 - span, r0 + span do
        for c = c0 - span, c0 + span do
            for _, lane in ipairs(ix.lanes[r * zone.cols + c] or {}) do
                if ix.lineFloors[lane.piece] and (floor == nil or lane.piece ~= floor and joined and joined[lane.piece]) then
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

-- Ends a climb route on its landing: the join point, then HELPER_ONTO yd on in the way the route last went.
local function onto(points, jx, jy)
    local last = points[#points]
    if dist(last.x, last.y, jx, jy) > 0.5 then
        points[#points + 1] = { x = jx, y = jy }
        last = points[#points - 1]
    else
        last = points[#points - 1] or last
    end
    local tip = points[#points]
    local l = dist(last.x, last.y, tip.x, tip.y)
    if l > 0 then
        points[#points + 1] = {
            x = tip.x + (tip.x - last.x) / l * logic.HELPER_ONTO,
            y = tip.y + (tip.y - last.y) / l * logic.HELPER_ONTO,
        }
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
    local best, bd
    for _, f in ipairs(ix.climbFeet or {}) do
        if (f.floor or 0) == floor then
            local d = dist(x, y, f.x, f.y)
            if d <= logic.HELPER_FLOOR_REACH and (bd == nil or d < bd) then
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
    local first = forward and line[1] or line[#line]
    local top = points[#points]
    local landing, jx, jy = landingAt(zone, piece, top.x, top.y, nil, first.x, first.y, lineLength(line))
    if landing then
        onto(points, jx, jy)
    end
    return { points = points, piece = piece, landing = landing, short = landing == nil }
end

-- The points through a doorway, an entrance or a way out: it, then HELPER_THROUGH yd on along the way through.
function logic.throughRoute(t)
    local points = { { x = t.x, y = t.y } }
    if t.through then
        local fx, fy = logic.compassVector(t.bearing or t.through)
        points[2] = { x = t.x + fx * logic.HELPER_THROUGH, y = t.y + fy * logic.HELPER_THROUGH }
    end
    return points
end

-- The helper's route for a guidance target `t` (the surroundings' target, texts.lua): { points, kind, short,
-- landing, piece }, or nil (a target nothing leads through: an aim on a flight, a way's beginning alone).
function logic.helperRoute(zone, t)
    if t == nil then
        return nil
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
