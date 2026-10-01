-- Surroundings: the spoken texts. One description of a spot, the same for the announcements and
-- the describe key: what is said depends only on where the player stands and the fixed map, never
-- on how they got there. The announcements (`cut`) may only leave things out: what was just said
-- (the way the player came, `previous`: the outdoor key before) and more than ITEMS_MAX things.

local logic = WowVision.surroundingsLogic
local L = WowVision:getLocale()

-- The templates that name a direction, and their clock forms ("6 to the northeast" / "6 at 2
-- o'clock"): looked up through T, which takes the clock form in clock mode.
local CLOCK = {
    ["%s to the %s"] = "%s at %s",
    ["%d to the %s"] = "%d yards at %s",
    ["%d %s"] = "%d at %s",
    ["in to the %s"] = "in at %s",
    ["out to the %s"] = "out at %s",
    ["through to the %s"] = "through at %s",
    ["on to the %s"] = "on at %s",
    ["road to the %s"] = "road at %s",
    ["street to the %s"] = "street at %s",
    ["ship to the %s"] = "ship at %s",
    ["zeppelin to the %s"] = "zeppelin at %s",
    ["tram to the %s"] = "tram at %s",
    ["lift to the %s"] = "lift at %s",
    -- drop edges ("at 4, water"; "9 at 4 o'clock, water": the yards before the hour ask for it)
    ["%s, drop %d"] = "at %s, drop %d",
    ["%d %s, drop %d"] = "%d at %s, drop %d",
    ["%s, water"] = "at %s, water",
    ["%d %s, water"] = "%d at %s, water",
    ["%s, canal"] = "at %s, canal",
    ["%d %s, canal"] = "%d at %s, canal",
    ["%s, lava"] = "at %s, lava",
    ["%d %s, lava"] = "%d at %s, lava",
    ["%s, moat"] = "at %s, moat",
    ["%d %s, moat"] = "%d at %s, moat",
}
local function T(key)
    if logic.clock and CLOCK[key] then
        return L[CLOCK[key]]
    end
    return L[key]
end
logic.T = T

local ITEMS_MAX = 4 -- things said at most on entering a square or a room
local APPROACH = 10 -- yd; on a square, a street, water or drop not said yet is said this close
local FEATURE_REACH = 25 -- yd; cliffs and water said with an outdoor place
local ROAD_SIDE_REACH = 12 -- yd; off a road or street, where it is is said within this
local GUIDE_REACH = 8 -- yd; entrances and street beginnings are guided to from this close
logic.GUIDE_REACH = GUIDE_REACH
local EXIT_REACH = 25 -- yd; ways out of the water guided to while swimming
local MOAT_EXIT_REACH = 300 -- yd; a moat's way out, from anywhere down in it (the Commons' moat is a ring)
logic.GUIDE_AT = 3 -- yd from a target that count as being at it

-- The names of the item classes that are their own word; the others (ways, rooms) carry a name.
local NAMED_CLASSES = { way = true, room = true, entrance = true }
-- the kinds said as cliffs and water near an outdoor place, and their words
local FEATURES = { ["cliff edge"] = "cliff edge", ["cliff foot"] = "rock wall", ["deep water"] = "water", shore = "water" }
-- places that say no cliffs and water: the ways (they come often; roads and streets alike, one
-- rule set, user 2026-10-01: a street said "rock wall to the northeast" where a road stays short)
-- and the water itself
local FEATURE_SKIP = { bridge = true, ["deep water"] = true, canal = true }
for kind in pairs(logic.LANE_KINDS) do
    FEATURE_SKIP[kind] = true
end
-- the ways with centre lines that are no road: city streets and walks ("street to the east")
local STREETS = {}
for kind in pairs(logic.LANE_KINDS) do
    if not logic.ROADS[kind] then
        STREETS[kind] = true
    end
end

