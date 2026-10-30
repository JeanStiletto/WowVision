-- Surroundings logic: drop edges (of the cities' floors, structures, buildings; a drop into a
-- liquid is one like any other), the floor pieces they lie on, and the ways out of the liquids.
--
-- An edge on a floor piece (a gate's wall-walk, a bridge deck over a bank, a landing) warns only
-- while the player is on that piece. The game gives no height, so the player's floor is followed: on the walk
-- graph's surfaces (tracker.lua) where the data has them (every zone but the Deeprun Tram); else, the older piece
-- tracker below, from the ground: it changes only at a join crossed, at a drop edge crossed, or when the floor is
-- no longer under them (updateFloor); walking under a piece never counts.

local logic = WowVision.surroundingsLogic

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
    for _, d in ipairs(logic.cellOffsets(zone.cols)) do
        local here = ix.floorCells[key + d]
        if here ~= nil and here[floor] ~= nil then
            return true
        end
    end
    return false
end

-- Did the step from (px, py) to (x, y) cross the join `j` (a point on the line where two floors
-- meet, with the direction from its piece a into b): within ACCESS_REACH beside the point, from
-- a's side to b's (1), from b's to a's (-1), or not (nil); a step reaching CROSS_MARGIN beyond
-- the join's line counts. The second result: a crossing pending (1 or -1), a step that passed the
-- join's line but ended within the margin beyond it; with `pending` (that result of the last look)
-- the next step reaching the margin counts (the module looks every few yards: one look ended
-- 0.4 yd past the deck's join at the zeppelin tower, the next began past the join, and the
-- stairs were never entered, walk 2026-10-06 09:56), and a step staying within the margin keeps
-- it pending. Strafing along the join within the margin never counts. A join without a
-- direction counts either way when the step passes within reach of it.
local function crossed(j, px, py, x, y, pending)
    if j.angle == nil then
        return segmentDistance(j.x, j.y, px, py, x, y) <= logic.ACCESS_REACH and 0 or nil
    end
    local vx, vy = logic.compassVector(j.angle)
    local before = (px - j.x) * vx + (py - j.y) * vy
    local after = (x - j.x) * vx + (y - j.y) * vy
    local margin = logic.CROSS_MARGIN
    -- where the step passes the line `line` yd beyond the join: within reach beside the point?
    local function beside(line)
        local t = (before - line) / (before - after)
        local mx, my = px + (x - px) * t, py + (y - py) * t
        return math.abs((mx - j.x) * vy - (my - j.y) * vx) <= logic.ACCESS_REACH
    end
    if before ~= after then
        if before <= 0 and after > margin then
            return beside(0) and 1 or nil
        elseif before >= 0 and after < -margin then
            return beside(0) and -1 or nil
        elseif pending == 1 and before > 0 and before <= margin and after > margin then
            return beside(margin) and 1 or nil
        elseif pending == -1 and before < 0 and before >= -margin and after < -margin then
            return beside(-margin) and -1 or nil
        end
        if before <= 0 and after > 0 and after <= margin then
            return nil, beside(0) and 1 or nil
        elseif before >= 0 and after < 0 and after >= -margin then
            return nil, beside(0) and -1 or nil
        end
    end
    if pending == 1 and after > 0 and after <= margin then
        return nil, 1
    elseif pending == -1 and after < 0 and after >= -margin then
        return nil, -1
    end
    return nil
end

-- How far (x, y) lies beyond a free end of a line floor's stretch, along it (0 alongside it, or
-- beyond an end another stretch of its piece goes on from): a climb's line is drawn out to its
-- floor's ends, so one steps onto it only alongside its line (standing 1.4 yd past the end of a
-- small bridge by the mausoleum's lift shaft put the player back on the bridge, the shaft's rim
-- counted as a fall beside it, and stepping away put them on the canal floor 110 yd below,
-- replay 2026-10-10)
local function pastEnd(lane, x, y)
    local dx, dy = lane.x2 - lane.x1, lane.y2 - lane.y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then
        return 0
    end
    local t = ((x - lane.x1) * dx + (y - lane.y1) * dy) / len
    if t < 0 and lane.free1 then
        return -t
    elseif t > len and lane.free2 then
        return t - len
    end
    return 0
