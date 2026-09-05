extends EnemyCombat
class_name EnemyGPUCombat

## Authoritative GPU simulation. EnemyWorld owns allocations; its positions/HP
## are snapshots only. Public damage methods return command acceptance, not hits.
signal diagnostic_ready(bytes: PackedByteArray)
@export_range(1, 30) var report_interval: int = 3
var backend: EnemyGPUBackend
var epoch: int = 1
var backend_error: String = ""
var separation_enabled: bool = false
var separation_speed: float = 120.0
var separation_padding: float = 2.0
var reports_received: int = 0
var report_backlog_events: int = 0
var readback_bytes: int = 0
var _commands: Array[PackedByteArray] = []
var _reports: Array = []
var _query_by_key: Dictionary = {}
var _queries: Array[PackedByteArray] = []
var _query_handles := PackedInt64Array()
var _obstacle_by_id: Dictionary = {}
var _obstacle_ids: Array[int] = []
var _obstacle_ack := PackedFloat32Array()
var _planet_ack: float = 0.0
var _archetype_bytes := PackedByteArray()
var _catalog_count: int = -1


func _ready() -> void:
	super._ready()
	backend = EnemyGPUBackend.new()
	backend.report_ready.connect(_receive_report, CONNECT_DEFERRED)
	backend.diagnostic_ready.connect(_receive_diagnostic, CONNECT_DEFERRED)
	backend.failed.connect(_receive_failure, CONNECT_DEFERRED)
	enemy_world.record_gpu_changes = true
	_obstacle_ack.resize(EnemyGPUBackend.MAX_OBSTACLES)
	# Also support attaching the consumer to a freshly populated CPU World.
	for i in range(enemy_world.get_active_count()):
		var slot := enemy_world.get_active_slot(i)
		enemy_world.gpu_changes.append([1, slot, enemy_world._generations[slot], enemy_world.archetype_indices[slot],
			enemy_world.positions[slot], enemy_world.health[slot], enemy_world.states[slot], enemy_world.headings[slot]])


func _exit_tree() -> void:
	if is_instance_valid(enemy_world):
		enemy_world.record_gpu_changes = false
		enemy_world.gpu_changes.clear()
	if backend != null:
		RenderingServer.call_on_render_thread(backend.release)


func reset_combat() -> void:
	# Authoritative state cannot be reconstructed from the targeting snapshots.
	# A session reset clears allocations together with GPU state.
	if is_instance_valid(enemy_world):
		enemy_world.reset_world()
		enemy_world.gpu_changes.clear()
	super.reset_combat()
	epoch += 1
	_commands.clear()
	_reports.clear()
	_queries.clear()
	_query_by_key.clear()
	_query_handles.clear()
	_obstacle_by_id.clear()
	_obstacle_ids.clear()
	_obstacle_ack.fill(0)
	_planet_ack = 0
	reports_received = 0
	report_backlog_events = 0
	if backend != null:
		RenderingServer.call_on_render_thread(backend.reset.bind(epoch))


func step(delta: float) -> void:
	if backend == null or not backend_error.is_empty() or not is_finite(delta) or delta < 0:
		return
	if (is_inside_tree() and get_tree().paused) or (respect_game_state and GameManager.current_state != GameManager.GameState.PLAYING):
		return
	var started := Time.get_ticks_usec()
	_consume_reports()
	_update_catalog()
	if not backend_error.is_empty():
		return
	var command_bytes := PackedByteArray()
	var consumed := mini(enemy_world.gpu_changes.size(), EnemyGPUBackend.MAX_COMMANDS)
	for i in range(consumed):
		var change: Array = enemy_world.gpu_changes[i]
		var command := _command(change[0])
		command.encode_u32(4, change[1])
		command.encode_u32(8, change[2])
		if change[0] == 1:
			command.encode_u32(12, change[3])
			_vector(command, 16, change[4])
			command.encode_float(28, change[7])
			command.encode_float(32, change[5])
			command.encode_float(36, change[6])
		command_bytes.append_array(command)
	if consumed > 0:
		enemy_world.gpu_changes = enemy_world.gpu_changes.slice(consumed)
	var attacks := mini(_commands.size(), EnemyGPUBackend.MAX_COMMANDS - consumed)
	for i in range(attacks):
		command_bytes.append_array(_commands[i])
	if attacks > 0:
		_commands = _commands.slice(attacks)
	var obstacle_bytes := _pack_obstacles()
	if not backend_error.is_empty():
		return
	var query_bytes := PackedByteArray()
	for query in _queries:
		query_bytes.append_array(query)
	simulation_time += delta
	var packet := {"capacity": enemy_world.capacity, "shot_capacity": projectile_capacity, "epoch": epoch,
		"archetypes": _archetype_bytes, "obstacles": obstacle_bytes, "queries": query_bytes, "commands": command_bytes,
		"command_count": consumed + attacks, "obstacle_count": _obstacle_ids.size(), "query_count": _queries.size(),
		"cell_size": cell_size, "planet": planet_position, "planet_radius": planet_radius,
		"delta": delta, "max_radius": _max_radius, "report_interval": report_interval, "force_report": delta == 0.0}
	packet["separation"] = separation_enabled
	packet["separation_speed"] = separation_speed
	packet["separation_padding"] = separation_padding
	if separation_enabled:
		# Interaction radius fits the current cell and its eight neighbors.
		packet["cell_size"] = maxf(cell_size, _max_radius * 2.0 + separation_padding)
	RenderingServer.call_on_render_thread(backend.advance.bind(packet))
	last_simulation_ms = (Time.get_ticks_usec() - started) / 1000.0


