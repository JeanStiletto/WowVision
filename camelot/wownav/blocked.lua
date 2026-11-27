-- The player's blocked passages (core/navigation/customPoints.lua, kind "blocked") on WowNav's network: a workaround
-- for links of the route data the player cannot get through in the game (2026-11-27).
--
-- penaltyTable: the penalty table every new route starts with (route.lua Route:reset through env.penalties). It is
-- filled per zone when the search first asks for a waypoint of that zone (his Pass reads penalties[id] once per
-- expanded waypoint), so a zone decoded later, one on the far side of a transit, or one of another map gets its
-- passages too. Seam steps between zones carry no penalty in his search, so only links inside a zone are penalised.
--
-- stuckSave: what the manual new route saves for the steering pair the player is stuck on (module.lua newRoute).
--
-- Pure apart from N (the engine), so the headless tests run it on the real data.

local blocked = {}
WowVision.wownavBlocked = blocked

local floor, abs, sqrt, max, min = math.floor, math.abs, math.sqrt, math.max, math.min

blocked.SAVE_DISTANCE = 10   -- yd in the plane: the manual new route saves the link only when the player is this near

-- The links touching a spot's waypoints in one decoded zone (a waypoint inside the circle, within the height band of
-- the spot's height when it has one): { { a, b }, ... }, both directions of a two-way link. The links leaving each
-- waypoint inside the circle (zone.adj); a one-way link that only enters the circle is not listed (a route through the
-- spot still has to leave it over a listed one). Cached per decoded zone table, so a zone decoded again is read again.
local spotCache = setmetatable({}, { __mode = "k" })
local statsOf = setmetatable({}, { __mode = "k" })   -- [penalty table] = its stats
function blocked.spotLinks(N, zoneId, point, radius, band)
    local zone = N.zones[zoneId]
    if zone == nil then
        return {}
    end
    local perZone = spotCache[zone]
    if perZone == nil then
        perZone = {}
        spotCache[zone] = perZone
    end
    local key = point.x .. ":" .. point.y .. ":" .. tostring(point.z) .. ":" .. radius .. ":" .. band
    local links = perZone[key]
    if links ~= nil then
        return links
    end
    links = {}
    local base, zz, adj = zone.base, zone.z, zone.adj
    for _, id in ipairs(N.NodesWithin(zoneId, point.x, point.y, radius)) do
        local i = id - base + 1
        if point.z == nil or abs(zz[i] - point.z) <= band then
            local out = adj[i]
            for j = 1, #out, 2 do
                links[#links + 1] = { id, base + out[j] }
            end
        end
    end
    perZone[key] = links
    return links
end

-- The zone as customPoints.blockedInZone sees it.
local function zoneView(N, cp, zoneId)
    local entry = N.index[zoneId]
    local boxes = entry ~= nil and entry.worldBoxes or {}
    return {
        owns = function(id)
            return type(id) == "number" and id < N.VIRT_BASE and floor(id / N.ZONE_BASE) == zoneId
        end,
        position = function(id)
            local x, y = N.Position(id)
            return x, y
        end,
        -- the circle meets one of the zone's boxes
        touches = function(x, y, radius)
            for _, box in pairs(boxes) do
                local dx = max(box.xmin - x, 0, x - box.xmax)
                local dy = max(box.ymin - y, 0, y - box.ymax)
                if dx * dx + dy * dy <= radius * radius then
                    return true
                end
            end
            return false
        end,
        linksNear = function(point, radius)
            return blocked.spotLinks(N, zoneId, point, radius, cp.BLOCKED_HEIGHT_BAND)
        end,
    }, entry ~= nil and entry.nativeMapId or N.activeMapId
end

-- A fresh penalty table for a new route: { [a] = { [b] = yd } }, filled per zone on first use (see the top). store nil
-- or without blocked passages: a plain empty table. Returns the table and its stats: { links = links penalised so far,
-- zones = zones filled so far } (the module's trail).
function blocked.penaltyTable(N, cp, store)
    local stats = { links = 0, zones = 0 }
    if store == nil or #store.blocked == 0 then
        return {}, stats
    end
    local filled = {}
    local rows = {}
    local penalty = cp.BLOCKED_PENALTY
    setmetatable(rows, {
        __index = function(t, id)
            if type(id) ~= "number" or id >= N.VIRT_BASE then
                return nil
            end
            local zoneId = floor(id / N.ZONE_BASE)
            if filled[zoneId] or N.zones[zoneId] == nil then
                return nil
            end
            filled[zoneId] = true
            stats.zones = stats.zones + 1
            local view, map = zoneView(N, cp, zoneId)
            for _, link in ipairs(cp.blockedInZone(store, map, view)) do
                local a, b = link[1], link[2]
                local ra, rb = rawget(t, a), rawget(t, b)
                if ra == nil then
                    ra = {}
                    rawset(t, a, ra)
                end
                if rb == nil then
                    rb = {}
                    rawset(t, b, rb)
                end
                -- one penalty per link, however many passages name it
                if ra[b] == nil then
                    stats.links = stats.links + 1
                end
                ra[b], rb[a] = penalty, penalty
            end
            return rawget(t, id)
        end,
    })
    statsOf[rows] = stats
    return rows, stats
end

-- The stats of a table penaltyTable made (nil for another table).
function blocked.stats(penalties)
    return statsOf[penalties]
end

-- Puts what stuckSave found on a running route's table at once (the zones there are filled already): the manual new
-- route's own penalty (Route:penalizeCurrentLink) lies on the steering pair, which is no link of the network around a
-- branch waypoint or across a seam.
function blocked.apply(N, cp, penalties, found)
    local penalty = cp.BLOCKED_PENALTY
    local function put(a, b)
        local ra, rb = penalties[a], penalties[b]
        if ra == nil then
            ra = {}
            rawset(penalties, a, ra)
        end
        if rb == nil then
            rb = {}
            rawset(penalties, b, rb)
        end
        ra[b], rb[a] = ra[b] or penalty, rb[a] or penalty
    end
    for _, link in ipairs(found.links or {}) do
        put(link[1], link[2])
    end
    local spot = found.spot
    if spot ~= nil then
        local zones = {}
        for _, id in ipairs(spot.ends or {}) do
            zones[floor(id / N.ZONE_BASE)] = true
        end
        for zoneId in pairs(zones) do
            for _, link in ipairs(blocked.spotLinks(N, zoneId, spot, spot.radius, cp.BLOCKED_HEIGHT_BAND)) do
                put(link[1], link[2])
            end
        end
    end
end

-- True when b is a's neighbour in a's zone (a link in either direction).
local function linked(N, a, b)
    if floor(a / N.ZONE_BASE) ~= floor(b / N.ZONE_BASE) then
        return false
    end
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        for _, neighbour in ipairs(N.Neighbors(pair[1])) do
            if neighbour[1] == pair[2] then
                return true
            end
        end
    end
    return false
end

-- What the manual new route saves for the steering pair a -> b (real waypoints) while the player stands at px, py
-- (pz: his estimated height, nil when not known: the plane only):
--   { links = { { a, b }, ... } }  the network links between them: a itself, or the two around a branch waypoint his
--                                  steering targets leave out (N.SteeringTargets)
--   { spot = { x, y, z, radius, ends = { a, b } } }  no link joins them (a seam step between zones): the spot
--                                  covering both ends
--   nil, reason                    "far" (the player is not near the pair: more than SAVE_DISTANCE in the plane, or
--                                  outside the height band) or "none" (nothing that a route would feel)
function blocked.stuckSave(N, cp, a, b, px, py, pz)
    local ax, ay, az = N.Position(a)
    local bx, by, bz = N.Position(b)
    local dx, dy = bx - ax, by - ay
    local length2 = dx * dx + dy * dy
    local t = length2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length2)) or 0
    local cx, cy, cz = ax + t * dx, ay + t * dy, az + t * (bz - az)
    local band = cp.BLOCKED_HEIGHT_BAND
    if (px - cx) ^ 2 + (py - cy) ^ 2 > blocked.SAVE_DISTANCE ^ 2 or (pz ~= nil and abs(pz - cz) > band) then
        return nil, "far"
    end
    if linked(N, a, b) then
        return { links = { { a, b } } }
    end
    for _, neighbour in ipairs(N.Neighbors(a)) do
        local c = neighbour[1]
        local p, q = N.BranchPair(c)
        if p ~= nil and ((p == a and q == b) or (p == b and q == a)) and linked(N, c, b) then
            return { links = { { a, c }, { c, b } } }
        end
    end
    -- a seam step: his search puts no penalty on it, so the waypoints at both ends are blocked (their links)
    if abs(az - bz) / 2 > band then
        return nil, "none"
    end
    return { spot = { x = (ax + bx) / 2, y = (ay + by) / 2, z = (az + bz) / 2, radius = sqrt(length2) / 2 + 1,
        ends = { a, b } } }
end

