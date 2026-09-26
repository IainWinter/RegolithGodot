-- boss_compass: Boss1's shell, BossController plus the shell's AiThrower.
-- holds its spot, throws what drifts into the thrower's reach back at the
-- player, drops rocks for its shield from a zone over the hull, fires
-- homing bolts from whichever hull point faces the player, and runs its
-- phases: each lasts while the weakpoint cells of its type last and
-- spawns bombs and fighters from zones on the hull. once the last phase's
-- weakpoints are gone the final phase (the stingray) leaves the hull and
-- the shell is a rock. the cell sensor says when cells leave the body,
-- the player sensor where the player is, the node does the throwing,
-- shielding, trapping and shooting mechanics
--
-- states: phase_1 (bolts, thrower, one bomb zone), phase_2 (bolts, no
-- thrower, a bomb and a fighter zone), detached (the stingray is out, the
-- shell is done). advance() moves on whenever the body loses cells

local M = require("message_types")

local Compass = class("boss_compass")

local DEFAULTS = {
	rock_interval = 4.0,
	rock_max_alive = 6,
	rock_zone_position = vec2(0.0, 2.8),
	rock_zone_scale = vec2(1.8, 0.8),
	find_interval = 0.2,
}

-- the phases of the original BossController. zones are in the prefab's
-- -1..1 hull space, angles in radians, intervals in seconds
local PHASES = {
	{
		alive_type = "CELL_WEAKPOINT1",
		weapon_active = true,
		thrower_active = true,
		line = "Shell holding. Hold what drifts in and throw it back at them.",
		zones = {
			{ kind = "bomb", max_alive = 3, interval = 9.0, burst = 1, position = vec2(-0.15, 1.1), scale = vec2(0.85, 0.6), angle = -5.6 },
		},
	},
	{
		alive_type = "CELL_WEAKPOINT2",
		weapon_active = true,
		thrower_active = false,
		line = "Outer plating gone. Open the hangar, keep the bolts coming.",
		zones = {
			{ kind = "bomb", max_alive = 12, interval = 7.0, burst = 4, position = vec2(-0.65, 0.1), scale = vec2(0.4, 0.35), angle = -5.6 },
			{ kind = "fighter", max_alive = 6, interval = 9.0, burst = 3, position = vec2(-0.05, 0.85), scale = vec2(0.4, 0.4), angle = -5.6 },
		},
	},
}

local DETACH_LINE = "Shell breached. Leaving the husk, this ends in the open."

-- a fresh copy of the phase table for this instance, with the weakpoint
-- types resolved and a running timer on each zone
local function copy_phases()
	local out = {}

	for i, phase in ipairs(PHASES) do
		local zones = {}

		for j, zone in ipairs(phase.zones) do
			local z = {}

			for k, v in pairs(zone) do
				z[k] = v
			end

			z.timer = 0
			zones[j] = z
		end

		out[i] = {
			alive_type = ai.cell_type(phase.alive_type),
			weapon_active = phase.weapon_active,
			thrower_active = phase.thrower_active,
			line = phase.line,
			zones = zones,
		}
	end

	return out
end

function Compass:init()
	self:config(DEFAULTS)
	self.phases = copy_phases()
	-- 0 until the body is loaded and advance() has looked at it
	self.phase = 0
	self.settled = false
	self.finished = false
	self.weapon_active = false
	self.player = nil
	self.thrower = self.node:get_thrower()

	-- what the zones let out, and the rocks for the shield
	self.spawned = {}
	self.pending = 0
	self.rocks = {}
	self.rocks_pending = 0
	self.rock_timer = 0

	self.fire_timer = 0
	self.fire_point = nil

	-- instance id -> seconds held, for what the thrower holds
	self.hold_timers = {}
	self.find_timer = 0

	for i = 1, #self.phases do
		self:register_state("phase_" .. i, { enter = "phase_enter", update = "phase_update" })
	end

	self:register_state("detached", { enter = "detached_enter" })
end

