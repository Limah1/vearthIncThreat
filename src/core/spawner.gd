# res://src/core/spawner.gd
extends Node
class_name Spawner

@export var level_config: LevelConfig = preload("res://src/resources/levels/FirstLevelConfig.tres")

var _level_started: bool = false
var _level_spawned_count: int = 0
var _batch_timer: float = 0.0

# Spawn positions gathered from editor groups.
var garbage_spawn_points: Array[Node2D] = []
var asteroid_spawn_points: Array[Node2D] = []
var enemy_spawn_points: Array[Node2D] = []

# Cached pooled actor masters.
var _garbage_master: SpaceGarbageMaster = null
var _enemy_master: Node = null
var _asteroid_master: Node = null

func _ready() -> void:
	add_to_group("spawner")
	GameManager.state_changed.connect(_on_state_changed)
	var selected_config = GameManager.get_selected_level_config()
	if selected_config:
		level_config = selected_config

	_gather_tagged_spawner_points()
	_ensure_fallback_spawners()
	_cache_masters()

func _cache_masters() -> void:
	if not _garbage_master:
		_garbage_master = get_tree().get_first_node_in_group("garbage_master") as SpaceGarbageMaster
	if not _enemy_master:
		_enemy_master = get_tree().get_first_node_in_group("enemy_master")
	if not _asteroid_master:
		_asteroid_master = get_tree().get_first_node_in_group("asteroid_master")

func _gather_tagged_spawner_points() -> void:
	garbage_spawn_points.clear()
	asteroid_spawn_points.clear()
	enemy_spawn_points.clear()

	for node in get_tree().get_nodes_in_group("garbage_spawner"):
		if node is Node2D:
			garbage_spawn_points.append(node)

	for node in get_tree().get_nodes_in_group("asteroid_spawner"):
		if node is Node2D:
			asteroid_spawn_points.append(node)

	for node in get_tree().get_nodes_in_group("enemy_spawner"):
		if node is Node2D:
			enemy_spawn_points.append(node)

## Keep safe fallback points for scenes without tagged points.
func _ensure_fallback_spawners() -> void:
	if garbage_spawn_points.is_empty():
		for i in range(40):
			var angle = i * (TAU / 40.0)
			var point = Node2D.new()
			point.global_position = Vector2.from_angle(angle) * 140.0
			point.name = "FallbackGarbageSpawner_" + str(i)
			add_child(point)
			garbage_spawn_points.append(point)

	if asteroid_spawn_points.is_empty():
		for i in range(4):
			var angle = i * (TAU / 4.0) + (PI / 4.0)
			var point = Node2D.new()
			point.global_position = Vector2.from_angle(angle) * 500.0
			point.name = "FallbackAsteroidSpawner_" + str(i)
			add_child(point)
			asteroid_spawn_points.append(point)

	if enemy_spawn_points.is_empty():
		for i in range(8):
			var angle = i * (TAU / 8.0)
			var point = Node2D.new()
			point.global_position = Vector2.from_angle(angle) * 550.0
			point.name = "FallbackEnemySpawner_" + str(i)
			add_child(point)
			enemy_spawn_points.append(point)

func start_spawning() -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not level_config:
		push_warning("Spawner has no LevelConfig assigned; nothing will spawn.")
		return
	if _level_started:
		return

	_ensure_fallback_spawners()
	_cache_masters()
	_start_configured_level()

## Apply selected resource without spawning yet. Main uses this before camera transitions.
func set_level_config(config: LevelConfig) -> void:
	if not config:
		return
	level_config = config
	_level_started = false
	_level_spawned_count = 0
	_batch_timer = 0.0

## Select resource and start it.
func start_level(config: LevelConfig = null) -> void:
	if config:
		set_level_config(config)
	start_spawning()

func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not _level_started or is_level_spawn_complete():
		return

	_batch_timer += delta
	var interval = maxf(level_config.batch_interval, 0.05)
	if _batch_timer < interval:
		return

	_batch_timer = 0.0
	_spawn_next_batch()

func _start_configured_level() -> void:
	_level_started = true
	_level_spawned_count = 0
	_batch_timer = 0.0

	# First batch starts immediately. Later batches use batch_interval.
	_spawn_next_batch()

func _spawn_next_batch() -> void:
	if not level_config:
		return

	var total = level_config.get_total_configured_enemies()
	var remaining = total - _level_spawned_count
	if remaining <= 0:
		return

	var amount = mini(maxi(level_config.batch_size, 1), remaining)
	var spawned_this_batch = 0
	for _i in range(amount):
		if _spawn_actor(level_config.actor_type):
			_level_spawned_count += 1
			spawned_this_batch += 1

	if spawned_this_batch == 0:
		push_warning("Spawner could not spawn actor type: " + level_config.actor_type)

func is_level_spawn_complete() -> bool:
	return level_config != null and _level_started and _level_spawned_count >= level_config.get_total_configured_enemies()

func _spawn_actor(actor_type: String) -> bool:
	var spawn_points = _get_spawn_points(actor_type)
	if spawn_points.is_empty():
		return false

	_cache_masters()
	var spawn_point: Node2D = spawn_points.pick_random()
	match actor_type:
		"small_asteroid":
			return _spawn_asteroid(spawn_point, "small")
		"medium_asteroid":
			return _spawn_asteroid(spawn_point, "medium")
		"large_asteroid":
			return _spawn_asteroid(spawn_point, "large")
		"enemy":
			if not _enemy_master:
				return false
			var spawn_pos_3d = Vector3(spawn_point.global_position.x, 0.0, spawn_point.global_position.y)
			return is_instance_valid(_enemy_master.spawn_enemy(spawn_pos_3d))
		"garbage":
			if not _garbage_master:
				return false
			return is_instance_valid(_garbage_master.spawn_garbage(spawn_point.global_position))
	return false

func _get_spawn_points(actor_type: String) -> Array:
	match actor_type:
		"small_asteroid", "medium_asteroid", "large_asteroid":
			return asteroid_spawn_points
		"enemy":
			return enemy_spawn_points
		"garbage":
			return garbage_spawn_points
	return []

func _spawn_asteroid(spawn_point: Node2D, asteroid_type: String) -> bool:
	if not _asteroid_master:
		return false

	var dir_2d = (Vector2.ZERO - spawn_point.global_position).normalized()
	var dir_3d = Vector3(dir_2d.x, 0.0, dir_2d.y)
	var spawn_pos_3d = Vector3(spawn_point.global_position.x, 0.0, spawn_point.global_position.y)
	return is_instance_valid(_asteroid_master.spawn_asteroid(spawn_pos_3d, dir_3d, asteroid_type))

func _on_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.PLAYING and not _level_started:
		start_level(level_config)
