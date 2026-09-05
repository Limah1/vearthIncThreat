# res://src/entities/asteroid_instance.gd
extends Node3D
class_name AsteroidInstance

const AvoidanceMathUtil = preload("res://src/core/avoidance_math.gd")
const DamageSystemScript = preload("res://src/core/damage_system.gd")

@export var base_speed: float = 85.0 # --- VELOCIDADE DE MOVIMENTO (MAIS ALTO = MAIS RAPIDO)
@export var base_value: float = 1.0 # --- CRÉDITOS CONCEDIDOS NA DESTRUIÇÃO
@export var base_planet_damage: float = 1.0 # --- DANO AO ATINGIR O PLANETA
@export_range(1, 5, 1) var minimum_spawn_hp: int = 1
@export_range(1, 5, 1) var maximum_spawn_hp: int = 1

@export_group("Ally Avoidance")
@export var avoidance_enabled: bool = true
@export_range(25.0, 500.0, 1.0) var avoidance_lookahead: float = 150.0
@export_range(0.0, 100.0, 1.0) var avoidance_clearance: float = 8.0
@export_range(0.1, 20.0, 0.1) var avoidance_turn_speed: float = 6.5
@export_range(0.0, 50.0, 1.0) var avoidance_release_margin: float = 4.0
@export_range(0.02, 1.0, 0.01) var avoidance_query_interval: float = 0.1

var current_move_speed: float = 85.0
var current_value: float = 1.0
var planet_damage: float = 1.0

var killed_by_player: bool = false
var slowdown_timer: float = 0.0

var max_hp: float = 1.0
var hp: float = 1.0
var active: bool = false
var pool_type: String = "enemy"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO
var asteroid_type: String = "small"
var radius: float = 24.0 # default radius for SMALL collision checks

var fbx_small: Node3D = null
var fbx_medium: Node3D = null
var fbx_large: Node3D = null
var _debris_master_ref: Node = null
var _avoidance_obstacle: Node = null
var _avoidance_side: float = 0.0
var _avoidance_query_timer: float = 0.0
var _barrier_contact: Node = null

func _ready() -> void:
	add_to_group("enemy")

	# The pooled scene already contains the small asteroid mesh. Reuse it and
	# lazily create medium/large visuals only if a level actually needs them.
	# Creating three FBX trees for every pooled asteroid made a 500-object level
	# unnecessarily slow and could look like spawning had stalled.
	fbx_small = get_node_or_null("meteoro_small") as Node3D
	if fbx_small:
		fbx_small.visible = false

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	movement_direction = dir_3d.normalized()
	killed_by_player = false
	slowdown_timer = 0.0
	_avoidance_obstacle = null
	_avoidance_side = 0.0
	# Stagger pooled actors so thousands of obstacle queries do not land on one frame.
	_avoidance_query_timer = (
		float(get_instance_id() % 17) / 17.0
	) * avoidance_query_interval
	_barrier_contact = null
	active = true
	visible = true
	GameManager.register_movement(self)
	GameManager.register_active_damageable(self)
	
	# Reset rotations of cached visual meshes
	if fbx_small:
		fbx_small.rotation = Vector3.ZERO
	if fbx_medium:
		fbx_medium.rotation = Vector3.ZERO
	if fbx_large:
		fbx_large.rotation = Vector3.ZERO

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_movement(self)
	GameManager.unregister_active_damageable(self)
	_avoidance_obstacle = null
	_avoidance_side = 0.0
	_avoidance_query_timer = 0.0
	_barrier_contact = null

func set_asteroid_type(type: String) -> void:
	asteroid_type = type
	_ensure_visual_for_type(type)
	var zone_scale = 1.0 + (GameManager.current_zone - 1) * 0.1
	var health_minimum: int = mini(minimum_spawn_hp, maximum_spawn_hp)
	var health_maximum: int = maxi(minimum_spawn_hp, maximum_spawn_hp)
	max_hp = float(randi_range(health_minimum, health_maximum))
	
	match type:
		"small":
			current_value = base_value
			planet_damage = base_planet_damage
			radius = 24.0
		"medium":
			current_value = base_value
			planet_damage = (base_planet_damage * 2.5) * zone_scale
			radius = 45.0
		"large":
			current_value = base_value
			planet_damage = (base_planet_damage * 6.0) * zone_scale
			radius = 70.0
			
	hp = max_hp
	current_move_speed = base_speed * (1.0 + (GameManager.current_zone - 1) * 0.05)
	
	# Toggle visibility instead of queue_free & load/instantiate at runtime
	if fbx_small:
		fbx_small.visible = (type == "small")
	if fbx_medium:
		fbx_medium.visible = (type == "medium")
	if fbx_large:
		fbx_large.visible = (type == "large")

