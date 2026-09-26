-- Surroundings (experimental, WoW: Forever): speaks the outdoor place the player enters ("forest",
-- "shore of Crystal Lake, water to the north", "bridge, running east-west") and, indoors, the
-- room ("Lion's Pride Inn, common room"). The data comes from the separate WowVision_Surroundings
-- addon (generated offline from the map files by wv-surroundings); without it the module is
-- silent. A place counts only after the player has moved some yards inside it, so walking along
-- a border does not flicker.

local T = WowVision:translate("enUS")
T["Surroundings"] = true
T["Surroundings Announcements"] = true
T["Announce Open Land"] = true
T["Announce Directions"] = true
T["Entry Distance Outdoors (yards)"] = true
T["Entry Distance Indoors (yards)"] = true
T["Entry Distance Roads and Bridges (yards)"] = true
T["Warn at Drop Edges"] = true
T["Announce Ways Out of the Water"] = true
T["edge %s, drop %d yards"] = true
T["edge %s, drop into water"] = true
T["edge %s in %d yards, drop into water"] = true
T["edge %s in %d yards, drop %d yards"] = true
T["Look Ahead for Edges (yards)"] = true
T["way out of the water, %d yards to the %s"] = true
T["road to the %s"] = true
T["Announce Entrances"] = true
T["Entrance Distance (yards)"] = true
T["entrance of %s, %d to the %s"] = true
T["at the entrance of %s"] = true
T["entrance, %d to the %s"] = true
T["at the entrance"] = true
T["Announce What Lies Around"] = true
T["Approach Distance on Squares (yards)"] = true
T["Describe Surroundings"] = true
T["%s to the %s"] = true
T["%s here"] = true
T["%s and %s"] = true
T["water"] = true
T["cliff edge"] = true
T["rock wall"] = true
T["Exits at Most"] = true
T["Announce Cliffs and Water Nearby"] = true
T["Cliffs and Water Distance (yards)"] = true
T["canal"] = true
T["way out"] = true
T["entrance of %s"] = true
T["room unknown"] = true

local logic = WowVision.surroundingsLogic
local module = WowVision.base.navigation:createModule("surroundings")
local L = module.L
module:setLabel(L["Surroundings"])

local CHECK_INTERVAL = 0.2

local settings = module:hasSettings()
settings:add({ key = "announceOpenLand", type = "Bool", label = L["Announce Open Land"], default = true })
settings:add({ key = "directions", type = "Bool", label = L["Announce Directions"], default = true })
settings:add({
    key = "entryDistance",
    type = "Number",
    label = L["Entry Distance Outdoors (yards)"],
    default = 8,
    min = 0,
    max = 40,
})
settings:add({
    key = "roadDistance",
    type = "Number",
    label = L["Entry Distance Roads and Bridges (yards)"],
    default = 3,
    min = 0,
    max = 40,
})
settings:add({ key = "dropEdges", type = "Bool", label = L["Warn at Drop Edges"], default = true })
settings:add({
    key = "edgeLookAhead",
    type = "Number",
    label = L["Look Ahead for Edges (yards)"],
    default = 10,
    min = 0,
    max = 25,
})
settings:add({ key = "entrances", type = "Bool", label = L["Announce Entrances"], default = true })
settings:add({
    key = "entranceReach",   -- was entranceDistance (15); a new key so the new default reaches saved settings
    type = "Number",
    label = L["Entrance Distance (yards)"],
    default = 10,
    min = 3,
    max = 40,
})
-- squares say their exits (streets, roads, squares) and, on coming close, water and drops;
-- rooms say their doorways; outdoor places the cliffs and water near them
settings:add({ key = "around", type = "Bool", label = L["Announce What Lies Around"], default = true })
settings:add({
    key = "aroundMax",
    type = "Number",
    label = L["Exits at Most"],
    default = 4,
    min = 1,
    max = 10,
})
settings:add({
    key = "approachDistance",
    type = "Number",
    label = L["Approach Distance on Squares (yards)"],
    default = 10,
    min = 3,
    max = 30,
})
settings:add({ key = "features", type = "Bool", label = L["Announce Cliffs and Water Nearby"], default = true })
settings:add({
    key = "featureDistance",
    type = "Number",
    label = L["Cliffs and Water Distance (yards)"],
    default = 25,
    min = 5,
    max = 60,
})
settings:add({ key = "waysOut", type = "Bool", label = L["Announce Ways Out of the Water"], default = true })
settings:add({
    key = "roomDistance",
    type = "Number",
    label = L["Entry Distance Indoors (yards)"],
    default = 3,
    min = 0,
    max = 20,
})

