extends Node
class_name EnemyCombat

## Reference simulation and combat. XZ gameplay, 3D presentation.
signal combat_events(kills: int, escaped: int, credits: float, planet_damage: float, obstacle_damage: Dictionary)
signal feedback_events(events: Array)
var _feedback: Array = []
var _hit_feedback_count: int = 0
var dropped_feedback: int = 0
@export var enemy_world: EnemyWorld
@export var simulation_enabled: bool = true
@export var respect_game_state: bool = true
@export var planet_radius: float = 45.0
@export_range(1.0, 1024.0) var cell_size: float = 128.0
@export var projectile_capacity: int = 4096
var planet_position := Vector3.ZERO
var last_simulation_ms: float = 0.0
var simulation_time: float = 0.0
var total_kills: int = 0
var total_escaped: int = 0
var total_credits: float = 0.0
var total_planet_damage: float = 0.0
var dropped_projectiles: int = 0

var _heads: Dictionary = {}
var _next := PackedInt32Array()
var _grid_dirty: bool = true
var _grid_count: int = -1
var _grid_revision: int = -1
var _max_radius: float = 0.0
var _obstacles: Array[Dictionary] = []
var _contact := PackedInt64Array()
var _contact_generation := PackedInt64Array()
var _kills: int = 0
var _escaped: int = 0
var _credits: float = 0.0
var _planet_damage: float = 0.0
var _obstacle_damage: Dictionary = {}

var shot_positions := PackedVector3Array()
var shot_directions := PackedVector3Array()
var shot_damage := PackedFloat32Array()
var shot_speeds := PackedFloat32Array()
var shot_lifetimes := PackedFloat32Array()
var shot_teams := PackedInt32Array()
var shot_radii := PackedFloat32Array()
var shot_pierce := PackedInt32Array()
var shot_kinds := PackedInt32Array()
var shot_hits: Array[Dictionary] = []
var shot_count: int = 0


func _ready() -> void:
	process_physics_priority = 10
	prepare()


func prepare() -> void:
	if not is_instance_valid(enemy_world):
		return
	if not is_finite(cell_size) or cell_size < 1.0:
		cell_size = 128.0
	enemy_world.initialize()
	if _next.size() != enemy_world.positions.size():
		_next.resize(enemy_world.positions.size())
		_contact.resize(enemy_world.positions.size())
		_contact_generation.resize(enemy_world.positions.size())
		_contact.fill(-1)
	if shot_positions.is_empty():
		var size := maxi(1, projectile_capacity)
		shot_positions.resize(size)
		shot_directions.resize(size)
		shot_damage.resize(size)
		shot_speeds.resize(size)
		shot_lifetimes.resize(size)
		shot_teams.resize(size)
		shot_radii.resize(size)
		shot_pierce.resize(size)
		shot_kinds.resize(size)
		shot_hits.resize(size)


## IDs are stable scene-instance IDs; existing enemies never retain array indices.
## Each entry: id, center(Vector2), half_size(Vector2), yaw, hp.
func set_obstacles(obstacles: Array[Dictionary]) -> void:
	_obstacles = obstacles.duplicate(true)


func reset_combat() -> void:
	_feedback.clear()
	_hit_feedback_count = 0
	dropped_feedback = 0
	shot_count = 0
	_kills = 0
	_escaped = 0
	_credits = 0
	_planet_damage = 0
	_obstacle_damage.clear()
	_contact.fill(-1)
	_heads.clear()
	_grid_dirty = true
	total_kills = 0
	total_escaped = 0
	total_credits = 0
	total_planet_damage = 0
	simulation_time = 0
	dropped_projectiles = 0


func _physics_process(delta: float) -> void:
	if not simulation_enabled or (respect_game_state and GameManager.current_state != GameManager.GameState.PLAYING):
		return
	step(delta)
	flush_combat_events()


