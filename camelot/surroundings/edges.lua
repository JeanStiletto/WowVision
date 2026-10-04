-- Surroundings logic: drop edges of structures (docks, bridges, walls, towers, the city water
-- edges), the high floor pieces they may lie on, and the water: what lies under a bridge and the
-- ways out of city water.
--
-- An edge on a high piece (a gate's wall-walk, a bridge deck over a bank) warns only while the
-- player is up there. There is no height on Forever, so a piece counts from where the player is
-- seen stepping onto it: from the ground where it joins level 0, out of a building's rooms, or from
-- a joined piece; walking under it never counts.

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

-- yd; a step (the move since the last look) passing this close to a place where a high piece is
-- stepped onto from the ground counts (the places lie about 2 yd apart along the step's line; 1.5
-- missed the griffon ramp's foot by 0.2 yd, user's walk 2026-10-01 10:47, and the ramp said the
-- level below; a cell of another place drops the piece again, so the bay beside the foot no
-- longer counts as the ramp)
logic.ACCESS_REACH = 2.5
-- place kinds painted over a raised piece's own floor that keep the player on it
local KEEP_ON = { fork = true, crossing = true, bridge = true }
logic.ROOMS_REACH = 6.0 -- yd from where it joins a building, just after coming out of it

-- The distance from (qx, qy) to the segment (ax, ay)-(bx, by).
local function segmentDistance(qx, qy, ax, ay, bx, by)
    local _px, _py, d = logic.segmentPoint(qx, qy, ax, ay, bx, by)
    return d
end

-- Updates the set `on` of the high pieces the player is on: a piece is entered by passing where
-- it is stepped onto from the ground (on no piece), where it joins a building the player just came
-- out of (`cameOut`), or from a joined piece the player is on; it is left by walking off its
-- footprint. A step from the ground counts only from a cell painted with the piece's own floor
-- (zone.piecePlaces): not from the bay under the landing at the griffon ramp's foot, 2 yd from
-- where the ramp rises (a false "8 deep" there, user's walk 2026-09-30). `px, py`: the position
-- at the last look (the step from there counts). Returns the set and whether it changed.
function logic.updateHigh(zone, on, x, y, cameOut, px, py)
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    local changed = false
    -- a hall's lower level is also entered by falling: walking over an edge whose drop falls onto
    -- it (the moat's rim: user's walk 2026-10-02, the trench is 19 yd under the walkways)
    local fell = logic.fellOnto(zone, on, px, py, x, y)
    if fell and not on[fell] then
        on[fell] = true
        changed = true
    end
    local painted = logic.placeOf(logic.paintedAtCell(zone, r, c))
    local paintedKind = painted ~= 0 and logic.kind(zone, painted) or nil
    local left = {}
    for piece in pairs(on) do
        local stays = logic.nearCell(zone, ix.pieces, r, c, piece)
        -- on its footprint but on a cell painted with another place (not a fork or bridge on the
        -- piece) that is not stacked under it, the player is beside the piece, not on it: the bay
        -- beside the griffon ramp's foot is a dead end's cells, the ramp's floor the ramp's and its
        -- street's (the user stood in the bay counted on the ramp for two minutes, hearing the
        -- ramp's edges and the level up on it, 2026-10-01)
        local own = ix.piecePlaces and ix.piecePlaces[piece]
        if stays and own and painted ~= 0 and not own[painted] and not KEEP_ON[paintedKind] then
            stays = false
            for _, a in ipairs(ix.stacked and ix.stacked[r * zone.cols + c] or {}) do
                if a.piece == piece then
                    stays = true
                end
            end
        end
        if not stays then
            on[piece] = nil
            changed = true
            left[#left + 1] = piece
        end
    end
    -- in a hall (the indoor layers' levels, zone.pieceOwn): the same level going on in the next
    -- piece of it, a piece of the same place stacked here (the moat is cut into nine pieces; at
    -- their seams the player left one and was on none, hearing the walkways over the trench,
    -- replay of the walk 2026-10-02 16:47). Not outdoors: the city's raised pieces carry their
    -- renamed streets, and the rule moved Stormwind's Mage Quarter stairs onto a street.
    local key = r * zone.cols + c
    for _, piece in ipairs(zone.pieceOwn and left or {}) do
        local own = ix.piecePlaces and ix.piecePlaces[piece]
        if own then
            for _, a in ipairs(ix.stacked and ix.stacked[key] or {}) do
                local theirs = ix.piecePlaces[a.piece]
                if not on[a.piece] and theirs then
                    for place in pairs(own) do
                        if theirs[place] then
                            on[a.piece] = true
                        end
                    end
                end
            end
        end
    end
    -- standing where only a level's floor is (the indoor layers' pieceOwn: the middle of the moat,
    -- the stairs down to it) the player is on that level
    for _, piece in ipairs(ix.pieceOwn and ix.pieceOwn[key] or {}) do
        if not on[piece] then
            on[piece] = true
            changed = true
        end
    end
    -- level 0, the ground outdoors or a hall's or a building's main floor: a piece is stepped onto
    -- where it joins level 0 (zone.groundAt), from a cell painted with its own floor, unless the
    -- player is up on a piece lying over the ground here (one rule for every floor over another,
    -- user 2026-10-04: the Brill tavern's room upstairs lies over the cellar stairs' top; Stormwind's
    -- docks are stepped onto from beside the quay, which the player still counts on)
    local n = math.ceil(logic.ROOMS_REACH / zone.cell)
    local ground = true
    for _, a in ipairs(ix.stacked and ix.stacked[key] or {}) do
        ground = ground and not on[a.piece]
    end
    for dr = -n, n do
        for dc = -n, n do
            local cell = (r + dr) * zone.cols + c + dc
            for _, g in ipairs(ground and ix.groundAt[cell] or {}) do
                local own = ix.piecePlaces and ix.piecePlaces[g.piece]
                if (own == nil or own[painted]) and not on[g.piece]
                    and segmentDistance(g.x, g.y, px or x, py or y, x, y) <= logic.ACCESS_REACH then
                    on[g.piece] = true
                    changed = true
                end
            end
            -- ... and where it joins a building the player just came out of
            for _, a in ipairs(cameOut and ix.access[cell] or {}) do
                if a.kind == 2 and not on[a.piece] and logic.dist(a.x, a.y, x, y) <= logic.ROOMS_REACH then
                    on[a.piece] = true
                    changed = true
                end
            end
        end
    end
    local added = true
    while added do
        added = false
        local new = {}
        if ix.linkAt then
            -- joined where the two levels meet: the step passes the place (the Brill tavern's
            -- landing lies over the foot of its stairs, next to it the player was up at once)
            local m = math.ceil(logic.ACCESS_REACH / zone.cell) + 1
            for dr = -m, m do
                for dc = -m, m do
                    for _, l in ipairs(ix.linkAt[(r + dr) * zone.cols + c + dc] or {}) do
                        local other = on[l.a] and not on[l.b] and l.b or on[l.b] and not on[l.a] and l.a or nil
                        if other and segmentDistance(l.x, l.y, px or x, py or y, x, y) <= logic.ACCESS_REACH then
                            new[#new + 1] = other
                        end
                    end
                end
            end
        else
            for piece in pairs(on) do
                for _, other in ipairs(ix.links[piece] or {}) do
                    if not on[other] and logic.nearCell(zone, ix.pieces, r, c, other) then
                        new[#new + 1] = other
                    end
                end
            end
        end
        for _, piece in ipairs(new) do
            on[piece] = true
            added, changed = true, true
        end
    end
    if ix.linkAt then
        -- of two joined levels the one whose floor is right here (the room beside the landing, a
        -- step through its doorway; next to the landing's footprint the landing held for 17 s)
        local here = ix.pieces[key]
        local exact = false
        for piece in pairs(on) do
            exact = exact or (here and here[piece]) or false
        end
        if exact then
            for piece in pairs(on) do
                if not here[piece] then
                    on[piece] = nil
                    changed = true
                end
            end
        end
    end
    return on, changed
end

function logic.edge(zone, i)
    return zone._index.edges[i]
end

-- Is an edge on the level the player is on? In a hall (the indoor layers) `levels` is the set of
-- the hall's other levels the player is on: an edge of the main floor counts only while on none,
-- an edge of a level only while on it (down in the moat the walkways' edges are no drops). nil:
-- every edge (outdoors).
local function onLevel(e, levels)
    if levels == nil then
        return true
    end
    if e.level == 0 then
        return next(levels) == nil
    end
    return levels[e.level] == true
end

-- Whether edge `i` is looked at from (x, y) at all: not skipped, low or on a piece the player is
-- on (`on`), on the level the player is on (`levels`), and its box within `reach` yards.
local function edgeCounts(e, i, x, y, reach, on, skip, levels)
    if (skip and skip[i]) or (e.piece ~= 0 and not (on and on[e.piece])) or not onLevel(e, levels) then
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
-- of the view) wins over a nearer one beside or behind. `on`: the high pieces the player is on
-- (see updateHigh); `skip`: a set of edge indexes left out (warned already).
function logic.nearestEdge(zone, x, y, reach, on, facing, skip, levels)
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    local vx, vy = nil, nil
    if facing then
        vx, vy = math.cos(facing), math.sin(facing)
    end
    local best, bestD, ahead, aheadD = nil, reach, nil, reach
    for i, e in ipairs(ix.edges) do
        if edgeCounts(e, i, x, y, reach, on, skip, levels) then
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
-- distance along the path and the edge point in the path (x, y). `on` and `skip` as for
-- nearestEdge; `all` (optional): a set that gets every edge in the path.
function logic.edgeAhead(zone, x, y, vx, vy, look, on, skip, all, levels)
    local ix = zone._index
    if look <= 0 then
        return nil
    end
    local r, c = logic.cellOf(zone, x, y)
    local best, bestAlong, bx, by = nil, look, nil, nil
    for i, e in ipairs(ix.edges) do
        local fx, fy = logic.compassVector(e.facing)
        if fx * vx + fy * vy >= logic.AHEAD_ANGLE and edgeCounts(e, i, x, y, look, on, skip, levels) then
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

-- The level a step from (px, py) to (x, y) fell onto: over an edge whose drop falls onto another
-- level of the hall (zone edges with `under`), from the level the edge lies on (`on`: the levels
-- the player is on), from the side the edge's floor is on to the other; or nil.
function logic.fellOnto(zone, on, px, py, x, y)
    local ix = zone._index
    if px == nil then
        return nil
    end
    for _, e in ipairs(ix.edges) do
        if e.under and onLevel(e, on) then
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
