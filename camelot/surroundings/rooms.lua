-- Surroundings logic: rooms, found indoors without a height. Room floors are boxes in their
-- building's own frame; where floors stack, the room is the one the player walked into through a
-- doorway. Doorways to outside are the building entrances.

local logic = WowVision.surroundingsLogic
local L = WowVision:getLocale()

-- A world position in a building's frame {ox, oy, scale, m00, m01, m10, m11}: world x = ox -
-- scale * (m00 vx + m01 vy), world y = oy - scale * (m10 vx + m11 vy). Room boxes are stored in
-- that frame, so they stay exact for rotated buildings.
function logic.toBuilding(frame, x, y)
    local a, b, c, d = frame.m00, frame.m01, frame.m10, frame.m11
    local r0, r1 = (frame.ox - x) / frame.scale, (frame.oy - y) / frame.scale
    local det = a * d - b * c
    return (d * r0 - b * r1) / det, (-c * r0 + a * r1) / det
end

-- A building-frame position in world yards (the inverse of toBuilding).
function logic.toWorld(frame, vx, vy)
    return frame.ox - frame.scale * (frame.m00 * vx + frame.m01 * vy), frame.oy - frame.scale * (frame.m10 * vx + frame.m11 * vy)
end

logic.DOOR_REACH = 3.0 -- yards from a doorway's centre within which a crossing counts

-- Did the player walk through a doorway of the current room between the previous position and
-- this one? A door {a, b (rooms, 0 = outside), interior, x, y (centre), nx, ny (its plane's
-- normal), side (the side of room a, 0 = a flat opening)}, in the building frame. Returns the room
-- behind it (0 = outside) or nil.
function logic.crossedDoor(zone, current, px, py, x, y)
    if current == nil or px == nil then
        return nil
    end
    local ix = zone._index
    for _, door in ipairs(ix.doorsOf[current] or {}) do
        if door.side ~= 0 and (door.nx ~= 0 or door.ny ~= 0) then
            local interior = ix.interiors[door.interior]
            local ax, ay = logic.toBuilding(interior, px, py)
            local bx, by = logic.toBuilding(interior, x, y)
            local near = function(u, v)
                return (u - door.x) ^ 2 + (v - door.y) ^ 2 <= logic.DOOR_REACH * logic.DOOR_REACH
            end
            if near(ax, ay) or near(bx, by) then
                local mine = current == door.a and door.side or -door.side
                local before = ((ax - door.x) * door.nx + (ay - door.y) * door.ny) * mine
                local after = ((bx - door.x) * door.nx + (by - door.y) * door.ny) * mine
                if before > 0 and after < 0 then
                    return current == door.a and door.b or door.a
                end
            end
        end
    end
    return nil
end

-- The first room whose outline (the box of its walls) holds the position, or nil: where the floor
-- boxes leave gaps (under counters, a raised platform).
function logic.roomOutlineAt(zone, x, y)
    local ix = zone._index
    for id, room in ipairs(ix.rooms) do
        local o = room.outline
        if o then
            local vx, vy = logic.toBuilding(ix.interiors[room.interior], x, y)
            if vx >= o[1] and vx <= o[3] and vy >= o[2] and vy <= o[4] then
                return id
            end
        end
    end
    return nil
end

