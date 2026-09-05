extends Node3D

## F6: configurable paced spawning and the same combat/rendering services as gameplay.
@export var level_config: LevelConfig = preload("res://src/prototypes/mass_enemies/MassEnemyTestConfig.tres")
@export_range(1, 10000) var test_population: int = 350
@export var use_gpu_transforms: bool = true
@export var use_gpu_simulation: bool = true
var world: EnemyWorld
var combat: EnemyCombat
var renderer: EnemyMultiMeshRenderer
var spawner: MassEnemySpawner
var status: Label
var paused: bool = false
var fire_timer: float = 0.0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1700
	camera.position = Vector3(0, 2000, 0)
	camera.rotation_degrees.x = -90
	camera.far = 5000
	add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101526")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	world = EnemyWorld.new()
	add_child(world)
	combat = EnemyGPUCombat.new() if use_gpu_simulation and RenderingServer.get_rendering_device() != null else EnemyCombat.new()
	combat.enemy_world = world
	combat.respect_game_state = false
	add_child(combat)
	renderer = EnemyMultiMeshRenderer.new()
	renderer.enemy_world = world
	renderer.use_gpu_transforms = use_gpu_transforms
	if combat is EnemyGPUCombat:
		renderer.gpu_combat = combat
	add_child(renderer)
	var shots := EnemyProjectileRenderer.new()
	shots.combat = combat
	add_child(shots)
	spawner = MassEnemySpawner.new()
	spawner.enemy_world = world
	spawner.respect_game_state = false
	add_child(spawner)
	var points: Array[Node2D] = []
	for i in range(40):
		var point := Node2D.new()
		point.position = Vector2.from_angle(i * TAU / 40.0) * 750
		add_child(point)
		points.append(point)
	spawner.set_spawn_points(points)
	var planet_mesh := SphereMesh.new()
	planet_mesh.radius = combat.planet_radius
	planet_mesh.height = combat.planet_radius * 2
	_add_mesh(planet_mesh, Vector3.ZERO, Color("3388cc"))
	var obstacles: Array[Dictionary] = []
	for i in range(8):
		var point := Vector2.from_angle(i * TAU / 8.0) * 300
		obstacles.append({"id": i + 1, "center": point, "half_size": Vector2(30, 15), "yaw": 0.0, "hp": 50.0})
		var box := BoxMesh.new()
		box.size = Vector3(60, 20, 30)
		var visual := _add_mesh(box, Vector3(point.x, 0, point.y), Color("ad7854"))
		visual.name = "Obstacle%d" % (i + 1)
	combat.set_obstacles(obstacles)
	combat.combat_events.connect(_on_events)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 20)
	canvas.add_child(status)
	_restart()


func _add_mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	add_child(visual)
	return visual


func _restart() -> void:
	spawner.reset_spawning()
	world.reset_world()
	combat.reset_combat()
	for obstacle in combat._obstacles:
		obstacle.hp = 50.0
		get_node("Obstacle%d" % obstacle.id).show()
	var config := level_config.duplicate() as LevelConfig
	config.total_enemies = test_population
	spawner.set_level_config(config)
	spawner.start_spawning()
	if paused:
		spawner.stop_spawning()


func _process(delta: float) -> void:
	status.text = "Mass Enemy Arena | simulação %s\nAtivos %d | spawn %d/%d | tiros %d\nPreparo simulação %.2f ms | preparo visual %.2f ms\nMortes %d | impactos %d | dano planeta %.0f\n1:350  2:1000  3:5000  4:10000 | R: reiniciar | P: pausar\n8 emissores aliados de teste" % [
		"GPU" if combat is EnemyGPUCombat else "CPU", world.get_active_count(), spawner.spawned_enemy_count,
		test_population, combat.shot_count, combat.last_simulation_ms, renderer.last_update_ms,
		combat.total_kills, combat.total_escaped, combat.total_planet_damage]
	if paused:
		return
	fire_timer -= delta
	if fire_timer <= 0:
		fire_timer = 0.15
		for i in range(8):
			var forward := Vector2.from_angle(i * TAU / 8.0)
			var origin := Vector3(forward.x, 0, forward.y) * 100
			var target := combat.find_target(origin, 650, forward, 90)
			if target >= 0:
				combat.fire_projectile(origin, world.positions[target & EnemyWorld.SLOT_MASK] - origin, 2, 350, 4, DamageSystem.Team.ALLY)


func _on_events(_kills: int, _escaped: int, _credits: float, _damage: float, _obstacles: Dictionary) -> void:
	for obstacle in combat._obstacles:
		if obstacle.hp <= 0:
			get_node("Obstacle%d" % obstacle.id).hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_P:
		paused = not paused
		combat.simulation_enabled = not paused
		if paused:
			spawner.stop_spawning()
		else:
			spawner.resume_spawning()
	elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_R]:
		if event.keycode != KEY_R:
			test_population = [350, 1000, 5000, 10000][event.keycode - KEY_1]
		_restart()
