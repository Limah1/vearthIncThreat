extends Node3D
class_name DefenseBlaster

const DEFAULT_CONFIG_PATH := "res://src/resources/turrets/DefaultTurretConfig.tres"

@export var turret_config: TurretConfig
@export var turret_height: float = 4.5
@export var turret_type_id: String = "defense_blaster"
@export var turret_display_name: String = "Defense Blaster"
@export var damage_upgrade_category: String = "TurretDamage"
@export var fire_rate_upgrade_category: String = "TurretAttackSpeed"

var active: bool = false
var previewing: bool = false
var footprint_radius: float = 7.0
var barrier_ref: Barrier = null
var local_offset: Vector2 = Vector2.ZERO
var target: Node = null
var mass_target: int = -1
var cooldown: float = 0.0
var _sat_projectile_master_ref: Node = null
var visual_root: Node3D = null
var aim_pivot: Node3D = null
var muzzle: Node3D = null
var _preview_materials: Dictionary = {}

## Per-instance aiming values selected during preparation.
var center_yaw: float = 0.0
var cone_angle: float = -1.0
var current_aim_yaw: float = 0.0
var sweep_phase: float = 0.0
var target_refresh_timer: float = 0.0
var effective_damage: float = 1.0
var effective_fire_rate: float = 1.0

func _ready() -> void:
	if not turret_type_id.is_empty():
		add_to_group(turret_type_id)
	add_to_group("barrier_turret") # Compatibility with existing debug/tools code.
	if not turret_config:
		var default_resource: Resource = load(DEFAULT_CONFIG_PATH)
		if default_resource is TurretConfig:
			turret_config = default_resource as TurretConfig
	_load_visual_asset()
	if turret_config:
		if cone_angle < 0.0:
			cone_angle = turret_config.get_clamped_cone_angle(turret_config.default_cone_angle)
		target_refresh_timer = (
			float(get_instance_id() % 11) / 11.0
		) * turret_config.target_refresh_interval
	current_aim_yaw = center_yaw
	_sync_aim_visual()
	sweep_phase = float(get_instance_id() % 31) / 31.0 * TAU
	if not UpgradeManager.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_refresh_upgrade_stats()

func _on_upgrade_purchased(_upgrade_id: String, _new_level: int) -> void:
	_refresh_upgrade_stats()

func _refresh_upgrade_stats() -> void:
	if not turret_config:
		effective_damage = 1.0
		effective_fire_rate = 1.0
		return
	effective_damage = turret_config.damage + UpgradeManager.get_total_bonus(damage_upgrade_category)
	effective_fire_rate = turret_config.fire_rate * UpgradeManager.get_multiplier(fire_rate_upgrade_category)

func get_turret_type_id() -> String:
	return turret_type_id

func get_turret_display_name() -> String:
	return turret_display_name


func _load_visual_asset() -> void:
	if turret_config == null or turret_config.visual_asset == null:
		return
	var errors := turret_config.get_visual_validation_errors()
	if not errors.is_empty():
		push_warning("Invalid visual for turret '%s': %s" % [turret_type_id, "; ".join(errors)])
		return
	visual_root = turret_config.visual_asset.instantiate_visual()
	if visual_root == null:
		return
	visual_root.name = "VisualAsset"
	add_child(visual_root)
	aim_pivot = turret_config.visual_asset.resolve_aim_pivot(visual_root)
	muzzle = turret_config.visual_asset.resolve_muzzle(visual_root)


func get_shot_origin() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position + Vector3(0.0, 1.0, 0.0)


func _sync_aim_visual() -> void:
	if is_instance_valid(aim_pivot):
		aim_pivot.rotation.y = current_aim_yaw
		return
	var legacy_mesh := get_node_or_null("TurretMesh") as MeshInstance3D
	if legacy_mesh:
		legacy_mesh.rotation.y = current_aim_yaw

func assign_to_barrier(new_barrier: Barrier, new_local_offset: Vector2, new_radius: float) -> void:
	barrier_ref = new_barrier
	local_offset = new_local_offset
	set_footprint_radius(new_radius)
	previewing = false
	active = true
	cooldown = 0.0
	target = null
	current_aim_yaw = center_yaw
	_sync_aim_visual()
	sync_from_barrier()

func set_aim_configuration(new_center_yaw: float, new_cone_angle: float) -> void:
	center_yaw = wrapf(new_center_yaw, -PI, PI)
	if turret_config:
		cone_angle = turret_config.get_clamped_cone_angle(new_cone_angle)
	else:
		cone_angle = clampf(new_cone_angle, 1.0, 179.0)
	target = null
	target_refresh_timer = 0.0
	current_aim_yaw = center_yaw
	_sync_aim_visual()

