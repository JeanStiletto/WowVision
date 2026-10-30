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
    ["an unpacked zone answers from its index with its flat lists dropped, and has them again on the next entry"] = function(t)
        local zone = loadStored()
        logic.unpack(zone, "enUS")
        local value = logic.valueAtCell(zone, 0, 2)
        local layerIn = zone._index.layerIn
        logic.dropLists(zone)
        t:assertNil(zone.grid)
        t:assertNil(zone.floorCells)
        t:assertNil(zone.indoorIn, "the inside layer's source")
        t:assertNil(layerIn.lanes, "a layer's own lists")
        t:assertEqual(logic.valueAtCell(zone, 0, 2), value)
        t:assertEqual(zone._index.layerIn, layerIn)
        logic.pack(zone)
        logic.unpack(zone, "enUS")
        t:assertNotNil(zone.grid)
        t:assertNotNil(zone.indoorIn)
        t:assertEqual(logic.valueAtCell(zone, 0, 2), value)
    end,
    -- the packed data (tools/surroundings-pack.py): the game's decoder is not here, a stand-in reverses the text
    ["a packed zone unpacks on entry like the text and stays packed after leaving"] = function(t)
        local inflate = logic.inflate
        logic.inflate = function(packed)
            return packed:reverse()
        end
        local zone = loadStored()
        zone.json, zone.deflated = zone.json:reverse(), true
        logic.unpack(zone, "deDE")
        t:assertEqual(zone.places[2][2], "Teststraße")
        t:assertEqual(logic.valueAtCell(zone, 0, 2), 28090)
        logic.pack(zone)
        t:assertEqual(zone.deflated, true)
        logic.unpack(zone, "enUS")
        t:assertEqual(zone.places[2][2], "Test road")
        logic.inflate = inflate
    end,
    ["a packed surfaces layer gives its rows band by band, few kept"] = function(t)
        local inflate, kept = logic.inflate, logic.BANDS_KEPT
        local opened = 0
        logic.inflate = function(packed)
            opened = opened + 1
            return packed
        end
        logic.BANDS_KEPT = 2
        -- bands of 2 rows: rows 0 and 1, 2 (row 3 empty), 6 and 7; band 2 has none
        local layer = logic.bandRows({ x0 = 0, y0 = 0, rec = 10, band = 2,
            bands = { [0] = "row0\nrow1", [1] = "row2\n", [3] = "row6\nrow7" } })
        local rows = layer.rows
        t:assertEqual(rows[0], "row0")
        t:assertEqual(rows[1], "row1")
        t:assertEqual(opened, 1, "one band unpacked for both its rows")
        t:assertNil(rows[3], "an empty row")
        t:assertEqual(rows[2], "row2")
        t:assertNil(rows[4], "a band with no rows")
        t:assertNil(rows[-1], "a row before the layer")
        t:assertEqual(opened, 2)
        t:assertEqual(rows[7], "row7")
        t:assertEqual(opened, 3)
        t:assertNil(rawget(rows, 0), "the band asked for first was let go")
        t:assertEqual(rawget(rows, 2), "row2")
        t:assertEqual(rows[0], "row0", "a band let go unpacks again")
        t:assertEqual(opened, 4)
        logic.inflate, logic.BANDS_KEPT = inflate, kept
    end,
})
