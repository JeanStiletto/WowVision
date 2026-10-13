-- Surroundings logic: centre lines (lanes) of roads and of the city's streets and walks. Near a
-- centre line the line decides whether the player is on the way, not the grid's cells: the way
-- counts from the stretch's enter distance and stops beyond its leave distance (in between the
-- state stays), so it is announced when the player is on track and left when drifting toward its
-- sides. The lines also tell which way to turn to face along the way, and where it bends.

local logic = WowVision.surroundingsLogic

-- places a lane never replaces (a platform: what lies beside or under it is not where one stands;
-- the street under the griffon ramp's walkway was said up there, walk 2026-10-12 18:36)
local LANE_KEEP = { bridge = true, platform = true }
local MIN_SPAN = 3 -- yd; a stretch of line shorter than this gives no direction

-- The nearest point on a centre line within `reach` yards (at most LANE_REACH) of a way whose kind
-- is in `kinds` (a set; nil: any): distance, the lane {x1, y1, x2, y2, value, kind, enter, leave},
-- and the point; nil when there is none. `skip`: a lane left out; `place`: only lanes of that place.
function logic.nearestLane(zone, x, y, reach, kinds, skip, place)
    local r, c = logic.cellOf(zone, x, y)
    local ix = zone._index
    local list = ix.lanes[r * zone.cols + c]
    if list == nil then
        return nil
    end
    -- a stretch whose floor lies over or under other floor counts only on its piece (the
    -- ground's lines not up on a landing over them, the landing's not down on the street); any
    -- other stretch (piece -1) counts on every floor: the position alone finds it
    local floor = ix.floor or 0
    -- up on a piece that joins the ground nowhere (a tower's landing), a stretch of every floor
    -- counts only where that piece (or one joined to it) lies: the road beside the tower is not
    -- the landing's 12 yd over it
    local joined = floor ~= 0 and ix.joined[floor] or nil
    local aloft = floor ~= 0 and not (joined and joined[0])
    local best, bestLane, bx, by = nil, nil, nil, nil
    for _, lane in ipairs(list) do
        if (kinds == nil or kinds[lane.kind]) and lane ~= skip and (lane.piece == -1 or lane.piece == floor)
            and (place == nil or logic.placeOf(lane.value) == place) then
            local px, py, d = logic.segmentPoint(x, y, lane.x1, lane.y1, lane.x2, lane.y2)
            local here = true
            if aloft and lane.piece == -1 then
                local lr, lc = logic.cellOf(zone, px, py)
                local cell = ix.floorCells[lr * zone.cols + lc]
                here = false
                for p in pairs(cell or {}) do
                    if p == floor or (joined and joined[p]) then
                        here = true
                        break
                    end
                end
            end
            if here and (best == nil or d < best) then
                best, bestLane, bx, by = d, lane, px, py
            end
        end
    end
    if best == nil or best > math.min(reach or logic.LANE_REACH, logic.LANE_REACH) then
        return nil
    end
    return best, bestLane, bx, by
end

-- Which side of a stretch the player is on: 1 left of its direction (x1 to x2), 2 right.
function logic.laneSide(lane, x, y)
    local cross = (lane.x2 - lane.x1) * (y - lane.y1) - (lane.y2 - lane.y1) * (x - lane.x1)
    return cross >= 0 and 1 or 2
end

-- A stretch's enter and leave distances on the player's side (the data measures each side on
-- its own: a wall on one side no longer narrows the other).
function logic.laneWidths(lane, x, y)
    if logic.laneSide(lane, x, y) == 1 then
        return lane.enter, lane.leave
    end
    return lane.enter2 or lane.enter, lane.leave2 or lane.leave
end

-- The place value near a way with a centre line: `value` is the grid's, `onWay` whether the player
-- is on a way now (then the leave distance counts, else the enter distance). On the way: the
-- lane's value. Off it the cell under the player decides (user 2026-10-01: "I walk up a whatever
-- and am on it"): a cell of a way goes on as that way (the ramp cell beside the street's line,
-- the wide sloped street beyond its narrow lane), any other cell is the place beside the way.
-- (Before: outward from the line, the first place that is no way within 6 yd, which said "Trade
-- District, street to the south" while the player stood on the slope's floor.) Returns the value
-- and whether a lane decided it (false: no centre line near, or a way's cell off the line).
function logic.laneValue(zone, x, y, value, onWay)
    local kind = logic.kindOf(zone, value)
    if LANE_KEEP[kind] then
        return value, false
    end
    local d, lane = logic.nearestLane(zone, x, y)
    if d ~= nil then
        local enter, leave = logic.laneWidths(lane, x, y)
        if d <= (onWay and leave or enter) then
            return lane.value, true
        end
    end
    -- a cell of a way with one direction but no direction code (a scrap of the way too small for a
    -- centre line: six cells at the foot of the Trade District ramp said "street, right" with no
    -- direction, user 2026-10-01): the value of the same way's nearest line within reach, so the
    -- scrap speaks and is keyed as one piece with it
    if logic.TURN_KINDS[kind] and logic.codeOf(value) == 0 then
        local _sd, same = logic.nearestLane(zone, x, y, logic.LANE_REACH, nil, nil, logic.placeOf(value))
        if same then
            value = same.value
        end
    end
    return value, not logic.LANE_KINDS[kind]
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

-- The way's direction here: from the nearest point (px, py) on the centre line of the way with one
-- direction under the player, the line about TURN_SPAN yd before and after that point along the
-- facing (short stretches alone bend too much; a city street's line has short bits at forks).
-- Returns px, py and the offset (dx, dy) from the point behind to the point ahead, or nil (no such
-- way here, or the line too short).
local function lineHere(zone, x, y, facing)
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
    return px, py, dx, dy
end

-- Which way to turn to face along the way here: the direction of its centre line over about 12 yd
-- around the nearest point (lineHere), taken the end nearer the facing. `spokenAxis`: the axis
-- angle the announcement says (0..179) or nil: a hint only where the words cannot tell the player
-- the facing is off, i.e. the facing points the same compass way as that axis. Returns -1 (turn
-- right), 1 (turn left), 0 (no turn needed), or nil (no way with one direction here, or facing
-- across it, crossing over).
function logic.turnHint(zone, x, y, facing, spokenAxis)
    local px, py, dx, dy = lineHere(zone, x, y, facing)
    if px == nil then
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
    if off < logic.TURN_OFF or (spokenAxis and not logic.sameAxis(logic.facingAxis(facing), spokenAxis)) then
        return 0
    end
    return diff > 0 and 1 or -1
end

-- The heading the export stored for the spot (px, py) on `lane` (zone.lua: lane.headings), one
-- each way: toward the stretch's end and back (bearings, or nil where it stored none).
local function storedHeadings(lane, px, py)
    local h = lane.headings
    if h == nil then
        return nil, nil
    end
    local n = #h / 2
    local length = logic.dist(lane.x1, lane.y1, lane.x2, lane.y2)
    local t = length > 0 and logic.dist(lane.x1, lane.y1, px, py) / length or 0
    local j = math.min(n - 1, math.max(0, math.floor(t * n)))
    local toEnd, back = h[2 * j + 1], h[2 * j + 2]
    return toEnd and toEnd >= 0 and toEnd or nil, back and back >= 0 and back or nil
end

-- The facings along the centre lines where the player stands, for the turn key while no beacon
-- leads (radians like a facing), read from the data, nothing worked out here: on a way with one
-- direction the headings of the way ahead the export stored for the spot of the stretch under the
-- player, one each way (lane_headings: every 2 yd the line's heading 5 yd on, by the bend rule;
-- near a line's end the other one turned round; until 2026-10-14 the key took a 12 yd stretch
-- centred on the player, which in bends turned it half way, walk 2026-10-13 23:07); without them
-- the stretch's own direction, without a stretch the direction the way is said with; on a bridge
-- the direction it is said with; on a fork or crossing its arms (the label's angles, as the fork
-- is said). Returns the list and whether it is a fork's, or nil (no way here, a square).
function logic.lineFacings(zone, x, y, value, _facing)
    local kind = logic.kindOf(zone, value)
    if logic.TURN_KINDS[kind] or kind == "bridge" then
        local d, lane, px, py = nil, nil, nil, nil
        if kind ~= "bridge" then
            d, lane, px, py = directedLane(zone, x, y)
        end
        if d ~= nil and (lane.x1 ~= lane.x2 or lane.y1 ~= lane.y2) then
            local along = math.atan2(lane.y2 - lane.y1, lane.x2 - lane.x1)
            -- a stored heading (clockwise from north) as a facing; near the line's end (none ahead)
            -- the heading the other way turned round, the way the line came; else the stretch's own
            local h1, h2 = storedHeadings(lane, px, py)
            local f1 = (h1 and math.rad(-h1)) or (h2 and math.rad(-h2) + math.pi) or along
            local f2 = (h2 and math.rad(-h2)) or (h1 and math.rad(-h1) + math.pi) or along + math.pi
            return { f1, f2 }, false
        end
        -- the direction said (degrees clockwise from north, an axis; a climb's rise)
        local axis = logic.axisOf(zone, value) or logic.riseOf(zone, value)
        if axis == nil then
            return nil
        end
        local along = math.rad(-axis)
        return { along, along + math.pi }, false
    end
    if kind ~= "fork" and kind ~= "crossing" then
        return nil
    end
    local place = logic.place(zone, logic.placeOf(value))
    local facings = {}
    for list in ((place and place.label) or ""):gmatch("<d([%d,]+)>") do
        for a in list:gmatch("%d+") do
            -- degrees clockwise from north to a facing (counter-clockwise from north)
            facings[#facings + 1] = math.rad(-tonumber(a))
        end
    end
    if #facings == 0 then
        return nil
    end
    return facings, true
end

-- degrees; at a fork an arm this close to the facing is the one faced (the turn key's calm zone,
-- turnTo.lua's TOLERANCE: farther off, a press corrects onto it)
logic.LINE_FACED = 3

-- Which of `facings` the turn key turns to: the one nearest the facing; at a fork (`cycle`), when
-- the player faces an arm already, the next arm clockwise (each press turns to the next).
function logic.lineTurnFacing(facings, facing, cycle)
    local best, bestOff = nil, nil
    for _, f in ipairs(facings) do
        local off = math.abs(logic.degreesBetween(f, facing))
        if bestOff == nil or off < bestOff then
            best, bestOff = f, off
        end
    end
    if not cycle or bestOff > logic.LINE_FACED then
        return best
    end
    -- clockwise is a falling facing: the smallest clockwise gap beyond the arm faced
    local next, nextGap = nil, nil
    for _, f in ipairs(facings) do
        local gap = (-logic.degreesBetween(f, facing)) % 360
        if gap > logic.LINE_FACED and (nextGap == nil or gap < nextGap) then
            next, nextGap = f, gap
        end
    end
    return next or best
end

-- Where a road or street leads ahead: from the nearest point on its centre line toward the point
-- on the line about `look` yards further on, taking the end nearer the facing. The player's own position
-- across the road does not change it, so walking a little aside is no bend. Returns the direction
-- (radians like a facing) and the cell value of the line there, or nil (no way with one direction
-- here; facing across it).
function logic.wayAhead(zone, x, y, facing, look)
    local px, py, dx, dy = lineHere(zone, x, y, facing)
    if px == nil then
        return nil
    end
    local n = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / n, dy / n
    local along = dx * math.cos(facing) + dy * math.sin(facing)
    if math.abs(along) < math.cos(math.rad(logic.TURN_ACROSS)) then
        return nil
    end
    if along < 0 then
        dx, dy = -dx, -dy
    end
    local _a, aheadLane, ax, ay = logic.nearestLane(zone, px + dx * look, py + dy * look, look, logic.LANE_KINDS)
    if aheadLane == nil or logic.dist2(ax, ay, px, py) < MIN_SPAN * MIN_SPAN then
        return nil
    end
    return math.atan2(ay - py, ax - px), aheadLane.value
end

-- yd; on a way the next piece is said this far before it (12 until 2026-10-12: over the walks of
-- 2026-09-29 to 10-12 the player stopped or turned a median 6 yd after the line, on the piece where
-- it was 9 yd off or less when said, 6 yd short of it where it was 12; capped at 8, 44 of 79 such
-- stops early -> 36)
logic.AHEAD_LOOK = 6
logic.AHEAD_MIN = 4 -- yd; a next piece closer than this is left to its own announcement
local AHEAD_STEP = 2 -- yd between the looks ahead along the way
-- yd; a look ahead finds the line's next stretch this close to it (stretches of one line meet
-- end to end; a line beside it farther off is another way: 6 yd found parallel fragments and
-- the lines of a bay beside the way, said as the next piece and never entered, Stormwind 2026-09-30)
local AHEAD_JOIN = 3

-- The next piece ahead on a way: from the nearest point on its centre line, along the line in
-- the direction of `heading` (radians; the way one moves), every AHEAD_STEP yd up to `look`,
-- following the line from stretch to stretch (each look moves to the nearest point of the
-- stretch found, so bends are followed and a line that ends says nothing); the first stretch of
-- another value than `current` (the cell value of the piece the player is on) is the next piece.
-- Returns its cell value and the yards to it, or nil (none within look, the heading across the way).
function logic.pieceAhead(zone, x, y, heading, current, look)
    local d, lane, px, py = directedLane(zone, x, y)
    if d == nil then
        return nil
    end
    -- the piece the player is on, as the entry rule keys it (a key, or a cell value)
    local currentKey = type(current) == "string" and current or logic.outdoorKey(zone, current)
    local fx, fy = math.cos(heading), math.sin(heading)
    local dx, dy = lane.x2 - lane.x1, lane.y2 - lane.y1
    local n = math.sqrt(dx * dx + dy * dy)
    if n < MIN_SPAN then
        return nil
    end
    dx, dy = dx / n, dy / n
    local along = dx * fx + dy * fy
    if math.abs(along) < math.cos(math.rad(logic.TURN_ACROSS)) then
        return nil
    end
    if along < 0 then
        dx, dy = -dx, -dy
    end
    local walked, last = 0, lane
    for _ = 1, math.ceil(2 * look / AHEAD_STEP) do
        local qx, qy = px + dx * AHEAD_STEP, py + dy * AHEAD_STEP
        local _d, next, nx, ny = logic.nearestLane(zone, qx, qy, AHEAD_JOIN, logic.LANE_KINDS)
        if next == nil then
            return nil
        end
        local step = logic.dist(nx, ny, px, py)
        if step < 0.5 and next == last then
            -- the stretch's end: the one meeting it there (a corner), else the line ends
            _d, next, nx, ny = logic.nearestLane(zone, qx, qy, AHEAD_JOIN, logic.LANE_KINDS, last)
            if next == nil then
                return nil
            end
            step = logic.dist(nx, ny, px, py)
        end
        walked = walked + step
        if logic.outdoorKey(zone, next.value, currentKey) ~= currentKey then
            return next.value, walked, nx, ny
        end
        if walked >= look then
            return nil
        end
        -- on along the stretch found, the way that keeps the heading
        local ex, ey = next.x2 - next.x1, next.y2 - next.y1
        local en = math.sqrt(ex * ex + ey * ey)
        if en > 0 then
            ex, ey = ex / en, ey / en
            if ex * dx + ey * dy < 0 then
                ex, ey = -ex, -ey
            end
            dx, dy = ex, ey
        end
        px, py, last = nx, ny, next
    end
    return nil
end

-- A gentle bend: `from` where the road led at the last message, `dir` where it leads now (both from
-- wayAhead), `threshold` degrees. Returns the turn to say (1 left, -1 right, 0 nothing) and whether
-- `dir` becomes the new `from`. The bend counts once the road has turned `threshold` degrees, and
-- is said only while the facing still points at least TURN_OFF degrees the other way from where
-- the road leads: a player already turned along it (or beyond) hears nothing. A turn of a whole
-- direction word (wordStep) or more is no bend: the hint only steers within the margin the words
-- leave (user 2026-10-03: "a street turning from 10 o'clock to 11 o'clock needs no hint, I can
-- turn myself then"; was 60 degrees).
function logic.bendTurn(from, dir, facing, threshold)
    local diff = logic.degreesBetween(dir, from)
    if math.abs(diff) >= logic.wordStep() then
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