func step(delta: float) -> void:
	if not is_instance_valid(enemy_world) or not is_finite(delta) or delta <= 0:
		return
	if is_inside_tree() and get_tree().paused:
		return
	if respect_game_state and GameManager.current_state != GameManager.GameState.PLAYING:
		return
	prepare()
	var start := Time.get_ticks_usec()
	simulation_time += delta
	# Backwards traversal tolerates swap-removal during planet impacts.
	for index in range(enemy_world.get_active_count() - 1, -1, -1):
		var slot := enemy_world.get_active_slot(index)
		var data := enemy_world.get_archetype(enemy_world.archetype_indices[slot])
		if data.behavior == EnemyData.BehaviorType.ASTEROID:
			_move_asteroid(slot, data, delta)
		else:
			_move_ship(slot, data, delta)
	_grid_dirty = true
	rebuild_grid()
	_update_projectiles(delta)
	last_simulation_ms = (Time.get_ticks_usec() - start) / 1000.0


func _move_asteroid(slot: int, data: EnemyData, delta: float) -> void:
	if _contact_generation[slot] != enemy_world._generations[slot]:
		_contact[slot] = -1
		_contact_generation[slot] = enemy_world._generations[slot]
	var origin := enemy_world.positions[slot]
	var direction := (planet_position - origin).normalized()
	var planar := Vector2(origin.x, origin.z)
	# Local obstacle avoidance uses enclosing circles; contact uses swept OBBs.
	for obstacle in _obstacles:
		if obstacle.hp <= 0:
			continue
		var offset: Vector2 = planar - obstacle.center
		var safe: float = obstacle.half_size.length() + data.radius + 8.0
		if offset.length_squared() < (safe + 60.0) * (safe + 60.0) and offset.dot(Vector2(direction.x, direction.z)) < 0:
			var radial := offset.normalized()
			var side := 1.0 if slot % 2 == 0 else -1.0
			var tangent := Vector2(-radial.y, radial.x) * side
			var desired := (tangent + radial * maxf(0.0, (safe - offset.length()) / 20.0)).normalized()
			direction = Vector3(desired.x, 0, desired.y)
			break
	var speed := data.movement_speed
	if simulation_time - delta - enemy_world.hit_times[slot] < data.hit_slow_duration:
		speed *= data.hit_speed_factor
	var destination := origin + direction * speed * delta
	var hit := first_obstacle_hit(origin, destination, data.radius)
	if hit >= 0:
		var obstacle: Dictionary = _obstacles[hit]
		if _contact[slot] != int(obstacle.id):
			_damage_obstacle(hit, data.damage)
		_contact[slot] = obstacle.id
		destination = origin
	else:
		_contact[slot] = -1
	enemy_world.velocities[slot] = direction * speed
	enemy_world.positions[slot] = destination
	if data.face_planet:
		var facing := planet_position - destination
		if facing.length_squared() > 0.000001:
			enemy_world.headings[slot] = atan2(facing.x, facing.z)
	else:
		enemy_world.headings[slot] += data.rotation_speed * delta
	var impact_radius := planet_radius + (data.radius if data.planet_contact_includes_radius else 0.0)
	if segment_circle_fraction(origin, destination, planet_position, impact_radius) >= 0:
		_planet_damage += data.damage
		total_planet_damage += data.damage
		_escaped += 1
		total_escaped += 1
		_feedback.append({"kind": "impact", "position": enemy_world.positions[slot]})
		enemy_world.recycle(_handle(slot))


