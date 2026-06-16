# res://src/entities/debris_projectile.gd
extends Entity2D
class_name DebrisProjectile

@export var base_speed: float = 240.0
@export var base_damage: float = 3.0
@export var base_lifetime: float = 6.0
@export var hit_radius: float = 20.0

var damage: float = 3.0

var max_pierce: int = 0
var current_pierce: int = 0

# Keep track of hit targets to prevent multi-hits in rapid succession
var hit_targets: Dictionary = {}
var arena_radius: float = 400.0

func _init() -> void:
	pool_type = "debris"

func _ready() -> void:
	add_to_group("debris")

func on_pool_activate(spawn_pos_2d: Vector2, direction: Vector2) -> void:
	super.on_pool_activate(spawn_pos_2d, direction * base_speed)
	
	current_pierce = 0
	hit_targets.clear()
	
	# Fetch upgrades to calculate final stats
	var damage_mult = UpgradeManager.get_multiplier("DebrisDamage")
	damage = base_damage * damage_mult
	
	# No lifetime limit, screen bounds used instead
	
	max_pierce = int(UpgradeManager.get_total_bonus("DebrisPiercing"))

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Move using standard linear velocity
	var _collision = move_and_collide(velocity * delta)
	
	# Check if completely out of screen bounds
	var camera = get_viewport().get_camera_3d()
	if camera:
		var half_height = camera.size * 0.5
		var aspect = 16.0 / 9.0
		var vp_size = get_viewport().size
		if vp_size.y > 0:
			aspect = float(vp_size.x) / float(vp_size.y)
		var half_width = half_height * aspect
		
		var cam_center = Vector2(camera.global_position.x, camera.global_position.z)
		var diff = global_position - cam_center
		var margin = 60.0 # Ensure completely off-screen
		if abs(diff.x) > half_width + margin or abs(diff.y) > half_height + margin:
			_recycle()
			return
		
	# Sync rotation to movement direction
	if velocity.length_squared() > 0.01:
		rotation = velocity.angle()
		
	# Sweep and damage resources & enemies in path
	_sweep_damage()
	
	# Sync positions to 3D visual
	super._physics_process(delta)

func _sweep_damage() -> void:
	# Scan groups: garbage, asteroid, enemy
	var groups_to_scan = ["garbage", "asteroid", "enemy"]
	for grp in groups_to_scan:
		var targets = get_tree().get_nodes_in_group(grp)
		for target in targets:
			if not target.active:
				continue
			if hit_targets.has(target):
				continue
				
			var target_dist = global_position.distance_to(target.global_position)
			if target_dist <= hit_radius:
				# Deal damage to target (as player-sourced damage)
				if target.has_method("take_player_damage"):
					target.take_player_damage(damage)
				else:
					target.take_damage(damage)
					
				hit_targets[target] = true
				
				# Trigger hit flash on visual if applicable
				if visual_3d and visual_3d.has_method("play_hit_vfx"):
					visual_3d.call("play_hit_vfx", target.global_position)
					
				# Pierce check
				if current_pierce < max_pierce:
					current_pierce += 1
				else:
					_recycle()
					return

func _recycle() -> void:
	if GameManager.object_pooler:
		GameManager.object_pooler.return_to_pool("debris", self)
	else:
		queue_free()
