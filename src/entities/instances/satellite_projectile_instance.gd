# res://src/entities/satellite_projectile_instance.gd
extends Node3D
class_name SatelliteProjectileInstance

@export var base_speed: float = 350.0 # --- VELOCIDADE DO TIRO DO SATELLITE
@export var base_damage: float = 3.0 # --- DANO DO TIRO DO SATELLITE
@export var base_lifetime: float = 4.0 # --- TEMPO DE VIDA MAXIMO DO PROJÉTIL (SEGUNDOS)
@export var hit_radius: float = 15.0 # --- RAIO DE COLISÃO DO TIRO DO SATELLITE

var speed: float = 350.0
var damage: float = 3.0
var max_lifetime: float = 4.0
var lifetime_timer: float = 0.0

var hit_targets: Dictionary = {}
var active: bool = false
var pool_type: String = "satellite_projectile"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("satellite_projectile")

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	
	var upgrade_mgr = get_node_or_null("/root/UpgradeManager")
	var speed_mult = 1.0
	var dmg_mult = 1.0
	if upgrade_mgr:
		speed_mult = upgrade_mgr.get_multiplier("SatelliteProjectileSpeed")
		dmg_mult = upgrade_mgr.get_multiplier("SatelliteDamage")
		
	damage = base_damage * dmg_mult
	speed = base_speed * speed_mult
	max_lifetime = base_lifetime
	lifetime_timer = 0.0
	hit_targets.clear()
	active = true
	visible = true
	
	if movement_direction.length_squared() > 0.01:
		global_rotation.y = -Vector2(movement_direction.x, movement_direction.z).angle()

func on_pool_deactivate() -> void:
	active = false
	visible = false

func take_damage(_amount: float) -> void:
	# Projectiles do not take damage
	pass

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move node
	global_position += movement_direction * speed * delta
	
	# Lifetime expiration check
	lifetime_timer += delta
	if lifetime_timer >= max_lifetime:
		_recycle()
		return
		
	# Sweep and damage targets in path
	_sweep_damage()

func _sweep_damage() -> void:
	var my_pos_2d = Vector2(global_position.x, global_position.z)
	var targets = GameManager.get_nearby_entities(global_position)
	
	for target in targets:
		if not is_instance_valid(target) or not target.active:
			continue
		if hit_targets.has(target):
			continue
			
		# Check if target is correct type (garbage, asteroid, enemy)
		if not ("pool_type" in target and target.pool_type in ["garbage", "asteroid", "enemy"]):
			continue
			
		# Query target's physical shape bounds if available
		var target_radius = 0.0
		if "radius" in target:
			target_radius = target.radius * target.scale.x
		else:
			var col_shape = target.get_node_or_null("CollisionShape2D")
			if col_shape and col_shape.shape is CircleShape2D:
				target_radius = col_shape.shape.radius * target.scale.x

		var max_dist = hit_radius + target_radius
		var target_pos_2d = target.global_position
		if target is Node3D:
			target_pos_2d = Vector2(target.global_position.x, target.global_position.z)
			
		var target_dist_sq = my_pos_2d.distance_squared_to(target_pos_2d)
		if target_dist_sq <= (max_dist * max_dist):
			# Deal damage to target (as player-sourced damage)
			if target.has_method("take_player_damage"):
				target.take_player_damage(damage)
			else:
				target.take_damage(damage)
				
			hit_targets[target] = true
			
			# Trigger hit flash on visual if applicable
			if has_method("play_hit_vfx"):
				call("play_hit_vfx", target.global_position)
			
			_recycle()
			return

func _recycle() -> void:
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()
