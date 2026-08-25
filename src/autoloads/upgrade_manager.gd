# res://src/autoloads/upgrade_manager.gd
extends Node

signal upgrade_purchased(upgrade_id: String, new_level: int)

const DEFAULT_SKILL_TREE_CONFIG_PATH := "res://src/resources/skill_trees/MainSkillTreeConfig.tres"

# Holds all loaded UpgradeData resources
var upgrades_list: Array[UpgradeData] = []
var upgrades_by_id: Dictionary = {}

# Player's current levels: { upgrade_id: int }
var purchased_levels: Dictionary = {}
var skill_tree_config: SkillTreeConfig = null

func _ready() -> void:
	# Create directory if it doesn't exist
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("res://src/resources/upgrades"):
		dir.make_dir_recursive("res://src/resources/upgrades")
	
	load_skill_tree_config()
	load_all_upgrades()

func load_skill_tree_config() -> void:
	var loaded_resource := load(DEFAULT_SKILL_TREE_CONFIG_PATH)
	if loaded_resource is SkillTreeConfig:
		skill_tree_config = loaded_resource as SkillTreeConfig
	else:
		push_error("[UpgradeManager] Invalid SkillTreeConfig: " + DEFAULT_SKILL_TREE_CONFIG_PATH)

# Scans directory and loads all .tres upgrades
func load_all_upgrades() -> void:
	upgrades_list.clear()
	upgrades_by_id.clear()
	
	_load_upgrades_from_directory("res://src/resources/upgrades")
	
	# Set levels for all loaded upgrades
	for upgrade in upgrades_list:
		if not purchased_levels.has(upgrade.upgrade_id):
			purchased_levels[upgrade.upgrade_id] = 0

func _load_upgrades_from_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if not directory:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			_load_upgrades_from_directory(resource_path)
		else:
			var actual_path := resource_path.trim_suffix(".remap") if file_name.ends_with(".remap") else resource_path
			if actual_path.ends_with(".tres") or actual_path.ends_with(".res"):
				var upgrade := load(actual_path) as UpgradeData
				if upgrade and not upgrade.upgrade_id.is_empty():
					if upgrades_by_id.has(upgrade.upgrade_id):
						push_error("[UpgradeManager] Duplicate upgrade ID: " + upgrade.upgrade_id)
					else:
						upgrades_list.append(upgrade)
						upgrades_by_id[upgrade.upgrade_id] = upgrade
		file_name = directory.get_next()
	directory.list_dir_end()

func get_upgrade_level(upgrade_id: String) -> int:
	return purchased_levels.get(upgrade_id, 0)

# Checks if the upgrade is revealed/visible in the skill tree
func is_upgrade_visible(upgrade: UpgradeData) -> bool:
	if not is_instance_valid(upgrade):
		return false
	if get_upgrade_level(upgrade.upgrade_id) > 0:
		return true
	if upgrade.default_unlocked:
		return true

	if is_instance_valid(skill_tree_config):
		var node_data := skill_tree_config.find_node_by_upgrade(upgrade)
		if is_instance_valid(node_data):
			if node_data.prerequisites.is_empty():
				return false
			if node_data.requirement_mode == SkillTreeNodeData.RequirementMode.ALL:
				for prerequisite in node_data.prerequisites:
					if get_upgrade_level(prerequisite.upgrade_id) <= 0:
						return false
				return true
			for prerequisite in node_data.prerequisites:
				if get_upgrade_level(prerequisite.upgrade_id) > 0:
					return true
			return false
	
	# Compatibility for upgrade resources not migrated into SkillTreeConfig.
	for other in upgrades_list:
		if get_upgrade_level(other.upgrade_id) > 0:
			if upgrade.upgrade_id in other.unlocks:
				return true
					
	return false

# Check if upgrade can be unlocked/purchased
func can_unlock_upgrade(upgrade_data: UpgradeData) -> bool:
	if not is_upgrade_visible(upgrade_data):
		return false
		
	var current_level = get_upgrade_level(upgrade_data.upgrade_id)
	if current_level >= upgrade_data.max_level:
		return false
			
	return true

# Try to purchase upgrade. Deducts currency from GameManager.
func purchase_upgrade(upgrade_data: UpgradeData) -> bool:
	print("[UpgradeManager] Attempting to purchase: ", upgrade_data.upgrade_id)
	if not can_unlock_upgrade(upgrade_data):
		print("[UpgradeManager] Purchase failed: cannot unlock ", upgrade_data.upgrade_id)
		return false
		
	var current_level = get_upgrade_level(upgrade_data.upgrade_id)
	var cost = upgrade_data.get_cost(current_level)
	
	print("[UpgradeManager] Cost: ", cost, ", Current Level: ", current_level)
	
	# Access global GameManager (we will create this autoload as GameManager)
	if GameManager.spend_lifetime_credits(cost):
		purchased_levels[upgrade_data.upgrade_id] = current_level + 1
		print("[UpgradeManager] Purchase success! New level for ", upgrade_data.upgrade_id, " is ", purchased_levels[upgrade_data.upgrade_id])
		upgrade_purchased.emit(upgrade_data.upgrade_id, current_level + 1)
		return true
		
	print("[UpgradeManager] Purchase failed: not enough credits.")
	return false

# Calculate Category Multiplier using additive scaling:
# FinalMultiplier = 1.0 + Sum(IndividualUpgradeMultiplier - 1.0)
func get_multiplier(category_name: String) -> float:
	var sum_bonuses = 0.0
	for upgrade in upgrades_list:
		if upgrade.category == category_name:
			var lvl = get_upgrade_level(upgrade.upgrade_id)
			var mult = upgrade.calculate_multiplier(lvl)
			sum_bonuses += (mult - 1.0)
	
	return 1.0 + sum_bonuses

# Multiplies each upgrade's calculated multiplier in a category.
# Used by test click damage scaling: 3 base damage, then x3 per level.
func get_compound_multiplier(category_name: String) -> float:
	var result = 1.0
	for upgrade in upgrades_list:
		if upgrade.category != category_name:
			continue
		var level = get_upgrade_level(upgrade.upgrade_id)
		if level > 0:
			result *= upgrade.calculate_multiplier(level)
	return result

# Sums the raw values of all purchased upgrades in a category
func get_total_bonus(category_name: String) -> float:
	var total = 0.0
	for upgrade in upgrades_list:
		if upgrade.category == category_name:
			var lvl = get_upgrade_level(upgrade.upgrade_id)
			if lvl > 0:
				total += upgrade.value_increment * lvl
	return total
