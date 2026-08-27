# res://src/resources/upgrade_data.gd
@tool
class_name UpgradeData
extends Resource

const UPGRADE_DIRECTORY := "res://src/resources/upgrades"
const ID_PREFIX := "UPG"
const CATEGORIES: Array[String] = [
	"ClickDamage",
	"ClickRadius",
	"AutoClickRate",
	"PlanetHealth",
	"ShieldHP",
	"UnlockTurret",
	"TurretAttackSpeed",
	"TurretDamage",
	"UnlockLaserTurret",
	"LaserCooldownReduction",
	"LaserDamage",
	"UnlockTurretMiner",
	"MinerDamage",
	"MinerRadius",
	"SatelliteAmount",
	"SatelliteDamage",
	"SatelliteSpeed",
	"SatelliteProjectileSpeed",
	"SatelliteUnlock",
	"GarbageAmount",
	"GarbageQuality",
	"UnlockSmallAsteroid",
	"UnlockMediumAsteroid",
	"UnlockLargeAsteroid",
	"AlienShips",
	"ChanceSmallAsteroid",
	"ChanceMediumAsteroid",
	"ChanceLargeAsteroid",
	"DebrisUnlock",
	"DebrisPiercing",
	"DebrisAmount",
	"DebrisDamage",
	"AsteroidAmount"
]

@export var upgrade_id: String = ""
@export var upgrade_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_enum(
	"ClickDamage",
	"ClickRadius",
	"AutoClickRate",
	"PlanetHealth",
	"ShieldHP",
	"UnlockTurret",
	"TurretAttackSpeed",
	"TurretDamage",
	"UnlockLaserTurret",
	"LaserCooldownReduction",
	"LaserDamage",
	"UnlockTurretMiner",
	"MinerDamage",
	"MinerRadius",
	"SatelliteAmount",
	"SatelliteDamage",
	"SatelliteSpeed",
	"SatelliteProjectileSpeed",
	"SatelliteUnlock",
	"GarbageAmount",
	"GarbageQuality",
	"UnlockSmallAsteroid",
	"UnlockMediumAsteroid",
	"UnlockLargeAsteroid",
	"AlienShips",
	"ChanceSmallAsteroid",
	"ChanceMediumAsteroid",
	"ChanceLargeAsteroid",
	"DebrisUnlock",
	"DebrisPiercing",
	"DebrisAmount",
	"DebrisDamage",
	"AsteroidAmount"
) var category: String = "":
	set(value):
		category = value
		_maybe_generate_id()
var unlocks: Array[String] = []

## Returns the supported gameplay categories used by the inspector and tools.
static func get_categories() -> Array[String]:
	return CATEGORIES.duplicate()

## Generates a stable, human-readable ID for a new upgrade asset.
## Existing IDs are deliberately never changed: they are save-game and tree keys.
static func generate_unique_id(category_name: String, ignored_id: String = "") -> String:
	var category_key := _normalize_id_component(category_name)
	if category_key.is_empty():
		category_key = "UPGRADE"
	var prefix := "%s_%s_" % [ID_PREFIX, category_key]
	var used_ids := _collect_upgrade_ids(UPGRADE_DIRECTORY)
	var sequence := 1
	while true:
		var candidate := "%s%03d" % [prefix, sequence]
		if candidate != ignored_id and not used_ids.has(candidate):
			return candidate
		sequence += 1
	return "%s%03d" % [prefix, sequence]

static func _normalize_id_component(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	var result := ""
	for character in normalized:
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			result += character
		elif not result.ends_with("_"):
			result += "_"
	return result.trim_prefix("_").trim_suffix("_")

static func _collect_upgrade_ids(directory_path: String) -> Dictionary:
	var ids: Dictionary = {}
	var directory := DirAccess.open(directory_path)
	if not directory:
		return ids
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			var nested_ids := _collect_upgrade_ids(resource_path)
			for nested_id in nested_ids:
				ids[nested_id] = true
		else:
			var actual_path := resource_path.trim_suffix(".remap") if file_name.ends_with(".remap") else resource_path
			if actual_path.ends_with(".tres") or actual_path.ends_with(".res"):
				var upgrade := load(actual_path) as UpgradeData
				if is_instance_valid(upgrade) and not upgrade.upgrade_id.is_empty():
					ids[upgrade.upgrade_id] = true
		file_name = directory.get_next()
	directory.list_dir_end()
	return ids

func _maybe_generate_id() -> void:
	if not Engine.is_editor_hint() or not upgrade_id.is_empty() or category.is_empty():
		return
	upgrade_id = generate_unique_id(category)
	emit_changed()

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	
	# Fetch all available upgrade IDs from resources
	var ids = _get_upgrade_ids()
	var ids_string = ",".join(ids)
	
	properties.append({
		"name": "unlocks",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM, ids_string]
	})
	
	return properties

func _get_upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	var collected_ids := _collect_upgrade_ids(UPGRADE_DIRECTORY)
	for upgrade_id_key in collected_ids:
		ids.append(upgrade_id_key)
	ids.sort()
	return ids

@export var base_cost: float = 100.0
@export_range(1.0, 100.0, 0.05) var cost_growth_multiplier: float = 1.0
@export_range(0.0, 1000000.0, 1.0) var cost_increment: float = 0.0
@export var max_level: int = 1

@export var value_increment: float = 0.1
@export var internal_level: float = 1.0
@export var is_percentage: bool = false
@export var default_unlocked: bool = false

# Calculates the individual multiplier bonus for a given level
# N = Level * InternalLevel
# Linear: Multiplier = 1.0 + (ValueIncrement * N)
# Compound: Multiplier = (1.0 + ValueIncrement) ^ N
func calculate_multiplier(level: int) -> float:
	var N = level * internal_level
	if is_percentage:
		return pow(1.0 + value_increment, N)
	else:
		return 1.0 + (value_increment * N)

# Calculates the cost to purchase the next level
func get_cost(level: int) -> float:
	if cost_increment > 0.0:
		return base_cost + cost_increment * maxi(level, 0)
	return base_cost * pow(cost_growth_multiplier, maxi(level, 0))
