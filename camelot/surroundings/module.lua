-- Surroundings (WoW: Forever): describes where the player walks, from the WowVision_Surroundings
-- data addon (without it the module is silent). Outdoors the place entered ("forest", "shore of
-- Crystal Lake, water to the north", "road, north to south"), on a square its ways on, indoors
-- the room and its doorways; drop edges, guidance to entrances, street beginnings and ways out
-- of the water, turn hints on roads, and what the player bumps into. The logic and the texts are
-- in the other files of this folder (docs/src/developer/surroundings.md).

local logic = WowVision.surroundingsLogic
local module = WowVision.base.navigation:createModule("surroundings")
local L = module.L
module:setLabel(L["Surroundings"])

local settings = module:hasSettings()
settings:add({ key = "dropEdges", type = "Bool", label = L["Warn at Drop Edges"], default = true })
-- guidance on foot to building entrances and to where streets begin on a square, and while
-- swimming to the ways out of the water
settings:add({ key = "guidance", type = "Bool", label = L["Guide to Entrances, Streets and Ways Out"], default = true })
-- on stepping onto a road, street or walk: which way to turn to face along it; at gentle bends
settings:add({ key = "turnHints", type = "Bool", label = L["Turn Hints on Roads and Streets"], default = true })
-- while a beacon leads the way: entrances and street beginnings only by name, no turn hints
settings:add({ key = "beaconQuiet", type = "Bool", label = L["Quieter While a Beacon Guides"], default = true })
settings:add({ key = "bumps", type = "Bool", label = L["Name What I Bump Into"], default = true })

-- Announcements made while walking speak with game voice 0, not the player's speech voice: with
-- an NVDA SAPI voice there, the screen reader cuts its speech off at every key press.
local alert = module:addAlert({ key = "place", label = L["Surroundings Announcements"] })
alert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    voice = 0,
    buildMessage = function(self, message)
        return message.text
    end,
})
settings:addRef("place", alert.parameters)

local CHECK_INTERVAL = 0.2 -- seconds between two looks at the position
-- Distances in yards, times in seconds
local ENTRY_OUTDOORS = 8 -- walked inside an outdoor place before it counts
local ENTRY_NARROW = 3 -- ... inside a road, bridge, fork, crossing or city street
local ENTRY_INDOORS = 3 -- ... inside a room
local EDGE_REACH = 3 -- a drop edge this close is warned about
local EDGE_REARM = 0.5 -- beyond the reach before the same edge warns again (not on position noise)
local EDGE_LOOK = 10 -- drop edges in the path are warned about this far ahead
local EDGE_REPEAT = 1 -- the same edge warning is not said again within this
local MOVE_MIN = 0.3 -- moved in one look that gives a direction to look ahead along
local CAME_OUT = 3 -- after coming out of a building it can lead onto a wall-walk this long
local GUIDE_TURN = 32 -- degrees off the last said direction before a new one is said
local GUIDE_REPEAT = 2 -- at least between two guiding announcements
local GUIDE_AWAY = 2 -- beyond "at" a target before it is guided to again
local BUMP_TICKS = 2 -- looks in a row hard against something (0.4 s) before naming it
local BUMP_FRESH = 0.5 -- the wall detection's grading counts this long (it stops while disabled)
local BUMP_FREE = 1.0 -- moving freely before the same thing is named again
local BUMP_MOVING = 0.2 -- moved in one look that counts as moving freely
local WALL_REACH = 2.5 -- a building's wall is looked for this far ahead
local BEND_LOOK = 10 -- where a road leads is taken this far ahead
local BEND_THRESHOLD = 15 -- degrees a road turns before a gentle bend is said