func _move_ship(slot: int, data: EnemyData, delta: float) -> void:
	var position_3d := enemy_world.positions[slot]
	var target_index := -1
	var target_id := enemy_world.target_handles[slot]
	for i in range(_obstacles.size()):
		if _obstacles[i].id == target_id and _obstacles[i].hp > 0:
			target_index = i
			break
	var state := enemy_world.states[slot]
	if state == EnemyWorld.State.APPROACH_BARRIER and target_index < 0:
		var nearest := INF
		for i in range(_obstacles.size()):
			if _obstacles[i].hp <= 0:
				continue
			var distance := Vector2(position_3d.x, position_3d.z).distance_squared_to(_obstacles[i].center)
			if distance < nearest:
				nearest = distance
				target_index = i
		if target_index >= 0:
			enemy_world.target_handles[slot] = _obstacles[target_index].id
		else:
			state = EnemyWorld.State.MOVING
	if state == EnemyWorld.State.ATTACK_BARRIER and target_index < 0:
		state = EnemyWorld.State.ROTATE_TO_PLANET
		enemy_world.target_handles[slot] = -1
	var target := planet_position
	var target_radius := planet_radius
	if target_index >= 0 and state in [EnemyWorld.State.APPROACH_BARRIER, EnemyWorld.State.ATTACK_BARRIER]:
		var center: Vector2 = _obstacles[target_index].center
		target = Vector3(center.x, 0, center.y)
		target_radius = _obstacles[target_index].half_size.length()
	var offset := target - position_3d
	var desired_heading := atan2(offset.x, offset.z)
	enemy_world.headings[slot] = rotate_toward(enemy_world.headings[slot], desired_heading, data.rotation_speed * delta)
	enemy_world.velocities[slot] = Vector3.ZERO
	if state in [EnemyWorld.State.MOVING, EnemyWorld.State.APPROACH_BARRIER]:
		var remaining := maxf(0.0, offset.length() - data.attack_range - target_radius - data.radius)
		var movement := offset.normalized() * minf(remaining, data.movement_speed * delta)
		enemy_world.positions[slot] += movement
		enemy_world.velocities[slot] = movement / delta
		if remaining <= data.movement_speed * delta:
			state = EnemyWorld.State.ATTACK_BARRIER if target_index >= 0 else EnemyWorld.State.ROTATE_TO_PLANET
	if state == EnemyWorld.State.ROTATE_TO_PLANET and absf(angle_difference(enemy_world.headings[slot], desired_heading)) < 0.02:
		state = EnemyWorld.State.ATTACK_PLANET
	if state in [EnemyWorld.State.ATTACK_BARRIER, EnemyWorld.State.ATTACK_PLANET]:
		enemy_world.attack_timers[slot] -= delta
		if enemy_world.attack_timers[slot] <= 0 and absf(angle_difference(enemy_world.headings[slot], desired_heading)) < 0.1:
			var direction := (target - enemy_world.positions[slot]).normalized()
			var accepted := fire_projectile(enemy_world.positions[slot], direction, data.damage, data.projectile_speed, 20.0, DamageSystem.Team.ENEMY)
			if accepted:
				enemy_world.attack_timers[slot] += data.attack_interval
	enemy_world.states[slot] = state


func rebuild_grid() -> void:
	prepare()
	_heads.clear()
	_max_radius = 0
	for i in range(enemy_world.get_archetype_count()):
		_max_radius = maxf(_max_radius, enemy_world.get_archetype(i).radius)
	for i in range(enemy_world.get_active_count()):
		var slot := enemy_world.get_active_slot(i)
		var position_3d := enemy_world.positions[slot]
		var cell := Vector2i(floori(position_3d.x / cell_size), floori(position_3d.z / cell_size))
		_next[slot] = int(_heads.get(cell, -1))
		_heads[cell] = slot
	_grid_count = enemy_world.get_active_count()
	_grid_revision = enemy_world.mutation_revision
	_grid_dirty = false


func _query_bounds(minimum: Vector2, maximum: Vector2) -> PackedInt64Array:
	if _grid_dirty or _grid_revision != enemy_world.mutation_revision:
		rebuild_grid()
	var result := PackedInt64Array()
	var low := Vector2i(floori(minimum.x / cell_size), floori(minimum.y / cell_size))
	var high := Vector2i(floori(maximum.x / cell_size), floori(maximum.y / cell_size))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var slot: int = _heads.get(Vector2i(x, y), -1)
			while slot >= 0:
				result.append(_handle(slot))
				slot = _next[slot]
	return result


