-- The places list window (Alt-F10): the zones with surroundings data on this continent, the
-- zone the player is in open; under a zone its subzones and the things in no subzone, under a
-- subzone its named buildings, squares, landmarks and shops, under a building its named rooms;
-- each level sorted by distance (places.lua builds the tree). Enter leads there through the
-- navigation's routes, as the scanner's Enter (a building: to the point outside its doorway,
-- then a beacon 3 yd inside). With the setting Discovery Mode a subzone the character has not
-- explored is listed without its name, only where one comes to it from what is known, and
-- nothing in it; the game's own map says what is explored (as a sighted player hovering it).

local logic = WowVision.surroundingsLogic
local module = WowVision.base.navigation.surroundings
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

local WINDOW = "surroundingsPlaces"

local function maps()
    return WowVision.base.navigation and WowVision.base.navigation.maps or nil
end

-- every places file of the data addon, unpacked in the client's language
local function placeLists()
    local out = {}
    local data = WowVisionSurroundingsData and WowVisionSurroundingsData.places or {}
    for _, raw in ipairs(data) do
        if raw.format == logic.PLACES_FORMAT then
            out[#out + 1] = logic.placesUnpack(raw, GetLocale())
        end
    end
    return out
end

-- The area ids the game counts as explored at a world position on a zone's map (the map's own
-- hover names come from the same call), or nil.
local function exploredAt(zone, x, y)
    if C_Map == nil or C_MapExplorationInfo == nil or zone.ui == 0 then
        return nil
    end
    local ok, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos, zone.map, CreateVector2D(x, y), zone.ui)
    if not ok or mapPos == nil then
        return nil
    end
    local ok2, ids = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, zone.ui, mapPos)
    return ok2 and ids or nil
end

-- A subzone with an exploration overlay is known where the map names it; one without (a mine,
-- the abbey inside Northshire Valley's) where the map shows the spot explored at all.
local function areaKnown(area)
    for _, p in ipairs(area.checks) do
        local ids = exploredAt(area.zone, p.x, p.y)
        if ids then
            if area.overlay then
                for _, id in ipairs(ids) do
                    if id == area.area then
                        return true
                    end
                end
            elseif #ids > 0 then
                return true
            end
        end
    end
    return false
end

function module:placesTree()
    local x, y, _z, map = UnitPosition("player")
    if x == nil then
        return {}
    end
    return logic.placesTree(placeLists(), {
        x = x, y = y, map = map, zoneName = GetZoneText and GetZoneText() or "",
        subzone = GetSubZoneText and GetSubZoneText() or "", discovery = self.settings.discovery,
        known = areaKnown, unexplored = L["unexplored area"],
    })
end

-- Where Enter leads: the one place to swap in another navigation later (WowNav). Through the
-- route network as the scanner's Enter; a building's doorway: to the point outside it, then a
-- beacon to 3 yd inside; a named room: to its building's doorway, then a beacon to the room.
function module:placesNavigate(node)
    local m = maps()
    if m == nil or node.x == nil then
        return
    end
    WowVision.UIHost:closeWindow(WINDOW)
    local onArrive
    local tx, ty = node.x, node.y
    if node.viaX ~= nil then
        -- a named room: to its building's doorway first
        tx, ty = node.viaX, node.viaY
    elseif node.ox ~= nil then
        tx, ty = node.ox, node.oy
    end
    if tx ~= node.x or ty ~= node.y then
        onArrive = function()
            m:beaconTo(node.x, node.y, node.label)
        end
    end
    if m.openNavigationTo ~= nil then
        m:openNavigationTo(tx, ty, node.label, onArrive)
    else
        m:beaconTo(tx, ty, node.label, onArrive)
    end
end

-- ---- the window: one tab stop with the tree, then Refresh (as the scanner's)
local function ensureTree(screen)
    if screen._tree == nil then
        screen._tree = module:placesTree()
        screen._seed = true
    end
    return screen._tree
end

local function vtableFor(node, screen, id)
    local announcements = { { text = node.label, kind = graph.kinds.label } }
    if node.x ~= nil then
        tinsert(announcements, {
            text = function()
                local m = maps()
                return m and m:whereText(node.x, node.y) or nil
            end,
            kind = graph.kinds.value,
        })
    end
    local vtable = { announcements = announcements }
    if node.children ~= nil then
        vtable.controlType = graph.controlTypes.group
    elseif node.x ~= nil then
        vtable.controlType = graph.controlTypes.button
    else
        vtable.controlType = graph.controlTypes.text
    end
    if node.x ~= nil then
        vtable.onActivate = function()
            module:placesNavigate(node)
        end
    elseif node.children ~= nil then
        vtable.onActivate = function()
            screen.state.expanded[id.key] = not screen.state.expanded[id.key] or nil
        end
    end
    return vtable
end

local function emit(builder, screen, node, path)
    local key = path .. "/" .. tostring(node.key)
    local id = ControlId.structural(key)
    if node.children == nil then
        builder:addItem(id, vtableFor(node, screen, id))
        return
    end
    if node.expanded and screen._seed then
        screen.state.expanded[key] = true
    end
    builder:beginGroup(id, vtableFor(node, screen, id))
    if builder:isExpanded(id) then
        for _, child in ipairs(node.children) do
            emit(builder, screen, child, key)
        end
    end
    builder:endGroup()
end

local function render(builder, screen)
    local tree = ensureTree(screen)
    builder:beginStop("tree")
    builder:pushContext("places", L["Places"])
    if #tree == 0 then
        builder:addItem(ControlId.structural("empty"), nodes.text({ label = L["Empty"] }))
    end
    for _, zone in ipairs(tree) do
        emit(builder, screen, zone, "places")
    end
    screen._seed = nil
    builder:popContext()

    builder:beginStop("refresh")
    builder:addItem(
        ControlId.structural("refresh"),
        nodes.button({
            label = L["Refresh"],
            onActivate = function()
                screen._tree = nil
                WowVision:speak(L["Refreshed"])
            end,
        })
    )
end

module:registerWindow({
    type = "ManualWindow",
    name = WINDOW,
    graphScreen = { render = render, captureClose = true },
})

module:registerBinding({
    type = "Script",
    key = "surroundings/places",
    label = L["Places"],
    inputs = { "ALT-F10" },
    script = "/run WowVision.UIHost:openWindow('surroundingsPlaces')",
})
