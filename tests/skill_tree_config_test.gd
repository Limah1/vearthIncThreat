extends Node

const CONFIG_PATH := "res://src/resources/skill_trees/MainSkillTreeConfig.tres"
const SKILL_TREE_SCENE := preload("res://src/ui/skill_tree.tscn")
const DEFENSE_BLASTER_SCENE := preload("res://src/entities/defense_blaster.tscn")

var _failures: int = 0

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var config := load(CONFIG_PATH) as SkillTreeConfig
	_expect(is_instance_valid(config), "Main SkillTreeConfig must load.")
	if is_instance_valid(config):
		_test_config(config)
		await _test_runtime_generation(config)
		await _test_defense_blaster_upgrades(config)
	if _failures == 0:
		print("Skill tree config tests passed.")
	else:
		push_error("Skill tree config tests failed: %d" % _failures)
	get_tree().quit(_failures)

func _test_config(config: SkillTreeConfig) -> void:
	var validation_errors := config.validate_tree()
	_expect(validation_errors.is_empty(), "Migrated SkillTreeConfig must validate: %s" % validation_errors)
	_expect(config.nodes.size() == 9, "The authored tree must contain all three turret branches and their upgrades.")

	var blaster_root := config.find_node_by_id("DA_UnlockTurret")
	var attack_speed := config.find_node_by_id("DA_DefenseBlasterAttackSpeed")
	var blaster_damage := config.find_node_by_id("DA_DefenseBlasterDamage")
	var laser_root := config.find_node_by_id("DA_UnlockLaserTurret")
	var laser_cooldown := config.find_node_by_id("DA_LaserCooldownReduction")
	var laser_damage := config.find_node_by_id("DA_LaserDamage")
	var miner_root := config.find_node_by_id("DA_UnlockTurretMiner")
	var miner_damage := config.find_node_by_id("DA_MinerDamage")
	var miner_radius := config.find_node_by_id("DA_MinerRadius")
	_expect(is_instance_valid(blaster_root), "Defense Blaster root must exist.")
	_expect(is_instance_valid(attack_speed), "Defense Blaster Attack Speed must exist.")
	_expect(is_instance_valid(blaster_damage), "Defense Blaster Damage must exist.")
	_expect(is_instance_valid(laser_root), "Laser Turret root must exist.")
	_expect(is_instance_valid(laser_cooldown), "Laser cooldown upgrade must exist.")
	_expect(is_instance_valid(laser_damage), "Laser damage upgrade must exist.")
	_expect(is_instance_valid(miner_root), "Turret Miner root must exist.")
	_expect(is_instance_valid(miner_damage), "Mine damage upgrade must exist.")
	_expect(is_instance_valid(miner_radius), "Mine radius upgrade must exist.")
	if is_instance_valid(blaster_root) and is_instance_valid(attack_speed) and is_instance_valid(blaster_damage):
		_expect(
			attack_speed.prerequisites.has(blaster_root.upgrade),
			"Attack Speed must require Defense Blaster."
		)
		_expect(
			blaster_damage.prerequisites.has(blaster_root.upgrade),
			"Damage must require Defense Blaster."
		)
		_expect(is_equal_approx(attack_speed.upgrade.get_cost(0), 20.0), "Attack Speed rank 1 must cost $20.")
		_expect(is_equal_approx(attack_speed.upgrade.get_cost(1), 40.0), "Attack Speed rank 2 must cost $40.")
		_expect(is_equal_approx(attack_speed.upgrade.get_cost(2), 80.0), "Attack Speed rank 3 must cost $80.")
		_expect(attack_speed.upgrade.max_level == 3, "Attack Speed must have three ranks.")
		_expect(is_equal_approx(blaster_damage.upgrade.get_cost(0), 80.0), "Defense Blaster Damage must cost $80.")
		_expect(blaster_damage.upgrade.max_level == 1, "Defense Blaster Damage must be a single purchase.")
	if is_instance_valid(laser_root) and is_instance_valid(laser_cooldown) and is_instance_valid(laser_damage):
		_expect(laser_cooldown.prerequisites.has(laser_root.upgrade), "Laser cooldown must require Laser Turret.")
		_expect(laser_damage.prerequisites.has(laser_root.upgrade), "Laser damage must require Laser Turret.")
		_expect(is_equal_approx(laser_root.upgrade.get_cost(0), 50.0), "Laser Turret unlock must cost $50.")
		_expect(is_equal_approx(laser_cooldown.upgrade.get_cost(0), 100.0), "Laser cooldown rank 1 must cost $100.")
		_expect(is_equal_approx(laser_cooldown.upgrade.get_cost(1), 200.0), "Laser cooldown rank 2 must cost $200.")
		_expect(is_equal_approx(laser_cooldown.upgrade.get_cost(2), 300.0), "Laser cooldown rank 3 must cost $300.")
		_expect(is_equal_approx(laser_damage.upgrade.get_cost(0), 50.0), "Laser damage must cost $50.")
	if is_instance_valid(miner_root) and is_instance_valid(miner_damage) and is_instance_valid(miner_radius):
		_expect(miner_damage.prerequisites.has(miner_root.upgrade), "Mine damage must require Turret Miner.")
		_expect(miner_radius.prerequisites.has(miner_root.upgrade), "Mine radius must require Turret Miner.")
		_expect(is_equal_approx(miner_root.upgrade.get_cost(0), 50.0), "Turret Miner unlock must cost $50.")
		_expect(is_equal_approx(miner_damage.upgrade.get_cost(0), 50.0), "Mine damage must cost $50.")
		_expect(is_equal_approx(miner_radius.upgrade.get_cost(0), 50.0), "Mine radius must cost $50.")

	UpgradeManager.purchased_levels.clear()
	UpgradeManager.load_all_upgrades()
	_expect(UpgradeManager.is_upgrade_visible(blaster_root.upgrade), "Defense Blaster must be initially visible.")
	_expect(not UpgradeManager.is_upgrade_visible(attack_speed.upgrade), "Attack Speed must be hidden before Defense Blaster is purchased.")
	UpgradeManager.purchased_levels[blaster_root.upgrade.upgrade_id] = 1
	_expect(UpgradeManager.is_upgrade_visible(attack_speed.upgrade), "Purchasing Defense Blaster must reveal Attack Speed.")

