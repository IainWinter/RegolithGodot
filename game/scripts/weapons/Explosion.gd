extends RefCounted
class_name Explosion

# what a missile or force bullet does when it goes off: the cells around the
# struck cell burn and shrapnel bullets fly off in every direction. also the
# one place a weapon hit lands on a cell

static func hit_cell(world: RegolithWorld, props: WeaponProps, sprite: RegolithSprite, cell: Vector2i, particle_velocity: Vector2, spawn_particle := true) -> Vector2:
	var position := sprite.cell_to_world(cell)
	var damage_ratio: float = props.damage_ratio if sprite.get_cell_class(cell) > 0 else 0.0
	if spawn_particle:
		world.spawn_cell_particle(position, particle_velocity, sprite.get_cell_color(cell), sprite.global_rotation)
	sprite.burn_fracture(cell, props.burn_strength, props.scorch_strength, damage_ratio, props.damage)
	return position

static func blast_rays(sprite: RegolithSprite, center: Vector2, radius: float, rays: int, cells_per_ray: int, first_removes: bool, burn_strength := 255, scorch_strength := 110, damage_ratio := 0.65, damage := 2) -> bool:
	var hit_any := false

	for i in rays:
		var direction := Vector2.from_angle(TAU * i / rays)
		var first := first_removes

		for cell in sprite.trace_cells(center, center + direction * radius, cells_per_ray):
			if first:
				sprite.remove_cell(cell)
			else:
				sprite.burn_fracture(cell, burn_strength, scorch_strength, damage_ratio, damage)

			first = false
			hit_any = true

	return hit_any

static func burst(props: HomingWeaponProps, position: Vector2, shooter: RegolithSprite, sprite: RegolithSprite = null, cell := Vector2i(-1, -1)) -> void:
	var world := RegolithWorld.active()
	if world == null:
		return

	if sprite and cell.x >= 0:
		var radius := roundi(props.explosion_radius * RegolithWorld.CELLS_PER_CHUNK)
		var pixels_per_unit := RegolithWorld.pixels_per_unit()

		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if x * x + y * y > radius * radius:
					continue

				var c := cell + Vector2i(x, y)
				if not sprite.has_cell(c):
					continue

				hit_cell(world, props, sprite, c, Vector2.from_angle(randf() * TAU) * randf_range(1.0, 4.0) * pixels_per_unit)

	spawn_shrapnel(props.shrapnel, props.shrapnel_count, position, shooter)
	spawn_shrapnel(props.shrapnel_long, props.shrapnel_long_count, position, shooter)

static func spawn_shrapnel(shrapnel: WeaponProps, count: int, position: Vector2, shooter: RegolithSprite) -> void:
	if shrapnel == null or shrapnel.projectile_scene == null:
		return

	var parent := Weapon.projectile_parent()
	if parent == null:
		return

	for i in range(count):
		var bullet: Node2D = shrapnel.projectile_scene.instantiate()
		bullet.setup(shrapnel, position, Vector2.from_angle(randf() * TAU), Vector2.ZERO, shooter)
		parent.add_child(bullet)
