@tool
extends RefCounted

const PROJECT_ID := "vearth-incremental-threat"
const SCHEMA_VERSION := 2
const DATA_SHEETS: Array[String] = ["Upgrades", "Turrets", "Barriers", "Levels"]
const HEADERS: Array[String] = [
	"Field ID",
	"System",
	"Actor / Asset",
	"Property",
	"Current Value",
	"New Value",
	"Type",
	"Minimum",
	"Maximum",
	"Resource Path",
	"Property Key",
	"Editing Notes",
]

const UPGRADE_DIRECTORY := "res://src/resources/upgrades"
const TURRET_DIRECTORY := "res://src/resources/turrets"
const BARRIER_DIRECTORY := "res://src/resources/barriers"
const LEVEL_DIRECTORY := "res://src/resources/levels"

const UPGRADE_FIELDS := [
	{"key": "base_cost", "label": "Base cost", "type": "float", "min": 0.0, "max": 1000000000000.0, "notes": "Cost of the first purchase."},
	{"key": "cost_growth_multiplier", "label": "Cost growth multiplier", "type": "float", "min": 1.0, "max": 100.0, "notes": "Used when Cost Increment is zero."},
	{"key": "cost_increment", "label": "Linear cost increment", "type": "float", "min": 0.0, "max": 1000000000.0, "notes": "When greater than zero, cost grows linearly."},
	{"key": "max_level", "label": "Maximum level", "type": "int", "min": 1, "max": 9999, "notes": "Maximum number of purchases."},
	{"key": "value_increment", "label": "Value increment", "type": "float", "min": -1000000.0, "max": 1000000.0, "notes": "Raw bonus; 0.10 means 10% when Is Percentage is TRUE."},
	{"key": "internal_level", "label": "Internal level", "type": "float", "min": 0.0, "max": 1000.0, "notes": "Scales the effective purchased level."},
	{"key": "is_percentage", "label": "Is percentage", "type": "bool", "min": null, "max": null, "notes": "Use a real TRUE/FALSE cell."},
	{"key": "default_unlocked", "label": "Default unlocked", "type": "bool", "min": null, "max": null, "notes": "Use a real TRUE/FALSE cell."},
]

const TURRET_FIELDS := [
	{"key": "damage", "label": "Damage", "type": "float", "min": 0.0, "max": 10000.0, "notes": "Base damage before upgrades."},
	{"key": "fire_rate", "label": "Fire rate", "type": "float", "min": 0.05, "max": 100.0, "notes": "Shots per second."},
	{"key": "attack_range", "label": "Attack range", "type": "float", "min": 10.0, "max": 5000.0, "notes": "Gameplay range in world units."},
	{"key": "default_cone_angle", "label": "Default cone angle", "type": "float", "min": 1.0, "max": 179.0, "notes": "Must remain between minimum and maximum cone angle."},
	{"key": "minimum_cone_angle", "label": "Minimum cone angle", "type": "float", "min": 1.0, "max": 179.0, "notes": "Smallest configurable cone angle."},
	{"key": "maximum_cone_angle", "label": "Maximum cone angle", "type": "float", "min": 1.0, "max": 179.0, "notes": "Largest configurable cone angle."},
	{"key": "sweep_speed", "label": "Sweep speed", "type": "float", "min": 0.0, "max": 10.0, "notes": "Complete idle sweeps per second."},
	{"key": "target_refresh_interval", "label": "Target refresh interval", "type": "float", "min": 0.02, "max": 1.0, "notes": "Seconds between target refreshes."},
	{"key": "minimum_handle_distance", "label": "Minimum handle distance", "type": "float", "min": 5.0, "max": 500.0, "notes": "Must not exceed maximum handle distance."},
	{"key": "maximum_handle_distance", "label": "Maximum handle distance", "type": "float", "min": 5.0, "max": 1000.0, "notes": "Must be at least minimum handle distance."},
]

const BARRIER_FIELDS := [
	{"key": "max_hp", "label": "Maximum HP", "type": "float", "min": 1.0, "max": 1000000.0, "notes": "Base health of the barrier."},
	{"key": "size", "label": "Collision size", "type": "vector2", "min": null, "max": null, "notes": "Text cell formatted as X, Y. Both values must be positive."},
	{"key": "distance_from_planet", "label": "Distance from planet", "type": "float", "min": 0.0, "max": 2000.0, "notes": "Gameplay distance from the planet."},
	{"key": "depth", "label": "Visual depth", "type": "float", "min": 1.0, "max": 50.0, "notes": "3D barrier depth."},
]

