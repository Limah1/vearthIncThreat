extends Node

var failures: int = 0
var cpu_world: EnemyWorld
var gpu_world: EnemyWorld
var cpu: EnemyCombat
var gpu: EnemyGPUCombat
var diagnostic := PackedByteArray()
var render_bytes := PackedByteArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		push_error("GPU combat tests require a real RenderingDevice.")
		get_tree().quit(1)
		return
	for path in ["enemy_sim", "enemy_sim_render"]:
		var shader := load("res://src/assets/shaders/%s.glsl" % path) as RDShaderFile
		var error := shader.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		_expect(error.is_empty(), path + ": " + error)
	if failures > 0:
		get_tree().quit(1)
		return
	_setup()
	await _test_reference_parity()
	await _test_authoritative_render()
	await _test_queries_and_damage()
	await _test_projectiles()
	await _test_projectile_capacity()
	await _test_legacy_rules_and_debris()
	await _test_mailbox_overflow_and_reset()
	await _test_separation()
	_expect(gpu.backend_error.is_empty(), "Backend must not report errors: " + gpu.backend_error)
	for node in [gpu, cpu, gpu_world, cpu_world]:
		node.queue_free()
	for i in range(5):
		await get_tree().process_frame
	if failures == 0:
		print("GPU combat tests passed: CPU parity, targeting, projectiles, concurrent deaths, report overflow, stale handles and reset.")
	get_tree().quit(failures)


func _setup() -> void:
	cpu_world = EnemyWorld.new()
	gpu_world = EnemyWorld.new()
	add_child(cpu_world)
	add_child(gpu_world)
	cpu = EnemyCombat.new()
	cpu.enemy_world = cpu_world
	cpu.simulation_enabled = false
	cpu.respect_game_state = false
	add_child(cpu)
	gpu = EnemyGPUCombat.new()
	gpu.enemy_world = gpu_world
	gpu.simulation_enabled = false
	gpu.respect_game_state = false
	gpu.report_interval = 1
	add_child(gpu)
	gpu.diagnostic_ready.connect(func(bytes: PackedByteArray): diagnostic = bytes)


func _data(name: String) -> EnemyData:
	var data := load("res://src/resources/enemies/%s.tres" % name) as EnemyData
	cpu_world.register_catalog([data])
	gpu_world.register_catalog([data])
	return data


func _reset() -> void:
	cpu_world.reset_world()
	gpu_world.reset_world()
	cpu.reset_combat()
	gpu.reset_combat()
	cpu.set_obstacles([])
	gpu.set_obstacles([])


func _step_both(delta: float, count: int) -> void:
	for i in range(count):
		cpu.step(delta)
		gpu.step(delta)
		await get_tree().process_frame


func _snapshot() -> PackedByteArray:
	diagnostic = PackedByteArray()
	gpu.request_diagnostic()
	for i in range(40):
		await get_tree().process_frame
		if not diagnostic.is_empty():
			return diagnostic
	_expect(false, "Diagnostic readback timed out.")
	return PackedByteArray()


func _pump(count: int = 12) -> void:
	for i in range(count):
		gpu.step(0)
		gpu.flush_combat_events()
		await get_tree().process_frame


func _compare(bytes: PackedByteArray, count: int) -> void:
	if bytes.is_empty():
		return
	for i in range(count):
		var slot := cpu_world.get_active_slot(i)
		var offset := gpu_world.get_active_slot(i) * 64
		var position_gpu := Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))
		_expect(position_gpu.distance_to(cpu_world.positions[slot]) < 0.04, "CPU/GPU trajectory mismatch at %d: %s / %s" % [slot, cpu_world.positions[slot], position_gpu])
		_expect(bytes.decode_u32(offset + 32) == cpu_world.states[slot], "CPU/GPU behavior state mismatch at %d" % slot)
		_expect(absf(angle_difference(bytes.decode_float(offset + 12), cpu_world.headings[slot])) < 0.005, "CPU/GPU heading mismatch.")


