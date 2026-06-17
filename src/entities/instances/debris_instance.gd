# res://src/entities/debris_instance.gd
extends Node3D
class_name DebrisInstance

@export var base_speed: float = 240.0 # --- VELOCIDADE DO DEBRIS (MAIS ALTO = MAIS RAPIDO)
@export var base_damage: float = 3.0 # --- DANO DO DEBRIS AOS INIMIGOS/LIXOS
@export var hit_radius: float = 20.0 # --- RAIO DE COLISÃO DO DEBRIS

var damage: float = 3.0
var max_pierce: int = 0
var current_pierce: int = 0

var hit_targets: Dictionary = {}
var active: bool = false
var pool_type: String = "debris"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("debris")

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	current_pierce = 0
	hit_targets.clear()
	active = true
	visible = true
	add_to_group("damageable")
	
	# Fetch upgrades to calculate final stats
	var damage_mult = UpgradeManager.get_multiplier("DebrisDamage")
	damage = base_damage * damage_mult
	
	max_pierce = int(UpgradeManager.get_total_bonus("DebrisPiercing"))
	
	# Rotate to move direction
	if movement_direction.length_squared() > 0.01:
		global_rotation.y = -Vector2(movement_direction.x, movement_direction.z).angle()

func on_pool_deactivate() -> void:
	active = false
	visible = false
	if is_in_group("damageable"):
		remove_from_group("damageable")

func take_damage(_amount: float) -> void:
	# Debris does not take damage, just ignored
	pass

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move node
	global_position += movement_direction * base_speed * delta
	
	# Check if completely out of screen bounds
	var camera = get_viewport().get_camera_3d()
	if camera:
		var half_height = camera.size * 0.5
		var aspect = 16.0 / 9.0
		var vp_size = get_viewport().size
		if vp_size.y > 0:
			aspect = float(vp_size.x) / float(vp_size.y)
		var half_width = half_height * aspect
		
		var cam_center_2d = Vector2(camera.global_position.x, camera.global_position.z)
		var pos_2d = Vector2(global_position.x, global_position.z)
		var diff = pos_2d - cam_center_2d
		var margin = 60.0
		if abs(diff.x) > half_width + margin or abs(diff.y) > half_height + margin:
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
			
		var target_pos_2d = target.global_position
		if target is Node3D:
			target_pos_2d = Vector2(target.global_position.x, target.global_position.z)
			
		var target_dist_sq = my_pos_2d.distance_squared_to(target_pos_2d)
		if target_dist_sq <= (hit_radius * hit_radius):
			# Deal damage to target (as player-sourced damage)
			if target.has_method("take_player_damage"):
				target.take_player_damage(damage)
			else:
				target.take_damage(damage)
				
			hit_targets[target] = true
			
			# Pierce check
			if current_pierce < max_pierce:
				current_pierce += 1
			else:
				_recycle()
				return

func _recycle() -> void:
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()