func _update_catalog() -> void:
	if _catalog_count == enemy_world.get_archetype_count():
		return
	_catalog_count = enemy_world.get_archetype_count()
	if _catalog_count > EnemyGPUBackend.MAX_ARCHETYPES:
		_receive_failure("GPU archetype capacity exceeded (%d)." % EnemyGPUBackend.MAX_ARCHETYPES)
		return
	_archetype_bytes.resize(maxi(1, _catalog_count) * 48)
	_max_radius = 0
	for i in range(_catalog_count):
		var data := enemy_world.get_archetype(i)
		var offset := i * 48
		var values := [data.max_hp, data.damage, data.radius, data.movement_speed,
			data.attack_interval, data.attack_range, data.projectile_speed, data.rotation_speed]
		for n in range(8):
			_archetype_bytes.encode_float(offset + n * 4, values[n])
		_archetype_bytes.encode_u32(offset + 32, data.behavior)
		_archetype_bytes.encode_u32(
			offset + 36,
			int(data.tumble_visual)
			| (2 if not data.planet_contact_includes_radius else 0)
			| (4 if data.face_planet else 0)
		)
		_archetype_bytes.encode_float(offset + 40, data.hit_slow_duration)
		_archetype_bytes.encode_float(offset + 44, data.hit_speed_factor)
		_max_radius = maxf(_max_radius, data.radius)


func _pack_obstacles() -> PackedByteArray:
	for obstacle in _obstacles:
		var id := int(obstacle.id)
		if not _obstacle_by_id.has(id):
			if _obstacle_ids.size() >= EnemyGPUBackend.MAX_OBSTACLES:
				_receive_failure("GPU obstacle capacity exceeded (%d)." % EnemyGPUBackend.MAX_OBSTACLES)
				return PackedByteArray()
			_obstacle_by_id[id] = _obstacle_ids.size()
			_obstacle_ids.append(id)
	var bytes := PackedByteArray()
	bytes.resize(maxi(1, _obstacle_ids.size()) * 48)
	for obstacle in _obstacles:
		var index: int = _obstacle_by_id[int(obstacle.id)]
		var offset := index * 48
		bytes.encode_float(offset, obstacle.center.x)
		bytes.encode_float(offset + 4, obstacle.center.y)
		bytes.encode_float(offset + 8, obstacle.half_size.x)
		bytes.encode_float(offset + 12, obstacle.half_size.y)
		bytes.encode_float(offset + 16, obstacle.yaw)
		bytes.encode_float(offset + 20, obstacle.hp)
		bytes.encode_float(offset + 24, _obstacle_ack[index])
		bytes.encode_u32(offset + 32, index + 1)
	return bytes


func _receive_report(bytes: PackedByteArray, report_epoch: int) -> void:
	if report_epoch == epoch:
		_reports.append(bytes)


