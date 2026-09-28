-- Surroundings: the spoken texts. One description of a spot, the same for the announcements and
-- the describe key: what is said depends only on where the player stands and the fixed map, never
-- on how they got there. The announcements (`cut`) may only leave things out: what was just said
-- (the way the player came, `previous`: the outdoor key before) and more than ITEMS_MAX things.

local logic = WowVision.surroundingsLogic
local L = WowVision:getLocale()

local ITEMS_MAX = 4 -- things said at most on entering a square or a room
local APPROACH = 10 -- yd; on a square, a street, water or drop not said yet is said this close
local FEATURE_REACH = 25 -- yd; cliffs and water said with an outdoor place
local ROAD_SIDE_REACH = 12 -- yd; off a road, where it is is said within this
local GUIDE_REACH = 8 -- yd; entrances and street beginnings are guided to from this close
local EXIT_REACH = 25 -- yd; ways out of the water guided to while swimming
logic.GUIDE_AT = 3 -- yd from a target that count as being at it

-- The names of the item classes that are their own word; the others (ways, rooms) carry a name.
local NAMED_CLASSES = { way = true, room = true, entrance = true }
local TURN_WORDS = { [-1] = "turn slightly right", [1] = "turn slightly left" }
-- the kinds said as cliffs and water near an outdoor place, and their words
local FEATURES = { ["cliff edge"] = "cliff edge", ["cliff foot"] = "rock wall", ["deep water"] = "water", shore = "water" }
-- places that say no cliffs and water: roads (they come often) and the water itself
local FEATURE_SKIP = { road = true, fork = true, crossing = true, bridge = true, ["deep water"] = true, canal = true }

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
        local name = item.label
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
                words[#words + 1] = zone.compass[dir]
            end
            parts[#parts + 1] = string.format(L["%s to the %s"], name, logic.joinWords(words))
        end
    end
    return table.concat(parts, ", ")
end

-- A drop edge: the direction first, then the drop ("southeast, drop into canal"; the drop already
-- says it is an edge); with `ahead` (yd along the path) its distance. Per edge's `into`: a plain
-- drop, into water, into a city canal; each said beside it and ahead.
local EDGE_TEXTS = {
    [0] = { "%s, drop %d yards", "%s in %d yards, drop %d yards" },
    [1] = { "%s, drop into water", "%s in %d yards, drop into water" },
    [2] = { "%s, drop into canal", "%s in %d yards, drop into canal" },
}

function logic.edgeText(zone, i, ahead)
    local e = logic.edge(zone, i)
    local texts = EDGE_TEXTS[e.into] or EDGE_TEXTS[0]
    local word = zone.compass[e.facing]
    if ahead then
        local yards = math.max(1, math.floor(ahead + 0.5))
        return string.format(L[texts[2]], word, yards, e.drop)
    end
    return string.format(L[texts[1]], word, e.drop)
end

-- Guidance targets -------------------------------------------------------------------------------
-- A target {key (unique among the targets of one guide), kind, x, y, d, dir (distance and compass
-- index from the player), name and short (its text the first time and after), atName and at (at the
-- target), through (the compass index of the way through it) and throughFormat}.

local function entranceTarget(zone, x, y, reach)
    local i, d, dir, e = logic.nearestEntrance(zone, x, y, reach)
    if i == nil then
        return nil
    end
    return {
        key = "e" .. i, kind = "entrance", d = d, dir = dir, x = e.x, y = e.y,
        name = string.format(L["entrance of %s"], e.text), short = L["entrance"],
        atName = string.format(L["at the entrance of %s"], e.text), at = L["at the entrance"],
        through = e.inDir, throughFormat = L["in to the %s"],
    }
end

-- Where a street (road, bridge, canal walk) begins on the square the player is on (or, just off
-- it, `square`); streets that run along the square's side are no target (see wayBeginnings).
local function beginningTarget(zone, x, y, reach, square)
    square = logic.regionAt(zone, x, y) or square
    if square == nil then
        return nil
    end
    local i, d, dir, b = logic.nearestBeginning(zone, square, x, y, reach)
    if i == nil then
        return nil
    end
    return {
        key = "w" .. b.label .. "@" .. math.floor(b.x) .. "," .. math.floor(b.y), kind = "way", d = d, dir = dir,
        x = b.x, y = b.y,
        name = b.label, short = L[b.kind],
        atName = string.format(L["at the %s"], b.label), at = string.format(L["at the %s"], L[b.kind]),
        through = b.onward, throughFormat = L["on to the %s"],
    }
end

-- The guidance target on foot: the nearest entrance or street beginning within reach.
function logic.footTarget(zone, x, y, square)
    local t = entranceTarget(zone, x, y, GUIDE_REACH)
    local w = beginningTarget(zone, x, y, GUIDE_REACH, square)
    if w and (t == nil or w.d < t.d) then
        return w
    end
    return t
end

-- The nearest way out of the water within reach, while swimming.
function logic.exitTarget(zone, x, y)
    local i, d, dir, exit = logic.nearestExit(zone, x, y, EXIT_REACH)
    if i == nil then
        return nil
    end
    return {
        key = i, kind = "exit", d = d, dir = dir, x = exit.x, y = exit.y,
        name = L["way out of the water"], short = L["way out"],
        atName = L["at the way out"], at = L["at the way out"],
        through = exit.out, throughFormat = L["out to the %s"],
    }
end

-- The text for a guidance target: by name (`named`, the first time) or its short word, with
-- distance and direction, or that the player is `at` it; and the way through it (into the
-- building, out of the water, on along the street): on the first naming only when it goes another
-- way than the direction to the target ("entrance, 6 to the northeast" goes in northeast), at the
-- target itself always.
function logic.guideText(zone, t, named, at)
    local parts = {}
    if at then
        parts[1] = named and t.atName or t.at
    else
        parts[1] = named and t.name or t.short
        parts[2] = string.format(L["%d to the %s"], math.floor(t.d + 0.5), zone.compass[t.dir])
    end
    if t.through and (at or (named and t.through ~= t.dir)) then
        parts[#parts + 1] = string.format(t.throughFormat, zone.compass[t.through])
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
        for _, item in ipairs(logic.aroundItems(region, x, y, { dirs = logic.ITEM_DIRS, classes = { entrance = true } })) do
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
-- tell; on a square its exits and what is close; elsewhere where a road is (within
-- ROAD_SIDE_REACH, off a road; announcements only on stepping off one) and the cliffs and water
-- near (not while `opts.swimming`). opts.cut: an announcement (see the top). Returns the text, and
-- on a square its region and the set of its mouths said now.
function logic.spotText(zone, x, y, value, previous, opts)
    local text = logic.describe(zone, value, true)
    if text == nil then
        return nil
    end
    local kind = logic.kindOf(zone, value)
    if opts.facing and logic.LANE_KINDS[kind] then
        local hint = logic.turnHint(zone, x, y, opts.facing, logic.axisOf(zone, value))
        if hint and hint ~= 0 then
            text = text .. ", " .. L[TURN_WORDS[hint]]
        end
    end
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
    local wasRoad = logic.ROADS[logic.kind(zone, logic.keyPlace(previous))]
    if not logic.ROADS[kind] and (wasRoad or not opts.cut) then
        -- toward the road's centre line where it has one: across the road, so it does not flicker
        local d, dir
        local ld, _lane, lx, ly = logic.nearestLane(zone, x, y, ROAD_SIDE_REACH, logic.ROADS)
        if ld then
            d, dir = ld, logic.compassIndex(lx - x, ly - y)
        else
            d, dir = logic.nearestOfKinds(zone, x, y, logic.ROADS, ROAD_SIDE_REACH)
        end
        if d then
            -- instead of the place's stored nearest road, which may be another one
            text = logic.describe(zone, value, true, true) .. ", " .. string.format(L["road to the %s"], zone.compass[dir])
        end
    end
    local near = not opts.swimming and featuresText(zone, x, y, kind, previous, opts.cut)
    if near then
        text = text .. ", " .. near
    end
    return text
end

-- A room: its name (with the building's when it changes) and its doorways, each with the fixed
-- direction one passes through it leaving the room; announcements (`cut`) at most ITEMS_MAX, the
-- doorway the player came through left out first.
function logic.roomText(zone, id, previous, cut)
    local text = logic.describeRoom(zone, id, previous)
    if text == nil then
        return nil
    end
    local opts = { dirs = logic.ITEM_DIRS }
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
