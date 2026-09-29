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
  and a new direction is said at once. On a city street or canal walk the next piece's
  direction is said 12 yards before it, with the distance ("northeast to southwest in 10
  yards"), so there is time to turn where a street ends at the water and goes on to the side;
  stepping onto it then says nothing more. Coming out of the water, the place on land is said
  after 3 yards on it.
- Next to a place, the **cliffs and water** near it ("forest, cliff edge to the west"), and
  after stepping off a road or street, where it is ("open land, road to the northwest";
  in a city "grass, street to the east"). The terrain between a city's streets is "grass".
- A **dead end**: the stretch of a street or walk from which the only way on is back the way
  you came is called "dead end" instead of its street name ("dead end, northwest to
  southeast").
- **On a city square**, its ways on ("square of Trade District, street to The Canals to the
  east"), and water, canals and drops as you come close to them.
- **Indoors**, the room and its doorways: "Lion's Pride Inn, common room, hallway to the
  north, kitchen to the east". The building's name is said when you enter it.
- **Drop edges** on docks, bridges, walls and canal sides: the direction first, then the drop
  ("southeast, drop into canal"; ahead of you with the distance, "north in 6 yards, drop 12
  yards").
- **Guidance**: within 8 yards of a building entrance or of where a street begins on a square,
  its name, distance and direction ("entrance of the bank, 6 to the northeast"), again when the
  direction changes, and once when you are at it. While swimming, the nearest way out of the
  water; one that only leads onto a ledge or into a dead end says so ("way out of the water to
  a dead end").
- **Turn hints** on roads and streets: "turn slightly left" when the direction words cannot
  tell you that you are facing a little off the way, and at gentle bends of a road.
- **Bumps**: when wall detection finds you blocked, what you are pushing against ("wagon",
  "wall of auction house", indoors "wall"). This needs the wall detection module enabled.

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