-- The rooms whose floor boxes contain the position (within `margin` yards).
function logic.roomCandidates(zone, x, y, margin)
    margin = margin or 0.5
    local ix = zone._index
    local found, inFrame = {}, {}
    for id, room in ipairs(ix.rooms) do
        local pos = inFrame[room.interior]
        if pos == nil then
            pos = { logic.toBuilding(ix.interiors[room.interior], x, y) }
            inFrame[room.interior] = pos
        end
        local vx, vy = pos[1], pos[2]
        local b = room.boxes
        for i = 1, #b - 3, 4 do
            if vx >= b[i] - margin and vx <= b[i + 2] + margin and vy >= b[i + 1] - margin and vy <= b[i + 3] + margin then
                found[#found + 1] = id
                break
            end
        end
    end
    return found
end

-- The room at a position: walking through a doorway of the current room leads into the room
-- behind it; otherwise the only candidate; or, where floors stack, the current room if it is a
-- candidate, else the one candidate joined to the current room by a door; else nil (unknown,
-- better quiet than wrong). px, py: the previous position (optional).
function logic.resolveRoom(zone, x, y, current, px, py)
    local crossed = logic.crossedDoor(zone, current, px, py, x, y)
    if crossed ~= nil then
        return crossed ~= 0 and crossed or nil
    end
    local cands = logic.roomCandidates(zone, x, y)
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
-- (its plane's normal, away from the room's side), a compass index. Fixed per room and doorway,
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
    return logic.compassIndex(bx - ax, by - ay)
end

logic.ENTRANCE_MERGE = 4 -- yd; doorways of one building closer than this are one entrance

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
        if aIn ~= bIn and interior then
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
                local merged = false
                for _, e in ipairs(list) do
                    if e.text == text and (e.x - x) ^ 2 + (e.y - y) ^ 2 < logic.ENTRANCE_MERGE ^ 2 then
                        merged = true
                        break
                    end
                end
                if not merged then
                    list[#list + 1] = {
                        x = x, y = y, text = text, building = text, plain = plain, wayOut = wayOut,
                        inDir = logic.doorwayDirection(layer, door, hall),
                    }
                end
            end
        end
    end
    return list
end

-- The entrances: the doorways between outside and a room, in world yards, built once per zone.
-- Each {x, y, text, building, inDir}: the building, and the room behind unless it is just the
-- entrance; inDir: the compass index one goes in toward (the room's way out, reversed). In the
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
        if room and interior then
            local x, y = logic.toWorld(interior, door.x, door.y)
            local text = interior.name
            if not room.entrance and room.name ~= interior.name then
                text = text .. ", " .. room.name
            end
            local merged = false
            for _, e in ipairs(list) do
                if e.text == text and (e.x - x) ^ 2 + (e.y - y) ^ 2 < logic.ENTRANCE_MERGE ^ 2 then
                    merged = true
                    break
                end
            end
            if not merged then
                local out = logic.doorwayDirection(zone, door, inside)
                list[#list + 1] = { x = x, y = y, text = text, building = interior.name, inDir = out and (out + 3) % 8 + 1 }
            end
        end
    end
    ix.entrances = list
    return list
end

-- The nearest entrance within `reach` yards: index, distance, compass index toward it, the entrance.
function logic.nearestEntrance(zone, x, y, reach)
    return logic.nearestPoint(logic.entrances(zone), x, y, reach)
end

-- The text of a room: the interior's name when it changes, then the room.
function logic.describeRoom(zone, roomId, previousRoomId)
    local ix = zone._index
    local room = ix.rooms[roomId]
    if room == nil then
        return nil
    end
    local previous = previousRoomId and ix.rooms[previousRoomId]
    if previous == nil or previous.interior ~= room.interior then
        local interior = ix.interiors[room.interior]
        return (interior and interior.name or "") .. ", " .. room.name
    end
    return room.name
end

logic.BIG_ROOM = 800 -- sq yd; in a room this big its doorways are said from where the player stands

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
-- room the player came from (a room id, 0 = outside), left out first when there are more than max.
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
                dist[door] = math.sqrt((dx - opts.x) ^ 2 + (dy - opts.y) ^ 2)
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
    for _, door in ipairs(ordered) do
        local other = door.a == roomId and door.b or door.a
        local label, class = "way out", "way out"
        if other ~= 0 then
            label, class = logic.describeRoom(zone, other, roomId), "room"
        end
        if label then
            if other == opts.cameFrom then
                cameLabel = label
            end
            local item = byLabel[label]
            if item == nil then
                item = { label = label, class = class, dirs = {} }
                byLabel[label] = item
                items[#items + 1] = item
            end
            local dir
            if fromPlayer then
                local dx, dy = logic.doorWorld(zone, door)
                if (dx - opts.x) ^ 2 + (dy - opts.y) ^ 2 >= logic.HERE ^ 2 then
                    dir = logic.compassIndex(dx - opts.x, dy - opts.y)
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
function logic.nearestDoorway(zone, roomId, x, y, reach, skip)
    if not logic.isBigRoom(zone, roomId) then
        return nil
    end
    local best, bestDoor, bx, by = reach, nil, nil, nil
    for _, door in ipairs(zone._index.doorsOf[roomId] or {}) do
        local dx, dy = logic.doorWorld(zone, door)
        if dx and door ~= skip then
            local d = math.sqrt((dx - x) ^ 2 + (dy - y) ^ 2)
            if d <= best then
                best, bestDoor, bx, by = d, door, dx, dy
            end
        end
    end
    if bestDoor == nil then
        return nil
    end
    return best, bestDoor, bx, by, bestDoor.a == roomId and bestDoor.b or bestDoor.a
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
    local cands = logic.roomCandidates(layer, x, y)
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
