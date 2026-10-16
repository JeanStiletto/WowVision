-- The data probe (/wv surr probe [zone key]): checks in the game what the planned data format
-- needs (Dev/WowVision/notes/surroundings-data-concept.md, local only): what the surroundings data
-- costs in memory now, and whether the game's own C_EncodingUtil.DeserializeJSON gives a zone's
-- tables back exactly from JSON text (every number, string and list), how fast, and what the
-- decoded tables cost. The zone is the one the player is in (else the largest), or the one named.
-- Every result line is printed to chat and kept in WowVisionDump.surroundingsProbe (written to
-- SavedVariables on /reload or logout). The game stalls for a few seconds while it runs: the JSON
-- text is written in Lua.

local logic = WowVision.surroundingsLogic
local module = WowVision.base.navigation.surroundings

local probe = {}
logic.dataProbe = probe

-- JSON writer ----------------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escape(ch)
    return ESCAPES[ch] or string.format("\\u%04x", ch:byte())
end

-- The shortest text that reads back as exactly this number.
local function numberText(v)
    local s = string.format("%.14g", v)
    if tonumber(s) ~= v then
        s = string.format("%.17g", v)
    end
    return s
end

-- A table whose keys are exactly 1..#t is a JSON array; any other an object with its keys as text.
local function isArray(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count == #t
end

-- Keys starting with "_" are the module's own (the unpacked index): left out.
local function encode(v, out)
    local kind = type(v)
    if kind == "number" then
        out[#out + 1] = numberText(v)
    elseif kind == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', escape) .. '"'
    elseif kind == "boolean" then
        out[#out + 1] = tostring(v)
    elseif kind == "table" then
        if isArray(v) then
            -- long lists broken into lines, as the line-based data files would be
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then
                    out[#out + 1] = i % 50 == 1 and ",\n" or ","
                end
                encode(v[i], out)
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, x in pairs(v) do
                if type(x) ~= "function" and not (type(k) == "string" and k:sub(1, 1) == "_") then
                    if not first then
                        out[#out + 1] = ",\n"
                    end
                    first = false
                    out[#out + 1] = '"' .. tostring(k):gsub('[%c"\\]', escape) .. '":'
                    encode(x, out)
                end
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "null"
    end
end

function probe.encode(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

-- Comparing ------------------------------------------------------------------------------------

-- Compares the original `a` with the decoded `b` and counts into `st`: values (leaves compared),
-- diffs (with up to 5 examples), arrays, arrays whose length differs, number keys that came back
-- only as text keys, keys the decoded side has beyond the original.
local function compare(a, b, path, st)
    if type(a) ~= "table" then
        st.values = st.values + 1
        if a ~= b then
            st.diffs = st.diffs + 1
            if #st.examples < 5 then
                st.examples[#st.examples + 1] = string.format("%s: %s became %s", path, tostring(a), tostring(b))
            end
        end
        return
    end
    if type(b) ~= "table" then
        st.diffs = st.diffs + 1
        if #st.examples < 5 then
            st.examples[#st.examples + 1] = string.format("%s: a table became %s", path, tostring(b))
        end
        return
    end
    if isArray(a) then
        st.arrays = st.arrays + 1
        if #b ~= #a then
            st.lengthDiffs = st.lengthDiffs + 1
            if #st.examples < 5 then
                st.examples[#st.examples + 1] = string.format("%s: list of %d became %d long", path, #a, #b)
            end
        end
    end
    for k, v in pairs(a) do
        if type(v) ~= "function" and not (type(k) == "string" and k:sub(1, 1) == "_") then
            local bv = b[k]
            if bv == nil and type(k) == "number" then
                bv = b[tostring(k)]
                if bv ~= nil then
                    st.numberKeysAsText = st.numberKeysAsText + 1
                end
            end
            compare(v, bv, path .. "." .. tostring(k), st)
        end
    end
    for k in pairs(b) do
        if a[k] == nil and a[tonumber(k)] == nil then
            st.extraKeys = st.extraKeys + 1
        end
    end
end

function probe.compare(a, b)
    local st = { values = 0, diffs = 0, arrays = 0, lengthDiffs = 0, numberKeysAsText = 0, extraKeys = 0, examples = {} }
    compare(a, b, "zone", st)
    return st
end

-- The small cases: each a JSON text and a check of what the decoder gave.
probe.CASES = {
    { "a list comes back as a 1-based list", "[10,20,30]", function(t)
        return type(t) == "table" and t[1] == 10 and t[3] == 30 and #t == 3
    end },
    { "an empty list comes back as an empty table", '{"e":[]}', function(t)
        return type(t) == "table" and type(t.e) == "table" and next(t.e) == nil
    end },
    { "lists in lists", "[[1,2],[3]]", function(t)
        return type(t) == "table" and type(t[1]) == "table" and t[1][2] == 2 and t[2][1] == 3 and #t == 2
    end },
    { "tenths of a yard exact", "[-8926.6,1222.9,0.1]", function(t)
        return type(t) == "table" and t[1] == -8926.6 and t[2] == 1222.9 and t[3] == 0.1
    end },
    { "big and negative whole numbers", "[3180113,-9173,2147483648]", function(t)
        return type(t) == "table" and t[1] == 3180113 and t[2] == -9173 and t[3] == 2147483648
    end },
    { "text with umlauts, accents, quotes and a line break", '["Stra\\u00dfe Straße \\"zum\\" Platz é\\nzwei"]', function(t)
        return type(t) == "table" and t[1] == 'Straße Straße "zum" Platz é\nzwei'
    end },
    { "true and false", "[true,false]", function(t)
        return type(t) == "table" and t[1] == true and t[2] == false
    end },
    { "line breaks and spaces between values", '{\n  "a" : [ 1 ,\n 2 ]\n}\n', function(t)
        return type(t) == "table" and type(t.a) == "table" and t.a[2] == 2
    end },
    { 'an object key "1" stays the text "1"', '{"1":"one","x":"ex"}', function(t)
        return type(t) == "table" and t["1"] == "one" and t[1] == nil and t.x == "ex"
    end },
}

-- In the game ----------------------------------------------------------------------------------

local function memoryKB(addon)
    local ok, kb = pcall(GetAddOnMemoryUsage, addon)
    return ok and kb or nil
end

local function pickZone(key)
    local zones = WowVisionSurroundingsData and WowVisionSurroundingsData.zones or {}
    local x, y, _, map = UnitPosition("player")
    local here, largest
    for _, z in ipairs(zones) do
        if key ~= "" and z.key == key then
            return z
        end
        if here == nil and x and z.map == map and logic.covers(z, x, y) then
            here = z
        end
        if largest == nil or (z.rows or 0) * (z.cols or 0) > (largest.rows or 0) * (largest.cols or 0) then
            largest = z
        end
    end
    if key ~= "" then
        return nil
    end
    return here or largest
end

function module:dataProbe(args)
    local key = (args or ""):match("^(%S*)")
    local lines = {}
    local result = { date = date("%Y-%m-%d %H:%M:%S"), lines = lines }
    local function line(text)
        lines[#lines + 1] = text
        print("WV probe: " .. text)
    end

    -- what the data costs now: all zones are kept as tables all the time
    pcall(UpdateAddOnMemoryUsage)
    result.surroundingsKB = memoryKB("WowVision_Surroundings")
    result.wowVisionKB = memoryKB("WowVision")
    result.luaKB = collectgarbage("count")
    line(string.format("memory now: WowVision_Surroundings %s KB, WowVision %s KB, all Lua %.0f KB",
        result.surroundingsKB and string.format("%.0f", result.surroundingsKB) or "unknown",
        result.wowVisionKB and string.format("%.0f", result.wowVisionKB) or "unknown", result.luaKB))

    local util = C_EncodingUtil
    result.hasJSON = util ~= nil and type(util.DeserializeJSON) == "function"
    result.hasCBOR = util ~= nil and type(util.DeserializeCBOR) == "function"
    line(string.format("C_EncodingUtil: %s, DeserializeJSON %s, DeserializeCBOR %s", util and "there" or "missing",
        result.hasJSON and "there" or "missing", result.hasCBOR and "there" or "missing"))

    if result.hasJSON then
        -- the small cases
        local passed = 0
        result.cases = {}
        for _, case in ipairs(probe.CASES) do
            local ok, t = pcall(util.DeserializeJSON, case[2])
            local good = ok and case[3](t) or false
            result.cases[#result.cases + 1] = { case[1], good, not ok and tostring(t) or nil }
            if good then
                passed = passed + 1
            else
                line("case failed: " .. case[1] .. (ok and "" or (", error " .. tostring(t))))
            end
        end
        line(string.format("small cases: %d of %d passed", passed, #probe.CASES))

        -- a whole zone: JSON text, decoded, compared value by value
        local zone = pickZone(key)
        if zone == nil then
            line(key ~= "" and ("no zone with the key " .. key) or "no surroundings data loaded")
        else
            result.zone = zone.key
            local t0 = debugprofilestop()
            local text = probe.encode(zone)
            local t1 = debugprofilestop()
            result.jsonBytes = #text
            result.writeMs = t1 - t0
            collectgarbage("collect")
            local before = collectgarbage("count")
            local t2 = debugprofilestop()
            local ok, decoded = pcall(util.DeserializeJSON, text)
            local t3 = debugprofilestop()
            local after = collectgarbage("count")
            result.decodeMs = t3 - t2
            result.decodedKB = after - before
            line(string.format("zone %s: JSON text %.0f KB, written in Lua in %.0f ms", zone.key, #text / 1024, result.writeMs))
            if not ok or type(decoded) ~= "table" then
                result.decodeError = tostring(decoded)
                line("decoding failed: " .. tostring(decoded))
            else
                line(string.format("decoded by the game in %.1f ms; the tables take %.0f KB (the text %.0f KB)",
                    result.decodeMs, result.decodedKB, #text / 1024))
                local st = probe.compare(zone, decoded)
                result.compare = st
                line(string.format("compared %d values in %d lists: %d differ, %d lists of another length, "
                    .. "%d number keys came back as text, %d keys beyond the original",
                    st.values, st.arrays, st.diffs, st.lengthDiffs, st.numberKeysAsText, st.extraKeys))
                for _, example in ipairs(st.examples) do
                    line("  " .. example)
                end
            end
            text, decoded = nil, nil
            collectgarbage("collect")
        end
    end

    WowVisionDump = WowVisionDump or {}
    WowVisionDump.surroundingsProbe = result
    line("kept in WowVisionDump.surroundingsProbe; /reload writes it to SavedVariables")
    WowVision:speak("Data probe done, " .. #lines .. " lines in chat")
end
