# res://src/entities/satellite_projectile.gd
extends Entity2D
class_name SatelliteProjectile

@export var base_speed: float = 350.0
@export var base_damage: float = 3.0
@export var base_lifetime: float = 4.0
@export var hit_radius: float = 15.0

var damage: float = 3.0
var max_lifetime: float = 4.0
var lifetime_timer: float = 0.0

var hit_targets: Dictionary = {}

func _init() -> void:
	pool_type = "satellite_projectile"

func _ready() -> void:
	add_to_group("satellite_projectile")

func on_pool_activate(spawn_pos_2d: Vector2, direction: Vector2) -> void:
	super.on_pool_activate(spawn_pos_2d, direction * base_speed)
	lifetime_timer = 0.0
	hit_targets.clear()
	damage = base_damage

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move using standard linear velocity
	move_and_collide(velocity * delta)
	
	# Lifetime expiration check
	lifetime_timer += delta
	if lifetime_timer >= max_lifetime:
		_recycle()
		return
		
	# Sync rotation to movement direction
	if velocity.length_squared() > 0.01:
		rotation = velocity.angle()
		
	# Sweep and damage targets in path
	_sweep_damage()
	
	# Sync position to 3D visual
	super._physics_process(delta)

func _sweep_damage() -> void:
	var groups_to_scan = ["garbage", "asteroid", "enemy"]
	for grp in groups_to_scan:
		var targets = get_tree().get_nodes_in_group(grp)
		for target in targets:
			if not target.active:
				continue
			if hit_targets.has(target):
				continue
				
			var target_dist = global_position.distance_to(target.global_position)
			# Query target's physical shape bounds if available
			var target_radius = 0.0
			var col_shape = target.get_node_or_null("CollisionShape2D")
			if col_shape and col_shape.shape is CircleShape2D:
				target_radius = col_shape.shape.radius * target.scale.x

			if target_dist <= (hit_radius + target_radius):
				# Deal damage to target (as player-sourced damage)
				if target.has_method("take_player_damage"):
					target.take_player_damage(damage)
				else:
					target.take_damage(damage)
					
				hit_targets[target] = true
				
				# Trigger hit flash on visual if applicable
				if visual_3d and visual_3d.has_method("play_hit_vfx"):
					visual_3d.call("play_hit_vfx", target.global_position)
				
				# Recycles on first hit
				_recycle()
				return

func _recycle() -> void:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.object_pooler:
		game_mgr.object_pooler.return_to_pool("satellite_projectile", self)
	else:
		queue_free()
