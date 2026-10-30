-- Surroundings logic: stops, where one waits for something that moves: a ship or zeppelin at its
-- dock or tower, a lift at its landing, the Deeprun Tram at its platform. A stop is a small area of
-- floor (grid cells) outdoors (room 0) or in a room, and where the vehicle will stand (line
-- segments); its text says what to wait for and which way the vehicle will be from where the player
-- stands: "wait for the ship to Auberdine, ship to the southwest".

local logic = WowVision.surroundingsLogic
local L = WowVision:getLocale()

-- what one waits for ("%s" the destination), without a destination, and where it will be
local WAIT_TO = {
    ship = L["wait for the ship to %s"],
    zeppelin = L["wait for the zeppelin to %s"],
    tram = L["wait for the tram to %s"],
}
local WAIT = {
    ship = L["wait for the ship"],
    zeppelin = L["wait for the zeppelin"],
    tram = L["wait for the tram"],
    ["lift up"] = L["wait for the lift up"],
    ["lift down"] = L["wait for the lift down"],
}
local WHERE = {
    ship = "ship to the %s",
    zeppelin = "zeppelin to the %s",
    tram = "tram to the %s",
    ["lift up"] = "lift to the %s",
    ["lift down"] = "lift to the %s",
}

-- The stop at a position: outdoors (`rooms` nil) one on open floor (room 0); indoors one in a room
-- of the set `rooms` (the room the player is in, or the candidates while it is unknown). `floor`
-- (optional): the floor piece held on the grid the player is in (indoors the layer's), else the
-- zone's. Returns its index and record, or nil.
function logic.stopAt(zone, x, y, rooms, floor)
    local ix = zone._index
    local r, c = logic.cellOf(zone, x, y)
    floor = floor or ix.floor or 0
    for _, i in ipairs(ix.stopCells[r * zone.cols + c] or {}) do
        local s = ix.stops[i]
        -- only on a floor piece its waiting floor lies on (the zeppelin tower's top platform was
        -- said at its foot, under it, 2026-10-06); in a room where the data lists them (the tram's
        -- platform, not the track bed 10 yd under it in the same room: STATE bug 70)
        if (rooms == nil and s.room == 0 and s.floors[floor])
                or (rooms ~= nil and rooms[s.room] and (s.anyFloor or s.floors[floor])) then
            return i, s
        end
    end
    return nil
end

-- The angles from the position toward where the vehicle of stop `i` will stand (the nearest point
-- of each of its segments), each word once.
function logic.stopDirections(zone, i, x, y)
    local item = { dirs = {} }
    for _, t in ipairs(zone._index.stops[i].targets) do
        local px, py = logic.segmentPoint(x, y, t[1], t[2], t[3], t[4])
        if logic.dist2(px, py, x, y) > 0.25 then
            logic.addDir(item, logic.bearingOf(px - x, py - y))
        end
    end
    return item.dirs
end

-- The stop whose vehicle stands nearest to the position, on any floor or room: its index and the
-- yards to the nearest point of its segments (a lift's is its shaft axis), or nil without stops.
function logic.nearestStop(zone, x, y)
    local best, bestD = nil, math.huge
    for i, s in ipairs(zone._index.stops or {}) do
        for _, t in ipairs(s.targets) do
            local _, _, d = logic.segmentPoint(x, y, t[1], t[2], t[3], t[4])
            if d < bestD then
                best, bestD = i, d
            end
        end
    end
    if best == nil then
        return nil
    end
    return best, bestD
end

-- "wait for the ship to Auberdine, ship to the southwest"; "wait for the lift down, lift to the west"
function logic.stopText(zone, i, x, y)
    local s = zone._index.stops[i]
    local text
    if s.to ~= "" and WAIT_TO[s.kind] then
        text = string.format(WAIT_TO[s.kind], s.to)
    else
        text = WAIT[s.kind] or s.kind
    end
    local words = {}
    for _, dir in ipairs(logic.stopDirections(zone, i, x, y)) do
        words[#words + 1] = logic.dirWord(zone, dir)
    end
    if #words > 0 and WHERE[s.kind] then
        text = text .. ", " .. string.format(logic.T(WHERE[s.kind]), logic.joinWords(words))
    end
    return text
end
