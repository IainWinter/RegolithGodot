-- runs once when the Ai runtime starts, before any class loads. gives
-- scripts the vec2 metatable, the Ai base class, class() and the ai table
-- that wraps the runtime node. everything a script sees comes from here or
-- from its own node

-- vec2: the shape Vector2 crosses over as, {x, y} with this metatable

local V = getmetatable(vec2())
V.__index = V

function V.__add(a, b) return vec2(a.x + b.x, a.y + b.y) end
function V.__sub(a, b) return vec2(a.x - b.x, a.y - b.y) end
function V.__unm(a) return vec2(-a.x, -a.y) end
function V.__eq(a, b) return a.x == b.x and a.y == b.y end
function V.__tostring(a) return string.format("(%.3f, %.3f)", a.x, a.y) end

function V.__mul(a, b)
	if type(a) == "number" then return vec2(a * b.x, a * b.y) end
	if type(b) == "number" then return vec2(a.x * b, a.y * b) end
	return vec2(a.x * b.x, a.y * b.y)
end

function V.__div(a, b)
	if type(b) == "number" then return vec2(a.x / b, a.y / b) end
	return vec2(a.x / b.x, a.y / b.y)
end

function V:length() return math.sqrt(self.x * self.x + self.y * self.y) end
function V:length_squared() return self.x * self.x + self.y * self.y end
function V:dot(o) return self.x * o.x + self.y * o.y end
function V:cross(o) return self.x * o.y - self.y * o.x end
function V:distance_to(o) return (o - self):length() end
function V:distance_squared_to(o) return (o - self):length_squared() end
function V:angle() return math.atan(self.y, self.x) end
function V:angle_to(o) return math.atan(self:cross(o), self:dot(o)) end
function V:lerp(o, t) return vec2(self.x + (o.x - self.x) * t, self.y + (o.y - self.y) * t) end

function V:normalized()
	local l = self:length()
	if l > 0 then return vec2(self.x / l, self.y / l) end
	return vec2(0, 0)
end

function V:rotated(a)
	local c, s = math.cos(a), math.sin(a)
	return vec2(self.x * c - self.y * s, self.x * s + self.y * c)
end

function V:limit_length(max)
	local l = self:length()
	if l > max and l > 0 then return self * (max / l) end
	return vec2(self.x, self.y)
end

function from_angle(a) return vec2(math.cos(a), math.sin(a)) end

-- modules: the runtime loads the res://game/lua files named in its MODULES
-- into __modules before any class, require(name) hands the table back. the
-- sandbox has no file loading of its own, this is the only require

__modules = {}

function require(name)
	local module = __modules[name]

	if module == nil then
		error(("no module '%s', the runtime loads modules from AiRuntime.MODULES"):format(tostring(name)), 2)
	end

	return module
end

-- the runtime: messages and lookups. __runtime is the Ai autoload node

ai = {}

function ai.valid(o) return o ~= nil and o.valid == true end

-- the script instance behind another scripted node, nil when it has none
function ai.instance(node)
	if not ai.valid(node) then return nil end
	local id = node.ai_id
	if id and id > 0 then return __instance(id) end
	return nil
end

function ai.send(sender, target, payload) return __runtime:send(sender, target, payload) end
function ai.send_instant(sender, target, payload) return __runtime:send_instant(sender, target, payload) end
function ai.broadcast(sender, radius, payload) return __runtime:broadcast(sender, radius, payload) end
function ai.broadcast_instant(sender, radius, payload) return __runtime:broadcast_instant(sender, radius, payload) end

-- the world through the runtime: spawning and queries, all generic. sender
-- is the node asking, positions are sim units. ai.spawn answers later with
-- a SPAWNED or SPAWN_EXPIRED message to the sender (message_types)
function ai.spawn(sender, kind, position, velocity, offscreen_only, lifetime, tag)
	return __runtime:spawn(sender, kind, position, velocity or vec2(0, 0), offscreen_only or false, lifetime or 10, tag or "")
end

-- a rock made from a RockProps resource, answered like ai.spawn
function ai.spawn_rock(sender, props, position, velocity, offscreen_only, lifetime, tag)
	return __runtime:spawn_rock(sender, props, position, velocity or vec2(0, 0), offscreen_only or false, lifetime or 10, tag or "")
end

-- the camera: half extents and center in units, the design height
function ai.camera_half_extents(node) return __runtime:camera_half_extents(node) end
function ai.camera_center(node, fallback) return __runtime:camera_center(node, fallback) end
function ai.camera_size() return __runtime:camera_size() end

-- the warning line telegraph between two points in units
function ai.warn(from, to, seconds) return __runtime:warn(from, to, seconds or 2) end

-- a RegolithSprite cell type constant by name, CELL_WEAKPOINT1 and the like
function ai.cell_type(name) return __runtime:cell_type(name) end

-- random points: in a box of half extents around center turned by angle,
-- and in a disc
function ai.random_in_box(center, half, angle)
	local local_point = vec2(ai.random(-half.x, half.x), ai.random(-half.y, half.y))
	return center + local_point:rotated(angle or 0)
end

function ai.random_in_circle(radius)
	return from_angle(math.random() * 2 * math.pi) * (math.random() * radius)
end

function ai.sprites_near(sender, radius) return __runtime:sprites_near(sender, radius) end
function ai.group(name) return __runtime:group(name) end
function ai.line_of_sight(sender, from, to, ignore_groups) return __runtime:line_of_sight(sender, from, to, ignore_groups or {}) end
function ai.ray_cast(sender, from, to, ignore_groups) return __runtime:ray_cast(sender, from, to, ignore_groups or {}) end
function ai.jointed(node) return __runtime:jointed(node) end

