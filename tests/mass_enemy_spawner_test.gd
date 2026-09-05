extends Node

const MASS_SPAWNER_SCRIPT = preload("res://src/core/mass_enemy_spawner.gd")
const SMALL_ASTEROID_PATH := "res://src/resources/enemies/asteroid_small.tres"

var _failures: int = 0
var _requests: Array[Dictionary] = []
var _completion_count: int = 0


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_level_config_rate_and_validation()
	_test_spawn_point_group_registration()
	_test_interval_batch_and_total_limit()
	_test_elapsed_time_catch_up_is_preserved()
	_test_invalid_configuration_is_rejected()
	_test_weighted_roster_selection()
	_test_invalid_enemy_and_intervals()
	_test_pause_and_resume()
	_test_large_cycle_budget_and_snapshot()
	_test_discovery_after_ready()
	_test_reentrant_stop_and_reset()
	_test_deleted_point_does_not_complete()
	_test_authored_configs()
	_test_zero_total()
	_test_spawn_spread()

	if _failures == 0:
		print("Mass enemy spawner tests passed.")
	else:
		push_error("Mass enemy spawner tests failed: %d" % _failures)
	get_tree().quit(_failures)


func _test_level_config_rate_and_validation() -> void:
	var config := _make_config(100, 3, 2.0, [_make_entry(_load_small_asteroid(), 1.0)])
	_expect(config.get_spawn_commands_per_cycle(4) == 12, "Four points must emit 12 commands per cycle.")
	_expect(is_equal_approx(config.get_spawn_commands_per_second(4), 6.0), "Configured rate must be six commands per second.")
	_expect(config.get_mass_spawn_validation_errors().is_empty(), "A complete mass-spawn config must be valid.")


func _test_spawn_point_group_registration() -> void:
	var point := SpawnerPoint.new()
	point.name = "RegisteredSpawnPoint"
	add_child(point)
	_expect(point.is_in_group("spawn_point"), "SpawnerPoint must register itself in the spawn_point group.")
	point.queue_free()


func _test_interval_batch_and_total_limit() -> void:
	var points := _create_points(2, "BatchPoint")
	var spawner := _create_spawner(points)
	spawner.set_level_config(_make_config(5, 2, 1.0, [_make_entry(_load_small_asteroid(), 1.0)]))
	spawner.spawn_requested.connect(_on_spawn_requested)
	spawner.spawning_completed.connect(_on_spawning_completed)
	_requests.clear()
	_completion_count = 0

	_expect(spawner.start_spawning(), "Valid spawner configuration must start.")
	spawner.advance_spawning(0.5)
	_expect(_requests.is_empty(), "No command may be emitted before the interval elapses.")
	spawner.advance_spawning(0.5)
	_expect(_requests.size() == 4, "Two points spawning two enemies must emit four commands per cycle.")
	spawner.advance_spawning(1.0)
	_expect(_requests.size() == 5, "The final cycle must stop exactly at total_enemies.")
	_expect(spawner.is_spawn_complete(), "Spawner must report completion at the configured total.")
	_expect(_completion_count == 1, "Completion must be emitted exactly once.")
	_expect(_requests[0].position == points[0].global_position, "First point must participate in the first cycle.")
	_expect(_requests[2].position == points[1].global_position, "Second point must participate in the first cycle.")
	_cleanup_spawner_and_points(spawner, points)


func _test_elapsed_time_catch_up_is_preserved() -> void:
	var points := _create_points(2, "CatchUpPoint")
	var spawner := _create_spawner(points)
	spawner.max_catch_up_cycles_per_frame = 2
	spawner.set_level_config(_make_config(20, 1, 0.5, [_make_entry(_load_small_asteroid(), 1.0)]))
	spawner.spawn_requested.connect(_on_spawn_requested)
	_requests.clear()

	spawner.start_spawning()
	spawner.advance_spawning(2.0)
	_expect(_requests.size() == 4, "Catch-up limit must cap one frame to two cycles.")
	_expect(is_equal_approx(spawner.get_pending_elapsed_seconds(), 1.0), "Unprocessed elapsed time must remain queued.")
	spawner.advance_spawning(0.001)
	_expect(_requests.size() == 8, "Queued elapsed time must be processed on the next frame.")
	_expect(spawner.get_pending_elapsed_seconds() > 0.0, "Sub-frame remainder must not be discarded.")
	_cleanup_spawner_and_points(spawner, points)


