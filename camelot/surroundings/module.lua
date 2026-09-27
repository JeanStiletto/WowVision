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
T["%s, drop %d yards"] = true
T["%s, drop into water"] = true
T["%s, drop into canal"] = true
T["%s in %d yards, drop into water"] = true
T["%s in %d yards, drop into canal"] = true
T["%s in %d yards, drop %d yards"] = true
T["Look Ahead for Edges (yards)"] = true
T["way out of the water"] = true
T["at the way out"] = true
T["%d to the %s"] = true
T["in to the %s"] = true
T["out to the %s"] = true
T["road to the %s"] = true
T["Guide to Entrances and Streets"] = true
T["Guidance Distance (yards)"] = true
T["on to the %s"] = true
T["at the %s"] = true
T["street"] = true
T["road"] = true
T["bridge"] = true
T["fork"] = true
T["crossing"] = true
T["quay"] = true
T["canal walk"] = true
T["slime canal walk"] = true
T["walk along the lava"] = true
T["at the entrance of %s"] = true
T["at the entrance"] = true
T["entrance"] = true
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
T["place unknown"] = true
T["Name What I Bump Into"] = true
T["Turn Hints on Roads and Streets"] = true
T["turn slightly left"] = true
T["turn slightly right"] = true
T["turn left"] = true
T["turn right"] = true
T["wall"] = true
T["wall of %s"] = true

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
-- guidance on foot to building entrances and to where streets begin on a square
settings:add({ key = "entrances", type = "Bool", label = L["Guide to Entrances and Streets"], default = true })
settings:add({
    key = "guideReach",   -- was entranceReach (10), entranceDistance (15): a new key so the new default reaches saved settings
    type = "Number",
    label = L["Guidance Distance (yards)"],
    default = 8,
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
settings:add({ key = "bumps", type = "Bool", label = L["Name What I Bump Into"], default = true })
-- on stepping onto a road, street or walk: which way to turn to face along it
settings:add({ key = "turnHints", type = "Bool", label = L["Turn Hints on Roads and Streets"], default = true })
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
local waterGuide = { index = nil, dir = nil, at = false, time = 0, named = nil }   -- ways out of the water, as guide
local high = {}                  -- the high floor pieces (wall-walks, bridge decks) the player is on
local outAt = nil                -- when the player last came out of a building
local region = nil               -- the square the player is on (announced), for what comes close
local saidMouths = {}            -- its streets, water and the like already said on this visit

local BUMP_TICKS = 2             -- checks in a row hard against something (0.4 s) before naming it
local BUMP_FREE = 1.0            -- seconds moving freely before the same thing is named again
local EDGE_REACH = 3             -- yd from a drop edge where the warning comes
local MOVE_MIN = 0.3             -- yd moved in one check (0.2 s) that give a direction to look ahead
local EDGE_REARM = 0.5           -- yd beyond the reach before the same edge warns again (not on position noise)
local EXIT_REACH = 25            -- yd to a way out of the water that is announced while swimming
local ENTRANCE_AT = 3            -- yd from an entrance's centre that count as "at the entrance"
local ENTRANCE_TURN = 32          -- degrees off the last said direction before a new one is said
local ENTRANCE_REPEAT = 2        -- seconds at least between two guiding announcements
local CAME_OUT = 3               -- seconds after coming out of a building that it can lead onto a wall-walk
local EDGE_REPEAT = 1            -- second in which the same edge warning is not said again

-- Guidance on foot: within the guidance distance the nearest target (a building entrance, or
-- where a street begins on a square) is said with distance and direction; again whenever the
-- direction turns (so turning toward it can be followed), and once at the target itself. Its
-- name only the first time: until another target is named, "entrance, 8 to the west".
local guide = { index = nil, dir = nil, at = false, time = 0, named = nil }   -- named: the target last said by name

-- Roads, bridges, forks and city streets are narrow (about 9 to 14 yd including junctions): with the
-- outdoor distance a road crossed straight across would never be announced.
-- A road's key is its whole value (road and direction piece), so a bend is a new place like any
-- other; other places are keyed by the place alone.
local NARROW = { road = true, bridge = true, fork = true, crossing = true, street = true }
local ROADS = { road = true, fork = true, crossing = true }
local ROAD_SIDE_REACH = 12       -- yd; leaving a road says where it is within this

-- Keys of road pieces ("r<value>"); canal pieces are keyed "c<value>".
local function isRoadKey(key)
    return type(key) == "string" and key:sub(1, 1) == "r"
end

-- A key of a way with centre lines (road, fork, crossing, city street or walk); `bridge`: bridges
-- count too (one stays on the way coming off one)
local function isWay(key, bridge)
    if isRoadKey(key) then
        return true
    end
    local kind = type(key) == "number" and zone and logic.kind(zone, key)
    return logic.LANE_KINDS[kind] or (bridge and kind == "bridge") or false
end

-- Whether a centre line decided the last outdoor value: stepping onto or off the way then counts
-- at once (the lane's enter and leave distances already keep it from flickering).
local laneDecided = false

outdoor.distanceFor = function(key)
    if key == nil then
        return nil
    end
    if laneDecided and isWay(key) ~= isWay(outdoor.current) then
        return 0
    end
    if isRoadKey(key) or (type(key) == "number" and zone and NARROW[logic.kind(zone, key)]) then
        return module.settings.roadDistance or 3
    end
end

local function outdoorKey(z, place, value)
    local kind = place and logic.kind(z, place)
    -- a canal is keyed with its direction like a road: a bend is a new place
    if kind == "canal" then
        return "c" .. value
    end
    if kind == "road" then
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

-- A trail point every few yards: "time x y", plus i (indoors), s (swimming), g (ghost) and f with
-- the facing in degrees (0 = north, counter-clockwise), as one token ("isf270").
local function logTrail(x, y)
    if trailX and (x - trailX) ^ 2 + (y - trailY) ^ 2 < TRAIL_STEP * TRAIL_STEP then
        return
    end
    local log = logStore()
    if log == nil then
        return
    end
    trailX, trailY = x, y
    local facing = GetPlayerFacing()
    local flags = (IsIndoors() and "i" or "") .. (IsSwimming() and "s" or "") .. (UnitIsGhost("player") and "g" or "")
        .. (facing and ("f" .. math.floor(math.deg(facing) + 0.5)) or "")
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
        guide.named, waterGuide.named = nil, nil
    end
    return zone
end

local function say(text, kind, x, y, walked, extra)
    if text and text ~= "" then
        module:fireAlert("place", { text = text })
    end
    extra = extra or {}
    extra.walked = walked and round1(walked) or nil
    logEntry(kind, text, x, y, extra)
end

-- The outdoor place key and value at a position (while swimming: the water under a bridge, or
-- the city canal under the streets).
local function outdoorValue(z, x, y)
    local value, r, c = logic.valueAt(z, x, y)
    if IsSwimming() then
        local under = logic.underBridge(z, r, c)
        if under then
            return logic.placeOf(under), under
        end
    end
    laneDecided = false
    if value == 0 then
        return nil, 0
    end
    -- near a centre line of a road or street the line decides whether the player is on it
    value, laneDecided = logic.laneValue(z, x, y, value, isWay(outdoor.current, true))
    return logic.placeOf(value), value
end

-- Warnings that do not wait for the entry distance: a drop edge ahead on a dock, bridge or wall
-- (on foot), and the nearest way out of city water (swimming).
-- Guidance targets. One helper says them all (building entrances, where streets begin on a
-- square, ways out of the water), so every kind follows the same rules.
-- The text for a guidance target: its name (or the short word), distance and direction, and the
-- way through it (into the building, out of the water, on along the street) when that differs
-- from the direction to it. `t`: {name, nameFormat or nameWord (else the name as it is), short,
-- at (or atText, already worded), atName, through (compass index), throughWord ("in to the %s"),
-- d, dir, x, y}.
local function guideText(z, t, named, at)
    local parts = {}
    if at then
        parts[1] = named and t.name and string.format(L[t.atName], t.name) or t.atText or L[t.at]
    else
        local name = named and t.name and (t.nameFormat and string.format(L[t.nameFormat], t.name)
            or t.nameWord and L[t.nameWord] or t.name)
        parts[1] = name or L[t.short]
        parts[2] = string.format(L["%d to the %s"], math.floor(t.d + 0.5), z.compass[t.dir])
    end
    -- the way through: on the first naming, only when it goes another way than the direction to the
    -- target ("entrance, 6 to the northeast" goes in northeast); at the target itself always
    if t.through and (at or (named and t.through ~= t.dir)) then
        parts[#parts + 1] = string.format(L[t.throughWord], z.compass[t.through])
    end
    return table.concat(parts, ", ")
end

-- Guidance to the nearest target within reach (on foot an entrance or a street's beginning, a
-- way out of the water while swimming): said with distance and direction; again when the
-- direction has turned (32 degrees off the last said one, after 2 s), and once at it. The name
-- and the way through only until another target is named: then "entrance, 6 to the north".
-- `i`: the target's key, unique among the targets of one guide.
local function guideTo(z, g, i, t, x, y, kind)
    local now = GetTime()
    local named = g.named ~= i
    if t.d <= ENTRANCE_AT then
        if not (g.index == i and g.at) then
            say(guideText(z, t, named, true), kind, x, y)
            g.index, g.dir, g.at, g.time, g.named = i, t.dir, true, now, i
        end
        return
    end
    local turned = g.dir ~= t.dir and logic.angleOff(t.x - x, t.y - y, g.dir or t.dir) > ENTRANCE_TURN
    if g.index ~= i or (turned and now - g.time >= ENTRANCE_REPEAT) or (g.at and t.d > ENTRANCE_AT + 2) then
        say(guideText(z, t, named, false), kind, x, y)
        g.index, g.dir, g.at, g.time, g.named = i, t.dir, false, now, i
    end
end

local function entranceTarget(z, x, y, reach)
    local i, d, dir = logic.nearestEntrance(z, x, y, reach)
    if i == nil then
        return nil
    end
    local e = logic.entrances(z)[i]
    return "e" .. i, {
        name = e.text, nameFormat = "entrance of %s", short = "entrance", at = "at the entrance",
        atName = "at the entrance of %s", through = e.inDir, throughWord = "in to the %s",
        d = d, dir = dir, x = e.x, y = e.y, kind = "entrance",
    }
end

-- Where a street (road, bridge, canal walk) begins on the square the player is on; streets that
-- run along the square's side are no target (see logic.wayBeginnings).
local function beginningTarget(z, x, y, reach)
    local square = logic.regionAt(z, x, y) or region
    if square == nil then
        return nil
    end
    local i, d, dir, b = logic.nearestBeginning(z, square, x, y, reach)
    if i == nil then
        return nil
    end
    return "w" .. b.label .. "@" .. math.floor(b.x) .. "," .. math.floor(b.y), {
        name = b.label, short = b.kind, atText = string.format(L["at the %s"], L[b.kind]),
        atName = "at the %s", through = b.onward, throughWord = "on to the %s",
        d = d, dir = dir, x = b.x, y = b.y, kind = "way",
    }
end

-- The guidance target on foot: the nearest entrance or street beginning within the guidance
-- distance.
local function footTarget(z, x, y)
    local reach = module.settings.guideReach or 8
    local i, t = entranceTarget(z, x, y, reach)
    local wi, wt = beginningTarget(z, x, y, reach)
    if wi and (t == nil or wt.d < t.d) then
        return wi, wt
    end
    return i, t
end

local function exitTarget(z, x, y)
    local i, d, dir, out = logic.nearestExit(z, x, y, EXIT_REACH)
    if i == nil then
        return nil
    end
    local k = (i - 1) * 4 + 1
    return i, {
        name = true, nameWord = "way out of the water", short = "way out", at = "at the way out",
        atName = "at the way out", through = out, throughWord = "out to the %s",
        d = d, dir = dir, x = z.exits[k], y = z.exits[k + 1],
    }
end

local function checkGuide(z, x, y)
    if not module.settings.entrances or IsSwimming() then
        guide.index = nil
        return
    end
    local i, t = footTarget(z, x, y)
    if i == nil then
        guide.index = nil
        return
    end
    guideTo(z, guide, i, t, x, y, t.kind)
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

-- One description of a spot, the same for the announcements and the describe key: what is said
-- depends only on where the player stands and the fixed map, never on how they got there. The
-- announcements (`cut`) may only leave things out: what was just said (the way the player came,
-- `previous`: the outdoor key before) and more than the setting's count.

-- A square's exits (streets, roads, squares that lead on; nearest first) and the water, canals
-- and cliff edges within the approach distance.
local function squareItems(z, x, y, region, cut, previous)
    local opts = { dirs = logic.ITEM_DIRS, classes = { way = true }, leading = true, zone = z }
    if cut then
        opts.max = module.settings.aroundMax or 4
        opts.cameFrom = keyLabel(z, previous)
    end
    local items = logic.aroundItems(region, x, y, opts)
    local said = {}
    for _, m in ipairs(region.mouths) do
        said[m] = m.class == "way" or nil
    end
    for _, item in ipairs(logic.approaching(region, x, y, module.settings.approachDistance or 10, said, logic.ITEM_DIRS)) do
        items[#items + 1] = item
    end
    -- the building entrances on the square; the announcements leave them to the entrance guidance
    if not cut then
        for _, item in ipairs(logic.aroundItems(region, x, y, { dirs = logic.ITEM_DIRS, classes = { entrance = true } })) do
            items[#items + 1] = item
        end
    end
    return items
end

-- Cliffs and water near an outdoor place: "forest, cliff edge to the west and north". Not on
-- roads (they come often), not what the place itself is; announcements also leave out what the
-- player just left (the shore behind them).
local TURN_WORDS = { [-2] = "turn right", [-1] = "turn slightly right", [1] = "turn slightly left", [2] = "turn left" }
local FEATURES = { ["cliff edge"] = "cliff edge", ["cliff foot"] = "rock wall", ["deep water"] = "water", shore = "water" }
local FEATURE_SKIP = { road = true, fork = true, crossing = true, bridge = true, ["deep water"] = true, canal = true }

local function featuresText(z, x, y, place, previous, cut)
    local kind = logic.kind(z, place)
    if not module.settings.features or IsSwimming() or FEATURE_SKIP[kind] then
        return nil
    end
    local skip = {}
    if FEATURES[kind] then
        skip[FEATURES[kind]] = true
    end
    local before = cut and type(previous) == "number" and FEATURES[logic.kind(z, previous)]
    if before then
        skip[before] = true
    end
    local items = logic.featuresAround(z, x, y, module.settings.featureDistance or 25, FEATURES, skip)
    if #items == 0 then
        return nil
    end
    return itemsText(z, items)
end

-- The outdoor spot: the place, its direction and nearest road; on a square its exits and what is
-- close; elsewhere where a road is (within 12 yd, off a road; announcements only on stepping off
-- one) and the cliffs and water near. Returns the text and the square's region (or nil).
local function spotText(z, x, y, place, value, previous, cut)
    local directions = module.settings.directions
    local text = logic.describe(z, value, directions)
    if text == nil then
        return nil
    end
    local kind = logic.kind(z, place)
    -- on a road, street or walk: which way to turn to face along it (nothing when already along
    -- it or facing across it)
    if module.settings.turnHints and logic.LANE_KINDS[kind] then
        local facing = GetPlayerFacing()
        local hint = facing and logic.turnHint(z, x, y, facing)
        if hint and hint ~= 0 then
            text = text .. ", " .. L[TURN_WORDS[hint]]
        end
    end
    if logic.isAroundPlace(z, value) then
        local region = logic.regionAt(z, x, y)
        if region and module.settings.around then
            local items = squareItems(z, x, y, region, cut, previous)
            if #items > 0 then
                text = text .. ", " .. itemsText(z, items)
            end
        end
        return text, region
    end
    local wasRoad = isRoadKey(previous) or (type(previous) == "number" and ROADS[logic.kind(z, previous)])
    if not ROADS[kind] and (wasRoad or not cut) then
        -- where the road is, to step back onto it (instead of the place's stored nearest road,
        -- which may be another one)
        -- toward its centre line where it has one: across the road, so it does not flicker
        local d, dir
        local ld, _i, lx, ly = logic.nearestLane(z, x, y, ROAD_SIDE_REACH, ROADS)
        if ld then
            d, dir = ld, logic.compassIndex(lx - x, ly - y)
        else
            d, dir = logic.nearestOfKinds(z, x, y, ROADS, ROAD_SIDE_REACH)
        end
        if d then
            text = logic.describe(z, value, directions, true) .. ", " .. string.format(L["road to the %s"], z.compass[dir])
        end
    end
    local near = featuresText(z, x, y, place, previous, cut)
    if near then
        text = text .. ", " .. near
    end
    return text, nil
end

-- A room: its name (with the building's when it changes) and its doorways, each with the fixed
-- direction one passes through it leaving the room; announcements at most the setting's count,
-- the doorway the player came through left out first.
local function roomText(z, id, previous, cut)
    local text = logic.describeRoom(z, id, previous)
    if text == nil or not module.settings.around then
        return text
    end
    local opts = { dirs = logic.ITEM_DIRS }
    if cut then
        opts.max = module.settings.aroundMax or 4
        opts.cameFrom = previous or 0
    end
    local items = logic.roomDoorways(z, id, opts)
    if #items > 0 then
        text = text .. ", " .. itemsText(z, items)
    end
    return text
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

-- Naming what the player bumps into: when they push against something (the wall detection's
-- "blocked", held for a moment), the object in the way they push (a barrel, a cart, a fence), or
-- the wall of the building ahead ("wall of auction house"), or indoors a wall. Once per bump; the
-- same thing again only after moving freely for a moment.
local bump = { ticks = 0, key = nil, free = 0, time = nil }

local function pushDirection()
    local facing = GetPlayerFacing()
    local flags = WowVision.movement and WowVision.movement.flags
    if facing == nil or flags == nil then
        return nil
    end
    local ahead = ((flags.moveForward or flags.autorun) and 1 or 0) - (flags.moveBackward and 1 or 0)
    local side = (flags.strafeLeft and 1 or 0) - (flags.strafeRight and 1 or 0)
    local vx = ahead * math.cos(facing) + side * math.cos(facing + math.pi / 2)
    local vy = ahead * math.sin(facing) + side * math.sin(facing + math.pi / 2)
    local len = math.sqrt(vx * vx + vy * vy)
    if len < 0.1 then
        return nil
    end
    return vx / len, vy / len
end

local function checkBump(z, x, y, px, py, isIndoors)
    local now = GetTime()
    local dt = bump.time and now - bump.time or nil
    bump.time = now
    if not module.settings.bumps or px == nil or dt == nil or IsSwimming() then
        bump.ticks = 0
        return
    end
    local moved = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
    local speed = GetUnitSpeed("player")
    if WowVision.isSecret and WowVision.isSecret(speed) then
        speed = nil
    end
    local translating = WowVision.movement and WowVision.movement:isTranslating()
    local severity = translating and WowVision.stuckMath.severity(moved, speed, dt) or nil
    if severity ~= 1 then
        bump.ticks = 0
        if moved > 0.2 then
            bump.free = bump.free + dt
            if bump.free >= BUMP_FREE then
                bump.key = nil
            end
        end
        return
    end
    bump.ticks = bump.ticks + 1
    bump.free = 0
    if bump.ticks < BUMP_TICKS then
        return
    end
    local vx, vy = pushDirection()
    if vx == nil then
        return
    end
    local i = logic.objectAhead(z, x, y, vx, vy, logic.BUMP_REACH, isIndoors and room or 0)
    local text, key
    if i then
        text, key = logic.objectName(z, i), i
    elseif isIndoors then
        text, key = L["wall"], "wall"
    else
        local owner = logic.wallOwner(z, x, y, vx, vy, 2.5)
        if owner then
            text, key = string.format(L["wall of %s"], owner), owner
        end
    end
    if text and key ~= bump.key then
        -- the movement keys held (f forward, b back, l and r strafe, a autorun): with the facing in
        -- the entry, the way the player pushed
        local flags = WowVision.movement.flags
        local keys = (flags.moveForward and "f" or "") .. (flags.moveBackward and "b" or "")
            .. (flags.strafeLeft and "l" or "") .. (flags.strafeRight and "r" or "") .. (flags.autorun and "a" or "")
        say(text, "bump", x, y, nil, { keys = keys })
    end
    bump.key = key or bump.key
end

-- The direction first, then the drop ("southeast, drop into canal"): the drop already says it is
-- an edge.
local function edgeText(z, e, ahead)
    local word = z.compass[e[2]]
    -- e[4]: 1 into water, 2 into a city canal, 0 a plain drop
    if ahead then
        local yards = math.max(1, math.floor(ahead + 0.5))
        if e[4] == 2 then
            return string.format(L["%s in %d yards, drop into canal"], word, yards)
        end
        return e[4] == 1 and string.format(L["%s in %d yards, drop into water"], word, yards)
            or string.format(L["%s in %d yards, drop %d yards"], word, yards, e[3])
    end
    if e[4] == 2 then
        return string.format(L["%s, drop into canal"], word)
    end
    return e[4] == 1 and string.format(L["%s, drop into water"], word)
        or string.format(L["%s, drop %d yards"], word, e[3])
end

local function checkEdgesAndExits(z, x, y, px, py)
    if IsSwimming() then
        -- climbing out at an edge warns again
        warnedEdges = {}
        high = {}
        if not module.settings.waysOut then
            return
        end
        local i, t = exitTarget(z, x, y)
        if i then
            guideTo(z, waterGuide, i, t, x, y, "exit")
        else
            waterGuide.index = nil
        end
        return
    end
    waterGuide.index = nil
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
    checkBump(z, x, y, px, py, isIndoors)
    if isIndoors then
        local found = logic.resolveRoom(z, x, y, room, px, py)
        if found ~= nil then
            room = found
        end
        if indoor:update(room, x, y) then
            say(roomText(z, room, lastRoom, true), "room", x, y, indoor.walked)
            lastRoom = room
        end
        return
    end
    lastRoom = nil
    checkEdgesAndExits(z, x, y, px, py)
    checkGuide(z, x, y)
    local place, value = outdoorValue(z, x, y)
    local previous = outdoor.current
    if outdoor:update(outdoorKey(z, place, value), x, y) then
        local text, square = spotText(z, x, y, place, value, previous, true)
        region = nil
        if square then
            -- on the square: what was said now (its exits, what is close) is not said again on
            -- coming close
            region, saidMouths = square, {}
            for _, m in ipairs(square.mouths) do
                saidMouths[m] = m.class == "way" or nil
            end
            logic.approaching(square, x, y, self.settings.approachDistance or 10, saidMouths)
        elseif logic.kind(z, place) == "open land" and not self.settings.announceOpenLand then
            logEntry("quiet", text, x, y, { walked = round1(outdoor.walked or 0) })
            return
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

-- The describe key: the place or room here as the announcements describe it, without their cuts.
function module:describeAround()
    local x, y, _z, map = UnitPosition("player")
    local z = x and findZone(x, y, map)
    if z == nil then
        return
    end
    -- the same description the announcements give here, without their cuts; plus the entrance
    -- guidance
    local text
    if IsIndoors() then
        text = room and roomText(z, room, nil, false) or L["room unknown"]
    else
        local place, value = outdoorValue(z, x, y)
        -- a spot the data has no place for (a gap in the map) says so, as a room does
        text = spotText(z, x, y, place, value, nil, false) or L["place unknown"]
        local i, t
        if IsSwimming() then
            i, t = exitTarget(z, x, y)
        elseif self.settings.entrances then
            i, t = footTarget(z, x, y)
        end
        if i then
            text = text .. ", " .. guideText(z, t, true, t.d <= ENTRANCE_AT)
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
