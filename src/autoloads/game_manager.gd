# res://src/autoloads/game_manager.gd
extends Node

signal state_changed(new_state: GameState)
signal credits_changed(run_credits: float, lifetime_credits: float)
signal timer_updated(time_left: float)
signal trigger_camera_animation()

enum GameState { PLAYING, PAUSED, UPGRADE_SCREEN, END_SESSION, VICTORY, TRANSITION }

var current_state: GameState = GameState.PLAYING

var object_pooler: Node = null

var spatial_grid: Dictionary = {}
var cell_size: float = 80.0


var run_credits: float = 0.0
var lifetime_credits: float = 0.0

var decay_time_limit: float = 60.0
var decay_timer: float = 60.0

var current_zone: int = 1

var eliminated_threats: int = 0
var debris_chance: float = 1.0

# Camera transition trigger from purchases
var b_can_animate_camera: bool = false
var has_camera_animated_once: bool = false

const SAVE_PATH = "user://save_game.json"
var is_fully_loaded: bool = false

var _popup_pool: Array[Label3D] = []
var _popup_size: int = 80

# Array rastreado de entidades ativas dañables — evita get_nodes_in_group todo frame
var _active_damageable: Array = []

# Buffer reutilizável para get_nearby_entities — evita alocação por chamada
var _nearby_buffer: Array = []

func _ready() -> void:
	# Listen to upgrade purchases to trigger camera fly transitions
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	reset_game()
	if not OS.is_debug_build():
		load_game()
	_init_popup_pool()
	is_fully_loaded = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			lifetime_credits += 9000.0
			credits_changed.emit(run_credits, lifetime_credits)
		elif event.keycode == KEY_O:
			if current_state == GameState.PLAYING:
				planet_destroyed()

func reset_game() -> void:
	run_credits = 0.0
	current_zone = 1
	decay_timer = decay_time_limit
	b_can_animate_camera = false
	has_camera_animated_once = false
	eliminated_threats = 0
	change_state(GameState.PLAYING, false)
	save_game()

func change_state(new_state: GameState, should_emit: bool = true) -> void:
	current_state = new_state
	if should_emit:
		state_changed.emit(new_state)
	
	if new_state == GameState.PAUSED or new_state == GameState.END_SESSION:
		for grp in ["garbage_master", "debris_master", "asteroid_master", "enemy_master", "enemy_proj_master", "sat_proj_master", "satellite_master"]:
			var master_nodes = get_tree().get_nodes_in_group(grp)
			for master in master_nodes:
				if master.has_method("return_all_active_to_pool"):
					master.return_all_active_to_pool()


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
	# Change state to TRANSITION to stop spawning and cursor sweep immediately
	change_state(GameState.TRANSITION, false)
	
	# Stop all active actors
	var actors = get_active_actors()
	for actor in actors:
		if actor.has_method("stop_movement"):
			actor.stop_movement()
			
	# Animate scale down planet and its dependents (satellites)
	var anim_duration = 0.5
	var planet = get_tree().current_scene.find_child("PlayerPlanet", true, false)
	if planet and planet.has_method("animate_scale_down"):
		planet.animate_scale_down(anim_duration)
		
	var satellites = get_tree().get_nodes_in_group("satellites")
	for sat in satellites:
		if sat.has_method("animate_scale_down"):
			sat.animate_scale_down(anim_duration)
			
	# Wait for animation to finish (0.5 seconds)
	await get_tree().create_timer(anim_duration).timeout
	
	# Return all active actors to pool
	for grp in ["garbage_master", "debris_master", "asteroid_master", "enemy_master", "enemy_proj_master", "sat_proj_master", "satellite_master"]:
		var master_nodes = get_tree().get_nodes_in_group(grp)
		for master in master_nodes:
			if master.has_method("return_all_active_to_pool"):
				master.return_all_active_to_pool()
		
	if planet and "satellites" in planet:
		planet.satellites.clear()
		
	# Wait 0.5 seconds after cleaning up before showing UI
	await get_tree().create_timer(0.5).timeout
	
	lifetime_credits += run_credits
	change_state(GameState.END_SESSION)
	credits_changed.emit(run_credits, lifetime_credits)
	save_game()

func _on_upgrade_purchased(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "DA_UnlockAsteroids" and not has_camera_animated_once:
		b_can_animate_camera = true
		has_camera_animated_once = true
	if upgrade_id == "DA_UnlockDebrie_T0":
		debris_chance = 1.0
	save_game()

func save_game() -> void:
	return

func load_game() -> void:
	return

func register_eliminated_threat() -> void:
	eliminated_threats += 1

func get_active_actors() -> Array:
	return _active_damageable

## Registra entidade ativa no array rastreado (chamado no on_pool_activate / activate_at)
func register_active_damageable(entity: Node) -> void:
	if not _active_damageable.has(entity):
		_active_damageable.append(entity)

## Remove entidade do array rastreado (chamado no on_pool_deactivate / _recycle)
func unregister_active_damageable(entity: Node) -> void:
	_active_damageable.erase(entity)

func _init_popup_pool() -> void:
	for i in range(_popup_size):
		var label = Label3D.new()
		label.visible = false
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 1.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		_popup_pool.append(label)

func spawn_popup_3d(text: String, color: Color, global_pos: Vector3) -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
		
	var label: Label3D = null
	while not _popup_pool.is_empty():
		var candidate = _popup_pool.pop_back()
		if is_instance_valid(candidate):
			label = candidate
			break
			
	if not label:
		# Fallback dynamic creation if pool is exhausted
		label = Label3D.new()
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 1.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		
	label.text = text
	label.modulate = color
	label.modulate.a = 1.0 # Reset alpha
	label.visible = true
	
	# Offset slightly on Y to float above gameplay plane, and randomize horizontal spread
	var offset = Vector3(randf_range(-15.0, 15.0), 30.0, randf_range(-15.0, 15.0))
	label.global_position = global_pos + offset
	
	var tween = label.create_tween()
	tween.set_parallel(true)
	# Rise up along vertical Y axis
	tween.tween_property(label, "global_position:y", label.global_position.y + 25.0, 0.7)
	# Fade out modulate.a
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	
	tween.set_parallel(false)
	tween.tween_callback(func():
		label.visible = false
		_popup_pool.append(label)
	)

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

func register_to_grid(entity: Node) -> void:
	var pos = entity.global_position
	var px = pos.x
	var pz = pos.y if entity is Node2D else pos.z
	var cell = Vector2i(floor(px / cell_size), floor(pz / cell_size))
	if not spatial_grid.has(cell):
		spatial_grid[cell] = []
	spatial_grid[cell].append(entity)

func get_nearby_entities(pos_3d: Vector3) -> Array:
	var cell_x = floor(pos_3d.x / cell_size)
	var cell_z = floor(pos_3d.z / cell_size)
	# Reutiliza buffer pré-alocado — zero alocação por chamada
	_nearby_buffer.clear()
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell = Vector2i(cell_x + dx, cell_z + dz)
			if spatial_grid.has(cell):
				_nearby_buffer.append_array(spatial_grid[cell])
	return _nearby_buffer

func _physics_process(_delta: float) -> void:
	if current_state != GameState.PLAYING:
		return
	# Rebuild spatial grid apenas com entidades ativas rastreadas — O(ativas) não O(pool total)
	spatial_grid.clear()
	for target in _active_damageable:
		if is_instance_valid(target) and target.active:
			register_to_grid(target)
