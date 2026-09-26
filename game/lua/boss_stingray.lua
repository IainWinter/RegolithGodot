-- boss_stingray: AiBoss1FinalPhase, the core that leaves Boss1's shell.
-- it orbits the player at a distance, lines up and dives past them,
-- dropping bombs and fighters or spraying volleys, and rams them when it
-- can. a close pass starts a fight: it parks a screen away, cages the
-- player with the trap, shields itself with rocks and pushes them out,
-- sprays arcs, and spawns bombs and fighters, then swings around to orbit
-- again. the player sensor says where the player is (their center of
-- mass), the node steers, shoots, rams, sizes the fight rocks and tells
-- us when the player turned to cloud. the numbers are exports on the node
--
-- states: idle until the player sensor reports them, orbit (a ring at
-- roam_radius, a dive every orbit_roam_time), prepare_dive (turn onto the
-- dive line, the warning line shows it), dive (straight past the player,
-- drops or volleys inside the camera, a touch rams and starts the fight,
-- a near pass starts it too, a far one lines up again or gives up into
-- aggress after dive_max_misses), aggress (chase until engage radius or
-- give up, then fight), fight (anchored a screen beside the player for
-- fight_time), reposition (swing around the player to a clear spot on the
-- ring, then orbit)

local M = require("message_types")

local Stingray = class("boss_stingray")

function Stingray:init()
	self.player = nil
	self.greeted = false
	self.pos = vec2(0, 0)
	self.player_pos = vec2(0, 0)
	self.active_zone = vec2(0, 0)
	self.camera_pos = vec2(0, 0)

	self.orbit_angle = 0
	self.roam_timer = 0

	self.dive = {
		from = nil,
		index = 0,
		miss_count = 0,
		closest = 0,
		point = vec2(0, 0),
		mix_fighters = false,
		big_volley = false,
		volley_fired = false,
		barrage_timer = 0,
		bomb_timer = 0,
		bombs_dropped = 0,
		dropping_bombs = false,
	}

	self.fight = {
		timer = 0,
		side = 1,
		position = vec2(0, 0),
		rocks_spawned = false,
		rocks_pushed = false,
		bomb_timer = 0,
		fighter_timer = 0,
		spawned = {},
		pending = 0,
	}

	self.aggress_timer = 0
	self.reposition = { dir = 1, target_angle = 0 }

	self:register_state("idle", {})
	self:register_state("orbit", { enter = "orbit_enter", update = "orbit_update" })
	self:register_state("prepare_dive", { enter = "prepare_dive_enter", update = "prepare_dive_update" })
	self:register_state("dive", { enter = "dive_enter", update = "dive_update" })
	self:register_state("aggress", { enter = "aggress_enter", update = "aggress_update" })
	self:register_state("fight", { enter = "fight_enter", update = "fight_update", exit = "fight_exit" })
	self:register_state("reposition", { enter = "reposition_enter", update = "reposition_update" })
	self:transition("idle")
end

function Stingray:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		if not self.greeted then
			self.greeted = true
			self:say("Out of the shell. Nothing between us now.")
		end

		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	elseif kind == M.SPAWNED then
		if msg.tag == "fighter" then
			self.fight.pending = math.max(self.fight.pending - 1, 0)
			table.insert(self.fight.spawned, msg.node)
		end
	elseif kind == M.SPAWN_EXPIRED then
		if msg.tag == "fighter" then
			self.fight.pending = math.max(self.fight.pending - 1, 0)
		end
	elseif kind == M.PLAYER_ENTERED_CLOUD then
		-- PlayerEnteredCloudStateEvent: killing the player mid fight ends
		-- it with a ring of bullets
		if self:state() == "fight" then
			self.node:fire_burst(vec2(1, 0), self.node.fight_kills_player_bullet_ring_count)
			self:say("Down. Back to the dark.", 1.5)
			self:transition("reposition")
		end
	end
end

