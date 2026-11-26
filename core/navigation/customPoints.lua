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
-- The addon may ship points as well (customPoints.shipped, filled by data files of a version): a shipped point is
-- handed to the player's list once and is then his like any other. Nothing in his list is ever replaced: his names
-- stay, and a shipped point he deleted does not come back (shippedSeen remembers every one handed over).
--
-- Pure Lua (headless tests): the store is a plain table the module keeps in the account's saved variables.
--   store = { waypoints = { point, ... }, dangers = { point, ... }, nextId = n, shippedSeen = { [id] = true } }
--   point = { id, name (nil: the kind's default name), x, y, z (or nil), map (UnitPosition's map), radius (dangers;
--             nil: DANGER_RADIUS), nameCleared (the player cleared the name: a shipped name is not filled in again) }

local customPoints = {}
WowVision.customPoints = customPoints

customPoints.LISTS = { waypoint = "waypoints", danger = "dangers", blocked = "blocked" }
customPoints.BLOCKED_PENALTY = 1000  -- yd added to a blocked passage's link (the manual new route's penalty)
customPoints.BLOCKED_TOLERANCE = 2   -- yd: a blocked passage counts only while its waypoints still lie where they did
customPoints.BLOCKED_SPOT_RADIUS = 12  -- yd: the default circle of a blocked spot
customPoints.BLOCKED_HEIGHT_BAND = 8   -- yd above and below a blocked spot's height (a bridge or a cave is not hit)
customPoints.DANGER_RADIUS = 45      -- yd around a custom danger point (the radius of a monster far above the player)
customPoints.shipped = {}            -- { { id = "wv:...", kind = "danger" | "waypoint", x, y, z, map, name, radius }, ... }

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
-- position (x, y) is the link's middle. The same link saved again is not added twice. Returns the point.
function customPoints.addBlocked(store, a, b, ax, ay, bx, by, map)
    for _, point in ipairs(store.blocked) do
        if (point.a == a and point.b == b) or (point.a == b and point.b == a) then
            return point
        end
    end
    local id = "u" .. store.nextId
    store.nextId = store.nextId + 1
    local point = { id = id, a = a, b = b, ax = ax, ay = ay, bx = bx, by = by, map = map,
        x = (ax + bx) / 2, y = (ay + by) / 2 }
    store.blocked[#store.blocked + 1] = point
    return point
end

-- A blocked spot at x, y (z may be nil) on map; radius nil: BLOCKED_SPOT_RADIUS. Returns the point.
function customPoints.addBlockedSpot(store, x, y, z, map, radius)
    local id = "u" .. store.nextId
    store.nextId = store.nextId + 1
    local point = { id = id, x = x, y = y, z = z, map = map, radius = radius or customPoints.BLOCKED_SPOT_RADIUS }
    store.blocked[#store.blocked + 1] = point
    return point
end

-- The route penalties of the blocked passages on map: { [a] = { [b] = yd }, [b] = { [a] = yd } }.
--   positionOf(id) -> x, y of a waypoint of the loaded network (nil when unknown): a link whose waypoints moved (other
--     route data) or are unknown is left out
--   linksNear(point) -> { { a, b }, ... }: the links touching a blocked spot (radius, height band); nil: spots are
--     left out
-- Returns the table and how many links it holds.
function customPoints.blockedPenalties(store, map, positionOf, linksNear)
    local penalties, count = {}, 0
    local tolerance = customPoints.BLOCKED_TOLERANCE
    local function near(id, x, y)
        local px, py = positionOf(id)
        return px ~= nil and x ~= nil and (px - x) ^ 2 + (py - y) ^ 2 <= tolerance * tolerance
    end
    local function add(a, b)
        penalties[a] = penalties[a] or {}
        penalties[b] = penalties[b] or {}
        if penalties[a][b] == nil then
            count = count + 1
        end
        -- one penalty per link, however many passages name it
        penalties[a][b] = customPoints.BLOCKED_PENALTY
        penalties[b][a] = customPoints.BLOCKED_PENALTY
    end
    for _, point in ipairs(store.blocked) do
        if point.map == map then
            if point.a ~= nil and point.b ~= nil then
                if near(point.a, point.ax, point.ay) and near(point.b, point.bx, point.by) then
                    add(point.a, point.b)
                end
            elseif linksNear ~= nil and point.x ~= nil then
                for _, link in ipairs(linksNear(point) or {}) do
                    add(link[1], link[2])
                end
            end
        end
    end
    return penalties, count
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
