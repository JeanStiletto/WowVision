-- Custom points in the game (user request 2026-11-27; the store logic is core/navigation/customPoints.lua):
--   Alt+Ctrl+W  a new custom waypoint: the current position or typed map coordinates, then a name
--   Alt+Ctrl+D  a new custom danger point: the current position or typed map coordinates; no name asked ("Monster
--               spawn", renamed in the list when wanted)
-- Both kinds join the destination list of the navigation window (F10), and its "Custom Points" button lists them
-- with Rename and Delete (Shift+F10 on a point). A route engine's safe routes count the danger points
-- (customPointsChanged tells it when they change; camelot/wownav/module.lua).
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

-- The player's store, with the shipped points handed over; nil while the account's saved variables are not there yet
-- (WoW: Forever hands them over after the addon loaded: a point saved before that would be lost).
function module:customPointStore()
    if WowVision.globalStoreProvisional then
        return nil
    end
    local data = self.globalDB ~= nil and self.globalDB.data or nil
    if data == nil then
        return nil
    end
    local store = cp.store(data)
    if cp.mergeShipped(store, cp.shipped) > 0 then
        self.customPointsChanged:emit("danger")
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

-- Map percent of the zone the player is in -> world position and map (UnitPosition's convention), or nil.
local function worldFromMapPercent(xPercent, yPercent)
    local uiMap = C_Map.GetBestMapForUnit("player")
    if uiMap == nil then
        return nil
    end
    local map, worldPos = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(xPercent / 100, yPercent / 100))
    if worldPos == nil then
        return nil
    end
    local x, y = worldPos:GetXY()
    if map == nil then
        local _, _, ownMap = playerPosition()
        map = ownMap
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

-- Saves a point of `kind` at x, y on map; a waypoint asks for its name first (the subzone is offered).
local function save(kind, x, y, map)
    if kind == "danger" then
        local store = storeOrSay()
        if store == nil then
            return
        end
        cp.add(store, "danger", x, y, nil, map)
        module.customPointsChanged:emit("danger")
        WowVision:notify(L["Danger point saved"])
        return
    end
    local offered = GetSubZoneText ~= nil and GetSubZoneText() or ""
    if offered == "" and GetZoneText ~= nil then
        offered = GetZoneText() or ""
    end
    WowVision.graphHost:openTextEntry({
        label = L["Name of the waypoint"],
        text = offered,
        onCommit = function(text)
            local store = storeOrSay()
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

local function finishNew(kind, x, y, map)
    WowVision.UIHost:closeWindow(NEW_WINDOW)
    save(kind, x, y, map)
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
            finishNew(kind, x, y, map)
        end,
    }))
    builder:addItem(ControlId.structural("coordinates"), nodes.textInput({
        label = L["Map Coordinates, for Example 45.2 63.1"],
        get = function()
            return ""
        end,
        set = function(value)
            local mode, a, b = cp.parseCoordinates(value)
            if mode == nil then
                WowVision:notify(L["Coordinates not understood"])
                return
            end
            local x, y, map
            if mode == "world" then
                local _, _, own = playerPosition()
                x, y, map = a, b, own
            else
                x, y, map = worldFromMapPercent(a, b)
            end
            if x == nil then
                WowVision:notify(L["Position unavailable"])
                return
            end
            finishNew(kind, x, y, map)
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

-- ---- the navigation window (ui.lua): the points as destinations, and the list with Rename and Delete

-- The points of the player's map join the window's destinations (copies of the window's table: the continent's own
-- waypoint table is shared). Each is a virtual destination, so without a route engine it gets a straight beacon.
function module:withCustomDestinations(waypoints, map)
    local store = self:customPointStore()
    if store == nil then
        return waypoints
    end
    local merged = nil
    local foldCase = WowVision.utils.foldCase
    for kind in pairs(cp.LISTS) do
        for _, point in ipairs(cp.list(store, kind, map)) do
            if merged == nil then
                merged = {}
                for id, wp in pairs(waypoints) do
                    merged[id] = wp
                end
            end
            local label = cp.label(point, kind, L)
            local detail = KIND_WORDS[kind]()
            local id = "custom:" .. point.id
            merged[id] = {
                id = id, n = label, detail = detail, x = point.x, y = point.y, z = point.z, virtual = true,
                search = foldCase(label .. " " .. detail),
            }
        end
    end
    return merged or waypoints
end

local function renderList(builder, screen)
    local store = module:customPointStore()
    local _, _, map = playerPosition()
    for _, kind in ipairs({ "waypoint", "danger" }) do
        builder:beginStop(kind)
        builder:pushContext(kind, kind == "danger" and L["Danger Points"] or L["Custom Waypoints"])
        local points = store ~= nil and cp.list(store, kind, map) or {}
        if #points == 0 then
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
                                    module.customPointsChanged:emit(kind)
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

-- The "Custom Points" button of the navigation window (its own stop after the destinations).
function module:renderCustomPointsStop(builder, screen)
    builder:beginStop("customPoints")
    builder:addItem(ControlId.structural("customPoints"), nodes.button({
        label = L["Custom Points"],
        opensLevel = true,
        onActivate = function()
            WowVision.graph.settings.pushScreen("customPoints", renderList)
        end,
    }))
end
