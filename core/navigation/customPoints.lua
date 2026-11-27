-- Custom points (user request 2026-11-27): places the player saves for himself, kept per account.
--   waypoint  a place to navigate to; it joins the destination list of the navigation window (F10)
--   danger    a place a route keeps away from (a monster the route data does not know); it joins the destination list
--             too, and the route engine's safe routes (WowNav) count it like a monster spawn
--   blocked   a passage of the route network the player cannot get through (a slope too steep in the game); every
--             route puts a penalty on it, so it is used only when there is no way around (2026-11-27). Not a
--             destination. Two forms:
--               a link   two waypoints of the network (a, b with their positions ax, ay, bx, by)
--               a spot   x, y (z optional) and a radius: every link touching a network waypoint inside the circle
--                        (within BLOCKED_HEIGHT_BAND of z, when z is known) -- a rock top with many parallel links
--             Only WowNav's routes use them (WoW: Forever, camelot/wownav/blocked.lua): shipped ones, and the link the
--             manual new route saves when the player is stuck on it. A workaround for defects of the route data.
-- The addon may ship points as well (customPoints.shipped, filled by data files of a version): a shipped point is
-- handed to the player's list once and is then his like any other. Nothing in his list is ever replaced: his names
-- stay, and a shipped point he deleted does not come back (shippedSeen remembers every one handed over).
--
-- Pure Lua (headless tests): the store is a plain table the module keeps in the account's saved variables.
--   store = { waypoints = { point, ... }, dangers = { point, ... }, blocked = { point, ... }, nextId = n,
--             shippedSeen = { [id] = true } }
--   point = { id, name (nil: the kind's default name), x, y, z (or nil), map (UnitPosition's map), radius (dangers:
--             nil means DANGER_RADIUS; blocked spots: nil means BLOCKED_SPOT_RADIUS), nameCleared (the player cleared
--             the name: a shipped name is not filled in again), shipped (handed over from customPoints.shipped) }
--   a blocked link has a, b (the network's waypoint ids) and ax, ay, bx, by (their positions); x, y is its middle

local customPoints = {}
WowVision.customPoints = customPoints

local abs = math.abs

customPoints.LISTS = { waypoint = "waypoints", danger = "dangers", blocked = "blocked" }
customPoints.BLOCKED_PENALTY = 1000  -- yd added to a blocked passage's link (the manual new route's penalty)
customPoints.BLOCKED_TOLERANCE = 2   -- yd: a blocked passage counts only while its waypoints still lie where they did
customPoints.BLOCKED_SPOT_RADIUS = 12  -- yd: the default circle of a blocked spot
customPoints.BLOCKED_HEIGHT_BAND = 8   -- yd above and below a blocked spot's height (a bridge or a cave is not hit)
customPoints.DANGER_RADIUS = 45      -- yd around a custom danger point (the radius of a monster far above the player)
-- { { id = "wv:...", kind = "danger" | "waypoint" | "blocked", x, y, z, map, name, radius, and a blocked link's a, b,
-- ax, ay, bx, by }, ... }
customPoints.shipped = {}

local function listOf(store, kind)
    local key = customPoints.LISTS[kind]
    if key == nil then
        error("unknown custom point kind " .. tostring(kind))
    end
    return store[key]
end

-- The store inside the saved table `data` (created on first use). Only ever completes what is missing.
function customPoints.store(data)
    local store = data.customPoints
    if type(store) ~= "table" then
        store = {}
        data.customPoints = store
    end
    if type(store.waypoints) ~= "table" then
        store.waypoints = {}
    end
    if type(store.dangers) ~= "table" then
        store.dangers = {}
    end
    if type(store.blocked) ~= "table" then
        store.blocked = {}
    end
    if type(store.shippedSeen) ~= "table" then
        store.shippedSeen = {}
    end
    if type(store.nextId) ~= "number" then
        store.nextId = 1
    end
    return store
end

local function copyPoint(point)
    local copy = {}
    for key, value in pairs(point) do
        if key ~= "kind" then
            copy[key] = value
        end
    end
    return copy
end