func _test_invalid_configuration_is_rejected() -> void:
	var points := _create_points(1, "InvalidPoint")
	var spawner := _create_spawner(points)
	var config := LevelConfig.new()
	config.total_enemies = 10
	config.enemies_per_spawn_point = 1
	config.spawn_interval_seconds = 1.0
	spawner.set_level_config(config)
	_expect(not spawner.start_spawning(), "Spawner must reject an empty enemy roster.")
	_expect(not spawner.is_spawning(), "Rejected configuration must remain stopped.")
	_cleanup_spawner_and_points(spawner, points)


func _test_weighted_roster_selection() -> void:
	var points := _create_points(1, "WeightedPoint")
	var spawner := _create_spawner(points)
	spawner.random_seed = 12345
	var common := _load_small_asteroid()
	var rare := common.duplicate() as EnemyData
	rare.enemy_id = &"weighted_test_rare"
	rare.display_name = "Weighted Test Rare"
	var roster: Array[EnemySpawnEntry] = [
		_make_entry(common, 9.0),
		_make_entry(rare, 1.0),
	]
	spawner.set_level_config(_make_config(1000, 1000, 1.0, roster))
	spawner.spawn_requested.connect(_on_spawn_requested)
	_requests.clear()

	spawner.start_spawning()
	spawner.advance_spawning(1.0)
	var common_count := 0
	var rare_count := 0
	for request in _requests:
		if request.enemy.enemy_id == common.enemy_id:
			common_count += 1
		elif request.enemy.enemy_id == rare.enemy_id:
			rare_count += 1
	_expect(common_count > rare_count, "Higher spawn weight must produce more selections.")
	_expect(rare_count >= 60 and rare_count <= 140, "9:1 weights must approximately produce 10% rare selections over 1000 samples.")
	var first_sequence := _requests.duplicate()
	_requests.clear()
	spawner.reset_spawning()
	spawner.start_spawning()
	spawner.advance_spawning(1.0)
	_expect(_requests == first_sequence, "The same seed must reproduce all choices and sequences after reset.")
	_cleanup_spawner_and_points(spawner, points)


func _create_spawner(points: Array[Node2D]) -> MassEnemySpawner:
	var spawner := MASS_SPAWNER_SCRIPT.new() as MassEnemySpawner
	spawner.auto_start = false
	spawner.respect_game_state = false
	add_child(spawner)
	spawner.set_spawn_points(points)
	return spawner


func _create_points(count: int, prefix: String) -> Array[Node2D]:
	var points: Array[Node2D] = []
	for index in range(count):
		var point := Node2D.new()
		point.name = "%s%d" % [prefix, index]
		point.position = Vector2(index * 100.0, index * 25.0)
		add_child(point)
		points.append(point)
	return points


func _cleanup_spawner_and_points(spawner: MassEnemySpawner, points: Array[Node2D]) -> void:
	spawner.free()
	for point in points:
		point.free()


func _make_config(
	total: int,
	per_point: int,
	interval: float,
	roster: Array[EnemySpawnEntry]
) -> LevelConfig:
	var config := LevelConfig.new()
	config.total_enemies = total
	config.enemies_per_spawn_point = per_point
	config.spawn_interval_seconds = interval
	config.enemy_roster = roster
	return config


func _make_entry(enemy: EnemyData, weight: float) -> EnemySpawnEntry:
	var entry := EnemySpawnEntry.new()
	entry.enemy = enemy
	entry.spawn_weight = weight
	return entry


func _load_small_asteroid() -> EnemyData:
	return load(SMALL_ASTEROID_PATH) as EnemyData


func _on_spawn_requested(enemy: EnemyData, world_position: Vector3, sequence: int) -> void:
	_requests.append({
		"enemy": enemy,
		"position": Vector2(world_position.x, world_position.z),
		"sequence": sequence,
	})