func find_target(origin: Vector3, attack_range: float, forward: Vector2, cone_degrees: float) -> int:
	var point := Vector2(origin.x, origin.z)
	var best := -1
	var nearest := attack_range * attack_range
	var dot_limit := cos(deg_to_rad(cone_degrees * 0.5))
	for handle in _query_bounds(point - Vector2.ONE * attack_range, point + Vector2.ONE * attack_range):
		if not enemy_world.is_handle_valid(handle):
			continue
		var delta := enemy_world.positions[handle & EnemyWorld.SLOT_MASK] - origin
		var offset := Vector2(delta.x, delta.z)
		var distance := offset.length_squared()
		if distance <= nearest and (offset.is_zero_approx() or offset.normalized().dot(forward.normalized()) >= dot_limit):
			best = handle
			nearest = distance
	return best


func apply_damage(handle: int, amount: float, team: int = DamageSystem.Team.ALLY) -> bool:
	if team != DamageSystem.Team.ALLY or not is_finite(amount) or amount <= 0 or not enemy_world.is_handle_valid(handle):
		return false
	var slot := handle & EnemyWorld.SLOT_MASK
	enemy_world.health[slot] -= amount
	enemy_world.hit_times[slot] = simulation_time
	if _hit_feedback_count < 128:
		_feedback.append({"kind": "hit", "position": enemy_world.positions[slot], "damage": amount, "hp": maxf(0, enemy_world.health[slot])})
		_hit_feedback_count += 1
	else:
		dropped_feedback += 1
	if enemy_world.health[slot] <= 0:
		_feedback.append({"kind": "death", "position": enemy_world.positions[slot], "archetype": enemy_world.archetype_indices[slot]})
		var credits := enemy_world.get_archetype(enemy_world.archetype_indices[slot]).credit_value
		_kills += 1
		total_kills += 1
		_credits += credits
		total_credits += credits
		enemy_world.recycle(handle)
		_grid_dirty = true
	return true


func damage_circle(center: Vector3, radius: float, damage: float) -> int:
	var point := Vector2(center.x, center.z)
	# Ensure radius is current even when new archetypes have just been registered.
	if _grid_dirty or _grid_revision != enemy_world.mutation_revision:
		rebuild_grid()
	var extent := Vector2.ONE * (radius + _max_radius)
	var hits := 0
	for handle in _query_bounds(point - extent, point + extent):
		if not enemy_world.is_handle_valid(handle):
			continue
		var slot := handle & EnemyWorld.SLOT_MASK
		var data := enemy_world.get_archetype(enemy_world.archetype_indices[slot])
		var offset := enemy_world.positions[slot] - center
		if Vector2(offset.x, offset.z).length_squared() <= pow(radius + data.radius, 2):
			if apply_damage(handle, damage):
				hits += 1
	return hits


func damage_line(start: Vector3, end: Vector3, width: float, damage: float, first_only: bool = false) -> int:
	if _grid_dirty or _grid_revision != enemy_world.mutation_revision:
		rebuild_grid()
	var extent := Vector2.ONE * (width + _max_radius)
	var low := Vector2(minf(start.x, end.x), minf(start.z, end.z)) - extent
	var high := Vector2(maxf(start.x, end.x), maxf(start.z, end.z)) + extent
	var nearest := INF
	var nearest_handle := -1
	var hits := 0
	for handle in _query_bounds(low, high):
		if not enemy_world.is_handle_valid(handle):
			continue
		var slot := handle & EnemyWorld.SLOT_MASK
		var data := enemy_world.get_archetype(enemy_world.archetype_indices[slot])
		var fraction := segment_circle_fraction(start, end, enemy_world.positions[slot], width + data.radius)
		if fraction < 0:
			continue
		if first_only:
			if fraction < nearest:
				nearest = fraction
				nearest_handle = handle
		elif apply_damage(handle, damage):
			hits += 1
	if first_only and apply_damage(nearest_handle, damage):
		hits = 1
	return hits


