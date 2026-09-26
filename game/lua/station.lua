-- station: AiStation. drifts to the nearest base (any thrower with room)
-- that is nearer than the player and stands off on its far side, else to a
-- spot around the player picked every goal_interval. every spawn_interval
-- it lets a fighter or a bomb out of its hangar point while under
-- max_spawned, and it shoots at the player in range with a clear line.
-- spawns go over ai.spawn and come back as SPAWNED messages, the player
-- sensor tells it where they are, the weapon is the host's
--
-- states: idle until the player sensor reports them, escort while a
-- thrower with room is nearer than the player (goal = standoff behind it),
-- roam otherwise (goal around the player). spawning and shooting run in
-- both player states

local M = require("message_types")

local Station = class("station")

local DEFAULTS = {
	move_speed = 1.0,
	move_accel = 1.0,
	goal_interval = 25.0,
	goal_ellipse = vec2(16.0, 6.0),
	standoff_distance = 8.0,
	spawn_interval = 4.0,
	max_spawned = 8,
	spawn_origin = vec2(-0.29686213, -0.2961769),
	spawn_kinds = { "fighter", "bomb" },
	fire_radius = 10.0,
}

-- the hangar sides, rotated with the hull
local SPAWN_OFFSETS = { vec2(0, -1), vec2(0, 1), vec2(1, 0), vec2(-1, 0) }

function Station:init()
	self:config(DEFAULTS)
	self.player = nil
	self.goal = nil
	self.goal_timer = 0
	self.spawn_timer = 0
	self.spawned = {}
	self.pending = 0

	self:register_state("idle", { enter = "idle_enter" })
	self:register_state("escort", { update = "escort_update" })
	self:register_state("roam", { update = "roam_update" })
	self:transition("idle")
end

function Station:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	elseif kind == M.SPAWNED then
		self.pending = math.max(self.pending - 1, 0)
		table.insert(self.spawned, msg.node)
	elseif kind == M.SPAWN_EXPIRED then
		self.pending = math.max(self.pending - 1, 0)
	end
end

-- every tick: the state from what is around, then the hangar and the gun
function Station:update(dt)
	local player = self.player

	if player == nil then
		self:transition("idle")
		return
	end

	local node = self.node
	self.escort_of = node:nearest_thrower(node.pos, node.pos:distance_squared_to(player.position))

	if self.escort_of ~= nil then
		self:transition("escort")
	else
		self:transition("roam")
	end

	self:hangar(dt)
	self:shoot()
end

function Station:idle_enter()
	self.node:fire(false, vec2(1, 0))
end

-- behind the base, on the far side from the player
function Station:escort_update(dt)
	local thrower = self.escort_of

	if not ai.valid(thrower) then
		return
	end

	local center = thrower.center
	self.goal = center + (center - self.player.position):normalized() * self.cfg.standoff_distance
	self:move(dt)
end

-- a spot around the player every goal_interval
function Station:roam_update(dt)
	local cfg = self.cfg
	self.goal_timer = self.goal_timer - dt

	if self.goal_timer <= 0 then
		self.goal_timer = cfg.goal_interval
		self.goal = self.player.position + from_angle(math.random() * 2 * math.pi) * cfg.goal_ellipse
	end

	self:move(dt)
end

function Station:move(dt)
	if self.goal ~= nil then
		self.node:force_move_to(self.goal, self.cfg.move_speed, self.cfg.move_accel, dt)
	end
end

function Station:shoot()
	local node = self.node
	local player = self.player
	local to_player = player.position - node.pos
	node:fire(to_player:length() < self.cfg.fire_radius and player.in_sight, to_player)
end

-- what it let out that is still around
function Station:alive_count()
	local kept = {}

	for _, enemy in ipairs(self.spawned) do
		if ai.valid(enemy) and not enemy.dead then
			table.insert(kept, enemy)
		end
	end

	self.spawned = kept
	return #kept
end

function Station:hangar(dt)
	self.spawn_timer = self.spawn_timer + dt

	if self.spawn_timer < self.cfg.spawn_interval then
		return
	end

	self.spawn_timer = 0
	self:spawn_one()
end

-- a fighter or a bomb out of one side of the hangar point, moving away
function Station:spawn_one()
	local cfg = self.cfg

	if self:alive_count() + self.pending >= cfg.max_spawned then
		return
	end

	local node = self.node
	local kind = cfg.spawn_kinds[math.random(#cfg.spawn_kinds)]
	local offset = SPAWN_OFFSETS[math.random(#SPAWN_OFFSETS)]:rotated(node.global_rotation)
	local at = node:local_point_units(cfg.spawn_origin) + offset * 0.5

	if self:spawn(kind, at, offset * 2) ~= nil then
		self.pending = self.pending + 1

		if kind == "fighter" then
			self:say("Launching a fighter. Form up on the base.")
		else
			self:say("Bomb away. Find the thrower.")
		end
	end
end

return Station
