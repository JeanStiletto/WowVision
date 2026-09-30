-- Surroundings logic: what the player bumps into. Objects are footprints {x, y, halfLength,
-- halfWidth, angle (of the long axis), name, room (0 = outdoors)}; without one in the way, the
-- wall of the building or structure ahead.

local logic = WowVision.surroundingsLogic

logic.BUMP_REACH = 1.5 -- yd from the player to an object that can be what they push against
logic.BUMP_ANGLE = 0.34 -- cosine: the object lies at most 70 degrees off the way they push
local TOUCHING = 0.3 -- yd; this close an object counts whichever way the player pushes

-- The nearest point of an object's footprint to a position, and the distance.
function logic.objectPoint(o, x, y)
    local ux, uy = math.cos(o.angle), math.sin(o.angle)
    local dx, dy = x - o.x, y - o.y
    local pu = math.max(-o.halfLength, math.min(o.halfLength, dx * ux + dy * uy))
    local pv = math.max(-o.halfWidth, math.min(o.halfWidth, -dx * uy + dy * ux))
    local qx, qy = o.x + pu * ux - pv * uy, o.y + pu * uy + pv * ux
    return qx, qy, math.sqrt((x - qx) ^ 2 + (y - qy) ^ 2)
end

-- The object the player pushes against: moving (or trying to) along the unit vector (vx, vy), the
-- nearest object within `reach` yards that lies that way. `room`: only objects of this room
-- (0 = outdoors, nil = any). Returns the object and its distance, or nil.
function logic.objectAhead(zone, x, y, vx, vy, reach, room)
    local buckets = zone._index.objects
    local r, c = logic.cellOf(zone, x, y)
    local n = math.ceil(reach / zone.cell)
    local best, bestD, seen = nil, reach, {}
    for dr = -n, n do
        for dc = -n, n do
            for _, o in ipairs(buckets[(r + dr) * zone.cols + c + dc] or {}) do
                if not seen[o] and (room == nil or o.room == room) then
                    seen[o] = true
                    local qx, qy, d = logic.objectPoint(o, x, y)
                    if d <= bestD and (d < TOUCHING or ((qx - x) * vx + (qy - y) * vy) / d >= logic.BUMP_ANGLE) then
                        best, bestD = o, d
                    end
                end
            end
        end
    end
    return best, best and bestD
end

local WALL_STEP = 0.5 -- yd between the points looked at ahead

-- Whose wall the player pushes against from outside: the interior whose room floor or outline lies
-- just ahead (within `reach` yards along the vector), a structure with drop edges (a gate, a
-- wall, a pier) whose floor lies there, or the side of a ramp or stairs the player does not stand
-- on (the Dwarven District bank's ramp stands 4 yd over the street beside it). Returns the name
-- (and "side" for a ramp or stairs) or nil.
function logic.wallOwner(zone, x, y, vx, vy, reach)
    local ix = zone._index
    local here = logic.valueAt(zone, x, y)
    for k = WALL_STEP, reach, WALL_STEP do
        local px, py = x + vx * k, y + vy * k
        local id = logic.roomCandidates(zone, px, py, 0)[1] or logic.roomOutlineAt(zone, px, py)
        if id then
            local interior = ix.interiors[ix.rooms[id].interior]
            return interior and interior.name
        end
        local r, c = logic.cellOf(zone, px, py)
        local struct = ix.struct[r * zone.cols + c]
        if struct and not ix.waterStructs[struct] then
            return zone.structs[struct]
        end
        local value = logic.valueAtCell(zone, r, c)
        if value ~= 0 and logic.placeOf(value) ~= logic.placeOf(here) and logic.CLIMBS[logic.kindOf(zone, value)] then
            return logic.place(zone, logic.placeOf(value)).label, "side"
        end
    end
    return nil
end