func fire_projectile(origin: Vector3, direction: Vector3, damage: float, speed: float, lifetime: float, team: int) -> bool:
	return fire_projectile_with_radius(origin, direction, damage, speed, lifetime, team, 3.0)


func fire_debris(origin: Vector3, direction: Vector3, damage: float, pierce: int) -> bool:
	return fire_projectile_with_radius(origin, direction, damage, 240, 3, DamageSystem.Team.ALLY, 20, pierce, 1)


func fire_projectile_with_radius(origin: Vector3, direction: Vector3, damage: float, speed: float, lifetime: float, team: int, radius: float, pierce: int = 0, kind: int = 0) -> bool:
	prepare()
	if not is_finite(radius) or radius < 0 or pierce < 0 or pierce > 15:
		return false
	if shot_count >= shot_positions.size():
		dropped_projectiles += 1
		return false
	if not origin.is_finite() or not direction.is_finite() or Vector2(direction.x, direction.z).is_zero_approx():
		return false
	if not is_finite(damage) or not is_finite(speed) or not is_finite(lifetime) or damage <= 0 or speed <= 0 or lifetime <= 0:
		return false
	if team not in [DamageSystem.Team.ALLY, DamageSystem.Team.ENEMY]:
		return false
	shot_positions[shot_count] = Vector3(origin.x, 0, origin.z)
	shot_directions[shot_count] = Vector3(direction.x, 0, direction.z).normalized()
	shot_damage[shot_count] = damage
	shot_speeds[shot_count] = speed
	shot_lifetimes[shot_count] = lifetime
	shot_teams[shot_count] = team
	shot_radii[shot_count] = radius
	shot_pierce[shot_count] = pierce
	shot_kinds[shot_count] = kind
	shot_hits[shot_count] = {}
	shot_count += 1
	return true


func _update_projectiles(delta: float) -> void:
	for i in range(shot_count - 1, -1, -1):
		var origin := shot_positions[i]
		var step_time := minf(delta, shot_lifetimes[i])
		var destination := origin + shot_directions[i] * shot_speeds[i] * step_time
		var hit := false
		if shot_teams[i] == DamageSystem.Team.ALLY:
			# Stable handle history prevents repeat damage while remaining inside a target.
			for attempt in range(shot_pierce[i] + 1):
				var nearest := 2.0
				var target := -1
				var extent := Vector2.ONE * (shot_radii[i] + _max_radius)
				for handle in _query_bounds(Vector2(minf(origin.x, destination.x), minf(origin.z, destination.z)) - extent, Vector2(maxf(origin.x, destination.x), maxf(origin.z, destination.z)) + extent):
					if shot_hits[i].has(handle) or not enemy_world.is_handle_valid(handle):
						continue
					var slot := handle & EnemyWorld.SLOT_MASK
					var enemy_radius := 0.0 if shot_kinds[i] == 1 else enemy_world.get_archetype(enemy_world.archetype_indices[slot]).radius
					var fraction := segment_circle_fraction(origin, destination, enemy_world.positions[slot], shot_radii[i] + enemy_radius)
					if fraction >= 0 and fraction < nearest:
						nearest = fraction
						target = handle
				if target < 0:
					break
				apply_damage(target, shot_damage[i])
				shot_hits[i][target] = true
				if shot_hits[i].size() > shot_pierce[i]:
					hit = true
					break
		else:
			var obstacle_index := first_obstacle_hit(origin, destination, 3.0)
			var planet_hit := segment_circle_fraction(origin, destination, planet_position, planet_radius + 3.0)
			if obstacle_index >= 0 and (planet_hit < 0 or obstacle_fraction(origin, destination, _obstacles[obstacle_index], 3.0) <= planet_hit):
				_damage_obstacle(obstacle_index, shot_damage[i])
				hit = true
			elif planet_hit >= 0:
				_planet_damage += shot_damage[i]
				total_planet_damage += shot_damage[i]
				hit = true
		shot_lifetimes[i] -= delta
		if hit or shot_lifetimes[i] <= 0:
			shot_count -= 1
			shot_positions[i] = shot_positions[shot_count]
			shot_directions[i] = shot_directions[shot_count]
			shot_damage[i] = shot_damage[shot_count]
			shot_speeds[i] = shot_speeds[shot_count]
			shot_lifetimes[i] = shot_lifetimes[shot_count]
			shot_teams[i] = shot_teams[shot_count]
			shot_radii[i] = shot_radii[shot_count]
			shot_pierce[i] = shot_pierce[shot_count]
			shot_kinds[i] = shot_kinds[shot_count]
			shot_hits[i] = shot_hits[shot_count]
		else:
			shot_positions[i] = destination


