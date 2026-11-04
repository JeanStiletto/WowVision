-- Surroundings (WoW: Forever): describes where the player walks, from the surroundings data (the
-- WowVision_Surroundings repository, a submodule at mapdata/WowVision_Surroundings; without it the
-- module is silent). Outdoors the place entered ("forest", "shore of
-- Crystal Lake, water to the north", "road, north to south"), on a square its ways on, indoors
-- the room and its doorways, and in a city's big halls (the indoor layers: Ironforge, the
-- Undercity) the same as on its streets; drop edges, guidance to entrances, street beginnings and ways out of the water,
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
-- on stairs with a wall along one side and a drop along the other: the way up said toward the
-- wall side (user 2026-10-07)
settings:add({ key = "wallSide", type = "Bool", label = L["Guide Up Stairs on Their Wall Side"], default = true })
-- while a beacon leads the way: entrances and street beginnings only by name, no turn hints
settings:add({ key = "beaconQuiet", type = "Bool", label = L["Quieter While a Beacon Guides"], default = true })
settings:add({ key = "bumps", type = "Bool", label = L["Name What I Bump Into"], default = true })
-- the places list (Alt-F10, placesUi.lua) names only the subzones the character has explored,
-- as the game's map does; off by default (user 2026-10-16: experienced players and tests)
settings:add({ key = "discovery", type = "Bool", label = L["Discovery Mode: Places List Names Only Explored Subzones"], default = false })

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
local ENTRY_INDOORS = 3 -- ... inside a room, and a place of a building's floors on their own fine grid
local CAME_IN_STEP = 10 -- yd between two looks at most for coming indoors to be a step (more: a hearthstone, a portal)
local JUMP = 100 -- yd between two looks from which the player was moved (a hearthstone, a portal; the tram runs up to 70 yd a second)
local EDGE_REACH = 3 -- a drop edge this close is warned about
local EDGE_REARM = 0.5 -- beyond the reach before the same edge warns again (not on position noise)
local EDGE_LOOK = 10 -- drop edges in the path are warned about this far ahead
local EDGE_REPEAT = 1 -- the same edge warning is not said again within this
local MOVE_MIN = 0.3 -- moved in one look that gives a direction to look ahead along
local AHEAD_FORGET = 6 -- yd farther from a piece said ahead than when it was said: forgotten
local GUIDE_TURN = 32 -- degrees off the last said direction before a new one is said
local GUIDE_REPEAT = 2 -- at least between two guiding announcements
local GUIDE_AWAY = 2 -- beyond "at" a target before it is guided to again
local WATER_KEEP = 6 -- yd from where the player stood up out of the water: its way out stays the target (leftWater)
-- yd: a new direction only when the last said one would also pass the target more than this beside
-- it (near a door a step sideways turns the bearing a lot, the way to it hardly: 10 lines in 35 s
-- at a shop door, walk 2026-10-08 16:06)
local GUIDE_MISS = 2
-- yd beyond a target's reach before it counts as left: said once and not left, it is not said again
-- when it drops out of reach and comes back, or another target came between (over all walks
-- replayed at running speed 2026-10-15, a third of the guidance lines were a target said again
-- that way, a door in Deathknell six times in 20 s at the edge of its reach)
local GUIDE_FORGET = 6
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
local HALL_ENTRY_DZ = 3.0 -- yd: into the halls by a hall's floor only where their layer has a floor this near the height held
local PASSED_REACH = 8 -- a doorway this close (a gate is 20 yd wide) when the player changes room, hall or goes in or out was walked through
local PASSED_SAME = 4 -- a guidance target this close to that doorway is that doorway

