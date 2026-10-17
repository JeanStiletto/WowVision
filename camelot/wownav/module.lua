-- WowNav routes in WowVision (WoW: Forever). With the setting on, every route request of the navigation (the
-- scanner's Enter, the places list, /beacon to, the F10 window) goes to WowNav's network instead of the route data:
-- WowNav finds the entry point, binds the target and searches the route (in time slices); WowVision walks it with
-- its own beacon (path.lua). Its creature and object catalog joins the F10 list, and the route data's spawns leave
-- it. A floor is asked only when there is a choice: where floors are stacked and nothing tells which one the player
-- or the target is on. A route that reaches a portal, the tram or a lift ends there; once the player comes out at its
-- other end, the route to the target goes on by itself.
--
-- The network is the WowNav submodule (mapdata/WowNav, branch wv-engine), loaded through its engine.xml: only the
-- network and the zone files, packed as text until a route needs a zone; never WowNav's own core, commands or keys.
-- With the standalone WowVisionNavigation addon loaded as well, this stays off (both would share the globals).

local maps = WowVision.base.navigation.maps
local logic = WowVision.wownavLogic

local module = WowVision.base.navigation:createModule("wownav")
local L = module.L
module:setLabel(L["WowNav Routes"])

local settings = module:hasSettings()
settings:add({ key = "enabled", type = "Bool", label = L["Routes from WowNav"], default = false })
-- WowNav's comfort level: a road route may be up to this many percent longer than the shortest way.
settings:add({ key = "comfort", type = "Number", label = L["Road Preference (Percent Longer)"], default = 50, min = 0, max = 300 })

local BUDGET_MS = 8          -- search time per frame
local START_TRIES = 4        -- start attachments tried when the first finds no way (WowNav RouteFromStart)
local SLOW_NOTICE = 1.0      -- seconds before "calculating route" is said
local CONTINUE_REACH = 25    -- yd around a transit's far end that count as having come out there
local CONTINUE_TIME = 600    -- seconds a route waits for the player to use the transit
local RECALC_DELAY = 1.0     -- seconds after the last change of the road preference before the route is searched again

local job = nil              -- the pending search: { target, starts, index, jobs, startedAt, noticed }
local continuation = nil     -- after a transit: { target, x, y, map, until }
local recalcAt = nil         -- when the running route is searched again with a changed road preference

function module:network()
    return _G.WowVisionNavigationNavNetwork, _G.WowVisionNavigationGuidance
end

local function standaloneLoaded()
    return C_AddOns ~= nil and C_AddOns.IsAddOnLoaded ~= nil and C_AddOns.IsAddOnLoaded("WowVisionNavigation")
end

local indexed = false
local function ready(self)
    local N = self:network()
    if N == nil or N.RouteJob == nil or type(_G.WVN7Index) ~= "table" then
        return nil
    end
    if not indexed then
        N.LoadIndex()
        N.ActionAllowed = logic.actionAllowed
        indexed = true
    end
    N.SetComfort(self.settings.comfort or 50)
    return N
end

-- ---- the engine maps calls (core/navigation/maps/module.lua setRouteEngine)
local engine = {}

function engine:isActive()
    return module:getEnabled() and module.settings.enabled == true and not standaloneLoaded() and ready(module) ~= nil
end

function engine:hidesRouteDataSpawns()
    return true
end

function engine:routeTo(target)
    return module:routeTo(target)
end

function engine:destinations(px, py, map)
    return module:destinations(px, py, map)
end

maps:setRouteEngine(engine)

-- ---- speech
local function say(text)
    WowVision:speak(text)
end

local TRANSIT_WORDS = { portal = "portal", tram = "tram", lift = "lift" }

function module:onRejoined()
    say(L["Back on the route"])
end

-- ---- destinations: the WowNav catalog of the zones the player is in
local catalogZones = {}

function module:destinations(px, py, map)
    local N = ready(self)
    if N == nil then
        return {}
    end
    local german = GetLocale ~= nil and GetLocale() == "deDE"
    local out, here = {}, {}
    for _, zone in ipairs(logic.zonesAt(N, px, py, map)) do
        here[zone.id] = true
        for _, wp in ipairs(logic.zoneDestinations(N, zone.id, german)) do
            out[#out + 1] = wp
        end
    end
    -- catalogs of zones left behind go back to text
    for id in pairs(catalogZones) do
        if not here[id] then
            N.DropTargets(id)
        end
    end
    catalogZones = here
    return out
end

-- ---- floors: asked only when there is a choice
local floorChoice = nil

function module:floorChoice()
    return floorChoice
end

local function askFloor(kind, floors, onChoose)
    floorChoice = { kind = kind, floors = floors, onChoose = onChoose }
    WowVision.UIHost:openWindow("wownavFloors")
end

function module:chooseFloor(floor)
    local choice = floorChoice
    floorChoice = nil
    WowVision.UIHost:closeWindow("wownavFloors")
    if choice ~= nil then
        choice.onChoose(floor)
    end
end

-- ---- the route request
local function finishRoute(self, target, result, startBinding)
    local N = self:network()
    local px, py, _, map = UnitPosition("player")
    local waypoints, action = logic.buildWaypoints(N, result)
    -- keep the route's virtual points and zones (the player's zone too), drop the rest
    local keepIds = {}
    for _, wp in ipairs(waypoints) do
        keepIds[#keepIds + 1] = wp.id
    end
    N.KeepVirtual(keepIds)
    local zonesHere = {}
    if px ~= nil then
        for _, zone in ipairs(logic.zonesAt(N, px, py, map)) do
            zonesHere[#zonesHere + 1] = zone.id
        end
    end
    N.KeepZones(logic.routeZones(N, result, zonesHere))

    local last = waypoints[#waypoints]
    local lastLeg = 0
    if action == nil and last ~= nil then
        lastLeg = logic.distance(last.x, last.y, target.x, target.y)
        if lastLeg > logic.FINAL_GAP then
            waypoints[#waypoints + 1] = { x = target.x, y = target.y, z = target.z, n = target.label, final = true }
        end
    elseif action == nil then
        waypoints[1] = { x = target.x, y = target.y, z = target.z, n = target.label, final = true }
    end
    if action ~= nil and #waypoints > 0 then
        waypoints[#waypoints].n = target.label
    end

    local path = WowVision.WowNavPath:new(self)
    for _, wp in ipairs(waypoints) do
        path:add(wp)
    end
    path.transit = action
    path.events.complete:subscribe(self, function()
        maps.path = nil
        if path.transit ~= nil then
            self:transitReached(target, path.transit)
            return
        end
        WowVision:speak(L["Arrived"] .. (target.label ~= nil and (" " .. target.label) or ""))
        if target.onArrive ~= nil then
            target.onArrive()
        end
    end)
    maps:pathfind(path)
    self.path = path

    local count = #waypoints
    local yards = px ~= nil and logic.routeLength(waypoints, px, py) or result.length
    local text = string.format("%d %s, %d %s", count, L["waypoints"], yards, L["yards"])
    lastLeg = math.floor(lastLeg + 0.5)
    if action == nil and lastLeg > maps:arrivalDistance() then
        text = text .. ", " .. string.format(L["last %d yards direct"], lastLeg)
    end
    if action ~= nil then
        local word = L[TRANSIT_WORDS[action.kind] or "transit"]
        text = text .. ", " .. string.format(L["then the %s"], word)
    end
    say(text)
end

-- A route ended at a portal, the tram or a lift: say so, and go on once the player comes out at its far end.
function module:transitReached(target, action)
    local N = self:network()
    local word = L[TRANSIT_WORDS[action.kind] or "transit"]
    say(string.format(L["Use the %s; the route goes on after it"], word))
    local zoneId = action.toZoneId or math.floor(action.toNode / N.ZONE_BASE)
    N.LoadZone(zoneId)
    local x, y = N.Position(action.toNode)
    continuation = { target = target, x = x, y = y, map = action.toNativeMap, untilTime = GetTime() + CONTINUE_TIME }
end

local function checkContinuation(self)
    local c = continuation
    if c == nil or job ~= nil then
        return
    end
    if GetTime() > c.untilTime then
        continuation = nil
        return
    end
    local px, py, _, map = UnitPosition("player")
    if px == nil or (c.map ~= nil and map ~= c.map) then
        return
    end
    if logic.distance(px, py, c.x, c.y) <= CONTINUE_REACH then
        continuation = nil
        say(L["The route goes on"])
        self:routeTo(c.target)
    end
end

-- Starts the search for a target { x, y, z, label, onArrive, floorZ }. True when WowNav took it.
function module:routeTo(target)
    local N = ready(self)
    if N == nil then
        return false
    end
    local px, py, _, map = UnitPosition("player")
    if px == nil or not logic.coversMap(N, map) then
        return false
    end
    local zonesHere = logic.zonesAt(N, px, py, map)
    if #zonesHere == 0 then
        return false
    end
    job = nil
    continuation = nil
    local swimming = IsSwimming ~= nil and IsSwimming() or false

    -- the start: the route state and the last height decide a stacked cell, else the player
    local opts = { swimming = swimming, zones = zonesHere, lastHeight = self.lastHeight }
    if self.path ~= nil and maps.path == self.path then
        opts.preferred = self.path:nodeSet()
    end
    local starts, why = N.StartBindings(px, py, nil, opts)
    if starts == nil and why == "ambiguous" then
        local floors = logic.floorsAt(N, px, py, swimming)
        if #floors > 1 then
            askFloor("start", floors, function(floor)
                self.lastHeight = floor.z
                self:routeTo(target)
            end)
            return true
        end
    end
    if starts == nil then
        say(L["No WowNav network here"])
        return false
    end

    -- the target: its own height, else the floor chosen, else asked when its spot has several floors
    local tz = target.z or target.floorZ
    if tz == nil then
        local floors = logic.floorsAt(N, target.x, target.y, false)
        if #floors > 1 then
            askFloor("target", floors, function(floor)
                target.floorZ = floor.z
                self:routeTo(target)
            end)
            return true
        end
    end
    local goal = N.Bind(target.x, target.y, tz, { radius = logic.TARGET_REACH })
    if goal == nil then
        say(L["No WowNav network at the target"])
        return false
    end
    self.target = target
    job = { target = target, goal = goal, starts = starts, index = 1, startedAt = GetTime() }
    job.current = N.RouteJob(starts[1], goal)
    return true
end

local function stepJob(self)
    local j = job
    if j == nil then
        return
    end
    local done, result, reason = j.current:Step(BUDGET_MS, debugprofilestop)
    if not done then
        if not j.noticed and GetTime() - j.startedAt >= SLOW_NOTICE then
            j.noticed = true
            say(L["Calculating route"])
        end
        return
    end
    if result == nil and j.index < math.min(#j.starts, START_TRIES) then
        local N = self:network()
        j.index = j.index + 1
        j.current = N.RouteJob(j.starts[j.index], j.goal)
        return
    end
    job = nil
    if result == nil then
        say(L["No route found"] .. (reason ~= nil and (" " .. tostring(reason)) or ""))
        return
    end
    finishRoute(self, j.target, result, j.starts[j.index])
end

-- The target of the route being searched or walked, nil without one (arrived, ended at a transit, stopped).
function module:runningTarget()
    if job ~= nil then
        return job.target
    end
    local path = self.path
    if path ~= nil and maps.path == path and path.active and not path.complete then
        return self.target
    end
    return nil
end

-- A changed road preference applies to the running route as well (WowNav's /vn komfort does the same): once the
-- slider has rested for RECALC_DELAY, the same target is searched again from where the player is.
local function checkRecalculation(self)
    if recalcAt == nil or GetTime() < recalcAt then
        return
    end
    recalcAt = nil
    local target = self:runningTarget()
    if target ~= nil then
        say(L["Searching the route again with the new road preference"])
        self:routeTo(target)
    end
end

function module:onEnable()
    self:hasUpdate(function(self)
        stepJob(self)
        checkContinuation(self)
        checkRecalculation(self)
    end)
end

module.settings.class:getField("comfort").events.valueChange:subscribe(module, function()
    if module:runningTarget() ~= nil then
        recalcAt = GetTime() + RECALC_DELAY
    end
end)

-- With the setting turned on while the standalone addon runs, say why nothing changes.
module.settings.class:getField("enabled").events.valueChange:subscribe(module, function(_, _, _, _, value)
    if value == true and standaloneLoaded() then
        say(L["Turn off the WowVisionNavigation addon to use its routes here"])
    end
end)
