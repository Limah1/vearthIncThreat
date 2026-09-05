extends Node3D
class_name GridDefenseBlock

const DamageSystemScript = preload("res://src/core/damage_system.gd")

signal health_changed(current_hp: float, maximum_hp: float)
signal destroyed(block: GridDefenseBlock)

@export var maximum_hp: float = 200.0
@export var block_size: Vector2 = Vector2(90.0, 90.0)
@export var block_height: float = 18.0

var hp: float = 200.0
var placed: bool = true
var previewing: bool = false
var active: bool = false
var world_yaw: float = 0.0

@onready var block_mesh: MeshInstance3D = $BlockMesh
@onready var life_bar: Node3D = $LifeBar
@onready var life_bar_fill: MeshInstance3D = $LifeBar/LifeBarFill

func _ready() -> void:
	add_to_group("barrier")
	add_to_group("grid_defense_block")
	hp = maximum_hp
	_apply_dimensions()
	GameManager.register_barrier(self)
	_sync_state()

func _exit_tree() -> void:
	if is_instance_valid(GameManager):
		GameManager.unregister_barrier(self)

func set_deployment_world_transform(world_position: Vector3, yaw: float) -> void:
	global_position = world_position
	world_yaw = wrapf(yaw, -PI, PI)
	rotation.y = world_yaw
	GameManager.update_avoidance_obstacle(self)

func set_placed(value: bool) -> void:
	placed = value
	if placed:
		hp = maximum_hp
		previewing = false
	_sync_state()

func set_preview(value: bool) -> void:
	previewing = value
	_sync_state()
	_apply_preview_material()

func contains_world_point(world_point: Vector2) -> bool:
	var local_point: Vector3 = to_local(Vector3(world_point.x, global_position.y, world_point.y))
	return absf(local_point.x) <= block_size.x * 0.5 and absf(local_point.z) <= block_size.y * 0.5

func contains_collision(hit_position: Vector3, impact_radius: float = 0.0) -> bool:
	if not active:
		return false
	var local_hit: Vector3 = to_local(hit_position)
	var point := Vector2(local_hit.x, local_hit.z)
	var half_size: Vector2 = block_size * 0.5
	var closest := Vector2(
		clampf(point.x, -half_size.x, half_size.x),
		clampf(point.y, -half_size.y, half_size.y)
	)
	return point.distance_squared_to(closest) <= impact_radius * impact_radius

func receive_damage(amount: float, source_team: int) -> bool:
	if source_team != DamageSystemScript.Team.ENEMY or not active or amount <= 0.0:
		return false
	hp = maxf(hp - amount, 0.0)
	_sync_life_bar()
	health_changed.emit(hp, maximum_hp)
	GameManager.spawn_popup_3d("-" + str(int(round(amount))), Color(0.72, 0.46, 0.25), global_position)
	if hp <= 0.0:
		active = false
		GameManager.update_avoidance_obstacle(self)
		destroyed.emit(self)
		queue_free()
	return true

func take_damage(amount: float) -> void:
	receive_damage(amount, DamageSystemScript.Team.ENEMY)

func is_avoidance_active() -> bool:
	return active

func get_avoidance_center() -> Vector2:
	return Vector2(global_position.x, global_position.z)

func get_avoidance_radius() -> float:
	return block_size.length() * 0.5

func _apply_dimensions() -> void:
	if block_mesh.mesh is BoxMesh:
		var mesh := block_mesh.mesh as BoxMesh
		mesh.size = Vector3(block_size.x, block_height, block_size.y)
	life_bar.position = Vector3(0.0, block_height * 0.5 + 5.0, -block_size.y * 0.5 - 7.0)
	_sync_life_bar()

func _sync_state() -> void:
	active = placed and not previewing and hp > 0.0
	visible = placed or previewing
	GameManager.update_avoidance_obstacle(self)

func _sync_life_bar() -> void:
	if not is_instance_valid(life_bar_fill):
		return
	var ratio: float = clampf(hp / maximum_hp, 0.0, 1.0) if maximum_hp > 0.0 else 0.0
	life_bar_fill.scale.x = ratio
	life_bar_fill.position.x = -38.0 * 0.5 * (1.0 - ratio)

func _apply_preview_material() -> void:
	if not is_instance_valid(block_mesh):
		return
	if previewing:
		var base_material := block_mesh.get_active_material(0) as StandardMaterial3D
		if base_material:
			var preview_material := base_material.duplicate() as StandardMaterial3D
			preview_material.albedo_color.a = 0.5
			preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			preview_material.no_depth_test = true
			block_mesh.material_override = preview_material
	else:
		block_mesh.material_override = null
