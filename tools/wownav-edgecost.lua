-- Edge cost for WowNav routes: the links of a zone that run beside a drop, for tools/wownav-pack.lua.
--
-- WowNav's links carry no width and no edge information, and its search adds HOP_COST per waypoint, so it likes long
-- straight links; under Ironforge one ran up a ramp along its lava side, 1.3 yd from a 60 yd drop, while the ramp's own
-- waypoints were linked beside it (walk 2026-11-10 16:38, the player slid off at the top). The links found here get an
-- extra cost per yard in the search (camelot/wownav/edgecost.lua), so a route takes such a link only when the way
-- around costs more.
--
-- The ground beside a link comes from the surroundings data's floor model (WowVision_Surroundings, format 5 surfaces:
-- every walkable surface and liquid surface of a 1 yd column), not from WowNav's attachment cells: their 2 yd fields
-- count as floor where any floor touches them, and under Ironforge they claim floor over the lava. Zones the
-- surroundings data does not cover get no edge cost.
--
-- The rule (measured 2026-11-10 on seven zones, scripts/edge-measure in the project folder): every yard along a link
-- (from 1 yd after its start) whose own point has floor at the link's height (within SAME) is beside a drop when, on
-- either side, out to REACH, a column holds no floor at that height and its highest surface below lies DROP or more
-- down (a wall, a step or a column without data ends that side). A link with MIN_YARDS or more such yards is listed.

local EdgeCost = {}

EdgeCost.OFFSETS = { 0.5, 1.0, 1.5, 2.0 }   -- yd sideways from the link (REACH 2 yd)
EdgeCost.SAME = 1.5                         -- yd: a surface this close to the link's height is its floor
EdgeCost.DROP = 5.0                         -- yd: a floor beside at least this far down is a drop
EdgeCost.STEP = 1.0                         -- yd between samples along a link
EdgeCost.MIN_YARDS = 2                      -- yd beside a drop from which a link is listed

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max

-- ---------------------------------------------------------------------------------------------------------------
-- The surroundings floor model
-- ---------------------------------------------------------------------------------------------------------------

local ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-"
local VALUE = {}
for i = 1, #ALPHABET do
    VALUE[ALPHABET:byte(i)] = i - 1
end
local byte = string.byte

