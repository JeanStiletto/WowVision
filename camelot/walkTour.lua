-- Walk tours (developer tool, LOCAL only, not for a PR): /wv tour <name> starts a beacon chain through fixed
-- points to test where WowNav links are hard to walk (the "step you cannot undo" rule, 2026-11-11). The points come
-- from Dev/WowVision/scripts/edge-measure/darkshore-2026-11-11 (tour.lua): the legs between test points follow
-- WowNav waypoints; at each test the beacon leads below a step, above it, and back below. Ctrl-W skips a point.
-- What happened is read afterwards from WowVisionDump (surroundings trail, bumps, falls).

local tours = {
    ironforge = {
        label = "Ironforge steps 1.37 to 1.77 yards, from Gryth Thurden",
        points = {
        { -4823.9, -1160.8 },
        { -4806.8, -1171.2 },
        { -4765.1, -1164.4 },
        { -4740.9, -1157.8 },
        { -4735.4, -1116.9 },
        { -4725.3, -1109.8 },
        { -4722.9, -1106.6 },
        { -4725.3, -1109.8 },
        { -4735.4, -1116.9 },
        { -4740.9, -1157.8 },
        { -4739.3, -1160.2 },
        { -4707.8, -1195.3 },
        { -4688.3, -1191.2 },
        { -4687.3, -1189.3 },
        { -4684.9, -1184.9 },
        { -4687.3, -1189.3 },
        { -4688.3, -1191.2 },
        { -4681.4, -1198.1 },
        { -4645.7, -1182.7 },
        { -4643.0, -1178.0 },
        { -4629.4, -1150.3 },
        { -4628.1, -1131.2 },
        { -4625.2, -1124.7 },
        { -4621.6, -1124.2 },
        { -4618.2, -1120.6 },
        { -4621.6, -1124.2 },
        { -4625.2, -1124.7 },
        { -4628.5, -1127.8 },
        { -4628.5, -1055.9 },
        { -4636.3, -1025.9 },
        { -4633.7, -1015.7 },
        { -4639.1, -943.8 },
        { -4627.4, -930.8 },
        { -4615.7, -939.2 },
        { -4595.5, -922.3 },
        { -4596.6, -924.5 },
        { -4592.4, -921.7 },
        { -4596.6, -924.5 },
        { -4595.5, -922.3 },
        { -4591.1, -920.0 },
        { -4589.0, -911.3 },
        { -4602.2, -914.9 },
        { -4597.4, -913.6 },
        { -4602.2, -914.9 },
        { -4607.9, -921.5 },
        { -4615.1, -927.3 },
        { -4619.9, -929.0 },
        { -4615.1, -927.3 },
        { -4619.3, -920.4 },
        { -4632.5, -933.7 },
        { -4654.7, -953.6 },
        { -4650.4, -953.0 },
        { -4646.5, -949.8 },
        { -4650.4, -953.0 },
        },
    },
    auberdine = {
        label = "Auberdine: the bank, the bridge corner and the U-turn, from Innkeeper Shaussiy",
        points = {
        { 6415.5, 512.4 },
        { 6439.6, 519.1 },
        { 6448.7, 521.6 },
        { 6448.6, 532.6 },
        { 6454.4, 516.5 },
        { 6425.4, 450.2 },
        { 6425.2, 449.9 },
        { 6446.7, 470.4 },
        { 6452.1, 488.9 },
        { 6479.1, 484.8 },
        { 6483.6, 488.2 },
        { 6515.7, 465.6 },
        { 6483.6, 488.2 },
        { 6504.1, 465.5 },
        },
    },
    -- Zephras Isle, Nachtklauenhoehle: the long way around the 3.1 and 3.5 yd ledge to the druids on the shelf, as
    -- the WowNav data routes it once impossible climbs are blocked (newest data 52c6c83, about 340 yd)
    nachtklauen = {
        label = "Nachtklauenhoehle, the long way to Baeo Sharpstrike and Mithraless Sterngale, from the cave floor below the shelf",
        points = {
            { 3689.8, 576.1 },
            { 3700.2, 583.8 },
            { 3710.5, 591.5 },
            { 3721.7, 600.1 },
            { 3730.9, 612.0 },
            { 3740.2, 623.9 },
            { 3759.7, 626.1 },
            { 3779.2, 628.4 },
            { 3796.4, 637.3 },
            { 3813.7, 646.1 },
            { 3828.8, 637.2 },
            { 3833.9, 629.3 },
            { 3830.6, 614.6 },
            { 3828.4, 612.7 },
            { 3811.0, 601.0 },
            { 3793.6, 589.4 },
            { 3776.2, 577.7 },
            { 3769.9, 566.4 },
            { 3763.7, 555.1 },
            { 3744.2, 555.1 },
            { 3724.7, 555.1 },
            { 3712.1, 564.5 },
            { 3734.0, 571.1 },
        },
    },
}

local function names()
    local list = {}
    for name in pairs(tours) do
        list[#list + 1] = name
    end
    table.sort(list)
    return table.concat(list, ", ")
end

WowVision.base:registerCommand({
    name = "tour",
    description = "Walk tour (developer tool): /wv tour <name> [first point] starts a beacon chain through test points; /wv tour lists the tours",
    func = function(args)
        local name, first = tostring(args or ""):lower():match("^%s*(%S*)%s*(%d*)")
        local tour = tours[name or ""]
        if tour == nil then
            local text = "Tours: " .. names()
            print(text)
            WowVision:speak(text)
            return
        end
        first = math.max(1, math.min(tonumber(first) or 1, #tour.points))
        local maps = WowVision.base.navigation.maps
        maps:cancelNavigation()
        local path = maps.Path:new()
        for i = first, #tour.points do
            local p = tour.points[i]
            path:add({ x = p[1], y = p[2], n = string.format("%s %d", name, i), tourIndex = i })
        end
        -- each point reached is said and printed with its number, so a tour can start again there
        path.events.arriveAtWaypoint:subscribe(maps, function(_, _, _, waypoint)
            if waypoint and waypoint.tourIndex then
                local text = string.format("Point %d of %d", waypoint.tourIndex, #tour.points)
                print("Tour " .. name .. ": " .. text)
                WowVision:speak(text)
            end
        end)
        path.events.complete:subscribe(maps, function()
            -- as maps:beaconTo does: the finished chain stops guiding
            if maps.path == path then
                maps.path = nil
            end
            print("Tour " .. name .. " finished")
            WowVision:speak("Tour " .. name .. " finished")
        end)
        maps:pathfind(path)
        local text = string.format("Tour %s: %s, %d points, from point %d", name, tour.label, #tour.points, first)
        print(text)
        WowVision:speak(text)
    end,
})
