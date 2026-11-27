-- Custom points (user request 2026-11-27): places the player saves for himself, kept per account.
--   waypoint  a place to navigate to; it joins the destination list of the navigation window (F10)
--   danger    a place a route keeps away from (a monster the route data does not know); it joins the destination list
--             too, and the route engine's safe routes (WowNav) count it like a monster spawn
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

customPoints.LISTS = { waypoint = "waypoints", danger = "dangers" }
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
    if type(store.shippedSeen) ~= "table" then
        store.shippedSeen = {}
    end
    if type(store.nextId) ~= "number" then
        store.nextId = 1
    end
    return store
end

local function copyPoint(point)
    return {
        id = point.id, name = point.name, x = point.x, y = point.y, z = point.z, map = point.map,
        radius = point.radius, shipped = point.shipped,
    }
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
            if entry.radius == customPoints.DANGER_RADIUS then
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
function customPoints.label(point, kind, L)
    if point.name ~= nil and point.name ~= "" then
        return point.name
    end
    return kind == "danger" and L["Monster spawn"] or L["Custom waypoint"]
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

-- ---- changes made while the account store is provisional (WoW: Forever hands the account's saved variables over
-- after the addon loaded; core/WowVision.lua bindGlobalStore). They go into the provisional store, which is saved as
-- the account's when the client never hands one over, and each is noted in a journal: when the client's store
-- arrives, replay makes the same changes there.
--   entry = { op = "add" | "rename" | "remove", kind, id, x, y, z, map, name }

-- The journal entry for a change of `point` (for "add" and "rename": its name after the change).
function customPoints.journalEntry(op, kind, point)
    return {
        op = op, kind = kind, id = point.id, x = point.x, y = point.y, z = point.z, map = point.map, name = point.name,
    }
end

-- Makes the journal's changes in `store`. An added point gets an id of this store; a renamed or deleted point is found
-- by its id and must still lie where it lay (else it is another point, and the change is dropped). Returns how many
-- changes were made.
function customPoints.replay(store, journal)
    local ids = {}
    local done = 0
    for _, entry in ipairs(journal or {}) do
        if entry.op == "add" then
            ids[entry.id] = customPoints.add(store, entry.kind, entry.x, entry.y, entry.z, entry.map, entry.name).id
            done = done + 1
        else
            local id = ids[entry.id]
            local point = customPoints.find(store, entry.kind, id or entry.id)
            if point ~= nil and id == nil and (point.x ~= entry.x or point.y ~= entry.y) then
                point = nil
            end
            if point ~= nil then
                if entry.op == "rename" then
                    customPoints.rename(store, entry.kind, point.id, entry.name)
                else
                    customPoints.remove(store, entry.kind, point.id)
                end
                done = done + 1
            end
        end
    end
    return done
end
