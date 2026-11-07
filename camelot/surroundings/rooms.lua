-- Surroundings logic: rooms, found indoors without a height. Room floors are boxes in their
-- building's own frame; where floors stack, the room is the one the player walked into through a
-- doorway. Doorways to outside are the building entrances.

local logic = WowVision.surroundingsLogic
local L = WowVision:getLocale()

-- The building frames, the room floors under a position, the room outlines and the doorway crossing are the bump
-- layer's (core/navigation/bumpLogic.lua, which names what the player bumps into from data cut out of these zones):
-- the rooms and buildings here carry the same fields (a room's interior, boxes, outline; a building's ox, oy,
-- scale, m00 to m11; a doorway's a, b, interior, x, y, nx, ny, side, half). One set of rules for both.
local bumpLogic = WowVision.bumpLogic

-- A world position in a building's frame {ox, oy, scale, m00, m01, m10, m11}: world x = ox - scale * (m00 vx +
-- m01 vy), world y = oy - scale * (m10 vx + m11 vy). Room boxes are stored in that frame, so they stay exact for
-- rotated buildings. toWorld is its inverse.
logic.toBuilding = bumpLogic.toBuilding
logic.toWorld = bumpLogic.toWorld
logic.DOOR_REACH = bumpLogic.DOOR_REACH -- yards from a doorway's plane (or centre) within which a crossing counts

logic.DOOR_HOLD = 4.0 -- yards from a doorway of the room entered through it within which that room holds (resolveRoom)

-- Did the player walk through a doorway of the current room between the previous position and
-- this one? A door {a, b (rooms, 0 = outside), interior, x, y (centre), nx, ny (its plane's
-- normal), side (the side of room a, 0 = a flat opening)}, in the building frame. Returns the room
-- behind it (0 = outside) or nil. `fits` (optional): a doorway into a room with fits(room) false
-- is passed over (a doorway has no height: the Trade Quarter's doorway into its shop lies 0.8 yd
-- from the canal tunnel's 17 yd below it, one step crossed both and the tunnel's came first, walk
-- 2026-10-13 16:59).
local ANY = function()
    return true
end
function logic.crossedDoor(zone, current, px, py, x, y, fits)
    return bumpLogic.crossedDoor(zone, current, px, py, x, y, fits or ANY)
end

-- The first room whose outline (the box of its walls) holds the position, or nil: where the floor
-- boxes leave gaps (under counters, a raised platform).
logic.roomOutlineAt = bumpLogic.roomOutlineAt

-- The rooms whose floor boxes contain the position (within `margin` yards). `rooms` (optional): a
-- list of room ids to look at instead of all.
function logic.roomCandidates(zone, x, y, margin, rooms)
    return bumpLogic.roomsAt(zone, x, y, margin or 0.5, nil, rooms)
end

-- Is the room's floor (within `margin`) under the position?
local function roomHolds(zone, id, x, y, margin)
    return #logic.roomCandidates(zone, x, y, margin, { id }) > 0
end

-- Does the room fit what the game says: a hall it calls outdoors (the room has a hallMap) while
-- IsIndoors() is false, any other room while it is true? `indoors` nil: everything fits.
local function gameFits(zone, id, indoors)
    if indoors == nil then
        return true
    end
    return (zone._index.rooms[id].hallMap ~= nil) ~= indoors
end