func _test_reference_parity() -> void:
	_reset()
	var asteroid := _data("asteroid_small")
	var ship := _data("barrier_attack_ship")
	var obstacles: Array[Dictionary] = [{"id": 101, "center": Vector2(0, 200), "half_size": Vector2(10, 10), "yaw": 0.0, "hp": 10000.0}]
	cpu.set_obstacles(obstacles)
	gpu.set_obstacles(obstacles)
	for i in range(24):
		var position_3d := Vector3(-500 - i * 10, 0, 400 + i * 5)
		cpu_world.request_spawn(asteroid, position_3d)
		gpu_world.request_spawn(asteroid, position_3d)
	cpu_world.request_spawn(ship, Vector3(0, 0, 500))
	gpu_world.request_spawn(ship, Vector3(0, 0, 500))
	await _step_both(0.02, 100)
	_compare(await _snapshot(), 25)
	var anchor := cpu_world.positions[24]
	cpu.set_obstacles([])
	gpu.set_obstacles([])
	await _step_both(0.02, 100)
	var bytes := await _snapshot()
	_compare(bytes, 25)
	_expect(cpu_world.positions[24].is_equal_approx(anchor), "Ship must keep its position after barrier destruction.")
	_expect(bytes.decode_u32(24 * 64 + 32) == EnemyWorld.State.ATTACK_PLANET, "GPU ship must switch to planet attack.")


func _test_authoritative_render() -> void:
	var tumble := load("res://src/resources/enemies/asteroid_small.tres").duplicate() as EnemyData
	tumble.enemy_id = &"render_tumble"
	tumble.tumble_visual = true
	tumble.max_hp = 100
	gpu_world.register_catalog([tumble])
	var tumble_handle := gpu_world.request_spawn(tumble, Vector3(1000, 0, 1000))
	gpu.step(0.25)
	gpu.apply_damage(tumble_handle, 1)
	gpu.step(0)
	var renderer := EnemyMultiMeshRenderer.new()
	renderer.enemy_world = gpu_world
	renderer.gpu_combat = gpu
	add_child(renderer)
	renderer.set_process(false)
	# CPU snapshots are deliberately wrong: the renderer must use GPU state.
	for i in range(gpu_world.get_active_count()):
		gpu_world.positions[gpu_world.get_active_slot(i)] = Vector3(9999, 9999, 9999)
	await _verify_render(renderer)
	var dead := gpu_world.get_active_handle(0)
	gpu.apply_damage(dead, 100000)
	gpu.step(0)
	# Do not consume the death report yet. The allocated slot must already hide.
	await _verify_render(renderer)
	_expect(gpu_world.is_handle_valid(dead), "Render test must precede CPU death acknowledgement.")
	renderer.queue_free()
	await get_tree().process_frame


func _verify_render(renderer: EnemyMultiMeshRenderer) -> void:
	renderer.update_visuals()
	var state := await _snapshot()
	if state.is_empty():
		return
	for batch in renderer.batches:
		render_bytes = PackedByteArray()
		RenderingServer.call_on_render_thread(_read_render.bind(batch.mesh_instance.multimesh))
		for frame in range(40):
			await get_tree().process_frame
			if not render_bytes.is_empty():
				break
		_expect(render_bytes.size() >= batch.count * 64, "Authoritative MultiMesh diagnostic must complete.")
		if render_bytes.size() < batch.count * 64:
			continue
		var expected := PackedFloat32Array()
		expected.resize(batch.count * 12)
		for i in range(batch.count):
			var slot := renderer._slot_groups[batch.archetype][i]
			var offset: int = slot * 64
			if state.decode_u32(offset + 32) == EnemyWorld.State.INACTIVE:
				continue
			var position_gpu := Vector3(state.decode_float(offset), state.decode_float(offset + 4), state.decode_float(offset + 8))
			var basis := EnemyMultiMeshRenderer.enemy_basis(state.decode_float(offset + 12), gpu_world.get_archetype(batch.archetype).tumble_visual)
			var transform := Transform3D(basis, position_gpu) * batch.local_transform
			EnemyMultiMeshRenderer.write_transform(expected, i * 12, transform)
		var actual := render_bytes.to_float32_array()
		if gpu_world.get_archetype(batch.archetype).enemy_id == &"render_tumble":
			_expect(actual[12] > 1.0 and actual[15] == 1.0, "Recent damage must write an opaque HDR hit flash into instance color.")
		for i in range(expected.size()):
			var actual_index := (i / 12) * 16 + i % 12
			if absf(actual[actual_index] - expected[i]) > 0.002:
				_expect(false, "Authoritative GPU transform mismatch at %d: %f / %f" % [i, actual[actual_index], expected[i]])
				break


