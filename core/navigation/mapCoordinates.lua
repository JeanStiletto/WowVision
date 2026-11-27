-- Typed coordinates, shared by /beacon (maps/module.lua) and the custom points (maps/customPointsUi.lua), so both take
-- the same input:
--   "45.2 63.1"            map percent of the zone the player is in (the numbers maps and guides give)
--   "world 1198.2 -1116"   world yards, the convention of UnitPosition
-- Between the two numbers: spaces, or a comma or a semicolon with optional spaces. A decimal comma is taken where it
-- cannot be mistaken for the separator: with spaces or a semicolon between the numbers ("45,2 63,1", "45,2;63,1").
-- With a comma between them ("45,63", "45.2, 63.1") the numbers are whole or take a decimal point.
-- parse is pure Lua (headless tests); toWorld asks the game.

local mapCoordinates = {}
WowVision.mapCoordinates = mapCoordinates

local DOT = "(-?%d+%.?%d*)"         -- a number with an optional decimal point
local ANY = "(-?%d+[%.,]?%d*)"      -- a number with an optional decimal point or decimal comma

local function number(text)
    return tonumber((text:gsub(",", ".")))
end

-- Returns "map" | "world", a, b; nil when the text is not two numbers (or map percent outside 0 to 100).
function mapCoordinates.parse(text)
    if type(text) ~= "string" then
        return nil
    end
    local mode = "map"
    local rest = text:match("^%s*[Ww][Oo][Rr][Ll][Dd]%s+(.*)$")
    if rest ~= nil then
        mode = "world"
        text = rest
    end
    text = text:match("^%s*(.-)%s*$")
    local a, b = text:match("^" .. DOT .. "%s*,%s*" .. DOT .. "$")
    if a == nil then
        a, b = text:match("^" .. ANY .. "%s*;%s*" .. ANY .. "$")
    end
    if a == nil then
        a, b = text:match("^" .. ANY .. "%s+" .. ANY .. "$")
    end
    if a == nil then
        return nil
    end
    a, b = number(a), number(b)
    if a == nil or b == nil then
        return nil
    end
    if mode == "map" and (a < 0 or a > 100 or b < 0 or b > 100) then
        return nil
    end
    return mode, a, b
end

-- Map percent of the zone map the player is on -> world x, y (UnitPosition's convention) and the map
-- GetWorldPosFromMapPos names (nil when it names none). Nil when the game gives no position.
function mapCoordinates.toWorld(xPercent, yPercent)
    local uiMap = C_Map.GetBestMapForUnit("player")
    if uiMap == nil then
        return nil
    end
    local map, worldPos = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(xPercent / 100, yPercent / 100))
    if worldPos == nil then
        return nil
    end
    local x, y = worldPos:GetXY()
    return x, y, map
end
