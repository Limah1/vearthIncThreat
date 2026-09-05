extends Node3D
class_name GridCombatController

const GridAllyShipScene: PackedScene = preload("res://src/prototypes/grid_combat/grid_ally_ship.tscn")
const GridDefenseBlockScene: PackedScene = preload("res://src/prototypes/grid_combat/grid_defense_block.tscn")
const GridLayoutStoreScript = preload("res://src/core/grid_layout_store.gd")
const FIRST_LEVEL_CONFIG_PATH: String = "res://src/resources/levels/FirstLevelConfig.tres"
const DEFAULT_STARTING_ALLY_SHIPS: int = 4
const DEFAULT_STARTING_DEFENSE_BLOCKS: int = 3

enum PlacementMode { IDLE, PLACING }
enum PlaceableType { ALLY_SHIP, DEFENSE_BLOCK }

signal layout_restored(restored_actor_count: int, restored_turret_count: int)

@onready var board: GridBoard = $"../GridBoard"
@onready var ally_ships_root: Node2D = $"../AllyShips"
@onready var grid_actors_root: Node3D = $"../GridActors"
@onready var camera: Camera3D = $"../CameraController"
@onready var spawner: Spawner = $"../Spawner"
@onready var player_cursor: PlayerCursor = $"../PlayerCursor"
@onready var standard_preparation_controller: PreparationController = $"../PreparationController"
@onready var standard_preparation_footer: Control = $"../CanvasLayer/PreparationFooter"
@onready var grid_ui: Control = $"../CanvasLayer/GridPrototypeUI"
@onready var status_label: Label = $"../CanvasLayer/GridPrototypeUI/TopPanel/Margin/VBox/StatusLabel"
@onready var inventory_label: Label = $"../CanvasLayer/GridPrototypeUI/TopPanel/Margin/VBox/InventoryLabel"
@onready var ally_ship_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/AllyShipButton"
@onready var defense_block_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/DefenseBlockButton"
@onready var reset_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/ResetButton"
@onready var start_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/StartButton"
@onready var return_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/ReturnButton"
@onready var defense_turret_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/DefenseTurretButton"
@onready var laser_turret_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/LaserTurretButton"
@onready var turret_miner_button: Button = $"../CanvasLayer/GridPrototypeUI/Footer/Margin/Buttons/TurretMinerButton"
@onready var rotation_hints: Control = $"../CanvasLayer/GridPrototypeUI/RotationHints"
@onready var left_hint: Control = $"../CanvasLayer/GridPrototypeUI/RotationHints/LeftHint"
@onready var right_hint: Control = $"../CanvasLayer/GridPrototypeUI/RotationHints/RightHint"

var active: bool = false
var placement_mode: PlacementMode = PlacementMode.IDLE
var selected_placeable_type: PlaceableType = PlaceableType.ALLY_SHIP
var starting_ally_ships: int = DEFAULT_STARTING_ALLY_SHIPS
var starting_defense_blocks: int = DEFAULT_STARTING_DEFENSE_BLOCKS
var minimum_ally_ships_to_start: int = 1
var ally_ships_remaining: int = DEFAULT_STARTING_ALLY_SHIPS
var defense_blocks_remaining: int = DEFAULT_STARTING_DEFENSE_BLOCKS
var preview_actor: Node = null
var preview_anchor_cell: Vector2i = Vector2i(-1, -1)
var preview_orientation: int = 0
var selected_ship: Barrier = null
var wave_started: bool = false

var placed_actors: Array[Node] = []
var placed_ally_ships: Array[Barrier] = []
var anchor_by_actor: Dictionary = {}
var orientation_by_actor: Dictionary = {}
var type_by_actor: Dictionary = {}
var _layout_io_suspended: bool = false

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	if is_instance_valid(GameManager):
		var level_config := GameManager.get_selected_level_config()
		active = is_instance_valid(level_config) and level_config.grid_combat_enabled
		if active:
			starting_ally_ships = maxi(level_config.starting_ally_ships, 0)
			starting_defense_blocks = maxi(level_config.starting_defense_blocks, 0)
			minimum_ally_ships_to_start = clampi(
				level_config.minimum_ally_ships_to_start,
				0,
				starting_ally_ships
			)
			ally_ships_remaining = starting_ally_ships
			defense_blocks_remaining = starting_defense_blocks
			GameManager.change_state(GameManager.GameState.PREPARATION, false)

