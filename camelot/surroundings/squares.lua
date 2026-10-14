-- Surroundings logic: what lies around a place with no direction of its own (a city square, a
-- hall, a street without a direction): the things along its border (streets, other squares, roads,
-- bridges, canal walks, water, canals, drops) and the building entrances on it, each said with its
-- direction from the player on a north-up map. The place's cells are found by a flood fill from
-- the player's cell (one region per square, cached), so nothing is cut up: a big square says the
-- nearest things on entry and the others when the player comes close to them. Terrain under a
-- city (open land, hillside, forest) is no landmark. Outdoors elsewhere: the cliffs and water near.

local logic = WowVision.surroundingsLogic

logic.MOUTH_MIN = 2 -- border cells at least that make a thing worth saying (about 8 yd)
logic.MOUTH_GAP = 2 -- cells; border pieces of one thing closer than this are one mouth
logic.REGION_MAX = 20000 -- cells; a flood fill stops there
logic.LEADS_MAX = 5000 -- cells a way is followed to see where it leads; farther counts as leading on
logic.BEGIN_MAX = 24 -- yd; a way meeting the square along a longer border runs beside it (Stormwind's
-- 78 squares, 2026-09-30: 21 real openings of streets, stairs, ramps and quays span 16 to 24 yd,
-- the lane through the gate 18; the ways along a side start above 24)
logic.ONWARD_CELLS = 24 -- cells of a way from its opening whose axis says where it leads on
logic.ITEM_DIRS = 2 -- directions per thing while walking (a street meeting a square in five places)
logic.HERE = 2 -- yd; closer than this a thing is "here", without a direction
-- degrees between a climb's rise and the step from the square onto it: within this it goes up from
-- the square, beyond 180 less this down; between, it runs along the square's side (no word)
logic.RISE_ALONG = 60
logic.DOOR_NEAR = 3 -- cells; a doorway this close to a border cell of a room's opening is the opening

-- Does a cell value belong to a place with an edge (logic.EDGED: a square, hall or platform), which
-- says what its edge leads to (texts.lua spotBody)? A street without a direction (a piece without
-- centre line) is a way like a road without one (one rule for roads and streets, user 2026-09-30).
function logic.hasEdge(zone, value)
    if value == nil or value == 0 then
        return false
    end
    return logic.EDGED[logic.kindOf(zone, value)] or false
end

