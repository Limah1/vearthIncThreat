extends Area2D
class_name Barrier

const DamageSystemScript = preload("res://src/core/damage_system.gd")

signal health_changed(current_hp: float, maximum_hp: float)
signal deployment_changed(world_position: Vector2)

const DEFAULT_CONFIG_PATH: String = "res://src/resources/barriers/BarrierConfig.tres"
const MAX_TURRETS: int = 3
const TURRET_GAP: float = 2.0
const MAX_TURRET_RADIUS: float = 7.0
const PLAYFIELD_Y: float = 0.0

@export var barrier_config: BarrierConfig
@export var visual_3d_scene: PackedScene
@export var turret_scene: PackedScene

var max_hp: float = 10.0
var hp: float = 10.0
var active: bool = false
var unlocked: bool = false
var placed: bool = true
var previewing: bool = false
## 3D height shared by planet, spawn actors, and barrier placement plane.
var world_plane_y: float = PLAYFIELD_Y
var visual_3d: Node3D = null
var life_bar: Node3D = null
var life_bar_fill: MeshInstance3D = null
var life_bar_width: float = 42.0
var turrets: Array[Node3D] = []

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("barrier")
	GameManager.register_barrier(self)
	if not barrier_config:
		var default_resource: Resource = load(DEFAULT_CONFIG_PATH)
		if default_resource is BarrierConfig:
			barrier_config = default_resource as BarrierConfig

	_apply_config()
	# Barriers are authored directly in each AllyShips level scene. Turret unlock
	# controls preparation mode; barrier visibility is no longer upgrade-gated.
	_set_unlocked(true)
	call_deferred("_add_visual_to_scene")

func _exit_tree() -> void:
	if is_instance_valid(GameManager):
		GameManager.unregister_barrier(self)

func _apply_config() -> void:
	if not barrier_config:
		return

	max_hp = maxf(barrier_config.max_hp, 1.0)
	hp = max_hp

	if collision_shape:
		var rectangle := collision_shape.shape as RectangleShape2D
		if not rectangle:
			rectangle = RectangleShape2D.new()
			collision_shape.shape = rectangle
		rectangle.size = barrier_config.size

func _add_visual_to_scene() -> void:
	if visual_3d or not visual_3d_scene:
		return
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	visual_3d = visual_3d_scene.instantiate() as Node3D
	if not visual_3d:
		return
	current_scene.add_child(visual_3d)
	visual_3d.name = "BarrierVisual"
	life_bar = visual_3d.find_child("LifeBar", true, false) as Node3D
	life_bar_fill = visual_3d.find_child("LifeBarFill", true, false) as MeshInstance3D
	_apply_visual_config()
	_sync_visual_transform()
	visual_3d.visible = unlocked and (placed or previewing)
	_apply_preview_visual()

func _apply_visual_config() -> void:
	if not visual_3d or not barrier_config:
		return
	var mesh_instance := visual_3d.find_child("BarrierMesh", true, false) as MeshInstance3D
	if mesh_instance and mesh_instance.mesh is BoxMesh:
		var box_mesh := mesh_instance.mesh as BoxMesh
		box_mesh.size = Vector3(barrier_config.size.x, barrier_config.depth, barrier_config.size.y)

	if life_bar:
		life_bar.position = Vector3(0.0, barrier_config.depth * 0.5 + 4.0, -barrier_config.size.y * 0.5 - 8.0)
	var background := visual_3d.find_child("LifeBarBackground", true, false) as MeshInstance3D
	if background and background.mesh is BoxMesh:
		var background_mesh := background.mesh as BoxMesh
		life_bar_width = minf(barrier_config.size.x - 6.0, 80.0)
		background_mesh.size = Vector3(life_bar_width + 2.0, 1.0, 5.0)
	if life_bar_fill and life_bar_fill.mesh is BoxMesh:
		var fill_mesh := life_bar_fill.mesh as BoxMesh
		fill_mesh.size = Vector3(life_bar_width, 1.2, 3.0)
	_sync_life_bar()

func _sync_visual_transform() -> void:
	if visual_3d:
		# Gameplay uses XZ plane: 2D X/Y maps to 3D X/Z.
		visual_3d.global_position = Vector3(global_position.x, world_plane_y, global_position.y)
	_sync_turret_transforms()

func set_deployment_position(world_position: Vector2) -> void:
	set_deployment_world_position(Vector3(world_position.x, world_plane_y, world_position.y))