func _ensure_visual_for_type(type: String) -> void:
	if type == "small":
		return
	if type == "medium" and not fbx_medium:
		var scene_medium := load("res://src/assets/3d/meteoro_medium.FBX") as PackedScene
		if scene_medium:
			fbx_medium = scene_medium.instantiate() as Node3D
			fbx_medium.scale = Vector3(140.0, 140.0, 140.0)
			fbx_medium.visible = false
			add_child(fbx_medium)
			_disable_shadows_recursive(fbx_medium)
	elif type == "large" and not fbx_large:
		var scene_large := load("res://src/assets/3d/meteoro_big.FBX") as PackedScene
		if scene_large:
			fbx_large = scene_large.instantiate() as Node3D
			fbx_large.scale = Vector3(220.0, 220.0, 220.0)
			fbx_large.visible = false
			add_child(fbx_large)
			_disable_shadows_recursive(fbx_large)

func _disable_shadows_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows_recursive(child)

func receive_damage(amount: float, source_team: int) -> bool:
	if source_team != DamageSystemScript.Team.ALLY:
		return false
	killed_by_player = true
	_apply_damage(amount)
	return true

func take_damage(amount: float) -> void:
	# Untyped damage is neutral and cannot destroy an enemy asteroid.
	receive_damage(amount, DamageSystemScript.Team.NEUTRAL)

func _apply_damage(amount: float) -> void:
	if not active:
		return
	slowdown_timer = 0.4
	hp -= amount
	
	var damage_text = str(int(round(amount)))
	GameManager.spawn_popup_3d(damage_text, Color(1.0, 1.0, 1.0), global_position)
	
	if hp <= 0.0:
		die()

func take_player_damage(amount: float) -> void:
	# Compatibility entry point: player damage belongs to the ALLY team.
	receive_damage(amount, DamageSystemScript.Team.ALLY)

func _manager_move(delta: float) -> void:
	if not is_inside_tree() or not active:
		return

	_update_avoidance(delta)

	var speed: float = current_move_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = current_move_speed * 0.8

	# Move node
	global_position += movement_direction * speed * delta

	# Small directional enemies always face the planet. Other asteroids tumble.
	var active_mesh: Node3D = null
	match asteroid_type:
		"small": active_mesh = fbx_small
		"medium": active_mesh = fbx_medium
		"large": active_mesh = fbx_large

	if active_mesh and is_instance_valid(active_mesh):
		if asteroid_type == "small":
			var facing := -global_position
			facing.y = 0.0
			if facing.length_squared() > 0.000001:
				active_mesh.rotation.y = atan2(facing.x, facing.z)
		else:
			active_mesh.rotate_x(0.6 * delta)
			active_mesh.rotate_z(0.3 * delta)

	var collided_barrier: Node = GameManager.get_barrier_collision(global_position, radius)
	if is_instance_valid(collided_barrier):
		if collided_barrier != _barrier_contact:
			DamageSystemScript.apply(
				collided_barrier,
				planet_damage,
				DamageSystemScript.Team.ENEMY
			)
		_barrier_contact = collided_barrier
		_recover_avoidance_from_collision(collided_barrier)
	else:
		_barrier_contact = null

	# Check for planet collision (planet is at center 0,0,0, radius ~ 45)
	if global_position.length() < 45.0:
		var planet = GameManager.get_player_planet()
		if planet:
			DamageSystemScript.apply(planet, planet_damage, DamageSystemScript.Team.ENEMY)
		_recycle_after_planet_impact()
		return

