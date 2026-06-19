# res://src/entities/enemy_spaceship_instance.gd
extends Node3D
class_name EnemySpaceshipInstance

@export var base_hp: float = 12.0 # --- VIDA INICIAL DO INIMIGO
@export var base_value: float = 20.0 # --- CRÉDITOS CONCEDIDOS NA DESTRUIÇÃO
@export var fly_in_speed: float = 120.0 # --- VELOCIDADE DE ENTRADA (MAIS ALTO = MAIS RAPIDO)
@export var orbit_speed: float = 0.5 # --- VELOCIDADE DE ORBITA EM VOLTA DO PLANETA
@export var fire_interval: float = 2.5 # --- INTERVALO DE DISPARO EM SEGUNDOS (MAIS BAIXO = ATIRA MAIS RAPIDO)

var current_value: float = 20.0
var orbit_radius: float = 200.0
var current_angle: float = 0.0
var is_orbiting: bool = false
var fire_timer: float = 0.0
var killed_by_player: bool = false

var max_hp: float = 12.0
var hp: float = 12.0
var active: bool = false
var pool_type: String = "enemy"
var master_node: Node = null
var radius: float = 20.0 # Bounding radius for collision checks

func _ready() -> void:
	add_to_group("enemy")

func on_pool_activate(spawn_pos_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.12
	max_hp = base_hp * zone_scale
	hp = max_hp
	
	current_value = base_value * zone_scale
	killed_by_player = false
	is_orbiting = false
	current_angle = Vector2(spawn_pos_3d.x, spawn_pos_3d.z).angle()
	
	# Orbit setup
	orbit_radius = randf_range(160.0, 240.0)
	if randf() > 0.5:
		orbit_speed = abs(orbit_speed)
	else:
		orbit_speed = - abs(orbit_speed)
		
	fire_timer = randf() * fire_interval
	active = true
	visible = true
	GameManager.register_active_damageable(self)

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_active_damageable(self)

func take_damage(amount: float) -> void:
	if not active:
		return
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
		
	var to_center = Vector3.ZERO - global_position
	to_center.y = 0.0
	var dist = to_center.length()
	
	if not is_orbiting:
		# Fly inwards
		if dist <= orbit_radius:
			is_orbiting = true
			current_angle = Vector2(global_position.x, global_position.z).angle()
		else:
			var velocity = to_center.normalized() * fly_in_speed
			global_rotation.y = - Vector2(to_center.x, to_center.z).angle() + PI
			global_position += velocity * delta
	else:
		# Orbit rotation
		current_angle += orbit_speed * delta
		global_position = Vector3(cos(current_angle) * orbit_radius, 0.0, sin(current_angle) * orbit_radius)
		global_rotation.y = - current_angle + PI / 2.0 # Face the planet center (adjusted for 3D orientation)
		
		# Shoot loop
		fire_timer += delta
		if fire_timer >= fire_interval:
			fire_timer = 0.0
			_shoot_projectile()

func _shoot_projectile() -> void:
	var master_nodes = get_tree().get_nodes_in_group("enemy_proj_master")
	if master_nodes.is_empty():
		return
	var master_node_proj = master_nodes[0]
	
	# Shoot towards center
	var shoot_dir = (Vector3.ZERO - global_position).normalized()
	shoot_dir.y = 0.0
	shoot_dir = shoot_dir.normalized()
	
	master_node_proj.spawn_enemy_projectile(global_position, shoot_dir)

func stop_movement() -> void:
	orbit_speed = 0.0
	fly_in_speed = 0.0

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
		if has_method("play_explosion"):
			call("play_explosion")
