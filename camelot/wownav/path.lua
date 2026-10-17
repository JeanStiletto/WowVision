-- A route from WowNav, walked by WowVision: the normal Path (beacon, arrival cue, Ctrl-W/S, Shift-F12, the turn key
-- all read it as before), with WowNav's rules for moving on to the next waypoint instead of one radius for all:
-- each waypoint's own radius from the data (WowVision's arrival radius, Alt-P, only makes it smaller), the gate line
-- at narrow spots, the turning point in the open; and back
-- onto the route when the player is off it (a later waypoint whose cell holds the player, no new route).

local maps = WowVision.base.navigation.maps
local logic = WowVision.wownavLogic

local WowNavPath = WowVision.Class("WowNavPath", maps.Path)
WowVision.WowNavPath = WowNavPath

-- engine: the wownav module (it speaks and knows the network); final radius of the target point: WowVision's
-- arrival distance.
function WowNavPath:initialize(engine)
    maps.Path.initialize(self)
    self.engine = engine
    self.watch = {}
end

function WowNavPath:start()
    maps.Path.start(self)
    self.px, self.py = nil, nil
    self.watch = {}
end

function WowNavPath:moveBy(offset)
    local waypoint = maps.Path.moveBy(self, offset)
    if waypoint ~= nil then
        self.px, self.py = nil, nil
        self.watch = {}
    end
    return waypoint
end

-- The waypoint IDs of the route (route state: a stacked start cell attached to one of them wins).
function WowNavPath:nodeSet()
    local set = {}
    for _, wp in ipairs(self.waypoints) do
        if wp.id ~= nil then
            set[wp.id] = true
        end
    end
    return set
end

local function advance(self)
    self.events.arriveAtWaypoint:emit(self, self.currentWaypoint)
    self.currentIndex = self.currentIndex + 1
    self.currentWaypoint = self.waypoints[self.currentIndex]
    self.watch = {}
    if self.currentWaypoint then
        self.beacon = maps.Beacon:new(self.currentWaypoint)
    else
        self.beacon = nil
    end
end

function WowNavPath:update()
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
    local N, G = self.engine:network()
    local swimming = IsSwimming ~= nil and IsSwimming() or false
    local wp = self.currentWaypoint
    local z = logic.heightAlong(self.waypoints[self.currentIndex - 1], wp, x, y, swimming)
    if z ~= nil then
        self.engine.lastHeight = z
    end
    local reached = N ~= nil and logic.reached(N, G, self.waypoints, self.currentIndex, {
        x = x, y = y, px = self.px, py = self.py, z = z, swimming = swimming,
        finalRadius = maps:arrivalDistance(), radiusCap = maps:arrivalDistance(),
    })
    if reached then
        advance(self)
    elseif N ~= nil and not wp.final then
        local moving = (IsPlayerMoving ~= nil and IsPlayerMoving()) or false
        if logic.offRoute(self.watch, GetTime(), x, y, wp.x, wp.y, moving) then
            -- off the route the route's height says little: it only decides where floors are stacked here
            local stacked = #logic.floorsAt(N, x, y, swimming) > 1
            local index = logic.rejoinIndex(N, G, self.waypoints, self.currentIndex, x, y, stacked and z or nil, swimming)
            if index ~= nil and index > self.currentIndex then
                self.currentIndex = index
                self.currentWaypoint = self.waypoints[index]
                self.beacon = maps.Beacon:new(self.currentWaypoint)
                self.watch = {}
                self.engine:onRejoined()
            end
        end
    end
    self.px, self.py = x, y
    if self.beacon then
        self.beacon:update()
    end
end