-- What the module knows about where the player is
local zone = nil -- the zone data the player is in (unpacked)
local outdoor = logic.newEntry(ENTRY_OUTDOORS)
local indoor = logic.newEntry(ENTRY_INDOORS)
local laneDecided = false -- a centre line decided the last outdoor value (see distanceFor)
local wasIndoors = nil -- indoors at the last look (nil before the first)
local lastCheck = 0
local lastX, lastY = nil, nil -- the previous position, for walking through doorways
local room = nil -- the room the player is in as far as known (switches at once)
local lastRoom = nil -- the last announced room, for the interior name
local high = {} -- the high floor pieces (wall-walks, bridge decks) the player is on
local outAt = nil -- when the player last came out of a building
local warnedEdges = {} -- drop edges warned about (again after stepping out of reach)
local lastEdgeText, edgeAt = nil, 0 -- the last edge warning and when: a neighbouring piece of the same edge stays quiet
local region = nil -- the square the player is on (announced), for what comes close
local saidMouths = {} -- its streets, water and the like already said on this visit
local bendFrom = nil -- where the road led at the last message (radians), nil: take it anew
local aheadKey = nil -- the next piece of a city street, said before reaching it (not again on it)
local aheadX, aheadY = nil, nil -- where it was said: walking far from there forgets it
-- Guidance: the target last said, the direction said, whether it was "at" it, when, and the
-- target last said by name
local guide = { key = nil, dir = nil, at = false, time = 0, named = nil } -- on foot
local waterGuide = { key = nil, dir = nil, at = false, time = 0, named = nil } -- ways out of the water
local bump = { ticks = 0, key = nil, free = 0, time = nil }

-- Forget where the player was: after a flight, in a new zone, on going in or out of a building.
-- The place or room there is then said at once.
local function forgetPlace()
    outdoor:reset()
    indoor:reset()
    room, lastRoom = nil, nil
    high, warnedEdges = {}, {}
    region, saidMouths = nil, {}
    bendFrom, aheadKey = nil, nil
end

-- A way with centre lines (road, fork, crossing, city street or walk); with `bridge` also a bridge
-- (one stays on the way coming off one).
local function isWay(key, bridge)
    local kind = logic.kind(zone, logic.keyPlace(key))
    return logic.LANE_KINDS[kind] or (bridge and kind == "bridge") or false
end

outdoor.distanceFor = function(key)
    if key == nil then
        return nil
    end
    -- out of the water onto land only after a few yards on it: bobbing at a canal's edge switched
    -- "street" and "canal" every half second (Stormwind 2026-09-29); falling in is said at once
    local here = logic.kind(zone, logic.keyPlace(outdoor.current))
    local there = logic.kind(zone, logic.keyPlace(key))
    if (here == "canal" or logic.WATER[here]) and not (there == "canal" or logic.WATER[there]) then
        return ENTRY_NARROW
    end
    -- stepping onto or off a way counts at once where its centre line decided (the line's enter
    -- and leave distances already keep it from flickering)
    if laneDecided and isWay(key) ~= isWay(outdoor.current) then
        return 0
    end
    -- from one road or street piece onto the next (a new direction): at once, so the bend is heard
    -- before walking straight on carries the player off the way
    if logic.isWayKey(key) and logic.isWayKey(outdoor.current) then
        return 0
    end
    if logic.NARROW[logic.kind(zone, logic.keyPlace(key))] then
        return ENTRY_NARROW
    end
end

-- The walk log (/wv surr log on): every announcement with what `/wv surr` would say there, plus a
-- position trail, kept in WowVisionDump.surroundings, so walks can be compared with the data
-- offline after a /reload or logout (the walklog tools of wv-surroundings). Off until switched
-- on, then on until switched off.
local LOG_MAX, TRAIL_MAX, TRAIL_STEP = 3000, 20000, 4
local trailX, trailY = nil, nil
local sessionLogged = false

local function logStore()
    WowVisionDump = WowVisionDump or {}
    if type(WowVisionDump.surroundings) ~= "table" then
        WowVisionDump.surroundings = { entries = {}, trail = {} }
    end
    return WowVisionDump.surroundings
end

-- The log while it is switched on, else nil.
local function activeLog()
    local log = WowVisionDump and WowVisionDump.surroundings
    return type(log) == "table" and log.on and log or nil
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

local function facingDegrees()
    local facing = GetPlayerFacing()
    return facing and math.floor(math.deg(facing) + 0.5)
