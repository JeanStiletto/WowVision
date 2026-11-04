-- The walk-graph tracker (2026-10-19, user: "build it, it's the smarter solution and measures good"): the floor
-- piece the player is on, followed on the walk graph's own surfaces instead of the pieces' joins. The data
-- (format 5, wv-surroundings tools/surfaces.py, zones/<zone>-surfaces.lua) holds every floor surface of a layer in
-- 1 yd columns: its height, its piece and its steps to the four neighbouring columns. The tracker keeps a few
-- candidate surfaces with costs, as the offline truth tool does (wv-surroundings tools/truth.py, the forward pass
-- without hindsight): every look the surfaces under the position are the new candidates, each costed from the
-- cheapest old candidate it can be reached from (a walk of steps costs nothing, a fall 2, a missing step at one
-- height 1.5, a jump 8; a liquid surface on foot or a dry one swimming is no candidate, both are while the game
-- says neither, in the air); candidates far costlier than the best are dropped. The floor is the best candidate's piece (of equal costs the nearest column's); it is SURE when
-- every candidate within the margin lies at that height, else unsure (floors at several heights are possible;
-- logged with the looks, nothing waits on it). Measured offline before
-- it was built (STATE task 0 "THE TRACKER MEASUREMENT"): with about a second of evidence wrong on 4 / 4 / 0
-- points where the piece module was wrong on 2.1 / 10.3 / 4.0 %.
-- Holes of the walk graph (2026-10-19, after the walk of 10-18 21:55, bug 63: the zeppelin tower's base has no
-- ground under its flights in the data, and the tracker took the player walking there up the flights): where
-- every surface under the player costs a jump from every candidate and the floor held lies in this cell or one
-- next to it, the floor and the candidates are kept and carried along with the player (HOLES, HOLE_ANCHOR,
-- HOLE_MAX; the candidates' `far` is the way walked since their surface was adopted, so the reach grows with it;
-- a walk-graph gap with no surface at all carries them the same way). The offline truth tool has the same hole
-- state (truth.py HOLES), so a hole is unscored there, or scored as the carried floor with WV_SCORE_HOLES=1.
-- No WoW API here: the headless suite and the walk replays load this file.
local logic = WowVision.surroundingsLogic

local tracker = {}
logic.tracker = tracker

tracker.REACH = 1.25       -- yd: surfaces this near the position are its candidates
tracker.STEP_DZ = 1.5      -- yd: a step leads to the neighbouring column's surface nearest in height within this
tracker.EXTRA_HOPS = 5     -- steps allowed beyond the distance moved (corners on the 1 yd grid; a U-ramp or a zigzag
                           -- ramp climbs 14 steps inside a 5 by 6 yd box: the Lion's Pride Inn, the Abbey bell tower
                           -- ramp; 3 until 2026-10-19, swept 3 / 5 against the truth: 5 with MAX_HOPS 15 Elwynn
                           -- 189 -> 144 wrong points, the Undercity 389 -> 387, Dun Morogh 36 -> 38)
tracker.MAX_HOPS = 15      -- steps looked for at most (a longer move is a missing step, a fall or a jump; 9 until
                           -- 2026-10-19, the sweep above)
