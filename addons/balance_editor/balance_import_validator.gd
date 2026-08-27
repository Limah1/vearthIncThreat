@tool
extends RefCounted

const BalanceSchemaScript := preload("res://addons/balance_editor/balance_schema.gd")
const PROJECT_ID := "vearth-incremental-threat"
const SCHEMA_VERSION := 2
const DATA_SHEETS: Array[String] = ["Upgrades", "Turrets", "Barriers", "Levels"]
const REQUIRED_HEADERS: Array[String] = [
	"Field ID", "System", "Actor / Asset", "Property", "Current Value", "New Value",
	"Type", "Minimum", "Maximum", "Resource Path", "Property Key", "Editing Notes",
]

func validate_workbook(parsed_sheets: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	_validate_schema_sheet(parsed_sheets, errors)
	var schema := BalanceSchemaScript.new()
	var definitions_by_sheet := schema.build_definitions()
	var expected_by_id := schema.flatten_definitions(definitions_by_sheet)
	var seen_ids: Dictionary = {}
	var changes: Array[Dictionary] = []
	var proposed_values: Dictionary = {}

	for sheet_name in DATA_SHEETS:
		if not parsed_sheets.has(sheet_name):
			errors.append("Missing worksheet: %s." % sheet_name)
			continue
		var sheet: Dictionary = parsed_sheets[sheet_name]
		var headers_valid := true
		for required_header in REQUIRED_HEADERS:
			if not sheet.headers.has(required_header):
				errors.append("Worksheet '%s' is missing column '%s'." % [sheet_name, required_header])
				headers_valid = false
		if not headers_valid:
			continue
		for row in sheet.rows:
			var field_id := _cell_as_string(row.cells.get("Field ID", {}))
			if field_id.is_empty():
				if not _row_is_blank(row):
					errors.append("%s row %d has no Field ID." % [sheet_name, row.row_number])
				continue
			if seen_ids.has(field_id):
				errors.append("Duplicate Field ID: %s." % field_id)
				continue
			seen_ids[field_id] = true
			if not expected_by_id.has(field_id):
				errors.append("Unknown or stale Field ID: %s." % field_id)
				continue
			var definition: Dictionary = expected_by_id[field_id]
			if not definitions_by_sheet[sheet_name].has(definition):
				errors.append("Field '%s' is in the wrong worksheet." % field_id)
				continue
			_validate_identity_cells(row, definition, errors)
			var new_value_result := _decode_typed_value(row.cells.get("New Value", {}), definition, sheet_name, row.row_number)
			if not new_value_result.ok:
				errors.append(new_value_result.error)
				continue
			var current_value_result := _decode_typed_value(row.cells.get("Current Value", {}), definition, sheet_name, row.row_number)
			if not current_value_result.ok or not _values_equal(current_value_result.get("value"), definition.current_value, definition.type):
				errors.append("%s row %d is stale: Current Value no longer matches the Godot resource." % [sheet_name, row.row_number])
				continue
			var new_value: Variant = new_value_result.value
			if not proposed_values.has(definition.resource_path):
				proposed_values[definition.resource_path] = {}
			proposed_values[definition.resource_path][definition.property_key] = new_value
			if not _values_equal(new_value, definition.current_value, definition.type):
				changes.append({
					"field_id": field_id,
					"resource_path": definition.resource_path,
					"property_key": definition.property_key,
					"type": definition.type,
					"old_value": definition.current_value,
					"new_value": new_value,
				})

	for field_id in expected_by_id:
		if not seen_ids.has(field_id):
			errors.append("Workbook is missing registered field: %s." % field_id)
	_validate_consistency(definitions_by_sheet, proposed_values, errors)
	return {"ok": errors.is_empty(), "errors": errors, "changes": changes}

func _validate_schema_sheet(parsed_sheets: Dictionary, errors: PackedStringArray) -> void:
	if not parsed_sheets.has("Schema"):
		errors.append("Missing Schema worksheet.")
		return
	var schema_sheet: Dictionary = parsed_sheets.Schema
	if not schema_sheet.headers.has("Key") or not schema_sheet.headers.has("Value"):
		errors.append("Schema worksheet has invalid columns.")
		return
	var values: Dictionary = {}
	for row in schema_sheet.rows:
		var key := _cell_as_string(row.cells.get("Key", {}))
		if not key.is_empty():
			values[key] = row.cells.get("Value", {}).get("value")
	if String(values.get("project_id", "")) != PROJECT_ID:
		errors.append("Workbook belongs to a different project.")
	if int(values.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("Workbook schema version is stale. Extract a fresh workbook.")

func _validate_identity_cells(row: Dictionary, definition: Dictionary, errors: PackedStringArray) -> void:
	var checks := {
		"System": definition.system,
		"Resource Path": definition.resource_path,
		"Property Key": definition.property_key,
		"Type": definition.type,
	}
	for header in checks:
		if _cell_as_string(row.cells.get(header, {})) != String(checks[header]):
			errors.append("Row %d changed protected identity column '%s' for %s." % [row.row_number, header, definition.field_id])

func _decode_typed_value(cell: Dictionary, definition: Dictionary, sheet_name: String, row_number: int) -> Dictionary:
	var kind: String = cell.get("kind", "blank")
	var raw_value: Variant = cell.get("value")
	var value: Variant
	match definition.type:
		"int":
			if kind != "number" or not is_equal_approx(float(raw_value), round(float(raw_value))):
				return {"ok": false, "error": "%s row %d requires a whole-number cell for %s." % [sheet_name, row_number, definition.field_id]}
			value = int(round(float(raw_value)))
		"float":
			if kind != "number":
				return {"ok": false, "error": "%s row %d requires a numeric cell for %s." % [sheet_name, row_number, definition.field_id]}
			value = float(raw_value)
		"bool":
			if kind != "bool":
				return {"ok": false, "error": "%s row %d requires a real TRUE/FALSE cell for %s." % [sheet_name, row_number, definition.field_id]}
			value = bool(raw_value)
		"vector2":
			if kind != "string":
				return {"ok": false, "error": "%s row %d requires text formatted as X, Y for %s." % [sheet_name, row_number, definition.field_id]}
			var vector_result := _parse_vector2(String(raw_value))
			if not vector_result.ok:
				return {"ok": false, "error": "%s row %d requires text formatted as X, Y for %s." % [sheet_name, row_number, definition.field_id]}
			value = vector_result.value
		_:
			return {"ok": false, "error": "Unsupported type '%s' for %s." % [definition.type, definition.field_id]}
	if definition.min != null and float(value) < float(definition.min):
		return {"ok": false, "error": "%s row %d is below the minimum for %s." % [sheet_name, row_number, definition.field_id]}
	if definition.max != null and float(value) > float(definition.max):
		return {"ok": false, "error": "%s row %d is above the maximum for %s." % [sheet_name, row_number, definition.field_id]}
	return {"ok": true, "value": value}

func _validate_consistency(definitions_by_sheet: Dictionary, proposed_values: Dictionary, errors: PackedStringArray) -> void:
	var turret_paths: Dictionary = {}
	for definition in definitions_by_sheet.Turrets:
		turret_paths[definition.resource_path] = true
	for resource_path in turret_paths:
		if not proposed_values.has(resource_path):
			continue
		var values: Dictionary = proposed_values[resource_path]
		if (
			values.has("minimum_cone_angle")
			and values.has("default_cone_angle")
			and values.has("maximum_cone_angle")
			and (
			float(values.minimum_cone_angle) > float(values.default_cone_angle)
			or float(values.default_cone_angle) > float(values.maximum_cone_angle)
			)
		):
			errors.append("Turret cone angles must satisfy minimum <= default <= maximum: %s." % resource_path)
		if (
			values.has("minimum_handle_distance")
			and values.has("maximum_handle_distance")
			and float(values.minimum_handle_distance) > float(values.maximum_handle_distance)
		):
			errors.append("Turret handle distance minimum exceeds maximum: %s." % resource_path)
	var barrier_paths: Dictionary = {}
	for definition in definitions_by_sheet.Barriers:
		barrier_paths[definition.resource_path] = true
	for resource_path in barrier_paths:
		if not proposed_values.has(resource_path) or not proposed_values[resource_path].has("size"):
			continue
		var size: Vector2 = proposed_values[resource_path].size
		if size.x <= 0.0 or size.y <= 0.0:
			errors.append("Barrier collision size must use positive X and Y values: %s." % resource_path)
	var level_paths: Dictionary = {}
	for definition in definitions_by_sheet.Levels:
		level_paths[definition.resource_path] = true
	for resource_path in level_paths:
		if not proposed_values.has(resource_path):
			continue
		var values: Dictionary = proposed_values[resource_path]
		if (
			values.has("minimum_ally_ships_to_start")
			and values.has("starting_ally_ships")
			and int(values.minimum_ally_ships_to_start) > int(values.starting_ally_ships)
		):
			errors.append("Required Ally Ships cannot exceed the starting inventory: %s." % resource_path)

func _parse_vector2(text: String) -> Dictionary:
	var parts := text.split(",", false)
	if parts.size() != 2:
		return {"ok": false}
	var x_text := parts[0].strip_edges()
	var y_text := parts[1].strip_edges()
	if not x_text.is_valid_float() or not y_text.is_valid_float():
		return {"ok": false}
	return {"ok": true, "value": Vector2(float(x_text), float(y_text))}

func _values_equal(first: Variant, second: Variant, type_name: String) -> bool:
	match type_name:
		"float":
			return is_equal_approx(float(first), float(second))
		"vector2":
			return first is Vector2 and second is Vector2 and first.is_equal_approx(second)
	return first == second

func _cell_as_string(cell: Dictionary) -> String:
	if cell.get("kind", "blank") == "blank":
		return ""
	return String(cell.get("value", "")).strip_edges()

func _row_is_blank(row: Dictionary) -> bool:
	for cell in row.cells.values():
		if cell.get("kind", "blank") != "blank" and not String(cell.get("value", "")).is_empty():
			return false
	return true