-- Hands the shipped points the store has never had to it (appended). A shipped point the player already has and
-- never named gets the name the addon ships for it now (a name is only ever filled in, never replaced; one the player
-- cleared stays cleared). Returns how many points were added, then how many were named.
function customPoints.mergeShipped(store, shipped)
    local added, named = 0, 0
    for _, point in ipairs(shipped or {}) do
        local known = point.id ~= nil and customPoints.LISTS[point.kind] ~= nil and store.shippedSeen[point.id]
        if known and point.name ~= nil then
            local own = customPoints.find(store, point.kind, point.id)
            if own ~= nil and own.name == nil and not own.nameCleared then
                own.name = point.name
                named = named + 1
            end
        end
        if point.id ~= nil and customPoints.LISTS[point.kind] ~= nil and not store.shippedSeen[point.id] then
            store.shippedSeen[point.id] = true
            local entry = copyPoint(point)
            entry.shipped = true
            if point.kind == "danger" and entry.radius == customPoints.DANGER_RADIUS then
                entry.radius = nil
            end
            local list = listOf(store, point.kind)
            list[#list + 1] = entry
            added = added + 1
        end
    end
    return added, named
end

-- A new point of `kind` at x, y (z may be nil) on `map`. name nil: the kind's default name. Returns the point.
function customPoints.add(store, kind, x, y, z, map, name)
    local list = listOf(store, kind)
    local id = "u" .. store.nextId
    store.nextId = store.nextId + 1
    local point = { id = id, name = name, x = x, y = y, z = z, map = map }
    list[#list + 1] = point
    return point
end

function customPoints.find(store, kind, id)
    for index, point in ipairs(listOf(store, kind)) do
        if point.id == id then
            return point, index
        end
    end
    return nil
end

-- A new name (empty or blank: back to the kind's default name, and a shipped name is not filled in again). True when
-- the point exists.
function customPoints.rename(store, kind, id, name)
    local point = customPoints.find(store, kind, id)
    if point == nil then
        return false
    end
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$")
    end
    point.name = (name ~= nil and name ~= "") and name or nil
    point.nameCleared = point.name == nil or nil
    return true
end

-- Deletes a point. A shipped one stays in shippedSeen, so it is not handed over again. True when it existed.
function customPoints.remove(store, kind, id)
    local _, index = customPoints.find(store, kind, id)
    if index == nil then
        return false
    end
    table.remove(listOf(store, kind), index)
    return true
end

-- The points of `kind` on `map` (every map when nil), in the order they were saved.
function customPoints.list(store, kind, map)
    local out = {}
    for _, point in ipairs(listOf(store, kind)) do
        if map == nil or point.map == map then
            out[#out + 1] = point
        end
    end
    return out
end

-- The name to say: the point's own, else the kind's default (L: the locale table).
local DEFAULT_NAMES = { danger = "Monster spawn", blocked = "Blocked passage", waypoint = "Custom waypoint" }
function customPoints.label(point, kind, L)
    if point.name ~= nil and point.name ~= "" then
        return point.name
    end
    return L[DEFAULT_NAMES[kind] or DEFAULT_NAMES.waypoint]
end

-- A blocked passage: the link between the network's waypoints a and b (positions ax, ay and bx, by) on map. Its
-- position (x, y) is the link's middle. Returns the point, then what happened: "added", "known" (the same link at the
-- same positions is there already: nothing changes), or "moved" (the same ids at other positions: the route data
-- changed, so the old entry, which no route feels any more, is replaced by a new one with its name; the third value is
-- the old entry).
function customPoints.addBlocked(store, a, b, ax, ay, bx, by, map)
    local tolerance2 = customPoints.BLOCKED_TOLERANCE ^ 2
    local function at(x, y, px, py)
        return x ~= nil and px ~= nil and (x - px) ^ 2 + (y - py) ^ 2 <= tolerance2
    end
    local stale = nil
    for index, point in ipairs(store.blocked) do
        if point.map == map then
            local same, swapped = point.a == a and point.b == b, point.a == b and point.b == a
            if (same and at(point.ax, point.ay, ax, ay) and at(point.bx, point.by, bx, by))
                or (swapped and at(point.ax, point.ay, bx, by) and at(point.bx, point.by, ax, ay)) then
                return point, "known"
            end
            if (same or swapped) and stale == nil then
                stale = index
            end
        end
    end
    local old = nil
    if stale ~= nil then
        old = table.remove(store.blocked, stale)
    end
    local id = "u" .. store.nextId
    store.nextId = store.nextId + 1
    local point = { id = id, a = a, b = b, ax = ax, ay = ay, bx = bx, by = by, map = map,
        x = (ax + bx) / 2, y = (ay + by) / 2, name = old ~= nil and old.name or nil }
    store.blocked[#store.blocked + 1] = point
    return point, old ~= nil and "moved" or "added", old
end

-- A blocked spot at x, y (z may be nil) on map; radius nil: BLOCKED_SPOT_RADIUS. A spot at the same place (within
-- BLOCKED_TOLERANCE, the same height and radius) is not added twice. Returns the point, then "added" or "known".
function customPoints.addBlockedSpot(store, x, y, z, map, radius)
    radius = radius or customPoints.BLOCKED_SPOT_RADIUS
    local tolerance = customPoints.BLOCKED_TOLERANCE
    for _, point in ipairs(store.blocked) do
        if point.a == nil and point.map == map and point.x ~= nil and (point.x - x) ^ 2 + (point.y - y) ^ 2
            <= tolerance * tolerance and (point.z == nil) == (z == nil) and (z == nil or abs(point.z - z) <= tolerance)
            and abs((point.radius or customPoints.BLOCKED_SPOT_RADIUS) - radius) <= tolerance then
            return point, "known"
        end
    end
    local id = "u" .. store.nextId
    store.nextId = store.nextId + 1
    local point = { id = id, x = x, y = y, z = z, map = map, radius = radius }
    store.blocked[#store.blocked + 1] = point
    return point, "added"
end

-- The links of one zone of the route network that the blocked passages on map put a penalty on: { { a, b }, ... }
-- (the same link may come more than once; the caller penalises it once). zone tells about the zone:
--   owns(id) -> true for a waypoint of this zone
--   position(id) -> x, y of a waypoint of this zone: a link whose waypoints moved (other route data) is left out
--   touches(x, y, radius) -> true when the circle meets the zone
--   linksNear(point, radius) -> { { a, b }, ... }: the zone's links touching a blocked spot (radius, height band)
function customPoints.blockedInZone(store, map, zone)
    local links = {}
    local tolerance2 = customPoints.BLOCKED_TOLERANCE ^ 2
    local function at(id, x, y)
        local px, py = zone.position(id)
        return px ~= nil and x ~= nil and (px - x) ^ 2 + (py - y) ^ 2 <= tolerance2
    end
    for _, point in ipairs(store.blocked) do
        if point.map == map then
            if point.a ~= nil and point.b ~= nil then
                if zone.owns(point.a) and zone.owns(point.b) and at(point.a, point.ax, point.ay)
                    and at(point.b, point.bx, point.by) then
                    links[#links + 1] = { point.a, point.b }
                end
            elseif point.x ~= nil then
                local radius = point.radius or customPoints.BLOCKED_SPOT_RADIUS
                if zone.touches(point.x, point.y, radius) then
                    for _, link in ipairs(zone.linksNear(point, radius)) do
                        links[#links + 1] = link
                    end
                end
            end
        end
    end
    return links
end

-- The custom danger points on `map` that lie in a zone, as monster spawns for the route engine's danger table:
-- { { x, y, z, name, radius } }. inZone(x, y) -> true for a point of the zone asked for. The name is unique per
-- point, so the engine's merging of spawns of one name close together never joins two of them.
function customPoints.dangerSpawns(store, map, inZone)
    local out = {}
    for _, point in ipairs(store.dangers) do
        if point.map == map and (inZone == nil or inZone(point.x, point.y)) then
            out[#out + 1] = {
                x = point.x, y = point.y, z = point.z, name = "custom:" .. point.id,
                radius = point.radius or customPoints.DANGER_RADIUS,
            }
        end
    end
    return out
end
