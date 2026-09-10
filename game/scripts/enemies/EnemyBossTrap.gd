@tool
class_name EnemyBossTrap
extends Node

# AiPlayerTrap: a box the host sets each step, on its hull or out in the
# world. a player outside it is grabbed and hauled toward the push point
# with a pull that grows every second, until it gets there and takes a burn,
# or it snags on something and the trap lets go for a while. lightning runs
# along the pull and zaps the box edges. the host calls update each physics
# step. the hull box is in the original's -1..1 local space, sim units
# otherwise

@export var active := true
@export var lightning_props: LightningProps
@export var lightning_material: Material
@export var trap_position := Vector2(0.0, -0.95)
@export var trap_scale := Vector2(1.0, 1.0)
@export var trap_angle := 0.0
@export var push_point := Vector2(0.0, -0.55)
@export var pull_strength := 30.0
@export var pull_strength_exp_rate := 1.0
@export var margin := 1.0
@export var release_speed := 1.0
@export var regrab_cooldown := 1.5
@export var boundary_margin := 1.5
@export var boundary_span := 1.0
@export var beam_interval := 0.02
@export var boundary_interval := 0.01
@export var delay := 0.1
@export var hit_grace := 0.3
@export var damage_rays := 8
@export var damage_cells := 2

var lightning: Lightning
var pull_target: RegolithSprite
var pull_exp := 1.0
var cooldown := 0.0
var beam_timer := 0.0
var boundary_timer := 0.0
var delay_timer := 0.0
var grace_timer := 0.0

var center := Vector2.ZERO
var half := Vector2.ONE
var angle := 0.0
var push := Vector2.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if lightning_props == null:
		return

	lightning = Lightning.new()
	lightning.props = lightning_props
	lightning.material = lightning_material
	lightning.auto_free = false
	add_child(lightning)

func set_box(box_center: Vector2, half_size: Vector2, box_angle: float) -> void:
	center = box_center
	half = half_size
	angle = box_angle
	push = box_center

func set_hull_box(host: Enemy) -> void:
	center = host.local_point_units(trap_position)
	half = trap_scale * Steering.half_extent_units(host)
	angle = host.global_rotation - trap_angle
	push = host.local_point_units(push_point)

func update(host: Enemy, delta: float) -> void:
	if not active:
		if pull_target:
			release(false)
		return

	var player := host.player

	if player == null:
		return

	var player_pos := host.player_pos

	boundary_timer += delta

	if boundary_timer >= boundary_interval:
		boundary_timer = 0.0
		spawn_boundary_lightning(host, player_pos)

	if pull_target and (not is_instance_valid(pull_target) or pull_target.is_queued_for_deletion()):
		release(false)

	if pull_target == null and cooldown > 0.0:
		cooldown -= delta
		return

	if pull_target == null:
		var local := to_trap_local(player_pos)

		if absf(local.x) > 1.0 or absf(local.y) > 1.0:
			pull_target = player
			pull_exp = 1.0
			beam_timer = 0.0
			delay_timer = 0.0
			grace_timer = 0.0

	if pull_target == null:
		return

	var diff := push - player_pos
	var length := diff.length()
	var direction := diff / length if length > 0.0 else Vector2.ZERO

	if length < margin:
		damage_player(player)
		release(false)
		return

	beam_timer += delta

	if beam_timer >= beam_interval and lightning:
		beam_timer = 0.0
		lightning.strike(host.global_position, player, host)

	delay_timer += delta

	if delay_timer < delay:
		return

	grace_timer += delta

	if grace_timer >= hit_grace and player.linear_velocity.dot(direction) < release_speed:
		release(true)
		return

	if length < 0.01:
		return

	pull_exp *= 1.0 + pull_strength_exp_rate * delta
	player.apply_impulse(direction * pull_strength * pull_exp * delta, player.global_position)

func release(hit: bool) -> void:
	pull_target = null

	if hit:
		cooldown = regrab_cooldown

func to_trap_local(point: Vector2) -> Vector2:
	var local := (point - center).rotated(-angle)
	return Vector2(local.x / maxf(half.x, 0.0001), local.y / maxf(half.y, 0.0001))

func to_trap_world(local: Vector2) -> Vector2:
	return center + (local * half).rotated(angle)

# the box corners in world units, grown by grow units on each side
func box_corners(grow := 0.0) -> PackedVector2Array:
	var corners := PackedVector2Array()

	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + (corner * (half + Vector2.ONE * grow)).rotated(angle))

	return corners

func draw_gizmos(g: RegolithGizmos) -> void:
	if Engine.is_editor_hint():
		return

	var host := get_parent() as Enemy
	if host == null:
		return

	var color := Color(0.95, 0.35, 0.35)
	var name := RegolithDebugDraw.AI_TRAP
	var ppu := Steering.ppu()
	# box corners/push live in world sim units; the walker sets g.transform
	# to the host's global_transform, so we un-transform to host-local pixels
	# and let the framework put them back where they were
	var to_local := host.global_transform.affine_inverse()
	var push_local := to_local * (push * ppu)

	g.polygon(_scaled_corners(0.0, ppu, to_local), color, name)
	g.polygon(_scaled_corners(boundary_margin, ppu, to_local), color, name)
	g.cross(push_local, 0.25 * ppu, color, name)
	g.circle(push_local, margin * ppu, color, name)

	if pull_target and is_instance_valid(pull_target):
		g.line(to_local * pull_target.global_position, push_local, color, name)

func _scaled_corners(grow: float, ppu: float, to_local: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in box_corners(grow):
		out.append(to_local * (corner * ppu))
	return out

func damage_player(player: RegolithSprite) -> void:
	var reach := Steering.sprite_radius_units(player) * Steering.ppu()
	Explosion.blast_rays(player, player.global_position, reach, damage_rays, damage_cells, false, 255, 110, 0.65, 1)

func spawn_boundary_lightning(host: Enemy, player_pos: Vector2) -> void:
	if lightning == null:
		return

	var local := to_trap_local(player_pos)
	var dist_x := 1.0 - absf(local.x)
	var dist_y := 1.0 - absf(local.y)
	var vertical := dist_x < dist_y
	var edge_local := dist_x if vertical else dist_y
	var edge_scale := half.x if vertical else half.y
	var world_dist := absf(edge_local) * edge_scale

	if world_dist > boundary_margin:
		return

	var closeness := clampf(1.0 - world_dist / boundary_margin, 0.0, 1.0)
	closeness *= closeness

	if randf() > closeness:
		return

	var span := randf() * boundary_span
	var a: Vector2
	var b: Vector2

	if vertical:
		var ex := 1.0 if local.x >= 0.0 else -1.0
		var seg := span / maxf(half.y, 0.0001)
		var cy := clampf(local.y, -1.0, 1.0)
		a = Vector2(ex, clampf(cy - seg, -1.0, 1.0))
		b = Vector2(ex, clampf(cy + seg, -1.0, 1.0))
	else:
		var ey := 1.0 if local.y >= 0.0 else -1.0
		var seg := span / maxf(half.x, 0.0001)
		var cx := clampf(local.x, -1.0, 1.0)
		a = Vector2(clampf(cx - seg, -1.0, 1.0), ey)
		b = Vector2(clampf(cx + seg, -1.0, 1.0), ey)

	var wa := to_trap_world(a) * Steering.ppu()
	var wb := to_trap_world(b) * Steering.ppu()

	if randf() < 0.5:
		lightning.strike(wa, wb, host)
	else:
		lightning.strike(wb, wa, host)
