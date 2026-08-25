extends SceneTree

const TurretConfigScript = preload("res://src/resources/turret_config.gd")

var _failures: int = 0

func _initialize() -> void:
	var config: TurretConfig = TurretConfigScript.new()
	_test_handle_mapping(config)
	_test_cone_query(config)
	if _failures == 0:
		print("Turret cone tests passed.")
	else:
		push_error("Turret cone tests failed: %d" % _failures)
	quit(_failures)

func _test_handle_mapping(config: TurretConfig) -> void:
	_expect(
		is_equal_approx(
			config.get_cone_angle_for_handle_distance(config.minimum_handle_distance),
			config.maximum_cone_angle
		),
		"A near handle must produce the widest action cone."
	)
	_expect(
		is_equal_approx(
			config.get_cone_angle_for_handle_distance(config.maximum_handle_distance),
			config.minimum_cone_angle
		),
		"A far handle must produce the narrowest action cone."
	)

func _test_cone_query(config: TurretConfig) -> void:
	config.attack_range = 100.0
	var forward := Vector2(0.0, 1.0)
	_expect(
		config.contains_offset_in_action_cone(Vector2(0.0, 90.0), forward, 90.0),
		"A target in front must be inside the action cone."
	)
	_expect(
		not config.contains_offset_in_action_cone(Vector2(90.0, 0.0), forward, 90.0),
		"A target outside the angle must be rejected."
	)
	_expect(
		not config.contains_offset_in_action_cone(Vector2(0.0, 101.0), forward, 90.0),
		"A target beyond range must be rejected."
	)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
