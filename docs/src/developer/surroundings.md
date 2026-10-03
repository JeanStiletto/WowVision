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
  doorway walked through; a room entered that way holds while its floor is within
  `logic.ROOM_SLACK`, `resolveRoom`'s `byDoor`), doorways, entrances. Rooms whose names differ
  only by a trailing number are sections of one thing (`logic.sameRoomName`): walking from one
  into the next says `logic.sectionText` (texts.lua) instead of the full room line. A doorway
  into a room of the very same name (the pieces of one staircase) is never listed.
- `squares.lua`: the region of a square (flood fill), what borders it (mouths), where ways
  begin on it, items around a place, cliffs and water near an outdoor place.
- `objects.lua`: objects one bumps into, whose wall it is.
- `texts.lua`: every spoken text: places, squares, rooms, drop edges, guidance targets.
- `stops.lua`: where one waits for a ship, zeppelin, lift or tram, and which way it will be.

`module.lua` is the WoW side: settings, the alert, the update loop (every 0.2 s:
`updateIndoors`, `updateLayer` for the indoor layer's halls, `updateOutdoors`), the walk log,
`/wv surr` and the describe key.

## Conventions

- A world offset is (dx north, dy west), as `UnitPosition` gives x and y.
- A direction is an angle in degrees clockwise from north (0..359; an axis, both ways of a
  street, 0..179). The words come last: `logic.dirWord` (the 8 compass words, or the 12 clock
  hours with `logic.clock`), `logic.axisWords`, `logic.sameDir` (two angles that come out as one
  word), `logic.finishText` (places the "o'clock").
- A facing (`GetPlayerFacing`) is in radians, 0 = north, counter-clockwise.
- Geometry lives in `zone.lua`: `logic.dist`, `logic.dist2`, `logic.segmentPoint`,
  `logic.nearestOfPoints`, and `logic.nearestPoint` for lists of records with x and y, which
  carries the guidance's stick rule (`logic.sticks`, `GUIDE_STICK`): the target guided to last
  stays unless another is clearly nearer. Use these rather than writing the arithmetic again.
- Derived data lives under `zone._index` (`ix`), built by `logic.unpack` from the data's flat
  lists (`eachRecord`) and dropped by `logic.pack`; lookups per grid cell are buckets keyed
  `row * cols + col`.
- Kinds are the data's English keys ("road", "canal walk", "deep water"); the words spoken
  come from the zone (localized) or from the locale strings. A city's outdoor ramps and stairs
  are the kinds "ramp" and "stairs" (`logic.CLIMBS`): ways with centre lines keyed like streets;
  `wallOwner` names their side when bumped into from beside them.

## Zone data

Each zone file calls `addon.addZone{...}` with:

- `key`, `label`, `map`: the map id `UnitPosition` returns.
- `top`, `left`, `cell`, `rows`, `cols`: the grid. Row 0 lies at world x = `top` (north),
  column 0 at world y = `left` (west); cells are `cell` yards wide.
- `format`: 2. Directions are angles in degrees clockwise from north (an axis, both ways of a
  street, 0..179); the module turns them into the player's words: the 8 compass words, or with
  the compass module's Directions setting the 12 hours of a north-up clock (`logic.clock`,
  `logic.dirWord`, `logic.axisWords`, `logic.finishText` for the "o'clock"). Data of another
  format is left alone and said once.
