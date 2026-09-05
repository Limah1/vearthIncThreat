extends Node3D
class_name PreparationController

signal layout_changed

const TurretAimGizmoScript = preload("res://src/main/turret_aim_gizmo.gd")
const DefenseBlasterScene = preload("res://src/entities/defense_blaster.tscn")
const LaserTurretScene = preload("res://src/entities/laser_turret.tscn")
const TurretMinerScene = preload("res://src/entities/turret_miner.tscn")

enum PlacementMode { NONE, POSITIONING, AIMING }
enum TurretType { DEFENSE_BLASTER, LASER_TURRET, TURRET_MINER }

const STARTING_TURRETS: int = 4
const STARTING_LASER_TURRETS: int = 1
const STARTING_TURRET_MINERS: int = 2

var ally_ships: Node = null
var footer: Control = null
var camera: Camera3D = null
var game_manager: Node = null
var active: bool = false
var placement_mode: PlacementMode = PlacementMode.NONE
var preview_turret: DefenseBlaster = null
var aiming_turret: DefenseBlaster = null
var aim_gizmo: TurretAimGizmo = null
var dragging_aim_handle: bool = false
var aiming_is_new_turret: bool = false
var original_center_yaw: float = 0.0
var original_cone_angle: float = 90.0
var available_turrets: int = STARTING_TURRETS
var starting_turrets: int = STARTING_TURRETS
var selected_turret_type: TurretType = TurretType.DEFENSE_BLASTER
var available_by_type: Dictionary = {}
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
		_create_aim_gizmo(current_scene)
	_refresh_barriers()
	if not camera:
		camera = get_viewport().get_camera_3d()
	if game_manager:
		var level_config := game_manager.get_selected_level_config() as LevelConfig
		if is_instance_valid(level_config):
			starting_turrets = maxi(level_config.starting_defense_blasters, 0)
	_reset_inventory()
	_on_state_changed(game_manager.current_state if game_manager else 0)

func _create_aim_gizmo(current_scene: Node) -> void:
	if is_instance_valid(aim_gizmo):
		return
	aim_gizmo = TurretAimGizmoScript.new() as TurretAimGizmo
	if aim_gizmo:
		current_scene.add_child(aim_gizmo)
		aim_gizmo.name = "TurretAimGizmo"

func _refresh_barriers() -> void:
	barriers.clear()
	if not is_instance_valid(ally_ships):
		return
	for node in get_tree().get_nodes_in_group("barrier"):
		if node is Barrier and ally_ships.is_ancestor_of(node):
			barriers.append(node as Barrier)