func _ready() -> void:
	if not active:
		visible = false
		grid_ui.visible = false
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	var level_config := GameManager.get_selected_level_config()
	if is_instance_valid(level_config) and is_instance_valid(level_config.grid_board_config):
		board.config = level_config.grid_board_config
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	ally_ship_button.pressed.connect(begin_ally_ship_placement)
	defense_block_button.pressed.connect(begin_defense_block_placement)
	reset_button.pressed.connect(reset_prototype)
	start_button.pressed.connect(start_wave)
	return_button.visible = is_instance_valid(level_config) and level_config.level_number <= 0
	return_button.pressed.connect(return_to_first_level)
	defense_turret_button.pressed.connect(_begin_defense_turret_placement)
	laser_turret_button.pressed.connect(_begin_laser_turret_placement)
	turret_miner_button.pressed.connect(_begin_turret_miner_placement)
	GameManager.level_completed.connect(_on_level_completed)
	GameManager.state_changed.connect(_on_game_state_changed)
	if not standard_preparation_controller.layout_changed.is_connected(_on_turret_layout_changed):
		standard_preparation_controller.layout_changed.connect(_on_turret_layout_changed)
	rotation_hints.visible = false
	_enable_standard_preparation_ui()
	call_deferred("_enable_standard_preparation_ui")
	_sync_prototype_runtime_state()
	call_deferred("_sync_prototype_runtime_state")
	_set_status("Prepare the defense grid, then start the wave.")
	_update_ui()
	call_deferred("_restore_saved_layout")


func _exit_tree() -> void:
	if active and not wave_started:
		save_layout()

func _process(_delta: float) -> void:
	if not active:
		return
	if placement_mode == PlacementMode.PLACING and is_instance_valid(preview_actor):
		var pointer_world: Vector3 = project_mouse_to_world()
		preview_anchor_cell = board.world_to_cell(pointer_world)
		var footprint: Array[Vector2i] = _get_footprint_cells(
			selected_placeable_type,
			preview_anchor_cell,
			preview_orientation
		)
		var valid: bool = board.are_cells_available(footprint)
		board.set_highlight_cells(footprint, valid)
		if not footprint.is_empty() and board.is_cell_inside(preview_anchor_cell):
			_set_actor_transform(preview_actor, footprint, preview_orientation)
	else:
		board.clear_highlight()
	_update_rotation_hint_positions()
	_update_turret_ui()
	_sync_turret_status()

