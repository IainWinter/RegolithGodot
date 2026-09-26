-- turret: a very large gun. the same idle, track and fire states as gun.lua
-- on a heavier barrel: a slow traverse (a softer spring and a cap on the
-- barrel's spin), a longer reach to match its size and a tighter aim before
-- it fires, since its cannon fires few, slow, heavy shots. the node is an
-- EnemyGun built at the scenario's scale_cells (EnemyTurret.tscn ships
-- the parts at 96 across), its player sensor's radius grows with it.
-- speaks once as "turret" when the player first shows (no Character .tres
-- yet, the registry shows a placeholder under that name)

local M = require("message_types")

local Turret = class("turret", Gun)

Turret.DEFAULTS = {
	range = 30.0,
	muzzle = 1.2,
	aim_tolerance = 0.06,
	align_torque = 6.0,
	align_damping = 4.0,
	-- rad/s, the slow traverse
	max_turn_rate = 0.6,
	greeting = "Contact. Traversing to bearing.",
}

-- the gun's numbers under the turret's own
function Turret:defaults()
	local merged = {}

	for k, v in pairs(Gun.DEFAULTS) do
		merged[k] = v
	end

	for k, v in pairs(Turret.DEFAULTS) do
		merged[k] = v
	end

	return merged
end

function Turret:init()
	Gun.init(self)
	self.greeted = false
end

function Turret:on_message(msg)
	Gun.on_message(self, msg)

	if msg.kind == M.PLAYER_SEEN and not self.greeted then
		self.greeted = true

		if self.cfg.greeting and self.cfg.greeting ~= "" then
			self:say(self.cfg.greeting)
		end
	end
end

return Turret
