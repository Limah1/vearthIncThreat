extends Node

var failures: int = 0
var world: EnemyWorld
var combat: EnemyCombat


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_asteroid_faces_planet()
	_test_asteroid_impact()
	_test_ship_state_machine()
	_test_grid_damage_and_recycling()
	_test_swept_projectile()
	_test_render_batches()
	_test_projectile_validation_and_capacity()
	if failures == 0:
		print("Enemy combat and CPU rendering tests passed.")
	get_tree().quit(failures)


func _setup() -> void:
	world = EnemyWorld.new()
	world.capacity = 32
	add_child(world)
	combat = EnemyCombat.new()
	combat.enemy_world = world
	combat.respect_game_state = false
	combat.simulation_enabled = false
	add_child(combat)


func _clean() -> void:
	combat.free()
	world.free()


func _data(ship: bool = false) -> EnemyData:
	var path := "barrier_attack_ship" if ship else "asteroid_small"
	var data := load("res://src/resources/enemies/%s.tres" % path).duplicate() as EnemyData
	data.radius = 2.0
	data.max_hp = 10
	data.movement_speed = 100
	data.rotation_speed = 100
	data.attack_range = 20
	data.projectile_speed = 500
	data.attack_interval = 1
	world.register_catalog([data])
	return data


func _test_asteroid_faces_planet() -> void:
	_setup()
	var data := load("res://src/resources/enemies/asteroid_small.tres").duplicate() as EnemyData
	data.movement_speed = 0.0
	data.rotation_speed = 100.0
	world.register_catalog([data])
	var right_handle := world.request_spawn(data, Vector3(200, 0, 0))
	var left_handle := world.request_spawn(data, Vector3(-200, 0, 0))
	combat.step(0.1)
	var right_slot := right_handle & EnemyWorld.SLOT_MASK
	var left_slot := left_handle & EnemyWorld.SLOT_MASK
	_expect(is_equal_approx(world.headings[right_slot], -PI * 0.5), "A small asteroid spawned on the right must face the planet.")
	_expect(is_equal_approx(world.headings[left_slot], PI * 0.5), "A small asteroid spawned on the left must face the planet.")
	_clean()


func _test_asteroid_impact() -> void:
	_setup()
	var data := _data()
	var handle := world.request_spawn(data, Vector3(0, 0, 200))
	combat.step(2.0)
	_expect(not world.is_handle_valid(handle), "Swept planet contact must recycle the asteroid.")
	_expect(combat.total_escaped == 1 and combat.total_planet_damage == data.damage, "Impact must damage once and resolve once.")
	_expect(combat.total_credits == 0, "Impacts must not award kill credits.")
	_clean()


func _test_ship_state_machine() -> void:
	_setup()
	var data := _data(true)
	combat.set_obstacles([{"id": 101, "center": Vector2(0, 200), "half_size": Vector2(10, 10), "yaw": 0.0, "hp": 10000.0}])
	var handle := world.request_spawn(data, Vector3(0, 0, 400))
	var slot := handle & EnemyWorld.SLOT_MASK
	for i in range(40):
		combat.step(0.05)
	_expect(world.states[slot] == EnemyWorld.State.ATTACK_BARRIER, "Ship must approach and stop to attack the barrier.")
	var anchor := world.positions[slot]
	for i in range(20):
		combat.step(0.05)
	_expect(world.positions[slot].is_equal_approx(anchor), "Attacking ship must hold its position.")
	combat.set_obstacles([])
	for i in range(100):
		combat.step(0.05)
	_expect(world.states[slot] == EnemyWorld.State.ATTACK_PLANET, "Destroyed barrier must trigger rotation and planet attack.")
	_expect(world.positions[slot].is_equal_approx(anchor), "Ship must stay anchored while turning and shooting the planet.")
	_expect(combat.total_planet_damage > 0, "Enemy projectiles must damage the planet.")
	_clean()


