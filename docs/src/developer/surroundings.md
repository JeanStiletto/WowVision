# Surroundings (WoW: Forever, TBC, Era)

The surroundings module (`camelot/surroundings/`) describes where the player walks from map
data prepared offline. The data is the repository
[JeanStiletto/WowVision_Surroundings](https://github.com/JeanStiletto/WowVision_Surroundings), a
git submodule at `mapdata/WowVision_Surroundings` (as `locale/` is): it is loaded as part of
WowVision: each game version has its folder there, packed for the game by `tools/surroundings-pack.py`
into the git-ignored `mapdata/WowVision_SurroundingsPacked` ("Packed data" below), and its modules.xml
includes the packed folder's `data.xml` after the module (`camelot/` `forever/data.xml`, `tbc/`
`tbc/data.xml`, `vanilla/` `era/data.xml`). It is generated from
the client's map files by the wv-surroundings tools (`tools/export.py`, stored by
`tools/store.py`), one Lua file per zone. Each zone file registers its frame and its data as
JSON text (`addZone`, on WowVision's own addon table); the module decodes and unpacks a zone only
while the player is in it, and drops it again on leaving ("Stored data" below).

## Files

Pure logic, no WoW API calls, loaded by the headless suite (`tools/headless-tests.lua`) and
tested in `tests.lua` (the stored data in `storeTests.lua`, against `tools/testdata`):

- `store.lua`: the stored data (format 4) expanded into the model (`logic.expand`); the fields a
  zone keeps while the player is elsewhere (`logic.ZONE_HEADER`).

- `zone.lua`: the `WowVision.surroundingsLogic` table; directions; the grid; unpacking a
  zone into named records (all derived data under `zone._index`; `logic.pack` drops it);
  place texts; the entry rule (`logic.newEntry`); outdoor keys.
- `edges.lua`: drop edges (of the cities' floors, structures, buildings; a drop into a liquid
  is one like any other) and the floor piece the player is on (`logic.updateFloor`: the walk-graph
  tracker, `logic.swimFloor`, `logic.setFloor`, `logic.joinedPieces`). The way-out target
  (`logic.exitTarget`) lives in `texts.lua`.
- `lanes.lua`: centre lines of roads and streets: whether the player is on the way, turn
  hints, where a road leads, gentle bends, the facings the turn key turns to without a beacon
  (`logic.lineFacings`: a way's or bridge's line, else its said direction; `logic.lineTurnFacing`; the module hands them to the maps module's
  `facingWithoutWaypoint`).
- `rooms.lua`: building frames, rooms without a height (in a city's indoor layer the room whose floor
  the player's floor piece is, `logic.floorRoomsAt` from the layer's `floorRooms`; elsewhere stacked floors resolved by the
  doorway walked through; a room entered that way holds while its floor is within
  `logic.ROOM_SLACK` or one of its doorways within `logic.DOOR_HOLD`, 4 yd: `resolveRoom`'s
  `byDoor`), doorways, entrances. Rooms change as floors do (`logic.onFloorRooms`): a hall stays
  a candidate only as the current room, one joined to it by a doorway, or a hall lying on the
  zone's floor piece here. Rooms whose names differ
  only by a trailing number are sections of one thing (`logic.sameRoomName`): walking from one
  into the next says `logic.sectionText` (texts.lua) instead of the full room line. A doorway
  into a room of the very same name (the pieces of one staircase) is never listed.
- `places.lua`: the places list (Alt-F10, "Places list" below; the window is `placesUi.lua`).
- `squares.lua`: the region of a square (flood fill), what borders it (mouths), where ways
  begin on it, items around a place, cliffs and water near an outdoor place.
- `objects.lua`: whose wall one bumps into outside (`logic.wallOwner`). What one bumps into is named by the bump
  module (`core/navigation/bumps.lua`); `module.lua` hands it this module's room and wall text
  (`bumps:setRoomSource`). The building frames, the room floors under a position (`logic.roomCandidates`), the room
  outlines and the doorway crossing (`logic.crossedDoor`) are the bump layer's (`core/navigation/bumpLogic.lua`,
  since 2026-11-07: one set of rules for both; the rooms, buildings and doorways here carry its fields). The
  objects are only in its index.
