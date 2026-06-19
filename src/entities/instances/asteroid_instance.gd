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

var fbx_small: Node3D = null
var fbx_medium: Node3D = null
var fbx_large: Node3D = null

func _ready() -> void:
	add_to_group("asteroid")
	
	# Pre-instantiate visual meshes to avoid runtime instantiations/disk loading
	var scene_small = load("res://src/assets/3DAssets/meteoro_small.FBX")
	if scene_small:
		fbx_small = scene_small.instantiate() as Node3D
		fbx_small.scale = Vector3(90.0, 90.0, 90.0)
		fbx_small.visible = false
		add_child(fbx_small)
		
	var scene_medium = load("res://src/assets/3DAssets/meteoro_medium.FBX")
	if scene_medium:
		fbx_medium = scene_medium.instantiate() as Node3D
		fbx_medium.scale = Vector3(140.0, 140.0, 140.0)
		fbx_medium.visible = false
		add_child(fbx_medium)
		
	var scene_large = load("res://src/assets/3DAssets/meteoro_big.FBX")
	if scene_large:
		fbx_large = scene_large.instantiate() as Node3D
		fbx_large.scale = Vector3(220.0, 220.0, 220.0)
		fbx_large.visible = false
		add_child(fbx_large)

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	killed_by_player = false
	slowdown_timer = 0.0
	active = true
	visible = true
	GameManager.register_active_damageable(self)
	
	# Reset rotations of cached visual meshes
	if fbx_small:
		fbx_small.rotation = Vector3.ZERO
	if fbx_medium:
		fbx_medium.rotation = Vector3.ZERO
	if fbx_large:
		fbx_large.rotation = Vector3.ZERO

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_active_damageable(self)

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
	
	# Toggle visibility instead of queue_free & load/instantiate at runtime
	if fbx_small:
		fbx_small.visible = (type == "small")
	if fbx_medium:
		fbx_medium.visible = (type == "medium")
	if fbx_large:
		fbx_large.visible = (type == "large")

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
	
	# Rotate the active mesh slowly
	var active_mesh: Node3D = null
	match asteroid_type:
		"small": active_mesh = fbx_small
		"medium": active_mesh = fbx_medium
		"large": active_mesh = fbx_large
		
	if active_mesh and is_instance_valid(active_mesh):
		active_mesh.rotate_x(0.6 * delta)
		active_mesh.rotate_z(0.3 * delta)
		
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
			GameManager.debris_chance = 0.2 + UpgradeManager.get_total_bonus("DebrisChance")

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
