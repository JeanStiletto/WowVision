-- Surroundings logic, shared by the module and the headless tests (no WoW API calls in these
-- files). This one: directions, the zone grid, unpacking a zone's data into named records, place
-- texts and the entry rule. The data format is described in docs/src/developer/surroundings.md.
--
-- Directions: a world offset is (dx north, dy west); a direction is an angle in degrees clockwise
-- from north (0..359; an axis, both ways of a street, 0..179); a facing (GetPlayerFacing) is in
-- radians, 0 = north, counter-clockwise. The words come last: the 8 compass words, or with
-- logic.clock the 12 clock hours of a north-up clock (12 = north).

local logic = {}
WowVision.surroundingsLogic = logic

local function set(...)
    local s = {}
    for _, key in ipairs({ ... }) do
        s[key] = true
    end
    return s
end

-- Place kinds (the data's English kind keys)
logic.ROADS = set("road", "fork", "crossing")
-- places with an edge (their region: logic.regionAt), which says what they lead to (a structure's
-- platform too: its stairs, user 2026-10-06); no way begins there. Every other place says what lies
-- around the player by radius (texts.lua spotBody: one rule for both)
logic.EDGED = set("square", "hall", "platform")
logic.WAYS = set("street", "square", "hall", "road", "fork", "crossing", "bridge", "quay", "pier", "canal walk",
    "slime canal walk", "walk along the lava", "ramp", "stairs")
logic.LANE_KINDS = set("road", "fork", "crossing", "street", "quay", "pier", "canal walk", "slime canal walk",
    "walk along the lava", "ramp", "stairs") -- ways with centre lines
logic.TURN_KINDS = set("road", "street", "quay", "pier", "canal walk", "slime canal walk", "walk along the lava",
    "ramp", "stairs") -- ... with one direction
-- counted after a short walk inside: bridges and every way with a centre line (streets and walks
-- follow the road rules)
logic.NARROW = set("road", "bridge", "fork", "crossing", "street", "quay", "pier", "canal walk", "slime canal walk",
    "walk along the lava", "ramp", "stairs")
-- ramps and stairs (said like a street, "stairs, north to south": no "up" or "down" since
-- 2026-10-04); their sides are named when bumped into from beside them
logic.CLIMBS = set("ramp", "stairs")
logic.WATER = set("deep water", "shore")
logic.DROPS = set("cliff edge")

-- Directions -------------------------------------------------------------------------------------
-- The data carries angles (since format 2, 2026-10-01); the player's words are chosen here: the 8
-- compass words, or with logic.clock (the compass module's Directions setting) the 12 hours.

logic.CODE = 10000 -- a cell value is place id * CODE + direction code (template * 1000 + angle)
logic.clock = false -- clock hours instead of compass words (the module sets it from the setting)
local HOUR = "\1" -- marks an hour in a text until finishText decides where "o'clock" goes
local HOUR_SAID = "\2" -- ... an hour that gets its "o'clock" in place (a yard count comes before it)
local L = WowVision:getLocale()

-- Degrees clockwise from north of a world offset.
local function bearing(dx, dy)
    return math.deg(math.atan2(-dy, dx)) % 360
end

-- Degrees clockwise from north of a world offset, rounded (0..359).
function logic.bearingOf(dx, dy)
    return math.floor(bearing(dx, dy) + 0.5) % 360
end

-- Degrees between the direction of a world offset and an angle.
function logic.angleOff(dx, dy, angle)
    local off = math.abs(bearing(dx, dy) - angle) % 360
    return math.min(off, 360 - off)
end

-- Degrees between two angles (0..180).
function logic.angleGap(a, b)
    local off = math.abs(a - b) % 360
    return math.min(off, 360 - off)
end

-- Unit world vector of an angle.
function logic.compassVector(angle)
    local a = math.rad(angle)
    return math.cos(a), -math.sin(a)
end

-- The compass word index (1 = north .. 8 = northwest) and the clock hour (1..12) of an angle.
function logic.wordIndex(angle)
    return math.floor((angle + 22.5) / 45) % 8 + 1
end

function logic.hourOf(angle)
    local h = math.floor((angle + 15) / 30) % 12
    return h == 0 and 12 or h
end

-- Two angles that come out as one word (or hour) in the current mode are the same direction.
function logic.dirKey(angle)
    if logic.clock then
        return logic.hourOf(angle)
    end
    return logic.wordIndex(angle)
end

function logic.sameDir(a, b)
    return logic.dirKey(a) == logic.dirKey(b)
end

-- How many words (or hours) apart two angles come out: 0 the same word, 1 neighbours, ...
function logic.wordSteps(a, b)
    local n = logic.clock and 12 or 8
    local gap = math.abs(logic.dirKey(a) - logic.dirKey(b)) % n
    return math.min(gap, n - gap)
end

-- The spoken direction of an angle: "northeast", or in clock mode the hour as a bare number (the
-- text gets its "o'clock" from finishText). `said`: this hour needs "o'clock" right after it.
function logic.dirWord(zone, angle, said)
    if logic.clock then
        return logic.hourOf(angle) .. (said and HOUR_SAID or HOUR)
    end
    return zone.compass[logic.wordIndex(angle)]
end

-- The axis key of an axis angle (0..179): one of 4 in compass mode, of 6 in clock mode.
function logic.axisKey(angle)
    if logic.clock then
        return math.floor((angle + 15) / 30) % 6
    end
    return math.floor((angle + 22.5) / 45) % 4
end

function logic.sameAxis(a, b)
    return logic.axisKey(a) == logic.axisKey(b)
end

-- The spoken words of an axis angle: "north to south" (zone.spokenAxes in the client's language),
-- in clock mode both hours, the one nearer 12 first as the compass words put the northern end
-- first ("10 to 4" for northwest to southeast, "3 to 9" for east to west; user 2026-10-01).
function logic.axisWords(zone, angle)
    if logic.clock then
        local a, b = logic.hourOf(angle), logic.hourOf(angle + 180)
        local function fromNorth(h)
            return math.min(math.abs(h - 12), h)
        end
        if fromNorth(b) < fromNorth(a) or (fromNorth(b) == fromNorth(a) and b < a) then
            a, b = b, a
        end
        return string.format(L["%s to %s"], logic.dirWord(zone, a * 30), logic.dirWord(zone, b * 30))
    end
    local i = logic.axisKey(angle) + 1
    if zone.spokenAxes then
        return zone.spokenAxes[i]
    end
    local word = zone.axes[i]
    return word and (word:gsub("%-", " to "))
end

-- A direction template of the data ("water to the %s", index into zone.dirs); in clock mode its
-- clock form ("water at %s", zone.dirsClock).
function logic.dirTemplate(zone, i)
    if logic.clock and zone.dirsClock then
        return zone.dirsClock[i]
    end
    return zone.dirs[i]
end

-- A text ready to speak: the hour marks resolved. "o'clock" once after the last hour where a text
-- names two or more hours (a list), in place where a yard count comes before the hour ("6 at 4
-- o'clock, in at 4"); a single hour elsewhere stays a bare number (user 2026-10-01: as short as
-- possible without confusion). The list's "o'clock" follows its last hour, not the whole text: the
-- describe key's "fork, canal walk at 1 and 8, street at 5, 5 at 2 o'clock, canal" ended in
-- "canal o'clock" (walk 2026-10-02).
function logic.finishText(text)
    if text == nil or not text:find("[\1\2]") then
        return text
    end
    local _, plain = text:gsub(HOUR, "")
    local clock = L["o'clock"]
    text = text:gsub(HOUR_SAID, " " .. clock)
    if plain >= 2 then
        local last = text:find(HOUR .. "[^" .. HOUR .. "]*$")
        text = text:sub(1, last - 1) .. " " .. clock .. text:sub(last + 1)
    end
    text = text:gsub(HOUR, "")
    return text
end

-- Fork and crossing labels (and a place's nearest road) carry their directions as angles in the
-- data ("<d45,135>"): said in the player's words ("to the northeast and southeast", "at 2 and 4").
function logic.expandDirs(zone, text)
    if text == nil or not text:find("<d", 1, true) then
        return text
    end
    local template = logic.dirTemplate(zone, zone._toward) or "%s"
    return (text:gsub("<d([%d,]+)>", function(list)
        -- clockwise from north ("12, 2, 4 and 7"), not in the data's order
        local angles = {}
        for a in list:gmatch("%d+") do
            angles[#angles + 1] = tonumber(a)
        end
        table.sort(angles)
        -- one word said once: two arms 13 degrees apart are two compass words but one clock hour
        -- ("Die große Schmiede auf 5, 5 und 9", walk 2026-10-24 16:41:27)
        local words = {}
        for _, a in ipairs(angles) do
            local w = logic.dirWord(zone, a)
            if w ~= words[#words] then
                words[#words + 1] = w
            end
        end
        if #words > 1 and words[#words] == words[1] then
            words[#words] = nil
        end
        return string.format(template, logic.joinWords(words))
    end))
end

-- Signed degrees from angle b to angle a (both radians, counter-clockwise), -180 to 180.
function logic.degreesBetween(a, b)
    local d = math.deg(a - b) % 360
    return d > 180 and d - 360 or d
end

-- The axis angle (0..179) a facing lies on: facing north or south is the north-south axis, 0.
function logic.facingAxis(facing)
    return logic.bearingOf(math.cos(facing), math.sin(facing)) % 180
end

-- Geometry ---------------------------------------------------------------------------------------

-- The distance between two points, and its square (for comparisons without the root).
function logic.dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function logic.dist2(ax, ay, bx, by)
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The point of the segment (ax, ay)-(bx, by) nearest to (qx, qy): its x, y and the distance to it.
function logic.segmentPoint(qx, qy, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local n = dx * dx + dy * dy
    local t = n > 0 and math.max(0, math.min(1, ((qx - ax) * dx + (qy - ay) * dy) / n)) or 0
    local px, py = ax + t * dx, ay + t * dy
    return px, py, math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

-- The point of a flat list {x1, y1, x2, y2, ...} nearest to (x, y): its distance, x and y, and the
-- index of its x in the list; nil for an empty list.
function logic.nearestOfPoints(points, x, y)
    local best, bk = math.huge, nil
    for k = 1, #points - 1, 2 do
        local d = (points[k] - x) ^ 2 + (points[k + 1] - y) ^ 2
        if d < best then
            best, bk = d, k
        end
    end
    if bk == nil then
        return nil
    end
    return math.sqrt(best), points[bk], points[bk + 1], bk
end

-- The grid -----------------------------------------------------------------------------------------

-- Row 0 lies at world x = zone.top (north), column 0 at world y = zone.left (west).
function logic.cellOf(zone, x, y)
    return math.floor((zone.top - x) / zone.cell), math.floor((zone.left - y) / zone.cell)
end

-- The cell key offsets of the cell (r, c) and the 8 around it that lie in the grid, in the order rows north to south,
-- each row's cells west to east: `r * zone.cols + c + offset` for each. A cell in the first or last column has no
-- neighbour beyond it (the key one step west of column 0 is the last cell of the row before: the user 2026-10-30,
-- the column wrap guard), nor a cell in the first or last row; a cell outside the grid has none of them in it.
-- (Cached per grid width and the rows and columns in it: no new table at a call.)
local AROUND = {}
function logic.cellOffsets(zone, r, c)
    local cols, rows = zone.cols, zone.rows
    local rowMask, colMask = 0, 0
    for i = -1, 1 do
        if r + i >= 0 and r + i < rows then
            rowMask = rowMask + 2 ^ (i + 1)
        end
        if c + i >= 0 and c + i < cols then
            colMask = colMask + 2 ^ (i + 1)
        end
    end
    local k = cols * 64 + rowMask * 8 + colMask
    local a = AROUND[k]
    if a == nil then
        a = {}
        for dr = -1, 1 do
            for dc = -1, 1 do
                if rowMask % 2 ^ (dr + 2) >= 2 ^ (dr + 1) and colMask % 2 ^ (dc + 2) >= 2 ^ (dc + 1) then
                    a[#a + 1] = dr * cols + dc
                end
            end
        end
        AROUND[k] = a
    end
    return a
end

function logic.cellCentre(zone, r, c)
    return zone.top - (r + 0.5) * zone.cell, zone.left - (c + 0.5) * zone.cell
end

function logic.inGrid(zone, r, c)
    return r >= 0 and r < zone.rows and c >= 0 and c < zone.cols
end

function logic.covers(zone, x, y)
    return logic.inGrid(zone, logic.cellOf(zone, x, y))
end

-- The painted cell value of a grid cell (0 = no data): place id * CODE + direction code; where
-- floors stack, the level the export painted (mostly the lowest).
function logic.paintedAtCell(zone, r, c)
    if not logic.inGrid(zone, r, c) then
        return 0
    end
    local row = logic.gridRow(zone, r + 1)
    if row == nil then
        return 0
    end
    local starts = row.starts
    local lo, hi = 1, #starts
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if starts[mid] <= c then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return row.values[lo]
end

-- The cell value of a grid cell: the painted one (the ground's where the ground has floor in the
-- cell), or, up on another floor piece (zone._index.floor, edges.lua updateFloor), that piece's
-- value where the cell lists it (zone.floorCells: the landing over the street), else its value
-- in one of the 8 cells around (the player is on the piece, so it is here, with a cell of its
-- own too narrow for a surface: the ground floor's paint came through at the top of the
-- tavern's stairs, walk 2026-10-06), else the value of a piece joined to it in the cell. So
-- every lookup follows the floor the player is on.
function logic.valueAtCell(zone, r, c)
    local v = logic.paintedAtCell(zone, r, c)
    local ix = zone._index
    local floor = ix.floor or 0
    if floor ~= 0 then
        local cols = zone.cols
        local here = ix.floorCells[r * cols + c]
        local own = here and here[floor]
        if own then
            return own
        end
        local key = r * cols + c
        for _, d in ipairs(logic.cellOffsets(zone, r, c)) do
            local near = ix.floorCells[key + d]
            local nv = near and near[floor]
            if nv then
                return nv
            end
        end
        local joined = ix.joined[floor]
        if here and joined then
            local cx, cy = logic.cellCentre(zone, r, c)
            for p, pv in pairs(here) do
                if joined[p] and logic.joinedHere(zone, floor, p, cx, cy) then
                    return pv
                end
            end
        end
        -- a piece that joins the ground nowhere (a tower's landing 12 yd up, reached by its
        -- stairs) has no ground around it: the ground's paint there is nothing up here (the road
        -- under the zeppelin tower came as "street at 9" on its landings, walk 2026-10-06)
        if not (joined and joined[0]) then
            return 0
        end
    end
    return v
end

-- The value of a floor piece at a grid cell (0 for none there): the ground's is the painted one.
function logic.valueOfFloor(zone, r, c, floor)
    if floor == 0 then
        return logic.paintedAtCell(zone, r, c)
    end
    local here = zone._index.floorCells[r * zone.cols + c]
    return here and here[floor] or 0
end

-- Forgets the squares found so far: their flood depends on the level the player is on.
function logic.forgetRegions(zone)
    local ix = zone._index
    ix.regionOf, ix.regionsByFloor, ix.regionFloor = {}, nil, ix.floor or 0
end

-- The cell value at a world position, plus row and column.
function logic.valueAt(zone, x, y)
    local r, c = logic.cellOf(zone, x, y)
    return logic.valueAtCell(zone, r, c), r, c
end

function logic.placeOf(value)
    return math.floor(value / logic.CODE)
end

-- The direction code of a cell value (template * 1000 + angle), 0 for none.
function logic.codeOf(value)
    return value % logic.CODE
end

-- The place record {kind, label, road} of a place id, or nil.
function logic.place(zone, placeId)
    return zone._index.places[placeId]
end

-- Is the player's floor piece the top of the ramp or stairs `placeId`: neither one of its feet's
-- floors nor the climb itself, and joined to it? From the floor alone, the same from every spot on it.
function logic.atClimbTop(zone, placeId)
    local ix = zone._index
    local floor = ix.floor or 0
    local own = ix.placePieces[placeId] or {}
    local feet = ix.footFloors and ix.footFloors[placeId]
    -- the data's top records (since trial L4): a top of that climb on this floor, and none of its feet (a climb with
    -- its foot and its top on one floor piece, the huts' stairs onto a ground that runs on inside: from that floor
    -- the step onto it tells, riseFrom; STATE bug 113)
    if ix.climbTops then
        local tops = ix.topFloors[placeId]
        return tops ~= nil and tops[floor] == true and not own[floor] and not (feet and feet[floor])
    end
    if feet == nil or feet[floor] or own[floor] then
        return false
    end
    -- (only from a floor the climb is joined to: its top; a floor held a moment by mistake beside
    -- it named the Brill tavern's stairs up "Treppe Richtung Schankraum" in the common room)
    for q in pairs(ix.joined[floor] or {}) do
        if own[q] then
            return true
        end
    end
    return false
end

-- A ramp or stairs named from where the player stands (user 2026-10-17: "Treppe Richtung Keller"
-- from the kitchen, "Treppe Richtung Küche" from the cellar): the place of its name from its top
-- (the export's climbDown) where the player's floor is its top (logic.atClimbTop); else nil (its own name).
function logic.downPlace(zone, placeId)
    local p = zone._index.places[placeId]
    if p == nil or p.down == nil or not logic.atClimbTop(zone, placeId) then
        return nil
    end
    return zone._index.places[p.down]
end

function logic.kind(zone, placeId)
    local p = zone._index.places[placeId]
    return p and p.kind
end

function logic.kindOf(zone, value)
    return logic.kind(zone, logic.placeOf(value))
end

-- Is `map[key]` of the cell (r, c) or one of its eight neighbours `want`? `map` holds a value per
-- cell key, or a set of values.
function logic.nearCell(zone, map, r, c, want)
    local key = r * zone.cols + c
    for _, d in ipairs(logic.cellOffsets(zone, r, c)) do
        local v = map[key + d]
        if v == want or (type(v) == "table" and v[want]) then
            return true
        end
    end
    return false
end

-- The nearest cell centre at most `cells` cells from the position's cell (and within `reach`
-- yards, if given) whose value `accept(value)` takes: distance, centre x and y, value; or nil.
function logic.nearestCell(zone, x, y, cells, reach, accept)
    local r0, c0 = logic.cellOf(zone, x, y)
    local best, bx, by, bv = nil, nil, nil, nil
    for dr = -cells, cells do
        for dc = -cells, cells do
            local cx, cy = logic.cellCentre(zone, r0 + dr, c0 + dc)
            local d = logic.dist(cx, cy, x, y)
            if (reach == nil or d <= reach) and (best == nil or d < best) then
                local v = logic.valueAtCell(zone, r0 + dr, c0 + dc)
                if accept(v) then
                    best, bx, by, bv = d, cx, cy, v
                end
            end
        end
    end
    return best, bx, by, bv
end

-- The nearest cell within `reach` yards whose place kind is in `kinds`: distance, the angle
-- toward it (from the cell centres) and the cell's value, or nil.
function logic.nearestOfKinds(zone, x, y, kinds, reach)
    local d, cx, cy, v = logic.nearestCell(zone, x, y, math.ceil(reach / zone.cell), reach, function(v)
        return kinds[logic.kindOf(zone, v)]
    end)
    if d == nil then
        return nil
    end
    return d, logic.bearingOf(cx - x, cy - y), v
end

logic.STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } -- a cell's four neighbours

-- A flood over the grid from the `seeds` (a list of {r, c}), through the four neighbours of each
-- cell, depth first (breadth first with `breadthFirst`). `joins(r, c, key)` says whether a
-- neighbour in the grid joins; `visit(r, c)` is called for every cell taken and ends the flood by
-- returning true. `seen`: the set of cell keys taken or queued (a new one if nil).
function logic.flood(zone, seeds, joins, visit, seen, breadthFirst)
    seen = seen or {}
    local queue, head = {}, 1
    for _, s in ipairs(seeds) do
        local key = s[1] * zone.cols + s[2]
        if not seen[key] then
            seen[key] = true
            queue[#queue + 1] = s
        end
    end
    while #queue >= head do
        local cell
        if breadthFirst then
            cell, head = queue[head], head + 1
        else
            cell = table.remove(queue)
        end
        local r, c = cell[1], cell[2]
        if visit(r, c) then
            return seen
        end
        for _, s in ipairs(logic.STEPS) do
            local nr, nc = r + s[1], c + s[2]
            local key = nr * zone.cols + nc
            if not seen[key] and logic.inGrid(zone, nr, nc) and joins(nr, nc, key) then
                seen[key] = true
                queue[#queue + 1] = { nr, nc }
            end
        end
    end
    return seen
end

-- yd; the target guided to last (`prefer`, its position) stays the target unless another is
-- nearer by more than this (user 2026-10-01: on the Old Town square the guidance hopped between
-- the stairs and a street beginning at about the same distance with every half step)
logic.GUIDE_STICK = 2

-- Is point p the one at `prefer` {x, y} (within half a yard)?
function logic.samePoint(p, prefer)
    return prefer ~= nil and logic.dist2(p.x, p.y, prefer.x, prefer.y) <= 0.25
end

-- The stick rule: does the target guided to last (at `keptD`) stay, against the nearest (at
-- `bestD`)? Only a target nearer by more than GUIDE_STICK takes over.
function logic.sticks(bestD, keptD)
    return keptD ~= nil and bestD > keptD - logic.GUIDE_STICK
end

-- The nearest of the records in `list` (each with x and y) within `reach` yards, with the stick
-- rule for the one at `prefer` {x, y}: index, distance, the angle toward it, the record; or nil.
-- opts (optional): reachOf(p), a record's own reach instead of `reach`; skip(p), true for a record
-- left out.
function logic.nearestPoint(list, x, y, reach, prefer, opts)
    local reachOf, skip = opts and opts.reachOf, opts and opts.skip
    local best, bestD = nil, math.huge
    local kept, keptD = nil, nil
    for i, p in ipairs(list) do
        if not (skip and skip(p)) then
            local d = logic.dist(p.x, p.y, x, y)
            if d <= (reachOf and reachOf(p) or reach) then
                if d <= bestD then
                    best, bestD = i, d
                end
                if logic.samePoint(p, prefer) then
                    kept, keptD = i, d
                end
            end
        end
    end
    if kept and best ~= kept and logic.sticks(bestD, keptD) then
        best, bestD = kept, keptD
    end
    if best == nil then
        return nil
    end
    local p = list[best]
    return best, bestD, logic.bearingOf(p.x - x, p.y - y), p
end

-- Adds a direction (an angle) to an item's directions unless one with the same word is there
-- already or the item has `max`.
function logic.addDir(item, dir, max)
    if dir == nil or #item.dirs >= (max or math.huge) then
        return
    end
    for _, known in ipairs(item.dirs) do
        if logic.sameDir(known, dir) then
            return
        end
    end
    item.dirs[#item.dirs + 1] = dir
end

-- Unpacking ------------------------------------------------------------------------------------

-- Once per zone, before anything else: the index of the axis template "running %s" (found by its
-- English text), the entrance rooms marked (by their English name), then the words of the
-- client's language from the zone's `locales` (same indexes as the English lists) in place of the
-- English ones; the other languages are dropped. Kinds stay English keys.
local function prepareWords(zone, locale)
    if zone._worded then
        return
    end
    zone._worded = true
    zone._running = false
    zone._toward = nil
    for i, template in ipairs(zone.dirs or {}) do
        if template == "running %s" then
            zone._running = i
        elseif template == "to the %s" then
            zone._toward = i
        end
    end
    for _, room in ipairs(zone.rooms or {}) do
        if room[2] == "entrance" then
            room.entrance = true
        end
    end
    -- dead ends (decided offline with the heights), known by their English name; a ramp or
    -- stairs named by its kind alone (no "to <where>")
    for _, place in ipairs(zone.places or {}) do
        if place[2] == "dead end" then
            place.deadEnd = true
        end
        if logic.CLIMBS[place[1]] and place[2] == place[1] then
            place.plain = true
        end
    end
    local t = zone.locales and zone.locales[locale]
    zone.locales = nil
    if t == nil then
        return
    end
    zone.dirs = t.dirs or zone.dirs
    zone.dirsClock = t.dirsClock or zone.dirsClock
    zone.compass = t.compass or zone.compass
    zone.spokenAxes = t.axes
    zone.floors = t.floors or zone.floors
    zone.ofTemplate = t.ofTemplate or zone.ofTemplate
    zone.spoken = t.spoken or zone.spoken
    for i, p in ipairs(t.places or {}) do
        local place = zone.places[i]
        if place then
            place[2] = p[1] or place[2]
            if place[3] then
                place[3] = p[2] or place[3]
            end
            place.of = p.of or place.of
        end
    end
    for i, name in ipairs(t.interiors or {}) do
        if zone.interiors[i] then
            zone.interiors[i][1] = name
        end
    end
    for i, name in ipairs(t.interiorWalls or {}) do
        if zone.interiors[i] and name ~= "" then
            zone.interiors[i].w = name
        end
    end
    for i, name in ipairs(t.rooms or {}) do
        if zone.rooms[i] then
            zone.rooms[i][2] = name
        end
    end
    for i, name in ipairs(t.roomsShort or {}) do
        if zone.rooms[i] and name ~= "" then
            zone.rooms[i].sn = name
        end
    end
    for key, field in pairs({ roomsAtA = "ta", roomsAtB = "tb", roomsArea = "ar" }) do
        for i, name in ipairs(t[key] or {}) do
            if zone.rooms[i] and name ~= "" then
                zone.rooms[i][field] = name
            end
        end
    end
    for _, key in ipairs({ "structs", "objectNames" }) do
        for i, name in ipairs(t[key] or {}) do
            if zone[key] and zone[key][i] then
                zone[key][i] = name
            end
        end
    end
    -- the stops' destinations
    for i, name in ipairs(t.stops or {}) do
        if zone.stops and zone.stops[i] then
            zone.stops[i][2] = name
        end
    end
end

-- Calls `add(...)` with the `n` values of each record of a flat list (nil: no records).
local function eachRecord(list, n, add)
    list = list or {}
    for i = 1, #list - n + 1, n do
        add(unpack(list, i, i + n - 1))
    end
end

-- Calls `add(cellKey, value)` for each (row, column, value) triple of a flat list.
local function eachCellTriple(zone, list, add)
    eachRecord(list, 3, function(r, c, value)
        add(r * zone.cols + c, value)
    end)
end

-- Appends `item` to the list at `key` of `buckets` (made when missing).
local function addToBucket(buckets, key, item)
    local bucket = buckets[key]
    if bucket == nil then
        bucket = {}
        buckets[key] = bucket
    end
    bucket[#bucket + 1] = item
end

-- Buckets per block of cells (2026-10-30, the user: memory and game performance; a table per cell held Elwynn's
-- objects in 62730 buckets of 1.3 each, 8.8 MB, its lines in 23322 of 4.3): an item that covers a box of cells
-- goes into the bucket of every block of BLOCK by BLOCK cells the box reaches, once, and keeps its box (rows
-- item[1]..item[2], columns item[3]..item[4]: the array part, four plain slots; four more named fields doubled the
-- hash part of every object and stretch); the items of one cell are those of its block whose box holds the cell
-- (logic.boxHolds), in the order they were added: the very items and order a bucket per cell had.
logic.BLOCK = 4

-- The block of cells the cell key `key` (row * cols + col) lies in: the key of its bucket.
function logic.blockOf(zone, key)
    local cols, b = zone.cols, logic.BLOCK
    local r = math.floor(key / cols)
    local c = key - r * cols
    return math.floor(r / b) * (math.floor(cols / b) + 1) + math.floor(c / b)
end

-- Whether the box of cells of `item` (item[1]..item[4]) holds the cell key `key`: a cell of the box beyond the
-- grid's first or last column has the key of the row before or after (as a bucket per cell keyed it).
function logic.boxHolds(item, key, cols)
    local r = math.floor(key / cols)
    local c = key - r * cols
    for d = -1, 1 do
        local rr, cc = r + d, c - d * cols
        if rr >= item[1] and rr <= item[2] and cc >= item[3] and cc <= item[4] then
            return true
        end
    end
    return false
end

-- Puts `item` into the buckets of the blocks of every cell the box (x0..x1, y0..y1, widened by `margin` yards)
-- touches, and gives it that box of cells.
local function addToBlocks(zone, buckets, x0, x1, y0, y1, margin, item)
    item[1], item[2] = math.floor((zone.top - x1 - margin) / zone.cell), math.floor((zone.top - x0 + margin) / zone.cell)
    item[3], item[4] = math.floor((zone.left - y1 - margin) / zone.cell), math.floor((zone.left - y0 + margin) / zone.cell)
    local added = {}
    for r = item[1], item[2] do
        for c = item[3], item[4] do
            local block = logic.blockOf(zone, r * zone.cols + c)
            if not added[block] then
                added[block] = true
                addToBucket(buckets, block, item)
            end
        end
    end
end

-- The items of the cell key `key` in the block buckets `buckets` (a list in the order added; nil: none).
-- `cache` (optional, a table kept beside the buckets) keeps the lists asked for, CELL_LISTS_KEPT at most.
logic.CELL_LISTS_KEPT = 4096
function logic.cellItems(zone, buckets, key, cache)
    if cache then
        local got = cache[key]
        if got ~= nil then
            return got or nil
        end
    end
    local out = nil
    for _, item in ipairs(buckets[logic.blockOf(zone, key)] or {}) do
        if logic.boxHolds(item, key, zone.cols) then
            out = out or {}
            out[#out + 1] = item
        end
    end
    if cache then
        cache.n = (cache.n or 0) + 1
        if cache.n > logic.CELL_LISTS_KEPT then
            for k in pairs(cache) do
                cache[k] = nil
            end
            cache.n = 1
        end
        cache[key] = out or false
    end
    return out
end

-- The centre line stretches of the cell key `key` (those within LANE_REACH of it), in the order of the data; nil
-- where none.
function logic.lanesAt(zone, key)
    local ix = zone._index
    ix.laneCells = ix.laneCells or {}
    return logic.cellItems(zone, ix.lanes, key, ix.laneCells)
end

-- Cells whose tables were built by the same records share one table (2026-10-30, the user: memory; Elwynn's 20933
-- cells of rooms by floor hold 1117 different ones, its 11200 floor cells 1429): `sig` holds per cell key the
-- records that built its table, in their order, so a shared table is built exactly as each of its cells' own
-- (the same pieces, lists and order; pairs() goes through it the same way). Nothing writes into these tables
-- after the unpack.
local function shareCells(cells, sig)
    local shared = {}
    for key, t in pairs(cells) do
        local s = table.concat(sig[key], ";")
        local got = shared[s]
        if got then
            cells[key] = got
        else
            shared[s] = t
        end
    end
end

-- Row `r` (1-based) of the grid as runs: `starts` (the first column of each run) and `values`; nil past the grid.
-- Made from the row's text (zone.grid, palette values with counts: "3180113*4,0*12") when first read, and kept
-- for the ROWS_KEPT rows read last (2026-10-30, the user: memory; all of Elwynn's 528 rows as runs held 1.6 MB,
-- the text 0.5 MB).
logic.ROWS_KEPT = 64
function logic.gridRow(zone, r)
    local ix = zone._index
    local row = ix.rows[r]
    if row then
        return row
    end
    local text = zone.grid[r]
    if text == nil then
        return nil
    end
    local starts, values = {}, {}
    local col = 0
    for token in text:gmatch("[^,]+") do
        local v, n = token:match("^(%d+)%*(%d+)$")
        if v == nil then
            v, n = token, 1
        end
        starts[#starts + 1] = col
        values[#values + 1] = tonumber(v)
        col = col + tonumber(n)
    end
    if ix.rowsKept >= logic.ROWS_KEPT then
        ix.rows, ix.rowsKept = {}, 0
    end
    row = { starts = starts, values = values }
    ix.rows[r] = row
    ix.rowsKept = ix.rowsKept + 1
    return row
end

logic.LANE_REACH = 12 -- yd; farther from every centre line the grid alone decides
logic.FEET_APART = 8 -- yd; two feet of one climb closer than this are one guidance target

-- Unpacks a zone on entry (once; `locale`: the client's language): a registered zone's JSON text
-- decoded and expanded into the model (store.lua), then the grid rows as runs, and the flat lists
-- of the data as named records with lookups per grid cell, all in zone._index.
function logic.unpack(zone, locale)
    if zone._index then
        return
    end
    -- the walk graph's surfaces per layer (format 5, the walk-graph tracker; tracker.lua), before the layers are
    -- built from the data (unpackLayer takes its layer's): the piece tracker of before runs where the data has none
    if zone.parent == nil then   -- (a layer, unpacked through here too, keeps the surf unpackLayer gave it)
        local S = WowVision.surroundingsData and WowVision.surroundingsData.surfaces
        zone.surfaces = S and S[zone.key] or nil
        zone.surf = zone.surfaces and zone.surfaces.zone or nil
    end
    if zone.json then
        local data = logic.decodeJson(zone.deflated and logic.inflate(zone.json) or zone.json)
        assert(type(data) == "table", "the surroundings data of " .. tostring(zone.key) .. " could not be read")
        logic.expand(zone, data, locale)
    end
    prepareWords(zone, locale)
    local ix = {}
    zone._index = ix
    -- the numbered room names said otherwise (logic.spokenText), the longest first
    ix.spokenKeys = {}
    for name in pairs(zone.spoken or {}) do
        ix.spokenKeys[#ix.spokenKeys + 1] = name
    end
    table.sort(ix.spokenKeys, function(a, b)
        return #a > #b or (#a == #b and a < b)
    end)

    -- the grid's rows as runs, made from the row's text when first read (logic.gridRow)
    ix.rows, ix.rowsKept = {}, 0

    ix.places = {}
    for id, p in pairs(zone.places) do
        ix.places[id] = { kind = p[1], label = p[2], road = p[3], deadEnd = p.deadEnd or false, of = p.of, plain = p.plain }
    end
    -- a climb's name said from its top (zone.climbDown: its place, the place of that name; the
    -- export's climb_names): "stairs to the cellar" from the kitchen the stairs lead up to
    local down = zone.climbDown or (zone.parent and zone.parent.climbDown)
    for k = 1, #(down or {}) - 1, 2 do
        if ix.places[down[k]] then
            ix.places[down[k]].down = down[k + 1]
        end
    end

    -- structures with drop edges: the structure on each of their floor cells
    ix.struct = {}
    eachCellTriple(zone, zone.structCells, function(key, struct)
        ix.struct[key] = struct
    end)
    -- the city water edges are a structure of their own: no wall one bumps into
    ix.waterStructs = {}
    for _, struct in ipairs(zone.waterStructs or {}) do
        ix.waterStructs[struct] = true
    end
    -- the floor pieces (one rule for every floor over or under another): per cell the pieces
    -- present besides the ground with their values (floorCells: row, col, piece, value), the
    -- cells where the ground has no floor (noGround), and the joins (a, b, x, y, angle: where
    -- piece a meets piece b, the direction from a into b; a 0 the ground, -1 a building's door;
    -- angle -1 none, -2 no point): per cell the joins with a point, per piece the pieces it joins
    ix.floorCells = {}
    ix.placePieces = {}
    local placeCounts = {}
    local cellSig = {}
    eachRecord(zone.floorCells, 4, function(r, c, piece, value)
        local key = r * zone.cols + c
        ix.floorCells[key] = ix.floorCells[key] or {}
        ix.floorCells[key][piece] = value
        cellSig[key] = cellSig[key] or {}
        table.insert(cellSig[key], piece .. "=" .. value)
        -- (per piece the count of each place on it: below, the piece's own place)
        local place = logic.placeOf(value)
        local counts = placeCounts[piece] or {}
        placeCounts[piece] = counts
        counts[place] = (counts[place] or 0) + 1
    end)
    shareCells(ix.floorCells, cellSig)
    -- per place the floor pieces whose own place it is (most of their cells): on a climb's own
    -- piece it is said by its name (logic.downPlace; the Abbey's gallery carries the ramp's place
    -- on three cells at the ramp's top, and is no part of the ramp)
    for piece, counts in pairs(placeCounts) do
        local best, most = nil, 0
        for place, n in pairs(counts) do
            if n > most or (n == most and place < best) then
                best, most = place, n
            end
        end
        ix.placePieces[best] = ix.placePieces[best] or {}
        ix.placePieces[best][piece] = true
    end
    ix.noGround = {}
    eachRecord(zone.noGround, 2, function(r, c)
        ix.noGround[r * zone.cols + c] = true
    end)
    -- (joinPoints: per pair of pieces the points where they meet, x, y flat, both ways)
    ix.joinAt, ix.joined, ix.joinPoints = {}, {}, {}
    eachRecord(zone.joins, 5, function(a, b, x, y, angle)
        if angle ~= -2 then
            local r, c = logic.cellOf(zone, x, y)
            addToBucket(ix.joinAt, r * zone.cols + c, { a = a, b = b, x = x, y = y, angle = angle >= 0 and angle or nil })
        end
        if a >= 0 then
            ix.joined[a] = ix.joined[a] or {}
            ix.joined[a][b] = true
            ix.joined[b] = ix.joined[b] or {}
            ix.joined[b][a] = true
            if angle ~= -2 then
                ix.joinPoints[a] = ix.joinPoints[a] or {}
                ix.joinPoints[b] = ix.joinPoints[b] or {}
                local list = ix.joinPoints[a][b] or {}
                ix.joinPoints[a][b], ix.joinPoints[b][a] = list, list
                list[#list + 1] = x
                list[#list + 1] = y
            end
        end
    end)
    -- the liquid pieces (water, city water, lava: a liquid's surface is a floor piece like any
    -- other, and swimming is the one height the game tells): piece -> kind (1 water, 2 city
    -- water, 3 lava)
    ix.liquids = {}
    eachRecord(zone.liquids, 2, function(piece, kind)
        ix.liquids[piece] = kind
    end)
    ix.floor = 0
    -- the rooms by their floor (indoor layers, floorRooms: row, col, piece, room): per cell, per
    -- floor piece the rooms whose floor that piece is there (rooms.lua floorRoomsAt); nil in data
    -- without them
    if zone.floorRooms then
        -- (floorRoomIds: the rooms with floor in the records)
        ix.floorRooms, ix.floorRoomIds = {}, {}
        local roomSig = {}
        eachRecord(zone.floorRooms, 4, function(r, c, piece, room)
            ix.floorRoomIds[room] = true
            local key = r * zone.cols + c
            local byPiece = ix.floorRooms[key] or {}
            ix.floorRooms[key] = byPiece
            local list = byPiece[piece] or {}
            byPiece[piece] = list
            list[#list + 1] = room
            roomSig[key] = roomSig[key] or {}
            table.insert(roomSig[key], piece .. ":" .. room)
        end)
        shareCells(ix.floorRooms, roomSig)
    end
    -- the cells where a hall the game calls outdoors lies on the ground (rooms.lua inHallFloor)
    ix.hallGround = {}
    eachRecord(zone.hallGround, 2, function(r, c)
        ix.hallGround[r * zone.cols + c] = true
    end)
    -- drop edges with a box each, so the edge search skips the far ones (cities have hundreds)
    ix.edges = {}
    for i, e in ipairs(zone.edges or {}) do
        local points = {}
        local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
        for k = 6, #e - 1, 2 do
            points[#points + 1] = e[k]
            points[#points + 1] = e[k + 1]
            x0, x1 = math.min(x0, e[k]), math.max(x1, e[k])
            y0, y1 = math.min(y0, e[k + 1]), math.max(y1, e[k + 1])
        end
        ix.edges[i] = {
            struct = e[1], facing = e[2], drop = e[3], into = e[4], piece = e[5], points = points,
            drops = e.d, -- the depth per point (a ramp's side edge: 2 yd at the foot, 9 at the top), or nil
            -- the floor piece it lies on (0 the ground) and the piece its drop lands on (walking
            -- over it puts the player there)
            floor = e.l, under = e.u,
            box = { x0, x1, y0, y1 },
        }
    end

    -- the feet of ramps and stairs joined to the way below (export.join_climbs): guidance targets
    -- on the way, as entrances are
    -- (a climb with two line ends at its foot has two feet a yard or two apart: one target, else
    -- the guidance named the ramp to Thane's Boots anew at every step, replay of 2026-10-01)
    -- x, y, the climb's cell value, the line's bearing up the climb in degrees (0 north, clockwise):
    -- the way through at the foot, finer than the compass word, and the floor piece at the foot (0 the
    -- ground): guided to only from that floor
    ix.climbFeet = {}
    ix.footFloors = {}
    eachRecord(zone.climbFeet, 5, function(x, y, value, bearing, floor)
        for _, f in ipairs(ix.climbFeet) do
            if f.value == value and logic.dist2(f.x, f.y, x, y) <= logic.FEET_APART ^ 2 then
                return
            end
        end
        ix.climbFeet[#ix.climbFeet + 1] = { x = x, y = y, value = value, bearing = bearing, floor = floor }
        -- (per place the floors its feet stand on: from there it is said by its name)
        local place = logic.placeOf(value)
        ix.footFloors[place] = ix.footFloors[place] or {}
        ix.footFloors[place][floor] = true
    end)
    -- the tops of ramps and stairs (export.climb_ends, data since trial L4): x, y, the top flight's cell value, the
    -- way on DOWN that flight (degrees), the floor piece at the top; guided to from that floor as a foot is from its
    -- own (user 2026-10-20: tops and feet alike). Data without them: nil, the top is worked out (logic.atClimbTop)
    ix.climbTops = zone.climbTops and {} or nil
    ix.topFloors = {}
    eachRecord(zone.climbTops, 5, function(x, y, value, bearing, floor)
        ix.climbTops[#ix.climbTops + 1] = { x = x, y = y, value = value, bearing = bearing, floor = floor, top = true }
        local place = logic.placeOf(value)
        ix.topFloors[place] = ix.topFloors[place] or {}
        ix.topFloors[place][floor] = true
    end)
    -- the flights with a wall along one side and a drop along the other (export.climb_sides): per
    -- floor piece the point at its top on the wall side its way up is said toward (setting
    -- wallSide), its place value and its way up (degrees)
    ix.climbAims = {}
    eachRecord(zone.climbAims, 5, function(piece, value, x, y, up)
        ix.climbAims[piece] = { piece = piece, value = value, x = x, y = y, up = up }
    end)

    ix.exits = {}
    eachRecord(zone.exits, 4, function(x, y, width, out)
        -- out: the angle one climbs out toward, -1 unknown
        ix.exits[#ix.exits + 1] = { x = x, y = y, width = width, out = out >= 0 and out or nil, i = #ix.exits + 1 }
    end)
    -- per way out the floor piece it leads out of (zone.exitFloors: a liquid's, the moat's; 0 or
    -- none: the ground)
    for i, fl in ipairs(zone.exitFloors or {}) do
        if ix.exits[i] then
            ix.exits[i].floor = fl
        end
    end
    -- per way out its group (zone.exitGroups): the stretches of one way out (a long shore) share
    -- one, so the guidance names it once while it follows the nearest stretch
    for i, g in ipairs(zone.exitGroups or {}) do
        if ix.exits[i] then
            ix.exits[i].group = g
        end
    end
    -- neighbouring cells of two squares with no walkable crossing between them (decided offline
    -- with the heights): no border between the two squares
    ix.noContact = {}
    local cells = zone.rows * zone.cols
    eachRecord(zone.noContact, 4, function(r1, c1, r2, c2)
        local a, b = r1 * zone.cols + c1, r2 * zone.cols + c2
        ix.noContact[a * cells + b] = true
        ix.noContact[b * cells + a] = true
    end)

    -- objects, in the buckets of the blocks of every cell their footprint's circle touches (addToBlocks)
    ix.objects = {}
    eachRecord(zone.objects, 7, function(x, y, halfLength, halfWidth, angle, name, room)
        local o = {
            x = x, y = y, halfLength = halfLength / 10, halfWidth = halfWidth / 10, angle = math.rad(angle),
            name = zone.objectNames and zone.objectNames[name], room = room,
        }
        addToBlocks(zone, ix.objects, x, x, y, y, math.sqrt(halfLength ^ 2 + halfWidth ^ 2) / 10, o)
    end)

    -- centre line stretches, in the buckets of the blocks of every cell within LANE_REACH of them (addToBlocks; a
    -- cell's stretches: logic.lanesAt)
    ix.lanes = {}
    -- 10 fields each: the ends, the cell value, the widths per side (enter and leave left of the stretch's
    -- direction, then right: a wall on one side does not narrow the other) and the raised piece it runs on
    local order = {}
    eachRecord(zone.lanes, 10, function(x1, y1, x2, y2, value, enter, leave, enter2, leave2, piece)
        local lane = {
            x1 = x1, y1 = y1, x2 = x2, y2 = y2, value = value, kind = logic.kindOf(zone, value),
            enter = enter / 10, leave = leave / 10, enter2 = enter2 / 10, leave2 = leave2 / 10, piece = piece,
        }
        addToBlocks(zone, ix.lanes, math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2),
            logic.LANE_REACH, lane)
        order[#order + 1] = lane
    end)
    -- the floor pieces left beyond their own lines (every ramp's and stairs': edges.lua
    -- onOwnLines); nil in data before 2026-10-16
    -- data whose lines of flights, landings and platforms are the cheapest way through the piece (the export's
    -- WV_LINES=path, 2026-10-18): the turn key and the guidance to a foot follow them (lanes.lua, texts.lua)
    ix.pathLines = zone.pathLines == true
    ix.lineFloors = {}
    for _, piece in ipairs(zone.lineFloors or {}) do
        ix.lineFloors[piece] = true
    end
    -- the free ends of those pieces' lines (a stretch end no other stretch of its piece goes on
    -- from): the piece is not stepped onto beyond them (edges.lua pastEnd)
    local ends = {}
    local function endKey(lane, x, y)
        return string.format("%d %.1f %.1f", lane.piece, x, y)
    end
    for _, lane in ipairs(order) do
        if ix.lineFloors[lane.piece] then
            for _, k in ipairs({ endKey(lane, lane.x1, lane.y1), endKey(lane, lane.x2, lane.y2) }) do
                ends[k] = (ends[k] or 0) + 1
            end
        end
    end
    for _, lane in ipairs(order) do
        if ix.lineFloors[lane.piece] then
            lane.free1 = ends[endKey(lane, lane.x1, lane.y1)] == 1
            lane.free2 = ends[endKey(lane, lane.x2, lane.y2)] == 1
        end
        -- a path-line data's line across a landing or platform between flights (gated to a piece that is no
        -- lineFloor) is a way through for the turn key and the guidance only, never a way the place is said by
        -- (the Abbey gallery became "Die Haupthalle, erster Stock" bare, its ramps unsaid, walk 2026-10-18 07:52)
        lane.guideOnly = ix.pathLines and lane.piece > 0 and not ix.lineFloors[lane.piece] or nil
    end
    -- since 2026-10-14 the heading of the way ahead along each stretch (the export's
    -- lane_headings, for the turn key): per stretch in order the number of samples, then per
    -- sample (the stretch cut in that many equal parts, one at each part's middle) the bearing
    -- toward its end and back (degrees clockwise from north, -1 none)
    local h, list = 1, zone.laneHeadings
    if list then
        for _, lane in ipairs(order) do
            local n = list[h]
            if n == nil then
                break
            end
            lane.headings = { unpack(list, h + 1, h + 2 * n) }
            h = h + 1 + 2 * n
        end
    end

    ix.interiors = {}
    for i, f in ipairs(zone.interiors or {}) do
        -- city: a city's own complex or a map that is one building (Ironforge, the Deeprun Tram),
        -- named after its zone, which the player knows: a room in it is said without that name
        -- wall: the place its wall is said by where its name is only "building of <place>"
        ix.interiors[i] = { name = f[1], ox = f[2], oy = f[3], scale = f[4], m00 = f[5], m01 = f[6], m10 = f[7], m11 = f[8],
            city = f.c == 1, wall = f.w }
    end
    ix.rooms, ix.roomIds = {}, {}
    for i, room in ipairs(zone.rooms or {}) do
        ix.roomIds[i] = i
        -- axis: the way the room runs (an axis angle, 0..179) when it is long and narrow; winding: its
        -- floor winds up turning left (1) or right (-1); floor: sq yd; named: a name of its own (a shop);
        -- hallMap: the game calls the room outdoors (IsIndoors() false), the UI map one stands on in it;
        -- district: the district a city complex's room names (its English name), short: the name
        -- without it ("canal 3" for "canal, Trade Quarter 3"); subzone: a hall's area as the game
        -- names where one stands in it; niche: a city's small dead end (no guidance into
        -- it); zonePieces: the zone's floor pieces a hall lies on (0 the ground; rooms.lua
        -- inHallFloor); place: the key of a place a city's
        -- ways join; wayA, wayB: a way's two places, atA, atB: its names said at each ("passage to
        -- War Quarter" in the canal)
        ix.rooms[i] = {
            interior = room[1], name = room[2], kind = room[3], boxes = room[4], outline = room[5],
            entrance = room.entrance or false, axis = room.a and room.a >= 0 and room.a or nil, winding = room.w,
            floor = room.f or 0,
            named = room.s == 1, hallMap = room.g, district = room.d, short = room.sn,
            place = room.e, wayA = room.wa, wayB = room.wb, atA = room.ta, atB = room.tb,
            subzone = room.ar, niche = room.ni == 1, zonePieces = room.zp and {},
        }
        for _, p in ipairs(room.zp or {}) do
            ix.rooms[i].zonePieces[p] = true
        end
    end
    -- doors between rooms (0 = outside), and per room its doors and the rooms they join
    ix.doors, ix.doorsOf, ix.neighbours = {}, {}, {}
    for i, d in ipairs(zone.doors or {}) do
        -- half: half the opening's width along its plane (0 unknown)
        local door = { a = d[1], b = d[2], interior = d[3], x = d[4], y = d[5], nx = d[6], ny = d[7], side = d[8], half = d[9] }
        -- the floor piece its sill lies on (doorFloors; -1 none, nil older data): an entrance is guided
        -- to only from it (rooms.lua nearestEntrance)
        local fl = zone.doorFloors and zone.doorFloors[i]
        door.floor = fl and fl >= 0 and fl or nil
        -- -2: no floor of this grid at its sill or within jump height under it (an opening high in a
        -- wall: the Abbey's belfry, said as a way out on every floor, walk 2026-10-17 11:20): never
        -- said from it; it stays a doorway the player passes (falling or jumping out)
        door.unsaid = fl == -2 or nil
        -- a door between two pieces of one room (doorVia): the room's own doorway reached through
        -- it from a into b (viaA) and from b into a (viaB), door numbers; nil none or older data
        local va, vb = zone.doorVia and zone.doorVia[2 * i - 1], zone.doorVia and zone.doorVia[2 * i]
        door.viaA = va and va > 0 and va or nil
        door.viaB = vb and vb > 0 and vb or nil
        ix.doors[i] = door
        for _, pair in ipairs({ { door.a, door.b }, { door.b, door.a } }) do
            local room, other = pair[1], pair[2]
            ix.neighbours[room] = ix.neighbours[room] or {}
            ix.neighbours[room][other] = true
            ix.doorsOf[room] = ix.doorsOf[room] or {}
            table.insert(ix.doorsOf[room], door)
        end
    end

    ix.regionOf = {} -- squares found so far, per cell key

    -- stops (where one waits for a ship, zeppelin, lift or tram): {kind, destination, room, cells,
    -- segments, {floor pieces; 0 the ground: the stop counts only on one of them, the zeppelin
    -- tower's top was said at its foot, 2026-10-06; a stop in a room with none listed counts on
    -- every floor of its room (anyFloor)}}; the stops on each cell
    ix.stops, ix.stopCells = {}, {}
    for i, s in ipairs(zone.stops or {}) do
        local stop = { kind = s[1], to = s[2] or "", room = s[3] or 0, floors = {}, targets = {} }
        stop.anyFloor = stop.room ~= 0 and (type(s[6]) ~= "table" or #s[6] == 0)
        for _, fl in ipairs(type(s[6]) == "table" and s[6] or { 0 }) do
            stop.floors[fl] = true
        end
        eachRecord(s[5], 4, function(x1, y1, x2, y2)
            stop.targets[#stop.targets + 1] = { x1, y1, x2, y2 }
        end)
        ix.stops[i] = stop
        eachRecord(s[4], 2, function(r, c)
            addToBucket(ix.stopCells, r * zone.cols + c, i)
        end)
    end

    if zone.indoor then
        ix.layer = logic.unpackLayer(zone, zone.indoor, "/indoor")
    end
    if zone.indoorIn then
        ix.layerIn = logic.unpackLayer(zone, zone.indoorIn, "/indoorIn")
    end
end

-- An indoor layer (zone.indoor, zone.indoorIn): the big halls of a city (Ironforge's, the Undercity
-- quarters) cut into pieces like its streets, on a grid of their own, with centre lines and the
-- edges of their floors (lava, water). Unpacked as a zone of its own that shares the frame, the
-- words, the places and the rooms of `zone`; `covered` is the set of rooms whose floor it holds;
-- its entrances are the doorways from those rooms into the others (see layerEntrances). `src`: the
-- layer's data, `suffix` its key after the zone's.
function logic.unpackLayer(zone, src, suffix)
    -- a grid of its own where the data gives one (the halls the game calls indoors and the
    -- buildings with floors over each other: cells half the zone's), else the zone's
    local own = src.cell ~= nil
    local layer = {
        key = zone.key .. suffix, label = zone.label, map = zone.map,
        top = own and src.top or zone.top, left = own and src.left or zone.left,
        cell = own and src.cell or zone.cell, rows = own and src.rows or zone.rows, cols = own and src.cols or zone.cols, dirs = zone.dirs, dirsClock = zone.dirsClock,
        compass = zone.compass, axes = zone.axes, spokenAxes = zone.spokenAxes, floors = zone.floors, places = zone.places, grid = src.grid or {},
        spoken = zone.spoken,
        lanes = src.lanes, laneHeadings = src.laneHeadings, lineFloors = src.lineFloors, pathLines = src.pathLines, noContact = src.noContact, structs = src.structs, waterStructs = src.waterStructs,
        structCells = src.structCells, edges = src.edges, exits = src.exits, exitFloors = src.exitFloors, exitGroups = src.exitGroups,
        interiors = zone.interiors, rooms = zone.rooms,
        -- its floor pieces (a gallery, the moat under the walkways, a building's floors), as the
        -- zone's: one rule for every floor over or under another
        floorCells = src.floorCells, noGround = src.noGround, joins = src.joins, liquids = src.liquids,
        -- the rooms by their floor: per cell and piece the rooms whose floor it is
        floorRooms = src.floorRooms,
        -- per door the layer's floor piece its sill lies on
        doorFloors = src.doorFloors,
        -- the feet of its climbs and their wall sides, as the zone's (one rule for every grid)
        climbFeet = src.climbFeet, climbTops = src.climbTops, climbAims = src.climbAims,
        -- on a grid of its own (cells of 2 yd) a doorway of 2 yd is one border cell and worth saying
        mouthMin = own and 1 or nil,
        doors = zone.doors, doorVia = zone.doorVia, _worded = true, _running = zone._running, _toward = zone._toward, parent = zone,
        -- its walk-graph surfaces (format 5), where the data has them
        surf = zone.surfaces and zone.surfaces[suffix == "/indoor" and "indoor" or "indoorIn"] or nil,
    }
    logic.unpack(layer)
    local covered = {}
    for _, id in ipairs(src.rooms or {}) do
        covered[id] = true
    end
    layer._index.covered = covered
    -- the floor piece the player is on in it (edges.lua updateFloor), its own
    logic.setFloor(layer, 0)
    return layer
end

-- The indoor layer of a zone (unpacked), or nil. A city has two where the game says so: the halls
-- it calls outdoors (IsIndoors() false: Ironforge's Great Forge and Commons, the Undercity) and the
-- big halls it calls indoors (the cavern under Ironforge's throne room); where they lie on top of
-- each other the game's word tells the floors apart (user's walks 2026-10-02: on the forge floor the
-- cavern's lava and doorways 60 yd below, on the stairs down the forge's lava walk). `indoors`:
-- IsIndoors(); nil or a city with one layer: that one.
function logic.layer(zone, indoors)
    local ix = zone._index
    if ix == nil then
        return nil
    end
    if indoors and ix.layerIn then
        return ix.layerIn
    end
    return ix.layer or (indoors == nil and ix.layerIn) or nil
end

-- Frees the unpacked data when the player leaves the zone; a registered zone keeps only its frame
-- and its JSON text (logic.ZONE_HEADER).
function logic.pack(zone)
    zone._index = nil
    if zone.json then
        for key in pairs(zone) do
            if not logic.ZONE_HEADER[key] then
                zone[key] = nil
            end
        end
    end
end

-- Place texts ------------------------------------------------------------------------------------

-- The axis angle a direction code says ("running %s", 0..179), or nil.
local function axisOfCode(zone, code)
    if math.floor(code / 1000) == zone._running then
        return code % 1000
    end
end

-- The axis angle (0..179) a cell value says, or nil.
function logic.axisOf(zone, value)
    return axisOfCode(zone, value % logic.CODE)
end

-- The angle a ramp's or stairs' cell value rises toward ("up to the northeast"), or nil.
function logic.riseOf(zone, value)
    local code = value % logic.CODE
    if code == 0 or axisOfCode(zone, code) or not logic.CLIMBS[logic.kindOf(zone, value)] then
        return nil
    end
    return code % 1000
end

-- The direction a cell value says ("northwest to southeast", "up to the northeast"), or nil.
function logic.directionText(zone, value)
    local code = value % logic.CODE
    if code == 0 then
        return nil
    end
    local axis = axisOfCode(zone, code)
    if axis then
        -- an axis without its template: "road, northwest to southeast"
        return logic.axisWords(zone, axis)
    end
    -- a ramp or stairs runs like a street: its axis, the same walking up or down (user 2026-10-04:
    -- "up to the south" while going down the Brill tavern's cellar stairs to the north; with rooms
    -- and places named, "stairs to the upstairs landing up at 3" was a word monster)
    if logic.CLIMBS[logic.kindOf(zone, value)] then
        return logic.axisWords(zone, code % 1000 % 180)
    end
    local template = logic.dirTemplate(zone, math.floor(code / 1000))
    if template then
        return string.format(template, logic.dirWord(zone, code % 1000))
    end
end

-- Named floors (zone.floors, per floor: its word, the name of its own room, the stairs up to it,
-- those stairs said plainly: "Obergeschoss", "Obergeschoss", "Treppe Richtung Obergeschoss",
-- "Treppe"): said once, as a building's name is (user 2026-10-04: "Obergeschoss" three times in one
-- line upstairs in the Brill tavern). The floor a label lies on (an index into zone.floors) and
-- the label without it: a room on it ("Raum Südost, Obergeschoss" -> "Raum Südost"), the stairs up
-- to it ("Treppe"), the floor's own room (no shorter form: nil); nil for any other label.
function logic.floorOf(zone, label)
    if label == nil then
        return nil
    end
    local floors = zone.floors or {}
    -- one floor may have several entries (reached by stairs and by a ramp: a structure's
    -- "platform" up a ramp at one tower and up stairs at another): the floor is its first entry
    local function first(i)
        for j = 1, i do
            if floors[j][2] == floors[i][2] then
                return j
            end
        end
        return i
    end
    for i, f in ipairs(floors) do
        if label == f[2] then
            return first(i), nil
        elseif label == f[3] then
            return first(i), f[4]
        end
        local tail = ", " .. f[1]
        if #label > #tail and label:sub(-#tail) == tail then
            return first(i), label:sub(1, -#tail - 1)
        end
    end
    return nil
end

-- A label as said on floor `floor` (an index into zone.floors, or nil): without the floor where it
-- lies on that floor.
function logic.floorLabel(zone, label, floor)
    if floor == nil then
        return label
    end
    local on, bare = logic.floorOf(zone, label)
    if on == floor and bare then
        return bare
    end
    return label
end

-- A room's name (or a place or climb named after a room) as said: the data keeps the numbered
-- names as the rooms' identity ("mine 3"), said without the number where the zone's `spoken`
-- gives that ("mine"; user 2026-10-07: the numbers mean nothing by ear, the directions in a list
-- tell the rooms apart).
function logic.spokenName(zone, name)
    return name and zone.spoken and zone.spoken[name] or name
end

-- A text as said: a numbered room name still in it (a label said as it is) said as spokenName, where
-- it stands as a name of its own (not "mine 30" for "mine 3").
function logic.spokenText(zone, text)
    local keys = text and zone and zone._index and zone._index.spokenKeys
    if keys == nil or #keys == 0 or not text:find("%d") then
        return text
    end
    for _, name in ipairs(keys) do
        local from = 1
        while true do
            local a, b = text:find(name, from, true)
            if a == nil then
                break
            end
            local before, after = text:sub(a - 1, a - 1), text:sub(b + 1, b + 1)
            if (a == 1 or before:find("[%s,(]")) and (after == "" or after:find("[%s,%.;:)]")) then
                local said = zone.spoken[name]
                text = text:sub(1, a - 1) .. said .. text:sub(b + 1)
                from = a + #said
            else
                from = b + 1
            end
        end
    end
    return text
end

-- The structure a place belongs to (its name, as said), or nil: by place id, by cell value.
function logic.ownerOfPlace(zone, id)
    local p = id and zone._index.places[id]
    return p and p.of or nil
end

function logic.ownerOf(zone, value)
    return value and value ~= 0 and logic.ownerOfPlace(zone, logic.placeOf(value)) or nil
end

-- The floor of the place at a cell value (see floorOf), or nil.
function logic.floorOfValue(zone, value)
    local p = value and value ~= 0 and zone._index.places[logic.placeOf(value)]
    return p and logic.floorOf(zone, p.label) or nil
end

-- The text of a cell value: the place label, and with `withDirection` its direction and its
-- nearest road ("Goldshire road to the north"; left out with `noNearRoad`, when the caller says
-- where the road is itself). `floor` (optional): the named floor the player is on or comes from,
-- whose name the label leaves out (floorLabel).
function logic.describe(zone, value, withDirection, noNearRoad, floor, here)
    local p = zone._index.places[logic.placeOf(value)]
    if p == nil then
        return nil
    end
    local down = logic.downPlace(zone, logic.placeOf(value))
    local text = logic.expandDirs(zone, logic.floorLabel(zone, logic.spokenName(zone, (down or p).label), floor))
    -- a place of a structure (a tower's platform, its stairs) says the structure's name where the
    -- player is not on it yet: `here`, the structure of the place the player is on or comes from
    -- (nil: none, or the name is always said, as Alt-L says a room's building); inside the
    -- structure its places go without it, as a building's rooms do (user 2026-10-06: "Treppe
    -- Richtung zweiter Stock" is enough up in the zeppelin tower)
    if p.of and p.of ~= here then
        text = string.format(zone.ofTemplate or "%s of %s", text, p.of)
    end
    local direction = withDirection and logic.directionText(zone, value)
    if direction then
        text = text .. ", " .. direction
    end
    if withDirection and p.road and not noNearRoad then
        text = text .. ", " .. logic.expandDirs(zone, p.road)
    end
    return text
end

-- Outdoor keys ------------------------------------------------------------------------------------
-- What the entry rule compares outdoors: the place id; a piece of a way with one direction (a
-- road, a city street or walk: TURN_KINDS) "r<place>:<axis key>" and a canal piece "c<place>:<axis
-- key>" are keyed with their spoken direction (the axis as the current words tell it apart), so a
-- bend counts like a new place, said with its direction only (sameWay); streets follow the road
-- rules.

-- `previous`: the key the player is on now (optional). The same piece whose axis has moved into
-- the next word but stays within KEY_STICK degrees of the word said keeps that key: a street whose
-- heading hovers about a word boundary (the data carries each run's heading to the degree) is not
-- a new place at every run; it becomes one once the heading is clearly in the next word.
logic.KEY_STICK = 10 -- degrees beyond the spoken word's half step

-- Degrees between two direction words: an hour with the clock, else a compass word.
function logic.wordStep()
    return logic.clock and 30 or 45
end

function logic.outdoorKey(zone, value, previous)
    if value == 0 then
        return nil
    end
    local kind = logic.kindOf(zone, value)
    if kind == "canal" or logic.TURN_KINDS[kind] then
        local axis = logic.axisOf(zone, value)
        local prefix = (kind == "canal" and "c" or "r") .. logic.placeOf(value) .. ":"
        -- a ramp or stairs: each flight a piece of its own by the way it rises, so the turn on a
        -- landing is said (the Brill tavern's stairs go up north, then up south: four times into
        -- the landing's wall in silence, walk 2026-10-03 23:55); said with its axis (directionText)
        local rise = axis == nil and logic.riseOf(zone, value)
        if rise then
            return prefix .. "u" .. logic.dirKey(rise)
        end
        if axis and type(previous) == "string" and previous:sub(1, #prefix) == prefix then
            local said = tonumber(previous:sub(#prefix + 1))
            local step = logic.wordStep()
            if said and said ~= logic.axisKey(axis) then
                local gap = math.abs(axis - said * step) % 180
                if math.min(gap, 180 - gap) <= step / 2 + logic.KEY_STICK then
                    return previous
                end
            end
        end
        return prefix .. (axis and logic.axisKey(axis) or "")
    end
    return logic.placeOf(value)
end

-- A key of a way with one direction (a road, street or walk piece).
function logic.isWayKey(key)
    return type(key) == "string" and key:sub(1, 1) == "r"
end

-- Is the cell value `value` another piece of the way the player is on (the key `previous`, a road,
-- street, walk or canal keyed with its direction), and was that way's name the last one said
-- (`named`, a place id)? Then only the direction changes: the name was said on stepping onto it
-- (user 2026-10-02: the name once, then only the direction, until one leaves the way or steps onto
-- one with another name). After the next piece ahead was named as another way (a ramp beside the
-- street), a bare direction would sound like that one's.
-- With `zone`: a plain ramp or stairs (named by its kind alone) straight after a ramp or stairs,
-- while a climb was the last named, is the same way too: a winding climb's flights are said
-- "stairs" and "ramp" by turns as their slopes come out (the Crusader's Outpost tower, four names
-- in 8 yd, walk 2026-10-14 12:23); the direction tells the turn.
function logic.sameWay(value, previous, named, zone)
    local place = logic.placeOf(value)
    if type(previous) ~= "string" or value == 0 then
        return false
    end
    if logic.keyPlace(previous) == place and named == place then
        return true
    end
    if zone == nil or named == nil then
        return false
    end
    local p = logic.place(zone, place)
    local before, last = logic.place(zone, logic.keyPlace(previous)), logic.place(zone, named)
    return p ~= nil and p.plain and before ~= nil and logic.CLIMBS[before.kind]
        and last ~= nil and logic.CLIMBS[last.kind] or false
end

-- The place id of an outdoor key (nil for nil).
function logic.keyPlace(key)
    if type(key) == "string" then
        return tonumber(key:match("^[rc](%d+)")) or 0
    end
    return key
end

function logic.keyLabel(zone, key)
    local p = key and logic.place(zone, logic.keyPlace(key))
    return p and p.label
end

-- Is `value` a climb's whose floor piece lies in the cell (with `around`, or the 8 around it),
-- while the player is on the ground?
local function climbPieceHere(zone, r, c, value, around)
    local ix = zone._index
    if not tostring(zone.key):match("/indoor$") or (ix.floor or 0) ~= 0 or not logic.CLIMBS[logic.kindOf(zone, value)] then
        return false
    end
    local place = logic.placeOf(value)
    local key = r * zone.cols + c
    for _, d in ipairs(around and logic.cellOffsets(zone, r, c) or (logic.inGrid(zone, r, c) and { 0 }) or {}) do
        for _, pv in pairs(ix.floorCells[key + d] or {}) do
            if logic.placeOf(pv) == place then
                return true
            end
        end
    end
    return false
end

-- The outdoor cell value at a position, on the floor piece the player is on: near a centre line
-- what the line decides (`onWay`: the player is on a way now, see laneValue); on a liquid's piece
-- the liquid's own (a centre line is a way's, on its floor: the street beside the canal is no
-- place of the swimmer's). Returns the value (0 = no data) and whether a lane decided it.
function logic.outdoorValue(zone, x, y, onWay)
    -- (the ground beside a ramp in the halls, painted with its name, took the name of the ground
    -- around until 2026-10-16: the climb's own lines and floor piece say it now, bug 41)
    local value, r, c = logic.valueAt(zone, x, y)
    if value == 0 or logic.liquidKind(zone, zone._index.floor) then
        return value, false
    end
    -- (so the line joining a climb's foot to the ways on the ground: it names the climb along
    -- its foot, a yard wide)
    local lane, decided = logic.laneValue(zone, x, y, value, onWay)
    if lane ~= value and climbPieceHere(zone, r, c, lane, true) then
        return value, false
    end
    return lane, decided
end

-- The liquid kind of a floor piece (1 water, 2 city water, 3 lava), or nil for floor.
function logic.liquidKind(zone, piece)
    return piece and zone._index.liquids[piece] or nil
end

-- The kind of a liquid lying in the cell `key` (one of its pieces there), or nil.
function logic.liquidIn(zone, key)
    local ix = zone._index
    for piece in pairs(ix.floorCells[key] or {}) do
        if ix.liquids[piece] then
            return ix.liquids[piece]
        end
    end
    return nil
end

-- The entry rule ---------------------------------------------------------------------------------

-- A new key (place or room) counts only after the player has moved `distance` yards while
-- staying on it; the first key after a reset counts at once.
local Entry = {}
Entry.__index = Entry

function logic.newEntry(distance)
    return setmetatable({ distance = distance, current = nil }, Entry)
end

function Entry:reset()
    self.current, self.candidate, self.walked, self.lastX, self.lastY = nil, nil, 0, nil, nil
    self.fromX, self.fromY = nil, nil
end

-- Returns the key when it becomes the current one, else nil. `distanceFor(key)` (optional) gives
-- a key its own distance; the shorter of the new key's and the current key's counts, so leaving
-- a road is as quick as entering it. `fromX`, `fromY`: where the step onto the current key began
-- (where the one before was left).
function Entry:update(key, x, y)
    if key == nil then
        self.candidate = nil
        return nil
    end
    if self.current == nil then
        self.current, self.candidate = key, nil
        return key
    end
    if key == self.current then
        self.candidate = nil
        return nil
    end
    if key ~= self.candidate then
        self.candidate, self.walked, self.lastX, self.lastY = key, 0, x, y
        self.candidateX, self.candidateY = x, y
    else
        self.walked = self.walked + logic.dist(x, y, self.lastX, self.lastY)
        self.lastX, self.lastY = x, y
    end
    local distance = self.distance
    if self.distanceFor then
        distance = math.min(self.distanceFor(key) or distance, self.distanceFor(self.current) or distance)
    end
    if self.walked >= distance then
        self.current, self.candidate = key, nil
        self.fromX, self.fromY = self.candidateX, self.candidateY
        return key
    end
    return nil
end