- `texts.lua`: every spoken text: places, squares, rooms, drop edges, guidance targets.
- `stops.lua`: where one waits for a ship, zeppelin, lift or tram, and which way it will be.
- `helper.lua`: the building helper (Alt plus the turn key) and the climbs' routes: a beacon route to the next
  doorway, entrance or way out of the water, or along a climb's own stored centre line to its other end and the
  floor joined there (`logic.helperRoute`, `logic.climbRouteFrom`); the turn key's facing on a climb
  (`logic.climbLineFacing`). It follows only what the export stored (tested in `helperTests.lua`).
- `tracker.lua`: the walk-graph tracker, the floor piece the player is on followed over a layer's own floor
  surfaces (the zone's `<zone>-surfaces.lua` file, written by the tools' `surfaces.py`: every floor surface in
  1 yd columns with its height, its piece and its steps to the neighbouring columns), with a few costed
  candidates per look.

`module.lua` is the WoW side: settings, the alert, the update loop, the walk log, `/wv surr`,
`/wv surr around` and the describe key (both run `describeAround`). Every 0.2 s the loop pauses
on a flight (`UnitOnTaxi`), then runs `updateHall` (the halls the game calls outdoors),
and `updateIndoors` (with `updateLayer` for the indoor layer's halls) or
`updateOutdoors`. `keepHere` stores the room and the floor pieces per character in
`WowVisionDB.surroundingsHere`; `restoreHere` takes them back after a reload or login, only on
the same spot (within 1.5 yd), and finds a floor piece again by the place it carries there,
since every export numbers the pieces anew.

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
  `row * cols + col`, except the objects and the centre line stretches, which sit in buckets per block of
  4 by 4 cells with their box of cells (`logic.blockOf`, `logic.boxHolds`; a cell's stretches:
  `logic.lanesAt`): the same items in the same order per cell, a fraction of the memory. Cells whose
  floor table or rooms-by-floor table were built by the same records share one table (`shareCells`):
  nothing may write into them after the unpack. The grid's rows become runs when first read
  (`logic.gridRow`, the 64 read last kept). In the game `findZone` then drops the flat lists
  (`logic.dropLists`: nothing reads them after the unpack; the offline tools keep them), and the walk
  log's zone line carries the unpack's milliseconds and the Lua memory after it (`unpackMs`, `luaMB`).
- Kinds are the data's English keys ("road", "canal walk", "deep water"); the words spoken
  come from the zone (localized) or from the locale strings. Ramps and stairs are the kinds
  "ramp" and "stairs" (`logic.CLIMBS`): ways with centre lines keyed like streets, on every
  floor (outdoors, in the halls, in mapped buildings) since the 2026-10-11 export, their feet
  carrying the floor piece they stand on; `wallOwner` names their side when bumped into from
  beside them.

## Stored data (format 4)

A zone file calls `addon.addZone(header, json)`: the header is the zone's `key`, `label`, `map`,
its grid frame (`top`, `left`, `cell`, `rows`, `cols`) and `format = 4`; `json` is the data as
JSON text, one row or record to a line so git diffs stay readable. The module keeps only these
(`logic.ZONE_HEADER`) for the zones the player is not in. On entry `logic.unpack` decodes the text
(`logic.decodeJson`: the game's `C_EncodingUtil.DeserializeJSON`; offline `tools/json.lua`) and
`logic.expand` (`store.lua`) turns it into the model below, exactly: every list in its order, every
value as the export wrote it (wv-surroundings `tools/store.py` refuses to write a zone whose stored
form does not give the model back value by value). `logic.pack` drops it again on leaving.

The JSON object:

- `format`: 4. `palette`: the grid's cell values; a row of a grid is palette index, count pairs.
- `places`: the kind of every place id (its names are in `names`).
- `placeDirs` (optional): `{"index": template}` for the places that have their own direction
  template (the same in every language): a cave's or a mine's cells say it instead of their cell's
  template. Written only where a place has one.
- `words`: per client language (`enUS`, `deDE`, `frFR`) the model's `dirs`, `dirsClock`,
  `compass`, `axes`, `floors`, `ofTemplate`. They stay in the data: a grid value's direction code
  is the index of its template here.
- `names`: per language every name: `places` as `[label, road or "", of or ""]`, `interiors`,
  `interiorWalls`, `rooms`, `roomsShort`, `roomsArea`, `roomsAtA`, `roomsAtB` (these five as
  `{"index": name}` for the ones that have one), `spoken`, `structs`, `objectNames`, `stops` (the
  destinations).
- `buildings`: `interiors` (`ox, oy, scale, m00, m01, m10, m11, c` with c 0 or 1), `rooms` (`i`
  interior, `k` kind, `b` floor boxes, `o` outline, and the model's named fields but the names),
  `doors` (the model's 9 values, then the door's two `doorVia` values where `doorVia` is true).
- `objects`: `shapes` (half length, half width, name: 3 values each) and `list` (x, y, angle,
  shape, room: 5 values each).
- `stops`: `[kind, room, cells, segments, floor pieces]` (the destination is in `names`).
- `layers`: `ground` (the zone's own), `halls` (the model's `indoor`), `inside` (`indoorIn`),
  one schema: `frame` (a layer's own grid), `grid`, `cells` with runs along a row (row, column,
  count, then the values; count < 0: the columns go down) for `floor` (floorCells), `noGround`,
  `struct` (structCells), `rooms` (floorRooms), `hallGround`; `joins` as groups of one pair (a, b,
  then x, y, angle per join); `lines`: the centre line stretches as polylines (their 6 values, the
  number of points, the points, then the stretches' headings), `lineHeadings` whether the model
  has headings; `exits` with 6 values each (x, y, width, way out, floor, group); `edges` as
  `{h = the first 5 values, p = points, l, u, d}`; `climbFeet`, `climbAims`; and as the model has
  them `noContact`, `liquids`, `lineFloors`, `doorFloors`, `waterStructs`, `structs`,
  `rooms` (a layer's covered rooms).
- Coordinates (points, ways out, climbs, objects, joins) are whole tenths of a yard; a path (a
  polyline's or an edge's points) is its first point, then each the step from the one before.
- `extra` (in the zone or a layer): model fields the store does not know yet, kept as they are.

## Packed data

git keeps the data as readable text (diffs, history, and every offline tool reads it); the game loads it packed,
about a fifth of the size, so a login reads and keeps far less (TBC 2026-10-30: 22.6 MB of text, 4.9 MB packed).
`tools/surroundings-pack.py` writes `mapdata/WowVision_SurroundingsPacked/<client>/` (generated, git-ignored, as
`tools/wownav-pack.lua` does for the WowNav data):

- a zone file: its header with `deflated = true`, its JSON text zlib-compressed and Base64-coded;
  `logic.unpack` gives it to `logic.inflate` first (the game's `C_EncodingUtil.DecodeBase64` and
  `DecompressString` with `Enum.CompressionMethod.Zlib`), then decodes it as before;
- a surfaces file: per layer its frame with `band` (rows per band, 32) and `bands` (per band one packed string
  of its rows, a line each, an empty line for a row with none) in place of `rows`; `logic.bandRows` (store.lua)
  gives the layer a `rows` table that unpacks a band when a row of it is first read and keeps only the
  `logic.BANDS_KEPT` bands read last, so `tracker.lua` reads rows as before;
- a places list file: copied as it is.

Every packed file names the SHA-1 of its source text; the tool unpacks everything it packs and compares it with
the source before writing. It runs at the end of every export into the data (wv-surroundings `store.py`
`write_data_xml`) and must run after the data submodule changes in git (a checkout, a pull):
`py tools/surroundings-pack.py` (all clients), `--client tbc` (one), `--check` (report stale files, exit code 1).
A release build runs it before packaging.

## Zone data

The model: what `logic.expand` makes of a zone file, and what the logic and the tests read. A zone
of the model has:

- `key`, `label`, `map`: the map id `UnitPosition` returns.
- `top`, `left`, `cell`, `rows`, `cols`: the grid. Row 0 lies at world x = `top` (north),
  column 0 at world y = `left` (west); cells are `cell` yards wide.
- `format`: the stored data's (4; the model itself is format 3's shape: the floor pieces
  (`floorCells`, `noGround`, `joins`, `liquids`) on top of format 2's angles). Directions are angles in degrees clockwise from north (an axis, both ways of a
  street, 0..179); the module turns them into the player's words: the 8 compass words, or with
  the compass module's Directions setting the 12 hours of a north-up clock (`logic.clock`,
  `logic.dirWord`, `logic.axisWords`, `logic.finishText` for the "o'clock"). Data of another
  format is left alone and said once.
- `dirs`: the 13 direction templates, in this order: "water to the %s", "deep water to the %s",
  "land to the %s", "drop to the %s", "rock wall to the %s", "building to the %s", "to the %s",
  "running %s", "up to the %s" (a ramp's or stairs' way up; the module says a climb by its axis
  instead, `logic.directionText`, and keys each flight by its rise, `logic.outdoorKey`), "cave to
  the %s", "mine to the %s", "crypt to the %s", "tunnel to the %s" (a place's own template, `dir`:
  a cell holds templates 1 to 9 only); `dirsClock`: the same 13 for the hours ("water at %s", "at %s", "up at %s"); `compass`: the 8
  compass words; `axes`: the 4 axis words ("north-south"). A place label may carry directions as
  angles, `<d45,135>` ("fork, Goldshire road <d45,135>"): said with the "to the %s" template in
  the player's words.
- `places`: `{kind, label, nearest road (optional), of = structure (optional), dir = template
  (optional)}` per place id. `dir` is the direction template the place's cells are said with instead
  of their own ("cave to the north" beside a cave, never "building"; `logic.directionText`).
  `of` names the structure a place belongs to (a tower's platform, its stairs); it is said
  through `ofTemplate` ("%s of %s") where the player is not on that structure already.
- `floors` (optional): per named floor of a building `{word, its own room's name, the stairs up
  to it, those stairs said plainly}` ("upstairs", "upstairs landing", "stairs to the upstairs
  landing", "stairs"). One floor may have several entries (reached by stairs and by a ramp); its
  first entry counts. The floor is said once, like a building's name: on that floor its rooms
  and stairs are said without it (`logic.floorOf`, `logic.floorLabel`).
- `ofTemplate`: the template a structure is added with ("%s of %s"); also used for a wall
  bumped into ("wall of <place>").
- `spoken` (optional): numbered room names said otherwise, name to spoken form ("cellar 2" is
  said "cellar"; `logic.spokenName`, and `logic.spokenText` inside a longer text, longest names
  first).
- `grid`: one run-length string per row, `"value*count,value,..."`. A value is
  place id * 10000 + direction code; the code is template index * 1000 + angle (0..359, or the
  axis 0..179 for "running %s"); 0 = no data. A way's cells carry the heading of their centre
  line's run (roads.bend_runs), so the spoken word is the nearest one; the entry rule's key
  (`logic.outdoorKey`) quantizes it to the current words and sticks to the word said while the
  heading stays within KEY_STICK degrees of it. A new key of the way the player is on says only
  its direction while that way was the last place named (`logic.sameWay`): the name once, then
  "north to south", until the player leaves the way or another way is named.
- `exits`: x, y, width, out quadruples: ways out of the liquids (the joins of a liquid's piece
  with floor, in stretches of 10 yards at most); out is the angle one climbs out toward (-1 =
  unknown); `exitFloors`: per way out the floor piece it leads out of (the liquid's): guided to
  only from that piece; `exitGroups`: per way out its group. The stretches of one way out (a long
  shore) share a group, and the guidance keys its target by the group, so it is named once while
  it follows the nearest stretch. In an indoor layer the moat's ways out come first, each with a
  negative group of its own.
- `noContact`: row, column, row, column quadruples: neighbouring cells of two squares with no
  walkable crossing between them (decided offline with the heights; optional). Such cells are
  no border between the squares.
- `structs`: names of structures with drop edges; `structCells`: row, column, structure
  triples (their floors); `waterStructs`: the structures that are a city's floor edges (no wall).
- `edges`: per drop edge `{structure, facing (the angle of the drop), drop yards, into
  (0 a plain drop, 1 water, 2 a city canal, 3 lava: the liquid the drop lands in; 4 a moat's
  floor), room (indoor layers: the room
  the edge's floor belongs to, 0 any; 0 outdoors), x1, y1, x2, y2, ...}`: points about 2 yards
  apart along the edge; named fields after them: `l = piece` the floor piece the edge's floor is
  on (0 the ground; not optional: an edge without `l` never counts), and optionally `d = {...}`
  the depth per point (a ramp's side edge: 2 yd at the foot, 9 at the top) and `u = piece` the
  piece its drop lands on (0 the ground, a liquid's piece for a drop into it). An edge warns only
  while the player is on its floor piece, or on a piece joined to it (`logic.joinedPieces`).
- Floor pieces (one rule for every floor over or under another, 2026-10-05; `floors.py` in the
  exporter): the player is always on exactly one piece, 0 being the ground. A piece is connected
  walkable floor cut where a climb begins (every flight of stairs or ramp is a piece) and where a
  floor lies over itself; flat floor that lies over or under no other floor is the ground.
  `floorCells`: row, column, piece, value: the pieces present in a cell besides the ground, each
  with its place value there (the grid holds the ground's); `noGround`: row, column pairs, the
  cells where the ground has no floor; `joins`: a, b, x, y, angle: where piece a meets piece b
  (a 0 the ground, -1 a building's door) with the direction from a into b in degrees (-1 none:
  such a join only leads from a into b; -2 no point: the two are joined somewhere). The module
  (`logic.updateFloor`) follows the floor on the layer's walk-graph surfaces (`tracker.lua`, every zone's data
  has them since the Deeprun Tram's of 2026-10-30; the piece tracker of before, which changed the floor at the
  joins crossed, the drop edges crossed and the climbs' lines, is gone); a grid with no surfaces keeps the floor
  it was set to. A liquid's surface (water, lava, slime) is a floor piece of its own
  (`liquids`: piece, kind pairs, kind 1 water, 2 city water, 3 lava; its cells in `floorCells`
  with the liquid's place, the canal's name or the water under a bridge): swimming is the one
  height the game tells, so `updateFloor` (its `swimming` argument: true, false, nil in the air)
  keeps a swimming player on a liquid's surface and a player on foot off it (`logic.swimFloor`: the
  floor stood up onto out of a liquid); on a liquid's piece no centre line decides the place, and its ways out are
  guided to (`logic.exitTarget` with the piece). `logic.valueAtCell` returns the floor piece's value where the cell
  lists it, else the grid's, so every lookup (places, squares, lanes, guidance) follows the
  floor the player is on; a square's neighbours are the cells its floor goes on into and the
  pieces it joins there (`logic.mouthValue`). In a house's layer a room's opening into another room is its
  doorway (the portal record, `logic.doorsBetween`): the grid cuts no walls between rooms, so
  two rooms with no doorway between them are no neighbours; a city's halls keep the grid's
  openings (no doorway records between them).
- `lanes`: centre line stretches, 10 values each (`laneFields`, always 10):
  x1, y1, x2, y2, the cell value there, the distances from the line in 0.1 yards within which
  the way starts to count (enter) and beyond which it stops (leave) left of the stretch's
  direction, the same two right of it (a wall on one side no longer narrows the other), and the
  floor piece the stretch runs on where that floor lies over or under other floor (0 = the
  ground; -1 = not stacked: the stretch counts on every floor, the position alone finds it):
  a stacked stretch counts only on its piece.
- `climbFeet`: the feet of ramps and stairs joined to the way below, 5 values each
  (`climbFeetFields`, always 5): x, y, the climb's cell value, the bearing up the climb in
  degrees, and the floor piece at the foot (0 the ground): guided to only from that floor.
  Guidance targets on the way, like entrances; two feet of one climb closer than
  `logic.FEET_APART` are one target.
- `climbAims` (optional): piece, value, x, y, up: the flights with a wall along one side and a
  drop along the other (`export.climb_sides`). Per flight's floor piece, its place value, a point
  at its top on the wall side, and its way up in degrees. With the setting `wallSide` on (and no
  beacon leading), `logic.aimTarget` (texts.lua) says the way up toward that point from wherever
  the player is on the flight ("on to the northeast"), until 2 yd before it
  (`logic.AIM_DONE`), and only while the player faces up the flight.
- Indoor layer of mapped buildings, the key `indoorIn` (split.room_levels: every built house
  with stairs or a sloped floor, and the big halls the game calls indoors): its own `top`,
  `left`, `cell`, `rows`, `cols` (cells half the zone's); its rooms are pieces on that fine grid,
  its floors floor pieces on the building's own walk graph, with drop edges from it
  (`deadends.dry_edges` with `head`) and its staircases' feet in `climbFeet` (with
  `climbFeetFields`); `exitFloors` (indoor layers too): per way out the floor piece it leads out
  of (a moat's, a liquid's); `liquids` as the zone's. A zone can have both `indoor` (the halls
  the game calls outdoors) and `indoorIn`; `logic.layer(zone, IsIndoors())` picks `indoorIn`
  while the game says indoors, else `indoor`.
- `objects`: 7 values each: x, y, half length and half width in 0.1 yards, the long axis'
  angle in degrees (0 = north, toward west), name index into `objectNames`, room (0 =
  outdoors).
- `interiors`: `{name, ox, oy, scale, m00, m01, m10, m11, c = 1 (optional), w = place
  (optional)}`: a building and its frame. World x = ox - scale * (m00 vx + m01 vy), world y = oy
  - scale * (m10 vx + m11 vy). `c = 1` marks a city's own complex or a map that is one building
  (Ironforge, the Deeprun Tram): it is named after its zone, which the player knows, so its rooms
  are said without it. `w`: for a building named only "building of <place>", the place its wall
  is said by when bumped into ("wall of <place>", through `ofTemplate`; `logic.wallOwner`).
- `rooms`: `{interior, name, kind, floor boxes {x0, y0, x1, y1, ...}, outline box
  (optional), f = floor (sq yd), a = axis (optional), w = winding (optional), s = 1 (optional),
  d = district (optional), sn = short name (optional)}`,
  in the building's frame. `a`: the axis angle (0..179) a long, narrow room runs along, or for
  a piece of a staircase split into pieces (all named alike) the line from its lowest to its
  highest doorway;
  `w`: its floor winds up turning left (1, counter-clockwise seen from above) or right (-1);
  `s`: the room has a name of its own (a shop: "entrance of" it from a hall). A room of at least
  `logic.BIG_ROOM` sq yd says and guides to its doorways from the player's position.
  `d` and `sn`: in a city complex spanning districts, the district the name says (or, for one
  of its ways, the places the way joins) and the name without it ("canal" for "canal, Trade
  Quarter", "lift" for "lift between Ruins of Lordaeron and Trade Quarter"); `describeRoom` says
  the short name when the room one comes from, or stands in for a doorway list, has the same
  `d`. The locales carry the short names as `roomsShort` ("" for none). `e`: the key of a place
  the complex's ways join (a quarter's hall, a canal); `wa`, `wb`: a way's two places, `ta`,
  `tb`: its names said from each ("passage to canal" from the War Quarter, "passage to War
  Quarter" from the canal); the locales carry them as `roomsAtA`, `roomsAtB`. `ar`: a hall's
  area as the game names it (its subzone; locales `roomsArea`); `ni = 1`: a niche, a city's
  small dead end, never a guidance target; `g`: the UI map id one stands on in a hall the game
  calls outdoors (`hallMap`; `logic.isHallMap` tells the halls' maps); `zp`: the zone's floor pieces a hall the game calls
  outdoors lies on (0 the ground), with `hallGround` (row, column pairs: the cells where a hall's
  floor is the ground): the module (`logic.inHallFloor`) takes the player into the halls only
  when the floor piece they are on is one of these here, or where the game's subzone is a hall's
  `ar` (`logic.hallPieceForArea`), or just after the game's map became the halls'; out of them
  through a doorway to outside, or a step between two halls that are apart (`logic.hallsApart`).
- `doors`: 9 values each, `{room a, room b (0 = outside), interior, x, y, nx, ny, side of room
  a (+1 or -1; 0 = unknown, never crossed), half width}`, in the building's frame. The ninth
  value is half the opening's width along its plane: a step counts as crossing the doorway
  anywhere across its whole width (`logic.crossedDoor`), else only near its centre (older
  exports have no ninth value).
- `doorVia` (optional): 2 values per door, door numbers (0 none): through the door from room a
  into room b, and from b into a, the nearest doorway out of the room both are pieces of. Set only
  for a door between two rooms said alike (`logic.sameRoomName`: one name, or one word numbered,
  "mine 2"); a room under
  800 sq yd says that doorway, in the inner door's direction, where it would say nothing
  (`logic.roomDoorways`).
- `indoor` (optional): the indoor layer, the big halls of a city (Ironforge, the Undercity
  quarters) cut into pieces like its streets: `rooms` (the room ids it covers), `grid` (same
  frame and places as the zone's), `lanes`, `noContact`, `structs`, `waterStructs`,
  `structCells` and `edges` (the edges of floors inside: lava, water, canals; they warn in every
  room), `exits`, `exitFloors`, `exitGroups`, and its floor pieces (`floorCells`, `noGround`,
  `joins`, `liquids`); `indoorIn` also `climbFeet` and `climbFeetFields`. `floorRooms` (optional):
  row, column, piece, room: the rooms whose dry floor that floor piece (0 the ground) is in the cell,
  by the model group each floor surface comes from (every room of a city has its floor in a layer); on the
  ground only a room with a third of its floor on it, never on a liquid's piece. The module takes the room
  of the player's floor piece in the cell, else in the 8 around (`logic.floorRoomsAt`), and the boxes only
  where the layer does not say; coming into the halls by a hall's floor puts the player on its piece
  (`logic.roomPieceHere`), and a doorway into a room whose floor the layer knows counts only where that
  floor lies on the player's piece (`logic.roomFloorNear`).
  `logic.unpackLayer` makes it a zone of its own (`logic.layer(zone, indoors)`) that shares the zone's
  words, places, interiors, rooms and doors; its entrances are the doorways from a covered room
  into one that is not (a shop by "entrance of", a passage by its name, the way outside). While
  the player is in a covered room (`logic.inLayer`), the module runs the outdoor rules on it.
- `stops` (optional): where one waits for something that moves: `{kind, destination, room (0 =
  outdoors), cells {row, column, ...}, segments {x1, y1, x2, y2, ...}}`. Kinds `ship`,
  `zeppelin`, `tram` (with a destination: "wait for the ship to Auberdine"), `lift up`, `lift down`;
  the cells are the waiting floor (the dock edge beside a ship, a lift's landing, a tram platform
  along the cars); the segments are where the vehicle stands (a ship along its heading, a lift's
  car as a point, a tram's cars along the track); the direction said is toward the nearest point
  of each, from where the player stands ("ship to the southwest"). A sixth element lists the
  floor pieces the waiting floor lies on (`{0}` the ground; older data has none): an outdoor stop
  counts only outdoors and only up on one of those pieces (the zeppelin tower's top was said at
  its foot), a stop in a room only in that room (the room the player is in, or the candidates
  while it is unknown). The module says a stop on stepping onto it, again only after the player
  walked 3 yards off every stop; the describe key and `/wv surr` add it.
- A map made of one building (the Deeprun Tram, map 369) has an empty grid: rooms, doors,
  objects, stops, and its platforms' drop edges into the pits under the tracks as the indoor
  layer's `edges` (piece = the platform's room), with no layer grid or rooms.
- Docks and piers are ways: kinds `quay` and `pier` (a spur that joins one other piece), the wide
  parts `square` ("dock of ..."); the water under them is the water's own floor piece.
- Water (since the 2026-10-11 export): it comes from the game's liquid data, a building's water
  down to its model group's box. The player swims from 1.75 yd depth, so deep water and shores
  are cut there. A city's beaches are shore places.
- `locales`: per client language the words with the same indexes as the English lists
  (`dirs`, `dirsClock`, `compass`, `axes`, `floors`, `ofTemplate`, `spoken`, `places` as
  `{label, road, of = structure}`, `interiors`, `interiorWalls` (the `w` of each interior, ""
  for none), `rooms`, `roomsShort`, `roomsArea`, `roomsAtA`, `roomsAtB`, `structs`,
  `objectNames`, `stops` as the destinations). Unpacking puts them in place once and drops the
  other languages.

## Places list

`places.lua` (pure logic, tested in `placesTests.lua`) and `placesUi.lua` (the window, Alt-F10)
make the places list from the data's `places/<zone>.lua` files (wv-surroundings
`tools/destinations.py`, written by every export beside the zone file; they call
`addon.addPlaces{...}` and land in `WowVision.surroundingsData.places`). They are small and read
whole; nothing is unpacked per zone. `logic.placesUnpack` puts the client's names in place,
`logic.placesTree` builds the scanner's kind of nodes sorted by distance (`placesUi.lua` renders
them as the scanner does) and `module:placesNavigate` is the one place where Enter hands a
target to the navigation (`maps:openNavigationTo`, the scanner's Enter).

A places file, `format = 1`:

- `key`, `map` (the continent, `UnitPosition`'s instance id).
- `zones`: `{area id, name, UI map id, open, items = {...}}`. `open = 1`: the zone's map has no
  exploration overlays (a city's): shown whole in discovery mode. `items`: the things in no subzone.
- `areas`: `{zone index, area id (the area table's; 0 a city district), name, overlay (1: the
  map names it once explored), heart stride, heart {x, y[, ox, oy], ...}, border crossings {x, y,
  from, road, ...}, check points {x, y, ...}, items = {...}}`. The heart is where the subzone
  leads (its building of the same name, as a doorway: 4 values; its main square; a quarter's
  open hall floor nearest its middle; the middle of its village on a way); with no heart, its
  nearest border crossing. A crossing lies 5 yd inside the subzone, `from` is the subzone it
  comes from (an index into `areas`, 0 the zone's own land), `road` 1 where a road crosses. The
  check points are what discovery mode asks the game about
  (`C_MapExplorationInfo.GetExploredAreaIDsAtPosition`, the map's own hover names): a subzone with
  an overlay is known where the game lists its id there, one without where it lists any.
- An item: `{kind, name, stride, targets {...}, rooms = {...}}`; kinds `building`, `shop`,
  `room`, `square`, `landmark`. Stride 4: a doorway's point 3 yd inside and the point 3 yd
  outside it, routed to first; stride 2: a point. A building's `rooms` are its named rooms,
  reached through the building's doorway first.
- `names_enUS`, `names_deDE`, `names_frFR`: the names, indexed by the records.

## Walk log

`/wv surr log on` keeps every announcement and a position trail in
`WowVisionDump.surroundings`, until `/wv surr log off`. At most 3000 entries and 20000 trail
points are kept (the oldest go first).

- An entry: date, kind ("place", "room", "edge", "bump", "session", "zone", "surr", "floor"
  for a change of the floor piece, and more), text; then x, y, the zone and the data's cell
  (r, c) with its text, the game's `subzone`, `swimming`, the facing in degrees; indoors also
  `indoors`, `hall` (in a hall the game calls outdoors), the room candidates, the room and the
  indoor `layer`'s text; `layerKey` when the player is in an indoor layer, and `floor` with the
  floor piece when it is not the ground.
- The trail: a point every 2 yd, "time x y" plus one token of flags: i (indoors), h (in a hall
  the game calls outdoors), s (swimming), g (ghost), f with the facing in degrees, p with the
  floor piece when it is not the ground ("isf270p33"). `tools/walklog/module.lua` in wv-surroundings replays a log through
this module itself (stand-ins for the WoW API) and prints what it would say, so a change to the
module or the data can be heard offline on a real walk, and a refactor can be checked for
byte-identical output over every logged walk.
