# res://src/entities/enemy_spaceship.gd
extends Entity2D
class_name EnemySpaceship

@export var base_hp: float = 12.0
@export var base_value: float = 20.0
@export var fly_in_speed: float = 120.0
@export var orbit_speed: float = 0.5 # Radians per second
@export var fire_interval: float = 2.5

var current_value: float = 20.0
var orbit_radius: float = 200.0
var current_angle: float = 0.0
var is_orbiting: bool = false
var fire_timer: float = 0.0
var killed_by_player: bool = false

func _init() -> void:
	pool_type = "enemy"

func _ready() -> void:
	add_to_group("enemy")

func on_pool_activate(spawn_pos_2d: Vector2, initial_velocity: Vector2) -> void:
	# Difficulty scaling
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.12
	max_hp = base_hp * zone_scale
	hp = max_hp
	
	super.on_pool_activate(spawn_pos_2d, initial_velocity)
	
	current_value = base_value * zone_scale
	killed_by_player = false
	is_orbiting = false
	current_angle = spawn_pos_2d.angle()
	
	# Randomized orbit target radius to prevent all enemies stacking in one line
	orbit_radius = randf_range(160.0, 240.0)
	
	# Orbit direction (clockwise or counter-clockwise)
	if randf() > 0.5:
		orbit_speed = abs(orbit_speed)
	else:
		orbit_speed = -abs(orbit_speed)
		
	# Randomize fire timer offset
	fire_timer = randf() * fire_interval

func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	var to_center = Vector2.ZERO - global_position
	var dist = to_center.length()
	
	if not is_orbiting:
		# Fly inwards to reach orbit radius
		if dist <= orbit_radius:
			is_orbiting = true
			current_angle = global_position.angle()
		else:
			velocity = to_center.normalized() * fly_in_speed
			rotation = to_center.angle() + PI # Face center
			move_and_slide()
	else:
		# Circle orbit
		current_angle += orbit_speed * delta
		var target_pos = Vector2.from_angle(current_angle) * orbit_radius
		global_position = target_pos
		rotation = current_angle + PI # Keep facing planet
		
		# Shoot loop
		fire_timer += delta
		if fire_timer >= fire_interval:
			fire_timer = 0.0
			_shoot_projectile()
			
	# Sync position/rotation to 3D visual
	super._physics_process(delta)

func _shoot_projectile() -> void:
	if not GameManager.object_pooler:
		return
	var pooler = GameManager.object_pooler
		
	var shoot_dir = (Vector2.ZERO - global_position).normalized()
	# Spawn enemy projectile pointing at center
	pooler.borrow_from_pool("enemy_projectile", global_position, shoot_dir)

func _on_death() -> void:
	if killed_by_player:
		# Award credits delayed by 0.2s
		var spawn_pos = visual_3d.global_position if visual_3d else Vector3(global_position.x, 0.0, global_position.y)
		GameManager.add_credits_delayed(current_value, spawn_pos)
		# Register threat eliminated
		GameManager.register_eliminated_threat()
		# Explosion VFX
		if visual_3d and visual_3d.has_method("play_explosion"):
			visual_3d.call("play_explosion")