func set_aim_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	set_aim_configuration(atan2(direction.x, direction.y), get_cone_angle())

func get_center_yaw() -> float:
	return center_yaw

func get_cone_angle() -> float:
	if cone_angle >= 0.0:
		return cone_angle
	return turret_config.default_cone_angle if turret_config else 90.0

func get_aim_forward_2d() -> Vector2:
	return Vector2(sin(center_yaw), cos(center_yaw))

func get_handle_distance() -> float:
	if not turret_config:
		return 60.0
	return turret_config.get_handle_distance_for_cone_angle(get_cone_angle())

func update_aim_from_handle(world_point: Vector2) -> void:
	if not turret_config:
		return
	var turret_position := Vector2(global_position.x, global_position.z)
	var handle_delta: Vector2 = world_point - turret_position
	if handle_delta.length_squared() <= 0.001:
		return
	var handle_distance: float = clampf(
		handle_delta.length(),
		turret_config.minimum_handle_distance,
		turret_config.maximum_handle_distance
	)
	set_aim_configuration(
		atan2(handle_delta.x, handle_delta.y),
		turret_config.get_cone_angle_for_handle_distance(handle_distance)
	)

func set_footprint_radius(new_radius: float) -> void:
	footprint_radius = maxf(new_radius, 2.0)
	var turret_mesh := get_node_or_null("TurretMesh") as MeshInstance3D
	if turret_mesh and turret_mesh.mesh is CylinderMesh:
		var cylinder := turret_mesh.mesh as CylinderMesh
		cylinder.top_radius = footprint_radius
		cylinder.bottom_radius = footprint_radius

func set_barrier_offset(new_local_offset: Vector2) -> void:
	local_offset = new_local_offset
	sync_from_barrier()

func sync_from_barrier() -> void:
	if not is_instance_valid(barrier_ref):
		return
	var barrier_position: Vector2 = barrier_ref.global_position
	var height: float = turret_height
	if barrier_ref.has_method("get_turret_height"):
		height = float(barrier_ref.get_turret_height())
	var mount_position: Vector2 = barrier_position + local_offset
	if barrier_ref.has_method("get_world_position_for_local_offset"):
		mount_position = barrier_ref.get_world_position_for_local_offset(local_offset)
	global_position = Vector3(mount_position.x, height, mount_position.y)

func set_deployment_active(value: bool) -> void:
	active = value
	visible = value or previewing
	if not active:
		target = null

func set_preview(value: bool) -> void:
	previewing = value
	if previewing:
		active = false
		target = null
		visible = true
	else:
		visible = active
	_apply_preview_visual()

func _apply_preview_visual() -> void:
	if previewing:
		if not _preview_materials.is_empty():
			return
		for mesh in _get_visual_meshes():
			_preview_materials[mesh] = mesh.material_override
			var base_material := mesh.get_active_material(0) as StandardMaterial3D
			if base_material:
				var ghost_material := base_material.duplicate() as StandardMaterial3D
				ghost_material.albedo_color = Color(0.5, 0.5, 0.5, 0.55)
				ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost_material.no_depth_test = true
				mesh.material_override = ghost_material
	else:
		for mesh in _preview_materials:
			if is_instance_valid(mesh):
				mesh.material_override = _preview_materials[mesh]
		_preview_materials.clear()


func _get_visual_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var root: Node = visual_root if is_instance_valid(visual_root) else self
	_collect_visual_meshes(root, result)
	return result


func _collect_visual_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.name != "LaserBeam":
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_visual_meshes(child, result)

func contains_world_point(world_point: Vector2) -> bool:
	var turret_position := Vector2(global_position.x, global_position.z)
	return turret_position.distance_squared_to(world_point) <= footprint_radius * footprint_radius

func _process(delta: float) -> void:
	if not active or not is_instance_valid(barrier_ref) or not turret_config:
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if is_instance_valid(GameManager.mass_combat):
		_process_mass(delta)
		return

	if cooldown > 0.0:
		cooldown -= delta
	target_refresh_timer -= delta
	if not _is_valid_target(target):
		target = null
	if not is_instance_valid(target) and target_refresh_timer <= 0.0:
		target = _find_nearest_enemy()
		target_refresh_timer = turret_config.target_refresh_interval

	sweep_phase = fmod(sweep_phase + delta * turret_config.sweep_speed * TAU, TAU)
	var desired_aim_yaw: float
	if is_instance_valid(target):
		var target_position: Vector3 = target.get("global_position")
		var target_direction := Vector2(
			target_position.x - global_position.x,
			target_position.z - global_position.z
		)
		desired_aim_yaw = atan2(target_direction.x, target_direction.y)
	else:
		var half_cone_radians: float = deg_to_rad(get_cone_angle() * 0.5)
		desired_aim_yaw = center_yaw + sin(sweep_phase) * half_cone_radians
	current_aim_yaw = lerp_angle(
		current_aim_yaw,
		desired_aim_yaw,
		clampf(delta * turret_config.tracking_speed, 0.0, 1.0)
	)
	_sync_aim_visual()

	if is_instance_valid(target) and cooldown <= 0.0:
		_fire_at_target()
		cooldown = 1.0 / maxf(effective_fire_rate, 0.05)