end

local function roomCandidateNames(z, x, y)
    local names = {}
    for _, id in ipairs(logic.roomCandidates(z, x, y)) do
        names[#names + 1] = logic.describeRoom(z, id, nil)
    end
    return table.concat(names, "; ")
end

-- One log entry: {date, kind ("place", "room", "edge", "bump", "session", "zone", "surr", ...),
-- text}, where the player was (the data's cell and its text, the room candidates indoors, the high
-- pieces the player was on) and the facing in degrees (0 = north, counter-clockwise).
local function logEntry(kind, text, x, y, extra)
    local log = activeLog()
    if log == nil then
        return
    end
    local e = { date("%Y-%m-%d %H:%M:%S"), kind, text or "" }
    if x then
        e.x, e.y = round1(x), round1(y)
    end
    if zone and x then
        local value, r, c = logic.valueAt(zone, x, y)
        e.zone, e.r, e.c = zone.key, r, c
        e.cell = logic.describe(zone, value, true)
        if IsIndoors() then
            e.indoors = true
            e.candidates = roomCandidateNames(zone, x, y)
            e.room = room and logic.describeRoom(zone, room, nil) or nil
        end
    end
    e.swimming = IsSwimming() or nil
    e.facing = facingDegrees()
    local on = {}
    for piece in pairs(high) do
        on[#on + 1] = piece
    end
    if #on > 0 then
        table.sort(on)
        e.high = table.concat(on, " ")
    end
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    table.insert(log.entries, e)
    log.entries = trim(log.entries, LOG_MAX)
end

-- A trail point every few yards: "time x y", plus i (indoors), s (swimming), g (ghost) and f with
-- the facing in degrees, as one token ("isf270").
local function logTrail(x, y)
    if trailX and (x - trailX) ^ 2 + (y - trailY) ^ 2 < TRAIL_STEP * TRAIL_STEP then
        return
    end
    local log = activeLog()
    if log == nil then
        return
    end
    trailX, trailY = x, y
    local facing = facingDegrees()
    local flags = (IsIndoors() and "i" or "") .. (IsSwimming() and "s" or "") .. (UnitIsGhost("player") and "g" or "")
        .. (facing and ("f" .. facing) or "")
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
            logic.unpack(found, GetLocale())
        end
        zone = found
        if found then
            logEntry("zone", found.label or found.key, x, y)
        end
        forgetPlace()
        -- the targets are numbered per zone
        guide.key, guide.named, waterGuide.key, waterGuide.named = nil, nil, nil, nil
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

-- A beacon (a route or a straight line) leads the way: the guidance to entrances and street
-- beginnings and the turn hints on roads and streets stay quiet (setting beaconQuiet).
local function beaconGuides()
    return module.settings.beaconQuiet and WowVision.base.navigation.maps:isGuiding()
end

-- The facing for turn hints, or nil when they are off.
local function turnFacing()
    if module.settings.turnHints and not beaconGuides() then
        return GetPlayerFacing()
    end
end

-- Guidance to the nearest target within reach (on foot an entrance or a street's beginning, a way
-- out of the water while swimming): said with distance and direction; again when the direction
-- has turned (GUIDE_TURN degrees off the last said one, after GUIDE_REPEAT), and once at it. The
-- name and the way through only until another target is named: then "entrance, 6 to the north".
-- `brief` (a beacon leads): only that the target is there and its name, once.
local function guideTo(z, g, t, x, y, brief)
    local now = GetTime()
    if brief then
        if g.key ~= t.key then
            say(t.name, t.kind, x, y)
            g.key, g.dir, g.at, g.time, g.named = t.key, t.dir, false, now, t.key
        end
        return
    end
    local named = g.named ~= t.key
    if t.d <= logic.GUIDE_AT then
        if not (g.key == t.key and g.at) then
            say(logic.guideText(z, t, named, true), t.kind, x, y)
            g.key, g.dir, g.at, g.time, g.named = t.key, t.dir, true, now, t.key
        end
        return
    end
    local turned = g.dir ~= t.dir and logic.angleOff(t.x - x, t.y - y, g.dir or t.dir) > GUIDE_TURN
    if g.key ~= t.key or (turned and now - g.time >= GUIDE_REPEAT) or (g.at and t.d > logic.GUIDE_AT + GUIDE_AWAY) then
        say(logic.guideText(z, t, named, false), t.kind, x, y)
        g.key, g.dir, g.at, g.time, g.named = t.key, t.dir, false, now, t.key
    end
end

local function checkGuide(z, x, y)
    if not module.settings.guidance then
        guide.key = nil
        return
    end
    -- a beacon starting or ending: the nearest target is said anew in the other manner, by name
    local brief = beaconGuides()
    if brief ~= guide.brief then
        guide.brief, guide.key, guide.named = brief, nil, nil
    end
    local t = logic.footTarget(z, x, y, region)
    if t == nil then
        guide.key = nil
        return
    end
    guideTo(z, guide, t, x, y, brief)
end

-- While swimming: the nearest way out of the water; climbing out at an edge warns again.
local function checkWater(z, x, y)
    warnedEdges, high = {}, {}
    local t = module.settings.guidance and logic.exitTarget(z, x, y)
    if t then
        guideTo(z, waterGuide, t, x, y)
    else
        waterGuide.key = nil
    end
end

-- Drop edges: the one within reach ahead in the view first, else one in the path with its
-- distance. An edge warns again after the player is out of its reach and it is no longer in the
-- path; edges of a wall-walk or a deck high over the ground only while the player is up there.
local function checkEdges(z, x, y, px, py)
    logic.updateHigh(z, high, x, y, outAt ~= nil and GetTime() - outAt < CAME_OUT)
    -- the way the player moves (not the facing: strafing and walking back count too)
    local vx, vy = nil, nil
    local moved = px and math.sqrt((x - px) ^ 2 + (y - py) ^ 2) or 0
    if moved >= MOVE_MIN then
        vx, vy = (x - px) / moved, (y - py) / moved
    end
    local inPath = {}
    if vx then
        logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, high, nil, inPath)
    end
    for i in pairs(warnedEdges) do
        if not inPath[i] and logic.edgeDistance(z, i, x, y) > EDGE_REACH + EDGE_REARM then
            warnedEdges[i] = nil
        end
    end
    if not module.settings.dropEdges then
        return
    end
    local i = logic.nearestEdge(z, x, y, EDGE_REACH, high, GetPlayerFacing(), warnedEdges)
    local along = nil
    if i == nil and vx then
        i, along = logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, high, warnedEdges)
    end
    if i then
        local text = logic.edgeText(z, i, along)
        local now = GetTime()
        if text ~= lastEdgeText or now - edgeAt >= EDGE_REPEAT then
            say(text, "edge", x, y)
            lastEdgeText, edgeAt = text, now
        end
        warnedEdges[i] = true
    end