func _read_render(multimesh: MultiMesh) -> void:
	var rd := RenderingServer.get_rendering_device()
	var rid := RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid())
	rd.buffer_get_data_async(rid, func(bytes: PackedByteArray): call_deferred("_receive_render", bytes))


func _receive_render(bytes: PackedByteArray) -> void:
	render_bytes = bytes


func _test_queries_and_damage() -> void:
	_reset()
	var data := _data("asteroid_small")
	var first := gpu_world.request_spawn(data, Vector3(100, 0, 0))
	var second := gpu_world.request_spawn(data, Vector3(130, 0, 0))
	var behind := gpu_world.request_spawn(data, Vector3(-100, 0, 0))
	gpu.find_target(Vector3.ZERO, 300, Vector2.RIGHT, 45)
	await _pump()
	_expect(gpu.find_target(Vector3.ZERO, 300, Vector2.RIGHT, 45) == first, "GPU targeting must honor nearest/cone.")
	_expect(not gpu.apply_damage(first, 100, DamageSystem.Team.ENEMY), "Enemy team must not damage enemies.")
	for i in range(32):
		gpu.damage_circle(Vector3(115, 0, 0), 20, 10)
	await _pump()
	_expect(not gpu_world.is_handle_valid(first) and not gpu_world.is_handle_valid(second), "Concurrent area attacks must kill both enemies.")
	_expect(gpu_world.is_handle_valid(behind), "Out-of-area enemy must survive.")
	_expect(gpu.total_kills == 2 and gpu.total_credits == data.credit_value * 2, "Concurrent GPU damage must award each death once.")
	_expect(not gpu.apply_damage(first, 100), "Stale CPU handle must reject commands.")
	# A queued command may become stale before reaching the GPU as well.
	gpu.apply_damage(behind, 100)
	gpu_world.recycle(behind)
	var fresh := gpu_world.request_spawn(data, Vector3(-200, 0, 0))
	await _pump()
	_expect(gpu_world.is_handle_valid(fresh), "Queued old-generation damage must not reach a reused slot.")


func _test_projectiles() -> void:
	_reset()
	var data := _data("asteroid_small")
	var first := gpu_world.request_spawn(data, Vector3(100, 0, 0))
	var second := gpu_world.request_spawn(data, Vector3(200, 0, 0))
	gpu.fire_projectile(Vector3.ZERO, Vector3.RIGHT, 100, 1000, 2, DamageSystem.Team.ALLY)
	gpu.step(0.3)
	await _pump()
	_expect(not gpu_world.is_handle_valid(first) and gpu_world.is_handle_valid(second), "Swept GPU projectile must hit only the nearest enemy.")
	gpu.set_obstacles([{"id": 8, "center": Vector2(0, 150), "half_size": Vector2(20, 5), "yaw": 0.4, "hp": 100.0}])
	gpu.fire_projectile(Vector3(0, 0, 300), Vector3.FORWARD, 4, 1000, 2, DamageSystem.Team.ENEMY)
	gpu.step(0.5)
	await _pump()
	_expect(gpu.total_planet_damage == 0, "Rotated barrier must intercept enemy fire before planet.")
	_expect(is_equal_approx(gpu._obstacles[0].hp, 96), "GPU barrier damage must be reported exactly once.")
	gpu.set_obstacles([])
	gpu.fire_projectile(Vector3(0, 0, 300), Vector3.FORWARD, 4, 1000, 2, DamageSystem.Team.ENEMY)
	gpu.step(0.5)
	await _pump()
	_expect(is_equal_approx(gpu.total_planet_damage, 4), "GPU projectile must damage planet after barrier removal.")


