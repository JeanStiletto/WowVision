local testRunner = WowVision.testing.testRunner
local logic = WowVision.surroundingsLogic

-- The stored data (format 4) against the model it was made from: tools/testdata has a tiny zone of
-- the model using every part format 4 stores, and the file wv-surroundings tools/store.py wrote from
-- it. Expanding the stored zone must give the model back value by value, in every language.

local function loadModel()
    local zone
    assert(loadfile("tools/testdata/surroundings-model.lua"))(nil, { addZone = function(z) zone = z end })
    return zone
end

local function loadStored()
    local zone
    assert(loadfile("tools/testdata/surroundings-store.lua"))(nil, { addZone = function(header, json)
        header.json = json
        zone = header
    end })
    return zone
end

-- The first difference between `a` and `b` as text, or nil.
local function difference(a, b, path)
    if type(a) ~= type(b) then
        return string.format("%s: %s became %s", path, tostring(a), tostring(b))
    end
    if type(a) ~= "table" then
        return a ~= b and string.format("%s: %s became %s", path, tostring(a), tostring(b)) or nil
    end
    for k, v in pairs(a) do
        local d = difference(v, b[k], path .. "." .. tostring(k))
        if d then
            return d
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return path .. "." .. tostring(k) .. ": only in the expanded zone"
        end
    end
end

testRunner:addSuite("Surroundings stored data", {
    ["expanding the stored zone gives the model back in every language"] = function(t)
        local model = loadModel()
        local locales = model.locales
        model.format = logic.FORMAT
        for _, locale in ipairs({ "enUS", "deDE", "frFR" }) do
            local zone = loadStored()
            local data = logic.decodeJson(zone.json)
            zone.json = nil
            logic.expand(zone, data, locale)
            model.locales = locale ~= "enUS" and { [locale] = locales[locale] } or nil
            t:assertNil(difference(model, zone, "zone"), locale)
        end
    end,
    ["a registered zone unpacks on entry and keeps only its frame and text after leaving"] = function(t)
        local zone = loadStored()
        logic.unpack(zone, "deDE")
        t:assertEqual(zone.places[2][2], "Teststraße")
        t:assertEqual(logic.valueAtCell(zone, 0, 2), 28090)
        t:assertNotNil(zone._index.layer, "the halls layer")
        t:assertEqual(zone._index.layerIn.cell, 5)
        logic.pack(zone)
        local left = {}
        for key in pairs(zone) do
            left[#left + 1] = key
        end
        table.sort(left)
        t:assertEqual(table.concat(left, ","), "cell,cols,format,json,key,label,left,map,rows,top")
        logic.unpack(zone, "enUS")
        t:assertEqual(zone.places[2][2], "Test road")
        t:assertEqual(zone.rooms[3].sn, "canal 2")
        t:assertEqual(zone.interiors[2].c, 1)
        t:assertEqual(zone.doorVia[3], 2)
    end,
})