const LEVEL_FIELDS := [
	{"key": "total_enemies", "label": "Total enemies", "type": "int", "min": 0, "max": 100000, "notes": "Total actors spawned by this level."},
	{"key": "starting_ally_ships", "label": "Starting Ally Ships", "type": "int", "min": 0, "max": 64, "notes": "Two-cell ships available during grid preparation."},
	{"key": "starting_defense_blocks", "label": "Starting Barriers", "type": "int", "min": 0, "max": 64, "notes": "One-cell destructible barriers available during grid preparation."},
	{"key": "minimum_ally_ships_to_start", "label": "Required Ally Ships", "type": "int", "min": 0, "max": 64, "notes": "Minimum placed ships required before Start Wave is enabled."},
]

func build_definitions() -> Dictionary:
	var sheets := {
		"Upgrades": [],
		"Turrets": [],
		"Barriers": [],
		"Levels": [],
	}
	_add_discovered_resources(sheets["Upgrades"], UPGRADE_DIRECTORY, "Upgrades", UPGRADE_FIELDS, "UpgradeData")
	_add_discovered_resources(sheets["Turrets"], TURRET_DIRECTORY, "Turrets", TURRET_FIELDS, "TurretConfig")
	_add_discovered_resources(sheets["Barriers"], BARRIER_DIRECTORY, "Barriers", BARRIER_FIELDS, "BarrierConfig")
	_add_discovered_resources(sheets["Levels"], LEVEL_DIRECTORY, "Levels", LEVEL_FIELDS, "LevelConfig")
	for sheet_name in DATA_SHEETS:
		var rows: Array = sheets[sheet_name]
		rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return String(first.field_id).naturalnocasecmp_to(String(second.field_id)) < 0
		)
	return sheets

func build_workbook_sheets() -> Dictionary:
	var definitions := build_definitions()
	var workbook_sheets: Dictionary = {}
	for sheet_name in DATA_SHEETS:
		var rows: Array = []
		for definition in definitions[sheet_name]:
			rows.append([
				definition.field_id,
				definition.system,
				definition.asset,
				definition.property_label,
				definition.current_value,
				definition.current_value,
				definition.type,
				definition.min,
				definition.max,
				definition.resource_path,
				definition.property_key,
				definition.notes,
			])
		workbook_sheets[sheet_name] = {
			"headers": Array(HEADERS),
			"rows": rows,
			"editable_columns": [5],
			"hidden_columns": [9, 10],
		}
	workbook_sheets["Schema"] = {
		"headers": ["Key", "Value"],
		"rows": [
			["project_id", PROJECT_ID],
			["schema_version", SCHEMA_VERSION],
			["exported_at_utc", Time.get_datetime_string_from_system(true)],
			["workbook_format", "Vearth Balance XLSX"],
			["instructions", "Edit only the New Value column, then import the .xlsx in Godot."],
		],
		"hidden": true,
	}
	return workbook_sheets

func flatten_definitions(definitions_by_sheet: Dictionary) -> Dictionary:
	var definitions_by_id: Dictionary = {}
	for sheet_name in DATA_SHEETS:
		for definition in definitions_by_sheet.get(sheet_name, []):
			definitions_by_id[definition.field_id] = definition
	return definitions_by_id

func _add_discovered_resources(
	output: Array,
	directory_path: String,
	system_name: String,
	fields: Array,
	expected_class_name: String
) -> void:
	for resource_path in _scan_resource_paths(directory_path):
		var resource := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if not _matches_script_class(resource, expected_class_name):
			continue
		var asset_name := resource_path.get_file().get_basename()
		var identity := _normalize_id_component(asset_name)
		if expected_class_name == "UpgradeData":
			var configured_name: String = resource.get("upgrade_name")
			var configured_id: String = resource.get("upgrade_id")
			if not configured_name.is_empty():
				asset_name = configured_name
			if not configured_id.is_empty():
				identity = configured_id
		for field in fields:
			var field_id := "%s.%s.%s" % [system_name.to_lower(), identity, field.key]
			output.append({
				"field_id": field_id,
				"system": system_name,
				"asset": asset_name,
				"property_label": field.label,
				"current_value": resource.get(field.key),
				"type": field.type,
				"min": field.min,
				"max": field.max,
				"resource_path": resource_path,
				"property_key": field.key,
				"notes": field.notes,
			})

func _scan_resource_paths(directory_path: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if not directory:
		return paths
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			paths.append_array(_scan_resource_paths(path))
		else:
			var actual_path := path.trim_suffix(".remap") if file_name.ends_with(".remap") else path
			if actual_path.ends_with(".tres") or actual_path.ends_with(".res"):
				paths.append(actual_path)
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths

func _matches_script_class(resource: Resource, expected_class_name: String) -> bool:
	if not is_instance_valid(resource):
		return false
	match expected_class_name:
		"UpgradeData":
			return resource is UpgradeData
		"TurretConfig":
			return resource is TurretConfig
		"BarrierConfig":
			return resource is BarrierConfig
		"LevelConfig":
			return resource is LevelConfig
	return false

func _normalize_id_component(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	var result := ""
	for character in normalized:
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			result += character
		elif not result.ends_with("_"):
			result += "_"
	return result.trim_prefix("_").trim_suffix("_")