func _test_projectile_capacity() -> void:
	_reset()
	for i in range(gpu.projectile_capacity + 17):
		_expect(gpu.fire_projectile(Vector3(3000, 0, 3000), Vector3.RIGHT, 1, 10, 2, DamageSystem.Team.ALLY), "CPU command queue must accept the bounded projectile burst.")
	await _pump()
	_expect(gpu.shot_count == gpu.projectile_capacity, "GPU projectile pool must fill exactly to capacity.")
	_expect(gpu.dropped_projectiles == 17, "GPU projectile overflow must report every rejected allocation.")
	gpu.step(3)
	await _pump()
	_expect(gpu.shot_count == 0, "Expired GPU projectiles must release their slots.")
	for i in range(gpu.projectile_capacity):
		gpu.fire_projectile(Vector3(3000, 0, 3000), Vector3.RIGHT, 1, 10, 2, DamageSystem.Team.ALLY)
	await _pump()
	_expect(gpu.shot_count == gpu.projectile_capacity and gpu.dropped_projectiles == 17, "Recovered projectile slots must support a second full burst without leakage.")
	_reset()
	var data := _data("asteroid_small")
	var target := gpu_world.request_spawn(data, Vector3(100, 0, 35))
	gpu.fire_projectile_with_radius(Vector3.ZERO, Vector3.RIGHT, 100, 1000, 2, DamageSystem.Team.ALLY, 15)
	gpu.step(0.2)
	await _pump()
	_expect(not gpu_world.is_handle_valid(target), "Satellite GPU delegation must preserve its larger collision radius.")


