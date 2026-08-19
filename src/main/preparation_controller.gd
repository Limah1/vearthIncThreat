extends Node3D
class_name PreparationController

enum PlacementMode { NONE, TURRET }

const STARTING_TURRETS: int = 4

var ally_ships: Node = null
var footer: Control = null
var camera: Camera3D = null
var game_manager: Node = null
var active: bool = false
var placement_mode: PlacementMode = PlacementMode.NONE
var preview_turret: BarrierTurret = null
var available_turrets: int = STARTING_TURRETS
var barriers: Array[Barrier] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("preparation_controller")
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager and not game_manager.state_changed.is_connected(_on_state_changed):
		game_manager.state_changed.connect(_on_state_changed)
	call_deferred("_initialize")

func _initialize() -> void:
	var current_scene := get_tree().current_scene
	if current_scene:
		ally_ships = current_scene.find_child("AllyShips", true, false)
		footer = current_scene.find_child("PreparationFooter", true, false) as Control
		camera = current_scene.find_child("CameraController", true, false) as Camera3D
	_refresh_barriers()
	if not camera:
		camera = get_viewport().get_camera_3d()
	_reset_inventory()
	_on_state_changed(game_manager.current_state if game_manager else 0)

func _refresh_barriers() -> void:
	barriers.clear()
	if not is_instance_valid(ally_ships):
		return
	for node in get_tree().get_nodes_in_group("barrier"):
		if node is Barrier and ally_ships.is_ancestor_of(node):
			barriers.append(node as Barrier)

func _on_state_changed(new_state: int) -> void:
	active = is_instance_valid(game_manager) and new_state == game_manager.GameState.PREPARATION
	if active:
		_cancel_placement()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_set_footer_visible(true)
		if barriers.is_empty():
			_set_status("No barriers found in AllyShips. Add barriers to the selected level scene.")
		else:
			_set_status("Select a turret icon, then click a barrier to place it. Right-click cancels.")
	else:
		_cancel_placement()
		_set_footer_visible(false)
		if game_manager and new_state == game_manager.GameState.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(_delta: float) -> void:
	if not active or placement_mode != PlacementMode.TURRET or not preview_turret:
		return
	var pointer_world := project_mouse_to_world()
	var pointer := Vector2(pointer_world.x, pointer_world.z)
	var preview_height: float = preview_turret.turret_height
	var target_barrier := _find_barrier_at(pointer)
	if target_barrier:
		preview_height = target_barrier.get_turret_height()
	elif not barriers.is_empty() and is_instance_valid(barriers[0]):
		preview_height = barriers[0].get_turret_height()
	preview_turret.global_position = Vector3(pointer_world.x, preview_height, pointer_world.z)

func _input(event: InputEvent) -> void:
	if not active or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if _handle_mouse_event(mouse_event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if _handle_mouse_event(mouse_event):
		get_viewport().set_input_as_handled()

func _handle_mouse_event(mouse_event: InputEventMouseButton) -> bool:
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		_cancel_placement()
		_set_status("Placement cancelled. Select the turret icon to try again.")
		return true
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and placement_mode == PlacementMode.TURRET and not _is_pointer_over_footer(mouse_event.position):
		var pointer_world := project_mouse_to_world()
		_commit_turret(Vector2(pointer_world.x, pointer_world.z))
		return true
	return false

func begin_turret_placement() -> void:
	if not active:
		return
	if available_turrets <= 0:
		_set_status("No turrets remaining.")
		return
	_refresh_barriers()
	var source_barrier := _get_turret_source_barrier()
	if not source_barrier:
		_set_status("No barrier with a turret scene found in AllyShips.")
		return
	_cancel_placement()

	preview_turret = source_barrier.turret_scene.instantiate() as BarrierTurret
	if not preview_turret:
		_set_status("Could not create a turret preview.")
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		preview_turret.queue_free()
		preview_turret = null
		return
	current_scene.add_child(preview_turret)
	preview_turret.set_footprint_radius(source_barrier.get_turret_radius())
	preview_turret.set_preview(true)
	placement_mode = PlacementMode.TURRET
	_set_status("Turret preview attached to cursor. Click a barrier to place it; right-click cancels.")

func reset_layout() -> void:
	if not active:
		return
	_cancel_placement()
	_refresh_barriers()
	for current_barrier in barriers:
		if is_instance_valid(current_barrier):
			current_barrier.clear_turrets()
	_reset_inventory()
	_set_status("Turret layout reset. Select the turret icon to deploy again.")

func start_wave() -> void:
	if not active:
		return
	_refresh_barriers()
	if barriers.is_empty():
		_set_status("Add at least one barrier to AllyShips before starting the wave.")
		return
	_cancel_placement()
	game_manager.begin_gameplay()

func get_available_turrets() -> int:
	return available_turrets

func get_barrier_count() -> int:
	_refresh_barriers()
	return barriers.size()

func get_placed_barrier_count() -> int:
	return get_barrier_count()

func get_turret_radius() -> float:
	var source_barrier := _get_turret_source_barrier()
	return source_barrier.get_turret_radius() if source_barrier else Barrier.MAX_TURRET_RADIUS

func can_start_wave() -> bool:
	return active and get_barrier_count() > 0

func _commit_turret(world_point: Vector2) -> void:
	if not preview_turret:
		return
	var target_barrier := _find_barrier_at(world_point)
	if not target_barrier:
		_set_status("Click inside a barrier from AllyShips to place the turret.")
		return
	if not target_barrier.attach_turret(preview_turret, world_point):
		_set_status("Invalid turret position: keep it inside and avoid overlap.")
		return
	available_turrets -= 1
	preview_turret = null
	placement_mode = PlacementMode.NONE
	_set_status("Turret placed. Select another turret or start the wave.")

func _get_turret_source_barrier() -> Barrier:
	for current_barrier in barriers:
		if is_instance_valid(current_barrier) and current_barrier.turret_scene:
			return current_barrier
	return null

func _find_barrier_at(world_point: Vector2) -> Barrier:
	for current_barrier in barriers:
		if is_instance_valid(current_barrier) and current_barrier.placed and current_barrier.contains_world_point(world_point):
			return current_barrier
	return null

func _cancel_placement() -> void:
	placement_mode = PlacementMode.NONE
	if preview_turret:
		preview_turret.queue_free()
		preview_turret = null

func _reset_inventory() -> void:
	available_turrets = STARTING_TURRETS

func project_mouse_to_world() -> Vector3:
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3(0.0, Barrier.PLAYFIELD_Y, 0.0)
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.0001:
		return Vector3(ray_origin.x, Barrier.PLAYFIELD_Y, ray_origin.z)
	var distance := (Barrier.PLAYFIELD_Y - ray_origin.y) / ray_direction.y
	return ray_origin + ray_direction * distance

func project_mouse_to_plane() -> Vector2:
	var point := project_mouse_to_world()
	return Vector2(point.x, point.z)

func _is_pointer_over_footer(screen_position: Vector2) -> bool:
	if not is_instance_valid(footer) or not footer.visible:
		return false
	var panel := footer.get_node_or_null("Panel") as Control
	return is_instance_valid(panel) and panel.visible and panel.get_global_rect().has_point(screen_position)

func _set_footer_visible(value: bool) -> void:
	if footer:
		footer.visible = value
		if footer.has_method("set_controller"):
			footer.set_controller(self)

func _set_status(message: String) -> void:
	if footer and footer.has_method("set_status"):
		footer.set_status(message)