func first_obstacle_hit(start: Vector3, end: Vector3, radius: float) -> int:
	var best := -1
	var fraction := INF
	for i in range(_obstacles.size()):
		if _obstacles[i].hp <= 0:
			continue
		var hit := obstacle_fraction(start, end, _obstacles[i], radius)
		if hit >= 0 and hit < fraction:
			best = i
			fraction = hit
	return best


static func obstacle_fraction(start: Vector3, end: Vector3, obstacle: Dictionary, radius: float) -> float:
	var a := (Vector2(start.x, start.z) - Vector2(obstacle.center)).rotated(obstacle.yaw)
	var b := (Vector2(end.x, end.z) - Vector2(obstacle.center)).rotated(obstacle.yaw)
	var half := Vector2(obstacle.half_size) + Vector2.ONE * radius
	var direction := b - a
	var low := 0.0
	var high := 1.0
	for axis in range(2):
		if absf(direction[axis]) < 0.000001:
			if absf(a[axis]) > half[axis]:
				return -1.0
		else:
			var t1 := (-half[axis] - a[axis]) / direction[axis]
			var t2 := (half[axis] - a[axis]) / direction[axis]
			low = maxf(low, minf(t1, t2))
			high = minf(high, maxf(t1, t2))
			if low > high:
				return -1.0
	return low


static func segment_circle_fraction(start: Vector3, end: Vector3, center: Vector3, radius: float) -> float:
	var offset := Vector2(start.x - center.x, start.z - center.z)
	var d := Vector2(end.x - start.x, end.z - start.z)
	var c := offset.length_squared() - radius * radius
	if c <= 0:
		return 0
	var a := d.length_squared()
	if a < 0.000001:
		return -1
	var b := offset.dot(d)
	var discriminant := b * b - a * c
	if discriminant < 0:
		return -1
	var t := (-b - sqrt(discriminant)) / a
	return t if t >= 0 and t <= 1 else -1.0


func _handle(slot: int) -> int:
	return (enemy_world._generations[slot] << 32) | slot


func _damage_obstacle(index: int, damage: float) -> void:
	var obstacle: Dictionary = _obstacles[index]
	obstacle.hp = maxf(0.0, obstacle.hp - damage)
	_obstacle_damage[obstacle.id] = float(_obstacle_damage.get(obstacle.id, 0.0)) + damage


func flush_combat_events() -> void:
	if not _feedback.is_empty():
		var events := _feedback
		_feedback = []
		_hit_feedback_count = 0
		feedback_events.emit(events)
	if _kills == 0 and _escaped == 0 and _planet_damage == 0 and _obstacle_damage.is_empty():
		return
	var kills := _kills
	var escaped := _escaped
	var credits := _credits
	var planet_damage := _planet_damage
	var obstacle_damage := _obstacle_damage
	_kills = 0
	_escaped = 0
	_credits = 0
	_planet_damage = 0
	_obstacle_damage = {}
	combat_events.emit(kills, escaped, credits, planet_damage, obstacle_damage)
