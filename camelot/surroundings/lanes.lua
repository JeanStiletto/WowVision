-- Surroundings logic: centre lines (lanes) of roads and of the city's streets and walks. Near a
-- centre line the line decides whether the player is on the way, not the grid's cells: the way
-- counts from the stretch's enter distance and stops beyond its leave distance (in between the
-- state stays), so it is announced when the player is on track and left when drifting toward its
-- sides. The lines also tell which way to turn to face along the way, and where it bends.

local logic = WowVision.surroundingsLogic

local LANE_KEEP = { bridge = true } -- places a lane never replaces
local BESIDE_STEP, BESIDE_REACH = 2, 12 -- yd; looking outward from the line for what is beside the way
local ROAD_SIDE_CELLS = 3 -- cells searched beside a road for the nearest place that is no road
local MIN_SPAN = 3 -- yd; a stretch of line shorter than this gives no direction

-- The nearest point on a centre line within `reach` yards (at most LANE_REACH) of a way whose kind
-- is in `kinds` (a set; nil: any): distance, the lane {x1, y1, x2, y2, value, kind, enter, leave},
-- and the point; nil when there is none.
function logic.nearestLane(zone, x, y, reach, kinds)
    local r, c = logic.cellOf(zone, x, y)
    local list = zone._index.lanes[r * zone.cols + c]
    if list == nil then
        return nil
    end
    local best, bestLane, bx, by = nil, nil, nil, nil
    for _, lane in ipairs(list) do
        if kinds == nil or kinds[lane.kind] then
            local ax, ay, dx, dy = lane.x1, lane.y1, lane.x2 - lane.x1, lane.y2 - lane.y1
            local n = dx * dx + dy * dy
            local t = n > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / n)) or 0
            local px, py = ax + t * dx, ay + t * dy
            local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            if best == nil or d < best then
                best, bestLane, bx, by = d, lane, px, py
            end
        end
    end
    if best == nil or best > math.min(reach or logic.LANE_REACH, logic.LANE_REACH) then
        return nil
    end
    return best, bestLane, bx, by
end

