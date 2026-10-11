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
- `edges.lua`: drop edges (of the cities' floors, structures, buildings; a drop into a liquid
  is one like any other) and the floor piece the player is on (`logic.updateFloor`,
  `logic.swimFloor`, `logic.setFloor`, `logic.joinedPieces`). The way-out target
  (`logic.exitTarget`) lives in `texts.lua`.
- `lanes.lua`: centre lines of roads and streets: whether the player is on the way, turn
  hints, where a road leads, gentle bends.
- `rooms.lua`: building frames, rooms without a height (stacked floors resolved by the
  doorway walked through; a room entered that way holds while its floor is within
  `logic.ROOM_SLACK` or one of its doorways within `logic.DOOR_HOLD`, 4 yd: `resolveRoom`'s
  `byDoor`), doorways, entrances. Rooms change as floors do (`logic.onFloorRooms`): a hall stays
  a candidate only as the current room, one joined to it by a doorway, or a hall lying on the
  zone's floor piece here. Rooms whose names differ
  only by a trailing number are sections of one thing (`logic.sameRoomName`): walking from one
  into the next says `logic.sectionText` (texts.lua) instead of the full room line. A doorway
  into a room of the very same name (the pieces of one staircase) is never listed.
- `squares.lua`: the region of a square (flood fill), what borders it (mouths), where ways
  begin on it, items around a place, cliffs and water near an outdoor place.
- `objects.lua`: objects one bumps into, whose wall it is.
- `texts.lua`: every spoken text: places, squares, rooms, drop edges, guidance targets.
- `stops.lua`: where one waits for a ship, zeppelin, lift or tram, and which way it will be.

`module.lua` is the WoW side: settings, the alert, the update loop, the walk log, `/wv surr`,
`/wv surr around` and the describe key (both run `describeAround`). Every 0.2 s the loop pauses
on a flight (`UnitOnTaxi`), then runs `updateHall` (the halls the game calls outdoors),
`checkBump`, and `updateIndoors` (with `updateLayer` for the indoor layer's halls) or
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
  `row * cols + col`.
- Kinds are the data's English keys ("road", "canal walk", "deep water"); the words spoken
  come from the zone (localized) or from the locale strings. Ramps and stairs are the kinds
  "ramp" and "stairs" (`logic.CLIMBS`): ways with centre lines keyed like streets, on every
  floor (outdoors, in the halls, in mapped buildings) since the 2026-10-11 export, their feet
  carrying the floor piece they stand on; `wallOwner` names their side when bumped into from
  beside them.

## Zone data

Each zone file calls `addon.addZone{...}` with:

- `key`, `label`, `map`: the map id `UnitPosition` returns.
- `top`, `left`, `cell`, `rows`, `cols`: the grid. Row 0 lies at world x = `top` (north),
  column 0 at world y = `left` (west); cells are `cell` yards wide.
- `format`: 3: the floor pieces (`floorCells`, `noGround`, `joins`, `liquids`) on top of
  format 2's angles. Directions are angles in degrees clockwise from north (an axis, both ways of a
  street, 0..179); the module turns them into the player's words: the 8 compass words, or with
  the compass module's Directions setting the 12 hours of a north-up clock (`logic.clock`,
  `logic.dirWord`, `logic.axisWords`, `logic.finishText` for the "o'clock"). Data of another
  format is left alone and said once.
- `dirs`: the 9 direction templates, in this order: "water to the %s", "deep water to the %s",
  "land to the %s", "drop to the %s", "rock wall to the %s", "building to the %s", "to the %s",
  "running %s", "up to the %s" (a ramp's or stairs' way up; the module says a climb by its axis
  instead, `logic.directionText`, and keys each flight by its rise, `logic.outdoorKey`);
  `dirsClock`: the same 9 for the hours ("water at %s", "at %s", "up at %s"); `compass`: the 8
  compass words; `axes`: the 4 axis words ("north-south"). A place label may carry directions as
  angles, `<d45,135>` ("fork, Goldshire road <d45,135>"): said with the "to the %s" template in
  the player's words.
- `places`: `{kind, label, nearest road (optional), of = structure (optional)}` per place id.
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
- `deadExits`: 1-based indexes into the ways out that lead onto floor joining nothing, or into
  a dead end (decided offline with the heights; optional).
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
  (`logic.updateFloor`) changes the floor only at a join crossed in its direction, at a drop edge
  of the floor crossed (onto `u`), or when the floor is no longer under the player: then the
  piece here that the floor joins or drops onto (joined within `logic.JOINED_HERE`, 6 yd, of the
  player), else the only piece here where the ground is absent, else the ground. A building's
  door join (a = -1) counts only within `logic.ROOMS_REACH` (6 yd) and only during the 3 s after
  the player came out of the building. No fall is taken while the wall detection says the
  player is blocked (a push against a railing just past an edge's rim). A liquid's surface (water, lava, slime) is a floor piece of its own
  (`liquids`: piece, kind pairs, kind 1 water, 2 city water, 3 lava; its cells in `floorCells`
  with the liquid's place, the canal's name or the water under a bridge): swimming is the one
  height the game tells, so `updateFloor` (its `swimming` argument: true, false, nil in the air)
  puts a swimming player on a liquid's piece here (the one the floor joins or drops onto, else
  the only one) and a player on foot off it (the floor it joins here, else the only floor, else
  the ground); on a liquid's piece no centre line decides the place, and its ways out are
  guided to (`logic.exitTarget` with the piece). `logic.valueAtCell` returns the floor piece's value where the cell
  lists it, else the grid's, so every lookup (places, squares, lanes, guidance) follows the
  floor the player is on; a square's neighbours are the cells its floor goes on into and the
  pieces it joins there (`logic.mouthValue`). In a house's layer a room's opening into another room is its
  doorway (the portal record, `logic.doorsBetween`): the grid cuts no walls between rooms, so
  two rooms with no doorway between them are no neighbours; a city's halls keep the grid's
  openings (no doorway records between them).
- `lanes`: centre line stretches, `laneFields` values each (10 now; 7 and 8 in older files):
  x1, y1, x2, y2, the cell value there, the distances from the line in 0.1 yards within which
  the way starts to count (enter) and beyond which it stops (leave) left of the stretch's
  direction, the same two right of it (a wall on one side no longer narrows the other), and the
  floor piece the stretch runs on where that floor lies over or under other floor (0 = the
  ground; -1 = not stacked: the stretch counts on every floor, the position alone finds it):
  a stacked stretch counts only on its piece. 8-field files have one width pair and the piece;
  7-field files the width pair alone.
- `climbFeet`: the feet of ramps and stairs joined to the way below, `climbFeetFields` values
  each (5; 3 and 4 in older files): x, y, the climb's cell value, the bearing up the climb in
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
- `indoor` (optional): the indoor layer, the big halls of a city (Ironforge, the Undercity
  quarters) cut into pieces like its streets: `rooms` (the room ids it covers), `grid` (same
  frame and places as the zone's), `lanes`, `noContact`, `structs`, `waterStructs`,
  `structCells` and `edges` (the edges of floors inside: lava, water, canals; they warn in every
  room), `exits`, `exitFloors`, `exitGroups`, and its floor pieces (`floorCells`, `noGround`,
  `joins`, `liquids`); `indoorIn` also `climbFeet` and `climbFeetFields`.
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