end

-- On the square: a street, water or square not said yet comes within the approach distance.
local function checkApproach(z, x, y)
    local here = logic.regionAt(z, x, y)
    if here and here ~= region and here.value == region.value then
        region, saidMouths = here, {}
    end
    local text = logic.approachText(z, region, x, y, saidMouths)
    if text then
        say(text, "near", x, y)
    end
end

-- The movement keys held (f forward, b back, l and r strafe, a autorun), for the log.
local function movementKeys(flags)
    return (flags.moveForward and "f" or "") .. (flags.moveBackward and "b" or "")
        .. (flags.strafeLeft and "l" or "") .. (flags.strafeRight and "r" or "") .. (flags.autorun and "a" or "")
end

-- The way the player pushes from the movement keys held and the facing, as a unit vector.
local function pushDirection()
    local facing = GetPlayerFacing()
    local flags = WowVision.movement.flags
    if facing == nil then
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

-- Naming what the player bumps into: when they push against something (the wall detection's
-- "blocked", held for a moment; nothing while wall detection is disabled), the object in the way
-- they push (a barrel, a cart, a fence), or the wall of the building ahead ("wall of auction
-- house"), or indoors a wall. Once per bump; the same thing again only after moving freely.
local function checkBump(z, x, y, px, py, isIndoors)
    local now = GetTime()
    local dt = bump.time and now - bump.time or nil
    bump.time = now
    if not module.settings.bumps or px == nil or dt == nil or IsSwimming() then
        bump.ticks = 0
        return
    end
    local moved = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
    local walls = WowVision.base.navigation.walls
    if walls.severity ~= 1 or now - walls.severityAt > BUMP_FRESH then
        bump.ticks = 0
        if moved > BUMP_MOVING then
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
    local o = logic.objectAhead(z, x, y, vx, vy, logic.BUMP_REACH, isIndoors and room or 0)
    local text, key
    if o then
        text, key = o.name, o
    elseif isIndoors then
        text, key = L["wall"], "wall"
    else
        local owner = logic.wallOwner(z, x, y, vx, vy, WALL_REACH)
        if owner then
            text, key = string.format(L["wall of %s"], owner), owner
        end
    end
    if text and key ~= bump.key then
        say(text, "bump", x, y, nil, { keys = movementKeys(WowVision.movement.flags) })
    end
    bump.key = key or bump.key
end

-- Gentle bends: on a road piece, once the road ahead has turned BEND_THRESHOLD degrees from where
-- it led at the last announcement or hint but keeps its direction words (a new direction is an
-- announcement of its own), which way to turn, unless the player faces that way already. Where
-- the road leads comes from its centre line, not from the player's steps, so drifting or turning
-- on the spot says nothing. Not on city streets: a wide street has several centre lines side by
-- side (around planters and stalls), and where it leads 10 yd ahead jumps between them (a replay
-- of the Trade District walk gave 20 hints in 4 minutes); a street's new direction is still said.
local function checkBend(z, x, y)
    local key = outdoor.current
    local facing = turnFacing()
    if not logic.isWayKey(key) or not logic.ROADS[logic.kind(z, logic.keyPlace(key))] or facing == nil then
        bendFrom = nil
        return
    end
    local dir, ahead = logic.wayAhead(z, x, y, facing, BEND_LOOK)
    if dir == nil then
        return
    end
    if bendFrom == nil then
        bendFrom = dir
        return
    end
    local turn, moveOn = logic.bendTurn(bendFrom, dir, facing, BEND_THRESHOLD)
    if moveOn then
        bendFrom = dir
    end
    if turn ~= 0 and ahead % 100 == tonumber(key:sub(2)) % 100 then
        say(logic.turnText(turn), "bend", x, y)
    end
end

-- On a city street or walk (not a road: there the user turned too early on words said ahead):
-- the next piece's direction AHEAD_LOOK yd before it, once, with the distance ("northeast to
-- southwest in 10 yards"), so there is time to turn where a street ends at the water and goes on
-- to the side (Stormwind 2026-09-29: the new direction came 4 to 8 yd before the water). Stepping
-- onto that piece then says nothing more.
local function checkAhead(z, x, y)
    local key = outdoor.current
    local facing = GetPlayerFacing()
    if not logic.isWayKey(key) or logic.ROADS[logic.kind(z, logic.keyPlace(key))] or facing == nil then
        return
    end
    if aheadKey and (x - aheadX) ^ 2 + (y - aheadY) ^ 2 > (logic.AHEAD_LOOK + 6) ^ 2 then
        aheadKey = nil
    end
    local current = tonumber(key:sub(2))
    local value, yards = logic.pieceAhead(z, x, y, facing, current, logic.AHEAD_LOOK)
    if value == nil or yards < logic.AHEAD_MIN then
        return
    end
    local nextKey = logic.outdoorKey(z, value)
    if nextKey ~= aheadKey then
        aheadKey, aheadX, aheadY = nextKey, x, y
        say(logic.aheadText(z, value, current, yards), "ahead", x, y)
    end
end

-- Outdoors: the place, announced after the entry distance; on a square what comes close.
local function checkPlace(z, x, y)
    local value
    value, laneDecided = logic.outdoorValue(z, x, y, IsSwimming(), isWay(outdoor.current, true))
    local previous = outdoor.current
    if outdoor:update(logic.outdoorKey(z, value), x, y) then
        local text, square, said = logic.spotText(z, x, y, value, previous,
            { cut = true, facing = turnFacing(), swimming = IsSwimming() })
        -- on a square: what was said now (its exits, what is close) is not said again on coming close
        region, saidMouths = square, said or {}
        bendFrom = nil
        if outdoor.current == aheadKey then
            -- said before reaching it (checkAhead): only logged
            logEntry("place", text, x, y, { walked = round1(outdoor.walked), early = true })
        else
            say(text, "place", x, y, outdoor.walked)
        end
        aheadKey = nil
    elseif region and outdoor.current == logic.placeOf(region.value) then
        -- also from the square's edge (a step onto the street beside it does not leave it)
        checkApproach(z, x, y)
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
        forgetPlace()
        lastX, lastY = nil, nil
        return
    end
    local x, y, _z, map = UnitPosition("player")
    if x == nil then
        return
    end
    if not sessionLogged and activeLog() then
        sessionLogged = true
        logEntry("session", GetRealmName() .. ", " .. UnitName("player"), x, y)
    end
    local z = findZone(x, y, map)
    if z == nil then
        return
    end
    logTrail(x, y)
    local isIndoors = IsIndoors()
    if isIndoors ~= wasIndoors then
        forgetPlace()
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
            say(logic.roomText(z, room, lastRoom, true), "room", x, y, indoor.walked)
            lastRoom = room
        end
        return
    end
    lastRoom = nil
    if IsSwimming() then
        guide.key = nil
        checkWater(z, x, y)
    else
        waterGuide.key = nil
        checkEdges(z, x, y, px, py)
        checkGuide(z, x, y)
    end
    checkPlace(z, x, y)
    checkAhead(z, x, y)
    checkBend(z, x, y)
end)

