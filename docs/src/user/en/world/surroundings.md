# Surroundings (WoW: Forever)

On WoW: Forever, WowVision describes where you walk, from map data: the land you are on,
the roads and streets, the rooms of buildings, drop edges, and what you bump into. The map data
comes with WowVision, in its folder `mapdata/WowVision_Surroundings` (the
[WowVision_Surroundings repository](https://github.com/JeanStiletto/WowVision_Surroundings));
there is nothing extra to install. Without it the surroundings are silent, and `/wv surr` tells
you the data is missing. The data currently covers Elwynn Forest with Stormwind, Dun Morogh with
Ironforge, Tirisfal Glades with Undercity, and the Deeprun Tram. A zone's data is read only
while you are in it. An older separate `WowVision_Surroundings` addon in the addons folder is
no longer used: remove it.

Announcements made while walking are spoken by a game voice, not by your screen reader: a
screen reader cuts its own speech off at every key press. The voice is the Voice setting of the
Surroundings Announcements alert's TTS Alert output (default: game voice 0). Rate and volume
follow WowVision's speech settings.

Directions are said as the 8 compass words ("north", "southwest"). With the compass module's
Directions setting (under Navigation, Compass) on Clock Hours, they are the 12 hours of a
clock with north at 12 ("water at 3"), whichever way you face.

## What you hear

- **Outdoors**, each place you walk into: "forest", "shore of Crystal Lake, water to the
  north", "Goldshire road, north to south". A place counts only after you have walked a few
  yards inside it (3 yards on every way: roads, streets, bridges, forks, crossings, quays,
  piers, ramps, stairs and walks; elsewhere 8), so walking along a border does not flicker. A
  step from one piece of a way onto the next counts at once. Roads and city streets (canal walks
  too) follow the same rules: they follow their centre lines, so drifting toward the side of a
  road or street is heard as leaving it, and a new direction is said at once. Coming out of the
  water, the place on land is said after 3 yards on it.
- **Looking ahead** on every way with a centre line (roads, streets, walks, quays, piers, ramps,
  stairs): the next piece is said about 12 yards before you reach it, just as if you had stepped
  onto it, so there is time to stop and turn where a street ends at the water and goes on to the
  side. A piece closer than 4 yards is not said ahead. It is said once, and not again until you
  are 6 yards farther from it than when it was said; stepping onto it then says nothing more.
  This is automatic while you walk, and quiet while a beacon guides you (with the setting
  Quieter While a Beacon Guides on).
- **Forks** name their ways with the direction of each ("fork, road to the bridge to the north,
  Iceflow Lake road to the west").
- Next to a place, the **cliffs and water** near it ("forest, cliff edge to the west"), and
  after stepping off a road or street, where it is ("open land, road to the northwest";
  in a city "Trade District, street to the east", or "grass, street to the east" where there
  really is grass). The open ground between a city's streets is called by its district; where
  the district is a square of its own name (Cathedral Square), it is part of that square.
- A **dead end**: the stretch of a street or walk from which the only way on is back the way
  you came is called "dead end" instead of its street name ("dead end, northwest to
  southeast").
- **On a city square**, its ways on ("square of Trade District, street to The Canals to the
  east"), and water, canals and drops as you come close to them. Where a street's paved lane
  crosses a square to another street, you can follow the street across it; stepping off the lane
  says the square again.
- **Ramps and stairs** are ways of their own, said like a street, the same going up or down:
  "ramp to the bank, northeast to southwest", "stairs of Mage Quarter, east to west". One that
  leads to a building's door is named after it. Each flight is a piece of its own, and so is a
  landing where the stairs turn: the stairs that go up north, cross a landing to the west and go
  on up south say "north to south", "east to west", "north to south". On a square or in a room they
  are listed with its other ways ("stairs to the upstairs landing to the east").
- **Platforms**: the raised floors of structures (a zeppelin tower, a harbor) are places of
  their own ("platform of Stormwind Harbor") that list their stairs and ramps like a square. Their
  drop edges warn only while you are up there.
- **Indoors**, the room and its doorways: "Lion's Pride Inn, common room, hallway to the
  north, kitchen to the east". The building's name is said when you enter it. A long, narrow
  room says which way it runs ("passage of Ironforge, north to south"); winding stairs say so
  ("stairs of Ironforge, winding"). Rooms without a
  name of their own say their floor ("room, floor 1"), or the floor's name where the game names
  it ("room southeast, upstairs"; said once: on that floor its rooms are "room southeast" and the
  stairs up to it just "stairs"), the room they stand over when a named one
  carries the same word ("Main Hall, floor 1" is the gallery over the Main Hall), or their
  direction when several share a word ("entrance" has the door, "entrance northeast" lies
  behind it); stairs are named by where they lead up to ("stairs to the bell tower"), and a
  staircase the map splits into pieces is one staircase with one name. Walking on into the
  next section of the same thing (a mine's passages, the tram tunnel, the next piece of a
  staircase) says no name again: only the way it runs when that changed ("northwest to
  southeast") and its doorways on, not the one you came through ("side tunnel southeast to
  the northeast, mine 7 to the northeast"); a passage whose only way on is the next section
  says nothing. A room
  entered through a doorway stays the room until the next doorway or until its floor is left,
  so narrow stairs over a hall are not lost to the hall's floor below. In a big room
  the doorways are said from where you stand, nearest first, and within 8 yards of one you are
  guided to it like to an entrance ("shop, 6 to the west").
- **The big halls of a city** (Ironforge, the Undercity quarters) are described like its
  streets and squares: their pieces with their directions ("walk along the lava, north to
  south"), what lies around a hall, the doorways into shops and passages as entrances
  ("entrance of Stonebrow's Clothier, 5 to the east", "passage of Ironforge, 6 to the north"),
  and the edges down to lava and water.
- **Docks and piers** are ways like streets: "quay of Stormwind Harbor, north to south",
  "pier of Stormwind Harbor"; the wide parts of a dock are a square ("dock of Stormwind
  Harbor") that says its piers and quays. The water under them is said only while swimming.
- **Drop edges** on docks, bridges, walls and canal sides, kept short: the direction and what
  lies below ("southeast, canal", "north, water", "east, drop 12", indoors also "west, lava",
  and in Ironforge's Commons "east, moat");
  ahead of you the distance in yards first ("9 southwest, canal"). In buildings whose floors are
  mapped (the Brill tavern) also an open stairwell or the open side of a staircase, only on the
  floor it lies on; going over it counts you on the floor below.
- **Feet of ramps and stairs**: within 8 yards of the foot, guidance to it with the way up
  ("stairs, 2 to the east, on to the north"), lined up with the climb; everywhere only from the
  floor the foot is on. On stairs with a wall along one side and a drop along the other, the way
  up is said toward the wall side ("on to the northeast"), so a step toward the open side is said
  back to you; this needs the setting Guide Up Stairs on Their Wall Side.
- **Guidance**: within 8 yards of a building entrance or of where a street begins on a square,
  its name, distance and direction ("entrance of the bank, 6 to the northeast"), again when the
  direction changes, and once when you are at it. Once named, it keeps saying its direction
  out to 10 yards, so you can step back and strafe to line up with a door. While swimming, the
  nearest way out of the water within 25 yards (ways out that only lead onto a ledge or into a
  dead end are left out of the data). A long shore is one way out: it is named
  once while the guidance follows its nearest stretch. Down in Ironforge's moat you are guided to
  the nearest "way out of the moat", from anywhere down there.
- **Turn hints** on roads and streets (not on ramps and stairs): "left" or "right" when the
  direction words cannot tell you that you are facing a little off the way, and at gentle bends
  of roads and streets. Ramps and stairs get no bend hints.
- **Bumps**: when wall detection finds you blocked, what you are pushing against ("wagon",
  "wall of auction house", indoors "wall"); the wall of a structure ("wall of gate of
  Northshire Valley"), or of a building named only by its place ("wall of Ruins of Lordaeron"); beside a
  raised ramp or stairs its side ("ramp to the bank, side"). Nothing is named while swimming.
  This needs the wall detection module enabled.
- **Stops**: stepping onto a spot where one waits for a ship, zeppelin, lift or tram says what
  to wait for and where it will be ("wait for the ship to Auberdine, ship to the southwest",
  "wait for the lift down, lift to the west"). The same stop is said again only after you have
  walked 3 yards off every stop.
- **After a reload or login** on the same spot, the room and the floor you were on are taken
  back, so a reload upstairs does not put you on the floor below.

## Keys and commands

- **Alt-L** (Describe Surroundings): the full description of where you stand, without the
  shortening of the announcements, plus the nearest guidance target and the stop you stand on.
  Outdoors it adds a drop edge within 3 yards, or one ahead of you within 10 yards.
  `/wv surr around` does the same.
- **I** (Turn to Waypoint) with no beacon active: on a road, street, walk, ramp, stairs or
  bridge it turns you along its centre line (where it has none, along the direction it is said
  with), the way nearer your facing. On a fork or crossing it turns you to the arm nearest your
  facing, the way the fork names it; once you face an arm, each further press turns you to the
  next arm clockwise. It is the same turn as to a waypoint: within 3 degrees a press does
  nothing, farther off it corrects. Nothing is spoken; elsewhere (a square, a room) it says
  there is no active waypoint, as before.
- **Alt-F10** (Places): a list of the places to go to, like looking at the map. The zone you
  are in comes first and open; the other zones with surroundings data on your continent follow,
  closed. Under a zone are its subzones (in a city its districts and quarters: Trade District,
  The Great Forge, Trade Quarter), the subzone you stand in first and open, and the things that
  lie in no subzone; under a subzone its named buildings and buildings with a use (inn,
  smithy, bank, auction house, griffon roost, tower, mine, cave), squares, landmarks (well,
  forge, statue, signpost) and a city's shops; under a building its named rooms. Every level is
  sorted by distance, and each entry says how far and in which direction. Things of one name
  are one entry, which leads to the nearest of them. Streets, roads, ramps, stairs, forks and
  plain houses, farmhouses, barns and huts are not listed. Enter leads you there through the
  navigation's routes, as Enter in the scanner (F9): a building to its doorway, then a few yards
  inside; a square to its most open spot; a subzone to its own building (a mine, a tower), its
  main square or hall, the middle of its village, or where a road comes into it. Right and Left
  open and close an entry; Refresh rebuilds the list.
- `/wv surr`: position, data cell, place, nearest entrance, the stop you stand on, whether the
  game says indoors or outdoors with its map and area, and, indoors, the room candidates, the
  current room and the indoor layer; spoken and printed.
- `/wv surr log on`, `/wv surr log off`: a walk log for reporting problems, kept in
  WowVision's saved variables until you switch it off. `/wv surr log` says the last 5 entries,
  `/wv surr log 20` the last 20 (any count); they are also printed to chat.
  `/wv surr log clear` empties it.

## Settings

Under Navigation, Surroundings (the first six are on by default):

- Warn at Drop Edges
- Guide to Entrances, Streets and Ways Out
- Turn Hints on Roads and Streets
- Guide Up Stairs on Their Wall Side: on stairs with a wall along one side and a drop along the
  other, the way up is said toward the wall side.
- Quieter While a Beacon Guides: while a WowVision beacon or route leads you, entrances and
  street beginnings are said once by name only, and there are no turn hints, no look-ahead to
  the next piece of a way, and no wall-side guidance on stairs.
- Name What I Bump Into
- Discovery Mode: Places List Names Only Explored Subzones (off by default): the places list
  (Alt-F10) names only the subzones your character has explored, as the game's map does, and
  lists nothing in the others. A subzone you have not explored that borders one you have, or
  the one you stand in, is listed as "unexplored area", leading to where you cross into it. A
  city's map has nothing to explore, so a city is listed whole. Things that lie in no subzone are
  listed when they are within 150 yards.

The announcements themselves are an alert ("Surroundings Announcements") that can be switched
off like any other.
