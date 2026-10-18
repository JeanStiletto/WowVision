-- The walk-graph tracker (2026-10-19, user: "build it, it's the smarter solution and measures good"): the floor
-- piece the player is on, followed on the walk graph's own surfaces instead of the pieces' joins. The data
-- (format 5, wv-surroundings tools/surfaces.py, zones/<zone>-surfaces.lua) holds every floor surface of a layer in
-- 1 yd columns: its height, its piece and its steps to the four neighbouring columns. The tracker keeps a few
-- candidate surfaces with costs, as the offline truth tool does (wv-surroundings tools/truth.py, the forward pass
-- without hindsight): every look the surfaces under the position are the new candidates, each costed from the
-- cheapest old candidate it can be reached from (a walk of steps costs nothing, a fall 2, a missing step at one
-- height 1.5, a jump 8; a liquid surface on foot or a dry one swimming is no candidate, both are while the game
-- says neither, in the air); candidates far costlier than the best are dropped. The floor is the best candidate's piece (of equal costs the nearest column's); it is SURE when
-- every candidate within the margin lies at that height, else unsure (floors at several heights are possible:
-- the speech should wait). Measured offline before
-- it was built (STATE task 0 "THE TRACKER MEASUREMENT"): with about a second of evidence wrong on 4 / 4 / 0
-- points where the piece module was wrong on 2.1 / 10.3 / 4.0 %.
-- No WoW API here: the headless suite and the walk replays load this file.
local logic = WowVision.surroundingsLogic

local tracker = {}
logic.tracker = tracker

tracker.REACH = 1.25       -- yd: surfaces this near the position are its candidates
tracker.STEP_DZ = 1.5      -- yd: a step leads to the neighbouring column's surface nearest in height within this
tracker.EXTRA_HOPS = 3     -- steps allowed beyond the distance moved (corners on the 1 yd grid)
tracker.MAX_HOPS = 9       -- steps looked for at most (a longer move is a missing step, a fall or a jump)
tracker.FALL = 2.0         -- the cost of a fall onto a lower surface not reached by steps
tracker.MISSING = 1.5      -- the cost of a move at one height no steps explain (a step the data misses)
tracker.JUMP = 8.0         -- the cost of a move nothing explains
tracker.PRUNE = 9.0        -- a candidate costlier than the best by more than this is dropped
tracker.MARGIN = 1.5       -- the floor is sure when every candidate within this of the best lies on its piece
tracker.LEVEL = 1.5        -- yd: heights this close are one level (a fall must go lower than this)
tracker.NEAR = 6.0         -- yd: a fall or a missing step reaches this far; farther is a jump
tracker.RESET = 20.0       -- yd: a move this long since the last look starts afresh (a login, a hearthstone)

-- (offline only: WV_TRACKER_DEBUG=1 says when the tracker first runs, 2 prints every look with its candidates)
local DEBUG = os and os.getenv and os.getenv("WV_TRACKER_DEBUG") or nil
tracker.debug = DEBUG == "2" or DEBUG == "3"
tracker.KEEP = 1.5         -- yd: of two pieces meeting at one height the one held stays while its surface lies this near
tracker.STEEP = 0          -- yd: a move up along ONE piece no steps explain costs MISSING up to this height (a steep ramp
                           -- zigzags on the 1 yd grid, the Abbey bell tower ramp: 9 steps for a 2 yd move, the hop budget
                           -- 7, and a fall onto the ramp below at 2 beat the jump at 8; 0 = off; swept 2026-10-19)
-- (offline only: WV_TRACKER_<NAME>=<number> overrides a number above for a sweep against the truth, e.g.
-- WV_TRACKER_STEP_DZ=2.5; the process asks that a number be swept before it is used, 2026-10-18)
if os and os.getenv then
    for _, name in ipairs({ "REACH", "STEP_DZ", "EXTRA_HOPS", "MAX_HOPS", "FALL", "MISSING", "JUMP", "PRUNE", "MARGIN", "LEVEL", "NEAR", "RESET", "KEEP", "STEEP" }) do
        local v = tonumber(os.getenv("WV_TRACKER_" .. name) or "")
        if v then tracker[name] = v end
    end
