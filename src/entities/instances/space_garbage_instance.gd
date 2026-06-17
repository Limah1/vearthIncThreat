# res://src/entities/space_garbage_instance.gd
extends Node3D
class_name SpaceGarbageInstance

@export var base_speed: float = 30.0 # --- VELOCIDADE DE MOVIMENTO (MAIS ALTO = MAIS RAPIDO)
@export var base_value: float = 1.0 # --- CRÉDITOS CONCEDIDOS NA DESTRUIÇÃO PELO JOGADOR
@export var base_planet_damage: float = 1.0 # --- DANO CAUSADO AO COLIDIR NO PLANETA
@export var base_hp: float = 3.0 # --- VIDA INICIAL DA ENTIDADE

var current_move_speed: float = 30.0
var current_value: float = 10.0
var planet_damage: float = 10.0

var slowdown_timer: float = 0.0
var killed_by_player: bool = false
var is_quality: bool = false

@export_group("Physics & Visual Behavior")
@export var rotation_speed: float = -1.6
@export var radius: float = 18.0

var max_hp: float = 3.0
var hp: float = 3.0
var active: bool = false
var pool_type: String = "garbage"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("garbage")

func on_pool_activate(spawn_pos_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	killed_by_player = false
	slowdown_timer = 0.0
	current_move_speed = base_speed
	scale = Vector3.ONE * 0.2
	active = true
	visible = true
	add_to_group("damageable")
	
	# Calculate linear direction to center once at spawn
	var dir = (Vector3.ZERO - spawn_pos_3d)
	dir.y = 0.0
	movement_direction = dir.normalized()
	
	# Face towards center once
	global_rotation.y = -Vector2(movement_direction.x, movement_direction.z).angle()
	
	# Reset rotation of the child mesh
	if get_child_count() > 0:
		get_child(0).rotation = Vector3.ZERO
		
	# Determine if this garbage is high quality
	is_quality = false
	var quality_lvl = UpgradeManager.get_upgrade_level("GarbageQuality")
	if quality_lvl > 0:
		is_quality = randf() < 0.20
		
	# Apply massify and quality multipliers
	var hp_mult = 1.0
	var value_mult = 1.0
	var scale_mult = 1.0
	
	var massify_lvl = UpgradeManager.get_upgrade_level("massify")
	if massify_lvl > 0:
		hp_mult *= 2.0
		value_mult *= 2.0
		planet_damage = base_planet_damage * 2.0
		scale_mult *= 1.6
	else:
		planet_damage = base_planet_damage
		
	if is_quality:
		hp_mult *= 2.0
		value_mult *= 2.0
		scale_mult *= 1.5
		
	max_hp = base_hp * hp_mult
	hp = max_hp
	current_value = base_value * value_mult
	
	# Animate scale to 100% over 1 second
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * scale_mult, 1.0)

func on_pool_deactivate() -> void:
	active = false
	visible = false
	if is_in_group("damageable"):
		remove_from_group("damageable")

func take_damage(amount: float) -> void:
	if not active:
		return
	slowdown_timer = 0.4
	hp -= amount
	
	var damage_text = str(int(round(amount)))
	if is_quality:
		damage_text += " HQ"
	var popup_color = Color(1.0, 0.85, 0.0) if is_quality else Color(1.0, 1.0, 1.0)
	GameManager.spawn_popup_3d(damage_text, popup_color, global_position)
	
	if hp <= 0.0:
		die()

func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Handle slowdown decay
	var speed = base_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = base_speed * 0.8
	current_move_speed = speed
	
	# Move node linearly
	global_position += movement_direction * current_move_speed * delta
	
	# Spin/tumble the child mesh (e.g. dumpster) on its own local X axis as it travels
	if get_child_count() > 0:
		get_child(0).rotate_object_local(Vector3.RIGHT, rotation_speed * delta)
		
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
		
		# 8 sub-diagonals
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
