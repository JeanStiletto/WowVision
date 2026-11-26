-- Custom points the addon ships for WoW: Forever (core/navigation/customPoints.lua). Each is handed to the player's
-- account list once, by its id; his own points, names and deletions are never touched. Positions in world yards on
-- UnitPosition's map. Add new points with a new id; never reuse or change an id once shipped.

local shipped = WowVision.customPoints.shipped

-- The five danger points on the way from Chillwind Camp to the Scarlet Monastery, Western Plaguelands, are named in
-- English and numbered in this file's order (user decision 2026-11-27); a player who already has them keeps the name
-- he has, since mergeShipped fills in only a point without a name.

-- A level 58 vulture ("Pestschwingengeier" in the German client, in neither the route data nor Questie) attacked a
-- level 34 player twice on that way (trial walks 2026-11-26, the fight starts the walk trace recorded).
shipped[#shipped + 1] = { id = "wv:forever:wpl-vulture-1", kind = "danger", x = 1198.2, y = -1116.0, map = 0,
    name = "Monster on the shortcut to the monastery 1" }
shipped[#shipped + 1] = { id = "wv:forever:wpl-vulture-2", kind = "danger", x = 1183.6, y = -1137.0, map = 0,
    name = "Monster on the shortcut to the monastery 2" }

-- The next walk (2026-11-27 00:00), same way: a vulture attacked again further south-west (the fight start), then a
-- second fight with an unknown creature and the death spot; no monster of any zone's data within 80 yd of the three.
shipped[#shipped + 1] = { id = "wv:forever:wpl-vulture-3", kind = "danger", x = 1087.2, y = -1140.8, map = 0,
    name = "Monster on the shortcut to the monastery 3" }
shipped[#shipped + 1] = { id = "wv:forever:wpl-unknown-1", kind = "danger", x = 1247.3, y = -1023.9, map = 0,
    name = "Monster on the shortcut to the monastery 4" }
shipped[#shipped + 1] = { id = "wv:forever:wpl-unknown-2", kind = "danger", x = 1289.7, y = -990.7, map = 0,
    name = "Monster on the shortcut to the monastery 5" }

-- Blocked passages: links of WowNav's network the player cannot get through in the game. The walk of 2026-11-27
-- 00:16 got stuck 17 times on a rock between Chillwind Camp and the Scarlet Monastery (12.6 yd up over 22.7 yd onto a
-- rock top, then down again; the first trial walk of 2026-11-26 got stuck there too). Every route puts a penalty on
-- them while their waypoints still lie at these positions (other route data: left out).
shipped[#shipped + 1] = { id = "wv:forever:wpl-rock-1", kind = "blocked", map = 0,
    a = 14220006522, ax = 1164.8, ay = -1201.3, b = 14220006538, bx = 1177.1, by = -1182.2, x = 1171.0, y = -1191.8 }
shipped[#shipped + 1] = { id = "wv:forever:wpl-rock-2", kind = "blocked", map = 0,
    a = 14220006538, ax = 1177.1, ay = -1182.2, b = 14220006580, bx = 1206.2, by = -1182.5, x = 1191.7, y = -1182.4 }
-- The next walk (00:30) went over the same rock top on parallel links (14220006547-6551-6582): the rock top carries a
-- dense mesh of links, so the whole top is a blocked spot (links touching a waypoint within 12 yd and 8 yd of 81.5 yd
-- height; the foot of the rock lies at about 69 yd and is not hit).
shipped[#shipped + 1] = { id = "wv:forever:wpl-rock-top", kind = "blocked", map = 0, x = 1185.5, y = -1182.0, z = 81.5,
    radius = 12 }
