-- Surroundings logic, shared by the module and the headless tests (no WoW API calls in these
-- files). This one: directions, the zone grid, unpacking a zone's data into named records, place
-- texts and the entry rule. The data format is described in docs/src/developer/surroundings.md.
--
-- Directions: a world offset is (dx north, dy west); compass indexes run from 1 = north clockwise
-- to 8 = northwest; a facing (GetPlayerFacing) is in radians, 0 = north, counter-clockwise.

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
logic.SQUARES = set("square", "hall") -- places that say what lies around them; no way begins there
logic.WAYS = set("street", "square", "hall", "road", "fork", "crossing", "bridge", "quay", "pier", "canal walk",
    "slime canal walk", "walk along the lava")
logic.LANE_KINDS = set("road", "fork", "crossing", "street", "quay", "pier", "canal walk", "slime canal walk",
    "walk along the lava") -- ways with centre lines
logic.TURN_KINDS = set("road", "street", "quay", "pier", "canal walk", "slime canal walk", "walk along the lava") -- ... with one direction
-- counted after a short walk inside: bridges and every way with a centre line (streets and walks
-- follow the road rules)
logic.NARROW = set("road", "bridge", "fork", "crossing", "street", "quay", "pier", "canal walk", "slime canal walk",
    "walk along the lava")
logic.WATER = set("deep water", "shore")
logic.DROPS = set("cliff edge")

-- Directions -------------------------------------------------------------------------------------

-- Degrees clockwise from north of a world offset.
local function bearing(dx, dy)
    return math.deg(math.atan2(-dy, dx)) % 360
end

function logic.compassIndex(dx, dy)
    return math.floor((bearing(dx, dy) + 22.5) / 45) % 8 + 1
end

-- Degrees between the direction of a world offset and a compass index's.
function logic.angleOff(dx, dy, index)
    local off = math.abs(bearing(dx, dy) - (index - 1) * 45) % 360
    return math.min(off, 360 - off)
end

-- Unit world vector of a compass index.
function logic.compassVector(index)
    local angle = math.rad((index - 1) * 45)
    return math.cos(angle), -math.sin(angle)
end

-- Signed degrees from angle b to angle a (both radians, counter-clockwise), -180 to 180.
function logic.degreesBetween(a, b)
    local d = math.deg(a - b) % 360
    return d > 180 and d - 360 or d
end

-- The axis (index into zone.axes) the compass word of a facing lies on: facing north or south is
-- the north-south axis.
function logic.facingAxis(facing)
    return (logic.compassIndex(math.cos(facing), math.sin(facing)) - 1) % 4 + 1
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

-- The cell value of a grid cell (0 = no data): place id * 100 + direction code.
function logic.valueAtCell(zone, r, c)
    if not logic.inGrid(zone, r, c) then
        return 0
    end
    local row = zone._index.rows[r + 1]
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

-- The cell value at a world position, plus row and column.
function logic.valueAt(zone, x, y)
    local r, c = logic.cellOf(zone, x, y)
    return logic.valueAtCell(zone, r, c), r, c
end

function logic.placeOf(value)
    return math.floor(value / 100)
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
            local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
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

-- The nearest cell within `reach` yards whose place kind is in `kinds`: distance and compass
-- index toward it (from the cell centres), or nil.
function logic.nearestOfKinds(zone, x, y, kinds, reach)
    local d, cx, cy = logic.nearestCell(zone, x, y, math.ceil(reach / zone.cell), reach, function(v)
        return kinds[logic.kindOf(zone, v)]
    end)
    if d == nil then
        return nil
    end
    return d, logic.compassIndex(cx - x, cy - y)
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

-- The nearest of the records in `list` (each with x and y) within `reach` yards: index, distance,
-- compass index toward it, the record; or nil.
function logic.nearestPoint(list, x, y, reach)
    local best, bestD = nil, reach
    for i, p in ipairs(list) do
        local d = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
        if d <= bestD then
            best, bestD = i, d
        end
    end
    if best == nil then
        return nil
    end
    local p = list[best]
    return best, bestD, logic.compassIndex(p.x - x, p.y - y), p
end

-- Adds a compass index to an item's directions unless it is there already or the item has `max`.
function logic.addDir(item, dir, max)
    if dir == nil or #item.dirs >= (max or math.huge) then
        return
    end
    for _, known in ipairs(item.dirs) do
        if known == dir then
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
    for i, template in ipairs(zone.dirs or {}) do
        if template == "running %s" then
            zone._running = i
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
    zone.compass = t.compass or zone.compass
    zone.spokenAxes = t.axes
    for i, p in ipairs(t.places or {}) do
        local place = zone.places[i]
        if place then
            place[2] = p[1] or place[2]
            if place[3] then
                place[3] = p[2] or place[3]
            end
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
    for _, key in ipairs({ "structs", "objectNames" }) do
        for i, name in ipairs(t[key] or {}) do
            if zone[key] and zone[key][i] then
                zone[key][i] = name
            end
        end
    end