-- What the module knows about where the player is
local zone = nil -- the zone data the player is in (unpacked)
local outdoor = logic.newEntry(ENTRY_OUTDOORS)
local indoor = logic.newEntry(ENTRY_INDOORS)
local laneDecided = false -- a centre line decided the last outdoor value (see distanceFor)
local leftWay = nil -- the way piece the player last stepped off (back onto it only after a few yards)
local leftClimb = nil -- the ramp or stairs piece the player last stepped off (the same)
local wasIndoors = nil -- indoors at the last look (nil before the first)
local lastCheck = 0
local lastX, lastY = nil, nil -- the previous position, for walking through doorways
local room = nil -- the room the player is in as far as known (switches at once)
local roomByDoor = false -- ... entered through one of its doorways: it holds over stacked floors (logic.resolveRoom)
local lastRoom = nil -- the last announced room, for the interior name
local roomWaySaid = nil -- the way the last said room runs ("north to south"), for its next section
local layerMode = false -- in one of the big halls of the indoor layer: its places, not the room
-- the doorway the player came into the room by, left out of the doorway guidance until they were
-- once beyond the guidance reach from it (it said "at the way outside" right after coming in)
local entryRoom, entryDoor, entryAway = nil, nil, false
local cameIn = nil -- {x, y}: where the player walked in from outside (a step, not a jump), until ENTRY_INDOORS walked from it
-- drop edges warned about (again after stepping out of reach), per zone or layer: each numbers its
-- own edges (a halls edge's number kept into the Brill tavern's layer after a hearthstone, 2026-10-13)
local warnedEdges = {}
local lastEdgeText, edgeAt = nil, 0 -- the last edge warning and when: a neighbouring piece of the same edge stays quiet
local region = nil -- the square the player is on (announced), for what comes close
local saidMouths = {} -- its streets, water and the like already said on this visit
local saidLabels = {} -- the names said on a place, over the place's copies per floor piece
local bendFrom = nil -- where the road led at the last message (radians), nil: take it anew
local bendWalked = 0 -- walked on the way since the last announcement or bend hint
-- the next pieces of a way said before reaching them (not again on them, nor again ahead): key ->
-- { x, y, d }, the point on the line where the piece begins and the yards to it when said; walking
-- away from it forgets it
local aheadSaid = {}
local wayNamed = nil -- the place last said by name (on entering it or ahead): its next pieces say only their direction
-- Guidance: the target last said (key and position), the direction said, whether it was "at"
-- it, when, the target last said by name, and whether it was said briefly (a beacon led)
local guide = { key = nil, x = nil, y = nil, dir = nil, at = false, time = 0, named = nil, brief = nil, said = {} } -- on foot
local waterGuide = { key = nil, x = nil, y = nil, dir = nil, at = false, time = 0, named = nil, said = {} } -- ways out of the water
-- `said` of each: the targets said and not left since, key -> {x, y, reach}; `target`: the target
-- guided to last (kept when the guidance lets it go: the turn key's), `atSaid` its key when the
-- last line about it was that the player is at it. The guide whose line was the last said, until
-- a place, room, bend or the next piece ahead is said: the turn key turns to its target
-- (spokenGuide).
local spokenGuide = nil
local LINE_KINDS_SAID = { place = true, room = true, ahead = true, bend = true }
-- The lines that named what lies around since the player came into the place or room: its own
-- line (or the around key's), then the look-ahead and what came near; a target one of them named
-- is guided to without its name (logic.linesName)
local heardLines = {}
local HEARD_STARTS = { place = true, room = true, around = true }
local HEARD_ADDS = { ahead = true, near = true }
local bump = { ticks = 0, key = nil, free = 0, time = nil }
local stopSaid, stopOut = nil, 0 -- the stop last said, and how far the player walked off stops since
-- In a hall the game calls outdoors (Ironforge's, the Undercity's): yards walked since its floor
-- was last near; nil = not in such a hall
local hallGap = nil
-- The doorway just walked through {x, y}: not said again (it is a doorway on both sides) until the
-- player was once farther than the guidance reach from it (user 2026-09-29: "Ausgang, 6 Meter im
-- Nordosten" right after going out through it)
local passed = nil

-- The UI map the game puts the player on (in Ironforge's halls Ironforge's, on the mountain over
-- them Dun Morogh's; on the Ruins of Lordaeron the Undercity's, as in the city under them).
local function gameMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

-- The area the game says the player is in (the subzone; in a city's halls the hall's own).
local function gameSubzone()
    return GetSubZoneText and GetSubZoneText() or ""
end

-- In a hall the game calls outdoors (IsIndoors() is false in all of Ironforge's big halls and
-- almost all of the Undercity). Into the halls only on evidence (user 2026-10-07: the Undercity
-- under the Ruins of Lordaeron took over the rose walk by its floor in x and y alone): the zone's
-- floor piece the player is on (followed at its joins outdoors, as on the zeppelin tower) is one a
-- hall here lies on (logic.inHallFloor); the game's subzone is the area of a hall here
-- (logic.hallPieceForArea: after a login, a lift); or the game's map just became the halls' (a
-- gate). Inside, the halls' own floors and rooms take over; out of them through a doorway to
-- outside (updateIndoors), on another map, or after HALL_GAP yards without hall floor near (a
-- bridge, over lava). After a doorway out, no way back in until DOOR_AWAY yards from it.
local HERE_SAME = 1.5 -- yd from the kept spot (keepHere) that still count as the same
local hereRestored = false -- the kept spot was looked at after loading (restoreHere)
local hereKept = nil
local hereTable = nil -- the table keepHere writes the spot into (one per session, filled anew at each write)
local DOOR_AWAY = 4.0 -- yd from the doorway left by before the halls can take the player again
local hallMapWas = nil      -- the game's map at the last look
local hallMapWalked = nil   -- yd walked since it became the halls' (nil: not just now)
local hallDoorOut = nil     -- {x, y}: the doorway the player just came out of the halls by
local hallEntryFloor = nil  -- the halls layer's floor piece the player came in on (kept over forgetPlace)

local function updateHall(z, x, y, px, py)
    local uiMap = gameMap()
    -- the game's area at this look (the halls' rooms are checked against it: logic.onFloorRooms)
    z._index.gameArea = gameSubzone()
    if hallMapWas ~= nil and uiMap ~= hallMapWas and logic.isHallMap(z, uiMap) then
        hallMapWalked = 0
    elseif hallMapWalked and px then
        hallMapWalked = hallMapWalked + logic.dist(x, y, px, py)
        if hallMapWalked > HALL_GAP then
            hallMapWalked = nil
        end
    end
    hallMapWas = uiMap
    if not logic.isHallMap(z, uiMap) then
        hallGap, hallMapWalked, hallDoorOut = nil, nil, nil
        return false
    end
    if hallDoorOut and logic.dist(hallDoorOut[1], hallDoorOut[2], x, y) > DOOR_AWAY then
        hallDoorOut = nil
    end
    if hallGap ~= nil then
        -- in the halls: until no hall floor is near for HALL_GAP yd
        if logic.inHall(z, x, y, uiMap, room) then
            hallGap = 0
        elseif px then
            hallGap = hallGap + logic.dist(x, y, px, py)
            if hallGap > HALL_GAP then
                hallGap = nil
            end
        end
        return hallGap ~= nil
    end
    if hallDoorOut then
        return false
    end
    -- after a reload or login on the spot of the last look, in the halls as then (restoreHere takes the
    -- room and the floor pieces back): swimming in a canal right after a login nothing else told it,
    -- 12 s of "place unknown" (walk 2026-10-12 10:59)
    local kept = not hereRestored and WowVisionDB and WowVisionDB.surroundingsHere
    if type(kept) == "table" and kept.halls and kept.zone == z.key and logic.dist(kept.x, kept.y, x, y) <= HERE_SAME then
        hallGap = 0
        return true
    end
    local piece = logic.hallPieceForArea(z, x, y, uiMap, z._index.gameArea, z._index.floor or 0)
    if piece then
        logic.setFloor(z, piece)
    end
    local inFloor, hallRoom = logic.inHallFloor(z, x, y, uiMap, z._index.floor or 0, hallMapWalked ~= nil, z._index.gameArea)
    -- the height the zone's floor is followed at: into the halls only where their layer has a floor at it, and onto
    -- that floor (walk 2026-10-22 11:31:37, STATE bug 68: a step before the Ruins' bell tower doorway the tower's room
    -- box took the player in where the halls' layer has only the canal ring 124 yd below; the layer started on the
    -- ring, the ring's room lies apart from the tower and the next look put the player out again, a place said twice)
    local layer = logic.layer(z, IsIndoors())
    local heldZ = inFloor and layer and logic.tracker and logic.tracker.heldZ(z)
    local atHeight = heldZ and logic.tracker.pieceAt(layer, x, y, heldZ, HALL_ENTRY_DZ)
    if atHeight == false then
        inFloor = false
    end
    if inFloor then
        -- the room whose floor let the player in is the room they are in (not one found by x and y
        -- at another height; an older room held from before is forgotten), and the halls layer's
        -- floor is that room's (logic.roomPieceHere: the rooms are found by the floor), or the one at the height
        -- held where that room's piece lies at another
        hallGap, room, roomByDoor = 0, hallRoom, false
        local piece = layer and logic.roomPieceHere(layer, hallRoom, x, y)
        if atHeight and (piece == nil or not logic.tracker.pieceAt(layer, x, y, heldZ, HALL_ENTRY_DZ, piece)) then
            piece = atHeight
        end
        if piece then
            logic.setFloor(layer, piece)
        end
        hallEntryFloor = piece
        return true
    end
    return false
end

-- Indoors: as the game says, or in one of the halls it calls outdoors (as of the last look).
local function isInside()
    return IsIndoors() or hallGap ~= nil
end

-- The grid the player's floor is held in: the layer inside (a building, a city's halls), else the zone; nil with no
-- zone data.
local function heldGrid()
    return zone and zone._index and (isInside() and logic.layer(zone, IsIndoors()) or zone) or nil
end

-- The floor piece held on that grid (0 the ground; nil with no zone data).
local function heldFloor()
    local g = heldGrid()
    return g and (g._index.floor or 0) or nil
end

-- How far from a guidance target it stays the target (its own reach, a way out's, else the guidance's).
local function targetReach(t)
    return t.reach or (t.kind == "exit" and logic.EXIT_REACH) or logic.GUIDE_REACH
end

-- Forget the place on the ways (outdoors, or the indoor layer's): stepping between a room and the
-- indoor layer says the new one at once.
local function forgetWays()
    outdoor:reset()
    indoor:reset()
    region, saidMouths, saidLabels = nil, {}, {}
    bendFrom, leftWay, wayNamed = nil, nil, nil
    aheadSaid = {}
end

-- Forget where the player was: after a flight, in a new zone, on going in or out of a building.
-- The place or room there is then said at once.
local function forgetPlace()
    forgetWays()
    heardLines = {}
    room, lastRoom, roomByDoor = nil, nil, false
    if zone then
        logic.setFloor(zone, 0)
        local layer = logic.layer(zone)
        if layer then
            logic.setFloor(layer, 0)
        end
        if zone._index and zone._index.layerIn then
            logic.setFloor(zone._index.layerIn, 0)
        end
    end
    warnedEdges = {}
    layerMode = false
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
    -- onto a ramp or stairs: at once, so a short flight is heard while one is on it (the Temple of the Moon's way up,
    -- flights of 3 yd: stepped onto and off before its line came, walk 2026-11-04 08:39:31, bug 165); back onto the
    -- flight just left only after a few yards (the floor at a stair's foot flips)
    if logic.CLIMBS[there] and key ~= outdoor.current then
        return key == leftClimb and ENTRY_NARROW or 0
    end
    if logic.NARROW[logic.kind(zone, logic.keyPlace(key))] then
        return ENTRY_NARROW
    end
end

-- The walk log (/wv surr log on): every announcement with what `/wv surr` would say there, plus a
-- position trail, kept in WowVisionDump.surroundings, so walks can be compared with the data
-- offline after a /reload or logout (the walklog tools of wv-surroundings). Off until switched
-- on, then on until switched off.
-- (a trail point every 2 yd: at 4 the replays walked straight past the steps around a door,
-- 2026-10-08)
local LOG_MAX, TRAIL_MAX, TRAIL_STEP = 3000, 20000, 2
local trailX, trailY = nil, nil
-- the game's area (its subzone) at the last trail point that gave it, and the points since: a trail
-- point gives it ("|<area>" at its end, "|" for none) when it changes and every TRAIL_AREA_EVERY points
-- (a reduced walk set keeps it), so the replays hand the module what the game said (user 2026-10-17)
local TRAIL_AREA_EVERY = 20
local trailArea, trailSince = nil, 0
-- the game's UI map at the last trail point that gave it ("m<map>" among the flags, with the area): the replays had
-- one map per zone, while the halls are left and entered by the map (the Undercity's lifts, Ironforge's gate), 2026-10-22
local trailMap = nil
local sessionLogged = false

-- The game version the log was walked in ("2.5.6.70006", GetBuildInfo's version and build): the offline tools refuse a
-- log of another version than the one they work on (wv-surroundings tools/clients.lua; user 2026-10-24: logs of one
-- game version must never be taken for another's). Each game client keeps its own saved variables, so one label
-- per log; written whenever the log is switched on and at every login while it is on.
local function gameVersion()
    local version, build = GetBuildInfo()
    return version and (version .. "." .. tostring(build)) or nil
end

local function logStore()
    WowVisionDump = WowVisionDump or {}
    if type(WowVisionDump.surroundings) ~= "table" then
        WowVisionDump.surroundings = { entries = {}, trail = {} }
    end
    WowVisionDump.surroundings.client = gameVersion()
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

-- One log entry: {date, kind ("place", "room", "edge", "bump", "session", "zone", "surr", "floor"
-- for a change of the floor piece, "turn" for a press of the turn key, ...),
-- text}, where the player was (the data's cell and its text, the room candidates indoors, the
-- floor piece the player was on) and the facing in degrees (0 = north, counter-clockwise).
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
        -- the game's own area (its subzone), what makes a hall here certain (hallPieceForArea)
        local sub = gameSubzone()
        e.subzone = sub ~= "" and sub or nil
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
    -- the floor piece the player is on (0 the ground), in the hall layer they are in or outdoors
    local held = heldGrid()
    if held and (held._index.floor or 0) ~= 0 then
        e.floor = held._index.floor
    end
    if held and held ~= zone then
        e.layerKey = held.key
    end
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    table.insert(log.entries, e)
    log.entries = trim(log.entries, LOG_MAX)
end

-- A trail point every few yards: "time x y", plus i (indoors), h (in a hall the game calls
-- outdoors), s (swimming), g (ghost), a (in the air: falling or jumping), f with the facing in degrees and p with the floor piece
-- when it is not the ground, and m with the game's UI map where it or the area is given, as one token
-- ("isf270p33m1458"); then "|<area>", the game's area, where it changed or every TRAIL_AREA_EVERY points (after
-- a space: tools read the flags before it).
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
    -- p with the floor piece the player is on when it is not the ground ("if270p33")
    local held = heldGrid()
    local piece = held and held._index.floor or 0
    local flags = (IsIndoors() and "i" or "") .. (hallGap and "h" or "") .. (IsSwimming() and "s" or "")
        .. (UnitIsGhost("player") and "g" or "") .. (IsFalling() and "a" or "")
        .. (facing and ("f" .. facing) or "")
        .. (piece ~= 0 and ("p" .. piece) or "")
    local area = gameSubzone()
    local uiMap = gameMap()
    trailSince = trailSince + 1
    local tail = ""
    if area ~= trailArea or uiMap ~= trailMap or trailSince >= TRAIL_AREA_EVERY then
        tail, trailArea, trailMap, trailSince = " |" .. area, area, uiMap, 0
        if uiMap then
            flags = flags .. "m" .. uiMap
        end
    end
    table.insert(log.trail, string.format("%d %.1f %.1f%s%s", time(), x, y, flags ~= "" and " " .. flags or "", tail))
    log.trail = trim(log.trail, TRAIL_MAX)
end

-- Falls, for the walk log (walk review 2026-10-20c: x and y cannot tell a flight from the floor under it; how long the
-- player was in the air can). Every stretch the game has the player in the air (IsFalling, the signal WowVision's fall
-- sounds use) from its first frame to the landing, as one line of the log's falls: "<landing time> <seconds> <x y at
-- the start> <x y at the landing> <flags>", flags j (the jump key started it: pressed within FALL_JUMP_GRACE before, as
-- the fall sounds tell a hop), w (water: swimming at its start or landing, or out of the water within FALL_JUMP_GRACE),
-- s (a slow-fall effect on the player), p with the floor piece held at its start. Looked at every frame (the looks come
-- every CHECK_INTERVAL, too coarse for the 0.2 s of a step); only while the log is on. Nothing reads it in the game:
-- the tools measure first how falls fit the drops (steps 0.2 to 0.4 s, 2026-10-05), before the tracker may use them.
local FALLS_MAX, FALL_JUMP_GRACE = 5000, 0.8
-- Slow Fall, Levitate, Noggenfogger's slow fall, the parachute cloak's: spell ids as in Classic (not checked on Forever)
local SLOW_FALLS = { 130, 1706, 16593, 12438 }
local fall = nil          -- the fall under way: start time, x, y, flags so far
local lastJumpKey, lastSwimAt = -math.huge, -math.huge
hooksecurefunc("JumpOrAscendStart", function()
    lastJumpKey = GetTime()
end)

local function slowFalling()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if get == nil then
        return false
    end
    for _, id in ipairs(SLOW_FALLS) do
        local ok, aura = pcall(get, id)
        if ok and aura ~= nil then
            return true
        end
    end
    return false
end

local function watchFall(now)
    local swimming = IsSwimming()
    if swimming then
        lastSwimAt = now
    end
    local inAir = IsFalling()
    if inAir and fall == nil then
        local log = activeLog()
        if log == nil then
            return
        end
        local x, y = UnitPosition("player")
        if x == nil then
            return
        end
        local held = heldGrid()
        fall = {
            t = now, x = x, y = y, piece = held and held._index.floor or 0,
            jump = now - lastJumpKey <= FALL_JUMP_GRACE,
            water = swimming or now - lastSwimAt <= FALL_JUMP_GRACE,
            slow = slowFalling(),
        }
    elseif inAir and fall then
        fall.slow = fall.slow or slowFalling()
    elseif not inAir and fall then
        local f = fall
        fall = nil
        local log = activeLog()
        local x, y = UnitPosition("player")
        if log == nil or x == nil then
            return
        end
        local flags = (f.jump and "j" or "") .. ((f.water or swimming) and "w" or "") .. (f.slow and "s" or "")
            .. "p" .. f.piece
        log.falls = log.falls or {}
        table.insert(log.falls, string.format("%d %.2f %.1f %.1f %.1f %.1f %s", time(), now - f.t, f.x, f.y, x, y, flags))
        log.falls = trim(log.falls, FALLS_MAX)
    end
end

-- Boarding, for the walk log (user 2026-10-21: what matters first is knowing that the player stands where the
-- platform should be and is not falling, a sign to stop moving; knowing they ride a ship is a small extra). Ships,
-- zeppelins and lifts move and are in no surroundings data, so the tracker sees water or air under a deck. Near a
-- stop's vehicle (BOARD_NEAR yd from where it stands: a ship's or zeppelin's 24 yd along its heading, a lift's shaft
-- axis) a point every BOARD_STEP s goes into the log's boards: "<time> <stop> <yd to the vehicle> <x y> <flags>",
-- flags a (in the air), s (swimming), m (moving on their own: IsPlayerMoving), c (carried: the position moved since
-- the last point while the player was not moving on their own, now or then, and not in the air). Anywhere a carried
-- stretch (a ship at sea) goes into the log's carried as one line when it ends: "<end time> <seconds> <yards> <x y at
-- the start> <x y at the end> <stop near its start or ->". The game gives no height: a lift's ride shows only as
-- standing on its axis without falling. Only while the log is on; nothing reads it in the game: the tools measure
-- first how the signals fit the stops.
local BOARD_NEAR, BOARD_STEP, BOARDS_MAX, CARRIED_MAX = 30, 0.5, 5000, 2000
local CARRY_MIN, CARRY_JUMP, CARRY_END = 0.3, 40, 1.5   -- yd per step at least, more is a teleport; s to end a stretch
local boardAt, boardX, boardY, boardMoving = -math.huge, nil, nil, false
local carry = nil          -- the carried stretch under way: start time, x, y, stop near it, yards, last carried time, x, y

local function endCarry(log)
    local c = carry
    carry = nil
    log.carried = log.carried or {}
    table.insert(log.carried, string.format("%d %.1f %.1f %.1f %.1f %.1f %.1f %s", time(), c.lastT - c.t, c.yd,
        c.x, c.y, c.lx, c.ly, c.stop or "-"))
    log.carried = trim(log.carried, CARRIED_MAX)
end

local function watchBoard(now)
    if now - boardAt < BOARD_STEP then
        return
    end
    boardAt = now
    local log = activeLog()
    local x, y = UnitPosition("player")
    if log == nil or x == nil or UnitOnTaxi("player") then
        carry, boardX = nil, nil
        return
    end
    local moving, inAir = IsPlayerMoving() == true, IsFalling() == true
    local moved = boardX and math.sqrt(logic.dist2(x, y, boardX, boardY)) or 0
    local carried = boardX ~= nil and not moving and not boardMoving and not inAir
        and moved >= CARRY_MIN and moved <= CARRY_JUMP
    local stop, d = nil, nil
    if zone and zone._index then
        stop, d = logic.nearestStop(zone, x, y)
    end
    local nearStop = stop ~= nil and d <= BOARD_NEAR
    if carried then
        if carry == nil then
            carry = { t = now - BOARD_STEP, x = boardX, y = boardY, yd = 0, stop = nearStop and stop or nil }
        end
        carry.yd = carry.yd + moved
        carry.lastT, carry.lx, carry.ly = now, x, y
    elseif carry and (moved > CARRY_JUMP or now - carry.lastT >= CARRY_END) then
        endCarry(log)
    end
    boardX, boardY, boardMoving = x, y, moving
    if nearStop then
        local flags = (inAir and "a" or "") .. (IsSwimming() and "s" or "") .. (moving and "m" or "")
            .. (carried and "c" or "")
        log.boards = log.boards or {}
        table.insert(log.boards, string.format("%d %d %.1f %.1f %.1f%s", time(), stop, d, x, y,
            flags ~= "" and " " .. flags or ""))
        log.boards = trim(log.boards, BOARDS_MAX)
    end
end

-- The walk-graph tracker's cost, one silent log entry (kind "time") a minute while the log is on: the looks
-- of the minute, their milliseconds in all and the slowest one, the most candidates kept and surfaces under
-- the position after one look, the looks that ended unsure (the Lua time per look in the game was
-- unmeasured, 2026-10-19; the user's next walk brings the numbers, no sighted check).
local TIMING_EVERY = 60
local timingAt = nil

local function logTiming(x, y)
    local tracker = logic.tracker
    if tracker == nil or activeLog() == nil then
        return
    end
    local now = GetTime()
    if timingAt == nil then
        timingAt = now
        tracker.takeStats()
        return
    end
    if now - timingAt < TIMING_EVERY then
        return
    end
    timingAt = now
    local s = tracker.takeStats()
    if s.looks == 0 then
        return
    end
    logEntry("time", string.format("%d looks, %.1f ms in all, %.2f ms the slowest, %d candidates and %d surfaces at most, %d unsure, %d in holes",
        s.looks, s.ms, s.maxMs, s.maxCands, s.maxUnder, s.unsure, s.holes or 0), x, y)
end

-- The data registers here as it loads (its data.xml comes after this folder in camelot/modules.xml):
-- a zone file its frame and its JSON text (decoded only while the player is in the zone: store.lua),
-- a places list file its table (placesUi.lua). The files call addZone and addPlaces on the addon's
-- own table, the second value every file of WowVision gets.
local _, namespace = ...
local data = WowVision.surroundingsData or { zones = {}, places = {} }
WowVision.surroundingsData = data
if namespace then
    function namespace.addZone(header, json)
        header.json = json
        table.insert(data.zones, header)
    end
    function namespace.addPlaces(places)
        table.insert(data.places, places)
    end
    -- the walk graph's surfaces per layer (format 5, zones/<zone>-surfaces.lua): the walk-graph tracker's data;
    -- a packed layer's rows are unpacked band by band as the tracker reads them (store.lua logic.bandRows)
    function namespace.addSurfaces(key, layers)
        for _, layer in pairs(layers) do
            if layer.bands then
                logic.bandRows(layer)
            end
        end
        data.surfaces = data.surfaces or {}
        data.surfaces[key] = layers
    end
end
-- the game decodes a zone's JSON text (offline the tools put a stand-in in its place)
logic.decodeJson = function(text)
    return C_EncodingUtil.DeserializeJSON(text)
end
-- and unpacks the packed data (WowVision tools/surroundings-pack.py: zlib, then Base64)
logic.inflate = function(packed)
    local raw = C_EncodingUtil.DecodeBase64(packed)
    return raw and C_EncodingUtil.DecompressString(raw, Enum.CompressionMethod.Zlib)
end

local function zones()
    return data.zones
end

-- The data format this module reads (zone.format, logic.FORMAT). Data of another format is left
-- alone, and said once: the data and WowVision are updated together.
local formatWarned = false
local function formatFits(z)
    if (z.format or 1) == logic.FORMAT then
        return true
    end
    if not formatWarned then
        formatWarned = true
        WowVision:speak(string.format("Surroundings data %s has format %d, this WowVision reads format %d; "
            .. "update the data and WowVision together", z.key or "?", z.format or 1, logic.FORMAT))
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
        -- (the unpack's milliseconds and the game's Lua memory after it, in the walk log's zone line: what an entry
        -- costs in the game, 2026-10-30)
        local ms
        if found then
            -- (debugprofilestop is the game's millisecond clock; the walk replays run without it)
            local clock = debugprofilestop or function() return os.clock() * 1000 end
            local t0 = clock()
            logic.unpack(found, GetLocale())
            logic.dropLists(found)
            ms = clock() - t0
        end
        zone = found
        if found then
            logEntry("zone", found.label or found.key, x, y,
                { unpackMs = round1(ms), luaMB = round1(collectgarbage("count") / 1024) })
        end
        forgetPlace()
        -- the targets and stops are numbered per zone
        guide.key, guide.named, waterGuide.key, waterGuide.named = nil, nil, nil, nil
        stopSaid, stopOut = nil, 0
    end
    return zone
end

-- What may cut what (user 2026-10-15): a new place or room (and the around key) throws away the
-- lines of ours still waiting and cuts ours playing, except a drop warning, which is let finish
-- (the place then waits for it); everything else, drop warnings too, waits its turn and cuts
-- nothing; a drop warning still waiting goes with the rest. Lines are tagged in WowVision's speech
-- queue (retail/speech.lua): other speech there is neither dropped nor cut.
local CUTS = { place = true, room = true, around = true }

local function speakLine(text, kind)
    local speech = WowVision.base.speech
    if not (speech and speech.withTag) then
        module:fireAlert("place", { text = text })
        return
    end
    if CUTS[kind] then
        speech:dropQueued(module)
        local current = speech.current
        if current and current.tag and current.tag.owner == module and current.tag.kind ~= "edge" then
            C_VoiceChat.StopSpeakingText()
        end
    end
    speech:withTag({ owner = module, kind = kind }, function()
        module:fireAlert("place", { text = text })
    end)
end

local helperArrival -- (below: ends the helper's route on a place or room line)

local function say(text, kind, x, y, walked, extra)
    local raw = text
    text = logic.finishText(text)
    if zone then
        text = logic.spokenText(zone, text)
    end
    if text and text ~= "" then
        speakLine(text, kind)
    else
        -- nothing to say (the next piece of the same way, no direction): logged, but nothing heard changes: the
        -- names of the last line, the turn key's target and the helper's route stay (bug 32, review 2026-10-29)
        extra = extra or {}
        extra.walked = walked and round1(walked) or nil
        logEntry(kind, text, x, y, extra)
        return
    end
    if HEARD_STARTS[kind] then
        heardLines = { raw }
    elseif HEARD_ADDS[kind] then
        heardLines[#heardLines + 1] = raw
    end
    extra = extra or {}
    extra.walked = walked and round1(walked) or nil
    logEntry(kind, text, x, y, extra)
    if LINE_KINDS_SAID[kind] then
        spokenGuide = nil
    end
    if (kind == "place" or kind == "room") and helperArrival then
        helperArrival()
    end
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
-- has turned (GUIDE_TURN degrees off the last said one, after GUIDE_REPEAT, and the last said
-- one would pass it more than GUIDE_MISS beside it or lie behind), and once at it. The
-- name and the way through only until another target is named: then "entrance, 6 to the north".
-- `brief` (a beacon leads): only that the target is there and its name, once.
-- A target said: remembered until the player is GUIDE_FORGET beyond its reach (forgetLeft), and
-- the turn key's target.
local function noteSaid(g, t)
    g.said[t.key] = { x = t.x, y = t.y, reach = targetReach(t) }
    spokenGuide = g
end

local function forgetLeft(g, x, y)
    for key, s in pairs(g.said) do
        if logic.dist2(x, y, s.x, s.y) > (s.reach + GUIDE_FORGET) ^ 2 then
            g.said[key] = nil
        end
    end
end

local function guideTo(z, g, t, x, y, brief)
    local now = GetTime()
    -- where the target is and from how far it is guided to (checkGuide keeps it while within reach)
    g.x, g.y, g.reach = t.x, t.y, t.reach
    if brief then
        if g.key ~= t.key then
            say(t.name, t.kind, x, y)
            g.key, g.dir, g.at, g.time, g.named = t.key, t.dir, false, now, t.key
            -- the target just named is the one the turn key and Alt-I take (review 2026-10-29: they took the one
            -- named before the beacon started)
            g.target, g.zone = t, z
            noteSaid(g, t)
        end
        return
    end
    local named = g.named ~= t.key
    -- named by the line of the place the player is in (a square's opening, a fork's arm, a room's
    -- doorway): said without its name
    local bare = logic.linesName(z, heardLines, t.name)
        or (t.label ~= nil and t.label ~= t.name and logic.linesName(z, heardLines, t.label))
    g.target, g.zone = t, z
    if logic.atTarget(z, t, x, y) then
        if not (g.key == t.key and g.at) then
            -- already on the climb's own piece (stepped onto it by its line at the foot): its place line says the
            -- way on a moment later, and "weiter auf 3" right before it was noise (user 2026-10-18 08:37)
            local ixz = z._index
            local onIt = t.kind == "climb" and ixz.lineFloors ~= nil and ixz.lineFloors[ixz.floor or 0]
                and logic.placeOf(logic.valueAt(z, x, y)) == logic.placeOf(t.value)
            if not onIt then
                say(logic.guideText(z, t, named, true, bare), t.kind, x, y)
            end
            g.key, g.dir, g.at, g.time, g.named, g.quiet = t.key, t.dir, true, now, t.key, false
            noteSaid(g, t)
            g.atSaid = t.key
        end
        return
    end
    -- said before and not left since: back in reach, or nearest again, it goes on quietly
    local s = g.key ~= t.key and g.said[t.key]
    if s and logic.dist2(s.x, s.y, t.x, t.y) <= 1 then
        g.key, g.dir, g.at, g.time, g.atSaid, g.quiet = t.key, t.dir, false, now, nil, false
        return
    end
    -- heading for it: nothing until the player heads elsewhere, or is at it (user 2026-10-16:
    -- said only when on the wrong way)
    local facing = GetPlayerFacing()
    if facing and logic.headsFor(t, x, y, logic.bearingOf(math.cos(facing), math.sin(facing))) then
        if g.key ~= t.key then
            g.key, g.dir, g.at, g.time, g.atSaid, g.quiet = t.key, t.dir, false, now, nil, true
        end
        return
    end
    local turned = g.dir ~= t.dir and logic.angleOff(t.x - x, t.y - y, g.dir or t.dir) > GUIDE_TURN
    if turned and g.dir then
        local vx, vy = logic.compassVector(g.dir)
        local along = (t.x - x) * vx + (t.y - y) * vy
        turned = along < 0 or math.abs((t.x - x) * vy - (t.y - y) * vx) > GUIDE_MISS
    end
    if g.key ~= t.key or g.quiet or (turned and now - g.time >= GUIDE_REPEAT) or (g.at and t.d > logic.GUIDE_AT + GUIDE_AWAY) then
        say(logic.guideText(z, t, named, false, bare), t.kind, x, y)
        g.key, g.dir, g.at, g.time, g.named, g.quiet = t.key, t.dir, false, now, t.key, false
        noteSaid(g, t)
        g.atSaid = nil
    end
end

local function checkGuide(z, x, y, roomId, skipDoor, climbZone)
    if not module.settings.guidance then
        guide.key = nil
        -- guidance off: the turn key no longer aims at the target last said
        if spokenGuide == guide then
            spokenGuide = nil
        end
        return
    end
    forgetLeft(guide, x, y)
    -- a beacon starting or ending: the nearest target is said anew in the other manner, by name
    local brief = beaconGuides()
    if brief ~= guide.brief then
        guide.brief, guide.key, guide.named, guide.said = brief, nil, nil, {}
    end
    logic.wallSide = module.settings.wallSide == true
    -- in a big room: its doorways and the climb ends on the player's floor; on foot elsewhere: entrances, street
    -- beginnings and climb ends
    local prefer = guide.key and guide.x and { x = guide.x, y = guide.y } or nil
    local function lookup(reach)
        if roomId then
            return logic.roomTarget(z, roomId, x, y, skipDoor, prefer, reach, climbZone)
        end
        return logic.footTarget(z, x, y, region, prefer, reach)
    end
    local t = lookup()
    -- the target guided to stays guided while the player is within its reach and GUIDE_AWAY
    -- (until 2026-10-03 it was kept there silently: backing off the chapel's door in Deathknell
    -- beyond its reach and strafing along its front crossed the doorway's lane without a word,
    -- the user's walk 13:49)
    if t == nil and prefer and guide.reach
        and logic.dist2(x, y, guide.x, guide.y) <= (guide.reach + GUIDE_AWAY) ^ 2 then
        t = lookup(guide.reach + GUIDE_AWAY)
        if t and logic.samePoint(t, prefer) then
            t.reach = guide.reach
        else
            t = nil
        end
    end
    -- not the beginning of the way the player is on (stepping out of a street onto its square), nor
    -- of the way under the player's feet before the step onto it counts (user's walk 2026-10-03
    -- 08:06: stepped onto the stairs beside the landing, "stairs, 7 to the southeast" came)
    if t and t.kind == "way" then
        local here = logic.valueAt(z, x, y)
        local onIt = here and here ~= 0 and logic.place(z, logic.placeOf(here))
        local name = t.label or t.name
        if (logic.isWayKey(outdoor.current) and logic.keyLabel(z, outdoor.current) == name)
            or (onIt and onIt.label == name) then
            t = nil
        end
    end
    -- not the foot of a climb the player is past (going up it), nor of the one the player stands on;
    -- back down at that foot its "up to the west" is said again (a second try at the griffon ramp)
    -- (a climb found for a room on the halls layer is checked, said and guided on that layer: t.zone)
    local tz = t and t.zone or z
    if t and t.kind == "climb" then
        if logic.onClimb(tz, t, x, y, outdoor.current) then
            if guide.key == t.key then
                guide.at = false
            end
            t = nil
        elseif logic.pastTarget(tz, t, x, y) then
            t = nil
        end
    end
    -- up a flight with a wall along one side and a drop along the other: its way up toward the
    -- wall side (setting wallSide), not while a beacon leads; coming off its foot, whose way on
    -- said that direction already, it is said only once it turns
    if t == nil and not roomId and not brief then
        local facing = GetPlayerFacing()
        t = logic.aimTarget(z, x, y, facing and logic.bearingOf(math.cos(facing), math.sin(facing)))
        if t and guide.key ~= t.key and guide.through and logic.sameDir(guide.through, t.dir) then
            guide.key, guide.dir, guide.at, guide.time, guide.named = t.key, t.dir, false, GetTime(), t.key
            guide.x, guide.y, guide.reach, guide.through = t.x, t.y, t.reach, nil
            return
        end
    end
    if t and t.kind == "climb" then
        guide.through = t.through
    elseif t and t.kind ~= "aim" then
        guide.through = nil
    end
    -- the doorway just walked through stays quiet (said again as new once the player left it)
    if t == nil or (passed and logic.dist2(t.x, t.y, passed.x, passed.y) <= PASSED_SAME ^ 2) then
        -- a target that drops out while the player is still within its reach and GUIDE_AWAY is
        -- kept, so its return is no new target: on the stairs beside the Trade District's
        -- terrace the cells flip between stairs and square and a street beginning was said
        -- three times in three seconds, and at the edge of an entrance's reach every step back
        -- in said it again (user 2026-10-02)
        if t == nil and guide.key and guide.reach
            and logic.dist2(x, y, guide.x, guide.y) <= (guide.reach + GUIDE_AWAY) ^ 2 then
            return
        end
        guide.key = nil
        return
    end
    guideTo(tz, guide, t, x, y, brief)
end

-- Down in a moat? The place here on the floor piece the player is on (updateFloor: in once fallen
-- or stepped in or come down its stairs, out once up its way out) is one; returns its value then
-- (user 2026-10-02: no rule of the moat's own, the moat's let the player out within 4 yd of its
-- stairs while still down in the trench).
local function downHere(layer, x, y)
    local v = logic.valueAt(layer, x, y)
    if v and v ~= 0 and logic.kind(layer, logic.placeOf(v)) == "moat" then
        return v
    end
    return nil
end

-- The swimming state for the floor model (logic.updateFloor): true swimming, false on foot, nil
-- in the air (jumping out of the water or falling into it: decided on landing).
local function swimState()
    if IsFalling() then
        return nil
    end
    return IsSwimming() and true or false
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

-- Stepped off a way (a ramp or stairs too) onto a square at (fx, fy): the beginning of that way
-- the player came out of stays quiet, as a doorway walked through does, until the player is beyond
-- its guidance reach (the lane through Stormwind's gate is guided to from 17 yd; user 2026-09-30).
-- The one of its name nearest to where it was left: on the landing by the auction house two
-- stairs begin 13 yd apart, and the one come up by was guided back to (user's walk 2026-10-03).
local function notePassedBeginning(z, fx, fy, square, wayKey)
    local label, best, bd = logic.keyLabel(z, wayKey), nil, nil
    for _, b in ipairs(logic.wayBeginnings(z, square)) do
        local d = logic.dist(b.x, b.y, fx, fy)
        if b.label == label and d <= logic.beginningReach(logic.GUIDE_REACH, b) and (bd == nil or d < bd) then
            best, bd = b, d
        end
    end
    if best then
        passed = { x = best.x, y = best.y, reach = logic.beginningReach(logic.GUIDE_REACH, best) }
    end
end

-- The floor piece of `grid` the sill of the doorway at (x, y) lies on: the doorway nearest within PASSED_REACH
-- (the one just walked through), its piece of that grid (doorFloors); nil where none is near or its sill lies on
-- the ground. Stepping in or out starts the grid entered on it: a door onto a raised floor over walkable ground
-- (a balcony, a wall walk, a building's upper door) held the ground, and the raised floor's drops went unwarned
-- (review 2026-10-29: RULES' "the outside sill takes the player onto its piece" lived in the piece tracker of before
-- only).
local function sillFloor(grid, x, y)
    local best, floor = PASSED_REACH ^ 2, nil
    for _, door in ipairs(grid._index.doors or {}) do
        local dx, dy = logic.doorWorld(grid, door)
        if dx then
            local d = logic.dist2(dx, dy, x, y)
            if d <= best then
                best, floor = d, door.floor
            end
        end
    end
    return floor
end

-- The grid entered through a doorway starts on the floor its sill lies on, where there is one.
local function startOnSill(grid, x, y)
    local sill = grid and sillFloor(grid, x, y)
    if sill then
        logic.setFloor(grid, sill)
    end
end

-- Forget the doorway or beginning passed once the player was farther than its guidance reach.
local function updatePassed(x, y)
    if passed and logic.dist2(x, y, passed.x, passed.y) > passed.reach ^ 2 then
        passed = nil
    end
end

-- Guidance to the nearest way out of the floor piece the player is on (a liquid's, the moat's;
-- `down`: the moat's place value, naming it), when there is one.
local function guideExit(z, x, y, down)
    local t = module.settings.guidance and logic.exitTarget(z, x, y, z._index.floor, down)
    forgetLeft(waterGuide, x, y)
    waterGuide.out = nil
    if t then
        guideTo(z, waterGuide, t, x, y)
    else
        waterGuide.key = nil
    end
end

-- Out of the water: the way out guided to stays the target while the player is within WATER_KEEP
-- of where they stood up, so swimming on from there is no new target (where the water is about as
-- deep as one stands, the game's swimming flag flips from step to step: the way out was said
-- again at every flip, the Trade Quarter's canal); farther away it is forgotten.
local function leftWater(x, y)
    if waterGuide.key == nil then
        return
    end
    local o = waterGuide.out
    if o == nil then
        waterGuide.out = { x = x, y = y }
    elseif logic.dist2(x, y, o.x, o.y) > WATER_KEEP ^ 2 then
        waterGuide.key, waterGuide.out = nil, nil
    end
end

-- Is the player pushing against something (the wall detection's "blocked", fresh)? The position only jitters
-- then: no way of moving to look ahead along (checkEdges).
local function pushing()
    local walls = WowVision.base.navigation.walls
    return walls ~= nil and walls.severity == 1 and GetTime() - (walls.severityAt or 0) <= BUMP_FRESH
end

-- Drop edges: the one within reach ahead in the view first, else one in the path with its
-- distance. An edge warns again after the player is out of its reach and it is no longer in the
-- path; an edge warns only on the floor piece its floor belongs to (a wall-walk's or a deck's
-- only while the player is up there, a landing's only on the landing). Indoors (the indoor
-- layer's edges) `rooms` is the set of rooms the player may be in: an edge inside warns only in
-- the room its floor belongs to (its piece).
local function checkEdges(z, x, y, px, py, rooms)
    if rooms == nil then
        local before = z._index.floor or 0
        local floor, changed = logic.updateFloor(z, x, y, swimState())
        if changed then
            -- (the places found so far are kept per floor piece: logic.regionCache)
            z._index.floorBefore = before
            logic.noteClimbStep(z, x, y)
            logEntry("floor", before .. " -> " .. floor, x, y)
        end
    end
    -- the way the player moves (not the facing: strafing and walking back count too); none while
    -- pushing against something (the position only jitters there)
    local vx, vy = nil, nil
    local moved = px and logic.dist(x, y, px, py) or 0
    if moved >= MOVE_MIN and not pushing() then
        vx, vy = (x - px) / moved, (y - py) / moved
    end
    local warned = warnedEdges[z] or {}
    warnedEdges[z] = warned
    local inPath = {}
    if vx then
        logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, rooms, nil, inPath)
        -- out of its path only while moving: standing still (or pushing against a wall) has no
        -- path, and an edge warned 10 yd ahead warned again at every step after a stop (pressed
        -- against a wall of the Trade Quarter's ring, "10 auf 3 Uhr, 12 tief" three times in 6 s,
        -- walk 2026-10-15 20:49)
        for i in pairs(warned) do
            if not inPath[i] and logic.edgeDistance(z, i, x, y) > EDGE_REACH + EDGE_REARM then
                warned[i] = nil
            end
        end
    end
    if not module.settings.dropEdges then
        return
    end
    local i = logic.nearestEdge(z, x, y, EDGE_REACH, rooms, GetPlayerFacing(), warned)
    local along, qx, qy = nil, nil, nil
    if i == nil and vx then
        i, along, qx, qy = logic.edgeAhead(z, x, y, vx, vy, EDGE_LOOK, rooms, warned, nil)
    end
    if i then
        local text = logic.edgeText(z, i, along, x, y, qx, qy)
        local now = GetTime()
        if text ~= lastEdgeText or now - edgeAt >= EDGE_REPEAT then
            say(text, "edge", x, y)
            lastEdgeText, edgeAt = text, now
        end
        warned[i] = true
    end
end

-- On the square: a street, water or square not said yet comes within the approach distance.
local function checkApproach(z, x, y)
    local here = logic.regionAt(z, x, y)
    if here and here ~= region and here.value == region.value then
        -- the same place found anew on another floor piece (a building's floors): what was
        -- said there stays said (the landing said its stairs "down here", then "down to the
        -- north" a second later). Kept by name over the whole visit, not only from the copy
        -- left: after falling into the Brill tavern's cellar the module went between two copies
        -- of the cellar, one without the stairs, and "stairs here" came again 3 s after the
        -- place line (walks 2026-10-04 19:10 and 23:19)
        local carried = {}
        for m in pairs(saidMouths) do
            if type(m) == "table" then
                saidLabels[tostring(m.label)] = true
            end
        end
        for _, m in ipairs(here.mouths) do
            if saidLabels[tostring(m.label)] then
                carried[m] = true
            end
        end
        region, saidMouths = here, carried
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
    -- indoors the room's objects, any room's while the room is unknown (stacked floors); outdoors the outdoor ones
    -- (not `isIndoors and room or 0`: with the room unknown that gave the outdoor objects)
    local objectRoom = 0
    if isIndoors then
        objectRoom = room
    end
    local o = logic.objectAhead(z, x, y, vx, vy, logic.BUMP_REACH, objectRoom)
    local text, key
    if o then
        text, key = o.name, o
    elseif isIndoors then
        text, key = L["wall"], "wall"
    else
        local owner, what = logic.wallOwner(z, x, y, vx, vy, WALL_REACH)
        if owner and what == "place" then
            text, key = string.format(z.ofTemplate or "%s of %s", L["wall"], owner), owner
        elseif owner then
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
    -- not on ramps and stairs: left and right only keep one from drifting on long ways (user
    -- 2026-10-04)
    if not logic.isWayKey(key) or facing == nil or logic.CLIMBS[logic.kind(z, logic.keyPlace(key))] then
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
-- Stepping onto that piece then says nothing more, also after a short next piece of the same way
-- on the way to it (a fork said ahead, a bit of street, the fork again: walk 2026-10-09 22:04),
-- and it is not said ahead again while the player stays near it (at the ramp's corner east of the
-- griffon street the next piece ahead took turns with each small step: the fork and the Canals'
-- street, six lines in 25 s, walk 2026-10-09 22:08); it is forgotten once the player is
-- AHEAD_FORGET yd farther from it than when it was said. Looked for along the way one MOVES, only while
-- moving: taken from the facing it spoke on every turn on the spot, a different piece each time
-- among the short lines at the griffon ramp's foot (nine lines in 50 s, user's walk 2026-09-30),
-- and it kept talking while a beacon led (then the beacon says where to go).
local function checkAhead(z, x, y, px, py)
    local key = outdoor.current
    if not logic.isWayKey(key) or px == nil or beaconGuides() then
        return
    end
    for k, a in pairs(aheadSaid) do
        if logic.dist2(x, y, a.x, a.y) > (a.d + AHEAD_FORGET) ^ 2 then
            aheadSaid[k] = nil
        end
    end
    if logic.dist(x, y, px, py) < MOVE_MIN then
        return
    end
    local heading = math.atan2(y - py, x - px)
    local value, yards, tx, ty = logic.pieceAhead(z, x, y, heading, key, logic.AHEAD_LOOK)
    if value == nil or yards < logic.AHEAD_MIN then
        return
    end
    local nextKey = logic.outdoorKey(z, value, key)
    if not aheadSaid[nextKey] then
        -- the next piece of this way: its direction only ("north to south"), as on stepping onto it;
        -- one with nothing to say is no piece said ahead (its own line then says it on stepping
        -- onto it: a stairs' line in a tower beside the canal walk had no direction to say)
        local text, named
        if logic.sameWay(value, key, wayNamed, z) then
            text = logic.directionText(z, value)
        else
            text = logic.describe(z, value, true, nil, nil, logic.ownerOfPlace(z, logic.keyPlace(key)))
            named = logic.placeOf(value)
        end
        if text and text ~= "" then
            aheadSaid[nextKey] = { x = tx or x, y = ty or y, d = yards }
            wayNamed = named or wayNamed
            say(text, "ahead", x, y)
        end
    end
end

-- Stops: stepping onto the floor where one waits for a ship, zeppelin, lift or tram says so and
-- which way it will be ("wait for the ship to Auberdine, ship to the southwest"); the same stop
-- again only after the player walked STOP_REARM yards off every stop (a step off the edge of the
-- area and back is quiet). `rooms`: indoors the set of rooms the player may be in, nil outdoors.
local function checkStop(z, x, y, px, py, rooms)
    local i = logic.stopAt(z, x, y, rooms, rooms and heldFloor() or nil)
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

-- Indoors: the rooms the player may be in: the room when known, else the candidates here (the
-- rooms of the floor they are on, logic.floorRoomsAt, else those whose boxes hold the spot).
local function roomsHere(z, x, y)
    local here = {}
    if room then
        here[room] = true
    else
        local byFloor = logic.floorRoomsAt(logic.layer(z, IsIndoors()), x, y)
        for _, id in ipairs(logic.fittingRooms(z, byFloor or logic.roomCandidates(z, x, y), IsIndoors())) do
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
        value, laneDecided = logic.outdoorValue(z, x, y, isWay(outdoor.current, true))
    end
    local previous = outdoor.current
    -- a building's floors on a grid of their own (cells of 2 yd: the Brill tavern) are rooms: said
    -- after ENTRY_INDOORS (the kitchen came 14 s after the guidance to its stairs, walk 2026-10-03
    -- 23:14). The halls on the zone's grid keep ENTRY_OUTDOORS: at 5 or 3 Ironforge's large hall
    -- and its moat took turns within 2 s, and outdoors 3 nearly doubled the back and forth
    -- between places (replay of all walks, 2026-10-04)
    outdoor.distance = z.cell < zone.cell - 0.01 and ENTRY_INDOORS or ENTRY_OUTDOORS
    if outdoor:update(logic.outdoorKey(z, value, outdoor.current), x, y, z._index.floor or 0) then
        leftWay = logic.isWayKey(previous) and previous or nil
        leftClimb = previous and logic.CLIMBS[logic.kind(z, logic.keyPlace(previous))] and previous or nil
        -- off a way onto a square: at the way's end the square's description, before its end (a
        -- step off it sideways) where the way is (logic.leftAtEnd). A way left from another floor piece than the
        -- square's ends where its piece meets the square's: off its end (the road to Stormwind City on the approach
        -- bridge, a piece of its own, onto the Valley of Heroes' square, whose openings are found on its own floors
        -- only: the square's exits went unsaid, trial te2 replay 17:57:32)
        -- The same where the way is no opening of the square at all (it ends at the square's rim on a cell or two of
        -- paint, no mouth of it found): a way along the square's side is one of its openings, this one is not
        local sideways = false
        if leftWay and logic.hasEdge(z, value) and (outdoor.fromFloor == nil or outdoor.fromFloor == (z._index.floor or 0)) then
            local sq = logic.regionAt(z, x, y)
            sideways = sq ~= nil and logic.isOpeningOf(z, sq, previous)
                and not logic.leftAtEnd(z, sq, previous, outdoor.fromX or x, outdoor.fromY or y)
        end
        local text, square, said = logic.spotText(z, x, y, value, previous,
            { cut = true, facing = turnFacing(), swimming = IsSwimming(), named = wayNamed, sideways = sideways,
                from = { outdoor.fromX or x, outdoor.fromY or y } })
        if not logic.sameWay(value, previous, wayNamed, z) then
            wayNamed = logic.placeOf(value)
        end
        -- on a square: what was said now (its exits, what is close) is not said again on coming close
        region, saidMouths, saidLabels = square, said or {}, {}
        local cameOff = previous and (logic.isWayKey(previous) or logic.CLIMBS[logic.kind(z, logic.keyPlace(previous))])
        if cameOff and square then
            notePassedBeginning(z, outdoor.fromX or x, outdoor.fromY or y, square, previous)
        end
        bendFrom, bendWalked = nil, 0
        if aheadSaid[outdoor.current] then
            -- said before reaching it (checkAhead): only logged
            logEntry("place", text, x, y, { walked = round1(outdoor.walked), early = true })
            aheadSaid[outdoor.current] = nil
            heardLines = { text }
            -- an Alt-I route that waits for this place's line ends here, as on a place said now (review 2026-10-29)
            if helperArrival then
                helperArrival()
            end
        else
            say(text, "place", x, y, outdoor.walked)
        end
    elseif region and outdoor.current == logic.placeOf(region.value) then
        -- also from the square's edge (a step onto the street beside it does not leave it)
        checkApproach(z, x, y)
    end
end

-- In a big hall of the indoor layer: its pieces, as the city's streets; down in a moat or on a
-- liquid's piece (swimming in a canal) its way out (user 2026-09-29). `here`: the rooms the player
-- may be in.
local function updateLayer(z, layer, x, y, px, py, here)
    if not layerMode then
        layerMode = true
        forgetWays()
        notePassed(z, x, y)
    end
    lastRoom = room or lastRoom
    local down = downHere(layer, x, y)
    if down or logic.liquidKind(layer, layer._index.floor) then
        guide.key = nil
        guideExit(layer, x, y, down)
    else
        leftWater(x, y)
        checkGuide(layer, x, y)
    end
    checkPlace(layer, x, y, down)
    checkAhead(layer, x, y, px, py)
    checkStop(z, x, y, px, py, here)
end

-- Where the player was (the room, the levels of the indoor layer they were on, the floor piece
-- outdoors), kept per character over a reload or logout: with no height in the game a reload
-- upstairs left the module on the floor below (the Brill tavern, trial 2026-10-03; a login on the
-- zeppelin tower's deck said the street under it, walk 2026-10-06 14:21). Taken back only on the
-- same spot.
local function keepHere(z, x, y)
    -- (not before the kept spot was taken back: the first looks after a login in the halls,
    -- before the game's map was theirs, kept "not in the halls" over it)
    if WowVisionDB == nil or not hereRestored then
        return
    end
    local layer = logic.layer(z, IsIndoors())
    local floor = layer and (layer._index.floor or 0) or 0
    local ground = z._index.floor or 0
    local sig = tostring(room) .. "|" .. floor .. "|" .. ground .. "|" .. tostring(hallGap ~= nil)
    local h = WowVisionDB.surroundingsHere
    if hereKept == sig and h and logic.dist(h.x, h.y, x, y) < HERE_SAME / 2 then
        return
    end
    hereKept = sig
    local r = room and z._index.rooms[room]
    -- the floor piece by the place it carries at the spot, not by its number alone: every export
    -- numbers the pieces anew, and the number of the tavern's upper floor became another
    -- building's piece after the floor-pieces export, so a login upstairs landed on the ground
    -- (walk 2026-10-05)
    -- (every field written each time into the session's own table: no new table at nearly every look)
    if h == nil or h ~= hereTable then
        hereTable = {}
        WowVisionDB.surroundingsHere = hereTable
    end
    h = hereTable
    h.zone, h.x, h.y, h.room, h.roomName, h.halls = z.key, x, y, room, r and r.name, hallGap ~= nil
    h.layer, h.floor, h.floorLabel = layer and layer.key, floor, layer and logic.pieceLabel(layer, x, y, floor) or nil
    h.ground, h.groundLabel = ground, logic.pieceLabel(z, x, y, ground)
end

-- (`outdoors`: the room is not taken back)
local function restoreHere(z, x, y, outdoors)
    hereRestored = true
    local h = WowVisionDB and WowVisionDB.surroundingsHere
    if type(h) ~= "table" or h.zone ~= z.key or logic.dist(h.x, h.y, x, y) > HERE_SAME then
        return
    end
    local r = not outdoors and h.room and z._index.rooms[h.room]
    if r and r.name == h.roomName then
        room, roomByDoor = h.room, true
    end
    -- the zone's own floor piece (a tower's deck, a bridge, a city's raised street)
    if type(h.ground) == "number" and h.ground ~= 0 then
        local ground = logic.pieceWithLabel(z, x, y, h.groundLabel, h.ground)
        if ground ~= nil then
            logic.setFloor(z, ground)
        end
    end
    local layer = logic.layer(z, IsIndoors())
    if layer and layer.key == h.layer and type(h.floor) == "number" then
        local floor = h.floor
        if floor ~= 0 then
            floor = logic.pieceWithLabel(layer, x, y, h.floorLabel, floor)
        end
        if floor ~= nil then
            logic.setFloor(layer, floor)
            logic.forgetRegions(layer)
        end
    end
end

-- The platform or climb piece last said in room mode (roomPieceLine), where, so a step off and back on its edge is
-- not said again until the player was ROOM_PIECE_AGAIN yd away.
local roomPieceSaid = nil
local ROOM_PIECE_AGAIN = 6
local function roomPieceLine(layer, x, y)
    local v = logic.valueAt(layer, x, y)
    local kind = v and v ~= 0 and logic.kindOf(layer, v)
    local floor = layer._index.floor or 0
    if not (kind == "platform" or logic.CLIMBS[kind]) then
        -- a raised floor of its own that its room names (no platform: the Golden Rose's upper floor, ground trial
        -- 2026-10-31) is a step off the climb as a platform's line was: back onto the climb, the climb is said
        if floor ~= 0 then
            roomPieceSaid = { floor = floor, x = x, y = y }
        end
        return
    end
    local s = roomPieceSaid
    if s and s.floor == floor and logic.dist(s.x, s.y, x, y) < ROOM_PIECE_AGAIN then
        return
    end
    roomPieceSaid = { floor = floor, x = x, y = y }
    local text = logic.spotText(layer, x, y, v, nil, { facing = turnFacing(), swimming = IsSwimming() })
    if text and text ~= "" then
        say(text, "place", x, y)
    end
end

-- Out of a city's halls at (x, y) (a doorway to outside, or a hall no step leads from): logged once. The zone's grid
-- is followed from here, while the game may say indoors a few steps longer (the gate's tunnel): it starts on the
-- floor of the doorway's sill, as a step outdoors does (a hall's floor is a piece of its own on the zone's grid, held
-- since the way in: out of Ironforge's gate it was the floor for a second, ground trial 2026-10-30).
local function leaveHalls(z, x, y)
    hallGap, hallDoorOut = nil, { x, y }
    startOnSill(z, x, y)
    logEntry("floor", "out of the halls", x, y, { subzone = gameSubzone() })
end

-- Indoors: the room as far as known (switches at once; announced after the entry distance), the
-- doorways of a big room, the indoor layer's edges and halls, the stops in the room.
local function updateIndoors(z, x, y, px, py)
    if not hereRestored then
        restoreHere(z, x, y)
    end
    local before = room
    -- a doorway into a room whose floor is not here is passed over (see below), so the one behind
    -- it in the same step still counts
    local held = logic.layer(z, IsIndoors())
    local crossed = logic.crossedDoor(z, room, px, py, x, y, held and function(id)
        return logic.roomFloorNear(held, id, x, y) ~= false
    end)
    if crossed == 0 and hallGap ~= nil and room and z._index.rooms[room].hallMap then
        -- out of the halls through a doorway to outside (the throne room's onto the rose walk)
        leaveHalls(z, x, y)
    end
    local found = logic.resolveRoom(z, x, y, room, px, py, roomByDoor, crossed or false, IsIndoors())
    if found ~= nil and room ~= nil and found ~= room and hallGap ~= nil and logic.hallsApart(z, room, found) then
        -- no step leads from this hall into that one: out of the halls (a doorway left unnoticed)
        leaveHalls(z, x, y)
        found, room = nil, nil
    end
    -- up on a level of the indoor layer (a building's upper floor, its stairs) a doorway of the
    -- floor below leads nowhere: no room the layer does not cover (trial 2026-10-03, the Brill
    -- tavern: upstairs over the entrance's doorway the module said the entrance). Where the layer
    -- knows the room's floor (logic.roomFloorNear: a city's rooms by their floor) that floor decides,
    -- on any piece: a room whose floor is not here on the player's piece or one joined to it is
    -- none they walked into (a doorway has no height: the shops' doors on the Trade Quarter's ring
    -- lie over the canal hall)
    local near = held and found ~= nil and logic.roomFloorNear(held, found, x, y)
    if near == false or (near == nil and held and (held._index.floor or 0) ~= 0 and found ~= nil
        and not held._index.covered[found]) then
        crossed, found = nil, nil
    end
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
        -- the floor piece the player is on in the hall (a gallery, the moat under the walkways, a
        -- building's floors), as on the city's floors outdoors
        local ix = layer._index
        local before = ix.floor or 0
        local floor, floorChanged = logic.updateFloor(layer, x, y, swimState())
        if floorChanged then
            -- logged as an entry of its own (the walk log tools show where the floor switched;
            -- user 2026-10-06: a ground floor line at the top of the tavern's stairs)
            logEntry("floor", before .. " -> " .. floor, x, y)
            -- (the floor held before: the turn key on a landing faces the flight not come from)
            ix.floorBefore = before
            logic.noteClimbStep(layer, x, y)
            -- (the places found so far are kept per floor piece: logic.regionCache)
        end
        -- lava and drops inside warn as outdoors (user 2026-09-29: indoors keeps what outdoors
        -- has), each in the room its floor belongs to: this room, or while it is unknown
        -- (stacked floors) any room here; and on its own floor piece
        checkEdges(layer, x, y, px, py, here)
        -- in a room the layer does not cover (its room text speaks there): stepping onto a platform, a ramp or
        -- stairs of the layer says that piece's place line, as everywhere else (the Trade Quarter canal's raised
        -- platform and its ramp, user 2026-10-22: the room text stays, platforms named by the existing rules)
        if floorChanged and not logic.inLayer(layer, room, x, y) then
            roomPieceLine(layer, x, y)
        end
    end
    keepHere(z, x, y)
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
    -- walked in from outside without a doorway crossed: the room is said after ENTRY_INDOORS yd inside, so
    -- a step into a doorway and back says nothing (The Gilded Rose's door, where the floor names the inn;
    -- after a hearthstone, a jump, the room is said at once)
    if cameIn and logic.dist(cameIn[1], cameIn[2], x, y) >= ENTRY_INDOORS then
        cameIn = nil
    end
    if indoor:update(not cameIn and room or nil, x, y) then
        if room and lastRoom and logic.sameRoomName(z, room, lastRoom) then
            -- the next section of the same thing (a mine's passages, tram tunnel 6, 7..., the pieces
            -- of one staircase): no name, the way it runs when that changed and its doorways on
            -- (user 2026-10-03; until then only logged); with nothing left only logged
            local text, way = logic.sectionText(z, room, lastRoom, roomWaySaid, x, y)
            if text then
                say(text, "room", x, y, indoor.walked)
                roomWaySaid = way or roomWaySaid
            else
                logEntry("room", logic.roomText(z, room, lastRoom, true, x, y), x, y,
                    { walked = round1(indoor.walked), same = true })
            end
        else
            say(logic.roomText(z, room, lastRoom, true, x, y), "room", x, y, indoor.walked)
            roomWaySaid = room and logic.roomWay(z, room)
        end
        lastRoom = room
    end
    -- only a big room guides to its doorways (a small one leaves the entrance guidance as it was)
    if room and logic.isBigRoom(z, room) then
        if entryDoor and not entryAway then
            local dx, dy = logic.doorWorld(z, entryDoor)
            entryAway = dx == nil or logic.dist2(dx, dy, x, y) > logic.GUIDE_REACH ^ 2
        end
        checkGuide(z, x, y, room, not entryAway and entryDoor or nil, layer)
    end
    checkStop(z, x, y, px, py, here)
end

-- Outdoors: the drop edges and the floor piece (swimming, a liquid's), the guidance (on a
-- liquid's piece its ways out); the place, the next piece ahead on a way and its bends, the stops.
local function updateOutdoors(z, x, y, px, py)
    -- (only right after loading: not when walking past the kept spot later; a spot kept in the
    -- halls is left to updateHall, which takes it back once the game's map is the halls': after
    -- a login in the Trade Quarter's canal the first looks were outdoors, the restore was used up
    -- there and the halls never came back, "Ort unbekannt", walk 2026-10-16 12:44)
    local kept = WowVisionDB and WowVisionDB.surroundingsHere
    local keptHalls = type(kept) == "table" and kept.halls and kept.zone == z.key
        and logic.dist(kept.x, kept.y, x, y) <= HERE_SAME
    if not hereRestored and not keptHalls then
        restoreHere(z, x, y, true)
    end
    lastRoom = nil
    checkEdges(z, x, y, px, py)
    if logic.liquidKind(z, z._index.floor) then
        guide.key = nil
        guideExit(z, x, y)
    else
        leftWater(x, y)
        checkGuide(z, x, y)
    end
    checkPlace(z, x, y)
    checkAhead(z, x, y, px, py)
    checkBend(z, x, y, px, py)
    checkStop(z, x, y, px, py, nil)
    keepHere(z, x, y)
end

module:hasUpdate(function(self)
    local now = GetTime()
    watchFall(now)
    watchBoard(now)
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
        activeLog().client = gameVersion()
        logEntry("session", GetRealmName() .. ", " .. UnitName("player"), x, y, { client = gameVersion() })
    end
    local z = findZone(x, y, map)
    if z == nil then
        return
    end
    local px, py = lastX, lastY
    lastX, lastY = x, y
    local wasHall = hallGap ~= nil
    local inHall = updateHall(z, x, y, px, py)
    if inHall ~= wasHall then
        -- entering or leaving the halls, logged as a floor change (the walk log tools show where)
        if not inHall then
            startOnSill(z, x, y)
        end
        logEntry("floor", inHall and "into the halls" or "out of the halls", x, y, { subzone = gameSubzone() })
    end
    logTrail(x, y)
    logTiming(x, y)
    local isIndoors = IsIndoors() or inHall
    updatePassed(x, y)
    -- a jump (a hearthstone, a portal, a graveyard release, a summon) starts afresh as a step in or out does: from
    -- the Undercity's halls into the Brill tavern, inside both times, the halls' room held (2026-10-13); outdoors too
    -- (review 2026-10-29: released to a graveyard in the same zone, its place came only after 8 yd of walking)
    local jumped = wasIndoors ~= nil and px ~= nil and logic.dist(x, y, px, py) > JUMP
    if isIndoors ~= wasIndoors or jumped then
        if wasIndoors ~= nil then
            notePassed(z, x, y)
        end
        forgetPlace()
        -- through a doorway: the grid entered starts on the floor its sill lies on (not after a jump: no doorway)
        local entered = (isIndoors and logic.layer(z, IsIndoors())) or (not isIndoors and z) or nil
        if not jumped and wasIndoors ~= nil then
            startOnSill(entered, x, y)
        end
        cameIn = (isIndoors and wasIndoors == false and px and logic.dist(x, y, px, py) <= CAME_IN_STEP) and { x, y } or nil
        wasIndoors = isIndoors
        -- (into the halls by a hall's floor: on that hall's floor piece, updateHall)
        local layer = inHall and hallEntryFloor and logic.layer(z, IsIndoors())
        if layer then
            logic.setFloor(layer, hallEntryFloor)
        end
    end
    hallEntryFloor = nil
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
            parts[#parts + 1] = "No surroundings data loaded; the data folder mapdata/WowVision_Surroundings is missing "
                .. "(github.com/JeanStiletto/WowVision_Surroundings)"
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
                local stop = logic.stopAt(z, x, y, isInside() and roomsHere(z, x, y) or nil, isInside() and heldFloor() or nil)
                if stop then
                    parts[#parts + 1] = "Stop: " .. logic.finishText(logic.stopText(z, stop, x, y))
                end
                -- the game's own word on inside: IsIndoors, and its map (the halls it calls outdoors)
                parts[#parts + 1] = string.format("Game: %s, map %s, area %s%s", IsIndoors() and "indoors" or "outdoors",
                    tostring(gameMap()), gameSubzone() ~= "" and gameSubzone() or "none", hallGap and ", in a hall" or "")
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
        -- a big hall of the indoor layer: as a place outdoors; down in the moat or on a liquid its
        -- way out
        local down = downHere(layer, x, y)
        local out = down or logic.liquidKind(layer, layer._index.floor)
        local value = logic.outdoorValue(layer, x, y, isWay(outdoor.current, true))
        text = logic.spotText(layer, x, y, value, nil, { facing = turnFacing(), swimming = IsSwimming() }) or L["place unknown"]
        local t = self.settings.guidance and (out and logic.exitTarget(layer, x, y, layer._index.floor, down)
            or not out and logic.footTarget(layer, x, y, region))
        if t then
            text = text .. ", " .. logic.guideText(layer, t, true, logic.atTarget(layer, t, x, y))
        end
    elseif isInside() then
        text = room and logic.roomText(z, room, nil, false, x, y) or L["room unknown"]
        local t = room and self.settings.guidance and logic.roomDoorTarget(z, room, x, y)
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, logic.atTarget(z, t, x, y))
        end
    else
        local value = logic.outdoorValue(z, x, y, isWay(outdoor.current, true))
        -- a spot the data has no place for (a gap in the map) says so, as a room does
        text = logic.spotText(z, x, y, value, nil, { facing = turnFacing(), swimming = IsSwimming() }) or L["place unknown"]
        local t = nil
        if self.settings.guidance and logic.liquidKind(z, z._index.floor) then
            t = logic.exitTarget(z, x, y, z._index.floor)
        elseif self.settings.guidance then
            t = logic.footTarget(z, x, y, region)
        end
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, logic.atTarget(z, t, x, y))
        end
    end
    -- where one waits for a ship, zeppelin, lift or tram
    local stop = logic.stopAt(z, x, y, isInside() and roomsHere(z, x, y) or nil, isInside() and heldFloor() or nil)
    if stop then
        text = text .. ", " .. logic.stopText(z, stop, x, y)
    end
    -- a drop or water edge within reach, or ahead in the line of the facing (user's walk
    -- 2026-10-01: 1.4 yd from the canal the key said only the walk's name, then the fall); inside on the layer
    -- with the rooms here, as walking warns them (checkEdges): the halls' lava and canals, a room's drop
    local ez, rooms = z, nil
    if isInside() then
        ez, rooms = layer, layer and roomsHere(z, x, y)
    end
    if ez then
        local facing = GetPlayerFacing()
        local i = logic.nearestEdge(ez, x, y, EDGE_REACH, rooms, facing)
        local along, qx, qy = nil, nil, nil
        if i == nil and facing then
            i, along, qx, qy = logic.edgeAhead(ez, x, y, math.cos(facing), math.sin(facing), EDGE_LOOK, rooms)
        end
        if i then
            text = text .. ", " .. logic.edgeText(ez, i, along, x, y, qx, qy)
        end
    end
    say(text, "around", x, y)
end

-- The turn key toward the target the last guidance line spoke of (spokenGuide), while it is still
-- guided to: before it toward its point; at it, or on the climb whose foot it is, along its way
-- through, the direction said after it ("on to the 6", "in to the 3", "out to the 11"). Exact,
-- from the data's angles, not the hour said (user 2026-10-15: the beacon's turn key aims exactly,
-- this one should too). nil: no such target, or at one with no way through.
local function guideFacing(x, y)
    local g = spokenGuide
    local t = g and g.target
    if t == nil then
        return nil
    end
    -- the guidance lets a target go as soon as the player steps onto its climb or past its doorway;
    -- the key keeps it until the player is as far from it as the guidance forgets it (forgetLeft)
    local reach = targetReach(t)
    local d2 = logic.dist2(x, y, t.x, t.y)
    if d2 > (reach + GUIDE_FORGET) ^ 2 then
        return nil
    end
    local through = t.through and math.rad(-t.through)
    if g.atSaid == t.key or d2 <= 1 then
        return through
    end
    if t.kind == "climb" and through
        and (logic.pastTarget(g.zone, t, x, y) or logic.onClimb(g.zone, t, x, y, outdoor.current)) then
        return through
    end
    -- a foot guided to along the piece's own line (path lines, texts.lua climbTarget): the key turns along it
    if t.along then
        return math.rad(-t.along)
    end
    return math.rad(-logic.bearingOf(t.x - x, t.y - y))
end

-- The turn key with no beacon (maps' turn to waypoint): toward the target the last guidance line
-- spoke of (guideFacing); else along the centre line where the player stands (a way or a bridge;
-- without a line, the direction it is said with: a ramp, stairs, a canal), the way nearer the
-- facing; on a fork or crossing its arm nearest the facing, the next arm clockwise with each
-- further press; in a room said with the way it runs, along it. Outdoors, in a city's big halls
-- and in rooms; nil elsewhere (a square, no way here), and the key says there is no waypoint.
-- (also what it turned toward, for the walk log: "target", "room", "landing", "flight", "climb", "line", or nil)
-- `wayOnly`: the way here alone, not the guidance target (the beacon's quiet rule, maps.wayHere)
local function lineFacing(wayOnly)
    if not module:getEnabled() then
        return nil
    end
    local x, y, _z, map = UnitPosition("player")
    local facing = GetPlayerFacing()
    local z = x and facing and findZone(x, y, map)
    if z == nil then
        return nil
    end
    local toTarget = not wayOnly and guideFacing(x, y)
    if toTarget then
        return toTarget, "target"
    end
    if isInside() then
        local layer = logic.layer(z, IsIndoors())
        if not (layerMode and layer) then
            -- on a ramp or stairs piece of the layer in a room said by its text (the layer holds the floor there too:
            -- the Slaughtered Lamb's and the Golden Rose's stairs): the landing, the flight or the climb's route, as
            -- in the halls below; before, the key turned along the room's way or did nothing on the stairs (the
            -- user's walk 2026-11-02 18:34, "it ignores the stair directions I am on")
            local held = layer and (layer._index.floor or 0) ~= 0 and layer._index.floor
            if held then
                local onLanding = logic.landingFacing(layer, held, x, y, facing, layer._index.floorBefore)
                if onLanding then
                    return onLanding, "landing"
                end
                local onFlight = logic.flightFacing(layer, held, x, y, facing)
                if onFlight then
                    return onFlight, "flight"
                end
                local onClimb = logic.climbLineFacing(layer, held, x, y, facing)
                if onClimb then
                    return onClimb, "climb"
                end
            end
            -- a room said with the way it runs ("passage, north to south"): along it
            local r = room and z._index.rooms and z._index.rooms[room]
            if r and r.axis and not r.winding then
                local along = math.rad(-r.axis)
                return logic.lineTurnFacing({ along, along + math.pi }, facing, false), "room"
            end
            return nil
        end
        z = layer
    end
    -- on a landing between flights: toward the flight the player did not come from (lanes.lua landingFacing;
    -- the landing's own line is a stub, the inn's turned the player back down, walk 2026-10-19 22:11)
    local onLanding = logic.landingFacing(z, z._index.floor, x, y, facing, z._index.floorBefore)
    if onLanding then
        return onLanding, "landing"
    end
    -- on a flight whose own line is a stub: along the direction it is said with (lanes.lua flightFacing)
    local onFlight = logic.flightFacing(z, z._index.floor, x, y, facing)
    if onFlight then
        return onFlight, "flight"
    end
    -- (the beacon's quiet rule asks only whether there is a way to turn along: the way's own line first, before the
    -- route Alt-I would lead by on a climb, which builds that whole route at every ping; the same answer)
    if wayOnly then
        local value = logic.outdoorValue(z, x, y, isWay(outdoor.current, true))
        local facings, fork = logic.lineFacings(z, x, y, value, facing)
        local along = facings and logic.lineTurnFacing(facings, facing, fork)
        if along then
            return along, fork and "fork" or "line"
        end
    end
    -- on a ramp or stairs with its own line: along the route Alt-I leads by from here (helper.lua climbLineFacing)
    local onClimb = logic.climbLineFacing(z, z._index.floor, x, y, facing)
    if onClimb then
        return onClimb, "climb"
    end
    local value = logic.outdoorValue(z, x, y, isWay(outdoor.current, true))
    local facings, fork = logic.lineFacings(z, x, y, value, facing)
    if facings then
        return logic.lineTurnFacing(facings, facing, fork), fork and "fork" or "line"
    end
    return nil
end

-- Every press of the turn key (I) in the walk log, silent (user 2026-10-17: to see in the log when
-- the player went by ear and when by the key): kind "turn", what it turned toward (the route's
-- beacon, the guidance target said last with its name, a fork's arm, a way's line, a room's way,
-- or nothing) and `to`, the facing it turned to (degrees, as the entry's own facing).
local function turnLog(what, toFacing, name)
    local x, y = UnitPosition("player")
    if x == nil then
        return
    end
    local text = what .. (name and (": " .. name) or "")
    logEntry("turn", text, x, y, { to = toFacing and math.floor(math.deg(toFacing) % 360 + 0.5) or nil })
end

WowVision.base.navigation.maps.facingWithoutWaypoint = function()
    local facing, what = lineFacing()
    local t = what == "target" and spokenGuide and spokenGuide.target
    turnLog(what or "nothing", facing, t and logic.finishText(t.name or t.short or "") or nil)
    return facing
end
-- The beacon's loop stays quiet on a way with a direction of its own (maps setting quietOnWays, user 2026-10-28:
-- "I will align with the direction of the structure anyways, the beacon has no extra information to offer"): where
-- the plain turn key has a way to turn along (a street, road, canal, bridge, fork, ramp, stairs, landing, a room
-- said with its way); on squares and open ground the loop plays.
WowVision.base.navigation.maps.wayHere = function()
    return lineFacing(true) ~= nil
end
-- The floor choices of WowNav's routes name their floors (maps.floorName, user 2026-10-28) where the zone the
-- player is in knows the floor there (logic.floorNameAt); elsewhere they keep their heights.
WowVision.base.navigation.maps.floorName = function(x, y, height)
    if not module:getEnabled() or zone == nil then
        return nil
    end
    updateWords()
    return logic.floorNameAt(zone, x, y, height)
end
-- (the route's beacon: maps' turnToWaypoint calls this with the waypoint before it turns)
WowVision.base.navigation.maps.onTurnToWaypoint = function(wx, wy)
    local x, y = UnitPosition("player")
    turnLog("beacon", x and math.atan2(wy - y, wx - x) or nil)
end

-- The building helper (Alt plus the turn key, helper.lua): a beacon route from here through the next exit.
-- On a ramp or stairs with its own line: along it toward the end the player faces, onto the floor there. Else the
-- target the guidance spoke of last (while still guided to), else the one here, as the describe key finds it: a
-- doorway, an entrance or a way out is led through, a climb's foot up the whole climb to its landing. The beacon,
-- its keys (Shift-F12 ends it) and the quieter surroundings are those of every beacon (maps).
-- (made on first use: the walk replays load this file without the navigation's Path)
local HelperPath = nil

local function helperUpdate(self)
    if not self.active or self.complete then
        return nil
    end
    if self.currentIndex > #self.waypoints then
        self.beacon = nil
        -- (a route with an arrival rule ends on the surroundings' line for being there: helperArrival)
        if not self.waitsForLine then
            self.events.complete:emit(self)
            self.active = false
            self.complete = true
        end
        return
    end
    local x, y = UnitPosition("player")
    if x == nil then
        return
    end
    local w = self.currentWaypoint
    local before = self.waypoints[self.currentIndex - 1] or self.origin
    if logic.helperPassed(self.px, self.py, x, y, before, w) then
        self.events.arriveAtWaypoint:emit(self, w)
        self.currentIndex = self.currentIndex + 1
        self.currentWaypoint = self.waypoints[self.currentIndex]
        local maps = WowVision.base.navigation.maps
        self.beacon = self.currentWaypoint and maps.Beacon:new(self.currentWaypoint) or nil
    end
    self.px, self.py = x, y
    if self.beacon then
        self.beacon:update()
    end
end

-- The route led now (nil: none), and where the player was at its start, in its grid (logic.helperArrived).
local helperLed = nil
local function helperNow(grid)
    local f = grid._index.floor or 0
    return { floor = f, liquid = logic.liquidKind(grid, f) ~= nil, room = room, inside = isInside() }
end

-- On a place or room line (say): the route led ends here when the player is where it leads by the same rules.
helperArrival = function()
    local led = helperLed
    if led == nil or not led.path.active or led.path.complete then
        helperLed = nil
        return
    end
    if logic.helperArrived(led.route, led.start, helperNow(led.grid)) then
        helperLed = nil
        led.path.events.complete:emit(led.path)
        led.path.active = false
        led.path.complete = true
        led.path.beacon = nil
    end
end

local function helperPathClass()
    if HelperPath == nil then
        HelperPath = WowVision.Class("SurroundingsHelperPath", WowVision.base.navigation.maps.Path)
        HelperPath.update = helperUpdate
    end
    return HelperPath
end

-- The target the helper leads through, in the grid it belongs to: the last guided one while it is still guided to.
local function helperTarget(z, grid, x, y)
    local g = spokenGuide
    local t = g and g.target
    if t ~= nil then
        local reach = targetReach(t)
        if logic.dist2(x, y, t.x, t.y) <= (reach + GUIDE_FORGET) ^ 2 then
            return t, g.zone or grid
        end
    end
    if isInside() and not (layerMode and grid ~= z) then
        -- any room's doorway, a small room's too (the guidance names doorways in big rooms only)
        return room and logic.roomDoorTarget(z, room, x, y, nil, nil, nil, true) or nil, z
    end
    local down = downHere(grid, x, y)
    if down or logic.liquidKind(grid, grid._index.floor) then
        return logic.exitTarget(grid, x, y, grid._index.floor, down), grid
    end
    return logic.footTarget(grid, x, y, region), grid
end

function module:leadOn()
    local maps = WowVision.base.navigation.maps
    local x, y, _z, map = UnitPosition("player")
    local z = x and findZone(x, y, map)
    if z == nil then
        WowVision:speak(L["No exit nearby"])
        return
    end
    updateWords()
    local grid = z
    local layer = logic.layer(z, IsIndoors())
    if isInside() and layerMode and layer then
        grid = layer
    end
    local route, name = nil, nil
    local on = grid._index.floor
    if on and on ~= 0 and grid._index.lineFloors and grid._index.lineFloors[on] then
        route = logic.climbRouteFrom(grid, on, x, y, GetPlayerFacing())
    end
    -- (with end records: the climb end the guidance spoke of, or the one guided to here, before any other: Alt-I leads
    -- where the guidance points, up a foot or down a top)
    if route == nil and grid._index.climbTops then
        local t, g2 = helperTarget(z, grid, x, y)
        if t and t.kind == "climb" then
            route, name, grid = logic.helperRoute(g2, t), t.name, g2
        end
    end
    if route == nil then
        -- a climb's line beginning right here (a spiral's foot often has no foot record)
        route = logic.climbNear(grid, x, y, on, logic.HELPER_NEAR)
        if route then
            route.kind = "climb"
        end
    end
    if route == nil and on and on ~= 0 and grid._index.pathLines then
        -- a climb up from this floor piece farther off, along the piece's own line (path-line data)
        route = logic.floorClimbRoute(grid, on, x, y)
        if route and route.foot then
            name = logic.finishText(logic.describe(grid, route.foot.value, false, true, nil, nil))
        end
    end
    if route == nil then
        local t
        t, grid = helperTarget(z, grid, x, y)
        route = t and logic.helperRoute(grid, t) or nil
        name = t and t.name or nil
    end
    if route == nil or #route.points == 0 then
        WowVision:speak(L["No exit nearby"])
        return
    end
    local path = helperPathClass():new()
    path.origin = { x = x, y = y }
    for _, p in ipairs(route.points) do
        path:add({ x = p.x, y = p.y, n = name })
    end
    route.kind = route.kind or "climb"
    local start = helperNow(grid)
    -- a route the surroundings' rules end (out of the water, through a doorway, onto a landing) ends on their place
    -- or room line, with nothing more said; any other at its last point, with "Arrived"
    path.waitsForLine = logic.helperArrived(route, start, start) ~= nil
    helperLed = path.waitsForLine and { path = path, route = route, start = start, grid = grid } or nil
    path.events.complete:subscribe(self, function()
        maps.path = nil
        if not path.waitsForLine then
            WowVision:speak(L["Arrived"])
        end
    end)
    maps:pathfind(path)
    -- (the hours and a fork's arms resolved, as every other line: logic.finishText, expandDirs)
    local text = name and logic.finishText(logic.expandDirs(grid, string.format(L["Leading to %s"], name)))
        or L["Leading along the climb"]
    if route.short then
        text = text .. ", " .. L["the line ends before the top"]
    end
    WowVision:speak(text)
end

module:registerBinding({
    type = "Script",
    key = "surroundings/leadOn",
    label = L["Lead Through the Next Exit"],
    inputs = { "ALT-I" },
    -- (controller: left shoulder + right stick press, next to the turn key)
    padInputs = { "ALT-PADRSTICK" },
    script = "/run WowVision.base.navigation.surroundings:leadOn()",
})

module:registerBinding({
    type = "Script",
    key = "surroundings/describe",
    label = L["Describe Surroundings"],
    inputs = { "ALT-L" },
    -- (controller: left trigger + right stick press)
    padInputs = { "SHIFT-PADRSTICK" },
    script = "/run WowVision.base.navigation.surroundings:describeAround()",
})