func _test_legacy_rules_and_debris() -> void:
	var profile := EnemyWorld.new()
	profile.use_legacy_rules = true
	profile.zone = 3
	add_child(profile)
	var asteroid := load("res://src/resources/enemies/asteroid_small.tres") as EnemyData
	var ship := load("res://src/resources/enemies/barrier_attack_ship.tres") as EnemyData
	_expect(profile.register_catalog([asteroid, ship]).is_empty(), "Legacy profile must register without mutating source Resources.")
	var scaled := profile.get_archetype(0)
	_expect(is_equal_approx(scaled.movement_speed, 93.5) and is_equal_approx(scaled.damage, 1.0), "Asteroid zone speed must scale while authored damage stays fixed.")
	_expect(scaled.drops_debris and not scaled.tumble_visual and scaled.face_planet and not scaled.planet_contact_includes_radius, "Directional legacy asteroids must face the planet without tumble and keep center-based planet impact.")
	_expect(is_equal_approx(profile.get_archetype(1).max_hp, 14.88) and is_equal_approx(profile.get_archetype(1).credit_value, 24.8), "Ship zone HP/reward must match legacy without restoring orbit AI.")
	for i in range(100):
		var handle := profile.request_spawn(asteroid, Vector3(1000, 0, 0))
		var hp := profile.health[handle & EnemyWorld.SLOT_MASK]
		_expect(hp == 1.0, "Legacy profile must preserve the authored Small Asteroid HP.")
	_expect(asteroid.max_hp == 1 and not asteroid.drops_debris, "Runtime profile must leave authored Resources untouched.")
	profile.queue_free()
	_reset()
	var data := asteroid.duplicate() as EnemyData
	data.enemy_id = &"slow_parity"
	data.max_hp = 100
	data.movement_speed = 100
	data.hit_slow_duration = 0.4
	data.hit_speed_factor = 0.8
	cpu_world.register_catalog([data])
	gpu_world.register_catalog([data])
	var c := cpu_world.request_spawn(data, Vector3(1000, 0, 0))
	var g := gpu_world.request_spawn(data, Vector3(1000, 0, 0))
	await _step_both(0.1, 1)
	cpu.apply_damage(c, 1)
	gpu.apply_damage(g, 1)
	await _pump()
	var cpu_slot := c & EnemyWorld.SLOT_MASK
	var before := cpu_world.positions[cpu_slot]
	await _step_both(0.2, 1)
	_compare(await _snapshot(), 1)
	_expect(is_equal_approx(before.x - cpu_world.positions[cpu_slot].x, 16), "Damaged asteroid must move at 80% speed.")
	before = cpu_world.positions[cpu_slot]
	await _step_both(0.3, 1)
	_compare(await _snapshot(), 1)
	_expect(is_equal_approx(before.x - cpu_world.positions[cpu_slot].x, 24), "A tick that starts slowed must stay slowed for that tick, matching legacy.")
	before = cpu_world.positions[cpu_slot]
	await _step_both(0.1, 1)
	_compare(await _snapshot(), 1)
	_expect(is_equal_approx(before.x - cpu_world.positions[cpu_slot].x, 10), "Asteroid speed must recover on the next tick after 0.4 seconds.")
	_reset()
	data = data.duplicate() as EnemyData
	data.enemy_id = &"debris_parity"
	data.movement_speed = 0
	cpu_world.register_catalog([data])
	gpu_world.register_catalog([data])
	for i in range(3):
		cpu_world.request_spawn(data, Vector3(1000 + i * 30, 0, 0))
		gpu_world.request_spawn(data, Vector3(1000 + i * 30, 0, 0))
	cpu.fire_debris(Vector3(940, 0, 0), Vector3.RIGHT, 3, 1)
	gpu.fire_debris(Vector3(940, 0, 0), Vector3.RIGHT, 3, 1)
	await _step_both(0.5, 1)
	await _pump()
	var bytes := await _snapshot()
	for i in range(3):
		var expected := 97.0 if i < 2 else 100.0
		_expect(is_equal_approx(cpu_world.health[cpu_world.get_active_slot(i)], expected) and is_equal_approx(bytes.decode_float(gpu_world.get_active_slot(i) * 64 + 48), expected), "Debris piercing must hit exactly two distinct enemies, CPU and GPU.")
	_expect(gpu.shot_count == 0, "Debris must recycle after exhausting piercing.")
	_reset()
	g = gpu_world.request_spawn(data, Vector3(1000, 0, 0))
	gpu.fire_projectile_with_radius(Vector3(1000, 0, 0), Vector3.RIGHT, 3, 1, 3, DamageSystem.Team.ALLY, 20, 3, 1)
	for i in range(5):
		gpu.step(0.1)
		await get_tree().process_frame
	bytes = await _snapshot()
	_expect(is_equal_approx(bytes.decode_float((g & EnemyWorld.SLOT_MASK) * 64 + 48), 97), "Debris cannot repeatedly damage the same overlapping handle.")
	gpu_world.recycle(g)
	g = gpu_world.request_spawn(data, Vector3(1000, 0, 0))
	gpu.step(0.1)
	bytes = await _snapshot()
	_expect(is_equal_approx(bytes.decode_float((g & EnemyWorld.SLOT_MASK) * 64 + 48), 97), "Debris hit history must distinguish a reused slot's new generation.")


func _test_mailbox_overflow_and_reset() -> void:
	_reset()
	var observed := {"death": 0, "hit": 0}
	var collect := func(events: Array):
		for event: Dictionary in events:
			if observed.has(event.kind):
				observed[event.kind] += 1
	gpu.feedback_events.connect(collect)
	var data := _data("asteroid_small")
	for i in range(3000):
		gpu_world.request_spawn(data, Vector3(800 + i % 10, 0, 800))
	gpu.damage_circle(Vector3(805, 0, 800), 100, 100)
	await _pump(35)
	_expect(gpu_world.get_active_count() == 0, "More than one report page of deaths must eventually recycle all slots.")
	_expect(gpu.total_kills == 3000 and gpu.total_credits == data.credit_value * 3000, "Overflow pages must not lose or duplicate rewards.")
	_expect(observed.death == 3000, "Cosmetic feedback overflow must never discard gameplay death/debris events.")
	_expect(observed.hit <= EnemyGPUBackend.MAX_FEEDBACK and gpu.dropped_feedback >= 2872, "Cosmetic damage feedback must be bounded separately from gameplay events.")
	gpu.feedback_events.disconnect(collect)
	gpu_world.request_spawn(data, Vector3(100, 0, 0))
	gpu.apply_damage(gpu_world.get_active_handle(0), 100)
	gpu.step(0)
	gpu.reset_combat()
	var fresh := gpu_world.request_spawn(data, Vector3(500, 0, 0))
	await _pump()
	_expect(gpu_world.is_handle_valid(fresh) and gpu.total_kills == 0, "Reset must discard old in-flight GPU reports.")


