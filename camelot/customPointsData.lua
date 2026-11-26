-- Custom points the addon ships for WoW: Forever (core/navigation/customPoints.lua). Each is handed to the player's
-- account list once, by its id; his own points, names and deletions are never touched. Positions in world yards on
-- UnitPosition's map. Add new points with a new id; never reuse or change an id once shipped.

local shipped = WowVision.customPoints.shipped

-- A level 58 vulture ("Pestschwingengeier", in neither the route data nor Questie) attacked a level 34 player twice
-- on the way from Chillwind Camp to the Scarlet Monastery, Western Plaguelands (trial walks 2026-11-26, the fight
-- starts the walk trace recorded).
-- Named after the creature as the German client says it (user 2026-11-27); the English name is not known.
shipped[#shipped + 1] = { id = "wv:forever:wpl-vulture-1", kind = "danger", x = 1198.2, y = -1116.0, map = 0,
    name = "Pestschwingengeier" }
shipped[#shipped + 1] = { id = "wv:forever:wpl-vulture-2", kind = "danger", x = 1183.6, y = -1137.0, map = 0,
    name = "Pestschwingengeier" }
