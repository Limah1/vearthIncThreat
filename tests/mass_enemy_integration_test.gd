extends Node

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := load("res://src/resources/levels/FirstLevelConfig.tres").duplicate() as LevelConfig
	config.use_mass_enemies = true
	config.total_enemies = 350
	config.enemies_per_spawn_point = 2
	config.spawn_interval_seconds = 1.0
	GameManager.selected_level_config = config
	GameManager.run_credits = 0
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.change_state(GameManager.GameState.PREPARATION, false)
	var level := config.level_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var controller := level.get_node("GridCombatController") as GridCombatController
	var spawner := level.get_node("Spawner") as Spawner
	controller.begin_ally_ship_placement()
	controller._commit_preview(Vector2i(7, 2))
	controller.start_button.pressed.emit()
	await get_tree().process_frame
	_expect(GameManager.current_state == GameManager.GameState.PLAYING, "Production preparation must start mass gameplay.")
	_expect(is_instance_valid(spawner.mass_runtime), "Production Spawner must create MassEnemyRuntime when opted in.")
	if not is_instance_valid(spawner.mass_runtime):
		get_tree().quit(1)
		return
	var runtime := spawner.mass_runtime
	runtime.spawner.set_process(false)
	runtime.combat.simulation_enabled = false
	for group in ["asteroid_master", "enemy_master"]:
		for master in get_tree().get_nodes_in_group(group):
			_expect(master.get_child_count() == 0, "Mass mode must skip legacy enemy Node pools.")
	_expect(runtime.world.get_active_count() == 0, "Mass mode must wait for the first spawn interval.")
	runtime.spawner.advance_spawning(1.0)
	var count := runtime.world.get_active_count()
	_expect(count == spawner.spawn_points.size() * 2, "Each point must emit the configured batch at the interval.")
	var handle := runtime.world.get_active_handle(0)
	var before := runtime.world.positions[handle & EnemyWorld.SLOT_MASK]
	GameManager.change_state(GameManager.GameState.PAUSED)
	runtime.combat.step(1)
	runtime.spawner.advance_spawning(10)
	_expect(runtime.world.get_active_count() == count, "Pause must preserve every active enemy and spawn count.")
	_expect(runtime.world.positions[handle & EnemyWorld.SLOT_MASK] == before, "Paused simulation must not move enemies.")
	GameManager.change_state(GameManager.GameState.PLAYING)
	runtime.world.reset_world()
	runtime.combat.reset_combat()
	var data: EnemyData = config.enemy_roster[0].enemy
	var first := runtime.world.request_spawn(data, Vector3(0, 0, 100))
	var second := runtime.world.request_spawn(data, Vector3(0, 0, 200))
	var blaster := load("res://src/entities/defense_blaster.tscn").instantiate() as DefenseBlaster
	add_child(blaster)
	blaster.set_process(false)
	blaster._fire_mass(Vector3(0, 0, 100))
	_expect(runtime.combat.shot_count == 1, "Real blaster must emit a pooled data projectile.")
	_expect(runtime.combat.shot_radii[0] == 9.0, "Defense Blaster projectile collision radius must be 50 percent larger.")
	runtime.combat._update_projectiles(0.5)
	_expect(runtime.world.health[first & EnemyWorld.SLOT_MASK] < data.max_hp, "Blaster projectile must damage the nearest mass enemy.")
	var laser := load("res://src/entities/laser_turret.tscn").instantiate() as LaserTurret
	add_child(laser)
	laser.set_process(false)
	laser.effective_damage = 100
	laser._fire_mass(Vector3(0, 0, 100))
	_expect(not runtime.world.is_handle_valid(first) and not runtime.world.is_handle_valid(second), "Real laser must pierce both mass enemies.")
	var mine_target := runtime.world.request_spawn(data, Vector3(100, 0, 100))
	var miner := load("res://src/entities/turret_miner.tscn").instantiate() as TurretMiner
	add_child(miner)
	miner.set_process(false)
	miner.effective_damage = 100
	miner.mine_end_positions[0] = Vector3(100, 0, 100)
	miner._explode_mine(0)
	_expect(not runtime.world.is_handle_valid(mine_target), "Real mine must damage mass enemies by area.")
	var credits_before := GameManager.run_credits
	runtime.combat.flush_combat_events()
	_expect(GameManager.eliminated_threats == 3, "Aggregated kills must enter production progress exactly once.")
	_expect(is_equal_approx(GameManager.run_credits - credits_before, data.credit_value * 3), "Production credits must match killed archetypes.")
	runtime.combat.flush_combat_events()
	_expect(GameManager.eliminated_threats == 3, "Repeated flush must not duplicate progress.")
	runtime._sync_obstacles()
	_expect(not runtime.combat._obstacles.is_empty(), "Placed allied ship must be exposed as a combat obstacle.")
	if not runtime.combat._obstacles.is_empty():
		var obstacle_id: int = runtime.combat._obstacles[0].id
		var obstacle_node: Node = runtime._obstacle_nodes[obstacle_id]
		var hp_before: float = obstacle_node.hp
		runtime.combat._damage_obstacle(0, 1)
		runtime.combat.flush_combat_events()
		_expect(is_equal_approx(obstacle_node.hp, hp_before - 1), "Aggregate obstacle damage must reach the real allied ship.")
	var planet := GameManager.get_player_planet()
	var planet_hp: float = planet.hp
	runtime.combat.fire_projectile(Vector3(0, 0, 100), Vector3.FORWARD, 1, 350, 2, DamageSystem.Team.ENEMY)
	runtime.combat._update_projectiles(0.5)
	runtime.combat.flush_combat_events()
	_expect(is_equal_approx(planet.hp, planet_hp - 1), "Enemy projectile damage must reach the real planet.")
	var old := runtime.world.request_spawn(data, Vector3(900, 0, 0))
	GameManager.change_state(GameManager.GameState.PREPARATION)
	_expect(runtime.world.get_active_count() == 0 and runtime.combat.shot_count == 0, "Preparation reset must clear enemies and projectiles.")
	_expect(not runtime.world.is_handle_valid(old), "Restart must invalidate old target handles.")
	# Kill the entire next wave between physics ticks: bank its last reward before reset.
	config.total_enemies = 1
	spawner.set_level_config(config)
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.run_credits = 0
	var bank_before := GameManager.lifetime_credits
	GameManager.change_state(GameManager.GameState.PLAYING)
	runtime.spawner.advance_spawning(1.0)
	var final_enemy := runtime.world.get_active_handle(0)
	runtime.combat.apply_damage(final_enemy, 100)
	runtime._physics_process(0.016)
	_expect(GameManager.current_state == GameManager.GameState.END_SESSION, "Last kill must finish the actual wave.")
	_expect(is_equal_approx(GameManager.lifetime_credits - bank_before, data.credit_value), "Last-frame reward must be banked before end/reset.")
	for node in [blaster, laser, miner, level]:
		node.queue_free()
	await get_tree().process_frame
	_expect(GameManager.mass_combat == null, "Scene teardown must release the global combat bridge.")
	if failures == 0:
		print("Mass enemy production integration tests passed.")
	get_tree().quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
