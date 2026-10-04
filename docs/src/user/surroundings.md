# Surroundings (WoW: Forever)

On WoW: Forever, WowVision describes where you walk, from map data: the land you are on,
the roads and streets, the rooms of buildings, drop edges, and what you bump into. It needs the
**WowVision_Surroundings** data addon, installed next to WowVision. Without it the
surroundings are silent. The data currently covers Elwynn Forest with Stormwind, Dun Morogh
with Ironforge, and Tirisfal Glades with Undercity.

To install the data, download
[WowVision_Surroundings.zip](https://github.com/JeanStiletto/WowVision_Surroundings/releases/latest/download/WowVision_Surroundings.zip),
the latest release of the
[WowVision_Surroundings repository](https://github.com/JeanStiletto/WowVision_Surroundings),
and extract it into the WoW: Forever client's addons folder, so the files sit in
`World of Warcraft/_classic_beta_/Interface/AddOns/WowVision_Surroundings`.

Announcements made while walking are spoken by the game's voice 0, not by your speech voice:
a screen reader would cut its own speech off at every key press.

## What you hear

- **Outdoors**, each place you walk into: "forest", "shore of Crystal Lake, water to the
  north", "Goldshire road, north to south". A place counts only after you have walked a few
  yards inside it (on roads and streets 3 yards, elsewhere 8), so walking along a border does
  not flicker. Roads and city streets (canal walks too) follow the same rules: they follow
  their centre lines, so drifting toward the side of a road or street is heard as leaving it,
  and a new direction is said at once. On a city street or canal walk the next piece is said
  about 12 yards before you reach it, just as if you had stepped onto it, so there is time to
  stop and turn where a street ends at the water and goes on to the side; stepping onto it then
  says nothing more. Coming out of the water, the place on land is said
  after 3 yards on it.
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
  leads to a building's door is named after it. Each flight is a piece of its own, so where
  stairs turn on a landing you hear the new flight's direction. On a square or in a room they
  are listed with its other ways ("stairs to the upstairs landing to the east").
- **Indoors**, the room and its doorways: "Lion's Pride Inn, common room, hallway to the
  north, kitchen to the east". The building's name is said when you enter it. A long, narrow
  room says which way it runs ("passage of Ironforge, north to south"); winding stairs say which
  way they turn going up ("stairs of Ironforge, winding, turns left going up"). Rooms without a
  name of their own say their floor ("room, floor 1"), the room they stand over when a named one
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
  lies below ("southeast, canal", "north, water", "east, drop 12", indoors also "west, lava");
  ahead of you the distance in yards first ("9 southwest, canal").
- **Guidance**: within 8 yards of a building entrance or of where a street begins on a square,
  its name, distance and direction ("entrance of the bank, 6 to the northeast"), again when the
  direction changes, and once when you are at it. Once named, it keeps saying its direction
  out to 10 yards, so you can step back and strafe to line up with a door. While swimming, the nearest way out of the
  water; one that only leads onto a ledge or into a dead end says so ("way out of the water to
  a dead end").
- **Turn hints** on roads and streets (not on ramps and stairs): "left" or "right" when the
  direction words cannot tell you that you are facing a little off the way, and at gentle bends
  of a road.
- **Bumps**: when wall detection finds you blocked, what you are pushing against ("wagon",
  "wall of auction house", indoors "wall"); beside a raised ramp or stairs its side ("ramp to the
  bank, side"). This needs the wall detection module enabled.

## Keys and commands

- **Alt-L** (Describe Surroundings): the full description of where you stand, without the
  shortening of the announcements, plus the nearest guidance target.
- `/wv surr`: position, data cell, place, nearest entrance and, indoors, the room; spoken and
  printed.
- `/wv surr log on`, `/wv surr log off`: a walk log for reporting problems, kept in
  WowVision's saved variables until you switch it off. `/wv surr log` says the last entries,
  `/wv surr log clear` empties it.

## Settings

Under Navigation, Surroundings:

- Warn at Drop Edges
- Guide to Entrances, Streets and Ways Out
- Turn Hints on Roads and Streets
- Quieter While a Beacon Guides: while a WowVision beacon or route leads you, entrances and
  street beginnings are said once by name only, and there are no turn hints.
- Name What I Bump Into

The announcements themselves are an alert ("Surroundings Announcements") that can be switched
off like any other.