-- /wv surr log on|off switches the walk log; /wv surr log [count] says the last entries;
-- /wv surr log clear empties it.
local function speakLog(args)
    local log = logStore()
    if args == "on" or args == "off" then
        log.on = args == "on" or nil
        WowVision:speak(log.on and "Surroundings log on" or "Surroundings log off")
        return
    elseif args == "clear" then
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
    WowVision:speak(string.format("Log %s, %d entries, %d trail points. ", log.on and "on" or "off", #log.entries, #log.trail)
        .. table.concat(parts, ". "))
end

-- /wv surr: what the module knows here, spoken and printed.
module:registerCommand({
    name = "surr",
    description = "Surroundings: speak the current place or room and the data state; log on|off|clear|[count]; around",
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
            parts[#parts + 1] = "No surroundings data loaded; is the WowVision_Surroundings addon installed and enabled? "
                .. "It is at github.com/JeanStiletto/WowVision_Surroundings"
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
                local i, d, dir, e = logic.nearestEntrance(z, x, y, 100)
                if i then
                    parts[#parts + 1] = string.format("Nearest entrance: %s, %d yards to the %s", e.text, math.floor(d + 0.5), z.compass[dir])
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

-- The describe key: the place or room here as the announcements describe it, without their cuts;
-- plus the guidance target.
function module:describeAround()
    local x, y, _z, map = UnitPosition("player")
    local z = x and findZone(x, y, map)
    if z == nil then
        return
    end
    local text
    if IsIndoors() then
        text = room and logic.roomText(z, room, nil, false) or L["room unknown"]
    else
        local swimming = IsSwimming()
        local value = logic.outdoorValue(z, x, y, swimming, isWay(outdoor.current, true))
        -- a spot the data has no place for (a gap in the map) says so, as a room does
        text = logic.spotText(z, x, y, value, nil, { facing = turnFacing(), swimming = swimming }) or L["place unknown"]
        local t = nil
        if self.settings.guidance and swimming then
            t = logic.exitTarget(z, x, y)
        elseif self.settings.guidance then
            t = logic.footTarget(z, x, y, region)
        end
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, t.d <= logic.GUIDE_AT)
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