local alert = module:addAlert({ key = "place", label = L["Surroundings Announcements"] })
local placeTTS = alert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return message.text
    end,
})
settings:addRef("place", alert.parameters)

-- Announcements made while walking speak with game voice 0, not the player's speech voice: with
-- an NVDA SAPI voice there, the screen reader cuts its speech off at every key press (walking).
-- Same as the minimap scanner's walking announcements.
local WALK_VOICE = 0

function placeTTS:onFire(message)
    local text = message.text
    if text == nil then
        return
    end
    local speech = WowVision.base.speech
    local volume = math.max(0, math.min(100, speech.settings.speechVolume or 100))
    C_VoiceChat.SpeakText(WALK_VOICE, WowVision.ttsCacheBust.bust(text), speech.settings.speechRate, volume, false)
end

local zone = nil                 -- the zone data the player is in (unpacked)
local outdoor = logic.newEntry(8)
local indoor = logic.newEntry(3)
local wasIndoors = nil
local lastCheck = 0
local lastRoom = nil             -- the last announced room, for the interior name
local room = nil                 -- the room the player is in as far as known (switches at once)
local lastX, lastY = nil, nil    -- the previous position, for walking through doorways
local warnedEdges = {}           -- drop edges in reach and warned about (again after stepping out of reach)
local lastEdgeText, edgeAt = nil, 0  -- the last edge warning and when: a neighbouring piece of the same edge stays quiet
local saidExit = nil             -- the way out of the water last announced
local high = {}                  -- the high floor pieces (wall-walks, bridge decks) the player is on
local outAt = nil                -- when the player last came out of a building
local region = nil               -- the square the player is on (announced), for what comes close
local saidMouths = {}            -- its streets, water and the like already said on this visit

local EDGE_REACH = 3             -- yd from a drop edge where the warning comes
local MOVE_MIN = 0.3             -- yd moved in one check (0.2 s) that give a direction to look ahead
local EDGE_REARM = 0.5           -- yd beyond the reach before the same edge warns again (not on position noise)
local EXIT_REACH = 25            -- yd to a way out of the water that is announced while swimming
local ENTRANCE_AT = 3            -- yd from an entrance's centre that count as "at the entrance"
local ENTRANCE_TURN = 32          -- degrees off the last said direction before a new one is said
local ENTRANCE_REPEAT = 2        -- seconds at least between two guiding announcements
local CAME_OUT = 3               -- seconds after coming out of a building that it can lead onto a wall-walk
local EDGE_REPEAT = 1            -- second in which the same edge warning is not said again

-- Entrance guidance: within the entrance distance the nearest entrance is said with distance and
-- direction; again whenever the direction word changes (so turning toward it can be followed),
-- and once at the entrance itself. Its name only the first time: until another entrance is named,
-- "entrance, 8 yards to the west".
local guide = { index = nil, dir = nil, at = false, time = 0, named = nil }   -- named: the entrance last said by name

-- Roads, bridges and forks are narrow (about 9 to 14 yd including junctions): with the outdoor distance
-- a road crossed straight across would never be announced.
-- A road's key is its whole value (road and direction piece), so a bend is a new place like any
-- other; other places are keyed by the place alone.
local NARROW = { road = true, bridge = true, fork = true, crossing = true }
local ROADS = { road = true, fork = true, crossing = true }
local ROAD_SIDE_REACH = 12       -- yd; leaving a road says where it is within this

outdoor.distanceFor = function(key)
    if key == nil then
        return nil
    end
    if type(key) == "string" or (zone and NARROW[logic.kind(zone, key)]) then
        return module.settings.roadDistance or 3
    end
end

local function outdoorKey(z, place, value)
    if place and logic.kind(z, place) == "road" then
        return "r" .. value
    end
    return place
end

-- Log: every announcement (and every place entered but not said) with what `/wv surr` would say,
-- plus a position trail, in the data addon's SavedVariables (WowVisionSurroundingsLog), so walks
-- can be compared with the data offline after a /reload or logout.
local LOG_MAX, TRAIL_MAX, TRAIL_STEP = 3000, 20000, 4
local trailX, trailY = nil, nil
local sessionLogged = false