-- where things are this tick: the body's center of mass (the node keeps
-- pos at it), the player's from their last report, the camera box
function Stingray:sense()
	local node = self.node
	self.pos = node.pos

	if self.player ~= nil then
		self.player_pos = self.player.center or self.player.position
	else
		self.player_pos = node.player_pos
	end

	self.active_zone = self:camera_half_extents()
	self.camera_pos = self:camera_center(self.player_pos)
end

-- every tick before the state: idle without a player, else the arcs are
-- off unless the fight turns them on
function Stingray:update(dt)
	if self.player == nil then
		self:transition("idle")
		return
	end

	if self:state() == "idle" then
		self:transition("orbit")
	end

	self:sense()
	self.node:fire_arc(false, vec2(0, 0))
end

-- orbit

function Stingray:orbit_enter()
	self.roam_timer = 0
end

function Stingray:orbit_update(dt)
	local node = self.node
	self.orbit_angle = (self.pos - self.player_pos):angle() + node.orbit_speed
	self.roam_timer = self.roam_timer + dt

	if self.roam_timer >= node.orbit_roam_time then
		self.roam_timer = 0
		self.dive.miss_count = 0
		self:start_prepare_dive(self.pos + node.linear_velocity / math.max(node.accel, 0.01))
	end

	node:steer_toward_target(self.player_pos + from_angle(self.orbit_angle) * node.roam_radius, node.roam_speed, dt)
end

