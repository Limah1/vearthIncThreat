# res://src/core/spawner.gd
extends Node
class_name Spawner

@export var base_garbage_amount: int = 25
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
		
	# 1. ORBIT GARBAGE RESPAWN
	# If there is no active garbage, spawn a new wave
	var active_garbage = get_tree().get_nodes_in_group("garbage")
	var active_count = 0
	for g in active_garbage:
		if g.active:
			active_count += 1
			
	if active_count == 0 and not _spawning_orbit_wave:
		_start_orbit_garbage_wave()
		
	# 2. ENEMY SPAWNING LOOP
	var _enemy_mult = UpgradeManager.get_multiplier("AutoClickRate") # Scale wave pacing with difficulty
	var side_switch_interval = base_enemy_interval / (1.0 + (GameManager.current_zone - 1) * 0.1)
	side_switch_interval = max(0.2, side_switch_interval) # Cap spawning limit
	
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
	
	# Calculate total garbage count from upgrades (additive)
	var garbage_bonus = UpgradeManager.get_total_bonus("GarbageAmount")
	var total_garbage = int(round(base_garbage_amount + garbage_bonus))
	
	# Shuffle spawn points to ensure random unique selection
	var available_points = garbage_spawn_points.duplicate()
	available_points.shuffle()
	
	# Spawning Stage 1 (Immediate)
	var points_count = available_points.size()
	var immediate_spawn_count = min(total_garbage, points_count)
	
	if not GameManager.object_pooler:
		_spawning_orbit_wave = false
		return
	var pooler = GameManager.object_pooler
		
	for i in range(immediate_spawn_count):
		var point = available_points[i]
		# Spawn space garbage heading straight inwards
		var dir = (Vector2.ZERO - point.global_position).normalized()
		pooler.borrow_from_pool("garbage", point.global_position, dir)
		
	var remaining_count = total_garbage - immediate_spawn_count
	if remaining_count > 0:
		# Stage 2: Spawn remaining after 2.0s delay
		get_tree().create_timer(2.0).timeout.connect(
			func():
				if GameManager.current_state == GameManager.GameState.PLAYING:
					for i in range(remaining_count):
						var point = available_points[i % points_count]
						var dir = (Vector2.ZERO - point.global_position).normalized()
						pooler.borrow_from_pool("garbage", point.global_position, dir)
				_spawning_orbit_wave = false
		)
	else:
		_spawning_orbit_wave = false

func _spawn_enemy() -> void:
	if not GameManager.object_pooler or enemy_spawn_points.is_empty():
		return
	if not is_enemy_unlocked:
		return # Do not spawn enemies until AutoClickRate (Auto Clicker) is unlocked
	var pooler = GameManager.object_pooler
		
	# Choose random spawner from the tagged list
	var spawner_node = enemy_spawn_points.pick_random()
	# Spawn enemy and let it navigate inwards
	pooler.borrow_from_pool("enemy", spawner_node.global_position)

func _spawn_asteroid() -> void:
	if not GameManager.object_pooler or asteroid_spawn_points.is_empty():
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
	
	var pooler = GameManager.object_pooler
	
	for i in range(spawn_count):
		var chosen_type = _pick_weighted(allowed, weights)
		var spawner_node = asteroid_spawn_points.pick_random()
		var dir = (Vector2.ZERO - spawner_node.global_position).normalized()
		
		# Slight offset to prevent exact overlap at spawn time
		var offset = Vector2.ZERO
		if i > 0:
			offset = Vector2(randf_range(-25.0, 25.0), randf_range(-25.0, 25.0))
			
		var asteroid_node = pooler.borrow_from_pool("asteroid", spawner_node.global_position + offset, dir)
		if asteroid_node and asteroid_node.has_method("set_asteroid_type"):
			asteroid_node.call("set_asteroid_type", chosen_type)

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
