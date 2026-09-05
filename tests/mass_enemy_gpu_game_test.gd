extends Node

## Runs real production scene, preparation, mounted turrets and normal physics ticks.
var failures: int = 0
var level: Node
var runtime: MassEnemyRuntime
var controller: GridCombatController
var spawner: Spawner
var mounts: Array[DefenseBlaster] = []
var result: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		push_error("Production GPU test requires a real GPU.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = Vector2i(1920, 1080)
	var benchmark := "--benchmark" in OS.get_cmdline_user_args()
	if benchmark:
		result = {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
			"spawn_spread_and_separation": "--separation" in OS.get_cmdline_user_args(),
			"planet_invulnerable": "--separation" in OS.get_cmdline_user_args(),
			"legacy_rules_and_feedback": "--legacy-parity" in OS.get_cmdline_user_args(),
			"debris_upgrades": {"unlock": 1, "chance": 1, "amount": 1, "damage": 1, "piercing": 3} if "--debris-upgraded" in OS.get_cmdline_user_args() else {},
			"gpu": RenderingServer.get_video_adapter_name(), "build": "debug" if OS.is_debug_build() else "release",
			"resolution": str(get_window().size), "physics": "normal engine fixed ticks, no manual simulation steps",
			"fixture": "production GridCombatLevel, 4 allied ships, 3 barriers, 4 blasters, 2 lasers, 2 miners; original spawn points; 60/25/10/5 roster",
			"results": []}
		for count in [5000, 10000]:
			await _start(count)
			await _measure(count)
			await _cleanup()
		var output := "user://mass_enemy_gpu_game_benchmark.json"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--output="):
				output = argument.trim_prefix("--output=")
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Could not write production GPU benchmark: " + output)
			get_tree().quit(1)
			return
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
		print("Production GPU benchmark report: " + ProjectSettings.globalize_path(output))
	else:
		await _start(350)
		await _functional()
		await _cleanup()
	if failures == 0:
		print("Production GPU game tests passed.")
	get_tree().quit(failures)


func _start(total: int) -> void:
	if "--debris-upgraded" in OS.get_cmdline_user_args():
		for entry in {"DA_UnlockDebrie_T0": 1, "DebrisChance": 1, "DebrisAmount": 1, "DA_DebrisDamage_T0": 1, "DebrisPiercing": 3}:
			UpgradeManager.purchased_levels[entry] = 3 if entry == "DebrisPiercing" else 1
		GameManager.debris_chance = 0.8 + UpgradeManager.get_total_bonus("DebrisChance")
	var config := load("res://src/resources/levels/FirstLevelConfig.tres").duplicate() as LevelConfig
	var roster := load("res://src/prototypes/mass_enemies/MassEnemyTestConfig.tres") as LevelConfig
	config.enemy_roster = roster.enemy_roster
	config.use_mass_enemies = true
	config.use_gpu_enemy_simulation = true
	config.use_mass_legacy_rules = "--legacy-parity" in OS.get_cmdline_user_args()
	config.use_mass_enemy_feedback = config.use_mass_legacy_rules
	if "--separation" in OS.get_cmdline_user_args():
		config.mass_spawn_spread_radius = 250
		config.mass_gpu_separation = true
		config.mass_planet_invulnerable = true
	config.total_enemies = total
	config.enemies_per_spawn_point = 50 if total >= 5000 else 1
	config.spawn_interval_seconds = 1
	GameManager.selected_level_config = config
	GameManager.run_credits = 0
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.change_state(GameManager.GameState.PREPARATION, false)
	level = config.level_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	controller = level.get_node("GridCombatController")
	spawner = level.get_node("Spawner")
	for cell in [Vector2i(1, 1), Vector2i(8, 1), Vector2i(1, 4), Vector2i(8, 4)]:
		controller.begin_ally_ship_placement()
		controller._commit_preview(cell)
	for cell in [Vector2i(4, 0), Vector2i(5, 5), Vector2i(0, 3)]:
		controller.begin_defense_block_placement()
		controller._commit_preview(cell)
	var types := ["defense_blaster", "defense_blaster", "defense_blaster", "defense_blaster", "laser_turret", "laser_turret", "turret_miner", "turret_miner"]
	for i in range(controller.placed_ally_ships.size()):
		var ship := controller.placed_ally_ships[i]
		for slot in range(2):
			var turret := load("res://src/entities/%s.tscn" % types[i * 2 + slot]).instantiate() as DefenseBlaster
			level.add_child(turret)
			var at := ship.get_world_position_for_local_offset(ship.get_mount_slot_offset(slot))
			_expect(ship.attach_turret(turret, at), "Turret must attach through the real mount API.")
			turret.set_aim_direction(at.normalized())
			mounts.append(turret)
	_expect(mounts.size() == 8, "Fixture must contain eight actual mounted turrets.")
	controller.start_button.pressed.emit()
	await get_tree().process_frame
	runtime = spawner.mass_runtime
	_expect(is_instance_valid(runtime) and runtime.combat is EnemyGPUCombat, "Production level must select authoritative GPU combat.")
	if not is_instance_valid(runtime):
		get_tree().quit(1)
		return
	for group in ["asteroid_master", "enemy_master", "debris_master"]:
		for master in get_tree().get_nodes_in_group(group):
			_expect(master.get_child_count() == 0, "Legacy enemy pools must stay unallocated in mass mode.")


func _functional() -> void:
	# Normal spawn cadence must work before any manual damage commands are used.
	await get_tree().create_timer(1.2).timeout
	_expect(spawner.get_spawned_actor_count() > 0, "Real Start Wave must produce a timed GPU batch.")
	var count := runtime.world.get_active_count()
	var time_before := runtime.combat.simulation_time
	GameManager.change_state(GameManager.GameState.PAUSED)
	await get_tree().create_timer(0.2).timeout
	_expect(runtime.world.get_active_count() == count and runtime.combat.simulation_time == time_before, "Pause must freeze the GPU command producer and allocations.")
	GameManager.change_state(GameManager.GameState.PLAYING)
	runtime.spawner.stop_spawning()
	runtime.world.reset_world()
	runtime.combat.reset_combat()
	# Isolate acquisition/damage from ballistic accuracy against lateral avoidance.
	# Moving trajectories and ship transitions have separate CPU/GPU parity tests.
	var data := runtime.spawner.level_config.enemy_roster[0].enemy.duplicate() as EnemyData
	data.enemy_id = &"gpu_mount_target"
	data.movement_speed = 0
	_expect(runtime.world.register_catalog([data]).is_empty(), "Stationary targeting fixture must register its archetype.")
	var turret := mounts[0]
	var forward := turret.get_aim_forward_2d()
	var position_3d := turret.global_position + Vector3(forward.x, 0, forward.y) * 150
	position_3d.y = 0
	var victim := runtime.world.request_spawn(data, position_3d)
	_expect(runtime.world.is_handle_valid(victim), "Targeting fixture must allocate a valid GPU handle.")
	turret.effective_damage = 100
	turret.cooldown = 0
	var bursts_before := runtime.debris_bursts
	if config_uses_legacy():
		UpgradeManager.b_next_debris_guaranteed = true
	var kills_before := runtime.combat.total_kills
	for i in range(240):
		await get_tree().process_frame
		if not runtime.world.is_handle_valid(victim):
			break
	_expect(not runtime.world.is_handle_valid(victim), "Real mounted blaster must acquire and kill a GPU target.")
	_expect(runtime.combat.total_kills > kills_before and GameManager.run_credits > 0, "GPU kill must reach real credits/progress.")
	if config_uses_legacy():
		_expect(runtime.debris_bursts == bursts_before + 1 and not UpgradeManager.b_next_debris_guaranteed, "Guaranteed asteroid debris must consume its flag exactly once.")
		_expect(runtime.feedback != null and runtime.feedback._count > 0, "GPU death must produce a pooled visual effect.")
	# Confirm completion and banking after an asynchronous last kill in a fresh wave.
	GameManager.change_state(GameManager.GameState.PREPARATION)
	var config := spawner.level_config
	config.total_enemies = 1
	spawner.set_level_config(config)
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.run_credits = 0
	var bank_before := GameManager.lifetime_credits
	GameManager.change_state(GameManager.GameState.PLAYING)
	for i in range(180):
		await get_tree().process_frame
		if runtime.world.get_active_count() > 0:
			break
	_expect(runtime.world.get_active_count() == 1, "Restart must spawn its new single-enemy wave.")
	if runtime.world.get_active_count() > 0:
		var handle := runtime.world.get_active_handle(0)
		var reward := runtime.world.get_archetype(runtime.world.archetype_indices[handle & EnemyWorld.SLOT_MASK]).credit_value
		runtime.combat.apply_damage(handle, 1000000)
		for i in range(80):
			await get_tree().process_frame
			if GameManager.current_state == GameManager.GameState.END_SESSION:
				break
		_expect(GameManager.current_state == GameManager.GameState.END_SESSION, "GPU final kill must finish the production wave.")
		_expect(is_equal_approx(GameManager.lifetime_credits - bank_before, reward), "Final GPU reward must be banked once.")


func _measure(total: int) -> void:
	var samples: Array[float] = []
	var physics: Array[float] = []
	var previous := Time.get_ticks_usec()
	var peak := 0
	var first_batch := 0
	var max_alive := 0
	var min_alive := total
	var start := Time.get_ticks_msec()
	# Includes real paced spawn ramp; collect steady samples after final batch.
	for frame in range(1600):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var alive := runtime.world.get_active_count()
		peak = maxi(peak, alive)
		if first_batch == 0 and spawner.get_spawned_actor_count() > 0:
			first_batch = spawner.get_spawned_actor_count()
		if spawner.is_level_spawn_complete():
			samples.append((now - previous) / 1000.0)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			min_alive = mini(min_alive, alive)
			max_alive = maxi(max_alive, alive)
		previous = now
		if samples.size() >= 180 or GameManager.current_state != GameManager.GameState.PLAYING:
			break
	_expect(samples.size() == 180, "Production benchmark must remain in gameplay for all steady samples.")
	_expect(runtime.combat.backend_error.is_empty(), "Production GPU backend must remain healthy.")
	if "--debris-upgraded" in OS.get_cmdline_user_args():
		_expect(runtime.debris_bursts > 0, "Upgraded benchmark must actually exercise offensive debris.")
	samples.sort()
	physics.sort()
	var row := {"total_spawned": spawner.get_spawned_actor_count(), "requested": total, "first_observed_batch": first_batch,
		"spawn_points": spawner.spawn_points.size(), "peak_alive": peak, "steady_min_alive": min_alive, "steady_max_alive": max_alive,
		"samples": samples.size(), "elapsed_seconds": (Time.get_ticks_msec() - start) / 1000.0,
		"frame_median_ms": samples[samples.size() / 2] if not samples.is_empty() else -1,
		"frame_p95_ms": samples[mini(samples.size() - 1, int(samples.size() * 0.95))] if not samples.is_empty() else -1,
		"physics_median_ms": physics[physics.size() / 2] if not physics.is_empty() else -1,
		"kills": runtime.combat.total_kills, "escaped": runtime.combat.total_escaped, "projectiles": runtime.combat.shot_count,
		"rejected_projectiles": runtime.combat.dropped_projectiles, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	row["debris_bursts"] = runtime.debris_bursts
	row["rejected_debris_commands"] = runtime.rejected_debris_commands
	row["dropped_cosmetic_feedback"] = runtime.combat.dropped_feedback
	result.results.append(row)
	print(JSON.stringify(row))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://mass_enemy_gpu_game_%d.png" % total)


func _cleanup() -> void:
	GameManager.change_state(GameManager.GameState.PREPARATION)
	level.queue_free()
	mounts.clear()
	for i in range(8):
		await get_tree().process_frame
	_expect(GameManager.mass_combat == null, "Level cleanup must release the active GPU bridge.")


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func config_uses_legacy() -> bool:
	return spawner.level_config.use_mass_legacy_rules