end

-- Calls `add(cellKey, value)` for each (row, column, value) triple of a flat list.
local function eachCellTriple(zone, list, add)
    list = list or {}
    for i = 1, #list - 2, 3 do
        add(list[i] * zone.cols + list[i + 1], list[i + 2])
    end
end

-- Puts `item` into the bucket of every cell the box (x0..x1, y0..y1, widened by `margin` yards)
-- touches.
local function addToCells(zone, buckets, x0, x1, y0, y1, margin, item)
    for r = math.floor((zone.top - x1 - margin) / zone.cell), math.floor((zone.top - x0 + margin) / zone.cell) do
        for c = math.floor((zone.left - y1 - margin) / zone.cell), math.floor((zone.left - y0 + margin) / zone.cell) do
            local key = r * zone.cols + c
            buckets[key] = buckets[key] or {}
            table.insert(buckets[key], item)
        end
    end
end

logic.LANE_REACH = 12 -- yd; farther from every centre line the grid alone decides

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
        ix.places[id] = { kind = p[1], label = p[2], road = p[3], deadEnd = p.deadEnd or false }
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
    -- high floor pieces: their footprints (a set of pieces per cell), where they are stepped onto
    -- and which join
    ix.pieces = {}
    eachCellTriple(zone, zone.pieceCells, function(key, piece)
        ix.pieces[key] = ix.pieces[key] or {}
        ix.pieces[key][piece] = true
    end)
    ix.access = {}
    local list = zone.access or {}
    for i = 1, #list - 3, 4 do
        local a = { piece = list[i], kind = list[i + 1], x = list[i + 2], y = list[i + 3] }
        local r, c = logic.cellOf(zone, a.x, a.y)
        local key = r * zone.cols + c
        ix.access[key] = ix.access[key] or {}
        table.insert(ix.access[key], a)
    end
    ix.links = {}
    list = zone.links or {}
    for i = 1, #list - 1, 2 do
        local a, b = list[i], list[i + 1]
        ix.links[a] = ix.links[a] or {}
        ix.links[b] = ix.links[b] or {}
        table.insert(ix.links[a], b)
        table.insert(ix.links[b], a)
    end

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
            box = { x0, x1, y0, y1 },
        }
    end

    ix.exits = {}
    list = zone.exits or {}
    for i = 1, #list - 3, 4 do
        local out = list[i + 3]
        ix.exits[#ix.exits + 1] = { x = list[i], y = list[i + 1], width = list[i + 2], out = out ~= 0 and out or nil }
    end
    -- ways out onto floor that joins nothing, or into a dead end (decided offline with the heights)
    -- neighbouring cells of two squares with no walkable crossing between them (decided offline
    -- with the heights): no border between the two squares
    ix.noContact = {}
    local cells = zone.rows * zone.cols
    list = zone.noContact or {}
    for i = 1, #list - 3, 4 do
        local a, b = list[i] * zone.cols + list[i + 1], list[i + 2] * zone.cols + list[i + 3]
        ix.noContact[a * cells + b] = true
        ix.noContact[b * cells + a] = true
    end
    for _, i in ipairs(zone.deadExits or {}) do
        if ix.exits[i] then
            ix.exits[i].dead = true
        end
    end

    -- objects, in the bucket of every cell their footprint's circle touches
    ix.objects = {}
    list = zone.objects or {}
    for i = 1, #list - 6, 7 do
        local o = {
            x = list[i], y = list[i + 1], halfLength = list[i + 2] / 10, halfWidth = list[i + 3] / 10,
            angle = math.rad(list[i + 4]), name = zone.objectNames and zone.objectNames[list[i + 5]],
            room = list[i + 6],
        }
        local reach = math.sqrt(list[i + 2] ^ 2 + list[i + 3] ^ 2) / 10
        addToCells(zone, ix.objects, o.x, o.x, o.y, o.y, reach, o)
    end

    -- centre line stretches, in the bucket of every cell within LANE_REACH of them
    ix.lanes = {}
    list = zone.lanes or {}
    for i = 1, #list - 6, 7 do
        local lane = {
            x1 = list[i], y1 = list[i + 1], x2 = list[i + 2], y2 = list[i + 3], value = list[i + 4],
            kind = logic.kindOf(zone, list[i + 4]), enter = list[i + 5] / 10, leave = list[i + 6] / 10,
        }
        addToCells(zone, ix.lanes, math.min(lane.x1, lane.x2), math.max(lane.x1, lane.x2),
            math.min(lane.y1, lane.y2), math.max(lane.y1, lane.y2), logic.LANE_REACH, lane)
    end

    ix.interiors = {}
    for i, f in ipairs(zone.interiors or {}) do
        ix.interiors[i] = { name = f[1], ox = f[2], oy = f[3], scale = f[4], m00 = f[5], m01 = f[6], m10 = f[7], m11 = f[8] }
    end
    ix.rooms = {}
    for i, room in ipairs(zone.rooms or {}) do
        -- axis: the way the room runs (index into zone.axes) when it is long and narrow; winding: its
        -- floor winds up turning left (1) or right (-1); floor: sq yd; named: a name of its own (a shop)
        ix.rooms[i] = {
            interior = room[1], name = room[2], kind = room[3], boxes = room[4], outline = room[5],
            entrance = room.entrance or false, axis = room.a, winding = room.w, floor = room.f or 0,
            named = room.s == 1,
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
end

-- Frees the unpacked data when the player leaves the zone.
function logic.pack(zone)
    zone._index = nil
end

-- Place texts ------------------------------------------------------------------------------------

-- The axis a direction code says ("running %s"), or nil.
local function axisOfCode(zone, code)
    if math.floor(code / 10) == zone._running then
        return code % 10
    end
end

-- The axis (index into zone.axes) a cell value says, or nil.
function logic.axisOf(zone, value)
    return axisOfCode(zone, value % 100)
end

-- The spoken words of an axis: "north to south" (the hyphenated word runs together when spoken);
-- a localized zone brings its own.
function logic.axisWords(zone, i)
    if zone.spokenAxes then
        return zone.spokenAxes[i]
    end
    local word = zone.axes[i]
    return word and (word:gsub("%-", " to "))
end

-- The text of a cell value: the place label, and with `withDirection` its direction and its
-- nearest road ("Goldshire road to the north"; left out with `noNearRoad`, when the caller says
-- where the road is itself).
function logic.describe(zone, value, withDirection, noNearRoad)
    local p = zone._index.places[logic.placeOf(value)]
    if p == nil then
        return nil
    end
    local text = p.label
    local code = value % 100
    if withDirection and code > 0 then
        local template = zone.dirs[math.floor(code / 10)]
        local axis = axisOfCode(zone, code)
        local word = axis and logic.axisWords(zone, axis) or zone.compass[code % 10]
        if template and word then
            -- an axis without its template: "road, northwest to southeast"
            text = text .. ", " .. (axis and word or string.format(template, word))
        end
    end
    if withDirection and p.road and not noNearRoad then
        text = text .. ", " .. p.road
    end
    return text
end

-- Outdoor keys ------------------------------------------------------------------------------------
-- What the entry rule compares outdoors: the place id; a piece of a way with one direction (a
-- road, a city street or walk: TURN_KINDS) "r<value>" and a canal piece "c<value>" are keyed with
-- their direction, so a bend is a new place like any other; streets follow the road rules.

function logic.outdoorKey(zone, value)
    if value == 0 then
        return nil
    end
    local kind = logic.kindOf(zone, value)
    if kind == "canal" then
        return "c" .. value
    elseif logic.TURN_KINDS[kind] then
        return "r" .. value
    end
    return logic.placeOf(value)
end

-- A key of a way with one direction (a road, street or walk piece).
function logic.isWayKey(key)
    return type(key) == "string" and key:sub(1, 1) == "r"
end

-- The place id of an outdoor key (nil for nil).
function logic.keyPlace(key)
    if type(key) == "string" then
        return logic.placeOf(tonumber(key:sub(2)) or 0)
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
end

-- Returns the key when it becomes the current one, else nil. `distanceFor(key)` (optional) gives
-- a key its own distance; the shorter of the new key's and the current key's counts, so leaving
-- a road is as quick as entering it.
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
    else
        local dx, dy = x - self.lastX, y - self.lastY
        self.walked = self.walked + math.sqrt(dx * dx + dy * dy)
        self.lastX, self.lastY = x, y
    end
    local distance = self.distance
    if self.distanceFor then
        distance = math.min(self.distanceFor(key) or distance, self.distanceFor(self.current) or distance)
    end
    if self.walked >= distance then
        self.current, self.candidate = key, nil
        return key
    end
    return nil
end