func _test_runtime_generation(config: SkillTreeConfig) -> void:
	var tree := SKILL_TREE_SCENE.instantiate() as SkillTree
	add_child(tree)
	await get_tree().process_frame
	var generated_slots: Array[UpgradeSlotUI] = []
	for slot in tree._find_slots_recursive(tree.grid_container):
		generated_slots.append(slot)
	_expect(
		generated_slots.size() == config.nodes.size(),
		"Runtime SkillTree must generate exactly one slot per config node."
	)
	tree.queue_free()

func _test_defense_blaster_upgrades(config: SkillTreeConfig) -> void:
	var attack_speed := config.find_node_by_id("DA_DefenseBlasterAttackSpeed")
	var blaster_damage := config.find_node_by_id("DA_DefenseBlasterDamage")
	if not is_instance_valid(attack_speed) or not is_instance_valid(blaster_damage):
		return
	UpgradeManager.purchased_levels[attack_speed.upgrade.upgrade_id] = 3
	UpgradeManager.purchased_levels[blaster_damage.upgrade.upgrade_id] = 1
	var blaster := DEFENSE_BLASTER_SCENE.instantiate() as DefenseBlaster
	add_child(blaster)
	await get_tree().process_frame
	_expect(is_equal_approx(blaster.effective_damage, 2.0), "Damage upgrade must add 1 to base blaster damage.")
	_expect(
		is_equal_approx(blaster.effective_fire_rate, blaster.turret_config.fire_rate * pow(1.1, 3)),
		"Three Attack Speed ranks must multiply fire rate by 1.1 three times."
	)
	blaster.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
