extends Node

const ENEMY_RESOURCE_PATHS: PackedStringArray = [
	"res://src/resources/enemies/asteroid_small.tres",
	"res://src/resources/enemies/asteroid_medium.tres",
	"res://src/resources/enemies/asteroid_large.tres",
	"res://src/resources/enemies/barrier_attack_ship.tres",
]

var _failures: int = 0


func _ready() -> void:
	_test_initial_catalog()
	_test_empty_catalog_resource()
	_test_duplicate_enemy_ids()
	_test_empty_roster_resource()
	_test_invalid_spawn_weight()
	_test_duplicate_roster_enemy()
	_test_attack_parameters()
	_test_standardized_visual_contract()

	if _failures == 0:
		print("Enemy data validation tests passed.")
	else:
		push_error("Enemy data validation tests failed: %d" % _failures)
	get_tree().quit(_failures)


func _test_initial_catalog() -> void:
	var catalog: Array = []
	for resource_path in ENEMY_RESOURCE_PATHS:
		var enemy := load(resource_path) as EnemyData
		_expect(is_instance_valid(enemy), "Enemy resource must load: %s" % resource_path)
		catalog.append(enemy)
	var errors := EnemyData.validate_catalog(catalog)
	_expect(errors.is_empty(), "Initial enemy catalog must be valid: %s" % str(errors))
	for enemy: EnemyData in catalog:
		_expect(enemy.visual_asset != null and enemy.visual_scene == null, "Authored enemy must use VisualAsset3D instead of a raw imported scene: %s" % enemy.enemy_id)


func _test_empty_catalog_resource() -> void:
	var errors := EnemyData.validate_catalog([null])
	_expect(_contains_text(errors, "entry 0 is empty"), "Catalog must reject empty resources.")


func _test_duplicate_enemy_ids() -> void:
	var first := _make_valid_enemy(&"duplicate_enemy")
	var second := _make_valid_enemy(&"duplicate_enemy")
	var errors := EnemyData.validate_catalog([first, second])
	_expect(_contains_text(errors, "Duplicate enemy_id"), "Catalog must reject duplicate enemy IDs.")


func _test_empty_roster_resource() -> void:
	var errors := EnemySpawnEntry.validate_roster([null])
	_expect(_contains_text(errors, "entry 0 is empty"), "Roster must reject empty resources.")


func _test_invalid_spawn_weight() -> void:
	var entry := EnemySpawnEntry.new()
	entry.enemy = _make_valid_enemy(&"weighted_enemy")
	entry.spawn_weight = 0.0
	var errors := entry.get_validation_errors()
	_expect(_contains_text(errors, "greater than zero"), "Roster must reject zero spawn weight.")


func _test_duplicate_roster_enemy() -> void:
	var enemy := _make_valid_enemy(&"roster_duplicate")
	var first := EnemySpawnEntry.new()
	first.enemy = enemy
	var second := EnemySpawnEntry.new()
	second.enemy = enemy
	var errors := EnemySpawnEntry.validate_roster([first, second])
	_expect(_contains_text(errors, "Duplicate enemy_id"), "Roster must reject duplicate enemy IDs.")


func _test_attack_parameters() -> void:
	for field in ["attack_range", "projectile_speed"]:
		var enemy := _make_valid_enemy(&"invalid_attack")
		enemy.set(field, NAN)
		_expect(not enemy.get_validation_errors().is_empty(), "Attack parameters must reject NaN: " + field)
		enemy.set(field, 0.0)
		_expect(not enemy.get_validation_errors().is_empty(), "Attack parameters must be positive: " + field)


func _test_standardized_visual_contract() -> void:
	var visual := VisualAsset3D.new()
	visual.scene = load("res://src/assets/3d/prefabs/turrets/defense_blaster_visual.tscn") as PackedScene
	visual.aim_pivot_path = NodePath("MissingPivot")
	visual.muzzle_path = NodePath("AimPivot/Muzzle")
	_expect(_contains_text(visual.get_validation_errors(), "aim_pivot_path"), "Visual contract must reject an unresolved aim pivot.")
	visual.aim_pivot_path = NodePath("AimPivot")
	visual.scale = Vector3(1, 0, 1)
	_expect(_contains_text(visual.get_validation_errors(), "scale"), "Visual contract must reject a zero scale axis.")
	visual.scale = Vector3.ONE
	_expect(visual.get_validation_errors().is_empty(), "Complete turret visual contract must validate.")
	var root := visual.instantiate_visual()
	_expect(root != null and visual.resolve_aim_pivot(root) != null and visual.resolve_muzzle(root) != null, "Visual contract must instantiate and resolve authored markers.")
	root.free()


func _make_valid_enemy(id: StringName) -> EnemyData:
	var enemy := EnemyData.new()
	enemy.enemy_id = id
	enemy.display_name = String(id)
	enemy.visual_scene = load("res://src/assets/3d/meteoro_small.FBX") as PackedScene
	return enemy


func _contains_text(messages: PackedStringArray, text: String) -> bool:
	for message in messages:
		if message.contains(text):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