local function logStore()
    local log = WowVisionSurroundingsLog
    if type(log) ~= "table" then
        return nil
    end
    log.entries = log.entries or {}
    log.trail = log.trail or {}
    return log
end

local function trim(list, max)
    if #list > max + 500 then
        local keep = {}
        for i = #list - max + 1, #list do
            keep[#keep + 1] = list[i]
        end
        return keep
    end
    return list
end

local function round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

local roomCandidateNames

-- One log entry: {date, kind ("place", "room", "quiet", "session", "zone", "surr"), text} and
-- the state here.
local function logEntry(kind, text, x, y, extra)
    local log = logStore()
    if log == nil then
        return
    end
    local e = { date("%Y-%m-%d %H:%M:%S"), kind, text or "" }
    if x then
        e.x, e.y = round1(x), round1(y)
    end
    if zone and zone._rows and x then
        local value, r, c = logic.valueAt(zone, x, y)
        e.zone, e.r, e.c = zone.key, r, c
        e.cell = logic.describe(zone, value, true)
        if IsIndoors() then
            e.indoors = true
            e.candidates = roomCandidateNames(zone, x, y)
            e.room = room and logic.describeRoom(zone, room, nil) or nil
        end
    end
    if IsSwimming() then
        e.swimming = true
    end
    local facing = GetPlayerFacing()
    if facing then
        e.facing = math.floor(math.deg(facing) + 0.5)   -- degrees, 0 = north, counter-clockwise
    end
    local on = {}
    for piece in pairs(high) do
        on[#on + 1] = piece
    end
    if #on > 0 then
        table.sort(on)
        e.high = table.concat(on, " ")   -- the high floor pieces the player was on
    end
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    table.insert(log.entries, e)
    log.entries = trim(log.entries, LOG_MAX)
end

-- A trail point every few yards: "time x y", plus i (indoors), s (swimming) and g (ghost).
local function logTrail(x, y)
    if trailX and (x - trailX) ^ 2 + (y - trailY) ^ 2 < TRAIL_STEP * TRAIL_STEP then
        return
    end
    local log = logStore()
    if log == nil then
        return
    end
    trailX, trailY = x, y
    local flags = (IsIndoors() and "i" or "") .. (IsSwimming() and "s" or "") .. (UnitIsGhost("player") and "g" or "")
    table.insert(log.trail, string.format("%d %.1f %.1f%s", time(), x, y, flags ~= "" and " " .. flags or ""))
    log.trail = trim(log.trail, TRAIL_MAX)
end

local function zones()
    return WowVisionSurroundingsData and WowVisionSurroundingsData.zones or {}
end

-- The registered zone covering the position; unpack it, free the one left behind.
local function findZone(x, y, map)
    if zone and zone.map == map and logic.covers(zone, x, y) then
        return zone
    end
    local found = nil
    for _, z in ipairs(zones()) do
        if z.map == map and logic.covers(z, x, y) then
            found = z
            break
        end
    end
    if found ~= zone then
        if zone then
            logic.pack(zone)
        end
        if found then
            logic.unpack(found)
        end
        zone = found
        if found then
            logEntry("zone", found.label or found.key, x, y)
        end
        outdoor:reset()
        indoor:reset()
        lastRoom, room = nil, nil
        high = {}
        region = nil
        warnedEdges = {}
        guide.named = nil
    end
    return zone
end

local function say(text, kind, x, y, walked)
    if text and text ~= "" then
        module:fireAlert("place", { text = text })
    end
    logEntry(kind, text, x, y, { walked = walked and round1(walked) or nil })
end

-- The outdoor place key and value at a position (while swimming: the water under a bridge, or
-- the city canal under the streets).
local function outdoorValue(z, x, y)
    local value, r, c = logic.valueAt(z, x, y)
    if IsSwimming() then
        local under = logic.underBridge(z, r, c)
        if under then
            return under, under * 100
        end
    end
    if value == 0 then
        return nil, 0
    end
    return logic.placeOf(value), value
end

-- Warnings that do not wait for the entry distance: a drop edge ahead on a dock, bridge or wall
-- (on foot), and the nearest way out of city water (swimming).
local function checkEntrance(z, x, y)
    if not module.settings.entrances or IsSwimming() then
        guide.index = nil
        return
    end
    local i, d, dir = logic.nearestEntrance(z, x, y, module.settings.entranceReach or 10)
    if i == nil then
        guide.index = nil
        return
    end
    local e = logic.entrances(z)[i]
    local now = GetTime()
    -- the name only when the entrance is not the one last named
    local named = guide.named ~= i
    if d <= ENTRANCE_AT then
        if not (guide.index == i and guide.at) then
            say(named and string.format(L["at the entrance of %s"], e.text) or L["at the entrance"], "entrance", x, y)
            guide.index, guide.dir, guide.at, guide.time, guide.named = i, dir, true, now, i
        end
        return
    end
    -- a new direction only when well into it: standing near the line between north and northwest
    -- does not switch back and forth
    local turned = guide.dir ~= dir and logic.angleOff(e.x - x, e.y - y, guide.dir or dir) > ENTRANCE_TURN
    if guide.index ~= i or (turned and now - guide.time >= ENTRANCE_REPEAT) or (guide.at and d > ENTRANCE_AT + 2) then
        local yards, word = math.floor(d + 0.5), z.compass[dir]
        say(named and string.format(L["entrance of %s, %d to the %s"], e.text, yards, word)
            or string.format(L["entrance, %d to the %s"], yards, word), "entrance", x, y)
        guide.index, guide.dir, guide.at, guide.time, guide.named = i, dir, false, now, i
    end
end

-- "street of Old Town to the northwest and south, water to the east, entrance of the bank here"
local WORDS = {
    water = "water", drop = "cliff edge", canal = "canal", out = "way out",
    ["cliff edge"] = "cliff edge", ["rock wall"] = "rock wall",
}

local function joinWords(words)
    local text = words[#words]
    for i = #words - 1, 1, -1 do
        text = i == #words - 1 and string.format(L["%s and %s"], words[i], text) or words[i] .. ", " .. text
    end
    return text
end

local function itemsText(z, items)
    local parts = {}
    for _, item in ipairs(items) do
        local name = item.label
        if WORDS[item.class] then
            name = L[WORDS[item.class]]
        elseif item.class == "entrance" then
            name = string.format(L["entrance of %s"], item.label)
        end
        if #item.dirs == 0 then
            parts[#parts + 1] = string.format(L["%s here"], name)
        else
            local words = {}
            for _, dir in ipairs(item.dirs) do
                words[#words + 1] = z.compass[dir]
            end
            parts[#parts + 1] = string.format(L["%s to the %s"], name, joinWords(words))
        end
    end
    return table.concat(parts, ", ")
end

-- The label of an outdoor key's place (roads are keyed "r<value>").
local function keyLabel(z, key)
    if type(key) == "string" then
        key = logic.placeOf(tonumber(key:sub(2)) or 0)
    end
    local p = key and z.places[key]
    return p and p[2]
end

-- Stepping onto a square: its name and its exits (streets, roads, squares; nearest first, at most
-- the setting's count, the way the player came going first when there are more), so even on a
-- big square the direction to search for is known; plus water and drops already close. The
-- rest of those is said on coming close to it, as landmarks outdoors.
local function squareText(z, x, y, value, previous)
    region = logic.regionAt(z, x, y)
    saidMouths = {}
    local text = logic.describe(z, value, module.settings.directions)
    if region == nil or not module.settings.around then
        return text
    end
    local items = logic.aroundItems(region, x, y, {
        max = module.settings.aroundMax or 4,
        cameFrom = keyLabel(z, previous),
        dirs = logic.ITEM_DIRS,
        classes = { way = true },
        leading = true,
        zone = z,
    })
    for _, item in ipairs(logic.aroundItems(region, x, y, { classes = { way = true } })) do
        for _, m in ipairs(item.mouths) do
            saidMouths[m] = true   -- the exits are said on entry (or left out as the way back)
        end
    end
    local close = logic.approaching(region, x, y, module.settings.approachDistance or 10, saidMouths, logic.ITEM_DIRS)
    for _, item in ipairs(close) do
        items[#items + 1] = item
    end
    if #items > 0 then
        text = text .. ", " .. itemsText(z, items)
    end
    return text
end

-- Cliffs and water near an outdoor place, said with it: "forest, cliff edge to the west and
-- north". Not on roads (they come often), not what the place itself is or what the player just
-- left (the shore behind them).
local FEATURES = { ["cliff edge"] = "cliff edge", ["cliff foot"] = "rock wall", ["deep water"] = "water", shore = "water" }
local FEATURE_SKIP = { road = true, fork = true, crossing = true, bridge = true, ["deep water"] = true, canal = true }

local function featuresText(z, x, y, place, previous)
    local kind = logic.kind(z, place)
    if not module.settings.features or IsSwimming() or FEATURE_SKIP[kind] then
        return nil
    end
    local skip = {}
    if FEATURES[kind] then
        skip[FEATURES[kind]] = true
    end
    local before = type(previous) == "number" and FEATURES[logic.kind(z, previous)]
    if before then
        skip[before] = true
    end
    local items = logic.featuresAround(z, x, y, module.settings.featureDistance or 25, FEATURES, skip)
    if #items == 0 then
        return nil
    end
    return itemsText(z, items)
end

-- On the square: a street, water or square not said yet comes within the approach distance.
local function checkApproach(z, x, y)
    if region == nil or not module.settings.around then
        return
    end
    local here = logic.regionAt(z, x, y)
    if here and here ~= region and here.value == region.value then
        region, saidMouths = here, {}
    end
    local items = logic.approaching(region, x, y, module.settings.approachDistance or 10, saidMouths, logic.ITEM_DIRS)
    if #items > 0 then
        say(itemsText(z, items), "near", x, y)
    end
end

-- A room: its name and its doorways (at most the setting's count; with more, the one the player
-- came through goes first).
local function roomText(z, x, y, id, previous)
    local text = logic.describeRoom(z, id, previous)
    if text == nil or not module.settings.around then
        return text
    end
    local items = logic.roomDoorways(z, id, x, y, {
        max = module.settings.aroundMax or 4,
        cameFrom = previous or 0,
        dirs = logic.ITEM_DIRS,
    })
    if #items > 0 then
        text = text .. ", " .. itemsText(z, items)
    end
    return text
end

local function edgeText(z, e, ahead)
    local word = z.compass[e[2]]
    if ahead then
        local yards = math.max(1, math.floor(ahead + 0.5))
        return e[4] == 1 and string.format(L["edge %s in %d yards, drop into water"], word, yards)
            or string.format(L["edge %s in %d yards, drop %d yards"], word, yards, e[3])
    end
    return e[4] == 1 and string.format(L["edge %s, drop into water"], word)
        or string.format(L["edge %s, drop %d yards"], word, e[3])
end

local function checkEdgesAndExits(z, x, y, px, py)
    if IsSwimming() then
        -- climbing out at an edge warns again
        warnedEdges = {}
        high = {}
        if not module.settings.waysOut then
            return
        end
        local i, d, dir = logic.nearestExit(z, x, y, EXIT_REACH)
        if i and i ~= saidExit then
            say(string.format(L["way out of the water, %d yards to the %s"], math.floor(d + 0.5), z.compass[dir]),
                "exit", x, y)
        end
        saidExit = i
        return
    end
    saidExit = nil
    -- edges of a wall-walk or a deck high over the ground warn only while the player is up there
    logic.updateHigh(z, high, x, y, outAt ~= nil and GetTime() - outAt < CAME_OUT)
    -- the way the player moves (not the facing: strafing and walking back count too)
    local vx, vy = nil, nil
    local moved = px and math.sqrt((x - px) ^ 2 + (y - py) ^ 2) or 0
    if moved >= MOVE_MIN then
        vx, vy = (x - px) / moved, (y - py) / moved
    end
    local look = module.settings.edgeLookAhead or 10
    local aheadNow = {}
    if vx then
        -- every edge in the path counts as still ahead (not only the one said)
        local skip = {}
        while true do
            local i = logic.edgeAhead(z, x, y, vx, vy, look, high, skip)
            if i == nil then
                break
            end
            aheadNow[i], skip[i] = true, true
        end
    end
    -- an edge warns again after the player is out of its reach and it is no longer in the path
    for i in pairs(warnedEdges) do
        if not aheadNow[i] and logic.edgeDistance(z, i, x, y) > EDGE_REACH + EDGE_REARM then
            warnedEdges[i] = nil
        end
    end
    if not module.settings.dropEdges then
        return
    end
    -- within reach: the one ahead in the view first; else an edge in the path, with its distance
    local i = logic.nearestEdge(z, x, y, EDGE_REACH, high, GetPlayerFacing(), warnedEdges)
    local along = nil
    if i == nil and vx then
        i, along = logic.edgeAhead(z, x, y, vx, vy, look, high, warnedEdges)
    end
    if i then
        local text = edgeText(z, z.edges[i], along)
        local now = GetTime()
        if text ~= lastEdgeText or now - edgeAt >= EDGE_REPEAT then
            say(text, "edge", x, y)
            lastEdgeText, edgeAt = text, now
        end
        warnedEdges[i] = true
    end
end

module:hasUpdate(function(self)
    local now = GetTime()
    if now - lastCheck < CHECK_INTERVAL then
        return
    end
    lastCheck = now
    -- a ghost walks back to the body by the same rules; only a flight pauses the announcements
    if UnitOnTaxi("player") then
        outdoor:reset()
        indoor:reset()
        room, lastX = nil, nil
        high = {}
        return
    end
    local x, y, _z, map = UnitPosition("player")
    if x == nil then
        return
    end
    if not sessionLogged then
        sessionLogged = true
        logEntry("session", GetRealmName() .. ", " .. UnitName("player"), x, y)
    end
    local z = findZone(x, y, map)
    if z == nil then
        return
    end
    logTrail(x, y)
    outdoor.distance = self.settings.entryDistance or 8
    indoor.distance = self.settings.roomDistance or 3
    local isIndoors = IsIndoors()
    if isIndoors ~= wasIndoors then
        -- going in or out: the new side speaks its place or room at once
        outdoor:reset()
        indoor:reset()
        room = nil
        high = {}
        outAt = (wasIndoors and not isIndoors) and now or nil
        wasIndoors = isIndoors
    end
    local px, py = lastX, lastY
    lastX, lastY = x, y
    if isIndoors then
        local found = logic.resolveRoom(z, x, y, room, px, py)
        if found ~= nil then
            room = found
        end
        if indoor:update(room, x, y) then
            say(roomText(z, x, y, room, lastRoom), "room", x, y, indoor.walked)
            lastRoom = room
        end
        return
    end
    lastRoom = nil
    checkEdgesAndExits(z, x, y, px, py)
    checkEntrance(z, x, y)
    local place, value = outdoorValue(z, x, y)
    local previous = outdoor.current
    if outdoor:update(outdoorKey(z, place, value), x, y) then
        local text = logic.describe(z, value, self.settings.directions)
        region = nil
        -- stepped off a road: where the road is, to step back onto it (instead of the place's
        -- stored nearest road, which may be another one)
        local wasRoad = type(previous) == "string" or (previous and ROADS[logic.kind(z, previous)])
        if logic.isAroundPlace(z, value) then
            text = squareText(z, x, y, value, previous)
        elseif wasRoad and not ROADS[logic.kind(z, place)] then
            local d, dir = logic.nearestOfKinds(z, x, y, ROADS, ROAD_SIDE_REACH)
            if d then
                text = logic.describe(z, value, self.settings.directions, true) .. ", "
                    .. string.format(L["road to the %s"], z.compass[dir])
            end
        elseif logic.kind(z, place) == "open land" and not self.settings.announceOpenLand then
            logEntry("quiet", text, x, y, { walked = round1(outdoor.walked or 0) })
            return
        end
        if not logic.isAroundPlace(z, value) then
            local near = featuresText(z, x, y, place, previous)
            if near then
                text = text .. ", " .. near
            end
        end
        say(text, "place", x, y, outdoor.walked)
    elseif region and outdoor.current == logic.placeOf(region.value) then
        -- also from the square's edge (a step onto the street beside it does not leave it)
        checkApproach(z, x, y)
    end
end)

roomCandidateNames = function(z, x, y)
    local names = {}
    for _, id in ipairs(logic.roomCandidates(z, x, y)) do
        names[#names + 1] = logic.describeRoom(z, id, nil)
    end
    return table.concat(names, "; ")
end

-- /wv surr log [count]: the last announcements; /wv surr log clear empties the log.
local function speakLog(args)
    local log = logStore()
    if log == nil then
        WowVision:speak("No surroundings log; is the WowVision_Surroundings addon enabled?")
        return
    end
    if args == "clear" then
        log.entries, log.trail = {}, {}
        trailX, trailY = nil, nil
        WowVision:speak("Surroundings log cleared")
        return
    end
    local count = tonumber(args) or 5
    local parts = {}
    for i = math.max(1, #log.entries - count + 1), #log.entries do
        local e = log.entries[i]
        parts[#parts + 1] = e[1]:sub(12) .. " " .. e[2] .. ": " .. e[3]
    end
    for _, line in ipairs(parts) do
        print(line)
    end
    WowVision:speak(string.format("%d log entries, %d trail points. ", #log.entries, #log.trail)
        .. table.concat(parts, ". "))
end

-- /wv surr: what the module knows here, spoken and printed.
module:registerCommand({
    name = "surr",
    description = "Surroundings: speak the current place or room and the data state; log [count|clear]; around",
    func = function(args)
        local sub, rest = (args or ""):match("^(%S*)%s*(.*)$")
        if sub == "log" then
            speakLog(rest)
            return
        elseif sub == "around" then
            module:describeAround()
            return
        end
        local x, y, _z, map = UnitPosition("player")
        local parts = {}
        if #zones() == 0 then
            parts[#parts + 1] = "No surroundings data loaded; is the WowVision_Surroundings addon enabled?"
        elseif x == nil then
            parts[#parts + 1] = "No position here"
        else
            local z = findZone(x, y, map)
            parts[#parts + 1] = string.format("Position %.1f %.1f, map %s", x, y, tostring(map))
            if z == nil then
                parts[#parts + 1] = "Outside the surroundings data"
            else
                local value, r, c = logic.valueAt(z, x, y)
                parts[#parts + 1] = string.format("Data %s, cell %d %d", z.label or z.key, r, c)
                parts[#parts + 1] = "Place: " .. (logic.describe(z, value, true) or "none")
                local ei, ed, edir = logic.nearestEntrance(z, x, y, 100)
                if ei then
                    parts[#parts + 1] = string.format("Nearest entrance: %s, %d yards to the %s",
                        logic.entrances(z)[ei].text, math.floor(ed + 0.5), z.compass[edir])
                end
                if IsIndoors() then
                    local names = roomCandidateNames(z, x, y)
                    parts[#parts + 1] = "Indoors. Room candidates: " .. (names ~= "" and names or "none")
                    parts[#parts + 1] = "Current room: " .. (room and logic.describeRoom(z, room, nil) or "unknown")
                end
            end
        end
        for _, line in ipairs(parts) do
            print(line)
        end
        logEntry("surr", table.concat(parts, ". "), x, y)
        WowVision:speak(table.concat(parts, ". "))
    end,
})

-- The describe key: the place or room here and everything around it, without the count limit.
function module:describeAround()
    local x, y, _z, map = UnitPosition("player")
    local z = x and findZone(x, y, map)
    if z == nil then
        return
    end
    local text
    if IsIndoors() then
        if room == nil then
            text = L["room unknown"]
        else
            text = logic.describeRoom(z, room, nil)
            local items = logic.roomDoorways(z, room, x, y)
            if #items > 0 then
                text = text .. ", " .. itemsText(z, items)
            end
        end
    else
        local place, value = outdoorValue(z, x, y)
        text = logic.describe(z, value, true) or ""
        local here = logic.regionAt(z, x, y)
        if here then
            local items = logic.aroundItems(here, x, y)
            if #items > 0 then
                text = text .. ", " .. itemsText(z, items)
            end
        else
            local near = featuresText(z, x, y, place, nil)
            if near then
                text = text .. ", " .. near
            end
            local i, d, dir = logic.nearestEntrance(z, x, y, self.settings.entranceReach or 10)
            if i then
                text = text .. ", " .. string.format(L["entrance of %s, %d to the %s"],
                    logic.entrances(z)[i].text, math.floor(d + 0.5), z.compass[dir])
            end
        end
    end
    say(text, "around", x, y)
end

module:registerBinding({
    type = "Script",
    key = "surroundings/describe",
    label = L["Describe Surroundings"],
    inputs = { "ALT-L" },
    script = "/run WowVision.base.navigation.surroundings:describeAround()",
})
