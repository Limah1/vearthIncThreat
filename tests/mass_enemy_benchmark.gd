extends Node3D

## Real rendered benchmark. No headless results are accepted.
const POPULATIONS := [350, 1000, 5000, 10000]
const WARMUP := 30
const SAMPLES := 120
var report: Dictionary = {}
var world: EnemyWorld
var combat: EnemyCombat
var renderer: EnemyMultiMeshRenderer
var catalog: Array[EnemyData] = []
var label: Label
var gpu_simulation: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	gpu_simulation = "--gpu-simulation" in OS.get_cmdline_user_args()
	if RenderingServer.get_rendering_device() == null:
		push_error("Benchmark requires a real GPU; do not use --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_window().size = Vector2i(1920, 1080)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4500
	camera.position = Vector3(0, 3000, 0)
	camera.rotation_degrees.x = -90
	camera.far = 6000
	add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -25, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101526")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 20)
	canvas.add_child(label)
	world = EnemyWorld.new()
	add_child(world)
	for name in ["asteroid_small", "asteroid_medium", "asteroid_large", "barrier_attack_ship"]:
		catalog.append(load("res://src/resources/enemies/%s.tres" % name) as EnemyData)
	world.register_catalog(catalog)
	combat = EnemyGPUCombat.new() if gpu_simulation else EnemyCombat.new()
	combat.enemy_world = world
	combat.simulation_enabled = false
	combat.respect_game_state = false
	add_child(combat)
	var shots := EnemyProjectileRenderer.new()
	shots.combat = combat
	add_child(shots)
	report = {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"build": "debug" if OS.is_debug_build() else "release",
		"gpu": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_current_rendering_driver_name(),
		"resolution": str(get_window().size), "vsync": false, "warmup_frames": WARMUP, "samples": SAMPLES,
		"distribution": "60% small, 25% medium, 10% large, 5% ships; annulus 1200..1900; all inside camera",
		"gpu_simulation": gpu_simulation,
		"combat_workload": "60Hz fixed-step per sampled frame; 8 barriers; 32 allied targeting emitters every 6 steps; no VFX except pooled shots",
		"results": []}
	for gpu in ([true] if gpu_simulation else [false, true]):
		renderer = EnemyMultiMeshRenderer.new()
		renderer.enemy_world = world
		renderer.use_gpu_transforms = gpu
		if gpu_simulation:
			renderer.gpu_combat = combat
		add_child(renderer)
		renderer.set_process(false)
		for simulate in ([true] if gpu_simulation else [false, true]):
			for population in POPULATIONS:
				await _measure(population, gpu, simulate)
		renderer.queue_free()
		for i in range(3):
			await RenderingServer.frame_post_draw
	var output := "user://mass_enemy_gpu_benchmark.json" if gpu_simulation else "user://mass_enemy_benchmark.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write benchmark report: " + output)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Mass enemy rendered benchmark passed: " + ProjectSettings.globalize_path(output))
	get_tree().quit()


func _measure(population: int, gpu: bool, simulate: bool) -> void:
	world.reset_world()
	combat.reset_combat()
	var obstacles: Array[Dictionary] = []
	for i in range(8):
		var point := Vector2.from_angle(i * TAU / 8.0) * 750
		obstacles.append({"id": i + 1, "center": point, "half_size": Vector2(30, 15), "yaw": i * 0.1, "hp": 10000.0})
	combat.set_obstacles(obstacles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	for i in range(population):
		var roll := i % 100
		var archetype := 0 if roll < 60 else (1 if roll < 85 else (2 if roll < 95 else 3))
		var angle := rng.randf_range(0, TAU)
		var radius := rng.randf_range(1200, 1900)
		world.request_spawn(catalog[archetype], Vector3(cos(angle) * radius, 0, sin(angle) * radius))
	var frames: Array[float] = []
	var sim_times: Array[float] = []
	var upload_times: Array[float] = []
	var gpu_times: Array[float] = []
	var cpu_times: Array[float] = []
	label.text = "%d enemies | %s transforms | %s\n1920x1080 / VSync OFF / fixed sample workload" % [population, "GPU" if gpu else "CPU", ("combat GPU" if gpu_simulation else "combat CPU") if simulate else "render only"]
	var previous := Time.get_ticks_usec()
	for frame in range(WARMUP + SAMPLES):
		var sim_start := Time.get_ticks_usec()
		if simulate:
			combat.step(1.0 / 60.0)
			if frame % 6 == 0:
				for emitter in range(32):
					var forward := Vector2.from_angle(emitter * TAU / 32.0)
					var origin := Vector3(forward.x, 0, forward.y) * 600
					var handle := combat.find_target(origin, 1300, forward, 90)
					if handle >= 0:
						combat.fire_projectile(origin, world.positions[handle & EnemyWorld.SLOT_MASK] - origin, 0.01, 350, 4, DamageSystem.Team.ALLY)
		var sim_ms := (Time.get_ticks_usec() - sim_start) / 1000.0
		renderer.update_visuals()
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame >= WARMUP:
			frames.append((now - previous) / 1000.0)
			sim_times.append(sim_ms)
			upload_times.append(renderer.last_update_ms)
			gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		previous = now
	var result := {"population": population, "active_end": world.get_active_count(), "gpu_transforms": gpu, "combat": simulate,
		"frame_median_ms": _percentile(frames, 0.5), "frame_p95_ms": _percentile(frames, 0.95),
		"simulation_median_ms": _percentile(sim_times, 0.5), "upload_median_ms": _percentile(upload_times, 0.5),
		"viewport_gpu_median_ms": _percentile(gpu_times, 0.5), "viewport_cpu_median_ms": _percentile(cpu_times, 0.5),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_nodes": renderer.get_child_count(), "projectiles": combat.shot_count, "rejected_shots": combat.dropped_projectiles}
	report.results.append(result)
	print(JSON.stringify(result))
	if population == 10000 and gpu and not simulate:
		get_viewport().get_texture().get_image().save_png("user://mass_enemy_10000.png")
	if gpu_simulation:
		if population == 10000:
			get_viewport().get_texture().get_image().save_png("user://mass_enemy_gpu_combat_10000.png")
		var snapshots: Array[PackedByteArray] = []
		var receive := func(bytes: PackedByteArray): snapshots.append(bytes)
		combat.diagnostic_ready.connect(receive, CONNECT_ONE_SHOT)
		combat.request_diagnostic()
		for i in range(40):
			await get_tree().process_frame
			if not snapshots.is_empty():
				break
		var gpu_alive := 0
		if not snapshots.is_empty():
			for slot in range(world.capacity):
				if snapshots[0].decode_u32(slot * 64 + 32) != 0:
					gpu_alive += 1
		result["gpu_active_end"] = gpu_alive
		result["reports_received"] = combat.reports_received
		result["readback_bytes"] = combat.readback_bytes
		if gpu_alive != population or not combat.backend_error.is_empty():
			push_error("GPU benchmark population/backend validation failed.")
			get_tree().quit(1)


func _percentile(values: Array[float], fraction: float) -> float:
	values.sort()
	return values[mini(values.size() - 1, int(values.size() * fraction))]
