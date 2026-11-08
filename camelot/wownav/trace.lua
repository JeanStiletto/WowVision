-- The saved diagnostics of WowNav routes, with WowNav's own field names (WowVisionNavigation.lua by Broesel33), so a
-- walk can be read after /reload or logout without asking the player where he was:
--   WowVisionDump.wownavLog         his /vn log (CreateLogEntry): one full snapshot per key press, with a comment
--   WowVisionDump.wownavBlockages   his blockage telemetry (HandleBlockage, WowVisionNavigationDB.blockageTelemetry)
--   WowVisionDump.wownavWalk        WowVision's own walk trace: the route's waypoints when it starts, then one sample per
--                                   guidance update while the player moves (his log fields), and every route event
-- His z note (10.6b) holds here too: the game gives no height on Forever, so estimatedHeight is the route's estimate,
-- or the floor height another module knows (maps.floorHeight, the surroundings' tracker); heightSource says which.
-- WowVision's own field: isFalling (IsFalling), and a fall_start / fall_end event; a fall is what a walk trace looks for.
--
-- Pure apart from WowVisionDump: the module (or a test) gives the game state as a table (see trace.sample).

local trace = {}
WowVision.wownavTrace = trace

trace.WALK_SIZE = 2400        -- samples and events: 10 minutes of walking at his 0.25 s update interval
trace.BLOCKAGE_SIZE = 200
trace.LOG_SIZE = 100

local function list(key, size)
    WowVisionDump = WowVisionDump or {}
    local entries = WowVisionDump[key]
    if type(entries) ~= "table" then
        entries = {}
        WowVisionDump[key] = entries
    end
    return entries, size
end

local function append(key, size, entry)
    local entries = list(key, size)
    entries[#entries + 1] = entry
    while #entries > size do
        table.remove(entries, 1)
    end
    return #entries
end

-- The game's part of an entry. game: { timestamp, time, x, y, map, facing, moving, speed, falling, swimming, indoors,
-- outdoors, zone, subzone, normalizedX, normalizedY } (nil where the game does not say).
local function gameFields(entry, game)
    entry.worldX, entry.worldY = game.x, game.y
    entry.mapID = game.map
    entry.viewDirection = game.facing
    entry.isPlayerMoving = game.moving
    entry.playerSpeed = game.speed
    entry.isFalling = game.falling
    entry.isSwimming = game.swimming
    return entry
end

-- His /vn log entry (CreateLogEntry): the route's fields (Route:logFields) and the game's. Returns the entry and its
-- number in the log.
function trace.logEntry(route, game, comment)
    local entry = gameFields({ timestamp = game.timestamp, time = game.time }, game)
    entry.normalizedX, entry.normalizedY = game.normalizedX, game.normalizedY
    entry.zone, entry.subzone = game.zone, game.subzone
    entry.isIndoorsPerAPI, entry.isOutdoorsPerAPI = game.indoors, game.outdoors
    entry.comment = comment
    if route ~= nil then
        route:logFields(game.x, game.y, entry)
    end
    return entry, append("wownavLog", trace.LOG_SIZE, entry)
end

function trace.clearLog()
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.wownavLog = {}
end

-- His blockage telemetry entry (Route:blockageTelemetry), as the route hands it over.
function trace.blockage(entry, game)
    entry.timestamp = entry.timestamp or game.timestamp
    entry.time = game.time
    entry.mapID = game.map
    entry.isFalling = game.falling
    append("wownavBlockages", trace.BLOCKAGE_SIZE, entry)
    trace.event("blockage", nil, game, { kind = entry.kind, reaction = entry.reaction, pathIndex = entry.pathIndex,
        edgeFrom = entry.edgeFrom, edgeTo = entry.edgeTo })
end

-- A route begins: its target and every waypoint with position, arrival radius, gate half width and his codes, so the
-- trace can be read against exactly the network the game ran.
function trace.routeStarted(route, game)
    local N = route.N
    local waypoints = {}
    for i, id in ipairs(route.path or {}) do
        local x, y, z = N.Position(id)
        local real = id < N.VIRT_BASE
        waypoints[i] = string.format("%d %s %.1f %.1f %.1f r=%s gate=%s %s", i, tostring(id), x or 0, y or 0, z or 0,
            tostring(real and N.Radius(id) or nil), tostring(real and N.GateHalfWidth(id) or nil),
            real and route.waypointBaseCode(N.Bits(id)) or "virtual")
    end
    trace.lastUpdates = nil
    trace.lastIndex = nil
    trace.event("route", route, game, { waypoints = waypoints })
end

-- One entry of the walk trace: the game's and the route's fields, plus the event's own.
function trace.event(kind, route, game, extra)
    local entry = gameFields({ event = kind, timestamp = game.timestamp, time = game.time }, game)
    if route ~= nil then
        route:logFields(game.x, game.y, entry)
    end
    for key, value in pairs(extra or {}) do
        entry[key] = value
    end
    append("wownavWalk", trace.WALK_SIZE, entry)
end

-- Every frame while a route runs: one sample per guidance update that ran (route.updates), while the player moves,
-- falls or the current waypoint changed; standing still is left out. A fall gets its start and its end.
function trace.sample(route, game)
    if game.falling and not trace.fallStart then
        trace.fallStart = { time = game.time, x = game.x, y = game.y, height = route:estimatedHeight(),
            pathIndex = route.pathIndex, waypointId = route.path and route.path[route.pathIndex] }
        trace.event("fall_start", route, game)
    elseif not game.falling and trace.fallStart then
        local start = trace.fallStart
        trace.fallStart = nil
        trace.event("fall_end", route, game, { fallSeconds = game.time and start.time and game.time - start.time,
            fallFromX = start.x, fallFromY = start.y, fallFromHeight = start.height, fallFromIndex = start.pathIndex,
            fallFromWaypointId = start.waypointId })
    end
    if route.updates == trace.lastUpdates then
        return
    end
    trace.lastUpdates = route.updates
    local changed = route.pathIndex ~= trace.lastIndex
    trace.lastIndex = route.pathIndex
    if game.moving or game.falling or changed then
        trace.event("sample", route, game)
    end
end

-- A route event (Route:update's kinds) after the route took it: the waypoint just reached and by which rule.
function trace.routeEvent(route, game, event)
    local extra = { kind = event.kind }
    if event.kind == "advance" then
        extra.reachedWaypointId = route.lastConfirmedNode
        extra.reachedBy = route.lastArrivalRule
    elseif event.kind == "reentry" or event.kind == "fallback" then
        extra.skipped = event.skipped
    end
    trace.lastIndex = route.pathIndex
    trace.event("route_event", route, game, extra)
end

-- The route ended (arrived, stopped, lost, a transit): the last entry of its walk.
function trace.routeEnded(route, game, why)
    trace.fallStart = nil
    trace.event("route_end", route, game, { why = why })
end
