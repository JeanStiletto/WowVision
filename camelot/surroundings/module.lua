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
local CAME_OUT = 3 -- after coming out of a building it can lead onto a wall-walk this long
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
local PASSED_REACH = 8 -- a doorway this close (a gate is 20 yd wide) when the player changes room, hall or goes in or out was walked through
local PASSED_SAME = 4 -- a guidance target this close to that doorway is that doorway

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
local roomWaySaid = nil -- the way the last said room runs ("north to south"), for its next section
local layerMode = false -- in one of the big halls of the indoor layer: its places, not the room
-- the doorway the player came into the room by, left out of the doorway guidance until they were
-- once beyond the guidance reach from it (it said "at the way outside" right after coming in)
local entryRoom, entryDoor, entryAway = nil, nil, false
local outAt = nil -- when the player last came out of a building
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
    local inFloor, entryRoom = logic.inHallFloor(z, x, y, uiMap, z._index.floor or 0, hallMapWalked ~= nil, z._index.gameArea)
    if inFloor then
        -- the room whose floor let the player in is the room they are in (not one found by x and y
        -- at another height; an older room held from before is forgotten), and the halls layer's
        -- floor is that room's (logic.roomPieceHere: the rooms are found by the floor)
        hallGap, room, roomByDoor = 0, entryRoom, false
        local layer = logic.layer(z, IsIndoors())
        local piece = layer and logic.roomPieceHere(layer, entryRoom, x, y)
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
    local held = zone and zone._index and (isInside() and logic.layer(zone, IsIndoors()) or zone) or nil
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
-- outdoors), s (swimming), g (ghost), f with the facing in degrees and p with the floor piece
-- when it is not the ground, as one token ("isf270p33"); then "|<area>", the game's area, where it
-- changed or every TRAIL_AREA_EVERY points (after a space: tools read the flags before it).
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
    local held = zone and zone._index and (isInside() and logic.layer(zone, IsIndoors()) or zone) or nil
    local piece = held and held._index.floor or 0
    local flags = (IsIndoors() and "i" or "") .. (hallGap and "h" or "") .. (IsSwimming() and "s" or "")
        .. (UnitIsGhost("player") and "g" or "")
        .. (facing and ("f" .. facing) or "")
        .. (piece ~= 0 and ("p" .. piece) or "")
    local area = gameSubzone()
    trailSince = trailSince + 1
    local tail = ""
    if area ~= trailArea or trailSince >= TRAIL_AREA_EVERY then
        tail, trailArea, trailSince = " |" .. area, area, 0
    end
    table.insert(log.trail, string.format("%d %.1f %.1f%s%s", time(), x, y, flags ~= "" and " " .. flags or "", tail))
    log.trail = trim(log.trail, TRAIL_MAX)
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
end
-- the game decodes a zone's JSON text (offline the tools put a stand-in in its place)
logic.decodeJson = function(text)
    return C_EncodingUtil.DeserializeJSON(text)
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
        if found then
            logic.unpack(found, GetLocale())
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

local function say(text, kind, x, y, walked, extra)
    local raw = text
    text = logic.finishText(text)
    if zone then
        text = logic.spokenText(zone, text)
    end
    if text and text ~= "" then
        speakLine(text, kind)
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
    g.said[t.key] = { x = t.x, y = t.y, reach = t.reach or (t.kind == "exit" and logic.EXIT_REACH) or logic.GUIDE_REACH }
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
            say(logic.guideText(z, t, named, true, bare), t.kind, x, y)
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

local function checkGuide(z, x, y, roomId, skipDoor)
    if not module.settings.guidance then
        guide.key = nil
        return
    end
    forgetLeft(guide, x, y)
    -- a beacon starting or ending: the nearest target is said anew in the other manner, by name
    local brief = beaconGuides()
    if brief ~= guide.brief then
        guide.brief, guide.key, guide.named, guide.said = brief, nil, nil, {}
    end
    logic.wallSide = module.settings.wallSide == true
    -- in a big room: its doorways; on foot elsewhere: entrances and street beginnings
    local prefer = guide.key and guide.x and { x = guide.x, y = guide.y } or nil
    local function lookup(reach)
        if roomId then
            return logic.roomDoorTarget(z, roomId, x, y, skipDoor, prefer, reach)
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
    if t and t.kind == "climb" then
        if logic.onClimb(z, t, x, y, outdoor.current) then
            if guide.key == t.key then
                guide.at = false
            end
            t = nil
        elseif logic.pastTarget(z, t, x, y) then
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
    guideTo(z, guide, t, x, y, brief)
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

