extends Node

var _failures: int = 0
var _aggregate_calls: int = 0
var _spawned_sum: int = 0
var _recycled_sum: int = 0


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_slots_and_handles()
	_test_validation_and_world_identity()
	_test_spawner_backpressure()
	_test_ten_thousand()
	if _failures == 0:
		print("EnemyWorld tests passed (including 10,000 active enemies without per-enemy Nodes).")
	else:
		push_error("EnemyWorld tests failed: %d" % _failures)
	get_tree().quit(_failures)


func _catalog() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	for file in ["asteroid_small", "asteroid_medium", "asteroid_large", "barrier_attack_ship"]:
		result.append(load("res://src/resources/enemies/%s.tres" % file) as EnemyData)
	return result


func _world(size: int) -> EnemyWorld:
	var world := EnemyWorld.new()
	world.capacity = size
	add_child(world)
	_expect(world.register_catalog(_catalog()).is_empty(), "Initial catalog must register.")
	return world


func _test_slots_and_handles() -> void:
	var world := _world(3)
	var data := _catalog()
	var first := world.request_spawn(data[0], Vector3(10, 0, 20))
	var middle := world.request_spawn(data[3], Vector3(20, 0, 30))
	var last := world.request_spawn(data[2], Vector3(30, 0, 40))
	_expect(world.get_enemy_snapshot(first).hp == data[0].max_hp, "New health must use archetype defaults.")
	_expect(world.get_enemy_snapshot(middle).state == EnemyWorld.State.APPROACH_BARRIER, "Ship must begin in its own state.")
	_expect(world.request_spawn(data[0], Vector3.ZERO) == -1, "Full capacity must reject without stealing a living slot.")
	_expect(world.recycle(middle), "Live handle must recycle.")
	_expect(world.is_handle_valid(last), "Swap removal must preserve the moved enemy handle.")
	var replacement := world.request_spawn(data[0], Vector3(99, 0, 88))
	_expect((replacement & EnemyWorld.SLOT_MASK) == (middle & EnemyWorld.SLOT_MASK), "Free slot must be reused.")
	_expect(replacement != middle and not world.is_handle_valid(middle), "Reused slot must have a new generation.")
	_expect(not world.recycle(middle), "Old handle cannot recycle its replacement.")
	_expect(world.get_enemy_snapshot(replacement).position == Vector3(99, 0, 88), "Reused slot must reset position.")
	world.reset_world()
	_expect(world.get_active_count() == 0 and world.get_available_capacity() == 3, "Reset must recover all slots.")
	var after_reset := world.request_spawn(data[0], Vector3.ZERO)
	_expect(after_reset != replacement and not world.is_handle_valid(first), "Reset cannot revive stale handles.")
	_expect(world.get_enemy_snapshot(after_reset).target == -1, "Target must reset on spawn.")
	world.free()


func _test_validation_and_world_identity() -> void:
	var first_world := _world(1)
	var other_world := _world(1)
	var data := _catalog()
	var first_handle := first_world.request_spawn(data[0], Vector3.ZERO)
	var other_handle := other_world.request_spawn(data[0], Vector3.ZERO)
	_expect(not other_world.is_handle_valid(first_handle) and first_handle != other_handle, "Handles must not alias across worlds.")
	var duplicate := data[0].duplicate() as EnemyData
	_expect(not first_world.register_catalog([duplicate]).is_empty(), "Conflicting resource ID must be rejected.")
	_expect(first_world.register_catalog(data).is_empty() and first_world.get_archetype_count() == 4, "Registering the same catalog is idempotent.")
	first_world.recycle(first_handle)
	_expect(first_world.request_spawn(duplicate, Vector3.ZERO) == -1, "Unregistered Resource cannot spawn using another Resource's ID.")
	_expect(first_world.request_spawn(data[0], Vector3(NAN, 0, 0)) == -1, "Non-finite positions must not enter arrays.")
	first_world.free()
	other_world.free()


func _test_spawner_backpressure() -> void:
	var world := _world(2)
	var point := SpawnerPoint.new()
	add_child(point)
	var spawner := MassEnemySpawner.new()
	spawner.respect_game_state = false
	spawner.enemy_world = world
	add_child(spawner)
	spawner.set_spawn_points([point])
	var config := LevelConfig.new()
	config.total_enemies = 5
	config.enemies_per_spawn_point = 5
	var entry := EnemySpawnEntry.new()
	entry.enemy = _catalog()[0]
	config.enemy_roster = [entry]
	spawner.level_config = config
	_expect(spawner.start_spawning(), "Spawner must initialize its world catalog.")
	spawner.advance_spawning(1.0)
	_expect(world.get_active_count() == 2 and spawner.spawned_enemy_count == 2, "Only accepted allocations count as spawned.")
	_expect(not spawner.is_spawn_complete(), "Full pool must not complete a pending wave.")
	spawner.advance_spawning(1.0)
	_expect(spawner.spawned_enemy_count == 2, "Repeated full-pool frames must not lose pending requests.")
	world.reset_world()
	spawner.advance_spawning(0.0)
	_expect(spawner.spawned_enemy_count == 4, "Pending cycle must resume after slots are released.")
	world.recycle(world.get_active_handle(0))
	spawner.advance_spawning(0.0)
	_expect(spawner.spawned_enemy_count == 5 and spawner.is_spawn_complete(), "Backpressure must eventually finish at exactly the requested total.")
	spawner.free()
	point.free()
	world.free()


func _test_ten_thousand() -> void:
	var world := _world(10000)
	world.events_flushed.connect(_on_events)
	_aggregate_calls = 0
	_spawned_sum = 0
	_recycled_sum = 0
	var points: Array[Node2D] = []
	for i in range(40):
		var point := SpawnerPoint.new()
		point.position = Vector2.from_angle(i * TAU / 40.0) * 650.0
		add_child(point)
		points.append(point)
	var spawner := MassEnemySpawner.new()
	spawner.respect_game_state = false
	spawner.enemy_world = world
	spawner.random_seed = 101
	add_child(spawner)
	spawner.set_spawn_points(points)
	var config := LevelConfig.new()
	config.total_enemies = 10000
	config.enemies_per_spawn_point = 25
	for enemy in _catalog():
		var entry := EnemySpawnEntry.new()
		entry.enemy = enemy
		config.enemy_roster.append(entry)
	spawner.level_config = config
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_expect(spawner.start_spawning(), "10k integration wave must start.")
	for _cycle in range(10):
		spawner.advance_spawning(1.0)
	_expect(world.get_active_count() == 10000 and spawner.is_spawn_complete(), "Ten timed cycles must create 10,000 active data entries.")
	_expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes_before, "Spawning 10k must not create any Nodes.")
	var types: Dictionary = {}
	for index in range(world.get_active_count()):
		var handle := world.get_active_handle(index)
		_expect(world.is_handle_valid(handle), "All 10k handles must resolve.")
		types[world.archetype_indices[handle & EnemyWorld.SLOT_MASK]] = true
	_expect(types.size() == 4, "10k wave must include all four weighted archetypes.")
	world.flush_events()
	_expect(_aggregate_calls == 1 and _spawned_sum == 10000, "10k spawns must flush as one aggregate event.")
	world.reset_world()
	world.flush_events()
	world.flush_events()
	_expect(_aggregate_calls == 2 and _recycled_sum == 10000, "Reset events must be aggregated and drained exactly once.")
	spawner.free()
	for point in points:
		point.free()
	world.free()


func _on_events(spawned: int, recycled: int, _rejected: int, _active: int) -> void:
	_aggregate_calls += 1
	_spawned_sum += spawned
	_recycled_sum += recycled


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
