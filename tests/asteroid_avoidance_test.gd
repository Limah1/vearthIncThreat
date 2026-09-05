extends Node

const AvoidanceMathUtil = preload("res://src/core/avoidance_math.gd")
const DamageSystemScript = preload("res://src/core/damage_system.gd")
const AsteroidInstanceScript = preload("res://src/entities/instances/asteroid_instance.gd")
const LEVEL_ONE_PATH := "res://src/levels/Level1.tscn"
const BARRIER_CONFIG_PATH := "res://src/resources/barriers/BarrierConfig.tres"
const ASTEROID_RADIUS := 24.0
const CLEARANCE := 8.0
const LOOKAHEAD := 150.0
const TURN_SPEED := 6.5
const SPEED := 85.0
const DELTA := 1.0 / 60.0

var _failures: int = 0

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_segment_circle_query()
	_test_asteroid_damage_teams()
	_test_first_level_routes()
	if _failures == 0:
		print("Asteroid avoidance tests passed.")
	else:
		push_error("Asteroid avoidance tests failed: %d" % _failures)
	get_tree().quit(_failures)

func _test_segment_circle_query() -> void:
	_expect(
		AvoidanceMathUtil.segment_circle_hit_fraction(
			Vector2(-100.0, 0.0),
			Vector2(100.0, 0.0),
			Vector2.ZERO,
			20.0
		) >= 0.0,
		"A direct route must detect the obstacle."
	)
	_expect(
		AvoidanceMathUtil.segment_circle_hit_fraction(
			Vector2(-100.0, 50.0),
			Vector2(100.0, 50.0),
			Vector2.ZERO,
			20.0
		) < 0.0,
		"A clear route must not report an obstacle."
	)

func _test_asteroid_damage_teams() -> void:
	var asteroid: Node = AsteroidInstanceScript.new()
	add_child(asteroid)
	asteroid.set("active", true)
	asteroid.set("hp", 3.0)

	DamageSystemScript.apply(asteroid, 1.0, DamageSystemScript.Team.ENEMY)
	_expect(
		is_equal_approx(float(asteroid.get("hp")), 3.0),
		"ENEMY damage must not reduce asteroid HP."
	)
	DamageSystemScript.apply(asteroid, 1.0, DamageSystemScript.Team.NEUTRAL)
	_expect(
		is_equal_approx(float(asteroid.get("hp")), 3.0),
		"NEUTRAL damage must not reduce asteroid HP."
	)
	DamageSystemScript.apply(asteroid, 1.0, DamageSystemScript.Team.ALLY)
	_expect(
		is_equal_approx(float(asteroid.get("hp")), 2.0),
		"ALLY damage must reduce asteroid HP."
	)
	asteroid.free()

func _test_first_level_routes() -> void:
	var obstacle_centers: Array[Vector2] = _load_first_level_obstacle_centers()
	_expect(obstacle_centers.size() == 15, "Level 1 fixture must include all fifteen authored allied ships.")
	if obstacle_centers.is_empty():
		return

	var barrier_config := load(BARRIER_CONFIG_PATH) as BarrierConfig
	_expect(is_instance_valid(barrier_config), "BarrierConfig must load for the route test.")
	if not barrier_config:
		return
	var safe_radius: float = barrier_config.size.length() * 0.5 + ASTEROID_RADIUS + CLEARANCE

	# Match the first-level ring: fifty representative approaches toward the planet.
	for spawn_index in range(50):
		var angle: float = float(spawn_index) * TAU / 50.0
		var position := Vector2.from_angle(angle) * 725.0
		var direction: Vector2 = (-position).normalized()
		var active_obstacle: int = -1
		var avoidance_side: float = 0.0
		var query_timer: float = float(spawn_index % 17) / 17.0 * 0.1
		var reached_planet: bool = false

		for _step in range(1600):
			query_timer -= DELTA
			if active_obstacle < 0 and query_timer <= 0.0:
				query_timer = 0.1
				active_obstacle = _find_blocking_obstacle(
					position,
					position + direction * LOOKAHEAD,
					obstacle_centers,
					safe_radius
				)
				if active_obstacle >= 0:
					avoidance_side = AvoidanceMathUtil.choose_side(
						position,
						Vector2.ZERO,
						obstacle_centers[active_obstacle],
						spawn_index
					)

			if active_obstacle >= 0:
				var center: Vector2 = obstacle_centers[active_obstacle]
				var direct_path_clear: bool = AvoidanceMathUtil.segment_circle_hit_fraction(
					position,
					Vector2.ZERO,
					center,
					safe_radius
				) < 0.0
				if direct_path_clear and position.distance_to(center) > safe_radius + 4.0:
					active_obstacle = -1
					query_timer = 0.0
				else:
					var avoidance_direction: Vector2 = AvoidanceMathUtil.circle_avoidance_direction(
						position,
						Vector2.ZERO,
						center,
						safe_radius,
						avoidance_side
					)
					direction = direction.lerp(
						avoidance_direction,
						clampf(TURN_SPEED * DELTA, 0.0, 1.0)
					).normalized()

			if active_obstacle < 0:
				var planet_direction: Vector2 = (-position).normalized()
				direction = direction.lerp(
					planet_direction,
					clampf(TURN_SPEED * DELTA, 0.0, 1.0)
				).normalized()

			position += direction * SPEED * DELTA
			for center in obstacle_centers:
				if position.distance_to(center) < safe_radius:
					_expect(false, "Route %d entered an allied avoidance volume." % spawn_index)
					return
			if position.length() < 45.0:
				reached_planet = true
				break

		_expect(reached_planet, "Route %d must still reach the planet after avoiding allies." % spawn_index)

func _find_blocking_obstacle(
	segment_start: Vector2,
	segment_end: Vector2,
	centers: Array[Vector2],
	safe_radius: float
) -> int:
	var nearest_index: int = -1
	var nearest_fraction: float = INF
	for index in range(centers.size()):
		var hit_fraction: float = AvoidanceMathUtil.segment_circle_hit_fraction(
			segment_start,
			segment_end,
			centers[index],
			safe_radius
		)
		if hit_fraction >= 0.0 and hit_fraction < nearest_fraction:
			nearest_fraction = hit_fraction
			nearest_index = index
	return nearest_index

func _load_first_level_obstacle_centers() -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var level_scene := load(LEVEL_ONE_PATH) as PackedScene
	if not level_scene:
		return centers
	var state: SceneState = level_scene.get_state()
	for node_index in range(state.get_node_count()):
		var node_path: String = str(state.get_node_path(node_index))
		if not node_path.contains("AllyShips/BasicAllyShip_"):
			continue
		var position := Vector2.ZERO
		for property_index in range(state.get_node_property_count(node_index)):
			if state.get_node_property_name(node_index, property_index) == &"position":
				var property_value: Variant = state.get_node_property_value(node_index, property_index)
				if property_value is Vector2:
					position = property_value
				break
		centers.append(position)
	return centers

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
