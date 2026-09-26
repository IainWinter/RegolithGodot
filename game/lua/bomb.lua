-- bomb: drifts toward a thrower that has room, else toward where the
-- player was last reported, turning at a bounded rate. close to the player
-- with a clear line it lights its fuse, the node does the bursting. the
-- fuse countdown and being held by a thrower are mechanics on the node
--
-- states: idle until the player sensor reports them, seek_thrower while a
-- thrower with room is nearer than the player, seek_player otherwise, and
-- fused once the fuse is lit (the node stops ticking the script then)

local M = require("message_types")

local Bomb = class("bomb")

function Bomb:init()
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
	local node = self.node

	if node.exploding then
		self:transition("fused")
		return
	end

	if self.player == nil then
		self:transition("idle")
		return
	end

	self.goal = nil

	if node.seek_thrower and not node:is_thrown() then
		self.goal = node:thrower_goal(self.player.position)
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

	if to_goal:length() < node.start_exploding_radius and player.in_sight then
		node:start_fuse(node.fuse_time)
		self:transition("fused")
		return
	end

	self:drift(player.position, dt)
end

function Bomb:drift(target, dt)
	local node = self.node
	local seek = node:path_steer_target(target, dt)

	if node.path_blocked then
		return
	end

	node:steer(seek - node.pos, dt)
end

return Bomb
