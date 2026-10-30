-- The stored data (format 4, written by wv-surroundings tools/store.py) back into the zone the rest
-- of this module reads (the model: the flat lists docs/src/developer/surroundings.md describes).
-- A zone file registers its frame and its data as JSON text; the text is decoded (logic.decodeJson:
-- the game's C_EncodingUtil.DeserializeJSON, offline tools/json.lua) and expanded only when the
-- player enters the zone (logic.unpack), and dropped again on leaving (logic.pack).
-- Format 4 keeps the order of every list, so the expanded lists are exactly the model's:
-- - cells as runs along a row: row, column, count (< 0: the columns go down), values;
-- - centre lines as polylines: their 6 values, the number of points, the points (tenths of a yard,
--   each the step from the one before), then their stretches' headings;
-- - joins grouped by pair: a, b, then x, y (tenths), angle per join;
-- - the grid's rows as palette index, count pairs; objects by shape; coordinates in tenths.

local logic = WowVision.surroundingsLogic

logic.FORMAT = 4

-- set by module.lua (the game's C_EncodingUtil.DeserializeJSON), offline by the tools
logic.decodeJson = nil
-- The packed data (WowVision tools/surroundings-pack.py, what the game loads; git keeps the text the tools read):
-- a zone's JSON text and each band of a surfaces layer are compressed strings, `logic.inflate(packed)` gives the
-- text back (set by module.lua: the game's C_EncodingUtil.DecodeBase64 and DecompressString; offline the tests
-- put a stand-in in its place).
logic.inflate = nil

-- The fields a registered zone keeps while the player is elsewhere: its frame (findZone) and the
-- JSON text (`deflated`: packed). logic.pack drops the rest.
logic.ZONE_HEADER = { key = true, label = true, map = true, top = true, left = true, cell = true, rows = true,
    cols = true, format = true, json = true, deflated = true }

-- A packed surfaces layer (its `bands`: per band of `band` rows one packed string of the rows, a line each, an
-- empty line where a row has none) gets the `rows` the walk-graph tracker reads (tracker.lua column): a band is
-- unpacked when a row of it is first asked for, and only the BANDS_KEPT bands asked for last stay unpacked (the
-- tracker reads 16 rows around the player at most, two bands).
logic.BANDS_KEPT = 4
function logic.bandRows(layer)
    local bands, size = layer.bands, layer.band
    local open, order = {}, {}   -- the unpacked bands: a set, and in the order unpacked
    local rows = {}
    setmetatable(rows, { __index = function(_, r)
        local b = math.floor(r / size)
        if open[b] or bands[b] == nil then
            return nil   -- (a row with no surfaces, or a band with none)
        end
        if #order >= logic.BANDS_KEPT then
            local old = table.remove(order, 1)
            open[old] = nil
            for i = old * size, old * size + size - 1 do
                rawset(rows, i, nil)
            end
        end
        local text = logic.inflate(bands[b])
        assert(text, "the surroundings surfaces could not be unpacked")
        local i = b * size
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if line ~= "" then
                rawset(rows, i, line)
            end
            i = i + 1
        end
        open[b] = true
        order[#order + 1] = b
        return rawget(rows, r)
    end })
    layer.rows = rows
    return layer
end

local LAYERS = { { "indoor", "halls" }, { "indoorIn", "inside" } }
-- per-cell lists: the model's key, the values after row and column, the key in a layer's cells
local CELL_LISTS = { { "floorCells", 2, "floor" }, { "noGround", 0, "noGround" }, { "structCells", 1, "struct" },
    { "floorRooms", 2, "rooms" }, { "hallGround", 0, "hallGround" } }
local COPIED = { "noContact", "liquids", "lineFloors", "doorFloors", "waterStructs", "structs", "rooms" }
local WORDS = { "dirs", "dirsClock", "compass", "axes", "floors", "ofTemplate" }

-- Steps in tenths of a yard (the first from 0) as world coordinates, appended to `out`.
local function unpath(steps, out, from, to)
    local x, y = 0, 0
    for i = from or 1, (to or #steps) - 1, 2 do
        x, y = x + steps[i], y + steps[i + 1]
        out[#out + 1] = x / 10
        out[#out + 1] = y / 10
    end
    return out
end

local function uncellRuns(runs, nRest)
    local out, stride = {}, 3 + nRest
    for i = 1, #runs, stride do
        local r, c, n = runs[i], runs[i + 1], runs[i + 2]
        local step = n > 0 and 1 or -1
        for k = 0, math.abs(n) - 1 do
            out[#out + 1] = r
            out[#out + 1] = c + k * step
            for j = 1, nRest do
                out[#out + 1] = runs[i + 2 + j]
            end
        end
    end
    return out
end

local function ungridRows(rows, palette)
    local out = {}
    for r, row in ipairs(rows) do
        local tokens = {}
        for i = 1, #row, 2 do
            local v, n = palette[row[i]], row[i + 1]
            tokens[#tokens + 1] = n > 1 and (v .. "*" .. n) or tostring(v)
        end
        out[r] = table.concat(tokens, ",")
    end
    return out
end

local function unjoin(groups)
    local out = {}
    for _, g in ipairs(groups) do
        for i = 3, #g, 3 do
            out[#out + 1] = g[1]
            out[#out + 1] = g[2]
            out[#out + 1] = g[i] / 10
            out[#out + 1] = g[i + 1] / 10
            out[#out + 1] = g[i + 2]
        end
    end
    return out
end

-- Polylines back into stretches (x1, y1, x2, y2, then the line's 6 values) and their headings.
local function unpolylines(lines)
    local lanes, headings = {}, {}
    for _, line in ipairs(lines) do
        local npts = line[7]
        local pts = unpath(line, {}, 8, 7 + 2 * npts)
        for k = 0, npts - 2 do
            for j = 1, 4 do
                lanes[#lanes + 1] = pts[2 * k + j]
            end
            for j = 1, 6 do
                lanes[#lanes + 1] = line[j]
            end
        end
        for i = 8 + 2 * npts, #line do
            headings[#headings + 1] = line[i]
        end
    end
    return lanes, headings
end

local function expandLayer(S, palette, ground)
    local L = {}
    for key, v in pairs(S.frame or {}) do
        L[key] = v
    end
    if S.grid then
        L.grid = ungridRows(S.grid, palette)
    end
    local cells = S.cells or {}
    for _, c in ipairs(CELL_LISTS) do
        if cells[c[3]] then
            L[c[1]] = uncellRuns(cells[c[3]], c[2])
        end
    end
    if S.joins then
        L.joins = unjoin(S.joins)
    end
    if S.lines then
        local lanes, headings = unpolylines(S.lines)
        L.lanes = lanes
        if S.lineHeadings then
            L.laneHeadings = headings
        end
        if ground then
            L.laneFields = 10
        end
    end
    if S.exits then
        local ex, floors, groups = {}, {}, {}
        for i = 1, #S.exits, 6 do
            ex[#ex + 1] = S.exits[i] / 10
            ex[#ex + 1] = S.exits[i + 1] / 10
            ex[#ex + 1] = S.exits[i + 2]
            ex[#ex + 1] = S.exits[i + 3]
            floors[#floors + 1] = S.exits[i + 4]
            groups[#groups + 1] = S.exits[i + 5]
        end
        L.exits, L.exitFloors, L.exitGroups = ex, floors, groups
    end
    if S.edges then
        L.edges = {}
        for i, rec in ipairs(S.edges) do
            local e = { unpack(rec.h) }
            unpath(rec.p, e)
            e.l, e.u, e.d = rec.l, rec.u, rec.d
            L.edges[i] = e
        end
    end
    if S.climbFeet then
        local f, out = S.climbFeet, {}
        for i = 1, #f, 5 do
            out[#out + 1] = f[i] / 10
            out[#out + 1] = f[i + 1] / 10
            out[#out + 1] = f[i + 2]
            out[#out + 1] = f[i + 3]
            out[#out + 1] = f[i + 4]
        end
        L.climbFeet, L.climbFeetFields = out, 5
    end
    if S.climbTops then
        local f, out = S.climbTops, {}
        for i = 1, #f, 5 do
            out[#out + 1] = f[i] / 10
            out[#out + 1] = f[i + 1] / 10
            out[#out + 1] = f[i + 2]
            out[#out + 1] = f[i + 3]
            out[#out + 1] = f[i + 4]
        end
        L.climbTops = out
    end
    if S.climbAims then
        local a, out = S.climbAims, {}
        for i = 1, #a, 5 do
            out[#out + 1] = a[i]
            out[#out + 1] = a[i + 1]
            out[#out + 1] = a[i + 2] / 10
            out[#out + 1] = a[i + 3] / 10
            out[#out + 1] = a[i + 4]
        end
        L.climbAims = out
    end
    for _, key in ipairs(COPIED) do
        if S[key] ~= nil then
            L[key] = S[key]
        end
    end
    for key, v in pairs(S.extra or {}) do
        L[key] = v
    end
    return L
end

local function unsparse(m, n)
    local out = {}
    for i = 1, n do
        out[i] = m and m[tostring(i)] or ""
    end
    return out
end

local function some(s)
    if s ~= "" then
        return s
    end
end

-- Expands the decoded format 4 `data` into `zone` (a registered zone: its frame is there already),
-- with the names and words of `locale` beside the English ones as the model's `locales`.
function logic.expand(zone, data, locale)
    local palette = data.palette
    for key, v in pairs(expandLayer(data.layers.ground, palette, true)) do
        zone[key] = v
    end
    for _, l in ipairs(LAYERS) do
        if data.layers[l[2]] then
            zone[l[1]] = expandLayer(data.layers[l[2]], palette, false)
        end
    end
    local en, words = data.names.enUS, data.words
    for _, key in ipairs(WORDS) do
        zone[key] = words.enUS[key]
    end
    zone.places = {}
    for i, kind in ipairs(data.places) do
        local n = en.places[i]
        zone.places[i] = { kind, n[1], some(n[2]), of = some(n[3]) }
    end
    local b = data.buildings
    local walls = unsparse(en.interiorWalls, #b.interiors)
    zone.interiors = {}
    for i, f in ipairs(b.interiors) do
        zone.interiors[i] = { en.interiors[i], f[1], f[2], f[3], f[4], f[5], f[6], f[7],
            c = f[8] ~= 0 and f[8] or nil, w = some(walls[i]) }
    end
    local short, area = unsparse(en.roomsShort, #b.rooms), unsparse(en.roomsArea, #b.rooms)
    local atA, atB = unsparse(en.roomsAtA, #b.rooms), unsparse(en.roomsAtB, #b.rooms)
    zone.rooms = {}
    for i, r in ipairs(b.rooms) do
        local room = { r.i, en.rooms[i], r.k, r.b, r.o }
        for key, v in pairs(r) do
            if key ~= "i" and key ~= "k" and key ~= "b" and key ~= "o" then
                room[key] = v
            end
        end
        room.sn, room.ar, room.ta, room.tb = some(short[i]), some(area[i]), some(atA[i]), some(atB[i])
        zone.rooms[i] = room
    end
    zone.doors = {}
    zone.doorVia = b.doorVia and {} or nil
    for i, d in ipairs(b.doors) do
        zone.doors[i] = { d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9] }
        if b.doorVia then
            zone.doorVia[2 * i - 1], zone.doorVia[2 * i] = d[10], d[11]
        end
    end
    local shapes, list, objects = data.objects.shapes, data.objects.list, {}
    for i = 1, #list, 5 do
        local s = 3 * (list[i + 3] - 1)
        objects[#objects + 1] = list[i] / 10
        objects[#objects + 1] = list[i + 1] / 10
        objects[#objects + 1] = shapes[s + 1]
        objects[#objects + 1] = shapes[s + 2]
        objects[#objects + 1] = list[i + 2]
        objects[#objects + 1] = shapes[s + 3]
        objects[#objects + 1] = list[i + 4]
    end
    zone.objects = objects
    zone.objectNames, zone.structs, zone.spoken = en.objectNames, en.structs, en.spoken
    zone.stops = {}
    for i, s in ipairs(data.stops) do
        zone.stops[i] = { s[1], en.stops[i], s[2], s[3], s[4], s[5] }
    end
    local n = locale ~= "enUS" and data.names[locale]
    if n then
        local t = {}
        for _, key in ipairs(WORDS) do
            t[key] = (words[locale] or {})[key]
        end
        t.places = {}
        for i, p in ipairs(n.places) do
            t.places[i] = { p[1], some(p[2]), of = some(p[3]) }
        end
        for _, key in ipairs({ "interiors", "rooms", "structs", "objectNames", "stops" }) do
            t[key] = n[key]
        end
        t.interiorWalls = unsparse(n.interiorWalls, #b.interiors)
        for _, key in ipairs({ "roomsShort", "roomsArea", "roomsAtA", "roomsAtB" }) do
            t[key] = unsparse(n[key], #b.rooms)
        end
        t.spoken = n.spoken
        zone.locales = { [locale] = t }
    end
    for key, v in pairs(data.extra or {}) do
        zone[key] = v
    end
end
