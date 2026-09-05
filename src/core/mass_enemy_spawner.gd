extends Node
class_name MassEnemySpawner

## Produces timed requests; an optional EnemyWorld confirms slot allocation.
signal spawn_requested(enemy: EnemyData, world_position: Vector3, sequence: int)
signal spawn_cycle_completed(cycle_index: int, spawned_in_cycle: int, total_spawned: int)
signal spawning_completed(total_spawned: int)
signal configuration_rejected(errors: PackedStringArray)

const SPAWN_POINT_GROUP: StringName = &"spawn_point"

@export var level_config: LevelConfig
@export var enemy_world: EnemyWorld
## Restrict discovery to this subtree, or the parent subtree when unset.
@export var spawn_root: Node
@export var auto_start: bool = false
@export var respect_game_state: bool = true
@export_range(1, 120, 1) var max_catch_up_cycles_per_frame: int = 4
## A single large cycle can span several frames.
@export_range(1, 100000, 1) var max_spawn_commands_per_frame: int = 1024
## Zero randomizes; any other value gives repeatable selection.
@export var random_seed: int = 0

var spawn_points: Array[Node2D] = []
var spawned_enemy_count: int = 0
var _spread_radius: float = 0.0
var completed_cycle_count: int = 0

var _elapsed_seconds: float = 0.0
var _is_spawning: bool = false
var _started: bool = false
var _completion_emitted: bool = false
var _explicit_points: bool = false
var _next_spawn_point_index: int = 0
var _enemies: Array[EnemyData] = []
var _weights := PackedFloat64Array()
var _total_roster_weight: float = 0.0
var _rng := RandomNumberGenerator.new()
var _total: int = 0
var _per_point: int = 0
var _interval: float = 1.0
var _cycle_slot: int = -1
var _cycle_size: int = 0
var _cycle_spawned: int = 0
var _pending_enemy: EnemyData
var _bound_world: EnemyWorld
var _requires_world: bool = false
var _revision: int = 0
var _advancing: bool = false


func _ready() -> void:
	add_to_group("mass_enemy_spawner")
	# All sibling SpawnPaths must finish _ready before point discovery.
	if auto_start:
		call_deferred("start_spawning")


func _process(delta: float) -> void:
	advance_spawning(delta)


func set_level_config(config: LevelConfig) -> void:
	reset_spawning()
	level_config = config


func refresh_spawn_points() -> void:
	spawn_points.clear()
	var scope := spawn_root if is_instance_valid(spawn_root) else get_parent()
	if not is_inside_tree() or scope == null:
		return
	for node in get_tree().get_nodes_in_group(SPAWN_POINT_GROUP):
		if node is Node2D and not node.is_queued_for_deletion() and (node == scope or scope.is_ancestor_of(node)):
			spawn_points.append(node as Node2D)
	spawn_points.sort_custom(_spawn_point_path_less_than)


func set_spawn_points(points: Array[Node2D]) -> void:
	reset_spawning()
	_explicit_points = true
	spawn_points.clear()
	for point in points:
		if is_instance_valid(point) and not spawn_points.has(point):
			spawn_points.append(point)
	# Preserve caller order; discovery is sorted by scene path.


func start_spawning(config: LevelConfig = null) -> bool:
	if config != null:
		set_level_config(config)
	elif _started:
		return true
	reset_spawning()
	if not _explicit_points:
		refresh_spawn_points()
	var errors := get_configuration_errors()
	if not errors.is_empty():
		_reject(errors)
		return false
	for entry in level_config.enemy_roster:
		_enemies.append(entry.enemy)
		_weights.append(entry.spawn_weight)
		_total_roster_weight += entry.spawn_weight
	_bound_world = enemy_world
	_requires_world = is_instance_valid(_bound_world)
	if _requires_world:
		if not _bound_world.initialize():
			_reject(PackedStringArray(["EnemyWorld capacity is invalid."]))
			return false
		errors = _bound_world.register_catalog(_enemies)
		if not errors.is_empty():
			_reject(errors)
			return false
	# Snapshot scheduling values. Edits take effect on explicit restart.
	_total = level_config.total_enemies
	_per_point = level_config.enemies_per_spawn_point
	_interval = level_config.spawn_interval_seconds
	_spread_radius = level_config.mass_spawn_spread_radius
	_cycle_size = spawn_points.size() * _per_point
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed
	_started = true
	_is_spawning = _total > 0
	if not _is_spawning:
		_finish_spawning()
	return true


func stop_spawning() -> void:
	_is_spawning = false


func resume_spawning() -> void:
	if _started and not _completion_emitted:
		_is_spawning = true


func reset_spawning() -> void:
	_revision += 1
	_started = false
	_is_spawning = false
	_completion_emitted = false
	spawned_enemy_count = 0
	completed_cycle_count = 0
	_elapsed_seconds = 0.0
	_next_spawn_point_index = 0
	_enemies.clear()
	_weights.clear()
	_total_roster_weight = 0.0
	_cycle_slot = -1
	_cycle_spawned = 0
	_pending_enemy = null
	_bound_world = null
	_requires_world = false


