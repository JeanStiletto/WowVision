-- Surroundings logic: drop edges of structures (docks, bridges, walls, towers, the city water
-- edges), the high floor pieces they may lie on, and the water: what lies under a bridge and the
-- ways out of city water.
--
-- An edge on a floor piece (a gate's wall-walk, a bridge deck over a bank, a landing) warns only
-- while the player is on that piece. There is no height on Forever (measured 2026-10-05), so the
-- player's floor is followed from the ground: it changes only at a join crossed, at a drop edge
-- crossed, or when the floor is no longer under them (updateFloor); walking under a piece never
-- counts.

local logic = WowVision.surroundingsLogic

-- The water under a bridge cell (or the canal under a city street), as a cell value, or nil.
function logic.underBridge(zone, r, c)
    return zone._index.under[r * zone.cols + c]
end

-- The nearest way out of the water within `reach` yards: index, distance, the angle toward it,
-- the exit {x, y, width, out (the angle one climbs out toward, or nil)}.
function logic.nearestExit(zone, x, y, reach)
    return logic.nearestPoint(zone._index.exits, x, y, reach)
end

-- yd; a step (the move since the last look) crossing a join within this of one of its points
-- counts (the points lie about 2 yd apart along the line where two floors meet; 1.5 missed the
-- griffon ramp's foot by 0.2 yd, user's walk 2026-10-01)
logic.ACCESS_REACH = 2.5
logic.ROOMS_REACH = 6.0 -- yd from a building's door join, just after coming out of it
-- yd the step must reach beyond a join's line for the crossing to count: strafing along the rim
-- of a raised strip crosses its line back and forth by inches, and every crossing is a floor
-- change (the Valley of Heroes' avenue flipped four times in 11 s, replay 2026-10-05)
logic.CROSS_MARGIN = 0.5

-- The distance from (qx, qy) to the segment (ax, ay)-(bx, by).
local function segmentDistance(qx, qy, ax, ay, bx, by)
    local _px, _py, d = logic.segmentPoint(qx, qy, ax, ay, bx, by)
    return d
end

-- Is the floor piece `floor` under the cell `key`: the ground wherever the data does not say it
-- is absent (zone.noGround; the middle of a moat), another piece where the cell or one of the 8
-- cells around it lists it (zone.floorCells): a piece's floor has a cell without a walk surface
-- now and then (the moat under its bridges, the cavern floor), and the floor fell back to the
-- ground there for a step.
function logic.floorHere(zone, key, floor)
    local ix = zone._index
    if floor == 0 then
        return not ix.noGround[key]
    end
    local cols = zone.cols
    local r, c = math.floor(key / cols), key % cols
    for dr = -1, 1 do
        for dc = -1, 1 do
            local here = ix.floorCells[(r + dr) * cols + c + dc]
            if here ~= nil and here[floor] ~= nil then
                return true
            end
        end
    end
    return false
end

-- Did the step from (px, py) to (x, y) cross the join `j` (a point on the line where two floors
-- meet, with the direction from its piece a into b): within ACCESS_REACH beside the point, from
-- a's side to b's (1), from b's to a's (-1), or not (nil). A join without a direction counts
-- either way when the step passes within reach of it.
local function crossed(j, px, py, x, y)
    if j.angle == nil then
        return segmentDistance(j.x, j.y, px, py, x, y) <= logic.ACCESS_REACH and 0 or nil
    end
    local vx, vy = logic.compassVector(j.angle)
    local before = (px - j.x) * vx + (py - j.y) * vy
    local after = (x - j.x) * vx + (y - j.y) * vy
    if before == after then
        return nil
    end
    -- where the step meets the join's line, how far beside the point
    local t = before / (before - after)
    if t < 0 or t > 1 then
        return nil
    end
    local mx, my = px + (x - px) * t, py + (y - py) * t
    if math.abs((mx - j.x) * vy - (my - j.y) * vx) > logic.ACCESS_REACH then
        return nil
    end
    if before <= 0 and after > logic.CROSS_MARGIN then
        return 1
    elseif before >= 0 and after < -logic.CROSS_MARGIN then
        return -1
    end
    return nil
end

-- Updates the floor piece the player is on (zone._index.floor; 0 the ground: the one rule for
-- every floor over or under another, user 2026-10-05). It changes only (1) at a drop edge of the
-- floor crossed, onto the piece the drop lands on; (2) at a join crossed in its direction, from
-- the floor into the piece it meets there (a join from a building's door counts while `cameOut`,
-- within ROOMS_REACH); (3) when the floor is no longer under the player: then the piece here
-- that the floor joins or drops onto, else the only piece here where the ground is absent, else
-- the ground. `px, py`: the position at the last look. Returns the floor and whether it changed.
function logic.updateFloor(zone, x, y, cameOut, px, py)
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    local key = r * zone.cols + c
    local was = ix.floor or 0
    local floor = was
    local fell = px and logic.fellOnto(zone, floor, px, py, x, y)
    if fell then
        floor = fell
    elseif px then
        local n = math.ceil(logic.ROOMS_REACH / zone.cell)
        local best, bd = nil, nil
        for dr = -n, n do
            for dc = -n, n do
                for _, j in ipairs(ix.joinAt[(r + dr) * zone.cols + c + dc] or {}) do
                    local other, d = nil, nil
                    if j.a == -1 then
                        if cameOut and j.b ~= floor then
                            d = logic.dist(j.x, j.y, x, y)
                            other = d <= logic.ROOMS_REACH and j.b or nil
                        end
                    elseif j.a == floor or j.b == floor then
                        -- a join without a direction (a structure's, a step between two surfaces
                        -- of one cell) only leads from its a into its b: the piece is left by
                        -- walking off it, not by passing the point again
                        local way = crossed(j, px, py, x, y)
                        if way and ((way == 0 and j.a == floor) or (way ~= 0 and (way > 0) == (j.a == floor))) then
                            other = j.a == floor and j.b or j.a
                            d = logic.dist(j.x, j.y, x, y)
                        end
                    end
                    if other and (bd == nil or d < bd) then
                        best, bd = other, d
                    end
                end
            end
        end
        if best then
            floor = best
        end
    end
    -- a floor just entered is trusted for this look (a join point may lie a step outside the
    -- cells its piece has); otherwise the floor must be under the player
    if floor == was and not logic.floorHere(zone, key, floor) then
        local here = ix.floorCells[key]
        local pick, only, count = nil, nil, 0
        for p in pairs(here or {}) do
            only, count = p, count + 1
            if ix.joined[floor] and ix.joined[floor][p] and (pick == nil or p < pick) then
                pick = p
            end
        end
        if pick == nil and count == 1 and ix.noGround[key] then
            pick = only
        end
        floor = pick or 0
    end
    ix.floor = floor
    return floor, floor ~= was
end

-- Sets the floor piece the player is on (0 the ground); every lookup follows it.
function logic.setFloor(zone, floor)
    zone._index.floor = floor or 0
end

-- The label of the place a floor piece carries at (x, y) (nil for the ground, or a piece without
-- a place there): what names the piece across exports, which number the pieces anew.
function logic.pieceLabel(zone, x, y, floor)
    if not floor or floor == 0 then
        return nil
    end
    local r, c = logic.cellOf(zone, x, y)
    local v = logic.valueOfFloor(zone, r, c, floor)
    local place = v ~= 0 and logic.place(zone, logic.placeOf(v)) or nil
    return place and place.label or nil
end

-- The floor piece at (x, y) (the cell or one of the 8 around it) carrying the place `label`,
-- the piece `number` when it carries it, else the lowest numbered one; without a label the
-- number itself when that piece lies there; nil when no piece there fits (a reload memory
-- from before a re-export: the number means another piece now).
function logic.pieceWithLabel(zone, x, y, label, number)
    local ix = zone._index
    local cols = zone.cols
    local r0, c0 = logic.cellOf(zone, x, y)
    local found = nil
    for dr = -1, 1 do
        for dc = -1, 1 do
            local here = ix.floorCells[(r0 + dr) * cols + c0 + dc]
            for p, v in pairs(here or {}) do
                if label == nil then
                    if p == number then
                        return p
                    end
                else
                    local place = v ~= 0 and logic.place(zone, logic.placeOf(v)) or nil
                    if place and place.label == label then
                        if p == number then
                            return p
                        end
                        if found == nil or p < found then
                            found = p
                        end
                    end
                end
            end
        end
    end
    return found
end

function logic.edge(zone, i)
    return zone._index.edges[i]
end

-- Whether edge `i` is looked at from (x, y) at all: not skipped, on the floor piece the player is
-- on (zone._index.floor: an edge of the ground (floor 0) counts only on the ground, an edge of a
-- piece only up on it; down in the moat the walkways' edges are no drops; an edge with no floor
-- (nil: the zone's edges into water, a structure's low edges) on every floor), in one of the
-- rooms the player may be in (`rooms`, the indoor layers: an edge inside warns only in the room
-- its floor belongs to; nil: every room), and its box within `reach` yards.
local function edgeCounts(zone, e, i, x, y, reach, rooms, skip)
    if (skip and skip[i]) or (e.floor ~= nil and e.floor ~= (zone._index.floor or 0))
        or (rooms and e.piece ~= 0 and not rooms[e.piece]) then
        return false
    end
    local b = e.box
    return x >= b[1] - reach and x <= b[2] + reach and y >= b[3] - reach and y <= b[4] + reach
end

-- Does the player stand in front of the edge point (q), on the structure's side, not beyond it?
local function inFront(qx, qy, x, y, fx, fy)
    return (x - qx) * fx + (y - qy) * fy <= 0.5
end

-- The drop edge to warn about within `reach` yards: one the player stands in front of, on the
-- structure's floor; the edge index and distance. With `facing`, an edge ahead (within 90 degrees
-- of the view) wins over a nearer one beside or behind. `rooms`: the rooms the player may be in
-- (indoors), nil outdoors; `skip`: a set of edge indexes left out (warned already).
function logic.nearestEdge(zone, x, y, reach, rooms, facing, skip)
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    local vx, vy = nil, nil
    if facing then
        vx, vy = math.cos(facing), math.sin(facing)
    end
    local best, bestD, ahead, aheadD = nil, reach, nil, reach
    for i, e in ipairs(ix.edges) do
        if edgeCounts(zone, e, i, x, y, reach, rooms, skip) then
            local fx, fy = logic.compassVector(e.facing)
            local p = e.points
            for k = 1, #p - 1, 2 do
                local qx, qy = p[k], p[k + 1]
                local d = logic.dist(x, y, qx, qy)
                if (d <= bestD or d <= aheadD) and inFront(qx, qy, x, y, fx, fy)
                    and logic.nearCell(zone, ix.struct, r, c, e.struct) then
                    if d <= bestD then
                        best, bestD = i, d
                    end
                    -- ahead in the view: toward the point, or, standing on it, toward the drop
                    local dx, dy = qx - x, qy - y
                    if d < 0.5 then
                        dx, dy = fx, fy
                    end
                    if vx and d <= aheadD and dx * vx + dy * vy >= 0 then
                        ahead, aheadD = i, d
                    end
                end
            end
        end
    end
    if ahead then
        return ahead, aheadD
    end
    return best, best and bestD
end

logic.AHEAD_WIDTH = 1.5 -- yd beside the path
logic.AHEAD_ANGLE = 0.25 -- cosine: the path turns at most 75 degrees away from the drop

-- A drop edge in the player's path: moving along the unit vector (vx, vy), an edge point at most
-- `look` yards ahead and AHEAD_WIDTH beside the path, whose drop lies ahead (not running along
-- the edge), with the player on the structure in front of it. Returns the edge index, the
-- distance along the path and the edge point in the path (x, y). `rooms` and `skip` as for
-- nearestEdge; `all` (optional): a set that gets every edge in the path.
function logic.edgeAhead(zone, x, y, vx, vy, look, rooms, skip, all)
    local ix = zone._index
    if look <= 0 then
        return nil
    end
    local r, c = logic.cellOf(zone, x, y)
    local best, bestAlong, bx, by = nil, look, nil, nil
    for i, e in ipairs(ix.edges) do
        local fx, fy = logic.compassVector(e.facing)
        if fx * vx + fy * vy >= logic.AHEAD_ANGLE and edgeCounts(zone, e, i, x, y, look, rooms, skip) then
            local p = e.points
            for k = 1, #p - 1, 2 do
                local dx, dy = p[k] - x, p[k + 1] - y
                local along = dx * vx + dy * vy
                if along > 0 and along <= (all and look or bestAlong) and math.abs(dx * vy - dy * vx) <= logic.AHEAD_WIDTH
                    and inFront(p[k], p[k + 1], x, y, fx, fy) and logic.nearCell(zone, ix.struct, r, c, e.struct) then
                    if all then
                        all[i] = true
                    end
                    if along <= bestAlong then
                        best, bestAlong, bx, by = i, along, p[k], p[k + 1]
                    end
                end
            end
        end
    end
    if best then
        return best, bestAlong, bx, by
    end
    return nil
end

logic.FALL_REACH = 3.0 -- yd from an edge point a step over the edge counts as a fall over it

-- The floor piece a step from (px, py) to (x, y) fell onto: over a drop edge of the floor the
-- player is on (`floor`) whose drop lands on another piece (zone edges with `under`; the ground
-- is 0), from the side the edge's floor is on to the other; or nil.
function logic.fellOnto(zone, floor, px, py, x, y)
    local ix = zone._index
    if px == nil then
        return nil
    end
    for _, e in ipairs(ix.edges) do
        if e.under ~= nil and (e.floor == nil or e.floor == floor) then
            local b = e.box
            local reach = logic.FALL_REACH
            if x >= b[1] - reach and x <= b[2] + reach and y >= b[3] - reach and y <= b[4] + reach then
                local fx, fy = logic.compassVector(e.facing)
                local p = e.points
                for k = 1, #p - 1, 2 do
                    local qx, qy = p[k], p[k + 1]
                    if logic.dist(x, y, qx, qy) <= reach and inFront(qx, qy, px, py, fx, fy)
                        and not inFront(qx, qy, x, y, fx, fy) then
                        return e.under
                    end
                end
            end
        end
    end
    return nil
end

-- Distance from a position to the nearest point of edge `i`.
function logic.edgeDistance(zone, i, x, y)
    return logic.nearestOfPoints(zone._index.edges[i].points, x, y) or math.huge
end