func _find_nearest_enemy() -> Node:
	var nearest: Node = null
	if not turret_config:
		return nearest
	var nearest_distance_sq: float = turret_config.attack_range * turret_config.attack_range
	var candidates: Array = GameManager.get_nearby_entities(global_position, turret_config.attack_range)
	for candidate in candidates:
		if not _is_hostile_candidate(candidate):
			continue
		if not bool(candidate.get("active")):
			continue
		var candidate_position: Vector3 = candidate.get("global_position")
		if not is_world_position_in_action_cone(candidate_position):
			continue
		var distance_sq: float = global_position.distance_squared_to(candidate_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest

func _is_valid_target(candidate: Node) -> bool:
	if not _is_hostile_candidate(candidate):
		return false
	if not bool(candidate.get("active")):
		return false
	var candidate_position: Vector3 = candidate.get("global_position")
	return is_world_position_in_action_cone(candidate_position)

func _is_hostile_candidate(candidate: Node) -> bool:
	return is_instance_valid(candidate) and candidate.is_in_group("enemy")

func is_world_position_in_action_cone(world_position: Vector3) -> bool:
	if not turret_config:
		return false
	var to_target := Vector2(
		world_position.x - global_position.x,
		world_position.z - global_position.z
	)
	return turret_config.contains_offset_in_action_cone(
		to_target,
		get_aim_forward_2d(),
		get_cone_angle()
	)

func _fire_at_target() -> void:
	if not is_instance_valid(target) or not turret_config:
		return
	if not is_instance_valid(_sat_projectile_master_ref):
		_sat_projectile_master_ref = get_tree().get_first_node_in_group("sat_proj_master")
	if not is_instance_valid(_sat_projectile_master_ref):
		return
	var target_position: Vector3 = target.get("global_position")
	var shot_origin := get_shot_origin()
	var shot_direction: Vector3 = target_position - shot_origin
	shot_direction.y = 0.0
	if shot_direction.length_squared() <= 0.0001:
		return
	_sat_projectile_master_ref.spawn_satellite_projectile(
		shot_origin,
		shot_direction.normalized(),
		effective_damage
	)


func _process_mass(delta: float) -> void:
	var combat := GameManager.mass_combat as EnemyCombat
	if combat is EnemyGPUCombat:
		# Follow the newest asynchronous result so retained targets never use an
		# abandoned position snapshot after the GPU selects a different enemy.
		mass_target = combat.find_target(global_position, turret_config.attack_range, get_aim_forward_2d(), get_cone_angle())
	cooldown = maxf(0.0, cooldown - delta)
	target_refresh_timer -= delta
	if combat.enemy_world.is_handle_valid(mass_target):
		if not is_world_position_in_action_cone(combat.enemy_world.positions[mass_target & EnemyWorld.SLOT_MASK]):
			mass_target = -1
	else:
		mass_target = -1
	if mass_target < 0 and target_refresh_timer <= 0:
		mass_target = combat.find_target(global_position, turret_config.attack_range, get_aim_forward_2d(), get_cone_angle())
		target_refresh_timer = turret_config.target_refresh_interval
	sweep_phase = fmod(sweep_phase + delta * turret_config.sweep_speed * TAU, TAU)
	var desired := center_yaw + sin(sweep_phase) * deg_to_rad(get_cone_angle() * 0.5)
	if mass_target >= 0:
		var offset := combat.enemy_world.positions[mass_target & EnemyWorld.SLOT_MASK] - global_position
		desired = atan2(offset.x, offset.z)
	current_aim_yaw = lerp_angle(
		current_aim_yaw,
		desired,
		clampf(delta * turret_config.tracking_speed, 0.0, 1.0)
	)
	_sync_aim_visual()
	if mass_target >= 0 and cooldown <= 0:
		_fire_mass(combat.enemy_world.positions[mass_target & EnemyWorld.SLOT_MASK])


func _fire_mass(target_position: Vector3) -> void:
	var combat := GameManager.mass_combat as EnemyCombat
	var shot_origin := get_shot_origin()
	if combat.fire_projectile_with_radius(shot_origin, target_position - shot_origin, effective_damage, 350.0, 4.0, DamageSystem.Team.ALLY, 9.0):
		cooldown = 1.0 / maxf(effective_fire_rate, 0.05)