function Compass:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	elseif kind == M.CELLS_REMOVED or kind == M.SPRITE_SPLIT then
		self:advance()
	elseif kind == M.SPAWNED then
		self:on_spawned(msg)
	elseif kind == M.SPAWN_EXPIRED then
		if msg.tag == "rock" then
			self.rocks_pending = math.max(self.rocks_pending - 1, 0)
		elseif msg.tag == "zone" then
			self.pending = math.max(self.pending - 1, 0)
		end
	end
end

-- a placed spawn: rocks join the shield's supply, zone spawns are counted
-- against the zone caps and a bomb leaves the hull moving away from it
function Compass:on_spawned(msg)
	local node = msg.node

	if msg.tag == "rock" then
		self.rocks_pending = math.max(self.rocks_pending - 1, 0)
		table.insert(self.rocks, node)
	elseif msg.tag == "zone" then
		self.pending = math.max(self.pending - 1, 0)

		if ai.valid(node) then
			if node.ai_class == "bomb" then
				node.linear_velocity = (msg.request.position - self.node.pos):normalized() * node.speed
			end

			table.insert(self.spawned, node)
		end
	end
end

-- the phase from the weakpoints left on the body: past the last one the
-- final phase leaves
function Compass:advance()
	local node = self.node

	if self.finished or not node:is_loaded() then
		return
	end

	local phase = math.max(self.phase, 1)

	while phase <= #self.phases and node:count_cells_of_type(self.phases[phase].alive_type) == 0 do
		phase = phase + 1
	end

	self.phase = phase

	if phase > #self.phases then
		self.finished = true
		self:transition("detached")
	else
		self:transition("phase_" .. phase)
	end
end

-- every tick: settle into the first phase once the body is loaded, then
-- hold station, run the thrower, drop shield rocks and shoot. the zones
-- are the state's
function Compass:update(dt)
	if not self.settled then
		self.settled = true
		self:advance()
	end

	if self.finished then
		return
	end

	local node = self.node
	node:hold_station(dt)

	local player = self.player
	local thrower = self.thrower
	local aim

	if player ~= nil then
		aim = player.position
	elseif ai.valid(thrower) then
		aim = thrower.center
	else
		aim = node.pos + vec2(1, 0)
	end

	self:collect(dt, aim)
	self:throw_held(dt)
	self:drop_rocks(dt)
	self:shoot(dt)
end

-- a phase begins: the parts it uses come on, the rest let go
function Compass:phase_enter()
	local phase = self.phases[self.phase]
	local node = self.node
	local thrower = self.thrower

	if phase == nil then
		return
	end

	if ai.valid(thrower) then
		thrower.active = phase.thrower_active
	end

	self.weapon_active = phase.weapon_active

	if ai.valid(node.shield) then
		node.shield.active = true
	end

	if ai.valid(node.trap) then
		node.trap.active = true
	end

	self:say(phase.line)
end

-- the zones of the current phase let bombs and fighters out on their
-- clocks, in bursts, while what is out stays under the zone's cap
function Compass:phase_update(dt)
	local phase = self.phases[self.phase]

	if phase == nil then
		return
	end

	for _, zone in ipairs(phase.zones) do
		zone.timer = zone.timer + dt

		if zone.timer >= zone.interval then
			zone.timer = 0

			for _ = 1, zone.burst do
				if self:alive_count() + self.pending >= zone.max_alive then
					break
				end

				local at = self:zone_point(zone.position, zone.scale, zone.angle)

				if self:spawn(zone.kind, at, vec2(0, 0), false, 10, "zone") ~= nil then
					self.pending = self.pending + 1
				end
			end
		end
	end
end

function Compass:detached_enter()
	self:say(DETACH_LINE)
	self.node:detach_final_phase()
end

-- what the zones let out that is still around
function Compass:alive_count()
	local kept = {}

	for _, enemy in ipairs(self.spawned) do
		if ai.valid(enemy) and not enemy.dead then
			table.insert(kept, enemy)
		end
	end

	self.spawned = kept
	return #kept
