# res://src/entities/enemy_projectile.gd
extends Entity2D
class_name EnemyProjectile

@export var speed: float = 140.0
@export var damage: float = 4.0

var arena_radius: float = 450.0

func _init() -> void:
	pool_type = "enemy_projectile"

func _ready() -> void:
	add_to_group("enemy_projectile")

func on_pool_activate(spawn_pos_2d: Vector2, direction: Vector2) -> void:
	# Store stats scaled slightly by current zone
	var zone_scale = 1.0 + (get_node("/root/GameManager").current_zone - 1) * 0.08
	damage = 4.0 * zone_scale
	
	super.on_pool_activate(spawn_pos_2d, direction * speed)
	
	if direction.length_squared() > 0.01:
		rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move node
	var _collision = move_and_collide(velocity * delta)
	
	# Check distance to planet
	var dist = global_position.length()
	if dist < 45.0:
		# Hit planet!
		var planet = get_tree().current_scene.find_child("PlayerPlanet", true, false) as PlayerPlanet
		if planet:
			planet.take_damage(damage)
		_recycle()
		return
		
	# Check out of bounds
	if dist > arena_radius:
		_recycle()
		return
		
	# Sync position/rotation to 3D visual
	super._physics_process(delta)

func _recycle() -> void:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.object_pooler:
		game_mgr.object_pooler.return_to_pool("enemy_projectile", self)
	else:
		queue_free()