-- "a", "a and b", "a, b and c"
function logic.joinWords(words)
    local text = words[#words]
    for i = #words - 1, 1, -1 do
        text = i == #words - 1 and string.format(L["%s and %s"], words[i], text) or words[i] .. ", " .. text
    end
    return text
end

-- "street of Old Town to the northwest and south, water to the east, entrance of the bank here"
function logic.itemsText(zone, items)
    local parts = {}
    for _, item in ipairs(items) do
        local name = logic.expandDirs(zone, item.label)
        if item.class == "entrance" then
            name = string.format(L["entrance of %s"], item.label)
        elseif not NAMED_CLASSES[item.class] then
            name = L[item.class]
        end
        if #item.dirs == 0 then
            parts[#parts + 1] = string.format(L["%s here"], name)
        else
            local words = {}
            for _, dir in ipairs(item.dirs) do
                words[#words + 1] = logic.dirWord(zone, dir)
            end
            parts[#parts + 1] = string.format(T("%s to the %s"), name, logic.joinWords(words))
        end
    end
    return table.concat(parts, ", ")
end

-- A drop edge, short (user 2026-09-29: every word counts in the moment before a fall; distances
-- are always yards): the direction and what lies below ("southeast, canal"); with `ahead` (yd
-- along the path) the distance first ("9 southwest, canal"). Per edge's `into`: a plain drop with
-- its depth ("north, drop 12"), water, a city canal, lava (Ironforge), a moat (Ironforge's Commons).
local EDGE_TEXTS = {
    [0] = { "%s, drop %d", "%d %s, drop %d" },
    [1] = { "%s, water", "%d %s, water" },
    [2] = { "%s, canal", "%d %s, canal" },
    [3] = { "%s, lava", "%d %s, lava" },
    [4] = { "%s, moat", "%d %s, moat" },
}

-- `x, y`: the player; with them an edge with a depth per point says the depth at its nearest
-- point (a ramp's side edge: 2 yd at the foot, 9 at the top; one value said "8 deep" at the foot).
function logic.edgeText(zone, i, ahead, x, y)
    local e = logic.edge(zone, i)
    local texts = EDGE_TEXTS[e.into] or EDGE_TEXTS[0]
    local word = logic.dirWord(zone, e.facing, ahead ~= nil)
    local drop = e.drop
    if e.drops and x then
        local p, best = e.points, math.huge
        for k = 1, #p - 1, 2 do
            local d = logic.dist2(x, y, p[k], p[k + 1])
            local at = e.drops[(k + 1) / 2]
            if at and d < best then
                best, drop = d, at
            end
        end
    end
    if ahead then
        local yards = math.max(1, math.floor(ahead + 0.5))
        return string.format(T(texts[2]), yards, word, drop)
    end
    return string.format(T(texts[1]), word, drop)
end

-- A turn hint: 1 left, -1 right. A gentle bend says the turn alone, in clock mode too (user
-- 2026-10-01 after the first clock walk: a bend stays inside the piece's direction, the hour said
-- with it is noise).
function logic.turnText(turn)
    return turn > 0 and L["left"] or L["right"]
end

-- Guidance targets -------------------------------------------------------------------------------
-- A target {key (unique among the targets of one guide), kind, x, y, d, dir (distance and angle
-- from the player), name and short (its text the first time and after), atName and at (at the
-- target), through (the angle of the way through it) and throughFormat}.

-- A doorway target: into the room `label` (the way out when `label` is nil), `through` the
-- angle of the way through it.
local function doorwayTarget(key, d, dir, x, y, label, through)
    if label == nil then
        return {
            key = key, kind = "doorway", d = d, dir = dir, x = x, y = y,
            name = L["way outside"], short = L["way outside"], atName = L["at the way outside"],
            at = L["at the way outside"],
            through = through, throughFormat = T("out to the %s"),
        }
    end
    return {
        key = key, kind = "doorway", d = d, dir = dir, x = x, y = y,
        name = label, short = L["doorway"],
        atName = string.format(L["at the doorway to %s"], label), at = L["at the doorway"],
        through = through, throughFormat = T("through to the %s"),
    }
end

local function entranceTarget(zone, x, y, reach, prefer)
    local i, d, dir, e = logic.nearestEntrance(zone, x, y, reach, prefer)
    if i == nil then
        return nil
    end
    if e.plain then
        -- in the indoor layer: a doorway into a passage, stairs, or out
        return doorwayTarget("e" .. i, d, dir, e.x, e.y, not e.wayOut and e.text or nil, e.inDir)
    end
    return {
        key = "e" .. i, kind = "entrance", d = d, dir = dir, x = e.x, y = e.y,
        name = string.format(L["entrance of %s"], e.text), short = L["entrance"],
        atName = string.format(L["at the entrance of %s"], e.text), at = L["at the entrance"],
        through = e.inDir, throughFormat = T("in to the %s"),
    }
end

-- In a big room (logic.isBigRoom), the nearest of its doorways within reach, as a guidance target:
-- the room behind it by name, the way through it leaving the room. `skip` (optional): a door left
-- out (the one the player just came in by).
function logic.roomDoorTarget(zone, roomId, x, y, skip, prefer)
    local d, door, dx, dy, beyond = logic.nearestDoorway(zone, roomId, x, y, GUIDE_REACH, skip, prefer)
    if d == nil then
        return nil
    end
    local label = beyond ~= 0 and logic.describeRoom(zone, beyond, roomId) or nil
    return doorwayTarget(string.format("d%.1f,%.1f", door.x, door.y), d, logic.bearingOf(dx - x, dy - y), dx, dy,
        label, logic.doorwayDirection(zone, door, roomId))
end

-- Where a street (road, bridge, canal walk) begins on the square the player is on (or, just off
-- it, `square`); streets that run along the square's side are no target (see wayBeginnings).
local function beginningTarget(zone, x, y, reach, square, prefer)
    square = logic.regionAt(zone, x, y) or square
    if square == nil then
        return nil
    end
    local i, d, dir, b = logic.nearestBeginning(zone, square, x, y, reach, prefer)
    if i == nil then
        return nil
    end
    return {
        key = "w" .. b.label .. "@" .. math.floor(b.x) .. "," .. math.floor(b.y), kind = "way", d = d, dir = dir,
        x = b.x, y = b.y,
        -- always by name: "street here" says nothing on a square (user 2026-09-30), an opening is
        -- one of few, unlike the entrances along it
        name = b.label, short = b.label,
        atName = string.format(L["at the %s"], b.label), at = string.format(L["at the %s"], b.label),
        through = b.onward, throughFormat = T("on to the %s"),
    }
end

-- The foot of a ramp or stairs joined to the way the player is on (zone.climbFeet), as a guidance
-- target: named like the climb ("ramp to the griffon roost"), the way through its rise ("up to
-- the southeast"). User 2026-10-01: "hitting the ramp by ear still impossible, I always miss
-- the entrance and walk on the street next to it".
local function climbTarget(zone, x, y, reach, prefer)
    local i, d, dir, f = logic.nearestPoint(zone._index.climbFeet, x, y, reach, prefer)
    if i == nil then
        return nil
    end
    local code = logic.codeOf(f.value)
    local up = code > 0 and not logic.axisOf(zone, f.value) and code % 1000 or nil
    local name = logic.describe(zone, f.value, false, true)
    return {
        key = "c" .. i, kind = "climb", d = d, dir = dir, x = f.x, y = f.y, value = f.value,
        name = name, short = name, atName = name, at = name,
        through = up, throughFormat = up and logic.dirTemplate(zone, math.floor(code / 1000)) or nil,
        bearing = f.bearing,
    }
end

-- The guidance target on foot: the nearest entrance, street beginning or climb's foot within
-- reach; the one guided to last (`prefer`, its position) stays unless another is nearer by more
-- than GUIDE_STICK.
function logic.footTarget(zone, x, y, square, prefer)
    local candidates = {
        entranceTarget(zone, x, y, GUIDE_REACH, prefer),
        beginningTarget(zone, x, y, GUIDE_REACH, square, prefer),
        climbTarget(zone, x, y, GUIDE_REACH, prefer),
    }
    local best, kept = nil, nil
    for _, t in pairs(candidates) do
        if best == nil or t.d < best.d then
            best = t
        end
        if logic.samePoint(t, prefer) then
            kept = t
        end
    end
    if kept and best ~= kept and logic.sticks(best.d, kept.d) then
        return kept
    end
    return best
end

logic.GUIDE_SIDE = 1.5 -- yd beside the line through a doorway before one is at it
-- yd beside a climb's line at its foot (user 2026-10-01: the griffon ramp is 5 yd wide, its
-- compass word 14 degrees off its line, so a start 1.5 yd to the wrong side ended over its rim
-- within 8 yd; "make ramp entries more precise")
logic.GUIDE_SIDE_CLIMB = 1.0

-- Is the player at the target: within GUIDE_AT, and for a doorway (a target with the way
-- through) no farther than GUIDE_SIDE beside the line through it, so "in to the southwest" does
-- not lead into the wall beside the door (user 2026-10-01 at the Hall of Champions: "at the
-- entrance" 2.6 yd beside the doorway, then the wall three times); at a climb's foot within
-- GUIDE_SIDE_CLIMB of its line, which the data gives in degrees (finer than the compass word).
-- The unit vector of the way through a target: the data's bearing (degrees, 0 north, 90 east)
-- where it has one, else the compass word.
local function throughVector(t)
    if t.bearing then
        local a = math.rad(t.bearing)
        return math.cos(a), -math.sin(a)   -- 0 north (+x), 90 east (-y)
    end
    return logic.compassVector(t.through)
end

function logic.atTarget(zone, t, x, y)
    if t.d > logic.GUIDE_AT then
        return false
    end
    if t.kind == "way" or not t.through then
        return true
    end
    local fx, fy = throughVector(t)
    local side = t.kind == "climb" and logic.GUIDE_SIDE_CLIMB or logic.GUIDE_SIDE
    return math.abs((t.x - x) * fy - (t.y - y) * fx) <= side
end

-- Is the player past a climb's foot: more than GUIDE_AT yards beyond it along the way up? Then
-- the foot is no target any more (user 2026-10-01: the foot was dropped as soon as the place
-- said "ramp", which the junction stretch did 2 yd before the foot, so "hinauf nach Südosten"
-- never came).
function logic.pastTarget(zone, t, x, y)
    if not t.through then
        return false
    end
    local fx, fy = throughVector(t)
    return (x - t.x) * fx + (y - t.y) * fy > logic.GUIDE_AT
end

-- The nearest way out of the water within reach, while swimming; one onto floor that joins
-- nothing or into a dead end says so.
function logic.exitTarget(zone, x, y, moat)
    local i, d, dir, exit = logic.nearestExit(zone, x, y, moat and MOAT_EXIT_REACH or EXIT_REACH)
    if i == nil then
        return nil
    end
    local dead = exit.dead
    local name = moat and L["way out of the moat"] or L["way out of the water"]
    return {
        key = i, kind = "exit", d = d, dir = dir, x = exit.x, y = exit.y,
        name = dead and L["way out of the water to a dead end"] or name,
        short = dead and L["way out to a dead end"] or L["way out"],
        atName = dead and L["at the way out to a dead end"] or L["at the way out"],
        at = dead and L["at the way out to a dead end"] or L["at the way out"],
        through = exit.out, throughFormat = T("out to the %s"),
    }
end

-- The text for a guidance target: by name (`named`, the first time) or its short word, with
-- distance and direction, or that the player is `at` it; and the way through it (into the
-- building, out of the water, on along the street): on the first naming only when it goes another
-- way than the direction to the target ("entrance, 6 to the northeast" goes in northeast), at the
-- target itself always.
-- At an entrance or doorway only the way through ("in to the southwest"); while the guidance
-- stays on one, a repeat is the yards and the direction alone ("7 southwest"): the first
-- announcement named it (user 2026-10-01).
function logic.guideText(zone, t, named, at)
    local door = t.kind == "entrance" or t.kind == "doorway" or t.kind == "climb"
    local parts = {}
    if at then
        if door and t.through then
            return string.format(t.throughFormat, logic.dirWord(zone, t.through))
        end
        parts[1] = named and t.atName or t.at
    elseif door and not named then
        return string.format(T("%d %s"), math.max(1, math.floor(t.d + 0.5)), logic.dirWord(zone, t.dir, true))
    else
        parts[1] = named and t.name or t.short
        parts[2] = string.format(T("%d to the %s"), math.floor(t.d + 0.5), logic.dirWord(zone, t.dir, true))
    end
    if t.through and (at or (named and not logic.sameDir(t.through, t.dir))) then
        parts[#parts + 1] = string.format(t.throughFormat, logic.dirWord(zone, t.through))
    end
    return table.concat(parts, ", ")
end

-- Spots -------------------------------------------------------------------------------------------

-- A square's exits (streets, roads, squares that lead on; nearest first) and the water, canals
-- and cliff edges within APPROACH yards, which are marked in `said`; the building entrances on it
-- only without `cut` (the announcements leave them to the entrance guidance).
local function squareItems(zone, x, y, region, cut, previous, said)
    local opts = { dirs = logic.ITEM_DIRS, classes = { way = true }, leading = true, zone = zone }
    if cut then
        opts.max = ITEMS_MAX
        opts.cameFrom = logic.keyLabel(zone, previous)
    end
    local items = logic.aroundItems(region, x, y, opts)
    for _, item in ipairs(logic.approaching(region, x, y, APPROACH, said, logic.ITEM_DIRS)) do
        items[#items + 1] = item
    end
    if not cut then
        local classes = { entrance = true, room = true }
        for _, item in ipairs(logic.aroundItems(region, x, y, { dirs = logic.ITEM_DIRS, classes = classes })) do
            items[#items + 1] = item
        end
    end
    return items
end

-- Cliffs and water near an outdoor place: "forest, cliff edge to the west and north". Not on roads
-- nor what the place itself is; announcements also leave out what the player just left (the shore
-- behind them).
local function featuresText(zone, x, y, kind, previous, cut)
    if FEATURE_SKIP[kind] then
        return nil
    end
    local skip = {}
    if FEATURES[kind] then
        skip[FEATURES[kind]] = true
    end
    local before = cut and FEATURES[logic.kind(zone, logic.keyPlace(previous))]
    if before then
        skip[before] = true
    end
    local items = logic.featuresAround(zone, x, y, FEATURE_REACH, FEATURES, skip)
    if #items == 0 then
        return nil
    end
    return logic.itemsText(zone, items)
end

-- The outdoor spot of a cell value: the place, its direction and nearest road; on a road, street
-- or walk which way to turn to face along it (with `opts.facing`), only where the words cannot
-- tell; on a square its exits and what is close; elsewhere where a road or street is (within
-- ROAD_SIDE_REACH, off a way; announcements only on stepping off one) and the cliffs and water
-- near (not while `opts.swimming`). opts.cut: an announcement (see the top). Returns the text, and
-- on a square its region and the set of its mouths said now.
local function spotBody(zone, x, y, value, previous, opts)
    local text = logic.describe(zone, value, true)
    if text == nil then
        return nil
    end
    local kind = logic.kindOf(zone, value)
    if logic.isAroundPlace(zone, value) then
        -- (a square beside a way decided by its centre line may lie off the player's own cell)
        local region = logic.regionAt(zone, x, y)
        if region == nil then
            return text
        end
        local said = logic.wayMouths(region)
        local items = squareItems(zone, x, y, region, opts.cut, previous, said)
        if #items > 0 then
            text = text .. ", " .. logic.itemsText(zone, items)
        end
        return text, region, said
    end
    -- off a way: where the nearest road or street is (the same rule for both; in a city the word
    -- is street)
    local wasWay = logic.LANE_KINDS[logic.kind(zone, logic.keyPlace(previous))]
    if not logic.LANE_KINDS[kind] and (wasWay or not opts.cut) then
        -- toward the way's centre line where it has one: across the way, so it does not flicker
        local d, dir, street
        local ld, lane, lx, ly = logic.nearestLane(zone, x, y, ROAD_SIDE_REACH, logic.LANE_KINDS)
        if ld then
            d, dir, street = ld, logic.bearingOf(lx - x, ly - y), not logic.ROADS[lane.kind]
        else
            d, dir = logic.nearestOfKinds(zone, x, y, logic.ROADS, ROAD_SIDE_REACH)
            local sd, sdir = logic.nearestOfKinds(zone, x, y, STREETS, ROAD_SIDE_REACH)
            if sd and (d == nil or sd < d) then
                d, dir, street = sd, sdir, true
            end
        end
        if d then
            -- instead of the place's stored nearest road, which may be another one
            local format = street and T("street to the %s") or T("road to the %s")
            text = logic.describe(zone, value, true, true) .. ", " .. string.format(format, logic.dirWord(zone, dir))
        end
    end
    local near = not opts.swimming and featuresText(zone, x, y, kind, previous, opts.cut)
    if near then
        text = text .. ", " .. near
    end
    return text
end

-- The spot text (spotBody) with the turn hint last, after the description is complete and its
-- "o'clock" placed ("street, 10 to 4 o'clock, left"; the hint stood inside the text and the
-- "o'clock" landed after it, user 2026-10-01).
function logic.spotText(zone, x, y, value, previous, opts)
    local text, region, said = spotBody(zone, x, y, value, previous, opts)
    if text == nil then
        return nil
    end
    local kind = logic.kindOf(zone, value)
    if opts.facing and logic.LANE_KINDS[kind] then
        local hint = logic.turnHint(zone, x, y, opts.facing, logic.axisOf(zone, value))
        if hint and hint ~= 0 then
            text = logic.finishText(text) .. ", " .. logic.turnText(hint)
        end
    end
    return text, region, said
end

-- A room: its name (with the building's when it changes), the way it runs when it is long and
-- narrow ("passage of Ironforge, north to south") or which way its winding stairs turn, and its
-- doorways, each with the fixed direction one passes through it leaving the room, or in a big room
-- the direction from the player (x, y) to it; announcements (`cut`) at most ITEMS_MAX, the doorway
-- the player came through left out first.
function logic.roomText(zone, id, previous, cut, x, y)
    local text = logic.describeRoom(zone, id, previous)
    if text == nil then
        return nil
    end
    local room = zone._index.rooms[id]
    if room.winding then
        text = text .. ", " .. (room.winding > 0 and L["winding, turns left going up"] or L["winding, turns right going up"])
    elseif room.axis then
        text = text .. ", " .. logic.axisWords(zone, room.axis)
    end
    local opts = { dirs = logic.ITEM_DIRS, x = x, y = y }
    if cut then
        opts.max = ITEMS_MAX
        opts.cameFrom = previous or 0
    end
    local items = logic.roomDoorways(zone, id, opts)
    if #items > 0 then
        text = text .. ", " .. logic.itemsText(zone, items)
    end
    return text
end

-- On a square: the streets, water and squares not said yet (`said`) that come within APPROACH.
function logic.approachText(zone, region, x, y, said)
    local items = logic.approaching(region, x, y, APPROACH, said, logic.ITEM_DIRS)
    if #items > 0 then
        return logic.itemsText(zone, items)
    end
end