func _update_avoidance(delta: float) -> void:
	if not avoidance_enabled:
		return
	_avoidance_query_timer -= delta

	var target_position := Vector3.ZERO
	var position_2d := Vector2(global_position.x, global_position.z)
	var target_2d := Vector2(target_position.x, target_position.z)

	if is_instance_valid(_avoidance_obstacle):
		if not GameManager.is_avoidance_obstacle_active(_avoidance_obstacle):
			_avoidance_obstacle = null
			_avoidance_side = 0.0
			_avoidance_query_timer = 0.0

	if is_instance_valid(_avoidance_obstacle):
		var center: Vector2 = GameManager.get_avoidance_obstacle_center(_avoidance_obstacle)
		var safe_radius: float = GameManager.get_avoidance_safe_radius(
			_avoidance_obstacle,
			radius,
			avoidance_clearance
		)
		var has_cleared_obstacle: bool = GameManager.is_avoidance_path_clear(
			global_position,
			target_position,
			_avoidance_obstacle,
			radius,
			avoidance_clearance
		) and position_2d.distance_to(center) > safe_radius + avoidance_release_margin
		if has_cleared_obstacle:
			_avoidance_obstacle = null
			_avoidance_side = 0.0
			_avoidance_query_timer = 0.0

	if not is_instance_valid(_avoidance_obstacle) and _avoidance_query_timer <= 0.0:
		_avoidance_query_timer = avoidance_query_interval
		_avoidance_obstacle = GameManager.find_avoidance_obstacle(
			global_position,
			movement_direction,
			radius,
			avoidance_lookahead,
			avoidance_clearance
		)
		if is_instance_valid(_avoidance_obstacle):
			_avoidance_side = AvoidanceMathUtil.choose_side(
				position_2d,
				target_2d,
				GameManager.get_avoidance_obstacle_center(_avoidance_obstacle),
				get_instance_id()
			)

	var desired_direction_2d: Vector2 = (target_2d - position_2d).normalized()
	if is_instance_valid(_avoidance_obstacle):
		desired_direction_2d = AvoidanceMathUtil.circle_avoidance_direction(
			position_2d,
			target_2d,
			GameManager.get_avoidance_obstacle_center(_avoidance_obstacle),
			GameManager.get_avoidance_safe_radius(_avoidance_obstacle, radius, avoidance_clearance),
			_avoidance_side
		)
	if desired_direction_2d.is_zero_approx():
		return

	var desired_direction := Vector3(desired_direction_2d.x, 0.0, desired_direction_2d.y)
	var turn_weight: float = clampf(avoidance_turn_speed * delta, 0.0, 1.0)
	movement_direction = movement_direction.lerp(desired_direction, turn_weight).normalized()

func _recover_avoidance_from_collision(obstacle: Node) -> void:
	if not is_instance_valid(obstacle):
		return
	var obstacle_changed: bool = obstacle != _avoidance_obstacle
	_avoidance_obstacle = obstacle
	_avoidance_query_timer = avoidance_query_interval
	var position_2d := Vector2(global_position.x, global_position.z)
	var center: Vector2 = GameManager.get_avoidance_obstacle_center(obstacle)
	if obstacle_changed or is_zero_approx(_avoidance_side):
		_avoidance_side = AvoidanceMathUtil.choose_side(
			position_2d,
			Vector2.ZERO,
			center,
			get_instance_id()
		)
	var recovery_direction: Vector2 = AvoidanceMathUtil.circle_avoidance_direction(
		position_2d,
		Vector2.ZERO,
		center,
		GameManager.get_avoidance_safe_radius(obstacle, radius, avoidance_clearance),
		_avoidance_side
	)
	if not recovery_direction.is_zero_approx():
		var recovery_3d := Vector3(recovery_direction.x, 0.0, recovery_direction.y)
		movement_direction = movement_direction.lerp(recovery_3d, 0.5).normalized()

func _recycle_after_planet_impact() -> void:
	# Reaching the planet is not an ALLY kill: no credits, debris, or eliminated
	# threat count.
	active = false
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()

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
			GameManager.debris_chance = 0.2 + UpgradeManager.get_total_bonus("DebrisChance")

func _spawn_debris_burst() -> void:
	if not is_instance_valid(_debris_master_ref):
		_debris_master_ref = get_tree().get_first_node_in_group("debris_master")
	var debris_master = _debris_master_ref
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
