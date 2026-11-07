-- Surroundings logic: whose wall the player bumps into outside. What they bump into is named by the bump module
-- (core/navigation/bumps.lua), which asks this module for the wall ahead (module.lua: its room source): this
-- module knows a ramp's or stairs' side, which needs the place grid. The objects are the bump layer's.

local logic = WowVision.surroundingsLogic

local WALL_STEP = 0.5 -- yd between the points looked at ahead

-- Whose wall the player pushes against from outside: the interior whose room floor or outline lies
-- just ahead (within `reach` yards along the vector), a structure with drop edges (a gate, a
-- wall, a pier) whose floor lies there, or the side of a ramp or stairs the player does not stand
-- on (the Dwarven District bank's ramp stands 4 yd over the street beside it). Returns the name
-- (and "side" for a ramp or stairs, "place" for an interior named only "building of <place>":
-- then the place alone, user 2026-10-07: "wall, Ruins of Lordaeron" is enough) or nil.
function logic.wallOwner(zone, x, y, vx, vy, reach)
    local ix = zone._index
    local here = logic.valueAt(zone, x, y)
    for k = WALL_STEP, reach, WALL_STEP do
        local px, py = x + vx * k, y + vy * k
        local id = logic.roomCandidates(zone, px, py, 0)[1] or logic.roomOutlineAt(zone, px, py)
        if id then
            local interior = ix.interiors[ix.rooms[id].interior]
            if interior and interior.wall then
                return interior.wall, "place"
            end
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
