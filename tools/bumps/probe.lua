-- LOCAL (local-play only): does an object hold the player? Reads the collision probe (WowVisionDump.bumpProbe and
-- bumpProbeBefore, written by core/navigation/bumps.lua) and compares every pushing look with the footprints of
-- the objects near it: the bump data's tables, chairs, benches, desks and stools, and the extra targets of a file
-- (a Lua list of { map, x, y, hl, hw, angle (radians, the long axis), height, name, source }, e.g. server-spawned
-- mailboxes and chairs).
--
--   luajit tools/bumps/probe.lua <client> <SavedVariables/WowVision.lua> [targets file]
--
-- Per object approached (a look within NEAR yd of its footprint):
-- - through: looks with the player's centre inside the footprint (shrunk by INSIDE): the player stood where the
--   object stands, so it holds nobody (or they stood on top of it: jumping onto low things spoils the test);
-- - held: looks with the wall detection's "blocked", the player pushing toward the footprint (within AIM radians
--   of the way to its nearest point) and the centre at most HELD yd from its edge (the player's own half width
--   is about 0.3 to 0.4 yd): pushing against it stopped them;
-- - gap: the smallest edge distance of the held looks.
-- Verdict: "collides" with HELD_MIN held looks from at least two pushes and no look through; "no collision" with
-- THROUGH_MIN looks through; else "unsure". Every line also names the other objects within reach of the held
-- looks, so a held look that a neighbour explains is visible.
local NEAR, INSIDE, AIM, HELD = 2.0, 0.1, math.rad(50), 0.8
local HELD_MIN, THROUGH_MIN = 3, 2
local WORDS = { table = true, chair = true, bench = true, desk = true, stool = true }

local client, svFile, targetsFile = arg[1], arg[2], arg[3]
assert(client and svFile, "usage: luajit tools/bumps/probe.lua <client> <WowVision.lua> [targets file]")
local bl = dofile("tools/bumps/load.lua")(client)

-- the probe's lines in the order taken: the previous session's ring, then this one's
local env = {}
local chunk = assert(loadfile(svFile))
setfenv(chunk, env)
chunk()
local dump = env.WowVisionDump or {}
local looks = {}
local function readRing(ring)
    if type(ring) ~= "table" or type(ring.lines) ~= "table" then
        return
    end
    local n, start = ring.kept or #ring.lines, ring.nextAt or 1
    for k = 0, n - 1 do
        local line = ring.lines[(start - 1 + k) % n + 1]
        if line then
            local t, map, x, y, facing, push, moved, blocked = line:match(
                "^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
            if t then
                looks[#looks + 1] = {
                    t = tonumber(t), map = tonumber(map), x = tonumber(x), y = tonumber(y),
                    push = tonumber(push), moved = tonumber(moved), blocked = blocked == "1",
                }
            end
        end
    end
end
readRing(dump.bumpProbeBefore)
readRing(dump.bumpProbe)
print(string.format("%d pushing looks, %d of them blocked", #looks, (function()
    local c = 0
    for _, l in ipairs(looks) do
        c = c + (l.blocked and 1 or 0)
    end
    return c
end)()))
if #looks == 0 then
    return
end

-- the targets: extra file + the bump data's furniture near the looks
local targets = {}
local seen = {}
if targetsFile then
    for _, t in ipairs(dofile(targetsFile)) do
        -- (a spot spawned twice, under two entries, counts once)
        local id = string.format("%d %.1f %.1f %s", t.map, t.x, t.y, t.name)
        if not seen[id] then
            seen[id] = true
            targets[#targets + 1] = t
        end
    end
end
for _, l in ipairs(looks) do
    local key = math.floor(l.x / 8) .. " " .. math.floor(l.y / 8) .. " " .. l.map
    if not seen[key] then
        seen[key] = true
        for _, o in ipairs(bl.objectsNear(l.map, l.x, l.y, 12) or {}) do
            if WORDS[o.name] then
                local id = string.format("%.1f %.1f", o.x, o.y)
                if not seen[id] then
                    seen[id] = true
                    targets[#targets + 1] = { map = l.map, x = o.x, y = o.y, hl = o.halfLength, hw = o.halfWidth,
                        angle = o.angle, name = o.name, source = "bump data" }
                end
            end
        end
    end
end

-- the distance from a point to a footprint's edge (0 inside) and the nearest point of it; inside: how deep
local function toBox(t, x, y)
    local c, s = math.cos(t.angle), math.sin(t.angle)
    local dx, dy = x - t.x, y - t.y
    local u, v = dx * c + dy * s, -dx * s + dy * c
    local cu = math.max(-t.hl, math.min(t.hl, u))
    local cv = math.max(-t.hw, math.min(t.hw, v))
    local du, dv = u - cu, v - cv
    local outside = math.sqrt(du * du + dv * dv)
    local depth = math.min(t.hl - math.abs(u), t.hw - math.abs(v))
    return outside, t.x + cu * c - cv * s, t.y + cu * s + cv * c, depth
end

local results = {}
for _, t in ipairs(targets) do
    local r = { t = t, near = 0, through = 0, held = 0, pushes = 0, gap = math.huge, lastHeld = -math.huge }
    for _, l in ipairs(looks) do
        if l.map == t.map and math.abs(l.x - t.x) < 6 and math.abs(l.y - t.y) < 6 then
            local d, nx, ny, depth = toBox(t, l.x, l.y)
            if d <= NEAR then
                r.near = r.near + 1
                if d == 0 and depth >= INSIDE then
                    r.through = r.through + 1
                elseif l.blocked and d <= HELD then
                    local way = math.atan2(ny - l.y, nx - l.x)
                    local off = math.abs((l.push - way + math.pi) % (2 * math.pi) - math.pi)
                    if off <= AIM then
                        r.held = r.held + 1
                        r.gap = math.min(r.gap, d)
                        if l.t - r.lastHeld > 2 then
                            r.pushes = r.pushes + 1
                        end
                        r.lastHeld = l.t
                    end
                end
            end
        end
    end
    if r.near > 0 then
        results[#results + 1] = r
    end
end
table.sort(results, function(a, b)
    return a.near > b.near
end)
print(string.format("%d objects approached within %.1f yd", #results, NEAR))
for _, r in ipairs(results) do
    local t = r.t
    local verdict = "unsure"
    if r.through >= THROUGH_MIN then
        verdict = "no collision (stood inside it)"
    elseif r.held >= HELD_MIN and r.pushes >= 2 then
        verdict = "collides"
    end
    local others = {}
    if r.held > 0 then
        for _, o in ipairs(bl.objectsNear(t.map, t.x, t.y, math.max(t.hl, t.hw) + 1.5) or {}) do
            if math.abs(o.x - t.x) > 0.2 or math.abs(o.y - t.y) > 0.2 then
                others[#others + 1] = string.format("%s %.1f yd", o.name, o.distance)
            end
        end
    end
    print(string.format("%s (%s) at %.1f %.1f, %.1f x %.1f yd: %s; looks near %d, through %d, held %d in %d pushes%s%s",
        t.name, t.source, t.x, t.y, 2 * t.hl, 2 * t.hw, verdict, r.near, r.through, r.held, r.pushes,
        r.held > 0 and string.format(", smallest gap %.2f yd", r.gap) or "",
        #others > 0 and ("; also near: " .. table.concat(others, ", ")) or ""))
end
