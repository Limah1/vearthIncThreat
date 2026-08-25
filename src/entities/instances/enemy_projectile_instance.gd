# res://src/entities/enemy_projectile_instance.gd
extends Node3D
class_name EnemyProjectileInstance

const DamageSystemScript = preload("res://src/core/damage_system.gd")

@export var speed: float = 140.0 # --- VELOCIDADE DO TIRO DO INIMIGO
@export var damage: float = 4.0 # --- DANO QUE O TIRO DO INIMIGO CAUSA NO PLANETA
var arena_radius: float = 450.0

var active: bool = false
var pool_type: String = "enemy_projectile"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("enemy_projectile")

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.08
	damage = 4.0 * zone_scale
	
	active = true
	visible = true
	GameManager.register_movement(self)
	GameManager.register_multimesh_visual(self, "enemy_projectile")
	
	if movement_direction.length_squared() > 0.01:
		global_rotation.y = -Vector2(movement_direction.x, movement_direction.z).angle()

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_movement(self)
	GameManager.unregister_multimesh_visual(self, "enemy_projectile")

func take_damage(_amount: float) -> void:
	# Projectiles do not take damage
	pass

func _manager_move(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move node
	global_position += movement_direction * speed * delta

	if GameManager.try_damage_barrier(global_position, damage, 5.0):
		_recycle()
		return
	
	# Check distance to planet
	var dist = global_position.length()
	if dist < 45.0:
		var planet = GameManager.get_player_planet()
		if planet:
			DamageSystemScript.apply(planet, damage, DamageSystemScript.Team.ENEMY)
		_recycle()
		return
		
	# Check out of bounds
	if dist > arena_radius:
		_recycle()
		return

func _recycle() -> void:
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()
