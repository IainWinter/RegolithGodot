-- base: the structure of AiBase + AiThrower. keeps upright, holds its spot
-- and only picks a new one around the player (an ellipse, every
-- goal_interval) once they have gone far, grabs the bombs and small rocks
-- that drift into its thrower's reach, parks them on the arc facing the
-- player and flings them once the player is inside the throw radius. the
-- EnemyThrower child does the pulling and swinging (step), this decides
-- what to grab and when to throw. the player sensor tells it where they
-- are, the ring geometry and times stay on the thrower node
--
-- states: idle until the player sensor reports them (what is held stays
-- held), guard while they are known but outside only_throw_at_radius
-- (collect and hold), throw while they are inside it (hold timers run,
-- each thing is flung hold_time after it was grabbed)

local M = require("message_types")

local Base = class("base")

local DEFAULTS = {
	move_speed = 1.0,
	move_accel = 1.0,
	goal_interval = 25.0,
	far_distance = 20.0,
	goal_ellipse = vec2(16.0, 6.0),
	align_torque = 0.5,
	align_damping = 2.0,
	find_interval = 0.2,
}

function Base:init()
	self:config(DEFAULTS)
	self.player = nil
	self.last_seen = nil
	self.greeted = false
	self.goal = nil
	self.goal_timer = 0
	self.find_timer = 0
	-- instance id -> seconds held, for the things not yet thrown
	self.hold_timers = {}
	self.thrower = self.node:get_thrower()

	self:register_state("idle", {})
	self:register_state("guard", {})
	self:register_state("throw", { update = "throw_update" })
	self:transition("idle")
end

function Base:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		if kind == M.PLAYER_SEEN and not self.greeted then
			self.greeted = true
			self:say("Contact. Hold what you have, wait for them to come close.")
		end

		self.player = msg
		self.last_seen = msg.position
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	end
end

-- every tick: upright, the roam goal, the thrower mechanics and grabbing,
-- then the state from where the player is
function Base:update(dt)
	local node = self.node
	local cfg = self.cfg

	node:align_angle(0, cfg.align_torque, cfg.align_damping, dt)

	local player = self.player
	local aim = player and player.position or self.last_seen or (node.pos + vec2(1, 0))

	self:collect(dt, aim)

	if player == nil then
		self:transition("idle")
		return
	end

	self:roam(dt, player.position)

	local thrower = self.thrower

	if ai.valid(thrower) and thrower.center:distance_to(player.position) <= thrower.only_throw_at_radius then
		self:transition("throw")
	else
		self:transition("guard")
	end
end

-- a new spot around the player every goal_interval while they are far,
-- and always on the way to the last one
function Base:roam(dt, player_pos)
	local node = self.node
	local cfg = self.cfg

	self.goal_timer = self.goal_timer - dt

	if self.goal_timer <= 0 and node.pos:distance_to(player_pos) > cfg.far_distance then
		self.goal_timer = cfg.goal_interval
		self.goal = player_pos + from_angle(math.random() * 2 * math.pi) * cfg.goal_ellipse
	end

	if self.goal ~= nil then
		node:force_move_to(self.goal, cfg.move_speed, cfg.move_accel, dt)
	end
end

-- runs the thrower and grabs what comes in reach every find_interval
function Base:collect(dt, aim)
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

-- the player is close: each held thing goes hold_time after it was grabbed
function Base:throw_update(dt)
	local thrower = self.thrower

	if not ai.valid(thrower) then
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
				self:say("Loose.", 0.6)
			end
		end
	end
end

return Base
