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
    key = "roomDistance",
    type = "Number",
    label = L["Entry Distance Indoors (yards)"],
    default = 3,
    min = 0,
    max = 20,
})

local alert = module:addAlert({ key = "place", label = L["Surroundings Announcements"] })
alert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return message.text
    end,
})
settings:addRef("place", alert.parameters)

local zone = nil                 -- the zone data the player is in (unpacked)
local outdoor = logic.newEntry(8)
local indoor = logic.newEntry(3)
local wasIndoors = nil
local lastCheck = 0
local lastRoom = nil             -- the last announced room, for the interior name
local room = nil                 -- the room the player is in as far as known (switches at once)
local lastX, lastY = nil, nil    -- the previous position, for walking through doorways

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
        outdoor:reset()
        indoor:reset()
        lastRoom, room = nil, nil
    end
    return zone
end

local function say(text)
    if text and text ~= "" then
        module:fireAlert("place", { text = text })
    end
end

-- The outdoor place key and value at a position (bridges while swimming: the water below).
local function outdoorValue(z, x, y)
    local value, r, c = logic.valueAt(z, x, y)
    if value == 0 then
        return nil, 0
    end
    local place = logic.placeOf(value)
    if logic.kind(z, place) == "bridge" and IsSwimming() then
        local under = logic.underBridge(z, r, c)
        if under then
            return under, under * 100
        end
    end
    return place, value
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
    local z = findZone(x, y, map)
    if z == nil then
        return
    end
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
            say(logic.describeRoom(z, room, lastRoom))
            lastRoom = room
        end
        return
    end
    lastRoom = nil
    local place, value = outdoorValue(z, x, y)
    if outdoor:update(place, x, y) then
        if logic.kind(z, place) == "open land" and not self.settings.announceOpenLand then
            return
        end
        say(logic.describe(z, value, self.settings.directions))
    end
end)

-- /wv surr: what the module knows here, spoken and printed.
module:registerCommand({
    name = "surr",
    description = "Surroundings: speak the current place or room and the data state",
    func = function(args)
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
                if IsIndoors() then
                    local cands = logic.roomCandidates(z, x, y)
                    local names = {}
                    for _, id in ipairs(cands) do
                        names[#names + 1] = logic.describeRoom(z, id, nil)
                    end
                    parts[#parts + 1] = "Indoors. Room candidates: " .. (#names > 0 and table.concat(names, "; ") or "none")
                    parts[#parts + 1] = "Current room: " .. (room and logic.describeRoom(z, room, nil) or "unknown")
                end
            end
        end
        for _, line in ipairs(parts) do
            print(line)
        end
        WowVision:speak(table.concat(parts, ". "))
    end,
})
