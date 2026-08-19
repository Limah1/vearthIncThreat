# res://src/core/spawner.gd
extends Node
class_name Spawner

const DEFAULT_LEVEL_CONFIG_PATH: String = "res://src/resources/levels/FirstLevelConfig.tres"
const SPAWN_INTERVAL_SECONDS: float = 1.0

@export var level_config: LevelConfig

var _level_started: bool = false
var _level_spawned_count: int = 0
var _spawn_timer: float = 0.0
var _spawning_batches: bool = false
var _spawn_batch_size: int = 0
var _spawn_rounds_total: int = 0
var _spawn_rounds_completed: int = 0

# All scene-authored spawn positions share one pool. Actor type no longer
# restricts which point can be selected.
var spawn_points: Array[Node2D] = []

# Cached pooled actor masters.
var _garbage_master: SpaceGarbageMaster = null
var _enemy_master: Node = null
var _asteroid_master: Node = null

func _ready() -> void:
	add_to_group("spawner")
	GameManager.state_changed.connect(_on_state_changed)
	if not level_config:
		var default_resource: Resource = load(DEFAULT_LEVEL_CONFIG_PATH)
		if default_resource is LevelConfig:
			level_config = default_resource as LevelConfig
	var selected_config = GameManager.get_selected_level_config()
	if selected_config:
		level_config = selected_config

	_gather_tagged_spawner_points()
	_ensure_fallback_spawners()
	_cache_masters()

func _process(delta: float) -> void:
	if not _spawning_batches or GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_spawn_timer += delta
	if _spawn_timer < SPAWN_INTERVAL_SECONDS:
		return

	_spawn_timer = 0.0
	_spawn_batch()

func _cache_masters() -> void:
	if not _garbage_master:
		_garbage_master = get_tree().get_first_node_in_group("garbage_master") as SpaceGarbageMaster
	if not _enemy_master:
		_enemy_master = get_tree().get_first_node_in_group("enemy_master")
	if not _asteroid_master:
		_asteroid_master = get_tree().get_first_node_in_group("asteroid_master")

func _gather_tagged_spawner_points() -> void:
	spawn_points.clear()
	var seen: Dictionary = {}
	for group_name in ["spawn_point", "asteroid_spawner", "enemy_spawner"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node2D and not seen.has(node):
				seen[node] = true
				spawn_points.append(node)

## Keep safe fallback points for scenes without tagged points.
func _ensure_fallback_spawners() -> void:
	if not spawn_points.is_empty():
		return
	for child in get_children():
		if child is Node2D and child.name.begins_with("FallbackSpawnPoint_"):
			spawn_points.append(child)
	if not spawn_points.is_empty():
		return

	for i in range(4):
		var angle: float = i * (TAU / 4.0) + (PI / 4.0)
		var point: Node2D = Node2D.new()
		point.global_position = Vector2.from_angle(angle) * 500.0
		point.name = "FallbackSpawnPoint_" + str(i)
		add_child(point)
		spawn_points.append(point)

func start_spawning() -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not level_config:
		push_warning("Spawner has no LevelConfig assigned; nothing will spawn.")
		return
	if _level_started:
		return

	# Re-scan after all PathFollow2D nodes have entered the tree. This keeps
	# scene-authored spawn points working even when their groups are added
	# from SpawnPath._ready().
	_gather_tagged_spawner_points()
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
	_spawn_timer = 0.0
	_spawning_batches = false
	_spawn_batch_size = 0
	_spawn_rounds_total = 0
	_spawn_rounds_completed = 0

## Select resource and start it.
func start_level(config: LevelConfig = null) -> void:
	if config:
		set_level_config(config)
	start_spawning()

func _start_configured_level() -> void:
	_level_started = true
	_level_spawned_count = 0
	_spawn_timer = 0.0
	_spawning_batches = false
	_spawn_rounds_completed = 0
	if not level_config:
		return

	var total: int = level_config.get_total_configured_enemies()
	if total <= 0:
		return
	if spawn_points.is_empty():
		push_warning("Spawner has no spawn points.")
		return

	_cache_masters()
	_spawn_batch_size = spawn_points.size()
	# Example: 500 actors / 50 points = 10 planned rounds.
	_spawn_rounds_total = int(ceil(float(total) / float(_spawn_batch_size)))
	_spawn_batch()
	_spawning_batches = _level_spawned_count < total

func is_level_spawn_complete() -> bool:
	return level_config != null and _level_started and _level_spawned_count >= level_config.get_total_configured_enemies()

func get_spawned_actor_count() -> int:
	return _level_spawned_count

func get_spawn_total() -> int:
	return level_config.get_total_configured_enemies() if level_config else 0

func _spawn_batch() -> void:
	if not level_config or spawn_points.is_empty():
		_spawning_batches = false
		return

	var total: int = level_config.get_total_configured_enemies()
	var remaining: int = total - _level_spawned_count
	if remaining <= 0:
		_spawning_batches = false
		return

	# One round visits each point once, in a new random order. The final round
	# only uses the number of points still needed.
	var round_points: Array = spawn_points.duplicate()
	round_points.shuffle()
	var batch_size: int = mini(round_points.size(), remaining)
	for i in range(batch_size):
		var spawn_point: Node2D = round_points[i] as Node2D
		if _spawn_actor_at_point(level_config.actor_type, spawn_point):
			_level_spawned_count += 1

	_spawn_rounds_completed += 1
	if _level_spawned_count >= total:
		_spawning_batches = false

func _spawn_actor(actor_type: String) -> bool:
	if spawn_points.is_empty():
		return false
	return _spawn_actor_at_point(actor_type, spawn_points.pick_random() as Node2D)

func _spawn_actor_at_point(actor_type: String, spawn_point: Node2D) -> bool:
	if not is_instance_valid(spawn_point):
		return false

	_cache_masters()
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
			var spawn_pos_3d: Vector3 = Vector3(spawn_point.global_position.x, 0.0, spawn_point.global_position.y)
			return is_instance_valid(_enemy_master.spawn_enemy(spawn_pos_3d))
		"garbage":
			if not _garbage_master:
				return false
			return is_instance_valid(_garbage_master.spawn_garbage(spawn_point.global_position))
	return false

func _get_spawn_points(_actor_type: String) -> Array:
	return spawn_points

func _spawn_asteroid(spawn_point: Node2D, asteroid_type: String) -> bool:
	if not _asteroid_master:
		return false

	var dir_2d: Vector2 = (Vector2.ZERO - spawn_point.global_position).normalized()
	var dir_3d: Vector3 = Vector3(dir_2d.x, 0.0, dir_2d.y)
	var spawn_pos_3d: Vector3 = Vector3(spawn_point.global_position.x, 0.0, spawn_point.global_position.y)
	return is_instance_valid(_asteroid_master.spawn_asteroid(spawn_pos_3d, dir_3d, asteroid_type))

func _on_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.PLAYING and not _level_started:
		start_level(level_config)
