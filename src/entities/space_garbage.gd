# res://src/entities/space_garbage.gd
extends Entity2D
class_name SpaceGarbage

@export var base_speed: float = 60.0
@export var base_value: float = 10.0
@export var base_planet_damage: float = 10.0
@export var base_debris_chance: float = 0.25
@export var base_hp: float = 6.0

var current_move_speed: float = 60.0
var current_value: float = 10.0
var planet_damage: float = 10.0

var slowdown_timer: float = 0.0
var killed_by_player: bool = false
var is_quality: bool = false

@export_group("Physics & Visual Behavior")
@export var separation_radius: float = 35.0
@export var separation_force: float = 120.0
@export var rotation_speed: float = -1.6

func _init() -> void:
	pool_type = "garbage"

func _ready() -> void:
	add_to_group("garbage")

func on_pool_activate(spawn_pos_2d: Vector2, initial_velocity: Vector2) -> void:
	super.on_pool_activate(spawn_pos_2d, initial_velocity)
	killed_by_player = false
	slowdown_timer = 0.0
	current_move_speed = base_speed
	scale = Vector2.ONE
	
	# Determine if this garbage is high quality
	is_quality = false
	var quality_lvl = UpgradeManager.get_upgrade_level("GarbageQuality")
	if quality_lvl > 0:
		is_quality = randf() < 0.20
		
	# Apply massify and quality multipliers
	var hp_mult = 1.0
	var value_mult = 1.0
	var scale_mult = 1.0
	
	var massify_lvl = UpgradeManager.get_upgrade_level("massify")
	if massify_lvl > 0:
		hp_mult *= 2.0
		value_mult *= 2.0
		planet_damage = base_planet_damage * 2.0
		scale_mult *= 1.6
	else:
		planet_damage = base_planet_damage
		
	if is_quality:
		hp_mult *= 2.0
		value_mult *= 2.0
		scale_mult *= 1.5
		
	max_hp = base_hp * hp_mult
	hp = max_hp
	current_value = base_value * value_mult
	
	# Apply size/scale increases to both 2D and 3D
	scale = Vector2(scale_mult, scale_mult)
	if visual_3d:
		visual_3d.scale = Vector3(scale_mult, scale_mult, scale_mult)
		
		# Reset rotation of the child mesh
		if visual_3d.get_child_count() > 0:
			visual_3d.get_child(0).rotation = Vector3.ZERO

func take_damage(amount: float) -> void:
	if not active:
		return
	# Trigger slowdown on hit: 20% reduction (speed * 0.8) for 0.4s
	slowdown_timer = 0.4
	hp -= amount
	
	if pool_type in ["garbage", "asteroid", "enemy"]:
		var damage_text = str(int(round(amount)))
		if is_quality:
			damage_text += " HQ"
		var popup_color = Color(1.0, 0.85, 0.0) if is_quality else Color(1.0, 1.0, 1.0)
		spawn_popup(damage_text, popup_color)
		
	if hp <= 0.0:
		die()

# Triggered when clicked or hit by player projectles/debris
func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	# Handle slowdown decay
	var speed = base_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = base_speed * 0.8
	current_move_speed = speed
	
	# Linear direction to planet at (0, 0)
	var dir = (Vector2.ZERO - global_position).normalized()
	var move_vel = dir * current_move_speed
	
	# Face towards the planet
	global_rotation = dir.angle()
	
	# Project separation force along the radial line (speed adjustment only) to prevent lateral curving
	var separation_offset = 0.0
	var neighbors = get_tree().get_nodes_in_group("garbage")
	for neighbor in neighbors:
		if neighbor == self or not neighbor.active:
			continue
		var dist = global_position.distance_to(neighbor.global_position)
		if dist < separation_radius and dist > 0.01:
			var push_dir = (global_position - neighbor.global_position).normalized()
			var proj = push_dir.dot(dir)
			separation_offset += proj * (separation_radius - dist)
			
	var speed_adjustment = separation_offset * separation_force
	speed_adjustment = clamp(speed_adjustment, -current_move_speed * 0.6, current_move_speed * 0.6)
	
	velocity = dir * (current_move_speed + speed_adjustment)
	
	# Move node
	global_position += velocity * delta
	
	# Sync position/rotation to 3D mesh
	super._physics_process(delta)
	
	# Spin/tumble the child mesh (e.g. dumpster) on its own local X axis as it travels
	if visual_3d and visual_3d.get_child_count() > 0:
		visual_3d.get_child(0).rotate_object_local(Vector3.RIGHT, rotation_speed * delta)
	
	# Check for planet collision (planet is at center 0,0, radius ~ 40)
	if global_position.length() < 45.0:
		# Hit planet!
		var planet = get_tree().current_scene.find_child("PlayerPlanet", true, false) as PlayerPlanet
		if planet:
			planet.take_damage(planet_damage)
		
		# Return to pool without death awards
		killed_by_player = false
		if GameManager.object_pooler:
			GameManager.object_pooler.return_to_pool("garbage", self)
		else:
			queue_free()

func _on_death() -> void:
	if killed_by_player:
		# Award credits delayed by 0.2s
		var spawn_pos = visual_3d.global_position if visual_3d else Vector3(global_position.x, 0.0, global_position.y)
		GameManager.add_credits_delayed(current_value, spawn_pos)
		
		# Register threat eliminated
		GameManager.register_eliminated_threat()
		
		# Roll debris chance
		var roll_chance = GameManager.debris_chance
		var roll_success = randf() < roll_chance
		
		# Check if UpgradeManager has a guaranteed debris flag
		if "b_next_debris_guaranteed" in UpgradeManager and UpgradeManager.get("b_next_debris_guaranteed") == true:
			roll_success = true
			UpgradeManager.set("b_next_debris_guaranteed", false)
			
		if roll_success:
			_spawn_debris_burst()
			GameManager.debris_chance = 0.20

func _spawn_debris_burst() -> void:
	if not GameManager.object_pooler:
		return
	var pooler = GameManager.object_pooler
	
	# Determine how many debris to spawn based on DebrisAmount upgrade level
	var extra_debris = int(UpgradeManager.get_total_bonus("DebrisAmount"))
	var count = clamp(2 + extra_debris, 1, 8)
	
	# Fixed 8 directions order: North, South, East, West, NE, SW, NW, SE
	var directions = [
		Vector2(0, -1),                  # North
		Vector2(0, 1),                   # South
		Vector2(1, 0),                   # East
		Vector2(-1, 0),                  # West
		Vector2(1, -1).normalized(),     # North-East
		Vector2(-1, 1).normalized(),     # South-West
		Vector2(-1, -1).normalized(),    # North-West
		Vector2(1, 1).normalized()       # South-East
	]
	
	for i in range(count):
		var dir = directions[i]
		pooler.borrow_from_pool("debris", global_position, dir)
