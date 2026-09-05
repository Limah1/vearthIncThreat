extends Node

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := load("res://src/resources/levels/FirstLevelConfig.tres") as LevelConfig
	var original_total := original.total_enemies
	var launcher: Node = load("res://src/prototypes/mass_enemies/MassEnemyPlayable5000.tscn").instantiate()
	add_child(launcher)
	await get_tree().process_frame
	var config := GameManager.get_selected_level_config()
	_expect(config.total_enemies == 10000 and config.use_mass_enemies and config.use_gpu_enemy_simulation, "Playable entry must select the dedicated 10,000 GPU config.")
	_expect(config.use_mass_legacy_rules and config.use_mass_enemy_feedback and not config.mass_planet_invulnerable and not config.show_in_level_select, "Playtest must enable legacy rules/feedback and planet damage without publishing a campaign level.")
	_expect(GameManager.current_state == GameManager.GameState.PREPARATION, "Playtest must use normal preparation, not auto-start all enemies.")
	var level: Node = launcher.get_child(0)
	var controller := level.get_node("GridCombatController") as GridCombatController
	var preparation := level.get_node("PreparationController") as PreparationController
	_expect(controller.get_ships_remaining() == 10, "Playtest must provide ten Ally Ships.")
	_expect(preparation.get_available_turrets() == 20, "Playtest must provide twenty unlocked Defense Blasters.")
	controller.begin_ally_ship_placement()
	controller._commit_preview(Vector2i(7, 2))
	controller.start_button.pressed.emit()
	var spawner := level.get_node("Spawner") as Spawner
	var runtime := spawner.mass_runtime
	_expect(config.mass_gpu_separation and config.mass_spawn_spread_radius > 0, "Playtest must enable spawn dispersion and GPU separation.")
	if runtime.combat is EnemyGPUCombat:
		_expect(runtime.combat.separation_enabled, "Runtime must forward the playtest separation setting to GPU combat.")
	var planet := GameManager.get_player_planet() as PlayerPlanet
	var planet_hp_before := planet.hp
	runtime._on_combat_events(0, 0, 0, 25, {})
	_expect(is_equal_approx(planet.hp, planet_hp_before - 25.0), "The 10,000 playtest must apply mass-enemy planet damage.")
	runtime.combat.simulation_enabled = false
	runtime.spawner.set_process(false)
	_expect(runtime.world.get_active_count() == 0, "First batch must wait for interval.")
	runtime.spawner.advance_spawning(1)
	_expect(runtime.spawner.spawned_enemy_count == 1024, "First cycle must respect the per-frame command budget.")
	for i in range(3):
		runtime.spawner.advance_spawning(0)
	_expect(runtime.spawner.spawned_enemy_count == 2500, "50 points must each produce 50 per cycle.")
	runtime.spawner.advance_spawning(1)
	for i in range(3):
		runtime.spawner.advance_spawning(0)
	_expect(runtime.world.get_active_count() == 5000 and not runtime.spawner.is_spawn_complete(), "Second cycle must reach 5,000 without ending the 10,000 spawn.")
	for cycle in range(2):
		runtime.spawner.advance_spawning(1)
		for i in range(3):
			runtime.spawner.advance_spawning(0)
	_expect(runtime.world.get_active_count() == 10000 and runtime.spawner.is_spawn_complete(), "Fourth cycle must reach exactly 10,000 without a combat step.")
	var spawned_archetypes: Dictionary = {}
	for index in range(runtime.world.get_active_count()):
		var slot := runtime.world.get_active_slot(index)
		spawned_archetypes[runtime.world.get_archetype(runtime.world.archetype_indices[slot]).enemy_id] = true
	_expect(spawned_archetypes.size() == 1 and spawned_archetypes.has(&"asteroid_small"), "Playtest must spawn only small asteroids.")
	_expect(runtime.world.get_child_count() == 0, "No enemy Nodes may be created in the World.")
	_expect(original.total_enemies == original_total and not original.use_mass_enemies and not original.mass_planet_invulnerable, "Published campaign config must remain unchanged.")
	GameManager.change_state(GameManager.GameState.PREPARATION)
	launcher.queue_free()
	for i in range(4):
		await get_tree().process_frame
	if failures == 0:
		print("Mass playable tests passed.")
	get_tree().quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
