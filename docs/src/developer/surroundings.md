# Surroundings (WoW: Forever)

The surroundings module (`camelot/surroundings/`) describes where the player walks from map
data prepared offline. The data comes from the separate **WowVision_Surroundings** addon
(its own repository, [JeanStiletto/WowVision_Surroundings](https://github.com/JeanStiletto/WowVision_Surroundings)), generated from the client's map files by the wv-surroundings tools (`tools/export.py`), one
Lua file per zone. The module reads `WowVisionSurroundingsData.zones` and unpacks a zone only
while the player is in it.

## Files

Pure logic, no WoW API calls, loaded by the headless suite (`tools/headless-tests.lua`) and
tested in `tests.lua`:

- `zone.lua`: the `WowVision.surroundingsLogic` table; directions; the grid; unpacking a
  zone into named records (all derived data under `zone._index`; `logic.pack` drops it);
  place texts; the entry rule (`logic.newEntry`); outdoor keys.
- `edges.lua`: drop edges of structures, the high floor pieces they lie on, water under
  bridges, ways out of the water.
- `lanes.lua`: centre lines of roads and streets: whether the player is on the way, turn
  hints, where a road leads, gentle bends.
- `rooms.lua`: building frames, rooms without a height (stacked floors resolved by the
  doorway walked through), doorways, entrances.
- `squares.lua`: the region of a square (flood fill), what borders it (mouths), where ways
  begin on it, items around a place, cliffs and water near an outdoor place.
- `objects.lua`: objects one bumps into, whose wall it is.
- `texts.lua`: every spoken text: places, squares, rooms, drop edges, guidance targets.

`module.lua` is the WoW side: settings, the alert, the update loop (every 0.2 s), the walk
log, `/wv surr` and the describe key.

## Conventions

- A world offset is (dx north, dy west), as `UnitPosition` gives x and y.
- Compass indexes run from 1 = north clockwise to 8 = northwest; axes 1 to 4 are
  north-south, northeast-southwest, east-west, northwest-southeast.
- A facing (`GetPlayerFacing`) is in radians, 0 = north, counter-clockwise.
- Kinds are the data's English keys ("road", "canal walk", "deep water"); the words spoken
  come from the zone (localized) or from the locale strings.

## Zone data

Each zone file calls `addon.addZone{...}` with:

- `key`, `label`, `map`: the map id `UnitPosition` returns.
- `top`, `left`, `cell`, `rows`, `cols`: the grid. Row 0 lies at world x = `top` (north),
  column 0 at world y = `left` (west); cells are `cell` yards wide.
- `dirs`: direction templates ("water to the %s", "running %s"); `compass`: the 8 compass
  words; `axes`: the 4 axis words ("north-south").
- `places`: `{kind, label, nearest road (optional)}` per place id.
- `grid`: one run-length string per row, `"value*count,value,..."`. A value is
  place id * 100 + direction code; the code is template index * 10 + word index (a compass
  word, or an axis for "running %s"); 0 = no data.
- `bridgeUnder`: row, column, value triples: the water under a bridge or the city canal
  under a street, said while swimming.
- `exits`: x, y, width, out quadruples: ways out of city water; out is the compass index one
  climbs out toward (0 = unknown).
- `deadExits`: 1-based indexes into the ways out that lead onto floor joining nothing, or into
  a dead end (decided offline with the heights; optional).
- `structs`: names of structures with drop edges; `structCells`: row, column, structure
  triples (their floors); `waterStructs`: the structures that are city water edges (no wall).
- `edges`: per drop edge `{structure, facing (compass index of the drop), drop yards, into
  (0 a plain drop, 1 water, 2 a city canal), piece, x1, y1, x2, y2, ...}`: points about 2
  yards apart along the edge.
- High floor pieces (wall-walks, bridge decks one can walk under): an edge with piece 0 lies
  low; otherwise it warns only after the player was seen stepping onto that piece.
  `pieceCells`: row, column, piece triples (footprints); `access`: piece, kind, x, y
  (kind 1 stepped onto from the ground, 2 out of a building's rooms); `links`: pairs of joined
  pieces.
- `lanes`: centre line stretches, 7 values each: x1, y1, x2, y2, the cell value there, and
  the distances from the line in 0.1 yards within which the way starts to count (enter) and
  beyond which it stops (leave).
- `objects`: 7 values each: x, y, half length and half width in 0.1 yards, the long axis'
  angle in degrees (0 = north, toward west), name index into `objectNames`, room (0 =
  outdoors).
- `interiors`: `{name, ox, oy, scale, m00, m01, m10, m11}`: a building and its frame. World
  x = ox - scale * (m00 vx + m01 vy), world y = oy - scale * (m10 vx + m11 vy).
- `rooms`: `{interior, name, kind, floor boxes {x0, y0, x1, y1, ...}, outline box
  (optional)}`, in the building's frame.
- `doors`: `{room a, room b (0 = outside), interior, x, y, nx, ny, side of room a (0 = a
  flat opening)}`, in the building's frame.
- `locales`: per client language the words with the same indexes as the English lists
  (`dirs`, `compass`, `axes`, `places` as `{label, road}`, `interiors`, `rooms`, `structs`,
  `objectNames`). Unpacking puts them in place once and drops the other languages.

## Walk log

`/wv surr log on` keeps every announcement (with the data's cell and text there, the room
candidates, the facing) and a position trail every 4 yards in `WowVisionDump.surroundings`,
until `/wv surr log off`. The walklog tools in wv-surroundings replay a log against the data
offline.