end

local ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-"
local VALUE = {}
for i = 1, #ALPHABET do
    VALUE[ALPHABET:byte(i)] = i - 1
end
local Z_OFFSET = 200000
-- (a record of 9 characters: col, height, piece, flags; 10 where the layer says `rec = 10`: a tenth with the
-- surface's place within its column in eighths of a yard, x in bits 3 to 5, y in bits 0 to 2, since 2026-10-19
-- evening; without it a surface is taken at its column's centre)
local COLS = 100003   -- a column key: r * COLS + c
local byte = string.byte
local floor = math.floor
local sqrt = math.sqrt

-- The surfaces of column (r, c) of the layer's surfaces `S` (its x0, y0, rows): a list of {r, c, x, y, z, piece,
-- steps (bits 1, 2, 4, 8: r-1, r+1, c-1, c+1), liquid, terrain}, sorted by height; nil where none. `cache`
-- (per look) keeps decoded columns.
local function column(S, r, c, cache)
    local k = r * COLS + c
    local got = cache[k]
    if got ~= nil then
        return got or nil
    end
    local row = S.rows[r]
    local out = false
    if row then
        local REC = S.rec or 9
        local n = floor(#row / REC)
        local lo, hi = 1, n
        -- the first record whose col is c or more
        while lo < hi do
            local m = floor((lo + hi) / 2)
            local p = (m - 1) * REC + 1
            local a, b, d = byte(row, p, p + 2)
            if VALUE[a] * 4096 + VALUE[b] * 64 + VALUE[d] < c then
                lo = m + 1
            else
                hi = m
            end
        end
        local i = lo
        while i <= n do
            local p = (i - 1) * REC + 1
            local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10 = byte(row, p, p + REC - 1)
            if VALUE[b1] * 4096 + VALUE[b2] * 64 + VALUE[b3] ~= c then
                break
            end
            local flags = VALUE[b9]
            local piece = VALUE[b7] * 64 + VALUE[b8]
            if piece ~= 4095 then
                local sx, sy = S.x0 + r + 0.5, S.y0 + c + 0.5
                if b10 then
                    local pos = VALUE[b10]
                    sx, sy = S.x0 + r + (floor(pos / 8) + 0.5) / 8, S.y0 + c + (pos % 8 + 0.5) / 8
                end
                out = out or {}
                out[#out + 1] = {
                    r = r, c = c, x = sx, y = sy, z = (VALUE[b4] * 4096 + VALUE[b5] * 64 + VALUE[b6] - Z_OFFSET) / 10,
                    piece = piece, steps = flags % 16, liquid = floor(flags / 16) % 2 == 1, terrain = flags >= 32,
                }
            end
            i = i + 1
        end
    end
    cache[k] = out
    return out or nil
end
tracker.column = column

-- The surface a step from `s` leads to in the column (r, c): the one nearest in height within STEP_DZ.
local function stepTo(S, s, r, c, cache)
    local col = column(S, r, c, cache)
    if not col then
        return nil
    end
    local best, bd = nil, tracker.STEP_DZ
    for i = 1, #col do
        local t = col[i]
        local d = t.z > s.z and t.z - s.z or s.z - t.z
        if d <= bd then
            best, bd = t, d
        end
    end
    return best
end

-- (the height whole, in half yards: a key folded modulo 64 made surfaces 32, 64 or 128 yd apart in one column
-- one, the Undercity's ring at -66 under the Ruins at 62 among 889 such pairs; found by review 2026-10-19)
local function keyOf(s)
    return (s.r * COLS + s.c) * 1048576 + floor(s.z * 2 + 0.5) + 400000
end

-- The surfaces reached from `s` in at most `hops` steps: a set by key.
local function reached(S, s, hops, cache)
    local seen = { [keyOf(s)] = true }
    local frontier = { s }
    for _ = 1, hops do
        local nxt = {}
        for i = 1, #frontier do
            local u = frontier[i]
            local st = u.steps
            if st % 2 == 1 then
                local t = stepTo(S, u, u.r - 1, u.c, cache)
                if t and not seen[keyOf(t)] then seen[keyOf(t)] = true; nxt[#nxt + 1] = t end
            end
            if floor(st / 2) % 2 == 1 then
                local t = stepTo(S, u, u.r + 1, u.c, cache)
                if t and not seen[keyOf(t)] then seen[keyOf(t)] = true; nxt[#nxt + 1] = t end
            end
            if floor(st / 4) % 2 == 1 then
                local t = stepTo(S, u, u.r, u.c - 1, cache)
                if t and not seen[keyOf(t)] then seen[keyOf(t)] = true; nxt[#nxt + 1] = t end
            end
            if floor(st / 8) % 2 == 1 then
                local t = stepTo(S, u, u.r, u.c + 1, cache)
                if t and not seen[keyOf(t)] then seen[keyOf(t)] = true; nxt[#nxt + 1] = t end
            end
        end
        if #nxt == 0 then
            break
        end
        frontier = nxt
    end
    return seen
end

-- The surfaces under (x, y): those within REACH of it (at their true place where the data has it, else at
-- their column's centre), out of the nine columns around.
local function under(S, x, y, cache)
    local r0, c0 = floor(x - S.x0), floor(y - S.y0)
    local out = {}
    local reach2 = tracker.REACH * tracker.REACH
    for dr = -1, 1 do
        for dc = -1, 1 do
            local col = column(S, r0 + dr, c0 + dc, cache)
            if col then
                for i = 1, #col do
                    local s = col[i]
                    local dx, dy = s.x - x, s.y - y
                    if dx * dx + dy * dy <= reach2 then
                        out[#out + 1] = s
                    end
                end
            end
        end
    end
    return out
end
tracker.under = under
tracker.reached = reached   -- (offline probes)

-- The cost of the looks since the stats were last taken (module.lua writes them into the walk log once a
-- minute, kind "time": the Lua time per look in the game was unmeasured, STATE 2026-10-19): looks, their
-- milliseconds in all, the slowest look, the most candidates kept after one, the most surfaces under one
-- position, and the looks that ended unsure.
tracker.stats = { looks = 0, ms = 0, maxMs = 0, maxCands = 0, maxUnder = 0, unsure = 0 }
-- (debugprofilestop is the game's millisecond clock; os.clock serves the headless suite and the replays)
local clock = debugprofilestop or (os and os.clock and function() return os.clock() * 1000 end) or function() return 0 end

-- Returns the stats since the last call and starts afresh.
function tracker.takeStats()
    local s = tracker.stats
    tracker.stats = { looks = 0, ms = 0, maxMs = 0, maxCands = 0, maxUnder = 0, unsure = 0 }
    return s
end

local look

-- One look: the floor piece at (x, y) on the layer `zone` (its surfaces in zone.surf), `swimming` true, false
-- or nil (unknown). Returns floor, changed. Keeps zone._index.cands (the candidates: {s, cost, x, y, fell}),
-- .floor, .floorSure, .cameFrom, .fellFrom, .swumIn; clears the join bookkeeping of the piece tracker.
function tracker.update(zone, x, y, swimming)
    local t0 = clock()
    local floor_, changed = look(zone, x, y, swimming)
    local ms = clock() - t0
    local s = tracker.stats
    local ix = zone._index
    s.looks = s.looks + 1
    s.ms = s.ms + ms
    if ms > s.maxMs then s.maxMs = ms end
    local n = ix.cands and #ix.cands or 0
    if n > s.maxCands then s.maxCands = n end
    if (ix.under or 0) > s.maxUnder then s.maxUnder = ix.under end
    if ix.floorSure == false then s.unsure = s.unsure + 1 end
    return floor_, changed
end

function look(zone, x, y, swimming)
    local ix = zone._index
    local S = zone.surf
    local was = ix.floor or 0
    tracker.looks = (tracker.looks or 0) + 1
    if tracker.looks == 1 and DEBUG then
        io.stderr:write("tracker: first look on " .. tostring(zone.key) .. "\n")
    end
    local cache = {}
    local now = under(S, x, y, cache)
    ix.under = #now
    local prev = ix.cands
    if prev and (#prev == 0 or logic.dist(prev[1].x, prev[1].y, x, y) > tracker.RESET) then
        prev = nil
    end
    if #now == 0 then
        -- no surface under the point (a gap of the walk graph: a beach, a ledge the export did not reach): the
        -- candidates stay where they were, and the floor piece is checked against the cell's records as the
        -- piece tracker did it: out of a liquid on foot the floor it stands up onto (swimFloor: the shore
        -- gap at Crystal Lake kept the lake, 2026-10-19), else, where the cell has not the piece held, its
        -- only piece or the ground
        local r, c = logic.cellOf(zone, x, y)
        local key = r * zone.cols + c
        local floor_ = was
        if swimming ~= nil and (swimming == true) ~= (ix.liquids[was] ~= nil) then
            floor_ = logic.swimFloor(zone, key, was, swimming, x, y) or was
        elseif not logic.floorHere(zone, key, was) then
            local only, count = nil, 0
            for p in pairs(ix.floorCells[key] or {}) do
                if swimming == nil or (ix.liquids[p] ~= nil) == swimming then
                    only, count = p, count + 1
                end
            end
            if count == 1 then
                floor_ = only
            elseif swimming ~= true and not ix.noGround[key] then
                floor_ = 0
            end
        end
        if floor_ ~= was then
            ix.floor = floor_
            ix.cameFrom = was
            ix.fellFrom = nil
            ix.cands = nil
        end
        if ix.liquids[floor_] == nil then
            ix.swumIn = nil
        end
        return floor_, floor_ ~= was
    end
    -- the reach of every old candidate, once
    local sets = {}
    local hops = 0
    if prev then
        local d = logic.dist(prev[1].x, prev[1].y, x, y) + tracker.REACH
        hops = math.min(tracker.MAX_HOPS, math.ceil(d) + tracker.EXTRA_HOPS)
        for i = 1, #prev do
            sets[i] = reached(S, prev[i].s, hops, cache)
        end
    end
    -- the game says whether the player swims: on foot no liquid surface is a candidate (the piece tracker's
    -- rule too: a shore's shallow water held the player on the lake, Crystal Lake and Goldshire, 2026-10-19),
    -- swimming no dry one; unknown, both at a cost
    local new = {}
    local best = nil
    for i = 1, #now do
        local b = now[i]
        local local_ = 0
        if swimming ~= nil and b.liquid ~= swimming then
            local_ = nil
        end
        if local_ then
        local cost, fell, from = 0, false, nil
        if prev then
            cost = nil
            local kb = keyOf(b)
            for j = 1, #prev do
                local a = prev[j]
                local t
                if sets[j][kb] then
                    t = 0
                else
                    local d = logic.dist(a.x, a.y, x, y)
                    local dz = b.z - a.s.z
                    if d <= tracker.NEAR and dz < -tracker.LEVEL then
                        t = tracker.FALL
                    elseif d <= tracker.NEAR and dz <= tracker.LEVEL and dz >= -tracker.LEVEL then
                        t = tracker.MISSING
                    elseif d <= tracker.NEAR and a.s.piece == b.piece and dz > 0 and dz <= tracker.STEEP then
                        t = tracker.MISSING
                    else
                        t = tracker.JUMP
                    end
                end
                local v = a.cost + t
                -- (of two ways equally cheap, a fall from the floor held explains more than a walk on a
                -- floor long left: the guidance back onto a climb needs the floor fallen from)
                if cost == nil or v < cost or (v == cost and t == tracker.FALL and not fell and a.s.piece == was) then
                    cost, fell, from = v, t == tracker.FALL, a.s.piece
                    if DEBUG == "3" then
                        io.stderr:write(string.format("  cand %.1f/%d from %.1f/%d cost %.1f at %.1f %.1f: t %.1f -> %.1f\n",
                            b.z, b.piece, a.s.z, a.s.piece, a.cost, a.x, a.y, t, v))
                    end
                end
            end
        end
        cost = cost + local_
        -- how far the position lies from the surface's column centre: among candidates of one cost the
        -- nearest column's surface is the floor (two pieces meeting at one height, a street and its square,
        -- a stair's foot and the ground: no question of height, the nearer one), but the piece held stays
        -- while its surface lies within KEEP (no flapping along a seam the player walks beside; the piece
        -- tracker needed a join crossing to switch)
        local dx, dy = b.x - x, b.y - y
        local off = dx * dx + dy * dy
        if b.piece == was and off <= tracker.KEEP * tracker.KEEP then
            off = 0
        end
        local cand = { s = b, cost = cost, x = x, y = y, fell = fell, from = from, off = off }
        new[#new + 1] = cand
        if best == nil or cost < best.cost or (cost == best.cost and (cand.off < best.off - 0.01
            or (cand.off <= best.off + 0.01 and b.piece == was and best.s.piece ~= was))) then
            best = cand
        end
        end
    end
    if best == nil then
        -- every surface here is of the wrong kind (dry while swimming, wet on foot): nothing to decide
        return was, false
    end
    -- normalised and pruned
    local kept = {}
    local min = best.cost
    for i = 1, #new do
        local cand = new[i]
        if cand.cost - min <= tracker.PRUNE then
            cand.cost = cand.cost - min
            kept[#kept + 1] = cand
        end
    end
    ix.cands = kept
    -- sure: every candidate within the margin lies at the best one's height (one level; another piece at the
    -- same height is a question of names, not of floors, and the nearest column's piece answers it)
    local floor_ = best.s.piece
    local sure = true
    local bz = best.s.z
    for i = 1, #kept do
        local kz = kept[i].s.z
        -- (within the margin: costlier than the best by less than it; a floor reached only by a missing
        -- step or a fall, 1.5 or 2, is a weaker hypothesis than one walked onto)
        if kept[i].cost < tracker.MARGIN and (kz > bz + tracker.LEVEL or kz < bz - tracker.LEVEL) then
            sure = false
            break
        end
    end
    ix.floorSure = sure
    if tracker.debug then
        -- (offline, WV_TRACKER_DEBUG=2: every look with its candidates, to trace a wrong stretch)
        local parts = {}
        for i = 1, #kept do
            parts[#parts + 1] = string.format("%.1f/%d/%.1f%s", kept[i].s.z, kept[i].s.piece, kept[i].cost, kept[i].fell and "F" or "")
        end
        io.stderr:write(string.format("look %s %.1f %.1f floor %d %s hops %d: %s\n", tostring(zone.key), x, y, floor_,
            sure and "sure" or "UNSURE", hops, table.concat(parts, " ")))
    end
    -- the liquid the game had the player swim in (standing up in it), as the piece tracker kept it
    if swimming == true and ix.liquids[floor_] ~= nil then
        ix.swumIn = floor_
    elseif ix.liquids[floor_] == nil then
        ix.swumIn = nil
    end
    ix.floor = floor_
    ix.pendingJoins = {}
    ix.fallBeside = nil
    if floor_ ~= was then
        ix.cameFrom = was
        -- (the piece of the candidate fallen from, not always the piece held: review 2026-10-19)
        ix.fellFrom = best.fell and best.from or nil
    end
    return floor_, floor_ ~= was
end

-- Forgets the candidates (a layer's reset, a teleport): the next look starts from every surface under it.
function tracker.reset(zone)
    local ix = zone._index
    if ix then
        ix.cands = nil
        ix.floorSure = nil
    end
end