end

-- Is the player on `floor` by its own lines (a ramp's or stairs' piece, zone.lineFloors): within
-- the leave distance of one of the stretches tied to it, as a way counts (user 2026-10-16: a climb
-- is a way like any other)? nil for a piece without lines of its own.
function logic.onOwnLines(zone, x, y, floor)
    local ix = zone._index
    if not (ix.lineFloors and ix.lineFloors[floor]) then
        return nil
    end
    local r, c = logic.cellOf(zone, x, y)
    for _, lane in ipairs(ix.lanes[r * zone.cols + c] or {}) do
        if lane.piece == floor then
            local _px, _py, d = logic.segmentPoint(x, y, lane.x1, lane.y1, lane.x2, lane.y2)
            local _enter, leave = logic.laneWidths(lane, x, y)
            if d <= leave then
                return true
            end
        end
    end
    return false
end

-- The piece with lines of its own the player steps onto from `floor` at (x, y): within the enter
-- distance of one of its stretches, alongside it (not past its line's ends: pastEnd), where it is
-- joined to `floor` (within JOINED_HERE of a join of
-- the two: the bay under the griffon ramp's upper half is no step onto it), the nearest; nil when
-- none. A climb counts from its enter distance as a way does (user 2026-10-16): coming down the
-- griffon ramp from its platform crossed none of their joins in their direction, and the module
-- kept the player on the platform, its rim warned 9 yd down beside the ramp (replay 2026-10-01).
function logic.ontoOwnLines(zone, x, y, floor)
    local ix = zone._index
    local joined = ix.joined[floor]
    if not (joined and ix.lineFloors) then
        return nil
    end
    local r, c = logic.cellOf(zone, x, y)
    local best, bd = nil, nil
    for _, lane in ipairs(ix.lanes[r * zone.cols + c] or {}) do
        local p = lane.piece
        if p ~= floor and ix.lineFloors[p] and joined[p] then
            local _px, _py, d = logic.segmentPoint(x, y, lane.x1, lane.y1, lane.x2, lane.y2)
            local enter = logic.laneWidths(lane, x, y)
            if d <= enter and (bd == nil or d < bd) and pastEnd(lane, x, y) == 0
                    and logic.joinedHere(zone, floor, p, x, y) then
                best, bd = p, d
            end
        end
    end
    return best
end

-- Updates the floor piece the player is on (zone._index.floor; 0 the ground: the one rule for
-- every floor over or under another, user 2026-10-05). It changes only (1) at a drop edge of the
-- floor crossed, onto the piece the drop lands on; (2) at a join crossed in its direction, from
-- the floor into the piece it meets there (a join from a building's door counts while `cameOut`,
-- within ROOMS_REACH); (3) when the floor is no longer under the player: then the piece here
-- that the floor joins or drops onto here (within JOINED_HERE: a join a kilometre away says
-- nothing about this spot; the Brill tavern's upper floor took a player downstairs, replay
-- 2026-10-08), else the only piece here where the ground is absent, else the ground. `px, py`: the position at the last look; `blocked`: the player pushes against
-- something (the wall detection's "blocked"): no fall then (pressing against the zeppelin tower's
-- railing ends just past an edge's rim, and the module dropped the player from the first flight
-- to the deck on a bump, walk 2026-10-06 11:21; a real fall is no push). `swimming` (true,
-- false, or nil while in the air): a liquid's surface is a floor piece, and swimming is the one
-- height the game tells (user 2026-10-08): swimming, the player is on a liquid's piece (the one
-- the floor joins or drops onto here, else the only one here); not swimming, on none (the floor
-- the liquid joins here, else the ground). Returns the floor and whether it changed.
function logic.updateFloor(zone, x, y, cameOut, px, py, blocked, swimming)
    -- the walk-graph tracker where the data has the layer's surfaces (format 5; tracker.lua): the joins, the
    -- drop edges and the lines decide nothing about the floor then, the surfaces do
    if zone.surf and logic.tracker then
        return logic.tracker.update(zone, x, y, swimming)
    end
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    local key = r * zone.cols + c
    local was = ix.floor or 0
    local floor = was
    local fell = px and not blocked and logic.fellOnto(zone, floor, px, py, x, y)
    -- on a piece with lines of its own its lines decide whether the player is still on it (as a
    -- bridge's next to a drop): a drop edge crossed within them says only where the player lands
    -- once beyond them (the griffon ramp's rim, its points 2 yd inside the ramp on the 2 yd raster,
    -- dropped the player off it walking down 1.5 yd beside its line, replay 2026-10-01 00:27)
    if fell and logic.onOwnLines(zone, x, y, floor) then
        ix.fallBeside = { piece = fell, x = x, y = y }
        fell = nil
    end
    if ix.fallBeside and (logic.dist(x, y, ix.fallBeside.x, ix.fallBeside.y) > logic.JOINED_HERE) then
        ix.fallBeside = nil
    end
    -- the crossings pending from the last look (crossed), and this look's
    local pendingBefore, pendingNow = ix.pendingJoins or {}, {}
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
                        local way, pending = crossed(j, px, py, x, y, pendingBefore[j])
                        if pending and (pending > 0) == (j.a == floor) then
                            pendingNow[j] = pending
                        end
                        if way and ((way == 0 and j.a == floor) or (way ~= 0 and (way > 0) == (j.a == floor))) then
                            other = j.a == floor and j.b or j.a
                            d = logic.dist(j.x, j.y, x, y)
                            -- onto a piece with lines of its own only within them, as a way
                            -- counts (a join counts 2.5 yd beside its point: passing a ramp's
                            -- foot 3.7 yd off its line put the player on it and the line took
                            -- them off at the next look, tour of the Undercity's island)
                            if logic.onOwnLines(zone, x, y, other) == false then
                                other, d = nil, nil
                            end
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
    -- cells its piece has); otherwise the floor must be under the player, and a piece with lines
    -- of its own is left beyond them, as a way is (a step off a ramp's side where its floor meets
    -- the floor beside: nothing to cross there, and its cells are 4 yd with the 8 around counted,
    -- so the griffon ramp kept the player 7 yd along its side, bug 41); that counts as falling off
    -- it (logic.belowClimb: its foot is guided to again)
    -- (and, as a way, a piece with lines of its own is entered from a floor joined to it within
    -- their enter distance)
    if floor == was and px and not fell then
        floor = logic.ontoOwnLines(zone, x, y, floor) or floor
    end
    local offLines = floor == was and logic.onOwnLines(zone, x, y, floor) == false
    if floor == was and (offLines or not logic.floorHere(zone, key, floor)) then
        local here = ix.floorCells[key]
        local pick, only, count = nil, nil, 0
        for p in pairs(here or {}) do
            -- (on foot never into a liquid: swimming is the one height the game tells; the
            -- Undercity's canal walk under a bridge ended in the canal beside it, and the player
            -- walking up the bridge was held in the water, trial replay 2026-10-17)
            if (p ~= floor or not offLines) and not (swimming == false and ix.liquids[p] ~= nil) then
                only, count = p, count + 1
                if logic.joinedHere(zone, floor, p, x, y) and (pick == nil or p < pick) then
                    pick = p
                end
            end
        end
        if pick == nil and count == 1 and ix.noGround[key] then
            pick = only
        end
        -- on foot with nothing joined here: still on the floor one was on while it lies in a cell
        -- next to this one (its rim: a step beyond its last cell), not the ground absent here
        if pick == nil and not offLines and swimming == false and was ~= 0 and ix.liquids[was] == nil
            and ix.noGround[key] then
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if logic.floorHere(zone, (r + dr) * zone.cols + c + dc, was) then
                        pick = was
                    end
                end
            end
        end
        if offLines and ix.fallBeside then
            -- beyond its lines past a drop edge crossed: where that drop lands
            pick = ix.fallBeside.piece
        elseif offLines and pick == nil and ix.noGround[key] then
            -- beside its lines with no floor there but its own: still on it
            pick = was
        end
        floor = pick or 0
    end
    if swimming ~= nil and (swimming == true) ~= (ix.liquids[floor] ~= nil) then
        floor = logic.swimFloor(zone, key, floor, swimming, x, y) or floor
    end
    -- the liquid the game had the player swim in (swimFloor: standing up in it)
    if swimming == true and ix.liquids[floor] ~= nil then
        ix.swumIn = floor
    elseif ix.liquids[floor] == nil then
        ix.swumIn = nil
    end
    ix.floor = floor
    -- a crossing pending leads off the floor it began on only
    ix.pendingJoins = floor == was and pendingNow or {}
    -- the floor the player came onto this one from (the guidance on a flight: logic.footTarget)
    if floor ~= was then
        ix.fallBeside = nil
        ix.cameFrom = was
        -- and the floor fallen or stepped off from, while on the one fallen onto (logic.belowClimb)
        ix.fellFrom = (fell or offLines) and was or nil
    end
    return floor, floor ~= was
end

-- The floor piece the swimming state puts the player on in the cell `key` (else the 8 around),
-- coming from `floor` at (x, y): swimming, a liquid's piece there that `floor` joins or drops onto
-- here, else the only one there (swimming tells the height: one liquid here is the one swum in;
-- nil where several); not swimming, a floor there that the liquid `floor` joins here, else, in a
-- liquid the player swam in, nil (still in it), in another the ground where it is there; nil where
-- none. Standing tells no height: the only floor in the cell is no way out of a liquid (out of
-- the Ruins of Lordaeron's courtyard canal it was the Undercity's canal walk 116 yd under it, walk
-- 2026-10-07 23:44).
function logic.swimFloor(zone, key, floor, swimming, x, y)
    local ix = zone._index
    local cols = zone.cols
    local r, c = math.floor(key / cols), key % cols
    local found, list = {}, {}
    local function add(k)
        for p in pairs(ix.floorCells[k] or {}) do
            if (ix.liquids[p] ~= nil) == swimming and not found[p] then
                found[p] = true
                list[#list + 1] = p
            end
        end
    end
    add(key)
    if #list == 0 then
        for _, d in ipairs(logic.cellOffsets(zone.cols)) do
            add(key + d)
        end
    end
    if not swimming and not ix.noGround[key] then
        found[0] = true
        list[#list + 1] = 0
    end
    table.sort(list)
    for _, p in ipairs(list) do
        if logic.joinedHere(zone, floor, p, x, y) or logic.landsOnHere(zone, floor, p, x, y) then
            return p
        end
    end
    -- standing up in a liquid split into pieces at one height (walls over the water cut it): a
    -- floor joined here to a piece of it joined to this one (the Ruins of Lordaeron's sewer, walk
    -- 2026-10-14 10:32: the water stood up in met the floor beside it only behind its walls)
    if not swimming and ix.liquids[floor] ~= nil then
        for _, p in ipairs(list) do
            if p ~= 0 then
                for q in pairs(ix.liquids) do
                    if q ~= floor and logic.joinedHere(zone, floor, q, x, y) and logic.joinedHere(zone, q, p, x, y) then
                        return p
                    end
                end
            end
        end
    end
    if swimming and #list == 1 then
        return list[1]
    end
    -- standing up where no floor joins the liquid the player swam in (a ledge at the foot of a
    -- wall, at the water's level): still in it, not on the ground's floor up on the walk over it
    -- (the slime canal walk 5 to 9 yd up and its drops into the canal, walk 2026-10-15 07:15);
    -- on foot on a liquid never swum in (a fall the game did not make), where the liquid has no
    -- place of its own (a cell kept for its record only), or in the halls (zone.parent: the
    -- Undercity's canals, about as deep as one stands, where the halls took turns with the
    -- ground and said the canal again and again, replay of the 2026-10-12 16:50 walk), the ground
    if not swimming and ix.swumIn == floor and zone.parent == nil then
        -- (its place as on it: the cell's, around it, or a piece joined to it here, valueAtCell)
        local was = ix.floor
        ix.floor = floor
        local v = logic.valueAtCell(zone, r, c)
        ix.floor = was
        if v ~= 0 then
            return nil
        end
    end
    return not swimming and found[0] and 0 or nil
end

-- Does a drop edge of `floor` land on `piece` within JOINED_HERE of (x, y)?
function logic.landsOnHere(zone, floor, piece, x, y)
    local reach = logic.JOINED_HERE
    for _, e in ipairs(zone._index.edges) do
        local b = e.box
        if e.floor == floor and e.under == piece and x >= b[1] - reach and x <= b[2] + reach
            and y >= b[3] - reach and y <= b[4] + reach then
            return true
        end
    end
    return false
end

-- Sets the floor piece the player is on (0 the ground); every lookup follows it.
function logic.setFloor(zone, floor)
    zone._index.floor = floor or 0
    if logic.tracker then
        logic.tracker.reset(zone)
    end
    zone._index.fallBeside = nil
    zone._index.pendingJoins = {}
    zone._index.cameFrom = nil
    zone._index.fellFrom = nil
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
    local r0, c0 = logic.cellOf(zone, x, y)
    local key = r0 * zone.cols + c0
    local found = nil
    for _, d in ipairs(logic.cellOffsets(zone.cols)) do
        for p, v in pairs(ix.floorCells[key + d] or {}) do
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
    return found
end

function logic.edge(zone, i)
    return zone._index.edges[i]
end

-- Whether edge `i` is looked at from (x, y) at all: not skipped, on the floor piece the player is
-- on (zone._index.floor: an edge of the ground (floor 0) counts only on the ground, an edge of a
-- piece only up on it; down in the moat the walkways' edges are no drops), in one of the rooms
-- the player may be in (`rooms`, the indoor layers: an edge inside warns only in the room
-- its floor belongs to; nil: every room), and its box within `reach` yards.
local function edgeCounts(zone, e, i, x, y, reach, rooms, skip)
    local floor = zone._index.floor or 0
    if (skip and skip[i]) or (e.floor ~= floor and not (floor ~= 0 and logic.joinedPieces(zone, floor, e.floor)))
        or (rooms and e.piece ~= 0 and not rooms[e.piece]) then
        return false
    end
    local b = e.box
    return x >= b[1] - reach and x <= b[2] + reach and y >= b[3] - reach and y <= b[4] + reach
end

-- yd from a join of the player's floor with another piece within which that piece's drop edge
-- points count on the player's floor too: where two pieces meet their rims run on into each other,
-- and the rim of one is a yard or two (too short for an edge of its own, it went to the other's
-- record): the zeppelin tower's landing beside the gap at the top of the first flight had none,
-- the user stood on the landing and walked into the gap unwarned (walk 2026-10-06 11:19)
logic.JOIN_EDGE_REACH = 3.0

-- Are pieces a and b joined (a floor and another piece)?
function logic.joinedPieces(zone, a, b)
    local joined = zone._index.joined[a]
    return joined ~= nil and joined[b] == true
end

-- Are pieces a and b joined within JOINED_HERE of (x, y)? What a floor leads to at this spot,
-- when the player's floor must be found again (updateFloor, swimFloor, valueAtCell).
logic.JOINED_HERE = 6.0
function logic.joinedHere(zone, a, b, x, y)
    if not logic.joinedPieces(zone, a, b) then
        return false
    end
    local ix = zone._index
    local reach = logic.JOINED_HERE
    local r, c = logic.cellOf(zone, x, y)
    local n = math.ceil(reach / zone.cell)
    for dr = -n, n do
        for dc = -n, n do
            for _, j in ipairs(ix.joinAt[(r + dr) * zone.cols + c + dc] or {}) do
                if ((j.a == a and j.b == b) or (j.a == b and j.b == a)) and logic.dist(j.x, j.y, x, y) <= reach then
                    return true
                end
            end
        end
    end
    return false
end

-- Does the point (qx, qy) of edge `e` count on the floor `floor`: every point of an edge of that
-- floor, and up on a piece (not the ground: it joins the foot of every stairs, and
-- their side drops came as drops ahead from the street below, replay 2026-10-06) a point of an
-- edge of a piece joined to it within JOIN_EDGE_REACH of one of their joins.
local function pointCounts(zone, e, floor, qx, qy)
    if e.floor == floor then
        return true
    elseif floor == 0 then
        return false
    end
    local pts = zone._index.joinPoints[floor]
    pts = pts and pts[e.floor]
    if pts == nil then
        return false
    end
    local reach2 = logic.JOIN_EDGE_REACH * logic.JOIN_EDGE_REACH
    for k = 1, #pts - 1, 2 do
        if logic.dist2(qx, qy, pts[k], pts[k + 1]) <= reach2 then
            return true
        end
    end
    return false
end

-- Does the player stand in front of the edge point (q), on the structure's side, not beyond it?
local function inFront(qx, qy, x, y, fx, fy)
    return (x - qx) * fx + (y - qy) * fy <= 0.5
end


logic.STAIR_FACING = 0.5 -- cosine: a stairs' edge beside the player warns only facing within 60 degrees of its drop

-- Is edge `i` a stairs' edge: its floor is a staircase room's, or a floor piece whose place is
-- stairs (cached on the edge)?
function logic.isStairEdge(zone, i)
    local e = zone._index.edges[i]
    if e.stair == nil then
        local room = e.piece and e.piece ~= 0 and zone._index.rooms and zone._index.rooms[e.piece]
        local stair = room and room.kind == "stairs" or false
        if not stair and (e.floor or 0) ~= 0 and #e.points >= 2 then
            local r, c = logic.cellOf(zone, e.points[1], e.points[2])
            stair = logic.kindOf(zone, logic.valueOfFloor(zone, r, c, e.floor)) == "stairs"
        end
        e.stair = stair
    end
    return e.stair
end

-- The drop edge to warn about within `reach` yards: one the player stands in front of, on the
-- structure's floor; the edge index and distance. With `facing`, an edge ahead (within 90 degrees
-- of the view) wins over a nearer one beside or behind. A stairs' edge (isStairEdge: the inner rim
-- of a winding stair) counts only while the player faces within 60 degrees of its drop (user
-- 2026-10-12: walking round Ironforge's east stairs the stairwell's rim warned at every pass; a path
-- into it still warns, edgeAhead). `rooms`: the rooms the player may be in (indoors), nil outdoors;
-- `skip`: a set of edge indexes left out (warned already).
function logic.nearestEdge(zone, x, y, reach, rooms, facing, skip)
    local ix = zone._index
    local floor = ix.floor or 0
    local r, c = logic.cellOf(zone, x, y)
    local vx, vy = nil, nil
    if facing then
        vx, vy = math.cos(facing), math.sin(facing)
    end
    local best, bestD, ahead, aheadD = nil, reach, nil, reach
    for i, e in ipairs(ix.edges) do
        local fx, fy = logic.compassVector(e.facing)
        if edgeCounts(zone, e, i, x, y, reach, rooms, skip)
            and not (logic.isStairEdge(zone, i) and not (vx and fx * vx + fy * vy >= logic.STAIR_FACING)) then
            local p = e.points
            for k = 1, #p - 1, 2 do
                local qx, qy = p[k], p[k + 1]
                local d = logic.dist(x, y, qx, qy)
                if (d <= bestD or d <= aheadD) and inFront(qx, qy, x, y, fx, fy)
                    and pointCounts(zone, e, floor, qx, qy)
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
    local floor = ix.floor or 0
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
                    and inFront(p[k], p[k + 1], x, y, fx, fy) and pointCounts(zone, e, floor, p[k], p[k + 1])
                    and logic.nearCell(zone, ix.struct, r, c, e.struct) then
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
        if e.under ~= nil and (e.floor == floor or (floor ~= 0 and logic.joinedPieces(zone, floor, e.floor))) then
            local b = e.box
            local reach = logic.FALL_REACH
            if x >= b[1] - reach and x <= b[2] + reach and y >= b[3] - reach and y <= b[4] + reach then
                local fx, fy = logic.compassVector(e.facing)
                local p = e.points
                for k = 1, #p - 1, 2 do
                    local qx, qy = p[k], p[k + 1]
                    if logic.dist(x, y, qx, qy) <= reach and inFront(qx, qy, px, py, fx, fy)
                        and not inFront(qx, qy, x, y, fx, fy) and pointCounts(zone, e, floor, qx, qy) then
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
