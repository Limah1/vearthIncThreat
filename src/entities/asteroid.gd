# res://src/entities/asteroid.gd
extends Entity2D
class_name Asteroid

@export var base_speed: float = 85.0
@export var base_value: float = 30.0
@export var base_planet_damage: float = 20.0

var current_move_speed: float = 85.0
var current_value: float = 30.0
var planet_damage: float = 20.0

var killed_by_player: bool = false
var slowdown_timer: float = 0.0
var base_max_hp: float = 35.0

var asteroid_type: String = "small"

func _init() -> void:
	pool_type = "asteroid"

func _ready() -> void:
	add_to_group("asteroid")
	base_max_hp = max_hp

func on_pool_activate(spawn_pos_2d: Vector2, initial_velocity: Vector2) -> void:
	# High base health for asteroids
	max_hp = base_max_hp
	hp = max_hp
	super.on_pool_activate(spawn_pos_2d, initial_velocity)
	killed_by_player = false
	slowdown_timer = 0.0
	
	# Scale stats with current zone/difficulty
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.1
	max_hp = base_max_hp * zone_scale
	hp = max_hp
	current_value = base_value * zone_scale
	planet_damage = base_planet_damage * zone_scale
	current_move_speed = base_speed * (1.0 + (GameManager.current_zone - 1) * 0.05)

func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func take_damage(amount: float) -> void:
	# Trigger slowdown on hit: 20% reduction (speed * 0.8) for 0.4s
	slowdown_timer = 0.4
	super.take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Asteroids move in a direct line towards center (planet)
	var dir = (Vector2.ZERO - global_position).normalized()
	
	var speed = current_move_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = current_move_speed * 0.8
		
	velocity = dir * speed
	
	# Move node
	global_position += velocity * delta
	
	# Sync position/rotation to 3D mesh
	super._physics_process(delta)
	
	# Rotate the asteroid slowly on its child mesh to prevent gimbal lock
	if visual_3d and visual_3d.get_child_count() > 0:
		var mesh_node = visual_3d.get_child(0)
		mesh_node.rotate_x(0.6 * delta)
		mesh_node.rotate_z(0.3 * delta)
		
	# Check for planet collision
	if global_position.length() < 45.0:
		var planet = get_tree().current_scene.find_child("PlayerPlanet", true, false) as PlayerPlanet
		if planet:
			planet.take_damage(planet_damage)
		
		# Return to pool
		killed_by_player = false
		if GameManager.object_pooler:
			GameManager.object_pooler.return_to_pool("asteroid", self )
		else:
			queue_free()

func _on_death() -> void:
	if killed_by_player:
		# Award credits delayed by 0.2s
		var spawn_pos = visual_3d.global_position if visual_3d else Vector3(global_position.x, 0.0, global_position.y)
		GameManager.add_credits_delayed(current_value, spawn_pos)
		
		# Register threat eliminated
		GameManager.register_eliminated_threat()
		
		# Roll debris chance
		var roll_chance = GameManager.debris_chance
		var roll_success = randf() < roll_chance
		
		# Check if UpgradeManager has a guaranteed debris flag
		if "b_next_debris_guaranteed" in UpgradeManager and UpgradeManager.get("b_next_debris_guaranteed") == true:
			roll_success = true
			UpgradeManager.set("b_next_debris_guaranteed", false)
			
		if roll_success:
			_spawn_debris_burst()
			GameManager.debris_chance = 0.20
			
		# Asteroids explode. We can trigger a small screen shake or particle burst in 3D
		_trigger_destruction_fx()

func _spawn_debris_burst() -> void:
	if not GameManager.object_pooler:
		return
	var pooler = GameManager.object_pooler
	
	# Determine how many debris to spawn based on DebrisAmount upgrade level
	var extra_debris = int(UpgradeManager.get_total_bonus("DebrisAmount"))
	var count = clamp(2 + extra_debris, 1, 8)
	
	# Fixed 8 directions order: North, South, East, West, NE, SW, NW, SE
	var directions = [
		Vector2(0, -1),                  # North
		Vector2(0, 1),                   # South
		Vector2(1, 0),                   # East
		Vector2(-1, 0),                  # West
		Vector2(1, -1).normalized(),     # North-East
		Vector2(-1, 1).normalized(),     # South-West
		Vector2(-1, -1).normalized(),    # North-West
		Vector2(1, 1).normalized()       # South-East
	]
	
	for i in range(count):
		var dir = directions[i]
		pooler.borrow_from_pool("debris", global_position, dir)

func _trigger_destruction_fx() -> void:
	# Can trigger a camera shake or explosion effect if visual_3d has one
	if visual_3d and visual_3d.has_method("play_explosion"):
		visual_3d.call("play_explosion")

func set_asteroid_type(type: String) -> void:
	asteroid_type = type
	
	# Scale stats with current zone/difficulty
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.1
	
	# Adjust stats depending on the asteroid size
	match type:
		"small":
			max_hp = base_max_hp * zone_scale
			current_value = base_value * zone_scale
			planet_damage = base_planet_damage * zone_scale
		"medium":
			max_hp = (base_max_hp * (100.0 / 35.0)) * zone_scale
			current_value = (base_value * 3.0) * zone_scale
			planet_damage = (base_planet_damage * 2.5) * zone_scale
		"large":
			max_hp = (base_max_hp * (300.0 / 35.0)) * zone_scale
			current_value = (base_value * 8.0) * zone_scale
			planet_damage = (base_planet_damage * 6.0) * zone_scale
			
	hp = max_hp
	
	# Swap FBX model in 3D visual dynamically
	if visual_3d:
		# Remove old FBX children
		for child in visual_3d.get_children():
			child.queue_free()
			
		# Load the correct FBX based on type
		var fbx_scene: PackedScene
		match type:
			"small": fbx_scene = load("res://src/assets/3DAssets/meteoro_small.FBX")
			"medium": fbx_scene = load("res://src/assets/3DAssets/meteoro_medium.FBX")
			"large": fbx_scene = load("res://src/assets/3DAssets/meteoro_big.FBX")
			
		if fbx_scene:
			var fbx_node = fbx_scene.instantiate()
			# Set scale (Unreal models are very small in Godot unit scale, so we scale them up)
			var scale_val = 90.0
			match type:
				"small": scale_val = 90.0
				"medium": scale_val = 140.0
				"large": scale_val = 220.0
			fbx_node.scale = Vector3(scale_val, scale_val, scale_val)
			visual_3d.add_child(fbx_node)
