extends DefenseBlaster
class_name LaserTurret

const DamageSystemScript = preload("res://src/core/damage_system.gd")

const DAMAGE_TICK_INTERVAL: float = 0.2

@export_range(0.1, 30.0, 0.1) var beam_duration: float = 3.0
@export_range(0.5, 60.0, 0.5) var base_beam_cooldown: float = 10.0
@export_range(0.5, 30.0, 0.5) var beam_half_width: float = 4.0

var effective_beam_cooldown: float = 10.0
var beam_remaining: float = 0.0
var beam_tick_timer: float = 0.0
var beam_direction: Vector2 = Vector2.ZERO

@onready var beam_visual: MeshInstance3D = get_node_or_null("LaserBeam") as MeshInstance3D

func _ready() -> void:
	super._ready()
	if beam_visual:
		beam_visual.visible = false

func _refresh_upgrade_stats() -> void:
	if not turret_config:
		effective_damage = 5.0
		effective_beam_cooldown = base_beam_cooldown
		return
	effective_damage = turret_config.damage + UpgradeManager.get_total_bonus("LaserDamage")
	effective_beam_cooldown = maxf(
		0.5,
		base_beam_cooldown - UpgradeManager.get_total_bonus("LaserCooldownReduction")
	)

func set_deployment_active(value: bool) -> void:
	super.set_deployment_active(value)
	if not value:
		_stop_beam(false)

func set_preview(value: bool) -> void:
	super.set_preview(value)
	if value and beam_visual:
		beam_visual.visible = false

func _process(delta: float) -> void:
	if not active or not is_instance_valid(barrier_ref) or not turret_config:
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if beam_remaining > 0.0:
		_update_active_beam(delta)
		return

	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	target_refresh_timer -= delta
	if not _is_valid_target(target):
		target = null
	if not is_instance_valid(target) and target_refresh_timer <= 0.0:
		target = _find_nearest_asteroid()
		target_refresh_timer = turret_config.target_refresh_interval

	sweep_phase = fmod(sweep_phase + delta * turret_config.sweep_speed * TAU, TAU)
	var desired_yaw: float = center_yaw + sin(sweep_phase) * deg_to_rad(get_cone_angle() * 0.5)
	if is_instance_valid(target):
		var target_position: Vector3 = target.get("global_position")
		var target_offset := Vector2(
			target_position.x - global_position.x,
			target_position.z - global_position.z
		)
		if not target_offset.is_zero_approx():
			desired_yaw = atan2(target_offset.x, target_offset.y)
	current_aim_yaw = lerp_angle(current_aim_yaw, desired_yaw, clampf(delta * 10.0, 0.0, 1.0))
	_sync_turret_mesh_rotation()

	if cooldown <= 0.0 and is_instance_valid(target):
		_begin_beam(target)

func _begin_beam(first_target: Node) -> void:
	if not _is_valid_target(first_target):
		return
	var target_position: Vector3 = first_target.get("global_position")
	beam_direction = Vector2(
		target_position.x - global_position.x,
		target_position.z - global_position.z
	).normalized()
	if beam_direction.is_zero_approx():
		return
	current_aim_yaw = atan2(beam_direction.x, beam_direction.y)
	_sync_turret_mesh_rotation()
	beam_remaining = beam_duration
	beam_tick_timer = DAMAGE_TICK_INTERVAL
	target = null
	_set_beam_visible(true)
	_damage_beam_tick()

func _update_active_beam(delta: float) -> void:
	beam_remaining -= delta
	beam_tick_timer -= delta
	while beam_tick_timer <= 0.0 and beam_remaining > 0.0:
		_damage_beam_tick()
		beam_tick_timer += DAMAGE_TICK_INTERVAL
	if beam_remaining <= 0.0:
		_stop_beam(true)

func _stop_beam(start_cooldown: bool) -> void:
	beam_remaining = 0.0
	beam_tick_timer = 0.0
	if beam_visual:
		beam_visual.visible = false
	if start_cooldown:
		cooldown = effective_beam_cooldown

func _damage_beam_tick() -> void:
	if beam_direction.is_zero_approx() or not turret_config:
		return
	var candidates: Array = GameManager.get_nearby_entities(global_position, turret_config.attack_range)
	var tick_damage: float = effective_damage * DAMAGE_TICK_INTERVAL
	for candidate in candidates:
		if not _is_hostile_candidate(candidate) or not bool(candidate.get("active")):
			continue
		var candidate_position: Vector3 = candidate.get("global_position")
		var offset := Vector2(
			candidate_position.x - global_position.x,
			candidate_position.z - global_position.z
		)
		var along_beam: float = offset.dot(beam_direction)
		if along_beam < 0.0 or along_beam > turret_config.attack_range:
			continue
		var perpendicular_distance: float = absf(offset.cross(beam_direction))
		var target_radius: float = 0.0
		var radius_value: Variant = candidate.get("radius")
		if radius_value != null:
			target_radius = maxf(float(radius_value), 0.0)
		if perpendicular_distance <= beam_half_width + target_radius:
			DamageSystemScript.apply(candidate, tick_damage, DamageSystemScript.Team.ALLY)

func _set_beam_visible(value: bool) -> void:
	if not beam_visual or not turret_config:
		return
	beam_visual.visible = value
	beam_visual.rotation.y = current_aim_yaw
	beam_visual.position = Vector3(
		sin(current_aim_yaw) * turret_config.attack_range * 0.5,
		1.0,
		cos(current_aim_yaw) * turret_config.attack_range * 0.5
	)
	beam_visual.scale = Vector3(1.0, 1.0, turret_config.attack_range)

func _sync_turret_mesh_rotation() -> void:
	var turret_mesh := get_node_or_null("TurretMesh") as MeshInstance3D
	if turret_mesh:
		turret_mesh.rotation.y = current_aim_yaw
	if beam_remaining > 0.0 and beam_visual:
		beam_visual.rotation.y = current_aim_yaw

func _is_hostile_candidate(candidate: Node) -> bool:
	return (
		is_instance_valid(candidate)
		and (candidate.is_in_group("asteroid") or candidate.is_in_group("enemy"))
	)
