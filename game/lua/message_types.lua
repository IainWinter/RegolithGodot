-- every message kind that crosses between sensors, scripts and the runtime.
-- scripts require this once (local M = require("message_types")) and use
-- the constants instead of string literals. the value is still the plain
-- string, so the wire format through AiMessage couriers, send_instant and
-- the gdscript sensors is unchanged. PlayerSensor.gd mirrors the sensor
-- kinds as constants on the gdscript side

local M = {}

-- player sensor -> the script on its host. each carries player, position,
-- velocity, distance and in_sight (a clear line from the host)
M.PLAYER_SEEN = "player_seen"      -- the player came within the sensor radius
M.PLAYER_UPDATE = "player_update"  -- every update_interval while they stay inside
M.PLAYER_LOST = "player_lost"      -- they left the radius or died, no fields

-- squads, fighter <-> fighter. shoot the courier and the squad never forms
M.SQUAD_JOIN = "squad_join"        -- a loner broadcasts by courier to everything near, asking for a leader
M.SQUAD_ACCEPT = "squad_accept"    -- a leader with room answers the joiner, instant
M.SQUAD_JOINED = "squad_joined"    -- the joiner confirms it took that leader, instant
M.SQUAD_FULL = "squad_full"        -- the leader turns a confirmed joiner away, instant

-- runtime -> the script that asked ai.spawn or ai.spawn_rock. AiRuntime.gd
-- mirrors these. each carries the tag the request was made with
M.SPAWNED = "spawned"              -- the StableSpawner placed it, carries node, request and tag
M.SPAWN_EXPIRED = "spawn_expired"  -- the request found no room in its lifetime, carries request and tag

-- cell sensor -> the script on its host, the world's own signals about
-- the host's body. CellSensor.gd mirrors these
M.CELLS_REMOVED = "cells_removed"  -- cells left the host, carries count
M.SPRITE_SPLIT = "sprite_split"    -- a piece broke off the host, carries piece
M.CORE_EXPLODED = "core_exploded"  -- a core on the host went, carries position, power, type

-- host body -> its script, from the node's own mechanics
M.PLAYER_ENTERED_CLOUD = "player_entered_cloud"  -- the watched player turned to cloud, no fields

return M
