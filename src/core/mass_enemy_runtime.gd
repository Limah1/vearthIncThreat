extends Node
class_name MassEnemyRuntime

## Bridge between the data simulation and the current scene-based allies/UI.
var level_config: LevelConfig
var world: EnemyWorld
var combat: EnemyCombat
var renderer: EnemyMultiMeshRenderer
var spawner: MassEnemySpawner
var feedback: MassEnemyFeedback
var debris_bursts: int = 0
var rejected_debris_commands: int = 0
var _obstacle_nodes: Dictionary = {}
var _ending: bool = false


func _ready() -> void:
	process_physics_priority = -10
	world = EnemyWorld.new()
	world.name = "EnemyWorld"
	world.capacity = 10000
	world.use_legacy_rules = level_config != null and level_config.use_mass_legacy_rules
	world.zone = level_config.level_number if level_config != null else 1
	add_child(world)
	combat = EnemyGPUCombat.new() if level_config != null and level_config.use_gpu_enemy_simulation and RenderingServer.get_rendering_device() != null else EnemyCombat.new()
	combat.name = "EnemyCombat"
	combat.enemy_world = world
	add_child(combat)
	renderer = EnemyMultiMeshRenderer.new()
	renderer.enemy_world = world
	if combat is EnemyGPUCombat:
		renderer.gpu_combat = combat
	renderer.name = "EnemyRenderer"
	add_child(renderer)
	var projectiles := EnemyProjectileRenderer.new()
	projectiles.combat = combat
	add_child(projectiles)
	spawner = MassEnemySpawner.new()
	spawner.enemy_world = world
	spawner.name = "MassEnemySpawner"
	add_child(spawner)
	combat.combat_events.connect(_on_combat_events)
	combat.feedback_events.connect(_on_feedback_events)
	if level_config != null and level_config.use_mass_enemy_feedback:
		feedback = MassEnemyFeedback.new()
		feedback.name = "EnemyFeedback"
		add_child(feedback)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.mass_combat = combat
	configure(level_config)


func _exit_tree() -> void:
	if GameManager.mass_combat == combat:
		GameManager.mass_combat = null


func configure(config: LevelConfig) -> void:
	level_config = config
	_ending = false
	spawner.reset_spawning()
	world.reset_world()
	combat.reset_combat()
	if combat is EnemyGPUCombat:
		combat.separation_enabled = config != null and config.mass_gpu_separation
		combat.separation_speed = config.mass_separation_speed if config != null else 120.0
		combat.separation_padding = config.mass_separation_padding if config != null else 2.0
	spawner.set_level_config(config)


func begin(points: Array[Node2D]) -> bool:
	spawner.set_spawn_points(points)
	_sync_obstacles()
	return spawner.start_spawning()


func _physics_process(_delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING:
		_sync_obstacles()
		if spawner.is_spawn_complete() and world.get_active_count() == 0:
			# A turret can kill the last enemy in _process after the previous physics flush.
			# Deliver that reward before opening the end-of-round summary.
			combat.flush_combat_events()
			_check_wave_end()


func _sync_obstacles() -> void:
	var obstacles: Array[Dictionary] = []
	_obstacle_nodes.clear()
	for node in GameManager.get_barriers():
		if not is_instance_valid(node) or not bool(node.get("active")):
			continue
		var half := Vector2.ZERO
		if node is Barrier:
			half = node.barrier_config.size * 0.5
		elif node is GridDefenseBlock:
			half = node.block_size * 0.5
		else:
			continue
		var id := node.get_instance_id()
		_obstacle_nodes[id] = node
		obstacles.append({"id": id, "center": node.get_avoidance_center(), "half_size": half, "yaw": node.world_yaw, "hp": node.hp})
	combat.set_obstacles(obstacles)
	var planet := GameManager.get_player_planet()
	if is_instance_valid(planet):
		var pos: Vector2 = planet.global_position
		combat.planet_position = Vector3(pos.x, 0, pos.y)


func _on_combat_events(kills: int, _escaped: int, credits: float, planet_damage: float, obstacles: Dictionary) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	for id in obstacles:
		var node: Node = _obstacle_nodes.get(id)
		if is_instance_valid(node):
			DamageSystem.apply(node, obstacles[id], DamageSystem.Team.ENEMY)
	if planet_damage > 0 and (level_config == null or not level_config.mass_planet_invulnerable):
		DamageSystem.apply(GameManager.get_player_planet(), planet_damage, DamageSystem.Team.ENEMY)
	if credits > 0:
		GameManager.add_credits(credits)
	# Defeat takes precedence over a simultaneous final kill.
	if GameManager.current_state == GameManager.GameState.PLAYING and kills > 0:
		GameManager.register_eliminated_threat(kills)
	_check_wave_end()


func _on_feedback_events(events: Array) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if feedback != null:
		feedback.show_events(events, world)
	if not world.use_legacy_rules:
		return
	var damage := 3.0 * UpgradeManager.get_multiplier("DebrisDamage")
	var pierce := int(UpgradeManager.get_total_bonus("DebrisPiercing"))
	var count := clampi(2 + int(UpgradeManager.get_total_bonus("DebrisAmount")), 1, 16)
	for event: Dictionary in events:
		if event.kind != "death" or not world.get_archetype(event.archetype).drops_debris:
			continue
		var success := randf() < GameManager.debris_chance
		if UpgradeManager.b_next_debris_guaranteed:
			success = true
			UpgradeManager.b_next_debris_guaranteed = false
		if not success:
			continue
		debris_bursts += 1
		GameManager.debris_chance = 0.2 + UpgradeManager.get_total_bonus("DebrisChance")
		var directions: Array[Vector2] = [Vector2(0,-1),Vector2(0,1),Vector2(1,0),Vector2(-1,0),Vector2(1,-1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,1),Vector2(0.5,-1),Vector2(1,-0.5),Vector2(1,0.5),Vector2(0.5,1),Vector2(-0.5,1),Vector2(-1,0.5),Vector2(-1,-0.5),Vector2(-0.5,-1)]
		directions.shuffle()
		for i in range(count):
			var direction := (directions[i].normalized() + Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))).normalized()
			if not combat.fire_debris(event.position, Vector3(direction.x, 0, direction.y), damage, pierce):
				rejected_debris_commands += 1


func _check_wave_end() -> void:
	if not _ending and spawner.is_spawn_complete() and world.get_active_count() == 0 and GameManager.current_state == GameManager.GameState.PLAYING:
		_ending = true
		GameManager.end_round()


func _on_state_changed(state: GameManager.GameState) -> void:
	if state in [GameManager.GameState.PREPARATION, GameManager.GameState.END_SESSION]:
		spawner.reset_spawning()
		world.reset_world()
		combat.reset_combat()
