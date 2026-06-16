# res://src/entities/player_planet.gd
extends Area2D
class_name PlayerPlanet

@export var visual_3d_scene: PackedScene
var visual_3d: Node3D

@export var satellite_scene: PackedScene
var satellites: Array[Satellite] = []

@export var base_hp: float = 100.0
@export var base_shield: float = 50.0
@export var decay_rate: float = 0.0

var max_hp: float = 100.0
var hp: float = 100.0

var max_shield: float = 50.0
var shield: float = 50.0

func _ready() -> void:
	global_position = Vector2.ZERO
	
	# Connect to upgrade events to update stats dynamically
	get_node("/root/UpgradeManager").upgrade_purchased.connect(_on_upgrade_purchased)
	
	# Instantiate visual 3D node if not already done
	if visual_3d_scene and not visual_3d:
		visual_3d = visual_3d_scene.instantiate() as Node3D
		# Add to the 3D world (Main.gd will place it in the correct parent)
		call_deferred("_add_visual_to_3d_world")
		
	recalculate_stats(true)
	_update_satellites()

func _add_visual_to_3d_world() -> void:
	var world_3d = get_tree().current_scene.find_child("World3D", true, false)
	if world_3d:
		world_3d.add_child(visual_3d)
		visual_3d.global_position = Vector3.ZERO
		_sync_shield_visual()

func recalculate_stats(reset_current: bool = false) -> void:
	var prev_max_hp = max_hp
	var _prev_max_shield = max_shield
	
	var upgrade_mgr = get_node("/root/UpgradeManager")
	max_hp = base_hp + upgrade_mgr.get_total_bonus("PlanetHealth")
	max_shield = 0.0 # Disabled for now
	shield = 0.0
	
	if reset_current:
		hp = max_hp
		shield = max_shield
	else:
		# Scale proportionally to avoid sudden death/damage issues on upgrade
		if prev_max_hp > 0:
			hp = clamp(hp * (max_hp / prev_max_hp), 1.0, max_hp)
		else:
			hp = max_hp
			
		shield = 0.0
			
	_sync_shield_visual()

func take_damage(amount: float) -> void:
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.current_state != game_mgr.GameState.PLAYING:
		return
		
	if shield > 0.0:
		if amount <= shield:
			shield -= amount
			amount = 0.0
		else:
			amount -= shield
			shield = 0.0
	
	if amount > 0.0:
		hp = max(0.0, hp - amount)
		
	_sync_shield_visual()
	
	if hp <= 0.0:
		game_mgr.planet_destroyed()

func repair_shield(amount: float) -> void:
	shield = min(max_shield, shield + amount)
	_sync_shield_visual()

func _sync_shield_visual() -> void:
	if visual_3d:
		var shield_mesh = visual_3d.find_child("ShieldMesh", true, false)
		if shield_mesh:
			shield_mesh.visible = shield > 0.0
			# Optionally scale shield based on current vs max shield
			if shield > 0.0:
				var scale_ratio = 1.0 + 0.1 * (shield / max_shield)
				shield_mesh.scale = Vector3(scale_ratio, scale_ratio, scale_ratio)

func _physics_process(_delta: float) -> void:
	if not is_inside_tree():
		return
		
	if visual_3d and visual_3d.is_inside_tree():
		# Keep 3D visual locked at center
		visual_3d.global_position = Vector3.ZERO
		# Slow rotation for visual aesthetic
		visual_3d.rotate_y(0.005)
		
	# Planet health decay disabled

func _on_upgrade_purchased(upgrade_id: String, _new_level: int) -> void:
	var upgrade = get_node("/root/UpgradeManager").upgrades_by_id.get(upgrade_id)
	if upgrade:
		if upgrade.category == "PlanetHealth" or upgrade.category == "ShieldHP":
			recalculate_stats(false)
		elif upgrade.category == "SatelliteAmount":
			_update_satellites()

func _update_satellites() -> void:
	# 1. Clean up old satellites
	for sat in satellites:
		if is_instance_valid(sat):
			sat.queue_free()
	satellites.clear()
	
	# 2. Get current upgrade level/bonus
	var upgrade_mgr = get_node_or_null("/root/UpgradeManager")
	if not upgrade_mgr:
		return
		
	var count = int(upgrade_mgr.get_total_bonus("SatelliteAmount"))
	if count <= 0 or not satellite_scene:
		return
		
	# 3. Priority angles (Symmetric opposite pairs):
	# Level 1 (2 satellites): East (0), West (PI)
	# Level 2 (4 satellites): Add South (PI/2), North (-PI/2)
	# Level 3 (6 satellites): Add South-East (PI/4), North-West (-3*PI/4)
	# Level 4 (8 satellites): Add South-West (3*PI/4), North-East (-PI/4)
	var angles = [
		0.0, PI,               # Pair 1 (East, West)
		PI/2, -PI/2,           # Pair 2 (South, North)
		PI/4, -3.0*PI/4,       # Pair 3 (SE, NW)
		3.0*PI/4, -PI/4        # Pair 4 (SW, NE)
	]
	
	# Clamp to maximum supported spots (8)
	var spawn_count = min(count, angles.size())
	
	# 4. Instantiate new ones
	var parent_node = get_parent()
	if parent_node:
		for i in range(spawn_count):
			var sat = satellite_scene.instantiate() as Satellite
			sat.angle = angles[i]
			parent_node.add_child(sat)
			satellites.append(sat)
