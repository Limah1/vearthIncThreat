# res://src/entities/satellite.gd
extends Node2D
class_name Satellite

@export var orbit_radius: float = 110.0 # Just outside the planet
@export var fire_interval: float = 2.0
@export var visual_3d_scene: PackedScene

var visual_3d: Node3D
var angle: float = 0.0 # Configured by player_planet.gd on instantiate
var fire_timer: float = 0.0

func _ready() -> void:
	add_to_group("satellites")
	
	# Instantiate 3D visual
	if visual_3d_scene and not visual_3d:
		visual_3d = visual_3d_scene.instantiate() as Node3D
		var world_3d = get_tree().current_scene.find_child("World3D", true, false)
		if world_3d:
			world_3d.add_child(visual_3d)
			
	# Update physical position
	_update_position()
	
	# Randomize fire timer slightly
	fire_timer = randf() * fire_interval

func _exit_tree() -> void:
	if visual_3d:
		visual_3d.queue_free()

func _physics_process(delta: float) -> void:
	# Position update
	_update_position()
	
	# Shoot loop
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.current_state == game_mgr.GameState.PLAYING:
		fire_timer += delta
		if fire_timer >= fire_interval:
			fire_timer = 0.0
			_shoot()

func _update_position() -> void:
	global_position = Vector2.from_angle(angle) * orbit_radius
	global_rotation = angle
	
	if visual_3d:
		visual_3d.global_position = Vector3(global_position.x, 0.0, global_position.y)
		visual_3d.global_rotation.y = -global_rotation

func _shoot() -> void:
	var game_mgr = get_node_or_null("/root/GameManager")
	if not game_mgr or not game_mgr.object_pooler:
		return
	var pooler = game_mgr.object_pooler
	
	# Shoot outward (direction away from planet center)
	var shoot_dir = Vector2.from_angle(angle)
	
	# Spawn projectile from our current position
	pooler.borrow_from_pool("satellite_projectile", global_position, shoot_dir)