func _on_state_changed(new_state: int) -> void:
	active = is_instance_valid(game_manager) and new_state == game_manager.GameState.PREPARATION
	_refresh_barriers()
	_set_mount_spots_visible(active)
	if active:
		_cancel_placement()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_set_footer_visible(true)
		if barriers.is_empty():
			_set_status("No Basic Ally Ships found. Add them to the level's AllyShips node.")
		else:
			_set_status("Select a turret, click a grey mount on a Basic Ally Ship, then configure its cone.")
	else:
		_cancel_placement()
		_set_footer_visible(false)
		if game_manager and new_state == game_manager.GameState.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(_delta: float) -> void:
	if not active:
		return
	if placement_mode == PlacementMode.POSITIONING and is_instance_valid(preview_turret):
		var pointer_world := project_mouse_to_world()
		var pointer := Vector2(pointer_world.x, pointer_world.z)
		var preview_height: float = preview_turret.turret_height
		var target_barrier := _find_barrier_at(pointer)
		if target_barrier:
			preview_height = target_barrier.get_turret_height()
			var mount_position: Variant = target_barrier.get_available_mount_world_position_near(pointer)
			if mount_position is Vector2:
				pointer_world.x = (mount_position as Vector2).x
				pointer_world.z = (mount_position as Vector2).y
		elif not barriers.is_empty() and is_instance_valid(barriers[0]):
			preview_height = barriers[0].get_turret_height()
		preview_turret.global_position = Vector3(pointer_world.x, preview_height, pointer_world.z)
	elif placement_mode == PlacementMode.AIMING and dragging_aim_handle and is_instance_valid(aim_gizmo):
		var pointer_world := project_mouse_to_world()
		aim_gizmo.update_from_pointer(Vector2(pointer_world.x, pointer_world.z))

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
			return_all_turrets()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if _handle_mouse_event(event as InputEventMouseButton):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_aim_handle:
		var pointer_world := project_mouse_to_world()
		if is_instance_valid(aim_gizmo):
			aim_gizmo.update_from_pointer(Vector2(pointer_world.x, pointer_world.z))
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active or not event is InputEventMouseButton:
		return
	if _handle_mouse_event(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()

func _handle_mouse_event(mouse_event: InputEventMouseButton) -> bool:
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		_cancel_placement()
		_set_status("Action cancelled. Select a turret to continue. R returns all turrets.")
		return true
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	# Always finish a handle drag, even when the release lands over the footer.
	# Otherwise the gizmo would remain attached to the cursor.
	if placement_mode == PlacementMode.AIMING and not mouse_event.pressed and dragging_aim_handle:
		dragging_aim_handle = false
		if not _is_pointer_over_footer(mouse_event.position):
			var release_world := project_mouse_to_world()
			if is_instance_valid(aim_gizmo):
				aim_gizmo.update_from_pointer(Vector2(release_world.x, release_world.z))
		_set_status("Cone updated. Left-click outside the handle to confirm; right-click cancels.")
		return true
	if _is_pointer_over_footer(mouse_event.position):
		return false

	var pointer_world := project_mouse_to_world()
	var pointer := Vector2(pointer_world.x, pointer_world.z)
	if placement_mode == PlacementMode.POSITIONING and mouse_event.pressed:
		_commit_turret(pointer)
		return true
	if placement_mode == PlacementMode.AIMING:
		if mouse_event.pressed:
			if is_instance_valid(aim_gizmo) and aim_gizmo.is_handle_hit(pointer):
				dragging_aim_handle = true
				aim_gizmo.update_from_pointer(pointer)
			else:
				_confirm_turret_aim()
			return true
	if placement_mode == PlacementMode.NONE and mouse_event.pressed:
		var selected_turret := _find_turret_at(pointer)
		if selected_turret:
			_begin_turret_aim(selected_turret, false)
			return true
	return false

func begin_turret_placement(turret_type: TurretType = TurretType.DEFENSE_BLASTER) -> void:
	if not active:
		return
	if not is_turret_type_unlocked(turret_type):
		_set_status("%s is locked. Purchase its unlock in the skill tree first." % get_turret_type_name(turret_type))
		return
	if get_available_turrets_for_type(turret_type) <= 0:
		_set_status("No %s units remaining." % get_turret_type_name(turret_type))
		return
	_refresh_barriers()
	if barriers.is_empty():
		_set_status("No Basic Ally Ship found in the level's AllyShips node.")
		return
	_cancel_placement()
	selected_turret_type = turret_type

	var turret_scene: PackedScene = _get_scene_for_type(turret_type)
	preview_turret = turret_scene.instantiate() as DefenseBlaster if turret_scene else null
	if not preview_turret:
		_set_status("Could not create a %s preview." % get_turret_type_name(turret_type))
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		preview_turret.queue_free()
		preview_turret = null
		return
	current_scene.add_child(preview_turret)
	preview_turret.set_footprint_radius(barriers[0].get_turret_radius())
	preview_turret.set_preview(true)
	placement_mode = PlacementMode.POSITIONING
	_set_status("%s attached to cursor. Click an empty grey ship mount; right-click cancels." % get_turret_type_name(turret_type))

func begin_laser_turret_placement() -> void:
	begin_turret_placement(TurretType.LASER_TURRET)

func begin_turret_miner_placement() -> void:
	begin_turret_placement(TurretType.TURRET_MINER)

func reset_layout() -> void:
	if not active:
		return
	_return_all_turrets("Turret layout reset. All turrets returned to inventory.")

func return_all_turrets() -> void:
	if not active:
		return
	_return_all_turrets("R pressed: all deployed turrets returned to inventory.")

func _return_all_turrets(status_message: String) -> void:
	_cancel_placement()
	_refresh_barriers()
	for current_barrier in barriers:
		if is_instance_valid(current_barrier):
			current_barrier.clear_turrets()
	_reset_inventory()
	_set_status(status_message)
	layout_changed.emit()

func start_wave() -> void:
	if not active:
		return
	_refresh_barriers()
	if barriers.is_empty():
		_set_status("Add at least one Basic Ally Ship to AllyShips before starting the wave.")
		return
	if placement_mode == PlacementMode.AIMING:
		_confirm_turret_aim()
	elif placement_mode == PlacementMode.POSITIONING:
		_cancel_placement()
	game_manager.begin_gameplay()

func get_available_turrets() -> int:
	return get_available_turrets_for_type(TurretType.DEFENSE_BLASTER)

func get_available_laser_turrets() -> int:
	return get_available_turrets_for_type(TurretType.LASER_TURRET)

func get_available_turret_miners() -> int:
	return get_available_turrets_for_type(TurretType.TURRET_MINER)

func is_defense_blaster_unlocked() -> bool:
	return is_turret_type_unlocked(TurretType.DEFENSE_BLASTER)

func is_laser_turret_unlocked() -> bool:
	return is_turret_type_unlocked(TurretType.LASER_TURRET)

func is_turret_miner_unlocked() -> bool:
	return is_turret_type_unlocked(TurretType.TURRET_MINER)

func get_available_turrets_for_type(turret_type: TurretType) -> int:
	return int(available_by_type.get(turret_type, 0))

func is_turret_type_unlocked(turret_type: TurretType) -> bool:
	if turret_type == TurretType.DEFENSE_BLASTER and game_manager:
		var level_config := game_manager.get_selected_level_config() as LevelConfig
		if is_instance_valid(level_config) and level_config.defense_blasters_unlocked:
			return true
	return UpgradeManager.get_upgrade_level(_get_unlock_upgrade_id(turret_type)) > 0

func get_turret_type_name(turret_type: TurretType) -> String:
	match turret_type:
		TurretType.LASER_TURRET:
			return "Laser Turret"
		TurretType.TURRET_MINER:
			return "Turret Miner"
		_:
			return "Defense Blaster"

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
		_set_status("Click an empty grey mount on a Basic Ally Ship to place the %s." % get_turret_type_name(selected_turret_type))
		return
	if not target_barrier.attach_turret(preview_turret, world_point):
		_set_status("That mount is unavailable. Choose one of the empty grey circles.")
		return

	available_by_type[selected_turret_type] = get_available_turrets_for_type(selected_turret_type) - 1
	available_turrets = get_available_turrets()
	var placed_turret: DefenseBlaster = preview_turret
	preview_turret = null
	var outward_direction := Vector2(placed_turret.global_position.x, placed_turret.global_position.z).normalized()
	if outward_direction.is_zero_approx():
		outward_direction = Vector2(0.0, 1.0)
	placed_turret.set_aim_direction(outward_direction)
	_begin_turret_aim(placed_turret, true)

func _begin_turret_aim(turret: DefenseBlaster, is_new_turret: bool) -> void:
	if not is_instance_valid(turret):
		return
	aiming_turret = turret
	selected_turret_type = _get_type_for_turret(turret)
	aiming_is_new_turret = is_new_turret
	original_center_yaw = turret.get_center_yaw()
	original_cone_angle = turret.get_cone_angle()
	dragging_aim_handle = false
	placement_mode = PlacementMode.AIMING
	if is_instance_valid(aim_gizmo):
		aim_gizmo.show_for_turret(turret)
	_set_status("Drag the center handle: farther is narrower, closer is wider. Left-click outside it to confirm.")

func _confirm_turret_aim() -> void:
	if placement_mode != PlacementMode.AIMING:
		return
	if is_instance_valid(aim_gizmo):
		aim_gizmo.hide_gizmo()
	aiming_turret = null
	aiming_is_new_turret = false
	dragging_aim_handle = false
	placement_mode = PlacementMode.NONE
	_set_status("%s angle confirmed. Select another turret, edit a placed turret, or start the wave." % get_turret_type_name(selected_turret_type))
	layout_changed.emit()


func commit_pending_layout_changes() -> void:
	if placement_mode == PlacementMode.AIMING:
		_confirm_turret_aim()
	elif placement_mode == PlacementMode.POSITIONING:
		_cancel_placement()


func prepare_inventory_for_layout_restore() -> void:
	_cancel_placement()
	_refresh_barriers()
	_reset_inventory()


func restore_turret_configuration(
	barrier: Barrier,
	turret_type_id: String,
	mount_slot: int,
	center_yaw: float,
	cone_angle: float
) -> bool:
	if not is_instance_valid(barrier) or mount_slot < 0 or mount_slot >= Barrier.MAX_TURRETS:
		return false
	var turret_type := _get_type_for_id(turret_type_id)
	if not is_turret_type_unlocked(turret_type) or get_available_turrets_for_type(turret_type) <= 0:
		return false
	var turret_scene := _get_scene_for_type(turret_type)
	var turret := turret_scene.instantiate() as DefenseBlaster if turret_scene else null
	if not is_instance_valid(turret):
		return false
	var current_scene := get_tree().current_scene
	if not is_instance_valid(current_scene):
		turret.queue_free()
		return false
	current_scene.add_child(turret)
	var mount_position := barrier.get_world_position_for_local_offset(
		barrier.get_mount_slot_offset(mount_slot)
	)
	if not barrier.attach_turret(turret, mount_position):
		turret.queue_free()
		return false
	turret.set_aim_configuration(center_yaw, cone_angle)
	available_by_type[turret_type] = get_available_turrets_for_type(turret_type) - 1
	available_turrets = get_available_turrets()
	return true

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

func _find_turret_at(world_point: Vector2) -> DefenseBlaster:
	for current_barrier in barriers:
		if not is_instance_valid(current_barrier):
			continue
		for turret_variant in current_barrier.turrets:
			var turret := turret_variant as DefenseBlaster
			if is_instance_valid(turret) and turret.contains_world_point(world_point):
				return turret
	return null

func _cancel_placement() -> void:
	if is_instance_valid(preview_turret):
		preview_turret.queue_free()
	preview_turret = null

	if is_instance_valid(aiming_turret):
		if aiming_is_new_turret:
			var owner_barrier: Barrier = aiming_turret.barrier_ref
			if is_instance_valid(owner_barrier):
				owner_barrier.remove_turret(aiming_turret)
			else:
				aiming_turret.queue_free()
			var maximum: int = _get_maximum_for_type(selected_turret_type)
			available_by_type[selected_turret_type] = mini(
				get_available_turrets_for_type(selected_turret_type) + 1,
				maximum
			)
			available_turrets = get_available_turrets()
		else:
			aiming_turret.set_aim_configuration(original_center_yaw, original_cone_angle)
	aiming_turret = null
	aiming_is_new_turret = false
	dragging_aim_handle = false
	if is_instance_valid(aim_gizmo):
		aim_gizmo.hide_gizmo()
	placement_mode = PlacementMode.NONE

func _reset_inventory() -> void:
	available_by_type[TurretType.DEFENSE_BLASTER] = starting_turrets if is_turret_type_unlocked(TurretType.DEFENSE_BLASTER) else 0
	available_by_type[TurretType.LASER_TURRET] = STARTING_LASER_TURRETS if is_turret_type_unlocked(TurretType.LASER_TURRET) else 0
	available_by_type[TurretType.TURRET_MINER] = STARTING_TURRET_MINERS if is_turret_type_unlocked(TurretType.TURRET_MINER) else 0
	available_turrets = get_available_turrets()

func _get_scene_for_type(turret_type: TurretType) -> PackedScene:
	match turret_type:
		TurretType.LASER_TURRET:
			return LaserTurretScene
		TurretType.TURRET_MINER:
			return TurretMinerScene
		_:
			return DefenseBlasterScene

func _get_unlock_upgrade_id(turret_type: TurretType) -> String:
	match turret_type:
		TurretType.LASER_TURRET:
			return "DA_UnlockLaserTurret"
		TurretType.TURRET_MINER:
			return "DA_UnlockTurretMiner"
		_:
			return "DA_UnlockTurret"

func _get_maximum_for_type(turret_type: TurretType) -> int:
	match turret_type:
		TurretType.LASER_TURRET:
			return STARTING_LASER_TURRETS
		TurretType.TURRET_MINER:
			return STARTING_TURRET_MINERS
		_:
			return starting_turrets

func _get_type_for_turret(turret: DefenseBlaster) -> TurretType:
	if not is_instance_valid(turret):
		return TurretType.DEFENSE_BLASTER
	match turret.get_turret_type_id():
		"laser_turret":
			return TurretType.LASER_TURRET
		"turret_miner":
			return TurretType.TURRET_MINER
		_:
			return TurretType.DEFENSE_BLASTER


func _get_type_for_id(turret_type_id: String) -> TurretType:
	match turret_type_id:
		"laser_turret":
			return TurretType.LASER_TURRET
		"turret_miner":
			return TurretType.TURRET_MINER
		_:
			return TurretType.DEFENSE_BLASTER

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

func _set_mount_spots_visible(value: bool) -> void:
	for current_barrier in barriers:
		if is_instance_valid(current_barrier) and current_barrier.has_method("set_mount_spots_visible"):
			current_barrier.set_mount_spots_visible(value)
