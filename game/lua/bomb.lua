-- bomb: drifts toward a thrower that has room, else toward where the
-- player was last reported, turning at a bounded rate. close to the player
-- with a clear line it emits start_fuse, and the BombBehavior child on
-- the scene runs the countdown and the burst. being held by a thrower is
-- a mechanic on the Throwable child
--
-- states: idle until the player sensor reports them, seek_thrower while a
-- thrower with room is nearer than the player, seek_player otherwise, and
-- fused once the fuse is lit (the script stops trying to steer then)

local M = require("message_types")

local Bomb = class("bomb")

function Bomb:settings()
	return {
		speed = 3.0,
		turn_strength = 4.0,
		turn_commit_angle = 0.6,
		start_exploding_radius = 3.0,
		fuse_time = 2.0,
		seek_thrower = true,
	}
end

function Bomb:init()
	self:apply_settings()
	self.player = nil
	self.goal = nil

	self:register_state("idle", {})
	self:register_state("seek_thrower", { update = "seek_thrower_update" })
	self:register_state("seek_player", { update = "seek_player_update" })
	self:register_state("fused", {})
	self:transition("idle")
end

function Bomb:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	end
end

-- every tick before the state: pick who to chase
function Bomb:update(dt)
	if self:state() == "fused" then
		return
	end

	-- a thrower is holding it, the swing sets the velocity
	if self.node:is_held() then
		return
	end

	if self.player == nil then
		self:transition("idle")
		return
	end

	self.goal = nil

	if self.cfg.seek_thrower and not self.node:is_thrown() then
		self.goal = self.node:thrower_goal(self.player.position)
	end

	if self.goal ~= nil then
		self:transition("seek_thrower")
	else
		self:transition("seek_player")
	end
end

function Bomb:seek_thrower_update(dt)
	self:drift(self.goal, dt)
end

function Bomb:seek_player_update(dt)
	local node = self.node
	local player = self.player
	local to_goal = player.position - node.pos

	if to_goal:length() < self.cfg.start_exploding_radius and player.in_sight then
		node:emit_event("start_fuse", { time = self.cfg.fuse_time })
		self:transition("fused")
		return
	end

	self:drift(player.position, dt)
end

function Bomb:drift(target, dt)
	local node = self.node
	local cfg = self.cfg
	local seek = node:path_steer_target(target, dt)

	if node.path_blocked then
		return
	end

	node:steer_bounded_turn(seek - node.pos, cfg.speed, cfg.turn_strength, cfg.turn_commit_angle, dt)
end

return Bomb
