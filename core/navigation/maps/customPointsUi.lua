-- Custom points in the game (user request 2026-11-27; the store logic is core/navigation/customPoints.lua):
--   Alt+Ctrl+W  a new custom waypoint: the current position or typed map coordinates, then a name
--   Alt+Ctrl+D  a new custom danger point: the current position or typed map coordinates; no name asked ("Monster
--               spawn", renamed in the list when wanted)
-- Both kinds join the destinations (module:destinationWaypoints: F10, /beacon to, Auto Route). The WowVision menu's
-- Navigation page has a "Custom Points" button that lists them with Rename and Delete (Shift+F10 on a point); Enter
-- on one opens F10 aimed at it. A route engine's safe routes count the danger points
-- (customPointsChanged tells it when they change; camelot/wownav/module.lua). Its argument says what changed: "danger"
-- (the danger points or the store itself), "waypoint" (the waypoints), "rename" (only a name).
-- Kept per account (the module's account store); the points the addon ships (customPoints.shipped) are handed over
-- once and never replace the player's.

local module = WowVision.base.navigation.maps
local L = module.L
local cp = WowVision.customPoints

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

local NEW_WINDOW = "customPointNew"
local KIND_WORDS = {
    waypoint = function()
        return L["Custom waypoint"]
    end,
    danger = function()
        return L["Danger point"]
    end,
}

module.customPointsChanged = WowVision.Event:new("customPointsChanged")

-- The points are written into whatever account store is bound, as every other account value is: on WoW: Forever the
-- client hands its account file over after the addon loaded (core/WowVision.lua bindGlobalStore), and a point saved
-- in that short gap stays in the provisional table, which becomes the account's only when the client never hands one
-- over (user decision 2026-11-27). The store is read fresh on every access, so the client's points show once it is
-- adopted.
local storeData = nil   -- the saved table the store was last bound to

-- A new account store (the client's replacing the provisional one): the danger tables are built again from it.
local setDBObj = module.setDBObj
function module:setDBObj(db, globalDB)
    setDBObj(self, db, globalDB)
    local data = globalDB ~= nil and globalDB.data or nil
    if data == storeData then
        return
    end
    local previous = storeData
    storeData = data
    if previous ~= nil then
        self.customPointsChanged:emit("danger")
    end
end

-- The player's store, with the shipped points handed over; nil only before the saved variables are bound.
function module:customPointStore()
    local data = self.globalDB ~= nil and self.globalDB.data or nil
    if data == nil then
        return nil
    end
    local store = cp.store(data)
    local added, named = cp.mergeShipped(store, cp.shipped)
    if added > 0 then
        self.customPointsChanged:emit("danger")
    elseif named > 0 then
        self.customPointsChanged:emit("rename")
    end
    return store
end

local function storeOrSay()
    local store = module:customPointStore()
    if store == nil then
        WowVision:notify(L["Custom points are not loaded yet, try again in a moment"])
    end
    return store
end

local function playerPosition()
    local ok, x, y, _, map = pcall(UnitPosition, "player")
    if not ok or x == nil or (issecretvalue ~= nil and (issecretvalue(x) or issecretvalue(y))) then
        return nil
    end
    return x, y, map
end

local function distanceText(point)
    local px, py, map = playerPosition()
    if px == nil or point.map ~= map then
        return nil
    end
    local dx, dy = point.x - px, point.y - py
    return string.format(L["%d yards"], math.floor(math.sqrt(dx * dx + dy * dy) + 0.5))
end

-- The name offered for a waypoint at the player's position: the subzone, else the zone.
local function placeName()
    local offered = GetSubZoneText ~= nil and GetSubZoneText() or ""
    if offered == "" and GetZoneText ~= nil then
        offered = GetZoneText() or ""
    end
    return offered
end

-- Saves a point of `kind` at x, y on map; a waypoint asks for its name first (offered: the name proposed, nil for
-- none). Nothing is asked when there is no store to save in.
local function save(kind, x, y, map, offered)
    local store = storeOrSay()
    if store == nil then
        return
    end
    if kind == "danger" then
        local point = cp.add(store, "danger", x, y, nil, map)
        module.customPointsChanged:emit("danger")
        WowVision:notify(L["Danger point saved"])
        return
    end
    WowVision.graphHost:openTextEntry({
        label = L["Name of the waypoint"],
        text = offered or "",
        onCommit = function(text)
            -- read again: the client's account store may have been adopted while the name was typed
            store = storeOrSay()
            if store == nil then
                return
            end
            local name = type(text) == "string" and text:match("^%s*(.-)%s*$") or nil
            local point = cp.add(store, "waypoint", x, y, nil, map, name ~= "" and name or nil)
            module.customPointsChanged:emit("waypoint")
            WowVision:notify(string.format(L["Waypoint saved: %s"], cp.label(point, "waypoint", L)))
        end,
        onCancel = function()
            WowVision:notify(L["Not saved"])
        end,
    })
end

local function finishNew(kind, x, y, map, offered)
    WowVision.UIHost:closeWindow(NEW_WINDOW)
    if map == nil then
        -- a point without its map is never listed nor routed to
        WowVision:notify(L["The map here is not known, nothing saved"])
        return
    end
    save(kind, x, y, map, offered)
end

local function renderNew(builder, screen)
    local kind = module.newCustomKind or "waypoint"
    builder:beginStop("new")
    builder:pushContext("new", kind == "danger" and L["New Danger Point"] or L["New Custom Waypoint"])
    builder:addItem(ControlId.structural("here"), nodes.button({
        label = L["Current Position"],
        onActivate = function()
            local x, y, map = playerPosition()
            if x == nil then
                WowVision:notify(L["Position unavailable"])
                return
            end
            finishNew(kind, x, y, map, placeName())
        end,
    }))
    builder:addItem(ControlId.structural("coordinates"), nodes.textInput({
        label = L["Map Coordinates, for Example 45.2 63.1"],
        get = function()
            return ""
        end,
        set = function(value)
            local mode, a, b = WowVision.mapCoordinates.parse(value)
            if mode == nil then
                WowVision:notify(L["Coordinates not understood"])
                return
            end
            local x, y, map
            if mode == "world" then
                x, y = a, b
            else
                x, y, map = WowVision.mapCoordinates.toWorld(a, b)
                if x == nil then
                    WowVision:notify(L["Position unavailable"])
                    return
                end
            end
            if map == nil then
                local _, _, own = playerPosition()
                map = own
            end
            -- typed coordinates lie elsewhere: the player's subzone is not offered as their name
            finishNew(kind, x, y, map, nil)
        end,
    }))
    builder:popContext()
end

module:registerWindow({
    type = "ManualWindow",
    name = NEW_WINDOW,
    graphScreen = { render = renderNew, captureClose = true },
})

function module:newCustomPoint(kind)
    self.newCustomKind = kind
    WowVision.UIHost:openWindow(NEW_WINDOW)
end

module:registerBinding({
    type = "Function",
    key = "maps/newCustomWaypoint",
    label = L["New Custom Waypoint"],
    inputs = { "ALT-CTRL-W" },
    opensWindow = true,
    func = function()
        module:newCustomPoint("waypoint")
    end,
})

module:registerBinding({
    type = "Function",
    key = "maps/newCustomDanger",
    label = L["New Danger Point"],
    inputs = { "ALT-CTRL-D" },
    opensWindow = true,
    func = function()
        module:newCustomPoint("danger")
    end,
})

-- ---- the points as destinations

-- The points of the player's map join every consumer of the destinations (F10, /beacon to, Auto Route, Ctrl-Shift-N):
-- module:destinationWaypoints gives a fresh table each call, so they are added to it. Each is a virtual destination,
-- so without a route it gets a straight beacon.
local destinationWaypoints = module.destinationWaypoints
function module:destinationWaypoints()
    local waypoints, engine = destinationWaypoints(self)
    local store = self:customPointStore()
    local _, _, map = playerPosition()
    if store == nil or map == nil then
        return waypoints, engine
    end
    local foldCase = WowVision.utils.foldCase
    for kind in pairs(cp.LISTS) do
        for _, point in ipairs(cp.list(store, kind, map)) do
            local label = cp.label(point, kind, L)
            local detail = KIND_WORDS[kind]()
            local id = "custom:" .. point.id
            waypoints[id] = {
                id = id, n = label, detail = detail, x = point.x, y = point.y, z = point.z, virtual = true,
                search = foldCase(label .. " " .. detail),
            }
        end
    end
    return waypoints, engine
end

local function renderList(builder, screen)
    local store = module:customPointStore()
    local _, _, map = playerPosition()
    for _, kind in ipairs({ "waypoint", "danger" }) do
        builder:beginStop(kind)
        builder:pushContext(kind, kind == "danger" and L["Danger Points"] or L["Custom Waypoints"])
        local points = (store ~= nil and map ~= nil) and cp.list(store, kind, map) or {}
        if map == nil then
            -- without the map every continent's points would be listed
            builder:addItem(ControlId.structural(kind .. ":noMap"),
                nodes.text({ label = L["The map here is not known"] }))
        elseif #points == 0 then
            builder:addItem(ControlId.structural(kind .. ":empty"), nodes.text({ label = L["Empty"] }))
        end
        for _, point in ipairs(points) do
            local captured = point
            local label = cp.label(point, kind, L)
            local distance = distanceText(point)
            local node = nodes.button({
                label = distance ~= nil and (label .. ", " .. distance) or label,
                -- Enter: the navigation window aims at the point (it heads the destinations, Enter there routes)
                onActivate = function()
                    local host = WowVision.graphHost
                    host:pop(host:focusedStack())
                    module:openNavigationTo(captured.x, captured.y, cp.label(captured, kind, L))
                end,
            })
            -- Shift+F10 on a point (nodes.button has no field for it; the settings lists set it the same way)
            node.contextActions = function(add)
                add({
                    label = L["Rename"],
                    onActivate = function()
                        WowVision.graphHost:openTextEntry({
                            label = L["New name"],
                            text = captured.name or "",
                            onCommit = function(text)
                                local current = storeOrSay()
                                if current ~= nil and cp.rename(current, kind, captured.id, text) then
                                    -- only the name: the danger tables stay (a spawn's name is its id)
                                    module.customPointsChanged:emit("rename")
                                    WowVision:notify(string.format(L["Renamed: %s"], cp.label(captured, kind, L)))
                                end
                            end,
                        })
                    end,
                })
                add({
                    label = L["Delete"],
                    onActivate = function()
                        nodes.pushConfirm({
                            prompt = string.format(L["Delete %s?"], cp.label(captured, kind, L)),
                            onConfirm = function()
                                local current = storeOrSay()
                                if current ~= nil and cp.remove(current, kind, captured.id) then
                                    module.customPointsChanged:emit(kind)
                                    WowVision:notify(L["Deleted"])
                                end
                                -- Yes closed the confirmation only: the point's context menu goes too, and the
                                -- list lands on the deleted row's neighbour
                                graph.contextMenu.close()
                            end,
                        })
                    end,
                })
            end
            builder:addItem(ControlId.structural(kind .. ":" .. point.id), node)
        end
        builder:popContext()
    end
end

-- ---- the WowVision menu: "Custom Points" on the Navigation page (user 2026-11-27: there, not in F10), next to
-- whatever else that page lists
local navigation = WowVision.base.navigation
local previousMenuItems = navigation.getGraphMenuItems
function navigation:getGraphMenuItems(builder)
    if previousMenuItems ~= nil then
        previousMenuItems(self, builder)
    end
    builder:addItem(ControlId.structural("customPoints"), nodes.button({
        label = L["Custom Points"],
        opensLevel = true,
        onActivate = function()
            WowVision.graph.settings.pushScreen("customPoints", renderList)
        end,
    }))
end
