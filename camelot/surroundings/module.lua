-- Surroundings (WoW: Forever): describes where the player walks, from the WowVision_Surroundings
-- data addon (without it the module is silent). Outdoors the place entered ("forest", "shore of
-- Crystal Lake, water to the north", "road, north to south"), on a square its ways on, indoors
-- the room and its doorways, and in a city's big halls (the indoor layer: Ironforge) the same as
-- on its streets; drop edges, guidance to entrances, street beginnings and ways out of the water,
-- turn hints on roads, what the player bumps into, and where to wait for a ship, zeppelin, lift or
-- the Deeprun Tram. The logic and the texts are
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
local BEND_WALK = 10 -- walked on the way since the last announcement or hint before a bend is said
local STOP_REARM = 3 -- walked off every stop before the same stop is said again
local HALL_GAP = 15 -- yards walked in a hall with no hall floor near (a bridge, over lava) before it ends
local PASSED_REACH = 8 -- a doorway this close (a gate is 20 yd wide) when the player changes room, hall or goes in or out was walked through
local PASSED_SAME = 4 -- a guidance target this close to that doorway is that doorway
local MOAT_NEAR = 8 -- down in a moat the player stays in it while a moat cell is this near
local MOAT_OUT = 4 -- walking this near a moat's way out takes the player out of it

-- What the module knows about where the player is
local zone = nil -- the zone data the player is in (unpacked)
local outdoor = logic.newEntry(ENTRY_OUTDOORS)
local indoor = logic.newEntry(ENTRY_INDOORS)
local laneDecided = false -- a centre line decided the last outdoor value (see distanceFor)
local leftWay = nil -- the way piece the player last stepped off (back onto it only after a few yards)
local wasIndoors = nil -- indoors at the last look (nil before the first)
local lastCheck = 0
local lastX, lastY = nil, nil -- the previous position, for walking through doorways
local room = nil -- the room the player is in as far as known (switches at once)
local roomByDoor = false -- ... entered through one of its doorways: it holds over stacked floors (logic.resolveRoom)
local lastRoom = nil -- the last announced room, for the interior name
local layerMode = false -- in one of the big halls of the indoor layer: its places, not the room
-- the doorway the player came into the room by, left out of the doorway guidance until they were
-- once beyond the guidance reach from it (it said "at the way outside" right after coming in)
local entryRoom, entryDoor, entryAway = nil, nil, false
local high = {} -- the high floor pieces (wall-walks, bridge decks, raised city floors) the player is on

-- Empties a set in place (the zone's lookups hold the same table: logic.setOn).
local function wipeSet(set)
    for k in pairs(set) do
        set[k] = nil
    end
end
local outAt = nil -- when the player last came out of a building
local warnedEdges = {} -- drop edges warned about (again after stepping out of reach)
local lastEdgeText, edgeAt = nil, 0 -- the last edge warning and when: a neighbouring piece of the same edge stays quiet
local region = nil -- the square the player is on (announced), for what comes close
local saidMouths = {} -- its streets, water and the like already said on this visit
local bendFrom = nil -- where the road led at the last message (radians), nil: take it anew
local bendWalked = 0 -- walked on the way since the last announcement or bend hint
local aheadKey = nil -- the next piece of a city street, said before reaching it (not again on it)
local aheadX, aheadY = nil, nil -- where it was said: walking far from there forgets it
-- Guidance: the target last said (key and position), the direction said, whether it was "at"
-- it, when, the target last said by name, and whether it was said briefly (a beacon led)
local guide = { key = nil, x = nil, y = nil, dir = nil, at = false, time = 0, named = nil, brief = nil } -- on foot
local waterGuide = { key = nil, x = nil, y = nil, dir = nil, at = false, time = 0, named = nil } -- ways out of the water
local bump = { ticks = 0, key = nil, free = 0, time = nil }
local stopSaid, stopOut = nil, 0 -- the stop last said, and how far the player walked off stops since
-- In a hall the game calls outdoors (Ironforge's, the Undercity's): yards walked since its floor
-- was last near; nil = not in such a hall
local hallGap = nil
-- The doorway just walked through {x, y}: not said again (it is a doorway on both sides) until the
-- player was once farther than the guidance reach from it (user 2026-09-29: "Ausgang, 6 Meter im
-- Nordosten" right after going out through it)
local passed = nil
-- Down in a moat (Ironforge's Commons): its floor reaches under the walkways beside it, where the
-- map (no height) has the walkway; so once in it the player stays in it until walking out at its
-- way out or leaving its area, as on a high piece
local inMoat = false
local inPool = nil -- the pool the player is down in (logic.poolAt)

-- The UI map the game puts the player on (it knows the height: in the Ironforge halls Ironforge's,
-- on the ground above the Undercity Tirisfal's).
local function gameMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

-- Is the player in a hall the game calls outdoors (IsIndoors() is false in all of Ironforge's big
-- halls, user's walk 2026-09-29): its floor here while the game's map is the hall's. Short gaps in
-- the floor data (HALL_GAP) keep it; leaving the city changes the game's map.
local function updateHall(z, x, y, px, py)
    local uiMap = gameMap()
    if logic.inHall(z, x, y, uiMap) then
        hallGap = 0
    elseif hallGap and px and logic.isHallMap(z, uiMap) then
        hallGap = hallGap + logic.dist(x, y, px, py)
        if hallGap > HALL_GAP then
            hallGap = nil
        end
    else
        hallGap = nil
    end
    return hallGap ~= nil
end

-- Indoors: as the game says, or in one of the halls it calls outdoors (as of the last look).
local function isInside()
    return IsIndoors() or hallGap ~= nil
end

-- Forget the place on the ways (outdoors, or the indoor layer's): stepping between a room and the
-- indoor layer says the new one at once.
local function forgetWays()
    outdoor:reset()
    indoor:reset()
    region, saidMouths = nil, {}
    bendFrom, aheadKey, leftWay = nil, nil, nil
end

-- Forget where the player was: after a flight, in a new zone, on going in or out of a building.
-- The place or room there is then said at once.
local function forgetPlace()
    forgetWays()
    room, lastRoom, roomByDoor = nil, nil, false
    wipeSet(high)
    warnedEdges = {}
    layerMode = false
    inMoat = false
    inPool = nil
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
    -- before walking straight on carries the player off the way; back onto the piece just left
    -- only after a few yards (along the seam of two pieces the directions switched four times in
    -- a second, Stormwind 2026-09-29)
    if logic.isWayKey(key) and logic.isWayKey(outdoor.current) and key ~= outdoor.current then
        return key == leftWay and ENTRY_NARROW or 0
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
        names[#names + 1] = logic.finishText(logic.describeRoom(z, id, nil))
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
        e.cell = logic.finishText(logic.describe(zone, value, true))
        if isInside() then
            e.indoors = true
            e.hall = hallGap ~= nil or nil
            e.candidates = roomCandidateNames(zone, x, y)
            e.room = room and logic.finishText(logic.describeRoom(zone, room, nil)) or nil
            local layer = logic.layer(zone, IsIndoors())
            if layerMode and layer then
                e.layer = logic.finishText(logic.describe(layer, logic.valueAt(layer, x, y), true))
            end
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

-- A trail point every few yards: "time x y", plus i (indoors), h (in a hall the game calls
-- outdoors), s (swimming), g (ghost) and f with the facing in degrees, as one token ("isf270").
local function logTrail(x, y)
    if trailX and logic.dist2(x, y, trailX, trailY) < TRAIL_STEP * TRAIL_STEP then
        return
    end
    local log = activeLog()
    if log == nil then
        return
    end
    trailX, trailY = x, y
    local facing = facingDegrees()
    local flags = (IsIndoors() and "i" or "") .. (hallGap and "h" or "") .. (IsSwimming() and "s" or "")
        .. (UnitIsGhost("player") and "g" or "")
        .. (facing and ("f" .. facing) or "")
    table.insert(log.trail, string.format("%d %.1f %.1f%s", time(), x, y, flags ~= "" and " " .. flags or ""))
    log.trail = trim(log.trail, TRAIL_MAX)
end

local function zones()
    return WowVisionSurroundingsData and WowVisionSurroundingsData.zones or {}
end

-- The data format this module reads (zone.format): 2 carries directions as angles. Data of
-- another format is left alone, and said once (the data addon and WowVision are switched
-- together: branch clock-directions on both).
local FORMAT = 2
local formatWarned = false
local function formatFits(z)
    if (z.format or 1) == FORMAT then
        return true
    end
    if not formatWarned then
        formatWarned = true
        WowVision:speak(string.format("Surroundings data %s has format %d, this WowVision reads format %d; "
            .. "switch the data addon and WowVision to the same branch", z.key or "?", z.format or 1, FORMAT))
    end
    return false
end

-- Clock hours or compass words: the compass module's Directions setting, shared by every
-- direction WowVision speaks.
local function updateWords()
    local compass = WowVision.base.navigation.compass
    logic.clock = compass ~= nil and compass.settings.directions == "clock"
end

-- The registered zone covering the position; unpack it, free the one left behind.
local function findZone(x, y, map)
    if zone and zone.map == map and logic.covers(zone, x, y) then
        return zone
    end
    local found = nil
    for _, z in ipairs(zones()) do
        if z.map == map and logic.covers(z, x, y) and formatFits(z) then
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
            logic.setOn(found, high)
        end
        zone = found
        if found then
            logEntry("zone", found.label or found.key, x, y)
        end
        forgetPlace()
        -- the targets and stops are numbered per zone
        guide.key, guide.named, waterGuide.key, waterGuide.named = nil, nil, nil, nil
        stopSaid, stopOut = nil, 0
    end
    return zone
end

local function say(text, kind, x, y, walked, extra)
    text = logic.finishText(text)
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
    g.x, g.y = t.x, t.y
    if logic.atTarget(z, t, x, y) then
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

local function checkGuide(z, x, y, roomId, skipDoor)
    if not module.settings.guidance then
        guide.key = nil
        return
    end
    -- a beacon starting or ending: the nearest target is said anew in the other manner, by name
    local brief = beaconGuides()
    if brief ~= guide.brief then
        guide.brief, guide.key, guide.named = brief, nil, nil
    end
    -- in a big room: its doorways; on foot elsewhere: entrances and street beginnings
    local t
    local prefer = guide.key and guide.x and { x = guide.x, y = guide.y } or nil
    if roomId then
        t = logic.roomDoorTarget(z, roomId, x, y, skipDoor, prefer)
    else
        t = logic.footTarget(z, x, y, region, prefer)
    end
    -- not the beginning of the way the player is on (stepping out of a street onto its square)
    if t and t.kind == "way" and logic.isWayKey(outdoor.current) and logic.keyLabel(z, outdoor.current) == t.name then
        t = nil
    end
    -- not the foot of a climb the player is past (going up it)
    if t and t.kind == "climb" and logic.pastTarget(z, t, x, y) then
        t = nil
    end
    -- the doorway just walked through stays quiet (said again as new once the player left it)
    if t == nil or (passed and logic.dist2(t.x, t.y, passed.x, passed.y) <= PASSED_SAME ^ 2) then
        guide.key = nil
        return
    end
    guideTo(z, guide, t, x, y, brief)
end

-- The value of the nearest moat cell within `reach` yards of the player, or nil.
local function moatNear(layer, x, y, reach)
    local _d, _cx, _cy, v = logic.nearestCell(layer, x, y, math.ceil(reach / layer.cell), reach, function(value)
        return value ~= 0 and logic.kindOf(layer, value) == "moat"
    end)
    return v
end

-- Down in a moat? On a moat cell the player is; once in it, still while a moat cell is near,
-- until walking near its way out. Returns the moat's value while in it.
local function updateMoat(layer, x, y)
    local v = logic.valueAt(layer, x, y)
    if v and v ~= 0 and logic.kind(layer, logic.placeOf(v)) == "moat" then
        inMoat = true
        return v
    end
    if not inMoat then
        return nil
    end
    local near = moatNear(layer, x, y, MOAT_NEAR)
    if near == nil or logic.nearestExit(layer, x, y, MOAT_OUT) then
        inMoat = false
        return nil
    end
    return near
end

-- Walked through a doorway (the room, the big hall or inside and outside changed, or a doorway of
-- the room was crossed): the nearest doorway within PASSED_REACH is the one passed.
local function notePassed(z, x, y)
    local best, bx, by = PASSED_REACH ^ 2, nil, nil
    for _, door in ipairs(z._index.doors or {}) do
        local dx, dy = logic.doorWorld(z, door)
        if dx then
            local d = logic.dist2(dx, dy, x, y)
            if d <= best then
                best, bx, by = d, dx, dy
            end
        end
    end
    if bx then
        passed = { x = bx, y = by, reach = logic.GUIDE_REACH }
    end
end

-- Stepped off a way onto a square: the beginning of that way the player came out of stays quiet,
-- as a doorway walked through does, until the player is beyond its guidance reach (the lane
-- through Stormwind's gate is guided to from 17 yd; user 2026-09-30).
local function notePassedBeginning(z, x, y, square, wayKey)
    local _i, _d, _dir, b = logic.nearestBeginning(z, square, x, y, logic.GUIDE_REACH)
    if b and b.label == logic.keyLabel(z, wayKey) then
        passed = { x = b.x, y = b.y, reach = logic.beginningReach(logic.GUIDE_REACH, b) }
    end
end

-- Forget the doorway or beginning passed once the player was farther than its guidance reach.
local function updatePassed(x, y)
    if passed and logic.dist2(x, y, passed.x, passed.y) > passed.reach ^ 2 then
        passed = nil
    end
end

-- Guidance to the nearest way out of the water (or, with `moat`, of a moat; with `pool`, of that
-- pool), when there is one.
local function guideExit(z, x, y, moat, pool)
    local t = module.settings.guidance and logic.exitTarget(z, x, y, moat, pool)
    if t then
        guideTo(z, waterGuide, t, x, y)
    else
        waterGuide.key = nil
    end
end

-- Down in a pool? Not while swimming (the water's own ways out); held near its rim (poolAt).
-- Returns the pool and whether it is only held (then nothing new is said).
local function updatePool(z, x, y)
    local pool, held = nil, false
    if not IsSwimming() then
        pool, held = logic.poolAt(z, x, y, inPool)
    end
    inPool = pool
    return pool, held
end

-- Out of a pool: its way out is named with it again on stepping back in (a pool's keys are "p1"...;
-- the ways out while swimming keep their naming as before).
local function leavePool()
    waterGuide.key = nil
    if type(waterGuide.named) == "string" then
        waterGuide.named = nil
    end
end

-- While swimming: the nearest way out of the water; climbing out at an edge warns again.
local function checkWater(z, x, y)
    warnedEdges = {}
    wipeSet(high)
    guideExit(z, x, y)
end

-- Drop edges: the one within reach ahead in the view first, else one in the path with its
-- distance. An edge warns again after the player is out of its reach and it is no longer in the
-- path; edges of a wall-walk or a deck high over the ground only while the player is up there.
-- Indoors (the indoor layer's edges) `rooms` is the set of rooms the player may be in: an edge
-- inside warns only in the room its floor belongs to (its piece), as a high piece's edge.
local function checkEdges(z, x, y, px, py, rooms)
    local on = rooms
    if on == nil then
        local _on, changed = logic.updateHigh(z, high, x, y, outAt ~= nil and GetTime() - outAt < CAME_OUT, px, py)
        if changed then
            -- the squares found so far were flooded on the old level
            logic.forgetRegions(z)
        end
        on = high
    end
    -- the way the player moves (not the facing: strafing and walking back count too)
    local vx, vy = nil, nil
    local moved = px and logic.dist(x, y, px, py) or 0
    if moved >= MOVE_MIN then
        vx, vy = (x - px) / moved, (y - py) / moved
    end
    local inPath = {}
    if vx then
        logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, on, nil, inPath)
    end
    for i in pairs(warnedEdges) do
        if not inPath[i] and logic.edgeDistance(z, i, x, y) > EDGE_REACH + EDGE_REARM then
            warnedEdges[i] = nil
        end
    end
    if not module.settings.dropEdges then
        return
    end
    local i = logic.nearestEdge(z, x, y, EDGE_REACH, on, GetPlayerFacing(), warnedEdges)
    local along, qx, qy = nil, nil, nil
    if i == nil and vx then
        i, along, qx, qy = logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, on, warnedEdges)
    end
    if i and inMoat and logic.edge(z, i).into == 4 then
        -- down in the moat: the walkway's edge above is no drop
        warnedEdges[i] = true
        i = nil
    end
    if i then
        local text = logic.edgeText(z, i, along, x, y, qx, qy)
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
    local moved = logic.dist(x, y, px, py)
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
        local owner, what = logic.wallOwner(z, x, y, vx, vy, WALL_REACH)
        if owner then
            text, key = string.format(what == "side" and L["%s, side"] or L["wall of %s"], owner), owner
        end
    end
    if text and key ~= bump.key then
        say(text, "bump", x, y, nil, { keys = movementKeys(WowVision.movement.flags) })
    end
    bump.key = key or bump.key
end

-- Gentle bends: on a way, once the way ahead has turned BEND_THRESHOLD degrees from where it led
-- at the last announcement or hint but keeps its direction words (a new direction is an
-- announcement of its own), which way to turn, unless the player faces that way already. Where
-- the way leads comes from its centre line, not from the player's steps, so drifting or turning
-- on the spot says nothing. Roads and streets alike (one rule set, user 2026-10-01): with the
-- streets' lines drawn from the painted way and pruned over the whole floor, the close parallel
-- lines that made the hints jump (183 instead of 9 in a replay, 2026-09-30) are gone.
local function checkBend(z, x, y, px, py)
    local key = outdoor.current
    local facing = turnFacing()
    if not logic.isWayKey(key) or facing == nil then
        bendFrom, bendWalked = nil, 0
        return
    end
    -- only after walking on along the way: turning about on the spot, where several short
    -- lines meet (the foot of the griffon ramp: six hints in 40 s in a replay), says nothing
    if px then
        bendWalked = bendWalked + logic.dist(x, y, px, py)
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
    if turn ~= 0 and logic.outdoorKey(z, ahead, key) == key and bendWalked >= BEND_WALK then
        say(logic.turnText(turn), "bend", x, y)
        bendWalked = 0
    end
end

-- On a way (a road, a city street or walk; the same rules for both, user 2026-09-30: the careful
-- one of the streets for all): the next piece AHEAD_LOOK yd before it, once, said as on entering it
-- ("street to Cathedral Square, northeast to southwest"; no distance, the user found it spam and
-- stops and turns on hearing it), so there is time to turn where a street ends at the water and
-- goes on to the side (Stormwind 2026-09-29: the new direction came 4 to 8 yd before the water).
-- Stepping onto that piece then says nothing more. Looked for along the way one MOVES, only while
-- moving: taken from the facing it spoke on every turn on the spot, a different piece each time
-- among the short lines at the griffon ramp's foot (nine lines in 50 s, user's walk 2026-09-30),
-- and it kept talking while a beacon led (then the beacon says where to go).
local function checkAhead(z, x, y, px, py)
    local key = outdoor.current
    if not logic.isWayKey(key) or px == nil or beaconGuides() then
        return
    end
    if aheadKey and logic.dist2(x, y, aheadX, aheadY) > (logic.AHEAD_LOOK + 6) ^ 2 then
        aheadKey = nil
    end
    if logic.dist(x, y, px, py) < MOVE_MIN then
        return
    end
    local heading = math.atan2(y - py, x - px)
    local value, yards = logic.pieceAhead(z, x, y, heading, key, logic.AHEAD_LOOK)
    if value == nil or yards < logic.AHEAD_MIN then
        return
    end
    local nextKey = logic.outdoorKey(z, value, key)
    if nextKey ~= aheadKey then
        aheadKey, aheadX, aheadY = nextKey, x, y
        say(logic.describe(z, value, true), "ahead", x, y)
    end
end

-- Stops: stepping onto the floor where one waits for a ship, zeppelin, lift or tram says so and
-- which way it will be ("wait for the ship to Auberdine, ship to the southwest"); the same stop
-- again only after the player walked STOP_REARM yards off every stop (a step off the edge of the
-- area and back is quiet). `rooms`: indoors the set of rooms the player may be in, nil outdoors.
local function checkStop(z, x, y, px, py, rooms)
    local i = logic.stopAt(z, x, y, rooms)
    if i then
        stopOut = 0
        if i ~= stopSaid then
            say(logic.stopText(z, i, x, y), "stop", x, y)
            stopSaid = i
        end
    elseif stopSaid and px then
        stopOut = stopOut + logic.dist(x, y, px, py)
        if stopOut >= STOP_REARM then
            stopSaid = nil
        end
    end
end

-- Indoors: the rooms the player may be in: the room when known, else the candidates here.
local function roomsHere(z, x, y)
    local here = {}
    if room then
        here[room] = true
    else
        for _, id in ipairs(logic.fittingRooms(z, logic.roomCandidates(z, x, y), IsIndoors())) do
            here[id] = true
        end
    end
    return here
end

-- Outdoors: the place, announced after the entry distance; on a square what comes close.
local function checkPlace(z, x, y, forced)
    local value
    if forced then
        value, laneDecided = forced, false
    else
        value, laneDecided = logic.outdoorValue(z, x, y, IsSwimming(), isWay(outdoor.current, true))
    end
    local previous = outdoor.current
    if outdoor:update(logic.outdoorKey(z, value, outdoor.current), x, y) then
        leftWay = logic.isWayKey(previous) and previous or nil
        local text, square, said = logic.spotText(z, x, y, value, previous,
            { cut = true, facing = turnFacing(), swimming = IsSwimming() })
        -- on a square: what was said now (its exits, what is close) is not said again on coming close
        region, saidMouths = square, said or {}
        if leftWay and square then
            notePassedBeginning(z, x, y, square, leftWay)
        end
        bendFrom, bendWalked = nil, 0
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

-- In a big hall of the indoor layer: its pieces, as the city's streets; down in a moat its way out,
-- as out of a canal (user 2026-09-29), and so down in a pool (2026-10-02). `here`: the rooms the
-- player may be in.
local function updateLayer(z, layer, x, y, px, py, here)
    if not layerMode then
        layerMode = true
        forgetWays()
        notePassed(z, x, y)
    end
    lastRoom = room or lastRoom
    local moat = updateMoat(layer, x, y)
    local pool, held = nil, false
    if not moat then
        pool, held = updatePool(layer, x, y)
    end
    if moat or pool then
        guide.key = nil
        if not held then
            guideExit(layer, x, y, moat ~= nil, pool)
        end
    else
        leavePool()
        checkGuide(layer, x, y)
    end
    checkPlace(layer, x, y, moat)
    checkAhead(layer, x, y, px, py)
    checkStop(z, x, y, px, py, here)
end

-- Indoors: the room as far as known (switches at once; announced after the entry distance), the
-- doorways of a big room, the indoor layer's edges and halls, the stops in the room.
local function updateIndoors(z, x, y, px, py)
    local before = room
    local crossed = logic.crossedDoor(z, room, px, py, x, y)
    local found = logic.resolveRoom(z, x, y, room, px, py, roomByDoor, crossed or false, IsIndoors())
    if found ~= nil then
        if found ~= room then
            roomByDoor = crossed ~= nil
        end
        room = found
    end
    if crossed ~= nil or (before ~= nil and room ~= before) then
        notePassed(z, x, y)
    end
    local layer = logic.layer(z, IsIndoors())
    local here = roomsHere(z, x, y)
    if layer then
        -- lava and drops inside warn as outdoors (user 2026-09-29: indoors keeps what outdoors
        -- has), each in the room its floor belongs to: this room, or while it is unknown
        -- (stacked floors) any room here
        checkEdges(layer, x, y, px, py, here)
    end
    if layer and logic.inLayer(layer, room, x, y) then
        updateLayer(z, layer, x, y, px, py, here)
        return
    end
    if layerMode then
        layerMode = false
        forgetWays()
        notePassed(z, x, y)
    end
    if room ~= entryRoom then
        -- a new room: the doorway just walked through (a big room's, within reach)
        entryRoom, entryDoor, entryAway = room, nil, false
        if room then
            local _d, door = logic.nearestDoorway(z, room, x, y, logic.DOOR_REACH + 1)
            entryDoor = door
        end
    end
    if indoor:update(room, x, y) then
        local text = logic.roomText(z, room, lastRoom, true, x, y)
        if room and lastRoom and logic.sameRoomName(z, room, lastRoom) then
            -- the next numbered section of the same thing (tram tunnel 6, 7...): only logged
            logEntry("room", text, x, y, { walked = round1(indoor.walked), same = true })
        else
            say(text, "room", x, y, indoor.walked)
        end
        lastRoom = room
    end
    -- only a big room guides to its doorways (a small one leaves the entrance guidance as it was)
    if room and logic.isBigRoom(z, room) then
        if entryDoor and not entryAway then
            local dx, dy = logic.doorWorld(z, entryDoor)
            entryAway = dx == nil or logic.dist2(dx, dy, x, y) > logic.GUIDE_REACH ^ 2
        end
        checkGuide(z, x, y, room, not entryAway and entryDoor or nil)
    end
    checkStop(z, x, y, px, py, here)
end

-- Outdoors: the drop edges and the guidance on foot, or while swimming (or down in a pool, water
-- one stands in: its way out, named with it) the ways out of the water; the place, the next piece
-- ahead on a way and its bends, the stops.
local function updateOutdoors(z, x, y, px, py)
    lastRoom = nil
    local pool, held = updatePool(z, x, y)
    if IsSwimming() then
        guide.key = nil
        checkWater(z, x, y)
    elseif pool then
        guide.key = nil
        if not held then
            guideExit(z, x, y, false, pool)
        end
    else
        leavePool()
        checkEdges(z, x, y, px, py)
        checkGuide(z, x, y)
    end
    checkPlace(z, x, y)
    checkAhead(z, x, y, px, py)
    checkBend(z, x, y, px, py)
    if not IsSwimming() then
        checkStop(z, x, y, px, py, nil)
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
    updateWords()
    if not sessionLogged and activeLog() then
        sessionLogged = true
        logEntry("session", GetRealmName() .. ", " .. UnitName("player"), x, y)
    end
    local z = findZone(x, y, map)
    if z == nil then
        return
    end
    local px, py = lastX, lastY
    lastX, lastY = x, y
    local inHall = updateHall(z, x, y, px, py)
    logTrail(x, y)
    local isIndoors = IsIndoors() or inHall
    updatePassed(x, y)
    if isIndoors ~= wasIndoors then
        if wasIndoors ~= nil then
            notePassed(z, x, y)
        end
        forgetPlace()
        outAt = (wasIndoors and not isIndoors) and now or nil
        wasIndoors = isIndoors
    end
    checkBump(z, x, y, px, py, isIndoors)
    if isIndoors then
        updateIndoors(z, x, y, px, py)
    else
        updateOutdoors(z, x, y, px, py)
    end
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
                parts[#parts + 1] = "Place: " .. (logic.finishText(logic.describe(z, value, true)) or "none")
                local i, d, dir, e = logic.nearestEntrance(z, x, y, 100)
                if i then
                    parts[#parts + 1] = logic.finishText(string.format("Nearest entrance: %s, %d yards to the %s", e.text,
                        math.floor(d + 0.5), logic.dirWord(z, dir)))
                end
                local stop = logic.stopAt(z, x, y, isInside() and roomsHere(z, x, y) or nil)
                if stop then
                    parts[#parts + 1] = "Stop: " .. logic.finishText(logic.stopText(z, stop, x, y))
                end
                -- the game's own word on inside: IsIndoors, and its map (the halls it calls outdoors)
                parts[#parts + 1] = string.format("Game: %s, map %s%s", IsIndoors() and "indoors" or "outdoors",
                    tostring(gameMap()), hallGap and ", in a hall" or "")
                if isInside() then
                    local names = roomCandidateNames(z, x, y)
                    parts[#parts + 1] = "Indoors. Room candidates: " .. (names ~= "" and names or "none")
                    parts[#parts + 1] = "Current room: " .. (room and logic.finishText(logic.describeRoom(z, room, nil)) or "unknown")
                    local layer = logic.layer(z, IsIndoors())
                    if layer then
                        parts[#parts + 1] = "Indoor layer: " .. (logic.finishText(logic.describe(layer, logic.valueAt(layer, x, y), true)) or "none")
                            .. (layerMode and ", in use" or ", not in use")
                    end
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
    updateWords()
    local text
    local layer = logic.layer(z, IsIndoors())
    if isInside() and layerMode and layer then
        -- a big hall of the indoor layer: as a place outdoors; down in a pool its way out
        local pool = not IsSwimming() and logic.poolAt(layer, x, y)
        local value = logic.outdoorValue(layer, x, y, false, isWay(outdoor.current, true))
        text = logic.spotText(layer, x, y, value, nil, { facing = turnFacing() }) or L["place unknown"]
        local t = self.settings.guidance and (pool and logic.exitTarget(layer, x, y, false, pool)
            or not pool and logic.footTarget(layer, x, y, region))
        if t then
            text = text .. ", " .. logic.guideText(layer, t, true, t.d <= logic.GUIDE_AT)
        end
    elseif isInside() then
        text = room and logic.roomText(z, room, nil, false, x, y) or L["room unknown"]
        local t = room and self.settings.guidance and logic.roomDoorTarget(z, room, x, y)
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, t.d <= logic.GUIDE_AT)
        end
    else
        local swimming = IsSwimming()
        local pool = not swimming and logic.poolAt(z, x, y)
        local value = logic.outdoorValue(z, x, y, swimming, isWay(outdoor.current, true))
        -- a spot the data has no place for (a gap in the map) says so, as a room does
        text = logic.spotText(z, x, y, value, nil, { facing = turnFacing(), swimming = swimming }) or L["place unknown"]
        local t = nil
        if self.settings.guidance and (swimming or pool) then
            t = logic.exitTarget(z, x, y, false, pool or nil)
        elseif self.settings.guidance then
            t = logic.footTarget(z, x, y, region)
        end
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, t.d <= logic.GUIDE_AT)
        end
    end
    -- where one waits for a ship, zeppelin, lift or tram
    local stop = logic.stopAt(z, x, y, isInside() and roomsHere(z, x, y) or nil)
    if stop then
        text = text .. ", " .. logic.stopText(z, stop, x, y)
    end
    -- a drop or water edge within reach, or ahead in the line of the facing (user's walk
    -- 2026-10-01: 1.4 yd from the canal the key said only the walk's name, then the fall)
    if not isInside() then
        local facing = GetPlayerFacing()
        local i = logic.nearestEdge(z, x, y, EDGE_REACH, high, facing)
        local along, qx, qy = nil, nil, nil
        if i == nil and facing then
            i, along, qx, qy = logic.edgeAhead(z, x, y, math.cos(facing), math.sin(facing), EDGE_LOOK, high)
        end
        if i then
            text = text .. ", " .. logic.edgeText(z, i, along, x, y, qx, qy)
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