-- The heights of every surface in the 1 yd column of (x, y) over the layers of `model`.
local function heightsAt(model, x, y)
    local out = {}
    for _, S in ipairs(model.layers) do
        local r, c = floor(x - S.x0), floor(y - S.y0)
        local row = S.rows[r]
        if row then
            local REC = S.rec or 9
            local n = floor(#row / REC)
            local lo, hi = 1, n
            while lo < hi do
                local m = floor((lo + hi) / 2)
                local p = (m - 1) * REC + 1
                local a, b, d = byte(row, p, p + 2)
                if VALUE[a] * 4096 + VALUE[b] * 64 + VALUE[d] < c then lo = m + 1 else hi = m end
            end
            for i = lo, n do
                local p = (i - 1) * REC + 1
                local b1, b2, b3, b4, b5, b6, b7, b8 = byte(row, p, p + 7)
                if VALUE[b1] * 4096 + VALUE[b2] * 64 + VALUE[b3] ~= c then break end
                if VALUE[b7] * 64 + VALUE[b8] ~= 4095 then
                    out[#out + 1] = (VALUE[b4] * 4096 + VALUE[b5] * 64 + VALUE[b6] - 200000) / 10
                end
            end
        end
    end
    return out
end

-- "floor" | "drop", depth | "wall" (only surfaces above) | "empty" (no surface)
local function classify(model, x, y, z)
    local list = heightsAt(model, x, y)
    if #list == 0 then return "empty" end
    local below
    for _, h in ipairs(list) do
        if math.abs(h - z) <= EdgeCost.SAME then return "floor" end
        if h < z and (not below or h > below) then below = h end
    end
    if below then return "drop", z - below end
    return "wall"
end

local function listFiles(dir, suffix)
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. dir .. '" 2>/dev/null')
    local pipe = io.popen(command)
    local out = {}
    if pipe then
        for line in pipe:lines() do
            line = line:gsub("[\r\n]", "")
            if line:sub(-#suffix) == suffix then out[#out + 1] = line end
        end
        pipe:close()
    end
    table.sort(out)
    return out
end

-- The floor models of the surroundings zones in `dir` (their <key>-surfaces.lua beside <key>.lua), by native map:
-- { [mapId] = { {key, layers = {...}, box = {xmin, xmax, ymin, ymax}}, ... } }. Empty when the folder is missing.
function EdgeCost.loadModels(dir)
    local models = {}
    for _, file in ipairs(listFiles(dir, "-surfaces.lua")) do
        local key = file:sub(1, -#"-surfaces.lua" - 1)
        local header
        local zoneChunk = loadfile(dir .. "/" .. key .. ".lua")
        if zoneChunk then
            zoneChunk(nil, { addZone = function(h) header = h end })
        end
        local layers
        assert(loadfile(dir .. "/" .. file))(nil, { addSurfaces = function(_, l) layers = l end })
        if header and layers then
            local model = { key = key, layers = {} }
            local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
            local names = {}
            for name in pairs(layers) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local S = layers[name]
                model.layers[#model.layers + 1] = S
                local REC = S.rec or 9
                for r, row in pairs(S.rows) do
                    if #row >= REC then
                        local a, b, d = byte(row, 1, 3)
                        local first = VALUE[a] * 4096 + VALUE[b] * 64 + VALUE[d]
                        local p = (floor(#row / REC) - 1) * REC + 1
                        a, b, d = byte(row, p, p + 2)
                        local last = VALUE[a] * 4096 + VALUE[b] * 64 + VALUE[d]
                        xmin, xmax = min(xmin, S.x0 + r), max(xmax, S.x0 + r + 1)
                        ymin, ymax = min(ymin, S.y0 + first), max(ymax, S.y0 + last + 1)
                    end
                end
            end
            model.box = { xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax }
            models[header.map] = models[header.map] or {}
            table.insert(models[header.map], model)
        end
    end
    return models
end

-- The models of the zone's native map whose box meets one of the zone's world boxes (index entry `entry`).
function EdgeCost.modelsFor(models, entry)
    local out = {}
    for _, model in ipairs(models[entry.nativeMapId] or {}) do
        local b = model.box
        for _, box in pairs(entry.worldBoxes or {}) do
            if box.xmin <= b.xmax and b.xmin <= box.xmax and box.ymin <= b.ymax and b.ymin <= box.ymax then
                out[#out + 1] = model
                break
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- The links beside a drop
-- ---------------------------------------------------------------------------------------------------------------

-- Yards of link k of the decoded zone beside a drop, over the floor models `list`.
function EdgeCost.dropYards(zone, k, list)
    local u, v = zone.lu[k] + 1, zone.lv[k] + 1
    local ax, ay, az = zone.x[u], zone.y[u], zone.z[u]
    local dx, dy, dz = zone.x[v] - ax, zone.y[v] - ay, zone.z[v] - az
    local len = sqrt(dx * dx + dy * dy)
    if len < 2 or zone.lflag[k] >= 8 then return 0 end      -- too short to judge, or swimming
    local nx, ny = -dy / len, dx / len
    local yards = 0
    for s = 0, floor((len - 2) / EdgeCost.STEP) do
        local f = (1 + s * EdgeCost.STEP) / len
        local px, py, pz = ax + dx * f, ay + dy * f, az + dz * f
        for _, model in ipairs(list) do
            -- only where the line itself is on floor: a long link over a hill runs above or below the ground, and
            -- probes at its straight-line height would read the slope beside it as a drop
            if classify(model, px, py, pz) == "floor" then
                local beside = false
                for _, side in ipairs({ 1, -1 }) do
                    for _, off in ipairs(EdgeCost.OFFSETS) do
                        local kind, depth = classify(model, px + nx * off * side, py + ny * off * side, pz)
                        if kind == "drop" and depth >= EdgeCost.DROP then
                            beside = true
                            break
                        elseif kind ~= "floor" then
                            break
                        end
                    end
                    if beside then break end
                end
                if beside then yards = yards + EdgeCost.STEP end
                break
            end
        end
    end
    return yards
end

-- The file text for one zone (the decoded `zone`, its models `list`), or nil when no link is beside a drop.
-- WVN7EdgeCost[zoneId] = { fingerprint, links = { u, v, yards, ... } } with the local waypoint IDs of each link.
function EdgeCost.zoneText(zone, list, name)
    local links, count = {}, 0
    for k = 1, #zone.lu do
        local yards = EdgeCost.dropYards(zone, k, list)
        if yards >= EdgeCost.MIN_YARDS then
            links[#links + 1] = string.format("%d,%d,%d", zone.lu[k], zone.lv[k], yards)
            count = count + 1
        end
    end
    if count == 0 then return nil, 0 end
    local lines = {
        "-- WVN7 edge cost by tools/wownav-edgecost.lua: the links of " .. name .. " that run beside a drop (u, v, yards).",
        "WVN7EdgeCost = WVN7EdgeCost or {}",
        string.format("WVN7EdgeCost[%d] = { fingerprint = %q, links = {", zone.id, zone.fingerprint),
    }
    for i = 1, #links, 20 do
        lines[#lines + 1] = table.concat(links, ",", i, min(i + 19, #links)) .. ","
    end
    lines[#lines + 1] = "} }"
    return table.concat(lines, "\n") .. "\n", count
end

return EdgeCost