- `dirs`: direction templates ("water to the %s", "running %s", "up to the %s" for a ramp's or
  stairs' way up); `dirsClock`: the same for the hours ("water at %s"); `compass`: the 8 compass
  words; `axes`: the 4 axis words ("north-south"). A place label may carry directions as angles,
  `<d45,135>` ("fork, Goldshire road <d45,135>"): said with the "to the %s" template in the
  player's words.
- `places`: `{kind, label, nearest road (optional)}` per place id.
- `grid`: one run-length string per row, `"value*count,value,..."`. A value is
  place id * 10000 + direction code; the code is template index * 1000 + angle (0..359, or the
  axis 0..179 for "running %s"); 0 = no data. A way's cells carry the heading of their centre
  line's run (roads.bend_runs), so the spoken word is the nearest one; the entry rule's key
  (`logic.outdoorKey`) quantizes it to the current words and sticks to the word said while the
  heading stays within KEY_STICK degrees of it. A new key of the way the player is on says only
  its direction while that way was the last place named (`logic.sameWay`): the name once, then
  "north to south", until the player leaves the way or another way is named.
- `bridgeUnder`: row, column, value triples: the water under a bridge or the city canal
  under a street, said while swimming.
- `exits`: x, y, width, out quadruples: ways out of city water; out is the angle one climbs out
  toward (-1 = unknown).
- `deadExits`: 1-based indexes into the ways out that lead onto floor joining nothing, or into
  a dead end (decided offline with the heights; optional).
- `noContact`: row, column, row, column quadruples: neighbouring cells of two squares with no
  walkable crossing between them (decided offline with the heights; optional). Such cells are
  no border between the squares.
- `structs`: names of structures with drop edges; `structCells`: row, column, structure
  triples (their floors); `waterStructs`: the structures that are city water edges (no wall).
- `edges`: per drop edge `{structure, facing (the angle of the drop), drop yards, into
  (0 a plain drop, 1 water, 2 a city canal, 3 lava, 4 a moat), piece, x1, y1, x2, y2, ...}`:
  points about 2 yards apart along the edge; `d = {...}` (optional) the depth per point (a
  ramp's side edge: 2 yd at the foot, 9 at the top).
- High floor pieces (wall-walks, bridge decks one can walk under, a city's raised floors): an
  edge with piece 0 lies low; otherwise it warns only after the player was seen stepping onto
  that piece. `pieceCells`: row, column, piece triples (footprints); `access`: piece, kind, x,
  y (kind 1 stepped onto from the ground, 2 out of a building's rooms); `links`: pairs of
  joined pieces. `piecePlaces` (optional): piece, place id pairs, the places of the floor up on
  the piece: a step from the ground counts only from a cell painted with one of them.
- `stacked` (optional): row, column, piece, value up, value below: cells where a high piece
  lies over other floor (decided offline with the heights: the landing of a ramp over the bay
  beside it). The grid holds one value per cell; `logic.valueAtCell` returns the value up
  while the module counts the player on that piece (`logic.setOn`), else the value below, so
  every lookup (places, squares, guidance) follows the level the player is on.
- `lanes`: centre line stretches, `laneFields` values each (10 now; 7 and 8 in older files):
  x1, y1, x2, y2, the cell value there, the distances from the line in 0.1 yards within which
  the way starts to count (enter) and beyond which it stops (leave) left of the stretch's
  direction, the same two right of it (a wall on one side no longer narrows the other), and the
  high piece the stretch runs on (0 = none): such a stretch counts only up on its piece, and
  over a stacked cell the lower floor's stretches do not count while the player is up. 8-field
  files have one width pair and the piece; 7-field files the width pair alone.
- `climbFeet`: the feet of ramps and stairs joined to the way below, `climbFeetFields` values
  each (4; 3 in older files): x, y, the climb's cell value, and the bearing up the climb in
  degrees. Guidance targets on the way, like entrances; two feet of one climb closer than
  `logic.FEET_APART` are one target.
- `objects`: 7 values each: x, y, half length and half width in 0.1 yards, the long axis'
  angle in degrees (0 = north, toward west), name index into `objectNames`, room (0 =
  outdoors).
- `interiors`: `{name, ox, oy, scale, m00, m01, m10, m11, c = 1 (optional)}`: a building and
  its frame. World x = ox - scale * (m00 vx + m01 vy), world y = oy - scale * (m10 vx + m11 vy).
  `c = 1` marks a city's own complex or a map that is one building (Ironforge, the Deeprun
  Tram): it is named after its zone, which the player knows, so its rooms are said without it.
- `rooms`: `{interior, name, kind, floor boxes {x0, y0, x1, y1, ...}, outline box
  (optional), f = floor (sq yd), a = axis (optional), w = winding (optional), s = 1 (optional)}`,
  in the building's frame. `a`: the axis angle (0..179) a long, narrow room runs along, or for
  a piece of a staircase split into pieces (all named alike) the line from its lowest to its
  highest doorway;
  `w`: its floor winds up turning left (1, counter-clockwise seen from above) or right (-1);
  `s`: the room has a name of its own (a shop: "entrance of" it from a hall). A room of at least
  `logic.BIG_ROOM` sq yd says and guides to its doorways from the player's position.
- `doors`: `{room a, room b (0 = outside), interior, x, y, nx, ny, side of room a (0 = a
  flat opening)}`, in the building's frame.
- `indoor` (optional): the indoor layer, the big halls of a city (Ironforge, the Undercity
  quarters) cut into pieces like its streets: `rooms` (the room ids it covers), `grid` (same
  frame and places as the zone's), `lanes`, `noContact`, `structs`, `waterStructs`,
  `structCells` and `edges` (the edges of floors inside: lava, water, canals; they warn in every
  room). `logic.unpack` makes it a zone of its own (`logic.layer(zone)`) that shares the zone's
  words, places, interiors, rooms and doors; its entrances are the doorways from a covered room
  into one that is not (a shop by "entrance of", a passage by its name, the way outside). While
  the player is in a covered room (`logic.inLayer`), the module runs the outdoor rules on it.
- `stops` (optional): where one waits for something that moves: `{kind, destination, room (0 =
  outdoors), cells {row, column, ...}, segments {x1, y1, x2, y2, ...}}`. Kinds `ship`,
  `zeppelin`, `tram` (with a destination: "wait for the ship to Auberdine"), `lift up`, `lift down`;
  the cells are the waiting floor (the dock edge beside a ship, a lift's landing, a tram platform
  along the cars); the segments are where the vehicle stands (a ship along its heading, a lift's
  car as a point, a tram's cars along the track); the direction said is toward the nearest point
  of each, from where the player stands ("ship to the southwest"). An outdoor stop counts only
  outdoors, a stop in a room only in that room (the room the player is in, or the candidates
  while it is unknown). The module says a stop on stepping onto it, again only after the player
  walked 3 yards off every stop; the describe key and `/wv surr` add it.
- A map made of one building (the Deeprun Tram, map 369) has an empty grid: rooms, doors,
  objects, stops, and its platforms' drop edges into the pits under the tracks as the indoor
  layer's `edges` (piece = the platform's room), with no layer grid or rooms.
- Docks and piers are ways: kinds `quay` and `pier` (a spur that joins one other piece), the wide
  parts `square` ("dock of ..."); the water under them is in `bridgeUnder`.
- `locales`: per client language the words with the same indexes as the English lists
  (`dirs`, `compass`, `axes`, `places` as `{label, road}`, `interiors`, `rooms`, `structs`,
  `objectNames`, `stops` as the destinations). Unpacking puts them in place once and drops the other languages.

## Walk log

`/wv surr log on` keeps every announcement (with the data's cell and text there, the room
candidates, the facing) and a position trail every 4 yards in `WowVisionDump.surroundings`,
until `/wv surr log off`. `tools/walklog/module.lua` in wv-surroundings replays a log through
this module itself (stand-ins for the WoW API) and prints what it would say, so a change to the
module or the data can be heard offline on a real walk, and a refactor can be checked for
byte-identical output over every logged walk.