func _input(event: InputEvent) -> void:
	if not active:
		return
	if _handle_input_event(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if _handle_input_event(event):
		get_viewport().set_input_as_handled()

func _handle_input_event(event: InputEvent) -> bool:
	# PreparationController owns mouse input while a turret is being positioned
	# or aimed. The grid controller must not select ships or consume that click.
	if _is_turret_interaction_active():
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_A and (
				(placement_mode == PlacementMode.PLACING and selected_placeable_type == PlaceableType.ALLY_SHIP)
				or is_instance_valid(selected_ship)
			):
				_rotate_active_ship(-1)
				return true
			elif key_event.keycode == KEY_D and (
				(placement_mode == PlacementMode.PLACING and selected_placeable_type == PlaceableType.ALLY_SHIP)
				or is_instance_valid(selected_ship)
			):
				_rotate_active_ship(1)
				return true
		return false
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return false
	# A placed turret owns clicks on its own footprint. This lets the
	# PreparationController select/configure it before the grid can react.
	if _is_turret_at_screen_position(mouse_event.position):
		return false
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if placement_mode == PlacementMode.PLACING:
			_cancel_preview()
			_set_status("Placement cancelled. Select an object to continue.")
		else:
			_select_ship(null)
		return true
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	# The prototype UI is layered over the inherited production scene. Route
	# this critical action here so an ancestor Control or gameplay input handler
	# cannot swallow the click before Button.pressed is emitted.
	if is_instance_valid(start_button) and start_button.get_global_rect().has_point(mouse_event.position):
		if not start_button.disabled:
			start_wave()
		return true
	if _is_pointer_over_ui(mouse_event.position):
		return false
	var pointer_world: Vector3 = project_screen_to_world(mouse_event.position)
	if placement_mode == PlacementMode.PLACING:
		_commit_preview(board.world_to_cell(pointer_world))
	else:
		_select_ship(_find_ship_at(Vector2(pointer_world.x, pointer_world.z)))
	return true

func begin_ally_ship_placement() -> void:
	_begin_placement(PlaceableType.ALLY_SHIP)

func begin_defense_block_placement() -> void:
	_begin_placement(PlaceableType.DEFENSE_BLOCK)

func _begin_placement(placeable_type: PlaceableType) -> void:
	if not active or _get_remaining(placeable_type) <= 0:
		return
	_cancel_preview()
	_select_ship(null)
	selected_placeable_type = placeable_type
	preview_orientation = 0
	var scene: PackedScene = GridAllyShipScene if placeable_type == PlaceableType.ALLY_SHIP else GridDefenseBlockScene
	preview_actor = scene.instantiate()
	if not is_instance_valid(preview_actor):
		_set_status("Could not create the placement preview.")
		return
	if preview_actor is Barrier:
		var ship := preview_actor as Barrier
		ship.placed = false
		ship.previewing = true
		ally_ships_root.add_child(ship)
		# Production PreparationController scans the barrier group. Keep preview
		# ships out so its Start Wave button only unlocks for placed ships.
		ship.remove_from_group("barrier")
		ship.set_placed(false)
		ship.set_preview(true)
		ship.set_mount_spots_visible(false)
	else:
		var defense_block := preview_actor as GridDefenseBlock
		defense_block.placed = false
		defense_block.previewing = true
		grid_actors_root.add_child(defense_block)
		defense_block.set_placed(false)
		defense_block.set_preview(true)
	placement_mode = PlacementMode.PLACING
	if placeable_type == PlaceableType.ALLY_SHIP:
		_set_status("Ally Ship occupies two cells. A/D rotates; left-click places; right-click cancels.")
	else:
		_set_status("Brown Barrier occupies one cell. Left-click places; enemies can destroy it.")
	_update_ui()

func reset_prototype() -> void:
	if not active:
		return
	_cancel_preview()
	_select_ship(null)
	if is_instance_valid(standard_preparation_controller) and standard_preparation_controller.active:
		standard_preparation_controller.return_all_turrets()
	for actor in placed_actors.duplicate():
		_destroy_actor(actor as Node)
	placed_actors.clear()
	placed_ally_ships.clear()
	anchor_by_actor.clear()
	orientation_by_actor.clear()
	type_by_actor.clear()
	board.clear_occupancy()
	ally_ships_remaining = starting_ally_ships
	defense_blocks_remaining = starting_defense_blocks
	wave_started = false
	_set_status("Grid reset. Select an Ally Ship or Barrier to begin.")
	_update_ui()
	save_layout()

func start_wave() -> void:
	if not active:
		return
	if placed_ally_ships.size() < minimum_ally_ships_to_start:
		_set_status("Place at least %d Ally Ship(s) before starting the wave." % minimum_ally_ships_to_start)
		return
	_cancel_preview()
	_select_ship(null)
	var level_config := GameManager.get_selected_level_config()
	if not is_instance_valid(level_config):
		_set_status("Could not load the grid prototype level configuration.")
		return
	if is_instance_valid(standard_preparation_controller):
		standard_preparation_controller.commit_pending_layout_changes()
	save_layout()
	# Re-apply config here. This removes startup-order dependency on main.gd.
	spawner.set_level_config(level_config)
	_enter_gameplay_handoff()
	GameManager.begin_gameplay()
	# Spawner normally starts from state_changed. Explicit call makes this safe
	# when prototype scene entered after the signal connection window.
	if GameManager.current_state == GameManager.GameState.PLAYING:
		spawner.start_spawning()
		_sync_prototype_runtime_state()

func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state != GameManager.GameState.PLAYING or wave_started:
		return
	# Production PreparationController can also start the shared wave. Keep
	# prototype UI/spawner state synchronized when its Start Wave is clicked.
	_enter_gameplay_handoff()
	spawner.start_spawning()
	_sync_prototype_runtime_state()

func _enter_gameplay_handoff() -> void:
	save_layout()
	_cancel_preview()
	_select_ship(null)
	active = false
	wave_started = true
	spawner.set_start_blocked(false)
	board.clear_highlight()
	rotation_hints.visible = false
	grid_ui.visible = false

func _on_level_completed(level_number: int, _next_level_number: int) -> void:
	var config: LevelConfig = GameManager.get_selected_level_config()
	if not wave_started or not is_instance_valid(config) or config.level_number != level_number:
		return
	wave_started = false
	GameManager.end_round()

func return_to_first_level() -> void:
	save_layout()
	var loaded_resource: Resource = load(FIRST_LEVEL_CONFIG_PATH)
	if loaded_resource is LevelConfig:
		GameManager.start_level(loaded_resource as LevelConfig)

func get_placed_ship_count() -> int:
	return placed_ally_ships.size()

func get_placed_defense_block_count() -> int:
	var count: int = 0
	for actor in placed_actors:
		if is_instance_valid(actor) and actor is GridDefenseBlock:
			count += 1
	return count

func get_ships_remaining() -> int:
	return ally_ships_remaining

func get_defense_blocks_remaining() -> int:
	return defense_blocks_remaining

func rotate_selected_left() -> void:
	_rotate_active_ship(-1)

func rotate_selected_right() -> void:
	_rotate_active_ship(1)

func _commit_preview(anchor_cell: Vector2i) -> void:
	if not is_instance_valid(preview_actor):
		return
	var footprint: Array[Vector2i] = _get_footprint_cells(
		selected_placeable_type,
		anchor_cell,
		preview_orientation
	)
	if not board.are_cells_available(footprint):
		_set_status("Every required grid cell must be free and inside the board.")
		return
	var placed_actor: Node = preview_actor
	if not board.occupy_cells(footprint, placed_actor):
		return
	_set_actor_transform(placed_actor, footprint, preview_orientation)
	placed_actor.call("set_preview", false)
	placed_actor.call("set_placed", true)
	if placed_actor is Barrier:
		(placed_actor as Barrier).add_to_group("barrier")
	placed_actors.append(placed_actor)
	anchor_by_actor[placed_actor] = anchor_cell
	orientation_by_actor[placed_actor] = preview_orientation
	type_by_actor[placed_actor] = selected_placeable_type
	preview_actor = null
	placement_mode = PlacementMode.IDLE

	if selected_placeable_type == PlaceableType.ALLY_SHIP:
		var placed_ship := placed_actor as Barrier
		ally_ships_remaining -= 1
		placed_ally_ships.append(placed_ship)
		placed_ship.set_mount_spots_visible(true)
		placed_ship.health_changed.connect(_on_ally_ship_health_changed.bind(placed_ship))
		_select_ship(placed_ship)
		_set_status("Two-cell Ally Ship placed. A/D rotates it; select a turret to mount it.")
	else:
		var placed_block := placed_actor as GridDefenseBlock
		defense_blocks_remaining -= 1
		placed_block.destroyed.connect(_on_defense_block_destroyed)
		_set_status("Brown Barrier placed. It has 200 HP and occupies one cell.")
	_update_ui()
	save_layout()

func _rotate_active_ship(direction: int) -> void:
	if placement_mode == PlacementMode.PLACING and is_instance_valid(preview_actor):
		if selected_placeable_type != PlaceableType.ALLY_SHIP:
			return
		preview_orientation = posmod(preview_orientation + direction, 4)
		var footprint: Array[Vector2i] = _get_footprint_cells(
			PlaceableType.ALLY_SHIP,
			preview_anchor_cell,
			preview_orientation
		)
		if not footprint.is_empty():
			_set_actor_transform(preview_actor, footprint, preview_orientation)
		_set_status("Ally Ship preview rotated 90 degrees.")
		return
	if not is_instance_valid(selected_ship):
		return
	var current_anchor: Vector2i = anchor_by_actor.get(selected_ship, Vector2i(-1, -1))
	var current_orientation: int = int(orientation_by_actor.get(selected_ship, 0))
	var next_orientation := posmod(current_orientation + direction, 4)
	var next_footprint := _get_footprint_cells(
		PlaceableType.ALLY_SHIP,
		current_anchor,
		next_orientation
	)
	if not board.are_cells_available(next_footprint, selected_ship):
		_set_status("The Ally Ship cannot rotate because one of its cells is blocked.")
		return
	if not board.occupy_cells(next_footprint, selected_ship):
		return
	orientation_by_actor[selected_ship] = next_orientation
	_set_actor_transform(selected_ship, next_footprint, next_orientation)
	_set_status("Ally Ship rotated 90 degrees.")
	save_layout()

func _get_footprint_cells(
	placeable_type: PlaceableType,
	anchor_cell: Vector2i,
	orientation: int
) -> Array[Vector2i]:
	if placeable_type == PlaceableType.DEFENSE_BLOCK:
		return [anchor_cell]
	var direction: Vector2i
	match posmod(orientation, 4):
		1:
			direction = Vector2i(1, 0)
		2:
			direction = Vector2i(0, -1)
		3:
			direction = Vector2i(-1, 0)
		_:
			direction = Vector2i(0, 1)
	return [anchor_cell, anchor_cell + direction]

func _set_actor_transform(actor: Node, footprint: Array[Vector2i], orientation: int) -> void:
	if not is_instance_valid(actor) or footprint.is_empty():
		return
	var world_position := Vector3.ZERO
	for cell in footprint:
		world_position += board.cell_to_world(cell)
	world_position /= float(footprint.size())
	var yaw: float = float(posmod(orientation, 4)) * PI * 0.5
	actor.call("set_deployment_world_transform", world_position, yaw)

func _select_ship(ship: Barrier) -> void:
	selected_ship = ship if is_instance_valid(ship) and ship.active else null
	rotation_hints.visible = is_instance_valid(selected_ship)
	if is_instance_valid(selected_ship):
		_set_status("Ally Ship selected. Press A to rotate left or D to rotate right.")

func _find_ship_at(world_point: Vector2) -> Barrier:
	for index in range(placed_ally_ships.size() - 1, -1, -1):
		var ship: Barrier = placed_ally_ships[index]
		if is_instance_valid(ship) and ship.active and ship.contains_world_point(world_point):
			return ship
	return null

func project_mouse_to_world() -> Vector3:
	return project_screen_to_world(get_viewport().get_mouse_position())

func project_screen_to_world(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return Vector3(ray_origin.x, 0.0, ray_origin.z)
	var distance: float = -ray_origin.y / ray_direction.y
	return ray_origin + ray_direction * distance

func _update_rotation_hint_positions() -> void:
	if not is_instance_valid(selected_ship) or not rotation_hints.visible:
		return
	var ship_world_position: Vector3 = selected_ship.get_world_position() + Vector3(0.0, 18.0, 0.0)
	if camera.is_position_behind(ship_world_position):
		rotation_hints.visible = false
		return
	rotation_hints.visible = true
	var ship_screen_position: Vector2 = camera.unproject_position(ship_world_position)
	left_hint.position = ship_screen_position + Vector2(-92.0, -28.0)
	right_hint.position = ship_screen_position + Vector2(52.0, -28.0)

func _is_turret_at_screen_position(screen_position: Vector2) -> bool:
	var pointer_world := project_screen_to_world(screen_position)
	var pointer := Vector2(pointer_world.x, pointer_world.z)
	for ship in placed_ally_ships:
		if not is_instance_valid(ship):
			continue
		for turret_variant in ship.turrets:
			if is_instance_valid(turret_variant) and turret_variant.has_method("contains_world_point"):
				if turret_variant.contains_world_point(pointer):
					return true
	return false

func _is_pointer_over_ui(screen_position: Vector2) -> bool:
	var top_panel := grid_ui.get_node("TopPanel") as Control
	var footer := grid_ui.get_node("Footer") as Control
	var standard_panel := standard_preparation_footer.get_node_or_null("Panel") as Control
	var over_standard_footer: bool = (
		is_instance_valid(standard_panel)
		and standard_panel.visible
		and standard_panel.get_global_rect().has_point(screen_position)
	)
	return (
		top_panel.get_global_rect().has_point(screen_position)
		or footer.get_global_rect().has_point(screen_position)
		or over_standard_footer
	)

func _is_turret_interaction_active() -> bool:
	return (
		is_instance_valid(standard_preparation_controller)
		and standard_preparation_controller.active
		and standard_preparation_controller.placement_mode != PreparationController.PlacementMode.NONE
	)

func _cancel_preview() -> void:
	if is_instance_valid(preview_actor):
		_destroy_actor(preview_actor)
	preview_actor = null
	placement_mode = PlacementMode.IDLE
	_update_ui()

func _destroy_actor(actor: Node) -> void:
	if not is_instance_valid(actor):
		return
	board.release_occupant(actor)
	if actor is Barrier:
		var ship := actor as Barrier
		ship.clear_turrets()
		if is_instance_valid(ship.visual_3d):
			ship.visual_3d.queue_free()
	actor.queue_free()

func _on_defense_block_destroyed(block: GridDefenseBlock) -> void:
	board.release_occupant(block)
	placed_actors.erase(block)
	anchor_by_actor.erase(block)
	orientation_by_actor.erase(block)
	type_by_actor.erase(block)

func _on_ally_ship_health_changed(current_hp: float, _maximum_hp: float, ship: Barrier) -> void:
	if current_hp > 0.0:
		return
	board.release_occupant(ship)
	if selected_ship == ship:
		_select_ship(null)

func _get_remaining(placeable_type: PlaceableType) -> int:
	return ally_ships_remaining if placeable_type == PlaceableType.ALLY_SHIP else defense_blocks_remaining

func _enable_standard_preparation_ui() -> void:
	var default_controller := standard_preparation_controller
	if is_instance_valid(default_controller):
		default_controller.process_mode = Node.PROCESS_MODE_ALWAYS
		default_controller.set_process_input(true)
		default_controller.set_process_unhandled_input(true)
		var state_callback := Callable(default_controller, "_on_state_changed")
		if not GameManager.state_changed.is_connected(state_callback):
			GameManager.state_changed.connect(state_callback)
	if is_instance_valid(standard_preparation_footer):
		# The grid footer is the only preparation footer in this prototype.
		standard_preparation_footer.process_mode = Node.PROCESS_MODE_DISABLED
		standard_preparation_footer.visible = false

func _sync_prototype_runtime_state() -> void:
	if is_instance_valid(standard_preparation_footer):
		standard_preparation_footer.process_mode = Node.PROCESS_MODE_DISABLED
		standard_preparation_footer.visible = false
	if is_instance_valid(spawner):
		# Never reset Spawner after wave started: set_level_config() clears its
		# batch counters and would silently stop an active wave.
		if not wave_started:
			var level_config := GameManager.get_selected_level_config()
			if is_instance_valid(level_config):
				spawner.set_level_config(level_config)
			spawner.set_start_blocked(true)
		else:
			spawner.set_start_blocked(false)
	if is_instance_valid(player_cursor) and player_cursor.has_method("refresh_state"):
		player_cursor.refresh_state()

func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message

func _update_ui() -> void:
	if inventory_label:
		inventory_label.text = "ALLY SHIPS: %d    BARRIERS: %d    TURRETS: %d / %d / %d" % [
			ally_ships_remaining,
			defense_blocks_remaining,
			standard_preparation_controller.get_available_turrets() if is_instance_valid(standard_preparation_controller) else 0,
			standard_preparation_controller.get_available_laser_turrets() if is_instance_valid(standard_preparation_controller) else 0,
			standard_preparation_controller.get_available_turret_miners() if is_instance_valid(standard_preparation_controller) else 0
		]
	if ally_ship_button:
		ally_ship_button.text = "ALLY SHIP (2 CELLS)  x%d" % ally_ships_remaining
		ally_ship_button.disabled = ally_ships_remaining <= 0 or not active
	if defense_block_button:
		defense_block_button.text = "BARRIER (1 CELL)  x%d" % defense_blocks_remaining
		defense_block_button.disabled = defense_blocks_remaining <= 0 or not active
	if start_button:
		start_button.disabled = not active or placed_ally_ships.size() < minimum_ally_ships_to_start
	_update_turret_ui()

func _begin_defense_turret_placement() -> void:
	if is_instance_valid(standard_preparation_controller):
		standard_preparation_controller.begin_turret_placement()

func _begin_laser_turret_placement() -> void:
	if is_instance_valid(standard_preparation_controller):
		standard_preparation_controller.begin_laser_turret_placement()

func _begin_turret_miner_placement() -> void:
	if is_instance_valid(standard_preparation_controller):
		standard_preparation_controller.begin_turret_miner_placement()

func _update_turret_ui() -> void:
	if not is_instance_valid(standard_preparation_controller):
		return
	# Refresh the production controller's barrier scan because its footer is hidden.
	standard_preparation_controller.get_barrier_count()
	var can_mount: bool = not placed_ally_ships.is_empty()
	var defense_unlocked := standard_preparation_controller.is_defense_blaster_unlocked()
	var laser_unlocked := standard_preparation_controller.is_laser_turret_unlocked()
	var miner_unlocked := standard_preparation_controller.is_turret_miner_unlocked()
	var defense_available := standard_preparation_controller.get_available_turrets()
	var laser_available := standard_preparation_controller.get_available_laser_turrets()
	var miner_available := standard_preparation_controller.get_available_turret_miners()
	if inventory_label:
		inventory_label.text = "ALLY SHIPS: %d    BARRIERS: %d    TURRETS: %d / %d / %d" % [
			ally_ships_remaining, defense_blocks_remaining,
			defense_available, laser_available, miner_available
		]
	defense_turret_button.text = ("DEFENSE BLASTER  x%d" % defense_available) if defense_unlocked else "DEFENSE BLASTER  LOCKED"
	laser_turret_button.text = ("LASER TURRET  x%d" % laser_available) if laser_unlocked else "LASER TURRET  LOCKED"
	turret_miner_button.text = ("TURRET MINER  x%d" % miner_available) if miner_unlocked else "TURRET MINER  LOCKED"
	defense_turret_button.disabled = not active or not can_mount or not defense_unlocked or defense_available <= 0
	laser_turret_button.disabled = not active or not can_mount or not laser_unlocked or laser_available <= 0
	turret_miner_button.disabled = not active or not can_mount or not miner_unlocked or miner_available <= 0

func _sync_turret_status() -> void:
	if not active or not is_instance_valid(standard_preparation_controller):
		return
	match standard_preparation_controller.placement_mode:
		PreparationController.PlacementMode.POSITIONING:
			_set_status("Turret selected. Click an empty mount on an Ally Ship; right-click cancels.")
		PreparationController.PlacementMode.AIMING:
			_set_status("Aim the turret cone. Drag the handle; left-click confirms; right-click cancels.")


func save_layout() -> bool:
	if _layout_io_suspended or not GridLayoutStoreScript.is_available():
		return false
	var layout_key := _get_layout_key()
	if layout_key.is_empty():
		return false
	var actor_entries: Array = []
	for actor in placed_actors:
		if not is_instance_valid(actor) or not anchor_by_actor.has(actor):
			continue
		var placeable_type: int = int(type_by_actor.get(actor, PlaceableType.DEFENSE_BLOCK))
		var anchor: Vector2i = anchor_by_actor[actor] as Vector2i
		var entry := {
			"type": "ally_ship" if placeable_type == PlaceableType.ALLY_SHIP else "defense_block",
			"anchor": {"x": anchor.x, "y": anchor.y},
			"orientation": int(orientation_by_actor.get(actor, 0)),
		}
		if actor is Barrier:
			entry["turrets"] = _serialize_ship_turrets(actor as Barrier)
		actor_entries.append(entry)
	var layout := {
		"actors": actor_entries,
	}
	return GridLayoutStoreScript.save_layout(layout_key, layout) == OK


func restore_saved_layout() -> bool:
	return await _restore_saved_layout()


func _restore_saved_layout() -> bool:
	if not active or _layout_io_suspended or not GridLayoutStoreScript.is_available():
		return false
	var layout_key := _get_layout_key()
	if layout_key.is_empty() or not GridLayoutStoreScript.has_layout(layout_key):
		return false
	var layout := GridLayoutStoreScript.load_layout(layout_key)
	var actor_variants: Variant = layout.get("actors", [])
	if not actor_variants is Array:
		return false

	_layout_io_suspended = true
	_clear_deployed_layout_for_restore()
	var pending_turrets: Array = []
	var restored_turret_count: int = 0
	for actor_variant in actor_variants as Array:
		if not actor_variant is Dictionary:
			continue
		var entry := actor_variant as Dictionary
		var restored_actor := _restore_actor_entry(entry)
		if not restored_actor is Barrier:
			continue
		var turret_variants: Variant = entry.get("turrets", [])
		if turret_variants is Array:
			pending_turrets.append({"ship": restored_actor, "turrets": turret_variants})

	# Barrier visuals define the authored mount offsets and are added deferred.
	# Wait one frame before mounting turrets so restored slots match those visuals.
	await get_tree().process_frame
	for pending_variant in pending_turrets:
		var pending := pending_variant as Dictionary
		var ship := pending.get("ship") as Barrier
		if not is_instance_valid(ship):
			continue
		for turret_variant in pending.get("turrets", []) as Array:
			if turret_variant is Dictionary and _restore_turret_entry(
				ship,
				turret_variant as Dictionary
			):
				restored_turret_count += 1
	_layout_io_suspended = false
	_select_ship(null)
	_set_status("Saved defense layout restored. You can edit it or start the wave.")
	_update_ui()
	layout_restored.emit(placed_actors.size(), restored_turret_count)
	return true


func _clear_deployed_layout_for_restore() -> void:
	_cancel_preview()
	_select_ship(null)
	if is_instance_valid(standard_preparation_controller):
		standard_preparation_controller.prepare_inventory_for_layout_restore()
	for actor in placed_actors.duplicate():
		_destroy_actor(actor as Node)
	placed_actors.clear()
	placed_ally_ships.clear()
	anchor_by_actor.clear()
	orientation_by_actor.clear()
	type_by_actor.clear()
	board.clear_occupancy()
	ally_ships_remaining = starting_ally_ships
	defense_blocks_remaining = starting_defense_blocks


func _restore_actor_entry(entry: Dictionary) -> Node:
	var type_name := String(entry.get("type", ""))
	var placeable_type: PlaceableType
	match type_name:
		"ally_ship":
			placeable_type = PlaceableType.ALLY_SHIP
		"defense_block":
			placeable_type = PlaceableType.DEFENSE_BLOCK
		_:
			return null
	var anchor_data: Variant = entry.get("anchor", {})
	if not anchor_data is Dictionary:
		return null
	var anchor_dictionary := anchor_data as Dictionary
	var anchor := Vector2i(
		int(anchor_dictionary.get("x", -1)),
		int(anchor_dictionary.get("y", -1))
	)
	var actor_count_before := placed_actors.size()
	_begin_placement(placeable_type)
	if not is_instance_valid(preview_actor):
		return null
	preview_orientation = posmod(int(entry.get("orientation", 0)), 4)
	_commit_preview(anchor)
	if placed_actors.size() <= actor_count_before:
		_cancel_preview()
		return null
	return placed_actors[-1]


func _restore_turret_entry(ship: Barrier, entry: Dictionary) -> bool:
	if not is_instance_valid(standard_preparation_controller):
		return false
	return standard_preparation_controller.restore_turret_configuration(
		ship,
		String(entry.get("type", "defense_blaster")),
		int(entry.get("mount_slot", -1)),
		float(entry.get("center_yaw", 0.0)),
		float(entry.get("cone_angle", 90.0))
	)


func _serialize_ship_turrets(ship: Barrier) -> Array:
	var result: Array = []
	for turret_variant in ship.turrets:
		var turret := turret_variant as DefenseBlaster
		if not is_instance_valid(turret):
			continue
		var mount_slot := _get_turret_mount_slot(ship, turret)
		if mount_slot < 0:
			continue
		result.append({
			"type": turret.get_turret_type_id(),
			"mount_slot": mount_slot,
			"center_yaw": turret.get_center_yaw(),
			"cone_angle": turret.get_cone_angle(),
		})
	return result


func _get_turret_mount_slot(ship: Barrier, turret: DefenseBlaster) -> int:
	for slot_index in range(Barrier.MAX_TURRETS):
		if turret.local_offset.is_equal_approx(ship.get_mount_slot_offset(slot_index)):
			return slot_index
	return -1


func _get_layout_key() -> String:
	if not is_instance_valid(GameManager):
		return ""
	if not GameManager.selected_level_config_path.is_empty():
		return GameManager.selected_level_config_path
	var level_config := GameManager.get_selected_level_config()
	return level_config.resource_path if is_instance_valid(level_config) else ""


func _on_turret_layout_changed() -> void:
	if active and not wave_started:
		save_layout()
