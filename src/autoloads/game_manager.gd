# res://src/autoloads/game_manager.gd
extends Node

signal state_changed(new_state: GameState)
signal credits_changed(run_credits: float, lifetime_credits: float)
signal timer_updated(time_left: float)
signal trigger_camera_animation()

enum GameState { PLAYING, PAUSED, UPGRADE_SCREEN, DEFEAT, VICTORY, TRANSITION }

var current_state: GameState = GameState.PLAYING

var object_pooler: Node = null


var run_credits: float = 0.0
var lifetime_credits: float = 0.0

var decay_time_limit: float = 60.0
var decay_timer: float = 60.0

var current_zone: int = 1

var eliminated_threats: int = 0
var debris_chance: float = 0.20

# Camera transition trigger from purchases
var b_can_animate_camera: bool = false
const CAMERA_ANIM_TRIGGER_CATEGORIES = ["GarbageAmount", "AutoClickRate"] # Equivalent categories triggering zoom

const SAVE_PATH = "user://save_game.json"
var is_fully_loaded: bool = false

func _ready() -> void:
	# Listen to upgrade purchases to trigger camera fly transitions
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	reset_game()
	if not OS.is_debug_build():
		load_game()
	is_fully_loaded = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			lifetime_credits += 9000.0
			credits_changed.emit(run_credits, lifetime_credits)

func reset_game() -> void:
	run_credits = 0.0
	current_zone = 1
	decay_timer = decay_time_limit
	b_can_animate_camera = false
	eliminated_threats = 0
	change_state(GameState.PLAYING, false)
	save_game()

func change_state(new_state: GameState, should_emit: bool = true) -> void:
	current_state = new_state
	if should_emit:
		state_changed.emit(new_state)
	
	if new_state == GameState.PAUSED or new_state == GameState.DEFEAT:
		if object_pooler and object_pooler.has_method("return_all_active_to_pool"):
			object_pooler.return_all_active_to_pool()


# Add credits scaled by ResourceMultiplier upgrade
func add_credits(amount: float) -> void:
	var multiplier = UpgradeManager.get_multiplier("ResourceMultiplier")
	var scaled_amount = round(amount * multiplier)
	run_credits += scaled_amount
	credits_changed.emit(run_credits, lifetime_credits)

# Spends lifetime bank credits for purchases
func spend_lifetime_credits(amount: float) -> bool:
	if lifetime_credits >= amount:
		lifetime_credits -= amount
		credits_changed.emit(run_credits, lifetime_credits)
		return true
	return false

# Finish round, bank run credits into lifetime bank, open summary menu
func end_round() -> void:
	lifetime_credits += run_credits
	change_state(GameState.PAUSED)
	credits_changed.emit(run_credits, lifetime_credits)
	save_game()

# Launch next wave, increment difficulty and reload scene to trigger spawners
func start_next_round() -> void:
	current_zone += 1
	run_credits = 0.0
	credits_changed.emit(run_credits, lifetime_credits)
	change_state(GameState.PLAYING, false)
	get_tree().reload_current_scene()

func planet_destroyed() -> void:
	lifetime_credits += run_credits
	change_state(GameState.DEFEAT)
	credits_changed.emit(run_credits, lifetime_credits)
	save_game()

func _on_upgrade_purchased(upgrade_id: String, _new_level: int) -> void:
	var upgrade = UpgradeManager.upgrades_by_id.get(upgrade_id)
	if upgrade and upgrade.category in CAMERA_ANIM_TRIGGER_CATEGORIES:
		b_can_animate_camera = true
	if upgrade_id == "UnlockDebrie":
		debris_chance = 0.80
	save_game()

func save_game() -> void:
	if not is_fully_loaded or OS.is_debug_build():
		return
		
	var master_vol = 0.8
	var master_bus_idx = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		master_vol = db_to_linear(AudioServer.get_bus_volume_db(master_bus_idx))
		
	var is_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	
	var save_data = {
		"lifetime_credits": lifetime_credits,
		"current_zone": current_zone,
		"purchased_levels": UpgradeManager.purchased_levels,
		"master_volume": master_vol,
		"fullscreen": is_fullscreen
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data)
		file.store_string(json_string)
		file.close()
		print("[GameManager] Game auto-saved successfully.")
	else:
		print("[GameManager] Failed to write save file.")

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[GameManager] No save game found.")
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_err = json.parse(json_string)
		if parse_err == OK:
			var save_data = json.get_data()
			if save_data is Dictionary:
				lifetime_credits = save_data.get("lifetime_credits", 0.0)
				current_zone = save_data.get("current_zone", 1)
				
				var saved_levels = save_data.get("purchased_levels", {})
				if saved_levels is Dictionary:
					for upgrade_id in saved_levels.keys():
						UpgradeManager.purchased_levels[upgrade_id] = int(saved_levels[upgrade_id])
						
				# Update specific upgrade side-effects in GameManager
				if UpgradeManager.get_upgrade_level("UnlockDebrie") > 0:
					debris_chance = 0.80
					
				# Apply options settings
				var master_vol = save_data.get("master_volume", 0.8)
				var master_bus_idx = AudioServer.get_bus_index("Master")
				if master_bus_idx != -1:
					if master_vol <= 0.0001:
						AudioServer.set_bus_volume_db(master_bus_idx, -80.0)
					else:
						AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_vol))
				
				var is_fullscreen = save_data.get("fullscreen", false)
				if is_fullscreen:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					
				credits_changed.emit(run_credits, lifetime_credits)
				print("[GameManager] Game loaded successfully.")
			else:
				print("[GameManager] Save data format invalid.")
		else:
			print("[GameManager] Parse error loading save game: ", parse_err)

func register_eliminated_threat() -> void:
	eliminated_threats += 1

func get_active_actors() -> Array[Node]:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group("damageable")

func spawn_popup_3d(text: String, color: Color, global_pos: Vector3) -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
		
	var label = Label3D.new()
	label.text = text
	label.modulate = color
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 1.0
	
	current_scene.add_child(label)
	
	# Offset slightly on Y to float above gameplay plane, and randomize horizontal spread
	var offset = Vector3(randf_range(-15.0, 15.0), 3.0, randf_range(-15.0, 15.0))
	label.global_position = global_pos + offset
	
	var tween = label.create_tween()
	tween.set_parallel(true)
	# Rise up along the screen-up axis (-Z in 3D)
	tween.tween_property(label, "global_position:z", label.global_position.z - 35.0, 0.7)
	# Fade out modulate.a
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)

func add_credits_delayed(amount: float, global_pos: Vector3) -> void:
	# Avoid executing when leaving the tree or during transitions
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.2).timeout
	if not is_inside_tree():
		return
		
	# Calculate scaled amount for the green popup
	var multiplier = get_node("/root/UpgradeManager").get_multiplier("ResourceMultiplier")
	var scaled_amount = round(amount * multiplier)
	
	add_credits(amount)
	spawn_popup_3d("+$" + str(int(scaled_amount)), Color(0.0, 1.0, 0.0), global_pos)