func set_deployment_world_position(world_position: Vector3) -> void:
	if not unlocked:
		return
	world_plane_y = world_position.y
	global_position = Vector2(world_position.x, world_position.z)
	_sync_visual_transform()
	GameManager.update_avoidance_obstacle(self)
	deployment_changed.emit(global_position)

func set_placed(value: bool) -> void:
	if value and not placed:
		hp = max_hp
	placed = value
	if placed:
		previewing = false
	_sync_placement_state()

func set_preview(value: bool) -> void:
	previewing = value
	_sync_placement_state()
	_apply_preview_visual()

func _sync_placement_state() -> void:
	active = unlocked and placed and not previewing
	if collision_shape:
		collision_shape.disabled = not active
	if visual_3d:
		visual_3d.visible = unlocked and (placed or previewing)
	for turret in turrets:
		if is_instance_valid(turret) and turret.has_method("set_deployment_active"):
			turret.set_deployment_active(active)
	if is_inside_tree():
		GameManager.update_avoidance_obstacle(self)

func _apply_preview_visual() -> void:
	if not visual_3d:
		return
	var mesh_instance := visual_3d.find_child("BarrierMesh", true, false) as MeshInstance3D
	if not mesh_instance:
		return
	if previewing:
		var base_material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if base_material:
			var ghost_material := base_material.duplicate() as StandardMaterial3D
			ghost_material.albedo_color = Color(0.45, 0.48, 0.52, 0.55)
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_material.no_depth_test = true
			mesh_instance.material_override = ghost_material
	else:
		mesh_instance.material_override = null

func contains_world_point(world_point: Vector2, padding: float = 0.0) -> bool:
	if not barrier_config:
		return false
	var local_point := world_point - global_position
	var half_size := barrier_config.size * 0.5
	return absf(local_point.x) <= half_size.x + padding and absf(local_point.y) <= half_size.y + padding

## Radius is calculated from the current barrier width so three footprints fit
## side-by-side with a small gap. For the current 50x80 barrier this is 7 units.
func get_turret_radius() -> float:
	if not barrier_config:
		return MAX_TURRET_RADIUS
	var width_limit := (barrier_config.size.x - TURRET_GAP * 2.0) / 6.0
	var height_limit := (barrier_config.size.y - TURRET_GAP * 2.0) / 6.0
	return maxf(2.0, minf(MAX_TURRET_RADIUS, minf(width_limit, height_limit)))

func get_turret_height() -> float:
	if not barrier_config:
		return world_plane_y + 4.5
	# Barrier mesh is centered on Y; place the 3-unit turret prism flush on its top face.
	return world_plane_y + barrier_config.depth * 0.5 + 1.5

func add_turret_at(world_position: Vector2) -> Node3D:
	if not active or not turret_scene or turrets.size() >= MAX_TURRETS:
		return null
	var turret := turret_scene.instantiate() as Node3D
	if not turret:
		return null
	var current_scene := get_tree().current_scene
	if not current_scene:
		turret.queue_free()
		return null
	current_scene.add_child(turret)
	if not attach_turret(turret, world_position):
		turret.queue_free()
		return null
	return turret

func attach_turret(turret: Node3D, world_position: Vector2) -> bool:
	if not active or not is_instance_valid(turret) or turrets.size() >= MAX_TURRETS:
		return false
	if not contains_world_point(world_position):
		return false

	var local_point := world_position - global_position
	var half_size := barrier_config.size * 0.5
	var radius := get_turret_radius()
	local_point.x = clampf(local_point.x, -half_size.x + radius, half_size.x - radius)
	local_point.y = clampf(local_point.y, -half_size.y + radius, half_size.y - radius)
	var placement := global_position + local_point
	if not _can_place_turret_at(placement):
		return false

	if not turret.get_parent():
		var current_scene := get_tree().current_scene
		if not current_scene:
			return false
		current_scene.add_child(turret)
	turrets.append(turret)
	if turret.has_method("assign_to_barrier"):
		turret.assign_to_barrier(self, local_point, radius)
	if turret.has_method("set_preview"):
		turret.set_preview(false)
	_sync_turret_transforms()
	return true