tracker.FALL = 2.0         -- the cost of a fall onto a lower surface not reached by steps
tracker.MISSING = 1.5      -- the cost of a move at one height no steps explain (a step the data misses)
tracker.JUMP = 8.0         -- the cost of a move nothing explains
tracker.PRUNE = 9.0        -- a candidate costlier than the best by more than this is dropped
tracker.MARGIN = 1.5       -- the floor is sure when every candidate within this of the best lies on its piece
tracker.LEVEL = 1.5        -- yd: heights this close are one level (a fall must go lower than this)
tracker.NEAR = 6.0         -- yd: a fall or a missing step reaches this far; farther is a jump
tracker.RESET = 20.0       -- yd: a move this long since the last look starts afresh (a login, a hearthstone)
tracker.HOLES = 1          -- the hole rule (0 = off): where every surface under the player costs a jump from every
                           -- candidate held and the floor held lies in this cell or one next to it, the walk graph
                           -- has a hole there (the zeppelin tower's base: no ground under the flights, bug 63); the
                           -- floor and the candidates stay, carried along with the player
tracker.HOLE_ANCHOR = 5.0  -- yd the floor must have been followed since the last cold start before a hole is believed
                           -- (a hall entry sets the floor by the area, the canal ring 124 yd under the Ruins' courtyard,
                           -- and the courtyard above was taken for a hole, 10-18 22:07)
tracker.HOLE_DZ = 4.0      -- yd: a surface this little above a candidate (within NEAR) is a missing step or a stair's
                           -- foot the walk graph lacks, no hole (the zeppelin tower's first flight starts 2.8 yd over
                           -- the terrain in the data: with the terrain back under the tower the rule held the ground
                           -- while the player climbed, trial H1 2026-10-19)
tracker.HOLE_MAX = 60.0    -- yd of walking in a hole after which the floor held is given up (a hole is local; the
                           -- truth tool caps its holes at 60 yd too; swept 15 to 100 on 2026-10-19: 60 the knee)
tracker.PRIOR = 8.0        -- the cost a surface at another height starts with at a cold start (a reset, a login, a
                           -- hearthstone) when the floor the module set has a surface under the player: the module's
                           -- floor (the game's area, the cell's default) is evidence taken where it was surer than the
                           -- tracker can be with no way walked; 0 = every surface at 0, as before. Brill's tavern
                           -- 2026-10-19 16:30 after a /reload in the common room: the ground and the upper floor both
                           -- started at 0, the furnished ground paid missing steps where the empty upper floor paid
                           -- nothing, and the upper floor won after 4 yd, "sure".
tracker.RISE = 4.0         -- yd: a move up onto a surface more than this over the candidate it starts from, that no steps
                           -- explain, is none a player makes (no jump climbs that high): such a surface is no candidate
                           -- while the look has another explanation than a jump (a walk, a fall, a missing step); where
                           -- nothing else explains it (the data misses a climb), it costs JUMP as before. The Temple of
                           -- the Moon, walk 2026-11-04 08:39:34, bug 163: the gallery 20 yd over the hall floor was a
                           -- candidate at JUMP under the whole ring, every fall of the player's real chain made it
                           -- cheaper against it, and it won after a 1.5 yd drop and a 1.7 yd ledge; 0 = off
tracker.DETOUR = 1.5       -- the cost of a move at one height on the SAME piece that no step chain explains (a table or
                           -- a bench cuts the ground's walk graph, the way round it is longer than the hop budget);
                           -- MISSING by default (a sweep against the truth decides, 2026-10-19 afternoon)

-- (offline only: WV_TRACKER_DEBUG=1 says when the tracker first runs, 2 prints every look with its candidates)
local DEBUG = os and os.getenv and os.getenv("WV_TRACKER_DEBUG") or nil
tracker.debug = DEBUG == "2" or DEBUG == "3"
tracker.KEEP = 1.5         -- yd: of two pieces meeting at one height the one held stays while its surface lies this near
tracker.STEEP = 0          -- yd: a move up along ONE piece no steps explain costs MISSING up to this height (a steep ramp
                           -- zigzags on the 1 yd grid, the Abbey bell tower ramp: 9 steps for a 2 yd move, the hop budget
                           -- 7, and a fall onto the ramp below at 2 beat the jump at 8; 0 = off; swept 2026-10-19)
tracker.CHAIN = 1          -- 1: of candidates of one cost, the one reached from the floor held wins before the nearest
                           -- column: a U-ramp split into its flights (data trial K3) kept its upper flight over the ground
                           -- under it while the lower flight was held (the Lion's Pride Inn, walk 2026-10-19 17:08:13); the
                           -- piece held alone did that while the U was one piece. 0 = off; swept 2026-10-19 late on J2 and
                           -- K3, the whole set: Elwynn 155 -> 144 on K3 (J2 144 either way), Undercity 388 -> 389 (one point
                           -- in Brill's common room), Dun Morogh 38 either way
tracker.THROUGH = 1        -- 1: a fall lands on the first dry floor under it, never through one: a lower surface with another
                           -- dry floor in its 1 yd column between it and the fall's start costs JUMP, not FALL (the Abbey
                           -- bell tower, walk 2026-10-30 17:47:28, bug 142: a hop 2 to 4 yd down off the platform onto the
                           -- tower floor, and the Main Hall's floor 35 yd under both cost FALL alike; the hall won for 37 s).
                           -- 0 = off
tracker.PERSIST = true     -- the decoded columns and each surface's steps kept per layer from look to look, not decoded
                           -- afresh per look; the same floors (the data does not change; offline since 2026-10-21 night
                           -- for the replays of a million looks, tools/walklog/vtrack.lua; in the game since 2026-10-30,
                           -- the user: game performance). WV_TRACKER_PERSIST=0 offline: decoded afresh per look
tracker.SPAN = 48.0        -- yd: the kept columns are let go and kept afresh once the player is this far from where they
                           -- began (the memory stays that of the ground around the player; offline WV_TRACKER_SPAN)
-- (offline only: WV_TRACKER_<NAME>=<number> overrides a number above for a sweep against the truth, e.g.
-- WV_TRACKER_STEP_DZ=2.5; the process asks that a number be swept before it is used, 2026-10-18)
if os and os.getenv then
    tracker.PERSIST = os.getenv("WV_TRACKER_PERSIST") ~= "0"
    for _, name in ipairs({ "SPAN", "REACH", "STEP_DZ", "EXTRA_HOPS", "MAX_HOPS", "FALL", "MISSING", "JUMP", "PRUNE", "MARGIN", "LEVEL", "NEAR", "RESET", "KEEP", "STEEP", "HOLES", "HOLE_ANCHOR", "HOLE_MAX", "HOLE_DZ", "PRIOR", "DETOUR", "CHAIN", "THROUGH", "RISE" }) do
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
-- (a record of 10 characters: col, height, piece, flags, and the surface's place within its column in eighths of a
-- yard, x in bits 3 to 5, y in bits 0 to 2; the layer says `rec = 10`. Records of 9, without the place, were the
-- data before 2026-10-19 evening: a surface taken at its column's centre)
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

-- Whether the candidate `cand` is a better floor than `best` (nil: none yet), `was` the floor piece held: the cheaper;
-- of one cost the one reached from the floor held (CHAIN), then the nearest column's, then the piece held.
local function better(cand, best, was)
    if best == nil or cand.cost < best.cost then
        return true
    end
    return cand.cost == best.cost and ((cand.cont and not best.cont)
        or (cand.cont == best.cont and (cand.off < best.off - 0.01
        or (cand.off <= best.off + 0.01 and cand.s.piece == was and best.s.piece ~= was))))
end

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

-- (PERSIST: a surface's four steps found once and kept on it, false where it has none; its key too)
local function stepKept(S, u, d, r, c, cache)
    local nb = u.nb
    if not nb then
        nb = { nil, nil, nil, nil }
        u.nb = nb
        u.key = keyOf(u)
    end
    local t = nb[d]
    if t == nil then
        t = stepTo(S, u, r, c, cache) or false
        if t and not t.key then
            t.key = keyOf(t)
        end
        nb[d] = t
    end
    return t or nil
end

local function stepFresh(S, u, _, r, c, cache)
    return stepTo(S, u, r, c, cache)
end

-- The surfaces reached from `s` in at most `hops` steps: a set by key. `box` (PERSIST only; rows r1..r2, columns
-- c1..c2: the columns the answer is asked for) leaves out what cannot reach the box in the hops left; the set
-- still holds every surface in the box that the whole search holds (a step crosses one column).
local function reached(S, s, hops, cache, box)
    local step = tracker.PERSIST and stepKept or stepFresh
    local seen = { [keyOf(s)] = true }
    local frontier = { s }
    local r1, r2, c1, c2
    if box then
        r1, r2, c1, c2 = box[1], box[2], box[3], box[4]
    end
    for k = 1, hops do
        local nxt = {}
        for i = 1, #frontier do
            local u = frontier[i]
            local st = u.steps
            if st % 2 == 1 then
                local t = step(S, u, 1, u.r - 1, u.c, cache)
                if t then local q = t.key or keyOf(t); if not seen[q] then seen[q] = true; if not r1 or k + (t.r < r1 and r1 - t.r or t.r > r2 and t.r - r2 or 0) + (t.c < c1 and c1 - t.c or t.c > c2 and t.c - c2 or 0) <= hops then nxt[#nxt + 1] = t end end end
            end
            if floor(st / 2) % 2 == 1 then
                local t = step(S, u, 2, u.r + 1, u.c, cache)
                if t then local q = t.key or keyOf(t); if not seen[q] then seen[q] = true; if not r1 or k + (t.r < r1 and r1 - t.r or t.r > r2 and t.r - r2 or 0) + (t.c < c1 and c1 - t.c or t.c > c2 and t.c - c2 or 0) <= hops then nxt[#nxt + 1] = t end end end
            end
            if floor(st / 4) % 2 == 1 then
                local t = step(S, u, 3, u.r, u.c - 1, cache)
                if t then local q = t.key or keyOf(t); if not seen[q] then seen[q] = true; if not r1 or k + (t.r < r1 and r1 - t.r or t.r > r2 and t.r - r2 or 0) + (t.c < c1 and c1 - t.c or t.c > c2 and t.c - c2 or 0) <= hops then nxt[#nxt + 1] = t end end end
            end
            if floor(st / 8) % 2 == 1 then
                local t = step(S, u, 4, u.r, u.c + 1, cache)
                if t then local q = t.key or keyOf(t); if not seen[q] then seen[q] = true; if not r1 or k + (t.r < r1 and r1 - t.r or t.r > r2 and t.r - r2 or 0) + (t.c < c1 and c1 - t.c or t.c > c2 and t.c - c2 or 0) <= hops then nxt[#nxt + 1] = t end end end
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
tracker.stats = { looks = 0, ms = 0, maxMs = 0, maxCands = 0, maxUnder = 0, unsure = 0, holes = 0 }
-- (debugprofilestop is the game's millisecond clock; os.clock serves the headless suite and the replays)
local clock = debugprofilestop or (os and os.clock and function() return os.clock() * 1000 end) or function() return 0 end

-- Returns the stats since the last call and starts afresh.
function tracker.takeStats()
    local s = tracker.stats
    tracker.stats = { looks = 0, ms = 0, maxMs = 0, maxCands = 0, maxUnder = 0, unsure = 0, holes = 0 }
    return s
end

local look

-- One look: the floor piece at (x, y) on the layer `zone` (its surfaces in zone.surf), `swimming` true, false
-- or nil (unknown). Returns floor, changed. Keeps zone._index.cands (the candidates: {s, cost, x, y, fell}),
-- .floor, .floorSure, .cameFrom, .fellFrom, .swumIn.
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
    if ix.inHole then s.holes = s.holes + 1 end
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
    local cache
    if tracker.PERSIST then
        cache = S._cache
        if cache == nil or logic.dist(S._cacheX, S._cacheY, x, y) > tracker.SPAN then
            cache = {}
            S._cache, S._cacheX, S._cacheY = cache, x, y
        end
    else
        cache = {}
    end
    local now = under(S, x, y, cache)
    ix.under = #now
    local prev = ix.cands
    -- (the reset is measured from the last look, not from the candidates: carried through a hole or a gap
    -- they keep the player's position, and their `far` counts the way walked since their surface was adopted)
    local lx, ly = ix.lastX or x, ix.lastY or y
    local moved = logic.dist(lx, ly, x, y)
    ix.lastX, ix.lastY = x, y
    ix.inHole = false
    if prev and (#prev == 0 or moved > tracker.RESET) then
        prev = nil
    end
    -- the way followed since the last cold start (none: a reset, a layer's setFloor): a hole is believed only
    -- on a floor followed for HOLE_ANCHOR
    ix.sinceCold = prev and ((ix.sinceCold or 0) + moved) or 0
    -- the candidates carried along with the player (a hole, a gap): their surfaces as they were, at the
    -- player's position, the way walked since added to their reach
    local function carry()
        if prev then
            for i = 1, #prev do
                local cand = prev[i]
                cand.far = (cand.far or 0) + moved
                cand.x, cand.y = x, y
            end
            ix.cands = prev
        end
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
        ix.lookKind, ix.lookZ = "gap", nil
        if floor_ ~= was then
            ix.floor = floor_
            ix.cameFrom = was
            ix.fellFrom = nil
            ix.cands = nil
        else
            carry()
        end
        if ix.liquids[floor_] == nil then
            ix.swumIn = nil
        end
        return floor_, floor_ ~= was
    end
    -- the reach of every old candidate, once
    local sets = {}
    local hops = 0
    local box = nil
    if prev and tracker.PERSIST then
        local r0, c0 = floor(x - S.x0), floor(y - S.y0)
        box = { r0 - 1, r0 + 1, c0 - 1, c0 + 1 }
    end
    if prev then
        for i = 1, #prev do
            local d = logic.dist(prev[i].x, prev[i].y, x, y) + (prev[i].far or 0) + tracker.REACH
            local h = math.min(tracker.MAX_HOPS, math.ceil(d) + tracker.EXTRA_HOPS)
            if h > hops then hops = h end
            sets[i] = reached(S, prev[i].s, h, cache, box)
        end
    end
    -- the game says whether the player swims: on foot no liquid surface is a candidate (the piece tracker's
    -- rule too: a shore's shallow water held the player on the lake, Crystal Lake and Goldshire, 2026-10-19),
    -- swimming no dry one; unknown, both at a cost
    local new = {}
    local best = nil
    -- no surface here that any candidate walks, steps or falls onto (the hole rule below; only on a floor followed
    -- for HOLE_ANCHOR, and not beyond HOLE_MAX of walking in the hole)
    local allJump = prev ~= nil and tracker.HOLES ~= 0 and ix.sinceCold >= tracker.HOLE_ANCHOR
        and (prev[1].far or 0) + moved <= tracker.HOLE_MAX
    -- a cold start: the floor the module set (the game's area, the cell's default) is the prior, where it has a
    -- surface under the player; surfaces at another height start at PRIOR instead of 0 (one level, as the
    -- margin's rule: another piece at the prior's height is a question of names)
    local priorZ = nil
    if prev == nil and tracker.PRIOR ~= 0 then
        local nearest = nil
        for i = 1, #now do
            if now[i].piece == was then
                local dx, dy = now[i].x - x, now[i].y - y
                local off = dx * dx + dy * dy
                if nearest == nil or off < nearest then
                    nearest, priorZ = off, now[i].z
                end
            end
        end
    end
    -- (a layer entered where another layer's floor was held a moment ago, within RESET: that floor's height
    -- is the prior, not the module's floor of this layer; the Mystic Ward's shop entered from the hall at 502.8 took the
    -- floor 24 yd over it, ground trial gl1b, 2026-10-30)
    local carried = tracker.held
    if prev == nil and tracker.PRIOR ~= 0 and carried and carried.zone ~= zone
            and logic.dist(carried.x, carried.y, x, y) <= tracker.RESET then
        priorZ = carried.z
    end
    -- per surface the nearest dry floor over it in its own 1 yd column, a level or more up (THROUGH: a fall from
    -- higher than that lands on that floor first)
    local over = {}
    if prev and tracker.THROUGH ~= 0 then
        for i = 1, #now do
            local b = now[i]
            for k = 1, #now do
                local c = now[k]
                if not c.liquid and c.z > b.z + tracker.LEVEL and math.abs(c.x - b.x) <= 0.5 and math.abs(c.y - b.y) <= 0.5
                        and (over[i] == nil or c.z < over[i]) then
                    over[i] = c.z
                end
            end
        end
    end
    for i = 1, #now do
        local b = now[i]
        local local_ = 0
        if swimming ~= nil and b.liquid ~= swimming then
            local_ = nil
        end
        if local_ then
        local cost, fell, from, step = 0, false, nil, 0
        local risen = false   -- (the cheapest way here is a rise over RISE: see below)
        if priorZ and (b.z > priorZ + tracker.LEVEL or b.z < priorZ - tracker.LEVEL) then
            cost = tracker.PRIOR
        end
        if prev then
            cost = nil
            local kb = keyOf(b)
            for j = 1, #prev do
                local a = prev[j]
                local t
                local d = logic.dist(a.x, a.y, x, y)
                local dz = b.z - a.s.z
                if sets[j][kb] then
                    t = 0
                else
                    if d <= tracker.NEAR and dz < -tracker.LEVEL then
                        t = tracker.FALL
                        if over[i] and over[i] < a.s.z - tracker.LEVEL then
                            t = tracker.JUMP   -- through a floor (THROUGH)
                        end
                    elseif d <= tracker.NEAR and dz <= tracker.LEVEL and dz >= -tracker.LEVEL then
                        t = a.s.piece == b.piece and tracker.DETOUR or tracker.MISSING
                    elseif d <= tracker.NEAR and a.s.piece == b.piece and dz > 0 and dz <= tracker.STEEP then
                        t = tracker.MISSING
                    else
                        t = tracker.JUMP
                    end
                end
                -- (against the best chain: a candidate that survived an earlier jump, at JUMP within PRUNE,
                -- walks the surfaces it jumped onto at 0, but the chain still costs a jump)
                -- (HOLE_DZ against the chain's own floor, the candidates at 0: a surface a little above it is a
                -- missing step or a stair's foot, no hole; a candidate that jumped there earlier does not count)
                if a.cost + t < tracker.JUMP or (a.cost == 0 and d <= tracker.NEAR and dz <= tracker.HOLE_DZ) then
                    allJump = false
                end
                local v = a.cost + t
                -- (a rise over RISE, or a walk on from a candidate that rose so: kept apart, any other way here is
                -- taken first; the chain of a rise stays one, so a fall the real chain pays never makes it the best)
                local high = tracker.RISE ~= 0 and ((t >= tracker.JUMP and dz > tracker.RISE) or a.risen == true)
                -- (of two ways equally cheap, a fall from the floor held explains more than a walk on a
                -- floor long left: the guidance back onto a climb needs the floor fallen from)
                if cost == nil or (risen and not high) or (high == risen and (v < cost
                        or (v == cost and t == tracker.FALL and not fell and a.s.piece == was))) then
                    cost, fell, from, step, risen = v, t == tracker.FALL, a.s.piece, t, high
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
        local cand = { s = b, cost = cost, x = x, y = y, fell = fell, from = from, off = off, step = step, risen = risen }
        cand.cont = tracker.CHAIN == 1 and from == was
        new[#new + 1] = cand
        if better(cand, best, was) then
            best = cand
        end
        end
    end
    -- (RISE: the surfaces reached only by a rise no jump makes are dropped while another candidate here is explained
    -- by a walk, a fall or a missing step; the best is chosen again among the rest)
    if best and best.risen ~= nil and tracker.RISE ~= 0 then
        local explained = false
        for i = 1, #new do
            if not new[i].risen and new[i].step < tracker.JUMP then
                explained = true
                break
            end
        end
        if explained then
            local rest = {}
            best = nil
            for i = 1, #new do
                local cand = new[i]
                if not cand.risen then
                    rest[#rest + 1] = cand
                    if better(cand, best, was) then
                        best = cand
                    end
                end
            end
            new = rest
        else
            -- (nothing here explained but by jumps, the data misses something: a rise no jump makes stays a
            -- candidate, a MISSING step dearer than a jump onto a ledge, so a tie of the two goes to the ledge; where
            -- every candidate rose, nothing to weigh: the same cost on all of them changed no pick, but the walk on
            -- an upper floor reached so counted as a "switch" at every look, 1265 in Elwynn's walk set)
            local ledge = false
            for i = 1, #new do
                if not new[i].risen then
                    ledge = true
                    break
                end
            end
            best = nil
            for i = 1, #new do
                local cand = new[i]
                if cand.risen and ledge then
                    cand.cost = cand.cost + tracker.MISSING
                end
                if better(cand, best, was) then
                    best = cand
                end
            end
        end
    end
    if best == nil then
        -- every surface here is of the wrong kind (dry while swimming, wet on foot): nothing to decide
        ix.lookKind, ix.lookZ = "none", nil
        carry()
        return was, false
    end
    if allJump and ix.liquids[was] == nil and swimming ~= true then
        -- a hole of the walk graph: nothing under the player that any candidate reaches, and the floor held
        -- lies in this cell or one next to it (the piece tracker's rule for a lost floor, edges.lua: the
        -- zeppelin tower's base has no ground under the flights, the player walks it, bug 63); the floor and
        -- the candidates stay, carried along (a real jump up onto something else far from the floor held
        -- is still a jump: the cell test fails there)
        local r, c = logic.cellOf(zone, x, y)
        local near = false
        for dr = -1, 1 do
            for dc = -1, 1 do
                if logic.floorHere(zone, (r + dr) * zone.cols + c + dc, was) then
                    near = true
                end
            end
        end
        if near then
            carry()
            ix.inHole = true
            ix.lookKind, ix.lookZ = "hole", nil
            if tracker.debug then
                io.stderr:write(string.format("look %s %.1f %.1f floor %d HOLE (%d surfaces under, %d candidates carried)\n",
                    tostring(zone.key), x, y, was, #now, #prev))
            end
            return was, false
        end
    end
    -- what explained this look (offline checks, tools/walklog/module.lua WV_LOOKS=1: the looks no step explains are
    -- where the data lacks what the player walked on, STATE bug 86): "cold" a start with nothing held, "walk" a
    -- chain of steps from the best candidate held, "switch" a candidate that was not the best before took over,
    -- "fall", "missing" (a move at one height no steps explain), "jump"; also "gap", "hole", "none" above
    if prev == nil then
        ix.lookKind = "cold"
    elseif best.cost == 0 then
        ix.lookKind = "walk"
    elseif best.step >= tracker.JUMP then
        ix.lookKind = "jump"
    elseif best.fell then
        ix.lookKind = "fall"
    elseif best.step > 0 then
        ix.lookKind = "missing"
    else
        ix.lookKind = "switch"
    end
    ix.lookZ, ix.lookCost = best.s.z, best.cost
    tracker.held = { zone = zone, x = x, y = y, z = best.s.z }   -- (the floor held, for a layer entered next)
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
    if floor_ ~= was then
        ix.cameFrom = was
        -- (the piece of the candidate fallen from, not always the piece held: review 2026-10-19)
        ix.fellFrom = best.fell and best.from or nil
    end
    return floor_, floor_ ~= was
end

-- The height of the floor held on the layer `zone`: the cheapest candidate on its floor piece, or nil where the
-- tracker holds none (a reset, a cold start not looked at yet, a layer that has no surfaces).
function tracker.heldZ(zone)
    local ix = zone._index
    local cands = ix and ix.cands
    if not cands then
        return nil
    end
    local best = nil
    for i = 1, #cands do
        local c = cands[i]
        if c.s.piece == ix.floor and (best == nil or c.cost < best.cost) then
            best = c
        end
    end
    return best and best.s.z or nil
end

-- The floor piece of the layer `zone` with a dry surface under (x, y) within `dz` of the height `z` (the nearest), or
-- false where it has none there; nil where the layer has no surfaces (an older data file: nothing to tell by). With
-- `only`, that piece's surfaces alone.
function tracker.pieceAt(zone, x, y, z, dz, only)
    local S = zone.surf
    if not S then
        return nil
    end
    local found, fd = false, dz
    local now = under(S, x, y, {})
    for i = 1, #now do
        local s = now[i]
        local d = s.z > z and s.z - z or z - s.z
        if not s.liquid and d <= fd and (only == nil or s.piece == only) then
            found, fd = s.piece, d
        end
    end
    return found
end

-- Forgets the candidates (a layer's reset, a teleport): the next look starts from every surface under it.
function tracker.reset(zone)
    local ix = zone._index
    if ix then
        ix.cands = nil
        ix.floorSure = nil
    end
end
