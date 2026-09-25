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
T["edge to the %s, drop %d yards"] = true
T["edge to the %s, drop into water"] = true
T["way out of the water, %d yards to the %s"] = true
T["road to the %s"] = true
T["Announce Entrances"] = true
T["Entrance Distance (yards)"] = true
T["entrance of %s, %d yards to the %s"] = true
T["at the entrance of %s"] = true

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
settings:add({ key = "entrances", type = "Bool", label = L["Announce Entrances"], default = true })
settings:add({
    key = "entranceDistance",
    type = "Number",
    label = L["Entrance Distance (yards)"],
    default = 15,
    min = 3,
    max = 40,
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
local warnedEdge = nil           -- the drop edge last warned about (again only after leaving it)
local saidExit = nil             -- the way out of the water last announced

local EDGE_REACH = 3             -- yd from a drop edge where the warning comes
local EDGE_CLEAR = 6             -- yd away from every edge before the same edge warns again
local EXIT_REACH = 25            -- yd to a way out of the water that is announced while swimming
local ENTRANCE_AT = 3            -- yd from an entrance's centre that count as "at the entrance"
local ENTRANCE_REPEAT = 2        -- seconds at least between two guiding announcements

-- Entrance guidance: within the entrance distance the nearest entrance is said with distance and
-- direction; again whenever the direction word changes (so turning toward it can be followed),
-- and once at the entrance itself.
local guide = { index = nil, dir = nil, at = false, time = 0 }

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
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    table.insert(log.entries, e)
    log.entries = trim(log.entries, LOG_MAX)
end

-- A trail point every few yards: "time x y", plus i (indoors) and s (swimming).
local function logTrail(x, y)
    if trailX and (x - trailX) ^ 2 + (y - trailY) ^ 2 < TRAIL_STEP * TRAIL_STEP then
        return
    end
    local log = logStore()
    if log == nil then
        return
    end
    trailX, trailY = x, y
    local flags = (IsIndoors() and "i" or "") .. (IsSwimming() and "s" or "")
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
    local i, d, dir = logic.nearestEntrance(z, x, y, module.settings.entranceDistance or 15)
    if i == nil then
        guide.index = nil
        return
    end
    local e = logic.entrances(z)[i]
    local now = GetTime()
    if d <= ENTRANCE_AT then
        if not (guide.index == i and guide.at) then
            say(string.format(L["at the entrance of %s"], e.text), "entrance", x, y)
            guide.index, guide.dir, guide.at, guide.time = i, dir, true, now
        end
        return
    end
    if guide.index ~= i or (guide.dir ~= dir and now - guide.time >= ENTRANCE_REPEAT) or (guide.at and d > ENTRANCE_AT + 2) then
        say(string.format(L["entrance of %s, %d yards to the %s"], e.text, math.floor(d + 0.5), z.compass[dir]),
            "entrance", x, y)
        guide.index, guide.dir, guide.at, guide.time = i, dir, false, now
    end
end

local function checkEdgesAndExits(z, x, y)
    if IsSwimming() then
        warnedEdge = nil
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
    if not module.settings.dropEdges then
        return
    end
    local i = logic.nearestEdge(z, x, y, EDGE_REACH)
    if i then
        if i ~= warnedEdge then
            local e = z.edges[i]
            local word = z.compass[e[2]]
            local text = e[4] == 1 and string.format(L["edge to the %s, drop into water"], word)
                or string.format(L["edge to the %s, drop %d yards"], word, e[3])
            say(text, "edge", x, y)
            warnedEdge = i
        end
    elseif warnedEdge and not logic.nearestEdge(z, x, y, EDGE_CLEAR) then
        warnedEdge = nil
    end
end

module:hasUpdate(function(self)
    local now = GetTime()
    if now - lastCheck < CHECK_INTERVAL then
        return
    end
    lastCheck = now
    if UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then
        outdoor:reset()
        indoor:reset()
        room, lastX = nil, nil
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
            say(logic.describeRoom(z, room, lastRoom), "room", x, y, indoor.walked)
            lastRoom = room
        end
        return
    end
    lastRoom = nil
    checkEdgesAndExits(z, x, y)
    checkEntrance(z, x, y)
    local place, value = outdoorValue(z, x, y)
    local previous = outdoor.current
    if outdoor:update(outdoorKey(z, place, value), x, y) then
        local text = logic.describe(z, value, self.settings.directions)
        -- stepped off a road: where the road is, to step back onto it
        local wasRoad = type(previous) == "string" or (previous and ROADS[logic.kind(z, previous)])
        if wasRoad and not ROADS[logic.kind(z, place)] then
            local d, dir = logic.nearestOfKinds(z, x, y, ROADS, ROAD_SIDE_REACH)
            if d then
                text = text .. ", " .. string.format(L["road to the %s"], z.compass[dir])
            end
        elseif logic.kind(z, place) == "open land" and not self.settings.announceOpenLand then
            logEntry("quiet", text, x, y, { walked = round1(outdoor.walked or 0) })
            return
        end
        say(text, "place", x, y, outdoor.walked)
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
    description = "Surroundings: speak the current place or room and the data state; log [count|clear]",
    func = function(args)
        local sub, rest = (args or ""):match("^(%S*)%s*(.*)$")
        if sub == "log" then
            speakLog(rest)
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