-- Is the player pushing against something (the wall detection's "blocked", fresh)? Then a step
-- past an edge's rim is a push against its railing, no fall (logic.updateFloor).
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
        local floor, changed = logic.updateFloor(z, x, y, outAt ~= nil and GetTime() - outAt < CAME_OUT, px, py, pushing(), swimState())
        if changed then
            -- the squares found so far were flooded on the old floor
            logic.forgetRegions(z)
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
    local o = logic.objectAhead(z, x, y, vx, vy, logic.BUMP_REACH, isIndoors and room or 0)
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
    if outdoor:update(logic.outdoorKey(z, value, outdoor.current), x, y) then
        leftWay = logic.isWayKey(previous) and previous or nil
        -- off a way onto a square: at the way's end the square's description, before its end (a
        -- step off it sideways) where the way is (logic.leftAtEnd)
        local sideways = false
        if leftWay and logic.hasEdge(z, value) then
            local sq = logic.regionAt(z, x, y)
            sideways = sq ~= nil and not logic.leftAtEnd(z, sq, previous, outdoor.fromX or x, outdoor.fromY or y)
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

-- Indoors: the room as far as known (switches at once; announced after the entry distance), the
-- doorways of a big room, the indoor layer's edges and halls, the stops in the room.
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
    WowVisionDB.surroundingsHere = { zone = z.key, x = x, y = y, room = room, roomName = r and r.name, halls = hallGap ~= nil,
        layer = layer and layer.key, floor = floor, floorLabel = layer and logic.pieceLabel(layer, x, y, floor) or nil,
        ground = ground, groundLabel = logic.pieceLabel(z, x, y, ground) }
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
        hallGap, hallDoorOut = nil, { x, y }
        logEntry("floor", "out of the halls", x, y, { subzone = gameSubzone() })
    end
    local found = logic.resolveRoom(z, x, y, room, px, py, roomByDoor, crossed or false, IsIndoors())
    if found ~= nil and room ~= nil and found ~= room and hallGap ~= nil and logic.hallsApart(z, room, found) then
        -- no step leads from this hall into that one: out of the halls (a doorway left unnoticed)
        hallGap, hallDoorOut = nil, { x, y }
        logEntry("floor", "out of the halls", x, y, { subzone = gameSubzone() })
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
        local floor, floorChanged = logic.updateFloor(layer, x, y, false, px, py, pushing(), swimState())
        if floorChanged then
            -- logged as an entry of its own (the walk log tools show where the floor switched;
            -- user 2026-10-06: a ground floor line at the top of the tavern's stairs)
            logEntry("floor", before .. " -> " .. floor, x, y)
            -- the places found so far kept per floor piece, so stepping back onto a floor finds
            -- its places again with what was said there (a fresh flood at every hop said the
            -- stairs twice)
            ix.regionsByFloor = ix.regionsByFloor or {}
            ix.regionsByFloor[ix.regionFloor or 0] = ix.regionOf
            ix.regionOf = ix.regionsByFloor[floor] or {}
            ix.regionFloor = floor
        end
        -- lava and drops inside warn as outdoors (user 2026-09-29: indoors keeps what outdoors
        -- has), each in the room its floor belongs to: this room, or while it is unknown
        -- (stacked floors) any room here; and on its own floor piece
        checkEdges(layer, x, y, px, py, here)
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
        checkGuide(z, x, y, room, not entryAway and entryDoor or nil)
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
    local wasHall = hallGap ~= nil
    local inHall = updateHall(z, x, y, px, py)
    if inHall ~= wasHall then
        -- entering or leaving the halls, logged as a floor change (the walk log tools show where)
        logEntry("floor", inHall and "into the halls" or "out of the halls", x, y, { subzone = gameSubzone() })
    end
    logTrail(x, y)
    local isIndoors = IsIndoors() or inHall
    updatePassed(x, y)
    -- a jump inside (a hearthstone, a portal) starts afresh as a step in or out does: from the
    -- Undercity's halls into the Brill tavern, inside both times, the halls' room held (2026-10-13)
    local jumped = isIndoors and wasIndoors and px ~= nil and logic.dist(x, y, px, py) > JUMP
    if isIndoors ~= wasIndoors or jumped then
        if wasIndoors ~= nil then
            notePassed(z, x, y)
        end
        forgetPlace()
        outAt = (wasIndoors and not isIndoors) and now or nil
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
                local stop = logic.stopAt(z, x, y, isInside() and roomsHere(z, x, y) or nil)
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
            text = text .. ", " .. logic.guideText(layer, t, true, t.d <= logic.GUIDE_AT)
        end
    elseif isInside() then
        text = room and logic.roomText(z, room, nil, false, x, y) or L["room unknown"]
        local t = room and self.settings.guidance and logic.roomDoorTarget(z, room, x, y)
        if t then
            text = text .. ", " .. logic.guideText(z, t, true, t.d <= logic.GUIDE_AT)
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
        local i = logic.nearestEdge(z, x, y, EDGE_REACH, nil, facing)
        local along, qx, qy = nil, nil, nil
        if i == nil and facing then
            i, along, qx, qy = logic.edgeAhead(z, x, y, math.cos(facing), math.sin(facing), EDGE_LOOK, nil)
        end
        if i then
            text = text .. ", " .. logic.edgeText(z, i, along, x, y, qx, qy)
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
    local reach = t.reach or (t.kind == "exit" and logic.EXIT_REACH) or logic.GUIDE_REACH
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
    return math.rad(-logic.bearingOf(t.x - x, t.y - y))
end

-- The turn key with no beacon (maps' turn to waypoint): toward the target the last guidance line
-- spoke of (guideFacing); else along the centre line where the player stands (a way or a bridge;
-- without a line, the direction it is said with: a ramp, stairs, a canal), the way nearer the
-- facing; on a fork or crossing its arm nearest the facing, the next arm clockwise with each
-- further press; in a room said with the way it runs, along it. Outdoors, in a city's big halls
-- and in rooms; nil elsewhere (a square, no way here), and the key says there is no waypoint.
-- (also what it turned toward, for the walk log: "target", "room", "line", or nil)
local function lineFacing()
    if not module:getEnabled() then
        return nil
    end
    local x, y, _z, map = UnitPosition("player")
    local facing = GetPlayerFacing()
    local z = x and facing and findZone(x, y, map)
    if z == nil then
        return nil
    end
    local toTarget = guideFacing(x, y)
    if toTarget then
        return toTarget, "target"
    end
    if isInside() then
        local layer = logic.layer(z, IsIndoors())
        if not (layerMode and layer) then
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
        self.events.complete:emit(self)
        self.active = false
        self.complete = true
        self.beacon = nil
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
        local reach = t.reach or (t.kind == "exit" and logic.EXIT_REACH) or logic.GUIDE_REACH
        if logic.dist2(x, y, t.x, t.y) <= (reach + GUIDE_FORGET) ^ 2 then
            return t, g.zone or grid
        end
    end
    if isInside() and not (layerMode and grid ~= z) then
        return room and logic.roomDoorTarget(z, room, x, y) or nil, z
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
    if route == nil then
        -- a climb's line beginning right here (a spiral's foot often has no foot record)
        route = logic.climbNear(grid, x, y, on, logic.HELPER_NEAR)
        if route then
            route.kind = "climb"
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
    local last = route.points[#route.points]
    local landing = route.landing
    path.events.complete:subscribe(self, function()
        maps.path = nil
        local where = landing and logic.pieceLabel(grid, last.x, last.y, landing) or nil
        WowVision:speak(L["Arrived"] .. (where and (", " .. where) or ""))
    end)
    maps:pathfind(path)
    local text = name and string.format(L["Leading to %s"], name) or L["Leading along the climb"]
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
    script = "/run WowVision.base.navigation.surroundings:leadOn()",
})

module:registerBinding({
    type = "Script",
    key = "surroundings/describe",
    label = L["Describe Surroundings"],
    inputs = { "ALT-L" },
    script = "/run WowVision.base.navigation.surroundings:describeAround()",
})