-- a voice line from the node's character, the Dialog autoload shows it
function ai.say(node, text, duration) return __runtime:say(node, text, duration or -1) end

-- a stable key for a node in a lua table, userdata wrappers are not
function ai.id(node)
	if not ai.valid(node) then return nil end
	return node:get_instance_id()
end

function ai.random(lo, hi) return lo + math.random() * (hi - lo) end
function ai.clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
function ai.wrap_angle(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- Ai: the base every class extends. self.node is the godot node, self.id
-- the instance id. override init, on_message(msg) and update(dt); update
-- runs before the current state's update each tick

Ai = {}
Ai.__index = Ai

function Ai:init() end
function Ai:update(dt) end
function Ai:on_message(msg) end

function Ai:send(target, payload) return ai.send(self.node, target, payload) end
function Ai:send_instant(target, payload) return ai.send_instant(self.node, target, payload) end
function Ai:broadcast(radius, payload) return ai.broadcast(self.node, radius, payload) end
function Ai:broadcast_instant(radius, payload) return ai.broadcast_instant(self.node, radius, payload) end

function Ai:pos() return self.node.pos end

function Ai:spawn(kind, position, velocity, offscreen_only, lifetime, tag)
	return ai.spawn(self.node, kind, position, velocity, offscreen_only, lifetime, tag)
end

function Ai:spawn_rock(props, position, velocity, offscreen_only, lifetime, tag)
	return ai.spawn_rock(self.node, props, position, velocity, offscreen_only, lifetime, tag)
end

function Ai:camera_half_extents() return ai.camera_half_extents(self.node) end
function Ai:camera_center(fallback) return ai.camera_center(self.node, fallback) end

function Ai:sprites_near(radius) return ai.sprites_near(self.node, radius) end
function Ai:line_of_sight(from, to, ignore_groups) return ai.line_of_sight(self.node, from, to, ignore_groups) end
function Ai:ray_cast(from, to, ignore_groups) return ai.ray_cast(self.node, from, to, ignore_groups) end
function Ai:jointed() return ai.jointed(self.node) end
function Ai:say(text, duration) return ai.say(self.node, text, duration) end

-- tunables: the class's defaults under the node's ai_config dictionary
-- (EnemyScripted export, so a scene or a test can override a number
-- without touching the script). kept on self.cfg, configure(overrides)
-- changes them on a live instance
function Ai:config(defaults)
	local cfg = {}

	for k, v in pairs(defaults or {}) do
		cfg[k] = v
	end

	local node = self.node
	local overrides = node and node.ai_config

	if type(overrides) == "table" then
		for k, v in pairs(overrides) do
			cfg[k] = v
		end
	end

	self.cfg = cfg
	return cfg
end

function Ai:configure(overrides)
	if type(overrides) ~= "table" then
		return
	end

	self.cfg = self.cfg or {}

	for k, v in pairs(overrides) do
		self.cfg[k] = v
	end
end

-- states. a class registers named states and asks for transitions, the
-- node's AiStateMachine (self.node.state_machine, gdscript) owns the
-- current state, its timing and the transition log and calls back into
-- __state_call each tick. a state is {enter = f, update = f, exit = f},
-- every field optional, each called as f(self, dt) (dt is 0 for enter and
-- exit). a field may also be the name of a method on the class, which
-- survives a hot reload where a captured function would not.
-- self:transition(name) from inside a state function applies after it
-- returns, see AiStateMachine.gd

function Ai:machine()
	local node = self.node
	return node and node.state_machine or nil
end

function Ai:register_state(name, def)
	if type(name) ~= "string" or name == "" then
		error("register_state: the name must be a string", 2)
	end

	if type(def) ~= "table" then
		error(("register_state '%s': pass a table with enter, update and exit"):format(name), 2)
	end

	self.__states = self.__states or {}
	self.__states[name] = def

	local machine = self:machine()

	if machine then
		machine:register_state(name)
	end

	return def
end

function Ai:transition(name)
	local machine = self:machine()

	if machine == nil then
		error(("transition '%s': the node has no state machine"):format(tostring(name)), 2)
	end

	if not machine:transition(name) then
		error(("transition to unregistered state '%s' on %s"):format(tostring(name), tostring(self.__name)), 2)
	end
end

function Ai:state()
	local machine = self:machine()
	return machine and machine:get_state() or ""
end

function Ai:previous_state()
	local machine = self:machine()
	return machine and machine:get_previous_state() or ""
end

function Ai:time_in_state()
	local machine = self:machine()
	return machine and machine:get_time_in_state() or 0
end

-- the machine's entry: one phase of one state. true on success, else the
-- error names the state and phase, is kept for __take_state_error and
-- raised so the runtime reports it
local function state_fail(self, message)
	self.__state_error = message
	error(message, 0)
end

function Ai:__state_call(phase, name, dt)
	local states = self.__states
	local def = states and states[name]

	if def == nil then
		state_fail(self, ("state '%s' is not registered on %s"):format(tostring(name), tostring(self.__name)))
	end

	local fn = def[phase]

	if type(fn) == "string" then
		local method = self[fn]

		if type(method) ~= "function" then
			state_fail(self, ("state '%s' %s: no method '%s' on %s"):format(name, phase, fn, tostring(self.__name)))
		end

		fn = method
	end

	if fn == nil then
		return true
	end

	local ok, err = pcall(fn, self, dt)

	if not ok then
		state_fail(self, ("state '%s' %s: %s"):format(name, phase, tostring(err)))
	end

	return true
end

function Ai:__take_state_error()
	local message = self.__state_error
	self.__state_error = nil
	return message
end

function class(name, base)
	local c = setmetatable({}, { __index = base or Ai })
	c.__index = c
	c.__name = name
	return c
end
