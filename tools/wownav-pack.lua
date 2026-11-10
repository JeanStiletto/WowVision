-- Packs the WowNav navigation data (the submodule mapdata/WoW_NavigationData, Broesel's public data repo) for the
-- game: every zone file is kept as one long string until a route, a list or a target needs that zone, instead of
-- building all its tables at login (concept chapter 7 point 2 of WowNav: "at login all files are in memory as compact
-- strings"). The data itself is not changed: a packed file holds the original file text byte for byte, and
-- camelot/wownav/engine/NavNetwork.lua compiles it on first use.
--
--   WVN7Src[zoneId]        = [[ <navdata.lua> ]]
--   WVN7LogicalSrc[zoneId] = [[ <logical_targets.lua> ]]
--   WVN7DynSrc[zoneId]     = [[ <dyn_targets.lua> ]]
--
-- The continent indexes stay as they are (small, read at login). The output goes to mapdata/WowNavPacked/ (not in
-- git) with a data.xml that loads it, included from camelot/modules.xml. Until the data repo ships packed files, run
-- this after every update of the submodule:
--
--   luajit tools/wownav-pack.lua            (from the repo root)
--   luajit tools/wownav-pack.lua --check    (only report; exit code 1 when the output is stale)
--
-- It also writes <zone>/edgecost.lua for every zone the surroundings data's floor model covers (SURROUNDINGS, the
-- Forever zones of WowVision_Surroundings; skipped when the folder is missing): the links that run beside a drop, which
-- the route search makes dearer (tools/wownav-edgecost.lua, camelot/wownav/edgecost.lua). Run it again after an update
-- of either data.

local SOURCE = "mapdata/WoW_NavigationData/Forever"
local TARGET = "mapdata/WowNavPacked"
local MARKER = "-- WVN7 packed"
local SURROUNDINGS = "mapdata/WowVision_Surroundings/forever/zones"

local check = false
for _, a in ipairs(arg or {}) do
    if a == "--check" then
        check = true
    end
end

local windows = package.config:sub(1, 1) == "\\"

local function native(path)
    return windows and path:gsub("/", "\\") or path
end

local function listDirs(path)
    local command = windows and ('dir /b /ad "' .. native(path) .. '" 2>nul') or ('ls -1 "' .. path .. '" 2>/dev/null')
    local pipe = assert(io.popen(command))
    local out = {}
    for line in pipe:lines() do
        line = line:gsub("[\r\n]", "")
        if line ~= "" then
            out[#out + 1] = line
        end
    end
    pipe:close()
    table.sort(out)
    return out
end

local function mkdir(path)
    local command = windows and ('if not exist "' .. native(path) .. '" mkdir "' .. native(path) .. '"')
        or ('mkdir -p "' .. path .. '"')
    os.execute(command)
end

local function read(path)
    local f = io.open(path, "rb")
    if f == nil then
        return nil
    end
    local text = f:read("*a")
    f:close()
    return text
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

-- file name -> (registration line of the original file, source table of the packed file)
local KINDS = {
    ["navdata.lua"] = { "\nWVN7%[(%d+)%]%s*=%s*W%s*\r?\n", "WVN7Src" },
    ["logical_targets.lua"] = { "\nWVN7Logical%[(%d+)%]%s*=%s*LogicalTargets%s*\r?\n", "WVN7LogicalSrc" },
    ["dyn_targets.lua"] = { "\nWVN7Dyn%[(%d+)%]%s*=%s*DynTargets%s*\r?\n", "WVN7DynSrc" },
}

-- The lowest long bracket level whose brackets occur nowhere in the text (Lua 5.1 refuses a nested "[[" inside a
-- level-0 long string).
local function longLevel(text)
    local level = 0
    while text:find("]" .. string.rep("=", level) .. "]", 1, true) or text:find("[" .. string.rep("=", level) .. "[", 1, true) do
        level = level + 1
    end
    return level
end

local function pack(text, kind, name)
    local spec = KINDS[kind]
    local zoneId = text:match(spec[1])
    if zoneId == nil then
        error(name .. ": no registration line found")
    end
    local eq = string.rep("=", longLevel(text))
    local packed = MARKER .. " by tools/wownav-pack.lua: the source below is compiled only when WowVision needs this zone.\n"
        .. spec[2] .. " = " .. spec[2] .. " or {}\n"
        .. spec[2] .. "[" .. zoneId .. "] = [" .. eq .. "[\n" .. text .. "]" .. eq .. "]\n"
    -- the packed file must load, and its string must compile (the game's loader does the same)
    local chunk, err = loadstring(packed, "=" .. name)
    if chunk == nil then
        error(name .. ": packed file does not compile: " .. tostring(err))
    end
    local env = {}
    setfenv(chunk, env)
    chunk()
    local source = env[spec[2]][tonumber(zoneId)]
    if source:gsub("\r\n", "\n") ~= text:gsub("\r\n", "\n") then
        error(name .. ": packed text differs from the original")
    end
    assert(loadstring(source, "=" .. name .. " (inner)"))
    return packed
end

-- The zones of a continent index in the order of their folders.
local function indexZones(path)
    local chunk = assert(loadfile(path))
    local env = {}
    setfenv(chunk, env)
    chunk()
    local zones = {}
    for continent, entry in pairs(env.WVN7Index or {}) do
        for _, zone in pairs(entry.zones or {}) do
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(a, b)
        return a.dir < b.dir
    end)
    return zones
end

local xml = {
    '<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        .. 'xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\\FrameXML\\UI.xsd">',
    "  <!-- Generated by tools/wownav-pack.lua from mapdata/WoW_NavigationData: the continent indexes and the packed",
    "       zone files of WowNav's navigation data. Not in git; run the tool after updating the submodule. -->",
}
local changed, files = 0, 0

-- Edge cost: the floor models and the engine's decoder, only when there is a model at all.
local EdgeCost = dofile("tools/wownav-edgecost.lua")
local models = EdgeCost.loadModels(SURROUNDINGS)
local N
if next(models) ~= nil then
    WowVisionNavigationNavNetwork = nil
    assert(loadfile("camelot/wownav/engine/NavNetwork.lua"))()
    N = WowVisionNavigationNavNetwork
    -- every continent index, so that the decoder knows each zone
    WVN7Index = {}
    for _, continent in ipairs(listDirs(SOURCE)) do
        local chunk = loadfile(SOURCE .. "/" .. continent .. "/index.lua")
        if chunk then chunk() end
    end
    N.LoadIndex()
else
    print("no surroundings floor model in " .. SURROUNDINGS .. ": no edge cost")
end
local edgeZones, edgeLinks = 0, 0

-- The edge cost file text of a zone (index entry `zone`, its navdata text), or nil.
local function edgeCostText(zone, navText)
    if not N then return nil end
    local list = EdgeCost.modelsFor(models, zone)
    if #list == 0 then return nil end
    WVN7Src = WVN7Src or {}
    WVN7Src[zone.zoneId] = navText
    local decoded = assert(N.LoadZone(zone.zoneId))
    local text, count = EdgeCost.zoneText(decoded, list, zone.name)
    N.UnloadZone(zone.zoneId)
    WVN7Src[zone.zoneId] = nil
    if text then
        edgeZones, edgeLinks = edgeZones + 1, edgeLinks + count
    end
    return text
end
for _, continent in ipairs(listDirs(SOURCE)) do
    local indexPath = SOURCE .. "/" .. continent .. "/index.lua"
    local indexText = read(indexPath)
    if indexText ~= nil then
        mkdir(TARGET .. "/" .. continent)
        local outIndex = TARGET .. "/" .. continent .. "/index.lua"
        if read(outIndex) ~= indexText then
            changed = changed + 1
            if not check then
                write(outIndex, indexText)
            end
        end
        xml[#xml + 1] = '  <Script file="' .. continent .. '\\index.lua" />'
        for _, zone in ipairs(indexZones(indexPath)) do
            mkdir(TARGET .. "/" .. continent .. "/" .. zone.dir)
            for _, kind in ipairs({ "navdata.lua", "logical_targets.lua", "dyn_targets.lua" }) do
                local rel = continent .. "/" .. zone.dir .. "/" .. kind
                local text = assert(read(SOURCE .. "/" .. rel), "missing " .. rel)
                local packed = pack(text, kind, rel)
                files = files + 1
                if read(TARGET .. "/" .. rel) ~= packed then
                    changed = changed + 1
                    if not check then
                        write(TARGET .. "/" .. rel, packed)
                    end
                end
                xml[#xml + 1] = '  <Script file="' .. rel:gsub("/", "\\") .. '" />'
                if kind == "navdata.lua" then
                    local edgeText = edgeCostText(zone, text)
                    local edgeRel = continent .. "/" .. zone.dir .. "/edgecost.lua"
                    if edgeText then
                        if read(TARGET .. "/" .. edgeRel) ~= edgeText then
                            changed = changed + 1
                            if not check then
                                write(TARGET .. "/" .. edgeRel, edgeText)
                            end
                        end
                        xml[#xml + 1] = '  <Script file="' .. edgeRel:gsub("/", "\\") .. '" />'
                    elseif read(TARGET .. "/" .. edgeRel) ~= nil then
                        changed = changed + 1
                        if not check then
                            os.remove(TARGET .. "/" .. edgeRel)
                        end
                    end
                end
            end
        end
    end
end
xml[#xml + 1] = "</Ui>"
local xmlText = table.concat(xml, "\n") .. "\n"
if read(TARGET .. "/data.xml") ~= xmlText then
    changed = changed + 1
    if not check then
        write(TARGET .. "/data.xml", xmlText)
    end
end
print(string.format("%d zone files, edge cost for %d links in %d zones; %d file(s) %s", files, edgeLinks, edgeZones, changed,
    check and "stale" or "written"))
if check and changed > 0 then
    os.exit(1)
end