func _on_spawning_completed(_total_spawned: int) -> void:
	_completion_count += 1


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _test_invalid_enemy_and_intervals() -> void:
	var config := _make_config(3, 1, 1.0, [_make_entry(_load_small_asteroid(), 1.0)])
	for interval in [0.0, -1.0, NAN, INF]:
		config.spawn_interval_seconds = interval
		_expect(not config.is_mass_spawn_config_valid(), "Invalid interval must fail validation.")
	config.spawn_interval_seconds = 1.0
	var invalid := _load_small_asteroid().duplicate() as EnemyData
	invalid.max_hp = NAN
	config.enemy_roster = [_make_entry(invalid, 1.0)]
	_expect(not config.is_mass_spawn_config_valid(), "Roster must validate nested EnemyData, including NaN HP.")
	invalid.max_hp = 3.0
	invalid.enemy_id = &""
	_expect(not config.is_mass_spawn_config_valid(), "Empty enemy ID must be rejected through LevelConfig.")
	invalid.enemy_id = &"invalid_visual"
	invalid.visual_asset = null
	invalid.visual_scene = PackedScene.new()
	_expect(not config.is_mass_spawn_config_valid(), "An unpacked visual Resource must be rejected.")
	config.enemy_roster = [_make_entry(_load_small_asteroid(), -1.0)]
	_expect(not config.is_mass_spawn_config_valid(), "Negative weights must be rejected.")


func _test_pause_and_resume() -> void:
	var previous_state = GameManager.current_state
	var points := _create_points(1, "PausePoint")
	var spawner := _create_spawner(points)
	spawner.respect_game_state = true
	spawner.set_level_config(_make_config(3, 1, 1.0, [_make_entry(_load_small_asteroid(), 1.0)]))
	_expect(not spawner.is_spawn_complete(), "An unstarted spawner cannot be complete.")
	spawner.start_spawning()
	GameManager.current_state = GameManager.GameState.PREPARATION
	spawner.advance_spawning(50.0)
	_expect(spawner.get_pending_elapsed_seconds() == 0.0, "Preparation must freeze the clock.")
	GameManager.current_state = GameManager.GameState.PLAYING
	spawner.advance_spawning(0.5)
	spawner.start_spawning() # Idempotent start must not reset the timer.
	GameManager.current_state = GameManager.GameState.PAUSED
	spawner.advance_spawning(50.0)
	GameManager.current_state = GameManager.GameState.PLAYING
	get_tree().paused = true
	spawner.advance_spawning(50.0)
	get_tree().paused = false
	spawner.advance_spawning(0.5)
	_expect(spawner.spawned_enemy_count == 1, "Pause and duplicate start must preserve half-interval progress.")
	spawner.stop_spawning()
	spawner.advance_spawning(10.0)
	spawner.resume_spawning()
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 2, "Stop/resume must not lose progress or count stopped time.")
	GameManager.current_state = previous_state
	_cleanup_spawner_and_points(spawner, points)


func _test_large_cycle_budget_and_snapshot() -> void:
	var points := _create_points(2, "BudgetPoint")
	var spawner := _create_spawner(points)
	spawner.max_spawn_commands_per_frame = 3
	var config := _make_config(11, 5, 1.0, [_make_entry(_load_small_asteroid(), 1.0)])
	spawner.set_level_config(config)
	spawner.spawn_requested.connect(_on_spawn_requested)
	_requests.clear()
	spawner.start_spawning()
	config.spawn_interval_seconds = 0.0
	config.total_enemies = 1000
	config.enemies_per_spawn_point = 0
	config.enemy_roster.clear()
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 3, "Command budget must split one large cycle.")
	_expect(spawner.completed_cycle_count == 0, "Partial cycle must remain open.")
	spawner.advance_spawning(0.0)
	spawner.advance_spawning(0.0)
	spawner.advance_spawning(0.0)
	_expect(spawner.spawned_enemy_count == 10, "Partial-cycle cursor must reach exactly five per point.")
	_expect(spawner.completed_cycle_count == 1, "One large cycle completes once after all chunks.")
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 11 and spawner.is_spawn_complete(), "Running wave must use a stable settings snapshot.")
	_expect(_requests[10].position == points[1].position, "Final partial cycle must rotate its first point.")
	for i in range(_requests.size()):
		_expect(_requests[i].sequence == i, "Sequences must stay contiguous across split cycles.")
	_cleanup_spawner_and_points(spawner, points)


func _test_discovery_after_ready() -> void:
	var scope := Node.new()
	add_child(scope)
	var spawner := MASS_SPAWNER_SCRIPT.new() as MassEnemySpawner
	spawner.respect_game_state = false
	scope.add_child(spawner) # Spawner enters before the point.
	var point := SpawnerPoint.new()
	scope.add_child(point)
	var outsider := SpawnerPoint.new()
	add_child(outsider)
	spawner.level_config = _make_config(2, 1, 1.0, [_make_entry(_load_small_asteroid(), 1.0)])
	_expect(spawner.start_spawning(), "Discover points after sibling _ready calls.")
	_expect(spawner.spawn_points.size() == 1, "Discovery must be scoped to the owning subtree.")
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 1, "Discovered point must produce requests.")
	scope.free()
	outsider.free()


