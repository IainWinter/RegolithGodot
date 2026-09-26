-- gun: the GunEntity with AiGunHostSystem and AiAngleAlignment. the node
-- is an EnemyGun, a mount with a barrel part hanging on a pin joint at its
-- center. it turns the barrel onto the player with a spring (align_aim, the
-- AiAngleAlignment torque and damping) and pulls the trigger along the
-- barrel's facing when it is aimed within aim_tolerance, the player is
-- within range and the muzzle has a clear line to them. the host is
-- whatever else shares a world joint with the mount (ai.jointed, the
-- barrel does not count); its gun_fire property, when it has one, holds
-- the trigger. a gun with no host fires on its own and looks for one every
-- host_retry_interval. the player sensor tells it where they are
--
-- states: idle until the player sensor reports them, track while turning
-- onto them or held back (out of range, blocked, host says no), fire while
-- the trigger is down
--
-- Gun is a global so turret.lua can extend it (class("turret", Gun)), the
-- runtime loads the files in name order

local M = require("message_types")

Gun = class("gun")

Gun.DEFAULTS = {
	range = 10.0,
	-- where the shots leave along the facing when the node has no barrel
	muzzle = 0.4,
	aim_tolerance = 0.2,
	-- the enemy_gun prefab's AiAngleAlignment
	align_torque = 40.0,
	align_damping = 6.0,
	-- rad/s cap on the barrel's spin, zero for none
	max_turn_rate = 0.0,
	host_retry_interval = 0.5,
	los_ignore_groups = { "player", "gun", "gun_host" },
}

-- the tunables this class starts from, a subclass merges its own on top
function Gun:defaults()
	return Gun.DEFAULTS
end

function Gun:init()
	self:config(self:defaults())
	self.player = nil
	self.host = nil
	self.host_timer = 0

	self:register_state("idle", { enter = "idle_enter" })
	self:register_state("track", {})
	self:register_state("fire", {})
	self:transition("idle")
end

function Gun:on_message(msg)
	local kind = msg.kind

	if kind == M.PLAYER_SEEN or kind == M.PLAYER_UPDATE then
		self.player = msg
	elseif kind == M.PLAYER_LOST then
		self.player = nil
	end
end

-- the barrel's angle, the mount's own without one
function Gun:aim_angle()
	return self.node:aim_angle()
end

function Gun:facing()
	return from_angle(self:aim_angle())
end

-- the barrel's tip, where the shots leave
function Gun:muzzle_position()
	local node = self.node

	if node:has_barrel() then
		return node:muzzle_position()
	end

	return node.pos + self:facing() * self.cfg.muzzle
end

-- the sprite on the other end of a joint that is not one of the gun's own
-- parts, looked for again every host_retry_interval while there is none
function Gun:find_host(dt)
	if ai.valid(self.host) then
		return
	end

	self.host = nil
	self.host_timer = self.host_timer - dt

	if self.host_timer > 0 then
		return
	end

	self.host_timer = self.cfg.host_retry_interval

	for _, other in ipairs(self:jointed()) do
		if not self.node:is_part(other) then
			self.host = other
			break
		end
	end
end

-- a host without a gun_fire property lets it fire, so does no host
function Gun:host_fires()
	if not ai.valid(self.host) then
		return true
	end

	local fire = self.host.gun_fire
	return fire == nil or fire == true
end

-- turns the barrel onto an angle with the alignment spring
function Gun:aim(target_angle, dt)
	local cfg = self.cfg
	self.node:align_aim(target_angle, cfg.align_torque, cfg.align_damping, dt, cfg.max_turn_rate or 0)
end

function Gun:idle_enter()
	self.node:fire(false, self:facing())
end

-- every tick: the host, then aim and the trigger
function Gun:update(dt)
	self:find_host(dt)

	local player = self.player

	if player == nil then
		self:transition("idle")
		return
	end

	local node = self.node
	local cfg = self.cfg
	local to_player = player.position - node:pivot_position()
	local distance = to_player:length()
	local aim_angle = self:aim_angle()
	local delta_angle = ai.wrap_angle(to_player:angle() - aim_angle)

	self:aim(aim_angle + delta_angle, dt)

	local aimed = math.abs(delta_angle) < cfg.aim_tolerance
	local pull = self:host_fires() and aimed and distance < cfg.range

	if pull then
		pull = self:line_of_sight(self:muzzle_position(), player.position, cfg.los_ignore_groups)
	end

	node:fire(pull, self:facing())

	if pull then
		self:transition("fire")
	else
		self:transition("track")
	end
end

return Gun
