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
logic.BEGIN_MAX = 16 -- yd; a way meeting the square along a longer border runs beside it
logic.ONWARD_CELLS = 24 -- cells of a way from its opening whose axis says where it leads on
logic.ITEM_DIRS = 2 -- directions per thing while walking (a street meeting a square in five places)
logic.HERE = 2 -- yd; closer than this a thing is "here", without a direction
-- yd; a neighbouring square whose border lies this close to the opening of a street that leads to
-- it is that street's connection: only the street is said (see logic.sameWayMouths)
logic.SAME_WAY = 15

-- Does a cell value belong to a place that says what lies around it?
function logic.isAroundPlace(zone, value)
    if value == nil or value == 0 then
        return false
    end
    local kind = logic.kindOf(zone, value)
    return logic.SQUARES[kind] or (kind == "street" and value % 100 == 0) or false
end

-- The thing a border cell shows: label and class ("way" with the place's label; "water", "cliff
-- edge", "canal", which are their own label), or nil.
local function borderThing(zone, value, key)
    if value ~= 0 then
        local p = logic.place(zone, logic.placeOf(value))
        local kind = p and p.kind
        if logic.WAYS[kind] then
            return p.label, "way"
        elseif logic.WATER[kind] then
            return "water", "water"
        elseif logic.DROPS[kind] then
            return "cliff edge", "cliff edge"
        end
        return nil
    end
    if zone._index.under[key] then
        return "canal", "canal"
    end
    return nil
end

-- The border cells of the region grouped into mouths, one per stretch of border of each thing:
-- {label, class, points {x, y, ...}, cells {border r, c, square r, c}}.
local function findMouths(zone, cells, list)
    local byLabel, order, seen = {}, {}, {}
    for i = 1, #list - 1, 2 do
        local r, c = list[i], list[i + 1]
        for _, s in ipairs(logic.STEPS) do
            local nr, nc = r + s[1], c + s[2]
            local key = nr * zone.cols + nc
            if not cells[key] and not seen[key] and logic.inGrid(zone, nr, nc) then
                seen[key] = true
                local label, class = borderThing(zone, logic.valueAtCell(zone, nr, nc), key)
                if label then
                    if byLabel[label] == nil then
                        byLabel[label] = { class = class, cells = {} }
                        order[#order + 1] = label
                    end
                    -- the border cell and the square's cell beside it (for the way on)
                    table.insert(byLabel[label].cells, { nr, nc, r, c })
                end
            end
        end
    end
    local mouths = {}
    for _, label in ipairs(order) do
        local group = byLabel[label]
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
                if #members >= logic.MOUTH_MIN then
                    local points = {}
                    for _, m in ipairs(members) do
                        local px, py = logic.cellCentre(zone, m[1], m[2])
                        points[#points + 1] = px
                        points[#points + 1] = py
                    end
                    mouths[#mouths + 1] = { label = label, class = group.class, points = points, cells = members }
                end
            end
        end
    end
    return mouths
end

-- The region of the around-place at a position: {value, label, cells (set of keys), mouths}, where
-- the building entrances on the square or at its edge are mouths too (class "entrance", labelled
-- with the building); nil where the place is no around-place. Cached per cell.
function logic.regionAt(zone, x, y)
    local value, r0, c0 = logic.valueAt(zone, x, y)
    if not logic.isAroundPlace(zone, value) then
        return nil
    end
    local ix = zone._index
    local cols = zone.cols
    if ix.regionOf[r0 * cols + c0] then
        return ix.regionOf[r0 * cols + c0]
    end
    local cells, list = {}, {}
    logic.flood(zone, { { r0, c0 } }, function(r, c)
        return logic.valueAtCell(zone, r, c) == value
    end, function(r, c)
        list[#list + 1] = r
        list[#list + 1] = c
        return #list >= logic.REGION_MAX * 2
    end, cells)
    local region = {
        value = value, label = logic.place(zone, logic.placeOf(value)).label, cells = cells,
        mouths = logic.sameWayMouths(zone, findMouths(zone, cells, list)),
    }
    for _, e in ipairs(logic.entrances(zone)) do
        local er, ec = logic.cellOf(zone, e.x, e.y)
        if logic.nearCell(zone, cells, er, ec, true) then
            table.insert(region.mouths, { label = e.building, class = "entrance", points = { e.x, e.y } })
        end
    end
    for key in pairs(cells) do
        ix.regionOf[key] = region
    end
    return region
end

-- The place label and kind at a grid cell.
local function labelAtCell(zone, r, c)
    local p = logic.place(zone, logic.placeOf(logic.valueAtCell(zone, r, c)))
    return p and p.label, p and p.kind
end

-- Does the way behind a mouth reach the place `place` (a place id): the cells of the mouth's
-- thing joined to it, and the cells beside them. Cached per mouth and place.
local function wayReaches(zone, mouth, place)
    mouth.reaches = mouth.reaches or {}
    if mouth.reaches[place] ~= nil then
        return mouth.reaches[place]
    end
    local found, count = false, 0
    logic.flood(zone, mouth.cells or {}, function(r, c)
        if labelAtCell(zone, r, c) == mouth.label then
            return true
        end
        if logic.placeOf(logic.valueAtCell(zone, r, c)) == place then
            found = true
        end
        return false
    end, function()
        count = count + 1
        return found or count > logic.LEADS_MAX
    end)
    mouth.reaches[place] = found
    return found
end

local function mouthsApart(a, b)
    local best = math.huge
    for i = 1, #a.points - 1, 2 do
        for j = 1, #b.points - 1, 2 do
            best = math.min(best, math.sqrt((a.points[i] - b.points[j]) ^ 2 + (a.points[i + 1] - b.points[j + 1]) ^ 2))
        end
    end
    return best
end

-- A square's mouths without the neighbouring squares that touch it within SAME_WAY yd of the
-- opening of a street (not a square) that leads to them: the street is the connection. On the flat
-- grid each square reaches a few yards past its floor, so two squares seemed to touch right beside
-- the street joining them, and both were said in the same direction (user 2026-09-29: "left and
-- right of the street is already place").
function logic.sameWayMouths(zone, mouths)
    local kept = {}
    for _, m in ipairs(mouths) do
        local cell = m.class == "way" and m.cells and m.cells[1]
        local value = cell and logic.valueAtCell(zone, cell[1], cell[2])
        local same = false
        if value and logic.SQUARES[logic.kindOf(zone, value)] then
            local place = logic.placeOf(value)
            for _, w in ipairs(mouths) do
                local wc = w ~= m and w.class == "way" and w.cells and w.cells[1]
                local wv = wc and logic.valueAtCell(zone, wc[1], wc[2])
                if wv and not logic.SQUARES[logic.kindOf(zone, wv)] and mouthsApart(m, w) <= logic.SAME_WAY
                    and wayReaches(zone, w, place) then
                    same = true
                    break
                end
            end
        end
        if not same then
            kept[#kept + 1] = m
        end
    end
    return kept
end

-- Does the way behind a square's mouth lead on: does the thing (all cells of that name joined to
-- the mouth) meet another way than itself and the square? The ramps from the Valley of Heroes down
-- to the moat banks do not (they end at the shore); a street to the next district does. Cached.
function logic.leadsOn(zone, mouth, originLabel)
    if mouth.leads ~= nil then
        return mouth.leads
    end
    local leads, count = false, 0
    logic.flood(zone, mouth.cells or {}, function(r, c)
        local label, kind = labelAtCell(zone, r, c)
        if label ~= mouth.label and label and label ~= originLabel and logic.WAYS[kind] then
            leads = true
        end
        return label == mouth.label
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
-- short bend piece at the opening does not decide it), away from the square (`vx`, `vy`: from the
-- square into the opening); without an axis, that direction itself. A compass index, or nil.
local function onwardDirection(zone, region, mouth, vx, vy)
    local votes, count = { 0, 0, 0, 0 }, 0
    logic.flood(zone, mouth.cells, function(r, c, key)
        return not region.cells[key] and labelAtCell(zone, r, c) == mouth.label
    end, function(r, c)
        local axis = logic.axisOf(zone, logic.valueAtCell(zone, r, c))
        if axis then
            votes[axis] = votes[axis] + 1
        end
        count = count + 1
        return count >= logic.ONWARD_CELLS
    end, nil, true)
    local best, most = nil, 0
    for axis = 1, 4 do
        if votes[axis] > most then
            best, most = axis, votes[axis]
        end
    end
    if best then
        local ax, ay = logic.compassVector(best)
        return (ax * vx + ay * vy >= 0) and best or best + 4
    elseif vx ~= 0 or vy ~= 0 then
        return logic.compassIndex(vx, vy)
    end
    return nil
end

-- The longest distance between two of a mouth's border points.
local function mouthSpan(mouth)
    local p, span = mouth.points, 0
    for i = 1, #p - 1, 2 do
        for j = i + 2, #p - 1, 2 do
            span = math.max(span, math.sqrt((p[i] - p[j]) ^ 2 + (p[i + 1] - p[j + 1]) ^ 2))
        end
    end
    return span
end

-- Where ways begin on the square: the mouths of streets, roads, bridges and walks (not squares)
-- that lead on and meet the square along a short border (a street running along the side of the
-- square shares a long one). Each {mouth, label, kind, x, y (the middle of the opening), onward
-- (compass index the way leads on from the square, or nil)}. Cached per region.
function logic.wayBeginnings(zone, region)
    if region.beginnings then
        return region.beginnings
    end
    local list = {}
    for _, m in ipairs(region.mouths) do
        local kind = m.class == "way" and m.cells[1] and select(2, labelAtCell(zone, m.cells[1][1], m.cells[1][2]))
        if kind and not logic.SQUARES[kind] and mouthSpan(m) <= logic.BEGIN_MAX and logic.leadsOn(zone, m, region.label) then
            -- the middle of the opening: the border point nearest to the border's centre
            local mx, my, ix, iy, n = 0, 0, 0, 0, #m.cells
            for _, cell in ipairs(m.cells) do
                local bx, by = logic.cellCentre(zone, cell[1], cell[2])
                local sx, sy = logic.cellCentre(zone, cell[3], cell[4])
                mx, my, ix, iy = mx + bx / n, my + by / n, ix + sx / n, iy + sy / n
            end
            local p = m.points
            local best, bx, by = math.huge, nil, nil
            for i = 1, #p - 1, 2 do
                local d = (p[i] - mx) ^ 2 + (p[i + 1] - my) ^ 2
                if d < best then
                    best, bx, by = d, p[i], p[i + 1]
                end
            end
            list[#list + 1] = {
                mouth = m, label = m.label, kind = kind, x = bx, y = by,
                onward = onwardDirection(zone, region, m, mx - ix, my - iy),
            }
        end
    end
    region.beginnings = list
    return list
end

-- The nearest way beginning on the square within `reach` yards (to the middle of its opening):
-- index, distance, compass index toward it, the beginning.
function logic.nearestBeginning(zone, region, x, y, reach)
    return logic.nearestPoint(logic.wayBeginnings(zone, region), x, y, reach)
end

-- Distance from a position to a mouth's nearest point, and the compass index toward it.
function logic.mouthDistance(mouth, x, y)
    local p = mouth.points
    local best, bx, by = math.huge, nil, nil
    for i = 1, #p - 1, 2 do
        local d = math.sqrt((p[i] - x) ^ 2 + (p[i + 1] - y) ^ 2)
        if d < best then
            best, bx, by = d, p[i], p[i + 1]
        end
    end
    return best, logic.compassIndex(bx - x, by - y)
end

-- Items from a list of {label, class, d, dir, mouth}: one item per label with its compass indexes
-- (nearest first, at most `maxDirs`; closer than HERE none), items nearest first.
local function groupItems(found, maxDirs)
    table.sort(found, function(a, b)
        return a.d < b.d
    end)
    local items, byLabel = {}, {}
    for _, f in ipairs(found) do
        local item = byLabel[f.label]
        if item == nil then
            item = { label = f.label, class = f.class, d = f.d, dirs = {}, mouths = {} }
            byLabel[f.label] = item
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
    return { label = m.label, class = m.class, d = d, dir = dir, mouth = m }
end

-- A neighbouring square or hall is a place of its own: it counts even where it meets no other way
-- (the square before the Cathedral of Light lies between two parts of an unnamed square and the
-- cathedral; it was dropped as leading nowhere, 2026-09-29). leadsOn is for streets and ramps.
local function isSquareMouth(zone, m)
    local cell = m.cells and m.cells[1]
    return cell ~= nil and logic.SQUARES[select(2, labelAtCell(zone, cell[1], cell[2]))] or false
end

-- What lies around the player on the region: items {label, class, dirs, mouths}, nearest first.
-- opts (all optional): max (items), cameFrom (the label that goes first when there are more),
-- dirs (directions per item at most), classes (a set: only these classes), leading (with zone:
-- only ways that lead on, see leadsOn; squares always).
function logic.aroundItems(region, x, y, opts)
    opts = opts or {}
    local found = {}
    for _, m in ipairs(region.mouths) do
        if (opts.classes == nil or opts.classes[m.class])
            and not (opts.leading and m.class == "way" and not isSquareMouth(opts.zone, m)
                and not logic.leadsOn(opts.zone, m, region.label)) then
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
-- within `reach` yards of, nearest first, as items; they are marked said. Entrances are left to
-- the entrance guidance.
function logic.approaching(region, x, y, reach, said, maxDirs)
    local found = {}
    for _, m in ipairs(region.mouths) do
        if not said[m] and m.class ~= "entrance" then
            local f = mouthFound(m, x, y)
            if f.d <= reach then
                said[m] = true
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
    local sectors = {} -- class -> compass index -> nearest distance
    for dr = -n, n do
        for dc = -n, n do
            local cx, cy = logic.cellCentre(zone, r0 + dr, c0 + dc)
            local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
            if d <= reach and d >= zone.cell / 2 then
                local v = logic.valueAtCell(zone, r0 + dr, c0 + dc)
                local class = v ~= 0 and classOf[logic.kindOf(zone, v)]
                if class and not (skip and skip[class]) then
                    local byDir = sectors[class] or {}
                    sectors[class] = byDir
                    local dir = logic.compassIndex(cx - x, cy - y)
                    if byDir[dir] == nil or d < byDir[dir] then
                        byDir[dir] = d
                    end
                end
            end
        end
    end
    local items = {}
    for class, byDir in pairs(sectors) do
        local list = {}
        for dir, d in pairs(byDir) do
            list[#list + 1] = { dir = dir, d = d }
        end
        table.sort(list, function(a, b)
            return a.d < b.d
        end)
        local dirs = {}
        for _, s in ipairs(list) do
            local apart = true
            for _, dir in ipairs(dirs) do
                local gap = math.abs(s.dir - dir) % 8
                apart = apart and math.min(gap, 8 - gap) >= 2
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
