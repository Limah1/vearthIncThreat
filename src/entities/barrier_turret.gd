extends Node3D
class_name BarrierTurret

## Lightweight barrier-mounted turret. It locks the nearest asteroid and
## applies one hit per cooldown until that asteroid is destroyed.
@export var base_damage: float = 1.0
@export var fire_interval: float = 0.35
@export var attack_range: float = 700.0
@export var turret_height: float = 4.5

var active: bool = false
var previewing: bool = false
var footprint_radius: float = 7.0
var barrier_ref: Barrier = null
var local_offset: Vector2 = Vector2.ZERO
var target: Node = null
var cooldown: float = 0.0
var tracer_timer: float = 0.0
var tracer: MeshInstance3D = null

func _ready() -> void:
	add_to_group("barrier_turret")
	_create_tracer()

func assign_to_barrier(new_barrier: Barrier, new_local_offset: Vector2, new_radius: float) -> void:
	barrier_ref = new_barrier
	local_offset = new_local_offset
	set_footprint_radius(new_radius)
	previewing = false
	active = true
	cooldown = 0.0
	target = null
	sync_from_barrier()

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
	global_position = Vector3(barrier_position.x + local_offset.x, height, barrier_position.y + local_offset.y)

func set_deployment_active(value: bool) -> void:
	active = value
	visible = value or previewing
	if not active:
		target = null
		if tracer:
			tracer.visible = false

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
	var turret_mesh := get_node_or_null("TurretMesh") as MeshInstance3D
	if not turret_mesh:
		return
	if previewing:
		var base_material := turret_mesh.get_active_material(0) as StandardMaterial3D
		if base_material:
			var ghost_material := base_material.duplicate() as StandardMaterial3D
			ghost_material.albedo_color = Color(0.5, 0.5, 0.5, 0.55)
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_material.no_depth_test = true
			turret_mesh.material_override = ghost_material
	else:
		turret_mesh.material_override = null

func contains_world_point(world_point: Vector2) -> bool:
	var turret_position := Vector2(global_position.x, global_position.z)
	return turret_position.distance_squared_to(world_point) <= footprint_radius * footprint_radius

func _process(delta: float) -> void:
	if tracer_timer > 0.0:
		tracer_timer -= delta
		if tracer_timer <= 0.0 and tracer:
			tracer.visible = false

	if not active or not is_instance_valid(barrier_ref):
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if cooldown > 0.0:
		cooldown -= delta
	if not _is_valid_target(target):
		target = _find_nearest_asteroid()
	if is_instance_valid(target) and cooldown <= 0.0:
		_fire_at_target()
		cooldown = fire_interval

func _find_nearest_asteroid() -> Node:
	var nearest: Node = null
	var nearest_distance_sq := attack_range * attack_range
	var candidates: Array = GameManager.get_nearby_entities(global_position, attack_range)
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate.is_in_group("asteroid"):
			continue
		if not bool(candidate.get("active")):
			continue
		var candidate_position: Vector3 = Vector3(candidate.get("global_position"))
		var distance_sq := global_position.distance_squared_to(candidate_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest

func _is_valid_target(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or not bool(candidate.get("active")):
		return false
	var candidate_position: Vector3 = Vector3(candidate.get("global_position"))
	return global_position.distance_squared_to(candidate_position) <= attack_range * attack_range

func _fire_at_target() -> void:
	if not is_instance_valid(target):
		return
	var target_position: Vector3 = Vector3(target.get("global_position"))
	var damage := base_damage
	if target.has_method("take_player_damage"):
		target.take_player_damage(damage)
	else:
		target.take_damage(damage)
	_show_tracer(target_position)
	if not _is_valid_target(target):
		target = null

func _create_tracer() -> void:
	tracer = MeshInstance3D.new()
	tracer.name = "TurretTracer"
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.8, 0.5, 1.0)
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = Color(1.0, 0.75, 0.2, 0.9)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.no_depth_test = true
	beam_material.emission_enabled = false
	beam_material.render_priority = 90
	beam_mesh.material = beam_material
	tracer.mesh = beam_mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.visible = false
	add_child(tracer)

func _show_tracer(target_position: Vector3) -> void:
	if not tracer:
		return
	var start_position := global_position + Vector3(0.0, 1.0, 0.0)
	var direction := target_position - start_position
	var distance := direction.length()
	if distance <= 0.01:
		return
	tracer.global_position = start_position + direction * 0.5
	tracer.global_rotation = Vector3.ZERO
	tracer.rotation.y = atan2(direction.x, direction.z)
	tracer.scale = Vector3.ONE
	tracer.scale.z = distance
	tracer.visible = true
	tracer_timer = 0.08
