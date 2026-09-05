extends DefenseBlaster
class_name TurretMiner

const DamageSystemScript = preload("res://src/core/damage_system.gd")

enum MineState { AVAILABLE, FLYING, ARMED }

const MINE_POOL_SIZE: int = 3

@export_range(0.1, 10.0, 0.1) var launch_duration: float = 0.45
@export_range(0.1, 10.0, 0.1) var fuse_duration: float = 1.5
@export_range(0.1, 100.0, 0.5) var base_explosion_radius: float = 10.0
@export_range(0.0, 100.0, 0.5) var launch_arc_height: float = 10.0

var effective_explosion_radius: float = 10.0
var mine_visuals: Array[MeshInstance3D] = []
var mine_states: Array[int] = []
var mine_timers: Array[float] = []
var mine_start_positions: Array[Vector3] = []
var mine_end_positions: Array[Vector3] = []

func _ready() -> void:
	super._ready()
	_create_mine_pool()

func _refresh_upgrade_stats() -> void:
	if not turret_config:
		effective_damage = 5.0
		effective_fire_rate = 1.0 / 3.0
	else:
		effective_damage = turret_config.damage + UpgradeManager.get_total_bonus("MinerDamage")
		effective_fire_rate = turret_config.fire_rate
	effective_explosion_radius = base_explosion_radius + UpgradeManager.get_total_bonus("MinerRadius")

func set_deployment_active(value: bool) -> void:
	super.set_deployment_active(value)
	if not value:
		_recycle_all_mines()

func set_preview(value: bool) -> void:
	super.set_preview(value)
	if value:
		_recycle_all_mines()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(barrier_ref) or not turret_config:
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_update_mines(delta)

	sweep_phase = fmod(sweep_phase + delta * turret_config.sweep_speed * TAU, TAU)
	current_aim_yaw = center_yaw + sin(sweep_phase) * deg_to_rad(get_cone_angle() * 0.5)
	_sync_aim_visual()

	cooldown -= delta
	if cooldown <= 0.0:
		_launch_mine_at_random_cone_position()
		cooldown = 1.0 / maxf(effective_fire_rate, 0.05)

func _create_mine_pool() -> void:
	if not mine_visuals.is_empty():
		return
	for mine_index in range(MINE_POOL_SIZE):
		var visual := MeshInstance3D.new()
		visual.name = "Mine%d" % mine_index
		var mine_mesh := SphereMesh.new()
		mine_mesh.radius = 2.2
		mine_mesh.height = 4.4
		mine_mesh.radial_segments = 8
		mine_mesh.rings = 4
		var mine_material := StandardMaterial3D.new()
		mine_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mine_material.albedo_color = Color(0.95, 0.72, 0.12, 1.0)
		mine_material.emission_enabled = false
		mine_mesh.material = mine_material
		visual.mesh = mine_mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visible = false
		add_child(visual)
		mine_visuals.append(visual)
		mine_states.append(MineState.AVAILABLE)
		mine_timers.append(0.0)
		mine_start_positions.append(Vector3.ZERO)
		mine_end_positions.append(Vector3.ZERO)

func _launch_mine_at_random_cone_position() -> void:
	var mine_index: int = mine_states.find(MineState.AVAILABLE)
	if mine_index < 0 or not turret_config:
		return
	var half_angle: float = deg_to_rad(get_cone_angle() * 0.5)
	var random_yaw: float = center_yaw + randf_range(-half_angle, half_angle)
	var minimum_distance: float = minf(
		turret_config.attack_range,
		maxf(footprint_radius * 1.5, turret_config.attack_range * 0.2)
	)
	var minimum_ratio: float = minimum_distance / maxf(turret_config.attack_range, 0.001)
	var distance: float = sqrt(randf_range(minimum_ratio * minimum_ratio, 1.0)) * turret_config.attack_range
	var direction := Vector2(sin(random_yaw), cos(random_yaw))
	var start := get_shot_origin()
	var destination := Vector3(
		global_position.x + direction.x * distance,
		global_position.y + 0.5,
		global_position.z + direction.y * distance
	)
	mine_states[mine_index] = MineState.FLYING
	mine_timers[mine_index] = 0.0
	mine_start_positions[mine_index] = start
	mine_end_positions[mine_index] = destination
	mine_visuals[mine_index].global_position = start
	mine_visuals[mine_index].visible = true

func _update_mines(delta: float) -> void:
	for mine_index in range(mine_states.size()):
		match mine_states[mine_index]:
			MineState.FLYING:
				mine_timers[mine_index] += delta
				var progress: float = clampf(mine_timers[mine_index] / maxf(launch_duration, 0.001), 0.0, 1.0)
				var position: Vector3 = mine_start_positions[mine_index].lerp(mine_end_positions[mine_index], progress)
				position.y += sin(progress * PI) * launch_arc_height
				mine_visuals[mine_index].global_position = position
				if progress >= 1.0:
					mine_states[mine_index] = MineState.ARMED
					mine_timers[mine_index] = fuse_duration
					mine_visuals[mine_index].global_position = mine_end_positions[mine_index]
			MineState.ARMED:
				if GameManager.current_state != GameManager.GameState.PLAYING:
					continue
				mine_timers[mine_index] -= delta
				var pulse: float = 1.0 + 0.12 * sin(mine_timers[mine_index] * TAU * 4.0)
				mine_visuals[mine_index].scale = Vector3.ONE * pulse
				if mine_timers[mine_index] <= 0.0:
					_explode_mine(mine_index)

func _explode_mine(mine_index: int) -> void:
	if mine_index < 0 or mine_index >= mine_visuals.size():
		return
	var explosion_position: Vector3 = mine_end_positions[mine_index]
	if is_instance_valid(GameManager.mass_combat):
		GameManager.mass_combat.damage_circle(explosion_position, effective_explosion_radius, effective_damage)
		_recycle_mine(mine_index)
		return
	var candidates: Array = GameManager.get_nearby_entities(explosion_position, effective_explosion_radius)
	var radius_squared: float = effective_explosion_radius * effective_explosion_radius
	for candidate in candidates:
		if not _is_hostile_candidate(candidate) or not bool(candidate.get("active")):
			continue
		var candidate_position: Vector3 = candidate.get("global_position")
		var planar_offset := Vector2(
			candidate_position.x - explosion_position.x,
			candidate_position.z - explosion_position.z
		)
		if planar_offset.length_squared() <= radius_squared:
			DamageSystemScript.apply(candidate, effective_damage, DamageSystemScript.Team.ALLY)
	_recycle_mine(mine_index)

func _recycle_mine(mine_index: int) -> void:
	mine_states[mine_index] = MineState.AVAILABLE
	mine_timers[mine_index] = 0.0
	mine_visuals[mine_index].visible = false
	mine_visuals[mine_index].scale = Vector3.ONE

func _recycle_all_mines() -> void:
	for mine_index in range(mine_states.size()):
		_recycle_mine(mine_index)
