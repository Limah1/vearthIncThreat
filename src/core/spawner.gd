# res://src/core/spawner.gd
extends Node
class_name Spawner

@export var base_garbage_amount: int = 20
@export var base_enemy_interval: float = 5.0
@export var base_asteroid_interval: float = 9.0

var enemy_timer: float = 0.0
var asteroid_timer: float = 0.0

var _spawning_orbit_wave: bool = false

# Unlocked status of asteroid sizes and enemies
var is_small_asteroid_unlocked: bool = false
var is_medium_asteroid_unlocked: bool = false
var is_large_asteroid_unlocked: bool = false
var is_enemy_unlocked: bool = false

# Spawner positions lists gathered using Groups (Tags)
var garbage_spawn_points: Array[Node2D] = []
var asteroid_spawn_points: Array[Node2D] = []
var enemy_spawn_points: Array[Node2D] = []

# Referências cacheadas aos masters — evita get_first_node_in_group por evento/frame
var _garbage_master: SpaceGarbageMaster = null
var _enemy_master: Node = null
var _asteroid_master: Node = null

func _ready() -> void:
	# Add spawner to group for easy referencing
	add_to_group("spawner")
	
	# Listen to game state changes
	GameManager.state_changed.connect(_on_state_changed)
	
	# Listen to upgrade purchases
	UpgradeManager.upgrade_purchased.connect(func(_id, _lvl): _update_unlocked_types())
	_update_unlocked_types()
		
	# Gather tagged spawner points
	_gather_tagged_spawner_points()
	
	# Cachear masters (estão na cena quando o spawner faz _ready)
	_garbage_master = get_tree().get_first_node_in_group("garbage_master") as SpaceGarbageMaster
	_enemy_master = get_tree().get_first_node_in_group("enemy_master")
	_asteroid_master = get_tree().get_first_node_in_group("asteroid_master")
	
	# Conectar ao sinal wave_cleared — dispara nova wave sem polling por frame
	if _garbage_master:
		_garbage_master.wave_cleared.connect(_on_garbage_wave_cleared)

func _update_unlocked_types() -> void:
	is_small_asteroid_unlocked = _is_category_purchased("UnlockSmallAsteroid")
	is_medium_asteroid_unlocked = _is_category_purchased("UnlockMediumAsteroid")
	is_large_asteroid_unlocked = _is_category_purchased("UnlockLargeAsteroid")
	is_enemy_unlocked = _is_category_purchased("AlienShips")

func _is_category_purchased(category_name: String) -> bool:
	for upgrade in UpgradeManager.upgrades_list:
		if upgrade.category == category_name:
			if UpgradeManager.get_upgrade_level(upgrade.upgrade_id) > 0:
				return true
	return false

func _gather_tagged_spawner_points() -> void:
	garbage_spawn_points.clear()
	asteroid_spawn_points.clear()
	enemy_spawn_points.clear()
	
	# Fetch by groups (equivalent to Unreal Actor Tags)
	for node in get_tree().get_nodes_in_group("garbage_spawner"):
		if node is Node2D:
			garbage_spawn_points.append(node)
			
	for node in get_tree().get_nodes_in_group("asteroid_spawner"):
		if node is Node2D:
			asteroid_spawn_points.append(node)
			
	for node in get_tree().get_nodes_in_group("enemy_spawner"):
		if node is Node2D:
			enemy_spawn_points.append(node)

# Fallback generator if user hasn't defined nodes in the editor groups
func _ensure_fallback_spawners() -> void:
	if garbage_spawn_points.is_empty():
		# Spawn 40 orbit points around the planet
		for i in range(40):
			var angle = i * (TAU / 40.0)
			var temp_spawner = Node2D.new()
			temp_spawner.global_position = Vector2.from_angle(angle) * 140.0
			temp_spawner.name = "FallbackGarbageSpawner_" + str(i)
			add_child(temp_spawner)
			garbage_spawn_points.append(temp_spawner)
			
	if asteroid_spawn_points.is_empty():
		# 4 distant asteroid points
		for i in range(4):
			var angle = i * (TAU / 4.0) + (PI / 4.0)
			var temp_spawner = Node2D.new()
			temp_spawner.global_position = Vector2.from_angle(angle) * 500.0
			temp_spawner.name = "FallbackAsteroidSpawner_" + str(i)
			add_child(temp_spawner)
			asteroid_spawn_points.append(temp_spawner)
			
	if enemy_spawn_points.is_empty():
		# 8 side spawn points outside screen
		for i in range(8):
			var angle = i * (TAU / 8.0)
			var temp_spawner = Node2D.new()
			temp_spawner.global_position = Vector2.from_angle(angle) * 550.0
			temp_spawner.name = "FallbackEnemySpawner_" + str(i)
			add_child(temp_spawner)
			enemy_spawn_points.append(temp_spawner)

func start_spawning() -> void:
	_ensure_fallback_spawners()
	enemy_timer = 0.0
	asteroid_timer = 0.0
	_spawning_orbit_wave = false
	_start_orbit_garbage_wave()

func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
		
	# 1. ORBIT GARBAGE: controlado por sinal wave_cleared — sem polling de grupo aqui
	
	# 2. ENEMY SPAWNING LOOP
	var _enemy_mult = UpgradeManager.get_multiplier("AutoClickRate")
	var side_switch_interval = base_enemy_interval / (1.0 + (GameManager.current_zone - 1) * 0.1)
	side_switch_interval = max(0.2, side_switch_interval)
	
	enemy_timer += delta
	if enemy_timer >= side_switch_interval:
		enemy_timer = 0.0
		_spawn_enemy()
		
	# 3. ASTEROID SPAWNING LOOP
	var asteroid_interval = base_asteroid_interval / (1.0 + (GameManager.current_zone - 1) * 0.05)
	asteroid_interval = max(1.5, asteroid_interval)
	
	asteroid_timer += delta
	if asteroid_timer >= asteroid_interval:
		asteroid_timer = 0.0
		_spawn_asteroid()