-- prepare dive: the line is laid from where the dive starts (from, nil
-- for the body's spot), the state turns the nose onto it

function Stingray:start_prepare_dive(from)
	self:sense()
	self.dive.from = from
	self:transition("prepare_dive")
end

function Stingray:prepare_dive_enter()
	local node = self.node
	local d = self.dive
	local from = d.from or self.pos
	d.from = nil

	d.index = d.index + 1
	d.dropping_bombs = d.index % 2 == 0
	d.mix_fighters = math.random() < 0.5
	d.bombs_dropped = 0

	local direction = (self.player_pos - from):normalized()
	local tangent = vec2(-direction.y, direction.x) * (math.random() < 0.5 and 1 or -1)
	local pass_point = self.player_pos + tangent * node.dive_tangent
	local dive_direction = (pass_point - from):normalized()

	d.point = pass_point + dive_direction * node.dive_overshoot
	d.big_volley = math.random() < 0.5
	d.volley_fired = false
	d.closest = from:distance_to(self.player_pos)

	-- the telegraph of start_prepare_dive_warned, a line along the dive
	-- out to a camera height past the turn point. it starts on the body
	-- when the dive starts from where the boss is
	local warn_direction = (d.point - from):normalized()
	local warn_from = from

	if from == self.pos and node:is_loaded() then
		warn_from = node:effect_origin_units()
	end

	ai.warn(warn_from, d.point + warn_direction * ai.camera_size(), node.dive_warning_time)

	if d.dropping_bombs then
		self:say("Lining up. Bombs on this pass.", 1.5)
	else
		self:say("Lining up. Hold still.", 1.5)
	end
end

function Stingray:prepare_dive_update(dt)
	local node = self.node
	local d = self.dive
	local want = (d.point - self.pos):angle() + math.pi * 0.5
	local diff = ai.wrap_angle(want - node.global_rotation)

	if math.abs(diff) < 0.1 then
		self:transition("dive")
	end

	node:steer_toward_target(d.point, 0, dt)
end

-- dive

function Stingray:dive_enter()
	self.dive.bomb_timer = 0
	self.dive.barrage_timer = 0
end

function Stingray:inside_camera()
	return math.abs(self.pos.x - self.player_pos.x) < self.active_zone.x and math.abs(self.pos.y - self.player_pos.y) < self.active_zone.y
end

function Stingray:dive_update(dt)
	local node = self.node
	local d = self.dive
	d.closest = math.min(d.closest, self.pos:distance_to(self.player_pos))

	local inside = self:inside_camera()

	if inside and d.dropping_bombs then
		d.bomb_timer = d.bomb_timer + dt

		if d.bombs_dropped < node.dive_bombs_per_dive and d.bomb_timer >= node.dive_bomb_interval then
			d.bomb_timer = 0
			d.bombs_dropped = d.bombs_dropped + 1

			local back = -node.linear_velocity:normalized()
			local at = self.pos + back * (node:radius_units() + 0.2)
			local fighter = d.mix_fighters and math.random() < 0.5
			self:spawn(fighter and "fighter" or "bomb", at, back * 2.0, false, 10, "dive")
		end
	elseif inside then
		if d.big_volley then
			if not d.volley_fired then
				d.volley_fired = true
				node:fire_burst(vec2(1, 0), node.dive_volley_big)
			end
		else
			d.barrage_timer = d.barrage_timer + dt

			if d.barrage_timer >= node.dive_barrage_interval then
				d.barrage_timer = 0
				node:fire_burst(vec2(1, 0), node.dive_volley_small)
			end
		end
	end

	local target = self.player.player

	if node:touching(target) then
		-- the ContactEvent of the original: the ram, then the fight
		node:ram(target)
		self:transition("fight")
	elseif (d.point - self.pos):dot(node:forward()) < 0 or self.pos:distance_to(d.point) < 1.5 then
		if d.closest > node.dive_near_radius then
			d.miss_count = d.miss_count + 1

			if d.miss_count >= node.dive_max_misses then
				self:transition("aggress")
			else
				self:start_prepare_dive(self.pos)
			end
		else
			self:transition("fight")
		end
	end

	node:steer_toward_target(d.point, node.dive_speed, dt)
end

-- aggress

function Stingray:aggress_enter()
	self.aggress_timer = 0
	self:say("Enough circling.", 1.5)
end

function Stingray:aggress_update(dt)
	local node = self.node
	self.aggress_timer = self.aggress_timer + dt

	if self.pos:distance_to(self.player_pos) < node.aggress_engage_radius or self.aggress_timer >= node.aggress_give_up_time then
		self:transition("fight")
		return
	end

	node:steer_toward_target(self.player_pos, node.aggress_speed, dt)
end

-- fight

function Stingray:start_fight()
	self:sense()
	self:transition("fight")
end

function Stingray:fight_enter()
	local node = self.node
	local f = self.fight
	self.dive.miss_count = 0
	f.side = self.pos.x >= self.player_pos.x and 1 or -1
	f.timer = 0
	f.bomb_timer = 0
	f.fighter_timer = 0
	f.position = self.player_pos + vec2(f.side * ai.camera_size() * node.fight_offset_ratio, 0)
	f.rocks_spawned = false
	f.rocks_pushed = false

	if ai.valid(node.shield) then
		node.shield.active = true
	end

	self:say("Stay in the box.", 2.0)
end

-- the trap and shield let go however the fight ends
function Stingray:fight_exit()
	local node = self.node

	if ai.valid(node.trap) then
		node.trap.active = false
	end

	if ai.valid(node.shield) then
		node.shield.active = false
	end
end

-- the band just off the camera on the fight side, where rocks and bombs
-- come from
function Stingray:fight_offscreen_zone()
	local band = math.max(self.active_zone.x * self.node.fight_spawn_band, 0.5)
	return {
		center = vec2(self.camera_pos.x + self.fight.side * (self.active_zone.x + band), self.camera_pos.y),
		half = vec2(band, self.active_zone.y),
	}
end

-- fight_rock_count_min..max one chunk rocks from off screen, drifting at
-- the fight spot for the shield to gather
function Stingray:spawn_fight_rocks()
	local node = self.node
	local props = node.rock_props

	if props == nil then
		return
	end

	local zone = self:fight_offscreen_zone()
	local count = math.random(node.fight_rock_count_min, node.fight_rock_count_max)

	for _ = 1, count do
		local at = ai.random_in_box(zone.center, zone.half, 0)
		local velocity = (self.fight.position - at):normalized() * node.fight_rock_speed
		self:spawn_rock(node:fight_rock_props(node:fight_rock_cells()), at, velocity, true, 10, "rock")
	end
end

function Stingray:fight_alive_count()
	local kept = {}

	for _, fighter in ipairs(self.fight.spawned) do
		if ai.valid(fighter) and not fighter.dead then
			table.insert(kept, fighter)
		end
	end

	self.fight.spawned = kept
	return #kept
end

function Stingray:fight_update(dt)
	local node = self.node
	local f = self.fight
	local distance = self.pos:distance_to(f.position)
	local trap_zone = self.active_zone * node.fight_trap_camera_scale
	local near_camera = math.abs(self.pos.x - self.camera_pos.x) < trap_zone.x and math.abs(self.pos.y - self.camera_pos.y) < trap_zone.y

	if ai.valid(node.trap) then
		local size = ai.camera_size()
		node.trap.active = near_camera and distance < node.fight_arrive_radius
		node.trap:set_box(vec2(self.pos.x - f.side * size, self.pos.y), vec2(1, 1) * size * 0.8, 0)
	end

	if distance >= node.fight_arrive_radius then
		node:steer_fight(f.position, math.max(node.roam_speed, distance / math.max(node.fight_return_time, 0.1)), dt)
		return
	end

	if not f.rocks_spawned then
		f.rocks_spawned = true
		self:spawn_fight_rocks()
	end

	if not f.rocks_pushed and f.timer / node.fight_time >= 0.5 then
		f.rocks_pushed = true

		if ai.valid(node.shield) then
			node.shield:push_rocks(self.pos, node.fight_push_speed)
		end
	end

	node:fire_arc(true, self.player_pos - self.pos)

	local zone = self:fight_offscreen_zone()

	f.bomb_timer = f.bomb_timer + dt

	if f.bomb_timer >= node.fight_bomb_interval then
		f.bomb_timer = 0
		local at = ai.random_in_box(zone.center, zone.half, 0)
		self:spawn("bomb", at, (self.player_pos - at):normalized() * node.fight_bomb_speed, true, 10, "bomb")
	end

	f.fighter_timer = f.fighter_timer + dt

	if f.fighter_timer >= node.fight_fighter_interval then
		if self:fight_alive_count() + f.pending < node.fight_max_fighters then
			f.fighter_timer = 0
			local behind = node:radius_units() + node.fight_spawn_behind
			local at = self.pos + vec2(f.side * behind, 0) + ai.random_in_circle(node.fight_spawn_behind)

			if self:spawn("fighter", at, vec2(0, 0), false, 10, "fighter") ~= nil then
				f.pending = f.pending + 1
			end
		end
	end

	f.timer = f.timer + dt

	if f.timer >= node.fight_time then
		self:transition("reposition")
	end

	node:steer_fight(f.position, 0, dt)
end

-- reposition: swing around the player, the way the body was already
-- moving, to the first clear spot on the ring at least a quarter turn on

function Stingray:reposition_enter()
	local node = self.node
	local r = self.reposition
	self.orbit_angle = (self.pos - self.player_pos):angle()

	local radial = from_angle(self.orbit_angle)
	r.dir = radial:cross(node.linear_velocity) >= 0 and 1 or -1

	local min_arc = math.pi * 0.5
	local step = 2 * math.pi / 12
	local arc = min_arc + step * 11

	for i = 0, 11 do
		local candidate = min_arc + step * i
		local point = self.player_pos + from_angle(self.orbit_angle + r.dir * candidate) * node.roam_radius

		if node:space_is_free(point, node.reposition_clearance) then
			arc = candidate
			break
		end
	end

	r.target_angle = self.orbit_angle + r.dir * arc
end

function Stingray:reposition_update(dt)
	local node = self.node
	local r = self.reposition
	local radius = math.max(node.roam_radius, 1)
	self.orbit_angle = self.orbit_angle + r.dir * node.roam_speed / radius * dt

	if r.dir * (r.target_angle - self.orbit_angle) <= 0 then
		self:transition("orbit")
	end

	node:steer_toward_target(self.player_pos + from_angle(self.orbit_angle) * radius, node.roam_speed, dt)
end

return Stingray
