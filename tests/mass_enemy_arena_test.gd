extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena: Node = load("res://src/prototypes/mass_enemies/MassEnemyArena.tscn").instantiate()
	add_child(arena)
	arena.spawner.set_process(false)
	arena.combat.simulation_enabled = false
	arena.spawner.advance_spawning(1.0)
	if arena.world.get_active_count() != 350:
		push_error("Arena must spawn its configured 350 enemies, bounded by total.")
		get_tree().quit(1)
		return
	for i in range(60):
		arena.combat.step(1.0 / 60.0)
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://mass_enemy_arena.png")
	var pause := InputEventKey.new()
	pause.keycode = KEY_P
	pause.pressed = true
	arena._unhandled_key_input(pause)
	var count: int = arena.world.get_active_count()
	arena.spawner.advance_spawning(5)
	if not arena.paused or arena.combat.simulation_enabled or arena.world.get_active_count() != count:
		push_error("Arena pause must preserve its data population.")
		get_tree().quit(1)
		return
	arena.queue_free()
	await get_tree().process_frame
	print("Mass enemy arena smoke test passed.")
	get_tree().quit()