func move_turret_to(turret: Node3D, world_position: Vector2) -> bool:
	if not turrets.has(turret) or not contains_world_point(world_position):
		return false
	var local_point := world_position - global_position
	var half_size := barrier_config.size * 0.5
	var radius := get_turret_radius()
	local_point.x = clampf(local_point.x, -half_size.x + radius, half_size.x - radius)
	local_point.y = clampf(local_point.y, -half_size.y + radius, half_size.y - radius)
	var placement := global_position + local_point
	if not _can_place_turret_at(placement, turret):
		return false
	if turret.has_method("set_barrier_offset"):
		turret.set_barrier_offset(local_point)
	else:
		turret.global_position = Vector3(placement.x, get_turret_height(), placement.y)
	return true

func remove_turret(turret: Node3D) -> void:
	if not turrets.has(turret):
		return
	turrets.erase(turret)
	if is_instance_valid(turret):
		turret.queue_free()

func clear_turrets() -> void:
	for turret in turrets:
		if is_instance_valid(turret):
			turret.queue_free()
	turrets.clear()

func _can_place_turret_at(world_position: Vector2, ignored_turret: Node3D = null) -> bool:
	if not contains_world_point(world_position, -get_turret_radius()):
		return false
	var minimum_distance := get_turret_radius() * 2.0 + TURRET_GAP
	for turret in turrets:
		if turret == ignored_turret or not is_instance_valid(turret):
			continue
		var turret_position := Vector2(turret.global_position.x, turret.global_position.z)
		if world_position.distance_to(turret_position) < minimum_distance:
			return false
	return true

func _sync_turret_transforms() -> void:
	for turret in turrets:
		if is_instance_valid(turret) and turret.has_method("sync_from_barrier"):
			turret.sync_from_barrier()

func _set_unlocked(value: bool) -> void:
	unlocked = value
	if unlocked:
		hp = max_hp
	_sync_placement_state()
	_sync_life_bar()
	health_changed.emit(hp, max_hp)

func _sync_life_bar() -> void:
	if not life_bar_fill:
		return
	var ratio := clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	life_bar_fill.scale.x = ratio
	life_bar_fill.position.x = -life_bar_width * 0.5 * (1.0 - ratio)

func receive_damage(amount: float, source_team: int) -> bool:
	if source_team != DamageSystemScript.Team.ENEMY:
		return false
	_apply_damage(amount)
	return true

func take_damage(amount: float) -> void:
	# Compatibility for older enemy sources.
	receive_damage(amount, DamageSystemScript.Team.ENEMY)

func _apply_damage(amount: float) -> void:
	if not active or amount <= 0.0:
		return

	hp = maxf(hp - amount, 0.0)
	_sync_life_bar()
	health_changed.emit(hp, max_hp)
	GameManager.spawn_popup_3d("-" + str(int(round(amount))), Color(0.45, 0.85, 1.0), get_world_position())

	if hp <= 0.0:
		active = false
		GameManager.update_avoidance_obstacle(self)
		if collision_shape:
			collision_shape.disabled = true
		if visual_3d:
			visual_3d.visible = false
		for turret in turrets:
			if is_instance_valid(turret) and turret.has_method("set_deployment_active"):
				turret.set_deployment_active(false)

func contains_collision(hit_position: Vector3, impact_radius: float = 0.0) -> bool:
	if not active or not barrier_config:
		return false

	var point := Vector2(hit_position.x, hit_position.z)
	var half_size := barrier_config.size * 0.5
	var center := global_position
	var closest := Vector2(
		clampf(point.x, center.x - half_size.x, center.x + half_size.x),
		clampf(point.y, center.y - half_size.y, center.y + half_size.y)
	)
	if point.distance_squared_to(closest) > impact_radius * impact_radius:
		return false
	return true

func try_handle_collision(
	hit_position: Vector3,
	damage: float,
	impact_radius: float = 0.0,
	damage_team: int = DamageSystemScript.Team.ENEMY
) -> bool:
	if not contains_collision(hit_position, impact_radius):
		return false
	DamageSystemScript.apply(self, damage, damage_team)
	return true

func get_world_position() -> Vector3:
	return Vector3(global_position.x, world_plane_y, global_position.y)

func is_avoidance_active() -> bool:
	return active

func get_avoidance_center() -> Vector2:
	return global_position

func get_avoidance_radius() -> float:
	if not barrier_config:
		return 0.0
	# Circular broadphase volume encloses the full 50x80 rectangle. Asteroids
	# therefore avoid its corners as well as its center.
	return barrier_config.size.length() * 0.5