func _test_grid_damage_and_recycling() -> void:
	_setup()
	var data := _data()
	var a := world.request_spawn(data, Vector3(100, 0, 0))
	var b := world.request_spawn(data, Vector3(110, 0, 0))
	var behind := world.request_spawn(data, Vector3(-100, 0, 0))
	var target := combat.find_target(Vector3.ZERO, 200, Vector2.RIGHT, 45)
	_expect(target == a, "Targeting must honor cone and distance.")
	_expect(not combat.apply_damage(a, 50, DamageSystem.Team.ENEMY), "Enemy fire must not kill enemies.")
	_expect(combat.damage_circle(Vector3(105, 0, 0), 10, 50) == 2, "AoE must safely kill all candidates despite swap-removal.")
	_expect(combat.total_kills == 2 and combat.total_credits == data.credit_value * 2, "Kills and rewards must aggregate exactly once.")
	_expect(not combat.apply_damage(b, 50), "Stale handles must not grant a second reward.")
	_expect(world.is_handle_valid(behind), "Out-of-range enemies must survive.")
	combat.rebuild_grid()
	world.recycle(behind)
	var fresh := world.request_spawn(data, Vector3(500, 0, 0))
	_expect(combat.find_target(Vector3.ZERO, 600, Vector2.RIGHT, 45) == fresh, "Grid must rebuild after same-count recycle/spawn.")
	_clean()


func _test_swept_projectile() -> void:
	_setup()
	var data := _data()
	data.movement_speed = 0 # World snapshots retain earlier data; use no simulation before swept damage.
	var nearest := world.request_spawn(data, Vector3(100, 0, 0))
	var farther := world.request_spawn(data, Vector3(200, 0, 0))
	_expect(combat.damage_line(Vector3.ZERO, Vector3(400, 0, 0), 1, 50, true) == 1, "Swept projectile must hit only its first enemy.")
	_expect(not world.is_handle_valid(nearest) and world.is_handle_valid(farther), "Nearest intersection must win.")
	combat.set_obstacles([{"id": 9, "center": Vector2(150, 0), "half_size": Vector2(5, 20), "yaw": 0.4, "hp": 100.0}])
	_expect(combat.first_obstacle_hit(Vector3(300, 0, 0), Vector3.ZERO, 2) == 0, "Sweeps must catch a thin rotated barrier.")
	combat.fire_projectile(Vector3(300, 0, 0), Vector3.LEFT, 4, 1000, 2, DamageSystem.Team.ENEMY)
	combat._update_projectiles(0.5)
	_expect(combat.shot_count == 0 and combat.total_planet_damage == 0, "Barrier must intercept projectile before the planet.")
	_clean()


func _test_render_batches() -> void:
	_setup()
	var data := _data(true)
	var handle := world.request_spawn(data, Vector3(100, 0, 200))
	var renderer := EnemyMultiMeshRenderer.new()
	renderer.enemy_world = world
	renderer.use_gpu_transforms = false
	add_child(renderer)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	renderer.update_visuals()
	_expect(renderer.batches.size() == 2, "Ship body and engine must each retain their mesh batch.")
	var allocation_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_expect(allocation_nodes - nodes_before == 2, "Only the two shared mesh batches may enter the tree.")
	for batch in renderer.batches:
		var expected := Transform3D(Basis.IDENTITY, Vector3(100, 0, 200)) * batch.local_transform
		_expect(is_equal_approx(batch.buffer[3], expected.origin.x) and is_equal_approx(batch.buffer[11], expected.origin.z), "Local mesh offsets must survive bulk buffer packing.")
	for i in range(20):
		world.request_spawn(data, Vector3(i, 0, i))
	renderer.update_visuals()
	_expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == allocation_nodes, "More enemies cannot create more render Nodes.")
	world.recycle(handle)
	world.reset_world()
	renderer.update_visuals()
	for batch in renderer.batches:
		_expect(batch.mesh_instance.multimesh.visible_instance_count == 0, "Inactive slots must not render.")
	renderer.free()
	_clean()


func _test_projectile_validation_and_capacity() -> void:
	_setup()
	_expect(not combat.fire_projectile(Vector3.ZERO, Vector3.UP, 1, 1, 1, DamageSystem.Team.ALLY), "A vertical-only projectile has no planar direction.")
	_expect(not combat.fire_projectile(Vector3.ZERO, Vector3.RIGHT, NAN, 1, 1, DamageSystem.Team.ALLY), "Projectile damage must be finite.")
	for i in range(combat.projectile_capacity):
		_expect(combat.fire_projectile(Vector3.ZERO, Vector3.RIGHT, 1, 1, 1, DamageSystem.Team.ALLY), "Available projectile slots must accept shots.")
	_expect(not combat.fire_projectile(Vector3.ZERO, Vector3.RIGHT, 1, 1, 1, DamageSystem.Team.ALLY), "A full projectile pool must reject without replacing live shots.")
	_expect(combat.shot_count == combat.projectile_capacity and combat.dropped_projectiles == 1, "Projectile count must respect capacity.")
	combat.reset_combat()
	_expect(combat.shot_count == 0, "Reset must release all projectile slots.")
	_clean()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
