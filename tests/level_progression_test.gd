extends Node

const ASTEROID_SCRIPT = preload("res://src/entities/instances/asteroid_instance.gd")
const FIRST_LEVEL_PATH := "res://src/resources/levels/FirstLevelConfig.tres"

var _failures: int = 0

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_asteroid_health_range()
	_test_level_selector_discovery()
	_test_sequential_level_unlock()
	if _failures == 0:
		print("Level progression tests passed.")
	else:
		push_error("Level progression tests failed: %d" % _failures)
	get_tree().quit(_failures)

func _test_asteroid_health_range() -> void:
	var asteroid: AsteroidInstance = ASTEROID_SCRIPT.new()
	for _sample in range(100):
		asteroid.set_asteroid_type("small")
		_expect(asteroid.max_hp >= 1.0 and asteroid.max_hp <= 5.0, "Asteroid HP must stay in the 1–5 range.")
		_expect(is_equal_approx(asteroid.hp, asteroid.max_hp), "Asteroid current HP must reset to its rolled maximum.")
	asteroid.free()

func _test_sequential_level_unlock() -> void:
	var config := load(FIRST_LEVEL_PATH) as LevelConfig
	_expect(is_instance_valid(config), "First level config must load.")
	if not config:
		return

	GameManager.selected_level_config = config
	GameManager.selected_level_config_path = FIRST_LEVEL_PATH
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.highest_unlocked_level = 1
	GameManager.completed_levels.clear()
	_expect(not GameManager.is_level_unlocked(2), "Level 2 must begin locked.")

	var total: int = config.get_total_configured_enemies()
	for _elimination in range(maxi(total - 1, 0)):
		GameManager.register_eliminated_threat()
	_expect(not GameManager.is_level_unlocked(2), "An incomplete clear must not unlock level 2.")

	GameManager.register_eliminated_threat()
	_expect(GameManager.is_current_level_complete(), "Eliminating 100% must complete the current level.")
	_expect(GameManager.is_level_unlocked(2), "Completing level 1 must unlock level 2.")

func _test_level_selector_discovery() -> void:
	var selector := SkillTree.new()
	var configs: Array[LevelConfig] = selector._load_level_configs()
	var visible_level_numbers: Array[int] = []
	for config in configs:
		visible_level_numbers.append(config.level_number)
	_expect(visible_level_numbers.has(1), "The level selector must discover Level 1.")
	_expect(visible_level_numbers.has(2), "The level selector must discover Level 2.")
	_expect(not visible_level_numbers.has(0), "Hidden test levels must stay out of the selector.")
	selector.free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