-- The thing a border cell shows: label and class ("way" with the place's label; "water", "cliff
-- edge", "canal" (a city's water lying there, a liquid piece of its own), which are their own
-- label), or nil; and for a way of a structure the player is
-- not on (`here`: the structure of the region's place, or nil) its label as said, with the
-- structure's name (logic.describe: "ramp of pier of Stormwind Harbor" from the dock beside it).
local function borderThing(zone, value, key, here)
    if value ~= 0 then
        local p = logic.place(zone, logic.placeOf(value))
        local kind = p and p.kind
        if logic.WAYS[kind] then
            local said = logic.spokenName(zone, p.label)
            local spoken = said ~= p.label and said or nil
            if p.of and p.of ~= here then
                spoken = string.format(zone.ofTemplate or "%s of %s", said, p.of)
            end
            return p.label, "way", spoken
        elseif logic.WATER[kind] then
            return "water", "water"
        elseif logic.DROPS[kind] then
            return "cliff edge", "cliff edge"
        end
        return nil
    end
    if logic.liquidIn(zone, key) == 2 then
        return "canal", "canal"
    end
    return nil
end

-- Does the climb in a border cell (nr, nc) go up or down from the region's `cells` beside it: "up"
-- where a step from one of them onto it goes up (its foot; a corner cell has two square cells
-- beside it, one along the climb's side: the foot of the stairs to Champion's Hall), else "down",
-- else "along" (it runs along the square's side); nil for no climb. From the climb's own rise in
-- the data (user's walk 2026-10-03 08:06: on a landing between two flights "stairs at 1" did not
-- say which stairs, nor whether up or down; the user wants "up" or "down" said).
local function riseFrom(zone, cells, value, nr, nc)
    local up = value ~= 0 and logic.riseOf(zone, value)
    if not up then
        return nil
    end
    local rise = "along"
    for _, s in ipairs(logic.STEPS) do
        local r, c = nr + s[1], nc + s[2]
        if cells[r * zone.cols + c] then
            local gap = logic.angleGap(up, logic.bearingOf((r - nr) * zone.cell, (c - nc) * zone.cell))
            if gap <= logic.RISE_ALONG then
                return "up"
            elseif gap >= 180 - logic.RISE_ALONG then
                rise = "down"
            end
        end
    end
    return rise
end

-- The border cells of the region grouped into mouths, one per stretch of border of each thing and,
-- for a ramp or stairs, of each way it goes from the square (up, down; a stretch running along the
-- square's side only where the climb goes neither up nor down from it, without a word: the long
-- stairs beside the landing by the auction house said "stairs to the west" beside "stairs up to the
-- north"): {label, class, rise, points {x, y, ...}, cells {border r, c, square r, c}}.
local function findMouths(zone, cells, list, floors, own)
    local byLabel, order, seen, along, rising = {}, {}, {}, {}, {}
    local here = logic.ownerOfPlace(zone, own)
    floors = floors or { [zone._index.floor or 0] = true }
    for i = 1, #list - 1, 2 do
        local r, c = list[i], list[i + 1]
        for _, s in ipairs(logic.STEPS) do
            local nr, nc = r + s[1], c + s[2]
            local key = nr * zone.cols + nc
            local pair = (r * zone.cols + c) * zone.rows * zone.cols + key
            local noContact = zone._index.noContact[pair]
            if not cells[key] and not seen[key] and not noContact and logic.inGrid(zone, nr, nc) then
                seen[key] = true
                -- what lies there on the player's floor: its value where the floor goes on into
                -- the cell, else the piece the floor joins there (the stairs down from a landing;
                -- the common room 7 yd below the landing is no neighbour of it)
                local value, piece = logic.mouthValue(zone, nr, nc, key, floors, r * zone.cols + c, own)
                -- the square's own place beyond a join (its part on a raised strip the flood did
                -- not reach) is no neighbour
                if own and value ~= 0 and logic.placeOf(value) == own then
                    value = 0
                end
                local label, class, spoken = borderThing(zone, value, key, here)
                local rise = label and riseFrom(zone, cells, value, nr, nc)
                if rise == "along" then
                    along[#along + 1] = { label = label, class = class, spoken = spoken, value = value, piece = piece, cell = { nr, nc, r, c } }
                elseif label then
                    if rise then
                        rising[value] = true
                    end
                    -- a climb's way up or down per climb (two stairs going down from a landing)
                    local group = label .. "|" .. (rise and rise .. value or "")
                    if byLabel[group] == nil then
                        byLabel[group] = { label = label, class = class, spoken = spoken, rise = rise, value = value, piece = piece, cells = {} }
                        order[#order + 1] = group
                    end
                    -- the border cell and the square's cell beside it (for the way on)
                    table.insert(byLabel[group].cells, { nr, nc, r, c })
                end
            end
        end
    end
    -- a climb's stretches along the side, where that climb (its cell value) goes nowhere up or down
    for _, a in ipairs(along) do
        if not rising[a.value] then
            local group = byLabel[a.label .. "|"]
            if group == nil then
                group = { label = a.label, class = a.class, spoken = a.spoken, value = a.value, piece = a.piece, cells = {} }
                byLabel[a.label .. "|"] = group
                order[#order + 1] = a.label .. "|"
            end
            table.insert(group.cells, a.cell)
        end
    end
    local mouths = {}
    for _, key in ipairs(order) do
        local group = byLabel[key]
        local todo, done = group.cells, {}
        for i = 1, #todo do
            if not done[i] then
                done[i] = true
                local members, queue = { todo[i] }, { i }
                while #queue > 0 do
                    local a = todo[table.remove(queue)]
                    for j = 1, #todo do
                        if not done[j] and math.abs(todo[j][1] - a[1]) <= logic.MOUTH_GAP
                            and math.abs(todo[j][2] - a[2]) <= logic.MOUTH_GAP then
                            done[j] = true
                            members[#members + 1] = todo[j]
                            queue[#queue + 1] = j
                        end
                    end
                end
                -- a climb going up or down from the square counts from one border cell: a ramp
                -- is narrow, and a raised part of the square beside its foot takes its other cells
                if #members >= (zone.mouthMin or logic.MOUTH_MIN) or (group.rise and #members >= 1) then
                    local points = {}
                    for _, m in ipairs(members) do
                        local px, py = logic.cellCentre(zone, m[1], m[2])
                        points[#points + 1] = px
                        points[#points + 1] = py
                    end
                    mouths[#mouths + 1] = { label = group.label, class = group.class, rise = group.rise, points = points, cells = members,
                        value = group.value, piece = group.piece, spoken = group.spoken }
                end
            end
        end
    end
    return mouths
end

-- In a building layer a room's opening into another room is its doorway, not the border the grid
-- shows: the grid cuts no walls between rooms, so the Brill tavern kitchen's opening ran along the
-- common room's whole north wall and "kitchen at 12" pointed at the wall 5 yd beside the door,
-- and the porch beyond the entrance room was a neighbour through a wall (user's walk 2026-10-06
-- 04:16). The opening keeps its border cells (the way on is followed from them) and takes the
-- doorways within DOOR_NEAR of them as its points; two rooms of one building with no doorway
-- between them are no neighbours. A climb's opening stays the grid's (its foot is guided to as a
-- climb), and so does a place that is no room (a hall cut into pieces).
local function doorMouths(zone, region)
    local out = {}
    for _, m in ipairs(region.mouths) do
        local keep = true
        if m.class == "way" and m.cells and not logic.CLIMBS[logic.kindOf(zone, m.value)] then
            local doors, rooms = logic.doorsBetween(zone, region.label, m.label)
            if rooms then
                local points, reach = {}, (logic.DOOR_NEAR * zone.cell) ^ 2
                for _, door in ipairs(doors) do
                    local dx, dy = logic.doorWorld(zone, door)
                    local near = false
                    for _, cell in ipairs(m.cells) do
                        local cx, cy = logic.cellCentre(zone, cell[1], cell[2])
                        if dx and logic.dist2(dx, dy, cx, cy) <= reach then
                            near = true
                            break
                        end
                    end
                    if near then
                        points[#points + 1] = dx
                        points[#points + 1] = dy
                    end
                end
                if #points == 0 then
                    keep = false
                else
                    m.points = points
                end
            end
        end
        if keep then
            out[#out + 1] = m
        end
    end
    return out
end

-- The region of the around-place at a position: {value, label, cells (set of keys), mouths}, where
-- the building entrances on the square or at its edge are mouths too (class "entrance", labelled
-- with the building); nil where the place is no around-place. Cached per cell.
-- The value a neighbouring cell shows from the player's floor piece: the floor's own value where
-- the floor goes on into the cell; water and a cliff's edge from any floor (the harbour's quay
-- sees the water beside it); else the value of a piece the floor joins at that cell or at the
-- square's cell beside it (the join points lie on the border); 0 when none of these: the cell is
-- no neighbour on this floor (the common room 7 yd below the landing).
function logic.mouthValue(zone, r, c, key, floors, fromKey, own)
    -- of the region's floors here, the first that shows another place than the region's own (a
    -- raised strip of the square runs on beside the ramp's foot: the ramp is the neighbour)
    local same, samePiece = nil, nil
    for f in pairs(floors) do
        if logic.floorHere(zone, key, f) then
            local v = logic.valueOfFloor(zone, r, c, f)
            if v ~= 0 and logic.placeOf(v) ~= own then
                return v, f
            end
            if same == nil then
                same, samePiece = v, f
            end
        end
    end
    local painted = logic.paintedAtCell(zone, r, c)
    local kind = painted ~= 0 and logic.kindOf(zone, painted) or nil
    if painted == 0 or logic.WATER[kind] or logic.DROPS[kind] then
        return painted
    end
    local joinAt = zone._index.joinAt
    for dr = -1, 1 do
        for dc = -1, 1 do
            for _, j in ipairs(joinAt[(r + dr) * zone.cols + c + dc] or {}) do
                local other = floors[j.a] and j.b or floors[j.b] and j.a or nil
                if other and other >= 0 then
                    local v = logic.valueOfFloor(zone, r, c, other)
                    if v ~= 0 and logic.placeOf(v) ~= own then
                        return v, other
                    end
                end
            end
        end
    end
    return same or 0, samePiece
end

-- A cell's value as seen from a mouth: on the floor piece the mouth's thing lies on (a ramp beside
-- the square is a piece of its own; from the square's floor its cells show the square), else the
-- player's floor's.
function logic.mouthCellValue(zone, mouth, r, c)
    if mouth.piece then
        local v = logic.valueOfFloor(zone, r, c, mouth.piece)
        if v ~= 0 then
            return v
        end
    end
    return logic.valueAtCell(zone, r, c)
end

-- The floor pieces a region spreads over: the player's, and every piece joined to one of them
-- whose value at the join's cell is the region's (a square cut into ground and a raised strip
-- along its canal is one square). Returns whether the cell (r, c) joins the region, adding the
-- piece it reaches through.
local function regionJoins(zone, r, c, key, floors, value)
    for f in pairs(floors) do
        if logic.floorHere(zone, key, f) and logic.valueOfFloor(zone, r, c, f) == value then
            return true
        end
    end
    -- a join in the cell or one of its neighbours (the join points lie on the border between
    -- the two floors' cells, on either side)
    local joinAt = zone._index.joinAt
    for dr = -1, 1 do
        for dc = -1, 1 do
            for _, j in ipairs(joinAt[(r + dr) * zone.cols + c + dc] or {}) do
                local other = floors[j.a] and j.b or floors[j.b] and j.a or nil
                if other and other >= 0 and logic.valueOfFloor(zone, r, c, other) == value then
                    floors[other] = true
                    return true
                end
            end
        end
    end
    return false
end

-- A ramp or stairs joined to the region's floor at a point on the region is a mouth there too,
-- unless a mouth of that name is found already: a flight rising from the middle of a tower's deck
-- lies over the deck's own cells, and the border never shows it (Alt-L on the zeppelin tower's deck
-- named the stairs down, not the spiral up; user 2026-10-06).
local function joinedClimbMouths(zone, region, cells, floors)
    local have = {}
    for _, m in ipairs(region.mouths) do
        have[m.label] = true
    end
    local ix, cols = zone._index, zone.cols
    for f in pairs(floors) do
        for other, pts in pairs(ix.joinPoints[f] or {}) do
            if not floors[other] then
                for k = 1, #pts - 1, 2 do
                    local jx, jy = pts[k], pts[k + 1]
                    local r, c = logic.cellOf(zone, jx, jy)
                    if cells[r * cols + c] then
                        -- the climb's value at the join: in its cell, else one of the 8 around
                        local v, vr, vc = 0, r, c
                        for dr = -1, 1 do
                            for dc = -1, 1 do
                                if v == 0 then
                                    local w = logic.valueOfFloor(zone, r + dr, c + dc, other)
                                    if w ~= 0 then
                                        v, vr, vc = w, r + dr, c + dc
                                    end
                                end
                            end
                        end
                        if v ~= 0 and logic.CLIMBS[logic.kindOf(zone, v)] then
                            local label, _class, spoken = borderThing(zone, v, vr * cols + vc, logic.ownerOf(zone, region.value))
                            if label and not have[label] then
                                have[label] = true
                                region.mouths[#region.mouths + 1] = { label = label, class = "way", points = { jx, jy },
                                    cells = { { vr, vc, r, c } }, value = v, piece = other, spoken = spoken }
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

function logic.regionAt(zone, x, y)
    local value, r0, c0 = logic.valueAt(zone, x, y)
    if not logic.hasEdge(zone, value) then
        return nil
    end
    local ix = zone._index
    local cols = zone.cols
    if ix.regionOf[r0 * cols + c0] then
        return ix.regionOf[r0 * cols + c0]
    end
    -- the same region from whichever cell it is first worked out (static rule 1; bug 28: from the
    -- Ruins courtyard's north bank the bridge was guided to in the middle of its deck, from the
    -- courtyard at its north end): the floors it spreads over grow during the flood, so a cell
    -- turned away before its floor joined counted only from some starts; flooded again with the
    -- floors found until they grow no more. Its cells are taken in grid order (the order of the
    -- flood gave each mouth's points another order, and the guidance another point).
    local cells, list = {}, {}
    local floors = { [ix.floor or 0] = true }
    local nFloors = 0
    while true do
        local n = 0
        for _ in pairs(floors) do
            n = n + 1
        end
        if n == nFloors then
            break
        end
        nFloors = n
        cells, list = {}, {}
        logic.flood(zone, { { r0, c0 } }, function(r, c, key)
            return regionJoins(zone, r, c, key, floors, value)
        end, function(r, c)
            list[#list + 1] = r
            list[#list + 1] = c
            return #list >= logic.REGION_MAX * 2
        end, cells)
    end
    local keys = {}
    for i = 1, #list - 1, 2 do
        keys[#keys + 1] = list[i] * cols + list[i + 1]
    end
    table.sort(keys)
    list = {}
    for _, key in ipairs(keys) do
        list[#list + 1] = math.floor(key / cols)
        list[#list + 1] = key % cols
    end
    local region = {
        value = value, label = logic.place(zone, logic.placeOf(value)).label, cells = cells,
        mouths = findMouths(zone, cells, list, floors, logic.placeOf(value)),
    }
    joinedClimbMouths(zone, region, cells, floors)
    if ix.covered then
        region.mouths = doorMouths(zone, region)
    end
    for _, e in ipairs(logic.entrances(zone)) do
        local er, ec = logic.cellOf(zone, e.x, e.y)
        if logic.nearCell(zone, cells, er, ec, true) then
            -- in the indoor layer a passage or the way out is said by its name alone
            table.insert(region.mouths, { label = e.building, class = e.plain and "room" or "entrance", points = { e.x, e.y } })
        end
    end
    -- cached before the side streets are dropped: withoutSideStreets asks for the neighbouring
    -- squares' regions, which ask for this one again (the cache ends that round trip)
    for key in pairs(cells) do
        ix.regionOf[key] = region
    end
    region.mouths = logic.withoutSideStreets(zone, region)
    return region
end

-- The place label and kind at a grid cell.
local function labelAtCell(zone, r, c, mouth)
    local v = mouth and logic.mouthCellValue(zone, mouth, r, c) or logic.valueAtCell(zone, r, c)
    local p = logic.place(zone, logic.placeOf(v))
    return p and p.label, p and p.kind
end

-- The place kind of a mouth: that of its first border cell (nil for a mouth without cells, an
-- entrance).
local function mouthKind(zone, m)
    local cell = m.cells and m.cells[1]
    return cell and select(2, labelAtCell(zone, cell[1], cell[2], m)) or nil
end

-- A neighbouring square or hall is a place of its own: it counts even where it meets no other way
-- (the square before the Cathedral of Light lies between two parts of an unnamed square and the
-- cathedral; it was dropped as leading nowhere, 2026-09-29). leadsOn is for streets and ramps.
local function isSquareMouth(zone, m)
    return logic.EDGED[mouthKind(zone, m)] or false
end

-- The middle of a mouth's border cells, and of the square's cells beside them (world yards).
-- Cached on the mouth.
local function mouthMiddle(zone, m)
    if m.mx == nil then
        local mx, my, ix, iy, n = 0, 0, 0, 0, #m.cells
        for _, cell in ipairs(m.cells) do
            local bx, by = logic.cellCentre(zone, cell[1], cell[2])
            local sx, sy = logic.cellCentre(zone, cell[3], cell[4])
            mx, my, ix, iy = mx + bx / n, my + by / n, ix + sx / n, iy + sy / n
        end
        m.mx, m.my, m.ix, m.iy = mx, my, ix, iy
    end
    return m.mx, m.my, m.ix, m.iy
end

-- The squares a street touches along its length (regions), and whether it touches any other way
-- (another street, a walk, a bridge; not a dead end, which leads nowhere): then it leads on.
-- Cached per mouth.
local function streetTouches(zone, mouth)
    if mouth.touches then
        return mouth.touches, mouth.touchesWay
    end
    local squares, other, count = {}, false, 0
    logic.flood(zone, mouth.cells or {}, function(r, c)
        local label, kind = labelAtCell(zone, r, c)
        if label == mouth.label then
            return true
        end
        if logic.EDGED[kind] then
            local x, y = logic.cellCentre(zone, r, c)
            local region = logic.regionAt(zone, x, y)
            if region then
                squares[region] = true
            end
        elseif logic.WAYS[kind] and not logic.place(zone, logic.placeOf(logic.valueAtCell(zone, r, c))).deadEnd then
            other = true
        end
        return false
    end, function()
        count = count + 1
        return other or count > logic.LEADS_MAX
    end)
    mouth.touches, mouth.touchesWay = squares, other or count > logic.LEADS_MAX
    return mouth.touches, mouth.touchesWay
end

-- A square's mouths without its side streets: a street that reaches nothing but this square and
-- squares this one opens onto directly (their shared border can be walked across: the export's
-- noContact), at least one of them, is a strip along the side of the open space or a second way
-- beside the opening (user 2026-09-29: the Mage Quarter's square and the Wizard's Sanctum's are one
-- plaza, the street between them runs along its edge; the harbour's square and the Canals' meet
-- over 40 yd, a street beside them joins the same two). A street touching any other way or square
-- leads on and stays; so do dead ends and streets touching this square only.
function logic.withoutSideStreets(zone, region)
    local direct = {}
    for _, m in ipairs(region.mouths) do
        if m.class == "way" and isSquareMouth(zone, m) then
            local x, y = logic.cellCentre(zone, m.cells[1][1], m.cells[1][2])
            local other = logic.regionAt(zone, x, y)
            if other then
                direct[other] = true
            end
        end
    end
    local kept = {}
    for _, m in ipairs(region.mouths) do
        local side = false
        if m.class == "way" and m.cells and m.cells[1] and next(direct) and not isSquareMouth(zone, m) then
            local squares, leadsOther = streetTouches(zone, m)
            if not leadsOther then
                local neighbour = false
                side = true
                for other in pairs(squares) do
                    if other ~= region then
                        if direct[other] then
                            neighbour = true
                        else
                            side = false
                        end
                    end
                end
                side = side and neighbour
            end
        end
        if not side then
            kept[#kept + 1] = m
        end
    end
    return kept
end

-- Does the way behind a square's mouth lead on: does the thing (the cells of its pieces joined to
-- the mouth) meet another way than itself and the square's own region? The ramps from the Valley
-- of Heroes down to the moat banks do not (they end at the shore); a street to the next district
-- does. Pieces, not names: a district's streets and squares share a name, and the lane through
-- Stormwind's gate joins the forecourt to the Trade District, both "square of Trade District"
-- (user's walk 2026-09-30 22:15, the lane was dropped as leading nowhere). Cached.
function logic.leadsOn(zone, mouth, region)
    if mouth.leads ~= nil then
        return mouth.leads
    end
    local own = {}
    for _, m in ipairs(mouth.cells or {}) do
        own[logic.placeOf(logic.mouthCellValue(zone, mouth, m[1], m[2]))] = true
    end
    local leads, count = false, 0
    logic.flood(zone, mouth.cells or {}, function(r, c, key)
        local value = logic.mouthCellValue(zone, mouth, r, c)
        local place = value ~= 0 and logic.placeOf(value) or nil
        if own[place] then
            return true
        end
        if place and not region.cells[key] and logic.WAYS[logic.kind(zone, place)] then
            leads = true
        end
        return false
    end, function()
        count = count + 1
        if count > logic.LEADS_MAX then
            leads = true
        end
        return leads
    end)
    mouth.leads = leads
    return leads
end

-- The way a way leads on from a square's mouth: along the axis most of its first cells have (a
-- short bend piece at the opening does not decide it), toward where those cells lie from the
-- opening (not the border's own direction: a mouth in a corner of the square has square cells
-- south and west of it, and the lane through Stormwind's gate said "on to the southeast" while it
-- runs north); without an axis, that direction itself, or `vx`, `vy` (from the square into the
-- opening) when the cells lie on the opening. An angle, or nil.
local function onwardDirection(zone, region, mouth, vx, vy)
    -- a ramp or stairs leads on the way it goes from the square, up or down its own rise (the
    -- stairs past the landing by the auction house said "on to the west" going up to the north)
    if mouth.rise then
        -- the climb's own value (a piece joined to the square's floor shows another value from
        -- the square's floor itself)
        local cell = mouth.cells[1]
        local up = logic.riseOf(zone, mouth.value or logic.valueAtCell(zone, cell[1], cell[2]))
        if up then
            return mouth.rise == "up" and up or (up + 180) % 360
        end
    end
    -- the axes of the cells by compass axis (4 bins), each bin with the sum of its doubled angles
    -- for the mean axis of the winning bin
    local votes, sinSum, cosSum, count, sx, sy = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 0, 0, 0
    logic.flood(zone, mouth.cells, function(r, c, key)
        return not region.cells[key] and labelAtCell(zone, r, c, mouth) == mouth.label
    end, function(r, c)
        local axis = logic.axisOf(zone, logic.valueAtCell(zone, r, c))
        if axis then
            local bin = math.floor((axis + 22.5) / 45) % 4 + 1
            votes[bin] = votes[bin] + 1
            sinSum[bin] = sinSum[bin] + math.sin(math.rad(2 * axis))
            cosSum[bin] = cosSum[bin] + math.cos(math.rad(2 * axis))
        end
        local cx, cy = logic.cellCentre(zone, r, c)
        sx, sy, count = sx + cx, sy + cy, count + 1
        return count >= logic.ONWARD_CELLS
    end, nil, true)
    if count > 0 then
        local mx, my = mouthMiddle(zone, mouth)
        local dx, dy = sx / count - mx, sy / count - my
        if dx * dx + dy * dy >= zone.cell * zone.cell then
            vx, vy = dx, dy
        end
    end
    local best, most = nil, 0
    for bin = 1, 4 do
        if votes[bin] > most then
            best, most = bin, votes[bin]
        end
    end
    if best then
        local axis = (math.deg(math.atan2(sinSum[best], cosSum[best])) / 2) % 180
        local ax, ay = logic.compassVector(axis)
        local len = math.sqrt(vx * vx + vy * vy)
        local along = len > 0 and (ax * vx + ay * vy) / len or 1
        -- the cells lie across the axis rather than along it (a bent lane from a corner mouth)
        if math.abs(along) >= 0.5 then
            return math.floor((along >= 0 and axis or axis + 180) + 0.5) % 360
        end
    end
    if vx ~= 0 or vy ~= 0 then
        return logic.bearingOf(vx, vy)
    end
    return nil
end

-- The longest distance between two of a mouth's border points. Cached on the mouth.
local function mouthSpan(mouth)
    if mouth.span == nil then
        local p, span = mouth.points, 0
        for i = 1, #p - 1, 2 do
            for j = i + 2, #p - 1, 2 do
                span = math.max(span, logic.dist(p[i], p[i + 1], p[j], p[j + 1]))
            end
        end
        mouth.span = span
    end
    return mouth.span
end

-- Where ways begin on the square: the mouths of streets, roads, bridges and walks (not squares)
-- that lead on and meet the square along a short border (a street running along the side of the
-- square shares a long one). Each {mouth, label, kind, x, y (the middle of the opening), onward
-- (the angle the way leads on from the square, or nil)}. Cached per region.
function logic.wayBeginnings(zone, region)
    if region.beginnings then
        return region.beginnings
    end
    local list = {}
    for _, m in ipairs(region.mouths) do
        local kind = m.class == "way" and mouthKind(zone, m)
        if kind and not logic.EDGED[kind] and mouthSpan(m) <= logic.BEGIN_MAX and logic.leadsOn(zone, m, region) then
            -- the middle of the opening: the border point nearest to the border's centre
            local mx, my, ix, iy = mouthMiddle(zone, m)
            local _d, bx, by = logic.nearestOfPoints(m.points, mx, my)
            list[#list + 1] = {
                mouth = m, label = m.label, spoken = m.spoken, kind = kind, x = bx, y = by, span = mouthSpan(m),
                onward = onwardDirection(zone, region, m, mx - ix, my - iy),
            }
        end
    end
    region.beginnings = list
    return list
end

-- The nearest way beginning on the square within reach (to the middle of its opening): `reach`
-- yards beyond half the opening's width, so a wide opening is guided to from as far as a doorway
-- is from its threshold (the 18 yd lane through Stormwind's gate from 17 yd, a 6 yd street from
-- 11; user 2026-09-30: with 8 yd for all, the lane was entered before a word was said). Index,
-- distance, the angle toward it, the beginning.
-- yd; at most this much of half the opening's width is added to the reach: 15 yd at most for an
-- opening 14 yd wide or wider (user 2026-10-01: 18 yd on the Old Town square was too far, "10 or
-- 15 should be sufficient")
logic.BEGINNING_EXTRA = 7

-- From how far a way beginning is guided to: the reach plus half its opening, capped.
-- Did the player leave the way `wayKey` at its end onto the square `region`: the step off it began
-- at (fx, fy) within a beginning's reach (beginningReach, GUIDE_REACH) of that way's beginning on
-- the square (wayBeginnings)? A way running along the square's side has none there: a step off it
-- is a step off sideways.
function logic.leftAtEnd(zone, region, wayKey, fx, fy)
    local label = logic.keyLabel(zone, wayKey)
    for _, b in ipairs(logic.wayBeginnings(zone, region)) do
        if b.label == label and logic.dist(b.x, b.y, fx, fy) <= logic.beginningReach(logic.GUIDE_REACH, b) then
            return true
        end
    end
    -- ... or at an opening of a ramp or stairs onto the square that leads nowhere on the ground's
    -- paint (it goes on over pieces of its own: Northshire Abbey's library ramp, whose foot's paint
    -- ends at its landing; stepping off at its foot counted as stepping off its side once the
    -- ground under its upper part no longer carried its name, trial 2026-10-14)
    if logic.CLIMBS[logic.kind(zone, logic.keyPlace(wayKey))] then
        for _, m in ipairs(region.mouths) do
            if m.label == label and m.class == "way" and mouthSpan(m) <= logic.BEGIN_MAX then
                local d = logic.nearestOfPoints(m.points, fx, fy)
                if d <= logic.beginningReach(logic.GUIDE_REACH, { span = mouthSpan(m) }) then
                    return true
                end
            end
        end
    end
    return false
end

function logic.beginningReach(reach, b)
    return reach + math.min(b.span / 2, logic.BEGINNING_EXTRA)
end

-- `prefer` {x, y}: the beginning guided to last stays the target unless another is nearer by
-- more than GUIDE_STICK (nearestPoint).
function logic.nearestBeginning(zone, region, x, y, reach, prefer)
    return logic.nearestPoint(logic.wayBeginnings(zone, region), x, y, reach, prefer, {
        reachOf = function(b)
            return logic.beginningReach(reach, b)
        end,
    })
end

-- Distance from a position to a mouth's nearest point, and the angle toward it.
function logic.mouthDistance(mouth, x, y)
    local d, bx, by = logic.nearestOfPoints(mouth.points, x, y)
    return d, logic.bearingOf(bx - x, by - y)
end

-- Items from a list of {label, class, d, dir, mouth}: one item per label with its directions
-- (nearest first, at most `maxDirs`; closer than HERE none), items nearest first. A climb's mouths
-- up and down from the square are one item: no "up" or "down" said since 2026-10-04 (user: with
-- rooms and places named they made word monsters, and the stairs one came up said "down here").
local function groupItems(found, maxDirs)
    table.sort(found, function(a, b)
        return a.d < b.d
    end)
    local items, byLabel = {}, {}
    for _, f in ipairs(found) do
        local key = f.label
        local item = byLabel[key]
        if item == nil then
            item = { label = f.label, class = f.class, d = f.d, dirs = {}, mouths = {} }
            byLabel[key] = item
            items[#items + 1] = item
        end
        logic.addDir(item, f.d >= logic.HERE and f.dir or nil, maxDirs)
        if f.mouth then
            item.mouths[#item.mouths + 1] = f.mouth
        end
    end
    return items
end

-- At most `max` items (nil: all); with more, the item labelled `cameFrom` goes first.
function logic.capItems(items, max, cameFrom)
    if max == nil or #items <= max then
        return items
    end
    local out = {}
    for _, item in ipairs(items) do
        if item.label ~= cameFrom then
            out[#out + 1] = item
        end
    end
    while #out > max do
        table.remove(out)
    end
    return out
end

local function mouthFound(m, x, y)
    local d, dir = logic.mouthDistance(m, x, y)
    return { label = m.spoken or m.label, class = m.class, rise = m.rise, d = d, dir = dir, mouth = m }
end

-- yd; the opening of the flight just left lies at most this far from where the player stepped off
logic.LEAVE_NEAR = 12

-- What lies around the player on the region: items {label, class, dirs, mouths}, nearest first.
-- opts (all optional): max (items), cameFrom (the label that goes first when there are more),
-- leaveOut ({place, x, y}: the climb just left and where; its opening nearest there left out),
-- dirs (directions per item at most), classes (a set: only these classes), leading (with zone:
-- only ways that lead on, see leadsOn; squares always, and climbs: a ramp or stairs leads to
-- another floor, which is somewhere, though no way begins there (the Brill tavern's stairs fell
-- off the common room's entry line because the landing above is no way; user 2026-10-06)).
function logic.aroundItems(region, x, y, opts)
    opts = opts or {}
    local found = {}
    -- the opening of the flight just left: of that flight's place, the one nearest to where the
    -- player stepped off it (a landing's two flights open 4 to 6 yd from the step, both)
    local left, leftD = nil, logic.LEAVE_NEAR
    if opts.leaveOut then
        for _, m in ipairs(region.mouths) do
            if m.value and logic.placeOf(m.value) == opts.leaveOut.place then
                local d = logic.nearestOfPoints(m.points, opts.leaveOut.x, opts.leaveOut.y)
                if d and d <= leftD then
                    left, leftD = m, d
                end
            end
        end
    end
    for _, m in ipairs(region.mouths) do
        if (opts.classes == nil or opts.classes[m.class]) and m ~= left
            and not (opts.leading and m.class == "way" and not isSquareMouth(opts.zone, m)
                and not logic.CLIMBS[mouthKind(opts.zone, m)] and not logic.leadsOn(opts.zone, m, region)) then
            found[#found + 1] = mouthFound(m, x, y)
        end
    end
    return logic.capItems(groupItems(found, opts.dirs), opts.max, opts.cameFrom)
end

-- The mouths of the region's ways (said with the square's exits on entry), as a set.
function logic.wayMouths(region)
    local said = {}
    for _, m in ipairs(region.mouths) do
        said[m] = m.class == "way" or nil
    end
    return said
end

-- Mouths of the region not yet said (`said`, a set kept by the caller) that the player has come
-- within `reach` yards of, nearest first, as items; they are marked said. Entrances and doorways
-- are left to the entrance guidance.
function logic.approaching(region, x, y, reach, said, maxDirs)
    local found = {}
    -- a thing said is said by its label: a staircase in flights is several mouths of one name
    -- (the tavern's stairs came as "near" three times in two seconds)
    local labels = {}
    for _, m in ipairs(region.mouths) do
        if said[m] then
            labels[m.label] = true
        end
    end
    for _, m in ipairs(region.mouths) do
        if not said[m] and not labels[m.label] and m.class ~= "entrance" and m.class ~= "room" then
            local f = mouthFound(m, x, y)
            if f.d <= reach then
                said[m] = true
                labels[m.label] = true
                found[#found + 1] = f
            end
        end
    end
    return groupItems(found, maxDirs)
end

-- Cliffs and water around an outdoor place: per class (from `classOf`, kind -> class word) the
-- nearest cells within `reach` yards, as items {label, class, dirs, d}: up to 2 directions that
-- are not neighbours on the compass ("cliff edge to the west and north", not "west and
-- northwest"), items nearest first. `skip`: a set of classes left out.
function logic.featuresAround(zone, x, y, reach, classOf, skip)
    local r0, c0 = logic.cellOf(zone, x, y)
    local n = math.ceil(reach / zone.cell)
    local sectors = {} -- class -> direction key (one per word) -> {nearest distance, its angle}
    for dr = -n, n do
        for dc = -n, n do
            local cx, cy = logic.cellCentre(zone, r0 + dr, c0 + dc)
            local d = logic.dist(cx, cy, x, y)
            if d <= reach and d >= zone.cell / 2 then
                local v = logic.valueAtCell(zone, r0 + dr, c0 + dc)
                local class = v ~= 0 and classOf[logic.kindOf(zone, v)]
                if class and not (skip and skip[class]) then
                    local byDir = sectors[class] or {}
                    sectors[class] = byDir
                    local dir = logic.bearingOf(cx - x, cy - y)
                    local key = logic.dirKey(dir)
                    if byDir[key] == nil or d < byDir[key].d then
                        byDir[key] = { d = d, dir = dir }
                    end
                end
            end
        end
    end
    local items = {}
    for class, byDir in pairs(sectors) do
        local list = {}
        for _, s in pairs(byDir) do
            list[#list + 1] = s
        end
        table.sort(list, function(a, b)
            return a.d < b.d
        end)
        local dirs = {}
        for _, s in ipairs(list) do
            local apart = true
            for _, dir in ipairs(dirs) do
                -- not neighbours among the 8 words (or the 12 hours)
                apart = apart and logic.wordSteps(s.dir, dir) >= 2
            end
            if apart and #dirs < 2 then
                dirs[#dirs + 1] = s.dir
            end
        end
        items[#items + 1] = { label = class, class = class, dirs = dirs, d = list[1].d }
    end
    table.sort(items, function(a, b)
        return a.d < b.d
    end)
    return items
end