-- The place value near a way with a centre line: `value` is the grid's, `onWay` whether the player
-- is on a way now (then the leave distance counts, else the enter distance). On the way: the
-- lane's value; off it, on the grid's cells of a way: the place beside it on the player's side
-- (outward from the line), for a road also the nearest place that is no road. Returns the value
-- and whether a lane decided it (false: no centre line near, or nothing beside the way, as along
-- a canal walk's water side: the grid as it is).
function logic.laneValue(zone, x, y, value, onWay)
    local kind = logic.kindOf(zone, value)
    if LANE_KEEP[kind] then
        return value, false
    end
    local d, lane, px, py = logic.nearestLane(zone, x, y)
    if d == nil then
        return value, false
    end
    if d <= (onWay and lane.leave or lane.enter) then
        return lane.value, true
    end
    if not logic.LANE_KINDS[kind] then
        return value, true
    end
    -- beside the way: outward from the line through the player, the first place that is no way
    local ux, uy = (x - px) / d, (y - py) / d
    for step = 0, BESIDE_REACH, BESIDE_STEP do
        local v = logic.valueAt(zone, x + ux * step, y + uy * step)
        if v ~= 0 and not logic.LANE_KINDS[logic.kindOf(zone, v)] then
            return v, true
        end
    end
    if not logic.ROADS[kind] then
        return value, false
    end
    local near, _x, _y, other = logic.nearestCell(zone, x, y, ROAD_SIDE_CELLS, nil, function(v)
        return v ~= 0 and not logic.ROADS[logic.kindOf(zone, v)]
    end)
    if near == nil then
        return value, false
    end
    return other, true
end

logic.TURN_OFF, logic.TURN_ACROSS = 8, 60 -- degrees
local TURN_SPAN = 6 -- yd before and after the nearest point

-- The nearest lane of a way with one direction here (not a fork or crossing): as nearestLane.
local function directedLane(zone, x, y)
    local d, lane, px, py = logic.nearestLane(zone, x, y)
    if d == nil or not logic.TURN_KINDS[lane.kind] then
        return nil
    end
    return d, lane, px, py
end

-- Which way to turn to face along the way here: the direction of its centre line over about 12 yd
-- around the nearest point (short stretches alone bend too much), taken the end nearer the
-- facing. `spokenAxis`: the axis the announcement says (index into zone.axes) or nil: a hint only
-- where the words cannot tell the player the facing is off, i.e. the facing points the same
-- compass way as that axis. Returns -1 (turn right), 1 (turn left), 0 (no turn needed), or nil
-- (no way with one direction here, or facing across it, crossing over).
function logic.turnHint(zone, x, y, facing, spokenAxis)
    local d, _lane, px, py = directedLane(zone, x, y)
    if d == nil then
        return nil
    end
    local fx, fy = math.cos(facing), math.sin(facing)
    local _a, _l1, ax, ay = logic.nearestLane(zone, px + fx * TURN_SPAN, py + fy * TURN_SPAN, TURN_SPAN, logic.LANE_KINDS)
    local _b, _l2, bx, by = logic.nearestLane(zone, px - fx * TURN_SPAN, py - fy * TURN_SPAN, TURN_SPAN, logic.LANE_KINDS)
    ax, ay, bx, by = ax or px, ay or py, bx or px, by or py
    local dx, dy = ax - bx, ay - by
    if dx * dx + dy * dy < MIN_SPAN * MIN_SPAN then
        return nil
    end
    local diff = logic.degreesBetween(math.atan2(dy, dx), facing)
    -- the way runs both ways: the end nearer the facing
    if diff > 90 then
        diff = diff - 180
    elseif diff < -90 then
        diff = diff + 180
    end
    local off = math.abs(diff)
    if off > logic.TURN_ACROSS then
        return nil
    end
    if off < logic.TURN_OFF or (spokenAxis and logic.facingAxis(facing) ~= spokenAxis) then
        return 0
    end
    return diff > 0 and 1 or -1
end

-- Where a road leads ahead: from the nearest point on its centre line toward the point on the line
-- about `look` yards further on, taking the end nearer the facing. The player's own position
-- across the road does not change it, so walking a little aside is no bend. Returns the direction
-- (radians like a facing) and the cell value of the line there, or nil (no way with one direction
-- here; facing across it).
function logic.wayAhead(zone, x, y, facing, look)
    local d, lane, px, py = directedLane(zone, x, y)
    if d == nil then
        return nil
    end
    local dx, dy = lane.x2 - lane.x1, lane.y2 - lane.y1
    local n = math.sqrt(dx * dx + dy * dy)
    if n == 0 then
        return nil
    end
    dx, dy = dx / n, dy / n
    local along = dx * math.cos(facing) + dy * math.sin(facing)
    if math.abs(along) < math.cos(math.rad(logic.TURN_ACROSS)) then
        return nil
    end
    if along < 0 then
        dx, dy = -dx, -dy
    end
    local _a, aheadLane, ax, ay = logic.nearestLane(zone, px + dx * look, py + dy * look, look, logic.LANE_KINDS)
    if aheadLane == nil or (ax - px) ^ 2 + (ay - py) ^ 2 < MIN_SPAN * MIN_SPAN then
        return nil
    end
    return math.atan2(ay - py, ax - px), aheadLane.value
end

logic.BEND_RESET = 60 -- degrees; more is turning round or another road

-- A gentle bend: `from` where the road led at the last message, `dir` where it leads now (both from
-- wayAhead), `threshold` degrees. Returns the turn to say (1 left, -1 right, 0 nothing) and whether
-- `dir` becomes the new `from`. The bend counts once the road has turned `threshold` degrees, and
-- is said only while the facing still points at least TURN_OFF degrees the other way from where
-- the road leads: a player already turned along it (or beyond) hears nothing.
function logic.bendTurn(from, dir, facing, threshold)
    local diff = logic.degreesBetween(dir, from)
    if math.abs(diff) > logic.BEND_RESET then
        return 0, true
    end
    if math.abs(diff) < threshold then
        return 0, false
    end
    local off = logic.degreesBetween(dir, facing)
    if (off > 0) == (diff > 0) and math.abs(off) >= logic.TURN_OFF then
        return diff > 0 and 1 or -1, true
    end
    return 0, true
end
