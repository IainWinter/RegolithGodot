-- fighter: flies in formation behind a squad leader or roams a spot near
-- the player, keeps apart from everything close, flocks with the other
-- fighters, dodges what is ahead and shoots when the player is in range
-- and in sight. it never looks for the player, the player sensor tells it.
-- squads form over messages: a loner sends SQUAD_JOIN couriers to what is
-- near, a leader with room answers SQUAD_ACCEPT, the joiner confirms with
-- SQUAD_JOINED. shoot the courier and the squad never forms
--
-- states: idle holds position (no leader, no player), roam wanders a spot
-- near the player, formation keeps its slot behind the leader. update
-- picks the state each tick from what the messages left behind, a state
-- only decides the waypoint, fly() does the shared steering and shooting

local M = require("message_types")

local Fighter = class("fighter")

local SQUAD_INTERVAL_MIN = 0.25
local SQUAD_INTERVAL_MAX = 0.5
local TARGET_CHECK_INTERVAL = 0.5

function Fighter:init()
	self.player = nil
	self.leader = nil
	self.followers = {}
	self.target = nil
	self.meander_angle = math.random() * math.pi * 2
	self.squad_timer = 0
	self.target_timer = 0

	self:register_state("idle", { update = "idle_update" })
	self:register_state("roam", { update = "roam_update" })
	self:register_state("formation", { update = "formation_update" })
	self:transition("idle")
end

function Fighter:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	elseif kind == M.SQUAD_JOIN then
		if self.leader == nil and #self.followers < self.node.max_followers and msg.sender ~= self.node then
			self:send_instant(msg.sender, { kind = M.SQUAD_ACCEPT })
		end
	elseif kind == M.SQUAD_ACCEPT then
		if self.leader == nil and #self.followers == 0 and ai.valid(msg.sender) then
			self.leader = msg.sender
			self:send_instant(self.leader, { kind = M.SQUAD_JOINED })
		end
	elseif kind == M.SQUAD_JOINED then
		if #self.followers < self.node.max_followers then
			table.insert(self.followers, msg.sender)
		else
			self:send_instant(msg.sender, { kind = M.SQUAD_FULL })
		end
	elseif kind == M.SQUAD_FULL then
		if self.leader == msg.sender then
			self.leader = nil
		end
	end
end

function Fighter:update_squad(dt)
	if self.leader ~= nil and not ai.valid(self.leader) then
		self.leader = nil
	end

	local kept = {}

	for _, follower in ipairs(self.followers) do
		local other = ai.instance(follower)

		if other and other.leader == self.node then
			table.insert(kept, follower)
		end
	end

	self.followers = kept
	self.squad_timer = self.squad_timer - dt

	if self.squad_timer > 0 then
		return
	end

	self.squad_timer = ai.random(SQUAD_INTERVAL_MIN, SQUAD_INTERVAL_MAX)

	if self.leader ~= nil or #self.followers > 0 then
		return
	end

	self:broadcast(self.node.neighbor_radius * 2, { kind = M.SQUAD_JOIN })
end

function Fighter:formation_waypoint(pos)
	local node = self.node
	local leader = self.leader
	local leader_pos = leader.pos
	local leader_velocity = leader.linear_velocity
	local leader_speed = leader_velocity:length()
	local direction = leader_speed > 0 and leader_velocity / leader_speed or vec2(0, 0)

	if leader_speed < 0.1 and self.player then
		direction = (self.player.position - leader_pos):normalized()
	end

	local index = 0
	local squad = ai.instance(leader)

	if squad then
		for i, follower in ipairs(squad.followers) do
			if follower == node then
				index = i - 1
			end
		end
	end

	local rank = index // 2 + 1
	local side = (index % 2 == 0) and 1 or -1
	local back = -direction
	local right = vec2(direction.y, -direction.x)
	local spacing = node.formation_spacing

	local waypoint = leader_pos + back * (spacing * rank) + right * (spacing * 0.8 * rank * side)
	local match_speed = -1

	if pos:distance_to(waypoint) < 1.5 then
		match_speed = leader_speed
	end

	return waypoint, match_speed
end

function Fighter:roam_waypoint(pos, dt)
	local node = self.node
	local player = self.player

	self.target_timer = self.target_timer - dt

	if self.target == nil
		or self.target:distance_to(player.position) > node.roam_distance
		or (self.target_timer <= 0 and node:point_blocked(self.target)) then
		self.target_timer = TARGET_CHECK_INTERVAL
		self.target = node:pick_target(player.position)
	end

	local meander = self.target:distance_to(pos) < node.meander_radius

	if meander then
		self.meander_angle = (self.meander_angle + dt * 0.4) % (2 * math.pi)
		return self.target + from_angle(self.meander_angle) * 2, true
	end

	return self.target, false
end

-- every tick before the state: squad bookkeeping, then the state follows
-- from whether there is a leader or a player
function Fighter:update(dt)
	self:update_squad(dt)

	if self.leader ~= nil then
		self:transition("formation")
	elseif self.player ~= nil then
		self:transition("roam")
	else
		self:transition("idle")
	end
end

function Fighter:idle_update(dt)
	self:fly(self.node.pos, false, -1, dt)
end

function Fighter:roam_update(dt)
	local pos = self.node.pos
	local waypoint, meander = self:roam_waypoint(pos, dt)
	self:fly(waypoint, meander, -1, dt)
end

function Fighter:formation_update(dt)
	local pos = self.node.pos
	local waypoint, match_speed = self:formation_waypoint(pos)
	self:fly(waypoint, false, match_speed, dt)
end

-- steer toward the waypoint with separation, flocking and dodging, slow
-- down to meander or to match the leader, and shoot when the player is in
-- range and in sight
function Fighter:fly(waypoint, meander, match_speed, dt)
	local node = self.node
	local pos = node.pos
	local seek = node:path_steer_target(waypoint, dt)

	node:steer_to_waypoint(pos + node:steer_correction(dt) + (seek - pos))

	if meander then
		node.desired_speed = math.min(node.desired_speed, node.drive_max_speed * 0.35)
	end

	if match_speed >= 0 then
		node.desired_speed = math.min(node.desired_speed, match_speed + node.drive_max_speed * 0.2)
	end

	node:avoid_obstacles(dt)
	node:drive(dt)

	local pull = false
	local aim = vec2(1, 0)

	if self.player ~= nil then
		aim = self.player.position - pos
		pull = aim:length() < node.fire_radius and self.player.in_sight
	end

	node:fire(pull, aim)
end

return Fighter
