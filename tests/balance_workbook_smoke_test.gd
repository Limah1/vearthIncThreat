extends Node

const BalanceSchemaScript := preload("res://addons/balance_editor/balance_schema.gd")
const XlsxCodecScript := preload("res://addons/balance_editor/xlsx_balance_codec.gd")
const BalanceImportValidatorScript := preload("res://addons/balance_editor/balance_import_validator.gd")

var _failures := 0

func _ready() -> void:
	var schema := BalanceSchemaScript.new()
	var codec := XlsxCodecScript.new()
	var workbook_path := ProjectSettings.globalize_path("user://balance_editor_smoke.xlsx")
	var sheets: Dictionary = schema.build_workbook_sheets()
	_expect(codec.write_workbook(workbook_path, sheets) == OK, "Workbook export must succeed.")
	var result: Dictionary = codec.read_workbook(workbook_path)
	_expect(result.get("ok", false), "Exported workbook must be readable by the codec.")
	if result.get("ok", false):
		for sheet_name in ["Upgrades", "Turrets", "Barriers", "Levels", "Schema"]:
			_expect(result.sheets.has(sheet_name), "Workbook must contain worksheet '%s'." % sheet_name)
		_expect(result.sheets.Upgrades.rows.size() > 0, "Upgrade worksheet must contain balance rows.")
		_expect(result.sheets.Turrets.rows.size() > 0, "Turret worksheet must contain balance rows.")
		_expect(result.sheets.Barriers.rows.size() > 0, "Barrier worksheet must contain balance rows.")
		_expect(result.sheets.Levels.rows.size() > 0, "Levels worksheet must contain balance rows.")
		_test_typed_cells(result.sheets.Upgrades.rows)
		_test_import_validation(result.sheets)
	var external_roundtrip_path := ProjectSettings.globalize_path("user://balance_editor_artifact_roundtrip.xlsx")
	var external_is_current := (
		FileAccess.file_exists(external_roundtrip_path)
		and FileAccess.get_modified_time(external_roundtrip_path) >= FileAccess.get_modified_time(workbook_path)
	)
	if external_is_current:
		var external_result: Dictionary = codec.read_workbook(external_roundtrip_path)
		_expect(external_result.get("ok", false), "Codec must read an XLSX re-saved by a general spreadsheet library.")
		if external_result.get("ok", false):
			var external_validation := BalanceImportValidatorScript.new().validate_workbook(external_result.sheets)
			if not external_validation.ok:
				print("External workbook validation errors: ", external_validation.errors)
			_expect(external_validation.ok, "A re-saved XLSX workbook must pass import validation.")

	if _failures == 0:
		print("Balance workbook smoke tests passed: ", workbook_path)
	else:
		push_error("Balance workbook smoke tests failed: %d" % _failures)
	get_tree().quit(_failures)

func _test_typed_cells(rows: Array) -> void:
	var found_number := false
	var found_bool := false
	for row in rows:
		var type_name := String(row.cells.get("Type", {}).get("value", ""))
		var new_value_kind := String(row.cells.get("New Value", {}).get("kind", "blank"))
		if type_name == "float" and new_value_kind == "number":
			found_number = true
		elif type_name == "bool" and new_value_kind == "bool":
			found_bool = true
	_expect(found_number, "Float upgrade values must round-trip as numeric cells.")
	_expect(found_bool, "Boolean upgrade values must round-trip as Boolean cells.")

func _test_import_validation(parsed_sheets: Dictionary) -> void:
	var validator := BalanceImportValidatorScript.new()
	var valid_result: Dictionary = validator.validate_workbook(parsed_sheets)
	_expect(valid_result.ok, "A freshly exported workbook must pass import validation.")
	_expect(valid_result.changes.is_empty(), "A fresh workbook must not contain changes.")
	var changed_row: Dictionary = {}
	for row in parsed_sheets.Upgrades.rows:
		if String(row.cells.get("Type", {}).get("value", "")) == "float":
			changed_row = row
			break
	_expect(not changed_row.is_empty(), "The workbook must expose at least one editable float value.")
	if changed_row.is_empty():
		return
	var original_value := float(changed_row.cells["New Value"].value)
	changed_row.cells["New Value"] = {"kind": "number", "value": original_value + 0.25}
	var changed_result: Dictionary = validator.validate_workbook(parsed_sheets)
	_expect(changed_result.ok, "A valid numeric balance edit must pass import validation.")
	_expect(changed_result.changes.size() == 1, "A single edited cell must produce exactly one resource change.")
	changed_row.cells["New Value"] = {"kind": "string", "value": "10"}
	var invalid_result: Dictionary = validator.validate_workbook(parsed_sheets)
	_expect(not invalid_result.ok, "Text must be rejected when a numeric cell is required.")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
