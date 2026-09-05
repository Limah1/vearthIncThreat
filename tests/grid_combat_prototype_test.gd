extends Node

const PrototypeScene: PackedScene = preload("res://src/prototypes/grid_combat/GridCombatPrototype.tscn")
const ProductionGridScene: PackedScene = preload("res://src/levels/GridCombatLevel.tscn")
const DamageSystemScript = preload("res://src/core/damage_system.gd")

var failures: int = 0

func _ready() -> void:
	# When this scene is played from the editor, behave as an interactive
	# prototype launcher. Automated placement/completion is reserved for the
	# headless test runner so it cannot take control away from the player.
	if DisplayServer.get_name() != "headless":
		var interactive_prototype := PrototypeScene.instantiate() as Node3D
		add_child(interactive_prototype)
		return

	var first_level_resource: Resource = load("res://src/resources/levels/FirstLevelConfig.tres")
	_expect(first_level_resource is LevelConfig, "Level 1 must use a valid LevelConfig.")
	if not first_level_resource is LevelConfig:
		get_tree().quit(1)
		return
	var first_level_config := first_level_resource as LevelConfig
	_expect(first_level_config.grid_combat_enabled, "Level 1 must enable production grid combat.")
	_expect(first_level_config.level_scene == ProductionGridScene, "Level 1 must load the production grid-combat scene.")
	_expect(first_level_config.starting_ally_ships == 4, "Level 1 must configure four Ally Ships.")
	var second_level_resource: Resource = load("res://src/resources/levels/SecondtLevelConfig.tres")
	_expect(second_level_resource is LevelConfig, "Level 2 must use a valid LevelConfig.")
	if second_level_resource is LevelConfig:
		var second_level_config := second_level_resource as LevelConfig
		_expect(second_level_config.grid_combat_enabled, "Level 2 must enable production grid combat.")
		_expect(second_level_config.starting_ally_ships == 5, "Level 2 must configure its own grid inventory.")
	GameManager.selected_level_config = first_level_config
	GameManager.selected_level_config_path = first_level_config.resource_path
	GameManager.current_zone = first_level_config.level_number
	GameManager.change_state(GameManager.GameState.PREPARATION, false)

	var prototype_scene_root := first_level_config.level_scene.instantiate() as Node3D
	add_child(prototype_scene_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var prototype := prototype_scene_root.get_node("GridCombatController") as GridCombatController

	_expect(is_instance_valid(prototype), "The production gameplay scene must contain the grid controller.")
	_expect(
		GameManager.selected_level_config_path == "res://src/resources/levels/FirstLevelConfig.tres",
		"Production grid combat must preserve the level selected by the player."
	)
	_expect(GameManager.current_state == GameManager.GameState.PREPARATION, "Grid gameplay must begin in preparation.")
	var damage_cursor := prototype_scene_root.get_node("PlayerCursor") as PlayerCursor
	await get_tree().process_frame
	_expect(not damage_cursor.mouse_circle_visual.visible, "Preparation must use the normal mouse cursor without the damage circle.")
	_expect(damage_cursor.preparation_cursor_active, "Preparation must use the white triangular placement cursor.")
	_expect(not prototype_scene_root.get_node("CanvasLayer/PreparationFooter").visible, "The production preparation footer must stay hidden in the grid prototype.")
	_expect(prototype.get_ships_remaining() == 4, "Prototype must begin with four Ally Ships.")
	_expect(prototype.get_defense_blocks_remaining() == 3, "Prototype must begin with three Barriers.")
	_expect(not is_instance_valid(prototype.preview_actor), "The player must select which object to place first.")
	_expect(prototype.start_button.disabled, "Start Wave must remain disabled until the required Ally Ship is placed.")
	_expect(not prototype.board.is_cell_available(Vector2i(4, 2)), "Planet cells must reject placement.")
	var spawner := prototype_scene_root.get_node("Spawner") as Spawner
	_expect(spawner.start_blocked, "The prototype spawner must be explicitly blocked during preparation.")
	spawner.start_level(GameManager.get_selected_level_config())
	await get_tree().create_timer(1.1).timeout
	_expect(spawner.get_spawned_actor_count() == 0, "Preparation must never spawn enemies, even if the spawner receives a start request.")

	prototype.ally_ship_button.pressed.emit()
	var ship_click := InputEventMouseButton.new()
	ship_click.button_index = MOUSE_BUTTON_LEFT
	ship_click.pressed = true
	ship_click.position = prototype.camera.unproject_position(prototype.board.cell_to_world(Vector2i(2, 2)))
	prototype._input(ship_click)
	await get_tree().process_frame
	_expect(prototype.get_placed_ship_count() == 1, "A valid click must place one Ally Ship.")
	_expect(prototype.get_ships_remaining() == 3, "Placing a ship must consume one inventory unit.")
	var placed_ship: Barrier = prototype.placed_ally_ships[0]
	var occupied_ship_cells: Array[Vector2i] = prototype.board.get_occupant_cells(placed_ship)
	_expect(occupied_ship_cells.size() == 2, "A grid Ally Ship must occupy exactly two cells.")
	_expect(not prototype.board.is_cell_available(Vector2i(2, 2)), "The Ally Ship anchor cell must be occupied.")
	_expect(not prototype.board.is_cell_available(Vector2i(2, 3)), "The Ally Ship second cell must be occupied.")

	prototype._select_ship(null)
	var select_ship_click := InputEventMouseButton.new()
	select_ship_click.button_index = MOUSE_BUTTON_LEFT
	select_ship_click.pressed = true
	select_ship_click.position = prototype.camera.unproject_position(placed_ship.get_world_position())
	prototype._input(select_ship_click)
	_expect(prototype.selected_ship == placed_ship, "Clicking a placed Ally Ship must select it for rotation.")
	var original_yaw: float = placed_ship.world_yaw
	prototype.rotate_selected_left()
	_expect(not is_equal_approx(placed_ship.world_yaw, original_yaw), "A must rotate the selected Ally Ship.")
	_expect(prototype.rotation_hints.visible, "Selecting an Ally Ship must show the A/D hints.")
	_expect(prototype.board.is_cell_available(Vector2i(2, 3)), "Rotation must release the old second cell.")
	_expect(not prototype.board.is_cell_available(Vector2i(1, 2)), "Rotation must occupy the new second cell.")

	prototype.defense_block_button.pressed.emit()
	var barrier_click := InputEventMouseButton.new()
	barrier_click.button_index = MOUSE_BUTTON_LEFT
	barrier_click.pressed = true
	barrier_click.position = prototype.camera.unproject_position(prototype.board.cell_to_world(Vector2i(0, 0)))
	prototype._input(barrier_click)
	await get_tree().process_frame
	_expect(prototype.get_placed_defense_block_count() == 1, "A brown Barrier must occupy one cell.")
	_expect(prototype.get_defense_blocks_remaining() == 2, "Placing a Barrier must consume one inventory unit.")
	var defense_block: GridDefenseBlock = null
	for actor in prototype.placed_actors:
		if actor is GridDefenseBlock:
			defense_block = actor as GridDefenseBlock
			break
	_expect(is_instance_valid(defense_block), "The placed Barrier must use the destructible grid actor.")
	if is_instance_valid(defense_block):
		_expect(defense_block.maximum_hp == 200.0 and defense_block.hp == 200.0, "Every placed grid Barrier must start with 200 HP.")
		_expect(
			GameManager.get_barrier_collision(defense_block.global_position, 0.0) == defense_block,
			"Production asteroid collision queries must find the brown Barrier."
		)
		defense_block.receive_damage(200.0, DamageSystemScript.Team.ENEMY)
	await get_tree().process_frame
	_expect(prototype.board.is_cell_available(Vector2i(0, 0)), "A destroyed Barrier must release its cell.")

	prototype.reset_prototype()
	prototype.begin_ally_ship_placement()
	prototype._commit_preview(Vector2i(7, 2))
	_expect(not prototype.start_button.disabled, "Start Wave must be enabled after placing an Ally Ship.")
	var start_click := InputEventMouseButton.new()
	start_click.button_index = MOUSE_BUTTON_LEFT
	start_click.pressed = true
	start_click.position = prototype.start_button.get_global_rect().get_center()
	prototype._input(start_click)
	await get_tree().process_frame
	_expect(GameManager.current_state == GameManager.GameState.PLAYING, "Start Wave must enter production gameplay.")
	_expect(not damage_cursor.preparation_cursor_active, "The preparation cursor must be removed when gameplay starts.")
	_expect(not prototype.grid_ui.visible, "Grid preparation controls must hide when gameplay starts.")
	_expect(not spawner.start_blocked, "Start Wave must release the prototype spawn gate.")
	_expect(spawner.get_spawned_actor_count() > 0, "The production spawner must spawn the grid level's asteroids.")

	var lifetime_before_completion: float = GameManager.lifetime_credits
	GameManager.run_credits = 7.0
	for _enemy_index in range(GameManager.get_current_level_total_enemies()):
		GameManager.register_eliminated_threat()
	await get_tree().process_frame
	_expect(GameManager.current_state == GameManager.GameState.END_SESSION, "Clearing the wave must open the balance summary state.")
	_expect(prototype_scene_root.get_node("CanvasLayer/PauseOverlay").visible, "The balance summary must be visible after clearing the wave.")
	_expect(GameManager.lifetime_credits == lifetime_before_completion + 7.0, "Wave credits must be banked before the balance summary opens.")

	if failures == 0:
		print("Grid combat prototype tests passed.")
	else:
		push_error("Grid combat prototype tests failed: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
