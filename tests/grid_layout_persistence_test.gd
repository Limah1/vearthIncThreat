extends Node

const GridLayoutStoreScript = preload("res://src/core/grid_layout_store.gd")

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GridLayoutStoreScript.storage_path = "user://grid_layout_persistence_test.json"
	GridLayoutStoreScript.allow_headless = true
	var config := load("res://src/prototypes/mass_enemies/MassEnemyPlayable5000Config.tres") as LevelConfig
	var layout_key := config.resource_path
	GridLayoutStoreScript.clear_layout(layout_key)
	_select_level(config)

	var first_level := config.level_scene.instantiate() as Node3D
	add_child(first_level)
	await get_tree().process_frame
	await get_tree().process_frame
	var first_controller := first_level.get_node("GridCombatController") as GridCombatController
	var first_preparation := first_level.get_node("PreparationController") as PreparationController

	first_controller.begin_ally_ship_placement()
	first_controller.preview_orientation = 3
	first_controller._commit_preview(Vector2i(2, 2))
	first_controller.begin_defense_block_placement()
	first_controller._commit_preview(Vector2i(0, 0))
	var first_ship := first_controller.placed_ally_ships[0]
	_expect(
		first_preparation.restore_turret_configuration(first_ship, "defense_blaster", 1, 0.75, 60.0),
		"Fixture turret must attach before saving."
	)
	_expect(first_controller.save_layout(), "Layout must be written to the dedicated save file.")

	# Clean the nested test scene without replacing the saved fixture with an empty layout.
	first_controller._layout_io_suspended = true
	first_controller.reset_prototype()
	first_level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	_select_level(config)
	var restored_level := config.level_scene.instantiate() as Node3D
	add_child(restored_level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var restored := restored_level.get_node("GridCombatController") as GridCombatController
	var restored_preparation := restored_level.get_node("PreparationController") as PreparationController

	_expect(restored.get_placed_ship_count() == 1, "Saved Ally Ship must be restored.")
	_expect(restored.get_placed_defense_block_count() == 1, "Saved Barrier must be restored.")
	_expect(restored.get_ships_remaining() == 9, "Restored ship must consume its inventory unit.")
	_expect(restored.get_defense_blocks_remaining() == 2, "Restored Barrier must consume its inventory unit.")
	if not restored.placed_ally_ships.is_empty():
		var ship := restored.placed_ally_ships[0]
		_expect(restored.anchor_by_actor.get(ship) == Vector2i(2, 2), "Ship anchor cell must round-trip.")
		_expect(int(restored.orientation_by_actor.get(ship, -1)) == 3, "Ship orientation must round-trip.")
		_expect(ship.turrets.size() == 1, "Mounted turret must be restored.")
		if ship.turrets.size() == 1:
			var turret := ship.turrets[0] as DefenseBlaster
			_expect(turret.local_offset.is_equal_approx(ship.get_mount_slot_offset(1)), "Turret mount slot must round-trip.")
			_expect(is_equal_approx(turret.get_center_yaw(), 0.75), "Turret aim direction must round-trip.")
			_expect(is_equal_approx(turret.get_cone_angle(), 60.0), "Turret cone angle must round-trip.")
	_expect(restored_preparation.get_available_turrets() == 19, "Restored turret must consume inventory.")

	restored.reset_prototype()
	var empty_layout := GridLayoutStoreScript.load_layout(layout_key)
	_expect((empty_layout.get("actors", []) as Array).is_empty(), "Reset must persist an empty layout.")
	restored._layout_io_suspended = true
	restored_level.queue_free()
	GridLayoutStoreScript.clear_layout(layout_key)
	GridLayoutStoreScript.storage_path = GridLayoutStoreScript.DEFAULT_STORAGE_PATH
	GridLayoutStoreScript.allow_headless = false

	if failures == 0:
		print("Grid layout persistence tests passed.")
	else:
		push_error("Grid layout persistence tests failed: %d" % failures)
	get_tree().quit(failures)


func _select_level(config: LevelConfig) -> void:
	GameManager.selected_level_config = config
	GameManager.selected_level_config_path = config.resource_path
	GameManager.current_zone = config.level_number
	GameManager.change_state(GameManager.GameState.PREPARATION, false)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
