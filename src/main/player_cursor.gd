# res://src/main/player_cursor.gd
extends Node3D
class_name PlayerCursor

@export var base_click_radius: float = 15.0
@export var base_click_damage: float = 5.0
@export var base_auto_click_interval: float = 1.5

var final_click_radius: float = 15.0
var click_damage: float = 2.0
var auto_click_timer: float = 0.0

var mouse_circle_visual: Node3D
var border_material_ref: StandardMaterial3D
var inner_material_ref: StandardMaterial3D
var camera: Camera3D

func _ready() -> void:
	# Find current camera
	camera = get_node_or_null("../CameraController")
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	# Parent node for both toruses
	mouse_circle_visual = Node3D.new()
	add_child(mouse_circle_visual)
	
	# Outer/black border torus
	var border_mesh_instance = MeshInstance3D.new()
	var border_mesh = TorusMesh.new()
	border_mesh.inner_radius = 0.94
	border_mesh.outer_radius = 1.06
	border_mesh.rings = 64
	border_mesh.ring_segments = 8
	
	var border_material = StandardMaterial3D.new()
	border_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	border_material.albedo_color = Color(0.0, 0.0, 0.0, 0.9) # Black
	border_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	border_material.no_depth_test = true
	border_material.render_priority = 99
	border_mesh.material = border_material
	border_mesh_instance.mesh = border_mesh
	mouse_circle_visual.add_child(border_mesh_instance)
	border_material_ref = border_material
	
	# Inner/dark blue torus
	var inner_mesh_instance = MeshInstance3D.new()
	var inner_mesh = TorusMesh.new()
	inner_mesh.inner_radius = 0.97
	inner_mesh.outer_radius = 1.03
	inner_mesh.rings = 64
	inner_mesh.ring_segments = 8
	
	var inner_material = StandardMaterial3D.new()
	inner_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	inner_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9) # White
	inner_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	inner_material.no_depth_test = true
	inner_material.render_priority = 100
	inner_mesh.material = inner_material
	inner_mesh_instance.mesh = inner_mesh
	mouse_circle_visual.add_child(inner_mesh_instance)
	inner_material_ref = inner_material
	
	# Connect dynamic stats calculations
	_recalculate_click_stats()
	get_node("/root/UpgradeManager").upgrade_purchased.connect(func(_id, _lvl): _recalculate_click_stats())

func _recalculate_click_stats() -> void:
	var upgrade_mgr = get_node("/root/UpgradeManager")
	final_click_radius = base_click_radius + upgrade_mgr.get_total_bonus("ClickRadius")
	click_damage = base_click_damage + upgrade_mgr.get_total_bonus("ClickDamage")

func _input(event: InputEvent) -> void:
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.current_state != game_mgr.GameState.PLAYING:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_perform_click_sweep()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.current_state != game_mgr.GameState.PLAYING:
		if mouse_circle_visual:
			mouse_circle_visual.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
		
	# Hide Windows mouse cursor during active gameplay
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		
	if not camera:
		camera = get_node_or_null("../CameraController")
		if not camera:
			camera = get_viewport().get_camera_3d()
		
	if camera and mouse_circle_visual:
		mouse_circle_visual.visible = true
		var plane_pos = project_mouse_to_plane()
		mouse_circle_visual.global_position = Vector3(plane_pos.x, 0.1, plane_pos.y)
		
		# Pulsing animation: sharp, rapid contraction of 25% repeating every 1.2 seconds
		var loop_time = 1.2
		var t = wrapf(Time.get_ticks_msec() * 0.001, 0.0, loop_time)
		var pulse = 1.0
		var dip_duration = 0.3 # 0.3 seconds to complete the quick pulse contraction
		if t < dip_duration:
			var nt = t / dip_duration
			var dip_amount = 0.25 * sin(nt * PI)
			pulse = 1.0 - dip_amount
			
		mouse_circle_visual.scale = Vector3(final_click_radius * pulse, 1.0, final_click_radius * pulse)
		
		if border_material_ref and inner_material_ref:
			# Fade out slightly as it contracts
			var alpha_factor = lerp(0.5, 1.0, (pulse - 0.75) / 0.25)
			border_material_ref.albedo_color.a = 0.9 * alpha_factor
			inner_material_ref.albedo_color.a = 0.9 * alpha_factor
			
	# Automatic hover damage sweep tick loop (always active)
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var rate_mult = upgrade_mgr.get_multiplier("AutoClickRate")
	var auto_click_interval = base_auto_click_interval / rate_mult
	auto_click_interval = max(0.05, auto_click_interval)
	
	auto_click_timer += delta
	if auto_click_timer >= auto_click_interval:
		auto_click_timer = 0.0
		_perform_click_sweep()

# Raycast projection from camera onto Y=0 plane
func project_mouse_to_plane() -> Vector2:
	if not camera:
		return Vector2.ZERO
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = camera.project_ray_normal(mouse_pos)
	
	if abs(to.y) < 0.0001:
		return Vector2.ZERO
		
	var t = - from.y / to.y
	var intersection_3d = from + to * t
	return Vector2(intersection_3d.x, intersection_3d.z)

# Apply damage sweep in a circle
func _perform_click_sweep() -> void:
	var click_pos = project_mouse_to_plane()
	var targets = GameManager._active_damageable
	
	for target in targets:
		if not target.active:
			continue
			
		# Query entity's circle collision shape radius to calculate exact bounding overlaps
		var target_radius = 0.0
		if "radius" in target:
			target_radius = target.radius * target.scale.x
		else:
			var col_shape = target.get_node_or_null("CollisionShape2D")
			if col_shape and col_shape.shape is CircleShape2D:
				target_radius = col_shape.shape.radius * target.scale.x
			
		var target_pos_2d = target.global_position
		if target is Node3D:
			target_pos_2d = Vector2(target.global_position.x, target.global_position.z)
		var dist = target_pos_2d.distance_to(click_pos)
		
		# Hit if the hover circle overlaps anywhere with the target's physical shape bounds
		if dist <= (final_click_radius + target_radius):
			print("    -> HIT! Inflicting damage: ", click_damage)
			if target.has_method("take_player_damage"):
				target.take_player_damage(click_damage)
			else:
				target.take_damage(click_damage)
