-- The places list (Alt-F10): the zones, their subzones, the things in them (named buildings,
-- buildings with a use, squares, landmarks, a city's shops) and the named rooms of a building,
-- sorted by distance, from the data addon's places files (wv-surroundings tools/destinations.py).
-- Where each entry leads was worked out offline; this file only picks the nearest of an entry's
-- points and sorts. No WoW API here: the module (placesUi.lua) passes in the position, the
-- subzone the game says, and whether the character explored a subzone (discovery mode).

local logic = WowVision.surroundingsLogic

logic.PLACES_FORMAT = 1
logic.IN_SIGHT = 150 -- discovery mode: a thing in no subzone is listed this close (what one sees around)

local function points(flat, stride)
    local out = {}
    for i = 1, #flat - stride + 1, stride do
        out[#out + 1] = { x = flat[i], y = flat[i + 1], ox = stride >= 4 and flat[i + 2] or nil,
            oy = stride >= 4 and flat[i + 3] or nil }
    end
    return out
end

-- The data of one places file with the names of `locale` put in place, kept on the raw table.
-- zones: {id, name, ui (the UI map), open (a map without exploration overlays, a city's: shown
-- whole), items, areas}; areas: {zone, area (the area table's id, 0 a district), name, overlay,
-- heart (points), doors {x, y, from (an area of this list, 0 the zone's own land), road}, checks
-- (points the game is asked about), items}; items: {kind, name, targets (points; ox, oy the point
-- outside a doorway routed to first), rooms}.
function logic.placesUnpack(raw, locale)
    if raw._unpacked then
        return raw._unpacked
    end
    local names = raw["names_" .. tostring(locale)] or raw.names_enUS or {}
    local function name(i)
        return names[i] or (raw.names_enUS and raw.names_enUS[i]) or "?"
    end
    local function items(list)
        local out = {}
        for _, it in ipairs(list or {}) do
            out[#out + 1] = { kind = it[1], name = name(it[2]), targets = points(it[4] or {}, it[3] or 2),
                rooms = it.rooms and items(it.rooms) or nil }
        end
        return out
    end
    local P = { key = raw.key, map = raw.map, zones = {}, areas = {} }
    for i, z in ipairs(raw.zones or {}) do
        P.zones[i] = { id = z[1], name = name(z[2]), ui = z[3], open = z[4] == 1, items = items(z.items), areas = {},
            map = raw.map }
    end
    for i, a in ipairs(raw.areas or {}) do
        local zone = P.zones[a[1]]
        local doors = {}
        local d = a[7] or {}
        for k = 1, #d - 3, 4 do
            doors[#doors + 1] = { x = d[k], y = d[k + 1], from = d[k + 2], road = d[k + 3] == 1 }
        end
        local area = { index = i, zone = zone, area = a[2], name = name(a[3]), overlay = a[4] == 1,
            heart = points(a[6] or {}, a[5] or 2), doors = doors, checks = points(a[8] or {}, 2), items = items(a.items) }
        P.areas[i] = area
        if zone then
            zone.areas[#zone.areas + 1] = area
        end
    end
    raw._unpacked = P
    return P
end

local function nearestPoint(list, x, y)
    local best, bestD
    for _, p in ipairs(list) do
        local d = logic.dist(p.x, p.y, x, y)
        if bestD == nil or d < bestD then
            best, bestD = p, d
        end
    end
    return best, bestD
end
logic.placesNearest = nearestPoint

local function byDistance(a, b)
    if (a.first == true) ~= (b.first == true) then
        return a.first == true
    end
    if a.distance ~= b.distance then
        return (a.distance or math.huge) < (b.distance or math.huge)
    end
    return a.label < b.label
end

local function itemNodes(list, x, y, path)
    local out = {}
    for _, it in ipairs(list or {}) do
        local p, d = nearestPoint(it.targets, x, y)
        if p then
            local node = { key = path .. "/" .. it.kind .. ":" .. it.name, label = it.name, kind = it.kind,
                x = p.x, y = p.y, ox = p.ox, oy = p.oy, distance = d }
            if it.rooms and #it.rooms > 0 then
                node.children = itemNodes(it.rooms, x, y, node.key)
                -- a room is reached through the building's doorway nearest the player: no
                -- route leads inside, a straight line from the street would cross its walls
                for _, child in ipairs(node.children) do
                    child.viaX, child.viaY = node.ox or node.x, node.oy or node.y
                end
            end
            out[#out + 1] = node
        end
    end
    table.sort(out, byDistance)
    return out
end

-- The tree of every places file on the player's continent, as the scanner's nodes (key, label,
-- x, y, children, expanded) plus ox, oy (a doorway's outside point, routed to first), kind and
-- distance. opts: x, y, map (the player's position and continent), zoneName and subzone (what the
-- game says: GetZoneText, GetSubZoneText), discovery (true: only explored subzones by name),
-- known(area) -> whether the character explored it (asked only in discovery mode, never for a
-- map shown whole), unexplored (the label of a subzone not explored yet).
function logic.placesTree(lists, opts)
    local x, y = opts.x, opts.y
    local zoneNodes = {}
    for _, P in ipairs(lists) do
        if P.map == opts.map then
            for _, zone in ipairs(P.zones) do
                local here = zone.name == opts.zoneName
                local zkey = "z:" .. tostring(zone.id)
                local children = {}
                local knownArea = {}
                local current
                for _, area in ipairs(zone.areas) do
                    local isHere = here and area.name == opts.subzone
                    if isHere then
                        current = area
                    end
                    knownArea[area.index] = isHere or not opts.discovery or zone.open or (opts.known and opts.known(area)) or false
                end
                for _, area in ipairs(zone.areas) do
                    local key = zkey .. "/a:" .. area.name
                    if knownArea[area.index] then
                        local p, d = nearestPoint(area.heart, x, y)
                        if p == nil then
                            p, d = nearestPoint(area.doors, x, y)
                        end
                        if p ~= nil or #area.items > 0 then
                            local node = { key = key, label = area.name, kind = "area", x = p and p.x, y = p and p.y,
                                ox = p and p.ox, oy = p and p.oy, distance = d, first = area == current,
                                expanded = area == current }
                            node.children = itemNodes(area.items, x, y, key)
                            if #node.children == 0 then
                                node.children = nil
                            end
                            if node.distance == nil and node.children then
                                node.distance = node.children[1].distance
                            end
                            children[#children + 1] = node
                        end
                    else
                        -- not explored: listed without its name only beside an explored subzone or
                        -- the one here (user 2026-10-16: at least the border of the neighbours),
                        -- toward the nearest crossing from it; the zone's own land between
                        -- subzones does not count
                        local usable = {}
                        for _, door in ipairs(area.doors) do
                            if door.from ~= 0 and knownArea[door.from] then
                                usable[#usable + 1] = door
                            end
                        end
                        local p, d = nearestPoint(usable, x, y)
                        if p then
                            children[#children + 1] = { key = key, label = opts.unexplored or "unexplored area",
                                kind = "unexplored", x = p.x, y = p.y, distance = d }
                        end
                    end
                end
                for _, node in ipairs(itemNodes(zone.items, x, y, zkey)) do
                    if not opts.discovery or zone.open or node.distance <= logic.IN_SIGHT then
                        children[#children + 1] = node
                    end
                end
                table.sort(children, byDistance)
                local zd
                for _, c in ipairs(children) do
                    if c.distance and (zd == nil or c.distance < zd) then
                        zd = c.distance
                    end
                end
                zoneNodes[#zoneNodes + 1] = { key = zkey, label = zone.name, kind = "zone", children = children,
                    expanded = here, first = here, distance = zd }
            end
        end
    end
    -- no zone named as the game names this one (another spelling): the nearest is the one here
    local named = false
    for _, z in ipairs(zoneNodes) do
        named = named or z.first == true
    end
    if not named then
        local best
        for _, z in ipairs(zoneNodes) do
            if z.distance and (best == nil or z.distance < best.distance) then
                best = z
            end
        end
        if best then
            best.first, best.expanded = true, true
        end
    end
    table.sort(zoneNodes, byDistance)
    return zoneNodes
end