func _gpu_position(bytes: PackedByteArray, handle: int) -> Vector3:
	var offset := (handle & EnemyWorld.SLOT_MASK) * 64
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))


func _test_separation() -> void:
	_reset()
	var data := load("res://src/resources/enemies/asteroid_small.tres").duplicate() as EnemyData
	data.enemy_id = &"separation_test"
	data.movement_speed = 0
	gpu_world.register_catalog([data])
	gpu.separation_enabled = true
	var a := gpu_world.request_spawn(data, Vector3(500, 0, 500))
	var b := gpu_world.request_spawn(data, Vector3(500, 0, 500))
	await _pump(2)
	var initial := await _snapshot()
	_expect(_gpu_position(initial, a) == _gpu_position(initial, b), "Zero-delta report pumps must not apply separation.")
	for i in range(40):
		gpu.step(0.02)
		await get_tree().process_frame
	var separated := await _snapshot()
	var pa := _gpu_position(separated, a)
	var pb := _gpu_position(separated, b)
	_expect(pa.is_finite() and pb.is_finite() and pa.distance_to(pb) >= 49.9, "Coincident GPU enemies must separate to their radius sum plus padding without NaNs.")
	_expect((pa + pb).distance_to(Vector3(1000, 0, 1000)) < 0.01, "Coincident-pair correction must be symmetric.")
	gpu.separation_enabled = false
	_reset()
	a = gpu_world.request_spawn(data, Vector3(500, 0, 500))
	b = gpu_world.request_spawn(data, Vector3(500, 0, 500))
	gpu.step(0.1)
	await get_tree().process_frame
	var disabled := await _snapshot()
	_expect(_gpu_position(disabled, a) == _gpu_position(disabled, b), "Disabling separation must preserve the original simulation.")
	_reset()
	gpu.separation_enabled = true
	var ship := _data("barrier_attack_ship")
	a = gpu_world.request_spawn(ship, Vector3(150, 0, 0))
	b = gpu_world.request_spawn(data, Vector3(150, 0, 0))
	for i in range(30):
		gpu.step(0.02)
		await get_tree().process_frame
	var anchored := await _snapshot()
	_expect(_gpu_position(anchored, a).distance_to(Vector3(150, 0, 0)) < 0.001, "An attacking ship must retain its stationary anchor during separation.")
	_expect(_gpu_position(anchored, a).distance_to(_gpu_position(anchored, b)) >= 45.9, "A mobile asteroid must yield to an anchored ship.")
	_reset()
	gpu.set_obstacles([{"id": 9001, "center": Vector2(500, 500), "half_size": Vector2(10, 100), "yaw": 0.0, "hp": 10000.0}])
	a = gpu_world.request_spawn(data, Vector3(465, 0, 500))
	b = gpu_world.request_spawn(data, Vector3(455, 0, 500))
	for i in range(30):
		gpu.step(0.02)
		await get_tree().process_frame
	var clipped := await _snapshot()
	_expect(_gpu_position(clipped, a).x <= 466.001, "Separation must not push the enemy radius into a barrier.")
	_expect(gpu_world.is_handle_valid(a) and gpu_world.is_handle_valid(b), "Separation must not lose or recycle live slots.")
	gpu.separation_enabled = false
	_reset()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
