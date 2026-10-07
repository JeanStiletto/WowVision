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
logic.SQUARES = set("square", "hall", "platform") -- places that say what lies around them (a structure's platform too: its stairs, user 2026-10-06); no way begins there
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
-- The data carries angles (format 2, 2026-10-01); the player's words are chosen here: the 8
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
        local words = {}
        for _, a in ipairs(angles) do
            words[#words + 1] = logic.dirWord(zone, a)
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
    local row = zone._index.rows[r + 1]
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
        for dr = -1, 1 do
            for dc = -1, 1 do
                local near = ix.floorCells[(r + dr) * cols + c + dc]
                local nv = near and near[floor]
                if nv then
                    return nv
                end
            end
        end
        local joined = ix.joined[floor]
        if here and joined then
            for p, pv in pairs(here) do
                if joined[p] then
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
    zone._index.regionOf = {}
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
    for dr = -1, 1 do
        for dc = -1, 1 do
            local v = map[(r + dr) * zone.cols + c + dc]
            if v == want or (type(v) == "table" and v[want]) then
                return true
            end
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

-- The nearest cell within `reach` yards whose place kind is in `kinds`: distance and the angle
-- toward it (from the cell centres), or nil.
function logic.nearestOfKinds(zone, x, y, kinds, reach)
    local d, cx, cy = logic.nearestCell(zone, x, y, math.ceil(reach / zone.cell), reach, function(v)
        return kinds[logic.kindOf(zone, v)]
    end)
    if d == nil then
        return nil
    end
    return d, logic.bearingOf(cx - x, cy - y)
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
    -- dead ends (decided offline with the heights), known by their English name
    for _, place in ipairs(zone.places or {}) do
        if place[2] == "dead end" then
            place.deadEnd = true
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
    for key, field in pairs({ roomsAtA = "ta", roomsAtB = "tb" }) do
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

-- Puts `item` into the bucket of every cell the box (x0..x1, y0..y1, widened by `margin` yards)
-- touches.
local function addToCells(zone, buckets, x0, x1, y0, y1, margin, item)
    for r = math.floor((zone.top - x1 - margin) / zone.cell), math.floor((zone.top - x0 + margin) / zone.cell) do
        for c = math.floor((zone.left - y1 - margin) / zone.cell), math.floor((zone.left - y0 + margin) / zone.cell) do
            addToBucket(buckets, r * zone.cols + c, item)
        end
    end
end

logic.LANE_REACH = 12 -- yd; farther from every centre line the grid alone decides
logic.FEET_APART = 8 -- yd; two feet of one climb closer than this are one guidance target

-- Unpacks a zone on entry (once; `locale`: the client's language): the grid rows as runs, and the
-- flat lists of the data as named records with lookups per grid cell, all in zone._index.
function logic.unpack(zone, locale)
    if zone._index then
        return
    end
    prepareWords(zone, locale)
    local ix = {}
    zone._index = ix

    ix.rows = {}
    for r = 1, #zone.grid do
        local starts, values = {}, {}
        local col = 0
        for token in zone.grid[r]:gmatch("[^,]+") do
            local v, n = token:match("^(%d+)%*(%d+)$")
            if v == nil then
                v, n = token, 1
            end
            starts[#starts + 1] = col
            values[#values + 1] = tonumber(v)
            col = col + tonumber(n)
        end
        ix.rows[r] = { starts = starts, values = values }
    end

    ix.places = {}
    for id, p in pairs(zone.places) do
        ix.places[id] = { kind = p[1], label = p[2], road = p[3], deadEnd = p.deadEnd or false, of = p.of }
    end

    -- water under a bridge (or a city canal under the streets), said while swimming
    ix.under = {}
    eachCellTriple(zone, zone.bridgeUnder, function(key, value)
        ix.under[key] = value
    end)
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
    eachRecord(zone.floorCells, 4, function(r, c, piece, value)
        local key = r * zone.cols + c
        ix.floorCells[key] = ix.floorCells[key] or {}
        ix.floorCells[key][piece] = value
    end)
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
    ix.floor = 0
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
            -- in a hall (the indoor layers): the other level its floor belongs to (0 = the main
            -- floor) and the level its drop falls onto (walking over it puts the player there)
            floor = e.l, under = e.u,
            box = { x0, x1, y0, y1 },
        }
    end

    -- the feet of ramps and stairs joined to the way below (export.join_climbs): guidance targets
    -- on the way, as entrances are
    -- (a climb with two line ends at its foot has two feet a yard or two apart: one target, else
    -- the guidance named the ramp to Thane's Boots anew at every step, replay of 2026-10-01)
    -- x, y, the climb's cell value, and (climbFeetFields 4) the line's bearing up the climb in
    -- degrees (0 north, clockwise): the way through at the foot, finer than the compass word
    ix.climbFeet = {}
    -- (climbFeetFields 5) the floor piece at the foot (0 the ground): guided to only from that floor
    local feetStride = zone.climbFeetFields or 3
    eachRecord(zone.climbFeet, feetStride, function(x, y, value, bearing, floor)
        for _, f in ipairs(ix.climbFeet) do
            if f.value == value and logic.dist2(f.x, f.y, x, y) <= logic.FEET_APART ^ 2 then
                return
            end
        end
        ix.climbFeet[#ix.climbFeet + 1] = { x = x, y = y, value = value, bearing = feetStride >= 4 and bearing or nil,
            floor = feetStride >= 5 and floor or 0 }
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
    -- per way out the floor piece it leads out of (zone.exitFloors: the moat's, a pool's; 0 or
    -- none: the ground, the canals')
    for i, fl in ipairs(zone.exitFloors or {}) do
        if ix.exits[i] then
            ix.exits[i].floor = fl
        end
    end
    -- ways out onto floor that joins nothing, or into a dead end (decided offline with the heights)
    for _, i in ipairs(zone.deadExits or {}) do
        if ix.exits[i] then
            ix.exits[i].dead = true
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

    -- objects, in the bucket of every cell their footprint's circle touches
    ix.objects = {}
    eachRecord(zone.objects, 7, function(x, y, halfLength, halfWidth, angle, name, room)
        local o = {
            x = x, y = y, halfLength = halfLength / 10, halfWidth = halfWidth / 10, angle = math.rad(angle),
            name = zone.objectNames and zone.objectNames[name], room = room,
        }
        addToCells(zone, ix.objects, x, x, y, y, math.sqrt(halfLength ^ 2 + halfWidth ^ 2) / 10, o)
    end)

    -- centre line stretches, in the bucket of every cell within LANE_REACH of them
    ix.lanes = {}
    -- 8 since 2026-10-01: the raised piece the stretch runs on; 10: the widths per side (enter and
    -- leave left of the stretch's direction, then right: a wall on one side no longer narrows the other)
    local stride = zone.laneFields or 7
    local wide = stride >= 10
    eachRecord(zone.lanes, stride, function(x1, y1, x2, y2, value, enter, leave, f8, f9, f10)
        local lane = {
            x1 = x1, y1 = y1, x2 = x2, y2 = y2, value = value, kind = logic.kindOf(zone, value),
            enter = enter / 10, leave = leave / 10,
            enter2 = (wide and f8 or enter) / 10, leave2 = (wide and f9 or leave) / 10,
            piece = (wide and f10) or (stride >= 8 and f8) or 0,
        }
        addToCells(zone, ix.lanes, math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2),
            logic.LANE_REACH, lane)
    end)

    ix.interiors = {}
    for i, f in ipairs(zone.interiors or {}) do
        -- city: a city's own complex or a map that is one building (Ironforge, the Deeprun Tram),
        -- named after its zone, which the player knows: a room in it is said without that name
        ix.interiors[i] = { name = f[1], ox = f[2], oy = f[3], scale = f[4], m00 = f[5], m01 = f[6], m10 = f[7], m11 = f[8],
            city = f.c == 1 }
    end
    ix.rooms, ix.roomIds = {}, {}
    for i, room in ipairs(zone.rooms or {}) do
        ix.roomIds[i] = i
        -- axis: the way the room runs (an axis angle, 0..179) when it is long and narrow; winding: its
        -- floor winds up turning left (1) or right (-1); floor: sq yd; named: a name of its own (a shop);
        -- hallMap: the game calls the room outdoors (IsIndoors() false), the UI map one stands on in it;
        -- district: the district a city complex's room names (its English name), short: the name
        -- without it ("canal 3" for "canal, Trade Quarter 3"); place: the key of a place a city's
        -- ways join; wayA, wayB: a way's two places, atA, atB: its names said at each ("passage to
        -- War Quarter" in the canal)
        ix.rooms[i] = {
            interior = room[1], name = room[2], kind = room[3], boxes = room[4], outline = room[5],
            entrance = room.entrance or false, axis = room.a and room.a >= 0 and room.a or nil, winding = room.w,
            floor = room.f or 0,
            named = room.s == 1, hallMap = room.g, district = room.d, short = room.sn,
            place = room.e, wayA = room.wa, wayB = room.wb, atA = room.ta, atB = room.tb,
        }
    end
    -- doors between rooms (0 = outside), and per room its doors and the rooms they join
    ix.doors, ix.doorsOf, ix.neighbours = {}, {}, {}
    for i, d in ipairs(zone.doors or {}) do
        local door = { a = d[1], b = d[2], interior = d[3], x = d[4], y = d[5], nx = d[6], ny = d[7], side = d[8] }
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
    -- segments, {floor pieces; 0 the ground: outdoors the stop counts only on one of them, the
    -- zeppelin tower's top was said at its foot, 2026-10-06}}; the stops on each cell
    ix.stops, ix.stopCells = {}, {}
    for i, s in ipairs(zone.stops or {}) do
        local stop = { kind = s[1], to = s[2] or "", room = s[3] or 0, floors = {}, targets = {} }
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
        cell = own and src.cell or zone.cell, rows = own and src.rows or zone.rows, cols = own and src.cols or zone.cols, laneFields = zone.laneFields, dirs = zone.dirs, dirsClock = zone.dirsClock,
        compass = zone.compass, axes = zone.axes, spokenAxes = zone.spokenAxes, floors = zone.floors, places = zone.places, grid = src.grid or {},
        lanes = src.lanes, noContact = src.noContact, structs = src.structs, waterStructs = src.waterStructs,
        structCells = src.structCells, edges = src.edges, exits = src.exits, exitFloors = src.exitFloors, interiors = zone.interiors, rooms = zone.rooms,
        -- its floor pieces (a gallery, the moat under the walkways, a building's floors), as the
        -- zone's: one rule for every floor over or under another
        floorCells = src.floorCells, noGround = src.noGround, joins = src.joins,
        -- the feet of a building's staircases, guided to as the city's climbs' feet
        climbFeet = src.climbFeet, climbFeetFields = src.climbFeetFields,
        -- on a grid of its own (cells of 2 yd) a doorway of 2 yd is one border cell and worth saying
        mouthMin = own and 1 or nil,
        doors = zone.doors, _worded = true, _running = zone._running, _toward = zone._toward, parent = zone,
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

-- Frees the unpacked data when the player leaves the zone.
function logic.pack(zone)
    zone._index = nil
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
    local text = logic.expandDirs(zone, logic.floorLabel(zone, p.label, floor))
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
function logic.sameWay(value, previous, named)
    local place = logic.placeOf(value)
    return type(previous) == "string" and value ~= 0 and logic.keyPlace(previous) == place and named == place
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

-- The outdoor cell value at a position: while swimming the water under a bridge (or the city
-- canal under the streets); near a centre line what the line decides (`onWay`: the player is on
-- a way now, see laneValue). Returns the value (0 = no data) and whether a lane decided it.
function logic.outdoorValue(zone, x, y, swimming, onWay)
    local value, r, c = logic.valueAt(zone, x, y)
    if swimming then
        local under = logic.underBridge(zone, r, c)
        if under then
            return under, false
        end
    end
    if value == 0 then
        return 0, false
    end
    return logic.laneValue(zone, x, y, value, onWay)
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