end

-- a random point in a zone box on the hull, world units
function Compass:zone_point(position, scale, angle)
	local node = self.node
	local center = node:local_point_units(position)
	local half = scale * node:half_extent_units()
	return ai.random_in_box(center, half, node.global_rotation - angle)
end

-- a rock for the shield from the zone over the hull every rock_interval
-- while under the cap
function Compass:drop_rocks(dt)
	local cfg = self.cfg
	self.rock_timer = self.rock_timer + dt

	if self.rock_timer < cfg.rock_interval then
		return
	end

	self.rock_timer = 0

	local kept = {}

	for _, rock in ipairs(self.rocks) do
		if ai.valid(rock) then
			table.insert(kept, rock)
		end
	end

	self.rocks = kept

	local props = self.node.rock_props

	if props ~= nil and #self.rocks + self.rocks_pending < cfg.rock_max_alive then
		local at = self:zone_point(cfg.rock_zone_position, cfg.rock_zone_scale, 0)

		if self:spawn_rock(props, at, vec2(0, 0), false, 10, "rock") ~= nil then
			self.rocks_pending = self.rocks_pending + 1
		end
	end
end

-- runs the thrower and grabs what comes in reach every find_interval
function Compass:collect(dt, aim)
	local thrower = self.thrower

	if not ai.valid(thrower) then
		return
	end

	thrower:step(dt, aim)

	self.find_timer = self.find_timer - dt

	if self.find_timer <= 0 and thrower:can_hold_more() then
		self.find_timer = self.cfg.find_interval

		for _, thing in ipairs(thrower:find_throwables()) do
			if thrower:can_hold_more() and thrower:grab(thing) then
				self.hold_timers[ai.id(thing)] = 0
			end
		end
	end

	-- forget the timers of what is gone or already flying
	local live = {}

	for _, thing in ipairs(thrower:held()) do
		if not thrower:is_throwing(thing) then
			live[ai.id(thing)] = true
		end
	end

	for id in pairs(self.hold_timers) do
		if not live[id] then
			self.hold_timers[id] = nil
		end
	end
end

-- while the player is inside the throw radius each held thing goes
-- hold_time after it was grabbed
function Compass:throw_held(dt)
	local thrower = self.thrower
	local player = self.player

	if player == nil or not ai.valid(thrower) or not thrower.active then
		return
	end

	if thrower.center:distance_to(player.position) > thrower.only_throw_at_radius then
		return
	end

	for _, thing in ipairs(thrower:held()) do
		if not thrower:is_throwing(thing) then
			local id = ai.id(thing)
			local held = (self.hold_timers[id] or 0) + dt
			self.hold_timers[id] = held

			if held >= thrower.hold_time then
				thrower:throw(thing)
				self.hold_timers[id] = nil
			end
		end
	end
end

-- homing bolts at the player from a hull point on their side, a new
-- point every fire_cooldown
function Compass:shoot(dt)
	local node = self.node
	local player = self.player
	local points = node.fire_points

	if player == nil or not self.weapon_active or #points == 0 then
		node:fire(false, vec2(1, 0))
		return
	end

	self.fire_timer = self.fire_timer - dt

	if self.fire_timer <= 0 or self.fire_point == nil then
		self.fire_timer = node.fire_cooldown
		self.fire_point = self:pick_fire_point(points, player.position)
	end

	local from = node:local_point_units(self.fire_point)
	node:fire_from(self.fire_point, player.position - from)
end

-- one of the hull points facing the player, the current one when none do
function Compass:pick_fire_point(points, player_pos)
	local node = self.node
	local to_player = player_pos - node.pos
	local front = {}

	for _, local_point in ipairs(points) do
		if (node:local_point_units(local_point) - node.pos):dot(to_player) > 0 then
			table.insert(front, local_point)
		end
	end

	if #front > 0 then
		return front[math.random(#front)]
	end

	return self.fire_point or points[1]
end

return Compass
