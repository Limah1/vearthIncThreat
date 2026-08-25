extends Node3D
class_name TurretAimGizmo

const CONE_SEGMENTS: int = 48
const HANDLE_RADIUS: float = 8.0
const HEIGHT_OFFSET: float = 2.0

var selected_turret: DefenseBlaster = null
var cone_visual: MeshInstance3D = null
var line_visual: MeshInstance3D = null
var handle_visual: MeshInstance3D = null
var cone_mesh: ImmediateMesh = null
var line_mesh: ImmediateMesh = null
var cone_material: StandardMaterial3D = null
var line_material: StandardMaterial3D = null
var _last_cone_angle: float = -1.0
var _last_range: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_visuals()
	visible = false

func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(selected_turret):
		hide_gizmo()
		return
	_sync_from_turret()

func show_for_turret(turret: DefenseBlaster) -> void:
	selected_turret = turret
	_last_cone_angle = -1.0
	_last_range = -1.0
	visible = is_instance_valid(selected_turret)
	_sync_from_turret()

func hide_gizmo() -> void:
	visible = false
	selected_turret = null

func update_from_pointer(world_point: Vector2) -> void:
	if not is_instance_valid(selected_turret):
		return
	selected_turret.update_aim_from_handle(world_point)
	_sync_from_turret()

func is_handle_hit(world_point: Vector2) -> bool:
	if not visible or not is_instance_valid(selected_turret):
		return false
	return get_handle_world_position().distance_squared_to(world_point) <= HANDLE_RADIUS * HANDLE_RADIUS

func get_handle_world_position() -> Vector2:
	if not is_instance_valid(selected_turret):
		return Vector2.ZERO
	var turret_position := Vector2(selected_turret.global_position.x, selected_turret.global_position.z)
	return turret_position + selected_turret.get_aim_forward_2d() * selected_turret.get_handle_distance()

func _sync_from_turret() -> void:
	if not is_instance_valid(selected_turret) or not selected_turret.turret_config:
		return
	global_position = selected_turret.global_position + Vector3(0.0, HEIGHT_OFFSET, 0.0)
	global_rotation = Vector3(0.0, selected_turret.get_center_yaw(), 0.0)
	if handle_visual:
		handle_visual.position = Vector3(0.0, 0.25, selected_turret.get_handle_distance())

	var action_range: float = selected_turret.turret_config.attack_range
	var action_angle: float = selected_turret.get_cone_angle()
	if not is_equal_approx(_last_cone_angle, action_angle) or not is_equal_approx(_last_range, action_range):
		_last_cone_angle = action_angle
		_last_range = action_range
		_rebuild_geometry(action_range, action_angle)

func _create_visuals() -> void:
	cone_material = StandardMaterial3D.new()
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.albedo_color = Color(0.2, 0.72, 1.0, 0.14)
	cone_material.no_depth_test = true
	cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_material.emission_enabled = false
	cone_material.render_priority = 80

	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.albedo_color = Color(0.35, 0.85, 1.0, 0.9)
	line_material.no_depth_test = true
	line_material.emission_enabled = false
	line_material.render_priority = 81

	cone_mesh = ImmediateMesh.new()
	cone_visual = MeshInstance3D.new()
	cone_visual.name = "ActionCone"
	cone_visual.mesh = cone_mesh
	cone_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone_visual)

	line_mesh = ImmediateMesh.new()
	line_visual = MeshInstance3D.new()
	line_visual.name = "ActionConeLines"
	line_visual.mesh = line_mesh
	line_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_visual)

	var handle_mesh := SphereMesh.new()
	handle_mesh.radius = HANDLE_RADIUS * 0.55
	handle_mesh.height = HANDLE_RADIUS * 1.1
	handle_mesh.radial_segments = 16
	handle_mesh.rings = 8
	var handle_material := StandardMaterial3D.new()
	handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	handle_material.albedo_color = Color(0.95, 0.95, 0.95, 0.95)
	handle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	handle_material.no_depth_test = true
	handle_material.emission_enabled = false
	handle_material.render_priority = 82
	handle_mesh.material = handle_material
	handle_visual = MeshInstance3D.new()
	handle_visual.name = "AimHandle"
	handle_visual.mesh = handle_mesh
	handle_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(handle_visual)

func _rebuild_geometry(action_range: float, action_angle: float) -> void:
	if not cone_mesh or not line_mesh:
		return
	cone_mesh.clear_surfaces()
	line_mesh.clear_surfaces()
	var half_angle: float = deg_to_rad(action_angle * 0.5)

	cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, cone_material)
	for segment_index in range(CONE_SEGMENTS):
		var first_ratio: float = float(segment_index) / float(CONE_SEGMENTS)
		var second_ratio: float = float(segment_index + 1) / float(CONE_SEGMENTS)
		var first_angle: float = lerpf(-half_angle, half_angle, first_ratio)
		var second_angle: float = lerpf(-half_angle, half_angle, second_ratio)
		cone_mesh.surface_add_vertex(Vector3.ZERO)
		cone_mesh.surface_add_vertex(_point_on_arc(first_angle, action_range))
		cone_mesh.surface_add_vertex(_point_on_arc(second_angle, action_range))
	cone_mesh.surface_end()

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	line_mesh.surface_add_vertex(Vector3.ZERO)
	line_mesh.surface_add_vertex(_point_on_arc(-half_angle, action_range))
	line_mesh.surface_add_vertex(Vector3.ZERO)
	line_mesh.surface_add_vertex(_point_on_arc(half_angle, action_range))
	line_mesh.surface_add_vertex(Vector3.ZERO)
	line_mesh.surface_add_vertex(Vector3(0.0, 0.0, action_range))
	for segment_index in range(CONE_SEGMENTS):
		var first_ratio: float = float(segment_index) / float(CONE_SEGMENTS)
		var second_ratio: float = float(segment_index + 1) / float(CONE_SEGMENTS)
		line_mesh.surface_add_vertex(_point_on_arc(lerpf(-half_angle, half_angle, first_ratio), action_range))
		line_mesh.surface_add_vertex(_point_on_arc(lerpf(-half_angle, half_angle, second_ratio), action_range))
	line_mesh.surface_end()

func _point_on_arc(angle: float, radius: float) -> Vector3:
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