func advance_spawning(delta: float) -> void:
	if _advancing or not _can_advance() or not is_finite(delta) or delta < 0.0:
		return
	_advancing = true
	_advance(delta)
	_advancing = false


func _can_advance() -> bool:
	if not _is_spawning:
		return false
	if is_inside_tree() and get_tree().paused:
		return false
	return not respect_game_state or GameManager.current_state == GameManager.GameState.PLAYING


func _advance(delta: float) -> void:
	_elapsed_seconds += delta
	var cycles := 0
	var commands := 0
	var revision := _revision
	while _can_advance() and cycles < maxi(max_catch_up_cycles_per_frame, 1) and commands < maxi(max_spawn_commands_per_frame, 1):
		if _cycle_slot < 0:
			if _elapsed_seconds + 1e-9 < _interval:
				break
			_elapsed_seconds = maxf(0.0, _elapsed_seconds - _interval)
			_cycle_slot = 0
			_cycle_spawned = 0

		var point_index := (_next_spawn_point_index + _cycle_slot / _per_point) % spawn_points.size()
		var point := spawn_points[point_index]
		if not is_instance_valid(point) or point.is_queued_for_deletion() or not point.is_inside_tree():
			_reject(PackedStringArray(["A configured SpawnPoint was removed. Restart with valid points."]))
			return
		var point_position := point.global_position
		if _spread_radius > 0:
			# Sunflower disk: stable across frame budgets/backpressure, no RNG consumed.
			var disk_index := _cycle_slot % _per_point
			var angle := (disk_index + completed_cycle_count * _per_point + point_index) * 2.399963229728653
			var distance := _spread_radius * sqrt((float(disk_index) + 0.5) / _per_point)
			point_position += Vector2(cos(angle), sin(angle)) * distance
		var position_3d := Vector3(point_position.x, 0.0, point_position.y)
		if not position_3d.is_finite():
			_reject(PackedStringArray(["SpawnPoint position must be finite."]))
			return

		if _requires_world:
			if not is_instance_valid(_bound_world):
				_reject(PackedStringArray(["EnemyWorld was removed during spawning."]))
				return
			if _bound_world.get_available_capacity() == 0:
				break # Backpressure: preserve cycle cursor, time and total.
		if _pending_enemy == null:
			_pending_enemy = _choose_weighted_enemy()
		if _requires_world:
			var handle := _bound_world.request_spawn(_pending_enemy, position_3d)
			if handle == EnemyWorld.INVALID_HANDLE:
				_reject(PackedStringArray(["EnemyWorld rejected a spawn with available capacity."]))
				return

		var enemy := _pending_enemy
		_pending_enemy = null
		var sequence := spawned_enemy_count
		spawned_enemy_count += 1
		_cycle_spawned += 1
		_cycle_slot += 1
		commands += 1
		# Counters are consistent when observers run. Observers may stop/reset.
		spawn_requested.emit(enemy, position_3d, sequence)
		if revision != _revision:
			return

		if _cycle_slot == _cycle_size or spawned_enemy_count == _total:
			_cycle_slot = -1
			_next_spawn_point_index = (_next_spawn_point_index + 1) % spawn_points.size()
			completed_cycle_count += 1
			cycles += 1
			spawn_cycle_completed.emit(completed_cycle_count, _cycle_spawned, spawned_enemy_count)
			if revision != _revision:
				return
			if spawned_enemy_count == _total:
				_finish_spawning()


func get_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if level_config == null:
		errors.append("level_config cannot be empty.")
	else:
		errors.append_array(level_config.get_mass_spawn_validation_errors())
	if spawn_points.is_empty():
		errors.append("At least one SpawnPoint is required.")
	for point in spawn_points:
		if not is_instance_valid(point) or point.is_queued_for_deletion() or not point.is_inside_tree():
			errors.append("SpawnPoints must be live nodes in the scene tree.")
		elif not point.global_position.is_finite():
			errors.append("SpawnPoint position must be finite.")
	return errors


func is_spawning() -> bool:
	return _is_spawning


func is_spawn_complete() -> bool:
	return _started and _completion_emitted and spawned_enemy_count == _total


func get_pending_elapsed_seconds() -> float:
	return _elapsed_seconds


func _choose_weighted_enemy() -> EnemyData:
	var roll := _rng.randf() * _total_roster_weight
	var cumulative := 0.0
	for index in range(_enemies.size()):
		cumulative += _weights[index]
		if roll < cumulative:
			return _enemies[index]
	return _enemies.back()


func _finish_spawning() -> void:
	_is_spawning = false
	_elapsed_seconds = 0.0
	if not _completion_emitted:
		_completion_emitted = true
		spawning_completed.emit(spawned_enemy_count)


func _reject(errors: PackedStringArray) -> void:
	_is_spawning = false
	_started = false
	configuration_rejected.emit(errors)
	for error in errors:
		push_warning("[MassEnemySpawner] %s" % error)


func _spawn_point_path_less_than(first: Node2D, second: Node2D) -> bool:
	return String(first.get_path()) < String(second.get_path())
