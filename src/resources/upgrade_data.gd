# res://src/resources/upgrade_data.gd
@tool
class_name UpgradeData
extends Resource

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
	"SatelliteAmount",
	"GarbageAmount",
	"GarbageQuality",
	"ResourceMultiplier",
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
) var category: String = ""
var unlocks: Array[String] = []

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
	var path = "res://src/resources/upgrades/"
	if DirAccess.dir_exists_absolute(path):
		var dir = DirAccess.open(path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(".tres"):
					var file = FileAccess.open(path + file_name, FileAccess.READ)
					if file:
						var content = file.get_as_text()
						file.close()
						
						# Parse upgrade_id = "value"
						var idx = content.find("upgrade_id = \"")
						if idx != -1:
							var start = idx + 14
							var end = content.find("\"", start)
							if end != -1:
								var val = content.substr(start, end - start)
								if val != "" and not val in ids:
									ids.append(val)
				file_name = dir.get_next()
			dir.list_dir_end()
	ids.sort()
	return ids

@export var base_cost: float = 100.0
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
	return base_cost
