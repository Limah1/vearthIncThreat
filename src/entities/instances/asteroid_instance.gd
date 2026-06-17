# res://src/entities/asteroid_instance.gd
extends Node3D
class_name AsteroidInstance

@export var base_speed: float = 85.0 # --- VELOCIDADE DE MOVIMENTO (MAIS ALTO = MAIS RAPIDO)
@export var base_value: float = 30.0 # --- CRÉDITOS CONCEDIDOS NA DESTRUIÇÃO
@export var base_planet_damage: float = 20.0 # --- DANO CAUSADO AO COLIDIR NO PLANETA

var current_move_speed: float = 85.0
var current_value: float = 30.0
var planet_damage: float = 20.0

var killed_by_player: bool = false
var slowdown_timer: float = 0.0
@export var base_max_hp: float = 35.0 # --- VIDA INICIAL DO ASTEROIDE

var max_hp: float = 35.0
var hp: float = 35.0
var active: bool = false
var pool_type: String = "asteroid"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO
var asteroid_type: String = "small"
var radius: float = 24.0 # default radius for SMALL collision checks

func _ready() -> void:
	add_to_group("asteroid")

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	killed_by_player = false
	slowdown_timer = 0.0
	active = true
	visible = true
	add_to_group("damageable")

func on_pool_deactivate() -> void:
	active = false
	visible = false
	if is_in_group("damageable"):
		remove_from_group("damageable")

func set_asteroid_type(type: String) -> void:
	asteroid_type = type
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.1
	
	match type:
		"small":
			max_hp = base_max_hp * zone_scale
			current_value = base_value * zone_scale
			planet_damage = base_planet_damage * zone_scale
			radius = 24.0
		"medium":
			max_hp = (base_max_hp * (100.0 / 35.0)) * zone_scale
			current_value = (base_value * 3.0) * zone_scale
			planet_damage = (base_planet_damage * 2.5) * zone_scale
			radius = 45.0
		"large":
			max_hp = (base_max_hp * (300.0 / 35.0)) * zone_scale
			current_value = (base_value * 8.0) * zone_scale
			planet_damage = (base_planet_damage * 6.0) * zone_scale
			radius = 70.0
			
	hp = max_hp
	current_move_speed = base_speed * (1.0 + (GameManager.current_zone - 1) * 0.05)
	
	# Rebuild 3D visual dynamically
	for child in get_children():
		child.queue_free()
		
	var fbx_scene: PackedScene = null
	match type:
		"small": fbx_scene = load("res://src/assets/3DAssets/meteoro_small.FBX")
		"medium": fbx_scene = load("res://src/assets/3DAssets/meteoro_medium.FBX")
		"large": fbx_scene = load("res://src/assets/3DAssets/meteoro_big.FBX")
		
	if fbx_scene:
		var fbx_node = fbx_scene.instantiate()
		var scale_val = 90.0
		match type:
			"small": scale_val = 90.0
			"medium": scale_val = 140.0
			"large": scale_val = 220.0
		fbx_node.scale = Vector3(scale_val, scale_val, scale_val)
		add_child(fbx_node)

func take_damage(amount: float) -> void:
	if not active:
		return
	slowdown_timer = 0.4
	hp -= amount
	
	var damage_text = str(int(round(amount)))
	GameManager.spawn_popup_3d(damage_text, Color(1.0, 1.0, 1.0), global_position)
	
	if hp <= 0.0:
		die()

func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	var speed = current_move_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = current_move_speed * 0.8
		
	# Move node
	global_position += movement_direction * speed * delta
	
	# Rotate the asteroid slowly on its child mesh
	if get_child_count() > 0:
		var mesh_node = get_child(0)
		mesh_node.rotate_x(0.6 * delta)
		mesh_node.rotate_z(0.3 * delta)
		
	# Check for planet collision (planet is at center 0,0,0, radius ~ 45)
	if global_position.length() < 45.0:
		var planet = get_tree().current_scene.find_child("PlayerPlanet", true, false)
		if planet:
			planet.take_damage(planet_damage)
			
		killed_by_player = false
		die()

func stop_movement() -> void:
	current_move_speed = 0.0
	base_speed = 0.0

func die() -> void:
	active = false
	_on_death()
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()

func _on_death() -> void:
	if killed_by_player:
		GameManager.add_credits_delayed(current_value, global_position)
		GameManager.register_eliminated_threat()
		
		# Roll debris chance
		var roll_chance = GameManager.debris_chance
		var roll_success = randf() < roll_chance
		
		if "b_next_debris_guaranteed" in UpgradeManager and UpgradeManager.get("b_next_debris_guaranteed") == true:
			roll_success = true
			UpgradeManager.set("b_next_debris_guaranteed", false)
			
		if roll_success:
			_spawn_debris_burst()
			GameManager.debris_chance = 0.20

func _spawn_debris_burst() -> void:
	var debris_master = get_tree().get_first_node_in_group("debris_master")
	if not debris_master:
		return
		
	var extra_debris = int(UpgradeManager.get_total_bonus("DebrisAmount"))
	var count = clamp(2 + extra_debris, 1, 16)
	
	var directions = [
		Vector3(0, 0, -1),
		Vector3(0, 0, 1),
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, 1).normalized(),
		Vector3(-1, 0, -1).normalized(),
		Vector3(1, 0, 1).normalized(),
		
		Vector3(0.5, 0, -1).normalized(),
		Vector3(1, 0, -0.5).normalized(),
		Vector3(1, 0, 0.5).normalized(),
		Vector3(0.5, 0, 1).normalized(),
		Vector3(-0.5, 0, 1).normalized(),
		Vector3(-1, 0, 0.5).normalized(),
		Vector3(-1, 0, -0.5).normalized(),
		Vector3(-0.5, 0, -1).normalized()
	]
	
	directions.shuffle()
	
	for i in range(count):
		var dir = directions[i]
		var random_variation = Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
		var final_dir = (dir + random_variation).normalized()
		debris_master.spawn_debris(global_position, final_dir)
