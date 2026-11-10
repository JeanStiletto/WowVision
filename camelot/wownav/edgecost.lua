-- Edge cost of WowNav routes: links that run beside a drop cost more in the search, so a route takes such a link only
-- when the way around costs more. WowNav's search adds HOP_COST per waypoint and so likes long straight links; under
-- Ironforge one ran up a ramp along its lava side while the ramp's own waypoints were linked beside it (walk
-- 2026-11-10, the player slid off at the top).
--
-- The links and their yards beside a drop come from the pack step (tools/wownav-pack.lua with
-- tools/wownav-edgecost.lua, from the surroundings data's floor model) as WVN7EdgeCost[zoneId] = { fingerprint,
-- links = { u, v, yards, ... } }; a zone gets them only when the fingerprint is that of its navdata. Each yard costs
-- PER_YARD in the search (engine/NavNetwork.lua, Pass: zone.lextra). A waypoint costs HOP_COST 15 yd, 22.5 on fine
-- links: at 30 a yard a link with 3 yd beside a drop is worth a way around with about three more waypoints (measured
-- 2026-11-10 on seven zones: 0.3 to 2.8 % longer routes, most yards beside drops gone).

local edgeCost = {}
WowVision.wownavEdgeCost = edgeCost

edgeCost.PER_YARD = 30

local N = _G.WowVisionNavigationNavNetwork

-- Sets zone.lextra (link number -> extra cost) from WVN7EdgeCost, or clears it. Returns the number of links. Two
-- waypoints can be joined by two links (the data has such twins); the list names each, so each entry takes the next
-- link of its pair that has no cost yet.
function edgeCost.apply(zone)
    zone.lextra = nil
    local data = _G.WVN7EdgeCost and _G.WVN7EdgeCost[zone.id]
    if type(data) ~= "table" or data.fingerprint ~= zone.fingerprint or type(data.links) ~= "table" then
        return 0
    end
    local extra, count = {}, 0
    local links = data.links
    for i = 1, #links - 2, 3 do
        local u, v, yards = links[i], links[i + 1], links[i + 2]
        local adj = zone.adj[u + 1]
        for j = 1, adj and #adj or 0, 2 do
            if adj[j] == v and extra[adj[j + 1]] == nil then
                extra[adj[j + 1]] = edgeCost.PER_YARD * yards
                count = count + 1
                break
            end
        end
    end
    if count > 0 then
        zone.lextra = extra
    end
    return count
end

if N ~= nil then
    local previous = N.onZoneLoaded
    N.onZoneLoaded = function(zone)
        edgeCost.apply(zone)
        if previous then
            previous(zone)
        end
    end
end
