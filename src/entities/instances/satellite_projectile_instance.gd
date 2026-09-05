# res://src/entities/satellite_projectile_instance.gd
extends Node3D
class_name SatelliteProjectileInstance

const DamageSystemScript = preload("res://src/core/damage_system.gd")

@export var base_speed: float = 350.0 # --- VELOCIDADE DO TIRO DO SATELLITE
@export var base_damage: float = 3.0 # --- DANO DO TIRO DO SATELLITE
@export var base_lifetime: float = 4.0 # --- TEMPO DE VIDA MAXIMO DO PROJÉTIL (SEGUNDOS)
@export var hit_radius: float = 9.0 # --- RAIO DE COLISÃO DO TIRO DO SATELLITE

var speed: float = 350.0
var damage: float = 3.0
var max_lifetime: float = 4.0
var lifetime_timer: float = 0.0
var _mass_sweep_origin := Vector3.ZERO

var hit_targets: Dictionary = {}
var active: bool = false
var pool_type: String = "satellite_projectile"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("satellite_projectile")

func on_pool_activate(
	spawn_pos_3d: Vector3,
	dir_3d: Vector3,
	damage_override: float = -1.0
) -> void:
	global_position = spawn_pos_3d
	_mass_sweep_origin = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	
	var upgrade_mgr = UpgradeManager
	var speed_mult = 1.0
	var dmg_mult = 1.0
	# Regular satellites keep using their upgrades. Turrets provide their own
	# damage value and therefore remain independent from satellite upgrades.
	if upgrade_mgr and damage_override < 0.0:
		speed_mult = upgrade_mgr.get_multiplier("SatelliteProjectileSpeed")
		dmg_mult = upgrade_mgr.get_multiplier("SatelliteDamage")
		
	damage = damage_override if damage_override >= 0.0 else base_damage * dmg_mult
	speed = base_speed * speed_mult
	max_lifetime = base_lifetime
	if GameManager.mass_combat is EnemyGPUCombat:
		GameManager.mass_combat.fire_projectile_with_radius(spawn_pos_3d, movement_direction, damage, speed, max_lifetime, DamageSystemScript.Team.ALLY, hit_radius)
		call_deferred("_recycle")
		return
	lifetime_timer = 0.0
	hit_targets.clear()
	active = true
	visible = true
	GameManager.register_movement(self)
	GameManager.register_collision(self)
	GameManager.register_multimesh_visual(self, "satellite_projectile")
	
	if movement_direction.length_squared() > 0.01:
		global_rotation.y = - Vector2(movement_direction.x, movement_direction.z).angle()

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_movement(self)
	GameManager.unregister_collision(self)
	GameManager.unregister_multimesh_visual(self, "satellite_projectile")

func take_damage(_amount: float) -> void:
	# Projectiles do not take damage
	pass

func _manager_move(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move node
	global_position += movement_direction * speed * delta
	
	# Lifetime expiration check
	lifetime_timer += delta
	if lifetime_timer >= max_lifetime:
		_recycle()
		return
		

func _manager_collision() -> void:
	if not is_inside_tree() or not active:
		return
	_sweep_damage()

func _sweep_damage() -> void:
	if is_instance_valid(GameManager.mass_combat):
		var hits: int = GameManager.mass_combat.damage_line(_mass_sweep_origin, global_position, hit_radius, damage, true)
		_mass_sweep_origin = global_position
		if hits > 0:
			_recycle()
		return
	var my_pos_2d = Vector2(global_position.x, global_position.z)
	var targets = GameManager.get_nearby_entities(
		global_position,
		hit_radius + GameManager.MAX_DAMAGEABLE_RADIUS
	)
	
	for target in targets:
		if not is_instance_valid(target) or not target.active:
			continue
		if hit_targets.has(target):
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
			DamageSystemScript.apply(target, damage, DamageSystemScript.Team.ALLY)
				
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
