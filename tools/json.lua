-- A JSON reader in plain Lua: the offline stand-in for the game's C_EncodingUtil.DeserializeJSON
-- (the headless tests, wv-surroundings' replays). Arrays become lists from 1, objects tables with
-- text keys, null nil. Returns the reader: `local decode = dofile("tools/json.lua")`.
local byte, sub, find, char, concat = string.byte, string.sub, string.find, string.char, table.concat

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(cp)
    if cp < 0x80 then
        return char(cp)
    elseif cp < 0x800 then
        return char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function fail(s, i, what)
    error(string.format("JSON: %s at %d near %q", what, i, sub(s, i, i + 20)), 0)
end

local function skip(s, i)
    local _, e = find(s, "^[ \n\r\t]*", i)
    return e + 1
end

local function readString(s, i)
    local j, parts = i + 1, nil
    while true do
        local a = find(s, '["\\]', j)
        if a == nil then
            fail(s, i, "unfinished text")
        end
        if byte(s, a) == 34 then
            if parts == nil then
                return sub(s, j, a - 1), a + 1
            end
            parts[#parts + 1] = sub(s, j, a - 1)
            return concat(parts), a + 1
        end
        parts = parts or {}
        parts[#parts + 1] = sub(s, j, a - 1)
        local c = sub(s, a + 1, a + 1)
        if c == "u" then
            local cp = tonumber(sub(s, a + 2, a + 5), 16) or fail(s, a, "bad \\u")
            j = a + 6
            if cp >= 0xD800 and cp < 0xDC00 and sub(s, j, j + 1) == "\\u" then
                local lo = tonumber(sub(s, j + 2, j + 5), 16)
                if lo and lo >= 0xDC00 and lo < 0xE000 then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    j = j + 6
                end
            end
            parts[#parts + 1] = utf8(cp)
        else
            parts[#parts + 1] = ESCAPES[c] or fail(s, a, "bad escape")
            j = a + 2
        end
    end
end

local readValue

local function readArray(s, i)
    local t, n = {}, 0
    i = skip(s, i + 1)
    if byte(s, i) == 93 then
        return t, i + 1
    end
    while true do
        local v
        v, i = readValue(s, i)
        n = n + 1
        t[n] = v
        i = skip(s, i)
        local c = byte(s, i)
        if c == 93 then
            return t, i + 1
        elseif c ~= 44 then
            fail(s, i, "expected , or ]")
        end
        i = i + 1
    end
end

local function readObject(s, i)
    local t = {}
    i = skip(s, i + 1)
    if byte(s, i) == 125 then
        return t, i + 1
    end
    while true do
        if byte(s, i) ~= 34 then
            fail(s, i, "expected a key")
        end
        local key
        key, i = readString(s, i)
        i = skip(s, i)
        if byte(s, i) ~= 58 then
            fail(s, i, "expected :")
        end
        t[key], i = readValue(s, i + 1)
        i = skip(s, i)
        local c = byte(s, i)
        if c == 125 then
            return t, i + 1
        elseif c ~= 44 then
            fail(s, i, "expected , or }")
        end
        i = skip(s, i + 1)
    end
end

function readValue(s, i)
    i = skip(s, i)
    local c = byte(s, i)
    if c == 91 then
        return readArray(s, i)
    elseif c == 123 then
        return readObject(s, i)
    elseif c == 34 then
        return readString(s, i)
    elseif sub(s, i, i + 3) == "true" then
        return true, i + 4
    elseif sub(s, i, i + 4) == "false" then
        return false, i + 5
    elseif sub(s, i, i + 3) == "null" then
        return nil, i + 4
    end
    local a, b = find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if a == nil then
        fail(s, i, "unexpected character")
    end
    return tonumber(sub(s, a, b)), b + 1
end

return function(s)
    local v, i = readValue(s, 1)
    i = skip(s, i)
    if i <= #s then
        fail(s, i, "text after the value")
    end
    return v
end