func _consume_reports() -> void:
	for bytes: PackedByteArray in _reports:
		reports_received += 1
		readback_bytes += bytes.size()
		var count := bytes.decode_u32(0)
		report_backlog_events = maxi(0, count - EnemyGPUBackend.MAX_EVENTS)
		for i in range(mini(count, EnemyGPUBackend.MAX_EVENTS)):
			var offset := EnemyGPUBackend.EVENT_OFFSET + i * 32
			var slot := bytes.decode_u32(offset)
			var generation := bytes.decode_u32(offset + 4)
			var handle := (generation << 32) | slot
			if not enemy_world.is_handle_valid(handle):
				continue
			var reason := bytes.decode_u32(offset + 8)
			var data := enemy_world.get_archetype(bytes.decode_u32(offset + 12))
			if reason == 1:
				_feedback.append({"kind": "death", "position": Vector3(bytes.decode_float(offset + 16), bytes.decode_float(offset + 20), bytes.decode_float(offset + 24)), "archetype": bytes.decode_u32(offset + 12)})
				_kills += 1
				total_kills += 1
				_credits += data.credit_value
				total_credits += data.credit_value
			elif reason == 2:
				_feedback.append({"kind": "impact", "position": Vector3(bytes.decode_float(offset + 16), bytes.decode_float(offset + 20), bytes.decode_float(offset + 24))})
				_escaped += 1
				total_escaped += 1
			enemy_world.recycle(handle)
		var planet_total := bytes.decode_float(4)
		_planet_damage += maxf(0, planet_total - _planet_ack)
		total_planet_damage = planet_total
		_planet_ack = planet_total
		dropped_projectiles = bytes.decode_u32(8)
		shot_count = bytes.decode_u32(12)
		var feedback_count := bytes.decode_u32(EnemyGPUBackend.FEEDBACK_OFFSET)
		dropped_feedback += maxi(0, feedback_count - EnemyGPUBackend.MAX_FEEDBACK)
		for i in range(mini(feedback_count, EnemyGPUBackend.MAX_FEEDBACK)):
			var offset := EnemyGPUBackend.FEEDBACK_OFFSET + 16 + i * 32
			var handle := (bytes.decode_u32(offset + 4) << 32) | bytes.decode_u32(offset)
			# Death popups remain valid, but recycled/reused slots cannot update HP snapshots.
			_feedback.append({"kind": "hit", "position": Vector3(bytes.decode_float(offset + 8), bytes.decode_float(offset + 12), bytes.decode_float(offset + 16)), "damage": bytes.decode_float(offset + 20), "hp": bytes.decode_float(offset + 24)})
			if enemy_world.is_handle_valid(handle):
				enemy_world.health[handle & EnemyWorld.SLOT_MASK] = bytes.decode_float(offset + 24)
		for i in range(_obstacle_ids.size()):
			var accumulated := bytes.decode_float(16 + i * 4)
			var damage := maxf(0, accumulated - _obstacle_ack[i])
			_obstacle_ack[i] = accumulated
			if damage > 0:
				var id := _obstacle_ids[i]
				_obstacle_damage[id] = float(_obstacle_damage.get(id, 0)) + damage
				# Keep the sandbox snapshot in sync. Production replaces it from scene HP.
				for obstacle in _obstacles:
					if int(obstacle.id) == id:
						obstacle.hp = maxf(0, float(obstacle.hp) - damage)
		for i in range(_queries.size()):
			var offset := EnemyGPUBackend.QUERY_OFFSET + i * 32
			var handle := (bytes.decode_u32(offset + 4) << 32) | bytes.decode_u32(offset)
			_query_handles[i] = -1
			if bytes.decode_u32(offset + 8) != 0 and enemy_world.is_handle_valid(handle):
				_query_handles[i] = handle
				var slot := handle & EnemyWorld.SLOT_MASK
				enemy_world.positions[slot] = Vector3(bytes.decode_float(offset + 16), bytes.decode_float(offset + 20), bytes.decode_float(offset + 24))
				enemy_world.health[slot] = bytes.decode_float(offset + 28)
				enemy_world.states[slot] = bytes.decode_u32(offset + 12)
	_reports.clear()