func _start_orbit_garbage_wave() -> void:
	_spawning_orbit_wave = true
	
	
	var total_garbage = base_garbage_amount

	
	# Start cascading spawns (immediate is delay = 0)
	_spawn_garbage_chunk(total_garbage, 0.0)

## Disparado pelo sinal wave_cleared do SpaceGarbageMaster
func _on_garbage_wave_cleared() -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING and not _spawning_orbit_wave:
		_start_orbit_garbage_wave()

func _spawn_garbage_chunk(remaining_garbage: int, delay_seconds: float) -> void:
	if remaining_garbage <= 0:
		_spawning_orbit_wave = false
		return
		
	if delay_seconds > 0.0:
		get_tree().create_timer(delay_seconds).timeout.connect(
			func():
				if not is_inside_tree():
					return
				if GameManager.current_state == GameManager.GameState.PLAYING:
					_do_spawn_chunk(remaining_garbage)
				else:
					_spawning_orbit_wave = false
		)
	else:
		_do_spawn_chunk(remaining_garbage)

func _do_spawn_chunk(remaining_garbage: int) -> void:
	var points_count = garbage_spawn_points.size()
	if points_count == 0:
		_spawning_orbit_wave = false
		return
		
	if not _garbage_master:
		_garbage_master = get_tree().get_first_node_in_group("garbage_master") as SpaceGarbageMaster
	if not _garbage_master:
		_spawning_orbit_wave = false
		return
		
	var spawn_count = min(remaining_garbage, points_count)
	
	# Fisher-Yates parcial in-place: sem duplicate() nem shuffle() completo
	for i in range(spawn_count):
		var j = randi_range(i, points_count - 1)
		var tmp = garbage_spawn_points[i]
		garbage_spawn_points[i] = garbage_spawn_points[j]
		garbage_spawn_points[j] = tmp
	
	for i in range(spawn_count):
		_garbage_master.spawn_garbage(garbage_spawn_points[i].global_position)
		
	var next_remaining = remaining_garbage - spawn_count
	if next_remaining > 0:
		_spawn_garbage_chunk(next_remaining, 1.0)
	else:
		_spawning_orbit_wave = false

func _spawn_enemy() -> void:
	if enemy_spawn_points.is_empty():
		return
	if not is_enemy_unlocked:
		return
		
	if not _enemy_master:
		_enemy_master = get_tree().get_first_node_in_group("enemy_master")
	if not _enemy_master:
		return
		
	var spawner_node = enemy_spawn_points.pick_random()
	var spawn_pos_3d = Vector3(spawner_node.global_position.x, 0.0, spawner_node.global_position.y)
	_enemy_master.spawn_enemy(spawn_pos_3d)

func _spawn_asteroid() -> void:
	if asteroid_spawn_points.is_empty():
		return
		
	# Check which asteroid types are unlocked
	var allowed = []
	if is_small_asteroid_unlocked:
		allowed.append("small")
	if is_medium_asteroid_unlocked:
		allowed.append("medium")
	if is_large_asteroid_unlocked:
		allowed.append("large")
		
	if allowed.is_empty():
		return # Do not spawn any asteroids until unlocked in skill tree
		
	# Determine weights based on Chance upgrades
	var weights = []
	for type in allowed:
		match type:
			"small":
				var w = UpgradeManager.get_total_bonus("ChanceSmallAsteroid")
				weights.append(w if w > 0.0 else 1.0)
			"medium":
				var w = UpgradeManager.get_total_bonus("ChanceMediumAsteroid")
				weights.append(w if w > 0.0 else 1.0)
			"large":
				var w = UpgradeManager.get_total_bonus("ChanceLargeAsteroid")
				weights.append(w if w > 0.0 else 1.0)
				
	var extra_asteroids = int(UpgradeManager.get_total_bonus("AsteroidAmount"))
	var spawn_count = 5 + extra_asteroids
	
	if not _asteroid_master:
		_asteroid_master = get_tree().get_first_node_in_group("asteroid_master")
	if not _asteroid_master:
		return
	
	for i in range(spawn_count):
		var chosen_type = _pick_weighted(allowed, weights)
		var spawner_node = asteroid_spawn_points.pick_random()
		var dir_2d = (Vector2.ZERO - spawner_node.global_position).normalized()
		var dir_3d = Vector3(dir_2d.x, 0.0, dir_2d.y)
		
		var offset = Vector2.ZERO
		if i > 0:
			offset = Vector2(randf_range(-25.0, 25.0), randf_range(-25.0, 25.0))
			
		var spawn_pos_3d = Vector3(spawner_node.global_position.x + offset.x, 0.0, spawner_node.global_position.y + offset.y)
		_asteroid_master.spawn_asteroid(spawn_pos_3d, dir_3d, chosen_type)

func _pick_weighted(options: Array, weights: Array) -> String:
	var sum = 0.0
	for w in weights:
		sum += w
	var r = randf() * sum
	var accum = 0.0
	for i in range(options.size()):
		accum += weights[i]
		if r <= accum:
			return options[i]
	return options[0]

func _on_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.PLAYING:
		# If timer was reset (i.e. starting new wave), initialize waves
		if GameManager.decay_timer >= GameManager.decay_time_limit - 0.1:
			start_spawning()
