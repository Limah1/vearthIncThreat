# res://src/autoloads/upgrade_manager.gd
extends Node

signal upgrade_purchased(upgrade_id: String, new_level: int)

# Holds all loaded UpgradeData resources
var upgrades_list: Array[UpgradeData] = []
var upgrades_by_id: Dictionary = {}

# Player's current levels: { upgrade_id: int }
var purchased_levels: Dictionary = {}

func _ready() -> void:
	# Create directory if it doesn't exist
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("res://src/resources/upgrades"):
		dir.make_dir_recursive("res://src/resources/upgrades")
	
	load_all_upgrades()

# Scans directory and loads all .tres upgrades
func load_all_upgrades() -> void:
	upgrades_list.clear()
	upgrades_by_id.clear()
	
	var dir = DirAccess.open("res://src/resources/upgrades/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var upgrade = load("res://src/resources/upgrades/" + file_name) as UpgradeData
				if upgrade:
					upgrades_list.append(upgrade)
					upgrades_by_id[upgrade.upgrade_id] = upgrade
			file_name = dir.get_next()
		dir.list_dir_end()
	
	# Set levels for all loaded upgrades
	for upgrade in upgrades_list:
		if not purchased_levels.has(upgrade.upgrade_id):
			purchased_levels[upgrade.upgrade_id] = 0

func get_upgrade_level(upgrade_id: String) -> int:
	return purchased_levels.get(upgrade_id, 0)

# Checks if the upgrade is revealed/visible in the skill tree
func is_upgrade_visible(upgrade: UpgradeData) -> bool:
	if upgrade.default_unlocked:
		return true
	
	# Check if any other upgrade is purchased (level > 0) and has this upgrade's ID in its 'unlocks' list
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
	if not can_unlock_upgrade(upgrade_data):
		return false
		
	var current_level = get_upgrade_level(upgrade_data.upgrade_id)
	var cost = upgrade_data.get_cost(current_level)
	
	# Access global GameManager (we will create this autoload as GameManager)
	if GameManager.spend_lifetime_credits(cost):
		purchased_levels[upgrade_data.upgrade_id] = current_level + 1
		upgrade_purchased.emit(upgrade_data.upgrade_id, current_level + 1)
		return true
		
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

# Sums the raw values of all purchased upgrades in a category
func get_total_bonus(category_name: String) -> float:
	var total = 0.0
	for upgrade in upgrades_list:
		if upgrade.category == category_name:
			var lvl = get_upgrade_level(upgrade.upgrade_id)
			if lvl > 0:
				total += upgrade.value_increment * lvl
	return total