func find_target(origin: Vector3, attack_range: float, forward: Vector2, cone_degrees: float) -> int:
	# Static mounts have stable query keys; handles/positions return asynchronously.
	var key := "%s|%s|%s|%s" % [origin, attack_range, forward, cone_degrees]
	if not _query_by_key.has(key):
		if _queries.size() >= EnemyGPUBackend.MAX_QUERIES:
			return -1
		var query := PackedByteArray()
		query.resize(48)
		query.encode_float(0, origin.x)
		query.encode_float(4, origin.z)
		query.encode_float(8, attack_range)
		query.encode_float(16, forward.normalized().x)
		query.encode_float(20, forward.normalized().y)
		query.encode_float(24, cos(deg_to_rad(cone_degrees * 0.5)))
		query.encode_u32(32, 1)
		_query_by_key[key] = _queries.size()
		_queries.append(query)
		_query_handles.append(-1)
	var handle := _query_handles[int(_query_by_key[key])]
	return handle if enemy_world.is_handle_valid(handle) else -1


func apply_damage(handle: int, amount: float, team: int = DamageSystem.Team.ALLY) -> bool:
	if team != DamageSystem.Team.ALLY or not _valid_damage(amount) or not enemy_world.is_handle_valid(handle):
		return false
	var command := _command(3)
	command.encode_u32(4, handle & EnemyWorld.SLOT_MASK)
	command.encode_u32(8, handle >> 32)
	command.encode_float(16, amount)
	return _enqueue(command)


func damage_circle(center: Vector3, radius: float, damage: float) -> int:
	if not center.is_finite() or not is_finite(radius) or radius < 0 or not _valid_damage(damage):
		return 0
	var command := _command(4)
	_vector(command, 16, center)
	command.encode_float(28, radius)
	command.encode_float(44, damage)
	return int(_enqueue(command))


func damage_line(start: Vector3, end: Vector3, width: float, damage: float, first_only: bool = false) -> int:
	if not start.is_finite() or not end.is_finite() or not is_finite(width) or width < 0 or not _valid_damage(damage):
		return 0
	var command := _command(5)
	_vector(command, 16, start)
	_vector(command, 32, end)
	command.encode_float(28, width)
	command.encode_float(44, damage)
	command.encode_float(48, float(first_only))
	return int(_enqueue(command))


func fire_projectile(origin: Vector3, direction: Vector3, damage: float, speed: float, lifetime: float, team: int) -> bool:
	return fire_projectile_with_radius(origin, direction, damage, speed, lifetime, team, 3.0)


func fire_projectile_with_radius(origin: Vector3, direction: Vector3, damage: float, speed: float, lifetime: float, team: int, radius: float, pierce: int = 0, kind: int = 0) -> bool:
	if not origin.is_finite() or not direction.is_finite() or Vector2(direction.x, direction.z).is_zero_approx():
		return false
	if not is_finite(radius) or radius < 0 or pierce < 0 or pierce >= EnemyGPUBackend.MAX_PROJECTILE_HITS:
		return false
	if not _valid_damage(damage) or not is_finite(speed) or not is_finite(lifetime) or speed <= 0 or lifetime <= 0 or team not in [DamageSystem.Team.ALLY, DamageSystem.Team.ENEMY]:
		return false
	var command := _command(6)
	command.encode_u32(4, pierce)
	command.encode_u32(8, kind)
	_vector(command, 16, origin)
	_vector(command, 32, direction)
	command.encode_float(28, radius)
	command.encode_float(44, damage)
	command.encode_float(48, speed)
	command.encode_float(52, lifetime)
	command.encode_float(56, float(team))
	return _enqueue(command)


func _enqueue(command: PackedByteArray) -> bool:
	if _commands.size() >= EnemyGPUBackend.MAX_COMMANDS * 2 or not backend_error.is_empty():
		return false
	_commands.append(command)
	return true


static func _command(op: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(64)
	bytes.encode_u32(0, op)
	return bytes


static func _vector(bytes: PackedByteArray, offset: int, value: Vector3) -> void:
	bytes.encode_float(offset, value.x)
	bytes.encode_float(offset + 4, value.y)
	bytes.encode_float(offset + 8, value.z)


static func _valid_damage(value: float) -> bool:
	return is_finite(value) and value > 0


func request_diagnostic() -> void:
	RenderingServer.call_on_render_thread(backend.read_diagnostic)


func _receive_diagnostic(bytes: PackedByteArray, report_epoch: int) -> void:
	if report_epoch == epoch:
		diagnostic_ready.emit(bytes)


func _receive_failure(message: String) -> void:
	backend_error = message
	push_error(message)
