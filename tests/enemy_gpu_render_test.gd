extends Node

signal readback_ready(bytes: PackedByteArray)
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		push_error("GPU render parity requires a real RenderingDevice (run without --headless).")
		get_tree().quit(1)
		return
	var world := EnemyWorld.new()
	add_child(world)
	var data := load("res://src/resources/enemies/barrier_attack_ship.tres") as EnemyData
	world.register_catalog([data])
	var renderer := EnemyMultiMeshRenderer.new()
	renderer.enemy_world = world
	renderer.use_gpu_transforms = true
	add_child(renderer)
	renderer.set_process(false)
	for i in range(7):
		var handle := world.request_spawn(data, Vector3(10 * i, 0, 20 * i))
		world.headings[handle & EnemyWorld.SLOT_MASK] = float(i) * 0.35
	await _verify(world, renderer)
	# Recycle slots, grow the native instance buffer and add another archetype.
	world.recycle(world.get_active_handle(2))
	var asteroid := load("res://src/resources/enemies/asteroid_small.tres") as EnemyData
	world.register_catalog([asteroid])
	for i in range(140):
		var handle := world.request_spawn(data if i % 2 == 0 else asteroid, Vector3(-i * 3, i % 5, i * 2))
		world.headings[handle & EnemyWorld.SLOT_MASK] = float(i) * 0.11
	await _verify(world, renderer)
	# Movement must not require rebuilding the cached archetype membership.
	for i in range(world.get_active_count()):
		var slot := world.get_active_slot(i)
		world.positions[slot] += Vector3(13, 2, -7)
		world.headings[slot] += 0.7
	await _verify(world, renderer)
	world.reset_world()
	renderer.update_visuals()
	for batch in renderer.batches:
		if batch.mesh_instance.multimesh.visible_instance_count != 0:
			failures += 1
	renderer.queue_free()
	await get_tree().process_frame
	world.queue_free()
	for i in range(3):
		await RenderingServer.frame_post_draw
	if failures == 0:
		print("GPU render parity passed: transforms, hierarchy, mixed archetypes, movement, resize and recycle.")
	get_tree().quit(failures)


func _verify(world: EnemyWorld, renderer: EnemyMultiMeshRenderer) -> void:
	renderer.update_visuals()
	for i in range(5):
		await RenderingServer.frame_post_draw
	for batch in renderer.batches:
		RenderingServer.call_on_render_thread(_read.bind(batch.mesh_instance.multimesh))
		var bytes: PackedByteArray = await readback_ready
		var actual := bytes.to_float32_array()
		var expected := PackedFloat32Array()
		expected.resize(batch.count * 12)
		for i in range(batch.count):
			var slot := renderer._slot_groups[batch.archetype][i]
			var transform := Transform3D(Basis(Vector3.UP, world.headings[slot]), world.positions[slot]) * batch.local_transform
			EnemyMultiMeshRenderer.write_transform(expected, i * 12, transform)
		if actual.size() < expected.size():
			failures += 1
		else:
			for i in range(expected.size()):
				if absf(actual[i] - expected[i]) > 0.002:
					failures += 1
					push_error("GPU transform mismatch at %d: %f vs %f" % [i, actual[i], expected[i]])
					break


func _read(multimesh: MultiMesh) -> void:
	var rd := RenderingServer.get_rendering_device()
	var rid := RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid())
	var bytes := rd.buffer_get_data(rid)
	call_deferred("_deliver", bytes)


func _deliver(bytes: PackedByteArray) -> void:
	readback_ready.emit(bytes)