func _test_reentrant_stop_and_reset() -> void:
	var points := _create_points(1, "CallbackPoint")
	var spawner := _create_spawner(points)
	spawner.set_level_config(_make_config(10, 10, 1.0, [_make_entry(_load_small_asteroid(), 1.0)]))
	var stop_callback := func(_enemy, _position, _sequence): spawner.stop_spawning()
	spawner.spawn_requested.connect(stop_callback)
	spawner.start_spawning()
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 1, "Stopping in an observer must stop the batch immediately.")
	spawner.spawn_requested.disconnect(stop_callback)
	spawner.resume_spawning()
	spawner.spawn_requested.connect(func(_enemy, _position, _sequence): spawner.reset_spawning())
	spawner.advance_spawning(0.0)
	_expect(spawner.spawned_enemy_count == 0 and not spawner.is_spawn_complete(), "Observer reset must not be overwritten by the old cycle.")
	_cleanup_spawner_and_points(spawner, points)


func _test_deleted_point_does_not_complete() -> void:
	var points := _create_points(1, "RemovedPoint")
	var spawner := _create_spawner(points)
	spawner.set_level_config(_make_config(2, 1, 1.0, [_make_entry(_load_small_asteroid(), 1.0)]))
	spawner.start_spawning()
	points[0].free()
	spawner.advance_spawning(1.0)
	_expect(not spawner.is_spawning() and not spawner.is_spawn_complete(), "Removed points must stop with an error, never false completion.")
	spawner.free()


func _test_authored_configs() -> void:
	for path in ["FirstLevelConfig", "SecondtLevelConfig", "GridPrototypeLevelConfig"]:
		var config := load("res://src/resources/levels/%s.tres" % path) as LevelConfig
		_expect(config != null and config.is_mass_spawn_config_valid(), "Authored config must load with a valid typed roster: %s" % path)


func _test_spawn_spread() -> void:
	var points := _create_points(1, "SpreadPoint")
	var spawner := _create_spawner(points)
	var config := _make_config(100, 50, 1.0, [_make_entry(_load_small_asteroid(), 1.0)])
	config.mass_spawn_spread_radius = 250
	spawner.level_config = config
	spawner.spawn_requested.connect(_on_spawn_requested)
	_requests.clear()
	spawner.start_spawning()
	spawner.advance_spawning(2)
	var first := _requests.duplicate(true)
	var unique: Dictionary = {}
	for request in first:
		_expect(request.position.distance_to(points[0].global_position) <= 250.001, "Spread must stay inside the configured disk.")
		unique[request.position] = true
	_expect(unique.size() == 100, "Spread must give both cycles distinct spawn positions.")
	spawner.reset_spawning()
	spawner.max_spawn_commands_per_frame = 7
	_requests.clear()
	spawner.start_spawning()
	config.mass_spawn_spread_radius = 0 # Running wave uses its snapshot.
	spawner.advance_spawning(2)
	for i in range(20):
		spawner.advance_spawning(0)
	_expect(_requests.size() == 100, "Spread must preserve totals across split batches.")
	for i in range(_requests.size()):
		_expect(_requests[i].position == first[i].position, "Spread positions must not depend on frame budget or mid-wave config edits.")
	_cleanup_spawner_and_points(spawner, points)
	config.mass_spawn_spread_radius = NAN
	_expect(not config.is_mass_spawn_config_valid(), "Nonfinite spread must be rejected.")


func _test_zero_total() -> void:
	var points := _create_points(1, "EmptyWavePoint")
	var spawner := _create_spawner(points)
	spawner.level_config = _make_config(0, 1, 1.0, [_make_entry(_load_small_asteroid(), 1.0)])
	_completion_count = 0
	spawner.spawning_completed.connect(_on_spawning_completed)
	_expect(not spawner.is_spawn_complete(), "An unstarted zero-total wave must not be complete.")
	spawner.start_spawning()
	spawner.start_spawning()
	spawner.advance_spawning(100.0)
	_expect(spawner.is_spawn_complete() and _completion_count == 1, "Zero-total wave must complete once without any spawns.")
	_cleanup_spawner_and_points(spawner, points)
