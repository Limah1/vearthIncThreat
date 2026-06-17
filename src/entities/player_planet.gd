# res://src/entities/player_planet.gd
extends Area2D
class_name PlayerPlanet

@export var visual_3d_scene: PackedScene
var visual_3d: Node3D

@export var satellite_scene: PackedScene
var satellites: Array[Node3D] = []

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
	
	# Startup scale animation (2D)
	scale = Vector2(0.2, 0.2)
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self , "scale", Vector2.ONE, 1.0)

func _add_visual_to_3d_world() -> void:
	var world_3d = get_tree().current_scene.find_child("World3D", true, false)
	if world_3d:
		world_3d.add_child(visual_3d)
		visual_3d.global_position = Vector3.ZERO
		_sync_shield_visual()
		
		# Startup scale animation (3D)
		visual_3d.scale = Vector3(0.2, 0.2, 0.2)
		var tween_3d = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween_3d.tween_property(visual_3d, "scale", Vector3.ONE, 1.0)

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
		
	# Planet health decay
	if decay_rate > 0.0:
		take_damage(decay_rate * _delta)
		
func animate_scale_down(duration: float) -> void:
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self , "scale", Vector2.ZERO, duration)
	if visual_3d:
		var tween_3d = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween_3d.tween_property(visual_3d, "scale", Vector3.ZERO, duration)

func _on_upgrade_purchased(upgrade_id: String, _new_level: int) -> void:
	var upgrade = get_node("/root/UpgradeManager").upgrades_by_id.get(upgrade_id)
	if upgrade:
		if upgrade.category == "PlanetHealth" or upgrade.category == "ShieldHP":
			recalculate_stats(false)
		elif upgrade.category == "SatelliteAmount" or upgrade.category == "SatelliteUnlock":
			_update_satellites()

func _update_satellites() -> void:
	# 1. Clean up old satellites
	var satellite_master = get_tree().get_first_node_in_group("satellite_master")
	if satellite_master:
		satellite_master.return_all_active_to_pool()
	else:
		for sat in satellites:
			if is_instance_valid(sat):
				sat.queue_free()
	satellites.clear()
	
	# 2. Get current upgrade level/bonus
	var upgrade_mgr = get_node_or_null("/root/UpgradeManager")
	if not upgrade_mgr:
		return
		
	# Check if SatelliteUnlock has been purchased
	var is_unlocked = upgrade_mgr.get_total_bonus("SatelliteUnlock") > 0.0
	print("[PlayerPlanet] --- UPDATE SATELLITES ---")
	print("[PlayerPlanet] Is unlocked (SatelliteUnlock > 0): ", is_unlocked)
	if not is_unlocked:
		return
		
	# Starts with 16 satellites upon unlock (test setup)
	var count = 16
	print("[PlayerPlanet] Count to spawn: ", count)
	if count <= 0:
		return
		
	# 3. Priority angles (Symmetric opposite pairs) supporting up to 16 satellites:
	var angles = [
		0.0, PI, # Pair 1 (East, West)
		PI / 2.0, -PI / 2.0, # Pair 2 (South, North)
		PI / 4.0, -3.0 * PI / 4.0, # Pair 3 (SE, NW)
		3.0 * PI / 4.0, -PI / 4.0, # Pair 4 (SW, NE)
		PI / 8.0, -7.0 * PI / 8.0, # Pair 5
		5.0 * PI / 8.0, -3.0 * PI / 8.0, # Pair 6
		3.0 * PI / 8.0, -5.0 * PI / 8.0, # Pair 7
		7.0 * PI / 8.0, -PI / 8.0 # Pair 8
	]
	
	# Clamp to maximum supported spots (16)
	var spawn_count = min(count, angles.size())
	
	# 4. Borrow from pool
	if satellite_master:
		for i in range(spawn_count):
			var sat = satellite_master.spawn_satellite(angles[i])
			if sat:
				satellites.append(sat)