-- The room candidates that fit what the game says (gameFits), or all of them when none does (the
-- game's word only decides between floors on top of each other; it never empties the list). In
-- Ironforge the Great Forge's floor lies over the throne room's stairs and the cavern below: the
-- game calls the forge outdoors and the rest indoors (user's walks 2026-10-02).
function logic.fittingRooms(zone, cands, indoors)
    if indoors == nil then
        return cands
    end
    local out = {}
    for _, id in ipairs(cands) do
        if gameFits(zone, id, indoors) then
            out[#out + 1] = id
        end
    end
    return #out > 0 and out or cands
end

logic.ROOM_SLACK = 2.0 -- yd; where no floor lies right under the player, a floor this close counts


-- Do two rooms of one building differ only by their number ("tram tunnel 6", "tram tunnel 7")?
-- Then walking from one into the other says nothing (user 2026-09-29: only when the name really
-- changes).
function logic.sameRoomName(zone, a, b)
    local rooms = zone._index.rooms
    local ra, rb = rooms[a], rooms[b]
    if ra == nil or rb == nil or ra.interior ~= rb.interior then
        return false
    end
    return ra.name:gsub("%s+%d+$", "") == rb.name:gsub("%s+%d+$", "")
end

-- The room at a position: walking through a doorway of the current room leads into the room
-- behind it; otherwise the only candidate; or, where floors stack, the current room if it is a
-- candidate, else the one candidate joined to the current room by a door; else nil (unknown,
-- better quiet than wrong). Where no floor lies under the player, the floors within ROOM_SLACK are
-- the candidates (user 2026-09-29: riding the tram over its pit, the tunnel floor runs 1.4 yd to the
-- side of the car; leaving the station into the tunnel's area is enough). px, py: the previous
-- position (optional). byDoor: the current room was entered through one of its doorways; it then
-- holds as long as its floor is within ROOM_SLACK or one of its doorways within DOOR_HOLD, even
-- where only another room's floor lies right under the player (Northshire Abbey 2026-10-01: on
-- the stairs the gallery's floor box over them was the only one found a step after the door, so
-- the stairs were lost and the bell tower's door, a door of the stairs, was never checked; the
-- stairs' floor begins 3 yd behind their door). crossed (optional): the result of crossedDoor for
-- this step, when the caller has it already (false: none crossed). indoors (optional): IsIndoors();
-- the candidates are those that fit it (fittingRooms), and a current room that does not fit while
-- one here does is left, held by its door or not.
-- The candidate rooms one can be in, coming from `current`: rooms change as floors do, through a
-- doorway or onto floor one is on. A hall stays a candidate only as the current room, one joined to
-- it by a doorway, or a hall lying on the zone's floor piece here (hallOnFloor, the test that lets
-- the player into the halls; the game's area as last looked, zone._index.gameArea). The rooms of
-- the Undercity under the Ruins of Lordaeron hold the same x and y as the throne room and the
-- bell towers 110 yd over them and join them nowhere (walks 2026-10-07: canal names beside the
-- bell tower, "room unknown" at a login in the throne room).
function logic.onFloorRooms(zone, x, y, cands, current)
    local ix = zone._index
    local r0, c0 = logic.cellOf(zone, x, y)
    local nb = current and ix.neighbours[current] or nil
    local out = {}
    for _, id in ipairs(cands) do
        if not ix.rooms[id].hallMap or id == current or (nb and nb[id])
            or logic.hallOnFloor(zone, id, r0, c0, ix.floor or 0, false, ix.gameArea) then
            out[#out + 1] = id
        end
    end
    return out
end

-- The rooms whose floor the player stands on (user 2026-10-12: the room under the player is found
-- by the floor, not by the room boxes, which have no height: under the Undercity Trade Quarter's
-- shops their boxes held the canal hall 18 yd below): in indoor layer `layer` the rooms of the
-- floor piece the player is on (logic.updateFloor) in this cell, else in the 8 cells around; nil
-- where the layer does not say (older data, or no room's floor of that piece here). The second
-- value is true where the rooms come from the cells around on the ground, which holds floors at
-- any height (roomsAt takes them only from the room the player is in or one joined to it).
function logic.floorRoomsAt(layer, x, y)
    local fr = layer and layer._index and layer._index.floorRooms
    if fr == nil then
        return nil
    end
    local floor = layer._index.floor or 0
    local r0, c0 = logic.cellOf(layer, x, y)
    local here = fr[r0 * layer.cols + c0]
    if here and here[floor] then
        return here[floor], false
    end
    local seen, out = {}, {}
    for dr = -1, 1 do
        for dc = -1, 1 do
            local cell = (dr ~= 0 or dc ~= 0) and c0 + dc >= 0 and c0 + dc < layer.cols and fr[(r0 + dr) * layer.cols + c0 + dc]
            for _, id in ipairs(cell and cell[floor] or {}) do
                if not seen[id] then
                    seen[id] = true
                    out[#out + 1] = id
                end
            end
        end
    end
    if #out == 0 then
        return nil
    end
    return out, floor == 0
end

-- Does room `id` have floor here (this cell or the 8 around) on the floor piece the player is on in
-- `layer`? (Not a piece joined to it: the ground holds floors at several heights, and swimming
-- under the Trade Quarter's shops the canal's water, joined to the ground, let the Inn's doorway
-- overhead be walked through.) nil where the layer knows no floor of that room (older data, a room
-- of no city: a house's, a mapped building's).
function logic.roomFloorNear(layer, id, x, y)
    local fr = layer and layer._index and layer._index.floorRooms
    if fr == nil or not layer._index.floorRoomIds[id] then
        return nil
    end
    local floor = layer._index.floor or 0
    local r0, c0 = logic.cellOf(layer, x, y)
    for dr = -1, 1 do
        for dc = -1, 1 do
            local cell = c0 + dc >= 0 and c0 + dc < layer.cols and fr[(r0 + dr) * layer.cols + c0 + dc]
            for _, r in ipairs(cell and cell[floor] or {}) do
                if r == id then
                    return true
                end
            end
        end
    end
    return false
end

-- The floor piece of `layer` that room `id` lies on here, where it does not lie on the player's:
-- coming into the halls by a hall's floor the player is on that room's floor (the floor follows
-- the room the evidence gives; at the Ruins of Lordaeron's entrance the halls layer's floor was
-- still the ground, which holds the canal 110 yd below in the same cells, and the floor named the
-- canal). Looked for in this cell, else in the cells around: the piece most of those cells list
-- the room on (the fewer number where as many), nil to keep the floor where that is the player's
-- piece (a scrap of the room's floor on the ground beside it, the ground's canal under it, kept
-- the wrong floor); nil where the data does not know the room.
function logic.roomPieceHere(layer, id, x, y)
    local ix = layer and layer._index
    if id == nil or ix == nil or ix.floorRooms == nil or not ix.floorRoomIds[id] then
        return nil
    end
    local floor = ix.floor or 0
    local r0, c0 = logic.cellOf(layer, x, y)
    for ring = 0, 1 do
        local count, best = {}, nil
        for dr = -ring, ring do
            for dc = -ring, ring do
                local cell = math.max(math.abs(dr), math.abs(dc)) == ring and c0 + dc >= 0 and c0 + dc < layer.cols
                    and ix.floorRooms[(r0 + dr) * layer.cols + c0 + dc]
                for p, list in pairs(cell or {}) do
                    for _, r in ipairs(list) do
                        if r == id then
                            count[p] = (count[p] or 0) + 1
                            if best == nil or count[p] > count[best] or (count[p] == count[best] and p < best) then
                                best = p
                            end
                        end
                    end
                end
            end
        end
        if best ~= nil then
            if best == floor or (ring == 0 and count[floor]) then
                return nil
            end
            return best
        end
    end
    return nil
end

-- The room candidates here: the rooms of the floor the player is on in the layer the game's word
-- picks (floorRoomsAt; the floor is the evidence, so no hall test), else the rooms whose boxes
-- hold the position within `margin` that fit the game's word and the way the player came
-- (fittingRooms, onFloorRooms).
function logic.roomsAt(zone, x, y, margin, indoors, current)
    local byFloor, aside = logic.floorRoomsAt(logic.layer(zone, indoors), x, y)
    if byFloor and aside and current ~= nil then
        -- (from the cells around on the ground: only the room the player is in or one joined to it
        -- by a doorway; the Ruins of Lordaeron's passage 120 yd over the Trade Quarter's island was
        -- said there, walk 2026-10-12 11:02:48)
        local nb = zone._index.neighbours[current] or {}
        local kept = {}
        for _, id in ipairs(byFloor) do
            if id == current or nb[id] then
                kept[#kept + 1] = id
            end
        end
        byFloor = #kept > 0 and kept or nil
    end
    if byFloor then
        return logic.fittingRooms(zone, byFloor, indoors)
    end
    return logic.onFloorRooms(zone, x, y, logic.fittingRooms(zone, logic.roomCandidates(zone, x, y, margin), indoors), current)
end

function logic.resolveRoom(zone, x, y, current, px, py, byDoor, crossed, indoors)
    if crossed == nil then
        crossed = logic.crossedDoor(zone, current, px, py, x, y)
    end
    if crossed then
        return crossed ~= 0 and crossed or nil
    end
    local cands = logic.roomsAt(zone, x, y, nil, indoors, current)
    if current ~= nil and not gameFits(zone, current, indoors) and #cands > 0 and gameFits(zone, cands[1], indoors) then
        current, byDoor = nil, false
    end
    if byDoor and current ~= nil then
        if roomHolds(zone, current, x, y, logic.ROOM_SLACK) then
            return current
        end
        for _, door in ipairs(zone._index.doorsOf[current] or {}) do
            local dx, dy = logic.doorWorld(zone, door)
            if dx and logic.dist2(dx, dy, x, y) <= logic.DOOR_HOLD ^ 2 then
                return current
            end
        end
    end
    if #cands == 0 then
        cands = logic.roomsAt(zone, x, y, logic.ROOM_SLACK, indoors, current)
    end
    if #cands == 0 then
        return nil
    end
    if #cands == 1 then
        return cands[1]
    end
    if current == nil then
        return nil
    end
    local joined = nil
    local neighbours = zone._index.neighbours[current] or {}
    for _, id in ipairs(cands) do
        if id == current then
            return current
        end
        if neighbours[id] then
            if joined ~= nil then
                return nil
            end
            joined = id
        end
    end
    return joined
end

-- The middle of a room's floor boxes (building frame), area weighted.
local function roomMiddle(room)
    local b = room.boxes
    local sx, sy, n = 0, 0, 0
    for i = 1, #b - 3, 4 do
        local a = math.max((b[i + 2] - b[i]) * (b[i + 3] - b[i + 1]), 0.01)
        sx, sy, n = sx + (b[i] + b[i + 2]) / 2 * a, sy + (b[i + 1] + b[i + 3]) / 2 * a, n + a
    end
    if n == 0 then
        return nil
    end
    return sx / n, sy / n
end

-- The direction of a doorway seen from a room: the way one passes through it leaving the room
-- (its plane's normal, away from the room's side), an angle. Fixed per room and doorway,
-- like the map: the auction house's way out is to the east from anywhere in the hall. Without a
-- usable plane (a flat opening), the way from the room's middle to the doorway.
function logic.doorwayDirection(zone, door, roomId)
    local ix = zone._index
    local interior = ix.interiors[door.interior]
    if interior == nil then
        return nil
    end
    local vx, vy
    if door.side ~= 0 and (door.nx ~= 0 or door.ny ~= 0) then
        -- room a lies on the door's side, room b on the other one
        local side = roomId == door.a and door.side or -door.side
        vx, vy = -side * door.nx, -side * door.ny
    else
        local room = ix.rooms[roomId]
        local mx, my = nil, nil
        if room then
            mx, my = roomMiddle(room)
        end
        if mx == nil then
            return nil
        end
        vx, vy = door.x - mx, door.y - my
        if vx * vx + vy * vy < 0.01 then
            return nil
        end
    end
    local ax, ay = logic.toWorld(interior, door.x, door.y)
    local bx, by = logic.toWorld(interior, door.x + vx, door.y + vy)
    return logic.bearingOf(bx - ax, by - ay)
end

logic.ENTRANCE_MERGE = 4 -- yd; doorways of one building closer than this are one entrance

-- Adds an entrance to the list unless one of the same text lies within ENTRANCE_MERGE of it (then
-- its doorway's floor joins that one's floors; an unknown floor makes them unknown). `floor`: the
-- floor piece the doorway's sill lies on, or nil.
local function addEntrance(list, entrance, floor)
    for _, e in ipairs(list) do
        if e.text == entrance.text and logic.dist2(e.x, e.y, entrance.x, entrance.y) < logic.ENTRANCE_MERGE ^ 2 then
            if e.floors and floor ~= nil then
                e.floors[floor] = true
            else
                e.floors = nil
            end
            return
        end
    end
    entrance.floors = floor ~= nil and { [floor] = true } or nil
    list[#list + 1] = entrance
end

-- The entrances of the indoor layer: the doorways from a room it covers into a room it does not
-- (a shop, a passage, stairs) or outside. Each as an entrance (see logic.entrances): a room with a
-- name of its own (a shop, the bank) is "entrance of" it; another room is said by its name alone
-- (plain: "passage of Ironforge"), outside as the way out; inDir: the way through it, leaving the
-- hall. Doorways of one text closer than ENTRANCE_MERGE are one.
local function layerEntrances(layer)
    local ix = layer._index
    local covered = ix.covered
    local list = {}
    for _, door in ipairs(ix.doors) do
        local aIn, bIn = covered[door.a] or false, covered[door.b] or false
        local interior = ix.interiors[door.interior]
        if aIn ~= bIn and interior and not door.unsaid then
            local hall = aIn and door.a or door.b
            local beyond = aIn and door.b or door.a
            local room = ix.rooms[beyond]
            local text, plain, wayOut
            if beyond == 0 then
                text, plain, wayOut = L["way outside"], true, true
            elseif room then
                text = logic.describeRoom(layer, beyond, hall)
                plain = not room.named
            end
            if text then
                local x, y = logic.toWorld(interior, door.x, door.y)
                addEntrance(list, {
                    x = x, y = y, text = text, building = text, plain = plain, wayOut = wayOut,
                    inDir = logic.doorwayDirection(layer, door, hall),
                }, door.floor)
            end
        end
    end
    return list
end

-- The entrances: the doorways between outside and a room, in world yards, built once per zone.
-- Each {x, y, text, building, inDir}: the building, and the room behind unless it is just the
-- entrance; inDir: the angle one goes in toward (the room's way out, reversed). In the
-- indoor layer: the doorways out of its halls (layerEntrances).
function logic.entrances(zone)
    local ix = zone._index
    if ix.entrances then
        return ix.entrances
    end
    if ix.covered then
        ix.entrances = layerEntrances(zone)
        return ix.entrances
    end
    local list = {}
    for _, door in ipairs(ix.doors) do
        local inside = door.a == 0 and door.b or door.b == 0 and door.a or nil
        local room = inside and ix.rooms[inside]
        local interior = ix.interiors[door.interior]
        if room and interior and not door.unsaid then
            local x, y = logic.toWorld(interior, door.x, door.y)
            local text = interior.name
            if not room.entrance and room.name ~= interior.name then
                text = text .. ", " .. logic.spokenName(zone, room.name)
            end
            local out = logic.doorwayDirection(zone, door, inside)
            addEntrance(list, { x = x, y = y, text = text, building = interior.name, inDir = out and (out + 180) % 360 }, door.floor)
        end
    end
    ix.entrances = list
    return list
end

-- Is the player at (x, y) on an entrance's floor: the floor piece they are on is one its doorways'
-- sills lie on, or one joined to such (a doorstep, a shop's landing up a few steps; true where the
-- data does not say)?
function logic.onEntranceFloor(zone, e, x, y)
    if e.floors == nil then
        return true
    end
    local floor = zone._index.floor or 0
    if e.floors[floor] then
        return true
    end
    for f in pairs(e.floors) do
        if logic.joinedPieces(zone, floor, f) then
            return true
        end
    end
    return false
end

-- The nearest entrance within `reach` yards: index, distance, the angle toward it, the entrance.
-- `onFloor`: only one on the player's floor (onEntranceFloor; the guidance: the Trade Quarter's
-- shops up on the ring were guided to from the canal hall 17 yd under them, walk 2026-10-11 23:47).
function logic.nearestEntrance(zone, x, y, reach, prefer, onFloor)
    local opts = onFloor and { skip = function(e)
        return not logic.onEntranceFloor(zone, e, x, y)
    end } or nil
    return logic.nearestPoint(logic.entrances(zone), x, y, reach, prefer, opts)
end

-- The text of a room: the interior's name when it changes, then the room; a city complex's district
-- only when it is not the one of `previousRoomId` (the room one comes from, or for a doorway the
-- room one stands in; user 2026-10-07, the Undercity's "canal, Trade Quarter 4" said from inside
-- the Trade Quarter); likewise a way between two places from one of them says only the other
-- ("passage to War Quarter" in the canal, not "passage between War Quarter and canal").
function logic.describeRoom(zone, roomId, previousRoomId)
    local ix = zone._index
    local room = ix.rooms[roomId]
    if room == nil then
        return nil
    end
    local previous = previousRoomId and ix.rooms[previousRoomId]
    local interior = ix.interiors[room.interior]
    -- a named floor is said once, as the building is: not again from a room on it (logic.floorOf);
    -- a numbered name without its number (logic.spokenName): a list of doorways then says the
    -- rooms of one word once, with their directions ("mine to the east and west")
    local name = logic.spokenName(zone, room.name)
    if previous and previous.interior == room.interior then
        if room.short and room.district == previous.district then
            name = room.short
        elseif previous.place and previous.place == room.wayA then
            name = room.atA
        elseif previous.place and previous.place == room.wayB then
            name = room.atB
        else
            name = logic.floorLabel(zone, name, (logic.floorOf(zone, previous.name)))
        end
    end
    -- a city's own complex (Ironforge) is named after the zone the player knows: never said
    local city = interior ~= nil and interior.city
    if not city and (previous == nil or previous.interior ~= room.interior) then
        return (interior and interior.name or "") .. ", " .. name
    end
    return name
end

logic.BIG_ROOM = 800 -- sq yd; in a room this big its doorways are said from where the player stands

-- The doorways between a room called `nameA` and one called `nameB` in one house (the rooms'
-- bare names, which the indoor layer's places of them are labelled with): the doors, and whether
-- the two names are rooms of one house at all (then no door between them means a wall). Two
-- pieces of one thing (one name) are no two rooms; a city's own complex (Ironforge, the Undercity)
-- is none either: its halls meet without doorway records (the Hall of Explorers and the Forlorn
-- Cavern), so the grid says what lies beside them.
function logic.doorsBetween(zone, nameA, nameB)
    local ix = zone._index
    local doors = {}
    if nameA == nameB then
        return doors, false
    end
    local byInterior, bothRooms = {}, false
    for _, room in pairs(ix.rooms) do
        local interior = ix.interiors[room.interior]
        if (room.name == nameA or room.name == nameB) and interior and not interior.city then
            local names = byInterior[room.interior] or {}
            byInterior[room.interior] = names
            names[room.name] = true
            bothRooms = bothRooms or (names[nameA] and names[nameB]) or false
        end
    end
    if not bothRooms then
        return doors, false
    end
    for _, door in ipairs(ix.doors) do
        local a, b = ix.rooms[door.a], ix.rooms[door.b]
        if a and b and ((a.name == nameA and b.name == nameB) or (a.name == nameB and b.name == nameA)) then
            doors[#doors + 1] = door
        end
    end
    return doors, true
end

-- Is the room big (BIG_ROOM)? There its doorways are said and guided to from the player's position.
function logic.isBigRoom(zone, roomId)
    local room = zone._index.rooms[roomId]
    return room ~= nil and room.floor >= logic.BIG_ROOM
end

-- A doorway's centre in world yards.
function logic.doorWorld(zone, door)
    local interior = zone._index.interiors[door.interior]
    if interior == nil then
        return nil
    end
    return logic.toWorld(interior, door.x, door.y)
end

-- The doorways of a room as items {label, class ("room" or "way out"), dirs}: the room behind each
-- (or the way out) with the fixed direction of its doorways (doorwayDirection); the way out first,
-- then the other rooms in the data's order, so a room always says the same. In a big room
-- (isBigRoom), given the player's position (opts.x, opts.y), instead the direction from the player
-- to each doorway (none closer than HERE), nearest first (user 2026-09-29: "exit northeast" said the
-- side of a 90 yd hall). opts (optional): max (items), dirs (directions per item); cameFrom: the
-- room the player came from (a room id, 0 = outside), left out first when there are more than max;
-- section: leave out the doorways back to cameFrom (sectionText). Doorways into a room of the
-- very same name (another piece of one staircase) are never said.
function logic.roomDoorways(zone, roomId, opts)
    opts = opts or {}
    local ix = zone._index
    if ix.rooms[roomId] == nil then
        return {}
    end
    local fromPlayer = opts.x ~= nil and logic.isBigRoom(zone, roomId)
    local doors = ix.doorsOf[roomId] or {}
    local ordered = {}
    if fromPlayer then
        local dist = {}
        for _, door in ipairs(doors) do
            local dx, dy = logic.doorWorld(zone, door)
            if dx then
                dist[door] = logic.dist(dx, dy, opts.x, opts.y)
                ordered[#ordered + 1] = door
            end
        end
        table.sort(ordered, function(a, b)
            return dist[a] < dist[b]
        end)
    else
        for _, outside in ipairs({ true, false }) do
            for _, door in ipairs(doors) do
                if (door.a == 0 or door.b == 0) == outside then
                    ordered[#ordered + 1] = door
                end
            end
        end
    end
    local items, byLabel, cameLabel = {}, {}, nil
    local name = ix.rooms[roomId].name
    for _, door in ipairs(ordered) do
        local other = door.a == roomId and door.b or door.a
        local label, class = "way out", "way out"
        -- a doorway into another room said alike (a piece of this one: one name, or one word
        -- numbered) is no doorway the player tells apart: a small room says through it, in its
        -- direction, the room's own doorway it leads to (doorVia; a lift hall cut in three said
        -- "Halle" with no way out, 45 s at its end wall, walk 2026-10-15 11:20); big rooms say
        -- their doorways from the player
        local via = nil
        if other ~= 0 and not fromPlayer and not (opts.section and other == opts.cameFrom)
                and logic.sameRoomName(zone, roomId, other) then
            local viaId
            if door.a == roomId then
                viaId = door.viaA
            else
                viaId = door.viaB
            end
            via = viaId and ix.doors[viaId]
        end
        if via then
            label = nil
            local piece = logic.sameRoomName(zone, roomId, via.a) and via.a or via.b
            local beyond = via.a == piece and via.b or via.a
            if beyond == 0 then
                label, class = "way out", "way out"
            elseif ix.rooms[beyond] and not logic.sameRoomName(zone, roomId, beyond) then
                label, class = logic.describeRoom(zone, beyond, piece), "room"
            end
        elseif other ~= 0 and (ix.rooms[other].name == name or (opts.section and other == opts.cameFrom)) then
            -- not into another piece of the same thing (one staircase, one of Ironforge's hall ways:
            -- the data names its pieces alike), nor back on a section's announcement (sectionText)
            label = nil
        elseif other ~= 0 then
            -- (a numbered piece with no doorway out beyond it: a mine's passage on, said as one)
            label, class = logic.describeRoom(zone, other, roomId), "room"
        end
        if label then
            if other == opts.cameFrom then
                cameLabel = label
            end
            local item = byLabel[label]
            if item == nil then
                -- through: said only through rooms said alike (sectionText: a single way on
                -- through the same thing is no choice)
                item = { label = label, class = class, dirs = {}, through = via ~= nil }
                byLabel[label] = item
                items[#items + 1] = item
            elseif not via then
                item.through = false
            end
            local dir
            if fromPlayer then
                local dx, dy = logic.doorWorld(zone, door)
                if logic.dist2(dx, dy, opts.x, opts.y) >= logic.HERE ^ 2 then
                    dir = logic.bearingOf(dx - opts.x, dy - opts.y)
                end
            else
                dir = logic.doorwayDirection(zone, door, roomId)
            end
            logic.addDir(item, dir, opts.dirs)
        end
    end
    return logic.capItems(items, opts.max, cameLabel)
end

-- The nearest doorway of a big room (isBigRoom) within `reach` yards of the player: distance, the
-- door, its world x and y, the room behind it (0 = outside); or nil. `skip` (optional): a door
-- left out.
-- `prefer` {x, y}: the doorway guided to last stays the target unless another is nearer by more
-- than GUIDE_STICK (Ironforge's Great Forge, 2026-10-01: seven doorway lines in 30 s).
-- `anySize`: any room, not only a big one (the building helper: Alt-I in a house's room leads to its doorway
-- by the same rule as in a hall, the user 2026-10-29).
function logic.nearestDoorway(zone, roomId, x, y, reach, skip, prefer, anySize)
    if not anySize and not logic.isBigRoom(zone, roomId) then
        return nil
    end
    local ix = zone._index
    -- the room's doorways in world yards, once
    ix.doorPoints = ix.doorPoints or {}
    local points = ix.doorPoints[roomId]
    if points == nil then
        points = {}
        local name = ix.rooms[roomId].name
        for _, door in ipairs(ix.doorsOf[roomId] or {}) do
            local dx, dy = logic.doorWorld(zone, door)
            local other = ix.rooms[door.a == roomId and door.b or door.a]
            -- not into another piece of the same thing, as roomDoorways (the Undercity's canal
            -- pieces, 2026-10-07: the seam between two was guided to and swung behind the player),
            -- nor into a niche (the Ruins' throne room guided into one of its alcoves, a dead end)
            if dx and not (other and (other.name == name or other.niche)) then
                points[#points + 1] = { x = dx, y = dy, door = door }
            end
        end
        ix.doorPoints[roomId] = points
    end
    local opts = skip and { skip = function(p) return p.door == skip end } or nil
    local _i, d, _dir, p = logic.nearestPoint(points, x, y, reach, prefer, opts)
    if p == nil then
        return nil
    end
    return d, p.door, p.x, p.y, p.door.a == roomId and p.door.b or p.door.a
end

-- Halls the game calls outdoors (IsIndoors() false, one may mount there): Ironforge's big halls,
-- almost all of the Undercity. Their rooms carry the UI map one stands on in them (hallMap).
-- Is `uiMap` (C_Map.GetBestMapForUnit) the map of such a hall in this zone?
function logic.isHallMap(zone, uiMap)
    local ix = zone._index
    if ix.hallMaps == nil then
        ix.hallMaps, ix.hallRooms = {}, {}
        for id, room in ipairs(ix.rooms) do
            if room.hallMap then
                ix.hallMaps[room.hallMap] = true
                ix.hallRooms[#ix.hallRooms + 1] = id
            end
        end
    end
    return uiMap ~= nil and ix.hallMaps[uiMap] == true
end

-- Is a hall's floor here (within ROOM_SLACK) while the game's map is the hall's? Only that the
-- hall lies here in x and y: the game gives no height, and its map does not tell the floors
-- apart everywhere (in Ironforge's halls Ironforge's and on the mountain over them Dun Morogh's,
-- but on the Ruins of Lordaeron's rose walk the Undercity's, as in the city 110 yd under it, walk
-- 2026-10-07). Whether the player is in it is inHallFloor's.
-- With `current` (the room the player is in) only the halls they can be in coming from it count
-- (logic.onFloorRooms: it, a room joined to it by a doorway, a hall on the zone's floor piece
-- here): out of the Ruins of Lordaeron's sewer, whose mouth onto the courtyard is no doorway, the
-- Undercity's canals under the courtyard kept the player in the halls (walk 2026-10-07 23:43).
function logic.inHall(zone, x, y, uiMap, current)
    if not logic.isHallMap(zone, uiMap) then
        return false
    end
    local ix = zone._index
    local here = {}
    for _, id in ipairs(ix.hallRooms) do
        if ix.rooms[id].hallMap == uiMap and roomHolds(zone, id, x, y, logic.ROOM_SLACK) then
            if current == nil then
                return true
            end
            here[#here + 1] = id
        end
    end
    return #logic.onFloorRooms(zone, x, y, here, current) > 0
end

-- Is the player in a hall here (user 2026-10-07): a hall whose floor is here (inHall) lying on
-- the zone's floor piece the player is on (`zoneFloor`, edges.lua updateFloor: the walk-graph
-- tracker). Where the halls lie under other floor (the
-- Undercity under the Ruins of Lordaeron, 110 yd down) their floor here in x and y is not enough:
-- the rose walk's floor piece is none the canal under it lies on. The ground holds every floor
-- that lies under nothing, at any height, so on the ground a hall counts only in the cells where
-- its floor is the ground (zone.hallGround, or a cell next to one): the Ruins' courtyard is ground
-- over the Magic Quarter's canal, the throne room's floor is ground and hall. A hall whose pieces
-- are not known (none matched, an older export) counts only with `staying` (the caller's: just
-- after the game's map became the halls', the game's own way in at Ironforge's gate). On the
-- ground a hall also needs the game's area (`area`, its subzone text) not to name another place
-- than the hall's own: the Magic Quarter's floor counted as ground under the Ruins' courtyard canal
-- walk, where the game said "Ruins of Lordaeron" (walk 2026-10-07 23:46).
function logic.hallGroundNear(zone, r, c)
    local hg = zone._index.hallGround
    local key = r * zone.cols + c
    for _, d in ipairs(logic.cellOffsets(zone, r, c)) do
        if hg[key + d] then
            return true
        end
    end
    return false
end

-- Does hall room `id` lie on the zone's floor piece `floor` in the cell (r0, c0), as the game's
-- area `area` allows (the test of inHallFloor for one room)?
function logic.hallOnFloor(zone, id, r0, c0, floor, staying, area)
    local r = zone._index.rooms[id]
    local pieces = r.zonePieces
    if pieces == nil then
        return staying and true or false
    end
    local known = area ~= nil and area ~= ""
    return (pieces[floor] and (floor ~= 0 or (logic.hallGroundNear(zone, r0, c0)
        and not (known and r.subzone and r.subzone ~= area)))) and true or false
end

-- Returns true and the hall room whose floor is here and lies on the zone's floor piece (the
-- room the player comes into the halls by), else false.
function logic.inHallFloor(zone, x, y, uiMap, zoneFloor, staying, area)
    if not logic.isHallMap(zone, uiMap) then
        return false
    end
    local ix = zone._index
    local r0, c0 = logic.cellOf(zone, x, y)
    for _, id in ipairs(ix.hallRooms) do
        local r = ix.rooms[id]
        if r.hallMap == uiMap and roomHolds(zone, id, x, y, logic.ROOM_SLACK)
            and logic.hallOnFloor(zone, id, r0, c0, zoneFloor or 0, staying, area) then
            return true, id
        end
    end
    return false
end

-- Are two halls apart: no doorway between them and no floor piece in common (both known)? A
-- step from one into the other is none: the player went out (the right bell tower of the Ruins,
-- left by its doorway unnoticed, and the Undercity's canal 110 yd under the rose walk beside it).
function logic.hallsApart(zone, a, b)
    local ix = zone._index
    local ra, rb = ix.rooms[a], ix.rooms[b]
    if not (ra and rb and ra.hallMap and rb.hallMap and ra.zonePieces and rb.zonePieces) then
        return false
    end
    if ix.neighbours[a] and ix.neighbours[a][b] then
        return false
    end
    for p in pairs(ra.zonePieces) do
        if rb.zonePieces[p] then
            return false
        end
    end
    return true
end

-- Where the game makes it certain the player is in a hall here (its subzone is the area of a hall
-- whose floor is here) but their floor piece is none it lies on (after a login, or a lift's ride,
-- which the floor pieces cannot follow): the zone's floor piece of that hall present in this cell,
-- when exactly one is; else nil. Only ever into a hall, never out of one (stairs where the area
-- changes halfway would flicker).
function logic.hallPieceForArea(zone, x, y, uiMap, area, zoneFloor)
    if area == nil or area == "" or not logic.isHallMap(zone, uiMap) then
        return nil
    end
    local ix = zone._index
    local r0, c0 = logic.cellOf(zone, x, y)
    local key = r0 * zone.cols + c0
    local found = nil
    for _, id in ipairs(ix.hallRooms) do
        local r = ix.rooms[id]
        if r.hallMap == uiMap and r.subzone == area and r.zonePieces and roomHolds(zone, id, x, y, logic.ROOM_SLACK) then
            if r.zonePieces[zoneFloor or 0] then
                return nil   -- already on it
            end
            for p in pairs(r.zonePieces) do
                if logic.floorHere(zone, key, p) then
                    if found ~= nil and found ~= p then
                        return nil
                    end
                    found = p
                end
            end
        end
    end
    return found
end

-- Is the player in the indoor layer: in a room it covers, or, where the room is unknown (stacked
-- floors), where the layer has a place and every room candidate is covered?
function logic.inLayer(layer, roomId, x, y)
    local covered = layer._index.covered
    if roomId ~= nil then
        return covered[roomId] or false
    end
    if logic.valueAt(layer, x, y) == 0 then
        return false
    end
    local cands = logic.floorRoomsAt(layer, x, y) or logic.roomCandidates(layer, x, y)
    if #cands == 0 then
        return false
    end
    for _, id in ipairs(cands) do
        if not covered[id] then
            return false
        end
    end
    return true
end
